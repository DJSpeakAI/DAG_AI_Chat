// BillingPage.ets — 账单页（★ 0.289.0 充能包账本版面重做）
// 版面：司忆点资产卡 → 充能 SP 两档 → 我的充能包（按包账本：几点几秒买的/剩余/退款）→
//   SP 扣点规则 → 获取途径 → 兑换码 → 发票说明；左上角「账单」标题已删（用户拍板——
//   手机左滑返回手势即出口，标题冗余）；旧「记录」文本卡删除（信息被充能包卡全量取代，数据保留）
// ★ 0.289.0 包级退款政策（用户拍板三条）：①嘉奖 SP 先扣 ②充能按购买顺序 FIFO 扣包
//   ③整包未消耗 1 点=可退（申请退款=弹订单凭据+引导华为应用市场）；退款由开发者后台执行；
//   退款到账后 app 进本页自动感知核销（queryPurchaseRecords 检测 revocationTime，用户零操作）

import { SubscriptionStore, connectSubscription, redeemCode, onLoginAccountHooks,
  SiyiPointStore, connectSiyiPoints, siyiLevelTitle, SIYI_REDEEM_SP,
  SignInStore, connectSignIn, siyiBalanceDisplay,
  IAP_PRODUCT_SP_200W, IAP_PRODUCT_SP_400W,
  IapPackage, parseIapPackages, ensureIapPackagesMigrated,
  freezePackageUntil, REFUND_FREEZE_MS, frozenAvailableSp,

  StatisticsStore, connectStatistics, getStatDays,
  pullSpAdminCommands } from '../common/ChatModel';
import { HuaweiAccountStore, connectHuaweiAccount, loginWithHuaweiID, AUTH_CANCELLED_TIP } from '../utils/HuaweiAccountUtil'; // ★ 0.194.0：兑换前置登录；★ 0.196.9：取消登录静默
import { needsHwAgreement, connectAgreementBridge } from '../utils/Agreement'; // ★ 0.264.0：华为协议门禁（基础协议由首页未同意态承担，0.305.0）
import { IapOutcome, purchaseSp, queryIapSpPrices, recoverPendingPurchases, detectRefundedIapPurchases, pullRefundMarks } from '../utils/IapUtil';
import { requireSiyiGate } from '../utils/SiyiGate'; // ★ 0.293.0：SP 云同步门卫（充值购买前置闸）
import { common } from '@kit.AbilityKit'; // ★ 0.194.0：loginWithHuaweiID 的 context 类型
import { RADIUS_CONTROL, RADIUS_NAV, FONT_SIZE_CARD_TITLE_SM, FONT_SIZE_CAPTION, FONT_SIZE_BODY } from '../common/DesignTokens';
import { AppTheme, connectAppTheme } from '../common/AppTheme';
import { connectGlobalSettingsShared } from './GlobalSettingsDialog'; // ★ 0.230.0：返回键优先关设置弹窗
import { WindowMode, connectWindowMode } from '../common/WindowMode'; // ★ 0.288.2：购买结果提示框宽度断点制

@ComponentV2
export struct BillingPage {
  theme: AppTheme = connectAppTheme();
  @Param pathStack: NavPathStack = new NavPathStack();
  subscription: SubscriptionStore = connectSubscription();
  siyi: SiyiPointStore = connectSiyiPoints(); // ★ 0.248.0：司忆点资产（三池余额+礼包标记）
  signIn: SignInStore = connectSignIn(); // ★ 0.259.0：补签券持有量（资产卡展示）
  statStore: StatisticsStore = connectStatistics(); // ★ 0.248.0：等级推导数据源（累计学习天数）
  account: HuaweiAccountStore = connectHuaweiAccount(); // ★ 0.194.0：兑换前置登录（未登录不允许兑换）
  @Local redeemInput: string = '';
  @Local redeemResult: string = ''; // ''=无提示 / 'ok' / 'invalid' / 'used'
  @Local isLoggingIn: boolean = false; // ★ 0.194.0：登录中防重复点击
  @Local price200w: string = '¥9.9';  // ★ 0.261.0：展示价（queryProducts 拉取，保底 ¥9.9）
  @Local price400w: string = '¥19';   // ★ 0.261.0：展示价（queryProducts 拉取，保底 ¥19）
  @Local purchasing: string = '';     // ★ 0.261.0：购买中商品 ID（''=空闲；防重复点击节流）
  @Local purchaseNotice: string = ''; // ★ 0.288.2：购买/补单/核销结果提示框正文（''=隐藏；付款级结果弹框展示）
  @Local refundTok: string = '';      // ★ 0.289.0：退款申请弹窗目标包 token（''=隐藏）
  @Local windowMode: WindowMode = connectWindowMode(); // ★ 0.288.2：提示框宽度断点制（@Computed 源状态 @Local 挂载铁律）
  @Computed get isTablet(): boolean {
    return this.windowMode.isTablet;
  }

  // ★ 0.261.0：进场静默拉商品展示价 + 补单（登录态才有未完成单；均不阻塞 UI）
  // ★ 0.289.0：包账本迁移重建（旧池级账拆成独立包）+ 退款自动感知核销（用户零操作）
  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    queryIapSpPrices(ctx).then((prices: Record<string, string>) => {
      const p1 = prices[IAP_PRODUCT_SP_200W];
      if (p1 !== undefined && p1.length > 0) {
        this.price200w = p1;
      }
      const p2 = prices[IAP_PRODUCT_SP_400W];
      if (p2 !== undefined && p2.length > 0) {
        this.price400w = p2;
      }
    });
    if (this.account.isLoggedIn) {
      // 未完成单恢复（支付成功但消耗确认中断的场景）
      recoverPendingPurchases(ctx).then((recovered: number) => {
        if (recovered > 0) {
          this.purchaseNotice = `检测到未完成的充值订单，已自动补入账 ${recovered / 10000} 万 SP（之前的支付没有白付）`;
        }
      });
      // ★ 0.289.0 退款自动感知：华为侧已退款的包 → 剩余 SP 自动作废核销（回本页即平账）
      detectRefundedIapPurchases(ctx).then((writtenOff: number) => {
        if (writtenOff > 0) {
          this.purchaseNotice = `检测到已退款的充能包，已自动核销 ${writtenOff / 10000} 万 SP（退款金额以华为订单为准）`;
        }
      });
      // ★ 0.291.0 云端退款标记拉取（可靠主链路——本地 queryPurchases 查不到已发货消耗型订单）：
      // 云函数 refund-events 查询命中 → 核销作废；失败静默（云函数未部署=常态）
      pullRefundMarks().then((writtenOff: number) => {
        if (writtenOff > 0) {
          this.purchaseNotice = `该充能包退款已到账，已自动核销 ${writtenOff / 10000} 万 SP（退款金额以华为订单为准）`;
        }
      });
      // ★ 0.301.0：账单页进场拉 SP 数据台运营指令（与退款标记同款三时机之一；静默零影响）
      pullSpAdminCommands();
    }
  }

  // ★ 0.261.0：SP 充能购买流——登录前置 → 拉收银台 → 到账弹框（取消/失败按分类提示）
  doPurchase(productId: string): void {
    if (this.purchasing !== '') {
      return; // 购买进行中防重复点击
    }
    if (!this.account.isLoggedIn) {
      this.showToastSafe('请先登录华为账号');
      return;
    }
    // ★ 0.293.0：SP 云同步门卫（充值购 SP 也是 SP 变动——账本云端对齐才放行，防离线充值账对不上）
    if (!requireSiyiGate()) {
      return;
    }
    this.purchasing = productId;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    purchaseSp(ctx, productId).then((outcome: IapOutcome) => {
      this.purchasing = '';
      if (outcome.state === 'cancelled') {
        this.showToastSafe('已取消'); // 用户主动取消——轻提示即可，不打扰
        return;
      }
      if (outcome.state === 'ok') {
        this.purchaseNotice = outcome.spAmount > 0
          ? `已到账 ${outcome.spAmount / 10000} 万 SP`
          : outcome.message; // 重复单等零额成功态
      } else {
        this.purchaseNotice = outcome.message; // 失败原因弹框展示（0.288.2 用户实测：toast 看不到）
      }
    }).catch(() => {
      this.purchasing = '';
      this.purchaseNotice = '支付流程异常，请重试';
    });
  }

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
    const bonusTotal = Math.max(0, this.siyi.bonusSp - this.siyi.consumedBonusSp)
      + Math.max(0, this.siyi.giftSp - this.siyi.consumedGiftSp);
    if (bonusTotal > 0) {
      lines.push(`嘉奖 SP ${bonusTotal.toLocaleString()}（永久）`);
    }
    // ★ 0.291.0：充能行=可用口径（排除退款申请冻结包额度——与 siyiTotalSp/consumeSiyiSp 三处同源，
    //   防「展示可用但发消息余额不足」矛盾）；冻结额单列说明行
    const frozen = frozenAvailableSp(this.siyi);
    const permTotal = Math.max(0, this.siyi.permanentSp - this.siyi.consumedPermanentSp - frozen);
    if (permTotal > 0) {
      lines.push(`充能 SP ${permTotal.toLocaleString()}（永久）`);
    }
    if (frozen > 0) {
      lines.push(`退款处理中 SP ${frozen.toLocaleString()}（锁定不可用）`);
    }
    if (lines.length === 0) {
      return '暂无余额——通过下方途径获取';
    }
    return lines.join('\n');
  }

  // ── ★ 0.289.0 充能包账本 ──
  pkgList(): IapPackage[] {
    ensureIapPackagesMigrated(this.subscription, this.siyi); // 幂等写销旧测试充能账（★ 0.290.2 唯一触发点；上线前随函数一并删除）
    return parseIapPackages(this.siyi.iapPackages);
  }

  // 时间格式化 YYYY-M-D HH:MM:SS（账本要求精确到秒；ts=0 迁移无据=「时间未记录」）
  fmtPkgTime(ts: number): string {
    if (ts <= 0) {
      return '时间未记录';
    }
    const d = new Date(ts);
    const two = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()} ${two(d.getHours())}:${two(d.getMinutes())}:${two(d.getSeconds())}`;
  }

  pkgPriceText(pid: string): string {
    return pid === IAP_PRODUCT_SP_400W ? '¥19' : '¥9.9';
  }

  pkgAmtText(amt: number): string {
    return `${(amt / 10000).toLocaleString()} 万 SP`;
  }

  // 汇总行：共 N 包 · 累计 X 万 · 已消耗 Y 万 · 剩余 Z 万
  pkgSummaryText(): string {
    const list = this.pkgList();
    let total = 0;
    let consumed = 0;
    for (let i = 0; i < list.length; i++) {
      total += list[i].amt;
      consumed += list[i].cons;
    }
    return `共 ${list.length} 包 · 累计 ${(total / 10000).toLocaleString()} 万 · 已消耗 ${(consumed / 10000).toLocaleString()} 万 · 剩余 ${((total - consumed) / 10000).toLocaleString()} 万`;
  }

  refundTarget(): IapPackage | null {
    const list = this.pkgList();
    for (let i = 0; i < list.length; i++) {
      if (list[i].tok === this.refundTok) {
        return list[i];
      }
    }
    return null;
  }

  // ★ 0.194.0：账单页登录（兑换/试用的前置条件）——成功后统一打 30 天试用戳
  doLoginFromBilling(): void {
    if (this.isLoggingIn) {
      return;
    }
    // ★ 0.305.0：基础协议门禁=首页未同意态（唯一同意入口，未同意时进不了本页）——此处只留华为协议门禁
    if (needsHwAgreement()) {
      connectAgreementBridge().pendingAction = 'login';
      connectAgreementBridge().hwPromptVisible = true;
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
        this.showToastSafe(tip);
        return;
      }
      onLoginAccountHooks(); // ★ 0.305.1：登录后账号钩子
      this.showToastSafe('登录成功');
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

  build() {
    NavDestination() {
      // ★ 0.195.0：根包 Stack——顶层挂订阅提醒/购买/退款弹窗
      Stack() {
      Column() {
        // ★ 0.289.0：左上角「账单」标题删除（用户拍板——左滑返回手势即出口）；顶部仅留呼吸间距
        Scroll() {
          Column() {
            // ── 司忆点资产卡 ──
            Column() {
              Text('司忆点')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(600)
                .fontColor(this.theme.textSecondary)
              Text(siyiBalanceDisplay(this.siyi, this.learnDays()))
                .fontSize(28)
                .fontWeight(700)
                .fontColor(this.theme.brandSecondary)
                .margin({ top: 4 })
              Text(this.levelTitle())
                .fontSize(FONT_SIZE_BODY)
                .fontColor(this.theme.textSecondary)
                .margin({ top: 2 })
              Text(this.spPoolText())
                .fontSize(FONT_SIZE_CAPTION)
                .lineHeight(20)
                .fontColor(this.theme.textTertiary)
                .margin({ top: 6 })
              if (this.signIn.makeupVouchers > 0) {
                Text(`补签券 ×${this.signIn.makeupVouchers}（等级升级奖励 · 断签时可续接连击）`)
                  .fontSize(FONT_SIZE_CAPTION)
                  .fontColor(this.theme.brandSecondary)
                  .margin({ top: 4 })
              }
              if (!this.account.isLoggedIn) {
                Button(this.isLoggingIn ? '登录中…' : '登录华为账号')
                  .fontSize(FONT_SIZE_BODY)
                  .height(40)
                  .backgroundColor(this.theme.brandPrimary)
                  .fontColor(this.theme.textPrimary)
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
            .backgroundColor(this.theme.surfaceSoft)
            .border({ width: 1, color: this.theme.strokeCard })
            .margin({ bottom: 12 })

            // ── 充能 SP（两档定稿 ¥9.9→200万 / ¥19→400万；华为 IAP 真实购买）──
            Column() {
              Text('充能 SP')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(600)
                .fontColor(this.theme.textPrimary)
                .margin({ bottom: 10 })
              Row({ space: 10 }) {
                Column() {
                  Text('200 万 SP')
                    .fontSize(FONT_SIZE_BODY)
                    .fontColor(this.theme.textPrimary)
                  Text(this.purchasing === IAP_PRODUCT_SP_200W ? '支付中…' : this.price200w)
                    .fontSize(18)
                    .fontWeight(600)
                    .fontColor(this.theme.brandPrimary)
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .padding({ top: 12, bottom: 12 })
                .borderRadius(RADIUS_CONTROL)
                .backgroundColor(this.theme.surfaceSoft)
                .border({ width: 1, color: this.theme.strokeCard })
                .onClick(() => {
                  this.doPurchase(IAP_PRODUCT_SP_200W);
                })

                Column() {
                  Text('400 万 SP')
                    .fontSize(FONT_SIZE_BODY)
                    .fontColor(this.theme.textPrimary)
                  Row({ space: 4 }) {
                    Text(this.purchasing === IAP_PRODUCT_SP_400W ? '支付中…' : this.price400w)
                      .fontSize(18)
                      .fontWeight(600)
                      .fontColor(this.theme.brandPrimary)
                    Text('更划算')
                      .fontSize(FONT_SIZE_CAPTION)
                      .fontColor(this.theme.brandSecondary)
                  }
                  .margin({ top: 4 })
                }
                .layoutWeight(1)
                .padding({ top: 12, bottom: 12 })
                .borderRadius(RADIUS_CONTROL)
                .backgroundColor(this.theme.surfaceSoft)
                .border({ width: 1, color: this.theme.brandSecondary })
                .onClick(() => {
                  this.doPurchase(IAP_PRODUCT_SP_400W);
                })
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)

              Text('💡 全部 SP 永久有效；支付由华为应用内支付收银台完成，可在「华为应用市场 → 我的 → 订单」中查看')
                .fontSize(FONT_SIZE_CAPTION)
                .lineHeight(18)
                .fontColor(this.theme.textTertiary)
                .margin({ top: 8 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(this.theme.surfaceNode)
            .margin({ bottom: 12 })

            // ── ★ 0.289.0 我的充能包（按包账本：几点几秒买的/剩余/退款——取代旧「记录」文本卡）──
            Column() {
              Text('我的充能包')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(600)
                .fontColor(this.theme.textPrimary)
                .margin({ bottom: 4 })
              Text(this.pkgSummaryText())
                .fontSize(FONT_SIZE_CAPTION)
                .fontColor(this.theme.textTertiary)
                .margin({ bottom: 8 })
              ForEach(this.pkgList(), (pkg: IapPackage) => {
                Column() {
                  Row() {
                    Text(`${this.pkgPriceText(pkg.pid)} · ${this.pkgAmtText(pkg.amt)}`)
                      .fontSize(FONT_SIZE_BODY)
                      .fontWeight(600)
                      .fontColor(this.theme.textPrimary)
                    Blank()
                    if (pkg.frozenUntil > Date.now()) {
                      // ★ 0.291.0 退款申请锁包中——状态标签（不可重复发起；7 天未成功自动解锁恢复可用）
                      Text(`退款处理中·剩 ${Math.max(1, Math.ceil((pkg.frozenUntil - Date.now()) / 86400000))} 天`)
                        .fontSize(FONT_SIZE_CAPTION)
                        .fontColor(this.theme.textTertiary)
                    } else if (pkg.ref === 1) {
                      Text('已退款')
                        .fontSize(FONT_SIZE_CAPTION)
                        .fontColor(this.theme.textTertiary)
                    } else if (pkg.cons === 0) {
                      Button('申请退款')
                        .fontSize(FONT_SIZE_CAPTION)
                        .height(28)
                        .padding({ left: 10, right: 10 })
                        .backgroundColor(this.theme.surfaceSoft)
                        .fontColor(this.theme.brandSecondary)
                        .borderRadius(14)
                        .border({ width: 1, color: this.theme.brandSecondary })
                        .onClick(() => {
                          this.refundTok = pkg.tok;
                        })
                    } else {
                      Text('已消耗不可退')
                        .fontSize(FONT_SIZE_CAPTION)
                        .fontColor(this.theme.textTertiary)
                    }
                  }
                  .width('100%')
                  Text(`${this.fmtPkgTime(pkg.ts)} 购入 · 剩余 ${((pkg.amt - pkg.cons) / 10000).toLocaleString()} 万 SP`)
                    .fontSize(FONT_SIZE_CAPTION)
                    .fontColor(this.theme.textTertiary)
                    .margin({ top: 2 })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding({ top: 8, bottom: 8 })
                .borderRadius(RADIUS_CONTROL)
                .backgroundColor(this.theme.surfaceSoft)
                .border({ width: 1, color: this.theme.strokeCard })
                .margin({ bottom: 6 })
              }, (pkg: IapPackage, idx: number) => `${pkg.tok}_${pkg.cons}_${pkg.ref}_${pkg.frozenUntil > Date.now() ? 1 : 0}_${idx}`)
              if (this.pkgList().length === 0) {
                Text('暂无充能包——上方档位购买后每笔为一独立包，未消耗可整包退款')
                  .fontSize(FONT_SIZE_CAPTION)
                  .fontColor(this.theme.textTertiary)
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(this.theme.surfaceNode)
            .margin({ bottom: 12 })

            // ── SP 扣点规则（★ 0.289.0 文案随包级政策更新）──
            Column() {
              Text('SP 扣点规则')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(600)
                .fontColor(this.theme.textPrimary)
                .margin({ bottom: 6 })
              Text('• 消耗顺序：先扣嘉奖 SP，嘉奖用尽后按购买顺序逐包扣充能 SP（老包先扣）\n• 退款规则：按包退款——某包未消耗过任何 SP（1 点都没花）即可整包退款；该包一旦产生消耗即不可退款。退款在华为订单侧完成后，回到本页将自动核销该包剩余 SP')
                .fontSize(FONT_SIZE_BODY)
                .lineHeight(22)
                .fontColor(this.theme.textSecondary)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(this.theme.surfaceNode)
            .margin({ bottom: 12 })

            // ── 获取途径 ──
            Column() {
              Text('获取途径')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(600)
                .fontColor(this.theme.textPrimary)
                .margin({ bottom: 6 })
              Text('• 每日签到：连签奖励递增，第 7 天起 8,000 司忆点/天\n• 司忆学习：复习与学习行为产出 19,000 司忆点/天\n• 新用户礼包：注册即赠司忆点（永久有效）\n• 兑换码：输入兑换码入账（嘉奖 SP，永久）\n• 充能：上方充值档位，充能 SP 永久有效')
                .fontSize(FONT_SIZE_BODY)
                .lineHeight(22)
                .fontColor(this.theme.textSecondary)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(this.theme.surfaceNode)
            .margin({ bottom: 12 })

            // ── 兑换码 ──
            Column() {
              Text('兑换码')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(600)
                .fontColor(this.theme.textPrimary)
                .margin({ bottom: 8 })
              if (!this.account.isLoggedIn) {
                Column() {
                  Text('兑换前请先登录华为账号')
                    .fontSize(FONT_SIZE_CAPTION)
                    .fontColor(this.theme.textTertiary)
                  Button(this.isLoggingIn ? '登录中…' : '登录华为账号')
                    .fontSize(FONT_SIZE_BODY)
                    .height(40)
                    .backgroundColor(this.theme.brandPrimary)
                    .fontColor(this.theme.textPrimary)
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
                    .fontColor(this.theme.textPrimary)
                    .placeholderColor(this.theme.textTertiary)
                    .borderRadius(RADIUS_CONTROL)
                    .backgroundColor(this.theme.surfaceSoft)
                    .onChange((v: string) => {
                      this.redeemInput = v;
                      this.redeemResult = '';
                    })
                    .onSubmit(() => {
                      this.doRedeem(); // ★ 0.287.0 P1：回车=兑换
                    })
                  Button('兑换')
                    .fontSize(FONT_SIZE_BODY)
                    .height(42)
                    .backgroundColor(this.theme.brandPrimary)
                    .fontColor(this.theme.textPrimary)
                    .borderRadius(RADIUS_CONTROL)
                    .onClick(() => {
                      this.doRedeem();
                    })
                }
                .width('100%')

                if (this.redeemResult === 'ok') {
                  Text(`✓ 兑换成功，+${SIYI_REDEEM_SP / 10000} 万司忆点`)
                    .fontSize(FONT_SIZE_CAPTION)
                    .fontColor(this.theme.brandSecondary)
                    .margin({ top: 6 })
                } else if (this.redeemResult === 'used') {
                  Text('该兑换码已被使用')
                    .fontSize(FONT_SIZE_CAPTION)
                    .fontColor(this.theme.textTertiary)
                    .margin({ top: 6 })
                } else if (this.redeemResult === 'invalid') {
                  Text('兑换码无效，请检查输入')
                    .fontSize(FONT_SIZE_CAPTION)
                    .fontColor(this.theme.textTertiary)
                    .margin({ top: 6 })
                }
                Text('兑换码可叠加，每码仅可使用一次')
                  .fontSize(FONT_SIZE_CAPTION)
                  .fontColor(this.theme.textTertiary)
                  .margin({ top: 6 })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(this.theme.surfaceNode)
            .margin({ bottom: 12 })

            // ── 发票说明 ──
            Text('💡 发票说明：本应用内支付由华为收取并开具发票——请在「华为应用市场 → 我的 → 订单」中自助申请电子发票，开票方为华为。')
              .fontSize(FONT_SIZE_CAPTION)
              .lineHeight(18)
              .fontColor(this.theme.textTertiary)
              .padding({ left: 4, right: 4 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 24 })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .align(Alignment.TopStart)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.bgApp)
      .expandSafeArea([SafeAreaType.SYSTEM])

      // ★ 0.288.2：购买/补单/核销结果提示框（居中弹窗；宽度断点制 平板/PC 400 / 手机 86%）
      if (this.purchaseNotice.length > 0) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.theme.overlay)
            .onClick(() => {
              this.purchaseNotice = ''; // 点遮罩关闭（轻量信息框）
            })
          Column() {
            Text('支付提示')
              .fontSize(FONT_SIZE_CARD_TITLE_SM)
              .fontWeight(600)
              .fontColor(this.theme.textSecondary)
            Text(this.purchaseNotice)
              .fontSize(FONT_SIZE_BODY)
              .lineHeight(22)
              .fontColor(this.theme.textPrimary)
              .margin({ top: 10 })
            Button('知道了')
              .width('100%')
              .height(42)
              .fontSize(FONT_SIZE_BODY)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(this.theme.brandPrimary)
              .fontColor(this.theme.textPrimary)
              .borderRadius(RADIUS_CONTROL)
              .margin({ top: 16 })
              .onClick(() => {
                this.purchaseNotice = '';
              })
          }
          .width(this.isTablet ? 400 : '86%')
          .padding(20)
          .borderRadius(RADIUS_NAV)
          .backgroundColor(this.theme.surfaceNode)
          .border({ width: 1, color: this.theme.strokeCard })
          .shadow({ radius: 30, color: this.theme.shadowColor, offsetX: 0, offsetY: 12 })
        }
        .width('100%')
        .height('100%')
      }

      // ── ★ 0.289.0 申请退款弹窗（订单凭据+引导华为应用市场；退款由开发者后台执行）──
      if (this.refundTok.length > 0) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.theme.overlay)
            .onClick(() => {
              this.refundTok = '';
            })
          Column() {
            Text('申请退款')
              .fontSize(FONT_SIZE_CARD_TITLE_SM)
              .fontWeight(600)
              .fontColor(this.theme.textSecondary)
            if (this.refundTarget() !== null) {
              Text(`${this.pkgPriceText(this.refundTarget()!.pid)} · ${this.pkgAmtText(this.refundTarget()!.amt)}（未消耗，可整包退）`)
                .fontSize(FONT_SIZE_BODY)
                .fontWeight(600)
                .fontColor(this.theme.textPrimary)
                .margin({ top: 10 })
              Text(`购入时间：${this.fmtPkgTime(this.refundTarget()!.ts)}\n订单凭据：${this.refundTarget()!.tok.substring(0, 12)}…`)
                .fontSize(FONT_SIZE_CAPTION)
                .lineHeight(20)
                .fontColor(this.theme.textTertiary)
                .margin({ top: 6 })
            }
            Text('① 点击下方按钮后，该包立即锁定（7 天内不可使用），防止申请期间误扣\n② 前往「华为应用市场 → 我的 → 支付与账单」找到对应订单申请退款；无退款入口时拨打华为客服 950180 人工申请（审核约 1~3 天）\n③ 退款成功：款项由华为原路退回，本包 SP 将在您下次打开应用时自动核销作废，无需任何操作\n④ 7 天内未退款成功：该包自动解锁，恢复可用')
              .fontSize(FONT_SIZE_BODY)
              .lineHeight(22)
              .fontColor(this.theme.textSecondary)
              .margin({ top: 10 })
            Button('开始申请并锁定该包 7 天')
              .width('100%')
              .height(42)
              .fontSize(FONT_SIZE_BODY)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(this.theme.brandPrimary)
              .fontColor(this.theme.textPrimary)
              .borderRadius(RADIUS_CONTROL)
              .margin({ top: 16 })
              .onClick(() => {
                // ★ 0.291.0 确认申请=本地立即锁包（max 续锁随云同步多端一致）；退款本身在华为侧操作
                if (this.refundTok.length > 0) {
                  if (freezePackageUntil(this.siyi, this.refundTok, Date.now() + REFUND_FREEZE_MS)) {
                    this.showToastSafe('已锁定该包，请前往华为应用市场申请退款');
                  } else {
                    this.showToastSafe('订单信息异常，请稍后重试');
                  }
                }
                this.refundTok = '';
              })
            Button('暂不申请')
              .width('100%')
              .height(42)
              .fontSize(FONT_SIZE_BODY)
              .backgroundColor(this.theme.surfaceSoft)
              .fontColor(this.theme.textSecondary)
              .borderRadius(RADIUS_CONTROL)
              .margin({ top: 8 })
              .onClick(() => {
                this.refundTok = '';
              })
          }
          .width(this.isTablet ? 400 : '86%')
          .padding(20)
          .borderRadius(RADIUS_NAV)
          .backgroundColor(this.theme.surfaceNode)
          .border({ width: 1, color: this.theme.strokeCard })
          .shadow({ radius: 30, color: this.theme.shadowColor, offsetX: 0, offsetY: 12 })
        }
        .width('100%')
        .height('100%')
      }

      }
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.bgApp) // ★ 0.278.12：NavDestination 容器级显式背景（华为官方建议双保险）
    .onBackPressed(() => {
      // ★ 0.289.0：退款弹窗打开时返回键先关退款弹窗（弹窗优先关定式）
      if (this.refundTok.length > 0) {
        this.refundTok = '';
        return true;
      }
      if (this.purchaseNotice.length > 0) {
        this.purchaseNotice = '';
        return true;
      }
      const gsShared = connectGlobalSettingsShared();
      if (gsShared.visible) {
        gsShared.closeReq++;
        return true;
      }
      return false;
    })
    .background(this.theme.bgApp) // ★ 0.278.10：background() 背景延伸进安全区（统一 0.278.9 模板）
  }
}
