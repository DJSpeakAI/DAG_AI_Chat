// ============================================================
// WordSpeaker.ets — Word pronunciation speaker (0.149 / 0.189.0 本地化 / ★ 0.189.1 口音联动)
// ============================================================
// ★ 0.189.0：火山云端 TTS 取消——发音走本地 CoreSpeechKit（LocalTtsEngine 单例）。
// ★ 0.189.1 口音联动（用户拍板方案）：
//   - 单词发音永远优先 en-US Laura 引擎（真美式，需语音包已装）
//   - 音标口音设置（0.185.0 PhoneticAccentStore）驱动提示：
//       美式 + Laura 可下载未装 → onNeedUsPack 提示（每会话一次，引导去单词库 ⚙ 下载）
//       英式 → 系统无 en-GB 音色（清单封闭）→ onNoBritishPack 提示（每会话一次）后照常播
//   - Laura 未装/不可用 → 聆小珊兜底（中文语境英文）
//   - 提示回调由调用方持有 UI 上下文负责 toast（本单例无 UI）
// 三态 🔈/⏳/🔊 状态标志沿用；与消息朗读共用引擎实例——引擎级互斥。
// ============================================================

import { localTts, EnVoiceStatus } from './LocalTtsEngine';
import { connectPhoneticAccent } from '../common/ChatModel'; // ★ 0.189.1：音标口音设置（british: false=美式默认）
import { UIContext } from '@kit.ArkUI'; // ★ 0.189.2：口音提示弹窗（UIContext.showAlertDialog）

// ★ 0.189.1：发音提示回调（调用方 toast；均为每会话一次，WordSpeaker 内部去重）
export interface WordSpeakHooks {
  onEngineUnavailable?: () => void; // 本地引擎不可用（旧固件/语音包缺失）
  onNeedUsPack?: () => void;        // 美式设置 + Laura 可下载未装 → 引导 ⚙ 下载
  onNoBritishPack?: () => void;     // 英式设置 → 系统无英式音色提示
}

@ObservedV2
export class WordSpeaker {
  @Trace loadingWord: string = '';   // 引擎启动中（speaker icon shows ⏳）
  @Trace speakingWord: string = '';  // 播报中（含启动阶段，speaker icon shows 🔊）

  // 每会话一次的提示去重标志（app 启动重置——语音包状态可能变化，重启后再提示合理）
  private noticedNeedUsPack: boolean = false;
  private noticedNoBritish: boolean = false;

  // Text to speak: abbreviations speak their FULL NAME (the few
  // letters are trivial to read — the full term is what's worth hearing);
  // plain words speak themselves.
  textFor(word: string, fullName: string): string {
    return fullName.length > 0 ? fullName : word;
  }

  // Called by UI: toggle speak/stop for the word.
  speak(word: string, hooks?: WordSpeakHooks): void {
    if (this.loadingWord === word) {
      return; // 引擎启动中——防重复点击
    }
    if (this.speakingWord === word) {
      this.stop(); // 播放本词中——点击即停
      return;
    }
    this.stop(); // 顶替其他会话（含消息朗读的引擎占用）
    this.speakingWord = word;
    this.loadingWord = word;
    // ★ 0.189.1：口音联动——先查 Laura 状态（缓存），再决定引擎与提示
    localTts.queryEnVoiceStatus().then((status: EnVoiceStatus) => {
      // 提示（每会话一次；先提示后播报，不打断发音节奏）
      const accent = connectPhoneticAccent();
      if (accent.british) {
        if (!this.noticedNoBritish && hooks && hooks.onNoBritishPack) {
          this.noticedNoBritish = true;
          hooks.onNoBritishPack();
        }
      } else if (status === 'downloadable') {
        if (!this.noticedNeedUsPack && hooks && hooks.onNeedUsPack) {
          this.noticedNeedUsPack = true;
          hooks.onNeedUsPack();
        }
      }
      // 引擎选择：Laura 已装 → en（真美式）；否则聆小珊兜底
      const lang = status === 'installed' ? 'en' : 'zh';
      return localTts.speakText(word, {
        onStart: () => {
          this.loadingWord = ''; // ⏳→🔊
        },
        onComplete: () => {
          this.resetState(); // 播完——恢复空闲态
        },
        onError: (code: number, message: string) => {
          this.resetState(); // 出错——静默恢复（单词短文本，错误罕见）
        }
      }, lang);
    }).then((ok: boolean) => {
      if (!ok) {
        this.resetState();
        if (hooks && hooks.onEngineUnavailable) {
          hooks.onEngineUnavailable(); // 引擎不可用——调用方 toast 提示
        }
      }
    });
  }

  // Stop everything: stop the engine + reset state (idempotent)
  stop(): void {
    localTts.stop();
    this.resetState();
  }

  private resetState(): void {
    this.speakingWord = '';
    this.loadingWord = '';
  }
}

// Module-level singleton shared by all entry points
export const wordSpeaker = new WordSpeaker();

// ★ 0.189.2：口音提示弹窗工厂（用户要求：英式无包提示必须弹窗——切英式却播美式是
// 重要信息，toast 一闪而过太轻；美式缺包引导同步升级弹窗。4 处调用点共用，单一真相源）
export function showAccentDialogs(ui: UIContext): WordSpeakHooks {
  return {
    onEngineUnavailable: () => {
      try {
        ui.getPromptAction().showToast({ message: '本机语音引擎不可用', duration: 2000 });
      } catch (e) {
        // toast 失败静默（非关键路径）
      }
    },
    onNeedUsPack: () => {
      ui.showAlertDialog({
        title: '美式语音包未安装',
        message: '下载美式语音包（Laura）后，单词发音为真美式音色。\n请前往「单词库 ⚙ 设置 → 发音语音包」下载（免费）。',
        confirm: {
          value: '确定',
          action: () => {}
        }
      });
    },
    onNoBritishPack: () => {
      ui.showAlertDialog({
        title: '系统暂无英式语音包',
        message: '鸿蒙系统语音包暂无英式（en-GB）音色，当前将按美式发音播放。\n可留意系统后续语音包更新。',
        confirm: {
          value: '确定',
          action: () => {}
        }
      });
    }
  };
}
