// MemoryEngine.test.ets — ★ 0.265.0 记忆引擎一期纯函数断言（§12.13 军令：纯逻辑抽纯函数走 hypium）
//   覆盖：画像聚合视图（分组/排序/superseded 过滤）/ supersede 只增不删（溯源链保留）/
//   清空入口 / 注入埋点按天聚合 + 14 天滚动 / 摘要头树距离衰减（距离1完整/距离2仅标题/
//   距离≥3不注入/总开关关=零注入）
import { describe, it, expect } from '@ohos/hypium';
import { BubbleNode, BubbleTree, ChatMessage } from '../../../main/ets/common/ChatModel';
import { ProfileObservation, ProfileStore, appendObservation, supersedeObservation, buildCardView,
  clearAllObservations, activeObservationCount, MemoryInjectStatsStore, recordMemoryInjectStats,
  buildSiblingHeadsContext, connectMemoryPref } from '../../../main/ets/common/ProfileModel';

function makeObs(id: string, kind: string, content: string, createdAt: number): ProfileObservation {
  return new ProfileObservation(id, kind, content, 'node_a', '', createdAt, createdAt);
}

function makeNode(id: string, parentID: string | null, userText: string): BubbleNode {
  const msgs: ChatMessage[] = userText.length > 0
    ? [new ChatMessage(`m_${id}`, 'user', userText)] : [];
  return new BubbleNode(id, parentID, msgs, 0, 0, 0, 0);
}

export default function memoryEngineTest() {
  describe('DAGAI_MemoryEngineTest', () => {
    // ── WP1 画像观察行 ──
    it('profile_cardview_group_sort_filter', 0, () => {
      const s = new ProfileStore();
      appendObservation(s, makeObs('o1', 'preference', '偏好分步骤推导', 100));
      appendObservation(s, makeObs('o2', 'identity', '高三学生备考数学', 50)); // 更早但 identity 组排前
      appendObservation(s, makeObs('o3', 'goal', '掌握导数应用题', 200));
      appendObservation(s, makeObs('o4', 'preference', '旧偏好已取代', 80));
      supersedeObservation(s, 'o4', 'o1'); // o4 被取代 → 不进画像卡
      const card = buildCardView(s);
      expect(card.length > 0).assertTrue();
      expect(card.includes('[用户画像]')).assertTrue();
      const idAt = card.indexOf('- identity:');
      const goalAt = card.indexOf('- goal:');
      const prefAt = card.indexOf('- preference:');
      expect(idAt >= 0 && goalAt > idAt && prefAt > goalAt).assertTrue(); // kind 分组序：identity→goal→preference
      expect(card.includes('旧偏好已取代')).assertFalse(); // 被取代行过滤
      expect(card.includes('偏好分步骤推导')).assertTrue(); // 生效行保留
    })
    it('profile_supersede_keeps_history_rows', 0, () => {
      const s = new ProfileStore();
      appendObservation(s, makeObs('old', 'preference', '先看推导', 100));
      appendObservation(s, makeObs('new', 'preference', '先看结论', 200));
      supersedeObservation(s, 'old', 'new');
      // 只增不删：旧行仍在（可溯源），activeCount 只算生效行
      expect(activeObservationCount(s)).assertEqual(1);
      expect(s.raw.includes('先看推导')).assertTrue(); // 历史行保留（S4 演变数据链）
      expect(buildCardView(s).includes('先看结论')).assertTrue();
    })
    it('profile_clear_all', 0, () => {
      const s = new ProfileStore();
      appendObservation(s, makeObs('o1', 'identity', '测试', 1));
      clearAllObservations(s);
      expect(activeObservationCount(s)).assertEqual(0);
      expect(buildCardView(s).length).assertEqual(0); // 空画像=跳过注入
    })
    // ── WP4 注入埋点：按天聚合 + 14 天滚动 ──
    it('inject_stats_daily_merge_and_rolling', 0, () => {
      const s = new MemoryInjectStatsStore();
      recordMemoryInjectStats(s, 100, 1000, 50, 200);
      recordMemoryInjectStats(s, 30, 500, 20, 10); // 同天累加
      let records = JSON.parse(s.raw)['records'] as Array<Record<string, number>>;
      expect(records.length).assertEqual(1);
      expect(records[0]['profileTok']).assertEqual(130);
      expect(records[0]['pathTok']).assertEqual(1500);
      // 造 16 个历史日期行（拼 raw 直写）→ 滚动只留 14 行
      const fake: Array<Record<string, number | string>> = [];
      for (let i = 0; i < 16; i++) {
        const row: Record<string, number | string> = {}; // 程序化构建（ArkTS 字面量需 quoted keys）
        row['date'] = `2020-01-${(i + 1) < 10 ? '0' + (i + 1) : (i + 1)}`;
        row['profileTok'] = 1;
        row['pathTok'] = 1;
        row['headsTok'] = 1;
        row['summaryTok'] = 1;
        fake.push(row);
      }
      s.raw = JSON.stringify({ records: fake });
      recordMemoryInjectStats(s, 1, 1, 1, 1); // 触发滚动
      records = JSON.parse(s.raw)['records'] as Array<Record<string, number>>;
      expect(records.length).assertEqual(14); // 14 天滚动裁剪
    })
    // ── WP2 摘要头树距离衰减 ──
    it('heads_tree_distance_decay', 0, () => {
      const pref = connectMemoryPref();
      pref.memoryMode = 'on';
      const root = makeNode('root', null, '根话题');
      const childA = makeNode('a', 'root', '分支A聊换元法');
      const childB = makeNode('b', 'root', '分支B聊数列');
      const grandChildB = makeNode('b1', 'b', '分支B的子节点');
      const uncleC = makeNode('c', 'root', '叔伯分支C聊立体几何');
      const farD = makeNode('d', 'farRoot', '远房分支D'); // 另一棵树（距离≥3）
      const farRoot = makeNode('farRoot', null, '远树根');
      // 打摘要头数据
      childA.summaryHead = '讨论了换元法技巧';
      childA.topicTags = ['数学', '导数'];
      uncleC.summaryHead = '立体几何建系方法';
      uncleC.topicTags = ['数学'];
      farD.summaryHead = '远房内容';
      farD.topicTags = ['物理'];
      grandChildB.summaryHead = '数列递推';
      const tree = new BubbleTree([root, childA, childB, grandChildB, uncleC, farRoot, farD]);
      // 当前=grandChildB：childA/childB=同父？不——grandChildB 父=b，childA/childB 与 b 同父=root，
      // 对 grandChildB 而言 childA/childB 是「父的兄弟」（距离2=叔伯辈）；无距离1 兄弟（b 无其他子）
      const ctx1 = buildSiblingHeadsContext(tree, grandChildB);
      expect(ctx1.includes('分支A聊换元法')).assertTrue(); // 距离2：仅标题+话题词
      expect(ctx1.includes('[数学/导数]')).assertTrue();
      expect(ctx1.includes('讨论了换元法技巧')).assertFalse(); // 距离2 不含摘要体
      expect(ctx1.includes('远房内容')).assertFalse(); // 距离≥3 不注入
      // 当前=childB：childA=同父兄弟（距离1=完整行）；uncleC=距离2；grandChildB 是 childB 自己的子（在链上，不注入）
      const ctx2 = buildSiblingHeadsContext(tree, childB);
      expect(ctx2.includes('讨论了换元法技巧')).assertTrue(); // 距离1 完整摘要头
      expect(ctx2.includes('立体几何建系方法')).assertTrue(); // 距离2（叔伯）
      expect(ctx2.includes('数列递推')).assertFalse(); // 自身子节点在链上不注入
      // WP5 总开关关=零注入（回到纯父链）
      pref.memoryMode = 'off';
      expect(buildSiblingHeadsContext(tree, childB).length).assertEqual(0);
      pref.memoryMode = 'on'; // 恢复默认（防影响其他用例）
    })
  });
}
