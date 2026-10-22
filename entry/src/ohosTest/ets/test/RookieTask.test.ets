// RookieTask.test.ets — ★ 0.294.0 好奇宝宝新手任务纯函数断言
//   任务表完整性（7 条/数额拍板）/ done·granted 集合读写与坏 JSON 兜底 /
//   计数与结清判定 / everDone 语义（重做不复活信号灯·SP 不再发）。
import { describe, it, expect } from '@ohos/hypium';
import {
  RookieTaskDef, ROOKIE_TASKS, ROOKIE_BONUS_SP,
  rookieDoneIds, rookieGrantedIds, rookieTaskDone, rookieTaskGranted,
  rookieDoneCount, rookieUndoneCount, rookieAllSettled
} from '../../../main/ets/common/RookieTask';
import { SiyiPointStore } from '../../../main/ets/common/ChatModel';
import {
  QUIZ_SP_PER_NODE, PersonalityQuizStore, markQuizEverDone, resetQuizForRetake,
  buildQuizClaimAmount
} from '../../../main/ets/common/PersonalityQuiz';

export default function rookieTaskTest() {
  describe('DAGAI_RookieTaskTest', () => {
    // ── 任务表完整性（拍板口径） ──
    it('task_table_seven_unique', 0, () => {
      expect(ROOKIE_TASKS.length).assertEqual(7);
      const ids: string[] = [];
      for (let i = 0; i < ROOKIE_TASKS.length; i++) {
        ids.push(ROOKIE_TASKS[i].id);
      }
      expect(new Set(ids).size).assertEqual(7); // id 唯一
      // 必含七任务（用户点名清单）
      for (const need of ['use_sishu', 'new_bubble', 'screen_annotate', 'personality_quiz',
        'word_translate', 'word_to_knowledge', 'first_review']) {
        expect(ids.indexOf(need) >= 0).assertTrue();
      }
    })
    it('task_sp_amounts_final', 0, () => {
      const byId = (id: string): RookieTaskDef => {
        for (let i = 0; i < ROOKIE_TASKS.length; i++) {
          if (ROOKIE_TASKS[i].id === id) {
            return ROOKIE_TASKS[i];
          }
        }
        return new RookieTaskDef('', '', '', 0);
      };
      expect(byId('new_bubble').sp).assertEqual(10000);        // 探索类 1 万
      expect(byId('word_translate').sp).assertEqual(10000);
      expect(byId('word_to_knowledge').sp).assertEqual(10000);
      expect(byId('use_sishu').sp).assertEqual(20000);         // 核心类 2 万
      expect(byId('screen_annotate').sp).assertEqual(20000);
      expect(byId('first_review').sp).assertEqual(20000);
      expect(byId('personality_quiz').sp).assertEqual(10000);  // 性格测试任务奖 1 万
      expect(ROOKIE_BONUS_SP).assertEqual(20000);              // 完赛奖 2 万
    })
    // ── 集合读写与兜底 ──
    it('done_granted_roundtrip_and_badjson', 0, () => {
      const s = new SiyiPointStore();
      expect(rookieDoneIds(s).length).assertEqual(0);
      s.rookieDoneJson = '["new_bubble","use_sishu"]';
      expect(rookieDoneIds(s).length).assertEqual(2);
      expect(rookieTaskDone(s, 'new_bubble')).assertTrue();
      expect(rookieTaskDone(s, 'first_review')).assertFalse();
      s.rookieGrantedJson = '["new_bubble"]';
      expect(rookieTaskGranted(s, 'new_bubble')).assertTrue();
      expect(rookieTaskGranted(s, 'use_sishu')).assertFalse();
      s.rookieDoneJson = '{bad json';
      expect(rookieDoneIds(s).length).assertEqual(0); // 坏数据兜底不崩
    })
    it('count_and_settled_ladder', 0, () => {
      const s = new SiyiPointStore();
      expect(rookieDoneCount(s)).assertEqual(0);
      expect(rookieUndoneCount(s)).assertEqual(7);
      expect(rookieAllSettled(s)).assertFalse();
      s.rookieDoneJson = JSON.stringify(ROOKIE_TASKS.map((t: RookieTaskDef) => t.id));
      expect(rookieDoneCount(s)).assertEqual(7);
      expect(rookieUndoneCount(s)).assertEqual(0);
      expect(rookieAllSettled(s)).assertFalse();          // 全 done 但完赛奖哨兵未发
      s.rookieGrantedJson = JSON.stringify(
        ROOKIE_TASKS.map((t: RookieTaskDef) => t.id).concat(['__bonus__']));
      expect(rookieAllSettled(s)).assertTrue();           // 结清=true → 画布入口消失
    })
    // ── 性格测试 0.294.0 语义 ──
    it('quiz_node_sp_upgraded_5000', 0, () => {
      expect(QUIZ_SP_PER_NODE).assertEqual(5000);          // 二轮拍板上调
      expect(buildQuizClaimAmount(0, 15)).assertEqual(15000); // 三节点 1.5 万
      expect(buildQuizClaimAmount(3, 15)).assertEqual(0);     // 已领满不重发（老用户不补差价）
    })
    it('quiz_everdone_and_retake_semantics', 0, () => {
      const s = new PersonalityQuizStore();
      expect(s.everDone).assertFalse();
      s.choiceAnswers = '["a","ac","b"]';
      s.done = true;
      s.claimed = 3;
      s.profileWritten = true;
      markQuizEverDone(s);
      expect(s.everDone).assertTrue();
      // 重做：进度/评阅标记清零重答；everDone 保留（信号灯不复活）；claimed 保留（SP 不再发）
      resetQuizForRetake(s);
      expect(s.done).assertFalse();
      expect(s.profileWritten).assertFalse();
      expect(s.choiceAnswers).assertEqual('[]');
      expect(s.claimed).assertEqual(3);                    // 防刷死锁
      expect(s.everDone).assertTrue();                     // 重做不复活
      // 重做后再答满：claim 差额恒 0（claimed=3 ≥ node 上限）
      expect(buildQuizClaimAmount(s.claimed, 15)).assertEqual(0);
      markQuizEverDone(s); // 幂等
      expect(s.everDone).assertTrue();
    })
  })
}