// ============================================================
// ContinueBridge.ets — ★ 0.307.0：应用接续（Continuation）桥
// ============================================================
// 场景（用户口述）：手机对话到一半（含输入框草稿打到一半）→ 系统接续到 PC，
//   直接落同一气泡对话页并回填草稿——免「打开 app→找对话框」两步。
// 官方机制（bpta-continue-cast）：源端 onContinue(wantParam) 存数据（<100KB）→
//   系统迁移 → 目标端 onCreate/onNewWant(launchReason=CONTINUATION) 恢复；
//   对话数据本体走云同步，接续只传「指针+草稿」双保险：
//   ①wantParam 直达（秒到）②bubble.draftText 随树云同步（兜底，可能滞后数秒）。
// 数据流：
//   源端实时态（inChat/nodeId/draft）← ChatPage 实时写（saveDraft 每键顺带）
//   → EntryAbility.onContinue 读出塞进 wantParam → 目标端 onCreate/onNewWant
//   写 pending* → Index 直达 BBTreeCanvas → consumeContinuePayload（幂等，
//   aboutToAppear+onShown 双保险）→ 交棒三连进 ChatPage → 草稿回填+清 pending。
// AppStorageV2 应用级共享、不落盘（接续是瞬时动作，重启残留即脏数据）。
// ============================================================

import { AppStorageV2 } from '@kit.ArkUI';

@ObservedV2
export class ContinueBridgeStore {
  // ── 源端实时态（EntryAbility.onContinue 读）──
  @Trace inChat: boolean = false;   // 当前是否在对话页（ChatPage aboutToAppear true / aboutToDisappear false）
  @Trace nodeId: string = '';       // 对话页当前气泡 ID（ChatPage 打开时写）
  @Trace draft: string = '';        // 输入框实时草稿（saveDraft 每键顺带同步——onChange 已实时调）

  // ── 目标端待恢复（onCreate/onNewWant 写，消费方一次性清空）──
  @Trace pendingNodeId: string = '';   // BBTreeCanvas 消费（导航目标气泡；清空=导航已消费/无接续）
  @Trace pendingDraftFor: string = ''; // 草稿宿主气泡 ID（ChatPage 匹配判定；防误回填他气泡）
  @Trace pendingDraft: string = '';    // 源端最后一刻草稿（新鲜度 ≥ 云端 draftText，匹配即覆盖回填）
}

// 连接应用级单例（key 'continue-bridge'——AppStorageV2 生命周期共享、非持久化）
export function connectContinueBridge(): ContinueBridgeStore {
  return AppStorageV2.connect(ContinueBridgeStore, 'continue-bridge',
    () => new ContinueBridgeStore()) as ContinueBridgeStore;
}
