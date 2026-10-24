// ============================================================
// SpCloudSeenShadow.ets — 「SP 云端行见过」本地影子标记（★ 0.311.1）
// ============================================================
// 病灶：假开启判定（0.308.0）的唯一本地证据 = PersistenceV2 'sp-cloud-seen-v1'，
//   属华为 P2 单 key 水合黑盒高发区（同族前科：huawei-account 永久水合失败 → bug5）。
//   冷启动一旦水合失败，证据丢失 → 只剩云函数探针；探针对「只有本机有历史」的账号
//   （其他设备从未登录过该账号）返回 no → fail-open 发礼包/签到 = 2026-10-24 用户实测
//   「系统云空间没开却弹 200 万礼包」的直接成因。
// 解法：preferences 轻通道双写（同步载入、独立于 P2 水合），启动时回填 P2 标志。
// 纪律：本件零 import ChatModel（防环）；标记是「本机曾真实下行收到 SP 行」的全局事实，
//   跨账号不做隔离（只作正向证据：为真时绝不放行假开启）。
// ============================================================

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';

const PREF_NAME = 'sp_cloud_seen_shadow';
const KEY_SEEN = 'spRow';

let shadowPref: preferences.Preferences | null = null;

// onCreate 最早同步点调用（与 initAccountShadow 同纪律）
export function initSpCloudSeenShadow(context: common.Context): void {
  if (shadowPref !== null) {
    return;
  }
  try {
    shadowPref = preferences.getPreferencesSync(context, { name: PREF_NAME });
  } catch (_e) {
    shadowPref = null;
    return;
  }
  // P2 盘文件一次性种子：影子空而 P2 盘值已置位（水合失败但盘上完好）→ 回填影子
  if (!readShadow()) {
    seedFromP2File(context);
  }
}

// 影子是否记录过「真实下行 SP 行」
export function isSpCloudRowSeen(): boolean {
  return readShadow();
}

// 真实下行收到 SP 行时调用（同步落盘）
export function markSpCloudRowSeen(): void {
  if (shadowPref === null) {
    return;
  }
  try {
    shadowPref.putSync(KEY_SEEN, true);
    shadowPref.flushSync();
  } catch (_e) {
    // 静默：写失败退化为 P2 单通道（原行为）
  }
}

function readShadow(): boolean {
  if (shadowPref === null) {
    return false;
  }
  try {
    return shadowPref.getSync(KEY_SEEN, false) as boolean;
  } catch (_e) {
    return false;
  }
}

// P2 盘文件直读（persistent_storage，XML 转义格式）——'sp-cloud-seen-v1' 的 spRow 字段
function seedFromP2File(context: common.Context): void {
  try {
    const text = fileIo.readTextSync(`${context.filesDir}/persistent_storage`);
    const tag = '<string key="sp-cloud-seen-v1">';
    const i = text.indexOf(tag);
    if (i < 0) {
      return;
    }
    const start = i + tag.length;
    const end = text.indexOf('</string>', start);
    if (end <= start) {
      return;
    }
    const unescaped = text.substring(start, end).split('&quot;').join('"');
    const objStr = JSON.parse(`"${unescaped}"`) as string;
    const d = JSON.parse(objStr) as Record<string, Object>;
    if (d['spRow'] === true) {
      markSpCloudRowSeen();
    }
  } catch (_e) {
    // 迁移失败静默（下轮真下行会重新置位）
  }
}
