// StatisticsPage.ets — 学习统计页（★ 0.192.0 用户定稿）
// 入口：边栏「统计」（知识库下方）+ 边栏底部账号行点击
// 内容：AI 鼓励卡（按统计数据找亮点吹捧——数据再差也能找到优点）+ 日/周/月/年柱状图 + 三大块卡片
//   ①对话（累计条数/气泡数 + 今日昨日/本周上周环比）②学习资产（词库/知识库：总数/已学/未来7天待复习）
//   ③token（累计输入输出 + 本周上周）
// 统计口径：只增不减（消息/气泡删除不影响已统计数据，用户明确要求）

import { WordItem, WordBankStore } from '../common/WordModel';
import { KnowledgeCard, KnowledgeBankStore } from '../common/KnowledgeModel';
import { ChatMessage, ApiConfig, AiPreference, StatisticsStore, StatDayEntry, connectStatistics, connectAiPreference, connectApiConfig, getStatDays, statDateKey, generateMessageId, StatDayData } from '../common/ChatModel';
import { buildStatEncouragePrompt } from '../common/Prompts'; // ★ 0.193.0：统计鼓励 prompt 单一真相源
import { connectWordBank } from '../utils/WordStoreUtil';
import { connectKnowledgeBank } from '../utils/KnowledgeStoreUtil';
import { streamChat } from '../utils/ApiClient';
import { PersistenceV2 } from '@kit.ArkUI'; // ★ 0.202.3：测试数据 seed marker
import { BG_APP, SURFACE_NODE, SURFACE_SOFT, BRAND_PRIMARY, BRAND_SECONDARY, TEXT_PRIMARY, TEXT_SECONDARY, TEXT_TERTIARY, STROKE_CARD, SEGMENTED_TRACK, RADIUS_CONTROL, RADIUS_NAV, FONT_SIZE_SCREEN_TITLE, FONT_SIZE_CARD_TITLE_SM, FONT_SIZE_BODY } from '../common/DesignTokens';

// 柱状图桶（一个周期一根柱）
class StatBucket {
  label: string;
  value: number;
  constructor(label: string, value: number) {
    this.label = label;
    this.value = value;
  }
}

// 区间聚合结果
class StatAgg {
  msgs: number = 0;
  bubbles: number = 0;
  tokens: number = 0;
  siyi: number = 0; // ★ 0.202.3
}

// ★ 0.202.3：测试数据 seed marker（上线清零时随 seedTestData 一起删除）
@ObservedV2
class StatsTestSeedMarker {
  @Trace v: number = 0;
}

@ComponentV2
export struct StatisticsPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  statStore: StatisticsStore = connectStatistics();
  aiPreference: AiPreference = connectAiPreference();
  apiConfig: ApiConfig = connectApiConfig();
  wordBank: WordBankStore = connectWordBank();
  knowledgeBank: KnowledgeBankStore = connectKnowledgeBank();
  @Local rangeMode: number = 0; // 0=日 1=周 2=月 3=年
  @Local aiText: string = '';
  @Local aiLoading: boolean = false;

  aboutToAppear(): void {
    this.seedTestData(); // ★ 0.202.3：一年测试数据（一次性注入——上线前删除本方法+marker 即清零）
    this.requestAiEncourage();
  }

  // ── ★ 0.202.3：一年测试数据（用户验收统计图表用；上线前清零=删 seedTestData 调用+marker 类）──
  // 形态：360 天前→4 天前；增长趋势（25%→100%）+ 周末低谷（×0.4）+ 随机波动；近 3 天不造保真实
  seedTestData(): void {
    const marker = PersistenceV2.connect(StatsTestSeedMarker, 'stats-test-seed-v1', () => new StatsTestSeedMarker()) as StatsTestSeedMarker;
    if (marker.v >= 1) {
      return;
    }
    marker.v = 1;
    const days = getStatDays(this.statStore);
    const existing = new Set<string>();
    days.forEach((d: StatDayEntry) => {
      existing.add(d.date);
    });
    const out: StatDayEntry[] = [...days];
    const n = new Date();
    n.setHours(0, 0, 0, 0);
    for (let back = 360; back >= 4; back--) {
      const ts = n.getTime() - back * 86400000;
      const key = statDateKey(ts);
      if (existing.has(key)) {
        continue; // 已有真实数据的日期不覆盖
      }
      const d = new Date(ts);
      const dow = (d.getDay() + 6) % 7; // 周一=0
      const growth = 0.25 + 0.75 * (1 - back / 360);
      const weekend = dow >= 5 ? 0.4 : 1;
      const jitter = 0.7 + Math.random() * 0.6;
      const userM = Math.max(0, Math.round(14 * growth * weekend * jitter));
      const aiM = Math.max(0, Math.round(16 * growth * weekend * jitter));
      const bub = Math.random() < 0.6 ? Math.round(3 * growth * weekend * jitter) : 0;
      const inT = Math.round((1200 + 2800 * growth) * weekend * jitter * (userM + 1) / 10);
      const outT = Math.round(inT * (0.5 + Math.random() * 0.5));
      const sy = Math.round((6 + 26 * growth) * weekend * jitter);
      out.push({ date: key, userMsgs: userM, aiMsgs: aiM, bubbles: bub, inputTokens: inT, outputTokens: outT, siyi: sy });
    }
    this.statStore.raw = JSON.stringify({ days: out } as StatDayData);
  }

  // ── 区间聚合：[fromTs, toTs) 内的累计 ──
  sumRange(fromTs: number, toTs: number): StatAgg {
    const agg = new StatAgg();
    const days = getStatDays(this.statStore);
    const fromKey = statDateKey(fromTs);
    const toKey = statDateKey(toTs);
    for (let i = 0; i < days.length; i++) {
      const d: StatDayEntry = days[i];
      if (d.date >= fromKey && d.date < toKey) {
        agg.msgs += d.userMsgs + d.aiMsgs;
        agg.bubbles += d.bubbles;
        agg.tokens += d.inputTokens + d.outputTokens;
        agg.siyi += d.siyi ?? 0;
      }
    }
    return agg;
  }

  // ── 全量累计 ──
  sumAll(): StatAgg {
    const agg = new StatAgg();
    const days = getStatDays(this.statStore);
    for (let i = 0; i < days.length; i++) {
      agg.msgs += days[i].userMsgs + days[i].aiMsgs;
      agg.bubbles += days[i].bubbles;
      agg.tokens += days[i].inputTokens + days[i].outputTokens;
      agg.siyi += days[i].siyi ?? 0;
    }
    return agg;
  }

  // ── 时间锚点 ──
  todayStart(): number {
    const d = new Date();
    d.setHours(0, 0, 0, 0);
    return d.getTime();
  }

  weekStart(offsetWeeks: number): number {
    // 本周一 0 点（offsetWeeks=0 本周 / -1 上周）
    const d = new Date(this.todayStart());
    const dow = (d.getDay() + 6) % 7; // 周一=0
    d.setDate(d.getDate() - dow + offsetWeeks * 7);
    return d.getTime();
  }

  // ── ★ 0.202.3：图表指标切换（四大卡点击联动）──
  // msg=对话条数 / bubble=新建气泡 / token=token 消耗 / siyi=司忆量（被司忆区展示次数）
  @Local selectedMetric: string = 'msg';

  metricOfDay(d: StatDayEntry): number {
    if (this.selectedMetric === 'bubble') {
      return d.bubbles;
    }
    if (this.selectedMetric === 'token') {
      return d.inputTokens + d.outputTokens;
    }
    if (this.selectedMetric === 'siyi') {
      return d.siyi ?? 0;
    }
    return d.userMsgs + d.aiMsgs;
  }

  metricOfAgg(a: StatAgg): number {
    if (this.selectedMetric === 'bubble') {
      return a.bubbles;
    }
    if (this.selectedMetric === 'token') {
      return a.tokens;
    }
    if (this.selectedMetric === 'siyi') {
      return a.siyi;
    }
    return a.msgs;
  }

  metricName(): string {
    if (this.selectedMetric === 'bubble') {
      return '新建气泡（个）';
    }
    if (this.selectedMetric === 'token') {
      return 'Token 消耗';
    }
    if (this.selectedMetric === 'siyi') {
      return '司忆量（次）——卡片被司忆区展示';
    }
    return '对话条数（条）';
  }

  fmtMetric(v: number): string {
    if (this.selectedMetric === 'token' && v >= 10000) {
      return `${(v / 1000).toFixed(1)}k`;
    }
    return `${v}`;
  }

  // ── 柱状图数据（@Computed 依赖 rangeMode + statStore.raw 自动重算）──
  @Computed
  get chartBuckets(): StatBucket[] {
    const days = getStatDays(this.statStore);
    const buckets: StatBucket[] = [];
    if (this.rangeMode === 0) {
      // 日：最近 14 天
      for (let i = 13; i >= 0; i--) {
        const ts = this.todayStart() - i * 86400000;
        const key = statDateKey(ts);
        let v = 0;
        for (let j = 0; j < days.length; j++) {
          if (days[j].date === key) {
            v = this.metricOfDay(days[j]);
            break;
          }
        }
        const d = new Date(ts);
        buckets.push(new StatBucket(`${d.getMonth() + 1}/${d.getDate()}`, v));
      }
    } else if (this.rangeMode === 1) {
      // 周：最近 12 周
      for (let i = -11; i <= 0; i++) {
        const agg = this.sumRange(this.weekStart(i), this.weekStart(i + 1));
        const d = new Date(this.weekStart(i));
        buckets.push(new StatBucket(`${d.getMonth() + 1}/${d.getDate()}`, this.metricOfAgg(agg)));
      }
    } else if (this.rangeMode === 2) {
      // 月：最近 12 个月
      for (let i = -11; i <= 0; i++) {
        const d = new Date();
        d.setDate(1);
        d.setHours(0, 0, 0, 0);
        d.setMonth(d.getMonth() + i);
        const from = d.getTime();
        const e = new Date(d);
        e.setMonth(e.getMonth() + 1);
        const agg = this.sumRange(from, e.getTime());
        buckets.push(new StatBucket(`${d.getMonth() + 1}月`, this.metricOfAgg(agg)));
      }
    } else {
      // 年：所有出现过的年份
      const yearSet: number[] = [];
      for (let i = 0; i < days.length; i++) {
        const y = Number(days[i].date.substring(0, 4));
        if (yearSet.indexOf(y) < 0) {
          yearSet.push(y);
        }
      }
      yearSet.sort((a: number, b: number) => a - b);
      for (let i = 0; i < yearSet.length; i++) {
        let v = 0;
        for (let j = 0; j < days.length; j++) {
          if (days[j].date.substring(0, 4) === `${yearSet[i]}`) {
            v += this.metricOfDay(days[j]);
          }
        }
        buckets.push(new StatBucket(`${yearSet[i]}`, v));
      }
    }
    return buckets;
  }

  @Computed
  get chartMax(): number {
    let max = 0;
    const bs = this.chartBuckets;
    for (let i = 0; i < bs.length; i++) {
      if (bs[i].value > max) {
        max = bs[i].value;
      }
    }
    return max > 0 ? max : 1;
  }

  // ── 学习资产统计（实时读词库/知识库）──
  // 未来 7 天待复习：nextReviewAt 在 [now, now+7天) 内，或 nextReviewAt=0（新词/新卡视为已到期）
  countDueIn7Days(items: WordItem[] | KnowledgeCard[]): number {
    const now = Date.now();
    const week = now + 7 * 86400000;
    let n = 0;
    for (let i = 0; i < items.length; i++) {
      const t = items[i].nextReviewAt;
      if (t === 0 || (t >= now && t < week)) {
        n += 1;
      }
    }
    return n;
  }

  countLearned(items: WordItem[] | KnowledgeCard[]): number {
    let n = 0;
    for (let i = 0; i < items.length; i++) {
      if (items[i].reviewCount > 0) {
        n += 1;
      }
    }
    return n;
  }

  // ── AI 鼓励：统计数据文本（增长由前端算好，AI 只管找亮点吹）──
  buildStatDataText(): string {
    const all = this.sumAll();
    const today = this.sumRange(this.todayStart(), this.todayStart() + 86400000);
    const yesterday = this.sumRange(this.todayStart() - 86400000, this.todayStart());
    const thisWeek = this.sumRange(this.weekStart(0), this.weekStart(1));
    const lastWeek = this.sumRange(this.weekStart(-1), this.weekStart(0));
    const words = this.wordBank.words;
    const cards = this.knowledgeBank.cards;
    return `【学习统计数据】
累计对话：${all.msgs} 条（今日 ${today.msgs} / 昨日 ${yesterday.msgs}；本周 ${thisWeek.msgs} / 上周 ${lastWeek.msgs}）
累计气泡：${all.bubbles} 个（本周新增 ${thisWeek.bubbles} / 上周新增 ${lastWeek.bubbles}）
单词库：共 ${words.length} 词（已学习 ${this.countLearned(words)}；未来 7 天待复习 ${this.countDueIn7Days(words)}）
知识库：共 ${cards.length} 卡（已学习 ${this.countLearned(cards)}；未来 7 天待复习 ${this.countDueIn7Days(cards)}）
累计 token：${all.tokens}（本周 ${thisWeek.tokens} / 上周 ${lastWeek.tokens}）`;
  }

  // ── AI 鼓励请求（档位跟随设置；off 不生成；称谓拼入；核心=数据再差也找优点）──
  // ★ 0.193.0：prompt 迁入 Prompts.ts（buildStatEncouragePrompt 单一真相源）
  requestAiEncourage(): void {
    if (this.aiPreference.encourageMode === 'off') {
      this.aiText = '';
      return;
    }
    const sys = buildStatEncouragePrompt(this.aiPreference.encourageMode, this.aiPreference.aiNickname.trim(), this.buildStatDataText());
    this.aiLoading = true;
    this.aiText = '';
    const messages: ChatMessage[] = [
      new ChatMessage(generateMessageId(), 'system', sys),
      new ChatMessage(generateMessageId(), 'user', '请根据我的学习统计数据给我一句鼓励。')
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
        this.aiText = '鼓励生成失败，请检查 API 配置后重进本页重试';
      },
      (reasoning: string) => {
        // 统计鼓励无需思考流展示，空回调占位
      }
    );
  }

  // ── 顶栏（自绘，hideTitleBar 模式同词库/知识库）──
  @Builder
  topBar() {
    Row() {
      Button('←')
        .fontSize(18)
        .backgroundColor(Color.Transparent)
        .fontColor(TEXT_PRIMARY)
        .padding({ left: 4, right: 4 })
        .margin({ right: 4 })
        .onClick(() => {
          this.pathStack.pop();
        })
      Text('统计')
        .fontSize(FONT_SIZE_SCREEN_TITLE)
        .fontWeight(600)
        .fontColor(TEXT_PRIMARY)
      Blank()
        .layoutWeight(1)
    }
    .width('100%')
  }

  build() {
    // ★ 0.192.0 修复：根组件必须 NavDestination + hideTitleBar(true)（词库/知识库同款 0.159 模式）——
    //   直接用 Column 作根组件 Navigation 无法渲染 → 全黑屏（真机实测）
    NavDestination() {
      Column() {
        this.topBar()

        Scroll() {
          Column() {
            // ── AI 鼓励卡（档位非关闭时显示）──
            if (this.aiPreference.encourageMode !== 'off') {
              Column() {
                Row({ space: 6 }) {
                  Text('✨')
                    .fontSize(14)
                  Text('AI 学习鼓励')
                    .fontSize(FONT_SIZE_CARD_TITLE_SM)
                    .fontWeight(600)
                    .fontColor(BRAND_SECONDARY)
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                if (this.aiLoading && this.aiText.length === 0) {
                  Text('等待服务器返回')
                    .fontSize(FONT_SIZE_BODY)
                    .fontColor(TEXT_TERTIARY)
                    .margin({ top: 8 })
                } else {
                  Text(this.aiText.length > 0 ? this.aiText : '（进入本页自动生成）')
                    .fontSize(FONT_SIZE_BODY)
                    .lineHeight(22)
                    .fontColor(TEXT_SECONDARY)
                    .margin({ top: 8 })
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(14)
              .borderRadius(RADIUS_NAV)
              .backgroundColor(SURFACE_SOFT)
              .border({ width: 1, color: BRAND_SECONDARY })
              .margin({ bottom: 16 })
            }

            // ── 维度分段：日/周/月/年 ──
            Row() {
              Text('日')
                .fontSize(13)
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .padding({ top: 7, bottom: 7 })
                .borderRadius(RADIUS_CONTROL - 2)
                .fontColor(this.rangeMode === 0 ? TEXT_PRIMARY : TEXT_SECONDARY)
                .backgroundColor(this.rangeMode === 0 ? BRAND_PRIMARY : Color.Transparent)
                .onClick(() => { this.rangeMode = 0; })
              Text('周')
                .fontSize(13)
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .padding({ top: 7, bottom: 7 })
                .borderRadius(RADIUS_CONTROL - 2)
                .fontColor(this.rangeMode === 1 ? TEXT_PRIMARY : TEXT_SECONDARY)
                .backgroundColor(this.rangeMode === 1 ? BRAND_PRIMARY : Color.Transparent)
                .onClick(() => { this.rangeMode = 1; })
              Text('月')
                .fontSize(13)
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .padding({ top: 7, bottom: 7 })
                .borderRadius(RADIUS_CONTROL - 2)
                .fontColor(this.rangeMode === 2 ? TEXT_PRIMARY : TEXT_SECONDARY)
                .backgroundColor(this.rangeMode === 2 ? BRAND_PRIMARY : Color.Transparent)
                .onClick(() => { this.rangeMode = 2; })
              Text('年')
                .fontSize(13)
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .padding({ top: 7, bottom: 7 })
                .borderRadius(RADIUS_CONTROL - 2)
                .fontColor(this.rangeMode === 3 ? TEXT_PRIMARY : TEXT_SECONDARY)
                .backgroundColor(this.rangeMode === 3 ? BRAND_PRIMARY : Color.Transparent)
                .onClick(() => { this.rangeMode = 3; })
            }
            .width('100%')
            .padding(4)
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(SEGMENTED_TRACK)
            .margin({ bottom: 12 })

            // ── 柱状图（★ 0.202.3：跟随四大卡选中指标切换）──
            Column() {
              Text(this.metricName())
                .fontSize(12)
                .fontColor(TEXT_SECONDARY)
                .alignSelf(ItemAlign.Start)
                .margin({ bottom: 8 })
              Row({ space: 5 }) {
                ForEach(this.chartBuckets, (b: StatBucket, i: number) => {
                  Column({ space: 3 }) {
                    Column()
                      .width('100%')
                      .height(b.value > 0 ? Math.max(6, Math.round(b.value / this.chartMax * 110)) : 2)
                      .borderRadius(3)
                      .backgroundColor(b.value > 0 ? BRAND_PRIMARY : STROKE_CARD)
                    Text(b.label)
                      .fontSize(9)
                      .fontColor(TEXT_TERTIARY)
                      .maxLines(1)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Center)
                }, (b: StatBucket, i: number) => `${i}_${b.label}_${b.value}`)
              }
              .width('100%')
              .alignItems(VerticalAlign.Bottom)
              .height(140)
            }
            .width('100%')
            .padding(12)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(SURFACE_NODE)
            .margin({ bottom: 16 })

            // ── 块①：对话统计（★ 0.202.3 点击切换图表指标；选中态主��描边）──
            Column() {
              Text('对话')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(600)
                .fontColor(TEXT_PRIMARY)
                .margin({ bottom: 8 })
              this.StatRow('累计对话', `${this.sumAll().msgs} 条`)
              this.StatRow('累计气泡', `${this.sumAll().bubbles} 个`)
              this.StatRow('今日 / 昨日', `${this.sumRange(this.todayStart(), this.todayStart() + 86400000).msgs} / ${this.sumRange(this.todayStart() - 86400000, this.todayStart()).msgs} 条`)
              this.StatRow('本周 / 上周', `${this.sumRange(this.weekStart(0), this.weekStart(1)).msgs} / ${this.sumRange(this.weekStart(-1), this.weekStart(0)).msgs} 条`)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(SURFACE_NODE)
            .border({ width: this.selectedMetric === 'msg' ? 1.5 : 0, color: BRAND_PRIMARY })
            .margin({ bottom: 12 })
            .onClick(() => {
              this.selectedMetric = 'msg';
            })

            // ── 块②：学习资产（点击→图表切「新建气泡」序列）──
            Column() {
              Text('学习资产')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(600)
                .fontColor(TEXT_PRIMARY)
                .margin({ bottom: 8 })
              this.StatRow('单词库', `共 ${this.wordBank.words.length} 词 · 已学 ${this.countLearned(this.wordBank.words)} · 7 天内待复习 ${this.countDueIn7Days(this.wordBank.words)}`)
              this.StatRow('知识库', `共 ${this.knowledgeBank.cards.length} 卡 · 已学 ${this.countLearned(this.knowledgeBank.cards)} · 7 天内待复习 ${this.countDueIn7Days(this.knowledgeBank.cards)}`)
              this.StatRow('累计新建气泡', `${this.sumAll().bubbles} 个`)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(SURFACE_NODE)
            .border({ width: this.selectedMetric === 'bubble' ? 1.5 : 0, color: BRAND_PRIMARY })
            .margin({ bottom: 12 })
            .onClick(() => {
              this.selectedMetric = 'bubble';
            })

            // ── 块③：token ──
            Column() {
              Text('Token')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(600)
                .fontColor(TEXT_PRIMARY)
                .margin({ bottom: 8 })
              this.StatRow('累计消耗', this.fmtMetric(this.sumAll().tokens))
              this.StatRow('本周 / 上周', `${this.fmtMetric(this.sumRange(this.weekStart(0), this.weekStart(1)).tokens)} / ${this.fmtMetric(this.sumRange(this.weekStart(-1), this.weekStart(0)).tokens)}`)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(SURFACE_NODE)
            .border({ width: this.selectedMetric === 'token' ? 1.5 : 0, color: BRAND_PRIMARY })
            .margin({ bottom: 12 })
            .onClick(() => {
              this.selectedMetric = 'token';
            })

            // ── 块④：司忆量（★ 0.202.3 新增——单词/知识卡被司忆区展示的次数，产品特色指标）──
            Column() {
              Text('司忆量')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(600)
                .fontColor(TEXT_PRIMARY)
                .margin({ bottom: 8 })
              this.StatRow('累计司忆', `${this.sumAll().siyi} 次`)
              this.StatRow('本周 / 上周', `${this.sumRange(this.weekStart(0), this.weekStart(1)).siyi} / ${this.sumRange(this.weekStart(-1), this.weekStart(0)).siyi} 次`)
              Text('单词与知识卡被司忆区展示出来的每一次，都在悄悄加固你的记忆')
                .fontSize(11)
                .fontColor(TEXT_TERTIARY)
                .margin({ top: 6 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(SURFACE_NODE)
            .border({ width: this.selectedMetric === 'siyi' ? 1.5 : 0, color: BRAND_PRIMARY })
            .margin({ bottom: 12 })
            .onClick(() => {
              this.selectedMetric = 'siyi';
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 24 })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .align(Alignment.TopStart)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG_APP)
      .expandSafeArea([SafeAreaType.SYSTEM])
    }
    .hideTitleBar(true)
  }

  // 统计行（label + 值）
  @Builder
  StatRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(FONT_SIZE_BODY)
        .fontColor(TEXT_SECONDARY)
      Blank()
        .layoutWeight(1)
      Text(value)
        .fontSize(FONT_SIZE_BODY)
        .fontColor(TEXT_PRIMARY)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ top: 5, bottom: 5 })
  }
}
