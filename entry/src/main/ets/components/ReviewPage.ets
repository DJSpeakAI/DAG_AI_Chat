// ReviewPage.ets — ★ 0.196.2 知识复习页（Anki 式单卡复习，用户定稿需求）
// ①入口：边栏「知识库」下方「知识复习」项（唯一入口）
// ②一页一卡居中展示——等待 AI 回复时专注背单词/知识卡
// ③顶部 2 标签切换：单词库 | 知识库
// ④★ 0.196.2 以天为单位（用户拍板）：当天队列=到期+新词（未来排期不掺入）；
//   「继续复习」=把明天之后的未来内容提前背；当天完成后再进直接跳完成页重新生成鼓励
// ⑤评分按钮三行全上（界面大描述回归）+ 单词卡喇叭发音（同单词库三态 svg）
// ⑥完成页：恭喜 + 总结卡（「总结正在生成」+三点动画，用户拍板改文案）+ 继续复习/完成两按钮

import { WordItem, WordBankStore } from '../common/WordModel';
import { KnowledgeCard, KnowledgeBankStore } from '../common/KnowledgeModel';
import { ChatMessage, ApiConfig, AiPreference, connectApiConfig, connectAiPreference, generateMessageId } from '../common/ChatModel';
import { buildStatEncouragePrompt } from '../common/Prompts';
import { connectWordBank } from '../utils/WordStoreUtil';
import { connectKnowledgeBank } from '../utils/KnowledgeStoreUtil';
import { MemoryItem, MemoryRating, pickReviewWords, pickReviewCards, applyRating, previewIntervalDays, formatIntervalDays } from '../utils/MemoryAlgorithm';
import { streamChat } from '../utils/ApiClient';
import { wordSpeaker, showAccentDialogs } from '../utils/WordSpeaker'; // ★ 0.196.2：单词卡喇叭发音（同单词库）
import { WaitingDots } from './ChatPage'; // ★ 0.196.2：完成页「总结正在生成」三点动画（0.190.5 组件复用）
import { PersistenceV2 } from '@kit.ArkUI';
import { WindowMode, connectWindowMode } from '../common/WindowMode'; // ★ 0.196.4：窗口宽度模式共享真相源（分屏/悬浮窗切手机布局）
import { BG_APP, BG_CANVAS, SURFACE_NODE, SURFACE_SOFT, SURFACE_HOVER, BRAND_PRIMARY, BRAND_SECONDARY, TEXT_PRIMARY, TEXT_SECONDARY, TEXT_TERTIARY, STROKE_CARD, RADIUS_CONTROL, RADIUS_NAV, FONT_SIZE_SCREEN_TITLE } from '../common/DesignTokens';

// ★ 0.196.2：每日复习完成状态（以天为单位——用户拍板：今天的内容今天复习，明天内容明天复习；
// 当天完成后再进复习页直接跳完成页重新生成鼓励。同日多次完成（继续复习）累计入当日总量）
@ObservedV2
export class ReviewDailyState {
  @Trace wordDate: string = ''; // 单词模式最近完成日（YYYY-MM-DD；非今天=今天未完成）
  @Trace wordTotal: number = 0;
  @Trace wordHard: number = 0;
  @Trace wordGood: number = 0;
  @Trace wordEasy: number = 0;
  @Trace knowledgeDate: string = '';
  @Trace knowledgeTotal: number = 0;
  @Trace knowledgeHard: number = 0;
  @Trace knowledgeGood: number = 0;
  @Trace knowledgeEasy: number = 0;
}

export function connectReviewDailyState(): ReviewDailyState {
  return PersistenceV2.connect(ReviewDailyState, 'review-daily-v1', () => new ReviewDailyState()) as ReviewDailyState;
}

function todayKey(): string {
  const d = new Date();
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}

@ComponentV2
export struct ReviewPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  wordBank: WordBankStore = connectWordBank();
  knowledgeBank: KnowledgeBankStore = connectKnowledgeBank();
  apiConfig: ApiConfig = connectApiConfig();
  aiPreference: AiPreference = connectAiPreference();
  dailyState: ReviewDailyState = connectReviewDailyState();

  // ★ 0.195.0：大屏断点（顶栏左间距对齐气泡树信息条 28/14 双分支；评分按钮宽 130/104）
  // ★ 0.196.4：改读窗口宽度共享真相源（WindowMode）——分屏/悬浮窗实时切手机布局
  windowMode: WindowMode = connectWindowMode();
  @Computed get isTablet(): boolean {
    return this.windowMode.isTablet;
  }

  @Local mode: string = 'word'; // 'word' | 'knowledge' — 顶部 2 标签
  @Local queue: MemoryItem[] = []; // 会话队列（当天=到期+新词；继续复习=未来内容）
  @Local idx: number = 0; // 当前卡下标
  @Local ratedHard: number = 0;
  @Local ratedGood: number = 0;
  @Local ratedEasy: number = 0;
  @Local finished: boolean = false;
  @Local aiText: string = '';
  @Local aiLoading: boolean = false;

  aboutToAppear(): void {
    // ★ 0.196.4：isTablet 屏宽检测删除——改读 WindowMode 共享真相源（Index 根 onAreaChange 写入）
    this.buildQueue();
  }

  isDoneToday(): boolean {
    return this.mode === 'word' ? this.dailyState.wordDate === todayKey() : this.dailyState.knowledgeDate === todayKey();
  }

  // ★ 0.196.2 用户拍板（以天为单位）：当天队列=到期（nextReviewAt≤now）+ 新词（reviewCount=0），
  // 未来排期不掺入——「继续复习」才把未来的提前背；当天已完成 → 直接完成页重新生成鼓励
  buildQueue(): void {
    const now = Date.now();
    if (this.mode === 'word') {
      const all = pickReviewWords(this.wordBank, this.wordBank.words.length, now);
      this.queue = all.filter((w: MemoryItem): boolean => w.reviewCount === 0 || w.nextReviewAt <= now);
    } else {
      const all = pickReviewCards(this.knowledgeBank, this.knowledgeBank.cards.length, now);
      this.queue = all.filter((c: MemoryItem): boolean => c.reviewCount === 0 || c.nextReviewAt <= now);
    }
    this.idx = 0;
    this.ratedHard = 0;
    this.ratedGood = 0;
    this.ratedEasy = 0;
    this.aiText = '';
    this.aiLoading = false;
    if (this.isDoneToday()) {
      this.finished = true;
      this.requestEncourage(); // 用户拍板：再进直接跳完成页 + 重新生成一次鼓励
    } else {
      this.finished = false;
    }
  }

  // ★ 0.196.2：继续复习——把明天之后的未来内容提前背（pickReview* 的 future 段按 nextReviewAt 升序=最近的先）
  continueReview(): void {
    const now = Date.now();
    if (this.mode === 'word') {
      const all = pickReviewWords(this.wordBank, this.wordBank.words.length, now);
      this.queue = all.filter((w: MemoryItem): boolean => w.reviewCount > 0 && w.nextReviewAt > now);
    } else {
      const all = pickReviewCards(this.knowledgeBank, this.knowledgeBank.cards.length, now);
      this.queue = all.filter((c: MemoryItem): boolean => c.reviewCount > 0 && c.nextReviewAt > now);
    }
    if (this.queue.length === 0) {
      return;
    }
    this.idx = 0;
    this.ratedHard = 0;
    this.ratedGood = 0;
    this.ratedEasy = 0;
    this.finished = false;
    this.aiText = '';
    this.aiLoading = false;
  }

  // 完成页「继续复习」按钮显隐：有未来排期内容才显示
  hasFutureContent(): boolean {
    const now = Date.now();
    if (this.mode === 'word') {
      for (let i = 0; i < this.wordBank.words.length; i++) {
        const w = this.wordBank.words[i];
        if (w.reviewCount > 0 && w.nextReviewAt > now) {
          return true;
        }
      }
      return false;
    }
    for (let i = 0; i < this.knowledgeBank.cards.length; i++) {
      const c = this.knowledgeBank.cards[i];
      if (c.reviewCount > 0 && c.nextReviewAt > now) {
        return true;
      }
    }
    return false;
  }

  switchMode(m: string): void {
    if (this.mode === m) {
      return;
    }
    this.mode = m;
    this.buildQueue();
  }

  currentItem(): MemoryItem | undefined {
    if (this.idx < this.queue.length) {
      return this.queue[this.idx];
    }
    return undefined;
  }

  totalCount(): number {
    return this.ratedHard + this.ratedGood + this.ratedEasy;
  }

  onRate(rating: MemoryRating): void {
    const item = this.currentItem();
    if (item === undefined) {
      return;
    }
    applyRating(item, rating, Date.now());
    if (rating === 'hard') {
      this.ratedHard += 1;
    } else if (rating === 'good') {
      this.ratedGood += 1;
    } else {
      this.ratedEasy += 1;
    }
    this.idx += 1;
    if (this.idx >= this.queue.length) {
      this.finished = true;
      this.saveTodayDone();
      this.requestEncourage();
    }
  }

  // 当日完成状态落盘（同日多次完成累计——继续复习的量也计入当日总量）
  saveTodayDone(): void {
    const key = todayKey();
    if (this.mode === 'word') {
      if (this.dailyState.wordDate === key) {
        this.dailyState.wordTotal += this.totalCount();
        this.dailyState.wordHard += this.ratedHard;
        this.dailyState.wordGood += this.ratedGood;
        this.dailyState.wordEasy += this.ratedEasy;
      } else {
        this.dailyState.wordDate = key;
        this.dailyState.wordTotal = this.totalCount();
        this.dailyState.wordHard = this.ratedHard;
        this.dailyState.wordGood = this.ratedGood;
        this.dailyState.wordEasy = this.ratedEasy;
      }
    } else {
      if (this.dailyState.knowledgeDate === key) {
        this.dailyState.knowledgeTotal += this.totalCount();
        this.dailyState.knowledgeHard += this.ratedHard;
        this.dailyState.knowledgeGood += this.ratedGood;
        this.dailyState.knowledgeEasy += this.ratedEasy;
      } else {
        this.dailyState.knowledgeDate = key;
        this.dailyState.knowledgeTotal = this.totalCount();
        this.dailyState.knowledgeHard = this.ratedHard;
        this.dailyState.knowledgeGood = this.ratedGood;
        this.dailyState.knowledgeEasy = this.ratedEasy;
      }
    }
  }

  // 完成鼓励：档位 off → 默认一句话；否则 AI 生成（数据=当日累计——用户拍板「今天你又背了几个」）
  requestEncourage(): void {
    const unit = this.mode === 'word' ? '单词' : '知识卡';
    const total = this.mode === 'word' ? this.dailyState.wordTotal : this.dailyState.knowledgeTotal;
    const hard = this.mode === 'word' ? this.dailyState.wordHard : this.dailyState.knowledgeHard;
    const good = this.mode === 'word' ? this.dailyState.wordGood : this.dailyState.knowledgeGood;
    const easy = this.mode === 'word' ? this.dailyState.wordEasy : this.dailyState.knowledgeEasy;
    const fallback = `今天你又复习了 ${total} 个${unit}，继续保持！`;
    if (this.aiPreference.encourageMode === 'off') {
      this.aiText = fallback;
      return;
    }
    const dataText = `今天完成了一轮知识复习：共复习 ${total} 个${unit}（生疏 ${hard}、尚可 ${good}、熟知 ${easy}）`;
    const sys = buildStatEncouragePrompt(this.aiPreference.encourageMode, this.aiPreference.aiNickname.trim(), dataText);
    this.aiLoading = true;
    this.aiText = '';
    const messages: ChatMessage[] = [
      new ChatMessage(generateMessageId(), 'system', sys),
      new ChatMessage(generateMessageId(), 'user', '请根据我今天的复习表现给我一句鼓励。')
    ];
    streamChat(
      messages,
      this.apiConfig,
      (chunk: string) => {
        this.aiText += chunk;
      },
      () => {
        this.aiLoading = false;
      },
      (errMsg: string) => {
        this.aiLoading = false;
        this.aiText = fallback; // AI 失败降级默认鼓励（用户拍板：鼓励永远要有）
      },
      (reasoning: string) => {
        // 复习鼓励无需思考流展示，空回调占位（同统计页）
      }
    );
  }

  // ── 顶栏：标题 + 2 标签切换 + 进度（0.195.0 统一规格：left 28/14 + top 8 + right 14）──
  @Builder
  topBar() {
    Row() {
      Text('知识复习')
        .fontSize(FONT_SIZE_SCREEN_TITLE)
        .fontWeight(600)
        .fontColor(TEXT_PRIMARY)
      // ★ 0.196.1：2 标签切换（单词库|知识库）——分段控件样式同画布（track 3 + 选中主紫）
      Row({ space: 0 }) {
        Text('单词库')
          .fontSize(12)
          .fontWeight(this.mode === 'word' ? 600 : 400)
          .fontColor(this.mode === 'word' ? Color.White : TEXT_SECONDARY)
          .height(30)
          .padding({ left: 16, right: 16 })
          .borderRadius(8)
          .backgroundColor(this.mode === 'word' ? BRAND_PRIMARY : Color.Transparent)
          .onClick(() => {
            this.switchMode('word');
          })
        Text('知识库')
          .fontSize(12)
          .fontWeight(this.mode === 'knowledge' ? 600 : 400)
          .fontColor(this.mode === 'knowledge' ? Color.White : TEXT_SECONDARY)
          .height(30)
          .padding({ left: 16, right: 16 })
          .borderRadius(8)
          .backgroundColor(this.mode === 'knowledge' ? BRAND_PRIMARY : Color.Transparent)
          .onClick(() => {
            this.switchMode('knowledge');
          })
      }
      .padding(3)
      .borderRadius(RADIUS_CONTROL)
      .backgroundColor(SURFACE_SOFT)
      .margin({ left: 16 })
      Blank()
        .layoutWeight(1)
      if (!this.finished && this.queue.length > 0) {
        Text(`${this.idx + 1} / ${this.queue.length}`) // ★ 0.196.2：1 基进度（第几张/共几张）
          .fontSize(12)
          .fontColor(TEXT_TERTIARY)
      }
    }
    .width('100%')
    .padding({ left: this.isTablet ? 28 : 14, right: 14, top: 8, bottom: 8 })
  }

  // ── 复习卡（居中单卡——用户拍板「一页只展示一个卡片，居中展示」）──
  @Builder
  cardArea() {
    Column({ space: 10 }) {
      if (this.mode === 'word') {
        // ★ 0.196.3 用户拍板：单词独占一行居中（原单词+喇叭同行=单词被挤偏不在正中）；
        //   喇叭移到音标旁（同单词库版式；缩写词读全称逻辑不变 textFor(word, fullName)）
        Text((this.currentItem() as WordItem).word)
          .fontSize(30)
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if ((this.currentItem() as WordItem).usPhonetic !== '') {
          Row({ space: 6 }) {
            Text((this.currentItem() as WordItem).usPhonetic)
              .fontSize(14)
              .fontColor(TEXT_TERTIARY)
            Image(wordSpeaker.loadingWord === wordSpeaker.textFor((this.currentItem() as WordItem).word, (this.currentItem() as WordItem).fullName) ? $r('app.media.speaker_loading') : (wordSpeaker.speakingWord === wordSpeaker.textFor((this.currentItem() as WordItem).word, (this.currentItem() as WordItem).fullName) ? $r('app.media.speaker_playing') : $r('app.media.speaker')))
              .width(14)
              .height(14)
              .objectFit(ImageFit.Contain)
              .onClick(() => {
                const w = this.currentItem() as WordItem;
                wordSpeaker.speak(wordSpeaker.textFor(w.word, w.fullName), showAccentDialogs(this.getUIContext()));
              })
          }
        } else {
          // 无音标：喇叭独立一行（发音永远可用）
          Image(wordSpeaker.loadingWord === wordSpeaker.textFor((this.currentItem() as WordItem).word, (this.currentItem() as WordItem).fullName) ? $r('app.media.speaker_loading') : (wordSpeaker.speakingWord === wordSpeaker.textFor((this.currentItem() as WordItem).word, (this.currentItem() as WordItem).fullName) ? $r('app.media.speaker_playing') : $r('app.media.speaker')))
            .width(16)
            .height(16)
            .objectFit(ImageFit.Contain)
            .onClick(() => {
              const w = this.currentItem() as WordItem;
              wordSpeaker.speak(wordSpeaker.textFor(w.word, w.fullName), showAccentDialogs(this.getUIContext()));
            })
        }
        Text((this.currentItem() as WordItem).explain)
          .fontSize(15)
          .fontColor(TEXT_SECONDARY)
          .textAlign(TextAlign.Center)
          .lineHeight(22)
          .maxLines(5)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      } else {
        // ★ 0.196.3 用户反馈：知识卡有图要显示图（原只有标题+定义——知识库里带图的卡复习时图丢了）
        if ((this.currentItem() as KnowledgeCard).imageUri !== '') {
          Image((this.currentItem() as KnowledgeCard).imageUri)
            .width('100%')
            .constraintSize({ maxHeight: 220 })
            .borderRadius(RADIUS_CONTROL)
            .objectFit(ImageFit.Contain)
            .margin({ bottom: 4 })
        }
        Text((this.currentItem() as KnowledgeCard).title)
          .fontSize(24)
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
        Text((this.currentItem() as KnowledgeCard).definition)
          .fontSize(15)
          .fontColor(TEXT_SECONDARY)
          .textAlign(TextAlign.Center)
          .lineHeight(22)
          .maxLines(8)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('76%')
    .constraintSize({ maxWidth: 520 })
    .padding(32)
    .borderRadius(RADIUS_NAV)
    .backgroundColor(SURFACE_NODE)
    .border({ width: 1, color: STROKE_CARD })
    .alignItems(HorizontalAlign.Center)
  }

  // ── 评分区：3 档按钮三行全上（界面大，描述回归——用户拍板「加了很漂亮」）──
  // ★ 0.196.2：宽度自适应 130/104——手机上 3×130+20 溢出屏幕（用户实测右边按钮超框）
  @Builder
  ratingArea() {
    Row({ space: 10 }) {
      Button() {
        Column({ space: 2 }) {
          Text('生疏').fontSize(14).fontWeight(600).fontColor('#E5484D')
          Text('几乎想不起来').fontSize(10).fontColor(TEXT_TERTIARY)
          Text(`${formatIntervalDays(previewIntervalDays(this.currentItem()!, 'hard'))}后`).fontSize(11).fontColor('#E5484D')
        }
      }
      .width(this.isTablet ? 130 : 104)
      .backgroundColor('#26E5484D')
      .borderRadius(RADIUS_CONTROL)
      .onClick(() => {
        this.onRate('hard');
      })
      Button() {
        Column({ space: 2 }) {
          Text('尚可').fontSize(14).fontWeight(600).fontColor('#F5A623')
          Text('回忆有点费劲').fontSize(10).fontColor(TEXT_TERTIARY)
          Text(`${formatIntervalDays(previewIntervalDays(this.currentItem()!, 'good'))}后`).fontSize(11).fontColor('#F5A623')
        }
      }
      .width(this.isTablet ? 130 : 104)
      .backgroundColor('#26F5A623')
      .borderRadius(RADIUS_CONTROL)
      .onClick(() => {
        this.onRate('good');
      })
      Button() {
        Column({ space: 2 }) {
          Text('熟知').fontSize(14).fontWeight(600).fontColor('#3BB273')
          Text('一眼就能反应').fontSize(10).fontColor(TEXT_TERTIARY)
          Text(`${formatIntervalDays(previewIntervalDays(this.currentItem()!, 'easy'))}后`).fontSize(11).fontColor('#3BB273')
        }
      }
      .width(this.isTablet ? 130 : 104)
      .backgroundColor('#263BB273')
      .borderRadius(RADIUS_CONTROL)
      .onClick(() => {
        this.onRate('easy');
      })
    }
    .justifyContent(FlexAlign.Center)
    .margin({ top: 32 })
  }

  // ── 完成页（背完不循环——用户拍板）：恭喜 + 总结卡 + 继续复习/完成 ──
  @Builder
  doneArea() {
    Column({ space: 0 }) {
      // ★ 0.196.3 用户拍板（标点悬挂）：「恭喜你」3 字与下方副标题居中对齐，「！」往后悬挂——
      //   整串居中时恭喜你中心偏左 ！/2，margin-left=！全角宽(1em=26px) 使文本右移 ！/2 恰好归正
      Text('恭喜你！')
        .fontSize(26)
        .fontWeight(600)
        .fontColor(TEXT_PRIMARY)
        .margin({ left: 26 })
      Text('今天的复习任务已经完成')
        .fontSize(15)
        .fontColor(TEXT_SECONDARY)
        .margin({ top: 6 })
      // ★ 0.196.2 排版优化（用户实测反馈）：总结独立成卡（SURFACE_SOFT 底）视觉分层；
      //   加载态文案用户拍板改「总结正在生成」+ 三点跳动动画（WaitingDots 复用）
      Column() {
        if (this.aiLoading) {
          Row({ space: 8 }) {
            Text('总结正在生成')
              .fontSize(13)
              .fontColor(TEXT_SECONDARY)
            WaitingDots()
          }
        } else {
          Text(this.aiText)
            .fontSize(14)
            .fontColor(BRAND_SECONDARY)
            .textAlign(TextAlign.Center)
            .lineHeight(21)
        }
      }
      .width('86%')
      .constraintSize({ maxWidth: 460, minHeight: 64 })
      .padding(16)
      .borderRadius(RADIUS_CONTROL)
      .backgroundColor(SURFACE_SOFT)
      .margin({ top: 20 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      // ★ 0.196.2 用户拍板：两选项——继续复习（把明天之后的内容提前背）/ 完成（返回）
      Row({ space: 12 }) {
        if (this.hasFutureContent()) {
          Button('继续复习')
            .fontSize(15)
            .fontWeight(600)
            .fontColor(TEXT_PRIMARY)
            .height(44)
            .padding({ left: 24, right: 24 })
            .backgroundColor(SURFACE_HOVER)
            .borderRadius(RADIUS_CONTROL)
            .onClick(() => {
              this.continueReview();
            })
        }
        Button('完成')
          .fontSize(15)
          .fontWeight(600)
          .fontColor(Color.White)
          .height(44)
          .padding({ left: 24, right: 24 })
          .backgroundColor(BRAND_PRIMARY)
          .borderRadius(RADIUS_CONTROL)
          .onClick(() => {
            this.pathStack.pop();
          })
      }
      .margin({ top: 28 })
    }
    .alignItems(HorizontalAlign.Center)
  }

  // ── 空态（当天无到期内容且无新词）──
  @Builder
  emptyArea() {
    Column({ space: 0 }) {
      Text('今天没有到期的复习内容')
        .fontSize(16)
        .fontColor(TEXT_SECONDARY)
      Text('新词加入后会自动进入当天的复习队列')
        .fontSize(13)
        .fontColor(TEXT_TERTIARY)
        .margin({ top: 8 })
    }
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    // ★ 0.159 模式：NavDestination + hideTitleBar(true)（自绘顶栏）——直接 Column 作根 = 全黑屏
    NavDestination() {
      Column() {
        this.topBar()
        if (this.finished) {
          Column() {
            Blank().layoutWeight(1)
            this.doneArea()
            Blank().layoutWeight(1)
          }
          .width('100%')
          .layoutWeight(1)
        } else if (this.queue.length === 0) {
          Column() {
            Blank().layoutWeight(1)
            this.emptyArea()
            Blank().layoutWeight(1)
          }
          .width('100%')
          .layoutWeight(1)
        } else {
          Column() {
            Blank().layoutWeight(1)
            this.cardArea()
            this.ratingArea()
            Blank().layoutWeight(1)
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG_CANVAS)
    }
    .hideTitleBar(true)
  }
}
