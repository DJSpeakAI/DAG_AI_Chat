// ============================================================
// WordStoreUtil.ets — Word bank persistence utilities (0.145 / 0.148)
// ============================================================
// Persistence and manipulation helpers for the word bank:
//   - connectWordBank(): PersistenceV2 connect with preset sample words
//   - genWordId(): unique id generator (0.148)
//   - addWordToBank(): add a word (returns false when duplicate);
//     auto-fills id/createTime when absent (0.148, legacy call sites unchanged)
//   - removeWordFromBank(): remove by entry id (0.148: was by word text —
//     word text can be changed by the editor, id is the stable key)
//   - updateWordInBank(): edit an entry by id (0.148, duplicate-checked)
//   - removeWordsByIds(): batch delete for multi-select mode (0.148)
//   - pickRandomWords(): pick n random words for the review table
//
// The word bank is persisted under its OWN PersistenceV2 key ('word-bank'),
// fully isolated from the bubble-tree persistence — deleting words never
// touches chat data and vice versa.
// ============================================================

import { PersistenceV2 } from '@kit.ArkUI';
import { WordItem, WordBankStore } from '../common/WordModel';

// Dedicated PersistenceV2 key, isolated from bubble tree / api config keys
const WORD_BANK_KEY = 'word-bank';

// ★ 0.148: unique entry id — timestamp(base36) + random suffix, collision-safe
export function genWordId(): string {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
}

// Connect (or create) the word bank persistence instance.
// Factory presets two sample entries on FIRST launch only:
//   - Harmony: a normal word (fullName = '', full-name row not rendered)
//   - OS: an abbreviation (fullName = 'Operating System')
// Once persisted, later launches restore from disk and the factory
// never runs again — deleted samples do not reappear after restart.
export function connectWordBank(): WordBankStore {
  return PersistenceV2.connect(WordBankStore, WORD_BANK_KEY, () => {
    const store = new WordBankStore();
    const now = Date.now();
    store.words = [
      new WordItem('Harmony', '', '/ˈhɑːrməni/', 'n. 和谐；融洽；协调', 'preset-harmony', now),
      new WordItem('OS', 'Operating System', '/ˈɒpəreɪtɪŋ ˈsɪstəm/', 'n. 操作系统（管理硬件与软件资源的系统软件）', 'preset-os', now - 1000)
    ];
    return store;
  }) as WordBankStore;
}

// Add a word to the bank. Returns false when the word already exists
// (case-insensitive) so the caller can show the "already exists" tip.
// New words are inserted at the head so the newest entry shows first.
// ★ 0.148: auto-fills id/createTime when absent — legacy 4-arg call sites
// (ChatPage translate popup) keep working without any change there.
export function addWordToBank(store: WordBankStore, item: WordItem): boolean {
  const lower = item.word.trim().toLowerCase();
  if (lower.length === 0) {
    return false;
  }
  if (item.id.length === 0) {
    item.id = genWordId();
  }
  if (item.createTime === 0) {
    item.createTime = Date.now();
  }
  for (let i = 0; i < store.words.length; i++) {
    if (store.words[i].word.trim().toLowerCase() === lower) {
      return false; // duplicate — caller shows "word already exists"
    }
  }
  store.words = [item, ...store.words];
  return true;
}

// ★ 0.148: edit an entry by id. Word text may change, so id is the key.
// Returns false when the NEW word duplicates another entry (excluding self).
export function updateWordInBank(store: WordBankStore, wordId: string,
  word: string, fullName: string, usPhonetic: string, explain: string): boolean {
  const lower = word.trim().toLowerCase();
  if (lower.length === 0) {
    return false;
  }
  for (let i = 0; i < store.words.length; i++) {
    if (store.words[i].word.trim().toLowerCase() === lower && store.words[i].id !== wordId) {
      return false; // new word collides with another entry
    }
  }
  for (let i = 0; i < store.words.length; i++) {
    if (store.words[i].id === wordId) {
      store.words[i].word = word.trim();
      store.words[i].fullName = fullName.trim();
      store.words[i].usPhonetic = usPhonetic.trim();
      store.words[i].explain = explain.trim();
      return true;
    }
  }
  return false; // id not found (entry deleted elsewhere)
}

// Remove a word by entry id (★ 0.148: was by word text — the editor can
// change word text, so id is the only stable delete key).
export function removeWordFromBank(store: WordBankStore, wordId: string): void {
  store.words = store.words.filter((w: WordItem) => w.id !== wordId);
}

// ★ 0.148: batch delete for the multi-select mode.
export function removeWordsByIds(store: WordBankStore, wordIds: string[]): void {
  store.words = store.words.filter((w: WordItem) => !wordIds.includes(w.id));
}

// Pick up to `count` random words (Fisher-Yates shuffle on a copy).
// Returns fewer items when the bank has fewer words; empty bank returns [].
export function pickRandomWords(store: WordBankStore, count: number): WordItem[] {
  const pool: WordItem[] = [...store.words];
  for (let i = pool.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    const tmp = pool[i];
    pool[i] = pool[j];
    pool[j] = tmp;
  }
  return pool.slice(0, count);
}
