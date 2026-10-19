// ============================================================
// ProfileModel.ets — ★ 0.265.0 记忆引擎一期（WP1 画像观察行 + WP2 分支摘要头 +
//   WP4 token 埋点 + WP5 深度记忆总开关 + Q1 隐式调用降频）
// ============================================================
// 任务书：docs/0.165+/0.263.0 记忆引擎一期执行任务书.md（版本号顺延 0.265.0——
//   0.263.0/0.264.0 已被退出清空/协议合规占用，用户拍板）
// 产品北极星：同一模型下用户聊得越久越觉得「AI 更懂我」——S1 跨会话连续性 +
//   S2 跨分支情境感知。
//
// 存储（全部 PersistenceV2 全新 key，发布后禁改）：
//   - 'profile-observations-v1'：画像观察行（只追加不删除；supersededBy 标记演变）
//   - 'memory-pref-v1'：深度记忆总开关（WP5 自救开关，默认开）
//   - 'memory-inject-stats-v1'：注入 token 埋点（14 天滚动，Q6 两周观察数据源）
//
// 纪律：
//   - @ObservedV2 实例禁直接 JSON.stringify（0.205.4 铁律）——全部走 plain 映射
//   - 摘要/记忆类 LLM 调用失败一律静默降级（沿用旧数据），绝不阻断对话
//   - 多提供商约束：无 function calling / 无 embedding 依赖
//   - ArkTS 禁 delete；Record 字面量程序化构建
// ============================================================

import { PersistenceV2 } from '@kit.ArkUI';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BubbleNode, BubbleTree, ChatMessage, ApiConfig, generateMessageId, connectApiConfig } from './ChatModel';
import { streamChat } from '../utils/ApiClient';
import { PROFILE_OBSERVE_PROMPT, BRANCH_HEAD_PROMPT } from './Prompts';

// ============================================================
// WP1：画像观察行（任务书 §4.1 定案，字段名一字不差）
// ============================================================
@ObservedV2
export class ProfileObservation {
  @Trace observationID: string = '';   // 唯一ID（generateMessageId 同款规则），未来云同步行级仲裁主键
  @Trace kind: string = 'preference'; // identity / goal / preference / emotion 四枚举
  @Trace content: string = '';        // 一句话观察（如「偏好简洁的推导步骤」）
  @Trace sourceNodeID: string = '';   // 来源气泡节点ID（画像↔树溯源桥梁）
  @Trace supersededBy: string = '';   // 被哪条观察取代（空=生效中）；偏好演变轨迹=S4 数据链
  @Trace createdAt: number = 0;
  @Trace updatedAt: number = 0;

  constructor(observationID: string, kind: string, content: string, sourceNodeID: string,
    supersededBy: string, createdAt: number, updatedAt: number) {
    this.observationID = observationID;
    this.kind = kind;
    this.content = content;
    this.sourceNodeID = sourceNodeID;
    this.supersededBy = supersededBy;
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
  }
}

// plain 映射（@ObservedV2 禁直接 stringify——0.205.4）
interface SerializedObservation {
  observationID: string;
  kind: string;
  content: string;
  sourceNodeID: string;
  supersededBy: string;
  createdAt: number;
  updatedAt: number;
}
interface ObservationData {
  observations: SerializedObservation[];
}
// Q1 隐式调用日计数（超 20 次/日画像降频为每天一次）
interface ImplicitDailyData {
  date: string;
  count: number;
  dailyDone: boolean; // 降频模式下当天是否已做过画像更新
}

@ObservedV2
export class ProfileStore {
  @Trace raw: string = '{"observations":[]}';
  @Trace implicitDailyJson: string = '{"date":"","count":0,"dailyDone":false}';
}

export function connectProfileObservations(): ProfileStore {
  return PersistenceV2.connect(ProfileStore, 'profile-observations-v1', () => new ProfileStore()) as ProfileStore;
}

function todayKey(): string {
  const d = new Date();
  const m = `${d.getMonth() + 1}`.padStart(2, '0');
  const day = `${d.getDate()}`.padStart(2, '0');
  return `${d.getFullYear()}-${m}-${day}`;
}

// 读取全部观察行（解析失败返回空数组——坏数据兜底不崩）
export function getObservations(store: ProfileStore): ProfileObservation[] {
  try {
    const data = JSON.parse(store.raw) as ObservationData;
    const list: ProfileObservation[] = [];
    if (data.observations !== undefined && data.observations !== null) {
      for (let i = 0; i < data.observations.length; i++) {
        const o = data.observations[i];
        list.push(new ProfileObservation(o.observationID, o.kind, o.content, o.sourceNodeID,
          o.supersededBy, o.createdAt, o.updatedAt));
      }
    }
    return list;
  } catch (_e) {
    return [];
  }
}

function writeObservations(store: ProfileStore, list: ProfileObservation[]): void {
  const plainList: SerializedObservation[] = [];
  for (let i = 0; i < list.length; i++) {
    const o = list[i];
    plainList.push({
      observationID: o.observationID,
      kind: o.kind,
      content: o.content,
      sourceNodeID: o.sourceNodeID,
      supersededBy: o.supersededBy,
      createdAt: o.createdAt,
      updatedAt: o.updatedAt
    });
  }
  store.raw = JSON.stringify({ observations: plainList } as ObservationData);
}

// 追加观察行（只追加、不删除——Schema 铁律）
export function appendObservation(store: ProfileStore, obs: ProfileObservation): void {
  const list = getObservations(store);
  list.push(obs);
  writeObservations(store, list);
}

// 偏好演变标记：旧行打 supersededBy（禁 delete——行保留可溯源）
export function supersedeObservation(store: ProfileStore, oldID: string, newID: string): void {
  if (oldID.length === 0) {
    return;
  }
  const list = getObservations(store);
  for (let i = 0; i < list.length; i++) {
    if (list[i].observationID === oldID && list[i].supersededBy === '') {
      list[i].supersededBy = newID;
      list[i].updatedAt = Date.now();
    }
  }
  writeObservations(store, list);
}

// 聚合视图：过滤生效行（supersededBy 空）、按 kind 分组、createdAt 稳定排序（稳定排序保证前缀缓存命中）
export function buildCardView(store: ProfileStore): string {
  const active: ProfileObservation[] = [];
  const all = getObservations(store);
  for (let i = 0; i < all.length; i++) {
    if (all[i].supersededBy === '') {
      active.push(all[i]);
    }
  }
  if (active.length === 0) {
    return ''; // 画像卡为空（新用户）时跳过注入
  }
  active.sort((a: ProfileObservation, b: ProfileObservation): number => a.createdAt - b.createdAt);
  const kindOrder: string[] = ['identity', 'goal', 'preference', 'emotion'];
  const lines: string[] = ['[用户画像]'];
  for (let k = 0; k < kindOrder.length; k++) {
    for (let i = 0; i < active.length; i++) {
      if (active[i].kind === kindOrder[k]) {
        lines.push(`- ${active[i].kind}: ${active[i].content}`);
      }
    }
  }
  return lines.join('\n');
}

// 生效观察行数（GSD 清空入口展示用）
export function activeObservationCount(store: ProfileStore): number {
  const all = getObservations(store);
  let n = 0;
  for (let i = 0; i < all.length; i++) {
    if (all[i].supersededBy === '') {
      n++;
    }
  }
  return n;
}

// 清空画像（WP5/Q4 用户数据主权入口——设置页显式操作；系统行为层面只增不删不冲突）
export function clearAllObservations(store: ProfileStore): void {
  store.raw = '{"observations":[]}';
}

// ============================================================
// Q1：隐式调用计数与画像降频（超 20 次/日 → 画像更新降为每天一次）
// ============================================================
function readImplicitDaily(store: ProfileStore): ImplicitDailyData {
  try {
    const d = JSON.parse(store.implicitDailyJson) as ImplicitDailyData;
    if (d.date === todayKey()) {
      return d;
    }
  } catch (_e) {
    // 坏数据兜底：视同新一天
  }
  return { date: todayKey(), count: 0, dailyDone: false };
}

function writeImplicitDaily(store: ProfileStore, d: ImplicitDailyData): void {
  store.implicitDailyJson = JSON.stringify(d);
}

// 每次隐式 LLM 调用（画像更新/摘要头 flush）发起时 +1
export function recordImplicitCall(store: ProfileStore): void {
  const d = readImplicitDaily(store);
  d.count += 1;
  writeImplicitDaily(store, d);
}

// 画像更新是否应降频跳过：超 20 次/日 且 当天已做过一次画像更新
export function shouldThrottleProfile(store: ProfileStore): boolean {
  const d = readImplicitDaily(store);
  return d.count > 20 && d.dailyDone;
}

// 画像更新成功后打点（降频模式下当天不再更新）
export function markProfileUpdatedToday(store: ProfileStore): void {
  const d = readImplicitDaily(store);
  d.dailyDone = true;
  writeImplicitDaily(store, d);
}

// ============================================================
// WP5：深度记忆总开关（默认开；关闭=不注入不触发、数据保留——记忆系统出 bug 的用户自救开关）
// ============================================================
@ObservedV2
export class MemoryPrefStore {
  @Trace memoryMode: string = 'on'; // 'on' / 'off'
}

export function connectMemoryPref(): MemoryPrefStore {
  return PersistenceV2.connect(MemoryPrefStore, 'memory-pref-v1', () => new MemoryPrefStore()) as MemoryPrefStore;
}

export function isMemoryOn(): boolean {
  return connectMemoryPref().memoryMode === 'on';
}

// ============================================================
// WP4：注入 token 埋点（key 'memory-inject-stats-v1'，14 天滚动；不走埋点上报零 LLM 成本）
// ============================================================
export interface InjectStatDay {
  date: string;      // 'YYYY-MM-DD'
  profileTok: number; // 画像段累计
  pathTok: number;    // 路径段累计
  headsTok: number;   // 摘要头段累计
  summaryTok: number; // 历史摘要段累计
}
interface InjectStatsData {
  records: InjectStatDay[];
}

@ObservedV2
export class MemoryInjectStatsStore {
  @Trace raw: string = '{"records":[]}';
}

export function connectMemoryInjectStats(): MemoryInjectStatsStore {
  return PersistenceV2.connect(MemoryInjectStatsStore, 'memory-inject-stats-v1',
    () => new MemoryInjectStatsStore()) as MemoryInjectStatsStore;
}

// token 估算（与 buildBranchMessageList 同口径：中文≈1字1.5token+每条固定开销50）
export function memoryTokenEstimate(text: string): number {
  return Math.ceil(text.length * 1.5) + 50;
}

// 分段统计落库（按天聚合累加；>14 天的旧行滚动丢弃）
export function recordMemoryInjectStats(store: MemoryInjectStatsStore, profileTok: number,
  pathTok: number, headsTok: number, summaryTok: number): void {
  try {
    const data = JSON.parse(store.raw) as InjectStatsData;
    const records: InjectStatDay[] = (data.records !== undefined && data.records !== null) ? data.records : [];
    const key = todayKey();
    let entry: InjectStatDay | undefined = undefined;
    for (let i = 0; i < records.length; i++) {
      if (records[i].date === key) {
        entry = records[i];
        break;
      }
    }
    if (entry === undefined) {
      entry = { date: key, profileTok: 0, pathTok: 0, headsTok: 0, summaryTok: 0 };
      records.push(entry);
    }
    entry.profileTok += profileTok;
    entry.pathTok += pathTok;
    entry.headsTok += headsTok;
    entry.summaryTok += summaryTok;
    // 14 天滚动：按日期排序后只保留最近 14 行
    records.sort((a: InjectStatDay, b: InjectStatDay): number => a.date < b.date ? 1 : (a.date > b.date ? -1 : 0));
    const kept: InjectStatDay[] = records.slice(0, 14);
    store.raw = JSON.stringify({ records: kept } as InjectStatsData);
  } catch (_e) {
    // 埋点失败静默（统计缺一天可接受）
  }
}

// ============================================================
// WP1：画像更新触发（隐式 LLM 调用——每 8 轮用户消息或会话结束）
// ============================================================
// 输入=旧画像卡（带 observationID 供 supersedes）+ 本段新增对话；输出=新观察行 JSON 数组。
// 识别到偏好变化：新增新行 + 对旧行调 supersedeObservation（LLM 输出 supersedes 字段）。
// 失败降级：解析失败/调用失败 → 静默沿用旧画像，下轮重试。
export function updateProfileFromConversation(store: ProfileStore, cfg: ApiConfig,
  sourceNodeID: string, recentMessages: ChatMessage[]): void {
  if (!isMemoryOn() || recentMessages.length === 0 || shouldThrottleProfile(store)) {
    return;
  }
  recordImplicitCall(store);
  const all = getObservations(store);
  const cardLines: string[] = [];
  for (let i = 0; i < all.length; i++) {
    if (all[i].supersededBy === '') {
      cardLines.push(`${all[i].observationID}|${all[i].kind}|${all[i].content}`);
    }
  }
  const dialogLines: string[] = [];
  const start = Math.max(0, recentMessages.length - 16); // 最近对话截尾（控制隐式调用成本）
  for (let i = start; i < recentMessages.length; i++) {
    const m = recentMessages[i];
    if (m.content.length === 0 || m.content === 'AI正在回复中，请稍候...' || m.content === 'AI 正在深度思考中...') {
      continue;
    }
    dialogLines.push(`${m.role === 'user' ? '用户' : 'AI'}: ${m.content.length > 400 ? m.content.substring(0, 400) : m.content}`);
  }
  if (dialogLines.length === 0) {
    return;
  }
  const sysContent = `${PROFILE_OBSERVE_PROMPT}\n\n[当前画像（observationID|kind|content，空=新用户）]\n${cardLines.length > 0 ? cardLines.join('\n') : '（无）'}\n\n[本段新增对话]\n${dialogLines.join('\n')}`;
  const msgs: ChatMessage[] = [
    new ChatMessage(generateMessageId(), 'system', sysContent)
  ];
  let out = '';
  streamChat(
    msgs,
    cfg,
    (chunk: string) => { out += chunk; },
    (_inTok: number, _outTok: number, _cached: number) => {
      applyProfileResult(store, out, sourceNodeID); // 解析+落库（内部静默降级）
    },
    (_err: string) => {
      // 调用失败静默（下轮重试）
    },
    undefined,
    'AI 记忆整理',
    true // ★ Q1 implicit 标记位：隐式调用暂不扣 SP，预留未来计费开关
  );
}

// 容错解析画像输出（沿用 AiClient JSON 容错模式：剥 ``` 围栏、截首尾括号）
function applyProfileResult(store: ProfileStore, out: string, sourceNodeID: string): void {
  try {
    let text = out.trim();
    const fence = text.indexOf('[');
    const fenceEnd = text.lastIndexOf(']');
    if (fence < 0 || fenceEnd <= fence) {
      return; // 无数组结构——静默沿用旧画像
    }
    text = text.substring(fence, fenceEnd + 1);
    const arr = JSON.parse(text) as Record<string, string>[];
    let added = false;
    for (let i = 0; i < arr.length && i < 5; i++) { // 单轮最多采纳 5 条（防 LLM 失控灌水）
      const item = arr[i];
      const kind = String(item['kind'] ?? '');
      const content = String(item['content'] ?? '').trim();
      if (content.length === 0 || content.length > 60) {
        continue; // 超长观察拒收（一句话约束）
      }
      if (kind !== 'identity' && kind !== 'goal' && kind !== 'preference' && kind !== 'emotion') {
        continue; // 四枚举之外拒收
      }
      const now = Date.now();
      const newID = generateMessageId();
      const src = String(item['sourceNodeID'] ?? '') || sourceNodeID; // LLM 未带则回填当前节点
      const obs = new ProfileObservation(newID, kind, content, src, '', now, now);
      appendObservation(store, obs);
      added = true;
      const sup = String(item['supersedes'] ?? '');
      if (sup.length > 0) {
        supersedeObservation(store, sup, newID); // 偏好演变：旧行打标（找不到旧 ID 无害跳过）
      }
    }
    if (added) {
      markProfileUpdatedToday(store); // 降频打点（超 20 次/日时当天不再更新）
    }
  } catch (_e) {
    // 解析失败静默（沿用旧画像）
  }
}

// ============================================================
// WP2：分支摘要头（失活入队 → 闲时批量 flush → 树距离衰减注入）
// ============================================================
// pending 队列（内存态——重启丢失仅意味着下次失活重新评估，幂等无害）
class PendingHeadEntry {
  nodeID: string;
  constructor(nodeID: string) {
    this.nodeID = nodeID;
  }
}
const pendingHeads: PendingHeadEntry[] = [];

// 引擎运行时绑定（ChatPage aboutToAppear 注入；ChatPage 是唯一持树页面）
let boundTree: BubbleTree | null = null;
let boundSaver: (() => void) | null = null;

export function bindMemoryEngine(tree: BubbleTree, saver: () => void): void {
  boundTree = tree;
  boundSaver = saver;
}

// 失活触发：切走/退出时旧节点入队（summaryHead 为空且消息≥10 → 首次生成；
//   已有摘要头且新增≥10 条 → 重新生成）
export function noteInactiveNode(node: BubbleNode | undefined): void {
  if (!isMemoryOn() || node === undefined || node === null) {
    return;
  }
  const validCount = node.messages.length; // 消息总数口径（含占位误差可接受）
  const need = node.summaryHead.length === 0
    ? validCount >= 10
    : (validCount - node.summaryHeadCount >= 10);
  if (!need) {
    return;
  }
  for (let i = 0; i < pendingHeads.length; i++) {
    if (pendingHeads[i].nodeID === node.nodeID) {
      return; // 已在队列（去重）
    }
  }
  pendingHeads.push(new PendingHeadEntry(node.nodeID));
}

// 节点展示标题（nodeTitle 优先；空=首条用户消息截 12 字；再无=未命名分支）
function headTitleOf(node: BubbleNode): string {
  if (node.nodeTitle.trim().length > 0) {
    return node.nodeTitle.trim();
  }
  for (let i = 0; i < node.messages.length; i++) {
    if (node.messages[i].role === 'user' && node.messages[i].content.trim().length > 0) {
      const t = node.messages[i].content.trim();
      return t.length > 12 ? `${t.substring(0, 12)}…` : t;
    }
  }
  return '未命名分支';
}

// 闲时 flush：批量处理 pending（合并为一次 LLM 调用；写回节点字段 + saveTree）
// 返回是否实际发起（供短时任务释放判定）
export async function flushPendingHeads(): Promise<boolean> {
  if (!isMemoryOn() || pendingHeads.length === 0 || boundTree === null) {
    return false;
  }
  const tree = boundTree;
  const cfg = connectApiConfig();
  // 取出队列条目并解析出节点（节点可能已被删除——跳过）
  const nodes: BubbleNode[] = [];
  while (pendingHeads.length > 0) {
    const entry = pendingHeads.shift();
    if (entry === undefined) {
      break;
    }
    const n = tree.nodeList.find((x: BubbleNode): boolean => x.nodeID === entry.nodeID);
    if (n !== undefined && n.messages.length > 0) {
      nodes.push(n);
    }
  }
  if (nodes.length === 0) {
    return false;
  }
  recordImplicitCall(connectProfileObservations());
  // 组装批量输入：每分支最近 12 条有效消息
  const blockLines: string[] = [];
  for (let i = 0; i < nodes.length; i++) {
    const n = nodes[i];
    const msgs: string[] = [];
    const start = Math.max(0, n.messages.length - 12);
    for (let j = start; j < n.messages.length; j++) {
      const m = n.messages[j];
      if (m.content.length === 0 || m.content === 'AI正在回复中，请稍候...' || m.content === 'AI 正在深度思考中...') {
        continue;
      }
      msgs.push(`${m.role === 'user' ? '用户' : 'AI'}: ${m.content.length > 300 ? m.content.substring(0, 300) : m.content}`);
    }
    if (msgs.length > 0) {
      blockLines.push(`【分支${i + 1}】\n${msgs.join('\n')}`);
    }
  }
  if (blockLines.length === 0) {
    return false;
  }
  const sysContent = `${BRANCH_HEAD_PROMPT}\n\n共 ${blockLines.length} 个分支：\n\n${blockLines.join('\n\n')}`;
  const msgs: ChatMessage[] = [
    new ChatMessage(generateMessageId(), 'system', sysContent)
  ];
  return new Promise<boolean>((resolve: (v: boolean) => void) => {
    let out = '';
    streamChat(
      msgs,
      cfg,
      (chunk: string) => { out += chunk; },
      (_inTok: number, _outTok: number, _cached: number) => {
        applyHeadsResult(nodes, out);
        resolve(true);
      },
      (_err: string) => {
        // 失败降级：摘要头为空的分支直接跳过（不阻塞；下次失活再入队重试）
        resolve(false);
      },
      undefined,
      'AI 记忆整理',
      true // Q1 implicit 预留位
    );
  });
}

// 批量摘要头结果写回（容错解析；成功一项写一项）
function applyHeadsResult(nodes: BubbleNode[], out: string): void {
  try {
    let text = out.trim();
    const l = text.indexOf('[');
    const r = text.lastIndexOf(']');
    if (l < 0 || r <= l) {
      return;
    }
    text = text.substring(l, r + 1);
    const arr = JSON.parse(text) as Record<string, Object>[];
    for (let i = 0; i < arr.length && i < nodes.length; i++) {
      const item = arr[i];
      const idx = Number(item['index'] ?? (i + 1)) - 1; // 分支序号（1 起；缺省按顺序对位）
      if (idx < 0 || idx >= nodes.length) {
        continue;
      }
      const head = String(item['summaryHead'] ?? '').trim();
      if (head.length === 0 || head.length > 200) {
        continue; // 空或超长拒收
      }
      const tagsRaw = item['topicTags'];
      const tags: string[] = [];
      if (tagsRaw instanceof Array) {
        for (let t = 0; t < tagsRaw.length && t < 5; t++) { // 话题词 0~5 个
          const tag = String(tagsRaw[t]).trim();
          if (tag.length > 0 && tag.length <= 12) {
            tags.push(tag);
          }
        }
      }
      const node = nodes[idx];
      node.summaryHead = head;
      node.topicTags = tags;
      node.summaryHeadCount = node.messages.length; // 失活判据基准（同 historySummaryCount 先例）
    }
    if (boundSaver !== null) {
      try {
        boundSaver(); // 写回节点字段 + saveTree（ChatPage 注入；未注入时字段仍在 @Trace 对象上，下次任何保存自然带上）
      } catch (_e) {
        // 落盘失败静默（下次保存兜底）
      }
    }
  } catch (_e) {
    // 解析失败静默（摘要头跳过，不阻塞）
  }
}

// 树距离衰减注入（任务书 WP2.3：距离1 完整行 / 距离2 标题+话题词 / ≥3 不注入；
//   总预算 ≤3000 token 超则裁远端）
export function buildSiblingHeadsContext(tree: BubbleTree, currentNode: BubbleNode): string {
  if (!isMemoryOn()) {
    return '';
  }
  // 当前节点父链（根→当前），含各节点深度
  const chainIDs: string[] = [];
  let cursor: BubbleNode | undefined = currentNode;
  while (cursor !== undefined && cursor !== null) {
    chainIDs.unshift(cursor.nodeID);
    if (cursor.parentID === null) {
      break;
    }
    cursor = tree.nodeList.find((n: BubbleNode): boolean => n.nodeID === cursor!.parentID);
  }
  if (chainIDs.length === 0) {
    return '';
  }
  const depthOf = (id: string): number => chainIDs.indexOf(id); // 链上深度（-1=不在链上）
  interface HeadRow {
    dist: number;   // 当前节点到分叉点的边数（1=同父兄弟 2=叔伯辈）
    line: string;   // 注入行文本
    tokens: number; // 行 token 估算
  }
  const rows: HeadRow[] = [];
  for (let i = 0; i < tree.nodeList.length; i++) {
    const x = tree.nodeList[i];
    if (depthOf(x.nodeID) >= 0) {
      continue; // 当前路径上的节点（含祖先与自身）不注入
    }
    if (x.summaryHead.length === 0 && x.topicTags.length === 0) {
      continue; // 无摘要头数据直接跳过（失败降级不阻塞）
    }
    // 找 LCA：沿 x 父链上溯第一个出现在当前链上的节点
    let walker: BubbleNode | undefined = x;
    let dist = -1;
    let guard = 0;
    while (walker !== undefined && walker !== null && guard < 10000) {
      guard++;
      const d = depthOf(walker.nodeID);
      if (d >= 0) {
        dist = chainIDs.length - 1 - d; // 当前节点到 LCA 的边数
        break;
      }
      if (walker.parentID === null) {
        break;
      }
      walker = tree.nodeList.find((n: BubbleNode): boolean => n.nodeID === walker!.parentID);
    }
    if (dist !== 1 && dist !== 2) {
      continue; // 距离 ≥3 不注入（dist≤0 理论不出现——防御跳过）
    }
    const title = headTitleOf(x);
    const tagText = x.topicTags.length > 0 ? ` [${x.topicTags.join('/')}]` : '';
    const line = dist === 1
      ? `- ${title}：${x.summaryHead}${tagText}`       // 距离1：标题+一句话摘要+话题词
      : `- ${title}${tagText}`;                        // 距离2：仅标题+话题词
    rows.push({ dist: dist, line: line, tokens: memoryTokenEstimate(line) });
  }
  if (rows.length === 0) {
    return '';
  }
  // 总预算 ≤3000 token，超则裁远端（距离 2 先裁，再裁距离 1 中 token 最大者）
  rows.sort((a: HeadRow, b: HeadRow): number => a.dist - b.dist); // 近的排前（稳定保留）
  let total = 0;
  for (let i = 0; i < rows.length; i++) {
    total += rows[i].tokens;
  }
  while (total > 3000 && rows.length > 1) {
    const dropped = rows.pop(); // 弹最远端
    if (dropped !== undefined) {
      total -= dropped.tokens;
    }
  }
  return `[相关分支背景]\n${rows.map((r: HeadRow): string => r.line).join('\n')}`;
}

// ============================================================
// Q9：Background Tasks Kit 短时任务（WP2.2——退后台瞬间申请续跑本轮摘要，
//   防切后台被挂起导致下次无摘要头；结束即取消）
// ============================================================
export function flushHeadsOnBackground(): void {
  if (pendingHeads.length === 0) {
    return;
  }
  let delayId = -1;
  try {
    const info = backgroundTaskManager.requestSuspendDelay('dagai-memory-summary', () => {
      // 超时前回调（6s 预警）——无需清理（flush 本身幂等、写回失败静默降级）
    });
    delayId = info.requestId;
  } catch (_e) {
    // 申请失败照常 flush（前台不受影响；后台最坏被挂起，下次失活再入队）
  }
  flushPendingHeads().then((_done: boolean) => {
    if (delayId >= 0) {
      try {
        backgroundTaskManager.cancelSuspendDelay(delayId); // 结束即取消（短时任务不留挂）
      } catch (_e) {
        // 取消失败静默（系统超时自动回收）
      }
    }
  }).catch(() => {
    if (delayId >= 0) {
      try {
        backgroundTaskManager.cancelSuspendDelay(delayId);
      } catch (_e) {
        // 静默
      }
    }
  });
}
