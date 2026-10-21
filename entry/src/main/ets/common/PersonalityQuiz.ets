// ============================================================
// PersonalityQuiz.ets — ★ 0.288.0 性格测试（15 题混合穿插）
//   产品定位：显式性格底色 → 转译成画像行灌入记忆引擎（ProfileModel 管道），
//   与隐式画像观察互补（测试=底色先验/冷启动解药，观察=日常动态修正）。
//   入口：气泡树画布左下角「信号灯」呼吸圆点（做完消失）；断点续做；
//   SP 激励：每答 5 题发一个节点（2000 司忆点，共 3 节点，claimed 幂等）。
//
// 存储（PersistenceV2 全新 key，发布后禁改）：
//   - 'personality-quiz-v1'：answers（'a'|'b'|'c' JSON 数组按题序）/ claimed / done / completedAt
//
// 纪律：
//   - 画像 kind 只用既有四枚举（identity/goal/preference/emotion），不扩枚举（Schema 铁律）
//   - @ObservedV2 禁直接 stringify 实例——字符串 JSON 整体赋值模式（同 ProfileStore.raw）
//   - 题目=「反推旋钮」设计：每题答案必须能拧动至少一个 AI 输出旋钮（锚点类型/难度/语气/口吻/节奏）
//   - 交叉验证：认知深度 q12 优先于 q2；抗压 q14 优先于 q4（行为题优先于自评题，心理学定论）
// ============================================================

import { PersistenceV2 } from '@kit.ArkUI';
import { ProfileStore, ProfileObservation, appendObservation } from './ProfileModel';
import { generateMessageId, connectSiyiPoints, grantBonusSp } from './ChatModel';

// ------------------------------------------------------------
// 题目数据（15 题，题型穿插：相邻两题永不同型）
// ------------------------------------------------------------
export interface QuizOption {
  label: string; // 'A' / 'B' / 'C'
  text: string;
}

export interface QuizQuestion {
  index: number;   // 1~15
  tag: string;     // 题型徽章（情境题/自评题/二选一/反应题/追问题/场景题）
  question: string;
  options: QuizOption[];
}

export const QUIZ_TOTAL: number = 15;
export const QUIZ_SP_PER_NODE: number = 2000; // 每节点 2000 司忆点（5 题一节点，共 3 节点）

function opt(label: string, text: string): QuizOption {
  return { label: label, text: text };
}

export const PERSONALITY_QUESTIONS: QuizQuestion[] = [
  {
    index: 1, tag: '情境题',
    question: '刚学完一个新概念，你更想干嘛？',
    options: [
      opt('A', '马上找道题试试手'),
      opt('B', '再琢磨琢磨它为什么成立'),
      opt('C', '先放一放，换个话题')
    ]
  },
  {
    index: 2, tag: '自评题',
    question: '看长文章或长视频时，你通常？',
    options: [
      opt('A', '讲得越深越爽，细节都想看'),
      opt('B', '先看结论，感兴趣的再深挖'),
      opt('C', '给我结论就行，细节懒得看')
    ]
  },
  {
    index: 3, tag: '二选一',
    question: '只能跟一个老师学，你选？',
    options: [
      opt('A', '满课例子和故事，原理自己悟'),
      opt('B', '满课原理和推导，例子自己找'),
      opt('C', '看心情，谁讲得好跟谁')
    ]
  },
  {
    index: 4, tag: '情境题',
    question: '一道题做错了，你的第一反应更接近？',
    options: [
      opt('A', '有意思，错在哪了？'),
      opt('B', '有点烦，但能接着来'),
      opt('C', '挫败感上来了，想先放放')
    ]
  },
  {
    index: 5, tag: '频率题',
    question: '定了学习计划之后，执行得怎样？',
    options: [
      opt('A', '说几点就几点，很稳'),
      opt('B', '大体跟上，偶尔飘'),
      opt('C', '计划是计划，做是做')
    ]
  },
  {
    index: 6, tag: '反应题',
    question: '长文读到一半，插进一句「考考你：刚才讲的两个概念是什么关系？」你觉得？',
    options: [
      opt('A', '来劲，正好检验自己'),
      opt('B', '还行，会停下来想想'),
      opt('C', '有压力，怕答不上')
    ]
  },
  {
    index: 7, tag: '自评题',
    question: '刷到「努力反而有害」这种反常识的说法，你会？',
    options: [
      opt('A', '眼睛一亮，想弄清楚怎么回事'),
      opt('B', '有点好奇，看心情深究'),
      opt('C', '标题党罢了，划走')
    ]
  },
  {
    index: 8, tag: '二选一',
    question: '同样 3000 字的长文，你更受不了？',
    options: [
      opt('A', '废话多，绕来绕去不到重点'),
      opt('B', '太干太密，没有喘气的地方'),
      opt('C', '都还行，看内容值不值')
    ]
  },
  {
    index: 9, tag: '情境题',
    question: '面对完全陌生的硬核领域（比如量子计算），你觉得自己？',
    options: [
      opt('A', '给我时间就能啃下来'),
      opt('B', '能懂个大概吧'),
      opt('C', '估计只能懂个科普层面')
    ]
  },
  {
    index: 10, tag: '反应题',
    question: '文中插一句「简单说：响应式=看到你走近，我换一套站姿」这种大白话翻译，你觉得？',
    options: [
      opt('A', '很棒，帮我消化'),
      opt('B', '偶尔来一次挺好'),
      opt('C', '多余，不需要')
    ]
  },
  {
    index: 11, tag: '自评题',
    question: '学有所成的时候，你最想？',
    options: [
      opt('A', '找人分享出去，嘚瑟一下'),
      opt('B', '自己心里默默爽'),
      opt('C', '无感，学完就完了')
    ]
  },
  {
    index: 12, tag: '追问题',
    question: 'AI 给了你一个能用但「知其然」的答案，你会？',
    options: [
      opt('A', '追问到底，非要搞懂为什么'),
      opt('B', '时间够就深挖，不够就算'),
      opt('C', '能用就行，不折腾')
    ]
  },
  {
    index: 13, tag: '情境题',
    question: '深夜独自学习卡壳了，你更希望听到什么声音？',
    options: [
      opt('A', '「这题确实难，慢慢来」——懂我的学长'),
      opt('B', '「你可以的，冲！」——打气的教练'),
      opt('C', '别说话，直接给我答案')
    ]
  },
  {
    index: 14, tag: '追问题',
    question: '连续三次复习都记不住同一个知识点，你会？',
    options: [
      opt('A', '正常，再来一遍就是了'),
      opt('B', '有点泄气，换个方法再试'),
      opt('C', '开始怀疑自己不适合学这个')
    ]
  },
  {
    index: 15, tag: '场景题',
    question: '理想中一次高质量的学习是？',
    options: [
      opt('A', '一头扎进去，两小时不出来'),
      opt('B', '半小时一段，中间起来走走'),
      opt('C', '碎片时间刷几条，积少成多')
    ]
  }
];

// ------------------------------------------------------------
// 进度存储（断点续做——答案即时落盘，退出再进从已答数继续）
// ------------------------------------------------------------
@ObservedV2
export class PersonalityQuizStore {
  @Trace answers: string = '[]'; // 已答选项 JSON 数组（元素 'a'|'b'|'c'，按题序追加）
  @Trace claimed: number = 0;    // 已领取 SP 奖励节点数 0~3（幂等防重发）
  @Trace done: boolean = false;  // 15 题全部完成且画像已写入（信号灯消失条件）
  @Trace completedAt: number = 0;
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

/** 追加一题答案（choice ∈ 'a'|'b'|'c'），返回追加后已答总数 */
export function recordQuizAnswer(store: PersonalityQuizStore, choice: string): number {
  const arr = getQuizAnswers(store);
  arr.push(choice);
  store.answers = JSON.stringify(arr);
  return arr.length;
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
  const total = getQuizAnswers(store).length;
  const amount = buildQuizClaimAmount(store.claimed, total);
  if (amount <= 0) {
    return 0;
  }
  store.claimed = quizNodeReached(total);
  grantBonusSp(connectSiyiPoints(), amount, 'quiz');
  return amount;
}

// ------------------------------------------------------------
// 结果转译：15 答案 → 画像行（kind 复用四枚举，不扩枚举）
//   12 维度 → 12 行；交叉验证：认知深度 q12 优先于 q2、抗压 q14 优先于 q4；
//   互动锚点= q6+q10 综合（双 A=互动型 / 双 C=低互动 / 其余=适度互动）
// ------------------------------------------------------------
export interface QuizProfileLine {
  kind: string;    // identity / goal / preference / emotion
  content: string; // 一句话（无主语风格，与 LLM 观察行同款，≤40 字）
}

// 维度定义：kind + 内容三选一文案 + 默认取题（0 起题号；-1=特殊综合维度）
interface QuizDim {
  kind: string;
  qIdx: number;
  contents: string[];
}

const QUIZ_DIMS: QuizDim[] = [
  { kind: 'goal', qIdx: 0, contents: ['应用导向：先上手例子，再回头补原理', '掌握导向：先吃透原理，再谈应用', '兴趣驱动：节奏自由，宜小步快跑'] },
  { kind: 'preference', qIdx: -1, contents: ['求知欲强：答案宁深勿浅，值得追问到底', '结论优先：先给结论，感兴趣再深挖', '务实型：能用就行，不折腾原理'] }, // q12 优先 / q2 兜底
  { kind: 'preference', qIdx: 2, contents: ['例子驱动：故事和例子先行，原理自悟', '原理驱动：推导讲透，例子自己找', '灵活驱动：怎么讲得好怎么来'] },
  { kind: 'emotion', qIdx: -1, contents: ['心态稳：可直言错误与盲区，抗打击', '抗压一般：纠错宜先肯定再指问题', '易挫败：需低压力、多鼓励的节奏'] }, // q14 优先 / q4 兜底
  { kind: 'preference', qIdx: 4, contents: ['自律：提醒与安排可严格直接', '半自律：提醒宜温和但坚持', '随性：提醒宜轻量、趣味化'] },
  { kind: 'preference', qIdx: -1, contents: ['互动型：欢迎「考考你」提问与大白话翻译', '低互动：少考问少插话，直接讲', '适度互动：偶尔来一个钩子即可'] }, // q6+q10 综合
  { kind: 'preference', qIdx: 6, contents: ['好奇心强：反常识话题是强钩子', '好奇心中等：钩子点到为止', '务实：少用悬念式开场'] },
  { kind: 'preference', qIdx: 7, contents: ['极简口味：直给重点，零废话', '节奏口味：内容再硬也要留喘息位', '口味均衡：内容值就行'] },
  { kind: 'preference', qIdx: 8, contents: ['学习自信高：可直接上难度、跨知识点', '学习自信中等：难度平缓爬坡', '学习自信偏低：宜多铺垫、降门槛'] },
  { kind: 'preference', qIdx: 10, contents: ['爱分享：鼓励可热情夸张、放开了夸', '内敛：鼓励宜简短真诚', '低调：鼓励点到即止'] },
  { kind: 'preference', qIdx: 12, contents: ['学长式口吻：懂我、慢慢来', '教练式口吻：打气、往前冲', '工具式口吻：直接给答案，少寒暄'] },
  { kind: 'preference', qIdx: 14, contents: ['长时段沉浸型：内容可成块展开', '半小时分段型：宜按段分章', '碎片型：宜短小、可独立成段'] }
];

function choiceIdx(letter: string): number {
  if (letter === 'a') {
    return 0;
  }
  if (letter === 'b') {
    return 1;
  }
  if (letter === 'c') {
    return 2;
  }
  return -1;
}

/** 15 题答案 → 画像行数组（不足 15 答的维度按已答部分生成，缺答维度跳过） */
export function buildQuizProfileLines(answers: string[]): QuizProfileLine[] {
  const lines: QuizProfileLine[] = [];
  const get = (qIdx0: number): number => {
    return qIdx0 < answers.length ? choiceIdx(answers[qIdx0]) : -1;
  };
  for (let d = 0; d < QUIZ_DIMS.length; d++) {
    const dim = QUIZ_DIMS[d];
    let sel = -1;
    if (dim.qIdx >= 0) {
      sel = get(dim.qIdx);
    } else if (d === 1) {
      // 求知深度：q12（题号 11）优先，q2（题号 1）兜底——行为题优先于自评题
      sel = get(11) >= 0 ? get(11) : get(1);
    } else if (d === 3) {
      // 抗压：q14（题号 13）优先，q4（题号 3）兜底
      sel = get(13) >= 0 ? get(13) : get(3);
    } else {
      // 互动锚点：q6（题号 5）+ q10（题号 9）综合
      const q6 = get(5);
      const q10 = get(9);
      if (q6 === 0 && q10 === 0) {
        sel = 0; // 双 A=互动型
      } else if (q6 === 2 && q10 === 2) {
        sel = 1; // 双 C=低互动
      } else if (q6 < 0 && q10 < 0) {
        sel = -1; // 两题都未答→跳过
      } else {
        sel = 2; // 混合/单边=适度互动
      }
    }
    if (sel >= 0 && sel < dim.contents.length) {
      lines.push({ kind: dim.kind, content: dim.contents[sel] });
    }
  }
  return lines;
}

// ------------------------------------------------------------
// 画像写入（第 15 题答完时调用；done 标记幂等——只写一次）
// ------------------------------------------------------------
export function writeQuizProfile(quiz: PersonalityQuizStore, profileStore: ProfileStore): number {
  if (quiz.done) {
    return 0;
  }
  const answers = getQuizAnswers(quiz);
  const lines = buildQuizProfileLines(answers);
  const now = Date.now();
  for (let i = 0; i < lines.length; i++) {
    const obs = new ProfileObservation(generateMessageId(), lines[i].kind, lines[i].content,
      'personality-quiz', '', now, now);
    appendObservation(profileStore, obs);
  }
  quiz.done = true;
  quiz.completedAt = now;
  return lines.length;
}

/** 画像行内容预览（完成页展示用） */
export function quizProfilePreview(answers: string[]): string[] {
  const lines = buildQuizProfileLines(answers);
  const out: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    out.push(lines[i].content);
  }
  return out;
}
