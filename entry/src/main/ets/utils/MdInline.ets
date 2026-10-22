// ============================================================
// MdInline.ets — Markdown 块级/行内纯函数解析器（★ 0.231.0）
// ============================================================
// 用途：ChatPage AI 消息富文本渲染（type=0 普通文本段）+ ohosTest hypium 单元断言双消费
//   （project_rule §12.13 测试覆盖军令：新功能必须带测试项——纯函数独立成模块即为此）
// 设计约束：
//   - 保守流式安全：只认成对标记，未闭合（打字机流式中间态）按字面量，不闪乱
//   - 块级先行（列表项/引用行不再走行内标记歧义，如 * 项 vs *斜体*）
//   - 数学公式（renderMathText）在 parse 层之前已转换，本模块只见纯文本
// ArkTS：无 any/无类型断言/无对象字面量类型；类字段显式默认值
// ============================================================

// 行内样式片段（Text → Span 一一对应）
export class MdSpan {
  text: string = '';
  bold: boolean = false;
  italic: boolean = false;
  strike: boolean = false;
  code: boolean = false;
  link: boolean = false;
  url: string = '';
}

// 块级单元（kind：p 段落 / h1~h6 标题 / li 无序列表 / oli 有序列表 / quote 引用 / hr 分割线 /
//   anchor 注意力锚点 ★ 0.234.0）
export class MdBlock {
  kind: string = 'p';
  order: string = ''; // oli 序号文本（如 '3.'）
  depth: number = 0; // 列表缩进层级（2 空格一级）
  lines: string[] = []; // 该块的原始行（p/quote 可多行；单行块=1 行）
  anchorType: string = ''; // ★ 0.234.0：锚点类型；★ 0.237.0 六类（quiz/hook/rephrase/predict/recap/breath；kind='anchor' 时有效）
  anchorText: string = ''; // ★ 0.234.0：锚点文案（lines 同步存一份，保 blockPlainText/降级渲染兼容）
}

// 链接解析中间产物（ArkTS 无元组，用类承载）
class ParsedLink {
  text: string = '';
  url: string = '';
  next: number = 0; // 解析完成后的继续扫描位置
}

// 判断字符是否参与词边界的字母/数字（仅 ASCII——CJK 属开放式文字，「前缀**加粗**」
// 这类贴字强调是主流形态必须放行；ASCII 字母数字才挡（3*4*5 数学表达防误判斜体））
function isAlnumLike(c: string): boolean {
  if (c.length !== 1) {
    return false;
  }
  const code = c.charCodeAt(0);
  return (code >= 0x30 && code <= 0x39) || (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
}

function prevChar(text: string, i: number): string {
  return i > 0 ? text.charAt(i - 1) : '';
}

function nextChar(text: string, i: number): string {
  return i + 1 < text.length ? text.charAt(i + 1) : '';
}

// 开侧闸（左 flanking 简化版）：标记符前不能是字母数字（挡 3*4 类数学表达误判斜体）
function canOpenMarker(text: string, i: number): boolean {
  const p = prevChar(text, i);
  return p === '' || p === ' ' || !isAlnumLike(p);
}

// 内容合法性：非空且首尾非空白（** x** / **x ** 按字面量——CommonMark 同款约束）
function validEmphasisContent(content: string): boolean {
  if (content.length === 0) {
    return false;
  }
  const first = content.charAt(0);
  const last = content.charAt(content.length - 1);
  return first !== ' ' && first !== '\t' && last !== ' ' && last !== '\t';
}

// 在 from 起找 count 连个 ch 的闭合位置（内容合法性一并校验；找不到=-1）
function findCloseMarker(text: string, from: number, ch: string, count: number): number {
  let j = from;
  while (j < text.length) {
    if (text.charAt(j) === ch) {
      let run = 1;
      while (j + run < text.length && text.charAt(j + run) === ch) {
        run++;
      }
      if (run === count) {
        const content = text.substring(from, j);
        if (validEmphasisContent(content)) {
          return j;
        }
        return -1; // 闭合到位但内容非法（首尾空白）——按字面量整体放弃
      }
      j += run;
      continue;
    }
    j++;
  }
  return -1;
}

// [text](url) 解析（i 指向 '['；失败=null 按字面量）
function tryParseLink(text: string, i: number): ParsedLink | null {
  const closeBracket = text.indexOf(']', i + 1);
  if (closeBracket < 0 || closeBracket === i + 1) {
    return null; // 无闭合或空文案
  }
  if (text.charAt(closeBracket + 1) !== '(') {
    return null;
  }
  const closeParen = text.indexOf(')', closeBracket + 2);
  if (closeParen < 0) {
    return null;
  }
  const url = text.substring(closeBracket + 2, closeParen);
  if (url.length === 0 || url.length > 2048 || url.indexOf(' ') >= 0 || url.indexOf('\n') >= 0) {
    return null;
  }
  const label = text.substring(i + 1, closeBracket);
  const out = new ParsedLink();
  out.text = label;
  out.url = url;
  out.next = closeParen + 1;
  return out;
}

// 行内解析：**粗** *斜* ***粗斜*** ~~删~~ `码` [链](url)（流式安全：未闭合=字面量）
export function parseInlineMd(text: string): MdSpan[] {
  const spans: MdSpan[] = [];
  let buf = '';
  let i = 0;
  const n = text.length;
  const pushPlain = (): void => {
    if (buf.length > 0) {
      const s = new MdSpan();
      s.text = buf;
      spans.push(s);
      buf = '';
    }
  };
  const pushStyled = (content: string, bold: boolean, italic: boolean, strike: boolean,
    code: boolean, link: boolean, url: string): void => {
    pushPlain();
    const s = new MdSpan();
    s.text = content;
    s.bold = bold;
    s.italic = italic;
    s.strike = strike;
    s.code = code;
    s.link = link;
    s.url = url;
    spans.push(s);
  };
  while (i < n) {
    const c = text.charAt(i);
    // 行内代码：`...`（内容不含反引号与换行）
    if (c === '`') {
      const close = text.indexOf('`', i + 1);
      if (close > i + 1) {
        const content = text.substring(i + 1, close);
        if (content.indexOf('\n') < 0) {
          pushStyled(content, false, false, false, true, false, '');
          i = close + 1;
          continue;
        }
      }
      buf += c;
      i++;
      continue;
    }
    // 链接：[text](url)
    if (c === '[') {
      const parsed = tryParseLink(text, i);
      if (parsed !== null) {
        pushStyled(parsed.text, false, false, false, false, true, parsed.url);
        i = parsed.next;
        continue;
      }
      buf += c;
      i++;
      continue;
    }
    // 删除线：~~x~~
    if (c === '~' && nextChar(text, i) === '~') {
      const close = findCloseMarker(text, i + 2, '~', 2);
      if (close > 0) {
        pushStyled(text.substring(i + 2, close), false, false, true, false, false, '');
        i = close + 2;
        continue;
      }
      buf += c;
      i++;
      continue;
    }
    // 强调族：***x*** / **x** / *x*（_ 同规）
    if (c === '*' || c === '_') {
      if (canOpenMarker(text, i)) {
        // 三连：粗+斜
        if (text.charAt(i + 1) === c && text.charAt(i + 2) === c) {
          const close = findCloseMarker(text, i + 3, c, 3);
          if (close > 0) {
            pushStyled(text.substring(i + 3, close), true, true, false, false, false, '');
            i = close + 3;
            continue;
          }
        }
        // 双连：粗
        if (text.charAt(i + 1) === c) {
          const close = findCloseMarker(text, i + 2, c, 2);
          if (close > 0) {
            pushStyled(text.substring(i + 2, close), true, false, false, false, false, '');
            i = close + 2;
            continue;
          }
        } else {
          // 单连：斜（下划线词内斜体本就被 canOpenMarker 挡死）
          const close = findCloseMarker(text, i + 1, c, 1);
          if (close > 0) {
            pushStyled(text.substring(i + 1, close), false, true, false, false, false, '');
            i = close + 1;
            continue;
          }
        }
      }
      buf += c;
      i++;
      continue;
    }
    buf += c;
    i++;
  }
  pushPlain();
  return spans;
}

const RE_HR: RegExp = /^ {0,3}(-{3,}|\*{3,}|_{3,}) *$/;
const RE_HEADER: RegExp = /^(#{1,6}) +(.*?)\s*#* *$/;
const RE_UL: RegExp = /^( {0,12})([-*•]) +(.*)$/;
const RE_OL: RegExp = /^( {0,12})(\d{1,3})[.)] +(.*)$/;
const RE_QUOTE: RegExp =/^> ?(.*)$/;
// ★ 0.234.0：锚点标记行——[[anchor:类型|文案]] 独占一行（前后空行由块级空行切分天然保证）
const RE_ANCHOR: RegExp = /^\[\[anchor:([a-zA-Z]+)\|(.+)\]\]$/;

// ★ 0.237.0：锚点类型白名单（六类——5 类 AI 生成 + breath 本地保留）；
//   砍 link（联想权只属于用户，AI 发散联想必然不对味——link 输入一律降级普通文本）
// ★ 0.269.0：钩子模式两段式扩三类——digest（简单说）/ progress（到这里了，本地保底专用）/
//   bait（文末引子）；quiz/predict 仅保留于单段式中回复既有锚点体系（两段式长回复移除）
const ANCHOR_TYPES: string[] = ['quiz', 'hook', 'rephrase', 'predict', 'recap', 'breath', 'digest', 'progress', 'bait'];

function isAnchorType(type: string): boolean {
  for (let i = 0; i < ANCHOR_TYPES.length; i++) {
    if (ANCHOR_TYPES[i] === type) {
      return true;
    }
  }
  return false;
}

// ★ 0.234.0：解析独占行锚点标记（宽容协议：类型大小写不敏感）；
//   ★ 0.237.0 白名单=quiz/hook/rephrase/predict/recap/breath；非法类型（含已砍的 link）/缺竖线/空文案/
//   非独占行 → null=普通文本
function parseAnchorLine(line: string): MdBlock | null {
  const m = RE_ANCHOR.exec(line.trim());
  if (m === null) {
    return null;
  }
  const type = m[1].toLowerCase();
  const text = m[2].trim();
  if (!isAnchorType(type) || text.length === 0) {
    return null;
  }
  const b = new MdBlock();
  b.kind = 'anchor';
  b.anchorType = type;
  b.anchorText = text;
  b.lines = [text];
  return b;
}

// 块级解析：标题/分割线/引用/有序无序列表/段落（连续普通行合并为一个 p 块）
export function parseBlockMd(lines: string[]): MdBlock[] {
  const blocks: MdBlock[] = [];
  let paraLines: string[] = [];
  let quoteLines: string[] = [];
  const flushPara = (): void => {
    if (paraLines.length > 0) {
      const b = new MdBlock();
      b.kind = 'p';
      b.lines = paraLines;
      blocks.push(b);
      paraLines = [];
    }
  };
  const flushQuote = (): void => {
    if (quoteLines.length > 0) {
      const b = new MdBlock();
      b.kind = 'quote';
      b.lines = quoteLines;
      blocks.push(b);
      quoteLines = [];
    }
  };
  for (let li = 0; li < lines.length; li++) {
    const line = lines[li];
    if (line.trim() === '') {
      flushPara();
      flushQuote();
      continue;
    }
    // ★ 0.234.0：独占行锚点标记 → 锚点块（半标记/非法 → null 走普通文本，流式截断安全）
    const anchor = parseAnchorLine(line);
    if (anchor !== null) {
      flushPara();
      flushQuote();
      blocks.push(anchor);
      continue;
    }
    const hr = RE_HR.exec(line);
    if (hr !== null) {
      flushPara();
      flushQuote();
      const b = new MdBlock();
      b.kind = 'hr';
      b.lines = [];
      blocks.push(b);
      continue;
    }
    const header = RE_HEADER.exec(line);
    if (header !== null && header[2].length > 0) {
      flushPara();
      flushQuote();
      const b = new MdBlock();
      b.kind = 'h' + header[1].length;
      b.lines = [header[2]];
      blocks.push(b);
      continue;
    }
    const ul = RE_UL.exec(line);
    if (ul !== null && ul[3].length > 0) {
      flushPara();
      flushQuote();
      const b = new MdBlock();
      b.kind = 'li';
      b.depth = Math.min(Math.floor(ul[1].length / 2), 6);
      b.lines = [ul[3]];
      blocks.push(b);
      continue;
    }
    const ol = RE_OL.exec(line);
    if (ol !== null && ol[3].length > 0) {
      flushPara();
      flushQuote();
      const b = new MdBlock();
      b.kind = 'oli';
      b.depth = Math.min(Math.floor(ol[1].length / 2), 6);
      b.order = ol[2] + '.';
      b.lines = [ol[3]];
      blocks.push(b);
      continue;
    }
    const quote = RE_QUOTE.exec(line.trim());
    if (quote !== null) {
      flushPara();
      quoteLines.push(quote[1]);
      continue;
    }
    flushQuote();
    paraLines.push(line);
  }
  flushPara();
  flushQuote();
  return blocks;
}

// 块的纯文本（渲染 Text 的选择偏移基准=所见内容；列表项不含符号、引用不含 >）
export function blockPlainText(block: MdBlock): string {
  return block.lines.join('\n');
}

// ★ 0.237.1：块的「渲染态文本」——与 ChatPage.MdBlockText 实际渲染的 Span 序列逐字符一致：
//   li 前缀 '• '、oli 前缀 order+' '、行内 parseInlineMd 剥 **/~~/`/[链](url) 标记、行间 '\n'。
//   划词选区偏移（onTextSelectionChange）按渲染文本计，取词/全选长度必须用同一字符串——
//   此前误用 blockPlainText（原始行含标记、无列表前缀），凡消息带行内标记，划词取词整体前移（用户实锤）。
//   纯函数=ChatPage 划词基准 + ohosTest 断言双消费（§12.13）。
export function blockRenderedText(block: MdBlock): string {
  let prefix = '';
  if (block.kind === 'li') {
    prefix = '• ';
  } else if (block.kind === 'oli') {
    prefix = block.order + ' ';
  }
  const renderedLines: string[] = [];
  for (let i = 0; i < block.lines.length; i++) {
    const spans = parseInlineMd(block.lines[i]);
    let t = '';
    for (let s = 0; s < spans.length; s++) {
      t += spans[s].text;
    }
    renderedLines.push(t);
  }
  return prefix + renderedLines.join('\n');
}

// 标题字号映射（基准 16 正文——ChatPage fs() 缩放前的 vp 值）
export function headerFontSize(kind: string): number {
  switch (kind) {
    case 'h1':
      return 21;
    case 'h2':
      return 19.5;
    case 'h3':
      return 18;
    case 'h4':
      return 17;
    case 'h5':
      return 16;
    default:
      return 15;
  }
}

// 表格分隔行（|---|---| 形态，仅 |、-、:、空格组成）
function isTableSeparatorLine(line: string): boolean {
  const t = line.trim();
  if (t.length === 0 || t.charAt(0) !== '|') {
    return false;
  }
  for (let i = 0; i < t.length; i++) {
    const c = t.charAt(i);
    if (c !== '|' && c !== '-' && c !== ':' && c !== ' ') {
      return false;
    }
  }
  return t.indexOf('-') >= 0;
}

// ★ 0.232.0：Markdown → 可朗读纯文本（TTS 专用——云端/本地引擎共用）。
// 用户痛点锚点：「本地语音连星号星号都要读进去」。规则：
//   - 代码围栏（``` 整段）跳过（读代码=纯噪音）
//   - 表格分隔行 / 分割线（hr）跳过；表格数据行 → 单元格以「，」连接
//   - 块级结构走 parseBlockMd（标题#、列表符号、引用> 由块分类天然剥离——blockPlainText
//     不含这些符号）；行内标记（**粗**/*斜*/~~删~~/`码`）走 parseInlineMd 取 span 文本拼接，
//     链接保留锚文本、丢弃 url
//   - 纯文本原样通过（非 Markdown 内容零损耗）
export function mdToSpeakableText(content: string): string {
  const lines = content.split('\n');
  const kept: string[] = [];
  let inFence = false;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();
    // 代码围栏开关（``` 或 ```lang）
    if (trimmed.length >= 3 && trimmed.substring(0, 3) === '```') {
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      continue; // 围栏内代码不朗读
    }
    if (trimmed.length === 0) {
      kept.push('');
      continue;
    }
    // 表格行：分隔行丢弃，数据行单元格以「，」连接
    if (trimmed.charAt(0) === '|') {
      if (!isTableSeparatorLine(line)) {
        const cells: string[] = [];
        const parts = trimmed.split('|');
        for (let j = 0; j < parts.length; j++) {
          const cell = parts[j].trim();
          if (cell.length > 0) {
            cells.push(cell);
          }
        }
        kept.push(cells.join('，'));
      }
      continue;
    }
    kept.push(line);
  }
  // 块级+行内双解析剥标记
  const blocks = parseBlockMd(kept);
  const out: string[] = [];
  for (let b = 0; b < blocks.length; b++) {
    const block = blocks[b];
    if (block.kind === 'hr') {
      continue; // 分割线无声
    }
    for (let l = 0; l < block.lines.length; l++) {
      const spans = parseInlineMd(block.lines[l]);
      let lineText = '';
      for (let s = 0; s < spans.length; s++) {
        lineText += spans[s].text;
      }
      out.push(lineText);
    }
  }
  return out.join('\n').trim();
}

// ============================================================
// ★ 0.234.0 注意力锚点 + 长文分章折叠（docs/0.165+/0.234.0 注意力锚点一期.md §5.1）
// 全部纯函数（ohosTest 双消费）：标记清洗 / breath 本地保底 / 章节切分 / 默认展开集
// ============================================================

// 锚点标记整行清洗：keepText=true 去 [[anchor:type| 与 ]] 留文案（TTS 用）；
//   false 整行删（复制/链路摘要上下文用——防标记污染送 LLM 的内容）
export function stripAnchorMarks(content: string, keepText: boolean): string {
  const lines = content.split('\n');
  const out: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    const m = RE_ANCHOR.exec(lines[i].trim());
    if (m !== null) {
      if (keepText) {
        out.push(m[2].trim());
      }
      continue; // keepText=false：整行丢弃
    }
    out.push(lines[i]);
  }
  return out.join('\n');
}

// ★ 0.237.0 breath 本地保底文案池——「到这里了」进度实感定位（替代一期「歇口气」空洞安慰）：
//   由结构信息本地可算（不进语义填空）；{sec}/{chars} 占位由 insertLocalAnchors 注入
//   （第几节 / 本节累计字数——渲染上下文实感）；确定性轮换纪律不变（同输入同输出；禁止 emoji）
export const BREATH_POOL: string[] = [
  '读到这里，你已经走完这一节了',
  '停一下：上面这段已经讲完了，往下是新的内容点',
  '到第{sec}节了，本节刚讲了约{chars}字',
  '喘口气，把这一段和前面连起来再看下一段'
];

// 保底文案占位解析：{sec}=当前节序号（1 起；0=引言/无 ## 兜底语境）、{chars}=本节累计正文字数；
//   无节语境时参数化文案退化为中性段级表述（确定性不变）
function resolveBreathText(tpl: string, sec: number, chars: number): string {
  if (tpl.indexOf('{sec}') < 0) {
    return tpl;
  }
  if (sec <= 0) {
    return `到这里告一段落了，这一段约 ${chars} 字，下面是新的内容`;
  }
  return tpl.replace('{sec}', String(sec)).replace('{chars}', String(chars));
}

// 密度档 → 本地保底阈值（★ 0.237.0 两档制，用户拍板去掉「中」：疏 800 / 密 400 字）；
//   非 dense（含遗留 standard 与一切非法档位）一律兜底疏 800；AI 侧密度联动见 Prompts.ts
export function breathThreshold(density: string): number {
  if (density === 'dense') {
    return 400;
  }
  return 800;
}

// 消息渲染条目——统一承载文本块/锚点/代码块/表格（ChatPage 由 parseMarkdown 段落展开；
//   章节切分与锚点保底在此流上运行，代码块/表格天然不被截断）
export class FoldItem {
  kind: string = 'text';        // 'text'（block 承载）| 'anchor' | 'code' | 'table'
  block: MdBlock | null = null; // text/anchor 条目的块
  lang: string = '';            // code 语言
  code: string = '';            // code 内容
  header: string[] = [];        // table 表头
  rows: string[][] = [];        // table 数据行
  segIdx: number = 0;           // 来源段落号（平铺渲染按段重组用；折叠视图不依赖）
}

// 条目字符量（正文块取纯文本；代码取内容长；表格取单元格合计；锚点不计——间距按正文字数）
export function foldItemCharCount(item: FoldItem): number {
  if (item.kind === 'text' && item.block !== null) {
    return blockPlainText(item.block).length;
  }
  if (item.kind === 'code') {
    return item.code.length;
  }
  if (item.kind === 'table') {
    let n = 0;
    for (let i = 0; i < item.header.length; i++) {
      n += item.header[i].length;
    }
    for (let r = 0; r < item.rows.length; r++) {
      const row = item.rows[r];
      for (let c = 0; c < row.length; c++) {
        n += row[c].length;
      }
    }
    return n;
  }
  return 0;
}

// 本地 breath 保底插入：累计正文 ≥ threshold 且区间无 AI 锚点时在文本块边界补 1 个 breath；
//   相邻锚点最小间距 200 字由 threshold≥400 天然满足；只在文本块后插（代码/表格边界不插，
//   免平铺渲染按段重组复杂化）；末条后不插（避免消息尾巴突兀）；确定性=同输入同输出
// ★ 0.237.0：节上下文实感注入——随走随记当前 ## 节序号与本节累计字数（h2 本体不计字数），
//   BREATH_POOL 参数化文案（{sec}/{chars}）由 resolveBreathText 就地解析
export function insertLocalAnchors(items: FoldItem[], threshold: number): FoldItem[] {
  const out: FoldItem[] = [];
  let since = 0;
  let pool = 0;
  let secOrder = 0;
  let secChars = 0;
  for (let i = 0; i < items.length; i++) {
    const blk = items[i].block;
    const isH2 = items[i].kind === 'text' && blk !== null && blk.kind === 'h2';
    if (isH2) {
      secOrder += 1;
      secChars = 0;
    }
    out.push(items[i]);
    if (items[i].kind === 'anchor') {
      since = 0; // AI 锚点重置累计
      continue;
    }
    since += foldItemCharCount(items[i]);
    if (!isH2) {
      secChars += foldItemCharCount(items[i]);
    }
    if (since >= threshold && i < items.length - 1 && items[i].kind === 'text') {
      const b = new MdBlock();
      b.kind = 'anchor';
      b.anchorType = 'breath';
      b.anchorText = resolveBreathText(BREATH_POOL[pool % BREATH_POOL.length], secOrder, secChars);
      b.lines = [b.anchorText];
      const it = new FoldItem();
      it.kind = 'anchor';
      it.block = b;
      it.segIdx = items[i].segIdx;
      out.push(it);
      pool++;
      since = 0;
    }
  }
  return out;
}

// 章节：title 空=开篇引言（order 0，不占章节序号）；numbered=true 为 ## 章节；
//   无 ## 兜底切段时 numbered=false（显示「第 X 段」）
export class FoldSection {
  title: string = '';
  items: FoldItem[] = [];
  charCount: number = 0;
  index: number = 0;   // 在 sections 数组中的下标（折叠状态 Set 存此值）
  order: number = 0;   // 章节序号（1 起；0=开篇引言）
  numbered: boolean = false; // true=## 章节（「第 X 节」）；false=无 ## 兜底段（「第 X 段」）
}

// 章节切分（本期核心）：## h2 块开新章（块级归属——### 以下/列表/代码/表格全部归属最近上一章，
//   天然不截断）；开头到首个 ## 为开篇引言（第 0 节）；全文无 ## 时按块累计 ~500 字切段兜底
export function splitFoldSections(items: FoldItem[]): FoldSection[] {
  const sections: FoldSection[] = [];
  let hasH2 = false;
  let order = 0;
  let cur = new FoldSection();
  const closeCur = (): void => {
    if (cur.items.length > 0) {
      sections.push(cur);
    }
    cur = new FoldSection();
  };
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    if (item.kind === 'text' && item.block !== null && item.block.kind === 'h2') {
      hasH2 = true;
      closeCur();
      order += 1;
      cur.title = blockPlainText(item.block);
      cur.order = order;
      cur.numbered = true;
      continue; // h2 块本体由折叠行承载，不重复渲染
    }
    cur.items.push(item);
    cur.charCount += foldItemCharCount(item);
  }
  closeCur();
  if (!hasH2) {
    // 无 ## 兜底：全部条目按累计 ~500 字切块（块边界切，不拆代码/表格）
    if (sections.length === 0) {
      return sections; // 空输入
    }
    const all = sections[0].items;
    const chunks: FoldSection[] = [];
    let chunk = new FoldSection();
    let co = 0;
    for (let i = 0; i < all.length; i++) {
      chunk.items.push(all[i]);
      chunk.charCount += foldItemCharCount(all[i]);
      if (chunk.charCount >= 500 && i < all.length - 1) {
        co += 1;
        chunk.order = co;
        chunks.push(chunk);
        chunk = new FoldSection();
      }
    }
    if (chunk.items.length > 0) {
      co += 1;
      chunk.order = co;
      chunks.push(chunk);
    }
    for (let c = 0; c < chunks.length; c++) {
      chunks[c].index = c;
    }
    return chunks;
  }
  for (let s = 0; s < sections.length; s++) {
    sections[s].index = s;
  }
  return sections;
}

// 默认展开集：≥3 节（order>0 的章/段计数）返回 前 ceil(N/3) 节 + 开篇引言 的 index 集；
// <3 节返回 null（折叠无意义，平铺全显）
export function initExpandedSet(sections: FoldSection[]): Set<number> | null {
  let numberedCount = 0;
  for (let i = 0; i < sections.length; i++) {
    if (sections[i].order > 0) {
      numberedCount++;
    }
  }
  if (numberedCount < 3) {
    return null;
  }
  const take = Math.ceil(numberedCount / 3);
  const set = new Set<number>();
  let taken = 0;
  for (let i = 0; i < sections.length; i++) {
    if (sections[i].order === 0) {
      set.add(i); // 开篇引言恒展开
      continue;
    }
    if (taken < take) {
      set.add(i);
      taken++;
    }
  }
  return set;
}

// ============================================================
// ★ 0.290.0 司枢模式 2.0：框架先行两段式纯函数层（任务书 WP2 §3.2/§3.3）
// ①段规划器输出框架 JSON → sanitizePlan 防弹衣（解析+修补+幻觉拦截）→
//   ②段执笔按框架写正文 → mergeSectionHooks 按 afterSection 节号渲染期插钩子。
// 全部纯函数（ohosTest 双消费）；旧 0.269.0 块级合成器（HookSpec/parseHookJsonResponse/
//   scanBlockSpans/mergeHooksIntoContent）已随 HOOK_SYSTEM_PROMPT 退役整体移除，
//   progress 类钩子同步绝迹（WP4：终态四类 digest/breath/quiz/bait）。
// ============================================================

// 框架节（## 标题 + 要点 + 深度档）
export class PlanSection {
  title: string = '';
  points: string[] = [];
  depth: string = 'deep'; // plain=直给要点 / deep=深入原理
}

// 框架钩子（afterSection=节号从 1 起，插在该节末尾；bait 恒最后一节）
export class PlanHook {
  afterSection: number = 1;
  type: string = ''; // digest / breath / quiz / bait 四枚举（progress 已砍）
  text: string = '';
}

// 规划框架（①段输出 schema）
export class PlanFrame {
  lengthTier: string = 'medium'; // brief / medium / long
  targetChars: number = 900;
  reason: string = '';
  sections: PlanSection[] = [];
  hooks: PlanHook[] = [];
  voice: string = 'senior';   // senior 学长 / coach 教练 / tool 工具
  encourage: string = 'low';  // high / low
  analogy: string = 'less';   // more / less
}

const PLAN_HOOK_TYPES: string[] = ['digest', 'breath', 'quiz', 'bait'];

function isPlanHookType(t: string): boolean {
  for (let i = 0; i < PLAN_HOOK_TYPES.length; i++) {
    if (PLAN_HOOK_TYPES[i] === t) {
      return true;
    }
  }
  return false;
}

/**
 * ★ 0.290.0 框架防弹衣（任务书 §3.3，Q3+Q6 审批裁决）：
 * 1. JSON 解析失败（含围栏/废话抠取兜底）→ null（调用侧重试①段一次，仍 null 走直写 fallback）；
 * 2. 字段修补：lengthTier 不认识→钳 medium；sections 空→塞默认节；afterSection 越界→钳到最后一节；
 *    hooks.type 非四枚举→丢弃该条；bait 只留最后一条并固定最后一节；节数 >8 裁到 8；
 * 3. 幻觉拦截（Q6）：targetChars≥1500 但 points 合计 <30 字 → 判框架废 → null（走直写）。
 */
export function sanitizePlan(raw: string): PlanFrame | null {
  const text = raw.trim();
  const l = text.indexOf('{');
  const r = text.lastIndexOf('}');
  if (l < 0 || r <= l) {
    return null;
  }
  let obj: Record<string, Object> | null = null;
  try {
    obj = JSON.parse(text.substring(l, r + 1)) as Record<string, Object>;
  } catch (_e) {
    return null;
  }
  if (obj === null || obj === undefined) {
    return null;
  }
  const frame = new PlanFrame();
  // 长度档修补
  const tier = String(obj['lengthTier'] ?? '');
  if (tier === 'brief' || tier === 'medium' || tier === 'long') {
    frame.lengthTier = tier;
  } else {
    frame.lengthTier = 'medium'; // 不认识钳 medium
  }
  // 目标字数修补（非法值按档位默认；全域钳 150~6000）
  const tc = Number(obj['targetChars']);
  const tierDefault = frame.lengthTier === 'brief' ? 300 : (frame.lengthTier === 'long' ? 1800 : 900);
  let target = Number.isFinite(tc) && tc > 0 ? Math.round(tc) : tierDefault;
  if (target < 150) {
    target = 150;
  }
  if (target > 6000) {
    target = 6000;
  }
  frame.targetChars = target;
  frame.reason = String(obj['reason'] ?? '').substring(0, 60);
  // sections 修补（空→默认节；>8 裁 8；title 空→「第N节」；depth 非法→deep）
  // ArkTS：Object 值经 JSON 往返具名化为 Record 数组（防 any 索引，applyProfileResult 同族模式）
  let rawSections: Record<string, Object>[] = [];
  try {
    if (obj['sections'] instanceof Array) {
      rawSections = JSON.parse(JSON.stringify(obj['sections'])) as Record<string, Object>[];
    }
  } catch (_e) {
    rawSections = [];
  }
  for (let i = 0; i < rawSections.length && frame.sections.length < 8; i++) {
    const rec = rawSections[i];
    const sec = new PlanSection();
    const title = String(rec['title'] ?? '').trim();
    sec.title = title.length > 0 ? title.substring(0, 40) : `第${frame.sections.length + 1}节`;
    if (rec['points'] instanceof Array) {
      const pts = JSON.parse(JSON.stringify(rec['points'])) as Object[];
      for (let p = 0; p < pts.length && p < 8; p++) {
        const pt = String(pts[p] ?? '').trim();
        if (pt.length > 0) {
          sec.points.push(pt.substring(0, 60));
        }
      }
    }
    const dep = String(rec['depth'] ?? '');
    sec.depth = dep === 'plain' ? 'plain' : 'deep';
    frame.sections.push(sec);
  }
  if (frame.sections.length === 0) {
    const def = new PlanSection();
    def.title = '解答';
    def.points.push('围绕用户问题完整解答');
    def.depth = 'deep';
    frame.sections.push(def);
  }
  const secCount = frame.sections.length;
  // hooks 修补（类型四枚举丢弃非法；text 空/超 20 截断；afterSection 钳 1..secCount；bait 取最后一条固定末节）
  let rawHooks: Record<string, Object>[] = [];
  try {
    if (obj['hooks'] instanceof Array) {
      rawHooks = JSON.parse(JSON.stringify(obj['hooks'])) as Record<string, Object>[];
    }
  } catch (_e) {
    rawHooks = [];
  }
  let baitText = '';
  for (let i = 0; i < rawHooks.length && i < 8; i++) {
    const rec = rawHooks[i];
    const type = String(rec['type'] ?? '');
    if (!isPlanHookType(type)) {
      continue; // 非四枚举（含 progress）丢弃
    }
    let ht = String(rec['text'] ?? '').trim();
    if (ht.length === 0) {
      continue;
    }
    if (ht.length > 20) {
      ht = ht.substring(0, 20);
    }
    if (type === 'bait') {
      baitText = ht; // 保留最后一条
      continue;
    }
    const hook = new PlanHook();
    const as = Number(rec['afterSection']);
    let sec = Number.isFinite(as) ? Math.floor(as) : secCount;
    if (sec < 1) {
      sec = 1;
    }
    if (sec > secCount) {
      sec = secCount; // 越界钳到最后一节
    }
    hook.afterSection = sec;
    hook.type = type;
    hook.text = ht;
    frame.hooks.push(hook);
  }
  if (baitText.length > 0) {
    const bait = new PlanHook();
    bait.afterSection = secCount;
    bait.type = 'bait';
    bait.text = baitText;
    frame.hooks.push(bait);
  }
  // tone 修补（各字段非法→默认）
  const tone = obj['tone'];
  if (tone !== null && tone !== undefined && typeof tone === 'object') {
    const trec = tone as Record<string, Object>;
    const v = String(trec['voice'] ?? '');
    frame.voice = v === 'coach' || v === 'tool' ? v : 'senior';
    const e = String(trec['encourage'] ?? '');
    frame.encourage = e === 'high' ? 'high' : 'low';
    const a = String(trec['analogy'] ?? '');
    frame.analogy = a === 'more' ? 'more' : 'less';
  }
  // 幻觉拦截（Q6）：long 目标字数撑不起要点量=废框架
  let pointsChars = 0;
  for (let i = 0; i < frame.sections.length; i++) {
    for (let p = 0; p < frame.sections[i].points.length; p++) {
      pointsChars += frame.sections[i].points[p].length;
    }
  }
  if (frame.targetChars >= 1500 && pointsChars < 30) {
    return null;
  }
  return frame;
}

/** 框架紧凑 JSON（②段执笔 system 注入用——只保留执笔所需字段） */
interface FrameSecJson {
  title: string;
  points: string[];
  depth: string;
}
interface FrameRootJson {
  sections: FrameSecJson[];
}

export function planFrameJson(frame: PlanFrame): string {
  const secs: FrameSecJson[] = [];
  for (let i = 0; i < frame.sections.length; i++) {
    const s = frame.sections[i];
    const item: FrameSecJson = { title: s.title, points: s.points, depth: s.depth };
    secs.push(item);
  }
  const root: FrameRootJson = { sections: secs };
  return JSON.stringify(root);
}

/** 语气指令行（buildWritePrompt toneLine 入参） */
export function planToneLine(frame: PlanFrame): string {
  const voiceMap: Record<string, string> = {
    'senior': '像懂你的学长（懂我、慢慢来）',
    'coach': '像打气的教练（你可以的、往前冲）',
    'tool': '像干练的工具（直接给答案，少寒暄）'
  };
  return `${voiceMap[frame.voice] ?? voiceMap['senior']}；鼓励${frame.encourage === 'high' ? '多一点（多肯定）' : '克制（少打气）'}；类比${frame.analogy === 'more' ? '多用（类比先行）' : '少用（直述为主）'}`;
}

/**
 * ★ 0.290.0 渲染期钩子合成器（钩子隔离 Q6）：按 afterSection 节号在对应 ## 节末尾
 * 插 [[anchor:类型|文案]] 标记。②段写劈叉（多节/少节）不影响钩子结构——越界钳位到
 * 实际节数。无 ## 节（brief 直给）时全部钩子并到文末。纯函数，ohosTest 断言。
 */
export function mergeSectionHooks(hooks: PlanHook[], content: string): string {
  const lines = content.split('\n');
  // 扫 ## 节标题行（'## ' 开头且非 '###'；trim 容忍缩进）
  const secTitleLines: number[] = [];
  for (let i = 0; i < lines.length; i++) {
    const t = lines[i].trim();
    if (t.length >= 4 && t.substring(0, 3) === '## ' && t.charAt(3) !== '#') {
      secTitleLines.push(i);
    }
  }
  const secCount = secTitleLines.length;
  // 每节末尾行号（区间内最后一个非空行；全空区间=节标题行自身）
  const secEndLines: number[] = [];
  for (let s = 0; s < secCount; s++) {
    const from = secTitleLines[s] + 1;
    const to = s + 1 < secCount ? secTitleLines[s + 1] - 1 : lines.length - 1;
    let last = secTitleLines[s];
    for (let i = from; i <= to; i++) {
      if (lines[i].trim().length > 0) {
        last = i;
      }
    }
    secEndLines.push(last);
  }
  // 无节：文末最后一个非空行
  let docEnd = lines.length - 1;
  while (docEnd >= 0 && lines[docEnd].trim().length === 0) {
    docEnd--;
  }
  if (docEnd < 0) {
    return content; // 空内容原文返回
  }
  // 规范化钩子（type 四枚举/text 非空/afterSection 钳位/同位去重保留首条）
  const insertAt = new Map<number, PlanHook>();
  for (let i = 0; i < hooks.length; i++) {
    const h = hooks[i];
    if (!isPlanHookType(h.type) || h.text.trim().length === 0) {
      continue;
    }
    let sec = h.afterSection;
    if (sec < 1) {
      sec = 1;
    }
    if (secCount > 0) {
      if (sec > secCount) {
        sec = secCount;
      }
    } else {
      sec = 1; // 无节并到文末
    }
    if (!insertAt.has(sec)) {
      insertAt.set(sec, h);
    }
  }
  if (insertAt.size === 0) {
    return content;
  }
  // 排序倒插（行号不位移）；标记行前后补空行确保独占成块
  const secs = Array.from(insertAt.keys()).sort((a: number, b: number): number => a - b);
  const out = lines.slice();
  for (let i = secs.length - 1; i >= 0; i--) {
    const sec = secs[i];
    const h = insertAt.get(sec) as PlanHook;
    const endLine = secCount > 0 ? secEndLines[sec - 1] : docEnd;
    out.splice(endLine + 1, 0, '', `[[anchor:${h.type}|${h.text.trim()}]]`, '');
  }
  return out.join('\n');
}

// ★ 0.285.5：表格整表工具（用户需求「表格整体划选/整体拿走」——格子架构选区不跨组件，
//   放大弹窗提供整表入口）——buildTableMarkdown=复制整表（Markdown 源格式，贴回对话/
//   文档/AI 输入框保留表格结构）；单元格内半角竖线转全角防破坏列结构；数据行按表头列数
//   归一（parseTableRow 尾格容错同族防御——AI 偶发多格/少格行不炸格式）
export function buildTableMarkdown(header: string[], rows: string[][]): string {
  const esc = (s: string): string => s.replace(/\|/g, '｜');
  const line = (cells: string[]): string => '| ' + cells.map(esc).join(' | ') + ' |';
  const colCount = header.length;
  const sepCells: string[] = [];
  for (let i = 0; i < colCount; i++) {
    sepCells.push('---');
  }
  const out: string[] = [line(header), line(sepCells)];
  for (const row of rows) {
    const norm: string[] = [];
    for (let ci = 0; ci < colCount; ci++) {
      norm.push(ci < row.length ? row[ci] : '');
    }
    out.push(line(norm));
  }
  return out.join('\n');
}

// ★ 0.285.5：文本模式展示文本——行间 \n、格间 ' | '（无围栏竖线，阅读友好）；放大弹窗
//   「文本模式」整表一个 Text 渲染，可整体划词（翻译/入知识库/引用/复制/系统 Ctrl+C 全链路）
export function buildTablePlainText(header: string[], rows: string[][]): string {
  const esc = (s: string): string => s.replace(/\|/g, '｜');
  const line = (cells: string[]): string => cells.map(esc).join(' | ');
  const colCount = header.length;
  const out: string[] = [line(header)];
  for (const row of rows) {
    const norm: string[] = [];
    for (let ci = 0; ci < colCount; ci++) {
      norm.push(ci < row.length ? row[ci] : '');
    }
    out.push(line(norm));
  }
  return out.join('\n');
}
