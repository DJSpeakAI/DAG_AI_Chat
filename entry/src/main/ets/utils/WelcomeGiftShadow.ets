// ============================================================
// WelcomeGiftShadow.ets — 新用户礼包「已发放」本地影子标记（★ bug6 根治）
// ============================================================
// 病灶：冷启动时 PersistenceV2 / 云端 cfg:siyi-points 的 welcomeGranted 可能晚于
//   首拉判定（水合竞态）→ 明明已领过礼包，重启又弹「新用户礼包」（重复弹窗，余额不变）。
// 解法：preferences 轻通道（同步载入、独立于 P2 水合）按账号标记「礼包已发」；
//   发放判定先查影子，命中即补 welcomeGranted=true 自愈、不再弹窗。
// 首次升级种子：影子为空时直读 P2 盘文件 persistent_storage，若已有礼包痕迹
//   （welcomeGranted=true 或 giftSp>0）且账号匹配，则补种——存量用户不再重弹。
// 纪律：本件零 import ChatModel（防环）；账号切换天然隔离（标记带账号 mark）。
// ============================================================

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';

const PREF_NAME = 'welcome_gift_marker';
const KEY_ISSUED = 'issued'; // JSON: {"mark":"<unionID/openID>","ts":<ms>,"amount":<sp>}

let markerPref: preferences.Preferences | null = null;

export class WelcomeGiftMark {
  mark: string = '';
  ts: number = 0;
  amount: number = 0;
}

// onCreate 最早同步点调用（accountMark=当前登录账号 unionID/openID，未登录传''）
export function initWelcomeGiftMarker(context: common.Context, accountMark: string): void {
  try {
    markerPref = preferences.getPreferencesSync(context, { name: PREF_NAME });
  } catch (_e) {
    markerPref = null;
    return;
  }
  if (readMark().mark !== '' || accountMark === '') {
    return;
  }
  // 存量用户种子：P2 盘文件里已有礼包痕迹 → 记到当前账号
  const seeded = seedFromP2File(context, accountMark);
  if (seeded) {
    writeMark(accountMark, 0);
  }
}

// 影子是否已标记「该账号领过礼包」
export function isWelcomeGiftIssued(accountMark: string): boolean {
  if (accountMark === '') {
    return false;
  }
  const m = readMark();
  return m.mark !== '' && m.mark === accountMark;
}

// 发放后落标记（同步写盘——即使应用随即被杀也不丢）
export function markWelcomeGiftIssued(accountMark: string, amount: number): void {
  if (accountMark === '') {
    return;
  }
  writeMark(accountMark, amount);
}

// ★ 0.303.1 建 / 0.311.4 恢复：调试重置专用——清除当前账号「已发」影子（仅 debug 包入口调用；
//   0.311.2 曾随「重置保留标记」删除，同日用户定稿「重置=完整新用户」后恢复）
export function clearWelcomeGiftIssued(accountMark: string): void {
  if (markerPref === null || accountMark === '') {
    return;
  }
  const m = readMark();
  if (m.mark !== '' && m.mark !== accountMark) {
    return; // 影子属于另一个账号——不误清
  }
  try {
    markerPref.deleteSync(KEY_ISSUED);
    markerPref.flushSync();
  } catch (_e) {
    // 静默：清失败退化为云端标记判定
  }
}

function readMark(): WelcomeGiftMark {
  const out = new WelcomeGiftMark();
  if (markerPref === null) {
    return out;
  }
  try {
    const raw = markerPref.getSync(KEY_ISSUED, '') as string;
    if (raw === '') {
      return out;
    }
    const d = JSON.parse(raw) as Record<string, Object>;
    out.mark = `${d['mark'] ?? ''}`;
    out.ts = Number(d['ts'] ?? 0);
    out.amount = Number(d['amount'] ?? 0);
  } catch (_e) {
    // 坏值=未标记
  }
  return out;
}

function writeMark(accountMark: string, amount: number): void {
  if (markerPref === null) {
    return;
  }
  try {
    const payload: Record<string, Object> = {};
    payload['mark'] = accountMark;
    payload['ts'] = Date.now();
    payload['amount'] = amount;
    markerPref.putSync(KEY_ISSUED, JSON.stringify(payload));
    markerPref.flushSync();
  } catch (_e) {
    // 静默：影子写失败退化为原 P2/云端判定
  }
}

// P2 盘文件直读（与 CloudSwitchShadow.restoreShadowFromP2File 同款——绕开水合黑盒）
function seedFromP2File(context: common.Context, accountMark: string): boolean {
  try {
    const text = fileIo.readTextSync(`${context.filesDir}/persistent_storage`);
    const acct = readP2Json(text, 'huawei-account');
    if (acct !== '') {
      const a = JSON.parse(acct) as Record<string, Object>;
      const last = `${a['lastAccountMark'] ?? ''}`;
      if (last !== '' && last !== accountMark) {
        return false; // 盘上是另一个账号的痕迹——不种子
      }
    }
    const siyiRaw = readP2Json(text, 'siyi-points-v1');
    if (siyiRaw === '') {
      return false;
    }
    const s = JSON.parse(siyiRaw) as Record<string, Object>;
    const granted = s['welcomeGranted'] === true;
    const gift = Number(s['giftSp'] ?? 0);
    return granted || gift > 0;
  } catch (_e) {
    return false;
  }
}

// P2 文件是 XML 转义 + 双层 JSON 字符串：&quot;{\&quot;k\&quot;:v}&quot;
function readP2Json(text: string, key: string): string {
  const tag = `<string key="${key}">`;
  const i = text.indexOf(tag);
  if (i < 0) {
    return '';
  }
  const start = i + tag.length;
  const end = text.indexOf('</string>', start);
  if (end < 0) {
    return '';
  }
  const raw = text.substring(start, end).split('&quot;').join('"');
  try {
    return JSON.parse(raw) as string;
  } catch (_e) {
    return raw;
  }
}
