// ============================================================
// ThemeChooseDialog.ets — ★ 0.262.0 新用户首启主题选择弹窗（三选一）
// ============================================================
// 触发链：新用户（needsAgreement()=true）→ 协议同意（markAgreed）→
//   theme-mode-v1 仍为空（未落盘）→ 弹出本弹窗；主按钮点击即落盘确认，无二次确认。
// 老用户升级静默落盘深色不弹（Q4 终裁）；卸载重装=协议 key 清零=按新用户走。
// ★ 0.296.0：点选即预览——点哪张卡全局立即切到对应外观（applyMode persist=false 不落盘，
//   所见即所得；落盘+角标消除仍由主按钮统一执行）；弹窗自身随 token 即时变色。
// UI：标题「选择外观」+ 三张卡片（跟随系统默认高亮/深色/浅色），每卡 40vp mini
//   预览块；选中卡=主紫描边+柔面高亮；底部主按钮「进入 DAG AI Chat」。
// 宽度断点制：手机 86% / 平板 PC 固定 400（UI_GUIDELINES 六-12a，禁裸百分比）。
// 弹窗初始（未点选前）暗紫渲染与协议弹窗连贯（新用户此时必为暂深色态，直接读
//   theme token 即可）；点选后随 applyMode 即时切换深浅（0.296.0）。
// ============================================================

import { AppTheme, ThemeMode, connectAppTheme, chooseThemeMode, THEME_PREVIEW_DARK_BG, THEME_PREVIEW_LIGHT_BG } from '../common/AppTheme'; // ★ 0.305.1：主题样张色常量（AppTheme 单一真相源）
import { WindowMode, connectWindowMode } from '../common/WindowMode';
import { RADIUS_CONTROL, RADIUS_NODE, FONT_SIZE_CARD_TITLE_SM, FONT_SIZE_CAPTION, FONT_SIZE_BODY, FONT_INTER_SEMIBOLD } from '../common/DesignTokens';

@ComponentV2
export struct ThemeChooseDialog {
  @Param visible: boolean = false;
  @Event onChoose: (mode: ThemeMode, improve: boolean) => void = (_mode: ThemeMode, _improve: boolean) => {
  };
  @Local selected: ThemeMode = 'system'; // 默认高亮「跟随系统」（任务书定稿）
  // ★ 0.303.0：体验改进计划并入外观页（单独控件、默认关、不与必选协议混排）
  @Local improveOn: boolean = false;
  theme: AppTheme = connectAppTheme();
  windowMode: WindowMode = connectWindowMode();

  @Monitor('visible')
  onVisibleChange(): void {
    if (this.visible) {
      this.improveOn = false;
    }
  }

  build() {
    if (this.visible) {
      Stack({ alignContent: Alignment.Center }) {
        Column({ space: 16 }) {
          Text('选择外观')
            .fontSize(16)
            .fontWeight(600)
            .fontFamily(FONT_INTER_SEMIBOLD)
            .fontColor(this.theme.textPrimary)

          // 三张卡片（跟随系统/深色/浅色）
          Row({ space: 10 }) {
            this.themeCard('system', '跟随系统', '随系统深浅色自动切换', true)
            this.themeCard('dark', '深色', '暗紫经典', false)
            this.themeCard('light', '浅色', '清新明亮', false)
          }
          .width('100%')

          // ★ 0.303.0：体验改进计划（单独同意、默认关——不与必选协议混排）
          Row({ space: 10 }) {
            Column({ space: 2 }) {
              Text('加入体验改进计划')
                .fontSize(FONT_SIZE_BODY)
                .fontColor(this.theme.textPrimary)
              Text('仅收集匿名功能使用频次，不含对话与学习内容，可随时在设置中关闭')
                .fontSize(FONT_SIZE_CAPTION)
                .lineHeight(16)
                .fontColor(this.theme.textTertiary)
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.improveOn })
              .onChange((on: boolean) => {
                this.improveOn = on;
              })
          }
          .width('100%')
          .padding(10)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(this.theme.surfaceSoft)
          .alignItems(VerticalAlign.Center)

          // 主按钮（进入 DAG AI Chat——选择即确认即落盘）
          Text('进入 DAG AI Chat')
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .width('100%')
            .padding({ top: 10, bottom: 10 })
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(this.theme.brandPrimary)
            .onClick(() => {
              chooseThemeMode(this.selected);
              this.onChoose(this.selected, this.improveOn);
            })
        }
        .padding(20)
        .borderRadius(RADIUS_NODE)
        .backgroundColor(this.theme.surfaceNode)
        .width(this.windowMode.isTablet ? 400 : '86%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.overlay)
    }
  }

  // 单张主题卡：40vp mini 预览块（跟随=左暗右浅对半 / 深=暗紫底 / 浅=白底，中间小紫块示意主紫贯穿）
  @Builder
  themeCard(mode: string, title: string, subtitle: string, half: boolean) {
    Column({ space: 6 }) {
      Stack() {
        if (half) {
          Row() {
            Column().backgroundColor(THEME_PREVIEW_DARK_BG).layoutWeight(1).height('100%')
            Column().backgroundColor(THEME_PREVIEW_LIGHT_BG).layoutWeight(1).height('100%')
          }
          .width('100%')
          .height('100%')
        } else {
          Column()
            .backgroundColor(mode === 'dark' ? THEME_PREVIEW_DARK_BG : THEME_PREVIEW_LIGHT_BG)
            .width('100%')
            .height('100%')
        }
        // 主紫贯穿示意（居中小紫块）
        Column()
          .backgroundColor(this.theme.brandPrimary)
          .width(10)
          .height(10)
          .borderRadius(3)
      }
      .width('100%')
      .height(40)
      .borderRadius(RADIUS_CONTROL - 4)
      .clip(true)

      Text(title)
        .fontSize(FONT_SIZE_BODY)
        .fontWeight(this.selected === mode ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.selected === mode ? this.theme.textPrimary : this.theme.textSecondary)

      Text(subtitle)
        .fontSize(FONT_SIZE_CAPTION)
        .fontColor(this.theme.textTertiary)
    }
    .layoutWeight(1)
    .padding(10)
    .borderRadius(RADIUS_CONTROL)
    .backgroundColor(this.selected === mode ? this.theme.surfaceSoft : Color.Transparent)
    .border({
      width: this.selected === mode ? 1.5 : 1,
      color: this.selected === mode ? this.theme.strokeBrand : this.theme.strokeCard
    })
    .onClick(() => {
      if (mode === 'system' || mode === 'dark' || mode === 'light') {
        this.selected = mode;
        // ★ 0.296.0：点选即预览——全局立即切到该外观（不落盘；落盘仍由主按钮 chooseThemeMode 统一执行）
        this.theme.applyMode(mode, this.theme.systemDark, false);
      }
    })
  }
}
