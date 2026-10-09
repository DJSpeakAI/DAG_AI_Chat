// ============================================================
// ImportUtil.ets — ★ 0.207.0 anything 导入体系：文件读取与解析（CSV/TXT）
// ============================================================
// 职责：picker 选中的文件 → 文本（UTF-8 优先 GBK 回落）→ 结构化卡片草稿数组
// 格式约定（0.207.0 第一批）：
//   TXT：每行一卡，分隔符 Tab 或 |——`标题|背面|标签(可选)`
//   CSV：每行一卡，逗号分隔（引号转义支持）——`标题,背面,标签(可选)`
//   .xls 老格式不支持——调用方提示「请用 Excel 另存为 .xlsx」（0.207.1 支持 xlsx）
// 导出：当前文件夹卡片 → CSV（UTF-8 BOM——Excel 直开不乱码）
// apkg（Anki）在 0.208.0 单独模块。
// ============================================================

import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { KnowledgeCard, getCardImages } from '../common/KnowledgeModel';
import ExcelJS from '@archermind/exceljs'; // ★ 0.207.1：xlsx 读取（ExcelJS 4.4 适配版）

/** 导入草稿行（解析产物——未入库的纯数据） */
export interface ImportRow {
  title: string;
  definition: string;
  tags: string;
}

/** 读文件全文（UTF-8 优先；失败回落 GBK——Excel 另存的中文 CSV 常是 GBK） */
export function readTextFile(uri: string): string {
  const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
  try {
    const stat = fileIo.statSync(file.fd);
    const buf = new ArrayBuffer(stat.size);
    fileIo.readSync(file.fd, buf);
    const bytes = new Uint8Array(buf);
    // BOM 剥除（UTF-8 BOM: EF BB BF）
    const start = bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF ? 3 : 0;
    try {
      const dec = util.TextDecoder.create('utf-8');
      return dec.decodeWithStream(bytes.slice(start));
    } catch (_e) {
      // UTF-8 解码失败（乱码容错）→ GBK 回落
      const dec2 = util.TextDecoder.create('gbk');
      return dec2.decodeWithStream(bytes);
    }
  } finally {
    fileIo.closeSync(file);
  }
}

/** 单行 CSV 解析（引号内逗号支持；"" 转义为 "；不支持引号内换行——异常行由调用方丢弃） */
function parseCsvLine(line: string): string[] {
  const out: string[] = [];
  let cur = '';
  let inQuote = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (inQuote) {
      if (ch === '"') {
        if (i + 1 < line.length && line[i + 1] === '"') {
          cur += '"';
          i++;
        } else {
          inQuote = false;
        }
      } else {
        cur += ch;
      }
    } else {
      if (ch === '"') {
        inQuote = true;
      } else if (ch === ',') {
        out.push(cur);
        cur = '';
      } else {
        cur += ch;
      }
    }
  }
  out.push(cur);
  return out.map((s: string): string => s.trim());
}

/**
 * 解析文本为卡片草稿行。format: 'txt' | 'csv'。
 * 规则：至少 2 列（标题+背面）才成卡；第 3 列（可选）= 标签；
 *   空行/单列行跳过；首行若是「标题/正面,背面,标签」类表头自动识别丢弃（启发式：含 标题|正面|title|front|word 且无第 2 列实义）。
 */
export function parseTextToRows(text: string, format: string): ImportRow[] {
  const rows: ImportRow[] = [];
  const lines = text.split(/\r\n|\n|\r/);
  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i].trim();
    if (raw.length === 0) {
      continue;
    }
    let cols: string[];
    if (format === 'csv') {
      cols = parseCsvLine(raw);
    } else {
      // TXT：Tab 优先，无 Tab 再试 |
      if (raw.indexOf('\t') >= 0) {
        cols = raw.split('\t');
      } else {
        cols = raw.split('|');
      }
    }
    cols = cols.map((s: string): string => s.trim());
    if (cols.length < 2 || cols[0].length === 0 || cols[1].length === 0) {
      continue; // 单列/空列不成卡
    }
    // 表头识别：第 2 列是典型表头词且无实义内容
    if (i === 0 && rows.length === 0) {
      const h = cols[1].toLowerCase();
      if (h === '背面' || h === 'back' || h === 'definition' || h === '答案' || h === 'answer') {
        continue;
    }
    }
    rows.push({ title: cols[0], definition: cols[1], tags: cols.length > 2 ? cols[2] : '' });
  }
  return rows;
}

/** CSV 字段转义（含逗号/引号/换行时加引号包裹） */
function csvEscape(s: string): string {
  if (s.indexOf(',') >= 0 || s.indexOf('"') >= 0 || s.indexOf('\n') >= 0) {
    return '"' + s.replace(/"/g, '""') + '"';
  }
  return s;
}

/**
 * 卡片数组 → CSV 文本（UTF-8 BOM；列：标题,背面,标签）。
 * scopeName 用于首行注释（导出来源），空则省略。
 */
export function cardsToCsv(cards: KnowledgeCard[], scopeName: string): string {
  const lines: string[] = ['标题,背面,标签'];
  for (let i = 0; i < cards.length; i++) {
    const c = cards[i];
    lines.push(csvEscape(c.title) + ',' + csvEscape(c.definition) + ',' + csvEscape(c.tags));
  }
  const body = lines.join('\r\n');
  const head = scopeName.length > 0 ? '# DAGAI 知识库导出：' + scopeName + '（' + cards.length + ' 张）\r\n' : '';
  return '\uFEFF' + head + body;
}

/** 预览摘要（导入确认弹窗用）：前 n 条 + 总数 */
export function previewRows(rows: ImportRow[], n: number): ImportRow[] {
  return rows.slice(0, n);
}

/** 草稿行卡片数（顺带把 getCardImages 引用留��——导出场景外部用） */
export function countWithImages(cards: KnowledgeCard[]): number {
  let n = 0;
  for (let i = 0; i < cards.length; i++) {
    if (getCardImages(cards[i]).length > 0) {
      n++;
    }
  }
  return n;
}

/**
 * ★ 0.207.1：读 xlsx 首个工作表 → 卡片草稿行。
 * 列约定同 CSV：A=标题 B=背面 C=标签(可选)；空行/单列跳过；首行表头启发式丢弃。
 * ExcelJS 适配版 row.values 为 1-based 数组——取前 3 列。
 */
export async function readXlsxRows(uri: string): Promise<ImportRow[]> {
  const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
  try {
    const stat = fileIo.statSync(file.fd);
    const buf = new ArrayBuffer(stat.size);
    fileIo.readSync(file.fd, buf);
    const wb = new ExcelJS.Workbook();
    await wb.xlsx.load(buf);
    if (wb.worksheets.length === 0) {
      return [];
    }
    const sheet = wb.worksheets[0];
    const rows: ImportRow[] = [];
    for (let r = 1; r <= sheet.rowCount; r++) {
      const vals = sheet.getRow(r).values as string[];
      const c0 = `${vals[1] ?? ''}`.trim();
      const c1 = `${vals[2] ?? ''}`.trim();
      const c2 = `${vals[3] ?? ''}`.trim();
      if (c0.length === 0 || c1.length === 0) {
        continue;
      }
      if (r === 1) {
        const h = c1.toLowerCase();
        if (h === '背面' || h === 'back' || h === 'definition' || h === '答案' || h === 'answer') {
          continue;
        }
      }
      const row: ImportRow = { title: c0, definition: c1, tags: c2 };
      rows.push(row);
    }
    return rows;
  } finally {
    fileIo.closeSync(file);
  }
}
