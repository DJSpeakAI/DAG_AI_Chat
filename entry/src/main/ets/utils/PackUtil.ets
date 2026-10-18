// ============================================================
// PackUtil.ets — ★ 0.207.1 DagPack v1：知识库模块化导出/导入
// ============================================================
// 设计（用户拍板「发送端粗粒度、接收端细粒度」）：
//   导出 = 点一个文件夹 → 该子树全量打包（含子文件夹/卡片/图片，零选择器）
//   导入 = 打开 .dagpack → 文件夹树勾选 → 只进勾中的子树（新建挂当前目录，绝不混入现有库）
// 格式 v1 = 单 JSON（图片 base64 内联）；v2 预留 zip（version 字段兼容，@ohos/jszip 依赖已备）
// id 安全：导出侧全部生成一次性 refId，导入侧再映射新 id——不同设备永不撞车
// 远景地基：卡片集市 / 碰一碰快传（kind 字段已为 bubble 类预留）
// ============================================================

import { KnowledgeBankStore, KnowledgeCard, KFolder, getCardImages, getTitleImages } from '../common/KnowledgeModel';
import { WordBankStore, WordItem } from '../common/WordModel';

export interface PackFolder {
  refId: string;
  name: string;
  parentRef: string; // '' = 包根（导入时挂到接收方当前文件夹下）
}

export interface PackCard {
  title: string;
  definition: string;
  tags: string;
  images: string[];  // base64 data URI 数组（v1 内联）
  titleImages?: string[]; // ★ 0.210.0：标题图（可选——v1 旧包无此字段，导入端按 [] 处理）
  folderRef: string; // '' = 包根级散卡
}

/** ★ 0.208.0：单词库包条目（wordbank 类——word 重词幂等合并） */
export interface PackWord {
  word: string;
  fullName: string;
  usPhonetic: string;
  explain: string;
  folderRef?: string; // ★ 0.249.1：所属文件夹 ref（可选——v1 旧包无此字段，导入端按 '' 根目录处理）
}

/** ★ 0.249.1：DagPack 隐式 AI 标识（合规：《人工智能生成合成内容标识办法》第五条——文件内嵌属性信息；
 *  包内容可能含 AI 提炼的卡片/释义，导出时随文件落盘，导入端 UI 同步显式提醒） */
export const DAGPACK_AI_NOTICE: string = '本包内容可能包含 AI 生成的内容，请注意甄别';

export interface DagPack {
  format: string;
  version: number;
  kind: string;      // 'knowledge' | 'wordbank'（bubble 类 0.208+ 专项）
  exportedAt: number;
  origin: string;
  folders: PackFolder[];
  cards: PackCard[];
  words?: PackWord[]; // ★ 0.208.0：kind='wordbank' 时使用
  aiNotice?: string;  // ★ 0.249.1：隐式 AI 标识（尾部追加——旧包无此字段，新版导入旧包不显示提醒）
}

/** 收集 rootFolderId 子树的全部文件夹 id（含自身；'' = 整库含根级散卡） */
function collectSubtreeFolderIds(store: KnowledgeBankStore, rootFolderId: string): string[] {
  const ids: string[] = [rootFolderId];
  let changed = true;
  // BFS 扩散：parent 在集合中的文件夹全部纳入（固定点迭代，层数不限）
  while (changed) {
    changed = false;
    for (let i = 0; i < store.folders.length; i++) {
      const f = store.folders[i];
      if (!ids.includes(f.id) && ids.includes(f.parentId)) {
        ids.push(f.id);
        changed = true;
      }
    }
  }
  return ids;
}

/**
 * 构建知识库包：rootFolderId = 某文件夹 id（该子树）或 ''（整库，含根级散卡）。
 * 图片走 getCardImages（两代字段兼容）。
 */
export function buildKnowledgePack(store: KnowledgeBankStore, rootFolderId: string): DagPack {
  const subtree = collectSubtreeFolderIds(store, rootFolderId);
  // id → refId 映射（rootFolderId 本身映射为 '' = 包根——接收方挂到其当前目录）
  const refMap: Map<string, string> = new Map<string, string>();
  refMap.set(rootFolderId, '');
  let seq = 0;
  const folders: PackFolder[] = [];
  for (let i = 0; i < store.folders.length; i++) {
    const f = store.folders[i];
    if (subtree.includes(f.id) && f.id !== rootFolderId) {
      seq++;
      const refId = 'pf' + seq;
      refMap.set(f.id, refId);
    }
  }
  // 两遍：先建映射再写 folders（parent 引用需要全部映射就位）
  for (let i = 0; i < store.folders.length; i++) {
    const f = store.folders[i];
    if (refMap.has(f.id) && f.id !== rootFolderId) {
      folders.push({ refId: refMap.get(f.id) ?? '', name: f.name, parentRef: refMap.get(f.parentId) ?? '' });
    }
  }
  const cards: PackCard[] = [];
  for (let i = 0; i < store.cards.length; i++) {
    const c = store.cards[i];
    if (refMap.has(c.folderId)) {
      cards.push({
        title: c.title, definition: c.definition, tags: c.tags,
        images: getCardImages(c), folderRef: refMap.get(c.folderId) ?? '',
        titleImages: getTitleImages(c) // ★ 0.210.0：标题图随包（可选字段——旧版接收端自动忽略）
      });
    }
  }
  const p: DagPack = { format: 'dagpack', version: 1, kind: 'knowledge', exportedAt: Date.now(), origin: 'DAGAI', folders: folders, cards: cards, aiNotice: DAGPACK_AI_NOTICE };
  return p;
}

export function packToJson(p: DagPack): string {
  return JSON.stringify(p);
}

/** 解析校验：format/version/kind 任一不符拒绝（防误选普通 JSON） */
export function parseDagPack(raw: string): DagPack | undefined {
  try {
    const p = JSON.parse(raw) as DagPack;
    if (p === null || p === undefined || p.format !== 'dagpack' || p.version !== 1) {
      return undefined;
    }
    if (p.kind !== 'knowledge' && p.kind !== 'wordbank') {
      return undefined;
    }
    if (p.kind === 'knowledge' && (!Array.isArray(p.folders) || !Array.isArray(p.cards))) {
      return undefined;
    }
    if (p.kind === 'wordbank' && !Array.isArray(p.words)) {
      return undefined;
    }
    return p;
  } catch (_e) {
    return undefined;
  }
}

// ============================================================
// ★ 0.208.0：单词库包（wordbank 类）——全量平铺导出 / word 幂等合并导入
// ============================================================

/**
 * 单词库全量打包（用户拍板：单词库只走 DagPack，不做 Anki/表格导入）。
 * ★ 0.249.1：随包带文件夹结构（folders + folderRef）——对标知识库，导入端可按文件夹勾选接收；
 * 旧版 app 导入新包自动忽略 folders/folderRef（词全部落根目录，向后兼容零破坏）。
 */
export function buildWordPack(store: WordBankStore): DagPack {
  // 两遍法：先建全量 id→refId 映射，再写 folders（parentRef 引用需要全部映射就位——同 buildKnowledgePack）
  const refMap: Map<string, string> = new Map<string, string>();
  let seq = 0;
  for (let i = 0; i < store.folders.length; i++) {
    seq++;
    refMap.set(store.folders[i].id, 'wf' + seq);
  }
  const folders: PackFolder[] = [];
  for (let i = 0; i < store.folders.length; i++) {
    const f = store.folders[i];
    folders.push({ refId: refMap.get(f.id) ?? '', name: f.name, parentRef: refMap.get(f.parentId) ?? '' });
  }
  const words: PackWord[] = [];
  for (let i = 0; i < store.words.length; i++) {
    const w = store.words[i];
    const pw: PackWord = { word: w.word, fullName: w.fullName, usPhonetic: w.usPhonetic, explain: w.explain, folderRef: refMap.get(w.folderId) ?? '' };
    words.push(pw);
  }
  const p: DagPack = { format: 'dagpack', version: 1, kind: 'wordbank', exportedAt: Date.now(), origin: 'DAGAI', folders: folders, cards: [], words: words, aiNotice: DAGPACK_AI_NOTICE };
  return p;
}

/** 包内某文件夹的直接子文件夹 refs（预览树渲染用） */
export function packChildFolders(p: DagPack, parentRef: string): PackFolder[] {
  return p.folders.filter((f: PackFolder): boolean => f.parentRef === parentRef);
}

/** 包内某 ref 子树的卡片数（含子孙文件夹；'' = 包根级散卡数） */
export function packCardCount(p: DagPack, refId: string): number {
  if (refId === '') {
    return p.cards.filter((c: PackCard): boolean => c.folderRef === '').length;
  }
  const refs: string[] = [refId];
  let changed = true;
  while (changed) {
    changed = false;
    for (let i = 0; i < p.folders.length; i++) {
      const f = p.folders[i];
      if (!refs.includes(f.refId) && refs.includes(f.parentRef)) {
        refs.push(f.refId);
        changed = true;
      }
    }
  }
  return p.cards.filter((c: PackCard): boolean => refs.includes(c.folderRef)).length;
}

/** ★ 0.249.1：包内某 ref 子树的单词数（含子孙文件夹；'' = 包根级散词数）——wordbank 导入勾选树渲染用 */
export function packWordCount(p: DagPack, refId: string): number {
  const ws: PackWord[] = p.words ?? [];
  if (refId === '') {
    return ws.filter((w: PackWord): boolean => (w.folderRef ?? '').length === 0).length;
  }
  const refs: string[] = packSubtreeRefs(p, refId);
  return ws.filter((w: PackWord): boolean => refs.includes(w.folderRef ?? '')).length;
}

/** ref 子树全部 refs（勾选计算用） */
export function packSubtreeRefs(p: DagPack, refId: string): string[] {
  const refs: string[] = [refId];
  let changed = true;
  while (changed) {
    changed = false;
    for (let i = 0; i < p.folders.length; i++) {
      const f = p.folders[i];
      if (!refs.includes(f.refId) && refs.includes(f.parentRef)) {
        refs.push(f.refId);
        changed = true;
      }
    }
  }
  return refs;
}

/** 包内文件夹全路径（预览显示，如「群论 › 有限群」） */
export function packFolderPath(p: DagPack, refId: string): string {
  const names: string[] = [];
  let cur = p.folders.find((f: PackFolder): boolean => f.refId === refId);
  let guard = 0;
  while (cur !== undefined && guard < 32) {
    names.unshift(cur.name);
    const pr: string = cur.parentRef;
    cur = pr.length === 0 ? undefined : p.folders.find((f: PackFolder): boolean => f.refId === pr);
    guard++;
  }
  return names.join(' › ');
}
