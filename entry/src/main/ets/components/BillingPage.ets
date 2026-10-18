// BillingPage.ets — 账单页（★ 0.248.0 改版=司忆点中心，用户拍板；★ 0.248.5 有效期取消+布局重排）
// 入口：边栏「统计」下方「账单」
// 终态：司忆点资产卡（余额+等级头衔+嘉奖/充能两池明细）→ 充能 SP 两档（¥9.9→200万 / ¥19→400万，IAP 占位）
//   → SP 扣点规则（先扣嘉奖→充能+按包退款）→ 获取途径 → 兑换码（+100 万嘉奖SP）→ 记录 → 发票指路
// ★ 0.248.5：SP 有效期全取消（永久）；口径统一「嘉奖」（禁「赠送」字样）；嘉奖 SP=嘉奖池+原赠送池合计
// ★ 0.248.0：会员/免费试用/云同步叙事全部退场（用户拍板「只有一种充值路径，其他会员什么的都没有，
//   云同步不用管默认全设备开启」）——isVip/试用打戳逻辑代码保留（云同步守卫仍依赖），仅本页 UI 不再呈现

import { SubscriptionStore, connectSubscription, redeemCode, stampFreeTrialOnLogin,
  SiyiPointStore, connectSiyiPoints, siyiLevelTitle, SIYI_REDEEM_SP,
  SignInStore, connectSignIn, siyiBalanceDisplay,

  StatisticsStore, connectStatistics, getStatDays } from '../common/ChatModel';
import { HuaweiAccountStore, connectHuaweiAccount, loginWithHuaweiID, AUTH_CANCELLED_TIP } from '../utils/HuaweiAccountUtil'; // ★ 0.194.0：兑换前置登录；★ 0.196.9：取消登录静默
import { ReminderDialog } from './ReminderDialog'; // ★ 0.195.0：首登欢迎自定义弹窗（与首页同款）
import { common } from '@kit.AbilityKit'; // ★ 0.194.0：loginWithHuaweiID 的 context 类型
import { BG_APP, SURFACE_NODE, SURFACE_SOFT, BRAND_PRIMARY, BRAND_SECONDARY, TEXT_PRIMARY, TEXT_SECONDARY, TEXT_TERTIARY, STROKE_CARD, RADIUS_CONTROL, RADIUS_NAV, FONT_SIZE_SCREEN_TITLE, FONT_SIZE_CARD_TITLE_SM, FONT_SIZE_CAPTION, FONT_SIZE_BODY } from '../common/DesignTokens';
import { connectGlobalSettingsShared } from './GlobalSettingsDialog'; // ★ 0.230.0：返回键优先关设置弹窗
import { BG_CANVAS } from '../common/DesignTokens'; // ★ 0.230.0

@ComponentV2
export struct BillingPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  subscription: SubscriptionStore = connectSubscription();
  siyi: SiyiPointStore = connectSiyiPoints(); // ★ 0.248.0：司忆点资产（三池余额+礼包标记）
  signIn: SignInStore = connectSignIn(); // ★ 0.259.0：补签券持有量（资产卡展示）
  statStore: StatisticsStore = connectStatistics(); // ★ 0.248.0：等级推导数据源（累计学习天数）
  account: HuaweiAccountStore = connectHuaweiAccount(); // ★ 0.194.0：兑换前置登录（未登录不允许兑换）
  @Local redeemInput: string = '';
  @Local redeemResult: string = ''; // ''=无提示 / 'ok' / 'invalid' / 'used'
  @Local isLoggingIn: boolean = false; // ★ 0.194.0：登录中防重复点击


  // ★ 0.248.0：资产卡数据
  learnDays(): number {
    return getStatDays(this.statStore).length; // 累计学习天数=有学习活动的天数
  }

  levelTitle(): string {
    return siyiLevelTitle(this.learnDays());
  }

  spPoolText(): string {
    let lines: string[] = [];
    // ★ 0.248.5：有效期取消+口径统一——嘉奖 SP=嘉奖池+原赠送池合计（永久），对外只两行
    //   ★ 0.248.7：余额口径（池=发放累计，展示=发放-消耗；扣点链路上线后显示真实可用值）
    const bonusTotal = Math.max(0, this.siyi.bonusSp - this.siyi.consumedBonusSp)
      + Math.max(0, this.siyi.giftSp - this.siyi.consumedGiftSp);
    if (bonusTotal > 0) {
      lines.push(`嘉奖 SP ${bonusTotal.toLocaleString()}（永久）`);
    }
    const permTotal = Math.max(0, this.siyi.permanentSp - this.siyi.consumedPermanentSp);
    if (permTotal > 0) {
      lines.push(`充能 SP ${permTotal.toLocaleString()}（永久）`);
    }
    if (lines.length === 0) {
      return '暂无余额——通过下方途径获取';
    }
    return lines.join('\n');
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
      // ★ 0.196.9：用户主动取消登录——静默（取消是正常行为非错误，不 toast）
      if (tip === AUTH_CANCELLED_TIP) {
        return;
      }
      if (tip !== '') {
        // ★ 0.196.12：showToast 可能抛异常（编译器警告「Function may throw exceptions」），
        //   try-catch 静默包裹（GlobalSettingsDialog.showToastSafe 同款，本页调用统一收口）
        this.showToastSafe(tip);
        return;
      }
      // ★ 0.248.1：首登欢迎弹窗已按用户要求移除（与首页同口径）；打戳保留，登录成功统一 toast
      stampFreeTrialOnLogin(this.subscription);
      this.showToastSafe('登录成功');
      // ★ 0.248.0：云同步询问弹窗移除（用户拍板「云同步不用管，默认全设备开启」）
    });
  }

  // ★ 0.196.12：showToast 静默包裹（showToast 可能抛异常——编译器警告；GlobalSettingsDialog 同款）
  showToastSafe(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1500 });
    } catch (_e) {
      // 静默失败（toast 非关键路径）
    }
  }

  doRedeem(): void {
    // ★ 0.194.0：兑换前置登录（UI 已按登录态隐藏输入框，此处兜底防绕过）
    if (!this.account.isLoggedIn) {
      this.showToastSafe('请先登录华为账号');
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
    const ok = redeemCode(this.subscription, normalized, this.siyi);
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
            // ── 司忆点资产卡（★ 0.248.0：余额+等级头衔+各池明细，替代旧订阅状态卡）──
            Column() {
              Text('司忆点')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(600)
                .fontColor(TEXT_SECONDARY)
              // ★ 0.259.0：Lv8 满级 SP 显示恒 999,999（「封神满格」纯显示层——真实余额/云同步不动）
              Text(siyiBalanceDisplay(this.siyi, this.learnDays()))
                .fontSize(28)
                .fontWeight(700)
                .fontColor(BRAND_SECONDARY)
                .margin({ top: 4 })
              Text(this.levelTitle())
                .fontSize(FONT_SIZE_BODY)
                .fontColor(TEXT_SECONDARY)
                .margin({ top: 2 })
              Text(this.spPoolText())
                .fontSize(FONT_SIZE_CAPTION)
                .lineHeight(20)
                .fontColor(TEXT_TERTIARY)
                .margin({ top: 6 })
              // ★ 0.259.0：补签券持有量（升级奖励制——与 SP 余额同屏，让「升级了」有获得感）
              if (this.signIn.makeupVouchers > 0) {
                Text(`补签券 ×${this.signIn.makeupVouchers}（等级升级奖励 · 断签时可续接连击）`)
                  .fontSize(FONT_SIZE_CAPTION)
                  .fontColor(BRAND_SECONDARY)
                  .margin({ top: 4 })
              }
              // 未登录 → 登录入口（兑换前置+新用户礼包随登录发放）
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
            .border({ width: 1, color: STROKE_CARD })
            .margin({ bottom: 12 })

            // ── 充能 SP（★ 0.248.0：两档定稿 ¥9.9→200万 / ¥19→400万，IAP 占位——用户拍板唯一充值路径）──
            // ★ 0.248.5：充能卡上移至资产卡正下方（购买入口前置，用户拍板）
            Column() {
              Text('充能 SP')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(600)
                .fontColor(TEXT_PRIMARY)
                .margin({ bottom: 10 })
              Row({ space: 10 }) {
                Column() {
                  Text('200 万 SP')
                    .fontSize(FONT_SIZE_BODY)
                    .fontColor(TEXT_PRIMARY)
                  Text('¥9.9')
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
                  this.showToastSafe('支付服务开通中，敬请期待'); // TODO-IAP：接入华为 IAP Kit ¥9.9 档
                })

                Column() {
                  Text('400 万 SP')
                    .fontSize(FONT_SIZE_BODY)
                    .fontColor(TEXT_PRIMARY)
                  Row({ space: 4 }) {
                    Text('¥19')
                      .fontSize(18)
                      .fontWeight(600)
                      .fontColor(BRAND_PRIMARY)
                    Text('更划算')
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
                  this.showToastSafe('支付服务开通中，敬请期待'); // TODO-IAP：接入华为 IAP Kit ¥19 档
                })
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)

              Text('💡 全部 SP 永久有效；支付服务开通中——华为应用内支付资格申请审核中，开通后此处可直接充能')
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

            // ── SP 扣点规则（★ 0.248.5 新增：用户拍板——先扣嘉奖再扣充能+按包退款；退款按钮待后台开通绑定）──
            Column() {
              Text('SP 扣点规则')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(600)
                .fontColor(TEXT_PRIMARY)
                .margin({ bottom: 6 })
              Text('• 消耗顺序：先扣嘉奖 SP，嘉奖用尽后自动扣充能 SP\n• 退款规则：按充能包退款——某包未消耗过任何 SP 可整包退款；该包一旦产生消耗（哪怕 1 点）即不可退款')
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

            // ── 获取途径（★ 0.248.5：下移至扣点规则之后）──
            Column() {
              Text('获取途径')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(600)
                .fontColor(TEXT_PRIMARY)
                .margin({ bottom: 6 })
              Text('• 每日签到：连签奖励递增，第 7 天起 8,000 司忆点/天\n• 司忆学习：复习与学习行为产出 19,000 司忆点/天\n• 新用户礼包：注册即赠司忆点（永久有效）\n• 兑换码：输入兑换码入账（嘉奖 SP，永久）\n• 充能：上方充值档位，充能 SP 永久有效')
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

            // ── 兑换码 ──
            Column() {
              Text('兑换码')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(600)
                .fontColor(TEXT_PRIMARY)
                .margin({ bottom: 8 })
              // ★ 0.194.0：兑换前置登录——未登录不显示输入框，先引导登录
              if (!this.account.isLoggedIn) {
                Column() {
                  Text('兑换前请先登录华为账号')
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
                  Text(`✓ 兑换成功，+${SIYI_REDEEM_SP / 10000} 万司忆点`)
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
                // ★ 0.248.0：小字脱敏（用户拍板——删「连续兑换天数顺延」句不泄露兑换码权益；冒号改逗号）
                Text('兑换码可叠加，每码仅可使用一次')
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

      }
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      // ★ 0.230.0：全局设置弹窗打开时返回键先关弹窗（共享真相源——本页原无任何返回键拦截，0.229.26 审计 B9 补全)
      const gsShared = connectGlobalSettingsShared();
      if (gsShared.visible) {
        gsShared.closeReq++;
        return true;
      }
      return false;
    })
    .backgroundColor(BG_CANVAS) // ★ 0.230.0：页面根底色对齐四主页面（0.196.5 补全——0.229.26 审计 A1 覆盖度缺口）
  }
}
