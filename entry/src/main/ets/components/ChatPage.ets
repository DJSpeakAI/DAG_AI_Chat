import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { BubbleNode, ChatMessage, BubbleTree, CurrentBubble, ApiConfig, PersistData, generateMessageId, generateNodeId, serializeBubbleTree } from '../common/ChatModel';
import { streamChat, StreamController } from '../utils/ApiClient';
import { ThemeStore } from '../entryability/EntryAbility';

// 对话页面 — V2 全量迁移
@ComponentV2
export struct ChatPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  store: BubbleTree = AppStorageV2.connect(BubbleTree, 'bubble-tree', () => new BubbleTree()) as BubbleTree;
  persistData: PersistData = PersistenceV2.connect(PersistData, 'persist-data', () => new PersistData()) as PersistData;
  currentBubbleStore: CurrentBubble = AppStorageV2.connect(CurrentBubble, 'current-bubble', () => new CurrentBubble()) as CurrentBubble;
  apiConfig: ApiConfig = PersistenceV2.connect(ApiConfig, 'api-config', () => new ApiConfig()) as ApiConfig;
  @Local inputText: string = '';
  @Local isLoading: boolean = false;
  @Local pendingImages: string[] = [];
  private scroller: Scroller = new Scroller();
  private inputController: TextInputController = new TextInputController();
  private streamController: StreamController | null = null;

  // ★ 获取 ThemeStore（通过 AppStorageV2 共享，0.103 功能）
  getThemeStore(): ThemeStore {
    return AppStorageV2.connect(ThemeStore, 'theme-store', () => new ThemeStore()) as ThemeStore;
  }

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
    if ((!this.inputText.trim() && this.pendingImages.length === 0) || !this.currentBubble || this.isLoading) {
      return;
    }
    if (this.streamController) {
      this.streamController.cancel();
    }
    const userMsg = new ChatMessage(generateMessageId(), 'user', this.inputText, [...this.pendingImages]);
    const aiMsg = new ChatMessage(generateMessageId(), 'assistant', 'AI正在回复中，请稍候...');
    this.currentBubble.messages = [...this.currentBubble.messages, userMsg, aiMsg];
    this.persistData.bubbleTreeJson = serializeBubbleTree(this.store);
    this.inputText = '';
    this.pendingImages = [];
    this.inputController.stopEditing();
    this.isLoading = true;

    // 构建发送给 API 的消息列表：剔除空 content 的占位 AI 消息
    const messagesToSend: ChatMessage[] = [];
    for (let i = 0; i < this.currentBubble.messages.length; i++) {
      if (this.currentBubble.messages[i].content.length > 0) {
        messagesToSend.push(this.currentBubble.messages[i]);
      }
    }

    this.streamController = streamChat(
      messagesToSend,
      this.apiConfig,
      (chunk: string) => {
        // onChunk：首次收到数据时清除占位文字，然后追加 AI content
        if (aiMsg.content === 'AI正在回复中，请稍候...') {
          aiMsg.content = '';
        }
        aiMsg.content += chunk;
        // ★ 流式接收时自动滚到底部（恢复 0.104-0.107 移除的行为）
        this.scroller.scrollEdge(Edge.Bottom);
      },
      (inputTokens: number, outputTokens: number) => {
        // onDone：解锁 + 存储 token
        this.isLoading = false;
        this.streamController = null;
        aiMsg.inputTokens = inputTokens;
        aiMsg.outputTokens = outputTokens;
        // 流式完成时滚到底部
        this.scroller.scrollEdge(Edge.Bottom);
        this.persistData.bubbleTreeJson = serializeBubbleTree(this.store);
      },
      (errMsg: string) => {
        // onError：解锁 + 日志 + 错误气泡
        this.isLoading = false;
        this.streamController = null;
        aiMsg.content = `请求出错，请检查网络/API配置\n${errMsg}`;
        // 错误时也滚到底部
        this.scroller.scrollEdge(Edge.Bottom);
        this.persistData.bubbleTreeJson = serializeBubbleTree(this.store);
      }
    );
    // 发送消息后自动滚到底部
    this.scroller.scrollEdge(Edge.Bottom);
  }

  // 进入对话页面：延迟滚到底部，显示最新消息
  aboutToAppear() {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 100);
  }

  // 页面退出：终止正在进行的 SSE 请求，防止内存泄漏
  aboutToDisappear() {
    if (this.streamController) {
      this.streamController.cancel();
      this.streamController = null;
    }
  }

  // 选择图片：调用相册多选，转 Base64 存入 pendingImages
  async selectImages(): Promise<void> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select({ maxSelectNumber: 9 });
      for (let i = 0; i < result.photoUris.length; i++) {
        const uri = result.photoUris[i];
        const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
        const stat = fileIo.statSync(file.fd);
        const arrayBuffer = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, arrayBuffer);
        fileIo.closeSync(file);
        const base64 = buffer.from(arrayBuffer).toString('base64');
        this.pendingImages = [...this.pendingImages, `data:image/jpeg;base64,${base64}`];
      }
    } catch (err) {
      console.error(`[ChatPage] selectImages error: ${(err as Error).message}`);
    }
  }

  // 删除待发送图片
  removeImage(index: number): void {
    const newList: string[] = [];
    for (let i = 0; i < this.pendingImages.length; i++) {
      if (i !== index) {
        newList.push(this.pendingImages[i]);
      }
    }
    this.pendingImages = newList;
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
      this.currentBubbleStore.bubbleX,
      this.currentBubbleStore.bubbleY
    );
    this.store.nodeList = [...this.store.nodeList, newBubble];
    this.persistData.bubbleTreeJson = serializeBubbleTree(this.store);
    this.pathStack.pop();
  }

  build() {
    NavDestination() {
      Column() {
        // 顶栏：添加子气泡按钮在右上角
        Row() {
          Blank()
            .layoutWeight(1)
          Button('⚙')
            .fontSize(18)
            .backgroundColor(Color.Transparent)
            .fontColor('#666')
            .margin({ right: 8 })
            .onClick(() => {
              this.pathStack.pushPath({ name: 'SettingsPage' });
            })
          Button('+ 添加子气泡')
            .fontSize(14)
            .backgroundColor('#1976D2')
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.addBubble();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 4 })

        // 消息列表 — 直接由 @Computed currentMessages 驱动
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
                  Column() {
                    // 文字内容（非空才显示）
                    if (msg.content.length > 0) {
                      Text(msg.content)
                        .fontSize(16)
                        .lineHeight(24)
                        // 深浅色模式（0.103 功能）
                        .fontColor(this.getThemeStore().isDark
                          ? (msg.role === 'user' ? '#FFFFFF' : '#FFFFFF')
                          : (msg.role === 'user' ? '#1976D2' : '#616161'))
                        .padding(10)
                        .borderRadius(8)
                        // 深浅色模式背景
                        .backgroundColor(this.getThemeStore().isDark
                          ? (msg.role === 'user' ? '#0D47A1' : '#1E1E1E')
                          : (msg.role === 'user' ? '#E3F2FD' : '#F5F5F5'))
                        .copyOption(CopyOptions.LocalDevice)
                    }
                    // 用户消息图片缩略图
                    if (msg.role === 'user' && msg.imageUrl.length > 0) {
                      Row() {
                        ForEach(msg.imageUrl, (url: string) => {
                          Image(url)
                            .width(80)
                            .height(80)
                            .borderRadius(8)
                            .margin({ right: 4 })
                        }, (url: string) => url)
                      }
                      .margin({ top: 4 })
                    }
                    // AI 消息 token 统计
                    if (msg.role === 'assistant' && msg.outputTokens > 0) {
                      Text(`输入 ${msg.inputTokens} · 输出 ${msg.outputTokens}`)
                        .fontSize(11)
                        .fontColor(this.getThemeStore().isDark ? '#888' : '#999')
                        .margin({ top: 4 })
                    }
                  }
                  .alignItems(HorizontalAlign.Start)

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

        // 图片预览区域
        if (this.pendingImages.length > 0) {
          Row() {
            ForEach(this.pendingImages, (img: string, index: number) => {
              Stack() {
                Image(img)
                  .width(60)
                  .height(60)
                  .borderRadius(8)
                Button('×')
                  .fontSize(12)
                  .fontColor('#FFFFFF')
                  .backgroundColor('#F44336')
                  .width(18)
                  .height(18)
                  .borderRadius(9)
                  .position({ x: 46, y: -2 })
                  .onClick(() => {
                    this.removeImage(index);
                  })
              }
              .width(60)
              .height(60)
              .margin({ right: 8 })
            }, (img: string, index: number) => `${img.substring(0, 30)}_${index}`)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8 })
        }

        // 输入区域 — 图片按钮 + 输入框 + 发送按钮
        Row() {
          Button('📷')
            .fontSize(20)
            .backgroundColor(Color.Transparent)
            .fontColor('#666')
            .margin({ right: 8 })
            .onClick(() => {
              this.selectImages();
            })

          TextInput({ text: $$this.inputText, placeholder: '输入问题...', controller: this.inputController })
            .layoutWeight(1)

          Button('发送')
            .enabled(!this.isLoading)
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
