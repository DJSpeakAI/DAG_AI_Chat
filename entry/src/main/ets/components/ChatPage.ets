// ============================================================
// ChatPage.ets — 对话页面（气泡内聊天界面）
// ============================================================
// 本文件是用户与 AI 对话的主界面，功能包括：
//   - 消息列表渲染（用户消息纯文本，AI 消息 Markdown 代码块/表格）
//   - 流式接收 AI 回复（打字机效果，边接收边渲染）
//   - 图片发送（多选相册 → Base64 → 发送给 AI）
//   - 图片全屏预览（点击放大、右滑/点击关闭、双指缩放）
//   - 输入框多行自适应（≤5 行自适应高度，>5 行内部滚动）
//   - DAG 链路回溯 + 上下文压缩（超 25 条消息自动摘要）
//   - ★ 0.145：划词翻译——长按气泡文本直接唤起系统选择模式 + 自研悬浮操作栏（翻译|复制|全选），
//     点「翻译」弹 AI 查词浮窗（不建气泡、不进 DAG），可一键加入单词库（独立 PersistenceV2 持久化）
//   - ★ 0.145：AI 消息气泡底部生词复习区（词库随机 2 词，词条式自适应宽度）+ 顶栏单词库入口
//   - ★ 0.146：划词菜单「入知识库」（AI 提炼草稿 → 卡片编辑弹窗二次编辑 → 入库）+ AI 气泡底部知识卡片展示（📖 区分）
//   - ★ 0.181.0：UI 规格化——色值全量收敛 DesignTokens（锁暗紫主题，isDark/浅色分支死代码已清除）
//   - ★ 0.133：下拉发送模式（正常对话/播客模式）+ AI 消息语音朗读（★ 0.139 openspeech 2.0 协议 + 分段流水线，0.143 收尾清理调试链路）
//   - ★ 0.152：内置屏幕圈选标注（第四大产品亮点）——✏️ 画画Icon 截取当前屏幕画面进入涂鸦标注页，
//     标注完成三操作（当前对话导入 / 创建子气泡分支 / 存入知识库）；底栏重排为 ＋ 输入框 ✏️ 发送▾，
//     图片添加/对话模式/回复长度收进发送右侧 ▾ 下拉菜单；底层气泡/上下文链路（10+15）零改动
//
// 技术栈：鸿蒙 ArkUI V2（@ComponentV2 / @Local / @Param / @Computed）
// 导航模式：NavPathStack（从 BBTreeCanvas 气泡画布页面跳入）
// ============================================================

import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI'; // ★ 0.131：收键盘改用 UIContext.getFocusController()（focusControl 不从 @kit.ArkUI 导出）；★ 0.152：截图改走 UIContext.getComponentSnapshot()（APP 内组件快照截屏，无需系统截屏权限，且避开已废弃的 componentSnapshot.get）
import { common } from '@kit.AbilityKit'; // 0.206.0 埋点 getHostContext
import { track } from '../utils/TrackUtil'; // 0.206.0 埋点
import deviceInfo from '@ohos.deviceInfo'; // ★ 0.215.14：设备类型三档（deviceType=phone/tablet/2in1/default，d.ts 实锤）
// ★ 删除未使用 import common（0.122 清理）
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { pasteboard } from '@kit.BasicServicesKit'; // ★ 0.145：pasteboard（划词复制）；★ 0.189.0：BusinessError 随 TTS 管线移除
 import { BubbleNode, ChatMessage, BubbleTree, CurrentBubble, ApiConfig, PersistData, generateMessageId, generateNodeId, serializeBubbleTree, connectApiConfig, AiPreference, connectAiPreference, CanvasModeStore, connectCanvasMode, TabMeta, TabForestStore, connectTabForest, parseTabs, serializeTabs, getRootDisplayName, LearnCountStore, connectLearnCount, KnowledgeCountStore, connectKnowledgeCount, BookmarkEntry, BookmarkData, ChatBookmarkStore, connectChatBookmarks, StatisticsStore, connectStatistics, recordStat } from '../common/ChatModel'; // ★ 0.143：connectApiConfig；★ 0.150：AiPreference（全局设置弹窗）；★ 0.151：画布模式分池保存；★ 0.151-bugfix2：Tab 名同步；★ 0.161：学习数量设置（单词库 ⚙ 设置，两处复习区共用）；★ 0.161.2：知识卡片数量设置（知识库 ⚙ 设置）；★ 0.191.0：BookmarkEntry/BookmarkData/connectChatBookmarks（阅读位置书签）；★ 0.192.0：StatisticsStore/recordStat（学习统计埋点）
 import { PODCAST_PROMPT, SHORT_REPLY_PROMPT, MEDIUM_REPLY_PROMPT, LONG_REPLY_PROMPT, SUMMARY_PROMPT, ENCOURAGE_LIGHT_PROMPT, ENCOURAGE_HEAVY_PROMPT } from '../common/Prompts'; // ★ 0.193.0：prompt 单一真相源（B 项）+摘要结构化（A 项）+鼓励三档
import { WordItem, WordBankStore, WordQueryResult } from '../common/WordModel'; // ★ 0.145：单词库数据模型
import { KnowledgeCard, KnowledgeBankStore, KnowledgeQueryResult, CardImportStore, connectCardImport, AttentionStore, connectAttention, updateAttention, parseTags } from '../common/KnowledgeModel'; // ★ 0.146：知识库数据模型；★ 0.200.0：卡片导入气泡落地消费；★ 0.202.0：注意力标签提取；★ 0.202.1：parseTags（建议标签勾选）
import { image } from '@kit.ImageKit'; // ★ 0.152：截图 PixelMap 打包 base64（componentSnapshot 产物 → data URI）
import { streamChat, queryWord, queryKnowledge, queryKnowledgeFromImage, StreamController, containsChinese, classifyStreamError } from '../utils/ApiClient'; // ★ 0.145：queryWord（AI 查词）；★ 0.146：queryKnowledge（AI 卡片草稿）；★ 0.152：queryKnowledgeFromImage（圈选截图入知识库·多模态提炼）；★ 0.155：containsChinese（划词语言检测）；★ 0.189.0：synthesizeTTS 移除（云端 TTS 取消，改本地引擎）；★ 0.190.6：classifyStreamError（错误场景分类）
import { localStreamChat } from '../utils/LocalLlm'; // ★ 0.216.0：端侧大模型（API Key 未配时的免费离线兜底）
import { connectWordBank, addWordToBank } from '../utils/WordStoreUtil'; // ★ 0.145：单词库持久化与操作；★ 0.187.0：pickRandomWords 移除（选词改走记忆算法）
import { MemoryRating, MemoryItem, pickReviewWords, pickReviewCards, applyPassiveReview, applyRating, formatNextReviewLabel, previewIntervalDays, formatIntervalDays } from '../utils/MemoryAlgorithm'; // ★ 0.187.0：记忆算法（遗忘曲线选词 + 展示即复习 + 3 档评分）；★ 0.188.0：知识库复刻（pickReviewCards + MemoryItem 联合类型）；★ 0.196.0：评分按钮时间预览（previewIntervalDays + formatIntervalDays）
import { connectKnowledgeBank, addKnowledgeCard } from '../utils/KnowledgeStoreUtil'; // ★ 0.146：知识库持久化与操作；★ 0.188.0：pickRandomKnowledgeCards 移除（选卡改走记忆算法）
import { AnnotationPrefStore, AnnotationDraftStore, AnnotationResultStore, connectAnnotationPref, connectAnnotationDraft, connectAnnotationResult } from '../common/AnnotationModel'; // ★ 0.152：屏幕圈选标注（首次提示 flag + 截图草稿 + 结果回传）
import { wordSpeaker, showAccentDialogs } from '../utils/WordSpeaker'; // ★ 0.149：单词发音 TTS 单例；★ 0.189.1：本地引擎化；★ 0.189.2：口音提示弹窗工厂共用
import { localTts } from '../utils/LocalTtsEngine'; // ★ 0.189.0：本地 TTS 引擎（CoreSpeechKit 免费离线，替换火山云端——消息朗读直连）
import { renderMathText } from '../utils/MathRender'; // ★ 0.151：LaTeX 数学符号本地渲染（必须在 parse 层转换，保证划词偏移一致）
import { CodeToken, tokenizeCode } from '../utils/SyntaxHighlight'; // ★ 0.149：代码块语法高亮（MVP 正则分词）
import { AppLifecycleStore } from '../entryability/EntryAbility'; // ★ 0.153：AppLifecycleStore（全局前后台标志，@Monitor 监听切后台中断 AI 提炼）；★ 0.181.0：ThemeStore 移除（锁暗色后色值全量收敛 DesignTokens，getThemeStore 链路删除）
import { upsertCloudData } from '../utils/CloudSyncUtil'; // ★ 0.165.1：云同步桥接（持久化点追加写 RDB 快照行，autoSync 自动上云）
import { GlobalSettingsDialog, isKnownTextOnlyModel } from './GlobalSettingsDialog'; // ★ 0.150：全局设置弹窗（顶栏 ⚙ 唤起，Tab1 API 配置 + Tab2 AI 偏好）；★ 0.190.2：加 isKnownTextOnlyModel（纯文本模型发图拦截）
// ★ 0.181.0：UI 规格化——散落色值/isDark 三元收敛到 DesignTokens（0.166.3 锁暗色后浅色分支是死代码）
import { WindowMode, connectWindowMode } from '../common/WindowMode'; // ★ 0.196.4：窗口宽度模式共享真相源（分屏/悬浮窗切手机布局）
import { BG_APP, BG_CANVAS, SURFACE_NODE, SURFACE_HOVER, SURFACE_SOFT, BRAND_PRIMARY, BRAND_SECONDARY, TEXT_PRIMARY, TEXT_SECONDARY, TEXT_TERTIARY, STROKE_CARD, STROKE_BRAND, DANGER, CODE_KEYWORD, CODE_STRING, CODE_COMMENT, CODE_NUMBER, CODE_TEXT, OVERLAY, OVERLAY_LIGHT, RADIUS_NAV, RADIUS_NODE, RADIUS_CONTROL, FONT_SIZE_SCREEN_TITLE, FONT_INTER, FONT_INTER_SEMIBOLD } from '../common/DesignTokens'; // ★ 0.195.0：加 BG_APP（根底色补齐）

// ★ 新增：Markdown 解析段（0.121）
class MdSegment {
  type: number; // 0=普通文本, 1=代码块, 2=表格
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
class ReviewCacheEntry {
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
class KnowledgeReviewCacheEntry {
  version: number;
  items: KnowledgeCard[];
  constructor(version: number, items: KnowledgeCard[]) {
    this.version = version;
    this.items = items;
  }
}

// ★ 0.132：AI 消息占位文字常量（两态：加载中 / 深度思考中）
// 注意：PLACEHOLDER_LOADING 字面值与历史持久化数据一致，不可改动（旧数据的过滤判断依赖它）
const PLACEHOLDER_LOADING = 'AI正在回复中，请稍候...';
const PLACEHOLDER_THINKING = 'AI 正在深度思考中...';

// ★ 0.191.0：会话级阅读高度记忆（方案 A）——模块级 Map，页面销毁不丢（同会话内返回画布/切气泡
// 再回来都在），重启清零（像素值跨设备/字体漂移不做持久化，重启走书签/底部兜底）
const chatScrollMemory: Map<string, number> = new Map();

// ============================================================
// ★ 0.190.5：三点跳动等待动画（用户选定方案：非静态等待，三点滚动表示正在等 AI 回复）
// ============================================================
// 0.160.2 秒表（⏱ 读秒）失败教训=页级定时器难清理；本组件**自管定时器**——
// aboutToAppear 启动 / aboutToDisappear 必然清理（组件随占位气泡卸载），零泄漏。
// phase 0→1→2 循环点亮三个点，属性动画 300ms 平滑过渡大小与颜色。
@ComponentV2
export struct WaitingDots { // ★ 0.196.2：export——ReviewPage 完成页「总结正在生成」复用（0.190.5 原创组件）
  @Local phase: number = 0;
  private timerId: number = -1;

  aboutToAppear(): void {
    console.info(`DAGAI-DEV deviceType=${deviceInfo.deviceType}`); // ★ 0.215.14：三档判定实锤日志（装机后拉 hilog 验证 Matebook 实际值）
    this.timerId = setInterval(() => {
      this.phase = (this.phase + 1) % 3;
    }, 400);
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  build() {
    Row({ space: 4 }) {
      Text('●')
        .fontSize(this.phase === 0 ? 10 : 6)
        .fontColor(this.phase === 0 ? BRAND_SECONDARY : TEXT_TERTIARY)
        .animation({ duration: 300, curve: Curve.EaseInOut })
      Text('●')
        .fontSize(this.phase === 1 ? 10 : 6)
        .fontColor(this.phase === 1 ? BRAND_SECONDARY : TEXT_TERTIARY)
        .animation({ duration: 300, curve: Curve.EaseInOut })
      Text('●')
        .fontSize(this.phase === 2 ? 10 : 6)
        .fontColor(this.phase === 2 ? BRAND_SECONDARY : TEXT_TERTIARY)
        .animation({ duration: 300, curve: Curve.EaseInOut })
    }
    .height(14)
    .alignItems(VerticalAlign.Center)
  }
}

// ★ 0.133：播客模式系统 prompt（发送时临时追加到消息末尾，不持久化、不进入后续上下文）
// ★ 0.193.0：迁入 Prompts.ts

// ★ 0.144：回复长度 prompt 约束（发送时以 system 消息临时插入，不持久化；档位状态仅内存，重启恢复默认「中」）
// ★ 0.193.0：全部 prompt 迁入 common/Prompts.ts 单一真相源（B 项集中管理），本文件只 import

// ★ 0.189.0：TTS_MAX_SEGMENT_LEN 已随云端管线移除——分段逻辑迁入 LocalTtsEngine（280 字/段）

// ★ 0.191.0：带书签标志的代码 token 渲染单元——书签区间与语法 token 求交集拆分，
// marked 段保留语法色 + 紫色下划线（划词级标记在代码块内的等效实现）
class MarkedToken {
  text: string;
  kind: number;
  marked: boolean;
  constructor(text: string, kind: number, marked: boolean) {
    this.text = text;
    this.kind = kind;
    this.marked = marked;
  }
}

// ★ 0.214.2：对话页缩放持久化（PersistenceV2 全新 key——跨页面/重启记住）
@ObservedV2
export class ChatFontScaleStore {
  @Trace value: number = 1.0;
}

export function connectChatFontScale(): ChatFontScaleStore {
  return PersistenceV2.connect(ChatFontScaleStore, 'chat-font-scale-v1', () => new ChatFontScaleStore()) as ChatFontScaleStore;
}

// ★ 新增：代码块组件，支持自动换行/横向滚动切换（0.122）
@ComponentV2
struct CodeBlockView {
  @Param content: string = '';   // 代码内容
  @Param lang: string = '';      // ★ 0.149：语言标识（parseMarkdown 已提取；空 = plaintext 不高亮）
  @Param fontScale: number = 1.0; // ★ 0.214.0：字号缩放透传（父组件捏合；工具栏/标签等辅助元素不缩）
  @Local wrap: boolean = true;    // 默认开启自动换行
  @Event onZoom: (content: string, lang: string) => void =
    (content: string, lang: string) => {}; // ★ 0.153：放大回调（父组件打开全屏代码弹窗）；★ 0.149 加传 lang
  // ★ 0.156：划词桥接——代码块 Text 复用 ChatPage 的选择工具栏（翻译/入知识库/复制/全选）与状态链路
  @Param textKey: string = '';                                    // 划词 key（父组件生成，如 `${msgId}|c${segIdx}`）
  @Param selController: TextController | undefined = undefined;   // 父组件注册的 TextController（关闭选择菜单用）
  @Param selectAllKey: string = '';                               // 全选受控态（`${key}|${nonce}`，命中时本块全选）
  // ★ 0.157 崩溃修复：弃用 @BuilderParam 传父组件工具栏——@Builder 经 @BuilderParam 传入后在子组件上下文执行，
  // this 不再指向 ChatPage，工具栏内父组件状态变 undefined → 长按代码块 TypeError 崩溃（真机实证）。
  // 改为：本组件自带工具栏 UI（★ 0.181.0 主题色收敛 DesignTokens 常量），按钮动作经 @Event 回调父组件（this 归位正确）
  @Event onTranslate: () => void = () => {};       // 翻译按钮（父组件 onToolbarTranslate）
  @Event onAddKnowledge: () => void = () => {};    // 入知识库按钮（父组件 onToolbarAddKnowledge）
  @Event onCopy: () => void = () => {};            // 复制按钮（父组件 onToolbarCopy）
  @Event onSelectAll: () => void = () => {};       // 全选按钮（父组件 onToolbarSelectAll）
  @Event onMenuAppear: (key: string) => void = (key: string) => {}; // 菜单弹出（父组件记录 selKey）
  @Event onMenuDisappear: () => void = () => {};                    // 菜单关闭（父组件清理选中状态）
  @Event onSelChange: (key: string, content: string, start: number, end: number) => void =
    (key: string, content: string, start: number, end: number) => {}; // 选中变化（父组件按偏移截取选中文本）
  // ★ 0.191.0：划词级书签——父组件传入本块书签偏移（-1=无）与工具栏标记按钮状态
  @Param bmStart: number = -1;
  @Param bmEnd: number = -1;
  @Param bookmarkBtnLabel: string = '标记'; // 按钮文案（标记/取消标记，父组件按划选首字符判定）
  @Event onBookmark: () => void = () => {}; // 标记/取消标记按钮（父组件 onToolbarBookmark）

  // ★ 0.149：着色 token 序列（@Computed 依赖 content/lang 自动重算；流式增量输出实时刷新高亮）
  // tokenizeCode 返回 null（语言不支持/超长兜底）时降级为单段全文本——渲染层只有一条 Span 拼接路径
  @Computed
  get renderTokens(): CodeToken[] {
    const tokens = tokenizeCode(this.content, this.lang);
    if (tokens === null) {
      return [new CodeToken(this.content, 0)];
    }
    return tokens;
  }

  // ★ 0.191.0：书签区间与语法 token 求交集拆分——marked 段渲染时加紫色下划线（保留语法色）
  // 偏移越界（书签过期/内容变化）时交集为空，自然降级为无标记渲染
  @Computed
  get markedTokens(): MarkedToken[] {
    const tokens = this.renderTokens;
    if (this.bmStart < 0 || this.bmEnd <= this.bmStart) {
      const plain: MarkedToken[] = [];
      for (const t of tokens) {
        plain.push(new MarkedToken(t.text, t.kind, false));
      }
      return plain;
    }
    const out: MarkedToken[] = [];
    let pos = 0;
    for (const t of tokens) {
      const tStart = pos;
      const tEnd = pos + t.text.length;
      pos = tEnd;
      if (tEnd <= this.bmStart || tStart >= this.bmEnd) {
        out.push(new MarkedToken(t.text, t.kind, false));
        continue;
      }
      if (tStart < this.bmStart) {
        out.push(new MarkedToken(t.text.substring(0, this.bmStart - tStart), t.kind, false));
      }
      const mStart = tStart > this.bmStart ? tStart : this.bmStart;
      const mEnd = tEnd < this.bmEnd ? tEnd : this.bmEnd;
      out.push(new MarkedToken(t.text.substring(mStart - tStart, mEnd - tStart), t.kind, true));
      if (tEnd > this.bmEnd) {
        out.push(new MarkedToken(t.text.substring(this.bmEnd - tStart), t.kind, false));
      }
    }
    return out;
  }

  // ★ 0.149：token 配色；★ 0.181.0 收敛 DesignTokens 语义常量（关键字蓝/字符串绿/注释灰/数字橙）
  tokenColor(kind: number): string {
    if (kind === 1) {
      return CODE_KEYWORD; // 关键字：蓝
    }
    if (kind === 2) {
      return CODE_STRING; // 字符串：绿
    }
    if (kind === 3) {
      return CODE_COMMENT; // 注释：灰
    }
    if (kind === 4) {
      return CODE_NUMBER; // 数字：橙
    }
    return CODE_TEXT;   // 普通代码文本：底色对应文字色
  }

  // toast 轻提示（showToast 可能抛异常，统一包裹消除编译告警，失败不影响主流程）
  showToastSafe(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (e) {
      // toast 失败静默忽略
    }
  }

  // ★ 0.157：代码块专用选择工具栏——UI 与 ChatPage.SelectionToolbar 保持一致（样式改动两处同步），
  // 主题色用 DesignTokens 常量、按钮动作走 @Event，规避 @BuilderParam 的 this 上下文丢失
  @Builder
  codeToolbar() {
    Row() {
      Text('翻译')
        .fontSize(Math.round(14 * this.fontScale * 10) / 10)
        .fontColor(BRAND_SECONDARY)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.onTranslate();
        })
      Divider()
        .vertical(true)
        .height(16)
        .color(STROKE_CARD)
      Text('入知识库')
        .fontSize(Math.round(14 * this.fontScale * 10) / 10)
        .fontColor(BRAND_SECONDARY)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.onAddKnowledge();
        })
      Divider()
        .vertical(true)
        .height(16)
        .color(STROKE_CARD)
      // ★ 0.191.0：标记/取消标记（与主工具栏同位——复制左边；文案由父组件按划选首字符判定）
      Text(this.bookmarkBtnLabel)
        .fontSize(Math.round(14 * this.fontScale * 10) / 10)
        .fontColor(TEXT_PRIMARY)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.onBookmark();
        })
      Divider()
        .vertical(true)
        .height(16)
        .color(STROKE_CARD)
      Text('复制')
        .fontSize(Math.round(14 * this.fontScale * 10) / 10)
        .fontColor(TEXT_PRIMARY)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.onCopy();
        })
      Divider()
        .vertical(true)
        .height(16)
        .color(STROKE_CARD)
      Text('全选')
        .fontSize(Math.round(14 * this.fontScale * 10) / 10)
        .fontColor(TEXT_PRIMARY)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.onSelectAll();
        })
    }
    .backgroundColor(SURFACE_NODE)
    .borderRadius(RADIUS_CONTROL)
    .border({ width: 0.5, color: STROKE_CARD })
    .shadow({ radius: 12, color: 'rgba(0,0,0,0.25)', offsetX: 0, offsetY: 4 })
  }

  build() {
    Column() {
      // ★ 按钮栏：左对齐 + 小字体 + 醒目样式（0.122 优化；0.153 拆分为两个独立按钮：换行切换 + 放大）
      // ★ 0.191.0：⧉ 全部复制按钮移除（用户定稿：划词工具栏已有「复制」，顶栏复制冗余）
      // ★ 0.191.0 定稿：换行/放大全换 svg 矢量图标（wrap/nowrap/zoom.svg 紫色 18×18）——
      //   字符图标根治（↩ 在鸿蒙被 emoji 化渲染成蓝底白箭头与 ⤢ 不统一，用户实测；⤢ 字形基线偏移居中难调）；
      //   Row({ space: 8 }) 间距统一（用户指示：图2 顶栏间距不统一重新排列）
      Row({ space: 8 }) {
        // ★ 0.149：语言标签（无语言标识的代码块标记为 plaintext，不高亮）
        Text(this.lang.length > 0 ? this.lang : 'plaintext')
          .fontSize(11)
          .fontColor(TEXT_TERTIARY)

        // 换行切换按钮：换行模式 wrap.svg（下弯左箭头），滚动模式 nowrap.svg（双向箭头）
        // ★ 0.191.0 定稿：按钮样式=深紫底+方框+圆角；★ 缩小 20×18/图标14（用户指示大了不美观）
        Row() {
          Image(this.wrap ? $r('app.media.wrap') : $r('app.media.nowrap'))
            .width(14)
            .height(14)
        }
        .width(20)
        .height(18)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .borderRadius(4)
        .backgroundColor(SURFACE_HOVER)
        .border({ width: 0.5, color: STROKE_BRAND })
        .onClick(() => {
          this.wrap = !this.wrap;
        })

        // ★ 0.153：放大按钮——打开全屏代码查看弹窗（父组件渲染）；zoom.svg=⤢ 对角双箭头矢量版；同款框样式
        Row() {
          Image($r('app.media.zoom'))
            .width(14)
            .height(14)
        }
        .width(20)
        .height(18)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .borderRadius(4)
        .backgroundColor(SURFACE_HOVER)
        .border({ width: 0.5, color: STROKE_BRAND })
        .onClick(() => {
          this.onZoom(this.content, this.lang); // ★ 0.149：加传 lang（放大弹窗同步高亮）
        })
      }
      .margin({ top: 4, bottom: 2 })

      // 代码内容：根据 wrap 状态切换渲染模式
      if (this.wrap) {
        // ★ 0.154：去掉 width('100%')——气泡链多层自适应父容器下百分比宽度解析异常，
        // 导致代码块比气泡内容区宽、右侧显示被挡；改为无 width + 父约束折行
        //（与气泡内普通文本段同模式：长代码自动折行且始终在气泡内，短代码背景随内容自适应）
        // ★ 0.156：划词五件套——与普通文本段同模式（copyOption + 自研菜单 + 选中回调 + 全选受控）
        // ★ 0.149：语法高亮——Text 内 ForEach Span 按着色 token 渲染；token 顺序拼接与 content
        // 完全一致，划词/全选/复制偏移不错位；keyGenerator 纳入内容长度，流式更新触发 Span 重建
        Text('', { controller: this.selController }) {
          ForEach(this.markedTokens, (t: MarkedToken, i: number) => {
            Span(t.text)
              .fontColor(this.tokenColor(t.kind))
              // ★ 0.191.0：书签 marked 段紫色下划线（保留语法色）
              .decoration(t.marked ? { type: TextDecorationType.Underline, color: BRAND_SECONDARY } : { type: TextDecorationType.None })
          }, (t: MarkedToken, i: number) => `${i}|${t.kind}|${t.text.length}|${t.marked}`)
        }
          .fontSize(14)
          .fontFamily('monospace')
          .fontColor(CODE_TEXT)
          .padding(10)
          .backgroundColor(BG_CANVAS)
          .borderRadius(RADIUS_CONTROL)
          .copyOption(CopyOptions.LocalDevice)
          .bindSelectionMenu(TextSpanType.TEXT, this.codeToolbar, TextResponseType.LONG_PRESS, {
            onAppear: () => {
              this.onMenuAppear(this.textKey);
            },
            onDisappear: () => {
              this.onMenuDisappear();
            }
          })
          .onTextSelectionChange((start: number, end: number) => {
            this.onSelChange(this.textKey, this.content, start, end);
          })
          .selection(
            this.selectAllKey.startsWith(`${this.textKey}|`) ? 0 : 1,
            this.selectAllKey.startsWith(`${this.textKey}|`) ? this.content.length : 0
          )
      } else {
        // 滚动模式：横向滚动查看长代码
        Scroll() {
          // ★ 0.156：划词五件套——同 wrap 模式（长按进入选择，拖动与横向滚动手势互不冲突）
          // ★ 0.149：语法高亮——同 wrap 模式 ForEach Span 着色渲染
          Text('', { controller: this.selController }) {
            ForEach(this.markedTokens, (t: MarkedToken, i: number) => {
              Span(t.text)
                .fontColor(this.tokenColor(t.kind))
                // ★ 0.191.0：书签 marked 段紫色下划线（保留语法色）
                .decoration(t.marked ? { type: TextDecorationType.Underline, color: BRAND_SECONDARY } : { type: TextDecorationType.None })
            }, (t: MarkedToken, i: number) => `${i}|${t.kind}|${t.text.length}|${t.marked}`)
          }
            .fontSize(14)
            .fontFamily('monospace')
            .fontColor(CODE_TEXT)
            .padding(10)
            .backgroundColor(BG_CANVAS)
            .borderRadius(RADIUS_CONTROL)
            .copyOption(CopyOptions.LocalDevice)
            .bindSelectionMenu(TextSpanType.TEXT, this.codeToolbar, TextResponseType.LONG_PRESS, {
              onAppear: () => {
                this.onMenuAppear(this.textKey);
              },
              onDisappear: () => {
                this.onMenuDisappear();
              }
            })
            .onTextSelectionChange((start: number, end: number) => {
              this.onSelChange(this.textKey, this.content, start, end);
            })
            .selection(
              this.selectAllKey.startsWith(`${this.textKey}|`) ? 0 : 1,
              this.selectAllKey.startsWith(`${this.textKey}|`) ? this.content.length : 0
            )
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Auto)
        // ★ 0.154：width('100%') 改为约束 maxWidth——视口被钳制在气泡内容区内，
        // 长代码横向滚动正常、不再向右溢出气泡
        .constraintSize({ maxWidth: '100%' })
      }
    }
    .margin({ top: 6, bottom: 6 })
    .alignItems(HorizontalAlign.Start) // ★ 按钮左对齐（0.122 优化）
  }
}

// 对话页面 — V2 全量迁移
@ComponentV2
export struct ChatPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  store: BubbleTree = AppStorageV2.connect(BubbleTree, 'bubble-tree', () => new BubbleTree()) as BubbleTree;
  persistData: PersistData = PersistenceV2.connect(PersistData, 'persist-data', () => new PersistData()) as PersistData;
  currentBubbleStore: CurrentBubble = AppStorageV2.connect(CurrentBubble, 'current-bubble', () => new CurrentBubble()) as CurrentBubble;
  apiConfig: ApiConfig = connectApiConfig(); // ★ 0.143：换 key 'api-config-v2'（旧快照无 audioKey 字段致新增属性不落盘，工厂迁移历史配置）
  bookmarkStore: ChatBookmarkStore = connectChatBookmarks(); // ★ 0.191.0：阅读书签持久化（方案 B，跨重启）
  @Local bookmarkCache: BookmarkEntry | null = null; // ★ 0.191.0：本气泡书签缓存（渲染期高频查询免逐段 JSON 解析）
  aiPreference: AiPreference = connectAiPreference(); // ★ 0.150：AI 偏好（称呼 + 鼓励开关，独立 key 'ai-preference-v1'）
  statStore: StatisticsStore = connectStatistics(); // ★ 0.192.0：学习统计（只增不减，删除消息/气泡不影响已统计数据）
  canvasModeStore: CanvasModeStore = connectCanvasMode(); // ★ 0.151：画布模式（'flat'/'tabs'，独立 key 'canvas-mode-v1'）
  tabForest: TabForestStore = connectTabForest();         // ★ 0.151：Tab 池（tabsJson + activeTabId，独立 key 'tab-forest-v1'）
  @Local inputText: string = '';
  @Local isLoading: boolean = false;
  // ★ 0.162：分支切换过渡动画状态——addBubble 切换气泡时消息区先淡出再淡入（约 440ms），
  // 让用户明确感知「跳到了新的空白消息页」（原瞬间清空重载刷屏过快、空页面时无感知）
  @Local msgAreaOpacity: number = 1;       // 消息区透明度（1=不透明；动画期间 0↔1 补间）
  @Local branchAnimating: boolean = false; // 分支切换动画进行中（防抖：播完前忽略重复点击）
  @Local pendingImages: string[] = [];
  // 全屏图片浏览器状态
  @Local imageViewerVisible: boolean = false;
  @Local imageViewerIndex: number = 0;
  @Local imageViewerImages: string[] = [];
  // ★ 0.145：划词翻译状态（替代原长按菜单/文本预览/删除确认——旧二级弹窗整体移除）
   @Local selText: string = '';            // 当前选中文本（onTextSelectionChange 时从对应 Text 内容截取）
   @Local selStart: number = -1;           // ★ 0.191.0：选中起始偏移（划词级书签用；-1=无有效选中）
   @Local selEnd: number = -1;             // ★ 0.191.0：选中结束偏移
   // ★ 0.191.0：粘性选中区间（不被 clearSelectionState 清理）——表格横向 Scroll 内拖选时菜单消失重弹
   // 丢失 selStart/selEnd，点「标记」误报「请划选文字」；同 key 兜底恢复（见 effectiveSelStart）
   private stickySelKey: string = '';
   private stickyStart: number = -1;
   private stickyEnd: number = -1;
  @Local selKey: string = '';             // 当前激活选择的 Text 标识（`${msgId}|u` 用户消息 / `${msgId}|${segIdx}` AI 段）
  @Local selectAllKey: string = '';       // 全选受控态标识（`${selKey}|${nonce}`，nonce 递增确保重复点击仍触发属性重应用）
  @Local selectAllNonce: number = 0;      // 全选触发计数（配合 selectAllKey）
  @Local wordPopupVisible: boolean = false;   // 翻译浮窗可见
  @Local wordPopupQuery: string = '';         // 浮窗展示的查询原文
  @Local wordPopupLoading: boolean = false;   // AI 查词进行中
  @Local wordPopupResult: WordQueryResult | null = null; // 查词结果（null=未出结果）
  @Local wordPopupError: string = '';         // 查词错误信息
  @Local wordPopupAdded: boolean = false;     // 当前结果已加入单词库（按钮转「已加入」防重复）
  @Local wordExistsTip: boolean = false;      // 「单词已存在」提示（重复添加时显示）
  // ★ 0.150：删除确认弹窗状态（防误触；「不再提示」仅本次对话会话内生效，重进对话页重置）
  @Local deleteConfirmVisible: boolean = false; // 确认弹窗可见
  @Local deleteConfirmMessageId: string = '';   // 待删除的消息 ID
  @Local deleteConfirmNoAsk: boolean = false;   // 弹窗内「不再提示」勾选框当前状态（每次打开复位）
  @Local deleteSkipConfirm: boolean = false;    // 本次会话内已勾选「不再提示」（aboutToAppear 重置）
  wordBank: WordBankStore = connectWordBank(); // ★ 0.145：单词库（独立 PersistenceV2 key，与气泡树持久化隔离）
  learnCountStore: LearnCountStore = connectLearnCount(); // ★ 0.161：学习数量（单词库 ⚙ 设置，默认 2；驱动气泡复习区+提炼弹窗复习区词条数）
  knowledgeCountStore: KnowledgeCountStore = connectKnowledgeCount(); // ★ 0.161.2：知识卡片数量（知识库 ⚙ 设置，默认 1 保持现状；驱动气泡复习区+提炼弹窗复习区卡片数）
  private textControllers: Map<string, TextController> = new Map(); // 每个 Text 独立 controller（关闭选择菜单用）
  private wordQueryController: StreamController | null = null;      // 进行中的查词请求（浮窗关闭时取消）
  private reviewCache: Map<string, ReviewCacheEntry> = new Map();   // 生词复习缓存（msgId → 随机词组）
  // ★ 0.146：知识库卡片编辑弹窗状态（AI 生成草稿 → 用户编辑确认 → 入库；AI 不直接入库）
  @Local knowledgeEditVisible: boolean = false;  // 编辑弹窗可见
  @Local knowledgeCardTitle: string = '';        // 标题输入框内容（AI 草稿自动填充，可自由编辑）
  @Local knowledgeSuggestedTags: string[] = [];  // ★ 0.202.1：AI 建议标签（弹窗勾选采纳）
  @Local knowledgeSelectedTags: string = '';     // ★ 0.202.1：已勾选标签（逗号分隔，随卡保存）
  @Local knowledgeCardDefinition: string = '';   // 定义输入框内容（AI 草稿自动填充，可自由编辑）
  @Local knowledgeImageUri: string = '';         // 卡片配图（base64 data URI；'' = 无图片，图片区不渲染）
  @Local knowledgeEditLoading: boolean = false;  // AI 提炼进行中
  @Local knowledgeEditError: string = '';        // AI 提炼错误信息（输入框仍可手动填写）
  knowledgeBank: KnowledgeBankStore = connectKnowledgeBank(); // ★ 0.146：知识库（独立 PersistenceV2 key，与气泡树/单词库隔离）
  attention: AttentionStore = connectAttention(); // ★ 0.202.0：注意力标签热度（发消息时提取——艾宾浩斯 2.0）
  private knowledgeQueryController: StreamController | null = null; // 进行中的提炼请求（弹窗关闭时取消）
  private knowledgeReviewCache: Map<string, KnowledgeReviewCacheEntry> = new Map(); // 复习区知识卡片缓存
  // ★ 0.153：提炼弹窗秒表——发起请求从 0 计数每秒 +1，弹窗标题展示「AI提炼中：XX秒」；
  // 成功/取消/报错/超时/切后台立刻停止清零；180s 业务超时自动 abort；组件销毁必须清除防泄漏
  @Local knowledgeExtractSeconds: number = 0;
  private knowledgeExtractTimer: number = -1; // 计时器 ID（-1 = 未启动）
  // ★ 0.160.2：AI 回复秒表已按用户决定整体移除（多轮修复未达预期，回复区保持干净）；
  // 提炼弹窗秒表（上方 knowledgeExtractSeconds 一套）保留勿动。
  // ★ 0.153：全局前后台标志（EntryAbility onForeground/onBackground 维护）——
  // NavDestination 无 onPageHide 生命周期，借 @Monitor 监听此标志实现切后台中断提炼
  @Local appLifecycle: AppLifecycleStore = AppStorageV2.connect(AppLifecycleStore, 'app-lifecycle', () => new AppLifecycleStore()) as AppLifecycleStore;
  // ★ 0.160：弹窗内复习区——AI 提炼等待期顺便学习（词库 N 词 + 知识库 M 卡，N/M 由 ⚙ 设置驱动）；
  // 弹窗打开时抽一次固定（渲染不重抽、不闪烁），样式与气泡底部复习区一致
  @Local editReviewWords: WordItem[] = [];

  // ★ 0.187.0：复习评分交互状态——key = `${messageId}|${wordId}`（气泡区）/ `edit|${wordId}`（提炼弹窗）
  @Local reviewExpandKey: string = '';                    // 当前展开评分按钮的词条（空 = 无）
  @Local reviewRatedMap: Map<string, string> = new Map(); // 已评分词条 key → 评分（hard/good/easy；整体替换触发 V2 刷新）
  @Local editReviewCards: KnowledgeCard[] = [];
  // ★ 0.133：发送模式下拉（'normal' 正常对话 | 'podcast' 播客模式）
  @Local sendMode: string = 'normal';
  // ★ 0.144：回复长度下拉（'short' | 'medium' | 'long'，默认中回复；仅内存状态，重启恢复默认）
  @Local replyLengthMode: string = 'medium';
  // ★ 0.151-D：⋮ 三点气泡菜单开关（合并原模式下拉 0.133 + 长度下拉 0.144 两个面板为一棵树形菜单）
  @Local modeMenuOpen: boolean = false;
  // ★ 0.153：代码块放大弹窗状态（代码块左上角「放大」按钮打开，全屏查看 + 换行切换）
  @Local codeZoomVisible: boolean = false;
  @Local codeZoomContent: string = '';
  @Local codeZoomLang: string = '';       // ★ 0.149：放大弹窗代码语言（与气泡内高亮一致）
  @Local codeZoomWrap: boolean = true;    // 放大视图默认换行（与气泡内代码块默认一致）
  // ★ 0.153：表格放大弹窗状态（表格默认不换行 + 固定列宽对齐；放大视图支持换行切换）
  @Local tableZoomVisible: boolean = false;
  @Local tableZoomHeader: string[] = [];
  @Local tableZoomRows: string[][] = [];
  @Local tableZoomWrap: boolean = false;  // 放大视图默认不换行（与气泡内表格默认一致）
  // ★ 0.150：全局设置弹窗状态（顶栏 ⚙ 唤起；遮罩不关闭，✕/返回键走弹窗内未保存确认）
  @Local globalSettingsVisible: boolean = false;
  @Local globalSettingsCloseReq: number = 0; // 外部请求关闭计数器（handleBack 递增 → 弹窗 @Monitor 触发 requestClose）
  // ★ 0.133：语音朗读状态（全局单播放源，驱动喇叭图标三态）
  @Local playingMessageId: string = '';    // 正在播放的消息 ID（🔊 态）
  @Local ttsLoadingMessageId: string = ''; // TTS 请求/等待中的消息 ID（⏳ 态，防重复点击）
  // ★ 0.195.0：大屏断点（≥600vp）——返回箭头大屏专属（小屏侧滑返回）
  // ★ 0.196.4：改读窗口宽度共享真相源（WindowMode）——分屏/悬浮窗实时切手机布局
  windowMode: WindowMode = connectWindowMode();
  @Computed get isTablet(): boolean {
    return this.windowMode.isTablet;
  }
  // ★ 0.189.0：云端分段管线状态（ttsSegments/请求播放索引/base64缓存/AVPlayer/临时文件/
  // 代际号）全部移除——本地引擎在 LocalTtsEngine 内部管理分段与排队，会话回调自动失效
  private scroller: Scroller = new Scroller();
  private streamController: StreamController | null = null;
  // ★ 0.152：屏幕圈选标注状态
  annotationPref: AnnotationPrefStore = connectAnnotationPref();       // 首次使用提示 flag（PersistenceV2 独立 key，跨重启只提示一次）
  annotationDraft: AnnotationDraftStore = connectAnnotationDraft();   // 截图草稿（ChatPage → AnnotationPage）
  annotationResult: AnnotationResultStore = connectAnnotationResult(); // 标注结果（AnnotationPage → ChatPage，onShown 消费）
  cardImport: CardImportStore = connectCardImport(); // ★ 0.200.0：知识卡片导入（画布确认后 → 本页落地，onShown 消费）
  @Local importArrived: number = 1; // ★ 0.200.0：导入落地渐显（常态 1；落地瞬间 0→1 的 300ms 动画——L3 末拍）
  @Local annotationNotifyVisible: boolean = false; // 首次使用说明弹窗可见

  // ★ 0.181.0：getThemeStore 已删除——锁暗色后 ChatPage 色值全量收敛 DesignTokens（UI_GUIDELINES.md 单一来源）

  // ★ 0.153：估算表格各列固定宽度（vp）——按每列最大内容长度计算，保证表头/数据行列边界严格对齐
  // fontSize 14 下中文≈14vp/字符、英文≈7.5vp/字符，按中文保守估算：列偏宽不错位不截断，超宽靠横向滚动兜底
  getTableColWidths(header: string[], rows: string[][]): number[] {
    let colCount = header.length;
    for (const row of rows) {
      if (row.length > colCount) {
        colCount = row.length;
      }
    }
    const widths: number[] = [];
    for (let ci = 0; ci < colCount; ci++) {
      let maxLen = ci < header.length ? header[ci].length : 0;
      for (const row of rows) {
        if (ci < row.length && row[ci].length > maxLen) {
          maxLen = row[ci].length;
        }
      }
      // 每字符 14vp + padding 16vp，clamp [48, 240]：窄列保底、超宽列上限防单列独占屏宽
      widths.push(Math.min(240, Math.max(48, maxLen * 14 + 16)));
    }
    return widths;
  }

  // ★ 0.153：打开代码块放大弹窗（换行模式重置为 true，与气泡内代码块默认一致）
  openCodeZoom(content: string, lang: string): void {
    this.codeZoomContent = content;
    this.codeZoomLang = lang; // ★ 0.149：记录语言，放大弹窗同步语法高亮
    this.codeZoomWrap = true;
    this.codeZoomVisible = true;
  }

  // ★ 0.149：放大弹窗代码 token 化（与气泡内 CodeBlockView.renderTokens 同逻辑；
  // null 时降级单段全文本单色渲染；codeZoomContent 为 @Local，变化触发 build 重跑自动重算）
  zoomTokens(): CodeToken[] {
    const tokens = tokenizeCode(this.codeZoomContent, this.codeZoomLang);
    if (tokens === null) {
      return [new CodeToken(this.codeZoomContent, 0)];
    }
    return tokens;
  }

  // ★ 0.181.0：放大弹窗 token 配色收敛 DesignTokens（锁暗色无浅色分支，与 CodeBlockView.tokenColor 同源常量）
  codeTokenColor(kind: number): string {
    if (kind === 1) {
      return CODE_KEYWORD; // 关键字：蓝
    }
    if (kind === 2) {
      return CODE_STRING; // 字符串：绿
    }
    if (kind === 3) {
      return CODE_COMMENT; // 注释：灰
    }
    if (kind === 4) {
      return CODE_NUMBER; // 数字：橙
    }
    return CODE_TEXT;   // 普通代码文本
  }

  // ★ 0.153：打开表格放大弹窗（换行模式重置为 false，与气泡内表格默认一致）
  openTableZoom(header: string[], rows: string[][]): void {
    this.tableZoomHeader = header;
    this.tableZoomRows = rows;
    this.tableZoomWrap = false;
    this.tableZoomVisible = true;
  }

  // V2 @Computed：从 store 读取当前气泡 ID，自动响应式
  @Computed
  get currentBubbleId(): string {
    return this.currentBubbleStore.nodeID;
  }

  // V2 @Computed：自动响应式，不需要手动同步
  @Computed
  get currentBubble(): BubbleNode | undefined {
    return this.store.nodeList.find(b => b.nodeID === this.currentBubbleId);
  }

  @Computed
  get currentMessages(): ChatMessage[] {
    return this.currentBubble?.messages ?? [];
  }

  // ★ 0.195.0：输入框动态高度计算整体废弃（原 0.118 条数制 → 0.195.0 measureTextSize 软换行制，
  //   真机密度单位翻车 1 字跳 3 行）——改 TextArea 原生自适应 + constraintSize 封顶（标注页同款），
  //   inputAreaHeight getter / inputAreaWidth 字段 / onAreaChange / measure import 随删

  // ★ 新增：Markdown 解析，拆分为普通文本/代码块/表格段（0.121）
  parseMarkdown(content: string): MdSegment[] {
    const segments: MdSegment[] = [];
    const lines: string[] = content.split('\n');
    let i = 0;
    let textBuffer: string[] = [];

    const flushText = () => {
      if (textBuffer.length > 0) {
        // ★ 0.151：parse 层做 LaTeX 数学符号转换，显示/划词/复制三者天然一致
        segments.push(new MdSegment(0, renderMathText(textBuffer.join('\n'))));
        textBuffer = [];
      }
    };

    while (i < lines.length) {
      const line = lines[i];
      const trimmed = line.trim();

      // 代码块：```lang ... ```
      if (trimmed.startsWith('```')) {
        flushText();
        const lang = trimmed.substring(3).trim();
        i++;
        const codeLines: string[] = [];
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          codeLines.push(lines[i]);
          i++;
        }
        segments.push(new MdSegment(1, codeLines.join('\n'), lang));
        i++; // 跳过闭合 ```
        continue;
      }

      // 表格：| header | ... | 后跟 |---|---|
      if (trimmed.startsWith('|') && trimmed.endsWith('|') &&
        i + 1 < lines.length && lines[i + 1].includes('---')) {
        flushText();
        const header = this.parseTableRow(line);
        i += 2; // 跳过表头和分隔行
        const rows: string[][] = [];
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          rows.push(this.parseTableRow(lines[i]));
          i++;
        }
        // ★ 0.151：表格单元格同样做数学符号转换（如 |\neq| → |≠|）
        const mathHeader: string[] = header.map((c: string) => renderMathText(c));
        const mathRows: string[][] = rows.map((r: string[]) => r.map((c: string) => renderMathText(c)));
        // ★ 0.191.0：行格数对齐表头——流式中间态/AI 输出瑕疵导致的短行补空格、超长行截断，
        //   列边界与表头严格对齐永不错位（配合 parseTableRow 尾格容错，双保险）
        const colCount = mathHeader.length;
        for (let ri = 0; ri < mathRows.length; ri++) {
          const r = mathRows[ri];
          while (r.length < colCount) {
            r.push('');
          }
          if (r.length > colCount) {
            mathRows[ri] = r.slice(0, colCount);
          }
        }
        segments.push(new MdSegment(2, '', '', mathHeader, mathRows));
        continue;
      }

      // 普通文本
      textBuffer.push(line);
      i++;
    }
    flushText();
    return segments;
  }

  // ★ 新增：解析表格行 | a | b | → [a, b]（0.121）
  // ★ 0.191.0：流式中间态末行可能不以 | 结尾（AI 正在写入）——尾格也要收进，
  //   原逻辑丢尾格 → 该行格数比表头少 → 渲染时列边界左移错乱（用户实测 5×5 表末行总是错乱的根因）
  parseTableRow(line: string): string[] {
    const parts = line.split('|');
    const result: string[] = [];
    const endJ = line.trim().endsWith('|') ? parts.length - 1 : parts.length;
    for (let j = 1; j < endJ; j++) {
      result.push(parts[j].trim());
    }
    return result;
  }

  // ★ 新增：调用 LLM 生成摘要（0.117）
  // ★ 0.193.0 A 项：摘要 prompt 结构化升级（SUMMARY_PROMPT 五部分清单——用户问题逐条枚举/核心概念/已推导结论/关键约定/当前进度），
  //   学习 Claude Code 9 部分压缩清单；摘要质量=分支继承的记忆质量
  async generateSummaryWithLLM(messages: ChatMessage[]): Promise<string> {
    return new Promise((resolve, reject) => {
      const summaryMessages: ChatMessage[] = [
        new ChatMessage(generateMessageId(), 'system', SUMMARY_PROMPT),
        ...messages
      ];
      let summary = '';
      streamChat(
        summaryMessages,
        this.apiConfig,
        (chunk: string) => { summary += chunk; },
        () => { resolve(summary); },
        (error: string) => { reject(error); }
      );
    });
  }

  // ★ 新增：链路回溯 + 摘要滑动窗口压缩（0.117）
  async buildBranchMessageList(currentNode: BubbleNode): Promise<ChatMessage[]> {
    // ★ 0.193.0 E 项：token 化阈值（学习 Claude Code 按容量触发，替代原 25 条条数制）——
    //   ★ 0.199.0：触发线 24000→48000（用户拍板——flash 输入成本 1M≈1 元上调无感，模型窗口 128K 余量充足；
    //   约 3.2 万字、~100 轮对话才触发，超长学习会话也几乎全量；保留预算 8000 不变）；
    //   保留预算 8000 token：最近消息按容量保留（替代固定 15 条）；摘要窗口=全量-保留段（替代固定前 10 条）；
    //   估算规则：中文≈1字1.5token + 每条固定开销 50；
    //   needRegenerate 增量判断保持条数制（historySummaryCount 持久化字段语义不变，零迁移风险）
    const TOKEN_TRIGGER = 48000;
    const TOKEN_RECENT_KEEP = 8000;
    const MSG_OVERHEAD = 50;

    // 1. 沿 parentID 回溯到根节点，收集链路上所有节点
    const chainNodes: BubbleNode[] = [];
    let node: BubbleNode | undefined = currentNode;
    while (node) {
      chainNodes.unshift(node);
      if (node.parentID === null) break;
      node = this.store.nodeList.find(n => n.nodeID === node!.parentID);
    }

    // 2. 按时序组装消息数组（根 → 当前），过滤空内容和占位文字
    const allMessages: ChatMessage[] = [];
    for (const n of chainNodes) {
      for (const msg of n.messages) {
        // ★ 0.132：兼容加载/思考两个占位态
        if (msg.content.length > 0 && msg.content !== PLACEHOLDER_LOADING && msg.content !== PLACEHOLDER_THINKING) {
          allMessages.push(msg);
        }
      }
    }

    const totalCount = allMessages.length;
    let totalTokens = 0;
    for (const m of allMessages) {
      totalTokens += Math.ceil(m.content.length * 1.5) + MSG_OVERHEAD;
    }

    // 3. 未超 token 触发线，直接全量返回（原条数制：25 条短消息也被压——token 制修复此浪费）
    if (totalTokens <= TOKEN_TRIGGER) {
      return allMessages;
    }

    // 4. 超线，从尾部按预算保留最近消息（至少保底最后 1 条）
    let recentTokens = 0;
    let splitIndex = allMessages.length;
    for (let i = allMessages.length - 1; i >= 0; i--) {
      const t = Math.ceil(allMessages[i].content.length * 1.5) + MSG_OVERHEAD;
      if (recentTokens + t > TOKEN_RECENT_KEEP && i < allMessages.length - 1) {
        break;
      }
      recentTokens += t;
      splitIndex = i;
    }
    const toSummarize = allMessages.slice(0, splitIndex);
    if (toSummarize.length === 0) {
      return allMessages; // 单条超长无法压缩（摘要即丢原文），全量交给模型
    }

    // 5. 摘要增量判断（条数制保持）+ 超线时执行压缩
    const needRegenerate = currentNode.historySummary.length === 0 ||
      (totalCount - currentNode.historySummaryCount >= 10);

    if (needRegenerate) {
      try {
        this.streamPhase = 3; // ★ 0.199.0：阶段 3——整理历史记忆中（摘要生成是一次完整 LLM 调用 5~15s，
        // 此前该期间误显示"已提交请求"而请求实际未发出；等待态透明化，用户知道 AI 在整理而非卡死）
        const summary = await this.generateSummaryWithLLM(toSummarize);
        currentNode.historySummary = summary;
        currentNode.historySummaryCount = totalCount;
        this.saveTree(); // ★ 0.151：按模式分池保存
      } catch (e) {
        // 摘要生成失败静默降级（沿用旧摘要继续组装，不阻断对话）
      } finally {
        this.streamPhase = 1; // ★ 0.199.0：恢复阶段 1（成败都继续发送，请求即将真正发出）
      }
    }

    // 6. 组装最终消息：[1 条摘要虚拟消息 + 按预算保留的最近原始消息]
    const summaryMsg = new ChatMessage(generateMessageId(), 'system',
      `【历史摘要】${currentNode.historySummary}`);
    const recentMessages = allMessages.slice(splitIndex);
    const result: ChatMessage[] = [summaryMsg, ...recentMessages];
    return result;
  }

  // ★ 0.191.0：流式请求阶段（等待态一行提示——用户核心诉求：干等难受，必须告知当前在哪一步）
  // 0=无 1=已提交请求（点发送/刷新瞬间） 2=等待服务器返回（思考模型思考阶段——锅甩给服务器，用户知道不是自己设备的问题）
  // 3=整理历史记忆中（★ 0.199.0：上下文超 48K 触发线时的摘要生成期间，一次完整 LLM 调用 5~15s，平时不出现）
  // 「正在接收内容」状态已删（用户指出：首字节一到占位即消失，该状态永远显示不出来=死代码）
  @Local streamPhase: number = 0;

  // ★ 0.190.5：等待态视图——三点动画 + 阶段反馈 + 回复模式
  // ★ 0.191.0 定稿（用户指示）：全部信息浓缩一行；文案两态——已提交请求 / 等待服务器返回；无省略号（三点动画已表达进行中）
  // ── ★ 0.214.0：对话页缩放（Pad 双指捏合 / Matebook 触摸板双指捏合；边栏不参与——只缩消息正文） ──
  @Local fontScale: number = 1.0;        // 字号缩放系数（0.75~1.6）
  pinchStartFontScale: number = 1.0;     // 捏合起点快照
  ctrlAxisAt: number = 0; // ★ 0.215.10：最近 Ctrl+滚轮时刻（300ms 窗内 List 滚动被吞=只缩放不滚动）
  shiftEnterAt: number = 0; // ★ 0.215.11：最近 Shift+回车时刻（300ms 窗内 onSubmit 跳过发送=只换行）
  shiftHeld: boolean = false; // ★ 0.215.15：Shift 键按住状态（onKeyPreIme 追踪 Down/Up，判定兜底）

  /** ★ 0.215.14 设备三档判定（方案二落地）：deviceType 按系统 API（d.ts 实锤 phone/tablet/2in1/default），
   * 防御写法=明确移动设备（phone/tablet/tv/car/wearable）之外全算 PC 档——Matebook 无论返 2in1 还是
   * default 都不回退；Pad 横屏再宽也是 tablet 档永不串 PC（0.215.13 isTablet 宽度分治的 Pad 误判根治） */
  isPcDevice(): boolean {
    const t = deviceInfo.deviceType;
    return t !== 'phone' && t !== 'tablet' && t !== 'tv' && t !== 'car' && t !== 'wearable';
  }
  // ★ 0.214.2：缩放持久化（全新 PersistenceV2 key——跨页面/重启记住，用户拍板"不用来回攻"）
  fontScaleStore: ChatFontScaleStore = connectChatFontScale();

  /** ★ 0.214.0：正文字号换算（一位小数平滑；只用于消息正文——边栏/顶栏/输入区不缩） */
  fs(base: number): number {
    return Math.round(base * this.fontScale * 10) / 10;
  }

  /** ★ 0.214.2：草稿写回当前气泡（文字+图片实时进 BubbleNode 内存；退出时 saveTree 持久化） */
  saveDraft(): void {
    const b = this.currentBubble;
    if (!b) {
      return;
    }
    b.draftText = this.inputText;
    b.draftImages = this.pendingImages.length > 0 ? JSON.stringify(this.pendingImages) : '';
  }


  @Builder
  waitingView() { // ★ 0.191.0 清理：单行化后不再区分 LOADING/THINKING 文案，死参数 content 移除
    Row() {
      WaitingDots()
      Text(this.streamPhase === 3 ? '整理历史记忆中' // ★ 0.199.0：阶段 3——上下文压缩摘要生成期间（无省略号，遵循 0.191.0 定稿：三点动画已表达进行中）
        : this.streamPhase === 1 ? '已提交请求'
        : this.streamPhase === 2 ? '等待服务器返回'
        : 'AI 正在回复')
        .fontSize(14)
        .fontColor(TEXT_SECONDARY)
        .maxLines(1)
        .margin({ left: 8 })
      // ★ 0.190.7：仅短/长模式显示模式段（特殊模式才需提示；中回复=默认模式不啰嗦，用户指示）
      if (this.replyLengthMode === 'short' || this.replyLengthMode === 'long') {
        Text(`· ${this.replyLengthMode === 'short' ? '短' : '长'}回复模式`)
          .fontSize(12)
          .fontColor(TEXT_TERTIARY)
          .maxLines(1)
          .margin({ left: 4 })
      }
    }
    .width('100%')
  }

  // ★ 0.190.2：纯文本模型发图确认弹窗（Promise 包装 AlertDialog，await 取用户选择）
  confirmSendImageToTextModel(): Promise<boolean> {
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      this.getUIContext().showAlertDialog({
        title: '当前模型不支持图片',
        message: '你选择的模型为纯文本模型，无法识别图片内容。建议在 ⚙ 设置中切换标注「多模态（可发图）」的模型。',
        primaryButton: {
          value: '取消发送',
          action: () => {
            resolve(false);
          }
        },
        secondaryButton: {
          value: '仍要发送',
          action: () => {
            resolve(true);
          }
        }
      });
    });
  }

  async sendMessage(): Promise<void> { // ★ 改为 async（0.117）
    // ★ 0.190.4：卡死自愈（须在 guard 前）——isLoading=true 但 streamController=null 是异常态
    //   （正常流两者同步设置/清除；真机实测超时出错后偶发卡此态，guard 挡死后续所有发送
    //   「发送不出去」），检测到即强制恢复放行，用户永远不会再被卡死
    if (this.isLoading && this.streamController === null) {
      this.isLoading = false;
    }
    if ((!this.inputText.trim() && this.pendingImages.length === 0) || !this.currentBubble || this.isLoading) {
      return;
    }
 const _tp1: Record<string, string> = {}; _tp1['mode'] = this.sendMode;
    track(this.getUIContext().getHostContext() as common.Context, 'send_message', _tp1); // 0.206.0 埋点：发送（含模式）
    // ★ 0.190.2：纯文本模型发图拦截（用户批准方案）——预设清单已知纯文本 + 本次发送含图
    //   → 弹窗提醒切换多模态；多模态/自定义/清单外 ID 能力未知不拦截（等对方报错走关键词提示）
    if (this.pendingImages.length > 0 && isKnownTextOnlyModel(this.apiConfig.provider, this.apiConfig.model)) {
      const proceed = await this.confirmSendImageToTextModel();
      if (!proceed) {
        return;
      }
    }
    if (this.streamController) {
      this.streamController.cancel();
    }
    const isPodcast = this.sendMode === 'podcast'; // ★ 0.133：本次发送模式
    const userMsg = new ChatMessage(generateMessageId(), 'user', this.inputText, [...this.pendingImages], 0, 0, isPodcast); // ★ 0.133：标记播客模式
    // ★ 0.202.0：注意力提取——消息命中卡标题/标签 → 标签热度+1（纯本地毫秒级；AI 还在流式回复时复习权重已算完）
    updateAttention(this.attention, this.knowledgeBank.cards, userMsg.content);
    recordStat(this.statStore, 'userMsg', 0, 0); // ★ 0.192.0：统计埋点——用户消息 +1（只增不减，删除不影响）
    const aiMsg = new ChatMessage(generateMessageId(), 'assistant', PLACEHOLDER_LOADING, [], 0, 0, isPodcast); // ★ 0.132：占位常量；★ 0.133：标记播客模式
    this.currentBubble.messages = [...this.currentBubble.messages, userMsg, aiMsg];
    this.saveTree(); // ★ 0.151：按模式分池保存
    this.inputText = '';
    this.pendingImages = [];
    // ★ 0.214.2：发送即清本气泡草稿（内容已入消息流，草稿使命完成）
    const sb = this.currentBubble;
    if (sb) {
      sb.draftText = '';
      sb.draftImages = '';
    }
    // ★ 0.216.2 PC 发送后光标留在输入框（用户拍板"仅限 PC"）：连续打字+回车发+继续打，
    //   免去每次鼠标点回输入框；手机/Pad 保持原行为（发送后收键盘）
    if (this.isPcDevice()) {
      setTimeout(() => {
        this.getUIContext().getFocusController().requestFocus('chatInputField'); // 延迟一帧重新聚焦（系统 submit 自动 blur 先生效再拉回）
      }, 50);
    } else {
      this.getUIContext().getFocusController().clearFocus(); // ★ 0.131：发送后收起键盘（原行为）
    }
    this.isLoading = true;
    this.streamPhase = 1; // ★ 0.191.0：阶段 1——请求即将发出，等待服务器响应

    // 构建发送给 API 的消息列表：剔除空 content 的占位 AI 消息
    // ★ 替换为链路回溯 + 压缩（0.117）
    const messagesToSend = await this.buildBranchMessageList(this.currentBubble);

    // ★ 0.144：按回复长度档位以 system 消息插入 prompt 约束（与播客 prompt 同机制，不持久化；长度在前、播客贴近 user 消息）
    if (this.replyLengthMode === 'short') {
      messagesToSend.push(new ChatMessage(generateMessageId(), 'system', SHORT_REPLY_PROMPT));
    } else if (this.replyLengthMode === 'long') {
      messagesToSend.push(new ChatMessage(generateMessageId(), 'system', LONG_REPLY_PROMPT));
    } else {
      messagesToSend.push(new ChatMessage(generateMessageId(), 'system', MEDIUM_REPLY_PROMPT));
    }

    // ★ 0.150：AI 偏好 prompt（称呼 + 鼓励，按全局设置弹窗 Tab2 用户设置拼接；不持久化，与长度 prompt 同机制）
    const prefPrompt = this.buildPreferencePrompt();
    if (prefPrompt.length > 0) {
      messagesToSend.push(new ChatMessage(generateMessageId(), 'system', prefPrompt));
    }

    // ★ 0.133：播客模式在消息末尾追加系统 prompt（只在本次请求临时追加，不持久化、不进入后续上下文）
    if (isPodcast) {
      messagesToSend.push(new ChatMessage(generateMessageId(), 'system', PODCAST_PROMPT));
    }

    // ★ 0.216.0 三级降级·第一分叉：API Key 未配 → 端侧大模型（免费离线，DataAugmentationKit）；
    //   已配 → 云端 streamChat（下方原链路不变）。端侧不支持图片——无 Key 且带图时提前友好报错
    // ★ 0.216.1：降级判定诊断日志（Key 长度+provider+model，抓"Key 清了还走云端"的真实现场）
    console.info(`DAGAI-LLM route keyLen=${this.apiConfig.apiKey.trim().length} provider=${this.apiConfig.provider} model=${this.apiConfig.model}`);
    if (this.apiConfig.apiKey.trim().length === 0) {
      if (this.pendingImages.length > 0) {
        this.isLoading = false;
        this.streamPhase = 0;
        const cb0 = this.currentBubble; // ★ ArkTS 严格空检查
        if (cb0) {
          cb0.messages = cb0.messages.slice(0, cb0.messages.length - 2); // 撤回刚压入的用户+AI 占位
          cb0.messages = [...cb0.messages];
        }
        this.saveTree();
        this.getUIContext().getPromptAction().showToast({ message: '端侧大模型暂不支持图片，请配置 API Key 使用多模态云端模型', duration: 3500 });
        return;
      }
      this.streamController = localStreamChat(
        messagesToSend,
        (chunk: string) => {
          if (aiMsg.content === PLACEHOLDER_LOADING || aiMsg.content === PLACEHOLDER_THINKING) {
            aiMsg.content = '';
          }
          aiMsg.content += chunk;
          this.scroller.scrollEdge(Edge.Bottom); // ★ 0.216.0：端侧流式同样自动滚底（对齐云端链路）
          const cb1 = this.currentBubble; // ★ ArkTS 严格空检查：getter 返回可空须判
          if (cb1) {
            cb1.messages = [...cb1.messages];
            cb1.historySummaryCount = cb1.messages.length;
          }
        },
        (inputTokens: number, outputTokens: number) => {
          this.isLoading = false;
          this.streamPhase = 0;
          this.streamController = null;
          const cb2 = this.currentBubble;
          if (cb2) {
            cb2.messages = [...cb2.messages];
          }
          this.scroller.scrollEdge(Edge.Bottom);
          this.saveTree();
          recordStat(this.statStore, 'aiMsg', inputTokens, outputTokens);
        },
        (error: string) => {
          this.isLoading = false;
          this.streamPhase = 0;
          this.streamController = null;
          aiMsg.content = classifyStreamError(error); // ★ 0.216.0：错误气泡对齐云端链路（含端侧引导文案分类）
          const cb3 = this.currentBubble;
          if (cb3) {
            cb3.messages = [...cb3.messages];
          }
          this.scroller.scrollEdge(Edge.Bottom);
          this.saveTree();
        }
      ) as StreamController;
      return;
    }

    this.streamController = streamChat(
      messagesToSend,
      this.apiConfig,
      (chunk: string) => {
        // onChunk：首次收到数据时清除占位文字（兼容加载/思考两态），然后追加 AI content
        if (aiMsg.content === PLACEHOLDER_LOADING || aiMsg.content === PLACEHOLDER_THINKING) {
          aiMsg.content = '';
        }
        aiMsg.content += chunk;
        // ★ 0.191.0：接收态已删——首字节到达即清占位，等待态消失，「正在接收内容」永远显示不出来
        // ★ 流式接收时自动滚到底部（恢复 0.104-0.107 移除的行为）
        this.scroller.scrollEdge(Edge.Bottom);
      },
      (inputTokens: number, outputTokens: number) => {
        // onDone：解锁 + 存储 token
        this.isLoading = false;
        this.streamController = null;
        this.streamPhase = 0; // ★ 0.191.0：阶段复位
        // ★ 0.132 兜底：流结束但零内容时给出明确提示，杜绝任何场景永久卡占位
        if (aiMsg.content === PLACEHOLDER_LOADING || aiMsg.content === PLACEHOLDER_THINKING) {
          aiMsg.content = '（AI 未返回文本内容，请重试或更换模型）';
        }
        aiMsg.inputTokens = inputTokens;
        aiMsg.outputTokens = outputTokens;
        recordStat(this.statStore, 'aiMsg', inputTokens, outputTokens); // ★ 0.192.0：统计埋点——AI 回复 +1 + token 累计
        // 流式完成时滚到底部
        this.scroller.scrollEdge(Edge.Bottom);
        this.saveTree(); // ★ 0.151：按模式分池保存
      },
      (errMsg: string) => {
        // onError：解锁 + 日志 + 错误气泡
        this.isLoading = false;
        this.streamController = null;
        this.streamPhase = 0; // ★ 0.191.0：阶段复位
        // ★ 0.190.6：错误场景分类（ApiClient 单一真相源）——中文场景+建议操作+保留原始错误；
        //   0.190.2 图片关键词检测已合并进 classifyStreamError
        aiMsg.content = classifyStreamError(errMsg);
        // 错误时也滚到底部
        this.scroller.scrollEdge(Edge.Bottom);
        this.saveTree(); // ★ 0.151：按模式分池保存
      },
      (reasoning: string) => {
        // ★ 0.132 onReasoning：深度思考内容到达，占位切换为思考态
        // 思考内容不追加进 content（不参与持久化、不进入后续上下文），仅用于 UI 状态反馈
        if (aiMsg.content === PLACEHOLDER_LOADING) {
          aiMsg.content = PLACEHOLDER_THINKING;
        }
        this.streamPhase = 2; // ★ 0.191.0：阶段 2——等待服务器返回（思考模型思考阶段，锅甩给服务器）
        this.scroller.scrollEdge(Edge.Bottom);
      }
    );
    // 发送消息后自动滚到底部
    this.scroller.scrollEdge(Edge.Bottom);
  }

  // ★ 0.149：刷新按钮——原位重新生成指定 AI 回复（置加载占位后按链路上下文重新请求，
  // buildBranchMessageList 自动剔除占位使旧回复不进入新请求；消息不删、位置不变）
  async regenerateMessage(msg: ChatMessage): Promise<void> {
    // ★ 0.190.4：卡死自愈（同 sendMessage，须在 guard 前）
    if (this.isLoading && this.streamController === null) {
      this.isLoading = false;
    }
    if (this.isLoading || !this.currentBubble) {
      return;
    }
    if (this.streamController) {
      this.streamController.cancel();
    }
    // 置加载占位：UI 立即显示加载态，且构建上下文时该条被自动剔除（旧回复不进入新请求）
    msg.content = PLACEHOLDER_LOADING;
    msg.inputTokens = 0;
    msg.outputTokens = 0;
    this.isLoading = true;
    this.streamPhase = 1; // ★ 0.191.0：阶段 1——请求即将发出，等待服务器响应
    const messagesToSend = await this.buildBranchMessageList(this.currentBubble);
    // 回复长度档位 prompt（与 sendMessage 同机制，不持久化）
    if (this.replyLengthMode === 'short') {
      messagesToSend.push(new ChatMessage(generateMessageId(), 'system', SHORT_REPLY_PROMPT));
    } else if (this.replyLengthMode === 'long') {
      messagesToSend.push(new ChatMessage(generateMessageId(), 'system', LONG_REPLY_PROMPT));
    } else {
      messagesToSend.push(new ChatMessage(generateMessageId(), 'system', MEDIUM_REPLY_PROMPT));
    }
    // ★ 0.150：AI 偏好 prompt（与 sendMessage 同机制，刷新时同样生效）
    const prefPrompt = this.buildPreferencePrompt();
    if (prefPrompt.length > 0) {
      messagesToSend.push(new ChatMessage(generateMessageId(), 'system', prefPrompt));
    }
    // 播客模式：沿用该消息原发起模式，重新追加播客 prompt
    if (msg.isPodcastMode) {
      messagesToSend.push(new ChatMessage(generateMessageId(), 'system', PODCAST_PROMPT));
    }
    // ★ 0.216.1：regenerateMessage 同样降级——Key 空→端侧（与 sendMessage 同款判定，两处调用点全覆盖）
    console.info(`DAGAI-LLM route(regen) keyLen=${this.apiConfig.apiKey.trim().length}`);
    if (this.apiConfig.apiKey.trim().length === 0) {
      this.streamController = localStreamChat(
        messagesToSend,
        (chunk: string) => {
          if (msg.content === PLACEHOLDER_LOADING || msg.content === PLACEHOLDER_THINKING) {
            msg.content = '';
          }
          msg.content += chunk;
          this.scroller.scrollEdge(Edge.Bottom);
          const cb1 = this.currentBubble;
          if (cb1) {
            cb1.messages = [...cb1.messages];
          }
        },
        (inputTokens: number, outputTokens: number) => {
          this.isLoading = false;
          this.streamPhase = 0;
          this.streamController = null;
          const cb2 = this.currentBubble;
          if (cb2) {
            cb2.messages = [...cb2.messages];
          }
          this.scroller.scrollEdge(Edge.Bottom);
          this.saveTree();
          recordStat(this.statStore, 'aiMsg', inputTokens, outputTokens);
        },
        (error: string) => {
          this.isLoading = false;
          this.streamPhase = 0;
          this.streamController = null;
          msg.content = classifyStreamError(error);
          const cb3 = this.currentBubble;
          if (cb3) {
            cb3.messages = [...cb3.messages];
          }
          this.scroller.scrollEdge(Edge.Bottom);
          this.saveTree();
        }
      ) as StreamController;
      return;
    }
    this.streamController = streamChat(
      messagesToSend,
      this.apiConfig,
      (chunk: string) => {
        // onChunk：首次收到数据时清除占位文字（兼容加载/思考两态），然后追加 AI content
        if (msg.content === PLACEHOLDER_LOADING || msg.content === PLACEHOLDER_THINKING) {
          msg.content = '';
        }
        msg.content += chunk;
        // ★ 0.191.0：接收态已删（同 sendMessage——死代码）
        this.scroller.scrollEdge(Edge.Bottom);
      },
      (inputTokens: number, outputTokens: number) => {
        // onDone：解锁 + 存储 token
        this.isLoading = false;
        this.streamController = null;
        this.streamPhase = 0; // ★ 0.191.0：阶段复位
        if (msg.content === PLACEHOLDER_LOADING || msg.content === PLACEHOLDER_THINKING) {
          msg.content = '（AI 未返回文本内容，请重试或更换模型）';
        }
        msg.inputTokens = inputTokens;
        msg.outputTokens = outputTokens;
        recordStat(this.statStore, 'aiMsg', inputTokens, outputTokens); // ★ 0.192.0：统计埋点——重新生成同样计 AI 回复 + token
        this.scroller.scrollEdge(Edge.Bottom);
        this.saveTree(); // ★ 0.151：按模式分池保存
      },
      (errMsg: string) => {
        // onError：解锁 + 错误提示
        this.isLoading = false;
        this.streamController = null;
        this.streamPhase = 0; // ★ 0.191.0：阶段复位
        // ★ 0.190.6：错误场景分类（与 sendMessage onError 同机制）
        msg.content = classifyStreamError(errMsg);
        this.scroller.scrollEdge(Edge.Bottom);
        this.saveTree(); // ★ 0.151：按模式分池保存
      },
      (reasoning: string) => {
        // onReasoning：深度思考内容到达，占位切换为思考态（不持久化，仅 UI 反馈）
        if (msg.content === PLACEHOLDER_LOADING) {
          msg.content = PLACEHOLDER_THINKING;
        }
        this.streamPhase = 2; // ★ 0.191.0：阶段 2——等待服务器返回（思考模型思考阶段）
        this.scroller.scrollEdge(Edge.Bottom);
      }
    );
    this.scroller.scrollEdge(Edge.Bottom);
  }

  // ============================================================
  // ★ 0.133 新增：语音朗读（TTS 分段合成流水线播放）
  // ============================================================

  // toast 轻提示（showToast 可能抛异常，统一包裹消除编译告警，失败不影响主流程）
  showToastSafe(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (e) {
      // toast 失败静默忽略
    }
  }

  // ★ 0.189.0：splitTextForTTS/splitLongSentence 已移除——分段逻辑迁入
  // LocalTtsEngine.splitTextForTts（单一真相源，单词/朗读共用）

  // 点击喇叭入口：三态判断 + 播新停旧 + 启动朗读会话
  startTTS(msg: ChatMessage): void {
    // 合成/加载中 → 防重复点击
    if (this.ttsLoadingMessageId === msg.messageId) {
      return;
    }
    // 正在播放这条消息 → 点击即停止
    if (this.playingMessageId === msg.messageId) {
      this.stopTTS();
      return;
    }
    // 占位态不可读（AI 尚未开始输出）
    if (msg.content === PLACEHOLDER_LOADING || msg.content === PLACEHOLDER_THINKING) {
      this.showToastSafe('AI 回复完成后才能朗读');
      return;
    }
    if (msg.content.trim().length === 0) {
      this.showToastSafe('消息内容为空，无法朗读');
      return;
    }
    // 播新停旧：先终止当前朗读会话
    this.stopTTS();
    // ★ 0.149：与单词发音互斥——消息朗读开始前停掉单词 TTS
    wordSpeaker.stop();
    // ★ 0.189.0：本地引擎播报（CoreSpeechKit 免费离线）——分段/排队/会话失效
    // 全在 LocalTtsEngine 内部管理；云端火山管线已按用户指示移除
    this.playingMessageId = msg.messageId;
    this.ttsLoadingMessageId = msg.messageId;
    localTts.speakText(msg.content, {
      onStart: () => {
        this.ttsLoadingMessageId = ''; // ⏳→🔊（首段开播）
      },
      onComplete: () => {
        this.stopTTS(); // 全部段播完——恢复正常态
      },
      onError: (code: number, message: string) => {
        this.stopTTS();
        this.showToastSafe(`朗读失败（${code}）：${message}`);
      }
    }).then((ok: boolean) => {
      if (!ok) {
        this.stopTTS();
        this.showToastSafe('本机语音引擎不可用：请在系统设置检查「文字转语音」语音包是否已下载');
      }
    });
  }

  // 停止整个朗读会话（★ 0.189.0：本地引擎版——停引擎+清状态，幂等，可安全重复调用）
  stopTTS(): void {
    localTts.stop();
    this.playingMessageId = '';
    this.ttsLoadingMessageId = '';
  }

  // 进入对话页面：延迟滚到底部，显示最新消息
  // ============================================================
  // ★ 0.191.0：阅读位置记忆（方案 A 会话级高度）+ 书签（方案 B 手动标记）
  // ============================================================
  // 记录当前气泡滚动高度（离开对话页/切气泡前调用；模块级 Map 同会话存活）
  recordReadingPosition(): void {
    const bubbleId = this.currentBubbleId;
    if (bubbleId.length === 0) {
      return;
    }
    try {
      const y = this.scroller.currentOffset().yOffset;
      if (y > 0) {
        chatScrollMemory.set(bubbleId, y);
      }
    } catch (_e) {
      // 布局未就绪等异常静默忽略
    }
  }

  // 恢复阅读位置：A 高度记忆 → 底部（原行为）
  // ★ 0.191.0 重做：书签跳转分支删除（用户定稿：与 A 冲突——A 生效即无需跳转；且多消息各有一个标记时无法决定跳哪个，本身是 bug）。
  //   书签降级为纯视觉标记（段落背景色），不再承担任何定位职责。
  restoreReadingPosition(): void {
    this.bookmarkCache = this.getBookmarkEntry(); // 重载本气泡书签缓存（视觉标记渲染用）
    const bubbleId = this.currentBubbleId;
    let targetY = -1;
    if (bubbleId.length > 0) {
      const memY = chatScrollMemory.get(bubbleId) ?? -1;
      if (memY > 0) {
        targetY = memY;
        this.scroller.scrollTo({ xOffset: 0, yOffset: memY });
      }
    }
    if (targetY < 0) {
      this.scroller.scrollEdge(Edge.Bottom);
      return;
    }
    // 二次补偿：长列表首帧渲染未完成时 scrollTo 被 clamp 到错误位置，延迟校验补滚一次
    setTimeout(() => {
      try {
        const cur = this.scroller.currentOffset().yOffset;
        if (Math.abs(cur - targetY) > 80) {
          this.scroller.scrollTo({ xOffset: 0, yOffset: targetY });
        }
      } catch (_e) {
        // 组件已销毁等异常静默
      }
    }, 350);
  }

  // 从持久化 JSON 解析本气泡书签（无则 null）
  getBookmarkEntry(): BookmarkEntry | null {
    const bubbleId = this.currentBubbleId;
    try {
      const data = JSON.parse(this.bookmarkStore.raw) as BookmarkData;
      if (data.entries === undefined || data.entries === null) {
        return null;
      }
      for (let i = 0; i < data.entries.length; i++) {
        if (data.entries[i].bubbleId === bubbleId) {
          return data.entries[i];
        }
      }
    } catch (_e) {
      // 解析失败视为无书签
    }
    return null;
  }

  // 设置书签（每气泡一个，新标记覆盖旧标记）——★ 0.191.0 重做：划词级（key+字符偏移）
  setBookmarkAt(segKey: string, start: number, end: number): void {
    const bubbleId = this.currentBubbleId;
    const entries: BookmarkEntry[] = [];
    try {
      const data = JSON.parse(this.bookmarkStore.raw) as BookmarkData;
      if (data.entries !== undefined && data.entries !== null) {
        for (let i = 0; i < data.entries.length; i++) {
          if (data.entries[i].bubbleId !== bubbleId) {
            entries.push(data.entries[i]);
          }
        }
      }
    } catch (_e) {
      // 解析失败从空表重建
    }
    const messageId = segKey.split('|')[0];
    const entry: BookmarkEntry = { bubbleId: bubbleId, messageId: messageId, segKey: segKey, start: start, end: end };
    entries.push(entry);
    this.bookmarkStore.raw = JSON.stringify({ entries: entries } as BookmarkData);
    this.bookmarkCache = entry;
  }

  // 清除本气泡书签
  clearBookmark(): void {
    const bubbleId = this.currentBubbleId;
    const entries: BookmarkEntry[] = [];
    try {
      const data = JSON.parse(this.bookmarkStore.raw) as BookmarkData;
      if (data.entries !== undefined && data.entries !== null) {
        for (let i = 0; i < data.entries.length; i++) {
          if (data.entries[i].bubbleId !== bubbleId) {
            entries.push(data.entries[i]);
          }
        }
      }
    } catch (_e) {
      return;
    }
    this.bookmarkStore.raw = JSON.stringify({ entries: entries } as BookmarkData);
    this.bookmarkCache = null;
  }

  // 渲染期高频查询：本划词 key 是否命中书签（读缓存，零 JSON 解析）
  isBookmarkAt(key: string): boolean {
    const bm = this.bookmarkCache;
    return bm !== null && bm.segKey === key;
  }

  // 书签划选偏移读取（模板内访问 bookmarkCache 需空安全辅助；-1=无）
  bmStart(): number {
    const bm = this.bookmarkCache;
    return bm !== null ? bm.start : -1;
  }

  bmEnd(): number {
    const bm = this.bookmarkCache;
    return bm !== null ? bm.end : -1;
  }

  // 划词 key 是否可标记（AI 正文文本段 `${msgId}|纯数字` + 表格格 `${msgId}|t..h..`/`t..r..c..`；
  // 'u'=用户消息、rk*/rkd*/rw*=复习区、c*=代码块、cz/tz*=放大页均排除）
  isBookmarkTargetKey(key: string): boolean {
    const parts = key.split('|');
    if (parts.length !== 2) {
      return false;
    }
    const segStr = parts[1];
    if (segStr.length === 0) {
      return false;
    }
    let allDigit = true;
    for (let i = 0; i < segStr.length; i++) {
      const c = segStr.charCodeAt(i);
      if (c < 48 || c > 57) {
        allDigit = false;
        break;
      }
    }
    if (allDigit) {
      return true; // 文本段
    }
    // 代码块：c${segIdx}；表格格：t${segIdx}h${ci}（表头）/ t${segIdx}r${ri}c${ci}（数据行）
    return /^c\d+$/.test(segStr) || /^t\d+h\d+$/.test(segStr) || /^t\d+r\d+c\d+$/.test(segStr);
  }

  // 划词工具栏「标记/取消标记」——划选首字符已在本气泡书签区间内 → 取消；否则把整个划选设为书签
  // ★ 0.191.0 定稿（用户方案）：不设独立清除入口，标记/取消都走划词工具栏，屏幕零占用
  onToolbarBookmark(): void {
    const s = this.effectiveSelStart();
    const e = this.effectiveSelEnd();
    if (s < 0 || e <= s) {
      this.showToastSafe('请划选文字后再标记');
      return;
    }
    const bm = this.bookmarkCache;
    if (bm !== null && bm.segKey === this.selKey && s >= bm.start && s < bm.end) {
      this.clearBookmark();
      this.showToastSafe('已取消标记');
    } else {
      this.setBookmarkAt(this.selKey, s, e);
      this.showToastSafe('已标记划选内容');
    }
    // ★ 0.191.0 修复：此处不清选中状态——菜单仍开着时按钮须变「取消标记」可再点
    //   （清了 selKey 按钮显示条件失效会整个消失，用户实测 bug）；菜单关闭时 onDisappear 统一清理
  }

  // ★ 0.191.0：工具栏按钮文案——划选首字符已被标记 → 「取消标记」，否则「标记」
  bookmarkBtnLabel(): string {
    const bm = this.bookmarkCache;
    if (bm === null || bm.segKey !== this.selKey) {
      return '标记';
    }
    const s = this.effectiveSelStart();
    if (s >= 0 && s >= bm.start && s < bm.end) {
      return '取消标记';
    }
    return '标记';
  }

  aboutToAppear() {
    // ★ 0.196.4：isTablet 屏宽检测删除——改读 WindowMode 共享真相源（Index 根 onAreaChange 写入）
    this.deleteSkipConfirm = false; // ★ 0.150：重进对话页重置「不再提示」——每次会话首次删除仍弹确认（防误触）
    this.bookmarkCache = this.getBookmarkEntry(); // ★ 0.191.0：首帧渲染前载入书签（标记线即时显示）
    // ★ 0.214.2：恢复缩放（持久化值优先；钳制防脏数据）
    this.fontScale = Math.min(1.6, Math.max(0.75, this.fontScaleStore.value));
    // ★ 0.214.2：恢复本气泡草稿（文字+图片——退出再回来继续编）
    const draftBubble = this.currentBubble;
    if (draftBubble) {
      this.inputText = draftBubble.draftText;
      if (draftBubble.draftImages.length > 0) {
        try {
          const draftArr = JSON.parse(draftBubble.draftImages) as string[];
          if (Array.isArray(draftArr)) {
            this.pendingImages = draftArr;
          }
        } catch (e) {
          // 损坏草稿按无图处理
        }
      }
    }
    setTimeout(() => {
      this.restoreReadingPosition(); // ★ 0.191.0：阅读位置恢复（A 高度记忆 → B 书签 → 底部），替代原固定滚底
    }, 100);
  }

  // 页面退出：终止正在进行的 SSE 请求，防止内存泄漏
  aboutToDisappear() {
    this.saveDraft(); // ★ 0.214.2：草稿写回当前气泡内存
    this.saveTree(); // ★ 0.214.2：草稿随树落盘（一次）
    this.recordReadingPosition(); // ★ 0.191.0：离开前记录阅读高度（方案 A）
    if (this.streamController) {
      this.streamController.cancel();
      this.streamController = null;
    }
    this.stopTTS(); // ★ 0.133：退出对话页停止朗读（现有交互下切气泡必经 pop，一个钩子覆盖退页+切气泡两种情况）
    this.stopExtractTimer(); // ★ 0.153：组件销毁清除提炼计时器，防内存泄漏
  }

  // 选择图片：调用相册多选，转 Base64 存入 pendingImages
  async selectImages(): Promise<void> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select({ maxSelectNumber: 9 });
      for (let i = 0; i < result.photoUris.length; i++) {
        const uri = result.photoUris[i];
        const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
        const stat = fileIo.statSync(file.fd);
        const arrayBuffer = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, arrayBuffer);
        fileIo.closeSync(file);
        const base64 = buffer.from(arrayBuffer).toString('base64');
          this.pendingImages = [...this.pendingImages, `data:image/jpeg;base64,${base64}`];
      this.saveDraft(); // 0.214.2 图片变化实时写回草稿
      }
    } catch (err) {
      // 选图取消/读取失败静默忽略（防崩溃）
    }
  }

  // 删除待发送图片
  removeImage(index: number): void {
    const newList: string[] = [];
    for (let i = 0; i < this.pendingImages.length; i++) {
      if (i !== index) {
        newList.push(this.pendingImages[i]);
      }
    }
    this.pendingImages = newList;
    this.saveDraft(); // 0.214.2 删图实时写回草稿
  }

  // ★ 0.150：删除入口——首次点 × 弹确认防误触；本次会话内勾选过「不再提示」则直接删
  requestDeleteMessage(messageId: string): void {
    if (this.deleteSkipConfirm) {
      this.deleteMessage(messageId);
      return;
    }
    this.deleteConfirmMessageId = messageId;
    this.deleteConfirmNoAsk = false; // 每次打开弹窗，勾选框复位
    this.deleteConfirmVisible = true;
  }

  // ★ 0.150：确认弹窗「删除」——记住勾选状态并执行删除
  confirmDeleteMessage(): void {
    this.deleteSkipConfirm = this.deleteConfirmNoAsk;
    this.deleteConfirmVisible = false;
    const id = this.deleteConfirmMessageId;
    this.deleteConfirmMessageId = '';
    if (id.length > 0) {
      this.deleteMessage(id);
    }
  }

  deleteMessage(messageId: string): void {
    if (!this.currentBubble) {
      return;
    }
    // ★ 0.133：删除正在朗读/合成中的消息 → 停止播放
    if (this.playingMessageId === messageId || this.ttsLoadingMessageId === messageId) {
      this.stopTTS();
    }
    this.currentBubble.messages = this.currentBubble.messages.filter(m => m.messageId !== messageId);
    this.saveTree(); // ★ 0.151：按模式分池保存
  }

  // ============================================================
  // ★ 0.145：划词翻译——选择状态管理
  // ============================================================

  // 惰性获取指定 Text 的控制器（ForEach 中每个可选 Text 一个独立实例，
  // closeSelectionMenu 只作用于自己绑定的 Text，互不干扰）
  getOrCreateTextController(key: string): TextController {
    let ctrl = this.textControllers.get(key);
    if (!ctrl) {
      ctrl = new TextController();
      this.textControllers.set(key, ctrl);
    }
    return ctrl;
  }

  // onTextSelectionChange 回调：记录激活的 Text 标识并截取选中文本。
  // content 由闭包捕获（用户消息=msg.content，AI 段=seg.content），
  // 位置是「该 Text 内容内」的偏移，直接 substring 即得选中词。
  handleSelectionChange(key: string, content: string, start: number, end: number): void {
    if (start < 0 || end > content.length || start >= end) {
      return; // 无效区间（取消选择时的 0,0 回调）——保留既有状态，由 onDisappear 统一清理
    }
    this.selKey = key;
    this.selText = content.substring(start, end);
    this.selStart = start; // ★ 0.191.0：记录偏移供划词级书签
    this.selEnd = end;
    // ★ 0.191.0：粘性区间——表格在横向 Scroll 内拖选时手势冲突会触发菜单消失重弹，
    //   onDisappear 清掉 selStart/selEnd 后点「标记」误报「请划选文字」（用户实测 bug）；
    //   粘性副本不被清理，点击时同 key 兜底恢复
    this.stickySelKey = key;
    this.stickyStart = start;
    this.stickyEnd = end;
  }

  // 选择菜单关闭时清理全部选择状态（点空白/点菜单按钮后由 onDisappear 触发）
  // ★ 0.191.0：粘性区间不清（跨菜单消失重弹存活，见 handleSelectionChange 注释）
  clearSelectionState(): void {
    this.selKey = '';
    this.selText = '';
    this.selStart = -1;
    this.selEnd = -1;
    this.selectAllKey = '';
  }

  // ★ 0.191.0：有效选中区间（当前回调值优先，菜单重弹丢失时用粘性副本兜底；-1=无）
  effectiveSelStart(): number {
    if (this.selStart >= 0) {
      return this.selStart;
    }
    if (this.selKey.length > 0 && this.stickySelKey === this.selKey) {
      return this.stickyStart;
    }
    return -1;
  }

  effectiveSelEnd(): number {
    if ( this.selEnd > this.selStart) {
      return this.selEnd;
    }
    if (this.selKey.length > 0 && this.stickySelKey === this.selKey) {
      return this.stickyEnd;
    }
    return -1;
  }

  // 关闭当前激活 Text 的选择菜单（悬浮栏按钮点击后调用）
  closeActiveSelectionMenu(): void {
    if (this.selKey.length > 0) {
      const ctrl = this.textControllers.get(this.selKey);
      ctrl?.closeSelectionMenu();
    }
  }

  // ============================================================
  // ★ 0.145：悬浮操作栏按钮（翻译 | 复制 | 全选）
  // ============================================================

  // 「翻译」：关闭菜单 → 打开浮窗 → 发起 AI 查词（独立请求，不建气泡、不进 DAG）
  onToolbarTranslate(): void {
    const text = this.selText.trim(); // 先取值——closeSelectionMenu 可能同步触发 onDisappear 清空状态
    this.closeActiveSelectionMenu();
    if (text.length === 0) {
      return;
    }
    this.wordPopupVisible = true;
    this.wordPopupQuery = text;
    this.wordPopupLoading = true;
    this.wordPopupResult = null;
    this.wordPopupError = '';
    this.wordPopupAdded = false;
    this.wordExistsTip = false;
    if (this.wordQueryController) {
      this.wordQueryController.cancel(); // 上一次查词未完成 → 取消
    }
    this.wordQueryController = queryWord(text, this.apiConfig,
      (result: WordQueryResult) => {
        this.wordPopupLoading = false;
        this.wordPopupResult = result;
      },
      (error: string) => {
        this.wordPopupLoading = false;
        this.wordPopupError = error;
      });
  }

  // 「复制」：选中文本写入系统剪贴板
  onToolbarCopy(): void {
    const text = this.selText; // 先取值（同上）
    this.closeActiveSelectionMenu();
    if (text.length === 0) {
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setData(data).catch((err: Error) => {
        // 写入失败静默忽略（复制为辅助功能，不打断主流程）
      });
    } catch (e) {
      // 复制异常静默忽略（防崩溃）
    }
  }

  // 「全选」：selection 属性受控驱动——nonce 递增拼进 key 使属性参数变化，
  // 确保全选后拖动手柄再点全选仍能重新应用 (0, len)。菜单保持显示（可继续翻译/复制全文）
  onToolbarSelectAll(): void {
    const key = this.selKey; // 先取值（同上）
    if (key.length === 0) {
      return;
    }
    this.selectAllNonce++;
    this.selectAllKey = `${key}|${this.selectAllNonce}`;
  }

  // ★ 0.160：「删除」——划词就地删本条消息（AI 超长回复时免滚到 × 按钮的冗余备份入口）。
  // 从 selKey 前缀提取消息 ID，复用 × 按钮的 requestDeleteMessage 入口——
  // 防误触确认状态天然共享（同一 deleteSkipConfirm 会话级变量：任一入口首次删除弹确认、
  // 勾选「此次对话不再提示」后两个入口都不再弹；重进对话页统一重置）。
  // 放大弹窗内的划词（代码放大 key 前缀 cz、表格放大 key 无 | 分隔）不对应消息，直接忽略。
  onToolbarDelete(): void {
    const key = this.selKey; // 先取值——closeSelectionMenu 可能同步触发 onDisappear 清空状态
    this.closeActiveSelectionMenu();
    const sep = key.indexOf('|');
    if (sep <= 0) {
      return; // 表格放大弹窗 key（tzh*/tzr*，无 |）或空——非消息文本
    }
    const messageId = key.substring(0, sep);
    if (messageId === 'cz') {
      return; // 代码放大弹窗内文本——非消息文本
    }
    // ★ 0.169.1：复习区划词 key（rw*/rwf*/rwe*/rk*/rkd* 段前缀）不对应消息文本——防御性忽略。
    // 复习区悬浮栏（ReviewSelectionToolbar）本无删除项，此处兜底防未来误绑 SelectionToolbar 时误删消息
    const segPart = key.substring(sep + 1);
    if (segPart.startsWith('rw') || segPart.startsWith('rk')) {
      return;
    }
    if (messageId.length > 0) {
      this.requestDeleteMessage(messageId);
    }
  }

  // ============================================================
  // ★ 0.145：翻译浮窗
  // ============================================================

  // 关闭浮窗并取消进行中的查词请求
  closeWordPopup(): void {
    this.wordPopupVisible = false;
    if (this.wordQueryController) {
      this.wordQueryController.cancel();
      this.wordQueryController = null;
    }
  }

  // ★ 0.155：翻译浮窗发音文本——中译英结果（查询词含中文）播英文译文（explain 字段），
  // 原英译中路径不变（缩略词播全称、普通词播原文）
  wordPopupSpeakText(): string {
    const r = this.wordPopupResult;
    if (r !== null && containsChinese(this.wordPopupQuery) && r.explain.length > 0) {
      return r.explain;
    }
    return wordSpeaker.textFor(this.wordPopupQuery, r !== null ? r.fullName : '');
  }

  // 「加入单词库」：查词结果转 WordItem 入库；重复时显示「单词已存在」
  addCurrentWordToBank(): void {
    if (this.wordPopupResult === null) {
      return;
    }
    track(this.getUIContext().getHostContext() as common.Context, 'add_word_from_chat'); // 0.206.0 埋点：对话翻译弹窗加词
    const r = this.wordPopupResult;
    const item = new WordItem(r.word, r.fullName, r.usPhonetic, r.explain);
    const ok = addWordToBank(this.wordBank, item);
    if (ok) {
      this.wordPopupAdded = true;
      this.wordExistsTip = false;
    } else {
      this.wordExistsTip = true;
    }
  }

  // 生词复习：按消息 ID 取 N 词（N=学习数量，单词库 ⚙ 设置）。
  // ★ 0.187.0：选词改走记忆算法（到期词按遗忘风险 R 升序 → 新词 → 未来词，替换纯随机）；
  // 缓存按消息 ID 永久固定（历史消息稳定），已删除的词读取时滤除；
  // 展示即复习——真到期的词计数 + 顺延 6h（未到期不计数：防重启重抽虚增，到期闸门防抖）
  getReviewWords(messageId: string): WordItem[] {
    const cached = this.reviewCache.get(messageId);
    if (cached) {
      return cached.items.filter((w: WordItem) => this.wordBank.words.includes(w));
    }
    const now = Date.now();
    const items = pickReviewWords(this.wordBank, this.learnCountStore.learnCount, now);
    for (let i = 0; i < items.length; i++) {
      applyPassiveReview(items[i], now);
    }
    recordStat(this.statStore, 'siyi', items.length, 0); // ★ 0.202.3：司忆量埋点
    this.reviewCache.set(messageId, new ReviewCacheEntry(0, items));
    return items;
  }

  // ============================================================
  // ★ 0.146：知识库卡片（入知识库 → AI 草稿 → 编辑弹窗 → 入库）
  // ============================================================

  // ★ 0.160：抽取弹窗内复习区内容（打开弹窗时调一次固定；词库/知识库为空时对应项为空，
  // 渲染层按空判不显示——与气泡底部复习区同款防御）
  // ★ 0.187.0：选词改走记忆算法 + 展示即复习（到期闸门防抖——反复开关弹窗不虚增计数）
  refreshEditReview(): void {
    const now = Date.now();
    this.editReviewWords = pickReviewWords(this.wordBank, this.learnCountStore.learnCount, now); // ★ 0.161：词条数由学习数量设置驱动（单词库 ⚙ 设置）
    for (let i = 0; i < this.editReviewWords.length; i++) {
      applyPassiveReview(this.editReviewWords[i], now);
    }
    this.editReviewCards = pickReviewCards(this.knowledgeBank, this.knowledgeCountStore.knowledgeCount, now); // ★ 0.161.2：卡片数由知识卡片数量设置驱动（知识库 ⚙ 设置）；★ 0.188.0：记忆算法选卡
    for (let i = 0; i < this.editReviewCards.length; i++) {
      applyPassiveReview(this.editReviewCards[i], now); // ★ 0.188.0：展示即复习（到期闸门防抖）
    }
    // ★ 0.202.3：司忆量埋点（本次展示的词+卡总数）
    recordStat(this.statStore, 'siyi', this.editReviewWords.length + this.editReviewCards.length, 0);
  }

  // ★ 0.187.0：点词条展开/收起 3 档评分（👆 图标勾引点击——点词即展开）
  onReviewWordTap(key: string): void {
    this.reviewExpandKey = this.reviewExpandKey === key ? '' : key;
  }

  // ★ 0.187.0：评分落库——按评分规则更新 S 与下次复习（方案B：现在+S），收起按钮
  // ★ 0.188.0：参数泛化 MemoryItem——单词/知识卡两库共用
  onReviewRate(key: string, w: MemoryItem, rating: MemoryRating): void {
 const _tp2: Record<string, string> = {}; _tp2['rating'] = rating;
    track(this.getUIContext().getHostContext() as common.Context, 'bubble_rate', _tp2); // 0.206.0 埋点：司忆区评分
    applyRating(w, rating, Date.now());
    const next = new Map<string, string>(this.reviewRatedMap);
    next.set(key, rating);
    this.reviewRatedMap = next; // Map 整体替换触发 V2 刷新
    this.reviewExpandKey = '';
  }

  // ★ 0.187.0：评分区（气泡复习区 + 提炼弹窗共用 @Builder）——
  // 已评分 → 「下次复习：X」结果行（按评分着色）；未评且展开 → 3 档按钮
  @Builder
  ratingArea(key: string, w: MemoryItem) { // ★ 0.188.0：参数泛化 MemoryItem——单词/知识卡共用
    if (this.reviewRatedMap.get(key) !== undefined) {
      Text(`下次复习：${formatNextReviewLabel(w.nextReviewAt, Date.now())}`)
        .fontSize(11)
        .fontColor(this.reviewRatedMap.get(key) === 'hard' ? DANGER : (this.reviewRatedMap.get(key) === 'easy' ? '#3BB273' : '#F5A623'))
        .margin({ top: 3 })
    } else if (this.reviewExpandKey === key) {
      // ★ 0.198.5 对齐终修（真机 density 实锤定案）：手机全屏 density=3.0（▲10vp=30px/Wisdom 13vp 字宽/
      //   width(96)=288px 三重铁证），屏幕仅 376vp、气泡内容区仅 289.7vp——此前拿 0.196.3 分屏小窗记录
      //   「1128px=451vp」当全屏换算基准，内容区被高估 1.2 倍，导致 96×3+12=300vp>289.7vp 五轮"溢出"
      //   误判（width(96) 其实一直精确生效）。用户拍板：熟知右缘须与词卡文字区右缘对齐，贴边留白难看
      //   → 按钮 layoutWeight(1) 均分铺��词卡区（右缘精确对齐，手机均分 92.6vp 观感与 96 几乎一致），
      //   平板均分超 96 被 maxWidth 钳回窄胶囊（守住 0.196.0 拍板；0.198.1 的 maxWidth 失效结论仅适用
      //   横向 Scroll 内无界环境，0.198.4 铁证：Row 在词卡 Column 内拿到的基准 869px 精确正确）
      Row({ space: 6 }) {
        Button() {
          Column() {
            Text('生疏').fontSize(13).fontWeight(600).fontColor('#E5484D')
            Text(`${formatIntervalDays(previewIntervalDays(w, 'hard'))}后`).fontSize(9).fontColor(TEXT_TERTIARY)
          }
        }
        .layoutWeight(1)
        .constraintSize({ maxWidth: 96 })
        .backgroundColor('#26E5484D')
        .borderRadius(RADIUS_CONTROL)
        .onClick(() => {
          this.onReviewRate(key, w, 'hard');
        })
        Button() {
          Column() {
            Text('尚可').fontSize(13).fontWeight(600).fontColor('#F5A623')
            Text(`${formatIntervalDays(previewIntervalDays(w, 'good'))}后`).fontSize(9).fontColor(TEXT_TERTIARY)
          }
        }
        .layoutWeight(1)
        .constraintSize({ maxWidth: 96 })
        .backgroundColor('#26F5A623')
        .borderRadius(RADIUS_CONTROL)
        .onClick(() => {
          this.onReviewRate(key, w, 'good');
        })
        Button() {
          Column() {
            Text('熟知').fontSize(13).fontWeight(600).fontColor('#3BB273')
            Text(`${formatIntervalDays(previewIntervalDays(w, 'easy'))}后`).fontSize(9).fontColor(TEXT_TERTIARY)
          }
        }
        .layoutWeight(1)
        .constraintSize({ maxWidth: 96 })
        .backgroundColor('#263BB273')
        .borderRadius(RADIUS_CONTROL)
        .onClick(() => {
          this.onReviewRate(key, w, 'easy');
        })
      }
      .margin({ top: 4 })
    }
  }

  // ★ 0.153：启动提炼秒表——清零后每秒 +1；累计 180s 业务超时自动 abort + 红色提示
  startExtractTimer(): void {
    this.stopExtractTimer();
    this.knowledgeExtractSeconds = 0;
    this.knowledgeExtractTimer = setInterval(() => {
      this.knowledgeExtractSeconds++;
      if (this.knowledgeExtractSeconds >= 180) {
        // 业务超时：终止 SSE 请求 + 停止计时 + 弹窗红色提示
        if (this.knowledgeQueryController) {
          this.knowledgeQueryController.cancel();
          this.knowledgeQueryController = null;
        }
        this.knowledgeEditLoading = false;
        this.knowledgeEditError = '请求超时：AI处理时间超出3分钟，请尝试裁剪图片、减少图片内文字内容后重试。';
        this.stopExtractTimer();
      }
    }, 1000);
  }

  // ★ 0.153：停止并清零提炼秒表（成功/取消/报错/超时/切后台统一收口）
  stopExtractTimer(): void {
    if (this.knowledgeExtractTimer >= 0) {
      clearInterval(this.knowledgeExtractTimer);
      this.knowledgeExtractTimer = -1;
    }
    this.knowledgeExtractSeconds = 0;
  }

  // ★ 0.153：提炼错误三分类友好中文提示（禁止直接展示英文原始报错）
  // ① Operation timeout 底层网络超时 ② AI 服务返回业务错误 ③ 本地代码异常
  friendlyKnowledgeError(raw: string): string {
    if (raw.toLowerCase().includes('timeout')) {
      return '后台网络超时：APP切后台后，系统限制网络，本次AI生成中断。请保持应用在前台重试。';
    }
    if (raw.startsWith('AI服务错误：')) {
      return `AI服务返回错误：${raw.substring(7)}，请检查API Key/模型配置。`;
    }
    return '本地处理异常：生成卡片失败，请重试。';
  }

  // ★ 0.153：应用切后台监听（NavDestination 无 onPageHide 生命周期，借 EntryAbility
  // 维护的全局标志 + AppStorageV2 + @Monitor 实现）——提炼进行中直接 abort
  // （鸿蒙限制后台网络，长连接必断，干等只会白耗输入 token）；
  // 停止计时 + 弹窗提示，回前台可查看提示后重试
  @Monitor('appLifecycle.isBackground')
  onAppBackgroundChange(): void {
    if (this.appLifecycle.isBackground && this.knowledgeEditLoading) {
      if (this.knowledgeQueryController) {
        this.knowledgeQueryController.cancel();
        this.knowledgeQueryController = null;
      }
      this.knowledgeEditLoading = false;
      this.knowledgeEditError = '提炼已暂停：应用切到后台，鸿蒙系统会限制后台网络，无法稳定接收结果。';
      this.stopExtractTimer();
    }
  }

  // 「入知识库」：关闭菜单 → 打开编辑弹窗 → 发起 AI 提炼。
  // AI 结果只填充输入框（草稿），不直接入库——用户拥有最终编辑权。
  onToolbarAddKnowledge(): void {
    const text = this.selText.trim(); // 先取值——closeSelectionMenu 可能同步触发 onDisappear 清空状态
    this.closeActiveSelectionMenu();
    if (text.length === 0) {
      return;
    }
    this.knowledgeEditVisible = true;
    this.knowledgeCardTitle = '';
    this.knowledgeCardDefinition = '';
    this.knowledgeSuggestedTags = []; // ★ 0.202.1：建议标签清空（新会话）
    this.knowledgeSelectedTags = '';
    this.knowledgeImageUri = '';
    this.knowledgeEditLoading = true;
    this.knowledgeEditError = '';
    this.refreshEditReview(); // ★ 0.160：抽一组复习内容——提炼等待期顺便学习
    if (this.knowledgeQueryController) {
      this.knowledgeQueryController.cancel(); // 上一次提炼未完成 → 取消
    }
    this.startExtractTimer(); // ★ 0.153：秒表从 0 开始计数
    this.knowledgeQueryController = queryKnowledge(text, this.apiConfig,
      (result: KnowledgeQueryResult) => {
        this.knowledgeEditLoading = false;
        this.knowledgeCardTitle = result.title;
        this.knowledgeCardDefinition = result.definition;
        this.knowledgeSuggestedTags = result.tags ?? []; // ★ 0.202.1：AI 建议标签（勾选采纳）
        this.stopExtractTimer(); // ★ 0.153：成功停止计时清零
      },
      (error: string) => {
        this.knowledgeEditLoading = false;
        this.knowledgeEditError = this.friendlyKnowledgeError(error); // ★ 0.153：三分类友好中文提示
        this.stopExtractTimer();
      },
      (title: string, definition: string) => { // ★ 0.153：流式实时填充弹窗输入框
        this.knowledgeCardTitle = title;
        this.knowledgeCardDefinition = definition;
      });
  }

  // 关闭编辑弹窗并取消进行中的提炼请求（【取消】按钮 / 系统返回；
  // 遮罩不关闭弹窗——防误触丢草稿）
  closeKnowledgeEdit(): void {
    this.knowledgeEditVisible = false;
    if (this.knowledgeQueryController) {
      this.knowledgeQueryController.cancel();
      this.knowledgeQueryController = null;
    }
    this.stopExtractTimer(); // ★ 0.153：【取消】abort 请求 + 停止计时清零
  }

  // ★ 0.202.1：建议标签勾选/取消（knowledgeSelectedTags 逗号串增删）
  isTagPicked(t: string): boolean {
    return parseTags(this.knowledgeSelectedTags).includes(t);
  }

  toggleSuggestedTag(t: string): void {
    const picked = parseTags(this.knowledgeSelectedTags);
    const idx = picked.indexOf(t);
    if (idx >= 0) {
      picked.splice(idx, 1);
    } else {
      picked.push(t);
    }
    this.knowledgeSelectedTags = picked.join(',');
  }

  // ★ 0.202.2：标签长按修改 / 自定义添加（old='' 即新增模式）——mini 编辑弹窗
  @Local tagEditVisible: boolean = false;
  @Local tagEditOld: string = '';
  @Local tagEditNew: string = '';

  openTagEdit(old: string): void {
    this.tagEditOld = old;
    this.tagEditNew = old;
    this.tagEditVisible = true;
  }

  commitTagEdit(): void {
    const nv = this.tagEditNew.trim();
    if (nv.length === 0) {
      this.tagEditVisible = false;
      return;
    }
    if (this.tagEditOld.length === 0) {
      // 新增自定义标签：进建议列表并自动勾选
      if (!this.knowledgeSuggestedTags.includes(nv)) {
        this.knowledgeSuggestedTags = [...this.knowledgeSuggestedTags, nv];
      }
      this.toggleSuggestedTag(nv);
    } else if (nv !== this.tagEditOld) {
      // 改名：建议列表与已勾选串同步替换
      this.knowledgeSuggestedTags = this.knowledgeSuggestedTags.map((t: string): string => t === this.tagEditOld ? nv : t);
      const picked = parseTags(this.knowledgeSelectedTags).map((t: string): string => t === this.tagEditOld ? nv : t);
      this.knowledgeSelectedTags = picked.join(',');
    }
    this.tagEditVisible = false;
  }

  // 【保存入库】：输入框内容转 KnowledgeCard 入库（用户确认后的最终卡片）。
  // 标题与定义全空时不入库（空卡片防御）。★ 0.202.1：勾选的建议标签随卡保存。
  saveKnowledgeCard(): void {
    const title = this.knowledgeCardTitle.trim();
    const definition = this.knowledgeCardDefinition.trim();
    if (title.length === 0 && definition.length === 0) {
      return;
    }
    const card = new KnowledgeCard(generateMessageId(), title, definition, this.knowledgeImageUri, Date.now(), 0, 0, 0, 0, this.knowledgeSelectedTags);
    addKnowledgeCard(this.knowledgeBank, card);
    this.closeKnowledgeEdit();
  }

  // 选择卡片配图：相册单选 → base64 data URI（跟随图片消息的既有存储模式，重启不丢）
  async selectKnowledgeImage(): Promise<void> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select({ maxSelectNumber: 1 });
      if (result.photoUris.length > 0) {
        const uri = result.photoUris[0];
        const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
        const stat = fileIo.statSync(file.fd);
        const arrayBuffer = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, arrayBuffer);
        fileIo.closeSync(file);
        const base64 = buffer.from(arrayBuffer).toString('base64');
        this.knowledgeImageUri = `data:image/jpeg;base64,${base64}`;
      }
    } catch (err) {
      // 选图取消/读取失败静默忽略（防崩溃）
    }
  }

  // 全屏预览卡片配图（复用图片浏览器；关闭预览后编辑弹窗仍在）
  openKnowledgeImagePreview(): void {
    if (this.knowledgeImageUri.length === 0) {
      return;
    }
    this.imageViewerImages = [this.knowledgeImageUri];
    this.imageViewerIndex = 0;
    this.imageViewerVisible = true;
  }

  // 复习区知识卡片：按消息 ID 取 N 张（N=知识卡片数量，知识库 ⚙ 设置）。
  // ★ 0.188.0：知识库复刻记忆算法——选卡改走遗忘曲线（到期卡按 R 升序 → 新卡 → 未来卡）；
  // 缓存按消息 ID 永久固定（同 0.187.0 单词库修复：杜绝加卡触发全量重抽的虚假复习），
  // 已删除的卡读取时滤除；展示即复习（到期闸门防抖）。
  getKnowledgeCards(messageId: string): KnowledgeCard[] {
    const cached = this.knowledgeReviewCache.get(messageId);
    if (cached) {
      return cached.items.filter((c: KnowledgeCard) => this.knowledgeBank.cards.includes(c));
    }
    const now = Date.now();
    const items = pickReviewCards(this.knowledgeBank, this.knowledgeCountStore.knowledgeCount, now);
    for (let i = 0; i < items.length; i++) {
      applyPassiveReview(items[i], now);
    }
    recordStat(this.statStore, 'siyi', items.length, 0); // ★ 0.202.3：司忆量埋点
    this.knowledgeReviewCache.set(messageId, new KnowledgeReviewCacheEntry(0, items));
    return items;
  }

  // ★ 0.145：划词悬浮操作栏（bindSelectionMenu 自定义菜单——完全替代系统小艺菜单）
  @Builder
  SelectionToolbar() {
    Row() {
      Text('翻译')
        .fontSize(14)
        .fontColor(BRAND_SECONDARY)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.onToolbarTranslate();
        })
      Divider()
        .vertical(true)
        .height(16)
        .color(STROKE_CARD)
      // ★ 0.146：入知识库——选中原文交 AI 提炼草稿，编辑弹窗二次修改后入库
      Text('入知识库')
        .fontSize(14)
        .fontColor(BRAND_SECONDARY)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.onToolbarAddKnowledge();
        })
      Divider()
        .vertical(true)
        .height(16)
        .color(STROKE_CARD)
      // ★ 0.191.0 重做：标记移到「复制」左边 + 白字（用户定稿）；仅可标记 key 显示
      // （AI 正文文本段/代码块/表格格；用户消息/复习区/放大页不显示）
      // ★ 0.191.0 定稿：划选首字符已被标记 → 按钮变「取消标记」（标记/取消统一走工具栏，无独立清除入口）
      if (this.isBookmarkTargetKey(this.selKey)) {
        Text(this.bookmarkBtnLabel())
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .onClick(() => {
            this.onToolbarBookmark();
          })
        Divider()
          .vertical(true)
          .height(16)
          .color(STROKE_CARD)
      }
      Text('复制')
        .fontSize(14)
        .fontColor(TEXT_PRIMARY)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.onToolbarCopy();
        })
      Divider()
        .vertical(true)
        .height(16)
        .color(STROKE_CARD)
      // ★ 0.191.0：「全选」按钮移除（用户定稿——工具栏过长致「删除」超出屏幕边界；
      //   代码块工具栏的全选保留：顶替已删的顶栏⧉复制按钮，全选→复制整段代码）
      // ★ 0.160：划词删除——AI 超长回复时免滚到 × 按钮就地删本条消息；
      // 红色警示（破坏性操作），确认防误触与 × 按钮共享状态
      Text('删除')
        .fontSize(14)
        .fontColor(DANGER)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.onToolbarDelete();
        })
    }
    .backgroundColor(SURFACE_NODE)
    .borderRadius(RADIUS_CONTROL)
    .border({ width: 0.5, color: STROKE_CARD })
    .shadow({ radius: 12, color: 'rgba(0,0,0,0.25)', offsetX: 0, offsetY: 4 })
  }

  // ★ 0.169.1：复习区划词悬浮操作栏——AI 气泡底部生词/知识卡复习区专用（翻译 | 入知识库 | 复制）。
  // 与正文 SelectionToolbar 的差异：无「全选」（复习词条恒单行超短文本，全选无意义）、
  // 无「删除」（复习区文本不对应可删消息，删除入口只保留消息 × 按钮）。
  // 三个按钮动作与正文完全复用（onToolbarTranslate/onToolbarAddKnowledge/onToolbarCopy 均取 selText）。
  @Builder
  ReviewSelectionToolbar() {
    Row() {
      Text('翻译')
        .fontSize(14)
        .fontColor(BRAND_SECONDARY)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.onToolbarTranslate();
        })
      Divider()
        .vertical(true)
        .height(16)
        .color(STROKE_CARD)
      Text('入知识库')
        .fontSize(14)
        .fontColor(BRAND_SECONDARY)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.onToolbarAddKnowledge();
        })
      Divider()
        .vertical(true)
        .height(16)
        .color(STROKE_CARD)
      Text('复制')
        .fontSize(14)
        .fontColor(TEXT_PRIMARY)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.onToolbarCopy();
        })
    }
    .backgroundColor(SURFACE_NODE)
    .borderRadius(RADIUS_CONTROL)
    .border({ width: 0.5, color: STROKE_CARD })
    .shadow({ radius: 12, color: 'rgba(0,0,0,0.25)', offsetX: 0, offsetY: 4 })
  }

  // 全屏图片浏览器：收集当前对话所有图片，定位点击的图片，打开 viewer
  openImageViewer(clickedUrl: string): void {
    if (!this.currentBubble) {
      return;
    }
    const allImages: string[] = [];
    const messages = this.currentBubble.messages;
    for (let i = 0; i < messages.length; i++) {
      const urls = messages[i].imageUrl;
      for (let j = 0; j < urls.length; j++) {
        if (urls[j].length > 0) {
          allImages.push(urls[j]);
        }
      }
    }
    if (allImages.length === 0) {
      return;
    }
    const idx = allImages.indexOf(clickedUrl);
    this.imageViewerImages = allImages;
    this.imageViewerIndex = idx >= 0 ? idx : 0;
    this.imageViewerVisible = true;
  }

  addBubble(carryImages: string[] = [], carryText: string = ''): void {
    if (!this.currentBubble) {
      return;
    }
    if (this.isLoading) {
      return; // ★ 0.151-D：流式回复进行中禁止新建——切换当前气泡会导致流式回调写错气泡
    }
    // ★ 0.162：过渡动画防抖——上一次切换动画未播完前忽略重复点击
    if (this.branchAnimating) {
      return;
    }
    this.branchAnimating = true;
    // ★ 0.151-D 需求 3：直接进入新子气泡的对话页（跳过「返回画布 + 双击气泡」两步）——
    // 先建节点入库，再播「淡出→切换→淡入」过渡（★ 0.162：原实现瞬间切换 currentBubbleStore，
    // 消息列表瞬间清空重载刷屏过快，空消息页时用户不知道是否跳转了；现在切换发生在透明态）
    const newBubble = new BubbleNode(
      generateNodeId(),
      this.currentBubbleId,
      [],
      this.currentBubbleStore.bubbleX + 80 + Math.floor(Math.random() * 40),
      this.currentBubbleStore.bubbleY + 80 + Math.floor(Math.random() * 40),
      this.currentBubbleStore.bubbleX,
      this.currentBubbleStore.bubbleY
    );
    this.store.nodeList = [...this.store.nodeList, newBubble];
    recordStat(this.statStore, 'bubble', 0, 0); // ★ 0.192.0：统计埋点——创建子气泡 +1
    this.saveTree(); // ★ 0.151：按模式分池保存
    this.store.needsRelayout = true; // ★ 0.126：通知 BBTreeCanvas 重新布局（返回画布时 onShown 消费）
    this.stopTTS(); // ★ 0.151-D：切气泡前补停 TTS（原依赖 pop 退页触发 aboutToDisappear，直接切气泡须在此停）
    this.recordReadingPosition(); // ★ 0.191.0：切气泡前记录阅读高度（此路径不触发 aboutToDisappear，须手动记录）
    // ★ 0.162 第一段：消息区淡出 140ms（EaseIn 加速消失，模拟「页面关闭」）
    this.getUIContext().animateTo({
      duration: 140,
      curve: Curve.EaseIn,
      onFinish: () => {
        // 第二段：淡出完成后才切换气泡——列表清空/重载发生在透明态，用户看不见闪变
        this.currentBubbleStore.nodeID = newBubble.nodeID;
        this.currentBubbleStore.bubbleX = newBubble.x;
        this.currentBubbleStore.bubbleY = newBubble.y;
        this.inputText = carryText;  // ★ 0.184.0：携带补充要求带入新气泡（圈注「创建子气泡」）；默认空串 = 原清空行为不变
        // ★ 0.166.1：携带图片带入新气泡（圈注「创建子气泡」的标注图）；默认空数组 = 原清空行为不变
        this.pendingImages = carryImages;
        // ★ 0.162 第三段：消息区淡入 300ms（EaseOut 减速浮现，模拟「页面打开」）；
        // 淡出 140ms + 淡入 300ms ≈ 440ms，落在用户要求的 0.3~0.5s 区间
        this.getUIContext().animateTo({
          duration: 300,
          curve: Curve.EaseOut,
          onFinish: () => {
            this.branchAnimating = false; // 动画播完解锁
            this.restoreReadingPosition(); // ★ 0.191.0：切气泡后恢复阅读位置（新气泡无记忆/书签→自然落底部，等价原行为）
          }
        }, () => {
          this.msgAreaOpacity = 1;
        });
      }
    }, () => {
      this.msgAreaOpacity = 0;
    });
  }

  // ============================================================
  // ★ 0.152：屏幕圈选标注——截图入口 + 结果消费
  // ============================================================
  // 截图路线：UIContext.getComponentSnapshot().get（APP 内组件快照，截取自身界面）——
  // 无需系统截屏权限（CAPTURE_SCREEN 为 system_basic 级，三方应用不可申请），
  // 也天然不存在「系统隐私页黑屏」问题；截图失败保留友好提示兜底。
  // 图片策略：base64 data URI 全程传递（与相册图片消息/知识卡片配图同模式），
  // 不写系统相册、不产生临时文件——随消息/卡片生命周期存续，无 24h 清理负担。

  // ✏️ 画画按钮入口：首次使用先弹说明（需求文案：用于屏幕圈选标注提问，不会后台录制屏幕），
  // 确认后记 flag 永不再弹；非首次直接进入截图流程
  startAnnotation(): void {
    if (this.annotationPref.notifyShown) {
      this.continueAnnotation();
      return;
    }
    this.annotationNotifyVisible = true;
  }

  // 首次说明弹窗「知道了」：记 flag + 继续截图
  confirmAnnotationNotify(): void {
    this.annotationPref.notifyShown = true;
    this.annotationNotifyVisible = false;
    this.continueAnnotation();
  }

  // 收起软键盘后延时截图——键盘弹出时内容区被压缩，立即截会截到压缩布局
  continueAnnotation(): void {
    this.getUIContext().getFocusController().clearFocus();
    setTimeout(() => {
      this.captureAndEnterAnnotation();
    }, 300); // 300ms 等键盘收起 + 布局恢复
  }

  // 截取当前页面内容区 → base64 → 写入草稿 store → 进入标注页
  async captureAndEnterAnnotation(): Promise<void> {
    try {
      // get 失败（组件 id 无效/系统资源不足）会 reject → 走 catch 友好提示
      const pm: image.PixelMap = await this.getUIContext().getComponentSnapshot().get('chatSnapshotRoot');
      const packer = image.createImagePacker();
      // packToData（API 13+）：packing(PixelMap) 已废弃的替代，PixelMap → ArrayBuffer
      const data: ArrayBuffer = await packer.packToData(pm, { format: 'image/jpeg', quality: 90 });
      packer.release();
      pm.release(); // 截图 PixelMap 已打包完，释放
      const base64 = buffer.from(data).toString('base64');
      this.annotationDraft.imageUri = `data:image/jpeg;base64,${base64}`;
      this.pathStack.pushPath({ name: 'AnnotationPage' });
    } catch (e) {
      // 截图失败友好提示（对应需求「捕获失败/黑屏做友好提示」的兜底）
      this.showToastSafe('截图失败，请重试');
    }
  }

  // ★ 0.200.0：知识卡片导入落地（画布确认导航进来时 onShown 触发；action 空 = 普通进入直接跳过）
  // 文字格式：📚 知识卡片｜标题 + 定义 + 「（我想问：）」引导行——不自动发送，等用户补充问题（用户拍板）
  consumeCardImport(): void {
    track(this.getUIContext().getHostContext() as common.Context, 'import_to_bubble'); // 0.206.0 埋点：知识卡片导入气泡
    const action = this.cardImport.action;
    if (action.length === 0) {
      return;
    }
    // 一次性消费（立即清空，防 onShown 重复触发）
    const title = this.cardImport.title;
    const definition = this.cardImport.definition;
    const imageUrisJson = this.cardImport.imageUrisJson;
    this.cardImport.action = '';
    this.cardImport.title = '';
    this.cardImport.definition = '';
    this.cardImport.imageUrisJson = '[]';
    const text = `📚 知识卡片｜${title}\n${definition}\n\n（我想问：）`;
    // ★ 0.202.2：多图全链路——卡片图组 JSON 解析（损坏回落空数组）
    let imgs: string[] = [];
    try {
      const parsed = JSON.parse(imageUrisJson) as string[];
      if (Array.isArray(parsed)) {
        imgs = parsed;
      }
    } catch (e) {
      imgs = [];
    }
    // 渐显动画起手（L3 末拍）：0 → 1
    this.importArrived = 0;
    if (action === 'import') {
      // ① 导入对话：文字填输入框（已有草稿换行追加，圈注 import 同规则）+ 图挂输入区
      this.pendingImages = [...this.pendingImages, ...imgs];
      this.saveDraft(); // 0.214.2 图片变化实时写回草稿
      this.inputText = this.inputText.length > 0 ? `${this.inputText}\n${text}` : text;
    } else {
      // ② 创建子气泡：复用圈注 branch 全套（isLoading 降级 + carryText/carryImages 随 140ms 回调带入）
      if (this.isLoading) {
        this.pendingImages = [...this.pendingImages, ...imgs];
      this.saveDraft(); // 0.214.2 图片变化实时写回草稿
        this.inputText = this.inputText.length > 0 ? `${this.inputText}\n${text}` : text;
        this.showToastSafe('AI 正在回复，卡片已导入当前对话，回复完成后可再创建子气泡');
      } else {
        this.addBubble(imgs, text);
      }
    }
    setTimeout(() => {
      animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
        this.importArrived = 1;
      });
    }, 60);
  }

  // 标注页 pop 回来时消费结果（NavDestination.onShown 触发；action 空 = 非标注返回，直接跳过）
  consumeAnnotationResult(): void {
    const action = this.annotationResult.action;
    if (action.length === 0) {
      return;
    }
    const img = this.annotationResult.imageUri;
    const note = this.annotationResult.note; // ★ 0.184.0：标注页补充要求（图+文一起消费）
    // 立即清空结果 store（一次性消费，防重复触发）
    this.annotationResult.action = '';
    this.annotationResult.imageUri = '';
    this.annotationResult.note = '';
    if (action === 'import') {
      // ① 当前对话导入：图片挂到输入区（可追加文字后点发送，走现有 sendMessage 链路）；
      //    ★ 0.184.0：补充要求填入输入框（输入框已有草稿时换行追加，不覆盖）
      this.pendingImages = [...this.pendingImages, img];
      this.saveDraft(); // 0.214.2 图片变化实时写回草稿
      if (note.length > 0) {
        this.inputText = this.inputText.length > 0 ? `${this.inputText}\n${note}` : note;
      }
    } else if (action === 'branch') {
      // ② 创建子气泡分支：调现有 addBubble（新建子节点 + 切换 + 继承父链路），
      //    图片挂到新气泡输入区；发送时 buildBranchMessageList 沿 parentID 回溯——
      //    10+15 上下文规则与底层消息链路零改动
      if (this.isLoading) {
        // 流式回复中禁止切气泡（addBubble 现有防御：切换会导致流式回调写错气泡）——
        // 降级为导入当前对话并提示，图片与补充要求都不丢
        this.pendingImages = [...this.pendingImages, img];
      this.saveDraft(); // 0.214.2 图片变化实时写回草稿
        if (note.length > 0) {
          this.inputText = this.inputText.length > 0 ? `${this.inputText}\n${note}` : note;
        }
        this.showToastSafe('AI 正在回复，图片已导入当前对话，回复完成后可再创建子气泡');
        return;
      }
      // ★ 0.166.1 修复：图片必须随 addBubble 的切换回调带入——0.162 动画改造后清空发生在
      // 140ms onFinish 回调里，原先「addBubble 后同步塞图」会被回调清空（圈注图丢失根因）
      // ★ 0.184.0：文字同模式随回调带入（carryText），避免被同一回调清空
      this.addBubble([img], note);
    } else if (action === 'knowledge') {
      // ③ 存入知识库：打开卡片编辑弹窗，标注图作配图，AI 多模态提炼草稿（用户二次编辑后入库）
      //    ★ 0.184.0：图片+补充要求一起发给 AI，按用户指定方向精准提炼
      this.openKnowledgeFromImage(img, note);
    }
  }

  // 圈选截图 → 知识库卡片：编辑弹窗预填配图 + 多模态 AI 提炼标题/定义草稿
  //（与 onToolbarAddKnowledge 同流程，仅数据源从划词文本换成标注图）
  // ★ 0.184.0：note = 标注页补充要求（空串 = 原纯图提炼行为不变）
  openKnowledgeFromImage(img: string, note: string): void {
    this.knowledgeEditVisible = true;
    this.knowledgeCardTitle = '';
    this.knowledgeCardDefinition = '';
    this.knowledgeSuggestedTags = []; // ★ 0.202.1：建议标签清空（新会话）
    this.knowledgeSelectedTags = '';
    this.knowledgeImageUri = img; // 标注合成图直接作卡片配图
    this.knowledgeEditLoading = true;
    this.knowledgeEditError = '';
    this.refreshEditReview(); // ★ 0.160：抽一组复习内容——提炼等待期顺便学习
    if (this.knowledgeQueryController) {
      this.knowledgeQueryController.cancel(); // 上一次提炼未完成 → 取消
    }
    this.startExtractTimer(); // ★ 0.153：秒表从 0 开始计数
    this.knowledgeQueryController = queryKnowledgeFromImage(img, note, this.apiConfig,
      (result: KnowledgeQueryResult) => {
        this.knowledgeEditLoading = false;
        this.knowledgeCardTitle = result.title;
        this.knowledgeCardDefinition = result.definition;
        this.knowledgeSuggestedTags = result.tags ?? []; // ★ 0.202.1：AI 建议标签（勾选采纳）
        this.stopExtractTimer(); // ★ 0.153：成功停止计时清零
      },
      (error: string) => {
        this.knowledgeEditLoading = false;
        this.knowledgeEditError = this.friendlyKnowledgeError(error); // ★ 0.153：三分类友好中文提示
        this.stopExtractTimer();
      },
      (title: string, definition: string) => { // ★ 0.153：流式实时填充弹窗输入框
        this.knowledgeCardTitle = title;
        this.knowledgeCardDefinition = definition;
      });
  }

  // ★ 0.151-bugfix：按模式分池保存工作区（两池隔离核心写路径，与 BBTreeCanvas.saveTree 同逻辑）
  // flat：工作区 = 平铺树 → 存回 bubbleTreeJson（现状路径）
  // tabs：工作区 = 当前 Tab 树 → 存回该 Tab 的 treeJson；
  //       无 activeTab 时【不写任何池】——此时工作区必为空（applyCanvasModeSwitch 保证），
  //       若写平铺池会把空树覆盖平铺池真实数据（用户实测丢树根因：切 tabs 后点 ➕，
  //       addTab 先走 saveTree 兜底、把空工作区写进 bubbleTreeJson，平铺池被清空）
  saveTree(): void {
    if (this.canvasModeStore.mode === 'tabs') {
      const tabs = parseTabs(this.tabForest.tabsJson);
      const idx = tabs.findIndex((t: TabMeta): boolean => t.id === this.tabForest.activeTabId);
      if (idx >= 0) {
        tabs[idx].treeJson = serializeBubbleTree(this.store);
        // ★ 0.151-bugfix2：Tab 名同步为树根显示名（聊天后根的第一条消息变化，Tab 名跟随根气泡）
        const root = this.store.nodeList.find((n: BubbleNode): boolean => n.parentID === null);
        if (root !== undefined) {
          tabs[idx].name = getRootDisplayName(root);
        }
        this.tabForest.tabsJson = serializeTabs(tabs);
        upsertCloudData('tabs_pool', this.tabForest.tabsJson); // ★ 0.165.1：云同步桥接（Tab 池快照上云）
      }
      // 无 activeTab：无主工作区无可保存内容，直接跳过（不写任何池）
    } else {
      this.persistData.bubbleTreeJson = serializeBubbleTree(this.store);
      upsertCloudData('flat_pool', this.persistData.bubbleTreeJson); // ★ 0.165.1：云同步桥接（平铺池快照上云）
    }
  }

  // ★ 0.150：AI 偏好 prompt 拼接——按用户设置（全局设置弹窗 Tab2）生成 system 指令（称呼 + 鼓励），
  // sendMessage/regenerateMessage 在长度 prompt 之后追加（不持久化、不进入后续上下文，与播客 prompt 同机制）。
  // 规则：称呼填写时短/中/长全部回复模式都带；鼓励仅在中/长回复且档位非关闭时生成（短回复不生成）；
  // ★ 0.191.0：鼓励三档（用户定稿）——off=无 / light=轻度（1~2 句温和，原文不动）/
  //   heavy=重度（2~4 句狂热夸张，含「未来的爱因斯坦」「嫁给你生猴子」式吹捧，用户指定示例词）
  buildPreferencePrompt(): string {
    let prompt = '';
    const nickname = this.aiPreference.aiNickname.trim();
    if (nickname.length > 0) {
      prompt += `请在回答中自然地称呼用户为「${nickname}」。`;
    }
    if (this.aiPreference.encourageMode !== 'off' && this.replyLengthMode !== 'short') {
      if (this.aiPreference.encourageMode === 'heavy') {
        prompt += ENCOURAGE_HEAVY_PROMPT;
      } else {
        prompt += ENCOURAGE_LIGHT_PROMPT;
      }
    }
    return prompt;
  }

  // ★ 0.159：返回逻辑统一入口——顶栏自定义返回按钮与系统返回手势（onBackPressed）共用；
  // 有弹窗打开时逐个关闭并返回 true（消费返回事件），全关时返回 false（由调用方执行导航）
  handleBack(): boolean {
    if (this.imageViewerVisible) {
      this.imageViewerVisible = false; // 图片预览（0.120）
      return true;
    }
    if (this.wordPopupVisible) {
      this.closeWordPopup(); // 翻译浮窗，取消查词请求（0.145）
      return true;
    }
    if (this.knowledgeEditVisible) {
      this.closeKnowledgeEdit(); // 知识编辑弹窗，取消提炼请求（0.146）
      return true;
    }
    if (this.codeZoomVisible) {
      this.codeZoomVisible = false; // 代码块放大弹窗（0.153）
      return true;
    }
    if (this.tableZoomVisible) {
      this.tableZoomVisible = false; // 表格放大弹窗（0.153）
      return true;
    }
    if (this.globalSettingsVisible) {
      this.globalSettingsCloseReq++; // ★ 0.150：全局设置弹窗——递增计数器触发弹窗内 requestClose（有未保存修改时二次确认，不直接丢弃）
      return true;
    }
    if (this.annotationNotifyVisible) {
      this.annotationNotifyVisible = false; // ★ 0.152：屏幕圈选首次说明弹窗（未确认则下次再提示）
      return true;
    }
    return false; // 无弹窗，由调用方执行默认返回
  }

  // ★ 0.159：顶栏改内容区自绘行——0.158 用 .title() 自定义标题行时，title 内容区宽度参照系含系统返回按钮占位，
  // width('100%') 解析后比可用区宽 → 按钮组溢出屏幕右侧（真机截图实证）；
  // 改为 hideTitleBar + 内容区自绘：返回按钮 + 「对话」标题 + 按钮组同一行，宽度参照系=屏幕宽（可靠）；
  // 按钮右对齐、间距收紧（压 Button 默认内边距 + margin 4~6vp，用户要求：不平均分布、宽度集中），
  // 右侧留白 16vp 与消息区 List 左右 padding 对齐
  @Builder
  topBarTitle() {
    Row() {
      // ★ 0.195.0：返回箭头改大屏专属（用户定稿：大屏保留——无侧滑习惯缺出口；小屏取消——侧滑返回是常识）；
      //   侧滑拦截逻辑仍在 onBackPressed（先关弹窗再退页，行为不变）
      if (this.isTablet) {
        Button('←')
          .fontSize(18)
          .backgroundColor(Color.Transparent)
          .fontColor(TEXT_PRIMARY)
          .padding({ left: 4, right: 4 })
          .margin({ right: 4 })
          .onClick(() => {
            if (!this.handleBack()) {
              this.pathStack.pop();
            }
          })
      }
      // ★ 0.196.5：标题列 space 2 对齐画布信息条（Column({space:2}){标题,统计}）——
      //   两列内容规格完全一致（16/600/Inter-SemiBold + 11/TEXT_SECONDARY/Inter）+ 同高 Row 居中 → 标题 y 像素级一致
      Column({ space: 2 }) {
        Text('气泡') // ★ 0.195.0：标题「对话」→「气泡」（用户定稿——页面主体是气泡对话，与气泡树命名体系统一）
          .fontSize(FONT_SIZE_SCREEN_TITLE) // ★ 0.181.0：顶栏标题对齐 ScreenTitle（18 Bold→16 SemiBold）
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
          .fontFamily(FONT_INTER_SEMIBOLD) // ★ 0.196.3：字体对齐气泡树信息条标题（用户实测两页视觉不一）
        // ★ 0.195.0：副标题统计行（模仿气泡树「N 个气泡 · N 条对话」——用户需求：知道当前对话已有多少条）
        // ★ 0.196.3：颜色/字体/间距全对齐气泡树统计行（用户实测「一亮一暗、高度不一样」——
        //   原 TEXT_TERTIARY(暗)+无 fontFamily+margin 1 → TEXT_SECONDARY(亮)+FONT_INTER+去 margin，以气泡树为准）
        Text(`${this.currentMessages.length} 条对话`)
          .fontSize(11)
          .fontColor(TEXT_SECONDARY)
          .fontFamily(FONT_INTER)
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
        .layoutWeight(1)
      // ★ 0.195.0：顶栏 emoji 图标（📚📖⚙ 彩色）换边栏同款单色 svg——UI 统一（用户拍板：与边栏
      //   单词库/知识库/设置同款；映射与边栏 navIcon 一致：wordbank=bookopen、knowledge=library）
      Row() {
        Image($r('app.media.bookopen'))
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
      }
      .height(40) // ★ 0.196.5：icon 包裹行 40vp——撑起顶栏 Row 与画布 ➕ 同高，标题列居中位置两页一致（像素级对齐）
      .padding({ left: 4, right: 4 }) // ★ 0.195.0：去 margin——相邻 icon 边缘间距 4+4=8vp（对齐单词库 ⚙↔+，实测原 12vp 不一致）
      .onClick(() => {
        this.pathStack.pushPath({ name: 'WordBankPage' });
      })
      Row() {
        Image($r('app.media.library'))
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
      }
      .height(40) // ★ 0.196.5：同上——40vp 撑高
      .padding({ left: 4, right: 4 }) // ★ 0.195.0：去 margin——8vp 间距统一
      .onClick(() => {
        this.pathStack.pushPath({ name: 'KnowledgeBankPage' });
      })
      Row() {
        Image($r('app.media.settings'))
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
      }
      .height(40) // ★ 0.196.5：同上——40vp 撑高
      .padding({ left: 4, right: 4 }) // ★ 0.195.0：去 margin——8vp 间距统一（Row 自身 right padding 16 收尾）
      .onClick(() => {
        this.globalSettingsVisible = true; // ★ 0.150：改唤全局设置弹窗（原 SettingsPage 页面入口由弹窗替代）
      })
    }
    .width('100%')
    .height(56) // ★ 0.196.7：顶栏 Row 40→56——height 含 padding，原 40+padding8/8 把内容区压到 24vp（icon 包裹行 40vp 溢出居中，顶栏整体比树页高 8vp：icons 中心 y137 vs 树页➕ y157，Pad 实测）；56=8padding+40内容+8padding，与树页外层 Column frame 等效（UI_GUIDELINES 10.2）
    //   修复后：Row frame y88-228≈树页 Column 88-227，内容区 40vp y108-208≈树页 107-207，标题列自然高 34vp 居中=树页逐像素一致
    .padding({ left: this.isTablet ? 28 : 14, right: 14, top: 8, bottom: 8 }) // ★ 0.195.0：顶栏左/上间距以气泡树信息条为准（Pad 实测：信息条标题 590px vs 本页 540px 差 20vp；left 28/14=信息条 ≥520 双分支，top 8/right 14 同款）
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
        // ★ 0.159：顶栏自绘行（返回按钮 + 「对话」标题 + 按钮组）——弃用 .title()（其内容区宽度参照系
        // 含系统返回按钮占位导致按钮组溢出屏幕右侧），hideTitleBar 后在内容区顶部渲染，宽度参照系=屏幕宽
        this.topBarTitle()

        // 消息列表 — 直接由 @Computed currentMessages 驱动
        if (this.currentMessages.length === 0) {
          Column() {
            Text('暂无对话')
              .fontSize(16)
              .fontColor(TEXT_TERTIARY)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .opacity(this.msgAreaOpacity) // ★ 0.162：分支切换过渡动画挂点（空态分支）
        } else {
          List({ space: 12, scroller: this.scroller }) {
            ForEach(this.currentMessages, (msg: ChatMessage) => {
              ListItem() {
                Row() {
                  // ★ 0.147：AI 消息气泡贴右（0.145），删除按钮移到气泡左侧——否则 × 被挤到屏幕最右缘
                  if (msg.role === 'assistant') {
                    Button('×')
                      .fontSize(16)
                      .fontColor(DANGER)
                      .backgroundColor(Color.Transparent)
                      .padding({ left: 2, right: 2 }) // ★ 0.148：压掉 Button 默认大内边距（≈32vp），给气泡留宽度
                      .margin({ right: 4 })
                      .onClick(() => {
                        this.requestDeleteMessage(msg.messageId); // ★ 0.150：先弹确认防误触
                      })
                  }
                  Column() {
                    // 图片缩略图（在文字上方）
                    if (msg.imageUrl.length > 0) {
                      Row() {
                        ForEach(msg.imageUrl, (url: string) => {
                          Image(url)
                            .width(80)
                            .height(80)
                            .borderRadius(RADIUS_CONTROL)
                            .margin({ right: 4 })
                            .onClick(() => {
                              this.openImageViewer(url);
                            })
                        }, (url: string) => url)
                      }
                      .margin({ bottom: 4 })
                    }
                    // 文字内容（非空才显示）
                    if (msg.content.length > 0) {
                      if (msg.role === 'user') {
                        // 用户消息：纯文本渲染（保持原有逻辑）
                        // ★ 0.145：划词翻译——controller 供关闭菜单；长按进入系统选择模式并弹自研悬浮操作栏（替代原「选择文本/删除」弹窗，禁用小艺原生菜单）
                        Text(msg.content, { controller: this.getOrCreateTextController(`${msg.messageId}|u`) })
                          .fontSize(this.fs(16))
                          .lineHeight(this.fs(24))
                          .fontColor(TEXT_PRIMARY)
                          .padding(10)
                          .borderRadius(RADIUS_NODE) // ★ 0.181.0：气泡圆角对齐节点卡片规格（8→18）
                          .backgroundColor(SURFACE_NODE) // ★ 0.195.0：用户气泡底色改与 AI 气泡一致（原主紫 BRAND_PRIMARY，用户拍板「调成一样」）
                          .copyOption(CopyOptions.LocalDevice)
                          .constraintSize({ maxWidth: '90%' }) // ★ 0.190.3：气泡最大宽度 85%→90%（用户要求对话列表再加宽一点点）；0.148 原约束——长文本自动换行，防溢出屏幕
                          // ★ 0.145：长按弹自研选择工具栏；onAppear 记录来源 key，onDisappear 清理选中状态
                          .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, TextResponseType.LONG_PRESS, {
                            onAppear: () => {
                              this.selKey = `${msg.messageId}|u`;
                            },
                            onDisappear: () => {
                              this.clearSelectionState();
                            }
                          })
                          // ★ 0.145：选中变化回调——闭包捕获 msg.content，按段内偏移截取选中文本
                          .onTextSelectionChange((start: number, end: number) => {
                            this.handleSelectionChange(`${msg.messageId}|u`, msg.content, start, end);
                          })
                          // ★ 0.145：全选受控——selectAllKey 命中本段时全选（nonce 递增确保重复点击仍触发重应用）；未命中时 (1, 0) 不选中
                          .selection(
                            this.selectAllKey.startsWith(`${msg.messageId}|u|`) ? 0 : 1,
                            this.selectAllKey.startsWith(`${msg.messageId}|u|`) ? msg.content.length : 0
                          )
                       } else {
                         // ★ 0.146：包裹容器——气泡与操作行组成同宽块，token 统计行左缘对齐气泡左缘（用户要求）
                         Column() {
                         // ★ AI 消息：Markdown 分段渲染（0.121）
                          // ★ 0.160.1 三次修复：删除占位行 Row——占位文字（LOADING/THINKING）本身就是 msg.content，
                          // 由下方 Markdown 通道渲染（原始行为，content @Trace 驱动，一直可靠）。此前占位行+
                          // Markdown 反向 visibility 双通道并存导致占位文字重复显示两次（已修复）。
                          // ★ 0.160.2：AI 回复秒表（⏱）已按用户决定整体移除，本区不再渲染任何计时组件。
                          Column() {
                           // ★ 0.190.5：等待态视图——占位文字（LOADING/THINKING）不再走 Markdown
                           //   通道渲染纯文本，改三点跳动动画+回复模式提示（长模式加耐心等待）；
                           //   Markdown 通道占位时传空串（parseMarkdown('') 零段渲染，不重复显示）
                           if (msg.content === PLACEHOLDER_LOADING || msg.content === PLACEHOLDER_THINKING) {
                              this.waitingView()
                           }
                            ForEach(this.parseMarkdown(msg.content === PLACEHOLDER_LOADING || msg.content === PLACEHOLDER_THINKING ? '' : msg.content), (seg: MdSegment, idx: number) => {
                             // ★ 0.191.0 定稿：清除入口已移除——标记/取消统一走划词工具栏
                             //   （划选已标记文字 → 按钮变「取消标记」），段落上方不再插任何小字行
                             if (seg.type === 0) {
                              // 普通文本段
                              // ★ 0.145：划词翻译——AI 文本段同样长按划词（key 纳入段索引 idx，与用户消息 key 空间隔离）
                              // ★ 0.191.0 重做：划词级书签——命中本段时按字符偏移拆三段 Span，
                              //   划选文字紫色+下划线（Span 不支持背景色，紫字+紫下划线为等效荧光笔方案）；未命中单 Span 原样
                              Text('', { controller: this.getOrCreateTextController(`${msg.messageId}|${idx}`) }) {
                                if (this.isBookmarkAt(`${msg.messageId}|${idx}`) && this.bmStart() >= 0 && this.bmEnd() > this.bmStart() && this.bmEnd() <= seg.content.length) {
                                  Span(seg.content.substring(0, this.bmStart()))
                                  Span(seg.content.substring(this.bmStart(), this.bmEnd()))
                                    .fontColor(BRAND_SECONDARY)
                                    .decoration({ type: TextDecorationType.Underline, color: BRAND_SECONDARY })
                                  Span(seg.content.substring(this.bmEnd()))
                                } else {
                                  Span(seg.content)
                                }
                              }
                                .fontSize(this.fs(16))
                                .lineHeight(this.fs(24))
                                .fontColor(TEXT_PRIMARY)
                                .copyOption(CopyOptions.LocalDevice)
                                // ★ 0.145：长按弹自研选择工具栏；onAppear 记录来源 key，onDisappear 清理选中状态
                                .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, TextResponseType.LONG_PRESS, {
                                  onAppear: () => {
                                    this.selKey = `${msg.messageId}|${idx}`;
                                  },
                                  onDisappear: () => {
                                    this.clearSelectionState();
                                  }
                                })
                                // ★ 0.145：选中变化回调——闭包捕获 seg.content，按段内偏移截取选中文本
                                .onTextSelectionChange((start: number, end: number) => {
                                  this.handleSelectionChange(`${msg.messageId}|${idx}`, seg.content, start, end);
                                })
                                // ★ 0.145：全选受控——selectAllKey 命中本段时全选；未命中时 (1, 0) 不选中
                                .selection(
                                  this.selectAllKey.startsWith(`${msg.messageId}|${idx}|`) ? 0 : 1,
                                  this.selectAllKey.startsWith(`${msg.messageId}|${idx}|`) ? seg.content.length : 0
                                )
                            }
                            if (seg.type === 1) {
                              // ★ 代码块：使用 CodeBlockView 组件，支持自动换行切换（0.122）
                              // ★ 0.156：划词桥接——key 用 `c${idx}` 前缀（与文本段纯数字 idx 空间隔离），
                              // controller 注册进父组件 map，工具栏/翻译/复制/全选链路完全复用
                              // ★ 0.191.0：代码块开放划词级标记——书签偏移传入（命中本块才传，否则 -1），
                              //   内部与语法 token 求交集拆分，marked 段紫色下划线
                              CodeBlockView({
                                content: seg.content,
                                lang: seg.lang, // ★ 0.149：语言标识（parseMarkdown 已提取，语法高亮+顶部标签）
                                fontScale: this.fontScale, // ★ 0.214.0：缩放透传
                                onZoom: (content: string, lang: string) => { this.openCodeZoom(content, lang); }, // ★ 0.153：左上角「放大」按钮回调；★ 0.149 加传 lang
                                textKey: `${msg.messageId}|c${idx}`,
                                selController: this.getOrCreateTextController(`${msg.messageId}|c${idx}`),
                                selectAllKey: this.selectAllKey,
                                bmStart: this.isBookmarkAt(`${msg.messageId}|c${idx}`) ? this.bmStart() : -1,
                                bmEnd: this.isBookmarkAt(`${msg.messageId}|c${idx}`) ? this.bmEnd() : -1,
                                bookmarkBtnLabel: this.bookmarkBtnLabel(),
                                onBookmark: () => { this.onToolbarBookmark(); },
                                // ★ 0.157：工具栏按钮动作经 @Event 回调（替代 @BuilderParam，修复子组件 this 丢失崩溃）
                                onTranslate: () => { this.onToolbarTranslate(); },
                                onAddKnowledge: () => { this.onToolbarAddKnowledge(); },
                                onCopy: () => { this.onToolbarCopy(); },
                                onSelectAll: () => { this.onToolbarSelectAll(); },
                                onMenuAppear: (key: string) => {
                                  this.selKey = key;
                                },
                                onMenuDisappear: () => {
                                  this.clearSelectionState();
                                },
                                onSelChange: (key: string, content: string, start: number, end: number) => {
                                  this.handleSelectionChange(key, content, start, end);
                                }
                              })
                            }
                            if (seg.type === 2) {
                              // ★ 0.153：表格重做——固定列宽对齐（layoutWeight 在横向 Scroll 内失去统一基准导致列错位）
                              // + 默认不换行（单行 + 超宽省略）+ 左上角「放大」按钮（全屏查看 + 换行切换）
                              Column() {
                                // 左上角放大按钮
                                // ★ 0.191.0 定稿：zoom.svg 矢量图标 + 深紫底方框圆角；★ 缩小 20×18/图标14
                                Row() {
                                  Image($r('app.media.zoom'))
                                    .width(14)
                                    .height(14)
                                }
                                .width(20)
                                .height(18)
                                .justifyContent(FlexAlign.Center)
                                .alignItems(VerticalAlign.Center)
                                .borderRadius(4)
                                .backgroundColor(SURFACE_HOVER)
                                .border({ width: 0.5, color: STROKE_BRAND })
                                .margin({ top: 4, bottom: 2 })
                                .onClick(() => {
                                  this.openTableZoom(seg.header, seg.rows);
                                })

                                // 表格主体：横向滚动 + 固定列宽（各行边界严格对齐）
                                Scroll() {
                                  Column() {
                                    // 表头行
                                    Row() {
                                      ForEach(seg.header, (cell: string, ci: number) => {
                                        // ★ 0.156：划词五件套——单元格内长按划词（翻译/复制/全选）；
                                        // key 用 `t${idx}h${ci}` 前缀（t=表格，与文本段纯数字 idx 空间隔离）
                                        // ★ 0.191.0 重做：划词级书签——命中本格时拆 Span，划选文字紫色+下划线
                                        Text('', { controller: this.getOrCreateTextController(`${msg.messageId}|t${idx}h${ci}`) }) {
                                          if (this.isBookmarkAt(`${msg.messageId}|t${idx}h${ci}`) && this.bmStart() >= 0 && this.bmEnd() > this.bmStart() && this.bmEnd() <= cell.length) {
                                            Span(cell.substring(0, this.bmStart()))
                                            Span(cell.substring(this.bmStart(), this.bmEnd()))
                                              .fontColor(BRAND_SECONDARY)
                                              .decoration({ type: TextDecorationType.Underline, color: BRAND_SECONDARY })
                                            Span(cell.substring(this.bmEnd()))
                                          } else {
                                            Span(cell)
                                          }
                                        }
                                          .fontSize(this.fs(14))
                                          .fontColor(TEXT_PRIMARY)
                                          .padding(8)
                                          .border({ width: 0.5, color: STROKE_CARD })
                                          .width(this.getTableColWidths(seg.header, seg.rows)[ci])
                                          .maxLines(1)
                                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                                          .textAlign(TextAlign.Center)
                                          .copyOption(CopyOptions.LocalDevice)
                                          .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, TextResponseType.LONG_PRESS, {
                                            onAppear: () => {
                                              this.selKey = `${msg.messageId}|t${idx}h${ci}`;
                                            },
                                            onDisappear: () => {
                                              this.clearSelectionState();
                                            }
                                          })
                                          .onTextSelectionChange((start: number, end: number) => {
                                            this.handleSelectionChange(`${msg.messageId}|t${idx}h${ci}`, cell, start, end);
                                          })
                                          .selection(
                                            this.selectAllKey.startsWith(`${msg.messageId}|t${idx}h${ci}|`) ? 0 : 1,
                                            this.selectAllKey.startsWith(`${msg.messageId}|t${idx}h${ci}|`) ? cell.length : 0
                                          )
                                       // ★ 0.191.0：key 纳入内容——流式中同格内容变化（列→列2）须触发重建，
                                       //   原 `h_${ci}` 恒定导致表头格停留在中间态（0.132 segment key 同款教训）
                                       }, (cell: string, ci: number) => `h_${ci}_${cell.length}_${cell.substring(0, 4)}`)
                                    }
                                    // 数据行
                                    ForEach(seg.rows, (row: string[], ri: number) => {
                                      Row() {
                                        ForEach(row, (cell: string, ci: number) => {
                                          // ★ 0.156：划词五件套——同表头（key 含行列号，每格独立 controller）
                                          // ★ 0.191.0 重做：划词级书签——命中本格时拆 Span，划选文字紫色+下划线
                                          Text('', { controller: this.getOrCreateTextController(`${msg.messageId}|t${idx}r${ri}c${ci}`) }) {
                                            if (this.isBookmarkAt(`${msg.messageId}|t${idx}r${ri}c${ci}`) && this.bmStart() >= 0 && this.bmEnd() > this.bmStart() && this.bmEnd() <= cell.length) {
                                              Span(cell.substring(0, this.bmStart()))
                                              Span(cell.substring(this.bmStart(), this.bmEnd()))
                                                .fontColor(BRAND_SECONDARY)
                                                .decoration({ type: TextDecorationType.Underline, color: BRAND_SECONDARY })
                                              Span(cell.substring(this.bmEnd()))
                                            } else {
                                              Span(cell)
                                            }
                                          }
                                            .fontSize(this.fs(14))
                                            .fontColor(TEXT_SECONDARY)
                                            .padding(8)
                                            .border({ width: 0.5, color: STROKE_CARD })
                                            .width(this.getTableColWidths(seg.header, seg.rows)[ci])
                                            .maxLines(1)
                                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                                            .textAlign(TextAlign.Center)
                                            .copyOption(CopyOptions.LocalDevice)
                                            .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, TextResponseType.LONG_PRESS, {
                                              onAppear: () => {
                                                this.selKey = `${msg.messageId}|t${idx}r${ri}c${ci}`;
                                              },
                                              onDisappear: () => {
                                                this.clearSelectionState();
                                              }
                                            })
                                            .onTextSelectionChange((start: number, end: number) => {
                                              this.handleSelectionChange(`${msg.messageId}|t${idx}r${ri}c${ci}`, cell, start, end);
                                            })
                                            .selection(
                                              this.selectAllKey.startsWith(`${msg.messageId}|t${idx}r${ri}c${ci}|`) ? 0 : 1,
                                              this.selectAllKey.startsWith(`${msg.messageId}|t${idx}r${ri}c${ci}|`) ? cell.length : 0
                                            )
                                        // ★ 0.191.0：key 纳入内容（同表头）
                                        }, (cell: string, ci: number) => `r_${ri}_${ci}_${cell.length}_${cell.substring(0, 4)}`)
                                      }
                                      // ★ 0.191.0：行 key 纳入格数+内容总长——流式追加格（| A3 | B3 → | A3 | B3 | C3 |）
                                      //   原 `row_${ri}` 恒定导致末行复用旧 item 冻结在中间态（用户实测 3×3 表末行空格根因）
                                    }, (row: string[], ri: number) => `row_${ri}_${row.length}_${row.join('').length}`)
                                  }
                                }
                                .scrollable(ScrollDirection.Horizontal)
                                .scrollBar(BarState.Auto)
                                .width('100%')
                                .margin({ top: 6, bottom: 6 })
                              }
                              .alignItems(HorizontalAlign.Start)
                            }
                            // ★ 0.132 修复：key 纳入 content/header/rows 尺寸——流式追加时 key 变化触发 item 重建，
                            // 否则 key 恒定导致 ForEach 复用旧 item，MdSegment 非响应式，Text 永不更新（卡占位 bug 根因）
                            // ★ 0.160 bugfix: key 再纳入 content 前 12 字符——0.132 的 length 维度存在等长碰撞边界：
                            // THINKING 占位与正文恰好等长时 key 相同 → item 复用 → 卡占位（用户实测：token 已写入但
                            // 气泡永显「AI 正在深度思考中...」，持久化 content 实为正文）。前缀维度保证占位↔正文切换 key 必变。
                              }, (seg: MdSegment, idx: number) => `${idx}_${seg.type}_${seg.content.length}_${seg.content.substring(0, 12)}_${seg.header.length}_${seg.rows.length}`)
                          // ★ 0.160.2 四次修复：删除原 Markdown 内层 Column 的残留闭合「}」与 .alignItems——
                          // 内层容器开头已在三次修复中随占位行一并移除，闭合括号残留导致括号错配（28 ERROR）。
                          // 现结构：2122 气泡 Column 直接包含 Markdown ForEach + 生词区 + 知识卡片区，
                          // 由 2400 行「}」+ constraintSize/padding 属性链闭合。

                         // ★ 0.145：生词复习区——词库非空时在 AI 气泡底部展示随机 2 词（词条式布局，与下方知识卡片风格统一）
                         // （仅 AI 气泡渲染，本分支天然不含用户消息；缓存按消息 ID，词库长度变化时重抽）
                         // ★ UI 定稿：普通词 2 行（词+音标/释义）、缩略词 3 行（+全称）；行内超宽横向滑动，不换行不省略，行高恒定
                         if (this.wordBank.words.length > 0) {
                           Divider()
                             .strokeWidth(0.5)
                             .color(STROKE_CARD)
                             .margin({ top: 8, bottom: 6 })
                           Column() {
                              ForEach(this.getReviewWords(msg.messageId), (w: WordItem, idx: number) => {
                                Scroll() {
                                  Column() {
                                    Row() {
                                      // ★ 0.169.1：复习区划词——词行/全称/释义均可长按划词（翻译/入知识库/复制）；
                                      // key 段前缀 rw*/rwf*/rwe* 与正文段纯数字 idx 空间隔离；音标行为发音辅助符号不加
                                      // ★ 0.188.0：👆→▼/▲ 紫色三角（UI_GUIDELINES 辅助紫=提示语义；展开态转▲）；点词/点箭头展开 3 档评分
                                      Text(this.reviewExpandKey === `${msg.messageId}|${w.id}` ? '▲' : '▼')
                                        .fontSize(this.fs(10))
                                        .fontColor(BRAND_SECONDARY)
                                        .margin({ right: 4 })
                                        .onClick(() => {
                                          this.onReviewWordTap(`${msg.messageId}|${w.id}`);
                                        })
                                      Text(w.word, { controller: this.getOrCreateTextController(`${msg.messageId}|rw${idx}`) })
                                        .fontSize(this.fs(13))
                                        .fontWeight(600)
                                        .fontColor(TEXT_SECONDARY)
                                        .maxLines(1)
                                        .copyOption(CopyOptions.LocalDevice)
                                        .onClick(() => {
                                          this.onReviewWordTap(`${msg.messageId}|${w.id}`);
                                        })
                                        .bindSelectionMenu(TextSpanType.TEXT, this.ReviewSelectionToolbar, TextResponseType.LONG_PRESS, {
                                          onAppear: () => {
                                            this.selKey = `${msg.messageId}|rw${idx}`;
                                          },
                                          onDisappear: () => {
                                            this.clearSelectionState();
                                          }
                                        })
                                        .onTextSelectionChange((start: number, end: number) => {
                                          this.handleSelectionChange(`${msg.messageId}|rw${idx}`, '📚 ' + w.word, start, end);
                                        })
                                      if (w.usPhonetic.length > 0) {
                                        // Phonetic right beside the word — same line, never ellipsized (user rule)
                                        Text(w.usPhonetic)
                                          .fontSize(this.fs(12))
                                          .fontColor(TEXT_TERTIARY)
                                          .maxLines(1)
                                          .margin({ left: 6 })
                                        // ★ 0.149：音标旁发音按钮——缩略词播全称（字母谁都会读）、普通词播单词本身（美式）；三态 🔈/⏳/🔊；点击先停消息朗读（互斥）
                                        // ★ 0.150：Button→Text——Button 默认高度（≈40vp）会撑高音标行，Text 无默认高度、行距还原
                                        // ★ 0.195.0：喇叭三态 emoji（🔈⏳🔊 彩色）换单色 svg——形状即状态（cone 空闲/dots 合成中/waves 播放中）
                                        Image(wordSpeaker.loadingWord === wordSpeaker.textFor(w.word, w.fullName) ? $r('app.media.speaker_loading') : (wordSpeaker.speakingWord === wordSpeaker.textFor(w.word, w.fullName) ? $r('app.media.speaker_playing') : $r('app.media.speaker')))
                                          .width(12)
                                          .height(12)
                                          .objectFit(ImageFit.Contain)
.onClick(() => {
  this.stopTTS();
  // ★ 0.189.2：口音提示改弹窗（英式无包/美式缺包——showAccentDialogs 共用工厂）
  wordSpeaker.speak(wordSpeaker.textFor(w.word, w.fullName), showAccentDialogs(this.getUIContext()));
})
                                      }
                                   }
                                    if (w.fullName.length > 0) {
                                      // ★ 0.169.1：全称行划词（缩略词全称/中译英答案）
                                      Text(w.fullName, { controller: this.getOrCreateTextController(`${msg.messageId}|rwf${idx}`) })
                                        .fontSize(this.fs(12))
                                        .fontColor(BRAND_SECONDARY)
                                        .maxLines(1)
                                        .margin({ top: 1 })
                                        .copyOption(CopyOptions.LocalDevice)
                                        .bindSelectionMenu(TextSpanType.TEXT, this.ReviewSelectionToolbar, TextResponseType.LONG_PRESS, {
                                          onAppear: () => {
                                            this.selKey = `${msg.messageId}|rwf${idx}`;
                                          },
                                          onDisappear: () => {
                                            this.clearSelectionState();
                                          }
                                        })
                                        .onTextSelectionChange((start: number, end: number) => {
                                          this.handleSelectionChange(`${msg.messageId}|rwf${idx}`, w.fullName, start, end);
                                        })
                                    }
                                    // ★ 0.169.1：释义行划词
                                    Text(w.explain, { controller: this.getOrCreateTextController(`${msg.messageId}|rwe${idx}`) })
                                      .fontSize(this.fs(12))
                                      .fontColor(TEXT_SECONDARY)
                                      .maxLines(1)
                                      .margin({ top: 2 })
                                      .copyOption(CopyOptions.LocalDevice)
                                      .bindSelectionMenu(TextSpanType.TEXT, this.ReviewSelectionToolbar, TextResponseType.LONG_PRESS, {
                                        onAppear: () => {
                                          this.selKey = `${msg.messageId}|rwe${idx}`;
                                        },
                                        onDisappear: () => {
                                          this.clearSelectionState();
                                        }
                                      })
                                       .onTextSelectionChange((start: number, end: number) => {
                                         this.handleSelectionChange(`${msg.messageId}|rwe${idx}`, w.explain, start, end);
                                       })
                                   }
                                   .alignItems(HorizontalAlign.Start)
                                }
                                .scrollable(ScrollDirection.Horizontal)
                                .scrollBar(BarState.Off)
                                .align(Alignment.Start)
                                .width('100%')
                                .margin({ top: idx > 0 ? 6 : 0 })
                                // ★ 0.187.0：评分区——展开 3 档按钮 / 已评分显示下次复习
                                // ★ 0.198.3 溢出根因修复：评分区必须放横向 Scroll 外——横向 Scroll 给子组件的
                                // 宽度约束无上限（内容可超视口滑动），内部 width 百分比/layoutWeight 全部失效
                                // 回退内容自适应（96 钳制恒 300vp），前三轮（0.196.0 固定宽/0.198.1 layoutWeight/
                                // 0.198.2 百分比）在 Scroll 内怎么改都溢出；评分区内容固定无需滚动，移出后恢复
                                // 气泡内容区（90%屏-padding10）约束，'30%' 生效——手机自动缩窄、平板钳 96 窄胶囊
                                this.ratingArea(`${msg.messageId}|${w.id}`, w)
                              }, (w: WordItem) => w.word)
                           }
                           .alignItems(HorizontalAlign.Start)
                         }

                          // ★ 0.146：知识卡片复习区——库非空时在 AI 气泡底部展示随机 N 张
                          // （N=知识卡片数量，知识库 ⚙ 设置，★ 0.161.2 单卡改多卡；与上方单词复习区并列，
                          // 📖 前缀区分知识库卡片/单词卡片；缓存按消息 ID；每卡独立横向滚动行、纵向排列——与生词区同款）
                          // ★ UI 定稿：卡片 2 行（标题+图片icon/定义）；有图才显示 🖼️ 指示（不用小缩略图）；行内超宽横向滑动
                          if (this.knowledgeBank.cards.length > 0) {
                            Divider()
                              .strokeWidth(0.5)
                              .color(STROKE_CARD)
                              .margin({ top: 6, bottom: 6 })
                            Column() {
                              ForEach(this.getKnowledgeCards(msg.messageId), (card: KnowledgeCard, idx: number) => {
                                Scroll() {
                                  Column() {
                                     Row() {
                                       // ★ 0.169.1：复习区划词——标题/定义行均可长按划词（翻译/入知识库/复制）；
                                       // key 段前缀 rk*/rkd* 与生词区 rw* 及正文段纯数字 idx 空间隔离
                                       // ★ 0.188.0：📖→▼/▲ 紫色三角（知识库复刻）；点标题/点箭头展开 3 档评分
                                       Text(this.reviewExpandKey === `${msg.messageId}|${card.id}` ? '▲' : '▼')
                                         .fontSize(this.fs(10))
                                         .fontColor(BRAND_SECONDARY)
                                         .margin({ right: 4 })
                                         .onClick(() => {
                                           this.onReviewWordTap(`${msg.messageId}|${card.id}`);
                                         })
                                       Text(card.title, { controller: this.getOrCreateTextController(`${msg.messageId}|rk${idx}`) })
                                         .fontSize(this.fs(13))
                                         .fontWeight(600)
                                         .fontColor(TEXT_SECONDARY)
                                         .maxLines(1)
                                         .copyOption(CopyOptions.LocalDevice)
                                         .onClick(() => {
                                           this.onReviewWordTap(`${msg.messageId}|${card.id}`);
                                         })
                                         .bindSelectionMenu(TextSpanType.TEXT, this.ReviewSelectionToolbar, TextResponseType.LONG_PRESS, {
                                          onAppear: () => {
                                            this.selKey = `${msg.messageId}|rk${idx}`;
                                          },
                                          onDisappear: () => {
                                            this.clearSelectionState();
                                          }
                                        })
                                         .onTextSelectionChange((start: number, end: number) => {
                                           this.handleSelectionChange(`${msg.messageId}|rk${idx}`, card.title, start, end);
                                         })
                                      if (card.imageUri.length > 0) {
                                        // Image indicator icon — only shown when the card has an image (user rule)
                                        // ★ 0.160 bugfix: icon was display-only with no onClick — tapping did nothing;
                                        // now opens the fullscreen image viewer with this card's image (same viewer as chat images)
                                        // ★ 0.210.1：彩色 emoji → 华为风格单色透明 svg
                                        Image($r('app.media.image'))
                                          .width(14)
                                          .height(14)
                                          .objectFit(ImageFit.Contain)
                                          .margin({ left: 6 })
                                          .onClick(() => {
                                            if (card.imageUri.length > 0) {
                                              this.imageViewerImages = [card.imageUri];
                                              this.imageViewerIndex = 0;
                                              this.imageViewerVisible = true;
                                            }
                                          })
                                      }
                                    }
                                    // ★ 0.169.1：定义行划词
                                    Text(card.definition, { controller: this.getOrCreateTextController(`${msg.messageId}|rkd${idx}`) })
                                      .fontSize(this.fs(12))
                                      .fontColor(TEXT_SECONDARY)
                                      .maxLines(1)
                                      .margin({ top: 2 })
                                      .copyOption(CopyOptions.LocalDevice)
                                      .bindSelectionMenu(TextSpanType.TEXT, this.ReviewSelectionToolbar, TextResponseType.LONG_PRESS, {
                                        onAppear: () => {
                                          this.selKey = `${msg.messageId}|rkd${idx}`;
                                        },
                                        onDisappear: () => {
                                          this.clearSelectionState();
                                        }
                                      })
                                        .onTextSelectionChange((start: number, end: number) => {
                                          this.handleSelectionChange(`${msg.messageId}|rkd${idx}`, card.definition, start, end);
                                        })
                                    }
                                    .alignItems(HorizontalAlign.Start)
                                 }
                                 .scrollable(ScrollDirection.Horizontal)
                                 .scrollBar(BarState.Off)
                                 .align(Alignment.Start)
                                 .width('100%')
                                 .margin({ top: idx > 0 ? 6 : 0 })
                                 // ★ 0.188.0：评分区——展开 3 档按钮 / 已评分显示下次复习
                                 // ★ 0.198.3 评分区移出横向 Scroll（同生词区根因——Scroll 内宽度约束失效）
                                 this.ratingArea(`${msg.messageId}|${card.id}`, card)
                               }, (card: KnowledgeCard, idx: number) => `${idx}_${card.title}`)
                            }
                            .alignItems(HorizontalAlign.Start)
                          }
                          }
                          .constraintSize({ maxWidth: '90%' }) // ★ 0.190.3：气泡最大宽度 85%→90%（用户要求对话列表再加宽一点点）；0.148 原约束——长文本行自动换行，防气泡被撑出屏幕右缘（用户截图实证）
                        .padding(10)
                        .borderRadius(RADIUS_CONTROL)
                        .backgroundColor(SURFACE_NODE)
                        .alignItems(HorizontalAlign.Start) // ★ 0.145：气泡内段落保持左对齐（阅读习惯），气泡整体位置由外层 alignItems 控制

                        // ★ 0.133：AI 消息操作行（token 统计 + 朗读喇叭三态：🔈 空闲 / ⏳ 合成中 / 🔊 播放中）
                        // ★ 0.146：移入包裹容器——行宽自适应，左缘对齐气泡内文字（margin left 10 = 气泡 padding 10）
                        if (msg.role === 'assistant') {
                          Row() {
                            // ★ 0.149：刷新按钮——原位重新生成本条 AI 回复（置于 token 统计左侧）
                            // ★ 0.195.0：🔄 emoji 换 refresh.svg 单色图标（UI 统一）
                            Row() {
                              Image($r('app.media.refresh'))
                                .width(14)
                                .height(14)
                                .objectFit(ImageFit.Contain)
                            }
                            .padding({ left: 0, right: 4, top: 2, bottom: 2 })
                            .onClick(() => {
                              this.regenerateMessage(msg);
                            })
                            if (msg.outputTokens > 0) {
                              Text(`输入 ${msg.inputTokens} · 输出 ${msg.outputTokens}`)
                                .fontSize(11)
                                .fontColor(TEXT_TERTIARY)
                            }
                            Blank()
                              .width(12) // ★ 0.146：固定间距（原 layoutWeight(1) 在自适应行内失效）
                            // ★ 0.195.0：喇叭三态 emoji（🔈⏳🔊 彩色）换单色 svg——形状即状态：
                            //   cone=空闲 / dots=合成中 / waves=播放中（原 BRAND_SECONDARY 激活色随 emoji 退役，形状足够区分）
                            Row() {
                              Image(this.ttsLoadingMessageId === msg.messageId ? $r('app.media.speaker_loading') : (this.playingMessageId === msg.messageId ? $r('app.media.speaker_playing') : $r('app.media.speaker')))
                                .width(14)
                                .height(14)
                                .objectFit(ImageFit.Contain)
                            }
                            .padding({ left: 8, right: 4, top: 2, bottom: 2 })
                            .onClick(() => {
                              this.startTTS(msg);
                            })
                          }
                          .margin({ top: 4, right: 10 }) // ★ 0.148：右对齐后 right 10 = 气泡 padding 10，喇叭与气泡内文字右缘对齐
                        }
                        }
                        .alignItems(HorizontalAlign.End) // ★ 0.148：包裹容器内操作行贴气泡右缘（用户要求统计行+喇叭右对齐）；气泡为最宽子元素不受影响
                      }
                      }
                  }
                  .alignItems(msg.role === 'user' ? HorizontalAlign.Start : HorizontalAlign.End) // ★ 0.145：AI 回复气泡贴右（用户要求右对齐）；用户消息保持靠左

                  // ★ 0.147：用户消息气泡靠左，删除按钮保持气泡右侧
                  if (msg.role === 'user') {
                    Button('×')
                      .fontSize(16)
                      .fontColor(DANGER)
                      .backgroundColor(Color.Transparent)
                      .padding({ left: 2, right: 2 }) // ★ 0.148：与 AI 分支 × 保持一致的紧凑内边距
                      .onClick(() => {
                        this.requestDeleteMessage(msg.messageId); // ★ 0.150：先弹确认防误触
                      })
                  }
                }
                .width('100%')
                .justifyContent(msg.role === 'user' ? FlexAlign.Start : FlexAlign.End)
                // ★ 0.145：移除整行长按手势——划词改为长按气泡文本本身（bindSelectionMenu 自研悬浮栏），
                // 原「选择文本/删除」二级弹窗随之移除（删除仍走 × 按钮）
              }
            }, (msg: ChatMessage) => msg.messageId)
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 16, right: 16, top: 12 })
          .opacity(this.msgAreaOpacity) // ★ 0.162：分支切换过渡动画挂点（消息列表分支）
           // ★ 0.191.0 重做：滚动中实时记录高度——aboutToDisappear 在 pop 转场中可能读不到偏移（实测记录丢失→回来跳底部），
           //   改由滚动事件持续写入模块级 Map，退出钩子仅作兜底
           .onScroll(() => {
              this.recordReadingPosition();
            })
            // ★ 0.215.9 对话页 Ctrl+滚轮缩放（用户核心诉求翻案成功）：
            // BaseEvent.getModifierKeyState(['ctrl'])（API12+，d.ts 实锤支持 Ctrl/Alt/Shift）——
            // 此前"Ctrl 判死"基于 MouseEvent 无按键状态，AxisEvent 继承 BaseEvent 有此方法；
            // Ctrl 按住+滚轮 → 正文/表格/代码块/司忆区字号缩放（fs 体系+持久化全复用）；
            // 未按 Ctrl → 零干预（消息列表正常滚动翻页）；仅宽屏启用（手机端无缩放=既定设计）
            .onAxisEvent((event: AxisEvent) => {
              let ctrl = false;
              try {
                ctrl = event.getModifierKeyState ? event.getModifierKeyState(['ctrl']) : false;
              } catch (e) {
                ctrl = false;
              }
              const v = event.getVerticalAxisValue();
              console.info(`DAGAI-ZOOM chatAxis v=${v} ctrl=${ctrl}`);
              if (ctrl && v !== 0 && this.windowMode.isTablet) {
                this.ctrlAxisAt = Date.now(); // ★ 0.215.10：Ctrl+滚轮时刻窗——窗内 List 滚动被 onScrollFrameBegin 全吞（只缩放不滚动，用户拍板"一边放大一边滚动很傻"）
                const s = this.fontScale * (v < 0 ? 1.04 : 0.96);
                this.fontScale = Math.min(1.6, Math.max(0.75, Math.round(s * 100) / 100));
                this.fontScaleStore.value = this.fontScale;
              }
            })
            // ★ 0.215.10：Ctrl+滚轮期间吞掉消息列表滚动（真拦截=frameBegin 返回 offsetRemain 0，
            //   0.214.0 画布场景实证过的可靠吞法）；松 Ctrl 后轴事件不再刷新窗（300ms 过期）→
            //   普通滚轮照常翻消息；触摸拖拽翻消息无轴事件不受影响
            .onScrollFrameBegin((offset: number, state: ScrollState) => {
              if (Date.now() - this.ctrlAxisAt < 300) {
                return { offsetRemain: 0 }; // Ctrl+滚轮帧：全吞，只缩放
              }
              return { offsetRemain: offset }; // 普通滚动：原样放行
            })
            // ★ 0.214.0：双指捏合缩放正文（Pad 双指 / Matebook 触摸板双指；单指滚动不受影响；边栏/顶栏/输入区不缩）
            // ★ 0.214.1：仅宽屏启用——手机端捏合体验差（误触），手机字号保持系统默认（用户拍板）
            .gesture(
              PinchGesture({ fingers: 2 })
                .onActionStart(() => {
                  this.pinchStartFontScale = this.fontScale;
                })
                .onActionUpdate((event: GestureEvent) => {
                  if (!this.windowMode.isTablet) {
                    return; // ★ 0.214.1：手机端不响应捏合缩放
                  }
                  const s = this.pinchStartFontScale * event.scale;
                  this.fontScale = Math.min(1.6, Math.max(0.75, Math.round(s * 100) / 100));
                  this.fontScaleStore.value = this.fontScale; // ★ 0.214.2：持久化缩放（退出/重启记住）
                })
           )
         }

        // 图片预览区域
        if (this.pendingImages.length > 0) {
          Row() {
            ForEach(this.pendingImages, (img: string, index: number) => {
              // ★ 0.160-fix2: × invisible on device — two suspects fixed at once:
              // ①Button default padding (≈32vp) squeezes the label out of a forced 22x22 box
              //   (content area goes negative) → use Text instead (no default padding);
              // ②position() absolute layout suspect → Stack TopEnd alignment + offset instead
              Stack({ alignContent: Alignment.TopEnd }) {
                Image(img)
                  .width(60)
                  .height(60)
                  .borderRadius(RADIUS_CONTROL)
                  // ★ 0.196.3 bugfix（用户实测「点了不能放大」）：待发图片不在任何消息里——
                  //   openImageViewer 只收集已发送消息的图，待发图走它=静默 return 没反应；
                  //   改为直接以 pendingImages 开查看器（同 openKnowledgeImagePreview 模式）
                  .onClick(() => {
                    this.imageViewerImages = [...this.pendingImages];
                    this.imageViewerIndex = index;
                    this.imageViewerVisible = true;
                  })
                Text('×')
                  .fontSize(15)
                  .fontWeight(600)
                  .fontColor(TEXT_PRIMARY)
                  .backgroundColor(DANGER)
                  .width(22)
                  .height(22)
                  .borderRadius(11)
                  .textAlign(TextAlign.Center)
                  .offset({ x: -2, y: 2 })
                  .onClick(() => {
                    this.removeImage(index);
                  })
              }
              .width(60)
              .height(60)
              .margin({ right: 8 })
            }, (img: string, index: number) => `${img.substring(0, 30)}_${index}`)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8 })
        }

        // 输入区域 — ＋添加子气泡 + 输入框 + ✏️画画Icon + 发送▾（★ 0.152 需求重排：
        // 图片添加/对话模式/回复长度收进发送右侧 ▾ 下拉菜单，底栏只留核心三键）
        Row() {
          // ★ 0.151-D：添加子气泡按钮挪到左下角行首（原顶栏文字按钮改 ＋ icon，样式与 BBTreeCanvas 画布 ＋ 同款；
          // 点击在当前气泡下新建子气泡）
          // ★ 0.162：icon ＋ → 🌿（树杈/新枝）——原 ＋ 易被误解为「添加图片」，
          // 换树杈传达「另起一个树杈（新分支）」语义；尺寸样式不变（32×32 圆角 8）
          // ★ 0.182.1：🌿 emoji 换 gitbranch 分叉符号 svg——用户实测反馈「消息页面的左下角 icon 没有换」
          //   （0.182.0 需求1 本意即此处：与 app logo/画布视觉语言统一）；32×32 容器/圆角/底色/描边样式不变
          Row() {
            Image($r('app.media.gitbranch'))
              .width(18)
              .height(18)
          }
          .width(32)
          .height(32)
          .justifyContent(FlexAlign.Center)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_HOVER)
          .border({ width: 1, color: STROKE_CARD })
          .margin({ right: 2 })
          .onClick(() => {
            this.getUIContext().getFocusController().clearFocus(); // ★ 0.182.0：点击输入框外收键盘（根容器兜底不覆盖有自身 onClick 的按钮，此处显式收）
            this.addBubble();
          })

          TextArea({ text: $$this.inputText, placeholder: '输入问题...' }) // ★ 0.131：去掉 controller 参数（TextAreaController 已移除）
            .key('chatInputField') // ★ 0.216.2：PC 发送后 requestFocus('chatInputField') 重聚焦（连续打字免鼠标回点）
            .onChange((value: string) => {
              this.inputText = value;
              this.saveDraft(); // ★ 0.214.2：输入实时写回本气泡草稿（退出再回来继续编）
            })
            .layoutWeight(1)
            // ★ 0.195.0：高度改自适应（标注页补充要求框同款，用户指认「他的体验就很好」）——
            //   TextArea 随内容自撑、一行一行长高，136vp（5 行）封顶后内部滚动；
            //   原 0.118 手动行数计算 + 0.195.0 measureTextSize 软换行版在真机密度单位翻车
            //   （1 字跳 3 行，用户实测截图实锤）——整条手动计算链废弃（getter/字段/onAreaChange/measure 全删）
            .constraintSize({ minHeight: 40, maxHeight: 136 })
            // ★ 0.215.11 回车=发送（用户要求标准 IM 交互；NEW_LINE 时代回车纯换行已废弃）；
            //   Shift+回车=换行：物理键盘经 onKeyEvent 判 Shift（组件层 KeyEvent.getModifierKeyState，
            //   滚轮翻案同源 API）插 \n 并标记时间窗，onSubmit 窗内跳过发送；软键盘无物理键直发。
            // ★ 0.215.13：软键盘行为按屏宽分治（用户拍板）——宽屏（PC 物理键盘）回车=发送；
            //   窄屏（手机）右下角=换行（用户要求恢复——手机发送走按钮，回车键留给换行更顺手）。
            //   PC Shift+回车换行受平台限制（TextArea 吞物理回车、onKeyEvent 零触发已实锤三面碰壁），
            //   PC 端换行过渡方案=输入框内手动换行；待华为新 API 或 DevEco 本地深挖。
            .enterKeyType(this.isPcDevice() ? EnterKeyType.Send : EnterKeyType.NEW_LINE) // ★ 0.215.14 三档定型：PC=Send（回车发送）、手机+Pad=NEW_LINE（右下角换行，发送走按钮——Pad 横屏不再被宽度断点误判成 PC）
            .onSubmit(() => {
              if (Date.now() - this.shiftEnterAt < 300) {
                return; // Shift+回车帧：已插换行，跳过发送
              }
              this.sendMessage();
            })
            // ★ 0.215.15 Shift+回车真解（DeepSeek 思路·本地 d.ts 实锤）：onKeyPreIme——按键链最早回调
            //   （输入法之前，common.d.ts 18687 行 Callback<KeyEvent, boolean>），return true 拦截输入法+onSubmit；
            //   此前 onKeyEvent 零触发=链路最末端被 TextArea 吞，onKeyPreIme 在输入法之前不受吞。
            //   键码实锤（keyCode.d.ts）：KEY_ENTER=2054（2040 是错值）、SHIFT_LEFT/RIGHT=2047/2048；
            //   Shift 判定双保险=即时查 getModifierKeyState + Shift 键 Down/Up 状态追踪兜底。
            .onKeyPreIme((event: KeyEvent): boolean => {
              console.info(`DAGAI-KEY preIme code=${event.keyCode} type=${event.type}`);
              if (event.keyCode === 2047 || event.keyCode === 2048) { // Shift 键本身：维护状态不消费
                this.shiftHeld = event.type === KeyType.Down;
                return false;
              }
              if (event.keyCode === 2054 && event.type === KeyType.Down) { // KEY_ENTER=2054 实锤
                let shift = false;
                try {
                  shift = event.getModifierKeyState ? event.getModifierKeyState(['shift']) : false;
                } catch (err) {
                  shift = false;
                }
                if (shift || this.shiftHeld) {
                  this.shiftEnterAt = Date.now(); // onSubmit 时间窗双保险（防个别场景漏拦）
                  this.inputText += '\n'; // 末尾插入换行（$$ 双向绑定刷新显示）
                  this.saveDraft(); // 草稿同步
                  return true; // 消费——输入法与 onSubmit 全拦截，只换行不发送
                }
              }
              return false; // 普通回车放行 → onSubmit 发送
            })
            .onKeyEvent((e: KeyEvent) => {
              console.info(`DAGAI-KEY legacy code=${e.keyCode} type=${e.type}`);
            })
            .margin({ left: 6, right: 6 }) // ★ 0.144：输入框与两侧图标按钮留出呼吸间距

          // ★ 0.152：画画Icon（屏幕圈选标注，核心新增亮点）——点击截取当前屏幕画面进入涂鸦标注页；
          // 原底栏 🖼️ 图片按钮与 💬 模式按钮移入发送右侧 ▾ 下拉菜单
          // ★ 0.195.0：✏️ emoji 换 edit.svg 单色图标（UI 统一——屏幕圈选标注入口）
          Row() {
            Image($r('app.media.edit'))
              .width(16)
              .height(16)
              .objectFit(ImageFit.Contain)
          }
          .padding({ left: 2, right: 2 })
          .margin({ left: 0, right: 2 })
          .onClick(() => {
            this.getUIContext().getFocusController().clearFocus(); // ★ 0.182.0：点击输入框外收键盘（根容器兜底不覆盖有自身 onClick 的按钮，此处显式收）
            this.startAnnotation();
          })

          // ★ 0.182.0：发送按钮与 ▾ 合体——▾ 内嵌进发送按钮右侧（原独立 18×32 小三角，用户要求稍大+内置，
          //   常见「发送 ▾」合体样式）；左区点击=发送、右区点击=模式下拉菜单，整按钮统一主紫背景；
          //   发送区保留 isLoading 禁用（置灰半透明白），▾ 区保持可用（原行为：发送中仍可切模式）
          Row() {
            Text('发送')
              .fontSize(16)
              .fontColor(this.isLoading ? 'rgba(255,255,255,0.50)' : Color.White)
              .padding({ left: 12, right: 2 })
              .onClick(() => {
                if (!this.isLoading) {
                  this.sendMessage();
                }
              })
            Text('▾')
              .fontSize(14) // ★ 0.182.0：原独立三角 12 → 14（用户要求稍大）
              .fontColor(Color.White)
              .padding({ left: 2, right: 10 })
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.modeMenuOpen = !this.modeMenuOpen;
              })
          }
          .height(40)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(BRAND_PRIMARY) // ★ 0.181.0：主操作按钮收敛主紫——原未设背景走系统默认蓝（Material 蓝残留），与暗紫主题冲突
          .margin({ left: 4 }) // ★ 0.144：收紧与模式按钮的间距，把宽度让给输入框
        }
        .width('100%')
        .padding({ left: 6, right: 6, top: 8, bottom: 8 }) // ★ 0.143：输入区顶部留白——消息列表/图片预览与输入框原本贴边，加 top 12 与列表顶部 padding 呼应
        .opacity(this.importArrived) // ★ 0.200.0：导入落地渐显（L3 末拍 0→1 300ms；常态恒 1 不影响日常输入/截图）
        }
        .width('100%')
        .height('100%')
        .id('chatSnapshotRoot') // ★ 0.152：屏幕圈选截图锚点（componentSnapshot.get 截取顶栏+消息列表+输入区当前画面）
        // ★ 0.182.0：点击输入框外任意处收起软键盘——根容器兜底 onClick（ArkUI 点击不冒泡：
        // 有自身 onClick 的按钮/菜单项各自消费不触发此处；TextArea 点击获焦点自消费；
        // 其余空白/消息区点击落到此处 → clearFocus 收键盘，与发送后收键盘同一先例）
        .onClick(() => {
          this.getUIContext().getFocusController().clearFocus();
          // ★ 0.195.0：点空白处同时收起划词悬浮栏——原仅点其他文本触发 onDisappear 取消，
          //   点空白自研菜单滞留不关（用户实测）；closeSelectionMenu 主动关闭 + 状态清理
          this.closeActiveSelectionMenu();
          this.clearSelectionState();
        })

        // ★ 0.146：知识库卡片编辑弹窗（AI 生成草稿 → 用户二次编辑 → 保存入库）
        // 遮罩不关闭弹窗——防误触丢草稿；关闭只走【取消】按钮 / 系统返回。
        // 声明在图片浏览器之前：预览配图时 imageViewer 渲染在上层，关闭预览后编辑弹窗仍在。
        if (this.knowledgeEditVisible) {
          Stack() {
            // 遮罩：仅挡底层交互
            Column() {
              Blank()
            }
            .width('100%')
            .height('100%')
            .backgroundColor(OVERLAY)

            // 弹窗主体：标题输入框 → 定义输入框 → 图片区 → 保存/取消
            Column() {
              // ★ 0.153：提炼中标题展示秒表计时（每秒 +1），空闲恢复静态标题
              // ★ 0.191.0：文案改「等待服务器返回」（与对话等待态统一，用户指示；秒表计时逻辑保留供超时判断，仅不展示）
              Text(this.knowledgeEditLoading ? '等待服务器返回' : '知识库卡片')
                .fontSize(16)
                .fontWeight(600)
                .fontColor(this.knowledgeEditLoading ? BRAND_SECONDARY : (TEXT_PRIMARY))
                .margin({ bottom: 12 })

              // AI 提炼失败提示（输入框仍可手动填写）
              if (!this.knowledgeEditLoading && this.knowledgeEditError.length > 0) {
                Text(this.knowledgeEditError)
                  .fontSize(13)
                  .fontColor(DANGER)
                  .margin({ bottom: 8 })
              }

              // 标题输入框（AI 草稿自动填充，可自由编辑增删）
              TextInput({ text: this.knowledgeCardTitle, placeholder: '标题（概念名称）' })
                .fontSize(14)
                .onChange((value: string) => {
                  this.knowledgeCardTitle = value;
                })
                .width('100%')
                .margin({ bottom: 8 })

              // 定义输入框（多行；AI 草稿自动填充，可自由编辑增删）
              TextArea({ text: this.knowledgeCardDefinition, placeholder: '定义（精简核心描述）' })
                .fontSize(14)
                .onChange((value: string) => {
                  this.knowledgeCardDefinition = value;
                })
                .width('100%')
                .height(100)
                .margin({ bottom: 8 })

              // ── ★ 0.202.2：AI 建议标签区（点击勾选；长按修改文字；「+ 自定义」添加自己的）──
              if (this.knowledgeSuggestedTags.length > 0 || true) {
                Column() {
                  Text('标签（点击勾选 · 长按修改）')
                    .fontSize(11)
                    .fontColor(TEXT_TERTIARY)
                    .alignSelf(ItemAlign.Start)
                    .margin({ bottom: 6 })
                  Flex({ wrap: FlexWrap.Wrap }) {
                    ForEach(this.knowledgeSuggestedTags, (t: string) => {
                      Text(t)
                        .fontSize(11)
                        .height(24)
                        .padding({ left: 10, right: 10 })
                        .borderRadius(6)
                        .fontColor(this.isTagPicked(t) ? Color.White : BRAND_SECONDARY)
                        .backgroundColor(this.isTagPicked(t) ? BRAND_PRIMARY : Color.Transparent)
                        .border({ width: 1, color: BRAND_SECONDARY })
                        .margin({ right: 6, bottom: 6 })
                        .onClick(() => {
                          this.toggleSuggestedTag(t);
                        })
                        .gesture(
                          LongPressGesture({ duration: 500 })
                            .onAction(() => {
                              this.openTagEdit(t);
                            })
                        )
                    }, (t: string) => t)
                    // ★ 0.202.2：「+ 自定义」chip——弹 mini 输入框添加自己的标签（自动勾选）
                    Text('+ 自定义')
                      .fontSize(11)
                      .height(24)
                      .padding({ left: 10, right: 10 })
                      .borderRadius(6)
                      .fontColor(TEXT_SECONDARY)
                      .border({ width: 1, color: STROKE_CARD, style: BorderStyle.Dashed })
                      .margin({ right: 6, bottom: 6 })
                      .onClick(() => {
                        this.openTagEdit('');
                      })
                  }
                  .width('100%')
                }
                .width('100%')
                .margin({ bottom: 10 })
              }

              // 图片区：无图片只显示【添加图片】按钮（占位框不渲染）；有图片显示缩略图（点击全屏预览，× 移除）
              if (this.knowledgeImageUri.length === 0) {
                Button('添加图片')
                  .fontSize(13)
                  .backgroundColor(SURFACE_NODE)
                  .fontColor(TEXT_SECONDARY)
                  .width('100%')
                  .margin({ bottom: 12 })
                  .onClick(() => {
                    this.selectKnowledgeImage();
                  })
              } else {
                // ★ 0.160-fix2: same double fix as pendingImages × — Text (Button default
                // padding ≈32vp squeezes label out of 22x22) + TopEnd align instead of position()
                Stack({ alignContent: Alignment.TopEnd }) {
                  Image(this.knowledgeImageUri)
                    .width(80)
                    .height(80)
                    .borderRadius(RADIUS_CONTROL)
                    .onClick(() => {
                      this.openKnowledgeImagePreview();
                    })
                  Text('×')
                    .fontSize(15)
                    .fontWeight(600)
                    .fontColor(TEXT_PRIMARY)
                    .backgroundColor(DANGER)
                    .width(22)
                    .height(22)
                    .borderRadius(11)
                    .textAlign(TextAlign.Center)
                    .offset({ x: -2, y: 2 })
                    .onClick(() => {
                      this.knowledgeImageUri = '';
                    })
                }
                .width(80)
                .height(80)
                .margin({ bottom: 12 })
              }

              // ★ 0.160：弹窗内复习区——AI 提炼等待期顺便学习（词库 2 词 + 知识库 1 卡），
              // 与气泡底部复习区同款样式；打开弹窗时抽一次固定，词库/知识库为空时对应块不渲染
              if (this.editReviewWords.length > 0) {
                Divider()
                  .strokeWidth(0.5)
                  .color(STROKE_CARD)
                  .margin({ bottom: 6 })
                ForEach(this.editReviewWords, (w: WordItem, idx: number) => {
                  // ★ 0.160 bugfix: wrap each entry in horizontal Scroll (same as bubble review area) —
                  // long word/phonetic text overflowed the dialog boundary without it (user report)
                  Scroll() {
                  Column() {
                     Row() {
                       // ★ 0.188.0：👆→▼/▲ 紫色三角（展开态转▲）；点词/点箭头展开 3 档评分
                       Text(this.reviewExpandKey === `edit|${w.id}` ? '▲' : '▼')
                         .fontSize(10)
                         .fontColor(BRAND_SECONDARY)
                         .margin({ right: 4 })
                         .onClick(() => {
                           this.onReviewWordTap(`edit|${w.id}`);
                         })
                       Text(w.word)
                         .fontSize(13)
                         .fontWeight(600)
                         .fontColor(TEXT_SECONDARY)
                         .maxLines(1)
                         .onClick(() => {
                           this.onReviewWordTap(`edit|${w.id}`);
                         })
                      if (w.usPhonetic.length > 0) {
                        Text(w.usPhonetic)
                          .fontSize(12)
                          .fontColor(TEXT_TERTIARY)
                          .maxLines(1)
                          .margin({ left: 6 })
                        // 发音按钮（与气泡复习区同款三态；缩略词播全称）
                        // ★ 0.195.0：喇叭三态 emoji（🔈⏳🔊 彩色）换单色 svg——形状即状态（cone 空闲/dots 合成中/waves 播放中）
                        Image(wordSpeaker.loadingWord === wordSpeaker.textFor(w.word, w.fullName) ? $r('app.media.speaker_loading') : (wordSpeaker.speakingWord === wordSpeaker.textFor(w.word, w.fullName) ? $r('app.media.speaker_playing') : $r('app.media.speaker')))
                          .width(12)
                          .height(12)
                          .objectFit(ImageFit.Contain)
                          .margin({ left: 4 })
.onClick(() => {
  this.stopTTS();
  // ★ 0.189.2：口音提示改弹窗（英式无包/美式缺包——showAccentDialogs 共用工厂）
  wordSpeaker.speak(wordSpeaker.textFor(w.word, w.fullName), showAccentDialogs(this.getUIContext()));
})
                      }
                    }
                    if (w.fullName.length > 0) {
                      Text(w.fullName)
                        .fontSize(12)
                        .fontColor(BRAND_SECONDARY)
                        .maxLines(1)
                        .margin({ top: 1 })
                    }
                    Text(w.explain)
                      .fontSize(12)
                      .fontColor(TEXT_SECONDARY)
                      .maxLines(1)
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  }
                  .scrollable(ScrollDirection.Horizontal)
                  .scrollBar(BarState.Off)
                  .align(Alignment.Start)
                  .width('100%')
                  .margin({ bottom: idx === this.editReviewWords.length - 1 ? 0 : 6 })
                  // ★ 0.187.0：评分区 / ★ 0.198.3 移出横向 Scroll（同气泡复习区根因——Scroll 内宽度约束失效）
                  this.ratingArea(`edit|${w.id}`, w)
                }, (w: WordItem) => w.word)
              }
              if (this.editReviewCards.length > 0) {
                Divider()
                  .strokeWidth(0.5)
                  .color(STROKE_CARD)
                  .margin({ top: 6, bottom: 6 })
                // ★ 0.160 bugfix: wrap each card in horizontal Scroll (same as bubble review area) —
                // long title/definition could not be swiped and overflowed the dialog (user report)
                // ★ 0.161.2: single card → ForEach over N cards (knowledge-count setting drives N)
                ForEach(this.editReviewCards, (card: KnowledgeCard, idx: number) => {
                Scroll() {
                Column() {
                   Row() {
                     // ★ 0.188.0：📖→▼/▲ 紫色三角（知识库复刻）；点标题/点箭头展开 3 档评分
                     Text(this.reviewExpandKey === `editcard|${card.id}` ? '▲' : '▼')
                       .fontSize(10)
                       .fontColor(BRAND_SECONDARY)
                       .margin({ right: 4 })
                       .onClick(() => {
                         this.onReviewWordTap(`editcard|${card.id}`);
                       })
                     Text(card.title)
                       .fontSize(13)
                       .fontWeight(600)
                       .fontColor(TEXT_SECONDARY)
                       .maxLines(1)
                       .onClick(() => {
                         this.onReviewWordTap(`editcard|${card.id}`);
                       })
                     if (card.imageUri.length > 0) {
                       // ★ 0.210.1：彩色 emoji → 华为风格单色透明 svg
                       Image($r('app.media.image'))
                         .width(14)
                         .height(14)
                         .objectFit(ImageFit.Contain)
                         .margin({ left: 6 })
                         .onClick(() => {
                           this.imageViewerImages = [card.imageUri];
                           this.imageViewerIndex = 0;
                           this.imageViewerVisible = true;
                         })
                     }
                  }
                    Text(card.definition)
                      .fontSize(12)
                      .fontColor(TEXT_SECONDARY)
                      .maxLines(1)
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  }
                 .scrollable(ScrollDirection.Horizontal)
                 .scrollBar(BarState.Off)
                 .align(Alignment.Start)
                 .width('100%')
                 .margin({ top: idx > 0 ? 6 : 0, bottom: idx === this.editReviewCards.length - 1 ? 12 : 0 })
                 // ★ 0.188.0：评分区 / ★ 0.198.3 移出横向 Scroll（同气泡复习区根因——Scroll 内宽度约束失效）
                 this.ratingArea(`editcard|${card.id}`, card)
                 }, (card: KnowledgeCard, idx: number) => `${idx}_${card.title}`)
              }

              // 保存 / 取消
              Row() {
                Button('取消')
                  .layoutWeight(1)
                  .margin({ right: 8 })
                  .onClick(() => {
                    this.closeKnowledgeEdit();
                  })
                Button('保存入库')
                  .layoutWeight(1)
                  .backgroundColor(BRAND_PRIMARY)
                  .fontColor(TEXT_PRIMARY)
                  // ★ 0.153：提炼中/报错/业务超时均置灰不可点击（修复报错态仍可点击的 BUG）；
                  // 仅请求成功结束（loading=false 且无错误）才启用
                  .enabled(!this.knowledgeEditLoading && this.knowledgeEditError.length === 0)
                  .onClick(() => {
                    this.saveKnowledgeCard();
                  })
              }
              .width('100%')

              // ★ 0.153：底部小字提示——取消仅停止后续内容生成（已发送部分不撤回）
              Text('提示：请求提交后，输入内容已发送AI服务，取消仅停止后续内容生成。')
                .fontSize(11)
                .fontColor(TEXT_TERTIARY)
                .margin({ top: 8 })
                .width('100%')
            }
            .width('85%')
            .padding(20)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(SURFACE_NODE)

            // ── ★ 0.202.2：标签 mini 编辑弹窗（长按改/自定义加）——挂编辑弹窗 Stack 顶层 ──
            if (this.tagEditVisible) {
              Stack() {
                Column() {
                  Blank()
                }
                .width('100%')
                .height('100%')
                .backgroundColor('rgba(0,0,0,0.45)')
                .onClick(() => {
                  this.tagEditVisible = false;
                })
                Column() {
                  Text(this.tagEditOld.length === 0 ? '添加自定义标签' : '修改标签')
                    .fontSize(14)
                    .fontWeight(600)
                    .fontColor(TEXT_PRIMARY)
                    .margin({ bottom: 10 })
                  TextInput({ text: this.tagEditNew, placeholder: '标签名（2~6 字最佳）' })
                    .fontSize(14)
                    .width('100%')
                    .height(40)
                    .padding({ left: 12, right: 12 })
                    .borderRadius(RADIUS_CONTROL)
                    .backgroundColor(SURFACE_SOFT)
                    .onChange((v: string) => {
                      this.tagEditNew = v;
                    })
                  Row({ space: 12 }) {
                    Button('取消')
                      .layoutWeight(1)
                      .fontColor(TEXT_SECONDARY)
                      .backgroundColor(Color.Transparent)
                      .onClick(() => {
                        this.tagEditVisible = false;
                      })
                    Button('确定')
                      .layoutWeight(1)
                      .backgroundColor(BRAND_PRIMARY)
                      .fontColor(TEXT_PRIMARY)
                      .onClick(() => {
                        this.commitTagEdit();
                      })
                  }
                  .width('100%')
                  .margin({ top: 14 })
                }
                .width('72%')
                .padding(18)
                .borderRadius(RADIUS_NAV)
                .backgroundColor(SURFACE_NODE)
                .border({ width: 1, color: STROKE_CARD })
              }
              .width('100%')
              .height('100%')
              .alignContent(Alignment.Center)
            }
          }
          .width('100%')
          .height('100%')
          .alignContent(Alignment.Center)
        }

        // 全屏图片浏览器
        if (this.imageViewerVisible) {
          Stack() {
            Swiper() {
              ForEach(this.imageViewerImages, (url: string) => {
                Image(url)
                  .objectFit(ImageFit.Contain)
                  .width('100%')
                  .height('100%')
              }, (url: string) => url)
            }
            .index(this.imageViewerIndex)
            .indicator(true)
            .backgroundColor(Color.Black)

            Button('×')
              .fontSize(24)
              .fontColor(TEXT_PRIMARY)
              .backgroundColor(Color.Transparent)
              .position({ x: 20, y: 20 })
              .onClick(() => {
                this.imageViewerVisible = false;
              })
          }
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Black)
          .onClick(() => {
            this.imageViewerVisible = false;
          })
          // ★ 新增：右滑手势关闭图片预览（0.120）
          .gesture(
            PanGesture({ direction: PanDirection.Horizontal })
              .onActionEnd((event: PanGestureEvent) => {
                if (event.offsetX > 30) { // 右滑超过30vp关闭预览
                  this.imageViewerVisible = false;
                }
              })
          )
        }

        // ★ 0.145：翻译浮窗（替代原长按菜单/删除确认/文本预览三个二级弹窗）
        // 点悬浮操作栏「翻译」弹出：小型浮窗展示 AI 查词结果，不新建气泡、不进 DAG；点遮罩关闭
        if (this.wordPopupVisible) {
          Stack() {
            // 遮罩：点击关闭浮窗（同时取消进行中的查词请求）
            Column() {
              Blank()
            }
            .width('100%')
            .height('100%')
            .backgroundColor(OVERLAY_LIGHT)
            .onClick(() => {
              this.closeWordPopup();
            })

            // 浮窗主体：标题(查询原文) → 查询中/错误/结果 → 加入单词库
            Column() {
              // 查询原文（即渲染顺序首项「单词」）
              Text(this.wordPopupQuery)
                .fontSize(20)
                .fontWeight(600)
                .fontColor(TEXT_PRIMARY)
                .maxLines(1)
                .margin({ bottom: 12 })

              // 查询中态
              if (this.wordPopupLoading) {
                Text('查询中...')
                  .fontSize(14)
                  .fontColor(TEXT_TERTIARY)
                  .margin({ bottom: 12 })
              }

              // 错误态
              if (!this.wordPopupLoading && this.wordPopupError.length > 0) {
                Text(this.wordPopupError)
                  .fontSize(14)
                  .fontColor(DANGER)
                  .margin({ bottom: 12 })
              }

              // 结果态：渲染顺序固定 单词(标题)→全称→音标→释义；fullName 为空时全称行不渲染（禁止空白占位）
              if (!this.wordPopupLoading && this.wordPopupResult !== null) {
                if (this.wordPopupResult.fullName.length > 0) {
                  Text(this.wordPopupResult.fullName)
                    .fontSize(14)
                    .fontColor(TEXT_SECONDARY)
                    .margin({ bottom: 4 })
                }
                if (this.wordPopupResult.usPhonetic.length > 0) {
                  Row() {
                    Text(this.wordPopupResult.usPhonetic)
                      .fontSize(14)
                      .fontColor(TEXT_SECONDARY)
                    // ★ 0.149：音标旁发音按钮——缩略词播全称（字母谁都会读）、普通词播单词本身（美式）；三态 🔈/⏳/🔊；点击先停消息朗读（互斥）
                    // ★ 0.150：Button→Text——Button 默认高度（≈40vp）会撑高音标行，Text 无默认高度、行距还原
                    // ★ 0.155：发音文本统一走 wordPopupSpeakText()——中译英播英文译文、原路径播全称/原文
                    // ★ 0.195.0：喇叭三态 emoji 换单色 svg（cone 空闲/dots 合成中/waves 播放中）
                    Image(wordSpeaker.loadingWord === this.wordPopupSpeakText() ? $r('app.media.speaker_loading') : (wordSpeaker.speakingWord === this.wordPopupSpeakText() ? $r('app.media.speaker_playing') : $r('app.media.speaker')))
                      .width(14)
                      .height(14)
                      .objectFit(ImageFit.Contain)
                      .margin({ left: 6 })
                       .onClick(() => {
                         this.stopTTS();
                         // ★ 0.189.2：口音提示改弹窗（showAccentDialogs 共用工厂）
                         wordSpeaker.speak(this.wordPopupSpeakText(), showAccentDialogs(this.getUIContext()));
                       })
                  }
                  .margin({ bottom: 4 })
                }
                // ★ 0.155：explain 空时不渲染（防 AI 返回空释义留空白行；与 fullName 条件渲染同模式）
                if (this.wordPopupResult.explain.length > 0) {
                  Text(this.wordPopupResult.explain)
                    .fontSize(14)
                    .fontColor(TEXT_SECONDARY)
                    .margin({ bottom: 12 })
                }
              }

              // 「单词已存在」提示（重复添加时显示）
              if (this.wordExistsTip) {
                Text('单词已存在')
                  .fontSize(12)
                  .fontColor(DANGER)
                  .margin({ bottom: 4 })
              }

              // 加入单词库按钮（已加入后转灰禁用防重复）
              Button(this.wordPopupAdded ? '已加入' : '加入单词库')
                .width('100%')
                .backgroundColor(this.wordPopupAdded ? (SURFACE_HOVER) : BRAND_PRIMARY)
                .fontColor(this.wordPopupAdded ? (TEXT_TERTIARY) : TEXT_PRIMARY)
                .enabled(!this.wordPopupAdded && this.wordPopupResult !== null)
                .onClick(() => {
                  this.addCurrentWordToBank();
                })
            }
            .width('70%')
            .padding(20)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(SURFACE_NODE)
          }
          .width('100%')
          .height('100%')
          .alignContent(Alignment.Center)
        }

        // ★ 0.150：删除确认弹窗（防误触）——首次点 × 弹出；勾选「此次对话不再提示」后本次会话内直接删；
        // 退回画布重进对话页后提醒重置（aboutToAppear 重置 deleteSkipConfirm）
        if (this.deleteConfirmVisible) {
          Stack() {
            // 遮罩：点击关闭弹窗（不删除）
            Column() {
              Blank()
            }
            .width('100%')
            .height('100%')
            .backgroundColor(OVERLAY_LIGHT)
            .onClick(() => {
              this.deleteConfirmVisible = false;
            })

            // 弹窗主体：提示文案 → 勾选行 → 取消/删除按钮
            Column() {
              Text('删除这条消息？')
                .fontSize(18)
                .fontWeight(600)
                .fontColor(TEXT_PRIMARY)
                .margin({ bottom: 8 })

              Text('删除后不可恢复')
                .fontSize(13)
                .fontColor(TEXT_TERTIARY)
                .margin({ bottom: 16 })

              // 勾选行：整行可点（Checkbox 只读展示，避免 Row/Checkbox 双触发）
              Row() {
                Checkbox()
                  .select(this.deleteConfirmNoAsk)
                  .selectedColor(BRAND_PRIMARY)
                  .width(18)
                  .height(18)
                  .hitTestBehavior(HitTestMode.None)
                Text('此次对话不再提示')
                  .fontSize(13)
                  .fontColor(TEXT_SECONDARY)
                  .margin({ left: 6 })
              }
              .margin({ bottom: 16 })
              .onClick(() => {
                this.deleteConfirmNoAsk = !this.deleteConfirmNoAsk;
              })

              // 按钮行：取消（左）/ 删除（右，红色）
              Row() {
                Button('取消')
                  .layoutWeight(1)
                  .backgroundColor(SURFACE_HOVER)
                  .fontColor(TEXT_SECONDARY)
                  .margin({ right: 8 })
                  .onClick(() => {
                    this.deleteConfirmVisible = false;
                  })
                Button('删除')
                  .layoutWeight(1)
                  .backgroundColor(DANGER)
                  .fontColor(TEXT_PRIMARY)
                  .onClick(() => {
                    this.confirmDeleteMessage();
                  })
              }
            }
            .width('70%')
            .padding(20)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(SURFACE_NODE)
          }
          .width('100%')
          .height('100%')
          .alignContent(Alignment.Center)
        }

        // ★ 0.153：代码块放大弹窗（左上角「放大」按钮打开，全屏查看 + 换行/横向滚动切换）
        if (this.codeZoomVisible) {
          Stack() {
            // 遮罩：点击关闭
            Column() {
              Blank()
            }
            .width('100%')
            .height('100%')
            .backgroundColor(OVERLAY)
            .onClick(() => {
              this.codeZoomVisible = false;
            })

            // 面板
            Column() {
              // 标题行：标题 + 换行切换 + 关闭
              Row() {
                Text('代码块')
                  .fontSize(16)
                  .fontWeight(600)
                  .fontColor(TEXT_PRIMARY)

                // ★ 0.149：语言标签（与气泡内代码块一致；无语言标识显示 plaintext）
                Text(this.codeZoomLang.length > 0 ? this.codeZoomLang : 'plaintext')
                  .fontSize(12)
                  .fontColor(TEXT_TERTIARY)
                  .margin({ left: 8 })

                Blank()

                // 换行切换按钮（样式与气泡内代码块按钮统一）
                // ★ 0.191.0：字符→wrap/nowrap.svg 矢量图标（↩ emoji 化根治），框样式保留；★ 缩小 20×18/图标14
                Row() {
                  Image(this.codeZoomWrap ? $r('app.media.wrap') : $r('app.media.nowrap'))
                    .width(14)
                    .height(14)
                }
                .width(20)
                .height(18)
                .justifyContent(FlexAlign.Center)
                .alignItems(VerticalAlign.Center)
                .borderRadius(4)
                .backgroundColor(SURFACE_HOVER)
                .border({ width: 0.5, color: STROKE_BRAND })
                .onClick(() => {
                  this.codeZoomWrap = !this.codeZoomWrap;
                })

                // 关闭按钮
                Text('✕')
                  .fontSize(16)
                  .fontColor(TEXT_TERTIARY)
                  .margin({ left: 12 })
                  .onClick(() => {
                    this.codeZoomVisible = false;
                  })
              }
              .width('100%')
              .margin({ bottom: 10 })

              // 代码内容：纵向滚动；换行模式 Text 自然换行，滚动模式内层横向滚动
              Scroll() {
                if (this.codeZoomWrap) {
                  // ★ 0.156：划词五件套——放大弹窗内代码同样可划词（key cz|w 与气泡内代码块空间隔离；
                  // 弹窗面板为固定宽度容器，width('100%') 无 0.154 的气泡链解析问题，保留）
                  // ★ 0.149：语法高亮——ForEach Span 着色（与气泡内同逻辑，token 拼接与 content 一致）
                    Text('', { controller: this.getOrCreateTextController('cz|w') }) {
                    ForEach(this.zoomTokens(), (t: CodeToken, i: number) => {
                      Span(t.text)
                        .fontColor(this.codeTokenColor(t.kind))
                    }, (t: CodeToken, i: number) => `${i}|${t.kind}|${t.text.length}`)
                  }
                    .fontSize(14)
                    .fontFamily('monospace')
                    .fontColor(CODE_TEXT)
                    .padding(10)
                    .backgroundColor(BG_CANVAS)
                    .borderRadius(RADIUS_CONTROL)
                    .width('100%')
                    .copyOption(CopyOptions.LocalDevice)
                    .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, TextResponseType.LONG_PRESS, {
                      onAppear: () => {
                        this.selKey = 'cz|w';
                      },
                      onDisappear: () => {
                        this.clearSelectionState();
                      }
                    })
                    .onTextSelectionChange((start: number, end: number) => {
                      this.handleSelectionChange('cz|w', this.codeZoomContent, start, end);
                    })
                    .selection(
                      this.selectAllKey.startsWith('cz|w|') ? 0 : 1,
                      this.selectAllKey.startsWith('cz|w|') ? this.codeZoomContent.length : 0
                    )
                } else {
                  Scroll() {
                    // ★ 0.156：划词五件套——滚动模式同 wrap（key cz|s 独立 controller）
                    // ★ 0.149：语法高亮——同 wrap 模式 ForEach Span 着色渲染
                      Text('', { controller: this.getOrCreateTextController('cz|s') }) {
                      ForEach(this.zoomTokens(), (t: CodeToken, i: number) => {
                        Span(t.text)
                          .fontColor(this.codeTokenColor(t.kind))
                      }, (t: CodeToken, i: number) => `${i}|${t.kind}|${t.text.length}`)
                    }
                      .fontSize(14)
                      .fontFamily('monospace')
                      .fontColor(CODE_TEXT)
                      .padding(10)
                      .backgroundColor(BG_CANVAS)
                      .borderRadius(RADIUS_CONTROL)
                      .copyOption(CopyOptions.LocalDevice)
                      .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, TextResponseType.LONG_PRESS, {
                        onAppear: () => {
                          this.selKey = 'cz|s';
                        },
                        onDisappear: () => {
                          this.clearSelectionState();
                        }
                      })
                      .onTextSelectionChange((start: number, end: number) => {
                        this.handleSelectionChange('cz|s', this.codeZoomContent, start, end);
                      })
                      .selection(
                        this.selectAllKey.startsWith('cz|s|') ? 0 : 1,
                        this.selectAllKey.startsWith('cz|s|') ? this.codeZoomContent.length : 0
                      )
                  }
                  .scrollable(ScrollDirection.Horizontal)
                  .scrollBar(BarState.Auto)
                  .width('100%')
                }
              }
              .scrollable(ScrollDirection.Vertical)
              .scrollBar(BarState.Auto)
              .layoutWeight(1)
              .width('100%')
            }
            .width('94%')
            .height('88%')
            .padding(16)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(SURFACE_NODE)
          }
          .width('100%')
          .height('100%')
          .alignContent(Alignment.Center)
        }

        // ★ 0.150：全局设置弹窗（顶栏 ⚙ 唤起；遮罩点击不关闭，✕/返回键走弹窗内未保存确认）
        if (this.globalSettingsVisible) {
          GlobalSettingsDialog({
            onClose: () => {
              this.globalSettingsVisible = false;
            },
            closeReq: this.globalSettingsCloseReq
          })
        }

        // ★ 0.153：表格放大弹窗（表格「放大」按钮打开，全屏查看 + 换行切换）
        if (this.tableZoomVisible) {
          Stack() {
            // 遮罩：点击关闭
            Column() {
              Blank()
            }
            .width('100%')
            .height('100%')
            .backgroundColor(OVERLAY)
            .onClick(() => {
              this.tableZoomVisible = false;
            })

            // 面板
            Column() {
              // 标题行：标题 + 换行切换 + 关闭
              Row() {
                Text('表格')
                  .fontSize(16)
                  .fontWeight(600)
                  .fontColor(TEXT_PRIMARY)

                Blank()

                // 换行切换按钮：不换行=单行+横向滚动，换行=固定列宽内折行
                // ★ 0.191.0：字符→wrap/nowrap.svg 矢量图标（全局 icon 统一），框样式保留；★ 缩小 20×18/图标14
                Row() {
                  Image(this.tableZoomWrap ? $r('app.media.wrap') : $r('app.media.nowrap'))
                    .width(14)
                    .height(14)
                }
                .width(20)
                .height(18)
                .justifyContent(FlexAlign.Center)
                .alignItems(VerticalAlign.Center)
                .borderRadius(4)
                .backgroundColor(SURFACE_HOVER)
                .border({ width: 0.5, color: STROKE_BRAND })
                .onClick(() => {
                  this.tableZoomWrap = !this.tableZoomWrap;
                })

                // 关闭按钮
                Text('✕')
                  .fontSize(16)
                  .fontColor(TEXT_TERTIARY)
                  .margin({ left: 12 })
                  .onClick(() => {
                    this.tableZoomVisible = false;
                  })
              }
              .width('100%')
              .margin({ bottom: 10 })

              // 表格内容：纵向滚动（外层）+ 横向滚动（内层）+ 固定列宽对齐
              Scroll() {
                Scroll() {
                  Column() {
                    // 表头行
                    Row() {
                      ForEach(this.tableZoomHeader, (cell: string, ci: number) => {
                        // ★ 0.156：划词五件套——放大弹窗表格单元格可划词（key tzh${ci}；wrap 模式完整显示，划词无截断）
                        Text(cell, { controller: this.getOrCreateTextController(`tzh${ci}`) })
                          .fontSize(14)
                          .fontColor(TEXT_PRIMARY)
                          .padding(8)
                          .border({ width: 0.5, color: STROKE_CARD })
                          .width(this.getTableColWidths(this.tableZoomHeader, this.tableZoomRows)[ci])
                          .maxLines(this.tableZoomWrap ? 999 : 1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .textAlign(TextAlign.Center)
                          .copyOption(CopyOptions.LocalDevice)
                          .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, TextResponseType.LONG_PRESS, {
                            onAppear: () => {
                              this.selKey = `tzh${ci}`;
                            },
                            onDisappear: () => {
                              this.clearSelectionState();
                            }
                          })
                          .onTextSelectionChange((start: number, end: number) => {
                            this.handleSelectionChange(`tzh${ci}`, cell, start, end);
                          })
                          .selection(
                            this.selectAllKey.startsWith(`tzh${ci}|`) ? 0 : 1,
                            this.selectAllKey.startsWith(`tzh${ci}|`) ? cell.length : 0
                          )
                      }, (cell: string, ci: number) => `zh_${ci}`)
                    }
                    // 数据行
                    ForEach(this.tableZoomRows, (row: string[], ri: number) => {
                      Row() {
                        ForEach(row, (cell: string, ci: number) => {
                          // ★ 0.156：划词五件套——同表头（key tzr${ri}c${ci}，每格独立 controller）
                          Text(cell, { controller: this.getOrCreateTextController(`tzr${ri}c${ci}`) })
                            .fontSize(14)
                            .fontColor(TEXT_SECONDARY)
                            .padding(8)
                            .border({ width: 0.5, color: STROKE_CARD })
                            .width(this.getTableColWidths(this.tableZoomHeader, this.tableZoomRows)[ci])
                            .maxLines(this.tableZoomWrap ? 999 : 1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .textAlign(TextAlign.Center)
                            .copyOption(CopyOptions.LocalDevice)
                            .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, TextResponseType.LONG_PRESS, {
                              onAppear: () => {
                                this.selKey = `tzr${ri}c${ci}`;
                              },
                              onDisappear: () => {
                                this.clearSelectionState();
                              }
                            })
                            .onTextSelectionChange((start: number, end: number) => {
                              this.handleSelectionChange(`tzr${ri}c${ci}`, cell, start, end);
                            })
                            .selection(
                              this.selectAllKey.startsWith(`tzr${ri}c${ci}|`) ? 0 : 1,
                              this.selectAllKey.startsWith(`tzr${ri}c${ci}|`) ? cell.length : 0
                            )
                        }, (cell: string, ci: number) => `zr_${ri}_${ci}`)
                      }
                    }, (row: string[], ri: number) => `zrow_${ri}`)
                  }
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Auto)
              }
              .scrollable(ScrollDirection.Vertical)
              .scrollBar(BarState.Auto)
              .layoutWeight(1)
              .width('100%')
            }
            .width('94%')
            .height('88%')
            .padding(16)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(SURFACE_NODE)
          }
          .width('100%')
          .height('100%')
          .alignContent(Alignment.Center)
        }

        // ★ 0.145：文本预览弹窗已移除——长按气泡文本直接进入系统选择模式 + 自研悬浮操作栏（bindSelectionMenu）

        // ★ 0.151-D：⋮ 三点气泡菜单面板（合并原发送模式面板 0.133 + 回复长度面板 0.144 为一棵树形菜单）
        // ★ 0.152：触发按钮改为发送右侧 ▾ 小三角（原底栏 💬 按钮移除）；菜单三组：
        // 上组=对话模式（💬 正常对话 / 🎙 播客模式），中组=回复长度（短/中/长），下组=图片添加（原 🖼️ 按钮收编）；
        // 当前选中高亮；半透明遮罩 + 右下角面板，浮于输入区上方
        if (this.modeMenuOpen) {
          Stack() {
            // 遮罩：点击关闭面板
            Column() {
              Blank()
            }
            .width('100%')
            .height('100%')
            .backgroundColor(OVERLAY)
            .onClick(() => {
              this.modeMenuOpen = false;
            })

            // 面板：树形两组选项（组标题 + 选项行，当前选中高亮）
            Column() {
              // ── 上组：对话模式（★ 0.151-D 需求 3：对话模式在上面） ──
              Text('对话模式')
                .fontSize(11)
                .fontColor(TEXT_TERTIARY)
                .width('100%')
                .padding({ left: 12, top: 8 })
                .textAlign(TextAlign.Start)
              Text('💬 正常对话')
                .fontSize(14)
                .fontColor(TEXT_PRIMARY)
                .width('100%')
                .padding(12)
                .textAlign(TextAlign.Start)
                .backgroundColor(this.sendMode === 'normal' ? (BRAND_PRIMARY) : Color.Transparent)
                .borderRadius(RADIUS_CONTROL)
                .onClick(() => {
                  this.sendMode = 'normal';
                  this.modeMenuOpen = false;
                })
              Text('🎙 播客模式')
                .fontSize(14)
                .fontColor(TEXT_PRIMARY)
                .width('100%')
                .padding(12)
                .textAlign(TextAlign.Start)
                .backgroundColor(this.sendMode === 'podcast' ? (BRAND_PRIMARY) : Color.Transparent)
                .borderRadius(RADIUS_CONTROL)
                .onClick(() => {
                  this.sendMode = 'podcast';
                  this.modeMenuOpen = false;
                  track(this.getUIContext().getHostContext() as common.Context, 'podcast_mode'); // 0.206.0 埋点：播客模式（伪需求验证重点）
                })
              Text('口语化输出，适合朗读')
                .fontSize(11)
                .fontColor(TEXT_TERTIARY)
                .width('100%')
                .padding({ left: 12, bottom: 8 })
                .textAlign(TextAlign.Start)
              Divider()
                .color(STROKE_CARD)
                .margin({ top: 4, bottom: 4 })
              // ── 下组：回复长度（★ 0.151-D 需求 3：短中长在下面） ──
              Text('回复长度')
                .fontSize(11)
                .fontColor(TEXT_TERTIARY)
                .width('100%')
                .padding({ left: 12, top: 4 })
                .textAlign(TextAlign.Start)
              Text('短回复')
                .fontSize(14)
                .fontColor(TEXT_PRIMARY)
                .width('100%')
                .padding(12)
                .textAlign(TextAlign.Start)
                .backgroundColor(this.replyLengthMode === 'short' ? (BRAND_PRIMARY) : Color.Transparent)
                .borderRadius(RADIUS_CONTROL)
                .onClick(() => {
                  this.replyLengthMode = 'short';
                  this.modeMenuOpen = false;
                })
              Text('中回复')
                .fontSize(14)
                .fontColor(TEXT_PRIMARY)
                .width('100%')
                .padding(12)
                .textAlign(TextAlign.Start)
                .backgroundColor(this.replyLengthMode === 'medium' ? (BRAND_PRIMARY) : Color.Transparent)
                .borderRadius(RADIUS_CONTROL)
                .onClick(() => {
                  this.replyLengthMode = 'medium';
                  this.modeMenuOpen = false;
                })
              Text('长回复')
                .fontSize(14)
                .fontColor(TEXT_PRIMARY)
                .width('100%')
                .padding(12)
                .textAlign(TextAlign.Start)
                .backgroundColor(this.replyLengthMode === 'long' ? (BRAND_PRIMARY) : Color.Transparent)
                .borderRadius(RADIUS_CONTROL)
                .onClick(() => {
                  this.replyLengthMode = 'long';
                  this.modeMenuOpen = false;
                })
              Text('输出长度为 AI 参考约束，无法保证严格固定字数')
                .fontSize(11)
                .fontColor(TEXT_TERTIARY)
                .width('100%')
                .padding({ left: 12, bottom: 8 })
                .textAlign(TextAlign.Start)
              Divider()
                .color(STROKE_CARD)
                .margin({ top: 4, bottom: 4 })
              // ── 第三组：图片添加（★ 0.152：原底栏 🖼️ 按钮收进下拉菜单）──
              // ★ 0.210.1：彩色 emoji → 华为风格单色透明 svg
              Row({ space: 6 }) {
                Image($r('app.media.image'))
                  .width(15)
                  .height(15)
                  .objectFit(ImageFit.Contain)
                Text('添加图片')
                  .fontSize(14)
                  .fontColor(TEXT_PRIMARY)
              }
              .width('100%')
              .padding(12)
              .borderRadius(RADIUS_CONTROL)
              .onClick(() => {
                this.modeMenuOpen = false;
                this.selectImages(); // 相册多选 → base64 挂到输入区（原链路不变）
              })
            }
            .width(200)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(SURFACE_NODE)
            .border({ width: 1, color: STROKE_CARD })
            .padding(4)
            .margin({ bottom: 64, right: 16 }) // 抬到输入区上方（⋮ 按钮正上方）
          }
          .alignContent(Alignment.BottomEnd)
          .width('100%')
          .height('100%')
        }

        // ★ 0.152：屏幕圈选首次使用说明弹窗（需求文案原文；确认后记 flag 永不再弹）
        // 遮罩不关闭弹窗——确认只走「知道了」按钮（一次性授权说明，防误触跳过）
        if (this.annotationNotifyVisible) {
          Stack() {
            Column() {
              Blank()
            }
            .width('100%')
            .height('100%')
            .backgroundColor(OVERLAY)

            Column() {
              Text('屏幕圈选标注')
                .fontSize(16)
                .fontWeight(600)
                .fontColor(TEXT_PRIMARY)
                .margin({ bottom: 10 })
              Text('用于屏幕圈选标注提问，不会后台录制屏幕。')
                .fontSize(14)
                .fontColor(TEXT_SECONDARY)
                .margin({ bottom: 16 })
              Button('知道了')
                .fontSize(14)
                .width('100%')
                .backgroundColor(BRAND_PRIMARY)
                .fontColor(TEXT_PRIMARY)
                .onClick(() => {
                  this.confirmAnnotationNotify();
                })
            }
            .width('75%')
            .padding(20)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(SURFACE_NODE)
          }
          .width('100%')
          .height('100%')
          .alignContent(Alignment.Center)
        }
      }
      .width('100%')
      .height('100%')
      // ★ 0.195.0：根底色补齐 BG_APP——原根容器未设底色透出窗口纯黑（用户截图实锤 #000000，
      //   与画布/单词库/知识库暗紫底不一致；0.183.0 修三页时本页漏网，本次补上）
      .backgroundColor(BG_CANVAS)
    }
    .hideTitleBar(true)
    // ★ 0.152：标注页 pop 返回时消费标注结果（import/branch/knowledge 三分支；
    // onShown 首次进入及其他页面返回时 action 为空直接跳过）
    .onShown(() => {
      this.consumeCardImport(); // ★ 0.200.0：知识卡片导入落地（画布确认导航进来）
      this.consumeAnnotationResult();
    })
    // ★ 0.153：切后台中断提炼已改由 onAppBackgroundChange（@Monitor 监听全局
    // 前后台标志）实现——NavDestination 组件无 onPageHide 生命周期属性
    // ★ 0.120/0.159：返回拦截统一走 handleBack——有弹窗打开时先关弹窗（消费返回），否则默认返回
    .onBackPressed(() => {
      return this.handleBack();
    })
  }
}

