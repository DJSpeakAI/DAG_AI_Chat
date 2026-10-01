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
  remainder: string;
  usage?: SSEResponseUsage;
}

// SSE 响应 JSON 结构
interface SSEResponseDelta {
  content?: string;
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
      if (json.choices && json.choices.length > 0 && json.choices[0].delta && json.choices[0].delta!.content) {
        texts.push(json.choices[0].delta!.content!);
      }
      if (json.usage) {
        usage = json.usage;
      }
    } catch (e) {
      // 单条 JSON 解析失败不中断整个流
    }
  }
  const result: SSEResult = { texts: texts, remainder: remainder, usage: usage };
  return result;
}

// ========== 资源清理 ==========
// off 事件监听 + destroy 销毁 httpRequest
function cleanupRequest(httpRequest: http.HttpRequest): void {
  httpRequest.off('dataReceive');
  httpRequest.off('dataEnd');
  httpRequest.off('headerReceive');
  httpRequest.destroy();
}

// ========== 流式聊天主函数 ==========
// 发起火山引擎 SSE 流式请求
// onChunk: 每收到一段文本回调（实时追加到 AI 消息 content）
// onDone: 流式结束回调
// onError: 错误回调
// 返回 StreamController，支持手动 cancel
export function streamChat(
  messages: ChatMessage[],
  config: ApiConfig,
  onChunk: (text: string) => void,
  onDone: (inputTokens: number, outputTokens: number) => void,
  onError: (error: string) => void
): StreamController {
  let cancelled = false;
  const httpRequest = http.createHttp();
  let sseBuffer = '';
  let trackedUsage: SSEResponseUsage | undefined = undefined;

  // 订阅流式数据回调
  httpRequest.on('dataReceive', (data: ArrayBuffer) => {
    if (cancelled) {
      return;
    }
    // ④ 日志：收到数据
    const dataStr = buffer.from(data).toString();
    console.info(`[ApiClient] ④ dataReceive 长度=${dataStr.length}, 预览=${dataStr.substring(0, 200)}`);
    // ArrayBuffer 转字符串，追加到累积 buffer
    sseBuffer += dataStr;
    // 解析 SSE 事件
    const parsed = parseSSEChunk(sseBuffer);
    sseBuffer = parsed.remainder;
    // 逐个回调文本分片
    for (let i = 0; i < parsed.texts.length; i++) {
      console.info(`[ApiClient] chunk=${parsed.texts[i]}`);
      onChunk(parsed.texts[i]);
    }
    if (parsed.usage) {
      trackedUsage = parsed.usage;
    }
  });

  // ③ 日志：响应头（含状态码）
  httpRequest.on('headerReceive', (header: Object) => {
    console.info(`[ApiClient] ③ headerReceive: ${JSON.stringify(header)}`);
  });

  // 流式结束回调
  httpRequest.on('dataEnd', () => {
    if (cancelled) {
      return;
    }
    // ⑤ 日志：流结束
    console.info('[ApiClient] ⑤ dataEnd 流结束');
    // 处理剩余 buffer
    if (sseBuffer.trim().length > 0) {
      const parsed = parseSSEChunk(sseBuffer + '\n');
      for (let i = 0; i < parsed.texts.length; i++) {
        onChunk(parsed.texts[i]);
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
