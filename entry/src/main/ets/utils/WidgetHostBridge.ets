// ============================================================
// WidgetHostBridge.ets — ★ 0.204.0 桌面卡片主应用侧桥
// ============================================================
// 职责（只在主应用进程调用——会 connect/操作 PersistenceV2 store 数据）：
//   ① buildWidgetState：双队列快照构建+写盘+推送（与 ReviewPage.buildQueue 同算法）
//   ② mergeWidgetPending：卡片上产生的评分回放到真数据（按 happenedAt 顺序）
// 卡片进程禁止 import 本文件（防 PersistenceV2 跨进程写冲突）。
// ============================================================

import { WordItem, WordBankStore } from '../common/WordModel';
import { KnowledgeCard, KnowledgeBankStore } from '../common/KnowledgeModel';
import { pickReviewWords, pickReviewCards, applyRating, MemoryRating } from './MemoryAlgorithm';
import { connectWordBank } from './WordStoreUtil';
import { connectKnowledgeBank } from './KnowledgeStoreUtil';
import { WidgetCardItem, WidgetQueue, WidgetState, writeWidgetStateForHost, readWidgetPending, clearWidgetPending, readWidgetState, pushWidgetState, ensureWidgetFormIds } from './WidgetReviewUtil';
import { track } from './TrackUtil'; // 0.206.0 埋点

const DEF_MAX = 200; // 释义截断长度（防爆 preferences 快照）

function wordToItem(w: WordItem): WidgetCardItem {
  return {
    id: w.id,
    title: w.word,
    definition: w.explain.substring(0, DEF_MAX),
    strength: w.strength,
    reviewCount: w.reviewCount,
    lastReviewAt: w.lastReviewAt,
    nextReviewAt: w.nextReviewAt
  };
}

function cardToItem(c: KnowledgeCard): WidgetCardItem {
  return {
    id: c.id,
    title: c.title,
    definition: c.definition.substring(0, DEF_MAX),
    strength: c.strength,
    reviewCount: c.reviewCount,
    lastReviewAt: c.lastReviewAt,
    nextReviewAt: c.nextReviewAt
  };
}

/** 构建双队列快照（与 ReviewPage.buildQueue 完全同算法：到期+新词，按每日量截断） */
export function buildWidgetState(context: Context, mode: string,
  wordBank: WordBankStore, knowledgeBank: KnowledgeBankStore,
  dailyWord: number, dailyKlg: number): void {
  const now = Date.now();
  // 单词队列
  const wAll = pickReviewWords(wordBank, wordBank.words.length, now);
  const wPicked = wAll.filter((w: WordItem): boolean => w.reviewCount === 0 || w.nextReviewAt <= now).slice(0, dailyWord);
  const wq: WidgetQueue = { items: [], idx: 0, done: false, hard: 0, good: 0, easy: 0 };
  wPicked.forEach((w: WordItem) => wq.items.push(wordToItem(w)));
  if (wq.items.length === 0) {
    wq.done = true;
  }
  // 知识卡队列
  const kAll = pickReviewCards(knowledgeBank, knowledgeBank.cards.length, now);
  const kPicked = kAll.filter((c: KnowledgeCard): boolean => c.reviewCount === 0 || c.nextReviewAt <= now).slice(0, dailyKlg);
  const kq: WidgetQueue = { items: [], idx: 0, done: false, hard: 0, good: 0, easy: 0 };
  kPicked.forEach((c: KnowledgeCard) => kq.items.push(cardToItem(c)));
  if (kq.items.length === 0) {
    kq.done = true;
  }

  const s: WidgetState = { mode: mode === 'word' ? 'word' : 'knowledge', word: wq, knowledge: kq };
  writeWidgetStateForHost(context, s);
}

/**
 * 回放卡片上产生的评分到 PersistenceV2 真数据。
 * 返回 true=有合并（调用方应随后重建快照）。
 * 已知边界（第一版接受，注释标注）：主应用前台复习中若同时在卡片评分，
 * 重建快照会以主应用数据为准——两处并发场景概率极低。
 */
export function mergeWidgetPending(context: Context,
  wordBank: WordBankStore, knowledgeBank: KnowledgeBankStore): boolean {
  const pending = readWidgetPending(context);
  if (pending.length === 0) {
    return false;
  }
  pending.forEach((p) => {
    if (p.mode === 'word') {
      const w = wordBank.words.find((x: WordItem): boolean => x.id === p.id);
      if (w !== undefined) {
        applyRating(w, p.rating as MemoryRating, p.happenedAt); // 用卡片评分时刻的时间戳——间隔排期精确
      }
    } else {
      const c = knowledgeBank.cards.find((x: KnowledgeCard): boolean => x.id === p.id);
      if (c !== undefined) {
        applyRating(c, p.rating as MemoryRating, p.happenedAt);
      }
    }
  });
  clearWidgetPending(context);
  return true;
}

// ---------------- ★ 0.204.1：卡片 call 通道处理（EntryAbility 分发；真数据即时落盘） ----------------
// message 通道 msg 被桌面 IPC 剥空（A/B 组实验证实）→ 切 call：卡片 postCardAction call
// 后台拉起 EntryAbility（不显示 UI）→ 此处直接操作 PersistenceV2 真数据 → updateForm 推回卡片。
// 评分即时落真数据（无 pending），单写者=主应用进程，数据一致性天然成立。

/** 卡片评分：真数据 applyRating + 快照 idx 推进 + 推送刷新 */
export function handleWidgetRate(context: Context, rating: string): void {
  ensureWidgetFormIds(context); // 0.204.3：formId 自愈（卸载重装后 form_ids 空→卡片收不到推送）
 const _tp1: Record<string, string> = {}; _tp1['rating'] = rating;
  track(context, 'widget_rate', _tp1); // 0.206.0 埋点：桌面卡片评分
  const s = readWidgetState(context);
  const q = s.mode === 'word' ? s.word : s.knowledge;
  console.info(`[WGT] callRate mode=${s.mode} idx=${q.idx}/${q.items.length} done=${q.done} rating=${rating}`);
  if (q.done || q.idx >= q.items.length) {
    pushWidgetState(context); // 已完成态重推一次
    return;
  }
  const it = q.items[q.idx];
  const now = Date.now();
  // 真数据评分（PersistenceV2 直改——主应用进程内安全）
  if (s.mode === 'word') {
    const w = connectWordBank().words.find((x: WordItem): boolean => x.id === it.id);
    if (w !== undefined) {
      applyRating(w, rating as MemoryRating, now);
    }
  } else {
    const c = connectKnowledgeBank().cards.find((x: KnowledgeCard): boolean => x.id === it.id);
    if (c !== undefined) {
      applyRating(c, rating as MemoryRating, now);
    }
  }
  // 快照会话进度推进（idx/计数/done——items 记忆字段不推，真数据已落）
  if (rating === 'hard') {
    q.hard += 1;
  } else if (rating === 'good') {
    q.good += 1;
  } else {
    q.easy += 1;
  }
  q.idx += 1;
  if (q.idx >= q.items.length) {
    q.done = true;
  }
  writeWidgetStateForHost(context, s);
}

/** 卡片切库：快照 mode 切换 + 推送刷新 */
export function handleWidgetSwitch(context: Context, mode: string): void {
  if (mode !== 'word' && mode !== 'knowledge') {
    return;
  }
  ensureWidgetFormIds(context); // 0.204.3：formId 自愈
 const _tp2: Record<string, string> = {}; _tp2['mode'] = mode;
  track(context, 'widget_switch', _tp2); // 0.206.0 埋点：桌面卡片切库
  const s = readWidgetState(context);
  s.mode = mode;
  writeWidgetStateForHost(context, s);
}

/**
 * ★ 0.204.2：卡片「继续复习」——把未来排期的内容提前背（与 ReviewPage.continueReview 同逻辑）：
 * ①未来队列（reviewCount>0 且 nextReviewAt>now，pick 已按最近到期升序）②空则回退当日队列
 * ③仍空 → noMore='y'（卡片显示「全部学完」无按钮态；主应用重建快照时重置）。
 */
export function handleWidgetContinue(context: Context): void {
  ensureWidgetFormIds(context); // 0.204.3：formId 自愈
  track(context, 'widget_continue'); // 0.206.0 埋点：桌面卡片继续复习
  const s = readWidgetState(context);
  const now = Date.now();
  const items: WidgetCardItem[] = [];
  if (s.mode === 'word') {
    const wb = connectWordBank();
    const all = pickReviewWords(wb, wb.words.length, now);
    const future = all.filter((w: WordItem): boolean => w.reviewCount > 0 && w.nextReviewAt > now);
    console.info(`[WGT] continue word: total=${wb.words.length} future=${future.length}`);
    if (future.length === 0) {
      const daily = all.filter((w: WordItem): boolean => w.reviewCount === 0 || w.nextReviewAt <= now).slice(0, 30);
      console.info(`[WGT] continue word fallback daily=${daily.length}`);
      daily.forEach((w: WordItem) => items.push(wordToItem(w)));
    } else {
      future.slice(0, 30).forEach((w: WordItem) => items.push(wordToItem(w)));
    }
  } else {
    const kb = connectKnowledgeBank();
    const all = pickReviewCards(kb, kb.cards.length, now);
    const future = all.filter((c: KnowledgeCard): boolean => c.reviewCount > 0 && c.nextReviewAt > now);
    console.info(`[WGT] continue klg: total=${kb.cards.length} future=${future.length}`);
    if (future.length === 0) {
      const daily = all.filter((c: KnowledgeCard): boolean => c.reviewCount === 0 || c.nextReviewAt <= now).slice(0, 30);
      console.info(`[WGT] continue klg fallback daily=${daily.length}`);
      daily.forEach((c: KnowledgeCard) => items.push(cardToItem(c)));
    } else {
      future.slice(0, 30).forEach((c: KnowledgeCard) => items.push(cardToItem(c)));
    }
  }
  if (items.length === 0) {
    s.noMore = 'y'; // 全库学完（连未来都没有）——完成态隐藏继续按钮
    writeWidgetStateForHost(context, s);
    return;
  }
  const q = s.mode === 'word' ? s.word : s.knowledge;
  q.items = items;
  q.idx = 0;
  q.done = false;
  q.hard = 0;
  q.good = 0;
  q.easy = 0;
  s.noMore = 'n';
  writeWidgetStateForHost(context, s);
}

