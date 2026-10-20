// SignIn.test.ets — ★ 0.256.0 签到体系纯函数断言（§12.13 军令：纯逻辑抽纯函数走 hypium）
//   覆盖：连签递增公式与封顶 / 里程碑节点 / 连击推导（首签·连签·断签）/
//   doSignIn 防重复+连击+发放入嘉奖池 / 头衔阈值边界
//   ★ 0.277.0 多端幂等回归组（任务书方案 B）：跨设备同日重复签到拦截 / 云端连击接续 /
//   里程碑跨端防重发 / 日期并集合并 / 集合连击推导 / 坏值兜底
import { describe, it, expect } from '@ohos/hypium';
import {
  SignInStore, SiyiPointStore,
  signInRewardSp, milestoneBonusSp, nextStreak, doSignIn, siyiLevelOf,
  parseSignedDates, mergeSignedDates, streakFromSignedDates, SIGNED_DATES_KEEP
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
    // ★ 0.277.0 回归组——修前红/修后绿（复现用户实测：手机已签，PC 冷启动又领一次）
    it('cross_device_same_day_no_double_grant', 0, () => {
      const s = new SignInStore();                       // PC 冷启动本地空
      const sp = new SiyiPointStore();
      sp.signedDates = JSON.stringify(['2026-10-19']);   // 手机已签、云端拉下来的标记
      expect(doSignIn(s, sp, '2026-10-19')).assertEqual(0); // 修前=2000（重复发放）
      expect(sp.bonusSp).assertEqual(0);                    // 不发
      expect(s.streak).assertEqual(0);                      // 连击不动
    })
    it('cross_device_streak_continuation', 0, () => {
      const s = new SignInStore();                        // PC 冷启动（本地 streak 归零）
      const sp = new SiyiPointStore();
      sp.signedDates = JSON.stringify(['2026-10-01', '2026-10-02', '2026-10-03']);
      const got = doSignIn(s, sp, '2026-10-04');
      expect(s.streak).assertEqual(4);                    // 接着手机第 3 天签第 4 天（修前=1）
      expect(got).assertEqual(5000);                      // 第 4 天=2,000+3×1,000
      const dates = parseSignedDates(sp.signedDates);
      expect(dates.length).assertEqual(4);                // 云端标记双写含今天
      expect(dates.indexOf('2026-10-04') >= 0).assertTrue();
    })
    it('milestone_no_regrant_after_reinstall', 0, () => {
      // 重装端重新数到 7 天，但云端已发过 7 天档 → 里程碑不再发（修前=重发 10,000）
      const s = new SignInStore();
      const sp = new SiyiPointStore();
      sp.signedDates = JSON.stringify(['2026-10-01', '2026-10-02', '2026-10-03',
        '2026-10-04', '2026-10-05', '2026-10-06']);
      sp.milestoneStreakGranted = 7;                       // 手机端已发过
      const got = doSignIn(s, sp, '2026-10-07');           // streak=7 里程碑节点
      expect(got).assertEqual(8000);                       // 仅当日封顶额，无 10,000
      expect(sp.bonusSp).assertEqual(8000);
      // 对照：全新账号首达 7 天 → 里程碑正常首发
      const s2 = new SignInStore();
      const sp2 = new SiyiPointStore();
      sp2.signedDates = JSON.stringify(['2026-10-01', '2026-10-02', '2026-10-03',
        '2026-10-04', '2026-10-05', '2026-10-06']);
      expect(doSignIn(s2, sp2, '2026-10-07')).assertEqual(18000);
      expect(sp2.milestoneStreakGranted).assertEqual(7);   // 发后记档
    })
    it('merge_signed_dates_union_sort_keep', 0, () => {
      const a: string[] = ['2026-10-03', '2026-10-01'];
      const b: string[] = ['2026-10-02', '2026-10-03'];    // 重复项+独有项
      const merged = mergeSignedDates(a, b);
      expect(merged.length).assertEqual(3);                // 去重
      expect(merged[0]).assertEqual('2026-10-01');         // 排序
      expect(merged[2]).assertEqual('2026-10-03');
      // 截断：401 天只保留最近 400（最旧的被裁）
      const many: string[] = [];
      for (let i = 1; i <= SIGNED_DATES_KEEP + 1; i++) {
        const mm = `${Math.floor(i / 28) + 1}`.padStart(2, '0');
        const dd = `${i % 28}`.padStart(2, '0');
        many.push(`2026-${mm}-${dd}`);
      }
      const kept = mergeSignedDates(many, []);
      expect(kept.length).assertEqual(SIGNED_DATES_KEEP);
    })
    it('streak_from_dates_calendar_semantics', 0, () => {
      // 连续 4 天（含 today 锚）→ 4
      expect(streakFromSignedDates(['2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04'],
        '2026-10-04')).assertEqual(4);
      // 断签：04 锚但 02 缺 → 2（01..03 缺 02 不连续）
      expect(streakFromSignedDates(['2026-10-01', '2026-10-03', '2026-10-04'],
        '2026-10-04')).assertEqual(2);
      // 锚不在集合 → 0（doSignIn 调用方保证 today 已入集）
      expect(streakFromSignedDates(['2026-10-01'], '2026-10-04')).assertEqual(0);
    })
    it('parse_signed_dates_bad_value_fallback', 0, () => {
      expect(parseSignedDates(undefined).length).assertEqual(0);  // 旧云端行缺字段
      expect(parseSignedDates('').length).assertEqual(0);
      expect(parseSignedDates('not json').length).assertEqual(0); // 坏行
      expect(parseSignedDates('{"a":1}').length).assertEqual(0);  // 非数组
      expect(parseSignedDates('["2026-10-01"]').length).assertEqual(1);
    })
  })
}
