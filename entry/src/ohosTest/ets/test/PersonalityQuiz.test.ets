// PersonalityQuiz.test.ets — ★ 0.288.0 性格测试纯函数断言（§12.13 军令：纯逻辑抽纯函数走 hypium）
//   ★ 0.290.0 性格测试 2.0 重写：开放题 answerTexts 存储 / 老用户字母+文本混合进度 /
//   本地关键词兜底（敷衍判定/命中文案/均衡兜底）/ 评阅输入组装（字母映射文案）
//   SP 节点阶梯断言延续保留。
import { describe, it, expect } from '@ohos/hypium';
import {
  PERSONALITY_QUESTIONS, QUIZ_TOTAL, QUIZ_SP_PER_NODE,
  PersonalityQuizStore, getQuizAnswers, getQuizAnswerTexts, recordQuizAnswerText,
  quizAnswerTotal, quizNodeReached, buildQuizClaimAmount,
  buildReviewInputs, localReviewQuizTexts, isInvalidQuizAnswer, quizProfilePreviewLines
} from '../../../main/ets/common/PersonalityQuiz';

export default function personalityQuizTest() {
  describe('DAGAI_PersonalityQuizTest', () => {
    // ── SP 节点阶梯（延续 0.288.0） ──
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
    // ── 0.290.0 开放题答案追加与续做 ──
    it('quiz_answer_text_append_and_resume', 0, () => {
      const s = new PersonalityQuizStore();
      expect(getQuizAnswerTexts(s).length).assertEqual(0);
      expect(recordQuizAnswerText(s, '马上找题试试手')).assertEqual(1);
      expect(recordQuizAnswerText(s, '先琢磨为什么')).assertEqual(2);
      const arr = getQuizAnswerTexts(s);
      expect(arr.length).assertEqual(2);
      expect(arr[0]).assertEqual('马上找题试试手');
      // 续做：新 store 实例从 answerTexts 落盘串恢复
      const s2 = new PersonalityQuizStore();
      s2.answerTexts = s.answerTexts;
      expect(getQuizAnswerTexts(s2).length).assertEqual(2);
    })
    it('quiz_answer_text_trimmed', 0, () => {
      const s = new PersonalityQuizStore();
      recordQuizAnswerText(s, '  带空白的答案  ');
      expect(getQuizAnswerTexts(s)[0]).assertEqual('带空白的答案'); // 首尾空白即时修剪
    })
    it('quiz_answer_text_bad_json_fallback', 0, () => {
      const s = new PersonalityQuizStore();
      s.answerTexts = '{bad json';
      expect(getQuizAnswerTexts(s).length).assertEqual(0); // 坏数据兜底不崩
    })
    // ── 混合进度：老用户字母 + 新开放题文本相加 ──
    it('quiz_total_letters_plus_texts', 0, () => {
      const s = new PersonalityQuizStore();
      s.answers = JSON.stringify(['a', 'b', 'c']);
      expect(quizAnswerTotal(s)).assertEqual(3);
      recordQuizAnswerText(s, '第四题答案');
      recordQuizAnswerText(s, '第五题答案');
      expect(quizAnswerTotal(s)).assertEqual(5); // 3 字母 + 2 文本
    })
    // ── 评阅输入组装：字母映射回三选一文案 ──
    it('quiz_review_inputs_letter_mapped', 0, () => {
      const s = new PersonalityQuizStore();
      s.answers = JSON.stringify(['a', 'b']);
      recordQuizAnswerText(s, '自由文本答案');
      const inputs = buildReviewInputs(s);
      expect(inputs.length).assertEqual(QUIZ_TOTAL);
      expect(inputs[0]).assertEqual(PERSONALITY_QUESTIONS[0].options[0].text); // 'a'→A 选项文案
      expect(inputs[1]).assertEqual(PERSONALITY_QUESTIONS[1].options[1].text); // 'b'→B 选项文案
      expect(inputs[2]).assertEqual('自由文本答案'); // 文本从 letters.length 位接续
      expect(inputs[3]).assertEqual(''); // 未答=空串（评阅判无效）
    })
    // ── 敷衍答案判定 ──
    it('quiz_invalid_answer_patterns', 0, () => {
      expect(isInvalidQuizAnswer('111')).assertTrue();
      expect(isInvalidQuizAnswer('不知道')).assertTrue();
      expect(isInvalidQuizAnswer('随便')).assertTrue();
      expect(isInvalidQuizAnswer('???')).assertTrue(); // 纯符号
      expect(isInvalidQuizAnswer('')).assertTrue();
      expect(isInvalidQuizAnswer('好')).assertTrue(); // 单字
      expect(isInvalidQuizAnswer('先琢磨它为什么成立')).assertFalse();
      expect(isInvalidQuizAnswer('马上找道题试试手')).assertFalse();
    })
    // ── 本地关键词兜底：12 维全量 + kind 四枚举 ──
    it('quiz_local_review_full_and_legal_kinds', 0, () => {
      const texts: string[] = [];
      for (let i = 0; i < QUIZ_TOTAL; i++) {
        texts.push('我会先琢磨它为什么成立，用例子和类比帮助理解');
      }
      const lines = localReviewQuizTexts(texts);
      expect(lines.length).assertEqual(12);
      const legalKinds: string[] = ['identity', 'goal', 'preference', 'emotion'];
      let hasGoal = false;
      let hasEmotion = false;
      for (let i = 0; i < lines.length; i++) {
        expect(legalKinds.includes(lines[i].kind)).assertTrue();
        expect(lines[i].content.length > 0).assertTrue();
        expect(lines[i].content.length <= 60).assertTrue();
        if (lines[i].kind === 'goal') {
          hasGoal = true;
        }
        if (lines[i].kind === 'emotion') {
          hasEmotion = true;
        }
      }
      expect(hasGoal).assertTrue();
      expect(hasEmotion).assertTrue();
    })
    // ── 兜底关键词命中：q3 例子驱动 ──
    it('quiz_local_review_keyword_hit', 0, () => {
      const texts: string[] = [];
      for (let i = 0; i < QUIZ_TOTAL; i++) {
        texts.push(i === 2 ? '希望老师多讲例子和故事打比方' : '正常作答的一些内容看看');
      }
      const lines = localReviewQuizTexts(texts);
      let hit = false;
      for (let i = 0; i < lines.length; i++) {
        if (lines[i].content.includes('例子驱动')) {
          hit = true;
        }
      }
      expect(hit).assertTrue(); // 第 3 维（q3 例子vs原理）命中关键词→例子驱动
    })
    // ── 兜底防空画像：有效证据 <5 题 → 全 12 行均衡型（坑3） ──
    it('quiz_local_review_invalid_majority_neutral', 0, () => {
      const texts: string[] = [];
      for (let i = 0; i < QUIZ_TOTAL; i++) {
        texts.push('111'); // 全敷衍
      }
      const lines = localReviewQuizTexts(texts);
      expect(lines.length).assertEqual(12); // 禁止空数组
      let neutralCount = 0;
      for (let i = 0; i < lines.length; i++) {
        if (lines[i].content.includes('均衡')) {
          neutralCount++;
        }
      }
      expect(neutralCount).assertEqual(12); // 全部均衡型默认文案
    })
    // ── 预览行 ──
    it('quiz_preview_lines', 0, () => {
      const lines = localReviewQuizTexts(['正常答案一', '正常答案二', '正常答案三', '正常答案四', '正常答案五',
        '正常答案六', '正常答案七', '正常答案八', '正常答案九', '正常答案十',
        '正常答案十一', '正常答案十二', '正常答案十三', '正常答案十四', '正常答案十五']);
      const preview = quizProfilePreviewLines(lines);
      expect(preview.length).assertEqual(12);
      for (let i = 0; i < preview.length; i++) {
        expect(preview[i].length > 0).assertTrue();
      }
    })
    // ── 题库完整性（0.290.0 开放题：题干更新+穿插铁律+三选项保留作映射源） ──
    it('quiz_bank_15_questions_well_formed', 0, () => {
      expect(PERSONALITY_QUESTIONS.length).assertEqual(QUIZ_TOTAL);
      let prevTag = '';
      for (let i = 0; i < PERSONALITY_QUESTIONS.length; i++) {
        const q = PERSONALITY_QUESTIONS[i];
        expect(q.index).assertEqual(i + 1);
        expect(q.options.length === 3).assertTrue(); // 三选项保留（老用户字母映射+兜底文案源）
        expect(q.question.length > 0).assertTrue();
        expect(q.tag.length > 0).assertTrue();
        expect(q.tag !== prevTag).assertTrue(); // 穿插铁律：相邻两题题型不同
        prevTag = q.tag;
      }
    })
    // ── 旧 answers 读取兼容（0.288 老用户数据不丢） ──
    it('quiz_legacy_answers_still_readable', 0, () => {
      const s = new PersonalityQuizStore();
      s.answers = JSON.stringify(['a', 'b', 'c']);
      expect(getQuizAnswers(s).length).assertEqual(3);
    })
  })
}
