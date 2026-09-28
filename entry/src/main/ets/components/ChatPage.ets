import { AppStorageV2 } from '@kit.ArkUI';
import { BubbleNode, ChatMessage, BubbleTree, CurrentBubble, generateMessageId, generateNodeId } from '../common/ChatModel';
import { saveBubbleTree } from '../utils/TreeFileUtil';

// 对话页面 — V2 全量迁移
@ComponentV2
export struct ChatPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  store: BubbleTree = AppStorageV2.connect(BubbleTree, 'bubble-tree', () => new BubbleTree()) as BubbleTree;
  currentBubbleStore: CurrentBubble = AppStorageV2.connect(CurrentBubble, 'current-bubble', () => new CurrentBubble()) as CurrentBubble;
  @Local inputText: string = '';
  private scroller: Scroller = new Scroller();

  // V2 @Computed：从 store 读取当前气泡 ID，自动响应式
  @Computed
  get currentBubbleId(): string {
    return this.currentBubbleStore.nodeID;
  }

  // V2 @Computed：自动响应式，不需要手动同步
  @Computed
  get currentBubble(): BubbleNode | undefined {
    return this.store.nodeList.find(b => b.nodeID === this.currentBubbleId);
  }

  @Computed
  get currentMessages(): ChatMessage[] {
    return this.currentBubble?.messages ?? [];
  }

  sendMessage(): void {
    if (!this.inputText.trim() || !this.currentBubble) {
      return;
    }
    const userMsg = new ChatMessage(generateMessageId(), 'user', this.inputText);
    const aiMsg = new ChatMessage(generateMessageId(), 'AI', '1');
    // V2：直接替换 messages 数组，@Trace 触发刷新
    this.currentBubble.messages = [...this.currentBubble.messages, userMsg, aiMsg];
    this.inputText = '';
    this.scroller.scrollToIndex(this.currentMessages.length - 1);
  }

  deleteMessage(messageId: string): void {
    if (!this.currentBubble) {
      return;
    }
    this.currentBubble.messages = this.currentBubble.messages.filter(m => m.messageId !== messageId);
  }

  addBubble(): void {
    if (!this.currentBubble) {
      return;
    }
    const newBubble = new BubbleNode(
      generateNodeId(),
      this.currentBubbleId,
      [],
      this.currentBubbleStore.bubbleX + 80 + Math.floor(Math.random() * 40),
      this.currentBubbleStore.bubbleY + 80 + Math.floor(Math.random() * 40),
      this.currentBubbleStore.bubbleX, // parentX — 冗余存储父节点坐标
      this.currentBubbleStore.bubbleY  // parentY
    );
    this.store.nodeList = [...this.store.nodeList, newBubble];
    saveBubbleTree(this.store);
    this.pathStack.pop();
  }

  build() {
    NavDestination() {
      Column() {
        // 顶栏：添加子气泡按钮在右上角
        Row() {
          Blank()
            .layoutWeight(1)
          Button('＋ 添加子气泡')
            .fontSize(14)
            .backgroundColor('#1976D2')
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.addBubble();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 4 })

        // 消息列表 — 直接用 @Computed currentMessages
        if (this.currentMessages.length === 0) {
          Column() {
            Text('暂无对话')
              .fontSize(16)
              .fontColor('#999999')
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 12, scroller: this.scroller }) {
            ForEach(this.currentMessages, (msg: ChatMessage) => {
              ListItem() {
                Row() {
                  Text(msg.content)
                    .fontSize(14)
                    .fontColor(msg.role === 'user' ? '#1976D2' : '#616161')
                    .padding(10)
                    .borderRadius(8)
                    .backgroundColor(msg.role === 'user' ? '#E3F2FD' : '#F5F5F5')

                  Button('×')
                    .fontSize(16)
                    .fontColor('#F44336')
                    .backgroundColor(Color.Transparent)
                    .onClick(() => {
                      this.deleteMessage(msg.messageId);
                    })
                }
                .width('100%')
                .justifyContent(msg.role === 'user' ? FlexAlign.Start : FlexAlign.End)
              }
            }, (msg: ChatMessage) => msg.messageId)
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 16, right: 16, top: 12 })
        }

        // 输入区域 — $$ + @Local 官方确认支持
        Row() {
          TextInput({ text: $$this.inputText, placeholder: '输入问题...' })
            .layoutWeight(1)

          Button('发送')
            .margin({ left: 8 })
            .onClick(() => {
              this.sendMessage();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
      }
      .width('100%')
      .height('100%')
    }
    .title('对话')
  }
}
