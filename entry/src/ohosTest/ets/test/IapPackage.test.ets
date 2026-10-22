import { describe, it, expect } from '@ohos/hypium';
import { SiyiPointStore, SubscriptionStore, siyiTotalSp, consumeSiyiSp,
  IapPackage, parseIapPackages, ensureIapPackagesMigrated, writeOffRefundedPackage,
  freezePackageUntil, frozenAvailableSp, REFUND_FREEZE_MS,
  grantSiyiSpFromIap, IAP_PRODUCT_SP_400W } from '../../../main/ets/common/ChatModel';

// ★ 0.289.0 充能包账本断言（§12.13 军令）：写销/按包 FIFO 扣费/退款核销守恒/冻结锁包/grant 建包联动
//   ★ 0.290.2 清零改写销语义（归零被云同步 max 复活根治）：permanentSp 不动+consumedPermanentSp 写满
//   ★ 0.291.0 冻结锁包：退款申请 7 天锁——FIFO 跳过+可用余额三处同源排除
export default function iapPackageTest() {
  describe('DAGAI_IapPackageTest', () => {
    const historyWith = (lines: string[]): SubscriptionStore => {
      const sub = new SubscriptionStore();
      sub.purchaseHistory = JSON.stringify(lines);
      return sub;
    };

    // ---- ★ 0.290.2 写销路A：迁移包（tok<92）存在 → 包写满+池级写销（余额 0 且单调不减）----
    it('writeoff_legacy_migration_packages_path_a', 0, () => {
      const sub = historyWith(['兑换 +100 万司忆点（兑换码）｜2026/10/20']);
      const s = new SiyiPointStore();
      s.permanentSp = 6000000;
      s.consumedPermanentSp = 100;
      const pkgs: IapPackage[] = [];
      const legacy1 = new IapPackage(); // 迁移包=tok 8 位截断（0.289.0 拆包特征）
      legacy1.tok = 'AbCd1234'; legacy1.amt = 2000000;
      const legacy2 = new IapPackage();
      legacy2.tok = 'EfGh5678'; legacy2.amt = 4000000;
      pkgs.push(legacy1); pkgs.push(legacy2);
      s.iapPackages = JSON.stringify(pkgs);
      ensureIapPackagesMigrated(sub, s);
      expect(s.permanentSp).assertEqual(6000000);            // 发放不动（只增军令）
      expect(s.consumedPermanentSp).assertEqual(6000000);    // 写满=余额 0
      expect(siyiTotalSp(s)).assertEqual(0);
      const after = parseIapPackages(s.iapPackages);
      expect(after[0].cons).assertEqual(2000000);            // 迁移包写满（保留展示=已耗尽）
      expect(after[1].cons).assertEqual(4000000);
      // 幂等：全部已写满 → 二次进场零改动
      const snap = s.iapPackages;
      ensureIapPackagesMigrated(sub, s);
      expect(s.iapPackages === snap).assertTrue();
    })
    // ---- 写销路B：池有余额+包账本空+history 无华为支付行（纯旧测试账）→ 池级写销 ----
    it('writeoff_legacy_pool_only_path_b', 0, () => {
      const sub = historyWith(['兑换 +100 万司忆点（兑换码）｜2026/10/20']);
      const s = new SiyiPointStore();
      s.permanentSp = 6000000;
      s.bonusSp = 50000;
      ensureIapPackagesMigrated(sub, s);
      expect(s.permanentSp).assertEqual(6000000);
      expect(s.consumedPermanentSp).assertEqual(6000000); // 充能写销
      expect(s.bonusSp).assertEqual(50000);               // 嘉奖池不碰
      expect(siyiTotalSp(s)).assertEqual(50000);          // 只剩嘉奖
    })
    // ---- 新购账保护：history 有「华为应用内支付」行（新购特征）→ 两路皆不触发 ----
    it('writeoff_never_touches_new_purchases', 0, () => {
      const sub = historyWith(['充能 +200 万司忆点｜华为应用内支付 AbCd1234…｜2026/10/21']);
      const s = new SiyiPointStore();
      s.permanentSp = 2000000; // 新购入账（有包账本场景在下方 grant 用例）
      ensureIapPackagesMigrated(sub, s);
      expect(s.consumedPermanentSp).assertEqual(0);       // 不写销
      expect(s.permanentSp).assertEqual(2000000);
      expect(siyiTotalSp(s)).assertEqual(2000000);
      // 包账本空+有支付行也不触发（防误伤：账本被极端清空的已购用户）
      const s2 = new SiyiPointStore();
      s2.permanentSp = 2000000;
      ensureIapPackagesMigrated(sub, s2);
      expect(s2.consumedPermanentSp).assertEqual(0);
    })
    // ---- 无充能账设备（180 测试号）零触发 ----
    it('writeoff_noop_without_charging', 0, () => {
      const sub = historyWith([]);
      const s = new SiyiPointStore();
      s.bonusSp = 50000;
      ensureIapPackagesMigrated(sub, s);
      expect(s.bonusSp).assertEqual(50000);
      expect(s.consumedPermanentSp).assertEqual(0);
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

    // ---- ★ 0.291.0 冻结锁包：FIFO 跳过冻结包+池级可用排除（三处同源）+守恒 ----
    it('freeze_excludes_package_from_spend', 0, () => {
      const s = new SiyiPointStore();
      s.permanentSp = 6000000; // 两包各 200/400 万
      const pkgs: IapPackage[] = [];
      const p1 = new IapPackage();
      p1.tok = 'FRZ'; p1.amt = 2000000; p1.ts = 1000;   // 将被冻结
      const p2 = new IapPackage();
      p2.tok = 'USE'; p2.amt = 4000000; p2.ts = 2000;
      pkgs.push(p1); pkgs.push(p2);
      s.iapPackages = JSON.stringify(pkgs);
      // 冻结老包 7 天
      expect(freezePackageUntil(s, 'FRZ', Date.now() + REFUND_FREEZE_MS)).assertTrue();
      expect(frozenAvailableSp(s)).assertEqual(2000000);       // 冻结额=200 万
      expect(siyiTotalSp(s)).assertEqual(4000000);             // 可用余额排除冻结额
      // 扣 300 万：全部落未冻结包（FIFO 想先扣老包但被跳过）
      expect(consumeSiyiSp(s, 3000000)).assertTrue();
      const after = parseIapPackages(s.iapPackages);
      expect(after[0].cons).assertEqual(0);                    // 冻结包一分未动
      expect(after[1].cons).assertEqual(3000000);              // 未冻结包扛全部
      expect(s.consumedPermanentSp).assertEqual(3000000);      // 池级=包级守恒（无裂账）
      // 冻结期可用余额只有 100 万：再扣 200 万 → 只扣到 100 万为（clamp）
      expect(consumeSiyiSp(s, 2000000)).assertTrue();
      expect(s.consumedPermanentSp).assertEqual(4000000);
      expect(siyiTotalSp(s)).assertEqual(0);                   // 可用 0（冻结 200 万在账但不可用）
      // 解冻（frozenUntil 过期）：冻结额回到可用
      const s2 = new SiyiPointStore();
      s2.permanentSp = 2000000;
      const frz = new IapPackage();
      frz.tok = 'F2'; frz.amt = 2000000; frz.frozenUntil = Date.now() - 1000; // 已过期
      s2.iapPackages = JSON.stringify([frz]);
      expect(frozenAvailableSp(s2)).assertEqual(0);            // 过期=不冻结
      expect(siyiTotalSp(s2)).assertEqual(2000000);            // 恢复可用
    })
    // 冻结幂等：重复申请取 max（续锁）；未命中 tok false；已核销包不可锁
    it('freeze_idempotent_max_and_miss', 0, () => {
      const s = new SiyiPointStore();
      s.permanentSp = 2000000;
      const p = new IapPackage();
      p.tok = 'T1'; p.amt = 2000000;
      s.iapPackages = JSON.stringify([p]);
      const until = Date.now() + REFUND_FREEZE_MS;
      freezePackageUntil(s, 'T1', until);
      freezePackageUntil(s, 'T1', until - 1000); // 更小不回退（max）
      const after = parseIapPackages(s.iapPackages);
      expect(after[0].frozenUntil).assertEqual(until);
      freezePackageUntil(s, 'T1', until + 5000);  // 更大续锁
      expect(parseIapPackages(s.iapPackages)[0].frozenUntil).assertEqual(until + 5000);
      expect(freezePackageUntil(s, 'NO-SUCH', until)).assertFalse();
      const w = new IapPackage();
      w.tok = 'T2'; w.amt = 100; w.ref = 1; w.cons = 100; // 已核销
      s.iapPackages = JSON.stringify([w]);
      expect(freezePackageUntil(s, 'T2', until)).assertFalse();
    })
    // 旧账本 JSON 无 frozenUntil 字段=0 未锁（Schema 尾部追加默认值兼容）
    it('parse_legacy_json_without_frozen_field', 0, () => {
      const raw = '[{"tok":"T","pid":"dagai_sp200w","amt":2000000,"ts":1,"cons":0,"ref":0}]';
      const list = parseIapPackages(raw);
      expect(list.length).assertEqual(1);
      expect(list[0].frozenUntil).assertEqual(0);
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

    // ---- grant 建包：token 幂等拒双发；★ 0.290.2 起新购链路不再调清零（雷已拆）----
    it('grant_creates_package_without_wipe', 0, () => {
      const sub = historyWith([]);
      const s = new SiyiPointStore();
      s.permanentSp = 2000000; // 既有账（含旧测试账）
      const ok = grantSiyiSpFromIap(sub, s, IAP_PRODUCT_SP_400W, 'FULLTOKEN092XXXXXXXXXXXXXXXXXXXXXXXX', '19.00');
      expect(ok).assertTrue();
      expect(s.permanentSp).assertEqual(6000000); // 旧 200 万+新 400 万（grant 不清账——0.290.2 拆雷）
      const list = parseIapPackages(s.iapPackages);
      expect(list.length).assertEqual(1);         // 仅新包（包账本独立）
      expect(list[0].tok).assertEqual('FULLTOKEN092XXXXXXXXXXXXXXXXXXXXXXXX');
      expect(list[0].amt).assertEqual(4000000);
      expect(list[0].ts > 0).assertTrue();
      // token 幂等：重复 grant 拒双发
      expect(grantSiyiSpFromIap(sub, s, IAP_PRODUCT_SP_400W, 'FULLTOKEN092XXXXXXXXXXXXXXXXXXXXXXXX', '19.00')).assertFalse();
    })
  })
}
