// SignIn.test.ets — ★ 0.256.0 签到体系纯函数断言（§12.13 军令：纯逻辑抽纯函数走 hypium）
//   覆盖：连签递增公式与封顶 / 里程碑节点 / 连击推导（首签·连签·断签）/
//   doSignIn 防重复+连击+发放入嘉奖池 / 头衔阈值边界
import { describe, it, expect } from '@ohos/hypium';
import {
  SignInStore, SiyiPointStore,
  signInRewardSp, milestoneBonusSp, nextStreak, doSignIn, siyiLevelOf
} from '../../../main/ets/common/ChatModel';

export default function signInTest() {
  describe('DAGAI_SignInTest', () => {
    it('reward_ladder_increment_and_cap', 0, () => {
      expect(signInRewardSp(1)).assertEqual(2000);   // 第 1 天 2,000
      expect(signInRewardSp(2)).assertEqual(3000);   // 每天 +1,000
      expect(signInRewardSp(6)).assertEqual(7000);
      expect(signInRewardSp(7)).assertEqual(8000);   // 第 7 天封顶
      expect(signInRewardSp(8)).assertEqual(8000);   // 封顶后恒 8,000
      expect(signInRewardSp(100)).assertEqual(8000);
    })
    it('milestone_at_7_30_100_only', 0, () => {
      expect(milestoneBonusSp(6)).assertEqual(0);
      expect(milestoneBonusSp(7)).assertEqual(10000);
      expect(milestoneBonusSp(8)).assertEqual(0);    // 仅节点当天
      expect(milestoneBonusSp(29)).assertEqual(0);
      expect(milestoneBonusSp(30)).assertEqual(50000);
      expect(milestoneBonusSp(31)).assertEqual(0);
      expect(milestoneBonusSp(100)).assertEqual(200000);
      expect(milestoneBonusSp(101)).assertEqual(0);
    })
    it('next_streak_first_continue_break', 0, () => {
      expect(nextStreak('', 0, '2026-10-19')).assertEqual(1);            // 首签
      expect(nextStreak('2026-10-18', 5, '2026-10-19')).assertEqual(6);  // 昨天签过=连击+1
      expect(nextStreak('2026-10-17', 5, '2026-10-19')).assertEqual(1);  // 间断=归 1（连击冻结）
    })
    it('do_sign_in_grant_streak_and_idempotent', 0, () => {
      const s = new SignInStore();
      const sp = new SiyiPointStore();
      const got = doSignIn(s, sp, '2026-10-19');
      expect(got).assertEqual(2000);                  // 首日=基础 2,000
      expect(sp.bonusSp).assertEqual(2000);           // 发放入嘉奖池
      expect(s.streak).assertEqual(1);
      expect(s.maxStreak).assertEqual(1);
      expect(s.lastSignDate).assertEqual('2026-10-19');
      expect(s.signDates.length).assertEqual(1);
      expect(doSignIn(s, sp, '2026-10-19')).assertEqual(0); // 同日再签=0
      expect(sp.bonusSp).assertEqual(2000);                 // 不重复发放
      // 次日连签第 7 天（预置连击 6）=当日 8,000 封顶+里程碑 10,000
      const s2 = new SignInStore();
      const sp2 = new SiyiPointStore();
      s2.lastSignDate = '2026-10-12';
      s2.streak = 6;
      s2.maxStreak = 6;
      const got2 = doSignIn(s2, sp2, '2026-10-13');
      expect(got2).assertEqual(18000);                // 8,000 + 10,000 里程碑
      expect(s2.streak).assertEqual(7);
      expect(s2.maxStreak).assertEqual(7);
    })
    it('siyi_level_thresholds', 0, () => {
      expect(siyiLevelOf(0)).assertEqual(1);
      expect(siyiLevelOf(6)).assertEqual(1);
      expect(siyiLevelOf(7)).assertEqual(2);
      expect(siyiLevelOf(29)).assertEqual(2);
      expect(siyiLevelOf(30)).assertEqual(3);
      expect(siyiLevelOf(89)).assertEqual(3);
      expect(siyiLevelOf(90)).assertEqual(4);
      expect(siyiLevelOf(364)).assertEqual(7);
      expect(siyiLevelOf(365)).assertEqual(8);
    })
  })
}
