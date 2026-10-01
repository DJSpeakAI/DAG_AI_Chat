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

import { http } from '@kit.NetworkKit'; // ★ 0.136：webSocket 已随播客路径移除（TTS 回归 HTTP）
import { buffer, util } from '@kit.ArkTS'; // ★ 0.139：util（UUID 生成 + Base64Helper 解码，openspeech 2.0 协议需要）
import { BusinessError } from '@kit.BasicServicesKit'; // ★ 0.136：HTTP 请求异常回调类型
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
    // ★ 0.143 收尾：TTS 调试/过程消息不进入 LLM 上下文（历史对话中持久化保存的调试遗留消息，
    // 构建上下文时跳过，避免污染对话；调试功能已删，此过滤为数据卫生逻辑长期保留）
    if (msg.content.startsWith('[TTS调试]') || msg.content.startsWith('[TTS过程]')) {
      continue;
    }
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

// ============================================================
// ★ 0.139 重写：TTS（文本转语音）— openspeech /api/v3/tts/unidirectional（豆包语音合成 2.0）
// ============================================================
// 0.134/0.137 真机两次 HTTP 404 实锤：模型与端点是绑定的，方舟 ark…/audio/speech
// 端点不服务语音合成模型（docs/0.139，依据用户提供的官方《豆包语音合成大模型 2.0 概览》）。
// 本版采用官方 2.0 协议（openspeech HTTP Chunked 单向流）：
//   - 端点：https://openspeech.bytedance.com/api/v3/tts/unidirectional
//   - 鉴权：X-Api-Key（方舟 Key）+ X-Api-Resource-Id（模型资源 ID）+ X-Api-Request-Id（UUID）
//   - 请求体：{ req_params: { text, speaker, audio_params: { format, sample_rate } } }
//   - 响应：Chunked 流式 JSON，data 字段为 base64 音频片段，code=0 成功
//   - 组合：resource=seed-tts-2.0 + speaker=zh_female_vv_uranus_bigtts（2.0 专用音色）

// TTS 音频参数（openspeech 2.0 协议 audio_params）
interface AudioParams {
  format: string;      // 音频格式：mp3
  sample_rate: number; // 采样率：24000
}

// TTS 请求参数（openspeech 2.0 协议 req_params）
interface ReqParams {
  text: string;      // 待合成文本
  speaker: string;   // 音色 ID（2.0 模型只能用 2.0 音色）
  audio_params: AudioParams;
}

// TTS 请求体（openspeech 2.0 协议）
interface SpeechRequestBody {
  req_params: ReqParams;
}

// 单段 TTS 合成：HTTP POST openspeech /api/v3/tts/unidirectional（0.139 官方 2.0 协议）
// onDone: 成功回调音频 base64（mp3）
// onError: 失败回调（错误信息）
// 返回 StreamController，支持手动 cancel（停止朗读时中断进行中的请求）
export function synthesizeTTS(
  text: string,
  config: ApiConfig,
  onDone: (audioBase64: string) => void,
  onError: (error: string) => void
): StreamController {
  let cancelled = false;

  // 端点兜底：旧版本持久化的方舟/播客端点（0.134-0.137 已证伪）→ 用官方 2.0 端点
  let endpoint = config.audioEndpoint.trim();
  if (endpoint.length === 0 || !endpoint.startsWith('https://')) {
    console.info(`[ApiClient] TTS 端点无效（${endpoint}），使用官方 2.0 端点`);
    endpoint = 'https://openspeech.bytedance.com/api/v3/tts/unidirectional';
  }

  // 音色兜底：空值用 2.0 官方默认音色（2.0 模型只能用 2.0 音色，1.0 音色会报错）
  const voice = config.audioVoice.trim().length > 0 ? config.audioVoice.trim() : 'zh_female_vv_uranus_bigtts';

  // 请求 ID（openspeech 2.0 协议要求每次请求携带唯一 UUID）
  const requestId = util.generateRandomUUID(false);

  // 请求体（openspeech 2.0 协议 req_params 嵌套格式）
  const body: SpeechRequestBody = {
    req_params: {
      text: text,
      speaker: voice,
      audio_params: {
        format: 'mp3',
        sample_rate: 24000
      }
    }
  };

  // ★ 0.140：音频 Key 空值检查——豆包语音 Key 与方舟 Key 相互独立，未填写直接明确报错（不拿空 Key 撞服务器）
  if (config.audioKey.trim().length === 0) {
    const errMsg = '音频 API Key 未填写：请在设置页「音频 API Key」填入豆包语音控制台新建的 Key（与对话 Key 相互独立）';
    console.error(`[ApiClient] TTS ${errMsg}`);
    onError(errMsg);
    return { cancel: () => { cancelled = true; } };
  }

  const httpRequest = http.createHttp();

  httpRequest.request(endpoint, {
    method: http.RequestMethod.POST,
    header: {
      'Content-Type': 'application/json',
      'X-Api-Key': config.audioKey, // ★ 0.140：豆包语音 Key（与方舟对话 Key 相互独立）
      'X-Api-Resource-Id': config.audioModel,
      'X-Api-Request-Id': requestId
    },
    extraData: JSON.stringify(body),
    // 响应是 Chunked 流式 JSON 文本（data 字段 base64），按文本接收
    expectDataType: http.HttpDataType.STRING,
    connectTimeout: 15000,
    readTimeout: 60000
  }).then((resp: http.HttpResponse) => {
    if (cancelled) {
      return;
    }
    httpRequest.destroy();
    const code = resp.responseCode;
    // ★ 0.137 空值保护沿用：错误响应可能无 body（如 404 空 body），resp.result 为 undefined
    const bodyText = resp.result ? (resp.result as string) : '';
    if (code !== 200) {
      // ★ 0.137：body 为空时明确显示「响应体为空」，不显示悬空冒号
      const errMsg = bodyText.length > 0
        ? `HTTP ${code}: ${bodyText.substring(0, 150)}`
        : `HTTP ${code}（响应体为空）`;
      console.error(`[ApiClient] TTS 失败: ${errMsg}`);
      onError(errMsg);
      return;
    }
    // 200：解析 Chunked 流式 JSON——正则提取 code 校验 + 所有 data 字段 base64 片段拼接
    if (bodyText.length === 0) {
      onError('HTTP 200 但响应体为空');
      return;
    }
    try {
      // code 校验：code=0 成功，非 0 为业务错误（提取 message 一并显示）
      const codeMatch = /"code"\s*:\s*(-?\d+)/.exec(bodyText);
      if (codeMatch && parseInt(codeMatch[1], 10) !== 0) {
        const msgMatch = /"message"\s*:\s*"([^"]*)"/.exec(bodyText);
        const bizMsg = msgMatch ? msgMatch[1] : '未知业务错误';
        const errMsg = `业务错误 code=${codeMatch[1]}: ${bizMsg}`;
        console.error(`[ApiClient] TTS 失败: ${errMsg}`);
        onError(errMsg);
        return;
      }
      // 提取所有 data 字段（Chunked 流式返回多段 base64 音频片段）
      const dataReg = /"data"\s*:\s*"([^"]*)"/g;
      const chunks: string[] = [];
      let dataMatch = dataReg.exec(bodyText);
      while (dataMatch !== null) {
        if (dataMatch[1].length > 0) {
          chunks.push(dataMatch[1]);
        }
        dataMatch = dataReg.exec(bodyText);
      }
      if (chunks.length === 0) {
        onError('响应中无 data 音频字段');
        return;
      }
      // 逐段 base64 解码 → ArrayBuffer 拼接 → 整体转 base64
      const helper = new util.Base64Helper();
      const decoded: Uint8Array[] = [];
      let totalLen = 0;
      for (let i = 0; i < chunks.length; i++) {
        const seg = helper.decodeSync(chunks[i]);
        decoded.push(seg);
        totalLen += seg.byteLength;
      }
      const mergedBuf = new ArrayBuffer(totalLen);
      const merged = new Uint8Array(mergedBuf);
      let offset = 0;
      for (let i = 0; i < decoded.length; i++) {
        merged.set(decoded[i], offset);
        offset += decoded[i].byteLength;
      }
      const audioBase64 = buffer.from(mergedBuf).toString('base64');
      onDone(audioBase64);
    } catch (e) {
      onError('响应解析失败');
      return;
    }
  }).catch((err: BusinessError) => {
    if (cancelled) {
      return;
    }
    httpRequest.destroy();
    const errMsg = `请求异常: ${err.message}`;
    console.error(`[ApiClient] TTS ${errMsg}`);
    onError(errMsg);
  });

  // 返回控制器，支持手动 cancel
  const controller: StreamController = {
    cancel: () => {
      cancelled = true;
      try {
        httpRequest.destroy();
      } catch (e) {
        // 已销毁
      }
    }
  };
  return controller;
}
