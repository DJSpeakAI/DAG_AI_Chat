// ClarifyCard.ets — ★ 0.300.0 司枢 Agent 3.0 反问收束卡（对话流内嵌）
// 交互先例=性格测试 3.0 点选流（PersonalityQuizDialog 0.292.1/0.298.0：单选可换选/多选可增减/
// 「以上都不像——我想自己说」自定义行）；数据源=SishuClarifyStore（AppStorageV2 应用级），
// @ComponentV2+@Event 桥接（0.295.0 拆分模式）；宽度断点制通规（UI_GUIDELINES 12a）。
// 挂载点=ChatPage 消息流（关联 AI 气泡下方，规划卡同族位置）；一任务最多 1 轮反问（军令）。
import { AppTheme, connectAppTheme } from '../common/AppTheme';
import { ClarifyQuestion, SishuClarifyState, connectSishuClarify } from '../common/SishuAgent';

const LETTERS: string[] = ['A', 'B', 'C', 'D'];

@ComponentV2
export struct ClarifyCard {
  @Event onSubmit: (answers: string[]) => void = () => {}; // 每题答案文本（选中项顿号连接+「自定义：xxx」）
  @Event onSkip: () => void = () => {};                    // 跳过=按契约默认假设直接执笔
  @Local clarify: SishuClarifyState = connectSishuClarify();
  theme: AppTheme = connectAppTheme();
  // 每题作答草稿（索引对位；多选=多字母拼接串如 "AC"；@Local 数组元素整体重赋值刷新）
  @Local selectedByQ: string[] = [];
  @Local customSelByQ: boolean[] = [];
  @Local customTextByQ: string[] = [];
  @Local toastTip: string = '';

  private optionLabel(oi: number): string {
    return oi < LETTERS.length ? LETTERS[oi] : `${oi + 1}`;
  }

  private ensureDrafts(): void {
    const n = this.clarify.questions.length;
    while (this.selectedByQ.length < n) {
      this.selectedByQ.push('');
      this.customSelByQ.push(false);
      this.customTextByQ.push('');
    }
  }

  private toggleOption(qi: number, oi: number): void {
    this.ensureDrafts();
    const letter = this.optionLabel(oi);
    const cur = this.selectedByQ[qi];
    const q = this.clarify.questions[qi];
    if (q.multi) {
      // 多选：增减切换（字母在串中=移除/不在=追加）
      const at = cur.indexOf(letter);
      const next = at >= 0 ? cur.replace(letter, '') : `${cur}${letter}`;
      this.selectedByQ[qi] = next.split('').sort().join('');
    } else {
      // 单选：换选，与自定义互斥
      this.selectedByQ[qi] = cur === letter ? '' : letter;
      this.customSelByQ[qi] = false;
      this.customTextByQ[qi] = '';
    }
  }

  private toggleCustom(qi: number): void {
    this.ensureDrafts();
    const q = this.clarify.questions[qi];
    if (q.multi) {
      this.customSelByQ[qi] = !this.customSelByQ[qi];
      if (!this.customSelByQ[qi]) {
        this.customTextByQ[qi] = '';
      }
    } else {
      this.customSelByQ[qi] = true;
      this.selectedByQ[qi] = ''; // 单选互斥：自定义顶掉字母选择
    }
  }

  private isSel(qi: number, oi: number): boolean {
    return this.selectedByQ.length > qi && this.selectedByQ[qi].indexOf(this.optionLabel(oi)) >= 0;
  }

  private buildAnswerTexts(): string[] {
    this.ensureDrafts();
    const out: string[] = [];
    for (let qi = 0; qi < this.clarify.questions.length; qi++) {
      const q = this.clarify.questions[qi];
      const parts: string[] = [];
      const sel = this.selectedByQ[qi];
      for (let oi = 0; oi < q.options.length; oi++) {
        if (sel.indexOf(this.optionLabel(oi)) >= 0) {
          parts.push(q.options[oi]);
        }
      }
      if (this.customSelByQ[qi] && this.customTextByQ[qi].trim().length > 0) {
        parts.push(`自定义：${this.customTextByQ[qi].trim()}`);
      }
      out.push(parts.join('；'));
    }
    return out;
  }

  private submitAnswers(): void {
    const answers = this.buildAnswerTexts();
    let any = false;
    for (let i = 0; i < answers.length; i++) {
      if (answers[i].length > 0) {
        any = true;
        break;
      }
    }
    if (!any) {
      this.toastTip = '选一项或填写自定义，也可以直接跳过';
      return;
    }
    this.clarify.visible = false;
    this.onSubmit(answers);
  }

  private skipClarify(): void {
    this.clarify.visible = false;
    this.onSkip();
  }

  build() {
    // 卡片本体（visible 由宿主 ChatPage 控制 if 挂载；此处只渲染内容）
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('开工前确认')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.brandSecondary)
          .layoutWeight(1)
        Text(`${this.clarify.questions.length} 个小问题`)
          .fontSize(11)
          .fontColor(this.theme.textTertiary)
      }
      .width('100%')

      Scroll() {
        Column({ space: 10 }) {
          ForEach(this.clarify.questions, (q: ClarifyQuestion, qi: number) => {
            Column({ space: 8 }) {
              Text(`${qi + 1}. ${q.q}`)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.theme.textPrimary)
                .lineHeight(19)
                .width('100%')
              ForEach(q.options, (opt: string, oi: number) => {
                Row({ space: 10 }) {
                  Text(this.optionLabel(oi))
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.isSel(qi, oi) ? '#FFFFFF' : this.theme.textSecondary)
                    .width(22)
                    .height(22)
                    .textAlign(TextAlign.Center)
                    .borderRadius(11)
                    .backgroundColor(this.isSel(qi, oi) ? this.theme.brandPrimary : this.theme.surfaceSoft)
                    .border({ width: 1, color: this.isSel(qi, oi) ? this.theme.brandPrimary : this.theme.strokeCard })
                  Text(opt)
                    .fontSize(12)
                    .fontColor(this.isSel(qi, oi) ? this.theme.textPrimary : this.theme.textSecondary)
                    .layoutWeight(1)
                    .lineHeight(18)
                  if (this.isSel(qi, oi)) {
                    Text('✓')
                      .fontSize(13)
                      .fontColor(this.theme.brandPrimary)
                      .fontWeight(FontWeight.Medium)
                  }
                }
                .alignItems(VerticalAlign.Center)
                .width('100%')
                .padding({ left: 9, right: 9, top: 9, bottom: 9 })
                .borderRadius(10)
                .backgroundColor(this.isSel(qi, oi) ? this.theme.hookBg : this.theme.surfaceSoft)
                .border({ width: 1, color: this.isSel(qi, oi) ? this.theme.brandPrimary : this.theme.strokeCard })
                .onClick(() => {
                  this.toggleOption(qi, oi);
                })
              }, (_opt: string, oi: number) => `cq${qi}-${this.optionLabel(oi)}`) // key 掺题索引+字母（0.288.2 防碰撞防线）

              // 自定义行（虚线描边区分——性格测试 3.0 同款视觉语言）
              Column() {
                Row({ space: 10 }) {
                  Text('…')
                    .fontSize(13)
                    .fontColor(this.customSelByQ[qi] ? '#FFFFFF' : this.theme.textSecondary)
                    .width(22)
                    .height(22)
                    .textAlign(TextAlign.Center)
                    .borderRadius(11)
                    .backgroundColor(this.customSelByQ[qi] ? this.theme.brandPrimary : this.theme.surfaceSoft)
                    .border({ width: 1, color: this.customSelByQ[qi] ? this.theme.brandPrimary : this.theme.strokeCard })
                  Text('以上都不像——我想自己说')
                    .fontSize(12)
                    .fontColor(this.customSelByQ[qi] ? this.theme.textPrimary : this.theme.textSecondary)
                    .layoutWeight(1)
                    .lineHeight(18)
                }
                .alignItems(VerticalAlign.Center)
                .width('100%')
                .padding({ left: 9, right: 9, top: 9, bottom: 9 })
                .borderRadius(10)
                .backgroundColor(this.customSelByQ[qi] ? this.theme.hookBg : this.theme.surfaceSoft)
                .border({
                  width: 1,
                  color: this.customSelByQ[qi] ? this.theme.brandPrimary : this.theme.strokeCard,
                  style: this.customSelByQ[qi] ? BorderStyle.Solid : BorderStyle.Dashed
                })
                .onClick(() => {
                  this.toggleCustom(qi);
                })
                if (this.customSelByQ[qi]) {
                  TextArea({ text: this.customTextByQ[qi], placeholder: '用一句话说清你的要求' })
                    .onChange((v: string) => {
                      this.customTextByQ[qi] = v;
                    })
                    .width('100%')
                    .constraintSize({ minHeight: 56 })
                    .fontSize(12)
                    .fontColor(this.theme.textPrimary)
                    .placeholderColor(this.theme.textTertiary)
                    .borderRadius(10)
                    .backgroundColor(this.theme.surfaceSoft)
                    .border({ width: 1, color: this.theme.strokeCard })
                    .padding({ left: 9, right: 9, top: 7, bottom: 7 })
                    .margin({ top: 6 })
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }, (_q: ClarifyQuestion, qi: number) => `cq-sec-${qi}`)

          if (this.toastTip.length > 0) {
            Text(this.toastTip)
              .fontSize(11)
              .fontColor('#FF6B6B')
              .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .constraintSize({ maxHeight: 260 })
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)

      // 底部双钮：提交主操作在左（0.196.9 confirmOnLeft 同语义）+跳过次操作
      Row({ space: 10 }) {
        Text('按这些开始')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(16)
          .backgroundColor(this.theme.brandPrimary)
          .onClick(() => {
            this.submitAnswers();
          })
        Text('跳过（按默认假设做）')
          .fontSize(12)
          .fontColor(this.theme.textSecondary)
          .padding({ left: 12, right: 12, top: 9, bottom: 9 })
          .borderRadius(16)
          .backgroundColor(this.theme.surfaceSoft)
          .border({ width: 1, color: this.theme.strokeCard })
          .onClick(() => {
            this.skipClarify();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(this.theme.hookBg)
    .border({ width: 1, color: this.theme.strokeCard })
  }
}
