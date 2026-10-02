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

import { AppStorageV2 } from '@kit.ArkUI';
import { KnowledgeCard, KnowledgeBankStore } from '../common/KnowledgeModel';
import { connectKnowledgeBank, addKnowledgeCard, removeKnowledgeCard, updateKnowledgeCard, removeCardsByIds } from '../utils/KnowledgeStoreUtil';
import { ThemeStore } from '../entryability/EntryAbility'; // dark/light theme
import { photoAccessHelper } from '@kit.MediaLibraryKit'; // ★ 0.160: editor image picking
import { fileIo } from '@kit.CoreFileKit'; // ★ 0.160: read picked photo into base64
import { buffer } from '@kit.ArkTS'; // ★ 0.160: ArrayBuffer → base64

@ComponentV2
export struct KnowledgeBankPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  knowledgeBank: KnowledgeBankStore = connectKnowledgeBank(); // isolated PersistenceV2 instance

  // ★ 0.148: search / sort state
  @Local searchKeyword: string = '';
  @Local sortDesc: boolean = true; // default: newest first (desc)

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

  // Global theme state (same pattern as ChatPage / WordBankPage)
  getThemeStore(): ThemeStore {
    return AppStorageV2.connect(ThemeStore, 'theme-store', () => new ThemeStore()) as ThemeStore;
  }

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
    list.sort((a: KnowledgeCard, b: KnowledgeCard) => {
      return this.sortDesc ? b.createdAt - a.createdAt : a.createdAt - b.createdAt;
    });
    return list;
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
      console.error(`[KnowledgeBankPage] selectEditorImage error: ${(err as Error).message}`);
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
        .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
        .padding({ left: 4, right: 4 })
        .margin({ right: 4 })
        .onClick(() => {
          this.pathStack.pop();
        })
      Text('知识库')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
      Blank()
        .layoutWeight(1)
      if (!this.multiSelectMode) {
        // ★ 0.148: add button — top bar's right, opens the editor dialog
        Button('+')
          .fontSize(20)
          .backgroundColor(Color.Transparent)
          .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
          .padding({ left: 8, right: 8 })
          .onClick(() => {
            this.openAddEditor();
          })
      } else {
        // ★ 0.148: multi-select replaces the add button with batch delete
        Button(`删除(${this.selectedIds.length})`)
          .fontSize(14)
          .fontColor('#F44336')
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

  // ★ 0.148: editor dialog — add & edit share it; tap the mask to dismiss
  @Builder
  editorDialog() {
    Column() {
      Column() {
        Text(this.editorIsAdd ? '新增知识卡' : '编辑知识卡')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
        TextInput({ text: this.editorTitle, placeholder: '标题（必填）' })
          .fontSize(14)
          .width('100%')
          .height(40)
          .margin({ top: 16 })
          .padding({ left: 12, right: 12 })
          .borderRadius(8)
          .backgroundColor(this.getThemeStore().isDark ? '#1E1E1E' : '#F5F5F5')
          .onChange((value: string) => {
            this.editorTitle = value;
          })
        TextArea({ text: this.editorDefinition, placeholder: '内容（选填）' })
          .fontSize(14)
          .width('100%')
          .height(96)
          .margin({ top: 8 })
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(8)
          .backgroundColor(this.getThemeStore().isDark ? '#1E1E1E' : '#F5F5F5')
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
              .borderRadius(4)
              .onClick(() => {
                this.editorImagePreviewVisible = true;
              })
            Text('删除图片')
              .fontSize(13)
              .fontColor('#F44336')
              .margin({ left: 12 })
              .onClick(() => {
                this.editorImageUri = '';
              })
            Text('换一张')
              .fontSize(13)
              .fontColor('#1976D2')
              .margin({ left: 8 })
              .onClick(() => {
                this.selectEditorImage();
              })
          } else {
            Text('🖼️ 添加图片')
              .fontSize(13)
              .fontColor('#1976D2')
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
            .fontColor(this.getThemeStore().isDark ? '#CCCCCC' : '#666666')
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onClick(() => {
              this.editorVisible = false;
            })
          Button('保存')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('#1976D2')
            .borderRadius(6)
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
      .borderRadius(12)
      .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#FFFFFF')
      .padding(20)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(0,0,0,0.5)')
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
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
        Row() {
          Text(this.deleteConfirmNoRemind ? '☑' : '☐')
            .fontSize(18)
            .fontColor(this.deleteConfirmNoRemind ? '#1976D2' : '#999999')
            .onClick(() => {
              this.deleteConfirmNoRemind = !this.deleteConfirmNoRemind;
            })
          Text('本次会话内不再提示')
            .fontSize(13)
            .fontColor(this.getThemeStore().isDark ? '#CCCCCC' : '#666666')
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
            .fontColor(this.getThemeStore().isDark ? '#CCCCCC' : '#666666')
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onClick(() => {
              this.deleteConfirmVisible = false;
            })
          Button('删除')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('#F44336')
            .borderRadius(6)
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
      .borderRadius(12)
      .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#FFFFFF')
      .padding(20)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(0,0,0,0.5)')
  }

  // ★ 0.148: batch-delete confirm dialog — ALWAYS shown, no no-remind
  // checkbox (spec 2.3.3: every batch delete must be confirmed)
  @Builder
  batchConfirmDialog() {
    Column() {
      Column() {
        Text(`确认删除选中的 ${this.selectedIds.length} 项？`)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
        Row() {
          Button('取消')
            .fontSize(14)
            .fontColor(this.getThemeStore().isDark ? '#CCCCCC' : '#666666')
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onClick(() => {
              this.batchConfirmVisible = false;
            })
          Button('删除')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('#F44336')
            .borderRadius(6)
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
      .borderRadius(12)
      .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#FFFFFF')
      .padding(20)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(0,0,0,0.5)')
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
                .backgroundColor(this.getThemeStore().isDark ? '#1E1E1E' : '#F5F5F5')
                .onChange((value: string) => {
                  this.searchKeyword = value;
                })
              if (this.searchKeyword.length > 0) {
                // Clear button — clearing restores the full list (spec 2.1.4)
                Text('×')
                  .fontSize(16)
                  .fontColor('#999999')
                  .margin({ left: 6 })
                  .onClick(() => {
                    this.searchKeyword = '';
                  })
              }
              Button(this.sortDesc ? '最新↓' : '最早↑')
                .fontSize(12)
                .fontColor(this.getThemeStore().isDark ? '#CCCCCC' : '#666666')
                .backgroundColor(Color.Transparent)
                .padding({ left: 6, right: 6 })
                .margin({ left: 6 })
                .onClick(() => {
                  this.sortDesc = !this.sortDesc;
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 4, bottom: 4 })
          } else {
            // ★ 0.148: multi-select toolbar — select-all / counter / cancel
            Row() {
              Button(this.isAllSelected() ? '取消全选' : '全选')
                .fontSize(13)
                .fontColor(this.getThemeStore().isDark ? '#CCCCCC' : '#666666')
                .backgroundColor(Color.Transparent)
                .padding({ left: 6, right: 6 })
                .onClick(() => {
                  this.toggleSelectAll();
                })
              Blank()
                .layoutWeight(1)
              Text(`已选 ${this.selectedIds.length} 项`)
                .fontSize(13)
                .fontColor(this.getThemeStore().isDark ? '#888888' : '#999999')
              Button('取消')
                .fontSize(13)
                .fontColor(this.getThemeStore().isDark ? '#CCCCCC' : '#666666')
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
                .fontColor(this.getThemeStore().isDark ? '#888888' : '#999999')
              Text('点右上角 + 手动添加，或长按对话气泡选中文本入知识库')
                .fontSize(12)
                .fontColor(this.getThemeStore().isDark ? '#666666' : '#BBBBBB')
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
                .fontColor(this.getThemeStore().isDark ? '#888888' : '#999999')
              Text('换个关键词试试')
                .fontSize(12)
                .fontColor(this.getThemeStore().isDark ? '#666666' : '#BBBBBB')
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
                        .fontColor(this.selectedIds.includes(c.id) ? '#1976D2' : '#999999')
                        .margin({ right: 8 })
                    }
                    // Entry content block: title -> definition -> image thumbnail
                    Column() {
                      Text(c.title)
                        .fontSize(16)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
                      Text(c.definition)
                        .fontSize(13)
                        .fontColor(this.getThemeStore().isDark ? '#CCCCCC' : '#666666')
                        .margin({ top: 2 })
                      if (c.imageUri.length > 0) {
                        // Card image thumbnail — not rendered when empty
                        Image(c.imageUri)
                          .height(64)
                          .width(96)
                          .objectFit(ImageFit.Cover)
                          .borderRadius(4)
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
                        .fontColor('#F44336')
                        .backgroundColor(Color.Transparent)
                        .padding({ left: 8, right: 8 })
                        .onClick(() => {
                          this.requestDeleteCard(c);
                        })
                    }
                  }
                  .width('100%')
                  .padding(12)
                  .borderRadius(8)
                  .backgroundColor(this.getThemeStore().isDark ? '#1E1E1E' : '#F5F5F5')
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
        // ★ 0.160: editor image fullscreen preview — topmost layer
        if (this.editorImagePreviewVisible) {
          this.editorImagePreview()
        }
      }
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
      if (this.multiSelectMode) {
        this.exitMultiSelect();
        return true;
      }
      return false;
    })
  }
}
