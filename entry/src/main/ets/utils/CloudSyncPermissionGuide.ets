// ============================================================
// CloudSyncPermissionGuide.ets — 云同步授权统一入口（★ 0.311.1）
// ============================================================
// 病灶：门卫引导弹窗「前往开启」原先走 enableCloudSyncNow——系统授权被拒后只有一句
//   「未授权，云同步保持关闭」（CloudSyncUtil 红线不可改），用户不知道去哪授权；
//   且系统授权窗仅首次弹（官方 FAQ：非首次直接返 success 不再弹），拒绝后必须走
//   requestPermissionOnSetting 直达本应用权限面板。
// 解法：统一「请求授权 → 成功即开 → 失败直达权限面板 + 长时手动路径提示」流程，
//   GSD 云同步按钮与 Index 门卫引导共用（消除两套行为分叉）。
// 纪律：本件零 import ChatModel（防环）；CloudSyncUtil 只消费其导出能力（红线）。
// ============================================================

import { common, abilityAccessCtrl } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import Want from '@ohos.app.ability.Want';
import { requestSyncPermission, activateCloudSync, connectCloudSync } from './CloudSyncUtil';
import { connectSiyiGate } from './SiyiGate';
import { writeCloudSwitchShadow } from './CloudSwitchShadow';

function toastSafe(uiContext: UIContext, msg: string, duration: number): void {
  try {
    uiContext.getPromptAction().showToast({ message: msg, duration });
  } catch (_e) {
    // 静默（toast 非关键路径）
  }
}

// 请求跨设备同步权限并引导：成功=开云同步；拒绝/系统不再弹窗=直达权限面板
export function enableCloudSyncWithGuide(uiContext: UIContext): void {
  const context = uiContext.getHostContext() as common.UIAbilityContext;
  if (context === undefined || context === null) {
    toastSafe(uiContext, '获取上下文失败，请重试', 1500);
    return;
  }
  requestSyncPermission(context).then((granted: boolean) => {
    connectSiyiGate().permGranted = granted; // 门卫/设置状态卡共用真值源
    if (granted) {
      writeCloudSwitchShadow(true); // P2 水合失败兜底——影子记住用户开过
      toastSafe(uiContext, '云同步已开启', 1500);
      return;
    }
    // 拒绝/系统不再弹窗：先给出手动路径（10 秒顶格，1.5 秒一闪用户看不清），再直达权限面板
    toastSafe(uiContext,
      '未授权「跨设备同步」：请在系统「设置→应用→DAG AI Chat→权限」允许，或直接在权限面板开启', 10000);
    openPermissionPanel(uiContext, context);
  });
}

// 直达本应用权限面板（手机/Pad 半屏面板、PC 系统设置权限页——系统 API 统一处理）；
// 面板内开启后当场激活云同步；异常兜底跳系统应用详情页（0.251.2 行为，不崩溃）
function openPermissionPanel(uiContext: UIContext, context: common.UIAbilityContext): void {
  (async () => {
    try {
      const atm = abilityAccessCtrl.createAtManager();
      const result = await atm.requestPermissionOnSetting(context,
        ['ohos.permission.DISTRIBUTED_DATASYNC']);
      if (result.length > 0 && result[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        connectSiyiGate().permGranted = true;
        connectCloudSync().enabled = true;
        writeCloudSwitchShadow(true);
        activateCloudSync();
        toastSafe(uiContext, '云同步已开启', 1500);
      }
    } catch (_e) {
      const want: Want = {
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        uri: 'application_info',
        parameters: { pushParams: 'com.dagaichat.app' }
      };
      context.startAbility(want).catch(() => {
        // 跳转失败静默——上方手动路径提示已兜底
      });
    }
  })();
}
