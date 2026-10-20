// ============================================================
// DailyReviewCountStore.ets — ★ 0.274.0 每日复习条目数全局单通道
// ============================================================
// 每日复习量（复习页右上角 ⚙ 设置；10 默认 / 20 / 自定义 1~500，0.202.0）。
// 独立中性文件（原居 ReviewPage——★ 0.274.0 桌面卡片切库自愈需 WidgetHostBridge
// 读取，反向 import 组件文件会成环，照 0.224.0 FaceModeStore 外提同款纪律）。
// key 沿用 'daily-review-count-v1'（禁改铁律——类外提不影响 PersistenceV2 按 key 存取）。
// ============================================================

import { PersistenceV2 } from '@kit.ArkUI';

// ★ 0.202.0：每日复习条目数（复习页右上角 ⚙ 设置；10 默认 / 20 / 自定义 1~500）
@ObservedV2
export class DailyReviewCountStore {
  @Trace wordCount: number = 10;      // 单词库每日复习条目
  @Trace knowledgeCount: number = 10; // 知识库每日复习条目
}

export function connectDailyReviewCount(): DailyReviewCountStore {
  return PersistenceV2.connect(DailyReviewCountStore, 'daily-review-count-v1', () => new DailyReviewCountStore()) as DailyReviewCountStore;
}
