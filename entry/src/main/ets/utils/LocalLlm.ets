// ★ 0.216.0 端侧大模型封装（DataAugmentationKit · localChatModel）
// 架构：三级降级——API Key 已配 → 云端 streamChat；未配 → 本模块（免费/离线端侧 Qwen 7B）；
// 端侧不可用（机型不支持/未下载/未授权）→ onError 友好中文引导配置 API。
// 接口形态：与 streamChat 五回调签名对齐（onChunk/onDone/onError），ChatPage 调用点零改造。
// 平台实锤（d.ts）：init(): Promise<boolean>；chat(QuestionInfo{questionId,content}, Config{isStream},
//   callback: Answer{questionId,content,isFinished})——单轮 content、无 messages/system/JSON mode，
//   多轮上下文由本模块拼接；流式=isStream true（Answer.content 为增量分片）。
import localChatModel from '@hms.data.localChatModel'; // ★ 0.216.0：原始 d.ts 源（namespace default export）——经 @kit re-export 时 namespace 内 interface 类型解析失败（编译实证），故不走 @kit.DataAugmentationKit
import { ChatMessage } from '../common/ChatModel';

let onDeviceReady: boolean | false | undefined = undefined; // undefined=未探测 false=不可用 true=可用（模块级缓存）
let questionSeq: number = 0;

/** 端侧探活（懒执行一次，结果缓存；失败不抛异常只记 false） */
async function ensureOnDevice(): Promise<boolean> {
  if (onDeviceReady !== undefined) {
    return onDeviceReady;
  }
  try {
    const ok: boolean = await localChatModel.init();
    onDeviceReady = ok === true;
    console.info(`DAGAI-LLM init ok=${ok}`);
  } catch (e) {
    onDeviceReady = false;
    console.info(`DAGAI-LLM init err=${JSON.stringify(e)}`);
  }
  return onDeviceReady;
}

/** 多轮消息拼单轮 content（端侧无 messages 数组——system 指令拼头部、历史按角色前缀拼接；长度截断防超 4500 字节性能线） */
function flattenMessages(messages: ChatMessage[]): string {
  let text: string = '';
  for (let i = 0; i < messages.length; i++) {
    const m = messages[i];
    if (m.content.trim().length === 0) {
      continue; // 跳过占位
    }
    const prefix = m.role === 'system' ? '[指令]' : (m.role === 'user' ? '[用户]' : '[助手]');
    text += `${prefix} ${m.content}\n\n`;
  }
  if (text.length > 4200) {
    text = text.slice(text.length - 4200); // 保留近段（尾部含最新问题），端侧 4500 字节性能线
  }
  return `${text}[助手] `;
}

/** 取消句柄（class 形态——ArkTS 对象字面量须对应显式 interface，class 实例彻底绕开 untyped-literal 检查） */
export class LocalStreamHandle {
  private cancelledFlag: () => void;
  constructor(flag: () => void) {
    this.cancelledFlag = flag;
  }
  cancel(): void {
    this.cancelledFlag();
  }
}

/**
 * 端侧流式对话（对齐 streamChat 前四回调；onReasoning 端侧无思考流不支持）。
 * 取消语义：端侧 chat 无官方取消接口，cancel=置已取消标志忽略后续分片（本地继续算完丢弃）。
 */
export function localStreamChat(
  messages: ChatMessage[],
  onChunk: (text: string) => void,
  onDone: (inputTokens: number, outputTokens: number) => void,
  onError: (error: string) => void
): LocalStreamHandle {
  let cancelled = false;
  const handle: LocalStreamHandle = new LocalStreamHandle((): void => {
    cancelled = true;
  });
  ensureOnDevice().then((ready: boolean) => {
    if (cancelled) {
      return;
    }
    if (!ready) {
      onError('本机端侧大模型不可用（设备不支持或模型未就绪）。请在「设置 → API 配置」填写 API Key 使用云端大模型（网上有免费额度可申请）。');
      return;
    }
    questionSeq = (questionSeq + 1) % 65536;
    const content = flattenMessages(messages);
    const qInfo: localChatModel.QuestionInfo = { questionId: questionSeq, content: content };
    const qConfig: localChatModel.Config = { isStream: true };
    console.info(`DAGAI-LLM chat start qid=${questionSeq} len=${content.length}`);
    localChatModel.chat(
      qInfo,
      qConfig,
      (err: Error, answer: localChatModel.Answer) => {
        if (cancelled) {
          return;
        }
        if (err) {
          console.info(`DAGAI-LLM chat err=${err.message}`);
          onError(`端侧模型对话失败：${err.message}。可在「设置 → API 配置」填 API Key 换用云端大模型。`);
          return;
        }
        if (answer.content && answer.content.length > 0) {
          onChunk(answer.content);
        }
        if (answer.isFinished) {
          console.info(`DAGAI-LLM chat finished qid=${answer.questionId}`);
          onDone(0, 0); // 端侧无 usage 统计
        }
      }
    ).catch((e: Error) => {
      if (cancelled) {
        return;
      }
      console.info(`DAGAI-LLM chat promise err=${e.message}`);
      onError(`端侧模型调用异常：${e.message}。可在「设置 → API 配置」填 API Key 换用云端大模型。`);
    });
  });
  return handle;
}