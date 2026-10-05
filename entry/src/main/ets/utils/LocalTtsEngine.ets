// ============================================================
// LocalTtsEngine.ets — ★ 0.189.0 本地 TTS 引擎（CoreSpeechKit，免费离线）
// ============================================================
// 用户拍板：火山云端 TTS 取消，只走本地。云端完整配置存档见
// docs/0.165+/0.189.0 本地TTS双引擎方案.md §9（恢复时照抄即可）。
//
// 能力事实（依据本机 SDK @hms.ai.textToSpeech.d.ts，API 26 实读）：
//   - 免费、无额度、纯离线（online:1 = 离线模式，当前唯一支持的模式）
//   - 单次文本 ≤ 10000 字符（超限抛 1002300001）；本引擎仍按 280 字/段
//     切分——沿用原云端流水线段长，任何固件都安全，排队模式下无缝连播
//   - zh-CN 聆小珊女声（person 13，内置免下载）；en-US Laura 美音
//     （person 8，需下载语音包）——英文发音质量不合格时的升级路径
//   - queueMode：0=排队追加（无缝连播）/ 1=抢占（打断当前）
//   - requestId 仅允许字母/数字/中文（d.ts 约束，禁用连字符）
//   - 全设备引擎实例上限 3 个——本应用单例 1 个
//
// 会话模型：一次 speakText = 一个会话。新会话/stop() 顶替旧会话；
// 引擎级 listener 通过 requestId 集合把回调严格限定在当前会话内，
// 旧会话的迟到回调（onError/onComplete）一律忽略，无需调用方管代际号。
// ============================================================

import { textToSpeech } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';

// 分段上限（沿用原云端流水线 280 字/段——远小于 10000 上限）
const LOCAL_TTS_MAX_SEGMENT_LEN = 280;

// 会话回调（stop/新会话顶替后自动失效）
export interface LocalTtsSession {
  onStart?: () => void;                              // 首段开始播报（⏳→🔊）
  onComplete?: () => void;                           // 全部段播报完成
  onError?: (code: number, message: string) => void; // 任一段出错
}

// ★ 0.189.0：长文本分段（自 ChatPage 0.136 云端流水线原样迁入，单一真相源）——
// 按句末标点+换行切句，累积成 ≤maxLen 的段；超长句按逗号类切小片，单片仍超则硬切
export function splitTextForTts(text: string, maxLen: number): string[] {
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
    if (s.length > maxLen) {
      if (seg.length > 0) {
        result.push(seg);
        seg = '';
      }
      const parts = splitLongSentence(s, maxLen);
      for (let j = 0; j < parts.length; j++) {
        result.push(parts[j]);
      }
      continue;
    }
    if (seg.length + s.length > maxLen) {
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
function splitLongSentence(s: string, maxLen: number): string[] {
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

export class LocalTtsEngine {
  private engine: textToSpeech.TextToSpeechEngine | null = null;
  private creating: Promise<boolean> | null = null;
  private seq: number = 0;                 // requestId 序号（实例内唯一）
  private session: LocalTtsSession | null = null;
  private activeIds: Set<string> = new Set<string>(); // 当前会话全部段的 requestId
  private started: boolean = false;        // onStart 是否已触发（每会话一次）
  private lastRequestId: string = '';      // 最后一段的 requestId（判定会话完成）

  // 引擎探测 + 懒创建（单实例；失败返回 false，调用方提示）
  ensureEngine(): Promise<boolean> {
    if (this.engine !== null) {
      return Promise.resolve(true);
    }
    if (!canIUse('SystemCapability.AI.TextToSpeech')) {
      return Promise.resolve(false); // 设备无此系统能力（旧固件）
    }
    if (this.creating !== null) {
      return this.creating; // 创建中——共用同一个 Promise
    }
    // ArkTS 严格模式：Record 字面量被拒（arkts-no-untyped-obj-literals）——程序化构建
    const extra: Record<string, Object> = {};
    extra['style'] = 'interaction-broadcast';
    extra['locate'] = 'CN';
    extra['name'] = 'DagLocalTts';
    const params: textToSpeech.CreateEngineParams = {
      language: 'zh-CN',
      person: 13, // 聆小珊女声（d.ts 推荐 13；0 亦可）
      online: 1,  // 离线模式（当前唯一支持）
      extraParams: extra
    };
    this.creating = textToSpeech.createEngine(params).then((e: textToSpeech.TextToSpeechEngine) => {
      this.engine = e;
      // ArkTS 严格模式：对象字面量须显式类型（arkts-no-untyped-obj-literals）
      const listener: textToSpeech.SpeakListener = {
        onStart: (requestId: string, response: textToSpeech.StartResponse) => {
          if (this.session !== null && this.activeIds.has(requestId) && !this.started) {
            this.started = true; // 每会话只触发一次（首段）
            if (this.session.onStart) {
              this.session.onStart();
            }
          }
        },
        onComplete: (requestId: string, response: textToSpeech.CompleteResponse) => {
          // type 1 = 播放完成（type 0 = 合成完成，忽略）；最后一段播完 = 会话完成
          if (this.session !== null && this.activeIds.has(requestId) &&
            response.type === 1 && requestId === this.lastRequestId) {
            const s = this.session;
            this.clearSession();
            if (s.onComplete) {
              s.onComplete();
            }
          }
        },
        onStop: (requestId: string, response: textToSpeech.StopResponse) => {
          // stop() 确认回调——会话已由发起方清理，无需处理
        },
        onError: (requestId: string, errorCode: number, errorMessage: string) => {
          if (this.session !== null && this.activeIds.has(requestId)) {
            const s = this.session;
            this.clearSession();
            if (s.onError) {
              s.onError(errorCode, errorMessage);
            }
          }
        }
      };
      e.setListener(listener);
      return true;
    }).catch((err: BusinessError) => {
      console.error(`[LocalTts] createEngine failed: ${err.code} ${err.message}`);
      this.creating = null; // 允许下次重试（如语音包下载完成后）
      return false;
    });
    return this.creating;
  }

  // 播报文本（内部自动分段；顶替旧会话）。返回 false = 引擎不可用（调用方提示）。
  async speakText(text: string, session: LocalTtsSession): Promise<boolean> {
    const trimmed = text.trim();
    if (trimmed.length === 0) {
      return false;
    }
    const ok = await this.ensureEngine();
    const engine = this.engine;
    if (!ok || engine === null) {
      return false;
    }
    this.stopInternal(); // 顶替旧会话（清 session + engine.stop() 清残留队列）
    const chunks = splitTextForTts(trimmed, LOCAL_TTS_MAX_SEGMENT_LEN);
    this.session = session;
    this.started = false;
    this.activeIds = new Set<string>();
    for (let i = 0; i < chunks.length; i++) {
      const requestId = `tts${Date.now()}${++this.seq}`; // 仅字母数字（d.ts 约束禁连字符）
      this.activeIds.add(requestId);
      if (i === chunks.length - 1) {
        this.lastRequestId = requestId;
      }
      // ArkTS 严格模式：Record 字面量被拒——程序化构建
      const extra: Record<string, Object> = {};
      extra['queueMode'] = i === 0 ? 1 : 0; // 首段抢占清场，后续排队无缝连播
      extra['speed'] = 1;
      extra['volume'] = 2;
      extra['pitch'] = 1;
      extra['languageContext'] = 'zh-CN';
      extra['audioType'] = 'pcm';
      extra['soundChannel'] = 3;
      extra['playType'] = 1; // 合成+播报（引擎直出，无需 AVPlayer/临时文件）
      // ArkTS 严格模式：对象字面量须显式类型（arkts-no-untyped-obj-literals）
      const speakParams: textToSpeech.SpeakParams = {
        requestId: requestId,
        extraParams: extra
      };
      try {
        engine.speak(chunks[i], speakParams);
      } catch (err) {
        const be = err as BusinessError; // 同步抛错（如文本超限 1002300001）
        this.clearSession();
        if (session.onError) {
          session.onError(be.code, be.message);
        }
        return true; // 引擎在，会话已报错收尾
      }
    }
    return true;
  }

  // 停止当前会话（幂等；同时停合成+播报+清队列）
  stop(): void {
    this.stopInternal();
  }

  private stopInternal(): void {
    this.clearSession();
    if (this.engine !== null) {
      try {
        this.engine.stop();
      } catch (e) {
        // 引擎异常忽略（已不可用）
      }
    }
  }

  private clearSession(): void {
    this.session = null;
    this.activeIds = new Set<string>();
    this.started = false;
    this.lastRequestId = '';
  }
}

// 模块级单例：单词发音（WordSpeaker）与消息朗读（ChatPage）共用——引擎级互斥
export const localTts = new LocalTtsEngine();
