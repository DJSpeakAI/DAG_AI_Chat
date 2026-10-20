// SpImplicitCost.test.ets — ★ 0.273.0 后台毛利财务报表单元断言（§12.13 军令：纯逻辑抽纯函数走 hypium）
//   覆盖：隐式扣费纯核心 consumeImplicitSpCore（Lv8 免扣零动账/正常实扣/余额不足 clamp/0 余额一分不扣）/
//   IAP 成交价换算 iapAmtFromPurchaseData（分→元/NaN 保底/缺失保底/400W 档保底）
//   ⚠️ AiRerank「无日限」（0.273.0 删 AI_RERANK_DAILY_LIMIT）不设运行时断言——运行时无法观测
//   「常量已不存在」，编译期已保证 + 真机验收（任务书验收标准 4：连续问答 30 次每次都在排）
import { describe, it, expect } from '@ohos/hypium';
import { SiyiPointStore, siyiTotalSp, consumeImplicitSpCore, IAP_PRODUCT_SP_200W } from '../../../main/ets/common/ChatModel';
import { iapAmtFromPurchaseData } from '../../../main/ets/utils/IapUtil';

export default function spImplicitCostTest() {
  describe('DAGAI_SpImplicitCostTest', () => {
    // ── 隐式扣费纯核心（0.273.0 翻案：rerank/profile/summary 实扣并入总账） ──
    it('implicit_free_lv8_zero_touch', 0, () => {
      const s = new SiyiPointStore();
      s.giftSp = 1000;
      const actual: number = consumeImplicitSpCore(s, true, 350); // Lv8 免扣
      expect(actual).assertEqual(0);                       // 一分不扣
      expect(s.consumedGiftSp).assertEqual(0);             // store 零动账（免扣≠扣 0 后补）
    })
    it('implicit_charge_normal', 0, () => {
      const s = new SiyiPointStore();
      s.giftSp = 100;
      s.bonusSp = 200;
      s.permanentSp = 300;
      const actual: number = consumeImplicitSpCore(s, false, 350);
      expect(actual).assertEqual(350);                     // 全额实扣（与 spCostOfTokens 同公式口径）
      expect(siyiTotalSp(s)).assertEqual(250);
    })
    it('implicit_charge_clamp_on_short', 0, () => {
      const s = new SiyiPointStore();
      s.bonusSp = 100;
      const actual: number = consumeImplicitSpCore(s, false, 99999); // 余额不足
      expect(actual).assertEqual(100);                       // clamp 到 0 为止（0.248.7 先例）
      expect(siyiTotalSp(s)).assertEqual(0);
    })
    it('implicit_zero_balance_zero_spent', 0, () => {
      const s = new SiyiPointStore();                        // 全 0 余额
      const actual: number = consumeImplicitSpCore(s, false, 500);
      expect(actual).assertEqual(0);                         // 一分不扣（事后扣无闸门——负余额不可能）
    })
    it('implicit_zero_cost_noop', 0, () => {
      const s = new SiyiPointStore();
      s.giftSp = 100;
      expect(consumeImplicitSpCore(s, false, 0)).assertEqual(0); // 零消耗（onDone usage 全 0）
      expect(siyiTotalSp(s)).assertEqual(100);
    })
    // ── IAP 成交价换算（InAppPurchaseData.price 单位分——d.ts 实查） ──
    it('iap_amt_fen_to_cny', 0, () => {
      const r: Record<string, Object> = {};
      r['price'] = 990; // 990 分 = ¥9.90
      expect(iapAmtFromPurchaseData(r, IAP_PRODUCT_SP_200W)).assertEqual('9.90');
      r['price'] = 1900;
      expect(iapAmtFromPurchaseData(r, IAP_PRODUCT_SP_200W)).assertEqual('19.00');
      r['price'] = 1; // 1 分 = ¥0.01（最小额也如实）
      expect(iapAmtFromPurchaseData(r, IAP_PRODUCT_SP_200W)).assertEqual('0.01');
    })
    it('iap_amt_fallback_on_invalid', 0, () => {
      const r: Record<string, Object> = {};
      r['price'] = 'not_a_number'; // 字符串脏值 → NaN → 保底
      expect(iapAmtFromPurchaseData(r, IAP_PRODUCT_SP_200W)).assertEqual('9.90');
      r['price'] = 0; // 非法 0/负数 → 保底（看板求和容错）
      expect(iapAmtFromPurchaseData(r, IAP_PRODUCT_SP_200W)).assertEqual('9.90');
      r['price'] = -5;
      expect(iapAmtFromPurchaseData(r, IAP_PRODUCT_SP_200W)).assertEqual('9.90');
      const r2: Record<string, Object> = {}; // 字段整体缺失 → 保底
      expect(iapAmtFromPurchaseData(r2, IAP_PRODUCT_SP_200W)).assertEqual('9.90');
    })
  })
}

