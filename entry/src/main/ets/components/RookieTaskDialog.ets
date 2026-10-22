// ============================================================
// RookieTaskDialog.ets — ★ 0.294.0：好奇宝宝任务面板 + 奖励到账弹窗
// ============================================================
// 宿主：BBTreeCanvas（画布右上角任务入口唤起；PersonalityQuizDialog 同款壳纪律）。
// 面板：7 条任务清单（不按顺序、做完哪条打勾哪条）+ 进度 x/7 + 完赛奖预告；
//   性格测试行实时显示答题进度 x/15（复用 quizAnswerTotal 三段口径）。
// 挂账态：任务已勾但奖励未发（云服务未开通期间完成）→ 行尾灰小字「云服务开通后到账」；
//   面板每次打开调 settleRookieTasks() 对账差集自动补发（三结算时机之一）。
// 奖励弹窗：单任务完成/汇总补发「+N SP」自绘小弹窗（桥驱动，随面板同挂画布）。
// 样式：宽度断点制手机 '90%' / 平板 PC 480（UI_GUIDELINES 12a）；完成态 checkbox_on.svg；
//   任务行直接内联 ForEach（禁带参 @Builder——0.190.1/0.209.1 按值传参雷）。
// ============================================================

import {
  RookieTaskDef, ROOKIE_TASKS, ROOKIE_BONUS_SP,
  connectRookieBridge, rookieTaskDone, rookieTaskGranted,
  rookieDoneCount, settleRookieTasks
} from '../common/RookieTask';
import { connectSiyiPoints } from '../common/ChatModel';
import { connectPersonalityQuiz, quizAnswerTotal, QUIZ_TOTAL } from '../common/PersonalityQuiz';
import { RADIUS_NAV, RADIUS_CONTROL, FONT_SIZE_SCREEN_TITLE, FONT_SIZE_BODY, FONT_SIZE_META, FONT_INTER_SEMIBOLD, FONT_INTER } from '../common/DesignTokens';
import { AppTheme, connectAppTheme } from '../common/AppTheme';
import { WindowMode, connectWindowMode } from '../common/WindowMode';

@ComponentV2
export struct RookieTaskDialog {
  theme: AppTheme = connectAppTheme();
  @Param visible: boolean = false;
  @Event onClose: () => void = () => {};
  @Local windowMode: WindowMode = connectWindowMode();
  @Computed get isTablet(): boolean {
    return this.windowMode.isTablet;
  }

  @Monitor('visible')
  onVisibleChange(): void {
    if (this.visible) {
      // ★ 结算时机之三：面板打开即对账（差集补发——云服务刚开通的场景在此闭环）
      settleRookieTasks();
    }
  }

  build() {
    if (this.visible) {
      // 全屏遮罩（点击不关闭——照 GSD/性格测试弹窗纪律，走 ✕ 关闭）
      Stack() {
        Column() {
          // 标题行
          Row() {
            Text('好奇宝宝任务')
              .fontSize(FONT_SIZE_SCREEN_TITLE)
              .fontWeight(700)
              .fontFamily(FONT_INTER_SEMIBOLD)
              .fontColor(this.theme.textPrimary)
              .layoutWeight(1)
              .maxLines(1)
            Button('✕')
              .fontSize(14)
              .fontColor(this.theme.textSecondary)
              .backgroundColor(Color.Transparent)
              .height(32)
              .padding({ left: 8, right: 8 })
              .onClick(() => {
                this.onClose();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          // 进度行：x/7 · 完赛奖预告
          Row({ space: 8 }) {
            Text(`已完成 ${rookieDoneCount(connectSiyiPoints())}/${ROOKIE_TASKS.length}`)
              .fontSize(FONT_SIZE_META)
              .fontFamily(FONT_INTER)
              .fontColor(this.theme.textSecondary)
              .maxLines(1)
            Text(`· 全部完成再得 ${ROOKIE_BONUS_SP / 10000} 万`)
              .fontSize(FONT_SIZE_META)
              .fontFamily(FONT_INTER)
              .fontColor(this.theme.brandPrimary)
              .maxLines(1)
          }
          .width('100%')
          .margin({ top: 4, bottom: 6 })
          // 任务清单（内联——禁带参 @Builder）
          Scroll() {
            Column() {
              ForEach(ROOKIE_TASKS, (t: RookieTaskDef) => {
                Row({ space: 10 }) {
                  if (rookieTaskDone(connectSiyiPoints(), t.id)) {
                    Image($r('app.media.checkbox_on'))
                      .width(18)
                      .height(18)
                      .objectFit(ImageFit.Contain)
                  } else {
                    // 未完成：空位占位（与完成态图标同宽——名称列纵向对齐）
                    Row()
                      .width(18)
                      .height(18)
                      .borderRadius(4)
                      .border({ width: 1.2, color: this.theme.textSecondary })
                      .opacity(0.5)
                  }
                  Column({ space: 3 }) {
                    Row({ space: 6 }) {
                      Text(t.name)
                        .fontSize(FONT_SIZE_BODY)
                        .fontWeight(600)
                        .fontFamily(FONT_INTER_SEMIBOLD)
                        .fontColor(rookieTaskDone(connectSiyiPoints(), t.id)
                          ? this.theme.textSecondary : this.theme.textPrimary)
                        .maxLines(1)
                      // 性格测试行：实时答题进度 x/15（未完成时展示）
                      if (t.id === 'personality_quiz' && !rookieTaskDone(connectSiyiPoints(), t.id)) {
                        Text(`${quizAnswerTotal(connectPersonalityQuiz())}/${QUIZ_TOTAL}`)
                          .fontSize(FONT_SIZE_META)
                          .fontFamily(FONT_INTER)
                          .fontColor(this.theme.brandPrimary)
                          .maxLines(1)
                      }
                    }
                    .alignItems(VerticalAlign.Bottom)
                    Text(t.desc)
                      .fontSize(FONT_SIZE_META)
                      .fontFamily(FONT_INTER)
                      .fontColor(this.theme.textSecondary)
                      .maxLines(1)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  // 右侧状态三态：已领 N SP / 云服务开通后到账（挂账）/ 待完成 +N SP
                  if (rookieTaskDone(connectSiyiPoints(), t.id)) {
                    if (rookieTaskGranted(connectSiyiPoints(), t.id)) {
                      Text(`+${t.sp / 10000} 万`)
                        .fontSize(FONT_SIZE_META)
                        .fontFamily(FONT_INTER)
                        .fontColor(this.theme.textSecondary)
                        .maxLines(1)
                    } else {
                      Text('云服务开通后到账')
                        .fontSize(FONT_SIZE_META)
                        .fontFamily(FONT_INTER)
                        .fontColor(this.theme.textSecondary)
                        .opacity(0.7)
                        .maxLines(1)
                    }
                  } else {
                    Text(`+${t.sp / 10000} 万 SP`)
                      .fontSize(FONT_SIZE_META)
                      .fontWeight(600)
                      .fontFamily(FONT_INTER_SEMIBOLD)
                      .fontColor(this.theme.brandPrimary)
                      .maxLines(1)
                  }
                }
                .width('100%')
                .padding({ top: 10, bottom: 10 })
                .alignItems(VerticalAlign.Center)
              }, (t: RookieTaskDef) => t.id)
            }
            .width('100%')
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.Start)
          // 底部说明（SP 云服务铁律口径）
          Text('奖励于云服务开通后发放并自动到账 · 全部完成后此入口消失')
            .fontSize(FONT_SIZE_META)
            .fontFamily(FONT_INTER)
            .fontColor(this.theme.textSecondary)
            .opacity(0.7)
            .maxLines(1)
            .margin({ top: 8 })
        }
        .width(this.isTablet ? 480 : '90%')
        .padding({ left: 20, right: 20, top: 18, bottom: 16 })
        .borderRadius(RADIUS_NAV)
        .backgroundColor(this.theme.surfaceNode)
        .border({ width: 1, color: this.theme.strokeCard })
        .shadow({ radius: 24, color: this.theme.shadowColor, offsetX: 0, offsetY: 10 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.overlay)
      .alignContent(Alignment.Center)
    }
  }
}

// ============================================================
// RookieRewardDialog — ★ 0.294.0：奖励到账小弹窗（桥驱动；主操作「好的」在左——双键弹窗规范）
// ============================================================
@ComponentV2
export struct RookieRewardDialog {
  theme: AppTheme = connectAppTheme();
  bridge = connectRookieBridge();
  @Local windowMode: WindowMode = connectWindowMode();
  @Computed get isTablet(): boolean {
    return this.windowMode.isTablet;
  }

  build() {
    if (this.bridge.rewardVisible) {
      Stack() {
        Column({ space: 10 }) {
          Text(this.bridge.rewardTitle)
            .fontSize(FONT_SIZE_BODY)
            .fontWeight(700)
            .fontFamily(FONT_INTER_SEMIBOLD)
            .fontColor(this.theme.textPrimary)
            .maxLines(1)
          Text(`+${this.bridge.rewardAmount.toLocaleString()} SP 已入嘉奖池`)
            .fontSize(FONT_SIZE_BODY)
            .fontWeight(600)
            .fontFamily(FONT_INTER_SEMIBOLD)
            .fontColor(this.theme.brandPrimary)
            .maxLines(1)
          Row({ space: 10 }) {
            Button('好的')
              .fontSize(FONT_SIZE_BODY)
              .fontWeight(600)
              .fontFamily(FONT_INTER_SEMIBOLD)
              .fontColor(Color.White)
              .backgroundColor(this.theme.brandPrimary)
              .borderRadius(RADIUS_CONTROL)
              .height(34)
              .padding({ left: 18, right: 18 })
              .onClick(() => {
                this.bridge.rewardVisible = false;
              })
          }
          .margin({ top: 6 })
        }
        .width(this.isTablet ? 360 : '80%')
        .padding({ left: 20, right: 20, top: 20, bottom: 18 })
        .borderRadius(RADIUS_NAV)
        .backgroundColor(this.theme.surfaceNode)
        .border({ width: 1, color: this.theme.strokeCard })
        .shadow({ radius: 24, color: this.theme.shadowColor, offsetX: 0, offsetY: 10 })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.overlay)
      .alignContent(Alignment.Center)
      .onClick(() => {
        this.bridge.rewardVisible = false; // 点遮罩也可关（轻提示窗）
      })
    }
  }
}
