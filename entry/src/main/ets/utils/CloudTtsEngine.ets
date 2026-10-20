// ============================================================
// CloudTtsEngine.ets — ★ 0.232.0 云端 TTS 引擎（火山 openspeech 2.0 协议回归）
// ============================================================
// 历史：0.136~0.142 云端管线 → 0.189.0 按用户指示移除（改本地 CoreSpeechKit）→
//   0.232.0 按用户需求回归（本地引擎「连星号星号都要读进去」，云端音色更自然）。
//   协议实现照抄 0.139 存档（docs/0.165+/0.189.0 §9 + git 16001f2^）。
//
// 端点：https://openspeech.bytedance.com/api/v3/tts/unidirectional（HTTP Chunked 单向流）
// 鉴权：X-Api-Key（豆包语音 Key，与方舟对话 Key 相互独立）+ X-Api-Resource-Id（模型
//   资源 ID）+ X-Api-Request-Id（每次唯一 UUID）
// 请求体：{ req_params: { text, speaker, audio_params: { format, sample_rate } } }
// 响应：Chunked 流式 JSON，data 字段 base64 mp3 片段多段拼接，code=0 成功
//
// ★ 0.232.0 三层兜底（用户规则「没配置→本地；失败→本地」）：
//   1. configured()（audioKey+audioModel 非空）才走云端，否则调用方直落本地；
//   2. ★ 音色资源回退（★ 0.236.2 重构）：声音复刻 2.0 资源（seed-icl-2.0）下 S_ 复刻音色
//      未开通/失效、或官方音色误配复刻资源，都返回 55000000「resource ID is mismatched
//      with speaker related resource」——回退=音色+模型资源同步换（官方音色
//      zh_female_vv_uranus_bigtts + seed-tts-2.0，0.232.0 实证可用组合），会话内记住生效
//      组合（控制台开通复刻资源后自动回到合成音色，零代码改动）；
//   3. 云端仍失败 → onError 交调用方回退本地 CoreSpeechKit。
//
// 会话模型：speak() = 一个会话（代际号 generation 使在飞回调全部失效）；
//   分段串行合成（280 字/段，复用 LocalTtsEngine.splitTextForTts 单一真相源）+
//   base64 缓存 → cacheDir 临时文件 → AVPlayer fd:// 顺序播放。
// ============================================================

import { http } from '@kit.NetworkKit';
import { buffer, util } from '@kit.ArkTS';
import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { connectApiConfig } from '../common/ChatModel';
import { splitTextForTts } from './LocalTtsEngine';
import { StreamController } from './ApiClient';

// 分段上限（与本地引擎同源 280 字/段——openspeech 单段请求长度安全线，沿用 0.136 值）
const CLOUD_TTS_MAX_SEGMENT_LEN = 280;

// 官方音色（合成音色资源不匹配时的回退目标——0.232.0 实证 seed-tts-2.0 下可用）
const FALLBACK_OFFICIAL_VOICE = 'zh_female_vv_uranus_bigtts';

// ★ 0.236.2：官方模型资源（复刻资源 55000000 时的回退目标）——官方音色 zh_female_vv_uranus_bigtts
//   属豆包语音合成体系，在 seed-icl-2.0（声音复刻 2.0）资源下同样报 55000000；回退必须
//   音色+资源 ID 同步换（旧逻辑只换音色不换资源=回退必然二次失败，2026-10-15 根因实锤）
const FALLBACK_OFFICIAL_MODEL = 'seed-tts-2.0';

// ★ 0.236.2：开发期临时默认音色（用户拍板「音色 ID 默认填写，上线之前我会命令给删除的」；
//   2026-10-14 实证 seed-icl-2.0 + S_bv8H32Sg2 code=0 直连可用）
const DEFAULT_VOICE_ICL = 'S_bv8H32Sg2';

// 资源/音色不匹配业务码（openspeech 返回体 code——55000000）
const CODE_VOICE_RESOURCE_MISMATCH = 55000000;

// 会话回调（调用方：ChatPage——驱动喇叭三态与本地回退）
// ★ 0.279.0：onSynthesized=合成完成计费回调（chars=全文清洗后字符数；cached=true 命中结果缓存
//   零请求零计费 / false=完整合成走完——中断/失败/回退重试不触发，失败零扣费铁律天然成立）
export interface CloudTtsSession {
  onStart?: () => void;                             // 首段开播（⏳→🔊）
  onComplete?: () => void;                          // 全部段播报完成
  onError?: (message: string) => void;              // 云端失败（调用方回退本地）
  onSynthesized?: (chars: number, cached: boolean) => void; // ★ 0.279.0：SP 计费点（云端 TTS 音频输出实扣）
}

// 单段合成：HTTP POST openspeech（0.139 实现原样恢复；ArkTS 严格模式接口显式类型）
interface AudioParams {
  format: string;
  sample_rate: number;
}

interface ReqParams {
  text: string;
  speaker: string;
  audio_params: AudioParams;
}

interface SpeechRequestBody {
  req_params: ReqParams;
}

export class CloudTtsEngine {
  private segments: string[] = [];
  private requestIndex: number = 0;   // 合成进度（串行流水线）
  private playIndex: number = 0;      // 播放进度
  private audioCache: string[] = [];  // 已合成段 base64（请求与播放解耦）
  private waitingForAudio: boolean = false; // 播放器空闲等音频（true=播完缓存等下一段）
  private currentFd: number = -1;     // 当前播放临时文件 fd
  private currentPath: string = '';   // 当前播放临时文件路径
  private requestController: StreamController | null = null;
  private generation: number = 0;     // 会话代际号（stop 递增使在飞回调失效）
  private avPlayer: media.AVPlayer | null = null;
  private session: CloudTtsSession | null = null;
  private cacheDir: string = '';
  private voiceOverride: string = ''; // ★ 音色资源回退会话缓存（空=用配置音色）
  private modelOverride: string = ''; // ★ 0.236.2：回退模型资源会话缓存（空=用 presetModel；音色+资源同步换）
  private started: boolean = false;   // onStart 已触发（每会话一次）

  // ★ 0.232.0：云端已配置判定（audioKey+audioModel 双非空——未填模型/Key 时直落本地）
  configured(): boolean {
    const c = connectApiConfig();
    return c.audioKey.trim().length > 0 && c.audioModel.trim().length > 0;
  }

  // 发起朗读会话（读持久化配置）。返回 false = 未配置（调用方直落本地引擎）
  // ★ 0.236.1：重构为显式传参单一管线（GSD 试听复用完整链路——对齐 QianwenTtsEngine 模式）
  speak(text: string, cacheDir: string, session: CloudTtsSession): boolean {
    const c = connectApiConfig();
    const model = c.audioModel.trim();
    if (c.audioKey.trim().length === 0 || model.length === 0) {
      return false;
    }
    let endpoint = c.audioEndpoint.trim();
    if (endpoint.length === 0 || !endpoint.startsWith('https://')) {
      endpoint = 'https://openspeech.bytedance.com/api/v3/tts/unidirectional';
    }
    return this.speakWithParams(text, endpoint, c.audioKey.trim(), model, c.audioVoice.trim(),
      cacheDir, session);
  }

  // ★ 0.236.1：显式传参合成（GSD 火山/自定义档试听用——表单未保存的编辑值直接验证）
  speakWithParams(
    text: string,
    endpoint: string,
    apiKey: string,
    model: string,
    voice: string,
    cacheDir: string,
    session: CloudTtsSession
  ): boolean {
    if (apiKey.length === 0 || model.length === 0 || endpoint.length === 0) {
      return false;
    }
    const trimmed = text.trim();
    if (trimmed.length === 0) {
      return false;
    }
    this.stop(); // 顶替旧会话
    this.session = session;
    this.cacheDir = cacheDir;
    this.presetEndpoint = endpoint;
    this.presetKey = apiKey;
    this.presetModel = model;
    this.presetVoice = voice;
    this.segments = splitTextForTts(trimmed, CLOUD_TTS_MAX_SEGMENT_LEN);
    if (this.segments.length === 0) {
      return false;
    }
    this.requestIndex = 0;
    this.playIndex = 0;
    this.audioCache = [];
    this.waitingForAudio = true; // 首段到达立即开播（0.142 死锁教训）
    this.started = false;
    this.voiceOverride = ''; // 显式会话音色即最终值（空值时合成层兜底官方音色）
    this.modelOverride = '';
    // ★ 0.256.1：播报结果缓存命中——同文本+同配置再次点击喇叭=直接重播已合成音频，
    //   零请求零计费（用户拍板「第二次发送很浪费」；value=段数组：各段独立 base64，
    //   直接串接会因 padding 错位——按段播放原管线零解码风险）
    const cacheKey = `vol|${this.presetEndpoint}|${this.presetKey}|${this.presetModel}|${this.presetVoice.trim()}|${trimmed}`;
    const hit = this.resultCache.get(cacheKey);
    if (hit !== undefined) {
      this.resultCache.delete(cacheKey);
      this.resultCache.set(cacheKey, hit); // LRU touch（Map 迭代序=插入序）
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

  // 结果缓存写入（全部段合成完成时调用；命中重播路径 pendingCacheKey 为空=跳过）
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
    if (this.resultCache.size > CloudTtsEngine.RESULT_CACHE_MAX) {
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

  // 会话级显式参数（speakWithParams 写入；speak 由配置换算后同走该通道，保持单一合成管线）
  private presetEndpoint: string = 'https://openspeech.bytedance.com/api/v3/tts/unidirectional';
  private presetKey: string = '';
  private presetModel: string = '';
  private presetVoice: string = '';

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

  // 请求下一段（串行：上一段回调后才发下一段，controller 始终指向在飞请求）
  private requestNextSegment(): void {
    if (this.requestIndex >= this.segments.length) {
      this.requestController = null; // 全部发出
      return;
    }
    const gen = this.generation;
    const index = this.requestIndex;
    this.requestIndex++;
    // ★ 0.236.1：会话参数走 preset* 显式值（speak/speakWithParams 统一管线）
    const endpoint = this.presetEndpoint;
    const apiKey = this.presetKey;
    // 音色：会话回退缓存 > 显式值；空值兜底（★ 0.236.2：声音复刻 2.0 资源=开发期默认复刻
    //   音色 S_bv8H32Sg2 免一次 55000000 失败重试，其他资源=官方音色原语义）
    const model = this.modelOverride.length > 0 ? this.modelOverride : this.presetModel;
    const configVoice = this.presetVoice.trim();
    let voice = this.voiceOverride.length > 0 ? this.voiceOverride : configVoice;
    if (voice.length === 0) {
      voice = model === 'seed-icl-2.0' ? DEFAULT_VOICE_ICL : FALLBACK_OFFICIAL_VOICE;
    }
    this.requestController = this.synthesizeSegment(
      endpoint, apiKey, model, voice,
      this.segments[index],
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
      (err: string, bizCode: number): void => {
        if (gen !== this.generation) {
          return;
        }
        // ★ 音色资源回退（★ 0.236.2 条件与动作重构）：声音复刻 2.0 资源（seed-icl-2.0）下
        //   S_ 复刻音色未开通/失效、或官方音色误配复刻资源，都返回 55000000——回退动作必须
        //   音色+模型资源同步换（官方音色 zh_female_vv_uranus_bigtts + seed-tts-2.0，
        //   0.232.0 实证可用组合），旧逻辑只换音色不换资源=回退二次失败照样 55000000；
        //   会话内记住生效组合（控制台开通复刻资源后自动回到合成音色，零代码改动）
        if (bizCode === CODE_VOICE_RESOURCE_MISMATCH && this.voiceOverride.length === 0 &&
          this.presetModel === 'seed-icl-2.0') {
          this.voiceOverride = FALLBACK_OFFICIAL_VOICE; // 会话内记住（含后续段）
          this.modelOverride = FALLBACK_OFFICIAL_MODEL;
          this.requestIndex = 0;
          this.playIndex = 0;
          this.audioCache = [];
          this.waitingForAudio = true;
          this.cleanupSegment();
          this.requestNextSegment(); // 从头重来（此时 voiceOverride/modelOverride 生效）
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

  // 单段合成（0.139 synthesizeTTS 原样恢复为私有方法；bizCode 回传供音色回退判定）
  private synthesizeSegment(
    endpoint: string,
    apiKey: string,
    model: string,
    voice: string,
    text: string,
    onDone: (audioBase64: string) => void,
    onError: (err: string, bizCode: number) => void
  ): StreamController {
    let cancelled = false;
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
    const requestId = util.generateRandomUUID(false);
    const httpRequest = http.createHttp();
    httpRequest.request(endpoint, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'X-Api-Key': apiKey,
        'X-Api-Resource-Id': model,
        'X-Api-Request-Id': requestId
      },
      extraData: JSON.stringify(body),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 60000
    }).then((resp: http.HttpResponse) => {
      if (cancelled) {
        return;
      }
      httpRequest.destroy();
      const code = resp.responseCode;
      const bodyText = resp.result ? (resp.result as string) : '';
      if (code !== 200) {
        const errMsg = bodyText.length > 0
          ? `HTTP ${code}: ${bodyText.substring(0, 150)}`
          : `HTTP ${code}（响应体为空）`;
        onError(errMsg, -1);
        return;
      }
      if (bodyText.length === 0) {
        onError('HTTP 200 但响应体为空', -1);
        return;
      }
      try {
        // code 校验：code=0 成功（v2 头结构与 v1 平体两种形态兼容）
        const codeMatch = /"code"\s*:\s*(-?\d+)/.exec(bodyText);
        if (codeMatch !== null && parseInt(codeMatch[1], 10) !== 0) {
          const bizCode = parseInt(codeMatch[1], 10);
          const msgMatch = /"message"\s*:\s*"([^"]*)"/.exec(bodyText);
          const bizMsg = msgMatch !== null ? msgMatch[1] : '未知业务错误';
          onError(`业务错误 code=${bizCode}: ${bizMsg}`, bizCode);
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
          onError('响应中无 data 音频字段', -1);
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
        onDone(buffer.from(mergedBuf).toString('base64'));
      } catch (_e) {
        onError('响应解析失败', -1);
      }
    }).catch((err: BusinessError) => {
      if (cancelled) {
        return;
      }
      httpRequest.destroy();
      onError(`请求异常: ${err.message}`, -1);
    });
    const controller: StreamController = {
      cancel: (): void => {
        cancelled = true;
        try {
          httpRequest.destroy();
        } catch (_e) {
          // 已销毁
        }
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
        // 全部播完——最后一段 completed 回调后收尾（completed 先于本调用的场景由此兜底）
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

  // 播放一段：base64 解码 → cacheDir 临时 mp3 → AVPlayer fd:// 播放（0.134 流水线恢复）
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
      const path = `${this.cacheDir}/tts_${Date.now()}.mp3`;
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

// 模块级单例：消息朗读（ChatPage）专用；与本地引擎（LocalTtsEngine）调用方互斥调度
export const cloudTts = new CloudTtsEngine();
