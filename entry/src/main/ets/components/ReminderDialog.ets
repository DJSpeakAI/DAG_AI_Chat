// ReminderDialog.ets — ★ 0.195.0：订阅提醒自定义弹窗（暗紫设计语言）
// 替代系统 AlertDialog 灰弹窗（用户实测反馈：30 天试用弹窗 UI 与应用风格不符，UI 必须同步）
// 样式模板：0.190.8 隐私弹窗同款（遮罩 rgba(0,0,0,0.5) + SURFACE_NODE 面板 + RADIUS_NAV + STROKE_CARD 描边 + 主紫按钮）
// 模式：mode=0 首登欢迎（🎉 30 天试用，仅 1 次）；mode=1~7 倒计时（还剩 N 天，带「去账单」CTA）
// 宿主：Index（onPageShow 倒计时 + doLogin 欢迎）/ BillingPage（本页登录欢迎）——Stack 顶层渲染

import { SubscriptionStore, connectSubscription, vipExpireTime } from '../common/ChatModel';
import { SURFACE_NODE, BRAND_PRIMARY, TEXT_PRIMARY, TEXT_SECONDARY, STROKE_CARD, RADIUS_NAV, RADIUS_CONTROL, FONT_SIZE_SCREEN_TITLE, FONT_SIZE_CARD_TITLE_SM, FONT_SIZE_BODY, FONT_INTER_SEMIBOLD } from '../common/DesignTokens';

@ComponentV2
export struct ReminderDialog {
  @Param visible: boolean = false;
  @Param mode: number = 0; // 0=首登欢迎；1~7=剩余天数（倒计时）
  @Event onClose: () => void = () => {};
  @Event onGoBilling: () => void = () => {};
  subscription: SubscriptionStore = connectSubscription(); // 到期日自取（弹窗自包含，宿主只传 visible/mode）

  expireDateStr(): string {
    const d = new Date(vipExpireTime(this.subscription));
    return `${d.getFullYear()}-${`${d.getMonth() + 1}`.padStart(2, '0')}-${`${d.getDate()}`.padStart(2, '0')}`;
  }

  titleStr(): string {
    if (this.mode === 0) {
      return '🎉 30 天云同步试用已开启';
    }
    return this.mode === 1 ? '⏰ 云同步明天到期' : `⏰ 云同步还剩 ${this.mode} 天`;
  }

  bodyStr(): string {
    if (this.mode === 0) {
      return '登录成功！即日起 30 天内，您的对话数据可自动同步云端，多台设备保持一致。\n\n' +
        `试用期至 ${this.expireDateStr()}\n` +
        '开启路径：设置 → 云同步\n\n' + // ★ 0.195.0：⚙ emoji 已去（用户指示 UI 同步——emoji 图标全灭）
        '到期后本机数据完整保留，仅停止跨设备同步；可随时到边栏「账单」订阅或兑换续期。';
    }
    return `您的云同步服务将于 ${this.expireDateStr()} 到期。到期后本机数据完整保留，仅停止跨设备同步。\n\n` +
      '继续使用请订阅（¥9.9/月）或输入兑换码。';
  }

  build() {
    if (this.visible) {
      // 遮罩（点击关闭——纯信息展示，不怕误触；隐私弹窗同款）
      Column() {
        Blank()
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0,0,0,0.5)')
      .onClick(() => {
        this.onClose();
      })

      // 面板
      Column() {
        Text(this.titleStr())
          .fontSize(FONT_SIZE_SCREEN_TITLE)
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
          .fontFamily(FONT_INTER_SEMIBOLD)
          .margin({ bottom: 12 })

        Text(this.bodyStr())
          .fontSize(FONT_SIZE_BODY)
          .lineHeight(22)
          .fontColor(TEXT_SECONDARY)

        if (this.mode === 0) {
          Button('知道了')
            .width('100%')
            .height(48)
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(BRAND_PRIMARY)
            .fontColor(TEXT_PRIMARY)
            .borderRadius(RADIUS_CONTROL)
            .margin({ top: 16 })
            .onClick(() => {
              this.onClose();
            })
        } else {
          Row({ space: 10 }) {
            Button('知道了')
              .layoutWeight(1)
              .height(48)
              .fontSize(FONT_SIZE_CARD_TITLE_SM)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(SURFACE_NODE)
              .fontColor(TEXT_SECONDARY)
              .border({ width: 1, color: STROKE_CARD })
              .borderRadius(RADIUS_CONTROL)
              .onClick(() => {
                this.onClose();
              })
            Button('去账单')
              .layoutWeight(1)
              .height(48)
              .fontSize(FONT_SIZE_CARD_TITLE_SM)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(BRAND_PRIMARY)
              .fontColor(TEXT_PRIMARY)
              .borderRadius(RADIUS_CONTROL)
              .onClick(() => {
                this.onGoBilling();
              })
          }
          .width('100%')
          .margin({ top: 16 })
        }
      }
      .width('88%')
      .padding(20)
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
      .border({ width: 1, color: STROKE_CARD })
    }
  }
}
