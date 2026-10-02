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

import { AppStorageV2 } from '@kit.ArkUI';
import { WordItem, WordBankStore } from '../common/WordModel';
import { ApiConfig, connectApiConfig } from '../common/ChatModel'; // ★ 0.149：pronunciation TTS config (same PersistenceV2 instance as ChatPage)
import { connectWordBank, addWordToBank, removeWordFromBank, updateWordInBank, removeWordsByIds, genWordId } from '../utils/WordStoreUtil';
import { wordSpeaker } from '../utils/WordSpeaker'; // ★ 0.149：word pronunciation singleton
import { ThemeStore } from '../entryability/EntryAbility'; // dark/light theme

@ComponentV2
export struct WordBankPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  wordBank: WordBankStore = connectWordBank(); // isolated PersistenceV2 instance
  apiConfig: ApiConfig = connectApiConfig(); // ★ 0.149：TTS config for pronunciation

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

  // Global theme state (same pattern as ChatPage / SettingsPage)
  getThemeStore(): ThemeStore {
    return AppStorageV2.connect(ThemeStore, 'theme-store', () => new ThemeStore()) as ThemeStore;
  }

  // ★ 0.148: back-fill id/createTime on entries saved before 0.148.
  // Array head = newer (head-insert history), so descending timestamps
  // keep the legacy display order stable under the default desc sort.
  aboutToAppear(): void {
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
    list.sort((a: WordItem, b: WordItem) => {
      return this.sortDesc ? b.createTime - a.createTime : a.createTime - b.createTime;
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
      Button('←')
        .fontSize(18)
        .backgroundColor(Color.Transparent)
        .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
        .padding({ left: 4, right: 4 })
        .margin({ right: 4 })
        .onClick(() => {
          this.pathStack.pop();
        })
      Text('单词库')
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
        Text(this.editorIsAdd ? '新增单词' : '编辑单词')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
        TextInput({ text: this.editorWord, placeholder: '单词（必填）' })
          .fontSize(14)
          .width('100%')
          .height(40)
          .margin({ top: 16 })
          .padding({ left: 12, right: 12 })
          .borderRadius(8)
          .backgroundColor(this.getThemeStore().isDark ? '#1E1E1E' : '#F5F5F5')
          .onChange((value: string) => {
            this.editorWord = value;
          })
        TextInput({ text: this.editorFullName, placeholder: '全称（缩略词选填，普通单词留空）' })
          .fontSize(14)
          .width('100%')
          .height(40)
          .margin({ top: 8 })
          .padding({ left: 12, right: 12 })
          .borderRadius(8)
          .backgroundColor(this.getThemeStore().isDark ? '#1E1E1E' : '#F5F5F5')
          .onChange((value: string) => {
            this.editorFullName = value;
          })
        TextInput({ text: this.editorPhonetic, placeholder: '音标（选填，如 /ˈhɑːrməni/）' })
          .fontSize(14)
          .width('100%')
          .height(40)
          .margin({ top: 8 })
          .padding({ left: 12, right: 12 })
          .borderRadius(8)
          .backgroundColor(this.getThemeStore().isDark ? '#1E1E1E' : '#F5F5F5')
          .onChange((value: string) => {
            this.editorPhonetic = value;
          })
        TextInput({ text: this.editorExplain, placeholder: '释义（选填）' })
          .fontSize(14)
          .width('100%')
          .height(40)
          .margin({ top: 8 })
          .padding({ left: 12, right: 12 })
          .borderRadius(8)
          .backgroundColor(this.getThemeStore().isDark ? '#1E1E1E' : '#F5F5F5')
          .onChange((value: string) => {
            this.editorExplain = value;
          })
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
              this.confirmDeleteWord();
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
              TextInput({ text: this.searchKeyword, placeholder: '搜索单词 / 音标 / 释义' })
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

          if (this.wordBank.words.length === 0) {
            // Empty bank — guide the user to both entry points (0.148 adds manual add)
            Column() {
              Text('单词库为空')
                .fontSize(16)
                .fontColor(this.getThemeStore().isDark ? '#888888' : '#999999')
              Text('点右上角 + 手动添加，或长按对话气泡选词翻译后加入')
                .fontSize(12)
                .fontColor(this.getThemeStore().isDark ? '#666666' : '#BBBBBB')
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
              ForEach(this.filteredWords, (w: WordItem) => {
                ListItem() {
                  Row() {
                    if (this.multiSelectMode) {
                      // ★ 0.148: multi-select check indicator — an icon Text,
                      // NOT a Checkbox: the whole row handles tap-toggle and a
                      // real Checkbox would fire a second onChange
                      Text(this.selectedIds.includes(w.id) ? '☑' : '☐')
                        .fontSize(20)
                        .fontColor(this.selectedIds.includes(w.id) ? '#1976D2' : '#999999')
                        .margin({ right: 8 })
                    }
                    // Entry text block: word -> fullName -> usPhonetic -> explain
                    Column() {
                      Text(w.word)
                        .fontSize(16)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
                      if (w.fullName.length > 0) {
                        // Abbreviation full term — row not rendered when empty
                        Text(w.fullName)
                          .fontSize(13)
                          .fontColor(this.getThemeStore().isDark ? '#7AB8FF' : '#1976D2')
                          .margin({ top: 2 })
                      }
                      if (w.usPhonetic.length > 0) {
                        Row() {
                          Text(w.usPhonetic)
                            .fontSize(13)
                            .fontColor(this.getThemeStore().isDark ? '#9E9E9E' : '#757575')
                          // ★ 0.149：音标旁发音按钮——缩略词播全称（字母谁都会读）、普通词播单词本身（美式）；三态 🔈/⏳/🔊
                          // ★ 0.150：Button→Text——Button 默认高度（≈40vp）会撑高音标行（用户指出单词本行距变大），Text 无默认高度、行距还原
                          Text(wordSpeaker.loadingWord === wordSpeaker.textFor(w.word, w.fullName) ? '⏳' : (wordSpeaker.speakingWord === wordSpeaker.textFor(w.word, w.fullName) ? '🔊' : '🔈'))
                            .fontSize(13)
                            .fontColor(wordSpeaker.speakingWord === wordSpeaker.textFor(w.word, w.fullName) || wordSpeaker.loadingWord === wordSpeaker.textFor(w.word, w.fullName) ? '#1976D2' : (this.getThemeStore().isDark ? '#888888' : '#999999'))
                            .margin({ left: 6 })
                            .onClick(() => {
                              const ctx = this.getUIContext().getHostContext();
                              wordSpeaker.speak(wordSpeaker.textFor(w.word, w.fullName), this.apiConfig, ctx ? ctx.cacheDir : '');
                            })
                        }
                        .margin({ top: 2 })
                      }
                      Text(w.explain)
                        .fontSize(13)
                        .fontColor(this.getThemeStore().isDark ? '#CCCCCC' : '#666666')
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
                        .fontColor('#F44336')
                        .backgroundColor(Color.Transparent)
                        .padding({ left: 8, right: 8 })
                        .onClick(() => {
                          this.requestDeleteWord(w);
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
      }
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
      if (this.multiSelectMode) {
        this.exitMultiSelect();
        return true;
      }
      return false;
    })
  }
}
