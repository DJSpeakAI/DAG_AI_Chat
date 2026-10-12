// ============================================================
// ApkgUtil.ets — Anki .apkg 导入解析（知识库专用——用户拍板单词库不做）
// ============================================================
// ★ 0.227.0 新版 Anki（24.11+，meta format=3）支持：
//   collection.anki21b = ZSTD 压缩真数据（同包 anki2 只是「请更新」兼容空壳）→
//   ZstdUtil 解码 → SQLite 落盘 → relationalStore rootDir 只读打开；
//   deck 名走 decks 表（新 schema，层级分隔符 \x1f 归一为 '::'），
//   media 清单 = zstd+protobuf（条目顺序=zip 编号），媒体文件逐个 zstd。
// 0.208.0 旧格式链保留：uri → 拷沙箱 → zlib.unzipFile → anki2/anki21 →
//   col.decks JSON → notes/cards。字段映射（用户拍板）：正面=title、背=definition、
//   图片全提（base64）、tags 对接、[sound:] 丢弃、Anki 复习进度丢弃（新卡）。
// deck「A::B::C」→ 文件夹链（导入时 ensureFolderPath——重复导入幂等复用）。
// ============================================================

import { Context } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { relationalStore } from '@kit.ArkData';
import { buffer } from '@kit.ArkTS';
import { zstdDecompress, u8Copy, isZstd } from './ZstdUtil';

/** 解析产物：单张 Anki 卡（deckPath 为牌组层级链） */
export interface ApkgCard {
  title: string;
  definition: string;
  tags: string;
  images: string[];   // base64 data URI（背面字段图）
  titleImages: string[]; // ★ 0.210.0：标题图（正面字段图——Anki 图对图语义）
  deckPath: string;   // 「数学::群论」原始牌组名（'::' 层级）
}

export interface ApkgParseResult {
  cards: ApkgCard[];
  deckCounts: Record<string, number>; // 牌组名 → 卡数（预览统计）
  mediaCount: number;                 // 成功提取的图片总数
}

const APKG_TMP = 'apkg_tmp'; // cacheDir 下的工作目录名

function tmpDirOf(context: Context): string {
  return context.cacheDir + '/' + APKG_TMP;
}

/** uri → 沙箱文件（zlib 只认沙箱路径） */
function copyUriToSandbox(uri: string, destPath: string): void {
  const src = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
  try {
    const stat = fileIo.statSync(src.fd);
    const buf = new ArrayBuffer(stat.size);
    fileIo.readSync(src.fd, buf);
    const dst = fileIo.openSync(destPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(dst.fd, buf);
    } finally {
      fileIo.closeSync(dst);
    }
  } finally {
    fileIo.closeSync(src);
  }
}

/** 整文件读取 → Uint8Array（沙箱路径） */
function readFileBytes(path: string): Uint8Array {
  const f = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
  try {
    const stat = fileIo.statSync(f.fd);
    const buf = new ArrayBuffer(stat.size);
    fileIo.readSync(f.fd, buf);
    return new Uint8Array(buf);
  } finally {
    fileIo.closeSync(f);
  }
}

/** Anki 字段 HTML 清洗：[sound:] 剥离、<br>/<div>→换行、其余标签剥掉、常用实体解码 */
export function cleanAnkiHtml(html: string): string {
  let s = html;
  s = s.replace(/\[sound:[^\]]*\]/g, ''); // 音频标记（用户拍板：App 自带语音，不迁移）
  s = s.replace(/<br\s*\/?>/gi, '\n');
  s = s.replace(/<\/div>/gi, '\n');
  s = s.replace(/<div[^>]*>/gi, '');
  s = s.replace(/<[^>]+>/g, ''); // 其余标签全剥
  s = s.replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, '\'');
  s = s.replace(/\n{3,}/g, '\n\n'); // 多空行收敛
  return s.trim();
}

/** 提取字段里全部 <img src="..."> 文件名 */
function extractImgSrcs(html: string): string[] {
  const out: string[] = [];
  const re = /<img[^>]+src=["']([^"']+)["']/gi;
  let m = re.exec(html);
  while (m !== null) {
    out.push(m[1]);
    m = re.exec(html);
  }
  return out;
}

/** 纯 hex 字符串（Anki 媒体去重改名的 -sha1 尾巴） */
function isHexName(s: string): boolean {
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    const isHex = (c >= 48 && c <= 57) || (c >= 97 && c <= 102) || (c >= 65 && c <= 70);
    if (!isHex) {
      return false;
    }
  }
  return s.length > 0;
}

function containsCjk(s: string): boolean {
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c >= 0x4e00 && c <= 0x9fff) {
      return true;
    }
  }
  return false;
}

/**
 * ★ 0.227.0 纯图正面兜底标题：文件名去扩展名、剥 -sha1 尾巴，
 * 仅当剩余部分含中文/空格/括号（过滤 paste-、纯 hash 名）才可用，否则「图片卡」。
 */
function imgFallbackTitle(src: string): string {
  let name = src;
  const slash = name.lastIndexOf('/');
  if (slash >= 0) {
    name = name.substring(slash + 1);
  }
  const dot = name.lastIndexOf('.');
  if (dot > 0) {
    name = name.substring(0, dot);
  }
  const dash = name.lastIndexOf('-');
  if (dash > 0 && name.length - dash - 1 >= 8 && isHexName(name.substring(dash + 1))) {
    name = name.substring(0, dash);
  }
  if (name.length > 0 && (containsCjk(name) || name.indexOf(' ') >= 0 || name.indexOf('(') >= 0)) {
    return name;
  }
  return '图片卡';
}

/** ★ 0.227.0 新版 deck 层级分隔符 \x1f → '::'（ensureFolderPath 沿用旧约定） */
function normalizeDeckName(name: string): string {
  return name.split('\x1f').join('::');
}

function mimeOf(name: string): string {
  const lower = name.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.gif')) {
    return 'image/gif';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  if (lower.endsWith('.svg')) {
    return 'image/svg+xml';
  }
  return 'image/jpeg'; // jpg/jpeg 及未知默认
}

/** protobuf varint/字符串 读取器（新版 media 清单解析用） */
class ProtoReader {
  d: Uint8Array;
  p: number;

  constructor(d: Uint8Array, p: number) {
    this.d = d;
    this.p = p;
  }

  varint(): number {
    let v = 0;
    let shift = 0;
    let b = 0;
    do {
      b = this.d[this.p];
      this.p++;
      v |= (b & 0x7f) << shift;
      shift += 7;
    } while ((b & 0x80) !== 0);
    return v;
  }

  str(len: number): string {
    const tmp = new Uint8Array(len);
    tmp.set(this.d.subarray(this.p, this.p + len));
    return buffer.from(tmp.buffer).toString('utf-8');
  }
}

/**
 * ★ 0.227.0 新版 media 清单（zstd 解压后为 protobuf）：
 * 顶层 repeated field1 = 媒体条目，条目内 field1 = fname；
 * 条目顺序与 zip 内数字文件名编号一一对应（实测 255/255 SHA1 全匹配）。
 * 返回：真名 → 编号字符串（与旧版 JSON 语义一致）。
 */
function parseNewMediaManifest(bytes: Uint8Array): Map<string, string> {
  const map: Map<string, string> = new Map<string, string>();
  const r = new ProtoReader(bytes, 0);
  let idx = 0;
  while (r.p < bytes.length) {
    const tag = r.varint();
    const field = tag >> 3;
    const wt = tag & 7;
    if (wt === 2) {
      const len = r.varint();
      if (field === 1) {
        const entryEnd = r.p + len;
        const er = new ProtoReader(r.d, r.p);
        let fname = '';
        while (er.p < entryEnd) {
          const et = er.varint();
          const ef = et >> 3;
          const ewt = et & 7;
          if (ewt === 2) {
            const el = er.varint();
            if (ef === 1) {
              fname = er.str(el);
            }
            er.p += el;
          } else if (ewt === 0) {
            er.varint();
          } else {
            break;
          }
        }
        if (fname.length > 0) {
          map.set(fname, `${idx}`);
        }
        idx++;
        r.p = entryEnd;
      } else {
        r.p += len;
      }
    } else if (wt === 0) {
      r.varint();
    } else {
      break;
    }
  }
  return map;
}

/** 读 tmp 目录媒体文件 → base64 data URI（★ 0.227.0 新版媒体单独 zstd 压缩；失败静默跳过） */
function readMediaAsDataUri(dir: string, fileName: string): string {
  try {
    const p = dir + '/' + fileName;
    if (!fileIo.accessSync(p)) {
      return '';
    }
    const bytes = readFileBytes(p);
    const data = isZstd(bytes) ? u8Copy(zstdDecompress(bytes)) : bytes;
    return 'data:' + mimeOf(fileName) + ';base64,' + buffer.from(data.buffer).toString('base64');
  } catch (_e) {
    return '';
  }
}

/**
 * 解析 apkg 主函数。出错抛异常（调用方 catch 转 toast）。
 * ★ 0.227.0：优先 collection.anki21b（新版 zstd）；否则 anki2/anki21（旧版明文）。
 * notes 按 cards 表取首卡 deck（同 note 多卡不重复导）。
 */
export async function parseApkg(context: Context, uri: string): Promise<ApkgParseResult> {
  // 0. 清理旧工作目录 + 拷包进沙箱
  const dir = tmpDirOf(context);
  if (fileIo.accessSync(dir)) {
    fileIo.rmdirSync(dir);
  }
  fileIo.mkdirSync(dir);
  const pkgPath = context.cacheDir + '/import.apkg';
  copyUriToSandbox(uri, pkgPath);

  // 1. 解压（zip；新版 Anki 条目多为 Stored——媒体内容本身已是 zstd）
  const opt: zlib.Options = { level: zlib.CompressLevel.COMPRESS_LEVEL_NO_COMPRESSION };
  await zlib.unzipFile(pkgPath, dir, opt);

  // 2. 定位 SQLite：新版 anki21b（zstd）优先，旧版 anki2/anki21 兜底
  let dbName: string;
  if (fileIo.accessSync(dir + '/collection.anki21b')) {
    const raw = readFileBytes(dir + '/collection.anki21b');
    if (!isZstd(raw)) {
      throw new Error('anki21b 不是 zstd 格式（未知的 Anki 新版包结构）');
    }
    const decoded = u8Copy(zstdDecompress(raw));
    const magicOk = decoded.length >= 16 && decoded[0] === 0x53 && decoded[1] === 0x51
      && decoded[2] === 0x4c && decoded[3] === 0x69; // "SQLi"
    if (!magicOk) {
      throw new Error('anki21b 解码失败（内容不是 SQLite）');
    }
    dbName = 'decoded.anki2';
    const df = fileIo.openSync(dir + '/' + dbName, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(df.fd, decoded.buffer);
    } finally {
      fileIo.closeSync(df);
    }
  } else {
    dbName = fileIo.accessSync(dir + '/collection.anki2') ? 'collection.anki2' : 'collection.anki21';
    if (!fileIo.accessSync(dir + '/' + dbName)) {
      throw new Error('包内没有 collection 数据库（不是标准 Anki 导出包）');
    }
  }

  // 3. 只读打开（rootDir=工作目录，API18+；securityLevel 必填给 S1）
  const store = await relationalStore.getRdbStore(context, {
    name: dbName,
    securityLevel: relationalStore.SecurityLevel.S1,
    customDir: '',
    rootDir: dir
  });

  // 4. did → 牌组名：新版 schema 优先 decks 表（col.decks 为空串）→ 旧版回落 col JSON
  const deckNames: Map<number, string> = new Map<number, string>();
  let decksLoaded = false;
  try {
    const rsD = await store.querySql('SELECT id, name FROM decks');
    try {
      while (rsD.goToNextRow()) {
        const nm = rsD.getString(1);
        if (nm.length > 0) {
          deckNames.set(rsD.getLong(0), normalizeDeckName(nm));
        }
      }
      decksLoaded = deckNames.size > 0;
    } finally {
      rsD.close();
    }
  } catch (_e) {
    // 旧版无 decks 表 → 走 col JSON
  }
  if (!decksLoaded) {
    const rsCol = await store.querySql('SELECT decks FROM col');
    try {
      if (rsCol.goToNextRow()) {
        const decksRaw = rsCol.getString(0);
        try {
          const decks = JSON.parse(decksRaw) as Record<string, Record<string, Object>>;
          const keys = Object.keys(decks);
          for (let i = 0; i < keys.length; i++) {
            const d = decks[keys[i]];
            const nm = d['name'] as string;
            if (typeof nm === 'string' && nm.length > 0) {
              deckNames.set(Number(keys[i]), nm);
            }
          }
        } catch (_e) {
          // decks JSON 异常 → 全部归默认牌组
        }
      }
    } finally {
      rsCol.close();
    }
  }

  // 5. media 映射：真名 → 数字文件名（新版=zstd+protobuf 清单；旧版=JSON）
  let mediaFile: Map<string, string> = new Map<string, string>();
  if (fileIo.accessSync(dir + '/media')) {
    try {
      const mbytes = readFileBytes(dir + '/media');
      if (isZstd(mbytes)) {
        mediaFile = parseNewMediaManifest(u8Copy(zstdDecompress(mbytes)));
      } else {
        const map = JSON.parse(buffer.from(mbytes.buffer).toString('utf-8')) as Record<string, string>;
        const keys = Object.keys(map);
        for (let i = 0; i < keys.length; i++) {
          mediaFile.set(map[keys[i]], keys[i]); // 真名 → 编号文件
        }
      }
    } catch (_e) {
      // media 缺失/损坏 → 图片全跳过
    }
  }

  // 6. cards: nid → 首卡 did（同 note 多卡只导一次）
  const nidDeck: Map<number, number> = new Map<number, number>();
  const rsCards = await store.querySql('SELECT nid, did FROM cards');
  try {
    while (rsCards.goToNextRow()) {
      const nid = rsCards.getLong(0);
      if (!nidDeck.has(nid)) {
        nidDeck.set(nid, rsCards.getLong(1));
      }
    }
  } finally {
    rsCards.close();
  }

  // 7. notes 逐条解析
  const cards: ApkgCard[] = [];
  const deckCounts: Record<string, number> = {};
  let mediaCount = 0;
  const seenNid: Set<number> = new Set<number>();
  const rsNotes = await store.querySql('SELECT id, flds, tags FROM notes');
  try {
    while (rsNotes.goToNextRow()) {
      const nid = rsNotes.getLong(0);
      if (seenNid.has(nid)) {
        continue;
      }
      seenNid.add(nid);
      const flds = rsNotes.getString(1).split('\x1f'); // 字段分隔符 0x1f
      if (flds.length === 0) {
        continue;
      }
      const frontHtml = flds[0];
      let front = cleanAnkiHtml(frontHtml);
      if (front.length === 0) {
        // ★ 0.227.0 纯图正面兜底：无文本但有图 → 图文件名当标题（图仍走 titleImages 通道）
        const frontSrcs = extractImgSrcs(frontHtml);
        if (frontSrcs.length === 0) {
          continue; // 无正面不成卡
        }
        front = imgFallbackTitle(frontSrcs[0]);
      }
      // ★ 0.227.1：标题换行展平为空格——Anki 正面 <br>/<div>→\n 会让列表单行标题只显首行
      //   （用户实测「82…」根因）；definition 是多行区保换行
      front = front.replace(/\s*\n\s*/g, ' ').replace(/ {2,}/g, ' ').trim();
      // 背面 = 其余字段合并（用户拍板：正面=title、背=definition）
      const backs: string[] = [];
      for (let i = 1; i < flds.length; i++) {
        const b = cleanAnkiHtml(flds[i]);
        if (b.length > 0) {
          backs.push(b);
        }
      }
      // 图片：字段原始 HTML 里的 <img src>（清洗前提取——清洗会剥标签）
      // ★ 0.210.0 图对图分流：正面字段（i=0）的图 → titleImages（题面图）；背面字段的图 → images（内容图）
      const images: string[] = [];
      const titleImages: string[] = [];
      for (let i = 0; i < flds.length; i++) {
        const srcs = extractImgSrcs(flds[i]);
        for (let j = 0; j < srcs.length; j++) {
          const numFile = mediaFile.get(srcs[j]);
          if (numFile !== undefined) {
            const dataUri = readMediaAsDataUri(dir, numFile);
            if (dataUri.length > 0) {
              if (i === 0) {
                titleImages.push(dataUri);
              } else {
                images.push(dataUri);
              }
              mediaCount++;
            }
          }
        }
      }
      // tags：" tag1 tag2 " 空格分隔 → 逗号
      const tags = rsNotes.getString(2).trim().split(/\s+/).filter((t: string): boolean => t.length > 0).join(',');
      const did = nidDeck.get(nid);
      const deckName = did !== undefined ? (deckNames.get(did) ?? 'Anki') : 'Anki';
      const card: ApkgCard = { title: front, definition: backs.join('\n'), tags: tags, images: images, titleImages: titleImages, deckPath: deckName };
      cards.push(card);
      deckCounts[deckName] = (deckCounts[deckName] ?? 0) + 1;
    }
  } finally {
    rsNotes.close();
  }

  // 8. 收尾：关库再清工作目录（媒体/临时库不留沙箱）
  try {
    await store.close();
  } catch (_e) {
    // 关库失败不阻断清理
  }
  try {
    if (fileIo.accessSync(pkgPath)) {
      fileIo.unlinkSync(pkgPath);
    }
    if (fileIo.accessSync(dir)) {
      fileIo.rmdirSync(dir);
    }
  } catch (_e) {
    // 清理失败静默（cacheDir 系统会回收）
  }

  if (cards.length === 0) {
    throw new Error('没解析出卡片（notes 表为空或字段全空）');
  }
  const result: ApkgParseResult = { cards: cards, deckCounts: deckCounts, mediaCount: mediaCount };
  return result;
}
