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
  @Trace word: string = '';       // the word itself (e.g. "OS")
  @Trace fullName: string = '';   // full English term for abbreviations; MUST be '' for normal words
  @Trace usPhonetic: string = ''; // American phonetic transcription (e.g. "/ˈɒpəreɪtɪŋ/")
  @Trace explain: string = '';    // concise Chinese explanation

  // All params have defaults so the class satisfies TypeConstructor<T> (new (): T),
  // which @Type requires for PersistenceV2 nested-class re-creation from disk.
  constructor(word: string = '', fullName: string = '', usPhonetic: string = '', explain: string = '') {
    this.word = word;
    this.fullName = fullName;
    this.usPhonetic = usPhonetic;
    this.explain = explain;
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
