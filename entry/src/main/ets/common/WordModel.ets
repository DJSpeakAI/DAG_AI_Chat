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

import { Type, AppStorageV2 } from '@kit.ArkUI'; // @Type decorator: required by PersistenceV2 nested class arrays；★ 0.222.19：AppStorageV2（文件夹导航/折叠态共享 store）

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
  @Trace folderId: string = '';    // ★ 0.222.19：所属文件夹（'' = 根目录）——对标知识库 anything 导入体系
  @Trace mtime: number = 0;        // ★ 0.223.0：条目最后编辑时间（云同步条目级仲裁——同 id 最后编辑者胜）

  // All params have defaults so the class satisfies TypeConstructor<T> (new (): T),
  // which @Type requires for PersistenceV2 nested-class re-creation from disk.
  // ★ 0.148: id/createTime are APPENDED AT THE TAIL so legacy 4-arg call sites
  // (ChatPage translate-popup add, preset samples) stay source-compatible;
  // addWordToBank() auto-fills both when they are left empty.
  // ★ 0.222.19: folderId appended at the tail — legacy 10-arg call sites unchanged（Schema 铁律：只尾部追加）.
  // ★ 0.223.0: mtime appended at the tail — legacy 11-arg call sites unchanged（Schema 铁律：只尾部追加）.
  constructor(word: string = '', fullName: string = '', usPhonetic: string = '', explain: string = '',
    id: string = '', createTime: number = 0,
    strength: number = 0, reviewCount: number = 0, lastReviewAt: number = 0, nextReviewAt: number = 0,
    folderId: string = '', mtime: number = 0) {
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
    this.folderId = folderId;
    this.mtime = mtime;
  }
}

/** ★ 0.222.19：单词库文件夹（对标知识库 KFolder；parentId='' = 根） */
@ObservedV2
export class WordFolder {
  @Trace id: string = '';
  @Trace name: string = '';
  @Trace parentId: string = '';   // '' = 根目录
  @Trace createdAt: number = 0;
  @Trace mtime: number = 0;       // ★ 0.223.0：云同步条目级仲裁（文件夹改名/移动/复制时刷新）

  constructor(id: string = '', name: string = '', parentId: string = '', createdAt: number = 0,
    mtime: number = 0) {
    this.id = id;
    this.name = name;
    this.parentId = parentId;
    this.createdAt = createdAt;
    this.mtime = mtime;
  }
}

// PersistenceV2 top-level container. PersistenceV2 requires the persisted
// root to be a class object, and nested custom-class array properties MUST
// be decorated with @Type so items are re-created as WordItem instances
// when restored from disk.
@ObservedV2
export class WordBankStore {
  @Type(WordItem) @Trace words: WordItem[] = [];
  @Type(WordFolder) @Trace folders: WordFolder[] = []; // ★ 0.222.19：文件夹体系（对标知识库 folders）
}

// Result shape of an AI word lookup (returned by ApiClient.queryWord).
// Mirrors WordItem fields; UI converts it to a WordItem when adding to bank.
export interface WordQueryResult {
  word: string;
  fullName: string;
  usPhonetic: string;
  explain: string;
}

// ★ 0.222.19：单词库文件夹导航（AppSideBar 文件夹树 ⇄ WordBankPage 视图 跨组件共享真相源）
@ObservedV2
export class WordFolderNavStore {
  @Trace folderId: string = ''; // 当前视图文件夹（'' = 根目录）；边栏树点击与页内面包屑同源
  @Trace nonce: number = 0; // 边栏点击递增（页面若需事件感知可用；V2 页面直读 folderId 即响应）
  @Trace folderAction: string = '';   // 边栏树文件夹操作请求（'' / move / copy / delete / rename）
  @Trace folderActionId: string = ''; // 目标文件夹 id（移动/复制/删除/重命名的对象）
  @Trace folderActionName: string = ''; // 重命名时的初始名（边栏树写入，页面 TextInput 读）
}

export function connectWordFolderNav(): WordFolderNavStore {
  return AppStorageV2.connect(WordFolderNavStore, 'word-folder-nav', () => new WordFolderNavStore()) as WordFolderNavStore;
}

// ★ 0.222.19：单词库边栏折叠态（与知识库 'sidebar-section' 隔离，独立 key 防状态污染）
@ObservedV2
export class WordSidebarSectionState {
  @Trace navExpanded: boolean = true;    // 六大模块展开态（进单词库首次自动收起；用户手动展开后保持）
  @Trace folderExpanded: boolean = true; // 文件夹树展开态（默认展开）
  @Trace autoConfigured: boolean = false; // 进单词库首次自动配置标记（仅首次收起六大+展开树）
}

export function connectWordSidebarSection(): WordSidebarSectionState {
  return AppStorageV2.connect(WordSidebarSectionState, 'word-sidebar-section', () => new WordSidebarSectionState()) as WordSidebarSectionState;
}

/** ★ 0.222.19：单词库文件夹树平铺项（DFS 顺序+缩进深度，含经典树形连接线字段） */
export interface WordFolderTreeItem {
  folder: WordFolder;
  depth: number;
  isLast: boolean;              // 同级最后一个（决定拐角 └ 还是 ├）
  ancestorIds: string[];        // 祖先链（长度=depth；路径高亮判定哪条竖线属于当前路径）
  ancestorHasNext: boolean[];   // 各祖先层是否有后续兄弟（长度=depth；决定该列竖线是否贯穿）
}
