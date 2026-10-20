// SpCostOfTokens.test.ets — ★ 0.272.0 SP 公式公共化等价断言（§12.13 军令：纯逻辑抽纯函数走 hypium）
//   覆盖：新旧公式对拍（ChatPage.spCostOf 原内联公式手写期望值——搬家零漂移证明）/
//   缓存命中钳位（cached>input 按 input 截）/ 零 token 零扣 / 纯输入/纯输出拆分展示值与总额一致 /
//   常量数值锚定（调价防漂——改常量必先过本组断言）
//   onUsage 透传为运行时链路（依赖网络请求成功路径），离线不可测——签名兼容由编译期保证。
import { describe, it, expect } from '@ohos/hypium';
import { spCostOfTokens, SP_TOKEN_DIVISOR, SP_COST_MULTIPLIER,
  SP_INPUT_PRICE_RATIO, SP_HIT_PRICE_RATIO, SP_OUTPUT_PRICE_RATIO } from '../../../main/ets/common/ChatModel';

// 旧公式原样复刻（0.248.7 ChatPage.spCostOf 搬家前内联实现——对拍基准，禁改）
function legacySpCost(inputTokens: number, outputTokens: number, cachedTokens: number): number {
  const hit = Math.min(cachedTokens, inputTokens);
  const miss = inputTokens - hit;
  const inSp = Math.round((miss * SP_INPUT_PRICE_RATIO + hit * SP_HIT_PRICE_RATIO) / SP_TOKEN_DIVISOR * SP_COST_MULTIPLIER);
  const outSp = Math.round(outputTokens * SP_OUTPUT_PRICE_RATIO / SP_TOKEN_DIVISOR * SP_COST_MULTIPLIER);
  return inSp + outSp;
}

export default function spCostOfTokensTest() {
  describe('DAGAI_SpCostOfTokensTest', () => {
    it('equivalence_with_legacy_formula', 0, () => {
      // 新旧公式对拍：典型量级（查词/提炼/聊天/大上下文）全覆盖，逐例相等
      const cases: number[][] = [
        [320, 180, 0],      // 查词典型：无缓存
        [1500, 260, 0],     // 提炼典型：无缓存
        [24000, 3000, 18000], // 聊天大上下文：高缓存命中
        [8000, 1200, 0],    // 聊天冷启动
        [100000, 8000, 95000] // 超长上下文深缓存
      ];
      for (let i = 0; i < cases.length; i++) {
        expect(spCostOfTokens(cases[i][0], cases[i][1], cases[i][2]))
          .assertEqual(legacySpCost(cases[i][0], cases[i][1], cases[i][2]));
      }
    })
    it('cached_over_input_clamped', 0, () => {
      // cached>input 按 input 截（防异常 usage 抬高命中折扣）——与旧公式同钳位
      expect(spCostOfTokens(100, 50, 99999)).assertEqual(legacySpCost(100, 50, 99999));
      expect(spCostOfTokens(100, 50, 100)).assertEqual(spCostOfTokens(100, 50, 99999)); // 全命中封顶
    })
    it('zero_tokens_zero_cost', 0, () => {
      // 失败/占位路径零 token 必零扣（失败零扣费铁律的公式侧保证）
      expect(spCostOfTokens(0, 0, 0)).assertEqual(0);
    })
    it('input_only_equals_in_sp', 0, () => {
      // 信息卡第一行拆分展示：纯输入值 + 纯输出值 = 总额（TokenInfoChip 两段展示与实扣一致）
      const inTok = 1400;
      const outTok = 350;
      const total = spCostOfTokens(inTok, outTok, 0);
      expect(total).assertEqual(spCostOfTokens(inTok, 0, 0) + spCostOfTokens(0, outTok, 0));
    })
    it('constants_anchored', 0, () => {
      // 计价常量数值锚定（0.247.7 终值——调价改常量必须同步改本断言，防无意识漂移）
      expect(SP_TOKEN_DIVISOR).assertEqual(7);
      expect(SP_COST_MULTIPLIER).assertEqual(2);
      expect(SP_INPUT_PRICE_RATIO).assertEqual(1);
      expect(SP_HIT_PRICE_RATIO).assertEqual(0.02);
      expect(SP_OUTPUT_PRICE_RATIO).assertEqual(4);
    })
    it('hand_computed_anchor', 0, () => {
      // 手算锚点：700 输入未命中 → 700×1/7×2=200 SP；700 输出 → 700×4/7×2=800 SP
      expect(spCostOfTokens(700, 0, 0)).assertEqual(200);
      expect(spCostOfTokens(0, 700, 0)).assertEqual(800);
      expect(spCostOfTokens(700, 700, 0)).assertEqual(1000);
    })
  })
}
