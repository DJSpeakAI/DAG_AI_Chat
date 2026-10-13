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

// 块级单元（kind：p 段落 / h1~h6 标题 / li 无序列表 / oli 有序列表 / quote 引用 / hr 分割线）
export class MdBlock {
  kind: string = 'p';
  order: string = ''; // oli 序号文本（如 '3.'）
  depth: number = 0; // 列表缩进层级（2 空格一级）
  lines: string[] = []; // 该块的原始行（p/quote 可多行；单行块=1 行）
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
