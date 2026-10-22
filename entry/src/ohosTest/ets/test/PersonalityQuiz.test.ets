// PersonalityQuiz.test.ets — ★ 0.288.0 性格测试纯函数断言（§12.13 军令：纯逻辑抽纯函数走 hypium）
//   ★ 0.290.0 性格测试 2.0 重写：开放题 answerTexts 存储 / 老用户字母+文本混合进度 /
//   本地关键词兜底（敷衍判定/命中文案/均衡兜底）/ 评阅输入组装（字母映射文案）
//   SP 节点阶梯断言延续保留。
//   ★ 0.292.1 性格测试 3.0：回归选择题（12 单选+3 多选）——choiceAnswers 存储 /
//   三段进度（字母+文本+选择）/ 评阅输入选择段拼接 / 题库 multi 标志完整性。
import { describe, it, expect } from '@ohos/hypium';
import {
  PERSONALITY_QUESTIONS, QUIZ_TOTAL, QUIZ_SP_PER_NODE,
  PersonalityQuizStore, getQuizAnswers, getQuizAnswerTexts, recordQuizAnswerText,
  getQuizChoices, recordQuizChoice, getQuizCustoms, recordQuizAnswerEntry, resetQuizForRetake,
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
    // ── 0.290.0 开放题答案追加与续做（0.292.1 起为兼容路径，存储行为不变） ──
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
    it('quiz_answer_text_bad_json_fallback', 0, () => {
      const s = new PersonalityQuizStore();
      s.answerTexts = '{bad json';
      expect(getQuizAnswerTexts(s).length).assertEqual(0); // 坏数据兜底不崩
    })
    // ── ★ 0.292.1 选择题答案追加与续做 ──
    it('quiz_choice_record_and_resume', 0, () => {
      const s = new PersonalityQuizStore();
      expect(getQuizChoices(s).length).assertEqual(0);
      expect(recordQuizChoice(s, 'a')).assertEqual(1);
      expect(recordQuizChoice(s, 'ac')).assertEqual(2);
      const arr = getQuizChoices(s);
      expect(arr.length).assertEqual(2);
      expect(arr[1]).assertEqual('ac'); // 多选拼接串原样落盘
      // 续做：新 store 实例从 choiceAnswers 落盘串恢复
      const s2 = new PersonalityQuizStore();
      s2.choiceAnswers = s.choiceAnswers;
      expect(getQuizChoices(s2).length).assertEqual(2);
    })
    it('quiz_choice_bad_json_fallback', 0, () => {
      const s = new PersonalityQuizStore();
      s.choiceAnswers = '{bad json';
      expect(getQuizChoices(s).length).assertEqual(0); // 坏数据兜底不崩
    })
    // ── 混合进度：老用户字母 + 开放题文本 + 选择题三段相加 ──
    it('quiz_total_letters_texts_choices', 0, () => {
      const s = new PersonalityQuizStore();
      s.answers = JSON.stringify(['a', 'b', 'c']);
      recordQuizAnswerText(s, '第四题答案');
      expect(quizAnswerTotal(s)).assertEqual(4); // 3 字母 + 1 文本
      recordQuizChoice(s, 'ac');
      recordQuizChoice(s, 'b');
      expect(quizAnswerTotal(s)).assertEqual(6); // 3 字母 + 1 文本 + 2 选择
    })
    // ── 评阅输入组装：字母映射文案 + 文本 + 选择段拼接 ──
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
    it('quiz_review_inputs_choice_segment', 0, () => {
      const s = new PersonalityQuizStore();
      recordQuizChoice(s, 'a');
      recordQuizChoice(s, 'ace'); // q3 多选题三选
      const inputs = buildReviewInputs(s);
      expect(inputs.length).assertEqual(QUIZ_TOTAL);
      // 选择段从第 0 位接续（无字母/文本）：'a'→q1 A 文案
      expect(inputs[0]).assertEqual(PERSONALITY_QUESTIONS[0].options[0].text);
      // 'ace'→q3（多选题 5 选项）A/C/E 三项文案顿号拼接
      const q3 = PERSONALITY_QUESTIONS[2];
      expect(inputs[1]).assertEqual(`${q3.options[0].text}、${q3.options[2].text}、${q3.options[4].text}`);
      expect(inputs[2]).assertEqual(''); // 未答=空串
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
    // ── 兜底关键词命中：选择题文案照样命中（q3 例子驱动） ──
    it('quiz_local_review_keyword_hit', 0, () => {
      const texts: string[] = [];
      for (let i = 0; i < QUIZ_TOTAL; i++) {
        texts.push(i === 2 ? '例子和故事、大白话类比打比方' : '正常作答的一些内容看看');
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
    // ── 题库完整性（★ 0.292.1 选择题 3.0：12 单选+3 多选；单选恰 3 选项、多选≥4） ──
    it('quiz_bank_15_questions_well_formed', 0, () => {
      expect(PERSONALITY_QUESTIONS.length).assertEqual(QUIZ_TOTAL);
      let prevTag = '';
      let multiCount = 0;
      for (let i = 0; i < PERSONALITY_QUESTIONS.length; i++) {
        const q = PERSONALITY_QUESTIONS[i];
        expect(q.index).assertEqual(i + 1);
        if (q.multi) {
          multiCount++;
          expect(q.options.length >= 4).assertTrue(); // 多选题选项 ≥4
        } else {
          expect(q.options.length === 3).assertTrue(); // 单选恰三选项（老用户字母映射+兜底文案源）
        }
        expect(q.question.length > 0).assertTrue();
        expect(q.tag.length > 0).assertTrue();
        expect(q.tag !== prevTag).assertTrue(); // 穿插铁律：相邻两题题型不同
        prevTag = q.tag;
      }
      expect(multiCount).assertEqual(3); // 恰 3 道多选（q3/q11/q15）
    })
    // ── 多选题位（q3/q11/q15）与选项文案可兜底性 ──
    it('quiz_bank_multi_positions', 0, () => {
      expect(PERSONALITY_QUESTIONS[2].multi).assertTrue();  // q3
      expect(PERSONALITY_QUESTIONS[10].multi).assertTrue(); // q11
      expect(PERSONALITY_QUESTIONS[14].multi).assertTrue(); // q15
      expect(PERSONALITY_QUESTIONS[0].multi).assertFalse(); // q1 单选
    })
    // ── 旧 answers 读取兼容（0.288 老用户数据不丢） ──
    it('quiz_legacy_answers_still_readable', 0, () => {
      const s = new PersonalityQuizStore();
      s.answers = JSON.stringify(['a', 'b', 'c']);
      expect(getQuizAnswers(s).length).assertEqual(3);
    })
    // ── ★ 0.298.0 自定义答案：原子双 push 等长 + 纯自定义空串计数 + 评阅并入 + 重做清空 ──
    it('quiz_custom_entry_atomic_double_push', 0, () => {
      const s = new PersonalityQuizStore();
      expect(getQuizCustoms(s).length).assertEqual(0);
      // 混合：q1 选 A + 自定义补充
      recordQuizAnswerEntry(s, 'a', '其实我想两者都要');
      // 纯自定义：q2 不选字母只写补充
      recordQuizAnswerEntry(s, '', '看心情，有时深有时浅');
      expect(getQuizChoices(s).length).assertEqual(2);
      expect(getQuizCustoms(s).length).assertEqual(2); // 两数组等长对齐
      expect(getQuizChoices(s)[1]).assertEqual(''); // 纯自定义 letters=空串
      expect(getQuizCustoms(s)[0]).assertEqual('其实我想两者都要');
      expect(quizAnswerTotal(s)).assertEqual(2); // 纯自定义照常计一答
    })
    it('quiz_custom_bad_json_fallback', 0, () => {
      const s = new PersonalityQuizStore();
      s.customAnswers = '{bad json';
      expect(getQuizCustoms(s).length).assertEqual(0); // 坏数据兜底不崩
    })
    it('quiz_custom_review_inputs_merged', 0, () => {
      const s = new PersonalityQuizStore();
      recordQuizAnswerEntry(s, 'a', '其实我想两者都要');   // 混合→「A 文案；自定义：xxx」
      recordQuizAnswerEntry(s, '', '看心情，有时深有时浅'); // 纯自定义→「自定义：xxx」
      recordQuizAnswerEntry(s, 'b', '');                    // 无自定义→纯选项文案
      const inputs = buildReviewInputs(s);
      expect(inputs[0]).assertEqual(`${PERSONALITY_QUESTIONS[0].options[0].text}；自定义：其实我想两者都要`);
      expect(inputs[1]).assertEqual('自定义：看心情，有时深有时浅');
      expect(inputs[2]).assertEqual(PERSONALITY_QUESTIONS[2].options[1].text);
    })
    it('quiz_custom_history_short_array_safe', 0, () => {
      // 历史数据 customs 短于 choices（0.298.0 前答的题无 custom 元素）——读侧越界兜底 ''
      const s = new PersonalityQuizStore();
      recordQuizChoice(s, 'a');
      const inputs = buildReviewInputs(s);
      expect(inputs[0]).assertEqual(PERSONALITY_QUESTIONS[0].options[0].text); // 无 custom 不拼接不崩
    })
    it('quiz_custom_reset_for_retake_cleared', 0, () => {
      const s = new PersonalityQuizStore();
      recordQuizAnswerEntry(s, 'a', '自定义内容');
      resetQuizForRetake(s);
      expect(getQuizChoices(s).length).assertEqual(0);
      expect(getQuizCustoms(s).length).assertEqual(0); // ★ 0.298.0 自定义同步清零
    })
  })
}