// BillingPage.ets — 账单/订阅页（★ 0.194.0 用户定稿）
// 入口：边栏「统计」下方「账单」
// 定价：¥9.9/月 + ¥99/年（华为 IAP 订阅型商品，商品 ID/公钥待商户资格下来后接入，当前占位）
// 规则：登录华为账号免费试用 30 天；到期只锁云同步（其他功能 100% 可用，账号照常登录）；
//   种子用户兑换码 +90 天（200 个码，SHA256 白名单离线校验）；兑换前置登录（未登录先引导登录）
// 发票：由华为开具（用户在华为应用市场订单中心自助申请），App 内只放指路说明

import { SubscriptionStore, connectSubscription, isVip, vipExpireTime, vipDaysLeft, redeemCode, stampFreeTrialOnLogin, markWelcomeShown } from '../common/ChatModel';
import { HuaweiAccountStore, connectHuaweiAccount, loginWithHuaweiID } from '../utils/HuaweiAccountUtil'; // ★ 0.194.0：兑换前置登录
import { ReminderDialog } from './ReminderDialog'; // ★ 0.195.0：首登欢迎自定义弹窗（与首页同款）
import { common } from '@kit.AbilityKit'; // ★ 0.194.0：loginWithHuaweiID 的 context 类型
import { BG_APP, SURFACE_NODE, SURFACE_SOFT, BRAND_PRIMARY, BRAND_SECONDARY, TEXT_PRIMARY, TEXT_SECONDARY, TEXT_TERTIARY, STROKE_CARD, RADIUS_CONTROL, RADIUS_NAV, FONT_SIZE_SCREEN_TITLE, FONT_SIZE_CARD_TITLE_SM, FONT_SIZE_CAPTION, FONT_SIZE_BODY } from '../common/DesignTokens';

@ComponentV2
export struct BillingPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  subscription: SubscriptionStore = connectSubscription();
  account: HuaweiAccountStore = connectHuaweiAccount(); // ★ 0.194.0：兑换前置登录（未登录不允许兑换）
  @Local redeemInput: string = '';
  @Local redeemResult: string = ''; // ''=无提示 / 'ok' / 'invalid' / 'used'
  @Local isLoggingIn: boolean = false; // ★ 0.194.0：登录中防重复点击
  // ★ 0.195.0：订阅提醒弹窗状态（本页登录回调触发的首登欢迎）
  @Local reminderVisible: boolean = false;
  @Local reminderMode: number = 0;

  // 状态文案（四态：未开通 / 免费试用中 / 会员生效中 / 已过期）
  // ★ 0.194.0：未登录且无权益 = 未开通（引导登录送试用；已有权益的旧数据仍如实显示生效中）
  statusTitle(): string {
    if (isVip(this.subscription)) {
      const expire = vipExpireTime(this.subscription);
      const trialEnd = this.subscription.freeTrialStart > 0 ? this.subscription.freeTrialStart + 30 * 86400000 : 0;
      if (expire === trialEnd) {
        return '免费试用中';
      }
      return '会员生效中';
    }
    if (!this.account.isLoggedIn) {
      return '未开通';
    }
    return '已过期';
  }

  statusDaysText(): string {
    const days = vipDaysLeft(this.subscription);
    if (days > 0) {
      return `${days} 天后到期（${this.formatDate(vipExpireTime(this.subscription))}）`;
    }
    if (!this.account.isLoggedIn) {
      return '登录华为账号，免费试用 30 天';
    }
    return '云同步已停用，订阅后恢复';
  }

  formatDate(ts: number): string {
    const d = new Date(ts);
    return `${d.getFullYear()}-${`${d.getMonth() + 1}`.padStart(2, '0')}-${`${d.getDate()}`.padStart(2, '0')}`;
  }

  historyList(): string[] {
    try {
      return JSON.parse(this.subscription.purchaseHistory) as string[];
    } catch (_e) {
      return [];
    }
  }

  // ★ 0.194.0：账单页登录（兑换/试用的前置条件）——成功后统一打 30 天试用戳
  doLoginFromBilling(): void {
    if (this.isLoggingIn) {
      return;
    }
    this.isLoggingIn = true;
    const context = this.getUIContext().getHostContext() as common.Context;
    loginWithHuaweiID(context).then((tip: string) => {
      this.isLoggingIn = false;
      if (tip !== '') {
        this.getUIContext().getPromptAction().showToast({ message: tip });
        return;
      }
      // ★ 0.195.0：首次登录弹欢迎弹窗（与首页同款 ReminderDialog）；重复登录简短 toast
      if (stampFreeTrialOnLogin(this.subscription)) {
        markWelcomeShown(this.subscription); // 弹出即记账（仅 1 次）
        this.reminderMode = 0;
        this.reminderVisible = true;
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '登录成功' });
      }
    });
  }

  doRedeem(): void {
    // ★ 0.194.0：兑换前置登录（UI 已按登录态隐藏输入框，此处兜底防绕过）
    if (!this.account.isLoggedIn) {
      this.getUIContext().getPromptAction().showToast({ message: '请先登录华为账号' });
      return;
    }
    if (this.redeemInput.trim().length === 0) {
      return;
    }
    // 已用码检测（区分无效码与重复码）
    let used: string[] = [];
    try {
      used = JSON.parse(this.subscription.redeemedCodes) as string[];
    } catch (_e) {
      used = [];
    }
    const normalized = this.redeemInput.trim().toUpperCase();
    const ok = redeemCode(this.subscription, normalized);
    this.redeemResult = ok ? 'ok' : (used.indexOf(normalized) >= 0 ? 'used' : 'invalid');
    if (ok) {
      this.redeemInput = '';
    }
  }

  @Builder
  topBar() {
    Row() {
      Button('←')
        .fontSize(18)
        .backgroundColor(Color.Transparent)
        .fontColor(TEXT_PRIMARY)
        .padding({ left: 4, right: 4 })
        .margin({ right: 4 })
        .onClick(() => {
          this.pathStack.pop();
        })
      Text('账单')
        .fontSize(FONT_SIZE_SCREEN_TITLE)
        .fontWeight(600)
        .fontColor(TEXT_PRIMARY)
      Blank()
        .layoutWeight(1)
    }
    .width('100%')
  }

  build() {
    NavDestination() {
      // ★ 0.195.0：根包 Stack——顶层挂订阅提醒弹窗（本页登录回调触发的首登欢迎）
      Stack() {
      Column() {
        this.topBar()

        Scroll() {
          Column() {
            // ── 订阅状态卡 ──
            Column() {
              Text(this.statusTitle())
                .fontSize(20)
                .fontWeight(600)
                .fontColor(isVip(this.subscription) ? BRAND_SECONDARY : TEXT_TERTIARY)
              Text(this.statusDaysText())
                .fontSize(FONT_SIZE_BODY)
                .fontColor(TEXT_SECONDARY)
                .margin({ top: 6 })
              // ★ 0.194.0：未登录 → 状态卡内直接给登录入口（登录即送 30 天试用）
              if (!this.account.isLoggedIn) {
                Button(this.isLoggingIn ? '登录中…' : '登录华为账号')
                  .fontSize(FONT_SIZE_BODY)
                  .height(40)
                  .backgroundColor(BRAND_PRIMARY)
                  .fontColor(TEXT_PRIMARY)
                  .borderRadius(RADIUS_CONTROL)
                  .margin({ top: 10 })
                  .onClick(() => {
                    this.doLoginFromBilling();
                  })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(16)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(SURFACE_SOFT)
            .border({ width: 1, color: isVip(this.subscription) ? BRAND_SECONDARY : STROKE_CARD })
            .margin({ bottom: 12 })

            // ── 权益说明 ──
            Column() {
              Text('会员权益')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(600)
                .fontColor(TEXT_PRIMARY)
                .margin({ bottom: 6 })
              Text('• 云同步：多设备对话数据实时同步（会员专属）\n• 其他全部功能永久免费：对话、词库、知识库、统计、圈注、朗读……100% 不设限')
                .fontSize(FONT_SIZE_BODY)
                .lineHeight(22)
                .fontColor(TEXT_SECONDARY)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(SURFACE_NODE)
            .margin({ bottom: 12 })

            // ── 购买区（IAP 占位：商户资格下来后接入华为应用内支付）──
            Column() {
              Text('订阅方案')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(600)
                .fontColor(TEXT_PRIMARY)
                .margin({ bottom: 10 })
              Row({ space: 10 }) {
                Column() {
                  Text('月付')
                    .fontSize(FONT_SIZE_BODY)
                    .fontColor(TEXT_PRIMARY)
                  Text('¥9.9/月')
                    .fontSize(18)
                    .fontWeight(600)
                    .fontColor(BRAND_PRIMARY)
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .padding({ top: 12, bottom: 12 })
                .borderRadius(RADIUS_CONTROL)
                .backgroundColor(SURFACE_SOFT)
                .border({ width: 1, color: STROKE_CARD })
                .onClick(() => {
                  this.getUIContext().getPromptAction().showToast({ message: '支付服务开通中，敬请期待' }); // TODO-IAP：接入华为 IAP Kit 月订阅商品
                })

                Column() {
                  Text('年付')
                    .fontSize(FONT_SIZE_BODY)
                    .fontColor(TEXT_PRIMARY)
                  Row({ space: 4 }) {
                    Text('¥99/年')
                      .fontSize(18)
                      .fontWeight(600)
                      .fontColor(BRAND_PRIMARY)
                    Text('省¥19.8')
                      .fontSize(FONT_SIZE_CAPTION)
                      .fontColor(BRAND_SECONDARY)
                  }
                  .margin({ top: 4 })
                }
                .layoutWeight(1)
                .padding({ top: 12, bottom: 12 })
                .borderRadius(RADIUS_CONTROL)
                .backgroundColor(SURFACE_SOFT)
                .border({ width: 1, color: BRAND_SECONDARY })
                .onClick(() => {
                  this.getUIContext().getPromptAction().showToast({ message: '支付服务开通中，敬请期待' }); // TODO-IAP：接入华为 IAP Kit 年订阅商品
                })
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)

              Text('💡 支付服务开通中——华为应用内支付资格申请审核中，开通后此处可直接订阅')
                .fontSize(FONT_SIZE_CAPTION)
                .lineHeight(18)
                .fontColor(TEXT_TERTIARY)
                .margin({ top: 8 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(SURFACE_NODE)
            .margin({ bottom: 12 })

            // ── 兑换码 ──
            Column() {
              Text('兑换码')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(600)
                .fontColor(TEXT_PRIMARY)
                .margin({ bottom: 8 })
              // ★ 0.194.0：兑换前置登录——未登录不显示输入框，先引导登录（登录即送 30 天试用）
              if (!this.account.isLoggedIn) {
                Column() {
                  Text('兑换前请先登录华为账号——登录即免费试用 30 天')
                    .fontSize(FONT_SIZE_CAPTION)
                    .fontColor(TEXT_TERTIARY)
                  Button(this.isLoggingIn ? '登录中…' : '登录华为账号')
                    .fontSize(FONT_SIZE_BODY)
                    .height(40)
                    .backgroundColor(BRAND_PRIMARY)
                    .fontColor(TEXT_PRIMARY)
                    .borderRadius(RADIUS_CONTROL)
                    .margin({ top: 8 })
                    .onClick(() => {
                      this.doLoginFromBilling();
                    })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              } else {
                Row({ space: 8 }) {
                  TextInput({ text: this.redeemInput, placeholder: '输入兑换码（如 DAGAI-XXXXX-XXXXX）' })
                    .layoutWeight(1)
                    .height(42)
                    .fontSize(FONT_SIZE_BODY)
                    .fontColor(TEXT_PRIMARY)
                    .placeholderColor(TEXT_TERTIARY)
                    .borderRadius(RADIUS_CONTROL)
                    .backgroundColor(SURFACE_SOFT)
                    .onChange((v: string) => {
                      this.redeemInput = v;
                      this.redeemResult = '';
                    })
                  Button('兑换')
                    .fontSize(FONT_SIZE_BODY)
                    .height(42)
                    .backgroundColor(BRAND_PRIMARY)
                    .fontColor(TEXT_PRIMARY)
                    .borderRadius(RADIUS_CONTROL)
                    .onClick(() => {
                      this.doRedeem();
                    })
                }
                .width('100%')

                if (this.redeemResult === 'ok') {
                  Text('✓ 兑换成功，已增加 90 天会员')
                    .fontSize(FONT_SIZE_CAPTION)
                    .fontColor(BRAND_SECONDARY)
                    .margin({ top: 6 })
                } else if (this.redeemResult === 'used') {
                  Text('该兑换码已被使用')
                    .fontSize(FONT_SIZE_CAPTION)
                    .fontColor(TEXT_TERTIARY)
                    .margin({ top: 6 })
                } else if (this.redeemResult === 'invalid') {
                  Text('兑换码无效，请检查输入')
                    .fontSize(FONT_SIZE_CAPTION)
                    .fontColor(TEXT_TERTIARY)
                    .margin({ top: 6 })
                }
                Text('兑换码可叠加：连续兑换天数顺延；每码仅可使用一次')
                  .fontSize(FONT_SIZE_CAPTION)
                  .fontColor(TEXT_TERTIARY)
                  .margin({ top: 6 })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(SURFACE_NODE)
            .margin({ bottom: 12 })

            // ── 历史记录 ──
            if (this.historyList().length > 0) {
              Column() {
                Text('记录')
                  .fontSize(FONT_SIZE_CARD_TITLE_SM)
                  .fontWeight(600)
                  .fontColor(TEXT_PRIMARY)
                  .margin({ bottom: 6 })
                ForEach(this.historyList(), (item: string, idx: number) => {
                  Text(item)
                    .fontSize(FONT_SIZE_BODY)
                    .fontColor(TEXT_SECONDARY)
                    .padding({ top: 4, bottom: 4 })
                }, (item: string, idx: number) => `${idx}_${item}`)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(14)
              .borderRadius(RADIUS_NAV)
              .backgroundColor(SURFACE_NODE)
              .margin({ bottom: 12 })
            }

            // ── 发票说明（用户定稿：放账单页主位置）──
            Text('💡 发票说明：本应用内支付由华为收取并开具发票——请在「华为应用市场 → 我的 → 订单」中自助申请电子发票，开票方为华为。')
              .fontSize(FONT_SIZE_CAPTION)
              .lineHeight(18)
              .fontColor(TEXT_TERTIARY)
              .padding({ left: 4, right: 4 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 24 })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .align(Alignment.TopStart)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG_APP)
      .expandSafeArea([SafeAreaType.SYSTEM])

      // ★ 0.195.0：订阅提醒弹窗（Stack 顶层；已在账单页，「去账单」仅关闭）
      ReminderDialog({
        visible: this.reminderVisible,
        mode: this.reminderMode,
        onClose: () => {
          this.reminderVisible = false;
        },
        onGoBilling: () => {
          this.reminderVisible = false; // 已在账单页，关闭即可
        }
      })
      }
    }
    .hideTitleBar(true)
  }
}
