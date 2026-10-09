// ============================================================
// ApiClient.ets — AI 大模型 API 请求客户端
// ============================================================
// 本文件封装了与火山引擎（Volcano）AI 大模型的通信逻辑：
//   - streamChat()：流式对话请求，AI 边生成边返回（SSE 协议）
//   - queryWord()：AI 查词，结果入单词库（★ 0.145；★ 0.155：划词含中文走中译英，美式音标+英文格式）
//   - queryKnowledge()：AI 知识卡片草稿提炼（★ 0.146）
//   - queryKnowledgeFromImage()：AI 知识卡片草稿提炼·多模态版，屏幕圈选截图入知识库（★ 0.152）
//   - synthesizeTTS()：★ 0.189.0 已移除——云端 TTS 取消，发音/朗读改走本地 CoreSpeechKit（LocalTtsEngine.ets）；配置存档见 docs/0.165+/0.189.0 §9
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
import { buffer } from '@kit.ArkTS'; // ★ 0.132：streamChat 字节级 UTF-8 缓冲；★ 0.189.0：util 随 synthesizeTTS 移除
import { ChatMessage, ApiConfig, generateMessageId, connectPhoneticAccent } from '../common/ChatModel'; // ★ 0.185.0：connectPhoneticAccent（音标口音，prompt 生成用）
import { WordQueryResult } from '../common/WordModel'; // ★ 0.145：AI 查词结果结构
import { KnowledgeQueryResult } from '../common/KnowledgeModel'; // ★ 0.146：AI 卡片草稿结果结构
import { KNOWLEDGE_QUERY_PROMPT, KNOWLEDGE_IMAGE_QUERY_PROMPT, KNOWLEDGE_IMAGE_QUERY_PROMPT_NOTE } from '../common/Prompts'; // ★ 0.193.0：卡片提炼 prompt 单一真相源（C 项数字锚定优化）

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

// ★ 0.188.0：零内容流的错误体形状（火山方舟/OpenAI 兼容：顶层 error 或顶层 message）
interface StreamErrorInfo {
  code?: string;
  message?: string;
}
interface StreamErrorBody {
  error?: StreamErrorInfo;
  message?: string;
}

// ★ 0.188.0：从原始响应体预览中提取真实错误。返回空串 = 合法 SSE 且无 error
// （真·空回复，维持 onDone 通用提示）；非空 = 诊断信息（走 onError 展示给用户）。
// 兼容两种载体：纯 JSON 错误体（HTTP 4xx/5xx，无 data: 前缀）与 SSE data: 行内 error。
function extractStreamError(raw: string): string {
  const trimmed = raw.trim();
  if (trimmed.length === 0) {
    return '服务器无响应：连接已建立但未收到任何数据，请检查网络后重试';
  }
  const candidates: string[] = [];
  if (trimmed.includes('data:')) {
    const lines = trimmed.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.startsWith('data:')) {
        candidates.push(line.substring(5).trim());
      }
    }
  } else {
    candidates.push(trimmed);
  }
  for (let i = 0; i < candidates.length; i++) {
    const c = candidates[i];
    if (c.length === 0 || c === '[DONE]' || !c.includes('"error"')) {
      continue;
    }
    try {
      const json = JSON.parse(c) as StreamErrorBody;
      if (json.error && (json.error.message !== undefined || json.error.code !== undefined)) {
        const code = json.error.code !== undefined ? json.error.code : '';
        const message = json.error.message !== undefined ? json.error.message : '';
        return `API 返回错误${code.length > 0 ? `（${code}）` : ''}：${message}`;
      }
      if (json.message !== undefined && json.message.length > 0) {
        return `API 返回错误：${json.message}`;
      }
    } catch (e) {
      // 非 JSON 段——跳过，走原始体预览兜底
    }
  }
  // 非 SSE 原始体（无 data: 前缀）——直接展示预览（可能是网关 HTML/纯文本错误）
  if (!trimmed.includes('data:')) {
    return `API 返回了非流式内容：${trimmed.substring(0, 200)}`;
  }
  return '';
}

// ============================================================
// ★ 0.190.6：错误场景分类（用户批准方案）——原始英文错误 → 中文场景说明 + 建议操作
// + 保留原始错误（用户反馈时可截图快速定位）；兜底场景引导去 ⚙ 设置 → 关于
// ★ 0.191.0：文案对齐设置 Tab 实名「关于」（原「关于与反馈」与 Tab 名不一致，用户指示对齐）
// 0.190.2 的图片关键词检测已合并进本函数（单一真相源）
// ============================================================
export function classifyStreamError(raw: string): string {
  const lower = raw.toLowerCase();
  // 图片不支持（原 0.190.2 逻辑合并）
  if (lower.includes('image') || lower.includes('vision') || raw.includes('图片') || raw.includes('多模态')) {
    return `当前模型可能不支持图片\n💡 建议在 ⚙ 设置中切换标注「多模态（可发图）」的模型\n\n原始错误：${raw}`;
  }
  // 超时（0.190.4 后长回复/思考模型生成久属正常，300s 上限才触发）
  if (lower.includes('timeout') || lower.includes('timed out')) {
    return `请求超时——AI 生成时间过长或网络不稳定\n💡 可点击 🔄 重试；长回复/深度思考模型生成较久属正常\n\n原始错误：${raw}`;
  }
  // 网络断开
  if (lower.includes('connection') || lower.includes('network') || lower.includes('getaddrinfo') ||
    lower.includes('enotfound') || lower.includes('econnrefused') || lower.includes('unreachable')) {
    return `网络连接失败——设备似乎未联网\n💡 请检查 Wi-Fi/移动网络后重试\n\n原始错误：${raw}`;
  }
  // 鉴权失败
  if (lower.includes('401') || lower.includes('unauthorized') || lower.includes('invalid api key') ||
    lower.includes('authentication') || lower.includes('api key')) {
    return `API Key 无效或已过期\n💡 请到 ⚙ 设置检查 API Key（可点「获取 API Key」去官网重新获取）\n\n原始错误：${raw}`;
  }
  // 欠费/余额不足
  if (lower.includes('402') || lower.includes('balance') || lower.includes('arrears') ||
    lower.includes('overdue') || raw.includes('欠费') || raw.includes('余额')) {
    return `账户余额不足或已欠费\n💡 请到对应 AI 平台官网充值后重试\n\n原始错误：${raw}`;
  }
  // 限流
  if (lower.includes('429') || lower.includes('rate limit') || raw.includes('限流') || raw.includes('频繁')) {
    return `请求过于频繁被限流\n💡 请稍等片刻再重试\n\n原始错误：${raw}`;
  }
  // 模型不存在/下线
  if (lower.includes('404') || lower.includes('not found') || lower.includes('not exist') ||
    lower.includes('model_not_exist') || lower.includes('does not exist')) {
    return `模型 ID 不存在或已下线\n💡 请到 ⚙ 设置更换模型\n\n原始错误：${raw}`;
  }
  // 服务器错误
  if (lower.includes('500') || lower.includes('502') || lower.includes('503') || lower.includes('504') ||
    lower.includes('internal') || lower.includes('server error')) {
    return `AI 服务端暂时不可用\n💡 请稍后重试；持续出现可到 ⚙ 设置更换提供商\n\n原始错误：${raw}`;
  }
  // 兜底：未知错误 + 反馈引导（用户要求：兜底场景引导去设置页联系我们）
  return `请求出错（未知原因）\n💡 可重试；如持续出现，请到 ⚙ 设置 → 关于 联系我们（附上下方原始错误截图）\n\n原始错误：${raw}`;
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
  let rawPreview: string = ''; // ★ 0.188.0：原始响应体预览（零内容流诊断真实错误用，截断 600 字符）
  let deliveredAny: boolean = false; // ★ 0.188.0：是否交付过任何内容/思考分片

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
    if (rawPreview.length < 600) { // ★ 0.188.0：留原始体预览（截断防长流撑爆）
      rawPreview += dataStr;
    }
    const parsed = parseSSEChunk(sseBuffer);
    sseBuffer = parsed.remainder;
    if (parsed.texts.length > 0 || parsed.reasonings.length > 0) { // ★ 0.188.0
      deliveredAny = true;
    }
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
      const tail = buffer.from(pendingBytes.buffer, pendingBytes.byteOffset, pendingBytes.byteLength).toString();
      sseBuffer += tail;
      if (rawPreview.length < 600) { // ★ 0.188.0
        rawPreview += tail;
      }
      pendingBytes = new Uint8Array(0);
    }
    // 处理剩余 buffer
    if (sseBuffer.trim().length > 0) {
      const parsed = parseSSEChunk(sseBuffer + '\n');
      if (parsed.texts.length > 0 || parsed.reasonings.length > 0) { // ★ 0.188.0
        deliveredAny = true;
      }
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
    // ★ 0.188.0：零内容流诊断——HTTP 4xx/5xx 的 JSON 错误体（无 data: 前缀）此前被
    // 静默吞掉、统一显示「AI 未返回文本内容」，真实原因（key 失效/模型下线/限流）不可见。
    // 现在零内容时解析原始响应体：含 error 的体 → 提取信息走 onError 展示真实原因；
    // 合法 SSE 且无 error → 维持 onDone（真·空回复，ChatPage 显示通用提示）。
    if (!deliveredAny) {
      const diag = extractStreamError(rawPreview);
      if (diag.length > 0) {
        onError(diag);
        cleanupRequest(httpRequest);
        return;
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
  // ★ 0.190.4：try-catch 兜底——requestInStream 同步异常（如底层会话异常态）此前直接抛出，
  //   调用方 sendMessage 的 isLoading 卡 true → 后续所有发送被 guard 挡死（真机实测
  //   「出错后发送不出去」）；此处统一捕获走 onError，调用方状态机正常恢复
  try {
    httpRequest.requestInStream(config.endpoint, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.apiKey}`
      },
      extraData: JSON.stringify(body),
      connectTimeout: 30000,
      readTimeout: 300000, // ★ 0.190.4：60s→300s——GLM-5.3-Flash 等深度思考不可关闭模型（华为MaaS文档：glm-5.3「深度思考（不可关闭）」）+长回复生成总时长轻松超60s，真机实测长回复模式 Operation timeout；DeepSeek 思考可开关生成快不触发。流式期间数据持续到达，300s 上限只拦真死连接
    }).catch((err: Error) => {
      if (cancelled) {
        return;
      }
      onError(err.message);
      cleanupRequest(httpRequest);
    });
  } catch (e) {
    if (!cancelled) {
      onError(e instanceof Error ? e.message : '请求发起失败');
    }
    cleanupRequest(httpRequest);
  }

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

// ★ 0.185.0：音标口音参数化（原常量改函数）——british=true 输出英式音标，false 美式（默认）。
// 口音来源：connectPhoneticAccent().british（单词库设置弹窗切换，PersistenceV2 持久化）。
function buildWordQueryPrompt(british: boolean): string {
  const accent = british ? '英式' : '美式';
  return `你是英文词典助手。用户会给你一个英文单词或缩写。你只能输出一个 JSON 对象，禁止输出任何其他文字、禁止 markdown 代码块。格式：{"word":"...","fullName":"...","usPhonetic":"...","explain":"..."}。字段规则：word=用户查询的原文；fullName=仅当查询对象是缩写（如 OS、AI、CPU）时返回其英文全称（如 Operating System），普通单词必须返回空字符串；usPhonetic=${accent}音标并用斜杠包裹（缩写时返回全称的音标，普通单词返回该词音标）；explain=简明中文释义（缩写时返回全称的中文释义）。`;
}

// ★ 0.155：检测文本是否含中文字符（CJK 统一表意区 0x4E00-0x9FFF）。
// 划词含中文（纯中文或中英混合）→ 走中译英 prompt；纯英文 → 原英译中 prompt。
// 混合词组无论第一个字符是中文还是英文，输出统一归一为「音标 + 英文词组」（口音随设置），
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
// 输出统一为「音标 + 英文词组」：usPhonetic=整体音标、explain=英文词组
//（浮窗按 音标→英文 顺序展示）；word=英文词组（入单词库的词条名）。
// ★ 0.185.0：音标口音参数化（原常量改函数），与英译中 prompt 同步生效。
function buildWordQueryZhPrompt(british: boolean): string {
  const accent = british ? '英式' : '美式';
  return `你是中英互译词典助手。用户会给你一段划选文本，其中包含中文（可能混有英文单词）。请把其中的中文部分翻译成对应的英文单词，已有的英文部分保持原样，按原顺序组合成英文词组。你只能输出一个 JSON 对象，禁止输出任何其他文字、禁止 markdown 代码块。格式：{"word":"...","fullName":"","usPhonetic":"...","explain":"..."}。字段规则：word=翻译后的完整英文词组；fullName=固定返回空字符串；usPhonetic=整个英文词组的${accent}音标并用斜杠包裹；explain=翻译后的完整英文词组（与 word 相同）。`;
}

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
  // ★ 0.155：划词含中文（纯中文/中英混合）→ 中译英 prompt（音标+英文格式）；
  // 纯英文 → 原英译中 prompt（中文释义格式）
  // ★ 0.185.0：音标口音从单词库设置读取（美式默认/英式），两路 prompt 同步生效
  const british = connectPhoneticAccent().british;
  const prompt = containsChinese(word) ? buildWordQueryZhPrompt(british) : buildWordQueryPrompt(british);
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
// ★ 0.193.0 C 项：迁入 common/Prompts.ts（数字锚定优化——"精简/压缩"违规模糊词改具体字数），本文件 import

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
    // ★ 0.202.1：建议标签（宽松解析——旧模型/失败未返回 tags 时为空数组，不阻断主流程）
    const tags: string[] = Array.isArray(obj['tags'])
      ? (obj['tags'] as Array<Object>).filter((t: Object): boolean => typeof t === 'string')
        .map((t: Object): string => t as string).filter((t: string): boolean => t.trim().length > 0)
      : [];
    const result: KnowledgeQueryResult = {
      title: title,
      definition: definition,
      tags: tags
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
// ★ 0.193.0 C 项：迁入 common/Prompts.ts（数字锚定优化），本文件 import

// ★ 0.184.0：带补充要求的提示词——用户在标注页写明了标题/内容方向时优先遵循：
// 核心素材仍取自图中圈选区域，补充要求只决定组织方向与重点（不虚构图中完全无关的信息）
// ★ 0.193.0 C 项：迁入 common/Prompts.ts，本文件 import

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
// ============================================================
// ★ 0.189.0：火山云端 TTS 已按用户指示整体移除（synthesizeTTS + openspeech 协议接口）。
// 发音/朗读改走本地 CoreSpeechKit 引擎（utils/LocalTtsEngine.ets，免费离线）。
// 云端完整配置存档（端点/鉴权/协议/音色/历史教训）见
// docs/0.165+/0.189.0 本地TTS双引擎方案.md §9——恢复时照抄即可。
// ============================================================

// ★ 0.189.0：synthesizeTTS 函数体已移除（云端 TTS 取消，见上方存档说明）
