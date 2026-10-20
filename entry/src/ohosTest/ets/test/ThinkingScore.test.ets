// ThinkingScore.test.ets — ★ 0.271.0 深度思考模式纯函数断言（§12.13 军令：纯逻辑抽纯函数走 hypium）
//   覆盖：计分矩阵穷举（S5 直通/S1 长度/S2 串联边界/S3 追问/S4 硬核话题/阈值分档）/
//   策略矩阵（听播强制覆盖/GSD 三态/短中长三档）/ 降级关键词窄门判定 / thinkingMode 归一
import { describe, it, expect } from '@ohos/hypium';
import { scoreThinkingEffort, resolveThinkingFor, isThinkingParamError, normalizeThinkingMode,
  THINK_EFFORT_LOW, THINK_EFFORT_HIGH } from '../../../main/ets/common/ChatModel';

export default function thinkingScoreTest() {
  describe('DAGAI_ThinkingScoreTest', () => {
    // ── 计分矩阵（任务书 §3.2） ──
    it('s5_explicit_straight_to_high', 0, () => {
      // S5 显式指令直通 high（不走计分——即使零其他信号）
      expect(scoreThinkingEffort('仔细分析下', '', 0)).assertEqual(THINK_EFFORT_HIGH);
      expect(scoreThinkingEffort('深入分析', '', 0)).assertEqual(THINK_EFFORT_HIGH);
      expect(scoreThinkingEffort('好好想想这个问题', '', 0)).assertEqual(THINK_EFFORT_HIGH);
    })
    it('s2_alone_not_scored_chain_rule', 0, () => {
      // S2 串联条款：仅复杂度关键词、无 S1/S3/S4 支撑 = 不思考（「分析一下这个段子」式误判防线）
      expect(scoreThinkingEffort('分析一下这个段子', '', 0)).assertEqual('disabled');
      expect(scoreThinkingEffort('为什么呀', '', 0)).assertEqual('disabled');
    })
    it('s2_plus_s1_scores_low', 0, () => {
      // S1（≥60 字）+ S2 = 2 分 → low
      const longText = '请帮我分析一下这个算法的时间复杂度，并且说说它在最坏情况下的表现如何，是否有什么优化的空间呢？';
      expect(longText.length >= 60).assertTrue();
      expect(scoreThinkingEffort(longText, '', 0)).assertEqual(THINK_EFFORT_LOW);
    })
    it('s3_three_ai_messages_scores_low', 0, () => {
      // S3（AI 消息 ≥3 条）+ S2 = 3 分 → low
      expect(scoreThinkingEffort('说说它的原理', '', 3)).assertEqual(THINK_EFFORT_LOW);
    })
    it('s4_hard_topic_scores', 0, () => {
      // S4 硬核话题命中 topicTags = 2 分 → low（单独 2 分）
      expect(scoreThinkingEffort('这题怎么解', '数学、微积分', 0)).assertEqual(THINK_EFFORT_LOW);
      // S4 + S3 = 4 分 → high
      expect(scoreThinkingEffort('这题怎么解', '物理', 3)).assertEqual(THINK_EFFORT_HIGH);
      // S4 不命中 = 0
      expect(scoreThinkingEffort('这题怎么解', '美食、旅游', 0)).assertEqual('disabled');
    })
    it('s1_alone_stays_disabled', 0, () => {
      // S1 单独 1 分（无 S2）→ disabled（≤1）
      const longPlain = '今天天气不错我和朋友出去走了走聊了很多家常感觉心情舒畅了很多，晚上回来吃了一顿很好的晚饭。';
      expect(longPlain.length >= 60).assertTrue();
      expect(scoreThinkingEffort(longPlain, '', 0)).assertEqual('disabled');
    })
    it('greeting_never_thinks', 0, () => {
      // 「在吗」类寒暄零延迟直回（BAD 示例的断言面）
      expect(scoreThinkingEffort('在吗', '', 0)).assertEqual('disabled');
      expect(scoreThinkingEffort('你好', '', 0)).assertEqual('disabled');
    })
    it('full_stack_reaches_high', 0, () => {
      // S1+S2+S3 = 4 分 → high（无话题标签）
      const longQ = '请比较一下这两种架构的区别，各自的优缺点是什么，在什么场景下应该选择哪一种呢？请帮我仔细权衡一下。';
      expect(longQ.length >= 60).assertTrue();
      expect(scoreThinkingEffort(longQ, '', 3)).assertEqual(THINK_EFFORT_HIGH);
    })
    // ── 策略矩阵（任务书 §3.1） ──
    it('podcast_always_disabled_override', 0, () => {
      // 听播强制覆盖条款：无视 GSD 开关与「每次思考」恒 disabled（首字延迟高于一切）
      const r1 = resolveThinkingFor('always', 'long', true, '为什么光速不可超越？请仔细分析', '物理', 5);
      expect(r1.enabled).assertFalse();
      const r2 = resolveThinkingFor('auto', 'long', true, '', '', 0);
      expect(r2.enabled).assertFalse();
    })
    it('mode_off_all_disabled', 0, () => {
      const r = resolveThinkingFor('off', 'long', false, '仔细分析', '数学', 5);
      expect(r.enabled).assertFalse();
    })
    it('short_auto_disabled_always_low', 0, () => {
      // 短回复：auto=disabled；「每次思考」也仅升 low
      expect(resolveThinkingFor('auto', 'short', false, '', '', 0).enabled).assertFalse();
      const r = resolveThinkingFor('always', 'short', false, '', '', 0);
      expect(r.enabled).assertTrue();
      expect(r.effort).assertEqual(THINK_EFFORT_LOW);
    })
    it('long_always_high', 0, () => {
      // 长回复①段：auto 与 always 均 high（质量优先）
      expect(resolveThinkingFor('auto', 'long', false, '', '', 0).effort).assertEqual(THINK_EFFORT_HIGH);
      expect(resolveThinkingFor('always', 'long', false, '', '', 0).effort).assertEqual(THINK_EFFORT_HIGH);
    })
    it('medium_auto_by_score_always_high', 0, () => {
      // 中回复：auto 走计分（寒暄 disabled/深问 high）；always 直通 high
      expect(resolveThinkingFor('auto', 'medium', false, '在吗', '', 0).enabled).assertFalse();
      expect(resolveThinkingFor('auto', 'medium', false, '仔细分析', '', 0).effort).assertEqual(THINK_EFFORT_HIGH);
      expect(resolveThinkingFor('always', 'medium', false, '在吗', '', 0).effort).assertEqual(THINK_EFFORT_HIGH);
    })
    // ── 降级关键词窄门（任务书 §3.6） ──
    it('degrade_narrow_gate', 0, () => {
      // 仅 400 且匹配关键词才降
      expect(isThinkingParamError('API 返回错误（400）：invalid parameter thinking')).assertTrue();
      expect(isThinkingParamError('400 reasoning_effort not supported')).assertTrue();
      expect(isThinkingParamError('400 模型不支持该参数')).assertTrue();
      // 非 400 一律不降（防其他参数错误被误降级）
      expect(isThinkingParamError('401 invalid api key')).assertFalse();
      expect(isThinkingParamError('500 server error thinking')).assertFalse();
      // 400 但关键词不匹配（其他参数错误）不降
      expect(isThinkingParamError('400 invalid model id')).assertFalse();
      expect(isThinkingParamError('网络停滞：90 秒未收到 AI 数据')).assertFalse();
    })
    // ── thinkingMode 归一 ──
    it('thinking_mode_normalize', 0, () => {
      expect(normalizeThinkingMode('auto')).assertEqual('auto');
      expect(normalizeThinkingMode('always')).assertEqual('always');
      expect(normalizeThinkingMode('off')).assertEqual('off');
      expect(normalizeThinkingMode('')).assertEqual('auto');
      expect(normalizeThinkingMode('garbage')).assertEqual('auto');
    })
  })
}
