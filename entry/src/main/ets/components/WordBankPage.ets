// ============================================================
// WordBankPage.ets — Word bank page (0.145 MVP / 0.148 CRUD upgrade)
// ============================================================
// Full entry management per the 0.148 spec:
//   - Add: "+" button at the top bar's right opens the editor dialog;
//     createTime is auto-recorded on save
//   - Edit: double-tap an entry (manual 300ms double-tap detection, so
//     single-tap stays zero-latency in multi-select mode) opens the
//     editor dialog pre-filled
//   - Delete (single): "×" on the entry's right; first tap shows a confirm
//     dialog with a "本次会话内不再提示" checkbox — session-level flag
//     held in page memory only, page rebuild (leave & re-enter) resets it
//   - Delete (batch): long-press an entry to enter multi-select; the top
//     bar "+" is replaced by the batch-delete button; EVERY batch delete
//     shows a confirm dialog (no no-remind option); select-all /
//     deselect-all supported; tap list blank area or "取消" to exit
//   - Search: full-field fuzzy match (word / fullName / usPhonetic /
//     explain), live filtering; clearing the box restores the full list
//   - Sort: createTime asc/desc toggle, default desc (newest first)
//   - Empty states: bank empty vs no search match are distinct
//   - Legacy entries saved before 0.148 get id/createTime back-filled in
//     aboutToAppear (array head = newer, display order preserved)
//
// Tech stack: HarmonyOS ArkUI V2 (@ComponentV2)
// ============================================================

import { WordItem, WordBankStore } from '../common/WordModel';
import { ApiConfig, connectApiConfig, LearnCountStore, connectLearnCount, PhoneticAccentStore, connectPhoneticAccent } from '../common/ChatModel'; // ★ 0.149：pronunciation TTS config (same PersistenceV2 instance as ChatPage)；★ 0.161：学习数量设置（同 PersistenceV2 实例，ChatPage 复习区共用）；★ 0.185.0：音标口音设置
import { connectWordBank, addWordToBank, removeWordFromBank, updateWordInBank, removeWordsByIds, genWordId, clearAllPhonetics } from '../utils/WordStoreUtil'; // ★ 0.185.0：clearAllPhonetics（切换口音清空音标）
// ★ 0.208.0：单词库 DagPack 导入导出（只走 DagPack——用户拍板不做 Anki/表格）
import { DagPack, buildWordPack, packToJson, parseDagPack, PackWord } from '../utils/PackUtil';
import { readTextFile } from '../utils/ImportUtil';
import { fileIo, picker } from '@kit.CoreFileKit';
import { track } from '../utils/TrackUtil';
import { formatNextReviewLabel } from '../utils/MemoryAlgorithm'; // ★ 0.187.0：下次复习时间标签（记忆算法）
import { localTts, EnVoiceStatus } from '../utils/LocalTtsEngine'; // ★ 0.189.1：发音语音包管理（listVoices 状态查询 + downloadVoice 应用内下载）
import { wordSpeaker, showAccentDialogs } from '../utils/WordSpeaker'; // ★ 0.149：word pronunciation singleton；★ 0.189.2：口音提示弹窗工厂共用
import intl from '@ohos.intl'; // ★ 0.195.0：字母排序 Collator（zh：英文 A-Z + 中文按拼音统一比较；本 SDK 的 @kit.ArkTS 未导出 intl，走 @ohos.intl——measure 同款坑）
import { WindowMode, connectWindowMode } from '../common/WindowMode'; // ★ 0.196.4：窗口宽度模式共享真相源（分屏/悬浮窗切手机布局）
// ★ 0.183.0：UI 收敛到 DesignTokens（UI_GUIDELINES 唯一真相源；v0.166.3 锁暗色后 isDark 三元为死代码，全部清除）
  import { BG_APP, BG_CANVAS, TEXT_PRIMARY, TEXT_SECONDARY, TEXT_TERTIARY, SURFACE_NODE, SURFACE_HOVER, SURFACE_SOFT, BRAND_PRIMARY, BRAND_SECONDARY, DANGER, OVERLAY, STROKE_CARD, RADIUS_CONTROL, RADIUS_NAV, FONT_SIZE_SCREEN_TITLE } from '../common/DesignTokens'; // ★ 0.191.0：加 SURFACE_HOVER（排序按钮激活态底色）

@ComponentV2
export struct WordBankPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  wordBank: WordBankStore = connectWordBank(); // isolated PersistenceV2 instance
  apiConfig: ApiConfig = connectApiConfig(); // ★ 0.149：TTS config for pronunciation

  // ★ 0.148: search / sort state
  @Local searchKeyword: string = '';
  @Local sortMode: number = 0; // ★ 0.191.0：排序 4 态——0=最新↓（创建降序，默认）1=最新↑（创建升序）2=需复习↑（复习升序）3=需复习↓（复习降序）；两按钮独立，再点同按钮切倒序

  // ★ 0.148: multi-select state (batch delete only)
  @Local multiSelectMode: boolean = false;
  @Local selectedIds: string[] = [];

  // ★ 0.148: session-level single-delete no-remind flag — page memory only,
  // never persisted; leaving the page rebuilds the component and resets it
  @Local skipDeleteConfirm: boolean = false;

  // ★ 0.148: manual double-tap detection (300ms window)
  @Local lastTapTime: number = 0;

  // ★ 0.148: entry-tap timestamp — ClickEvent has NO stopPropagation in
  // ArkUI, so the List blank-area handler distinguishes blank taps from
  // bubbled entry taps via a 200ms time window instead
  @Local lastEntryTapAt: number = 0;

  // ★ 0.148: editor dialog state (shared by add & edit)
  @Local editorVisible: boolean = false;
  @Local editorIsAdd: boolean = true;
  @Local editorId: string = '';
  @Local editorWord: string = '';
  @Local editorFullName: string = '';
  @Local editorPhonetic: string = '';
  @Local editorExplain: string = '';

  // ★ 0.148: single-delete confirm dialog state
  @Local deleteConfirmVisible: boolean = false;
  @Local deleteConfirmNoRemind: boolean = false;
  @Local pendingDeleteId: string = '';

  // ★ 0.148: batch-delete confirm dialog state (always shown, no no-remind)
  @Local batchConfirmVisible: boolean = false;

  // ★ 0.161: learn-count settings dialog state (top-bar ⚙ button, left of "+")
  learnCountStore: LearnCountStore = connectLearnCount(); // persisted learn count (default 2, range 1~20)
  @Local learnSettingsVisible: boolean = false;
  @Local learnCustomInput: string = '';  // free-input temp value (validated 1~20 on confirm)
  @Local learnInputError: string = '';   // free-input validation error text (empty = no error)

  // ★ 0.185.0: phonetic accent state (settings dialog section, same ⚙ dialog)
  phoneticAccentStore: PhoneticAccentStore = connectPhoneticAccent(); // persisted accent (false=美式 default, true=英式)
  @Local phoneticConfirmVisible: boolean = false; // switch confirm dialog (wipes phonetics on confirm)
  @Local pendingAccentBritish: boolean = false;   // accent to apply after confirm

  // ★ 0.189.1：发音语音包（en-US Laura）状态 + 下载进度（⚙ 弹窗「发音语音包」区）
  @Local voicePackStatus: string = 'unknown'; // EnVoiceStatus: unknown/installed/downloadable/none
  @Local voicePackDownloading: boolean = false;
  @Local voicePackProgress: string = '';

  // ★ 0.195.0：大屏断点（≥600vp）——顶栏左间距对齐气泡树信息条（28/14 双分支）
  // ★ 0.196.4：改读窗口宽度共享真相源（WindowMode）——分屏/悬浮窗实时切手机布局
  windowMode: WindowMode = connectWindowMode();
  @Computed get isTablet(): boolean {
    return this.windowMode.isTablet;
  }

  // ★ 0.148: back-fill id/createTime on entries saved before 0.148.
  // Array head = newer (head-insert history), so descending timestamps
  // keep the legacy display order stable under the default desc sort.
  aboutToAppear(): void {
    // ★ 0.196.4：isTablet 屏宽检测删除——改读 WindowMode 共享真相源（Index 根 onAreaChange 写入）
    const now = Date.now();
    for (let i = 0; i < this.wordBank.words.length; i++) {
      const w = this.wordBank.words[i];
      if (w.id.length === 0) {
        w.id = genWordId();
      }
      if (w.createTime === 0) {
        w.createTime = now - i * 1000;
      }
    }
  }

  // ★ 0.148: live-filtered + sorted view — full-field fuzzy match on
  // word / fullName / usPhonetic / explain, createTime asc/desc toggle.
  @Computed
  get filteredWords(): WordItem[] {
    const kw = this.searchKeyword.trim().toLowerCase();
    let list: WordItem[] = [];
    if (kw.length === 0) {
      list = [...this.wordBank.words];
    } else {
      list = this.wordBank.words.filter((w: WordItem) => {
        return w.word.toLowerCase().includes(kw)
          || w.fullName.toLowerCase().includes(kw)
          || w.usPhonetic.toLowerCase().includes(kw)
          || w.explain.toLowerCase().includes(kw);
      });
    }
    if (this.sortMode === 2) {
      // ★ 0.191.0：需复习升序（已到期/未学习 nextReviewAt=0 排最前）
      list.sort((a: WordItem, b: WordItem) => a.nextReviewAt - b.nextReviewAt);
    } else if (this.sortMode === 3) {
      // ★ 0.191.0：需复习降序（最晚复习的在前）
      list.sort((a: WordItem, b: WordItem) => b.nextReviewAt - a.nextReviewAt);
    } else if (this.sortMode === 4) {
      // ★ 0.195.0：字母升序——英文 A-Z、中文按拼音（intl.Collator zh 排序，首字符英文/中文统一处理）
      const coll = new intl.Collator('zh-CN');
      list.sort((a: WordItem, b: WordItem) => coll.compare(a.word, b.word));
    } else if (this.sortMode === 5) {
      // ★ 0.195.0：字母降序
      const coll = new intl.Collator('zh-CN');
      list.sort((a: WordItem, b: WordItem) => coll.compare(b.word, a.word));
    } else if (this.sortMode === 1) {
      // ★ 0.191.0：创建时间升序（最早在前）
      list.sort((a: WordItem, b: WordItem) => a.createTime - b.createTime);
    } else {
      // ★ 0.191.0：创建时间降序（最新在前，默认）
      list.sort((a: WordItem, b: WordItem) => b.createTime - a.createTime);
    }
    return list;
  }

  // ★ 0.187.0：下次复习标签——未学习 / 下次复习：已到期·N分钟后·N小时后·N天后·日期
  nextReviewLabel(w: WordItem): string {
    if (w.reviewCount === 0) {
      return '未学习';
    }
    // ★ 0.195.0：已到期标签简化——原「下次复习：已到期」易误解（用户实测），定稿三字「需复习」（nextReviewColor 自动标红）
    if (w.nextReviewAt <= Date.now()) {
      return '需复习';
    }
    return '下次复习：' + formatNextReviewLabel(w.nextReviewAt, Date.now());
  }

  // ★ 0.187.0：下次复习着色——已到期红 / 其余灰
  nextReviewColor(w: WordItem): string {
    if (w.reviewCount > 0 && w.nextReviewAt <= Date.now()) {
      return DANGER;
    }
    return TEXT_TERTIARY;
  }

  // toast 轻提示（showToast 可能抛异常，统一包裹消除编译告警，失败不影响主流程）
  showToast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
    } catch (e) {
      // toast 失败静默忽略
    }
  }

  // ★ 0.189.1：查询美式语音包状态（打开 ⚙ 时强制刷新）
  refreshVoicePackStatus(): void {
    localTts.queryEnVoiceStatus(true).then((status: EnVoiceStatus) => {
      this.voicePackStatus = status;
    });
  }

  // ★ 0.189.1：应用内下载美式语音包（downloadVoice 带进度回调）
  downloadVoicePack(): void {
    if (this.voicePackDownloading) {
      return;
    }
    this.voicePackDownloading = true;
    this.voicePackProgress = '';
    localTts.downloadEnVoice({
      onStart: () => {
        this.voicePackProgress = '下载中…';
      },
      onProgress: (info: string) => {
        this.voicePackProgress = info.length > 0 ? `下载中：${info}` : '下载中…';
      },
      onComplete: () => {
        this.voicePackDownloading = false;
        this.voicePackStatus = 'installed';
        this.voicePackProgress = '';
        this.showToast('美式语音包已就绪，单词发音启用真美式');
      },
      onCancelled: () => {
        this.voicePackDownloading = false;
        this.voicePackProgress = '';
      },
      onError: (code: number, message: string) => {
        this.voicePackDownloading = false;
        this.voicePackProgress = '';
        this.showToast(`语音包下载失败（${code}）：${message.substring(0, 60)}`);
      }
    });
  }

  // ★ 0.189.1：语音包状态文案（含下载进度态）
  voicePackLabel(): string {
    if (this.voicePackDownloading) {
      return this.voicePackProgress.length > 0 ? this.voicePackProgress : '下载中…';
    }
    if (this.voicePackStatus === 'installed') {
      return '✓ 已安装（真美式发音）';
    }
    if (this.voicePackStatus === 'downloadable') {
      return '未安装（当前用系统音色）';
    }
    if (this.voicePackStatus === 'none') {
      return '本机不支持（用系统音色）';
    }
    return '查询中…';
  }

  // ---- editor dialog (add & edit share it) ----

  // ============================================================
  // ★ 0.208.0：单词库 DagPack 导入导出
  // ============================================================

  /** 导出整库单词为 DagPack（wordbank 类，全量平铺） */
  async doExportWordPack(): Promise<void> {
    try {
      if (this.wordBank.words.length === 0) {
        this.showToast('单词库为空，无可导出');
        return;
      }
      const json = packToJson(buildWordPack(this.wordBank));
      const saver = new picker.DocumentViewPicker();
      const saveOpt = new picker.DocumentSaveOptions();
      saveOpt.newFileNames = ['DAGAI_单词库.dagpack'];
      const uris: string[] = await saver.save(saveOpt);
      if (uris.length === 0) {
        return;
      }
      const f = fileIo.openSync(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, json);
      fileIo.closeSync(f);
      const tp: Record<string, string> = {}; tp['kind'] = 'wordbank'; tp['count'] = `${this.wordBank.words.length}`;
      track(this.getUIContext().getHostContext() as Context, 'export_dagpack', tp);
      this.showToast(`已导出 ${this.wordBank.words.length} 个单词 → DagPack`);
    } catch (_e) {
      this.showToast('导出失败');
    }
  }

  /** 导入单词包：word 重词自动跳过（addWordToBank 自带幂等拒绝） */
  async pickWordPackFile(): Promise<void> {
    try {
      const doc = new picker.DocumentViewPicker();
      const selOpt = new picker.DocumentSelectOptions();
      selOpt.fileSuffixFilters = ['.dagpack', '.json'];
      selOpt.maxSelectNumber = 1;
      const uris: string[] = await doc.select(selOpt);
      if (uris.length === 0) {
        return;
      }
      const p = parseDagPack(readTextFile(uris[0]));
      if (p === undefined || p.kind !== 'wordbank' || p.words === undefined) {
        this.showToast('不是有效的 DagPack 单词包（wordbank v1）');
        return;
      }
      let added = 0;
      let skipped = 0;
      for (let i = 0; i < p.words.length; i++) {
        const pw: PackWord = p.words[i];
        if (pw.word.trim().length === 0) {
          continue;
        }
        const item = new WordItem(pw.word.trim(), pw.fullName, pw.usPhonetic, pw.explain, '', 0, 0, 0, 0, 0);
        if (addWordToBank(this.wordBank, item)) {
          added++;
        } else {
          skipped++; // 已存在同词——保留原词（含复习进度），幂等
        }
      }
      const tp: Record<string, string> = {}; tp['format'] = 'dagpack'; tp['count'] = `${added}`;
      track(this.getUIContext().getHostContext() as Context, 'batch_import', tp);
      this.showToast(`导入 ${added} 词${skipped > 0 ? `，跳过重复 ${skipped}` : ''}`);
    } catch (_e) {
      this.showToast('选文件失败');
    }
  }

  openAddEditor(): void {
    this.editorIsAdd = true;
    this.editorId = '';
    this.editorWord = '';
    this.editorFullName = '';
    this.editorPhonetic = '';
    this.editorExplain = '';
    this.editorVisible = true;
  }

  openEditEditor(w: WordItem): void {
    this.editorIsAdd = false;
    this.editorId = w.id;
    this.editorWord = w.word;
    this.editorFullName = w.fullName;
    this.editorPhonetic = w.usPhonetic;
    this.editorExplain = w.explain;
    this.editorVisible = true;
  }

  saveEditor(): void {
    const word = this.editorWord.trim();
    if (word.length === 0) {
      this.showToast('单词不能为空');
      return;
    }
    const fullName = this.editorFullName.trim();
    const phonetic = this.editorPhonetic.trim();
    const explain = this.editorExplain.trim();
    if (this.editorIsAdd) {
      // addWordToBank auto-fills id/createTime (createTime = creation record)
      const item = new WordItem(word, fullName, phonetic, explain);
      if (!addWordToBank(this.wordBank, item)) {
        this.showToast('该单词已在单词库中');
        return;
      }
    } else {
      if (!updateWordInBank(this.wordBank, this.editorId, word, fullName, phonetic, explain)) {
        this.showToast('该单词已在单词库中');
        return;
      }
    }
    this.editorVisible = false;
  }

  // ---- single delete (session-level no-remind) ----

  requestDeleteWord(w: WordItem): void {
    if (this.skipDeleteConfirm) {
      removeWordFromBank(this.wordBank, w.id);
      return;
    }
    this.pendingDeleteId = w.id;
    this.deleteConfirmNoRemind = false;
    this.deleteConfirmVisible = true;
  }

  confirmDeleteWord(): void {
    removeWordFromBank(this.wordBank, this.pendingDeleteId);
    if (this.deleteConfirmNoRemind) {
      this.skipDeleteConfirm = true; // session-level only, never persisted
    }
    this.deleteConfirmVisible = false;
  }

  // ---- multi-select (batch delete only) ----

  enterMultiSelect(id: string): void {
    this.multiSelectMode = true;
    this.selectedIds = [id];
  }

  exitMultiSelect(): void {
    this.multiSelectMode = false;
    this.selectedIds = [];
  }

  toggleSelect(id: string): void {
    if (this.selectedIds.includes(id)) {
      this.selectedIds = this.selectedIds.filter((x: string) => x !== id);
    } else {
      this.selectedIds = [...this.selectedIds, id];
    }
  }

  isAllSelected(): boolean {
    const list = this.filteredWords;
    if (list.length === 0 || this.selectedIds.length === 0) {
      return false;
    }
    for (let i = 0; i < list.length; i++) {
      if (!this.selectedIds.includes(list[i].id)) {
        return false;
      }
    }
    return true;
  }

  toggleSelectAll(): void {
    // Select-all operates on the CURRENT filtered view (what the user sees)
    if (this.isAllSelected()) {
      this.selectedIds = [];
    } else {
      this.selectedIds = this.filteredWords.map((w: WordItem) => w.id);
    }
  }

  requestBatchDelete(): void {
    if (this.selectedIds.length === 0) {
      this.showToast('请先选中要删除的条目');
      return;
    }
    this.batchConfirmVisible = true; // always confirmed, no no-remind option
  }

  confirmBatchDelete(): void {
    removeWordsByIds(this.wordBank, this.selectedIds);
    this.batchConfirmVisible = false;
    this.exitMultiSelect();
  }

  // ---- entry tap: multi-select toggle / manual double-tap to edit ----

  onItemTap(w: WordItem): void {
    // ClickEvent has no stopPropagation — record the tap time so the List's
    // blank-area handler can ignore this bubbled tap (200ms window)
    this.lastEntryTapAt = Date.now();
    if (this.multiSelectMode) {
      this.toggleSelect(w.id);
      return;
    }
    const now = Date.now();
    if (now - this.lastTapTime < 300) {
      this.lastTapTime = 0;
      this.openEditEditor(w); // double-tap → edit
    } else {
      this.lastTapTime = now;
    }
  }

  // ★ 0.159 pattern: self-drawn top bar with hideTitleBar(true) — a .title()
  // custom builder's content-area width reference includes the system
  // back-button slot and overflows the screen (proven on ChatPage).
  @Builder
  topBar() {
    Row() {
      // ★ 0.195.0：返回箭头删除（用户拍板：侧滑返回即可）——左上角改两库互切 ⇄（replacePath 不叠栈）
      Text('⇄')
        .fontSize(16)
        .fontColor(TEXT_TERTIARY)
        .padding({ left: 4, right: 4 })
        .margin({ right: 4 })
        .onClick(() => {
          this.pathStack.replacePath({ name: 'KnowledgeBankPage' });
        })
      Text('单词库')
        .fontSize(FONT_SIZE_SCREEN_TITLE) // ★ 0.183.0：18→16 对齐 ScreenTitle 规范
        .fontWeight(600)
        .fontColor(TEXT_PRIMARY)
        .onClick(() => {
          this.pathStack.replacePath({ name: 'KnowledgeBankPage' }); // ★ 0.195.0：标题也可点击切换（用户需求，与 ⇄ 同款）
        })
      Blank()
        .layoutWeight(1)
      // ★ 0.191.0 定稿：两个独立排序按钮（创建时间/下次复习时间各一个）——激活态紫字+底色；
      //   再点同按钮切倒序（最新↓↔最新↑ / 需复习↑↔需复习↓），箭头随方向实时变
      Button(this.sortMode === 1 ? '最新↑' : '最新↓')
        .fontSize(12)
        .height(28) // ★ 0.195.0：排序按钮高度缩小与右侧 ⚙ 图标对齐（用户实测太高）
        .backgroundColor(this.sortMode === 0 || this.sortMode === 1 ? SURFACE_HOVER : Color.Transparent)
        .fontColor(this.sortMode === 0 || this.sortMode === 1 ? BRAND_SECONDARY : TEXT_TERTIARY)
        .padding({ left: 8, right: 4 })
        .margin({ right: 2 })
        .onClick(() => {
          this.sortMode = this.sortMode === 0 ? 1 : 0;
        })
      Button(this.sortMode === 3 ? '需复习↓' : '需复习↑')
        .fontSize(12)
        .height(28) // ★ 0.195.0：高度对齐 ⚙
        .backgroundColor(this.sortMode === 2 || this.sortMode === 3 ? SURFACE_HOVER : Color.Transparent) // ★ 0.195.0 bugfix：>=2 → ===2||===3（字母模式 4/5 时误亮，用户实测互斥失效）
        .fontColor(this.sortMode === 2 || this.sortMode === 3 ? BRAND_SECONDARY : TEXT_TERTIARY)
        .padding({ left: 8, right: 4 })
        .margin({ right: 4 })
        .onClick(() => {
          this.sortMode = this.sortMode === 2 ? 3 : 2;
        })
      // ★ 0.195.0：字母排序（第三维度，用户需求）——英文 A-Z、中文按拼音（intl.Collator zh 统一比较首字符）；再点切倒序
      Button(this.sortMode === 5 ? '字母↓' : '字母↑')
        .fontSize(12)
        .height(28) // ★ 0.195.0：高度对齐 ⚙
        .backgroundColor(this.sortMode === 4 || this.sortMode === 5 ? SURFACE_HOVER : Color.Transparent) // ★ 0.195.0 bugfix：>=4 → ===4||===5（显式互斥）
        .fontColor(this.sortMode === 4 || this.sortMode === 5 ? BRAND_SECONDARY : TEXT_TERTIARY)
        .padding({ left: 8, right: 4 })
        .margin({ right: 4 })
        .onClick(() => {
          this.sortMode = this.sortMode === 4 ? 5 : 4;
        })
      // ★ 0.161: learn-count settings button — left of "+", visible in both normal & multi-select modes
      // ★ 0.195.0：⚙ emoji 换 settings.svg 单色图标（UI 统一——与边栏/ChatPage 顶栏同款）
      Row() {
        Image($r('app.media.settings'))
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
      }
      .padding({ left: 8, right: 4 })
      .margin({ right: 4 })
      .onClick(() => {
          // free-input box pre-fills only when current value is a custom one (> 3, quick options are 1/2/3)
          this.learnCustomInput = this.learnCountStore.learnCount > 2 ? `${this.learnCountStore.learnCount}` : ''; // ★ 0.195.0：>3→>2（快速项改 0/1/2，≥3 即自定义）
          this.learnInputError = '';
          this.learnSettingsVisible = true;
          this.refreshVoicePackStatus(); // ★ 0.189.1：打开 ⚙ 即查美式语音包状态
        })
      if (!this.multiSelectMode) {
        // ★ 0.208.0：+ 升级菜单（新建单词/单词库 DagPack 导入导出——用户拍板单词库只走 DagPack）
        Button('+')
          .fontSize(20)
          .height(40) // ★ 0.196.6：显式 40vp——导航栏统一规格（UI_GUIDELINES 10.2：以气泡页顶栏为基准）
          .backgroundColor(Color.Transparent)
          .fontColor(TEXT_PRIMARY)
          .padding({ left: 8, right: 8 })
          .bindMenu([
            { value: '新建单词', action: () => { this.openAddEditor(); } },
            { value: '导入 DagPack（单词包）', action: () => { this.pickWordPackFile(); } },
            { value: '导出 DagPack（整库单词）', action: () => { this.doExportWordPack(); } }
          ])
      } else {
        // ★ 0.148: multi-select replaces the add button with batch delete
        Button(`删除(${this.selectedIds.length})`)
          .fontSize(14)
          .fontColor(DANGER)
          .backgroundColor(Color.Transparent)
          .padding({ left: 8, right: 8 })
          .onClick(() => {
            this.requestBatchDelete();
          })
      }
    }
    .width('100%')
    .height(56) // ★ 0.196.7：顶栏 Row 40→56——height 含 padding，原 40+padding8/8 把内容区压到 24vp（顶栏比树页高 8vp，Pad 实测）；56=8padding+40内容+8padding 与树页外层 Column frame 等效，与 ChatPage 同步
    .padding({ left: this.isTablet ? 28 : 14, right: 14, top: 8, bottom: 8 }) // ★ 0.195.0：顶栏左/上间距以气泡树信息条为准（left 28/14 双分支 + top 8/right 14，与 ChatPage 同步）
  }

  // ★ 0.148: editor dialog — add & edit share it; tap the mask to dismiss
  @Builder
  editorDialog() {
    Column() {
      Column() {
        Text(this.editorIsAdd ? '新增单词' : '编辑单词')
          .fontSize(FONT_SIZE_SCREEN_TITLE)
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
        TextInput({ text: this.editorWord, placeholder: '单词（必填）' })
          .fontSize(14)
          .width('100%')
          .height(40)
          .margin({ top: 16 })
          .padding({ left: 12, right: 12 })
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
          .onChange((value: string) => {
            this.editorWord = value;
          })
        TextInput({ text: this.editorFullName, placeholder: '全称（缩略词选填，普通单词留空）' })
          .fontSize(14)
          .width('100%')
          .height(40)
          .margin({ top: 8 })
          .padding({ left: 12, right: 12 })
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
          .onChange((value: string) => {
            this.editorFullName = value;
          })
        TextInput({ text: this.editorPhonetic, placeholder: '音标（选填，如 /ˈhɑːrməni/）' })
          .fontSize(14)
          .width('100%')
          .height(40)
          .margin({ top: 8 })
          .padding({ left: 12, right: 12 })
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
          .onChange((value: string) => {
            this.editorPhonetic = value;
          })
        TextInput({ text: this.editorExplain, placeholder: '释义（选填）' })
          .fontSize(14)
          .width('100%')
          .height(40)
          .margin({ top: 8 })
          .padding({ left: 12, right: 12 })
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
          .onChange((value: string) => {
            this.editorExplain = value;
          })
        Row() {
          Button('取消')
            .fontSize(14)
            .fontColor(TEXT_SECONDARY)
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onClick(() => {
              this.editorVisible = false;
            })
          Button('保存')
            .fontSize(14)
            .fontColor(TEXT_PRIMARY)
            .backgroundColor(BRAND_PRIMARY)
            .borderRadius(RADIUS_CONTROL)
            .layoutWeight(1)
            .margin({ left: 12 })
            .onClick(() => {
              this.saveEditor();
            })
        }
        .width('100%')
        .margin({ top: 20 })
      }
      .width('86%')
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
      .padding(20)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(OVERLAY)
  }

  // ★ 0.161: learn-count settings dialog — 1 / 2 (default) / free input (1~20);
  // applies to BOTH review areas: AI-reply bottom review + extract-waiting review
  @Builder
  learnSettingsDialog() {
    Column() {
      Column() {
        Text('设置')
          .fontSize(FONT_SIZE_SCREEN_TITLE)
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
          .margin({ bottom: 12 })
        // ★ 0.189.2：排版重构——三区卡片化（SURFACE_SOFT 底 + RADIUS_CONTROL 圆角，对齐
        //   云同步状态卡规格；区块标题 14 主色半粗 + 描述 11 弱化），替代原先平铺堆叠的灰字
        // ── 卡片 1：复习显示数量 ──
        Column() {
          Text('复习显示数量')
            .fontSize(14)
            .fontWeight(600)
            .fontColor(TEXT_PRIMARY)
          Text('AI 回复底部复习区、提炼等待页每次展示的词条数')
            .fontSize(11)
            .fontColor(TEXT_TERTIARY)
            .margin({ top: 2 })
                    // ★ 0.195.0：布局统一（用户定稿「012+输入框」一行——与全局设置复习 Tab 完全同款）
          Row() {
            Button('0')
              .fontSize(14)
              .width(44)
              .height(40)
              .fontColor(this.learnCountStore.learnCount === 0 ? TEXT_PRIMARY : (TEXT_SECONDARY))
              .backgroundColor(this.learnCountStore.learnCount === 0 ? BRAND_PRIMARY : Color.Transparent)
              .borderRadius(RADIUS_CONTROL)
              .onClick(() => {
                this.learnCountStore.learnCount = 0;
                this.learnSettingsVisible = false;
              })
            Button('1')
              .fontSize(14)
              .width(44)
              .height(40)
              .fontColor(this.learnCountStore.learnCount === 1 ? TEXT_PRIMARY : (TEXT_SECONDARY))
              .backgroundColor(this.learnCountStore.learnCount === 1 ? BRAND_PRIMARY : Color.Transparent)
              .borderRadius(RADIUS_CONTROL)
              .margin({ left: 8 })
              .onClick(() => {
                this.learnCountStore.learnCount = 1;
                this.learnSettingsVisible = false;
              })
            Button('2')
              .fontSize(14)
              .width(44)
              .height(40)
              .fontColor(this.learnCountStore.learnCount === 2 ? TEXT_PRIMARY : (TEXT_SECONDARY))
              .backgroundColor(this.learnCountStore.learnCount === 2 ? BRAND_PRIMARY : Color.Transparent)
              .borderRadius(RADIUS_CONTROL)
              .margin({ left: 8 })
              .onClick(() => {
                this.learnCountStore.learnCount = 2;
                this.learnSettingsVisible = false;
              })
            TextInput({ text: this.learnCustomInput, placeholder: '0~20' })
              .fontSize(14)
              .layoutWeight(1)
              .height(40)
              .padding({ left: 12, right: 12 })
              .borderRadius(RADIUS_CONTROL)
              .backgroundColor(SURFACE_NODE)
              .type(InputType.Number)
              .margin({ left: 8 })
              .onChange((value: string) => {
                this.learnCustomInput = value;
                this.learnInputError = '';
              })
            Button('确定')
              .fontSize(14)
              .height(40)
              .fontColor(TEXT_PRIMARY)
              .backgroundColor(BRAND_PRIMARY)
              .borderRadius(RADIUS_CONTROL)
              .margin({ left: 8 })
              .padding({ left: 14, right: 14 })
              .onClick(() => {
                const n = parseInt(this.learnCustomInput, 10);
                if (!Number.isNaN(n) && n >= 0 && n <= 20) {
                  this.learnCountStore.learnCount = n;
                  this.learnSettingsVisible = false;
                } else {
                  this.learnInputError = '请输入 0~20 的整数';
                }
              })
          }
          .width('100%')
          .margin({ top: 10 })

          if (this.learnInputError.length > 0) {
            Text(this.learnInputError)
              .fontSize(12)
              .fontColor(DANGER)
              .margin({ top: 6 })
          }
        }
        .width('100%')
        .padding(12)
        .borderRadius(RADIUS_CONTROL)
        .backgroundColor(SURFACE_SOFT)
        .alignItems(HorizontalAlign.Start)
        // ── 卡片 2：音标口音（★ 0.185.0；切换需确认——清空现有音标，确认弹窗叠加于本弹窗之上）──
        Column() {
          Text('音标口音')
            .fontSize(14)
            .fontWeight(600)
            .fontColor(TEXT_PRIMARY)
          Text('划词查词生成音标的口音，切换将清空现有音标')
            .fontSize(11)
            .fontColor(TEXT_TERTIARY)
            .margin({ top: 2 })
          Row() {
            Button('美式（默认）')
              .fontSize(14)
              .fontColor(!this.phoneticAccentStore.british ? TEXT_PRIMARY : TEXT_SECONDARY)
              .backgroundColor(!this.phoneticAccentStore.british ? BRAND_PRIMARY : Color.Transparent)
              .borderRadius(RADIUS_CONTROL)
              .layoutWeight(1)
              .onClick(() => {
                if (!this.phoneticAccentStore.british) {
                  return; // already American — nothing to do
                }
                this.pendingAccentBritish = false;
                this.phoneticConfirmVisible = true;
              })
            Button('英式')
              .fontSize(14)
              .fontColor(this.phoneticAccentStore.british ? TEXT_PRIMARY : TEXT_SECONDARY)
              .backgroundColor(this.phoneticAccentStore.british ? BRAND_PRIMARY : Color.Transparent)
              .borderRadius(RADIUS_CONTROL)
              .layoutWeight(1)
              .margin({ left: 8 })
              .onClick(() => {
                if (this.phoneticAccentStore.british) {
                  return; // already British — nothing to do
                }
                this.pendingAccentBritish = true;
                this.phoneticConfirmVisible = true;
              })
          }
          .width('100%')
          .margin({ top: 10 })
        }
        .width('100%')
        .padding(12)
        .borderRadius(RADIUS_CONTROL)
        .backgroundColor(SURFACE_SOFT)
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 12 })
        // ── 卡片 3：发音语音包（★ 0.189.1：en-US Laura 状态 + 应用内下载）──
        Column() {
          Text('发音语音包')
            .fontSize(14)
            .fontWeight(600)
            .fontColor(TEXT_PRIMARY)
          Text('美式发音包 Laura：单词发音用真美式音色（系统语音包，免费离线）')
            .fontSize(11)
            .fontColor(TEXT_TERTIARY)
            .margin({ top: 2 })
          Row() {
            Text(this.voicePackLabel())
              .fontSize(13)
              .fontColor(this.voicePackStatus === 'installed' && !this.voicePackDownloading ? '#4CAF50' : TEXT_SECONDARY)
              .layoutWeight(1)
            if (this.voicePackStatus === 'downloadable' && !this.voicePackDownloading) {
              Button('下载')
                .fontSize(13)
                .fontColor(TEXT_PRIMARY)
                .backgroundColor(BRAND_PRIMARY)
                .borderRadius(RADIUS_CONTROL)
                .padding({ left: 14, right: 14 })
                .onClick(() => {
                  this.downloadVoicePack();
                })
            }
          }
          .width('100%')
          .margin({ top: 10 })
        }
        .width('100%')
        .padding(12)
        .borderRadius(RADIUS_CONTROL)
        .backgroundColor(SURFACE_SOFT)
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 12 })
        Button('关闭')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .backgroundColor(Color.Transparent)
          .width('100%')
          .margin({ top: 16 })
          .onClick(() => {
            this.learnSettingsVisible = false;
          })
      }
      .width('86%')
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
      .padding(20)
      .onClick(() => {}) // ★ 0.196.2：消费面板点击防冒泡到遮罩（ClickEvent 无 stopPropagation，空 handler 挡住）
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(OVERLAY)
    .onClick(() => {
      this.learnSettingsVisible = false; // ★ 0.196.2 用户拍板：点空白关闭（同「关闭」按钮=不保存退出）
    })
  }

  // ★ 0.185.0: phonetic accent switch confirm dialog — exact warning text
  // per spec: 切换音标后，原先的音标将会被删除
  @Builder
  phoneticConfirmDialog() {
    Column() {
      Column() {
        Text('切换音标口音？')
          .fontSize(FONT_SIZE_SCREEN_TITLE)
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
        Text('切换音标后，原先的音标将会被删除')
          .fontSize(13)
          .fontColor(TEXT_SECONDARY)
          .margin({ top: 12 })
        Row() {
          Button('取消')
            .fontSize(14)
            .fontColor(TEXT_SECONDARY)
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onClick(() => {
              this.phoneticConfirmVisible = false;
            })
          Button('确认切换')
            .fontSize(14)
            .fontColor(TEXT_PRIMARY)
            .backgroundColor(DANGER)
            .borderRadius(RADIUS_CONTROL)
            .layoutWeight(1)
            .margin({ left: 12 })
            .onClick(() => {
              this.confirmPhoneticSwitch();
            })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width('86%')
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
      .padding(20)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(OVERLAY)
  }

  // ★ 0.185.0: apply confirmed accent switch — persist, wipe existing
  // phonetics, close both dialogs, toast feedback
  confirmPhoneticSwitch(): void {
    this.phoneticAccentStore.british = this.pendingAccentBritish;
    clearAllPhonetics(this.wordBank);
    this.phoneticConfirmVisible = false;
    this.learnSettingsVisible = false;
    this.showToast(this.pendingAccentBritish ? '已切换为英式音标，原音标已清空' : '已切换为美式音标，原音标已清空');
  }

  // ★ 0.148: single-delete confirm dialog — with the session-level
  // "本次会话内不再提示" checkbox (spec 2.1.2)
  @Builder
  deleteConfirmDialog() {
    Column() {
      Column() {
        Text('确认删除该条目？')
          .fontSize(FONT_SIZE_SCREEN_TITLE)
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
        Row() {
          Text(this.deleteConfirmNoRemind ? '☑' : '☐')
            .fontSize(18)
            .fontColor(this.deleteConfirmNoRemind ? BRAND_PRIMARY : TEXT_TERTIARY)
            .onClick(() => {
              this.deleteConfirmNoRemind = !this.deleteConfirmNoRemind;
            })
          Text('本次会话内不再提示')
            .fontSize(13)
            .fontColor(TEXT_SECONDARY)
            .margin({ left: 6 })
            .onClick(() => {
              this.deleteConfirmNoRemind = !this.deleteConfirmNoRemind;
            })
        }
        .width('100%')
        .margin({ top: 16 })
        Row() {
          Button('取消')
            .fontSize(14)
            .fontColor(TEXT_SECONDARY)
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onClick(() => {
              this.deleteConfirmVisible = false;
            })
          Button('删除')
            .fontSize(14)
            .fontColor(TEXT_PRIMARY)
            .backgroundColor(DANGER)
            .borderRadius(RADIUS_CONTROL)
            .layoutWeight(1)
            .margin({ left: 12 })
            .onClick(() => {
              this.confirmDeleteWord();
            })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width('86%')
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
      .padding(20)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(OVERLAY)
  }

  // ★ 0.148: batch-delete confirm dialog — ALWAYS shown, no no-remind
  // checkbox (spec 2.3.3: every batch delete must be confirmed)
  @Builder
  batchConfirmDialog() {
    Column() {
      Column() {
        Text(`确认删除选中的 ${this.selectedIds.length} 项？`)
          .fontSize(FONT_SIZE_SCREEN_TITLE)
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
        Row() {
          Button('取消')
            .fontSize(14)
            .fontColor(TEXT_SECONDARY)
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onClick(() => {
              this.batchConfirmVisible = false;
            })
          Button('删除')
            .fontSize(14)
            .fontColor(TEXT_PRIMARY)
            .backgroundColor(DANGER)
            .borderRadius(RADIUS_CONTROL)
            .layoutWeight(1)
            .margin({ left: 12 })
            .onClick(() => {
              this.confirmBatchDelete();
            })
        }
        .width('100%')
        .margin({ top: 20 })
      }
      .width('86%')
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
      .padding(20)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(OVERLAY)
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          this.topBar()

          if (!this.multiSelectMode) {
            // ★ 0.148: search box + sort toggle (live filtering via @Computed)
            Row() {
              TextInput({ text: this.searchKeyword, placeholder: '搜索单词 / 音标 / 释义' })
                .fontSize(14)
                .layoutWeight(1)
                .height(40)
                .padding({ left: 12, right: 12 })
                .borderRadius(20)
                .backgroundColor(SURFACE_SOFT)
                .onChange((value: string) => {
                  this.searchKeyword = value;
                })
              if (this.searchKeyword.length > 0) {
                // Clear button — clearing restores the full list (spec 2.1.4)
                Text('×')
                  .fontSize(16)
                  .fontColor(TEXT_TERTIARY)
                  .margin({ left: 6 })
                  .onClick(() => {
                    this.searchKeyword = '';
                  })
               }
             }
            .width('100%')
            .padding({ left: 16, right: 16, top: 4, bottom: 4 })
          } else {
            // ★ 0.148: multi-select toolbar — select-all / counter / cancel
            Row() {
              Button(this.isAllSelected() ? '取消全选' : '全选')
                .fontSize(13)
                .fontColor(TEXT_SECONDARY)
                .backgroundColor(Color.Transparent)
                .padding({ left: 6, right: 6 })
                .onClick(() => {
                  this.toggleSelectAll();
                })
              Blank()
                .layoutWeight(1)
              Text(`已选 ${this.selectedIds.length} 项`)
                .fontSize(13)
                .fontColor(TEXT_TERTIARY)
              Button('取消')
                .fontSize(13)
                .fontColor(TEXT_SECONDARY)
                .backgroundColor(Color.Transparent)
                .padding({ left: 6, right: 6 })
                .margin({ left: 8 })
                .onClick(() => {
                  this.exitMultiSelect();
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 4, bottom: 4 })
          }

          if (this.wordBank.words.length === 0) {
            // Empty bank — guide the user to both entry points (0.148 adds manual add)
            Column() {
              Text('单词库为空')
                .fontSize(16)
                .fontColor(TEXT_TERTIARY)
              Text('点右上角 + 手动添加，或长按对话气泡选词翻译后加入')
                .fontSize(12)
                .fontColor(TEXT_TERTIARY)
                .margin({ top: 8 })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.filteredWords.length === 0) {
            // ★ 0.148: search matched nothing — distinct from the empty bank
            Column() {
              Text('无匹配结果')
                .fontSize(16)
                .fontColor(TEXT_TERTIARY)
              Text('换个关键词试试')
                .fontSize(12)
                .fontColor(TEXT_TERTIARY)
                .margin({ top: 8 })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            List({ space: 8 }) {
              ForEach(this.filteredWords, (w: WordItem) => {
                ListItem() {
                  Row() {
                    if (this.multiSelectMode) {
                      // ★ 0.148: multi-select check indicator — an icon Text,
                      // NOT a Checkbox: the whole row handles tap-toggle and a
                      // real Checkbox would fire a second onChange
                      Text(this.selectedIds.includes(w.id) ? '☑' : '☐')
                        .fontSize(20)
                        .fontColor(this.selectedIds.includes(w.id) ? BRAND_PRIMARY : TEXT_TERTIARY)
                        .margin({ right: 8 })
                    }
                    // Entry text block: word -> fullName -> usPhonetic -> explain
                    Column() {
                      Text(w.word)
                        .fontSize(16)
                        .fontWeight(600)
                        .fontColor(TEXT_PRIMARY)
                      if (w.fullName.length > 0) {
                        // Abbreviation full term — row not rendered when empty
                        Text(w.fullName)
                          .fontSize(13)
                          .fontColor(BRAND_SECONDARY)
                          .margin({ top: 2 })
                      }
                      if (w.usPhonetic.length > 0) {
                        Row() {
                          Text(w.usPhonetic)
                            .fontSize(13)
                            .fontColor(TEXT_TERTIARY)
                          // ★ 0.149：音标旁发音按钮——缩略词播全称（字母谁都会读）、普通词播单词本身（美式）；三态 🔈/⏳/🔊
                          // ★ 0.150：Button→Text——Button 默认高度（≈40vp）会撑高音标行（用户指出单词本行距变大），Text 无默认高度、行距还原
                          // ★ 0.195.0：喇叭三态 emoji（🔈⏳🔊 彩色）换单色 svg——形状即状态（cone 空闲/dots 合成中/waves 播放中）
                          Image(wordSpeaker.loadingWord === wordSpeaker.textFor(w.word, w.fullName) ? $r('app.media.speaker_loading') : (wordSpeaker.speakingWord === wordSpeaker.textFor(w.word, w.fullName) ? $r('app.media.speaker_playing') : $r('app.media.speaker')))
                            .width(13)
                            .height(13)
                            .objectFit(ImageFit.Contain)
                            .margin({ left: 6 })
                            .onClick(() => {
                              // ★ 0.189.2：口音提示改弹窗（英式无包/美式缺包——showAccentDialogs 共用工厂）
                              wordSpeaker.speak(wordSpeaker.textFor(w.word, w.fullName), showAccentDialogs(this.getUIContext()));
                            })
                        }
                        .margin({ top: 2 })
                      }
                      Text(w.explain)
                        .fontSize(13)
                        .fontColor(TEXT_SECONDARY)
                        .margin({ top: 2 })
                      // ★ 0.187.0：下次复习时间（未学习灰 / 已到期红 / 常规灰）
                      Text(this.nextReviewLabel(w))
                        .fontSize(11)
                        .fontColor(this.nextReviewColor(w))
                        .margin({ top: 2 })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    .onClick(() => {
                      this.onItemTap(w);
                    })

                    if (!this.multiSelectMode) {
                      // Single-delete button — hidden while multi-selecting
                      Button('×')
                        .fontSize(16)
                        .fontColor(DANGER)
                        .backgroundColor(Color.Transparent)
                        .padding({ left: 8, right: 8 })
                        .onClick(() => {
                          this.requestDeleteWord(w);
                        })
                    }
                  }
                  .width('100%')
                  .padding(12)
                  .borderRadius(RADIUS_CONTROL)
                  .backgroundColor(SURFACE_NODE) // ★ 0.183.0：卡片底对齐节点卡片规格（SURFACE_NODE + STROKE_CARD 描边）
                  .borderColor(STROKE_CARD)
                  .borderWidth(1)
                  .alignItems(VerticalAlign.Center)
                  .gesture(
                    // ★ 0.148: long-press enters multi-select (spec 2.3.1)
                    LongPressGesture()
                      .onAction(() => {
                        if (!this.multiSelectMode) {
                          this.enterMultiSelect(w.id);
                        }
                      })
                  )
                }
              }, (w: WordItem) => w.id)
            }
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 16, right: 16, top: 12 })
            .onClick(() => {
              // ★ 0.148: tapping the list's blank area exits multi-select.
              // Entry taps record lastEntryTapAt — a tap arriving here within
              // 200ms is a bubbled entry tap, not a blank-area tap.
              if (Date.now() - this.lastEntryTapAt < 200) {
                return;
              }
              if (this.multiSelectMode) {
                this.exitMultiSelect();
              }
            })
          }
        }
        .width('100%')
        .height('100%')

        // ★ 0.148: dialogs stacked above the page content
        if (this.editorVisible) {
          this.editorDialog()
        }
        if (this.deleteConfirmVisible) {
          this.deleteConfirmDialog()
        }
        if (this.batchConfirmVisible) {
          this.batchConfirmDialog()
        }
        // ★ 0.161: learn-count settings dialog
        if (this.learnSettingsVisible) {
          this.learnSettingsDialog()
        }
        // ★ 0.185.0: phonetic accent switch confirm dialog (stacks above settings)
        if (this.phoneticConfirmVisible) {
          this.phoneticConfirmDialog()
        }
      }
      .backgroundColor(BG_CANVAS) // ★ 0.183.0：页面根底色补齐——原根容器未设底色透出窗口纯黑（实测 #000000），与首页 BG_APP/画布 BG_CANVAS 暗紫底不一致，统一应用底色
    }
    // ★ 0.159 pattern: hide the system title bar — the top bar is self-drawn
    .hideTitleBar(true)
    // ★ 0.148: back gesture closes dialogs / multi-select first, page last
    .onBackPressed(() => {
      if (this.editorVisible) {
        this.editorVisible = false;
        return true;
      }
      if (this.deleteConfirmVisible) {
        this.deleteConfirmVisible = false;
        return true;
      }
      if (this.batchConfirmVisible) {
        this.batchConfirmVisible = false;
        return true;
      }
      // ★ 0.185.0: phonetic accent confirm closes before settings dialog
      if (this.phoneticConfirmVisible) {
        this.phoneticConfirmVisible = false;
        return true;
      }
      // ★ 0.161: learn-count settings dialog closes before multi-select
      if (this.learnSettingsVisible) {
        this.learnSettingsVisible = false;
        return true;
      }
      if (this.multiSelectMode) {
        this.exitMultiSelect();
        return true;
      }
      return false;
    })
  }
}
