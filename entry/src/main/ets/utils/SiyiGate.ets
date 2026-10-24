// ============================================================
// SiyiGate.ets — SP 云服务门卫（★ 0.313.0 Phase2：账本权威通道升级）
// ============================================================
// 用户拍板（2026-10-22）：一切「消耗 SP」与「增加 SP」的功能（AI 发送/重生成/划词圈注/
//   IAP 充值购买/签到/新用户礼包/未来做题奖励等）必须以「SP 账本与云端对齐」为前提。
// ★ 0.312.0/0.313.0 架构升级（B 方案）：账本真相迁到云函数（sp-admin 的 SpMirror/SpLedger），
//   不再依赖华为云空间行 cfg:siyi-points——云空间只负责内容同步。
// ready 条件（0.313.0 起）：
//   ①华为账号已登录 ②spAuthReady=true（云函数账本通道已连通且本机镜像已对齐）
//   ③非假开启（cloudBlocked）仅保留为云空间内容同步提示标志，**不再参与 SP 扣点闸门**
//   （旧五条件里的 connectCloudSync().enabled / permGranted / rowInitDone 全部退役——
//     系统云空间开关关掉也扣得到云端，正是本架构的目的）
// 红线纪律：CloudSyncUtil 禁改——本件只消费其已导出能力。
// ============================================================

import { AppStorageV2 } from '@kit.ArkUI';
import { isCloudSyncGranted } from './CloudSyncUtil';
import { connectHuaweiAccount } from './HuaweiAccountUtil';
import { connectConfirmDialog } from '../components/AppConfirmDialog';

// 权限缓存（应用级共享、不落盘）——GSD 云同步 Tab 状态卡 0.229.24 根治：
//   permGranted 由本 store 单一真值化，启动/回前台/登录时刷新，任意消费处即时响应
// ★ 0.308.0 cloudBlocked：假开启实锤标志——云函数探针查到「他设备资产痕迹」而本机拉不到
//   SP 行（华为无系统云空间开关检测 API，cloudSync 假开启静默无操作）。★ 0.313.0 起仅用于
//   云空间内容同步提示（礼包/签到的云行落地判定仍用），不再阻断 SP 扣点。
@ObservedV2
export class SiyiGateStore {
  @Trace permGranted: boolean = false; // app 权限异步缓存（isCloudSyncGranted 查询结果）
  @Trace cloudBlocked: boolean = false; // 假开启实锤（会话级，不落盘；内容同步提示用）
  @Trace spAuthReady: boolean = false;  // ★ 0.313.0：云函数账本通道就绪（sp_balance 成功/初始化成功）
  @Trace spAuthErr: string = '';        // ★ 0.313.0：未就绪原因 network / sync / unknown / no-account
}

export function connectSiyiGate(): SiyiGateStore {
  return AppStorageV2.connect(SiyiGateStore, 'siyi-gate',
    () => new SiyiGateStore()) as SiyiGateStore;
}

// ★ 0.313.0：账本通道刷新器（ChatModel 注入——SiyiGate 不 import ChatModel，防环）
let spAuthRefresher: (() => void) | null = null;

export function registerSpAuthRefresher(fn: () => void): void {
  spAuthRefresher = fn;
}

// 门卫就绪判定（同步纯读——全部 @Trace，消费组件自动响应）
export function siyiGateReady(): boolean {
  return connectHuaweiAccount().isLoggedIn
    && connectSiyiGate().spAuthReady;
}

// 阻塞原因（引导弹窗文案/动作分支用）：
//   1=未登录（去登录）
//   2=网络/云服务不可用（去检查网络，重试）
//   3=账本同步中/服务升级中（云端初始化未完成——稍后重试；含旧版函数、账号历史待下行）
export function siyiGateBlockReason(): number {
  if (!connectHuaweiAccount().isLoggedIn) {
    return 1;
  }
  const err = connectSiyiGate().spAuthErr;
  if (err === 'network') {
    return 2;
  }
  return 3;
}

// 权限刷新（启动 onCreate / 回前台 onForeground / 登录回调 / GSD 开弹窗时调用）——
//   ★ 0.313.0 起只服务 GSD 云同步 Tab 展示，不再参与 SP 门卫
export function refreshSiyiGatePerm(): void {
  isCloudSyncGranted().then((granted: boolean) => {
    connectSiyiGate().permGranted = granted;
  });
}

// 统一守卫（requireLoginForCloud 同款模式）：
//   ready → true 放行；未 ready → 弹「云服务连接」引导弹窗（Index 根 Stack 消费）并返回 false
//   ★ 0.313.0：未就绪时顺手催一次账本刷新（用户刚从弱网回来/冷启首点即到）
export function requireSiyiGate(): boolean {
  if (siyiGateReady()) {
    return true;
  }
  refreshSiyiGatePerm(); // 顺手刷新——GSD 云同步状态卡同源
  if (spAuthRefresher !== null) {
    spAuthRefresher();
  }
  connectConfirmDialog().syncGatePromptVisible = true;
  return false;
}
