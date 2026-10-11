// ============================================================
// CloudSyncBridge.ets — ★ 0.223.0 词库/知识库云同步桥
// ============================================================
// 快照行模式扩展（对齐 flat_pool/tabs_pool 既有架构，云端零改动）：
//   - word_pool：单词库全量（词条含记忆进度+文件夹归属 + 文件夹树 + 墓碑）
//   - knowledge_pool：知识库全量（卡片含记忆进度/标签/图片 + 文件夹树 + 墓碑）
//
// 仲裁语义（用户拍板 2026-10-12 方案A——条目级）：
//   - 池行时间戳（arbiter.mtimeWord/mtimeKnowledge）挡回声与整池旧数据（同 flat_pool）
//   - 条目级 mtime：同 id 双端都改过 → 最后编辑者胜；双端各改各的条目 → 全保留
//   - 墓碑（tomb）：删除可传播——墓碑时间 > 条目 mtime → 条目不复活；
//     条目在删除后又编辑（mtime > 墓碑）→ 编辑胜复活（删除 vs 编辑冲突取编辑）
//
// 纪律（0.165.2 快照行铁律，同 flat_pool）：
//   - 下行写池后绝不 upsert（防回环）；echo 由 arbiter 池级时间戳天然挡
//   - 序列化复用 BackupUtil plain 流水线（0.205.4：@ObservedV2 @Trace 字段
//     JSON.stringify 不可枚举——手写映射是唯一正确路线，两处共用一处修）
//
// 上行时机（用户拍板）：
//   - 条目变更 3 秒防抖（noteBankMutation——评分/增删改/文件夹操作咽喉统一挂）
//   - 退后台快照（EntryAbility.onBackground——本地 RDB 写入不受后台网络限制）
//   - 回前台 forceCloudSyncNow 拉取追赶（CloudSyncUtil）
// ============================================================

import { WordItem, WordFolder, WordBankStore } from '../common/WordModel';
import { KnowledgeCard, KFolder, KnowledgeBankStore } from '../common/KnowledgeModel';
import { wordToPlain, cardToPlain, folderToPlain, reviveWord, reviveCard, reviveFolder } from './BackupUtil';
import { upsertCloudData, connectCloudSyncArbiter } from './CloudSyncUtil';

const CLOUD_POOL_VERSION = 1;
const TOMB_MAX = 500;       // 墓碑上限（FIFO 裁剪——覆盖误删恢复窗口足够）
const UPLOAD_DEBOUNCE_MS = 3000; // 用户拍板：评分后 3 秒防抖上云

// ---------------- store 提供者注入（防循环依赖——0.165.2 registerCloudDataHandler 同款先例） ----------------
// WordStoreUtil/KnowledgeStoreUtil import 本文件（挂 noteBankMutation/墓碑钩子），本文件若反向
// import 它们的 connect 函数即成环。EntryAbility 启动时注入 connect 函数，运行时惰性调用。
let wordBankProvider: (() => WordBankStore) | null = null;
let knowledgeBankProvider: (() => KnowledgeBankStore) | null = null;

export function initCloudSyncBridge(wordProvider: () => WordBankStore, klgProvider: () => KnowledgeBankStore): void {
  wordBankProvider = wordProvider;
  knowledgeBankProvider = klgProvider;
}

/** 池载荷（JSON 行内容；条目为 plain Record——0.205.4 手写序列化产物） */
interface BankPoolPayload {
  schemaVersion: number;
  exportedAt: number;
  words: Record<string, Object>[];
  cards: Record<string, Object>[];
  folders: Record<string, Object>[];
  tomb: Record<string, number>;
}

// ---------------- 墓碑管理（本地持久化经 arbiter 尾部追加字段） ----------------

const wordTomb: Map<string, number> = new Map();
const knowledgeTomb: Map<string, number> = new Map();
let tombLoaded: boolean = false;

function loadTombs(): void {
  if (tombLoaded) {
    return;
  }
  tombLoaded = true;
  try {
    const arbiter = connectCloudSyncArbiter();
    if (arbiter.wordTombJson.length > 0) {
      const src = JSON.parse(arbiter.wordTombJson) as Record<string, number>;
      Object.keys(src).forEach((id: string) => wordTomb.set(id, Number(src[id])));
    }
    if (arbiter.knowledgeTombJson.length > 0) {
      const src = JSON.parse(arbiter.knowledgeTombJson) as Record<string, number>;
      Object.keys(src).forEach((id: string) => knowledgeTomb.set(id, Number(src[id])));
    }
  } catch (_e) {
    // 损坏按空处理（墓碑丢失最多导致远端复活一次，不丢数据）
  }
}

function saveTombs(): void {
  try {
    const arbiter = connectCloudSyncArbiter();
    const w: Record<string, number> = {};
    wordTomb.forEach((t: number, id: string) => { w[id] = t; });
    arbiter.wordTombJson = JSON.stringify(w);
    const k: Record<string, number> = {};
    knowledgeTomb.forEach((t: number, id: string) => { k[id] = t; });
    arbiter.knowledgeTombJson = JSON.stringify(k);
  } catch (_e) {
    // 静默（PersistenceV2 异常不影响主流程）
  }
}

function recordTombAt(map: Map<string, number>, ids: string[], now: number): void {
  loadTombs();
  for (const id of ids) {
    if (id.length === 0) {
      continue;
    }
    map.set(id, now);
  }
  while (map.size > TOMB_MAX) {
    // FIFO 裁剪：Map 保持插入序（forEach 首个=最旧；重复 set 不重排，删除时间语义可接受）
    let oldest: string = '';
    map.forEach((_t: number, id: string) => {
      if (oldest.length === 0) {
        oldest = id;
      }
    });
    if (oldest.length === 0) {
      break;
    }
    map.delete(oldest);
  }
  saveTombs();
}

/** 删除词条/单词库文件夹时记录墓碑（StoreUtil 删除链路咽喉统一挂） */
export function recordWordTomb(ids: string[]): void {
  recordTombAt(wordTomb, ids, Date.now());
  noteBankMutation();
}

/** 删除卡片/知识库文件夹时记录墓碑（含级联删除的全部卡片 id） */
export function recordKnowledgeTomb(ids: string[]): void {
  recordTombAt(knowledgeTomb, ids, Date.now());
  noteBankMutation();
}

// ---------------- 防抖上行 ----------------

let uploadTimerId: number = -1;

/** 条目变更上行入口（3 秒防抖合并连发——评分/展示复习/增删改/文件夹操作统一挂） */
export function noteBankMutation(): void {
  if (uploadTimerId >= 0) {
    clearTimeout(uploadTimerId);
  }
  uploadTimerId = setTimeout(() => {
    uploadTimerId = -1;
    try {
      upsertCloudData('word_pool', snapshotWordPool());
      upsertCloudData('knowledge_pool', snapshotKnowledgePool());
    } catch (_e) {
      // 静默（onBackground 快照兜底）
    }
  }, UPLOAD_DEBOUNCE_MS);
}

// ---------------- 快照构建 ----------------

export function snapshotWordPool(): string {
  loadTombs();
  if (wordBankProvider === null) {
    return ''; // 提供者未注入（极早期调用）——空串由 upsert 的 JSON 守卫拦截
  }
  const store = wordBankProvider();
  const words: Record<string, Object>[] = [];
  store.words.forEach((w: WordItem) => words.push(wordToPlain(w)));
  const folders: Record<string, Object>[] = [];
  store.folders.forEach((f: WordFolder) => {
    const o: Record<string, Object> = {}; // WordFolder 与 KFolder 字段同构（序列化面）
    o['id'] = f.id;
    o['name'] = f.name;
    o['parentId'] = f.parentId;
    o['createdAt'] = f.createdAt;
    o['mtime'] = f.mtime;
    folders.push(o);
  });
  const tomb: Record<string, number> = {};
  wordTomb.forEach((t: number, id: string) => { tomb[id] = t; });
  const p: BankPoolPayload = { schemaVersion: CLOUD_POOL_VERSION, exportedAt: Date.now(),
    words: words, cards: [], folders: folders, tomb: tomb };
  return JSON.stringify(p);
}

export function snapshotKnowledgePool(): string {
  loadTombs();
  if (knowledgeBankProvider === null) {
    return '';
  }
  const store = knowledgeBankProvider();
  const cards: Record<string, Object>[] = [];
  store.cards.forEach((c: KnowledgeCard) => cards.push(cardToPlain(c)));
  const folders: Record<string, Object>[] = [];
  store.folders.forEach((f: KFolder) => folders.push(folderToPlain(f)));
  const tomb: Record<string, number> = {};
  knowledgeTomb.forEach((t: number, id: string) => { tomb[id] = t; });
  const p: BankPoolPayload = { schemaVersion: CLOUD_POOL_VERSION, exportedAt: Date.now(),
    words: [], cards: cards, folders: folders, tomb: tomb };
  return JSON.stringify(p);
}

// ---------------- 条目级合并（下行） ----------------

function recordMtime(r: Record<string, Object>): number {
  return Number(r['mtime'] ?? 0);
}

function recordId(r: Record<string, Object>): string {
  return String(r['id'] ?? '');
}

/** 合并结果（避免元组返回类型——ArkTS 严格模式安全写法） */
interface MergeResult {
  items: Record<string, Object>[];
  changed: boolean;
}

/** 合并核心：同 id 取 mtime 大者；墓碑时间 ≥ 条目 mtime → 条目出局。
 *  调用方负责 revive 与写回。 */
function mergeRecords(local: Record<string, Object>[], cloud: Record<string, Object>[],
  localTomb: Map<string, number>, cloudTomb: Record<string, number>): MergeResult {
  const byId = new Map<string, Record<string, Object>>();
  let changed = false;
  // ① 本地条目先入（保留本地独有）
  local.forEach((r: Record<string, Object>) => {
    const id = recordId(r);
    if (id.length > 0) {
      byId.set(id, r);
    }
  });
  // ② 云端条目按仲裁覆盖/新增
  cloud.forEach((r: Record<string, Object>) => {
    const id = recordId(r);
    if (id.length === 0) {
      return;
    }
    const localT = localTomb.get(id) ?? 0;
    if (localT >= recordMtime(r)) {
      return; // 本地墓碑不早于云端条目编辑 → 维持删除（不复活）
    }
    const exist = byId.get(id);
    if (exist === undefined) {
      byId.set(id, r); // 云端新增 / 本地已删但云端编辑胜出（复活）→ 都是变更
      changed = true;
    } else if (recordMtime(r) > recordMtime(exist)) {
      byId.set(id, r); // 云端更新（条目级最后编辑者胜）
      changed = true;
    }
  });
  // ③ 云端墓碑传播：墓碑 ≥ 本地条目 mtime → 本地出局
  Object.keys(cloudTomb).forEach((id: string) => {
    const t = Number(cloudTomb[id]);
    const exist = byId.get(id);
    if (exist !== undefined && t >= recordMtime(exist)) {
      byId.delete(id); // 远端删除传播（本地此后再编辑会以新 mtime 复活——编辑胜语义）
      changed = true;
    }
  });
  const out: Record<string, Object>[] = [];
  byId.forEach((r: Record<string, Object>) => out.push(r));
  const result: MergeResult = { items: out, changed: changed };
  return result;
}

/** 墓碑并集（本地∪云端，同 id 取大）——合并后持久化，供下次快照携带 */
function unionTomb(local: Map<string, number>, cloudTomb: Record<string, number>): void {
  Object.keys(cloudTomb).forEach((id: string) => {
    const t = Number(cloudTomb[id]);
    const cur = local.get(id) ?? 0;
    if (t > cur) {
      local.set(id, t);
    }
  });
}

function parsePoolPayload(cloudJson: string): BankPoolPayload | undefined {
  try {
    const p = JSON.parse(cloudJson) as BankPoolPayload;
    if (p === null || p === undefined || typeof p.schemaVersion !== 'number' ||
      p.schemaVersion > CLOUD_POOL_VERSION) {
      return undefined;
    }
    if (!Array.isArray(p.words) || !Array.isArray(p.cards) || !Array.isArray(p.folders)) {
      return undefined;
    }
    return p;
  } catch (_e) {
    return undefined;
  }
}

/** word_pool 下行合并（写回 @Trace 数组触发全页刷新）。返回 true=有实际写回。
 *  调用方（ChatModel handler）负责池级时间戳仲裁与 echo 挡截。 */
export function mergeWordPoolFromCloud(cloudJson: string): boolean {
  loadTombs();
  if (wordBankProvider === null) {
    return false;
  }
  const p = parsePoolPayload(cloudJson);
  if (p === undefined) {
    return false;
  }
  const store = wordBankProvider();
  const localWords: Record<string, Object>[] = [];
  store.words.forEach((w: WordItem) => localWords.push(wordToPlain(w)));
  const localFolders: Record<string, Object>[] = [];
  store.folders.forEach((f: WordFolder) => {
    const o: Record<string, Object> = {};
    o['id'] = f.id;
    o['name'] = f.name;
    o['parentId'] = f.parentId;
    o['createdAt'] = f.createdAt;
    o['mtime'] = f.mtime;
    localFolders.push(o);
  });
  const wordsResult = mergeRecords(localWords, p.words, wordTomb, p.tomb);
  const foldersResult = mergeRecords(localFolders, p.folders, wordTomb, p.tomb);
  unionTomb(wordTomb, p.tomb);
  saveTombs();
  if (!wordsResult.changed && !foldersResult.changed) {
    return false;
  }
  const mergedWords = wordsResult.items;
  const revivedWords: WordItem[] = [];
  mergedWords.forEach((r: Record<string, Object>) => {
    const w = reviveWord(r);
    if (w.word.trim().length > 0 || w.id.length > 0) {
      revivedWords.push(w);
    }
  });
  store.words = revivedWords; // @Trace 数组整体替换=可靠刷新（0.222.x 定式）
  const mergedFolders = foldersResult.items;
  const revivedFolders: WordFolder[] = [];
  mergedFolders.forEach((r: Record<string, Object>) => {
    const id = String(r['id'] ?? '');
    const name = String(r['name'] ?? '');
    if (id.length === 0 || name.length === 0) {
      return;
    }
    const f = new WordFolder();
    f.id = id;
    f.name = name;
    f.parentId = String(r['parentId'] ?? '');
    f.createdAt = Number(r['createdAt'] ?? 0);
    f.mtime = Number(r['mtime'] ?? 0);
    revivedFolders.push(f);
  });
  store.folders = revivedFolders;
  return true;
}

/** knowledge_pool 下行合并（同 mergeWordPoolFromCloud） */
export function mergeKnowledgePoolFromCloud(cloudJson: string): boolean {
  loadTombs();
  if (knowledgeBankProvider === null) {
    return false;
  }
  const p = parsePoolPayload(cloudJson);
  if (p === undefined) {
    return false;
  }
  const store = knowledgeBankProvider();
  const localCards: Record<string, Object>[] = [];
  store.cards.forEach((c: KnowledgeCard) => localCards.push(cardToPlain(c)));
  const localFolders: Record<string, Object>[] = [];
  store.folders.forEach((f: KFolder) => localFolders.push(folderToPlain(f)));
  const cardsResult = mergeRecords(localCards, p.cards, knowledgeTomb, p.tomb);
  const foldersResult = mergeRecords(localFolders, p.folders, knowledgeTomb, p.tomb);
  unionTomb(knowledgeTomb, p.tomb);
  saveTombs();
  if (!cardsResult.changed && !foldersResult.changed) {
    return false;
  }
  const mergedCards = cardsResult.items;
  const revivedCards: KnowledgeCard[] = [];
  mergedCards.forEach((r: Record<string, Object>) => {
    const c = reviveCard(r);
    if (c.title.trim().length > 0 || c.id.length > 0) {
      revivedCards.push(c);
    }
  });
  store.cards = revivedCards;
  const mergedFolders = foldersResult.items;
  const revivedFolders: KFolder[] = [];
  mergedFolders.forEach((r: Record<string, Object>) => {
    const f = reviveFolder(r);
    if (f !== undefined) {
      revivedFolders.push(f);
    }
  });
  store.folders = revivedFolders;
  return true;
}
