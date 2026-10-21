// PersonalityQuiz.test.ets — ★ 0.288.0 性格测试纯函数断言（§12.13 军令：纯逻辑抽纯函数走 hypium）
//   覆盖：SP 节点阶梯（quizNodeReached/buildQuizClaimAmount 幂等差额）/ 答案追加与续做读取 /
//   画像转译 12 行与 kind 四枚举合法 / 交叉验证（q12 优先于 q2、q14 优先于 q4——行为题优先）/
//   互动锚点综合（双 A=互动 / 双 C=低互动 / 混合=适度）/ 画像行长度红线（≤60 字）
import { describe, it, expect } from '@ohos/hypium';
import {
  PERSONALITY_QUESTIONS, QUIZ_TOTAL, QUIZ_SP_PER_NODE, QuizProfileLine,
  PersonalityQuizStore, getQuizAnswers, recordQuizAnswer,
  quizNodeReached, buildQuizClaimAmount, buildQuizProfileLines, quizProfilePreview
} from '../../../main/ets/common/PersonalityQuiz';

function allAnswer(letter: string): string[] {
  const arr: string[] = [];
  for (let i = 0; i < QUIZ_TOTAL; i++) {
    arr.push(letter);
  }
  return arr;
}

function answersOf(picks: Record<string, string>): string[] {
  // picks: 题号(1起)→选项；未提到的题默认 'b'
  const arr: string[] = [];
  for (let i = 1; i <= QUIZ_TOTAL; i++) {
    const key = `${i}`;
    arr.push(picks[key] !== undefined ? picks[key] : 'b');
  }
  return arr;
}

export default function personalityQuizTest() {
  describe('DAGAI_PersonalityQuizTest', () => {
    // ── SP 节点阶梯 ──
    it('quiz_node_reached_ladder', 0, () => {
      expect(quizNodeReached(0)).assertEqual(0);
      expect(quizNodeReached(4)).assertEqual(0);
      expect(quizNodeReached(5)).assertEqual(1);
      expect(quizNodeReached(9)).assertEqual(1);
      expect(quizNodeReached(10)).assertEqual(2);
      expect(quizNodeReached(14)).assertEqual(2);
      expect(quizNodeReached(15)).assertEqual(3);
      expect(quizNodeReached(20)).assertEqual(3); // 上限钳位
      expect(quizNodeReached(-3)).assertEqual(0); // 负数兜底
    })
    it('quiz_claim_amount_idempotent_gap', 0, () => {
      expect(buildQuizClaimAmount(0, 5)).assertEqual(QUIZ_SP_PER_NODE);
      expect(buildQuizClaimAmount(1, 5)).assertEqual(0);   // 已领节点 1 不重发
      expect(buildQuizClaimAmount(0, 4)).assertEqual(0);   // 未到节点
      expect(buildQuizClaimAmount(1, 10)).assertEqual(QUIZ_SP_PER_NODE);
      expect(buildQuizClaimAmount(2, 15)).assertEqual(QUIZ_SP_PER_NODE);
      expect(buildQuizClaimAmount(3, 15)).assertEqual(0);  // 全领完
      expect(buildQuizClaimAmount(0, 15)).assertEqual(QUIZ_SP_PER_NODE * 3); // 一次性补三节点
    })
    // ── 答案追加与续做 ──
    it('quiz_answer_append_and_resume', 0, () => {
      const s = new PersonalityQuizStore();
      expect(getQuizAnswers(s).length).assertEqual(0);
      expect(recordQuizAnswer(s, 'a')).assertEqual(1);
      expect(recordQuizAnswer(s, 'c')).assertEqual(2);
      const arr = getQuizAnswers(s);
      expect(arr.length).assertEqual(2);
      expect(arr[0]).assertEqual('a');
      expect(arr[1]).assertEqual('c');
      // 续做：新 store 实例从 raw 恢复（断点续做同理由 JSON 落盘恢复）
      const s2 = new PersonalityQuizStore();
      s2.answers = s.answers;
      expect(getQuizAnswers(s2).length).assertEqual(2);
    })
    it('quiz_bad_json_fallback_empty', 0, () => {
      const s = new PersonalityQuizStore();
      s.answers = '{bad json';
      expect(getQuizAnswers(s).length).assertEqual(0); // 坏数据兜底不崩
    })
    // ── 画像转译 ──
    it('quiz_profile_lines_count_and_kind_enum', 0, () => {
      const lines = buildQuizProfileLines(allAnswer('a'));
      expect(lines.length).assertEqual(12); // 12 维度全量
      const legalKinds: string[] = ['identity', 'goal', 'preference', 'emotion'];
      let hasGoal = false;
      let hasEmotion = false;
      for (let i = 0; i < lines.length; i++) {
        expect(legalKinds.includes(lines[i].kind)).assertTrue(); // 四枚举之外拒收（Schema 铁律）
        if (lines[i].kind === 'goal') {
          hasGoal = true;
        }
        if (lines[i].kind === 'emotion') {
          hasEmotion = true;
        }
        expect(lines[i].content.length <= 60).assertTrue(); // ProfileObservation 长度红线
        expect(lines[i].content.length > 0).assertTrue();
      }
      expect(hasGoal).assertTrue();
      expect(hasEmotion).assertTrue();
    })
    it('quiz_profile_partial_answers_skip_missing_dims', 0, () => {
      // 只答 1 题（q1）→ 仅 1 行（其余维度缺答跳过）
      const lines = buildQuizProfileLines(['a']);
      expect(lines.length).assertEqual(1);
      expect(lines[0].kind).assertEqual('goal');
      expect(lines[0].content.includes('应用导向')).assertTrue();
      // 一题未答 → 0 行
      expect(buildQuizProfileLines([]).length).assertEqual(0);
    })
    // ── 交叉验证：行为题优先于自评题 ──
    it('quiz_crosscheck_q12_overrides_q2', 0, () => {
      // q2=a（讲得越深越爽）但 q12=c（能用就行）→ 以 q12 为准=务实型
      const lines = buildQuizProfileLines(answersOf({ '2': 'a', '12': 'c' }));
      let found = '';
      for (let i = 0; i < lines.length; i++) {
        if (lines[i].content.includes('务实型')) {
          found = lines[i].content;
        }
      }
      expect(found.length > 0).assertTrue();
      // 反向：q12=a q2=c → 求知欲强（q12 优先）
      const lines2 = buildQuizProfileLines(answersOf({ '2': 'c', '12': 'a' }));
      let found2 = false;
      for (let i = 0; i < lines2.length; i++) {
        if (lines2[i].content.includes('求知欲强')) {
          found2 = true;
        }
      }
      expect(found2).assertTrue();
    })
    it('quiz_crosscheck_q14_overrides_q4', 0, () => {
      // q4=a（错了有意思）但 q14=c（怀疑自己）→ 以 q14 为准=易挫败（emotion）
      const lines = buildQuizProfileLines(answersOf({ '4': 'a', '14': 'c' }));
      let found = false;
      for (let i = 0; i < lines.length; i++) {
        if (lines[i].kind === 'emotion' && lines[i].content.includes('易挫败')) {
          found = true;
        }
      }
      expect(found).assertTrue();
    })
    // ── 互动锚点综合（q6+q10）──
    it('quiz_anchor_combo_rules', 0, () => {
      // 双 A=互动型
      let lines = buildQuizProfileLines(answersOf({ '6': 'a', '10': 'a' }));
      expect(lines.some((l: QuizProfileLine) => l.content.includes('互动型'))).assertTrue();
      // 双 C=低互动
      lines = buildQuizProfileLines(answersOf({ '6': 'c', '10': 'c' }));
      expect(lines.some((l: QuizProfileLine) => l.content.includes('低互动'))).assertTrue();
      // A+C 混合=适度互动
      lines = buildQuizProfileLines(answersOf({ '6': 'a', '10': 'c' }));
      expect(lines.some((l: QuizProfileLine) => l.content.includes('适度互动'))).assertTrue();
      // q6/q10 都未答 → 互动维度跳过：答完前 5 题（q1/q2/q3/q4/q5 五维度各 1 行）恰 5 行
      expect(buildQuizProfileLines(['b', 'b', 'b', 'b', 'b']).length).assertEqual(5);
    })
    // ── 题库完整性 ──
    it('quiz_bank_15_questions_well_formed', 0, () => {
      expect(PERSONALITY_QUESTIONS.length).assertEqual(QUIZ_TOTAL);
      let prevTag = '';
      for (let i = 0; i < PERSONALITY_QUESTIONS.length; i++) {
        const q = PERSONALITY_QUESTIONS[i];
        expect(q.index).assertEqual(i + 1);
        expect(q.options.length === 3).assertTrue(); // 每题三选项
        expect(q.question.length > 0).assertTrue();
        expect(q.tag.length > 0).assertTrue();
        expect(q.tag !== prevTag).assertTrue(); // 穿插铁律：相邻两题题型不同
        prevTag = q.tag;
      }
    })
    it('quiz_preview_strings', 0, () => {
      const preview = quizProfilePreview(allAnswer('b'));
      expect(preview.length).assertEqual(12);
      for (let i = 0; i < preview.length; i++) {
        expect(preview[i].length > 0).assertTrue();
      }
    })
  })
}