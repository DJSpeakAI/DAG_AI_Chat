// ============================================================
// SiyiGate.ets — ★ 0.293.0：SP 云同步门卫（账本云端就绪闸门）
// ============================================================
// 用户拍板（2026-10-22）：一切「消耗 SP」与「增加 SP」的功能（AI 发送/重生成/划词圈注/
//   IAP 充值购买/签到/新用户礼包/未来做题奖励等）必须以「SP 账本与云端对齐」为前提——
//   否则未开云同步的设备=本地独立小金库，卸载重装即白嫖 200w，规模化后账本口径必然分裂。
// ready 四条件（全真才开闸）：
//   ①华为账号已登录 ②app 内云同步开关开 ③DISTRIBUTED_DATASYNC 权限 granted
//   ④首拉闸门 rowInitDone（本会话完成一次无缺片下行 reconcile=云端账本已对齐）
// 红线纪律：CloudSyncUtil 禁改——本件只消费其已导出能力；autoSyncProgress 云空间满监听
//   需 rdbStore 实例（未导出），一期不做（记 docs/0.293.0 §五后续人工审批项）。
// ============================================================

import { AppStorageV2 } from '@kit.ArkUI';
import { connectCloudSync, connectCloudSyncArbiter, isCloudSyncGranted } from './CloudSyncUtil';
import { connectHuaweiAccount } from './HuaweiAccountUtil';
import { connectConfirmDialog } from '../components/AppConfirmDialog';

// 权限缓存（应用级共享、不落盘）——GSD 云同步 Tab 状态卡 0.229.24 根治：
// permGranted 由本 store 单一真值化，启动/回前台/登录时刷新，任意消费处即时响应
@ObservedV2
export class SiyiGateStore {
  @Trace permGranted: boolean = false; // app 权限异步缓存（isCloudSyncGranted 查询结果）
}

export function connectSiyiGate(): SiyiGateStore {
  return AppStorageV2.connect(SiyiGateStore, 'siyi-gate',
    () => new SiyiGateStore()) as SiyiGateStore;
}

// 门卫就绪判定（同步纯读四条件——全部 @Trace，消费组件自动响应）
export function siyiGateReady(): boolean {
  return connectHuaweiAccount().isLoggedIn
    && connectCloudSync().enabled
    && connectSiyiGate().permGranted
    && connectCloudSyncArbiter().rowInitDone;
}

// 阻塞原因（引导弹窗文案/动作分支用）：1=未登录 2=app 开关或权限未开 3=云端通路未就绪
//   （3 含：系统设置-云空间-应用数据同步未开 / 网络异常 / 首拉未完成——华为无 API 细分，引导文案覆盖）
export function siyiGateBlockReason(): number {
  if (!connectHuaweiAccount().isLoggedIn) {
    return 1;
  }
  if (!connectCloudSync().enabled || !connectSiyiGate().permGranted) {
    return 2;
  }
  return 3;
}

// 权限刷新（启动 onCreate / 回前台 onForeground / 登录回调 / GSD 开弹窗时调用）
export function refreshSiyiGatePerm(): void {
  isCloudSyncGranted().then((granted: boolean) => {
    connectSiyiGate().permGranted = granted;
  });
}

// 统一守卫（requireLoginForCloud 同款模式）：
//   ready → true 放行；未 ready → 弹「开启云同步」引导弹窗（Index 根 Stack 消费）并返回 false
export function requireSiyiGate(): boolean {
  if (siyiGateReady()) {
    return true;
  }
  refreshSiyiGatePerm(); // 顺手刷新——用户可能刚从系统设置回来，弹窗期间状态即变
  connectConfirmDialog().syncGatePromptVisible = true;
  return false;
}
