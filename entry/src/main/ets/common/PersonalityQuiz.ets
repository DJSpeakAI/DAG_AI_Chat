// ============================================================
// PersonalityQuiz.ets — ★ 0.288.0 性格测试（15 题混合穿插）
//   ★ 0.290.0 性格测试 2.0：封闭三选一 → 开放题 + AI 评阅画像（WP1）。
//   ★ 0.292.1 性格测试 3.0（用户拍板）：开放题全部撤除，回归纯选择题——
//   12 单选 + 3 多选（q3/q11/q15），零文本输入；AI 评阅链路保留（输入=所选选项文案拼接）。
//   产品定位：显式性格底色 → 转译成画像行灌入记忆引擎（ProfileModel 管道），
//   与隐式画像观察互补（测试=底色先验/冷启动解药，观察=日常动态修正）。
//   入口：气泡树画布左下角「信号灯」呼吸圆点（做完消失）；断点续做；
//   SP 激励：每答 5 题发一个节点（2000 司忆点，共 3 节点，claimed 幂等）。
//
// 存储（PersistenceV2 key 'personality-quiz-v1'，发布后禁改；Schema 铁律只许尾部追加）：
//   - answers：旧封闭题字母 JSON 数组（'a'|'b'|'c'）——★ 0.290.0 起只读不写（老用户兼容评阅映射源）
//   - claimed / done / completedAt：SP 节点与完成标记
//   - answerTexts：★ 0.290.0 尾部追加——开放题答案文本 JSON 数组（★ 0.292.1 起停止写入，已答数据保留兼容评阅）
//   - profileWritten：★ 0.290.0 尾部追加——评阅结果已写入画像标记（幂等第二道闸，done 后仍防重写）
//   - choiceAnswers：★ 0.292.1 尾部追加——选择题答案 JSON 数组（元素=选中字母小写升序拼接串，如 'a'/'ac'/'ace'，按题序）
//
// 评阅链路（0.290.0）：15 题答完 → 全部答案一次性送轻模型隐式评阅（implicit:true
//   不扣用户 SP）→ 12 维画像行 → appendObservation 管道写入；失败/超时 25s → 本地
//   关键词兜底 → 仍失败写默认均衡画像。不阻塞测试完成、不阻塞 SP 发放。
//
// 纪律：
//   - 画像 kind 只用既有四枚举（identity/goal/preference/emotion），不扩枚举（Schema 铁律）
//   - @ObservedV2 禁直接 stringify 实例——字符串 JSON 整体赋值模式（同 ProfileStore.raw）
//   - 题目=「反推旋钮」设计：每题答案必须能拧动至少一个 AI 输出旋钮（锚点类型/难度/语气/口吻/节奏）
//   - 交叉验证：认知深度 q12 优先于 q2；抗压 q14 优先于 q4（行为题优先于自评题，心理学定论）
// ============================================================

import { PersistenceV2 } from '@kit.ArkUI';
import { ProfileStore, ProfileObservation, appendObservation } from './ProfileModel';
import { generateMessageId, connectSiyiPoints, grantBonusSp, ApiConfig } from './ChatModel';
import { streamChat } from '../utils/ApiClient';
import { ChatMessage } from './ChatModel';
import { QUIZ_REVIEW_PROMPT } from './Prompts';

// ------------------------------------------------------------
// 题目数据（15 题，题型穿插：相邻两题永不同型）
// ★ 0.292.1 性格测试 3.0：全部封闭式选择题（12 单选 + 3 多选 multi:true），
//   题干零开放表述、答案零文本输入；options 同为老用户字母映射与本地兜底文案源。
// ------------------------------------------------------------
export interface QuizOption {
  label: string; // 'A' / 'B' / 'C' / 'D' / 'E'
  text: string;
}

export interface QuizQuestion {
  index: number;   // 1~15
  tag: string;     // 题型徽章（情境题/自评题/多选题/反应题/频率题/行为追问题）
  question: string;
  options: QuizOption[];
  multi: boolean;  // ★ 0.292.1：true=多选（可选项≥4，至少选 1 项）；false=单选
}

export const QUIZ_TOTAL: number = 15;
export const QUIZ_SP_PER_NODE: number = 2000; // 每节点 2000 司忆点（5 题一节点，共 3 节点）
const QUIZ_REVIEW_TIMEOUT_MS: number = 25000; // 评阅超时保护（超时走本地兜底写入，AI 晚到丢弃）

function opt(label: string, text: string): QuizOption {
  return { label: label, text: text };
}

export const PERSONALITY_QUESTIONS: QuizQuestion[] = [
  {
    index: 1, tag: '情境题',
    question: '刚学完一个新概念，你接下来通常会做什么？',
    multi: false,
    options: [
      opt('A', '马上找道题试试手'),
      opt('B', '再琢磨琢磨它为什么成立'),
      opt('C', '先放一放，换个话题')
    ]
  },
  {
    index: 2, tag: '自评题',
    question: '看长文章或长视频时，你的习惯是什么？',
    multi: false,
    options: [
      opt('A', '讲得越深越爽，细节都想看'),
      opt('B', '先看结论，感兴趣的再深挖'),
      opt('C', '给我结论就行，细节懒得看')
    ]
  },
  {
    index: 3, tag: '多选题',
    question: '你希望老师或 AI 讲课时，多用哪些方式帮你理解？（可多选）',
    multi: true,
    options: [
      opt('A', '例子和故事'),
      opt('B', '原理和推导'),
      opt('C', '大白话类比打比方'),
      opt('D', '考考我的小问题'),
      opt('E', '动手练习')
    ]
  },
  {
    index: 4, tag: '情境题',
    question: '一道题做错了，你心里第一反应是什么？',
    multi: false,
    options: [
      opt('A', '有意思，错在哪了？'),
      opt('B', '有点烦，但能接着来'),
      opt('C', '挫败感上来了，想先放放')
    ]
  },
  {
    index: 5, tag: '频率题',
    question: '定了学习计划之后，你一般执行得怎样？',
    multi: false,
    options: [
      opt('A', '说几点就几点，很稳'),
      opt('B', '大体跟上，偶尔飘'),
      opt('C', '计划是计划，做是做')
    ]
  },
  {
    index: 6, tag: '反应题',
    question: '读长文时中途插入一个「考考你」小问题，你的真实感受是？',
    multi: false,
    options: [
      opt('A', '来劲，正好检验自己'),
      opt('B', '还行，会停下来想想'),
      opt('C', '有压力，怕答不上')
    ]
  },
  {
    index: 7, tag: '自评题',
    question: '刷到反常识的说法（比如「努力反而有害」），你通常会怎么做？',
    multi: false,
    options: [
      opt('A', '眼睛一亮，想弄清楚怎么回事'),
      opt('B', '有点好奇，看心情深究'),
      opt('C', '标题党罢了，划走')
    ]
  },
  {
    index: 8, tag: '情境题',
    question: '同样 3000 字的长文，什么样的写法最让你受不了？',
    multi: false,
    options: [
      opt('A', '废话多，绕来绕去不到重点'),
      opt('B', '太干太密，没有喘气的地方'),
      opt('C', '都还行，看内容值不值')
    ]
  },
  {
    index: 9, tag: '自评题',
    question: '面对完全陌生的硬核领域，你觉得自己能学到什么程度？',
    multi: false,
    options: [
      opt('A', '给我时间就能啃下来'),
      opt('B', '能懂个大概吧'),
      opt('C', '估计只能懂个科普层面')
    ]
  },
  {
    index: 10, tag: '反应题',
    question: '文中出现「简单说：响应式=看到你走近，我换一套站姿」这种大白话翻译，你什么感受？',
    multi: false,
    options: [
      opt('A', '很棒，帮我消化'),
      opt('B', '偶尔来一次挺好'),
      opt('C', '多余，不需要')
    ]
  },
  {
    index: 11, tag: '多选题',
    question: '学有所成的时候，你通常会做什么？（可多选）',
    multi: true,
    options: [
      opt('A', '找人分享出去，嘚瑟一下'),
      opt('B', '自己心里默默爽'),
      opt('C', '记录下来，看看成长足迹'),
      opt('D', '无感，直接开下一个')
    ]
  },
  {
    index: 12, tag: '行为追问题',
    question: 'AI 给了你一个能用但「知其然」的答案，你会怎么办？',
    multi: false,
    options: [
      opt('A', '追问到底，非要搞懂为什么'),
      opt('B', '时间够就深挖，不够就算'),
      opt('C', '能用就行，不折腾')
    ]
  },
  {
    index: 13, tag: '情境题',
    question: '深夜独自学习卡壳了，你更希望听到什么话？',
    multi: false,
    options: [
      opt('A', '「这题确实难，慢慢来」——懂我的学长'),
      opt('B', '「你可以的，冲！」——打气的教练'),
      opt('C', '别说话，直接给我答案')
    ]
  },
  {
    index: 14, tag: '行为追问题',
    question: '连续三次复习都记不住同一个知识点，你会怎么想？',
    multi: false,
    options: [
      opt('A', '正常，再来一遍就是了'),
      opt('B', '有点泄气，换个方法再试'),
      opt('C', '开始怀疑自己不适合学这个')
    ]
  },
  {
    index: 15, tag: '多选题',
    question: '你理想中一次高质量的学习，是什么样的？（可多选）',
    multi: true,
    options: [
      opt('A', '一头扎进去，两小时不出来'),
      opt('B', '半小时一段，中间起来走走'),
      opt('C', '碎片时间刷几条，积少成多'),
      opt('D', '边学边做题练手'),
      opt('E', '学完讲给别人听')
    ]
  }
];

// ------------------------------------------------------------
// 进度存储（断点续做——答案即时落盘，退出再进从已答数继续）
// ------------------------------------------------------------
@ObservedV2
export class PersonalityQuizStore {
  @Trace answers: string = '[]'; // 旧封闭题字母（元素 'a'|'b'|'c'）——0.290.0 起只读不写（兼容映射源）
  @Trace claimed: number = 0;    // 已领取 SP 奖励节点数 0~3（幂等防重发）
  @Trace done: boolean = false;  // 15 题全部完成（信号灯消失条件；0.290.0 起不等评阅——评阅异步）
  @Trace completedAt: number = 0;
  @Trace answerTexts: string = '[]';      // ★ 0.290.0 尾部追加：开放题答案文本（0.292.1 起停写，已答保留兼容）
  @Trace profileWritten: boolean = false; // ★ 0.290.0 尾部追加：评阅结果已写入画像（幂等第二道闸）
  @Trace choiceAnswers: string = '[]';    // ★ 0.292.1 尾部追加：选择题答案（元素=字母小写升序拼接串，如 'ac'）
}

export function connectPersonalityQuiz(): PersonalityQuizStore {
  return PersistenceV2.connect(PersonalityQuizStore, 'personality-quiz-v1',
    () => new PersonalityQuizStore()) as PersonalityQuizStore;
}

export function getQuizAnswers(store: PersonalityQuizStore): string[] {
  try {
    const arr = JSON.parse(store.answers) as string[];
    if (arr !== undefined && arr !== null) {
      return arr;
    }
  } catch (_e) {
    // 坏数据兜底：视同未答
  }
  return [];
}

/** 读取开放题答案文本（坏数据兜底空数组） */
export function getQuizAnswerTexts(store: PersonalityQuizStore): string[] {
  try {
    const arr = JSON.parse(store.answerTexts) as string[];
    if (arr !== undefined && arr !== null) {
      return arr;
    }
  } catch (_e) {
    // 坏数据兜底：视同未答
  }
  return [];
}

/** 追加一题开放题答案文本，返回追加后已答总数（0.292.1 起仅兼容旧数据路径，新答题流不走此函数） */
export function recordQuizAnswerText(store: PersonalityQuizStore, text: string): number {
  const arr = getQuizAnswerTexts(store);
  arr.push(text.trim());
  store.answerTexts = JSON.stringify(arr);
  return arr.length;
}

/** 读取选择题答案（坏数据兜底空数组） */
export function getQuizChoices(store: PersonalityQuizStore): string[] {
  try {
    const arr = JSON.parse(store.choiceAnswers) as string[];
    if (arr !== undefined && arr !== null) {
      return arr;
    }
  } catch (_e) {
    // 坏数据兜底：视同未答
  }
  return [];
}

/** 追加一题选择题答案（letters=选中字母小写升序拼接串，如 'a'/'ac'），返回追加后选择题已答数 */
export function recordQuizChoice(store: PersonalityQuizStore, letters: string): number {
  const arr = getQuizChoices(store);
  arr.push(letters);
  store.choiceAnswers = JSON.stringify(arr);
  return arr.length;
}

/** 已答总数（旧字母进度 + 开放题文本进度 + 选择题进度三段相加——老用户从已答处无缝续答） */
export function quizAnswerTotal(store: PersonalityQuizStore): number {
  return getQuizAnswers(store).length + getQuizAnswerTexts(store).length + getQuizChoices(store).length;
}

/** 纯函数：已答 total 题对应的应领节点数（5 题=1 / 10 题=2 / 15 题=3，上限 3） */
export function quizNodeReached(total: number): number {
  return Math.min(Math.floor(Math.max(0, total) / 5), 3);
}

/** 纯函数：本次应补发的 SP 额度（claimed→应领节点的差额 × 节点额度；0=无可领） */
export function buildQuizClaimAmount(claimed: number, total: number): number {
  const node = quizNodeReached(total);
  return node > claimed ? (node - claimed) * QUIZ_SP_PER_NODE : 0;
}

/** 发放差额节点 SP（入 bonusSp 嘉奖池 + 云上行 + sp_grant 埋点，走 ChatModel 收口），返回本次发放额 */
export function claimQuizSp(store: PersonalityQuizStore): number {
  const total = quizAnswerTotal(store);
  const amount = buildQuizClaimAmount(store.claimed, total);
  if (amount <= 0) {
    return 0;
  }
  store.claimed = quizNodeReached(total);
  grantBonusSp(connectSiyiPoints(), amount, 'quiz');
  return amount;
}

// ------------------------------------------------------------
// ★ 0.292.1 评阅输入组装（三段拼接）：前段=老字母题映射文案；中段=0.290.x 开放题
//   文本原文；尾段=选择题选中项文案拼接（多选顿号连接）。未答=空串（评阅判无效）。
// ------------------------------------------------------------
function letterToOptionText(qIdx0: number, letter: string): string {
  if (qIdx0 < 0 || qIdx0 >= PERSONALITY_QUESTIONS.length) {
    return '';
  }
  if (letter === 'a' || letter === 'b' || letter === 'c') {
    return PERSONALITY_QUESTIONS[qIdx0].options[letter.charCodeAt(0) - 97].text;
  }
  return '';
}

/** 选择题答案串（'ac'）→ 该题选中项文案拼接（顿号连接；越界字母忽略） */
function choiceToOptionText(qIdx0: number, joined: string): string {
  if (qIdx0 < 0 || qIdx0 >= PERSONALITY_QUESTIONS.length) {
    return '';
  }
  const opts = PERSONALITY_QUESTIONS[qIdx0].options;
  const parts: string[] = [];
  for (let i = 0; i < joined.length; i++) {
    const code = joined.charCodeAt(i) - 97; // 'a'=0
    if (code >= 0 && code < opts.length) {
      parts.push(opts[code].text);
    }
  }
  return parts.join('、');
}

export function buildReviewInputs(store: PersonalityQuizStore): string[] {
  const letters = getQuizAnswers(store);
  const texts = getQuizAnswerTexts(store);
  const choices = getQuizChoices(store);
  const letterCount = letters.length;
  const textCount = texts.length;
  const out: string[] = [];
  for (let i = 0; i < QUIZ_TOTAL; i++) {
    if (i < letterCount) {
      // 老用户字母题：映射回选项文案参与评阅（Q2 审批裁决的兼容路径）
      out.push(letterToOptionText(i, letters[i]));
    } else if (i - letterCount < textCount) {
      // 0.290.x 开放题文本：原文参与评阅（已答数据保留兼容）
      out.push(texts[i - letterCount].trim());
    } else {
      const c = i - letterCount - textCount;
      out.push(c < choices.length ? choiceToOptionText(c, choices[c]) : ''); // 未答=空串（评阅判无效）
    }
  }
  return out;
}

// ------------------------------------------------------------
// ★ 0.290.0 本地关键词兜底（降级链第二级）：12 维各配 2~3 组关键词，
//   命中→对应文案；全不命中→均衡文案（与 QUIZ_DIMS 12 维同序）
// ------------------------------------------------------------
export interface QuizProfileLine {
  kind: string;    // identity / goal / preference / emotion
  content: string; // 一句话（无主语风格，与 LLM 观察行同款）
}

interface LocalDim {
  kind: string;
  hitA: string[];   // A 向关键词
  textA: string;
  hitB: string[];   // B 向关键词
  textB: string;
  neutral: string;  // 均衡兜底文案
}

const LOCAL_REVIEW_DIMS: LocalDim[] = [
  { kind: 'goal', hitA: ['试试', '上手', '做题', '练习'], textA: '应用导向：先上手例子，再回头补原理',
    hitB: ['为什么', '原理', '琢磨', '推导'], textB: '掌握导向：先吃透原理，再谈应用',
    neutral: '驱动均衡：应用与原理并行吸收' },
  { kind: 'preference', hitA: ['深挖', '细节', '到底', '弄懂', '深'], textA: '求知欲强：答案宁深勿浅，值得追问到底',
    hitB: ['结论', '就行', '懒得', '随便看看'], textB: '结论优先：先给结论，感兴趣再深挖',
    neutral: '求知均衡：深浅按话题定' },
  { kind: 'preference', hitA: ['例子', '故事', '类比', '比方', '比喻'], textA: '例子驱动：故事和例子先行，原理自悟',
    hitB: ['推导', '证明', '原理讲'], textB: '原理驱动：推导讲透，例子自己找',
    neutral: '讲法均衡：怎么讲得好怎么来' },
  { kind: 'emotion', hitA: ['有趣', '错在哪', '正常', '再来', '哪里出'], textA: '心态稳：可直言错误与盲区，抗打击',
    hitB: ['烦', '挫败', '怀疑', '泄气', '难受'], textB: '易挫败：需低压力、多鼓励的节奏',
    neutral: '抗压一般：纠错宜先肯定再指问题' },
  { kind: 'preference', hitA: ['稳', '准时', '坚持', '说到做到'], textA: '自律：提醒与安排可严格直接',
    hitB: ['飘', '计划是计划', '拖延', '随缘'], textB: '随性：提醒宜轻量、趣味化',
    neutral: '半自律：提醒宜温和但坚持' },
  { kind: 'preference', hitA: ['来劲', '喜欢', '检验', '很棒', '考'], textA: '互动型：欢迎「考考你」提问与大白话翻译',
    hitB: ['压力', '多余', '不要', '烦'], textB: '低互动：少考问少插话，直接讲',
    neutral: '适度互动：偶尔来一个钩子即可' },
  { kind: 'preference', hitA: ['一亮', '弄清楚', '想知', '反常识'], textA: '好奇心强：反常识话题是强钩子',
    hitB: ['划走', '标题党', '不理'], textB: '务实：少用悬念式开场',
    neutral: '好奇心中等：钩子点到为止' },
  { kind: 'preference', hitA: ['废话', '绕', '直接', '重点', '干脆'], textA: '极简口味：直给重点，零废话',
    hitB: ['喘', '密', '透不过', '干巴巴'], textB: '节奏口味：内容再硬也要留喘息位',
    neutral: '口味均衡：内容值就行' },
  { kind: 'preference', hitA: ['啃下来', '能学', '自信', '学会'], textA: '学习自信高：可直接上难度、跨知识点',
    hitB: ['科普', '估计', '大概', '学不会'], textB: '学习自信偏低：宜多铺垫、降门槛',
    neutral: '学习自信中等：难度平缓爬坡' },
  { kind: 'preference', hitA: ['分享', '嘚瑟', '告诉', '炫耀'], textA: '爱分享：鼓励可热情夸张、放开了夸',
    hitB: ['默默', '自己', '低调', '无所谓'], textB: '内敛：鼓励宜简短真诚',
    neutral: '分享倾向均衡：鼓励点到即止' },
  { kind: 'emotion', hitA: ['学长', '慢慢', '懂我', '安慰'], textA: '学长式口吻：懂我、慢慢来',
    hitB: ['冲', '打气', '加油', '教练'], textB: '教练式口吻：打气、往前冲',
    neutral: '口吻均衡：按情境切换语气' },
  { kind: 'preference', hitA: ['两小时', '沉浸', '扎进去', '一整段'], textA: '长时段沉浸型：内容可成块展开',
    hitB: ['半小时', '走走', '分段', '碎片', '刷'], textB: '短时段分段型：宜按段分章、可独立成段',
    neutral: '时段均衡：长短内容皆可适应' }
];

const INVALID_ANSWER_PATTERNS: string[] = ['111', '222', '333', '123', '不知道', '随便', '无语', '测试', '呵呵', 'aaa', 'bbb'];

/** 敷衍答案判定（评阅与本地兜底同口径） */
export function isInvalidQuizAnswer(text: string): boolean {
  const t = text.trim();
  if (t.length <= 1) {
    return true; // 空/单字
  }
  const pure = t.replace(/[\s\p{P}\p{S}]/gu, ''); // 去空白与符号
  if (pure.length === 0) {
    return true; // 纯符号
  }
  for (let i = 0; i < INVALID_ANSWER_PATTERNS.length; i++) {
    if (t === INVALID_ANSWER_PATTERNS[i]) {
      return true;
    }
  }
  return false;
}

/** 本地关键词评阅（降级链第二级）：敷衍答案不参与命中；有效证据 <5 题→全 12 行均衡型 */
export function localReviewQuizTexts(texts: string[]): QuizProfileLine[] {
  let validCount = 0;
  const joined: string[] = [];
  for (let i = 0; i < texts.length; i++) {
    const ok = !isInvalidQuizAnswer(texts[i]);
    if (ok) {
      validCount++;
    }
    joined.push(ok ? texts[i] : '');
  }
  const lines: QuizProfileLine[] = [];
  for (let d = 0; d < LOCAL_REVIEW_DIMS.length; d++) {
    const dim = LOCAL_REVIEW_DIMS[d];
    let text = dim.neutral;
    if (validCount >= 5) {
      // 与该维最相关的题号区（12 维 × 15 题：按维度序就近映射题 1~15）
      const probe = (d * 15 / LOCAL_REVIEW_DIMS.length) | 0;
      const scope = [probe, Math.max(0, probe - 1), Math.min(texts.length - 1, probe + 1)];
      const bag: string[] = [];
      for (let s = 0; s < scope.length; s++) {
        if (scope[s] >= 0 && scope[s] < joined.length && joined[scope[s]].length > 0) {
          bag.push(joined[scope[s]]);
        }
      }
      const all = bag.join('\n');
      let hitA = false;
      let hitB = false;
      for (let k = 0; k < dim.hitA.length; k++) {
        if (all.includes(dim.hitA[k])) {
          hitA = true;
          break;
        }
      }
      for (let k = 0; k < dim.hitB.length; k++) {
        if (all.includes(dim.hitB[k])) {
          hitB = true;
          break;
        }
      }
      if (hitA && !hitB) {
        text = dim.textA;
      } else if (hitB && !hitA) {
        text = dim.textB;
      }
    }
    lines.push({ kind: dim.kind, content: text });
  }
  return lines;
}

// ------------------------------------------------------------
// ★ 0.290.0 AI 评阅 + 画像写入
//   writeQuizProfile：done 标记立即置位（不阻塞 SP/完成页）→ 评阅异步 fire-and-forget；
//   降级链：AI 失败/超时 25s → localReviewQuizTexts 关键词兜底 →（兜底恒有结果，不再降第三级）；
//   幂等：quiz.done（老闸）+ quiz.profileWritten（新闸）双保险，AI 晚到丢弃。
// ------------------------------------------------------------
function writeProfileLines(profileStore: ProfileStore, lines: QuizProfileLine[]): void {
  const now = Date.now();
  for (let i = 0; i < lines.length; i++) {
    const obs = new ProfileObservation(generateMessageId(), lines[i].kind, lines[i].content,
      'personality-quiz', '', now, now);
    appendObservation(profileStore, obs);
  }
}

/** AI 评阅结果容错解析（截首尾括号同 applyProfileResult 模式）；行数 <6 视为不合格返回 null */
function parseReviewOutput(out: string): QuizProfileLine[] | null {
  try {
    let text = out.trim();
    const l = text.indexOf('[');
    const r = text.lastIndexOf(']');
    if (l < 0 || r <= l) {
      return null;
    }
    text = text.substring(l, r + 1);
    const arr = JSON.parse(text) as Record<string, string>[];
    const lines: QuizProfileLine[] = [];
    for (let i = 0; i < arr.length && i < 12; i++) {
      const item = arr[i];
      const kind = String(item['kind'] ?? '');
      const content = String(item['content'] ?? '').trim();
      if (kind !== 'identity' && kind !== 'goal' && kind !== 'preference' && kind !== 'emotion') {
        continue;
      }
      if (content.length < 4 || content.length > 60) {
        continue;
      }
      lines.push({ kind: kind, content: content });
    }
    return lines.length >= 6 ? lines : null; // 坑3 防空画像：行数不足走兜底
  } catch (_e) {
    return null;
  }
}

/**
 * 发起评阅（第 15 题答完调用一次；隐式调用不扣用户 SP）。
 * onResult：画像行写入完成后回调（AI 或兜底结果，完成页预览刷新用）。
 */
export function reviewQuizProfile(quiz: PersonalityQuizStore, profileStore: ProfileStore,
  cfg: ApiConfig, onResult: (lines: QuizProfileLine[]) => void): void {
  if (quiz.profileWritten) {
    return; // 幂等闸：已写过不再触发
  }
  const inputs = buildReviewInputs(quiz);
  const inputLines: string[] = [];
  for (let i = 0; i < inputs.length; i++) {
    inputLines.push(`Q${i + 1}：${inputs[i].length > 0 ? inputs[i] : '（未作答）'}`);
  }
  let settled = false; // 超时保护旗（超时兜底已写入后 AI 晚到一律丢弃）
  const timer = setTimeout(() => {
    if (!settled && !quiz.profileWritten) {
      settled = true;
      const lines = localReviewQuizTexts(inputs);
      writeProfileLines(profileStore, lines);
      quiz.profileWritten = true;
      onResult(lines);
    }
  }, QUIZ_REVIEW_TIMEOUT_MS);
  const msgs: ChatMessage[] = [
    new ChatMessage(generateMessageId(), 'system', QUIZ_REVIEW_PROMPT + inputLines.join('\n'))
  ];
  let buf = '';
  streamChat(
    msgs,
    cfg,
    (chunk: string) => { buf += chunk; },
    () => {
      if (settled) {
        clearTimeout(timer);
        return; // 兜底已写入：丢弃 AI 结果
      }
      settled = true;
      clearTimeout(timer);
      const parsed = parseReviewOutput(buf);
      const lines = parsed !== null ? parsed : localReviewQuizTexts(inputs);
      if (quiz.profileWritten) {
        return;
      }
      writeProfileLines(profileStore, lines);
      quiz.profileWritten = true;
      onResult(lines);
    },
    (_err: string) => {
      // AI 失败：立即走本地关键词兜底（不阻塞完成页）
      if (settled) {
        clearTimeout(timer);
        return;
      }
      settled = true;
      clearTimeout(timer);
      if (quiz.profileWritten) {
        return;
      }
      const lines = localReviewQuizTexts(inputs);
      writeProfileLines(profileStore, lines);
      quiz.profileWritten = true;
      onResult(lines);
    },
    undefined,
    'AI 记忆整理',
    true // implicit：thinking 钳 disabled；★ 0.290.0 任务书 2.3 裁决——评阅不扣用户 SP（产品补贴）
  );
}

/**
 * 第 15 题答完收口（Dialog 调用）：done 立即置位（信号灯消失/SP 不阻塞）+ 触发异步评阅。
 * 返回本次写入不做等待——画像行到达后经 onResult 回调。
 */
export function writeQuizProfile(quiz: PersonalityQuizStore, profileStore: ProfileStore,
  cfg: ApiConfig, onResult: (lines: QuizProfileLine[]) => void): void {
  if (quiz.done) {
    return;
  }
  quiz.done = true;
  quiz.completedAt = Date.now();
  reviewQuizProfile(quiz, profileStore, cfg, onResult);
}

/** 画像行内容预览（完成页展示：评阅结果优先，未到达时空数组=显示进行态） */
export function quizProfilePreviewLines(lines: QuizProfileLine[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    out.push(lines[i].content);
  }
  return out;
}