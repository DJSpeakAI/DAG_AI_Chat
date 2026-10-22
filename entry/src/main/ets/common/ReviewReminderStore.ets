// ============================================================
// ReviewReminderStore.ets — ★ 0.299.0 每日复习提醒偏好（全局单通道）
// ============================================================
// key 'review-reminder-v1'（新 key——待补录 config.autofix.redlineKeys）。
// 外提件纪律照 DailyReviewCountStore（0.274.0）：独立中性文件防反向成环。
// 字段：
//   on          提醒总开关（默认关——AGC 代理提醒权益生效后用户自开；
//               未获批时 publishReminder 报 1700002 全链静默降级）
//   hour/minute 提醒时刻（默认 20:00；ReviewPage ⚙ 四档段选 19~22 点）
//   reminderId  最近发布的系统代理提醒 id（cancel 用；-1=未发布——
//               PersistenceV2 持久化，重启后仍可取消旧提醒防孤儿）
//   lastDoneDate 当日复习完成标记（yyyy-m-d，与 ReviewPage.todayKey 同格式
//               不垫零）——提醒文案双态判据：命中=正反馈文案；跨日自然失效
// 文案刷新三时机：开关/时段变更（⚙）、完成复习（ReviewPage 完成页）、
// 退后台（EntryAbility.onBackground）——进程活着才能算待复习数 N。
// ============================================================

import { PersistenceV2 } from '@kit.ArkUI';

@ObservedV2
export class ReviewReminderStore {
  @Trace on: boolean = false;        // 提醒总开关（默认关）
  @Trace hour: number = 20;          // 提醒时刻·时（默认 20:00）
  @Trace minute: number = 0;         // 提醒时刻·分
  @Trace reminderId: number = -1;    // 当前系统代理提醒 id（-1=未发布）
  @Trace lastDoneDate: string = '';  // 当日复习完成日（yyyy-m-d，todayKey 格式）
}

export function connectReviewReminder(): ReviewReminderStore {
  return PersistenceV2.connect(ReviewReminderStore, 'review-reminder-v1', () => new ReviewReminderStore()) as ReviewReminderStore;
}

// 当日 key（本地时区 yyyy-m-d 不垫零——必须与 ReviewPage.todayKey 字节级一致，
// 否则 lastDoneDate 判据失效；独立导出供 ReminderUtil 消费）
export function reminderTodayKey(now: number): string {
  const d = new Date(now);
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}
