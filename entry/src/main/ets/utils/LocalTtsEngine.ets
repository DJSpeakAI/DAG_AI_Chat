// ============================================================
// LocalTtsEngine.ets — ★ 0.189.0 本地 TTS 引擎 / ★ 0.189.1 双引擎口音联动
// ============================================================
// 用户拍板：云端火山 TTS 取消，只走本地（配置存档见 0.189.0 文档 §9）。
//
// ★ 0.189.1 双引擎架构：
//   - zhEngine（zh-CN 聆小珊 person 13，内置免下载）→ 消息朗读（中文内容）
//   - enEngine（en-US Laura person 8，需下载语音包）→ 单词发音（真美式）
//   - 设备引擎实例上限 3 个——本应用 2 个，余量 1
//   - 口音联动（WordSpeaker 驱动）：
//       美式设置 → Laura 已装=直接用；可下载=提示去 ⚙ 下载；无=聆小珊兜底
//       英式设置 → 系统无 en-GB 音色（清单封闭仅 3 个）→ 一次性提示后按现有音色播
//   - 音色清单不写死：listVoices 运行时查询（华为未来上新音色零代码升级）
//
// 能力事实（依据本机 SDK @hms.ai.textToSpeech.d.ts，API 26 实读）：
//   - 免费、无额度、纯离线（online:1 = 离线模式，当前唯一支持）
//   - 单次文本 ≤ 10000 字符；本引擎仍按 280 字/段切分（沿用原云端段长，无缝连播）
//   - queueMode：0=排队追加 / 1=抢占；requestId 仅字母/数字/中文（禁连字符）
//   - listVoices（命名空间级，API 19+）：查询音色 + status（GA=可下载/INSTALLED=已装/EOM=废弃）
//   - downloadVoice（API 19+）：应用内下载语音包，start/progress/complete/cancel/error 回调
//
// 会话模型：一次 speakText = 一个会话。新会话/stop() 顶替旧会话；两引擎的 listener
// 共用同一会话跟踪器（requestId 全局唯一），旧会话迟到回调一律忽略。
// ============================================================

import { textToSpeech } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';

// 分段上限（沿用原云端流水线 280 字/段——远小于 10000 上限）
const LOCAL_TTS_MAX_SEGMENT_LEN = 280;

// en-US Laura 音色状态
export type EnVoiceStatus = 'unknown' | 'installed' | 'downloadable' | 'none';

// 会话回调（stop/新会话顶替后自动失效）
export interface LocalTtsSession {
  onStart?: () => void;                              // 首段开始播报（⏳→🔊）
  onComplete?: () => void;                           // 全部段播报完成
  onError?: (code: number, message: string) => void; // 任一段出错
}

// 语音包下载回调（⚙ 弹窗消费：进度/完成/失败驱动 UI）
export interface VoiceDownloadHooks {
  onStart?: () => void;
  onProgress?: (info: string) => void;               // 系统原始进度信息（尝试解析数字）
  onComplete?: () => void;
  onCancelled?: () => void;
  onError?: (code: number, message: string) => void;
}

// ★ 0.189.0：长文本分段（自 ChatPage 0.136 云端流水线原样迁入，单一真相源）——
// 按句末标点+换行切句，累积成 ≤maxLen 段；超长句按逗号类切小片，单片仍超则硬切
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
  // ★ 0.189.1：双引擎（zh=消息朗读/聆小珊内置；en=单词发音/Laura 需下载）
  private zhEngine: textToSpeech.TextToSpeechEngine | null = null;
  private enEngine: textToSpeech.TextToSpeechEngine | null = null;
  private zhCreating: Promise<boolean> | null = null;
  private enCreating: Promise<boolean> | null = null;

  // en-US Laura 音色信息 + 状态（listVoices 查询缓存；下载完成后刷新）
  private enVoice: textToSpeech.VoiceInfo | null = null;
  private enStatus: EnVoiceStatus = 'unknown';

  private seq: number = 0;                 // requestId 序号（两引擎全局唯一）
  private session: LocalTtsSession | null = null;
  private activeIds: Set<string> = new Set<string>(); // 当前会话全部段的 requestId
  private started: boolean = false;        // onStart 是否已触发（每会话一次）
  private lastRequestId: string = '';      // 最后一段的 requestId（判定会话完成）

  // ★ 0.189.1：查询 en-US Laura 音色状态（命名空间级 listVoices，无需先建引擎；结果缓存）
  async queryEnVoiceStatus(force: boolean = false): Promise<EnVoiceStatus> {
    if (!force && this.enStatus !== 'unknown') {
      return this.enStatus;
    }
    if (!canIUse('SystemCapability.AI.TextToSpeech')) {
      this.enStatus = 'none';
      return this.enStatus;
    }
    const query: textToSpeech.VoiceQuery = {
      requestId: `vq${Date.now()}${++this.seq}`,
      online: 1
    };
    try {
      const voices = await textToSpeech.listVoices(query);
      this.enVoice = null;
      this.enStatus = 'none';
      for (let i = 0; i < voices.length; i++) {
        const v = voices[i];
        // en-US / en_US 归一匹配；Laura = person 8（d.ts 官方英文女声）
        const lang = v.language.replace('_', '-').toLowerCase();
        if (lang === 'en-us' && v.person === 8) {
          this.enVoice = v;
          this.enStatus = v.status === 'INSTALLED' ? 'installed' : 'downloadable';
          break;
        }
      }
    } catch (err) {
      const be = err as BusinessError;
      console.error(`[LocalTts] listVoices failed: ${be.code} ${be.message}`);
      this.enStatus = 'none'; // 查询失败按无处理（聆小珊兜底）
    }
    return this.enStatus;
  }

  // ★ 0.189.1：应用内下载 en-US Laura 语音包（downloadVoice，带进度回调）
  downloadEnVoice(hooks: VoiceDownloadHooks): void {
    if (this.enVoice === null) {
      if (hooks.onError) {
        hooks.onError(1002300009, '未查询到可下载的英文语音包');
      }
      return;
    }
    const dl: textToSpeech.VoiceDownload = {
      requestId: `dl${Date.now()}${++this.seq}`,
      language: this.enVoice.language,
      person: this.enVoice.person,
      style: this.enVoice.style
    };
    textToSpeech.downloadVoice(dl, (err: BusinessError, resp: textToSpeech.DownloadResponse) => {
      if (err) {
        if (err.code === 1002300010) {
          // 已下载过——直接置已装（幂等）
          this.enStatus = 'installed';
          if (hooks.onComplete) {
            hooks.onComplete();
          }
        } else if (hooks.onError) {
          hooks.onError(err.code, err.message);
        }
        return;
      }
      resp.on('start', (info: string) => {
        if (hooks.onStart) {
          hooks.onStart();
        }
      });
      resp.on('progress', (info: string) => {
        if (hooks.onProgress) {
          hooks.onProgress(info);
        }
      });
      resp.on('complete', (voice: textToSpeech.VoiceInfo) => {
        this.enStatus = 'installed';   // 下载完成 → 下次 ensureEnEngine 可建引擎
        this.enCreating = null;
        if (hooks.onComplete) {
          hooks.onComplete();
        }
      });
      resp.on('cancel', (info: string) => {
        if (hooks.onCancelled) {
          hooks.onCancelled();
        }
      });
      resp.on('error', (e: BusinessError) => {
        if (hooks.onError) {
          hooks.onError(e.code, e.message);
        }
      });
    });
  }

  // zh 引擎探测 + 懒创建（聆小珊内置，失败返回 false）
  ensureZhEngine(): Promise<boolean> {
    if (this.zhEngine !== null) {
      return Promise.resolve(true);
    }
    if (!canIUse('SystemCapability.AI.TextToSpeech')) {
      return Promise.resolve(false); // 设备无此系统能力（旧固件）
    }
    if (this.zhCreating !== null) {
      return this.zhCreating; // 创建中——共用同一个 Promise
    }
    // ArkTS 严格模式：Record 字面量被拒（arkts-no-untyped-obj-literals）——程序化构建
    const extra: Record<string, Object> = {};
    extra['style'] = 'interaction-broadcast';
    extra['locate'] = 'CN';
    extra['name'] = 'DagLocalTtsZh';
    const params: textToSpeech.CreateEngineParams = {
      language: 'zh-CN',
      person: 13, // 聆小珊女声（d.ts 推荐 13；0 亦可）
      online: 1,  // 离线模式（当前唯一支持）
      extraParams: extra
    };
    this.zhCreating = textToSpeech.createEngine(params).then((e: textToSpeech.TextToSpeechEngine) => {
      this.zhEngine = e;
      this.bindListener(e);
      return true;
    }).catch((err: BusinessError) => {
      console.error(`[LocalTts] createEngine zh failed: ${err.code} ${err.message}`);
      this.zhCreating = null; // 允许下次重试（如语音包下载完成后）
      return false;
    });
    return this.zhCreating;
  }

  // ★ 0.189.1：en 引擎懒创建（Laura；仅当状态=已安装才建，否则 false 走 zh 兜底）
  ensureEnEngine(): Promise<boolean> {
    if (this.enEngine !== null) {
      return Promise.resolve(true);
    }
    if (this.enStatus !== 'installed') {
      return Promise.resolve(false); // 未安装/未知——不建（WordSpeaker 先查状态再选 lang）
    }
    if (this.enCreating !== null) {
      return this.enCreating;
    }
    const extra: Record<string, Object> = {};
    extra['style'] = 'interaction-broadcast';
    extra['locate'] = 'CN';
    extra['name'] = 'DagLocalTtsEn';
    const params: textToSpeech.CreateEngineParams = {
      language: 'en-US',
      person: 8, // Laura 美式英文女声（需已下载语音包）
      online: 1,
      extraParams: extra
    };
    this.enCreating = textToSpeech.createEngine(params).then((e: textToSpeech.TextToSpeechEngine) => {
      this.enEngine = e;
      this.bindListener(e);
      return true;
    }).catch((err: BusinessError) => {
      console.error(`[LocalTts] createEngine en failed: ${err.code} ${err.message}`);
      this.enCreating = null;
      return false;
    });
    return this.enCreating;
  }

  // 两引擎共用的会话监听器（requestId 全局唯一 → activeIds 跨引擎不串扰）
  private bindListener(e: textToSpeech.TextToSpeechEngine): void {
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
  }

  // 播报文本（内部自动分段；顶替旧会话）。lang：'zh'=消息朗读（聆小珊），
  // 'en'=单词发音（Laura，未装自动回落聆小珊）。返回 false = 引擎不可用（调用方提示）。
  async speakText(text: string, session: LocalTtsSession, lang: string = 'zh'): Promise<boolean> {
    const trimmed = text.trim();
    if (trimmed.length === 0) {
      return false;
    }
    let engine: textToSpeech.TextToSpeechEngine | null = null;
    if (lang === 'en') {
      const enOk = await this.ensureEnEngine();
      if (enOk && this.enEngine !== null) {
        engine = this.enEngine;
      }
    }
    if (engine === null) {
      // zh 直连，或 en 未装回落
      const zhOk = await this.ensureZhEngine();
      if (!zhOk || this.zhEngine === null) {
        return false;
      }
      engine = this.zhEngine;
    }
    this.stopInternal(); // 顶替旧会话（清 session + 双引擎 stop 清残留队列）
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
      extra['languageContext'] = lang === 'en' ? 'en-US' : 'zh-CN';
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

  // 停止当前会话（幂等；同时停两引擎的合成+播报+清队列）
  stop(): void {
    this.stopInternal();
  }

  private stopInternal(): void {
    this.clearSession();
    if (this.zhEngine !== null) {
      try {
        this.zhEngine.stop();
      } catch (e) {
        // 引擎异常忽略（已不可用）
      }
    }
    if (this.enEngine !== null) {
      try {
        this.enEngine.stop();
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
