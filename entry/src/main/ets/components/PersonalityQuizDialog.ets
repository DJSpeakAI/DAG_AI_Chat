// PersonalityQuizDialog.ets — ★ 0.288.0 性格测试弹窗（15 题混合穿插）
//   宿主：BBTreeCanvas（画布左下角「信号灯」呼吸圆点唤起，做完消失）
//   交互：点选项即作答进入下一题（答案即时落盘，退出再进续做）；
//   每 5 题发 2000 司忆点（3 节点，claimed 幂等）；15 题答完生成画像写入记忆引擎。
//   样式：0.190.8 弹窗模板同款（遮罩 overlay + surfaceNode 面板 + RADIUS_NAV + strokeCard 描边）；
//   宽度断点制手机 '90%' / 平板 PC 480（题面+选项卡需要比确认类弹窗更宽，ReminderDialog 400/86% 变体）。

import {
  PERSONALITY_QUESTIONS, QUIZ_TOTAL, QUIZ_SP_PER_NODE, QuizQuestion,
  PersonalityQuizStore, connectPersonalityQuiz,
  getQuizAnswers, recordQuizAnswer, claimQuizSp, writeQuizProfile, quizProfilePreview
} from '../common/PersonalityQuiz';
import { ProfileStore, connectProfileObservations } from '../common/ProfileModel';
import { RADIUS_NAV, RADIUS_CONTROL, FONT_SIZE_SCREEN_TITLE, FONT_SIZE_BODY, FONT_SIZE_META, FONT_INTER_SEMIBOLD, FONT_INTER } from '../common/DesignTokens';
import { AppTheme, connectAppTheme } from '../common/AppTheme';
import { WindowMode, connectWindowMode } from '../common/WindowMode';

interface QuizOptionView {
  label: string;
  text: string;
}

@ComponentV2
export struct PersonalityQuizDialog {
  theme: AppTheme = connectAppTheme();
  @Param visible: boolean = false;
  @Event onClose: () => void = () => {};
  quiz: PersonalityQuizStore = connectPersonalityQuiz();
  profileStore: ProfileStore = connectProfileObservations();
  @Local windowMode: WindowMode = connectWindowMode();
  @Computed get isTablet(): boolean {
    return this.windowMode.isTablet;
  }
  // 答题态
  @Local currentIdx: number = 0;       // 当前题（0 起；续做从已答数开始）
  @Local answeredTotal: number = 0;    // 已答总数（驱动进度条/SP 提示）
  @Local finishedView: boolean = false; // 完成视图
  // SP 到账横幅（复用 SP 提示行——零布局跳动）
  @Local toastText: string = '';
  private toastTimer: number = -1;

  aboutToAppear(): void {
    this.syncState();
  }

  aboutToDisappear(): void {
    this.clearToastTimer();
  }

  @Monitor('visible')
  onVisibleChange(): void {
    if (this.visible) {
      this.syncState();
    } else {
      this.clearToastTimer();
    }
  }

  private syncState(): void {
    this.answeredTotal = getQuizAnswers(this.quiz).length;
    this.finishedView = this.quiz.done;
    if (!this.finishedView) {
      this.currentIdx = Math.min(this.answeredTotal, QUIZ_TOTAL - 1);
    }
    this.toastText = '';
  }

  private clearToastTimer(): void {
    if (this.toastTimer >= 0) {
      clearTimeout(this.toastTimer);
      this.toastTimer = -1;
    }
  }

  private showToast(text: string): void {
    this.clearToastTimer();
    this.toastText = text;
    this.toastTimer = setTimeout(() => {
      this.toastText = '';
      this.toastTimer = -1;
    }, 2500);
  }

  /** 距下一 SP 节点还差几题（已满 15 或已领满返回 0） */
  private nextNodeGap(): number {
    if (this.answeredTotal >= QUIZ_TOTAL || this.quiz.claimed >= 3) {
      return 0;
    }
    return 5 - (this.answeredTotal % 5);
  }

  /** 点选项即作答 */
  private onPick(letter: string): void {
    if (this.finishedView) {
      return;
    }
    const total = recordQuizAnswer(this.quiz, letter);
    this.answeredTotal = total;
    const granted = claimQuizSp(this.quiz);
    if (granted > 0) {
      this.showToast(`+${granted} 司忆点已入账`);
    }
    if (total >= QUIZ_TOTAL) {
      writeQuizProfile(this.quiz, this.profileStore);
      this.finishedView = true;
    } else {
      this.currentIdx = Math.min(total, QUIZ_TOTAL - 1);
    }
  }

  build() {
    if (this.visible) {
      Stack({ alignContent: Alignment.Center }) {
        // 遮罩（点击不关闭——答题专注态，退出走 × / 完成按钮）
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.theme.overlay)

        // ── 面板 ──
        Column() {
          if (this.finishedView) {
            this.FinishView()
          } else {
            this.QuizView()
          }
        }
        .width(this.isTablet ? 480 : '90%')
        .constraintSize({ maxHeight: '84%' })
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

  // ── 答题视图 ──
  @Builder
  QuizView() {
    // 头部：题型徽章 + 进度计数 + 关闭
    Row() {
      Text(this.currentQ().tag)
        .fontSize(FONT_SIZE_META)
        .fontColor(this.theme.brandSecondary)
        .padding({ left: 10, right: 10, top: 3, bottom: 3 })
        .backgroundColor(this.theme.hookBg)
        .borderRadius(RADIUS_CONTROL)
      Blank()
      Text(`${this.answeredTotal} / ${QUIZ_TOTAL}`)
        .fontSize(FONT_SIZE_META)
        .fontFamily(FONT_INTER)
        .fontColor(this.theme.textSecondary)
      // 关闭 ×（退出保留进度——下次从已答处继续）
      Text('✕')
        .fontSize(FONT_SIZE_BODY)
        .fontColor(this.theme.textSecondary)
        .width(28)
        .height(28)
        .textAlign(TextAlign.Center)
        .borderRadius(RADIUS_CONTROL)
        .onClick(() => {
          this.onClose();
        })
        .margin({ left: 8 })
    }
    .width('100%')

    // 进度条（15 段）
    Row({ space: 3 }) {
      ForEach(this.progressMarks(), (m: number) => {
        Column()
          .height(4)
          .layoutWeight(1)
          .borderRadius(2)
          .backgroundColor(m === 2 ? this.theme.brandPrimary : (m === 1 ? this.theme.strokeBrand : this.theme.strokeCard))
      }, (m: number) => `${m}`)
    }
    .width('100%')
    .margin({ top: 12 })

    // SP 行（横幅态/提示态一行两用——零布局跳动）
    Row() {
      if (this.toastText.length > 0) {
        Text(this.toastText)
          .fontSize(FONT_SIZE_META)
          .fontColor(this.theme.brandSecondary)
          .fontWeight(FontWeight.Medium)
      } else if (this.nextNodeGap() > 0) {
        Text(`再答 ${this.nextNodeGap()} 题可得 ${QUIZ_SP_PER_NODE} 司忆点`)
          .fontSize(FONT_SIZE_META)
          .fontColor(this.theme.textTertiary)
      }
    }
    .width('100%')
    .height(18)
    .margin({ top: 8 })

    // 题干
    Text(this.currentQ().question)
      .fontSize(FONT_SIZE_SCREEN_TITLE + 1)
      .fontWeight(600)
      .fontFamily(FONT_INTER_SEMIBOLD)
      .fontColor(this.theme.textPrimary)
      .lineHeight(24)
      .margin({ top: 10, bottom: 16 })

    // 选项（点击即作答进入下一题）
    Column({ space: 10 }) {
      ForEach(this.currentQ().options, (o: QuizOptionView, idx: number) => {
        Row({ space: 12 }) {
          Text(o.label)
            .fontSize(FONT_SIZE_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme.brandSecondary)
            .width(26)
            .height(26)
            .textAlign(TextAlign.Center)
            .borderRadius(13)
            .border({ width: 1, color: this.theme.strokeBrand })
          Text(o.text)
            .fontSize(FONT_SIZE_BODY + 1)
            .fontColor(this.theme.textPrimary)
            .layoutWeight(1)
        }
        .alignItems(VerticalAlign.Center)
        .width('100%')
        .padding({ left: 10, right: 14, top: 13, bottom: 13 })
        .borderRadius(RADIUS_NAV)
        .backgroundColor('rgba(0,0,0,0)')
        .border({ width: 1, color: this.theme.strokeCard })
        .onClick(() => {
          this.onPick(['a', 'b', 'c'][idx]);
        })
      }, (o: QuizOptionView) => o.label)
    }
    .width('100%')
  }

  // ── 完成视图 ──
  @Builder
  FinishView() {
    Text('性格画像已生成')
      .fontSize(FONT_SIZE_SCREEN_TITLE + 2)
      .fontWeight(600)
      .fontFamily(FONT_INTER_SEMIBOLD)
      .fontColor(this.theme.textPrimary)
      .margin({ top: 4 })

    Text('AI 已开始按你的性格调整回复——讲解风格、难度、口吻、鼓励方式都会随之变化。日常对话中 AI 还会持续修正这份画像。')
      .fontSize(FONT_SIZE_BODY)
      .lineHeight(20)
      .fontColor(this.theme.textSecondary)
      .margin({ top: 10 })

    Scroll() {
      Column({ space: 10 }) {
        ForEach(quizProfilePreview(getQuizAnswers(this.quiz)), (line: string) => {
          Row({ space: 8 }) {
            Column()
              .width(5)
              .height(5)
              .borderRadius(2.5)
              .backgroundColor(this.theme.brandPrimary)
              .margin({ top: 6 })
            Text(line)
              .fontSize(FONT_SIZE_BODY)
              .fontColor(this.theme.textSecondary)
              .layoutWeight(1)
          }
          .alignItems(VerticalAlign.Top)
          .width('100%')
        }, (line: string) => line)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .constraintSize({ maxHeight: 240 })
    .width('100%')
    .margin({ top: 14 })
    .align(Alignment.TopStart)

    Button('完成')
      .width('100%')
      .height(46)
      .fontSize(FONT_SIZE_SCREEN_TITLE)
      .fontWeight(FontWeight.Medium)
      .backgroundColor(this.theme.brandPrimary)
      .fontColor(this.theme.textPrimary)
      .borderRadius(RADIUS_CONTROL)
      .margin({ top: 16 })
      .onClick(() => {
        this.onClose();
      })
  }

  // ── 辅助 ──
  private currentQ(): QuizQuestion {
    return PERSONALITY_QUESTIONS[this.currentIdx];
  }

  /** 进度条 15 段状态：2=已答 1=当前 0=未答 */
  private progressMarks(): number[] {
    const marks: number[] = [];
    for (let i = 0; i < QUIZ_TOTAL; i++) {
      if (i < this.answeredTotal) {
        marks.push(2);
      } else if (i === this.answeredTotal && !this.finishedView) {
        marks.push(1);
      } else {
        marks.push(0);
      }
    }
    return marks;
  }
}