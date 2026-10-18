// SignInDialog.ets — ★ 0.256.0：签到弹窗 + 称号升级弹窗（Index 根 Stack 唯一挂载点）
// 触发：SignInDialogBridge / LevelUpBridge（AppStorageV2 应用级桥——边栏签到入口/首登引导判定/
//   学习天数落盘检测 触发，此处消费；AppConfirmDialog 同款解耦模式）
// 口径（用户 2026-10-19 拍板）：连签奖励递增封顶——第 1 天 2,000 每天 +1,000，第 7 天起 8,000/天；
//   里程碑 7/30/100 天额外 +10,000/+50,000/+200,000（发放入 bonusSp 嘉奖池）
// 样式：AppConfirmDialog/ReminderDialog 同款暗紫定式（遮罩 0.5 + SURFACE_NODE + RADIUS_NAV +
//   STROKE_CARD 描边 + 宽度断点制 isTablet?400:'86%'——UI_GUIDELINES 六-12a）
// 调试：底部日期小字长按/右键 bindContextMenu → 日期偏移菜单（+1/+7/+30/+365/清零，默认 0 零影响）

import {
  SignInStore, connectSignIn, SiyiPointStore, connectSiyiPoints,
  DebugDayOffsetStore, connectDebugDayOffset, SignInDialogBridge, connectSignInDialog,
  LevelUpBridge, connectLevelUpBridge, SIYI_LEVEL_PERKS, SIYI_LEVEL_TITLES,
  todayStrWithOffset, nextStreak, signInRewardSp, milestoneBonusSp, isSignedToday, doSignIn
} from '../common/ChatModel';
import { SURFACE_NODE, SURFACE_HOVER, BRAND_PRIMARY, BRAND_SECONDARY, TEXT_PRIMARY, TEXT_SECONDARY, TEXT_TERTIARY, STROKE_CARD, RADIUS_NAV, RADIUS_CONTROL, FONT_SIZE_SCREEN_TITLE, FONT_SIZE_BODY, FONT_SIZE_CARD_TITLE_SM, FONT_SIZE_CAPTION, FONT_INTER_SEMIBOLD } from '../common/DesignTokens';
import { WindowMode, connectWindowMode } from '../common/WindowMode'; // 宽屏断点（弹窗宽度收敛）

@ComponentV2
export struct SignInDialog {
  dialogBridge: SignInDialogBridge = connectSignInDialog();
  signIn: SignInStore = connectSignIn();
  siyi: SiyiPointStore = connectSiyiPoints();
  debugOffset: DebugDayOffsetStore = connectDebugDayOffset();
  @Local signedAmount: number = 0; // 刚签到发放总额（>0=成功态；关闭弹窗清零）
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
    const got = doSignIn(this.signIn, this.siyi, this.today());
    if (got > 0) {
      this.signedAmount = got;
    }
  }

  onClose(): void {
    this.dialogBridge.visible = false;
    this.signedAmount = 0;
  }

  @Builder
  dayDot(index: number, reached: boolean) {
    Column({ space: 4 }) {
      Circle()
        .width(index === 7 ? 12 : 10)
        .height(index === 7 ? 12 : 10)
        .fill(reached ? BRAND_PRIMARY : SURFACE_HOVER)
      Text(index === 7 ? '8,000' : `${index}`)
        .fontSize(9)
        .fontColor(reached ? BRAND_SECONDARY : TEXT_TERTIARY)
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
      .backgroundColor('rgba(0,0,0,0.5)')
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
            .fontColor(TEXT_PRIMARY)
            .margin({ bottom: 10 })
          Text(`+${this.signedAmount.toLocaleString()} SP 已入嘉奖池`)
            .fontSize(FONT_SIZE_BODY)
            .lineHeight(22)
            .fontColor(BRAND_SECONDARY)
            .margin({ bottom: 6 })
          if (milestoneBonusSp(this.signIn.streak) > 0) {
            Text(`连签 ${this.signIn.streak} 天里程碑 +${milestoneBonusSp(this.signIn.streak).toLocaleString()} SP`)
              .fontSize(FONT_SIZE_CAPTION)
              .fontColor(TEXT_TERTIARY)
          }
          Text(`当前连签 ${this.signIn.streak} 天 · 明日可领 ${signInRewardSp(this.signIn.streak + 1).toLocaleString()} SP`)
            .fontSize(FONT_SIZE_CAPTION)
            .fontColor(TEXT_SECONDARY)
            .margin({ top: 8 })
        } else if (this.todaySigned()) {
          // ── 今日已签态 ──
          Text('今日已签到')
            .fontSize(FONT_SIZE_SCREEN_TITLE)
            .fontWeight(600)
            .fontFamily(FONT_INTER_SEMIBOLD)
            .fontColor(TEXT_PRIMARY)
            .margin({ bottom: 10 })
          Text(`当前连签 ${this.signIn.streak} 天（历史最高 ${this.signIn.maxStreak} 天）`)
            .fontSize(FONT_SIZE_BODY)
            .lineHeight(22)
            .fontColor(TEXT_SECONDARY)
            .margin({ bottom: 6 })
          Text(`连签第 7 天起每日稳定 8,000 SP；明日可领 ${signInRewardSp(this.signIn.streak + 1).toLocaleString()} SP`)
            .fontSize(FONT_SIZE_CAPTION)
            .lineHeight(18)
            .fontColor(TEXT_TERTIARY)
        } else {
          // ── 未签态（首登引导与日常共用）──
          Text(`第 ${this.pendingStreak()} 天签到`)
            .fontSize(FONT_SIZE_SCREEN_TITLE)
            .fontWeight(600)
            .fontFamily(FONT_INTER_SEMIBOLD)
            .fontColor(TEXT_PRIMARY)
            .margin({ bottom: 12 })
          Text(`今日可领 ${this.todayGainText()}`)
            .fontSize(FONT_SIZE_BODY)
            .lineHeight(22)
            .fontColor(BRAND_SECONDARY)
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
            .fontColor(TEXT_TERTIARY)
            .margin({ bottom: 16 })

          Button('立即签到')
            .width('100%')
            .height(48)
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(BRAND_PRIMARY)
            .fontColor(TEXT_PRIMARY)
            .borderRadius(RADIUS_CONTROL)
            .onClick(() => {
              this.onSignClick();
            })
        }

        // 日期小字（长按/右键=调试日期偏移菜单；偏移≠0 时醒目提示）
        Text(this.debugOffset.offset === 0 ? this.today() : `${this.today()}（调试偏移 ${this.debugOffset.offset >= 0 ? '+' : ''}${this.debugOffset.offset} 天）`)
          .fontSize(10)
          .fontColor(this.debugOffset.offset === 0 ? TEXT_TERTIARY : BRAND_SECONDARY)
          .margin({ top: 14 })
          .bindContextMenu((): void => {
            this.debugMenuBuilder()
          }, ResponseType.RightClick)
      }
      .width(this.isTablet ? 400 : '86%')
      .padding(20)
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
      .border({ width: 1, color: STROKE_CARD })
    }
  }
}

// ★ 0.256.0：称号升级弹窗——头衔升级瞬间弹「恭喜升级」+新头衔+权益（此前静默变化无提醒）
@ComponentV2
export struct LevelUpDialog {
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
      .backgroundColor('rgba(0,0,0,0.5)')
      .onClick(() => {
        this.bridge.pendingLevel = 0;
      })

      Column() {
        Text('🎉 恭喜升级')
          .fontSize(FONT_SIZE_SCREEN_TITLE)
          .fontWeight(600)
          .fontFamily(FONT_INTER_SEMIBOLD)
          .fontColor(TEXT_PRIMARY)
          .margin({ bottom: 12 })

        Text(SIYI_LEVEL_TITLES[this.bridge.pendingLevel - 1])
          .fontSize(24)
          .fontWeight(700)
          .fontFamily(FONT_INTER_SEMIBOLD)
          .fontColor(BRAND_SECONDARY)
          .margin({ bottom: 12 })

        Text(`新头衔权益：${SIYI_LEVEL_PERKS[this.bridge.pendingLevel - 1]}`)
          .fontSize(FONT_SIZE_BODY)
          .lineHeight(22)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })

        Text('坚持每日学习，下一级头衔正在等你')
          .fontSize(FONT_SIZE_CAPTION)
          .fontColor(TEXT_TERTIARY)

        Button('继续学习')
          .width('100%')
          .height(48)
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(BRAND_PRIMARY)
          .fontColor(TEXT_PRIMARY)
          .borderRadius(RADIUS_CONTROL)
          .margin({ top: 16 })
          .onClick(() => {
            this.bridge.pendingLevel = 0;
          })
      }
      .width(this.isTablet ? 400 : '86%')
      .padding(20)
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
      .border({ width: 1, color: STROKE_CARD })
    }
  }
}
