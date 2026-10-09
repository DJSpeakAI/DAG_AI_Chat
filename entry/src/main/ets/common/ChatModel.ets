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
 import { cryptoFramework } from '@kit.CryptoArchitectureKit'; // ★ 0.194.0：兑换码 SHA256 离线校验
 import { connectHuaweiAccount } from '../utils/HuaweiAccountUtil'; // ★ 0.194.0：stampFreeTrialOnLogin 统一试用打点（无循环依赖：HuaweiAccountUtil 不引 ChatModel）
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
  @Trace draftText: string = ''; // ★ 0.214.2：输入框草稿（按气泡记忆——退出再回来继续编；Schema 铁律尾部追加）
  @Trace draftImages: string = ''; // ★ 0.214.2：待发图草稿（JSON string[]；随树持久化）

  constructor(nodeID: string, parentID: string | null, messages: ChatMessage[], x: number, y: number, parentX: number = 0, parentY: number = 0,
              historySummary: string = '', historySummaryCount: number = 0, nodeTitle: string = '',
              draftText: string = '', draftImages: string = '') {
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
    this.draftText = draftText;
    this.draftImages = draftImages;
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
  draftText?: string; // ★ 0.214.2（可选，旧数据无此字段兜底空串）
  draftImages?: string; // ★ 0.214.2（可选，同上）
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
        nodeTitle: node.nodeTitle, // ★ 0.147
        draftText: node.draftText, // ★ 0.214.2：草稿随树序列化
        draftImages: node.draftImages
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
        node.historySummary ?? '', node.historySummaryCount ?? 0, node.nodeTitle ?? '', // ★ 0.147：旧数据无此字段自动补空串
        node.draftText ?? '', node.draftImages ?? ''); // ★ 0.214.2：旧数据无草稿字段自动补空串
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
  siyi?: number;        // ★ 0.202.3：司忆量（单词/知识卡被司忆区展示的次数；可选兼容旧数据——读取处 ?? 0）
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
    entry = { date: key, userMsgs: 0, aiMsgs: 0, bubbles: 0, inputTokens: 0, outputTokens: 0, siyi: 0 };
    days.push(entry);
  }
  if (kind === 'userMsg') {
    entry.userMsgs += 1;
  } else if (kind === 'aiMsg') {
    entry.aiMsgs += 1;
  } else if (kind === 'bubble') {
    entry.bubbles += 1;
  } else if (kind === 'siyi') {
    // ★ 0.202.3：司忆量埋点（inTok 复用为批量次数，默认 1）；提前 return——不落入 token 累加
    entry.siyi = (entry.siyi ?? 0) + Math.max(1, Math.round(inTok));
    store.raw = JSON.stringify({ days: days } as StatDayData);
    return;
  }
  entry.inputTokens += inTok;
  entry.outputTokens += outTok;
  store.raw = JSON.stringify({ days: days } as StatDayData);
}

// ============================================================
// ★ 0.194.0：订阅体系（用户定稿：¥9.9/月 + ¥99/年；到期只锁云同步其他 100% 可用；
//   新用户登录华为账号免费试用 30 天；种子用户兑换码 +90 天）
// 存储：PersistenceV2 独立 key（0.143 教训：全新 key 无旧快照坑）
// IAP：华为应用内支付（商品 ID/公钥待用户拿到商户资格后填入，当前占位）
// ============================================================
@ObservedV2
export class SubscriptionStore {
  @Trace freeTrialStart: number = 0;      // 免费试用开始时间戳（首次登录华为账号记录；0=从未登录）
  @Trace subscriptionExpire: number = 0;  // 权益到期时间戳（订阅购买/兑换码写入；0=无权益）
  @Trace redeemedCodes: string = '[]';    // 已兑换码 JSON 数组（防同码重复兑换）
  @Trace purchaseHistory: string = '[]';  // 本地购买/兑换记录 JSON 数组（账单页展示）
  @Trace reminderState: string = '{}';    // ★ 0.195.0：到期提醒状态 JSON {welcome,last}（旧快照缺字段→parse 兜底）
}

// ★ 0.194.0：连接订阅持久化实例
export function connectSubscription(): SubscriptionStore {
  return PersistenceV2.connect(SubscriptionStore, 'subscription-v1', () => new SubscriptionStore()) as SubscriptionStore;
}

// ★ 0.194.0：统一试用打点——已登录且从未记录 → 从当下起算 30 天免费试用
//   （调用方：Index.doLogin 登录回调 / Index.aboutToAppear 老用户补查 / BillingPage 登录按钮，三处共用防逻辑漂移）
export function stampFreeTrialOnLogin(subscription: SubscriptionStore): boolean {
  const account = connectHuaweiAccount();
  if (account.isLoggedIn && subscription.freeTrialStart === 0) {
    subscription.freeTrialStart = Date.now();
    return true; // ★ 0.195.0：首次打戳返回 true——调用方据此弹「30 天试用欢迎弹窗」（仅首登 1 次）
  }
  return false;
}

// ★ 0.194.0：VIP 判断——免费期内 或 权益期内（到期只锁云同步，其他功能全开放）
export function isVip(store: SubscriptionStore): boolean {
  const now = Date.now();
  if (store.freeTrialStart > 0 && now < store.freeTrialStart + 30 * 86400000) {
    return true; // 免费试用 30 天内
  }
  if (store.subscriptionExpire > 0 && now < store.subscriptionExpire) {
    return true; // 订阅/兑换码权益期内
  }
  return false;
}

// ★ 0.194.0：权益到期时间（显示用；0=无任何权益）
export function vipExpireTime(store: SubscriptionStore): number {
  const now = Date.now();
  const trialEnd = store.freeTrialStart > 0 ? store.freeTrialStart + 30 * 86400000 : 0;
  if (trialEnd > now && trialEnd > store.subscriptionExpire) {
    return trialEnd; // 免费期更晚
  }
  return store.subscriptionExpire;
}

// ★ 0.194.0：剩余天数（向上取整；0=已到期/无权益）
export function vipDaysLeft(store: SubscriptionStore): number {
  const expire = vipExpireTime(store);
  if (expire <= Date.now()) {
    return 0;
  }
  return Math.ceil((expire - Date.now()) / 86400000);
}

// ============================================================
// ★ 0.195.0：到期提醒引擎（付费转化·用户定稿）
//   首登欢迎弹 1 次 + 最后 7 天（7/6/5/4/3/2/1）每日首开弹 1 次 + 过期后不再打扰
//   状态存 reminderState 单 JSON 字符串字段（0.143 教训：往类加字段旧快照坑——parse 全兜底）
// ============================================================
class ReminderState {
  welcome: boolean = false; // 欢迎弹窗已弹过（仅首登 1 次）
  last: string = '';        // 最近一次倒计时提醒日期 'YYYY-MM-DD'（每日去重）
}

function parseReminderState(store: SubscriptionStore): ReminderState {
  try {
    const s = JSON.parse(store.reminderState) as ReminderState;
    const st = new ReminderState();
    st.welcome = s.welcome === true;
    st.last = typeof s.last === 'string' ? s.last : '';
    return st;
  } catch (_e) {
    return new ReminderState();
  }
}

function todayStr(): string {
  const d = new Date();
  return `${d.getFullYear()}-${`${d.getMonth() + 1}`.padStart(2, '0')}-${`${d.getDate()}`.padStart(2, '0')}`;
}

// 今日应弹的倒计时提醒：0=不弹；1~7=剩余 N 天（每天最多 1 次；过期/无权益恒 0）
export function checkDailyReminder(store: SubscriptionStore): number {
  if (!isVip(store)) {
    return 0; // 已过期/无权益：不打扰（用户定稿）
  }
  if (parseReminderState(store).last === todayStr()) {
    return 0; // 今天已弹过——每日去重
  }
  const daysLeft = vipDaysLeft(store);
  if (daysLeft >= 1 && daysLeft <= 7) {
    return daysLeft; // 最后 7 天：7/6/5/4/3/2/1 每日一弹
  }
  return 0;
}

// 倒计时弹窗已弹（弹出即记账，不依赖按钮点击）
export function markReminderShownToday(store: SubscriptionStore): void {
  const st = parseReminderState(store);
  st.last = todayStr();
  store.reminderState = JSON.stringify(st);
}

// 欢迎弹窗已弹（仅首登 1 次）
export function markWelcomeShown(store: SubscriptionStore): void {
  const st = parseReminderState(store);
  st.welcome = true;
  store.reminderState = JSON.stringify(st);
}

// ★ 0.194.0：兑换码——写入 90 天权益（叠加到当前权益之后：连续兑换顺延）
export function redeemCode(store: SubscriptionStore, code: string): boolean {
  if (!isValidRedeemCode(code)) {
    return false;
  }
  // 防同码重复兑换
  let used: string[] = [];
  try {
    used = JSON.parse(store.redeemedCodes) as string[];
  } catch (_e) {
    used = [];
  }
  if (used.indexOf(code) >= 0) {
    return false;
  }
  used.push(code);
  store.redeemedCodes = JSON.stringify(used);
  // 权益叠加：从当前到期日、试用期末、现在三者中较晚者 +90 天
  // （★ 0.194.0-bugfix：试用期与兑换码顺延而非并行——登录当天兑码应得 30+90=120 天，原实现吞掉试用期）
  const trialEnd = store.freeTrialStart > 0 ? store.freeTrialStart + 30 * 86400000 : 0;
  const base = Math.max(store.subscriptionExpire, trialEnd, Date.now());
  store.subscriptionExpire = base + 90 * 86400000;
  // 记账
  let history: string[] = [];
  try {
    history = JSON.parse(store.purchaseHistory) as string[];
  } catch (_e) {
    history = [];
  }
  history.push(`兑换码 ${code.substring(0, 4)}****｜+90 天｜${new Date().toLocaleDateString()}`);
  store.purchaseHistory = JSON.stringify(history);
  return true;
}

// ★ 0.194.0：兑换码合法性校验——SHA256 哈希白名单（REDEEM_CODE_HASHES 内置 200 个种子码哈希；
//   单向哈希不可反推，离线验证无需服务器）
export function isValidRedeemCode(code: string): boolean {
  const normalized = code.trim().toUpperCase();
  if (normalized.length === 0) {
    return false;
  }
  const hash = sha256Hex(normalized);
  for (let i = 0; i < REDEEM_CODE_HASHES.length; i++) {
    if (REDEEM_CODE_HASHES[i] === hash) {
      return true;
    }
  }
  return false;
}

// ★ 0.194.0：SHA256 摘要（hex 小写）——cryptoFramework + util.TextEncoder
//   （ArkTS 无全局 TextEncoder，用 @kit.ArkTS 的 util.TextEncoder；encodeInto 直接返回 Uint8Array）

export function sha256Hex(text: string): string {
  try {
    const md = cryptoFramework.createMd('SHA256');
    md.updateSync({ data: new util.TextEncoder().encodeInto(text) });
    const result = md.digestSync();
    let hex = '';
    for (let i = 0; i < result.data.length; i++) {
      hex += result.data[i].toString(16).padStart(2, '0');
    }
    return hex;
  } catch (_e) {
    return '';
  }
}

// ★ 0.194.0：种子用户兑换码哈希白名单（200 个；码清单在用户手里，此处只存单向哈希）
// 生成方式：scripts/gen-redeem-codes.ps1 批量生成 DAGAI-XXXXX-XXXXX 随机码 + SHA256
export const REDEEM_CODE_HASHES: string[] = [
    '633326e06016dd8e3cca0e0523951d68ced702a2cad59136252dd12b8009b51a',
    '197fef7b49e147c58fd5a688f43ae290fec559672202c08e4606423746b672a7',
    '57d30eaa9f27c61babbafebf19efd30665fd6386a4fbbea30741fc815c5efae8',
    'bf2a4a0989633b9bded8138694014da7a0062195b2c7702d172947894f678d46',
    'b1567e1e01e4b0ed96f9e22200f843826ca518aa9d21f83bf2cf957a434d2587',
    '5f33ab3f3a9a0ae2865fb8bf9d531203a40316ebde993060561feb1d5dc1a8a8',
    'be75dcd71310b49114491d3ce9dee319cd9f42c349719507d9558758031c875c',
    'cd9ee31465fe7501ef83804c0bd9aff0961690bd2ada5e9c183183dbf6a77152',
    '304baec78757b059f1b6862581510c9370dc960d11b04c843b070c092c07aae1',
    'be55f2448e5bb0c597c511c46155ceb3f2fe66cf73e98848ec88944b65899a30',
    '5c5faccb314be4c9e6ca7bfee383aa13be47a64753e8726aa38daabeba1a22af',
    '2c931a530762b73dd2879e0cec8c11796fc817cc9d13c0b5c106d97ae1d1d8cf',
    '3fe7abd1fc91e6562cf677e4147ce69ea2ca1cbbd4e4140e01c2b4093b9f63b1',
    '9ae4de2f7eaf4020f8c64a84966371dd2570314bf44160214843db4d08ee7d80',
    'bb0fb559e25059eb5733e75e5736895712d5a278ff3fd09ff1bfa15f1c150ae8',
    '4fe3f65eb6efc2920ee390f44158b1467e6cbe149a9c77c932f452b2dc9a33fa',
    'dca5daa5d134775752664f9e513ee3cc52bb12231aadb25c90a9989eb0e0529f',
    'bdee2e43d87d87af85f1ae4b904a9a7dc15dae4f460b7ab0cece38ec4dc90318',
    'adb154169ca3d3c8a9cd08affed91a448b03e29f2ea74479eb382b70976a73b7',
    '7c75aa70600a51608928d3745f8f1b217e49cfcce247173ac473ef5481632d7c',
    '66497576c8e9e99201e3e949a91716db67e05cb5435547a9959ddfc9a1a38a70',
    '3a77c636149d6ec61122cb526aaa9268e9ff23ab98b687e4667b6720864dbb15',
    '5465a958c32d885f6270b3497205e96af57998f59b2d778736487601d70e5e07',
    '7aa3df6901111fe6b735d17094ace60a41279837b7fd948fd9c7138221d3ea52',
    'ab51c7d1113f709ed33e5eda12770f2ac292d9e6c6022445bd6525d5de35024b',
    '12e5a727ea83c57d0d06deaa0580e1ad7452134def60a3b0176f6555dd107bc4',
    '0c40b2d196531fd898f7d6d31e70cc89c9a32cf91895ab5d91290dda66295ed4',
    '152456fab6927e3deb6488428779c42b8d274588581a63083a8ee977e52327f5',
    '136042ed6b9842449407bfa3169f983963845a9558a665ec198245f166fa35a4',
    'd315ee4f03a2d7d0b19a493f15c717eba01f5999a423042c5b6d92070a3ea233',
    '5cfe8cc565a2ec0b59e784e1645e1fabce4f345dfef1d204668eb0860586dfa0',
    '673d67767ac9d8e93f9c6234a52b8a92a682fb4db18a8ba49ddf19b6250c609f',
    '0cb3a9c9e33647d33964a9c9183b38874d635e6fea097c83b4915f66a6d1ddc3',
    '1fb2cf0d905b21e56de2464648f2da1a787fab183a2a450ef9b974481a47a974',
    '74e10a6c8296840ffb3fc50387437eeb67a07a26bc780fdce33075ace2b1c260',
    '7701b86b8b5ffc08e4ca3fbb3a3ecd6fbbefb301cca98c7b552ea0e600371c52',
    'be2172cf2cec388526fb251841aaa97c70e0b861e66e9fc156f97258ec403ac1',
    'b39649ab6e3437878c16527ee8e78e60fcc1e987ec8af8f5ba849ef6041134ed',
    '6186685c80383738cd9df3679371a234bd44dd2de7572b5dc344bd710b163478',
    'b496e703ae4f3b294b64713cda4b88029597c249a2517cdb1f1cc250fc3e8b02',
    '03b561e694e923b8930a13dc8d2c56ab0e0fd38027b8e0f2d474cc7fd31f6537',
    'a2623d3fa2dc85ca8af33ca36c2cfb4841c60261d4789a3732a5b82cde175b6a',
    'bd85789aa88b3ae807aedb6d639b32c8aced0e6ac97bedb4e9d59766c4e994c1',
    'a66d18ef73133502d51b0fc88ab71e84b3779dd34ba56f4098b424bd645b6d77',
    '8b771869151a94b619a17b31bcfde3bae8ba3eab5943392ee733ac0087eebc0a',
    '3ce46628fdf2c007661576c75cc541b7a1506ce0b3163e7b0797a750fec74a82',
    '76d7acbf9d3cc8404979e15e0590c5e56da905070b3a3c3add24845adcfa57a4',
    'ab803c96b373a4a63cf09a596cddc8391f6b0bc6c4d9f186c985572e0dc5a34c',
    '19da12cae5ef5f96bc5373d1fa584d0f83901042d6abb399c3a6b151a9c2fb9d',
    '4009ae0aebfc2da854c51d23cca1c827f7a675d3c96bcf188e120d2b45c85d7b',
    'ff0dc9f32da906f71ecacf2390c35aee571dcba144592750f791bb287cdf5947',
    '62925dfab44b754fb9a4c37bfe5cf44fadf16d817250e27f6bc200af6dd7457c',
    'b0bfbe29be0cddcc4941fd6e28f2242ededff56cf719fc3cdab7d2377ff37428',
    '775659447879667396229505dec01d51bfcd59d84c90aac94c36d0f20d8168fe',
    '4bea128df4af0ec3a6eeca072f1a4eca7bd1ff6f34d8d52c5642726c1e90c260',
    '0d787d9059e5f19bef26559b9c5fcb21b75fc0c520ddca01f127f1b47d765718',
    '1caec460ca1e0c574c8c2194023d38faf4e3f2e7cb55d0c7465b53caf011269d',
    'a32c9595bc11ca525f81871f8e62f35f90f8d964c734561bd5036bb8ccdb4d81',
    'bef87febbc32256e1c3295eaa352e37bd45fdc35d128af3031ce6d8afae9d8e0',
    '0480542c88a03b0f9a18df3489104eabf25516ae8ebab2b422df056bc115a220',
    '836d16bfe55dad59e45272af9906d4a84ba88b7a84d9828149759eac2448b3a9',
    '12a51da5d9cbfc3365b670980263f7708563c19a33a3024a59faccf2a70c878a',
    '697854f34d0c61c5d733abca8323cae9e163c665934a793a7aedb3dd4d5a8110',
    'c20a7a3a74b28135962ca20584622a88c1929edb752ccf0d4bb4a1a30bddb5a0',
    '0481743d185eb1f9258db655347d7fa48938c03e6936bfb38d66c28118b03462',
    'eab436539b82f0650a96e7589e66fb968a68cd28768b7cd7bd9ea82b3d238eb1',
    '8a7dcb41e487d5d6918c83cdfe0c64df1a0fdf5e33e8ca648be9336996e9e41e',
    '61ed9e726b6c10848ea90a7ccd05fef8e20b31815dfd1e6dec095eb47cdc8a55',
    '5753e5524b4bc4390cd98f33bc298ed52b9c1aaac9443094822ce1611061d0e2',
    'e6b28d06f45fd391ed89fd3c2a3ecf6f97aee3aecd4dddbb1e4b4903985222fc',
    'f502c9091d893a1b5b6977c5d8e672ab06a20201251c094af2231987521358c8',
    '5598e6f0626a30e8034d4c0d5b88ec11fe5b62755d26929bc65e571096099e3f',
    'f410a2424da2310f1cfe24777389a2d07b1416ae63924fea187c1df8ddcb8274',
    '85955580f5ab557703a8a19709bae1c199bfd07e5e96b8aa8addd65b49139f84',
    '69c97756db93385ee53d69ddcabdd2ef1c48a855d35f4d9ee5210852c05bfc9b',
    '55719f8be578935b3d5d666e4e3e66bbb79ebe4bf914df4ba823e9b9c6cf1659',
    'e59bf1958b48dd4db5bebee9744b8a7b1b716c9b384c0c2ab7476658be2d3868',
    'b8d5ff5f79cd23f62ad36ca53311299831c239732c54eaf6374184a1692bd1fe',
    '740ab6191c38342a456f755c7540d124e69493853e25b0fa203cabcbbd6a28b3',
    '6033067e72b6ca7228c53b06de7374a9dc97a224ade94d40b12330bd7d33561d',
    '70f36500b39cba36fdf5294ff1e45c1c7ea46bd61bfc8dacac6d5ddb93267120',
    'd345986cf81aae0b1c3477ca230eaa47120edac164d51944c36cf0d6808c526d',
    'bf491f8cc8401b24a63c69e9d66ff7750578e45cac6f7c4d7fbb54718f6830ca',
    '7ae1a8b224e9b697a5a0d38521ed26dc446faed2b61eec60b1af4981749b4a6a',
    'c88ffda3036d4aef5329a9256b8a3b937d718dc79679eb50779d153248d51a99',
    'd757580740fe53745e1ac900250155d4110765b7bfb29e8d8b61862bb269c9a3',
    '6ce0df13655415ebbd8d4a4bcc2a8910b726476940e7fa3927efcc7674e05ad4',
    'e007f554e6b5bab5c5daa8ba1da01ea4f6640f98a964e9a9b9e1dee641c78cdf',
    '14555744831b09addf179b5d9a4a8ad8463d3d9236a7fbfbe71a69c2f340fa7d',
    'a49a6328e2d7d3bebaa295066375ac63df1afd5d9ae7955b6099fa145d79c360',
    'fa946708ae23a3e9d527f5ffd236c857d6fb123b6558cba9eafaabadb7aad37c',
    'ad89fb1f530c1f08c7bec6d1f65d66d4f73354ffcef54930920a052825012133',
    '2cdbd1a8c803142b56b9a27ebce2a4f2e70dca17428da6cc9d9c93ea31f34689',
    '8ae891e9350dc16506b13ba4cf8fdcae9fc3093a5a54f5690c25f58e1ddbacdd',
    'b38a541866c7247dee3334b5d74336131b9d1ebba47b7ce8db4d6a099664ce92',
    '0d23e20b5266c004a14a6037b502607ec811f453acd15f4ee55bbb2c88102e64',
    '4c9029feaa74b48648d5ed8dce4b89db69056df2f553d5280188f7172c8b9245',
    'a9f572362e4411d69cf2d16e187b2ca5feb8e3dea29c330f188a47f8280951f9',
    'b3383a832e5cb6a7ec2a2770c74fa1e6270e378ab06a04b976d2f0484fbc1332',
    'ff83dd83d0611faa48e3b596e74a5720f3705ff0c2fa8946e8970c89180cfead',
    '96e2727511085db834f60c0d1c543b369725fc76c08c81fef3bb150e1d78e891',
    'dfba26f7a23f0628dcde5a7194151ed68b6cd587ef6cc72ddfacc85edf12efd2',
    'e84eaa5c8b35684431536d3362eda2ff3db6e0a45efcf78c875388493832e162',
    '91a768f0856d48b2aa980e686f2edd76360579256028b8ea84ed609427d2f2c5',
    '1cfcff43d3624da4000635e7e873d590a7713dca072c90abf257e880aa395939',
    '392ebbf52dffc6172d123b986eb2af31add8e258ee8af0ec284c5eb42f3036a0',
    'ad17bce5b9b7c91b5b7aea7297714c248a6951377216641648caba25d549e258',
    '652e96ac2326da72a423d402409342dee99892f3b59cced5b3507deb378505e3',
    'ffe241ec6f11ac56b8a93c1115e6bc7752aec18e9a58e52cc1ba60d8737cd57b',
    'ada60eb914f00f71925bc801bac65be73eed63547e69866b904451b092543d3b',
    'd733f3edb98225d81c321661519d622364b3b42159710a68a9aa36f2954a07a6',
    '12a6a2f1933f0045ba095600057b027582a5a89a0652c9ac76b4a0d962037783',
    '28ebad2253e7459d8bbb88251df04452b92de6be9bfb396a6df72478d4e47498',
    'ad6630543ccb22d6fda4eff5f3f6c27d2bf18bf06a9468404a982408fe740b86',
    '6703ad7990b63b166c28be10ca5e8602c368f679d175526c641df928332afffd',
    '33943f1a481003466045d5f837770cff9a0787d1f64ee0b84e940341634f66e7',
    '0842be4a798b504b7310b948ff5ec6daaeaee8091b1e17d3b0079979f6f438a0',
    '536bf3d4a6683c80801719652542508d7ba15acc8b1178f5e7634a435ab1c79e',
    '4cf7c20d9e408608e19bec863a68593a1803958a5e6946e5a18a7c2a0e96adda',
    '4f0dcfa2f40ab68759f7355f8e34322d6c5faca1bffcb97314b8417d769e1545',
    '1c17d44e3a6ac4cca752037460a3f88e4e01dedac7d19965f5ea4dab1ea25a7b',
    '22d4d050fd857c8885795590d8bd9739a174fca2c02e7352cd96be7f61059998',
    '11d5b530b0acc46ca961eb83cc266327e68306b034330bdd8e042794d6fb0b03',
    '93dd5e7cb0aca5a509cfe79a32b596e042792a8b99144c892f6bddbbccdc3140',
    '8954830eb8f26a1b177f4f32350b8bc97fde6617dfbdfb4532ea491b555c62d1',
    '721169487b23970e992d0f116d4d7662577086dab558a811c0799a86e9ab9704',
    '2c72953a2e42897a9c7edd276b92c56e5392c6330dbdc2dfab34dce2887de6c0',
    '30b444119c06fd78123b6f035d47a3aaa08e58fd6788a19a11ab99e4638ff90e',
    '38aed9f90c8933c2f9898d8734590e6f5df446cc7840c058b567c17e7259cd23',
    'c44f3615b0c8dcab245d34d8cfd28387263601e4b93d879da57f984452039b56',
    'b0abd3dbe91419339d51cad035f2d469df3a99b7b138754dda69e52a4a836e4a',
    'ec3965a8f00b1523d9d742e5d0bc6a4a56f25be51b3af01377cb90b76440144b',
    'd44e2ec5ec928ba7340c10d79716ec2267cb791e3597ffcd30b4b6c827648575',
    '27dbb8b95f0644712790d6906aa997734587a257ab067c9b06bd4b309f7a0e3c',
    '1c5930b19dabbd5df228cf8830544e137a65815be2b6cfc90f220caa2adf7aec',
    '67decfdd1ab85642e4f72afb228ff658947341b243d93b8b7af51be0ada49652',
    'e3699ca09c268ef3f2f5e7eb40d62944c6563464680f521fd22b52b750141294',
    '785d74a9da5dad5a0182564eba743b8b58b7af5cf88c2d7be53f87a732b6efa0',
    '87b027f2ebb3be8a50102e81b1cc4c55eaacce5b897c835af4547f1e476caa8d',
    '41ff2674d59e024bb4b64cc800d2d227c10b7aeca3eb25628bb4d95f21f3bcbd',
    '887fa05310209608f911708ff112316f1e1d79a2e9d7b89c90ab35b47d28e027',
    '2d0c1ea863f0a653a680c849d12f0cedab4f41bf1a19c69574a38a712b5cd662',
    '382bf80117d9c2539c59bdc6b4b7064a8aff48901ce882cc1e543cf5a80600e6',
    'b88b41cdb09c6c7c6c1aaf5b800efdac554c5d62c622afa2bcf24015f4f8e5a4',
    '516c9356ad469e9b69d7d096af81bb5a3392fdfaf6b5f53bec4bd455220d6369',
    'cade717ef7fa8fd2391e516f6ce35645d61537ee9917839c22f0fd11b9062cb1',
    '295361e85252fd4b3cf39cd0844d2958b73fdce783566b3e4fa081d170b07790',
    'f6a9db17c8b183dd57a52a40666a54265ae9e0e54c8c3c94b350287caf16565e',
    '1dba106cfd41a451e05f5937cf37bdbeed9d45b7dcd171ffb60f0614962137ea',
    '23de7b9ee32289e9cf22e399641fafb26ac9ec3340841197cfab175e9f33e686',
    '391e6f01210fd142b6e6191f5b1df4d934c167469dd33ce1e82ad930a4a93078',
    'e48b2f0944b5c6edff39172c61df715ab99092966a93ee2577cf56d9647dce56',
    '2dddfd264916ecdb5401be26466311f113ed202ef03fd74ca3e4e1d59a0c5c0b',
    '8421b703d6d6f2cbd83776427ac147571497ef1287d575f13a993641f2c3b037',
    '83c2c91de96e475789de15d7054960c402f33aa2a94bb91bdda23d75a4af777e',
    '13053dbed67d4bf423bd5841d697813b2152ae009e43fe98b487693d6a606584',
    '82f34e9a743b4e89612912890cb2a1cc515b75e71e9524f890f314cdc39969eb',
    '99a070e71365cb51a78b197b8a5a73dceec7b8411dcc0eee2fd35448324cd8fd',
    '65a2831bf7ff77a0435c81bca49702f7187ce1507a6f41bfae994d7d79ec7646',
    '577e4b511190b9f62d415b198959d186bedca1a9fda90424c4861f3795575c0f',
    '53b156c46da7fa3315cf06b2f1f7d8087796f831e71c037267851c2cdcccdc08',
    '3bbb69551f70b188049d1e970b5fedf970b1b762187ee96d4c7d0f85a33363d3',
    'ca52f9a9060e3e21a65fb5947a17aadea8cb17d1a7cf2677ae74823baec6770e',
    '0810db52acce525b2f71d6e1d4c6b9355195d00d1f3595f55d69e52dd1cec1ec',
    '784db21e059c2f4241861d4a6203d777dd9dd62f10ca2f42a7258baaad532588',
    '6475f7f029988990f47d105453c4c244ae9322b13982df31134d495888b2616f',
    '6db081f3272c5d97ec6248f7968103ed608de3652650c6693eacd22dbfe2f318',
    'f1fac42e96d515fb02329d60b941f8b3fb765b4110601e2bab0f63cad1564703',
    '5c437a6e8934be5afbdf965af19d86dbddcbcd2b19953e271cd59c443027e3d8',
    '4ea7eaa2f0857307f836412fb3b04d8aec89f952aabc14faf925c661acb602a3',
    '62c47ed052ad8a3e0530d63c2c37cc4b84d0e73b1348a5a141224ac50112dc85',
    'c9411fe5b3f755f4819e17662b6aa5a91e813feb04430098e860289a76d5185f',
    'a58f2c34685c74cc4ac1f14933a5caaf4fd3031f61aecbc061e6793cae38a428',
    '5bae511483c9aced30b564bfc287b948448ed4011f9507f190f7ab439be51c40',
    'fe80f74d1684e22d2294a40d69e77fa1379fd90944e54297bf622cb5c56bf0c0',
    '53167861512d6befeb2fbf10d8cb3e05ee00b1d0410665bfb02fbc28521c89ec',
    '3fb714fd6e308eb517255369fa5c7f12fe49c054b01c288b71866bf79bab3fd6',
    '09cc16597e9cfc7b7da6bf31daaad0df6c2a9bda893a1823324a16ddb95e93e5',
    '938b3db47b58551b7e9ee64b809e80447d2d95225035b339defed8e417cc0b33',
    '1da7df08cdb1b02fd95fcff262414b88afdf3069a73b6535786cddbabc14a650',
    'e06b6141294bec370572a6763a583a2e99e97d8d09722e95eda7009f173b3b6f',
    '18bdb31c52d21cbe93b531aecff5d736091b1de93e3f6de39399f0466cd9290a',
    '59fae38152c183f598163940116fb88b58e1ff632345ed464d9e38d3bfee8b5f',
    '4f42d84f5e89be3d888b4dcaf199a5d9c332e1067a73f39d2ff92971498a7285',
    '0048636bbe168146ec66a2107d2afa99a314539942b5573e07d79c5d0ef3499b',
    '92c4f41eab0e8d1e78a1ab921e351abc632b7099405fc8a3ae682ac3f7c91212',
    '723cf1f73ecd985991563d49a9b528168746baa8953b5f43fb7b0acc76fb0d8c',
    '9472580edc80ae248611699565b51010929d7ab5bad5d41f97b54c8ab32dc785',
    '6559c8582e911173fcea0520ca32a1094bade553fc2dcdb98729db996258705f',
    '988cbd1845d332355f6a2e9ac46c41bf4bfeaa15f14075887e2f056944e812bf',
    '0f9ec9381a683cc20acea3b8bba5358c867813c6a1f9f0c7022ce63eb7a0fe6d',
    '77286e2f354abfb01be4ba6d706c01864e58026e4128d4be74ee0b8094450c4d',
    '0081e0fadc6cae29345cfe2f57a9048ca037c0b78cd368f768573d88cbdbc3a9',
    'ae17505494695d320c700556c71daeafa8fabc947cd9201658dcf364234156f5',
    'd8337f4d12bf6e374dd8dffc93e8870fe70354292a53d2d811ff356f8128c200',
    '2d9278c5464bd820cb7d91e026e6ac96d7d8aee9ecba49796fd7ce0050aef4f0',
    'a21c30379c8160e31d831b1cb16be8ed1273b6c65411188bbfa6ee17572b83e6',
    '8ca2f40b25ca69ee54fb0515bbfc6a91c8e6b1b644d07353fe3fd3e73b9e2ef2',
    '6eb4c10898404fcde3694563298ba9671cdc290a120670b1a4eb3b78c151af58',
    'b85d2fb3e43d97e50b4c7c5d217ab3d9c6dc5837b31bc0788b9cff1f9612a5a5',
];
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
