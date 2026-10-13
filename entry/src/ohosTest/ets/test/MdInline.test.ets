import { describe, it, expect } from '@ohos/hypium';
import { parseInlineMd, parseBlockMd, blockPlainText, headerFontSize } from '../../../main/ets/utils/MdInline';

// ★ 0.231.0：Markdown 行内/块级解析器单元断言（project_rule §12.13 测试覆盖军令——
//   新功能必须带测试项；纯函数模块=ChatPage 渲染与本断言双消费）
export default function mdInlineTest() {
  describe('DAGAI_MdInlineTest', () => {
    // ---- 行内：标记配对与样式归位 ----
    it('inline_bold', 0, () => {
      const spans = parseInlineMd('前缀**加粗**后缀');
      expect(spans.length).assertEqual(3);
      expect(spans[0].text).assertEqual('前缀');
      expect(spans[1].text).assertEqual('加粗');
      expect(spans[1].bold).assertTrue();
      expect(spans[2].text).assertEqual('后缀');
    })
    it('inline_italic_bold_strike_chain', 0, () => {
      const spans = parseInlineMd('*斜* ***粗斜*** ~~删~~');
      expect(spans.length).assertEqual(5);
      expect(spans[0].italic).assertTrue();
      expect(spans[2].bold && spans[2].italic).assertTrue();
      expect(spans[2].text).assertEqual('粗斜');
      expect(spans[4].strike).assertTrue();
    })
    it('inline_code_span', 0, () => {
      const spans = parseInlineMd('用 `arkts refactor` 命令');
      expect(spans.length).assertEqual(3);
      expect(spans[1].code).assertTrue();
      expect(spans[1].text).assertEqual('arkts refactor');
    })
    it('inline_link', 0, () => {
      const spans = parseInlineMd('见[文档](https://example.com/a?b=1)详解');
      expect(spans.length).assertEqual(3);
      expect(spans[1].link).assertTrue();
      expect(spans[1].text).assertEqual('文档');
      expect(spans[1].url).assertEqual('https://example.com/a?b=1');
    })
    // ---- 流式安全：未闭合标记按字面量（打字机中间态不闪乱） ----
    it('inline_unclosed_literal', 0, () => {
      const spans = parseInlineMd('未闭合**加粗没有结尾');
      expect(spans.length).assertEqual(1);
      expect(spans[0].bold).assertFalse();
      expect(spans[0].text).assertEqual('未闭合**加粗没有结尾');
    })
    it('inline_math_asterisk_literal', 0, () => {
      // 3*4*5 数学表达：开侧标记前是数字=不认斜体（canOpenMarker 挡）
      const spans = parseInlineMd('3*4*5 等于 60');
      expect(spans[0].italic).assertFalse();
      expect(spans[0].text).assertEqual('3*4*5 等于 60');
    })
    it('inline_space_content_rejected', 0, () => {
      // 内容首尾空白=非法强调（CommonMark 同款约束）
      const spans = parseInlineMd('** x** 不算粗体');
      expect(spans[0].bold).assertFalse();
    })
    // ---- 块级：分类与合并 ----
    it('block_headers', 0, () => {
      const blocks = parseBlockMd(['## 二级标题', '普通段']);
      expect(blocks.length).assertEqual(2);
      expect(blocks[0].kind).assertEqual('h2');
      expect(blocks[0].lines[0]).assertEqual('二级标题');
      expect(blocks[1].kind).assertEqual('p');
      expect(headerFontSize('h1') > headerFontSize('h4')).assertTrue();
    })
    it('block_hex_color_not_header_body', 0, () => {
      const blocks = parseBlockMd(['颜色 #FF0000 是红色']);
      expect(blocks[0].kind).assertEqual('p');
    })
    it('block_lists', 0, () => {
      const blocks = parseBlockMd(['- 一级项', '  - 二级项', '3. 有序项', '42) 括号序号']);
      expect(blocks[0].kind).assertEqual('li');
      expect(blocks[0].depth).assertEqual(0);
      expect(blocks[1].kind).assertEqual('li');
      expect(blocks[1].depth).assertEqual(1);
      expect(blocks[2].kind).assertEqual('oli');
      expect(blocks[2].order).assertEqual('3.');
      expect(blocks[3].kind).assertEqual('oli');
      expect(blocks[3].order).assertEqual('42.');
    })
    it('block_quote_hr_para_merge', 0, () => {
      const blocks = parseBlockMd(['第一行', '第二行', '', '>引用一', '>引用二', '---']);
      // 连续普通行合并单段；连续引用合并；空行分段
      expect(blocks[0].kind).assertEqual('p');
      expect(blocks[0].lines.length).assertEqual(2);
      expect(blocks[1].kind).assertEqual('quote');
      expect(blocks[1].lines.length).assertEqual(2);
      expect(blocks[2].kind).assertEqual('hr');
      expect(blockPlainText(blocks[0])).assertEqual('第一行\n第二行');
    })
    it('block_bold_line_not_list', 0, () => {
      // **加粗行** 行首双星非列表（列表要求标记后空格，** 后是文字）
      const blocks = parseBlockMd(['**要点说明** 正文']);
      expect(blocks[0].kind).assertEqual('p');
      const spans = parseInlineMd('**要点说明** 正文');
      expect(spans[0].bold).assertTrue();
    })
  })
}
