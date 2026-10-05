// ============================================================
// ChatModel.ets — 全局数据模型定义
// ============================================================
// 本文件定义了 DAG 气泡树聊天系统的核心数据结构：
//   - ChatMessage：单条对话消息（用户/AI/系统）
//   - BubbleNode：气泡节点，每个节点保存一组消息（nodeTitle 节点标题 ★ 0.147），通过 parentID 形成树状结构
//   - BubbleTree：气泡树，包含所有节点
//   - CurrentBubble：当前选中的气泡节点
//   - ApiConfig：API 配置（Key、Endpoint、Model）
//   - PersistData：持久化包装，将整棵树序列化为 JSON 字符串存储
//
// 技术栈：鸿蒙 ArkUI V2
//   - @ObservedV2：标记可观察类，属性变化时自动触发 UI 刷新
//   - @Trace：标记可观察属性，变化时通知依赖的组件更新
// ============================================================

import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI'; // ★ 0.143：connectApiConfig（换 key 迁移）需要 PersistenceV2；★ 0.151：applyCanvasModeSwitch 需要 AppStorageV2
import { util } from '@kit.ArkTS'; // ★ 0.161.3：rawfile config.json 解码（Uint8Array → string）
import { common } from '@kit.AbilityKit'; // ★ 0.161.3：loadBuiltinApiConfig 的 context 参数类型
import { upsertCloudData, registerCloudDataHandler } from '../utils/CloudSyncUtil'; // ★ 0.165.1 云同步桥接（写池后快照上云）；★ 0.165.2 下行处理器注册
import { NODE_W, NODE_H } from './DesignTokens'; // ★ 0.167.3：布局几何参数单一来源（气泡宽 150，防布局与 UI 两处漂移）；★ 0.167.4：NODE_H 供多根纵向堆叠的树高计算

// 角色类型：用户 / assistant / system（火山方舟 v3 接口规范）
export type ChatRole = 'user' | 'assistant' | 'system'; // ★ 新增 'system'（0.117 摘要虚拟消息）

// 单条对话消息
@ObservedV2
export class ChatMessage {
  @Trace messageId: string;
  @Trace role: ChatRole;
  @Trace content: string;
  @Trace imageUrl: string[]; // 多模态图片 URL 数组（Base64 或远程 URL），空数组代表无图片
  @Trace inputTokens: number; // 输入 token 数
  @Trace outputTokens: number; // 输出 token 数
  @Trace isPodcastMode: boolean; // ★ 0.133：本次交互是否以播客模式发起（仅标记存储，MVP 不做视觉区分）

  constructor(messageId: string, role: ChatRole, content: string, imageUrl: string[] = [], inputTokens: number = 0, outputTokens: number = 0,
              isPodcastMode: boolean = false) { // ★ 0.133：可选参数带默认值，现有 7 处调用点不破坏
    this.messageId = messageId;
    this.role = role;
    this.content = content;
    this.imageUrl = imageUrl;
    this.inputTokens = inputTokens;
    this.outputTokens = outputTokens;
    this.isPodcastMode = isPodcastMode;
  }
}

// 气泡节点（对话树中的一个节点）
@ObservedV2
export class BubbleNode {
  @Trace nodeID: string;
  @Trace parentID: string | null;
  @Trace messages: ChatMessage[];
  @Trace x: number;
  @Trace y: number;
  @Trace parentX: number; // 冗余存储父节点 x，避免 find 读取 @Trace 断链
  @Trace parentY: number; // 冗余存储父节点 y
  @Trace historySummary: string; // ★ 新增：分支链路摘要（0.117）
  @Trace historySummaryCount: number; // ★ 新增：上次生成摘要时的链路消息总数（0.117）
  @Trace nodeTitle: string; // ★ 0.147：节点标题（空串=自动取第一条用户提问，非空=用户手动覆盖）

  constructor(nodeID: string, parentID: string | null, messages: ChatMessage[], x: number, y: number, parentX: number = 0, parentY: number = 0,
              historySummary: string = '', historySummaryCount: number = 0, nodeTitle: string = '') {
    this.nodeID = nodeID;
    this.parentID = parentID;
    this.messages = messages;
    this.x = x;
    this.y = y;
    this.parentX = parentX;
    this.parentY = parentY;
    this.historySummary = historySummary;
    this.historySummaryCount = historySummaryCount;
    this.nodeTitle = nodeTitle;
  }
}

// V2 全局状态：包装 nodeList，AppStorageV2 内存（持久化通过 PersistData JSON）
@ObservedV2
export class BubbleTree {
  @Trace nodeList: BubbleNode[] = [];
  @Trace needsRelayout: boolean = false; // ★ 0.126：标记需要重新布局（新建气泡后触发）

  constructor(nodeList: BubbleNode[] = []) {
    this.nodeList = nodeList;
  }
}

// ── 持久化包装：PersistenceV2 只存一个 JSON 字符串 ──
@ObservedV2
export class PersistData {
  @Trace bubbleTreeJson: string = '';
}

// 序列化接口
interface SerializedMessage {
  messageId: string;
  role: string;
  content: string;
  imageUrl: string[];
  inputTokens: number;
  outputTokens: number;
  isPodcastMode?: boolean; // ★ 0.133 新增（可选字段，旧数据无此字段，反序列化时 ?? false 兜底）
}
interface SerializedNode {
  nodeID: string;
  parentID: string | null;
  messages: SerializedMessage[];
  x: number;
  y: number;
  parentX: number;
  parentY: number;
  historySummary?: string; // ★ 新增（0.117）
  historySummaryCount?: number; // ★ 新增（0.117）
  nodeTitle?: string; // ★ 0.147（可选字段，旧数据无此字段，反序列化时 ?? '' 兜底）
}
interface SerializedTree {
  nodeList: SerializedNode[];
}

// 序列化 BubbleTree → JSON 字符串
export function serializeBubbleTree(tree: BubbleTree): string {
  const data: SerializedTree = {
    nodeList: tree.nodeList.map((node: BubbleNode): SerializedNode => {
      const msgs: SerializedMessage[] = node.messages.map((msg: ChatMessage): SerializedMessage => {
        return {
          messageId: msg.messageId,
          role: msg.role,
          content: msg.content,
          imageUrl: msg.imageUrl,
          inputTokens: msg.inputTokens,
          outputTokens: msg.outputTokens,
          isPodcastMode: msg.isPodcastMode // ★ 0.133
        };
      });
      return {
        nodeID: node.nodeID,
        parentID: node.parentID,
        messages: msgs,
        x: node.x,
        y: node.y,
        parentX: node.parentX,
        parentY: node.parentY,
        historySummary: node.historySummary,
        historySummaryCount: node.historySummaryCount,
        nodeTitle: node.nodeTitle // ★ 0.147
      };
    })
  };
  return JSON.stringify(data);
}

// 反序列化 JSON → BubbleTree
export function deserializeBubbleTree(json: string): BubbleTree | null {
  if (!json || json.length === 0) {
    return null;
  }
  try {
    const data: SerializedTree = JSON.parse(json) as SerializedTree;
    const nodeList: BubbleNode[] = data.nodeList.map((node: SerializedNode): BubbleNode => {
      const messages: ChatMessage[] = node.messages.map((msg: SerializedMessage): ChatMessage => {
        return new ChatMessage(msg.messageId, msg.role as ChatRole, msg.content, msg.imageUrl, msg.inputTokens ?? 0, msg.outputTokens ?? 0,
          msg.isPodcastMode ?? false); // ★ 0.133：旧数据无此字段自动补 false，不报错不丢失
      });
      return new BubbleNode(node.nodeID, node.parentID, messages, node.x, node.y, node.parentX, node.parentY,
        node.historySummary ?? '', node.historySummaryCount ?? 0, node.nodeTitle ?? ''); // ★ 0.147：旧数据无此字段自动补空串
    });
    return new BubbleTree(nodeList);
  } catch (e) {
    return null;
  }
}

// V2 全局状态：当前选中的气泡 ID + 坐标
@ObservedV2
export class CurrentBubble {
  @Trace nodeID: string = '';
  @Trace bubbleX: number = 0; // 双击时存入 bubble.x，供 ChatPage addBubble 使用
  @Trace bubbleY: number = 0;
}

// 生成唯一气泡 ID
export function generateNodeId(): string {
  return `bubble_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
}

// 生成唯一消息 ID
export function generateMessageId(): string {
  return `msg_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
}

// API 配置（火山引擎方舟）：PersistenceV2 持久化，跨重启保存
@ObservedV2
export class ApiConfig {
  // ★ 0.161.3：内置 Key 从源码硬编码改为 rawfile/config.json 读取（该文件 .gitignore 忽略绝不入库，
  // 源码可安全上传 GitHub）；默认值改空串，由 EntryAbility 启动时调 loadBuiltinApiConfig 填充。
  // 用户在设置页自定义过的 Key（持久化非空）优先，不被内置值覆盖。
  @Trace apiKey: string = '';
  @Trace endpoint: string = 'https://ark.cn-beijing.volces.com/api/v3/chat/completions';
  @Trace model: string = 'deepseek-v4-flash-ga-260731'; // ★ 0.190.1：默认模型换 V4-Flash 正式版（用户指定；旧 260910 预览版已被替代，设置页回显时 mapLegacyModel 自动映射）
  @Trace provider: string = 'volcano'; // ★ 0.190.0：模型提供商（huawei/volcano/deepseek/custom；预设端点+模型清单见 GlobalSettingsDialog PROVIDER_PRESETS，ApiClient 不感知——端点/模型/Key 全走本类字段）
  @Trace audioModel: string = 'seed-tts-2.0'; // ★ 0.139：音频模型资源 ID（语音合成-2.0，openspeech HTTP 单向流端点，官方文档实证）
  @Trace audioVoice: string = 'zh_female_vv_uranus_bigtts'; // ★ 0.139：TTS 音色 ID（2.0 格式；2.0 模型只能用 2.0 音色，设置页不显示音色框）
  @Trace audioEndpoint: string = 'https://openspeech.bytedance.com/api/v3/tts/unidirectional'; // ★ 0.139：TTS 端点（openspeech HTTP 单向流，与 LLM endpoint 相互独立）
  // ★ 0.161.3：TTS 专用 Key 同样改 rawfile/config.json 读取（与方舟对话 Key 相互独立——两套体系
  // Key 不通用，0.139 拿方舟 Key 实测 401 Invalid X-Api-Key）
  @Trace audioKey: string = '';
}

// ★ 0.190.0：由端点推断提供商（v2→v3 迁移用——存量用户只可能是火山默认端点或自定义端点；
// 华为 MaaS / DeepSeek 为 0.190.0 新增预设，旧数据不会是这两家）
export function inferProviderFromEndpoint(endpoint: string): string {
  if (endpoint.includes('volces.com')) {
    return 'volcano';
  }
  if (endpoint.includes('modelarts-maas.com')) {
    return 'huawei';
  }
  if (endpoint.includes('api.deepseek.com')) {
    return 'deepseek';
  }
  return 'custom';
}

// ★ 0.143：连接 API 配置持久化实例——key 从 'api-config' 换为 'api-config-v2'
// 根因：PersistenceV2 磁盘旧快照（0.140 之前创建）没有 audioKey 字段，新增属性写不进旧快照、
// 重启即丢（用户实测：对话 Key 能存、音频 Key 不能存——差异即根因实锤）。换 key 强制重建全量
// 快照（新快照出生即含全部字段），audioKey 从此与 apiKey 同等持久化。工厂函数内读旧 key 数据
// 迁移历史配置（对话 Key/端点/模型等），用户无需重填；audioKey 旧快照从未存成功，需重填一次。
// ★ 0.190.0：key 再从 'api-config-v2' 换为 'api-config-v3'——同理（新增 provider 字段写不进
// v2 旧快照）；v2 数据全量迁移（含休眠音频字段），provider 由端点推断（inferProviderFromEndpoint）。
export function connectApiConfig(): ApiConfig {
  return PersistenceV2.connect(ApiConfig, 'api-config-v3', () => {
    const old = PersistenceV2.connect(ApiConfig, 'api-config-v2', () => new ApiConfig()) as ApiConfig;
    const fresh = new ApiConfig();
    fresh.apiKey = old.apiKey;
    fresh.endpoint = old.endpoint;
    fresh.model = old.model;
    fresh.provider = inferProviderFromEndpoint(old.endpoint);
    fresh.audioModel = old.audioModel;
    fresh.audioVoice = old.audioVoice;
    fresh.audioEndpoint = old.audioEndpoint;
    fresh.audioKey = old.audioKey;
    return fresh;
  }) as ApiConfig;
}

// ============================================================
// ★ 0.161.3：内置 API Key 本地配置（rawfile/config.json）
// ============================================================
// 背景：此前 Key 硬编码在本文件（0.160.1 内置），源码无法安全上传 GitHub。
// 改造：Key 挪到 resources/rawfile/config.json（.gitignore 忽略，绝不入库），
//       源码默认值改空串；EntryAbility 启动时读本文件填充空位。
// 注意：config.json 会被打进 HAP——自己装机测试没问题，但上架/公开分发 HAP
//       前仍须移除（原「上架前删除」约束不变，仅位置从源码挪到 rawfile）。
// 兜底：文件缺失/解析异常（如 clone 后未放本地配置）静默跳过，用户走设置页自填。
export interface BuiltinConfig {
  apiKey: string;
  audioKey: string;
}

// ★ 0.161.3：从 rawfile/config.json 读取内置 Key，填充持久化配置的空位。
// 仅填空位——用户在设置页自定义过的 Key（持久化非空）优先，不被内置值覆盖。
export function loadBuiltinApiConfig(context: common.UIAbilityContext): void {
  try {
    const raw = context.resourceManager.getRawFileContentSync('config.json');
    const text = util.TextDecoder.create('utf-8').decodeToString(raw);
    const obj = JSON.parse(text) as BuiltinConfig;
    const cfg = connectApiConfig();
    if (cfg.apiKey.length === 0 && obj.apiKey.length > 0) {
      cfg.apiKey = obj.apiKey;
    }
    if (cfg.audioKey.length === 0 && obj.audioKey.length > 0) {
      cfg.audioKey = obj.audioKey;
    }
  } catch (err) {
    // config.json 不存在或解析失败——保持空默认，设置页自填
  }
}

// ============================================================
// ★ 0.191.0：对话书签（阅读位置方案 B 手动标记）——独立 key 持久化，跨重启稳定
// ============================================================
// 设计：单 JSON 字符串字段存全部气泡的书签（bubbleId → 划词 key+字符偏移），
// 避免 Record 字面量（ArkTS 严格模式）与往类上加字段的旧快照坑（0.143 教训）。
// ★ 0.191.0 重做：段落级→划词级——segKey=完整划词 key（`${msgId}|${segIdx}` 文本段 / `${msgId}|t${segIdx}h${ci}` 表格格），
// start/end=划选在该 Text 内容中的字符偏移（onTextSelectionChange 原值，substring 即得划选文字）。
// key 升 v2：旧 v1 段落级数据结构不兼容，作废（均为测试期数据）。
export interface BookmarkEntry {
  bubbleId: string;   // 所属气泡
  messageId: string;  // AI 消息 ID
  segKey: string;     // 完整划词 key（含段/格定位）
  start: number;      // 划选起始偏移（该 Text 内容内）
  end: number;        // 划选结束偏移
}

export interface BookmarkData {
  entries: BookmarkEntry[];
}

@ObservedV2
export class ChatBookmarkStore {
  @Trace raw: string = '{"entries":[]}';
}

export function connectChatBookmarks(): ChatBookmarkStore {
  return PersistenceV2.connect(ChatBookmarkStore, 'chat-bookmarks-v2', () => new ChatBookmarkStore()) as ChatBookmarkStore;
}

// ★ 0.150：AI 对话偏好（自定义称呼 + 自动鼓励）——PersistenceV2 持久化，跨重启保存
// 独立 key 与 ApiConfig 隔离（0.143 教训：往已有磁盘快照的类新增字段会因旧快照缺字段不落盘；
// 全新 key 首次创建即含全部字段，无此坑——与单词库/知识库独立 key 模式一致）
// ★ 0.191.0：鼓励开关（boolean）→ 三档 encourageMode（off/light/heavy，默认 light=原「开」语义）；
//   字段类型变化 key 升 v2（0.143 教训），旧 v1 的称呼需用户重填一次（鼓励档默认轻度无缝衔接）
@ObservedV2
export class AiPreference {
  @Trace aiNickname: string = '';               // 自定义称呼（空 = 不添加称呼文本；短/中/长全部回复模式都生效）
  @Trace encourageMode: string = 'light';       // 鼓励三档：off=关闭 / light=轻度（默认，1~2 句温和）/ heavy=重度（2~4 句狂热夸张）；仅中/长回复生成，短回复不生成
}

// ★ 0.191.0：连接 AI 偏好持久化实例（key v2——encourageMode 字段类型变化，见类注释）
export function connectAiPreference(): AiPreference {
  return PersistenceV2.connect(AiPreference, 'ai-preference-v2', () => new AiPreference()) as AiPreference;
}

// ============================================================
// ★ 0.192.0：学习统计（用户定稿）——按天聚合轻量库，PersistenceV2 持久化
// 设计：单 JSON 字符串字段存全部日记录（同书签/偏好模式，避 Record 字面量坑）；
//   只增不减——消息/气泡删除不影响已统计数据（累计口径，用户明确要求）。
// 埋点：sendMessage（用户消息+1）/ onDone（AI 回复+1 + token 累加）/
//   createChildBubble + 新建树/Tab（气泡+1）。
// ============================================================
export interface StatDayEntry {
  date: string;         // 日期键 'YYYY-MM-DD'（本地时区）
  userMsgs: number;     // 用户消息条数
  aiMsgs: number;       // AI 回复条数
  bubbles: number;      // 创建气泡数
  inputTokens: number;  // 输入 token 累计
  outputTokens: number; // 输出 token 累计
}

export interface StatDayData {
  days: StatDayEntry[];
}

@ObservedV2
export class StatisticsStore {
  @Trace raw: string = '{"days":[]}';
}

// ★ 0.192.0：连接统计持久化实例（全新 key，无历史迁移需求）
export function connectStatistics(): StatisticsStore {
  return PersistenceV2.connect(StatisticsStore, 'statistics-v1', () => new StatisticsStore()) as StatisticsStore;
}

// ★ 0.192.0：本地日期键 'YYYY-MM-DD'（统计按用户本地天聚合，不用 UTC 防跨天错位）
export function statDateKey(ts: number): string {
  const d = new Date(ts);
  const m = `${d.getMonth() + 1}`.padStart(2, '0');
  const day = `${d.getDate()}`.padStart(2, '0');
  return `${d.getFullYear()}-${m}-${day}`;
}

// ★ 0.192.0：读取全部日记录（解析失败返回空表）
export function getStatDays(store: StatisticsStore): StatDayEntry[] {
  try {
    const data = JSON.parse(store.raw) as StatDayData;
    if (data.days !== undefined && data.days !== null) {
      return data.days;
    }
  } catch (_e) {
    // 解析失败视为空表
  }
  return [];
}

// ★ 0.192.0：写统计（原子操作：读-改-写整表；天记录不存在则创建）
// userMsg/aiMsg/bubble 各自 +1；tokens 传增量（默认 0）
export function recordStat(store: StatisticsStore, kind: string, inTok: number, outTok: number): void {
  const days = getStatDays(store);
  const key = statDateKey(Date.now());
  let entry: StatDayEntry | undefined = undefined;
  for (let i = 0; i < days.length; i++) {
    if (days[i].date === key) {
      entry = days[i];
      break;
    }
  }
  if (entry === undefined) {
    entry = { date: key, userMsgs: 0, aiMsgs: 0, bubbles: 0, inputTokens: 0, outputTokens: 0 };
    days.push(entry);
  }
  if (kind === 'userMsg') {
    entry.userMsgs += 1;
  } else if (kind === 'aiMsg') {
    entry.aiMsgs += 1;
  } else if (kind === 'bubble') {
    entry.bubbles += 1;
  }
  entry.inputTokens += inTok;
  entry.outputTokens += outTok;
  store.raw = JSON.stringify({ days: days } as StatDayData);
}

// ★ 0.161：学习数量设置——控制 AI 回复气泡底部生词复习区与知识卡片提炼等待页复习区
// 每次展示的词条数；单词库顶栏 ⚙ 设置弹窗提供 1 / 2（默认）/ 自由输入（1~20）三选项；
// PersistenceV2 独立全新 key 跨重启保存（与 AiPreference 同模式，无旧快照缺字段坑）
@ObservedV2
export class LearnCountStore {
  @Trace learnCount: number = 2; // 每次学习的词条数量（默认 2；合法范围 1~20）
}

// ★ 0.161：连接学习数量持久化实例（全新 key，无历史迁移需求）
export function connectLearnCount(): LearnCountStore {
  return PersistenceV2.connect(LearnCountStore, 'learn-count-v1', () => new LearnCountStore()) as LearnCountStore;
}

// ★ 0.161.2：知识卡片数量设置——控制 AI 回复气泡底部知识卡复习区与知识卡片提炼等待页复习区
// 每次展示的卡片数；知识库顶栏 ⚙ 设置弹窗提供 1（默认）/ 2 / 3 / 自由输入（1~20）四选项；
// 与 LearnCountStore 同模式（PersistenceV2 独立全新 key，默认 1 保持 0.146 以来现状）
@ObservedV2
export class KnowledgeCountStore {
  @Trace knowledgeCount: number = 1; // 每次展示的知识卡片数量（默认 1；合法范围 1~20）
}

// ★ 0.161.2：连接知识卡片数量持久化实例（全新 key，无历史迁移需求）
export function connectKnowledgeCount(): KnowledgeCountStore {
  return PersistenceV2.connect(KnowledgeCountStore, 'knowledge-count-v1', () => new KnowledgeCountStore()) as KnowledgeCountStore;
}

// ★ 0.185.0：音标口音设置——划词查词生成的音标口音（美式默认/英式）。
// 单词库顶栏 ⚙ 设置弹窗提供 美式（默认）/ 英式 两选项，切换需确认（切换时清空现有音标）。
// 与 LearnCountStore 同模式：PersistenceV2 独立全新 key，无旧快照缺字段坑。
@ObservedV2
export class PhoneticAccentStore {
  @Trace british: boolean = false; // false=美式音标（默认），true=英式音标
}

// ★ 0.185.0：连接音标口音持久化实例（全新 key，无历史迁移需求）
export function connectPhoneticAccent(): PhoneticAccentStore {
  return PersistenceV2.connect(PhoneticAccentStore, 'phonetic-accent-v1', () => new PhoneticAccentStore()) as PhoneticAccentStore;
}

// ============================================================
// ★ 0.151：画布多树模式数据层（互通设计，0.151-bugfix2 用户实测纠正）
// ============================================================
//   - 平铺池 = PersistData.bubbleTreeJson（存平铺视图的全部树）
//   - Tab 池 = TabForestStore.tabsJson（存选项卡视图每个 Tab 的独立树）
//   - 'bubble-tree' 单例 = 当前视图工作区：切模式/切 Tab 只换工作区内容
// 两模式是同一批树数据的两种视图（互通）：
//   - flat→tabs：平铺的每棵树（每个根气泡）自动拆成一个 Tab，Tab 名 = 树根显示名
//   - tabs→flat：全部 Tab 的树合并平铺渲染（需求 2.4.2 字面语义）
//   - 当前模式的池是权威数据源，切换时全量重建另一池
//   - Tab 名与树根标题绑定：重命名 Tab = 改树根 nodeTitle，往返切换名字不丢
// ============================================================

// ★ 0.151：画布模式类型（'flat' 多根平铺 / 'tabs' 选项卡多树）
export type CanvasMode = 'flat' | 'tabs';

// ★ 0.151：画布模式持久化——跨重启保持；独立全新 key（0.143 教训：往已有磁盘
// 快照的类新增字段会因旧快照缺字段不落盘，全新 key 首次创建即含全部字段）
@ObservedV2
export class CanvasModeStore {
  @Trace mode: CanvasMode = 'flat'; // 默认平铺模式
}

// ★ 0.151：连接画布模式持久化实例（全新 key，无历史迁移需求）
export function connectCanvasMode(): CanvasModeStore {
  return PersistenceV2.connect(CanvasModeStore, 'canvas-mode-v1', () => new CanvasModeStore()) as CanvasModeStore;
}

// ★ 0.151：Tab 元数据——一个 Tab = 一棵完整独立的树
export interface TabMeta {
  id: string;       // Tab 唯一 ID
  name: string;     // Tab 显示名（可重命名，溢出省略号截断）
  treeJson: string; // 该 Tab 整棵树的序列化 JSON（与 PersistData.bubbleTreeJson 同格式）
}

// ★ 0.151：Tab 森林持久化——tabsJson 存 TabMeta[] 的 JSON 字符串（字符串持久化与
// bubbleTreeJson 同模式，避免嵌套 @ObservedV2 类持久化风险）；activeTabId 记当前选中 Tab
@ObservedV2
export class TabForestStore {
  @Trace tabsJson: string = '[]';  // TabMeta[] JSON
  @Trace activeTabId: string = ''; // 当前选中 Tab ID（空 = 无 Tab）
}

// ★ 0.151：连接 Tab 森林持久化实例（全新 key，无历史迁移需求）
export function connectTabForest(): TabForestStore {
  return PersistenceV2.connect(TabForestStore, 'tab-forest-v1', () => new TabForestStore()) as TabForestStore;
}

// ★ 0.151：Tab 列表解析（JSON 容错：坏数据返回空数组，不崩溃）
export function parseTabs(tabsJson: string): TabMeta[] {
  if (!tabsJson || tabsJson.length === 0) {
    return [];
  }
  try {
    const parsed = JSON.parse(tabsJson) as TabMeta[];
    return Array.isArray(parsed) ? parsed : [];
  } catch (e) {
    return [];
  }
}

// ★ 0.151：Tab 列表序列化
export function serializeTabs(tabs: TabMeta[]): string {
  return JSON.stringify(tabs);
}

// ★ 0.151-bugfix2：树根显示名（与 BBTreeCanvas.getDisplayName 同规则）——Tab 名与树根绑定：
// nodeTitle 非空取标题（15 字截断）；否则取第一条 user 消息前 15 字（超长加…）；否则「空气泡」
export function getRootDisplayName(root: BubbleNode): string {
  const title = root.nodeTitle.trim();
  if (title.length > 0) {
    return title.length > 15 ? title.substring(0, 15) : title;
  }
  const firstUser = root.messages.find((m: ChatMessage): boolean => m.role === 'user');
  if (firstUser !== undefined) {
    const raw = firstUser.content.trim();
    if (raw.length > 15) {
      return raw.substring(0, 15) + '…';
    }
    return raw;
  }
  return '空气泡';
}

// ★ 0.151-bugfix2：按根拆树——nodeList 按根 BFS 收集子树，每棵树生成一个 TabMeta
// （applyCanvasModeSwitch 的 flat→tabs 与旧版遗留迁移共用；excludeRootIds 传根 nodeID
// 集合可跳过同源树，迁移去重用）
function buildTabsFromNodeList(nodeList: BubbleNode[], excludeRootIds?: Set<string>): TabMeta[] {
  const childrenMap = new Map<string, BubbleNode[]>();
  for (const node of nodeList) {
    if (node.parentID !== null) {
      const siblings = childrenMap.get(node.parentID);
      if (siblings) {
        siblings.push(node);
      } else {
        childrenMap.set(node.parentID, [node]);
      }
    }
  }
  const roots = nodeList.filter((n: BubbleNode): boolean => n.parentID === null);
  const tabs: TabMeta[] = [];
  for (let r = 0; r < roots.length; r++) {
    const root = roots[r];
    if (excludeRootIds !== undefined && excludeRootIds.has(root.nodeID)) {
      continue; // 同源树（已存在于目标池），不重复并入
    }
    // BFS 收集该根的全部后代节点（子树完整迁移，parentID 原值保持）
    const subtree: BubbleNode[] = [root];
    let layer: BubbleNode[] = [root];
    while (layer.length > 0) {
      const next: BubbleNode[] = [];
      for (const node of layer) {
        const children = childrenMap.get(node.nodeID);
        if (children) {
          for (const child of children) {
            next.push(child);
          }
        }
      }
      for (const node of next) {
        subtree.push(node);
      }
      layer = next;
    }
    tabs.push({
      id: `tab_${Date.now()}_${r}_${Math.floor(Math.random() * 10000)}`, // 循环索引参与 id，同毫秒多 Tab 绝不撞号
      name: getRootDisplayName(root), // Tab 名 = 树根显示名（与画布气泡文字一致，用户一眼对上）
      treeJson: serializeBubbleTree(new BubbleTree(subtree))
    });
  }
  return tabs;
}

// ★ 0.167.3：子树占位法（tidy tree 简化版）——递归计算子树水平占位
// 叶子占位 = NODE_W；内部节点占位 = max(NODE_W, sum(子占位) + (n-1)*gap)
// 供 layoutFlatForest 按占位排开，数学保证任意两气泡间必有空隙。
// 旧版 BFS 按层估宽（气泡宽硬编码 132 已过时）+ 子节点均分居中 → 孙子辈均分宽度
// 超出父辈间距时必然与叔伯家子树交叉重叠（0.167 加宽气泡后恶化），整体弃用。
function subtreeWidth(root: BubbleNode, childrenMap: Map<string, BubbleNode[]>, gap: number,
  cache: Map<string, number>): number {
  const cached = cache.get(root.nodeID);
  if (cached !== undefined) return cached;
  const children = childrenMap.get(root.nodeID);
  let w = NODE_W;
  if (children && children.length > 0) {
    let sum = 0;
    for (const child of children) {
      sum += subtreeWidth(child, childrenMap, gap, cache);
    }
    w = Math.max(NODE_W, sum + (children.length - 1) * gap);
  }
  cache.set(root.nodeID, w);
  return w;
}

// ★ 0.151-bugfix3：多根平铺布局纯函数（从 BBTreeCanvas.autoLayout 提取，单一来源防两份漂移）
// 供两处调用：① BBTreeCanvas.autoLayout（画布重排：新建根 / 切 Tab /「显示全部」等）
//            ② applyCanvasModeSwitch tabs→flat（合并树【先排好再持久化】——修复 bug2：
//               各 Tab 树坐标独立，直接拼接必然重叠；旧版靠 needsRelayout 事后重排，
//               但它是 AppStorageV2 内存态，保存后不关弹窗直接杀应用 / ChatPage 弹窗
//               切模式后直接退出 → 重启后重叠坐标已落盘无人重排）
// ★ 0.167.3：算法整体换子树占位法（tidy tree 简化版）——
//   旧版「子节点在父正下方均分居中」+ horizontalSpacing=160 中心距 < 气泡宽 200，
//   相邻气泡天然重叠 40vp；孙子辈均分宽度超出父辈间距时必然与叔伯家子树交叉重叠。
//   新版：node.x = leftX + 子树占位/2（子树水平中轴），子节点从 leftX 起按各自占位
//   依次排开——数学保证任意两气泡间必有 siblingGap 空隙；单根也走同一算法全量防重叠
//   （fitViewport 负责居中，x 归零无影响）。
// ★ 0.167.4 用户拍板：多根从上往下堆叠（纵向排列）——新建根气泡排在已有树下方，
//   弃 0.151 旧版横向并排；与「全设备统一从上到下」视觉语言一致。
export function layoutFlatForest(nodeList: BubbleNode[]): void {
  const roots = nodeList.filter((n: BubbleNode) => n.parentID === null);
  if (roots.length === 0) return;

  const siblingGap = 40;       // ★ 0.167.3：同层相邻子树间隙（用户硬性要求：气泡间必须有空隙）
  const treeGap = 120;         // ★ 0.167.4：多根树间垂直间隙（纵向堆叠，从上往下排）
  const verticalSpacing = 113; // ★ 0.172.2：用户拍板「间距高度再减 1/3」——净空 113-68=45 ≈ 68×2/3（0.172.1 净空 68 的 2/3；原 160 净空 92）

  // 构建父→子映射
  const childrenMap = new Map<string, BubbleNode[]>();
  for (const node of nodeList) {
    if (node.parentID !== null) {
      const children = childrenMap.get(node.parentID) || [];
      children.push(node);
      childrenMap.set(node.parentID, children);
    }
  }

  // 占位缓存（O(n)：每节点 subtreeWidth 只算一次，防深树重复递归）
  const widthCache = new Map<string, number>();

  // 递归布局：先定自身（子树占位中轴），再按占位 cursor 依次排开子树
  // ★ 0.167.4：baseY 参数——多根纵向堆叠时每棵树从各自起始 y 往下长（树内仍 depth*verticalSpacing）
  const layoutSubtree = (node: BubbleNode, leftX: number, depth: number, baseY: number): void => {
    node.x = leftX + subtreeWidth(node, childrenMap, siblingGap, widthCache) / 2;
    node.y = baseY + depth * verticalSpacing;
    const children = childrenMap.get(node.nodeID);
    if (!children || children.length === 0) return;
    let cursor = leftX;
    for (const child of children) {
      layoutSubtree(child, cursor, depth + 1, baseY);
      cursor += subtreeWidth(child, childrenMap, siblingGap, widthCache) + siblingGap;
    }
  };

  // ★ 0.167.4：树垂直占位——最深层气泡下缘相对树顶的偏移（maxDepth*verticalSpacing + NODE_H）
  const treeHeight = (node: BubbleNode, depth: number): number => {
    const children = childrenMap.get(node.nodeID);
    if (!children || children.length === 0) return depth * verticalSpacing + NODE_H;
    let maxH = 0;
    for (const child of children) {
      maxH = Math.max(maxH, treeHeight(child, depth + 1));
    }
    return maxH;
  };

  // ★ 0.167.4 用户拍板：多根从上往下堆叠（纵向排列）——新建根气泡排在已有树下方，
  //   非 0.151 旧版的横向并排；与「全设备统一从上到下树形结构」视觉语言一致，
  //   手机竖屏下纵向堆叠更省横向空间不易超宽。
  // ★ 0.167.5 用户拍板：根气泡 x 恒 0——所有树的根永远在同一条竖线上对齐（旧版根在
  //   各自子树占位中心，树宽不同根就歪歪扭扭不美观）；子树以根为中轴左右对称展开。
  let cursorY = 0;
  for (const root of roots) {
    const w = subtreeWidth(root, childrenMap, siblingGap, widthCache);
    root.x = 0;
    root.y = cursorY;
    const children = childrenMap.get(root.nodeID);
    if (children && children.length > 0) {
      let cursor = -w / 2; // 子树占位从根中轴左侧起排，整体居中于根正下方
      for (const child of children) {
        layoutSubtree(child, cursor, 1, cursorY);
        cursor += subtreeWidth(child, childrenMap, siblingGap, widthCache) + siblingGap;
      }
    }
    cursorY += treeHeight(root, 0) + treeGap;
  }

  // 更新所有子节点的 parentX/parentY
  for (const node of nodeList) {
    if (node.parentID !== null) {
      const parent = nodeList.find((n: BubbleNode) => n.nodeID === node.parentID);
      if (parent) {
        node.parentX = parent.x;
        node.parentY = parent.y;
      }
    }
  }
}

// ★ 0.151-bugfix2：模式切换核心——同一批树数据的两种视图互转（互通语义，用户实测纠正）
// 调用时机：全局设置弹窗「保存」按钮（用户确认切换后执行一次）
//   flat→tabs：平铺工作区按根拆树，每棵树自动变成一个 Tab（Tab 名 = 树根显示名），
//              全量重建 Tab 池；activeTab = 第一个 Tab；工作区加载第一棵树
//   tabs→flat：当前工作区先存回 activeTab；全部 Tab 的树合并成多根 BubbleTree，
//              全量重建平铺池；工作区加载合并树（needsRelayout 触发多根并排布局）
// 同时清空 currentBubble（旧选中节点在新工作区必然失效，防 ChatPage 数据错乱）+ 置 needsRelayout
export function applyCanvasModeSwitch(newMode: CanvasMode): void {
  const persist = PersistenceV2.connect(PersistData, 'persist-data', () => new PersistData()) as PersistData;
  const store = AppStorageV2.connect(BubbleTree, 'bubble-tree', () => new BubbleTree()) as BubbleTree;
  const forest = connectTabForest();
  const current = AppStorageV2.connect(CurrentBubble, 'current-bubble', () => new CurrentBubble()) as CurrentBubble;

  if (newMode === 'tabs') {
    // 平铺 → 选项卡：工作区（全部树）存回平铺池
    persist.bubbleTreeJson = serializeBubbleTree(store);
    upsertCloudData('flat_pool', persist.bubbleTreeJson); // ★ 0.165.1：云同步桥接（切换前平铺池先上云）
    // 按根拆树：每个根的子树 = 一个 Tab（互通：树还是那批树，只是换个组织方式）
    const tabs = buildTabsFromNodeList(store.nodeList);
    forest.tabsJson = serializeTabs(tabs);
    upsertCloudData('tabs_pool', forest.tabsJson); // ★ 0.165.1：云同步桥接（重建的 Tab 池上云）
    // 选中第一个 Tab，工作区加载第一棵树（无树 = 空工作区，等用户点 ➕ 创建）
    forest.activeTabId = tabs.length > 0 ? tabs[0].id : '';
    const first = tabs.length > 0 ? deserializeBubbleTree(tabs[0].treeJson) : null;
    store.nodeList = first ? first.nodeList : [];
  } else {
    // 选项卡 → 平铺：当前工作区先存回 activeTab（若有未落盘修改）
    const tabs = parseTabs(forest.tabsJson);
    const idx = tabs.findIndex((t: TabMeta): boolean => t.id === forest.activeTabId);
    if (idx >= 0) {
      tabs[idx].treeJson = serializeBubbleTree(store);
      forest.tabsJson = serializeTabs(tabs);
      upsertCloudData('tabs_pool', forest.tabsJson); // ★ 0.165.1：云同步桥接（当前 Tab 存回后 Tab 池上云）
    }
    // 合并全部 Tab 的树 → 多根平铺（互通：需求 2.4.2「统一平铺渲染」字面语义；
    // nodeID 为时间戳+随机全局唯一，各 Tab 树直接拼接无冲突）
    const merged: BubbleNode[] = [];
    for (const tab of tabs) {
      const loaded = deserializeBubbleTree(tab.treeJson);
      if (loaded) {
        for (const node of loaded.nodeList) {
          merged.push(node);
        }
      }
    }
    // ★ 0.151-bugfix3：合并树【先排好再持久化】——各 Tab 树坐标独立（各自布局过），
    // 直接拼接必然重叠（用户实测 bug2）；旧版靠 needsRelayout 事后重排，但它是
    // AppStorageV2 内存态，保存后不关弹窗直接杀应用 / ChatPage 弹窗切模式后直接退出
    // → 重启后重叠坐标已落盘无人重排。数据层直接排好，任何路径拿到的都是正确坐标
    layoutFlatForest(merged);
    // 全量重建平铺池 + 工作区加载合并树
    persist.bubbleTreeJson = serializeBubbleTree(new BubbleTree(merged));
    upsertCloudData('flat_pool', persist.bubbleTreeJson); // ★ 0.165.1：云同步桥接（重建的平铺池上云）
    store.nodeList = merged;
  }
  // 清空当前选中（旧选中节点在新工作区必然失效，防 ChatPage 数据错乱）
  current.nodeID = '';
  current.bubbleX = 0;
  current.bubbleY = 0;
  // 触发画布重布局（BBTreeCanvas onShown / 弹窗 onClose 消费）
  store.needsRelayout = true;
}

// ★ 0.151-bugfix2：互通迁移完成标记——PersistenceV2 独立全新 key（0.143 教训：往已有
// 磁盘快照的类新增字段会因旧快照缺字段不落盘，全新 key 首次创建即含全部字段）
@ObservedV2
export class CanvasInteropFlag {
  @Trace migrated: boolean = false; // 旧版两池隔离遗留数据的一次性迁移完成标记
}

// ★ 0.151-bugfix2：连接互通迁移标记持久化实例
export function connectCanvasInteropFlag(): CanvasInteropFlag {
  return PersistenceV2.connect(CanvasInteropFlag, 'canvas-interop-v1', () => new CanvasInteropFlag()) as CanvasInteropFlag;
}

// ★ 0.151-bugfix2：旧版两池隔离 → 互通版的一次性数据迁移（应用冷启动执行一次）
// 背景：0.151 初版把两模式解释为「两池隔离、互不混入」，Tab 池与平铺池各自独立积累了
// 数据（用户实测：平铺 3 棵树 + Tab 池 1 个手动建的 Tab，两批不同源）。互通版切换会
// 全量重建目标池，若不迁移、用户首次切换即丢非权威池的独立数据。
// 迁移规则：把非权威池的树并入权威池（按根 nodeID 去重——同源树不重复并入）：
//   - 当前 tabs 模式：权威 = Tab 池，平铺池的树拆成 Tab 并入
//   - 当前 flat 模式：权威 = 平铺池，Tab 池的树合并进平铺池
// 幂等双保险：migrated 标记保证仅执行一次；根 nodeID 去重保证重复执行也无害
export function migrateLegacyPoolsIfNeeded(canvasMode: CanvasMode): void {
  const flag = connectCanvasInteropFlag();
  if (flag.migrated) {
    return;
  }
  const persist = PersistenceV2.connect(PersistData, 'persist-data', () => new PersistData()) as PersistData;
  const forest = connectTabForest();
  const flatTree = deserializeBubbleTree(persist.bubbleTreeJson);
  const tabs = parseTabs(forest.tabsJson);

  if (canvasMode === 'tabs') {
    // 权威 = Tab 池：收集各 Tab 树的根 nodeID（去重键），平铺池的树拆成 Tab 并入
    if (flatTree !== null && flatTree.nodeList.length > 0) {
      const tabRootIds = new Set<string>();
      for (const tab of tabs) {
        const loadedTab = deserializeBubbleTree(tab.treeJson);
        if (loadedTab !== null) {
          const tabRoot = loadedTab.nodeList.find((n: BubbleNode): boolean => n.parentID === null);
          if (tabRoot !== undefined) {
            tabRootIds.add(tabRoot.nodeID);
          }
        }
      }
      const appended = buildTabsFromNodeList(flatTree.nodeList, tabRootIds);
      if (appended.length > 0) {
        for (const tab of appended) {
          tabs.push(tab);
        }
        forest.tabsJson = serializeTabs(tabs);
        upsertCloudData('tabs_pool', forest.tabsJson); // ★ 0.165.1：云同步桥接（迁移后 Tab 池上云）
      }
    }
  } else {
    // 权威 = 平铺池：Tab 池的树整棵并入平铺池（根 nodeID 去重）
    if (tabs.length > 0) {
      const flatIds = new Set<string>();
      const merged: BubbleNode[] = [];
      if (flatTree !== null) {
        for (const node of flatTree.nodeList) {
          flatIds.add(node.nodeID);
          merged.push(node);
        }
      }
      let appended = 0;
      for (const tab of tabs) {
        const loadedTab = deserializeBubbleTree(tab.treeJson);
        if (loadedTab === null) {
          continue;
        }
        const tabRoot = loadedTab.nodeList.find((n: BubbleNode): boolean => n.parentID === null);
        if (tabRoot === undefined || flatIds.has(tabRoot.nodeID)) {
          continue; // 空树或同源树，不并入
        }
        for (const node of loadedTab.nodeList) {
          merged.push(node);
        }
        appended++;
      }
      if (appended > 0) {
        persist.bubbleTreeJson = serializeBubbleTree(new BubbleTree(merged));
        upsertCloudData('flat_pool', persist.bubbleTreeJson); // ★ 0.165.1：云同步桥接（迁移后平铺池上云）
      }
    }
  }
  flag.migrated = true;
}

// ============================================================
// ★ 0.165.2：云端下行刷新（dataChange 事件 → 写回池 → 重建工作区）
// ============================================================
// 链路：CloudSyncUtil 订阅 SUBSCRIBE_TYPE_CLOUD → 云端数据下行到本地 RDB →
//   pullAndNotify 拉快照 → 此处 handler 写回 PersistenceV2 池 → 重建工作区
// 设计约束：
//   - 【绝不 upsert】下行写池后不能再调 upsertCloudData——否则 A 写→云→B 下行→
//     B 再 upsert→云→A 下行……无限回环。PersistenceV2 赋值自动落盘，无需手动上云
//   - 【值比较挡回声】本机 upsert 上云的回声事件：RDB 值 == 池值 → 不写回，天然幂等
//   - 【竞态窗口】本机池已更新但 upsert 尚未落 RDB 的毫秒级窗口内恰逢下行，可能用
//     旧值覆盖新编辑（last-write-wins 语义，快照行模式固有，概率极低，MVP 接受）
//   - 【打断风险】下行重建工作区会打断进行中的流式回复/输入（nodeList 整体替换）——
//     触发条件是另一台设备刚改过数据，属用户预期内的多端一致，MVP 接受
// ============================================================
export function setupCloudDownlink(): void {
  registerCloudDataHandler((key: string, value: string): void => {
    if (key === 'flat_pool') {
      const persist = PersistenceV2.connect(PersistData, 'persist-data',
        () => new PersistData()) as PersistData;
      if (persist.bubbleTreeJson !== value) {
        persist.bubbleTreeJson = value; // PersistenceV2 自动落盘（绝不 upsert，防回环）
        refreshWorkspaceFromPools();
      }
    } else if (key === 'tabs_pool') {
      const forest = connectTabForest();
      if (forest.tabsJson !== value) {
        forest.tabsJson = value;
        refreshWorkspaceFromPools();
      }
    }
  });
}

// ★ 0.165.2：按当前模式的权威池重建工作区（复用 0.151 applyCanvasModeSwitch 的搬移模式）——
// flat：工作区 = 平铺池全部树；tabs：工作区 = activeTab 的树。
// 清空 current（旧选中节点在新工作区可能失效）+ 置 needsRelayout（BBTreeCanvas 消费触发重布局）
function refreshWorkspaceFromPools(): void {
  const store = AppStorageV2.connect(BubbleTree, 'bubble-tree', () => new BubbleTree()) as BubbleTree;
  const current = AppStorageV2.connect(CurrentBubble, 'current-bubble',
    () => new CurrentBubble()) as CurrentBubble;
  const modeStore = connectCanvasMode();
  if (modeStore.mode === 'flat') {
    const persist = PersistenceV2.connect(PersistData, 'persist-data',
      () => new PersistData()) as PersistData;
    const tree = deserializeBubbleTree(persist.bubbleTreeJson);
    store.nodeList = tree !== null ? tree.nodeList : [];
  } else {
    const forest = connectTabForest();
    const tabs = parseTabs(forest.tabsJson);
    const active = tabs.find((t: TabMeta): boolean => t.id === forest.activeTabId);
    const tree = active !== undefined ? deserializeBubbleTree(active.treeJson) : null;
    store.nodeList = tree !== null ? tree.nodeList : [];
  }
  current.nodeID = '';
  current.bubbleX = 0;
  current.bubbleY = 0;
  store.needsRelayout = true;
}
