// ============================================================
// DocParseUtil.ets — ★ 0.291.2 文档加载（+号混选：word/excel/txt/md/pdf 交 AI 分析）
// ============================================================
// 架构（方案审批稿 docs/0.165+/0.291.0 定稿）：
//   格式路由——txt/md 本地直读；xlsx 本地 ExcelJS 转 Markdown 表格（项目已有依赖）；
//   docx/pdf 走腾讯云·多模态文档解析（异步 Submit + FileBase64 直传 ≤6MB → 轮询
//   Describe → 结果 ZIP 下载解压 → 取 .md）。
//   注入复刻 0.286 AI 读网页先例：system 一次性副本，零 Schema/持久化/云同步改动；
//   解析失败不阻断发送（失败文档零扣费）；页费嫁接见 ChatModel.docPageTokens。
//   通用地基：未来「批量上传 PDF 制作知识卡片」复用本件（用户前瞻拍板）。
// 不确定点（官方 API Explorer 未逐字核对，错码走友好报错路径不崩）：
//   FileType 枚举值 / Describe 响应字段名——全部多键防御式试探，实测后收敛注释。
// ============================================================

import { fileIo } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { zlib } from '@kit.BasicServicesKit';
import ExcelJS from '@archermind/exceljs';
import { buildTc3Headers, TC_OCR_HOST } from './Tc3Signer';
import { ContentFilter } from './ContentFilter';

// ---------- 常量（阈值均可调） ----------
export const DOC_MAX_BYTES: number = 6 * 1024 * 1024; // 云端文档安全线（官方 8M 未明示含否 base64 膨胀，保守 6M）
export const DOC_CONFIRM_BYTES: number = 2 * 1024 * 1024; // 超此线发送前强确认（页费可能高）
export const DOC_LOCAL_MAX_BYTES: number = 10 * 1024 * 1024; // 本地解析上限（txt/md/xlsx 防爆内存）
export const DOC_MAX_CHARS: number = 30000; // 单文档字符钳制
export const DOC_TOTAL_MAX_CHARS: number = 60000; // 合计字符钳制
const POLL_INTERVAL_MS: number = 2500;
const POLL_TIMEOUT_MS: number = 180000; // 解析总超时 3 分钟（对齐提炼弹窗业务超时先例）
const HTTP_CONNECT_MS: number = 15000;
const HTTP_READ_MS: number = 60000;
const XLSX_MAX_ROWS: number = 3000;
const XLSX_MAX_COLS: number = 20;

const IMG_EXTS: string[] = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'];
const CLOUD_EXTS: string[] = ['pdf', 'docx', 'doc']; // 走腾讯云
const LOCAL_EXTS: string[] = ['txt', 'md', 'xlsx']; // 本地解析
// +号混选选择器后缀过滤（图片+文档全集）
export const ATTACH_SUFFIX_FILTERS: string[] = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp',
  '.txt', '.md', '.pdf', '.docx', '.doc', '.xlsx'];

// 腾讯 FileType 枚举（防御式：实测错码改此表）
function tcFileTypeOf(ext: string): number {
  if (ext === 'pdf') {
    return 0; // PDF
  }
  return 1; // DOC（doc/docx）
}

// ---------- 数据结构（plain class——@Local 数组重建驱动刷新，同 pendingImages 模式） ----------
export class PendingDoc {
  name: string; // 展示文件名
  ext: string; // 小写后缀
  size: number; // 字节
  uri: string; // picker uri

  constructor(name: string, ext: string, size: number, uri: string) {
    this.name = name;
    this.ext = ext;
    this.size = size;
    this.uri = uri;
  }
}

export class DocParseResult {
  name: string;
  ok: boolean = false;
  content: string = ''; // 解析文本（ok=true 时非空）
  pages: number = 0; // 云端解析页数（页费嫁接用；本地解析=0）
  failReason: string = ''; // 失败中文原因（ok=false 时非空）
  truncated: boolean = false; // ★ 0.291.3：单文档超 3 万字被截断（计费透明——页费仍按全文页数计，用户侧 toast 提示）

  constructor(name: string) {
    this.name = name;
  }
}

// ---------- 后缀工具 ----------
export function docExtOf(name: string): string {
  const i = name.lastIndexOf('.');
  return i >= 0 ? name.substring(i + 1).toLowerCase() : '';
}

export function isImageExt(ext: string): boolean {
  return IMG_EXTS.indexOf(ext) >= 0;
}

export function isDocExt(ext: string): boolean {
  return LOCAL_EXTS.indexOf(ext) >= 0 || CLOUD_EXTS.indexOf(ext) >= 0;
}

export function needsCloudParse(ext: string): boolean {
  return CLOUD_EXTS.indexOf(ext) >= 0;
}

export function fmtDocSize(bytes: number): string {
  if (bytes >= 1024 * 1024) {
    return `${(bytes / 1024 / 1024).toFixed(1)}MB`;
  }
  return `${Math.max(1, Math.round(bytes / 1024))}KB`;
}

// ---------- 主入口：发送时解析一批待发文档 ----------
// 逐个解析（云端限 5 页并发，逐个最稳）；单个失败不阻断其余（失败项 failReason 进注入块提示模型）
export async function parseDocsForSend(docs: PendingDoc[], secretId: string, secretKey: string,
  cacheDir: string): Promise<DocParseResult[]> {
  const results: DocParseResult[] = [];
  for (let i = 0; i < docs.length; i++) {
    const d = docs[i];
    const r = new DocParseResult(d.name);
    try {
      if (LOCAL_EXTS.indexOf(d.ext) >= 0) {
        if (d.size > DOC_LOCAL_MAX_BYTES) {
          r.failReason = `文件超过 10MB，本地解析已跳过`;
        } else         if (d.ext === 'xlsx') {
          const rawX = await parseXlsxLocal(d.uri);
          r.content = clampDocText(rawX);
          r.truncated = rawX.length > DOC_MAX_CHARS; // ★ 0.291.3
          r.ok = r.content.length > 0;
          if (!r.ok) {
            r.failReason = '表格内容为空';
          }
        } else {
          const rawT = await parseTextLocal(d.uri);
          r.content = clampDocText(rawT);
          r.truncated = rawT.length > DOC_MAX_CHARS; // ★ 0.291.3
          r.ok = r.content.length > 0;
          if (!r.ok) {
            r.failReason = '文件内容为空';
          }
        }
      } else if (CLOUD_EXTS.indexOf(d.ext) >= 0) {
        if (d.size > DOC_MAX_BYTES) {
          r.failReason = '文件超过 6MB，请拆分后再试';
        } else if (secretId.length === 0 || secretKey.length === 0) {
          r.failReason = '未配置文档解析服务（设置 → API 配置）';
        } else {
          const cloud = await parseViaTencent(d, secretId, secretKey, cacheDir);
          r.content = cloud.content;
          r.pages = cloud.pages;
          r.ok = cloud.ok;
          r.failReason = cloud.failReason;
        }
      } else {
        r.failReason = '暂不支持该格式';
      }
      // 敏感词预过滤（WebFetch 同款：命中=丢弃该文档块，不阻断消息）
      if (r.ok && ContentFilter.checkInput(r.content) !== null) {
        r.ok = false;
        r.content = '';
        r.failReason = '内容未通过本地安全检查，已跳过';
      }
    } catch (_e) {
      r.ok = false;
      r.content = '';
      if (r.failReason.length === 0) {
        r.failReason = '解析过程出现异常';
      }
    }
    results.push(r);
  }
  return results;
}

function clampDocText(text: string): string {
  if (text.length > DOC_MAX_CHARS) {
    return `${text.substring(0, DOC_MAX_CHARS)}\n（文档内容过长，已截断）`;
  }
  return text;
}

// ---------- 本地：txt/md ----------
async function parseTextLocal(uri: string): Promise<string> {
  const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
  try {
    const stat = fileIo.statSync(file.fd);
    const ab = new ArrayBuffer(stat.size);
    fileIo.readSync(file.fd, ab);
    return buffer.from(ab).toString('utf-8');
  } finally {
    fileIo.closeSync(file);
  }
}

// ---------- 本地：xlsx → Markdown 表格（全量读取——与 ImportUtil.readXlsxRows 的
// 卡片导入语义不同，本函数保全部单元格/全部工作表） ----------
async function parseXlsxLocal(uri: string): Promise<string> {
  const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
  let buf: ArrayBuffer;
  try {
    const stat = fileIo.statSync(file.fd);
    buf = new ArrayBuffer(stat.size);
    fileIo.readSync(file.fd, buf);
  } finally {
    fileIo.closeSync(file);
  }
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(buf);
  const parts: string[] = [];
  for (let s = 0; s < wb.worksheets.length; s++) {
    const sheet = wb.worksheets[s];
    if (sheet.rowCount === 0) {
      continue;
    }
    if (wb.worksheets.length > 1) {
      parts.push(`## 工作表：${sheet.name}`);
    }
    const rowsOut: string[] = [];
    const colCap = Math.min(sheet.columnCount, XLSX_MAX_COLS);
    const rowCap = Math.min(sheet.rowCount, XLSX_MAX_ROWS);
    for (let r = 1; r <= rowCap; r++) {
      const vals = sheet.getRow(r).values as string[];
      const cells: string[] = [];
      for (let cIdx = 1; cIdx <= colCap; cIdx++) {
        const v = vals[cIdx];
        cells.push(`${v ?? ''}`.replace(/\|/g, '/').replace(/\n/g, ' '));
      }
      rowsOut.push(`| ${cells.join(' | ')} |`);
      if (r === 1) {
        const sep: string[] = [];
        for (let cIdx = 0; cIdx < colCap; cIdx++) {
          sep.push('---');
        }
        rowsOut.push(`| ${sep.join(' | ')} |`);
      }
    }
    if (sheet.rowCount > XLSX_MAX_ROWS) {
      rowsOut.push(`（表格过长，仅保留前 ${XLSX_MAX_ROWS} 行）`);
    }
    parts.push(rowsOut.join('\n'));
  }
  return parts.join('\n\n');
}

// ---------- 腾讯云链路 ----------
interface TcResponse {
  errCode: string; // 空=成功
  errMsg: string;
  taskId: string; // Submit 成功的 TaskId
  done: boolean; // Describe：任务终态
  success: boolean; // Describe：终态成功
  downloadUrl: string;
  pages: number;
}

function tcErrToChinese(code: string, msg: string): string {
  if (code.indexOf('AuthFailure') >= 0 || code.indexOf('Unauthorized') >= 0) {
    return '密钥无效，请检查设置中的文档解析服务配置';
  }
  if (code.indexOf('TooLargeFile') >= 0) {
    return '文件超出解析服务大小限制';
  }
  if (code.indexOf('LimitExceeded') >= 0) {
    return '解析服务繁忙或超限，请稍后再试';
  }
  if (code.indexOf('FailedOperation') >= 0) {
    return `解析失败：${msg.length > 0 ? msg : code}`;
  }
  return `解析服务异常（${code}）`;
}

// 腾讯 API POST（JSON；TC3 签名头；返回原始响应文本）
async function tcPost(action: string, payload: string, secretId: string, secretKey: string): Promise<string> {
  const head = buildTc3Headers(action, payload, secretId, secretKey, Math.floor(Date.now() / 1000));
  const client = http.createHttp();
  try {
    const resp = await client.request(`https://${TC_OCR_HOST}/`, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': head.contentType,
        'Authorization': head.authorization,
        'X-TC-Action': head.action,
        'X-TC-Timestamp': head.timestamp,
        'X-TC-Version': head.version
      },
      extraData: payload,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: HTTP_CONNECT_MS,
      readTimeout: HTTP_READ_MS
    } as http.HttpRequestOptions);
    if (resp.responseCode !== 200 || typeof resp.result !== 'string') {
      throw new Error(`HTTP ${resp.responseCode}`);
    }
    return resp.result;
  } finally {
    client.destroy();
  }
}

// 防御式解析腾讯响应（字段名多键试探——官方文档字段未逐字核对，错名走 errCode 路径）
function parseTcJson(text: string): TcResponse {
  const out: TcResponse = { errCode: '', errMsg: '', taskId: '', done: false, success: false, downloadUrl: '', pages: 0 };
  try {
    const root = JSON.parse(text) as Record<string, Object>;
    const resp = (root['Response'] ?? root) as Record<string, Object>;
    const err = resp['Error'] as Record<string, Object> | undefined;
    if (err !== undefined && err !== null) {
      out.errCode = String(err['Code'] ?? 'UnknownError');
      out.errMsg = String(err['Message'] ?? '');
      return out;
    }
    // Submit：TaskId
    const tid = resp['TaskId'] ?? resp['JobId'];
    if (tid !== undefined && tid !== null && String(tid).length > 0) {
      out.taskId = String(tid);
      return out;
    }
    // Describe：Status + 结果数组
    const status = String(resp['Status'] ?? resp['StatusCode'] ?? '').toLowerCase();
    const pagesNum = Number(resp['TotalPageNumber'] ?? resp['TotalPage'] ?? resp['PageCount'] ?? 0);
    out.pages = Number.isFinite(pagesNum) && pagesNum > 0 ? Math.round(pagesNum) : 0;
    if (status.indexOf('success') >= 0 || status === '2' || status === '3') {
      out.done = true;
      out.success = true;
    } else if (status.indexOf('fail') >= 0 || status.indexOf('error') >= 0) {
      out.done = true;
      out.success = false;
      out.errMsg = String(resp['Message'] ?? '解析失败');
      return out;
    }
    // 结果下载链接：Results 数组内多键试探
    const arr = resp['Results'] ?? resp['Datas'] ?? resp['ResultInfos'];
    if (arr !== undefined && arr !== null && Array.isArray(arr)) {
      const items = arr as Object[];
      for (let i = 0; i < items.length; i++) {
        const it = items[i] as Record<string, Object>;
        const url = it['DownloadUrl'] ?? it['FileUrl'] ?? it['Url'];
        if (url !== undefined && url !== null && String(url).length > 0) {
          out.downloadUrl = String(url);
          break;
        }
      }
    }
    return out;
  } catch (_e) {
    out.errCode = 'ParseResponseError';
    out.errMsg = '响应解析失败';
    return out;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

// 云端主链：读文件→base64→Submit→轮询 Describe→下载 ZIP→解压→读 .md
async function parseViaTencent(d: PendingDoc, secretId: string, secretKey: string, cacheDir: string): Promise<DocParseResult> {
  const r = new DocParseResult(d.name);
  // 1. 读文件 base64
  let b64 = '';
  const file = fileIo.openSync(d.uri, fileIo.OpenMode.READ_ONLY);
  try {
    const stat = fileIo.statSync(file.fd);
    const ab = new ArrayBuffer(stat.size);
    fileIo.readSync(file.fd, ab);
    b64 = buffer.from(ab).toString('base64');
  } finally {
    fileIo.closeSync(file);
  }
  // 2. Submit（不传 ResultType——默认全出，解压后取 .md；少一个字段不确定点）
  const body: Record<string, Object> = {};
  body['FileType'] = tcFileTypeOf(d.ext);
  body['FileBase64'] = b64;
  const submitResp = parseTcJson(await tcPost('SubmitMultimodalDocParseJob', JSON.stringify(body), secretId, secretKey));
  if (submitResp.errCode.length > 0) {
    r.failReason = tcErrToChinese(submitResp.errCode, submitResp.errMsg);
    return r;
  }
  if (submitResp.taskId.length === 0) {
    r.failReason = '解析服务未返回任务号';
    return r;
  }
  // 3. 轮询 Describe（3 分钟总超时）
  const deadline = Date.now() + POLL_TIMEOUT_MS;
  let final: TcResponse | null = null;
  while (Date.now() < deadline) {
    await sleep(POLL_INTERVAL_MS);
    const qBody: Record<string, Object> = {};
    qBody['TaskId'] = submitResp.taskId;
    const dr = parseTcJson(await tcPost('DescribeMultimodalDocParseJob', JSON.stringify(qBody), secretId, secretKey));
    if (dr.errCode.length > 0) {
      r.failReason = tcErrToChinese(dr.errCode, dr.errMsg);
      return r;
    }
    if (dr.done) {
      final = dr;
      break;
    }
  }
  if (final === null) {
    r.failReason = '解析超时（3 分钟），请稍后重试';
    return r;
  }
  if (!final.success || final.downloadUrl.length === 0) {
    r.failReason = final.errMsg.length > 0 ? final.errMsg : '解析失败';
    return r;
  }
  r.pages = final.pages;
  // 4. 下载 ZIP（30 分钟有效——立即下载）→ 解压 → 取 .md
  const md = await downloadAndExtractMd(final.downloadUrl, cacheDir);
  if (md.length === 0) {
    r.failReason = '结果包中未找到文本内容';
    return r;
  }
  r.content = clampDocText(md);
  r.truncated = md.length > DOC_MAX_CHARS; // ★ 0.291.3：页费按全文页数计但内容截断——用户侧 toast 透明化
  r.ok = true;
  return r;
}

async function downloadAndExtractMd(url: string, cacheDir: string): Promise<string> {
  const client = http.createHttp();
  let zipBytes: ArrayBuffer | null = null;
  try {
    const resp = await client.request(url, {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: HTTP_CONNECT_MS,
      readTimeout: HTTP_READ_MS
    } as http.HttpRequestOptions);
    if (resp.responseCode === 200 && resp.result instanceof ArrayBuffer) {
      zipBytes = resp.result;
    }
  } finally {
    client.destroy();
  }
  if (zipBytes === null || zipBytes.byteLength === 0) {
    return '';
  }
  const stamp = Date.now();
  const zipPath = `${cacheDir}/docparse_${stamp}.zip`;
  const outDir = `${cacheDir}/docparse_${stamp}`;
  const file = fileIo.openSync(zipPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  try {
    fileIo.writeSync(file.fd, zipBytes);
  } finally {
    fileIo.closeSync(file);
  }
  try {
    await zlib.decompressFile(zipPath, outDir);
    return collectMdFiles(outDir);
  } catch (_e) {
    return '';
  } finally {
    // 清理临时产物（zip+解压目录，不给沙箱留垃圾）
    try {
      fileIo.unlinkSync(zipPath);
    } catch (_e1) {
    }
    try {
      fileIo.rmdirSync(outDir);
    } catch (_e2) {
    }
  }
}

// 递归收集解压目录内全部 .md 文本（结果包可能含子目录；一个任务一份内容，多文件拼接）
function collectMdFiles(dir: string): string {
  const parts: string[] = [];
  const walk = (d: string): void => {
    const names = fileIo.listFileSync(d);
    for (let i = 0; i < names.length; i++) {
      const full = `${d}/${names[i]}`;
      let isDir = false;
      try {
        isDir = fileIo.statSync(full).isDirectory();
      } catch (_e) {
        continue;
      }
      if (isDir) {
        walk(full);
      } else if (docExtOf(names[i]) === 'md') {
        try {
          const f = fileIo.openSync(full, fileIo.OpenMode.READ_ONLY);
          try {
            const st = fileIo.statSync(f.fd);
            const ab = new ArrayBuffer(st.size);
            fileIo.readSync(f.fd, ab);
            parts.push(buffer.from(ab).toString('utf-8'));
          } finally {
            fileIo.closeSync(f);
          }
        } catch (_e2) {
        }
      }
    }
  };
  walk(dir);
  return parts.join('\n\n');
}

// ---------- 注入块（0.286 读网页同款拼装风格） ----------
export function buildDocContextBlock(results: DocParseResult[]): string {
  if (results.length === 0) {
    return '';
  }
  const parts: string[] = [];
  parts.push('【用户随消息附带了以下文档，应用已解析出文本内容，请结合文档内容回答；解析失败的文档不要凭空编造内容】');
  let budget = DOC_TOTAL_MAX_CHARS;
  for (let i = 0; i < results.length; i++) {
    const it = results[i];
    const pageLabel = it.pages > 0 ? `，${it.pages} 页` : '';
    parts.push(`—— 文档 ${i + 1}（${it.name}${pageLabel}）——`);
    if (it.ok) {
      if (it.content.length > budget) {
        if (budget > 200) {
          parts.push(`${it.content.substring(0, budget)}\n（文档总内容过长，此处截断）`);
        }
        budget = 0;
      } else {
        parts.push(it.content);
        budget -= it.content.length;
      }
    } else {
      parts.push(`（解析失败：${it.failReason}）`);
    }
  }
  parts.push('【文档内容结束】');
  return parts.join('\n');
}

// 待发文档汇总行（确认弹窗/气泡提示用）
export function docListLabel(docs: PendingDoc[]): string {
  const names: string[] = [];
  for (let i = 0; i < docs.length; i++) {
    names.push(docs[i].name);
  }
  return names.join('、');
}
