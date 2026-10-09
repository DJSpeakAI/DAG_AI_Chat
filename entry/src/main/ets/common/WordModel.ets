// ============================================================
// WordModel.ets — Word bank data model (0.145 Word Bank MVP)
// ============================================================
// Data structures for the personal word bank feature:
//   - WordItem: a single word entry (word / fullName / usPhonetic / explain)
//   - WordBankStore: PersistenceV2 top-level container holding WordItem[]
//   - WordQueryResult: plain result shape returned by the AI word-lookup API
//
// Tech stack: HarmonyOS ArkUI V2
//   - @ObservedV2 + @Trace: observable class properties
//   - @Type: required by PersistenceV2 for nested custom class arrays
//
// Field order is FIXED (word, fullName, usPhonetic, explain) per spec:
// rendering order is word -> fullName -> usPhonetic -> explain, and the
// fullName row/cell is simply NOT rendered when empty (no placeholder).
// ============================================================

import { Type } from '@kit.ArkUI'; // @Type decorator: required by PersistenceV2 nested class arrays

// A single word entry stored in the word bank
@ObservedV2
export class WordItem {
  @Trace id: string = '';          // ★ 0.148: unique entry id — the edit/delete key (word text may change via edit)
  @Trace word: string = '';       // the word itself (e.g. "OS")
  @Trace fullName: string = '';   // full English term for abbreviations; MUST be '' for normal words
  @Trace usPhonetic: string = ''; // American phonetic transcription (e.g. "/ˈɒpəreɪtɪŋ/")
  @Trace explain: string = '';    // concise Chinese explanation
  @Trace createTime: number = 0;  // ★ 0.148: creation timestamp (ms) — bank page sorting field
  // ★ 0.187.0: memory-algorithm state (hidden from users; full spec in docs/0.165+/0.187.0)
  @Trace strength: number = 0;     // 记忆强度 S（天，浮点）；0 = 从未评分（新词标记，选词走新词队列）
  @Trace reviewCount: number = 0;  // 展示复习次数（展示即复习——被动计数，评分不重复计）
  @Trace lastReviewAt: number = 0; // 上次展示复习时间戳（ms）
  @Trace nextReviewAt: number = 0; // 计划下次复习时间戳（ms）；0 = 新词，视为已到期

  // All params have defaults so the class satisfies TypeConstructor<T> (new (): T),
  // which @Type requires for PersistenceV2 nested-class re-creation from disk.
  // ★ 0.148: id/createTime are APPENDED AT THE TAIL so legacy 4-arg call sites
  // (ChatPage translate-popup add, preset samples) stay source-compatible;
  // addWordToBank() auto-fills both when they are left empty.
  constructor(word: string = '', fullName: string = '', usPhonetic: string = '', explain: string = '',
    id: string = '', createTime: number = 0,
    strength: number = 0, reviewCount: number = 0, lastReviewAt: number = 0, nextReviewAt: number = 0) {
    this.word = word;
    this.fullName = fullName;
    this.usPhonetic = usPhonetic;
    this.explain = explain;
    this.id = id;
    this.createTime = createTime;
    this.strength = strength;
    this.reviewCount = reviewCount;
    this.lastReviewAt = lastReviewAt;
    this.nextReviewAt = nextReviewAt;
  }
}

// PersistenceV2 top-level container. PersistenceV2 requires the persisted
// root to be a class object, and nested custom-class array properties MUST
// be decorated with @Type so items are re-created as WordItem instances
// when restored from disk.
@ObservedV2
export class WordBankStore {
  @Type(WordItem) @Trace words: WordItem[] = [];
}

// Result shape of an AI word lookup (returned by ApiClient.queryWord).
// Mirrors WordItem fields; UI converts it to a WordItem when adding to bank.
export interface WordQueryResult {
  word: string;
  fullName: string;
  usPhonetic: string;
  explain: string;
}
