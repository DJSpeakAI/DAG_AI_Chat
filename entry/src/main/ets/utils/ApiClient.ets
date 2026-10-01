// ============================================================
// ApiClient.ets — AI 大模型 API 请求客户端
// ============================================================
// 本文件封装了与火山引擎（Volcano）AI 大模型的通信逻辑：
//   - streamChat()：流式对话请求，AI 边生成边返回（SSE 协议）
//   - StreamController：流式请求控制器，支持手动 cancel 终止请求
//   - parseSSEChunk()：解析 SSE（Server-Sent Events）数据块
//
// 工作流程：
//   1. 构建 OpenAI 兼容格式的请求体（model + messages + stream:true）
//   2. 发送 HTTP POST 请求，设置 Authorization Bearer 头
//   3. 接收 SSE 流式响应，逐块解析出 AI 生成的文本片段
//   4. 通过 onChunk 回调实时推送文本片段到 UI（打字机效果）
//   5. 流结束后通过 onDone 回调通知 UI 完成
// ============================================================

import { http } from '@kit.NetworkKit';
import { buffer } from '@kit.ArkTS';
import { ChatMessage, ApiConfig } from '../common/ChatModel';

// ========== 接口定义 ==========
// 多模态内容片段 — 文本
interface TextContentPart {
  type: string;
  text: string;
}

// 多模态内容片段 — 图片 URL 对象
interface ImageUrlObj {
  url: string;
}

// 多模态内容片段 — 图片
interface ImageContentPart {
  type: string;
  image_url: ImageUrlObj;
}

// 火山引擎请求消息（OpenAI 兼容格式）
// content 纯文本时为 string，多模态时为 Object[]（TextContentPart | ImageContentPart）
interface VolcanoMessage {
  role: string;
  content: Object;
}

// 火山引擎请求体
interface StreamOptions {
  include_usage: boolean;
}

interface VolcanoRequestBody {
  model: string;
  messages: VolcanoMessage[];
  stream: boolean;
  stream_options?: StreamOptions;
}

// 流式控制器：支持手动 cancel 终止请求
export interface StreamController {
  cancel: () => void;
}

// SSE 解析结果
interface SSEResult {
  texts: string[];
  reasonings: string[]; // ★ 0.132：深度思考内容分片（Seed 系列思考模型 reasoning_content）
  remainder: string;
  usage?: SSEResponseUsage;
}

// SSE 响应 JSON 结构
interface SSEResponseDelta {
  content?: string;
  reasoning_content?: string; // ★ 0.132：深度思考内容（火山方舟 Seed 系列思考模型）
}

interface SSEResponseChoice {
  delta?: SSEResponseDelta;
}

interface SSEResponse {
  choices?: SSEResponseChoice[];
  usage?: SSEResponseUsage;
}

interface SSEResponseUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
  total_tokens?: number;
}

// ========== 消息转换 ==========
// 把项目 ChatMessage[] 转为火山 OpenAI 兼容格式
// 支持多模态：有图片时 content 为数组，无图片时 content 为 string
function buildMessages(messages: ChatMessage[]): VolcanoMessage[] {
  const result: VolcanoMessage[] = [];
  for (let i = 0; i < messages.length; i++) {
    const msg = messages[i];
    if (msg.imageUrl && msg.imageUrl.length > 0) {
      // 多模态：content 为数组
      const parts: Object[] = [];
      if (msg.content.length > 0) {
        const textPart: TextContentPart = { type: 'text', text: msg.content };
        parts.push(textPart);
      }
      for (let j = 0; j < msg.imageUrl.length; j++) {
        const imgUrl: ImageUrlObj = { url: msg.imageUrl[j] };
        const imgPart: ImageContentPart = { type: 'image_url', image_url: imgUrl };
        parts.push(imgPart);
      }
      const m: VolcanoMessage = {
        role: msg.role === 'user' ? 'user' : 'assistant',
        content: parts
      };
      result.push(m);
    } else {
      // 纯文本：content 为 string
      const m: VolcanoMessage = {
        role: msg.role === 'user' ? 'user' : 'assistant',
        content: msg.content
      };
      result.push(m);
    }
  }
  return result;
}

// ========== SSE 解析器 ==========
// 解析累积 buffer，按 \n 分割事件，返回提取的文本分片和剩余未解析数据
function parseSSEChunk(accumulated: string): SSEResult {
  const texts: string[] = [];
  const reasonings: string[] = []; // ★ 0.132
  let usage: SSEResponseUsage | undefined = undefined;
  const lines = accumulated.split('\n');
  const remainder = lines.pop() || ''; // 最后一段可能不完整，保留
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    // 跳过空行、注释行、非 data 行
    if (line === '' || line.startsWith(':') || !line.startsWith('data:')) {
      continue;
    }
    const data = line.substring(5).trim(); // 去掉 "data:" 前缀
    if (data === '[DONE]') {
      continue; // 流式结束标记
    }
    try {
      const json = JSON.parse(data) as SSEResponse;
      if (json.choices && json.choices.length > 0 && json.choices[0].delta) {
        const delta = json.choices[0].delta!;
        if (delta.content) {
          texts.push(delta.content!);
        }
        if (delta.reasoning_content) { // ★ 0.132：思考内容单独收集，不混入正式回答
          reasonings.push(delta.reasoning_content!);
        }
      }
      if (json.usage) {
        usage = json.usage;
      }
    } catch (e) {
      // 单条 JSON 解析失败不中断整个流
    }
  }
  const result: SSEResult = { texts: texts, reasonings: reasonings, remainder: remainder, usage: usage };
  return result;
}

// ========== 资源清理 ==========
// off 事件监听 + destroy 销毁 httpRequest
function cleanupRequest(httpRequest: http.HttpRequest): void {
  httpRequest.off('dataReceive');
  httpRequest.off('dataEnd');
  httpRequest.off('headersReceive'); // ★ 0.131：API 8 起废弃单数 headerReceive，官方推荐复数 headersReceive
  httpRequest.destroy();
}

// ========== 流式聊天主函数 ==========
// 发起火山引擎 SSE 流式请求
// onChunk: 每收到一段文本回调（实时追加到 AI 消息 content）
// onDone: 流式结束回调
// onError: 错误回调
// onReasoning: 深度思考内容回调（可选，Seed 系列思考模型的 reasoning_content，不传则忽略）
// 返回 StreamController，支持手动 cancel
export function streamChat(
  messages: ChatMessage[],
  config: ApiConfig,
  onChunk: (text: string) => void,
  onDone: (inputTokens: number, outputTokens: number) => void,
  onError: (error: string) => void,
  onReasoning?: (text: string) => void // ★ 0.132：深度思考内容回调（可选）
): StreamController {
  let cancelled = false;
  const httpRequest = http.createHttp();
  let sseBuffer = '';
  let pendingBytes: Uint8Array = new Uint8Array(0); // ★ 0.132：字节级缓冲，防 UTF-8 多字节字符被 TCP chunk 切断
  let trackedUsage: SSEResponseUsage | undefined = undefined;

  // 订阅流式数据回调
  httpRequest.on('dataReceive', (data: ArrayBuffer) => {
    if (cancelled) {
      return;
    }
    // ★ 0.132：字节级累积，只在最后一个 \n 边界处解码——被切断的多字节字符必然位于
    // 最后一个 \n 之后，等下个 chunk 拼齐后才解码，杜绝 U+FFFD 乱码导致的 JSON 解析失败
    const incoming = new Uint8Array(data);
    const merged = new Uint8Array(pendingBytes.length + incoming.length);
    merged.set(pendingBytes);
    merged.set(incoming, pendingBytes.length);
    // 从尾部向前找最后一个换行符（0x0A）
    let lastNl = -1;
    for (let i = merged.length - 1; i >= 0; i--) {
      if (merged[i] === 0x0A) {
        lastNl = i;
        break;
      }
    }
    if (lastNl < 0) {
      // 没有任何完整行，全部字节留待下个 chunk
      pendingBytes = merged;
      return;
    }
    const complete = merged.subarray(0, lastNl + 1);
    const dataStr = buffer.from(complete.buffer, complete.byteOffset, complete.byteLength).toString();
    pendingBytes = merged.subarray(lastNl + 1); // 不完整尾部留待下个 chunk
    // ④ 日志：收到数据
    console.info(`[ApiClient] ④ dataReceive 长度=${dataStr.length}, 预览=${dataStr.substring(0, 200)}`);
    // 追加到累积 buffer 并解析 SSE 事件
    sseBuffer += dataStr;
    const parsed = parseSSEChunk(sseBuffer);
    sseBuffer = parsed.remainder;
    // 逐个回调文本分片
    for (let i = 0; i < parsed.texts.length; i++) {
      console.info(`[ApiClient] chunk=${parsed.texts[i]}`);
      onChunk(parsed.texts[i]);
    }
    // ★ 0.132：逐个回调思考内容分片
    for (let i = 0; i < parsed.reasonings.length; i++) {
      if (onReasoning !== undefined) {
        onReasoning(parsed.reasonings[i]);
      }
    }
    if (parsed.usage) {
      trackedUsage = parsed.usage;
    }
  });

  // ③ 日志：响应头（含状态码）
  httpRequest.on('headersReceive', (header: Object) => { // ★ 0.131：单数 headerReceive 已废弃，改复数
    console.info(`[ApiClient] ③ headersReceive: ${JSON.stringify(header)}`);
  });

  // 流式结束回调
  httpRequest.on('dataEnd', () => {
    if (cancelled) {
      return;
    }
    // ⑤ 日志：流结束
    console.info('[ApiClient] ⑤ dataEnd 流结束');
    // ★ 0.132：刷出字节缓冲中未达行尾的剩余字节（服务端最后一条事件可能无结尾换行）
    if (pendingBytes.length > 0) {
      sseBuffer += buffer.from(pendingBytes.buffer, pendingBytes.byteOffset, pendingBytes.byteLength).toString();
      pendingBytes = new Uint8Array(0);
    }
    // 处理剩余 buffer
    if (sseBuffer.trim().length > 0) {
      const parsed = parseSSEChunk(sseBuffer + '\n');
      for (let i = 0; i < parsed.texts.length; i++) {
        onChunk(parsed.texts[i]);
      }
      for (let i = 0; i < parsed.reasonings.length; i++) {
        if (onReasoning !== undefined) {
          onReasoning(parsed.reasonings[i]);
        }
      }
      if (parsed.usage) {
        trackedUsage = parsed.usage;
      }
    }
    onDone(trackedUsage?.prompt_tokens ?? 0, trackedUsage?.completion_tokens ?? 0);
    cleanupRequest(httpRequest);
  });

  // 构建请求体
  const streamOpts: StreamOptions = { include_usage: true };
  const body: VolcanoRequestBody = {
    model: config.model,
    messages: buildMessages(messages),
    stream: true,
    stream_options: streamOpts
  };

  // ① 日志：请求构建完成
  const maskedKey = config.apiKey.length > 8
    ? `${config.apiKey.substring(0, 4)}...${config.apiKey.substring(config.apiKey.length - 4)}`
    : config.apiKey;
  console.info(`[ApiClient] ① 请求构建:`);
  console.info(`[ApiClient]   URL: ${config.endpoint}`);
  console.info(`[ApiClient]   API Key(脱敏): ${maskedKey}`);
  console.info(`[ApiClient]   Model: ${config.model}`);
  console.info(`[ApiClient]   Body: ${JSON.stringify(body)}`);

  // ② 发起流式请求
  console.info('[ApiClient] ② 调用 requestInStream...');
  httpRequest.requestInStream(config.endpoint, {
    method: http.RequestMethod.POST,
    header: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${config.apiKey}`
    },
    extraData: JSON.stringify(body),
    connectTimeout: 30000,
    readTimeout: 60000,
  }).then(() => {
    // ⑥ 日志：Promise resolve
    console.info('[ApiClient] ⑥ requestInStream Promise resolved（请求成功）');
  }).catch((err: Error) => {
    if (cancelled) {
      return;
    }
    // ⑦ 日志：请求失败
    console.error(`[ApiClient] ⑦ requestInStream 失败: ${err.message}`);
    console.error(`[ApiClient]   err.name: ${err.name}`);
    console.error(`[ApiClient]   err.stack: ${err.stack}`);
    onError(err.message);
    cleanupRequest(httpRequest);
  });

  // 返回控制器，支持手动 cancel
  const controller: StreamController = {
    cancel: () => {
      cancelled = true;
      cleanupRequest(httpRequest);
    }
  };
  return controller;
}
// ★ 删除未使用的 testApiConnection + testApiWithDiagnostics（0.122 清理）
