// ============================================================
// QianwenTtsEngine.ets — ★ 0.236.0 千问 TTS 引擎（百炼 CosyVoice 复刻音色）
// ============================================================
// 背景：用户重度 TTS 需求，千问 AI 平台（maas.qianwenaiapi.com，DashScope 兼容中转）购得
//   sk-ws- 业务空间 Key，并在平台复刻了 cosyvoice-v3.5-plus 音色。
//
// ★ 协议以 2026-10-14 全量 curl 实测为准（交接文档给的端点/参数被实测推翻）：
//   1. 中转域名 maas.qianwenaiapi.com 对 TTS 合成全路径 url error / WS 吞帧——不可用；
//      sk-ws- Key 实测直通百炼官方域名 dashscope.aliyuncs.com（同一复刻音色池）。
//   2. 端点：POST /api/v1/services/audio/tts/SpeechSynthesizer（HTTP 同步，用户拍板不做 WS）
//   3. 参数全在 input 内：text/voice/volume(0-100)/rate(0.5-2.0)/instruction（情感=自然语言
//      指令，无 emotion 枚举字段）；parameters.format='mp3' 生效（URL 后缀实证）。
//   4. 响应 JSON：output.audio.url = OSS mp3 下载链接（有 expires_at 有效期）→ GET 下载音频字节。
//   5. 音色错误形态：HTTP 400 code=InvalidParameter message 含 "Engine return error code: 418"
//      （cosyvoice-v3.5-plus 无系统音色——voice 必须是复刻 voice_id，longxiaochun 等官方音色同报 418）。
//   6. 连发 3 段无限流；401=Key 无效。
//
// 骨架对齐 CloudTtsEngine（0.232.0）：分段 280 字串行合成 + base64 缓存 + AVPlayer fd://
//   顺序播放 + generation 代际号 stop 幂等 + session 回调 onStart/onComplete/onError +
//   未配置返回 false 由调用方（ChatPage）直落本地 LocalTtsEngine。
//
// 情感回退（仿火山音色回退）：带 instruction 报错（418 之外的参数错）→ 去 instruction
//   整会话重试一次；418 音色错误不重试直接报友好中文。
// ============================================================

import { http } from '@kit.NetworkKit';
import { buffer, util } from '@kit.ArkTS';
import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { connectApiConfig } from '../common/ChatModel';
import { splitTextForTts } from './LocalTtsEngine';
import { StreamController } from './ApiClient';

// 分段上限（与火山引擎同源 280 字/段——百炼单段请求长度安全线）
const QWEN_TTS_MAX_SEGMENT_LEN = 280;

// 百炼官方域名常量（2026-10-14 实测 sk-ws- Key 直通；中转域名 TTS 全废不用）
const QWEN_TTS_ENDPOINT = 'https://dashscope.aliyuncs.com/api/v1/services/audio/tts/SpeechSynthesizer';
const QWEN_VOICE_LIST_ENDPOINT = 'https://dashscope.aliyuncs.com/api/v1/services/audio/tts/customization';

// 模型默认值（空值兜底）
const QWEN_TTS_DEFAULT_MODEL = 'cosyvoice-v3.5-plus';

// 会话回调（与 CloudTtsSession 同构——ChatPage 统一驱动喇叭三态与本地回退）
export interface QianwenTtsSession {
  onStart?: () => void;
  onComplete?: () => void;
  onError?: (message: string) => void;
  onSynthesized?: (chars: number, cached: boolean) => void; // ★ 0.279.0：SP 计费点（chars=全文清洗后字符数；cached=true 命中缓存零计费）
}

// 请求体（ArkTS 严格模式接口显式类型；实测形态：参数全在 input 内）
interface QwenTtsInput {
  text: string;
  voice: string;
  volume: number;
  rate: number;
  instruction?: string;
}

interface QwenTtsParameters {
  format: string;
}

interface QwenTtsRequestBody {
  model: string;
  input: QwenTtsInput;
  parameters: QwenTtsParameters;
}

// 响应体（output.audio.url → GET 下载 mp3）
interface QwenTtsRespAudio {
  url: string;
  id: string;
}

interface QwenTtsRespOutput {
  audio: QwenTtsRespAudio;
  finish_reason: string;
}

interface QwenTtsRespBody {
  output: QwenTtsRespOutput;
  request_id: string;
}

// 情感档位 → 百炼 instruction 自然语言指令（'默认'=不带指令；2026-10-14 实测 instruction 200 通过）
export function qwenEmotionToInstruction(emotion: string): string {
  if (emotion === '开心') {
    return '用开心愉悦的语气说';
  }
  if (emotion === '中立') {
    return '用平稳中立的语气说';
  }
  if (emotion === '生气') {
    return '用生气的语气说';
  }
  if (emotion === '悲伤') {
    return '用悲伤的语气说';
  }
  if (emotion === '惊讶') {
    return '用惊讶的语气说';
  }
  return ''; // '默认'及其余值：不带 instruction
}

// 拉取复刻音色列表（GSD 音色下拉用）——POST customization list_voice，
// 只返回 status=OK 的音色；失败抛中文错误信息
export interface QwenVoiceItem {
  voiceId: string;
  targetModel: string;
}

interface VoiceListEntry {
  voice_id: string;
  target_model: string;
  status: string;
}

interface VoiceListOutput {
  voice_list: VoiceListEntry[];
}

interface VoiceListBody {
  output: VoiceListOutput;
}

// 音色列表请求体（ArkTS 严格模式——对象字面量须有显式类型）
interface VoiceListReqInput {
  action: string;
  prefix: string;
}

interface VoiceListReqBody {
  model: string;
  input: VoiceListReqInput;
}

export async function fetchQwenVoiceList(apiKey: string): Promise<QwenVoiceItem[]> {
  return new Promise<QwenVoiceItem[]>((resolve, reject) => {
    const req = http.createHttp();
    const listBody: VoiceListReqBody = {
      model: 'voice-enrollment',
      input: { action: 'list_voice', prefix: '' }
    };
    req.request(QWEN_VOICE_LIST_ENDPOINT, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`
      },
      extraData: JSON.stringify(listBody),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 30000
    }).then((resp: http.HttpResponse) => {
      req.destroy();
      const code = resp.responseCode;
      const bodyText = resp.result ? (resp.result as string) : '';
      if (code !== 200) {
        if (code === 401) {
          reject('API Key 无效');
        } else {
          reject(`拉取失败（HTTP ${code}）`);
        }
        return;
      }
      try {
        const parsed = JSON.parse(bodyText) as VoiceListBody;
        const list: QwenVoiceItem[] = [];
        const entries = parsed.output.voice_list;
        for (let i = 0; i < entries.length; i++) {
          if (entries[i].status === 'OK') {
            list.push({ voiceId: entries[i].voice_id, targetModel: entries[i].target_model });
          }
        }
        resolve(list);
      } catch (_e) {
        reject('音色列表解析失败');
      }
    }).catch((err: BusinessError) => {
      req.destroy();
      reject(`网络异常：${err.message}`);
    });
  });
}

export class QianwenTtsEngine {
  private segments: string[] = [];
  private requestIndex: number = 0;
  private playIndex: number = 0;
  private audioCache: string[] = [];
  private waitingForAudio: boolean = false;
  private currentFd: number = -1;
  private currentPath: string = '';
  private requestController: StreamController | null = null;
  private generation: number = 0;
  private avPlayer: media.AVPlayer | null = null;
  private session: QianwenTtsSession | null = null;
  private cacheDir: string = '';
  private dropInstruction: boolean = false; // ★ 情感回退会话缓存（true=本会话去 instruction 重试已发生）
  private started: boolean = false;

  // ★ 三引擎物理互斥（用户铁律）：只有 ttsProvider='qianwen' 才算已配置；
  //   cosyvoice-v3.5-plus 无系统音色（418 实测）——audioVoice（复刻 voice_id）必填
  configured(): boolean {
    const c = connectApiConfig();
    return c.ttsProvider === 'qianwen' && c.audioKey.trim().length > 0 && c.audioVoice.trim().length > 0;
  }

  // 发起朗读会话（读持久化配置）。返回 false = 未配置（调用方直落本地引擎）
  speak(text: string, cacheDir: string, session: QianwenTtsSession): boolean {
    const c = connectApiConfig();
    if (c.ttsProvider !== 'qianwen') {
      return false; // 三引擎互斥：非千问档绝不发千问请求
    }
    const voice = c.audioVoice.trim();
    if (c.audioKey.trim().length === 0 || voice.length === 0) {
      return false;
    }
    const model = c.audioModel.trim().length > 0 ? c.audioModel.trim() : QWEN_TTS_DEFAULT_MODEL;
    return this.speakWithParams(text, c.audioKey.trim(), model, voice,
      c.ttsEmotion, c.ttsSpeed, c.ttsVolume, cacheDir, session);
  }

  // ★ 显式传参合成（GSD 试听用——表单未保存的编辑值直接验证；千问档独有能力）
  speakWithParams(
    text: string,
    apiKey: string,
    model: string,
    voice: string,
    emotion: string,
    speed: number,
    volume: number,
    cacheDir: string,
    session: QianwenTtsSession
  ): boolean {
    if (apiKey.length === 0 || voice.length === 0) {
      return false;
    }
    const trimmed = text.trim();
    if (trimmed.length === 0) {
      return false;
    }
    this.stop(); // 顶替旧会话
    this.session = session;
    this.cacheDir = cacheDir;
    this.presetKey = apiKey;
    this.presetModel = model.length > 0 ? model : QWEN_TTS_DEFAULT_MODEL;
    this.presetVoice = voice;
    this.presetEmotion = emotion;
    this.presetSpeed = speed;
    this.presetVolume = volume;
    this.segments = splitTextForTts(trimmed, QWEN_TTS_MAX_SEGMENT_LEN);
    if (this.segments.length === 0) {
      return false;
    }
    this.requestIndex = 0;
    this.playIndex = 0;
    this.audioCache = [];
    this.waitingForAudio = true;
    this.dropInstruction = false;
    this.started = false;
    // ★ 0.256.1：播报结果缓存命中——同文本+同配置再次点击喇叭=直接重播已合成音频，
    //   零请求零计费（value=段数组：各段独立 base64，串接会因 padding 错位——按段播放原管线）
    const cacheKey = `qwen|${this.presetKey}|${this.presetModel}|${this.presetVoice}|${this.presetEmotion}|${this.presetSpeed}|${this.presetVolume}|${trimmed}`;
    const hit = this.resultCache.get(cacheKey);
    if (hit !== undefined) {
      this.resultCache.delete(cacheKey);
      this.resultCache.set(cacheKey, hit); // LRU touch
      this.pendingCacheKey = '';
      this.segments = [trimmed];
      this.audioCache = hit.slice();
      this.requestIndex = 1; // 全部「已合成」
      this.playIndex = 0;
      this.waitingForAudio = true;
      this.started = false;
      // ★ 0.279.0：缓存命中重播——零请求零计费（调用方按 cached=true 免扣）
      if (this.session !== null && this.session.onSynthesized !== undefined && this.session.onSynthesized !== null) {
        this.session.onSynthesized(trimmed.length, true);
      }
      this.tryPlayNextAudio();
      return true;
    }
    this.pendingCacheKey = cacheKey;
    this.requestNextSegment();
    return true;
  }

  // ★ 0.256.1：播报结果缓存（key=引擎+配置+全文；value=各段 base64 数组；LRU 上限 20 条）
  private static readonly RESULT_CACHE_MAX = 20;
  private resultCache: Map<string, string[]> = new Map();
  private pendingCacheKey: string = '';

  // 结果缓存写入（全部段合成完成时调用；命中重播/回退重试路径由 pendingCacheKey 空值自然跳过）
  private saveResultCache(): void {
    const key = this.pendingCacheKey;
    if (key.length === 0) {
      return;
    }
    // ★ 0.279.0：完整合成走完（与写缓存同点同口径——中断/失败不写缓存也不计费）——
    //   触发调用方 SP 实扣（chars=全部段字符总和）
    if (this.session !== null && this.session.onSynthesized !== undefined && this.session.onSynthesized !== null) {
      let total = 0;
      this.segments.forEach((seg: string): void => {
        total += seg.length;
      });
      this.session.onSynthesized(total, false);
    }
    this.pendingCacheKey = '';
    this.resultCache.delete(key);
    this.resultCache.set(key, this.audioCache.slice());
    if (this.resultCache.size > QianwenTtsEngine.RESULT_CACHE_MAX) {
      let oldestKey = '';
      this.resultCache.forEach((_v: string[], k: string): void => {
        if (oldestKey.length === 0) {
          oldestKey = k; // Map 迭代序=插入序，首个即最旧
        }
      });
      if (oldestKey.length > 0) {
        this.resultCache.delete(oldestKey);
      }
    }
  }

  // 会话级显式参数（speakWithParams 写入；speak 由配置换算后同样走该通道，保持单一合成管线）
  private presetKey: string = '';
  private presetModel: string = QWEN_TTS_DEFAULT_MODEL;
  private presetVoice: string = '';
  private presetEmotion: string = '默认';
  private presetSpeed: number = 1.0;
  private presetVolume: number = 50;

  // 停止整个会话（幂等）：代际号失效 + 取消在飞请求 + 释放播放器/临时文件 + 清队列
  stop(): void {
    this.generation++;
    if (this.requestController !== null) {
      this.requestController.cancel();
      this.requestController = null;
    }
    this.cleanupSegment();
    this.segments = [];
    this.requestIndex = 0;
    this.playIndex = 0;
    this.audioCache = [];
    this.waitingForAudio = false;
    this.session = null;
    this.started = false;
  }

  // 请求下一段（串行：上一段回调后才发下一段）
  private requestNextSegment(): void {
    if (this.requestIndex >= this.segments.length) {
      this.requestController = null; // 全部发出
      return;
    }
    const gen = this.generation;
    const index = this.requestIndex;
    this.requestIndex++;
    const instruction = this.dropInstruction ? '' : qwenEmotionToInstruction(this.presetEmotion);
    this.requestController = this.synthesizeSegment(
      this.segments[index], instruction,
      (audioBase64: string): void => {
        if (gen !== this.generation) {
          return; // 会话已停止/被取代
        }
        this.audioCache.push(audioBase64);
        if (this.waitingForAudio) {
          this.tryPlayNextAudio();
        }
        this.requestNextSegment();
      },
      (err: string, kind: number): void => {
        if (gen !== this.generation) {
          return;
        }
        // ★ 情感回退：带 instruction 的参数类报错（kind=1）→ 去 instruction 整会话重试一次
        if (kind === 1 && !this.dropInstruction && instruction.length > 0) {
          this.dropInstruction = true;
          this.requestIndex = 0;
          this.playIndex = 0;
          this.audioCache = [];
          this.waitingForAudio = true;
          this.cleanupSegment();
          this.requestNextSegment();
          return;
        }
        const s = this.session;
        this.stop();
        if (s !== null && s.onError !== null && s.onError !== undefined) {
          s.onError(err);
        }
      }
    );
  }

  // 单段合成：POST SpeechSynthesizer（JSON）→ output.audio.url → GET 下载 mp3 → base64
  // kind：0=不可重试错误（音色/Key/网络） 1=参数类错误（情感回退候选）
  private synthesizeSegment(
    text: string,
    instruction: string,
    onDone: (audioBase64: string) => void,
    onError: (err: string, kind: number) => void
  ): StreamController {
    let cancelled = false;
    let synthReq: http.HttpRequest | null = null;
    let downloadReq: http.HttpRequest | null = null;
    const destroyAll = (): void => {
      try {
        if (synthReq !== null) {
          synthReq.destroy();
        }
      } catch (_e) {
        // 已销毁
      }
      try {
        if (downloadReq !== null) {
          downloadReq.destroy();
        }
      } catch (_e) {
        // 已销毁
      }
    };

    const input: QwenTtsInput = {
      text: text,
      voice: this.presetVoice,
      volume: this.presetVolume,
      rate: this.presetSpeed
    };
    if (instruction.length > 0) {
      input.instruction = instruction;
    }
    const body: QwenTtsRequestBody = {
      model: this.presetModel,
      input: input,
      parameters: { format: 'mp3' }
    };

    synthReq = http.createHttp();
    synthReq.request(QWEN_TTS_ENDPOINT, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.presetKey}`
      },
      extraData: JSON.stringify(body),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 60000
    }).then((resp: http.HttpResponse) => {
      if (cancelled) {
        return;
      }
      destroyAll();
      const code = resp.responseCode;
      const bodyText = resp.result ? (resp.result as string) : '';
      if (code !== 200) {
        // 错误转友好中文（规则：禁止原始英文报错直出）
        if (code === 401) {
          onError('API Key 无效，请检查千问 TTS Key', 0);
          return;
        }
        if (bodyText.includes('418')) {
          onError('音色不可用：cosyvoice 仅支持复刻音色，请在设置里用「拉取音色」选择', 0);
          return;
        }
        const msgMatch = /"message"\s*:\s*"([^"]*)"/.exec(bodyText);
        const detail = msgMatch !== null ? msgMatch[1].substring(0, 80) : `HTTP ${code}`;
        onError(`千问合成失败（${detail}）`, 1);
        return;
      }
      try {
        const parsed = JSON.parse(bodyText) as QwenTtsRespBody;
        const url = parsed.output.audio.url;
        if (url.length === 0) {
          onError('千问合成失败（响应缺少音频链接）', 0);
          return;
        }
        // 第二跳：GET OSS 链接下载 mp3 字节
        downloadReq = http.createHttp();
        downloadReq.request(url, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: 15000,
          readTimeout: 60000
        }).then((dl: http.HttpResponse) => {
          if (cancelled) {
            return;
          }
          destroyAll();
          if (dl.responseCode !== 200) {
            onError(`音频下载失败（HTTP ${dl.responseCode}）`, 0);
            return;
          }
          const audioBuf = dl.result as ArrayBuffer;
          if (audioBuf.byteLength === 0) {
            onError('音频下载失败（响应体为空）', 0);
            return;
          }
          onDone(buffer.from(audioBuf).toString('base64'));
        }).catch((err: BusinessError) => {
          if (cancelled) {
            return;
          }
          destroyAll();
          onError(`音频下载异常：${err.message}`, 0);
        });
      } catch (_e) {
        onError('千问响应解析失败', 0);
      }
    }).catch((err: BusinessError) => {
      if (cancelled) {
        return;
      }
      destroyAll();
      onError(`请求异常：${err.message}`, 0);
    });

    const controller: StreamController = {
      cancel: (): void => {
        cancelled = true;
        destroyAll();
      }
    };
    return controller;
  }

  // 尝试播放下一段缓存（有缓存开播；播完且全部合成完=正常收尾）
  private tryPlayNextAudio(): void {
    if (this.session === null) {
      return; // 会话已停止
    }
    if (this.playIndex >= this.audioCache.length) {
      if (this.audioCache.length >= this.segments.length) {
        this.saveResultCache(); // ★ 0.256.1：完整合成走完才写缓存（中断/失败不缓存）
        const s = this.session;
        this.stop();
        if (s.onComplete !== null && s.onComplete !== undefined) {
          s.onComplete();
        }
      } else {
        this.waitingForAudio = true; // 等下一段合成回调
      }
      return;
    }
    this.waitingForAudio = false;
    this.playSegment(this.playIndex);
  }

  // 清理当前段播放器+临时文件+fd（播放完成/停止时调用，幂等）
  private cleanupSegment(): void {
    const player = this.avPlayer;
    this.avPlayer = null;
    if (player !== null) {
      player.release().catch((): void => {
        // 释放失败忽略（播放器已不可用）
      });
    }
    if (this.currentFd >= 0) {
      try {
        fileIo.closeSync(this.currentFd);
      } catch (_e) {
        // 已关闭
      }
      this.currentFd = -1;
    }
    if (this.currentPath.length > 0) {
      try {
        fileIo.unlinkSync(this.currentPath);
      } catch (_e) {
        // 已删除
      }
      this.currentPath = '';
    }
  }

  // 播放一段：base64 解码 → cacheDir 临时 mp3 → AVPlayer fd:// 播放（对齐 CloudTtsEngine 流水线）
  private async playSegment(index: number): Promise<void> {
    const gen = this.generation;
    if (!this.started) {
      this.started = true; // 首段开播：⏳→🔊
      if (this.session !== null && this.session.onStart !== null && this.session.onStart !== undefined) {
        this.session.onStart();
      }
    }
    try {
      if (!canIUse('SystemCapability.Multimedia.Media.AVPlayer')) {
        throw new Error('设备不支持音频播放');
      }
      const audioBytes = buffer.from(this.audioCache[index], 'base64');
      const path = `${this.cacheDir}/qw_tts_${Date.now()}.mp3`;
      const file = fileIo.openSync(path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd,
        audioBytes.buffer.slice(audioBytes.byteOffset, audioBytes.byteOffset + audioBytes.length) as ArrayBuffer);
      if (gen !== this.generation) {
        fileIo.closeSync(file);
        fileIo.unlinkSync(path);
        return;
      }
      this.currentFd = file.fd;
      this.currentPath = path;
      const player = await media.createAVPlayer();
      if (gen !== this.generation) {
        player.release();
        this.cleanupSegment();
        return;
      }
      this.avPlayer = player;
      player.on('stateChange', (state: string) => {
        if (gen !== this.generation) {
          return;
        }
        if (state === 'initialized') {
          player.prepare();
        } else if (state === 'prepared') {
          player.play();
        } else if (state === 'completed') {
          this.cleanupSegment();
          this.playIndex++;
          this.tryPlayNextAudio();
        }
      });
      player.on('error', (err: BusinessError) => {
        if (gen !== this.generation) {
          return;
        }
        const s = this.session;
        this.stop();
        if (s !== null && s.onError !== null && s.onError !== undefined) {
          s.onError(`音频播放失败（${err.code}）`);
        }
      });
      player.fdSrc = { fd: file.fd };
    } catch (err) {
      if (gen !== this.generation) {
        return;
      }
      const s = this.session;
      this.stop();
      if (s !== null && s.onError !== null && s.onError !== undefined) {
        s.onError(`音频播放失败：${String(err)}`);
      }
    }
  }
}

// 模块级单例：消息朗读（ChatPage 按 ttsProvider 分发）+ 试听（GlobalSettingsDialog 千问档）
export const qianwenTts = new QianwenTtsEngine();
