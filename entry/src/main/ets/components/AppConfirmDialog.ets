// AppConfirmDialog.ets — ★ 0.196.9：通用确认弹窗（暗紫设计语言，替代系统灰 AlertDialog）
// 背景：登录后「是否开启云同步」/ 边栏头像「退出华为账号」两弹窗原用系统 AlertDialog
//   （灰白底），用户实测反馈与应用暗紫风格不符（同 0.195.0 暗紫弹窗先例——
//   用户拍板系统灰弹窗必须换自定义；本组件 = 该设计语言的通用双按钮版）
// 样式模板：0.190.8 隐私弹窗 / 0.195.0 AppConfirmDialog 同款
//   （遮罩 rgba(0,0,0,0.5) + this.theme.surfaceNode 面板 + RADIUS_NAV + this.theme.strokeCard 描边 + 主紫确认钮）
// 触发方式：ConfirmDialogStore（AppStorageV2 应用级共享、不落盘——弹窗状态重启即清不残留）；
//   挂载点唯一：Index 根 Stack 顶层（盖住 Navigation 全部子页——AppSideBar 常驻/抽屉两形态全兜住）

import { AppStorageV2 } from '@kit.ArkUI';
import { RADIUS_NAV, RADIUS_CONTROL, FONT_SIZE_SCREEN_TITLE, FONT_SIZE_BODY, FONT_SIZE_CARD_TITLE_SM, FONT_INTER_SEMIBOLD } from '../common/DesignTokens';
import { AppTheme, connectAppTheme } from '../common/AppTheme';
import { WindowMode, connectWindowMode } from '../common/WindowMode'; // ★ 0.225.2：宽屏断点（弹窗宽度收敛，UI_GUIDELINES 暂停-12）

// ★ 0.196.9：确认弹窗触发桥——AppStorageV2（应用生命周期共享、非持久化）
//   任意组件 set visible=true → Index 根挂载的对应弹窗实例显示（跨组件解耦）
@ObservedV2
export class ConfirmDialogStore {
  @Trace logoutConfirmVisible: boolean = false; // 「退出华为账号」确认（边栏头像触发）
  @Trace cloudSyncPromptVisible: boolean = false; // 登录后「是否开启云同步」询问（三条登录路径触发）
  @Trace loginPromptVisible: boolean = false; // ★ 0.196.10：未登录点「开启云同步」→ 登录引导（设置页触发）
  @Trace aiLoginPromptVisible: boolean = false; // ★ 0.248.2：未登录发消息问 AI → 登录引导（上架合规：AI 生成内容限实名华为账号用户——ChatPage 发送/重生成等入口触发）
  @Trace spRechargePromptVisible: boolean = false; // ★ 0.248.7：SP 余额为 0 发消息 → 充能引导（实扣链路上线；ChatPage 发送/重生成触发，确认跳账单页充能）
  // ★ 0.293.0：SP 云同步门卫引导（SiyiGate——消耗/增加 SP 的功能在云同步未就绪时触发；
  //   确认动作按 siyiGateBlockReason 分支：登录/一键开启/跳系统云空间，Index 根 Stack 消费）
  @Trace syncGatePromptVisible: boolean = false;
  // ★ 0.293.0：新用户礼包发放仪式感弹窗（云首拉完成+云端确认无发放记录才发放——发放即弹窗
  //   明示「您是新用户，免费赠送 N 万 SP」，绝不做后台默默到账；用户拍板）
  @Trace welcomeBonusVisible: boolean = false;
  @Trace welcomeBonusAmount: number = 0; // 本次发放额（弹窗文案用）
}

// 连接应用级单例（key 'confirm-dialog'）
export function connectConfirmDialog(): ConfirmDialogStore {
  return AppStorageV2.connect(ConfirmDialogStore, 'confirm-dialog',
    () => new ConfirmDialogStore()) as ConfirmDialogStore;
}

@ComponentV2
export struct AppConfirmDialog {
  theme: AppTheme = connectAppTheme();
  @Param visible: boolean = false;
  @Param title: string = '';
  @Param message: string = '';
  @Param confirmText: string = '确定';
  @Param cancelText: string = '取消';
  // ★ 0.196.10：确认钮放左侧（用户拍板：登录引导弹窗「左下角登录华为账号，右边取消」；
  //   默认 false = 取消左/确认右标准序）
  @Param confirmOnLeft: boolean = false;
  // ★ 0.263.0：可选勾选框（空串=不显示，现有调用点零波及）——「退出并清空本机数据」等高危附带动作；
  //   勾选态由组件自持（@Local），visible 复位时归零防跨次残留
  @Param checkboxLabel: string = '';
  // ★ 0.263.0：勾选态下确认钮替换文字（空串=不替换），防误触高危确认
  @Param checkedConfirmText: string = '';
  @Local checkboxChecked: boolean = false;
  @Event onConfirm: () => void = () => {};
  @Event onCancel: () => void = () => {};
  // ★ 0.263.0：checkbox 模式下确认钮改走此事件（携带勾选态）；普通模式仍走 onConfirm
  @Event onConfirmChecked: (checked: boolean) => void = () => {};

  @Monitor('visible')
  onVisibleChange(): void {
    if (!this.visible) {
      this.checkboxChecked = false; // 弹窗关闭复位——复用实例不残留上次勾选
    }
  }

  // ★ 0.225.2：宽屏断点——@ObservedV2 实例须挂 @Local 才可靠响应 @Trace（同 KnowledgeBankPage）
  @Local windowMode: WindowMode = connectWindowMode();
  @Computed get isTablet(): boolean {
    return this.windowMode.isTablet;
  }

  // 取消钮（弱化：this.theme.surfaceNode 底 + this.theme.strokeCard 描边）
  @Builder
  cancelButtonBuilder() {
    Button(this.cancelText)
      .layoutWeight(1)
      .height(48)
      .fontSize(FONT_SIZE_CARD_TITLE_SM)
      .fontWeight(FontWeight.Medium)
      .backgroundColor(this.theme.surfaceNode)
      .fontColor(this.theme.textSecondary)
      .border({ width: 1, color: this.theme.strokeCard })
      .borderRadius(RADIUS_CONTROL)
      .onClick(() => {
        this.onCancel();
      })
  }

  // 确认钮（主紫；★ 0.263.0：勾选态且有替换文案时切换按钮文字，明确高危动作；
  //   ★ 0.287.0 P1：defaultFocus 申请默认焦点——弹窗打开 Enter 经系统焦点链直接触发确认，
  //   「有确定按钮的弹窗回车=确定」；本组件场景均为询问/引导类，确认即用户意图）
  @Builder
  confirmButtonBuilder() {
    Button(this.checkboxLabel !== '' && this.checkboxChecked && this.checkedConfirmText !== ''
      ? this.checkedConfirmText : this.confirmText)
      .layoutWeight(1)
      .height(48)
      .fontSize(FONT_SIZE_CARD_TITLE_SM)
      .fontWeight(FontWeight.Medium)
      .backgroundColor(this.theme.brandPrimary)
      .fontColor(this.theme.textPrimary)
      .borderRadius(RADIUS_CONTROL)
      .defaultFocus(this.visible)
      .onClick(() => {
        if (this.checkboxLabel !== '') {
          this.onConfirmChecked(this.checkboxChecked);
        } else {
          this.onConfirm();
        }
      })
  }

  build() {
    if (this.visible) {
      // 遮罩（点击 = 取消——确认类弹窗防误触，点空白不执行确认动作）
      Column() {
        Blank()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.overlay)
      .onClick(() => {
        this.onCancel();
      })

      // 面板（AppConfirmDialog 同款：88% 宽 + padding 20 + RADIUS_NAV + this.theme.surfaceNode + this.theme.strokeCard）
      Column() {
        Text(this.title)
          .fontSize(FONT_SIZE_SCREEN_TITLE)
          .fontWeight(600)
          .fontColor(this.theme.textPrimary)
          .fontFamily(FONT_INTER_SEMIBOLD)
          .margin({ bottom: 12 })

        Text(this.message)
          .fontSize(FONT_SIZE_BODY)
          .lineHeight(22)
          .fontColor(this.theme.textSecondary)

        // ★ 0.263.0：可选勾选框（checkboxLabel 空串不渲染）——整行可点切换
        if (this.checkboxLabel !== '') {
          Row({ space: 8 }) {
            Image(this.checkboxChecked ? $r('app.media.checkbox_on') : $r('app.media.checkbox_off'))
              .width(20)
              .height(20)
            Text(this.checkboxLabel)
              .fontSize(FONT_SIZE_BODY)
              .fontColor(this.theme.textSecondary)
              .layoutWeight(1)
          }
          .width('100%')
          .margin({ top: 14 })
          .onClick(() => {
            this.checkboxChecked = !this.checkboxChecked;
          })
        }

        // 双按钮：默认取消左/确认右；confirmOnLeft 时确认左/取消右（0.196.10 登录引导）
        Row({ space: 10 }) {
          if (this.confirmOnLeft) {
            this.confirmButtonBuilder()
            this.cancelButtonBuilder()
          } else {
            this.cancelButtonBuilder()
            this.confirmButtonBuilder()
          }
        }
        .width('100%')
        .margin({ top: 16 })
      }
      // ★ 0.225.2 用户实测 PC 端太宽：88% 在宽屏被拉满——改断点制（手机 86% / 平板与 PC 固定 400，UI_GUIDELINES 暂停-12 确认类对话框定式）
      .width(this.isTablet ? 400 : '86%')
      .padding(20)
      .borderRadius(RADIUS_NAV)
      .backgroundColor(this.theme.surfaceNode)
      .border({ width: 1, color: this.theme.strokeCard })
    }
  }
}
