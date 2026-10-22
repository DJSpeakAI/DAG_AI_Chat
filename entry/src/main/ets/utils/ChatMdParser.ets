// ============================================================
// ChatMdParser.ets — 对话页 Markdown 解析纯函数层（★ 拆分自 ChatPage.ets）
// ============================================================
// 消息内容 → MdSegment 段（文本/代码/表格）→ FoldItem 流（锚点/折叠后处理）。
// 纯函数零状态零 UI：parse 层做 LaTeX 数学符号转换（renderMathText），
// 保证显示/划词/复制三者偏移天然一致（0.151 铁律）。
// 消费方：ChatPage.richPlanFor（渲染计划入口，缓存失效逻辑在 ChatPage）。
import { renderMathText } from './MathRender';
import { MdBlock, FoldItem, parseBlockMd, stripAnchorMarks } from './MdInline';
import { MdSegment } from '../common/ChatPageTypes';

// ★ 0.121：Markdown 解析，拆分为普通文本/代码块/表格段
export function parseMarkdown(content: string): MdSegment[] {
  const segments: MdSegment[] = [];
  const lines: string[] = content.split('\n');
  let i = 0;
  let textBuffer: string[] = [];

  const flushText = () => {
    if (textBuffer.length > 0) {
      // ★ 0.151：parse 层做 LaTeX 数学符号转换，显示/划词/复制三者天然一致
      segments.push(new MdSegment(0, renderMathText(textBuffer.join('\n'))));
      textBuffer = [];
    }
  };

  while (i < lines.length) {
    const line = lines[i];
    const trimmed = line.trim();

    // 代码块：```lang ... ```
    if (trimmed.startsWith('```')) {
      flushText();
      const lang = trimmed.substring(3).trim();
      i++;
      const codeLines: string[] = [];
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        codeLines.push(lines[i]);
        i++;
      }
      segments.push(new MdSegment(1, codeLines.join('\n'), lang));
      i++; // 跳过闭合 ```
      continue;
    }

    // 表格：| header | ... | 后跟 |---|---|
    if (trimmed.startsWith('|') && trimmed.endsWith('|') &&
      i + 1 < lines.length && lines[i + 1].includes('---')) {
      flushText();
      const header = parseTableRow(line);
      i += 2; // 跳过表头和分隔行
      const rows: string[][] = [];
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        rows.push(parseTableRow(lines[i]));
        i++;
      }
      // ★ 0.151：表格单元格同样做数学符号转换（如 |\neq| → |≠|）
      const mathHeader: string[] = header.map((c: string) => renderMathText(c));
      const mathRows: string[][] = rows.map((r: string[]) => r.map((c: string) => renderMathText(c)));
      // ★ 0.191.0：行格数对齐表头——流式中间态/AI 输出瑕疵导致的短行补空格、超长行截断，
      //   列边界与表头严格对齐永不错位（配合 parseTableRow 尾格容错，双保险）
      const colCount = mathHeader.length;
      for (let ri = 0; ri < mathRows.length; ri++) {
        const r = mathRows[ri];
        while (r.length < colCount) {
          r.push('');
        }
        if (r.length > colCount) {
          mathRows[ri] = r.slice(0, colCount);
        }
      }
      segments.push(new MdSegment(2, '', '', mathHeader, mathRows));
      continue;
    }

    // 普通文本
    textBuffer.push(line);
    i++;
  }
  flushText();
  return segments;
}

// ★ 0.121：解析表格行 | a | b | → [a, b]
// ★ 0.191.0：流式中间态末行可能不以 | 结尾（AI 正在写入）——尾格也要收进，
//   原逻辑丢尾格 → 该行格数比表头少 → 渲染时列边界左移错乱（用户实测 5×5 表末行总是错乱的根因）
export function parseTableRow(line: string): string[] {
  const parts = line.split('|');
  const result: string[] = [];
  const endJ = line.trim().endsWith('|') ? parts.length - 1 : parts.length;
  for (let j = 1; j < endJ; j++) {
    result.push(parts[j].trim());
  }
  return result;
}

// ★ 0.231.0：普通文本段 → 块级富文本（# 标题 / - 列表 / 1. 列表 / > 引用 / --- 分割线）
export function parseRichBlocks(content: string): MdBlock[] {
  return parseBlockMd(content.split('\n'));
}

// ★ 0.234.0：消息段落 → FoldItem 流（代码/表格段的后处理防线：内含锚点标记时剔除标记留文案——任务书 §3.4 双防线）
export function buildFoldItems(segs: MdSegment[]): FoldItem[] {
  const items: FoldItem[] = [];
  for (let si = 0; si < segs.length; si++) {
    const seg = segs[si];
    if (seg.type === 0) {
      const blocks = parseRichBlocks(seg.content);
      for (let bi = 0; bi < blocks.length; bi++) {
        const it = new FoldItem();
        it.kind = blocks[bi].kind === 'anchor' ? 'anchor' : 'text';
        it.block = blocks[bi];
        it.segIdx = si;
        items.push(it);
      }
    } else if (seg.type === 1) {
      const it = new FoldItem();
      it.kind = 'code';
      it.code = seg.content.indexOf('[[anchor:') >= 0 ? stripAnchorMarks(seg.content, true) : seg.content;
      it.lang = seg.lang;
      it.segIdx = si;
      items.push(it);
    } else {
      const it = new FoldItem();
      it.kind = 'table';
      it.header = seg.header.map((c: string): string => c.indexOf('[[anchor:') >= 0 ? stripAnchorMarks(c, true) : c);
      it.rows = seg.rows.map((r: string[]): string[] => r.map((c: string): string => c.indexOf('[[anchor:') >= 0 ? stripAnchorMarks(c, true) : c));
      it.segIdx = si;
      items.push(it);
    }
  }
  return items;
}
