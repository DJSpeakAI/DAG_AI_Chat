// ============================================================
// ChatPage.ets — 对话页面（气泡内聊天界面）
// ============================================================
// 本文件是用户与 AI 对话的主界面，功能包括：
//   - 消息列表渲染（用户消息纯文本，AI 消息 Markdown 代码块/表格）
//   - 流式接收 AI 回复（打字机效果，边接收边渲染）
//   - 图片发送（多选相册 → Base64 → 发送给 AI）
//   - 图片全屏预览（点击放大、右滑/点击关闭、双指缩放）
//   - 输入框多行自适应（≤5 行自适应高度，>5 行内部滚动）
//   - DAG 链路回溯 + 上下文压缩（超 25 条消息自动摘要）
//   - 长按消息菜单（复制、删除）
//   - 深浅色主题适配
//
// 技术栈：鸿蒙 ArkUI V2（@ComponentV2 / @Local / @Param / @Computed）
// 导航模式：NavPathStack（从 BBTreeCanvas 气泡画布页面跳入）
// ============================================================

import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
// ★ 删除未使用 import common（0.122 清理）
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { BubbleNode, ChatMessage, BubbleTree, CurrentBubble, ApiConfig, PersistData, generateMessageId, generateNodeId, serializeBubbleTree } from '../common/ChatModel';
import { streamChat, StreamController } from '../utils/ApiClient';
import { ThemeStore } from '../entryability/EntryAbility';

// ★ 新增：Markdown 解析段（0.121）
class MdSegment {
  type: number; // 0=普通文本, 1=代码块, 2=表格
  content: string;
  lang: string;
  header: string[];
  rows: string[][];
  constructor(type: number, content: string, lang: string = '', header: string[] = [], rows: string[][] = []) {
    this.type = type;
    this.content = content;
    this.lang = lang;
    this.header = header;
    this.rows = rows;
  }
}

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
  // 全屏图片浏览器状态
  @Local imageViewerVisible: boolean = false;
  @Local imageViewerIndex: number = 0;
  @Local imageViewerImages: string[] = [];
  // 长按菜单状态
  @Local menuMessageId: string = '';
  @Local menuVisible: boolean = false;
  @Local deleteConfirmVisible: boolean = false;
  @Local textPreviewVisible: boolean = false;
  @Local textPreviewContent: string = '';
  private scroller: Scroller = new Scroller();
  private inputController: TextAreaController = new TextAreaController();
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

  // ★ 新增：输入框动态高度，≤5行自适应，>5行固定触发内部滚动（0.118）
  // ★ 修复：单行基准40vp，避免首行文字被遮挡（0.119）
  @Computed
  get inputAreaHeight(): number {
    if (this.inputText.length === 0) return 40; // 空文本单行高度
    const lines = this.inputText.split('\n').length;
    return 40 + (Math.min(lines, 5) - 1) * 24; // 首行40vp，后续每行+24vp，上限5行=136vp
  }

  // ★ 新增：Markdown 解析，拆分为普通文本/代码块/表格段（0.121）
  parseMarkdown(content: string): MdSegment[] {
    const segments: MdSegment[] = [];
    const lines: string[] = content.split('\n');
    let i = 0;
    let textBuffer: string[] = [];

    const flushText = () => {
      if (textBuffer.length > 0) {
        segments.push(new MdSegment(0, textBuffer.join('\n')));
        textBuffer = [];
      }
    };

    while (i < lines.length) {
      const line = lines[i];
      const trimmed = line.trim();

      // 代码块：```lang ... ```
      if (trimmed.startsWith('```')) {
        flushText();
        const lang = trimmed.substring(3).trim();
        i++;
        const codeLines: string[] = [];
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          codeLines.push(lines[i]);
          i++;
        }
        segments.push(new MdSegment(1, codeLines.join('\n'), lang));
        i++; // 跳过闭合 ```
        continue;
      }

      // 表格：| header | ... | 后跟 |---|---|
      if (trimmed.startsWith('|') && trimmed.endsWith('|') &&
        i + 1 < lines.length && lines[i + 1].includes('---')) {
        flushText();
        const header = this.parseTableRow(line);
        i += 2; // 跳过表头和分隔行
        const rows: string[][] = [];
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          rows.push(this.parseTableRow(lines[i]));
          i++;
        }
        segments.push(new MdSegment(2, '', '', header, rows));
        continue;
      }

      // 普通文本
      textBuffer.push(line);
      i++;
    }
    flushText();
    return segments;
  }

  // ★ 新增：解析表格行 | a | b | → [a, b]（0.121）
  parseTableRow(line: string): string[] {
    const parts = line.split('|');
    const result: string[] = [];
    for (let j = 1; j < parts.length - 1; j++) {
      result.push(parts[j].trim());
    }
    return result;
  }

  // ★ 新增：调用 LLM 生成摘要（0.117）
  async generateSummaryWithLLM(messages: ChatMessage[]): Promise<string> {
    return new Promise((resolve, reject) => {
      const summaryMessages: ChatMessage[] = [
        new ChatMessage(generateMessageId(), 'system',
          '请将以下对话内容精简摘要，保留：核心定义、前提条件、已推导结论、关键约定。用简洁的中文输出。'),
        ...messages
      ];
      let summary = '';
      streamChat(
        summaryMessages,
        this.apiConfig,
        (chunk: string) => { summary += chunk; },
        () => { resolve(summary); },
        (error: string) => { reject(error); }
      );
    });
  }

  // ★ 新增：链路回溯 + 摘要滑动窗口压缩（0.117）
  async buildBranchMessageList(currentNode: BubbleNode): Promise<ChatMessage[]> {
    const THRESHOLD = 25;
    const SUMMARY_COUNT = 10;
    const RECENT_COUNT = 15;

    // 1. 沿 parentID 回溯到根节点，收集链路上所有节点
    const chainNodes: BubbleNode[] = [];
    let node: BubbleNode | undefined = currentNode;
    while (node) {
      chainNodes.unshift(node);
      if (node.parentID === null) break;
      node = this.store.nodeList.find(n => n.nodeID === node!.parentID);
    }

    // 2. 按时序组装消息数组（根 → 当前），过滤空内容和占位文字
    const allMessages: ChatMessage[] = [];
    for (const n of chainNodes) {
      for (const msg of n.messages) {
        if (msg.content.length > 0 && msg.content !== 'AI正在回复中，请稍候...') {
          allMessages.push(msg);
        }
      }
    }

    const totalCount = allMessages.length;
    console.info(`[0.117] 链路消息总数: ${totalCount}`);

    // 3. 未超阈值，直接返回
    if (totalCount <= THRESHOLD) {
      console.info(`[0.117] 未触发压缩，直接返回 ${totalCount} 条消息`);
      return allMessages;
    }

    // 4. 超阈值，执行压缩
    console.info(`[0.117] 触发压缩: ${totalCount} > ${THRESHOLD}`);

    // 判断是否需要重新生成摘要
    const needRegenerate = currentNode.historySummary.length === 0 ||
      (totalCount - currentNode.historySummaryCount >= SUMMARY_COUNT);

    if (needRegenerate) {
      const toSummarize = allMessages.slice(0, SUMMARY_COUNT);
      console.info(`[0.117] 生成新摘要，摘要消息数: ${toSummarize.length}`);
      try {
        const summary = await this.generateSummaryWithLLM(toSummarize);
        currentNode.historySummary = summary;
        currentNode.historySummaryCount = totalCount;
        this.persistData.bubbleTreeJson = serializeBubbleTree(this.store);
      } catch (e) {
        console.error(`[0.117] 摘要生成失败: ${e}`);
      }
    } else {
      console.info(`[0.117] 使用已有摘要，无需重新生成`);
    }

    // 5. 组装最终消息：[1 条摘要虚拟消息 + 最近 15 条原始消息]
    const summaryMsg = new ChatMessage(generateMessageId(), 'system',
      `【历史摘要】${currentNode.historySummary}`);
    const recentMessages = allMessages.slice(allMessages.length - RECENT_COUNT);
    const result: ChatMessage[] = [summaryMsg, ...recentMessages];

    console.info(`[0.117] 最终发给 AI 的消息数: ${result.length} (1 摘要 + ${recentMessages.length} 原始)`);
    return result;
  }

  async sendMessage(): Promise<void> { // ★ 改为 async（0.117）
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
    // ★ 替换为链路回溯 + 压缩（0.117）
    const messagesToSend = await this.buildBranchMessageList(this.currentBubble);

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
    this.persistData.bubbleTreeJson = serializeBubbleTree(this.store);
  }

  // 全屏图片浏览器：收集当前对话所有图片，定位点击的图片，打开 viewer
  openImageViewer(clickedUrl: string): void {
    if (!this.currentBubble) {
      return;
    }
    const allImages: string[] = [];
    const messages = this.currentBubble.messages;
    for (let i = 0; i < messages.length; i++) {
      const urls = messages[i].imageUrl;
      for (let j = 0; j < urls.length; j++) {
        if (urls[j].length > 0) {
          allImages.push(urls[j]);
        }
      }
    }
    if (allImages.length === 0) {
      return;
    }
    const idx = allImages.indexOf(clickedUrl);
    this.imageViewerImages = allImages;
    this.imageViewerIndex = idx >= 0 ? idx : 0;
    this.imageViewerVisible = true;
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
      Stack() {
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
                    // 图片缩略图（在文字上方）
                    if (msg.imageUrl.length > 0) {
                      Row() {
                        ForEach(msg.imageUrl, (url: string) => {
                          Image(url)
                            .width(80)
                            .height(80)
                            .borderRadius(8)
                            .margin({ right: 4 })
                            .onClick(() => {
                              this.openImageViewer(url);
                            })
                        }, (url: string) => url)
                      }
                      .margin({ bottom: 4 })
                    }
                    // 文字内容（非空才显示）
                    if (msg.content.length > 0) {
                      if (msg.role === 'user') {
                        // 用户消息：纯文本渲染（保持原有逻辑）
                        Text(msg.content)
                          .fontSize(16)
                          .lineHeight(24)
                          .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#1976D2')
                          .padding(10)
                          .borderRadius(8)
                          .backgroundColor(this.getThemeStore().isDark ? '#0D47A1' : '#E3F2FD')
                          .copyOption(CopyOptions.LocalDevice)
                      } else {
                        // ★ AI 消息：Markdown 分段渲染（0.121）
                        Column() {
                          ForEach(this.parseMarkdown(msg.content), (seg: MdSegment, idx: number) => {
                            if (seg.type === 0) {
                              // 普通文本段
                              Text(seg.content)
                                .fontSize(16)
                                .lineHeight(24)
                                .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#616161')
                                .copyOption(CopyOptions.LocalDevice)
                            }
                            if (seg.type === 1) {
                              // 代码块：等宽字体 + 深色底 + 横向滚动
                              Scroll() {
                                Text(seg.content)
                                  .fontSize(14)
                                  .fontFamily('monospace')
                                  .fontColor(this.getThemeStore().isDark ? '#D4D4D4' : '#333333')
                                  .padding(10)
                                  .backgroundColor(this.getThemeStore().isDark ? '#2D2D2D' : '#F0F0F0')
                                  .borderRadius(6)
                              }
                              .scrollable(ScrollDirection.Horizontal)
                              .scrollBar(BarState.Auto)
                              .width('100%')
                              .margin({ top: 6, bottom: 6 })
                            }
                            if (seg.type === 2) {
                              // 表格：带边框 + 表头区分 + 横向滚动
                              Scroll() {
                                Column() {
                                  // 表头行
                                  Row() {
                                    ForEach(seg.header, (cell: string, ci: number) => {
                                      Text(cell)
                                        .fontSize(14)
                                        .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
                                        .padding(8)
                                        .border({ width: 0.5, color: this.getThemeStore().isDark ? '#555555' : '#CCCCCC' })
                                        .layoutWeight(1)
                                        .textAlign(TextAlign.Center)
                                    }, (cell: string, ci: number) => `h_${ci}`)
                                  }
                                  // 数据行
                                  ForEach(seg.rows, (row: string[], ri: number) => {
                                    Row() {
                                      ForEach(row, (cell: string, ci: number) => {
                                        Text(cell)
                                          .fontSize(14)
                                          .fontColor(this.getThemeStore().isDark ? '#E0E0E0' : '#666666')
                                          .padding(8)
                                          .border({ width: 0.5, color: this.getThemeStore().isDark ? '#555555' : '#CCCCCC' })
                                          .layoutWeight(1)
                                          .textAlign(TextAlign.Center)
                                      }, (cell: string, ci: number) => `r_${ri}_${ci}`)
                                    }
                                  }, (row: string[], ri: number) => `row_${ri}`)
                                }
                              }
                              .scrollable(ScrollDirection.Horizontal)
                              .scrollBar(BarState.Auto)
                              .width('100%')
                              .margin({ top: 6, bottom: 6 })
                            }
                          }, (seg: MdSegment, idx: number) => `${idx}_${seg.type}`)
                        }
                        .padding(10)
                        .borderRadius(8)
                        .backgroundColor(this.getThemeStore().isDark ? '#1E1E1E' : '#F5F5F5')
                      }
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
                .gesture(
                  LongPressGesture().onAction(() => {
                    this.menuMessageId = msg.messageId;
                    this.menuVisible = true;
                  })
                )
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

          TextArea({ text: $$this.inputText, placeholder: '输入问题...', controller: this.inputController })
            .layoutWeight(1)
            .height(this.inputAreaHeight) // ★ 新增：动态高度，≤5行自适应，>5行固定触发内部滚动（0.118）
            .enterKeyType(EnterKeyType.NEW_LINE)

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

        // 全屏图片浏览器
        if (this.imageViewerVisible) {
          Stack() {
            Swiper() {
              ForEach(this.imageViewerImages, (url: string) => {
                Image(url)
                  .objectFit(ImageFit.Contain)
                  .width('100%')
                  .height('100%')
              }, (url: string) => url)
            }
            .index(this.imageViewerIndex)
            .indicator(true)
            .backgroundColor(Color.Black)

            Button('×')
              .fontSize(24)
              .fontColor('#FFFFFF')
              .backgroundColor(Color.Transparent)
              .position({ x: 20, y: 20 })
              .onClick(() => {
                this.imageViewerVisible = false;
              })
          }
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Black)
          .onClick(() => {
            this.imageViewerVisible = false;
          })
          // ★ 新增：右滑手势关闭图片预览（0.120）
          .gesture(
            PanGesture({ direction: PanDirection.Horizontal })
              .onActionEnd((event: PanGestureEvent) => {
                if (event.offsetX > 30) { // 右滑超过30vp关闭预览
                  this.imageViewerVisible = false;
                }
              })
          )
        }

        // 长按菜单弹窗
        if (this.menuVisible) {
          Stack() {
            Column() {
              Blank()
            }
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.4)')
            .onClick(() => {
              this.menuVisible = false;
            })

            Column() {
              Button('选择文本')
                .width('100%')
                .height(44)
                .fontSize(16)
                .backgroundColor(Color.Transparent)
                .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
                .onClick(() => {
                  const msg = this.currentBubble?.messages.find(m => m.messageId === this.menuMessageId);
                  this.textPreviewContent = msg?.content ?? '';
                  this.textPreviewVisible = true;
                  this.menuVisible = false;
                })

              Button('删除')
                .width('100%')
                .height(44)
                .fontSize(16)
                .backgroundColor(Color.Transparent)
                .fontColor('#F44336')
                .onClick(() => {
                  this.menuVisible = false;
                  this.deleteConfirmVisible = true;
                })
            }
            .width('50%')
            .borderRadius(12)
            .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#FFFFFF')
            .padding(4)
          }
          .width('100%')
          .height('100%')
          .alignContent(Alignment.Center)
        }

        // 删除确认弹窗
        if (this.deleteConfirmVisible) {
          Stack() {
            Column() {
              Blank()
            }
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.4)')
            .onClick(() => {
              this.deleteConfirmVisible = false;
            })

            Column() {
              Text('确认删除这条消息？')
                .fontSize(16)
                .margin({ bottom: 16 })

              Row() {
                Button('取消')
                  .layoutWeight(1)
                  .margin({ right: 8 })
                  .onClick(() => {
                    this.deleteConfirmVisible = false;
                  })

                Button('确认')
                  .layoutWeight(1)
                  .backgroundColor('#F44336')
                  .fontColor('#FFFFFF')
                  .onClick(() => {
                    this.deleteMessage(this.menuMessageId);
                    this.deleteConfirmVisible = false;
                  })
              }
              .width('100%')
            }
            .width('70%')
            .padding(20)
            .borderRadius(12)
            .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#FFFFFF')
          }
          .width('100%')
          .height('100%')
          .alignContent(Alignment.Center)
        }

        // 文本预览弹窗（选择文本）
        if (this.textPreviewVisible) {
          Stack() {
            Column() {
              Blank()
            }
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.4)')
            .onClick(() => {
              this.textPreviewVisible = false;
            })

            Column() {
              Text('选择文本')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 12 })

              Scroll() {
                Text(this.textPreviewContent)
                  .fontSize(14)
                  .copyOption(CopyOptions.LocalDevice)
                  .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
                  .padding(8)
              }
              .width('100%')
              .height(200)
              .borderRadius(8)
              .backgroundColor(this.getThemeStore().isDark ? '#1E1E1E' : '#F5F5F5')

              Button('关闭')
                .width('100%')
                .margin({ top: 12 })
                .onClick(() => {
                  this.textPreviewVisible = false;
                })
            }
            .width('80%')
            .padding(20)
            .borderRadius(12)
            .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#FFFFFF')
          }
          .width('100%')
          .height('100%')
          .alignContent(Alignment.Center)
        }
      }
      .width('100%')
      .height('100%')
    }
    .title('对话')
    // ★ 新增：图片/文本预览打开时拦截系统返回手势，不跳转Canvas（0.120）
    .onBackPressed(() => {
      if (this.imageViewerVisible) {
        this.imageViewerVisible = false;
        return true; // 消费返回事件，阻止页面导航
      }
      if (this.textPreviewVisible) {
        this.textPreviewVisible = false;
        return true;
      }
      return false; // 预览未打开，恢复原生返回逻辑
    })
  }
}
