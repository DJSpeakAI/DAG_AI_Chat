// SiyiPoint.test.ets — ★ 0.248.7 SP 实扣链路单元断言（§12.13 军令：纯逻辑抽纯函数走 hypium）
//   覆盖：余额口径（发放-消耗）/ 消耗顺序（gift→bonus→permanent，0.248.5 军令先嘉奖后充能）/
//   不足扣到 0 / 余额为 0 拒扣（false）/ 超额 clamp / 空参数安全
import { describe, it, expect } from '@ohos/hypium';
import { SiyiPointStore, siyiTotalSp, consumeSiyiSp } from '../../../main/ets/common/ChatModel';

export default function siyiPointTest() {
  describe('DAGAI_SiyiPointTest', () => {
    it('balance_grant_minus_consumed', 0, () => {
      const s = new SiyiPointStore();
      s.giftSp = 2000000;
      s.consumedGiftSp = 500;
      expect(siyiTotalSp(s)).assertEqual(1999500); // 余额=发放-消耗（0.248.7 池语义升级）
    })
    it('consume_order_gift_bonus_permanent', 0, () => {
      const s = new SiyiPointStore();
      s.giftSp = 100;
      s.bonusSp = 200;
      s.permanentSp = 300;
      const ok = consumeSiyiSp(s, 350);
      expect(ok).assertTrue();
      expect(s.consumedGiftSp).assertEqual(100);      // gift 先扣光
      expect(s.consumedBonusSp).assertEqual(200);     // bonus 次之扣光
      expect(s.consumedPermanentSp).assertEqual(50);  // permanent 兜底 50
      expect(siyiTotalSp(s)).assertEqual(250);        // 600-350
    })
    it('consume_over_balance_clamp_to_zero', 0, () => {
      const s = new SiyiPointStore();
      s.bonusSp = 100;
      const ok = consumeSiyiSp(s, 99999);
      expect(ok).assertTrue();                        // 有余额即扣（扣到 0 为止）
      expect(s.consumedBonusSp).assertEqual(100);
      expect(siyiTotalSp(s)).assertEqual(0);
    })
    it('consume_zero_balance_rejected', 0, () => {
      const s = new SiyiPointStore();                 // 全 0
      expect(consumeSiyiSp(s, 10)).assertFalse();     // 余额 0 拒扣（发送闸门依据）
      expect(consumeSiyiSp(s, 0)).assertTrue();       // 零消耗恒 true
    })
    it('balance_never_negative_on_weird_consumed', 0, () => {
      const s = new SiyiPointStore();
      s.giftSp = 100;
      s.consumedGiftSp = 150;                         // 异常态（理论上不该有）——clamp 0 防负数余额
      expect(siyiTotalSp(s)).assertEqual(0);
    })
  })
}
