// ============================================================
// ★ 0.251.0：AI 流式后台保活守卫（AiStreamGuard）
// ============================================================
// 背景：鸿蒙对后台应用掐网络（0.153/0.206.2 真机实证），AI 长回复/圈注提炼/
// 划词提炼/查词等待 1~4 分钟，用户切后台必断流——0.153 时代「切后台主动 abort」
// 策略 0.251.0 起整体反转：改申请 dataTransfer 长时任务保活续收（用户拍板）。
//
// 挂点设计：ApiClient.streamChat 是全部四条 AI 链的单一咽喉（queryWord/
// queryKnowledge/queryKnowledgeFromImage 内部全部复用 streamChat）——
// acquire/release/touch 全部收口在 streamChat 内部，页面零侵入。
//
// 官方条款（backgroundTaskManager 文档实锤）：
// ①DATA_TRANSFER 进度超 10 分钟未更新 → 长时任务被系统取消（须持续更新进度）；
// ②进度更新通知必须为实况窗（downloadTemplate + typeCode 8 + 任务返回的
//   notificationId 复用），具体见 startBackgroundRunning 官方示例；
// ③长时任务申请/更新不支持提示音——完成"叮咚"由独立本地通知承担（SOCIAL 槽位）。
//
// 看门狗：90 秒无任何数据（chunk/reasoning 均无）判死流 → 主动收尾
// （onError 提示 + 释放任务），防死后台白耗（比 ApiClient 300s readTimeout
// 提前止损；阈值留 30s 余量防深度思考慢启动误杀）。

import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent, common } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';

const PROGRESS_TICK_MS = 3000;   // 进度通知更新周期（3s——远小于 10 分钟官方红线）
const STALL_KILL_MS = 90000;     // 看门狗：90s 无数据判死流
const EXPECT_TOTAL_MS = 150000;  // 预估总时长（进度值映射：elapsed/150s → 0~99）
const DONE_NOTIF_ID = 251000;    // 完成通知固定 id（多次完成互相覆盖不堆叠）

// 活跃请求令牌（每个 streamChat 调用一个；并发多请求各自跟踪、共享一个长时任务）
export interface AiStreamToken {
  scene: string;          // 场景标签（「AI 回复」「AI 提炼」——通知文案用）
  lastDataAt: number;     // 最后一次收到数据时刻（看门狗判据）
  receivedChars: number;  // 累计接收字符数（进度文案用）
  stalled: boolean;       // 已触发看门狗（防重复触发）
  onStall: (() => void) | null; // 死流回调（streamChat 注册：cancel + onError）
}

let appContext: common.UIAbilityContext | null = null;
let appBackground = false;
let enablePromptTried = false;
let generation = 0;                 // 任务代数（防「启动竞态晚到」泄漏：stop 后才 start 成功）
let taskNotificationId = -1;
let progressTimer: number = -1;
let sessionStartAt = 0;
let activeTokens: AiStreamToken[] = [];

// ★ 0.251.0：EntryAbility.onCreate 注入上下文（长时任务/通知都需 UIAbilityContext）
export function initAiStreamGuard(context: common.UIAbilityContext): void {
  appContext = context;
}

// ★ 0.251.0：EntryAbility onForeground/onBackground 维护（完成通知只在后台发，前台有 UI 不打扰）
export function setAiStreamBackground(bg: boolean): void {
  appBackground = bg;
}

// 请求开始：领取令牌；首请求启动长时任务 + 进度定时器
export function acquireAiStream(scene: string): AiStreamToken {
  const token: AiStreamToken = {
    scene: scene,
    lastDataAt: Date.now(),
    receivedChars: 0,
    stalled: false,
    onStall: null
  };
  activeTokens.push(token);
  if (activeTokens.length === 1) {
    startTask();
  }
  return token;
}

// 收到数据（charsDelta 可为 0——纯活性心跳，如 reasoning 分片）
export function touchAiStream(token: AiStreamToken, charsDelta: number): void {
  token.lastDataAt = Date.now();
  token.receivedChars += charsDelta;
}

// 请求终结（完成/出错/用户取消——幂等由调用方 guardDone 保证）：归还令牌；
// 末请求停进度定时器 + 停长时任务（结束即停=过审红线）
export function releaseAiStream(token: AiStreamToken): void {
  const idx = activeTokens.indexOf(token);
  if (idx >= 0) {
    activeTokens.splice(idx, 1);
  }
  if (activeTokens.length === 0) {
    stopTask();
  }
}

function buildClickAgent(cb: (wa: WantAgent) => void): void {
  const ctx = appContext;
  if (ctx === null) {
    return;
  }
  const info: wantAgent.WantAgentInfo = {
    wants: [
      {
        bundleName: ctx.abilityInfo.bundleName,
        abilityName: ctx.abilityInfo.name
      }
    ],
    actionType: wantAgent.OperationType.START_ABILITY,
    requestCode: 0,
    wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
  };
  wantAgent.getWantAgent(info).then((wa: WantAgent) => {
    cb(wa);
  }).catch(() => {
    // wantAgent 构建失败：点击通知不跳转，任务照常
  });
}

function startTask(): void {
  sessionStartAt = Date.now();
  maybeRequestNotificationEnable();
  const ctx = appContext;
  if (ctx === null) {
    return;
  }
  const gen = generation;
  buildClickAgent((wa: WantAgent) => {
    if (gen !== generation) {
      return; // 竞态：等待期间任务已被 stop（如请求秒败）——不再启动
    }
    backgroundTaskManager.startBackgroundRunning(ctx, ['dataTransfer'], wa).then((res: backgroundTaskManager.ContinuousTaskNotification) => {
      if (gen !== generation) {
        // stop 晚到兜底：立即停掉刚启动的任务，杜绝泄漏挂起
        backgroundTaskManager.stopBackgroundRunning(ctx).catch(() => {
        });
        return;
      }
      taskNotificationId = res.notificationId;
    }).catch(() => {
      // 保活申请失败不阻断请求（前台不受影响；系统通知缺位仅损失后台进度展示）
    });
  });
  if (progressTimer >= 0) {
    clearInterval(progressTimer);
  }
  progressTimer = setInterval(progressTick, PROGRESS_TICK_MS);
}

function stopTask(): void {
  generation++;
  taskNotificationId = -1;
  if (progressTimer >= 0) {
    clearInterval(progressTimer);
    progressTimer = -1;
  }
  const ctx = appContext;
  if (ctx !== null) {
    backgroundTaskManager.stopBackgroundRunning(ctx).catch(() => {
      // 未启动成功时 stop 报错静默
    });
  }
}

// 进度心跳（3s 一跳）：①更新实况窗进度（官方 10 分钟红线）②看门狗巡检死流
function progressTick(): void {
  const now = Date.now();
  // 看门狗：90s 无数据且未触发过的令牌 → 死流收尾
  for (let i = 0; i < activeTokens.length; i++) {
    const t = activeTokens[i];
    if (!t.stalled && now - t.lastDataAt > STALL_KILL_MS) {
      t.stalled = true;
      if (t.onStall !== null) {
        t.onStall();
      }
    }
  }
  publishProgress(now);
}

// 实况窗进度通知（官方模板：downloadTemplate + typeCode 8 + 任务返回 id 复用）
function publishProgress(now: number): void {
  if (taskNotificationId < 0 || appContext === null || activeTokens.length === 0) {
    return;
  }
  const elapsed = now - sessionStartAt;
  const progressValue = Math.min(99, Math.floor((elapsed / EXPECT_TOTAL_MS) * 100));
  let chars = 0;
  let scene = activeTokens[0].scene;
  for (let i = 0; i < activeTokens.length; i++) {
    chars += activeTokens[i].receivedChars;
  }
  const text = chars > 0 ? `已接收 ${chars} 字` : `已等待 ${Math.floor(elapsed / 1000)} 秒`;
  const tpl: notificationManager.NotificationTemplate = {
    name: 'downloadTemplate',
    data: {
      title: `${scene}中`,
      fileName: 'DAG AI Chat',
      progressValue: progressValue
    }
  };
  const req: notificationManager.NotificationRequest = {
    id: taskNotificationId,
    notificationSlotType: notificationManager.SlotType.LIVE_VIEW,
    template: tpl,
    content: {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
      systemLiveView: {
        typeCode: 8,
        title: `${scene}中`,
        text: text
      }
    }
  };
  notificationManager.publish(req).catch(() => {
    // 未授权/系统限制：进度通知缺位不影响传输本体
  });
}

// 完成提醒（独立本地通知，SOCIAL 槽位带提示音——长时任务通知本身无提示音）；
// 仅应用在后台时发（前台有 UI 可见，不打扰）；点击拉回应用
export function notifyAiStreamTerminal(ok: boolean, scene: string): void {
  if (!appBackground || appContext === null) {
    return;
  }
  const title = ok ? `${scene}已完成` : `${scene}已中断`;
  const text = ok ? '点击回到应用查看' : '点击回到应用查看详情';
  buildClickAgent((wa: WantAgent) => {
    const req: notificationManager.NotificationRequest = {
      id: DONE_NOTIF_ID,
      notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: title,
          text: text
        }
      },
      wantAgent: wa
    };
    notificationManager.publish(req).catch(() => {
      // 通知被拒/失败静默（内容已落盘，回应用一定看得到）
    });
  });
}

// 通知授权（用户拍板时机：第一次发起 AI 请求时场景化申请，不一打开就弹；
// 首次弹一次，拒绝后非首次调用直接返回不再弹——官方 FAQ 机制）
function maybeRequestNotificationEnable(): void {
  if (enablePromptTried) {
    return;
  }
  enablePromptTried = true;
  try {
    notificationManager.requestEnableNotification().catch(() => {
      // 拒绝/失败：降级为无"叮咚"（内容照常落盘），不再骚扰
    });
  } catch (e) {
    // 接口异常静默
  }
}
