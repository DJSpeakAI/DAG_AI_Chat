// AppConfirmDialog.ets — ★ 0.196.9：通用确认弹窗（暗紫设计语言，替代系统灰 AlertDialog）
// 背景：登录后「是否开启云同步」/ 边栏头像「退出华为账号」两弹窗原用系统 AlertDialog
//   （灰白底），用户实测反馈与应用暗紫风格不符（同 0.195.0 ReminderDialog 先例——
//   用户拍板系统灰弹窗必须换自定义；本组件 = 该设计语言的通用双按钮版）
// 样式模板：0.190.8 隐私弹窗 / 0.195.0 ReminderDialog 同款
//   （遮罩 rgba(0,0,0,0.5) + SURFACE_NODE 面板 + RADIUS_NAV + STROKE_CARD 描边 + 主紫确认钮）
// 触发方式：ConfirmDialogStore（AppStorageV2 应用级共享、不落盘——弹窗状态重启即清不残留）；
//   挂载点唯一：Index 根 Stack 顶层（盖住 Navigation 全部子页——AppSideBar 常驻/抽屉两形态全兜住）

import { AppStorageV2 } from '@kit.ArkUI';
import { SURFACE_NODE, BRAND_PRIMARY, TEXT_PRIMARY, TEXT_SECONDARY, STROKE_CARD, RADIUS_NAV, RADIUS_CONTROL, FONT_SIZE_SCREEN_TITLE, FONT_SIZE_BODY, FONT_SIZE_CARD_TITLE_SM, FONT_INTER_SEMIBOLD } from '../common/DesignTokens';

// ★ 0.196.9：确认弹窗触发桥——AppStorageV2（应用生命周期共享、非持久化）
//   任意组件 set visible=true → Index 根挂载的对应弹窗实例显示（跨组件解耦）
@ObservedV2
export class ConfirmDialogStore {
  @Trace logoutConfirmVisible: boolean = false; // 「退出华为账号」确认（边栏头像触发）
  @Trace cloudSyncPromptVisible: boolean = false; // 登录后「是否开启云同步」询问（三条登录路径触发）
}

// 连接应用级单例（key 'confirm-dialog'）
export function connectConfirmDialog(): ConfirmDialogStore {
  return AppStorageV2.connect(ConfirmDialogStore, 'confirm-dialog',
    () => new ConfirmDialogStore()) as ConfirmDialogStore;
}

@ComponentV2
export struct AppConfirmDialog {
  @Param visible: boolean = false;
  @Param title: string = '';
  @Param message: string = '';
  @Param confirmText: string = '确定';
  @Param cancelText: string = '取消';
  @Event onConfirm: () => void = () => {};
  @Event onCancel: () => void = () => {};

  build() {
    if (this.visible) {
      // 遮罩（点击 = 取消——确认类弹窗防误触，点空白不执行确认动作）
      Column() {
        Blank()
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0,0,0,0.5)')
      .onClick(() => {
        this.onCancel();
      })

      // 面板（ReminderDialog 同款：88% 宽 + padding 20 + RADIUS_NAV + SURFACE_NODE + STROKE_CARD）
      Column() {
        Text(this.title)
          .fontSize(FONT_SIZE_SCREEN_TITLE)
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
          .fontFamily(FONT_INTER_SEMIBOLD)
          .margin({ bottom: 12 })

        Text(this.message)
          .fontSize(FONT_SIZE_BODY)
          .lineHeight(22)
          .fontColor(TEXT_SECONDARY)

        // 双按钮：取消（SURFACE_NODE 描边弱化）+ 确认（主紫）——ReminderDialog 倒计时模式同款
        Row({ space: 10 }) {
          Button(this.cancelText)
            .layoutWeight(1)
            .height(48)
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(SURFACE_NODE)
            .fontColor(TEXT_SECONDARY)
            .border({ width: 1, color: STROKE_CARD })
            .borderRadius(RADIUS_CONTROL)
            .onClick(() => {
              this.onCancel();
            })
          Button(this.confirmText)
            .layoutWeight(1)
            .height(48)
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(BRAND_PRIMARY)
            .fontColor(TEXT_PRIMARY)
            .borderRadius(RADIUS_CONTROL)
            .onClick(() => {
              this.onConfirm();
            })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width('88%')
      .padding(20)
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
      .border({ width: 1, color: STROKE_CARD })
    }
  }
}
