// ============================================================
// ImproveDataDialog.ets — ★ 0.226.0：体验改进计划引导弹窗（同意协议后首次弹一次）
// ============================================================
// 合规红线：体验改进计划必须「单独、非捆绑、默认关」——不得塞进必选同意框。
// 故在用户完成协议同意后，单独弹此卡一次询问；选择即记忆（AgreementStore.improvePromptShown）。
// 样式模板：ReminderDialog 同款（遮罩 + this.theme.surfaceNode 面板 + RADIUS_NAV + this.theme.strokeCard + 主紫按钮）
// 宿主：Index 根唯一挂载（bridge.improveVisible 驱动）
// ============================================================

import { RADIUS_NAV, RADIUS_CONTROL, FONT_SIZE_SCREEN_TITLE, FONT_SIZE_CARD_TITLE_SM, FONT_SIZE_BODY, FONT_INTER_SEMIBOLD } from '../common/DesignTokens';
import { AppTheme, connectAppTheme } from '../common/AppTheme';
import { WindowMode, connectWindowMode } from '../common/WindowMode';

@ComponentV2
export struct ImproveDataDialog {
  theme: AppTheme = connectAppTheme();
  @Param visible: boolean = false;
  @Event onJoin: () => void = () => {};
  @Event onSkip: () => void = () => {};
  @Local windowMode: WindowMode = connectWindowMode(); // ★ @ObservedV2 实例须挂 @Local（@Computed 依赖链真机可靠）
  @Computed get isTablet(): boolean {
    return this.windowMode.isTablet;
  }

  build() {
    if (this.visible) {
      // 遮罩（点击=暂不加入）
      Column() {
        Blank()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.overlay)
      .onClick(() => {
        this.onSkip();
      })

      // 面板
      Column() {
        Text('加入体验改进计划？')
          .fontSize(FONT_SIZE_SCREEN_TITLE)
          .fontWeight(600)
          .fontColor(this.theme.textPrimary)
          .fontFamily(FONT_INTER_SEMIBOLD)
          .margin({ bottom: 10 })

        Text('在您单独同意后，我们会收集匿名的功能使用频次（仅功能点击次数），不含任何对话内容、学习内容或个人信息，仅用于了解哪些功能被使用、优化产品优先级。可随时在「设置 → 关于」关闭。')
          .fontSize(FONT_SIZE_BODY)
          .lineHeight(20)
          .fontColor(this.theme.textSecondary)
          .margin({ bottom: 16 })

        Text('默认关闭，需您明确选择才会开启。')
          .fontSize(FONT_SIZE_BODY)
          .lineHeight(20)
          .fontColor(this.theme.textTertiary)
          .margin({ bottom: 16 })

        // ★ 0.278.6 用户拍板：主操作「加入」在左、次操作「暂不加入」在右（与协议弹窗同排布）
        Row({ space: 10 }) {
          Button('加入')
            .layoutWeight(1)
            .height(46)
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(this.theme.brandPrimary)
            .fontColor(this.theme.textPrimary)
            .borderRadius(RADIUS_CONTROL)
            .onClick(() => {
              this.onJoin();
            })
          Button('暂不加入')
            .layoutWeight(1)
            .height(46)
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .backgroundColor(this.theme.surfaceSoft)
            .fontColor(this.theme.textSecondary)
            .border({ width: 1, color: this.theme.strokeCard })
            .borderRadius(RADIUS_CONTROL)
            .onClick(() => {
              this.onSkip();
            })
        }
        .width('100%')
      }
      .width(this.isTablet ? 400 : '88%')
      .padding(20)
      .borderRadius(RADIUS_NAV)
      .backgroundColor(this.theme.surfaceNode)
      .border({ width: 1, color: this.theme.strokeCard })
    }
  }
}