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

import { AppStorageV2, PersistenceV2, curves, window, KeyboardAvoidMode } from '@kit.ArkUI'; // ★ 0.131：收键盘改用 UIContext.getFocusController()（focusControl 不从 @kit.ArkUI 导出）；★ 0.152：截图改走 UIContext.getComponentSnapshot()（APP 内组件快照截屏，无需系统截屏权限，且避开已废弃的 componentSnapshot.get）；★ 0.234.0：curves（onDone 收拢 springMotion 弹簧曲线——华为物理动效血统）
import { common, abilityAccessCtrl } from '@kit.AbilityKit'; // 0.206.0 埋点 getHostContext（★ 0.283.0：abilityAccessCtrl 复入——READ_PASTEBOARD user_grant 运行时授权，随新 Profile ACL 资格第三次申报落地；hilog 诊断埋点随拖拽验证通过删除）
import { track, trackUidAuto } from '../utils/TrackUtil'; // 0.206.0 埋点；★ 0.260.0：trackUidAuto（sp_consume）
import deviceInfo from '@ohos.deviceInfo'; // ★ 0.215.14：设备类型三档（deviceType=phone/tablet/2in1/default，d.ts 实锤）
// ★ 删除未使用 import common（0.122 清理）
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo, picker } from '@kit.CoreFileKit'; // ★ 0.246.0：picker（DocumentViewPicker 保存图片——免权限系统保存对话框）
import { buffer } from '@kit.ArkTS';
import { pasteboard } from '@kit.BasicServicesKit'; // ★ 0.145：pasteboard（划词复制）；★ 0.189.0：BusinessError 随 TTS 管线移除；★ 0.275.0：Ctrl+V 读取剪贴板图片（getData + PasteDataRecord.pixelMap/uri）
import { unifiedDataChannel } from '@kit.ArkData'; // ★ 0.275.0：onDrop 拖拽图片记录类型（DragEvent.getData → UnifiedData → Image.imageUri）

  import { BubbleNode, ChatMessage, BubbleTree, CurrentBubble, ApiConfig, PersistData, generateMessageId, generateNodeId, serializeBubbleTree, connectApiConfig, AiPreference, connectAiPreference, AnchorPref, connectAnchorPref, CanvasModeStore, connectCanvasMode, TabMeta, TabForestStore, connectTabForest, parseTabs, serializeTabs, getRootDisplayName, LearnCountStore, connectLearnCount, KnowledgeCountStore, connectKnowledgeCount, BookmarkEntry, BookmarkData, ChatBookmarkStore, connectChatBookmarks, StatisticsStore, connectStatistics, recordStat, SiyiPointStore, connectSiyiPoints, siyiTotalSp, consumeSiyiSp, getStatDays, isSiyiSpFree, resolveThinkingFor, isThinkingParamError, ThinkingRequest, spCostOfTokens, trackSpConsumeAuto, SP_INPUT_PRICE_RATIO, SP_HIT_PRICE_RATIO, SP_OUTPUT_PRICE_RATIO, SP_TOKEN_DIVISOR, SP_COST_MULTIPLIER, SP_CACHE_SAVING_RATIO, spCostOfTts, docPageTokens, connectSishuClassic } from '../common/ChatModel'; // ★ 0.143：connectApiConfig；★ 0.150：AiPreference（全局设置弹窗）；★ 0.151：画布模式分池保存；★ 0.151-bugfix2：Tab 名同步；★ 0.161：学习数量设置（单词库 ⚙ 设置，两处复习区共用）；★ 0.161.2：知识卡片数量设置（知识库 ⚙ 设置）；★ 0.191.0：BookmarkEntry/BookmarkData/connectChatBookmarks（阅读位置书签）；★ 0.192.0：StatisticsStore/recordStat（学习统计埋点）；★ 0.234.0：AnchorPref/connectAnchorPref（锚点/折叠偏好 anchor-pref-v1）；★ 0.247.1：ModelAliasStore/connectModelAlias 移除（别名机制下线，用户拍板）；★ 0.271.0：深度思考四件（归一/策略矩阵/降级判定/ThinkingRequest 统一类型）；★ 0.272.0：SP 常量与公式迁回（spCostOfTokens/trackSpConsumeAuto/六常量——单一真相源）；★ 0.291.2：docPageTokens（文档页费嫁接——页数折算等效 input token 并账）；★ 0.300.0：connectSishuClassic（经典模式灰度开关）
  import { PendingDoc, DocParseResult, ATTACH_SUFFIX_FILTERS, DOC_CONFIRM_BYTES, DOC_MAX_BYTES, docExtOf, isImageExt, isDocExt, needsCloudParse, fmtDocSize, parseDocsForSend, buildDocContextBlock, docListLabel } from '../utils/DocParseUtil'; // ★ 0.291.2：文档加载（+号混选/格式路由/腾讯云解析/system 注入——方案 docs/0.165+/0.291.0）
  import { PODCAST_PROMPT, MEDIUM_REPLY_PROMPT, LONG_REPLY_PROMPT, SUMMARY_PROMPT, SECTION_PROMPT, ANCHOR_MEDIUM_PROMPT, PLAN_PROMPT, buildWritePrompt, PLAN3_PROMPT, buildDeliverPrompt, CENSOR_PROMPT } from '../common/Prompts'; // ★ 0.193.0：prompt 单一真相源（B 项）；★ 0.234.0：SECTION/ANCHOR（锚点一期）；★ 0.290.0：PLAN_PROMPT/buildWritePrompt（司枢 2.0 两段式）+ HOOK_SYSTEM_PROMPT/buildAnchorLongPrompt 退役（②段伴读废止、长回复锚点指令并入框架规划）；★ 0.300.0：司枢 3.0 三件（PLAN3_PROMPT 枢机契约/buildDeliverPrompt 交付执笔/CENSOR_PROMPT 御史）
  import { TaskContract, SishuClarifyState, connectSishuClarify, sanitizeContract, contractToneLine, buildContractBrief, recordCorrectEntry, loadCorrectHint, parseCensorVerdict } from '../common/SishuAgent'; // ★ 0.300.0：司枢 Agent 3.0 契约层（会话级不持久化）
import { WordItem, WordBankStore, WordQueryResult, WordFolder, WordFolderTreeItem } from '../common/WordModel'; // ★ 0.145：单词库数据模型；★ 0.222.21：WordFolder/WordFolderTreeItem（加词目标文件夹选择弹窗）
import { KnowledgeCard, KnowledgeBankStore, KnowledgeQueryResult, KFolder, KFolderTreeItem, CardImportStore, connectCardImport, AttentionStore, connectAttention, updateAttention, parseTags, getTitleImages, getCardImages } from '../common/KnowledgeModel'; // ★ 0.146：知识库数据模型；★ 0.200.0：卡片导入气泡落地消费；★ 0.202.0：注意力标签提取；★ 0.202.1：parseTags（建议标签勾选）；★ 0.222.22：KFolder/KFolderTreeItem（知识卡入库文件夹选择弹窗）；★ 0.246.0：getTitleImages/getCardImages（司忆区知识卡正反面缩略图）
import { image } from '@kit.ImageKit'; // ★ 0.152：截图 PixelMap 打包 base64（componentSnapshot 产物 → data URI）
import { streamChat, queryWord, queryKnowledge, queryKnowledgeFromImage, StreamController, startsWithChinese, classifyStreamError, buildWebToolsSchema, buildToolRoundMessages, ToolCallResult } from '../utils/ApiClient'; // ★ 0.145：queryWord（AI 查词）；★ 0.146：queryKnowledge（AI 卡片草稿）；★ 0.152：queryKnowledgeFromImage（圈选截图入知识库·多模态提炼）；★ 0.222.21：startsWithChinese（划词方向首字符检测，替代 containsChinese）；★ 0.190.6：classifyStreamError（错误场景分类）；★ 0.271.0：ThinkingRequest 改从 ChatModel import（类型单一真相源）；★ 0.292.0：联网工具循环（WEB_TOOLS_SCHEMA/buildToolRoundMessages/ToolCallResult）
import { ContentFilter, FilterHit } from '../utils/ContentFilter'; // ★ 0.250.0：敏感词本地预过滤（上架合规应用侧兜底防线）
import { connectWordBank, addWordToBank } from '../utils/WordStoreUtil'; // ★ 0.145：单词库持久化与操作；★ 0.187.0：pickRandomWords 移除（选词改走记忆算法）
import { MemoryRating, MemoryItem, pickReviewWords, pickReviewCards, orderedReviewWords, orderedReviewCards, rotateSlice, applyPassiveReview, applyRating, formatNextReviewLabel, previewIntervalDays, formatIntervalDays } from '../utils/MemoryAlgorithm'; // ★ 0.187.0：记忆算法（遗忘曲线选词 + 展示即复习 + 3 档评分）；★ 0.188.0：知识库复刻（pickReviewCards + MemoryItem 联合类型）；★ 0.196.0：评分按钮时间预览（previewIntervalDays + formatIntervalDays）；★ 0.237.3：换一批（orderedReviewWords/Cards 全序视图 + rotateSlice 环绕轮换）
import { FaceModeStore, connectFaceMode } from '../common/FaceModeStore'; // ★ 0.224.0：司忆区跟随全局卡面模式（单面/双面）
  import { noteBankMutation, saveBubbleTreePools } from '../common/ChatModel'; // ★ 0.223.0：评分/展示复习进度上云钩子（3 秒防抖）；★ 0.287.0：saveBubbleTreePools 分池保存公共函数（saveTree 消重+撤销栈闭包安全）
import { connectKnowledgeBank, addKnowledgeCard } from '../utils/KnowledgeStoreUtil'; // ★ 0.146：知识库持久化与操作；★ 0.188.0：pickRandomKnowledgeCards 移除（选卡改走记忆算法）
import { AnnotationPrefStore, AnnotationDraftStore, AnnotationResultStore, connectAnnotationPref, connectAnnotationDraft, connectAnnotationResult } from '../common/AnnotationModel'; // ★ 0.152：屏幕圈选标注（首次提示 flag + 截图草稿 + 结果回传）
import { SketchResultStore, connectSketchResult } from '../common/SketchModel'; // ★ 0.297.0：数学证明画板（结果回传）
import { completeRookieTask } from '../common/RookieTask'; // ★ 0.294.0：好奇宝宝新手任务完成信号（六挂点：新建气泡/司枢/圈注/划词翻译/划词入库/司忆区评分）
import { wordSpeaker, showAccentDialogs, speakerPulse } from '../utils/WordSpeaker'; // ★ 0.149：单词发音 TTS 单例；★ 0.189.1：本地引擎化；★ 0.189.2：口音提示弹窗工厂共用
import { localTts } from '../utils/LocalTtsEngine'; // ★ 0.189.0：本地 TTS 引擎（CoreSpeechKit 免费离线，替换火山云端——消息朗读直连）
  import { MdSpan, MdBlock, parseInlineMd, blockPlainText, blockRenderedText, headerFontSize, listMarker, headingIcon, mdToSpeakableText, stripAnchorMarks, breathThreshold, FoldItem, FoldSection, insertLocalAnchors, splitFoldSections, initExpandedSet, PlanFrame, PlanHook, sanitizePlan, mergeSectionHooks, planFrameJson, planToneLine, buildTableMarkdown, buildTablePlainText } from '../utils/MdInline'; // ★ 0.231.0：Markdown 行内/块级渲染纯函数模块；★ 0.232.0：mdToSpeakableText；★ 0.234.0：锚点+分章折叠全家桶；★ 0.237.1：blockRenderedText；★ 0.290.0：司枢 2.0 框架四件（PlanFrame/sanitizePlan/mergeSectionHooks/planFrameJson/planToneLine）——旧 0.269.0 合成器四件（HookSpec/parseHookJsonResponse/scanBlockSpans/mergeHooksIntoContent）随②段伴读退役移除；★ 0.285.5：表格整表工具两件；★ 拆分：renderMathText/parseBlockMd 随 ChatMdParser 迁出
import { cloudTts } from '../utils/CloudTtsEngine'; // ★ 0.232.0：云端 TTS 引擎（火山 openspeech 回归——云端优先，失败回退本地）
import { qianwenTts } from '../utils/QianwenTtsEngine'; // ★ 0.236.0：千问 TTS 引擎（百炼 CosyVoice 复刻音色——ttsProvider='qianwen' 时优先，失败回退本地）
import { CodeToken, tokenizeCode } from '../utils/SyntaxHighlight'; // ★ 0.149：代码块语法高亮（MVP 正则分词）
// ★ 0.251.0：AppLifecycleStore import 随 0.153「切后台中断提炼」策略反转删除（后台保活见 utils/AiStreamGuard.ets）
import { upsertCloudData } from '../utils/CloudSyncUtil'; // ★ 0.165.1：云同步桥接（持久化点追加写 RDB 快照行，autoSync 自动上云）
import { GlobalSettingsDialog, isKnownTextOnlyModel, GlobalSettingsSharedStore, connectGlobalSettingsShared } from './GlobalSettingsDialog'; // ★ 0.150：全局设置弹窗（顶栏 ⚙ 唤起，Tab1 API 配置 + Tab2 AI 偏好）；★ 0.190.2：加 isKnownTextOnlyModel（纯文本模型发图拦截）；★ 0.230.0：加共享开态 store
import { ClarifyCard } from './ClarifyCard'; // ★ 0.300.0：司枢 3.0 反问收束卡（对话流内嵌，性格测试 3.0 点选流同款）
import { FoldChevron } from './FoldChevron'; // ★ 0.237.0：全项目唯一折叠指示器（军令统一——chevron SVG 旋转两态）
import { TokenInfoChip } from './TokenInfoChip'; // ★ 0.272.0：通用感叹号信息卡（查词/提炼 SP 透明化；主链路 tokenInfoBuilder 不动防回归）
// ★ 0.181.0：UI 规格化——散落色值/isDark 三元收敛到 DesignTokens（0.166.3 锁暗色后浅色分支是死代码）
import { WindowMode, connectWindowMode } from '../common/WindowMode'; // ★ 0.196.4：窗口宽度模式共享真相源（分屏/悬浮窗切手机布局）
import { RADIUS_NAV, RADIUS_NODE, RADIUS_CONTROL, FONT_SIZE_SCREEN_TITLE, FONT_INTER, FONT_INTER_SEMIBOLD, FONT_SIZE_CAPTION } from '../common/DesignTokens';
import { AppTheme, connectAppTheme } from '../common/AppTheme';
import { connectHuaweiAccount, requireLoginForCloud } from '../utils/HuaweiAccountUtil'; // ★ 0.248.2：AI 登录守卫（上架合规——未登录禁止问 AI）；★ 0.248.3：圈注/划词守卫
import { requireSiyiGate } from '../utils/SiyiGate'; // ★ 0.293.0：SP 云同步门卫（消耗 SP 的 AI 功能前置闸——账本云端对齐才放行）
import { connectConfirmDialog } from './AppConfirmDialog'; // ★ 0.248.2：AI 登录引导弹窗桥（Index 根 Stack 消费）
import { ProfileStore, connectProfileObservations, buildCardView, updateProfileFromConversation,
  noteInactiveNode, buildSiblingHeadsContext, bindMemoryEngine, memoryTokenEstimate,
  MemoryInjectStatsStore, connectMemoryInjectStats, recordMemoryInjectStats,
  connectMemoryPref, isMemoryOn } from '../common/ProfileModel'; // ★ 0.265.0 记忆引擎一期（画像观察行+分支摘要头+注入埋点）
import { triggerAiRerank, getRerankWordIds, getRerankCardIds, rerankDisplayBatch } from '../utils/AiRerank'; // ★ 0.268.0：司忆区 AI 智慧排序（发送时预触发+渲染时消费 AI 序，失败静默兜底本地序）
import { fetchWebContextForMessage, detectWebUrls, WebFetchSummary, fetchSingleUrlReadable, searchWeb, formatSearchResults, WEB_MAX_TOOL_ROUNDS } from '../utils/WebFetchUtil'; // ★ 0.286.0：AI 读网页一期（纯客户端抓取——消息含链接时抽正文一次性注入本次请求，失败不阻断）；★ 0.286.1 壳页走隐藏 Web 组件渲染重取；★ 0.292.0：联网工具循环数据源（单URL瀑布/searchWeb/formatSearchResults/轮数上限）
import { connectUndoStack, UndoStore } from '../common/UndoStack'; // ★ 0.287.0：操作撤销栈（删除消息入栈；Ctrl+Z 全局键在 Index 层消费）
import { webview } from '@kit.ArkWeb'; // ★ 0.286.1：AI 读网页渲染通道（SPA 文档站静态抓只有壳——Web 组件真渲染后注入脚本取 innerText）
// ★ 拆分重构（自 ChatPage 原文内区块迁出）：WaitingDots/CodeBlockView 独立组件件、ChatPageTypes 类型常量层、ChatMdParser 解析纯函数层
import { WaitingDots } from './WaitingDots';
import { CodeBlockView } from './CodeBlockView';
import { MdSegment, ReviewCacheEntry, KnowledgeReviewCacheEntry, RichPlan, RichPlanEntry, PlanCacheEntry, ChatFontScaleStore, connectChatFontScale, ImageViewerStore, connectImageViewer, PLACEHOLDER_LOADING, PLACEHOLDER_THINKING, TREE_CELL, chatScrollMemory, chatFoldMemory, animOn, glowHighlight, BODY_LINE_HEIGHT_RATIO, PC_SELECTION_MENU_WIDTH } from '../common/ChatPageTypes';
import { parseMarkdown, buildFoldItems } from '../utils/ChatMdParser';
import { WordFolderPicker, CardFolderPicker, QuotePicker } from './FolderPickerDialogs';
import { ImageViewer } from './ImageViewer';

// ★ 0.300.0：联网本地预路由关键词宽匹配（任务书 §三.1——宁可多挂声明、不可漏挂：
// 多挂代价仅几十 token，漏挂=场景整个失效；只作用于单段直写链路，司枢链路恒挂由枢机自主）
const WEB_PREROUTE_RE: RegExp = /(查一下|查查|搜一下|搜索|帮我查|官网|官方网站|最新|新闻|今天|现在几点|价格|多少钱|版本|政策|资质|发布|上线|写一篇|写个|生成|改写|润色|发帖|发到|投稿|邮件|文案|翻译)/;
// ★ 0.300.0：枢机工具轮防死循环护栏（非省 SP——产品军令 2 消耗永不封顶；这是防 bug）：
// 连续 N 轮工具结果全空/失败→停挂 tools 强制落笔；重复打开同一 URL→结果直回已读提示
const ORCH_EMPTY_ROUNDS_LIMIT: number = 2;
const ORCH_TOOL_ROUNDS_LIMIT: number = 8;

// 对话页面 — V2 全量迁移
@ComponentV2
export struct ChatPage {
  theme: AppTheme = connectAppTheme();
  @Param pathStack: NavPathStack = new NavPathStack();
  // ★ 0.297.0：数学证明画板——+号展开菜单态 + 画板结果回传（@Local 接管 connect 实例）
  @Local plusMenuOpen: boolean = false;
  @Local sketchResult: SketchResultStore = connectSketchResult();
  gsShared: GlobalSettingsSharedStore = connectGlobalSettingsShared(); // ★ 0.230.0：设置弹窗共享开态（跨页返回键拦截）
  store: BubbleTree = AppStorageV2.connect(BubbleTree, 'bubble-tree', () => new BubbleTree()) as BubbleTree;
  persistData: PersistData = PersistenceV2.connect(PersistData, 'persist-data', () => new PersistData()) as PersistData;
  currentBubbleStore: CurrentBubble = AppStorageV2.connect(CurrentBubble, 'current-bubble', () => new CurrentBubble()) as CurrentBubble;
  apiConfig: ApiConfig = connectApiConfig(); // ★ 0.143：换 key 'api-config-v2'（旧快照无 audioKey 字段致新增属性不落盘，工厂迁移历史配置）
  // ★ 0.247.1：aliasStore 引用删除——别名机制下线（用户拍板），顶栏模型名固定用 apiConfig.model 原名
  bookmarkStore: ChatBookmarkStore = connectChatBookmarks(); // ★ 0.191.0：阅读书签持久化（方案 B，跨重启）
  @Local bookmarkCache: BookmarkEntry | null = null; // ★ 0.191.0：本气泡书签缓存（渲染期高频查询免逐段 JSON 解析）
  aiPreference: AiPreference = connectAiPreference(); // ★ 0.150：AI 偏好（称呼 + 鼓励开关，独立 key 'ai-preference-v1'）
  anchorPref: AnchorPref = connectAnchorPref(); // ★ 0.234.0：注意力锚点偏好（锚点卡片/密度/分章折叠，独立 key 'anchor-pref-v1'）
  // ★ 0.234.0：流式中的消息 ID（该消息走平铺直显不折叠；onDone 瞬间清空触发收拢）
  @Local streamingMsgId: string = '';
  // ============================================================
  // ★ 0.290.0 司枢模式 2.0：框架先行两段式状态（消息级状态机 planning→writing→merged；
  //   同一时间只允许一个进行中①段——发新消息/重生成/切分支自动取消旧①段）
  //   旧 0.269.0 ②段伴读编排（arranging→merged）已随 HOOK_SYSTEM_PROMPT 退役整体移除。
  // ============================================================
  @Local planningMsgId: string = '';         // ①段规划进行中的消息 ID（空=无；气泡内规划卡依据）
  @Local planPreview: string = '';           // ①段流式预览文本（规划卡滚动展示，思考卡同族浅紫底）
  planController: StreamController | null = null; // ①段流控制器（取消/regenerate 防乱序）
  // ============================================================
  // ★ 0.300.0 司枢 Agent 3.0：三角色流水线状态（枢机→执笔→御史）
  //   契约=会话级临时数据（任务书 §二铁律：不持久化/不进 Schema/不写对话历史）
  // ============================================================
  @Local sishuSpPreview: string = '';        // 分阶段实时已耗 SP 估算（枢机/工具/执笔/御史逐轮累计，状态行展示）
  @Local censorBadge: string = '';           // 审核中标记（「正在审核（第N轮）」——消息区审核卡依据；空=无）
  contractByMsg: Map<string, TaskContract> = new Map();        // 交付卡渲染依据+纠偏入口（会话级；刷新退化普通气泡）
  @Local deliverMsgIds: string[] = [];                          // 交付型完成标记（@Local 整体重赋值触发渲染——交付卡出现依据）
  correctPendingByMsg: Map<string, TaskContract> = new Map();  // 纠偏重跑契约暂存（regenerate 消费即删）
  clarifyResume: ((answers: string[] | null) => void) | null = null; // ★ 0.300.0 反问恢复闭包（onSubmit/onSkip→resolveClarify；重入/销毁→abandonClarify 静默死亡）
  clarifyState: SishuClarifyState = connectSishuClarify();     // 反问卡共享 store（AppStorageV2 应用级不落盘）
  classicStore = connectSishuClassic();      // ★ 经典模式灰度开关（true=旧 0.290.0 两段式链路）
  streamGen: number = 0;                     // 任务代际（反问 await 恢复后核对——被新任务顶替则静默中断）
  // ============================================================
  // ★ 0.271.0 深度思考模式：思考卡状态机（phase2 思考中→phase3 冻结收起；乱序防护=contentStarted
  //   局部 flag；思维链会话级 Map 暂存 5000 字截断——不进 ChatMessage、不持久化、不云同步）
  // ============================================================
  @Local thinkingActiveMsgId: string = '';   // 思考中的消息 ID（思考卡浮现依据；空=无）
  @Local thinkingElapsed: number = 0;        // 思考计时（秒——setInterval 1s 更新，超 10s 显示取消钮）
  @Local thinkingHeadText: string = '';      // 思维链滚动摘要（前 120 字，随分片刷新）
  @Local thinkingEnabledNow: boolean = false; // 本次流式请求思考档是否生效（waitingView「·深度思考」后缀依据）
  thinkingTraceByMsg: Map<string, string> = new Map(); // 思维链全文暂存（msgId → 文本，单条 5000 字截断；切分支/退会话清空）
  thinkingSecondsByMsg: Map<string, number> = new Map(); // 完成思考的秒数（收起行「已深度思考 Ns」）
  @Local thinkingDoneTick: number = 0;       // 收起行渲染依赖驱动（Map 非 @Trace，用 tick 触发重建）
  @Local thinkingRetryMsgIds: string[] = []; // 思考档失败待手动降级重试的消息 ID（错误气泡「普通模式重试」按钮渲染依据）
  thinkingTimer: number = -1;                // 思考计时器句柄（aboutToDisappear/流结束必清）
  // ★ 0.234.0：折叠展开状态视图（msgId → 展开节 index 集；整体替换触发 V2 刷新——0.222.2 铁律；
  //   持久真身在模块级 chatFoldMemory，切页面回来保留）
  @Local foldStateView: Map<string, Set<number>> = new Map();
  // ★ 0.234.0：消息渲染计划缓存（msgId → 条目；流式增量按 content 长度失效，设置变化按指纹失效；
  //   超 40 条全清防膨胀——单气泡消息量级下极少触发）
  private planCache: Map<string, PlanCacheEntry> = new Map();
  statStore: StatisticsStore = connectStatistics(); // ★ 0.192.0：学习统计（只增不减，删除消息/气泡不影响已统计数据）
  siyiStore: SiyiPointStore = connectSiyiPoints(); // ★ 0.248.7：司忆点（发送前余额闸门+回复完成实扣）
  canvasModeStore: CanvasModeStore = connectCanvasMode(); // ★ 0.151：画布模式（'flat'/'tabs'，独立 key 'canvas-mode-v1'）
  tabForest: TabForestStore = connectTabForest();         // ★ 0.151：Tab 池（tabsJson + activeTabId，独立 key 'tab-forest-v1'）
  @Local inputText: string = '';
  // ★ 0.287.2：输入法组词态（拼音/语音预编辑未上屏）——自绘占位必须让位，否则与输入法文字叠在一起；
  //   信号来自 TextArea onChange 的 previewText 第二参（API 12+，组词中 value 非空、上屏后清空）
  @Local imeComposing: boolean = false;
  @Local isLoading: boolean = false;
  // ★ 0.162：分支切换过渡动画状态——addBubble 切换气泡时消息区先淡出再淡入（约 440ms），
  // 让用户明确感知「跳到了新的空白消息页」（原瞬间清空重载刷屏过快、空页面时无感知）
  @Local msgAreaOpacity: number = 1;       // 消息区透明度（1=不透明；动画期间 0↔1 补间）
  @Local branchAnimating: boolean = false; // 分支切换动画进行中（防抖：播完前忽略重复点击）
  @Local pendingImages: string[] = [];
  // ★ 0.291.2：待发文档（+号混选）——与 pendingImages 合计上限 9；uri 会话级有效不进草稿
  //   （picker uri 跨会话可能失效，刷新/退出=文档自然丢弃，图片/文字草稿照旧）
  @Local pendingDocs: PendingDoc[] = [];
  // ★ 0.291.2：文档计费首次告知标记（冷启后首次带文档发送弹一次告知；会话级不落盘——
  //   避免新增持久化 key，每次冷启首弹一次可接受）
  docBillingNotified: boolean = false;
  // ★ 0.145：划词翻译状态（替代原长按菜单/文本预览/删除确认——旧二级弹窗整体移除）
   @Local selText: string = '';            // 当前选中文本（onTextSelectionChange 时从对应 Text 内容截取）
   @Local selStart: number = -1;           // ★ 0.191.0：选中起始偏移（划词级书签用；-1=无有效选中）
   @Local selEnd: number = -1;             // ★ 0.191.0：选中结束偏移
   // ★ 0.191.0：粘性选中区间（不被 clearSelectionState 清理）——表格横向 Scroll 内拖选时菜单消失重弹
   // 丢失 selStart/selEnd，点「标记」误报「请划选文字」；同 key 兜底恢复（见 effectiveSelStart）
    private stickySelKey: string = '';
    private stickyStart: number = -1;
    private stickyEnd: number = -1;
    // ★ 0.285.5：粘性选中文本副本（同上族）——表格跨格拖选时拖出格子边界系统即取消选区，
    //   clearSelectionState 清空 selText 后 Ctrl+Shift+C/复制/翻译连锁报「请先划选文字」
    //   （用户实锤「找不到词」）；lastSelKey 配对兜底（见 effectiveSelText）
    private stickySelText: string = '';
   @Local selKey: string = '';             // 当前激活选择的 Text 标识（`${msgId}|u` 用户消息 / `${msgId}|${segIdx}` AI 段）
   // ★ 0.279.0：输入框（TextArea）自身选区——Ctrl+C 双闸之一：框内有有效选区时放行系统默认复制
  // （0.285.3 删 inputSelStart/inputSelEnd——输入框选区追踪随 Ctrl+C 接管一起退役）
   @Local selectAllKey: string = '';       // 全选受控态标识（`${selKey}|${nonce}`，nonce 递增确保重复点击仍触发属性重应用）
   @Local selectAllNonce: number = 0;      // 全选触发计数（配合 selectAllKey）
    // ★ 0.235.0 修法 B：最近一次有效选择的 key 副本（不被 clearSelectionState 清理）——
    // selKey 已被 onDisappear 清空但系统高亮/菜单残留时，closeActiveSelectionMenu 退用它兜底关闭
    private lastSelKey: string = '';
    // ★ 0.235.0 修法 C：List onTouch Down 时刻的选中 key 快照——Up 时仅当「选中未变」才执行清除
    // （长按新建选择会改变 selKey → 该次抬手不是「点空白收起」意图，误清会废掉整个划词功能）
    private selKeyAtTouchDown: string = '';
    // ★ 0.235.0：划词引用——选中内容挂输入区引用栏，发送时注入 prompt（一次性消费；不进草稿/Schema）
    @Local quoteText: string = '';               // 当前生效的引用全文（''=无引用）
    @Local quotePickerVisible: boolean = false;  // 二选一弹窗（引用到本聊天 / 引用为新子气泡）
    private quotePendingText: string = '';       // 弹窗暂存（取消则丢弃，不入 quoteText）
  @Local wordPopupVisible: boolean = false;   // 翻译浮窗可见
  @Local wordPopupQuery: string = '';         // 浮窗展示的查询原文
  @Local wordPopupLoading: boolean = false;   // AI 查词进行中
  @Local wordPopupResult: WordQueryResult | null = null; // 查词结果（null=未出结果）
   @Local wordPopupError: string = '';         // 查词错误信息
   @Local wordPopupAdded: boolean = false;     // 当前结果已加入单词库（按钮转「已加入」防重复）
  // ★ 0.272.0：查词 SP 透明化——token 用量与 SP 行文本（信息卡数据源；spText 空串=不出结果前不渲染）
  @Local wordPopupInTok: number = 0;
  @Local wordPopupOutTok: number = 0;
  @Local wordPopupSpText: string = '';
  // ★ 0.246.0：翻译浮窗司忆区——划词查词等待期顺便学习（词库 N 词+知识库 M 卡，⚙ 设置驱动）；
  //   样式与提炼弹窗复习区同款，独立状态+`wpp|` 前缀 key（与提炼弹窗 `edit|` 互不干扰）
  @Local wordPopupReviewWords: WordItem[] = [];
  @Local wordPopupReviewCards: KnowledgeCard[] = [];
   @Local wordExistsTip: boolean = false;      // 「单词已存在」提示（重复添加时显示）
   // ★ 0.222.21：加词目标文件夹选择弹窗（点「加入单词库」弹出；UI 与单词库移动/复制弹窗同款）
   @Local wordFolderPickerVisible: boolean = false;
   // ★ 0.150：删除确认弹窗状态（防误触；「不再提示」仅本次对话会话内生效，重进对话页重置）
  @Local deleteConfirmVisible: boolean = false; // 确认弹窗可见
  @Local deleteConfirmMessageId: string = '';   // 待删除的消息 ID
  @Local deleteConfirmNoAsk: boolean = false;   // 弹窗内「不再提示」勾选框当前状态（每次打开复位）
   @Local deleteSkipConfirm: boolean = false;    // 本次会话内已勾选「不再提示」（aboutToAppear 重置）
   // ★ 0.286.0：AI 内容举报（华为上架合规 G.3.8——AI 对话模块需显著举报入口）：flag 按钮 → 本地确认弹窗 → mailto
   @Local reportConfirmVisible: boolean = false; // 举报确认弹窗可见
   @Local reportTargetModel: string = '';        // 被举报消息的模型 ID（邮件正文自动附，便于追溯）
   undoStack: UndoStore = connectUndoStack(); // ★ 0.287.0：撤销栈（删除消息入栈）
   // ★ 0.286.1：AI 读网页渲染通道——SPA 文档站静态抓取只有壳（用户实测「文档中心」四字），
   //   按需挂载 1×1 隐形 Web 组件真渲染（javaScript+domStorage 全开），onPageEnd 后轮询注入脚本
   //   取 document.body.innerText（800ms×最多 5 轮等 SPA 异步出正文，整页 15s 超时兜底）；
   //   串行队列（一次渲染一页，最多 2 页），队列空即卸载组件（不常驻占内存）
   @Local webRenderActive: boolean = false;      // Web 组件挂载开关（if 控制挂/卸——挂载时恒 true，非 0.160 隐藏雷）
   webRenderController: webview.WebviewController = new webview.WebviewController();
   webRenderControllerReady: boolean = false;    // onControllerAttached 信号（attached 前 loadUrl 会抛异常）
   webRenderQueueUrls: string[] = [];            // 待渲染 URL 串行队列
   webRenderQueueResolvers: Array<(v: string) => void> = []; // 队列配套 resolve
   webRenderCurrentUrl: string = '';             // 正在渲染的 URL（空=空闲）
   webRenderTimeoutId: number = -1;              // 整页超时定时器句柄
   webRenderPollCount: number = 0;               // onPageEnd 后取文轮询计数
   webRenderPolling: boolean = false;            // 轮询进行中（防重入）
  // ★ 0.247.1：PC 判定——true=停用消息滑动删除（PC 鼠标按下拖动是划词手势，被 swipe 抢走）。
  //   ★ 0.247.2 改设备形态判定：deviceInfo.deviceType==='2in1'（Matebook=2in1）——弃 inputDevice
  //   sources 探测（Pad/手机外接触控板/蓝牙鼠标或系统虚拟设备即误报 true → 滑动删除被误停）；
  //   Pad=tablet / 手机=phone 恒保留右滑删除，PC 恒停用。aboutToAppear 同步赋值
  @Local hasMouse: boolean = false;
  // ★ 0.247.3：token 明细弹层（感叹号点击弹出「输入 N · 输出 N」）——单开互斥：tokenInfoMsgId 记当前打开的消息 id
  //   （空串=全关）；tokenInfoText=打开瞬间文本快照，无参 @Builder 直读（0.190.1 带参 @Builder 按值传参铁律）
  @Local tokenInfoMsgId: string = '';
  @Local tokenInfoText: string = '';
  @Local tokenInfoCacheLine: string = ''; // ★ 0.247.4：缓存命中行（空串=不渲染——无缓存数据/旧消息；★ 0.248.7 恒显示后仅输入 token 缺失时为空）
  @Local tokenInfoHookLine: string = ''; // ★ 0.269.0：伴读编排拆分行（空串=不渲染——非伴读消息/免扣/②段未成功；Q9 明细弹层拆分）
  @Local tokenInfoCacheHit: boolean = false; // ★ 0.248.7：缓存行命中态（true=品牌紫省钱行 / false=普通色未命中行）
  wordBank: WordBankStore = connectWordBank(); // ★ 0.145：单词库（独立 PersistenceV2 key，与气泡树持久化隔离）
  imgViewer: ImageViewerStore = connectImageViewer(); // 全屏图片浏览器共享态（ImageViewer 组件消费）
  learnCountStore: LearnCountStore = connectLearnCount(); // ★ 0.161：学习数量（单词库 ⚙ 设置，默认 2；驱动气泡复习区+提炼弹窗复习区词条数）
  knowledgeCountStore: KnowledgeCountStore = connectKnowledgeCount(); // ★ 0.161.2：知识卡片数量（知识库 ⚙ 设置，默认 1 保持现状；驱动气泡复习区+提炼弹窗复习区卡片数）
  private textControllers: Map<string, TextController> = new Map(); // 每个 Text 独立 controller（关闭选择菜单用）
  private wordQueryController: StreamController | null = null;      // 进行中的查词请求（浮窗关闭时取消）
  private reviewCache: Map<string, ReviewCacheEntry> = new Map();   // 生词复习缓存（msgId → 随机词组）
  // ★ 0.237.3：换一批——复习区整批轮换（AI 回复操作栏 shuffle 按钮）
  //   rerollSeq 挂 @Local：ForEach 数据源以第二参读到它建立渲染依赖（漏挂 @Local 依赖链真机不可靠——历史雷）；
  //   两 offset Map 记录各消息已轮换偏移（确定性排序下直接重抽=同一批，必须偏移环绕）
  @Local rerollSeq: number = 0;
  private rerollWordOffsets: Map<string, number> = new Map();   // 生词轮换偏移（msgId → 跳过词数）
  private rerollCardOffsets: Map<string, number> = new Map();  // 知识卡轮换偏移（msgId → 跳过卡数）
  // ★ 0.268.0：AI 智慧排序——本地序→AI 序延迟到达的替换脉冲（150ms 透明度渐变，防突兀闪烁）
  //   + 展开卡护栏挂起队列（用户已展开任一复习卡时延迟替换，收起后再切——任务书 Q3 终裁）
  @Local siyiSwapPulse: boolean = false;
  private pendingRerankMsgIds: Set<string> = new Set();
  // ★ 0.146：知识库卡片编辑弹窗状态（AI 生成草稿 → 用户编辑确认 → 入库；AI 不直接入库）
  @Local knowledgeEditVisible: boolean = false;  // 编辑弹窗可见
  @Local knowledgeCardTitle: string = '';        // 标题输入框内容（AI 草稿自动填充，可自由编辑）
  @Local knowledgeSuggestedTags: string[] = [];  // ★ 0.202.1：AI 建议标签（弹窗勾选采纳）
  @Local knowledgeSelectedTags: string = '';     // ★ 0.202.1：已勾选标签（逗号分隔，随卡保存）
  @Local knowledgeCardDefinition: string = '';   // 定义输入框内容（AI 草稿自动填充，可自由编辑）
   @Local knowledgeImageUri: string = '';         // 卡片配图（base64 data URI；'' = 无图片，图片区不渲染）
   @Local knowledgeEditLoading: boolean = false;  // AI 提炼进行中
   @Local knowledgeEditError: string = '';        // AI 提炼错误信息（输入框仍可手动填写）
  // ★ 0.272.0：提炼 SP 透明化——token 用量与 SP 行文本（信息卡数据源；弹窗右下角、完成即现）
  @Local knowledgeEditInTok: number = 0;
  @Local knowledgeEditOutTok: number = 0;
  @Local knowledgeEditSpText: string = '';
   // ★ 0.222.22：知识卡入库目标文件夹选择弹窗（点「保存入库」弹出；UI 与知识库移动/复制弹窗同款）
   @Local cardFolderPickerVisible: boolean = false;
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
   // ★ 0.251.0：0.153「切后台中断提炼」@Monitor 已随后台保活策略整体反转删除
   //   （appLifecycle 字段与 import 一并清理）——AI 请求由 ApiClient 层 AiStreamGuard
   //   长时任务保活续收，切后台不再断流（用户拍板，全案 docs/0.165+/0.251.0）
  // ★ 0.160：弹窗内复习区——AI 提炼等待期顺便学习（词库 N 词 + 知识库 M 卡，N/M 由 ⚙ 设置驱动）；
  // 弹窗打开时抽一次固定（渲染不重抽、不闪烁），样式与气泡底部复习区一致
  @Local editReviewWords: WordItem[] = [];

  // ★ 0.187.0：复习评分交互状态——key = `${messageId}|${wordId}`（气泡区）/ `edit|${wordId}`（提炼弹窗）
  @Local reviewExpandKey: string = '';                    // 当前展开评分按钮的词条（空 = 无）
  @Local reviewRatedMap: Map<string, string> = new Map(); // 已评分词条 key → 评分（hard/good/easy；整体替换触发 V2 刷新）
  // ★ 0.224.0：司忆区卡面模式（全局单通道跟随——双面模式释义/定义行隐藏，点词条展开=翻面出答案+评分按钮；
  //   @Local 接管 @ObservedV2 实例——0.221.4 铁律，直读字段勿走 @Computed 间接链）
  @Local faceMode: FaceModeStore = connectFaceMode();
  @Local editReviewCards: KnowledgeCard[] = [];
  // ★ 0.282.0：播客模式入口下线（用户拍板「所有一切都正常对话」，想清楚了再加回）——
  //   发送恒为正常对话；历史播客消息的 isPodcastMode 字段保留，兼容渲染与重生成。
  // ★ 0.144：回复长度下拉（'short' | 'medium' | 'long'，默认中回复；仅内存状态，重启恢复默认）
  @Local replyLengthMode: string = 'medium';
  @Local webMode: string = 'auto'; // ★ 0.292.0 联网问答（FC 工具循环；会话态不持久化）；★ 0.300.0 两态化：'auto'=AI 自主（枢机恒挂 tools 自己决定+单段关键词预路由命中才挂）/ 'force'=强制挂（Bing 抽风手动兜底）——禁止决策负担丢给用户（产品军令 5）
  // ★ 0.151-D：⋮ 三点气泡菜单开关（合并原模式下拉 0.133 + 长度下拉 0.144 两个面板为一棵树形菜单）
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
  // ★ 0.285.5：文本模式——整表渲染为一个 Text（行间 \n、格间 ' | '），可整体划词（翻译/入知识库/
  //   引用/复制/系统 Ctrl+C 全链路）；格子架构选区不跨组件，跨格/整表划选唯一落点在此
  @Local tableZoomTextMode: boolean = false;
  // ★ 0.150：全局设置弹窗状态（顶栏 ⚙ 唤起；遮罩不关闭，✕/返回键走弹窗内未保存确认）
      // ★ 0.133：语音朗读状态（全局单播放源，驱动喇叭图标三态）
  @Local playingMessageId: string = '';    // 正在播放的消息 ID（🔊 态）
  // ★ 0.287.6：消息朗读态驱动喇叭动画——loading/playing 任一非空即登记动画源，双空注销
  // （@Monitor 覆盖所有清空路径：点击停止/删除消息/播完回调，比在 startTTS/stopTTS 插调用更稳）
  @Monitor('playingMessageId', 'ttsLoadingMessageId')
  onTtsAnimStateChange(): void {
    if (this.playingMessageId.length > 0 || this.ttsLoadingMessageId.length > 0) {
      speakerPulse.begin('msg');
    } else {
      speakerPulse.end('msg');
    }
  }
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
  // ★ 0.280.0：「回到底部」悬浮钮可见性——onScrollIndex 检测视口末尾未到最后一条消息（用户上滑看历史）时置 true，
  //   滚回底部（含发送新消息 scrollEdge 自动滚底）回调 end=lastIndex 置 false
  @Local showScrollToBottom: boolean = false;
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
      return this.theme.codeKeyword; // 关键字：蓝
    }
    if (kind === 2) {
      return this.theme.codeString; // 字符串：绿
    }
    if (kind === 3) {
      return this.theme.codeComment; // 注释：灰
    }
    if (kind === 4) {
      return this.theme.codeNumber; // 数字：橙
    }
    return this.theme.codeText;   // 普通代码文本
  }

  // ★ 0.153：打开表格放大弹窗（换行模式重置为 false，与气泡内表格默认一致）
  openTableZoom(header: string[], rows: string[][]): void {
    this.tableZoomHeader = header;
    this.tableZoomRows = rows;
    this.tableZoomWrap = false;
    this.tableZoomTextMode = false; // ★ 0.285.5：每次打开重置文本模式（默认格子视图）
    this.tableZoomVisible = true;
  }

  // V2 @Computed：从 store 读取当前气泡 ID，自动响应式
  @Computed
  get currentBubbleId(): string {
    return this.currentBubbleStore.nodeID;
  }

  // ★ 0.265.0 记忆引擎一期：画像观察行 store + 注入埋点 store + 用户消息轮次计数
  //   （每 8 轮用户消息触发一次画像更新——fire-and-forget 隐式调用，静默降级不阻断对话）
  profileStore: ProfileStore = connectProfileObservations();
  memStats: MemoryInjectStatsStore = connectMemoryInjectStats();
  profileTick: number = 0;
  memoryPrefStore = connectMemoryPref(); // WP5 深度记忆总开关（关闭=不注入不触发，数据保留）

  // ★ 0.265.0：画像更新触发（每 8 轮/会话结束；深度记忆关或降频时内部静默跳过）
  triggerProfileUpdate(): void {
    const b = this.currentBubble;
    if (b === undefined) {
      return;
    }
    updateProfileFromConversation(this.profileStore, this.apiConfig, b.nodeID, b.messages);
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

  // ============================================================
  // ★ 0.234.0 注意力锚点 + 长文分章折叠：渲染管线（任务书 §5.2）
  // 消息 → parseMarkdown 段落 → FoldItem 流（文本块/锚点/代码/表格）→
  //   [锚点开] insertLocalAnchors（breath 保底）→ 平铺按段重组（流式直显）+ 章节切分（完成收拢）
  // ============================================================

  // 锚点相关设置指纹（缓存失效依据：密度变化即全量重算）
  // ★ 0.290.0：anchorMode 三态随 GSD 锚点卡 UI 隐藏退役——恒开（恒 companion 语义），指纹只留密度
  anchorFingerprint(): string {
    return `on_${this.anchorPref.anchorDensity}_on`;
  }

  // ★ 0.290.0：锚点恒开（GSD 设置 UI 已隐藏、恒定值 companion——钩子升级为结构性信息恒渲染；
  //   锚点关=降级普通文本行的旧分支保留在 RichBlockView，仅历史遗留路径不再触达）
  anchorsEnabled(): boolean {
    return true;
  }

  // 消息渲染计划（缓存：content 长度+首 16 字符 + 设置指纹三键失效；播客消息不插锚点——听播零改动）
  richPlanFor(msg: ChatMessage): RichPlan {
    const isPlaceholder = msg.content === PLACEHOLDER_LOADING || msg.content === PLACEHOLDER_THINKING;
    const fp = this.anchorFingerprint();
    const head = msg.content.substring(0, 16);
    const cached = this.planCache.get(msg.messageId);
    if (!isPlaceholder && cached !== undefined && cached.len === msg.content.length && cached.head === head && cached.fingerprint === fp) {
      return cached.plan;
    }
    const plan = new RichPlan();
    if (!isPlaceholder && msg.content.trim().length > 0) {
      const segs = parseMarkdown(msg.content);
      let items = buildFoldItems(segs);
      if (this.anchorsEnabled() && !msg.isPodcastMode) {
        items = insertLocalAnchors(items, breathThreshold(this.anchorPref.anchorDensity));
      }
      // 平铺重组：按段收集 text/anchor 条目（breath 已按段归属——只在文本块后插，代码/表格段恒无块）
      const bySeg: MdBlock[][] = [];
      for (let i = 0; i < items.length; i++) {
        const blk = items[i].block;
        if (blk !== null) {
          while (bySeg.length <= items[i].segIdx) {
            bySeg.push([]);
          }
          bySeg[items[i].segIdx].push(blk);
        }
      }
      for (let si = 0; si < segs.length; si++) {
        const entry = new RichPlanEntry();
        entry.seg = segs[si];
        entry.blocks = si < bySeg.length ? bySeg[si] : [];
        plan.entries.push(entry);
      }
      // 章节切分（同一条目流，不再重算）
      plan.sections = splitFoldSections(items);
      plan.sectionable = initExpandedSet(plan.sections) !== null;
    }
    if (this.planCache.size > 40) {
      this.planCache.clear(); // 防膨胀（气泡切换后旧消息计划不再消费）
    }
    const entry = new PlanCacheEntry();
    entry.len = msg.content.length;
    entry.head = head;
    entry.fingerprint = fp;
    entry.plan = plan;
    this.planCache.set(msg.messageId, entry);
    return plan;
  }

  // 折叠视图启用判定：非流式中 + 非播客 + AI 消息 + ≥3 节（任务书 §2.2 门槛）
  // ★ 0.290.0：分章折叠恒开（GSD 设置 UI 隐藏、恒定值 on）——不再读 foldMode
  useFoldView(msg: ChatMessage): boolean {
    if (msg.role !== 'assistant' || msg.isPodcastMode) {
      return false;
    }
    if (msg.messageId === this.streamingMsgId ||
      msg.content === PLACEHOLDER_LOADING || msg.content === PLACEHOLDER_THINKING) {
      return false;
    }
    return this.richPlanFor(msg).sectionable;
  }

  // 当前展开集：用户态优先（chatFoldMemory 视图），无记录=默认前 1/3 + 开篇（initExpandedSet）
  expandedSetFor(msgId: string, sections: FoldSection[]): Set<number> {
    const saved = this.foldStateView.get(msgId);
    if (saved !== undefined) {
      return saved;
    }
    const def = initExpandedSet(sections);
    return def !== null ? def : new Set<number>();
  }

  // 折叠行点击 toggle（220ms 开合动画；状态双写 @Local 视图 + 模块级记忆）
  toggleFoldSection(msgId: string, sections: FoldSection[], si: number): void {
    const apply = (): void => {
      const store = new Map(this.foldStateView);
      let set = store.get(msgId);
      if (set === undefined) {
        const def = initExpandedSet(sections);
        set = def !== null ? def : new Set<number>();
      }
      const next = new Set<number>(set);
      if (next.has(si)) {
        next.delete(si);
      } else {
        next.add(si);
      }
      store.set(msgId, next);
      this.foldStateView = store;
      chatFoldMemory.set(msgId, next);
    };
    if (animOn) {
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, apply);
    } else {
      apply();
    }
  }

  // 锚点徽标文案（★ 0.237.0 六档映射——钩子树砍2留2加3；禁止 emoji）
  // ★ 0.269.0 钩子体系四类：breath=歇口气 / digest=简单说 / bait=延伸
  // ★ 0.290.0（WP4）：progress 类全链砍除（PLAN_PROMPT 类型清单不含、本地保底模板删、渲染分支删）；
  //   钩子终态四类 digest/breath/quiz/bait；旧五类（quiz/hook/rephrase/predict/recap）保留于单段式中回复
  anchorBadge(type: string): string {
    if (type === 'quiz') {
      return '考考你';
    }
    if (type === 'hook') {
      return '前方高能';
    }
    if (type === 'rephrase') {
      return '换个说法';
    }
    if (type === 'predict') {
      return '先猜再看';
    }
    if (type === 'recap') {
      return '一句话锁住';
    }
    if (type === 'breath') {
      return '歇口气';
    }
    if (type === 'bait') {
      return '延伸';
    }
    return '简单说'; // digest（兜底同徽标——progress 已绝迹）
  }

  // 锚点卡片浮现动画（淡入+上移 8vp+200ms；ForEach key 稳定 → 每卡只播一次）
  anchorTransition(): TransitionEffect {
    return TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 })).animation({ duration: 200 });
  }

  @Builder
  MdInlineSpans(lines: string[], fontSize: number) {
    ForEach(lines, (line: string, lsi: number) => {
      ForEach(parseInlineMd(line), (sp: MdSpan, _si: number) => {
        if (sp.strike) {
          Span(sp.text)
            .fontSize(this.fs(fontSize))
            .decoration({ type: TextDecorationType.LineThrough })
        } else if (sp.link) {
          Span(sp.text)
            .fontSize(this.fs(fontSize))
            .fontColor(this.theme.brandSecondary)
            .decoration({ type: TextDecorationType.Underline, color: this.theme.brandSecondary })
        } else if (sp.code) {
          Span(sp.text)
            .fontSize(this.fs(fontSize - 1))
            .fontColor(this.theme.codeText)
            .fontFamily('monospace')
        } else if (sp.bold && sp.italic) {
          Span(sp.text)
            .fontSize(this.fs(fontSize))
            .fontWeight(600)
            .fontStyle(FontStyle.Italic)
        } else if (sp.bold) {
          Span(sp.text)
            .fontSize(this.fs(fontSize))
            .fontWeight(600)
            .textBackgroundStyle({ color: glowHighlight ? 'rgba(124,77,255,0.12)' : Color.Transparent, radius: glowHighlight ? 2 : 0 }) // ★ 0.237.0 术语荧光底（12% 品牌紫底——治「一大片白」；heading 走品牌色文字不加底，避免叠加；glowHighlight 一键回退纯加粗）
        } else if (sp.italic) {
          Span(sp.text)
            .fontSize(this.fs(fontSize))
            .fontStyle(FontStyle.Italic)
        } else {
          Span(sp.text)
            .fontSize(this.fs(fontSize))
        }
      }, (sp: MdSpan, si: number) => `${lsi}_${si}_${sp.text.length}_${sp.bold ? 1 : 0}${sp.italic ? 1 : 0}${sp.strike ? 1 : 0}${sp.code ? 1 : 0}${sp.link ? 1 : 0}`)
      if (lsi < lines.length - 1) {
        Span('\n')
          .fontSize(this.fs(fontSize))
      }
    }, (line: string, lsi: number) => `${lsi}_${line.length}`)
  }

  // ★ 0.237.0：h1~h6 标题块判定（'hr' 排除——同为 h 开头两字符但非标题）
  isHeadingKind(kind: string): boolean {
    return kind.length === 2 && kind.charAt(0) === 'h' && kind.charAt(1) >= '1' && kind.charAt(1) <= '6';
  }

  // ★ 0.302.2：块级间距分级（原所有块统一 Column space:4 无层次——段落/列表/标题差异化，
  //   豆包式「段落呼吸感」；与父 Column space 叠加生效，两处消费点（平铺/折叠章节）同源）
  blockMargin(blk: MdBlock): Margin {
    if (this.isHeadingKind(blk.kind)) {
      return { top: 12, bottom: 2 }; // 标题前留大空隙、后紧跟正文
    }
    if (blk.kind === 'li' || blk.kind === 'oli') {
      return { bottom: 2 }; // 列表项紧凑成组
    }
    if (blk.kind === 'quote') {
      return { top: 2, bottom: 4 };
    }
    if (blk.kind === 'hr') {
      return { top: 6, bottom: 6 };
    }
    return { bottom: 4 }; // 段落（p/兜底）
  }

  // 单块 Text：统一挂划词工具栏四件套（选择菜单/选中回调/全选受控/可复制）
  @Builder
  MdBlockText(blk: MdBlock, selKey: string, fontSize: number) {
    Text('', { controller: this.getOrCreateTextController(selKey) }) {
      if (blk.kind === 'li') {
        Span(listMarker(blk.depth)) // ★ 0.302.2：分层符号（• / ◦ / ▪，与 blockRenderedText 同源）
          .fontSize(this.fs(fontSize))
          .fontColor(this.theme.textTertiary)
      } else if (blk.kind === 'oli') {
        Span(blk.order + ' ')
          .fontSize(this.fs(fontSize))
          .fontColor(this.theme.textTertiary)
      } else if (this.isHeadingKind(blk.kind)) {
        Span(headingIcon(blk.kind)) // ★ 0.302.2：标题 emoji 图标（h1 📌 / h2 🔹 / h3 🔸；h4+ 空）
          .fontSize(this.fs(fontSize))
      }
      this.MdInlineSpans(blk.lines, fontSize)
    }
      .fontSize(this.fs(fontSize))
      .letterSpacing(this.fs(0.3)) // ★ 0.302.2：字距微松（豆包观感；字体走系统 HarmonyOS Sans）
      .lineHeight(this.fs(Math.round(fontSize * BODY_LINE_HEIGHT_RATIO)))
      .fontColor(this.isHeadingKind(blk.kind) ? this.theme.brandSecondary : (blk.kind === 'quote' ? this.theme.textSecondary : this.theme.textPrimary)) // ★ 0.237.0 文章小标题品牌色（整条染色不拆编号——AI 编号格式不统一，拆解有误伤风险）
      .fontWeight(this.isHeadingKind(blk.kind) ? 600 : 400)
      .copyOption(CopyOptions.LocalDevice)
      .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE) // ★ 0.285.3：可获焦模式（华为二轮正解）——Text 默认 UNFOCUSABLE 划选后不获焦、系统 Ctrl+C 派发给错误组件；本模式点击/划选即入获焦链，系统默认复制直接生效
      .focusOnTouch(true) // ★ 0.285.4：拖选起手 press 即申请焦点——textSelectable 只给获焦能力、拖选本身不改焦点归属（华为 Q2），获焦后系统 Ctrl+C 才作用于其选区
      .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, this.isPcDevice() ? TextResponseType.RIGHT_CLICK : TextResponseType.SELECT, {
        onAppear: () => {
          this.selKey = selKey;
        },
        onDisappear: () => {
          this.clearSelectionState();
        }
      })
      .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, TextResponseType.LONG_PRESS, {
        onAppear: () => {
          this.selKey = selKey;
        },
        onDisappear: () => {
          this.clearSelectionState();
        }
      })
      .onTextSelectionChange((start: number, end: number) => {
        // ★ 0.237.1：取词基准=渲染态文本（前缀+剥行内标记）——选区偏移按渲染 Span 序列计，
        //   用 blockPlainText（原始行含 **）会整体前移选错词
        this.handleSelectionChange(selKey, blockRenderedText(blk), start, end);
      })
      .selection(
        this.selectAllKey.startsWith(selKey + '|') ? 0 : 1,
        this.selectAllKey.startsWith(selKey + '|') ? blockRenderedText(blk).length : 0
      )
      .margin(this.blockMargin(blk)) // ★ 0.302.2：块级间距分级（段落 4 / 列表 2 / 标题前 12 / 引用 2·4 / 分隔线 6）
  }

  // ★ 0.290.0（WP4）：锚点卡纯胶囊形态 A（用户拍板喜欢「标签页」式样）——仅保留紫底白字
  //   胶囊单一视觉元素（徽标+文案合一入胶囊），删除左竖线与 8% 底色层，禁止徽标+描述双行叠加；
  //   ★ 本轮：胶囊不再单行截断——文案完整展开自动换行（用户拍板「不要点点点」），
  //   去掉 maxLines(1)/Ellipsis/maxWidth 40%/flexShrink(0) 三连；短文案仍自适应短胶囊、
  //   长文案撑满行宽自然折行；bait「→ 拉分支深挖」移胶囊下方独立一行（胶囊可占满整行）；
  //   breath/digest/quiz 零点击；浮现动画保留（淡入+上移，每卡只播一次）；形态 B 留档未实施。
  @Builder
  AnchorCard(blk: MdBlock) {
    Column({ space: 4 }) {
      Text(`${this.anchorBadge(blk.anchorType)} · ${blk.anchorText}`)
        .fontSize(this.fs(11))
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White) // 白字白图铁律：恒白允许——实色品牌底（brandPrimary）上
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(14)
        .backgroundColor(this.theme.brandPrimary)
      if (blk.anchorType === 'bait') {
        Text('→ 拉分支深挖')
          .fontSize(this.fs(12))
          .fontColor(this.theme.brandSecondary)
          .maxLines(1)
          .onClick(() => {
            // ★ 0.269.0 Q8：点击=创建子气泡+预填引子问题（待用户发送，不自动发）
            this.addBubble([], `关于「${blk.anchorText}」这一点，请展开深入讲讲`, '');
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 2, right: 8, top: 4, bottom: 4 })
    .transition(this.anchorTransition())
  }

  // 单块分发（平铺富文本段与折叠章节条目共用）——锚点竖线块/分割线/引用/列表缩进/标题字号
  // ★ 0.269.0：锚点渲染统一竖线块（中回复/长回复一套代码两种密度——Q7 裁决）
  @Builder
  RichBlockView(blk: MdBlock, keyBase: string) {
    if (blk.kind === 'anchor') {
      if (this.anchorsEnabled()) {
        this.AnchorCard(blk)
      } else {
        // 锚点关=无卡片：降级普通文本行（文案保留——「关闭后 AI 按原文回复」）
        this.MdBlockText(blk, keyBase, 15.5)
      }
    } else if (blk.kind === 'hr') {
      Divider()
        .strokeWidth(0.5)
        .color(this.theme.strokeCard)
        .margin({ top: 6, bottom: 6 }) // ★ 0.302.2：分隔线上下留白加大（原 2/2 贴字）
    } else if (blk.kind === 'quote') {
      Column() {
        this.MdBlockText(blk, keyBase, 15.5)
      }
      .border({ width: { left: 3 }, color: { left: this.theme.brandSecondary } })
      .padding({ left: 10 })
      .alignItems(HorizontalAlign.Start)
    } else if (blk.kind === 'li' || blk.kind === 'oli') {
      Column() {
        this.MdBlockText(blk, keyBase, 16)
      }
      .margin({ left: blk.depth * 14 })
      .alignItems(HorizontalAlign.Start)
    } else if (blk.kind === 'h1' || blk.kind === 'h2' || blk.kind === 'h3' ||
      blk.kind === 'h4' || blk.kind === 'h5' || blk.kind === 'h6') {
      this.MdBlockText(blk, keyBase, headerFontSize(blk.kind))
    } else {
      this.MdBlockText(blk, keyBase, 16)
    }
  }

  // 富文本段总入口：逐块分发（★ 0.234.0：改收预构建 blocks——锚点块/breath 保底已在 richPlanFor 注入）
  @Builder
  MdRichSegment(blocks: MdBlock[], keyBase: string) {
    Column({ space: 4 }) {
      ForEach(blocks, (blk: MdBlock, bi: number) => {
        this.RichBlockView(blk, `${keyBase}|b${bi}`)
      }, (blk: MdBlock, bi: number) => blk.kind === 'anchor'
        ? `a${bi}_${blk.anchorType}_${blk.anchorText}` // ★ 0.234.0：锚点卡 key 内容化——流式重解析不重播浮现动画
        : `${bi}_${blk.kind}_${blk.order}_${blk.depth}_${blk.lines.length}_${blockPlainText(blk).length}`)
    }
    .alignItems(HorizontalAlign.Start)
  }

  // ★ 0.234.0：表格渲染（自 0.153 段内联代码整段提取——平铺段与折叠章节共用；
  //   keyBase 形如 `${msgId}|t${idx}`（平铺）/ `${msgId}|f${si}i${ii}t`（折叠），格位 key 语义不变）
  @Builder
  TableBlockView(header: string[], rows: string[][], keyBase: string) {
    Column() {
      // 左上角放大按钮（zoom.svg 矢量图标 + 深紫底方框圆角；20×18/图标14）
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
      .backgroundColor(this.theme.surfaceHover)
      .border({ width: 0.5, color: this.theme.strokeBrand })
      .margin({ top: 4, bottom: 2 })
      .onClick(() => {
        this.openTableZoom(header, rows);
      })

      // 表格主体：横向滚动 + 固定列宽（各行边界严格对齐）
      Scroll() {
        Column() {
          // 表头行
          Row() {
            ForEach(header, (cell: string, ci: number) => {
              // 划词五件套 + 划词级书签（命中本格拆 Span，划选文字紫色+下划线）
              Text('', { controller: this.getOrCreateTextController(`${keyBase}h${ci}`) }) {
                if (this.isBookmarkAt(`${keyBase}h${ci}`) && this.bmStart() >= 0 && this.bmEnd() > this.bmStart() && this.bmEnd() <= cell.length) {
                  Span(cell.substring(0, this.bmStart()))
                  Span(cell.substring(this.bmStart(), this.bmEnd()))
                    .fontColor(this.theme.brandSecondary)
                    .decoration({ type: TextDecorationType.Underline, color: this.theme.brandSecondary })
                  Span(cell.substring(this.bmEnd()))
                } else {
                  Span(cell)
                }
              }
                .fontSize(this.fs(14))
                .fontColor(this.theme.textPrimary)
                .padding(8)
                .border({ width: 0.5, color: this.theme.strokeCard })
                .width(this.getTableColWidths(header, rows)[ci])
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .textAlign(TextAlign.Center)
                .copyOption(CopyOptions.LocalDevice)
                .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE) // ★ 0.285.3：可获焦模式（华为二轮正解）——Text 默认 UNFOCUSABLE 划选后不获焦、系统 Ctrl+C 派发给错误组件；本模式点击/划选即入获焦链，系统默认复制直接生效
                .focusOnTouch(true) // ★ 0.285.4：拖选起手 press 即申请焦点——textSelectable 只给获焦能力、拖选本身不改焦点归属（华为 Q2），获焦后系统 Ctrl+C 才作用于其选区
                .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, this.isPcDevice() ? TextResponseType.RIGHT_CLICK : TextResponseType.SELECT, {
                  onAppear: () => {
                    this.selKey = `${keyBase}h${ci}`;
                  },
                  onDisappear: () => {
                    this.clearSelectionState();
                  }
                })
                .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, TextResponseType.LONG_PRESS, {
                  onAppear: () => {
                    this.selKey = `${keyBase}h${ci}`;
                  },
                  onDisappear: () => {
                    this.clearSelectionState();
                  }
                })
                .onTextSelectionChange((start: number, end: number) => {
                  this.handleSelectionChange(`${keyBase}h${ci}`, cell, start, end);
                })
                .selection(
                  this.selectAllKey.startsWith(`${keyBase}h${ci}|`) ? 0 : 1,
                  this.selectAllKey.startsWith(`${keyBase}h${ci}|`) ? cell.length : 0
                )
            }, (cell: string, ci: number) => `h_${ci}_${cell.length}_${cell.substring(0, 4)}`)
          }
          // 数据行
          ForEach(rows, (row: string[], ri: number) => {
            Row() {
              ForEach(row, (cell: string, ci: number) => {
                Text('', { controller: this.getOrCreateTextController(`${keyBase}r${ri}c${ci}`) }) {
                  if (this.isBookmarkAt(`${keyBase}r${ri}c${ci}`) && this.bmStart() >= 0 && this.bmEnd() > this.bmStart() && this.bmEnd() <= cell.length) {
                    Span(cell.substring(0, this.bmStart()))
                    Span(cell.substring(this.bmStart(), this.bmEnd()))
                      .fontColor(this.theme.brandSecondary)
                      .decoration({ type: TextDecorationType.Underline, color: this.theme.brandSecondary })
                    Span(cell.substring(this.bmEnd()))
                  } else {
                    Span(cell)
                  }
                }
                  .fontSize(this.fs(14))
                  .fontColor(this.theme.textSecondary)
                  .padding(8)
                  .border({ width: 0.5, color: this.theme.strokeCard })
                  .width(this.getTableColWidths(header, rows)[ci])
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center)
                  .copyOption(CopyOptions.LocalDevice)
                  .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE) // ★ 0.285.3：可获焦模式（华为二轮正解）——Text 默认 UNFOCUSABLE 划选后不获焦、系统 Ctrl+C 派发给错误组件；本模式点击/划选即入获焦链，系统默认复制直接生效
                  .focusOnTouch(true) // ★ 0.285.4：拖选起手 press 即申请焦点——textSelectable 只给获焦能力、拖选本身不改焦点归属（华为 Q2），获焦后系统 Ctrl+C 才作用于其选区
                  .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, this.isPcDevice() ? TextResponseType.RIGHT_CLICK : TextResponseType.SELECT, {
                    onAppear: () => {
                      this.selKey = `${keyBase}r${ri}c${ci}`;
                    },
                    onDisappear: () => {
                      this.clearSelectionState();
                    }
                  })
                  .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, TextResponseType.LONG_PRESS, {
                    onAppear: () => {
                      this.selKey = `${keyBase}r${ri}c${ci}`;
                    },
                    onDisappear: () => {
                      this.clearSelectionState();
                    }
                  })
                  .onTextSelectionChange((start: number, end: number) => {
                    this.handleSelectionChange(`${keyBase}r${ri}c${ci}`, cell, start, end);
                  })
                  .selection(
                    this.selectAllKey.startsWith(`${keyBase}r${ri}c${ci}|`) ? 0 : 1,
                    this.selectAllKey.startsWith(`${keyBase}r${ri}c${ci}|`) ? cell.length : 0
                  )
              }, (cell: string, ci: number) => `r_${ri}_${ci}_${cell.length}_${cell.substring(0, 4)}`)
            }
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

  // ★ 0.235.1：折叠行——整行可点 toggle（收起态整行卡片）：章节标题(14fp，完整呈现可换行——禁截断省略号，
  //   0.235.1 用户拍板：「标题一定要呈现完整，哪怕两行三行」) + 右「约 X 字」(11fp/this.theme.textSecondary)；
  //   「第 X 节」序号已删——AI 生成 MD 的 ## 标题自带 123 序号，UI 再加前缀=把标题拆开还挤占窄屏宽度（0.235.1）；
  //   无 ## 兜底段显示「第 X 段 · 约 Y 字」（任务书 §2.3，兜底段无标题、序号是唯一标识故保留）
  // ★ 0.235.2：三角统一术卡样式 → ★ 0.237.0 军令 SVG 终式：字符字形（▼/▶/▸/▾）在系统字体下宽高粗细
  //   天然不一致且随字体漂移，根治=全项目唯一折叠指示器 FoldChevron（同一颗 chevron SVG 旋转两态：
  //   收起 0° 指右 / 展开 90° 指下，220ms EaseInOut——UI_GUIDELINES §13）
  // ★ 0.237.0：去「共 N 节」（用户拍板）——右侧只留「约 X 字」；「≥3 节才折叠」门槛逻辑不受影响
  @Builder
  FoldRow(msg: ChatMessage, sections: FoldSection[], sec: FoldSection, si: number) {
    Row({ space: 6 }) {
      FoldChevron({ expanded: this.expandedSetFor(msg.messageId, sections).has(si) })
      if (sec.numbered) {
        Text(sec.title)
          .fontSize(14)
          .fontColor(this.theme.textPrimary)
          .layoutWeight(1)
        Text(`约 ${sec.charCount} 字`)
          .fontSize(11)
          .fontColor(this.theme.textSecondary)
      } else {
        Text(`第 ${sec.order} 段`)
          .fontSize(14)
          .fontColor(this.theme.textPrimary)
        Blank()
        Text(`约 ${sec.charCount} 字`)
          .fontSize(11)
          .fontColor(this.theme.textSecondary)
      }
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 9, bottom: 9 })
    .margin({ top: 2, bottom: 2 })
    .borderRadius(RADIUS_CONTROL)
    .backgroundColor(this.theme.surfaceSoft)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.toggleFoldSection(msg.messageId, sections, si);
    })
  }

  // ★ 0.234.0：章节条目渲染——文本块走 RichBlockView、锚点卡、代码块、表格（折叠态与平铺同源）
  @Builder
  SectionItems(sec: FoldSection, keyBase: string) {
    ForEach(sec.items, (item: FoldItem, ii: number) => {
      if (item.kind === 'anchor' && item.block !== null) {
        if (this.anchorPref.anchorMode === 'on') {
          this.AnchorCard(item.block)
        } else {
          this.MdBlockText(item.block, `${keyBase}i${ii}`, 15.5)
        }
      } else if (item.kind === 'code') {
        CodeBlockView({
          content: item.code,
          lang: item.lang,
          fontScale: this.fontScale,
          onZoom: (content: string, lang: string) => { this.openCodeZoom(content, lang); },
          textKey: `${keyBase}i${ii}c`,
          selController: this.getOrCreateTextController(`${keyBase}i${ii}c`),
          selectAllKey: this.selectAllKey,
          bmStart: -1,
          bmEnd: -1,
          bookmarkBtnLabel: this.bookmarkBtnLabel(),
          onBookmark: () => { this.onToolbarBookmark(); },
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
      } else if (item.kind === 'table') {
        this.TableBlockView(item.header, item.rows, `${keyBase}i${ii}t`)
      } else {
        if (item.block !== null) {
          this.RichBlockView(item.block, `${keyBase}i${ii}`)
        }
      }
    }, (item: FoldItem, ii: number) => {
      let seed = `${ii}_${item.kind}`;
      if (item.block !== null) {
        // 锚点卡 key 内容化——同 MdRichSegment（每卡只播一次浮现动画）
        seed += item.block.kind === 'anchor' ? `_${item.block.anchorType}_${item.block.anchorText}` : `_${blockPlainText(item.block).length}`;
      } else if (item.kind === 'code') {
        seed += `_${item.code.length}`;
      } else {
        seed += `_${item.header.length}_${item.rows.length}`;
      }
      return seed;
    })
  }

  // ★ 0.234.0：折叠视图总入口——开篇引言恒展开无折叠行；其余按展开集渲染折叠行(+/−)章节体；
  //   key 纳入节 index 与展开态（0.231.0 Key 碰撞教训）；章节开合 220ms 过渡
  @Builder
  FoldedMessageView(msg: ChatMessage, sections: FoldSection[]) {
    Column({ space: 4 }) {
      ForEach(sections, (sec: FoldSection, si: number) => {
        if (sec.order === 0) {
          // 开篇引言（第 0 节）：默认恒展开、不占章节序号、无折叠行
          Column({ space: 4 }) {
            this.SectionItems(sec, `${msg.messageId}|f${si}`)
          }
          .alignItems(HorizontalAlign.Start)
        } else {
          Column({ space: 4 }) {
            this.FoldRow(msg, sections, sec, si)
            if (this.expandedSetFor(msg.messageId, sections).has(si)) {
              Column({ space: 4 }) {
                this.SectionItems(sec, `${msg.messageId}|f${si}`)
              }
              .alignItems(HorizontalAlign.Start)
              .transition(TransitionEffect.OPACITY.animation({ duration: animOn ? 220 : 0 }))
            }
          }
          .alignItems(HorizontalAlign.Start)
        }
      }, (sec: FoldSection, si: number) => `${si}_${sec.order}_${sec.title}_${sec.charCount}_${this.expandedSetFor(msg.messageId, sections).has(si) ? 1 : 0}`)
    }
    .alignItems(HorizontalAlign.Start)
  }

  // ★ 0.234.0：章节总数（order>0 的节/段——≥3 折叠门槛口径；0.237.0 起「共 N 节」展示已删，
  //   本方法保留供门槛语义与后续消费——任务书 §三：只删展示文本不删函数）
  numberedSectionCount(sections: FoldSection[]): number {
    let n = 0;
    for (let i = 0; i < sections.length; i++) {
      if (sections[i].order > 0) {
        n++;
      }
    }
    return n;
  }

  // ★ 新增：调用 LLM 生成摘要（0.117）
  // ★ 0.193.0 A 项：摘要 prompt 结构化升级（SUMMARY_PROMPT 五部分清单——用户问题逐条枚举/核心概念/已推导结论/关键约定/当前进度），
  //   学习 Claude Code 9 部分压缩清单；摘要质量=分支继承的记忆质量
  // ★ 0.265.0 WP3：摘要问题感知升级——SUMMARY_PROMPT 增第六部分（与本问题相关的信息优先保留），
  //   摘要调用入参带上当前 pending 问题（空串=无问题上下文，行为同旧版）
  async generateSummaryWithLLM(messages: ChatMessage[], pendingQuestion: string = ''): Promise<string> {
    return new Promise((resolve, reject) => {
      const q = pendingQuestion.trim();
      const sysText = q.length > 0 ? `${SUMMARY_PROMPT}\n\n本轮用户问题：${q}` : SUMMARY_PROMPT;
      const summaryMessages: ChatMessage[] = [
        new ChatMessage(generateMessageId(), 'system', sysText),
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

  // ★ 0.265.0 WP1/WP2/WP4：记忆上下文统一注入出口——buildBranchMessageList 两出口（未超线全量/超线摘要+保留窗）
  //   返回前统一过此函数；深度记忆关闭时原样返回（回到纯父链模式，数据保留）。
  //   注入顺序（任务书定案）：[画像卡(最前部), 历史摘要(超线时), 相关分支背景(树距离衰减), ...路径消息]；
  //   WP4 分段埋点：画像段/路径段/摘要头段/历史摘要段各自估算 token 落 memory-inject-stats-v1（14 天滚动）。
  injectMemoryContext(base: ChatMessage[], node: BubbleNode, summaryTok: number): ChatMessage[] {
    if (!isMemoryOn()) {
      return base; // WP5 总开关关：零注入零埋点，行为与旧版完全一致
    }
    const result: ChatMessage[] = [...base];
    const profileCard = buildCardView(this.profileStore);
    let profileTok = 0;
    if (profileCard.length > 0) {
      profileTok = memoryTokenEstimate(profileCard);
      result.unshift(new ChatMessage(generateMessageId(), 'system', profileCard)); // 画像卡插最前部
    }
    const headsText = buildSiblingHeadsContext(this.store, node);
    let headsTok = 0;
    if (headsText.length > 0) {
      headsTok = memoryTokenEstimate(headsText);
      // 摘要头插在历史摘要消息之后、当前路径消息之前（无历史摘要则紧随画像卡）
      let insertAt = 0;
      if (profileCard.length > 0) {
        insertAt = 1;
      }
      if (insertAt < result.length && result[insertAt].role === 'system' &&
        result[insertAt].content.startsWith('【历史摘要】')) {
        insertAt += 1; // 历史摘要之后
      }
      result.splice(insertAt, 0, new ChatMessage(generateMessageId(), 'system', headsText));
    }
    // WP4 路径段 token（注入前 base 的合计——路径消息全量口径）
    let pathTok = 0;
    for (let i = 0; i < base.length; i++) {
      pathTok += memoryTokenEstimate(base[i].content);
    }
    recordMemoryInjectStats(this.memStats, profileTok, pathTok, headsTok, summaryTok);
    return result;
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
          if (msg.role === 'assistant') {
            // ★ 0.234.0：AI 消息送 LLM 前剔除锚点标记整行（防标记污染摘要与后续上下文——任务书 §5.4；
            //   content 原文不动，仅上下文副本清洗）
            const clean = stripAnchorMarks(msg.content, false);
            if (clean.trim().length > 0) {
              allMessages.push(new ChatMessage(msg.messageId, msg.role, clean, msg.imageUrl,
                msg.inputTokens, msg.outputTokens, msg.isPodcastMode, msg.model));
            }
          } else {
            allMessages.push(msg);
          }
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
      return this.injectMemoryContext(allMessages, currentNode, 0); // ★ 0.265.0：统一注入出口（无历史摘要段）
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
        // ★ 0.265.0 WP3：摘要调用带上当前 pending 问题（当前节点尾部最后一条用户消息——问题感知优先保留）
        let pendingQ = '';
        for (let i = currentNode.messages.length - 1; i >= 0; i--) {
          if (currentNode.messages[i].role === 'user' && currentNode.messages[i].content.trim().length > 0) {
            pendingQ = currentNode.messages[i].content;
            break;
          }
        }
        const summary = await this.generateSummaryWithLLM(toSummarize, pendingQ);
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
    // ★ 0.265.0：统一注入出口（画像卡最前部 + 相关分支背景插历史摘要之后；WP4 分段埋点）
    return this.injectMemoryContext([summaryMsg, ...recentMessages], currentNode,
      memoryTokenEstimate(summaryMsg.content));
  }

  // ★ 0.191.0：流式请求阶段（等待态一行提示——用户核心诉求：干等难受，必须告知当前在哪一步）
  // 0=无 1=已提交请求（点发送/刷新瞬间） 2=等待服务器返回（思考模型思考阶段——锅甩给服务器，用户知道不是自己设备的问题）
  // 3=整理历史记忆中（★ 0.199.0：上下文超 48K 触发线时的摘要生成期间，一次完整 LLM 调用 5~15s，平时不出现）
  // 4=正在读取网页（★ 0.286.0：消息含链接时的网页抓取期间，最多 2 页 × 12s 超时，平时不出现）
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
   ctrlVPasting: boolean = false; // ★ 0.275.0：Ctrl+V 读剪贴板防重入（异步期间重复按键忽略）
   dragImageOver: boolean = false; // ★ 0.275.0：图片拖入输入卡高亮态（onDragEnter/Leave/Drop 三点维护）
  // ★ 0.270.0 输入区聚焦扩展（千问式）：聚焦态驱动输入框 minHeight 40→76 展开两行高 + 卡片内下方
  //   工具栏浮现；blur 走 150ms 宽限收起——PC 发送后 50ms 重聚焦（0.216.2）落在窗内 → 工具栏不闪，
  //   点工具栏按钮的焦点转移同样受保护（宽限内重新聚焦则不收）
  @Local isInputFocused: boolean = false;
  inputBlurTimer: number = -1; // blur 宽限定时器句柄（aboutToDisappear 必清，防泄漏）
  // ★ 0.281.4：键盘高度自控让位（用户真机实锤 0.281.2 的 RESIZE 在 NavDestination 里没生效，
  //   输入卡下半截仍被软键盘盖住）——onShown 设 KeyboardAvoidMode.NONE + 监听 keyboardHeightChange，
  //   根容器 paddingBottom=键盘高度（vp），输入大框/标签层/声明行整体贴键盘上沿；onHidden 恢复默认
  @Local kbAvoidHeight: number = 0;
  private kbAvoidWin: window.Window | null = null;
  private kbAvoidCallback: ((h: number) => void) | null = null;

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
      Text(this.streamPhase === 4 ? '正在读取网页' // ★ 0.286.0：阶段 4——消息含链接时的网页抓取期间（无省略号，遵循 0.191.0 定稿）
        : this.streamPhase === 7 ? '正在联网搜索' // ★ 0.292.0：阶段 7——联网工具循环 search_web 执行期间
        : this.streamPhase === 8 ? '正在打开网页' // ★ 0.292.0：阶段 8——联网工具循环 open_url 抓取期间
        : this.streamPhase === 9 ? '御史审核中（交付质检）' // ★ 0.300.0：阶段 9——司枢 3.0 御史审核期间
        : this.streamPhase === 10 ? '发现瑕疵，重写中' // ★ 0.300.0：阶段 10——御史打回按意见重写期间
        : this.streamPhase === 6 ? '正在解析文档' // ★ 0.291.2：阶段 6——带文档发送时的文档解析期间（本地直读/腾讯云 Submit+轮询）
        : this.streamPhase === 5 ? (this.classicStore.classic ? '正在搭建回答框架' : '枢机规划中') // ★ 0.290.0 阶段 5；★ 0.300.0 司枢 3.0=枢机（契约+任务类型判定，工具轮也在此态）
        : this.streamPhase === 3 ? '整理历史记忆中' // ★ 0.199.0：阶段 3——上下文压缩摘要生成期间（无省略号，遵循 0.191.0 定稿：三点动画已表达进行中）
        : this.streamPhase === 1 ? (this.thinkingEnabledNow ? '已提交请求 · 深度思考' : '已提交请求') // ★ 0.271.0：思考档生效加后缀（计费透明——SP 预估行任务书 §3.8）
        : this.streamPhase === 2 ? (this.thinkingEnabledNow ? '深度思考中' : '等待服务器返回') // ★ 0.271.0：三阶段状态行「深度思考中→生成正文→编排阅读节奏」首段
        : 'AI 正在回复')
        .fontSize(14)
        .fontColor(this.theme.textSecondary)
        .maxLines(1)
        .margin({ left: 8 })
      // ★ 0.300.0 SP 分阶段实时透明（产品军令 3：成本透明替代封顶——枢机/工具/执笔/御史逐轮累计；
      //   仅流水线阶段展示，常规单段链路沿用完成态感叹号明细，不重复打扰）
      if (this.sishuSpPreview.length > 0 && this.streamPhase >= 5) {
        Text(`· 已耗约 ${this.sishuSpPreview} SP`)
          .fontSize(12)
          .fontColor(this.theme.textTertiary)
          .maxLines(1)
          .margin({ left: 4 })
      }
      // ★ 0.282.0：仅开启深度思考（长回复）时显示模式段；中回复=默认不啰嗦（0.190.7 口径延续）
      if (this.replyLengthMode === 'long') {
        Text('· 深度思考')
          .fontSize(12)
          .fontColor(this.theme.textTertiary)
          .maxLines(1)
          .margin({ left: 4 })
      }
    }
    .width('100%')
  }

  // ★ 0.271.0：思考卡（任务书 §3.4——秒表图标+计时 Ns+思维链滚动摘要前 120 字；浅紫 8% 底 hookBg；
  //   超 10s 追加「取消」=取消本条请求（技术上无法只停思考不停正文，与现有停止同款）；
  //   视觉语言分族：思考卡=浅紫底 / 钩子卡=左侧竖线（0.269.0），两种辅助块禁混用）
  @Builder
  thinkingCard() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Image($r('app.media.timer'))
          .width(14)
          .height(14)
          .objectFit(ImageFit.Contain)
        Text(`深度思考中 ${this.thinkingElapsed}s`)
          .fontSize(13)
          .fontColor(this.theme.brandSecondary)
          .maxLines(1)
          .layoutWeight(1)
        if (this.thinkingElapsed >= 10) {
          Text('取消')
            .fontSize(12)
            .fontColor(this.theme.textTertiary)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .onClick(() => {
              if (this.streamController) {
                this.streamController.cancel();
                this.streamController = null;
              }
              this.isLoading = false;
              this.streamPhase = 0;
              this.streamingMsgId = '';
              if (this.thinkingActiveMsgId.length > 0) {
                this.finishThinkingTrace(this.thinkingActiveMsgId);
              }
            })
        }
      }
      .width('100%')
      if (this.thinkingHeadText.length > 0) {
        Text(this.thinkingHeadText)
          .fontSize(11)
          .lineHeight(17)
          .fontColor(this.theme.textTertiary)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Start)
      }
    }
    .width('100%')
    .padding(10)
    .borderRadius(RADIUS_CONTROL)
    .backgroundColor(this.theme.hookBg)
    .margin({ top: 6 })
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

  // ★ 0.244.0：流式写穿——云同步 reconcile 会在会话期整体替换 store.nodeList（refreshWorkspaceFromPools，
  //   按池 JSON 反序列化出全新对象）。流式回调若捕获的是被替换的旧消息对象，后续写入只进孤儿对象：
  //   界面冻结在替换瞬间、onDone saveTree 落盘残缺内容（用户实测「返回父气泡内容像被重新生成」家族
  //   根因之一）。每片/收尾把内容同步写回 store 当前对象（按 nodeID+messageId 定位），流尾零丢失。
  mirrorStreamToLive(bubbleId: string, msg: ChatMessage): void {
    const live = this.store.nodeList.find((n: BubbleNode) => n.nodeID === bubbleId);
    if (live === undefined) {
      return; // 气泡真没了（对端删除）——孤儿写入无害放弃
    }
    const liveMsg = live.messages.find((m: ChatMessage) => m.messageId === msg.messageId);
    if (liveMsg !== undefined && liveMsg !== msg) {
      liveMsg.content = msg.content;
      liveMsg.inputTokens = msg.inputTokens;
      liveMsg.outputTokens = msg.outputTokens;
    }
  }

  async sendMessage(): Promise<void> { // ★ 改为 async（0.117）
    this.cancelPlanning('new'); // ★ 0.290.0：发新消息自动取消进行中①段（非阻塞，不挡发送）
    this.streamGen += 1; // ★ 0.300.0：任务代际+1（反问挂起链路恢复后核对——被顶替则静默死亡）
    this.abandonClarify(); // ★ 0.300.0：新消息顶替反问挂起（旧链路静默中断，反问卡收起）
    // ★ 0.300.0：北极星最强负信号 sishu_reask（任务书 §七）——上一条 AI 消息属司枢任务且本轮
    //   输入命中「不对/不是我要的/我要的是」类重问语气 → 记一次同话题重问
    const reaskBubble = this.currentBubble;
    if (reaskBubble !== null && reaskBubble !== undefined && this.inputText.length > 0
      && /(不对|不是我要的|我要的是|不是这个|弄错了|说错了|重新|再问一次)/.test(this.inputText)) {
      const prev = reaskBubble.messages;
      for (let i = prev.length - 1; i >= 0; i--) {
        if (prev[i].role === 'assistant') {
          const pc = this.contractByMsg.get(prev[i].messageId);
          if (pc !== undefined) {
            const rk: Record<string, string> = {};
            rk['taskType'] = pc.taskType;
            track(this.getUIContext().getHostContext() as common.Context, 'sishu_reask', rk);
          }
          break; // 只看最近一条 AI 消息
        }
      }
    }
    // ★ 0.190.4：卡死自愈（须在 guard 前）——isLoading=true 但 streamController=null 是异常态
    //   （正常流两者同步设置/清除；真机实测超时出错后偶发卡此态，guard 挡死后续所有发送
    //   「发送不出去」），检测到即强制恢复放行，用户永远不会再被卡死
    if (this.isLoading && this.streamController === null) {
      this.isLoading = false;
    }
    // ★ 0.248.2：AI 登录守卫（上架合规最高优先——未登录发消息拦截 + 引导登录；置于一切 guard 之前）
    if (!connectHuaweiAccount().isLoggedIn) {
      connectConfirmDialog().aiLoginPromptVisible = true;
      return;
    }
    // ★ 0.293.0：SP 云同步门卫（SiyiGate——账本云端未对齐禁用 AI：防未开同步设备本地小金库白嫖，
    //   引导弹窗按阻塞原因分支：登录/一键开启/跳系统云空间）
    if (!requireSiyiGate()) {
      return;
    }
    // ★ 0.248.7：SP 余额闸门（实扣链路上线——余额为 0 拦截发送并引导充能；余额>0 放行，
    //   单次消耗远小于余额不做预估拦截，回复完成按实扣、不足扣到 0 为止）
    //   ★ 0.249.0：Lv8 司忆令「SP 永久免费」豁免（用户拍板真免扣——免扣账号余额 0 照常发送）
    if (!this.spFree() && siyiTotalSp(this.siyiStore) <= 0) {
      connectConfirmDialog().spRechargePromptVisible = true;
      return;
    }
    if ((!this.inputText.trim() && this.pendingImages.length === 0 && this.pendingDocs.length === 0) || !this.currentBubble || this.isLoading) {
      return;
    }
    // ★ 0.250.0：敏感词本地预过滤（输入侧兜底初筛——命中即本地拦截不出网，主防线=平台侧过滤；
    //   埋点只报类别不报词内容，隐私红线）
    const inputHit: FilterHit | null = ContentFilter.checkInput(this.inputText);
    if (inputHit !== null) {
      const _fh: Record<string, string> = {}; _fh['cat'] = inputHit.category;
      track(this.getUIContext().getHostContext() as common.Context, 'filter_input_hit', _fh);
      this.showToastSafe('消息包含违规内容，已停止发送，请修改后重试');
      return;
    }
  const _tp1: Record<string, string> = {}; _tp1['mode'] = this.replyLengthMode;
    track(this.getUIContext().getHostContext() as common.Context, 'send_message', _tp1); // 0.206.0 埋点：发送（含模式）
    // ★ 0.190.2：纯文本模型发图拦截（用户批准方案）——预设清单已知纯文本 + 本次发送含图
    //   → 弹窗提醒切换多模态；多模态/自定义/清单外 ID 能力未知不拦截（等对方报错走关键词提示）
    if (this.pendingImages.length > 0 && isKnownTextOnlyModel(this.apiConfig.provider, this.apiConfig.model)) {
      const proceed = await this.confirmSendImageToTextModel();
      if (!proceed) {
        return;
      }
    }
    // ★ 0.291.2：文档双提醒（用户拍板）——①云端格式超 2MB 强确认（页费可能高，取消=待发区保留）；
    //   ②冷启后首次带文档发送弹计费告知（此后发送即视为同意）。解析失败零扣费在注入块如实列明。
    if (this.pendingDocs.length > 0) {
      let bigName = '';
      for (let i = 0; i < this.pendingDocs.length; i++) {
        const d = this.pendingDocs[i];
        if (needsCloudParse(d.ext) && d.size > DOC_CONFIRM_BYTES) {
          bigName = d.name;
          break;
        }
      }
      if (bigName.length > 0) {
        const okBig = await this.confirmBigDocParse(bigName);
        if (!okBig) {
          return;
        }
      }
      if (!this.docBillingNotified) {
        this.docBillingNotified = true;
        this.getUIContext().showAlertDialog({
          title: '文档计费说明',
          message: '发送文档时，docx/PDF 由腾讯云文档解析服务处理（约 0.04 元/页，将折算并入本次输入 SP 消耗一并展示与扣除）；txt/md/xlsx 本地解析不产生解析费。解析失败不收取任何费用。文档内容仅随本次请求发送，不会存入历史。',
          confirm: {
            value: '知道了',
            action: () => {
            }
          }
        });
      }
    }
    if (this.streamController) {
      this.streamController.cancel();
    }
    const isPodcast: boolean = false; // ★ 0.282.0：播客入口下线，恒正常对话
    // ★ 0.271.0：深度思考策略解析（任务书 §3.1 矩阵——听播强制关 / GSD off 全关 / 短关 /
    //   中回复加权计分 / 长回复 high；S3 计数=发送时刻本气泡已有 AI 消息数，不含本次新建）
    const bubbleForThink = this.currentBubble;
    const aiCountForThink = bubbleForThink !== null
      ? bubbleForThink.messages.filter((m: ChatMessage): boolean => m.role === 'assistant').length : 0;
    const topicForThink = bubbleForThink !== null && bubbleForThink.topicTags.length > 0
      ? bubbleForThink.topicTags.join('、') : '';
    // ★ 0.300.0：解除联网×深度思考互斥（前置验证①实锤——腾讯云 TokenHub DeepSeek-Flash
    //   tools+thinking 同请求三组全 200；当年一刀切互斥的根因就是没验证，本版纠正）
    // ★ 0.300.0：联网两态+本地预路由（任务书 §三.1——'force' 强制挂 / 'auto' 单段链路
    //   关键词宽匹配命中才挂（宁可多挂漏挂=场景整个失效）；司枢链路恒挂由枢机自主）
    const webPrerouteHit: boolean = this.webMode === 'force' || WEB_PREROUTE_RE.test(this.inputText);
    const webOn: boolean = webPrerouteHit; // 单段直写链路挂 tools 依据（司枢链路独立恒挂）
    const webOffReq: ThinkingRequest = { enabled: false, effort: '' };
    const thinkingReq: ThinkingRequest = resolveThinkingFor('auto', // ★ 0.290.0：深度思考三态随 GSD UI 隐藏恒 auto（司枢开=长回复恒 high）；★ 0.300.0 删 webOn 强制关（兼容已验证）
      this.replyLengthMode, isPodcast, this.inputText, topicForThink, aiCountForThink);
    this.thinkingEnabledNow = thinkingReq.enabled;
    if (thinkingReq.enabled) {
      completeRookieTask('use_sishu'); // ★ 0.294.0：新手任务①司枢模式——发送时刻思考档生效即算使用一次
    }
    const userMsg = new ChatMessage(generateMessageId(), 'user', this.inputText, [...this.pendingImages], 0, 0, isPodcast); // ★ 0.133：标记播客模式
    // ★ 0.202.0：注意力提取——消息命中卡标题/标签 → 标签热度+1（纯本地毫秒级；AI 还在流式回复时复习权重已算完）
    updateAttention(this.attention, this.knowledgeBank.cards, userMsg.content);
    recordStat(this.statStore, 'userMsg', 0, 0); // ★ 0.192.0：统计埋点——用户消息 +1（只增不减，删除不影响）
    this.profileTick += 1; // ★ 0.265.0 WP1：画像更新轮次计数（每 8 轮触发一次隐式画像观察）
    if (this.profileTick >= 8) {
      this.profileTick = 0;
      this.triggerProfileUpdate(); // fire-and-forget（静默降级，不阻塞发送链路）
    }
    const aiMsg = new ChatMessage(generateMessageId(), 'assistant', PLACEHOLDER_LOADING, [], 0, 0, isPodcast); // ★ 0.132：占位常量；★ 0.133：标记播客模式
    aiMsg.model = this.apiConfig.model; // ★ 0.224.3：请求发出时打标模型 ID（操作行显示——用户跨模型对比"这个漂亮回复是哪个模型的"）
    // ★ 0.268.0：AI 智慧排序预触发（fire-and-forget——任务书 Q2 终裁：发送瞬间问题+话题标签
    //   已齐备，无需等 AI 回复；AI 回复完成渲染司忆区时消费结果，多数场景已就绪=零闪烁）。
    //   重排输入=问题文本+topicTags（空则 summaryHead 兜底——Q5 终裁，两家一致否决用户画像）；
    //   候选池=两库本地全序前 20（候选 <4/无 key/超 20 次日限在引擎内部静默终止）；
    //   单条气泡只触发 1 次（messageId 幂等），换一批复用不重调。
    if (this.currentBubble !== null && this.currentBubble !== undefined) {
      const rb = this.currentBubble;
      const rerankTopics = rb.topicTags.length > 0 ? rb.topicTags.join('、') : rb.summaryHead;
      triggerAiRerank(aiMsg.messageId, userMsg.content, rerankTopics,
        orderedReviewWords(this.wordBank, Date.now()),
        orderedReviewCards(this.knowledgeBank, Date.now()),
        this.apiConfig,
        (): void => { this.onRerankBatchReady(aiMsg.messageId); },
        (): void => { this.onRerankBatchReady(aiMsg.messageId); });
    }
    this.currentBubble.messages = [...this.currentBubble.messages, userMsg, aiMsg];
    this.saveTree(); // ★ 0.151：按模式分池保存
    this.inputText = '';
    this.imeComposing = false; // ★ 0.287.2：发送清空后占位恢复显示
    this.pendingImages = [];
    const docsToSend: PendingDoc[] = [...this.pendingDocs]; // ★ 0.291.2：发送时刻快照（解析在下文注入块消费；此处清待发区）
    this.pendingDocs = [];
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
    this.streamingMsgId = aiMsg.messageId; // ★ 0.234.0：流式直显标记（该消息完成前不折叠）
    const streamBubbleId = this.currentBubbleId; // ★ 0.244.0：流式写穿定位键（发送时刻的气泡 ID）

    // 构建发送给 API 的消息列表：剔除空 content 的占位 AI 消息
    // ★ 替换为链路回溯 + 压缩（0.117）
    const messagesToSend = await this.buildBranchMessageList(this.currentBubble);

    // ★ 0.235.0：划词引用注入——引用块只拼进本次请求的上下文副本（气泡原文/持久化/后续轮次不动，
    //   引用=一次性消费）；buildBranchMessageList 保底含最新一条 user 消息，从尾部找它替换为带引用块的副本
    if (this.quoteText.length > 0) {
      for (let i = messagesToSend.length - 1; i >= 0; i--) {
        if (messagesToSend[i].role === 'user') {
          const m = messagesToSend[i];
          messagesToSend[i] = new ChatMessage(m.messageId, 'user',
            `【用户引用了以下内容，请重点围绕这段内容回答】\n${this.quoteText}\n【引用内容结束】\n\n${m.content}`,
            m.imageUrl, m.inputTokens, m.outputTokens, m.isPodcastMode, m.model);
          break;
        }
      }
      this.quoteText = ''; // 发送后引用栏清空（一次性消费）
    }

    // ★ 0.286.0：AI 读网页一期——消息含 http/https 链接时，从设备直接抓取网页正文，以 system
    //   消息一次性拼进本次请求副本（复刻 0.235.0 划词引用模式：气泡原文/持久化/Schema 零改动）；
    //   失败不阻断发送（块内列明失败原因，模型不瞎编）；正文已过 ContentFilter、截断 6000 字符、
    //   最多 2 个链接（WebFetchUtil 内双闸，防 token 爆炸多扣 SP）
    if (detectWebUrls(userMsg.content).length > 0) {
      this.streamPhase = 4; // 抓取期间独立等待态（最多 2 页 × 15s——壳页走 Web 渲染更长）
      let webSummary: WebFetchSummary;
      try {
        // ★ 0.286.1：传渲染通道——静态抓到壳（<300 字，SPA 文档站）时隐形 Web 组件真渲染重取
        webSummary = await fetchWebContextForMessage(userMsg.content,
          (url: string): Promise<string> => this.renderUrlViaWeb(url));
      } catch (_we) {
        webSummary = { block: '', okCount: 0, failCount: 0 }; // 全链兜底：异常不阻断发送
      } finally {
        this.streamPhase = 1; // 恢复阶段 1（成败都继续，请求即将真正发出）
      }
      if (webSummary.block.length > 0) {
        messagesToSend.push(new ChatMessage(generateMessageId(), 'system', webSummary.block));
        if (webSummary.okCount > 0) {
          this.showToastSafe(`已读取 ${webSummary.okCount} 个网页，AI 将结合网页内容回答`);
        } else {
          this.showToastSafe('网页读取失败，AI 将按原文回答');
        }
      }
    }

    // ★ 0.291.2：文档加载注入（复刻 0.286 读网页同款一次性 system 副本——气泡原文/持久化/
    //   Schema 零改动；重生成/历史不带文档内容=既定先例语义）。解析失败不阻断发送（块内列明
    //   失败原因，模型不瞎编）；页费嫁接=页数折算等效 input token（ChatModel.docPageTokens），
    //   onDone 落账并入 inputTokens——展示与扣费同源军令天然满足，失败文档 pages=0 零扣费。
    let docExtraInTok = 0;
    if (docsToSend.length > 0) {
      this.streamPhase = 6; // 解析期间独立等待态（本地毫秒级/云端轮询分钟级）
      let docResults: DocParseResult[] = [];
      try {
        docResults = await parseDocsForSend(docsToSend, this.apiConfig.docSecretId, this.apiConfig.docSecretKey,
          (this.getUIContext().getHostContext() as common.Context).cacheDir);
      } catch (_de) {
        docResults = []; // 全链兜底：异常不阻断发送
      } finally {
        this.streamPhase = 1; // 恢复阶段 1（成败都继续，请求即将真正发出）
      }
      let docOk = 0;
      let docTrunc = 0; // ★ 0.291.3：超长截断文档数（计费透明——页费按全文页数计）
      for (let i = 0; i < docResults.length; i++) {
        if (docResults[i].ok) {
          docOk += 1;
          if (docResults[i].truncated) {
            docTrunc += 1;
          }
        }
        docExtraInTok += docPageTokens(docResults[i].pages);
      }
      const docBlock = buildDocContextBlock(docResults);
      if (docBlock.length > 0) {
        messagesToSend.push(new ChatMessage(generateMessageId(), 'system', docBlock));
      }
      if (docOk > 0) {
        const failPart = docResults.length - docOk > 0 ? `，${docResults.length - docOk} 个失败` : '';
        if (docTrunc > 0) { // ★ 0.291.3：截断=钱相关，10 秒顶格长 toast 必须看清
          this.showToastLong(`已解析 ${docOk} 个文档${failPart}；${docTrunc} 个超长已截断至 3 万字，页费仍按全文页数计，AI 将结合内容回答`);
        } else {
          this.showToastSafe(`已解析 ${docOk} 个文档${failPart}，AI 将结合内容回答`);
        }
      } else {
        this.showToastSafe('文档解析失败，AI 将按消息原文回答');
      }
    }

    // ★ 0.290.0（司枢 2.0）：长回复（司枢模式开）走框架先行两段式——长度裁定权前移到①段规划器，
    //   不再注入 LONG_REPLY_PROMPT（fallback 直写时动态补注）；中回复单段链路照旧注入 MEDIUM。
    //   prefPrompt 两段式下不进①段（防称呼指令污染框架 JSON）——②段执笔组装时追加。
    // ★ 0.300.0：删 !webOn 互斥（司枢+联网组合=枢机带工具轮，任务书 §三.1）；经典模式灰度分流
    const siyuMode = this.replyLengthMode === 'long' && !isPodcast;
    const useSishu3 = siyuMode && !this.classicStore.classic; // ★ 0.300.0：3.0 三角色流水线（默认）；classic=true 走旧 2.0 两段式
    const prefPrompt = this.buildPreferencePrompt(isPodcast);
    if (!siyuMode) {
      if (this.replyLengthMode === 'long') {
        messagesToSend.push(new ChatMessage(generateMessageId(), 'system', LONG_REPLY_PROMPT)); // 播客历史长回复重生成兼容（0.282 后常态不触达）
      } else {
        messagesToSend.push(new ChatMessage(generateMessageId(), 'system', MEDIUM_REPLY_PROMPT));
      }
      if (prefPrompt.length > 0) {
        messagesToSend.push(new ChatMessage(generateMessageId(), 'system', prefPrompt));
      }
    }

    // ★ 0.282.0：播客入口下线——不再注入播客 prompt（历史播客消息重生成仍按 isPodcastMode 兼容）

    // ★ 0.217.0 端侧大模型全线回滚（个人开发者白名单不通过=企业限定，0.216.0~0.216.2 时代终结）

    // ★ 0.271.0：流式调用包装为可降级重发的局部函数（§3.6——自动降级=400+关键词窄门，
    //   同上下文同消息以 disabled 原样重发一次；单次发送尝试只降一次，手动重试=新尝试）
    // ★ 0.290.0（司枢 2.0）：startStream 泛化为直写流（中回复/司枢 fallback/②段执笔三用）——
    //   extraMsgs=尾部动态追加的 system（fallback=[LONG,SECTION,pref]；②段=[writePrompt,SECTION,pref]）；
    //   planIn/Out/Cached=①段规划 token 暂存（两段累加一次性落账军令）；activeFrame≠null 时
    //   ②段 onDone 渲染期合成钩子（mergeSectionHooks 节号制，Q6 钩子隔离）。
    // ★ 0.292.0：联网工具循环状态（FC agentic loop；与 planInTok 同级——多轮 token 累加一次性落账军令）
    let webInTok = 0;
    let webOutTok = 0;
    let webCachedTok = 0;
    let webRound = 0;
    let webDowngraded = false;
    let curWebToolsOn = false;
    const toolAppendixAcc: Object[] = [];
    const webTools: Object[] = (webOn || siyuMode) ? buildWebToolsSchema() : []; // 工具定义（每条消息构造一次；★ 0.300.0 司枢链路恒构建——枢机自主决定调不调）
    const isWebToolParamError = (raw: string): boolean => {
      const lower = raw.toLowerCase();
      const toolWord = lower.includes('tool') || lower.includes('function call');
      const paramWord = lower.includes('400') || lower.includes('invalid') ||
        lower.includes('not support') || lower.includes('unsupported');
      return toolWord && paramWord;
    };
    // onToolCalls：执行工具（search_web=Bing 解析 / open_url=单 URL 两级瀑布）→ 结果回填 → 递归下一轮；
    //   到 WEB_MAX_TOOL_ROUNDS 上限后不再声明 tools 强制落笔；用户已取消（isLoading=false）则中断递归
    // ★ 0.300.0：工具轮统一改造——执行体抽 execToolRound（单段链路/司枢枢机链路共用），
    //   递归目标由 nextRecall 注入；新增防死循环护栏（openedUrls 查重+连续空轮计数——防 bug 非省 SP）
    const openedUrls = new Set<string>();
    let emptyToolRounds = 0;
    const execToolRound = (calls: ToolCallResult[], inTok: number, outTok: number, cachedTok: number,
      appendixAcc: Object[], nextRecall: (toolsStillOn: boolean) => void, roundLimit: number): void => {
      webInTok += inTok;
      webOutTok += outTok;
      webCachedTok += cachedTok;
      webRound += 1;
      this.updateSishuSpPreview(0, 0, 0, planInTok + webInTok, planOutTok + webOutTok, planCachedTok + webCachedTok); // ★ 0.300.0 SP 透明：工具轮逐轮累计
      const execTools = async (): Promise<void> => {
        const results: string[] = [];
        let anyUseful = false; // 护栏信号：本轮是否有任一成功结果
        for (let i = 0; i < calls.length; i++) {
          const c = calls[i];
          let arg1 = '';
          try {
            const args = JSON.parse(c.argumentsJson) as Record<string, Object>;
            if (c.name === 'search_web') {
              arg1 = typeof args['query'] === 'string' ? args['query'] as string : '';
            } else if (c.name === 'open_url') {
              arg1 = typeof args['url'] === 'string' ? args['url'] as string : '';
            }
          } catch (_pe) {
            arg1 = '';
          }
          if (c.name === 'search_web') {
            this.streamPhase = 7; // 正在联网搜索
            if (arg1.length === 0) {
              results.push('（search_web 参数缺失或格式错误，未执行）');
              continue;
            }
            try {
              const hits = await searchWeb(arg1);
              if (hits.length > 0) {
                anyUseful = true;
              }
              results.push(`【联网搜索：${arg1}】\n${formatSearchResults(hits)}`);
            } catch (se) {
              const reason = se instanceof Error ? se.message : '未知原因';
              results.push(`【联网搜索：${arg1}】\n（搜索失败：${reason}。请基于已有资料回答，不要编造搜索结果）`);
            }
          } else if (c.name === 'open_url') {
            this.streamPhase = 8; // 正在打开网页
            if (arg1.length === 0 || arg1.indexOf('http') !== 0) {
              results.push('（open_url 参数缺失或不是 http/https 链接，未执行）');
              continue;
            }
            if (openedUrls.has(arg1)) { // ★ 0.300.0 护栏：重复打开同一 URL（枢机死循环典型症状）
              results.push(`【已打开网页：${arg1}】\n（该网页本轮已读取过，请勿重复打开；请基于已有资料继续）`);
              continue;
            }
            openedUrls.add(arg1);
            const item = await fetchSingleUrlReadable(arg1,
              (u: string): Promise<string> => this.renderUrlViaWeb(u));
            if (item.ok) {
              anyUseful = true;
              results.push(`【已打开网页：${arg1}】\n${item.content}`);
            } else {
              results.push(`【已打开网页：${arg1}】\n（读取失败：${item.content}。不要编造该网页内容）`);
            }
          } else {
            results.push(`（未知工具 ${c.name}，未执行）`);
          }
        }
        const roundMsgs: Object[] = buildToolRoundMessages(calls, results);
        for (let i = 0; i < roundMsgs.length; i++) {
          appendixAcc.push(roundMsgs[i]);
        }
        emptyToolRounds = anyUseful ? 0 : emptyToolRounds + 1; // 连续空轮累计（防死循环）
        const limitReached = webRound >= roundLimit || emptyToolRounds >= ORCH_EMPTY_ROUNDS_LIMIT;
        this.streamPhase = 1; // 恢复等待态（下一轮流即将发出）
        if (!this.isLoading) {
          return; // 用户已取消：不再递归（取消语义与现有链路一致）
        }
        nextRecall(!limitReached);
      };
      execTools();
    };
    // ★ 0.292.0 单段链路薄包装：工具轮后递归 startStream（原 handleToolCalls 语义零变化）
    const handleToolCalls = (calls: ToolCallResult[], inTok: number, outTok: number, cachedTok: number): void => {
      execToolRound(calls, inTok, outTok, cachedTok, toolAppendixAcc,
        (toolsOn: boolean): void => {
          startStream(webOffReq, [], toolAppendixAcc, toolsOn);
        }, WEB_MAX_TOOL_ROUNDS);
    };
    let downgraded = false; // 降级防循环锚（降级请求本身 disabled 不可能再触发参数型降级，天然无循环）
    let contentStarted = false; // ★ 0.271.0：乱序防护——phase3（正文已开始）之后到达的 reasoning 分片一律丢弃
    let planInTok = 0;
    let planOutTok = 0;
    let planCachedTok = 0;
    let activeFrame: PlanFrame | null = null;
    // ★ 0.300.0（司枢 3.0）：三角色流水线暂存——deliver 族 token 累加器（执笔可能多轮：初稿+
    //   打回重写）/御史 token/审核轮次/契约存档；全部一次性并入 finalizeStream 落账
    //   （军令延续：凡 AI 交互必扣必展示——多轮 token 累加一次性实扣；过程透明走 sishuSpPreview）
    let deliverInTok = 0;
    let deliverOutTok = 0;
    let deliverCachedTok = 0;
    let deliverReasonTok = 0;
    let censorInTok = 0;
    let censorOutTok = 0;
    let censorCachedTok = 0;
    let censorRoundsDone = 0; // 已完成审核次数（0=未审/99=终态通过；交付型最多 2 次审核=1 轮打回）
    let deliverMode = false;  // 交付型链路标志（onDone 分流进御史轮）
    let activeContract: TaskContract | null = null;
    let userClarifiedText = '';    // 反问卡答案文本（buildDeliverPrompt userClarified 参）
    let lastCensorComments = '';   // 最近一轮御史意见（打回重写注入）
    let deliverWriteThink: ThinkingRequest = webOffReq; // 交付执笔思考档（continueWrite 定档）
    // ★ 0.300.0：落账收口——plan+web+deliver+censor+docPage 全并账（onDone 终点/审核通过/降级三点共用）
    const finalizeStream = (lastInTok: number, lastOutTok: number, lastCachedTok: number, lastReasonTok: number,
      thinkReqFin: ThinkingRequest): void => {
      this.isLoading = false;
      this.streamController = null;
      this.streamPhase = 0; // ★ 0.191.0：阶段复位
      this.censorBadge = '';
      this.sishuSpPreview = '';
      // ★ 0.290.0：两段 token 累加一次性落账（军令：①规划+②执笔合并计入消息统计，SP 实扣同源）
      // ★ 0.291.2：文档页费嫁接并入；★ 0.300.0：deliver/censor（多轮）并入
      aiMsg.inputTokens = lastInTok + planInTok + docExtraInTok + webInTok + deliverInTok + censorInTok;
      aiMsg.outputTokens = lastOutTok + planOutTok + webOutTok + deliverOutTok + censorOutTok;
      aiMsg.cacheHitTokens = lastCachedTok + planCachedTok + webCachedTok + deliverCachedTok + censorCachedTok;
      aiMsg.reasoningTokens = lastReasonTok + deliverReasonTok;
      const mergedIn = aiMsg.inputTokens;
      const mergedOut = aiMsg.outputTokens;
      const mergedCached = aiMsg.cacheHitTokens;
      const thinkDur = this.thinkingSecondsByMsg.get(aiMsg.messageId) ?? 0;
      const thinkChars = this.thinkingTraceByMsg.get(aiMsg.messageId)?.length ?? 0;
      if (!this.spFree()) { // ★ 0.249.0：Lv8 司忆令 SP 永久免费——免扣账号跳过实扣
        const _bal0 = siyiTotalSp(this.siyiStore); // ★ 0.260.0：实扣前后余额差=本行实扣额（consumeSiyiSp 不足 clamp 到 0）
        consumeSiyiSp(this.siyiStore, this.spCostOf(aiMsg)); // ★ 0.248.7：回复完成实扣 SP（先嘉奖后充能；不足扣到 0）
        this.trackSpConsume(aiMsg, false, _bal0 - siyiTotalSp(this.siyiStore), mergedIn, mergedCached, 'chat', mergedOut); // ★ 0.260.0；★ 0.273.0 补 ot；★ 0.290.0 合并口径；★ 0.300.0 三角色全并
        // ★ 0.271.0：thinking_use 埋点（sp=本条实扣；思考生效但零思考 token=网关静默忽略 degraded）
        this.trackThinkingUse(!thinkReqFin.enabled ? 'off' : (lastReasonTok + deliverReasonTok > 0 ? (downgraded ? 'auto_downgrade' : 'use') : 'degrade'),
          this.replyLengthMode, thinkReqFin.effort, thinkDur, thinkChars, _bal0 - siyiTotalSp(this.siyiStore));
      } else {
        this.trackSpConsume(aiMsg, true, 0, mergedIn, mergedCached, 'chat', mergedOut); // ★ 0.260.0：免扣照报 f:y（成本红线要真实 token/命中/余额）；★ 0.273.0 补 ot；★ 0.290.0 合并口径
        this.trackThinkingUse(!thinkReqFin.enabled ? 'off' : (lastReasonTok + deliverReasonTok > 0 ? (downgraded ? 'auto_downgrade' : 'use') : 'degrade'),
          this.replyLengthMode, thinkReqFin.effort, thinkDur, thinkChars, 0);
      }
      // ★ 0.300.0：任务级 SP 埋点（北极星 sishu_task_cost——按类型分桶）
      if (activeContract !== null) {
        const tc: Record<string, string> = {};
        tc['taskType'] = activeContract.taskType;
        tc['form'] = activeContract.form;
        tc['sp'] = `${Math.round(this.spCostOf(aiMsg))}`;
        tc['tools'] = activeContract.usedTools ? '1' : '0';
        tc['censor'] = censorRoundsDone > 90 ? (lastCensorComments.length > 0 ? '2' : '1') : '0'; // 终态折算：打回过=2 审/直通=1 审/未审=0
        track(this.getUIContext().getHostContext() as common.Context, 'sishu_task_cost', tc);
        // 交付型终态=交付卡出现（@Local 数组整体重赋值触发渲染）
        if (activeContract.form === 'deliverable') {
          this.deliverMsgIds = [...this.deliverMsgIds, aiMsg.messageId];
        }
      }
      // ★ 0.290.0：渲染期钩子合成（merged 态）——框架 hooks 按 afterSection 节号插入（Q6 钩子隔离：
      //   ②段写劈叉不影响钩子结构；合成失败=原文返回零风险）；fallback（activeFrame=null）跳过，
      //   渲染层 insertLocalAnchors 的 breath 保底自动兜住；★ 0.300.0 交付型零钩子（activeFrame=null）
      if (activeFrame !== null && aiMsg.content.length > 0) {
        const merged = mergeSectionHooks(activeFrame.hooks, aiMsg.content);
        if (merged !== aiMsg.content) {
          aiMsg.content = merged;
        }
      }
      this.mirrorStreamToLive(streamBubbleId, aiMsg); // ★ 0.244.0：收尾写穿后再落盘（完整内容）
      recordStat(this.statStore, 'aiMsg', mergedIn, mergedOut); // ★ 0.192.0：统计埋点——AI 回复 +1 + token 累加
      // 流式完成时滚到底部
      this.scroller.scrollEdge(Edge.Bottom);
      this.saveTree(); // ★ 0.151：按模式分池保存
      this.finishStreamFold(aiMsg); // ★ 0.234.0：完成瞬间解析章节→一次性收拢（前 1/3 展开，springMotion 收拢动画）
    };
    // ★ 0.300.0：御史审核流（同模型无记忆自审——只给契约简报+成品，不给生成过程/对话历史）；
    //   输出锁死「判定+≤3条意见」；通过→finalizeStream；不通过且未打回过→重写一轮；二审不过→降级告知
    let censorBuf = '';
    const runCensorPass = (): void => {
      if (activeContract === null || aiMsg.content.length === 0) {
        finalizeStream(0, 0, 0, 0, deliverWriteThink); // 防御：无契约/空成品直接放行
        return;
      }
      this.censorBadge = `正在审核（第 ${censorRoundsDone + 1} 轮）`;
      this.streamPhase = 9; // ★ 0.300.0 阶段 9——御史审核中
      censorBuf = '';
      const brief = buildContractBrief(activeContract);
      const censorPrompt = CENSOR_PROMPT.replace('{brief}', brief).replace('{content}', aiMsg.content);
      this.streamController = streamChat(
        [new ChatMessage(generateMessageId(), 'user', censorPrompt)],
        this.apiConfig,
        (chunk: string) => {
          censorBuf += chunk; // 审核流不写气泡（纯后台判定）
        },
        (inTok: number, outTok: number, cachedTok: number, _rTok: number) => {
          censorInTok += inTok;
          censorOutTok += outTok;
          censorCachedTok += cachedTok;
          this.updateSishuSpPreview(0, 0, 0, planInTok + deliverInTok, planOutTok + deliverOutTok, planCachedTok + deliverCachedTok);
          const v = parseCensorVerdict(censorBuf);
          if (v !== null && v.verdict === 'pass') {
            censorRoundsDone = 99; // 终态通过
            this.censorBadge = '';
            finalizeStream(0, 0, 0, 0, deliverWriteThink);
            return;
          }
          if (v !== null && censorRoundsDone < 1 && v.comments.length > 0) {
            // 打回重写（自动 ≤1 轮——2 次审核；用户手动「继续优化」为 V2）
            censorRoundsDone += 1;
            lastCensorComments = v.comments.map((c: string): string => `- ${c}`).join('\n');
            const cr: Record<string, string> = {};
            cr['round'] = `${censorRoundsDone}`;
            track(this.getUIContext().getHostContext() as common.Context, 'sishu_reject_round', cr);
            this.censorBadge = '发现瑕疵，重写中';
            this.streamPhase = 10; // ★ 0.300.0 阶段 10——按意见重写
            aiMsg.content = PLACEHOLDER_LOADING; // 重写从新稿开始（旧稿已被御史记录在案）
            this.mirrorStreamToLive(streamBubbleId, aiMsg);
            startDeliverWrite(lastCensorComments);
            return;
          }
          // 二审不过/审核输出两次解析失败 → 降级：保留成品+开头明确告知未兑现契约（不放行带病成品也不销毁）
          censorRoundsDone = 99;
          const fails = v !== null && v.comments.length > 0 ? v.comments.map((c: string): string => `- ${c}`).join('\n') : '（审核意见解析失败）';
          aiMsg.content = `> ⚠️ 御史审核未完全通过，以下契约项未兑现：\n> ${fails.replace(/\n/g, '\n> ')}\n> 已按分析型保留内容。可点「换一份」重试或补充要求后重发。\n\n${aiMsg.content}`;
          if (activeContract !== null) {
            activeContract.form = 'analysis'; // 降级=形态转分析（纠偏入口随之下线）
          }
          finalizeStream(0, 0, 0, 0, deliverWriteThink);
        },
        (_errMsg: string) => {
          // 审核流失败=放行成品（御史是质量增强不是阻塞——审核失败不能丢用户已付的执笔成品）
          censorRoundsDone = 99;
          this.showToastSafe('审核服务暂不可用，已直接交付');
          finalizeStream(0, 0, 0, 0, deliverWriteThink);
        },
        undefined,
        '御史审核',
        true // implicit：御史关思考（低随机性轻量审）
      );
    };
    // ★ 0.300.0：交付执笔（censorComments=''=初稿；非空=御史打回重写模式）
    const startDeliverWrite = (censorComments: string): void => {
      if (activeContract === null) {
        return;
      }
      deliverMode = true;
      const brief = buildContractBrief(activeContract);
      const writeMsgs: ChatMessage[] = [
        new ChatMessage(generateMessageId(), 'system', buildDeliverPrompt(brief, contractToneLine(activeContract),
          activeContract.targetChars, userClarifiedText, censorComments))
      ];
      if (prefPrompt.length > 0) {
        writeMsgs.push(new ChatMessage(generateMessageId(), 'system', prefPrompt));
      }
      this.thinkingEnabledNow = deliverWriteThink.enabled;
      startStream(deliverWriteThink, writeMsgs);
    };
    // ★ 0.292.0：webAppendix=FC 轮次消息；webToolsOn=本轮是否声明工具（onError 降级门读取 curWebToolsOn）
    const startStream = (thinkReq: ThinkingRequest, extraMsgs: ChatMessage[], webAppendix?: Object[], webToolsOn: boolean = false): void => {
    curWebToolsOn = webToolsOn;
    const finalMsgs: ChatMessage[] = extraMsgs.length > 0 ? [...messagesToSend, ...extraMsgs] : messagesToSend;
    this.streamController = streamChat(
      finalMsgs,
      this.apiConfig,
      (chunk: string) => {
        // onChunk：首次收到数据时清除占位文字（兼容加载/思考两态），然后追加 AI content
        contentStarted = true; // ★ 0.271.0：正文已开始（乱序防护置位）
        if (aiMsg.content === PLACEHOLDER_LOADING || aiMsg.content === PLACEHOLDER_THINKING) {
          aiMsg.content = '';
        }
        // ★ 0.271.0：进入 phase3——思考卡冻结收起为单行「已深度思考 Ns」（气泡尾部；★0.291.4「查看思维链」入口已删）
        if (this.thinkingActiveMsgId === aiMsg.messageId) {
          this.finishThinkingTrace(aiMsg.messageId);
        }
        aiMsg.content += chunk;
        this.mirrorStreamToLive(streamBubbleId, aiMsg); // ★ 0.244.0：流式写穿（防 reconcile 孤儿化丢流尾）
        // ★ 0.191.0：接收态已删——首字节到达即清占位，等待态消失，「正在接收内容」永远显示不出来
        // ★ 流式接收时自动滚到底部（恢复 0.104-0.107 移除的行为）
        this.scroller.scrollEdge(Edge.Bottom);
      },
      (inputTokens: number, outputTokens: number, cachedTokens: number, reasoningTokens: number) => {
        // onDone：解锁 + 存储 token（★ 0.247.4：缓存命中一并落账——弹层展示节省 SP；
        //   ★ 0.271.0：思考 token 拆分落账——已计入 outputTokens，仅明细弹层拆分展示用）
        // ★ 0.300.0 交付型御史分流：执笔完成≠任务完成——先审核（不落账），审核通过/降级才落账；
        //   执笔 tokens 入 deliver 累加器（重写多轮全累计，一次性实扣军令）
        this.streamController = null;
        if (this.thinkingActiveMsgId === aiMsg.messageId) {
          this.finishThinkingTrace(aiMsg.messageId);
        }
        if (aiMsg.content === PLACEHOLDER_LOADING || aiMsg.content === PLACEHOLDER_THINKING) {
          aiMsg.content = '（AI 未返回文本内容，请重试或更换模型）';
        }
        if (deliverMode && censorRoundsDone < 90 && aiMsg.content.length > 0
          && aiMsg.content !== '（AI 未返回文本内容，请重试或更换模型）') {
          deliverInTok += inputTokens;
          deliverOutTok += outputTokens;
          deliverCachedTok += cachedTokens;
          deliverReasonTok += reasoningTokens;
          this.updateSishuSpPreview(0, 0, 0, planInTok + deliverInTok + censorInTok, planOutTok + deliverOutTok + censorOutTok, planCachedTok + deliverCachedTok + censorCachedTok); // ★ 0.300.0 SP 透明：执笔轮落定
          this.isLoading = true; // 审核也是任务一部分（保持可取消）
          this.mirrorStreamToLive(streamBubbleId, aiMsg); // 执笔成品先写穿（审核期间可见）
          this.scroller.scrollEdge(Edge.Bottom);
          runCensorPass();
          return; // 落账延后到审核终点（finalizeStream）
        }
        finalizeStream(inputTokens, outputTokens, cachedTokens, reasoningTokens, thinkReq);
      },
      (errMsg: string) => {
        // ★ 0.271.0：思考参数不兼容自动降级（窄门：仅 400 且匹配 thinking/reasoning/模型不支持/参数非法——
        //   P0-4 实锤网关静默忽略为主路径，本判定防御网关未来行为变化；禁把所有 400 当参数错）
        if (!downgraded && thinkReq.enabled && isThinkingParamError(errMsg)) {
          downgraded = true;
          this.showToastSafe('已切换普通模式');
          startStream({ enabled: false, effort: '' }, extraMsgs);
          return;
        }
        // ★ 0.292.0：网关不支持 tools 自动降级（400+工具关键词窄门，单次语义同 thinking 降级）
        if (!webDowngraded && curWebToolsOn && isWebToolParamError(errMsg)) {
          webDowngraded = true;
          this.showToastSafe('当前模型通道不支持联网，已切换普通回答');
          startStream(webOffReq, extraMsgs, undefined, false);
          return;
        }
        // onError：解锁 + 日志 + 错误气泡
        this.isLoading = false;
        this.streamController = null;
        this.streamPhase = 0; // ★ 0.191.0：阶段复位
        this.streamingMsgId = ''; // ★ 0.234.0：错误态不折叠，恢复平铺显示
        // ★ 0.290.0（司枢 2.0）：②段失败语义=仅扣①段（任务书 §3.5，与 0.269 军令 #3/#4 一致）——
        //   ①段规划 token 已实耗则落账实扣；失败路径零扣费惯例保持（plan 无 usage=零扣）
        // ★ 0.300.0：deliver/censor 已耗 token 一并照落账（取消按已耗结算军令——审核轮失败不白嫖）
        if (planInTok > 0 || planOutTok > 0 || webInTok > 0 || webOutTok > 0
          || deliverInTok > 0 || deliverOutTok > 0 || censorInTok > 0 || censorOutTok > 0) {
          aiMsg.inputTokens = planInTok + webInTok + deliverInTok + censorInTok;
          aiMsg.outputTokens = planOutTok + webOutTok + deliverOutTok + censorOutTok;
          aiMsg.cacheHitTokens = planCachedTok + webCachedTok + deliverCachedTok + censorCachedTok;
          if (!this.spFree()) {
            const bal0 = siyiTotalSp(this.siyiStore);
            consumeSiyiSp(this.siyiStore, this.spCostOf(aiMsg));
            this.trackSpConsume(aiMsg, false, bal0 - siyiTotalSp(this.siyiStore), planInTok + deliverInTok + censorInTok, planCachedTok, 'plan', planOutTok + deliverOutTok + censorOutTok);
          }
        }
        // ★ 0.271.0：思考档失败不自动重发（超时/断流类二次超时概率高=双倍计费零收益）——
        //   登记手动「普通模式重试」按钮（把选择权给用户；regenerate=新尝试重新拥有降级机会）
        if (thinkReq.enabled) {
          this.thinkingRetryMsgIds = [...this.thinkingRetryMsgIds, aiMsg.messageId];
        }
        if (this.thinkingActiveMsgId === aiMsg.messageId) {
          this.finishThinkingTrace(aiMsg.messageId);
        }
        // ★ 0.190.6：错误场景分类（ApiClient 单一真相源）——中文场景+建议操作+保留原始错误；
        //   0.190.2 图片关键词检测已合并进 classifyStreamError
        aiMsg.content = classifyStreamError(errMsg);
        this.mirrorStreamToLive(streamBubbleId, aiMsg); // ★ 0.244.0：错误文案同步写穿
        // 错误时也滚到底部
        this.scroller.scrollEdge(Edge.Bottom);
        this.saveTree(); // ★ 0.151：按模式分池保存
      },
      (reasoning: string) => {
        // ★ 0.132 onReasoning：深度思考内容到达，占位切换为思考态
        // 思考内容不追加进 content（不参与持久化、不进入后续上下文），仅用于 UI 状态反馈
        // ★ 0.271.0：乱序防护——phase3 之后到达的 reasoning 分片一律丢弃，不再更新思考卡
        if (contentStarted) {
          return;
        }
        if (aiMsg.content === PLACEHOLDER_LOADING) {
          aiMsg.content = PLACEHOLDER_THINKING;
        }
        // ★ 0.271.0：思考卡驱动——首片浮现（秒表+计时+滚动摘要），后续分片持续追加
        if (this.thinkingActiveMsgId !== aiMsg.messageId) {
          this.beginThinkingTrace(aiMsg.messageId);
        }
        this.appendThinkingTrace(aiMsg.messageId, reasoning);
        this.streamPhase = 2; // ★ 0.191.0：阶段 2——等待服务器返回（思考模型思考阶段，锅甩给服务器）
        this.scroller.scrollEdge(Edge.Bottom);
      },
      'AI 回复',
      false,
      thinkReq, // ★ 0.271.0：思考档注入
      curWebToolsOn ? webTools : undefined, // ★ 0.292.0：联网工具声明（首轮与未达限轮）
      webAppendix, // ★ 0.292.0：FC 轮次消息（assistant tool_calls+tool 结果，请求副本）
      curWebToolsOn ? handleToolCalls : undefined // ★ 0.292.0：tool_calls 分流回调（执行工具后递归）
    );
    };
    // ============================================================
    // ★ 0.300.0（司枢 3.0）：枢机轮（Orchestrator）——三角色流水线总指挥。
    //   输入=对话上下文+PLAN3_PROMPT（+纠偏历史注入）；输出=执行契约 JSON（sanitizeContract 防弹衣）；
    //   恒挂联网 tools 由枢机自主调用（execToolRound 共用执行体，递归回枢机轮；护栏=空轮/查重/轮上限）；
    //   反问=挂起-回调恢复模式（clarifyResume 闭包注册——ClarifyCard 作答触发 resume；重入/销毁走
    //   abandonClarify 静默死亡，代际核对防新旧任务并发）；分级触发在 continueWrite。
    // ============================================================
    let activeContractPre: TaskContract | null = null; // 反问挂起期契约暂存（resume 后 continueWrite 消费）
    const startOrchestr = (): void => {
      const myGen = this.streamGen;
      this.streamPhase = 5; // 阶段 5——枢机规划中（复用规划卡视觉）
      this.planningMsgId = aiMsg.messageId;
      this.planPreview = '';
      const orchAppendixAcc: Object[] = [];
      let orchBuf = '';
      let orchRetried = false;
      const correctHint = loadCorrectHint(this.getUIContext().getHostContext() as common.Context);
      const orchMsgs: ChatMessage[] = [...messagesToSend,
        new ChatMessage(generateMessageId(), 'system', correctHint.length > 0 ? `${PLAN3_PROMPT}\n\n${correctHint}` : PLAN3_PROMPT)];
      // 枢机契约消费终点：分级触发（任务书 §一分级触发表）
      const continueWrite = (contract: TaskContract): void => {
        activeContract = contract;
        this.planningMsgId = '';
        this.planController = null;
        this.streamPhase = 1;
        // 契约存档（交付卡渲染+纠偏入口依据；会话级——刷新退化为普通气泡可接受）
        this.contractByMsg.set(aiMsg.messageId, contract);
        const o3: Record<string, string> = {};
        o3['ev'] = 'orch_ok';
        o3['taskType'] = contract.taskType;
        o3['form'] = contract.form;
        o3['tools'] = contract.usedTools ? '1' : '0';
        track(this.getUIContext().getHostContext() as common.Context, 'plan_three_stage', o3);
        if (contract.taskType === 'closed') {
          // 封闭问答：单轮直出（MEDIUM 自适应短答——不进框架链）
          activeFrame = null;
          const closedMsgs: ChatMessage[] = [new ChatMessage(generateMessageId(), 'system', MEDIUM_REPLY_PROMPT)];
          if (prefPrompt.length > 0) {
            closedMsgs.push(new ChatMessage(generateMessageId(), 'system', prefPrompt));
          }
          this.thinkingEnabledNow = false;
          startStream({ enabled: false, effort: '' }, closedMsgs);
          return;
        }
        if (contract.form === 'deliverable') {
          // 交付型（含 creative V1 归并）：执笔→御史（1 轮打回）→定稿/降级
          activeFrame = null; // 交付型零钩子合成
          deliverWriteThink = contract.lengthTier === 'brief' ? webOffReq : thinkingReq;
          censorRoundsDone = 0;
          startDeliverWrite('');
          return;
        }
        // 分析型/检索型：框架执笔（PlanFrame 兼容链——契约 sections/hooks 注入 buildWritePrompt）
        const frameLike: PlanFrame = new PlanFrame();
        frameLike.lengthTier = contract.lengthTier;
        frameLike.targetChars = contract.targetChars;
        frameLike.sections = contract.sections;
        frameLike.hooks = contract.hooks;
        frameLike.voice = contract.voice;
        frameLike.encourage = contract.encourage;
        frameLike.analogy = contract.analogy;
        activeFrame = frameLike;
        const writeMsgs: ChatMessage[] = [
          new ChatMessage(generateMessageId(), 'system', buildWritePrompt(planFrameJson(frameLike), frameLike.targetChars, planToneLine(frameLike))),
          new ChatMessage(generateMessageId(), 'system', SECTION_PROMPT)
        ];
        if (prefPrompt.length > 0) {
          writeMsgs.push(new ChatMessage(generateMessageId(), 'system', prefPrompt));
        }
        if (userClarifiedText.length > 0) {
          writeMsgs.push(new ChatMessage(generateMessageId(), 'system', `【用户反问作答（必须按此执行）】\n${userClarifiedText}`));
        }
        const writeThink: ThinkingRequest = contract.lengthTier === 'brief'
          ? webOffReq
          : thinkingReq;
        this.thinkingEnabledNow = writeThink.enabled;
        startStream(writeThink, writeMsgs);
      };
      // 枢机产物终点：防弹衣两次失败→fallback 直写（LONG 链，零契约）
      const fallbackOrch = (inTok: number, outTok: number, cachedTok: number): void => {
        this.planningMsgId = '';
        this.planController = null;
        planInTok = inTok;
        planOutTok = outTok;
        planCachedTok = cachedTok;
        activeFrame = null;
        activeContract = null;
        this.streamPhase = 1;
        const fbMsgs: ChatMessage[] = [new ChatMessage(generateMessageId(), 'system', LONG_REPLY_PROMPT),
          new ChatMessage(generateMessageId(), 'system', SECTION_PROMPT)];
        if (prefPrompt.length > 0) {
          fbMsgs.push(new ChatMessage(generateMessageId(), 'system', prefPrompt));
        }
        const oFail: Record<string, string> = {};
        oFail['ev'] = 'orch_degrade';
        track(this.getUIContext().getHostContext() as common.Context, 'plan_three_stage', oFail);
        startStream(thinkingReq, fbMsgs);
      };
      const finishOrchestr = (contract: TaskContract | null, inTok: number, outTok: number, cachedTok: number): void => {
        planInTok = inTok;
        planOutTok = outTok;
        planCachedTok = cachedTok;
        this.updateSishuSpPreview(0, 0, 0, planInTok, planOutTok, planCachedTok); // ★ 0.300.0 SP 透明：枢机轮落定
        if (contract === null) {
          fallbackOrch(0, 0, 0); // token 已记入上方，fallback 零参防双计
          return;
        }
        contract.usedTools = webRound > 0;
        // 反问收束（三条件由 PLAN3_PROMPT 判定；单任务最多 1 轮；跳过=按默认假设做）
        if (contract.needAsk && contract.askQuestions.length > 0) {
          activeContractPre = contract;
          this.planningMsgId = ''; // 规划期结束（进入反问态——规划卡收起）
          this.planController = null;
          this.planPreview = '';
          this.isLoading = false; // 挂起期暂释（用户需交互；resume 后复位）
          this.streamController = null;
          this.streamPhase = 0;
          this.clarifyState.messageId = aiMsg.messageId;
          this.clarifyState.questions = contract.askQuestions;
          this.clarifyState.title = `开工前确认 ${contract.askQuestions.length} 个问题`;
          this.clarifyState.visible = true;
          const cs: Record<string, string> = {};
          cs['count'] = `${contract.askQuestions.length}`;
          track(this.getUIContext().getHostContext() as common.Context, 'sishu_clarify_show', cs);
          // 恢复闭包：ClarifyCard onSubmit/onSkip → resolveClarify → resume（代际核对防并发）
          this.clarifyResume = (answers: string[] | null): void => {
            this.clarifyResume = null;
            this.clarifyState.visible = false;
            if (myGen !== this.streamGen) {
              return; // 被新任务顶替：静默死亡（新链路已接管）
            }
            if (answers === null || answers.length === 0) {
              const ck: Record<string, string> = {};
              ck['ev'] = 'skip';
              track(this.getUIContext().getHostContext() as common.Context, 'sishu_clarify_answer', ck);
            } else {
              userClarifiedText = answers.filter((a: string): boolean => a.length > 0).join('\n');
              const ca: Record<string, string> = {};
              ca['ev'] = 'answer';
              track(this.getUIContext().getHostContext() as common.Context, 'sishu_clarify_answer', ca);
            }
            const c = activeContractPre;
            activeContractPre = null;
            if (c === null) {
              return;
            }
            c.needAsk = false;
            this.isLoading = true;
            this.streamPhase = 1;
            continueWrite(c);
          };
          return;
        }
        continueWrite(contract);
      };
      const attemptOrchestrator = (toolsOn: boolean): void => {
        this.planController = streamChat(
          orchMsgs,
          this.apiConfig,
          (chunk: string) => {
            orchBuf += chunk; // 枢机不直显正文，规划卡流式预览（思考卡同族）
            this.planPreview = orchBuf.length > 160 ? `${orchBuf.substring(0, 160)}…` : orchBuf;
          },
          (inTok: number, outTok: number, cachedTok: number, _rTok: number) => {
            const contract = sanitizeContract(orchBuf);
            if (contract === null && !orchRetried) {
              orchRetried = true;
              orchBuf = '';
              this.planPreview = '';
              const oRetry: Record<string, string> = {};
              oRetry['ev'] = 'orch_retry';
              track(this.getUIContext().getHostContext() as common.Context, 'plan_three_stage', oRetry);
              attemptOrchestrator(toolsOn);
              return;
            }
            finishOrchestr(contract, inTok, outTok, cachedTok);
          },
          (_errMsg: string) => {
            if (!orchRetried) {
              orchRetried = true;
              orchBuf = '';
              this.planPreview = '';
              attemptOrchestrator(toolsOn);
              return;
            }
            fallbackOrch(0, 0, 0); // 两次失败：fallback 直写（枢机 onError 无 usage=零扣费惯例）
          },
          undefined,
          '司枢枢机',
          true, // implicit：枢机关思考（轻量快速）；SP 走全链 token 累加实扣
          undefined, // thinking（implicit 已钳 disabled，显式留空）
          toolsOn ? webTools : undefined,
          orchAppendixAcc.length > 0 ? orchAppendixAcc : undefined,
          toolsOn ? (calls: ToolCallResult[], inTok: number, outTok: number, cachedTok: number): void => {
            execToolRound(calls, inTok, outTok, cachedTok, orchAppendixAcc,
              (stillOn: boolean): void => {
                if (!this.isLoading) {
                  return; // 用户已取消：中断递归
                }
                attemptOrchestrator(stillOn);
              }, ORCH_TOOL_ROUNDS_LIMIT);
          } : undefined
        );
      };
      attemptOrchestrator(true); // 司枢恒挂 tools——枢机自主决定调不调（产品军令 5）
    };
    const startPlanning = (): void => {
      this.streamPhase = 5; // 阶段 5——正在搭建回答框架
      this.planningMsgId = aiMsg.messageId;
      this.planPreview = '';
      const planMsgs: ChatMessage[] = [...messagesToSend,
        new ChatMessage(generateMessageId(), 'system', PLAN_PROMPT)];
      let planBuf = '';
      let planRetried = false;
      const finishPlan = (frame: PlanFrame | null, inTok: number, outTok: number, cachedTok: number): void => {
        this.planningMsgId = '';
        this.planController = null;
        planInTok = inTok;
        planOutTok = outTok;
        planCachedTok = cachedTok;
        this.streamPhase = 1; // ②段即将发出（等待态回常规文案）
        if (frame === null) {
          // fallback 直写：现有 LONG 直写链路整体保留（LONG+SECTION+称呼），钩子走本地 breath 保底
          activeFrame = null;
          const fbMsgs: ChatMessage[] = [new ChatMessage(generateMessageId(), 'system', LONG_REPLY_PROMPT),
            new ChatMessage(generateMessageId(), 'system', SECTION_PROMPT)];
          if (prefPrompt.length > 0) {
            fbMsgs.push(new ChatMessage(generateMessageId(), 'system', prefPrompt));
          }
          const pFail: Record<string, string> = {};
          pFail['ev'] = 'plan_degrade';
          track(this.getUIContext().getHostContext() as common.Context, 'plan_two_stage', pFail);
          startStream(thinkingReq, fbMsgs);
          return;
        }
        // ②段执笔：框架注入 system（章节+要点+深度+语气旋钮）；brief 档关思考+压字数（Q5——
        //   不跳段恒两段，brief 自动省思考时延与 SP）；SECTION 保留（折叠地基）；钩子隔离零钩子指令
        activeFrame = frame;
        const writeMsgs: ChatMessage[] = [
          new ChatMessage(generateMessageId(), 'system', buildWritePrompt(planFrameJson(frame), frame.targetChars, planToneLine(frame))),
          new ChatMessage(generateMessageId(), 'system', SECTION_PROMPT)
        ];
        if (prefPrompt.length > 0) {
          writeMsgs.push(new ChatMessage(generateMessageId(), 'system', prefPrompt));
        }
        const writeThink: ThinkingRequest = frame.lengthTier === 'brief'
          ? { enabled: false, effort: '' }
          : thinkingReq;
        this.thinkingEnabledNow = writeThink.enabled;
        const pOk: Record<string, string> = {};
        pOk['ev'] = 'plan_ok';
        pOk['tier'] = frame.lengthTier;
        pOk['secs'] = `${frame.sections.length}`;
        track(this.getUIContext().getHostContext() as common.Context, 'plan_two_stage', pOk);
        startStream(writeThink, writeMsgs);
      };
      const attemptPlan = (): void => {
        this.planController = streamChat(
          planMsgs,
          this.apiConfig,
          (chunk: string) => {
            planBuf += chunk; // ①段不直显正文，仅规划卡流式预览（思考卡同族）
            this.planPreview = planBuf.length > 160 ? `${planBuf.substring(0, 160)}…` : planBuf;
          },
          (inTok: number, outTok: number, cachedTok: number, _rTok: number) => {
            const frame = sanitizePlan(planBuf);
            if (frame === null && !planRetried) {
              planRetried = true; // Q3：解析失败带报错重试一次
              planBuf = '';
              this.planPreview = '';
              const pRetry: Record<string, string> = {};
              pRetry['ev'] = 'plan_retry';
              track(this.getUIContext().getHostContext() as common.Context, 'plan_two_stage', pRetry);
              attemptPlan();
              return;
            }
            finishPlan(frame, inTok, outTok, cachedTok);
          },
          (_errMsg: string) => {
            if (!planRetried) {
              planRetried = true; // ①段失败重试一次
              planBuf = '';
              this.planPreview = '';
              attemptPlan();
              return;
            }
            finishPlan(null, 0, 0, 0); // 两次失败：fallback 直写（①段失败路径零扣费惯例）
          },
          undefined,
          '司枢规划',
          true // implicit：规划器 thinking 钳 disabled（轻量快速）；SP 走②段累加实扣
        );
      };
      attemptPlan();
    };
    if (useSishu3) {
      this.thinkingEnabledNow = false; // 枢机期无思考；执笔按契约档位重算
      startOrchestr(); // ★ 0.300.0 司枢 3.0：枢机→（反问）→执笔→御史 三角色流水线
    } else if (siyuMode) {
      this.thinkingEnabledNow = false; // 规划期无思考；②段按框架档位重算
      startPlanning(); // ★ 经典模式：旧 0.290.0 框架两段式（灰度开关）
    } else {
      startStream(thinkingReq, [], undefined, webOn); // ★ 0.292.0：联网开=首轮即声明工具；★ 0.300.0 webOn=强制或预路由命中
    }
    // 发送消息后自动滚到底部
    this.scroller.scrollEdge(Edge.Bottom);
  }

  // ★ 0.149：刷新按钮——原位重新生成指定 AI 回复（置加载占位后按链路上下文重新请求，
  // buildBranchMessageList 自动剔除占位使旧回复不进入新请求；消息不删、位置不变）
  async regenerateMessage(msg: ChatMessage, forceDisabled: boolean = false): Promise<void> { // ★ 0.271.0：forceDisabled——「普通模式重试」强制本条 disabled
    this.cancelPlanning('new'); // ★ 0.290.0：重生成先 abort 旧①段防乱序
    this.streamGen += 1; // ★ 0.300.0：任务代际+1（防反问挂起链路复活）
    this.abandonClarify(); // ★ 0.300.0：重生成顶替反问挂起（静默中断）
    // ★ 0.190.4：卡死自愈（同 sendMessage，须在 guard 前）
    if (this.isLoading && this.streamController === null) {
      this.isLoading = false;
    }
    // ★ 0.248.2：AI 登录守卫（同 sendMessage——重新生成同属 AI 生成内容，合规口径一致）
    if (!connectHuaweiAccount().isLoggedIn) {
      connectConfirmDialog().aiLoginPromptVisible = true;
      return;
    }
    // ★ 0.293.0：SP 云同步门卫（同 sendMessage——重生成同属 AI 调用，gate 口径一致）
    if (!requireSiyiGate()) {
      return;
    }
    // ★ 0.248.7：SP 余额闸门（同 sendMessage——重生成同属 AI 调用，实扣口径一致；★ 0.249.0：Lv8 免扣豁免）
    if (!this.spFree() && siyiTotalSp(this.siyiStore) <= 0) {
      connectConfirmDialog().spRechargePromptVisible = true;
      return;
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
    msg.reasoningTokens = 0; // ★ 0.271.0：重生成重置思考 token（随新请求更新）
    msg.model = this.apiConfig.model; // ★ 0.224.3：刷新用当前配置重生成——模型标记随新请求更新
    // ★ 0.271.0：思考档解析（forceDisabled=手动降级重试强制本条 disabled；策略矩阵同 sendMessage——
    //   S3 计数不含本条自身：当前 assistant 消息里本条已是占位，发送时刻气泡 AI 数-1）
    const regenAiCount = Math.max(0, this.currentBubble.messages
      .filter((m: ChatMessage): boolean => m.role === 'assistant').length - 1);
    const regenTopic = this.currentBubble.topicTags.length > 0 ? this.currentBubble.topicTags.join('、') : '';
    const regenUserText = this.findLastUserTextBefore(msg);
    const regenThinking: ThinkingRequest = forceDisabled ? { enabled: false, effort: '' } :
      resolveThinkingFor('auto', this.replyLengthMode, // ★ 0.290.0：思考档恒 auto（GSD UI 隐藏恒定值）
        msg.isPodcastMode, regenUserText, regenTopic, regenAiCount);
    this.thinkingEnabledNow = regenThinking.enabled;
    // ★ 0.271.0：重生成清旧思考态（新尝试新思考卡）
    if (this.thinkingActiveMsgId === msg.messageId) {
      this.finishThinkingTrace(msg.messageId);
    }
    this.thinkingSecondsByMsg.delete(msg.messageId);
    this.thinkingTraceByMsg.delete(msg.messageId);
    this.thinkingDoneTick += 1;
    // ★ 0.234.0：重走一遍（直显→收拢，任务书 §2.1.3）——清旧折叠态/渲染计划缓存，置流式标记
    this.planCache.delete(msg.messageId);
    chatFoldMemory.delete(msg.messageId);
    const foldStore = new Map(this.foldStateView);
    foldStore.delete(msg.messageId);
    this.foldStateView = foldStore;
    this.streamingMsgId = msg.messageId;
    this.isLoading = true;
    this.streamPhase = 1; // ★ 0.191.0：阶段 1——请求即将发出，等待服务器响应
    const regenBubbleId = this.currentBubbleId; // ★ 0.244.0：流式写穿定位键（刷新时刻的气泡 ID）
    const messagesToSend = await this.buildBranchMessageList(this.currentBubble);
    // ★ 0.290.0（司枢 2.0）：长回复重生成同样走框架先行两段式（与 sendMessage 同机制）；
    //   播客历史消息重生成维持旧直写链路（0.282 后常态不触达）
    const regenSiyu = this.replyLengthMode === 'long' && !msg.isPodcastMode;
    const prefPrompt = this.buildPreferencePrompt(msg.isPodcastMode);
    if (!regenSiyu) {
      if (this.replyLengthMode === 'long') {
        messagesToSend.push(new ChatMessage(generateMessageId(), 'system', LONG_REPLY_PROMPT));
      } else {
        messagesToSend.push(new ChatMessage(generateMessageId(), 'system', MEDIUM_REPLY_PROMPT));
      }
      if (prefPrompt.length > 0) {
        messagesToSend.push(new ChatMessage(generateMessageId(), 'system', prefPrompt));
      }
    }
    // 播客模式：沿用该消息原发起模式，重新追加播客 prompt
    if (msg.isPodcastMode) {
      messagesToSend.push(new ChatMessage(generateMessageId(), 'system', PODCAST_PROMPT));
    }

    // ★ 0.271.0：流式调用包装为可降级重发的局部函数（同 sendMessage §3.6 窄门降级）
    // ★ 0.290.0：泛化直写流（regen fallback/②段执笔两用；plan token 累加+渲染期钩子合成同 sendMessage）
    let regenDowngraded = false;
    let regenContentStarted = false; // 乱序防护
    let regenPlanIn = 0;
    let regenPlanOut = 0;
    let regenPlanCached = 0;
    let regenFrame: PlanFrame | null = null;
    let regenDeliverCorrected = false; // ★ 0.300.0：纠偏切交付型重跑完成→交付卡标记同步
    const startRegenStream = (thinkReq: ThinkingRequest, extraMsgs: ChatMessage[]): void => {
    const regenMsgs: ChatMessage[] = extraMsgs.length > 0 ? [...messagesToSend, ...extraMsgs] : messagesToSend;
    this.streamController = streamChat(
      regenMsgs,
      this.apiConfig,
      (chunk: string) => {
        // onChunk：首次收到数据时清除占位文字（兼容加载/思考两态），然后追加 AI content
        regenContentStarted = true; // ★ 0.271.0：正文已开始（乱序防护置位）
        if (msg.content === PLACEHOLDER_LOADING || msg.content === PLACEHOLDER_THINKING) {
          msg.content = '';
        }
        // ★ 0.271.0：进入 phase3——思考卡冻结收起
        if (this.thinkingActiveMsgId === msg.messageId) {
          this.finishThinkingTrace(msg.messageId);
        }
        msg.content += chunk;
        this.mirrorStreamToLive(regenBubbleId, msg); // ★ 0.244.0：流式写穿（防 reconcile 孤儿化丢流尾）
        // ★ 0.191.0：接收态已删（同 sendMessage——死代码）
        this.scroller.scrollEdge(Edge.Bottom);
      },
      (inputTokens: number, outputTokens: number, cachedTokens: number, reasoningTokens: number) => {
        // onDone：解锁 + 存储 token（★ 0.247.4：缓存命中一并落账；★ 0.271.0：思考 token 拆分落账）
        this.isLoading = false;
        this.streamController = null;
        this.streamPhase = 0; // ★ 0.191.0：阶段复位
        // ★ 0.271.0：思考态收尾兜底（零正文直接完成场景）
        if (this.thinkingActiveMsgId === msg.messageId) {
          this.finishThinkingTrace(msg.messageId);
        }
        if (msg.content === PLACEHOLDER_LOADING || msg.content === PLACEHOLDER_THINKING) {
          msg.content = '（AI 未返回文本内容，请重试或更换模型）';
        }
        // ★ 0.290.0：两段 token 累加一次性落账（同 sendMessage 军令）
        msg.inputTokens = inputTokens + regenPlanIn;
        msg.outputTokens = outputTokens + regenPlanOut;
        msg.cacheHitTokens = cachedTokens + regenPlanCached;
        msg.reasoningTokens = reasoningTokens; // ★ 0.271.0
        const regenMergedIn = msg.inputTokens;
        const regenMergedOut = msg.outputTokens;
        const regenMergedCached = msg.cacheHitTokens;
        const regenThinkDur = this.thinkingSecondsByMsg.get(msg.messageId) ?? 0;
        const regenThinkChars = this.thinkingTraceByMsg.get(msg.messageId)?.length ?? 0;
        if (!this.spFree()) { // ★ 0.249.0：Lv8 司忆令 SP 永久免费——免扣账号跳过实扣
          const _bal0 = siyiTotalSp(this.siyiStore); // ★ 0.260.0：实扣前后余额差=本行实扣额
          consumeSiyiSp(this.siyiStore, this.spCostOf(msg)); // ★ 0.248.7：重生成实扣 SP（同 sendMessage 口径）
          this.trackSpConsume(msg, false, _bal0 - siyiTotalSp(this.siyiStore), regenMergedIn, regenMergedCached, 'regen', regenMergedOut); // ★ 0.260.0；★ 0.273.0 补 ot；★ 0.290.0 合并口径
          // ★ 0.271.0：thinking_use 埋点（regen 场景同款五态）
          this.trackThinkingUse(!thinkReq.enabled ? 'off' : (reasoningTokens > 0 ? (regenDowngraded ? 'auto_downgrade' : 'use') : 'degrade'),
            this.replyLengthMode, thinkReq.effort, regenThinkDur, regenThinkChars, _bal0 - siyiTotalSp(this.siyiStore));
        } else {
          this.trackSpConsume(msg, true, 0, regenMergedIn, regenMergedCached, 'regen', regenMergedOut); // ★ 0.260.0：免扣照报 f:y；★ 0.273.0 补 ot；★ 0.290.0 合并口径
          this.trackThinkingUse(!thinkReq.enabled ? 'off' : (reasoningTokens > 0 ? (regenDowngraded ? 'auto_downgrade' : 'use') : 'degrade'),
            this.replyLengthMode, thinkReq.effort, regenThinkDur, regenThinkChars, 0);
        }
        // ★ 0.290.0：渲染期钩子合成（同 sendMessage——框架 hooks 节号制插入；fallback 跳过走 breath 保底）
        if (regenFrame !== null && msg.content.length > 0) {
          const merged = mergeSectionHooks(regenFrame.hooks, msg.content);
          if (merged !== msg.content) {
            msg.content = merged;
          }
        }
        // ★ 0.300.0：纠偏重跑完成→交付卡标记同步（切交付型=出现 / 切分析型=移除）
        if (regenDeliverCorrected && !this.deliverMsgIds.includes(msg.messageId)) {
          this.deliverMsgIds = [...this.deliverMsgIds, msg.messageId];
        } else if (!regenDeliverCorrected && this.deliverMsgIds.includes(msg.messageId)) {
          this.deliverMsgIds = this.deliverMsgIds.filter((id: string): boolean => id !== msg.messageId);
        }
        this.mirrorStreamToLive(regenBubbleId, msg); // ★ 0.244.0：收尾写穿后再落盘（完整内容）
        recordStat(this.statStore, 'aiMsg', regenMergedIn, regenMergedOut); // ★ 0.192.0：统计埋点——重新生成同样计 AI 回复 + token
        this.scroller.scrollEdge(Edge.Bottom);
        this.saveTree(); // ★ 0.151：按模式分池保存
        this.finishStreamFold(msg); // ★ 0.234.0：重新生成完成——重走收拢（默认展开集重置）
      },
      (errMsg: string) => {
        // ★ 0.271.0：思考参数不兼容自动降级（同 sendMessage 窄门）
        if (!regenDowngraded && thinkReq.enabled && isThinkingParamError(errMsg)) {
          regenDowngraded = true;
          this.showToastSafe('已切换普通模式');
          startRegenStream({ enabled: false, effort: '' }, extraMsgs);
          return;
        }
        // onError：解锁 + 错误提示
        this.isLoading = false;
        this.streamController = null;
        this.streamPhase = 0; // ★ 0.191.0：阶段复位
        this.streamingMsgId = ''; // ★ 0.234.0：错误态不折叠，恢复平铺显示
        // ★ 0.290.0：②段失败仅扣①段（同 sendMessage）
        if (regenPlanIn > 0 || regenPlanOut > 0) {
          msg.inputTokens = regenPlanIn;
          msg.outputTokens = regenPlanOut;
          msg.cacheHitTokens = regenPlanCached;
          if (!this.spFree()) {
            const bal0 = siyiTotalSp(this.siyiStore);
            consumeSiyiSp(this.siyiStore, this.spCostOf(msg));
            this.trackSpConsume(msg, false, bal0 - siyiTotalSp(this.siyiStore), regenPlanIn, regenPlanCached, 'plan', regenPlanOut);
          }
        }
        // ★ 0.271.0：思考档失败登记手动「普通模式重试」
        if (thinkReq.enabled) {
          this.thinkingRetryMsgIds = [...this.thinkingRetryMsgIds, msg.messageId];
        }
        if (this.thinkingActiveMsgId === msg.messageId) {
          this.finishThinkingTrace(msg.messageId);
        }
        // ★ 0.190.6：错误场景分类（与 sendMessage onError 同机制）
        msg.content = classifyStreamError(errMsg);
        this.mirrorStreamToLive(regenBubbleId, msg); // ★ 0.244.0：错误文案同步写穿
        this.scroller.scrollEdge(Edge.Bottom);
        this.saveTree(); // ★ 0.151：按模式分池保存
      },
      (reasoning: string) => {
        // onReasoning：深度思考内容到达，占位切换为思考态（不持久化，仅 UI 反馈）
        // ★ 0.271.0：乱序防护——phase3 之后到达的 reasoning 分片一律丢弃
        if (regenContentStarted) {
          return;
        }
        if (msg.content === PLACEHOLDER_LOADING) {
          msg.content = PLACEHOLDER_THINKING;
        }
        // ★ 0.271.0：思考卡驱动（同 sendMessage）
        if (this.thinkingActiveMsgId !== msg.messageId) {
          this.beginThinkingTrace(msg.messageId);
        }
        this.appendThinkingTrace(msg.messageId, reasoning);
        this.streamPhase = 2; // ★ 0.191.0：阶段 2——等待服务器返回（思考模型思考阶段）
        this.scroller.scrollEdge(Edge.Bottom);
      },
      'AI 回复',
      false,
      thinkReq // ★ 0.271.0：思考档注入
    );
    };
    // ★ 0.290.0（司枢 2.0）：重生成①段规划器（与 sendMessage startPlanning 同构——框架先行两段式）
    const startRegenPlanning = (): void => {
      this.streamPhase = 5;
      this.planningMsgId = msg.messageId;
      this.planPreview = '';
      const planMsgs: ChatMessage[] = [...messagesToSend,
        new ChatMessage(generateMessageId(), 'system', PLAN_PROMPT)];
      let planBuf = '';
      let planRetried = false;
      const finishPlan = (frame: PlanFrame | null, inTok: number, outTok: number, cachedTok: number): void => {
        this.planningMsgId = '';
        this.planController = null;
        regenPlanIn = inTok;
        regenPlanOut = outTok;
        regenPlanCached = cachedTok;
        this.streamPhase = 1;
        if (frame === null) {
          regenFrame = null;
          const fbMsgs: ChatMessage[] = [new ChatMessage(generateMessageId(), 'system', LONG_REPLY_PROMPT),
            new ChatMessage(generateMessageId(), 'system', SECTION_PROMPT)];
          if (prefPrompt.length > 0) {
            fbMsgs.push(new ChatMessage(generateMessageId(), 'system', prefPrompt));
          }
          startRegenStream(regenThinking, fbMsgs);
          return;
        }
        regenFrame = frame;
        const writeMsgs: ChatMessage[] = [
          new ChatMessage(generateMessageId(), 'system', buildWritePrompt(planFrameJson(frame), frame.targetChars, planToneLine(frame))),
          new ChatMessage(generateMessageId(), 'system', SECTION_PROMPT)
        ];
        if (prefPrompt.length > 0) {
          writeMsgs.push(new ChatMessage(generateMessageId(), 'system', prefPrompt));
        }
        const writeThink: ThinkingRequest = frame.lengthTier === 'brief'
          ? { enabled: false, effort: '' }
          : regenThinking;
        this.thinkingEnabledNow = writeThink.enabled;
        startRegenStream(writeThink, writeMsgs);
      };
      const attemptPlan = (): void => {
        this.planController = streamChat(
          planMsgs,
          this.apiConfig,
          (chunk: string) => {
            planBuf += chunk;
            this.planPreview = planBuf.length > 160 ? `${planBuf.substring(0, 160)}…` : planBuf;
          },
          (inTok: number, outTok: number, cachedTok: number, _rTok: number) => {
            const frame = sanitizePlan(planBuf);
            if (frame === null && !planRetried) {
              planRetried = true;
              planBuf = '';
              this.planPreview = '';
              attemptPlan();
              return;
            }
            finishPlan(frame, inTok, outTok, cachedTok);
          },
          (_errMsg: string) => {
            if (!planRetried) {
              planRetried = true;
              planBuf = '';
              this.planPreview = '';
              attemptPlan();
              return;
            }
            finishPlan(null, 0, 0, 0);
          },
          undefined,
          '司枢规划',
          true
        );
      };
      attemptPlan();
    };
    if (regenSiyu) {
      this.thinkingEnabledNow = false;
      // ★ 0.300.0 纠偏直写分支：correctPendingByMsg 有存档契约（form 已切换）→ 跳过枢机直接按
      //   修正后契约重跑执笔（任务书 §三.4「不是让用户重新描述」）；V1 纠偏重跑不再机审（用户接管）
      const corrected = this.correctPendingByMsg.get(msg.messageId);
      if (corrected !== undefined) {
        this.correctPendingByMsg.delete(msg.messageId);
        this.contractByMsg.set(msg.messageId, corrected);
        if (corrected.form === 'deliverable') {
          regenDeliverCorrected = true;
          const cMsgs: ChatMessage[] = [new ChatMessage(generateMessageId(), 'system',
            buildDeliverPrompt(buildContractBrief(corrected), contractToneLine(corrected), corrected.targetChars, '', ''))];
          if (prefPrompt.length > 0) {
            cMsgs.push(new ChatMessage(generateMessageId(), 'system', prefPrompt));
          }
          this.streamPhase = 1;
          startRegenStream(regenThinking, cMsgs);
        } else {
          const frameLike: PlanFrame = new PlanFrame();
          frameLike.lengthTier = corrected.lengthTier;
          frameLike.targetChars = corrected.targetChars;
          frameLike.sections = corrected.sections;
          frameLike.hooks = corrected.hooks;
          frameLike.voice = corrected.voice;
          frameLike.encourage = corrected.encourage;
          frameLike.analogy = corrected.analogy;
          regenFrame = frameLike;
          const wMsgs: ChatMessage[] = [
            new ChatMessage(generateMessageId(), 'system', buildWritePrompt(planFrameJson(frameLike), frameLike.targetChars, planToneLine(frameLike))),
            new ChatMessage(generateMessageId(), 'system', SECTION_PROMPT)
          ];
          if (prefPrompt.length > 0) {
            wMsgs.push(new ChatMessage(generateMessageId(), 'system', prefPrompt));
          }
          this.streamPhase = 1;
          startRegenStream(regenThinking, wMsgs);
        }
      } else {
        startRegenPlanning(); // 常规重生成：经典两段式规划器（3.0 全链在 sendMessage 主链，重生成沿用 2.0 框架链——契约重判由新发送承担）
      }
    } else {
      startRegenStream(regenThinking, []);
    }
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

  // ★ 0.291.3：10 秒顶格长 toast（钱相关提示必须看清——系统只认 1500/10000 两档，GSD 0.259.2 同款；
  //   ⚠️ 本文件 340 行附近的子组件 struct 另有同名 showToastSafe——同文件多 struct 同名方法，
  //   定位定义必须按 struct 区段（本轮两连错根因），勿只 grep 方法名）
  showToastLong(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 10000 });
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
    // ★ 0.232.0：朗读文本清洗——**粗**/#标题/代码围栏/表格竖线等 Markdown 符号不进 TTS
    //   （用户痛点锚点：本地语音「连星号星号都要读进去」，云端本地双引擎共用清洗）
    // ★ 0.234.0：锚点标记先剥壳留文案（stripAnchorMarks keepText=true）——朗读全文含收起章节、
    //   不读 [[anchor 等标记字符（任务书 §2.4/§5.4：全文照发，折叠状态不参与 TTS）
    // ★ 0.269.0：TTS 遇锚点/钩子块直接跳过不朗读（终稿拍板——钩子是视觉阅读辅助，朗读无意义；
    //   keepText false=标记行整行滤除；听播内容本无锚点、短回复无锚点，两模式零影响）
    const speakText = mdToSpeakableText(stripAnchorMarks(msg.content, false));
    if (speakText.length === 0) {
      this.showToastSafe('该消息没有可朗读的文本（代码/符号内容已跳过）');
      return;
    }
    this.playingMessageId = msg.messageId;
    this.ttsLoadingMessageId = msg.messageId;
    // ★ 0.272.0：本地语音档（TTS 1.0 默认档）——零成本直发本地引擎，不碰云端三档
    //   （云端三档保留可用：volcano/qianwen/custom 逻辑零改动，未配置/失败兜底链照旧）
    if (this.apiConfig.ttsProvider === 'local') {
      this.startLocalTts(speakText);
      return;
    }
    // ★ 0.232.0：云端优先（audioKey+audioModel 已配置）→ 失败回退本地 CoreSpeechKit（用户规则）
    // ★ 0.236.0：三引擎物理互斥（用户铁律）——ttsProvider='qianwen' 只发千问、'volcano'/'custom'
    //   只发火山系，哪怕另一引擎 Key 填得再全也绝不发请求；未配置/失败 → 本地兜底链不动
    const ctx = this.getUIContext().getHostContext();
    const cacheDir = ctx !== undefined && ctx !== null ? ctx.cacheDir : '';
    const useQwen = this.apiConfig.ttsProvider === 'qianwen';
    const cloudStarted = useQwen
      ? qianwenTts.speak(speakText, cacheDir, {
        onStart: () => {
          this.ttsLoadingMessageId = ''; // ⏳→🔊（首段开播）
        },
        onSynthesized: (chars: number, cached: boolean) => {
          this.onTtsSynthesized(chars, cached); // ★ 0.279.0：云端合成完成 SP 实扣（缓存命中免扣）
        },
        onComplete: () => {
          this.stopTTS(); // 全部段播完——恢复正常态
        },
        onError: (message: string) => {
          // 云端失败（网络/Key/音色）——本机语音兜底 + 轻提示（友好中文，规则#4）
          this.showToastSafe(`云端朗读失败，已切换本机语音（${message.substring(0, 60)}）`);
          this.startLocalTts(speakText);
        }
      })
      : cloudTts.speak(speakText, cacheDir, {
      onStart: () => {
        this.ttsLoadingMessageId = ''; // ⏳→🔊（首段开播）
      },
      onSynthesized: (chars: number, cached: boolean) => {
        this.onTtsSynthesized(chars, cached); // ★ 0.279.0：云端合成完成 SP 实扣（缓存命中免扣）
      },
      onComplete: () => {
        this.stopTTS(); // 全部段播完——恢复正常态
      },
      onError: (message: string) => {
        // 云端失败（网络/Key/资源）——本机语音兜底 + 轻提示（友好中文，规则#4）
        this.showToastSafe(`云端朗读失败，已切换本机语音（${message.substring(0, 60)}）`);
        this.startLocalTts(speakText);
      }
    });
    if (!cloudStarted) {
      // 未配置云端（audioKey/audioModel 空）——静默直落本地（用户规则：没配置就用本地）
      this.startLocalTts(speakText);
    }
  }

  // ★ 0.232.0：本地引擎朗读（云端未配置/失败的双路径汇入；0.189.0 管线原样）
  startLocalTts(speakText: string): void {
    localTts.speakText(speakText, {
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

  // ★ 0.279.0：云端 TTS 合成完成 SP 实扣（音频输出维度——SP 军令#2「凡 AI 交互必扣必展示」补口）。
  //   cached=true 缓存命中重播：零请求零计费静默（0.256.1）；本机语音档不进本方法（零成本）；
  //   失败/中断/回退本地不触发（引擎侧与结果缓存写点同源）；Lv8 司忆令免扣照报 f:y；
  //   余额不足 clamp 到 0 实扣（0.248.7 先例，播报不拦截）；toast 即时反馈消耗额。
  onTtsSynthesized(chars: number, cached: boolean): void {
    if (cached) {
      return;
    }
    const cost = spCostOfTts(chars);
    if (this.spFree()) {
      trackSpConsumeAuto(this.apiConfig.model, true, 0, 0, 0, 'tts');
      return;
    }
    const bal0 = siyiTotalSp(this.siyiStore);
    consumeSiyiSp(this.siyiStore, cost);
    const actual = bal0 - siyiTotalSp(this.siyiStore);
    trackSpConsumeAuto(this.apiConfig.model, false, actual, 0, 0, 'tts');
    this.showToastSafe(`音频输出 · 消耗 ${actual} SP`);
  }

  // 停止整个朗读会话（★ 0.232.0：云端+本地双引擎一起停，幂等，可安全重复调用；
  // ★ 0.236.0：千问引擎同列——三引擎一起停，幂等无害）
  stopTTS(): void {
    cloudTts.stop();
    qianwenTts.stop();
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


  // ★ 0.281.4：键盘让位自控（进/出对话页成对调用，防泄漏）——NONE 关掉系统避让，
  //   用 keyboardHeightChange 回调拿键盘高度（px→vp）驱动根容器 paddingBottom；
  //   离开页面恢复 OFFSET，其他页面行为与之前一致（0.281.2 全局 RESIZE 在 NavDestination 实测无效）
  private setupKbAvoid(): void {
    if (this.kbAvoidWin) {
      return; // 已注册（onShown 可能多次触发）
    }
    try {
      window.getLastWindow(getContext(this)).then((win: window.Window) => {
        this.kbAvoidWin = win;
        win.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
        this.kbAvoidCallback = (h: number): void => {
          this.kbAvoidHeight = h > 0 ? px2vp(h) : 0;
        };
        win.on('keyboardHeightChange', this.kbAvoidCallback);
      }).catch(() => {
        // 取窗口失败静默（沿用系统默认避让）
      });
    } catch (_e) {
      // 接口不可用静默
    }
  }

  private teardownKbAvoid(): void {
    try {
      if (this.kbAvoidWin && this.kbAvoidCallback) {
        this.kbAvoidWin.off('keyboardHeightChange', this.kbAvoidCallback);
        this.kbAvoidWin.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET);
      }
    } catch (_e) {
      // 注销失败静默
    }
    this.kbAvoidWin = null;
    this.kbAvoidCallback = null;
    this.kbAvoidHeight = 0;
  }

  aboutToAppear() {
    // ★ 0.196.4：isTablet 屏宽检测删除——改读 WindowMode 共享真相源（Index 根 onAreaChange 写入）
    this.deleteSkipConfirm = false; // ★ 0.150：重进对话页重置「不再提示」——每次会话首次删除仍弹确认（防误触）
    bindMemoryEngine(this.store, (): void => this.saveTree()); // ★ 0.265.0：记忆引擎绑定树引用+落盘通道（摘要头 flush 写回用）
    this.hasMouse = deviceInfo.deviceType === '2in1'; // ★ 0.247.2：PC 判定改设备形态（同步零误报，原 probeHasMouse 探测删除）
    this.bookmarkCache = this.getBookmarkEntry(); // ★ 0.191.0：首帧渲染前载入书签（标记线即时显示）
    this.foldStateView = new Map(chatFoldMemory); // ★ 0.234.0：恢复会话级折叠状态（切页面回来保留）
    // ★ 0.214.2：恢复缩放（持久化值优先；钳制防脏数据）
    this.fontScale = Math.min(1.6, Math.max(0.75, this.fontScaleStore.value));
    // ★ 0.214.2：恢复本气泡草稿（文字+图片——退出再回来继续编）
    const draftBubble = this.currentBubble;
    if (draftBubble) {
      this.inputText = draftBubble.draftText;
      this.imeComposing = false; // ★ 0.287.2：切气泡载草稿后按是否为空重新判定占位（组词态不跨气泡）
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
    this.teardownKbAvoid(); // ★ 0.281.4：注销键盘监听+恢复系统避让（防泄漏）
    this.saveDraft(); // ★ 0.214.2：草稿写回当前气泡内存
    this.saveTree(); // ★ 0.214.2：草稿随树落盘（一次）
    this.recordReadingPosition(); // ★ 0.191.0：离开前记录阅读高度（方案 A）
    if (this.inputBlurTimer >= 0) { // ★ 0.270.0：清 blur 宽限定时器，防泄漏
      clearTimeout(this.inputBlurTimer);
      this.inputBlurTimer = -1;
    }
    // ★ 0.271.0：思考计时器必清（防泄漏）；退出会话思维链/思考态自动清空（组件销毁 Map 随之回收）
    if (this.thinkingTimer >= 0) {
      clearInterval(this.thinkingTimer);
      this.thinkingTimer = -1;
    }
    // ★ 0.265.0 记忆引擎：会话结束触发画像更新（本段有新增用户消息才做）+ 失活节点入摘要头 pending 队列
    if (this.profileTick > 0) {
      this.triggerProfileUpdate();
      this.profileTick = 0;
    }
    noteInactiveNode(this.currentBubble);
    if (this.streamController) {
      this.streamController.cancel();
      this.streamController = null;
    }
    if (this.planController !== null) { // ★ 0.300.0：枢机/规划流兜底清理
      this.planController.cancel();
      this.planController = null;
    }
    this.abandonClarify(); // ★ 0.300.0：反问挂起链路随组件销毁静默死亡（防回调悬挂）
    this.contractByMsg.clear(); // 会话级契约随页销毁回收
    this.correctPendingByMsg.clear();
    this.stopTTS(); // ★ 0.133：退出对话页停止朗读（现有交互下切气泡必经 pop，一个钩子覆盖退页+切气泡两种情况）
    this.stopExtractTimer(); // ★ 0.153：组件销毁清除提炼计时器，防内存泄漏
    this.cleanupWebRender(); // ★ 0.286.1：渲染通道清理（清超时定时器+resolve 挂起 Promise+卸载隐形 Web，防泄漏）
    // ★ 0.249.3：查看器延迟关闭计时器随缩放/双击判定一起回滚删除，此处不再清理
  }

  // ★ 0.291.2：选择附件（原 selectImages 升级——用户拍板方案一：+号直接混选图片+文档，
  //   不加分菜单；DocumentViewPicker 文件管理器视角替代相册九宫格为已知情代价）。
  //   图片→base64 进 pendingImages（原链路不变）；文档→PendingDoc 进 pendingDocs（不进草稿）。
  //   合计上限 9（图+文）；云端格式 >6MB 选入即拦截。
  async selectAttachments(): Promise<void> {
    try {
      const room = 9 - this.pendingImages.length - this.pendingDocs.length;
      if (room <= 0) {
        this.showToastSafe('图片与文档合计最多 9 个');
        return;
      }
      const docPicker = new picker.DocumentViewPicker();
      const uris: Array<string> = await docPicker.select({
        maxSelectNumber: room,
        fileSuffixFilters: ATTACH_SUFFIX_FILTERS
      } as picker.DocumentSelectOptions);
      let imgsAdded = false;
      for (let i = 0; i < uris.length; i++) {
        const uri = uris[i];
        const name = decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1));
        const ext = docExtOf(name);
        if (isImageExt(ext)) {
          const dataUri = this.readImageToDataUri(uri);
          if (dataUri.length > 0) {
            this.pendingImages = [...this.pendingImages, dataUri];
            imgsAdded = true;
          }
        } else if (isDocExt(ext)) {
          let size = 0;
          const f = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
          try {
            size = fileIo.statSync(f.fd).size;
          } finally {
            fileIo.closeSync(f);
          }
          if (needsCloudParse(ext) && size > DOC_MAX_BYTES) {
            this.showToastSafe(`「${name}」超过 6MB，云端解析暂只支持 6MB 内文件，请拆分后再试`);
            continue;
          }
          this.pendingDocs = [...this.pendingDocs, new PendingDoc(name, ext, size, uri)];
        }
      }
      if (imgsAdded) {
        this.saveDraft(); // 0.214.2 图片变化实时写回草稿（文档 uri 会话级有效不落草稿）
      }
    } catch (err) {
      // 选择取消/读取失败静默忽略（防崩溃，原 selectImages 同策略）
    }
  }

  // ★ 0.297.0：画板回传消费（@Monitor 路径监听嵌套 @Trace 字段）——导出图挂待发区后清 store
  @Monitor('sketchResult.imageUri')
  onSketchResult(): void {
    const uri = this.sketchResult.imageUri;
    if (uri.length === 0) {
      return;
    }
    if (this.pendingImages.length + this.pendingDocs.length >= 9) {
      // 防御性满格守卫（画板入口已拦；弹页期间附件被拖满的竞态兜底）
      this.showToastSafe('待发区已有 9 个附件，请先删除再添加');
      this.sketchResult.imageUri = '';
      return;
    }
    this.pendingImages = [...this.pendingImages, uri];
    this.saveDraft(); // 图片变化实时写回草稿（selectAttachments 同策略）
    this.sketchResult.imageUri = '';
    this.showToastSafe('已加入待发区');
  }

  // ★ 0.297.0：进画板（满格守卫——9 格附件流已满时提示先删除）
  openSketchBoard(): void {
    if (this.pendingImages.length + this.pendingDocs.length >= 9) {
      this.showToastSafe('待发区已有 9 个附件，请先删除再添加');
      return;
    }
    this.pathStack.pushPath({ name: 'SketchPage' });
  }

  // 从 uri 读图转 data URI（与原 selectImages 内联读法一致——读失败返回空串）
  readImageToDataUri(uri: string): string {
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      try {
        const stat = fileIo.statSync(file.fd);
        const arrayBuffer = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, arrayBuffer);
        return `data:image/jpeg;base64,${buffer.from(arrayBuffer).toString('base64')}`;
      } finally {
        fileIo.closeSync(file);
      }
    } catch (_e) {
      return '';
    }
  }

  // 删除待发送文档
  removeDoc(index: number): void {
    const newList: PendingDoc[] = [];
    for (let i = 0; i < this.pendingDocs.length; i++) {
      if (i !== index) {
        newList.push(this.pendingDocs[i]);
      }
    }
    this.pendingDocs = newList;
  }

  // ★ 0.291.2：文档后缀徽章缩写（纯 UI 辅助）
  docBadgeOf(ext: string): string {
    if (ext === 'pdf') {
      return 'PDF';
    }
    if (ext === 'docx' || ext === 'doc') {
      return 'DOC';
    }
    if (ext === 'xlsx') {
      return 'XLS';
    }
    if (ext === 'md') {
      return 'MD';
    }
    return 'TXT';
  }

  // ★ 0.291.2：云端文档超 2MB 强确认（Promise 弹窗——复刻 confirmSendImageToTextModel 模式；
  //   取消=待发区保留文档由用户自行删改）
  confirmBigDocParse(name: string): Promise<boolean> {
    return new Promise<boolean>((resolve: (v: boolean) => void) => {
      this.getUIContext().showAlertDialog({
        title: '文件较大',
        message: `「${name}」超过 2MB，页数较多时解析费用较高（约 0.04 元/页，折算并入输入 SP 消耗）。是否继续解析并发送？`,
        primaryButton: {
          value: '取消',
          action: () => {
            resolve(false);
          }
        },
        secondaryButton: {
          value: '继续发送',
          action: () => {
            resolve(true);
          }
        }
      });
    });
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

  // ============================================================
  // ★ 0.275.0 PC 输入框图片直载（用户需求：Ctrl+V 粘贴剪贴板图片 + 拖拽图片进输入框）
  //   与选图器同链路（图源 → base64 data URI → pendingImages），发送/草稿/预览链零新增改动
  // ============================================================

  // 从 uri 读图入待发区（拖拽 File/Image 记录、剪贴板 uri 记录共用；与 selectAttachments 同读法）
  async addImageFromUri(uri: string): Promise<boolean> {
    if (this.pendingImages.length + this.pendingDocs.length >= 9) { // ★ 0.291.2：图+文合计口径
      this.showToastSafe('图片与文档合计最多 9 个');
      return false;
    }
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      const arrayBuffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, arrayBuffer);
      fileIo.closeSync(file);
      const base64 = buffer.from(arrayBuffer).toString('base64');
      this.pendingImages = [...this.pendingImages, `data:image/jpeg;base64,${base64}`];
      this.saveDraft();
      return true;
    } catch (err) {
      this.showToastSafe('图片读取失败，请重试');
      return false;
    }
  }

  // 剪贴板 PixelMap（截图场景）打包 JPEG 入待发区（对齐 0.211.1 压缩档：q80 控制落盘体积）
  async addPixelMapImage(pm: image.PixelMap): Promise<void> {
    if (this.pendingImages.length + this.pendingDocs.length >= 9) { // ★ 0.291.2：图+文合计口径
      this.showToastSafe('图片与文档合计最多 9 个');
      return;
    }
    try {
      const packer = image.createImagePacker();
      const opts: image.PackingOption = { format: 'image/jpeg', quality: 80 };
      const packed = await packer.packToData(pm, opts);
      packer.release();
      const base64 = buffer.from(packed).toString('base64');
      this.pendingImages = [...this.pendingImages, `data:image/jpeg;base64,${base64}`];
      this.saveDraft();
      this.showToastSafe('已粘贴图片');
    } catch (err) {
      this.showToastSafe('图片粘贴失败，请重试');
    }
  }

  // ★ 0.283.0：READ_PASTEBOARD 运行时授权链（user_grant 级——装机 grantStatus=-1，首次读取前
  //   须弹窗一次；requestPermissionsFromUser 对已授权权限直接返回不重复弹窗）。
  //   被拒分支=toast 手动路径说明 + requestPermissionOnSetting 直达权限面板（0.259.2 同款模式：
  //   专治「用户拒绝过系统不再弹窗」，用户在面板开了权限当场继续贴图）
  async ensurePastePermission(): Promise<boolean> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const atm = abilityAccessCtrl.createAtManager();
      const result = await atm.requestPermissionsFromUser(ctx, ['ohos.permission.READ_PASTEBOARD']);
      if (result.authResults.length > 0 &&
        result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return true;
      }
      // 被拒：toast 说明 + 直达权限面板（面板上开了→本次贴图不中断，下次 Ctrl+V 生效）
      this.showToastSafe('未授权：请在系统「设置→应用→DAG AI Chat→权限」允许「剪贴板」');
      try {
        const panelResult = await atm.requestPermissionOnSetting(ctx, ['ohos.permission.READ_PASTEBOARD']);
        return panelResult.length > 0 &&
          panelResult[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
      } catch (_e) {
        return false;
      }
    } catch (_e) {
      return false;
    }
  }

  // Ctrl+V 贴图读取（★ 0.283.0 恢复纯 Ctrl+V 方案——新调试 Profile ACL 已授权 READ_PASTEBOARD，
  //   module.json5 已声明，装机即具申请资格；0.275.0 注释的 PasteButton 通道不再需要）：
  //   pixelMap 优先（截图场景）、uri 次之（图库/文件管理器复制的图片）；无图分寸=silent 时静默
  //   （Ctrl+V 旁路调用=纯文本粘贴场景，弹「没有图片」会骚扰正常粘贴）
  async pasteImageFromClipboard(silent: boolean = false): Promise<void> {
    if (this.ctrlVPasting) {
      return;
    }
    this.ctrlVPasting = true;
    try {
      const granted = await this.ensurePastePermission();
      if (!granted) {
        return; // 未授权：ensurePastePermission 已 toast+拉面板，此处静默退出
      }
      const data = await pasteboard.getSystemPasteboard().getData();
      const count = data.getRecordCount();
      for (let i = 0; i < count; i++) {
        const rec = data.getRecordAt(i);
        if (rec.pixelMap !== undefined && rec.pixelMap !== null) {
          await this.addPixelMapImage(rec.pixelMap);
          return;
        }
        if (rec.uri !== undefined && rec.uri !== null && rec.uri.length > 0) {
          const ok = await this.addImageFromUri(rec.uri);
          if (ok) {
            this.showToastSafe('已粘贴图片');
          }
          return;
        }
      }
      if (!silent) {
        this.showToastSafe('剪贴板中没有图片');
      }
    } catch (err) {
      this.showToastSafe('图片粘贴失败，请重试');
    } finally {
      this.ctrlVPasting = false;
    }
  }

  // 拖拽落点：UDMF 记录流收集全部 Image uri（多选拖入全收，与选图器同上限 9 张截断）
  handleDropImages(event: DragEvent): void {
    try {
      const udata: unifiedDataChannel.UnifiedData = event.getData();
      const records: Array<unifiedDataChannel.UnifiedRecord> = udata.getRecords();
      const uris: string[] = [];
      for (let i = 0; i < records.length; i++) {
        const rec = records[i];
        if (rec instanceof unifiedDataChannel.Image) {
          const uri = rec.imageUri.length > 0 ? rec.imageUri : rec.uri;
          if (uri.length > 0) {
            uris.push(uri);
          }
        }
      }
      if (uris.length === 0) {
        this.showToastSafe('仅支持拖入图片');
        return;
      }
      // ★ 0.275.2 多张拖入（用户拍板：最多 9 张对齐选图器，超出截前 9 张+提示删了再拖）；
      //   ★ 0.291.2 合计口径（图+文档共享 9 席）
      const room = 9 - this.pendingImages.length - this.pendingDocs.length;
      if (room <= 0) {
        this.showToastSafe('待发区已有 9 个附件，请先删除再拖入');
        return;
      }
      const take = Math.min(uris.length, room);
      let added = 0;
      let done = false;
      const addNext = (idx: number): void => {
        if (done) {
          return;
        }
        if (idx >= take) {
          done = true;
          if (uris.length > room) {
            this.showToastSafe(`图片较多，已添加前 ${added} 张（上限 9 张）`);
          } else {
            this.showToastSafe(`已添加 ${added} 张图片`);
          }
          return;
        }
        this.addImageFromUri(uris[idx]).then((ok: boolean) => {
          if (ok) {
            added++;
          }
          addNext(idx + 1);
        });
      };
      addNext(0);
    } catch (err) {
      this.showToastSafe('拖入内容无法读取');
    }
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
    // ★ 0.287.0：撤销快照（删除消息入栈——闭包只捕获应用级单例+数据，不捕获页面 this；
    //   undo 按 nodeID 回 nodeList 找 live 对象（0.244 流式写穿同款防御——云同步 reconcile 整体
    //   替换 store.nodeList 后旧引用写入=孤儿失效），气泡没了=放弃撤销无害）
    const delNodeId = this.currentBubble.nodeID;
    const delIdx = this.currentBubble.messages.findIndex((m: ChatMessage): boolean => m.messageId === messageId);
    const delMsg = delIdx >= 0 ? this.currentBubble.messages[delIdx] : null;
    this.currentBubble.messages = this.currentBubble.messages.filter(m => m.messageId !== messageId);
    this.saveTree(); // ★ 0.151：按模式分池保存
    if (delIdx >= 0 && delMsg !== null) {
      const store = this.store;
      const cms = this.canvasModeStore;
      const tf = this.tabForest;
      const pd = this.persistData;
      this.undoStack.push('删除消息',
        (): void => {
          const live = store.nodeList.find((n: BubbleNode): boolean => n.nodeID === delNodeId);
          if (live === undefined) {
            return;
          }
          const arr = [...live.messages];
          arr.splice(Math.min(delIdx, arr.length), 0, delMsg);
          live.messages = arr;
          saveBubbleTreePools(store, cms, tf, pd, upsertCloudData);
        },
        (): void => {
          const live = store.nodeList.find((n: BubbleNode): boolean => n.nodeID === delNodeId);
          if (live === undefined) {
            return;
          }
          live.messages = live.messages.filter((m: ChatMessage): boolean => m.messageId !== messageId);
          saveBubbleTreePools(store, cms, tf, pd, upsertCloudData);
        });
    }
  }

  // ============================================================
  // ★ 0.286.0：AI 内容举报（华为上架合规 G.3.8——AI 对话模块需显著举报入口；
  //   链路复刻 0.253.0 openComplaintMail：mailto 预填 + 无邮件应用降级复制邮箱）
  // ============================================================

  // flag 按钮 → 本地确认弹窗（防误触；正文自动附模型 ID 便于追溯）
  requestReportMessage(model: string): void {
    this.reportTargetModel = model;
    this.reportConfirmVisible = true;
  }

  // 确认举报 → 拉起邮件（主题/正文预填；失败降级复制邮箱 + toast，禁止展示原始英文报错）
  confirmReportMessage(): void {
    this.reportConfirmVisible = false;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const modelLabel = this.reportTargetModel.length > 0 ? this.reportTargetModel : '未知模型';
    this.reportTargetModel = '';
    if (context === undefined || context === null) {
      this.copyReportEmail();
      return;
    }
    const subject = encodeURIComponent('DAGAI AI 内容举报');
    const body = encodeURIComponent(
      `举报对象：AI 生成的回复内容\n涉及模型：${modelLabel}\n举报描述：\n\n（请描述违规内容及发生位置，可附截图）`);
    const url = `mailto:1725912449@qq.com?subject=${subject}&body=${body}`;
    try {
      context.openLink(url).catch(() => {
        this.copyReportEmail();
        this.showToastSafe('未找到邮件应用，邮箱已复制请手动发送');
      });
    } catch (_e) {
      this.copyReportEmail();
      this.showToastSafe('未找到邮件应用，邮箱已复制请手动发送');
    }
  }

  // 降级：复制举报邮箱到剪贴板
  copyReportEmail(): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, '1725912449@qq.com');
      pasteboard.getSystemPasteboard().setData(data).catch(() => {});
      this.showToastSafe('邮箱已复制');
    } catch (_e2) {
      this.showToastSafe('复制失败，请手动记录邮箱');
    }
  }

  // ============================================================
  // ★ 0.286.1：AI 读网页渲染通道（WebFetchUtil 壳判定的 webRenderer 实现——
  //   隐形 Web 组件真渲染 SPA 文档站，注入脚本取 innerText；串行队列+15s 超时+轮询等渲染）
  // ============================================================

  // 对外入口：渲染一页取正文文本（失败 reject 中文 Error；组件按需挂载，队列空卸载）
  renderUrlViaWeb(url: string): Promise<string> {
    return new Promise<string>((resolve: (v: string) => void, reject: (e: Error) => void) => {
      this.webRenderQueueUrls.push(url);
      // 包一层：渲染失败走 reject（resolve 仅成功出文）——超时/异常统一收口 finishWebRender
      this.webRenderQueueResolvers.push((v: string) => {
        if (v.length > 0) {
          resolve(v);
        } else {
          reject(new Error('网页渲染读取失败'));
        }
      });
      this.webRenderActive = true; // 触发挂载（已挂载时无副作用）
      this.tryStartNextWebRender();
    });
  }

  // 空闲且队列有货 → 起下一页（controller 未 attached 时等 onControllerAttached 回调再起）
  tryStartNextWebRender(): void {
    if (this.webRenderCurrentUrl.length > 0 || this.webRenderQueueUrls.length === 0) {
      return;
    }
    if (!this.webRenderControllerReady) {
      return; // 等 Web 组件 onControllerAttached
    }
    this.webRenderCurrentUrl = this.webRenderQueueUrls.shift() as string;
    this.webRenderPollCount = 0;
    // 整页超时兜底（含加载+渲染轮询全程）：到点取已有内容（短也用）否则失败
    this.webRenderTimeoutId = setTimeout(() => {
      this.finishWebRender('');
    }, 15000);
    try {
      this.webRenderController.loadUrl(this.webRenderCurrentUrl);
    } catch (_le) {
      this.finishWebRender(''); // loadUrl 异常（组件异常态）直接失败收口
    }
  }

  // onPageEnd → 轮询取文（SPA 数据异步到——首轮延 800ms 再取，不足 300 字再等）
  onWebRenderPageEnd(): void {
    if (this.webRenderCurrentUrl.length === 0 || this.webRenderPolling) {
      return;
    }
    this.pollWebRenderText();
  }

  pollWebRenderText(): void {
    this.webRenderPolling = true;
    setTimeout(() => {
      this.webRenderPolling = false;
      if (this.webRenderCurrentUrl.length === 0) {
        return; // 已被超时/外部收口
      }
      this.runWebRenderScript();
    }, this.webRenderPollCount === 0 ? 800 : 1000);
  }

  // 注入脚本取 title+innerText（runJavaScript 回调结果为 JSON 字符串）
  runWebRenderScript(): void {
    const script = '(function(){var t=document.title||"";var b=(document.body&&document.body.innerText)?document.body.innerText:"";return JSON.stringify(t+"\\n"+b);})()';
    try {
      this.webRenderController.runJavaScript(script)
        .then((result: string) => {
          if (this.webRenderCurrentUrl.length === 0) {
            return;
          }
          let text = '';
          try {
            text = JSON.parse(result) as string;
          } catch (_pe) {
            text = result; // 非 JSON 包装（理论不至）——原样兜底
          }
          const bodyPart = text.length > 0 ? text : '';
          if (bodyPart.trim().length >= 300) {
            this.finishWebRender(bodyPart); // 正文足量——收工
          } else if (this.webRenderPollCount < 5) {
            this.webRenderPollCount += 1;
            this.pollWebRenderText(); // SPA 还在出文——再等一轮
          } else {
            // 轮询用尽：有字给字（总比没有好），没字失败
            this.finishWebRender(bodyPart.trim().length > 0 ? bodyPart : '');
          }
        })
        .catch(() => {
          if (this.webRenderCurrentUrl.length === 0) {
            return;
          }
          if (this.webRenderPollCount < 5) {
            this.webRenderPollCount += 1;
            this.pollWebRenderText();
          } else {
            this.finishWebRender('');
          }
        });
    } catch (_re) {
      this.finishWebRender('');
    }
  }

  // 单页收口：出队 resolve、清超时、空闲则起下一页或卸载组件
  finishWebRender(text: string): void {
    if (this.webRenderTimeoutId >= 0) {
      clearTimeout(this.webRenderTimeoutId);
      this.webRenderTimeoutId = -1;
    }
    const resolve = this.webRenderQueueResolvers.shift();
    this.webRenderCurrentUrl = '';
    this.webRenderPollCount = 0;
    if (resolve !== undefined) {
      resolve(text);
    }
    if (this.webRenderQueueUrls.length > 0) {
      this.tryStartNextWebRender();
    } else {
      this.webRenderActive = false; // 队列空——卸载 Web 组件（不常驻占内存）
      this.webRenderControllerReady = false; // 卸载后 controller 失效——重挂载等 onControllerAttached 再置位
    }
  }

  // 页面销毁兜底：清定时器、resolve 挂起 Promise（防泄漏——组件销毁后回调不再可靠）
  cleanupWebRender(): void {
    if (this.webRenderTimeoutId >= 0) {
      clearTimeout(this.webRenderTimeoutId);
      this.webRenderTimeoutId = -1;
    }
    while (this.webRenderQueueResolvers.length > 0) {
      const r = this.webRenderQueueResolvers.shift();
      if (r !== undefined) {
        r('');
      }
    }
    this.webRenderQueueUrls = [];
    this.webRenderCurrentUrl = '';
    this.webRenderActive = false;
    this.webRenderControllerReady = false;
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
      // ★ 0.235.0 修法 A：取消选择回调（0,0 / -1,-1 形态）纳入清理链路——原直接 return 全押 onDisappear，
      //   手机端 onDisappear 不触发/晚触发时 selKey 残留、系统高亮滞留 → 两段同时高亮（用户实锤截图）；
      //   sticky 三副本仍不清（0.191.0 表格粘性语义不回归，见下）
      if (this.selKey.length > 0) {
        this.clearSelectionState();
      }
      return;
    }
    // ★ 0.235.0：换段选择时显式关闭旧段菜单——长按 B 段时 A 段菜单/高亮由系统取消回调清理（修法 A），
    //   但 A 段悬浮菜单若未被系统联动收起，此处主动关（closeSelectionMenu 只作用自己绑定的 Text）
    if (this.selKey.length > 0 && this.selKey !== key) {
      const oldCtrl = this.textControllers.get(this.selKey);
      oldCtrl?.closeSelectionMenu();
    }
    this.selKey = key;
    this.lastSelKey = key; // ★ 0.235.0 修法 B：key 副本（clearSelectionState 不清理）
    this.selText = content.substring(start, end);
    this.selStart = start; // ★ 0.191.0：记录偏移供划词级书签
    this.selEnd = end;
    // ★ 0.191.0：粘性区间——表格在横向 Scroll 内拖选时手势冲突会触发菜单消失重弹，
    //   onDisappear 清掉 selStart/selEnd 后点「标记」误报「请划选文字」（用户实测 bug）；
    //   粘性副本不被清理，点击时同 key 兜底恢复
    this.stickySelKey = key;
    this.stickyStart = start;
    this.stickyEnd = end;
    this.stickySelText = this.selText; // ★ 0.285.5：文本粘性副本（selText 清空后 effectiveSelText 兜底）
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

  // ★ 0.285.5：有效选中文本（selText 优先；被 clearSelectionState 误清时 lastSelKey 与
  //   粘性副本配对兜底——表格跨格拖选/菜单消失重弹场景 Ctrl+Shift+C/复制/翻译三消费点共用）
  effectiveSelText(): string {
    if (this.selText.length > 0) {
      return this.selText;
    }
    if (this.lastSelKey.length > 0 && this.stickySelKey === this.lastSelKey) {
      return this.stickySelText;
    }
    return '';
  }

  // 关闭当前激活 Text 的选择菜单（悬浮栏按钮点击后调用）
  // ★ 0.235.0 修法 B：selKey 为空（onDisappear 先行清空）但系统菜单残留时，退用 lastSelKey 副本兜底关闭
  closeActiveSelectionMenu(): void {
    const key = this.selKey.length > 0 ? this.selKey : this.lastSelKey;
    if (key.length > 0) {
      const ctrl = this.textControllers.get(key);
      ctrl?.closeSelectionMenu();
    }
  }

  // ============================================================
  // ★ 0.145：悬浮操作栏按钮（翻译 | 复制 | 全选）
  // ============================================================

  // 「翻译」：关闭菜单 → 打开浮窗 → 发起 AI 查词（独立请求，不建气泡、不进 DAG）
  onToolbarTranslate(): void {
    // ★ 0.248.3：划词翻译守卫（上架合规——翻译走 AI 查词，未登录拦截）
    if (!requireLoginForCloud()) {
      return;
    }
    // ★ 0.293.0：SP 云同步门卫（翻译扣 SP——账本云端对齐才放行）
    if (!requireSiyiGate()) {
      return;
    }
    const text = this.effectiveSelText().trim(); // 先取值——closeSelectionMenu 可能同步触发 onDisappear 清空状态（0.285.5 粘性兜底）
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
    this.wordPopupInTok = 0;   // ★ 0.272.0：新查询清零（上一轮用量不带入）
    this.wordPopupOutTok = 0;
    this.wordPopupSpText = '';
    this.refreshWordPopupReview(); // ★ 0.246.0：浮窗司忆区——打开时抽一批固定（查词等待期顺便学习）
    if (this.wordQueryController) {
      this.wordQueryController.cancel(); // 上一次查词未完成 → 取消
    }
    this.wordQueryController = queryWord(text, this.apiConfig,
      (result: WordQueryResult) => {
        this.wordPopupLoading = false;
        this.wordPopupResult = result;
        completeRookieTask('word_translate'); // ★ 0.294.0：新手任务②划词翻译——结果到达即算一次
      },
      (error: string) => {
        this.wordPopupLoading = false;
        this.wordPopupError = error;
      },
      // ★ 0.272.0：token 用量透传——实扣 SP（scene='word'）+ 信息卡数据；失败/取消路径不回调（零扣费铁律）；
      //   事后实扣不足 clamp 到 0（0.248.7 先例——划词即查无确认步骤，不加事前闸门防打断）
      (inputTokens: number, outputTokens: number, cachedTokens: number) => {
        this.wordPopupInTok = inputTokens;
        this.wordPopupOutTok = outputTokens;
        const cost = spCostOfTokens(inputTokens, outputTokens, cachedTokens);
        if (this.spFree()) {
          this.wordPopupSpText = 'Lv8 免费';
          trackSpConsumeAuto(this.apiConfig.model, true, 0, inputTokens, cachedTokens, 'word', outputTokens);
          return;
        }
        consumeSiyiSp(this.siyiStore, cost);
        this.wordPopupSpText = `消耗 ${cost} SP`;
        trackSpConsumeAuto(this.apiConfig.model, false, cost, inputTokens, cachedTokens, 'word', outputTokens);
      });
  }

  // ★ 0.285.2（华为官方范式）：剪贴板同一时间只支持一个复制操作——失败立即重试大概率再冲突，
  //   改「await + 延迟 300ms 重试（上限 2 次）+ 每次重新构造 PasteData」；成功/失败 toast 反馈。
  //   写剪贴板零权限（0.279.0 华为官方答复）。
  async copyTextToClipboard(text: string, retry: number = 0): Promise<boolean> {
    if (text.length === 0) {
      return false;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      this.showToastSafe('已复制');
      return true;
    } catch (e) {
      if (retry < 2) {
        await new Promise<void>((resolve: () => void) => {
          setTimeout(resolve, 300); // 延迟重试，避开并发复制冲突窗口
        });
        return this.copyTextToClipboard(text, retry + 1);
      }
      this.showToastSafe('复制失败，请重试');
      return false;
    }
  }

  // 「复制」：选中文本写入系统剪贴板
  onToolbarCopy(): void {
    const text = this.effectiveSelText(); // 先取值（同上；0.285.5 粘性兜底）
    this.closeActiveSelectionMenu();
    if (text.length === 0) {
      return;
    }
    this.copyTextToClipboard(text);
  }

  // ★ 0.235.2：复制全文——消息操作行按钮（AI 消息 stripAnchorMarks 剥锚点标记防污染剪贴板，
  //   用户消息原文直取）；成功 toast「已复制全文」，失败静默（与 onToolbarCopy 同口径）
  copyFullMessage(msg: ChatMessage): void {
    const text = msg.role === 'assistant' ? stripAnchorMarks(msg.content, false) : msg.content;
    if (text.length === 0) {
      return;
    }
    // ★ 0.300.0：交付型复制=北极星正信号（sishu_copy——交付型核心正信号，任务书 §七）
    if (msg.role === 'assistant' && this.deliverMsgIds.includes(msg.messageId)) {
      const c = this.contractByMsg.get(msg.messageId);
      const cp: Record<string, string> = {};
      cp['taskType'] = c !== undefined ? c.taskType : '';
      cp['genre'] = c !== undefined ? c.genre : '';
      track(this.getUIContext().getHostContext() as common.Context, 'sishu_copy', cp);
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.showToastSafe('已复制全文');
      }).catch((err: Error) => {
        // 写入失败静默忽略
      });
    } catch (e) {
      // 复制异常静默忽略（防崩溃）
    }
  }

  // ★ 0.238.0：模型显示文本——别名优先（消息模型与当前配置模型一致且别名非空），否则官方模型 ID；
  //   拼接 token 统计（两段信息合并单一滑动区，格式「别名或模型ID · 输入 N · 输出 N」）
  //   ★ 0.240.1：别名读 map 兜底——apiConfig.modelAlias 水合在旧快照上读侧丢（0.224.1 家族），
  //   别名映射表（model-alias-v1）读写健在且为最全真相源（输入即记录）；两源取非空者
  // ★ 0.247.2：模型名改静态死文字——上线后统一由 DeepSeek-V4.1-Flash 服务用户，
  //   不再跟随全局设置 apiConfig.model 动态显示（用户拍板「直接静态」）；
  //   AIGC 标识文案暂不拼接（后续另定落点再加）
  topBarModelText(): string {
    return 'DeepSeek-V4.1-Flash';
  }

  // ★ 0.247.0：原 modelDisplayText 改名 tokenDisplayText——模型名上移顶栏（合规标识），消息行只留 token 统计。
  // msg.model 等字段不动（数据无损，仅展示变化）；无 token（outputTokens=0）返回空串，调用点条件同步收紧
  // ★ 0.247.7：明细行改 SP 单位（用户拍板「输入输出加上 SP 单位」+「预估」前缀）；
  //   ★ 0.247.7：改**实扣口径**（V2.0 商业方案，0.247.7 已随 1000292 上机——原注释误标 0.247.8 现更正），
  //   输出=×4 倍系数（输出单价是输入 4 倍，统一系数会亏 3/4）；★ 0.247.8：明细行去「预估」前缀、
  //   估算语义挪到缓存节省行「预估节省」（用户拍板——4 行收 2 行排版，弹层 216→272 同批）
  tokenDisplayText(msg: ChatMessage): string {
    if (msg.outputTokens <= 0) {
      return '';
    }
    if (this.spFree()) { // ★ 0.249.0：Lv8 司忆令免扣——明细行同步免费标识（展示与实扣一致军令：显示扣多少就扣多少，免费就显示免费）
      return '司忆令 · 本轮免费';
    }
    const hit = Math.min(msg.cacheHitTokens, msg.inputTokens);
    const miss = msg.inputTokens - hit;
    const inSp = Math.round((miss * SP_INPUT_PRICE_RATIO + hit * SP_HIT_PRICE_RATIO) / SP_TOKEN_DIVISOR * SP_COST_MULTIPLIER);
    const outSp = Math.round(msg.outputTokens * SP_OUTPUT_PRICE_RATIO / SP_TOKEN_DIVISOR * SP_COST_MULTIPLIER);
    // ★ 0.279.10：思考 SP 已含在输出数值内，不单独标注（用户拍板——只让用户看输入/输出两个总数）
    return `输入 ${inSp} SP · 输出 ${outSp} SP`; // ★ 0.247.8：去「预估」前缀（用户拍板——明细行省字，预估语义挪到缓存节省行）
  }

  // ★ 0.248.7：本次 AI 调用实扣 SP（与 tokenDisplayText 同公式同口径——明细行显示多少、账户就扣多少，
  //   展示与扣点永远一致）；★ 0.272.0：公式抽 common/ChatModel.spCostOfTokens 单一真相源，本方法薄壳化
  spCostOf(msg: ChatMessage): number {
    return spCostOfTokens(msg.inputTokens, msg.outputTokens, msg.cacheHitTokens);
  }

  // ★ 0.249.0：Lv8 司忆令免扣判定（用户拍板「SP 永久免费」）——learnDays=累计学习天数（cfg:stat-days
  //   云同步多端一致，只增不减、达成后免扣状态永不回退）；两处发送闸门+两处实扣+明细行统一走此封装
  spFree(): boolean {
    return isSiyiSpFree(getStatDays(this.statStore).length);
  }

  // ★ 0.260.0：sp_consume 埋点（与 consumeSiyiSp 实扣同点双写——0.259.0 本地统计外再加云端上报）：
  //   免扣账号照报 f:y（sp=0，成本红线要真实 token/命中率/余额）；h=缓存命中率%（cached/input，输入 0 防除零）
  //   ★ 0.272.0：实现抽 common/ChatModel.trackSpConsumeAuto（word/extract/encourage 新场景共用），薄壳化
  trackSpConsume(msg: ChatMessage, free: boolean, actualSp: number, inputTokens: number, cachedTokens: number, scene: string, outputTokens: number): void {
    trackSpConsumeAuto(msg.model, free, actualSp, inputTokens, cachedTokens, scene, outputTokens);
  }

  // ★ 0.247.3：token 明细弹层 builder（感叹号弹出）——无参 @Builder 直读 tokenInfoText 快照；
  //   ★ 0.247.4：命中缓存的回复追加「缓存命中 X% · 预估节省 N SP」行（节省算法见 SP_CACHE_SAVING_RATIO；0.247.8「帮你」→「预估」）；
  //   ★ 0.247.5：用户实测默认弹层太素难看——改自绘卡片容器（this.theme.surfaceNode 底+this.theme.strokeCard 描边+radius 12，
  //   padding 对齐知识库菜单 12/16），popupColor 透明由 builder 全掌控；缓存行走品牌紫突出省钱信息
  @Builder
  tokenInfoBuilder() {
    Column() {
      Text(this.tokenInfoText)
        .fontSize(13)
        .fontColor(this.theme.textPrimary)
        .textAlign(TextAlign.Center)
        .width('100%')
      if (this.tokenInfoCacheLine.length > 0) {
        Divider()
          .color(this.theme.strokeCard)
          .margin({ top: 9, bottom: 9 })
        Text(this.tokenInfoCacheLine)
          .fontSize(13)
          .fontColor(this.tokenInfoCacheHit ? this.theme.brandSecondary : this.theme.textPrimary) // ★ 0.248.7：命中=品牌紫省钱高亮 / 未命中=普通色
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      // ★ 0.269.0：伴读编排拆分行（Q9——「内容生成 X SP + 伴读编排 Y SP」明细透明拆分；空串不渲染）
      if (this.tokenInfoHookLine.length > 0) {
        Divider()
          .color(this.theme.strokeCard)
          .margin({ top: 9, bottom: 9 })
        Text(this.tokenInfoHookLine)
          .fontSize(13)
          .fontColor(this.theme.brandSecondary)
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      // ★ 0.279.8：音频输入/输出说明行暂时下线（待腾讯云音频接入后再补回本弹层）
    }
    .width(272) // ★ 0.247.6：定宽——Divider 无固有宽会把无约束 Column 撑满整行（0.239.0 同款坑：弹层被拉成全宽条），定宽+文字居中收口；★ 0.247.8：216→272（用户拍板「拉宽一点」——两行文字各自单行显示，4 行收 2 行）
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .borderRadius(12)
    .border({ width: 1, color: this.theme.strokeCard })
    .backgroundColor(this.theme.surfaceNode)
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
  // ★ 0.235.0：划词引用——选中内容挂输入区，发送时注入 prompt
  // ============================================================

  // 引用按钮显示条件：仅消息正文划词（用户消息/AI 段/折叠视图段）。
  // 放大弹窗（cz 代码 / tzh·tzr 表格，无消息挂靠）与复习区 key（rw*/rk* 段前缀）不显示（需求 Q9）
  isQuoteTargetKey(key: string): boolean {
    const sep = key.indexOf('|');
    if (sep <= 0) {
      return false; // 表格放大弹窗 key（tzh*/tzr*，无 | 分隔）
    }
    const messageId = key.substring(0, sep);
    if (messageId === 'cz') {
      return false; // 代码放大弹窗内文本
    }
    const segPart = key.substring(sep + 1);
    if (segPart.startsWith('rw') || segPart.startsWith('rk')) {
      return false; // 复习区 key 防御性排除（ReviewSelectionToolbar 本无引用，兜底防误绑）
    }
    return true;
  }

  // 引用栏/弹窗短标签：前 5 字符 + 省略号（换行拍平为空格；用户拍板不铺满全文）
  quoteShortLabel(): string {
    const t = this.quoteText.length > 0 ? this.quoteText : this.quotePendingText;
    const flat = t.replace(/\n/g, ' ');
    return flat.length > 5 ? `${flat.substring(0, 5)}…` : flat;
  }

  // 「引用」：先取值再关菜单（同 onToolbarTranslate 模式——closeSelectionMenu 可能同步触发 onDisappear 清状态），
  // 暂存 quotePendingText 后弹二选一；取消则丢弃不生效
  onToolbarQuote(): void {
    const text = this.effectiveSelText().trim(); // 0.285.5 粘性兜底（同上族）
    this.closeActiveSelectionMenu();
    if (text.length === 0) {
      return;
    }
    this.quotePendingText = text;
    this.quotePickerVisible = true;
  }

  // 二选一确认：false=引用到本聊天（挂当前输入区）；true=创建新子气泡并进入，引用带入其输入区
  // （复用 addBubble 成熟链路：ID/父子关系/埋点/保存/过渡动画全带，0.214.2 carryText/carryImages 同款第三参 carryQuote）
  confirmQuote(asNewChild: boolean): void {
    const text = this.quotePendingText;
    this.quotePickerVisible = false;
    this.quotePendingText = '';
    if (text.length === 0) {
      return;
    }
    if (asNewChild) {
      this.addBubble([], '', text);
    } else {
      this.quoteText = text;
    }
  }

  // 取消二选一（点遮罩/取消/返回键）——丢弃暂存
  cancelQuotePicker(): void {
    this.quotePickerVisible = false;
    this.quotePendingText = '';
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
  // ★ 0.222.21：检测改首字符判定（与 queryWord 方向检测同源——首字符中文=中翻英，播英文译文）
  wordPopupSpeakText(): string {
    const r = this.wordPopupResult;
    if (r !== null && startsWithChinese(this.wordPopupQuery) && r.explain.length > 0) {
      return r.explain;
    }
    return wordSpeaker.textFor(this.wordPopupQuery, r !== null ? r.fullName : '');
  }

  // 「加入单词库」：★ 0.222.21 起弹目标文件夹选择弹窗（用户拍板——加词必须选归入哪个文件夹，
  // UI 与单词库移动/复制弹窗同款）；单词库无任何文件夹时不弹、直接入根目录（无选择可言，行为与旧版一致）。
  // 查词结果转 WordItem 的真正入库落点在 confirmAddWordToFolder。
  addCurrentWordToBank(): void {
    if (this.wordPopupResult === null) {
      return;
    }
    if (this.wordBank.folders.length === 0) {
      this.confirmAddWordToFolder('');
      return;
    }
    this.wordFolderPickerVisible = true;
  }

  // ★ 0.222.21：确认加词到目标文件夹——WordItem 第 11 参显式传 folderId
  //（0.222.20 教训：构造尾部可省参数=最容易漏；第 5~10 参占位 ''/0 须逐个显式传才能传到 folderId）。
  // 重复时显示「单词已存在」（addWordToBank 仅空文本拒绝返回 false，0.222.19 已放开同名）。
  confirmAddWordToFolder(folderId: string): void {
    if (this.wordPopupResult === null) {
      return;
    }
    track(this.getUIContext().getHostContext() as common.Context, 'add_word_from_chat'); // 0.206.0 埋点：对话翻译弹窗加词
    const r = this.wordPopupResult;
    const item = new WordItem(r.word, r.fullName, r.usPhonetic, r.explain, '', 0, 0, 0, 0, 0, folderId);
    const ok = addWordToBank(this.wordBank, item);
    if (ok) {
      this.wordPopupAdded = true;
      this.wordExistsTip = false;
    } else {
      this.wordExistsTip = true;
    }
    this.wordFolderPickerVisible = false;
  }

  // ★ 0.268.0：AI 序生效判定/映射——rerank 缓存命中且有序（id 接回库对象，被删跳过；
  //   引用不落地=云同步整库重建天然免疫，0.248.6 教训消费端零特殊处理）
  aiOrderedWordObjects(messageId: string): WordItem[] {
    const ids = getRerankWordIds(messageId);
    if (ids.length === 0) {
      return [];
    }
    const byId = new Map<string, WordItem>();
    for (let i = 0; i < this.wordBank.words.length; i++) {
      byId.set(this.wordBank.words[i].id, this.wordBank.words[i]);
    }
    const out: WordItem[] = [];
    for (let i = 0; i < ids.length; i++) {
      const w = byId.get(ids[i]);
      if (w !== undefined) {
        out.push(w);
      }
    }
    return out;
  }

  aiOrderedCardObjects(messageId: string): KnowledgeCard[] {
    const ids = getRerankCardIds(messageId);
    if (ids.length === 0) {
      return [];
    }
    const byId = new Map<string, KnowledgeCard>();
    for (let i = 0; i < this.knowledgeBank.cards.length; i++) {
      byId.set(this.knowledgeBank.cards[i].id, this.knowledgeBank.cards[i]);
    }
    const out: KnowledgeCard[] = [];
    for (let i = 0; i < ids.length; i++) {
      const c = byId.get(ids[i]);
      if (c !== undefined) {
        out.push(c);
      }
    }
    return out;
  }

  // ★ 0.268.0：AI 重排结果到达（词库/卡库各自回调，可能先后两次）——
  //   该消息司忆区已按本地序渲染 → 就地替换缓存条目 + rerollSeq++ 重算（150ms 淡入脉冲）；
  //   未渲染（AI 回复流式中/占位）→ 不动，首次渲染 getReviewWords 直接走 AI 序分支；
  //   护栏（任务书 Q3）：用户已展开任一复习卡时挂起，收起后再替换（防展开态下条目被换走）。
  onRerankBatchReady(messageId: string): void {
    if (!this.reviewCache.has(messageId) && !this.knowledgeReviewCache.has(messageId)) {
      return; // 司忆区尚未渲染（或该库无 AI 序）——首抽时自然消费
    }
    if (this.reviewExpandKey !== '') {
      this.pendingRerankMsgIds.add(messageId); // 展开中：挂起等收起
      return;
    }
    this.applyRerankSwapFor(messageId);
  }

  // 挂起队列应用（收起展开卡后调；队列空零副作用）
  applyRerankSwap(): void {
    if (this.reviewExpandKey !== '') {
      return; // 仍有展开（防御，正常不会走到）
    }
    const ids: string[] = [];
    this.pendingRerankMsgIds.forEach((mid: string) => {
      ids.push(mid);
    });
    for (let i = 0; i < ids.length; i++) {
      this.applyRerankSwapFor(ids[i]);
      this.pendingRerankMsgIds.delete(ids[i]);
    }
  }

  // 就地替换该消息两库缓存为 AI 序（换过一批时保留偏移语义：AI 候选池内继续轮换）
  applyRerankSwapFor(messageId: string): void {
    let touched = false;
    if (this.reviewCache.has(messageId) && getRerankWordIds(messageId).length > 0) {
      const swapped = this.buildAiWordBatch(messageId);
      if (swapped !== null) {
        this.reviewCache.set(messageId, new ReviewCacheEntry(0, swapped));
        touched = true;
      }
    }
    if (this.knowledgeReviewCache.has(messageId) && getRerankCardIds(messageId).length > 0) {
      const swappedC = this.buildAiCardBatch(messageId);
      if (swappedC !== null) {
        this.knowledgeReviewCache.set(messageId, new KnowledgeReviewCacheEntry(0, swappedC));
        touched = true;
      }
    }
    if (!touched) {
      return;
    }
    this.rerollSeq++; // 触发两区 ForEach 重算（缓存分支返回 AI 序新批）
    this.siyiSwapPulse = true; // 150ms 透明度渐变替换（不做骨架屏——附属区不喧宾夺主）
    setTimeout(() => {
      this.siyiSwapPulse = false;
    }, 150);
  }

  // AI 序展示批（供首抽与替换两路共用）：非未来卡优先 + 未来卡 ≤1 张末位提权（Q1 终裁）；
  // 已换过一批（offset>0）时保持轮换语义——在 AI 候选池上按原偏移环绕取批（任务书补充采纳项）
  buildAiWordBatch(messageId: string): WordItem[] | null {
    const ordered = this.aiOrderedWordObjects(messageId);
    if (ordered.length === 0) {
      return null;
    }
    const n = Math.max(1, this.learnCountStore.learnCount);
    const offset = this.rerollWordOffsets.get(messageId);
    if (offset !== undefined && offset > 0) {
      return rotateSlice(ordered, offset, n);
    }
    const now = Date.now();
    return rerankDisplayBatch(ordered, n,
      (w: WordItem): boolean => w.reviewCount > 0 && w.nextReviewAt > now);
  }

  buildAiCardBatch(messageId: string): KnowledgeCard[] | null {
    const ordered = this.aiOrderedCardObjects(messageId);
    if (ordered.length === 0) {
      return null;
    }
    const n = Math.max(1, this.knowledgeCountStore.knowledgeCount);
    const offset = this.rerollCardOffsets.get(messageId);
    if (offset !== undefined && offset > 0) {
      return rotateSlice(ordered, offset, n);
    }
    const now = Date.now();
    return rerankDisplayBatch(ordered, n,
      (c: KnowledgeCard): boolean => c.reviewCount > 0 && c.nextReviewAt > now);
  }

  // 生词复习：按消息 ID 取 N 词（N=学习数量，单词库 ⚙ 设置）。
  // ★ 0.187.0：选词改走记忆算法（到期词按遗忘风险 R 升序 → 新词 → 未来词，替换纯随机）；
  // 缓存按消息 ID 永久固定（历史消息稳定），已删除的词读取时滤除；
  // 展示即复习——真到期的词计数 + 顺延 6h（未到期不计数：防重启重抽虚增，到期闸门防抖）
  // ★ 0.237.3：第二参 rerollSeq 仅为让 ForEach 渲染闭包建立依赖（换一批触发重算）；
  // 重抽走轮换分支——全序环绕取批，零复习副作用（不计数/不顺延/不埋点，防刷学习统计）
  // ★ 0.268.0：AI 序就绪时首抽走 AI 序展示批（同款展示即复习副作用）；换一批轮换池=
  //   AI 序对象数组（AI 候选池内沿用 rotateSlice 轮换——任务书补充采纳项）
  getReviewWords(messageId: string, rerollSeq: number = 0): WordItem[] {
    const cached = this.reviewCache.get(messageId);
    if (cached) {
      // ★ 0.248.6：缓存条目按 id 接回新库（原 includes 引用过滤在云同步 reconcile 整库
      //   重建 WordItem 后全部失配——AI 回复完成触发上行→下行合并→司忆区瞬间滤空只剩
      //   分隔线；id 稳定，重建后按 id 接回新对象，展示与评分均落最新实体）
      let allRef = true;
      for (let i = 0; i < cached.items.length; i++) {
        if (!this.wordBank.words.includes(cached.items[i])) {
          allRef = false;
          break;
        }
      }
      if (allRef) {
        return cached.items;
      }
      const byId = new Map<string, WordItem>();
      for (let i = 0; i < this.wordBank.words.length; i++) {
        byId.set(this.wordBank.words[i].id, this.wordBank.words[i]);
      }
      const out: WordItem[] = [];
      for (let i = 0; i < cached.items.length; i++) {
        const nw = byId.get(cached.items[i].id);
        if (nw !== undefined) {
          out.push(nw);
        }
      }
      return out;
    }
    const now = Date.now();
    const cachedOffset = this.rerollWordOffsets.get(messageId);
    if (cachedOffset !== undefined && cachedOffset > 0) {
      // ★ 0.268.0：AI 序生效时轮换池=AI 序（候选池内轮换）；未生效=现状本地全序
      const aiPool = this.aiOrderedWordObjects(messageId);
      const pool = aiPool.length > 0 ? aiPool : orderedReviewWords(this.wordBank, now);
      const rerolled = rotateSlice(pool, cachedOffset, this.learnCountStore.learnCount);
      this.reviewCache.set(messageId, new ReviewCacheEntry(0, rerolled));
      return rerolled;
    }
    // ★ 0.268.0：AI 序就绪（预触发先于首抽返回）——按 AI 序构建展示批（未来卡 ≤1 末位提权）
    const aiBatch = this.buildAiWordBatch(messageId);
    if (aiBatch !== null) {
      let aiMutated = false;
      for (let i = 0; i < aiBatch.length; i++) {
        if (applyPassiveReview(aiBatch[i], now)) { // 展示即复习（未来卡内部闸门不计数不顺延）
          aiMutated = true;
        }
      }
      if (aiMutated) {
        noteBankMutation();
      }
      recordStat(this.statStore, 'siyi', aiBatch.length, 0);
      this.reviewCache.set(messageId, new ReviewCacheEntry(0, aiBatch));
      return aiBatch;
    }
    const items = pickReviewWords(this.wordBank, this.learnCountStore.learnCount, now);
    let mutated = false; // ★ 0.223.0：展示即复习进度变更追踪（未到期不虚报）
    for (let i = 0; i < items.length; i++) {
      if (applyPassiveReview(items[i], now)) {
        mutated = true;
      }
    }
    if (mutated) {
      noteBankMutation(); // ★ 0.223.0：进度变更 3 秒防抖上云
    }
    recordStat(this.statStore, 'siyi', items.length, 0); // ★ 0.202.3：司忆量埋点
    this.reviewCache.set(messageId, new ReviewCacheEntry(0, items));
    return items;
  }

  // ★ 0.237.3：换一批——本条 AI 回复下方生词/知识卡复习区整批轮换。
  //   连点连换：offset 每次跳过当前批大小（在记忆算法全序上环绕轮换全库）；
  //   删两缓存 + rerollSeq++ 触发两区 ForEach 重算（重抽命中轮换分支写回新缓存）。
  //   语义备案：覆盖「缓存按消息 ID 永久固定」旧语义——换批结果仅本会话内生效，
  //   重启 app 回遗忘曲线默认首批（可接受，不额外持久化）。
  shuffleReviewBatch(messageId: string): void {
    const wordBatch = Math.max(1, this.learnCountStore.learnCount);
    const cardBatch = Math.max(1, this.knowledgeCountStore.knowledgeCount);
    const wPrev = this.rerollWordOffsets.get(messageId);
    this.rerollWordOffsets.set(messageId, (wPrev === undefined ? 0 : wPrev) + wordBatch);
    const cPrev = this.rerollCardOffsets.get(messageId);
    this.rerollCardOffsets.set(messageId, (cPrev === undefined ? 0 : cPrev) + cardBatch);
    this.reviewCache.delete(messageId);
    this.knowledgeReviewCache.delete(messageId);
    this.rerollSeq++;
  }

  // ============================================================
  // ★ 0.146：知识库卡片（入知识库 → AI 草稿 → 编辑弹窗 → 入库）
  // ============================================================

  // ★ 0.160：抽取弹窗内复习区内容（打开弹窗时调一次固定；词库/知识库为空时对应项为空，
  // 渲染层按空判不显示——与气泡底部复习区同款防御）
  // ★ 0.187.0：选词改走记忆算法 + 展示即复习（到期闸门防抖——反复开关弹窗不虚增计数）
  refreshEditReview(): void {
    const now = Date.now();
    let mutated = false; // ★ 0.223.0：展示即复习进度变更追踪
    this.editReviewWords = pickReviewWords(this.wordBank, this.learnCountStore.learnCount, now); // ★ 0.161：词条数由学习数量设置驱动（单词库 ⚙ 设置）
    for (let i = 0; i < this.editReviewWords.length; i++) {
      if (applyPassiveReview(this.editReviewWords[i], now)) {
        mutated = true;
      }
    }
    this.editReviewCards = pickReviewCards(this.knowledgeBank, this.knowledgeCountStore.knowledgeCount, now); // ★ 0.161.2：卡片数由知识卡片数量设置驱动（知识库 ⚙ 设置）；★ 0.188.0：记忆算法选卡
    for (let i = 0; i < this.editReviewCards.length; i++) {
      if (applyPassiveReview(this.editReviewCards[i], now)) { // ★ 0.188.0：展示即复习（到期闸门防抖）
        mutated = true;
      }
    }
    if (mutated) {
      noteBankMutation(); // ★ 0.223.0：进度变更 3 秒防抖上云
    }
    // ★ 0.202.3：司忆量埋点（本次展示的词+卡总数）
    recordStat(this.statStore, 'siyi', this.editReviewWords.length + this.editReviewCards.length, 0);
  }

  // ★ 0.246.0：抽取翻译浮窗司忆区内容（打开浮窗时调一次固定——同 refreshEditReview 哲学：
  //   查词等待期顺便学习；词库/知识库为空时对应块不渲染；展示即复习+司忆量埋点同款）
  refreshWordPopupReview(): void {
    const now = Date.now();
    let mutated = false;
    this.wordPopupReviewWords = pickReviewWords(this.wordBank, this.learnCountStore.learnCount, now);
    for (let i = 0; i < this.wordPopupReviewWords.length; i++) {
      if (applyPassiveReview(this.wordPopupReviewWords[i], now)) {
        mutated = true;
      }
    }
    this.wordPopupReviewCards = pickReviewCards(this.knowledgeBank, this.knowledgeCountStore.knowledgeCount, now);
    for (let i = 0; i < this.wordPopupReviewCards.length; i++) {
      if (applyPassiveReview(this.wordPopupReviewCards[i], now)) {
        mutated = true;
      }
    }
    if (mutated) {
      noteBankMutation(); // 进度变更 3 秒防抖上云
    }
    recordStat(this.statStore, 'siyi', this.wordPopupReviewWords.length + this.wordPopupReviewCards.length, 0);
  }

  // ★ 0.187.0：点词条展开/收起 3 档评分（👆 图标勾引点击——点词即展开）
  onReviewWordTap(key: string): void {
    this.reviewExpandKey = this.reviewExpandKey === key ? '' : key;
    if (this.reviewExpandKey === '') {
      this.applyRerankSwap(); // ★ 0.268.0：收起后应用挂起的 AI 序替换（Q3 护栏）
    }
  }

  // ★ 0.187.0：评分落库——按评分规则更新 S 与下次复习（方案B：现在+S），收起按钮
  // ★ 0.188.0：参数泛化 MemoryItem——单词/知识卡两库共用
  onReviewRate(key: string, w: MemoryItem, rating: MemoryRating): void {
 const _tp2: Record<string, string> = {}; _tp2['rating'] = rating;
    track(this.getUIContext().getHostContext() as common.Context, 'bubble_rate', _tp2); // 0.206.0 埋点：司忆区评分
    applyRating(w, rating, Date.now());
    completeRookieTask('first_review'); // ★ 0.294.0：新手任务④首次复习——司忆区评分即算（ReviewPage 同挂）
    noteBankMutation(); // ★ 0.223.0：评分=进度变更，3 秒防抖上云（用户拍板）
    const next = new Map<string, string>(this.reviewRatedMap);
    next.set(key, rating);
    this.reviewRatedMap = next; // Map 整体替换触发 V2 刷新
    this.reviewExpandKey = '';
    this.applyRerankSwap(); // ★ 0.268.0：评分收起后应用挂起的 AI 序替换（Q3 护栏）
  }

  // ★ 0.187.0：评分区（气泡复习区 + 提炼弹窗共用 @Builder）——
  // 已评分 → 「下次复习：X」结果行（按评分着色）；未评且展开 → 3 档按钮
  @Builder
  ratingArea(key: string, w: MemoryItem) { // ★ 0.188.0：参数泛化 MemoryItem——单词/知识卡共用
    if (this.reviewRatedMap.get(key) !== undefined) {
      Text(`下次复习：${formatNextReviewLabel(w.nextReviewAt, Date.now())}`)
        .fontSize(11)
        .fontColor(this.reviewRatedMap.get(key) === 'hard' ? this.theme.danger : (this.reviewRatedMap.get(key) === 'easy' ? '#3BB273' : '#F5A623'))
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
            Text('生疏').fontSize(13).fontWeight(600).fontColor(this.theme.reviewHard)
            Text(`${formatIntervalDays(previewIntervalDays(w, 'hard'))}后`).fontSize(9).fontColor(this.theme.textTertiary)
          }
        }
        .layoutWeight(1)
        .constraintSize({ maxWidth: 96 })
        .backgroundColor(this.theme.reviewHardBg)
        .borderRadius(RADIUS_CONTROL)
        .onClick(() => {
          this.onReviewRate(key, w, 'hard');
        })
        Button() {
          Column() {
            Text('尚可').fontSize(13).fontWeight(600).fontColor(this.theme.reviewGood)
            Text(`${formatIntervalDays(previewIntervalDays(w, 'good'))}后`).fontSize(9).fontColor(this.theme.textTertiary)
          }
        }
        .layoutWeight(1)
        .constraintSize({ maxWidth: 96 })
        .backgroundColor(this.theme.reviewGoodBg)
        .borderRadius(RADIUS_CONTROL)
        .onClick(() => {
          this.onReviewRate(key, w, 'good');
        })
        Button() {
          Column() {
            Text('熟知').fontSize(13).fontWeight(600).fontColor(this.theme.reviewEasy)
            Text(`${formatIntervalDays(previewIntervalDays(w, 'easy'))}后`).fontSize(9).fontColor(this.theme.textTertiary)
          }
        }
        .layoutWeight(1)
        .constraintSize({ maxWidth: 96 })
        .backgroundColor(this.theme.reviewEasyBg)
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
      return '网络连接超时：请检查网络后重试。'; // ★ 0.251.0：后台保活已上，超时不再归因切后台（旧文案「系统限制后台网络」作废）
    }
    if (raw.startsWith('AI服务错误：')) {
      return `AI服务返回错误：${raw.substring(7)}，请检查API Key/模型配置。`;
    }
    return '本地处理异常：生成卡片失败，请重试。';
  }

  // 「入知识库」：关闭菜单 → 打开编辑弹窗 → 发起 AI 提炼。
  // AI 结果只填充输入框（草稿），不直接入库——用户拥有最终编辑权。
  onToolbarAddKnowledge(): void {
    // ★ 0.248.3：划词入知识库守卫（上架合规——AI 多模态提炼，未登录拦截）
    if (!requireLoginForCloud()) {
      return;
    }
    // ★ 0.293.0：SP 云同步门卫（AI 提炼扣 SP——账本云端对齐才放行）
    if (!requireSiyiGate()) {
      return;
    }
    // ★ 0.272.0：提炼 SP 余额闸门（D3——余额≤0 且非 Lv8 弹充值引导，事前拦截防白跑 180s）
    if (!this.spFree() && siyiTotalSp(this.siyiStore) <= 0) {
      connectConfirmDialog().spRechargePromptVisible = true;
      return;
    }
    const text = this.effectiveSelText().trim(); // 先取值——closeSelectionMenu 可能同步触发 onDisappear 清空状态（0.285.5 粘性兜底）
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
    this.knowledgeEditInTok = 0;   // ★ 0.272.0：新提炼清零（上一轮用量不带入）
    this.knowledgeEditOutTok = 0;
    this.knowledgeEditSpText = '';
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
      },
      // ★ 0.272.0：token 用量透传——实扣 SP（scene='extract'）+ 信息卡数据；失败/取消/超时不回调（零扣费铁律）
      (inputTokens: number, outputTokens: number, cachedTokens: number) => {
        this.knowledgeEditInTok = inputTokens;
        this.knowledgeEditOutTok = outputTokens;
        const cost = spCostOfTokens(inputTokens, outputTokens, cachedTokens);
        if (this.spFree()) {
          this.knowledgeEditSpText = 'Lv8 免费';
          trackSpConsumeAuto(this.apiConfig.model, true, 0, inputTokens, cachedTokens, 'extract', outputTokens);
          return;
        }
        consumeSiyiSp(this.siyiStore, cost);
        this.knowledgeEditSpText = `消耗 ${cost} SP`;
        trackSpConsumeAuto(this.apiConfig.model, false, cost, inputTokens, cachedTokens, 'extract', outputTokens);
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
  // ★ 0.222.22 起弹目标文件夹选择弹窗（用户拍板——划词「入知识库」与屏幕圈选「存入知识库」
  // 两入口汇聚本弹窗，改此一处全覆盖）；知识库无任何文件夹时不弹、直接入根目录（同单词库拍板）。
  // 真正入库落点在 confirmSaveKnowledgeCard。
  saveKnowledgeCard(): void {
    const title = this.knowledgeCardTitle.trim();
    const definition = this.knowledgeCardDefinition.trim();
    if (title.length === 0 && definition.length === 0) {
      return;
    }
    if (this.knowledgeBank.folders.length === 0) {
      this.confirmSaveKnowledgeCard('');
      return;
    }
    this.cardFolderPickerVisible = true;
  }

  // ★ 0.222.22：确认知识卡入库到目标文件夹——KnowledgeCard 13 参显式传全
  //（第 11 参 images / 第 13 参 titleImages 均为 '' 占位，第 12 参 folderId 才是目标；
  // 构造尾部可省参数最容易漏，0.222.20 同族教训：显式占位逐参核对防错位）。
  confirmSaveKnowledgeCard(folderId: string): void {
    const title = this.knowledgeCardTitle.trim();
    const definition = this.knowledgeCardDefinition.trim();
    if (title.length === 0 && definition.length === 0) {
      return;
    }
    const card = new KnowledgeCard(generateMessageId(), title, definition, this.knowledgeImageUri,
      Date.now(), 0, 0, 0, 0, this.knowledgeSelectedTags, '', folderId, '');
    addKnowledgeCard(this.knowledgeBank, card);
    completeRookieTask('word_to_knowledge'); // ★ 0.294.0：新手任务③划词入知识库——卡片入库即算一次
    this.cardFolderPickerVisible = false;
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
    this.imgViewer.images = [this.knowledgeImageUri];
    this.imgViewer.index = 0;
    this.imgViewer.visible = true;
  }


  // 复习区知识卡片：按消息 ID 取 N 张（N=知识卡片数量，知识库 ⚙ 设置）。
  // ★ 0.188.0：知识库复刻记忆算法——选卡改走遗忘曲线（到期卡按 R 升序 → 新卡 → 未来卡）；
  // 缓存按消息 ID 永久固定（同 0.187.0 单词库修复：杜绝加卡触发全量重抽的虚假复习），
  // 已删除的卡读取时滤除；展示即复习（到期闸门防抖）。
  // ★ 0.237.3：第二参 rerollSeq 同 getReviewWords（换一批渲染依赖）；重抽走轮换分支零副作用
  // ★ 0.268.0：AI 序就绪时首抽走 AI 序展示批（未来卡 ≤1 末位提权）；换一批轮换池=AI 序（同生词区）
  getKnowledgeCards(messageId: string, rerollSeq: number = 0): KnowledgeCard[] {
    const cached = this.knowledgeReviewCache.get(messageId);
    if (cached) {
      // ★ 0.248.6：同 getReviewWords——按 id 接回新库，云同步整库重建后引用失配不再滤空
      let allRef = true;
      for (let i = 0; i < cached.items.length; i++) {
        if (!this.knowledgeBank.cards.includes(cached.items[i])) {
          allRef = false;
          break;
        }
      }
      if (allRef) {
        return cached.items;
      }
      const byId = new Map<string, KnowledgeCard>();
      for (let i = 0; i < this.knowledgeBank.cards.length; i++) {
        byId.set(this.knowledgeBank.cards[i].id, this.knowledgeBank.cards[i]);
      }
      const out: KnowledgeCard[] = [];
      for (let i = 0; i < cached.items.length; i++) {
        const nc = byId.get(cached.items[i].id);
        if (nc !== undefined) {
          out.push(nc);
        }
      }
      return out;
    }
    const now = Date.now();
    const cachedOffset = this.rerollCardOffsets.get(messageId);
    if (cachedOffset !== undefined && cachedOffset > 0) {
      // ★ 0.268.0：AI 序生效时轮换池=AI 序；未生效=现状本地全序
      const aiPool = this.aiOrderedCardObjects(messageId);
      const pool = aiPool.length > 0 ? aiPool : orderedReviewCards(this.knowledgeBank, now);
      const rerolled = rotateSlice(pool, cachedOffset, this.knowledgeCountStore.knowledgeCount);
      this.knowledgeReviewCache.set(messageId, new KnowledgeReviewCacheEntry(0, rerolled));
      return rerolled;
    }
    // ★ 0.268.0：AI 序就绪——按 AI 序构建展示批（未来卡 ≤1 末位提权）
    const aiBatch = this.buildAiCardBatch(messageId);
    if (aiBatch !== null) {
      let aiMutated = false;
      for (let i = 0; i < aiBatch.length; i++) {
        if (applyPassiveReview(aiBatch[i], now)) {
          aiMutated = true;
        }
      }
      if (aiMutated) {
        noteBankMutation();
      }
      recordStat(this.statStore, 'siyi', aiBatch.length, 0);
      this.knowledgeReviewCache.set(messageId, new KnowledgeReviewCacheEntry(0, aiBatch));
      return aiBatch;
    }
    const items = pickReviewCards(this.knowledgeBank, this.knowledgeCountStore.knowledgeCount, now);
    let mutated = false; // ★ 0.223.0：展示即复习进度变更追踪
    for (let i = 0; i < items.length; i++) {
      if (applyPassiveReview(items[i], now)) {
        mutated = true;
      }
    }
    if (mutated) {
      noteBankMutation(); // ★ 0.223.0：进度变更 3 秒防抖上云
    }
    recordStat(this.statStore, 'siyi', items.length, 0); // ★ 0.202.3：司忆量埋点
    this.knowledgeReviewCache.set(messageId, new KnowledgeReviewCacheEntry(0, items));
    return items;
  }

  // ★ 0.218.5：消息滑出删除面板（对齐知识库/单词库终式：44×44 品牌紫圆钮+白 trash 图标 20，
  //   外容器满高 Center 露出区宽 72；点击走 requestDeleteMessage 原确认链路）。swipeAction
  //   场景内容静态，带参 @Builder 无刷新风险（0.190.1 铁律）
  @Builder
  swipeDeleteMessagePanel(msg: ChatMessage) {
    Row() {
      Column() {
        Image($r('app.media.trash_brand'))
          .width(20)
          .height(20)
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor(this.theme.brandPrimary)
      .onClick(() => {
        this.requestDeleteMessage(msg.messageId); // 先弹确认防误触（原 × 按钮链路）
      })
    }
    .justifyContent(FlexAlign.Center)
    .width(72)
    .height('100%')
  }

  // ★ 0.145：划词悬浮操作栏（bindSelectionMenu 自定义菜单——完全替代系统小艺菜单）
  // ★ 0.284.0 PC 纵向菜单（用户需求「只在 PC：右击划词菜单改纵向排列，顺序=复制/粘贴/翻译/入知识库/
  //   引用/删除」）：粘贴=贴剪贴板图片入待发区（复用 0.283.0 Ctrl+V 同链路+运行时授权链）；标记条件项
  //   保留（置引用后，0.191.0 功能不删）；手机/Pad 维持横向原序不变（if 布局分治，isPcDevice 恒定值
  //   非 0.160 铁律的动态状态场景）
  @Builder
  SelectionToolbar() {
    if (this.isPcDevice()) {
      Column() {
        Text('复制')
          .fontSize(14)
          .fontColor(this.theme.textPrimary)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .width('100%')
          .onClick(() => {
            this.onToolbarCopy();
          })
        Divider()
          .color(this.theme.strokeCard)
        // ★ 0.284.0：粘贴——剪贴板图片入待发区（菜单点击场景非 silent：无图提示「剪贴板中没有图片」）
        Text('粘贴')
          .fontSize(14)
          .fontColor(this.theme.textPrimary)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .width('100%')
          .onClick(() => {
            this.pasteImageFromClipboard();
          })
        Divider()
          .color(this.theme.strokeCard)
        Text('翻译')
          .fontSize(14)
          .fontColor(this.theme.brandSecondary)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .width('100%')
          .onClick(() => {
            this.onToolbarTranslate();
          })
        Divider()
          .color(this.theme.strokeCard)
        // ★ 0.146：入知识库——选中原文交 AI 提炼草稿，编辑弹窗二次修改后入库
        Text('入知识库')
          .fontSize(14)
          .fontColor(this.theme.brandSecondary)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .width('100%')
          .onClick(() => {
            this.onToolbarAddKnowledge();
          })
        // ★ 0.235.0：引用——仅消息正文划词显示（放大弹窗/复习区不显示）
        if (this.isQuoteTargetKey(this.selKey)) {
          Divider()
            .color(this.theme.strokeCard)
          Text('引用')
            .fontSize(14)
            .fontColor(this.theme.brandSecondary)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .width('100%')
            .onClick(() => {
              this.onToolbarQuote();
            })
        }
        // ★ 0.191.0 标记（条件项保留——置引用后；划选首字符已标记→「取消标记」）
        if (this.isBookmarkTargetKey(this.selKey)) {
          Divider()
            .color(this.theme.strokeCard)
          Text(this.bookmarkBtnLabel())
            .fontSize(14)
            .fontColor(this.theme.textPrimary)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .width('100%')
            .onClick(() => {
              this.onToolbarBookmark();
            })
        }
        Divider()
          .color(this.theme.strokeCard)
        // ★ 0.160：划词删除——红色警示（破坏性操作），确认防误触与 × 按钮共享状态
        Text('删除')
          .fontSize(14)
          .fontColor(this.theme.danger)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .width('100%')
          .onClick(() => {
            this.onToolbarDelete();
          })
      }
      .alignItems(HorizontalAlign.Start)
      .width(PC_SELECTION_MENU_WIDTH) // ★ 0.285.0：定宽收口——原无宽度约束时 Divider 把纵向菜单撑到菜单上限（宽得离谱），对标鸿蒙系统右键菜单；PC 划词标准宽度
      .backgroundColor(this.theme.surfaceNode)
      .borderRadius(RADIUS_CONTROL)
      .border({ width: 0.5, color: this.theme.strokeCard })
      .shadow({ radius: 12, color: this.theme.shadowColorSoft, offsetX: 0, offsetY: 4 })
    } else {
      Row() {
        Text('翻译')
          .fontSize(14)
          .fontColor(this.theme.brandSecondary)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .onClick(() => {
            this.onToolbarTranslate();
          })
        Divider()
          .vertical(true)
          .height(16)
          .color(this.theme.strokeCard)
        // ★ 0.146：入知识库——选中原文交 AI 提炼草稿，编辑弹窗二次修改后入库
        Text('入知识库')
          .fontSize(14)
          .fontColor(this.theme.brandSecondary)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .onClick(() => {
            this.onToolbarAddKnowledge();
          })
        // ★ 0.235.0：引用——「入知识库」右侧新增（用户拍板）；仅消息正文划词显示（放大弹窗/复习区不显示）；
        //   样式与相邻按钮一致（this.theme.brandSecondary、fontSize 14、padding 14/8、同款分隔线）
        if (this.isQuoteTargetKey(this.selKey)) {
          Divider()
            .vertical(true)
            .height(16)
            .color(this.theme.strokeCard)
          Text('引用')
            .fontSize(14)
            .fontColor(this.theme.brandSecondary)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .onClick(() => {
              this.onToolbarQuote();
            })
        }
        Divider()
          .vertical(true)
          .height(16)
          .color(this.theme.strokeCard)
        // ★ 0.191.0 重做：标记移到「复制」左边 + 白字（用户定稿）；仅可标记 key 显示
        // （AI 正文文本段/代码块/表格格；用户消息/复习区/放大页不显示）
        // ★ 0.191.0 定稿：划选首字符已被标记 → 按钮变「取消标记」（标记/取消统一走工具栏，无独立清除入口）
        if (this.isBookmarkTargetKey(this.selKey)) {
          Text(this.bookmarkBtnLabel())
            .fontSize(14)
            .fontColor(this.theme.textPrimary)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .onClick(() => {
              this.onToolbarBookmark();
            })
          Divider()
            .vertical(true)
            .height(16)
            .color(this.theme.strokeCard)
        }
        Text('复制')
          .fontSize(14)
          .fontColor(this.theme.textPrimary)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .onClick(() => {
            this.onToolbarCopy();
          })
        Divider()
          .vertical(true)
          .height(16)
          .color(this.theme.strokeCard)
        // ★ 0.191.0：「全选」按钮移除（用户定稿——工具栏过长致「删除」超出屏幕边界；
        //   代码块工具栏的全选保留：顶替已删的顶栏⧉复制按钮，全选→复制整段代码）
        // ★ 0.160：划词删除——AI 超长回复时免滚到 × 按钮就地删本条消息；
        // 红色警示（破坏性操作），确认防误触与 × 按钮共享状态
        Text('删除')
          .fontSize(14)
          .fontColor(this.theme.danger)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .onClick(() => {
            this.onToolbarDelete();
          })
      }
      .backgroundColor(this.theme.surfaceNode)
      .borderRadius(RADIUS_CONTROL)
      .border({ width: 0.5, color: this.theme.strokeCard })
      .shadow({ radius: 12, color: this.theme.shadowColorSoft, offsetX: 0, offsetY: 4 })
    }
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
        .fontColor(this.theme.brandSecondary)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.onToolbarTranslate();
        })
      Divider()
        .vertical(true)
        .height(16)
        .color(this.theme.strokeCard)
      Text('入知识库')
        .fontSize(14)
        .fontColor(this.theme.brandSecondary)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.onToolbarAddKnowledge();
        })
      Divider()
        .vertical(true)
        .height(16)
        .color(this.theme.strokeCard)
      Text('复制')
        .fontSize(14)
        .fontColor(this.theme.textPrimary)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.onToolbarCopy();
        })
    }
    .backgroundColor(this.theme.surfaceNode)
    .borderRadius(RADIUS_CONTROL)
    .border({ width: 0.5, color: this.theme.strokeCard })
    .shadow({ radius: 12, color: this.theme.shadowColorSoft, offsetX: 0, offsetY: 4 })
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
    this.imgViewer.images = allImages;
    this.imgViewer.index = idx >= 0 ? idx : 0;
    this.imgViewer.visible = true;
  }

  addBubble(carryImages: string[] = [], carryText: string = '', carryQuote: string = ''): void {
    if (!this.currentBubble) {
      return;
    }
    this.cancelPlanning('switch'); // ★ 0.290.0：切分支自动取消进行中①段（bait 拉分支同走此口）
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
    completeRookieTask('new_bubble'); // ★ 0.294.0：新手任务⑥新建气泡——走到创建即算（防抖/流式/动画闸全过）
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
    this.store.rebuildEpoch++; // ★ 0.244.0：nodeList 替换——渲染世代 +1（画布 ForEach key 联动，防条目闭包持旧对象）
    recordStat(this.statStore, 'bubble', 0, 0); // ★ 0.192.0：统计埋点——创建子气泡 +1
    this.saveTree(); // ★ 0.151：按模式分池保存
    this.store.needsRelayout = true; // ★ 0.126：通知 BBTreeCanvas 重新布局（返回画布时 onShown 消费）
    this.stopTTS(); // ★ 0.151-D：切气泡前补停 TTS（原依赖 pop 退页触发 aboutToDisappear，直接切气泡须在此停）
    this.recordReadingPosition(); // ★ 0.191.0：切气泡前记录阅读高度（此路径不触发 aboutToDisappear，须手动记录）
    noteInactiveNode(this.currentBubble); // ★ 0.265.0：切走=旧节点失活（满足条件入摘要头 pending 队列，闲时 flush）
    // ★ 0.271.0：切分支清空思维链/思考态（任务书 §3.4——会话级数据不跨气泡；新分支新思考卡）
    if (this.thinkingTimer >= 0) {
      clearInterval(this.thinkingTimer);
      this.thinkingTimer = -1;
    }
    this.thinkingTraceByMsg.clear();
    this.thinkingSecondsByMsg.clear();
    this.thinkingActiveMsgId = '';
    this.thinkingHeadText = '';
    this.thinkingRetryMsgIds = [];
    this.thinkingDoneTick += 1;
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
        this.imeComposing = false; // ★ 0.287.2：新气泡输入区按携带文本是否为空重新判定占位
        // ★ 0.166.1：携带图片带入新气泡（圈注「创建子气泡」的标注图）；默认空数组 = 原清空行为不变
        this.pendingImages = carryImages;
        // ★ 0.235.0：划词引用随「引用为新子气泡」带入新输入区；默认空串 = 切气泡即清（一次性会话态，不进草稿）
        this.quoteText = carryQuote;
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
    // ★ 0.248.3：圈注守卫（上架合规——屏幕圈选后台走 AI 提炼，未登录拦截）
    if (!requireLoginForCloud()) {
      return;
    }
    // ★ 0.293.0：SP 云同步门卫（圈注 AI 提炼扣 SP——账本云端对齐才放行）
    if (!requireSiyiGate()) {
      return;
    }
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
    completeRookieTask('screen_annotate'); // ★ 0.294.0：新手任务⑤屏幕圈注——结果回传即算一次
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
    // ★ 0.272.0：提炼 SP 余额闸门（D3——与划词提炼同口径，事前拦截防白跑 180s）
    if (!this.spFree() && siyiTotalSp(this.siyiStore) <= 0) {
      connectConfirmDialog().spRechargePromptVisible = true;
      return;
    }
    this.knowledgeEditVisible = true;
    this.knowledgeCardTitle = '';
    this.knowledgeCardDefinition = '';
    this.knowledgeSuggestedTags = []; // ★ 0.202.1：建议标签清空（新会话）
    this.knowledgeSelectedTags = '';
    this.knowledgeImageUri = img; // 标注合成图直接作卡片配图
    this.knowledgeEditLoading = true;
    this.knowledgeEditError = '';
    this.knowledgeEditInTok = 0;   // ★ 0.272.0：新提炼清零（上一轮用量不带入）
    this.knowledgeEditOutTok = 0;
    this.knowledgeEditSpText = '';
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
      },
      // ★ 0.272.0：token 用量透传——实扣 SP（scene='extract'）+ 信息卡数据；失败/取消/超时不回调（零扣费铁律）
      (inputTokens: number, outputTokens: number, cachedTokens: number) => {
        this.knowledgeEditInTok = inputTokens;
        this.knowledgeEditOutTok = outputTokens;
        const cost = spCostOfTokens(inputTokens, outputTokens, cachedTokens);
        if (this.spFree()) {
          this.knowledgeEditSpText = 'Lv8 免费';
          trackSpConsumeAuto(this.apiConfig.model, true, 0, inputTokens, cachedTokens, 'extract', outputTokens);
          return;
        }
        consumeSiyiSp(this.siyiStore, cost);
        this.knowledgeEditSpText = `消耗 ${cost} SP`;
        trackSpConsumeAuto(this.apiConfig.model, false, cost, inputTokens, cachedTokens, 'extract', outputTokens);
      });
  }

  // ★ 0.151-bugfix：按模式分池保存工作区（两池隔离核心写路径，与 BBTreeCanvas.saveTree 同逻辑）
  // flat：工作区 = 平铺树 → 存回 bubbleTreeJson（现状路径）
  // tabs：工作区 = 当前 Tab 树 → 存回该 Tab 的 treeJson；
  //       无 activeTab 时【不写任何池】——此时工作区必为空（applyCanvasModeSwitch 保证），
  //       若写平铺池会把空树覆盖平铺池真实数据（用户实测丢树根因：切 tabs 后点 ➕，
  //       addTab 先走 saveTree 兜底、把空工作区写进 bubbleTreeJson，平铺池被清空）
  saveTree(): void {
    // ★ 0.287.0：重复体收口 ChatModel.saveBubbleTreePools（云上行经参数注入防环）
    saveBubbleTreePools(this.store, this.canvasModeStore, this.tabForest, this.persistData, upsertCloudData);
  }

  // ★ 0.150：AI 偏好 prompt 拼接——按用户设置（全局设置弹窗 Tab2）生成 system 指令，
  // sendMessage/regenerateMessage 在长度 prompt 之后追加（不持久化、不进入后续上下文，与播客 prompt 同机制）。
  // ★ 0.290.0（司枢 2.0）：长回复（司枢模式开）锚点/SECTION 指令整体移出——分节与语气由②段执笔
  //   buildWritePrompt+SECTION_PROMPT 注入、钩子由①段框架规划+渲染期合成器接管；本函数长回复只返回称呼。
  //   中回复单段锚点链路（ANCHOR_MEDIUM）原样保留；分章折叠恒开（GSD UI 隐藏、恒定值）不再参与判断。
  buildPreferencePrompt(isPodcast: boolean): string {
    let prompt = '';
    const nickname = this.aiPreference.aiNickname.trim();
    if (nickname.length > 0) {
      prompt += `请在回答中自然地称呼用户为「${nickname}」。`;
    }
    if (!isPodcast && this.replyLengthMode === 'medium' && this.anchorsEnabled()) {
      prompt += ANCHOR_MEDIUM_PROMPT; // 中回复单段锚点（旧五类）保留
    }
    return prompt;
  }

  // ★ 0.234.0：回复完成——清流式标记触发章节收拢（springMotion ~250ms 弹簧曲线，
  //   「文章写完自动叠好呈上来」的收拢时刻；直显→收拢，任务书 §2.1 A 方案）；
  //   不满足折叠条件（节数不足/折叠关/播客）时静默切换
  finishStreamFold(msg: ChatMessage): void {
    const flip = (): void => {
      this.streamingMsgId = '';
    };
    if (animOn && this.useFoldViewEligible(msg)) {
      this.getUIContext().animateTo({ duration: 250, curve: curves.springMotion(0.25, 1) }, flip);
    } else {
      flip();
    }
  }

  // ★ 0.234.0：折叠收拢动画适用判定（useFoldView 前置版——streamingMsgId 此刻仍指向本消息，
  //   故单独判定：非播客+AI+非占位+≥3 节；★ 0.290.0 折叠恒开不再读 foldMode）
  useFoldViewEligible(msg: ChatMessage): boolean {
    if (msg.role !== 'assistant' || msg.isPodcastMode) {
      return false;
    }
    if (msg.content === PLACEHOLDER_LOADING || msg.content === PLACEHOLDER_THINKING) {
      return false;
    }
    return this.richPlanFor(msg).sectionable;
  }

  // ============================================================
  // ★ 0.290.0 司枢模式 2.0：①段规划取消（用户点规划卡「取消」/发新消息/重生成/切分支；
  //   cancel 后 ApiClient 回调静默，状态就地清理——整条请求终止与思考卡取消同款语义）。
  //   旧 0.269.0 ②段伴读编排四件（buildNumberedHookInput/estimateHookSp/
  //   maybeStartHookArrangement/cancelHookArrangement）已随 HOOK_SYSTEM_PROMPT 退役移除。
  // ============================================================
  cancelPlanning(reason: string): void {
    if (this.planController !== null) {
      this.planController.cancel();
      this.planController = null;
    }
    if (this.planningMsgId.length > 0) {
      const pCancel: Record<string, string> = {};
      pCancel['ev'] = 'plan_cancel';
      pCancel['rs'] = reason;
      track(this.getUIContext().getHostContext() as common.Context, 'plan_two_stage', pCancel);
      this.planningMsgId = '';
      this.planPreview = '';
    }
  }

  // ============================================================
  // ★ 0.300.0 司枢 Agent 3.0 成员方法组
  // ============================================================
  // 反问卡作答/跳过 → 恢复挂起的枢机链路（代际核对在 resume 闭包内）
  resolveClarify(answers: string[] | null): void {
    const resume = this.clarifyResume;
    this.clarifyResume = null;
    if (resume !== null) {
      resume(answers);
    }
  }

  // 反问挂起被顶替（新消息/重生成/组件销毁）→ 旧链路静默死亡（不 resume——新链路已接管）
  abandonClarify(): void {
    this.clarifyResume = null;
    if (this.clarifyState.visible) {
      this.clarifyState.visible = false;
      this.clarifyState.questions = [];
    }
  }

  // ★ 0.300.0 SP 分阶段透明（产品军令 3：成本全程透明替代封顶）——枢机/工具/执笔/御史
  //   逐轮累计实时估算（spCostOfTokens 同源公式；live 轮的 token 未完不计，保守偏低不虚高）
  updateSishuSpPreview(liveIn: number, liveOut: number, liveCached: number,
    accIn: number, accOut: number, accCached: number): void {
    const inT = liveIn + accIn;
    const outT = liveOut + accOut;
    if (inT <= 0 && outT <= 0) {
      return;
    }
    const sp = spCostOfTokens(inT, outT, liveCached + accCached);
    this.sishuSpPreview = sp >= 100 ? `${Math.round(sp)}` : sp.toFixed(1);
  }

  // ★ 0.300.0 一键纠偏（任务书 §三.4）——成品卡「这不是我要的形态」：切换 form→存档契约直改→
  //   跳过枢机重跑执笔（不是让用户重新描述）；纠偏历史落 preferences（最近 20 条注入枢机调权重）
  correctForm(msg: ChatMessage): void {
    const c = this.contractByMsg.get(msg.messageId);
    if (c === undefined) {
      return;
    }
    const from = c.form;
    const to = from === 'deliverable' ? 'analysis' : 'deliverable';
    c.form = to;
    this.correctPendingByMsg.set(msg.messageId, c);
    recordCorrectEntry(this.getUIContext().getHostContext() as common.Context, from, to, c.taskType, c.genre);
    const cc: Record<string, string> = {};
    cc['from'] = from;
    cc['to'] = to;
    cc['taskType'] = c.taskType;
    track(this.getUIContext().getHostContext() as common.Context, 'sishu_correct', cc);
    this.showToastSafe(to === 'deliverable' ? '已切换为成品形态，重新执笔中' : '已切换为分析形态，重新执笔中');
    this.regenerateMessage(msg);
  }

  // 交付卡渲染三取数（@Builder 内禁 as 断言/局部变量——方法封装）
  deliverContractOf(msg: ChatMessage): TaskContract | null {
    const c = this.contractByMsg.get(msg.messageId);
    return c !== undefined && c.form === 'deliverable' ? c : null;
  }

  deliverGenreOf(msg: ChatMessage): string {
    const c = this.deliverContractOf(msg);
    return c !== null ? c.genre : '';
  }

  deliverAssumptionsOf(msg: ChatMessage): string {
    const c = this.deliverContractOf(msg);
    return c !== null ? c.assumptions.join('；') : '';
  }

  // 思考开始：登记活动消息 + 启动秒表计时器（1s tick——思考卡「深度思考中 Ns」）
  beginThinkingTrace(msgId: string): void {
    this.thinkingActiveMsgId = msgId;
    this.thinkingElapsed = 0;
    this.thinkingHeadText = '';
    this.thinkingTraceByMsg.set(msgId, '');
    if (this.thinkingTimer >= 0) {
      clearInterval(this.thinkingTimer);
    }
    this.thinkingTimer = setInterval((): void => {
      this.thinkingElapsed += 1;
    }, 1000);
  }

  // 思考分片追加：思维链全文累积（单条超 5000 字截断）+ 滚动摘要（前 120 字）
  appendThinkingTrace(msgId: string, chunk: string): void {
    const cur = this.thinkingTraceByMsg.get(msgId) ?? '';
    if (cur.length >= 5000) {
      return;
    }
    const merged = cur.length + chunk.length > 5000 ? cur + chunk.substring(0, 5000 - cur.length) : cur + chunk;
    this.thinkingTraceByMsg.set(msgId, merged);
    this.thinkingHeadText = merged.length > 120 ? `${merged.substring(0, 120)}…` : merged;
  }

  // 思考冻结收起：停计时器 + 记录秒数（收起行「已深度思考 Ns」；进入 phase3 或流结束时调用）
  finishThinkingTrace(msgId: string): void {
    if (this.thinkingTimer >= 0) {
      clearInterval(this.thinkingTimer);
      this.thinkingTimer = -1;
    }
    this.thinkingSecondsByMsg.set(msgId, this.thinkingElapsed);
    this.thinkingActiveMsgId = '';
    this.thinkingHeadText = '';
    this.thinkingDoneTick += 1; // Map 非 @Trace——tick 递增触发收起行渲染重建
  }

  // ★ 0.271.0：thinking_use 埋点（§3.9——ev/mode/eff/dur/rchars/sp；上线后按分位数回调 §3.2 阈值）
  trackThinkingUse(ev: string, mode: string, eff: string, dur: number, rchars: number, sp: number): void {
    const p: Record<string, string> = {};
    p['ev'] = ev;
    p['mode'] = mode;
    p['eff'] = eff;
    p['dur'] = `${dur}`;
    p['rchars'] = `${rchars}`;
    p['sp'] = `${sp}`;
    track(this.getUIContext().getHostContext() as common.Context, 'thinking_use', p);
  }

  // ★ 0.271.0：手动降级重试（超时类错误专用——§3.6.3 思考场景二次超时概率高=双倍计费零收益，
  //   不自动重发把选择权给用户；走 regenerate 链路+本条强制 disabled）
  retryWithNormalMode(msg: ChatMessage): void {
    const rest: string[] = this.thinkingRetryMsgIds.filter((id: string): boolean => id !== msg.messageId);
    this.thinkingRetryMsgIds = rest;
    this.trackThinkingUse('manual_retry', this.replyLengthMode, '', 0, 0, 0);
    this.regenerateMessage(msg, true);
  }

  // ★ 0.271.0：取本条 AI 消息之前最近一条用户消息文本（重生成思考计分 S1/S2/S5 信号源）
  findLastUserTextBefore(target: ChatMessage): string {
    const bubble = this.currentBubble; // 0.237.0 教训④：null 收窄不流动，提局部变量
    if (bubble === null || bubble === undefined) {
      return '';
    }
    const msgs = bubble.messages;
    let found = '';
    for (let i = 0; i < msgs.length; i++) {
      if (msgs[i].messageId === target.messageId) {
        break;
      }
      if (msgs[i].role === 'user') {
        found = msgs[i].content;
      }
    }
    return found;
  }


  // ★ 0.159：返回逻辑统一入口——顶栏自定义返回按钮与系统返回手势（onBackPressed）共用；
  // 有弹窗打开时逐个关闭并返回 true（消费返回事件），全关时返回 false（由调用方执行导航）
  handleBack(): boolean {
    if (this.imgViewer.visible) {
      this.imgViewer.visible = false; // 图片预览（0.120）
      return true;
    }
    if (this.wordFolderPickerVisible) {
      this.wordFolderPickerVisible = false; // 加词目标文件夹选择弹窗（0.222.21）——返回键先关此弹窗
      return true;
    }
    if (this.quotePickerVisible) {
      this.cancelQuotePicker(); // ★ 0.235.0：划词引用二选一弹窗——返回键先关此弹窗
      return true;
    }
    if (this.wordPopupVisible) {
      this.closeWordPopup(); // 翻译浮窗，取消查词请求（0.145）
      return true;
    }
    if (this.cardFolderPickerVisible) {
      this.cardFolderPickerVisible = false; // 知识卡入库文件夹选择弹窗（0.222.22）——返回键先关此弹窗（编辑弹窗保留）
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
    if (this.gsShared.visible) {
      this.gsShared.closeReq++; // ★ 0.150：全局设置弹窗——递增计数器触发弹窗内 requestClose（有未保存修改时二次确认，不直接丢弃）
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
          .fontColor(this.theme.textPrimary)
          .padding({ left: 4, right: 4 })
          .margin({ right: 4 })
          .onClick(() => {
            if (!this.handleBack()) {
              this.pathStack.pop();
            }
          })
      }
      // ★ 0.196.5：标题列 space 2 对齐画布信息条（Column({space:2}){标题,统计}）——
      //   两列内容规格完全一致（16/600/Inter-SemiBold + 11/this.theme.textSecondary/Inter）+ 同高 Row 居中 → 标题 y 像素级一致
      Column({ space: 2 }) {
        Text('气泡') // ★ 0.195.0：标题「对话」→「气泡」（用户定稿——页面主体是气泡对话，与气泡树命名体系统一）
          .fontSize(FONT_SIZE_SCREEN_TITLE) // ★ 0.181.0：顶栏标题对齐 ScreenTitle（18 Bold→16 SemiBold）
          .fontWeight(600)
          .fontColor(this.theme.textPrimary)
          .fontFamily(FONT_INTER_SEMIBOLD) // ★ 0.196.3：字体对齐气泡树信息条标题（用户实测两页视觉不一）
        // ★ 0.195.0：副标题统计行（模仿气泡树「N 个气泡 · N 条对话」——用户需求：知道当前对话已有多少条）
        // ★ 0.196.3：颜色/字体/间距全对齐气泡树统计行（用户实测「一亮一暗、高度不一样」——
        //   原 this.theme.textTertiary(暗)+无 fontFamily+margin 1 → this.theme.textSecondary(亮)+FONT_INTER+去 margin，以气泡树为准）
        Text(`${this.currentMessages.length} 条对话`)
          .fontSize(11)
          .fontColor(this.theme.textSecondary)
          .fontFamily(FONT_INTER)
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
        .layoutWeight(1)
      // ★ 0.278.4：顶栏模型名标识移除（用户拍板——模型名改显到每条消息下方 ⓘ 左侧，
      //   全局 AIGC 声明移到输入框下方；合规仍满足：每条消息带模型名 + 底部全局声明）
      Row() {
        Image($r('app.media.settings'))
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
      }
      .height(40) // ★ 0.196.5：同上——40vp 撑高
      .padding({ left: 4, right: 4 }) // ★ 0.195.0：去 margin——8vp 间距统一（Row 自身 right padding 16 收尾）
      .onClick(() => {
        this.gsShared.visible = true; // ★ 0.150：改唤全局设置弹窗（原 SettingsPage 页面入口由弹窗替代）
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
        // ★ 0.280.0：外包 Stack（BottomEnd 对齐）——「回到底部」悬浮钮挂点；layoutWeight 上移到 Stack，
        //   内层 List/空态改 100% 高（参照已定高的 Stack，安全——非 0.279.19 未定容器反向测量雷）
        Stack({ alignContent: Alignment.BottomEnd }) {
        if (this.currentMessages.length === 0) {
          Column() {
            Text('暂无对话')
              .fontSize(16)
              .fontColor(this.theme.textTertiary)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .opacity(this.msgAreaOpacity) // ★ 0.162：分支切换过渡动画挂点（空态分支）
        } else {
          List({ space: 12, scroller: this.scroller }) {
            ForEach(this.currentMessages, (msg: ChatMessage) => {
              ListItem() {
                Row() {
                  // ★ 0.218.5 用户拍板：AI 消息常驻红 × 撤除——删除入口改为滑出回收站圆钮面板；
                  //   ★ 0.235.2：滑动方向统一右滑（start 侧，与用户消息一致）
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
                        // ★ 0.235.2：包 Column 加操作行（复制全文+删除，与 AI 操作行同款同左对齐——用户拍板
                        //   「我人类发给 AI 的那个段落下面的东西也得有这两个小按钮」）
                        Column() {
                        Text(msg.content, { controller: this.getOrCreateTextController(`${msg.messageId}|u`) })
                          .fontSize(this.fs(16))
                          .lineHeight(this.fs(Math.round(16 * BODY_LINE_HEIGHT_RATIO)))
                          .fontColor(this.theme.userMsgText) // ★ 0.278.13：用户消息正文比 AI（纯白 textPrimary）暗一档（用户拍板「用户发的至少比 AI 的暗」）
                          .padding(10)
                          .borderRadius(RADIUS_NODE) // ★ 0.181.0：气泡圆角对齐节点卡片规格（8→18）
                          .backgroundColor(this.theme.bubbleUserBg) // ★ 0.278.13：用户气泡单独暗一档（原 0.195.0「与 AI 一致」作废——用户拍板「用户发的至少要比 AI 的暗」）
                          .copyOption(CopyOptions.LocalDevice)
                          .constraintSize({ maxWidth: '100%' }) // ★ 0.233.0：气泡宽度拉满（用户拍板「用户发的和 AI 回复的宽度全部凑齐拉满、填平对齐」——删除已由左滑/右滑/长按实现，不再留侧边空间）；0.190.3 原 90%、0.148 原约束——长文本自动换行，防溢出屏幕
                          // ★ 0.145：长按弹自研选择工具栏；onAppear 记录来源 key，onDisappear 清理选中状态
                           .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE) // ★ 0.285.3：可获焦模式（华为二轮正解）——Text 默认 UNFOCUSABLE 划选后不获焦、系统 Ctrl+C 派发给错误组件；本模式点击/划选即入获焦链，系统默认复制直接生效
                           .focusOnTouch(true) // ★ 0.285.4：拖选起手 press 即申请焦点——textSelectable 只给获焦能力、拖选本身不改焦点归属（华为 Q2），获焦后系统 Ctrl+C 才作用于其选区
                           .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, this.isPcDevice() ? TextResponseType.RIGHT_CLICK : TextResponseType.SELECT, {
                             onAppear: () => {
                               this.selKey = `${msg.messageId}|u`;
                             },
                             onDisappear: () => {
                               this.clearSelectionState();
                             }
                           })
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
                        // ★ 0.235.2：用户消息操作行——复制全文+删除（无刷新/换一批/token，AI 消息专属）；
                        //   左对齐 margin left 10 = 气泡 padding 10，与 AI 操作行同款定式（space 8、图标 14、padding 4）
                        // ★ 0.237.3：加喇叭（用户要求「我发的内容也能朗读」，无换一批/刷新）——
                        //   三态图标逻辑与 AI 行同款；ttsLoadingMessageId/playingMessageId 消息级单值
                        //   天然互斥（同一时间只读一条），startTTS 对 user 消息无 role 限制
                        Row({ space: 8 }) {
                          Row() {
                            Image(this.ttsLoadingMessageId === msg.messageId ? $r('app.media.speaker_loading') : (this.playingMessageId === msg.messageId ? (speakerPulse.wave ? $r('app.media.speaker_playing') : $r('app.media.speaker_wave1')) : $r('app.media.speaker')))
                              .width(14)
                              .height(14)
                              .objectFit(ImageFit.Contain)
                          }
                          .padding(4)
                          .onClick(() => {
                            this.startTTS(msg);
                          })
                          Row() {
                            Image($r('app.media.copy'))
                              .width(14)
                              .height(14)
                              .objectFit(ImageFit.Contain)
                          }
                          .padding(4)
                          .onClick(() => {
                            this.copyFullMessage(msg);
                          })
                          Row() {
                            Image($r('app.media.trash'))
                              .width(14)
                              .height(14)
                              .objectFit(ImageFit.Contain)
                          }
                          .padding(4)
                          .onClick(() => {
                            this.requestDeleteMessage(msg.messageId);
                          })
                        }
                        .margin({ top: 4, left: 10 })
                        }
                        .alignItems(HorizontalAlign.Start)
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
                            // ★ 0.271.0：思考卡（phase2 思考中浮现——秒表+计时+滚动摘要；进入 phase3 由
                            //   finishThinkingTrace 清活动态自动消失，占位区回归打字机正文）
                            if (this.thinkingActiveMsgId === msg.messageId) {
                              this.thinkingCard()
                            }
                            // ★ 0.234.0 注意力锚点+分章折叠：完成态（≥3 节且折叠开）走章节折叠视图；
                            //   流式中/折叠关/节数不足走平铺直显——同一渲染计划 richPlanFor，锚点卡两态同源
                            if (this.useFoldView(msg)) {
                              this.FoldedMessageView(msg, this.richPlanFor(msg).sections)
                            } else {
                             ForEach(this.richPlanFor(msg).entries, (entry: RichPlanEntry, idx: number) => {
                              // ★ 0.191.0 定稿：清除入口已移除——标记/取消统一走划词工具栏
                              //   （划选已标记文字 → 按钮变「取消标记」），段落上方不再插任何小字行
                              if (entry.seg.type === 0) {
                               // 普通文本段
                               // ★ 0.231.0：常态走 Markdown 富文本渲染（标题/粗斜/列表/引用/分割线/链接）；
                               //   命中书签的段回落纯文本渲染（书签偏移=纯文本语义，保划词级荧光笔不破）
                               if (this.isBookmarkAt(`${msg.messageId}|${idx}`)) {
                               // ★ 0.145：划词翻译——AI 文本段同样长按划词（key 纳入段索引 idx，与用户消息 key 空间隔离）
                               // ★ 0.191.0 重做：划词级书签——命中本段时按字符偏移拆三段 Span，
                               //   划选文字紫色+下划线（Span 不支持背景色，紫字+紫下划线为等效荧光笔方案）；未命中单 Span 原样
                               Text('', { controller: this.getOrCreateTextController(`${msg.messageId}|${idx}`) }) {
                                 if (this.isBookmarkAt(`${msg.messageId}|${idx}`) && this.bmStart() >= 0 && this.bmEnd() > this.bmStart() && this.bmEnd() <= entry.seg.content.length) {
                                   Span(entry.seg.content.substring(0, this.bmStart()))
                                   Span(entry.seg.content.substring(this.bmStart(), this.bmEnd()))
                                     .fontColor(this.theme.brandSecondary)
                                     .decoration({ type: TextDecorationType.Underline, color: this.theme.brandSecondary })
                                   Span(entry.seg.content.substring(this.bmEnd()))
                                 } else {
                                   Span(entry.seg.content)
                                 }
                               }
                                 .fontSize(this.fs(16))
                                 .lineHeight(this.fs(Math.round(16 * BODY_LINE_HEIGHT_RATIO)))
                                 .fontColor(this.theme.textPrimary)
                                 .copyOption(CopyOptions.LocalDevice)
                                 // ★ 0.145：长按弹自研选择工具栏；onAppear 记录来源 key，onDisappear 清理选中状态
                                  .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE) // ★ 0.285.3：可获焦模式（华为二轮正解）——Text 默认 UNFOCUSABLE 划选后不获焦、系统 Ctrl+C 派发给错误组件；本模式点击/划选即入获焦链，系统默认复制直接生效
                                  .focusOnTouch(true) // ★ 0.285.4：拖选起手 press 即申请焦点——textSelectable 只给获焦能力、拖选本身不改焦点归属（华为 Q2），获焦后系统 Ctrl+C 才作用于其选区
                                  .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, this.isPcDevice() ? TextResponseType.RIGHT_CLICK : TextResponseType.SELECT, {
                                    onAppear: () => {
                                      this.selKey = `${msg.messageId}|${idx}`;
                                    },
                                    onDisappear: () => {
                                      this.clearSelectionState();
                                    }
                                  })
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
                                   this.handleSelectionChange(`${msg.messageId}|${idx}`, entry.seg.content, start, end);
                                 })
                                 // ★ 0.145：全选受控——selectAllKey 命中本段时全选；未命中时 (1, 0) 不选中
                                 .selection(
                                   this.selectAllKey.startsWith(`${msg.messageId}|${idx}|`) ? 0 : 1,
                                   this.selectAllKey.startsWith(`${msg.messageId}|${idx}|`) ? entry.seg.content.length : 0
                                 )
                               } else {
                                 // ★ 0.231.0：常态富文本（标题/粗斜/列表/引用/分割线/链接——划词翻译/复制逐块照常）；
                                 // ★ 0.234.0：改传预构建 blocks（锚点卡/breath 保底已在 richPlanFor 注入）
                                 this.MdRichSegment(entry.blocks, `${msg.messageId}|${idx}`)
                               }
                             }
                             if (entry.seg.type === 1) {
                               // ★ 代码块：使用 CodeBlockView 组件，支持自动换行切换（0.122）
                               // ★ 0.156：划词桥接——key 用 `c${idx}` 前缀（与文本段纯数字 idx 空间隔离），
                               // controller 注册进父组件 map，工具栏/翻译/复制/全选链路完全复用
                               // ★ 0.191.0：代码块开放划词级标记——书签偏移传入（命中本块才传，否则 -1），
                               //   内部与语法 token 求交集拆分，marked 段紫色下划线
                               CodeBlockView({
                                 content: entry.seg.content,
                                 lang: entry.seg.lang, // ★ 0.149：语言标识（parseMarkdown 已提取，语法高亮+顶部标签）
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
                             if (entry.seg.type === 2) {
                               // ★ 0.153：表格重做——固定列宽对齐 + 默认不换行 + 左上角「放大」按钮
                               // ★ 0.234.0：整段提取为 TableBlockView 共用 Builder（平铺段与折叠章节同源渲染；
                               //   keyBase=`${msgId}|t${idx}` 与原格位 key 逐字一致——书签/划词/全选语义不变）
                               this.TableBlockView(entry.seg.header, entry.seg.rows, `${msg.messageId}|t${idx}`)
                             }
                             // ★ 0.132 修复：key 纳入 content/header/rows 尺寸——流式追加时 key 变化触发 item 重建，
                             // 否则 key 恒定导致 ForEach 复用旧 item，MdSegment 非响应式，Text 永不更新（卡占位 bug 根因）
                             // ★ 0.160 bugfix: key 再纳入 content 前 12 字符——0.132 的 length 维度存在等长碰撞边界：
                             // THINKING 占位与正文恰好等长时 key 相同 → item 复用 → 卡占位（用户实测：token 已写入但
                             // 气泡永显「AI 正在深度思考中...」，持久化 content 实为正文）。前缀维度保证占位↔正文切换 key 必变。
                             // ★ 0.234.0：追加 blocks 维度——锚点/breath 注入数量变化（开关切换/密度档）触发 item 重建。
                               }, (entry: RichPlanEntry, idx: number) => `${idx}_${entry.seg.type}_${entry.seg.content.length}_${entry.seg.content.substring(0, 12)}_${entry.seg.header.length}_${entry.seg.rows.length}_${entry.blocks.length}`)
                            }
                          // ★ 0.160.2 四次修复：删除原 Markdown 内层 Column 的残留闭合「}」与 .alignItems——
                          // 内层容器开头已在三次修复中随占位行一并移除，闭合括号残留导致括号错配（28 ERROR）。
                          // 现结构：2122 气泡 Column 直接包含 Markdown ForEach + 生词区 + 知识卡片区，
                          // 由 2400 行「}」+ constraintSize/padding 属性链闭合。

                         // ★ 0.145：生词复习区——词库非空时在 AI 气泡底部展示随机 2 词（词条式布局，与下方知识卡片风格统一）
                         // （仅 AI 气泡渲染，本分支天然不含用户消息；缓存按消息 ID，词库长度变化时重抽）
                          // ★ UI 定稿：普通词 2 行（词+音标/释义）、缩略词 3 行（+全称）；行内超宽横向滑动，不换行不省略，行高恒定
                          // ★ 0.248.6：加数量>0 判断——设置设 0（=关闭）时词条抽空但 Divider 仍渲染，
                          //   视觉上多出一条空横线；关闭语义须整块不渲染（含分隔线），两区同理
                           if (this.wordBank.words.length > 0 && this.learnCountStore.learnCount > 0) {
                            // ★ 0.268.0：分隔线+「✨ 语境优先」微标（AI 序对该消息生效时才出现；
                            //   灰紫 10vp 小字对齐灰色辅助字规范，附属区不喧宾夺主）
                            Row() {
                              Divider()
                                .strokeWidth(0.5)
                                .color(this.theme.strokeCard)
                                .layoutWeight(1)
                              if (getRerankWordIds(msg.messageId).length > 0) {
                                Text('✨ 语境优先')
                                  .fontSize(10)
                                  .fontColor(this.theme.brandSecondary)
                                  .margin({ left: 6 })
                              }
                            }
                            .alignItems(VerticalAlign.Center)
                            .margin({ top: 8, bottom: 6 })
                            Column() {
                                ForEach(this.getReviewWords(msg.messageId, this.rerollSeq), (w: WordItem, idx: number) => {
                                // ★ 0.233.0：单词词条拆两行（用户拍板「不能把单词和下面的解释内容放在一起一起滑——
                                //   拆开来」；体验对齐知识卡 0.232.1 标题/内容行分离）：词行（三角+词+音标+喇叭）常驻
                                //   独立横滑，全称+释义内容行独立横滑——滑解释时单词始终可见不动
                                Column() {
                                  Row() {
                                       // ★ 0.188.0：复习区划词——词行/全称/释义均可长按划词（翻译/入知识库/复制）；
                                       //   key 段前缀 rw*/rwf*/rwe* 与正文段纯数字 idx 空间隔离；音标行为发音辅助符号不加
                                       // ★ 0.237.0 军令：字符三角 ▼/▲ → FoldChevron SVG（收起指右/展开指下）；点词/点箭头展开 3 档评分
                                       FoldChevron({ expanded: this.reviewExpandKey === `${msg.messageId}|${w.id}` })
                                         .onClick(() => {
                                           this.onReviewWordTap(`${msg.messageId}|${w.id}`);
                                         })
                                    Scroll() {
                                      Row() {
                                      Text(w.word, { controller: this.getOrCreateTextController(`${msg.messageId}|rw${idx}`) })
                                        .fontSize(this.fs(13))
                                        .fontWeight(600)
                                        .fontColor(this.theme.textSecondary)
                                        .maxLines(1)
                                        .copyOption(CopyOptions.LocalDevice)
                                        .onClick(() => {
                                          this.onReviewWordTap(`${msg.messageId}|${w.id}`);
                                        })
                                        .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE) // ★ 0.285.3：可获焦模式（华为二轮正解）——Text 默认 UNFOCUSABLE 划选后不获焦、系统 Ctrl+C 派发给错误组件；本模式点击/划选即入获焦链，系统默认复制直接生效
                                        .focusOnTouch(true) // ★ 0.285.4：拖选起手 press 即申请焦点——textSelectable 只给获焦能力、拖选本身不改焦点归属（华为 Q2），获焦后系统 Ctrl+C 才作用于其选区
                                        .bindSelectionMenu(TextSpanType.TEXT, this.ReviewSelectionToolbar, this.isPcDevice() ? TextResponseType.RIGHT_CLICK : TextResponseType.SELECT, {
                                          onAppear: () => {
                                            this.selKey = `${msg.messageId}|rw${idx}`;
                                          },
                                          onDisappear: () => {
                                            this.clearSelectionState();
                                          }
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
                                         // ★ 0.232.1：音标可点=展开评分（用户需求：点击区扩大到整个词条——词条短时只点左上角单词很难受）
                                         // ★ 0.246.0：音标点击改发音（用户拍板：与旁边喇叭 icon 同行为）；展开评分仍走单词/箭头/全称/释义
                                         Text(w.usPhonetic)
                                           .fontSize(this.fs(12))
                                           .fontColor(this.theme.textTertiary)
                                           .maxLines(1)
                                           .margin({ left: 6 })
                                           .onClick(() => {
                                             this.stopTTS();
                                             wordSpeaker.speak(wordSpeaker.textForItem(w), showAccentDialogs(this.getUIContext()));
                                           })
                                        // ★ 0.149：音标旁发音按钮——缩略词播全称（字母谁都会读）、普通词播单词本身（美式）；三态 🔈/⏳/🔊；点击先停消息朗读（互斥）
                                        // ★ 0.150：Button→Text——Button 默认高度（≈40vp）会撑高音标行，Text 无默认高度、行距还原
                                        // ★ 0.195.0：喇叭三态 emoji（🔈⏳🔊 彩色）换单色 svg——形状即状态（cone 空闲/dots 合成中/waves 播放中）
                                        Image(wordSpeaker.loadingWord === wordSpeaker.textForItem(w) ? $r('app.media.speaker_loading') : (wordSpeaker.speakingWord === wordSpeaker.textForItem(w) ? (speakerPulse.wave ? $r('app.media.speaker_playing') : $r('app.media.speaker_wave1')) : $r('app.media.speaker')))
                                          .width(12)
                                          .height(12)
                                          .objectFit(ImageFit.Contain)
.onClick(() => {
  this.stopTTS();
  // ★ 0.189.2：口音提示改弹窗（英式无包/美式缺包——showAccentDialogs 共用工厂）
  wordSpeaker.speak(wordSpeaker.textForItem(w), showAccentDialogs(this.getUIContext()));
})
                                      }
                                      }
                                    }
                                    .scrollable(ScrollDirection.Horizontal)
                                    .scrollBar(BarState.Off)
                                    .align(Alignment.Start)
                                    .layoutWeight(1)
                                  }
                                  .width('100%')
                                  // 内容行：全称+释义（「答案」侧）独立横滑——双面模式展开即显（0.224.0 反面语义不变）
                                  if (this.faceMode.mode !== 'double' || this.reviewExpandKey === `${msg.messageId}|${w.id}`) {
                                    Scroll() {
                                      Column() {
                                      if (w.fullName.length > 0) {
                                        // ★ 0.169.1：全称行划词（缩略词全称/中译英答案）
                                        // ★ 0.232.1：全称可点=展开评分（点击区扩大——与音标/释义同规）
                                        Text(w.fullName, { controller: this.getOrCreateTextController(`${msg.messageId}|rwf${idx}`) })
                                          .fontSize(this.fs(12))
                                          .fontColor(this.theme.textSecondary) // ★ 0.274.0 用户拍板：全称行格式与释义行统一（去紫色高亮）
                                          .maxLines(1)
                                          .margin({ top: 1 })
                                          .copyOption(CopyOptions.LocalDevice)
                                          .onClick(() => {
                                            this.onReviewWordTap(`${msg.messageId}|${w.id}`);
                                          })
                                          .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE) // ★ 0.285.3：可获焦模式（华为二轮正解）——Text 默认 UNFOCUSABLE 划选后不获焦、系统 Ctrl+C 派发给错误组件；本模式点击/划选即入获焦链，系统默认复制直接生效
                                          .focusOnTouch(true) // ★ 0.285.4：拖选起手 press 即申请焦点——textSelectable 只给获焦能力、拖选本身不改焦点归属（华为 Q2），获焦后系统 Ctrl+C 才作用于其选区
                                          .bindSelectionMenu(TextSpanType.TEXT, this.ReviewSelectionToolbar, this.isPcDevice() ? TextResponseType.RIGHT_CLICK : TextResponseType.SELECT, {
                                            onAppear: () => {
                                              this.selKey = `${msg.messageId}|rwf${idx}`;
                                            },
                                            onDisappear: () => {
                                              this.clearSelectionState();
                                            }
                                          })
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
                                     // ★ 0.224.0：双面模式释义=反面内容——隐藏到点词条展开（展开=翻面，释义+评分按钮齐出；
                                     //   单面恒显=现状零回归）
                                     if (this.faceMode.mode !== 'double' || this.reviewExpandKey === `${msg.messageId}|${w.id}`) {
                                       // ★ 0.169.1：释义行划词
                                       // ★ 0.232.1：释义可点=展开评分（用户需求锚点：点翻译内容也要出「生疏/尚可/熟知」）
                                       Text(w.explain, { controller: this.getOrCreateTextController(`${msg.messageId}|rwe${idx}`) })
                                         .fontSize(this.fs(12))
                                         .fontColor(this.theme.textSecondary)
                                         .maxLines(1)
                                         .margin({ top: 2 })
                                         .copyOption(CopyOptions.LocalDevice)
                                         .onClick(() => {
                                           this.onReviewWordTap(`${msg.messageId}|${w.id}`);
                                         })
                                         .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE) // ★ 0.285.3：可获焦模式（华为二轮正解）——Text 默认 UNFOCUSABLE 划选后不获焦、系统 Ctrl+C 派发给错误组件；本模式点击/划选即入获焦链，系统默认复制直接生效
                                         .focusOnTouch(true) // ★ 0.285.4：拖选起手 press 即申请焦点——textSelectable 只给获焦能力、拖选本身不改焦点归属（华为 Q2），获焦后系统 Ctrl+C 才作用于其选区
                                         .bindSelectionMenu(TextSpanType.TEXT, this.ReviewSelectionToolbar, this.isPcDevice() ? TextResponseType.RIGHT_CLICK : TextResponseType.SELECT, {
                                           onAppear: () => {
                                             this.selKey = `${msg.messageId}|rwe${idx}`;
                                           },
                                           onDisappear: () => {
                                             this.clearSelectionState();
                                           }
                                         })
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
                                      }
                                    .alignItems(HorizontalAlign.Start)
                                      }
                                    .scrollable(ScrollDirection.Horizontal)
                                    .scrollBar(BarState.Off)
                                    .align(Alignment.Start)
                                    .width('100%')
                                  }
                                }
                                .alignItems(HorizontalAlign.Start)
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
                            // ★ 0.268.0：AI 序延迟到达替换时 150ms 透明度渐变（Q3 终裁——先本地序、
                            //   结果到了淡入替换，不做骨架屏）；脉冲 @Local 驱动全消息共用（150ms 短暂无感）
                            .opacity(this.siyiSwapPulse ? 0.4 : 1)
                            .animation({ duration: 150 })
                          }

                          // ★ 0.146：知识卡片复习区——库非空时在 AI 气泡底部展示随机 N 张
                          // （N=知识卡片数量，知识库 ⚙ 设置，★ 0.161.2 单卡改多卡；与上方单词复习区并列，
                          // 📖 前缀区分知识库卡片/单词卡片；缓存按消息 ID；每卡独立横向滚动行、纵向排列——与生词区同款）
                          // ★ UI 定稿：卡片 2 行（标题+图片icon/定义）；有图才显示 🖼️ 指示（不用小缩略图）；行内超宽横向滑动
                          // ★ 0.248.6：加数量>0 判断（同生词区——设 0 关闭时整块连同分隔线一起消失）
                           if (this.knowledgeBank.cards.length > 0 && this.knowledgeCountStore.knowledgeCount > 0) {
                            // ★ 0.268.0：分隔线+「✨ 语境优先」微标（同生词区——AI 序生效时才出现）
                            Row() {
                              Divider()
                                .strokeWidth(0.5)
                                .color(this.theme.strokeCard)
                                .layoutWeight(1)
                              if (getRerankCardIds(msg.messageId).length > 0) {
                                Text('✨ 语境优先')
                                  .fontSize(10)
                                  .fontColor(this.theme.brandSecondary)
                                  .margin({ left: 6 })
                              }
                            }
                            .alignItems(VerticalAlign.Center)
                            .margin({ top: 6, bottom: 6 })
                            Column() {
                                ForEach(this.getKnowledgeCards(msg.messageId, this.rerollSeq), (card: KnowledgeCard, idx: number) => {
                                // ★ 0.232.1 标题/内容行分离（用户需求锚点：定义很长横滑时标题跟着滑走被覆盖——
                                //   拆开=标题行常驻不动，仅定义行独立横滑，看内容时标题始终可见）
                                Column() {
                                      Row() {
                                         // ★ 0.169.1：复习区划词——标题/定义行均可长按划词（翻译/入知识库/复制）；
                                         //   key 段前缀 rk*/rkd* 与生词区 rw* 及正文段纯数字 idx 空间隔离
                                         // ★ 0.237.0 军令：字符三角 ▼/▲ → FoldChevron SVG；点标题/点箭头展开 3 档评分
                                         FoldChevron({ expanded: this.reviewExpandKey === `${msg.messageId}|${card.id}` })
                                           .onClick(() => {
                                             this.onReviewWordTap(`${msg.messageId}|${card.id}`);
                                           })
                                         if (getTitleImages(card).length > 0) {
                                           // ★ 0.255.2：标题图 icon 触发器（司忆区图片展示终版方案）——缩略图铺
                                           //   列表行被用户否决；icon 与输入区「添加图片」同款华为透明 svg（统一，
                                           //   彩色/图片直铺太难看）；固定槽位不随标题横滑；点击开统一查看器翻全部
                                           //   标题图；icon 只动查看器三状态、不碰展开态——关查看器返回后原地恒在
                                           Image($r('app.media.image'))
                                             .width(16)
                                             .height(16)
                                             .objectFit(ImageFit.Contain)
                                             .margin({ right: 4 })
                                             .onClick(() => {
                                               this.imgViewer.images = getTitleImages(card);
                                               this.imgViewer.index = 0;
                                               this.imgViewer.visible = true;
                                             })
                                         }
                                         Scroll() {
                                          Text(card.title, { controller: this.getOrCreateTextController(`${msg.messageId}|rk${idx}`) })
                                            .fontSize(this.fs(13))
                                            .fontWeight(600)
                                            .fontColor(this.theme.textSecondary)
                                            .maxLines(1)
                                            .copyOption(CopyOptions.LocalDevice)
                                            .onClick(() => {
                                              this.onReviewWordTap(`${msg.messageId}|${card.id}`);
                                            })
                                            .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE) // ★ 0.285.3：可获焦模式（华为二轮正解）——Text 默认 UNFOCUSABLE 划选后不获焦、系统 Ctrl+C 派发给错误组件；本模式点击/划选即入获焦链，系统默认复制直接生效
                                            .focusOnTouch(true) // ★ 0.285.4：拖选起手 press 即申请焦点——textSelectable 只给获焦能力、拖选本身不改焦点归属（华为 Q2），获焦后系统 Ctrl+C 才作用于其选区
                                            .bindSelectionMenu(TextSpanType.TEXT, this.ReviewSelectionToolbar, this.isPcDevice() ? TextResponseType.RIGHT_CLICK : TextResponseType.SELECT, {
                                              onAppear: () => {
                                                this.selKey = `${msg.messageId}|rk${idx}`;
                                              },
                                              onDisappear: () => {
                                                this.clearSelectionState();
                                              }
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
                                        }
                                        // ★ 0.232.2：align(Start) 必须显式——Scroll 内容默认居中（用户实锤「标题跑中间了」）
                                        .scrollable(ScrollDirection.Horizontal)
                                        .scrollBar(BarState.Off)
                                        .align(Alignment.Start)
                                        .layoutWeight(1)
                                      }
                                      .width('100%')
                                      // ★ 0.224.0：双面模式定义=反面内容——隐藏到点卡片展开（单面恒显=现状零回归）
                                      if (this.faceMode.mode !== 'double' || this.reviewExpandKey === `${msg.messageId}|${card.id}`) {
                                        // ★ 0.169.1：定义行划词
                                        // ★ 0.232.1：定义可点=展开评分（点击区扩大）+ 独立横滑（与标题行分离）
                                        // ★ 0.255.2：内容图 icon 放描述文字之前（终版方案「题面归题面、答案归答案」）——
                                        //   点 icon 开统一查看器只滑内容图；icon 不碰展开态，看图返回后原地恒在可反复点
                                        Row() {
                                          if (getCardImages(card).length > 0) {
                                            Image($r('app.media.image'))
                                              .width(16)
                                              .height(16)
                                              .objectFit(ImageFit.Contain)
                                              .margin({ right: 4 })
                                              .onClick(() => {
                                                this.imgViewer.images = getCardImages(card);
                                                this.imgViewer.index = 0;
                                                this.imgViewer.visible = true;
                                              })
                                          }
                                          Scroll() {
                                          Text(card.definition, { controller: this.getOrCreateTextController(`${msg.messageId}|rkd${idx}`) })
                                            .fontSize(this.fs(12))
                                            .fontColor(this.theme.textSecondary)
                                            .maxLines(1)
                                            .copyOption(CopyOptions.LocalDevice)
                                            .onClick(() => {
                                              this.onReviewWordTap(`${msg.messageId}|${card.id}`);
                                            })
                                             .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE) // ★ 0.285.3：可获焦模式（华为二轮正解）——Text 默认 UNFOCUSABLE 划选后不获焦、系统 Ctrl+C 派发给错误组件；本模式点击/划选即入获焦链，系统默认复制直接生效
                                             .focusOnTouch(true) // ★ 0.285.4：拖选起手 press 即申请焦点——textSelectable 只给获焦能力、拖选本身不改焦点归属（华为 Q2），获焦后系统 Ctrl+C 才作用于其选区
                                             .bindSelectionMenu(TextSpanType.TEXT, this.ReviewSelectionToolbar, this.isPcDevice() ? TextResponseType.RIGHT_CLICK : TextResponseType.SELECT, {
                                               onAppear: () => {
                                                 this.selKey = `${msg.messageId}|rkd${idx}`;
                                               },
                                               onDisappear: () => {
                                                 this.clearSelectionState();
                                               }
                                             })
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
                                          .scrollable(ScrollDirection.Horizontal)
                                          .scrollBar(BarState.Off)
                                          .align(Alignment.Start)
                                          .layoutWeight(1)
                                        }
                                        // ★ 0.233.0：定义行左缘与上方单词区左对齐（0 缩进——用户拍板「翻面左边留空
                                        //   不好看，跟上面的单词库的左对齐」）；原 margin left 18 正是「右边超出一个
                                        //   地方」真凶——margin 叠加在 width('100%') 外部使总宽超 18，右缘突出
                                          .width('100%')
                                          .margin({ top: 2 })
                                       }
                                   }
                                   .alignItems(HorizontalAlign.Start)
                                   .width('100%')
                                   .margin({ top: idx > 0 ? 6 : 0 })
                                   // ★ 0.188.0：评分区——展开 3 档按钮 / 已评分显示下次复习
                                   // ★ 0.198.3 评分区移出横向 Scroll（同生词区根因——Scroll 内宽度约束失效）
                                 this.ratingArea(`${msg.messageId}|${card.id}`, card)
                                 }, (card: KnowledgeCard, idx: number) => `${idx}_${card.title}`)
                             }
                             .alignItems(HorizontalAlign.Start)
                             // ★ 0.268.0：同生词区——AI 序替换 150ms 透明度渐变
                             .opacity(this.siyiSwapPulse ? 0.4 : 1)
                             .animation({ duration: 150 })
                           }
                          }
                          .constraintSize({ maxWidth: '100%' }) // ★ 0.233.0：气泡宽度拉满（用户拍板「用户发的和 AI 回复的宽度全部凑齐拉满、填平对齐」——删除已由左滑/右滑/长按实现）；0.190.3 原 90%、0.148 原约束——长文本行自动换行，防气泡被撑出屏幕右缘（用户截图实证）
                        .padding(10)
                        .borderRadius(RADIUS_CONTROL)
                        .backgroundColor(this.theme.bubbleAiBg) // ★ 0.278.13：AI 气泡底色调暗一档（用户反馈太亮影响阅读集中力）
                        .alignItems(HorizontalAlign.Start) // ★ 0.145：气泡内段落保持左对齐（阅读习惯），气泡整体位置由外层 alignItems 控制

                         // ★ 0.271.0：思考收起行（进入 phase3 后思考卡冻结收起为单行——紫弱高亮，气泡底部；
                         //   ★0.291.4 已删「查看思维链」入口（用户拍板：司忆区已覆盖其价值）；thinkingDoneTick 驱动 Map 渲染重建）
                         if (this.thinkingDoneTick >= 0 && this.thinkingSecondsByMsg.has(msg.messageId) &&
                           this.thinkingTraceByMsg.has(msg.messageId)) {
                           Row({ space: 6 }) {
                             Image($r('app.media.timer'))
                               .width(12)
                               .height(12)
                               .objectFit(ImageFit.Contain)
                             Text(`已深度思考 ${this.thinkingSecondsByMsg.get(msg.messageId)}s`)
                               .fontSize(11)
                               .fontColor(this.theme.brandSecondary)
                               .maxLines(1)
                           }
                           .padding({ left: 10, right: 10 })
                           .margin({ top: 4, bottom: 2 })
                         }

                         // ★ 0.271.0：思考档失败手动降级重试（超时类错误专用——§3.6.3 不自动重发，
                         //   把选择权给用户；点击走 regenerate 链路+本条强制 disabled）
                         if (this.thinkingRetryMsgIds.includes(msg.messageId)) {
                           Text('普通模式重试')
                             .fontSize(12)
                             .fontColor(this.theme.brandSecondary)
                             .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                             .borderRadius(RADIUS_CONTROL)
                             .backgroundColor(this.theme.surfaceSoft)
                             .margin({ left: 10, top: 4 })
                             .onClick(() => {
                               this.retryWithNormalMode(msg);
                             })
                         }

                          // ★ 0.290.0：①段规划卡（planning 态——任务书 §3.6 坑1：不让用户干等）：
                          //   浅紫底思考卡同族视觉语言（0.269 视觉分族纪律延续，禁与钩子卡混用）+
                          //   「正在搭建回答框架」+流式片段预览（前 160 字）+取消钮（取消本条请求与思考卡同款）；
                          //   SP 消耗=两段合并后消息感叹号明细展示（军令：凡 AI 交互必扣必展示）
                          if (this.planningMsgId === msg.messageId) {
                            Column({ space: 6 }) {
                              Row({ space: 8 }) {
                                Image($r('app.media.timer'))
                                  .width(14)
                                  .height(14)
                                  .objectFit(ImageFit.Contain)
                                Text('正在搭建回答框架…')
                                  .fontSize(13)
                                  .fontColor(this.theme.brandSecondary)
                                  .maxLines(1)
                                  .layoutWeight(1)
                                Text('取消')
                                  .fontSize(12)
                                  .fontColor(this.theme.textTertiary)
                                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                                  .onClick(() => {
                                    this.cancelPlanning('user');
                                    this.streamGen += 1; // ★ 0.300.0：代际+1（挂起链路全部死亡）
                                    this.abandonClarify();
                                    if (this.planController !== null) {
                                      this.planController.cancel();
                                      this.planController = null;
                                    }
                                    if (this.streamController !== null) {
                                      this.streamController.cancel();
                                      this.streamController = null;
                                    }
                                    this.isLoading = false;
                                    this.streamPhase = 0;
                                    this.streamingMsgId = '';
                                    this.sishuSpPreview = ''; // ★ 0.300.0：SP 预览复位
                                  })
                              }
                              .width('100%')
                              if (this.planPreview.length > 0) {
                                Text(this.planPreview)
                                  .fontSize(11)
                                  .lineHeight(17)
                                  .fontColor(this.theme.textTertiary)
                                  .maxLines(3)
                                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                                  .width('100%')
                                  .textAlign(TextAlign.Start)
                              }
                            }
                            .width('100%')
                            .padding(10)
                            .borderRadius(RADIUS_CONTROL)
                            .backgroundColor(this.theme.hookBg)
                            .margin({ top: 6 })
                          }

                          // ★ 0.300.0：反问收束卡（枢机 needAsk——对话流内嵌选择题，性格测试 3.0 点选流同款；
                          //   onSubmit=按作答执笔 / onSkip=按默认假设执笔；单任务最多 1 轮）
                          if (this.clarifyState.visible && this.clarifyState.messageId === msg.messageId) {
                            ClarifyCard({
                              onSubmit: (answers: string[]): void => {
                                this.resolveClarify(answers);
                              },
                              onSkip: (): void => {
                                this.resolveClarify(null);
                              }
                            })
                          }

                          // ★ 0.300.0：御史审核卡（streamPhase 9/10 的气泡内体现——审核轮次/重写态可见；
                          //   取消=整条任务终止（审核流挂 streamController 同链取消））
                          if (this.censorBadge.length > 0 && this.streamingMsgId === msg.messageId) {
                            Row({ space: 8 }) {
                              Image($r('app.media.timer'))
                                .width(14)
                                .height(14)
                                .objectFit(ImageFit.Contain)
                              Text(this.censorBadge)
                                .fontSize(13)
                                .fontColor(this.theme.brandSecondary)
                                .maxLines(1)
                                .layoutWeight(1)
                              Text('取消')
                                .fontSize(12)
                                .fontColor(this.theme.textTertiary)
                                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                                .onClick(() => {
                                  this.streamGen += 1;
                                  if (this.streamController !== null) {
                                    this.streamController.cancel();
                                    this.streamController = null;
                                  }
                                  this.isLoading = false;
                                  this.streamPhase = 0;
                                  this.censorBadge = '';
                                  this.streamingMsgId = '';
                                  this.sishuSpPreview = '';
                                })
                            }
                            .width('100%')
                            .padding(10)
                            .borderRadius(RADIUS_CONTROL)
                            .backgroundColor(this.theme.hookBg)
                            .margin({ top: 6 })
                          }

                          // ★ 0.300.0：交付卡（交付型终态——已成稿标记+默认假设标注+形态纠偏入口；
                          //   正文即成品可整体复制（复制钮复用操作行「复制全文」）；纠偏=存档契约切 form
                          //   跳过枢机重跑执笔——全链路唯一零成本高质量标注信号）
                          if (!this.isLoading && this.deliverMsgIds.includes(msg.messageId)
                            && this.deliverContractOf(msg) !== null) {
                            Column({ space: 6 }) {
                              Row({ space: 8 }) {
                                Image($r('app.media.timer'))
                                  .width(14)
                                  .height(14)
                                  .objectFit(ImageFit.Contain)
                                Text(`已成稿 · ${this.deliverGenreOf(msg)}`)
                                  .fontSize(13)
                                  .fontWeight(FontWeight.Medium)
                                  .fontColor(this.theme.brandSecondary)
                                  .maxLines(1)
                                  .layoutWeight(1)
                                Text('这不是我要的形态')
                                  .fontSize(12)
                                  .fontColor(this.theme.textSecondary)
                                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                                  .borderRadius(10)
                                  .backgroundColor(this.theme.surfaceSoft)
                                  .border({ width: 1, color: this.theme.strokeCard })
                                  .onClick(() => {
                                    this.correctForm(msg);
                                  })
                              }
                              .width('100%')
                              if (this.deliverAssumptionsOf(msg).length > 0) {
                                Text(`默认假设：${this.deliverAssumptionsOf(msg)}`)
                                  .fontSize(11)
                                  .lineHeight(16)
                                  .fontColor(this.theme.textTertiary)
                                  .width('100%')
                              }
                            }
                            .width('100%')
                            .padding(10)
                            .borderRadius(RADIUS_CONTROL)
                            .backgroundColor(this.theme.hookBg)
                            .border({ width: 1, color: this.theme.strokeCard })
                            .margin({ top: 6 })
                          }

                         // ★ 0.133：AI 消息操作行（token 统计 + 朗读喇叭三态：🔈 空闲 / ⏳ 合成中 / 🔊 播放中）
                        // ★ 0.146：移入包裹容器——行宽自适应，左缘对齐气泡内文字（margin left 10 = 气泡 padding 10）
                        if (msg.role === 'assistant') {
                          // ★ 0.224.4：操作行整齐划一（用户三要求）——统一间隙 Row({space:8})、按钮 padding 对称 4
                          // ★ 0.235.2：新增复制全文+删除按钮（复制走 copyFullMessage、删除走 requestDeleteMessage 确认链路）
                           // ★ 0.237.4：操作行再重排（用户语音拍板）——按钮组固定顺序：
                           //   喇叭→换一批→复制→删除→刷新（刷新从第2挪到第5收尾）②模型名+token
                          //   右对齐贴行尾（Blank 弹性占位推开）③左右边距对称：padding left/right 10——
                          //   最左喇叭离气泡内容左缘 = 「输出 N」末字离气泡内容右缘（width 100% 内 padding，
                          //   margin 会叠加在 100% 之外致溢出）④模型名/token 上限改百分比自适应（35%/50%
                          //   替代写死 100）+flexShrink 收缩兜底——宽屏静态铺开、窄屏自动可滑，滚动条横杠全隐藏
                          Row({ space: 8 }) {
                            // ★ 0.195.0：喇叭三态 emoji（🔈⏳🔊 彩色）换单色 svg——形状即状态：
                            //   cone=空闲 / dots=合成中 / waves=播放中（★ 0.237.3 从行尾挪最前）
                            Row() {
                              Image(this.ttsLoadingMessageId === msg.messageId ? $r('app.media.speaker_loading') : (this.playingMessageId === msg.messageId ? (speakerPulse.wave ? $r('app.media.speaker_playing') : $r('app.media.speaker_wave1')) : $r('app.media.speaker')))
                                .width(14)
                                .height(14)
                                .objectFit(ImageFit.Contain)
                            }
                            .padding(4)
                            .onClick(() => {
                              this.startTTS(msg);
                            })
                            // ★ 0.237.3：换一批——本条回复下方生词/知识卡复习区整批轮换
                            //   （shuffle 交叉双箭头，非刷新语义；图标白 65% 与全行统一；
                            //   ★ 0.237.4 从第3挪到第2，紧跟喇叭）
                            Row() {
                              Image($r('app.media.shuffle'))
                                .width(14)
                                .height(14)
                                .objectFit(ImageFit.Contain)
                            }
                            .padding(4)
                            .onClick(() => {
                              this.shuffleReviewBatch(msg.messageId);
                            })
                            // ★ 0.235.2：复制全文——本条 AI 回复剥锚点标记后整段写剪贴板
                            Row() {
                              Image($r('app.media.copy'))
                                .width(14)
                                .height(14)
                                .objectFit(ImageFit.Contain)
                            }
                            .padding(4)
                            .onClick(() => {
                              this.copyFullMessage(msg);
                            })
                            // ★ 0.235.2：删除本条回复——复用滑动删除同一确认链路
                            Row() {
                              Image($r('app.media.trash'))
                                .width(14)
                                .height(14)
                                .objectFit(ImageFit.Contain)
                            }
                            .padding(4)
                            .onClick(() => {
                              this.requestDeleteMessage(msg.messageId);
                            })
                             // ★ 0.149：刷新按钮——原位重新生成本条 AI 回复
                             // ★ 0.195.0：🔄 emoji 换 refresh.svg 单色图标（UI 统一）
                             // ★ 0.237.4：从第2挪到第5收尾（用户拍板，低频 destructive 前置、再生垫后）
                             Row() {
                               Image($r('app.media.refresh'))
                                 .width(14)
                                 .height(14)
                                 .objectFit(ImageFit.Contain)
                             }
                             .padding(4)
                             .onClick(() => {
                               this.regenerateMessage(msg);
                             })
                             // ★ 0.286.0：举报本条 AI 内容（上架合规 G.3.8——AI 模块显著举报入口）：
                             //   确认后拉起邮件（无邮件应用降级复制邮箱），正文自动附模型 ID
                             Row() {
                               Image($r('app.media.flag'))
                                 .width(14)
                                 .height(14)
                                 .objectFit(ImageFit.Contain)
                             }
                             .padding(4)
                             .onClick(() => {
                               this.requestReportMessage(msg.model);
                             })
                            // ★ 0.237.3：弹性占位——把右侧模型信息组推到行尾（右对齐）
                            Blank()
                            // ★ 0.238.0：token 合并单一滑动区（方案 1 拍板）——手机滑一次看全，
                            //   割裂感根除；宽屏（Pad/PC）放得下时视觉与合并前一致（两段文字本就紧挨着）；
                            //   上限 60%（合并后总内容更长给足空间）+ flexShrink 窄屏收缩兜底
                            //   ★ 0.247.0：模型名上移顶栏，本行只留 token 统计（用户拍板）
                            //   ★ 0.247.3：本行改显 AIGC 合规标识「内容由 AI 生成 · 仅供参考」灰色小字
                            //   （原 token 行同格式同色号；顶栏只留静态模型名）+ 右侧感叹号圆圈 icon；
                            //   点感叹号 bindPopup 弹 token 明细（输入 N · 输出 N）——单开互斥挂 tokenInfoMsgId
                            if (msg.outputTokens > 0) {
                              Row() {
                                Text(this.topBarModelText()) // ★ 0.278.4：改显模型名（用户拍板——声明句移到输入框下方全局一行；ⓘ 弹 token 明细不变）
                                  .fontSize(11)
                                  .fontColor(this.theme.textTertiary)
                                  .maxLines(1)
                                  .flexShrink(1)
                                Image($r('app.media.info'))
                                  .width(12)
                                  .height(12)
                                  .objectFit(ImageFit.Contain)
                                  .margin({ left: 4 })
                              }
                              .bindPopup(this.tokenInfoMsgId === msg.messageId, {
                                builder: this.tokenInfoBuilder(),
                                placement: Placement.Top,
                                popupColor: Color.Transparent, // ★ 0.247.5：弹层底色由 builder 自绘卡片接管（默认底太素被用户否）
                                radius: 12,
                                mask: { color: this.theme.overlayLight },
                                onStateChange: (e: PopupStateChangeParam) => {
                                  if (!e.isVisible && this.tokenInfoMsgId === msg.messageId) {
                                    this.tokenInfoMsgId = '';
                                  }
                                }
                              })
                              .onClick(() => {
                                if (this.tokenInfoMsgId === msg.messageId) {
                                  this.tokenInfoMsgId = '';
                                } else {
                                  this.tokenInfoMsgId = msg.messageId;
                                  this.tokenInfoText = this.tokenDisplayText(msg);
                                  // ★ 0.247.4：缓存命中行（节省 SP=命中 token × 省钱比例 ÷7×2，四舍五入——用户口径
                                  //   「拿输入价当标准、差价换算成 SP」；percent=命中占全部输入 token 比例）
                                  //   ★ 0.248.7：改恒显示（用户报「缓存行看不到」——腾讯云 MaaS 对 deepseek-flash
                                  //   恒不透传 cached_tokens（长前缀同前缀两轮 curl 实锤恒 0），原「命中才显示」
                                  //   设计下该行永不出现；改两态：命中>0 紫色省钱行（builder 分色）、未命中普通行
                                  //   消除「功能消失了」的困惑，云端将来支持命中时自然显示省钱）
                                  if (this.spFree()) { // ★ 0.249.0：Lv8 免扣——免费账号无节省概念，缓存行不显示
                                    this.tokenInfoCacheLine = '';
                                  } else if (msg.inputTokens > 0) {
                                    if (msg.cacheHitTokens > 0) {
                                      const percent = Math.round((msg.cacheHitTokens / msg.inputTokens) * 100);
                                      const savedSp = Math.round(msg.cacheHitTokens * SP_CACHE_SAVING_RATIO / SP_TOKEN_DIVISOR * SP_COST_MULTIPLIER);
                                      this.tokenInfoCacheLine = `缓存命中 ${percent}% · 预估节省 ${savedSp} SP`; // ★ 0.247.8：「帮你节省」→「预估节省」（用户拍板——估算属性标注挪到省钱行）
                                    } else {
                                      this.tokenInfoCacheLine = '本轮输入未命中缓存';
                                    }
                                    this.tokenInfoCacheHit = msg.cacheHitTokens > 0;
                                  } else {
                                    this.tokenInfoCacheLine = '';
                                  }
                                  // ★ 0.290.0：伴读编排拆分行随②段伴读退役移除（两段=规划+执笔已并入总账单一展示）
                                  this.tokenInfoHookLine = '';
                                }
                              })
                              .constraintSize({ maxWidth: '60%' })
                              .flexShrink(1)
                            }
                          }
                          .width('100%') // ★ 0.237.3：铺满气泡宽（Blank 推右对齐的前提）
                          .padding({ left: 10, right: 10 }) // ★ 0.237.3：左右边距对称（padding 计入 100% 内，margin 会外溢）；左 10 = 气泡 padding 10
                          .margin({ top: 4 })
                        }
                        }
                        .alignItems(HorizontalAlign.Start) // ★ 0.235.2：操作行贴气泡左缘（用户拍板「其他几个按钮都是左对齐」——推翻 0.148 右对齐）；气泡为最宽子元素不受影响
                      }
                      }
                  }
                  .alignItems(msg.role === 'user' ? HorizontalAlign.Start : HorizontalAlign.End) // ★ 0.145：AI 回复气泡贴右（用户要求右对齐）；用户消息保持靠左

                  // ★ 0.218.5 用户拍板：用户消息常驻红 × 撤除——删除入口改为右滑露回收站圆钮面板
                  //   （ListItem.swipeAction start 侧），点击走原确认链路
                }
                .width('100%')
                .justifyContent(msg.role === 'user' ? FlexAlign.Start : FlexAlign.End)
                // ★ 0.145：移除整行长按手势——划词改为长按气泡文本本身（bindSelectionMenu 自研悬浮栏），
                // 原「选择文本/删除」二级弹窗随之移除
              }
              // ★ 0.235.2 用户拍板：滑动删除方向统一「往右滑」——用户消息与 AI 消息都从 start 侧滑出
              //   回收站圆钮面板（推翻 0.218.5「方向分治」：原用户=start/AI=end 双向分治，用户嫌冗余
              //   「都是一模一样的逻辑」）；样式对齐知识库/单词库终式（44×44 品牌紫圆钮+白 trash 20，
              //   外容器 72 满高 Center）；点击走原确认链路；swipeAction end 不再传=左滑禁用
              //   ★ 0.247.1 用户拍板：仅 PC（鼠标在场）停用滑动删除——鼠标按下拖动=划词手势被 swipe 抢走；
              //   手机/Pad 触摸长按划词与滑动不冲突照常保留；start 传 undefined=不挂删除面板
              .swipeAction({
                start: this.hasMouse ? undefined : (): void => {
                  this.swipeDeleteMessagePanel(msg)
                }
              })
            }, (msg: ChatMessage) => msg.messageId)
          }
          .height('100%') // ★ 0.280.0：原 layoutWeight(1) 上移外层 Stack，改 100% 高参照已定高容器
          .width('100%')
          .padding({ left: 12, right: 12, top: 12 }) // ★ 0.279.12：左右 16→12（用户拍板「对话窗口 x 轴拉宽」）
          .opacity(this.msgAreaOpacity) // ★ 0.162：分支切换过渡动画挂点（消息列表分支）
          // ★ 0.280.0：滚离底部检测——视口末尾 end 未到最后一条消息（上滑看历史）显示「回到底部」钮；
          //   滚回底部（手动/发送新消息自动 scrollEdge）end=lastIndex 自动隐藏；内容不满一屏恒 lastIndex 不出现
          .onScrollIndex((start: number, end: number) => {
            this.showScrollToBottom = end < this.currentMessages.length - 1;
          })
           // ★ 0.191.0 重做：滚动中实时记录高度——aboutToDisappear 在 pop 转场中可能读不到偏移（实测记录丢失→回来跳底部），
           //   改由滚动事件持续写入模块级 Map，退出钩子仅作兜底
           .onScroll(() => {
              this.recordReadingPosition();
            })
            // ★ 0.215.9 对话页 Ctrl+滚轮缩放（用户核心诉求翻案成功）：
            // BaseEvent.getModifierKeyState(['Ctrl'])（API12+，d.ts 实锤支持 Ctrl/Alt/Shift）——
            // 此前"Ctrl 判死"基于 MouseEvent 无按键状态，AxisEvent 继承 BaseEvent 有此方法；
            // Ctrl 按住+滚轮 → 正文/表格/代码块/司忆区字号缩放（fs 体系+持久化全复用）；
            // 未按 Ctrl → 零干预（消息列表正常滚动翻页）；仅宽屏启用（手机端无缩放=既定设计）
            .onAxisEvent((event: AxisEvent) => {
              let ctrl = false;
              try {
                ctrl = event.getModifierKeyState ? event.getModifierKeyState(['Ctrl']) : false;
              } catch (e) {
                ctrl = false;
              }
              const v = event.getVerticalAxisValue();
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
            // ★ 0.235.0 修法 C：触摸抬起草兜底——手机上根容器 onClick 常被滚动/fling 手势竞争吞掉（不派发），
            //   高亮+工具栏滞留（用户实锤「点空白无效」）；onTouch 只读不拦截（不吞事件、不打断 List 滚动）。
            //   仅当「Down 时刻已有选中且 Up 时选中未变」才清除——长按新建选择会改变 selKey，
            //   该次抬手不是「点空白收起」意图（误清会废掉划词功能）
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.selKeyAtTouchDown = this.selKey;
              } else if (event.type === TouchType.Up &&
                this.selKeyAtTouchDown.length > 0 && this.selKey === this.selKeyAtTouchDown) {
                this.closeActiveSelectionMenu();
                this.clearSelectionState();
              }
            })
          }

        }
        .layoutWeight(1)
        .width('100%')

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
                    this.imgViewer.images = [...this.pendingImages];
                    this.imgViewer.index = index;
                    this.imgViewer.visible = true;
                  })
                // ★ 0.246.0：删除钮对齐 UI_GUIDELINES 统一删除控件（用户拍板「红 × 太难看」）——
                //   品牌紫圆钮+白色 trash.svg 回收站图标（同知识库/单词库滑出删除面板设计语言），
                //   小号规格 20×20 圆钮 + 12×12 图标骑缩略图右上角
                Column() {
                  Image($r('app.media.trash_brand'))
                    .width(12)
                    .height(12)
                }
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .width(20)
                .height(20)
                .borderRadius(10)
                .backgroundColor(this.theme.brandPrimary)
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
          .padding({ left: 12, right: 12, top: 8 })
        }

        // ★ 0.291.2：待发文档条——后缀徽章（品牌紫实底白字缩写，白字铁律合规）+
        //   文件名 + 大小 + 删除圆钮（trash_brand 与待发图删除同设计语言）
        if (this.pendingDocs.length > 0) {
          Column({ space: 6 }) {
            ForEach(this.pendingDocs, (d: PendingDoc, index: number) => {
              Row({ space: 8 }) {
                Text(this.docBadgeOf(d.ext))
                  .fontSize(10)
                  .fontColor(Color.White)
                  .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                  .borderRadius(6)
                  .backgroundColor(this.theme.brandPrimary)
                Text(d.name)
                  .fontSize(12)
                  .fontColor(this.theme.textPrimary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(fmtDocSize(d.size))
                  .fontSize(11)
                  .fontColor(this.theme.textTertiary)
                Column() {
                  Image($r('app.media.trash_brand'))
                    .width(12)
                    .height(12)
                }
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .width(20)
                .height(20)
                .borderRadius(10)
                .backgroundColor(this.theme.brandPrimary)
                .onClick(() => {
                  this.removeDoc(index);
                })
              }
              .width('100%')
              .padding({ left: 8, right: 8, top: 5, bottom: 5 })
              .borderRadius(RADIUS_CONTROL)
              .backgroundColor(this.theme.surfaceNode)
              .border({ width: 0.5, color: this.theme.strokeCard })
            }, (d: PendingDoc, index: number) => `${d.uri}_${index}`)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8 })
        }

        // ★ 0.235.0：引用栏——输入框上方小行（引用：前5字… + × 撤销），纯提示不可点跳转（用户拍板
        //   「创建子气泡后再跳转很傻」）；宽度自适应不写死（Q10：跟随输入区 100% 弹性）
        if (this.quoteText.length > 0) {
          Row({ space: 6 }) {
            Text(`引用：${this.quoteShortLabel()}`)
              .fontSize(12)
              .fontColor(this.theme.brandSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text('×')
              .fontSize(15)
              .fontWeight(600)
              .fontColor(this.theme.textTertiary)
              .width(24)
              .height(24)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.quoteText = ''; // 撤销引用（一次性会话态，撤销后可重新划词引用）
              })
          }
          .width('calc(100% - 24vp)')
          .height(30)
          .padding({ left: 12, right: 4 })
          .margin({ left: 12, right: 12, top: 8 })
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(this.theme.surfaceSoft)
          .border({ width: 0.5, color: this.theme.strokeBrand })
        }

        // ★ 0.280.1：输入卡外包 Stack（TopEnd 对齐）——「回到底部」悬浮钮新挂点（用户拍板「放到输入框正上方」）；
        //   按钮 offset 负 y 浮出绘制不占测量（画布 zoom translate 同族），恒贴输入卡上缘——引用栏/待发图出现时跟随下移
        Stack({ alignContent: Alignment.Top }) { // ★ 0.280.2：BottomEnd→Top（用户拍板「1 还在右边」——悬浮钮改输入卡正上方水平居中）
        // ★ 0.270.0 千问式聚焦扩展容器（用户拍板）：输入行 + 聚焦工具栏同包一张圆角卡片——
        //   默认态=现状单行（加子气泡/铅笔/发送▾ 功能位次零变化）；聚焦后卡片内输入框展开两行高 +
        //   下方 icon 工具栏浮现（未来功能膨胀预留位）；聚焦描边高亮（strokeBrand）
        Column() {
        // 输入区域 — ＋添加子气泡 + 输入框 + ✏️画画Icon + 发送▾（★ 0.152 需求重排：
        // 图片添加/对话模式/回复长度收进发送右侧 ▾ 下拉菜单，底栏只留核心三键）
        Row() {
          // ★ 0.151-D：添加子气泡按钮挪到左下角行首（原顶栏文字按钮改 ＋ icon，样式与 BBTreeCanvas 画布 ＋ 同款；
          // 点击在当前气泡下新建子气泡）
          // ★ 0.162：icon ＋ → 🌿（树杈/新枝）——原 ＋ 易被误解为「添加图片」，
          // 换树杈传达「另起一个树杈（新分支）」语义；尺寸样式不变（32×32 圆角 8）
          // ★ 0.182.1：🌿 emoji 换 gitbranch 分叉符号 svg——用户实测反馈「消息页面的左下角 icon 没有换」
          //   （0.182.0 需求1 本意即此处：与 app logo/画布视觉语言统一）；32×32 容器/圆角/底色/描边样式不变
          // ★ 0.278.0 聚焦态按钮切换（图1/图2）：新建气泡树仅未聚焦态显示，聚焦态切发送▾
          if (!this.isInputFocused) {
            Row() {
              Image($r('app.media.gitbranch'))
                .width(20)
                .height(20)
            }
            .width(28) // ★ 0.279.14：32→28（图标仍 20，左右各 4，挤出的横向空间让给文字框）
            .height(32)
            .justifyContent(FlexAlign.Center)
            .margin({ left: 10, right: 0 }) // ★ 0.279.14：图标左缘距卡内 4(Row padding)+10+4(Row 28 内居中)=18vp，再往中间靠 2vp
            .onClick(() => {
              this.getUIContext().getFocusController().clearFocus();
              this.addBubble();
            })
            .transition(TransitionEffect.OPACITY
              .animation({ duration: 200, curve: Curve.EaseOut }))
          }
          // ★ 0.279.18：占位改 Stack 自绘——原生 placeholder 只能纯文本、放不进 mic.svg；
          //   Stack 高度由 TextArea 撑开（尺寸确定，区别于 0.279.16 overlay 未定容器=0 高的翻车）；
          // ★ 0.281.5：占位改「与正文同轴同位」——顶部对齐 + 与 TextArea 完全相同的 padding(8/8/5/5)；
          Stack({ alignContent: Alignment.Start }) {
            if (this.inputText.length === 0 && !this.imeComposing) {
              Row() {
                Text('试一试小艺输入法的')
                  .fontSize(this.isInputFocused ? 16 : 13) // ★ 0.287.3：聚焦态放大到 16＝与 TextArea 正文字号完全一致（用户「字体能放大一点」+ 三次指认不齐的真因：13 号字比 16 号正文小一档，视觉天然不齐）；未聚焦态两侧图标占宽，保持 13 保单行
                  .fontColor(this.theme.textTertiary)
                  .maxLines(1)
                Image($r('app.media.mic'))
                  .width(this.isInputFocused ? 16 : 14)
                  .height(this.isInputFocused ? 16 : 14)
                  .objectFit(ImageFit.Contain)
                  .margin({ left: 1, right: 1 })
                  .opacity(0.85)
                Text('语音转文本功能？')
                  .fontSize(this.isInputFocused ? 16 : 13)
                  .fontColor(this.theme.textTertiary)
                  .maxLines(1)
              }
              .width('100%')
              .height(this.isInputFocused ? 36 : 33) // ★ 0.279.19：不能用 100%（Stack 内百分比高会反向把 Stack 撑满整屏、消息区被挤没）；★ 0.287.5：聚焦 40→36（16 号行高 22 + 上下 9/5，用户「大框高度再矮一点」）
              .padding(this.isInputFocused
                ? { top: 9, bottom: 5, left: 12, right: 8 } // ★ 0.287.5：上下 9/5 让提示与光标一起下沉 2vp（用户「竖条加试一试再往下去一点」）；left 8→12=聚焦时提示比光标多缩进 4vp，等于「第一个试字前打一个空格」（只在进入输入模式生效，光标不动）
                : { top: 7, bottom: 7, left: 8, right: 8 }) // ★ 0.281.5/0.287.4：非聚焦态保持原值——必须与 TextArea 内非聚焦 padding 一致，否则又错位
              .margin({ left: 2, right: 2 }) // ★ 0.287.2：必须与 TextArea 的 margin 2 同值——否则提示起点 5vp、光标起点 7vp，水平差 2vp（用户实机指认「试一试和竖线没对齐」）；盒模型逐项同值才真正同轴
              .alignItems(VerticalAlign.Top) // ★ 0.281.5：顶部对齐（原 Center 在聚焦态 56 高时把提示压到正文下方约 11vp，用户实机指认与光标不在一行）
              .hitTestBehavior(HitTestMode.None)
            }


          TextArea({ text: $$this.inputText, placeholder: '' }) // ★ 0.278.4：加话筒 icon（placeholder 纯文本不支持组件混排，用 emoji 实现）) // ★ 0.278.3：恢复 0.270.1 原文案（用户强拍板不许改写——引导小艺输入法话筒 icon 语音转文本）+字号调小保一行；上一版 0.270.1 文案「试一试小艺输入法的语音转文本功能？」；★ 0.131：去掉 controller 参数（TextAreaController 已移除）
            .key('chatInputField') // ★ 0.216.2：PC 发送后 requestFocus('chatInputField') 重聚焦（连续打字免鼠标回点）
            .onChange((value: string, previewText?: PreviewText) => {
              this.inputText = value;
              // ★ 0.287.2：输入法组词/语音预编辑（未上屏）也视为「已开始输入」——previewText 非空即让位自绘占位；
              //   此前只看已上屏 value，手机输入法打出字未上屏时「试一试」仍显示并与其叠字（用户实机指认）
              this.imeComposing = !!previewText && previewText.value.length > 0;
              this.saveDraft(); // ★ 0.214.2：输入实时写回本气泡草稿（退出再回来继续编）
            })
            .width('100%') // ★ 0.279.18：原 layoutWeight(1) 移到外层 Stack（TextArea 在 Stack 内铺满）
            // ★ 0.195.0：高度改自适应（标注页补充要求框同款，用户指认「他的体验就很好」）——
            //   TextArea 随内容自撑、一行一行长高，136vp（5 行）封顶后内部滚动；
            //   原 0.118 手动行数计算 + 0.195.0 measureTextSize 软换行版在真机密度单位翻车
            //   （1 字跳 3 行，用户实测截图实锤）——整条手动计算链废弃（getter/字段/onAreaChange/measure 全删）
            // ★ 0.270.0 聚焦扩展：聚焦/失焦驱动展开与工具栏——blur 走 150ms 宽限（见 isInputFocused 注释），
            //   宽限内重新聚焦取消收起（PC 发送后 50ms 重聚焦不闪；点工具栏按钮不失焦瞬收）
            .onFocus(() => {
              if (this.inputBlurTimer >= 0) {
                clearTimeout(this.inputBlurTimer);
                this.inputBlurTimer = -1;
              }
              this.isInputFocused = true;
            })
            .onBlur(() => {
              if (this.inputBlurTimer >= 0) {
                clearTimeout(this.inputBlurTimer);
              }
              this.inputBlurTimer = setTimeout(() => {
                this.isInputFocused = false;
                this.inputBlurTimer = -1;
              }, 150);
            })
            // ★ 0.270.0 高度档位（用户拍板「聚焦即展开」）：默认 40 单行紧凑态不变；聚焦展开 76（约两行高）
            //   ——TextArea 随内容自撑语义不变（minHeight 只抬下限不截内容），失焦收回 40（有草稿时随内容自然高）
            .constraintSize({ minHeight: this.isInputFocused ? 36 : 30, maxHeight: 136 }) // ★ 0.279.15：非聚焦 32→30；★ 0.287.5：聚焦 40→36（与占位行同步）
            .animation({ duration: 200, curve: Curve.EaseInOut }) // 高度档位过渡（对齐项目 200ms 动效档）
            // ★ 0.246.0：对称上下 padding——空态单行时占位符「输入问题...」垂直居中（用户截图指认偏上）；
            //   9/9 首轮仍偏上（TextArea 空态渲染高度大于 minHeight 40、内容顶部对齐致下空隙偏大），
            //   12/12 补偿顶对齐偏移；多行增高时对称 padding 不干扰布局
            .padding(this.isInputFocused
              ? { top: 9, bottom: 5, left: 8, right: 8 } // ★ 0.287.5：与占位行上下同值（光标同步下沉 2vp）；left 保持 8——提示多出的 4vp 只属于「空格」，光标不前移
              : { top: 7, bottom: 7, left: 8, right: 8 }) // 非聚焦态与占位行一致
            .backgroundColor(Color.Transparent) // ★ 0.278.2：去 TextArea 自带默认灰底（用户截图实锤=孤立小气泡，图标被留在外面）——容器底色由外层卡统一承担
            .placeholderColor(this.theme.textTertiary) // ★ 0.278.2：占位提示字调浅（用户拍板「太亮了」——提示语低调、与正文区隔）
            .placeholderFont({ size: 13 }) // ★ 0.279.17：恢复原生占位字号 13（0.279.16 自绘 overlay 真机整行不可见已回退；overlay 内 height 100% 相对未定尺寸容器致 0 高）
            // （0.285.3 删 onTextSelectionChange 选区追踪——随 Ctrl+C 自研接管一起退役，复制交还系统默认）
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
              if (event.keyCode === 2047 || event.keyCode === 2048) { // Shift 键本身：维护状态不消费
                this.shiftHeld = event.type === KeyType.Down;
                return false;
              }
              // ★ 0.285.3（华为二轮 Q4 正解）：Ctrl+C 接管整体删除——TextArea 是系统输入组件，
              //   获焦态系统默认 Ctrl+C 复制与系统备忘录同款链路（框架保证可靠性）；自研接管
              //   （选区变量+substring+setData）每一环都可能出错且 return true 拦截后无系统兜底。
              //   划词文本复制走：气泡 Text textSelectable(SELECTABLE_FOCUSABLE) 后系统 Ctrl+C
              //   直接生效 + 右键菜单「复制」+ 页面级 Ctrl+Shift+C 三条链。
              // ★ 0.283.0：Ctrl+V 贴图（PC 需求——截图存剪贴板后键盘直达贴入待发区）。
              //   KEYCODE_V=2038 实锤（keyCode 枚举）；READ_PASTEBOARD 已声明+新 Profile ACL 授权。
              //   拦截策略=放行（return false）：文本粘贴归 TextArea 原生行为（截图场景剪贴板无文本=
              //   系统粘贴零动作，互不打架）；图片走旁路异步贴入（silent=true 无图不弹提示）；
              //   图文混合记录两者都发生=期望行为。异步期间重复按键由 ctrlVPasting 防重入兜底。
              if (event.keyCode === 2038 && event.type === KeyType.Down) {
                let ctrlV = false;
                try {
                  ctrlV = event.getModifierKeyState ? event.getModifierKeyState(['Ctrl']) : false;
                } catch (err) {
                  ctrlV = false;
                }
                if (ctrlV) {
                  this.pasteImageFromClipboard(true);
                }
                return false;
              }
              if (event.keyCode === 2054 && event.type === KeyType.Down) { // KEY_ENTER=2054 实锤
                let shift = false;
                try {
                  shift = event.getModifierKeyState ? event.getModifierKeyState(['Shift']) : false;
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
            .margin({ left: 2, right: 2 }) // ★ 0.279.14：6→2（用户要求缩 margin 把文字框放大；呼吸间距由图标侧 padding 承担）
            // ★ 0.275.1 拖拽事件穿透（华为官方答复实锤根因：TextArea 属「默认可拖入组件」自带默认拖入处理，
            //   拖拽点落在其上事件被组件吞掉、外层根容器 onDrop 零回调）——allowDrop(null)=拒绝所有拖入类型，
            //   事件落到根容器三件套（全页面释放区），拖图无论落点都进待发区
            .allowDrop(null)
          }
          .layoutWeight(1)

          // ★ 0.152：画画Icon（屏幕圈选标注，核心新增亮点）——点击截取当前屏幕画面进入涂鸦标注页；
          // 原底栏 🖼️ 图片按钮与 💬 模式按钮移入发送右侧 ▾ 下拉菜单
          // ★ 0.195.0：✏️ emoji 换 edit.svg 单色图标（UI 统一——屏幕圈选标注入口）
          // ★ 0.278.0：屏幕圈注仅未聚焦态显示（图2 拍板——聚焦态删除）
          if (!this.isInputFocused) {
            Row() {
              Image($r('app.media.edit'))
                .width(20)
                .height(20)
                .objectFit(ImageFit.Contain)
            }
            .padding({ left: 2, right: 2 })
            .margin({ left: 0, right: 12 }) // ★ 0.279.14：8→12（图标右缘距卡内 4+12+2=18vp，与左侧 18vp 等距且两侧再往中间各靠 2vp）
            .onClick(() => {
              this.getUIContext().getFocusController().clearFocus();
              this.startAnnotation();
            })
            .transition(TransitionEffect.OPACITY
              .animation({ duration: 200, curve: Curve.EaseOut }))
          }

          // ★ 0.282.0：发送键迁至输入卡下层工具行右下角（参考 DeepSeek 布局，行内旧位置退役）
        }
        .width('100%')
        .padding({ left: 4, right: 4, top: 2, bottom: 2 }) // ★ 0.279.15：上下 5→3；★ 0.287.5：3→2（高度再压 2vp，上下对称让内容在卡内居中）
        .opacity(this.importArrived) // ★ 0.200.0：导入落地渐显（L3 末拍 0→1 300ms；常态恒 1 不影响日常输入/截图）
          if (this.isInputFocused) { // ★ 0.282.0：工具行仅聚焦态弹出（默认态保持 左树杈/中间提示/右圈注 三件）
          // ★ 0.282.0 输入区工具行重构（用户拍板，参考 DeepSeek 布局）；
          // ★ 0.287.3 二次重排（用户对照参考图拍板）：①「深度思考」更名「司枢模式」（司=掌管、枢=中枢，
          //   指在 DeepSeek 深度思考之上再加钩子层的那套模式，避免与 DS 原生「深度思考」混淆）；
          //   ②加号从行首移到发送键左侧（右侧成组，参考图右组=＋+发送）；③左右各内缩 10vp，按钮不再贴卡内缘。
          Row() {
            // 左：司枢模式开关——关=中回复（默认）/ 开=长回复（恒深度思考+锚点+分节+伴读）
            Row({ space: 4 }) {
              Image($r('app.media.timer'))
                .width(14)
                .height(14)
                .objectFit(ImageFit.Contain)
              Text('司枢模式')
                .fontSize(12) // ★ 0.287.4：11→12（用户「左下角司枢模式大一点」）
                .fontColor(this.replyLengthMode === 'long' ? Color.White : this.theme.textSecondary)
                .maxLines(1)
            }
            .height(28) // ★ 0.287.4：26→28 随字号抬一档
            .padding({ left: 9, right: 11 })
            .borderRadius(14)
            .backgroundColor(this.replyLengthMode === 'long' ? this.theme.brandPrimary : Color.Transparent)
            .border({ width: 0.5, color: this.replyLengthMode === 'long' ? Color.Transparent : this.theme.strokeCard })
            .onClick(() => {
              this.replyLengthMode = this.replyLengthMode === 'long' ? 'medium' : 'long';
            })

            // ★ 0.292.0：联网问答开关——开=AI 可自主搜索/读网页（FC 工具循环，同司枢胶囊视觉语言）
            // ★ 0.300.0：两态化（任务书 §三.1）——「自动」（默认：枢机自主决定+单段关键词预路由）↔
            //   「强制」（任何模式恒挂 tools——Bing 抽风时手动兜底）；点击循环切换，不删除
            Row({ space: 4 }) {
              Image($r('app.media.globe'))
                .width(14)
                .height(14)
                .objectFit(ImageFit.Contain)
              Text(this.webMode === 'force' ? '联网·强制' : '联网·自动')
                .fontSize(12)
                .fontColor(this.webMode === 'force' ? Color.White : this.theme.textSecondary)
                .maxLines(1)
            }
            .height(28)
            .padding({ left: 9, right: 11 })
            .borderRadius(14)
            .backgroundColor(this.webMode === 'force' ? this.theme.brandPrimary : Color.Transparent)
            .border({ width: 0.5, color: this.webMode === 'force' ? Color.Transparent : this.theme.strokeCard })
            .onClick(() => {
              this.webMode = this.webMode === 'force' ? 'auto' : 'force';
              this.showToastSafe(this.webMode === 'force' ? '联网已强制：每次回答都先查资料' : '联网自动：AI 按需决定是否查资料');
            })

            Blank()

            // ★ 0.297.0：+号展开菜单（图片/文件 + 画板）——点 + 切换展开，点按钮收起并执行
            if (this.plusMenuOpen) {
              Row({ space: 8 }) {
                Row({ space: 5 }) {
                  Image($r('app.media.image'))
                    .width(15)
                    .height(15)
                    .objectFit(ImageFit.Contain)
                  Image($r('app.media.file'))
                    .width(15)
                    .height(15)
                    .objectFit(ImageFit.Contain)
                  Text('图片/文件')
                    .fontSize(FONT_SIZE_CAPTION)
                    .fontColor(this.theme.textSecondary)
                    .maxLines(1)
                }
                .height(28)
                .padding({ left: 10, right: 11 })
                .borderRadius(14)
                .backgroundColor(this.theme.surfaceSoft)
                .border({ width: 0.5, color: this.theme.strokeCard })
                .onClick(() => {
                  this.plusMenuOpen = false;
                  this.selectAttachments(); // 原 + 号链路不变（图片+文档混选，合计 9）
                })

                Row({ space: 5 }) {
                  Image($r('app.media.sketch'))
                    .width(15)
                    .height(15)
                    .objectFit(ImageFit.Contain)
                  Text('画板')
                    .fontSize(FONT_SIZE_CAPTION)
                    .fontColor(this.theme.textSecondary)
                    .maxLines(1)
                }
                .height(28)
                .padding({ left: 10, right: 11 })
                .borderRadius(14)
                .backgroundColor(this.theme.surfaceSoft)
                .border({ width: 0.5, color: this.theme.strokeCard })
                .onClick(() => {
                  this.plusMenuOpen = false;
                  this.openSketchBoard(); // 满格守卫 + pushPath 进画板
                })
              }
            }

            // 右组：＋ 添加附件/画板（★ 0.297.0：点按展开双按钮菜单）——紧跟发送键左侧
            Row() {
              Image($r('app.media.plus'))
                .width(18)
                .height(18)
                .objectFit(ImageFit.Contain)
                .rotate({ angle: this.plusMenuOpen ? 45 : 0 }) // 展开态 + 旋转 45° 变 ×（收起暗示）
            }
            .width(28)
            .height(28)
            .justifyContent(FlexAlign.Center)
            .margin({ right: 8 }) // ★ 0.287.4：去掉圆底（用户「+ 号取消外面的圆圈」）——裸图标+保留 28 热区，图标 16→18 补足视觉分量
            .onClick(() => {
              this.plusMenuOpen = !this.plusMenuOpen;
            })

            // 右：发送（圆形向上箭头，右下角；isLoading 半透明置灰并屏蔽点击）
            Row() {
              Image($r('app.media.arrow_up'))
                .width(18)
                .height(18)
                .objectFit(ImageFit.Contain)
            }
            .width(32)
            .height(32)
            .borderRadius(16)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(this.theme.surfaceHover)
            .opacity(this.isLoading ? 0.45 : 1)
            .onClick(() => {
              if (!this.isLoading) {
                this.sendMessage();
              }
            })
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 0, bottom: 0 }) // ★ 0.287.3：左右 4→10（按钮不贴边）；★ 0.287.4：上下 2→0（用户「里面上下两层往中间靠一点」）
          }

          // ★ 0.278.0：0.270.0 聚焦工具栏整块移除（用户拍板图2——聚焦态唯一入口「屏幕圈住」删除；
          //   未来功能膨胀预留位需要时从 git 历史找回）
        }
        .borderRadius(24) // ★ 0.278.4：圆角 10→24（用户拍板——上下圆弧转好看，胶囊感）
        .backgroundColor(this.theme.surfaceSoft) // ★ 0.278.2：恢复容器底色（用户看实机后拍板「像 ChatCube 一样把功能键全包进去」）——唯一容器承担底色，图标裸放其上（TextArea 已透明不再有小气泡）
        .border({ width: 0.5, color: (this.dragImageOver || this.isInputFocused) ? this.theme.strokeBrand : Color.Transparent }) // ★ 0.278.1：常态无边框，仅聚焦/拖图悬停显描边反馈

        // ★ 0.280.1：「回到底部」悬浮钮（上滑看历史时出现，点击滚到最底）——输入卡正上方右侧、
        //   水平居中、恒贴卡上缘（底缘距卡顶 8vp）；底色 backgroundEffect 自定义玻璃（0.280.3 官方 AI 终式，取代 0.280.1 backgroundBlurStyle
        //   真毛玻璃——COMPONENT_THICK 深色蒙版过深真机显实色）；箭头 18vp 双主题 svg 不变；150ms 透明过渡
        if (this.showScrollToBottom && this.currentMessages.length > 0) {
          Column() {
            Image($r('app.media.arrow_down'))
              .width(18)
              .height(18)
              .objectFit(ImageFit.Contain)
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          // ★ 0.280.3 官方 AI 终式（华为客服五问答复）：backgroundEffect 自定义玻璃——color 的 alpha 全权决定
          //   透明度（10% 白玻璃），取代 0.280.1 COMPONENT_THICK（组件材质组第二厚档、深色模式蒙版深且
          //   不透明度高=真机实色深底的根因）；radius 20~40 宜小面积；三模糊接口同组件仅最后生效，禁再叠
          //   backgroundBlurStyle/backgroundColor；Stack+offset 浮层采样正常（offset 只改绘制位置）
          .backgroundEffect({
            radius: 24,          // 模糊半径，小面积组件官方建议 20~40
            saturation: 1.1,     // 轻微提饱和，增强「透光」质感
            brightness: 1.05,    // 轻微提亮，模拟玻璃反光
            color: '#03FFFFFF'   // ★ 0.280.6：1% 白玻璃（用户指定「1%」；alpha 0x03≈1.2%，极限透）
          })
          .border({ width: 0.5, color: '#33FFFFFF' }) // ★ 0.280.3 官方参数：20% 白高光描边（玻璃边缘反光）
          .shadow({ radius: 12, color: '#66000000', offsetX: 0, offsetY: 4 }) // ★ 0.280.3 官方参数：40% 黑浮起阴影
          .offset({ y: -44 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
          .onClick(() => {
            this.scroller.scrollEdge(Edge.Bottom);
            this.showScrollToBottom = false;
          })
        }
        }
        .width('calc(100% - 24vp)') // ★ 0.281.1：100%→calc 补偿（24=左右 margin 12×2）——0.280.1 的 100%+margin 触发 0.279.9 雷（width 百分比配 margin 会溢出、margin 被吃）致输入卡撑满贴边（用户实锤回归）；calc 先减自身边距恢复与消息区 padding 12 同轴；Stack 仍显式定宽防 0.279.19 反向测量雷，内层百分比参照已定容器
        .margin({ left: 12, right: 12, top: 10, bottom: 10 }) // ★ 0.280.1：边距从输入卡 Column 上移到 Stack（原 0.279.16/17 双 margin 合并为本行；Stack 顶=卡顶，悬浮钮 offset 参照才准）

        // ★ 0.278.4：AIGC 全局声明行（用户拍板——「内容由 AI 生成」从每条气泡下移到输入框外最下方，
        //   元宝/千问同款形态；气泡行原位改显模型名）
        // ⚠️0.278.4-fix：本行必须留在根 Column 内部、输入卡之后——严禁插到 Column 闭合「}」与根容器属性链
        //   （width/height/id=chatSnapshotRoot/onDragEnter/onDrop/onClick）之间，否则这些属性会被本 Text 吞掉
        //   （Text 撑满 100% 高 + 带 onClick → 覆盖整页，输入框与功能键全部点不动＝「输入框点不了」真凶）
        Text('内容由 AI 生成 · 仅供参考')
          .fontSize(11)
          .fontColor(this.theme.textTertiary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 0, bottom: 0 }) // ★ 0.279.16：top 4→0（间距已并入输入卡 bottom 10，避免重复叠加；bottom 0 仍为物理最低）
        }
        .width('100%')
        .height('100%')
        .padding({ bottom: this.kbAvoidHeight }) // ★ 0.281.4：键盘高度让位（NONE+高度监听，输入区整体贴在软键盘上沿）
        .id('chatSnapshotRoot') // ★ 0.152：屏幕圈选截图锚点（componentSnapshot.get 截取顶栏+消息列表+输入区当前画面）
        // ★ 0.275.1 图片拖入全页面化（华为官方客服 AI 答复定位根因：TextArea 属「默认可拖入组件」
        //   自带默认拖入处理，拖拽点落在其上时事件被吞、外层容器三件套零回调）——正解方式 B：
        //   ①TextArea .allowDrop(null)（拒绝所有拖入类型=事件穿透，见输入框属性链）
        //   ②三件套挂页面根容器（用户拍板「拖进对话页面即加载」——整个对话页都是释放区，
        //     落点无论在消息区/输入区，图都进待发区并高亮输入卡引导）
        //   ③onDrop 免剪贴板权限（UDMF 通道）；拖图悬停输入卡 strokeBrand 描边反馈
        .onDragEnter((event: DragEvent) => {
          this.dragImageOver = true;
        })
        .onDragLeave((event: DragEvent) => {
          this.dragImageOver = false;
        })
        .onDrop((event: DragEvent) => {
          this.dragImageOver = false;
          this.handleDropImages(event);
        })
        // ★ 0.182.0：点击输入框外任意处收起软键盘——根容器兜底 onClick（ArkUI 点击不冒泡：
        // 有自身 onClick 的按钮/菜单项各自消费不触发此处；TextArea 点击获焦点自消费；
        // 其余空白/消息区点击落到此处 → clearFocus 收键盘，与发送后收键盘同一先例）
        .onClick(() => {
          this.getUIContext().getFocusController().clearFocus();
          // ★ 0.195.0：点空白处同时收起划词悬浮栏——原仅点其他文本触发 onDisappear 取消，
          // 点空白自研菜单滞留不关（用户实测）；closeSelectionMenu 主动关闭 + 状态清理
          this.closeActiveSelectionMenu();
          this.clearSelectionState();
        })
        // ★ 0.285.2（华为官方 AI 答复范式）：页面级复制快捷键 Ctrl+Shift+C——keyboardShortcut
        //   「组件未获焦、只要窗口获焦即响应」，覆盖「划选气泡文本后焦点不在输入框」场景（华为实锤
        //   Ctrl+C 属系统保留键不可绑，非保留组合才可自绑）；华为二轮 Q5：空选中给轻提示，
        //   区分「快捷键没响应」与「无划选」；非空走统一复制链（延迟重试+toast）。
        //   ★ 0.285.3：气泡 Text 已加 textSelectable(SELECTABLE_FOCUSABLE)——系统默认 Ctrl+C
        //   直接生效（主链），本快捷键+右键菜单「复制」为双补充入口。
        .keyboardShortcut('c', [ModifierKey.CTRL, ModifierKey.SHIFT], (): void => {
          // ★ 0.285.5：粘性兜底——表格跨格拖选丢选区（selText 被 onDisappear 清空）时仍可复制
          const text = this.effectiveSelText();
          if (text.length > 0) {
            this.copyTextToClipboard(text);
          } else {
            this.showToastSafe('请先划选文字');
          }
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
            .backgroundColor(this.theme.overlay)

            // 弹窗主体：标题输入框 → 定义输入框 → 图片区 → 保存/取消
            Column() {
              // ★ 0.153：提炼中标题展示秒表计时（每秒 +1），空闲恢复静态标题
              // ★ 0.191.0：文案改「等待服务器返回」（与对话等待态统一，用户指示；秒表计时逻辑保留供超时判断，仅不展示）
              Text(this.knowledgeEditLoading ? '等待服务器返回' : '知识库卡片')
                .fontSize(16)
                .fontWeight(600)
                .fontColor(this.knowledgeEditLoading ? this.theme.brandSecondary : (this.theme.textPrimary))
                .margin({ bottom: 2 })

              // ★ 0.249.1：AI 内容标识（划词「入知识库」与屏幕圈选「存入知识库」两路口共用本弹窗——
              //   弹窗本质=AI 提炼草稿编辑器，恒显灰色小字，样式复刻对话区 0.247.3 标识）
              Text('内容由 AI 生成 · 仅供参考')
                .fontSize(11)
                .fontColor(this.theme.textTertiary)
                .margin({ bottom: 12 })

              // AI 提炼失败提示（输入框仍可手动填写）
              if (!this.knowledgeEditLoading && this.knowledgeEditError.length > 0) {
                Text(this.knowledgeEditError)
                  .fontSize(13)
                  .fontColor(this.theme.danger)
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
                    .fontColor(this.theme.textTertiary)
                    .alignSelf(ItemAlign.Start)
                    .margin({ bottom: 6 })
                  Flex({ wrap: FlexWrap.Wrap }) {
                    ForEach(this.knowledgeSuggestedTags, (t: string) => {
                      Text(t)
                        .fontSize(11)
                        .height(24)
                        .padding({ left: 10, right: 10 })
                        .borderRadius(6)
                        .fontColor(this.isTagPicked(t) ? Color.White : this.theme.brandSecondary)
                        .backgroundColor(this.isTagPicked(t) ? this.theme.brandPrimary : Color.Transparent)
                        .border({ width: 1, color: this.theme.brandSecondary })
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
                      .fontColor(this.theme.textSecondary)
                      .border({ width: 1, color: this.theme.strokeCard, style: BorderStyle.Dashed })
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
                  .backgroundColor(this.theme.surfaceNode)
                  .fontColor(this.theme.textSecondary)
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
                    .fontColor(this.theme.textPrimary)
                    .backgroundColor(this.theme.danger)
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
                  .color(this.theme.strokeCard)
                  .margin({ bottom: 6 })
                ForEach(this.editReviewWords, (w: WordItem, idx: number) => {
                  // ★ 0.233.0：同气泡复习区——单词词条拆两行（用户拍板「单词和解释拆开来」）：
                  //   词行（三角+词+音标+喇叭）常驻独立横滑，全称+释义内容行独立横滑——滑解释词不动
                  Column() {
                    Row() {
                        // ★ 0.237.0 军令：字符三角 ▼/▲ → FoldChevron SVG；点词/点箭头展开 3 档评分
                        FoldChevron({ expanded: this.reviewExpandKey === `edit|${w.id}` })
                          .onClick(() => {
                            this.onReviewWordTap(`edit|${w.id}`);
                          })
                     Scroll() {
                       Row() {
                       Text(w.word)
                         .fontSize(13)
                         .fontWeight(600)
                         .fontColor(this.theme.textSecondary)
                         .maxLines(1)
                         .onClick(() => {
                           this.onReviewWordTap(`edit|${w.id}`);
                         })
                       if (w.usPhonetic.length > 0) {
                         // ★ 0.232.1：音标可点=展开评分（点击区扩大——与气泡复习区同规）
                         // ★ 0.246.0：音标点击改发音（与气泡复习区同规——与旁边喇叭 icon 同行为）
                         Text(w.usPhonetic)
                           .fontSize(12)
                           .fontColor(this.theme.textTertiary)
                           .maxLines(1)
                           .margin({ left: 6 })
                           .onClick(() => {
                             this.stopTTS();
                             wordSpeaker.speak(wordSpeaker.textForItem(w), showAccentDialogs(this.getUIContext()));
                           })
                        // 发音按钮（与气泡复习区同款三态；缩略词播全称）
                        // ★ 0.195.0：喇叭三态 emoji（🔈⏳🔊 彩色）换单色 svg——形状即状态（cone 空闲/dots 合成中/waves 播放中）
                        Image(wordSpeaker.loadingWord === wordSpeaker.textForItem(w) ? $r('app.media.speaker_loading') : (wordSpeaker.speakingWord === wordSpeaker.textForItem(w) ? (speakerPulse.wave ? $r('app.media.speaker_playing') : $r('app.media.speaker_wave1')) : $r('app.media.speaker')))
                          .width(12)
                          .height(12)
                          .objectFit(ImageFit.Contain)
                          .margin({ left: 4 })
.onClick(() => {
  this.stopTTS();
  // ★ 0.189.2：口音提示改弹窗（英式无包/美式缺包——showAccentDialogs 共用工厂）
  wordSpeaker.speak(wordSpeaker.textForItem(w), showAccentDialogs(this.getUIContext()));
})
                      }
                       }
                     }
                     .scrollable(ScrollDirection.Horizontal)
                     .scrollBar(BarState.Off)
                     .align(Alignment.Start)
                     .layoutWeight(1)
                   }
                   .width('100%')
                   // 内容行：全称+释义（「答案」侧）独立横滑——双面模式展开即显（0.224.0 反面语义不变）
                   if (this.faceMode.mode !== 'double' || this.reviewExpandKey === `edit|${w.id}`) {
                     Scroll() {
                       Column() {
                       if (w.fullName.length > 0) {
                      // ★ 0.232.1：全称可点=展开评分（点击区扩大）
                       Text(w.fullName)
                         .fontSize(12)
                         .fontColor(this.theme.textSecondary) // ★ 0.274.0 用户拍板：全称行格式与释义行统一（去紫色高亮）
                         .maxLines(1)
                         .margin({ top: 1 })
                        .onClick(() => {
                          this.onReviewWordTap(`edit|${w.id}`);
                        })
                    }
                    // ★ 0.224.0：双面模式释义=反面内容——隐藏到点词条展开（单面恒显=现状零回归）
                    if (this.faceMode.mode !== 'double' || this.reviewExpandKey === `edit|${w.id}`) {
                      // ★ 0.232.1：释义可点=展开评分（点击区扩大）
                      Text(w.explain)
                        .fontSize(12)
                        .fontColor(this.theme.textSecondary)
                        .maxLines(1)
                        .margin({ top: 2 })
                        .onClick(() => {
                          this.onReviewWordTap(`edit|${w.id}`);
                        })
                    }

                     }
                     .alignItems(HorizontalAlign.Start)
                       }
                     .scrollable(ScrollDirection.Horizontal)
                     .scrollBar(BarState.Off)
                     .align(Alignment.Start)
                     .width('100%')
                   }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')
                  .margin({ bottom: idx === this.editReviewWords.length - 1 ? 0 : 6 })
                  // ★ 0.187.0：评分区 / ★ 0.198.3 移出横向 Scroll（同气泡复习区根因——Scroll 内宽度约束失效）
                  this.ratingArea(`edit|${w.id}`, w)
                }, (w: WordItem) => w.word)
              }
              if (this.editReviewCards.length > 0) {
                Divider()
                  .strokeWidth(0.5)
                  .color(this.theme.strokeCard)
                  .margin({ top: 6, bottom: 6 })
                // ★ 0.160 bugfix: wrap each card in horizontal Scroll (same as bubble review area) —
                // long title/definition could not be swiped and overflowed the dialog (user report)
                // ★ 0.161.2: single card → ForEach over N cards (knowledge-count setting drives N)
                ForEach(this.editReviewCards, (card: KnowledgeCard, idx: number) => {
                // ★ 0.232.1 标题/内容行分离（与气泡复习区同规——定义独立横滑，标题常驻）
                Column() {
                    Row() {
                        // ★ 0.237.0 军令：字符三角 ▼/▲ → FoldChevron SVG；点标题/点箭头展开 3 档评分
                        FoldChevron({ expanded: this.reviewExpandKey === `editcard|${card.id}` })
                          .onClick(() => {
                            this.onReviewWordTap(`editcard|${card.id}`);
                          })
                        if (getTitleImages(card).length > 0) {
                          // ★ 0.255.2：标题图 icon 触发器（同气泡底部司忆区——与输入区「添加图片」同款华为透明 svg）
                          Image($r('app.media.image'))
                            .width(16)
                            .height(16)
                            .objectFit(ImageFit.Contain)
                            .margin({ right: 4 })
                            .onClick(() => {
                              this.imgViewer.images = getTitleImages(card);
                              this.imgViewer.index = 0;
                              this.imgViewer.visible = true;
                            })
                        }
                       Scroll() {
                        Text(card.title)
                          .fontSize(13)
                          .fontWeight(600)
                          .fontColor(this.theme.textSecondary)
                          .maxLines(1)
                          .onClick(() => {
                            this.onReviewWordTap(`editcard|${card.id}`);
                          })
                       }
                       // ★ 0.232.2：align(Start) 必须显式——Scroll 内容默认居中（标题左对齐铁律）
                       .scrollable(ScrollDirection.Horizontal)
                       .scrollBar(BarState.Off)
                       .align(Alignment.Start)
                       .layoutWeight(1)
                    }
                    .width('100%')
                     // ★ 0.224.0：双面模式定义=反面内容——隐藏到点卡片展开（单面恒显=现状零回归）
                      if (this.faceMode.mode !== 'double' || this.reviewExpandKey === `editcard|${card.id}`) {
                        // ★ 0.232.1：定义可点=展开评分（点击区扩大）+ 独立横滑（与标题行分离）
                        // ★ 0.255.2：内容图 icon 放描述文字之前（同气泡底部司忆区终版方案，缩略图条移除）
                        Row() {
                          if (getCardImages(card).length > 0) {
                            Image($r('app.media.image'))
                              .width(16)
                              .height(16)
                              .objectFit(ImageFit.Contain)
                              .margin({ right: 4 })
                              .onClick(() => {
                                this.imgViewer.images = getCardImages(card);
                                this.imgViewer.index = 0;
                                this.imgViewer.visible = true;
                              })
                          }
                          Scroll() {
                            Text(card.definition)
                              .fontSize(12)
                              .fontColor(this.theme.textSecondary)
                              .maxLines(1)
                              .onClick(() => {
                                this.onReviewWordTap(`editcard|${card.id}`);
                              })
                          }
                          .scrollable(ScrollDirection.Horizontal)
                          .scrollBar(BarState.Off)
                          .align(Alignment.Start)
                          .layoutWeight(1)
                        }
                        // ★ 0.233.0：同气泡复习区——定义行左缘 0 对齐上方单词区（margin left 18 右缘超界同根因）
                          .width('100%')
                          .margin({ top: 2 })
                        }
                     }
                    .alignItems(HorizontalAlign.Start)
                    .width('100%')
                    .margin({ bottom: idx === this.editReviewCards.length - 1 ? 0 : 6 })
                   // ★ 0.187.0：评分区 / ★ 0.198.3 移出横向 Scroll（同气泡复习区根因——Scroll 内宽度约束失效）
                   this.ratingArea(`editcard|${card.id}`, card)
                 }, (card: KnowledgeCard, idx: number) => `${idx}_${card.title}`)
              }

              // 保存 / 取消
              // ★ 0.246.0：对齐 UI_GUIDELINES 按钮行规范（六-79 行，0.197.3 定式）——Row space 12 间隙
              //   （禁单侧 margin 挤窄）、等宽等高 height 48、取消=this.theme.surfaceSoft 底灰字（原默认蓝底出戏）、
              //   保存=this.theme.brandPrimary 底、fontSize 13 / Medium / RADIUS_CONTROL 三端统一
              Row({ space: 12 }) {
                Button('取消')
                  .layoutWeight(1)
                  .height(48)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.theme.textSecondary)
                  .backgroundColor(this.theme.surfaceSoft)
                  .borderRadius(RADIUS_CONTROL)
                  .onClick(() => {
                    this.closeKnowledgeEdit();
                  })
                Button('保存入库')
                  .layoutWeight(1)
                  .height(48)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.theme.textPrimary)
                  .backgroundColor(this.theme.brandPrimary)
                  .borderRadius(RADIUS_CONTROL)
                  // ★ 0.153：提炼中/报错/业务超时均置灰不可点击（修复报错态仍可点击的 BUG）；
                  // 仅请求成功结束（loading=false 且无错误）才启用
                  .enabled(!this.knowledgeEditLoading && this.knowledgeEditError.length === 0)
                  .onClick(() => {
                    this.saveKnowledgeCard();
                  })
                // ★ 0.272.0：SP 信息卡（弹窗右下角、确认按钮旁——用户点名位置）——
                //   提炼完成（onUsage 透传）才渲染；提炼中/失败/超时天然不出现
                if (this.knowledgeEditSpText.length > 0) {
                  TokenInfoChip({
                    inputTokens: this.knowledgeEditInTok,
                    outputTokens: this.knowledgeEditOutTok,
                    spText: this.knowledgeEditSpText
                  })
                }
              }
              .width('100%')
              .margin({ top: 12 })

              // ★ 0.153：底部小字提示——取消仅停止后续内容生成（已发送部分不撤回）
              Text('提示：请求提交后，输入内容已发送AI服务，取消仅停止后续内容生成。')
                .fontSize(11)
                .fontColor(this.theme.textTertiary)
                .margin({ top: 8 })
                .width('100%')
            }
            // ★ 0.246.0：宽度收敛断点制（用户截图指认 PC 太宽）——手机 85% 原样、平板与 PC 固定 400
            //   （UI_GUIDELINES 六-12 确认弹窗断点制定式，同 0.225.2 ReminderDialog/AppConfirmDialog 修法）
            .width(this.isTablet ? 400 : '85%')
            .padding(20)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(this.theme.surfaceNode)

            // ── ★ 0.202.2：标签 mini 编辑弹窗（长按改/自定义加）——挂编辑弹窗 Stack 顶层 ──
            if (this.tagEditVisible) {
              Stack() {
                Column() {
                  Blank()
                }
                .width('100%')
                .height('100%')
                .backgroundColor(this.theme.overlay)
                .onClick(() => {
                  this.tagEditVisible = false;
                })
                Column() {
                  Text(this.tagEditOld.length === 0 ? '添加自定义标签' : '修改标签')
                    .fontSize(14)
                    .fontWeight(600)
                    .fontColor(this.theme.textPrimary)
                    .margin({ bottom: 10 })
                  TextInput({ text: this.tagEditNew, placeholder: '标签名（2~6 字最佳）' })
                    .fontSize(14)
                    .width('100%')
                    .height(40)
                    .padding({ left: 12, right: 12 })
                    .borderRadius(RADIUS_CONTROL)
                    .backgroundColor(this.theme.surfaceSoft)
                    .onChange((v: string) => {
                      this.tagEditNew = v;
                    })
                  Row({ space: 12 }) {
                    Button('取消')
                      .layoutWeight(1)
                      .fontColor(this.theme.textSecondary)
                      .backgroundColor(Color.Transparent)
                      .onClick(() => {
                        this.tagEditVisible = false;
                      })
                    Button('确定')
                      .layoutWeight(1)
                      .backgroundColor(this.theme.brandPrimary)
                      .fontColor(this.theme.textPrimary)
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
                .backgroundColor(this.theme.surfaceNode)
                .border({ width: 1, color: this.theme.strokeCard })
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

        // ★ 0.222.22：知识卡入库目标文件夹选择弹窗（点「保存入库」弹出）——渲染在编辑弹窗之后=
        // 同层后绘制在上；点取消/遮罩回到编辑弹窗（草稿不丢），选完文件夹入库+双弹窗齐关。
        if (this.cardFolderPickerVisible) {
          CardFolderPicker({
            isTablet: this.isTablet,
            onPick: (folderId: string): void => {
              this.confirmSaveKnowledgeCard(folderId);
            },
            onClose: (): void => {
              this.cardFolderPickerVisible = false;
            }
          })
        }


        // 全屏图片浏览器（★ 拆分：独立 ImageViewer 组件——store 共享态驱动，右键/长按保存菜单内聚）
        if (this.imgViewer.visible) {
          ImageViewer()
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
            .backgroundColor(this.theme.overlayLight)
            .onClick(() => {
              this.closeWordPopup();
            })

            // 浮窗主体：标题(查询原文) → 查询中/错误/结果 → 加入单词库
            Column() {
              // 查询原文（即渲染顺序首项「单词」）
              Text(this.wordPopupQuery)
                .fontSize(20)
                .fontWeight(600)
                .fontColor(this.theme.textPrimary)
                .maxLines(1)
                .margin({ bottom: 12 })

              // 查询中态
              if (this.wordPopupLoading) {
                Text('查询中...')
                  .fontSize(14)
                  .fontColor(this.theme.textTertiary)
                  .margin({ bottom: 12 })
              }

              // 错误态
              if (!this.wordPopupLoading && this.wordPopupError.length > 0) {
                Text(this.wordPopupError)
                  .fontSize(14)
                  .fontColor(this.theme.danger)
                  .margin({ bottom: 12 })
              }

              // 结果态：渲染顺序固定 单词(标题)→全称→音标→释义；fullName 为空时全称行不渲染（禁止空白占位）
              if (!this.wordPopupLoading && this.wordPopupResult !== null) {
                if (this.wordPopupResult.fullName.length > 0) {
                  Text(this.wordPopupResult.fullName)
                    .fontSize(14)
                    .fontColor(this.theme.textSecondary)
                    .margin({ bottom: 4 })
                }
                if (this.wordPopupResult.usPhonetic.length > 0) {
                  Row() {
                    Text(this.wordPopupResult.usPhonetic)
                      .fontSize(14)
                      .fontColor(this.theme.textSecondary)
                    // ★ 0.149：音标旁发音按钮——缩略词播全称（字母谁都会读）、普通词播单词本身（美式）；三态 🔈/⏳/🔊；点击先停消息朗读（互斥）
                    // ★ 0.150：Button→Text——Button 默认高度（≈40vp）会撑高音标行，Text 无默认高度、行距还原
                    // ★ 0.155：发音文本统一走 wordPopupSpeakText()——中译英播英文译文、原路径播全称/原文
                    // ★ 0.195.0：喇叭三态 emoji 换单色 svg（cone 空闲/dots 合成中/waves 播放中）
                    Image(wordSpeaker.loadingWord === this.wordPopupSpeakText() ? $r('app.media.speaker_loading') : (wordSpeaker.speakingWord === this.wordPopupSpeakText() ? (speakerPulse.wave ? $r('app.media.speaker_playing') : $r('app.media.speaker_wave1')) : $r('app.media.speaker')))
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
                    .fontColor(this.theme.textSecondary)
                    .margin({ bottom: 12 })
                }
              }

              // 「单词已存在」提示（重复添加时显示）
              if (this.wordExistsTip) {
                Text('单词已存在')
                  .fontSize(12)
                  .fontColor(this.theme.danger)
                  .margin({ bottom: 4 })
              }

              // ★ 0.272.0：SP 信息卡（浮窗结果区底部左下角，与加入按钮同排另一侧）——
              //   spText 仅查词成功（onUsage 透传）才非空，加载中/失败天然不渲染
              Row({ space: 8 }) {
                if (this.wordPopupSpText.length > 0) {
                  TokenInfoChip({
                    inputTokens: this.wordPopupInTok,
                    outputTokens: this.wordPopupOutTok,
                    spText: this.wordPopupSpText
                  })
                }
                // 加入单词库按钮（已加入后转灰禁用防重复）
                Button(this.wordPopupAdded ? '已加入' : '加入单词库')
                  .layoutWeight(1)
                  .backgroundColor(this.wordPopupAdded ? (this.theme.surfaceHover) : this.theme.brandPrimary)
                  .fontColor(this.wordPopupAdded ? (this.theme.textTertiary) : this.theme.textPrimary)
                  .enabled(!this.wordPopupAdded && this.wordPopupResult !== null)
                  .onClick(() => {
                    this.addCurrentWordToBank();
                  })
              }
              .width('100%')

              // ★ 0.246.0：翻译浮窗司忆区——查词/等待期顺便学习（与提炼弹窗复习区同款样式；
              //   key 前缀 wpp|/wppcard| 独立命名空间，评分交互复用 reviewExpandKey/reviewRatedMap/ratingArea）
              if (this.wordPopupReviewWords.length > 0) {
                Divider()
                  .strokeWidth(0.5)
                  .color(this.theme.strokeCard)
                  .margin({ top: 12, bottom: 6 })
                ForEach(this.wordPopupReviewWords, (w: WordItem, idx: number) => {
                  Column() {
                    Row() {
                      FoldChevron({ expanded: this.reviewExpandKey === `wpp|${w.id}` })
                        .onClick(() => {
                          this.onReviewWordTap(`wpp|${w.id}`);
                        })
                      Scroll() {
                        Row() {
                          Text(w.word)
                            .fontSize(13)
                            .fontWeight(600)
                            .fontColor(this.theme.textSecondary)
                            .maxLines(1)
                            .onClick(() => {
                              this.onReviewWordTap(`wpp|${w.id}`);
                            })
                          if (w.usPhonetic.length > 0) {
                            // ★ 0.246.0：音标点击改发音（与气泡底部/提炼弹窗复习区三处统一——与旁边喇叭同行为）
                            Text(w.usPhonetic)
                              .fontSize(12)
                              .fontColor(this.theme.textTertiary)
                              .maxLines(1)
                              .margin({ left: 6 })
                              .onClick(() => {
                                this.stopTTS();
                                wordSpeaker.speak(wordSpeaker.textForItem(w), showAccentDialogs(this.getUIContext()));
                              })
                            Image(wordSpeaker.loadingWord === wordSpeaker.textForItem(w) ? $r('app.media.speaker_loading') : (wordSpeaker.speakingWord === wordSpeaker.textForItem(w) ? (speakerPulse.wave ? $r('app.media.speaker_playing') : $r('app.media.speaker_wave1')) : $r('app.media.speaker')))
                              .width(12)
                              .height(12)
                              .objectFit(ImageFit.Contain)
                              .margin({ left: 4 })
                              .onClick(() => {
                                this.stopTTS();
                                wordSpeaker.speak(wordSpeaker.textForItem(w), showAccentDialogs(this.getUIContext()));
                              })
                          }
                        }
                      }
                      .scrollable(ScrollDirection.Horizontal)
                      .scrollBar(BarState.Off)
                      .align(Alignment.Start)
                      .layoutWeight(1)
                    }
                    .width('100%')
                    if (this.faceMode.mode !== 'double' || this.reviewExpandKey === `wpp|${w.id}`) {
                      Scroll() {
                        Column() {
                          if (w.fullName.length > 0) {
                            Text(w.fullName)
                              .fontSize(12)
                              .fontColor(this.theme.brandSecondary)
                              .maxLines(1)
                              .margin({ top: 1 })
                              .onClick(() => {
                                this.onReviewWordTap(`wpp|${w.id}`);
                              })
                          }
                          Text(w.explain)
                            .fontSize(12)
                            .fontColor(this.theme.textSecondary)
                            .maxLines(1)
                            .margin({ top: 2 })
                            .onClick(() => {
                              this.onReviewWordTap(`wpp|${w.id}`);
                            })
                        }
                        .alignItems(HorizontalAlign.Start)
                      }
                      .scrollable(ScrollDirection.Horizontal)
                      .scrollBar(BarState.Off)
                      .align(Alignment.Start)
                      .width('100%')
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')
                  .margin({ top: idx === 0 ? 6 : 0, bottom: idx === this.wordPopupReviewWords.length - 1 ? 0 : 6 })
                  this.ratingArea(`wpp|${w.id}`, w)
                }, (w: WordItem) => `wpp_${w.word}`)
              }
              if (this.wordPopupReviewCards.length > 0) {
                Divider()
                  .strokeWidth(0.5)
                  .color(this.theme.strokeCard)
                  .margin({ top: 6, bottom: 6 })
                ForEach(this.wordPopupReviewCards, (card: KnowledgeCard, idx: number) => {
                  Column() {
                     Row() {
                       FoldChevron({ expanded: this.reviewExpandKey === `wppcard|${card.id}` })
                         .onClick(() => {
                           this.onReviewWordTap(`wppcard|${card.id}`);
                         })
                        if (getTitleImages(card).length > 0) {
                          // ★ 0.255.2：标题图 icon 触发器（同气泡底部/提炼弹窗司忆区——统一华为透明 svg）
                          Image($r('app.media.image'))
                            .width(16)
                            .height(16)
                            .objectFit(ImageFit.Contain)
                            .margin({ right: 4 })
                            .onClick(() => {
                              this.imgViewer.images = getTitleImages(card);
                              this.imgViewer.index = 0;
                              this.imgViewer.visible = true;
                            })
                        }
                       Scroll() {
                         Text(card.title)
                           .fontSize(13)
                           .fontWeight(600)
                           .fontColor(this.theme.textSecondary)
                           .maxLines(1)
                           .onClick(() => {
                             this.onReviewWordTap(`wppcard|${card.id}`);
                           })
                       }
                       .scrollable(ScrollDirection.Horizontal)
                       .scrollBar(BarState.Off)
                       .align(Alignment.Start)
                       .layoutWeight(1)

                    }
                    .width('100%')
                    if (this.faceMode.mode !== 'double' || this.reviewExpandKey === `wppcard|${card.id}`) {
                      // ★ 0.255.2：内容图 icon 放描述文字之前（三处司忆区统一终版方案，缩略图条移除）
                      Row() {
                        if (getCardImages(card).length > 0) {
                          Image($r('app.media.image'))
                            .width(16)
                            .height(16)
                            .objectFit(ImageFit.Contain)
                            .margin({ right: 4 })
                            .onClick(() => {
                              this.imgViewer.images = getCardImages(card);
                              this.imgViewer.index = 0;
                              this.imgViewer.visible = true;
                            })
                        }
                        Scroll() {
                          Text(card.definition)
                            .fontSize(12)
                            .fontColor(this.theme.textSecondary)
                            .maxLines(1)
                            .onClick(() => {
                              this.onReviewWordTap(`wppcard|${card.id}`);
                            })
                        }
                        .scrollable(ScrollDirection.Horizontal)
                        .scrollBar(BarState.Off)
                        .align(Alignment.Start)
                        .layoutWeight(1)
                      }
                      .width('100%')
                      .margin({ top: 2 })
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')
                  .margin({ bottom: idx === this.wordPopupReviewCards.length - 1 ? 0 : 6 })
                  this.ratingArea(`wppcard|${card.id}`, card)
                }, (card: KnowledgeCard, idx: number) => `wppcard_${idx}_${card.title}`)
              }
            }
            .width('70%')
            .padding(20)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(this.theme.surfaceNode)
          }
          .width('100%')
          .height('100%')
          .alignContent(Alignment.Center)
        }

        // ★ 0.222.21：加词目标文件夹选择弹窗（点「加入单词库」弹出）——渲染在翻译浮窗之后=同层后绘制在上，
        // 浮窗保持可见但被遮罩覆盖；选完文件夹浮窗按钮转「已加入」。
        if (this.wordFolderPickerVisible) {
          WordFolderPicker({
            isTablet: this.isTablet,
            onPick: (folderId: string): void => {
              this.confirmAddWordToFolder(folderId);
            },
            onClose: (): void => {
              this.wordFolderPickerVisible = false;
            }
          })
        }

        // ★ 0.235.0：划词引用二选一弹窗（渲染在翻译浮窗/文件夹弹窗之后=同层后绘制在上）
        if (this.quotePickerVisible) {
          QuotePicker({
            isTablet: this.isTablet,
            shortLabel: this.quoteShortLabel(),
            onQuote: (toNewBubble: boolean): void => {
              this.confirmQuote(toNewBubble);
            },
            onCancel: (): void => {
              this.cancelQuotePicker();
            }
          })
        }

        // ★ 0.286.1：AI 读网页渲染通道——按需挂载的 1×1 隐形 Web 组件（SPA 文档站静态抓只有壳，
        //   真渲染后注入脚本取 innerText）。挂载恒 if(true)（0.160 铁律针对「挂载着但初始隐藏」，
        //   此处按需挂/卸干净）；javaScript+domStorage 全开（SPA 依赖）；1×1+近全透明+不参与命中。
        //   渲染期间页面上可能有页面切换音效/网络活动——组件不可见不获焦，用户零感知
        if (this.webRenderActive) {
          Web({ src: 'about:blank', controller: this.webRenderController })
            .onControllerAttached(() => {
              this.webRenderControllerReady = true;
              this.tryStartNextWebRender(); // 首挂载时 controller 才可用——补发起排队的渲染
            })
            .onPageEnd(() => {
              this.onWebRenderPageEnd();
            })
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .onlineImageAccess(true)
            .width(1)
            .height(1)
            .opacity(0.01)
            .hitTestBehavior(HitTestMode.None)
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
            .backgroundColor(this.theme.overlayLight)
            .onClick(() => {
              this.deleteConfirmVisible = false;
            })

            // 弹窗主体：提示文案 → 勾选行 → 取消/删除按钮
            Column() {
              Text('删除这条消息？')
                .fontSize(18)
                .fontWeight(600)
                .fontColor(this.theme.textPrimary)
                .margin({ bottom: 8 })

              Text('删除后不可恢复')
                .fontSize(13)
                .fontColor(this.theme.textTertiary)
                .margin({ bottom: 16 })

              // 勾选行：整行可点（Checkbox 只读展示，避免 Row/Checkbox 双触发）
              Row() {
                Checkbox()
                  .select(this.deleteConfirmNoAsk)
                  .selectedColor(this.theme.brandPrimary)
                  .width(18)
                  .height(18)
                  .hitTestBehavior(HitTestMode.None)
                Text('此次对话不再提示')
                  .fontSize(13)
                  .fontColor(this.theme.textSecondary)
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
                  .backgroundColor(this.theme.surfaceHover)
                  .fontColor(this.theme.textSecondary)
                  .margin({ right: 8 })
                  .onClick(() => {
                    this.deleteConfirmVisible = false;
                  })
                Button('删除')
                  .layoutWeight(1)
                  .backgroundColor(this.theme.danger)
                  .fontColor(this.theme.textPrimary)
                  .onClick(() => {
                    this.confirmDeleteMessage();
                  })
              }
            }
            .width('70%')
            .padding(20)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(this.theme.surfaceNode)
          }
          .width('100%')
          .height('100%')
          .alignContent(Alignment.Center)
        }

        // ★ 0.286.0：AI 内容举报确认弹窗（上架合规 G.3.8——确认后拉起邮件，复刻 deleteConfirm 弹窗样式）
        if (this.reportConfirmVisible) {
          Stack() {
            // 遮罩：点击关闭弹窗（不举报）
            Column() {
              Blank()
            }
            .width('100%')
            .height('100%')
            .backgroundColor(this.theme.overlayLight)
            .onClick(() => {
              this.reportConfirmVisible = false;
            })

            // 弹窗主体：提示文案 → 取消/举报按钮
            Column() {
              Text('举报本条 AI 内容？')
                .fontSize(18)
                .fontWeight(600)
                .fontColor(this.theme.textPrimary)
                .margin({ bottom: 8 })

              Text('将拉起邮件应用向开发者举报该内容，举报内容不包含你的其他数据')
                .fontSize(13)
                .fontColor(this.theme.textTertiary)
                .margin({ bottom: 16 })

              Row() {
                Button('取消')
                  .layoutWeight(1)
                  .backgroundColor(this.theme.surfaceHover)
                  .fontColor(this.theme.textSecondary)
                  .margin({ right: 8 })
                  .onClick(() => {
                    this.reportConfirmVisible = false;
                  })
                Button('举报')
                  .layoutWeight(1)
                  .backgroundColor(this.theme.brandPrimary)
                  .fontColor(this.theme.textPrimary)
                  .onClick(() => {
                    this.confirmReportMessage();
                  })
              }
            }
            .width('70%')
            .padding(20)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(this.theme.surfaceNode)
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
            .backgroundColor(this.theme.overlay)
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
                  .fontColor(this.theme.textPrimary)

                // ★ 0.149：语言标签（与气泡内代码块一致；无语言标识显示 plaintext）
                Text(this.codeZoomLang.length > 0 ? this.codeZoomLang : 'plaintext')
                  .fontSize(12)
                  .fontColor(this.theme.textTertiary)
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
                .backgroundColor(this.theme.surfaceHover)
                .border({ width: 0.5, color: this.theme.strokeBrand })
                .onClick(() => {
                  this.codeZoomWrap = !this.codeZoomWrap;
                })

                // 关闭按钮
                Text('✕')
                  .fontSize(16)
                  .fontColor(this.theme.textTertiary)
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
                    .fontColor(this.theme.codeText)
                    .padding(10)
                    .backgroundColor(this.theme.bgCanvas)
                    .borderRadius(RADIUS_CONTROL)
                    .width('100%')
                    .copyOption(CopyOptions.LocalDevice)
                    .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE) // ★ 0.285.3：可获焦模式（华为二轮正解）——Text 默认 UNFOCUSABLE 划选后不获焦、系统 Ctrl+C 派发给错误组件；本模式点击/划选即入获焦链，系统默认复制直接生效
                    .focusOnTouch(true) // ★ 0.285.4：拖选起手 press 即申请焦点——textSelectable 只给获焦能力、拖选本身不改焦点归属（华为 Q2），获焦后系统 Ctrl+C 才作用于其选区
                    .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, this.isPcDevice() ? TextResponseType.RIGHT_CLICK : TextResponseType.SELECT, {
                      onAppear: () => {
                        this.selKey = 'cz|w';
                      },
                      onDisappear: () => {
                        this.clearSelectionState();
                      }
                    })
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
                      .fontColor(this.theme.codeText)
                      .padding(10)
                      .backgroundColor(this.theme.bgCanvas)
                      .borderRadius(RADIUS_CONTROL)
                      .copyOption(CopyOptions.LocalDevice)
                      .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE) // ★ 0.285.3：可获焦模式（华为二轮正解）——Text 默认 UNFOCUSABLE 划选后不获焦、系统 Ctrl+C 派发给错误组件；本模式点击/划选即入获焦链，系统默认复制直接生效
                      .focusOnTouch(true) // ★ 0.285.4：拖选起手 press 即申请焦点——textSelectable 只给获焦能力、拖选本身不改焦点归属（华为 Q2），获焦后系统 Ctrl+C 才作用于其选区
                      .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, this.isPcDevice() ? TextResponseType.RIGHT_CLICK : TextResponseType.SELECT, {
                        onAppear: () => {
                          this.selKey = 'cz|s';
                        },
                        onDisappear: () => {
                          this.clearSelectionState();
                        }
                      })
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
            .backgroundColor(this.theme.surfaceNode)
          }
          .width('100%')
          .height('100%')
          .alignContent(Alignment.Center)
        }

        // ★ 0.150：全局设置弹窗（顶栏 ⚙ 唤起；遮罩点击不关闭，✕/返回键走弹窗内未保存确认）
        if (this.gsShared.visible) {
          GlobalSettingsDialog({
            onClose: () => {
              this.gsShared.visible = false;
            },
            closeReq: this.gsShared.closeReq
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
            .backgroundColor(this.theme.overlay)
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
                  .fontColor(this.theme.textPrimary)

                Blank()

                // ★ 0.285.5：复制整表——Markdown 源格式（贴回对话/文档/AI 输入框保留表格结构）；
                //   格子架构选区不跨组件，整表拿走走本入口（复制链带延迟重试+成败 toast）
                Text('复制整表')
                  .fontSize(12)
                  .fontColor(this.theme.textPrimary)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .borderRadius(4)
                  .backgroundColor(this.theme.surfaceHover)
                  .border({ width: 0.5, color: this.theme.strokeBrand })
                  .onClick(() => {
                    this.copyTextToClipboard(buildTableMarkdown(this.tableZoomHeader, this.tableZoomRows));
                  })

                // ★ 0.285.5：文本模式切换——整表渲染为一个 Text 可整体划词（翻译/入知识库/引用/
                //   复制/系统 Ctrl+C 全链路）；选中态紫底白字与模式标签同规格
                Text('文本模式')
                  .fontSize(12)
                  .fontWeight(500)
                  .fontColor(this.tableZoomTextMode ? Color.White : this.theme.textPrimary)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .margin({ left: 8 })
                  .borderRadius(4)
                  .backgroundColor(this.tableZoomTextMode ? this.theme.brandPrimary : this.theme.surfaceHover)
                  .border({ width: 0.5, color: this.tableZoomTextMode ? this.theme.brandPrimary : this.theme.strokeBrand })
                  .onClick(() => {
                    this.tableZoomTextMode = !this.tableZoomTextMode;
                  })

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
                .backgroundColor(this.theme.surfaceHover)
                .border({ width: 0.5, color: this.theme.strokeBrand })
                .margin({ left: 8 }) // ★ 0.285.5：新增两按钮后与左侧按钮留间距
                .onClick(() => {
                  this.tableZoomWrap = !this.tableZoomWrap;
                })

                // 关闭按钮
                Text('✕')
                  .fontSize(16)
                  .fontColor(this.theme.textTertiary)
                  .margin({ left: 12 })
                  .onClick(() => {
                    this.tableZoomVisible = false;
                  })
              }
              .width('100%')
              .margin({ bottom: 10 })

              // 表格内容：纵向滚动（外层）；★ 0.285.5 文本模式=整表一个 Text 可整体划词（跨格/
              //   整表划选唯一落点——格子架构选区不跨组件），格子模式=横向滚动（内层）+固定列宽对齐
              Scroll() {
                if (this.tableZoomTextMode) {
                  // ★ 0.285.5：整表 Text（划词五件套 key 'tzt'，无 | 分隔——书签/删除按放大弹窗
                  //   key 族防御忽略，翻译/入知识库/引用/复制/全选/系统 Ctrl+C 全链路可用）
                  Text(buildTablePlainText(this.tableZoomHeader, this.tableZoomRows),
                    { controller: this.getOrCreateTextController('tzt') })
                    .fontSize(14)
                    .lineHeight(24)
                    .fontColor(this.theme.textPrimary)
                    .padding(12)
                    .textAlign(TextAlign.LEFT)
                    .copyOption(CopyOptions.LocalDevice)
                    .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE) // ★ 0.285.3：可获焦模式（华为二轮正解）——Text 默认 UNFOCUSABLE 划选后不获焦、系统 Ctrl+C 派发给错误组件；本模式点击/划选即入获焦链，系统默认复制直接生效
                    .focusOnTouch(true) // ★ 0.285.4：拖选起手 press 即申请焦点——textSelectable 只给获焦能力、拖选本身不改焦点归属（华为 Q2），获焦后系统 Ctrl+C 才作用于其选区
                    .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, this.isPcDevice() ? TextResponseType.RIGHT_CLICK : TextResponseType.SELECT, {
                      onAppear: () => {
                        this.selKey = 'tzt';
                      },
                      onDisappear: () => {
                        this.clearSelectionState();
                      }
                    })
                    .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, TextResponseType.LONG_PRESS, {
                      onAppear: () => {
                        this.selKey = 'tzt';
                      },
                      onDisappear: () => {
                        this.clearSelectionState();
                      }
                    })
                    .onTextSelectionChange((start: number, end: number) => {
                      this.handleSelectionChange('tzt',
                        buildTablePlainText(this.tableZoomHeader, this.tableZoomRows), start, end);
                    })
                    .selection(
                      this.selectAllKey.startsWith('tzt|') ? 0 : 1,
                      this.selectAllKey.startsWith('tzt|') ? buildTablePlainText(this.tableZoomHeader, this.tableZoomRows).length : 0
                    )
                } else {
                Scroll() {
                  Column() {
                    // 表头行
                    Row() {
                      ForEach(this.tableZoomHeader, (cell: string, ci: number) => {
                        // ★ 0.156：划词五件套——放大弹窗表格单元格可划词（key tzh${ci}；wrap 模式完整显示，划词无截断）
                        Text(cell, { controller: this.getOrCreateTextController(`tzh${ci}`) })
                          .fontSize(14)
                          .fontColor(this.theme.textPrimary)
                          .padding(8)
                          .border({ width: 0.5, color: this.theme.strokeCard })
                          .width(this.getTableColWidths(this.tableZoomHeader, this.tableZoomRows)[ci])
                          .maxLines(this.tableZoomWrap ? 999 : 1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .textAlign(TextAlign.Center)
                          .copyOption(CopyOptions.LocalDevice)
                          .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE) // ★ 0.285.3：可获焦模式（华为二轮正解）——Text 默认 UNFOCUSABLE 划选后不获焦、系统 Ctrl+C 派发给错误组件；本模式点击/划选即入获焦链，系统默认复制直接生效
                          .focusOnTouch(true) // ★ 0.285.4：拖选起手 press 即申请焦点——textSelectable 只给获焦能力、拖选本身不改焦点归属（华为 Q2），获焦后系统 Ctrl+C 才作用于其选区
                          .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, this.isPcDevice() ? TextResponseType.RIGHT_CLICK : TextResponseType.SELECT, {
                            onAppear: () => {
                              this.selKey = `tzh${ci}`;
                            },
                            onDisappear: () => {
                              this.clearSelectionState();
                            }
                          })
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
                            .fontColor(this.theme.textSecondary)
                            .padding(8)
                            .border({ width: 0.5, color: this.theme.strokeCard })
                            .width(this.getTableColWidths(this.tableZoomHeader, this.tableZoomRows)[ci])
                            .maxLines(this.tableZoomWrap ? 999 : 1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .textAlign(TextAlign.Center)
                            .copyOption(CopyOptions.LocalDevice)
                            .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE) // ★ 0.285.3：可获焦模式（华为二轮正解）——Text 默认 UNFOCUSABLE 划选后不获焦、系统 Ctrl+C 派发给错误组件；本模式点击/划选即入获焦链，系统默认复制直接生效
                            .focusOnTouch(true) // ★ 0.285.4：拖选起手 press 即申请焦点——textSelectable 只给获焦能力、拖选本身不改焦点归属（华为 Q2），获焦后系统 Ctrl+C 才作用于其选区
                            .bindSelectionMenu(TextSpanType.TEXT, this.SelectionToolbar, this.isPcDevice() ? TextResponseType.RIGHT_CLICK : TextResponseType.SELECT, {
                              onAppear: () => {
                                this.selKey = `tzr${ri}c${ci}`;
                              },
                              onDisappear: () => {
                                this.clearSelectionState();
                              }
                            })
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
            .backgroundColor(this.theme.surfaceNode)
          }
          .width('100%')
          .height('100%')
          .alignContent(Alignment.Center)
        }

        // ★ 0.145：文本预览弹窗已移除——长按气泡文本直接进入系统选择模式 + 自研悬浮操作栏（bindSelectionMenu）


        // ★ 0.152：屏幕圈选首次使用说明弹窗（需求文案原文；确认后记 flag 永不再弹）
        // 遮罩不关闭弹窗——确认只走「知道了」按钮（一次性授权说明，防误触跳过）
        if (this.annotationNotifyVisible) {
          Stack() {
            Column() {
              Blank()
            }
            .width('100%')
            .height('100%')
            .backgroundColor(this.theme.overlay)

            Column() {
              Text('屏幕圈选标注')
                .fontSize(16)
                .fontWeight(600)
                .fontColor(this.theme.textPrimary)
                .margin({ bottom: 10 })
              Text('用于屏幕圈选标注提问，不会后台录制屏幕。')
                .fontSize(14)
                .fontColor(this.theme.textSecondary)
                .margin({ bottom: 16 })
              Button('知道了')
                .fontSize(14)
                .width('100%')
                .backgroundColor(this.theme.brandPrimary)
                .fontColor(this.theme.textPrimary)
                .onClick(() => {
                  this.confirmAnnotationNotify();
                })
            }
            .width('75%')
            .padding(20)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(this.theme.surfaceNode)
          }
          .width('100%')
          .height('100%')
          .alignContent(Alignment.Center)
        }

      }
      .width('100%')
      .height('100%')
      // ★ 0.195.0：根底色补齐 this.theme.bgApp——原根容器未设底色透出窗口纯黑（用户截图实锤 #000000，
      //   与画布/单词库/知识库暗紫底不一致；0.183.0 修三页时本页漏网，本次补上）
      .background(this.theme.bgCanvas) // ★ 0.278.9：background() 背景延伸进安全区（Pad 上下黑边根治）
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.bgCanvas) // ★ 0.278.12：NavDestination 容器级显式背景（华为官方建议双保险）
    // ★ 0.152：标注页 pop 返回时消费标注结果（import/branch/knowledge 三分支；
    // onShown 首次进入及其他页面返回时 action 为空直接跳过）
    .onShown(() => {
      this.setupKbAvoid(); // ★ 0.281.4：键盘让位自控（NONE+高度监听）
      this.consumeCardImport(); // ★ 0.200.0：知识卡片导入落地（画布确认导航进来）
      this.consumeAnnotationResult();
    })
    .onHidden(() => {
      this.teardownKbAvoid(); // ★ 0.281.4：切走他页恢复系统避让（防 NONE 残留影响其他页）
    })
    // ★ 0.153：切后台中断提炼已改由 onAppBackgroundChange（@Monitor 监听全局
    // 前后台标志）实现——NavDestination 组件无 onPageHide 生命周期属性
    // ★ 0.120/0.159：返回拦截统一走 handleBack——有弹窗打开时先关弹窗（消费返回），否则默认返回
    .onBackPressed(() => {
      return this.handleBack();
    })
  }
}

