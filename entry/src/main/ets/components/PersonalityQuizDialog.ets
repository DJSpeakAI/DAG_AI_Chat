// PersonalityQuizDialog.ets — ★ 0.288.0 性格测试弹窗（15 题混合穿插）
//   ★ 0.290.0 性格测试 2.0：三选一点击流 → 开放题文本输入 + 确认（WP1）；
//   15 题答完 → SP 发放不阻塞 → AI 评阅画像异步进行（完成页 loading 态→到达刷新预览）。
//   宿主：BBTreeCanvas（画布左下角「信号灯」呼吸圆点唤起，做完消失）
//   交互：输入 1~3 句自由文本确认作答（答案即时落盘，退出再进续做；无硬性字数要求）；
//   每 5 题发 2000 司忆点（3 节点，claimed 幂等）。
//   样式：0.190.8 弹窗模板同款；宽度断点制手机 '90%' / 平板 PC 480。
//   ★ 0.288.2 ForEach key 纪律：选项点击流已随开放题化删除（key 碰撞雷根除）；
//   进度段 key 仍掺段索引。

import {
  PERSONALITY_QUESTIONS, QUIZ_TOTAL, QUIZ_SP_PER_NODE, QuizQuestion,
  PersonalityQuizStore, QuizProfileLine, connectPersonalityQuiz,
  recordQuizAnswerText, quizAnswerTotal, claimQuizSp,
  writeQuizProfile, quizProfilePreviewLines
} from '../common/PersonalityQuiz';
import { ProfileStore, connectProfileObservations } from '../common/ProfileModel';
import { connectApiConfig } from '../common/ChatModel';
import { RADIUS_NAV, RADIUS_CONTROL, FONT_SIZE_SCREEN_TITLE, FONT_SIZE_BODY, FONT_SIZE_META, FONT_INTER_SEMIBOLD, FONT_INTER } from '../common/DesignTokens';
import { AppTheme, connectAppTheme } from '../common/AppTheme';
import { WindowMode, connectWindowMode } from '../common/WindowMode';

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
  @Local answerDraft: string = '';     // 当前题输入草稿（切题清空）
  @Local finishedView: boolean = false; // 完成视图
  // ★ 0.290.0 完成页评阅态：画像行未到达=进行态（三点动画），到达=列表预览
  @Local previewLines: string[] = [];
  @Local reviewing: boolean = false;
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
    this.answeredTotal = quizAnswerTotal(this.quiz);
    this.finishedView = this.quiz.done;
    this.previewLines = [];
    this.reviewing = this.quiz.done && !this.quiz.profileWritten;
    if (!this.finishedView) {
      this.currentIdx = Math.min(this.answeredTotal, QUIZ_TOTAL - 1);
    }
    this.answerDraft = '';
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

  /** 确认当前题答案（开放文本；空文本拦截、敷衍放行——评阅侧判无效走均衡兜底） */
  private onSubmitAnswer(): void {
    if (this.finishedView) {
      return;
    }
    const text = this.answerDraft.trim();
    if (text.length === 0) {
      this.showToast('写点你的真实情况再继续吧');
      return;
    }
    const total = recordQuizAnswerText(this.quiz, text);
    this.answeredTotal = total;
    this.answerDraft = '';
    const granted = claimQuizSp(this.quiz);
    if (granted > 0) {
      this.showToast(`+${granted} 司忆点已入账`);
    }
    if (total >= QUIZ_TOTAL) {
      // 15 题答完：done 立即置位 + SP 不阻塞；评阅异步（onResult 刷新完成页预览）
      this.reviewing = true;
      this.previewLines = [];
      writeQuizProfile(this.quiz, this.profileStore, connectApiConfig(),
        (lines: QuizProfileLine[]): void => {
          this.previewLines = quizProfilePreviewLines(lines);
          this.reviewing = false;
        });
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
      }, (m: number, idx: number) => `${idx}-${m}`) // ★ 0.288.2：key 掺段索引——值集 {0,1,2} 大量重复致 key 碰撞，进度段永不刷新
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
      .margin({ top: 10, bottom: 12 })

    // 开放题输入区（1~3 句自由文本；无硬性字数要求）
    TextArea({ placeholder: '用 1~3 句话写写你的真实情况，越具体画像越准', text: this.answerDraft })
      .fontSize(FONT_SIZE_BODY)
      .fontColor(this.theme.textPrimary)
      .placeholderColor(this.theme.textTertiary)
      .constraintSize({ minHeight: 96, maxHeight: 160 })
      .width('100%')
      .padding(10)
      .borderRadius(RADIUS_CONTROL)
      .backgroundColor(this.theme.surfaceSoft)
      .border({ width: 1, color: this.theme.strokeCard })
      .maxLength(300)
      .onChange((v: string) => {
        this.answerDraft = v;
      })

    // 确认按钮（第 15 题=「完成答题」）
    Button(this.answeredTotal >= QUIZ_TOTAL - 1 ? '完成答题' : '确认，下一题')
      .width('100%')
      .height(44)
      .fontSize(FONT_SIZE_SCREEN_TITLE)
      .fontWeight(FontWeight.Medium)
      .backgroundColor(this.theme.brandPrimary)
      .fontColor(this.theme.textPrimary)
      .borderRadius(RADIUS_CONTROL)
      .margin({ top: 12 })
      .onClick(() => {
        this.onSubmitAnswer();
      })
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

    if (this.reviewing) {
      // 评阅进行态（AI 评阅/本地兜底到达前；断网场景几秒内兜底落位）
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          LoadingDots()
          Text('AI 正在阅读你的 15 个答案，生成专属画像…')
            .fontSize(FONT_SIZE_BODY)
            .fontColor(this.theme.textSecondary)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .margin({ top: 18 })
    } else {
      Text('AI 已开始按你的性格调整回复——讲解风格、难度、口吻、鼓励方式都会随之变化。日常对话中 AI 还会持续修正这份画像。')
        .fontSize(FONT_SIZE_BODY)
        .lineHeight(20)
        .fontColor(this.theme.textSecondary)
        .margin({ top: 10 })

      Scroll() {
        Column({ space: 10 }) {
          ForEach(this.previewLines, (line: string) => {
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
    }

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

/** ★ 0.290.0 完成页评阅进行态三点动画（弹窗内轻量版——WaitingDots 随 ChatPage 整件，
 *   弹窗自绘三点半径 3 呼吸；brandSecondary token 取色禁散落色值） */
@ComponentV2
struct LoadingDots {
  theme: AppTheme = connectAppTheme();
  @Local tick: number = 0;
  private timer: number = -1;

  aboutToAppear(): void {
    this.timer = setInterval((): void => {
      this.tick += 1;
    }, 450);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  build() {
    Row({ space: 4 }) {
      ForEach([0, 1, 2], (i: number) => {
        Column()
          .width(6)
          .height(6)
          .borderRadius(3)
          .backgroundColor(this.theme.brandSecondary)
          .opacity(((this.tick + i) % 3 === 0) ? 0.25 : 1)
      }, (i: number) => `${i}`)
    }
  }
}
