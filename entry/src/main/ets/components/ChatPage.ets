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
//   - ★ 0.133：下拉发送模式（正常对话/播客模式）+ AI 消息语音朗读（★ 0.139 openspeech 2.0 协议 + 分段流水线，0.143 收尾清理调试链路）
//
// 技术栈：鸿蒙 ArkUI V2（@ComponentV2 / @Local / @Param / @Computed）
// 导航模式：NavPathStack（从 BBTreeCanvas 气泡画布页面跳入）
// ============================================================

import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI'; // ★ 0.131：收键盘改用 UIContext.getFocusController()（focusControl 不从 @kit.ArkUI 导出）
// ★ 删除未使用 import common（0.122 清理）
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { media } from '@kit.MediaKit'; // ★ 0.133：AVPlayer（语音朗读播放）
import { BusinessError } from '@kit.BasicServicesKit'; // ★ 0.133：AVPlayer error 回调类型
import { BubbleNode, ChatMessage, BubbleTree, CurrentBubble, ApiConfig, PersistData, generateMessageId, generateNodeId, serializeBubbleTree, connectApiConfig } from '../common/ChatModel'; // ★ 0.143：connectApiConfig
import { streamChat, synthesizeTTS, StreamController } from '../utils/ApiClient';
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

// ★ 0.132：AI 消息占位文字常量（两态：加载中 / 深度思考中）
// 注意：PLACEHOLDER_LOADING 字面值与历史持久化数据一致，不可改动（旧数据的过滤判断依赖它）
const PLACEHOLDER_LOADING = 'AI正在回复中，请稍候...';
const PLACEHOLDER_THINKING = 'AI 正在深度思考中...';

// ★ 0.133：播客模式系统 prompt（发送时临时追加到消息末尾，不持久化、不进入后续上下文）
const PODCAST_PROMPT = '你的回答会用于语音朗读，请输出自然流畅的中文口语段落。禁止输出代码块、表格、列表、markdown 标记、特殊符号。只用连续自然的文字，适合耳朵收听。';

// ★ 0.144：回复长度 prompt 约束（发送时以 system 消息临时插入，不持久化；档位状态仅内存，重启恢复默认「中」）
const SHORT_REPLY_PROMPT = '你的回答尽量简短，只输出核心结论，不要多余解释，优先一句话给出答案。';
const MEDIUM_REPLY_PROMPT = '回答简洁完整，条理清晰，避免冗余啰嗦。';
const LONG_REPLY_PROMPT = '回答详细完整，分点展开，深度讲解原理，尽可能把内容讲透彻。';

// ★ 0.136：TTS 单段文本上限（HTTP 单段请求长度限制，留余量取 280；0.135 沿用值保留）
const TTS_MAX_SEGMENT_LEN = 280;

// ★ 新增：代码块组件，支持自动换行/横向滚动切换（0.122）
@ComponentV2
struct CodeBlockView {
  @Param content: string = '';   // 代码内容
  @Param isDark: boolean = false; // 深浅色主题
  @Local wrap: boolean = true;    // 默认开启自动换行

  build() {
    Column() {
      // ★ 按钮栏：左对齐 + 小字体 + 醒目样式（0.122 优化）
      Row() {
        // 切换图标：换行模式显示 ↩，滚动模式显示 ⇄
        Text(this.wrap ? '↩' : '⇄')
          .fontSize(11)
          .fontColor(this.isDark ? '#7AB8FF' : '#1976D2')
          .margin({ right: 3 })

        Text(this.wrap ? '自动换行' : '横向滚动')
          .fontSize(11)
          .fontColor(this.isDark ? '#7AB8FF' : '#1976D2')
      }
      .padding({ left: 6, right: 6, top: 3, bottom: 3 })
      .borderRadius(4)
      .backgroundColor(this.isDark ? '#1E3A5F' : '#E3F2FD')
      .border({ width: 0.5, color: this.isDark ? '#3D5A80' : '#90CAF9' })
      .margin({ top: 4, bottom: 2 })
      .onClick(() => {
        this.wrap = !this.wrap;
      })

      // 代码内容：根据 wrap 状态切换渲染模式
      if (this.wrap) {
        // 换行模式：Text 自然换行，无需 Scroll
        Text(this.content)
          .fontSize(14)
          .fontFamily('monospace')
          .fontColor(this.isDark ? '#D4D4D4' : '#333333')
          .padding(10)
          .backgroundColor(this.isDark ? '#2D2D2D' : '#F0F0F0')
          .borderRadius(6)
          .width('100%')
      } else {
        // 滚动模式：横向滚动查看长代码
        Scroll() {
          Text(this.content)
            .fontSize(14)
            .fontFamily('monospace')
            .fontColor(this.isDark ? '#D4D4D4' : '#333333')
            .padding(10)
            .backgroundColor(this.isDark ? '#2D2D2D' : '#F0F0F0')
            .borderRadius(6)
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Auto)
        .width('100%')
      }
    }
    .margin({ top: 6, bottom: 6 })
    .alignItems(HorizontalAlign.Start) // ★ 按钮左对齐（0.122 优化）
  }
}

// 对话页面 — V2 全量迁移
@ComponentV2
export struct ChatPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  store: BubbleTree = AppStorageV2.connect(BubbleTree, 'bubble-tree', () => new BubbleTree()) as BubbleTree;
  persistData: PersistData = PersistenceV2.connect(PersistData, 'persist-data', () => new PersistData()) as PersistData;
  currentBubbleStore: CurrentBubble = AppStorageV2.connect(CurrentBubble, 'current-bubble', () => new CurrentBubble()) as CurrentBubble;
  apiConfig: ApiConfig = connectApiConfig(); // ★ 0.143：换 key 'api-config-v2'（旧快照无 audioKey 字段致新增属性不落盘，工厂迁移历史配置）
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
  // ★ 0.133：发送模式下拉（'normal' 正常对话 | 'podcast' 播客模式）
  @Local sendMode: string = 'normal';
  @Local modeDropdownOpen: boolean = false;
  // ★ 0.144：回复长度下拉（'short' | 'medium' | 'long'，默认中回复；仅内存状态，重启恢复默认）
  @Local replyLengthMode: string = 'medium';
  @Local lengthDropdownOpen: boolean = false;
  // ★ 0.133：语音朗读状态（全局单播放源，驱动喇叭图标三态）
  @Local playingMessageId: string = '';    // 正在播放的消息 ID（🔊 态）
  @Local ttsLoadingMessageId: string = ''; // TTS 请求/等待中的消息 ID（⏳ 态，防重复点击）
  // ★ 0.136 恢复 0.134 分段流水线：逐段合成（HTTP 单段请求）+ 顺序播放（base64 → 临时文件 → AVPlayer）
  private ttsSegments: string[] = [];        // 文本分段队列
  private ttsRequestIndex: number = 0;       // 当前请求段索引（合成进度）
  private ttsPlayIndex: number = 0;          // 当前播放段索引（播放进度）
  private ttsAudioCache: string[] = [];      // 已合成段落的 base64 缓存（请求与播放解耦）
  private ttsWaitingForAudio: boolean = false; // 播放器空闲等待音频（true=播完缓存，等下一段合成）
  private ttsCurrentFd: number = -1;         // 当前播放的临时文件 fd（-1 无，播放完关闭）
  private ttsCurrentPath: string = '';       // 当前播放的临时文件路径（播放完删除）
  private ttsRequestController: StreamController | null = null; // 进行中的 HTTP 合成请求
  private ttsGeneration: number = 0;         // ★ 朗读会话代际号（stopTTS 递增，使在飞异步回调全部失效）
  private avPlayer: media.AVPlayer | null = null;
  private scroller: Scroller = new Scroller();
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
        // ★ 0.132：兼容加载/思考两个占位态
        if (msg.content.length > 0 && msg.content !== PLACEHOLDER_LOADING && msg.content !== PLACEHOLDER_THINKING) {
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
    const isPodcast = this.sendMode === 'podcast'; // ★ 0.133：本次发送模式
    const userMsg = new ChatMessage(generateMessageId(), 'user', this.inputText, [...this.pendingImages], 0, 0, isPodcast); // ★ 0.133：标记播客模式
    const aiMsg = new ChatMessage(generateMessageId(), 'assistant', PLACEHOLDER_LOADING, [], 0, 0, isPodcast); // ★ 0.132：占位常量；★ 0.133：标记播客模式
    this.currentBubble.messages = [...this.currentBubble.messages, userMsg, aiMsg];
    this.persistData.bubbleTreeJson = serializeBubbleTree(this.store);
    this.inputText = '';
    this.pendingImages = [];
    this.getUIContext().getFocusController().clearFocus(); // ★ 0.131：替代 TextAreaController.stopEditing（API 12+ 全设备兼容），发送后收起键盘
    this.isLoading = true;

    // 构建发送给 API 的消息列表：剔除空 content 的占位 AI 消息
    // ★ 替换为链路回溯 + 压缩（0.117）
    const messagesToSend = await this.buildBranchMessageList(this.currentBubble);

    // ★ 0.144：按回复长度档位以 system 消息插入 prompt 约束（与播客 prompt 同机制，不持久化；长度在前、播客贴近 user 消息）
    if (this.replyLengthMode === 'short') {
      messagesToSend.push(new ChatMessage(generateMessageId(), 'system', SHORT_REPLY_PROMPT));
    } else if (this.replyLengthMode === 'long') {
      messagesToSend.push(new ChatMessage(generateMessageId(), 'system', LONG_REPLY_PROMPT));
    } else {
      messagesToSend.push(new ChatMessage(generateMessageId(), 'system', MEDIUM_REPLY_PROMPT));
    }

    // ★ 0.133：播客模式在消息末尾追加系统 prompt（只在本次请求临时追加，不持久化、不进入后续上下文）
    if (isPodcast) {
      messagesToSend.push(new ChatMessage(generateMessageId(), 'system', PODCAST_PROMPT));
    }

    this.streamController = streamChat(
      messagesToSend,
      this.apiConfig,
      (chunk: string) => {
        // onChunk：首次收到数据时清除占位文字（兼容加载/思考两态），然后追加 AI content
        if (aiMsg.content === PLACEHOLDER_LOADING || aiMsg.content === PLACEHOLDER_THINKING) {
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
        // ★ 0.132 兜底：流结束但零内容时给出明确提示，杜绝任何场景永久卡占位
        if (aiMsg.content === PLACEHOLDER_LOADING || aiMsg.content === PLACEHOLDER_THINKING) {
          aiMsg.content = '（AI 未返回文本内容，请重试或更换模型）';
        }
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
      },
      (reasoning: string) => {
        // ★ 0.132 onReasoning：深度思考内容到达，占位切换为思考态
        // 思考内容不追加进 content（不参与持久化、不进入后续上下文），仅用于 UI 状态反馈
        if (aiMsg.content === PLACEHOLDER_LOADING) {
          aiMsg.content = PLACEHOLDER_THINKING;
        }
        this.scroller.scrollEdge(Edge.Bottom);
      }
    );
    // 发送消息后自动滚到底部
    this.scroller.scrollEdge(Edge.Bottom);
  }

  // ============================================================
  // ★ 0.133 新增：语音朗读（TTS 分段合成流水线播放）
  // ============================================================

  // toast 轻提示（showToast 可能抛异常，统一包裹消除编译告警，失败不影响主流程）
  showToastSafe(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (e) {
      // toast 失败静默忽略
    }
  }

  // 长文本按句末标点切句，累积成 ≤ TTS_MAX_SEGMENT_LEN 的段（TTS 单次请求有长度上限）
  splitTextForTTS(text: string): string[] {
    const result: string[] = [];
    if (text.trim().length === 0) {
      return result;
    }
    // 1. 按句末标点 + 换行切句
    const sentences: string[] = [];
    let current = '';
    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i);
      current += ch;
      if (ch === '。' || ch === '！' || ch === '？' || ch === '；' || ch === '\n' ||
        ch === '!' || ch === '?' || ch === ';') {
        sentences.push(current);
        current = '';
      }
    }
    if (current.length > 0) {
      sentences.push(current);
    }
    // 2. 累积成段（≤ 上限）；超长句交给 splitLongSentence 处理
    let seg = '';
    for (let i = 0; i < sentences.length; i++) {
      const s = sentences[i];
      if (s.length > TTS_MAX_SEGMENT_LEN) {
        if (seg.length > 0) {
          result.push(seg);
          seg = '';
        }
        const parts = this.splitLongSentence(s, TTS_MAX_SEGMENT_LEN);
        for (let j = 0; j < parts.length; j++) {
          result.push(parts[j]);
        }
        continue;
      }
      if (seg.length + s.length > TTS_MAX_SEGMENT_LEN) {
        result.push(seg);
        seg = s;
      } else {
        seg += s;
      }
    }
    if (seg.length > 0) {
      result.push(seg);
    }
    return result;
  }

  // 超长单句兜底：先按逗号类标点切小片累积，单片仍超上限则硬切
  splitLongSentence(s: string, maxLen: number): string[] {
    const pieces: string[] = [];
    let cur = '';
    for (let i = 0; i < s.length; i++) {
      const ch = s.charAt(i);
      cur += ch;
      if (ch === '，' || ch === '、' || ch === ',' || ch === '：' || ch === ':') {
        pieces.push(cur);
        cur = '';
      }
    }
    if (cur.length > 0) {
      pieces.push(cur);
    }
    const parts: string[] = [];
    let seg = '';
    for (let i = 0; i < pieces.length; i++) {
      const p = pieces[i];
      if (p.length > maxLen) {
        if (seg.length > 0) {
          parts.push(seg);
          seg = '';
        }
        let start = 0;
        while (start < p.length) {
          const end = Math.min(start + maxLen, p.length);
          parts.push(p.substring(start, end));
          start = end;
        }
        continue;
      }
      if (seg.length + p.length > maxLen) {
        parts.push(seg);
        seg = p;
      } else {
        seg += p;
      }
    }
    if (seg.length > 0) {
      parts.push(seg);
    }
    return parts;
  }

  // 点击喇叭入口：三态判断 + 播新停旧 + 启动朗读会话
  startTTS(msg: ChatMessage): void {
    // 合成/加载中 → 防重复点击
    if (this.ttsLoadingMessageId === msg.messageId) {
      return;
    }
    // 正在播放这条消息 → 点击即停止
    if (this.playingMessageId === msg.messageId) {
      this.stopTTS();
      return;
    }
    // 占位态不可读（AI 尚未开始输出）
    if (msg.content === PLACEHOLDER_LOADING || msg.content === PLACEHOLDER_THINKING) {
      this.showToastSafe('AI 回复完成后才能朗读');
      return;
    }
    if (msg.content.trim().length === 0) {
      this.showToastSafe('消息内容为空，无法朗读');
      return;
    }
    // 播新停旧：先终止当前朗读会话
    this.stopTTS();
    // ★ 0.136 恢复 0.134 分段流水线：逐段 HTTP 合成 + 顺序播放
    this.playingMessageId = msg.messageId;
    this.ttsLoadingMessageId = msg.messageId;
    this.ttsSegments = this.splitTextForTTS(msg.content);
    this.ttsRequestIndex = 0;
    this.ttsPlayIndex = 0;
    this.ttsAudioCache = [];
    this.ttsWaitingForAudio = true; // ★ 0.142：初始即「等音频」——首段到达立即开播（原 false 死锁：onDone 不触发播放、无人再调 tryPlayNextAudio）
    this.requestNextSegment();
  }

  // 请求下一段合成（串行流水线：上一段回调后才请求下一段，controller 始终指向在飞请求）
  requestNextSegment(): void {
    if (this.ttsRequestIndex >= this.ttsSegments.length) {
      this.ttsRequestController = null; // 全部段落已发出
      return;
    }
    const gen = this.ttsGeneration;
    const index = this.ttsRequestIndex;
    this.ttsRequestIndex++;
    this.ttsRequestController = synthesizeTTS(
      this.ttsSegments[index],
      this.apiConfig,
      (audioBase64: string) => {
        if (gen !== this.ttsGeneration) {
          return; // 会话已停止/被新会话取代，丢弃过期结果
        }
        this.ttsAudioCache.push(audioBase64);
        // 播放器空闲（等音频）→ 立即开播
        if (this.ttsWaitingForAudio) {
          this.tryPlayNextAudio();
        }
        // 继续请求下一段（串行流水线）
        this.requestNextSegment();
      },
      (err: string) => {
        if (gen !== this.ttsGeneration) {
          return;
        }
        console.error(`[ChatPage] 第 ${index + 1} 段合成失败: ${err}`);
        this.showToastSafe(`语音合成失败：${err.substring(0, 150)}`);
        this.stopTTS();
      }
    );
  }

  // 尝试播放下一段缓存音频（有缓存开播；缓存播完等合成或正常收尾）
  tryPlayNextAudio(): void {
    if (this.playingMessageId === '') {
      return; // 会话已停止
    }
    if (this.ttsPlayIndex >= this.ttsAudioCache.length) {
      if (this.ttsAudioCache.length >= this.ttsSegments.length) {
        // 全部段落合成完且播完 → 正常结束
        this.stopTTS();
      } else {
        // 缓存播完但合成未完 → 等待下一段合成回调
        this.ttsWaitingForAudio = true;
      }
      return;
    }
    this.ttsWaitingForAudio = false;
    this.playSegment(this.ttsPlayIndex);
  }

  // 停止整个朗读会话：取消请求 + 释放播放器与临时文件 + 清空队列与状态（幂等，可安全重复调用）
  stopTTS(): void {
    this.ttsGeneration++; // 使所有在飞的异步回调失效（会话代际号）
    if (this.ttsRequestController) {
      this.ttsRequestController.cancel();
      this.ttsRequestController = null;
    }
    this.cleanupSegment();
    this.ttsSegments = [];
    this.ttsRequestIndex = 0;
    this.ttsPlayIndex = 0;
    this.ttsAudioCache = [];
    this.ttsWaitingForAudio = false;
    this.playingMessageId = '';
    this.ttsLoadingMessageId = '';
  }

  // 清理当前段的播放器 + 临时文件 + fd（播放完成/停止时调用，幂等）
  cleanupSegment(): void {
    const player = this.avPlayer;
    this.avPlayer = null;
    if (player) {
      player.release().catch(() => {
        // 释放失败忽略（播放器已不可用）
      });
    }
    if (this.ttsCurrentFd >= 0) {
      try {
        fileIo.closeSync(this.ttsCurrentFd);
      } catch (e) {
        // 已关闭
      }
      this.ttsCurrentFd = -1;
    }
    if (this.ttsCurrentPath.length > 0) {
      try {
        fileIo.unlinkSync(this.ttsCurrentPath);
      } catch (e) {
        // 已删除
      }
      this.ttsCurrentPath = '';
    }
  }

  // 播放一段音频：base64 解码 → cacheDir 临时文件 → AVPlayer fd:// 播放（0.134 流水线恢复）
  async playSegment(index: number): Promise<void> {
    const gen = this.ttsGeneration;
    // 开播：清除加载态（喇叭图标 ⏳ → 🔊）
    this.ttsLoadingMessageId = '';
    try {
      // 设备能力检查：media.AVPlayer 不是全设备支持（消除 SysCap 告警的官方推荐做法）
      if (!canIUse('SystemCapability.Multimedia.Media.AVPlayer')) {
        this.showToastSafe('当前设备不支持音频播放');
        this.stopTTS();
        return;
      }
      // base64 → 二进制 → cacheDir 临时文件
      const audioBytes = buffer.from(this.ttsAudioCache[index], 'base64');
      const ctx = this.getUIContext().getHostContext(); // ★ 0.136：V2 组件无 getContext()，用 getHostContext() 取 Context
      const cacheDir = ctx ? ctx.cacheDir : '';
      const path = `${cacheDir}/tts_${Date.now()}.mp3`;
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, audioBytes.buffer.slice(audioBytes.byteOffset, audioBytes.byteOffset + audioBytes.length) as ArrayBuffer);
      if (gen !== this.ttsGeneration) {
        // 写文件期间会话被停止 → 清理退出
        fileIo.closeSync(file);
        fileIo.unlinkSync(path);
        return;
      }
      // fd 保持打开供播放器使用（fdSrc 模式），播放完成后 cleanupSegment 关闭
      this.ttsCurrentFd = file.fd;
      this.ttsCurrentPath = path;

      const player = await media.createAVPlayer();
      if (gen !== this.ttsGeneration) {
        // 等待期间会话被停止/取代 → 释放新建的播放器并清理退出
        player.release();
        this.cleanupSegment();
        return;
      }
      this.avPlayer = player;
      player.on('stateChange', (state: string) => {
        if (gen !== this.ttsGeneration) {
          return; // 过期回调
        }
        if (state === 'initialized') {
          player.prepare();
        } else if (state === 'prepared') {
          player.play();
        } else if (state === 'completed') {
          // 本段播完：清理 → 播下一段
          this.cleanupSegment();
          this.ttsPlayIndex++;
          this.tryPlayNextAudio();
        }
      });
      player.on('error', (err: BusinessError) => {
        console.error(`[ChatPage] AVPlayer 错误: ${err.message}`);
        this.showToastSafe('音频播放失败');
        this.stopTTS();
      });
      player.fdSrc = { fd: file.fd }; // fd 播放模式，触发 initialized → prepare → play
    } catch (err) {
      console.error(`[ChatPage] TTS 播放失败: ${(err as Error).message}`);
      this.showToastSafe('音频播放失败');
      this.stopTTS();
    }
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
    this.stopTTS(); // ★ 0.133：退出对话页停止朗读（现有交互下切气泡必经 pop，一个钩子覆盖退页+切气泡两种情况）
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
    // ★ 0.133：删除正在朗读/合成中的消息 → 停止播放
    if (this.playingMessageId === messageId || this.ttsLoadingMessageId === messageId) {
      this.stopTTS();
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
    this.store.needsRelayout = true; // ★ 0.126：通知 BBTreeCanvas 重新布局
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
                  // ★ 0.147：AI 消息气泡贴右（0.145），删除按钮移到气泡左侧——否则 × 被挤到屏幕最右缘
                  if (msg.role === 'assistant') {
                    Button('×')
                      .fontSize(16)
                      .fontColor('#F44336')
                      .backgroundColor(Color.Transparent)
                      .padding({ left: 2, right: 2 }) // ★ 0.148：压掉 Button 默认大内边距（≈32vp），给气泡留宽度
                      .margin({ right: 4 })
                      .onClick(() => {
                        this.deleteMessage(msg.messageId);
                      })
                  }
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
                          .constraintSize({ maxWidth: '85%' }) // ★ 0.148：气泡最大宽度约束——长文本自动换行，防溢出屏幕
                      } else {
                        // ★ 0.146：包裹容器——气泡与操作行组成同宽块，token 统计行左缘对齐气泡左缘（用户要求）
                        Column() {
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
                              // ★ 代码块：使用 CodeBlockView 组件，支持自动换行切换（0.122）
                              CodeBlockView({
                                content: seg.content,
                                isDark: this.getThemeStore().isDark
                              })
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
                           // ★ 0.132 修复：key 纳入 content/header/rows 尺寸——流式追加时 key 变化触发 item 重建，
                           // 否则 key 恒定导致 ForEach 复用旧 item，MdSegment 非响应式，Text 永不更新（卡占位 bug 根因）
                           }, (seg: MdSegment, idx: number) => `${idx}_${seg.type}_${seg.content.length}_${seg.header.length}_${seg.rows.length}`)
                        }
                        .constraintSize({ maxWidth: '85%' }) // ★ 0.148：气泡最大宽度约束——长文本行自动换行，防气泡被撑出屏幕右缘（用户截图实证）
                        .padding(10)
                        .borderRadius(8)
                        .backgroundColor(this.getThemeStore().isDark ? '#1E1E1E' : '#F5F5F5')
                        .alignItems(HorizontalAlign.Start) // ★ 0.145：气泡内段落保持左对齐（阅读习惯），气泡整体位置由外层 alignItems 控制

                        // ★ 0.133：AI 消息操作行（token 统计 + 朗读喇叭三态：🔈 空闲 / ⏳ 合成中 / 🔊 播放中）
                        // ★ 0.146：移入包裹容器——行宽自适应，左缘对齐气泡内文字（margin left 10 = 气泡 padding 10）
                        if (msg.role === 'assistant') {
                          Row() {
                            if (msg.outputTokens > 0) {
                              Text(`输入 ${msg.inputTokens} · 输出 ${msg.outputTokens}`)
                                .fontSize(11)
                                .fontColor(this.getThemeStore().isDark ? '#888' : '#999')
                            }
                            Blank()
                              .width(12) // ★ 0.146：固定间距（原 layoutWeight(1) 在自适应行内失效）
                            Button(this.ttsLoadingMessageId === msg.messageId ? '⏳' : (this.playingMessageId === msg.messageId ? '🔊' : '🔈'))
                              .fontSize(14)
                              .backgroundColor(Color.Transparent)
                              .fontColor(this.playingMessageId === msg.messageId || this.ttsLoadingMessageId === msg.messageId
                                ? '#1976D2' : (this.getThemeStore().isDark ? '#888' : '#999'))
                              .padding({ left: 8, right: 4, top: 2, bottom: 2 })
                              .onClick(() => {
                                this.startTTS(msg);
                              })
                          }
                          .margin({ top: 4, right: 10 }) // ★ 0.148：右对齐后 right 10 = 气泡 padding 10，喇叭与气泡内文字右缘对齐
                        }
                        }
                        .alignItems(HorizontalAlign.End) // ★ 0.148：包裹容器内操作行贴气泡右缘（用户要求统计行+喇叭右对齐）；气泡为最宽子元素不受影响
                      }
                      }
                  }
                  .alignItems(msg.role === 'user' ? HorizontalAlign.Start : HorizontalAlign.End) // ★ 0.145：AI 回复气泡贴右（用户要求右对齐）；用户消息保持靠左

                  // ★ 0.147：用户消息气泡靠左，删除按钮保持气泡右侧
                  if (msg.role === 'user') {
                    Button('×')
                      .fontSize(16)
                      .fontColor('#F44336')
                      .backgroundColor(Color.Transparent)
                      .padding({ left: 2, right: 2 }) // ★ 0.148：与 AI 分支 × 保持一致的紧凑内边距
                      .onClick(() => {
                        this.deleteMessage(msg.messageId);
                      })
                  }
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

        // 输入区域 — 图片按钮 + 输入框 + 回复长度 + 模式 + 发送按钮
        Row() {
          // ★ 0.144：图片附件按钮（暂用相机图标占位，后续有资源换图片图标；图标缩小+内边距压最小，不挤压输入框）
          Button('📷')
            .fontSize(16)
            .backgroundColor(Color.Transparent)
            .fontColor('#666')
            .padding({ left: 2, right: 2 })
            .margin({ right: 2 })
            .onClick(() => {
              this.selectImages();
            })

          TextArea({ text: $$this.inputText, placeholder: '输入问题...' }) // ★ 0.131：去掉 controller 参数（TextAreaController 已移除）
            .layoutWeight(1)
            .height(this.inputAreaHeight) // ★ 新增：动态高度，≤5行自适应，>5行固定触发内部滚动（0.118）
            .enterKeyType(EnterKeyType.NEW_LINE)
            .margin({ left: 6, right: 6 }) // ★ 0.144：输入框与两侧图标按钮留出呼吸间距

          // ★ 0.144：回复长度下拉按钮（📏），默认中回复灰色、短/长高亮；与模式下拉互斥展开；图标缩小+内边距压最小
          Button('📏')
            .fontSize(16)
            .backgroundColor(Color.Transparent)
            .fontColor(this.replyLengthMode !== 'medium' ? '#1976D2' : '#666')
            .padding({ left: 2, right: 2 })
            .margin({ left: 0, right: 2 })
            .onClick(() => {
              this.lengthDropdownOpen = !this.lengthDropdownOpen;
              this.modeDropdownOpen = false;
            })

          // ★ 0.133：发送模式下拉按钮（💬 正常对话 | 🎙 播客模式），点击弹出选择面板；★ 0.144：图标缩小+内边距压最小
          Button(this.sendMode === 'podcast' ? '🎙' : '💬')
            .fontSize(16)
            .backgroundColor(Color.Transparent)
            .fontColor(this.sendMode === 'podcast' ? '#1976D2' : '#666')
            .padding({ left: 2, right: 2 })
            .margin({ left: 0, right: 2 })
            .onClick(() => {
              this.modeDropdownOpen = !this.modeDropdownOpen;
              this.lengthDropdownOpen = false; // ★ 0.144：互斥——打开模式下拉时收起长度下拉
            })

          Button('发送')
            .enabled(!this.isLoading)
            .margin({ left: 4 }) // ★ 0.144：收紧与模式按钮的间距，把宽度让给输入框
            .onClick(() => {
              this.sendMessage();
            })
        }
        .width('100%')
        .padding({ left: 6, right: 6, top: 8, bottom: 8 }) // ★ 0.143：输入区顶部留白——消息列表/图片预览与输入框原本贴边，加 top 12 与列表顶部 padding 呼应
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

        // ★ 0.133：发送模式选择面板（半透明遮罩 + 右下角面板，浮于输入区上方）
        if (this.modeDropdownOpen) {
          Stack() {
            // 遮罩：点击关闭面板
            Column() {
              Blank()
            }
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.4)')
            .onClick(() => {
              this.modeDropdownOpen = false;
            })

            // 面板：两个模式选项（当前模式高亮）
            Column() {
              Text('💬 正常对话')
                .fontSize(14)
                .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
                .width('100%')
                .padding(12)
                .textAlign(TextAlign.Start)
                .backgroundColor(this.sendMode === 'normal' ? (this.getThemeStore().isDark ? '#1E3A5F' : '#E3F2FD') : Color.Transparent)
                .borderRadius(8)
                .onClick(() => {
                  this.sendMode = 'normal';
                  this.modeDropdownOpen = false;
                })
              Text('🎙 播客模式')
                .fontSize(14)
                .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
                .width('100%')
                .padding(12)
                .textAlign(TextAlign.Start)
                .backgroundColor(this.sendMode === 'podcast' ? (this.getThemeStore().isDark ? '#1E3A5F' : '#E3F2FD') : Color.Transparent)
                .borderRadius(8)
                .onClick(() => {
                  this.sendMode = 'podcast';
                  this.modeDropdownOpen = false;
                })
              Text('口语化输出，适合朗读')
                .fontSize(11)
                .fontColor(this.getThemeStore().isDark ? '#777777' : '#999')
                .width('100%')
                .padding({ left: 12, bottom: 8 })
                .textAlign(TextAlign.Start)
            }
            .width(180)
            .borderRadius(12)
            .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#FFFFFF')
            .border({ width: 1, color: this.getThemeStore().isDark ? '#555555' : '#E0E0E0' })
            .padding(4)
            .margin({ bottom: 64, right: 16 }) // 抬到输入区上方（输入框一行 40vp + 底部 padding 16vp + 间隙 8vp）
          }
          .alignContent(Alignment.BottomEnd)
          .width('100%')
          .height('100%')
        }

        // ★ 0.144：回复长度选择面板（结构复制播客面板，三档选项 + 小字提示，浮于输入区上方）
        if (this.lengthDropdownOpen) {
          Stack() {
            // 遮罩：点击关闭面板
            Column() {
              Blank()
            }
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.4)')
            .onClick(() => {
              this.lengthDropdownOpen = false;
            })

            // 面板：三个长度选项（当前档位高亮）
            Column() {
              Text('短回复')
                .fontSize(14)
                .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
                .width('100%')
                .padding(12)
                .textAlign(TextAlign.Start)
                .backgroundColor(this.replyLengthMode === 'short' ? (this.getThemeStore().isDark ? '#1E3A5F' : '#E3F2FD') : Color.Transparent)
                .borderRadius(8)
                .onClick(() => {
                  this.replyLengthMode = 'short';
                  this.lengthDropdownOpen = false;
                })
              Text('中回复')
                .fontSize(14)
                .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
                .width('100%')
                .padding(12)
                .textAlign(TextAlign.Start)
                .backgroundColor(this.replyLengthMode === 'medium' ? (this.getThemeStore().isDark ? '#1E3A5F' : '#E3F2FD') : Color.Transparent)
                .borderRadius(8)
                .onClick(() => {
                  this.replyLengthMode = 'medium';
                  this.lengthDropdownOpen = false;
                })
              Text('长回复')
                .fontSize(14)
                .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
                .width('100%')
                .padding(12)
                .textAlign(TextAlign.Start)
                .backgroundColor(this.replyLengthMode === 'long' ? (this.getThemeStore().isDark ? '#1E3A5F' : '#E3F2FD') : Color.Transparent)
                .borderRadius(8)
                .onClick(() => {
                  this.replyLengthMode = 'long';
                  this.lengthDropdownOpen = false;
                })
              Text('输出长度为 AI 参考约束，无法保证严格固定字数')
                .fontSize(11)
                .fontColor(this.getThemeStore().isDark ? '#777777' : '#999')
                .width('100%')
                .padding({ left: 12, bottom: 8 })
                .textAlign(TextAlign.Start)
            }
            .width(180)
            .borderRadius(12)
            .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#FFFFFF')
            .border({ width: 1, color: this.getThemeStore().isDark ? '#555555' : '#E0E0E0' })
            .padding(4)
            .margin({ bottom: 64, right: 120 }) // 锚在长度按钮上方（右移避开模式按钮与发送按钮占位）
          }
          .alignContent(Alignment.BottomEnd)
          .width('100%')
          .height('100%')
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
