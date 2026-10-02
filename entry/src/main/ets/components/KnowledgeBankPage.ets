// ============================================================
// KnowledgeBankPage.ets — Knowledge bank page (0.146 Knowledge Bank)
// ============================================================
// Lists all saved knowledge cards with delete-only management:
//   - Rendering order per entry: title -> definition -> image thumbnail
//   - Image thumbnail is rendered only when imageUri is non-empty
//     (base64 data URI, project-wide pattern); no blank placeholder
//   - Delete is the ONLY manual operation — cards are created through
//     the ChatPage selection toolbar "入知识库" flow (AI draft -> user
//     edit -> save); this page never creates cards
//   - Data comes from the isolated PersistenceV2 key 'knowledge-bank'
//
// Tech stack: HarmonyOS ArkUI V2 (@ComponentV2)
// ============================================================

import { AppStorageV2 } from '@kit.ArkUI';
import { KnowledgeCard, KnowledgeBankStore } from '../common/KnowledgeModel';
import { connectKnowledgeBank, removeKnowledgeCard } from '../utils/KnowledgeStoreUtil';
import { ThemeStore } from '../entryability/EntryAbility'; // dark/light theme

@ComponentV2
export struct KnowledgeBankPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  knowledgeBank: KnowledgeBankStore = connectKnowledgeBank(); // isolated PersistenceV2 instance

  // Global theme state (same pattern as ChatPage / WordBankPage)
  getThemeStore(): ThemeStore {
    return AppStorageV2.connect(ThemeStore, 'theme-store', () => new ThemeStore()) as ThemeStore;
  }

  build() {
    NavDestination() {
      Column() {
        if (this.knowledgeBank.cards.length === 0) {
          // Empty state — guide the user to the only entry point
          Column() {
            Text('知识库为空')
              .fontSize(16)
              .fontColor(this.getThemeStore().isDark ? '#888888' : '#999999')
            Text('长按对话气泡选中文本，点「入知识库」编辑后即可保存')
              .fontSize(12)
              .fontColor(this.getThemeStore().isDark ? '#666666' : '#BBBBBB')
              .margin({ top: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.knowledgeBank.cards, (c: KnowledgeCard) => {
              ListItem() {
                Row() {
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

                  // Delete button — the only manual operation in the bank
                  Button('×')
                    .fontSize(16)
                    .fontColor('#F44336')
                    .backgroundColor(Color.Transparent)
                    .padding({ left: 8, right: 8 })
                    .onClick(() => {
                      removeKnowledgeCard(this.knowledgeBank, c.id);
                    })
                }
                .width('100%')
                .padding(12)
                .borderRadius(8)
                .backgroundColor(this.getThemeStore().isDark ? '#1E1E1E' : '#F5F5F5')
                .alignItems(VerticalAlign.Center)
              }
            }, (c: KnowledgeCard) => c.id)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, top: 12 })
        }
      }
      .width('100%')
      .height('100%')
    }
    .title('知识库')
  }
}
