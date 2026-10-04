// ============================================================
// WordStoreUtil.ets — Word bank persistence utilities (0.145 / 0.148)
// ============================================================
// Persistence and manipulation helpers for the word bank:
//   - connectWordBank(): PersistenceV2 connect with 10 preset test words
//     + one-shot seed merge for pre-existing devices (0.151)
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

// ★ 0.151: preset test entries — 10 total covering 5 translation directions
// × 2 each (user request, for testing the bank / review features):
//   - EN→CN word:    Harmony, Serendipity
//   - Abbreviation:  OS, DAG
//   - CN→EN word:    智慧→Wisdom, 韧性→Resilience
//   - CN→EN phrase:  人工智能→Artificial Intelligence, 机器学习→Machine Learning
//   - EN→CN phrase:  Neural Network, Natural Language Processing
// AI-drafted sample data (same nature as the 0.145 Harmony/OS presets).
// CN→EN entries store the English answer in fullName — the abbreviation
// rendering path shows it right after the word and the 🔊 button speaks
// it, which is exactly the CN→EN test behaviour.
// Fixed 'preset-*' ids make seeding idempotent and deletion-aware.
function buildPresetWords(): WordItem[] {
  const now = Date.now();
  return [
    // EN→CN word (English word → Chinese explanation)
    new WordItem('Harmony', '', '/ˈhɑːrməni/', 'n. 和谐；融洽；协调', 'preset-harmony', now),
    new WordItem('Serendipity', '', '/ˌserənˈdɪpəti/', 'n. 不期而遇的惊喜；机缘巧合', 'preset-serendipity', now - 1000),
    // Abbreviation (abbreviation → English full name)
    new WordItem('OS', 'Operating System', '/ˈɒpəreɪtɪŋ ˈsɪstəm/', 'n. 操作系统（管理硬件与软件资源的系统软件）', 'preset-os', now - 2000),
    new WordItem('DAG', 'Directed Acyclic Graph', '/dəˈrektɪd eɪˈsaɪklɪk ɡræf/', 'n. 有向无环图（本应用对话树的核心结构）', 'preset-dag', now - 3000),
    // CN→EN word (Chinese word → English answer in fullName)
    new WordItem('智慧', 'Wisdom', '/ˈwɪzdəm/', 'n. 智慧；才智', 'preset-wisdom', now - 4000),
    new WordItem('韧性', 'Resilience', '/rɪˈzɪliəns/', 'n. 韧性；快速恢复的能力', 'preset-resilience', now - 5000),
    // CN→EN phrase (Chinese phrase → English phrase in fullName)
    new WordItem('人工智能', 'Artificial Intelligence', '/ˌɑːrtɪˈfɪʃl ɪnˈtelɪdʒəns/', 'n. 人工智能', 'preset-ai', now - 6000),
    new WordItem('机器学习', 'Machine Learning', '/məˈʃiːn ˈlɜːrnɪŋ/', 'n. 机器学习', 'preset-ml', now - 7000),
    // EN→CN phrase (English phrase → Chinese phrase)
    new WordItem('Neural Network', '', '/ˈnʊrəl ˈnetwɜːrk/', 'n. 神经网络', 'preset-neural-network', now - 8000),
    new WordItem('Natural Language Processing', '', '/ˈnætʃrəl ˈlæŋɡwɪdʒ prəˈsesɪŋ/', 'n. 自然语言处理（缩写 NLP）', 'preset-nlp', now - 9000)
  ];
}

// ★ 0.151: one-shot seed-merge marker. v1 = 0.145 Harmony/OS presets;
// v2 = the 10-entry test set above. The marker is persisted under its own
// key so each seed version merges missing presets EXACTLY ONCE — entries
// the user deleted stay deleted afterwards.
const WORD_SEED_VERSION = 2;
const WORD_SEED_KEY = 'word-bank-seed';

// Ids already seeded by v1 (0.145): v2 seeding must NOT resurrect these
// when the user has deleted them on a v1 device.
const WORD_SEED_V1_IDS: string[] = ['preset-harmony', 'preset-os'];

// PersistenceV2 wrapper for the seed marker (persisted root must be a class).
@ObservedV2
class WordSeedMarker {
  @Trace version: number = 0;
}

// Connect (or create) the word bank persistence instance.
// Factory presets the 10 test entries on FIRST launch only; once persisted,
// later launches restore from disk and the factory never runs again.
// ★ 0.151: devices that already hold v1 data get the v2 additions merged
// in by seedPresetWords() below — the factory alone cannot reach them.
export function connectWordBank(): WordBankStore {
  const store = PersistenceV2.connect(WordBankStore, WORD_BANK_KEY, () => {
    const s = new WordBankStore();
    s.words = buildPresetWords();
    return s;
  }) as WordBankStore;
  seedPresetWords(store);
  return store;
}

// ★ 0.151: one-shot seed merge for devices with pre-existing persisted data
// (the connect factory only runs when the key has never been persisted).
// Missing v2 presets (by fixed 'preset-*' id, v1 ids excluded) are inserted
// once; the marker version is persisted right after, so user-deleted
// presets never come back on later launches. Merged entries get fresh
// descending timestamps so the whole test set shows at the top of the bank
// page (bank page sorts by createTime, newest first).
function seedPresetWords(store: WordBankStore): void {
  const marker = PersistenceV2.connect(WordSeedMarker, WORD_SEED_KEY, () => new WordSeedMarker()) as WordSeedMarker;
  if (marker.version >= WORD_SEED_VERSION) {
    return; // v2 already merged — deleted presets stay deleted
  }
  const existing: Set<string> = new Set<string>();
  store.words.forEach((w: WordItem) => {
    existing.add(w.id);
  });
  const missing = buildPresetWords().filter((w: WordItem) =>
    !existing.has(w.id) && !WORD_SEED_V1_IDS.includes(w.id));
  if (missing.length > 0) {
    const now = Date.now();
    for (let i = 0; i < missing.length; i++) {
      missing[i].createTime = now - i * 1000;
    }
    store.words = [...missing, ...store.words];
  }
  marker.version = WORD_SEED_VERSION;
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

// ★ 0.185.0: clear every entry's phonetic (accent switch wipes old
// pronunciations). In-place loop mirrors updateWordInBank; @Trace on
// usPhonetic triggers the word-bank list refresh.
export function clearAllPhonetics(store: WordBankStore): void {
  for (let i = 0; i < store.words.length; i++) {
    store.words[i].usPhonetic = '';
  }
}
