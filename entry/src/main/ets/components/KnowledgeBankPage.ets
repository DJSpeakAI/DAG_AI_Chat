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

import { KnowledgeCard, KnowledgeBankStore } from '../common/KnowledgeModel';
import { connectKnowledgeBank, addKnowledgeCard, removeKnowledgeCard, updateKnowledgeCard, removeCardsByIds } from '../utils/KnowledgeStoreUtil';
import { formatNextReviewLabel } from '../utils/MemoryAlgorithm'; // ★ 0.188.0：下次复习时间标签（记忆算法·知识库复刻）
import { KnowledgeCountStore, connectKnowledgeCount } from '../common/ChatModel'; // ★ 0.161.2: knowledge-card count settings (same PersistenceV2 instance as ChatPage review areas)
import { photoAccessHelper } from '@kit.MediaLibraryKit'; // ★ 0.160: editor image picking
import { fileIo } from '@kit.CoreFileKit'; // ★ 0.160: read picked photo into base64
import { buffer } from '@kit.ArkTS'; // ★ 0.160: ArrayBuffer → base64
// ★ 0.183.0：UI 收敛到 DesignTokens（UI_GUIDELINES 唯一真相源；v0.166.3 锁暗色后 isDark 三元为死代码，全部清除）
  import { BG_APP, TEXT_PRIMARY, TEXT_SECONDARY, TEXT_TERTIARY, SURFACE_NODE, SURFACE_HOVER, SURFACE_SOFT, BRAND_PRIMARY, BRAND_SECONDARY, DANGER, OVERLAY, STROKE_CARD, RADIUS_CONTROL, RADIUS_NAV, FONT_SIZE_SCREEN_TITLE } from '../common/DesignTokens'; // ★ 0.191.0：加 SURFACE_HOVER/BRAND_SECONDARY（排序按钮激活态）

@ComponentV2
export struct KnowledgeBankPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  knowledgeBank: KnowledgeBankStore = connectKnowledgeBank(); // isolated PersistenceV2 instance

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
  // ★ 0.160: editor image state — base64 data URI, same storage pattern as
  // ChatPage's knowledge editor; empty string = no image
  @Local editorImageUri: string = '';
  // ★ 0.160: fullscreen preview of the editor image (tap thumbnail to open)
  @Local editorImagePreviewVisible: boolean = false;

  // ★ 0.148: single-delete confirm dialog state
  @Local deleteConfirmVisible: boolean = false;
  @Local deleteConfirmNoRemind: boolean = false;
  @Local pendingDeleteId: string = '';

  // ★ 0.148: batch-delete confirm dialog state (always shown, no no-remind)
  @Local batchConfirmVisible: boolean = false;

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
      list = [...this.knowledgeBank.cards];
    } else {
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
    this.editorImageUri = ''; // ★ 0.160: new card starts with no image
    this.editorVisible = true;
  }

  openEditEditor(c: KnowledgeCard): void {
    this.editorIsAdd = false;
    this.editorId = c.id;
    this.editorTitle = c.title;
    this.editorDefinition = c.definition;
    this.editorImageUri = c.imageUri; // ★ 0.160: pre-fill the existing image for edit/remove
    this.editorVisible = true;
  }

  saveEditor(): void {
    const title = this.editorTitle.trim();
    if (title.length === 0) {
      this.showToast('标题不能为空');
      return;
    }
    const definition = this.editorDefinition.trim();
    if (this.editorIsAdd) {
      // addKnowledgeCard auto-fills id/createdAt; no duplicate check —
      // cards may legitimately share a title (0.146 spec)
      addKnowledgeCard(this.knowledgeBank, new KnowledgeCard('', title, definition, this.editorImageUri, 0));
    } else {
      updateKnowledgeCard(this.knowledgeBank, this.editorId, title, definition, this.editorImageUri);
    }
    this.editorVisible = false;
  }

  // ★ 0.160: pick a photo from the gallery → base64 data URI (same flow as
  // ChatPage's knowledge editor: single select, read via fileIo, encode with
  // buffer). Failure is silent — the editor keeps its previous image state.
  async selectEditorImage(): Promise<void> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select({ maxSelectNumber: 1 });
      if (result.photoUris.length > 0) {
        const uri = result.photoUris[0];
        const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
        const stat = fileIo.statSync(file.fd);
        const arrayBuffer = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, arrayBuffer);
        fileIo.closeSync(file);
        const base64 = buffer.from(arrayBuffer).toString('base64');
        this.editorImageUri = `data:image/jpeg;base64,${base64}`;
      }
    } catch (err) {
      // 选图取消/读取失败静默忽略（防崩溃）
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
      Button('←')
        .fontSize(18)
        .backgroundColor(Color.Transparent)
        .fontColor(TEXT_PRIMARY)
        .padding({ left: 4, right: 4 })
        .margin({ right: 4 })
        .onClick(() => {
          this.pathStack.pop();
        })
      Text('知识库')
        .fontSize(FONT_SIZE_SCREEN_TITLE) // ★ 0.183.0：18→16 对齐 ScreenTitle 规范
        .fontWeight(600)
        .fontColor(TEXT_PRIMARY)
      Blank()
        .layoutWeight(1)
      // ★ 0.191.0 定稿：两个独立排序按钮（创建时间/下次复习时间各一个）——激活态紫字+底色；
      //   再点同按钮切倒序（最新↓↔最新↑ / 需复习↑↔需复习↓），箭头随方向实时变
      Button(this.sortMode === 1 ? '最新↑' : '最新↓')
        .fontSize(12)
        .backgroundColor(this.sortMode === 0 || this.sortMode === 1 ? SURFACE_HOVER : Color.Transparent)
        .fontColor(this.sortMode === 0 || this.sortMode === 1 ? BRAND_SECONDARY : TEXT_TERTIARY)
        .padding({ left: 8, right: 4 })
        .margin({ right: 2 })
        .onClick(() => {
          this.sortMode = this.sortMode === 0 ? 1 : 0;
        })
      Button(this.sortMode === 3 ? '需复习↓' : '需复习↑')
        .fontSize(12)
        .backgroundColor(this.sortMode >= 2 ? SURFACE_HOVER : Color.Transparent)
        .fontColor(this.sortMode >= 2 ? BRAND_SECONDARY : TEXT_TERTIARY)
        .padding({ left: 8, right: 4 })
        .margin({ right: 4 })
        .onClick(() => {
          this.sortMode = this.sortMode === 2 ? 3 : 2;
        })
      // ★ 0.161.2: card-count settings button — left of "+", visible in both normal & multi-select modes
      Button('⚙')
        .fontSize(18)
        .backgroundColor(Color.Transparent)
        .fontColor(TEXT_PRIMARY)
        .padding({ left: 8, right: 4 })
        .margin({ right: 4 })
        .onClick(() => {
          // free-input box pre-fills only when current value is a custom one (> 3, quick options are 1/2/3)
          this.cardCustomInput = this.knowledgeCountStore.knowledgeCount > 3 ? `${this.knowledgeCountStore.knowledgeCount}` : '';
          this.cardInputError = '';
          this.cardSettingsVisible = true;
        })
      if (!this.multiSelectMode) {
        // ★ 0.148: add button — top bar's right, opens the editor dialog
        Button('+')
          .fontSize(20)
          .backgroundColor(Color.Transparent)
          .fontColor(TEXT_PRIMARY)
          .padding({ left: 8, right: 8 })
          .onClick(() => {
            this.openAddEditor();
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
    .padding({ left: 8, right: 16, top: 8, bottom: 4 })
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
        Row() {
          Button('1（默认）')
            .fontSize(14)
            .fontColor(this.knowledgeCountStore.knowledgeCount === 1 ? TEXT_PRIMARY : (TEXT_SECONDARY))
            .backgroundColor(this.knowledgeCountStore.knowledgeCount === 1 ? BRAND_PRIMARY : Color.Transparent)
            .borderRadius(RADIUS_CONTROL)
            .layoutWeight(1)
            .onClick(() => {
              this.knowledgeCountStore.knowledgeCount = 1; // PersistenceV2 自动落盘，两处复习区即时生效
              this.cardSettingsVisible = false;
            })
          Button('2')
            .fontSize(14)
            .fontColor(this.knowledgeCountStore.knowledgeCount === 2 ? TEXT_PRIMARY : (TEXT_SECONDARY))
            .backgroundColor(this.knowledgeCountStore.knowledgeCount === 2 ? BRAND_PRIMARY : Color.Transparent)
            .borderRadius(RADIUS_CONTROL)
            .layoutWeight(1)
            .margin({ left: 8 })
            .onClick(() => {
              this.knowledgeCountStore.knowledgeCount = 2;
              this.cardSettingsVisible = false;
            })
          Button('3')
            .fontSize(14)
            .fontColor(this.knowledgeCountStore.knowledgeCount === 3 ? TEXT_PRIMARY : (TEXT_SECONDARY))
            .backgroundColor(this.knowledgeCountStore.knowledgeCount === 3 ? BRAND_PRIMARY : Color.Transparent)
            .borderRadius(RADIUS_CONTROL)
            .layoutWeight(1)
            .margin({ left: 8 })
            .onClick(() => {
              this.knowledgeCountStore.knowledgeCount = 3;
              this.cardSettingsVisible = false;
            })
        }
        .width('100%')
        .margin({ top: 16 })
        Row() {
          Text('自由输入：')
            .fontSize(14)
            .fontColor(TEXT_SECONDARY)
          TextInput({ text: this.cardCustomInput, placeholder: '1~20' })
            .fontSize(14)
            .layoutWeight(1)
            .height(40)
            .padding({ left: 12, right: 12 })
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(SURFACE_SOFT)
            .type(InputType.Number)
            .onChange((value: string) => {
              this.cardCustomInput = value;
              this.cardInputError = ''; // 输入变化即清错误提示
            })
          Button('确定')
            .fontSize(14)
            .fontColor(TEXT_PRIMARY)
            .backgroundColor(BRAND_PRIMARY)
            .borderRadius(RADIUS_CONTROL)
            .margin({ left: 8 })
            .padding({ left: 14, right: 14 })
            .onClick(() => {
              const n = parseInt(this.cardCustomInput, 10);
              if (!Number.isNaN(n) && n >= 1 && n <= 20) {
                this.knowledgeCountStore.knowledgeCount = n;
                this.cardSettingsVisible = false;
              } else {
                this.cardInputError = '请输入 1~20 的整数';
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
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(OVERLAY)
  }

  // ★ 0.148: editor dialog — add & edit share it; tap the mask to dismiss
  @Builder
  editorDialog() {
    Column() {
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
        // ★ 0.160: image row — with image: thumbnail (tap = fullscreen preview)
        // + remove + replace; without image: a single add button.
        // The URI is only committed to the store on 保存 (same draft pattern
        // as title/definition — cancel discards the image change too).
        Row() {
          if (this.editorImageUri.length > 0) {
            Image(this.editorImageUri)
              .height(56)
              .width(84)
              .objectFit(ImageFit.Cover)
              .borderRadius(RADIUS_CONTROL)
              .onClick(() => {
                this.editorImagePreviewVisible = true;
              })
            Text('删除图片')
              .fontSize(13)
              .fontColor(DANGER)
              .margin({ left: 12 })
              .onClick(() => {
                this.editorImageUri = '';
              })
            Text('换一张')
              .fontSize(13)
              .fontColor(TEXT_SECONDARY) // ★ 0.183.0：操作文字对齐 ChatPage「添加图片」先例（TEXT_SECONDARY）
              .margin({ left: 8 })
              .onClick(() => {
                this.selectEditorImage();
              })
          } else {
            Text('🖼️ 添加图片')
              .fontSize(13)
              .fontColor(TEXT_SECONDARY) // ★ 0.183.0：对齐 ChatPage「添加图片」按钮文字色先例
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

  // ★ 0.160: fullscreen preview of the editor image — tap anywhere to close
  @Builder
  editorImagePreview() {
    Column() {
      Image(this.editorImageUri)
        .objectFit(ImageFit.Contain)
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .onClick(() => {
      this.editorImagePreviewVisible = false;
    })
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
              this.confirmDeleteCard();
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

          if (this.knowledgeBank.cards.length === 0) {
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
          } else if (this.filteredCards.length === 0) {
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
              ForEach(this.filteredCards, (c: KnowledgeCard) => {
                ListItem() {
                  Row() {
                    if (this.multiSelectMode) {
                      // ★ 0.148: multi-select check indicator — an icon Text,
                      // NOT a Checkbox: the whole row handles tap-toggle and a
                      // real Checkbox would fire a second onChange
                      Text(this.selectedIds.includes(c.id) ? '☑' : '☐')
                        .fontSize(20)
                        .fontColor(this.selectedIds.includes(c.id) ? BRAND_PRIMARY : TEXT_TERTIARY)
                        .margin({ right: 8 })
                    }
                    // Entry content block: title -> definition -> image thumbnail
                    Column() {
                      Text(c.title)
                        .fontSize(16)
                        .fontWeight(600)
                        .fontColor(TEXT_PRIMARY)
                      Text(c.definition)
                        .fontSize(13)
                        .fontColor(TEXT_SECONDARY)
                        .margin({ top: 2 })
                      // ★ 0.188.0：下次复习时间（未学习灰 / 已到期红 / 常规灰，复刻单词库）
                      Text(this.nextReviewLabel(c))
                        .fontSize(11)
                        .fontColor(this.nextReviewColor(c))
                        .margin({ top: 2 })
                      if (c.imageUri.length > 0) {
                        // Card image thumbnail — not rendered when empty
                        Image(c.imageUri)
                          .height(64)
                          .width(96)
                          .objectFit(ImageFit.Cover)
                          .borderRadius(RADIUS_CONTROL)
                          .margin({ top: 6 })
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    .onClick(() => {
                      this.onItemTap(c);
                    })

                    if (!this.multiSelectMode) {
                      // Single-delete button — hidden while multi-selecting
                      Button('×')
                        .fontSize(16)
                        .fontColor(DANGER)
                        .backgroundColor(Color.Transparent)
                        .padding({ left: 8, right: 8 })
                        .onClick(() => {
                          this.requestDeleteCard(c);
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
                          this.enterMultiSelect(c.id);
                        }
                      })
                  )
                }
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
        // ★ 0.160: editor image fullscreen preview — topmost layer
        if (this.editorImagePreviewVisible) {
          this.editorImagePreview()
        }
      }
      .backgroundColor(BG_APP) // ★ 0.183.0：页面根底色补齐——原根容器未设底色透出窗口纯黑（实测 #000000），与首页 BG_APP/画布 BG_CANVAS 暗紫底不一致，统一应用底色
    }
    // ★ 0.159 pattern: hide the system title bar — the top bar is self-drawn
    .hideTitleBar(true)
    // ★ 0.148: back gesture closes dialogs / multi-select first, page last
    .onBackPressed(() => {
      // ★ 0.160: image preview closes first (topmost layer)
      if (this.editorImagePreviewVisible) {
        this.editorImagePreviewVisible = false;
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
      if (this.multiSelectMode) {
        this.exitMultiSelect();
        return true;
      }
      return false;
    })
  }
}
