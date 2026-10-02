// ============================================================
// WordBankPage.ets — Word bank page (0.145 Word Bank MVP)
// ============================================================
// Lists all saved words with delete-only management:
//   - Rendering order per entry: word -> fullName -> usPhonetic -> explain
//   - fullName row is NOT rendered when empty (no blank placeholder)
//   - Delete is the ONLY manual operation — manual add is intentionally
//     absent; the single entry point is the translate popup's
//     "Add to word bank" button in ChatPage.
//   - Data comes from the isolated PersistenceV2 key 'word-bank'
//
// Tech stack: HarmonyOS ArkUI V2 (@ComponentV2)
// ============================================================

import { AppStorageV2 } from '@kit.ArkUI';
import { WordItem, WordBankStore } from '../common/WordModel';
import { connectWordBank, removeWordFromBank } from '../utils/WordStoreUtil';
import { ThemeStore } from '../entryability/EntryAbility'; // dark/light theme

@ComponentV2
export struct WordBankPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  wordBank: WordBankStore = connectWordBank(); // isolated PersistenceV2 instance

  // Global theme state (same pattern as ChatPage / SettingsPage)
  getThemeStore(): ThemeStore {
    return AppStorageV2.connect(ThemeStore, 'theme-store', () => new ThemeStore()) as ThemeStore;
  }

  build() {
    NavDestination() {
      Column() {
        if (this.wordBank.words.length === 0) {
          // Empty state — guide the user to the only entry point
          Column() {
            Text('单词库为空')
              .fontSize(16)
              .fontColor(this.getThemeStore().isDark ? '#888888' : '#999999')
            Text('长按对话气泡选中单词，点「翻译」后即可加入单词库')
              .fontSize(12)
              .fontColor(this.getThemeStore().isDark ? '#666666' : '#BBBBBB')
              .margin({ top: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.wordBank.words, (w: WordItem) => {
              ListItem() {
                Row() {
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
                      Text(w.usPhonetic)
                        .fontSize(13)
                        .fontColor(this.getThemeStore().isDark ? '#9E9E9E' : '#757575')
                        .margin({ top: 2 })
                    }
                    Text(w.explain)
                      .fontSize(13)
                      .fontColor(this.getThemeStore().isDark ? '#CCCCCC' : '#666666')
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  // Delete button — the only manual operation in the bank
                  Button('×')
                    .fontSize(16)
                    .fontColor('#F44336')
                    .backgroundColor(Color.Transparent)
                    .padding({ left: 8, right: 8 })
                    .onClick(() => {
                      removeWordFromBank(this.wordBank, w.word);
                    })
                }
                .width('100%')
                .padding(12)
                .borderRadius(8)
                .backgroundColor(this.getThemeStore().isDark ? '#1E1E1E' : '#F5F5F5')
                .alignItems(VerticalAlign.Center)
              }
            }, (w: WordItem) => w.word)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, top: 12 })
        }
      }
      .width('100%')
      .height('100%')
    }
    .title('单词库')
  }
}
