import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { BubbleNode, ChatMessage, BubbleTree, CurrentBubble, ApiConfig, generateMessageId, generateNodeId } from '../common/ChatModel';
import { saveBubbleTree } from '../utils/TreeFileUtil';
import { streamChat, StreamController, testApiConnection, testApiWithDiagnostics } from '../utils/ApiClient';

// 对话页面 — V2 全量迁移
@ComponentV2
export struct ChatPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  store: BubbleTree = AppStorageV2.connect(BubbleTree, 'bubble-tree', () => new BubbleTree()) as BubbleTree;
  currentBubbleStore: CurrentBubble = AppStorageV2.connect(CurrentBubble, 'current-bubble', () => new CurrentBubble()) as CurrentBubble;
  apiConfig: ApiConfig = PersistenceV2.connect(ApiConfig, 'api-config', () => new ApiConfig()) as ApiConfig;
  @Local inputText: string = '';
  @Local isLoading: boolean = false; // 请求期间置灰发送按钮
  @Local pendingImages: string[] = []; // 待发送图片 Base64 数组
  private scroller: Scroller = new Scroller();
  private inputController: TextInputController = new TextInputController();
  private streamController: StreamController | null = null;

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
    // 空输入 / 无气泡 / 加载中 直接返回
    if ((!this.inputText.trim() && this.pendingImages.length === 0) || !this.currentBubble || this.isLoading) {
      return;
    }
    // 取消上一轮请求（如有）
    if (this.streamController) {
      this.streamController.cancel();
    }
    // 新建用户消息（含图片）+ 占位 AI 消息
    const userMsg = new ChatMessage(generateMessageId(), 'user', this.inputText, [...this.pendingImages]);
    const aiMsg = new ChatMessage(generateMessageId(), 'assistant', 'AI正在回复中，请稍候...');
    // 追加到当前气泡，@Trace 触发刷新
    this.currentBubble.messages = [...this.currentBubble.messages, userMsg, aiMsg];
    // 清空输入 + 图片 + 收起键盘
    this.inputText = '';
    this.pendingImages = [];
    this.inputController.stopEditing();
    // 发起流式请求
    this.isLoading = true;

    // 构建发送给 API 的消息列表：剔除空 content 的占位 AI 消息
    const messagesToSend: ChatMessage[] = [];
    for (let i = 0; i < this.currentBubble.messages.length; i++) {
      if (this.currentBubble.messages[i].content.length > 0) {
        messagesToSend.push(this.currentBubble.messages[i]);
      }
    }
    console.info(`[ChatPage] 发送请求，消息数: ${messagesToSend.length}`);
    console.info(`[ChatPage] Endpoint: ${this.apiConfig.endpoint}`);
    console.info(`[ChatPage] Model: ${this.apiConfig.model}`);
    // 打印每条消息的 role + content，方便调试
    let logMsgs: string = '';
    for (let i = 0; i < messagesToSend.length; i++) {
      logMsgs += `[${messagesToSend[i].role}] ${messagesToSend[i].content}; `;
    }
    console.info(`[ChatPage] messagesToSend: ${logMsgs}`);

    this.streamController = streamChat(
      messagesToSend,
      this.apiConfig,
      (chunk: string) => {
        // onChunk：首次收到数据时清除占位文字，然后追加 AI content
        if (aiMsg.content === 'AI正在回复中，请稍候...') {
          aiMsg.content = '';
        }
        aiMsg.content += chunk;
        console.info(`[ChatPage] AI chunk: ${chunk}`);
      },
      () => {
        // onDone：解锁 + 保存 + 滚动
        this.isLoading = false;
        this.streamController = null;
        // 日志：打印完整 AI 回复；空则警告
        if (aiMsg.content.length === 0) {
          console.warn('[ChatPage] AI 回复内容为空');
        } else {
          console.info(`[ChatPage] AI 回复完成: ${aiMsg.content}`);
        }
        // IIFE 异步包裹 saveBubbleTree
        (async () => {
          await saveBubbleTree(
            this.store,
            this.getUIContext().getHostContext() as common.UIAbilityContext
          );
        })();
        this.scroller.scrollEdge(Edge.Bottom);
      },
      (errMsg: string) => {
        // onError：解锁 + 日志 + 错误气泡
        this.isLoading = false;
        this.streamController = null;
        console.error(`[ChatPage] SSE error: ${errMsg}`);
        aiMsg.content = `请求出错，请检查网络/API配置\n${errMsg}`;
      }
    );
    this.scroller.scrollEdge(Edge.Bottom);
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
      console.info(`[ChatPage] 已选择 ${result.photoUris.length} 张图片`);
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
      this.currentBubbleStore.bubbleX, // parentX — 冗余存储父节点坐标
      this.currentBubbleStore.bubbleY  // parentY
    );
    this.store.nodeList = [...this.store.nodeList, newBubble];
    saveBubbleTree(this.store, this.getUIContext().getHostContext() as common.UIAbilityContext);
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
          // 测试 API 连通性：诊断结果直接显示在消息气泡中
          Button('测试')
            .fontSize(13)
            .backgroundColor(Color.Transparent)
            .fontColor('#1976D2')
            .margin({ right: 8 })
            .onClick(() => {
              if (!this.currentBubble) {
                return;
              }
              console.info('[ChatPage] 点击诊断测试');
              // 创建用户消息 + AI 占位消息
              const userMsg = new ChatMessage(generateMessageId(), 'user', '[诊断测试]');
              const aiMsg = new ChatMessage(generateMessageId(), 'assistant', '正在诊断，请稍候...');
              this.currentBubble.messages = [...this.currentBubble.messages, userMsg, aiMsg];
              // 调用诊断函数，结果写入 AI 气泡
              testApiWithDiagnostics(this.apiConfig, (result: string) => {
                aiMsg.content = result;
              });
            })
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
                  Column() {
                    // 文字内容（非空才显示）
                    if (msg.content.length > 0) {
                      Text(msg.content)
                        .fontSize(14)
                        .fontColor(msg.role === 'user' ? '#1976D2' : '#616161')
                        .padding(10)
                        .borderRadius(8)
                        .backgroundColor(msg.role === 'user' ? '#E3F2FD' : '#F5F5F5')
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
