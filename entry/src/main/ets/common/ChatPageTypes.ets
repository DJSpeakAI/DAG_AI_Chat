// ============================================================
// ChatPageTypes.ets — 对话页数据类型与会话级常量（★ 拆分自 ChatPage.ets）
// ============================================================
// 承载：Markdown 解析段模型、复习缓存条目、渲染计划（RichPlan 族）、
//       字号缩放持久化 store、页面级常量与会话级内存 Map。
// 注意：PLACEHOLDER_LOADING 字面值与历史持久化数据一致，不可改动（旧数据的过滤判断依赖它）。
import { PersistenceV2, AppStorageV2 } from '@kit.ArkUI';
import { MdBlock, FoldSection } from '../utils/MdInline';
import { WordItem } from './WordModel';
import { KnowledgeCard } from './KnowledgeModel';

// ★ 0.237.0 术语荧光底回退开关（任务书 §5.2 实验性——先全量加底试观感，观感太花一键关掉回退纯加粗）
export const glowHighlight: boolean = true;
// ★ 0.285.0 对话正文行高倍率（UI_GUIDELINES 二十九章）：WCAG 1.4.12 行高 ≥1.5 为下限、1.75 为中文长文舒适档（对标 DeepSeek 16/28）
//   铁律：AI 正文（MdBlockText 行高公式）、用户消息气泡、书签回退纯文本段三处必须走同一倍率，禁止单侧收紧。
export const BODY_LINE_HEIGHT_RATIO: number = 1.75;
// ★ 0.285.0 PC 划词菜单定宽：条目文字 2~4 字，180vp 内整行可命中且不出现大片空白。
export const PC_SELECTION_MENU_WIDTH: number = 180;

// ★ 0.121：Markdown 解析段（0=普通文本, 1=代码块, 2=表格）
export class MdSegment {
  type: number;
  content: string;
  lang: string;
  header: string[];
  rows: string[][];
  constructor(type: number, content: string, lang: string = '', header: string[] = [], rows: string[][] = []) {
    this.type = type;
    this.content = content;
    this.lang = lang;
    this.header = header;
    this.rows = rows;
  }
}

// ★ 0.145：生词复习缓存条目——按消息 ID 缓存抽取的复习词。
// ★ 0.187.0：缓存改为按消息 ID 永久固定（version 弃用置 0）——历史消息展示「当时」
// 的词；加词/改设置不再触发全量重抽（原 version=词库长度失效机制会把一次加词变成
// 几十次虚假复习）。已删除的词由 getReviewWords 读取时滤除。
export class ReviewCacheEntry {
  version: number;
  items: WordItem[];
  constructor(version: number, items: WordItem[]) {
    this.version = version;
    this.items = items;
  }
}

// ★ 0.146：知识卡片复习缓存条目——与 ReviewCacheEntry 同模式。
// ★ 0.188.0：缓存改为按消息 ID 永久固定（version 弃用置 0，同 0.187.0 单词库修复）；
// 已删除的卡由 getKnowledgeCards 读取时滤除。
export class KnowledgeReviewCacheEntry {
  version: number;
  items: KnowledgeCard[];
  constructor(version: number, items: KnowledgeCard[]) {
    this.version = version;
    this.items = items;
  }
}

// ★ 0.132：AI 消息占位文字常量（两态：加载中 / 深度思考中）
export const PLACEHOLDER_LOADING = 'AI正在回复中，请稍候...';
export const PLACEHOLDER_THINKING = 'AI 正在深度思考中...';

// ★ 0.222.21：树形连接线每层缩进宽度（vp，与单词库/知识库 TREE_CELL 同款——加词文件夹选择弹窗用）
export const TREE_CELL: number = 14;

// ★ 0.191.0：会话级阅读高度记忆（方案 A）——模块级 Map，页面销毁不丢（同会话内返回画布/切气泡
// 再回来都在），重启清零（像素值跨设备/字体漂移不做持久化，重启走书签/底部兜底）
export const chatScrollMemory: Map<string, number> = new Map();

// ★ 0.234.0：会话级章节折叠状态记忆（msgId → 展开节 index 集）——同 chatScrollMemory 模式：
// 内存级不落盘，切页面回来保留；重启 app 恢复默认前 1/3；不改 content 原文（任务书 §2.1）
export const chatFoldMemory: Map<string, Set<number>> = new Map();

// ★ 0.234.0：动画总开关（任务书 §5.5——代码留常量一键关，出 bug 可秒回退）
export const animOn: boolean = true;

// ★ 0.234.0：消息渲染计划——parseMarkdown 段落展开成 FoldItem 流（文本块/锚点/代码/表格统一承载），
// breath 保底插入后按段重组回 blocks（平铺渲染）+ 章节切分（折叠渲染）双消费
export class RichPlanEntry {
  seg: MdSegment = new MdSegment(0, '');
  blocks: MdBlock[] = [];
}

export class RichPlan {
  entries: RichPlanEntry[] = [];
  sections: FoldSection[] = [];
  sectionable: boolean = false; // initExpandedSet !== null（≥3 节才折叠）
}

// ★ 0.234.0：渲染计划缓存条目（msgId → 计划；流式中 content 变化按长度+首 16 字符失效，
//   防等长异容撞缓存——regenerate 换内容长度恰好相同；设置变化按指纹失效）
export class PlanCacheEntry {
  len: number = -1;
  head: string = '';
  fingerprint: string = '';
  plan: RichPlan = new RichPlan();
}

// ★ 0.214.2：对话页缩放持久化（PersistenceV2 全新 key——跨页面/重启记住）
@ObservedV2
export class ChatFontScaleStore {
  @Trace value: number = 1.0;
}

export function connectChatFontScale(): ChatFontScaleStore {
  return PersistenceV2.connect(ChatFontScaleStore, 'chat-font-scale-v1', () => new ChatFontScaleStore()) as ChatFontScaleStore;
}

// ★ 全屏图片浏览器共享态（拆分自 ChatPage @Local 三件；AppStorageV2 应用级不落盘——
//   宿主页写 store、ImageViewer 组件 connect 同一实例渲染；if 挂载制=每次打开菜单态天然重置）
@ObservedV2
export class ImageViewerStore {
  @Trace visible: boolean = false;
  @Trace index: number = 0;
  @Trace images: string[] = [];
}

export function connectImageViewer(): ImageViewerStore {
  return AppStorageV2.connect(ImageViewerStore, 'image-viewer', () => new ImageViewerStore()) as ImageViewerStore;
}
