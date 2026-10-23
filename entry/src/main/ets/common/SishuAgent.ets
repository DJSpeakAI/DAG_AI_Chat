// SishuAgent.ets — ★ 0.300.0 司枢 Agent 3.0 契约层（三角色流水线：枢机→执笔→御史）
// 全案=《司枢Agent3.0 最终方案-落码任务书》（V2.1 定稿）；本文=执行契约一等公民数据结构。
// 铁律（任务书 §二/§八）：
//   1. 契约是会话级临时数据——不持久化、不进 ChatMessage Schema、不碰持久化 key；
//   2. 防契约污染：交执笔前必须经 buildContractBrief 压缩为纯文本指令；
//   3. 上下文物理隔离：枢机/御史过程数据绝不写进对话历史 messages。
import { PlanSection, PlanHook } from '../utils/MdInline';
import { AppStorageV2 } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

// 反问题目（枢机产出，1~3 题；每题 2~4 选项+自定义行由 UI 层固定提供）
export class ClarifyQuestion {
  q: string = '';
  options: string[] = [];
  multi: boolean = false; // false=单选（可换选）/ true=多选（可增减）
}

// 执行契约（枢机产出，执笔与御史只消费契约）
export class TaskContract {
  taskType: string = 'analysis'; // closed / analysis / deliverable / retrieval / creative
  form: string = 'analysis';     // analysis=章节长文 / deliverable=可复制成品
  genre: string = '';            // 体裁：论坛帖/邮件/文档/文案…（交付型必填）
  audience: string = '';         // 受众/场合（如「华为开发者论坛」）
  lengthTier: string = 'medium'; // brief / medium / long
  targetChars: number = 900;
  assumptions: string[] = [];    // 默认假设标注（交付卡开头展示给用户）
  needAsk: boolean = false;      // 反问判定（三条件缺一不问——写死在 PLAN3_PROMPT）
  askQuestions: ClarifyQuestion[] = [];
  sections: PlanSection[] = [];  // 分析型框架（交付型可空）
  hooks: PlanHook[] = [];
  voice: string = 'senior';
  encourage: string = 'low';
  analogy: string = 'less';
  usedTools: boolean = false;    // 枢机是否调过联网工具（埋点/审核 checklist 用）
}

const CONTRACT_TASK_TYPES: string[] = ['closed', 'analysis', 'deliverable', 'retrieval', 'creative'];
const CONTRACT_HOOK_TYPES: string[] = ['digest', 'breath', 'quiz', 'bait'];

function isContractTaskType(t: string): boolean {
  for (let i = 0; i < CONTRACT_TASK_TYPES.length; i++) {
    if (CONTRACT_TASK_TYPES[i] === t) {
      return true;
    }
  }
  return false;
}

function isContractHookType(t: string): boolean {
  for (let i = 0; i < CONTRACT_HOOK_TYPES.length; i++) {
    if (CONTRACT_HOOK_TYPES[i] === t) {
      return true;
    }
  }
  return false;
}

/**
 * ★ 0.300.0 契约防弹衣（仿 sanitizePlan 模式）：
 * JSON 解析失败（含围栏/废话抠取兜底）→ null（调用侧重试枢机一次，仍 null 走 fallback）；
 * 字段修补：taskType 非五枚举→analysis；form 非枚举→按 taskType 推默认（交付族=deliverable）；
 * 交付型 genre 空→「通用文稿」；needAsk 但 askQuestions 空/非法→needAsk=false（宁可不问）；
 * sections 修补仅分析型强制兜底节（交付型 sections 允许空=直给成品）；幻觉拦截不适用（与 sanitizePlan 差异点）。
 */
export function sanitizeContract(raw: string): TaskContract | null {
  const text = raw.trim();
  const l = text.indexOf('{');
  const r = text.lastIndexOf('}');
  if (l < 0 || r <= l) {
    return null;
  }
  let obj: Record<string, Object> | null = null;
  try {
    obj = JSON.parse(text.substring(l, r + 1)) as Record<string, Object>;
  } catch (_e) {
    return null;
  }
  if (obj === null || obj === undefined) {
    return null;
  }
  const c = new TaskContract();
  // taskType / form
  const tt = String(obj['taskType'] ?? '');
  c.taskType = isContractTaskType(tt) ? tt : 'analysis';
  const fm = String(obj['form'] ?? '');
  if (fm === 'analysis' || fm === 'deliverable') {
    c.form = fm;
  } else {
    c.form = (c.taskType === 'deliverable' || c.taskType === 'creative') ? 'deliverable' : 'analysis';
  }
  // closed 单轮直出不进框架链（消费侧分支），form 归 analysis
  if (c.taskType === 'closed') {
    c.form = 'analysis';
  }
  c.genre = String(obj['genre'] ?? '').trim().substring(0, 20);
  if (c.form === 'deliverable' && c.genre.length === 0) {
    c.genre = '通用文稿';
  }
  c.audience = String(obj['audience'] ?? '').trim().substring(0, 30);
  // 长度档（与 PlanFrame 同枚举；交付型默认 medium）
  const tier = String(obj['lengthTier'] ?? '');
  c.lengthTier = tier === 'brief' || tier === 'medium' || tier === 'long' ? tier : 'medium';
  const tc = Number(obj['targetChars']);
  const tierDefault = c.lengthTier === 'brief' ? 300 : (c.lengthTier === 'long' ? 1800 : 900);
  let target = Number.isFinite(tc) && tc > 0 ? Math.round(tc) : tierDefault;
  if (target < 150) {
    target = 150;
  }
  if (target > 6000) {
    target = 6000;
  }
  c.targetChars = target;
  // assumptions（≤3 条×40 字）
  try {
    if (obj['assumptions'] instanceof Array) {
      const arr = JSON.parse(JSON.stringify(obj['assumptions'])) as Object[];
      for (let i = 0; i < arr.length && c.assumptions.length < 3; i++) {
        const a = String(arr[i] ?? '').trim();
        if (a.length > 0) {
          c.assumptions.push(a.substring(0, 40));
        }
      }
    }
  } catch (_e) {
    c.assumptions = [];
  }
  // askQuestions（needAsk=true 时 1~3 题、每题 2~4 选项截断；任何非法→needAsk=false 宁可不问）
  c.needAsk = obj['needAsk'] === true;
  if (c.needAsk) {
    try {
      if (obj['askQuestions'] instanceof Array) {
        const arr = JSON.parse(JSON.stringify(obj['askQuestions'])) as Record<string, Object>[];
        for (let i = 0; i < arr.length && c.askQuestions.length < 3; i++) {
          const rec = arr[i];
          const q = String(rec['q'] ?? '').trim().substring(0, 60);
          let opts: string[] = [];
          if (rec['options'] instanceof Array) {
            const rawOpts = JSON.parse(JSON.stringify(rec['options'])) as Object[];
            for (let k = 0; k < rawOpts.length && opts.length < 4; k++) {
              const o = String(rawOpts[k] ?? '').trim().substring(0, 30);
              if (o.length > 0) {
                opts.push(o);
              }
            }
          }
          if (q.length === 0 || opts.length < 2) {
            continue; // 题干空/选项不足 2=废题丢弃
          }
          const cq = new ClarifyQuestion();
          cq.q = q;
          cq.options = opts;
          cq.multi = rec['multi'] === true;
          c.askQuestions.push(cq);
        }
      }
    } catch (_e) {
      c.askQuestions = [];
    }
    if (c.askQuestions.length === 0) {
      c.needAsk = false;
    }
  }
  // sections（≤8 节；分析型空→默认节；交付型允许空）
  let rawSections: Record<string, Object>[] = [];
  try {
    if (obj['sections'] instanceof Array) {
      rawSections = JSON.parse(JSON.stringify(obj['sections'])) as Record<string, Object>[];
    }
  } catch (_e) {
    rawSections = [];
  }
  for (let i = 0; i < rawSections.length && c.sections.length < 8; i++) {
    const rec = rawSections[i];
    const sec = new PlanSection();
    const title = String(rec['title'] ?? '').trim();
    sec.title = title.length > 0 ? title.substring(0, 40) : `第${c.sections.length + 1}节`;
    if (rec['points'] instanceof Array) {
      const pts = JSON.parse(JSON.stringify(rec['points'])) as Object[];
      for (let p = 0; p < pts.length && p < 8; p++) {
        const pt = String(pts[p] ?? '').trim();
        if (pt.length > 0) {
          sec.points.push(pt.substring(0, 60));
        }
      }
    }
    sec.depth = String(rec['depth'] ?? '') === 'plain' ? 'plain' : 'deep';
    c.sections.push(sec);
  }
  if (c.form === 'analysis' && c.sections.length === 0) {
    const def = new PlanSection();
    def.title = '解答';
    def.points.push('围绕用户问题完整解答');
    def.depth = 'deep';
    c.sections.push(def);
  }
  // hooks（四枚举丢弃非法；afterSection 钳 1..节数；bait 取最后定末节；交付型通常 0 条——枢机不该给，不强制清）
  const secCount = Math.max(1, c.sections.length);
  let rawHooks: Record<string, Object>[] = [];
  try {
    if (obj['hooks'] instanceof Array) {
      rawHooks = JSON.parse(JSON.stringify(obj['hooks'])) as Record<string, Object>[];
    }
  } catch (_e) {
    rawHooks = [];
  }
  let baitText = '';
  for (let i = 0; i < rawHooks.length && i < 8; i++) {
    const rec = rawHooks[i];
    const type = String(rec['type'] ?? '');
    if (!isContractHookType(type)) {
      continue;
    }
    let ht = String(rec['text'] ?? '').trim();
    if (ht.length === 0) {
      continue;
    }
    if (ht.length > 20) {
      ht = ht.substring(0, 20);
    }
    if (type === 'bait') {
      baitText = ht;
      continue;
    }
    const hook = new PlanHook();
    const as = Number(rec['afterSection']);
    let sec = Number.isFinite(as) ? Math.floor(as) : secCount;
    if (sec < 1) {
      sec = 1;
    }
    if (sec > secCount) {
      sec = secCount;
    }
    hook.afterSection = sec;
    hook.type = type;
    hook.text = ht;
    c.hooks.push(hook);
  }
  if (c.form === 'analysis' && baitText.length > 0) {
    const bait = new PlanHook();
    bait.afterSection = secCount;
    bait.type = 'bait';
    bait.text = baitText;
    c.hooks.push(bait);
  }
  // tone（非法→默认）
  const tone = obj['tone'];
  if (tone !== null && tone !== undefined && typeof tone === 'object') {
    const trec = tone as Record<string, Object>;
    const v = String(trec['voice'] ?? '');
    c.voice = v === 'coach' || v === 'tool' ? v : 'senior';
    const e = String(trec['encourage'] ?? '');
    c.encourage = e === 'high' ? 'high' : 'low';
    const a = String(trec['analogy'] ?? '');
    c.analogy = a === 'more' ? 'more' : 'less';
  }
  return c;
}

/** 契约语气行（与 planToneLine 同文案——独立实现防 MdInline 反向依赖） */
export function contractToneLine(c: TaskContract): string {
  const voiceMap: Record<string, string> = {
    'senior': '像懂你的学长（懂我、慢慢来）',
    'coach': '像打气的教练（你可以的、往前冲）',
    'tool': '像干练的工具（直接给答案，少寒暄）'
  };
  return `${voiceMap[c.voice] ?? voiceMap['senior']}；鼓励${c.encourage === 'high' ? '多一点（多肯定）' : '克制（少打气）'}；类比${c.analogy === 'more' ? '多用（类比先行）' : '少用（直述为主）'}`;
}

/**
 * 防契约污染（任务书 §二）：交执笔/御史的契约压缩为纯文本简报——
 * 只保留形态决策字段，禁止把枢机完整 JSON 塞给下游。
 */
export function buildContractBrief(c: TaskContract): string {
  const parts: string[] = [];
  parts.push(`任务类型：${c.taskType}`);
  parts.push(`输出形态：${c.form === 'deliverable' ? '可整体复制的成品' : '章节化长文'}`);
  if (c.genre.length > 0) {
    parts.push(`体裁：${c.genre}`);
  }
  if (c.audience.length > 0) {
    parts.push(`受众/场合：${c.audience}`);
  }
  parts.push(`长度档：${c.lengthTier}（目标约 ${c.targetChars} 字）`);
  if (c.assumptions.length > 0) {
    parts.push(`默认假设：${c.assumptions.join('；')}`);
  }
  return parts.join('\n');
}

// ============================================================
// ★ 0.300.0 御史判定解析（防弹衣）——verdict 两枚举钳制；comments ≤3 条×60 字截断；
//   解析失败返回 null（调用侧按「审核不可用」放行——御史是增强不是阻塞）
// ============================================================
export class CensorVerdict {
  verdict: string = 'fail'; // pass / fail
  comments: string[] = [];
}

export function parseCensorVerdict(raw: string): CensorVerdict | null {
  const text = raw.trim();
  const l = text.indexOf('{');
  const r = text.lastIndexOf('}');
  if (l < 0 || r <= l) {
    return null;
  }
  let obj: Record<string, Object> | null = null;
  try {
    obj = JSON.parse(text.substring(l, r + 1)) as Record<string, Object>;
  } catch (_e) {
    return null;
  }
  if (obj === null || obj === undefined) {
    return null;
  }
  const v = new CensorVerdict();
  v.verdict = obj['verdict'] === 'pass' ? 'pass' : 'fail';
  if (obj['comments'] instanceof Array) {
    try {
      const arr = JSON.parse(JSON.stringify(obj['comments'])) as Object[];
      for (let i = 0; i < arr.length && v.comments.length < 3; i++) {
        const c = String(arr[i] ?? '').trim();
        if (c.length > 0) {
          v.comments.push(c.substring(0, 60));
        }
      }
    } catch (_e) {
      v.comments = [];
    }
  }
  return v;
}

// ============================================================
// ★ 0.300.0 反问卡共享 store（AppStorageV2 应用级不落盘——ImageViewerStore 同款模式）
// ============================================================
@ObservedV2
export class SishuClarifyState {
  @Trace visible: boolean = false;
  @Trace messageId: string = ''; // 关联的 AI 消息 ID（反问卡渲染在该消息气泡下）
  @Trace title: string = '';     // 卡头（如「开始前确认 2 个问题」）
  @Trace questions: ClarifyQuestion[] = []; // 整体重赋值触发（@Local 消费端刷新）
}

const SIYU_CLARIFY_KEY: string = 'sishu-clarify-state';

export function connectSishuClarify(): SishuClarifyState {
  const s = AppStorageV2.connect(SishuClarifyState, SIYU_CLARIFY_KEY, () => new SishuClarifyState()) as SishuClarifyState;
  return s;
}

// ============================================================
// ★ 0.300.0 一键纠偏历史（preferences 轻通道——只写该用户偏好，不写全局规则、
//   不污染画像主档；最近 20 条，枢机 prompt 动态注入调权重）
// ============================================================
const CORRECT_PREF_NAME: string = 'sishu_agent_v1';
const CORRECT_PREF_KEY: string = 'correct_history';

/** 记一次纠偏（form 切换方向+当时体裁/任务类型关键词） */
export function recordCorrectEntry(ctx: common.Context, fromForm: string, toForm: string, taskType: string, genre: string): void {
  try {
    const p = preferences.getPreferencesSync(ctx, { name: CORRECT_PREF_NAME });
    const raw = p.getSync(CORRECT_PREF_KEY, '[]') as string;
    let arr: string[] = [];
    try {
      const parsed = JSON.parse(raw) as Object[];
      for (let i = 0; i < parsed.length; i++) {
        arr.push(String(parsed[i] ?? ''));
      }
    } catch (_e) {
      arr = [];
    }
    arr.push(`${fromForm}>${toForm}|${taskType}|${genre}|${Date.now()}`);
    while (arr.length > 20) {
      arr.shift();
    }
    p.putSync(CORRECT_PREF_KEY, JSON.stringify(arr));
    p.flushSync();
  } catch (_e) {
    // 纠偏历史=增强信号，失败静默（不影响主链）
  }
}

/** 读纠偏历史→枢机 prompt 注入行（空历史返回空串零注入） */
export function loadCorrectHint(ctx: common.Context): string {
  try {
    const p = preferences.getPreferencesSync(ctx, { name: CORRECT_PREF_NAME });
    const raw = p.getSync(CORRECT_PREF_KEY, '[]') as string;
    if (raw.length <= 2) {
      return '';
    }
    let arr: string[] = [];
    try {
      const parsed = JSON.parse(raw) as Object[];
      for (let i = 0; i < parsed.length; i++) {
        arr.push(String(parsed[i] ?? ''));
      }
    } catch (_e) {
      return '';
    }
    if (arr.length === 0) {
      return '';
    }
    // 只取最近 10 条且只保留语义段（去时间戳）
    const recent = arr.slice(-10).map((s: string): string => s.split('|').slice(0, 3).join('·'));
    return `【该用户历史纠偏记录（同类需求请避开被纠偏方向）】\n${recent.join('\n')}`;
  } catch (_e) {
    return '';
  }
}
