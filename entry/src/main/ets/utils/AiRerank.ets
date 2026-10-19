// ============================================================
// ★ 0.268.0 司忆区 AI 智慧排序（rerank）引擎
// ============================================================
// 任务书《0.268.0 司忆区AI智慧排序（终稿·交开发）》照单施工。
// 数据流：用户发送问题时并行预触发（fire-and-forget，照抄 ProfileModel 隐式调用先例），
// AI 回复完成渲染司忆区时消费结果；失败/超时/离线/超限一律静默兜底本地序，用户零感知。
// 红线：纯只读视图层——不改 reviewCount/nextReviewAt/strength，不落任何持久化数据。
// 护栏：日上限 20 次（两库合计，内存计数重启清零可接受）；单请求 3s 超时 Abort；
//       无 apiKey 自动休眠；AI_RERANK_ENABLED=false 全局关停（编译期常量，出问题改 false 即可）。
import { WordItem } from '../common/WordModel';
import { KnowledgeCard, parseTags } from '../common/KnowledgeModel';
import { ApiConfig, ChatMessage, generateMessageId } from '../common/ChatModel';
import { streamChat, StreamController } from './ApiClient';
import { RERANK_PROMPT } from '../common/Prompts';
import { trackAuto } from './TrackUtil';

// 一期不加用户开关、零新持久化 key（任务书 Q8 终裁）——编译期常量即全局关停阀
export const AI_RERANK_ENABLED: boolean = true;
const AI_RERANK_TIMEOUT_MS: number = 3000;      // 单请求 3s 超时（附属区不值得久等）
const AI_RERANK_DAILY_LIMIT: number = 20;       // 日上限（两库合计一次重排记 1 次）
const AI_RERANK_MIN_CANDIDATES: number = 4;     // 候选 <4 条直接本地序不调 AI
const AI_RERANK_POOL_SIZE: number = 20;         // 候选池=本地全序前 20 条

// 重排结果（按 messageId 缓存，与 reviewCache 同生命周期=会话级；id 存储防云同步整库
// 重建后引用失配——0.248.6 教训：缓存条目一律按 id 接回新对象）
class RerankResult {
  orderedWordIds: string[] = []; // 空=词库未成功/未触发（走本地序）
  orderedCardIds: string[] = []; // 空=卡库未成功/未触发
}

// 模块级缓存 + 日计数（内存态；重启清零=该消息回本地序，可接受）
const rerankCache: Map<string, RerankResult> = new Map();
let rerankDayKey: string = '';
let rerankDayCount: number = 0;

function rerankTodayKey(now: number): string {
  const d = new Date(now);
  const m = d.getMonth() + 1;
  const day = d.getDate();
  return `${d.getFullYear()}-${m < 10 ? '0' + m : m}-${day < 10 ? '0' + day : day}`;
}

// ── 消费接口（ChatPage 司忆区渲染调用） ──
export function getRerankWordIds(messageId: string): string[] {
  const r = rerankCache.get(messageId);
  return r === undefined ? [] : r.orderedWordIds;
}

export function getRerankCardIds(messageId: string): string[] {
  const r = rerankCache.get(messageId);
  return r === undefined ? [] : r.orderedCardIds;
}

// ── 解析侧纯函数（hypium 断言覆盖，任务书 §五解析规则） ──
// 正则提取 JSON 序号数组 → 过滤越界（<1 或 >N）→ 去重 → 缺失序号按本地序（升序）补尾；
// 任何异常 / 无数组结构 = 返回空数组（调用方兜底本地序）。
export function parseRerankOrder(text: string, total: number): number[] {
  try {
    if (total <= 0) {
      return [];
    }
    const m = /\[[\d\s,，]+\]/.exec(text);
    if (m === null) {
      return [];
    }
    const raw = m[0];
    const parts = raw.split(/[^0-9]+/);
    const seen: number[] = [];
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].length === 0) {
        continue;
      }
      const n = parseInt(parts[i]);
      if (isNaN(n) || n < 1 || n > total) {
        continue; // 越界过滤
      }
      if (seen.indexOf(n) < 0) {
        seen.push(n); // 去重（保留首个出现位次）
      }
    }
    if (seen.length === 0) {
      return [];
    }
    // 缺失序号按本地序（数字升序）补尾部
    for (let n = 1; n <= total; n++) {
      if (seen.indexOf(n) < 0) {
        seen.push(n);
      }
    }
    return seen;
  } catch (_e) {
    return [];
  }
}

// 序号数组 → 候选 id 全序（1-based 序号映射 candidateIds；异常兜底=本地序未选中补尾）
export function applyRerankOrder(candidateIds: string[], orderNums: number[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < orderNums.length; i++) {
    const n = orderNums[i];
    if (n >= 1 && n <= candidateIds.length) {
      const id = candidateIds[n - 1];
      if (out.indexOf(id) < 0) {
        out.push(id);
      }
    }
  }
  if (out.length < candidateIds.length) {
    for (let i = 0; i < candidateIds.length; i++) {
      if (out.indexOf(candidateIds[i]) < 0) {
        out.push(candidateIds[i]);
      }
    }
  }
  return out;
}

// 展示批构建（Q1 单卡提权·情境唤醒）：AI 序内非未来卡优先取满一批；未来卡至多 1 张、
// 仅当批未满时进末位（被展示的未来卡沿用现有「未到期不计数不顺延」闸门，调度零改动）。
export function rerankDisplayBatch<T>(aiOrdered: T[], count: number, isFuture: (item: T) => boolean): T[] {
  const nonFuture: T[] = [];
  let futurePick: T | null = null;
  for (let i = 0; i < aiOrdered.length; i++) {
    if (isFuture(aiOrdered[i])) {
      if (futurePick === null) {
        futurePick = aiOrdered[i]; // AI 序中最靠前的未来卡（AI 认为与当前问题最相关）
      }
    } else {
      nonFuture.push(aiOrdered[i]);
    }
  }
  const out: T[] = [];
  for (let i = 0; i < nonFuture.length && out.length < count; i++) {
    out.push(nonFuture[i]);
  }
  if (out.length < count && futurePick !== null) {
    out.push(futurePick); // 末位提权
  }
  return out;
}

// ── 候选行构建（prompt 素材，纯函数可测） ──
export function buildWordCandLine(w: WordItem): string {
  const title = w.fullName.length > 0 ? `${w.word}（${w.fullName}）` : w.word;
  const brief = w.explain.length > 20 ? w.explain.substring(0, 20) : w.explain;
  return `${title}｜${brief}`;
}

export function buildCardCandLine(c: KnowledgeCard, tagsArr: string[]): string {
  const brief = tagsArr.length > 0 ? tagsArr.join(' ') : (c.definition.length > 20 ? c.definition.substring(0, 20) : c.definition);
  return `${c.title}｜${brief}`;
}

// prompt 拼装：{question}（截 200 字）/{topics} 替换 + 候选块占位行替换为真实候选行
export function buildRerankPrompt(question: string, topics: string, candLines: string[]): string {
  const q = question.length > 200 ? question.substring(0, 200) : question;
  const t = topics.trim().length > 0 ? topics.trim() : '（无）';
  let p = RERANK_PROMPT.replace('{question}', q).replace('{topics}', t);
  const ph = p.indexOf('1. {标题}');
  if (ph >= 0) {
    p = p.substring(0, ph) + candLines.join('\n');
  }
  return p;
}

// ── 单库请求（非流式拼接 onDone 文本；3s 超时 Abort；全程静默降级） ──
function requestRerankOrder(question: string, topics: string, candLines: string[], candidateIds: string[],
  cfg: ApiConfig, lib: string, onSettled: (orderedIds: string[]) => void): void {
  const msgs: ChatMessage[] = [new ChatMessage(generateMessageId(), 'system', buildRerankPrompt(question, topics, candLines))];
  let out = '';
  let settled = false;
  let timerId = -1;
  const ctrl: StreamController = streamChat(
    msgs,
    cfg,
    (chunk: string) => {
      out += chunk;
    },
    (_inTok: number, _outTok: number, _cached: number) => {
      if (settled) {
        return;
      }
      settled = true;
      if (timerId >= 0) {
        clearTimeout(timerId);
      }
      const nums = parseRerankOrder(out, candidateIds.length);
      if (nums.length === 0) {
        const pf: Record<string, string> = {};
        pf['r'] = 'fallback';
        pf['lib'] = lib;
        trackAuto('ai_rerank', pf); // 解析失败/空结果=兜底本地序
        onSettled([]);
        return;
      }
      const pok: Record<string, string> = {};
      pok['r'] = 'ok';
      pok['lib'] = lib;
      trackAuto('ai_rerank', pok);
      onSettled(applyRerankOrder(candidateIds, nums));
    },
    (_err: string) => {
      if (settled) {
        return;
      }
      settled = true;
      if (timerId >= 0) {
        clearTimeout(timerId);
      }
      const pe: Record<string, string> = {};
      pe['r'] = 'fallback';
      pe['lib'] = lib;
      trackAuto('ai_rerank', pe); // 调用失败静默（本地序兜底，用户零感知）
      onSettled([]);
    },
    undefined,
    'AI 智慧排序',
    true // ★ implicit=true：隐式调用不扣 SP（0.265.0 Q1 终案先例）
  );
  timerId = setTimeout(() => {
    if (settled) {
      return;
    }
    settled = true;
    ctrl.cancel(); // cancel 后 ApiClient 全回调静默（0.250.0 已核）
    const pt: Record<string, string> = {};
    pt['r'] = 'timeout';
    pt['lib'] = lib;
    trackAuto('ai_rerank', pt);
    onSettled([]);
  }, AI_RERANK_TIMEOUT_MS);
}

// ── 预触发主入口（ChatPage 发送问题处 fire-and-forget 调用） ──
// 单条气泡只触发 1 次（sendMessage 单点挂载天然保证）；换一批复用不重调。
export function triggerAiRerank(messageId: string, question: string, topics: string,
  wordCandidates: WordItem[], cardCandidates: KnowledgeCard[], cfg: ApiConfig,
  onWordReady: () => void, onCardReady: () => void): void {
  if (!AI_RERANK_ENABLED) {
    return; // 编译期关停阀：全局退化为本地序
  }
  const q = question.trim();
  if (q.length === 0) {
    return; // 纯图发送无问题文本——排序无输入
  }
  if (rerankCache.has(messageId)) {
    return; // 同一消息幂等（不重调不重复计数）
  }
  const hasWordJob = wordCandidates.length >= AI_RERANK_MIN_CANDIDATES;
  const hasCardJob = cardCandidates.length >= AI_RERANK_MIN_CANDIDATES;
  if (!hasWordJob && !hasCardJob) {
    return; // 两库候选均 <4 条——直接本地序不调 AI
  }
  if (cfg.apiKey.trim().length === 0) {
    return; // 无 apiKey/离线自动休眠
  }
  const today = rerankTodayKey(Date.now());
  if (rerankDayKey !== today) {
    rerankDayKey = today;
    rerankDayCount = 0;
  }
  if (rerankDayCount >= AI_RERANK_DAILY_LIMIT) {
    return; // 日上限护栏（两库合计 20 次/日）
  }
  rerankDayCount += 1;
  rerankCache.set(messageId, new RerankResult()); // 占位条目（两库结果分头回填）
  if (hasWordJob) {
    const pool = wordCandidates.slice(0, AI_RERANK_POOL_SIZE);
    const ids: string[] = [];
    const lines: string[] = [];
    for (let i = 0; i < pool.length; i++) {
      ids.push(pool[i].id);
      lines.push(`${i + 1}. ${buildWordCandLine(pool[i])}`);
    }
    requestRerankOrder(q, topics, lines, ids, cfg, 'word', (orderedIds: string[]) => {
      const r = rerankCache.get(messageId);
      if (r !== undefined && orderedIds.length > 0) {
        r.orderedWordIds = orderedIds;
        onWordReady();
      }
    });
  }
  if (hasCardJob) {
    const pool = cardCandidates.slice(0, AI_RERANK_POOL_SIZE);
    const ids: string[] = [];
    const lines: string[] = [];
    for (let i = 0; i < pool.length; i++) {
      ids.push(pool[i].id);
      lines.push(`${i + 1}. ${buildCardCandLine(pool[i], parseTags(pool[i].tags))}`);
    }
    requestRerankOrder(q, topics, lines, ids, cfg, 'card', (orderedIds: string[]) => {
      const r = rerankCache.get(messageId);
      if (r !== undefined && orderedIds.length > 0) {
        r.orderedCardIds = orderedIds;
        onCardReady();
      }
    });
  }
}
