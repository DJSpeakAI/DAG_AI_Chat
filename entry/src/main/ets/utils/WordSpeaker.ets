// ============================================================
// WordSpeaker.ets — Word pronunciation speaker (0.149 phonetic TTS)
// ============================================================
// Single-segment TTS for word pronunciation. We synthesize the WORD
// itself (not the IPA symbols — TTS engines read plain English
// natively in a US accent, matching the stored usPhonetic) and play
// it via AVPlayer.
// Module-level singleton so all three entry points (review strip in
// ChatPage, WordBankPage rows, translate popup) share one player and
// one set of speaking-state flags (mutual exclusion for free).
//
// State is @ObservedV2 + @Trace so V2 UI binds directly:
//   loadingWord  — synthesis in flight (speaker icon shows ⏳)
//   speakingWord — playing or loading (speaker icon shows 🔊)
// ============================================================

import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { ApiConfig } from '../common/ChatModel';
import { synthesizeTTS, StreamController } from './ApiClient';

@ObservedV2
export class WordSpeaker {
  @Trace loadingWord: string = '';   // synthesis in flight
  @Trace speakingWord: string = '';  // playing (includes loading phase)

  private player: media.AVPlayer | null = null;
  private fd: number = -1;
  private path: string = '';
  private gen: number = 0;
  private controller: StreamController | null = null;
  private cacheDir: string = '';

  // Text to synthesize: abbreviations speak their FULL NAME (the few
  // letters are trivial to read — the full term is what's worth hearing);
  // plain words speak themselves (US accent matches usPhonetic).
  textFor(word: string, fullName: string): string {
    return fullName.length > 0 ? fullName : word;
  }

  // Called by UI: toggle speak/stop for the word.
  // cacheDir comes from the caller's getHostContext() (kept as plain
  // string to avoid importing Context types here).
  speak(word: string, config: ApiConfig, cacheDir: string): void {
    if (this.loadingWord === word) {
      return; // synthesis in flight — ignore repeat taps
    }
    if (this.speakingWord === word) {
      this.stop(); // playing this word — tap = stop
      return;
    }
    this.stop();
    if (cacheDir.length > 0) {
      this.cacheDir = cacheDir;
    }
    this.speakingWord = word;
    this.loadingWord = word;
    const g = ++this.gen;
    this.controller = synthesizeTTS(
      word,
      config,
      (audioBase64: string) => {
        if (g !== this.gen) {
          return; // stale callback
        }
        this.loadingWord = '';
        this.playAudio(audioBase64, g);
      },
      (err: string) => {
        if (g !== this.gen) {
          return;
        }
        console.error(`[WordSpeaker] 发音合成失败: ${err}`);
        this.stop();
      }
    );
  }

  // Stop everything: cancel in-flight request, release player, reset state (idempotent)
  stop(): void {
    this.gen++; // invalidate all in-flight callbacks
    if (this.controller) {
      this.controller.cancel();
      this.controller = null;
    }
    this.cleanup();
    this.speakingWord = '';
    this.loadingWord = '';
  }

  // Release player + fd + temp file (idempotent)
  private cleanup(): void {
    const player = this.player;
    this.player = null;
    if (player) {
      player.release().catch(() => {
        // release failure ignored (player already unusable)
      });
    }
    if (this.fd >= 0) {
      try {
        fileIo.closeSync(this.fd);
      } catch (e) {
        // already closed
      }
      this.fd = -1;
    }
    if (this.path.length > 0) {
      try {
        fileIo.unlinkSync(this.path);
      } catch (e) {
        // already removed
      }
      this.path = '';
    }
  }

  // base64 → cacheDir temp file → AVPlayer fd playback (mirrors ChatPage.playSegment)
  private async playAudio(audioBase64: string, g: number): Promise<void> {
    try {
      if (!canIUse('SystemCapability.Multimedia.Media.AVPlayer')) {
        console.error('[WordSpeaker] 当前设备不支持音频播放');
        this.stop();
        return;
      }
      if (this.cacheDir.length === 0) {
        console.error('[WordSpeaker] cacheDir 不可用');
        this.stop();
        return;
      }
      const audioBytes = buffer.from(audioBase64, 'base64');
      const path = `${this.cacheDir}/word_tts_${Date.now()}.mp3`;
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, audioBytes.buffer.slice(audioBytes.byteOffset, audioBytes.byteOffset + audioBytes.length) as ArrayBuffer);
      if (g !== this.gen) {
        // stopped while writing the file → clean up and bail
        fileIo.closeSync(file);
        fileIo.unlinkSync(path);
        return;
      }
      // fd stays open for the player (fdSrc mode); cleanup() closes it
      this.fd = file.fd;
      this.path = path;

      const player = await media.createAVPlayer();
      if (g !== this.gen) {
        // stopped while creating the player → release and bail
        player.release();
        this.cleanup();
        return;
      }
      this.player = player;
      player.on('stateChange', (state: string) => {
        if (g !== this.gen) {
          return; // stale callback
        }
        if (state === 'initialized') {
          player.prepare();
        } else if (state === 'prepared') {
          player.play();
        } else if (state === 'completed') {
          this.stop(); // finished — restore idle icon
        }
      });
      player.on('error', (err: BusinessError) => {
        console.error(`[WordSpeaker] AVPlayer 错误: ${err.message}`);
        this.stop();
      });
      player.fdSrc = { fd: file.fd }; // triggers initialized → prepare → play
    } catch (err) {
      console.error(`[WordSpeaker] 播放失败: ${(err as Error).message}`);
      this.stop();
    }
  }
}

// Module-level singleton shared by all entry points
export const wordSpeaker = new WordSpeaker();
