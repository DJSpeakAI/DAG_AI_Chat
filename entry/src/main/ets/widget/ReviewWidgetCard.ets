// ============================================================
// ReviewWidgetCard.ets — ★ 0.204.0 桌面卡片 UI（卡片上直接复习）
// ============================================================
// 用户拍板：去掉跳 APP——卡片自闭环：切库（单词库/知识卡）+ 三档评分，
//   全部 postCardAction call → EntryAbility Callee → 主进程真数据 → updateForm 推回。
// 规格（supportDimensions 2×4/4×4，dimension 键由 onSizeChanged 写入）：
//   3=2×4 标准（切库 pill+正面题面/反面 List 滚动+三按钮两行）
//   4=4×4 大卡（切库+统计行+正面大题面/反面 List+三按钮三行）
// ★ 0.252.0 固定双面双态排版：正面=题面（标题居中放大+「点击查看答案」）；
//   反面=答案面（标题+音标+释义滚动+三档评分——先回忆后自评）。
// 完成态：纯文案+统计（无跳转——用户明确拍板去掉）。
//
// ★ 0.255.0 切库根治三件套（替换 0.252.0 消费层方案——空 onClick 挡不住冒泡，实锤无效）：
//   ① 热区收窄：翻面 onClick 只挂正面题面 Column——pill/评分/音标从热区物理移出，
//      冒泡双发（switch+flip 双 call 竞态）在结构上不可能发生；
//   ② 全局动作门闸 gate()：rate/switch/flip/continue 四出口共用 500ms 冷却——
//      一次物理点击无论冒泡触发几个 onClick 只发一个 call；同时根治评分连点跳卡
//      （call 通道 handleWidgetRate 无时间戳闸，刷新未回连点=idx 跳两格丢卡）；
//      （置灰视觉反馈编译实锤降级删除：卡片渲染进程禁 setTimeout 无复位路径——
//       静默忽略+主进程 300ms 延迟重推已保证刷新及时，体验损失极小）
//   （发音 speak 不进门闸：反面无卡身 onClick 无双发风险，主进程 WordSpeaker 自带防重）
// ★ 0.255.0 布局：反面 List 替代 Scroll（卡片进程硬约束）+评分按钮固定高度不被挤出
//   +标题自适应字号（maxFontSize/minFontSize——heightAdaptivePolicy/wordBreak 卡片
//   编译器拒斥已删，默认策略即 MAX_LINES_FIRST）+音标显示与点击发音。
// 注意：卡片环境 API 受限——纯 UI + postCardAction，无复杂逻辑。
// ============================================================

const BG_CARD = '#1C1130';        // 卡片底（暗紫，深于 SURFACE_NODE 与桌面协调）
const TITLE_COLOR = '#F4F1FA';
const SUB_COLOR = '#B9B3C7';
const ACCENT = '#9B7BFF';         // 辅助紫（与主应用 BRAND_SECONDARY 同族）
// 三档评分配色（同源主应用 ReviewPage REVIEW_HARD/GOOD/EASY——卡片进程禁 import token 文件，常量复制）
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
  @LocalStorageProp('phonetic') phonetic: string = ''; // ★ 0.255.0：单词卡音标（宿主 wordToItem 注入；知识卡空串）
  @LocalStorageProp('progress') progress: string = '';
  @LocalStorageProp('remain') remain: string = '0';
  @LocalStorageProp('done') done: string = 'n';
  @LocalStorageProp('dimension') dimension: string = '3';
  @LocalStorageProp('hard') hard: string = '0';
  @LocalStorageProp('good') good: string = '0';
  @LocalStorageProp('easy') easy: string = '0';
  @LocalStorageProp('noMore') noMore: string = 'n';
  @LocalStorageProp('face') face: string = 'double';   // ★ 0.252.0：恒 'double'（全局固定双面——快照注入值已恒定，字段保留兼容旧快照）
  @LocalStorageProp('flipped') flipped: string = 'n';  // ★ 0.224.0：翻面态
  @LocalStorageProp('hardEta') hardEta: string = '';   // ★ 0.252.1：生疏后预计间隔（宿主预计算注入）
  @LocalStorageProp('goodEta') goodEta: string = '';   // ★ 0.252.1：尚可后预计间隔
  @LocalStorageProp('easyEta') easyEta: string = '';   // ★ 0.252.1：熟知后预计间隔

  lastActionAt: number = 0; // ★ 0.255.0：全局动作门闸时间戳（纯逻辑，无 UI 依赖）

  dim(): number {
    return Number(this.dimension);
  }

  // ★ 0.252.0：反面可见性（全局固定双面——翻面后才显反面；face 字段保留仅作旧快照兼容）
  showBack(): boolean {
    return this.face !== 'double' || this.flipped === 'y';
  }

  // ★ 0.255.0：全局动作门闸——500ms 内只放行一个改状态 call（rate/switch/flip/continue 共用）。
  //   挡两类事故：①一次物理点击冒泡触发多个 onClick 双发 call 竞态（热区收窄后理论不可能，兜底）
  //   ②刷新未回时连点撞 call 超时窗/updateForm 合并窗（含评分连点 idx 跳卡）。
  //   静默忽略（置灰视觉因卡片禁 setTimeout 无复位路径已删——见文件头注释）。
  gate(): boolean {
    const now = Date.now();
    if (now - this.lastActionAt < 500) {
      return false;
    }
    this.lastActionAt = now;
    return true;
  }

  // ── 交互出口（★ 0.204.1 定稿：call 通道——message 的 msg 在本机桌面被 IPC 剥空，
  //    A/B 组实验均为 ''；call 的 params 与 router 同通路已验证可穿透）──
  // call 后台拉起 EntryAbility（不显示 UI）→ 主应用进程真数据评分 → updateForm 推回卡片
  sendRate(rating: string): void {
    if (!this.gate()) {
      return;
    }
    postCardAction(this, {
      'action': 'call',
      'abilityName': 'EntryAbility',
      'method': 'widgetRate',
      'params': { 'method': 'widgetRate', 'cmd': 'rate', 'rating': rating }
    });
  }

  sendSwitch(target: string): void {
    if (!this.gate()) {
      return;
    }
    postCardAction(this, {
      'action': 'call',
      'abilityName': 'EntryAbility',
      'method': 'widgetSwitch',
      'params': { 'method': 'widgetSwitch', 'cmd': 'switch', 'mode': target }
    });
  }

  // ★ 0.204.2：继续复习——完成态点击拉未来队列继续背（call 通道同上）
  sendContinue(): void {
    if (!this.gate()) {
      return;
    }
    postCardAction(this, {
      'action': 'call',
      'abilityName': 'EntryAbility',
      'method': 'widgetContinue',
      'params': { 'method': 'widgetContinue', 'cmd': 'continue' }
    });
  }

  // ★ 0.224.0：双面模式卡身翻面（call 通道——主进程切 flipped 推回；纯显示态零数据变更）
  sendFlip(): void {
    if (!this.gate()) {
      return;
    }
    postCardAction(this, {
      'action': 'call',
      'abilityName': 'EntryAbility',
      'method': 'widgetFlip',
      'params': { 'method': 'widgetFlip', 'cmd': 'flip' }
    });
  }

  // ★ 0.255.0：音标点击发音——主进程发音单例（本地 TTS 双引擎+防重+口音联动全继承；
  //   不 updateForm 不占刷新窗；不进门闸——反面无卡身 onClick 无双发，主进程自带防重）
  sendSpeak(word: string): void {
    postCardAction(this, {
      'action': 'call',
      'abilityName': 'EntryAbility',
      'method': 'widgetSpeak',
      'params': { 'method': 'widgetSpeak', 'cmd': 'speak', 'word': word }
    });
  }

  // ── 切库 pill（当前模式高亮）──
  // ★ 0.255.0：0.252.0「消费层空 onClick」已删——空 onClick 物理上挡不住冒泡（事件照样
  //   穿过到卡身），该修复无效；冒泡双发改由「热区收窄+gate 门闸」根治（见文件头注释）。
  @Builder
  switchPill(label: string, target: string, active: boolean) {
    Text(label)
      .fontSize(10)
      .fontFamily('HarmonyOS Sans')
      .fontColor(active ? '#FFFFFF' : SUB_COLOR)
      .padding({ left: 9, right: 9, top: 3, bottom: 3 })
      .borderRadius(10)
      .backgroundColor(active ? '#559B7BFF' : '#1AFFFFFF')
      .onClick(() => {
        if (!active) {
          this.sendSwitch(target);
        }
      })
  }

  // ★ 0.255.0：评分按钮对齐主应用 ReviewPage 三行结构（档名档色粗体+描述灰+预计间隔档色带「后」）；
  //   2×4 空间所限两行（描述省略）；「后」字在卡片 UI 层拼接（formatEtaDays 保持纯数字语义）
  @Builder
  rateButton(label: string, desc: string, eta: string, rating: string,
    color: string, bg: string, heightLen: number, nameFont: number,
    descFont: number, etaFont: number, showDesc: boolean) {
    Column({ space: 1 }) {
      Text(label)
        .fontSize(nameFont)
        .fontWeight(600)
        .fontColor(color)
      if (showDesc) {
        Text(desc)
          .fontSize(descFont)
          .fontColor(SUB_COLOR)
          .maxLines(1)
      }
      Text(`${eta}后`)
        .fontSize(etaFont)
        .fontColor(color)
        .maxLines(1)
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

  // ★ 0.255.0：音标行——正面仅展示（题面聚焦背诵）；反面可点发音（热区左右外扩 8vp 保小字可点性）
  @Builder
  phoneticRow(clickable: boolean, fontLen: number) {
    Text(this.phonetic)
      .fontSize(fontLen)
      .fontColor(SUB_COLOR)
      .width('100%')
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .padding({ left: 8, right: 8, top: clickable ? 4 : 0, bottom: clickable ? 4 : 0 })
      .onClick(() => {
        if (clickable && this.title.length > 0) {
          this.sendSpeak(this.title);
        }
      })
  }

  // ── 完成态（纯文案+统计；零评分=空库引导；★ 0.204.2 用户拍板两规格必须加「继续复习」按钮；
  //    noMore=y=连未来队列都空 →「全部学完」无按钮态）──
  @Builder
  doneArea() {
    Column({ space: 6 }) {
      if (this.noMore === 'y') {
        if (Number(this.hard) + Number(this.good) + Number(this.easy) > 0) {
          Text('🏅')
            .fontSize(this.dim() === 4 ? 40 : 30)
          Text('全部学完啦')
            .fontSize(this.dim() === 4 ? 16 : 13)
            .fontColor(TITLE_COLOR)
          Text('明天再来，记忆更牢固')
            .fontSize(10)
            .fontColor(SUB_COLOR)
        } else {
          Text('📚')
            .fontSize(this.dim() === 4 ? 40 : 30)
          Text('暂无复习内容')
            .fontSize(this.dim() === 4 ? 16 : 13)
            .fontColor(TITLE_COLOR)
          Text('打开应用添加单词或知识卡')
            .fontSize(10)
            .fontColor(SUB_COLOR)
        }
      } else {
        Text('🎉')
          .fontSize(this.dim() === 4 ? 40 : 30)
        Text('今日复习已完成')
          .fontSize(this.dim() === 4 ? 16 : 13)
          .fontColor(TITLE_COLOR)
        Text('明天再来，记忆更牢固')
          .fontSize(10)
          .fontColor(SUB_COLOR)
        Text(`生疏 ${this.hard} · 尚可 ${this.good} · 熟知 ${this.easy}`)
          .fontSize(11)
          .fontColor(ACCENT)
          .margin({ top: 2 })
        // ★ 0.204.2：继续复习按钮（把未来排期提前背——用户拍板必加）
        Text('继续复习 ›')
          .fontSize(13)
          .fontWeight(600)
          .fontColor(TITLE_COLOR)
          .padding({ left: 22, right: 22, top: 9, bottom: 9 })
          .backgroundColor('#339B7BFF')
          .borderRadius(999)
          .margin({ top: 6 })
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
      } else {
        // ── 2×4 标准 / 4×4 大卡（★ 0.252.0 固定双面双态排版）：正面=标题居中放大+翻面提示 / 反面=List 滚动答案面 ──
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

          if (this.showBack()) {
            // 反面（答案面）：List 滚动（卡片进程 Scroll 不支持，List 是平台硬约束下的正解）——
            // 标题/音标/释义全部居中（对齐 app 内复习卡排版）；释义不设 maxLines 靠滚动看完
            List({ space: 6 }) {
              ListItem() {
                Text(this.title)
                  .fontSize(this.dim() === 4 ? 20 : 18)
                  .fontWeight(600)
                  .fontColor(TITLE_COLOR)
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .maxFontSize(this.dim() === 4 ? 20 : 18)
                  .minFontSize(12)
                  .maxLines(2)
              }
              if (this.mode === 'word' && this.phonetic.length > 0) {
                ListItem() {
                  this.phoneticRow(true, 11)
                }
              }
              if (this.definition.length > 0) {
                ListItem() {
                  Text(this.definition)
                    .fontSize(this.dim() === 4 ? 12 : 11)
                    .fontColor(SUB_COLOR)
                    .lineHeight(this.dim() === 4 ? 18 : 16)
                    .width('100%')
                    .textAlign(TextAlign.Center)
                }
              }
            }
            .layoutWeight(1)
            .width('100%')
            .scrollBar(BarState.Off)
            .alignListItem(ListItemAlign.Center)
          } else {
            // 正面（题面）：标题居中放大聚焦背诵 + 音标小字 + 底部翻面提示。
            // ★ 0.255.0 热区收窄：翻面 onClick 只挂本区（pill 行/评分区从热区物理移出——
            //   冒泡双发结构性根除；反面=终态不挂 onClick，0.209.3 同语义）
            Column({ space: 4 }) {
              Blank()
              Text(this.title)
                .fontSize(this.dim() === 4 ? 28 : 20)
                .fontWeight(600)
                .fontColor(TITLE_COLOR)
                .width('100%')
                .textAlign(TextAlign.Center)
                .maxFontSize(this.dim() === 4 ? 28 : 20)
                .minFontSize(12)
                .maxLines(3)
              if (this.mode === 'word' && this.phonetic.length > 0) {
                this.phoneticRow(false, 10)
              }
              Blank()
              Text('点击查看答案')
                .fontSize(this.dim() === 4 ? 12 : 11)
                .fontColor(SUB_COLOR)
                .width('100%')
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .layoutWeight(1)
            .onClick(() => {
              if (this.face === 'double' && this.flipped !== 'y') {
                this.sendFlip();
              }
            })
          }

          if (this.showBack()) {
            // 评分按钮固定高度（2×4:44 / 4×4:56）——内容区 List 已 layoutWeight 隔离，物理上不可能被挤出
            Row({ space: 6 }) {
              if (this.dim() === 4) {
                this.rateButton('生疏', '几乎想不起来', this.hardEta, 'hard', HARD_COLOR, HARD_BG, 56, 14, 10, 11, true)
                this.rateButton('尚可', '回忆有点费劲', this.goodEta, 'good', GOOD_COLOR, GOOD_BG, 56, 14, 10, 11, true)
                this.rateButton('熟知', '一眼就能反应', this.easyEta, 'easy', EASY_COLOR, EASY_BG, 56, 14, 10, 11, true)
              } else {
                this.rateButton('生疏', '', this.hardEta, 'hard', HARD_COLOR, HARD_BG, 44, 12, 9, 9, false)
                this.rateButton('尚可', '', this.goodEta, 'good', GOOD_COLOR, GOOD_BG, 44, 12, 9, 9, false)
                this.rateButton('熟知', '', this.easyEta, 'easy', EASY_COLOR, EASY_BG, 44, 12, 9, 9, false)
              }
            }
            .width('100%')
          }
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
    }

    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor(BG_CARD)
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }
}
