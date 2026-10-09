// ============================================================
// ApkgUtil.ets — ★ 0.208.0 Anki .apkg 导入解析（知识库专用——用户拍板单词库不做）
// ============================================================
// apkg 结构（zip）：collection.anki2（或 .anki21 新 schema）SQLite +
//   media（{"0":"dog.png"} 编号→真名映射）+ 数字命名的媒体文件
// 解析链：picker uri → 拷沙箱 → zlib.unzipFile → relationalStore.getRdbStore
//   **rootDir**（API18+ 只读开任意路径 SQLite）→ notes/cards/col 三表 → 卡片草稿
// 字段映射（用户拍板）：正面=title、背面=definition、图片全提（base64）、
//   tags 对接、[sound:] 音频丢弃（App 自带本地语音）、Anki 复习进度丢弃（新卡）
// deck「A::B::C」→ 文件夹链（导入时 ensureFolderPath——重复导入幂等复用）
// ============================================================

import { Context } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { relationalStore } from '@kit.ArkData';
import { buffer } from '@kit.ArkTS';

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

/** 读 tmp 目录媒体文件 → base64 data URI（失败静默跳过） */
function readMediaAsDataUri(dir: string, fileName: string): string {
  try {
    const p = dir + '/' + fileName;
    if (!fileIo.accessSync(p)) {
      return '';
    }
    const f = fileIo.openSync(p, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = fileIo.statSync(f.fd);
      const buf = new ArrayBuffer(stat.size);
      fileIo.readSync(f.fd, buf);
      return 'data:' + mimeOf(fileName) + ';base64,' + buffer.from(buf).toString('base64');
    } finally {
      fileIo.closeSync(f);
    }
  } catch (_e) {
    return '';
  }
}

/**
 * 解析 apkg 主函数。出错抛异常（调用方 catch 转 toast）。
 * anki2 / anki21 两种文件名都认；notes 按 cards 表取首卡 deck（同 note 多卡不重复导）。
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

  // 1. 解压（zip；媒体文件为数字命名——无中文乱码风险）
  const opt: zlib.Options = { level: zlib.CompressLevel.COMPRESS_LEVEL_NO_COMPRESSION };
  await zlib.unzipFile(pkgPath, dir, opt);

  // 2. 定位 SQLite（老 .anki2 / 新 .anki21）
  const dbName = fileIo.accessSync(dir + '/collection.anki2') ? 'collection.anki2' : 'collection.anki21';
  if (!fileIo.accessSync(dir + '/' + dbName)) {
    throw new Error('包内没有 collection.anki2/anki21（不是标准 Anki 导出包）');
  }

  // 3. 只读打开（rootDir=解压目录，API18+；securityLevel 必填给 S1）
  const store = await relationalStore.getRdbStore(context, {
    name: dbName,
    securityLevel: relationalStore.SecurityLevel.S1,
    customDir: '',
    rootDir: dir
  });

  // 4. col.decks → did→牌组名
  const deckNames: Map<number, string> = new Map<number, string>();
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

  // 5. media 映射：真名 → 数字文件名
  const mediaFile: Map<string, string> = new Map<string, string>();
  if (fileIo.accessSync(dir + '/media')) {
    const mf = fileIo.openSync(dir + '/media', fileIo.OpenMode.READ_ONLY);
    try {
      const stat = fileIo.statSync(mf.fd);
      const buf = new ArrayBuffer(stat.size);
      fileIo.readSync(mf.fd, buf);
      const map = JSON.parse(buffer.from(buf).toString('utf-8')) as Record<string, string>;
      const keys = Object.keys(map);
      for (let i = 0; i < keys.length; i++) {
        mediaFile.set(map[keys[i]], keys[i]); // 真名 → 编号文件
      }
    } catch (_e) {
      // media 缺失/损坏 → 图片全跳过
    } finally {
      fileIo.closeSync(mf);
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
      if (flds.length === 0 || flds[0].trim().length === 0) {
        continue; // 无正面不成卡
      }
      const front = cleanAnkiHtml(flds[0]);
      if (front.length === 0) {
        continue;
      }
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

  // 8. 清理工作目录（媒体/临时库不留沙箱）
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
