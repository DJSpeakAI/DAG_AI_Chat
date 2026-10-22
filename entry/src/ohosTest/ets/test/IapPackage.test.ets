import { describe, it, expect } from '@ohos/hypium';
import { SiyiPointStore, SubscriptionStore, siyiTotalSp, consumeSiyiSp,
  IapPackage, parseIapPackages, ensureIapPackagesMigrated, writeOffRefundedPackage,
  grantSiyiSpFromIap, IAP_PRODUCT_SP_400W } from '../../../main/ets/common/ChatModel';

// ★ 0.289.0 充能包账本断言（§12.13 军令）：迁移重建/FIFO 回放/按包 FIFO 扣费/退款核销守恒/grant 建包联动
//   （用户政策三条：嘉奖先扣→购买顺序逐包扣→整包未消耗可退）
export default function iapPackageTest() {
  describe('DAGAI_IapPackageTest', () => {
    // 构造旧版历史账（grantSiyiSpFromIap 的文本格式：token 前 8 位+日期无时分秒）
    const historyWith = (lines: string[]): SubscriptionStore => {
      const sub = new SubscriptionStore();
      sub.purchaseHistory = JSON.stringify(lines);
      return sub;
    };

    // ---- ★ 0.289.1 旧测试充能账一次性清零（用户拍板：600 万旧账无精确时间，清零重测）----
    it('wipe_legacy_clears_pool_packages_history', 0, () => {
      const sub = historyWith([
        '兑换 +100 万司忆点（兑换码）｜2026/10/20',
        '充能 +200 万司忆点｜华为应用内支付 AbCd1234…｜2026/10/21',
        '充能 +400 万司忆点｜华为应用内支付 EfGh5678…｜2026/10/22'
      ]);
      const s = new SiyiPointStore();
      s.permanentSp = 6000000;
      s.consumedPermanentSp = 100;
      ensureIapPackagesMigrated(sub, s);
      expect(s.permanentSp).assertEqual(0);              // 池级归零
      expect(s.consumedPermanentSp).assertEqual(0);
      expect(parseIapPackages(s.iapPackages).length).assertEqual(0); // 包账本清空
      const kept = JSON.parse(sub.purchaseHistory) as string[];
      expect(kept.length).assertEqual(1);                // 非充能行保留
      expect(kept[0].indexOf('兑换') === 0).assertTrue();
    })
    // 幂等：清后无充能行零改动；无充能账的设备（180 测试号）不触发
    it('wipe_idempotent_and_noop_without_legacy', 0, () => {
      const sub = historyWith(['充能 +200 万司忆点｜华为应用内支付 AbCd1234…｜2026/10/21']);
      const s = new SiyiPointStore();
      s.permanentSp = 2000000;
      ensureIapPackagesMigrated(sub, s);
      const after = sub.purchaseHistory;
      ensureIapPackagesMigrated(sub, s);
      expect(sub.purchaseHistory === after).assertTrue(); // 二次清零零改动
      const sub2 = historyWith(['兑换 +100 万司忆点｜2026/10/20']);
      const s2 = new SiyiPointStore();
      s2.bonusSp = 50000; // 嘉奖账不受影响
      ensureIapPackagesMigrated(sub2, s2);
      expect(s2.bonusSp).assertEqual(50000);
      expect(s2.permanentSp).assertEqual(0);
    })

    // ---- 按包 FIFO 扣费：嘉奖先扣→老包先扣→跨包拆分；池级与包级守恒 ----
    it('consume_fifo_bonus_first_then_oldest_package', 0, () => {
      const s = new SiyiPointStore();
      s.bonusSp = 5000;                 // 嘉奖 5000
      s.permanentSp = 6000000;          // 充能 600 万（两包）
      const pkgs: IapPackage[] = [];
      const p1 = new IapPackage();      // 老包 200 万
      p1.tok = 'OLD'; p1.amt = 2000000; p1.ts = 1000;
      const p2 = new IapPackage();      // 新包 400 万
      p2.tok = 'NEW'; p2.amt = 4000000; p2.ts = 2000;
      pkgs.push(p1); pkgs.push(p2);
      s.iapPackages = JSON.stringify(pkgs);
      const ok = consumeSiyiSp(s, 2005000 + 5000); // 扣 201 万（嘉奖 5000 全扣+充能 200 万+再跨包 5000）
      expect(ok).assertTrue();
      expect(s.consumedBonusSp).assertEqual(5000);       // 嘉奖先扣光
      expect(s.consumedPermanentSp).assertEqual(2005000);
      const after = parseIapPackages(s.iapPackages);
      expect(after[0].cons).assertEqual(2000000);        // 老包耗尽
      expect(after[1].cons).assertEqual(5000);           // 溢出 5000 落新包（跨包拆分）
      expect(siyiTotalSp(s)).assertEqual(3995000);       // 余额守恒
    })
    // 包账本为空时扣池级不炸（迁移未跑窗口）——迁移后按终值回放，最终一致
    it('consume_without_packages_pool_only', 0, () => {
      const s = new SiyiPointStore();
      s.permanentSp = 1000000;
      expect(consumeSiyiSp(s, 300000)).assertTrue();
      expect(s.consumedPermanentSp).assertEqual(300000);
      expect(parseIapPackages(s.iapPackages).length).assertEqual(0);
    })

    // ---- 退款核销：剩余作废+ref=1+幂等；池级发放累计不动（只增军令）----
    it('writeoff_refunded_package_conservation', 0, () => {
      const s = new SiyiPointStore();
      s.permanentSp = 6000000;
      const pkgs: IapPackage[] = [];
      const p1 = new IapPackage();
      p1.tok = 'TOK200'; p1.amt = 2000000;
      const p2 = new IapPackage();
      p2.tok = 'TOK400'; p2.amt = 4000000;
      pkgs.push(p1); pkgs.push(p2);
      s.iapPackages = JSON.stringify(pkgs);
      const before = siyiTotalSp(s);
      const written = writeOffRefundedPackage(s, 'TOK200'); // 200 万包未消耗全额作废
      expect(written).assertEqual(2000000);
      expect(s.permanentSp).assertEqual(6000000);       // 发放累计不动
      expect(s.consumedPermanentSp).assertEqual(2000000);
      expect(siyiTotalSp(s)).assertEqual(before - 2000000); // 余额减作废额=守恒
      const after = parseIapPackages(s.iapPackages);
      expect(after[0].ref).assertEqual(1);
      expect(after[0].cons).assertEqual(2000000);
      expect(writeOffRefundedPackage(s, 'TOK200')).assertEqual(0); // 幂等：二核 0
      expect(writeOffRefundedPackage(s, 'NO-SUCH')).assertEqual(0); // 未命中 0
    })

    // ---- grant 建包：旧账存在时先清零再建新包（tok 全量/精确时间）；token 幂等拒双发 ----
    it('grant_after_wipe_creates_single_package', 0, () => {
      const sub = historyWith(['充能 +200 万司忆点｜华为应用内支付 AbCd1234…｜2026/10/21']);
      const s = new SiyiPointStore();
      s.permanentSp = 2000000; // 旧测试账
      const ok = grantSiyiSpFromIap(sub, s, IAP_PRODUCT_SP_400W, 'FULLTOKEN092XXXXXXXXXXXXXXXXXXXXXXXX', '19.00');
      expect(ok).assertTrue();
      expect(s.permanentSp).assertEqual(4000000); // 旧账已清+新包 400 万（不是 600 万）
      const list = parseIapPackages(s.iapPackages);
      expect(list.length).assertEqual(1); // 仅新包（旧包已随清零移除）
      expect(list[0].tok).assertEqual('FULLTOKEN092XXXXXXXXXXXXXXXXXXXXXXXX');
      expect(list[0].amt).assertEqual(4000000);
      expect(list[0].ts > 0).assertTrue(); // 精确到秒时间戳
      // token 幂等：重复 grant 拒双发
      expect(grantSiyiSpFromIap(sub, s, IAP_PRODUCT_SP_400W, 'FULLTOKEN092XXXXXXXXXXXXXXXXXXXXXXXX', '19.00')).assertFalse();
    })
  })
}
