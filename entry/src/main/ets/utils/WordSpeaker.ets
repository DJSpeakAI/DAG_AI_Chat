// ============================================================
// WordSpeaker.ets — Word pronunciation speaker (0.149 / ★ 0.189.0 本地化)
// ============================================================
// ★ 0.189.0：火山云端 TTS 按用户指示取消——发音改走本地 CoreSpeechKit
// 引擎（LocalTtsEngine 单例，免费离线）。原 HTTP 合成 → base64 → 临时文件
// → AVPlayer 链路全部移除；三态 🔈/⏳/🔊 状态标志沿用（loadingWord 由
// 引擎 onStart 回调清除）。onUnavailable：引擎不可用时的提示回调
// （调用方持有 UI 上下文负责 toast）。
// 模块级单例：三处入口（ChatPage 复习区×2/翻译弹窗、单词库列表）共用，
// 与消息朗读共用同一引擎实例——引擎级互斥。
// ============================================================

import { localTts } from './LocalTtsEngine';

@ObservedV2
export class WordSpeaker {
  @Trace loadingWord: string = '';   // 引擎启动中（speaker icon shows ⏳）
  @Trace speakingWord: string = '';  // 播报中（含启动阶段，speaker icon shows 🔊）

  // Text to speak: abbreviations speak their FULL NAME (the few
  // letters are trivial to read — the full term is what's worth hearing);
  // plain words speak themselves.
  textFor(word: string, fullName: string): string {
    return fullName.length > 0 ? fullName : word;
  }

  // Called by UI: toggle speak/stop for the word.
  speak(word: string, onUnavailable?: () => void): void {
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
    localTts.speakText(word, {
      onStart: () => {
        this.loadingWord = ''; // ⏳→🔊
      },
      onComplete: () => {
        this.resetState(); // 播完——恢复空闲态
      },
      onError: (code: number, message: string) => {
        this.resetState(); // 出错——静默恢复（单词短文本，错误罕见）
      }
    }).then((ok: boolean) => {
      if (!ok) {
        this.resetState();
        if (onUnavailable) {
          onUnavailable(); // 引擎不可用——调用方 toast 提示
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
