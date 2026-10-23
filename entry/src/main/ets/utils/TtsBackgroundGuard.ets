// ============================================================
// ★ 0.304.0：TTS 朗读后台保活守卫（TtsBackgroundGuard）
// ============================================================
// 背景：用户拍板「朗读一定要切后台/熄屏后继续读」。鸿蒙对后台应用掐音频
// （AVSession 管控：未接入 AVSession 的应用检测到后台即强制停播）+进程挂起
// 管控，双管齐下——仅靠前台播报切后台必停。
//
// 官方条款（长时任务/AVSession 文档实锤）：
// ①后台播放音频必须申请 AUDIO_PLAYBACK 长时任务；MUSIC/MOVIE/AUDIOBOOK 流
//   类型（云端 TTS 的 AVPlayer 即是）还必须接入 AVSession，否则退后台被系统
//   静音+冻结；本地 CoreSpeechKit TTS 流不在 AVSession 强制清单，但接入无害
//   且统一（白得播控中心暂停/停止控制）。
// ②一个 UIAbility 旧接口同一时刻仅一个长时任务——AiStreamGuard 已占
//   dataTransfer（AI 流式保活），故本守卫走 API21+ ContinuousTaskRequest
//   多任务新接口，独立 continuousTaskId、独立 stop，互不误伤。
// ③AVSession 一个进程只能存在一个会话对象，重复创建报 6600101——懒创建一次
//   永久复用，朗读会话间只刷 metadata/播放状态。
// ④结束即停：朗读结束/停止立即停长时任务（系统管控红线：业务结束不停任务
//   =退后台被挂起）。
//
// 挂点：ChatPage.startTTS/stopTTS 单点收口（消息朗读会话=playingMessageId
// 非空期间）；单词发音（WordSpeaker）/设置页试听为秒级短播不挂本守卫。
// ============================================================

import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent, common } from '@kit.AbilityKit';
import { avSession } from '@kit.AVSessionKit';
import { cloudTts } from './CloudTtsEngine';
import { qianwenTts } from './QianwenTtsEngine';
import { localTts } from './LocalTtsEngine';

let appContext: common.UIAbilityContext | null = null;
let stopHandler: (() => void) | null = null; // ChatPage 注入（UI 状态收敛+三引擎停）
let generation = 0;                          // 会话代数（防 begin/end 异步交错晚到泄漏）
let continuousTaskId = -1;                   // 本守卫长时任务 id（-1=未持有）
let avSessionObj: avSession.AVSession | null = null; // 全局唯一（懒创建复用防 6600101）
let sessionCreating: Promise<void> | null = null;

// ★ 0.304.0：EntryAbility.onCreate 注入上下文（长时任务/AVSession 需 UIAbilityContext）
export function initTtsGuard(context: common.UIAbilityContext): void {
  appContext = context;
}

// ChatPage 生命周期注入/注销停读回调（播控中心暂停/停止命令 → 停 TTS）；
// 页面销毁注销防悬挂（闭包捕获页面 this=定时炸弹纪律）
export function setTtsStopHandler(fn: (() => void) | null): void {
  stopHandler = fn;
}

// 朗读会话开始：申请 audioPlayback 长时任务 + AVSession 置播放中（幂等——
// 播新停旧由调用方 stopTTS 先走 endTtsPlayback，此处只管开新会话）
export function beginTtsPlayback(title: string): void {
  generation++;
  const gen = generation;
  startTask(gen);
  updateSessionPlaying(gen, title);
}

// 朗读会话结束：停长时任务（指定 id——不误伤 AiStreamGuard 的 dataTransfer）+
// AVSession 置暂停（会话对象保留复用，播控中心卡片驻留为听书类标准形态）
export function endTtsPlayback(): void {
  generation++;
  stopTask();
  updateSessionPaused();
}

// 播控中心命令兜底：优先走 ChatPage.stopTTS（UI 状态+三引擎+本守卫全收敛）；
// 页面已销毁（handler 空）时直停三引擎+收守卫
function handleRemoteStop(): void {
  if (stopHandler !== null) {
    stopHandler();
    return;
  }
  cloudTts.stop();
  qianwenTts.stop();
  localTts.stop();
  endTtsPlayback();
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
    // wantAgent 构建失败：通知不可点，任务照常
  });
}

// 申请 MODE_AUDIO_PLAYBACK 长时任务（API21+ ContinuousTaskRequest 多任务接口，
// 与 AiStreamGuard 旧接口 dataTransfer 任务并存互不干扰）
function startTask(gen: number): void {
  const ctx = appContext;
  if (ctx === null) {
    return;
  }
  buildClickAgent((wa: WantAgent) => {
    if (gen !== generation) {
      return; // 竞态：等待期间会话已结束
    }
    try {
      const modeList: Array<number> = [backgroundTaskManager.BackgroundTaskMode.MODE_AUDIO_PLAYBACK];
      const subModeList: Array<number> = [backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_NORMAL_NOTIFICATION];
      const req = new backgroundTaskManager.ContinuousTaskRequest();
      req.backgroundTaskModes = modeList;
      req.backgroundTaskSubmodes = subModeList;
      req.wantAgent = wa;
      req.combinedTaskNotification = false;
      backgroundTaskManager.startBackgroundRunning(ctx, req).then((res: backgroundTaskManager.ContinuousTaskNotification) => {
        if (gen !== generation) {
          // end 晚到兜底：立即停掉刚申请的任务，杜绝泄漏
          if (res.continuousTaskId !== undefined) {
            backgroundTaskManager.stopBackgroundRunning(ctx, res.continuousTaskId).catch(() => {
            });
          }
          return;
        }
        continuousTaskId = res.continuousTaskId !== undefined ? res.continuousTaskId : -1;
      }).catch(() => {
        // 保活申请失败不阻断朗读（前台不受影响；仅后台续读缺位）
      });
    } catch (e) {
      // 接口异常静默（不影响朗读本体）
    }
  });
}

// 停本守卫的长时任务（按 id 精确停，幂等）
function stopTask(): void {
  const ctx = appContext;
  if (ctx === null || continuousTaskId < 0) {
    return;
  }
  const id = continuousTaskId;
  continuousTaskId = -1;
  backgroundTaskManager.stopBackgroundRunning(ctx, id).catch(() => {
    // 未成功申请时 stop 报错静默
  });
}

// AVSession 懒创建（进程唯一，一次永复用）：注册播控命令（至少一个控制命令
// 播控中心才展示）+激活；创建失败静默——长时任务兜底本地 TTS 流场景
function ensureSession(): Promise<void> {
  if (avSessionObj !== null) {
    return Promise.resolve();
  }
  if (sessionCreating !== null) {
    return sessionCreating;
  }
  const ctx = appContext;
  if (ctx === null) {
    return Promise.resolve();
  }
  sessionCreating = avSession.createAVSession(ctx, 'DagTtsReading', 'audio').then((s: avSession.AVSession) => {
    avSessionObj = s;
    try {
      s.on('pause', () => {
        handleRemoteStop();
      });
      s.on('stop', () => {
        handleRemoteStop();
      });
    } catch (e) {
      // 命令注册失败：播控中心不可控，播放本体不受影响
    }
    return s.activate().catch(() => {
      // 激活失败静默（会话对象仍可尝试复用）
    });
  }).then(() => {
  }).catch(() => {
    sessionCreating = null; // 允许下次重试
    avSessionObj = null;
  });
  return sessionCreating;
}

// 会话播放中：刷元数据（朗读标题）+播放状态 PLAYING
function updateSessionPlaying(gen: number, title: string): void {
  ensureSession().then(() => {
    if (gen !== generation || avSessionObj === null) {
      return; // 竞态：会话已结束/会话不可用
    }
    const meta: avSession.AVMetadata = {
      assetId: 'dag-tts-reading',
      title: title.length > 0 ? title : '朗读中',
      artist: 'DAG AI Chat',
      album: '消息朗读'
    };
    avSessionObj.setAVMetadata(meta).catch(() => {
      // 元数据失败静默（播放不受影响）
    });
    const state: avSession.AVPlaybackState = {
      state: avSession.PlaybackState.PLAYBACK_STATE_PLAY
    };
    avSessionObj.setAVPlaybackState(state).catch(() => {
      // 状态失败静默
    });
  });
}

// 会话暂停态（朗读结束——卡片驻留播控中心，标准听书形态）
function updateSessionPaused(): void {
  if (avSessionObj === null) {
    return;
  }
  const state: avSession.AVPlaybackState = {
    state: avSession.PlaybackState.PLAYBACK_STATE_PAUSE
  };
  avSessionObj.setAVPlaybackState(state).catch(() => {
    // 状态失败静默
  });
}
