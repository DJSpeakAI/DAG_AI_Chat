// ============================================================
// WordStoreUtil.ets — Word bank persistence utilities (0.145)
// ============================================================
// Persistence and manipulation helpers for the word bank:
//   - connectWordBank(): PersistenceV2 connect with preset sample words
//   - addWordToBank(): add a word (returns false when duplicate)
//   - removeWordFromBank(): remove by word text
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

// Connect (or create) the word bank persistence instance.
// Factory presets two sample entries on FIRST launch only:
//   - Harmony: a normal word (fullName = '', full-name row not rendered)
//   - OS: an abbreviation (fullName = 'Operating System')
// Once persisted, later launches restore from disk and the factory
// never runs again — deleted samples do not reappear after restart.
export function connectWordBank(): WordBankStore {
  return PersistenceV2.connect(WordBankStore, WORD_BANK_KEY, () => {
    const store = new WordBankStore();
    store.words = [
      new WordItem('Harmony', '', '/ˈhɑːrməni/', 'n. 和谐；融洽；协调'),
      new WordItem('OS', 'Operating System', '/ˈɒpəreɪtɪŋ ˈsɪstəm/', 'n. 操作系统（管理硬件与软件资源的系统软件）')
    ];
    return store;
  }) as WordBankStore;
}

// Add a word to the bank. Returns false when the word already exists
// (case-insensitive) so the caller can show the "already exists" tip.
// New words are inserted at the head so the newest entry shows first.
export function addWordToBank(store: WordBankStore, item: WordItem): boolean {
  const lower = item.word.trim().toLowerCase();
  if (lower.length === 0) {
    return false;
  }
  for (let i = 0; i < store.words.length; i++) {
    if (store.words[i].word.trim().toLowerCase() === lower) {
      return false; // duplicate — caller shows "word already exists"
    }
  }
  store.words = [item, ...store.words];
  return true;
}

// Remove a word by exact word text (delete is the ONLY manual operation
// in the bank page — manual add is intentionally not provided).
export function removeWordFromBank(store: WordBankStore, word: string): void {
  store.words = store.words.filter((w: WordItem) => w.word !== word);
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
