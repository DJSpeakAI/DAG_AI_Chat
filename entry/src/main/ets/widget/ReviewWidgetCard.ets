// ============================================================
// ReviewWidgetCard.ets — ★ 0.204.0 桌面卡片 UI（卡片上直接复习）
// ============================================================
// 用户拍板：去掉跳 APP——卡片自闭环：切库（单词库/知识卡）+ 三档评分，
//   全部 postCardAction message → EntryFormAbility.onFormEvent 快照内推进。
// 规格（supportDimensions 2×2/2×4/4×4，dimension 键由 onSizeChanged 写入）：
//   2=2×2 紧凑（模式标签+标题1行+释义2行+小按钮）
//   3=2×4 标准（切库 pill+标题+释义+三按钮）
//   4=4×4 大卡（切库+统计行+大标题+长释义+大按钮+今日三档统计）
// 完成态：纯文案+统计（无跳转——用户明确拍板去掉）。
// 注意：卡片环境 API 受限——纯 UI + postCardAction，无复杂逻辑。
// ============================================================

const BG_CARD = '#1C1130';        // 卡片底（暗紫，深于 SURFACE_NODE 与桌面协调）
const TITLE_COLOR = '#F4F1FA';
const SUB_COLOR = '#B9B3C7';
const ACCENT = '#9B7BFF';         // 辅助紫（与主应用 BRAND_SECONDARY 同族）
// 三档评分配色（与主应用 ReviewPage 一致：生疏红/尚可橙/熟知绿，0x26 ���明底）
const HARD_COLOR = '#E5484D';
const GOOD_COLOR = '#F5A623';
const EASY_COLOR = '#3BB273';
const HARD_BG = '#26E5484D';
const GOOD_BG = '#26F5A623';
const EASY_BG = '#263BB273';

let storage = new LocalStorage();

@Entry(storage)
@Component
struct ReviewWidgetCard {
  @LocalStorageProp('mode') mode: string = 'knowledge';
  @LocalStorageProp('title') title: string = '';
  @LocalStorageProp('definition') definition: string = '';
  @LocalStorageProp('progress') progress: string = '';
  @LocalStorageProp('remain') remain: string = '0';
  @LocalStorageProp('done') done: string = 'n';
  @LocalStorageProp('dimension') dimension: string = '3';
  @LocalStorageProp('hard') hard: string = '0';
  @LocalStorageProp('good') good: string = '0';
  @LocalStorageProp('easy') easy: string = '0';
  @LocalStorageProp('noMore') noMore: string = 'n';

  dim(): number {
    return Number(this.dimension);
  }

  // ── 交互出口（★ 0.204.1 定稿：call 通道——message 的 msg 在本机桌面被 IPC 剥空，
  //    A/B 组实验均为 ''；call 的 params 与 router 同通路已验证可穿透）──
  // call 后台拉起 EntryAbility（不显示 UI）→ 主应用进程真数据评分 → updateForm 推回卡片
  sendRate(rating: string): void {
    postCardAction(this, {
      'action': 'call',
      'abilityName': 'EntryAbility',
      'method': 'widgetRate',
      'params': { 'method': 'widgetRate', 'cmd': 'rate', 'rating': rating }
    });
  }

  sendSwitch(target: string): void {
    postCardAction(this, {
      'action': 'call',
      'abilityName': 'EntryAbility',
      'method': 'widgetSwitch',
      'params': { 'method': 'widgetSwitch', 'cmd': 'switch', 'mode': target }
    });
  }

  // ★ 0.204.2：继续复习——完成态点击拉未来队列继续背（call 通道同上）
  sendContinue(): void {
    postCardAction(this, {
      'action': 'call',
      'abilityName': 'EntryAbility',
      'method': 'widgetContinue',
      'params': { 'method': 'widgetContinue', 'cmd': 'continue' }
    });
  }

  // ── 切库 pill（当前模式高亮；2×2 放不下纯展示标签）──
  @Builder
  switchPill(label: string, target: string, active: boolean) {
    Text(label)
      .fontSize(10)
      .fontFamily('HarmonyOS Sans')
      .fontColor(active ? ACCENT : SUB_COLOR)
      .padding({ left: 9, right: 9, top: 3, bottom: 3 })
      .borderRadius(10)
      .backgroundColor(active ? '#2A9B7BFF' : '#1AFFFFFF')
      .onClick(() => {
        if (!active) {
          this.sendSwitch(target);
        }
      })
  }

  modeName(): string {
    return this.mode === 'word' ? '单词库' : '知识卡';
  }

  @Builder
  rateButton(label: string, sub: string, rating: string, color: string, bg: string, heightLen: number, fontLen: number) {
    Column({ space: 1 }) {
      Text(label)
        .fontSize(fontLen)
        .fontWeight(600)
        .fontColor(color)
      if (heightLen >= 40) {
        Text(sub)
          .fontSize(9)
          .fontColor(SUB_COLOR)
      }
    }
    .layoutWeight(1)
    .height(heightLen)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(bg)
    .borderRadius(9)
    .onClick(() => {
      this.sendRate(rating);
    })
  }

  // ── 完成态（纯文案+统计；零评分=空库引导；★ 0.204.2 用户拍板三规格必须加「继续复习」按钮；
  //    noMore=y=连未来队列都空 →「全部学完」无按钮态）──
  @Builder
  doneArea() {
    Column({ space: 6 }) {
      if (this.noMore === 'y') {
        if (Number(this.hard) + Number(this.good) + Number(this.easy) > 0) {
          Text('🏅')
            .fontSize(this.dim() === 4 ? 40 : (this.dim() === 3 ? 30 : 22))
          Text('全部学完啦')
            .fontSize(this.dim() === 4 ? 16 : 13)
            .fontColor(TITLE_COLOR)
          Text('明天再来，记忆更牢固')
            .fontSize(10)
            .fontColor(SUB_COLOR)
        } else {
          Text('📚')
            .fontSize(this.dim() === 4 ? 40 : (this.dim() === 3 ? 30 : 22))
          Text('暂无复习内容')
            .fontSize(this.dim() === 4 ? 16 : 13)
            .fontColor(TITLE_COLOR)
          Text('打开应用添加单词或知识卡')
            .fontSize(10)
            .fontColor(SUB_COLOR)
        }
      } else {
        Text('🎉')
          .fontSize(this.dim() === 4 ? 40 : (this.dim() === 3 ? 30 : 22))
        Text('今日复习已完成')
          .fontSize(this.dim() === 4 ? 16 : 13)
          .fontColor(TITLE_COLOR)
        Text('明天再来，记忆更牢固')
          .fontSize(10)
          .fontColor(SUB_COLOR)
        if (this.dim() === 4 || this.dim() === 3) {
          Text(`生疏 ${this.hard} · 尚可 ${this.good} · 熟知 ${this.easy}`)
            .fontSize(11)
            .fontColor(ACCENT)
            .margin({ top: 2 })
        }
        // ★ 0.204.2：继续复习按钮（把未来排期提前背——用户拍板三规格必加）
        Text('继续复习 ›')
          .fontSize(this.dim() === 2 ? 11 : 13)
          .fontWeight(600)
          .fontColor(TITLE_COLOR)
          .padding({
            left: this.dim() === 2 ? 12 : 22,
            right: this.dim() === 2 ? 12 : 22,
            top: this.dim() === 2 ? 5 : 9,
            bottom: this.dim() === 2 ? 5 : 9
          })
          .backgroundColor('#339B7BFF')
          .borderRadius(999)
          .margin({ top: this.dim() === 2 ? 2 : 6 })
          .onClick(() => {
            this.sendContinue();
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      if (this.done === 'y') {
        this.doneArea()
      } else if (this.dim() === 2) {
        // ── 2×2 紧凑：模式标签+进度 / 标题1行 / 释义2行 / 小按钮一排 ──
        Column({ space: 5 }) {
          Row() {
            Text(this.modeName())
              .fontSize(9)
              .fontColor(ACCENT)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(6)
              .backgroundColor('#2A9B7BFF')
            Blank()
            Text(this.progress)
              .fontSize(10)
              .fontColor(SUB_COLOR)
          }
          .width('100%')

          Text(this.title)
            .fontSize(14)
            .fontWeight(600)
            .fontColor(TITLE_COLOR)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (this.definition.length > 0) {
            Text(this.definition)
              .fontSize(10)
              .fontColor(SUB_COLOR)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .lineHeight(14)
              .width('100%')
              .layoutWeight(1)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row({ space: 4 }) {
          this.rateButton('生疏', '', 'hard', HARD_COLOR, HARD_BG, 26, 10)
          this.rateButton('尚可', '', 'good', GOOD_COLOR, GOOD_BG, 26, 10)
          this.rateButton('熟知', '', 'easy', EASY_COLOR, EASY_BG, 26, 10)
        }
        .width('100%')
        .margin({ top: 5 })
      } else {
        // ── 2×4 标准 / 4×4 大卡（结构同构，字号行数分层）──
        Column({ space: 6 }) {
          Row() {
            Row({ space: 5 }) {
              this.switchPill('单词库', 'word', this.mode === 'word')
              this.switchPill('知识卡', 'knowledge', this.mode === 'knowledge')
            }
            Blank()
            Text(this.progress)
              .fontSize(11)
              .fontColor(SUB_COLOR)
          }
          .width('100%')

          if (this.dim() === 4) {
            Text(`剩 ${this.remain} 张 · 已学 ${Number(this.hard) + Number(this.good) + Number(this.easy)} 张`)
              .fontSize(10)
              .fontColor(SUB_COLOR)
              .width('100%')
          }

          Text(this.title)
            .fontSize(this.dim() === 4 ? 24 : 18)
            .fontWeight(600)
            .fontColor(TITLE_COLOR)
            .maxLines(this.dim() === 4 ? 3 : 2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (this.definition.length > 0) {
            Text(this.definition)
              .fontSize(this.dim() === 4 ? 12 : 11)
              .fontColor(SUB_COLOR)
              .maxLines(this.dim() === 4 ? 8 : 4)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .lineHeight(this.dim() === 4 ? 18 : 16)
              .width('100%')
              .layoutWeight(1)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row({ space: 6 }) {
          if (this.dim() === 4) {
            this.rateButton('生疏', '几乎想不起来', 'hard', HARD_COLOR, HARD_BG, 48, 14)
            this.rateButton('尚可', '回忆有点费劲', 'good', GOOD_COLOR, GOOD_BG, 48, 14)
            this.rateButton('熟知', '一眼就能反应', 'easy', EASY_COLOR, EASY_BG, 48, 14)
          } else {
            this.rateButton('生疏', '', 'hard', HARD_COLOR, HARD_BG, 36, 12)
            this.rateButton('尚可', '', 'good', GOOD_COLOR, GOOD_BG, 36, 12)
            this.rateButton('熟知', '', 'easy', EASY_COLOR, EASY_BG, 36, 12)
          }
        }
        .width('100%')
        .margin({ top: 6 })
      }
    }
    .width('100%')
    .height('100%')
    .padding(this.dim() === 2 ? 10 : 14)
    .backgroundColor(BG_CARD)
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }
}
