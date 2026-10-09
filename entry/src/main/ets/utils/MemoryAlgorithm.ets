// ============================================================
// MemoryAlgorithm.ets — ★ 0.187.0 记忆算法（简化遗忘曲线 · 方案B）
// ============================================================
// 核心公式：R = e^(-t/S)
//   R = 记忆保留率（0~1，越低遗忘越多）；t = 距上次复习的天数（浮点）；
//   S = 记忆强度（天），每次评分更新。
//
// 方案B（用户拍板）：下次复习 = 现在 + S。复习时保留率 ≈ 37%，属
//   简化工程模型——不锁定目标保留率，信 3 档评分自纠错（觉得难就点
//   「生疏」，间隔自动缩短）。未来开放设置时可加 k 系数（间隔=k×S）。
//
// 单位约定（防单位 BUG，豆包审查采纳）：strength 与全部间隔常量统一
//   用「天」（浮点）。10 分钟 = 10/(24*60) ≈ 0.00694 天；6 小时 = 0.25
//   天；12 小时 = 0.5 天。展示层再转中文标签。
//
// 展示即复习（DAG 特色，区别于 Anki 必须点击）：
//   抽进复习区且真到期（now ≥ nextReviewAt）→ reviewCount++ + 顺延 6h；
//   未到期被重复抽到（重启重抽/历史刷新）→ 不计数不顺延。
//   「到期闸门」即天然防抖——替代固定 24h 防抖（24h 会把词卡在到期
//   态、霸占复习位长达 18 小时，轮转卡死）。
//
// 完整设计文档：docs/0.165+/0.187.0 记忆算法与复习系统.md
// ============================================================

import { WordItem, WordBankStore } from '../common/WordModel';
import { KnowledgeCard, KnowledgeBankStore, AttentionStore, connectAttention, getTagHeat, isAttentionHot } from '../common/KnowledgeModel';

const DAY_MS = 24 * 60 * 60 * 1000;

// ★ 0.188.0：记忆算法作用对象——WordItem / KnowledgeCard 联合类型（两库复刻共用同一套核心函数）
export type MemoryItem = WordItem | KnowledgeCard;

// ---- 可调参数（未来开放给用户设置时的候选旋钮，见 0.187.0 文档 §6）----
export const S_MIN_DAYS: number = 10 / (24 * 60);   // S 下限：10 分钟（生疏减半的底线）
export const S_MAX_DAYS: number = 365;              // S 上限：一年（长期词不再高频打扰）
export const PASSIVE_INTERVAL_DAYS: number = 0.25;  // 不点评顺延：固定 6 小时（不套 S——防看一眼强词顺延一年）
// 首评绝对间隔（天）：生疏 10 分钟 / 尚可 12 小时 / 熟知 2 天
const FIRST_HARD: number = 10 / (24 * 60);
const FIRST_GOOD: number = 0.5;
const FIRST_EASY: number = 2;
// 复评系数：生疏 ×0.5 / 尚可 ×1.6 / 熟知 ×2.4（SM-2 合理区间，暂不调）
const MULT_HARD: number = 0.5;
const MULT_GOOD: number = 1.6;
const MULT_EASY: number = 2.4;
// ★ 0.202.0 提前背惩罚（艾宾浩斯 2.0 第一批，用户拍板两层）：
//   层1 强度增长打折——没经过遗忘考验的记忆不配全额涨强度，factor=实际间隔/应有间隔，下限 15%（"大幅下降"）
//   层2 排期散开保底——提前背的卡下次排期 ≥ 原排期+1 天（提前背不可能让卡更早回来，"永远滚明天"数学上不可能）
export const EARLY_GROWTH_FLOOR: number = 0.15;
export const EARLY_MIN_PUSH_DAYS: number = 1;

// 3 档评分（用户不可见的内部枚举；UI 文案：生疏/尚可/熟知）
export type MemoryRating = 'hard' | 'good' | 'easy';

// 保留率 R = e^(-t/S)。新词（S≤0 或从未展示）返回 0（最紧急）；
// S 异常一律按 0 处理，杜绝除零。★ 0.188.0：参数泛化为 MemoryItem（两库共用）
export function retention(w: MemoryItem, now: number): number {
  if (w.strength <= 0 || w.lastReviewAt <= 0) {
    return 0;
  }
  const t = (now - w.lastReviewAt) / DAY_MS;
  return Math.exp(-t / w.strength);
}

// 展示即复习：真到期才算一次。返回是否计数。
// 未到期（重启重抽/历史刷新重复抽到）→ 不计数、不顺延（到期闸门防抖）。
// S 保持不变——被动浏览不涨强度，只把下次复习固定顺延 6 小时。
export function applyPassiveReview(w: MemoryItem, now: number): boolean {
  if (now < w.nextReviewAt) {
    return false;
  }
  w.reviewCount += 1;
  w.lastReviewAt = now;
  w.nextReviewAt = now + PASSIVE_INTERVAL_DAYS * DAY_MS;
  return true;
}

// 评分更新：首评（S=0，从未评分）用绝对间隔；复评乘系数并钳制到
// [S_MIN, S_MAX]。下次复习 = 现在 + S（方案B）。
// ★ 0.202.0 提前背惩罚：good/easy 增长按「实际间隔/应有间隔」打折（下限 15%）；
//   提前背（now < 原排期）时排期保底 = 原排期+1 天。hard 全额缩短不折（真忘了就该赶紧回来）。
//   到期背（now ≥ 原排期）行为与 0.187.0 完全一致（零回归）。
// reviewCount 已在展示时计过，此处不重复计。
export function applyRating(w: MemoryItem, rating: MemoryRating, now: number): void {
  if (w.strength <= 0) {
    w.strength = rating === 'hard' ? FIRST_HARD : (rating === 'good' ? FIRST_GOOD : FIRST_EASY);
  } else {
    const mult = rating === 'hard' ? MULT_HARD : (rating === 'good' ? MULT_GOOD : MULT_EASY);
    if (rating === 'hard') {
      w.strength = Math.min(Math.max(w.strength * mult, S_MIN_DAYS), S_MAX_DAYS);
    } else {
      // 层1：增长打折——记忆��过多少比例的考验，强度就涨多少
      const elapsedDays = (now - w.lastReviewAt) / DAY_MS;
      const factor = Math.min(Math.max(elapsedDays / w.strength, EARLY_GROWTH_FLOOR), 1);
      w.strength = Math.min(Math.max(w.strength * (1 + (mult - 1) * factor), S_MIN_DAYS), S_MAX_DAYS);
    }
  }
  w.lastReviewAt = now;
  let next = now + w.strength * DAY_MS;
  // 层2：提前背的排期散开保底（仅 now < 原排期时生效——到期背零影响）
  if (rating !== 'hard' && now < w.nextReviewAt &&
    next < w.nextReviewAt + EARLY_MIN_PUSH_DAYS * DAY_MS) {
    next = w.nextReviewAt + EARLY_MIN_PUSH_DAYS * DAY_MS;
  }
  w.nextReviewAt = next;
}

// ★ 0.196.0：评分按钮时间预览——不落盘，只算「这档评完会隔多久再复习」（天）。
// 与 applyRating 同一套首评绝对间隔/复评系数/钳制逻辑，改参数时两处同步。
// ★ 0.202.0：同步提前背惩罚（含层1打折+层2排期保底）——提前背时按钮显示的间隔即真实落盘间隔。
export function previewIntervalDays(w: MemoryItem, rating: MemoryRating): number {
  const now = Date.now();
  if (w.strength <= 0) {
    return rating === 'hard' ? FIRST_HARD : (rating === 'good' ? FIRST_GOOD : FIRST_EASY);
  }
  const mult = rating === 'hard' ? MULT_HARD : (rating === 'good' ? MULT_GOOD : MULT_EASY);
  let s: number;
  if (rating === 'hard') {
    s = Math.min(Math.max(w.strength * mult, S_MIN_DAYS), S_MAX_DAYS);
  } else {
    const elapsedDays = (now - w.lastReviewAt) / DAY_MS;
    const factor = Math.min(Math.max(elapsedDays / w.strength, EARLY_GROWTH_FLOOR), 1);
    s = Math.min(Math.max(w.strength * (1 + (mult - 1) * factor), S_MIN_DAYS), S_MAX_DAYS);
  }
  let interval = s;
  if (rating !== 'hard' && now < w.nextReviewAt) {
    const floorDays = (w.nextReviewAt + EARLY_MIN_PUSH_DAYS * DAY_MS - now) / DAY_MS;
    if (floorDays > interval) {
      interval = floorDays;
    }
  }
  return interval;
}

// ★ 0.196.0：间隔天数 → 中文短标签（评分按钮小字用；区别于 formatNextReviewLabel 的时间戳标签）。
// <1 小时「N 分钟」/ <1 天「N 小时」/ ≤30 天「N 天」/ 更长「N 个月」。UI 侧自行加「后」。
export function formatIntervalDays(days: number): string {
  const ms = days * DAY_MS;
  if (ms < 3600000) {
    return `${Math.max(1, Math.ceil(ms / 60000))} 分钟`;
  }
  if (ms < DAY_MS) {
    return `${Math.ceil(ms / 3600000)} 小时`;
  }
  if (days <= 30) {
    return `${Math.ceil(days)} 天`;
  }
  return `${Math.max(1, Math.round(days / 30))} 个月`;
}

// 选词（替换纯随机——量大后随机不靠谱，用户拍板）：
//   ① 到期老词（reviewCount>0 且 nextReviewAt≤now）按 R 升序——遗忘风险最高优先
//   ② 不够补新词（reviewCount=0）按加入时间升序——公平轮转
//   ③ 再不够补未来词按 nextReviewAt 升序——最快到期优先
export function pickReviewWords(store: WordBankStore, count: number, now: number): WordItem[] {
  const due: WordItem[] = [];
  const fresh: WordItem[] = [];
  const future: WordItem[] = [];
  for (let i = 0; i < store.words.length; i++) {
    const w = store.words[i];
    if (w.reviewCount === 0) {
      fresh.push(w);
    } else if (w.nextReviewAt <= now) {
      due.push(w);
    } else {
      future.push(w);
    }
  }
  due.sort((a: WordItem, b: WordItem) => retention(a, now) - retention(b, now));
  fresh.sort((a: WordItem, b: WordItem) => a.createTime - b.createTime);
  future.sort((a: WordItem, b: WordItem) => a.nextReviewAt - b.nextReviewAt);
  return [...due, ...fresh, ...future].slice(0, count);
}

// ★ 0.188.0：知识卡选词（与 pickReviewWords 同构，新卡按 createdAt 升序）——
// 到期卡按 R 升序 → 新卡 → 未来卡，替换纯随机。
// ★ 0.202.0：注意力提权——命中热标签且 S<30 天的卡在各自段内排最前
//   （「注意力在哪记忆曲线就变在哪」：问"幺半群"→ 抽象代数域的卡优先浮上来；很熟的卡不打扰）。
//   heat 内部自取（调用方零改动）；排序键 = (提权降序, 原排序键)。
export function pickReviewCards(store: KnowledgeBankStore, count: number, now: number): KnowledgeCard[] {
  const heat = getTagHeat(connectAttention() as AttentionStore);
  const due: KnowledgeCard[] = [];
  const fresh: KnowledgeCard[] = [];
  const future: KnowledgeCard[] = [];
  for (let i = 0; i < store.cards.length; i++) {
    const c = store.cards[i];
    if (c.reviewCount === 0) {
      fresh.push(c);
    } else if (c.nextReviewAt <= now) {
      due.push(c);
    } else {
      future.push(c);
    }
  }
  due.sort((a: KnowledgeCard, b: KnowledgeCard) => {
    const ha = isAttentionHot(a, heat) ? 1 : 0;
    const hb = isAttentionHot(b, heat) ? 1 : 0;
    return ha !== hb ? hb - ha : retention(a, now) - retention(b, now);
  });
  fresh.sort((a: KnowledgeCard, b: KnowledgeCard) => {
    const ha = isAttentionHot(a, heat) ? 1 : 0;
    const hb = isAttentionHot(b, heat) ? 1 : 0;
    return ha !== hb ? hb - ha : a.createdAt - b.createdAt;
  });
  future.sort((a: KnowledgeCard, b: KnowledgeCard) => {
    const ha = isAttentionHot(a, heat) ? 1 : 0;
    const hb = isAttentionHot(b, heat) ? 1 : 0;
    return ha !== hb ? hb - ha : a.nextReviewAt - b.nextReviewAt;
  });
  return [...due, ...fresh, ...future].slice(0, count);
}

// 下次复习时间的中文短标签（复习区结果行与单词本列表共用）。
// 已到期 / N 分钟后 / N 小时后 / N 天后 / 超 30 天显示日期。
export function formatNextReviewLabel(nextReviewAt: number, now: number): string {
  const diff = nextReviewAt - now;
  if (diff <= 0) {
    return '已到期';
  }
  if (diff < 3600000) {
    return `${Math.max(1, Math.ceil(diff / 60000))} 分钟后`;
  }
  if (diff < DAY_MS) {
    return `${Math.ceil(diff / 3600000)} 小时后`;
  }
  if (diff <= 30 * DAY_MS) {
    return `${Math.ceil(diff / DAY_MS)} 天后`;
  }
  const d = new Date(nextReviewAt);
  return `${d.getMonth() + 1} 月 ${d.getDate()} 日`;
}
