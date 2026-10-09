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

import { KnowledgeCard, KnowledgeBankStore, CardImportStore, connectCardImport, navBackToCanvas, parseTags, getCardImages, getTitleImages } from '../common/KnowledgeModel'; // ★ 0.200.0：卡片导入气泡；★ 0.202.0：parseTags；★ 0.202.1：getCardImages（多图兼容读取）
import { connectKnowledgeBank, addKnowledgeCard, removeKnowledgeCard, updateKnowledgeCard, removeCardsByIds } from '../utils/KnowledgeStoreUtil';
import { formatNextReviewLabel } from '../utils/MemoryAlgorithm'; // ★ 0.188.0：下次复习时间标签（记忆算法·知识库复刻）
import { KnowledgeCountStore, connectKnowledgeCount } from '../common/ChatModel'; // ★ 0.161.2: knowledge-card count settings (same PersistenceV2 instance as ChatPage review areas)
import { photoAccessHelper } from '@kit.MediaLibraryKit'; // ★ 0.160: editor image picking
import { fileIo, picker } from '@kit.CoreFileKit'; // ★ 0.160: read picked photo into base64；★ 0.207.0 picker：文档选/存（批量导入 CSV/TXT、导出 CSV）
import { image } from '@kit.ImageKit'; // ★ 0.211.1：选图压缩（9 张原图 base64 直接持久化=手机保存崩溃根因）
import { buffer } from '@kit.ArkTS'; // ★ 0.160: ArrayBuffer → base64
import { WindowMode, connectWindowMode } from '../common/WindowMode'; // ★ 0.196.4：窗口宽度模式共享真相源（分屏/悬浮窗切手机布局）
// ★ 0.183.0：UI 收敛到 DesignTokens（UI_GUIDELINES 唯一真相源；v0.166.3 锁暗色后 isDark 三元为死代码，全部清除）
  import { BG_APP, BG_CANVAS, TEXT_PRIMARY, TEXT_SECONDARY, TEXT_TERTIARY, SURFACE_NODE, SURFACE_HOVER, SURFACE_SOFT, BRAND_PRIMARY, BRAND_SECONDARY, DANGER, OVERLAY, STROKE_CARD, RADIUS_CONTROL, RADIUS_NAV, FONT_SIZE_SCREEN_TITLE } from '../common/DesignTokens'; // ★ 0.191.0：加 SURFACE_HOVER/BRAND_SECONDARY（排序按钮激活态）
// ★ 0.207.0 anything 导入体系：文件夹 + CSV/TXT 批量导入 + 导出
import { KFolder } from '../common/KnowledgeModel';
import { addFolder, renameFolder, deleteFolder, moveCards, copyCards, folderChain } from '../utils/KnowledgeStoreUtil';
import { ImportRow, readTextFile, parseTextToRows, cardsToCsv, readXlsxRows } from '../utils/ImportUtil';
// ★ 0.207.1 DagPack：知识库模块化导出/导入（发送端粗粒度·接收端勾选细粒度——用户拍板）
import { DagPack, PackFolder, buildKnowledgePack, packToJson, parseDagPack, packChildFolders, packCardCount, packSubtreeRefs, packFolderPath } from '../utils/PackUtil';
// ★ 0.208.0 Anki：apkg 导入（知识库专用——单词库不���，用户拍板）
import { ApkgCard, ApkgParseResult, parseApkg } from '../utils/ApkgUtil';
import { ensureFolderPath } from '../utils/KnowledgeStoreUtil';
import { track } from '../utils/TrackUtil';

@ComponentV2
export struct KnowledgeBankPage {
  @Param pathStack: NavPathStack = new NavPathStack();
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
  windowMode: WindowMode = connectWindowMode();
  @Computed get isTablet(): boolean {
    return this.windowMode.isTablet;
  }

  aboutToAppear(): void {
    // ★ 0.196.4：isTablet 屏宽检测删除——改读 WindowMode 共享真相源（Index 根 onAreaChange 写入）
  }

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
  @Local currentFolderId: string = '';          // '' = 根目录（面包屑跳转/文件夹点击切换）
  @Local folderDialogVisible: boolean = false;  // 新建/重命名共用弹窗
  @Local folderDialogIsRename: boolean = false;
  @Local folderDialogTargetId: string = '';
  @Local folderDialogName: string = '';
  @Local folderPickerVisible: boolean = false;  // 移动/复制目标选择弹窗
  @Local moveOrCopyMode: string = 'move';       // 'move' | 'copy'（folderPicker 确认时分流）
  @Local importPreviewVisible: boolean = false; // 批量导入预览弹窗
  @Local importRows: ImportRow[] = [];
  @Local importFileName: string = '';
  @Local importFormat: string = 'txt';

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
      .filter((f: KFolder): boolean => f.parentId === this.currentFolderId)
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
      list = this.knowledgeBank.cards.filter((c: KnowledgeCard) => c.folderId === this.currentFolderId);
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
      addKnowledgeCard(this.knowledgeBank, new KnowledgeCard('', title, definition, '', 0, 0, 0, 0, 0, tags, imagesJson, '', titleImagesJson));
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
      .backgroundColor(BRAND_PRIMARY)
      .onClick(() => {
        if (!this.multiSelectMode) {
          this.askSheetTitle = c.title;
          this.askSheetDefinition = c.definition;
          this.askSheetImages = [...getTitleImages(c), ...getCardImages(c)]; // 标题图在前+内容图合并带入问AI面板
          this.askSheetVisible = true;
        }
      })
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
          this.pathStack.replacePath({ name: 'WordBankPage' });
        })
      Text('知识库')
        .fontSize(FONT_SIZE_SCREEN_TITLE) // ★ 0.183.0：18→16 对齐 ScreenTitle 规范
        .fontWeight(600)
        .fontColor(TEXT_PRIMARY)
        .onClick(() => {
          this.pathStack.replacePath({ name: 'WordBankPage' }); // ★ 0.195.0：标题也可点击切换（用户需求，与 ⇄ 同款）
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
        .backgroundColor(this.sortMode >= 2 ? SURFACE_HOVER : Color.Transparent)
        .fontColor(this.sortMode >= 2 ? BRAND_SECONDARY : TEXT_TERTIARY)
        .padding({ left: 8, right: 4 })
        .margin({ right: 4 })
        .onClick(() => {
          this.sortMode = this.sortMode === 2 ? 3 : 2;
        })
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
        // ★ 0.207.0：+ 升级为菜单——anything 导入体系入口（新建卡片/文件夹/批量导入/导出）
        Button('+')
          .fontSize(20)
          .height(40) // ★ 0.196.6：显式 40vp——导航栏统一规格（UI_GUIDELINES 10.2：以气泡页顶栏为基准）
          .backgroundColor(Color.Transparent)
          .fontColor(TEXT_PRIMARY)
          .padding({ left: 8, right: 8 })
          .bindMenu([
            { value: '新建卡片', action: () => { this.openAddEditor(); } },
            { value: '新建文件夹', action: () => { this.openFolderCreate(); } },
            { value: '批量导入（TXT · CSV · XLSX）', action: () => { this.pickImportFile(); } },
            { value: '导入 Anki 包（.apkg）', action: () => { this.pickApkgFile(); } },
            { value: '导入 DagPack（知识库包）', action: () => { this.pickPackFile(); } },
            { value: '导出 CSV（当前文件夹）', action: () => { this.doExportCsv(); } },
            { value: '导出 DagPack（当前文件夹）', action: () => { this.exportDagPack(this.currentFolderId); } }
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
          .fontColor(TEXT_PRIMARY)
        Text('每次复习展示的卡片数，生效于：AI 回复底部复习区、知识卡片提炼等待页')
          .fontSize(12)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 6 })
                  // ★ 0.195.0：布局统一（用户定稿「012+输入框」一行——与全局设置复习 Tab 完全同款）
          Row() {
            Button('0')
              .fontSize(14)
              .width(44)
              .height(40)
              .fontColor(this.knowledgeCountStore.knowledgeCount === 0 ? TEXT_PRIMARY : (TEXT_SECONDARY))
              .backgroundColor(this.knowledgeCountStore.knowledgeCount === 0 ? BRAND_PRIMARY : Color.Transparent)
              .borderRadius(RADIUS_CONTROL)
              .onClick(() => {
                this.knowledgeCountStore.knowledgeCount = 0;
                this.cardSettingsVisible = false;
              })
            Button('1')
              .fontSize(14)
              .width(44)
              .height(40)
              .fontColor(this.knowledgeCountStore.knowledgeCount === 1 ? TEXT_PRIMARY : (TEXT_SECONDARY))
              .backgroundColor(this.knowledgeCountStore.knowledgeCount === 1 ? BRAND_PRIMARY : Color.Transparent)
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
              .fontColor(this.knowledgeCountStore.knowledgeCount === 2 ? TEXT_PRIMARY : (TEXT_SECONDARY))
              .backgroundColor(this.knowledgeCountStore.knowledgeCount === 2 ? BRAND_PRIMARY : Color.Transparent)
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
              .backgroundColor(SURFACE_SOFT)
              .type(InputType.Number)
              .margin({ left: 8 })
              .onChange((value: string) => {
                this.cardCustomInput = value;
                this.cardInputError = '';
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
                const n = parseInt(this.cardCustomInput, 10);
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
            .fontColor(DANGER)
            .margin({ top: 6 })
        }
        Button('关闭')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .backgroundColor(Color.Transparent)
          .width('100%')
          .margin({ top: 12 })
          .onClick(() => {
            this.cardSettingsVisible = false;
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
          .fontColor(TEXT_PRIMARY)
          .backgroundColor(BRAND_PRIMARY)
          .borderRadius(RADIUS_CONTROL)
          .width(this.isTablet ? 280 : '100%') // ★ 0.201.2：平板固定 280 居中（手机 100% 不变）
          .margin({ top: 16 })
          .onClick(() => {
            this.startCardImport('import', this.askSheetTitle, this.askSheetDefinition, this.askSheetImages);
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
            this.startCardImport('branch', this.askSheetTitle, this.askSheetDefinition, this.askSheetImages);
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
      .width(this.isTablet ? 460 : '100%') // ★ 0.201.2：平板固定 460 居中（手机 100% 贴底不变）——用户实测宽屏按钮拉满太长；规范入 UI_GUIDELINES「模态弹窗与操作按钮」
      .borderRadius(RADIUS_NAV) // ★ 0.201.2：四角圆角（宽屏居中浮岛感；手机贴底时下圆角贴屏不可见无副作用）
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

  // ★ 0.148: editor dialog — add & edit share it; tap the mask to dismiss
  // ★ 0.210.2：根改 Stack（原 Column+Center 布局流里，mini 遮罩 100% 尺寸解析受兄弟元素影响
  //   不铺满——dump 实锤 [520,1049] 起；Stack 子项百分比铺满语义可靠，双弹窗层互不干扰）
  @Builder
  editorDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        Text(this.editorIsAdd ? '新增知识卡' : '编辑知识卡')
          .fontSize(FONT_SIZE_SCREEN_TITLE)
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
        TextInput({ text: this.editorTitle, placeholder: '标题（必填）' })
          .fontSize(14)
          .width('100%')
          .height(40)
          .margin({ top: 16 })
          .padding({ left: 12, right: 12 })
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
          .onChange((value: string) => {
            this.editorTitle = value;
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
                      .fontColor(TEXT_PRIMARY)
                      .backgroundColor(DANGER)
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
                .fontColor(TEXT_SECONDARY)
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
          .backgroundColor(SURFACE_SOFT)
          .onChange((value: string) => {
            this.editorDefinition = value;
          })
        // ── ★ 0.202.2：标签区 chip 化（用户拍板：弃逗号输入——大小写/分隔符心智负担；同提炼页交互）──
        Column() {
          Text(parseTags(this.editorTags).length > 0 ? '标签（点 × 删除 · 长按修改）' : '标签')
            .fontSize(11)
            .fontColor(TEXT_TERTIARY)
            .alignSelf(ItemAlign.Start)
            .margin({ bottom: 6 })
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(parseTags(this.editorTags), (t: string) => {
              Row({ space: 4 }) {
                Text(t)
                  .fontSize(11)
                  .fontColor(BRAND_SECONDARY)
                Text('×')
                  .fontSize(12)
                  .fontColor(TEXT_TERTIARY)
                  .onClick(() => {
                    this.removeEditorTag(t);
                  })
              }
              .height(24)
              .padding({ left: 10, right: 8 })
              .borderRadius(6)
              .border({ width: 1, color: BRAND_SECONDARY })
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
              .fontColor(TEXT_SECONDARY)
              .border({ width: 1, color: STROKE_CARD, style: BorderStyle.Dashed })
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
                      .fontColor(TEXT_PRIMARY)
                      .backgroundColor(DANGER)
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
                .fontColor(TEXT_SECONDARY)
            }
            .alignSelf(ItemAlign.Start)
            .onClick(() => {
              this.selectEditorImage();
            })
          }
        }
        .width('100%')
        .margin({ top: 10 })
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
      .width(this.isTablet ? 520 : '86%') // ★ 0.201.2：平板固定 520（86% 在宽屏超宽、双按钮被拉长——用户实测）；规范入 UI_GUIDELINES「模态弹窗与操作按钮」
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
      .padding(20)
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
              .fontColor(TEXT_PRIMARY)
              .margin({ bottom: 10 })
            TextInput({ text: this.tagEditNew, placeholder: '标签名（2~6 字最佳）' })
              .fontSize(14)
              .width('100%')
              .height(40)
              .padding({ left: 12, right: 12 })
              .borderRadius(RADIUS_CONTROL)
              .backgroundColor(SURFACE_SOFT)
              .onChange((v: string) => {
                this.tagEditNew = v;
              })
            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .fontColor(TEXT_SECONDARY)
                .backgroundColor(Color.Transparent)
                .onClick(() => {
                  this.tagEditVisible = false;
                })
              Button('确定')
                .layoutWeight(1)
                .backgroundColor(BRAND_PRIMARY)
                .fontColor(TEXT_PRIMARY)
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
          .backgroundColor(SURFACE_NODE)
          .border({ width: 1, color: STROKE_CARD })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(0,0,0,0.45)')
        .onClick(() => {
          this.tagEditVisible = false;
        })
      }
    }
    .width('100%')
    .height('100%')

    .backgroundColor(OVERLAY)
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
          .fontColor(TEXT_PRIMARY)
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
          .fontColor(TEXT_PRIMARY)
        Row() {
          Image(this.deleteConfirmNoRemind ? $r('app.media.checkbox_on') : $r('app.media.checkbox_off')) // ★ 0.212.0：☑/☐ 换 svg
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

  // ============================================================
  // ★ 0.207.0：文件夹 / 导入 / 导出 —— 方法集
  // ============================================================

  /** 当前目录名链（根→…→当前）——面包屑/导出命名用 */
  @Computed
  get currentChain(): KFolder[] {
    return folderChain(this.knowledgeBank, this.currentFolderId);
  }

  folderParentId(): string {
    const ch = this.currentChain;
    return ch.length > 0 ? ch[ch.length - 1].parentId : '';
  }

  folderFullPath(f: KFolder): string {
    return folderChain(this.knowledgeBank, f.id).map((x: KFolder): string => x.name).join(' › ');
  }

  openFolderCreate(): void {
    this.folderDialogIsRename = false;
    this.folderDialogTargetId = '';
    this.folderDialogName = '';
    this.folderDialogVisible = true;
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
    if (this.folderDialogIsRename) {
      renameFolder(this.knowledgeBank, this.folderDialogTargetId, nm);
    } else {
      addFolder(this.knowledgeBank, nm, this.currentFolderId);
      const tp: Record<string, string> = {};
      track(this.getUIContext().getHostContext() as Context, 'folder_create', tp);
    }
    this.folderDialogVisible = false;
  }

  requestDeleteFolder(f: KFolder): void {
    deleteFolder(this.knowledgeBank, f.id);
    if (this.currentFolderId === f.id) {
      this.currentFolderId = this.folderParentId();
    }
    this.showToast(`已删除「${f.name}」——卡片已移到上一级`);
  }

  /** 移动/复制确认（folderPicker 行点击） */
  confirmFolderTarget(folderId: string): void {
    const ids = [...this.selectedIds];
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
  async pickImportFile(): Promise<void> {
    try {
      const doc = new picker.DocumentViewPicker();
      const selOpt = new picker.DocumentSelectOptions();
      selOpt.fileSuffixFilters = ['.txt', '.csv', '.xlsx'];
      selOpt.maxSelectNumber = 1;
      const uris: string[] = await doc.select(selOpt);
      if (uris.length === 0) {
        return;
      }
      const uri = uris[0];
      let rows: ImportRow[] = [];
      let fmt = 'txt';
      if (uri.toLowerCase().endsWith('.xlsx')) {
        fmt = 'xlsx';
        rows = await readXlsxRows(uri);
      } else {
        fmt = uri.toLowerCase().endsWith('.csv') ? 'csv' : 'txt';
        rows = parseTextToRows(readTextFile(uri), fmt);
      }
      if (rows.length === 0) {
        this.showToast('没解析出卡片：每行需「标题 + 分隔符 + 背面」（xlsx 取 A/B/C 三列）');
        return;
      }
      this.importRows = rows;
      this.importFormat = fmt;
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
    idMap.set('', this.currentFolderId);
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
        0, 0, 0, 0, r.tags, '', this.currentFolderId));
      n++;
    }
    const tp: Record<string, string> = {}; tp['format'] = this.importFormat; tp['count'] = `${n}`;
    track(this.getUIContext().getHostContext() as Context, 'batch_import', tp);
    this.showToast(`已导入 ${n} 张`);
    this.importPreviewVisible = false;
  }

  /** 导出当前视图卡片为 CSV（无搜索=当前文件夹全部；搜索中=结果集——导出所见） */
  async doExportCsv(): Promise<void> {
    try {
      const cards = this.filteredCards;
      if (cards.length === 0) {
        this.showToast('当前没有卡片可导出');
        return;
      }
      const names = this.currentChain.map((x: KFolder): string => x.name).join('/');
      const scopeName = names.length === 0 ? '知识库根目录' : names;
      const csv = cardsToCsv(cards, scopeName);
      // ★ 写法抄 BackupUtil 0.205.1 定稿：DocumentViewPicker.save + Options 实例（本 SDK 无 DocumentSavePicker 类）
      const saver = new picker.DocumentViewPicker();
      const saveOpt = new picker.DocumentSaveOptions();
      saveOpt.newFileNames = ['DAGAI_知识库.csv'];
      const uris: string[] = await saver.save(saveOpt);
      if (uris.length === 0) {
        return;
      }
      const f = fileIo.openSync(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, csv); // 0.205.1 教训：WRITE_ONLY|CREATE|TRUNC 组合（autoCreateEmptyFile 预创建坑在 save picker 无此问题，写入字节数隐含校验）
      fileIo.closeSync(f);
      const tp: Record<string, string> = {}; tp['count'] = `${cards.length}`;
      track(this.getUIContext().getHostContext() as Context, 'export_csv', tp);
      this.showToast(`已导出 ${cards.length} 张 → CSV`);
    } catch (_e) {
      this.showToast('导出失败');
    }
  }

  // ============================================================
  // ★ 0.207.0：builders——面包屑 / 文件夹弹窗 / 目标选择 / 导入预览
  // ============================================================

  @Builder
  folderBreadcrumb() {
    Scroll() {
      Row() {
        Text('知识库')
          .fontSize(13)
          .fontColor(TEXT_TERTIARY)
          .onClick(() => {
            this.currentFolderId = '';
          })
        ForEach(this.currentChain, (f: KFolder, idx: number) => {
          Text(' › ')
            .fontSize(12)
            .fontColor(TEXT_TERTIARY)
          Text(f.name)
            .fontSize(13)
            .fontColor(idx === this.currentChain.length - 1 ? TEXT_PRIMARY : BRAND_SECONDARY)
            .maxLines(1)
            .onClick(() => {
              this.currentFolderId = f.id;
            })
        }, (f: KFolder) => f.id)
      }
      .padding({ left: 16, right: 16, top: 2, bottom: 2 })
    }
    .scrollable(ScrollDirection.Horizontal) // ★ API26 Scroll 构造只收 Scroller——水平滚动用 scrollable 属性
    .width('100%')
    .align(Alignment.Start)
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
      .width('86%')
      .padding(18)
      .borderRadius(14)
      .backgroundColor(BG_APP)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(OVERLAY)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.folderDialogVisible = false;
    })
  }

  @Builder
  folderPickerDialog() {
    Column() {
      Column() {
        Text(this.moveOrCopyMode === 'copy' ? `复制 ${this.selectedIds.length} 张到…` : `移动 ${this.selectedIds.length} 张到…`)
          .fontSize(16)
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
        Scroll() {
          Column() {
            Row() {
              Text('📂 根目录')
                .fontSize(14)
                .fontColor(TEXT_PRIMARY)
                .layoutWeight(1)
              Text('选择')
                .fontSize(12)
                .fontColor(BRAND_SECONDARY)
            }
            .width('100%')
            .padding(12)
            .borderRadius(8)
            .backgroundColor(SURFACE_SOFT)
            .margin({ top: 10 })
            .onClick(() => {
              this.confirmFolderTarget('');
            })
            ForEach(this.knowledgeBank.folders, (f: KFolder) => {
              Row() {
                Text('📁 ' + this.folderFullPath(f))
                  .fontSize(13)
                  .fontColor(TEXT_PRIMARY)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text('选择')
                  .fontSize(12)
                  .fontColor(BRAND_SECONDARY)
              }
              .width('100%')
              .padding(12)
              .borderRadius(8)
              .backgroundColor(SURFACE_SOFT)
              .margin({ top: 6 })
              .onClick(() => {
                this.confirmFolderTarget(f.id);
              })
            }, (f: KFolder) => f.id)
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
          })
      }
      .width('86%')
      .constraintSize({ maxHeight: '80%' })
      .padding(18)
      .borderRadius(14)
      .backgroundColor(BG_APP)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(OVERLAY)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.folderPickerVisible = false;
    })
  }

  @Builder
  importPreviewDialog() {
    Column() {
      Column() {
        Text('批量导入预览')
          .fontSize(16)
          .fontWeight(600)
          .fontColor(TEXT_PRIMARY)
        Text(`${this.importFileName} · 解析到 ${this.importRows.length} 张 · ${this.importFormat.toUpperCase()} 格式`)
          .fontSize(12)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 6 })
        Scroll() {
          Column() {
            ForEach(this.importRows.slice(0, 10), (r: ImportRow, i: number) => {
              Column() {
                Text(`${i + 1}. ${r.title}`)
                  .fontSize(13)
                  .fontColor(TEXT_PRIMARY)
                  .maxLines(1)
                Text(r.definition)
                  .fontSize(12)
                  .fontColor(TEXT_TERTIARY)
                  .maxLines(1)
                  .margin({ top: 2 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(8)
              .borderRadius(8)
              .backgroundColor(SURFACE_SOFT)
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
            .fontColor(TEXT_TERTIARY)
            .margin({ top: 4 })
        }
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .backgroundColor(SURFACE_SOFT)
            .fontColor(TEXT_SECONDARY)
            .onClick(() => {
              this.importPreviewVisible = false;
            })
          Button(`导入 ${this.importRows.length} 张`)
            .layoutWeight(1)
            .backgroundColor(BRAND_PRIMARY)
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
      .backgroundColor(BG_APP)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(OVERLAY)
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
        fid = segs.length === 0 ? this.currentFolderId : ensureFolderPath(this.knowledgeBank, segs, this.currentFolderId);
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
          .fontColor(TEXT_PRIMARY)
        Text(`${this.packFileName} · ${this.packData.folders.length} 个文件夹 · ${this.packData.cards.length} 张卡 · 新子树挂当前文件夹`)
          .fontSize(12)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 6 })
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
                    .fontColor(TEXT_PRIMARY)
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${this.packSubtreeCardCount(f.refId)} 张`)
                    .fontSize(12)
                    .fontColor(TEXT_TERTIARY)
                }
                .width('100%')
                .padding(10)
                .borderRadius(8)
                .backgroundColor(SURFACE_SOFT)
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
                  .fontColor(TEXT_PRIMARY)
                  .layoutWeight(1)
                Text(`${this.packRootCardCount()} 张`)
                  .fontSize(12)
                  .fontColor(TEXT_TERTIARY)
              }
              .width('100%')
              .padding(10)
              .borderRadius(8)
              .backgroundColor(SURFACE_SOFT)
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
            .backgroundColor(SURFACE_SOFT)
            .fontColor(TEXT_SECONDARY)
            .onClick(() => {
              this.packPreviewVisible = false;
            })
          Button('导入所选')
            .layoutWeight(1)
            .backgroundColor(BRAND_PRIMARY)
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
      .backgroundColor(BG_APP)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(OVERLAY)
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
          .fontColor(TEXT_PRIMARY)
        Text(`${this.apkgFileName} · ${this.apkgCards.length} 张卡 · ${this.apkgMediaCount} 张图片 · 牌组自动映射为文件夹链`)
          .fontSize(12)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 6 })
        Text('Anki 复习进度不迁移（DAGAI 从新卡开始，用自己的算法）；音频不迁移（App 自带语音）')
          .fontSize(11)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 2 })
        Scroll() {
          Column() {
            ForEach(this.apkgDeckNames(), (deck: string) => {
              Row() {
                Text('🗂 ' + deck)
                  .fontSize(13)
                  .fontColor(TEXT_PRIMARY)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${this.apkgDeckCounts[deck]} 张`)
                  .fontSize(12)
                  .fontColor(TEXT_TERTIARY)
              }
              .width('100%')
              .padding(10)
              .borderRadius(8)
              .backgroundColor(SURFACE_SOFT)
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
            .backgroundColor(SURFACE_SOFT)
            .fontColor(TEXT_SECONDARY)
            .onClick(() => {
              this.apkgPreviewVisible = false;
            })
          Button(`导入 ${this.apkgCards.length} 张`)
            .layoutWeight(1)
            .backgroundColor(BRAND_PRIMARY)
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
      .backgroundColor(BG_APP)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(OVERLAY)
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

          // ★ 0.207.0：面包屑（非根目录显示；点级名跳转，点「知识库」回根）
          if (this.currentFolderId.length > 0) {
            this.folderBreadcrumb()
          }

          if (!this.multiSelectMode) {
            // ★ 0.148: search box + sort toggle (live filtering via @Computed)
            Row() {
              TextInput({ text: this.searchKeyword, placeholder: '搜索标题 / 内容' })
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
              // ★ 0.207.0：批量移动/复制到文件夹（单张=多选 1 张，交互统一）
              Button('移动')
                .fontSize(13)
                .fontColor(BRAND_SECONDARY)
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
                .fontColor(BRAND_SECONDARY)
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

          if (this.knowledgeBank.cards.length === 0 && this.knowledgeBank.folders.length === 0) {
            // Empty bank — guide the user to both entry points (0.148 adds manual add)
            Column() {
              Text('知识库为空')
                .fontSize(16)
                .fontColor(TEXT_TERTIARY)
              Text('点右上角 + 手动添加，或长按对话气泡选中文本入知识库')
                .fontSize(12)
                .fontColor(TEXT_TERTIARY)
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
                .fontColor(TEXT_TERTIARY)
              Text(this.searchKeyword.length > 0 ? '换个关键词试试' : '点右上角 + 导入或新建')
                .fontSize(12)
                .fontColor(TEXT_TERTIARY)
                .margin({ top: 8 })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            List({ space: 8 }) {
              // ★ 0.207.0：文件夹区（当前目录子文件夹，新在前；搜索/多选模式隐藏）
              if (this.searchKeyword.trim().length === 0 && !this.multiSelectMode) {
                ForEach(this.currentFolders, (f: KFolder) => {
                  ListItem() {
                    Row() {
                      Text('📁')
                        .fontSize(18)
                        .margin({ right: 10 })
                      Text(f.name)
                        .fontSize(14)
                        .fontWeight(600)
                        .fontColor(TEXT_PRIMARY)
                        .layoutWeight(1)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(`${this.folderCardCount(f.id)} 张`)
                        .fontSize(12)
                        .fontColor(TEXT_TERTIARY)
                      // ⋯ 菜单：重命名/删除（与行点击分流——行点击=进入目录）
                      Text('⋯')
                        .fontSize(18)
                        .fontColor(TEXT_TERTIARY)
                        .padding({ left: 10, right: 2 })
                        .bindMenu([
                          { value: '重命名', action: () => { this.openFolderRename(f); } },
                          { value: '删除文件夹（卡片移到上一级）', action: () => { this.requestDeleteFolder(f); } },
                          { value: '★ 导出此文件夹包（DagPack）', action: () => { this.exportDagPack(f.id); } }
                        ])
                    }
                    .width('100%')
                    .padding(12)
                    .borderRadius(RADIUS_CONTROL)
                    .backgroundColor(SURFACE_SOFT)
                    .borderColor(STROKE_CARD)
                    .borderWidth(1)
                    .alignItems(VerticalAlign.Center)
                    .onClick(() => {
                      this.currentFolderId = f.id;
                      this.searchKeyword = ''; // 进目录清搜索（目录视图）
                    })
                  }
                }, (f: KFolder) => f.id)
              }
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
                      //   灰色小字「问AI?」与标题平行，颜色同「未学习」标签（TEXT_TERTIARY 弱化灰）：
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
                                          .fontColor(BRAND_SECONDARY)
                                          .height(20)
                                          .padding({ left: 8, right: 8 })
                                          .borderRadius(4)
                                          .border({ width: 1, color: BRAND_SECONDARY })
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
                              .fontColor(TEXT_PRIMARY)
                              .maxLines(1)
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
                              .fontColor(TEXT_PRIMARY)
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .constraintSize({ maxWidth: '62%' })
                            if (parseTags(c.tags).length > 0) {
                              Scroll() {
                                Row({ space: 6 }) {
                                  ForEach(parseTags(c.tags), (t: string) => {
                                    Text(t)
                                      .fontSize(10)
                                      .fontColor(BRAND_SECONDARY)
                                      .height(20)
                                      .padding({ left: 8, right: 8 })
                                      .borderRadius(4)
                                      .border({ width: 1, color: BRAND_SECONDARY })
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
                        .fontColor(TEXT_SECONDARY)
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
                  .backgroundColor(SURFACE_NODE) // ★ 0.183.0：卡片底对齐节点卡片规格（SURFACE_NODE + STROKE_CARD 描边）
                  .borderColor(STROKE_CARD)
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
              }, (c: KnowledgeCard) => c.id)
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
        if (this.folderDialogVisible) {
          this.folderDialog()
        }
        if (this.folderPickerVisible) {
          this.folderPickerDialog()
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
      }
      .backgroundColor(BG_CANVAS) // ★ 0.183.0：页面根底色补齐——原根容器未设底色透出窗口纯黑（实测 #000000），与首页 BG_APP/画布 BG_CANVAS 暗紫底不一致，统一应用底色
    }
    // ★ 0.159 pattern: hide the system title bar — the top bar is self-drawn
    .hideTitleBar(true)
    // ★ 0.148: back gesture closes dialogs / multi-select first, page last
    .onBackPressed(() => {
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
      if (this.currentFolderId.length > 0) {
        this.currentFolderId = this.folderParentId();
        return true;
      }
      return false;
    })
  }
}
