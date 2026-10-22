// ============================================================
// ReminderUtil.ets — ★ 0.299.0 每日复习提醒（后台代理提醒预埋）
// ============================================================
// 产品定位：用户当日未完成复习时，每天固定时间由系统代理提醒（app 被
// 杀死/退后台照常触达）——多邻国 streak 同款习惯养成机制；华为官方点名
// 开放场景「学习类提醒（背单词提醒）」，教育类应用合规可申请。
// 技术选型（与华为 AI 客服确认）：reminderAgentManager 周期闹钟
// （ReminderRequestAlarm daysOfWeek 全选=每天响），发布一次长期有效、
// 无需进程存活、单应用仅占 1/30 配额。
// ★ 权益前置（关键）：手机/平板/PC 已管控——须 AGC「项目设置→开放能力
//   管理→代理提醒」申请权益（8 个工作日，教育类+背单词场景通过率高）；
//   通过后必须①勾选能力开关保存②重新生成 Profile+手动签名。获批前
//   publishReminder 报 1700002，本模块全链静默降级（开关可开、无提醒、
//   无报错）——权益到即自动生效，代码零改动。
// 方案取舍（为何周期闹钟而非华为建议的滚动单日日历）：滚动方案在用户
// 连续多日不开 app 时会断档（单日提醒响完即止），违背「天天被提醒逼
// 养成习惯」的产品初衷；周期闹钟永续兜底，「完成当日静默」改为文案
// 双态（完成=正反馈通知「好习惯+1」——多邻国 streak 庆祝通知同款）。
// 文案动态性：待复习数 N 只在进程活着时能算（三个刷新时机见 store 注释）；
// 用户不开 app 词库不变，陈旧 N 仍近似准确（新卡 nextReviewAt=0 恒计入
// due；跨日新到期的卡只低估不高报——「约 N 条」措辞兜底）。
// ============================================================

import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { connectWordBank } from './WordStoreUtil';
import { connectKnowledgeBank } from './KnowledgeStoreUtil';
import { connectReviewReminder, reminderTodayKey } from '../common/ReviewReminderStore';

const REMINDER_PKG = 'com.dagaichat.app';
const REMINDER_ABILITY = 'EntryAbility';
const REMINDER_NOTIFICATION_ID = 1001; // 固定 id：同 id 提醒覆盖展示，不堆叠

// 文案双态：当日已完成=正反馈；未完成=待复习数 N（到期+新卡合并计数）
function buildReminderContent(): string {
  const store = connectReviewReminder();
  const now = Date.now();
  if (store.lastDoneDate === reminderTodayKey(now)) {
    return '今日复习已完成，好习惯 +1，明天继续加油';
  }
  const wb = connectWordBank();
  const kb = connectKnowledgeBank();
  const total = wb.words.length + kb.cards.length;
  if (total === 0) {
    return '打开看看你的记忆库，今天也别忘了学习';
  }
  let due = 0;
  for (let i = 0; i < wb.words.length; i++) {
    if (wb.words[i].nextReviewAt <= now) {
      due += 1;
    }
  }
  for (let i = 0; i < kb.cards.length; i++) {
    if (kb.cards[i].nextReviewAt <= now) {
      due += 1;
    }
  }
  if (due === 0) {
    return '暂无到期记忆，可以来学点新内容';
  }
  return `今天有约 ${due} 条记忆等你复习，花几分钟巩固一下吧`;
}

// 刷新提醒（唯一入口——开关变更/时段变更/完成复习/退后台四时机调用）：
// 先撤旧提醒（改时段/关闭都要清；周期提醒 cancel 即全周期），再按当前
// 偏好发布新周期闹钟。全链静默：1700002（权益未开通）等任何失败绝不
// 阻断主流程、不弹提示——增强能力定位。
export async function refreshReviewReminder(): Promise<void> {
  const store = connectReviewReminder();
  if (store.reminderId >= 0) {
    const oldId = store.reminderId;
    store.reminderId = -1;
    try {
      await reminderAgentManager.cancelReminder(oldId);
    } catch (_e) {
      // 旧提醒可能已被系统清理/用户清除——取消失败继续发布
    }
  }
  if (!store.on) {
    return;
  }
  const alarm: reminderAgentManager.ReminderRequestAlarm = {
    reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
    hour: store.hour,
    minute: store.minute,
    daysOfWeek: [1, 2, 3, 4, 5, 6, 7], // 周一至周日全选=每天提醒（永续）
    title: '复习提醒',
    content: buildReminderContent(),
    wantAgent: { // 点击通知拉起本应用（跳转限制：仅本应用）
      pkgName: REMINDER_PKG,
      abilityName: REMINDER_ABILITY
    },
    notificationId: REMINDER_NOTIFICATION_ID,
    slotType: notificationManager.SlotType.CONTENT_INFORMATION
  };
  try {
    const id: number = await reminderAgentManager.publishReminder(alarm);
    store.reminderId = id;
  } catch (_e) {
    // 1700002=权益未开通/数量超限、1700001=通知未使能——均静默降级，
    // 权益到即自动生效（见文件头注释）
  }
}
