// AiRerank.test.ets — ★ 0.268.0 司忆区 AI 智慧排序纯函数断言（§12.13 军令：纯逻辑抽纯函数走 hypium）
//   覆盖：序号解析容错（正常/越界乱文/缺漏补尾/重复/纯乱文）/ 序号→id 映射兜底 /
//   展示批未来卡 ≤1 张末位约束 / 护栏矩阵（enabled 常量·空 key·空问题·候选不足=零副作用本地序）
import { describe, it, expect } from '@ohos/hypium';
import { AI_RERANK_ENABLED, parseRerankOrder, applyRerankOrder, rerankDisplayBatch,
  buildRerankPrompt, triggerAiRerank, getRerankWordIds } from '../../../main/ets/utils/AiRerank';
import { WordItem } from '../../../main/ets/common/WordModel';
import { KnowledgeCard } from '../../../main/ets/common/KnowledgeModel';
import { ApiConfig } from '../../../main/ets/common/ChatModel';

function makeWord(id: string, word: string): WordItem {
  return new WordItem(word, '', '', '测试释义', id);
}

function makeCard(id: string, title: string): KnowledgeCard {
  return new KnowledgeCard(id, title, '测试定义');
}
export default function aiRerankTest() {
  describe('DAGAI_AiRerankTest', () => {
    // ── 解析容错（任务书 §五解析侧规则） ──
    it('parse_normal_order', 0, () => {
      const nums = parseRerankOrder('[2,3,1]', 3);
      expect(nums.length).assertEqual(3);
      expect(nums[0]).assertEqual(2);
      expect(nums[1]).assertEqual(3);
      expect(nums[2]).assertEqual(1);
    })
    it('parse_out_of_range_and_junk_filtered', 0, () => {
      // 越界（5/99）过滤 + 中文逗号容错 + 前后废话剥除 + 缺失 3 按本地序补尾
      const nums = parseRerankOrder('好的，我认为顺序是 [5, 1，99, 2] 以上。', 3);
      expect(nums.length).assertEqual(3);
      expect(nums[0]).assertEqual(1);
      expect(nums[1]).assertEqual(2);
      expect(nums[2]).assertEqual(3); // 缺失补尾
    })
    it('parse_missing_fill_local_order', 0, () => {
      const nums = parseRerankOrder('[3]', 4);
      expect(nums.length).assertEqual(4);
      expect(nums[0]).assertEqual(3);
      expect(nums[1]).assertEqual(1); // 缺失按数字升序（=本地序）补尾
      expect(nums[2]).assertEqual(2);
      expect(nums[3]).assertEqual(4);
    })
    it('parse_duplicate_kept_once', 0, () => {
      const nums = parseRerankOrder('[2,2,1]', 3);
      expect(nums.length).assertEqual(3);
      expect(nums[0]).assertEqual(2);
      expect(nums[1]).assertEqual(1);
      expect(nums[2]).assertEqual(3);
    })
    it('parse_garbage_returns_empty', 0, () => {
      // 纯乱文/无数组结构 = 空（消费端兜底本地序——断网关 key 回归零感知的解析层保障）
      expect(parseRerankOrder('这道题我觉得都不太相关。', 3).length).assertEqual(0);
      expect(parseRerankOrder('', 3).length).assertEqual(0);
      expect(parseRerankOrder('[]', 3).length).assertEqual(0);
      expect(parseRerankOrder('[1,2]', 0).length).assertEqual(0); // 无候选
    })
    // ── 序号 → id 映射 ──
    it('apply_order_maps_ids_with_fallback', 0, () => {
      const ids = ['w1', 'w2', 'w3'];
      const out = applyRerankOrder(ids, [3, 1]);
      expect(out.length).assertEqual(3);
      expect(out[0]).assertEqual('w3');
      expect(out[1]).assertEqual('w1');
      expect(out[2]).assertEqual('w2'); // 未覆盖兜底按本地序补尾
    })
    // ── 展示批未来卡约束（Q1 单卡提权·情境唤醒） ──
    it('display_batch_future_cap_one_at_tail', 0, () => {
      // a=到期 b=新词 c/d/e=未来卡；count=3：非未来优先，未来卡仅 1 张进末位
      const mk = (id: string, future: boolean): string => future ? `f_${id}` : `n_${id}`;
      const ordered: string[] = [mk('a', false), mk('c', true), mk('b', false), mk('d', true), mk('e', true)];
      const isFuture = (x: string): boolean => x.startsWith('f_');
      const batch = rerankDisplayBatch(ordered, 3, isFuture);
      expect(batch.length).assertEqual(3);
      expect(batch[0]).assertEqual('n_a');
      expect(batch[1]).assertEqual('n_b');
      expect(batch[2]).assertEqual('f_c'); // AI 序最靠前的未来卡 1 张末位提权
      const futureCount = batch.filter((x: string): boolean => isFuture(x)).length;
      expect(futureCount).assertEqual(1); // 未来卡 ≤1 张
    })
    it('display_batch_full_no_future_slot', 0, () => {
      // 非未来卡已满一批：未来卡不进（末位名额被占——非未来优先）
      const ordered: string[] = ['n_a', 'f_x', 'n_b', 'n_c', 'n_d'];
      const isFuture = (x: string): boolean => x.startsWith('f_');
      const batch = rerankDisplayBatch(ordered, 3, isFuture);
      expect(batch.length).assertEqual(3);
      expect(batch.includes('f_x')).assertFalse();
    })
    it('display_batch_no_future_no_pick', 0, () => {
      // 无未来卡=纯重排；池小于 count=原样全上
      const ordered: string[] = ['n_b', 'n_a'];
      const isFuture = (_x: string): boolean => false;
      const batch = rerankDisplayBatch(ordered, 5, isFuture);
      expect(batch.length).assertEqual(2);
      expect(batch[0]).assertEqual('n_b');
      expect(batch[1]).assertEqual('n_a');
    })
    // ── prompt 拼装 ──
    it('prompt_placeholders_replaced', 0, () => {
      const p = buildRerankPrompt('快速排序的时间复杂度？', '', ['1. 算法复杂度｜算法', '2. 红黑树｜数据结构']);
      expect(p.includes('快速排序的时间复杂度？')).assertTrue();
      expect(p.includes('{question}')).assertFalse();
      expect(p.includes('{topics}')).assertFalse();
      expect(p.includes('（无）')).assertTrue(); // 空话题兜底
      expect(p.includes('1. 算法复杂度｜算法')).assertTrue();
      expect(p.includes('1. {标题}')).assertFalse(); // 占位行已替换
      expect(p.includes('[2,3,1]')).assertTrue(); // few-shot 正确示例保留
    })
    // ── 护栏矩阵（全静默零副作用 → 消费端走本地序） ──
    it('guard_matrix_silent_fallback', 0, () => {
      expect(AI_RERANK_ENABLED).assertTrue(); // 编译期常量存在（改 false 即全局关停——triggerAiRerank 首行 return）
      const words: WordItem[] = [];
      for (let i = 0; i < 6; i++) {
        words.push(makeWord(`gw${i}`, `w${i}`));
      }
      const cards: KnowledgeCard[] = [];
      for (let i = 0; i < 6; i++) {
        cards.push(makeCard(`gc${i}`, `c${i}`));
      }
      const noop = (): void => {};
      // 空 apiKey（new ApiConfig 默认空串）：自动休眠——无缓存条目，消费端本地序
      triggerAiRerank('guard_key', '什么是快速排序？', '算法', words, cards, new ApiConfig(), noop, noop);
      expect(getRerankWordIds('guard_key').length).assertEqual(0);
      // 空问题（纯图发送）：无输入不重排
      const cfg = new ApiConfig();
      cfg.apiKey = 'k';
      triggerAiRerank('guard_empty_q', '   ', '算法', words, cards, cfg, noop, noop);
      expect(getRerankWordIds('guard_empty_q').length).assertEqual(0);
      // 两库候选均 <4：直接本地序不调 AI
      triggerAiRerank('guard_few', '什么是快速排序？', '算法', words.slice(0, 3), cards.slice(0, 2), cfg, noop, noop);
      expect(getRerankWordIds('guard_few').length).assertEqual(0);
      // 未知 messageId：恒空（历史消息/未触发消息走本地序）
      expect(getRerankWordIds('never_triggered').length).assertEqual(0);
    })
  })
}
