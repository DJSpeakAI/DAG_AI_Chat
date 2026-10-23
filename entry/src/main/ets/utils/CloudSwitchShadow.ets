// ============================================================
// CloudSwitchShadow.ets — 云同步开关影子通道（★ 0.301.1 bug8 修复）
// ============================================================
// 实锤（2026-10-23 PC）：PersistenceV2 key 'cloud-sync-switch' 冷启水合失败——
//   盘值 enabled=true 完好，运行时恒 false（与 0.299.2 'huawei-account' 同族黑盒）。
//   后果：首拉闸门 rowInitDone 永不开 → SP 显示 0/指令不执行/礼包判定失效。
// 解法（同 bug5 影子模式，不碰 CloudSyncUtil 红线）：preferences 轻通道记「用户开过同步」，
//   EntryAbility 回前台：enabled=true→写影子；enabled=false 且影子=true→setCloudSyncEnabled(true) 恢复。
//   用户主动关闭（GSD 两个关闭入口）同步写影子 false，避免与用户意愿打架。
// ============================================================

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';

const PREF_NAME = 'cloud_switch_shadow';
const KEY_ON = 'on';

let shadowPref: preferences.Preferences | null = null;

export function initCloudSwitchShadow(context: common.Context): void {
  try {
    shadowPref = preferences.getPreferencesSync(context, { name: PREF_NAME });
  } catch (_e) {
    shadowPref = null;
  }
}

export function writeCloudSwitchShadow(on: boolean): void {
  try {
    if (shadowPref !== null) {
      shadowPref.putSync(KEY_ON, on ? '1' : '0');
      shadowPref.flush();
    }
  } catch (_e) {
    // 静默
  }
}

export function readCloudSwitchShadow(): boolean {
  try {
    return shadowPref !== null && (shadowPref.getSync(KEY_ON, '0') as string) === '1';
  } catch (_e) {
    return false;
  }
}

// 影子为空时从 P2 盘文件直读 cloud-sync-switch.enabled（bug5 迁移同款双重转义两段 parse）
//   用于首次升级到带影子的版本：盘值 enabled=true 直接补影并返回 true（调用方随即恢复开关）
export function restoreShadowFromP2File(context: common.Context): boolean {
  try {
    if (readCloudSwitchShadow()) {
      return true;
    }
    const text = fileIo.readTextSync(`${context.filesDir}/persistent_storage`);
    const tag = '"cloud-sync-switch">&quot;';
    const i = text.indexOf(tag);
    if (i < 0) {
      return false;
    }
    const start = i + tag.length;
    const end = text.indexOf('&quot;</string>', start);
    if (end <= start) {
      return false;
    }
    const seg = text.substring(start, end);
    const unescaped = seg.split('&quot;').join('"').split('&amp;').join('&');
    const objStr = JSON.parse(`"${unescaped}"`) as string;
    const d = JSON.parse(objStr) as Record<string, Object>;
    if (d['enabled'] === true) {
      writeCloudSwitchShadow(true);
      return true;
    }
  } catch (_e) {
    // 静默（读不到=按未开处理，用户重新开一次即建影子）
  }
  return false;
}
