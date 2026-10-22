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
import { CloudRow, deleteRowLocal, queryAllRows, registerCloudRowsReady, registerRowFlush, upsertRow, upsertCloudData, connectCloudSyncArbiter, writeTombstone, forceCloudSyncNow } from '../utils/CloudSyncUtil'; // ★ 0.165.1 云同步桥接；★ 0.228.0 行模式原语（reconcile/flush/行写）；★ 0.230.1 writeTombstone（显式墓碑唯一出生通道）+ forceCloudSyncNow（缺片 nudge 重拉）
import { WordItem, WordFolder, WordBankStore } from './WordModel'; // ★ 0.228.0 行桥接（词池序列化/复活）
import { KnowledgeCard, KFolder, KnowledgeBankStore } from './KnowledgeModel'; // ★ 0.228.0 行桥接
import { wordToPlain, cardToPlain, folderToPlain, reviveWord, reviveCard, reviveFolder } from '../utils/BackupUtil'; // ★ 0.228.0 plain 流水线复用（0.205.4 纪律）
import { FaceModeStore, connectFaceMode } from './FaceModeStore'; // ★ 0.228.0 cfg:face-mode
 import { cryptoFramework } from '@kit.CryptoArchitectureKit'; // ★ 0.194.0：兑换码 SHA256 离线校验
 import { connectHuaweiAccount } from '../utils/HuaweiAccountUtil'; // ★ 0.194.0：stampFreeTrialOnLogin 统一试用打点（无循环依赖：HuaweiAccountUtil 不引 ChatModel）
 import { siyiGateReady } from '../utils/SiyiGate'; // ★ 0.293.0：SP 云同步门卫（SiyiGate 不引 ChatModel——无循环依赖）
 import { connectConfirmDialog } from '../components/AppConfirmDialog'; // ★ 0.293.0：新用户礼包仪式感弹窗桥（AppConfirmDialog 不引 ChatModel 不成环）
import { trackUidAuto, setDailyLdProvider } from '../utils/TrackUtil'; // ★ 0.260.0：sp_grant 发放埋点（无循环依赖：TrackUtil 不引 ChatModel）；★ 0.273.0：setDailyLdProvider（app_daily 日活行的 ld 字段注入位——TrackUtil 禁 import ChatModel，由本模块单向注入）
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
  @Trace model: string = ''; // ★ 0.224.3：生成本条回复的模型 ID（请求发出时打标——操作行显示供用户跨模型对比；旧消息空串不显示）
  @Trace cacheHitTokens: number = 0; // ★ 0.247.4：命中缓存的输入 token 数（腾讯云 usage.prompt_tokens_details.cached_tokens；0=无缓存数据/旧消息）
  @Trace reasoningTokens: number = 0; // ★ 0.271.0：其中思考 token 数（usage.completion_tokens_details.reasoning_tokens——P0-1 实测 TokenHub 回传；已计入 outputTokens，本字段仅拆分展示用；0=未思考/旧消息）

  constructor(messageId: string, role: ChatRole, content: string, imageUrl: string[] = [], inputTokens: number = 0, outputTokens: number = 0,
              isPodcastMode: boolean = false, model: string = '', cacheHitTokens: number = 0, reasoningTokens: number = 0) { // ★ 0.247.4/★ 0.271.0：尾部追加（可选参默认 0，现有调用点零破坏）
    this.messageId = messageId;
    this.role = role;
    this.content = content;
    this.imageUrl = imageUrl;
    this.inputTokens = inputTokens;
    this.outputTokens = outputTokens;
    this.isPodcastMode = isPodcastMode;
    this.model = model;
    this.cacheHitTokens = cacheHitTokens;
    this.reasoningTokens = reasoningTokens;
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
  @Trace topicTags: string[] = []; // ★ 0.265.0：话题词 0~5 个（记忆引擎一期 WP2——随节点行持久化，云同步自然携带）
  @Trace summaryHead: string = ''; // ★ 0.265.0：分支摘要头（一行：节点标题+一句话摘要；失活时生成）
  @Trace summaryHeadCount: number = 0; // ★ 0.265.0：上次生成摘要头时节点消息总数（失活重生成判据基准，同 historySummaryCount 先例）

  constructor(nodeID: string, parentID: string | null, messages: ChatMessage[], x: number, y: number, parentX: number = 0, parentY: number = 0,
              historySummary: string = '', historySummaryCount: number = 0, nodeTitle: string = '',
              draftText: string = '', draftImages: string = '', topicTags: string[] = [],
              summaryHead: string = '', summaryHeadCount: number = 0) {
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
    this.topicTags = topicTags; // ★ 0.265.0
    this.summaryHead = summaryHead; // ★ 0.265.0
    this.summaryHeadCount = summaryHeadCount; // ★ 0.265.0
  }
}

// V2 全局状态：包装 nodeList，AppStorageV2 内存（持久化通过 PersistData JSON）
@ObservedV2
export class BubbleTree {
  @Trace nodeList: BubbleNode[] = [];
  @Trace needsRelayout: boolean = false; // ★ 0.126：标记需要重新布局（新建气泡后触发）
  @Trace needsCloudRedraw: boolean = false; // ★ 0.223.0：云端下行重建画布（保坐标重绘连线，绝不 autoLayout 重排——对端坐标是真相）
  // ★ 0.244.0：渲染世代计数器——nodeList 被【整体替换为新对象】（云同步 refreshWorkspaceFromPools /
  //   模式切换 / 删 Tab 等）或坐标被批量改写（autoLayout）时 +1。画布 ForEach 的 key 拼入此值，
  //   强制条目重建重新捕获当前对象。根因（0.244.0 实锤）：ForEach 稳定 key 复用条目时，条目闭包持有
  //   旧对象——云同步隐藏期替换 nodeList 后，旧坐标冻结渲染（气泡重叠+连线悬空），直到页面重建才恢复。
  //   不持久化（serializeBubbleTree 只序列化 nodeList，此字段无 Schema 影响）。
  @Trace rebuildEpoch: number = 0;

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
  model?: string; // ★ 0.224.3 新增（可选字段，旧数据无此字段，反序列化时 ?? '' 兜底）
  cacheHitTokens?: number; // ★ 0.247.4 新增（可选字段，旧数据无此字段，反序列化时 ?? 0 兜底）
  reasoningTokens?: number; // ★ 0.271.0 新增（可选字段，旧数据无此字段，反序列化时 ?? 0 兜底——思考 token 拆分展示）
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
  topicTags?: string[]; // ★ 0.265.0（可选，旧数据无此字段兜底空数组）
  summaryHead?: string; // ★ 0.265.0（可选，旧数据无此字段兜底空串）
  summaryHeadCount?: number; // ★ 0.265.0（可选，旧数据无此字段兜底 0）
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
          isPodcastMode: msg.isPodcastMode, // ★ 0.133
          model: msg.model, // ★ 0.224.3
          cacheHitTokens: msg.cacheHitTokens, // ★ 0.247.4
          reasoningTokens: msg.reasoningTokens // ★ 0.271.0
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
        draftImages: node.draftImages,
        topicTags: node.topicTags, // ★ 0.265.0：摘要头字段随树序列化
        summaryHead: node.summaryHead, // ★ 0.265.0
        summaryHeadCount: node.summaryHeadCount // ★ 0.265.0
      };
    })
  };
  return JSON.stringify(data);
}

// ★ 0.287.0：按模式分池保存（公共函数）——ChatPage/BBTreeCanvas 两处 saveTree 逐字重复体收口，
//   同时供撤销栈闭包使用（参数全为应用级单例，闭包安全——页面销毁后仍可调用）。
//   ⚠️ 防环红线：ChatModel 禁 import CloudSyncUtil——云上行经 cloudUpsert 参数注入（调用方传 upsertCloudData）
export function saveBubbleTreePools(store: BubbleTree, canvasModeStore: CanvasModeStore,
  tabForest: TabForestStore, persistData: PersistData,
  cloudUpsert: (key: string, value: string) => void): void {
  if (canvasModeStore.mode === 'tabs') {
    const tabs = parseTabs(tabForest.tabsJson);
    const idx = tabs.findIndex((t: TabMeta): boolean => t.id === tabForest.activeTabId);
    if (idx >= 0) {
      tabs[idx].treeJson = serializeBubbleTree(store);
      // ★ 0.151-bugfix2：Tab 名同步为树根显示名（聊天/改标题后 Tab 名跟随）
      const root = store.nodeList.find((n: BubbleNode): boolean => n.parentID === null);
      if (root !== undefined) {
        tabs[idx].name = getRootDisplayName(root);
      }
      tabForest.tabsJson = serializeTabs(tabs);
      cloudUpsert('tabs_pool', tabForest.tabsJson); // ★ 0.165.1：云同步桥接（注入）
    }
    // 无 activeTab：无主工作区无可保存内容，直接跳过（不写任何池）
  } else {
    persistData.bubbleTreeJson = serializeBubbleTree(store);
    cloudUpsert('flat_pool', persistData.bubbleTreeJson); // ★ 0.165.1：云同步桥接（注入）
  }
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
          msg.isPodcastMode ?? false, msg.model ?? '', msg.cacheHitTokens ?? 0, msg.reasoningTokens ?? 0); // ★ 0.133：旧数据无此字段自动补 false；★ 0.224.3：旧消息无模型标记补空串；★ 0.247.4：缓存命中补 0；★ 0.271.0：思考 token 补 0
      });
      return new BubbleNode(node.nodeID, node.parentID, messages, node.x, node.y, node.parentX, node.parentY,
        node.historySummary ?? '', node.historySummaryCount ?? 0, node.nodeTitle ?? '', // ★ 0.147：旧数据无此字段自动补空串
        node.draftText ?? '', node.draftImages ?? '', node.topicTags ?? [], node.summaryHead ?? '',
        node.summaryHeadCount ?? 0); // ★ 0.214.2：旧数据无草稿字段自动补空串；★ 0.265.0：旧数据无摘要头字段自动补默认（零迁移）
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

// ★ 2026-10-17 用户拍板：腾讯云 DeepSeek-Flash=上线后唯一对外模型，由「自定义配置」档承载
// （端点/模型/Key 全内置开箱即用；Key 走 rawfile/config.json 不入库；测试期火山/DeepSeek 预设保留）
export const TENCENT_CHAT_ENDPOINT: string = 'https://tokenhub.tencentmaas.com/v1/chat/completions';
export const TENCENT_CHAT_MODEL: string = 'deepseek/deepseek-flash';

// API 配置（火山引擎方舟）：PersistenceV2 持久化，跨重启保存
@ObservedV2
export class ApiConfig {
  // ★ 0.161.3：内置 Key 从源码硬编码改为 rawfile/config.json 读取（该文件 .gitignore 忽略绝不入库，
  // 源码可安全上传 GitHub）；默认值改空串，由 EntryAbility 启动时调 loadBuiltinApiConfig 填充。
  // 用户在设置页自定义过的 Key（持久化非空）优先，不被内置值覆盖。
  @Trace apiKey: string = '';
  @Trace endpoint: string = TENCENT_CHAT_ENDPOINT;
  @Trace model: string = TENCENT_CHAT_MODEL; // ★ 2026-10-17：默认模型换腾讯云 DeepSeek-Flash（上线唯一对外模型；自定义档承载，key 经 config.json 内置）
  @Trace provider: string = 'custom'; // ★ 0.190.0：模型提供商（huawei/volcano/deepseek/custom）；★ 2026-10-17 默认改 custom（腾讯云）
  @Trace audioModel: string = 'seed-icl-2.0'; // ★ 0.232.1：默认音频模型=声音复刻 2.0（用户拍板；2026-10-14 实证 seed-icl-2.0+S_ 音色 code=0 直连）；seed-tts-2.0=豆包语音合成 2.0（官方音色体系）
  @Trace audioVoice: string = 'S_bv8H32Sg2'; // ★ 0.232.0：默认音色=用户合成音色（声音复刻体系 S_ 前缀，用户提供）；未开通复刻资源时引擎自动回退官方音色 zh_female_vv_uranus_bigtts（55000000 重试）
  @Trace audioEndpoint: string = 'https://openspeech.bytedance.com/api/v3/tts/unidirectional'; // ★ 0.139：TTS 端点（openspeech HTTP 单向流，与 LLM endpoint 相互独立）
  // ★ 0.161.3：TTS 专用 Key 同样改 rawfile/config.json 读取（与方舟对话 Key 相互独立——两套体系
  // Key 不通用，0.139 拿方舟 Key 实测 401 Invalid X-Api-Key）
  @Trace audioKey: string = '';
  // ★ 0.236.0：千问 TTS 专属字段（Schema 铁律——只尾部追加，不改不删前三字段）
  // ttsProvider：'local' | 'volcano' | 'qianwen' | 'custom' 四档（★ 0.272.0 扩 local——TTS 1.0
  //   默认本地语音零成本；云端三档物理互斥铁律不变：选了哪个只调哪个，禁止按 Key 存在自动切换）；
  // audioKey/audioModel/audioVoice 云端三档复用承载当前生效引擎的值（local 档不写入不覆盖——
  // 切回云端档配置还在）；存量已存 volcano/qianwen/custom 的不迁移（PersistenceV2 落盘值不动）
  @Trace ttsProvider: string = 'local';
  // ttsEmotion：千问档情感档位（'默认'=不带 instruction；'开心'/'中立'/'生气'/'悲伤'/'惊讶'
  //   引擎内映射为百炼 instruction 自然语言指令——2026-10-14 实测 cosyvoice-v3.5-plus 无 emotion 枚举字段）
  @Trace ttsEmotion: string = '开心';
  // ttsSpeed：千问档语速（0.5~2.0，百炼 rate 参数）；ttsVolume：千问档音量（0~100，百炼 volume 参数）
  @Trace ttsSpeed: number = 1.0;
  @Trace ttsVolume: number = 50;
  // ★ 0.238.0：模型别名（应用内展示名；空=显示官方模型 ID）——别名是全局单值跟随配置，
  //   消息级不存别名（旧消息 model 与当前配置不同时自然回落官方名，零迁移）
  @Trace modelAlias: string = '';
  // ★ 0.291.2：文档解析服务（腾讯云 OCR·多模态文档解析）专属凭证——与 chat 的 apiKey
  //   （TokenHub 体系）相互独立，走用户个人 CAM 密钥（A 模式：用户自配风险自担，与
  //   DeepSeek/火山 key 同构）；空=未配置（选 docx/pdf 时友好提示）
  @Trace docSecretId: string = '';
  @Trace docSecretKey: string = '';
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
// ★ 0.238.0：key 再从 'api-config-v3' 换为 'api-config-v4'——同理（新增 modelAlias 字段写不进
// v3 旧快照，0.143/0.190/0.224.1 三次实锤：不换 key=新增字段重启即丢）；v3 数据全量迁移
// （含 0.236.0 千问 TTS 四字段），modelAlias 旧快照从未存在、走新默认空串。
// ★ 0.240.2 方案B拍平存储（豆包+华为AI双评审共同方案，终案）：放弃用 13 个 @Trace 字段的
//   @ObservedV2 类直接做 PersistenceV2 key（v2→v3→v4 三代同坑），api-config 整体改为「单 string
//   存 JSON」——与 'model-alias-v1'（ModelAliasStore）完全同构，0.240.1 全天唯一 100% 可靠的实证
//   模式（纯 new factory + 顶层 connect + key 一次性首创 + 永不嵌套 + 永不换 key + 结构永不加字段）。
//   B1（盘值被冷启工厂值回滚）/B2（嵌套 connect 毒害水合）/B3（行为自相矛盾）一键绕开。
//   ApiConfig 保留为运行时视图：@Trace 响应式照常驱动 UI；持久化=进程级单例 runtimeApiCfg，
//   启动读 JSON 全量灌入（connectApiConfig），保存全量写 JSON（snapshotApiConfig）。
//   0.240.1 病象族谱（供后来者避坑）：①v4 modelAlias「写盘正常、重启读恒空」；②「火山 Key 保存→
//   重启变空」；③「献祭档保存落盘→重启回显被回滚成旧档」；④四版首启 v4 盘值 glm 被重置成类默认。
//   共因=带 factory 的 connect 冷启时盘值被 factory 值覆盖（嵌套 connect 还毒害被嵌 key 水合）。
//   迁移链（一次性，幂等判据=v5 非空天然跳过）：backup 快照（0.240.1 五版用户）> v4 实例 > v3 实例，
//   全部顶层 connect 非嵌套；迁移成功即写回 v5 转正，此后永不再读旧 key。
@ObservedV2
class ApiCfgStore {
  @Trace cfgJson: string = ''; // api-config 主真相源（plain JSON；空=从未保存过/新用户）
  // ★ 0.240.2 水合竞态补灌回调：PersistenceV2.connect 返回实例时盘值水合可能尚未完成（真机实锤：
  // onCreate 首读 cfgJson=''（水合 pending）→ 误判新用户走迁移链灌入 backup 旧值；同款代码有时存活
  // 有时重置的 B3 矛盾=读得早/晚与水合完成的赛跑）。@Monitor 在水合完成（cfgJson 被框架赋盘值）时
  // 触发补灌，把 runtimeApiCfg 修正为盘上真值。
  onHydrated: (() => void) | null = null;

  @Monitor('cfgJson')
  onCfgJsonChange(): void {
    if (this.cfgJson.trim().length > 0 && this.onHydrated !== null) {
      try {
        this.onHydrated();
      } catch (_e) {
        // 补灌异常静默（下次变化重试）
      }
    }
  }
}

// 二级兜底快照（0.240.1 通道保留：saveAll 双写，成本≈0；仅供未来排查，不再参与自愈判定）
@ObservedV2
class ApiCfgBackup {
  @Trace cfgJson: string = '';
}

function apiCfgToBackupJson(cfg: ApiConfig): string {
  const plain: Record<string, string | number> = {}; // @ObservedV2 实例禁直接 stringify（0.205.4 铁律）
  plain['apiKey'] = cfg.apiKey;
  plain['endpoint'] = cfg.endpoint;
  plain['model'] = cfg.model;
  plain['provider'] = cfg.provider;
  plain['audioModel'] = cfg.audioModel;
  plain['audioVoice'] = cfg.audioVoice;
  plain['audioEndpoint'] = cfg.audioEndpoint;
  plain['audioKey'] = cfg.audioKey;
  plain['ttsProvider'] = cfg.ttsProvider;
  plain['ttsEmotion'] = cfg.ttsEmotion;
  plain['ttsSpeed'] = cfg.ttsSpeed;
  plain['ttsVolume'] = cfg.ttsVolume;
  plain['modelAlias'] = cfg.modelAlias;
  plain['docSecretId'] = cfg.docSecretId; // ★ 0.291.2：文档解析服务凭证（尾部追加）
  plain['docSecretKey'] = cfg.docSecretKey;
  return JSON.stringify(plain);
}

let runtimeApiCfg: ApiConfig | null = null; // 进程级运行时视图单例（多处 connectApiConfig 复用同实例）

export function connectApiConfig(): ApiConfig {
  if (runtimeApiCfg !== null) {
    return runtimeApiCfg; // 同实例复用（GSD/ChatPage/Review/WordBank/Statistics/CloudTts 等七处调用点）
  }
  const store = PersistenceV2.connect(ApiCfgStore, 'api-config-v5', () => new ApiCfgStore()) as ApiCfgStore;
  const cfg = new ApiConfig(); // 纯运行时实例（@Trace 响应式与 PersistenceV2 无关）
  const applyJson = (json: string): boolean => {
    try {
      const b = JSON.parse(json) as Record<string, string | number>;
      cfg.apiKey = String(b['apiKey'] ?? '');
      cfg.endpoint = String(b['endpoint'] ?? cfg.endpoint);
      cfg.model = String(b['model'] ?? cfg.model);
      cfg.provider = String(b['provider'] ?? cfg.provider);
      cfg.audioModel = String(b['audioModel'] ?? cfg.audioModel);
      cfg.audioVoice = String(b['audioVoice'] ?? cfg.audioVoice);
      cfg.audioEndpoint = String(b['audioEndpoint'] ?? cfg.audioEndpoint);
      cfg.audioKey = String(b['audioKey'] ?? '');
      cfg.ttsProvider = String(b['ttsProvider'] ?? cfg.ttsProvider);
      cfg.ttsEmotion = String(b['ttsEmotion'] ?? cfg.ttsEmotion);
      cfg.ttsSpeed = Number(b['ttsSpeed'] ?? cfg.ttsSpeed);
      cfg.ttsVolume = Number(b['ttsVolume'] ?? cfg.ttsVolume);
      cfg.modelAlias = String(b['modelAlias'] ?? '');
      cfg.docSecretId = String(b['docSecretId'] ?? ''); // ★ 0.291.2：旧快照无此键=空串默认（尾部追加语义）
      cfg.docSecretKey = String(b['docSecretKey'] ?? '');
      return true;
    } catch (_e) {
      return false; // 坏数据兜底=默认（下次保存重建）
    }
  };
  // ★ 0.240.2 补灌器：盘值（水合完成）非空且≠已灌值 → 重灌 runtimeApiCfg。
  //   值等价门闩（lastApplied）：迁移/保存的自写回声与已灌值相等自然跳过——无自环、无覆盖用户
  //   正在编辑表单的风险（编辑副本独立，重灌只修正运行时真值）。
  let lastApplied = '';
  const reapply = (): boolean => {
    const j = store.cfgJson;
    if (j.trim().length === 0 || j === lastApplied) {
      return false;
    }
    if (applyJson(j)) {
      lastApplied = j;
      return true;
    }
    return false;
  };
  const loaded = reapply(); // 同步首读（水合已完成则直接命中；未完成走迁移链，水合后 @Monitor 补灌）
  store.onHydrated = reapply; // 水合完成/后续任何盘值变化 → 响应式补灌（ChatPage 消息行等消费点自动刷新）
  cfgReapply = reapply;
  if (!loaded) {
    // 一次性迁移（顶层 connect 非嵌套；迁移源尽力而为——B1 下旧实例可能读出工厂值，最坏=回默认）
    // ★ 仅灌内存不落盘（0.240.2 修正）：此刻若水合仍 pending，迁移写入会与水合互踩（迁移值落盘
    //   覆盖盘上真值=数据丢失）。转正交给下次保存（snapshotApiConfig 自然写全量）；真·新用户
    //   不保存就重启=重走迁移链（幂等无害）。
    let migrated = '';
    try {
      const bak = PersistenceV2.connect(ApiCfgBackup, 'api-cfg-backup-v1',
        () => new ApiCfgBackup()) as ApiCfgBackup;
      if (bak.cfgJson.trim().length > 0) {
        migrated = bak.cfgJson; // 0.240.1 五版用户的上次保存快照（最全真相源）
      } else {
        const v4IsDefault = (c: ApiConfig): boolean => c.apiKey.length === 0 && c.provider === 'volcano' &&
          c.model === 'deepseek-v4-flash-ga-260731';
        const v4 = PersistenceV2.connect(ApiConfig, 'api-config-v4', () => new ApiConfig()) as ApiConfig;
        if (!v4IsDefault(v4)) {
          migrated = apiCfgToBackupJson(v4);
        } else {
          const v3 = PersistenceV2.connect(ApiConfig, 'api-config-v3', () => new ApiConfig()) as ApiConfig;
          if (!v4IsDefault(v3)) {
            migrated = apiCfgToBackupJson(v3); // v3 老用户（v4 空档）兜底；别名真相在 map（GSD 回灌）
          }
        }
      }
    } catch (_e) {
      // 迁移源读失败静默（走默认）
    }
    if (migrated.length > 0) {
      applyJson(migrated); // 仅内存（水合完成后 @Monitor/复核把盘上真值重灌修正）
      lastApplied = migrated;
    }
    // ★ 第三保险：1.5s 延迟复核（水合必已完成——本地小 XML 毫秒级；防 @Monitor 极端不触发的情形）
    setTimeout(() => {
      reapply();
    }, 1500);
  }
  runtimeApiCfg = cfg;
  return cfg;
}

// ★ 0.240.2 开弹窗主动补灌（双保险第二通道）：GSD aboutToAppear 开头调用——此刻距 onCreate 已数秒，
//   水合必已完成，即便 @Monitor 未触发（框架内部赋值不走 setter 的极端情形）也能兜住表单回显真值。
let cfgReapply: (() => void) | null = null;

export function refreshApiCfg(): void {
  if (cfgReapply !== null) {
    cfgReapply();
  }
}

// ★ 0.240.2：配置落盘唯一主动通道——saveAll / 云同步 apply / 搭救回灌后调用。
//   双写：v5（主真相源）+ backup（0.240.1 兜底快照通道保留）。
//   ★ 保存即上行：cfg:api-config 行同步写本地 RDB（autoSync 推云）——根治「保存后上行不及时+
//   云端滞留旧值→冷启下行 apply 把回显/内存顶回旧档」（真机取证实锤的回滚第二凶）。
export function snapshotApiConfig(): void {
  try {
    const cfg = connectApiConfig();
    const json = apiCfgToBackupJson(cfg);
    const store = PersistenceV2.connect(ApiCfgStore, 'api-config-v5', () => new ApiCfgStore()) as ApiCfgStore;
    store.cfgJson = json;
    const bak = PersistenceV2.connect(ApiCfgBackup, 'api-cfg-backup-v1', () => new ApiCfgBackup()) as ApiCfgBackup;
    bak.cfgJson = json;
  } catch (_e) {
    // 落盘失败静默（下次保存重试）
  }
  try {
    if (connectCloudSyncArbiter().rowInitDone) {
      upsertIfChanged('cfg:api-config', cfgApiToJson()); // 首拉闸门内才写行（0.223.1 防种子事故同款纪律）
    }
  } catch (_e) {
    // 上行失败静默（下轮 flush 兜底）
  }
}

// ★ 0.238.1：模型别名映射表（按模型 ID 一一对应，用户拍板「别名跟模型绑定+自动记录」——
//   设置表单里切提供商/切模型别名自动带出，不每次重打）。独立全新 key 'model-alias-v1'
//   （Schema 铁律：全新 key 首次创建即含全部字段，零换 key 迁移负担，不动刚换的 api-config-v4）。
//   存储形态=string 存 JSON（@Trace string 持久化可靠；空别名存空串=回落官方名，不删键）。
//   消费分工：本表只服务设置表单回显与跨重启记忆；消息行展示仍走 apiConfig.modelAlias
//   （编辑副本「保存才生效」语义不变——未保存的别名不会泄漏到对话界面）。
@ObservedV2
export class ModelAliasStore {
  @Trace aliasMapJson: string = '{}'; // { "<模型ID>": "<别名>", ... }

  aliasFor(modelId: string): string {
    if (modelId.length === 0) {
      return '';
    }
    try {
      const map = JSON.parse(this.aliasMapJson) as Record<string, string>;
      const v = map[modelId];
      return v === undefined || v === null ? '' : v.trim(); // ★ 0.240.1：读侧 trim（纯空格=空，防残留脏值上屏）
    } catch (_e) {
      return ''; // 坏数据兜底：视同无别名
    }
  }

  setAlias(modelId: string, alias: string): void {
    if (modelId.length === 0) {
      return; // 模型 ID 未定（如自定义档空手填）不记录
    }
    const norm = alias.trim().length === 0 ? '' : alias; // ★ 0.240.1：纯空格归一为空串（测试台收尾清空通道）
    try {
      const map = JSON.parse(this.aliasMapJson) as Record<string, string>;
      map[modelId] = norm; // 空别名=存空串（aliasFor 读空串返回 ''，等效回落官方名）
      this.aliasMapJson = JSON.stringify(map);
    } catch (_e) {
      // 坏数据兜底：重建为只含当前键
      const fresh: Record<string, string> = {};
      fresh[modelId] = norm;
      this.aliasMapJson = JSON.stringify(fresh);
    }
  }
}

export function connectModelAlias(): ModelAliasStore {
  return PersistenceV2.connect(ModelAliasStore, 'model-alias-v1', () => new ModelAliasStore()) as ModelAliasStore;
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
  volcanoApiKey?: string; // ★ 2026-10-17：火山方舟内置对话 Key（apiKey 已让位给腾讯云默认；火山档测试期备查，上架前必删）
  audioKey: string;
  audioModel?: string; // ★ 0.232.1：内置音频模型（可选——缺省不动 audioModel）
  audioVoice?: string; // ★ 0.232.0：内置合成音色（可选——缺省不动 audioVoice）
  qwenTtsKey?: string; // ★ 0.236.0：千问 TTS 内置 Key（开发测试期预填千问档——上架前必删该字段）
}

// ★ 0.236.0：千问 TTS 内置 Key 模块级缓存（loadBuiltinApiConfig 填充一次；GSD 切千问档时
// 经 getBuiltinQwenTtsKey() 取用预填表单——不写持久化，用户自定义值优先纪律不变）
let builtinQwenTtsKey: string = '';

export function getBuiltinQwenTtsKey(): string {
  return builtinQwenTtsKey;
}

// ★ 2026-10-17：内置腾讯云对话 Key 模块级缓存（config.json apiKey；存量设备 apiKey 已持久化火山值
// 不被覆盖，GSD 切自定义档首次预填表单用——仅预填不写持久化，用户点保存才落盘）
let builtinTencentChatKey: string = '';

export function getBuiltinTencentChatKey(): string {
  return builtinTencentChatKey;
}

// ★ 2026-10-17：内置火山方舟对话 Key 模块级缓存（config.json volcanoApiKey；因腾讯云默认化后 apiKey
// 字段让位，火山档测试期经 getBuiltinVolcanoChatKey() 回填表单——不写持久化，用户自定义值优先）
let builtinVolcanoChatKey: string = '';

export function getBuiltinVolcanoChatKey(): string {
  return builtinVolcanoChatKey;
}

// ★ 0.236.1：内置火山 TTS Key/音色快照（loadBuiltinApiConfig 填充）——GSD 切火山档且
// 无会话缓存时回填表单（audioKey/audioVoice 三档复用承载，千问档保存会覆盖火山值，
// 切回火山档靠内置快照兜底显示，用户不再困惑"保存过的 Key 怎么没了"）
let builtinVolcanoTtsKey: string = '';
let builtinVolcanoTtsVoice: string = '';

export function getBuiltinVolcanoTtsKey(): string {
  return builtinVolcanoTtsKey;
}

export function getBuiltinVolcanoTtsVoice(): string {
  return builtinVolcanoTtsVoice;
}

// ★ 0.161.3：从 rawfile/config.json 读取内置 Key，填充持久化配置的空位。
// 仅填空位——用户在设置页自定义过的 Key（持久化非空）优先，不被内置值覆盖。
// ★ 0.232.0：audioVoice 旧默认值迁移——该字段自 0.139 起从未开放编辑（0.139 注释「设置页
// 不显示音色框」），存量持久化值必为旧类默认 zh_female_vv_uranus_bigtts；按值等价迁移到
// 内置合成音色（幂等：用户在新设置页改过音色后值≠旧默认，永不再覆盖）。
// ★ 0.232.1：audioModel 同款迁移——旧默认 seed-tts-2.0（豆包语音合成2.0）→ 内置
// seed-icl-2.0（声音复刻2.0，用户拍板默认；2026-10-14 实证 seed-icl-2.0+S_bv8H32Sg2
// code=0 直连可用）。字段 0.232.0 才开放编辑且用户未改过（值=旧默认）才迁移，改过不动。
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
    const builtinModel = obj.audioModel ?? '';
    if (builtinModel.length > 0 &&
      (cfg.audioModel.length === 0 || cfg.audioModel === 'seed-tts-2.0')) {
      cfg.audioModel = builtinModel;
    }
    const builtinVoice = obj.audioVoice ?? '';
    if (builtinVoice.length > 0 &&
      (cfg.audioVoice.length === 0 || cfg.audioVoice === 'zh_female_vv_uranus_bigtts')) {
      cfg.audioVoice = builtinVoice;
    }
    // ★ 0.236.0：千问 TTS 内置 Key 只存模块级变量（不写持久化）——GSD 切千问档且用户未自定义时
    // 预填表单；默认 ttsProvider 保持 'volcano' 不变，不打扰现有火山体验
    builtinQwenTtsKey = obj.qwenTtsKey ?? '';
    // ★ 2026-10-17：腾讯云对话 Key 内置缓存（config.json apiKey 即腾讯云 key；存量设备持久化非空
    // 不覆盖，仅供 GSD 切自定义档首次预填表单——用户点保存才落盘）
    builtinTencentChatKey = obj.apiKey;
    // ★ 2026-10-17：火山方舟对话 Key 内置缓存（apiKey 已让位腾讯云默认；火山档测试期回填表单用）
    builtinVolcanoChatKey = obj.volcanoApiKey ?? '';
    // ★ 0.236.1：内置火山 Key/音色快照（切火山档兜底回填用——config.json audioKey/audioVoice）
    builtinVolcanoTtsKey = obj.audioKey;
    builtinVolcanoTtsVoice = obj.audioVoice ?? '';
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

// ★ 0.234.0：注意力锚点偏好（锚点卡片/密度/分章折叠三字段）——独立全新 key 'anchor-pref-v1'
// （0.143 铁律：绝不往 ai-preference-v2 旧快照类加字段；独立 key 让称呼/鼓励零迁移零风险）
// anchorDensity：密度档（★ 0.237.0 两档制，用户拍板去掉「中」：dense 密 400 / sparse 疏 800 字，默认疏；
//   遗留 'standard' 值由 breathThreshold/设置分段兜底为疏，不改写已落盘数据）；foldMode：长文分章折叠开关（off/on，默认开）
// ★ 0.269.0 anchorMode 三态值域：off=关 / smart=智能锚点（单段式，默认） / companion=伴读模式（两段式）；
//   遗留 'on' 值不改写（★ 0.237.0 脏检查坑——AnchorPref 自身也是该 key 的 connect 工厂，改写旧值
//   会触发持久化脏写），一律由消费侧归一函数归到 'smart'（写入时机=GSD 保存，语义完全等价）
@ObservedV2
export class AnchorPref {
  @Trace anchorMode: string = 'smart';
  @Trace anchorDensity: string = 'sparse';
  @Trace foldMode: string = 'on';
  // ★ 0.271.0：深度思考三态（auto 跟随模式=短关/中计分/长 high / always 每次思考 / off 全关）——
  //   Schema 尾部追加合规（任务书 §3.7：AnchorPref 同 store 追加，免新 key 免 redlineKeys 补录）
  @Trace thinkingMode: string = 'auto';
}

// ★ 0.271.0：thinkingMode 归一（非法值/遗留值一律归 'auto'；一切比较侧统一走此函数，normalizeAnchorMode 同源纪律）
export function normalizeThinkingMode(mode: string): string {
  if (mode === 'always') {
    return 'always';
  }
  if (mode === 'off') {
    return 'off';
  }
  return 'auto';
}

// ============================================================
// ★ 0.271.0：深度思考策略（任务书 §3.1/§3.2 终稿）——纯函数集，ohosTest 断言消费
// ============================================================

// 思考档位常量（effort 仅 low/high 两值合法——max 不暴露：平台仅两档+成本 2~3 倍，任务书 §3.3.4）
export const THINK_EFFORT_LOW: string = 'low';
export const THINK_EFFORT_HIGH: string = 'high';

// ★ 0.271.0：思考档请求/解析结果统一类型（ApiClient.streamChat 尾参与 resolveThinkingFor 返回共用——
//   arkts-no-structural-typing 铁律：同结构两个 interface 互相赋值=结构类型违规，必须单一具名类型；
//   定义收口本文件，ApiClient 从此处 import，ChatModel↔ApiClient 零循环依赖）
export interface ThinkingRequest {
  enabled: boolean;
  effort: string; // enabled 时仅 'low'|'high' 两值合法（max 不暴露——平台约束+成本取舍）
}

// S5 显式指令关键词（用户原话直通 high，不走计分）
const THINK_EXPLICIT_KEYWORDS: string[] = ['深想', '认真想', '仔细分析', '好好想想', '深入分析'];
// S2 复杂度关键词（仅当 S1/S3/S4 至少一项同时命中才计分——串联条款防「分析一下这个段子」式误判）
const THINK_COMPLEX_KEYWORDS: string[] = ['为什么', '原理', '分析', '比较', '区别', '推导', '证明', '计算', '优缺点', '权衡'];
// S4 硬核话题（气泡 topicTags 命中任一即 2 分）
const THINK_HARD_TOPIC_KEYWORDS: string[] = ['数学', '物理', '化学', '编程', '算法', '法律', '医疗', '金融'];

/** ★ 0.271.0 §3.2：中回复加权计分（纯函数可测）
 * 返回 'high' | 'low' | 'disabled'
 * S5 显式指令直通 high；否则 Σ(S1+S2+S3+S4)：≥4→high / 2~3→low / ≤1→disabled
 */
export function scoreThinkingEffort(userText: string, topicTags: string, aiMsgCount: number): string {
  let s1 = 0; // 消息长度 ≥60 字
  let s2 = 0; // 复杂度关键词（串联条款）
  const s3 = aiMsgCount >= 3 ? 2 : 0; // 本气泡 AI 消息 ≥3 条
  let s4 = 0; // 硬核话题命中 topicTags
  for (let i = 0; i < THINK_EXPLICIT_KEYWORDS.length; i++) {
    if (userText.includes(THINK_EXPLICIT_KEYWORDS[i])) {
      return THINK_EFFORT_HIGH; // S5 直通，不走计分
    }
  }
  if (userText.length >= 60) {
    s1 = 1;
  }
  for (let i = 0; i < THINK_HARD_TOPIC_KEYWORDS.length; i++) {
    if (topicTags.includes(THINK_HARD_TOPIC_KEYWORDS[i])) {
      s4 = 2;
      break;
    }
  }
  // S2 串联条款：仅当 S1/S3/S4 至少一项同时命中才计分（S4 已先行计算）
  if (s1 > 0 || s3 > 0 || s4 > 0) {
    for (let i = 0; i < THINK_COMPLEX_KEYWORDS.length; i++) {
      if (userText.includes(THINK_COMPLEX_KEYWORDS[i])) {
        s2 = 1;
        break;
      }
    }
  }
  const total = s1 + s2 + s3 + s4;
  if (total >= 4) {
    return THINK_EFFORT_HIGH;
  }
  if (total >= 2) {
    return THINK_EFFORT_LOW;
  }
  return 'disabled';
}

/** ★ 0.271.0 §3.6.1：思考参数不兼容降级判定（窄门——仅 400 且匹配关键词才降；
 *  P0-4 实锤网关对错误参数静默忽略，本判定为防御网关未来行为变化）
 */
export function isThinkingParamError(errMsg: string): boolean {
  const lower = errMsg.toLowerCase();
  if (!lower.includes('400')) {
    return false;
  }
  return lower.includes('thinking') || lower.includes('reasoning') ||
    errMsg.includes('模型不支持') || errMsg.includes('参数非法');
}

/** ★ 0.271.0 §3.1：策略矩阵解析（场景×思考档）——纯函数可测
 * thinkingMode：GSD 三态（auto/always/off，调用侧先 normalizeThinkingMode）
 * replyMode：short/medium/long；isPodcast：听播恒 disabled（强制覆盖条款，无视开关与 always）
 */
export function resolveThinkingFor(thinkingMode: string, replyMode: string, isPodcast: boolean,
  userText: string, topicTags: string, aiMsgCount: number): ThinkingRequest {
  if (isPodcast) {
    return { enabled: false, effort: '' }; // 首字延迟高于一切
  }
  if (normalizeThinkingMode(thinkingMode) === 'off') {
    return { enabled: false, effort: '' };
  }
  const always = normalizeThinkingMode(thinkingMode) === 'always';
  if (replyMode === 'short') {
    // 短回复秒回定位：auto=disabled；always 仅升 low
    return always ? { enabled: true, effort: THINK_EFFORT_LOW } : { enabled: false, effort: '' };
  }
  if (replyMode === 'long') {
    // 长回复①段质量优先：high
    return { enabled: true, effort: THINK_EFFORT_HIGH };
  }
  // 中回复加权计分（always 直通 high）
  if (always) {
    return { enabled: true, effort: THINK_EFFORT_HIGH };
  }
  const effort = scoreThinkingEffort(userText, topicTags, aiMsgCount);
  return effort === 'disabled' ? { enabled: false, effort: '' } : { enabled: true, effort: effort };
}

// ★ 0.269.0：anchorMode 归一（遗留 'on'→'smart'；一切比较侧统一走此函数，0.237.0 脏检查坑同源纪律）
export function normalizeAnchorMode(mode: string): string {
  if (mode === 'companion') {
    return 'companion';
  }
  if (mode === 'off') {
    return 'off';
  }
  return 'smart'; // 'on'（存量）/'smart'/一切非法档位一律归智能锚点
}

// ★ 0.234.0：连接注意力锚点偏好持久化实例
export function connectAnchorPref(): AnchorPref {
  return PersistenceV2.connect(AnchorPref, 'anchor-pref-v1', () => new AnchorPref()) as AnchorPref;
}

// ★ 0.232.0：云端语音朗读首次配置提示 flag（用户要求：第一次填写音频配置时提示一次，
// 之后不再提示；独立全新 key——0.143 教训：不往旧快照类尾追字段）
@ObservedV2
export class TtsHintStore {
  @Trace cloudHintShown: boolean = false;
}

export function connectTtsHint(): TtsHintStore {
  return PersistenceV2.connect(TtsHintStore, 'tts-cloud-hint-v1', () => new TtsHintStore()) as TtsHintStore;
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
  spUsed?: number;      // ★ 0.259.0：SP 消耗量（consumeSiyiSp 收口累加；可选兼容旧数据——读取处 ?? 0）
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
    scheduleRowFlush(); // ★ 0.248.4：统计落盘即防抖上行（cfg:stat-days——等级头衔多端一致）
    return;
  }
  entry.inputTokens += inTok;
  entry.outputTokens += outTok;
  store.raw = JSON.stringify({ days: days } as StatDayData);
  scheduleRowFlush(); // ★ 0.248.4：统计落盘即防抖上行（cfg:stat-days——等级头衔多端一致）
  notifyLevelUp(days.length); // ★ 0.256.0：学习天数落盘即检头衔升级（本端学习路径）
}

// ============================================================
// ★ 0.279.1：历史测试统计数据一次性清理（用户指令——0.202.3 一年测试 seed 已随上线清零删除，
//   但设备/云端 statistics-v1 与 cfg:stat-days 行仍残留 360 天假数据；今日起用户真实使用，
//   需清掉「今天之前」的全部统计天，只保留当天真实数据）。
// 设计：持久化清理界 wipeDate（'YYYY-MM-DD'，空=未清理）——
//   ① 本地：启动后一次性删除 date < wipeDate 的天记录，flush 上行覆盖云端旧行（自愈）；
//   ② 云端：mergeStatDaysRow 下行吸收时丢弃 date < wipeDate 的云端天（防旧全量行 union 回灌）。
//   不动等级/签到/SP——头衔按 days.length 动态回落为真实值；升级桥 lastLevel 为 AppStorageV2
//   会话级，冷启动自然重建基线。
// ============================================================
@ObservedV2
export class StatsWipeMarker {
  @Trace wipeDate: string = ''; // 统计清理界日期（'YYYY-MM-DD'；'' = 未执行过清理）
}

export function connectStatsWipeMarker(): StatsWipeMarker {
  return PersistenceV2.connect(StatsWipeMarker, 'stats-wipe-date-v1', () => new StatsWipeMarker()) as StatsWipeMarker;
}

/** ★ 0.279.1：一次性清理历史测试统计（保留当天真实数据；本地已净也落 wipeDate——云端旧行同需免疫） */
export function wipeHistoricalTestStats(): void {
  const marker = connectStatsWipeMarker();
  if (marker.wipeDate.length > 0) {
    return; // 已清理过（幂等）
  }
  const today = statDateKey(Date.now());
  marker.wipeDate = today;
  const store = connectStatistics();
  const days = getStatDays(store);
  const kept = days.filter((d: StatDayEntry): boolean => d.date >= today);
  if (kept.length !== days.length) {
    store.raw = JSON.stringify({ days: kept } as StatDayData);
  }
  scheduleRowFlush(); // 无论本地是否有删动都上行——云端 360 天旧行靠本地净表覆盖自愈
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
  // ★ 0.261.0：IAP 已入账 purchaseToken JSON 数组（幂等防双入账；纯本地记录与 redeemedCodes 同类——
  //   不随 cfg 行上行：LWW 整行覆盖反而会丢别端 token，本地集合+permanentSp 云端 max 合并双保险已闭环）
  @Trace iapConsumedTokens: string = '[]';
}

// ★ 0.194.0：连接订阅持久化实例
export function connectSubscription(): SubscriptionStore {
  return PersistenceV2.connect(SubscriptionStore, 'subscription-v1', () => new SubscriptionStore()) as SubscriptionStore;
}

// ★ 0.194.0：统一试用打点——已登录且从未记录 → 从当下起算 30 天免费试用
//   （调用方：Index.doLogin 登录回调 / Index.aboutToAppear 老用户补查 / BillingPage 登录按钮 / 边栏头像，
//   四处共用防逻辑漂移）
// ★ 0.293.0：新用户礼包不再随 stamp 同步直发（「先发后拉」时序洞=冷装重领 200w 根因）——
//   改挂云首拉完成回调 maybeGrantWelcomeAfterFirstPull（老账号重装由云端 welcomeGranted 拦截）；
//   本函数新增职责=账号切换检测（资产行隔离入口，见 detectAccountSwitchAndResetAssets）
export function stampFreeTrialOnLogin(subscription: SubscriptionStore): boolean {
  const account = connectHuaweiAccount();
  if (account.isLoggedIn) {
    detectAccountSwitchAndResetAssets(); // ★ 0.293.0：先于一切发放/同步合并（重置后闸门重开等新账号首拉）
    maybeShowSignInGuide(); // ★ 0.256.0：首登签到引导（挂此=四登录入口全覆盖；guideShown 只弹一次）
  }
  if (account.isLoggedIn && subscription.freeTrialStart === 0) {
    subscription.freeTrialStart = Date.now();
    return true; // ★ 0.195.0：首次打戳返回 true——调用方据此弹「30 天试用欢迎弹窗」（仅首登 1 次）
  }
  return false;
}

// ============================================================
// ★ 0.293.0：多账号切换资产行隔离（用户拍板：SP/充值包/等级/签到=账号级资产跟账号走，
//   绝不跟设备走；内容数据默认合并不动——华为实锤系统不做本地隔离，本地遗留会随
//   云同步合并上行带入新账号云端，资产行必须应用层自行隔离）
//   链路：stamp 检测 lastAccountMark 变化 → store 全量重置默认值（不改 key 不碰 Schema）
//   + RDB 资产行本地删除（deleteRowLocal 不传播）+ rowCache 清（防 flush diff 误判）
//   + 首拉闸门重开（防重置 0 值 LWW 压掉新账号云端资产）→ 等新账号云端下行对齐
// ============================================================
function detectAccountSwitchAndResetAssets(): void {
  const account = connectHuaweiAccount();
  const mark = account.unionID !== '' ? account.unionID : account.openID;
  if (mark === '' || account.lastAccountMark === mark) {
    if (mark !== '') {
      account.lastAccountMark = mark; // 首次登录（新装）落标记
    }
    return;
  }
  account.lastAccountMark = mark; // 换登新账号——落新标记后重置
  resetAccountAssetsOnAccountSwitch();
}

function resetAccountAssetsOnAccountSwitch(): void {
  const siyi = connectSiyiPoints();
  siyi.permanentSp = 0;
  siyi.bonusSp = 0;
  siyi.giftSp = 0;
  siyi.giftSpExpireAt = 0;
  siyi.welcomeGranted = false;
  siyi.consumedGiftSp = 0;
  siyi.consumedBonusSp = 0;
  siyi.consumedPermanentSp = 0;
  siyi.signedDates = '[]';
  siyi.milestoneStreakGranted = 0;
  siyi.iapPackages = '[]';
  connectStatistics().raw = '{"days":[]}';
  const signIn = connectSignIn();
  signIn.signDates = [];
  signIn.lastSignDate = '';
  signIn.streak = 0;
  signIn.maxStreak = 0;
  signIn.guideShown = false;
  signIn.makeupVouchers = 0;
  signIn.makeupGrantedLevel = 0;
  signIn.makeupDates = [];
  // RDB 资产行本地删除（仅本地——物理删行不传播云端）+ diff-cache 清
  deleteRowLocal('cfg:siyi-points');
  deleteRowLocal('cfg:stat-days');
  rowCache.delete('cfg:siyi-points');
  rowCache.delete('cfg:stat-days');
  // 首拉闸门重开：新账号云端下行 reconcile 完成前禁一切行上行（防重置 0 值 LWW 压掉新账号云端资产）
  connectCloudSyncArbiter().rowInitDone = false;
  // 等级桥复位（检测基线随新账号重建）
  const bridge = connectLevelUpBridge();
  bridge.lastLevel = 0;
  bridge.pendingLevel = 0;
  bridge.pendingMakeupGrant = 0;
  welcomeCheckDone = false; // 新账号重新走礼包判定（其云端无发放记录=其自己是新用户）
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
// ★ 0.248.0：司忆点（SP）资产体系——三池余额+新用户礼包+等级头衔（用户拍板商业方案 V2.1）
//   ★ 0.248.5：有效期全取消（用户拍板）——所有 SP 一经获得永久有效；对外口径统一「嘉奖 SP」
//     （禁「赠送」字样，见 UI_GUIDELINES 第十八章）；消耗顺序=先扣嘉奖（gift+bonus）→充能（permanent）
//   池语义：充能池=充值购买（永久）；嘉奖池=兑换码/签到/学习/新用户礼包（永久）；
//   赠送池字段（giftSp/giftSpExpireAt）按 Schema 铁律保留不再消费——旧到期戳自动作废（零迁移）
//   存储：PersistenceV2 全新 key（0.185 铁律：全新 key 无旧快照坑）
// ============================================================
@ObservedV2
export class SiyiPointStore {
  @Trace permanentSp: number = 0;         // 充能池（充值购买，永久；★ 0.248.7 起语义=发放累计，余额=发放-消耗）
  @Trace bonusSp: number = 0;             // 嘉奖池（兑换码/签到/学习，永久；★ 0.248.7 起语义=发放累计）
  @Trace giftSp: number = 0;              // 赠送池（新用户礼包入此池；0.248.5 起并入嘉奖口径展示、永久）
  @Trace giftSpExpireAt: number = 0;      // ★ 0.248.5 弃用（Schema 禁删；旧值不再被消费）
  @Trace welcomeGranted: boolean = false; // 新用户礼包已发放标记（一次性）
  // ★ 0.248.7 SP 消耗链路（尾部追加默认 0，Schema 铁律合规）——池改「发放累计」语义，
  //   三字段=对应池累计消耗（单调递增只增不减）：多端 max 合并单调自洽（发放/消耗都只增，
  //   余额=发放-消耗 永不回滚；双端并发消耗窗口 max 只取大者=少扣不回滚，对用户有利可接受）
  @Trace consumedGiftSp: number = 0;
  @Trace consumedBonusSp: number = 0;
  @Trace consumedPermanentSp: number = 0;
  // ★ 0.277.0 签到幂等标记下沉云端行（任务书方案 B——多端重复签到/里程碑重复发放根治）：
  //   signDates/lastSignDate/streak 本是本地数据不上云，换设备后签到状态清零可重复领；
  //   两字段随本行（cfg:siyi-points）max/并集合并多端收敛，doSignIn 签到前校验。
  //   存 String 字段而非数组（与 redeemedCodes 同款模式，规避旧快照缺字段坑——Schema 铁律尾部追加）
  @Trace signedDates: string = '[]';       // 已签到日期并集（JSON 数组 'YYYY-MM-DD'，保留最近 400 天）
  @Trace milestoneStreakGranted: number = 0; // 已发里程碑的最高连击档（max 合并单调递增，防跨端重发）
  // ★ 0.289.0 充能包账本（用户拍板：按包记账+购买顺序 FIFO 扣+包级退款）——JSON 数组字符串
  //   （同 signedDates 模式规避旧快照坑，Schema 尾部追加铁律）；池级 permanentSp/consumedPermanentSp
  //   保留=包级汇总（云同步 max 合并兼容、余额口径不变）；包级才是退款判定的唯一真相（cons===0=可退）
  @Trace iapPackages: string = '[]';
  // ★ 0.294.0 好奇宝宝新手任务（尾部追加，同 signedDates 模式规避旧快照坑）：done=已完成任务 id 并集
  //   （含未开云服务期间挂账完成的）；granted=已发放 SP 的任务 id 并集——两集合随本行（cfg:siyi-points）
  //   并集合并多端收敛；done−granted 差集=待发放（云服务开通后 settleRookieTasks 自动补发）
  @Trace rookieDoneJson: string = '[]';
  @Trace rookieGrantedJson: string = '[]';
}

export function connectSiyiPoints(): SiyiPointStore {
  return PersistenceV2.connect(SiyiPointStore, 'siyi-points-v1', () => new SiyiPointStore()) as SiyiPointStore;
}

// ============================================================
// ★ 0.289.0 充能包账本（按包记账/购买顺序 FIFO 扣/包级退款——用户政策三条：
//   ①嘉奖先扣 ②充能按购买顺序逐包扣 ③整包未消耗 1 点 SP=可退、花过=不可退，退款后台执行）
// ============================================================

// 充能包（plain class 非 @ObservedV2——@Trace 字段 stringify 不可枚举 0.205.4 铁律绕开）
export class IapPackage {
  tok: string = '';   // purchaseToken（新购全量 92 位；迁移包=历史记录截断前 8 位）
  pid: string = '';   // 商品 ID（dagai_sp200w / dagai_sp400w）
  amt: number = 0;    // 包额度 SP（200 万=2000000）
  ts: number = 0;     // 购买时间 epoch ms（迁移包=记录当日 00:00——旧账无几点几秒，如实展示）
  cons: number = 0;   // 该包累计消耗（FIFO；amt-cons=剩余；cons===0 且未退=可退）
  ref: number = 0;    // 0=正常 / 1=已退款已核销（剩余作废）
  frozenUntil: number = 0; // ★ 0.291.0 退款申请锁包截止 epoch ms（0=未锁；>now=冻结不可用；到期自动解锁=时间戳天然过期；云同步 max 单调自洽——续锁取大值，无解锁回退冲突）
}

// ★ 0.291.0 退款申请锁包时长（7 天——华为客服退款审核 1~3 天+缓冲；期间该包冻结防「申请中花光 SP」）
export const REFUND_FREEZE_MS: number = 7 * 24 * 60 * 60 * 1000;

export function parseIapPackages(raw: string): IapPackage[] {
  const out: IapPackage[] = [];
  try {
    const arr = JSON.parse(raw) as Record<string, Object>[];
    for (let i = 0; i < arr.length; i++) {
      const r = arr[i];
      const p = new IapPackage();
      const tok = r['tok'];
      const pid = r['pid'];
      if (typeof tok === 'string') {
        p.tok = tok;
      }
      if (typeof pid === 'string') {
        p.pid = pid;
      }
      p.amt = Number(r['amt'] ?? 0);
      p.ts = Number(r['ts'] ?? 0);
      p.cons = Number(r['cons'] ?? 0);
      p.ref = Number(r['ref'] ?? 0);
      p.frozenUntil = Number(r['frozenUntil'] ?? 0); // 旧账本缺字段=0 未锁（Schema 尾部追加默认值铁律）
      if (p.tok.length > 0 && p.amt > 0) {
        out.push(p);
      }
    }
  } catch (_e) {
    // 坏 JSON 当空账本（发放累计池级字段仍在，余额不受影响）
  }
  return out;
}

// ★ 0.290.2 一次性旧测试充能账写销（0.289.1「归零」方案实测失败根因=写减法违反 0.248.7 单调军令，
//   云同步 mergeSiyiPointsRow 下行 max 直接把云端旧值 600 万复活回本地；且触发条件「history 充能行」
//   首轮清零已删、purchaseHistory 不云同步永不复活=条件永久失效——181 账号实测 SP 一直 600 万）：
//   改用写销语义（writeOffRefundedPackage 同族）：permanentSp 不动，consumedPermanentSp 写满至
//   permanentSp → 余额=0 且发放/消耗双侧单调只增——上行覆盖云端后，任何端旧值顶回（600 万/0）在
//   max 合并下 600!>600、0!>600 均不覆盖，永不复活；迁移包同步写满 cons=amt（保留展示=已耗尽，
//   union 复活链上云端 cons 旧值 < 本地 amt，max 收敛到 amt 稳定）。
//   触发两路：A=包账本存在迁移包（tok<92 位截断=0.289.0 拆包特征）；B=充能池有余额+包账本空+
//   history 无「华为应用内支付」行（=纯 0.261 时代旧测试账，新购必建包+必留支付行，两路皆不误伤）。
//   iapConsumedTokens 保留（防同 token 回放重复入账）；purchaseHistory 不再动（账单页已不展示文本卡）。
//   ⚠️ 上线前必须删除本函数与全部调用点（stats-test-seed-v1 同款纪律）——正式用户花钱的充值账绝不能写销！
export function ensureIapPackagesMigrated(subscription: SubscriptionStore, store: SiyiPointStore): void {
  const pkgs = parseIapPackages(store.iapPackages);
  let hasUnwrittenLegacyPkg = false;
  for (let i = 0; i < pkgs.length; i++) {
    if (pkgs[i].tok.length < 92 && pkgs[i].cons < pkgs[i].amt) {
      hasUnwrittenLegacyPkg = true;
      break;
    }
  }
  let hasNewIapHistory = false;
  try {
    const history = JSON.parse(subscription.purchaseHistory) as string[];
    hasNewIapHistory = history.some((line: string): boolean => line.indexOf('华为应用内支付') >= 0);
  } catch (_e) {
    hasNewIapHistory = false;
  }
  const hasLegacyBalance = store.permanentSp > store.consumedPermanentSp;
  const pathA = hasUnwrittenLegacyPkg;
  const pathB = hasLegacyBalance && pkgs.length === 0 && !hasNewIapHistory;
  if (!pathA && !pathB) {
    return;
  }
  if (pathA) {
    for (let i = 0; i < pkgs.length; i++) {
      if (pkgs[i].tok.length < 92 && pkgs[i].cons < pkgs[i].amt) {
        pkgs[i].cons = pkgs[i].amt; // 迁移包写满=已耗尽（ref 不动——无真实退款语义）
      }
    }
    store.iapPackages = JSON.stringify(pkgs);
  }
  if (store.consumedPermanentSp < store.permanentSp) {
    store.consumedPermanentSp = store.permanentSp; // 池级写销：余额→0，单调只增军令
  }
  scheduleRowFlush();
}

// ★ 0.289.0 退款核销：华为侧已退款的包 → 剩余额度作废（cons 补满=消耗语义，发放累计只增军令不破坏）
//   + ref=1；池级 consumedPermanentSp 同步 +=（守恒：余额=发放-消耗 自洽）。
//   返回本轮作废 SP 额（0=token 未命中/已核销过——幂等）
export function writeOffRefundedPackage(store: SiyiPointStore, token: string): number {
  const list = parseIapPackages(store.iapPackages);
  let writtenOff = 0;
  for (let i = 0; i < list.length; i++) {
    const pkg = list[i];
    if (pkg.tok === token && pkg.ref !== 1) {
      const waste = Math.max(0, pkg.amt - pkg.cons);
      pkg.cons = pkg.amt;
      pkg.ref = 1;
      writtenOff += waste;
    }
  }
  if (writtenOff > 0) {
    store.consumedPermanentSp += writtenOff;
    store.iapPackages = JSON.stringify(list);
    scheduleRowFlush();
  }
  return writtenOff;
}

// ★ 0.291.0 退款申请锁包（用户拍板流程：app 内点申请退款 → 本地立即冻结该包 7 天防申请期间花光 SP
//   → 用户去华为侧申请（自助/客服 1~3 天）→ 成功=云端退款标记拉到后核销作废（writeOff 同族终态）；
//   失败=无事件推送，7 天到期自动解冻恢复可用（时间戳判过期即解锁，零额外状态）。
//   幂等：重复申请取更大 frozenUntil（max 语义与云同步合并同构）；tok 未命中返回 false
export function freezePackageUntil(store: SiyiPointStore, token: string, until: number): boolean {
  const list = parseIapPackages(store.iapPackages);
  for (let i = 0; i < list.length; i++) {
    if (list[i].tok === token && list[i].ref !== 1) {
      if (until > list[i].frozenUntil) {
        list[i].frozenUntil = until;
        store.iapPackages = JSON.stringify(list);
        scheduleRowFlush();
      }
      return true;
    }
  }
  return false;
}

// ★ 0.291.0 冻结包可用额（退款申请中包的账面可用 SP 合计）——可用余额口径的统一扣除项：
//   siyiTotalSp / 充能池扣费 / BillingPage 资产卡三处同源引用，防「展示可用但发消息余额不足」矛盾
export function frozenAvailableSp(store: SiyiPointStore): number {
  const now = Date.now();
  const list = parseIapPackages(store.iapPackages);
  let sum = 0;
  for (let i = 0; i < list.length; i++) {
    const pkg = list[i];
    if (pkg.frozenUntil > now && pkg.ref !== 1) {
      sum += Math.max(0, pkg.amt - pkg.cons);
    }
  }
  return sum;
}

// 司忆点总余额（三池合计；★ 0.248.5 有效期取消——giftSp 恒计入；
//   ★ 0.248.7 池语义升级=发放累计，余额=各池发放-各池消耗，clamp 0 防异常负数；
//   ★ 0.291.0 语义=**可用余额**——充能池扣除冻结包可用额（退款申请中不可用；全部调用方
//   皆扣费判断/实扣差额/bal 展示口径，无一需要账面总额，改此处即三处同源）
export function siyiTotalSp(store: SiyiPointStore): number {
  return Math.max(0, store.permanentSp - store.consumedPermanentSp - frozenAvailableSp(store))
    + Math.max(0, store.bonusSp - store.consumedBonusSp)
    + Math.max(0, store.giftSp - store.consumedGiftSp);
}

// ★ 0.248.7 SP 实扣（AI 回复完成按实扣口径结算）——消耗顺序=先嘉奖（gift→bonus）→充能（permanent，
//   0.248.5 军令）；只记累计消耗不回退发放值（云同步 max 合并下单调安全）；余额不足时扣到 0 为止；
//   返回是否扣到账（false=余额已为 0 一分未扣，调用方以此决定是否引导充值）
export function consumeSiyiSp(store: SiyiPointStore, amount: number): boolean {
  if (amount <= 0) {
    return true;
  }
  if (!siyiGateReady()) {
    return false; // ★ 0.293.0 gate 防御：云同步未就绪禁扣（UI 层 requireSiyiGate 已引导，此处兜底）
  }
  let remain = Math.min(amount, siyiTotalSp(store));
  if (remain <= 0) {
    return false;
  }
  const g = Math.min(remain, Math.max(0, store.giftSp - store.consumedGiftSp));
  store.consumedGiftSp += g;
  remain -= g;
  const b = Math.min(remain, Math.max(0, store.bonusSp - store.consumedBonusSp));
  store.consumedBonusSp += b;
  remain -= b;
  const p = Math.min(remain, Math.max(0, store.permanentSp - store.consumedPermanentSp - frozenAvailableSp(store)));
  if (p > 0) {
    store.consumedPermanentSp += p;
    // ★ 0.289.0 包 FIFO：按购买顺序（ts 升序=数组序）逐包扣、老包先扣（用户政策②）；
    //   已退款包（ref=1，cons 已补满）自然跳过；池级与包级同步累加守恒。
    //   包账本为空（迁移未跑）时只扣池级——迁移回放以 consumedPermanentSp 终值统一补包，最终一致
    //   ★ 0.291.0：冻结包（frozenUntil>now=退款申请中）跳过 FIFO——冻结期间该包 SP 不可用
    //   （池级余额照扣不误：池级金额不含冻结包可用额——见 siyiAvailableSp）
    const now = Date.now();
    const list = parseIapPackages(store.iapPackages);
    let left = p;
    for (let i = 0; i < list.length && left > 0; i++) {
      const pkg = list[i];
      if (pkg.frozenUntil > now) {
        continue; // 退款申请冻结中——不可扣
      }
      const avail = Math.max(0, pkg.amt - pkg.cons);
      const take = Math.min(left, avail);
      if (take > 0) {
        pkg.cons += take;
        left -= take;
      }
    }
    if (list.length > 0) {
      store.iapPackages = JSON.stringify(list); // 包账本为空（极端：迁移无据）只扣池级不丢账
    }
  }
  recordSpUsed(g + b + p); // ★ 0.259.0：SP 消耗统计埋点（单一收口——一切新扣点场景自动带上；实扣额才计）
  scheduleRowFlush(); // SP 变动防抖上行（cfg:siyi-points——多端一致）
  return true;
}

// ★ 0.259.0：SP 消耗按天统计（统计页第五卡数据源）——只累加已存在的当天行、绝不创建新行：
//   守住「行存在=当天有学习活动」不变式（learnDays=行数=等级头衔依据），杜绝纯消耗虚增
//   学习天数误触 Lv8 免扣的理论风险。实际场景 SP 消耗必伴随 AI 对话（userMsg 已建行），零丢失。
function recordSpUsed(amount: number): void {
  if (amount <= 0) {
    return;
  }
  const store = connectStatistics();
  const days = getStatDays(store);
  const key = statDateKey(Date.now());
  for (let i = 0; i < days.length; i++) {
    if (days[i].date === key) {
      days[i].spUsed = (days[i].spUsed ?? 0) + amount;
      store.raw = JSON.stringify({ days: days } as StatDayData);
      scheduleRowFlush(); // 统计落盘即防抖上行（cfg:stat-days——多端消耗数据一致）
      return;
    }
  }
  // 当天无行——不创建（learnDays 口径保护；丢一条统计可接受，等级数据安全优先）
}

// 等级头衔（0.249.0 八级表，用户 2026-10-18 拍板「司」系）：Lv1 好奇宝宝注册即得 / Lv2 司墨 7 / Lv3 司简 30 /
//   Lv4 司理 90 / Lv5 司微 150 / Lv6 司玄 210 / Lv7 司天 240 / Lv8 司忆令 365（一年封神，SP 永久免费）
// 累计口径=统计有学习活动的天数（StatisticsStore days 行数，cfg:stat-days 云同步多端一致）；等级中断保留头衔
export function siyiLevelTitle(learnDays: number): string {
  if (learnDays >= SIYI_LV8_DAYS) {
    return 'Lv8 司忆令';
  }
  if (learnDays >= 240) {
    return 'Lv7 司天';
  }
  if (learnDays >= 210) {
    return 'Lv6 司玄';
  }
  if (learnDays >= 150) {
    return 'Lv5 司微';
  }
  if (learnDays >= 90) {
    return 'Lv4 司理';
  }
  if (learnDays >= 30) {
    return 'Lv3 司简';
  }
  if (learnDays >= 7) {
    return 'Lv2 司墨';
  }
  return 'Lv1 好奇宝宝';
}

// Lv8 司忆令免扣判定（0.249.0，用户拍板「SP 永久免费」真免扣）——AI 回复实扣 0+余额闸门豁免；
// 与 siyiLevelTitle 同源同常量，learnDays=累计学习天数只增不减，达成后免扣状态永不回退
export const SIYI_LV8_DAYS = 365;

export function isSiyiSpFree(learnDays: number): boolean {
  return learnDays >= SIYI_LV8_DAYS;
}

// ★ 0.259.0：当前累计学习天数（=统计行数；余额展示判定用便捷收口）
export function currentLearnDays(): number {
  return getStatDays(connectStatistics()).length;
}

// ★ 0.259.0：Lv8 满级 SP 余额显示口径（用户拍板「给他填满，永远 999,999 封神爽感」）——
//   所有对用户可见的 SP 余额展示点统一走此函数：Lv8 态恒显 '999,999'；纯显示层——
//   真实余额字段/云同步/统计一律不动（免扣保证实际余额永不减少，显示不撒谎）
export function siyiBalanceDisplay(store: SiyiPointStore, learnDays: number): string {
  if (isSiyiSpFree(learnDays)) {
    return '999,999';
  }
  return siyiTotalSp(store).toLocaleString();
}

// ============================================================
// ★ 0.272.0：SP 计价常量与公式单一真相源（从 ChatPage 迁入——全场景 SP 透明化）
// ============================================================
// SP=token÷7×2，结果四舍五入无小数；÷7 刻意不整除防反推成本；界面永不出现 token 字样=商业铁律；
// 调价只改本处勿散落逻辑（原 ChatPage 模块级常量整体搬家，公式/数值零变化）
export const SP_TOKEN_DIVISOR: number = 7;
export const SP_COST_MULTIPLIER: number = 2;
// 价格倍数系数（腾讯云 DeepSeek-V4-Flash 实价：输入 1 元 / 命中 0.02 元=1/50 / 输出 4 元 每百万）
export const SP_INPUT_PRICE_RATIO: number = 1;     // 输入·未命中
export const SP_HIT_PRICE_RATIO: number = 0.02;    // 输入·缓存命中（未命中的 1/50）
export const SP_OUTPUT_PRICE_RATIO: number = 4;    // 输出（输入的 4 倍）
// 缓存节省展示系数：命中部分假如未命中本要按基准价扣，实扣仅 0.02 → 省 98%（1 − 0.02/1）
export const SP_CACHE_SAVING_RATIO: number = 0.98;

// ★ 0.272.0：SP 换算公共纯函数（原 ChatPage.spCostOf 内联公式抽出——查词/提炼/鼓励语等
//   全场景 AI 调用统一走此口径；展示与扣点同源军令：信息卡显示的数字=本函数输出=实扣值）
export function spCostOfTokens(inputTokens: number, outputTokens: number, cachedTokens: number): number {
  const hit = Math.min(cachedTokens, inputTokens);
  const miss = inputTokens - hit;
  const inSp = Math.round((miss * SP_INPUT_PRICE_RATIO + hit * SP_HIT_PRICE_RATIO) / SP_TOKEN_DIVISOR * SP_COST_MULTIPLIER);
  const outSp = Math.round(outputTokens * SP_OUTPUT_PRICE_RATIO / SP_TOKEN_DIVISOR * SP_COST_MULTIPLIER);
  return inSp + outSp;
}

// ★ 0.279.0：云端 TTS 播报 SP 计价（音频输出维度——感叹号明细卡补音频行+播报实扣同源）。
//   本机语音引擎（CoreSpeechKit）与小艺输入法语音转文字（音频输入）免费零扣；
//   云端合成（火山/千问/自定义）按字符计费：对齐云端语音合成实价区间折算 SP + 华为抽成
//   冗余（同 token ×2 口径）；缓存命中重播零请求零计费（0.256.1）。调价改此一处。
export const SP_TTS_PER_KCHAR: number = 100;

// 云端 TTS 消耗换算（千字符→SP，向上取整，最低 1——展示与扣点同源军令）
export function spCostOfTts(chars: number): number {
  if (chars <= 0) {
    return 0;
  }
  return Math.max(1, Math.ceil(chars / 1000 * SP_TTS_PER_KCHAR));
}

// ★ 0.291.2：文档解析页费嫁接（用户拍板「成本嫁接到输入 SP」）——腾讯多模态文档解析
//   0.04 元/页 → 按 DeepSeek 输入价（2 元/百万 token）折算等效 input token：
//   0.04 ÷ 2 × 1,000,000 = 20,000 token/页；等效 token 并入本次请求 inputTokens 总账，
//   走 spCostOfTokens 同源公式一次实扣（展示=扣费同源军令天然满足）；解析失败=零页零扣。
//   调价改此一处（腾讯资源包量大单价更低，保守取 0.04 上限价）。
export const DOC_TOKENS_PER_PAGE: number = 20000;

// 页数 → 等效 input token（用于发送链 onDone 落账前并入 inputTokens）
export function docPageTokens(pages: number): number {
  if (pages <= 0) {
    return 0;
  }
  return Math.round(pages * DOC_TOKENS_PER_PAGE);
}

// ★ 0.272.0：sp_consume 埋点公共函数（原 ChatPage.trackSpConsume 抽出——chat/regen 之外的
//   新场景 word/extract/encourage_r/encourage_s 复用；免扣账号照报 f:y，成本红线要真实 token/命中/余额）
// ★ 0.273.0：尾加 outputTokens/mid 两参（默认值=既有调用点零波及）；p 尾加 it/ot/ct/ld 四字段
//   （毛利成本侧数据源：it=总输入（含命中，看板按 (it−ct)×输入价 折算）/ot=输出（含思考）/
//    ct=缓存命中/ld=累计学习天数）；mid=关联消息 ID（隐式场景对账，空不写）
export function trackSpConsumeAuto(model: string, free: boolean, actualSp: number,
  inputTokens: number, cachedTokens: number, scene: string,
  outputTokens: number = 0, mid: string = ''): void {
  const p: Record<string, string> = {};
  p['sp'] = `${actualSp}`;
  p['m'] = model;
  p['sc'] = scene; // chat=发送 / regen=重生成 / word=查词 / extract=提炼 / encourage_r=复习鼓励 / encourage_s=统计鼓励 /
  // rerank=AI排序 / profile=画像观察 / summary=分支摘要（★ 0.273.0 隐式三件套翻案实扣）
  p['f'] = free ? 'y' : 'n';
  p['bal'] = `${siyiTotalSp(connectSiyiPoints())}`;
  p['h'] = `${inputTokens > 0 ? Math.round(cachedTokens * 100 / inputTokens) : 0}`;
  p['it'] = `${inputTokens}`;
  p['ot'] = `${outputTokens}`;
  p['ct'] = `${Math.min(cachedTokens, inputTokens)}`;
  p['ld'] = `${currentLearnDays()}`;
  if (mid.length > 0) {
    p['mid'] = mid;
  }
  trackUidAuto('sp_consume', p);
}

// ★ 0.273.0：隐式调用（rerank/profile/summary）实扣收口——只在 onDone 成功路径调用
//   （失败/取消/超时零扣费铁律：onError/timeout 分支禁调）；翻 0.265.0 Q1「隐式暂不扣」旧案
//   （用户拍板「要扣啊，加到总账」）；Lv8 司忆令免扣照报 f:y；余额不足 clamp 0（0.248.7 先例）；
//   展示与扣点同源=spCostOfTokens 同公式；用户端不单展示（并入总账，D2 展示边界）
// 纯核心（hypium 可测——不动 connect 单例）：返回实扣额（免扣=0；不足=clamp 后实际值）
export function consumeImplicitSpCore(store: SiyiPointStore, free: boolean, cost: number): number {
  if (free) {
    return 0; // Lv8 司忆令：一分不扣（f:y 由调用方上报）
  }
  const bal0 = siyiTotalSp(store);
  consumeSiyiSp(store, cost);
  return bal0 - siyiTotalSp(store);
}

export function consumeImplicitSp(scene: string, model: string, mid: string,
  inputTokens: number, outputTokens: number, cachedTokens: number): void {
  const store = connectSiyiPoints();
  const free = isSiyiSpFree(currentLearnDays());
  const cost = spCostOfTokens(inputTokens, outputTokens, cachedTokens);
  const actual = consumeImplicitSpCore(store, free, cost);
  trackSpConsumeAuto(model, free, actual, inputTokens, cachedTokens, scene, outputTokens, mid);
}

// ★ 0.273.0：app_daily 日活埋点 ld 注入（模块级一次性注入——惰性调用，currentLearnDays 在
//   maybeTrackDaily 真正发 app_daily 时才执行；TrackUtil→ChatModel 反向依赖由此断路）
setDailyLdProvider((): number => currentLearnDays());

// 新用户礼包分档（用户 2026-10-18 拍板）：上线首月注册=200 万（≈免费畅用一月）；次月起新用户=100 万
// ⚠️ SIYI_FIRST_MONTH_END 为首月截止占位——上线时间确定后更新此常量即可
export const SIYI_FIRST_MONTH_END: number = new Date(2026, 10, 30, 23, 59, 59).getTime();
export const SIYI_WELCOME_FIRST_MONTH: number = 2000000;
export const SIYI_WELCOME_NORMAL: number = 1000000;


// 新用户礼包发放（一次性）：★ 0.293.0 改「云下行后发放」——唯一合法触发点=首拉完成回调
//   maybeGrantWelcomeAfterFirstPull（云端 cfg:siyi-points 行已对齐：老账号重装由云端
//   welcomeGranted=true 拦截不重发；云端无行/无标记=真新用户此刻才发）。
//   返回发放额（0=未发——gate 未就绪/已发过）；发放即由调用方弹仪式感弹窗（用户拍板）。
export function grantSiyiWelcomeBonus(store: SiyiPointStore): number {
  if (!siyiGateReady()) {
    return 0; // ★ 0.293.0 gate 防御：云同步未就绪绝不发放（挂起等首拉完成）
  }
  if (store.welcomeGranted) {
    return 0;
  }
  store.welcomeGranted = true;
  const amount = Date.now() < SIYI_FIRST_MONTH_END ? SIYI_WELCOME_FIRST_MONTH : SIYI_WELCOME_NORMAL;
  store.giftSp += amount;
  // ★ 0.248.5：有效期取消——不再设置 giftSpExpireAt（礼包永久）
  scheduleRowFlush(); // ★ 0.248.4：SP 变动防抖上行（cfg:siyi-points——多端余额一致）
  const _gp: Record<string, string> = {}; // ★ 0.260.0：sp_grant 埋点（发放收口单一挂点）
  _gp['src'] = 'welcome';
  _gp['sp'] = `${amount}`;
  _gp['bal'] = `${siyiTotalSp(store)}`;
  trackUidAuto('sp_grant', _gp);
  return amount;
}

// ★ 0.293.0：新用户礼包首拉判定（挂 reconcileWithRows 闸门开启点——会话级判一次）：
//   首拉完成=云端账本已对齐，此刻 welcomeGranted 仍 false 即真新用户 → 发放+弹窗仪式感；
//   未登录保持待判（登录后下轮 reconcile 补判）；老账号重装被云端标记拦截（Bug A 根治本体）
let welcomeCheckDone: boolean = false;
function maybeGrantWelcomeAfterFirstPull(): void {
  if (welcomeCheckDone) {
    return;
  }
  if (!connectHuaweiAccount().isLoggedIn) {
    return; // 未登录不判不发——登录后的 forceCloudSyncNow→reconcile 会再进本函数
  }
  const siyi = connectSiyiPoints();
  if (siyi.welcomeGranted) {
    welcomeCheckDone = true; // 云端已置位（老账号）或本会话已发——判定完结
    return;
  }
  welcomeCheckDone = true;
  const amount = grantSiyiWelcomeBonus(siyi);
  if (amount <= 0) {
    return;
  }
  const dlg = connectConfirmDialog();
  dlg.welcomeBonusAmount = amount;
  dlg.welcomeBonusVisible = true; // 仪式感弹窗：明示赠送，绝不后台默默到账
}

// ============================================================
// ★ 0.256.0：签到体系（需求正本已归档 docs/0.256.0；此前仅文案无功能本体）
//   口径（用户 2026-10-19 拍板）：连签奖励递增封顶——第 1 天 2,000，每天 +1,000，
//   第 7 天起 8,000/天封顶；里程碑额外奖励 7/30/100 天 → +10,000/+50,000/+200,000
//   （断签后重新连满再发；maxStreak 只记最高不阻断）。发放一律入 bonusSp 嘉奖池。
//   存储：PersistenceV2 全新 key 'sign-in-v1'（本地——重装清沙箱=首登引导天然复现，丙方案定案）
// ============================================================
@ObservedV2
export class SignInStore {
  @Trace signDates: string[] = [];    // 已签到日期集合 'YYYY-MM-DD'（本地自然日）
  @Trace lastSignDate: string = '';   // 最后签到日
  @Trace streak: number = 0;          // 当前连击天数
  @Trace maxStreak: number = 0;       // 历史最高连击
  @Trace guideShown: boolean = false; // 首登签到引导弹窗已展示标志（只弹一次）
  @Trace autoShownDate: string = ''; // ★ 0.294.0 尾部追加：每日首开自动弹签到窗去重标志（'YYYY-MM-DD'，当日已自动弹过不再弹）
  // ★ 0.259.0 补签券（升级奖励制，尾部追加默认值——Schema 铁律合规；本地不同步=与连击本地语义一致）
  @Trace makeupVouchers: number = 0;      // 持有券数
  @Trace makeupGrantedLevel: number = 0;  // 已发券等级基线（防重复发放）
  @Trace makeupDates: string[] = [];      // 已补签日期（防同一日重复补签）
}

export function connectSignIn(): SignInStore {
  return PersistenceV2.connect(SignInStore, 'sign-in-v1', () => new SignInStore()) as SignInStore;
}

// ★ 0.256.0：日期偏移调试开关（AppStorageV2 应用级、默认 0=正常用户零影响）——
//   签到/连击涉及「今天」统一走此偏移，测试连签 7 天/断签/里程碑不真等时间；
//   入口=签到弹窗底部日期小字长按（bindContextMenu，触屏长按/PC 右键双通道）
@ObservedV2
export class DebugDayOffsetStore {
  @Trace offset: number = 0;
}

export function connectDebugDayOffset(): DebugDayOffsetStore {
  return AppStorageV2.connect(DebugDayOffsetStore, 'debug-day-offset',
    () => new DebugDayOffsetStore()) as DebugDayOffsetStore;
}

// 签到弹窗触发桥（AppStorageV2 应用级共享；挂载点唯一=Index 根 Stack——AppConfirmDialog 同款模式）
@ObservedV2
export class SignInDialogBridge {
  @Trace visible: boolean = false;
}

export function connectSignInDialog(): SignInDialogBridge {
  return AppStorageV2.connect(SignInDialogBridge, 'sign-in-dialog',
    () => new SignInDialogBridge()) as SignInDialogBridge;
}

// 本地自然日字符串（YYYY-MM-DD）+ 调试偏移天——需求 §5.1：统一 getFullYear/getMonth/getDate
//   拼 串比较，不用 Date.now() 直比（防时区/时分秒误差）
export function todayStrWithOffset(offsetDays: number): string {
  const d = new Date(Date.now() + offsetDays * 86400000);
  return `${d.getFullYear()}-${`${d.getMonth() + 1}`.padStart(2, '0')}-${`${d.getDate()}`.padStart(2, '0')}`;
}

// 日期字符串平移（本地时间构造防 UTC 偏移）：'2026-10-19' + (-1) = '2026-10-18'
function shiftDateStr(dateStr: string, deltaDays: number): string {
  const parts = dateStr.split('-');
  const d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]) + deltaDays);
  return `${d.getFullYear()}-${`${d.getMonth() + 1}`.padStart(2, '0')}-${`${d.getDate()}`.padStart(2, '0')}`;
}

// 连击推导（纯函数）：昨天签过=连击+1；否则（间断/首签）归 1
export function nextStreak(lastSignDate: string, streak: number, today: string): number {
  if (lastSignDate !== '' && shiftDateStr(today, -1) === lastSignDate) {
    return streak + 1;
  }
  return 1;
}

// ============================================================
// ★ 0.277.0：签到状态跨端共享纯函数组（任务书方案 B——幂等标记下沉 cfg:siyi-points）
// ============================================================
// 云端已签日期保留窗口（天）：100 天里程碑最多需 100 天连续记录，400 窗口充裕；
//   一年 365 项 JSON 约 4KB，RDB value 承载无碍（截断控体积）
export const SIGNED_DATES_KEEP: number = 400;
// 已签日期 JSON 解析（坏值/undefined 兜底空数组——旧云端行缺字段天然兼容）
export function parseSignedDates(json: string | undefined): string[] {
  if (json === undefined || json === '') {
    return [];
  }
  try {
    const arr: string[] = JSON.parse(json) as string[];
    return Array.isArray(arr) ? arr : [];
  } catch (_e) {
    return [];
  }
}

// 日期并集合并（纯函数）：去重→字典序排序（YYYY-MM-DD 字典序=时间序）→截断保留最近 N 天
export function mergeSignedDates(a: string[], b: string[]): string[] {
  const set = new Set<string>();
  for (let i = 0; i < a.length; i++) {
    set.add(a[i]);
  }
  for (let i = 0; i < b.length; i++) {
    set.add(b[i]);
  }
  const sorted = Array.from(set).sort();
  return sorted.length > SIGNED_DATES_KEEP ? sorted.slice(sorted.length - SIGNED_DATES_KEEP) : sorted;
}

// 从日期集合推导连击（纯函数）：以 today 为锚（today 须已在集合中）向前逐日连续计数——
//   PC 冷启动本地 streak 归零也能从云端并集接着数（任务书验收 3：手机签 3 天→PC 接着签第 4 天）
export function streakFromSignedDates(dates: string[], today: string): number {
  const set = new Set<string>();
  for (let i = 0; i < dates.length; i++) {
    set.add(dates[i]);
  }
  let n = 0;
  let cur = today;
  while (set.has(cur)) {
    n++;
    cur = shiftDateStr(cur, -1);
  }
  return n;
}

// 每日签到奖励（纯函数）——连签递增：第 N 天 = min(2000 + (N-1)×1000, 8000)，第 7 天起封顶
export function signInRewardSp(streak: number): number {
  const n = Math.max(1, streak);
  return Math.min(2000 + (n - 1) * 1000, 8000);
}

// 连签里程碑额外奖励（纯函数）——正好达到 7/30/100 天当天发放；断签重连再满再发
export function milestoneBonusSp(streak: number): number {
  if (streak === 100) {
    return 200000;
  }
  if (streak === 30) {
    return 50000;
  }
  if (streak === 7) {
    return 10000;
  }
  return 0;
}

// 今日是否已签（读取统一走调试偏移）
// ★ 0.293.0 双查口径统一：本地 signDates ∪ 云端 siyi.signedDates——修复「手机显示可签但点击
//   无反应」（UI 判定只查本地 vs doSignIn 幂等查本地∪云端口径分裂，跨设备签到 UI 状态相反的根因）
export function isSignedToday(store: SignInStore): boolean {
  const today = todayStrWithOffset(connectDebugDayOffset().offset);
  if (store.signDates.indexOf(today) >= 0) {
    return true;
  }
  return parseSignedDates(connectSiyiPoints().signedDates).indexOf(today) >= 0;
}

// 签到执行（完整链：防重复→连击→发 SP→云上行；today 由调用方统一走 todayStrWithOffset 传入——
//   显式参数化=纯函数可测）：返回本次发放总额（0=今日已签未发）
//   里程碑与当日奖励一并入 bonusSp 嘉奖池（scheduleRowFlush 走 cfg:siyi-points 同款上行）
//   ★ 0.277.0 多端幂等（任务书方案 B）：幂等/连击/里程碑三处改查云端标记（siyi.signedDates 并集 +
//   milestoneStreakGranted 档位）——换设备本地清零不再重复发放/重新数连击/重发里程碑
export function doSignIn(store: SignInStore, siyi: SiyiPointStore, today: string): number {
  // ★ 0.293.0 gate 防御：云同步未就绪禁签（签到增发 SP 必须账本云端对齐；UI 层 requireSiyiGate 已引导）
  if (!siyiGateReady()) {
    return 0;
  }
  // 幂等：本地记录 ∪ 云端记录（云端拦跨设备同日重复签到→sp_grant 埋点天然不再多报）
  if (store.signDates.indexOf(today) >= 0
    || parseSignedDates(siyi.signedDates).indexOf(today) >= 0) {
    return 0;
  }
  // 连击取双链路最大值：本地续接链路（nextStreak——保留 0.259.0 补签「断签前+1 续接」语义）
  //   与云端日期并集日历推导（streakFromSignedDates——PC 冷启动接着手机的连击数）；
  //   ⚠️ 本地链路须用更新前的 lastSignDate/streak 计算（推到 today 后昨天比较恒 false）
  const localNext = nextStreak(store.lastSignDate, store.streak, today);
  store.signDates.push(today);
  store.lastSignDate = today;
  const dates = mergeSignedDates(store.signDates, parseSignedDates(siyi.signedDates));
  store.streak = Math.max(localNext, streakFromSignedDates(dates, today));
  if (store.streak > store.maxStreak) {
    store.maxStreak = store.streak;
  }
  // 云端签到标记双写（本地 SignInStore.signDates 保留全量供 UI 红点/弹窗展示用）
  siyi.signedDates = JSON.stringify(dates);
  // 里程碑：达到节点 && 高于云端已发档才发（换设备重新数到同档不再重发）
  let milestone = 0;
  if (store.streak > siyi.milestoneStreakGranted) {
    milestone = milestoneBonusSp(store.streak);
    if (milestone > 0) {
      siyi.milestoneStreakGranted = store.streak;
    }
  }
  const total = signInRewardSp(store.streak) + milestone;
  siyi.bonusSp += total;
  scheduleRowFlush(); // SP 变动防抖上行（cfg:siyi-points——多端余额+签到标记一致）
  const _sg: Record<string, string> = {}; // ★ 0.260.0：sp_grant 埋点（签到发放）
  _sg['src'] = 'sign';
  _sg['sp'] = `${total}`;
  _sg['bal'] = `${siyiTotalSp(siyi)}`;
  trackUidAuto('sp_grant', _sg);
  return total;
}

// ★ 0.288.0：嘉奖 SP 发放统一收口（性格测试等一次性奖励场景；签到仍走 doSignIn 不改）——
//   发放入 bonusSp 嘉奖池 + 云上行防抖（cfg:siyi-points）+ sp_grant 埋点，与 doSignIn 同款三件套
export function grantBonusSp(siyi: SiyiPointStore, amount: number, src: string): boolean {
  // ★ 0.294.0 起返回 boolean：true=已发放；false=被拦截/零额——调用方（claimQuizSp 等）据此
  //   决定幂等标记是否置位，gate 未就绪时不置位、后续可自然补发（挂账语义的前提）
  if (amount <= 0) {
    return false;
  }
  if (!siyiGateReady()) {
    return false; // ★ 0.293.0 gate 防御：一切 SP 发放口（签到/性格测试/未来做题奖励）未就绪不发
  }
  siyi.bonusSp += amount;
  scheduleRowFlush();
  const p: Record<string, string> = {};
  p['src'] = src;
  p['sp'] = `${amount}`;
  p['bal'] = `${siyiTotalSp(siyi)}`;
  trackUidAuto('sp_grant', p);
  return true;
}

// ★ 0.294.0 每日首开自动弹签到（用户拍板：自然时间 0 点后第一次打开 app 且今日未签 → 自动弹；
//   ★ SP 云服务铁律：仅云服务开通（SiyiGate ready）才弹——没网/没云同步一律不弹，不置去重标志）
export function maybeAutoShowSignIn(): void {
  if (!siyiGateReady()) {
    return; // 云服务未就绪：不弹（且不消耗当日去重——开通后同日仍可弹）
  }
  const store = connectSignIn();
  if (isSignedToday(store)) {
    return; // 今日已签（本地∪云端双查口径）
  }
  const today = todayStrWithOffset(connectDebugDayOffset().offset);
  if (store.autoShownDate === today) {
    return; // 今日已自动弹过
  }
  store.autoShownDate = today; // 弹即置标志（每日最多自动弹一次）
  connectSignInDialog().visible = true;
}

// 首登签到引导判定（丙方案）：从未引导过 && 从未签过 && 登录态已建立 → 弹一次并打标志。
//   卸载重装清 PersistenceV2 沙箱 → guideShown 清零 → 重装后首次登录必弹（验收标准）。
//   挂 stampFreeTrialOnLogin 内=四登录入口全覆盖（Index.doLogin/Index 补查/BillingPage/边栏头像，0.217.2 铁律）
function maybeShowSignInGuide(): void {
  const store = connectSignIn();
  if (store.guideShown || store.signDates.length > 0) {
    return; // 已引导过（或异常防御：签过必已引导）
  }
  const account = connectHuaweiAccount();
  if (!account.isLoggedIn) {
    return;
  }
  store.guideShown = true; // 弹即置标志——只弹一次
  connectSignInDialog().visible = true;
}

// ============================================================
// ★ 0.259.0：补签券（升级奖励制，用户拍板每级 +1）——因努力升级而奖励的券，非购买
//   阶梯：Lv2 司墨 1 张 / Lv3 司简 2 / Lv4 司理 3 / Lv5 司微 4 / Lv6 司玄 5 / Lv7 司天 6；
//   Lv8 司忆令不另送券——满级专属权益=SP 显示恒 999,999（§3.6）
//   使用：只补「昨天」（唯一补签日最简防刷），断签前 streak+1 续接（后悔药语义）
// ============================================================

// 等级应得券总额（纯函数）：Lv1=0 / Lv2~Lv7=等级-1 / Lv8 及以上=6（不随 Lv8 增发）
export function makeupVouchersForLevel(level: number): number {
  if (level >= 7) {
    return 6;
  }
  if (level >= 2) {
    return level - 1;
  }
  return 0;
}

// 升级发券（notifyLevelUp 单一收口内调用）：补齐「新等级应得总额−已发基线」（跳级自动补差）
function grantMakeupVouchers(newLevel: number): number {
  const store = connectSignIn();
  const grant = makeupVouchersForLevel(newLevel) - makeupVouchersForLevel(store.makeupGrantedLevel);
  if (grant > 0) {
    store.makeupVouchers += grant;
  }
  store.makeupGrantedLevel = Math.max(store.makeupGrantedLevel, newLevel);
  return grant;
}

// 断签可补判定（弹窗展示补签按钮依据）：今天未签 && 昨天未签 && 昨天未补过 && 持有券>0
export function canMakeupYesterday(store: SignInStore, today: string): boolean {
  if (store.makeupVouchers <= 0 || store.signDates.indexOf(today) >= 0) {
    return false;
  }
  const yesterday = shiftDateStr(today, -1);
  return store.signDates.indexOf(yesterday) < 0 && store.makeupDates.indexOf(yesterday) < 0;
}

// 使用补签券（只补昨天）：昨天记入已签+已补集合，streak=断签前 streak+1（续接不重新计数），
//   lastSignDate 推到昨天（今天再签到 nextStreak 自然 +1）；today 由调用方走 todayStrWithOffset 传入
export function useMakeupVoucher(store: SignInStore, today: string): boolean {
  if (!canMakeupYesterday(store, today)) {
    return false;
  }
  const yesterday = shiftDateStr(today, -1);
  store.makeupVouchers -= 1;
  store.makeupDates.push(yesterday);
  store.signDates.push(yesterday);
  store.streak += 1; // 续接语义：断签前 streak（字段保留历史值）+1
  if (store.streak > store.maxStreak) {
    store.maxStreak = store.streak;
  }
  store.lastSignDate = yesterday; // 今天再签到 nextStreak(yesterday, streak, today)=streak+1
  return true;
}

// ============================================================
// ★ 0.256.0：称号升级检测（头衔此前静默变化，补升级提醒弹窗）
//   桥=AppStorageV2 应用级（lastLevel 基线 + pendingLevel 待展示）；
//   检测点=recordStat（本端学习落盘）+ mergeStatDaysRow（云下行天数吸收）两路；
//   冷启动基线静默同步不弹——升级只可能发生在「本次会话学习/云下行」时刻（符合需求 §7）
// ============================================================
@ObservedV2
export class LevelUpBridge {
  @Trace lastLevel: number = 0;    // 已通知等级基线（0=未初始化）
  @Trace pendingLevel: number = 0; // 待展示升级弹窗等级（>0 即弹，关闭清零）
  @Trace pendingMakeupGrant: number = 0; // ★ 0.259.0：本次升级发放补签券数（升级弹窗「获得补签券 ×N」）
}

export function connectLevelUpBridge(): LevelUpBridge {
  return AppStorageV2.connect(LevelUpBridge, 'level-up-bridge',
    () => new LevelUpBridge()) as LevelUpBridge;
}

// 头衔数值化（纯函数，1~8）——与 siyiLevelTitle 同阈值单一真相源
export function siyiLevelOf(learnDays: number): number {
  if (learnDays >= SIYI_LV8_DAYS) {
    return 8;
  }
  if (learnDays >= 240) {
    return 7;
  }
  if (learnDays >= 210) {
    return 6;
  }
  if (learnDays >= 150) {
    return 5;
  }
  if (learnDays >= 90) {
    return 4;
  }
  if (learnDays >= 30) {
    return 3;
  }
  if (learnDays >= 7) {
    return 2;
  }
  return 1;
}

// 等级权益文案（升级弹窗展示）——与 GlobalSettingsDialog 八级表充能/嘉奖两列同源
//   （⚠️ 双份维护：GSD 表改文案时此处同步；GSD 为规则展示真相源）
export const SIYI_LEVEL_PERKS: string[] = [
  '基础嘉奖',
  '嘉奖 +5%',
  '嘉奖 +10% · 充能 98 折',
  '嘉奖 +15% · 充能 96 折',
  '嘉奖 +20% · 充能 94 折',
  '嘉奖 +25% · 充能 90 折',
  '嘉奖 +30% · 充能 85 折',
  'AI 对话 SP 永久免费 · 余额恒显 999,999', // ★ 0.259.0 补满级显示口径
];

// 等级头衔文案（按等级数值取用）——与 siyiLevelTitle 八级表同源（⚠️ 双份维护，siyiLevelTitle 为真相源）
export const SIYI_LEVEL_TITLES: string[] = [
  'Lv1 好奇宝宝',
  'Lv2 司墨',
  'Lv3 司简',
  'Lv4 司理',
  'Lv5 司微',
  'Lv6 司玄',
  'Lv7 司天',
  'Lv8 司忆令',
];

// 等级升级通知：learnDays 变化后调用——首次建立基线（静默），升级置 pendingLevel 触发弹窗
export function notifyLevelUp(learnDays: number): void {
  const bridge = connectLevelUpBridge();
  const level = siyiLevelOf(learnDays);
  if (bridge.lastLevel === 0) {
    bridge.lastLevel = level; // 冷启动/首检基线——不弹（老用户登录即 Lv8 也不打扰）
    // ★ 0.259.0：冷启动基线同步发券基线（不发券——防历史数据升级误发/重复追发）；
    //   APP 未上线无存量用户，此为防御性对齐（盘值更高时保留盘值——多端 stat-days 吸收场景）
    const signIn = connectSignIn();
    if (signIn.makeupGrantedLevel < level) {
      signIn.makeupGrantedLevel = level;
    }
    return;
  }
  if (level > bridge.lastLevel) {
    bridge.lastLevel = level;
    bridge.pendingMakeupGrant = grantMakeupVouchers(level); // ★ 0.259.0：升级发券（阶梯补差；Lv8 返 0 不展示）
    bridge.pendingLevel = level; // 触发 Index 根挂载弹窗
  }
}

// ============================================================
// ★ 0.195.0：到期提醒引擎（付费转化·用户定稿）
//   最后 7 天（7/6/5/4/3/2/1）每日首开弹 1 次 + 过期后不再打扰（★ 0.248.1：首登欢迎弹窗已移除）
//   状态存 reminderState 单 JSON 字符串字段（0.143 教训：往类加字段旧快照坑——parse 全兜底）
// ============================================================
class ReminderState {
  last: string = '';        // 最近一次倒计时提醒日期 'YYYY-MM-DD'（每日去重）
}

function parseReminderState(store: SubscriptionStore): ReminderState {
  try {
    const s = JSON.parse(store.reminderState) as ReminderState;
    const st = new ReminderState();
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


// ★ 0.248.0：兑换码奖励=100 万嘉奖 SP（用户拍板；200 个码与 SHA256 白名单不变；旧 +90 天会员逻辑作废）
export const SIYI_REDEEM_SP: number = 1000000;

// ★ 0.194.0：兑换码——0.248.0 起写入 100 万嘉奖 SP（入 bonusSp 永久池；码唯一性/防重用不变）
export function redeemCode(store: SubscriptionStore, code: string, siyi: SiyiPointStore): boolean {
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
  // ★ 0.248.0：入嘉奖池（永久；消耗顺序=★ 0.248.5 先扣嘉奖→充能，由消耗链路执行）
  siyi.bonusSp += SIYI_REDEEM_SP;
  // 记账（文案不泄露兑换码权益构成——用户拍板「不让用户知道兑换码能获得什么」）
  let history: string[] = [];
  try {
    history = JSON.parse(store.purchaseHistory) as string[];
  } catch (_e) {
    history = [];
  }
  history.push(`兑换码 ${code.substring(0, 4)}****｜+${SIYI_REDEEM_SP / 10000} 万司忆点｜${new Date().toLocaleDateString()}`);
  store.purchaseHistory = JSON.stringify(history);
  scheduleRowFlush(); // ★ 0.248.4：SP 变动防抖上行（cfg:siyi-points——多端余额一致）
  const _rd: Record<string, string> = {}; // ★ 0.260.0：sp_grant 埋点（兑码发放）
  _rd['src'] = 'redeem';
  _rd['sp'] = `${SIYI_REDEEM_SP}`;
  _rd['bal'] = `${siyiTotalSp(siyi)}`;
  trackUidAuto('sp_grant', _rd);
  return true;
}

// ============================================================
// ★ 0.261.0：IAP 支付到账（华为应用内购买 SP 充能；API 封装在 utils/IapUtil.ets）
//   充能池=permanentSp（发放累计语义 0.248.7，单调只增——与云同步 max 合并天然一致，禁止减法）
// ============================================================

// IAP 商品 ID（AGC 后台配置，2026-10-19 就绪：两档均为消耗型）
export const IAP_PRODUCT_SP_200W: string = 'dagai_sp200w'; // 200 万 SP / ¥9.9
export const IAP_PRODUCT_SP_400W: string = 'dagai_sp400w'; // 400 万 SP / ¥19

// IAP 商品 → SP 额度映射（未知商品返回 0=拒到账）
export function iapSpAmountOf(productId: string): number {
  if (productId === IAP_PRODUCT_SP_200W) {
    return 2000000;
  }
  if (productId === IAP_PRODUCT_SP_400W) {
    return 4000000;
  }
  return 0;
}

// IAP 到账（幂等）：purchaseToken 已入集合拒到账；到账+记 token 同帧原子完成——
//   finishPurchase 失败不丢防线（补单链路再入时 token 已记，grant 幂等挡双入账）
// ★ 0.273.0：尾加 amountCny（实际成交价 ¥ 字符串如 '9.90'）——sp_grant iap 行补 amt/pid 两字段
//   （毛利收入侧数据源；InAppPurchaseData.price 单位分，调用方换算；空串=看板按 0 并标注）
export function grantSiyiSpFromIap(subscription: SubscriptionStore, siyi: SiyiPointStore,
  productId: string, purchaseToken: string, amountCny: string = ''): boolean {
  const amount = iapSpAmountOf(productId);
  if (amount <= 0 || purchaseToken.length === 0) {
    return false; // 未知商品/脏凭据拒到账
  }
  let tokens: string[] = [];
  try {
    tokens = JSON.parse(subscription.iapConsumedTokens) as string[];
  } catch (_e) {
    tokens = [];
  }
  if (tokens.indexOf(purchaseToken) >= 0) {
    return false; // 幂等——已入账 token 拒双发
  }
  tokens.push(purchaseToken);
  subscription.iapConsumedTokens = JSON.stringify(tokens);
  siyi.permanentSp += amount; // 充能池发放累计，只增不减（数据安全军令）
  // ★ 0.290.2 删除此处清零调用——0.289.1 在新购链路调清零，而新购 history 行同为「充能 +」前缀，
  //   第二笔购买会把第一笔新购账误清；清零只保留 BillingPage 进场单一触发点
  // 建包（token 幂等已挡上，此处必为新包）：ts=Date.now() 精确到秒（账本要求）
  const pkg = new IapPackage();
  pkg.tok = purchaseToken;
  pkg.pid = productId;
  pkg.amt = amount;
  pkg.ts = Date.now();
  const pkgList = parseIapPackages(siyi.iapPackages);
  pkgList.push(pkg);
  siyi.iapPackages = JSON.stringify(pkgList);
  let history: string[] = [];
  try {
    history = JSON.parse(subscription.purchaseHistory) as string[];
  } catch (_e) {
    history = [];
  }
  history.push(`充能 +${amount / 10000} 万司忆点｜华为应用内支付 ${purchaseToken.substring(0, 8)}…｜${new Date().toLocaleDateString()}`);
  subscription.purchaseHistory = JSON.stringify(history);
  scheduleRowFlush(); // SP 变动防抖上行（cfg:siyi-points——多端一致）
  const _ip: Record<string, string> = {}; // ★ 0.260.0：sp_grant 埋点（IAP 发放）
  _ip['src'] = 'iap';
  _ip['sp'] = `${amount}`;
  _ip['bal'] = `${siyiTotalSp(siyi)}`;
  _ip['amt'] = amountCny; // ★ 0.273.0：实际成交价 ¥（充值流水求和数据源）
  _ip['pid'] = productId; // ★ 0.273.0：商品 ID
  trackUidAuto('sp_grant', _ip);
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
  store.rebuildEpoch++; // ★ 0.244.0：nodeList 整体替换——渲染世代 +1（ForEach key 联动重建条目）
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
// ★ 0.228.0 行桥接（rowBridge）——细粒度行模式：上行 flush / 下行 reconcile / 旧池迁移
// ============================================================
// 行键：node:<id> / tab:<id> / word:<id> / card:<id> / wfolder:<id> / kfolder:<id> /
//   cfg:<name>（api-config/ai-pref/face-mode 三枚账号级设置） / del:<id>（删除标记行）
// 探针实证约束（docs/0.165+/0.228.0 §四）：物理删行不传播→删除=del 标记行；
//   超限行毒化批次→CloudSyncUtil 512KB 分块；TIME_FIRST 行级 LWW 框架已裁决行版本。
// 语义仲裁（cache 规则，统一全类型）：本地序列化==云端行值→跳过；不等时——本地值==cache
//   （本端自上次上行后未改）或 cache 缺失（本端从未上行，含全新安装种子）→云端胜；本地值
//   !=cache（有未上行编辑）→本地胜（flush 上行）。种子 mtime=now 顶掉云端进度的事故路径
//   被「cache 缺失→云端胜」结构性封死（0.223.1 同源防线升级）。
// 回环纪律：reconcile 只写 PersistenceV2 不 upsert 行；flush 只在值变时写行（diff-cache）。
// ============================================================

// 提供者注入（防循环依赖：WordStoreUtil/KnowledgeStoreUtil import 本文件挂钩子，本文件不反向 import 它们）
let wordBankProvider: (() => WordBankStore) | null = null;
let knowledgeBankProvider: (() => KnowledgeBankStore) | null = null;

export function initRowBridgeProviders(wordProvider: () => WordBankStore, klgProvider: () => KnowledgeBankStore): void {
  wordBankProvider = wordProvider;
  knowledgeBankProvider = klgProvider;
}

// diff-cache：key → 本端最后上行值（杀行时间戳 churn + reconcile 语义仲裁基石；重启由
//   首轮 reconcile 的「云端值==本地值→set cache」与 flush 重建，无需持久化）
const rowCache = new Map<string, string>();

// ---- 序列化（0.205.4 纪律：@ObservedV2 一律手写 plain 映射） ----
function nodeToJson(node: BubbleNode): string {
  const msgs: SerializedMessage[] = node.messages.map((msg: ChatMessage): SerializedMessage => {
    return {
      messageId: msg.messageId, role: msg.role, content: msg.content, imageUrl: msg.imageUrl,
      inputTokens: msg.inputTokens, outputTokens: msg.outputTokens,
      isPodcastMode: msg.isPodcastMode, model: msg.model, cacheHitTokens: msg.cacheHitTokens, // ★ 0.247.4
      reasoningTokens: msg.reasoningTokens // ★ 0.271.0：思考 token 拆分随行序列化（云同步/行模式共用）
    };
  });
  const n: SerializedNode = {
    nodeID: node.nodeID, parentID: node.parentID, messages: msgs, x: node.x, y: node.y,
    parentX: node.parentX, parentY: node.parentY, historySummary: node.historySummary,
    historySummaryCount: node.historySummaryCount, nodeTitle: node.nodeTitle,
    draftText: node.draftText, draftImages: node.draftImages
  };
  return JSON.stringify(n);
}

function nodeFromJson(v: string): BubbleNode | null {
  try {
    const n = JSON.parse(v) as SerializedNode;
    const messages: ChatMessage[] = (n.messages ?? []).map((m: SerializedMessage): ChatMessage => {
      return new ChatMessage(m.messageId, m.role as ChatRole, m.content, m.imageUrl ?? [],
        m.inputTokens ?? 0, m.outputTokens ?? 0, m.isPodcastMode ?? false, m.model ?? '', m.cacheHitTokens ?? 0, m.reasoningTokens ?? 0); // ★ 0.247.4：缓存命中尾部追加；★ 0.271.0：思考 token 补 0
    });
    return new BubbleNode(n.nodeID, n.parentID, messages, n.x ?? 0, n.y ?? 0, n.parentX ?? 0, n.parentY ?? 0,
      n.historySummary ?? '', n.historySummaryCount ?? 0, n.nodeTitle ?? '', n.draftText ?? '', n.draftImages ?? '');
  } catch (_e) {
    return null;
  }
}

function wordFolderToJson(f: WordFolder): string {
  const o: Record<string, Object> = {};
  o['id'] = f.id;
  o['name'] = f.name;
  o['parentId'] = f.parentId;
  o['createdAt'] = f.createdAt;
  o['mtime'] = f.mtime;
  return JSON.stringify(o);
}

function wordFolderFromJson(v: string): WordFolder | null {
  try {
    const r = JSON.parse(v) as Record<string, Object>;
    const f = new WordFolder();
    f.id = String(r['id'] ?? '');
    f.name = String(r['name'] ?? '');
    f.parentId = String(r['parentId'] ?? '');
    f.createdAt = Number(r['createdAt'] ?? 0);
    f.mtime = Number(r['mtime'] ?? 0);
    return f.id.length > 0 ? f : null;
  } catch (_e) {
    return null;
  }
}

function cfgApiToJson(): string {
  const c = connectApiConfig();
  const o: Record<string, Object> = {};
  o['apiKey'] = c.apiKey;
  o['endpoint'] = c.endpoint;
  o['model'] = c.model;
  o['provider'] = c.provider;
  o['audioModel'] = c.audioModel;
  o['audioVoice'] = c.audioVoice;
  o['audioEndpoint'] = c.audioEndpoint;
  o['audioKey'] = c.audioKey;
  o['docSecretId'] = c.docSecretId; // ★ 0.291.2：云同步行同待遇（与 apiKey 一致上云）
  o['docSecretKey'] = c.docSecretKey;
  return JSON.stringify(o);
}

function cfgApiApply(v: string): boolean {
  try {
    const r = JSON.parse(v) as Record<string, Object>;
    const c = connectApiConfig();
    const g = (k: string, cur: string): string => {
      return String(r[k] ?? cur);
    };
    c.apiKey = g('apiKey', c.apiKey);
    c.endpoint = g('endpoint', c.endpoint);
    c.model = g('model', c.model);
    c.provider = g('provider', c.provider);
    c.audioModel = g('audioModel', c.audioModel);
    c.audioVoice = g('audioVoice', c.audioVoice);
    c.audioEndpoint = g('audioEndpoint', c.audioEndpoint);
    c.audioKey = g('audioKey', c.audioKey);
    c.docSecretId = g('docSecretId', c.docSecretId); // ★ 0.291.2：云下行补灌（云端旧值无此键=保留本地）
    c.docSecretKey = g('docSecretKey', c.docSecretKey);
    // ★ 0.240.2 修正：此处禁 snapshotApiConfig——云下行旧值（保存后上行未及时+云端滞留旧配置）
    //   会被固化到 v5 盘上=「保存→重启被回滚」的帮凶（真机取证实锤：⑤ 回显华为+旧标记后拉盘
    //   v5 已被覆写成云端旧值）。云下行只改内存：每次冷启云同步重放 apply，无需落盘；
    //   盘=v5 本地保存真值，云端断网时兜底。
    return true;
  } catch (_e) {
    return false;
  }
}

function cfgAiPrefToJson(): string {
  const p = connectAiPreference();
  const o: Record<string, Object> = {};
  o['aiNickname'] = p.aiNickname;
  o['encourageMode'] = p.encourageMode;
  return JSON.stringify(o);
}

function cfgAiPrefApply(v: string): boolean {
  try {
    const r = JSON.parse(v) as Record<string, Object>;
    const p = connectAiPreference();
    const n = String(r['aiNickname'] ?? p.aiNickname);
    p.aiNickname = n;
    const m = String(r['encourageMode'] ?? p.encourageMode);
    if (m === 'off' || m === 'light' || m === 'heavy') {
      p.encourageMode = m;
    }
    return true;
  } catch (_e) {
    return false;
  }
}

function cfgFaceModeToJson(): string {
  const f = connectFaceMode();
  const o: Record<string, Object> = {};
  o['mode'] = f.mode;
  return JSON.stringify(o);
}

function cfgFaceModeApply(v: string): boolean {
  try {
    const r = JSON.parse(v) as Record<string, Object>;
    const m = String(r['mode'] ?? '');
    if (m === 'single' || m === 'double') {
      connectFaceMode().mode = m;
    }
    return true;
  } catch (_e) {
    return false;
  }
}

// ---- 上行 flush（防抖 3s；onBackground/闸门开后立即版 flushCloudRowsNow） ----
let flushTimerId: number = -1;

function scheduleRowFlush(): void {
  if (flushTimerId >= 0) {
    clearTimeout(flushTimerId);
  }
  flushTimerId = setTimeout(() => {
    flushTimerId = -1;
    flushCloudRowsNow();
  }, 3000);
}

// ★ 0.228.1：模式感知节点真相（saveTree 只写当前模式的池——非活动池必然 stale；
//   flush 必须从活动模式取活集，否则 tabs 模式下删除被 stale flat 池判为存活→del 行永不产生）
function activeTreeNodes(): BubbleNode[] {
  const modeStore = connectCanvasMode();
  if (modeStore.mode === 'tabs') {
    const forest = connectTabForest();
    const out: BubbleNode[] = [];
    for (const t of parseTabs(forest.tabsJson)) {
      const tree = deserializeBubbleTree(t.treeJson);
      if (tree !== null) {
        for (const n of tree.nodeList) {
          out.push(n);
        }
      }
    }
    return out;
  }
  const persist = PersistenceV2.connect(PersistData, 'persist-data',
    () => new PersistData()) as PersistData;
  const tree = deserializeBubbleTree(persist.bubbleTreeJson);
  return tree !== null ? tree.nodeList : [];
}

// ★ 0.228.1：flat 池坐标快照（layout:flat 原子行——整套坐标单行 LWW，杜绝并发重排
//   每节点独立裁决导致的混排汤；tab 树天然整树一行本就原子，仅 flat 视图需要）
function localLayoutJson(): string {
  const persist = PersistenceV2.connect(PersistData, 'persist-data',
    () => new PersistData()) as PersistData;
  const tree = deserializeBubbleTree(persist.bubbleTreeJson);
  const o: Record<string, Object> = {};
  if (tree !== null) {
    for (const n of tree.nodeList) {
      const a: number[] = [n.x, n.y, n.parentX, n.parentY];
      o[n.nodeID] = a;
    }
  }
  return JSON.stringify(o);
}

function applyCloudLayout(v: string | undefined): boolean {
  if (v === undefined) {
    return false;
  }
  const local = localLayoutJson();
  if (v === local) {
    rowCache.set('layout:flat', v);
    return false;
  }
  if (!cloudWins('layout:flat', local)) {
    return false; // 本地未上行布局胜（flush 收口）
  }
  try {
    const r = JSON.parse(v) as Record<string, Object>;
    const persist = PersistenceV2.connect(PersistData, 'persist-data',
      () => new PersistData()) as PersistData;
    const tree = deserializeBubbleTree(persist.bubbleTreeJson);
    if (tree === null) {
      return false;
    }
    let hit = false;
    for (const n of tree.nodeList) {
      const a = r[n.nodeID];
      if (Array.isArray(a) && (a as Array<number>).length >= 4) {
        const q = a as Array<number>;
        n.x = q[0];
        n.y = q[1];
        n.parentX = q[2];
        n.parentY = q[3];
        hit = true;
      }
    }
    if (!hit) {
      return false;
    }
    persist.bubbleTreeJson = serializeBubbleTree(tree);
    rowCache.set('layout:flat', v);
    return true;
  } catch (_e) {
    return false;
  }
}

// ★ 0.228.1：del 行双池清理（tab 树删除盲区修复——mergeNodes 只清 flat 池，
//   非活动模式的 tab 树留僵尸，切模式即还魂；云端有实体行的 id 跳过=复活语义保留）
function propagateDelsToPools(dels: Map<string, number>, cloudNodes: Map<string, string>): boolean {
  if (dels.size === 0) {
    return false;
  }
  let changed = false;
  const persist = PersistenceV2.connect(PersistData, 'persist-data',
    () => new PersistData()) as PersistData;
  const flatTree = deserializeBubbleTree(persist.bubbleTreeJson);
  if (flatTree !== null && flatTree.nodeList.length > 0) {
    const kept = flatTree.nodeList.filter((n: BubbleNode): boolean => {
      return !dels.has(n.nodeID) || cloudNodes.has('node:' + n.nodeID);
    });
    if (kept.length !== flatTree.nodeList.length) {
      persist.bubbleTreeJson = serializeBubbleTree(new BubbleTree(kept));
      changed = true;
    }
  }
  const forest = connectTabForest();
  const tabs = parseTabs(forest.tabsJson);
  let tabsChanged = false;
  for (const t of tabs) {
    const tr = deserializeBubbleTree(t.treeJson);
    if (tr !== null && tr.nodeList.length > 0) {
      const kept = tr.nodeList.filter((n: BubbleNode): boolean => {
        return !dels.has(n.nodeID) || cloudNodes.has('node:' + n.nodeID);
      });
      if (kept.length !== tr.nodeList.length) {
        t.treeJson = serializeBubbleTree(new BubbleTree(kept));
        tabsChanged = true;
      }
    }
  }
  if (tabsChanged) {
    forest.tabsJson = serializeTabs(tabs);
    changed = true;
  }
  return changed;
}

// ★ 0.228.5：两池互转（0.151「两池互通」语义在行模式的落地）——nodeSet=内容唯一真相
//   （flat 池∪tab 树、同 id 取 flat=node 行最新、剔 dels），Tab=派生视图：每根必有 Tab、
//   现有 Tab 保名保序、根亡 Tab 除、新根生 Tab（id='tab_'+根id后缀=跨端确定性，杜绝 ID 错乱）；
//   幂等（确定性排序+稳定序列化），收敛后零写入零 churn
function interconvertPools(dels: Map<string, number>): boolean {
  const persist = PersistenceV2.connect(PersistData, 'persist-data',
    () => new PersistData()) as PersistData;
  const forest = connectTabForest();
  const byId = new Map<string, BubbleNode>();
  const flatTree = deserializeBubbleTree(persist.bubbleTreeJson);
  if (flatTree !== null) {
    for (const n of flatTree.nodeList) {
      if (!dels.has(n.nodeID)) {
        byId.set(n.nodeID, n);
      }
    }
  }
  const tabs = parseTabs(forest.tabsJson);
  const tabRootIds: string[] = [];
  for (const t of tabs) {
    const tr = deserializeBubbleTree(t.treeJson);
    if (tr === null) {
      tabRootIds.push('');
      continue;
    }
    const root = tr.nodeList.find((n: BubbleNode): boolean => n.parentID === null);
    tabRootIds.push(root !== undefined ? root.nodeID : '');
    for (const n of tr.nodeList) {
      if (!dels.has(n.nodeID) && !byId.has(n.nodeID)) {
        byId.set(n.nodeID, n);
      }
    }
  }
  let changed = false;
  const all: BubbleNode[] = [];
  byId.forEach((n: BubbleNode): void => {
    all.push(n);
  });
  all.sort((a: BubbleNode, b: BubbleNode): number => {
    return idCreateTime(a.nodeID) - idCreateTime(b.nodeID);
  });
  const newFlatJson = serializeBubbleTree(new BubbleTree(all));
  if (newFlatJson !== persist.bubbleTreeJson) {
    persist.bubbleTreeJson = newFlatJson;
    changed = true;
  }
  const children = new Map<string, BubbleNode[]>();
  byId.forEach((n: BubbleNode): void => {
    if (n.parentID !== null) {
      const list = children.get(n.parentID) ?? [];
      list.push(n);
      children.set(n.parentID, list);
    }
  });
  const newTabs: TabMeta[] = [];
  const covered = new Set<string>();
  for (let i = 0; i < tabs.length; i++) {
    const rootId = tabRootIds[i];
    const rn = byId.get(rootId);
    if (rootId.length === 0 || rn === undefined || covered.has(rootId)) {
      changed = true; // 坏树/根已删/重复 → Tab 移除
      continue;
    }
    covered.add(rootId);
    const subtree: BubbleNode[] = [];
    collectSubtree(rn, children, subtree, new Set<string>());
    newTabs.push({
      id: tabs[i].id,
      name: tabs[i].name.length > 0 ? tabs[i].name : getRootDisplayName(rn),
      treeJson: serializeBubbleTree(new BubbleTree(subtree))
    });
  }
  byId.forEach((n: BubbleNode): void => {
    if (n.parentID === null && !covered.has(n.nodeID)) {
      covered.add(n.nodeID);
      const subtree: BubbleNode[] = [];
      collectSubtree(n, children, subtree, new Set<string>());
      newTabs.push({
        id: 'tab_' + n.nodeID.substring('bubble_'.length),
        name: getRootDisplayName(n),
        treeJson: serializeBubbleTree(new BubbleTree(subtree))
      });
      changed = true;
    }
  });
  newTabs.sort((a: TabMeta, b: TabMeta): number => {
    return idCreateTime(a.id) - idCreateTime(b.id);
  });
  const newTabsJson = serializeTabs(newTabs);
  if (newTabsJson !== forest.tabsJson) {
    forest.tabsJson = newTabsJson;
    changed = true;
  }
  return changed;
}

function collectSubtree(root: BubbleNode, children: Map<string, BubbleNode[]>, out: BubbleNode[], seen: Set<string>): void {
  if (seen.has(root.nodeID)) {
    return;
  }
  seen.add(root.nodeID);
  out.push(root);
  const kids = children.get(root.nodeID) ?? [];
  kids.sort((a: BubbleNode, b: BubbleNode): number => {
    return idCreateTime(a.nodeID) - idCreateTime(b.nodeID);
  });
  for (const k of kids) {
    collectSubtree(k, children, out, seen);
  }
}

export async function flushCloudRowsNow(): Promise<void> {
  if (!connectCloudSyncArbiter().rowInitDone) {
    return; // 首拉闸门未开（0.223.1 种子事故防线——闸开后的首轮 flush 补写一切）
  }
  // ★ 0.228.3：cache 冷启播种——cache 为空（新进程）时从 RDB 现有行播种：
  //   未变值零重写=时间戳不被冷启集体刷新（否则开着的对端给已删条目盖新戳→压过
  //   del 行→复活循环，用户实测「马上回复」根因）；顺带杀全量 churn
  if (rowCache.size === 0) {
    const seedRows = await queryAllRows();
    for (const r of seedRows) {
      if (r.key.startsWith('cfg:') || r.key.startsWith('node:') || r.key.startsWith('tab:') ||
        r.key.startsWith('word:') || r.key.startsWith('card:') || r.key.startsWith('wfolder:') ||
        r.key.startsWith('kfolder:') || r.key.startsWith('layout:')) {
        rowCache.set(r.key, r.value);
      }
    }
  }
  try {
    // 气泡树（★ 0.228.1 活动模式真相——非活动池 stale 不得作为活集/写行来源）
    // ★ 0.230.1：flushDeletions 自动差集对账已整体删除——墓碑只准显式删除操作触发
    //   （recordNodeTomb/recordTabTomb/recordWordTomb/recordKnowledgeTomb），reconcile/flush
    //   自动路径永不写墓碑（0.228.0 四连环 Bug B 根凶：残缺池对账 RDB 全表 → 伪墓碑批量
    //   出生+本地物理删行 → 新戳压制增量下行 → 上行即全端丢失）
    for (const node of activeTreeNodes()) {
      upsertIfChanged('node:' + node.nodeID, nodeToJson(node));
    }
    // Tab 森林
    const forest = connectTabForest();
    const tabs = parseTabs(forest.tabsJson);
    for (const t of tabs) {
      upsertIfChanged('tab:' + t.id, JSON.stringify(t));
    }
    // 单词库 + 文件夹
    if (wordBankProvider !== null) {
      const ws = wordBankProvider();
      for (const w of ws.words) {
        upsertIfChanged('word:' + w.id, JSON.stringify(wordToPlain(w)));
      }
      for (const f of ws.folders) {
        upsertIfChanged('wfolder:' + f.id, wordFolderToJson(f));
      }
    }
    // 知识库 + 文件夹
    if (knowledgeBankProvider !== null) {
      const ks = knowledgeBankProvider();
      for (const c of ks.cards) {
        upsertIfChanged('card:' + c.id, JSON.stringify(cardToPlain(c)));
      }
      for (const f of ks.folders) {
        upsertIfChanged('kfolder:' + f.id, JSON.stringify(folderToPlain(f)));
      }
    }
    // 账号级设置三枚
    upsertIfChanged('cfg:api-config', cfgApiToJson());
    upsertIfChanged('cfg:ai-pref', cfgAiPrefToJson());
    upsertIfChanged('cfg:face-mode', cfgFaceModeToJson());
    // ★ 0.248.4：账号级资产两行（等级数据源+SP——并集/max 合并语义见 mergeStatDaysRow/mergeSiyiPointsRow）
    upsertIfChanged('cfg:stat-days', connectStatistics().raw);
    upsertIfChanged('cfg:siyi-points', siyiPointsToJson());
    // ★ 0.228.1：flat 模式写 layout 原子行（整套坐标单行——并发重排不再混排）
    if (connectCanvasMode().mode === 'flat') {
      upsertIfChanged('layout:flat', localLayoutJson());
    }
  } catch (_e) {
  }
}

// ★ 0.230.1：会话级墓碑注册表——显式删除与每轮 reconcile 的 del 行全集；
//   flush 写行前查表：已墓碑 id 永不写行（否则「展示即复习」等 mtime 变更会令实体行
//   时间戳反超墓碑 → LWW 判活 → 已删条目复活——真机实锤：删词后进词库页即复活）
const tombstonedIds = new Set<string>();

function upsertIfChanged(key: string, value: string): void {
  const id = key.substring(key.indexOf(':') + 1);
  if (tombstonedIds.has(id)) {
    deleteRowLocal(key); // 墓碑压制中的实体行：清本地残行，绝不重写（重写=新时间戳=复活）
    rowCache.delete(key);
    return;
  }
  if (rowCache.get(key) === value) {
    return; // diff-cache 挡（值变才写行——杀 churn）
  }
  upsertRow(key, value);
  rowCache.set(key, value);
}

// ---- 下行 reconcile（dataChange/forceSync 后触发；全表 query=同步完成后的单点快照） ----
let reconcileBusy = false;
let reconcileQueued = false;

function reconcileCloudRows(): void {
  if (reconcileBusy) {
    reconcileQueued = true;
    return;
  }
  reconcileBusy = true;
  queryAllRows().then((rows: CloudRow[]) => {
    try {
      reconcileWithRows(rows);
    } catch (_e) {
    } finally {
      reconcileBusy = false;
      if (reconcileQueued) {
        reconcileQueued = false;
        reconcileCloudRows();
      }
    }
  }).catch(() => {
    reconcileBusy = false;
  });
}


interface ChunkedMarker {
  __chunks?: number;
}

function reconcileWithRows(rows: CloudRow[]): void {
  const raw = new Map<string, string>();
  const ts = new Map<string, number>();
  for (const r of rows) {
    raw.set(r.key, r.value);
    ts.set(r.key, r.updatedAt);
  }
  // chunk 重组（主行 {"__chunks":N} + <key>~<i> 片段行；缺片=pending 计数 + 坏行丢弃自愈）
  let pendingChunkCount = 0; // ★ 0.230.1：缺片行计数（>0=本轮下行不完整，闸门不开）
  const entity = new Map<string, string>();
  raw.forEach((v: string, k: string): void => {
    if (k.indexOf('~') >= 0) {
      return;
    }
    let chunked = false;
    try {
      const m = JSON.parse(v) as ChunkedMarker;
      if (typeof m.__chunks === 'number' && m.__chunks > 0) {
        chunked = true;
        let full = '';
        let ok = true;
        for (let i = 0; i < m.__chunks; i++) {
          const seg = raw.get(`${k}~${i}`);
          if (seg === undefined) {
            ok = false;
            break;
          }
          full += seg;
        }
        if (ok) {
          entity.set(k, full);
        } else {
          // ★ 0.230.1：缺片=下行不完整（Bug A 实锤形态）——该行不进实体域（现行为），
          //   并计数上报：闸门本会话不开（防残缺态上行旧值覆盖云端）+ 有界 nudge 重拉
          pendingChunkCount++;
        }
      }
    } catch (_e) {
      // 非 JSON 值按原文处理
    }
    if (!chunked) {
      entity.set(k, v);
    }
  });
  // 域收集
  const cloudNodes = new Map<string, string>();
  const cloudTabs = new Map<string, string>();
  const cloudWords = new Map<string, string>();
  const cloudCards = new Map<string, string>();
  const cloudWf = new Map<string, string>();
  const cloudKf = new Map<string, string>();
  const cloudCfg = new Map<string, string>();
  const dels = new Map<string, number>();
  entity.forEach((v: string, k: string): void => {
    if (k.startsWith('node:')) {
      cloudNodes.set(k, v);
    } else if (k.startsWith('tab:')) {
      cloudTabs.set(k, v);
    } else if (k.startsWith('word:')) {
      cloudWords.set(k, v);
    } else if (k.startsWith('card:')) {
      cloudCards.set(k, v);
    } else if (k.startsWith('wfolder:')) {
      cloudWf.set(k, v);
    } else if (k.startsWith('kfolder:')) {
      cloudKf.set(k, v);
    } else if (k.startsWith('cfg:')) {
      cloudCfg.set(k, v);
    } else if (k.startsWith('del:')) {
      try {
        const r = JSON.parse(v) as Record<string, Object>;
        const t = Number(r['t'] ?? 0);
        if (t > 0) {
          const did = k.substring('del:'.length);
          dels.set(did, t);
          tombstonedIds.add(did); // ★ 0.230.1：注册进会话墓碑表——flush 对其永不写行（防 mtime 复活）
        }
      } catch (_e) {
        // 坏墓碑忽略
      }
    }
  });
  // ★ 旧池迁移（一次性）：四池行内容吸收进各域 map（走同款合并=幂等；本地/云端池行删除）
  const arb = connectCloudSyncArbiter();
  let justMigrated = false;
  if (!arb.legacyMigrated) {
    absorbLegacyPools(entity, cloudNodes, cloudTabs, cloudWords, cloudCards, cloudWf, cloudKf);
    arb.legacyMigrated = true;
    justMigrated = true;
    deleteRowLocal('flat_pool');
    deleteRowLocal('tabs_pool');
    deleteRowLocal('word_pool');
    deleteRowLocal('knowledge_pool');
  }
  // ★ 0.259.1：复活型脏对自愈——node 行戳 > 墓碑戳（历史 bug 版本上行污染，2026-10-19 真机实锤
  //   42/42 全为此型）的节点每次下行 LWW 复活入池=用户实测「先弹出整个然后又删掉」的僵尸源；
  //   自愈=重打新墓碑（新戳恒>node 戳，墓碑上行全端收敛根除）+本端当轮即剔（dels 抬戳走剔除分支，
  //   顺带触发 deleteRowLocal 清压制行）。id 已注册 tombstonedIds（下行 del 注册在先）——flush 永不对抗。
  let revivedDirty = 0;
  cloudNodes.forEach((v: string, k: string): void => {
    const nid = k.substring('node:'.length);
    const ndelT = dels.get(nid);
    if (ndelT !== undefined && ndelT < (ts.get(k) ?? 0)) {
      writeTombstone(nid);
      dels.set(nid, Date.now() + 1);
      revivedDirty++;
    }
  });
  cloudTabs.forEach((v: string, k: string): void => {
    const tid = k.substring('tab:'.length);
    const tdelT = dels.get(tid);
    if (tdelT !== undefined && tdelT < (ts.get(k) ?? 0)) {
      writeTombstone(tid);
      dels.set(tid, Date.now() + 1);
      revivedDirty++;
    }
  });
  // 各域合并
  const nodesChanged = mergeNodes(cloudNodes, dels, ts);
  const tabsChanged = mergeTabs(cloudTabs, dels, ts);
  mergeWords(cloudWords, cloudWf, dels, ts);
  mergeKnowledge(cloudCards, cloudKf, dels, ts);
  mergeCfgs(cloudCfg);
  // ★ 0.228.1：布局原子行下发 + del 行双池清理（tab 树删除盲区修复）
  const layoutChanged = applyCloudLayout(entity.get('layout:flat'));
  const delsPropagated = propagateDelsToPools(dels, cloudNodes);
  const interChanged = interconvertPools(dels); // ★ 0.228.5：两池绑定（每根必有 Tab）
  if (nodesChanged || tabsChanged || layoutChanged || delsPropagated || interChanged) {
    refreshWorkspaceFromPools(); // 重建工作区 + needsCloudRedraw（保坐标重绘，0.223.0 机制原样）
  }
  // ★ 0.230.1：首拉闸门纪律——本轮无缺片才开（开着=本会话已完成一次完整下行）；
  //   缺片>0：闸门保持关（上行全阻——防残缺态旧值 LWW 压云端新值），但有界 nudge 重拉，
  //   dataChange 事件到片后自动重跑 reconcile 直至完整开闸（重试上限后放弃=只读态等前台再拉）
  if (pendingChunkCount > 0) {
    schedulePullNudge();
  } else {
    pullNudgeAttempts = 0;
    arb.rowInitDone = true;
    maybeGrantWelcomeAfterFirstPull(); // ★ 0.293.0：首拉完成=SP 云端账本已对齐→此刻判新用户礼包（云端标记拦老账号重装）
  }
  // 迁移物化：吸收值只存在于内存 map（reconcile 已把它们播进 cache 令 flush 误判「未变」）——
  //   必须显式落行，否则实体行永远不出生、行模式云端为空（实测实锤：仅 cfg 3 行）
  if (justMigrated) {
    materializeRows(cloudNodes, 'node:');
    materializeRows(cloudTabs, 'tab:');
    materializeRows(cloudWords, 'word:');
    materializeRows(cloudCards, 'card:');
    materializeRows(cloudWf, 'wfolder:');
    materializeRows(cloudKf, 'kfolder:');
  }
  // flush：diff-cache 消化成本（全等=零写行）；闸门未开时内部自返回（0.230.1 起闸门=会话级）
  flushCloudRowsNow();
}

// ★ 0.230.1：缺片 nudge 重拉（有界）——15s 后 forceCloudSyncNow 触发下一轮 reconcile；
//   ≤6 次（约 90s），成功（无缺片）即由上方 pullNudgeAttempts=0 复位
let pullNudgeAttempts: number = 0;
let pullNudgeTimer: number = -1;

function schedulePullNudge(): void {
  if (pullNudgeTimer >= 0 || pullNudgeAttempts >= 6) {
    return;
  }
  pullNudgeAttempts++;
  pullNudgeTimer = setTimeout(() => {
    pullNudgeTimer = -1;
    forceCloudSyncNow();
  }, 15000);
}

function materializeRows(m: Map<string, string>, _prefix: string): void {
  m.forEach((v: string, k: string): void => {
    upsertRow(k, v);
    rowCache.set(k, v);
  });
}

function absorbLegacyPools(entity: Map<string, string>, cloudNodes: Map<string, string>, cloudTabs: Map<string, string>,
  cloudWords: Map<string, string>, cloudCards: Map<string, string>, cloudWf: Map<string, string>, cloudKf: Map<string, string>): void {
  // flat_pool → node 行
  const flat = entity.get('flat_pool');
  if (flat !== undefined) {
    const tree = deserializeBubbleTree(flat);
    if (tree !== null) {
      for (const node of tree.nodeList) {
        cloudNodes.set('node:' + node.nodeID, nodeToJson(node));
      }
    }
  }
  // tabs_pool → tab 行
  const tabsJson = entity.get('tabs_pool');
  if (tabsJson !== undefined) {
    const tabs = parseTabs(tabsJson);
    for (const t of tabs) {
      cloudTabs.set('tab:' + t.id, JSON.stringify(t));
    }
  }
  // word_pool / knowledge_pool → 条目行（payload 沿用 0.223.0 BankPoolPayload 结构）
  absorbBankPool(entity.get('word_pool'), cloudWords, cloudWf, true);
  absorbBankPool(entity.get('knowledge_pool'), cloudCards, cloudKf, false);
}

function absorbBankPool(poolJson: string | undefined, items: Map<string, string>, folders: Map<string, string>, isWord: boolean): void {
  if (poolJson === undefined) {
    return;
  }
  try {
    const p = JSON.parse(poolJson) as Record<string, Object>;
    const words = p['words'];
    if (Array.isArray(words)) {
      for (const w of words as Array<Record<string, Object>>) {
        const id = String(w['id'] ?? '');
        if (id.length > 0) {
          items.set((isWord ? 'word:' : 'card:') + id, JSON.stringify(w));
        }
      }
    }
    const cards = p['cards'];
    if (Array.isArray(cards)) {
      for (const c of cards as Array<Record<string, Object>>) {
        const id = String(c['id'] ?? '');
        if (id.length > 0) {
          items.set((isWord ? 'word:' : 'card:') + id, JSON.stringify(c));
        }
      }
    }
    const fs = p['folders'];
    if (Array.isArray(fs)) {
      for (const f of fs as Array<Record<string, Object>>) {
        const id = String(f['id'] ?? '');
        if (id.length > 0) {
          folders.set((isWord ? 'wfolder:' : 'kfolder:') + id, JSON.stringify(f));
        }
      }
    }
  } catch (_e) {
    // 坏池静默（旧池数据保留在本地 PersistenceV2，无损）
  }
}

// cache 语义仲裁核心：true=云端胜（本地未改或从未上行） / false=本地胜（有未上行编辑）
function cloudWins(key: string, localSer: string): boolean {
  const cached = rowCache.get(key);
  return cached === undefined || cached === localSer;
}

function mergeNodes(cloud: Map<string, string>, dels: Map<string, number>, ts: Map<string, number>): boolean {
  const persist = PersistenceV2.connect(PersistData, 'persist-data',
    () => new PersistData()) as PersistData;
  const tree = deserializeBubbleTree(persist.bubbleTreeJson);
  const local = tree !== null ? tree.nodeList : [];
  const byId = new Map<string, BubbleNode>();
  for (const n of local) {
    byId.set(n.nodeID, n);
  }
  const merged: BubbleNode[] = [];
  let changed = false;
  cloud.forEach((v: string, k: string): void => {
    const id = k.substring('node:'.length);
    const delT = dels.get(id);
    if (delT !== undefined && delT >= (ts.get(k) ?? 0)) {
      deleteRowLocal(k); // ★ 0.230.1：del 胜出同步清本地实体行（防压制行滞留→两端行数假不对称）
      rowCache.delete(k);
      return; // 云端删除（del 行新于实体行）
    }
    const localNode = byId.get(id);
    const localSer = localNode !== undefined ? nodeToJson(localNode) : '';
    if (localNode !== undefined && localSer === v) {
      rowCache.set(k, v);
      merged.push(localNode);
      return;
    }
    if (localNode === undefined || cloudWins(k, localSer)) {
      const revived = nodeFromJson(v);
      if (revived !== null) {
        changed = true;
        rowCache.set(k, v);
        merged.push(revived);
      }
    } else if (localNode !== undefined) {
      merged.push(localNode); // 本地未上行编辑胜（flush 收口）
    }
  });
  byId.forEach((node: BubbleNode, id: string): void => {
    if (!cloud.has('node:' + id)) {
      if (dels.has(id)) {
        changed = true; // 云端墓碑：本地删除传播
        rowCache.delete('node:' + id);
        deleteRowLocal('node:' + id);
      } else {
        merged.push(node); // 本端独有（离线新建/云端未达）
      }
    }
  });
  // ★ 0.228.4：合并结果按 id 内嵌创建时间戳排序（nodeID= bubble_<ts>_rand）——
  //   合并数组顺序曾= SQLite 返回序+本地补尾（两端不同）→ autoLayout 各排各的→
  //   坐标/连线双端漂移=用户定位的「根节点顺序不一样」根因；排序后顺序全局确定
  merged.sort((a: BubbleNode, b: BubbleNode): number => {
    return idCreateTime(a.nodeID) - idCreateTime(b.nodeID);
  });
  const sortedJson = serializeBubbleTree(new BubbleTree(merged));
  if (sortedJson !== (tree !== null ? persist.bubbleTreeJson : '')) {
    persist.bubbleTreeJson = sortedJson;
    return true;
  }
  return changed;
}

// ★ 0.228.4：从 id 提取创建时间戳（bubble_1791741572440_2091 / tab_1791742001857_0_2089 同构）
function idCreateTime(id: string): number {
  const parts = id.split('_');
  if (parts.length >= 2) {
    const t = Number(parts[1]);
    if (!Number.isNaN(t) && t > 0) {
      return t;
    }
  }
  return 0;
}

function mergeTabs(cloud: Map<string, string>, dels: Map<string, number>, ts: Map<string, number>): boolean {
  const forest = connectTabForest();
  const local = parseTabs(forest.tabsJson);
  const byId = new Map<string, TabMeta>();
  for (const t of local) {
    byId.set(t.id, t);
  }
  const merged: TabMeta[] = [];
  let changed = false;
  cloud.forEach((v: string, k: string): void => {
    const id = k.substring('tab:'.length);
    const delT = dels.get(id);
    if (delT !== undefined && delT >= (ts.get(k) ?? 0)) {
      deleteRowLocal(k); // ★ 0.230.1：del 胜出同步清本地实体行（防压制行滞留→两端行数假不对称）
      rowCache.delete(k);
      return;
    }
    try {
      const ct = JSON.parse(v) as TabMeta;
      if (ct.id === undefined || ct.id.length === 0) {
        return;
      }
      const localTab = byId.get(id);
      const localSer = localTab !== undefined ? JSON.stringify(localTab) : '';
      if (localTab !== undefined && localSer === v) {
        rowCache.set(k, v);
        merged.push(localTab);
        return;
      }
      if (localTab === undefined || cloudWins(k, localSer)) {
        changed = true;
        rowCache.set(k, v);
        merged.push(ct);
      } else {
        merged.push(localTab);
      }
    } catch (_e) {
      // 坏行丢弃
    }
  });
  byId.forEach((t: TabMeta, id: string): void => {
    if (!cloud.has('tab:' + id)) {
      if (dels.has(id)) {
        changed = true;
        rowCache.delete('tab:' + id);
        deleteRowLocal('tab:' + id);
      } else {
        merged.push(t);
      }
    }
  });
  // ★ 0.228.4：Tab 同款确定性排序（防各端 Tab 序漂移）
  merged.sort((a: TabMeta, b: TabMeta): number => {
    return idCreateTime(a.id) - idCreateTime(b.id);
  });
  if (changed) {
    forest.tabsJson = serializeTabs(merged);
  }
  return changed;
}

function mergePlainItems(prefix: string, cloud: Map<string, string>, localSers: Map<string, string>, dels: Map<string, number>, ts: Map<string, number>): Map<string, string> {
  // 通用条目合并（词/卡/夹）：返回 id → 胜出值（云端串或本地串）
  const out = new Map<string, string>();
  cloud.forEach((v: string, k: string): void => {
    const id = k.substring(prefix.length);
    const delT = dels.get(id);
    if (delT !== undefined && delT >= (ts.get(k) ?? 0)) {
      deleteRowLocal(k); // ★ 0.230.1：del 胜出同步清本地实体行（防压制行滞留→两端行数假不对称）
      rowCache.delete(k);
      return; // 云端删除胜
    }
    const localSer = localSers.get(id);
    if (localSer !== undefined && localSer === v) {
      rowCache.set(k, v);
      out.set(id, v);
      return;
    }
    if (localSer === undefined || cloudWins(k, localSer)) {
      rowCache.set(k, v);
      out.set(id, v);
    } else {
      out.set(id, localSer); // 本地未上行编辑胜（flush 收口）
    }
  });
  localSers.forEach((v: string, id: string): void => {
    if (!out.has(id)) {
      if (dels.has(id)) {
        rowCache.delete(prefix + id); // 云端墓碑：本地删除传播
        deleteRowLocal(prefix + id);
      } else {
        out.set(id, v); // 本端独有（离线新建/云端未达）
      }
    }
  });
  return out;
}

function mergeWords(cloudWords: Map<string, string>, cloudWf: Map<string, string>, dels: Map<string, number>, ts: Map<string, number>): void {
  if (wordBankProvider === null) {
    return;
  }
  const store = wordBankProvider();
  const localWords = new Map<string, string>();
  for (const w of store.words) {
    localWords.set(w.id, JSON.stringify(wordToPlain(w)));
  }
  const mergedWords = mergePlainItems('word:', cloudWords, localWords, dels, ts);
  const localWf = new Map<string, string>();
  for (const f of store.folders) {
    localWf.set(f.id, wordFolderToJson(f));
  }
  const mergedWf = mergePlainItems('wfolder:', cloudWf, localWf, dels, ts);
  // 复活 + 数组整体替换（@Trace 可靠刷新定式）
  const revivedWords: WordItem[] = [];
  mergedWords.forEach((v: string, _id: string): void => {
    const w = reviveWord(jsonToRecord(v));
    if (w.id.length > 0) {
      revivedWords.push(w);
    }
  });
  if (revivedWords.length !== store.words.length || itemsOverridden(store.words.map((w: WordItem): string => w.id), localWords, mergedWords)) {
    store.words = revivedWords;
  }
  const revivedFolders: WordFolder[] = [];
  mergedWf.forEach((v: string, _id: string): void => {
    const f = wordFolderFromJson(v);
    if (f !== null) {
      revivedFolders.push(f);
    }
  });
  if (revivedFolders.length !== store.folders.length) {
    store.folders = revivedFolders;
  }
}

function itemsOverridden(ids: string[], localSers: Map<string, string>, merged: Map<string, string>): boolean {
  for (const id of ids) {
    const m = merged.get(id);
    if (m !== undefined && m !== localSers.get(id)) {
      return true; // 存在云端胜出覆盖本地的条目
    }
  }
  return false;
}

function mergeKnowledge(cloudCards: Map<string, string>, cloudKf: Map<string, string>, dels: Map<string, number>, ts: Map<string, number>): void {
  if (knowledgeBankProvider === null) {
    return;
  }
  const store = knowledgeBankProvider();
  const localCards = new Map<string, string>();
  for (const c of store.cards) {
    localCards.set(c.id, JSON.stringify(cardToPlain(c)));
  }
  const mergedCards = mergePlainItems('card:', cloudCards, localCards, dels, ts);
  const localKf = new Map<string, string>();
  for (const f of store.folders) {
    localKf.set(f.id, JSON.stringify(folderToPlain(f)));
  }
  const mergedKf = mergePlainItems('kfolder:', cloudKf, localKf, dels, ts);
  const revivedCards: KnowledgeCard[] = [];
  mergedCards.forEach((v: string, _id: string): void => {
    const c = reviveCard(jsonToRecord(v));
    if (c.id.length > 0) {
      revivedCards.push(c);
    }
  });
  if (revivedCards.length !== store.cards.length || itemsOverridden(store.cards.map((c: KnowledgeCard): string => c.id), localCards, mergedCards)) {
    store.cards = revivedCards;
  }
  const revivedFolders: KFolder[] = [];
  mergedKf.forEach((v: string, _id: string): void => {
    const f = reviveFolder(jsonToRecord(v));
    if (f !== undefined) {
      revivedFolders.push(f);
    }
  });
  if (revivedFolders.length !== store.folders.length) {
    store.folders = revivedFolders;
  }
}

function jsonToRecord(v: string): Record<string, Object> {
  try {
    return JSON.parse(v) as Record<string, Object>;
  } catch (_e) {
    return {};
  }
}

function mergeCfgs(cloudCfg: Map<string, string>): void {
  const apply = (key: string, fn: (v: string) => boolean, localSer: string): void => {
    const v = cloudCfg.get(key);
    if (v === undefined) {
      return;
    }
    if (v === localSer) {
      rowCache.set(key, v);
      return;
    }
    if (cloudWins(key, localSer)) {
      fn(v);
      rowCache.set(key, v);
    }
  };
  apply('cfg:api-config', cfgApiApply, cfgApiToJson());
  apply('cfg:ai-pref', cfgAiPrefApply, cfgAiPrefToJson());
  apply('cfg:face-mode', cfgFaceModeApply, cfgFaceModeToJson());
  // ★ 0.248.4：账号级资产两行——专用并集/max 合并（刻意不走上方 apply LWW 通道：
  //   LWW 整行覆盖会让新装机空态/云端全量互相毁灭对方；统计只增不减+SP 只发放无消耗
  //   语义下 max/并集数学上单调收敛、幂等、无乒乓。⚠️ SP 消耗链路上线时此语义须重审）
  mergeStatDaysRow(cloudCfg.get('cfg:stat-days'));
  mergeSiyiPointsRow(cloudCfg.get('cfg:siyi-points'));
}

// ★ 0.248.4：cfg:stat-days 下行合并——本地∪云端按 date 键并集，同日各数值取 max。
//   合并写回 @Trace raw → 等级头衔/统计页自动刷新；变化则防抖上行把并集推回云端（全端收敛）。
//   rowCache 不在此碰——首拉播种+flush diff 自然裁决（播种值=RDB 云端值，diff 出合并值才上行）
function mergeStatDaysRow(v: string | undefined): void {
  if (v === undefined) {
    return; // 云端无此行（首装/旧版本）——flush 首轮上行本地值即可
  }
  let cloudDays: StatDayEntry[] = [];
  try {
    const data = JSON.parse(v) as StatDayData;
    if (data.days !== undefined && data.days !== null) {
      cloudDays = data.days;
    }
  } catch (_e) {
    return; // 云端坏行——保持本地，flush 上行好值自愈
  }
  // ★ 0.279.1：清理界回灌防护——早于 wipeDate 的云端天一律丢弃（未装新版的旧端把 360 天
  //   测试旧行推上来时，union 吸收会把已清数据拉回；丢弃后 changed 语义不变，flush 上行净表自愈）
  const wipeDate = connectStatsWipeMarker().wipeDate;
  if (wipeDate.length > 0) {
    cloudDays = cloudDays.filter((c: StatDayEntry): boolean => c.date >= wipeDate);
  }
  const store = connectStatistics();
  const localDays = getStatDays(store);
  const byDate = new Map<string, StatDayEntry>();
  for (let i = 0; i < localDays.length; i++) {
    byDate.set(localDays[i].date, localDays[i]);
  }
  let changed = false;
  for (let i = 0; i < cloudDays.length; i++) {
    const c = cloudDays[i];
    const l = byDate.get(c.date);
    if (l === undefined) {
      byDate.set(c.date, c); // 云端独有的天——吸收（等级=天数并集的正是此源）
      changed = true;
      continue;
    }
    if (c.userMsgs > l.userMsgs) {
      l.userMsgs = c.userMsgs;
      changed = true;
    }
    if (c.aiMsgs > l.aiMsgs) {
      l.aiMsgs = c.aiMsgs;
      changed = true;
    }
    if (c.bubbles > l.bubbles) {
      l.bubbles = c.bubbles;
      changed = true;
    }
    if (c.inputTokens > l.inputTokens) {
      l.inputTokens = c.inputTokens;
      changed = true;
    }
    if (c.outputTokens > l.outputTokens) {
      l.outputTokens = c.outputTokens;
      changed = true;
    }
    if ((c.siyi ?? 0) > (l.siyi ?? 0)) {
      l.siyi = c.siyi ?? 0;
      changed = true;
    }
    if ((c.spUsed ?? 0) > (l.spUsed ?? 0)) { // ★ 0.259.0：SP 消耗 max 合并（单调递增语义同 siyi）
      l.spUsed = c.spUsed ?? 0;
      changed = true;
    }
  }
  if (!changed) {
    return; // 本地已是超集——零写回零 churn（云端旧行由 flush diff 上行本地值自愈）
  }
  const merged: StatDayEntry[] = [];
  byDate.forEach((d: StatDayEntry): void => {
    merged.push(d);
  });
  merged.sort((a: StatDayEntry, b: StatDayEntry): number => {
    return a.date < b.date ? -1 : 1;
  });
  store.raw = JSON.stringify({ days: merged } as StatDayData);
  scheduleRowFlush();
  notifyLevelUp(merged.length); // ★ 0.256.0：云下行天数吸收后检头衔升级（对端学习路径）
}

// ★ 0.248.4：cfg:siyi-points 行 payload（普通 class——非 @ObservedV2，stringify 可枚举无 0.205.4 坑）
//   ★ 0.248.7：尾部追加三消耗字段（发放/消耗双侧单调——max 合并语义自洽）
class SiyiRowPayload {
  permanentSp: number = 0;
  bonusSp: number = 0;
  giftSp: number = 0;
  giftSpExpireAt: number = 0;
  welcomeGranted: boolean = false;
  consumedGiftSp: number = 0;
  consumedBonusSp: number = 0;
  consumedPermanentSp: number = 0;
  signedDates: string = '[]';        // ★ 0.277.0：已签日期并集（旧云端行缺字段=undefined 走兜底，零迁移）
  milestoneStreakGranted: number = 0; // ★ 0.277.0：已发里程碑最高档
  iapPackages: string = '[]';        // ★ 0.289.0：充能包账本（union+包级 max 合并）
  rookieDoneJson: string = '[]';     // ★ 0.294.0：新手任务完成 id 并集（并集合并；旧云端行缺字段=undefined 走兜底）
  rookieGrantedJson: string = '[]';  // ★ 0.294.0：新手任务已发放 id 并集（并集合并防跨端重发）
}

function siyiPointsToJson(): string {
  const s = connectSiyiPoints();
  const p = new SiyiRowPayload();
  p.permanentSp = s.permanentSp;
  p.bonusSp = s.bonusSp;
  p.giftSp = s.giftSp;
  p.giftSpExpireAt = s.giftSpExpireAt;
  p.welcomeGranted = s.welcomeGranted;
  p.consumedGiftSp = s.consumedGiftSp;
  p.consumedBonusSp = s.consumedBonusSp;
  p.consumedPermanentSp = s.consumedPermanentSp;
  p.signedDates = s.signedDates;
  p.milestoneStreakGranted = s.milestoneStreakGranted;
  p.iapPackages = s.iapPackages;
  p.rookieDoneJson = s.rookieDoneJson;       // ★ 0.294.0：新手任务两集合随行上行
  p.rookieGrantedJson = s.rookieGrantedJson;
  return JSON.stringify(p);
}

// ★ 0.294.0：新手任务 id 并集解析（坏 JSON 兜底空数组，与 parseSignedDates 同款防御）
function parseRookieIds(v: string): string[] {
  try {
    const arr = JSON.parse(v) as string[];
    return Array.isArray(arr) ? arr : [];
  } catch (_e) {
    return [];
  }
}

// ★ 0.248.4：cfg:siyi-points 下行合并——三池+到期戳各自取 max、welcomeGranted 取或
//   （当前 SP 只有发放没有消耗，单调增=max 安全；缺字段 undefined 比较恒 false 天然兜底）
//   ★ 0.248.7：三消耗字段同 max（发放/消耗双侧单调——扣减不会被对端旧值回填复活）
function mergeSiyiPointsRow(v: string | undefined): void {
  if (v === undefined) {
    return;
  }
  let cloud: SiyiRowPayload | null = null;
  try {
    cloud = JSON.parse(v) as SiyiRowPayload;
  } catch (_e) {
    return; // 云端坏行——保持本地，flush 上行好值自愈
  }
  const s = connectSiyiPoints();
  let changed = false;
  if (cloud.permanentSp > s.permanentSp) {
    s.permanentSp = cloud.permanentSp;
    changed = true;
  }
  if (cloud.bonusSp > s.bonusSp) {
    s.bonusSp = cloud.bonusSp;
    changed = true;
  }
  if (cloud.giftSp > s.giftSp) {
    s.giftSp = cloud.giftSp;
    changed = true;
  }
  if (cloud.giftSpExpireAt > s.giftSpExpireAt) {
    s.giftSpExpireAt = cloud.giftSpExpireAt;
    changed = true;
  }
  if (cloud.welcomeGranted && !s.welcomeGranted) {
    s.welcomeGranted = true;
    changed = true;
  }
  if (cloud.consumedGiftSp > s.consumedGiftSp) {
    s.consumedGiftSp = cloud.consumedGiftSp;
    changed = true;
  }
  if (cloud.consumedBonusSp > s.consumedBonusSp) {
    s.consumedBonusSp = cloud.consumedBonusSp;
    changed = true;
  }
  if (cloud.consumedPermanentSp > s.consumedPermanentSp) {
    s.consumedPermanentSp = cloud.consumedPermanentSp;
    changed = true;
  }
  // ★ 0.277.0：签到标记下行合并——已签日期取并集（跨端接续/幂等的数据源），
  //   里程碑档取 max（单调递增防重发）。云端行并集更大才落盘（幂等收敛，防 flush 上行乒乓）。
  const mergedDates = mergeSignedDates(parseSignedDates(s.signedDates), parseSignedDates(cloud.signedDates));
  if (mergedDates.length > parseSignedDates(s.signedDates).length) {
    s.signedDates = JSON.stringify(mergedDates);
    changed = true;
  }
  if (cloud.milestoneStreakGranted > s.milestoneStreakGranted) {
    s.milestoneStreakGranted = cloud.milestoneStreakGranted;
    changed = true;
  }
  // ★ 0.289.0 充能包账本下行合并：按 tok 并集 + 每包 cons/ref 取 max（发放幂等=token 唯一，
  //   consumeSiyiSp 幂等入口挡双建包；cons 单调与池级 consumedPermanentSp 同语义）
  const localPkgs = parseIapPackages(s.iapPackages);
  const cloudPkgs = parseIapPackages(cloud.iapPackages);
  let pkgsChanged = false;
  for (let ci = 0; ci < cloudPkgs.length; ci++) {
    const cp = cloudPkgs[ci];
    let found = false;
    for (let li = 0; li < localPkgs.length; li++) {
      if (localPkgs[li].tok === cp.tok) {
        found = true;
        if (cp.cons > localPkgs[li].cons) {
          localPkgs[li].cons = cp.cons;
          pkgsChanged = true;
        }
        if (cp.ref > localPkgs[li].ref) {
          localPkgs[li].ref = cp.ref;
          pkgsChanged = true;
        }
        // ★ 0.291.0 锁包状态取 max（frozenUntil 单调大值=续锁；时间戳自然过期=自动解锁，
        //   解锁无需回退同步——对端到期同样判过期，无乒乓）
        if (cp.frozenUntil > localPkgs[li].frozenUntil) {
          localPkgs[li].frozenUntil = cp.frozenUntil;
          pkgsChanged = true;
        }
        break;
      }
    }
    if (!found) {
      localPkgs.push(cp);
      pkgsChanged = true;
    }
  }
  if (pkgsChanged) {
    s.iapPackages = JSON.stringify(localPkgs);
    changed = true;
  }
  // ★ 0.294.0 新手任务两集合下行合并——id 并集（跨端接续/防重发；云端并集更大才落盘防乒乓）
  const localDone = parseRookieIds(s.rookieDoneJson);
  const cloudDone = parseRookieIds(cloud.rookieDoneJson);
  let rookieChanged = false;
  for (let di = 0; di < cloudDone.length; di++) {
    if (localDone.indexOf(cloudDone[di]) < 0) {
      localDone.push(cloudDone[di]);
      rookieChanged = true;
    }
  }
  if (rookieChanged) {
    s.rookieDoneJson = JSON.stringify(localDone);
    changed = true;
  }
  const localGranted = parseRookieIds(s.rookieGrantedJson);
  const cloudGranted = parseRookieIds(cloud.rookieGrantedJson);
  let grantedChanged = false;
  for (let gi = 0; gi < cloudGranted.length; gi++) {
    if (localGranted.indexOf(cloudGranted[gi]) < 0) {
      localGranted.push(cloudGranted[gi]);
      grantedChanged = true;
    }
  }
  if (grantedChanged) {
    s.rookieGrantedJson = JSON.stringify(localGranted);
    changed = true;
  }
  if (changed) {
    scheduleRowFlush();
  }
}

// ---- 显式墓碑入口（★ 0.230.1：del 行唯一合法出生通道——用户显式删除操作专用） ----
// 词/卡/夹全部删除路径（单删/批删/夹删/级联删/清空根夹）已带 id 列表汇入下列函数；
// 节点/Tab 删除由 BBTreeCanvas 显式调用（0.228.x 旧案靠 flush 差集自动出生=四连环根凶，已废）
// 墓碑 id=裸 id（无域前缀，各域 id 生成方案天然不撞车）；本地实体行的清理由 reconcile
// del 分支完成（del 新戳每次压制+deleteRowLocal），此处不碰域前缀（级联列表混夹/词/卡）
const TOMB_ROW_PREFIXES: string[] = ['node:', 'tab:', 'word:', 'card:', 'wfolder:', 'kfolder:'];

export function noteBankMutation(): void {
  scheduleRowFlush(); // 词/卡/夹非删除变更（增/改/移动/复制）统一防抖上行
}

export function recordTombstones(ids: string[]): void {
  for (const id of ids) {
    writeTombstone(id); // del:<id> 行（绕首拉闸门——显式意图任何时刻落库都安全）
    tombstonedIds.add(id); // ★ 0.230.1：会话墓碑表注册（flush 永不写行）
    for (const pre of TOMB_ROW_PREFIXES) {
      rowCache.delete(pre + id); // cache 除账（防残留缓存令 flush 误判）
    }
  }
  scheduleRowFlush(); // 删除常伴随归属/mtime 变更，其余行照常 flush
}

export function recordWordTomb(ids: string[]): void {
  recordTombstones(ids); // 词 + 单词库文件夹共用（裸 id 域自明）
}

export function recordKnowledgeTomb(ids: string[]): void {
  recordTombstones(ids); // 卡 + 知识库文件夹共用
}

export function recordNodeTomb(ids: string[]): void {
  recordTombstones(ids); // ★ 0.230.1 新增：气泡节点（含子树全集 id）
}

export function recordTabTomb(ids: string[]): void {
  recordTombstones(ids); // ★ 0.230.1 新增：选项卡
}

// ---- 启动接线（EntryAbility.onWindowStageCreate 调用） ----
export function setupCloudDownlink(): void {
  registerCloudRowsReady(reconcileCloudRows);
  registerRowFlush(scheduleRowFlush);
  // ★ 0.230.1：首拉闸门每会话再武装——原持久化 true 跨会话存活，重启后首拉未完成
  //   flush 即上行本地旧值（残缺 RDB 态 LWW 压过云端新值=Bug A 放大器）；闸门改为
  //   「本会话内完成一次无缺片 reconcile」才开（见 reconcileWithRows）
  connectCloudSyncArbiter().rowInitDone = false;
}

// ★ 0.165.2：按当前模式的权威池重建工作区（复用 0.151 applyCanvasModeSwitch 的搬移模式）——
// flat：工作区 = 平铺池全部树；tabs：工作区 = activeTab 的树。
// 清空 current（旧选中节点在新工作区可能失效）。
// ★ 0.223.0：needsRelayout → needsCloudRedraw——下行重建**绝不再 autoLayout 重排**：
//   对端同步来的节点坐标是真相（0.223.0 前旧链路把坐标全丢重排=「样式和PC不一样」+重排
//   saveTree 又上行污染对端布局的乒乓毁灭链）；BBTreeCanvas 消费 needsCloudRedraw 做
//   保坐标的 redrawEdges + fitViewport，画布不在栈时由 onShown 兜底。
function refreshWorkspaceFromPools(): void {
  const store = AppStorageV2.connect(BubbleTree, 'bubble-tree', () => new BubbleTree()) as BubbleTree;
  const current = AppStorageV2.connect(CurrentBubble, 'current-bubble',
    () => new CurrentBubble()) as CurrentBubble;
  const modeStore = connectCanvasMode();
  // ★ 0.232.0：记录重建前的选中（云同步下行重建工作区不得打断正在浏览的对话）
  const prevId = current.nodeID;
  const prevX = current.bubbleX;
  const prevY = current.bubbleY;
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
  // ★ 0.244.0：nodeList 整体替换为新对象——渲染世代 +1（画布 ForEach key 拼入 epoch，
  //   强制条目重建重新捕获新对象；否则条目闭包持有旧对象渲染冻结旧坐标，气泡重叠+连线悬空）
  store.rebuildEpoch++;
  // ★ 0.232.0：旧实现无条件清空 current.nodeID——手机回前台拉同步（0.223.0 onForeground
  //   forceCloudSyncNow）触发重建 → 正开着的 ChatPage 消息绑定瞬间清零，用户必须退回画布
  //   重进（用户实测硬伤）。修正：节点在新工作区仍存在则保留选中+坐标（bubbleX/Y 是创建
  //   子气泡的画布坐标基准，一并保留）；真被远端删除/不在池中才清空。
  let kept = false;
  if (prevId.length > 0) {
    for (let i = 0; i < store.nodeList.length; i++) {
      if (store.nodeList[i].nodeID === prevId) {
        kept = true;
        break;
      }
    }
  }
  if (kept) {
    current.nodeID = prevId;
    current.bubbleX = prevX;
    current.bubbleY = prevY;
  } else {
    current.nodeID = '';
    current.bubbleX = 0;
    current.bubbleY = 0;
  }
  store.needsCloudRedraw = true;
}
