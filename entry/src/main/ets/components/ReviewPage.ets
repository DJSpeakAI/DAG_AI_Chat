// ReviewPage.ets — ★ 0.196.2 知识复习页（Anki 式单卡复习，用户定稿需求）
// ①入口：边栏「知识库」下方「知识复习」项（唯一入口）
// ②一页一卡居中展示——等待 AI 回复时专注背单词/知识卡
// ③顶部 2 标签切换：单词库 | 知识库
// ④★ 0.196.2 以天为单位（用户拍板）：当天队列=到期+新词（未来排期不掺入）；
//   「继续复习」=把明天之后的未来内容提前背；当天完成后再进直接跳完成页重新生成鼓励
// ⑤评分按钮三行全上（界面大描述回归）+ 单词卡喇叭发音（同单词库三态 svg）
// ⑥完成页：恭喜 + 总结卡（「总结正在生成」+三点动画，用户拍板改文案）+ 继续复习/完成两按钮

import { WordItem, WordBankStore } from '../common/WordModel';
import { KnowledgeCard, KnowledgeBankStore, CardImportStore, connectCardImport, navBackToCanvas, getCardImages, getTitleImages } from '../common/KnowledgeModel'; // ★ 0.200.0：卡片导入气泡（复习即问场景）
import { ChatMessage, ApiConfig, AiPreference, connectApiConfig, connectAiPreference, generateMessageId, StatisticsStore, connectStatistics, recordStat } from '../common/ChatModel';
import { buildStatEncouragePrompt } from '../common/Prompts';
import { connectWordBank } from '../utils/WordStoreUtil';
import { connectKnowledgeBank } from '../utils/KnowledgeStoreUtil';
import { MemoryItem, MemoryRating, pickReviewWords, pickReviewCards, applyRating, previewIntervalDays, formatIntervalDays } from '../utils/MemoryAlgorithm';
import { streamChat } from '../utils/ApiClient';
import { wordSpeaker, showAccentDialogs } from '../utils/WordSpeaker'; // ★ 0.196.2：单词卡喇叭发音（同单词库）
import { WaitingDots } from './ChatPage'; // ★ 0.196.2：完成页「总结正在生成」三点动画（0.190.5 组件复用）
import { buildWidgetState, mergeWidgetPending } from '../utils/WidgetHostBridge'; // ★ 0.204.0：桌面卡片双队列快照（构建+pending 回放）
import { track } from '../utils/TrackUtil'; // 0.206.0 埋点
import { common } from '@kit.AbilityKit'; // ★ 0.203.0：getHostContext 取 context 写卡片快照
import { PersistenceV2 } from '@kit.ArkUI';
import { WindowMode, connectWindowMode } from '../common/WindowMode'; // ★ 0.196.4：窗口宽度模式共享真相源（分屏/悬浮窗切手机布局）
import { BG_APP, BG_CANVAS, SURFACE_NODE, SURFACE_SOFT, SURFACE_HOVER, BRAND_PRIMARY, BRAND_SECONDARY, TEXT_PRIMARY, TEXT_SECONDARY, TEXT_TERTIARY, STROKE_CARD, RADIUS_CONTROL, RADIUS_NAV, FONT_SIZE_SCREEN_TITLE, OVERLAY } from '../common/DesignTokens';

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

// ★ 0.202.0：每日复习条目数（复习页右上角 ⚙ 设置；10 默认 / 20 / 自定义 1~500）
@ObservedV2
export class DailyReviewCountStore {
  @Trace wordCount: number = 10;      // 单词库每日复习条目
  @Trace knowledgeCount: number = 10; // 知识库每日复习条目
}

export function connectDailyReviewCount(): DailyReviewCountStore {
  return PersistenceV2.connect(DailyReviewCountStore, 'daily-review-count-v1', () => new DailyReviewCountStore()) as DailyReviewCountStore;
}

// ★ 0.209.0：卡面模式（用户需求：复习卡支持「正反两面」——先看题面，点击翻面后再评分）
// 'single'=单面（现状：题面+内容全显，评分按钮直接可按）；'double'=正反两面
@ObservedV2
export class FaceModeStore {
  @Trace wordFace: string = 'single';      // 单词库：正面=单词+音标，反面=释义
  @Trace knowledgeFace: string = 'single'; // 知识库：正面=标题，反面=图片+定义
}

export function connectFaceMode(): FaceModeStore {
  return PersistenceV2.connect(FaceModeStore, 'review-face-mode-v1', () => new FaceModeStore()) as FaceModeStore;
}

function todayKey(): string {
  const d = new Date();
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}

@ComponentV2
export struct ReviewPage {
  @Param pathStack: NavPathStack = new NavPathStack();

  // ── ★ 0.200.0 入口 C：复习页「问 AI」（复习遇到不懂的概念立刻问——100% 场景）──
  cardImport: CardImportStore = connectCardImport();
  @Local askSheetVisible: boolean = false;
  // ── ★ 0.202.0：每日复习量（右上角 ⚙）──
  // ★ 0.209.1 修复：普通成员→@Local（@ObservedV2 实例必须挂组件状态，@Computed 依赖才在真机上可靠响应）
  @Local dailyCount: DailyReviewCountStore = connectDailyReviewCount();
  @Local countSettingsVisible: boolean = false; // ⚙ 弹窗开关
  statStore: StatisticsStore = connectStatistics(); // ★ 0.202.3：司忆量埋点
  // ── ★ 0.209.0：卡面模式 + 翻面状态 ──
  @Local faceMode: FaceModeStore = connectFaceMode();
  @Local cardFlipped: boolean = false; // 当前卡是否已翻到反面（每换一张卡重置为 false）

  @Computed get isDoubleFace(): boolean {
    return this.mode === 'word' ? this.faceMode.wordFace === 'double' : this.faceMode.knowledgeFace === 'double';
  }

  // ★ 0.209.0：评分区可见条件——单面模式恒显（现状不变）；双面模式须翻面后才显示（评分逻辑本身完全不动）
  @Computed get faceReady(): boolean {
    return !this.isDoubleFace || this.cardFlipped;
  }

  /** ★ 0.200.0：写入导入 store + 回画布进入选择模式（取当前复习中的知识卡） */
  startCardImport(action: string): void {
    const card = this.currentItem() as KnowledgeCard;
    this.cardImport.action = action;
    this.cardImport.title = card.title;
    this.cardImport.definition = card.definition;
    this.cardImport.imageUrisJson = JSON.stringify([...getTitleImages(card), ...getCardImages(card)]); // ★ 0.210.0：标题图在前+内容图合并导入气泡
    this.askSheetVisible = false;
    navBackToCanvas(this.pathStack);
  }
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
    // ★ 0.204.0：先回放桌面卡片上产生的评分到真数据（合并后 buildQueue 的队列才是正确的）
    const ctx = this.getUIContext().getHostContext() as common.Context;
    mergeWidgetPending(ctx, this.wordBank, this.knowledgeBank);
    this.buildQueue();
  }

  isDoneToday(): boolean {
    return this.mode === 'word' ? this.dailyState.wordDate === todayKey() : this.dailyState.knowledgeDate === todayKey();
  }

  // ★ 0.196.2 用户拍板（以天为单位）：当天队列=到期（nextReviewAt≤now）+ 新词（reviewCount=0），
  // 未来排期不掺入——「继续复习」才把未来的提前背；当天已完成 → 直接完成页重新生成鼓励
  buildQueue(): void {
    const now = Date.now();
    const dailyN = this.mode === 'word' ? this.dailyCount.wordCount : this.dailyCount.knowledgeCount; // ★ 0.202.0：每日量（⚙ 设置默认 10）
    if (this.mode === 'word') {
      const all = pickReviewWords(this.wordBank, this.wordBank.words.length, now);
      this.queue = all.filter((w: MemoryItem): boolean => w.reviewCount === 0 || w.nextReviewAt <= now).slice(0, dailyN);
    } else {
      const all = pickReviewCards(this.knowledgeBank, this.knowledgeBank.cards.length, now);
      this.queue = all.filter((c: MemoryItem): boolean => c.reviewCount === 0 || c.nextReviewAt <= now).slice(0, dailyN);
    }
    this.idx = 0;
    this.ratedHard = 0;
    this.ratedGood = 0;
    this.ratedEasy = 0;
    this.cardFlipped = false; // ★ 0.209.0：新队列从正面开始
    this.aiText = '';
    this.aiLoading = false;
    if (this.queue.length === 0) {
      this.finished = true;
      this.requestEncourage(); // ★ 0.202.0 铁律修复：队列空才完成页（isDoneToday 一刀切已删——新卡必须当日学）
    } else {
      this.finished = false;
      recordStat(this.statStore, 'siyi', this.queue.length, 0); // ★ 0.202.3：司忆量埋点（本队展示张数）
    }
    this.rebuildWidgetState(); // 0.204.0 队列重建后刷新桌面卡片
  }

  // ★ 0.196.2：继续复习——把明天之后的未来内容提前背（pickReview* 的 future 段按 nextReviewAt 升序=最近的先）
  continueReview(): void {
    track(this.getUIContext().getHostContext() as common.Context, 'review_continue'); // 0.206.0 埋点：继续复习按钮
    const now = Date.now();
    if (this.mode === 'word') {
      const all = pickReviewWords(this.wordBank, this.wordBank.words.length, now);
      this.queue = all.filter((w: MemoryItem): boolean => w.reviewCount > 0 && w.nextReviewAt > now);
    } else {
      const all = pickReviewCards(this.knowledgeBank, this.knowledgeBank.cards.length, now);
      this.queue = all.filter((c: MemoryItem): boolean => c.reviewCount > 0 && c.nextReviewAt > now);
    }
    if (this.queue.length === 0) {
      // ★ 0.202.0：future 空 → 兜底重拉当日队列（每日量外的剩余到期/新卡）→ 仍空 → 轻提示（永不空转）
      this.buildQueue();
      if (this.queue.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '今日内容已全部学完，明天再来吧', duration: 2000 });
      }
      return;
    }
    this.idx = 0;
    this.ratedHard = 0;
    this.ratedGood = 0;
    this.ratedEasy = 0;
    this.cardFlipped = false; // ★ 0.209.0：继续复习新队列从正面开始
    this.finished = false;
    recordStat(this.statStore, 'siyi', this.queue.length, 0); // 0.202.3 司忆量埋点（继续复习队列）
    this.aiText = '';
    this.aiLoading = false;
    this.rebuildWidgetState(); // 0.204.0 继续复习新队列也推桌面卡片
  }

  // 完成页「继续复习」按钮显隐：有未来排期内容才显示
  // ★ 0.202.0 铁律 2：库非空「继续复习」按钮常驻（"没有卡可学"在系统里不允许存在——
  //   原判定只认已评分未来卡，全新卡时按钮消失=用户实测 bug）
  hasFutureContent(): boolean {
    return this.mode === 'word' ? this.wordBank.words.length > 0 : this.knowledgeBank.cards.length > 0;
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

  // ★ 0.204.0：重建桌面卡片双队列快照（页面队列变化后调用；与 buildQueue 同算法独立构建，未添加卡片时静默）
  rebuildWidgetState(): void {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    buildWidgetState(ctx, this.mode, this.wordBank, this.knowledgeBank,
      this.dailyCount.wordCount, this.dailyCount.knowledgeCount);
  }

  onRate(rating: MemoryRating): void {
    const item = this.currentItem();
    if (item === undefined) {
      return;
    }
 const _tp1: Record<string, string> = {}; _tp1['rating'] = rating;
    track(this.getUIContext().getHostContext() as common.Context, 'review_rate', _tp1); // 0.206.0 埋点：复习页评分
    applyRating(item, rating, Date.now());
    if (rating === 'hard') {
      this.ratedHard += 1;
    } else if (rating === 'good') {
      this.ratedGood += 1;
    } else {
      this.ratedEasy += 1;
    }
    this.idx += 1;
    this.cardFlipped = false; // ★ 0.209.0：下一张卡从正面开始
    this.rebuildWidgetState(); // 0.204.0 翻卡后刷新桌面卡片（完成态自动切换）
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
    const dataText = `今天完成了一轮卡片复习：共复习 ${total} 个${unit}（生疏 ${hard}、尚可 ${good}、熟知 ${easy}）`;
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
      Text('卡片复习')
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
      // ★ 0.202.0：右上角 ⚙ 每日复习量设置（与全局设置「复习区」语义分开——此处管每日队列条目数）
      Image($r('app.media.settings'))
        .width(18)
        .height(18)
        .objectFit(ImageFit.Contain)
        .margin({ left: 12 })
        .onClick(() => {
          this.openCountSettings();
        })
    }
    .width('100%')
    .height(56) // ★ 0.196.7：顶栏 Row 40→56——height 含 padding，原 40+padding8/8 把内容区压到 24vp（顶栏比树页高 8vp，Pad 实测）；56=8padding+40内容+8padding 与树页外层 Column frame 等效，与 ChatPage 同步
    .padding({ left: this.isTablet ? 28 : 14, right: 14, top: 8, bottom: 8 })
  }

  // ── 复习卡（居中单卡——用户拍板「一页只展示一个卡片，居中展示」）──
  @Builder
  cardArea() {
    // ★ 0.200.0：外层 Stack（TopEnd）——承载右上角「问 AI」icon（绝对定位不占卡片版面，保住一页一卡居中美学）
    Stack({ alignContent: Alignment.TopEnd }) {
    Column({ space: 10 }) {
      if (this.mode === 'word') {
        // ★ 0.196.3 用户拍板：单词独占一行居中（原单词+喇叭同行=单词被挤偏不在正中）；
        //   喇叭移到音标旁（同单词库版式；缩写词读全称逻辑不变 textFor(word, fullName)）
        Text((this.currentItem() as WordItem).word)
          .fontSize(30)
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
          // ★ 0.197.0 用户拍板：英文展示词截断绝对不允许——maxLines+minFontSize/maxFontSize
          //   触发自适应缩字号（放不下自动缩字体而非省略号；3 行 × 16px 下限，长英文短语必 100% 完整展示）
          .maxLines(3)
          .minFontSize(16)
          .maxFontSize(30)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center) // 换行后各行居中（原单行靠 alignItems 居中，折行后左歪）
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
        // ★ 0.209.0：双面模式下释义=反面内容（翻面后才显示；单面恒显=现状不变）
        if (!this.isDoubleFace || this.cardFlipped) {
          Text((this.currentItem() as WordItem).explain)
            .fontSize(15)
            .fontColor(TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
            .lineHeight(22)
            .maxLines(5)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      } else {
        // ★ 0.210.0：标题图（Anki 图对图——题面插图；恒显=正面内容，双面模式随正面出题）
        if (getTitleImages(this.currentItem() as KnowledgeCard).length > 0) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(getTitleImages(this.currentItem() as KnowledgeCard), (img: string) => {
                Image(img)
                  .width('86%')
                  .constraintSize({ maxHeight: 220 })
                  .borderRadius(RADIUS_CONTROL)
                  .objectFit(ImageFit.Contain)
              }, (img: string) => img)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .margin({ bottom: 4 })
        }
        // ★ 0.196.3 用户反馈：知识卡有图要显示图（原只有标题+定义——知识库里带图的卡复习时图丢了）
        // ★ 0.202.1：多图横滑（单图无滑感）；图片兼容读取 getCardImages
        // ★ 0.209.0：双面模式下图片+定义=反面内容（翻面后才显示；正面只有标题）
        if ((!this.isDoubleFace || this.cardFlipped) && getCardImages(this.currentItem() as KnowledgeCard).length > 0) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(getCardImages(this.currentItem() as KnowledgeCard), (img: string) => {
                Image(img)
                  .width('86%')
                  .constraintSize({ maxHeight: 220 })
                  .borderRadius(RADIUS_CONTROL)
                  .objectFit(ImageFit.Contain)
              }, (img: string) => img)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .margin({ bottom: 4 })
        }
        Text((this.currentItem() as KnowledgeCard).title)
          .fontSize(24)
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
          // ★ 0.197.0：同单词卡——自适应缩字号防截断（用户拍板：展示词必须 100% 完整展示）
          .maxLines(3)
          .minFontSize(14)
          .maxFontSize(24)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
        // ★ 0.209.0：双面模式下定义=反面内容（翻面后才显示；单面恒显=现状不变）
        if (!this.isDoubleFace || this.cardFlipped) {
          Text((this.currentItem() as KnowledgeCard).definition)
            .fontSize(15)
            .fontColor(TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
            .lineHeight(22)
            .maxLines(8)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      // ★ 0.209.0：双面模式未翻面时的操作提示（用户首次见双面卡即懂点击翻面）
      if (this.isDoubleFace && !this.cardFlipped) {
        Text('点击卡片查看答案')
          .fontSize(11)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      }
      .width('100%')
      .padding(32)
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
      .border({ width: 1, color: STROKE_CARD })
      .alignItems(HorizontalAlign.Center)
      // ★ 0.209.0：双面模式点击卡片翻面；★ 0.209.3 用户拍板：翻面后点反面无动作（反面=终态，
      // 「标题+内容组合」已完整展示，没有任何理由翻回——评分三按钮是唯一跳卡出口）
      // 喇叭/问AI 等子组件点击不冒泡（0.200.0 教训）互不干扰
      .onClick(() => {
        if (this.isDoubleFace && !this.cardFlipped) {
          this.cardFlipped = true;
        }
      })
      // ★ 0.200.0 入口 C：右上角「问 AI」——仅知识卡显示（单词走遗忘曲线无导入需求）；
      //   Stack TopEnd 绝对定位不占版面空间（保住一页一卡居中美学）；icon 规格同知识库列表入口
      if (this.mode === 'knowledge') {
        Column() {
          Image($r('app.media.ask_ai'))
            .width(16)
            .height(16)
        }
        .width(30)
        .height(30)
        .borderRadius(9)
        .linearGradient({ angle: 225, colors: [[BRAND_PRIMARY, 0], [BRAND_SECONDARY, 1]] })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .margin(10)
        .onClick(() => {
          this.askSheetVisible = true;
        })
      }
    }
    .width('76%')
    .constraintSize({ maxWidth: 520 })
  }

  // ── 评分区：3 档按钮三行全上（界面大，描述回归——用户拍板「加了很漂亮」）──
  // ★ 0.196.2：宽度自适应 130/104——手机上 3×130+20 溢出屏幕（用户实测右边按钮超框）
  // ★ 0.197.1：三按钮加上下 padding 12vp——原文字贴按钮框上下边（上 0/下 1-2vp，用户实测
  //   「框的高度增加一点，不要文字和边贴在一起」）；Button 自定义内容默认压贴边，显式内边距撑高
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
      .padding({ top: 12, bottom: 12 }) // ★ 0.197.1：文字离框边留白
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
      .padding({ top: 12, bottom: 12 }) // ★ 0.197.1：同上
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
      .padding({ top: 12, bottom: 12 }) // ★ 0.197.1：同上
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
      // ★ 0.196.3 用户拍板（标点悬挂）：「！」往后悬挂——整串居中时恭喜你中心偏左 ！/2，
      //   margin-left=！全角宽(1em=26px) 使文本右移 ！/2，大标题视觉重心恰好居中
      // ★ 0.198.0：副标题「今天的复习任务已经完成」删除（用户拍板——下方 AI 鼓励已表达同义，重复）
      Text('恭喜你！')
        .fontSize(26)
        .fontWeight(600)
        .fontColor(TEXT_PRIMARY)
        .margin({ left: 26 })
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
  // ★ 0.202.0 铁律 5：库空 → 直接给「去建卡」引导（不允许停在空完成页——用户拍板）
  @Builder
  emptyArea() {
    Column({ space: 0 }) {
      if (this.hasFutureContent()) {
        Text('今天没有到期的复习内容')
          .fontSize(16)
          .fontColor(TEXT_SECONDARY)
        Text('新词加入后会自动进入当天的复习队列')
          .fontSize(13)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 8 })
      } else {
        Text(this.mode === 'word' ? '单词库还是空的' : '知识库还是空的')
          .fontSize(16)
          .fontColor(TEXT_SECONDARY)
        Text('先添加内容，复习从这里开始')
          .fontSize(13)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 8 })
        Button(this.mode === 'word' ? '去单词库添加' : '去知识库建卡')
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .backgroundColor(BRAND_PRIMARY)
          .borderRadius(RADIUS_CONTROL)
          .padding({ left: 28, right: 28, top: 10, bottom: 10 })
          .margin({ top: 20 })
          .onClick(() => {
            if (this.mode === 'word') {
              this.pathStack.pushPath({ name: 'WordBankPage' });
            } else {
              this.pathStack.pushPath({ name: 'KnowledgeBankPage' });
            }
          })
      }
    }
    .alignItems(HorizontalAlign.Center)
  }

  // ── ★ 0.200.0 入口 C 配套：「问 AI」二选一面板（底部卡片，同知识库列表入口设计语言；点遮罩取消）──
  @Builder
  askAiSheet() {
    Column() {
      Blank()
      Column() {
        // ★ 0.201.4（用户拍板）：删标题与卡片名——从「问AI?」进来意图已明确（同知识库入口）
        Button('导入气泡对话')
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .backgroundColor(BRAND_PRIMARY)
          .borderRadius(RADIUS_CONTROL)
          .width(this.isTablet ? 280 : '100%') // ★ 0.201.2：平板固定 280 居中（手机 100% 不变），同知识库入口
          .margin({ top: 16 })
          .onClick(() => {
            this.startCardImport('import');
          })
        Text('选一个气泡 → 卡片填入它的输入框，补充问题后发送')
          .fontSize(11)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 6 })
        Button('创建子气泡')
          .fontSize(14)
          .fontColor(BRAND_SECONDARY)
          .backgroundColor(Color.Transparent)
          .borderRadius(RADIUS_CONTROL)
          .border({ width: 1, color: BRAND_SECONDARY })
          .width(this.isTablet ? 280 : '100%') // ★ 0.201.2：同上
          .margin({ top: 12 })
          .onClick(() => {
            this.startCardImport('branch');
          })
        Text('选一个父气泡 → 新建子气泡并填入卡片')
          .fontSize(11)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 6 })
        Button('取消')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .backgroundColor(Color.Transparent)
          .width(this.isTablet ? 280 : '100%') // ★ 0.201.2：同上
          .margin({ top: 12 })
          .onClick(() => {
            this.askSheetVisible = false;
          })
      }
      .width(this.isTablet ? 460 : '100%') // ★ 0.201.2：平板固定 460 居中（手机 100% 贴底不变），同知识库入口
      .borderRadius(RADIUS_NAV) // ★ 0.201.2：四角圆角（宽屏居中浮岛感；手机贴底时下圆角贴屏不可见）
      .backgroundColor(SURFACE_NODE)
      .border({ width: 1, color: STROKE_CARD })
      .padding({ left: 20, right: 20, top: 20, bottom: 28 })
      .onClick(() => {}) // 消费面板点击防冒泡到遮罩
    }
    .width('100%')
    .height('100%')
    .backgroundColor(OVERLAY)
    .onClick(() => {
      this.askSheetVisible = false;
    })
  }

  // ── ★ 0.202.0：每日复习量设置弹窗（右上角 ⚙；卡片化样式同单词库 ⚙ 先例——即时生效+完成关闭）──
  @Local csWordCustom: boolean = false;
  @Local csKnowledgeCustom: boolean = false;
  @Local csWordInput: string = '';
  @Local csKnowledgeInput: string = '';

  openCountSettings(): void {
    // 按当前值初始化分段模式（10/20 之外的值 = 自定义态）
    this.csWordCustom = this.dailyCount.wordCount !== 10 && this.dailyCount.wordCount !== 20;
    this.csKnowledgeCustom = this.dailyCount.knowledgeCount !== 10 && this.dailyCount.knowledgeCount !== 20;
    this.csWordInput = this.csWordCustom ? `${this.dailyCount.wordCount}` : '';
    this.csKnowledgeInput = this.csKnowledgeCustom ? `${this.dailyCount.knowledgeCount}` : '';
    this.countSettingsVisible = true;
  }

  applyWordCount(mode: string): void {
    if (mode === '10') {
      this.dailyCount.wordCount = 10;
      this.csWordCustom = false;
    } else if (mode === '20') {
      this.dailyCount.wordCount = 20;
      this.csWordCustom = false;
    } else {
      this.csWordCustom = true;
    }
  }

  applyKnowledgeCount(mode: string): void {
    if (mode === '10') {
      this.dailyCount.knowledgeCount = 10;
      this.csKnowledgeCustom = false;
    } else if (mode === '20') {
      this.dailyCount.knowledgeCount = 20;
      this.csKnowledgeCustom = false;
    } else {
      this.csKnowledgeCustom = true;
    }
  }

  commitCustomInput(): void {
    // 自定义输入确定（1~500 钳制；非法输入忽略）
    const w = parseInt(this.csWordInput, 10);
    if (this.csWordCustom && !Number.isNaN(w) && w >= 1 && w <= 500) {
      this.dailyCount.wordCount = w;
    }
    const k = parseInt(this.csKnowledgeInput, 10);
    if (this.csKnowledgeCustom && !Number.isNaN(k) && k >= 1 && k <= 500) {
      this.dailyCount.knowledgeCount = k;
    }
  }

  // ★ 0.209.1 修复：countSegment 带参 @Builder 按值传参不刷新（同 faceSegment）——无参化拆分，内部直读状态
  @Builder
  wordCountSegment(): void {
    Row({ space: 6 }) {
      Text('10')
        .fontSize(12)
        .fontWeight(!this.csWordCustom && this.dailyCount.wordCount === 10 ? 600 : 400)
        .fontColor(!this.csWordCustom && this.dailyCount.wordCount === 10 ? Color.White : TEXT_SECONDARY)
        .height(30)
        .padding({ left: 14, right: 14 })
        .borderRadius(8)
        .backgroundColor(!this.csWordCustom && this.dailyCount.wordCount === 10 ? BRAND_PRIMARY : Color.Transparent)
        .onClick(() => {
          this.applyWordCount('10');
        })
      Text('20')
        .fontSize(12)
        .fontWeight(!this.csWordCustom && this.dailyCount.wordCount === 20 ? 600 : 400)
        .fontColor(!this.csWordCustom && this.dailyCount.wordCount === 20 ? Color.White : TEXT_SECONDARY)
        .height(30)
        .padding({ left: 14, right: 14 })
        .borderRadius(8)
        .backgroundColor(!this.csWordCustom && this.dailyCount.wordCount === 20 ? BRAND_PRIMARY : Color.Transparent)
        .onClick(() => {
          this.applyWordCount('20');
        })
      Text('自定义')
        .fontSize(12)
        .fontWeight(this.csWordCustom ? 600 : 400)
        .fontColor(this.csWordCustom ? Color.White : TEXT_SECONDARY)
        .height(30)
        .padding({ left: 14, right: 14 })
        .borderRadius(8)
        .backgroundColor(this.csWordCustom ? BRAND_PRIMARY : Color.Transparent)
        .onClick(() => {
          this.applyWordCount('custom');
        })
    }
    .padding(3)
    .borderRadius(RADIUS_CONTROL)
    .backgroundColor(SURFACE_SOFT)
  }

  @Builder
  knowledgeCountSegment(): void {
    Row({ space: 6 }) {
      Text('10')
        .fontSize(12)
        .fontWeight(!this.csKnowledgeCustom && this.dailyCount.knowledgeCount === 10 ? 600 : 400)
        .fontColor(!this.csKnowledgeCustom && this.dailyCount.knowledgeCount === 10 ? Color.White : TEXT_SECONDARY)
        .height(30)
        .padding({ left: 14, right: 14 })
        .borderRadius(8)
        .backgroundColor(!this.csKnowledgeCustom && this.dailyCount.knowledgeCount === 10 ? BRAND_PRIMARY : Color.Transparent)
        .onClick(() => {
          this.applyKnowledgeCount('10');
        })
      Text('20')
        .fontSize(12)
        .fontWeight(!this.csKnowledgeCustom && this.dailyCount.knowledgeCount === 20 ? 600 : 400)
        .fontColor(!this.csKnowledgeCustom && this.dailyCount.knowledgeCount === 20 ? Color.White : TEXT_SECONDARY)
        .height(30)
        .padding({ left: 14, right: 14 })
        .borderRadius(8)
        .backgroundColor(!this.csKnowledgeCustom && this.dailyCount.knowledgeCount === 20 ? BRAND_PRIMARY : Color.Transparent)
        .onClick(() => {
          this.applyKnowledgeCount('20');
        })
      Text('自定义')
        .fontSize(12)
        .fontWeight(this.csKnowledgeCustom ? 600 : 400)
        .fontColor(this.csKnowledgeCustom ? Color.White : TEXT_SECONDARY)
        .height(30)
        .padding({ left: 14, right: 14 })
        .borderRadius(8)
        .backgroundColor(this.csKnowledgeCustom ? BRAND_PRIMARY : Color.Transparent)
        .onClick(() => {
          this.applyKnowledgeCount('custom');
        })
    }
    .padding(3)
    .borderRadius(RADIUS_CONTROL)
    .backgroundColor(SURFACE_SOFT)
  }

  // ★ 0.209.0：卡面模式分段控件（单面 | 正反两面——样式同 countSegment 分段）
  // ★ 0.209.1 修复：带参 @Builder 按值传参不刷新（0.190.1 铁律复发）——无参化拆分，内部直读状态
  @Builder
  wordFaceSegment(): void {
    Row({ space: 6 }) {
      Text('单面')
        .fontSize(12)
        .fontWeight(this.faceMode.wordFace !== 'double' ? 600 : 400)
        .fontColor(this.faceMode.wordFace !== 'double' ? Color.White : TEXT_SECONDARY)
        .height(30)
        .padding({ left: 14, right: 14 })
        .borderRadius(8)
        .backgroundColor(this.faceMode.wordFace !== 'double' ? BRAND_PRIMARY : Color.Transparent)
        .onClick(() => {
          this.applyWordFace('single');
        })
      Text('正反两面')
        .fontSize(12)
        .fontWeight(this.faceMode.wordFace === 'double' ? 600 : 400)
        .fontColor(this.faceMode.wordFace === 'double' ? Color.White : TEXT_SECONDARY)
        .height(30)
        .padding({ left: 14, right: 14 })
        .borderRadius(8)
        .backgroundColor(this.faceMode.wordFace === 'double' ? BRAND_PRIMARY : Color.Transparent)
        .onClick(() => {
          this.applyWordFace('double');
        })
    }
    .padding(3)
    .borderRadius(RADIUS_CONTROL)
    .backgroundColor(SURFACE_SOFT)
  }

  @Builder
  knowledgeFaceSegment(): void {
    Row({ space: 6 }) {
      Text('单面')
        .fontSize(12)
        .fontWeight(this.faceMode.knowledgeFace !== 'double' ? 600 : 400)
        .fontColor(this.faceMode.knowledgeFace !== 'double' ? Color.White : TEXT_SECONDARY)
        .height(30)
        .padding({ left: 14, right: 14 })
        .borderRadius(8)
        .backgroundColor(this.faceMode.knowledgeFace !== 'double' ? BRAND_PRIMARY : Color.Transparent)
        .onClick(() => {
          this.applyKnowledgeFace('single');
        })
      Text('正反两面')
        .fontSize(12)
        .fontWeight(this.faceMode.knowledgeFace === 'double' ? 600 : 400)
        .fontColor(this.faceMode.knowledgeFace === 'double' ? Color.White : TEXT_SECONDARY)
        .height(30)
        .padding({ left: 14, right: 14 })
        .borderRadius(8)
        .backgroundColor(this.faceMode.knowledgeFace === 'double' ? BRAND_PRIMARY : Color.Transparent)
        .onClick(() => {
          this.applyKnowledgeFace('double');
        })
    }
    .padding(3)
    .borderRadius(RADIUS_CONTROL)
    .backgroundColor(SURFACE_SOFT)
  }

  // ★ 0.209.0：切换卡面模式（即时生效；当前卡回到正面）
  applyWordFace(mode: string): void {
    this.faceMode.wordFace = mode;
    this.cardFlipped = false;
  }

  applyKnowledgeFace(mode: string): void {
    this.faceMode.knowledgeFace = mode;
    this.cardFlipped = false;
  }

  @Builder
  countSettingsDialog() {
    Column() {
      Column() {
        // ── ★ 0.209.0：卡面模式（用户需求：置于每日复习量上方）──
        Text('卡面模式')
          .fontSize(16)
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
        Text('正反两面：先看题面，点击卡片翻面后再评分')
          .fontSize(11)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
        Column() {
          Text('单词库')
            .fontSize(14)
            .fontWeight(600)
            .fontColor(TEXT_PRIMARY)
            .alignSelf(ItemAlign.Start)
          this.wordFaceSegment()
        }
        .width('100%')
        .padding(12)
        .borderRadius(RADIUS_CONTROL)
        .backgroundColor(SURFACE_SOFT)
        .margin({ top: 16 })
        Column() {
          Text('知识库')
            .fontSize(14)
            .fontWeight(600)
            .fontColor(TEXT_PRIMARY)
            .alignSelf(ItemAlign.Start)
          this.knowledgeFaceSegment()
        }
        .width('100%')
        .padding(12)
        .borderRadius(RADIUS_CONTROL)
        .backgroundColor(SURFACE_SOFT)
        .margin({ top: 12 })
        // ── 每日复习量（原有）──
        Text('每日复习量')
          .fontSize(16)
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
          .margin({ top: 20 })
        Text('进入复习页时，当日队列最多取多少条（到期+新卡）')
          .fontSize(11)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
        // ── 单词库卡片区 ──
        Column() {
          Text('单词库')
            .fontSize(14)
            .fontWeight(600)
            .fontColor(TEXT_PRIMARY)
            .alignSelf(ItemAlign.Start)
          this.wordCountSegment()
          if (this.csWordCustom) {
            Row({ space: 8 }) {
              TextInput({ text: this.csWordInput, placeholder: '1 ~ 500' })
                .fontSize(14)
                .layoutWeight(1)
                .height(36)
                .padding({ left: 12, right: 12 })
                .borderRadius(RADIUS_CONTROL)
                .backgroundColor(SURFACE_SOFT)
                .type(InputType.Number)
                .onChange((value: string) => {
                  this.csWordInput = value;
                })
              Button('确定')
                .fontSize(13)
                .height(36)
                .fontColor(TEXT_PRIMARY)
                .backgroundColor(BRAND_PRIMARY)
                .borderRadius(RADIUS_CONTROL)
                .padding({ left: 14, right: 14 })
                .onClick(() => {
                  this.commitCustomInput();
                })
            }
            .width('100%')
            .margin({ top: 10 })
          }
        }
        .width('100%')
        .padding(12)
        .borderRadius(RADIUS_CONTROL)
        .backgroundColor(SURFACE_SOFT)
        .margin({ top: 16 })
        // ── 知识库卡片区 ──
        Column() {
          Text('知识库')
            .fontSize(14)
            .fontWeight(600)
            .fontColor(TEXT_PRIMARY)
            .alignSelf(ItemAlign.Start)
          this.knowledgeCountSegment()
          if (this.csKnowledgeCustom) {
            Row({ space: 8 }) {
              TextInput({ text: this.csKnowledgeInput, placeholder: '1 ~ 500' })
                .fontSize(14)
                .layoutWeight(1)
                .height(36)
                .padding({ left: 12, right: 12 })
                .borderRadius(RADIUS_CONTROL)
                .backgroundColor(SURFACE_SOFT)
                .type(InputType.Number)
                .onChange((value: string) => {
                  this.csKnowledgeInput = value;
                })
              Button('确定')
                .fontSize(13)
                .height(36)
                .fontColor(TEXT_PRIMARY)
                .backgroundColor(BRAND_PRIMARY)
                .borderRadius(RADIUS_CONTROL)
                .padding({ left: 14, right: 14 })
                .onClick(() => {
                  this.commitCustomInput();
                })
            }
            .width('100%')
            .margin({ top: 10 })
          }
        }
        .width('100%')
        .padding(12)
        .borderRadius(RADIUS_CONTROL)
        .backgroundColor(SURFACE_SOFT)
        .margin({ top: 12 })
        Button('完成')
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .backgroundColor(BRAND_PRIMARY)
          .borderRadius(RADIUS_CONTROL)
          .width('100%')
          .margin({ top: 16 })
          .onClick(() => {
            this.commitCustomInput();
            this.countSettingsVisible = false;
            this.buildQueue(); // 新量即时生效重建队列
          })
      }
      .width(this.isTablet ? 460 : '86%')
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
      .border({ width: 1, color: STROKE_CARD })
      .padding(20)
      .onClick(() => {}) // 消费面板点击防冒泡到遮罩
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(OVERLAY)
    .onClick(() => {
      this.countSettingsVisible = false;
    })
  }

  build() {
    // ★ 0.159 模式：NavDestination + hideTitleBar(true)（自绘顶栏）——直接 Column 作根 = 全黑屏
    NavDestination() {
      // ★ 0.200.0：Stack 包裹——顶层挂「问 AI」面板（原 Column 主内容不动）
      Stack() {
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
            // ★ 0.209.3 用户拍板两连改：①占位区挪到卡片正下方（原 0.209.2 贴屏幕底——按钮与卡片
            //   之间被 Blank 弹性隔出大片空白，用户骂"上面的空格太多非常难看"；现在按钮紧跟卡片
            //   成组居中）②占位高度恒定 → 翻面瞬间卡片纹丝不动（0.209.2 跳卡修复不回归）；
            //   评分逻辑零改动
            Column() {
              if (this.faceReady) {
                this.ratingArea()
              }
            }
            .width('100%')
            .height(136) // ★ 0.209.4：按钮实测高 120vp（Pad dump 实量：三行文字+Button 自身 padding）+顶部间距 12+余量 4——原 92 可用仅 80，第三行「X天后」被容器裁剪（用户手机截图实锤）
            .padding({ top: 12 }) // 按钮与卡片底边的固定间距
            .justifyContent(FlexAlign.Start)
            Blank().layoutWeight(1)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ bottom: 32 }) // ★ 0.197.0 用户拍板：评分按钮不顶格——底部留白 32vp
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG_CANVAS)
      // ★ 0.200.0：问 AI 二选一面板（Stack 顶层）
      if (this.askSheetVisible) {
        this.askAiSheet()
      }
      // ★ 0.202.0：每日复习量设置弹窗（最顶层）
      if (this.countSettingsVisible) {
        this.countSettingsDialog()
      }
      }
    }
    .hideTitleBar(true)
    // ★ 0.200.0：面板打开时返回键先关面板
    .onBackPressed(() => {
      if (this.countSettingsVisible) {
        this.countSettingsVisible = false;
        return true;
      }
      if (this.askSheetVisible) {
        this.askSheetVisible = false;
        return true;
      }
      return false;
    })
  }
}

