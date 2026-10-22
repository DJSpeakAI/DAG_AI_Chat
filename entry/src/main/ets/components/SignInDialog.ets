// SignInDialog.ets — ★ 0.256.0：签到弹窗 + 称号升级弹窗（Index 根 Stack 唯一挂载点）
// 触发：SignInDialogBridge / LevelUpBridge（AppStorageV2 应用级桥——边栏签到入口/首登引导判定/
//   学习天数落盘检测 触发，此处消费；AppConfirmDialog 同款解耦模式）
// 口径（用户 2026-10-19 拍板）：连签奖励递增封顶——第 1 天 2,000 每天 +1,000，第 7 天起 8,000/天；
//   里程碑 7/30/100 天额外 +10,000/+50,000/+200,000（发放入 bonusSp 嘉奖池）
// 样式：AppConfirmDialog/ReminderDialog 同款暗紫定式（遮罩 0.5 + this.theme.surfaceNode + RADIUS_NAV +
//   this.theme.strokeCard 描边 + 宽度断点制 isTablet?400:'86%'——UI_GUIDELINES 六-12a）
// 调试：底部日期小字长按/右键 bindContextMenu → 日期偏移菜单（+1/+7/+30/+365/清零，默认 0 零影响）

import {
  SignInStore, connectSignIn, SiyiPointStore, connectSiyiPoints,
  DebugDayOffsetStore, connectDebugDayOffset, SignInDialogBridge, connectSignInDialog,
  LevelUpBridge, connectLevelUpBridge, SIYI_LEVEL_PERKS, SIYI_LEVEL_TITLES,
  todayStrWithOffset, nextStreak, signInRewardSp, milestoneBonusSp, isSignedToday, doSignIn,
  canMakeupYesterday, useMakeupVoucher
} from '../common/ChatModel';
import { RADIUS_NAV, RADIUS_CONTROL, FONT_SIZE_SCREEN_TITLE, FONT_SIZE_BODY, FONT_SIZE_CARD_TITLE_SM, FONT_SIZE_CAPTION, FONT_INTER_SEMIBOLD } from '../common/DesignTokens';
import { AppTheme, connectAppTheme } from '../common/AppTheme';
import { WindowMode, connectWindowMode } from '../common/WindowMode'; // 宽屏断点（弹窗宽度收敛）
import { requireSiyiGate } from '../utils/SiyiGate'; // ★ 0.293.0：SP 云同步门卫（签到增发 SP 前置闸）

@ComponentV2
export struct SignInDialog {
  theme: AppTheme = connectAppTheme();
  dialogBridge: SignInDialogBridge = connectSignInDialog();
  signIn: SignInStore = connectSignIn();
  siyi: SiyiPointStore = connectSiyiPoints();
  debugOffset: DebugDayOffsetStore = connectDebugDayOffset();
  @Local signedAmount: number = 0; // 刚签到发放总额（>0=成功态；关闭弹窗清零）
  @Local makeupJustUsed: boolean = false; // ★ 0.259.0：刚补签成功反馈态（显示「连击已续接」；关闭清零）
  // 宽屏断点——@ObservedV2 实例须挂 @Local 才可靠响应（0.209.1 铁律）
  @Local windowMode: WindowMode = connectWindowMode();
  @Computed get isTablet(): boolean {
    return this.windowMode.isTablet;
  }

  today(): string {
    return todayStrWithOffset(this.debugOffset.offset);
  }

  // 本次签到将达成的连击天数（未签态展示「第 N 天」用）
  pendingStreak(): number {
    return nextStreak(this.signIn.lastSignDate, this.signIn.streak, this.today());
  }

  todaySigned(): boolean {
    return isSignedToday(this.signIn);
  }

  // 今日可领（含里程碑）：未签态展示
  todayGainText(): string {
    const n = this.pendingStreak();
    const base = signInRewardSp(n);
    const mile = milestoneBonusSp(n);
    return mile > 0 ? `${(base + mile).toLocaleString()} SP（含里程碑 +${mile.toLocaleString()}）` : `${base.toLocaleString()} SP`;
  }

  onSignClick(): void {
    // ★ 0.293.0：SP 云同步门卫——签到增发 SP 必须账本云端对齐（未就绪弹引导，Index 根消费）
    if (!requireSiyiGate()) {
      return;
    }
    const got = doSignIn(this.signIn, this.siyi, this.today());
    if (got > 0) {
      this.signedAmount = got;
    } else if (!this.todaySigned()) {
      // 防御提示：云端已签标记晚到被幂等拦截（正常路径 todaySigned 双查口径已统一不进此支）
      try {
        this.getUIContext().getPromptAction().showToast({ message: '今日已在其他设备签到', duration: 1500 });
      } catch (_e) {
        // 静默
      }
    }
  }

  onClose(): void {
    this.dialogBridge.visible = false;
    this.signedAmount = 0;
    this.makeupJustUsed = false;
  }

  // ★ 0.259.0：断签可补判定（展示补签按钮依据——券>0 && 今天未签 && 昨天未签未补）
  canMakeup(): boolean {
    return canMakeupYesterday(this.signIn, this.today());
  }

  onMakeupClick(): void {
    if (useMakeupVoucher(this.signIn, this.today())) {
      this.makeupJustUsed = true;
    }
  }

  @Builder
  dayDot(index: number, reached: boolean) {
    Column({ space: 4 }) {
      Circle()
        .width(index === 7 ? 12 : 10)
        .height(index === 7 ? 12 : 10)
        .fill(reached ? this.theme.brandPrimary : this.theme.surfaceHover)
      Text(index === 7 ? '8,000' : `${index}`)
        .fontSize(9)
        .fontColor(reached ? this.theme.brandSecondary : this.theme.textTertiary)
    }
  }

  @Builder
  debugMenuBuilder() {
    Menu() {
      MenuItem({ content: `日期偏移 +1 天（当前 ${this.debugOffset.offset >= 0 ? '+' : ''}${this.debugOffset.offset}）` })
        .onClick(() => {
          this.debugOffset.offset += 1;
        })
      MenuItem({ content: '日期偏移 +7 天' })
        .onClick(() => {
          this.debugOffset.offset += 7;
        })
      MenuItem({ content: '日期偏移 +30 天' })
        .onClick(() => {
          this.debugOffset.offset += 30;
        })
      MenuItem({ content: '日期偏移 +365 天' })
        .onClick(() => {
          this.debugOffset.offset += 365;
        })
      MenuItem({ content: '偏移清零（恢复正常）' })
        .onClick(() => {
          this.debugOffset.offset = 0;
        })
    }
  }

  build() {
    if (this.dialogBridge.visible) {
      // 遮罩（点击关闭——签到是主动行为，误关无损失，红点入口仍在）
      Column() {
        Blank()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.overlay)
      .onClick(() => {
        this.onClose();
      })

      // 面板（AppConfirmDialog 同款定式）
      Column() {
        // ── 刚签到成功态 ──
        if (this.signedAmount > 0) {
          Text('✓ 签到成功')
            .fontSize(FONT_SIZE_SCREEN_TITLE)
            .fontWeight(600)
            .fontFamily(FONT_INTER_SEMIBOLD)
            .fontColor(this.theme.textPrimary)
            .margin({ bottom: 10 })
          Text(`+${this.signedAmount.toLocaleString()} SP 已入嘉奖池`)
            .fontSize(FONT_SIZE_BODY)
            .lineHeight(22)
            .fontColor(this.theme.brandSecondary)
            .margin({ bottom: 6 })
          if (milestoneBonusSp(this.signIn.streak) > 0) {
            Text(`连签 ${this.signIn.streak} 天里程碑 +${milestoneBonusSp(this.signIn.streak).toLocaleString()} SP`)
              .fontSize(FONT_SIZE_CAPTION)
              .fontColor(this.theme.textTertiary)
          }
          Text(`当前连签 ${this.signIn.streak} 天 · 明日可领 ${signInRewardSp(this.signIn.streak + 1).toLocaleString()} SP`)
            .fontSize(FONT_SIZE_CAPTION)
            .fontColor(this.theme.textSecondary)
            .margin({ top: 8 })
        } else if (this.todaySigned()) {
          // ── 今日已签态 ──
          Text('今日已签到')
            .fontSize(FONT_SIZE_SCREEN_TITLE)
            .fontWeight(600)
            .fontFamily(FONT_INTER_SEMIBOLD)
            .fontColor(this.theme.textPrimary)
            .margin({ bottom: 10 })
          Text(`当前连签 ${this.signIn.streak} 天（历史最高 ${this.signIn.maxStreak} 天）`)
            .fontSize(FONT_SIZE_BODY)
            .lineHeight(22)
            .fontColor(this.theme.textSecondary)
            .margin({ bottom: 6 })
          Text(`连签第 7 天起每日稳定 8,000 SP；明日可领 ${signInRewardSp(this.signIn.streak + 1).toLocaleString()} SP`)
            .fontSize(FONT_SIZE_CAPTION)
            .lineHeight(18)
            .fontColor(this.theme.textTertiary)
        } else {
          // ── 未签态（首登引导与日常共用）──
          Text(`第 ${this.pendingStreak()} 天签到`)
            .fontSize(FONT_SIZE_SCREEN_TITLE)
            .fontWeight(600)
            .fontFamily(FONT_INTER_SEMIBOLD)
            .fontColor(this.theme.textPrimary)
            .margin({ bottom: 12 })

          // ── ★ 0.259.0：断签补签块（昨天漏签 && 持有补签券——「后悔药」续接连击）──
          if (this.makeupJustUsed) {
            Text(`连击已续接（当前 ${this.signIn.streak} 天）——今日签到后变 ${this.signIn.streak + 1} 天`)
              .fontSize(FONT_SIZE_CAPTION)
              .lineHeight(18)
              .fontColor(this.theme.brandSecondary)
              .margin({ bottom: 10 })
          } else if (this.canMakeup()) {
            Text(`昨日漏签，连击已断（此前 ${this.signIn.streak} 天）`)
              .fontSize(FONT_SIZE_CAPTION)
              .lineHeight(18)
              .fontColor(this.theme.textTertiary)
              .margin({ bottom: 6 })
            Button(`使用补签券 ×1 续接连击（剩余 ${this.signIn.makeupVouchers} 张）`)
              .width('100%')
              .height(40)
              .fontSize(FONT_SIZE_BODY)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(Color.Transparent)
              .fontColor(this.theme.brandSecondary)
              .borderRadius(RADIUS_CONTROL)
              .border({ width: 1, color: this.theme.brandSecondary })
              .margin({ bottom: 10 })
              .onClick(() => {
                this.onMakeupClick();
              })
          }

          Text(`今日可领 ${this.todayGainText()}`)
            .fontSize(FONT_SIZE_BODY)
            .lineHeight(22)
            .fontColor(this.theme.brandSecondary)
            .margin({ bottom: 14 })

          // 连签 7 天进度点条（第 7 天满额 8,000/天）
          Row({ space: 10 }) {
            ForEach([1, 2, 3, 4, 5, 6, 7], (d: number) => {
              this.dayDot(d, d <= Math.min(this.pendingStreak(), 7))
            }, (d: number) => `dot_${d}`)
          }
          .margin({ bottom: 12 })

          Text('连签 7 / 30 / 100 天，额外 +10,000 / +50,000 / +200,000 SP')
            .fontSize(FONT_SIZE_CAPTION)
            .lineHeight(18)
            .fontColor(this.theme.textTertiary)
            .margin({ bottom: 16 })

          Button('立即签到')
            .width('100%')
            .height(48)
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(this.theme.brandPrimary)
            .fontColor(this.theme.textPrimary)
            .borderRadius(RADIUS_CONTROL)
            .onClick(() => {
              this.onSignClick();
            })
        }

        // ★ 0.259.0：补签券持有量小字（>0 才显示——等级升级奖励获得，可在断签时续接连击）
        if (this.signIn.makeupVouchers > 0) {
          Text(`补签券 ×${this.signIn.makeupVouchers}（等级升级奖励 · 断签时可续接连击）`)
            .fontSize(10)
            .fontColor(this.theme.textTertiary)
            .margin({ top: 10 })
        }

        // 日期小字（长按/右键=调试日期偏移菜单；偏移≠0 时醒目提示）
        Text(this.debugOffset.offset === 0 ? this.today() : `${this.today()}（调试偏移 ${this.debugOffset.offset >= 0 ? '+' : ''}${this.debugOffset.offset} 天）`)
          .fontSize(10)
          .fontColor(this.debugOffset.offset === 0 ? this.theme.textTertiary : this.theme.brandSecondary)
          .margin({ top: 14 })
          .bindContextMenu((): void => {
            this.debugMenuBuilder()
          }, ResponseType.RightClick)
      }
      .width(this.isTablet ? 400 : '86%')
      .padding(20)
      .borderRadius(RADIUS_NAV)
      .backgroundColor(this.theme.surfaceNode)
      .border({ width: 1, color: this.theme.strokeCard })
    }
  }
}

// ★ 0.256.0：称号升级弹窗——头衔升级瞬间弹「恭喜升级」+新头衔+权益（此前静默变化无提醒）
@ComponentV2
export struct LevelUpDialog {
  theme: AppTheme = connectAppTheme();
  bridge: LevelUpBridge = connectLevelUpBridge();
  @Local windowMode: WindowMode = connectWindowMode();
  @Computed get isTablet(): boolean {
    return this.windowMode.isTablet;
  }

  build() {
    if (this.bridge.pendingLevel > 0) {
      // 遮罩（点击关闭——庆祝性质，无确认语义）
      Column() {
        Blank()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.overlay)
      .onClick(() => {
        this.bridge.pendingLevel = 0;
      })

      Column() {
        Text('🎉 恭喜升级')
          .fontSize(FONT_SIZE_SCREEN_TITLE)
          .fontWeight(600)
          .fontFamily(FONT_INTER_SEMIBOLD)
          .fontColor(this.theme.textPrimary)
          .margin({ bottom: 12 })

        Text(SIYI_LEVEL_TITLES[this.bridge.pendingLevel - 1])
          .fontSize(24)
          .fontWeight(700)
          .fontFamily(FONT_INTER_SEMIBOLD)
          .fontColor(this.theme.brandSecondary)
          .margin({ bottom: 12 })

        Text(`新头衔权益：${SIYI_LEVEL_PERKS[this.bridge.pendingLevel - 1]}`)
          .fontSize(FONT_SIZE_BODY)
          .lineHeight(22)
          .fontColor(this.theme.textSecondary)
          .margin({ bottom: 6 })

        // ★ 0.259.0：升级发补签券（奖励的仪式感放在升级这一刻——因努力而奖励；Lv8 满级改 SP 恒显 999,999 不送券）
        if (this.bridge.pendingMakeupGrant > 0) {
          Text(`🎉 获得补签券 ×${this.bridge.pendingMakeupGrant}（断签时可续接连击）`)
            .fontSize(FONT_SIZE_BODY)
            .lineHeight(22)
            .fontColor(this.theme.brandSecondary)
            .margin({ bottom: 6 })
        }

        Text('坚持每日学习，下一级头衔正在等你')
          .fontSize(FONT_SIZE_CAPTION)
          .fontColor(this.theme.textTertiary)

        Button('继续学习')
          .width('100%')
          .height(48)
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(this.theme.brandPrimary)
          .fontColor(this.theme.textPrimary)
          .borderRadius(RADIUS_CONTROL)
          .margin({ top: 16 })
          .onClick(() => {
            this.bridge.pendingLevel = 0;
          })
      }
      .width(this.isTablet ? 400 : '86%')
      .padding(20)
      .borderRadius(RADIUS_NAV)
      .backgroundColor(this.theme.surfaceNode)
      .border({ width: 1, color: this.theme.strokeCard })
    }
  }
}
