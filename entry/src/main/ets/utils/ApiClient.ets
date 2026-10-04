// ============================================================
// ApiClient.ets — AI 大模型 API 请求客户端
// ============================================================
// 本文件封装了与火山引擎（Volcano）AI 大模型的通信逻辑：
//   - streamChat()：流式对话请求，AI 边生成边返回（SSE 协议）
//   - queryWord()：AI 查词，结果入单词库（★ 0.145；★ 0.155：划词含中文走中译英，美式音标+英文格式）
//   - queryKnowledge()：AI 知识卡片草稿提炼（★ 0.146）
//   - queryKnowledgeFromImage()：AI 知识卡片草稿提炼·多模态版，屏幕圈选截图入知识库（★ 0.152）
//   - synthesizeTTS()：语音合成，HTTP 分段请求（★ 0.136/0.139）
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
import { ChatMessage, ApiConfig, generateMessageId } from '../common/ChatModel';
import { WordQueryResult } from '../common/WordModel'; // ★ 0.145：AI 查词结果结构
import { KnowledgeQueryResult } from '../common/KnowledgeModel'; // ★ 0.146：AI 卡片草稿结果结构

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
// ★ 0.160 bugfix: role mapping is three-way — user→user, system→system, rest→assistant.
// Previously every non-user role was coerced to 'assistant', so injected system prompts
// (history summary / reply-length / preference / podcast) were sent as assistant turns;
// models treat a trailing assistant message as their own unfinished reply and continue
// it verbatim, leaking prompt text into chat answers.
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
        // ★ 0.160 bugfix: system role must pass through as 'system' — mapping it to
        // 'assistant' made trailing injected prompts (length/preference/podcast/summary)
        // look like the model's own unfinished reply, which the model would continue
        // verbatim (prompt leakage into chat answers)
        role: msg.role === 'user' ? 'user' : (msg.role === 'system' ? 'system' : 'assistant'),
        content: parts
      };
      result.push(m);
    } else {
      // 纯文本：content 为 string
      const m: VolcanoMessage = {
        // ★ 0.160 bugfix: same three-way mapping as the multimodal branch above
        role: msg.role === 'user' ? 'user' : (msg.role === 'system' ? 'system' : 'assistant'),
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
    // 追加到累积 buffer 并解析 SSE 事件
    sseBuffer += dataStr;
    const parsed = parseSSEChunk(sseBuffer);
    sseBuffer = parsed.remainder;
    // 逐个回调文本分片
    for (let i = 0; i < parsed.texts.length; i++) {
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

  // 流式结束回调
  httpRequest.on('dataEnd', () => {
    if (cancelled) {
      return;
    }
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

  // 发起流式请求
  httpRequest.requestInStream(config.endpoint, {
    method: http.RequestMethod.POST,
    header: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${config.apiKey}`
    },
    extraData: JSON.stringify(body),
    connectTimeout: 30000,
    readTimeout: 60000,
  }).catch((err: Error) => {
    if (cancelled) {
      return;
    }
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
// ★ 0.145：AI 查词（Word Lookup）— 划词翻译浮窗数据源
// ============================================================
// Reuses streamChat to accumulate the full reply, then parses a strict
// JSON payload. The prompt forces:
//   - abbreviations (OS / AI / CPU ...): fullName = English full term,
//     usPhonetic/explain describe the FULL term
//   - normal words: fullName = "" (empty string, never a placeholder)
// The result feeds the translate popup and can be added to the word
// bank. It never creates chat bubbles and never enters the DAG context.

// System prompt for word lookup (strict JSON, no markdown wrapper)
const WORD_QUERY_PROMPT = '你是英文词典助手。用户会给你一个英文单词或缩写。你只能输出一个 JSON 对象，禁止输出任何其他文字、禁止 markdown 代码块。格式：{"word":"...","fullName":"...","usPhonetic":"...","explain":"..."}。字段规则：word=用户查询的原文；fullName=仅当查询对象是缩写（如 OS、AI、CPU）时返回其英文全称（如 Operating System），普通单词必须返回空字符串；usPhonetic=美式音标并用斜杠包裹（缩写时返回全称的音标，普通单词返回该词音标）；explain=简明中文释义（缩写时返回全称的中文释义）。';

// ★ 0.155：检测文本是否含中文字符（CJK 统一表意区 0x4E00-0x9FFF）。
// 划词含中文（纯中文或中英混合）→ 走中译英 prompt；纯英文 → 原英译中 prompt。
// 混合词组无论第一个字符是中文还是英文，输出统一归一为「美式音标 + 英文词组」，
// 与用户规则「以第一个字符为准」在结果上等价（两种方向最终都输出英文词组）。
export function containsChinese(text: string): boolean {
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code >= 0x4E00 && code <= 0x9FFF) {
      return true;
    }
  }
  return false;
}

// ★ 0.155：中译英查词 prompt——划词含中文时使用。
// 中文部分译成对应英文单词、已有英文保持原样、按原词序组合成英文词组；
// 输出统一为「美式音标 + 英文词组」：usPhonetic=整体音标、explain=英文词组
//（浮窗按 音标→英文 顺序展示）；word=英文词组（入单词库的词条名）。
const WORD_QUERY_ZH_PROMPT = '你是中英互译词典助手。用户会给你一段划选文本，其中包含中文（可能混有英文单词）。请把其中的中文部分翻译成对应的英文单词，已有的英文部分保持原样，按原顺序组合成英文词组。你只能输出一个 JSON 对象，禁止输出任何其他文字、禁止 markdown 代码块。格式：{"word":"...","fullName":"","usPhonetic":"...","explain":"..."}。字段规则：word=翻译后的完整英文词组；fullName=固定返回空字符串；usPhonetic=整个英文词组的美式音标并用斜杠包裹；explain=翻译后的完整英文词组（与 word 相同）。';

// Parse the raw AI reply into a WordQueryResult.
// Extracts the first '{' to the last '}' so a stray markdown fence or
// extra prose around the JSON does not break parsing. Returns null when
// no parsable object exists.
function parseWordQueryResult(raw: string, fallbackWord: string): WordQueryResult | null {
  const start = raw.indexOf('{');
  const end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return null;
  }
  try {
    const obj = JSON.parse(raw.substring(start, end + 1)) as Record<string, Object>;
    const word = typeof obj['word'] === 'string' ? obj['word'] as string : fallbackWord;
    const fullName = typeof obj['fullName'] === 'string' ? obj['fullName'] as string : '';
    const usPhonetic = typeof obj['usPhonetic'] === 'string' ? obj['usPhonetic'] as string : '';
    const explain = typeof obj['explain'] === 'string' ? obj['explain'] as string : '';
    // Both phonetic and explanation missing → treat as unparsable
    if (usPhonetic.length === 0 && explain.length === 0) {
      return null;
    }
    const result: WordQueryResult = {
      word: word,
      fullName: fullName,
      usPhonetic: usPhonetic,
      explain: explain
    };
    return result;
  } catch (e) {
    return null;
  }
}

// AI word lookup: stream request whose chunks are accumulated silently
// and parsed once on completion. Independent from chat bubbles / DAG.
export function queryWord(
  word: string,
  config: ApiConfig,
  onDone: (result: WordQueryResult) => void,
  onError: (error: string) => void
): StreamController {
  // ★ 0.155：划词含中文（纯中文/中英混合）→ 中译英 prompt（美式音标+英文格式）；
  // 纯英文 → 原英译中 prompt（中文释义格式）
  const prompt = containsChinese(word) ? WORD_QUERY_ZH_PROMPT : WORD_QUERY_PROMPT;
  const messages: ChatMessage[] = [
    new ChatMessage(generateMessageId(), 'system', prompt),
    new ChatMessage(generateMessageId(), 'user', word)
  ];
  let full = '';
  return streamChat(
    messages,
    config,
    (chunk: string) => { full += chunk; }, // accumulate silently — no typewriter UI for lookup
    () => {
      const result = parseWordQueryResult(full, word);
      if (result !== null) {
        onDone(result);
      } else {
        onError('AI 返回内容无法解析为词条，请重试');
      }
    },
    onError
  );
}

// ============================================================
// ★ 0.146：知识库卡片草稿（AI 提炼）— queryKnowledge
// ============================================================
// Flow: user selects text in a bubble → taps "入知识库" in the selection
// toolbar → the selected text goes to the AI with a strict prompt → the
// AI returns {"title","definition"} → the card editor pre-fills both
// fields. The AI output is a DRAFT only — nothing is saved to the bank
// until the user confirms in the editor. It never creates chat bubbles
// and never enters the DAG context.

// System prompt for card drafting (strict JSON, no markdown wrapper).
// Hard constraint: the AI may ONLY distill from the selected source text.
const KNOWLEDGE_QUERY_PROMPT = '你是卡片提炼助手，仅基于用户提供的原文生成知识库卡片。规则：1. 只使用原文信息，严禁增加原文不存在的内容、例子、拓展解释；2. title填写术语/概念名称；definition写精简核心定义，压缩文字；3. 输出严格JSON，不要任何额外文字、注释、markdown，只返回json字符串，格式：{"title":"...","definition":"..."}。';

// Parse the raw AI reply into a KnowledgeQueryResult.
// Extracts the first '{' to the last '}' so a stray markdown fence or
// extra prose around the JSON does not break parsing. Returns null when
// no parsable object exists.
function parseKnowledgeQueryResult(raw: string): KnowledgeQueryResult | null {
  const start = raw.indexOf('{');
  const end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return null;
  }
  try {
    const obj = JSON.parse(raw.substring(start, end + 1)) as Record<string, Object>;
    const title = typeof obj['title'] === 'string' ? obj['title'] as string : '';
    const definition = typeof obj['definition'] === 'string' ? obj['definition'] as string : '';
    // Both fields missing → treat as unparsable
    if (title.length === 0 && definition.length === 0) {
      return null;
    }
    const result: KnowledgeQueryResult = {
      title: title,
      definition: definition
    };
    return result;
  } catch (e) {
    return null;
  }
}

// ★ 0.153：增量提取流式 JSON 字段值——AI 输出 {"title":"...","definition":"..."} 流到一半时，
// 从累积文本中提取已到达的字段内容实时上屏（处理 \" \\ \n 转义；字段未开始返回 ''）
function extractPartialField(raw: string, field: string): string {
  const key = `"${field}"`;
  const idx = raw.indexOf(key);
  if (idx < 0) {
    return '';
  }
  let i = idx + key.length;
  while (i < raw.length && (raw[i] === ' ' || raw[i] === ':')) {
    i++;
  }
  if (i < raw.length && raw[i] === '"') {
    i++;
  }
  let result = '';
  while (i < raw.length) {
    const ch = raw[i];
    if (ch === '\\') {
      if (i + 1 >= raw.length) {
        break; // 转义字符被 chunk 切断，等下个 chunk 拼齐再提取
      }
      const next = raw[i + 1];
      result += next === 'n' ? '\n' : next;
      i += 2;
      continue;
    }
    if (ch === '"') {
      break; // 字段值闭合，提取完成
    }
    result += ch;
    i++;
  }
  return result;
}

// ★ 0.153：解析方舟 API 错误体 {"error":{"message":"..."}}——返回简要错误信息；非错误体返回 null
function parseApiErrorMessage(raw: string): string | null {
  const start = raw.indexOf('{');
  const end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return null;
  }
  try {
    const obj = JSON.parse(raw.substring(start, end + 1)) as Record<string, Object>;
    const errObj = obj['error'];
    if (typeof errObj === 'object' && errObj !== null) {
      const msg = (errObj as Record<string, Object>)['message'];
      if (typeof msg === 'string' && msg.length > 0) {
        return msg.substring(0, 120); // 简要错误信息（截断防刷屏）
      }
    }
  } catch (e) {
    return null; // 非 JSON 内容走「本地处理异常」分类
  }
  return null;
}

// AI card draft: stream request whose chunks are accumulated silently
// and parsed once on completion. Independent from chat bubbles / DAG.
export function queryKnowledge(
  text: string,
  config: ApiConfig,
  onDone: (result: KnowledgeQueryResult) => void,
  onError: (error: string) => void,
  onPartial?: (title: string, definition: string) => void // ★ 0.153：流式实时填充弹窗输入框
): StreamController {
  const messages: ChatMessage[] = [
    new ChatMessage(generateMessageId(), 'system', KNOWLEDGE_QUERY_PROMPT),
    new ChatMessage(generateMessageId(), 'user', text)
  ];
  let full = '';
  return streamChat(
    messages,
    config,
    (chunk: string) => {
      full += chunk;
      // ★ 0.153：每个 chunk 后增量提取已到内容，实时填充弹窗输入框
      if (onPartial !== undefined) {
        onPartial(extractPartialField(full, 'title'), extractPartialField(full, 'definition'));
      }
    },
    () => {
      const result = parseKnowledgeQueryResult(full);
      if (result !== null) {
        onDone(result);
        return;
      }
      // ★ 0.153：检测方舟错误体（{"error":{"message":"..."}}）→ 归类「AI服务返回错误」
      const apiErr = parseApiErrorMessage(full);
      if (apiErr !== null) {
        onError(`AI服务错误：${apiErr}`);
        return;
      }
      onError('AI 返回内容无法解析为卡片，请重试');
    },
    onError
  );
}

// ============================================================
// ★ 0.152：屏幕圈选 → 知识库卡片草稿（多模态版）— queryKnowledgeFromImage
// ============================================================
// Flow: user annotates a screenshot in AnnotationPage → taps "存入知识库"
// → the annotated image (base64 data URI) goes to the vision-capable chat
// model with a strict prompt → the AI reads the circled region and returns
// {"title","definition"} → the card editor pre-fills both fields. Same
// contract as queryKnowledge: the AI output is a DRAFT only, nothing is
// saved until the user confirms in the editor; it never creates chat
// bubbles and never enters the DAG context.

// System prompt for image-based card drafting (strict JSON, no markdown).
// Hard constraint: the AI may ONLY distill from what is visible in the
// image, focusing on the region the user circled/highlighted.
const KNOWLEDGE_IMAGE_QUERY_PROMPT = '你是卡片提炼助手，用户会提供一张带画笔圈选标注的屏幕截图。请识别图中被圈选或标注区域的核心内容，仅基于图中可见信息生成知识库卡片。规则：1. 只使用图中可见的内容，严禁增加图中不存在的信息、例子或拓展解释；2. title填写图中核心术语或概念名称；definition写精简核心定义，压缩文字；3. 输出严格JSON，不要任何额外文字、注释、markdown，只返回json字符串，格式：{"title":"...","definition":"..."}。';

// ★ 0.184.0：带补充要求的提示词——用户在标注页写明了标题/内容方向时优先遵循：
// 核心素材仍取自图中圈选区域，补充要求只决定组织方向与重点（不虚构图中完全无关的信息）
const KNOWLEDGE_IMAGE_QUERY_PROMPT_NOTE = '你是卡片提炼助手，用户会提供一张带画笔圈选标注的屏幕截图，并附有补充要求。请识别图中被圈选或标注区域的核心内容，以图中可见信息为核心素材，并优先遵循用户补充要求组织卡片：用户指定了标题就按其指定填写，用户指定了内容方向就围绕该方向展开definition。规则：1. 核心素材须来自图中可见内容，补充要求仅用于确定标题与组织方向，严禁虚构图中完全无关的信息；2. title填写用户指定的标题或图中核心术语；definition精简核心内容，压缩文字；3. 输出严格JSON，不要任何额外文字、注释、markdown，只返回json字符串，格式：{"title":"...","definition":"..."}。';

// AI card draft from an annotated image: multimodal stream request (user
// message carries the image). Reuses parseKnowledgeQueryResult — the JSON
// contract is identical to the text-based queryKnowledge.
// ★ 0.184.0 note: the user's supplementary requirement from the annotation
//   page. Non-empty → image + note are sent together and the note-steering
//   prompt is used; empty → the original image-only behaviour is unchanged.
export function queryKnowledgeFromImage(
  imageUri: string,
  note: string,
  config: ApiConfig,
  onDone: (result: KnowledgeQueryResult) => void,
  onError: (error: string) => void,
  onPartial?: (title: string, definition: string) => void // ★ 0.153：流式实时填充弹窗输入框
): StreamController {
  const hasNote = note.trim().length > 0;
  const messages: ChatMessage[] = [
    new ChatMessage(generateMessageId(), 'system', hasNote ? KNOWLEDGE_IMAGE_QUERY_PROMPT_NOTE : KNOWLEDGE_IMAGE_QUERY_PROMPT),
    // ★ 0.152：图片走 imageUrl 数组（streamChat 多模态链路，与相册图片消息同机制）
    new ChatMessage(generateMessageId(), 'user', hasNote
      ? `请提取图中圈选标注区域的内容，生成知识库卡片。我的补充要求：${note.trim()}`
      : '请提取图中圈选标注区域的内容，生成知识库卡片', [imageUri])
  ];
  let full = '';
  return streamChat(
    messages,
    config,
    (chunk: string) => {
      full += chunk;
      // ★ 0.153：每个 chunk 后增量提取已到内容，实时填充弹窗输入框
      if (onPartial !== undefined) {
        onPartial(extractPartialField(full, 'title'), extractPartialField(full, 'definition'));
      }
    },
    () => {
      const result = parseKnowledgeQueryResult(full);
      if (result !== null) {
        onDone(result);
        return;
      }
      // ★ 0.153：检测方舟错误体（{"error":{"message":"..."}}）→ 归类「AI服务返回错误」
      const apiErr = parseApiErrorMessage(full);
      if (apiErr !== null) {
        onError(`AI服务错误：${apiErr}`);
        return;
      }
      onError('AI 无法从图片中解析出卡片内容，请重试');
    },
    onError
  );
}

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
