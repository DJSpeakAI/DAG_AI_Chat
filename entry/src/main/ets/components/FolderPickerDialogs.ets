// ============================================================
// FolderPickerDialogs.ets — 加词/知识卡入库目标文件夹选择弹窗（★ 拆分自 ChatPage.ets）
// ============================================================
// ★ 0.222.21/0.222.22 原生弹窗；UI 逐行复刻单词库/知识库移动/复制弹窗
// （树形连接线+折叠三角+行高 32/字号 13/RADIUS_NAV+根目录行显示总数+取消行）。
// 模式：@ComponentV2 子组件 + @Event 回调（0.156 划词五件套同款——按钮动作回宿主页，
// this 归位正确；禁 @BuilderParam 传父工具栏=0.157 崩溃教训）；store 直连单例零传递
// （PersistenceV2 connect 同一实例）；折叠态内聚弹窗生命周期（@Local string[] 替换引用触发重渲染）。
// 宿主页消费：ChatPage（wordFolderPickerVisible/cardFolderPickerVisible 条件挂载）。
import { AppTheme, connectAppTheme } from '../common/AppTheme';
import { RADIUS_NAV } from '../common/DesignTokens';
import { TREE_CELL } from '../common/ChatPageTypes';
import { FoldChevron } from './FoldChevron';
import { WordBankStore, WordFolder, WordFolderTreeItem } from '../common/WordModel';
import { KnowledgeBankStore, KFolder, KFolderTreeItem } from '../common/KnowledgeModel';
import { connectWordBank } from '../utils/WordStoreUtil';
import { connectKnowledgeBank } from '../utils/KnowledgeStoreUtil';

// ★ 0.235.0：划词引用二选一弹窗——「引用到本聊天 / 引用为新子气泡」；样式对齐文件夹选择弹窗
//   （暗紫卡片 surfaceNode+RADIUS_NAV+遮罩关闭=取消；宽度走确认类 400 断点制）。
@ComponentV2
export struct QuotePicker {
  theme: AppTheme = connectAppTheme();
  @Param isTablet: boolean = false;
  @Param shortLabel: string = ''; // 划选内容短预览（宿主页截取）
  @Event onQuote: (toNewBubble: boolean) => void = (toNewBubble: boolean) => {};
  @Event onCancel: () => void = () => {};

  build() {
    Column() {
      Column() {
        Text('引用选中内容')
          .fontSize(16)
          .fontWeight(600)
          .fontColor(this.theme.textPrimary)
        Text(this.shortLabel)
          .fontSize(12)
          .fontColor(this.theme.textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 6, bottom: 14 })
        Text('引用到本聊天')
          .fontSize(14)
          .fontColor(this.theme.brandSecondary)
          .width('100%')
          .height(44)
          .textAlign(TextAlign.Center)
          .borderRadius(RADIUS_NAV)
          .backgroundColor(this.theme.surfaceHover)
          .onClick(() => {
            this.onQuote(false);
          })
        Text('引用为新子气泡')
          .fontSize(14)
          .fontColor(this.theme.brandSecondary)
          .width('100%')
          .height(44)
          .textAlign(TextAlign.Center)
          .borderRadius(RADIUS_NAV)
          .backgroundColor(this.theme.surfaceHover)
          .margin({ top: 8 })
          .onClick(() => {
            this.onQuote(true);
          })
        Text('取消')
          .fontSize(13)
          .fontColor(this.theme.textTertiary)
          .margin({ top: 12 })
          .onClick(() => {
            this.onCancel();
          })
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
      this.onCancel();
    })
  }
}

// ★ 0.222.21：加词目标文件夹选择弹窗，标题「加入单词到…」；点行=确认入该文件夹、点取消/遮罩=关闭。
@ComponentV2
export struct WordFolderPicker {
  theme: AppTheme = connectAppTheme();
  @Param isTablet: boolean = false;
  wordBank: WordBankStore = connectWordBank(); // 直连 PersistenceV2 单例（与 ChatPage 同实例）
  @Event onPick: (folderId: string) => void = (folderId: string) => {};
  @Event onClose: () => void = () => {};
  @Local collapsedFolderIds: string[] = [];

  // 树形目录（DFS 层级+连接线字段，复刻单词库移动/复制弹窗；加词场景无排除项）
  treeItems(): WordFolderTreeItem[] {
    const out: WordFolderTreeItem[] = [];
    const walk = (parentId: string, depth: number, ancestorIds: string[], ancestorHasNext: boolean[]): void => {
      const kids = this.wordBank.folders
        .filter((f: WordFolder): boolean => f.parentId === parentId)
        .sort((a: WordFolder, b: WordFolder): number => b.createdAt - a.createdAt);
      for (let i = 0; i < kids.length; i++) {
        const isLast = i === kids.length - 1;
        out.push({ folder: kids[i], depth: depth, isLast: isLast, ancestorIds: ancestorIds, ancestorHasNext: ancestorHasNext });
        if (!this.isCollapsed(kids[i].id)) {
          walk(kids[i].id, depth + 1, [...ancestorIds, kids[i].id], [...ancestorHasNext, !isLast]);
        }
      }
    };
    walk('', 0, [], []);
    return out;
  }

  hasChildren(folderId: string): boolean {
    for (let i = 0; i < this.wordBank.folders.length; i++) {
      if (this.wordBank.folders[i].parentId === folderId) {
        return true;
      }
    }
    return false;
  }

  isCollapsed(folderId: string): boolean {
    return this.collapsedFolderIds.indexOf(folderId) >= 0;
  }

  toggleCollapse(folderId: string): void {
    if (this.isCollapsed(folderId)) {
      this.collapsedFolderIds = this.collapsedFolderIds.filter((id: string): boolean => id !== folderId);
    } else {
      this.collapsedFolderIds = [...this.collapsedFolderIds, folderId];
    }
  }

  build() {
    Column() {
      Column() {
        Text('加入单词到…')
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
              Text(`${this.wordBank.words.length}`)
                .fontSize(10)
                .fontColor(this.theme.textTertiary)
            }
            .width('100%')
            .height(32)
            .padding({ left: 8, right: 8 })
            .borderRadius(RADIUS_NAV)
            .onClick(() => {
              this.onPick('');
            })
            ForEach(this.treeItems(), (item: WordFolderTreeItem) => {
              Row({ space: 6 }) {
                // 静态经典树形连接线（与边栏同款，弹窗无路径高亮）
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
                if (this.hasChildren(item.folder.id)) {
                  FoldChevron({ expanded: !this.isCollapsed(item.folder.id) })
                    .onClick(() => {
                      this.toggleCollapse(item.folder.id);
                    })
                } else {
                  Row().width(12) // 叶子行空占位（同宽对齐——树行文本同轴线）
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
                this.onPick(item.folder.id);
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
          .fontColor(this.theme.textTertiary)
          .margin({ top: 10 })
          .onClick(() => {
            this.onClose();
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
      this.onClose();
    })
  }
}

// ★ 0.222.22：知识卡入库目标文件夹选择弹窗，标题「保存卡片到…」；点行=确认入该文件夹、
// 点取消/遮罩=回到编辑弹窗（草稿不丢——关闭回调由宿主页处理，编辑弹窗状态不动）。
@ComponentV2
export struct CardFolderPicker {
  theme: AppTheme = connectAppTheme();
  @Param isTablet: boolean = false;
  knowledgeBank: KnowledgeBankStore = connectKnowledgeBank(); // 直连 PersistenceV2 单例
  @Event onPick: (folderId: string) => void = (folderId: string) => {};
  @Event onClose: () => void = () => {};
  @Local collapsedFolderIds: string[] = [];

  // 树形目录（DFS 层级+连接线字段，复刻知识库移动/复制弹窗；入库场景无排除项）
  treeItems(): KFolderTreeItem[] {
    const out: KFolderTreeItem[] = [];
    const walk = (parentId: string, depth: number, ancestorIds: string[], ancestorHasNext: boolean[]): void => {
      const kids = this.knowledgeBank.folders
        .filter((f: KFolder): boolean => f.parentId === parentId)
        .sort((a: KFolder, b: KFolder): number => b.createdAt - a.createdAt);
      for (let i = 0; i < kids.length; i++) {
        const isLast = i === kids.length - 1;
        out.push({ folder: kids[i], depth: depth, isLast: isLast, ancestorIds: ancestorIds, ancestorHasNext: ancestorHasNext });
        if (!this.isCollapsed(kids[i].id)) {
          walk(kids[i].id, depth + 1, [...ancestorIds, kids[i].id], [...ancestorHasNext, !isLast]);
        }
      }
    };
    walk('', 0, [], []);
    return out;
  }

  hasChildren(folderId: string): boolean {
    for (let i = 0; i < this.knowledgeBank.folders.length; i++) {
      if (this.knowledgeBank.folders[i].parentId === folderId) {
        return true;
      }
    }
    return false;
  }

  isCollapsed(folderId: string): boolean {
    return this.collapsedFolderIds.indexOf(folderId) >= 0;
  }

  toggleCollapse(folderId: string): void {
    if (this.isCollapsed(folderId)) {
      this.collapsedFolderIds = this.collapsedFolderIds.filter((id: string): boolean => id !== folderId);
    } else {
      this.collapsedFolderIds = [...this.collapsedFolderIds, folderId];
    }
  }

  build() {
    Column() {
      Column() {
        Text('保存卡片到…')
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
              this.onPick('');
            })
            ForEach(this.treeItems(), (item: KFolderTreeItem) => {
              Row({ space: 6 }) {
                // 静态经典树形连接线（与边栏同款，弹窗无路径高亮）
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
                if (this.hasChildren(item.folder.id)) {
                  FoldChevron({ expanded: !this.isCollapsed(item.folder.id) })
                    .onClick(() => {
                      this.toggleCollapse(item.folder.id);
                    })
                } else {
                  Row().width(12) // 叶子行空占位（同宽对齐——树行文本同轴线）
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
                this.onPick(item.folder.id);
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
            this.onClose();
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
      this.onClose();
    })
  }
}
