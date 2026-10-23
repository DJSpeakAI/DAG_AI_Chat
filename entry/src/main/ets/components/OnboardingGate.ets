// ============================================================
// OnboardingGate.ets — ★ 0.303.0 首启合并门禁（协议 + 华为账号登录一屏）
// ============================================================
// 用户拍板（2026-10-23 四问全取推荐项）：
//   一屏 = 品牌区 + 三项协议勾选（均可点开：用户协议 / 隐私政策 / 华为账号用户认证协议）
//        + 主按钮「华为账号登录」（未勾选不可登录，点按抖动提示）
//        + 次级入口「暂不登录，先本地使用」（保住本地三板块，不构成强制登录）
//        + 底部「不同意，退出」（直接退出，不二次挽留）
//   登录成功 → 开云同步 → 选外观（含体验改进开关，默认关）→ 主界面。
// 合规：
//   1) 勾选前不发登录请求（官方 FAQ faqs-appgallery-2：同意前不得收集个人信息/申请权限）；
//   2) 《华为账号用户认证协议》走华为官方链接，不得以自有协议替代（FAQ faqs-account-17）；
//   3) 「不同意退出」为官方允许方式二；不得多次弹窗强制（故无二次挽留）；
//   4) 体验改进不在此屏出现——保持单独、非捆绑、默认关（移至外观页可选开关）。
// 宿主：Index 根唯一挂载（agreementBridge.promptVisible 驱动，AgreementStore 响应式校正）。
// ============================================================

import { common } from '@kit.AbilityKit';
import {
  RADIUS_CONTROL, FONT_SIZE_CARD_TITLE_SM,
  FONT_SIZE_BODY, FONT_SIZE_CAPTION, FONT_INTER_SEMIBOLD
} from '../common/DesignTokens';
import { AppTheme, connectAppTheme } from '../common/AppTheme';
import { WindowMode, connectWindowMode } from '../common/WindowMode';
import {
  AGREEMENT_CHECK_PREFIX, AGREEMENT_USER_NAME, AGREEMENT_PRIVACY_NAME, AGREEMENT_HUAWEI_NAME,
  HUAWEI_ACCOUNT_AGREEMENT_URL, USER_AGREEMENT_SECTIONS, PRIVACY_SECTIONS, isPrivacySensitiveSection
} from '../utils/Agreement';

@ComponentV2
export struct OnboardingGate {
  theme: AppTheme = connectAppTheme();
  @Param visible: boolean = false;
  @Param busy: boolean = false;
  @Param tip: string = '';
  @Event onLogin: () => void = () => {
  };
  @Event onLocalOnly: () => void = () => {
  };
  @Event onExit: () => void = () => {
  };
  @Local windowMode: WindowMode = connectWindowMode();
  @Local checked: boolean = false;      // 默认未勾选（合规红线）
  @Local viewing: number = -1;          // -1=主面板 0=用户协议正文 1=隐私政策正文
  @Local shakeX: number = 0;            // 未勾选点登录的抖动偏移
  @Local hint: string = '';             // 未勾选提示（与登录失败 tip 分开）

  @Computed get isTablet(): boolean {
    return this.windowMode.isTablet;
  }

  // 每次展示重置为默认未勾选态
  @Monitor('visible')
  onVisibleChange(): void {
    if (this.visible) {
      this.checked = false;
      this.viewing = -1;
      this.hint = '';
      this.shakeX = 0;
    }
  }

  viewSections(): string[] {
    return this.viewing === 0 ? USER_AGREEMENT_SECTIONS : PRIVACY_SECTIONS;
  }

  viewTitle(): string {
    return this.viewing === 0 ? AGREEMENT_USER_NAME : AGREEMENT_PRIVACY_NAME;
  }

  // 华为账号用户认证协议：系统浏览器打开华为官方页（不用应用内 WebView）
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

  // 未勾选点登录的抖动负反馈（逐帧偏移，末尾归零）
  shake(): void {
    const seq: number[] = [8, -8, 6, -6, 3, -3, 0];
    for (let i = 0; i < seq.length; i++) {
      setTimeout(() => {
        this.shakeX = seq[i];
      }, 40 * i);
    }
  }

  toggleChecked(): void {
    if (this.busy) {
      return;
    }
    this.checked = !this.checked;
    if (this.checked) {
      this.hint = '';
    }
  }

  requestLogin(): void {
    if (this.busy) {
      return;
    }
    if (!this.checked) {
      this.hint = '请先勾选同意上述协议';
      this.shake();
      return;
    }
    this.hint = '';
    this.onLogin();
  }

  build() {
    if (this.visible) {
      Stack({ alignContent: Alignment.Center }) {
        Column() {
          if (this.viewing < 0) {
            this.mainPanel()
          } else {
            this.textPanel()
          }
        }
        .width(this.isTablet ? 440 : '100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.bgApp)
    }
  }

  @Builder
  mainPanel() {
    Column() {
      Blank().layoutWeight(1)

      Text('DAG AI Chat')
        .fontSize(32)
        .fontWeight(FontWeight.Bold)
        .fontFamily(FONT_INTER_SEMIBOLD)
        .fontColor(this.theme.textPrimary)
      Text('你的AI学习伴侣')
        .fontSize(FONT_SIZE_CARD_TITLE_SM)
        .fontColor(this.theme.textSecondary)
        .margin({ top: 8 })
      Text('登录华为账号，学习数据多端同步')
        .fontSize(FONT_SIZE_CAPTION)
        .fontColor(this.theme.textTertiary)
        .margin({ top: 6 })

      Blank().layoutWeight(1)

      // 三项协议同一勾选行（都可点开；协议名点击不改变勾选态）
      Row({ space: 8 }) {
        if (this.checked) {
          Image($r('app.media.checkbox_on'))
            .width(18)
            .height(18)
            .onClick(() => {
              this.toggleChecked();
            })
        } else {
          Image($r('app.media.checkbox_off'))
            .width(18)
            .height(18)
            .onClick(() => {
              this.toggleChecked();
            })
        }
        Text() {
          Span(AGREEMENT_CHECK_PREFIX)
            .fontColor(this.theme.textSecondary)
            .onClick(() => {
              this.toggleChecked();
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
          Span('《' + AGREEMENT_HUAWEI_NAME + '》')
            .fontColor(this.theme.brandPrimary)
            .onClick(() => {
              this.openHuaweiAgreement();
            })
        }
        .fontSize(FONT_SIZE_CAPTION)
        .lineHeight(20)
        .layoutWeight(1)
      }
      .width('100%')
      .constraintSize({ maxWidth: 420 })
      .alignItems(VerticalAlign.Top)

      // 主按钮：未勾选=禁用视觉 + 点击抖动提示（不发起任何登录/网络请求）
      Column({ space: 3 }) {
        Text(this.busy ? '登录中…' : '华为账号登录')
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.checked ? Color.White : this.theme.textTertiary)
        Text('登录后开启云同步')
          .fontSize(FONT_SIZE_CAPTION)
          .fontColor(this.checked ? Color.White : this.theme.textTertiary)
      }
      .width('100%')
      .constraintSize({ maxWidth: 420 })
      .padding({ top: 12, bottom: 12 })
      .borderRadius(RADIUS_CONTROL)
      .backgroundColor(this.checked ? this.theme.brandPrimary : this.theme.surfaceSoft)
      .alignItems(HorizontalAlign.Center)
      .translate({ x: this.shakeX })
      .enabled(!this.busy)
      .onClick(() => {
        this.requestLogin();
      })
      .margin({ top: 16 })

      if (this.tip !== '') {
        Text(this.tip)
          .fontSize(FONT_SIZE_CAPTION)
          .lineHeight(18)
          .fontColor(this.theme.danger)
          .textAlign(TextAlign.Center)
          .constraintSize({ maxWidth: 420 })
          .margin({ top: 10 })
      } else if (this.hint !== '') {
        Text(this.hint)
          .fontSize(FONT_SIZE_CAPTION)
          .fontColor(this.theme.danger)
          .textAlign(TextAlign.Center)
          .margin({ top: 10 })
      }

      // 次级入口：不登录也能用本地三板块（与《用户协议》第 2 条一致，规避强制登录）
      Text('暂不登录，先本地使用')
        .fontSize(FONT_SIZE_BODY)
        .fontColor(this.theme.textSecondary)
        .margin({ top: 16 })
        .onClick(() => {
          if (!this.busy) {
            this.onLocalOnly();
          }
        })

      // 不同意=直接退出（官方 FAQ：不得多次弹窗强制用户操作）
      Text('不同意，退出')
        .fontSize(FONT_SIZE_CAPTION)
        .fontColor(this.theme.textTertiary)
        .margin({ top: 18 })
        .onClick(() => {
          if (!this.busy) {
            this.onExit();
          }
        })

      Blank().layoutWeight(0.3)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 16, bottom: 20 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  textPanel() {
    Row() {
      Text(this.viewTitle())
        .fontSize(FONT_SIZE_CARD_TITLE_SM)
        .fontWeight(600)
        .fontFamily(FONT_INTER_SEMIBOLD)
        .fontColor(this.theme.textPrimary)
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
        }, (_sec: string, idx: number) => `${idx}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
  }
}
