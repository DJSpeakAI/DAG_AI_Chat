import { describe, it, expect } from '@ohos/hypium';
import { HookSpec, parseHookJsonResponse, scanBlockSpans, mergeHooksIntoContent, stripAnchorMarks, parseBlockMd } from '../../../main/ets/utils/MdInline';

// ★ 0.269.0 钩子模式两段式：本地合成器单元断言（任务书 §八.10 / project_rule §12.13 测试覆盖军令）
// 覆盖：JSON 兜底抠取 / 块边界扫描（围栏表格整体） / 越界钳位 / 禁插标题列表后移 /
//   bait 截断（>1 保留最后）/ 开篇钳位 / progress 本地保底 / 标记插入位置 / 导出过滤无残留
export default function hookMergeTest() {
  describe('DAGAI_HookMergeTest', () => {
    // ---- parseHookJsonResponse：JSON 兜底抠取（模型加废话/围栏也能抠出数组） ----
    it('hook_json_clean_array', 0, () => {
      const hooks = parseHookJsonResponse('[{"afterPara":2,"type":"breath","text":"刚那个比喻值得再品"}]');
      expect(hooks.length).assertEqual(1);
      expect(hooks[0].afterPara).assertEqual(2);
      expect(hooks[0].type).assertEqual('breath');
      expect(hooks[0].text).assertEqual('刚那个比喻值得再品');
    })
    it('hook_json_fence_noise_extracted', 0, () => {
      const raw = '好的，以下是钩子：\n```json\n[{"afterPara":3,"type":"digest","text":"响应式=看到你走近换站姿"}]\n```\n希望有帮助';
      const hooks = parseHookJsonResponse(raw);
      expect(hooks.length).assertEqual(1);
      expect(hooks[0].type).assertEqual('digest');
    })
    it('hook_json_missing_field_dropped', 0, () => {
      // 字段缺失丢弃（Q1：无 afterPara / 空 text 均不进合成）
      const hooks = parseHookJsonResponse('[{"type":"breath","text":"缺块号"},{"afterPara":2,"type":"breath","text":""},{"afterPara":3,"type":"bait","text":"ok"}]');
      expect(hooks.length).assertEqual(1);
      expect(hooks[0].afterPara).assertEqual(3);
    })
    it('hook_json_garbage_empty', 0, () => {
      expect(parseHookJsonResponse('模型彻底跑偏，没有任何数组').length).assertEqual(0);
      expect(parseHookJsonResponse('').length).assertEqual(0);
    })
    // ---- scanBlockSpans：围栏/表格整体一块，列表逐行一块 ----
    it('hook_spans_fence_single_block', 0, () => {
      const lines = ['第一段', '', '```ts', 'const a = 1;', 'const b = 2;', '```', '', '收尾段'];
      const spans = scanBlockSpans(lines);
      expect(spans.length).assertEqual(3);
      expect(spans[1].kind).assertEqual('code');
      expect(spans[1].endLine).assertEqual(5);
    })
    it('hook_spans_table_single_block', 0, () => {
      const lines = ['| a | b |', '|---|---|', '| 1 | 2 |', '', '结尾'];
      const spans = scanBlockSpans(lines);
      expect(spans.length).assertEqual(2);
      expect(spans[0].kind).assertEqual('table');
    })
    it('hook_spans_list_line_blocks', 0, () => {
      const spans = scanBlockSpans(['- 项一', '- 项二', '- 项三']);
      expect(spans.length).assertEqual(3);
      expect(spans[0].kind).assertEqual('li');
    })
    // ---- mergeHooksIntoContent：插入位置与标记协议 ----
    it('hook_merge_marker_inserted_after_block', 0, () => {
      const content = '第一段正文内容。\n\n第二段正文内容。\n\n第三段正文内容，足够长的一段文字。';
      const h = new HookSpec();
      h.afterPara = 2;
      h.type = 'digest';
      h.text = '简单说：这一段讲的是结构';
      const merged = mergeHooksIntoContent([h], content);
      expect(merged !== content).assertTrue();
      expect(merged.indexOf('[[anchor:digest|简单说：这一段讲的是结构]]') >= 0).assertTrue();
      // 标记出现在第三段文字之后（块 2 之后）
      expect(merged.indexOf('[[anchor:digest') > merged.indexOf('第三段正文内容')).assertTrue();
    })
    it('hook_merge_never_inside_code_or_table', 0, () => {
      const content = '引入段说明。\n\n```ts\nconst a = 1;\nconst b = 2;\n```\n\n| 列一 | 列二 |\n|---|---|\n| 1 | 2 |\n\n收尾说明段落。';
      const h = new HookSpec();
      h.afterPara = 1; // 指向代码块（块 1）
      h.type = 'breath';
      h.text = '喘口气';
      const merged = mergeHooksIntoContent([h], content);
      // 标记必须出现在代码围栏关闭之后（永不进代码块内部）
      expect(merged.indexOf('[[anchor:breath|喘口气]]') > merged.indexOf('```')).assertTrue();
      // 表格内部无标记（标记只可能在表格块之后）
      const tableStart = merged.indexOf('| 列一 |');
      const markerPos = merged.indexOf('[[anchor:breath');
      expect(markerPos < tableStart).assertFalse();
    })
    it('hook_merge_clamp_out_of_range', 0, () => {
      const content = '第一段。\n\n第二段。\n\n第三段。';
      const h = new HookSpec();
      h.afterPara = 99; // 越界
      h.type = 'breath';
      h.text = '钳位';
      const merged = mergeHooksIntoContent([h], content);
      // 越界钳位到合法位置（不崩溃、有产出）
      expect(merged.indexOf('[[anchor:breath|钳位]]') >= 0).assertTrue();
    })
    it('hook_merge_bait_truncated_to_last_and_tail', 0, () => {
      const content = '第一段。\n\n第二段。\n\n第三段。\n\n第四段收尾。';
      const b1 = new HookSpec();
      b1.afterPara = 1;
      b1.type = 'bait';
      b1.text = '引子甲';
      const b2 = new HookSpec();
      b2.afterPara = 2;
      b2.type = 'bait';
      b2.text = '引子乙';
      const merged = mergeHooksIntoContent([b1, b2], content);
      expect(merged.indexOf('引子甲')).assertEqual(-1); // bait>1 丢弃多余（保留最后一条）
      expect(merged.indexOf('[[anchor:bait|引子乙]]') >= 0).assertTrue();
      // bait 恒在全文最后一块之后（倒数第一段文字之后）
      expect(merged.indexOf('[[anchor:bait') > merged.indexOf('第四段收尾')).assertTrue();
    })
    it('hook_merge_invalid_type_downgraded', 0, () => {
      const content = '第一段。\n\n第二段。\n\n第三段。';
      const h = new HookSpec();
      h.afterPara = 2;
      h.type = 'quiz'; // 两段式长回复已移除的类型
      h.text = '降级测';
      const merged = mergeHooksIntoContent([h], content);
      expect(merged.indexOf('[[anchor:breath|降级测]]') >= 0).assertTrue(); // 类型非法降级 breath
    })
    it('hook_merge_heading_and_list_shifted', 0, () => {
      const content = '## 一、开篇\n\n标题后正文段落一，写点内容。\n\n- 项一\n- 项二\n- 项三\n\n列表后正文段落二。';
      const h = new HookSpec();
      h.afterPara = 1; // 指向 h2 标题块（禁插标题后）
      h.type = 'digest';
      h.text = '后移';
      const merged = mergeHooksIntoContent([h], content);
      const markerPos = merged.indexOf('[[anchor:digest|后移');
      // 后移至下一合法块（列表整体结束后/或标题后首个合法块），不得直接贴在标题行后
      const h2Pos = merged.indexOf('## 一、开篇');
      expect(markerPos > h2Pos).assertTrue();
      // 列表项行内无标记
      const li1 = merged.indexOf('- 项一');
      const li3 = merged.indexOf('- 项三');
      expect(markerPos > li1 && markerPos < li3).assertFalse();
    })
    it('hook_merge_empty_hooks_original_returned', 0, () => {
      const content = '只有一段的短文。';
      const merged = mergeHooksIntoContent([], content);
      expect(merged).assertEqual(content);
    })
    // ---- progress 本地保底：钩子不足配额时自动补 ----
    it('hook_merge_progress_backfill_on_deficit', 0, () => {
      // 构造 >800 字长文（10 段 × 100 字），AI 只给 1 个钩子（配额 2）→ 本地补 1 个 progress
      const parts: string[] = [];
      for (let i = 0; i < 10; i++) {
        parts.push(`第${i + 1}段：${'长'.repeat(99)}文`);
      }
      const content = parts.join('\n\n');
      const h = new HookSpec();
      h.afterPara = 3;
      h.type = 'breath';
      h.text = 'AI 唯一钩子';
      const merged = mergeHooksIntoContent([h], content);
      expect(merged.indexOf('[[anchor:progress|') >= 0).assertTrue(); // 保底 progress 出现
      expect(merged.indexOf('[[anchor:breath|AI 唯一钩子]]') >= 0).assertTrue();
    })
    // ---- 导出/复制过滤：钩子标记零残留（stripAnchorMarks 同协议天然覆盖） ----
    it('hook_strip_marks_for_export', 0, () => {
      const content = '第一段。\n\n[[anchor:breath|喘口气]]\n\n第二段。\n\n[[anchor:bait|延伸一下]]';
      const stripped = stripAnchorMarks(content, false);
      expect(stripped.indexOf('[[anchor:')).assertEqual(-1);
      expect(stripped.indexOf('喘口气')).assertEqual(-1);
      expect(stripped.indexOf('第二段') >= 0).assertTrue();
    })
    // ---- 与既有渲染管线兼容：合成产物可被 parseBlockMd 解析为锚点块 ----
    it('hook_merged_content_parses_as_anchor_blocks', 0, () => {
      const content = '第一段正文。\n\n第二段正文。\n\n第三段正文。';
      const h = new HookSpec();
      h.afterPara = 2;
      h.type = 'digest';
      h.text = '管线兼容';
      const merged = mergeHooksIntoContent([h], content);
      const blocks = parseBlockMd(merged.split('\n'));
      let anchorCount = 0;
      for (let i = 0; i < blocks.length; i++) {
        if (blocks[i].kind === 'anchor') {
          anchorCount++;
          expect(blocks[i].anchorType).assertEqual('digest');
        }
      }
      expect(anchorCount).assertEqual(1);
    })
  })
}
