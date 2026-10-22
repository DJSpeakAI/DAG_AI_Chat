import { describe, it, expect } from '@ohos/hypium';
import { renderMathText } from '../../../main/ets/utils/MathRender';

// ★ 0.288.3：LaTeX 公式定界符剥离断言（根因=0.151 起只转 \cmd/^/_ 从不剥 $/$$，
//   美元符原样露出观感即「公式显示不出」）；命令转换既有行为回归一并锚定
export default function mathRenderTest() {
  describe('DAGAI_MathRenderTest', () => {
    // ---- 定界符剥离 ----
    it('strip_inline_dollar', 0, () => {
      expect(renderMathText('质能方程 $E=mc^2$ 成立')).assertEqual('质能方程 E=mc² 成立');
    })
    it('strip_block_dollar_inline_form', 0, () => {
      expect(renderMathText('$$E=mc^2$$')).assertEqual('E=mc²');
    })
    it('strip_block_dollar_multiline', 0, () => {
      // 块级 $$ 跨行：剥两端定界符，内部换行保留，\frac 照常转换
      expect(renderMathText('$$\n\\frac{a}{b}\n$$')).assertEqual('\n(a)/(b)\n');
    })
    it('price_dollars_kept', 0, () => {
      // 价格场景：闭 $ 前是空白 → 不剥，原样保留
      expect(renderMathText('价格 $5 和 $6 元')).assertEqual('价格 $5 和 $6 元');
    })
    it('unpaired_dollar_kept', 0, () => {
      expect(renderMathText('只要 $5 就够')).assertEqual('只要 $5 就够');
    })
    it('escaped_dollar_not_stripped', 0, () => {
      // \$ 转义美元：strip 阶段跳过，主循环 ESCAPE 输出为普通 $，不被当定界符
      expect(renderMathText('\\$5 和 \\$6 元')).assertEqual('$5 和 $6 元');
    })
    // ---- 命令转换既有行为回归 ----
    it('commands_still_converted_after_strip', 0, () => {
      expect(renderMathText('$\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}$'))
        .assertEqual('∑ᵢ₌₁ⁿ i = (n(n+1))/(2)');
    })
    it('no_math_text_untouched', 0, () => {
      expect(renderMathText('普通文本 snake_case 与 2^3 不变？')).assertEqual('普通文本 snake_case 与 2³ 不变？');
    })
  })
}