// ============================================================
// AgreementDialog.ets — ★ 0.226.0：阅读并同意弹窗 + 协议正文查看
// ============================================================
// 样式模板：ReminderDialog 同款（遮罩 rgba(0,0,0,0.5) + SURFACE_NODE 面板 + RADIUS_NAV
//   + STROKE_CARD 描边 + 主紫按钮）；宽度断点制（手机 88% / 平板与 PC 固定 400）
// 宿主：Index 根唯一挂载（首启自动弹 / 边栏登录 / 设置云同步 三入口共用同一弹窗）
// 合规：勾选框默认未勾选；协议名可点；「暂不同意」返回原页面（不退出应用）
// ============================================================

import { common } from '@kit.AbilityKit';
import { SURFACE_NODE, SURFACE_SOFT, BRAND_PRIMARY, TEXT_PRIMARY, TEXT_SECONDARY, TEXT_TERTIARY, STROKE_CARD, RADIUS_NAV, RADIUS_CONTROL, FONT_SIZE_SCREEN_TITLE, FONT_SIZE_CARD_TITLE_SM, FONT_SIZE_BODY, FONT_SIZE_CAPTION, FONT_INTER_SEMIBOLD } from '../common/DesignTokens';
import { WindowMode, connectWindowMode } from '../common/WindowMode';
import { AGREEMENT_CHECK_PREFIX, AGREEMENT_USER_NAME, AGREEMENT_PRIVACY_NAME, AGREEMENT_HUAWEI_NAME, HUAWEI_ACCOUNT_AGREEMENT_URL, USER_AGREEMENT_SECTIONS, PRIVACY_SECTIONS } from '../utils/Agreement';

@ComponentV2
export struct AgreementDialog {
  @Param visible: boolean = false;
  @Event onAgree: () => void = () => {};
  @Event onReject: () => void = () => {};
  @Local checked: boolean = false;        // 默认未勾选（合规红线）
  @Local viewing: number = -1;            // -1=主面板 0=用户协议正文 1=隐私政策正文
  @Local windowMode: WindowMode = connectWindowMode(); // ★ @ObservedV2 实例须挂 @Local（@Computed 依赖链真机可靠）
  @Computed get isTablet(): boolean {
    return this.windowMode.isTablet;
  }

  // 每次弹出重置为默认未勾选态
  @Monitor('visible')
  onVisibleChange(): void {
    if (this.visible) {
      this.checked = false;
      this.viewing = -1;
    }
  }

  viewSections(): string[] {
    return this.viewing === 0 ? USER_AGREEMENT_SECTIONS : PRIVACY_SECTIONS;
  }

  viewTitle(): string {
    return this.viewing === 0 ? AGREEMENT_USER_NAME : AGREEMENT_PRIVACY_NAME;
  }

  // 华为账号用户认证协议：用系统浏览器打开（不用应用内 WebView）
  openHuaweiAgreement(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ctx.openLink(HUAWEI_ACCOUNT_AGREEMENT_URL).catch(() => {
        // 打开失败静默
      });
    } catch (_e) {
      // 静默
    }
  }

  build() {
    if (this.visible) {
      // 遮罩（点击=暂不同意，返回原页面）
      Column() {
        Blank()
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0,0,0,0.5)')
      .onClick(() => {
        this.onReject();
      })

      // 面板
      Column() {
        if (this.viewing < 0) {
          this.mainPanel()
        } else {
          this.textPanel()
        }
      }
      .width(this.isTablet ? 400 : '88%')
      .padding(20)
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
      .border({ width: 1, color: STROKE_CARD })
    }
  }

  @Builder
  mainPanel() {
    Text('阅读并同意')
      .fontSize(FONT_SIZE_SCREEN_TITLE)
      .fontWeight(600)
      .fontColor(TEXT_PRIMARY)
      .fontFamily(FONT_INTER_SEMIBOLD)
      .margin({ bottom: 10 })

    Text('不同意仅无法使用华为账号登录、云同步、AI 对话、导入导出、圈注提炼、划词翻译等功能；单词库与知识库的新建/浏览、卡片复习等基础功能仍可正常使用。')
      .fontSize(FONT_SIZE_BODY)
      .lineHeight(20)
      .fontColor(TEXT_SECONDARY)
      .margin({ bottom: 16 })

    // 勾选行（勾选框/前缀文字=切换勾选；协议名=查看正文，各自消费点击互不干扰）
    Row({ space: 8 }) {
      if (this.checked) {
        Image($r('app.media.checkbox_on'))
          .width(18)
          .height(18)
          .onClick(() => {
            this.checked = false;
          })
      } else {
        Image($r('app.media.checkbox_off'))
          .width(18)
          .height(18)
          .onClick(() => {
            this.checked = true;
          })
      }
      Text() {
        Span(AGREEMENT_CHECK_PREFIX)
          .fontColor(TEXT_SECONDARY)
          .onClick(() => {
            this.checked = !this.checked;
          })
        Span('《' + AGREEMENT_USER_NAME + '》')
          .fontColor(BRAND_PRIMARY)
          .onClick(() => {
            this.viewing = 0;
          })
        Span('《' + AGREEMENT_PRIVACY_NAME + '》')
          .fontColor(BRAND_PRIMARY)
          .onClick(() => {
            this.viewing = 1;
          })
        Span('《' + AGREEMENT_HUAWEI_NAME + '》')
          .fontColor(BRAND_PRIMARY)
          .onClick(() => {
            this.openHuaweiAgreement();
          })
      }
      .fontSize(FONT_SIZE_CAPTION)
      .lineHeight(20)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)

    // 按钮组（次级在左、主操作在右；鸿蒙规范）
    Row({ space: 10 }) {
      Button('暂不同意')
        .layoutWeight(1)
        .height(46)
        .fontSize(FONT_SIZE_CARD_TITLE_SM)
        .backgroundColor(SURFACE_SOFT)
        .fontColor(TEXT_SECONDARY)
        .border({ width: 1, color: STROKE_CARD })
        .borderRadius(RADIUS_CONTROL)
        .onClick(() => {
          this.onReject();
        })
      Button('同意并继续')
        .layoutWeight(1)
        .height(46)
        .fontSize(FONT_SIZE_CARD_TITLE_SM)
        .fontWeight(FontWeight.Medium)
        .backgroundColor(this.checked ? BRAND_PRIMARY : SURFACE_SOFT)
        .fontColor(this.checked ? TEXT_PRIMARY : TEXT_TERTIARY)
        .borderRadius(RADIUS_CONTROL)
        .enabled(this.checked)
        .onClick(() => {
          this.onAgree();
        })
    }
    .width('100%')
    .margin({ top: 18 })
  }

  @Builder
  textPanel() {
    Row() {
      Text(this.viewTitle())
        .fontSize(FONT_SIZE_CARD_TITLE_SM)
        .fontWeight(600)
        .fontColor(TEXT_PRIMARY)
        .fontFamily(FONT_INTER_SEMIBOLD)
        .layoutWeight(1)
      Text('返回')
        .fontSize(FONT_SIZE_CAPTION)
        .fontColor(BRAND_PRIMARY)
        .onClick(() => {
          this.viewing = -1;
        })
    }
    .width('100%')
    .margin({ bottom: 12 })

    Scroll() {
      Column() {
        ForEach(this.viewSections(), (sec: string) => {
          Text(sec)
            .fontSize(FONT_SIZE_BODY)
            .lineHeight(21)
            .fontColor(TEXT_SECONDARY)
            .width('100%')
            .margin({ bottom: 10 })
        }, (sec: string, idx: number) => `${idx}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(this.isTablet ? 400 : 320)
    .scrollBar(BarState.Auto)
  }
}