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
  @Trace apiKey: string = '';
  @Trace endpoint: string = 'https://ark.cn-beijing.volces.com/api/v3/chat/completions';
  @Trace model: string = 'doubao-seed-2-1-lite-260915'; // ★ 0.131：与 SettingsPage 预置列表第 0 项一致（原 doubao-pro-32k 不在预置列表）
  @Trace audioModel: string = 'seed-tts-2.0'; // ★ 0.139：音频模型资源 ID（语音合成-2.0，openspeech HTTP 单向流端点，官方文档实证）
  @Trace audioVoice: string = 'zh_female_vv_uranus_bigtts'; // ★ 0.139：TTS 音色 ID（2.0 格式；2.0 模型只能用 2.0 音色，设置页不显示音色框）
  @Trace audioEndpoint: string = 'https://openspeech.bytedance.com/api/v3/tts/unidirectional'; // ★ 0.139：TTS 端点（openspeech HTTP 单向流，与 LLM endpoint 相互独立）
  @Trace audioKey: string = ''; // ★ 0.140：TTS 专用 Key（豆包语音控制台新建，与方舟对话 Key 相互独立——两套体系 Key 不通用，0.139 拿方舟 Key 实测 401 Invalid X-Api-Key）
}

// ★ 0.143：连接 API 配置持久化实例——key 从 'api-config' 换为 'api-config-v2'
// 根因：PersistenceV2 磁盘旧快照（0.140 之前创建）没有 audioKey 字段，新增属性写不进旧快照、
// 重启即丢（用户实测：对话 Key 能存、音频 Key 不能存——差异即根因实锤）。换 key 强制重建全量
// 快照（新快照出生即含全部字段），audioKey 从此与 apiKey 同等持久化。工厂函数内读旧 key 数据
// 迁移历史配置（对话 Key/端点/模型等），用户无需重填；audioKey 旧快照从未存成功，需重填一次。
export function connectApiConfig(): ApiConfig {
  return PersistenceV2.connect(ApiConfig, 'api-config-v2', () => {
    const old = PersistenceV2.connect(ApiConfig, 'api-config', () => new ApiConfig()) as ApiConfig;
    const fresh = new ApiConfig();
    fresh.apiKey = old.apiKey;
    fresh.endpoint = old.endpoint;
    fresh.model = old.model;
    fresh.audioModel = old.audioModel;
    fresh.audioVoice = old.audioVoice;
    fresh.audioEndpoint = old.audioEndpoint;
    fresh.audioKey = old.audioKey;
    return fresh;
  }) as ApiConfig;
}

// ★ 0.150：AI 对话偏好（自定义称呼 + 自动鼓励开关）——PersistenceV2 持久化，跨重启保存
// 独立 key 与 ApiConfig 隔离（0.143 教训：往已有磁盘快照的类新增字段会因旧快照缺字段不落盘；
// 全新 key 首次创建即含全部字段，无此坑——与单词库/知识库独立 key 模式一致）
@ObservedV2
export class AiPreference {
  @Trace aiNickname: string = '';          // 自定义称呼（空 = 不添加称呼文本；短/中/长全部回复模式都生效）
  @Trace encourageEnabled: boolean = true; // 自动鼓励开关（默认开启；仅中/长回复生成鼓励，短回复不生成）
}

// ★ 0.150：连接 AI 偏好持久化实例（全新 key，无历史迁移需求）
export function connectAiPreference(): AiPreference {
  return PersistenceV2.connect(AiPreference, 'ai-preference-v1', () => new AiPreference()) as AiPreference;
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

// ★ 0.151-bugfix3：子树结构宽度估算——BFS 按层统计节点数，每层宽 = (count-1)*spacing + 气泡宽 132
// （layoutChildren 均分居中，布局后每层实际宽度即此值；供多根并排时计算树占位）
function subtreeWidth(root: BubbleNode, childrenMap: Map<string, BubbleNode[]>, spacing: number): number {
  let maxWidth = 132; // 单节点（气泡 maxWidth 132）
  let layer: BubbleNode[] = [root];
  while (layer.length > 0) {
    const width = (layer.length - 1) * spacing + 132;
    if (width > maxWidth) {
      maxWidth = width;
    }
    const next: BubbleNode[] = [];
    for (const node of layer) {
      const children = childrenMap.get(node.nodeID);
      if (children) {
        for (const child of children) {
          next.push(child);
        }
      }
    }
    layer = next;
  }
  return maxWidth;
}

// ★ 0.151-bugfix3：多根平铺布局纯函数（从 BBTreeCanvas.autoLayout 提取，单一来源防两份漂移）
// 供两处调用：① BBTreeCanvas.autoLayout（画布重排：新建根 / 切 Tab /「显示全部」等）
//            ② applyCanvasModeSwitch tabs→flat（合并树【先排好再持久化】——修复 bug2：
//               各 Tab 树坐标独立，直接拼接必然重叠；旧版靠 needsRelayout 事后重排，
//               但它是 AppStorageV2 内存态，保存后不关弹窗直接杀应用 / ChatPage 弹窗
//               切模式后直接退出 → 重启后重叠坐标已落盘无人重排）
// 算法：单根保持原 x 只置 y=0（兼容现状）；多根按子树宽度并排 y=0（树间间隙 120）；
//       子节点在父正下方均分居中；末尾统一刷新 parentX/parentY（连线端点）
export function layoutFlatForest(nodeList: BubbleNode[]): void {
  const roots = nodeList.filter((n: BubbleNode) => n.parentID === null);
  if (roots.length === 0) return;

  const horizontalSpacing = 160; // ★ 0.147：气泡加宽（maxWidth 132），同层间距 160 防重叠
  const verticalSpacing = 160;   // 层级间垂直间距

  // 构建父→子映射
  const childrenMap = new Map<string, BubbleNode[]>();
  for (const node of nodeList) {
    if (node.parentID !== null) {
      const children = childrenMap.get(node.parentID) || [];
      children.push(node);
      childrenMap.set(node.parentID, children);
    }
  }

  // ★ 递归布局：子节点在父节点正下方居中排列（0.124）
  const layoutChildren = (parent: BubbleNode, depth: number): void => {
    const children = childrenMap.get(parent.nodeID);
    if (!children || children.length === 0) return;

    // ★ 均分居中排布（0.126）：同层子节点整体居中于父节点正下方
    const childCount = children.length;
    const totalWidth = (childCount - 1) * horizontalSpacing;
    const startX = parent.x - totalWidth / 2;
    for (let i = 0; i < childCount; i++) {
      children[i].x = startX + i * horizontalSpacing;
      children[i].y = (depth + 1) * verticalSpacing;
      layoutChildren(children[i], depth + 1);
    }
  };

  // ★ 0.151：多根支持（需求 2.1「多棵树的根气泡画布同一行对齐并排」）
  if (roots.length === 1) {
    roots[0].y = 0;
    layoutChildren(roots[0], 0);
  } else {
    const treeGap = 120; // 树间额外间隙
    let cursorX = 0;
    for (let r = 0; r < roots.length; r++) {
      const root = roots[r];
      root.x = cursorX;
      root.y = 0;
      layoutChildren(root, 0);
      cursorX += subtreeWidth(root, childrenMap, horizontalSpacing) + treeGap;
    }
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
    // 按根拆树：每个根的子树 = 一个 Tab（互通：树还是那批树，只是换个组织方式）
    const tabs = buildTabsFromNodeList(store.nodeList);
    forest.tabsJson = serializeTabs(tabs);
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
      }
    }
  }
  flag.migrated = true;
}
