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

import { WordItem, WordBankStore, WordFolder, WordFolderNavStore, connectWordFolderNav, WordFolderTreeItem } from '../common/WordModel'; // ★ 0.222.19：单词库文件夹体系（对标知识库）
import { ApiConfig, connectApiConfig, LearnCountStore, connectLearnCount, PhoneticAccentStore, connectPhoneticAccent } from '../common/ChatModel'; // ★ 0.149：pronunciation TTS config (same PersistenceV2 instance as ChatPage)；★ 0.161：学习数量设置（同 PersistenceV2 实例，ChatPage 复习区共用）；★ 0.185.0：音标口音设置
import { connectWordBank, addWordToBank, removeWordFromBank, updateWordInBank, removeWordsByIds, genWordId, clearAllPhonetics, addWordFolder, renameWordFolder, deleteWordFolder, moveWords, copyWords, wordFolderChain, moveWordFolder, copyWordFolder, deleteWordFolderCascade, copyRootWordFolder, clearRootWordFolder } from '../utils/WordStoreUtil'; // ★ 0.185.0：clearAllPhonetics（切换口音清空音标）；★ 0.222.19：单词库文件夹 CRUD + 单词移动/复制
// ★ 0.208.0：单词库 DagPack 导入导出（只走 DagPack——用户拍板不做 Anki/表格）
import { DagPack, buildWordPack, packToJson, parseDagPack, PackWord } from '../utils/PackUtil';
import { readTextFile } from '../utils/ImportUtil';
import { fileIo, picker } from '@kit.CoreFileKit';
import { AppStorageV2 } from '@kit.ArkUI'; // ★ 0.219.2：视图模式 store（跨页面记忆）
import { track } from '../utils/TrackUtil';
import { formatNextReviewLabel } from '../utils/MemoryAlgorithm'; // ★ 0.187.0：下次复习时间标签（记忆算法）
import { localTts, EnVoiceStatus } from '../utils/LocalTtsEngine'; // ★ 0.189.1：发音语音包管理（listVoices 状态查询 + downloadVoice 应用内下载）
import { wordSpeaker, showAccentDialogs } from '../utils/WordSpeaker'; // ★ 0.149：word pronunciation singleton；★ 0.189.2：口音提示弹窗工厂共用
import intl from '@ohos.intl'; // ★ 0.195.0：字母排序 Collator（zh：英文 A-Z + 中文按拼音统一比较；本 SDK 的 @kit.ArkTS 未导出 intl，走 @ohos.intl——measure 同款坑）
import { WindowMode, connectWindowMode } from '../common/WindowMode'; // ★ 0.196.4：窗口宽度模式共享真相源（分屏/悬浮窗切手机布局）
import deviceInfo from '@ohos.deviceInfo'; // ★ 0.218.8：设备类型三档（PC 窄窗保持网格的 deviceType 判定，复刻 ChatPage isPcDevice 先例）
// ★ 0.183.0：UI 收敛到 DesignTokens（UI_GUIDELINES 唯一真相源；v0.166.3 锁暗色后 isDark 三元为死代码，全部清除）
  import { BG_APP, BG_CANVAS, TEXT_PRIMARY, TEXT_SECONDARY, TEXT_TERTIARY, SURFACE_NODE, SURFACE_HOVER, SURFACE_SOFT, BRAND_PRIMARY, BRAND_SECONDARY, DANGER, OVERLAY, STROKE_CARD, RADIUS_CONTROL, RADIUS_NAV, FONT_SIZE_SCREEN_TITLE } from '../common/DesignTokens'; // ★ 0.191.0：加 SURFACE_HOVER（排序按钮激活态底色）
import { AppSideBar } from './AppSideBar'; // ★ 0.222.19：手机单词库页边栏抽屉（复用共享边栏，长按文件夹=6 项菜单）
import { connectGlobalSettingsShared } from './GlobalSettingsDialog'; // ★ 0.230.0：返回键优先关设置弹窗
import { FoldChevron } from './FoldChevron'; // ★ 0.237.0：全项目唯一折叠指示器（军令统一）
const TREE_CELL: number = 14; // ★ 0.222.19：树形连接线每层缩进宽度（vp，与知识库同款）

// ★ 0.219.2：单词库视图模式（AppStorageV2 共享 @Trace grid）——gridMode 从 @Local 改挂共享 store：
//   页面组件销毁重建（切其他页面再回来）gridMode 不再还原成横条（用户实测反馈"要有这个记忆"）；
//   AppStorageV2 会话级共享（跨页面保持；重启恢复默认横条可接受）
@ObservedV2
export class WordViewModeStore {
  @Trace grid: boolean = false;
}

export function connectWordViewMode(): WordViewModeStore {
  return AppStorageV2.connect(WordViewModeStore, 'word-view-mode', () => new WordViewModeStore()) as WordViewModeStore;
}

@ComponentV2
export struct WordBankPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  wordBank: WordBankStore = connectWordBank(); // isolated PersistenceV2 instance
  apiConfig: ApiConfig = connectApiConfig(); // ★ 0.149：TTS config for pronunciation
  viewMode: WordViewModeStore = connectWordViewMode(); // ★ 0.219.2：视图模式跨页面记忆
  // ── ★ 0.222.19：文件夹体系（对标知识库 anything）状态 ──
  //   folderId 迁 WordFolderNavStore（AppStorageV2 共享 @Trace）——边栏文件夹树与页内视图同源同步
  @Local wbFolderNav: WordFolderNavStore = connectWordFolderNav(); // 挂 @Local（@ObservedV2 实例须挂 @Local 才可靠响应 @Trace）
  @Local sidebarVisible: boolean = false; // 手机单词库页边栏抽屉开关

  // ★ 0.148: search / sort state
  @Local searchKeyword: string = '';
  @Local sortMode: number = 0; // ★ 0.191.0：排序 4 态——0=最新↓（创建降序，默认）1=最新↑（创建升序）2=需复习↑（复习升序）3=需复习↓（复习降序）；两按钮独立，再点同按钮切倒序
  @Local sortMenuVisible: boolean = false; // ★ 0.218.3 用户拍板：三排序按钮合并为一个「排序」入口——点击弹三选项（最新/需复习/字母），点选项只切排序**不收起**（用户可连续切换），点遮罩才收起
  // ★ 0.219.2：gridMode 已迁移至 viewMode.grid（AppStorageV2 共享 store，声明在组件外）——跨页面记忆
  @Local gridCols: number = 5; // ★ 0.218.8：网格列数随容器宽连续自适应（0.218.7 floor 170vp→0.218.8 round 均衡过渡——用户拍板"不要固定死档"，格宽在进位间连续缩放）
  @Local gridGap: number = 12; // ★ 0.218.8 用户拍板"间距跟着屏幕大小来排列"——间距随格宽连续缩放（8~14 连续区间）

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

  // ── ★ 0.222.19：文件夹弹窗态（对标知识库 KnowledgeBankPage）──
  @Local folderDialogVisible: boolean = false;  // 新建/重命名共用弹窗
  @Local createMenuVisible: boolean = false;    // PC 右键/Pad 长按创建菜单开关
  @Local plusMenuVisible: boolean = false;      // ★ 0.239.0：+ 菜单 bindPopup 开关（系统 bindMenu 换双库统一规格）
  @Local folderDialogIsRename: boolean = false;
  @Local folderDialogTargetId: string = '';
  @Local folderDialogName: string = '';
  @Local folderPickerVisible: boolean = false;  // 移动/复制目标选择弹窗
  @Local moveOrCopyMode: string = 'move';       // 'move' | 'copy'
  @Local pickerCollapsedFolderIds: string[] = []; // 目标选择器文件夹折叠状态

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

  /** ★ 0.218.8 设备三档判定（复刻 ChatPage isPcDevice 先例）：明确移动设备（phone/tablet/tv/car/
   * wearable）之外全算 PC 档——**PC 窗口拖到多窄都是 PC 档**（deviceType 是设备属性与窗口无关），
   * 用户拍板"PC 窗口缩到手机一样宽也按 PC 规矩走"（网格视图在 PC 窄窗下保持，不退化手机横条） */
  isPcDevice(): boolean {
    const t = deviceInfo.deviceType;
    return t !== 'phone' && t !== 'tablet' && t !== 'tv' && t !== 'car' && t !== 'wearable';
  }

  // ── ★ 0.240.0：手机端搜索栏滚动隐藏（用户拍板「上滑收起/下滑呼回」，与知识库同款）──
  // 宽屏（isTablet || isPcDevice）搜索栏常驻：渲染条件兜底 + onDidScroll 直接短路（PC 窗口拖窄误收后拖宽也能自愈）
  @Local searchBarVisible: boolean = true;
  private listScroller: Scroller = new Scroller();
  private scrollAccum: number = 0; // 同方向累计量（≥10vp 才收/放，防轻蹭抖动）
  private scrollDir: number = 0;   // 0=无 / 1=上滑（收） / -1=下滑（放）；方向反转即清零重计

  // ★ 0.240.0：手机端搜索栏滚动隐藏防抖逻辑（onDidScroll 每 tick 调用，纯轻量计算）——
  //   上滑累计 >10vp 收起 / 下滑累计 >10vp 呼回 / 方向反转清零重计 / 滚回顶部（≤0.5vp）强制显示
  handleSearchScroll(offset: number): void {
    if (this.isTablet || this.isPcDevice()) {
      if (!this.searchBarVisible) {
        this.searchBarVisible = true;
      }
      return;
    }
    if (this.listScroller.currentOffset().yOffset <= 0.5) {
      this.scrollAccum = 0;
      this.scrollDir = 0;
      if (!this.searchBarVisible) {
        this.searchBarVisible = true;
      }
      return;
    }
    if (offset === 0) {
      return;
    }
    const dir: number = offset > 0 ? 1 : -1;
    if (dir !== this.scrollDir) {
      this.scrollDir = dir;
      this.scrollAccum = 0;
    }
    this.scrollAccum += Math.abs(offset);
    if (this.scrollAccum >= 10) {
      this.scrollAccum = 0;
      if (dir > 0 && this.searchBarVisible) {
        this.searchBarVisible = false; // 直接赋值 + transition 动画（禁 animateTo 闭包——畅享90pro UI 不刷新雷）
      } else if (dir < 0 && !this.searchBarVisible) {
        this.searchBarVisible = true;
      }
    }
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
      // ★ 0.222.19：目录视图——无关键字只看当前文件夹（跨库找词走搜索）
      list = this.wordBank.words.filter((w: WordItem) => w.folderId === this.wbFolderNav.folderId);
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
      // ★ 0.222.19 fix：新单词归属当前文件夹（对标知识库 new KnowledgeCard(..., folderNav.folderId)）——
      //   此前漏传 folderId 致在文件夹内新建的单词全落根目录（用户实测）
      const item = new WordItem(word, fullName, phonetic, explain, '', 0, 0, 0, 0, 0, this.wbFolderNav.folderId);
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

  // ============================================================
  // ★ 0.222.19：手机边栏抽屉（复刻知识库 kbMobileDrawerLayer 范式）
  // ============================================================
  openSidebar(): void {
    if (this.sidebarVisible) {
      return;
    }
    this.sidebarVisible = true; // 直接赋值——animateTo 闭包内赋值真机不通知观察
  }

  closeSidebar(): void {
    if (!this.sidebarVisible) {
      return;
    }
    this.sidebarVisible = false; // 直接赋值（同 openSidebar 根因）
  }

  /** 手机抽屉导航（点导航项跳转+收抽屉；kind=''/wordbank/settings=只收抽屉） */
  onSidebarNav(kind: string): void {
    this.closeSidebar();
    if (kind === '' || kind === 'wordbank' || kind === 'settings') {
      return;
    }
    if (kind === 'canvas') {
      this.pathStack.replacePath({ name: 'BBTreeCanvas' });
      return;
    }
    const target = kind === 'knowledge' ? 'KnowledgeBankPage' : kind === 'review' ? 'ReviewPage' : kind === 'statistics' ? 'StatisticsPage' : kind === 'billing' ? 'BillingPage' : '';
    if (target !== '') {
      this.pathStack.pushPath({ name: target });
    }
  }

  // ============================================================
  // ★ 0.222.19：文件夹 / 移动复制 —— 方法集（对标知识库 anything 体系）
  // ============================================================

  /** 当前目录的子文件夹（新在前） */
  @Computed
  get currentFolders(): WordFolder[] {
    return this.wordBank.folders
      .filter((f: WordFolder): boolean => f.parentId === this.wbFolderNav.folderId)
      .sort((a: WordFolder, b: WordFolder) => b.createdAt - a.createdAt);
  }

  /** 当前目录名链（根→…→当前）——面包屑/导出命名用 */
  @Computed
  get currentChain(): WordFolder[] {
    return wordFolderChain(this.wordBank, this.wbFolderNav.folderId);
  }

  folderParentId(): string {
    const ch = this.currentChain;
    return ch.length > 0 ? ch[ch.length - 1].parentId : '';
  }

  openFolderRename(f: WordFolder): void {
    this.folderDialogIsRename = true;
    this.folderDialogTargetId = f.id;
    this.folderDialogName = f.name;
    this.folderDialogVisible = true;
  }

  confirmFolderDialog(): void {
    const nm = this.folderDialogName.trim();
    if (nm.length === 0) {
      this.showToast('名称不能为空');
      return;
    }
    // 边栏树右键「新建文件夹」——父级=右键的文件夹（folderActionId）
    if (this.wbFolderNav.folderAction === 'newfolder') {
      addWordFolder(this.wordBank, nm, this.wbFolderNav.folderActionId);
      this.wbFolderNav.folderAction = '';
      this.wbFolderNav.folderActionId = '';
      this.folderDialogVisible = false;
      return;
    }
    if (this.folderDialogIsRename) {
      renameWordFolder(this.wordBank, this.folderDialogTargetId, nm);
    } else {
      addWordFolder(this.wordBank, nm, this.wbFolderNav.folderId);
      const tp: Record<string, string> = {};
      track(this.getUIContext().getHostContext() as Context, 'folder_create', tp);
    }
    this.folderDialogVisible = false;
  }

  requestDeleteFolder(f: WordFolder): void {
    deleteWordFolder(this.wordBank, f.id);
    if (this.wbFolderNav.folderId === f.id) {
      this.wbFolderNav.folderId = this.folderParentId();
    }
    this.showToast(`已删除「${f.name}」——单词已移到上一级`);
  }

  /** folderPicker 标题（文件夹移动/复制 与 单词移动/复制 分流） */
  folderPickerTitle(): string {
    if (this.wbFolderNav.folderAction === 'move') {
      return '移动文件夹到…';
    }
    if (this.wbFolderNav.folderAction === 'copy') {
      return this.wbFolderNav.folderActionId === '' ? '复制根目录全部内容到…' : '复制文件夹到…';
    }
    return this.moveOrCopyMode === 'copy' ? `复制 ${this.selectedIds.length} 个到…` : `移动 ${this.selectedIds.length} 个到…`;
  }

  /** 按 id 取文件夹名 */
  folderNameById(folderId: string): string {
    const f = this.wordBank.folders.find((x: WordFolder): boolean => x.id === folderId);
    return f === undefined ? '' : f.name;
  }

  /** 移动/复制目标选择器的树形目录（DFS 层级 + 折叠 + 排除源文件夹） */
  folderPickerTreeItems(): WordFolderTreeItem[] {
    const out: WordFolderTreeItem[] = [];
    const walk = (parentId: string, depth: number, ancestorIds: string[], ancestorHasNext: boolean[]): void => {
      const all = this.wordBank.folders
        .filter((f: WordFolder): boolean => f.parentId === parentId)
        .sort((a: WordFolder, b: WordFolder): number => b.createdAt - a.createdAt);
      // 仅「移动」排除源文件夹自身（避免移到自己下面形成环）；「复制」全显示（含源自身/子孙）
      const kids = all.filter((f: WordFolder): boolean => !(this.wbFolderNav.folderAction === 'move' && f.id === this.wbFolderNav.folderActionId));
      for (let i = 0; i < kids.length; i++) {
        const isLast = i === kids.length - 1;
        out.push({ folder: kids[i], depth: depth, isLast: isLast, ancestorIds: ancestorIds, ancestorHasNext: ancestorHasNext });
        if (!this.isPickerCollapsed(kids[i].id)) {
          walk(kids[i].id, depth + 1, [...ancestorIds, kids[i].id], [...ancestorHasNext, !isLast]);
        }
      }
    };
    walk('', 0, [], []);
    return out;
  }

  /** 目标选择器里文件夹是否有子文件夹 */
  pickerHasChildren(folderId: string): boolean {
    for (let i = 0; i < this.wordBank.folders.length; i++) {
      if (this.wordBank.folders[i].parentId === folderId) {
        return true;
      }
    }
    return false;
  }

  /** 目标选择器文件夹是否折叠 */
  isPickerCollapsed(folderId: string): boolean {
    return this.pickerCollapsedFolderIds.indexOf(folderId) >= 0;
  }

  /** 切换目标选择器文件夹折叠（string[] 替换引用触发重渲染） */
  togglePickerCollapse(folderId: string): void {
    if (this.isPickerCollapsed(folderId)) {
      this.pickerCollapsedFolderIds = this.pickerCollapsedFolderIds.filter((id: string): boolean => id !== folderId);
    } else {
      this.pickerCollapsedFolderIds = [...this.pickerCollapsedFolderIds, folderId];
    }
  }

  /** 确认级联删除文件夹 */
  confirmFolderDelete(): void {
    const fid = this.wbFolderNav.folderActionId;
    const deleted = deleteWordFolderCascade(this.wordBank, fid);
    if (this.wbFolderNav.folderId === fid) {
      this.wbFolderNav.folderId = this.folderParentId();
    }
    this.wbFolderNav.folderAction = '';
    this.wbFolderNav.folderActionId = '';
    this.showToast(`已删除文件夹及 ${deleted} 个单词`);
  }

  /** 清空根目录（全部单词+全部文件夹；根目录「全部单词」入口保留） */
  confirmRootDelete(): void {
    const n = clearRootWordFolder(this.wordBank);
    this.wbFolderNav.folderAction = '';
    this.wbFolderNav.folderActionId = '';
    this.wbFolderNav.folderId = '';
    this.showToast(`已清空全部 ${n} 个单词与全部文件夹`);
  }

  /** 取消文件夹操作（关闭弹窗 + 清请求） */
  cancelFolderAction(): void {
    this.wbFolderNav.folderAction = '';
    this.wbFolderNav.folderActionId = '';
    this.wbFolderNav.folderActionName = '';
  }

  /** 确认重命名文件夹（边栏树触发） */
  confirmFolderRename(): void {
    const nm = this.wbFolderNav.folderActionName.trim();
    if (nm.length === 0) {
      this.showToast('名称不能为空');
      return;
    }
    renameWordFolder(this.wordBank, this.wbFolderNav.folderActionId, nm);
    this.wbFolderNav.folderAction = '';
    this.wbFolderNav.folderActionId = '';
    this.wbFolderNav.folderActionName = '';
  }

  /** 移动/复制确认（folderPicker 行点击） */
  confirmFolderTarget(folderId: string): void {
    // 文件夹移动/复制（边栏树右键触发）——与单词移动/复制分流
    if (this.wbFolderNav.folderAction === 'move' || this.wbFolderNav.folderAction === 'copy') {
      const fid = this.wbFolderNav.folderActionId;
      if (this.wbFolderNav.folderAction === 'copy') {
        let n = 0;
        if (fid === '') {
          if (folderId === '') {
            this.showToast('不能复制根目录到根目录');
            this.wbFolderNav.folderAction = '';
            this.wbFolderNav.folderActionId = '';
            this.folderPickerVisible = false;
            return;
          }
          n = copyRootWordFolder(this.wordBank, folderId);
          this.showToast(`已复制根目录全部内容（含 ${n} 个单词）`);
        } else {
          n = copyWordFolder(this.wordBank, fid, folderId);
          this.showToast(`已复制文件夹（含 ${n} 个单词）`);
        }
      } else {
        const ok = moveWordFolder(this.wordBank, fid, folderId);
        if (!ok) {
          this.showToast('不能移动到自身或其子文件夹');
          this.wbFolderNav.folderAction = '';
          this.wbFolderNav.folderActionId = '';
          this.folderPickerVisible = false;
          return;
        }
        this.showToast('已移动文件夹');
      }
      this.wbFolderNav.folderAction = '';
      this.wbFolderNav.folderActionId = '';
      this.folderPickerVisible = false;
      return;
    }
    const ids = [...this.selectedIds];
    if (this.moveOrCopyMode === 'copy') {
      const n = copyWords(this.wordBank, ids, folderId);
      const tp: Record<string, string> = {}; tp['count'] = `${n}`;
      track(this.getUIContext().getHostContext() as Context, 'word_copy', tp);
      this.showToast(`已复制 ${n} 个（新词从零复习）`);
    } else {
      moveWords(this.wordBank, ids, folderId);
      const tp: Record<string, string> = {}; tp['count'] = `${ids.length}`;
      track(this.getUIContext().getHostContext() as Context, 'word_move', tp);
      this.showToast(`已移动 ${ids.length} 个`);
    }
    this.folderPickerVisible = false;
    this.exitMultiSelect();
  }

  // ---- single delete (session-level no-remind) ----

  // ★ 0.218.3：排序选项菜单（bindPopup 自定义 builder）——无参 @Builder 内部直读 sortMode
  //   （0.190.1 铁律）；三项=最新/需复习/字母，各带当前方向箭头，激活项品牌紫高亮；
  //   点击只改 sortMode **不收起**（用户拍板：连续切换不退弹层，点遮罩才收）

  // ★ 0.239.0：+ 菜单（bindPopup 双库统一规格）——系统 bindMenu 换自定义弹层：字体/行距对齐系统
  //   菜单"舒服"观感（14fp/上下10左右14），配色改主题（SURFACE_NODE 底+紫字+STROKE_CARD 分隔线），
  //   宽度按最长项自适应收窄（系统菜单右侧大片留白就此根治）；placement BottomRight=按钮左下方；
  //   三项文字与 action 原样保留（新建/导入 DagPack/导出 DagPack）
  @Builder
  wbPlusMenuBuilder() {
    Column() {
      Text('新建单词')
        .fontSize(14)
        .fontColor(BRAND_SECONDARY)
        .padding({ top: 10, bottom: 10, left: 14, right: 14 })
        .onClick(() => {
          this.plusMenuVisible = false;
          this.openAddEditor();
        })
      Divider().color(STROKE_CARD)
      Text('导入 DagPack（单词包）')
        .fontSize(14)
        .fontColor(BRAND_SECONDARY)
        .padding({ top: 10, bottom: 10, left: 14, right: 14 })
        .onClick(() => {
          this.plusMenuVisible = false;
          this.pickWordPackFile();
        })
      Divider().color(STROKE_CARD)
      Text('导出 DagPack（整库单词）')
        .fontSize(14)
        .fontColor(BRAND_SECONDARY)
        .padding({ top: 10, bottom: 10, left: 14, right: 14 })
        .onClick(() => {
          this.plusMenuVisible = false;
          this.doExportWordPack();
        })
    }
    .width(210) // ★ 0.239.0：弹层定宽收窄（Divider 会把无约束 Column 撑满可用宽——最长项「导出 DagPack（整库单词）」≈195vp+余量）
    .alignItems(HorizontalAlign.Start)
  }

  // ★ 0.218.3：排序选项菜单（bindPopup 自定义 builder）——无参 @Builder 内部直读 sortMode；
  //   ★ 0.240.0：激活项补紫底（SURFACE_HOVER+radius 8）——UI_GUIDELINES 铁律「排序/筛选选中态统一品牌紫背景」，按钮图标化后弹层成为排序状态唯一可视位
  @Builder
  sortMenuBuilder() {
    Column() {
      Text(this.sortMode === 1 ? '最新 ↑' : '最新 ↓')
        .fontSize(14)
        .fontColor(this.sortMode === 0 || this.sortMode === 1 ? BRAND_SECONDARY : TEXT_PRIMARY)
        .backgroundColor(this.sortMode === 0 || this.sortMode === 1 ? SURFACE_HOVER : Color.Transparent)
        .borderRadius(8)
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ top: 12, bottom: 12, left: 16, right: 16 })
        .onClick(() => {
          this.sortMode = this.sortMode === 0 ? 1 : 0;
        })
      Divider().color(STROKE_CARD)
      Text(this.sortMode === 3 ? '需复习 ↓' : '需复习 ↑')
        .fontSize(14)
        .fontColor(this.sortMode === 2 || this.sortMode === 3 ? BRAND_SECONDARY : TEXT_PRIMARY)
        .backgroundColor(this.sortMode === 2 || this.sortMode === 3 ? SURFACE_HOVER : Color.Transparent)
        .borderRadius(8)
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ top: 12, bottom: 12, left: 16, right: 16 })
        .onClick(() => {
          this.sortMode = this.sortMode === 2 ? 3 : 2;
        })
      Divider().color(STROKE_CARD)
      Text(this.sortMode === 5 ? '字母 ↓' : '字母 ↑')
        .fontSize(14)
        .fontColor(this.sortMode === 4 || this.sortMode === 5 ? BRAND_SECONDARY : TEXT_PRIMARY)
        .backgroundColor(this.sortMode === 4 || this.sortMode === 5 ? SURFACE_HOVER : Color.Transparent)
        .borderRadius(8)
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ top: 12, bottom: 12, left: 16, right: 16 })
        .onClick(() => {
          this.sortMode = this.sortMode === 4 ? 5 : 4;
        })
    }
    .width(160)
  }

  // ★ 0.218.3：卡片滑动露出的回收站删除面板（左滑右滑同款，对齐知识库 0.212.2 终式：
  //   44×44 品牌紫圆钮+白 trash 图标 20，外容器满高 Center 露出区宽 72；点击走 requestDeleteWord
  //   原确认弹窗链路不直接删；多选中点击 guard 无动作）。swipeAction 场景内容静态，带参 @Builder
  //   无刷新风险（0.190.1 铁律针对需随状态变化的渲染）
  @Builder
  swipeDeletePanel(w: WordItem) {
    Row() {
      Column() {
        Image($r('app.media.trash'))
          .width(20)
          .height(20)
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor(BRAND_PRIMARY)
      .onClick(() => {
        if (!this.multiSelectMode) {
          this.requestDeleteWord(w);
        }
      })
    }
    .justifyContent(FlexAlign.Center)
    .width(72)
    .height('100%')
  }

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
      // ★ 0.222.19：手机端 ⇄ 改边栏图标（sidebar.svg，点击切出边栏抽屉）；宽屏保持 ⇄ 切知识库
      if (this.windowMode.isTablet) {
        Text('⇄')
          .fontSize(16)
          .fontColor(TEXT_TERTIARY)
          .padding({ left: 4, right: 4 })
          .margin({ right: 4 })
          .onClick(() => {
            this.pathStack.replacePath({ name: 'KnowledgeBankPage' });
          })
      } else {
        Image($r('app.media.sidebar'))
          .width(24)
          .height(24)
          .objectFit(ImageFit.Contain)
          .padding({ left: 4, right: 4 })
          .margin({ right: 4 })
          .onClick(() => {
            this.openSidebar();
          })
      }
      Text('单词库')
        .fontSize(FONT_SIZE_SCREEN_TITLE) // ★ 0.183.0：18→16 对齐 ScreenTitle 规范
        .fontWeight(600)
        .fontColor(TEXT_PRIMARY)
        .onClick(() => {
          if (this.windowMode.isTablet) {
            this.pathStack.replacePath({ name: 'KnowledgeBankPage' }); // ★ 0.195.0：标题也可点击切换（用户需求，与 ⇄ 同款）
          } else {
            this.openSidebar(); // ★ 0.222.19：手机点标题也切边栏（与边栏图标同款）
          }
        })
      Blank()
        .layoutWeight(1)
      // ★ 0.218.3 用户拍板：三排序按钮合并为一个「排序」入口——点击弹三选项（最新/需复习/字母）；
      //   点选项只切排序不收起（用户可连续切换，点遮罩才收）；
      //   ★ 0.240.0 用户拍板：紫底文字按钮（「最新 ↓」）→ sort.svg 图标按钮（顶栏全图标统一，与 grid/设置齿轮同规格 28×28）；
      //   当前排序状态不再印在按钮上，点开弹层看紫色高亮
      Row() {
        Image($r('app.media.sort'))
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .height(28)
      .width(28)
      .borderRadius(RADIUS_CONTROL)
      .backgroundColor(Color.Transparent)
      .margin({ right: 4 })
      .bindPopup(this.sortMenuVisible, {
          builder: this.sortMenuBuilder(),
          placement: Placement.Bottom,
          popupColor: SURFACE_NODE,
          radius: 12,
          mask: { color: 'rgba(0,0,0,0.3)' }, // 点遮罩自动收起
          onStateChange: (e: PopupStateChangeParam) => {
            this.sortMenuVisible = e.isVisible; // 遮罩关闭时同步状态，保证按钮可再次唤起
          }
        })
        .onClick(() => {
          this.sortMenuVisible = !this.sortMenuVisible;
        })
      // ★ 0.218.6 用户拍板：宽屏视图切换（四宫格图标=方块网格 / 默认横条）——仅宽屏显示入口，
      //   手机不做（用户"手机上现在的大小看着舒服，方块太拥挤"）
      // ★ 0.218.8：按钮条件扩为 isTablet || isPcDevice——PC 窗口拖窄穿过 600 断点后按钮仍在
      //   （deviceType 是设备属性与窗口无关），窄窗可随时切回横条；真机手机不渲染（既定设计）
      if (this.isTablet || this.isPcDevice()) {
        Row() {
          Image($r('app.media.grid'))
            .width(20)
            .height(20)
            .objectFit(ImageFit.Contain)
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .height(28)
        .width(28)
        .borderRadius(RADIUS_CONTROL)
        .backgroundColor(this.viewMode.grid ? SURFACE_HOVER : Color.Transparent)
        .margin({ right: 4 })
        .onClick(() => {
          this.viewMode.grid = !this.viewMode.grid;
        })
      }
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
        // ★ 0.239.0：系统 bindMenu → bindPopup 双库统一规格（与知识库 kbPlusMenu 同款：主题配色+
        //   宽度收窄+BottomRight 左下方弹出；字体行距对齐系统菜单观感——用户认可的"舒服"基准）
        Button('+')
          .fontSize(20)
          .height(40) // ★ 0.196.6：显式 40vp——导航栏统一规格（UI_GUIDELINES 10.2：以气泡页顶栏为基准）
          .backgroundColor(Color.Transparent)
          .fontColor(TEXT_PRIMARY)
          .padding({ left: 8, right: 8 })
          .bindPopup(this.plusMenuVisible, {
            builder: this.wbPlusMenuBuilder(),
            placement: Placement.BottomRight,
            popupColor: SURFACE_NODE,
            radius: 12,
            mask: { color: 'rgba(0,0,0,0.3)' },
            onStateChange: (e: PopupStateChangeParam) => {
              this.plusMenuVisible = e.isVisible;
            }
          })
          .onClick(() => {
            this.plusMenuVisible = !this.plusMenuVisible;
          })
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
  // ★ 0.230.0 B11 键盘适配：键盘触发系统级窗口 RESIZE（实测 app 高度 1840→1000px），弹窗下半+保存行
  //   整段出局渲染树=不可达——弹窗外包 Scroll+maxHeight 约束：窗口被压矮时弹窗收缩为可滚，保存滚动可达
  //   （固定底部版待弹窗体系统一迭代；0.229.26 审计 B11 实锤闭环）
  @Builder
  editorDialog() {
    Column() {
      Scroll() {
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
        Row({ space: 12 }) { // ★ 0.230.0：等宽铁律姿势（0.197.3——margin 参与 layoutWeight 分配会把保存挤窄 12vp，审计实锤差 29px；间隙一律 Row space）
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
            .onClick(() => {
              this.saveEditor();
            })
        }
        .width('100%')
        .margin({ top: 20 })
      }
      .width(this.isTablet ? 520 : '86%') // ★ 0.230.0：断点制对齐（原裸 86%——0.201.2 改造漏网，0.229.26 审计实锤 784vp 超宽）
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
      .padding(20)
      }
      .constraintSize({ maxHeight: '96%' })
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
          Image(this.deleteConfirmNoRemind ? $r('app.media.checkbox_on') : $r('app.media.checkbox_off')) // ★ 0.218.6：☑/☐ 换 svg（0.212.0 漏网统一）
            .width(20)
            .height(20)
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
      // ★ 0.218.4 用户拍板：删除确认弹窗对齐知识库（PC 上 86% 太宽）——确认类对话框 400 定式
      .width(this.isTablet ? 400 : '86%')
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
      // ★ 0.218.4：批量删除确认同属确认类对话框——400 定式（对齐 UI_GUIDELINES 六-12）
      .width(this.isTablet ? 400 : '86%')
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
      .padding(20)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(OVERLAY)
  }

  // ★ 0.222.19：PC 右键/Pad 长按创建菜单（两项：新单词/新文件夹）——无参 @Builder 直读状态
  @Builder
  wbCreateMenuBuilder() {
    if (!this.multiSelectMode) {
      Column() {
        Text('创建新单词')
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .width('100%')
          .textAlign(TextAlign.Start)
          .padding({ top: 12, bottom: 12, left: 16, right: 16 })
          .onClick(() => {
            this.createMenuVisible = false;
            this.openAddEditor();
          })
        Divider().color(STROKE_CARD)
        Text('创建新文件夹')
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .width('100%')
          .textAlign(TextAlign.Start)
          .padding({ top: 12, bottom: 12, left: 16, right: 16 })
          .onClick(() => {
            this.createMenuVisible = false;
            this.folderDialogVisible = true;
            this.folderDialogIsRename = false;
          })
      }
      .width(160)
    }
  }

  @Builder
  folderDialog() {
    Column() {
      Column() {
        Text(this.folderDialogIsRename ? '重命名文件夹' : '新建文件夹')
          .fontSize(16)
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
        TextInput({ text: this.folderDialogName, placeholder: '文件夹名称' })
          .fontSize(14)
          .height(40)
          .margin({ top: 12 })
          .padding({ left: 10, right: 10 })
          .backgroundColor(SURFACE_SOFT)
          .borderRadius(8)
          .onChange((v: string) => {
            this.folderDialogName = v;
          })
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .backgroundColor(SURFACE_SOFT)
            .fontColor(TEXT_SECONDARY)
            .onClick(() => {
              this.folderDialogVisible = false;
              this.cancelFolderAction();
            })
          Button('确定')
            .layoutWeight(1)
            .backgroundColor(BRAND_PRIMARY)
            .fontColor(Color.White)
            .onClick(() => {
              this.confirmFolderDialog();
            })
        }
        .margin({ top: 14 })
      }
      .width(this.isTablet ? 520 : '86%')
      .padding(20)
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(OVERLAY)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.folderDialogVisible = false;
      this.cancelFolderAction();
    })
  }

  // ★ 0.222.19：文件夹删除确认弹窗（边栏树右键「删除」）
  @Builder
  folderDeleteConfirmDialog() {
    Column() {
      Column() {
        Text(this.wbFolderNav.folderActionId === '' ? '清空根目录「全部单词」' : `删除「${this.folderNameById(this.wbFolderNav.folderActionId)}」`)
          .fontSize(16)
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
        Text(this.wbFolderNav.folderActionId === '' ? '将清空根目录下所有单词和文件夹，根目录入口将保留。不可恢复。' : '将删除该文件夹及其中所有单词和子文件夹，不可恢复。')
          .fontSize(13)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 10 })
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .backgroundColor(SURFACE_SOFT)
            .fontColor(TEXT_SECONDARY)
            .onClick(() => {
              this.cancelFolderAction();
            })
          Button('删除')
            .layoutWeight(1)
            .backgroundColor(DANGER)
            .fontColor(Color.White)
            .onClick(() => {
              this.wbFolderNav.folderActionId === '' ? this.confirmRootDelete() : this.confirmFolderDelete();
            })
        }
        .margin({ top: 16 })
      }
      .width(this.isTablet ? 400 : '86%')
      .padding(20)
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(OVERLAY)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.cancelFolderAction();
    })
  }

  // ★ 0.222.19：文件夹重命名弹窗（边栏树右键「重命名」）
  @Builder
  renameFolderDialog() {
    Column() {
      Column() {
        Text('重命名文件夹')
          .fontSize(16)
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
        TextInput({ text: this.wbFolderNav.folderActionName, placeholder: '文件夹名称' })
          .fontSize(14)
          .height(40)
          .margin({ top: 12 })
          .padding({ left: 10, right: 10 })
          .backgroundColor(SURFACE_SOFT)
          .borderRadius(8)
          .onChange((v: string) => {
            this.wbFolderNav.folderActionName = v;
          })
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .backgroundColor(SURFACE_SOFT)
            .fontColor(TEXT_SECONDARY)
            .onClick(() => {
              this.cancelFolderAction();
            })
          Button('确定')
            .layoutWeight(1)
            .backgroundColor(BRAND_PRIMARY)
            .fontColor(Color.White)
            .onClick(() => {
              this.confirmFolderRename();
            })
        }
        .margin({ top: 14 })
      }
      .width(this.isTablet ? 520 : '86%')
      .padding(20)
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(OVERLAY)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.cancelFolderAction();
    })
  }

  @Builder
  folderPickerDialog() {
    Column() {
      Column() {
        Text(this.folderPickerTitle())
          .fontSize(16)
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
        Scroll() {
          Column() {
            Row() {
              Text('根目录')
                .fontSize(13)
                .fontColor(TEXT_PRIMARY)
                .layoutWeight(1)
              Text(`${this.wordBank.words.length}`)
                .fontSize(10)
                .fontColor(TEXT_TERTIARY)
            }
            .width('100%')
            .height(32)
            .padding({ left: 8, right: 8 })
            .borderRadius(RADIUS_NAV)
            .onClick(() => {
              this.confirmFolderTarget('');
            })
            ForEach(this.folderPickerTreeItems(), (item: WordFolderTreeItem) => {
              Row({ space: 6 }) {
                // 静态经典树形连接线（与边栏同款，弹窗无路径高亮）
                Row() {
                  ForEach(item.ancestorHasNext, (cont: boolean, k: number) => {
                    Stack({ alignContent: Alignment.Top }) {
                      if (cont) {
                        Column()
                          .width(1)
                          .height('100%')
                          .backgroundColor(STROKE_CARD)
                      }
                    }
                    .width(TREE_CELL)
                    .height('100%')
                  }, (cont: boolean, k: number) => `${k}_${cont}`)
                  Row() {
                    Stack({ alignContent: Alignment.TopEnd }) {
                      Column()
                        .width(1)
                        .height(item.isLast ? '50%' : '100%')
                        .backgroundColor(STROKE_CARD)
                    }
                    .width('50%')
                    .height('100%')
                    Stack({ alignContent: Alignment.Center }) {
                      Row()
                        .width('100%')
                        .height(1)
                        .backgroundColor(STROKE_CARD)
                    }
                    .width('50%')
                    .height('100%')
                  }
                  .width(TREE_CELL)
                  .height('100%')
                }
                .height('100%')
                // ★ 0.237.0 军令：树行折叠三角字符 ▸/▾ → FoldChevron SVG；叶子行空占位同宽对齐
                if (this.pickerHasChildren(item.folder.id)) {
                  FoldChevron({ expanded: !this.isPickerCollapsed(item.folder.id) })
                    .onClick(() => {
                      this.togglePickerCollapse(item.folder.id);
                    })
                } else {
                  Row().width(12)
                }
                Text(item.folder.name)
                  .fontSize(13)
                  .fontColor(TEXT_PRIMARY)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .height(32)
              .padding({ left: 8, right: 8 })
              .borderRadius(RADIUS_NAV)
              .onClick(() => {
                this.confirmFolderTarget(item.folder.id);
              })
            }, (item: WordFolderTreeItem) => item.folder.id)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .margin({ top: 8 })
        .constraintSize({ maxHeight: 320 })
        Text('取消')
          .fontSize(13)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 10 })
          .onClick(() => {
            this.folderPickerVisible = false;
            this.cancelFolderAction();
          })
      }
      .width(this.isTablet ? 520 : '86%')
      .constraintSize({ maxHeight: '80%' })
      .padding(20)
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(OVERLAY)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.folderPickerVisible = false;
      this.cancelFolderAction();
    })
  }

  // ★ 0.222.19：手机单词库页边栏抽屉（条件渲染+transition，复刻知识库 kbMobileDrawerLayer）
  @Builder
  wbMobileDrawerLayer() {
    if (!this.windowMode.isTablet && this.sidebarVisible) {
      Stack({ alignContent: Alignment.TopStart }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.45)')
          .onClick(() => {
            this.closeSidebar();
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 220 }))
        Column() {
          AppSideBar({
            currentRoute: 'WordBankPage',
            onNavClick: (kind: string) => {
              this.onSidebarNav(kind);
            },
            onFolderClick: (folderId: string) => {
              this.closeSidebar();
            }
          })
        }
        .width(208)
        .height('100%')
        .transition(TransitionEffect.translate({ x: -208 }).animation({ duration: 220, curve: Curve.EaseOut }))
      }
      .width('100%')
      .height('100%')
    }
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          this.topBar()

          if (!this.multiSelectMode) {
            // ★ 0.148: search box + sort toggle (live filtering via @Computed)
            // ★ 0.240.0：手机端滚动隐藏——宽屏（isTablet/isPcDevice）常驻兜底；条件渲染 + transition（0.222.7/0.222.8 已验证范式）
            if (this.searchBarVisible || this.isTablet || this.isPcDevice()) {
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
              .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 })).animation({ duration: 200 }))
            }
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
              // ★ 0.222.19：批量移动/复制到文件夹（对齐知识库，单张=多选 1 张，交互统一）
              Button('移动')
                .fontSize(13)
                .fontColor(BRAND_SECONDARY)
                .backgroundColor(Color.Transparent)
                .padding({ left: 6, right: 6 })
                .margin({ left: 4 })
                .onClick(() => {
                  if (this.selectedIds.length === 0) {
                    this.showToast('先选中单词');
                    return;
                  }
                  this.moveOrCopyMode = 'move';
                  this.folderPickerVisible = true;
                })
              Button('复制')
                .fontSize(13)
                .fontColor(BRAND_SECONDARY)
                .backgroundColor(Color.Transparent)
                .padding({ left: 6, right: 6 })
                .onClick(() => {
                  if (this.selectedIds.length === 0) {
                    this.showToast('先选中单词');
                    return;
                  }
                  this.moveOrCopyMode = 'copy';
                  this.folderPickerVisible = true;
                })
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
          } else if (this.filteredWords.length === 0 && this.currentFolders.length === 0) {
            // ★ 0.222.19：目录空态（搜索无结果 / 空文件夹二合一文案）
            Column() {
              Text(this.searchKeyword.length > 0 ? '无匹配结果' : '此文件夹为空')
                .fontSize(16)
                .fontColor(TEXT_TERTIARY)
              Text(this.searchKeyword.length > 0 ? '换个关键词试试' : '点右上角 + 导入或新建')
                .fontSize(12)
                .fontColor(TEXT_TERTIARY)
                .margin({ top: 8 })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.viewMode.grid && (this.isTablet || this.isPcDevice())) {
            // ★ 0.218.8 用户拍板"PC 窗口缩到手机一样宽也按 PC 规矩走"：条件从 isTablet 改为
            //   gridMode && (isTablet || isPcDevice)——PC（2in1 等设备档）窗口多窄都保持网格；
            //   真机手机 gridMode 恒 false（切换按钮不渲染）永不进本分支（手机横条既定设计不变）
            // ★ 0.218.6：方块网格视图（仅宽屏可切入）——WaterFlow 瀑布流 5 等列，拖窗口大小自动整齐重排；
            //   网格卡交互=单击选中/双击编辑+长按多选（同横条）；滑动删除仅横条模式（网格下拖动与滑动冲突，
            //   删除走长按多选批量）
            // ★ 0.218.9 用户拍板（截图实锤"高度不统一+有重叠"）：瀑布流按内容自适应高度=行高参差
            //   +动态高度布局重叠——弃 WaterFlow 改 **Grid 等高网格**：GridItem 内卡片固定 150vp，
            //   全部格子完全一致（整齐即正义）；内容超出裁剪（explain 已 2 行省略，下方留白可接受）
            Grid() {
              ForEach(this.filteredWords, (w: WordItem) => {
                GridItem() {
                  Column() {
                    Row({ space: 6 }) {
                      Text(w.word)
                        .fontSize(15)
                        .fontWeight(600)
                        .fontColor(TEXT_PRIMARY)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                      if (this.multiSelectMode) {
                        Image(this.selectedIds.includes(w.id) ? $r('app.media.checkbox_on') : $r('app.media.checkbox_off'))
                          .width(18)
                          .height(18)
                      }
                    }
                    .width('100%')
                    if (w.fullName.length > 0) {
                      Text(w.fullName)
                        .fontSize(11)
                        .fontColor(BRAND_SECONDARY)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .margin({ top: 2 })
                    }
                    if (w.usPhonetic.length > 0) {
                      Text(w.usPhonetic)
                        .fontSize(11)
                        .fontColor(TEXT_TERTIARY)
                        .margin({ top: 2 })
                    }
                    Text(w.explain)
                      .fontSize(12)
                      .fontColor(TEXT_SECONDARY)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 2 })
                    Text(this.nextReviewLabel(w))
                      .fontSize(10)
                      .fontColor(this.nextReviewColor(w))
                      .margin({ top: 4 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')
                  .height(150) // ★ 0.218.9：固定格高——等高网格（瀑布流内容自适应高度=行高参差+重叠根因）
                  .padding(12)
                  .borderRadius(RADIUS_CONTROL)
                  .backgroundColor(SURFACE_NODE)
                  .borderColor(STROKE_CARD)
                  .borderWidth(1)
                  .onClick(() => {
                    this.onItemTap(w);
                  })
                  .gesture(
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
            .columnsTemplate(`repeat(${this.gridCols}, 1fr)`)
            .columnsGap(this.gridGap)
            .rowsGap(this.gridGap)
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 16, right: 16, top: 12 })
            .onAreaChange((_o: Area, n: Area) => {
              // ★ 0.218.8 用户拍板"不要固定，间距跟着屏幕大小来排列"——两处连续化：
              //   ①列数 floor→**round**（列数进位点更均衡，格宽在进位间的缩放更平滑）
              //   ②**间距随格宽连续缩放**（格宽 6% 区间 8~14vp：格子大间距大、格子小间距小）
              const availW = Number(n.width) - 32; // 减左右 padding 16×2
              if (availW > 0) {
                const cols = Math.max(2, Math.round(availW / 170));
                const cell = availW / cols;
                const gap = Math.min(14, Math.max(8, Math.round(cell * 0.06)));
                if (cols !== this.gridCols || gap !== this.gridGap) {
                  this.gridCols = cols;
                  this.gridGap = gap;
                }
              }
            })
          } else {
            List({ space: 8, scroller: this.listScroller }) { // ★ 0.240.0：挂 scroller（onDidScroll 里读 yOffset 判回顶）
              ForEach(this.filteredWords, (w: WordItem) => {
                ListItem() {
                  Row() {
                    if (this.multiSelectMode) {
                      // ★ 0.148: multi-select check indicator — an icon Text,
                      // NOT a Checkbox: the whole row handles tap-toggle and a
                      // real Checkbox would fire a second onChange
                      Image(this.selectedIds.includes(w.id) ? $r('app.media.checkbox_on') : $r('app.media.checkbox_off')) // ★ 0.218.6：☑/☐ 换 svg（0.212.0 漏网统一）
                        .width(20)
                        .height(20)
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
                    // ★ 0.218.3 用户拍板：常驻删除入口撤除（功能对齐知识库 0.212.x 终式）——
                    //   左滑/右滑露回收站圆钮面板（见 swipeDeletePanel），点击走原确认弹窗链路
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
                .swipeAction({
                  // ★ 0.218.3：左右滑露删除面板（对齐知识库 0.212.2 终式）；swipeAction 专属 ListItem（挂 Row 无效雷）；
                  //   箭头函数包 @Builder 调用（CustomBuilder 规范写法）
                  end: (): void => {
                    this.swipeDeletePanel(w)
                  },
                  start: (): void => {
                    this.swipeDeletePanel(w)
                  }
                })
              }, (w: WordItem) => w.id)
            }
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 16, right: 16, top: 12 })
            .onDidScroll((offset: number, state: ScrollState) => { // ★ 0.240.0：手机端搜索栏滚动隐藏（宽屏在方法内短路）
              if (state !== ScrollState.Idle) {
                this.handleSearchScroll(offset);
              }
            })
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
        // ★ 0.222.19：文件夹/移动复制弹窗（最顶层，对标知识库）
        if (this.folderDialogVisible || this.wbFolderNav.folderAction === 'newfolder') {
          this.folderDialog()
        }
        if (this.wbFolderNav.folderAction === 'newcard') {
          Column()
            .width(0)
            .height(0)
            .onAppear(() => {
              this.wbFolderNav.folderAction = '';
              this.wbFolderNav.folderActionId = '';
              this.openAddEditor();
            })
        }
        if (this.folderPickerVisible || this.wbFolderNav.folderAction === 'move' || this.wbFolderNav.folderAction === 'copy') {
          this.folderPickerDialog()
        }
        if (this.wbFolderNav.folderAction === 'delete') {
          this.folderDeleteConfirmDialog()
        }
        if (this.wbFolderNav.folderAction === 'rename') {
          this.renameFolderDialog()
        }
        // ★ 0.222.19：抽屉移入主 Column children 末尾（与正常工作的弹窗块同层）
        this.wbMobileDrawerLayer()
      }
      .backgroundColor(BG_CANVAS) // ★ 0.183.0：页面根底色补齐——原根容器未设底色透出窗口纯黑（实测 #000000），与首页 BG_APP/画布 BG_CANVAS 暗紫底不一致，统一应用底色
      // ★ 0.222.19：PC 右键 / Pad 长按空白 → 弹「创建新单词 / 创建新文件夹」菜单
      //   （bindContextMenu 跟随鼠标右键；bindPopup 供长按唤起；触屏设备 RightClick 响应=长按，双通道等效冗余）
      .bindContextMenu(this.wbCreateMenuBuilder, ResponseType.RightClick)
      .bindPopup(this.createMenuVisible, {
        builder: this.wbCreateMenuBuilder(),
        placement: Placement.Bottom,
        popupColor: SURFACE_NODE,
        radius: 12,
        mask: { color: 'rgba(0,0,0,0.3)' },
        onStateChange: (e: PopupStateChangeParam) => {
          this.createMenuVisible = e.isVisible;
        }
      })
      .gesture(
        LongPressGesture({ duration: 500 })
          .onAction(() => {
            if (deviceInfo.deviceType !== 'phone') { this.createMenuVisible = true; }
          })
      )
    }
    // ★ 0.159 pattern: hide the system title bar — the top bar is self-drawn
    .hideTitleBar(true)
    // ★ 0.148: back gesture closes dialogs / multi-select first, page last
    .onBackPressed(() => {
      // ★ 0.230.0：全局设置弹窗打开时返回键先关弹窗（共享真相源——修复仅画布页拦截的盲区，0.229.26 审计 B9 实锤）
      const gsShared = connectGlobalSettingsShared();
      if (gsShared.visible) {
        gsShared.closeReq++;
        return true;
      }
      // ★ 0.222.19：手机边栏抽屉开着时返回键先收抽屉
      if (this.sidebarVisible) {
        this.closeSidebar();
        return true;
      }
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
      // ★ 0.222.19：文件夹操作弹窗（移动/复制/删除/重命名）——返回键先关
      if (this.wbFolderNav.folderAction !== '') {
        this.cancelFolderAction();
        return true;
      }
      if (this.folderPickerVisible) {
        this.folderPickerVisible = false;
        return true;
      }
      if (this.folderDialogVisible) {
        this.folderDialogVisible = false;
        return true;
      }
      if (this.multiSelectMode) {
        this.exitMultiSelect();
        return true;
      }
      // ★ 0.222.19：非根目录时返回=回上一级（最后才退出页面）
      if (this.wbFolderNav.folderId.length > 0) {
        this.wbFolderNav.folderId = this.folderParentId();
        return true;
      }
      return false;
    })
  }
}
