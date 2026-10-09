// ============================================================
// BackupUtil.ets — ★ 0.205.0 数据安全三道防线（用户拍板 100% 上）
// ============================================================
// 第一道：Schema 铁律（见 project_rule.md——字段只追加不改名，本文件 SCHEMA_VERSION 兜底校验）
// 第二道：沙箱内自动双备份（backup_a/b 轮换 + 临时文件原子写）——防 PersistenceV2 损坏/升级失败清空
// 第三道：外部备份（用户目录 .dagbak 文件）——防卸载重装/换机；每日自动（开开关选目录，
//         超 24h 打开应用自动补备）+ 手动立即备份 + 从文件导入
//
// 数据范围（第一版）：单词库 + 知识库（含记忆字段/标签/图片 base64）。气泡树/设置后续扩展。
// 恢复策略：合并导入（同 id 以备份为准，库中多余保留——绝不删用户现有数据）。
// ============================================================

import { preferences } from '@kit.ArkData';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { WordItem, WordBankStore } from '../common/WordModel';
import { KnowledgeCard, KnowledgeBankStore, KFolder } from '../common/KnowledgeModel';

const SCHEMA_VERSION = 1;
const PREF_BACKUP = 'backup_settings';
const KEY_AUTO = 'auto_enabled';
const KEY_URI = 'external_uri';
const KEY_LAST_EXT = 'last_external_at';
const KEY_SLOT = 'internal_slot'; // 内部备份轮换位（0=a 1=b）

const AUTO_INTERVAL_MS = 24 * 60 * 60 * 1000; // 每日自动备份间隔（用户方案：错过 0 点则超 24h 打开时补备）

/** 备份载荷（.dagbak 内容；条目为平铺 Record——★ 0.205.4 手写序列化产物） */
export interface BackupPayload {
  schemaVersion: number;
  exportedAt: number;
  words: Record<string, Object>[];
  cards: Record<string, Object>[];
  folders?: Record<string, Object>[]; // ★ 0.207.0：知识库文件夹（可选——旧备份无此字段，恢复端兼容）
}

/** 备份设置快照（UI 显示用） */
export interface BackupSettings {
  autoEnabled: boolean;
  uri: string;
  lastExternalAt: number;
}

function getPref(context: Context): preferences.Preferences {
  return preferences.getPreferencesSync(context, { name: PREF_BACKUP });
}

// ---------------- 载荷构建与校验 ----------------

// ★ 0.205.4 根因修复：@ObservedV2 类的 @Trace 字段 JSON.stringify 不可枚举 → 序列化成 {}
//   （用户实测：备份恢复后卡片条数对但内容全空）。导出端必须手写字段映射——内部备份与
//   外部 .dagbak 共用本函数（同一流水线，一处修两处好）。气泡树 serialize 先例同理。
function wordToPlain(w: WordItem): Record<string, Object> {
  const o: Record<string, Object> = {};
  o['word'] = w.word;
  o['fullName'] = w.fullName;
  o['usPhonetic'] = w.usPhonetic;
  o['explain'] = w.explain;
  o['id'] = w.id;
  o['createTime'] = w.createTime;
  o['strength'] = w.strength;
  o['reviewCount'] = w.reviewCount;
  o['lastReviewAt'] = w.lastReviewAt;
  o['nextReviewAt'] = w.nextReviewAt;
  return o;
}

function cardToPlain(c: KnowledgeCard): Record<string, Object> {
  const o: Record<string, Object> = {};
  o['id'] = c.id;
  o['title'] = c.title;
  o['definition'] = c.definition;
  o['imageUri'] = c.imageUri;
  o['createdAt'] = c.createdAt;
  o['strength'] = c.strength;
  o['reviewCount'] = c.reviewCount;
  o['lastReviewAt'] = c.lastReviewAt;
  o['nextReviewAt'] = c.nextReviewAt;
  o['tags'] = c.tags;
  o['images'] = c.images;
  o['folderId'] = c.folderId; // ★ 0.207.0：所属文件夹（anything 导入体系）
  o['titleImages'] = c.titleImages; // ★ 0.210.0：标题图（Anki 图对图）
  return o;
}

/** ★ 0.207.0：文件夹平铺序列化（同 cardToPlain 理由——@Trace 字段手写映射） */
function folderToPlain(f: KFolder): Record<string, Object> {
  const o: Record<string, Object> = {};
  o['id'] = f.id;
  o['name'] = f.name;
  o['parentId'] = f.parentId;
  o['createdAt'] = f.createdAt;
  return o;
}

export function buildBackupPayload(wordBank: WordBankStore, knowledgeBank: KnowledgeBankStore): BackupPayload {
  const words: Record<string, Object>[] = [];
  wordBank.words.forEach((w: WordItem) => words.push(wordToPlain(w)));
  const cards: Record<string, Object>[] = [];
  knowledgeBank.cards.forEach((c: KnowledgeCard) => cards.push(cardToPlain(c)));
  const folders: Record<string, Object>[] = [];
  knowledgeBank.folders.forEach((f: KFolder) => folders.push(folderToPlain(f)));
  return { schemaVersion: SCHEMA_VERSION, exportedAt: Date.now(), words: words, cards: cards, folders: folders };
}

function payloadToJson(p: BackupPayload): string {
  return JSON.stringify(p);
}

/** 解析校验：版本超期/结构不对一律拒绝（fang-脏数据注入）；
 *  ★ 0.205.4：拦截 0.205.0~0.205.3 的坏备份（@Trace 序列化 bug 产物——条目非空但字段全空壳） */
function jsonToPayload(context: Context, raw: string): BackupPayload | undefined {
  try {
    const p = JSON.parse(raw) as BackupPayload;
    if (p === null || p === undefined || typeof p.schemaVersion !== 'number' || p.schemaVersion > SCHEMA_VERSION) {
      return undefined;
    }
    if (!Array.isArray(p.words) || !Array.isArray(p.cards)) {
      return undefined;
    }
    if (p.words.length > 0) {
      const f = p.words[0];
      if (((f['word'] ?? '') as string).length === 0 && ((f['id'] ?? '') as string).length === 0) {
        return undefined; // 坏备份：字段空壳（旧序列化 bug 产物）——拒绝防污染
      }
    }
    if (p.cards.length > 0) {
      const f = p.cards[0];
      if (((f['title'] ?? '') as string).length === 0 && ((f['id'] ?? '') as string).length === 0) {
        return undefined;
      }
    }
    return p;
  } catch (_e) {
    return undefined;
  }
}

// ---------------- 通用文件读写（TextDecoder） ----------------

function readFileText(pathOrUri: string): string {
  const f = fileIo.openSync(pathOrUri, fileIo.OpenMode.READ_ONLY);
  const buf = new ArrayBuffer(4 * 1024 * 1024); // 4MB 上限（图片 base64 库可能大）
  const len = fileIo.readSync(f.fd, buf);
  fileIo.closeSync(f);
  const decoder = util.TextDecoder.create('utf-8');
  return decoder.decodeToString(new Uint8Array(buf.slice(0, len))).trim();
}

function writeFileText(pathOrUri: string, text: string, mode: number): void {
  const f = fileIo.openSync(pathOrUri, mode);
  fileIo.writeSync(f.fd, text);
  fileIo.closeSync(f);
}

// ---------------- 第二道：内部双备份（沙箱内） ----------------

function internalDir(context: Context): string {
  return context.filesDir + '/backups';
}

/** 写内部备份：a/b 轮换 + 临时文件原子写（防写一半损坏） */
export function writeInternalBackup(context: Context, p: BackupPayload): boolean {
  try {
    try {
      fileIo.mkdirSync(internalDir(context));
    } catch (_e) {
      // 已存在
    }
    const pref = getPref(context);
    const slot = ((pref.getSync(KEY_SLOT, 0) as number) + 1) % 2; // 轮换到另一位
    const final = `${internalDir(context)}/backup_${slot === 0 ? 'a' : 'b'}.json`;
    const tmp = `${internalDir(context)}/backup_tmp_${slot}.json`;
    writeFileText(tmp, payloadToJson(p), fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
    fileIo.renameSync(tmp, final); // 原子替换
    pref.putSync(KEY_SLOT, slot);
    pref.flush();
    return true;
  } catch (_e) {
    return false;
  }
}

/** 读内部备份：a/b 取合法且最新的 */
export function readInternalBackup(context: Context): BackupPayload | undefined {
  let best: BackupPayload | undefined = undefined;
  for (const name of ['backup_a.json', 'backup_b.json']) {
    try {
      const raw = readFileText(`${internalDir(context)}/${name}`);
      const p = jsonToPayload(context, raw);
      if (p !== undefined && (best === undefined || p.exportedAt > best.exportedAt)) {
        best = p;
      }
    } catch (_e) {
      // 单个损坏跳过（双备份意义所在）
    }
  }
  return best;
}

export function hasInternalBackup(context: Context): boolean {
  return readInternalBackup(context) !== undefined;
}

/** 内部备份时间（UI 显示；0=无） */
export function getLastInternalTime(context: Context): number {
  const p = readInternalBackup(context);
  return p === undefined ? 0 : p.exportedAt;
}

// ---------------- 恢复（合并导入——绝不删现有数据） ----------------

function reviveWord(src: Record<string, Object>): WordItem {
  const w = new WordItem();
  w.word = (src['word'] ?? '') as string;
  w.fullName = (src['fullName'] ?? '') as string;
  w.usPhonetic = (src['usPhonetic'] ?? '') as string;
  w.explain = (src['explain'] ?? '') as string;
  w.id = (src['id'] ?? '') as string;
  w.createTime = (src['createTime'] ?? 0) as number;
  w.strength = (src['strength'] ?? 0) as number;
  w.reviewCount = (src['reviewCount'] ?? 0) as number;
  w.lastReviewAt = (src['lastReviewAt'] ?? 0) as number;
  w.nextReviewAt = (src['nextReviewAt'] ?? 0) as number;
  return w;
}

function reviveCard(src: Record<string, Object>): KnowledgeCard {
  const c = new KnowledgeCard();
  c.id = (src['id'] ?? '') as string;
  c.title = (src['title'] ?? '') as string;
  c.definition = (src['definition'] ?? '') as string;
  c.imageUri = (src['imageUri'] ?? '') as string;
  c.createdAt = (src['createdAt'] ?? 0) as number;
  c.strength = (src['strength'] ?? 0) as number;
  c.reviewCount = (src['reviewCount'] ?? 0) as number;
  c.lastReviewAt = (src['lastReviewAt'] ?? 0) as number;
  c.nextReviewAt = (src['nextReviewAt'] ?? 0) as number;
  c.tags = (src['tags'] ?? '') as string;
  c.images = (src['images'] ?? '') as string;
  c.folderId = (src['folderId'] ?? '') as string; // ★ 0.207.0：旧备份无此字段 → 根目录
  c.titleImages = (src['titleImages'] ?? '') as string; // ★ 0.210.0：旧备份无此字段 → 无标题图
  return c;
}

/** ★ 0.207.0：文件夹 revive（旧备份无 folders → 不动现有目录结构） */
function reviveFolder(src: Record<string, Object>): KFolder | undefined {
  const id = (src['id'] ?? '') as string;
  const name = (src['name'] ?? '') as string;
  if (id.length === 0 || name.length === 0) {
    return undefined;
  }
  const f = new KFolder();
  f.id = id;
  f.name = name;
  f.parentId = (src['parentId'] ?? '') as string;
  f.createdAt = (src['createdAt'] ?? 0) as number;
  return f;
}

/**
 * 合并导入：同 id 以备份为准（整卡覆盖），库中多余保留。
 * 返回导入条数（词+卡）。PersistenceV2 @Trace 数组整体替换触发 UI 刷新。
 */
export function restoreFromPayload(wordBank: WordBankStore, knowledgeBank: KnowledgeBankStore, p: BackupPayload): number {
  let count = 0;
  const words: WordItem[] = [];
  wordBank.words.forEach((w: WordItem) => words.push(w)); // 现有全保留
  p.words.forEach((src: Record<string, Object>) => {
    // ★ 0.205.5 第二道网：逐条丢弃空壳（word+id 全空=坏数据，拦截漏网也进不了库）
    if (((src['word'] ?? '') as string).length === 0 && ((src['id'] ?? '') as string).length === 0) {
      return; // 跳过本条
    }
    const revived = reviveWord(src);
    const idx = words.findIndex((w: WordItem): boolean => w.id === revived.id && revived.id !== '');
    if (idx >= 0) {
      words[idx] = revived; // 同 id 覆盖
    } else {
      words.push(revived);
    }
    count += 1;
  });
  wordBank.words = words; // 整体替换（@Trace 触发）

  const cards: KnowledgeCard[] = [];
  knowledgeBank.cards.forEach((c: KnowledgeCard) => cards.push(c));
  p.cards.forEach((src: Record<string, Object>) => {
    // ★ 0.205.5 第二道网：逐条丢弃空壳（title+id 全空）
    if (((src['title'] ?? '') as string).length === 0 && ((src['id'] ?? '') as string).length === 0) {
      return; // 跳过本条
    }
    const revived = reviveCard(src);
    const idx = cards.findIndex((c: KnowledgeCard): boolean => c.id === revived.id && revived.id !== '');
    if (idx >= 0) {
      cards[idx] = revived;
    } else {
      cards.push(revived);
    }
    count += 1;
  });
  knowledgeBank.cards = cards;

  // ★ 0.207.0：文件夹合并恢复（旧备份无 folders 字段 → 跳过不动现有目录）
  if (Array.isArray(p.folders) && p.folders.length > 0) {
    const folders: KFolder[] = [];
    knowledgeBank.folders.forEach((f: KFolder) => folders.push(f));
    p.folders.forEach((src: Record<string, Object>) => {
      const revived = reviveFolder(src);
      if (revived === undefined) {
        return;
      }
      const idx = folders.findIndex((f: KFolder): boolean => f.id === revived.id);
      if (idx >= 0) {
        folders[idx] = revived;
      } else {
        folders.push(revived);
      }
    });
    knowledgeBank.folders = folders;
  }
  return count;
}

// ---------------- 第三道：外部备份（用户目录） ----------------

export function getBackupSettings(context: Context): BackupSettings {
  try {
    const pref = getPref(context);
    return {
      autoEnabled: (pref.getSync(KEY_AUTO, false) as boolean) === true,
      uri: (pref.getSync(KEY_URI, '') as string),
      lastExternalAt: pref.getSync(KEY_LAST_EXT, 0) as number
    };
  } catch (_e) {
    return { autoEnabled: false, uri: '', lastExternalAt: 0 };
  }
}

// pickBackupFile: save picker -> uri ('' = cancelled)
// 0.205.1: autoCreateEmptyFile=false (no empty shell file)
// 0.205.2: FIXED filename Dag_AI_Chat_Backup (auto-backup overwrites the same file;
//          timestamp in name would mislead users into thinking it is a point-in-time snapshot)
export function pickBackupFile(context: Context): Promise<string> {
  return new Promise<string>((resolve) => {
    try {
      const docPicker = new picker.DocumentViewPicker(context);
      const opt = new picker.DocumentSaveOptions();
      opt.newFileNames = ['Dag_AI_Chat_Backup'];
      opt.fileSuffixChoices = ['DAGAI 备份文件|dagbak'];
      opt.autoCreateEmptyFile = false; // 由我们真正写入时创建——杜绝空壳文件
      docPicker.save(opt).then((uris: Array<string>) => {
        resolve(uris.length > 0 ? uris[0] : '');
      }).catch(() => {
        resolve('');
      });
    } catch (_e) {
      resolve('');
    }
  });
}

/** 弹系统文件选择器（选已有 .dagbak）→ 读出载荷（undefined=取消/非法）
 *  ★ 0.205.3 bugfix：去掉 fileSuffixFilters（用户实测「发现不了文件」——后缀过滤格式在该机
 *  选择器上把列表过滤空了。改显示全部文件，用户自己找 Dag_AI_Chat_Backup.dagbak） */
export function pickAndReadBackupFile(context: Context): Promise<BackupPayload | undefined> {
  return new Promise<BackupPayload | undefined>((resolve) => {
    try {
      const docPicker = new picker.DocumentViewPicker(context);
      const opt = new picker.DocumentSelectOptions();
      docPicker.select(opt).then((uris: Array<string>) => {
        if (uris.length === 0) {
          resolve(undefined);
          return;
        }
        try {
          const raw = readFileText(uris[0]);
          resolve(jsonToPayload(context, raw));
        } catch (_e) {
          resolve(undefined);
        }
      }).catch(() => {
        resolve(undefined);
      });
    } catch (_e) {
      resolve(undefined);
    }
  });
}

/** 记录外部目录（开开关/改目录后调用；记录即立即备份一份验证可写） */
export function setExternalUri(context: Context, uri: string): void {
  const pref = getPref(context);
  pref.putSync(KEY_URI, uri);
  pref.flush();
}

/** 开关每日自动备份 */
export function setAutoBackupEnabled(context: Context, on: boolean): void {
  const pref = getPref(context);
  pref.putSync(KEY_AUTO, on);
  pref.flush();
}

/** 写外部备份（覆盖 uri 指向的文件）；★ 0.205.1：写入字节数校验+读回验证（防假成功），
 *  打开模式 WRITE_ONLY|CREATE|TRUNC（picker 关预创建后由本调用建文件）。false=写入失败（UI 提示重新选目录） */
export function writeExternalBackup(context: Context, p: BackupPayload): Promise<boolean> {
  return new Promise<boolean>((resolve) => {
    const s = getBackupSettings(context);
    if (s.uri.length === 0) {
      resolve(false);
      return;
    }
    const json = payloadToJson(p);
    try {
      const f = fileIo.openSync(s.uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      const written = fileIo.writeSync(f.fd, json);
      fileIo.closeSync(f);
      if (written !== json.length) { // 字节数不符（string 按字符写，长度应一致）
        resolve(false);
        return;
      }
      const back = readFileText(s.uri); // 读回验证——空/短文件一律视为失败（0.205.1 空文件 bug 核心防线）
      if (back.length < json.length) {
        resolve(false);
        return;
      }
      const pref = getPref(context);
      pref.putSync(KEY_LAST_EXT, Date.now());
      pref.flush();
      resolve(true);
    } catch (_e) {
      resolve(false); // picker 授权失效等——提示用户重新选择目录
    }
  });
}

/**
 * 每日自动备份检测（Index 启动/回前台调用）：
 * 开关开 + 有目录 + 距上次 ≥24h → 自动覆盖备份一份（用户方案：错过 0 点由下次打开补）。
 * 返回 true=本次执行了自动备份（UI 可 toast 提示）。
 */
export function maybeAutoBackup(context: Context, wordBank: WordBankStore, knowledgeBank: KnowledgeBankStore): void {
  const s = getBackupSettings(context);
  if (!s.autoEnabled || s.uri.length === 0) {
    return;
  }
  if (Date.now() - s.lastExternalAt < AUTO_INTERVAL_MS) {
    return;
  }
  writeExternalBackup(context, buildBackupPayload(wordBank, knowledgeBank)).then((_ok: boolean) => {
    // 失败静默（下次打开再试；手动备份时 UI 会提示）
  });
}
