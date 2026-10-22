// PersonalityQuizDialog.ets — ★ 0.288.0 性格测试弹窗（15 题混合穿插）
//   ★ 0.290.0 性格测试 2.0：三选一点击流 → 开放题文本输入 + 确认（WP1）；
//   ★ 0.292.1 性格测试 3.0（用户拍板）：开放题撤除回归纯选择题——12 单选 + 3 多选，
//   点选选项（单选可换选/多选可增减）+ 统一「下一题」按钮提交；零文本输入。
//   15 题答完 → SP 发放不阻塞 → AI 评阅画像异步进行（完成页 loading 态→到达刷新预览）。
//   宿主：BBTreeCanvas（画布左下角「信号灯」呼吸圆点唤起，做完消失）
//   交互：断点续做（答案即时落盘，退出再进续做）；每 5 题发 2000 司忆点（3 节点，claimed 幂等）。
//   样式：0.190.8 弹窗模板同款；宽度断点制手机 '90%' / 平板 PC 480。
//   ★ 0.288.2 ForEach key 纪律：选项 key 掺题索引+字母（`q{idx}-{label}`）——值集重复
//   会让跨题复用组件错乱/key 碰撞，永不回退；进度段 key 仍掺段索引。

import {
  PERSONALITY_QUESTIONS, QUIZ_TOTAL, QUIZ_SP_PER_NODE, QuizQuestion, QuizOption,
  PersonalityQuizStore, QuizProfileLine, connectPersonalityQuiz,
  recordQuizAnswerEntry, quizAnswerTotal, claimQuizSp,
  writeQuizProfile, quizProfilePreviewLines, isInvalidQuizAnswer
} from '../common/PersonalityQuiz';
import { ProfileStore, connectProfileObservations } from '../common/ProfileModel';
import { connectApiConfig } from '../common/ChatModel';
import { siyiGateReady } from '../utils/SiyiGate'; // ★ 0.298.0：SP 铁律——答题=SP 获得，弹窗开启防御性闸门检查
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
  @Local selectedLetters: string[] = []; // ★ 0.292.1 当前题选中字母草稿（切题清空；单选 1 项/多选 1~选项数）
  @Local finishedView: boolean = false; // 完成视图
  // ★ 0.298.0 自定义答案态（「以上都不像——我想自己说」）
  @Local customSelected: boolean = false; // 当前题选中自定义（单选与字母互斥/多选可共存）
  @Local customText: string = '';         // 自定义补充文本草稿（placeholder 灰提示，输入即隐）
  // ★ 0.298.0 开场引导页（首次作答讲清「为什么做」；断点续做跳过）
  @Local started: boolean = false;
  // ★ 0.298.0 SP 节点奖励弹窗（toast 横幅升级为仪式感弹窗；pendingAdvance=弹窗确认后才推进题号）
  @Local rewardVisible: boolean = false;
  @Local rewardAmount: number = 0;
  @Local rewardIsFinal: boolean = false;
  @Local pendingAdvance: boolean = false;
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
      // ★ 0.298.0 防御性闸门：答题=SP 获得（SP 铁律），两入口已前置拦截，
      //   此处兜底中途掉闸（退出登录/关云同步后从后台续进）——未就绪直接收弹窗
      if (!siyiGateReady() && !this.quiz.done) {
        this.onClose();
        return;
      }
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
    this.selectedLetters = [];
    this.customSelected = false; // ★ 0.298.0 自定义草稿随切题/重开清空
    this.customText = '';
    this.started = this.answeredTotal > 0 || this.finishedView; // ★ 0.298.0 断点续做跳过开场页
    this.rewardVisible = false;
    this.pendingAdvance = false;
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

  /** 点击选项：单选=换选（恒 1 项，与自定义互斥）；多选=增减切换 */
  private toggleOption(label: string): void {
    if (this.finishedView) {
      return;
    }
    const upper = label.toLowerCase();
    if (this.currentQ().multi) {
      const at = this.selectedLetters.indexOf(upper);
      if (at >= 0) {
        this.selectedLetters.splice(at, 1);
      } else {
        this.selectedLetters.push(upper);
      }
    } else {
      this.selectedLetters = [upper]; // 单选换选（数组整体重赋值——@Local 刷新安全）
      this.customSelected = false;    // ★ 0.298.0 单选互斥：选字母清自定义
      this.customText = '';
    }
  }

  /** ★ 0.298.0 点击「以上都不像——我想自己说」：单选=与字母互斥；多选=增减切换 */
  private toggleCustom(): void {
    if (this.finishedView) {
      return;
    }
    if (this.currentQ().multi) {
      this.customSelected = !this.customSelected;
      if (!this.customSelected) {
        this.customText = ''; // 取消自定义清草稿
      }
    } else {
      this.customSelected = true;
      this.selectedLetters = []; // 单选互斥：自定义顶掉字母选择
    }
  }

  private isSelected(label: string): boolean {
    return this.selectedLetters.indexOf(label.toLowerCase()) >= 0;
  }

  /** 确认当前题答案（至少选 1 项或填自定义；自定义文本须过敷衍判定；字母升序+自定义原子双落盘） */
  private onSubmitAnswer(): void {
    if (this.finishedView) {
      return;
    }
    // ★ 0.298.0 提交拦截三态：全空 / 自定义敷衍 / 正常
    if (this.selectedLetters.length === 0 && !this.customSelected) {
      this.showToast(this.currentQ().multi ? '至少选一项再继续吧' : '选一个再继续吧');
      return;
    }
    if (this.customSelected && isInvalidQuizAnswer(this.customText)) {
      this.showToast('再多写几个字，AI 才能懂你');
      return;
    }
    const sorted = this.selectedLetters.slice().sort();
    recordQuizAnswerEntry(this.quiz, sorted.join(''), this.customSelected ? this.customText : '');
    this.selectedLetters = [];
    this.customSelected = false;
    this.customText = '';
    const total = quizAnswerTotal(this.quiz);
    this.answeredTotal = total;
    const granted = claimQuizSp(this.quiz);
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
      if (granted > 0) {
        // ★ 0.298.0 末节点奖励弹窗（叠在完成页上；按钮「完成」只关弹窗——画像后台生成用户无需跳转查看）
        this.rewardAmount = granted;
        this.rewardIsFinal = true;
        this.rewardVisible = true;
      }
    } else {
      if (granted > 0) {
        // ★ 0.298.0 中途节点奖励弹窗：确认「继续答题」才推进题号（仪式感拍板）
        this.rewardAmount = granted;
        this.rewardIsFinal = false;
        this.rewardVisible = true;
        this.pendingAdvance = true;
      } else {
        this.currentIdx = Math.min(total, QUIZ_TOTAL - 1);
      }
    }
  }

  /** ★ 0.298.0 奖励弹窗确认：中途节点=推进下一题；末节点=关弹窗露完成页 */
  private onRewardConfirm(): void {
    this.rewardVisible = false;
    if (this.pendingAdvance) {
      this.pendingAdvance = false;
      this.currentIdx = Math.min(this.answeredTotal, QUIZ_TOTAL - 1);
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
          } else if (!this.started) {
            // ★ 0.298.0 开场引导页（首次作答讲清「为什么做」——建立画像让 AI 更懂你）
            this.StartView()
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

        // ★ 0.298.0 SP 节点奖励弹窗（叠层——遮罩压主面板，居中小卡仪式感）
        if (this.rewardVisible) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.theme.overlay)
            .onClick(() => {
              // 点遮罩不关——仪式感必须经按钮确认（与 RookieRewardDialog 同款纪律）
            })
          Column() {
            Text('恭喜！')
              .fontSize(FONT_SIZE_SCREEN_TITLE + 2)
              .fontWeight(600)
              .fontFamily(FONT_INTER_SEMIBOLD)
              .fontColor(this.theme.textPrimary)
            Text(this.rewardIsFinal
              ? `15 道题全部完成，+${this.rewardAmount} 司忆点已入账`
              : `已完成前 ${Math.min(this.answeredTotal, QUIZ_TOTAL)} 题，+${this.rewardAmount} 司忆点已入账`)
              .fontSize(FONT_SIZE_BODY)
              .lineHeight(20)
              .fontColor(this.theme.textSecondary)
              .margin({ top: 10 })
              .textAlign(TextAlign.Center)
            Button(this.rewardIsFinal ? '完成' : '继续答题')
              .width('100%')
              .height(44)
              .fontSize(FONT_SIZE_SCREEN_TITLE)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(this.theme.brandPrimary)
              .fontColor(this.theme.textPrimary)
              .borderRadius(RADIUS_CONTROL)
              .margin({ top: 18 })
              .onClick(() => {
                this.onRewardConfirm();
              })
          }
          .width(this.isTablet ? 360 : '80%')
          .padding(22)
          .borderRadius(RADIUS_NAV)
          .backgroundColor(this.theme.surfaceNode)
          .border({ width: 1, color: this.theme.strokeCard })
          .shadow({ radius: 24, color: this.theme.shadowColor, offsetX: 0, offsetY: 10 })
        }
      }
      .width('100%')
      .height('100%')
    }
  }

  // ── ★ 0.298.0 开场引导页（为什么做：画像让 AI 更懂你；奖励预期；确认后开始） ──
  @Builder
  StartView() {
    Text('先让 AI 认识真正的你')
      .fontSize(FONT_SIZE_SCREEN_TITLE + 2)
      .fontWeight(600)
      .fontFamily(FONT_INTER_SEMIBOLD)
      .fontColor(this.theme.textPrimary)
      .margin({ top: 4 })

    Text('15 道小题，约 3 分钟。答完 AI 会为你生成专属学习画像——之后讲解的深浅、说话的口吻、鼓励的方式，都会更贴近真实的你。遇到不像你的选项，也可以用自己的话补充。')
      .fontSize(FONT_SIZE_BODY)
      .lineHeight(21)
      .fontColor(this.theme.textSecondary)
      .margin({ top: 12 })

    Text(`全程 3 个节点，共 ${QUIZ_SP_PER_NODE * 3} 司忆点（每答 5 题得 ${QUIZ_SP_PER_NODE}）`)
      .fontSize(FONT_SIZE_META)
      .fontColor(this.theme.brandSecondary)
      .margin({ top: 10 })

    Button('开始答题')
      .width('100%')
      .height(46)
      .fontSize(FONT_SIZE_SCREEN_TITLE)
      .fontWeight(FontWeight.Medium)
      .backgroundColor(this.theme.brandPrimary)
      .fontColor(this.theme.textPrimary)
      .borderRadius(RADIUS_CONTROL)
      .margin({ top: 22 })
      .onClick(() => {
        this.started = true;
      })

    Button('下次再说')
      .fontSize(FONT_SIZE_BODY)
      .fontColor(this.theme.textTertiary)
      .backgroundColor(Color.Transparent)
      .height(36)
      .margin({ top: 4 })
      .onClick(() => {
        this.onClose();
      })
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

    // 题干 + 选项列表（整体可滚——多选题 5 选项+长文案小屏防溢出）
    Scroll() {
      Column() {
        // 题干
        Text(this.currentQ().question)
          .fontSize(FONT_SIZE_SCREEN_TITLE + 1)
          .fontWeight(600)
          .fontFamily(FONT_INTER_SEMIBOLD)
          .fontColor(this.theme.textPrimary)
          .lineHeight(24)
          .margin({ top: 10, bottom: 12 })
          .width('100%')

        // ★ 0.292.1 选项列表（单选=换选 / 多选=切换）
        ForEach(this.currentQ().options, (o: QuizOption) => {
          Row({ space: 10 }) {
            // 字母圆标（选中=紫底白字 / 未选=描边圆）
            Text(o.label)
              .fontSize(FONT_SIZE_META)
              .fontFamily(FONT_INTER)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isSelected(o.label) ? '#FFFFFF' : this.theme.textSecondary)
              .width(24)
              .height(24)
              .textAlign(TextAlign.Center)
              .borderRadius(12)
              .backgroundColor(this.isSelected(o.label) ? this.theme.brandPrimary : this.theme.surfaceSoft)
              .border({ width: 1, color: this.isSelected(o.label) ? this.theme.brandPrimary : this.theme.strokeCard })
            // 选项文案
            Text(o.text)
              .fontSize(FONT_SIZE_BODY)
              .fontColor(this.isSelected(o.label) ? this.theme.textPrimary : this.theme.textSecondary)
              .layoutWeight(1)
              .lineHeight(20)
            // 选中对勾（多选/单选统一右缘反馈）
            if (this.isSelected(o.label)) {
              Text('✓')
                .fontSize(FONT_SIZE_BODY)
                .fontColor(this.theme.brandPrimary)
                .fontWeight(FontWeight.Medium)
            }
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .padding({ left: 10, right: 10, top: 11, bottom: 11 })
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(this.isSelected(o.label) ? this.theme.hookBg : this.theme.surfaceSoft)
          .border({ width: 1, color: this.isSelected(o.label) ? this.theme.brandPrimary : this.theme.strokeCard })
          .margin({ bottom: 8 })
          .onClick(() => {
            this.toggleOption(o.label);
          })
        }, (o: QuizOption) => `q${this.currentIdx}-${o.label}`) // ★ 0.288.2：key 掺题索引+字母——跨题复用永不碰撞

        // ★ 0.298.0 自定义答案行「以上都不像——我想自己说」（虚线描边区分常规选项）
        Column() {
          Row({ space: 10 }) {
            Text('…')
              .fontSize(FONT_SIZE_BODY)
              .fontFamily(FONT_INTER)
              .fontColor(this.customSelected ? '#FFFFFF' : this.theme.textSecondary)
              .width(24)
              .height(24)
              .textAlign(TextAlign.Center)
              .borderRadius(12)
              .backgroundColor(this.customSelected ? this.theme.brandPrimary : this.theme.surfaceSoft)
              .border({ width: 1, color: this.customSelected ? this.theme.brandPrimary : this.theme.strokeCard })
            Text('以上都不像——我想自己说')
              .fontSize(FONT_SIZE_BODY)
              .fontColor(this.customSelected ? this.theme.textPrimary : this.theme.textSecondary)
              .layoutWeight(1)
              .lineHeight(20)
            if (this.customSelected) {
              Text('✓')
                .fontSize(FONT_SIZE_BODY)
                .fontColor(this.theme.brandPrimary)
                .fontWeight(FontWeight.Medium)
            }
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .padding({ left: 10, right: 10, top: 11, bottom: 11 })
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(this.customSelected ? this.theme.hookBg : this.theme.surfaceSoft)
          .border({
            width: 1,
            color: this.customSelected ? this.theme.brandPrimary : this.theme.strokeCard,
            style: this.customSelected ? BorderStyle.Solid : BorderStyle.Dashed // 未选=虚线示意「可以自己写」
          })
          .onClick(() => {
            this.toggleCustom();
          })

          // 自定义输入框（选中展开；placeholder 灰提示输入即隐）
          if (this.customSelected) {
            TextArea({ text: this.customText, placeholder: '用一句话描述你的真实情况' })
              .onChange((v: string) => {
                this.customText = v;
              })
              .width('100%')
              .constraintSize({ minHeight: 64 })
              .fontSize(FONT_SIZE_BODY)
              .fontColor(this.theme.textPrimary)
              .placeholderColor(this.theme.textTertiary)
              .borderRadius(RADIUS_CONTROL)
              .backgroundColor(this.theme.surfaceSoft)
              .border({ width: 1, color: this.theme.strokeCard })
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .margin({ top: 8 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .constraintSize({ maxHeight: 320 })
    .width('100%')
    .align(Alignment.TopStart)
    .scrollBar(BarState.Off)

    // 确认按钮（第 15 题=「完成答题」；多选题实时显示已选数）
    Button(this.confirmLabel())
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

  /** 确认按钮文案：末题=完成答题；多选已选≥2 项时带已选数反馈 */
  private confirmLabel(): string {
    const base = this.answeredTotal >= QUIZ_TOTAL - 1 ? '完成答题' : '确认，下一题';
    const picked = this.selectedLetters.length + (this.customSelected ? 1 : 0); // ★ 0.298.0 自定义计 1 项
    if (this.currentQ().multi && picked > 1) {
      return `${base}（已选 ${picked} 项）`;
    }
    return base;
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