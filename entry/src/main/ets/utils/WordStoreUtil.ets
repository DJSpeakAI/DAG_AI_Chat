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
//   - normalizeMemoryFields(): ★ 0.187.0 back-fill memory fields on legacy data
//
// The word bank is persisted under its OWN PersistenceV2 key ('word-bank'),
// fully isolated from the bubble-tree persistence — deleting words never
// touches chat data and vice versa.
// ============================================================

import { PersistenceV2 } from '@kit.ArkUI';
import { WordItem, WordBankStore, WordFolder } from '../common/WordModel';
import { noteBankMutation, recordWordTomb } from '../common/ChatModel'; // ★ 0.223.0：云同步变更钩子（增删改/文件夹操作统一挂——单向依赖，Bridge 经提供者注入反向取 store 防环）

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
    // ★ 0.224.2 CN→EN word（用户拍板四行制修正：第二行 fullName=缩写全称专用——中译英的英文
    //   进第四行 explain、第二行必须空、中文不重复。旧版把英文塞 fullName+中文重复 explain 是错位格式）
    new WordItem('智慧', '', '/ˈwɪzdəm/', 'Wisdom', 'preset-wisdom', now - 4000),
    new WordItem('韧性', '', '/rɪˈzɪliəns/', 'Resilience', 'preset-resilience', now - 5000),
    new WordItem('人工智能', '', '/ˌɑːrtɪˈfɪʃl ɪnˈtelɪdʒəns/', 'Artificial Intelligence', 'preset-ai', now - 6000),
    new WordItem('机器学习', '', '/məˈʃiːn ˈlɜːrnɪŋ/', 'Machine Learning', 'preset-ml', now - 7000),
    // EN→CN phrase (English phrase → Chinese phrase)
    new WordItem('Neural Network', '', '/ˈnʊrəl ˈnetwɜːrk/', 'n. 神经网络', 'preset-neural-network', now - 8000),
    new WordItem('Natural Language Processing', '', '/ˈnætʃrəl ˈlæŋɡwɪdʒ prəˈsesɪŋ/', 'n. 自然语言处理（缩写 NLP）', 'preset-nlp', now - 9000),
    // ★ 0.274.0 v4：多方向测试数据扩充（用户需求「单词也多加几张、多元化」）——
    //   缩写 2 + 中译英 2 + 英译中 2；explain 保持简洁纯释义格式（与存量词条一致）
    new WordItem('API', 'Application Programming Interface', '/ˌeɪ piː ˈaɪ/', 'n. 应用程序编程接口', 'preset-api', now - 10000),
    new WordItem('CPU', 'Central Processing Unit', '/ˌsiː piː ˈjuː/', 'n. 中央处理器', 'preset-cpu', now - 11000),
    new WordItem('熵', '', '/ˈentrəpi/', 'Entropy', 'preset-entropy', now - 12000),
    new WordItem('深度学习', '', '/diːp ˈlɜːrnɪŋ/', 'Deep Learning', 'preset-deep-learning', now - 13000),
    new WordItem('Cache', '', '/kæʃ/', 'n. 高速缓存', 'preset-cache', now - 14000),
    new WordItem('Blockchain', '', '/ˈblɒktʃeɪn/', 'n. 区块链', 'preset-blockchain', now - 15000)
  ];
}

// ★ 0.151: one-shot seed-merge marker. v1 = 0.145 Harmony/OS presets;
//   v2 = the 10-entry test set; v3 = ★ 0.224.2 四行制内容修正（中译英 4 条：英文
//   从 fullName 挪到 explain、fullName 置空——同 id 更新内容保留记忆字段）；
//   v4 = ★ 0.274.0 多方向扩充 6 条（API/CPU 缩写、熵/深度学习中译英、Cache/Blockchain 英译中）。
const WORD_SEED_VERSION = 4;
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
  normalizeMemoryFields(store); // ★ 0.187.0：存量词条补齐记忆字段（防 undefined/NaN 进算法）
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
    return; // 已合入最新版——已删的预置保持删除
  }
  const presets = buildPresetWords();
  // ★ 0.224.2 v3：同 id 内容修正（四行制格式纠错——中译英旧版英文塞 fullName+中文重复 explain）。
  //   仅更新内容四字段，记忆/归档字段原样保留（同 0.202.2 知识卡 v3「同 id 更新内容保留记忆」模式）；
  //   已删 id 不在库中天然跳过（「删除保持删除」不破坏）。
  const byId = new Map<string, WordItem>();
  store.words.forEach((w: WordItem) => byId.set(w.id, w));
  presets.forEach((p: WordItem) => {
    const cur = byId.get(p.id);
    if (cur !== undefined) {
      cur.word = p.word;
      cur.fullName = p.fullName;
      cur.usPhonetic = p.usPhonetic;
      cur.explain = p.explain;
      cur.mtime = Date.now();
    }
  });
  const existing: Set<string> = new Set<string>();
  store.words.forEach((w: WordItem) => {
    existing.add(w.id);
  });
  const missing = presets.filter((w: WordItem) =>
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

// ★ 0.187.0: back-fill memory fields on legacy data. Entries persisted before
// 0.187 lack the 4 new fields — PersistenceV2 restore may leave them undefined
// (same fresh-key lesson as 0.185); normalize to numeric defaults so the
// memory algorithm never sees NaN/undefined.
function normalizeMemoryFields(store: WordBankStore): void {
  for (let i = 0; i < store.words.length; i++) {
    const w = store.words[i];
    if (typeof w.strength !== 'number' || !isFinite(w.strength)) {
      w.strength = 0;
    }
    if (typeof w.reviewCount !== 'number' || !isFinite(w.reviewCount)) {
      w.reviewCount = 0;
    }
    if (typeof w.lastReviewAt !== 'number' || !isFinite(w.lastReviewAt)) {
      w.lastReviewAt = 0;
    }
    if (typeof w.nextReviewAt !== 'number' || !isFinite(w.nextReviewAt)) {
      w.nextReviewAt = 0;
    }
    if (typeof w.folderId !== 'string') {
      w.folderId = ''; // ★ 0.222.19：存量词条补 folderId 兜底（旧快照缺失 → 根目录）
    }
  }
  if (!(store.folders instanceof Array)) {
    store.folders = []; // ★ 0.222.19：旧快照无 folders 字段兜底
  }
}

// Add a word to the bank (★ 0.222.19：完全放开，允许任意同名——彻底对标知识库无去重；
// 用户拍板随文件夹体系一起取消同名词拒绝，故「单词已存在」提示不再触发）。
// New words are inserted at the head so the newest entry shows first.
// ★ 0.148: auto-fills id/createTime when absent — legacy 4-arg call sites
// (ChatPage translate popup) keep working without any change there.
// Returns false ONLY for a blank word (empty text is still rejected).
export function addWordToBank(store: WordBankStore, item: WordItem): boolean {
  if (item.word.trim().length === 0) {
    return false;
  }
  const now = Date.now();
  if (item.id.length === 0) {
    item.id = genWordId();
  }
  if (item.createTime === 0) {
    item.createTime = now;
  }
  if (item.mtime === 0) {
    item.mtime = now; // ★ 0.223.0：条目级仲裁时间戳
  }
  store.words = [item, ...store.words];
  noteBankMutation();
  return true;
}

// ★ 0.148: edit an entry by id. Word text may change, so id is the key.
// ★ 0.222.19：取消同名冲突检查（与 addWordToBank 同步放开），仅空文本拒绝。
export function updateWordInBank(store: WordBankStore, wordId: string,
  word: string, fullName: string, usPhonetic: string, explain: string): boolean {
  if (word.trim().length === 0) {
    return false;
  }
  for (let i = 0; i < store.words.length; i++) {
    if (store.words[i].id === wordId) {
      store.words[i].word = word.trim();
      store.words[i].fullName = fullName.trim();
      store.words[i].usPhonetic = usPhonetic.trim();
      store.words[i].explain = explain.trim();
      store.words[i].mtime = Date.now(); // ★ 0.223.0：条目级仲裁时间戳
      noteBankMutation();
      return true;
    }
  }
  return false; // id not found (entry deleted elsewhere)
}

// Remove a word by entry id (★ 0.148: was by word text — the editor can
// change word text, so id is the only stable delete key).
export function removeWordFromBank(store: WordBankStore, wordId: string): void {
  store.words = store.words.filter((w: WordItem) => w.id !== wordId);
  recordWordTomb([wordId]); // ★ 0.223.0：墓碑传播删除（内含防抖上行）
}

// ★ 0.148: batch delete for the multi-select mode.
export function removeWordsByIds(store: WordBankStore, wordIds: string[]): void {
  store.words = store.words.filter((w: WordItem) => !wordIds.includes(w.id));
  recordWordTomb(wordIds); // ★ 0.223.0：墓碑传播删除
}

// ★ 0.187.0: pickRandomWords REMOVED — review selection now goes through
// MemoryAlgorithm.pickReviewWords (forgetting-curve driven, replaces random).

// ★ 0.185.0: clear every entry's phonetic (accent switch wipes old
// pronunciations). In-place loop mirrors updateWordInBank; @Trace on
// usPhonetic triggers the word-bank list refresh.
export function clearAllPhonetics(store: WordBankStore): void {
  const now = Date.now();
  for (let i = 0; i < store.words.length; i++) {
    store.words[i].usPhonetic = '';
    store.words[i].mtime = now; // ★ 0.223.0：条目级仲裁时间戳（口音切换=全量条目变更）
  }
  noteBankMutation();
}

// ============================================================
// ★ 0.222.19：单词库文件夹 CRUD + 单词移动/复制（对标知识库 anything 体系）
// ============================================================

/** 单词库文件夹 id 生成（'wf' 前缀，与词条 id 区分） */
export function genWordFolderId(): string {
  return 'wf' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
}

/** 新建文件夹（同名允许——id 唯一即可；返回新文件夹 id） */
export function addWordFolder(store: WordBankStore, name: string, parentId: string): string {
  const nm = name.trim();
  if (nm.length === 0) {
    return '';
  }
  const f = new WordFolder(genWordFolderId(), nm, parentId, Date.now(), Date.now());
  store.folders = [...store.folders, f];
  noteBankMutation(); // ★ 0.223.0
  return f.id;
}

/** 重命名文件夹 */
export function renameWordFolder(store: WordBankStore, folderId: string, name: string): void {
  const nm = name.trim();
  if (nm.length === 0) {
    return;
  }
  for (let i = 0; i < store.folders.length; i++) {
    if (store.folders[i].id === folderId) {
      store.folders[i].name = nm;
      store.folders[i].mtime = Date.now(); // ★ 0.223.0
      noteBankMutation();
      return;
    }
  }
}

/**
 * 删除文件夹——单词与子文件夹一律**上移到被删文件夹的父级**（绝不删词，数据安全红线）。
 */
export function deleteWordFolder(store: WordBankStore, folderId: string): void {
  const target = store.folders.find((f: WordFolder): boolean => f.id === folderId);
  if (target === undefined) {
    return;
  }
  const upParent = target.parentId;
  const now = Date.now();
  for (let i = 0; i < store.words.length; i++) {
    if (store.words[i].folderId === folderId) {
      store.words[i].folderId = upParent;
      store.words[i].mtime = now; // ★ 0.223.0：归属变化=条目变更
    }
  }
  const newFolders: WordFolder[] = [];
  for (let i = 0; i < store.folders.length; i++) {
    if (store.folders[i].id === folderId) {
      continue;
    }
    if (store.folders[i].parentId === folderId) {
      store.folders[i].parentId = upParent;
      store.folders[i].mtime = now; // ★ 0.223.0
    }
    newFolders.push(store.folders[i]);
  }
  store.folders = newFolders;
  recordWordTomb([folderId]); // ★ 0.223.0：文件夹墓碑（内含防抖上行）
}

/** 同级是否已存在同名文件夹（excludeId 排除自身——重命名/移动时用） */
export function wordFolderNameExists(store: WordBankStore, name: string, parentId: string, excludeId: string = ''): boolean {
  for (let i = 0; i < store.folders.length; i++) {
    const f = store.folders[i];
    if (f.id !== excludeId && f.parentId === parentId && f.name === name) {
      return true;
    }
  }
  return false;
}

/** 生成不重名的文件夹名（重名自动加「副本」后缀） */
export function genUniqueWordFolderName(store: WordBankStore, name: string, parentId: string): string {
  if (!wordFolderNameExists(store, name, parentId)) {
    return name;
  }
  let i = 1;
  let candidate = `${name} 副本`;
  while (wordFolderNameExists(store, candidate, parentId)) {
    i++;
    candidate = `${name} 副本${i}`;
  }
  return candidate;
}

/** 移动文件夹到目标父级（防环：目标不能是自己或自己的子孙）——返回是否成功 */
export function moveWordFolder(store: WordBankStore, folderId: string, targetParentId: string): boolean {
  // 防环：从目标沿 parentId 上溯，若命中自身则说明目标是自己的子孙
  let cur = targetParentId;
  let guard = 0;
  while (cur !== '' && guard < 64) {
    if (cur === folderId) {
      return false;
    }
    const p = store.folders.find((f: WordFolder): boolean => f.id === cur);
    if (p === undefined) {
      break;
    }
    cur = p.parentId;
    guard++;
  }
  const f = store.folders.find((x: WordFolder): boolean => x.id === folderId);
  if (f === undefined) {
    return false;
  }
  f.parentId = targetParentId;
  f.mtime = Date.now(); // ★ 0.223.0
  noteBankMutation();
  return true;
}

/** 递归复制整个文件夹子树（文件夹+单词+子文件夹全部新 id；记忆字段清零）——返回复制单词数
 *  复制到自身/子孙全部放开（对标知识库：复制自己=把自己复制一份变成自己的子文件夹）。
 *  children 快照务必在 addWordFolder 之前取（防复制到自身时无限递归）。 */
export function copyWordFolder(store: WordBankStore, folderId: string, targetParentId: string): number {
  const src = store.folders.find((f: WordFolder): boolean => f.id === folderId);
  if (src === undefined) {
    return 0;
  }
  // 先快照源子树直属 children（在 addWordFolder 之前）
  const childIds: string[] = [];
  for (let i = 0; i < store.folders.length; i++) {
    if (store.folders[i].parentId === folderId) {
      childIds.push(store.folders[i].id);
    }
  }
  const newName = genUniqueWordFolderName(store, src.name, targetParentId);
  const newId = addWordFolder(store, newName, targetParentId);
  let wordCount = 0;
  const now = Date.now();
  const copies: WordItem[] = [];
  for (let i = 0; i < store.words.length; i++) {
    const w = store.words[i];
    if (w.folderId !== folderId) {
      continue;
    }
    copies.push(new WordItem(w.word, w.fullName, w.usPhonetic, w.explain, genWordId(), now + wordCount,
      0, 0, 0, 0, newId, now + wordCount)); // ★ 0.223.0：复制件 mtime（新条目）
    wordCount++;
  }
  if (copies.length > 0) {
    store.words = [...copies, ...store.words];
  }
  // 递归复制子文件夹（基于前置快照，新增副本永不进遍历）
  for (let j = 0; j < childIds.length; j++) {
    wordCount += copyWordFolder(store, childIds[j], newId);
  }
  noteBankMutation(); // ★ 0.223.0
  return wordCount;
}

/** 复制根目录全部内容（所有文件夹子树 + 直属根单词）到目标文件夹——返回复制单词数；目标==根拒绝 */
export function copyRootWordFolder(store: WordBankStore, targetParentId: string): number {
  if (targetParentId === '') {
    return -1;
  }
  let wordCount = 0;
  const topFolders: string[] = [];
  for (let i = 0; i < store.folders.length; i++) {
    if (store.folders[i].parentId === '') {
      topFolders.push(store.folders[i].id);
    }
  }
  for (let j = 0; j < topFolders.length; j++) {
    const n = copyWordFolder(store, topFolders[j], targetParentId);
    if (n > 0) {
      wordCount += n;
    }
  }
  const now = Date.now();
  const copies: WordItem[] = [];
  let k = 0;
  for (let m = 0; m < store.words.length; m++) {
    const w = store.words[m];
    if (w.folderId !== '') {
      continue;
    }
    copies.push(new WordItem(w.word, w.fullName, w.usPhonetic, w.explain, genWordId(), now + k,
      0, 0, 0, 0, targetParentId, now + k)); // ★ 0.223.0：复制件 mtime
    k++;
  }
  if (copies.length > 0) {
    store.words = [...copies, ...store.words];
  }
  wordCount += k;
  noteBankMutation(); // ★ 0.223.0
  return wordCount;
}

/** 清空根目录全部内容（单词+文件夹全删，根目录「全部单词」入口概念保留）——返回删除单词数 */
export function clearRootWordFolder(store: WordBankStore): number {
  const n = store.words.length;
  const tombIds: string[] = store.words.map((w: WordItem): string => w.id);
  store.folders.forEach((f: WordFolder) => tombIds.push(f.id));
  store.words = [];
  store.folders = [];
  recordWordTomb(tombIds); // ★ 0.223.0：全量墓碑（内含防抖上行）
  return n;
}

/** 级联删除文件夹（自身+子孙文件夹+其中所有单词）——返回删除的单词数 */
export function deleteWordFolderCascade(store: WordBankStore, folderId: string): number {
  const toDelete: string[] = [folderId];
  let guard = 0;
  for (let i = 0; i < toDelete.length && guard < 1000; i++) {
    const pid = toDelete[i];
    const children = store.folders.filter((f: WordFolder): boolean => f.parentId === pid);
    for (let j = 0; j < children.length; j++) {
      if (!toDelete.includes(children[j].id)) {
        toDelete.push(children[j].id);
      }
    }
    guard++;
  }
  let wordCount = 0;
  const keep: WordItem[] = [];
  const tombIds: string[] = [...toDelete]; // ★ 0.223.0：文件夹全集墓碑
  for (let k = 0; k < store.words.length; k++) {
    if (toDelete.includes(store.words[k].folderId)) {
      tombIds.push(store.words[k].id);
      wordCount++;
    } else {
      keep.push(store.words[k]);
    }
  }
  store.words = keep;
  store.folders = store.folders.filter((f: WordFolder): boolean => !toDelete.includes(f.id));
  recordWordTomb(tombIds); // ★ 0.223.0：级联删除墓碑（内含防抖上行）
  return wordCount;
}

/** 移动单词（批量）到目标文件夹（folderId='' 即根目录） */
export function moveWords(store: WordBankStore, wordIds: string[], folderId: string): void {
  const now = Date.now();
  for (let i = 0; i < store.words.length; i++) {
    if (wordIds.includes(store.words[i].id)) {
      store.words[i].folderId = folderId;
      store.words[i].mtime = now; // ★ 0.223.0：归属变化=条目变更
    }
  }
  noteBankMutation();
}

/** 复制单词（批量）到目标文件夹——新 id / 新 createTime，记忆字段清零；返回新增条数 */
export function copyWords(store: WordBankStore, wordIds: string[], folderId: string): number {
  let n = 0;
  const now = Date.now();
  const copies: WordItem[] = [];
  for (let i = 0; i < store.words.length; i++) {
    const src = store.words[i];
    if (!wordIds.includes(src.id)) {
      continue;
    }
    copies.push(new WordItem(src.word, src.fullName, src.usPhonetic, src.explain, genWordId(), now + n,
      0, 0, 0, 0, folderId, now + n)); // ★ 0.223.0：复制件 mtime
    n++;
  }
  if (copies.length > 0) {
    store.words = [...copies, ...store.words];
    noteBankMutation();
  }
  return n;
}

/** 取文件夹名链（根→…→当前）——面包屑用 */
export function wordFolderChain(store: WordBankStore, folderId: string): WordFolder[] {
  const chain: WordFolder[] = [];
  let cur = store.folders.find((f: WordFolder): boolean => f.id === folderId);
  let guard = 0;
  while (cur !== undefined && guard < 32) {
    chain.unshift(cur);
    const pid: string = cur.parentId;
    cur = pid.length === 0 ? undefined : store.folders.find((f: WordFolder): boolean => f.id === pid);
    guard++;
  }
  return chain;
}

/** 逐级找/建文件夹路径（导入用，幂等）——返回最深层 folderId */
export function ensureWordFolderPath(store: WordBankStore, names: string[], parentId: string): string {
  let pid = parentId;
  for (let i = 0; i < names.length; i++) {
    const nm = names[i].trim();
    if (nm.length === 0) {
      continue;
    }
    const exist = store.folders.find((f: WordFolder): boolean => f.parentId === pid && f.name === nm);
    if (exist !== undefined) {
      pid = exist.id;
    } else {
      pid = addWordFolder(store, nm, pid);
    }
  }
  return pid;
}
