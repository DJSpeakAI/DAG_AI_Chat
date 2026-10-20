// ============================================================
// AgreementDialog.ets — ★ 0.226.0：阅读并同意弹窗 + 协议正文查看
// ============================================================
// ★ 0.264.0 门禁拆分（协议合规修订定稿·桌面任务书照单施工）：
//   mode='basic'：首启基础门禁（总门槛）——只含《用户协议》《隐私政策》两份；
//     不同意→二次挽留「不同意将无法使用本应用」→仍不同意=退出应用（Index onReject 消费）；
//     勾选未勾选点「同意并进入」→抖动提示先勾选
//   mode='hw'：华为账号登录门禁——《华为账号用户认证协议》单独征求（外链跳转）；
//     不同意=仅取消登录不退出应用（本地三板块照用），同意=onAgree 后拉起登录
// 样式模板：ReminderDialog 同款（遮罩 + this.theme.surfaceNode 面板 + RADIUS_NAV
//   + this.theme.strokeCard 描边 + 主紫按钮）；宽度断点制（手机 88% / 平板与 PC 固定 400）
// 宿主：Index 根唯一挂载（两形态各挂一份，AgreementBridge 驱动）
// 合规：勾选框默认未勾选；协议名可点；「不同意」在左、同意主操作在右（鸿蒙规范）
// ============================================================

import { common } from '@kit.AbilityKit';
import { RADIUS_NAV, RADIUS_CONTROL, FONT_SIZE_SCREEN_TITLE, FONT_SIZE_CARD_TITLE_SM, FONT_SIZE_BODY, FONT_SIZE_CAPTION, FONT_INTER_SEMIBOLD } from '../common/DesignTokens';
import { AppTheme, connectAppTheme } from '../common/AppTheme';
import { WindowMode, connectWindowMode } from '../common/WindowMode';
import { AGREEMENT_CHECK_PREFIX, AGREEMENT_USER_NAME, AGREEMENT_PRIVACY_NAME, AGREEMENT_HUAWEI_NAME, HUAWEI_ACCOUNT_AGREEMENT_URL, USER_AGREEMENT_SECTIONS, PRIVACY_SECTIONS, isPrivacySensitiveSection } from '../utils/Agreement';

@ComponentV2
export struct AgreementDialog {
  theme: AppTheme = connectAppTheme();
  @Param visible: boolean = false;
  @Param mode: string = 'basic';           // 'basic'=首启基础门禁 / 'hw'=华为协议登录门禁
  @Event onAgree: () => void = () => {};
  @Event onReject: () => void = () => {};
  @Local checked: boolean = false;        // 默认未勾选（合规红线）
  @Local viewing: number = -1;            // -1=主面板 0=用户协议正文 1=隐私政策正文
  @Local stage: number = 0;               // ★ 0.264.0：0=主面板 1=不同意挽留（仅 basic 形态）
  @Local shakeX: number = 0;              // ★ 0.264.0：未勾选点同意的抖动偏移
  @Local windowMode: WindowMode = connectWindowMode(); // ★ @ObservedV2 实例须挂 @Local（@Computed 依赖链真机可靠）
  @Computed get isTablet(): boolean {
    return this.windowMode.isTablet;
  }
  @Computed get isHwMode(): boolean {
    return this.mode === 'hw';
  }

  // 每次弹出重置为默认未勾选态
  @Monitor('visible')
  onVisibleChange(): void {
    if (this.visible) {
      this.checked = false;
      this.viewing = -1;
      this.stage = 0;
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

  // ★ 0.264.0：勾选未勾选点「同意并进入」的抖动负反馈（逐帧偏移，末尾归零）
  shake(): void {
    const seq: number[] = [8, -8, 6, -6, 3, -3, 0];
    for (let i = 0; i < seq.length; i++) {
      setTimeout(() => {
        this.shakeX = seq[i];
      }, 40 * i);
    }
  }

  // basic 主面板——点「不同意，退出」/遮罩 → 进挽留视图（二次确认，防误触直接退出）
  requestReject(): void {
    if (this.isHwMode) {
      this.onReject(); // hw 门禁：不同意仅取消登录，无需挽留
      return;
    }
    this.stage = 1;
  }

  // basic 主面板——点「同意并进入」：未勾选先抖动提示；已勾选走同意
  requestAgree(): void {
    if (!this.isHwMode && !this.checked) {
      this.shake();
      return;
    }
    this.onAgree();
  }

  build() {
    if (this.visible) {
      // 遮罩（basic=不同意挽留入口；hw=不同意取消登录）
      Column() {
        Blank()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.overlay)
      .onClick(() => {
        this.requestReject();
      })

      // 面板
      Column() {
        if (this.viewing < 0) {
          if (this.isHwMode) {
            this.hwPanel()
          } else if (this.stage === 0) {
            this.mainPanel()
          } else {
            this.retainPanel()
          }
        } else {
          this.textPanel()
        }
      }
      .width(this.isTablet ? 400 : '88%')
      .padding(20)
      .borderRadius(RADIUS_NAV)
      .backgroundColor(this.theme.surfaceNode)
      .border({ width: 1, color: this.theme.strokeCard })
    }
  }

  // ============ basic 形态：首启基础门禁（两份协议） ============
  @Builder
  mainPanel() {
    Text('阅读并同意')
      .fontSize(FONT_SIZE_SCREEN_TITLE)
      .fontWeight(600)
      .fontColor(this.theme.textPrimary)
      .fontFamily(FONT_INTER_SEMIBOLD)
      .margin({ bottom: 10 })

    Text('为了让您放心使用，请先阅读并同意《用户协议》与《隐私政策》。DAG AI Chat 是一款本地优先的学习工具：数据默认存储在设备本地，AI 对话内容仅在您主动发起请求时传输至 AI 服务商。')
      .fontSize(FONT_SIZE_BODY)
      .lineHeight(20)
      .fontColor(this.theme.textSecondary)
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
          .fontColor(this.theme.textSecondary)
          .onClick(() => {
            this.checked = !this.checked;
          })
        Span('《' + AGREEMENT_USER_NAME + '》')
          .fontColor(this.theme.brandPrimary)
          .onClick(() => {
            this.viewing = 0;
          })
        Span('《' + AGREEMENT_PRIVACY_NAME + '》')
          .fontColor(this.theme.brandPrimary)
          .onClick(() => {
            this.viewing = 1;
          })
      }
      .fontSize(FONT_SIZE_CAPTION)
      .lineHeight(20)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)

    // 按钮组（★ 0.278.6 用户拍板：主操作「同意」在左、次操作在右——推翻原「不同意在左、主操作在右」排布）
    Row({ space: 10 }) {
      Button('同意并进入')
        .layoutWeight(1)
        .height(46)
        .fontSize(FONT_SIZE_CARD_TITLE_SM)
        .fontWeight(FontWeight.Medium)
        .backgroundColor(this.checked ? this.theme.brandPrimary : this.theme.surfaceSoft)
        .fontColor(this.checked ? this.theme.textPrimary : this.theme.textTertiary)
        .borderRadius(RADIUS_CONTROL)
        .translate({ x: this.shakeX })
        .onClick(() => {
          this.requestAgree();
        })
      Button('不同意，退出')
        .layoutWeight(1)
        .height(46)
        .fontSize(FONT_SIZE_CARD_TITLE_SM)
        .backgroundColor(this.theme.surfaceSoft)
        .fontColor(this.theme.textSecondary)
        .border({ width: 1, color: this.theme.strokeCard })
        .borderRadius(RADIUS_CONTROL)
        .onClick(() => {
          this.requestReject();
        })
    }
    .width('100%')
    .margin({ top: 18 })
  }

  // basic 形态——不同意二次挽留（仍不同意=退出应用，交 Index onReject 消费）
  @Builder
  retainPanel() {
    Text('温馨提示')
      .fontSize(FONT_SIZE_SCREEN_TITLE)
      .fontWeight(600)
      .fontColor(this.theme.textPrimary)
      .fontFamily(FONT_INTER_SEMIBOLD)
      .margin({ bottom: 10 })

    Text('不同意将无法使用本应用。《用户协议》与《隐私政策》说明了本应用的服务方式与信息处理规则，数据默认存储在设备本地。')
      .fontSize(FONT_SIZE_BODY)
      .lineHeight(20)
      .fontColor(this.theme.textSecondary)
      .margin({ bottom: 16 })

    Row({ space: 10 }) {
      Button('返回继续使用')
        .layoutWeight(1)
        .height(46)
        .fontSize(FONT_SIZE_CARD_TITLE_SM)
        .fontWeight(FontWeight.Medium)
        .backgroundColor(this.theme.brandPrimary)
        .fontColor(this.theme.textPrimary)
        .borderRadius(RADIUS_CONTROL)
        .onClick(() => {
          this.stage = 0; // 回主面板重新选择
        })
      Button('仍不同意，退出')
        .layoutWeight(1)
        .height(46)
        .fontSize(FONT_SIZE_CARD_TITLE_SM)
        .backgroundColor(this.theme.surfaceSoft)
        .fontColor(this.theme.textSecondary)
        .border({ width: 1, color: this.theme.strokeCard })
        .borderRadius(RADIUS_CONTROL)
        .onClick(() => {
          this.onReject(); // Index 消费=退出应用
        })
    }
    .width('100%')
    .margin({ top: 18 })
  }

  // ============ hw 形态：华为账号登录门禁 ============
  @Builder
  hwPanel() {
    Text('华为账号登录')
      .fontSize(FONT_SIZE_SCREEN_TITLE)
      .fontWeight(600)
      .fontColor(this.theme.textPrimary)
      .fontFamily(FONT_INTER_SEMIBOLD)
      .margin({ bottom: 10 })

    Text('登录前请阅读并同意')
      .fontSize(FONT_SIZE_BODY)
      .fontColor(this.theme.textSecondary)
      .margin({ bottom: 12 })

    // 协议名（外链跳转华为官方页面）
    Text('《' + AGREEMENT_HUAWEI_NAME + '》')
      .fontSize(FONT_SIZE_BODY)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.theme.brandPrimary)
      .margin({ bottom: 12 })
      .onClick(() => {
        this.openHuaweiAgreement();
      })

    Text('不同意仅无法使用华为账号登录及 AI 对话、云同步等功能；单词库、知识库、卡片复习等本地功能不受影响，也不会退出应用。')
      .fontSize(FONT_SIZE_CAPTION)
      .lineHeight(20)
      .fontColor(this.theme.textTertiary)
      .margin({ bottom: 4 })

    Row({ space: 10 }) {
      Button('同意并登录')
        .layoutWeight(1)
        .height(46)
        .fontSize(FONT_SIZE_CARD_TITLE_SM)
        .fontWeight(FontWeight.Medium)
        .backgroundColor(this.theme.brandPrimary)
        .fontColor(this.theme.textPrimary)
        .borderRadius(RADIUS_CONTROL)
        .onClick(() => {
          this.onAgree(); // Index 消费=markHwAgreed+拉起登录
        })
      Button('不同意')
        .layoutWeight(1)
        .height(46)
        .fontSize(FONT_SIZE_CARD_TITLE_SM)
        .backgroundColor(this.theme.surfaceSoft)
        .fontColor(this.theme.textSecondary)
        .border({ width: 1, color: this.theme.strokeCard })
        .borderRadius(RADIUS_CONTROL)
        .onClick(() => {
          this.onReject(); // 仅取消登录，不退出应用
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
        .fontColor(this.theme.textPrimary)
        .fontFamily(FONT_INTER_SEMIBOLD)
        .layoutWeight(1)
      Text('返回')
        .fontSize(FONT_SIZE_CAPTION)
        .fontColor(this.theme.brandPrimary)
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
            .fontColor(isPrivacySensitiveSection(sec) ? this.theme.textPrimary : this.theme.textSecondary)
            .fontWeight(isPrivacySensitiveSection(sec) ? FontWeight.Medium : FontWeight.Normal)
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
