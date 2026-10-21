// ============================================================
// KnowledgeBankPage.ets — Knowledge bank page (0.146 / 0.148 CRUD upgrade)
// ============================================================
// Full entry management per the 0.148 spec (same interaction set as the
// word bank page — the two pages are intentionally symmetric):
//   - Add: "+" button at the top bar's right opens the editor dialog
//     (title + definition); createdAt is auto-recorded on save
//   - Edit: double-tap an entry (manual 300ms double-tap detection) opens
//     the editor dialog pre-filled; ★ 0.160: the editor now manages the
//     card image too — add (gallery pick → base64), remove, replace, and
//     fullscreen preview on thumbnail tap; committed only on 保存
//   - Delete (single): "×" on the entry's right; first tap shows a confirm
//     dialog with a "本次会话内不再提示" checkbox — session-level flag,
//     page rebuild resets it
//   - Delete (batch): long-press to enter multi-select; top bar "+" is
//     replaced by the batch-delete button; every batch delete shows a
//     confirm dialog (no no-remind option); select-all / deselect-all;
//     tap list blank area or "取消" to exit
//   - Search: fuzzy match on title + definition, live filtering; clearing
//     the box restores the full list
//   - Sort: createdAt asc/desc toggle, default desc (newest first)
//   - Empty states: bank empty vs no search match are distinct
//   - No duplicate check anywhere — cards may legitimately share a title
//
// Tech stack: HarmonyOS ArkUI V2 (@ComponentV2)
// ============================================================

import { KnowledgeCard, KnowledgeBankStore, CardImportStore, connectCardImport, navBackToCanvas, parseTags, getCardImages, getTitleImages, KbFolderNavStore, connectKbFolderNav } from '../common/KnowledgeModel'; // ★ 0.200.0：卡片导入气泡；★ 0.202.0：parseTags；★ 0.202.1：getCardImages（多图兼容读取）
import { connectKnowledgeBank, addKnowledgeCard, removeKnowledgeCard, updateKnowledgeCard, removeCardsByIds } from '../utils/KnowledgeStoreUtil';
import { formatNextReviewLabel } from '../utils/MemoryAlgorithm'; // ★ 0.188.0：下次复习时间标签（记忆算法·知识库复刻）
import { KnowledgeCountStore, connectKnowledgeCount } from '../common/ChatModel'; // ★ 0.161.2: knowledge-card count settings (same PersistenceV2 instance as ChatPage review areas)
import { photoAccessHelper } from '@kit.MediaLibraryKit'; // ★ 0.160: editor image picking
import { fileIo, picker } from '@kit.CoreFileKit'; // ★ 0.160: read picked photo into base64；★ 0.207.0 picker：文档选/存（批量导入 CSV/TXT、导出 CSV）
import { image } from '@kit.ImageKit'; // ★ 0.211.1：选图压缩（9 张原图 base64 直接持久化=手机保存崩溃根因）
import { buffer } from '@kit.ArkTS'; // ★ 0.160: ArrayBuffer → base64
import { pasteboard } from '@kit.BasicServicesKit'; // ★ 0.283.0：卡片编辑弹窗 Ctrl+V 贴图（读剪贴板，READ_PASTEBOARD 已声明+Profile ACL 授权）
import { common, abilityAccessCtrl } from '@kit.AbilityKit'; // ★ 0.283.0：READ_PASTEBOARD user_grant 运行时授权（弹窗+被拒直达权限面板）
import { WindowMode, connectWindowMode } from '../common/WindowMode'; // ★ 0.196.4：窗口宽度模式共享真相源（分屏/悬浮窗切手机布局）
// ★ 0.183.0：UI 收敛到 DesignTokens（UI_GUIDELINES 唯一真相源；v0.166.3 锁暗色后 isDark 三元为死代码，全部清除）
import { RADIUS_CONTROL, RADIUS_NAV, FONT_SIZE_SCREEN_TITLE } from '../common/DesignTokens';
import { AppTheme, connectAppTheme } from '../common/AppTheme';
// ★ 0.207.0 anything 导入体系：文件夹 + CSV/TXT 批量导入 + 导出
import { KFolder, KFolderTreeItem } from '../common/KnowledgeModel';
import { addFolder, renameFolder, deleteFolder, moveCards, copyCards, folderChain, moveFolder, copyFolder, deleteFolderCascade, copyRootFolder, clearRootFolder } from '../utils/KnowledgeStoreUtil';
import { ImportRow, readTextFile, parseTextToRows, cardsToTxt, cardsToXlsxBuffer, readXlsxRows } from '../utils/ImportUtil'; // ★ 0.249.1：cardsToCsv 随 CSV 导出删除（用户拍板）
// ★ 0.207.1 DagPack：知识库模块化导出/导入（发送端粗粒度·接收端勾选细粒度——用户拍板）
import { DagPack, PackFolder, buildKnowledgePack, packToJson, parseDagPack, packChildFolders, packCardCount, packSubtreeRefs, packFolderPath } from '../utils/PackUtil';
// ★ 0.208.0 Anki：apkg 导入（知识库专用——单词库不���，用户拍板）
import { ApkgCard, ApkgParseResult, parseApkg } from '../utils/ApkgUtil';
import { ensureFolderPath } from '../utils/KnowledgeStoreUtil';
import { track } from '../utils/TrackUtil';
import { AppSideBar } from './AppSideBar'; // ★ 0.222.0 手机知识库页边栏抽屉（复用共享边栏，长按文件夹=6 项菜单）
import { requireLoginForCloud } from '../utils/HuaweiAccountUtil'; // ★ 0.248.3：导入导出守卫（上架合规——用户拍板必须登录）
import { deviceInfo } from '@kit.BasicServicesKit'; // ★ 0.222.18：设备类型判定（仅手机去掉知识库空白处长按创建菜单，PC 右键/Pad 长按保留）
import { connectGlobalSettingsShared } from './GlobalSettingsDialog'; // ★ 0.230.0：返回键优先关设置弹窗
import { FoldChevron } from './FoldChevron'; // ★ 0.237.0：全项目唯一折叠指示器（军令统一）
import { AppStorageV2 } from '@kit.ArkUI'; // ★ 0.239.0：知识库视图模式 store（跨页面记忆，复刻 WordViewModeStore）
const TREE_CELL: number = 14; // ★ 0.222.17：树形连接线每层缩进宽度（vp）

// ★ 0.239.0：知识库视图模式（AppStorageV2 共享 @Trace grid）——复刻单词库 WordViewModeStore（0.219.2）：
//   页面组件销毁重建（切其他页面再回来）grid 不回弹列表（跨页面记忆）；key 独立 'knowledge-view-mode'
//   勿与 'word-view-mode' 冲突；AppStorageV2 会话级共享（重启恢复默认列表可接受，与单词库同语义）
@ObservedV2
export class KnowledgeViewModeStore {
  @Trace grid: boolean = false;
}

export function connectKnowledgeViewMode(): KnowledgeViewModeStore {
  return AppStorageV2.connect(KnowledgeViewModeStore, 'knowledge-view-mode', () => new KnowledgeViewModeStore()) as KnowledgeViewModeStore;
}

@ComponentV2
export struct KnowledgeBankPage {
  theme: AppTheme = connectAppTheme();
  @Param pathStack: NavPathStack = new NavPathStack();
  @Local sidebarVisible: boolean = false; // ★ 0.222.0 手机知识库页边栏抽屉开关
  knowledgeBank: KnowledgeBankStore = connectKnowledgeBank(); // isolated PersistenceV2 instance

  // ── ★ 0.200.0：知识卡片导入气泡（入口 A 列表 / 入口 B 编辑弹窗）──
  cardImport: CardImportStore = connectCardImport(); // 跨页共享 store（画布/ChatPage 消费）
  @Local askSheetVisible: boolean = false; // 「问 AI」二选一面板
  @Local askSheetTitle: string = '';       // 面板展示的卡片快照（列表入口暂存）
  @Local askSheetDefinition: string = '';
  @Local askSheetImages: string[] = []; // ★ 0.202.2：面板快照（多图）

  // ── ★ 0.202.2：标签 chip 交互（editorTags 逗号串存储，UI 层 chips 化）──
  removeEditorTag(t: string): void {
    this.editorTags = parseTags(this.editorTags).filter((x: string): boolean => x !== t).join(',');
  }

  @Local tagEditVisible: boolean = false;
  @Local tagEditOld: string = '';
  @Local tagEditNew: string = '';

  openEditorTagEdit(old: string): void {
    this.tagEditOld = old;
    this.tagEditNew = old;
    this.tagEditVisible = true;
  }

  commitEditorTagEdit(): void {
    const nv = this.tagEditNew.trim();
    if (nv.length === 0) {
      this.tagEditVisible = false;
      return;
    }
    if (this.tagEditOld.length === 0) {
      // 新增
      const picked = parseTags(this.editorTags);
      if (!picked.includes(nv)) {
        picked.push(nv);
        this.editorTags = picked.join(',');
      }
    } else if (nv !== this.tagEditOld) {
      // 改名
      this.editorTags = parseTags(this.editorTags).map((t: string): string => t === this.tagEditOld ? nv : t).join(',');
    }
    this.tagEditVisible = false;
  }

  /** ★ 0.200.0：写入导入 store + 回画布进入选择模式（B 入口已删 0.202.2——仅列表问 AI 面板调用） */
  startCardImport(action: string, title: string, definition: string, imageUris: string[]): void {
    this.cardImport.action = action;
    this.cardImport.title = title;
    this.cardImport.definition = definition;
    this.cardImport.imageUrisJson = JSON.stringify(imageUris); // ★ 0.202.2：多图全链路
    this.askSheetVisible = false;
    this.editorVisible = false; // B 入口：关编辑弹窗
    navBackToCanvas(this.pathStack);
  }

  // ★ 0.195.0：大屏断点（≥600vp）——顶栏左间距对齐气泡树信息条（28/14 双分支）
  // ★ 0.196.4：改读窗口宽度共享真相源（WindowMode）——分屏/悬浮窗实时切手机布局
  @Local windowMode: WindowMode = connectWindowMode(); // ★ 0.222.1 挂 @Local（@ObservedV2 实例须挂 @Local 才可靠响应 @Trace，isTablet @Computed 依赖链真机不可靠）
  @Computed get isTablet(): boolean {
    return this.windowMode.isTablet;
  }

  // ── ★ 0.239.0：列表/网格双视图（复刻单词库 0.218.x 已验证方案）──
  @Local viewMode: KnowledgeViewModeStore = connectKnowledgeViewMode(); // 挂 @Local（@ObservedV2 实例响应 @Trace 的可靠姿势）
  @Local gridCols: number = 4; // ★ 0.239.0：网格列数随容器宽连续自适应（禁写死档位军令）——封面卡目标格宽 200（卡片比单词卡高，格宽放宽）
  @Local gridGap: number = 12; // ★ 0.239.0：间距随格宽连续缩放（8~14 连续区间，与单词库同式）

  // ── ★ 0.240.0：手机端搜索栏滚动隐藏（用户拍板「上滑收起/下滑呼回」，与单词库同款）──
  // 宽屏（isTablet || isPcDevice）搜索栏常驻：渲染条件兜底 + onDidScroll 直接短路（PC 窗口拖窄误收后拖宽也能自愈）
  @Local searchBarVisible: boolean = true;
  private listScroller: Scroller = new Scroller();
  private scrollAccum: number = 0; // 同方向累计量（≥10vp 才收/放，防轻蹭抖动）
  private scrollDir: number = 0;   // 0=无 / 1=上滑（收） / -1=下滑（放）；方向反转即清零重计
  private lastToggleAt: number = 0; // ★ 0.241.0：上次收/放切换时间戳——300ms 冷却期掐断滚到底回弹横跳

  /** ★ 0.239.0 设备三档判定（照抄 WordBankPage.ets 0.218.8 先例）：phone/tablet/tv/car/wearable
   *  之外全算 PC 档——PC 窗口拖到多窄都是 PC 档（网格与切换按钮保持，不退化手机列表） */
  isPcDevice(): boolean {
    const t = deviceInfo.deviceType;
    return t !== 'phone' && t !== 'tablet' && t !== 'tv' && t !== 'car' && t !== 'wearable';
  }

  /** ★ 0.239.0：封面图优先级——标题图首张 → 内容图首张 → ''（无图走紫渐变占位） */
  cardCoverImage(c: KnowledgeCard): string {
    const t = getTitleImages(c);
    if (t.length > 0) {
      return t[0];
    }
    const g = getCardImages(c);
    return g.length > 0 ? g[0] : '';
  }

  aboutToAppear(): void {
    // ★ 0.196.4：isTablet 屏宽检测删除——改读 WindowMode 共享真相源（Index 根 onAreaChange 写入）
  }

  // ★ 0.148: search / sort state
  @Local searchKeyword: string = '';
  @Local sortMode: number = 0; // ★ 0.191.0：排序 4 态——0=最新↓（创建降序，默认）1=最新↑（创建升序）2=需复习↑（复习升序）3=需复习↓（复习降序）；★ 0.222.16 已并拢为单个「排序」入口
  @Local sortMenuVisible: boolean = false; // ★ 0.222.16 用户拍板：两个排序按钮并拢为单个「排序」入口（参考单词库右上角 UI）——点击弹两选项（最新/需复习），点选项只切排序不收起（可连续切换），点遮罩才收

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
  @Local editorTitle: string = '';
  @Local editorDefinition: string = '';
  @Local editorTags: string = ''; // ★ 0.202.0：标签输入（逗号/顿号/空格分隔）
  @Local editorImages: string[] = []; // ★ 0.202.1：多图编辑（上限 9；替代原单图 editorImageUri 的编辑态）
  @Local editorTitleImages: string[] = []; // ★ 0.210.0：标题图编辑（上限 9；Anki 图对图——题面插图）
  // ★ 0.160: editor image state — base64 data URI, same storage pattern as
  // ChatPage's knowledge editor; empty string = no image
  @Local editorImageUri: string = '';
  // ★ 0.160: fullscreen preview of the editor image（tap thumbnail to open）
  // ★ 0.211.2：旧单图预览状态已删——编辑弹窗预览统一走 imagePreviewViewer（四场景同一查看器）

  // ★ 0.148: single-delete confirm dialog state
  @Local deleteConfirmVisible: boolean = false;
  @Local deleteConfirmNoRemind: boolean = false;
  @Local pendingDeleteId: string = '';

  // ★ 0.148: batch-delete confirm dialog state (always shown, no no-remind)
  @Local batchConfirmVisible: boolean = false;

  // ── ★ 0.207.0：文件夹体系（anything 导入）状态 ──
  // ★ 0.220.0：currentFolderId 迁 KbFolderNavStore（AppStorageV2 共享 @Trace folderId）——
  //   边栏文件夹树与页内视图同源同步（边栏点文件夹=页内视图立即切换，同一 store 实例零桥接）
  @Local folderNav: KbFolderNavStore = connectKbFolderNav(); // ★ 0.221.4：挂 @Local（@ObservedV2 实例须挂 @Local 才可靠响应 @Trace——0.221.3 弹窗操作不生效真凶）
  @Local folderDialogVisible: boolean = false;  // 新建/重命名共用弹窗
  @Local createMenuVisible: boolean = false; // ★ 0.220.2：PC 右键/Pad 长按创建菜单开关
  @Local folderDialogIsRename: boolean = false;
  @Local folderDialogTargetId: string = '';
  @Local folderDialogName: string = '';
  @Local folderPickerVisible: boolean = false;  // 移动/复制目标选择弹窗
  @Local moveOrCopyMode: string = 'move';       // 'move' | 'copy'（folderPicker 确认时分流）
  @Local pickerCollapsedFolderIds: string[] = []; // ★ 0.222.1 目标选择器文件夹折叠状态
  @Local importPreviewVisible: boolean = false; // 批量导入预览弹窗
  @Local importRows: ImportRow[] = [];
  @Local importFileName: string = '';
  @Local importFormat: string = 'txt';
  // ★ 0.225.0：+ 菜单重构（用户拍板三主项+二级格式）——bindPopup drill-down 替代系统 bindMenu
  @Local plusMenuVisible: boolean = false;
  @Local plusMenuMode: string = 'main'; // 'main' | 'import' | 'export'

  // ── ★ 0.207.1：DagPack 导入（勾选树）状态 ──
  @Local packPreviewVisible: boolean = false;
  @Local packData: DagPack = { format: '', version: 0, kind: '', exportedAt: 0, origin: '', folders: [], cards: [] };
  @Local packSel: string[] = [];        // 勾选的顶层 refId（各含其子树）
  @Local packRootCardsSel: boolean = true; // 根级散卡是否随包导入
  @Local packFileName: string = '';

  // ── ★ 0.208.0：Anki apkg 导入状态 ──
  @Local apkgPreviewVisible: boolean = false;
  @Local apkgCards: ApkgCard[] = [];
  @Local apkgDeckCounts: Record<string, number> = {};
  @Local apkgMediaCount: number = 0;
  @Local apkgFileName: string = '';
  // ── ★ 0.211.0：列表图片全屏查看器（双击卡片图放大缩小——用户需求）──
  @Local previewImages: string[] = [];
  @Local previewIndex: number = 0;
  @Local previewVisible: boolean = false;
  @Local previewScale: number = 1;
  @Local previewLastTap: number = 0; // ★ 0.211.2：单击/双击判定（0.173.x 铁律）
  private previewCloseTimerId: number = -1; // ★ 0.211.2：延迟关闭计时器（aboutToDisappear 清理）

  /** 当前目录的子文件夹（新在前）；卡片计数用 folderCardCount() */
  @Computed
  get currentFolders(): KFolder[] {
    return this.knowledgeBank.folders
      .filter((f: KFolder): boolean => f.parentId === this.folderNav.folderId)
      .sort((a: KFolder, b: KFolder) => b.createdAt - a.createdAt);
  }

  folderCardCount(folderId: string): number {
    let n = 0;
    for (let i = 0; i < this.knowledgeBank.cards.length; i++) {
      if (this.knowledgeBank.cards[i].folderId === folderId) {
        n++;
      }
    }
    return n;
  }

  // ★ 0.161.2: knowledge-card count settings dialog state (top-bar ⚙ button, left of "+")
  knowledgeCountStore: KnowledgeCountStore = connectKnowledgeCount(); // persisted card count (default 1, range 1~20)
  @Local cardSettingsVisible: boolean = false;
  @Local cardCustomInput: string = '';  // free-input temp value (validated 1~20 on confirm)
  @Local cardInputError: string = '';   // free-input validation error text (empty = no error)

  // ★ 0.148: live-filtered + sorted view — fuzzy match on title +
  // definition (spec 2.1.4: title + body content), createdAt asc/desc.
  @Computed
  get filteredCards(): KnowledgeCard[] {
    const kw = this.searchKeyword.trim().toLowerCase();
    let list: KnowledgeCard[] = [];
    if (kw.length === 0) {
      // ★ 0.207.0：目录视图——无关键字只看当前文件夹（跨库找卡走搜索）
      list = this.knowledgeBank.cards.filter((c: KnowledgeCard) => c.folderId === this.folderNav.folderId);
    } else {
      // 搜索保持全库（含所有文件夹——找卡不被目录困住）
      list = this.knowledgeBank.cards.filter((c: KnowledgeCard) => {
        return c.title.toLowerCase().includes(kw)
          || c.definition.toLowerCase().includes(kw);
      });
    }
    if (this.sortMode === 2) {
      // ★ 0.191.0：需复习升序（已到期/未学习 nextReviewAt=0 排最前）
      list.sort((a: KnowledgeCard, b: KnowledgeCard) => a.nextReviewAt - b.nextReviewAt);
    } else if (this.sortMode === 3) {
      // ★ 0.191.0：需复习降序（最晚复习的在前）
      list.sort((a: KnowledgeCard, b: KnowledgeCard) => b.nextReviewAt - a.nextReviewAt);
    } else if (this.sortMode === 1) {
      // ★ 0.191.0：创建时间升序（最早在前）
      list.sort((a: KnowledgeCard, b: KnowledgeCard) => a.createdAt - b.createdAt);
    } else {
      // ★ 0.191.0：创建时间降序（最新在前，默认）
      list.sort((a: KnowledgeCard, b: KnowledgeCard) => b.createdAt - a.createdAt);
    }
    return list;
  }

  // ★ 0.240.0：手机端搜索栏滚动隐藏防抖逻辑（onDidScroll 每 tick 调用，纯轻量计算）——
  //   上滑累计 >10vp 收起 / 下滑累计 >10vp 呼回 / 方向反转清零重计 / 滚回顶部（≤0.5vp）强制显示
  // ★ 0.241.0：滚到底「鬼畜抖动」修复（用户真机实锤：收起→弹出→又收起来回横跳）——
  //   ①冷却期 300ms：收/放切换后 300ms 内丢弃一切偏移信号（触底回弹的反向信号进不来）
  //   ②不对称阈值：收起仍 10vp；唤回须 ≥24vp——小回弹唤不回，掐断循环（回顶强制显示保留不动）
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
    const now: number = Date.now();
    if (now - this.lastToggleAt < 300) {
      this.scrollAccum = 0; // 冷却期内偏移全部丢弃——回弹尾巴不带进冷却结束后的判定
      return;
    }
    const dir: number = offset > 0 ? 1 : -1;
    if (dir !== this.scrollDir) {
      this.scrollDir = dir;
      this.scrollAccum = 0;
    }
    this.scrollAccum += Math.abs(offset);
    const threshold: number = dir > 0 ? 10 : 24; // ★ 0.241.0 不对称阈值：收 10 / 唤回 24
    if (this.scrollAccum >= threshold) {
      this.scrollAccum = 0;
      if (dir > 0 && this.searchBarVisible) {
        this.searchBarVisible = false; // 直接赋值 + transition 动画（禁 animateTo 闭包——畅享90pro UI 不刷新雷）
        this.lastToggleAt = now;
      } else if (dir < 0 && !this.searchBarVisible) {
        this.searchBarVisible = true;
        this.lastToggleAt = now;
      }
    }
  }

  // ★ 0.222.16：排序选项菜单（bindPopup 自定义 builder）——无参 @Builder 内部直读 sortMode（0.190.1 铁律）；
  //   两项=最新/需复习，各带当前方向箭头，激活项品牌紫高亮；点击只改 sortMode 不收起，点遮罩才收；
  //   ★ 0.240.0：激活项补紫底（this.theme.surfaceHover+radius 8）——UI_GUIDELINES 铁律「排序/筛选选中态统一品牌紫背景」，按钮图标化后弹层成为排序状态唯一可视位
  @Builder
  sortMenuBuilder() {
    Column() {
      Text(this.sortMode === 1 ? '最新 ↑' : '最新 ↓')
        .fontSize(14)
        .fontColor(this.sortMode === 0 || this.sortMode === 1 ? this.theme.brandSecondary : this.theme.textPrimary)
        .backgroundColor(this.sortMode === 0 || this.sortMode === 1 ? this.theme.surfaceHover : Color.Transparent)
        .borderRadius(8)
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ top: 12, bottom: 12, left: 16, right: 16 })
        .onClick(() => {
          this.sortMode = this.sortMode === 0 ? 1 : 0;
        })
      Divider().color(this.theme.strokeCard)
      Text(this.sortMode === 3 ? '需复习 ↓' : '需复习 ↑')
        .fontSize(14)
        .fontColor(this.sortMode === 2 || this.sortMode === 3 ? this.theme.brandSecondary : this.theme.textPrimary)
        .backgroundColor(this.sortMode === 2 || this.sortMode === 3 ? this.theme.surfaceHover : Color.Transparent)
        .borderRadius(8)
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ top: 12, bottom: 12, left: 16, right: 16 })
        .onClick(() => {
          this.sortMode = this.sortMode === 2 ? 3 : 2;
        })
    }
    .width(160)
  }

  // ★ 0.188.0：下次复习标签——未学习 / 下次复习：已到期·N分钟后·N小时后·N天后·日期
  nextReviewLabel(c: KnowledgeCard): string {
    if (c.reviewCount === 0) {
      return '未学习';
    }
    // ★ 0.195.0：已到期标签简化——原「下次复习：已到期」易误解（用户实测），定稿三字「需复习」（nextReviewColor 自动标红）
    if (c.nextReviewAt <= Date.now()) {
      return '需复习';
    }
    return '下次复习：' + formatNextReviewLabel(c.nextReviewAt, Date.now());
  }

  // ★ 0.188.0：下次复习着色——已到期红 / 其余灰
  nextReviewColor(c: KnowledgeCard): string {
    if (c.reviewCount > 0 && c.nextReviewAt <= Date.now()) {
      return this.theme.danger;
    }
    return this.theme.textTertiary;
  }

  // toast 轻提示（showToast 可能抛异常，统一包裹消除编译告警，失败不影响主流程）
  showToast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
    } catch (e) {
      // toast 失败静默忽略
    }
  }

  // ---- editor dialog (add & edit share it) ----

  openAddEditor(): void {
    this.editorIsAdd = true;
    this.editorId = '';
    this.editorTitle = '';
    this.editorDefinition = '';
    this.editorTags = ''; // ★ 0.202.0：标签输入
    this.editorImages = []; // ★ 0.202.1：多图清空
    this.editorTitleImages = []; // ★ 0.210.0：标题图清空
    this.editorVisible = true;
  }

  openEditEditor(c: KnowledgeCard): void {
    this.editorIsAdd = false;
    this.editorId = c.id;
    this.editorTitle = c.title;
    this.editorDefinition = c.definition;
    this.editorTags = c.tags; // ★ 0.202.0：预填已有标签
    this.editorImages = getCardImages(c); // ★ 0.202.1：预填已有图片（两代字段兼容读取）
    this.editorTitleImages = getTitleImages(c); // ★ 0.210.0：预填标题图
    this.editorVisible = true;
  }

  saveEditor(): void {
    const title = this.editorTitle.trim();
    if (title.length === 0) {
      this.showToast('标题不能为空');
      return;
    }
    const definition = this.editorDefinition.trim();
    const tags = this.editorTags.trim(); // ★ 0.202.0：标签随卡保存
    const imagesJson = this.editorImages.length > 0 ? JSON.stringify(this.editorImages) : ''; // ★ 0.202.1：多图随卡保存
    const titleImagesJson = this.editorTitleImages.length > 0 ? JSON.stringify(this.editorTitleImages) : ''; // ★ 0.210.0：标题图随卡保存
    if (this.editorIsAdd) {
      // addKnowledgeCard auto-fills id/createdAt; no duplicate check —
      // cards may legitimately share a title (0.146 spec)
      // ★ 0.219.2 用户实测 bug 修复：新建卡片 folderId 曾写死空串（永落根目录）——用户双击进入
      //   文件夹后新建，卡片理应归属**当前所在文件夹**（currentFolderId；'' = 根目录视图原样）
      addKnowledgeCard(this.knowledgeBank, new KnowledgeCard('', title, definition, '', 0, 0, 0, 0, 0, tags, imagesJson, this.folderNav.folderId, titleImagesJson));
    } else {
      updateKnowledgeCard(this.knowledgeBank, this.editorId, title, definition, '', tags, imagesJson, titleImagesJson);
    }
    this.editorVisible = false;
  }

  // ★ 0.211.1 修复手机端「9 张点保存崩溃」：原图 base64（单张可达 5-10MB，×1.37 膨胀）9 张
  //   直接塞卡 → 保存时全库 JSON 序列化+PersistenceV2 写盘，内存峰值打爆手机（PC 内存大不崩）。
  //   根治=选图时压缩：解码→最长边缩到 1280→JPEG 质量 80（单张落盘 ~200-400KB，9 张 ~3MB）。
  //   data:image/jpeg;base64 前缀格式保持不变（备份/DagPack/apkg 全链兼容）
  async compressEditorImage(uri: string): Promise<string> {
    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const imageSource = image.createImageSource(file.fd);
      const info = await imageSource.getImageInfo();
      const maxEdge = 1280;
      const longest = Math.max(info.size.width, info.size.height);
      const ratio = longest > maxEdge ? maxEdge / longest : 1;
      const decodingOpts: image.DecodingOptions = {
        desiredSize: {
          width: Math.max(1, Math.round(info.size.width * ratio)),
          height: Math.max(1, Math.round(info.size.height * ratio))
        }
      };
      const pixelMap = await imageSource.createPixelMap(decodingOpts);
      const packer = image.createImagePacker();
      const packed = await packer.packToData(pixelMap, { format: 'image/jpeg', quality: 80 });
      const dataUri = `data:image/jpeg;base64,${buffer.from(packed).toString('base64')}`;
      pixelMap.release();
      packer.release();
      imageSource.release();
      return dataUri;
    } finally {
      fileIo.closeSync(file);
    }
  }

  // ★ 0.210.0：标题图选图（复刻 selectEditorImage 流程——目标数组独立 editorTitleImages；上限同 9）
  // ★ 0.211.0 修复手机端超限崩溃：maxSelectNumber 写死 9 → 已有 8 张仍可选 9 张全量读取（手机
  //   内存峰值被打爆直接闪退，PC 内存大仅静默截断）。改动态额度=9-已有张数（至少 1），选图器
  //   源头限制+循环兜底截断双保险——用户拍板"自动计算只能添加一张"
  async selectEditorTitleImage(): Promise<void> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const quota = Math.max(1, 9 - this.editorTitleImages.length);
      const result = await picker.select({ maxSelectNumber: quota });
      for (let i = 0; i < result.photoUris.length; i++) {
        if (this.editorTitleImages.length >= 9) {
          break; // 上限 9 张（每轮追加，超出静默截断）
        }
        const dataUri = await this.compressEditorImage(result.photoUris[i]); // ★ 0.211.1：压缩后再入库
        this.editorTitleImages.push(dataUri);
      }
      this.editorTitleImages = [...this.editorTitleImages]; // 触发数组状态更新
    } catch (err) {
      // 选图取消/读取失败静默忽略（防崩溃）
    }
  }

  // ★ 0.160: pick a photo from the gallery → base64 data URI (same flow as
  // ChatPage's knowledge editor: single select, read via fileIo, encode with
  // buffer). Failure is silent — the editor keeps its previous image state.
  // ★ 0.202.1: multi-image — up to 9 picks per round, appended to editorImages.
  async selectEditorImage(): Promise<void> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const quota = Math.max(1, 9 - this.editorImages.length); // ★ 0.211.0：动态额度同标题图（防手机超限崩溃）
      const result = await picker.select({ maxSelectNumber: quota });
      for (let i = 0; i < result.photoUris.length; i++) {
        if (this.editorImages.length >= 9) {
          break; // 上限 9 张（每轮追加，超出静默截断）
        }
        const dataUri = await this.compressEditorImage(result.photoUris[i]); // ★ 0.211.1：压缩后再入库
        this.editorImages.push(dataUri);
      }
      this.editorImages = [...this.editorImages]; // 触发数组状态更新
    } catch (err) {
      // 选图取消/读取失败静默忽略（防崩溃）
    }
  }

  // ★ 0.283.0：READ_PASTEBOARD 运行时授权链（ChatPage.ensurePastePermission 同款：user_grant 级
  //   首次弹窗一次；被拒=toast 说明+requestPermissionOnSetting 直达权限面板当场续贴）
  async ensureEditorPastePermission(): Promise<boolean> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const atm = abilityAccessCtrl.createAtManager();
      const result = await atm.requestPermissionsFromUser(ctx, ['ohos.permission.READ_PASTEBOARD']);
      if (result.authResults.length > 0 &&
        result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return true;
      }
      this.showToast('未授权：请在系统「设置→应用→DAG AI Chat→权限」允许「剪贴板」');
      try {
        const panelResult = await atm.requestPermissionOnSetting(ctx, ['ohos.permission.READ_PASTEBOARD']);
        return panelResult.length > 0 &&
          panelResult[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
      } catch (_e) {
        return false;
      }
    } catch (_e) {
      return false;
    }
  }

  // ★ 0.283.0：卡片编辑弹窗 Ctrl+V 贴图（PC 需求——截图后键盘直达贴图；复刻 ChatPage
  //   0.275.0/0.283.0 同款管线）：pixelMap 优先（截图）打包 JPEG q80（对齐 0.211.1 压缩档）；
  //   uri 次之（图库复制）走 compressEditorImage 同链路；无图静默（纯文本粘贴归
  //   TextInput/TextArea 原生行为不打扰）。editorPasting 防重入（异步期间重复按键忽略）。
  //   ★ 0.283.1 双目标区：isTitle=true 贴入标题图区 editorTitleImages（标题框聚焦时 Ctrl+V）、
  //   false 贴入内容图区 editorImages（内容框聚焦时 Ctrl+V）——数组分支直写不做引用别名
  //   （@Local 刷新安全）
  editorPasting: boolean = false;
  async pasteEditorImageFromClipboard(isTitle: boolean = false): Promise<void> {
    if (this.editorPasting) {
      return;
    }
    this.editorPasting = true;
    try {
      const granted = await this.ensureEditorPastePermission();
      if (!granted) {
        return; // 未授权：授权链已 toast+拉面板，此处静默退出
      }
      const data = await pasteboard.getSystemPasteboard().getData();
      const count = data.getRecordCount();
      for (let i = 0; i < count; i++) {
        const rec = data.getRecordAt(i);
        if (rec.pixelMap !== undefined && rec.pixelMap !== null) {
          if (isTitle) {
            if (this.editorTitleImages.length >= 9) {
              this.showToast('标题图片最多 9 张');
              return;
            }
            const packer = image.createImagePacker();
            const packed = await packer.packToData(rec.pixelMap, { format: 'image/jpeg', quality: 80 });
            packer.release();
            this.editorTitleImages.push(`data:image/jpeg;base64,${buffer.from(packed).toString('base64')}`);
            this.editorTitleImages = [...this.editorTitleImages]; // 触发数组状态更新
          } else {
            if (this.editorImages.length >= 9) {
              this.showToast('最多添加 9 张图片');
              return;
            }
            const packer = image.createImagePacker();
            const packed = await packer.packToData(rec.pixelMap, { format: 'image/jpeg', quality: 80 });
            packer.release();
            this.editorImages.push(`data:image/jpeg;base64,${buffer.from(packed).toString('base64')}`);
            this.editorImages = [...this.editorImages]; // 触发数组状态更新
          }
          this.showToast('已粘贴图片');
          return;
        }
        if (rec.uri !== undefined && rec.uri !== null && rec.uri.length > 0) {
          const dataUri = await this.compressEditorImage(rec.uri);
          if (dataUri.length > 0) {
            if (isTitle) {
              if (this.editorTitleImages.length >= 9) {
                this.showToast('标题图片最多 9 张');
                return;
              }
              this.editorTitleImages.push(dataUri);
              this.editorTitleImages = [...this.editorTitleImages];
            } else {
              if (this.editorImages.length >= 9) {
                this.showToast('最多添加 9 张图片');
                return;
              }
              this.editorImages.push(dataUri);
              this.editorImages = [...this.editorImages];
            }
            this.showToast('已粘贴图片');
          }
          return;
        }
      }
      // 无图记录：静默——Ctrl+V 粘贴文本归 TextInput/TextArea 原生行为
    } catch (err) {
      this.showToast('图片粘贴失败，请重试');
    } finally {
      this.editorPasting = false;
    }
  }

  // ★ 0.212.0：卡片滑动露出的操作面板（左滑右滑同款）
  // ★ 0.213.0 用户拍板：扩容为双圆钮——左「问AI」（ask_ai.svg 白图标，功能=知识卡重新带入对话框
  //   问AI，承接原列表标题行「问AI?」入口）+右「删除」（trash 白图标）——用户点名"问AI 放删除左边，
  //   滑块工具凸显问AI 概念，设计一个鸿蒙风格 logo"；同款 44×44 品牌紫圆钮（用户认可删除钮亮度设计）。
  //   多选中点击均 guard 无动作；规格入 UI_GUIDELINES 六-11
  @Builder
  swipeActionsPanel(c: KnowledgeCard) {
    Row({ space: 12 }) {
      Column() {
        Image($r('app.media.ask_ai'))
          .width(20)
          .height(20)
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor(this.theme.brandPrimary)
      .onClick(() => {
        if (!this.multiSelectMode) {
          this.askSheetTitle = c.title;
          this.askSheetDefinition = c.definition;
          this.askSheetImages = [...getTitleImages(c), ...getCardImages(c)]; // 标题图在前+内容图合并带入问AI面板
          this.askSheetVisible = true;
        }
      })
      Column() {
        Image($r('app.media.trash_brand'))
          .width(20)
          .height(20)
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor(this.theme.brandPrimary)
      .onClick(() => {
        if (!this.multiSelectMode) {
          this.requestDeleteCard(c); // 多选模式下滑动面板点击无动作（避免与整行点选/批量删除打架）
        }
      })
    }
    .justifyContent(FlexAlign.Center)
    .width(120)
    .height('100%')
  }


  // ★ 0.211.0：打开列表图片全屏查看器（双击卡片里的图片触发）
  openImagePreview(images: string[], index: number): void {
    this.previewImages = images;
    this.previewIndex = index;
    this.previewScale = 1;
    this.previewVisible = true;
  }

  // ★ 0.211.2：缩放缓动（250ms EaseOut——用户报"放大速度太快"；捏合跟手阶段不经此，松手归位走动画）
  private applyPreviewScale(target: number): void {
    const clamped = Math.min(4, Math.max(1, target));
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
      this.previewScale = clamped;
    });
  }

  // ★ 0.211.2：单击/双击手动判定（0.173.x 铁律：只绑 count:1，300ms 内第二击=双击缩放；
  //   否则延迟 320ms 关闭查看器——三重退出冗余之一"点一下图片退出"）
  private previewTapHandled(): void {
    const now = Date.now();
    if (now - this.previewLastTap < 300) {
      this.previewLastTap = 0;
      if (this.previewCloseTimerId >= 0) {
        clearTimeout(this.previewCloseTimerId);
        this.previewCloseTimerId = -1;
      }
      this.applyPreviewScale(this.previewScale > 1 ? 1 : 2.5);
    } else {
      this.previewLastTap = now;
      if (this.previewCloseTimerId >= 0) {
        clearTimeout(this.previewCloseTimerId);
      }
      this.previewCloseTimerId = setTimeout(() => {
        this.previewCloseTimerId = -1;
        this.previewVisible = false;
      }, 320);
    }
  }

  aboutToDisappear(): void {
    // ★ 0.211.2：定时器销毁纪律（项目铁律）——预览延迟关闭计时器
    if (this.previewCloseTimerId >= 0) {
      clearTimeout(this.previewCloseTimerId);
      this.previewCloseTimerId = -1;
    }
  }

  // ---- single delete (session-level no-remind) ----

  requestDeleteCard(c: KnowledgeCard): void {
    if (this.skipDeleteConfirm) {
      removeKnowledgeCard(this.knowledgeBank, c.id);
      return;
    }
    this.pendingDeleteId = c.id;
    this.deleteConfirmNoRemind = false;
    this.deleteConfirmVisible = true;
  }

  confirmDeleteCard(): void {
    removeKnowledgeCard(this.knowledgeBank, this.pendingDeleteId);
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
    const list = this.filteredCards;
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
      this.selectedIds = this.filteredCards.map((c: KnowledgeCard) => c.id);
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
    removeCardsByIds(this.knowledgeBank, this.selectedIds);
    this.batchConfirmVisible = false;
    this.exitMultiSelect();
  }

  // ---- entry tap: multi-select toggle / manual double-tap to edit ----

  onItemTap(c: KnowledgeCard): void {
    // ClickEvent has no stopPropagation — record the tap time so the List's
    // blank-area handler can ignore this bubbled tap (200ms window)
    this.lastEntryTapAt = Date.now();
    if (this.multiSelectMode) {
      this.toggleSelect(c.id);
      return;
    }
    const now = Date.now();
    if (now - this.lastTapTime < 300) {
      this.lastTapTime = 0;
      this.openEditEditor(c); // double-tap → edit
    } else {
      this.lastTapTime = now;
    }
  }

  // ★ 0.159 pattern: self-drawn top bar with hideTitleBar(true) — a .title()
  // custom builder's content-area width reference includes the system
  // back-button slot and overflows the screen (proven on ChatPage).

  // ★ 0.222.0：手机知识库页边栏抽屉（复刻气泡树 MobileDrawerLayer——遮罩点按收 + translate 滑入滑出）
  openSidebar(): void {
    if (this.sidebarVisible) {
      return;
    }
    this.sidebarVisible = true; // ★ 0.222.6 直接赋值——animateTo 闭包内赋值真机不通知观察（日志实锤 visible=true 打了 UI 不刷新）
  }

  closeSidebar(): void {
    if (!this.sidebarVisible) {
      return;
    }
    this.sidebarVisible = false; // ★ 0.222.6 直接赋值（同 openSidebar 根因）
  }
  /** 手机抽屉导航（点导航项跳转+收抽屉；kind=''/knowledge/settings=只收抽屉） */
  onSidebarNav(kind: string): void {
    this.closeSidebar();
    if (kind === '' || kind === 'knowledge' || kind === 'settings') {
      return;
    }
    if (kind === 'canvas') {
      this.pathStack.replacePath({ name: 'BBTreeCanvas' });
      return;
    }
    const target = kind === 'wordbank' ? 'WordBankPage' : kind === 'review' ? 'ReviewPage' : kind === 'statistics' ? 'StatisticsPage' : kind === 'billing' ? 'BillingPage' : '';
    if (target !== '') {
      this.pathStack.pushPath({ name: target });
    }
  }
  // ★ 0.222.4：抽屉块抽成 @Builder——build 主体 Stack children 内联 if 的 windowMode.isTablet
  //   依赖追踪真机不可靠（首帧 Index 屏宽猜测 isTablet=true、onAreaChange 纠正 false 后该 if
  //   不重求值、抽屉块永不创建——0.222.1 @Local 与 0.222.3 直读都没治到点上）；@Builder=独立
  //   渲染单元、依赖追踪可靠（BBTreeCanvas MobileDrawerLayer 同款模式、真机已验证）
  @Builder
  kbMobileDrawerLayer() {
    // ★ 0.222.7：重写=条件渲染+transition——0.222.4~0.222.6 三轮实锤 translate 藏屏+animateTo/直接赋值
    //   全不刷新（日志证明组件创建+赋值成功、UI 不动），改用与「正常工作弹窗块」同款的条件渲染机制
    if (!this.windowMode.isTablet && this.sidebarVisible) {
      // ★ 0.224.8 空隙病根：遮罩/边栏两兄弟裸挂页面 Stack——边栏包裹列无 height，
      //   自适应高撑不满全屏（底部漏遮罩黑条），且 AppSideBar height('100%')
      //   参照失效致内部 Blank() 弹性错乱（设置与账号栏间出现 500+px 大空隙）。
      //   修法=包一层全屏 Stack（TopStart 贴左上），边栏列显式 height('100%')。
      Stack({ alignContent: Alignment.TopStart }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.theme.overlay)
          .onClick(() => {
            this.closeSidebar();
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 220 }))
        Column() {
          AppSideBar({
            currentRoute: 'KnowledgeBankPage',
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
    }  }

  // ★ 0.241.0：左下角浮动导航胶囊条（仅手机端）——单手可达的边栏入口 + 目录面包屑
  //   （点任意一级直接跳转该文件夹；随滚动与搜索栏同向联动收放；多选模式不渲染；PC/Pad 完全不动）
  //   ⚠️ 全屏定位容器 hitTestBehavior(None)：自身穿透、不拦列表触摸，胶囊本体照常可点（0.200.0 变暗层同款范式）
  @Builder
  kbNavCapsule() {
    if (!this.windowMode.isTablet && !this.isPcDevice() && !this.multiSelectMode && this.searchBarVisible) {
      Stack({ alignContent: Alignment.BottomStart }) {
        Row({ space: 8 }) {
          Image($r('app.media.sidebar'))
            .width(20)
            .height(20)
            .objectFit(ImageFit.Contain)
            .onClick(() => {
              this.openSidebar();
            })
          Column()
            .width(1)
            .height(16)
            .backgroundColor(this.theme.strokeCard)
          Scroll() {
            Row({ space: 4 }) {
              Text('全部卡片')
                .fontSize(12)
                .fontColor(this.folderNav.folderId.length === 0 ? this.theme.brandSecondary : this.theme.textSecondary)
                .onClick(() => {
                  this.folderNav.folderId = ''; // 与边栏树点击同源——直接赋值即切主内容区
                })
              ForEach(this.currentChain, (f: KFolder, idx: number) => {
                Row({ space: 4 }) {
                  Image($r('app.media.chevronright'))
                    .width(16)
                    .height(16)
                    .objectFit(ImageFit.Contain)
                  Text(f.name)
                    .fontSize(12)
                    .fontColor(idx === this.currentChain.length - 1 ? this.theme.brandSecondary : this.theme.textSecondary)
                    .onClick(() => {
                      this.folderNav.folderId = f.id;
                    })
                }
                .alignItems(VerticalAlign.Center)
              }, (f: KFolder) => f.id)
            }
            .alignItems(VerticalAlign.Center)
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .constraintSize({ maxWidth: 230 }) // 长路径横向滚动，胶囊不顶满屏（横向 Scroll 子项自然宽铁律合规）
        }
        .alignItems(VerticalAlign.Center)
        .height(40)
        .padding({ left: 12, right: 12 })
        .borderRadius(20)
        .backgroundColor(this.theme.surfaceNode)
        .border({ width: 1, color: this.theme.strokeCard })
        .margin({ left: 14, bottom: 14 }) // 贴屏幕左下角
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 })).animation({ duration: 200 })) // 出场向下（与搜索栏 y:-8 镜像，同向联动）
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
    }
  }
  @Builder
  topBar() {
    Row() {
      // ★ 0.195.0：返回箭头删除（用户拍板：侧滑返回即可）——左上角改两库互切 ⇄（replacePath 不叠栈）
      // ★ 0.222.0：手机端 ⇄ 改边栏图标（sidebar.svg，点击切出边栏抽屉）；宽屏保持 ⇄ 切单词库
      if (this.windowMode.isTablet) {
        Text('⇄')
          .fontSize(16)
          .fontColor(this.theme.textTertiary)
          .padding({ left: 4, right: 4 })
          .margin({ right: 4 })
          .onClick(() => {
            this.pathStack.replacePath({ name: 'WordBankPage' });
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
      Text('知识库')
        .fontSize(FONT_SIZE_SCREEN_TITLE) // ★ 0.183.0：18→16 对齐 ScreenTitle 规范
        .fontWeight(600)
        .fontColor(this.theme.textPrimary)
        .onClick(() => {
          if (this.windowMode.isTablet) {
            this.pathStack.replacePath({ name: 'WordBankPage' }); // ★ 0.195.0：标题也可点击切换（用户需求，与 ⇄ 同款）
          } else {
            this.openSidebar(); // ★ 0.222.0：手机点标题也切边栏（与边栏图标同款）
          }
        })
      Blank()
        .layoutWeight(1)
      // ★ 0.222.16 用户拍板：两个独立排序按钮并拢为单个「排序」入口（参考单词库右上角 UI）；
      //   点击弹两选项（最新/需复习），点选项只切排序不收起（可连续切换），点遮罩才收；
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
          popupColor: this.theme.surfaceNode,
          radius: 12,
          mask: { color: this.theme.overlayLight },
          onStateChange: (e: PopupStateChangeParam) => {
            this.sortMenuVisible = e.isVisible;
          }
        })
        .onClick(() => {
          this.sortMenuVisible = !this.sortMenuVisible;
        })
      // ★ 0.239.0：宽屏视图切换（grid 四宫格图标 / 默认列表）——复刻单词库同款同位置同交互；
      //   单图标开关式（无 list 图标，靠底色表达状态）；手机端不渲染（既定设计，与单词库一致）
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
        .backgroundColor(this.viewMode.grid ? this.theme.surfaceHover : Color.Transparent)
        .margin({ right: 4 })
        .onClick(() => {
          this.viewMode.grid = !this.viewMode.grid;
        })
      }
      // ★ 0.161.2: card-count settings button — left of "+", visible in both normal & multi-select modes
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
          this.cardCustomInput = this.knowledgeCountStore.knowledgeCount > 2 ? `${this.knowledgeCountStore.knowledgeCount}` : ''; // ★ 0.195.0：>3→>2（快速项改 0/1/2，≥3 即自定义）
          this.cardInputError = '';
          this.cardSettingsVisible = true;
        })
      if (!this.multiSelectMode) {
        // ★ 0.207.0：+ 升级为菜单——anything 导入体系入口（新建卡片/导入/导出）
        // ★ 0.225.0 重构（用户拍板）：系统 bindMenu（灰色不可定制）→ bindPopup 自定义紫字菜单
        //   + 三主项（新建卡片/导入/导出）drill-down 二级格式（导入 5 项/导出 4 项）——复刻 0.218.3 sortMenu 已验证模式
        Button('+')
          .fontSize(20)
          .height(40) // ★ 0.196.6：显式 40vp——导航栏统一规格（UI_GUIDELINES 10.2：以气泡页顶栏为基准）
          .backgroundColor(Color.Transparent)
          .fontColor(this.theme.textPrimary)
          .padding({ left: 8, right: 8 })
          .bindPopup(this.plusMenuVisible, {
            builder: this.kbPlusMenuBuilder(),
            placement: Placement.BottomRight, // ★ 0.239.0：Bottom→BottomRight——弹层右缘对齐按钮右缘、整体在按钮左下方（用户拍板"放到左边去"）
            popupColor: this.theme.surfaceNode,
            radius: 12,
            mask: { color: this.theme.overlayLight },
            onStateChange: (e: PopupStateChangeParam) => {
              this.plusMenuVisible = e.isVisible;
              if (!e.isVisible) {
                this.plusMenuMode = 'main'; // 关闭时复位主级（下次打开从头开始）
              }
            }
          })
          .onClick(() => {
            this.plusMenuMode = 'main';
            this.plusMenuVisible = !this.plusMenuVisible;
          })
      } else {
        // ★ 0.148: multi-select replaces the add button with batch delete
        Button(`删除(${this.selectedIds.length})`)
          .fontSize(14)
          .fontColor(this.theme.danger)
          .backgroundColor(Color.Transparent)
          .padding({ left: 8, right: 8 })
          .onClick(() => {
            this.requestBatchDelete();
          })
      }
    }
    .width('100%')
    .height(56) // ★ 0.196.7：顶栏 Row 40→56——height 含 padding，原 40+padding8/8 把内容区压到 24vp（顶栏比树页高 8vp，Pad 实测）；56=8padding+40内容+8padding 与树页外层 Column frame 等效，与 ChatPage 同步
    .padding({ left: this.isTablet ? 28 : 14, right: 14, top: 8, bottom: 8 }) // ★ 0.195.0：顶栏左/上间距以气泡树信息条为准（left 28/14 双分支 + top 8/right 14，与 ChatPage/单词库同步）
  }

  // ★ 0.161.2: knowledge-card count settings dialog — same pattern as WordBankPage's
  // learnSettingsDialog; default 1 keeps the pre-0.161.2 single-card behaviour
  @Builder
  cardSettingsDialog() {
    Column() {
      Column() {
        Text('知识卡片数量设置')
          .fontSize(FONT_SIZE_SCREEN_TITLE)
          .fontWeight(600)
          .fontColor(this.theme.textPrimary)
        Text('每次复习展示的卡片数，生效于：AI 回复底部复习区、知识卡片提炼等待页')
          .fontSize(12)
          .fontColor(this.theme.textTertiary)
          .margin({ top: 6 })
                  // ★ 0.195.0：布局统一（用户定稿「012+输入框」一行——与全局设置复习 Tab 完全同款）
          Row() {
            Button('0')
              .fontSize(14)
              .width(44)
              .height(40)
              .fontColor(this.knowledgeCountStore.knowledgeCount === 0 ? this.theme.textPrimary : (this.theme.textSecondary))
              .backgroundColor(this.knowledgeCountStore.knowledgeCount === 0 ? this.theme.brandPrimary : Color.Transparent)
              .borderRadius(RADIUS_CONTROL)
              .onClick(() => {
                this.knowledgeCountStore.knowledgeCount = 0;
                this.cardSettingsVisible = false;
              })
            Button('1')
              .fontSize(14)
              .width(44)
              .height(40)
              .fontColor(this.knowledgeCountStore.knowledgeCount === 1 ? this.theme.textPrimary : (this.theme.textSecondary))
              .backgroundColor(this.knowledgeCountStore.knowledgeCount === 1 ? this.theme.brandPrimary : Color.Transparent)
              .borderRadius(RADIUS_CONTROL)
              .margin({ left: 8 })
              .onClick(() => {
                this.knowledgeCountStore.knowledgeCount = 1;
                this.cardSettingsVisible = false;
              })
            Button('2')
              .fontSize(14)
              .width(44)
              .height(40)
              .fontColor(this.knowledgeCountStore.knowledgeCount === 2 ? this.theme.textPrimary : (this.theme.textSecondary))
              .backgroundColor(this.knowledgeCountStore.knowledgeCount === 2 ? this.theme.brandPrimary : Color.Transparent)
              .borderRadius(RADIUS_CONTROL)
              .margin({ left: 8 })
              .onClick(() => {
                this.knowledgeCountStore.knowledgeCount = 2;
                this.cardSettingsVisible = false;
              })
            TextInput({ text: this.cardCustomInput, placeholder: '0~20' })
              .fontSize(14)
              .layoutWeight(1)
              .height(40)
              .padding({ left: 12, right: 12 })
              .borderRadius(RADIUS_CONTROL)
              .backgroundColor(this.theme.surfaceSoft)
              .type(InputType.Number)
              .margin({ left: 8 })
              .onChange((value: string) => {
                this.cardCustomInput = value.replace(/[^0-9]/g, ""); // ★ 0.252.0：即时清洗——剥全角/空格/不可见字符，防合法数字被误判
                this.cardInputError = '';
              })
            Button('确定')
              .fontSize(14)
              .height(40)
              .fontColor(this.theme.textPrimary)
              .backgroundColor(this.theme.brandPrimary)
              .borderRadius(RADIUS_CONTROL)
              .margin({ left: 8 })
              .padding({ left: 14, right: 14 })
              .onClick(() => {
                const cleaned = this.cardCustomInput.replace(/[^0-9]/g, ""); // ★ 0.252.0：提交兜底清洗（双防线）
                const n = cleaned.length > 0 ? parseInt(cleaned, 10) : NaN;
                if (!Number.isNaN(n) && n >= 0 && n <= 20) {
                  this.knowledgeCountStore.knowledgeCount = n;
                  this.cardSettingsVisible = false;
                } else {
                  this.cardInputError = '请输入 0~20 的整数';
                }
              })
          }
          .width('100%')
          .margin({ top: 12 })

        if (this.cardInputError.length > 0) {
          Text(this.cardInputError)
            .fontSize(12)
            .fontColor(this.theme.danger)
            .margin({ top: 6 })
        }
        Button('关闭')
          .fontSize(14)
          .fontColor(this.theme.textSecondary)
          .backgroundColor(Color.Transparent)
          .width('100%')
          .margin({ top: 12 })
          .onClick(() => {
            this.cardSettingsVisible = false;
          })
      }
      .width('86%')
      .borderRadius(RADIUS_NAV)
      .backgroundColor(this.theme.surfaceNode)
      .padding(20)
      .onClick(() => {}) // ★ 0.196.2：消费面板点击防冒泡到遮罩（ClickEvent 无 stopPropagation，空 handler 挡住）
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.theme.overlay)
    .onClick(() => {
      this.cardSettingsVisible = false; // ★ 0.196.2 用户拍板：点空白关闭（同「关闭」按钮）
    })
  }

  // ── ★ 0.200.0 入口 A 配套：「问 AI」二选一面板（底部卡片，暗紫设计语言；点遮罩取消）──
  @Builder
  askAiSheet() {
    Column() {
      Blank()
      Column() {
        // ★ 0.201.4（用户拍板）：删标题「把这张卡片导入气泡去问AI?」与卡片名——用户从「问AI?」进来意图
        //   已明确，两句是废话；直接三按钮开路
        Button('导入气泡对话')
          .fontSize(14)
          .fontColor(this.theme.textPrimary)
          .backgroundColor(this.theme.brandPrimary)
          .borderRadius(RADIUS_CONTROL)
          .width(this.isTablet ? 280 : '100%') // ★ 0.201.2：平板固定 280 居中（手机 100% 不变）
          .margin({ top: 16 })
          .onClick(() => {
            this.startCardImport('import', this.askSheetTitle, this.askSheetDefinition, this.askSheetImages);
          })
        Text('选一个气泡 → 卡片填入它的输入框，补充问题后发送')
          .fontSize(11)
          .fontColor(this.theme.textTertiary)
          .margin({ top: 6 })
        Button('创建子气泡')
          .fontSize(14)
          .fontColor(this.theme.brandSecondary)
          .backgroundColor(Color.Transparent)
          .borderRadius(RADIUS_CONTROL)
          .border({ width: 1, color: this.theme.brandSecondary })
          .width(this.isTablet ? 280 : '100%') // ★ 0.201.2：同上
          .margin({ top: 12 })
          .onClick(() => {
            this.startCardImport('branch', this.askSheetTitle, this.askSheetDefinition, this.askSheetImages);
          })
        Text('选一个父气泡 → 新建子气泡并填入卡片')
          .fontSize(11)
          .fontColor(this.theme.textTertiary)
          .margin({ top: 6 })
        Button('取消')
          .fontSize(14)
          .fontColor(this.theme.textSecondary)
          .backgroundColor(Color.Transparent)
          .width(this.isTablet ? 280 : '100%') // ★ 0.201.2：同上
          .margin({ top: 12 })
          .onClick(() => {
            this.askSheetVisible = false;
          })
      }
      .width(this.isTablet ? 460 : '100%') // ★ 0.201.2：平板固定 460 居中（手机 100% 贴底不变）——用户实测宽屏按钮拉满太长；规范入 UI_GUIDELINES「模态弹窗与操作按钮」
      .borderRadius(RADIUS_NAV) // ★ 0.201.2：四角圆角（宽屏居中浮岛感；手机贴底时下圆角贴屏不可见无副作用）
      .backgroundColor(this.theme.surfaceNode)
      .border({ width: 1, color: this.theme.strokeCard })
      .padding({ left: 20, right: 20, top: 20, bottom: 28 })
      .onClick(() => {}) // 消费面板点击防冒泡到遮罩
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.overlay)
    .onClick(() => {
      this.askSheetVisible = false;
    })
  }

  // ★ 0.148: editor dialog — add & edit share it; tap the mask to dismiss
  // ★ 0.210.2：根改 Stack（原 Column+Center 布局流里，mini 遮罩 100% 尺寸解析受兄弟元素影响
  //   不铺满——dump 实锤 [520,1049] 起；Stack 子项百分比铺满语义可靠，双弹窗层互不干扰）
  @Builder
  editorDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Scroll() { // ★ 0.230.0 B11 键盘适配：窗口 RESIZE 压矮时弹窗收缩可滚，保存滚动可达（同词库编辑器）
      Column() {
        Text(this.editorIsAdd ? '新增知识卡' : '编辑知识卡')
          .fontSize(FONT_SIZE_SCREEN_TITLE)
          .fontWeight(600)
          .fontColor(this.theme.textPrimary)
        TextInput({ text: this.editorTitle, placeholder: '标题（必填）' })
          .fontSize(14)
          .width('100%')
          .height(40)
          .margin({ top: 16 })
          .padding({ left: 12, right: 12 })
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(this.theme.surfaceSoft)
          .onChange((value: string) => {
            this.editorTitle = value;
          })
          // ★ 0.283.1：标题框 Ctrl+V 贴图（用户需求——标题图区也要能贴：标题框聚焦时 Ctrl+V
          //   直贴 editorTitleImages；文本粘贴归 TextInput 原生行为恒放行，同内容框策略）
          .onKeyPreIme((event: KeyEvent): boolean => {
            if (event.keyCode === 2038 && event.type === KeyType.Down) {
              let ctrlV = false;
              try {
                ctrlV = event.getModifierKeyState ? event.getModifierKeyState(['Ctrl']) : false;
              } catch (err) {
                ctrlV = false;
              }
              if (ctrlV) {
                this.pasteEditorImageFromClipboard(true); // isTitle=true → 标题图区
              }
            }
            return false; // 恒放行：文本粘贴归 TextInput 原生行为，贴图走旁路
          })
        // ── ★ 0.210.0：标题图区（Anki 图对图——题面插图；结构同下方内容图区，紧凑一号）──
        Column() {
          if (this.editorTitleImages.length > 0) {
            Scroll() {
              Row({ space: 8 }) {
                ForEach(this.editorTitleImages, (img: string, idx: number) => {
                  Stack({ alignContent: Alignment.TopEnd }) {
                    Image(img)
                      .height(48)
                      .width(72)
                      .objectFit(ImageFit.Cover)
                      .borderRadius(RADIUS_CONTROL)
                      .onClick(() => {
                        // ★ 0.211.2：四场景统一——编辑弹窗缩略也走全屏查看器（单击放大+可缩放）
                        this.openImagePreview([img], 0);
                      })
                    Text('×')
                      .fontSize(13)
                      .fontWeight(600)
                      .fontColor(this.theme.textPrimary)
                      .backgroundColor(this.theme.danger)
                      .width(18)
                      .height(18)
                      .borderRadius(9)
                      .textAlign(TextAlign.Center)
                      .offset({ x: -2, y: 2 })
                      .onClick(() => {
                        this.editorTitleImages.splice(idx, 1);
                        this.editorTitleImages = [...this.editorTitleImages];
                      })
                  }
                  .height(48)
                  .width(72)
                }, (img: string) => img)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
            .margin({ bottom: 8 })
          }
          if (this.editorTitleImages.length < 9) {
            // ★ 0.210.1：彩色 emoji 🖼️ → 华为风格单色透明 svg（0.190.2 铁律：图标用 svg 资源不用字符；用户拍板"透明的样式非常好看"）
            Row({ space: 5 }) {
              Image($r('app.media.image'))
                .width(14)
                .height(14)
                .objectFit(ImageFit.Contain)
              Text('标题图片' + (this.editorTitleImages.length > 0 ? `（${this.editorTitleImages.length}/9）` : ''))
                .fontSize(13) // ★ 0.211.0 用户拍板：与「添加图片」颜色字号全对齐（原紫 12 不一致）
                .fontColor(this.theme.textSecondary)
            }
            .alignSelf(ItemAlign.Start)
            .onClick(() => {
              this.selectEditorTitleImage();
            })
          }
        }
        .width('100%')
        .margin({ top: 8 })
        TextArea({ text: this.editorDefinition, placeholder: '内容（选填）' })
          .fontSize(14)
          .width('100%')
          .height(96)
          .margin({ top: 8 })
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(this.theme.surfaceSoft)
          .onChange((value: string) => {
            this.editorDefinition = value;
          })
          // ★ 0.283.0：Ctrl+V 贴图（PC 需求——知识卡片制作弹窗直贴截图，KEYCODE_V=2038 实锤；
          //   ChatPage 主输入框同款旁路策略：放行文本粘贴，图片异步贴入内容图区，防重入兜底）
          .onKeyPreIme((event: KeyEvent): boolean => {
            if (event.keyCode === 2038 && event.type === KeyType.Down) {
              let ctrlV = false;
              try {
                ctrlV = event.getModifierKeyState ? event.getModifierKeyState(['Ctrl']) : false;
              } catch (err) {
                ctrlV = false;
              }
              if (ctrlV) {
                this.pasteEditorImageFromClipboard();
              }
            }
            return false; // 恒放行：文本粘贴归 TextArea 原生行为，贴图走旁路
          })
        // ── ★ 0.202.2：标签区 chip 化（用户拍板：弃逗号输入——大小写/分隔符心智负担；同提炼页交互）──
        Column() {
          Text(parseTags(this.editorTags).length > 0 ? '标签（点 × 删除 · 长按修改）' : '标签')
            .fontSize(11)
            .fontColor(this.theme.textTertiary)
            .alignSelf(ItemAlign.Start)
            .margin({ bottom: 6 })
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(parseTags(this.editorTags), (t: string) => {
              Row({ space: 4 }) {
                Text(t)
                  .fontSize(11)
                  .fontColor(this.theme.brandSecondary)
                Text('×')
                  .fontSize(12)
                  .fontColor(this.theme.textTertiary)
                  .onClick(() => {
                    this.removeEditorTag(t);
                  })
              }
              .height(24)
              .padding({ left: 10, right: 8 })
              .borderRadius(6)
              .border({ width: 1, color: this.theme.brandSecondary })
              .margin({ right: 6, bottom: 6 })
              .gesture(
                LongPressGesture({ duration: 500 })
                  .onAction(() => {
                    this.openEditorTagEdit(t);
                  })
              )
            }, (t: string) => t)
            Text('+ 添加')
              .fontSize(11)
              .height(24)
              .padding({ left: 10, right: 10 })
              .borderRadius(6)
              .fontColor(this.theme.textSecondary)
              .border({ width: 1, color: this.theme.strokeCard, style: BorderStyle.Dashed })
              .margin({ right: 6, bottom: 6 })
              .onClick(() => {
                this.openEditorTagEdit('');
              })
          }
          .width('100%')
        }
        .width('100%')
        .margin({ top: 10 })
        // ★ 0.202.1: 多图编辑区——缩略图横排（每张可删）+「添加图片」常驻（上限 9）；
        //   提交时机同 title/definition 草稿模式（保存才落库，取消丢弃）
        Column() {
          if (this.editorImages.length > 0) {
            Scroll() {
              Row({ space: 8 }) {
                ForEach(this.editorImages, (img: string, idx: number) => {
                  Stack({ alignContent: Alignment.TopEnd }) {
                    Image(img)
                      .height(56)
                      .width(84)
                      .objectFit(ImageFit.Cover)
                      .borderRadius(RADIUS_CONTROL)
                      .onClick(() => {
                        this.openImagePreview([img], 0); // ★ 0.211.2：四场景统一走全屏查看器
                      })
                    Text('×')
                      .fontSize(13)
                      .fontWeight(600)
                      .fontColor(this.theme.textPrimary)
                      .backgroundColor(this.theme.danger)
                      .width(18)
                      .height(18)
                      .borderRadius(9)
                      .textAlign(TextAlign.Center)
                      .offset({ x: -2, y: 2 })
                      .onClick(() => {
                        this.editorImages.splice(idx, 1);
                        this.editorImages = [...this.editorImages];
                      })
                  }
                  .height(56)
                  .width(84)
                }, (img: string) => img)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
            .margin({ bottom: 8 })
          }
          if (this.editorImages.length < 9) {
            // ★ 0.210.1：彩色 emoji 🖼️ → 华为风格单色透明 svg（同标题图区）
            Row({ space: 5 }) {
              Image($r('app.media.image'))
                .width(14)
                .height(14)
                .objectFit(ImageFit.Contain)
              Text('添加图片' + (this.editorImages.length > 0 ? `（${this.editorImages.length}/9）` : ''))
                .fontSize(13)
                .fontColor(this.theme.textSecondary)
            }
            .alignSelf(ItemAlign.Start)
            .onClick(() => {
              this.selectEditorImage();
            })
          }
        }
        .width('100%')
        .margin({ top: 10 })
        Row({ space: 12 }) { // ★ 0.230.0：等宽铁律姿势（0.197.3——margin 参与 layoutWeight 分配挤窄保存 12vp，审计实锤差 30px）
          Button('取消')
            .fontSize(14)
            .fontColor(this.theme.textSecondary)
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onClick(() => {
              this.editorVisible = false;
            })
          Button('保存')
            .fontSize(14)
            .fontColor(this.theme.textPrimary)
            .backgroundColor(this.theme.brandPrimary)
            .borderRadius(RADIUS_CONTROL)
            .layoutWeight(1)
            .onClick(() => {
              this.saveEditor();
            })
        }
        .width('100%')
        .margin({ top: 20 })
      }
      .width(this.isTablet ? 520 : '86%') // ★ 0.201.2：平板固定 520（86% 在宽屏超宽、双按钮被拉长——用户实测）；规范入 UI_GUIDELINES「模态弹窗与操作按钮」
       .borderRadius(RADIUS_NAV)
       .backgroundColor(this.theme.surfaceNode)
       .padding(20)
       }
       .constraintSize({ maxHeight: '96%' }) // ★ 0.230.0 B11：Scroll 高度约束（键盘 RESIZE 压矮窗口时收缩可滚）
       // ── ★ 0.202.2：标签 mini 编辑弹窗（长按改/自定义加）──
      // ★ 0.210.1 修复「下面的方框一直往下」两连：①原 Blank() 把弹窗推到遮罩最底部（键盘避让
      //   反复触发一路下沉）②挂编辑弹窗内部时 height('100%') 参照自适应高度父——无参照、永不安居
      //   （真机 dump 实锤：标题 y=1640 贴屏底）。上移到全屏遮罩层与编辑弹窗同级：height('100%')
      //   有全屏参照 → justifyContent Center 标准居中；后绘制保持在上层，遮罩点击关闭不变
      if (this.tagEditVisible) {
        Column() {
          Column() {
            Text(this.tagEditOld.length === 0 ? '添加标签' : '修改标签')
              .fontSize(14)
              .fontWeight(600)
              .fontColor(this.theme.textPrimary)
              .margin({ bottom: 10 })
            TextInput({ text: this.tagEditNew, placeholder: '标签名（2~6 字最佳）' })
              .fontSize(14)
              .width('100%')
              .height(40)
              .padding({ left: 12, right: 12 })
              .borderRadius(RADIUS_CONTROL)
              .backgroundColor(this.theme.surfaceSoft)
              .onChange((v: string) => {
                this.tagEditNew = v;
              })
            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .fontColor(this.theme.textSecondary)
                .backgroundColor(Color.Transparent)
                .onClick(() => {
                  this.tagEditVisible = false;
                })
              Button('确定')
                .layoutWeight(1)
                .backgroundColor(this.theme.brandPrimary)
                .fontColor(this.theme.textPrimary)
                .onClick(() => {
                  this.commitEditorTagEdit();
                })
            }
            .width('100%')
            .margin({ top: 14 })
          }
          .width('86%')
          .padding(18)
          .borderRadius(RADIUS_NAV)
          .backgroundColor(this.theme.surfaceNode)
          .border({ width: 1, color: this.theme.strokeCard })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.theme.overlay)
        .onClick(() => {
          this.tagEditVisible = false;
        })
      }
    }
    .width('100%')
    .height('100%')

    .backgroundColor(this.theme.overlay)
  }

  // ★ 0.211.0：列表图片全屏查看器——★ 0.211.2 四场景统一载体（列表标题图/内容图+编辑弹窗标题图/内容图
  //   全部走本查看器）：①单击图片关闭（0.173.x 铁律：count:1 手动判双击，300ms 内第二击=缩放，
  //   否则延迟 320ms 关闭）②双击 1×↔2.5× 缓动动画（用户报"放大太快"）③PC 鼠标滚轮缩放（onMouse
  //   scrollDelta）④捏合 1~4× 跟手 ⑤右滑退出=系统侧滑+onBackPressed 拦截（原 PanGesture 与
  //   Swiper 翻页手势竞争恒失灵→系统返回手势透传直接退出知识库页——用户实测"直接退到气泡树"）；
  //   × 按钮关闭保留，退出方式三重冗余
  @Builder
  imagePreviewViewer() {
    if (this.previewVisible) {
      Stack() {
        Swiper() {
          ForEach(this.previewImages, (url: string) => {
            Image(url)
              .objectFit(ImageFit.Contain)
              .width('100%')
              .height('100%')
              .scale({ x: this.previewScale, y: this.previewScale })
              // ★ 0.211.3：UI 层 MouseEvent 无 scrollDelta 属性（编译实锤）——滚轮缩放暂缓，PC 用双击缩放
              .gesture(
                PinchGesture({ fingers: 2 })
                  .onActionUpdate((event: GestureEvent) => {
                    this.previewScale = Math.min(4, Math.max(1, this.previewScale * event.scale));
                  })
                  .onActionEnd(() => {
                    if (this.previewScale < 1) {
                      this.applyPreviewScale(1);
                    }
                  })
              )
              .gesture(
                TapGesture({ count: 1 })
                  .onAction(() => {
                    this.previewTapHandled();
                  })
              )
          }, (url: string) => url)
        }
        .index(this.previewIndex)
        .indicator(true)
        .backgroundColor(Color.Black)

        Button('×')
          .fontSize(24)
          .fontColor(this.theme.textPrimary)
          .backgroundColor(Color.Transparent)
          .position({ x: 20, y: 20 })
          .onClick(() => {
            this.previewVisible = false;
          })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
    }
  }

  // ★ 0.160: fullscreen preview of the editor image — tap anywhere to close
  // ★ 0.211.2：已废弃删除——编辑弹窗预览统一走 imagePreviewViewer（四场景同一查看器）

  // ★ 0.148: single-delete confirm dialog — with the session-level
  // "本次会话内不再提示" checkbox (spec 2.1.2)
  @Builder
  deleteConfirmDialog() {
    Column() {
      Column() {
        Text('确认删除该条目？')
          .fontSize(FONT_SIZE_SCREEN_TITLE)
          .fontWeight(600)
          .fontColor(this.theme.textPrimary)
        Row() {
          Image(this.deleteConfirmNoRemind ? $r('app.media.checkbox_on') : $r('app.media.checkbox_off')) // ★ 0.212.0：☑/☐ 换 svg
            .width(20)
            .height(20)

            .onClick(() => {
              this.deleteConfirmNoRemind = !this.deleteConfirmNoRemind;
            })
          Text('本次会话内不再提示')
            .fontSize(13)
            .fontColor(this.theme.textSecondary)
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
            .fontColor(this.theme.textSecondary)
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onClick(() => {
              this.deleteConfirmVisible = false;
            })
          Button('删除')
            .fontSize(14)
            .fontColor(this.theme.textPrimary)
            .backgroundColor(this.theme.danger)
            .borderRadius(RADIUS_CONTROL)
            .layoutWeight(1)
            .margin({ left: 12 })
            .onClick(() => {
              this.confirmDeleteCard();
            })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      // ★ 0.212.2 用户拍板（PC 截图实锤）：确认类弹窗 PC 上 86% 被拉得太宽、双按钮被拉长太难看——
      //   平板/PC 固定 400（比编辑弹窗 520 窄一档，对话框惯例），手机维持 86%；规格入 UI_GUIDELINES
      .width(this.isTablet ? 400 : '86%')
      .borderRadius(RADIUS_NAV)
      .backgroundColor(this.theme.surfaceNode)
      .padding(20)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.theme.overlay)
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
          .fontColor(this.theme.textPrimary)
        Row() {
          Button('取消')
            .fontSize(14)
            .fontColor(this.theme.textSecondary)
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onClick(() => {
              this.batchConfirmVisible = false;
            })
          Button('删除')
            .fontSize(14)
            .fontColor(this.theme.textPrimary)
            .backgroundColor(this.theme.danger)
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
      .backgroundColor(this.theme.surfaceNode)
      .padding(20)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.theme.overlay)
  }

  // ============================================================
  // ★ 0.207.0：文件夹 / 导入 / 导出 —— 方法集
  // ============================================================

  /** 当前目录名链（根→…→当前）——面包屑/导出命名用 */
  @Computed
  get currentChain(): KFolder[] {
    return folderChain(this.knowledgeBank, this.folderNav.folderId);
  }

  folderParentId(): string {
    const ch = this.currentChain;
    return ch.length > 0 ? ch[ch.length - 1].parentId : '';
  }

  folderFullPath(f: KFolder): string {
    return folderChain(this.knowledgeBank, f.id).map((x: KFolder): string => x.name).join(' › ');
  }


  openFolderRename(f: KFolder): void {
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

    // ★ 0.221.4：边栏树右键「新建文件夹」——父级=右键的文件夹（folderActionId）
    if (this.folderNav.folderAction === 'newfolder') {
      addFolder(this.knowledgeBank, nm, this.folderNav.folderActionId);
      this.folderNav.folderAction = '';
      this.folderNav.folderActionId = '';
      this.folderDialogVisible = false;
      return;
    }
    if (this.folderDialogIsRename) {
      renameFolder(this.knowledgeBank, this.folderDialogTargetId, nm);
    } else {
      addFolder(this.knowledgeBank, nm, this.folderNav.folderId);
      const tp: Record<string, string> = {};
      track(this.getUIContext().getHostContext() as Context, 'folder_create', tp);
    }
    this.folderDialogVisible = false;
  }

  requestDeleteFolder(f: KFolder): void {
    deleteFolder(this.knowledgeBank, f.id);
    if (this.folderNav.folderId === f.id) {
      this.folderNav.folderId = this.folderParentId();
    }
    this.showToast(`已删除「${f.name}」——卡片已移到上一级`);
  }


  /** ★ 0.221.0：folderPicker 标题（文件夹移动/复制 与 卡片移动/复制 分流） */
  folderPickerTitle(): string {
    if (this.folderNav.folderAction === 'move') {
      return '移动文件夹到…';
    }
    if (this.folderNav.folderAction === 'copy') {
      return this.folderNav.folderActionId === '' ? '复制根目录全部内容到…' : '复制文件夹到…';
    }
    return this.moveOrCopyMode === 'copy' ? `复制 ${this.selectedIds.length} 张到…` : `移动 ${this.selectedIds.length} 张到…`;
  }

  /** ★ 0.221.0：按 id 取文件夹名 */
  folderNameById(folderId: string): string {
    const f = this.knowledgeBank.folders.find((x: KFolder): boolean => x.id === folderId);
    return f === undefined ? '' : f.name;
  }
  /** ★ 0.222.1：移动/复制目标选择器的树形目录（DFS 层级 + 折叠 + 排除源文件夹） */
  /** ★ 0.222.17：补 isLast/ancestorIds/ancestorHasNext（静态树形连接线；弹窗无路径高亮） */
  folderPickerTreeItems(): KFolderTreeItem[] {
    const out: KFolderTreeItem[] = [];
    const walk = (parentId: string, depth: number, ancestorIds: string[], ancestorHasNext: boolean[]): void => {
      const all = this.knowledgeBank.folders
        .filter((f: KFolder): boolean => f.parentId === parentId)
        .sort((a: KFolder, b: KFolder): number => b.createdAt - a.createdAt);
      // ★ 0.222.14：仅「移动」排除源文件夹自身（避免移到自己下面形成环）；「复制」全显示（含源自身/子孙）
      const kids = all.filter((f: KFolder): boolean => !(this.folderNav.folderAction === 'move' && f.id === this.folderNav.folderActionId));
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

  /** ★ 0.222.1：目标选择器里文件夹是否有子文件夹 */
  pickerHasChildren(folderId: string): boolean {
    for (let i = 0; i < this.knowledgeBank.folders.length; i++) {
      if (this.knowledgeBank.folders[i].parentId === folderId) {
        return true;
      }
    }
    return false;
  }

  /** ★ 0.222.1：目标选择器文件夹是否折叠 */
  isPickerCollapsed(folderId: string): boolean {
    return this.pickerCollapsedFolderIds.indexOf(folderId) >= 0;
  }

  /** ★ 0.222.1：切换目标选择器文件夹折叠（string[] 替换引用触发重渲染） */
  togglePickerCollapse(folderId: string): void {
    if (this.isPickerCollapsed(folderId)) {
      this.pickerCollapsedFolderIds = this.pickerCollapsedFolderIds.filter((id: string): boolean => id !== folderId);
    } else {
      this.pickerCollapsedFolderIds = [...this.pickerCollapsedFolderIds, folderId];
    }
  }
  /** ★ 0.221.0：确认级联删除文件夹 */
  confirmFolderDelete(): void {
    const fid = this.folderNav.folderActionId;
    const deleted = deleteFolderCascade(this.knowledgeBank, fid);
    if (this.folderNav.folderId === fid) {
      this.folderNav.folderId = this.folderParentId();
    }
    this.folderNav.folderAction = '';
    this.folderNav.folderActionId = '';
    this.showToast(`已删除文件夹及 ${deleted} 张卡片`);
  }

  // ★ 0.222.13: 清空根目录（全部卡片+全部文件夹；根目录「全部卡片」入口保留）（边栏根目录右键/长按「删除」引发）
  confirmRootDelete(): void {
    const n = clearRootFolder(this.knowledgeBank);
    this.folderNav.folderAction = '';
    this.folderNav.folderActionId = '';
    this.folderNav.folderId = '';
    this.showToast(`已清空全部 ${n} 张卡片与全部文件夹`);
  }

  /** ★ 0.221.0：取消文件夹操作（关闭弹窗 + 清请求） */
  cancelFolderAction(): void {
    this.folderNav.folderAction = '';
    this.folderNav.folderActionId = '';
    this.folderNav.folderActionName = '';
  }

  /** ★ 0.221.0：确认重命名文件夹（边栏树触发） */
  confirmFolderRename(): void {
    const nm = this.folderNav.folderActionName.trim();
    if (nm.length === 0) {
      this.showToast('名称不能为空');
      return;
    }
    renameFolder(this.knowledgeBank, this.folderNav.folderActionId, nm);
    this.folderNav.folderAction = '';
    this.folderNav.folderActionId = '';
    this.folderNav.folderActionName = '';
  }  /** 移动/复制确认（folderPicker 行点击） */
  confirmFolderTarget(folderId: string): void {

    // ★ 0.221.0：文件夹移动/复制（边栏树右键触发）——与卡片移动/复制分流
    if (this.folderNav.folderAction === 'move' || this.folderNav.folderAction === 'copy') {
      const fid = this.folderNav.folderActionId;
      if (this.folderNav.folderAction === 'copy') {
        let n = 0;
        if (fid === '') {
          if (folderId === '') {
            this.showToast('不能复制根目录到根目录');
            this.folderNav.folderAction = '';
            this.folderNav.folderActionId = '';
            this.folderPickerVisible = false;
            return;
          }
          n = copyRootFolder(this.knowledgeBank, folderId);
          this.showToast(`已复制根目录全部内容（含 ${n} 张卡片）`);
        } else {
          n = copyFolder(this.knowledgeBank, fid, folderId);
          this.showToast(`已复制文件夹（含 ${n} 张卡片）`);
        }
      } else {
        const ok = moveFolder(this.knowledgeBank, fid, folderId);
        if (!ok) {
          this.showToast('不能移动到自身或其子文件夹');
          this.folderNav.folderAction = '';
          this.folderNav.folderActionId = '';
          this.folderPickerVisible = false;
          return;
        }
        this.showToast('已移动文件夹');
      }
      this.folderNav.folderAction = '';
      this.folderNav.folderActionId = '';
      this.folderPickerVisible = false;
      return;
    }    const ids = [...this.selectedIds];
    if (this.moveOrCopyMode === 'copy') {
      const n = copyCards(this.knowledgeBank, ids, folderId);
      const tp: Record<string, string> = {}; tp['count'] = `${n}`; // ArkTS 铁律：空对象+键赋值（0.206 挂点同款）
      track(this.getUIContext().getHostContext() as Context, 'card_copy', tp);
      this.showToast(`已复制 ${n} 张（新卡从零复习）`);
    } else {
      moveCards(this.knowledgeBank, ids, folderId);
      const tp: Record<string, string> = {}; tp['count'] = `${ids.length}`;
      track(this.getUIContext().getHostContext() as Context, 'card_move', tp);
      this.showToast(`已移动 ${ids.length} 张`);
    }
    this.folderPickerVisible = false;
    this.exitMultiSelect();
  }

  /** 批量导入第一步：选文件 → 解析 → 预览弹窗（★ 0.207.1 加 xlsx 分流） */
  async pickImportFile(fmt: string): Promise<void> {
    // ★ 0.248.3：导入/导出守卫（上架合规——用户拍板必须登录）
    if (!requireLoginForCloud()) {
      return;
    }

    try {
      const doc = new picker.DocumentViewPicker();
      const selOpt = new picker.DocumentSelectOptions();
      // ★ 0.225.0：菜单分项参数化——每格式只显自己后缀（语义清晰；统一三后缀的旧版随 bindMenu 退役）
      selOpt.fileSuffixFilters = ['.' + fmt];
      selOpt.maxSelectNumber = 1;
      const uris: string[] = await doc.select(selOpt);
      if (uris.length === 0) {
        return;
      }
      const uri = uris[0];
      let rows: ImportRow[] = [];
      let parsedFmt = 'txt'; // ★ 0.225.0：改名防与参数 fmt 撞名（参数=菜单格式、本变量=按文件后缀实判格式）
      if (uri.toLowerCase().endsWith('.xlsx')) {
        parsedFmt = 'xlsx';
        rows = await readXlsxRows(uri);
      } else {
        parsedFmt = uri.toLowerCase().endsWith('.csv') ? 'csv' : 'txt';
        rows = parseTextToRows(readTextFile(uri), parsedFmt);
      }
      if (rows.length === 0) {
        this.showToast('没解析出卡片：每行需「标题 + 分隔符 + 背面」（xlsx 取 A/B/C 三列）');
        return;
      }
      this.importRows = rows;
      this.importFormat = parsedFmt;
      this.importFileName = uri.substring(uri.lastIndexOf('/') + 1);
      this.importPreviewVisible = true;
    } catch (_e) {
      this.showToast('选文件失败');
    }
  }

  // ============================================================
  // ★ 0.207.1：DagPack 导出 / 导入
  // ============================================================

  /** 导出 DagPack：rootFolderId=文件夹 id（该子树）或 ''（整库）；文件名取文件夹名 */
  async exportDagPack(rootFolderId: string): Promise<void> {
    // ★ 0.248.3：导入/导出守卫（上架合规——用户拍板必须登录）
    if (!requireLoginForCloud()) {
      return;
    }

    try {
      const p = buildKnowledgePack(this.knowledgeBank, rootFolderId);
      const json = packToJson(p);
      const chain = folderChain(this.knowledgeBank, rootFolderId);
      const baseName = chain.length === 0 ? '知识库' : chain[chain.length - 1].name;
      const saver = new picker.DocumentViewPicker();
      const saveOpt = new picker.DocumentSaveOptions();
      saveOpt.newFileNames = [`DAGAI_${baseName}.dagpack`];
      const uris: string[] = await saver.save(saveOpt);
      if (uris.length === 0) {
        return;
      }
      const f = fileIo.openSync(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, json);
      fileIo.closeSync(f);
      const tp: Record<string, string> = {}; tp['folders'] = `${p.folders.length}`; tp['cards'] = `${p.cards.length}`;
      track(this.getUIContext().getHostContext() as Context, 'export_dagpack', tp);
      this.showToast(`已导出 ${p.folders.length} 个文件夹 / ${p.cards.length} 张卡 → DagPack`);
    } catch (_e) {
      this.showToast('导出失败');
    }
  }

  /** DagPack 导入第一步：选文件 → 解析 → 勾选树弹窗（默认全选） */
  async pickPackFile(): Promise<void> {
    // ★ 0.248.3：导入/导出守卫（上架合规——用户拍板必须登录）
    if (!requireLoginForCloud()) {
      return;
    }

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
      if (p === undefined) {
        this.showToast('不是有效的 DagPack 知识库包（v1）');
        return;
      }
      this.packData = p;
      this.packSel = packChildFolders(p, '').map((f: PackFolder): string => f.refId); // 默认全选
      this.packRootCardsSel = true;
      this.packFileName = uris[0].substring(uris[0].lastIndexOf('/') + 1);
      this.packPreviewVisible = true;
    } catch (_e) {
      this.showToast('选文件失败');
    }
  }

  togglePackSel(refId: string): void {
    if (this.packSel.includes(refId)) {
      this.packSel = this.packSel.filter((x: string): boolean => x !== refId);
    } else {
      this.packSel = [...this.packSel, refId];
    }
  }

  /** ★ 0.207.1：弹窗辅助——包内路径名 / 子树卡数 / 根级散卡数 */
  packFolderPathName(refId: string): string {
    return packFolderPath(this.packData, refId);
  }

  packSubtreeCardCount(refId: string): number {
    return packCardCount(this.packData, refId);
  }

  packRootCardCount(): number {
    return packCardCount(this.packData, '');
  }

  /** 勾选确认 → 入库：新子树挂当前文件夹（绝不合并现有目录——同名并存，用户可自移） */
  confirmPackImport(): void {
    const p = this.packData;
    // 纳入 refs = 各勾选顶层 ref 的子树并集
    const inRefs: Set<string> = new Set<string>();
    for (let i = 0; i < this.packSel.length; i++) {
      const sub = packSubtreeRefs(p, this.packSel[i]);
      for (let j = 0; j < sub.length; j++) {
        inRefs.add(sub[j]);
      }
    }
    // refId → 新库 folderId 映射（包根 '' → 当前文件夹；parentRef 已映射才建——固定点循环防乱序）
    const idMap: Map<string, string> = new Map<string, string>();
    idMap.set('', this.folderNav.folderId);
    let guard = 0;
    while (idMap.size < inRefs.size + 1 && guard < 64) {
      guard++;
      for (let i = 0; i < p.folders.length; i++) {
        const pf = p.folders[i];
        if (!inRefs.has(pf.refId) || idMap.has(pf.refId)) {
          continue;
        }
        if (idMap.has(pf.parentRef)) {
          idMap.set(pf.refId, addFolder(this.knowledgeBank, pf.name, idMap.get(pf.parentRef) ?? ''));
        }
      }
    }
    // 卡片入库（记忆字段清零=新卡；images base64 直接延续）
    const now = Date.now();
    let n = 0;
    for (let i = 0; i < p.cards.length; i++) {
      const pc = p.cards[i];
      const target = idMap.get(pc.folderRef);
      if (target === undefined) {
        continue; // 所在文件夹未勾选 → 跳过
      }
      if (pc.folderRef === '' && !this.packRootCardsSel) {
        continue; // 根级散卡未勾
      }
      const imgs = pc.images.length > 0 ? JSON.stringify(pc.images) : '';
      const tImgs = pc.titleImages !== undefined && pc.titleImages.length > 0 ? JSON.stringify(pc.titleImages) : ''; // ★ 0.210.0：旧包无字段 → 无标题图
      addKnowledgeCard(this.knowledgeBank, new KnowledgeCard('', pc.title, pc.definition, '', now + n,
        0, 0, 0, 0, pc.tags, imgs, target, tImgs));
      n++;
    }
    const tp: Record<string, string> = {}; tp['format'] = 'dagpack'; tp['count'] = `${n}`;
    track(this.getUIContext().getHostContext() as Context, 'batch_import', tp);
    this.showToast(`已导入 ${n} 张卡（新子树挂当前文件夹）`);
    this.packPreviewVisible = false;
  }

  /** 预览确认 → 入库（当前文件夹） */
  confirmImport(): void {
    const now = Date.now();
    let n = 0;
    for (let i = 0; i < this.importRows.length; i++) {
      const r = this.importRows[i];
      addKnowledgeCard(this.knowledgeBank, new KnowledgeCard('', r.title, r.definition, '', now + i,
        0, 0, 0, 0, r.tags, '', this.folderNav.folderId));
      n++;
    }
    const tp: Record<string, string> = {}; tp['format'] = this.importFormat; tp['count'] = `${n}`;
    track(this.getUIContext().getHostContext() as Context, 'batch_import', tp);
    this.showToast(`已导入 ${n} 张`);
    this.importPreviewVisible = false;
  }
  // ★ 0.225.0：TXT 导出（用户拍板菜单四格式）——复刻 doExportCsv 全链（当前文件夹语义+保存选择器+写入校验）
  async doExportTxt(): Promise<void> {
    // ★ 0.248.3：导入/导出守卫（上架合规——用户拍板必须登录）
    if (!requireLoginForCloud()) {
      return;
    }

    try {
      const cards = this.filteredCards;
      if (cards.length === 0) {
        this.showToast('当前没有卡片可导出');
        return;
      }
      const names = this.currentChain.map((x: KFolder): string => x.name).join('/');
      const scopeName = names.length === 0 ? '知识库根目录' : names;
      const txt = cardsToTxt(cards, scopeName);
      const saver = new picker.DocumentViewPicker();
      const saveOpt = new picker.DocumentSaveOptions();
      saveOpt.newFileNames = ['DAGAI_知识库.txt'];
      const uris: string[] = await saver.save(saveOpt);
      if (uris.length === 0) {
        return;
      }
      const f = fileIo.openSync(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, txt);
      fileIo.closeSync(f);
      this.showToast(`已导出 ${cards.length} 张 → TXT`);
    } catch (_e) {
      this.showToast('导出失败');
    }
  }

  // ★ 0.225.0：XLSX 导出（用户拍板菜单四格式）——cardsToXlsxBuffer（ExcelJS writeBuffer）+同款保存链
  async doExportXlsx(): Promise<void> {
    // ★ 0.248.3：导入/导出守卫（上架合规——用户拍板必须登录）
    if (!requireLoginForCloud()) {
      return;
    }

    try {
      const cards = this.filteredCards;
      if (cards.length === 0) {
        this.showToast('当前没有卡片可导出');
        return;
      }
      const buf = await cardsToXlsxBuffer(cards);
      const saver = new picker.DocumentViewPicker();
      const saveOpt = new picker.DocumentSaveOptions();
      saveOpt.newFileNames = ['DAGAI_知识库.xlsx'];
      const uris: string[] = await saver.save(saveOpt);
      if (uris.length === 0) {
        return;
      }
      const f = fileIo.openSync(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, buf);
      fileIo.closeSync(f);
      this.showToast(`已导出 ${cards.length} 张 → XLSX`);
    } catch (_e) {
      this.showToast('导出失败');
    }
  }

  // ============================================================
  // ★ 0.207.0：builders——面包屑 / 文件夹弹窗 / 目标选择 / 导入预览
  // ============================================================
  // ★ 0.225.0：+ 菜单 builder（无参直读状态 0.190.1 铁律）——三主项 drill-down：
  //   main=新建卡片/导入›/导出›；import=DAG/APKG/TXT/CSV/XLSX；export=DAG/TXT/CSV/XLSX。
  //   选项紫字 this.theme.brandSecondary（用户拍板「变紫色」）；返回行 this.theme.textTertiary；样式复刻 sortMenu 规格
  // ★ 0.239.0 双库统一规格（用户拍板）：全部菜单项删 .width('100%')（弹层宽度按最长项文字自适应收窄，
  //   不再铺满可用宽）；padding 上下 12→10/左右 16→14（对齐单词库系统菜单观感）；Column 左对齐
  @Builder
  kbPlusMenuBuilder() {
    Column() {
      if (this.plusMenuMode === 'main') {
        Text('新建卡片')
          .fontSize(14)
          .fontColor(this.theme.brandSecondary)
          .padding({ top: 10, bottom: 10, left: 14, right: 14 })
          .onClick(() => {
            this.plusMenuVisible = false;
            this.openAddEditor();
          })
        Divider().color(this.theme.strokeCard)
        Text('导入 ›')
          .fontSize(14)
          .fontColor(this.theme.brandSecondary)
          .padding({ top: 10, bottom: 10, left: 14, right: 14 })
          .onClick(() => {
            this.plusMenuMode = 'import';
          })
        Divider().color(this.theme.strokeCard)
        Text('导出 ›')
          .fontSize(14)
          .fontColor(this.theme.brandSecondary)
          .padding({ top: 10, bottom: 10, left: 14, right: 14 })
          .onClick(() => {
            this.plusMenuMode = 'export';
          })
      } else if (this.plusMenuMode === 'import') {
        Text('‹ 返回')
          .fontSize(13)
          .fontColor(this.theme.textTertiary)
          .padding({ top: 10, bottom: 10, left: 14, right: 14 })
          .onClick(() => {
            this.plusMenuMode = 'main';
          })
        Divider().color(this.theme.strokeCard)
        Text('DAG（知识库包）')
          .fontSize(14)
          .fontColor(this.theme.brandSecondary)
          .padding({ top: 10, bottom: 10, left: 14, right: 14 })
          .onClick(() => {
            this.plusMenuVisible = false;
            this.pickPackFile();
          })
        Divider().color(this.theme.strokeCard)
        Text('APKG（Anki 包）')
          .fontSize(14)
          .fontColor(this.theme.brandSecondary)
          .padding({ top: 10, bottom: 10, left: 14, right: 14 })
          .onClick(() => {
            this.plusMenuVisible = false;
            this.pickApkgFile();
          })
        Divider().color(this.theme.strokeCard)
        Text('TXT')
          .fontSize(14)
          .fontColor(this.theme.brandSecondary)
          .padding({ top: 10, bottom: 10, left: 14, right: 14 })
          .onClick(() => {
            this.plusMenuVisible = false;
            this.pickImportFile('txt');
          })
        Divider().color(this.theme.strokeCard)
        Text('CSV')
          .fontSize(14)
          .fontColor(this.theme.brandSecondary)
          .padding({ top: 10, bottom: 10, left: 14, right: 14 })
          .onClick(() => {
            this.plusMenuVisible = false;
            this.pickImportFile('csv');
          })
        Divider().color(this.theme.strokeCard)
        Text('XLSX')
          .fontSize(14)
          .fontColor(this.theme.brandSecondary)
          .padding({ top: 10, bottom: 10, left: 14, right: 14 })
          .onClick(() => {
            this.plusMenuVisible = false;
            this.pickImportFile('xlsx');
          })
      } else {
        Text('‹ 返回')
          .fontSize(13)
          .fontColor(this.theme.textTertiary)
          .padding({ top: 10, bottom: 10, left: 14, right: 14 })
          .onClick(() => {
            this.plusMenuMode = 'main';
          })
        Divider().color(this.theme.strokeCard)
        Text('DAG（知识库包）')
          .fontSize(14)
          .fontColor(this.theme.brandSecondary)
          .padding({ top: 10, bottom: 10, left: 14, right: 14 })
          .onClick(() => {
            this.plusMenuVisible = false;
            this.exportDagPack(this.folderNav.folderId);
          })
        Divider().color(this.theme.strokeCard)
        Text('TXT')
          .fontSize(14)
          .fontColor(this.theme.brandSecondary)
          .padding({ top: 10, bottom: 10, left: 14, right: 14 })
          .onClick(() => {
            this.plusMenuVisible = false;
            this.doExportTxt();
          })
        Text('XLSX')
          .fontSize(14)
          .fontColor(this.theme.brandSecondary)
          .padding({ top: 10, bottom: 10, left: 14, right: 14 })
          .onClick(() => {
            this.plusMenuVisible = false;
            this.doExportXlsx();
          })
      }
    }
    .width(150) // ★ 0.239.0：弹层定宽收窄——Divider 无固有宽会把无约束 Column 撑满可用宽（Pad 实测 2798px 全屏面板），
                //   显式定宽 150vp=最长项「DAG（知识库包）」≈134vp+余量（紧凑贴内容，无右侧大片留白）
    .alignItems(HorizontalAlign.Start) // ★ 0.239.0：各项左对齐（Column 默认居中会参差）
  }

  // ★ 0.220.2：PC 右键/Pad 长按创建菜单（两项：新卡片/新文件夹）——无参 @Builder 直读状态（0.190.1 铁律）
  @Builder
  kbCreateMenuBuilder() {
    if (!this.multiSelectMode) {
    Column() {
      Text('创建新卡片')
        .fontSize(14)
        .fontColor(this.theme.textPrimary)
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ top: 12, bottom: 12, left: 16, right: 16 })
        .onClick(() => {
          this.createMenuVisible = false;
          this.openAddEditor();
        })
      Divider().color(this.theme.strokeCard)
      Text('创建新文件夹')
        .fontSize(14)
        .fontColor(this.theme.textPrimary)
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
          .fontColor(this.theme.textPrimary)
        TextInput({ text: this.folderDialogName, placeholder: '文件夹名称' })
          .fontSize(14)
          .height(40)
          .margin({ top: 12 })
          .padding({ left: 10, right: 10 })
          .backgroundColor(this.theme.surfaceSoft)
          .borderRadius(8)
          .onChange((v: string) => {
            this.folderDialogName = v;
          })
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .backgroundColor(this.theme.surfaceSoft)
            .fontColor(this.theme.textSecondary)
            .onClick(() => {
              this.folderDialogVisible = false;
              this.cancelFolderAction();
            })
          Button('确定')
            .layoutWeight(1)
            .backgroundColor(this.theme.brandPrimary)
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
      .backgroundColor(this.theme.surfaceNode)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.overlay)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.folderDialogVisible = false;
      this.cancelFolderAction();
    })
  }


  // ★ 0.221.0：文件夹删除确认弹窗（边栏树右键「删除」）
  @Builder
  folderDeleteConfirmDialog() {
    Column() {
      Column() {
        Text(this.folderNav.folderActionId === '' ? '清空根目录「全部卡片」' : `删除「${this.folderNameById(this.folderNav.folderActionId)}」`)
          .fontSize(16)
          .fontWeight(600)
          .fontColor(this.theme.textPrimary)
        Text(this.folderNav.folderActionId === '' ? '将清空根目录下所有卡片和文件夹，根目录入口将保留。不可恢复。' : '将删除该文件夹及其中所有卡片和子文件夹，不可恢复。')
          .fontSize(13)
          .fontColor(this.theme.textTertiary)
          .margin({ top: 10 })
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .backgroundColor(this.theme.surfaceSoft)
            .fontColor(this.theme.textSecondary)
            .onClick(() => {
              this.cancelFolderAction();
            })
          Button('删除')
            .layoutWeight(1)
            .backgroundColor(this.theme.danger)
            .fontColor(Color.White)
            .onClick(() => {
              this.folderNav.folderActionId === '' ? this.confirmRootDelete() : this.confirmFolderDelete();
            })
        }
        .margin({ top: 16 })
      }
      .width(this.isTablet ? 400 : '86%')
      .padding(20)
      .borderRadius(RADIUS_NAV)
      .backgroundColor(this.theme.surfaceNode)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.overlay)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.cancelFolderAction();
    })
  }

  // ★ 0.221.0：文件夹重命名弹窗（边栏树右键「重命名」）
  @Builder
  renameFolderDialog() {
    Column() {
      Column() {
        Text('重命名文件夹')
          .fontSize(16)
          .fontWeight(600)
          .fontColor(this.theme.textPrimary)
        TextInput({ text: this.folderNav.folderActionName, placeholder: '文件夹名称' })
          .fontSize(14)
          .height(40)
          .margin({ top: 12 })
          .padding({ left: 10, right: 10 })
          .backgroundColor(this.theme.surfaceSoft)
          .borderRadius(8)
          .onChange((v: string) => {
            this.folderNav.folderActionName = v;
          })
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .backgroundColor(this.theme.surfaceSoft)
            .fontColor(this.theme.textSecondary)
            .onClick(() => {
              this.cancelFolderAction();
            })
          Button('确定')
            .layoutWeight(1)
            .backgroundColor(this.theme.brandPrimary)
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
      .backgroundColor(this.theme.surfaceNode)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.overlay)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.cancelFolderAction();
    })
  }  @Builder
  folderPickerDialog() {
    Column() {
      Column() {
        Text(this.folderPickerTitle())
          .fontSize(16)
          .fontWeight(600)
          .fontColor(this.theme.textPrimary)
        Scroll() {
          Column() {
            Row() {
              Text('根目录')
                .fontSize(13)
                .fontColor(this.theme.textPrimary)
                .layoutWeight(1)
              Text(`${this.knowledgeBank.cards.length}`)
                .fontSize(10)
                .fontColor(this.theme.textTertiary)
            }
            .width('100%')
            .height(32)
            .padding({ left: 8, right: 8 })
            .borderRadius(RADIUS_NAV)
            .onClick(() => {
              this.confirmFolderTarget('');
            })
            ForEach(this.folderPickerTreeItems(), (item: KFolderTreeItem) => {
              Row({ space: 6 }) {
                // ★ 0.222.17：静态经典树形连接线（与边栏同款，弹窗无路径高亮）
                Row() {
                  ForEach(item.ancestorHasNext, (cont: boolean, k: number) => {
                    Stack({ alignContent: Alignment.Top }) {
                      if (cont) {
                        Column()
                          .width(1)
                          .height('100%')
                          .backgroundColor(this.theme.strokeCard)
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
                        .backgroundColor(this.theme.strokeCard)
                    }
                    .width('50%')
                    .height('100%')
                    Stack({ alignContent: Alignment.Center }) {
                      Row()
                        .width('100%')
                        .height(1)
                        .backgroundColor(this.theme.strokeCard)
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
                  .fontColor(this.theme.textPrimary)
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
            }, (item: KFolderTreeItem) => item.folder.id)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .margin({ top: 8 })
        .constraintSize({ maxHeight: 320 })
        Text('取消')
          .fontSize(13)
          .fontColor(this.theme.textTertiary)
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
      .backgroundColor(this.theme.surfaceNode)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.overlay)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.folderPickerVisible = false;
      this.cancelFolderAction();
    })
  }

  @Builder
  importPreviewDialog() {
    Column() {
      Column() {
        Text('批量导入预览')
          .fontSize(16)
          .fontWeight(600)
          .fontColor(this.theme.textPrimary)
        Text(`${this.importFileName} · 解析到 ${this.importRows.length} 张 · ${this.importFormat.toUpperCase()} 格式`)
          .fontSize(12)
          .fontColor(this.theme.textTertiary)
          .margin({ top: 6 })
        // ★ 0.249.1：AI 内容显式提醒（导入内容可能含 AI 生成，口径与 DagPack/apkg 弹窗一致）
        Text('导入内容可能包含 AI 生成的内容，请注意甄别')
          .fontSize(11)
          .fontColor(this.theme.textTertiary)
          .margin({ top: 2 })
        Scroll() {
          Column() {
            ForEach(this.importRows.slice(0, 10), (r: ImportRow, i: number) => {
              Column() {
                Text(`${i + 1}. ${r.title}`)
                  .fontSize(13)
                  .fontColor(this.theme.textPrimary)
                  .maxLines(1)
                Text(r.definition)
                  .fontSize(12)
                  .fontColor(this.theme.textTertiary)
                  .maxLines(1)
                  .margin({ top: 2 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(8)
              .borderRadius(8)
              .backgroundColor(this.theme.surfaceSoft)
              .margin({ top: 6 })
            }, (r: ImportRow, i: number) => `${i}-${r.title}`)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .margin({ top: 8 })
        .constraintSize({ maxHeight: 300 })
        if (this.importRows.length > 10) {
          Text(`… 其余 ${this.importRows.length - 10} 张省略`)
            .fontSize(12)
            .fontColor(this.theme.textTertiary)
            .margin({ top: 4 })
        }
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .backgroundColor(this.theme.surfaceSoft)
            .fontColor(this.theme.textSecondary)
            .onClick(() => {
              this.importPreviewVisible = false;
            })
          Button(`导入 ${this.importRows.length} 张`)
            .layoutWeight(1)
            .backgroundColor(this.theme.brandPrimary)
            .fontColor(Color.White)
            .onClick(() => {
              this.confirmImport();
            })
        }
        .margin({ top: 12 })
      }
      .width('86%')
      .constraintSize({ maxHeight: '80%' })
      .padding(18)
      .borderRadius(14)
      .backgroundColor(this.theme.bgApp)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.overlay)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.importPreviewVisible = false;
    })
  }

  // ============================================================
  // ★ 0.208.0：Anki apkg 导入
  // ============================================================

  /** 选 apkg → 解析（解压+SQLite 读+媒体提取）→ 牌组统计预览 */
  async pickApkgFile(): Promise<void> {
    // ★ 0.248.3：导入/导出守卫（上架合规——用户拍板必须登录）
    if (!requireLoginForCloud()) {
      return;
    }

    try {
      const doc = new picker.DocumentViewPicker();
      const selOpt = new picker.DocumentSelectOptions();
      selOpt.fileSuffixFilters = ['.apkg', '.colpkg'];
      selOpt.maxSelectNumber = 1;
      const uris: string[] = await doc.select(selOpt);
      if (uris.length === 0) {
        return;
      }
      this.showToast('Anki 包解析中…（大包可能几十秒）');
      try {
        const r: ApkgParseResult = await parseApkg(this.getUIContext().getHostContext() as Context, uris[0]);
        this.apkgCards = r.cards;
        this.apkgDeckCounts = r.deckCounts;
        this.apkgMediaCount = r.mediaCount;
        this.apkgFileName = uris[0].substring(uris[0].lastIndexOf('/') + 1);
        this.apkgPreviewVisible = true;
      } catch (e) {
        this.showToast(`解析失败：${e instanceof Error ? e.message : '格式不识别'}`);
      }
    } catch (_e) {
      this.showToast('选文件失败');
    }
  }

  /** 牌组名列表（预览渲染） */
  apkgDeckNames(): string[] {
    return Object.keys(this.apkgDeckCounts);
  }

  /** 确认导入：deck「A::B::C」→ ensureFolderPath 幂等建链（重复导入复用同文件夹）→ 卡片入库 */
  confirmApkgImport(): void {
    const folderIdCache: Map<string, string> = new Map<string, string>();
    const now = Date.now();
    let n = 0;
    for (let i = 0; i < this.apkgCards.length; i++) {
      const ac = this.apkgCards[i];
      const deckKey = ac.deckPath.length > 0 ? ac.deckPath : 'Anki';
      let fid = folderIdCache.get(deckKey);
      if (fid === undefined) {
        // 「::」层级拆链（空段滤除）；'（重复导入幂等——同 deck 复用已有文件夹链）
        const segs = deckKey.split('::').map((s: string): string => s.trim()).filter((s: string): boolean => s.length > 0);
        fid = segs.length === 0 ? this.folderNav.folderId : ensureFolderPath(this.knowledgeBank, segs, this.folderNav.folderId);
        folderIdCache.set(deckKey, fid);
      }
      const imgs = ac.images.length > 0 ? JSON.stringify(ac.images) : '';
      const tImgs = ac.titleImages.length > 0 ? JSON.stringify(ac.titleImages) : ''; // ★ 0.210.0：Anki 正面字段图 → 标题图（图对图）
      addKnowledgeCard(this.knowledgeBank, new KnowledgeCard('', ac.title, ac.definition, '', now + n,
        0, 0, 0, 0, ac.tags, imgs, fid ?? '', tImgs));
      n++;
    }
    const tp: Record<string, string> = {}; tp['format'] = 'apkg'; tp['count'] = `${n}`;
    track(this.getUIContext().getHostContext() as Context, 'batch_import', tp);
    this.showToast(`已导入 ${n} 张（牌组已映射为文件夹链）`);
    this.apkgPreviewVisible = false;
  }

  /** ★ 0.207.1：DagPack 勾选树弹窗——顶层文件夹全路径行（勾=导其子树）+ 根级散卡行 */
  @Builder
  packPreviewDialog() {
    Column() {
      Column() {
        Text('导入 DagPack · 选择要接收的内容')
          .fontSize(16)
          .fontWeight(600)
          .fontColor(this.theme.textPrimary)
        Text(`${this.packFileName} · ${this.packData.folders.length} 个文件夹 · ${this.packData.cards.length} 张卡 · 新子树挂当前文件夹`)
          .fontSize(12)
          .fontColor(this.theme.textTertiary)
          .margin({ top: 6 })
        // ★ 0.249.1：AI 内容显式提醒（合规：《人工智能生成合成内容标识办法》——包内卡片可能含 AI 提炼内容）
        Text('导入内容可能包含 AI 生成的内容，请注意甄别')
          .fontSize(11)
          .fontColor(this.theme.textTertiary)
          .margin({ top: 2 })
        Scroll() {
          Column() {
            ForEach(this.packData.folders, (f: PackFolder) => {
              if (f.parentRef === '') {
                Row() {
                  Image(this.packSel.includes(f.refId) ? $r('app.media.checkbox_on') : $r('app.media.checkbox_off')) // ★ 0.212.0：☑/☐ 换 svg
                    .width(20)
                    .height(20)
                    .margin({ right: 10 })
                    .onClick(() => {
                      this.togglePackSel(f.refId);
                    })
                  Text('📁 ' + this.packFolderPathName(f.refId))
                    .fontSize(13)
                    .fontColor(this.theme.textPrimary)
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${this.packSubtreeCardCount(f.refId)} 张`)
                    .fontSize(12)
                    .fontColor(this.theme.textTertiary)
                }
                .width('100%')
                .padding(10)
                .borderRadius(8)
                .backgroundColor(this.theme.surfaceSoft)
                .margin({ top: 6 })
                .onClick(() => {
                  this.togglePackSel(f.refId);
                })
              }
            }, (f: PackFolder) => f.refId)
            if (this.packRootCardCount() > 0) {
              Row() {
                Image(this.packRootCardsSel ? $r('app.media.checkbox_on') : $r('app.media.checkbox_off')) // ★ 0.212.0：☑/☐ 换 svg
                  .width(20)
                  .height(20)
                  .margin({ right: 10 })
                  .onClick(() => {
                    this.packRootCardsSel = !this.packRootCardsSel;
                  })
                Text('📄 根级散卡（不属于任何文件夹）')
                  .fontSize(13)
                  .fontColor(this.theme.textPrimary)
                  .layoutWeight(1)
                Text(`${this.packRootCardCount()} 张`)
                  .fontSize(12)
                  .fontColor(this.theme.textTertiary)
              }
              .width('100%')
              .padding(10)
              .borderRadius(8)
              .backgroundColor(this.theme.surfaceSoft)
              .margin({ top: 6 })
              .onClick(() => {
                this.packRootCardsSel = !this.packRootCardsSel;
              })
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .margin({ top: 8 })
        .constraintSize({ maxHeight: 300 })
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .backgroundColor(this.theme.surfaceSoft)
            .fontColor(this.theme.textSecondary)
            .onClick(() => {
              this.packPreviewVisible = false;
            })
          Button('导入所选')
            .layoutWeight(1)
            .backgroundColor(this.theme.brandPrimary)
            .fontColor(Color.White)
            .onClick(() => {
              this.confirmPackImport();
            })
        }
        .margin({ top: 12 })
      }
      .width('86%')
      .constraintSize({ maxHeight: '80%' })
      .padding(18)
      .borderRadius(14)
      .backgroundColor(this.theme.bgApp)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.overlay)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.packPreviewVisible = false;
    })
  }

  /** ★ 0.208.0：Anki 导入预览弹窗——牌组→文件夹映射统计 + 确认 */
  @Builder
  apkgPreviewDialog() {
    Column() {
      Column() {
        Text('Anki 包导入预览')
          .fontSize(16)
          .fontWeight(600)
          .fontColor(this.theme.textPrimary)
        Text(`${this.apkgFileName} · ${this.apkgCards.length} 张卡 · ${this.apkgMediaCount} 张图片 · 牌组自动映射为文件夹链`)
          .fontSize(12)
          .fontColor(this.theme.textTertiary)
          .margin({ top: 6 })
        Text('Anki 复习进度不迁移（DAGAI 从新卡开始，用自己的算法）；音频不迁移（App 自带语音）')
          .fontSize(11)
          .fontColor(this.theme.textTertiary)
          .margin({ top: 2 })
        // ★ 0.249.1：AI 内容显式提醒（合规：《人工智能生成合成内容标识办法》——包内卡片可能含 AI 提炼内容）
        Text('导入内容可能包含 AI 生成的内容，请注意甄别')
          .fontSize(11)
          .fontColor(this.theme.textTertiary)
          .margin({ top: 2 })
        Scroll() {
          Column() {
            ForEach(this.apkgDeckNames(), (deck: string) => {
              Row() {
                Text('🗂 ' + deck)
                  .fontSize(13)
                  .fontColor(this.theme.textPrimary)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${this.apkgDeckCounts[deck]} 张`)
                  .fontSize(12)
                  .fontColor(this.theme.textTertiary)
              }
              .width('100%')
              .padding(10)
              .borderRadius(8)
              .backgroundColor(this.theme.surfaceSoft)
              .margin({ top: 6 })
            }, (deck: string) => deck)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .margin({ top: 8 })
        .constraintSize({ maxHeight: 300 })
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .backgroundColor(this.theme.surfaceSoft)
            .fontColor(this.theme.textSecondary)
            .onClick(() => {
              this.apkgPreviewVisible = false;
            })
          Button(`导入 ${this.apkgCards.length} 张`)
            .layoutWeight(1)
            .backgroundColor(this.theme.brandPrimary)
            .fontColor(Color.White)
            .onClick(() => {
              this.confirmApkgImport();
            })
        }
        .margin({ top: 12 })
      }
      .width('86%')
      .constraintSize({ maxHeight: '80%' })
      .padding(18)
      .borderRadius(14)
      .backgroundColor(this.theme.bgApp)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.overlay)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.apkgPreviewVisible = false;
    })
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
                TextInput({ text: this.searchKeyword, placeholder: '搜索标题 / 内容' })
                  .fontSize(14)
                  .layoutWeight(1)
                  .height(40)
                  .padding({ left: 12, right: 12 })
                  .borderRadius(20)
                  .backgroundColor(this.theme.surfaceSoft)
                  .onChange((value: string) => {
                    this.searchKeyword = value;
                  })
                if (this.searchKeyword.length > 0) {
                  // Clear button — clearing restores the full list (spec 2.1.4)
                  Text('×')
                    .fontSize(16)
                    .fontColor(this.theme.textTertiary)
                    .margin({ left: 6 })
                    .onClick(() => {
                      this.searchKeyword = '';
                    })
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: (this.isTablet || this.isPcDevice()) ? 4 : 2, bottom: (this.isTablet || this.isPcDevice()) ? 4 : 2 }) // ★ 0.241.0：手机端收紧对称——标题↔搜索栏 8+2=10 / 搜索栏↔首卡 2+8=10（顶栏 56 与宽屏间距原样不动）
              .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 })).animation({ duration: 200 }))
            }
          } else {
            // ★ 0.148: multi-select toolbar — select-all / counter / cancel
            Row() {
              Button(this.isAllSelected() ? '取消全选' : '全选')
                .fontSize(13)
                .fontColor(this.theme.textSecondary)
                .backgroundColor(Color.Transparent)
                .padding({ left: 6, right: 6 })
                .onClick(() => {
                  this.toggleSelectAll();
                })
              Blank()
                .layoutWeight(1)
              Text(`已选 ${this.selectedIds.length} 项`)
                .fontSize(13)
                .fontColor(this.theme.textTertiary)
              // ★ 0.207.0：批量移动/复制到文件夹（单张=多选 1 张，交互统一）
              Button('移动')
                .fontSize(13)
                .fontColor(this.theme.brandSecondary)
                .backgroundColor(Color.Transparent)
                .padding({ left: 6, right: 6 })
                .margin({ left: 4 })
                .onClick(() => {
                  if (this.selectedIds.length === 0) {
                    this.showToast('先选中卡片');
                    return;
                  }
                  this.moveOrCopyMode = 'move';
                  this.folderPickerVisible = true;
                })
              Button('复制')
                .fontSize(13)
                .fontColor(this.theme.brandSecondary)
                .backgroundColor(Color.Transparent)
                .padding({ left: 6, right: 6 })
                .onClick(() => {
                  if (this.selectedIds.length === 0) {
                    this.showToast('先选中卡片');
                    return;
                  }
                  this.moveOrCopyMode = 'copy';
                  this.folderPickerVisible = true;
                })
              Button('取消')
                .fontSize(13)
                .fontColor(this.theme.textSecondary)
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

          if (this.knowledgeBank.cards.length === 0 && this.knowledgeBank.folders.length === 0) {
            // Empty bank — guide the user to both entry points (0.148 adds manual add)
            Column() {
              Text('知识库为空')
                .fontSize(16)
                .fontColor(this.theme.textTertiary)
              Text('点右上角 + 手动添加，或长按对话气泡选中文本入知识库')
                .fontSize(12)
                .fontColor(this.theme.textTertiary)
                .margin({ top: 8 })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.filteredCards.length === 0 && this.currentFolders.length === 0) {
            // ★ 0.207.0：目录空态（搜索无结果 / 空文件夹二合一文案）
            Column() {
              Text(this.searchKeyword.length > 0 ? '无匹配结果' : '此文件夹为空')
                .fontSize(16)
                .fontColor(this.theme.textTertiary)
              Text(this.searchKeyword.length > 0 ? '换个关键词试试' : '点右上角 + 导入或新建')
                .fontSize(12)
                .fontColor(this.theme.textTertiary)
                .margin({ top: 8 })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.viewMode.grid && (this.isTablet || this.isPcDevice())) {
            // ★ 0.239.0：网格视图（图片浏览模式）——封面卡：首图（标题图优先→内容图）占上半当封面，
            //   无图卡紫渐变底+居中标题首字占位（解决 0 图卡空单调）；下半标题+标签+复习状态（描述不放）；
            //   等高 Grid（禁瀑布流——单词库 0.218.9 定案"整齐即正义"）；滑动删除不挂（swipeAction 是
            //   ListItem 专属）；单击（双击进编辑与列表一致）/长按多选/右键菜单与列表一致
            Grid() {
              ForEach(this.filteredCards, (c: KnowledgeCard) => {
                GridItem() {
                  Column() {
                    Stack() {
                      if (this.cardCoverImage(c).length > 0) {
                        Image(this.cardCoverImage(c))
                          .width('100%')
                          .height('100%')
                          .objectFit(ImageFit.Cover)
                          .borderRadius(RADIUS_CONTROL)
                          .onClick(() => {
                            // 单击封面=全屏预览（与列表图片单击预览一致；自消费不冒泡防误进编辑）
                            const t = getTitleImages(c);
                            const g = getCardImages(c);
                            this.openImagePreview(t.length > 0 ? t : g, 0);
                          })
                      } else {
                        // 无图占位：深紫渐变底 + 居中标题首字（克制设计，禁彩色 emoji）
                        Column() {
                          Text(c.title.length > 0 ? c.title.charAt(0) : '知')
                            .fontSize(34)
                            .fontWeight(700)
                            .fontColor(this.theme.textPrimary)
                        }
                        .width('100%')
                        .height('100%')
                        .justifyContent(FlexAlign.Center)
                        .borderRadius(RADIUS_CONTROL)
                        .linearGradient({
                          angle: 135,
                          colors: [[this.theme.brandPrimary, 0], [this.theme.surfaceHover, 1]]
                        })
                      }
                    }
                    .width('100%')
                    .height(104) // 封面区 ≈ 卡高 55%（190×0.55≈104）
                    Row() {
                      Text(c.title)
                        .fontSize(14)
                        .fontWeight(600)
                        .fontColor(this.theme.textPrimary)
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                      if (this.multiSelectMode) {
                        Image(this.selectedIds.includes(c.id) ? $r('app.media.checkbox_on') : $r('app.media.checkbox_off'))
                          .width(18)
                          .height(18)
                          .margin({ left: 6 })
                      }
                    }
                    .width('100%')
                    .margin({ top: 8 })
                    if (parseTags(c.tags).length > 0) {
                      // 标签 pill：最多 2 个，单标签超长省略（横向不滑——网格卡空间有限）
                      Row({ space: 4 }) {
                        ForEach(parseTags(c.tags).slice(0, 2), (t: string) => {
                          Text(t)
                            .fontSize(10)
                            .fontColor(this.theme.brandSecondary)
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .height(18)
                            .padding({ left: 6, right: 6 })
                            .borderRadius(4)
                            .border({ width: 1, color: this.theme.brandSecondary })
                        }, (t: string) => t)
                      }
                      .width('100%')
                      .margin({ top: 6 })
                    }
                    Text(this.nextReviewLabel(c))
                      .fontSize(11)
                      .fontColor(this.nextReviewColor(c))
                      .margin({ top: 4 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')
                  .height(190) // ★ 0.239.0：封面卡固定格高（规格 180~200 取中）
                  .padding(12)
                  .borderRadius(RADIUS_CONTROL)
                  .backgroundColor(this.theme.surfaceNode)
                  .borderColor(this.theme.strokeCard)
                  .borderWidth(1)
                  .onClick(() => {
                    this.onItemTap(c);
                  })
                  .gesture(
                    LongPressGesture()
                      .onAction(() => {
                        if (!this.multiSelectMode) {
                          this.enterMultiSelect(c.id);
                        }
                      })
                  )
                  .bindContextMenuByResponseType([
                    { value: '移动', action: () => { this.moveOrCopyMode = 'move'; this.selectedIds = [c.id]; this.folderPickerVisible = true; } },
                    { value: '复制', action: () => { this.moveOrCopyMode = 'copy'; this.selectedIds = [c.id]; this.folderPickerVisible = true; } },
                    { value: '修改', action: () => { this.openEditEditor(c); } },
                    { value: '删除', action: () => { this.requestDeleteCard(c); } }
                  ], ResponseType.RightClick)
                }
              }, (c: KnowledgeCard) => c.id)
            }
            .columnsTemplate(`repeat(${this.gridCols}, 1fr)`)
            .columnsGap(this.gridGap)
            .rowsGap(this.gridGap)
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 16, right: 16, top: 12 })
            .onClick(() => {
              // 与列表一致：点空白区退出多选（200ms 窗口内是冒泡的卡片点击）
              if (Date.now() - this.lastEntryTapAt < 200) {
                return;
              }
              if (this.multiSelectMode) {
                this.exitMultiSelect();
              }
            })
            .onAreaChange((_o: Area, n: Area) => {
              // ★ 0.239.0 用户军令"列数禁止写死档位"——连续自适应（复刻单词库 0.218.8 式）：
              //   列数 round 进位 + 间距随格宽 6% 连续缩放（8~14）；封面卡目标格宽 200（卡高比单词卡高，格宽放宽）
              const availW = Number(n.width) - 32; // 减左右 padding 16×2
              if (availW > 0) {
                const cols = Math.max(2, Math.round(availW / 200));
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
              ForEach(this.filteredCards, (c: KnowledgeCard) => {
                ListItem() {
                  Row() {
                    if (this.multiSelectMode) {
                      // ★ 0.148: multi-select check indicator — an icon Text,
                      // NOT a Checkbox: the whole row handles tap-toggle and a
                      // real Checkbox would fire a second onChange
                      // ★ 0.212.0 用户拍板：☑/☐ 字符勾选框太丑——换华为风格 checkbox svg（选中=品牌紫底白勾）
                      Image(this.selectedIds.includes(c.id) ? $r('app.media.checkbox_on') : $r('app.media.checkbox_off'))
                        .width(20)
                        .height(20)
                        .margin({ right: 8 })
                    }
                    // Entry content block: title -> definition -> image thumbnail
                    Column() {
                      // ★ 0.202.0：问AI 入口改版（用户拍板：原紫渐变钮设计「像坨屎」）——移至标题行右端，
                      //   灰色小字「问AI?」与标题平行，颜色同「未学习」标签（this.theme.textTertiary 弱化灰）：
                      //   不显眼但路口找得到；ArkUI 点击不冒泡：本 Text 自身消费，不触发卡片 onClick 进编辑
                      Row() {
                      // ★ 0.202.1：标签 chips（用户拍板：放标题旁空区，高度 20 ≤ 问AI 32，圆角偏方 4，多标签横向滑动）
                      //   0.198.3 铁律合规：横向 Scroll 挂在受约束容器内用 layoutWeight，chip 自身 padding 自然宽
                      Row({ space: 6 }) {

                        // ★ 0.212.3：宽屏标题行内居中、标签后置；手机左对齐+标签弹性（平台分治）
                        // ★ 0.213.0 用户拍板两连精化：①标题居中跟着标签宽度漂移（"上下不整齐"）→宽屏
                        //   标签列改**定宽** width 38%（内容左对齐——用户"标签不要右对齐要左对齐"），
                        //   标题列=剩余全部弹性 → 所有卡片标题同一垂直轴线居中；②"问AI?"文字按钮撤除
                        //   （功能不变）→挪进滑出面板（见 swipeActionsPanel），宽屏手机两端一致
                        // ★ 0.213.1 用户拍板（截图实锤）："标题要在方框的正中间+标签在标题右侧左对齐"。
                        //   0.213.0 不齐根因=标签列挂在 if(tags) 里——无标签卡右列不渲染→标题占满全行
                        //   （中心 50%）vs 有标签卡标题列被压缩（中心 ~31%）→上下漂移。
                        //   修复=组件级 if 平台分治：宽屏两列定式（右列恒渲染 38% 占位，无标签=空列，
                        //   标题列恒 62% → 全部卡片标题同一轴线）；标签列内容左对齐（用户点名）。
                        //   手机恢复 0.212.3 前好评原样（左对齐 62% + 标签弹性），并修 width(undefined) 雷
                        // ★ 0.213.2 用户拍板（0.213.1 仍不齐实锤）：0.213.1"标题列弹性居中"的轴线在列
                        //   中心（31% 处）且整列位置跟着布局走——用户要的是**卡片几何正中**（50% 轴）+
                        //   标签在标题右边往右排。终式=**Stack 叠层**：标题层 alignContent Center=恒定
                        //   卡片正中（与任何列无关，上下永远一条线），标签层贴右 38% 定宽列内容左对齐；
                        //   标题 maxWidth 60% 保证与标签区（62% 起）零重叠
                        if (this.isTablet) {
                          Stack({ alignContent: Alignment.Center }) {
                            Row() {
                              Blank()
                              Column() {
                                if (parseTags(c.tags).length > 0) {
                                  Scroll() {
                                    Row({ space: 6 }) {
                                      ForEach(parseTags(c.tags), (t: string) => {
                                        Text(t)
                                          .fontSize(10)
                                          .fontColor(this.theme.brandSecondary)
                                          .height(20)
                                          .padding({ left: 8, right: 8 })
                                          .borderRadius(4)
                                          .border({ width: 1, color: this.theme.brandSecondary })
                                      }, (t: string) => t)
                                    }
                                  }
                                  .scrollable(ScrollDirection.Horizontal)
                                  .scrollBar(BarState.Off)
                                  .height(20)
                                }
                              }
                              .width('38%')
                              .alignItems(HorizontalAlign.Start) // 标签左对齐（用户点名）
                            }
                            .width('100%')
                            Text(c.title)
                              .fontSize(16)
                              .fontWeight(600)
                              .fontColor(this.theme.textPrimary)
                              .maxLines(2) // ★ 0.227.1：宽屏长标题两行（导入卡标题多行文本，单行只显首段不够看；Stack 居中不受影响）
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .textAlign(TextAlign.Center)
                              .constraintSize({ maxWidth: '60%' })
                          }
                          .width('100%')
                        } else {
                          Row({ space: 6 }) {
                            Text(c.title)
                              .fontSize(16)
                              .fontWeight(600)
                              .fontColor(this.theme.textPrimary)
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .constraintSize({ maxWidth: '62%' })
                            if (parseTags(c.tags).length > 0) {
                              Scroll() {
                                Row({ space: 6 }) {
                                  ForEach(parseTags(c.tags), (t: string) => {
                                    Text(t)
                                      .fontSize(10)
                                      .fontColor(this.theme.brandSecondary)
                                      .height(20)
                                      .padding({ left: 8, right: 8 })
                                      .borderRadius(4)
                                      .border({ width: 1, color: this.theme.brandSecondary })
                                  }, (t: string) => t)
                                }
                              }
                              .scrollable(ScrollDirection.Horizontal)
                              .scrollBar(BarState.Off)
                              .height(20)
                              .layoutWeight(1)
                            }
                          }
                        }
                      }
                      .layoutWeight(1)
                      // ★ 0.213.0 用户拍板：标题行「问AI?」文字按钮撤除——功能不变，入口挪进滑出面板
                      //   （swipeActionsPanel 问AI 圆钮，宽屏手机两端一致；语义=知识卡重新带入对话框问AI）
                      }
                      .width('100%')
                      // ⚠️ 0.213.0 编辑事故复盘：撤问AI/删提前闭合两轮 edit 曾把外层标题行闭合与
                      //   Entry Column 闭合双双错位（症状=级联三件套：@Computed 失效+缺 build+undefined）
                      //   ——双层 Row 嵌套区改结构必须整段重读缩进，禁盲删闭合括号
                      // ★ 0.211.0 用户拍板：排版=第一行标题文字→第二行标题图，且**全部展示**（原仅首图
                      //   32×32 缩略）；横滑条 0.198.3 铁律合规（受约束容器内 Scroll+子项自然宽）；
                      //   双击图片=全屏查看器放大缩小；单击拦截不冒泡（0.200.0 教训）防误进编辑
                      if (getTitleImages(c).length > 0) {
                        Scroll() {
                          Row({ space: 6 }) {
                            ForEach(getTitleImages(c), (img: string, ti: number) => {
                              Image(img)
                                .height(72)
                                .width(108)
                                .objectFit(ImageFit.Cover)
                                .borderRadius(RADIUS_CONTROL)
                                .onClick(() => {
                                  // ★ 0.211.1 用户报：点击图片要放大（原双击+拦截不预览）——单击即预览，
                                  //   onClick 自消费不冒泡（0.200.0 教训）不会误进编辑
                                  this.openImagePreview(getTitleImages(c), ti);
                                })
                            }, (img: string) => img)
                          }
                        }
                        .scrollable(ScrollDirection.Horizontal)
                        .scrollBar(BarState.Off)
                        .width('100%')
                        .margin({ top: 6 })
                      }
                      Text(c.definition)
                        .fontSize(13)
                        .fontColor(this.theme.textSecondary)
                        .margin({ top: 4 }) // ★ 0.213.2 用户拍板：标题与内容太挤——行距 2→4（"大一两个像素"）
                      // ★ 0.188.0：下次复习时间（未学习灰 / 已到期红 / 常规灰，复刻单���库）
                      Text(this.nextReviewLabel(c))
                        .fontSize(11)
                        .fontColor(this.nextReviewColor(c))
                        .margin({ top: 2 })
                      // ★ 0.211.1 用户报：内容图 9 张也要全部展示（原仅首图 96×64 缩略）——对齐标题图条，
                      //   单击预览全屏查看器
                      if (getCardImages(c).length > 0) {
                        Scroll() {
                          Row({ space: 6 }) {
                            ForEach(getCardImages(c), (img: string, ci: number) => {
                              Image(img)
                                .height(72)
                                .width(108)
                                .objectFit(ImageFit.Cover)
                                .borderRadius(RADIUS_CONTROL)
                                .onClick(() => {
                                  this.openImagePreview(getCardImages(c), ci);
                                })
                            }, (img: string) => img)
                          }
                        }
                        .scrollable(ScrollDirection.Horizontal)
                        .scrollBar(BarState.Off)
                        .width('100%')
                        .margin({ top: 6 })
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    .onClick(() => {
                      this.onItemTap(c);
                    })

                  }
                  .width('100%')
                  .padding(12)
                  .borderRadius(RADIUS_CONTROL)
                  .backgroundColor(this.theme.surfaceNode) // ★ 0.183.0：卡片底对齐节点卡片规格（this.theme.surfaceNode + this.theme.strokeCard 描边）
                  .borderColor(this.theme.strokeCard)
                  .borderWidth(1)
                  .alignItems(VerticalAlign.Center)
                  .gesture(
                    // ★ 0.148: long-press enters multi-select (spec 2.3.1)
                    LongPressGesture()
                      .onAction(() => {
                        if (!this.multiSelectMode) {
                          this.enterMultiSelect(c.id);
                        }
                      })
                  )
                }
                .swipeAction({
                  // ★ 0.212.0：左右滑露操作面板；★ 0.213.0：面板扩容双圆钮（问AI+删除）并改名
                  //   swipeActionsPanel；swipeAction 是 ListItem 专属属性（挂 Row 上无效——编译实锤）；
                  //   箭头函数包 @Builder 调用（CustomBuilder 规范写法）
                  end: (): void => {
                    this.swipeActionsPanel(c)
                  },
                  start: (): void => {
                    this.swipeActionsPanel(c)
                  }
                })
                .bindContextMenuByResponseType([
                  { value: '移动', action: () => { this.moveOrCopyMode = 'move'; this.selectedIds = [c.id]; this.folderPickerVisible = true; } },
                  { value: '复制', action: () => { this.moveOrCopyMode = 'copy'; this.selectedIds = [c.id]; this.folderPickerVisible = true; } },
                  { value: '修改', action: () => { this.openEditEditor(c); } },
                  { value: '删除', action: () => { this.requestDeleteCard(c); } }
                ], ResponseType.RightClick)
              }, (c: KnowledgeCard) => c.id)
            }
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 16, right: 16, top: (this.isTablet || this.isPcDevice()) ? 12 : 8 }) // ★ 0.241.0：手机端 12→8（与搜索栏收紧配套，上下各 10 对称；宽屏原样）
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

        // ★ 0.241.0：左下角导航胶囊条（仅手机端；声明在弹窗层之前=弹窗盖胶囊、抽屉在最后盖一切）
        this.kbNavCapsule()

        // ★ 0.200.0: 问 AI 二选一面板（最顶层）
        if (this.askSheetVisible) {
          this.askAiSheet()
        }
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
        // ★ 0.161.2: card-count settings dialog
        if (this.cardSettingsVisible) {
          this.cardSettingsDialog()
        }
        // ★ 0.211.0：列表图片全屏查看器（最顶层——四场景统一：列表标题图/内容图+编辑弹窗缩略全走这里）
        if (this.previewVisible) {
          this.imagePreviewViewer()
        }
        // ★ 0.207.0：文件夹/导入/导出弹窗（最顶层）
        if (this.folderDialogVisible || this.folderNav.folderAction === 'newfolder') {
          this.folderDialog()
        }
        if (this.folderNav.folderAction === 'newcard') {
          Column()
            .width(0)
            .height(0)
            .onAppear(() => {
              this.folderNav.folderAction = '';
              this.folderNav.folderActionId = '';
              this.openAddEditor();
            })
        }
        if (this.folderPickerVisible || this.folderNav.folderAction === 'move' || this.folderNav.folderAction === 'copy') {
          this.folderPickerDialog()
        }

        if (this.folderNav.folderAction === 'delete') {
          this.folderDeleteConfirmDialog()
        }
        if (this.folderNav.folderAction === 'rename') {
          this.renameFolderDialog()
        }
        if (this.importPreviewVisible) {
          this.importPreviewDialog()
        }
        // ★ 0.207.1：DagPack 勾选树弹窗
        if (this.packPreviewVisible) {
          this.packPreviewDialog()
        }
        // ★ 0.208.0：Anki 导入预览
        if (this.apkgPreviewVisible) {
          this.apkgPreviewDialog()
        }
        // ★ 0.222.7：抽屉移入主 Column children 末尾（与正常工作的弹窗块同层）——「属性链后兄弟」位置弃用
        this.kbMobileDrawerLayer()
      }
      .background(this.theme.bgCanvas) // ★ 0.278.10：background() 背景延伸进安全区，上下与页面主体同色（统一 0.278.9 模板）
      // ★ 0.220.2 用户拍板：PC 右键 / Pad 长按空白 → 弹「创建新卡片 / 创建新文件夹」菜单
      //   （bindContextMenu 跟随鼠标右键；bindPopup 供长按唤起——点选项执行、点遮罩收起；
      //    触屏设备 RightClick 响应=长按，与 LongPressGesture 双通道等效冗余）
      .bindContextMenu(this.kbCreateMenuBuilder, ResponseType.RightClick)
      .bindPopup(this.createMenuVisible, {
        builder: this.kbCreateMenuBuilder(),
        placement: Placement.Bottom,
        popupColor: this.theme.surfaceNode,
        radius: 12,
        mask: { color: this.theme.overlayLight },
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
    .backgroundColor(this.theme.bgCanvas) // ★ 0.278.12：NavDestination 容器级显式背景（华为官方建议双保险）
    // ★ 0.148: back gesture closes dialogs / multi-select first, page last
    .onBackPressed(() => {
      // ★ 0.230.0：全局设置弹窗打开时返回键先关弹窗（共享真相源——修复仅画布页拦截的盲区，0.229.26 审计 B9 实锤）
      const gsShared = connectGlobalSettingsShared();
      if (gsShared.visible) {
        gsShared.closeReq++;
        return true;
      }
      // ★ 0.222.0：手机边栏抽屉开着时返回键先收抽屉
      if (this.sidebarVisible) {
        this.closeSidebar();
        return true;
      }
      // ★ 0.200.0: 问 AI 面板最顶层先关
      if (this.askSheetVisible) {
        this.askSheetVisible = false;
        return true;
      }
      // ★ 0.211.2：图片全屏查看器优先关闭——用户实测右滑（系统侧滑）直接退出知识库页；
      //   拦截后侧滑=只关查看器（三重退出冗余：单击图片/×/右滑侧滑均只关查看器不退页）
      if (this.previewVisible) {
        this.previewVisible = false;
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
      // ★ 0.161.2: card-count settings dialog closes before multi-select
      if (this.cardSettingsVisible) {
        this.cardSettingsVisible = false;
        return true;
      }
      // ★ 0.207.0：新弹窗先关（导入预览 > 目标选择 > 文件夹命名）
      if (this.importPreviewVisible) {
        this.importPreviewVisible = false;
        return true;
      }
      // ★ 0.207.1：DagPack 弹窗
      if (this.packPreviewVisible) {
        this.packPreviewVisible = false;
        return true;
      }
      // ★ 0.208.0：Anki 弹窗
      if (this.apkgPreviewVisible) {
        this.apkgPreviewVisible = false;
        return true;
      }

      // ★ 0.221.0：文件夹操作弹窗（移动/复制/删除/重命名）——返回键先关
      if (this.folderNav.folderAction !== '') {
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
      // ★ 0.207.0：非根目录时返回=回上一级（最后才退出页面）
      if (this.folderNav.folderId.length > 0) {
        this.folderNav.folderId = this.folderParentId();
        return true;
      }
      return false;
    })
  }
}
