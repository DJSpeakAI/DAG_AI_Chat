import { describe, it, expect } from '@ohos/hypium';
import { parseInlineMd, parseBlockMd, blockPlainText, blockRenderedText, headerFontSize, mdToSpeakableText, stripAnchorMarks, breathThreshold, BREATH_POOL, FoldItem, FoldSection, insertLocalAnchors, splitFoldSections, initExpandedSet, MdBlock, buildTableMarkdown, buildTablePlainText } from '../../../main/ets/utils/MdInline';

// ★ 0.231.0：Markdown 行内/块级解析器单元断言（project_rule §12.13 测试覆盖军令——
//   新功能必须带测试项；纯函数模块=ChatPage 渲染与本断言双消费）
// ★ 0.234.0：注意力锚点+分章折叠断言（任务书 §8.1 六组——标记解析/清洗/breath 保底/章节切分/展开集）
// ★ 0.237.0：锚点二期——钩子树六类白名单（砍 link 加 rephrase/predict/recap）/breath 两档阈值/
//   保底文案池节上下文实感（任务书 §8.1）
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
    // ---- ★ 0.237.1：blockRenderedText 划词取词基准（渲染态文本——修「划词取词整体前移」bug 的回归断言）----
    it('rendered_text_strips_inline_markers', 0, () => {
      const blocks = parseBlockMd(['这是**重点**内容和[链接](https://example.com)尾部']);
      expect(blocks[0].kind).assertEqual('p');
      // 渲染文本剥 ** 与链接 url（保留锚文本）——与 Span 渲染序列逐字符一致
      expect(blockRenderedText(blocks[0])).assertEqual('这是重点内容和链接尾部');
      // blockPlainText 保留原始行（含标记）——两者不同=bug 复现基线（旧代码拿它当取词基准）
      expect(blockPlainText(blocks[0])).assertEqual('这是**重点**内容和[链接](https://example.com)尾部');
    })
    it('rendered_text_list_prefix_offset_basis', 0, () => {
      // ★ 输入注意：标记前必须是 CJK/空格——ASCII 字母数字后跟 ** 按 canOpenMarker 设计=字面量（3*4*5 防线）
      const blocks = parseBlockMd(['- 单词甲**加粗**单词乙']);
      expect(blocks[0].kind).assertEqual('li');
      // 渲染文本含 '• ' 前缀（前缀 Span 承列表符号）——选区偏移含前缀，取词基准必须同构
      expect(blockRenderedText(blocks[0])).assertEqual('• 单词甲加粗单词乙');
      // 偏移一致性：在渲染文本上划选「单词乙」，按渲染偏移取词必须命中「单词乙」
      //（旧基准=原始行，同偏移取到「粗单词」=「往前面选择」用户实锤）
      const rendered = blockRenderedText(blocks[0]);
      const selStart = rendered.indexOf('单词乙');
      expect(rendered.substring(selStart, selStart + 3)).assertEqual('单词乙');
      // 有序列表前缀=序号+空格
      const oli = parseBlockMd(['3. 有序**加粗**项']);
      expect(blockRenderedText(oli[0])).assertEqual('3. 有序加粗项');
      // 引用多行：行间 '\n' 拼接、无前缀
      const q = parseBlockMd(['>引用一**粗**', '>引用二']);
      expect(blockRenderedText(q[0])).assertEqual('引用一粗\n引用二');
    })
    it('rendered_text_plain_and_unclosed_passthrough', 0, () => {
      // 无标记段落：渲染态=纯文本零损耗（普通消息划词不受影响）
      const blocks = parseBlockMd(['普通中文句子。']);
      expect(blockRenderedText(blocks[0])).assertEqual('普通中文句子。');
      // 未闭合标记=字面量（流式安全），渲染态同样原样保留
      const stream = parseBlockMd(['未闭合**加粗']);
      expect(blockRenderedText(stream[0])).assertEqual('未闭合**加粗');
    })
    // ---- ★ 0.232.0：mdToSpeakableText（TTS 朗读文本清洗——「星号都读进去」根治） ----
    it('speak_strips_inline_markers', 0, () => {
      // **粗**/*斜*/~~删~~/`码` 剥标记；链接保锚文本丢 url
      const out = mdToSpeakableText('# 标题\n\n这**加粗**和*斜体*还有~~删除~~以及`code`，见[文档](https://example.com)详解。');
      expect(out.includes('标题')).assertTrue();
      expect(out.includes('**')).assertFalse();
      expect(out.includes('加粗和斜体还有删除以及code')).assertTrue();
      expect(out.includes('见文档详解')).assertTrue();
      expect(out.includes('http')).assertFalse(); // url 不进朗读
      expect(out.includes('#')).assertFalse();   // 标题井号不进朗读
    })
    it('speak_skips_code_fence_and_hr', 0, () => {
      const out = mdToSpeakableText('前文\n\n```ts\nconst a = 1;\n```\n\n---\n\n后文');
      expect(out.includes('const a')).assertFalse(); // 围栏代码不朗读
      expect(out.includes('---')).assertFalse();     // 分割线无声
      expect(out.includes('前文')).assertTrue();
      expect(out.includes('后文')).assertTrue();
    })
    it('speak_table_cells_joined', 0, () => {
      const out = mdToSpeakableText('| 列A | 列B |\n| --- | --- |\n| 值1 | 值2 |');
      expect(out.includes('列A，列B')).assertTrue();  // 数据行单元格以「，」连接
      expect(out.includes('---')).assertFalse();     // 分隔行丢弃
      expect(out.includes('|')).assertFalse();       // 竖线不进朗读
      expect(out.includes('值1，值2')).assertTrue();
    })
    it('speak_plain_text_passthrough', 0, () => {
      // 非 Markdown 纯文本零损耗（3*4*5 数学表达保持字面）
      const out = mdToSpeakableText('3*4*5 等于 60，普通中文句子。');
      expect(out).assertEqual('3*4*5 等于 60，普通中文句子。');
    })
    // ---- ★ 0.234.0：锚点标记解析（§8.1-1）----
    it('anchor_legal_line', 0, () => {
      const blocks = parseBlockMd(['前文', '', '[[anchor:quiz|刚讲的三种类型是什么？]]', '', '后文']);
      expect(blocks.length).assertEqual(3);
      expect(blocks[1].kind).assertEqual('anchor');
      expect(blocks[1].anchorType).assertEqual('quiz');
      expect(blocks[1].anchorText).assertEqual('刚讲的三种类型是什么？');
    })
    it('anchor_case_insensitive_type', 0, () => {
      const blocks = parseBlockMd(['[[anchor:HOOK|下一节有惊喜]]']);
      expect(blocks[0].kind).assertEqual('anchor');
      expect(blocks[0].anchorType).assertEqual('hook'); // 大小写不敏感归一小写
    })
    it('anchor_invalid_variants_plain', 0, () => {
      // 半标记（流式截断）/非独占行/非法类型/缺竖线/空文案 → 普通文本
      const half = parseBlockMd(['正文 [[anchor:qu']);
      expect(half[0].kind).assertEqual('p');
      const inline = parseBlockMd(['前文 [[anchor:quiz|文案]] 后文']); // 非独占行
      expect(inline[0].kind).assertEqual('p');
      const badType = parseBlockMd(['[[anchor:warn|文案]]']);
      expect(badType[0].kind).assertEqual('p');
      // ★ 0.237.0：link 已砍（联想权只属于用户）——link 输入一律降级普通文本
      const legacyLink = parseBlockMd(['[[anchor:link|生活联想文案]]']);
      expect(legacyLink[0].kind).assertEqual('p');
      const noBar = parseBlockMd(['[[anchor:quiz 文案]]']);
      expect(noBar[0].kind).assertEqual('p');
      const empty = parseBlockMd(['[[anchor:quiz|   ]]']);
      expect(empty[0].kind).assertEqual('p');
    })
    // ---- ★ 0.237.0：钩子树新三类合法解析 + 徽标池成员 ----
    it('anchor_new_types_legal', 0, () => {
      const rephrase = parseBlockMd(['[[anchor:rephrase|把递归想成套娃]]']);
      expect(rephrase[0].kind).assertEqual('anchor');
      expect(rephrase[0].anchorType).assertEqual('rephrase');
      const predict = parseBlockMd(['[[anchor:PREDICT|你猜下一步会怎么推]]']);
      expect(predict[0].kind).assertEqual('anchor');
      expect(predict[0].anchorType).assertEqual('predict'); // 大小写归一
      const recap = parseBlockMd(['[[anchor:recap|一句话锁住刚讲的]]']);
      expect(recap[0].kind).assertEqual('anchor');
      expect(recap[0].anchorType).assertEqual('recap');
      expect(BREATH_POOL.length).assertEqual(4); // 文案池四条确定性轮换
    })
    // ---- stripAnchorMarks 两种模式（§8.1-3；★ 0.237.0 新类型同规清洗）----
    it('strip_keep_and_drop', 0, () => {
      const src = '第一段\n\n[[anchor:quiz|考考你刚看的]]\n\n第二段';
      const keep = stripAnchorMarks(src, true);
      expect(keep.includes('[[anchor')).assertFalse();
      expect(keep.includes('考考你刚看的')).assertTrue();
      const drop = stripAnchorMarks(src, false);
      expect(drop.includes('[[anchor')).assertFalse();
      expect(drop.includes('考考你刚看的')).assertFalse();
      expect(drop.includes('第一段')).assertTrue();
      expect(drop.includes('第二段')).assertTrue();
      const src2 = '前文\n\n[[anchor:rephrase|大白话重说]]\n\n[[anchor:predict|你猜呢]]\n\n后文';
      const drop2 = stripAnchorMarks(src2, false);
      expect(drop2.includes('[[anchor')).assertFalse();
      expect(drop2.includes('大白话重说')).assertFalse();
      expect(drop2.includes('你猜呢')).assertFalse();
      const keep2 = stripAnchorMarks(src2, true);
      expect(keep2.includes('大白话重说')).assertTrue();
      expect(keep2.includes('你猜呢')).assertTrue();
    })
    // ---- insertLocalAnchors：超阈值补插 / 区间有 AI 锚点不补 / 确定性（§8.1-4）----
    it('local_anchor_insert_rules', 0, () => {
      const mkPara = (ch: string): FoldItem => {
        const b = new MdBlock();
        b.kind = 'p';
        b.lines = [ch.repeat(300)];
        const it = new FoldItem();
        it.kind = 'text';
        it.block = b;
        return it;
      };
      const mkItems = (): FoldItem[] => {
        return [mkPara('a'), mkPara('b'), mkPara('c')];
      };
      const countBreath = (items: FoldItem[]): number => {
        let n = 0;
        for (let i = 0; i < items.length; i++) {
          const b = items[i].block;
          if (items[i].kind === 'anchor' && b !== null && b.anchorType === 'breath') {
            n++;
          }
        }
        return n;
      };
      // a(300)+b(300)=600≥550 → b 后补 1 个 breath；c 是末条不插
      const out = insertLocalAnchors(mkItems(), 550);
      expect(out.length).assertEqual(4);
      expect(out[2].kind).assertEqual('anchor');
      expect(countBreath(out)).assertEqual(1);
      // 确定性：同输入同输出
      const again = insertLocalAnchors(mkItems(), 550);
      const b1 = out[2].block;
      const b2 = again[2].block;
      expect(again.length).assertEqual(4);
      expect(b1 !== null && b2 !== null && b1.anchorText === b2.anchorText).assertTrue();
      // 区间有 AI 锚点重置累计 → 全程不补 breath
      const withAi = mkItems();
      const ai = new MdBlock();
      ai.kind = 'anchor';
      ai.anchorType = 'quiz';
      ai.anchorText = 'AI 锚点';
      const aiItem = new FoldItem();
      aiItem.kind = 'anchor';
      aiItem.block = ai;
      withAi.splice(1, 0, aiItem); // a, AI, b, c → 累计被 AI 锚点清零，各 300 < 550
      const out2 = insertLocalAnchors(withAi, 550);
      expect(out2.length).assertEqual(4);
      expect(countBreath(out2)).assertEqual(0);
      // 密度档阈值（★ 0.237.0 两档制：疏 800 / 密 400；遗留 standard 与非法档位兜底=疏 800）
      expect(breathThreshold('dense')).assertEqual(400);
      expect(breathThreshold('sparse')).assertEqual(800);
      expect(breathThreshold('standard')).assertEqual(800);
      expect(breathThreshold('whatever')).assertEqual(800);
    })
    // ---- ★ 0.237.0：保底文案池节上下文实感（{sec}/{chars} 注入 + 无节语境退化 + 确定性）----
    it('local_anchor_breath_pool_progress', 0, () => {
      const mkH2 = (t: string): FoldItem => {
        const b = new MdBlock();
        b.kind = 'h2';
        b.lines = [t];
        const it = new FoldItem();
        it.kind = 'text';
        it.block = b;
        return it;
      };
      const mkParaN = (): FoldItem => {
        const b = new MdBlock();
        b.kind = 'p';
        b.lines = ['字'.repeat(400)];
        const it = new FoldItem();
        it.kind = 'text';
        it.block = b;
        return it;
      };
      const breathTexts = (items: FoldItem[]): string[] => {
        const out = insertLocalAnchors(items, 400);
        const arr: string[] = [];
        for (let i = 0; i < out.length; i++) {
          const b = out[i].block;
          if (out[i].kind === 'anchor' && b !== null && b.anchorType === 'breath') {
            arr.push(b.anchorText);
          }
        }
        return arr;
      };
      // 有 ## 节：第 3 个 breath 命中参数化文案（pool[2]）→ 携带「第1节」+本节累计字数（400×3=1200）
      const withSec = [mkH2('一、概念'), mkParaN(), mkParaN(), mkParaN(), mkParaN()];
      const texts1 = breathTexts(withSec);
      expect(texts1.length).assertEqual(3); // 前三段各 ≥400 触发，末段不插
      expect(texts1[2].includes('第1节')).assertTrue();
      expect(texts1[2].includes('1200')).assertTrue();
      // 确定性：同输入同输出
      const texts2 = breathTexts(withSec);
      expect(texts1[2] === texts2[2]).assertTrue();
      // 无 ## 兜底语境：参数化文案退化为中性段级表述（不含「第N节」）
      const noSec = [mkParaN(), mkParaN(), mkParaN(), mkParaN()];
      const texts3 = breathTexts(noSec);
      expect(texts3.length).assertEqual(3);
      expect(texts3[2].includes('第')).assertFalse();
      expect(texts3[2].includes('1200')).assertTrue();
    })
    // ---- splitFoldSections：## 切分 / ### 归上节 / 引言第 0 节 / 无 ## 兜底（§8.1-5）----
    it('sections_split_by_h2', 0, () => {
      const blocks = parseBlockMd(['引言段落', '## 一、概念', '概念正文', '### 深入', '深入正文', '## 二、应用', '应用正文']);
      const items: FoldItem[] = blocks.map((b: MdBlock): FoldItem => {
        const it = new FoldItem();
        it.kind = b.kind === 'anchor' ? 'anchor' : 'text';
        it.block = b;
        return it;
      });
      const sections = splitFoldSections(items);
      expect(sections.length).assertEqual(3); // 引言 + 两章
      expect(sections[0].order).assertEqual(0); // 引言第 0 节
      expect(sections[1].order).assertEqual(1);
      expect(sections[1].title).assertEqual('一、概念');
      expect(sections[1].items.length).assertEqual(3); // 概念正文 + ### 标题 + 深入正文（### 归属上一章）
      expect(sections[2].order).assertEqual(2);
      expect(sections[2].title).assertEqual('二、应用');
      // 代码内 ## 不成章节：code 条目内容不参与切分
      const codeItem = new FoldItem();
      codeItem.kind = 'code';
      codeItem.code = '## 注释里的二级标题\nconst x = 1;';
      const p = new MdBlock();
      p.kind = 'p';
      p.lines = ['正文'];
      const textItem = new FoldItem();
      textItem.kind = 'text';
      textItem.block = p;
      const secs2 = splitFoldSections([textItem, codeItem]);
      expect(secs2.length).assertEqual(1); // 全文无 ## → 单段（不足 500 字不切）
    })
    it('sections_no_h2_chunk_500', 0, () => {
      const items: FoldItem[] = [];
      for (let i = 0; i < 4; i++) {
        const b = new MdBlock();
        b.kind = 'p';
        b.lines = ['字'.repeat(300)];
        const it = new FoldItem();
        it.kind = 'text';
        it.block = b;
        items.push(it);
      }
      const sections = splitFoldSections(items);
      expect(sections.length).assertEqual(2); // ★ 0.235.0 修正期望：300+300=600≥500 切一段 / 余 300+300=600 收尾（末块不再切）——原断言 3 与实现语义矛盾（「余 300 收尾」需第 5 块），0.234.0 落地后未设备跑过、今日首跑暴露
      expect(sections[0].numbered).assertFalse(); // 兜底段非 ## 章节
      expect(sections[0].order).assertEqual(1);
      // 空输入边界
      expect(splitFoldSections([]).length).assertEqual(0);
    })
    // ---- initExpandedSet：≥3 节前 ceil(N/3)+引言；<3 节 null（§8.1-6）----
    it('expanded_set_rules', 0, () => {
      const mkSections = (n: number): FoldSection[] => {
        const secs: FoldSection[] = [];
        const intro = new FoldSection();
        intro.order = 0;
        const introP = new MdBlock();
        introP.kind = 'p';
      introP.lines = ['引言'];
        const introItem = new FoldItem();
        introItem.kind = 'text';
        introItem.block = introP;
        intro.items.push(introItem);
        secs.push(intro);
        for (let i = 1; i <= n; i++) {
          const s = new FoldSection();
          s.order = i;
          s.numbered = true;
          s.title = `第${i}章`;
          const b = new MdBlock();
          b.kind = 'p';
          b.lines = ['x'.repeat(100)];
          const it = new FoldItem();
          it.kind = 'text';
          it.block = b;
          s.items.push(it);
          secs.push(s);
        }
        for (let i = 0; i < secs.length; i++) {
          secs[i].index = i;
        }
        return secs;
      };
      // 5 节：ceil(5/3)=2 → 展开引言(0)+前 2 章
      const set5 = initExpandedSet(mkSections(5));
      expect(set5 !== null).assertTrue();
      expect(set5!.size).assertEqual(3);
      expect(set5!.has(0)).assertTrue();
      expect(set5!.has(1)).assertTrue();
      expect(set5!.has(2)).assertTrue();
      expect(set5!.has(3)).assertFalse();
      // 3 节：ceil(3/3)=1 → 引言+第 1 章
      const set3 = initExpandedSet(mkSections(3));
      expect(set3 !== null).assertTrue();
      expect(set3!.size).assertEqual(2);
      // 2 节：null（不折叠）
      expect(initExpandedSet(mkSections(2))).assertNull();
    })

    // ---- 0.285.5：表格整表工具（放大弹窗复制整表/文本模式共用） ----
    it('table_markdown_full', 0, () => {
      const md = buildTableMarkdown(['列A', '列B'], [['1', '2'], ['3', '4']]);
      expect(md).assertEqual('| 列A | 列B |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |');
    })
    it('table_markdown_pipe_escaped_and_row_normalized', 0, () => {
      // 单元格内半角竖线转全角（防破坏列结构）；少格行补空、多格行截断（按表头列数归一）
      const md = buildTableMarkdown(['a', 'b'], [['x|y'], ['1', '2', '3']]);
      const lines = md.split('\n');
      expect(lines.length).assertEqual(4);
      expect(lines[0]).assertEqual('| a | b |');
      expect(lines[2]).assertEqual('| x｜y |  |');
      expect(lines[3]).assertEqual('| 1 | 2 |');
    })
    it('table_plain_text_layout', 0, () => {
      const pt = buildTablePlainText(['h1', 'h2'], [['v1', 'v2']]);
      expect(pt).assertEqual('h1 | h2\nv1 | v2');
    })
  })
}
