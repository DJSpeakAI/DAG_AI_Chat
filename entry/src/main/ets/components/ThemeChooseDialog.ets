// ============================================================
// ThemeChooseDialog.ets — ★ 0.262.0 新用户首启主题选择弹窗（三选一）
// ============================================================
// 触发链：新用户（needsAgreement()=true）→ 协议同意（markAgreed）→
//   theme-mode-v1 仍为空（未落盘）→ 弹出本弹窗；选择即确认即落盘，无二次确认。
// 老用户升级静默落盘深色不弹（Q4 终裁）；卸载重装=协议 key 清零=按新用户走。
// UI：标题「选择外观」+ 三张卡片（跟随系统默认高亮/深色/浅色），每卡 40vp mini
//   预览块；选中卡=主紫描边+柔面高亮；底部主按钮「进入 DAG AI Chat」。
// 宽度断点制：手机 86% / 平板 PC 固定 400（UI_GUIDELINES 六-12a，禁裸百分比）。
// 弹窗自身在选择落定前一律暗紫渲染（与协议弹窗连贯，防闪烁——新用户此时必为
//   暂深色态，直接读 theme token 即可）。
// ============================================================

import { AppTheme, ThemeMode, connectAppTheme, chooseThemeMode } from '../common/AppTheme';
import { WindowMode, connectWindowMode } from '../common/WindowMode';
import { RADIUS_CONTROL, RADIUS_NODE, FONT_SIZE_CARD_TITLE_SM, FONT_SIZE_CAPTION, FONT_SIZE_BODY, FONT_INTER_SEMIBOLD } from '../common/DesignTokens';

@ComponentV2
export struct ThemeChooseDialog {
  @Param visible: boolean = false;
  @Event onChoose: (mode: ThemeMode) => void = () => {
  };
  @Local selected: ThemeMode = 'system'; // 默认高亮「跟随系统」（任务书定稿）
  theme: AppTheme = connectAppTheme();
  windowMode: WindowMode = connectWindowMode();

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
              this.onChoose(this.selected);
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
            Column().backgroundColor('#160D26').layoutWeight(1).height('100%')
            Column().backgroundColor('#F2EEF8').layoutWeight(1).height('100%')
          }
          .width('100%')
          .height('100%')
        } else {
          Column()
            .backgroundColor(mode === 'dark' ? '#160D26' : '#F2EEF8')
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
      }
    })
  }
}
