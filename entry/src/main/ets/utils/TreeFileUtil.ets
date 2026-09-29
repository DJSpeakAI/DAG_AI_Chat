import { fileIo } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { BubbleTree, BubbleNode, ChatMessage, ChatRole } from '../common/ChatModel';

// ========== 纯对象接口定义（用于 JSON 序列化/反序列化） ==========
// ArkTS 禁止未类型化的对象字面量，必须显式声明接口
interface PlainChatMessage {
  messageId: string;
  role: string;
  content: string;
}

interface PlainBubbleNode {
  nodeID: string;
  parentID: string | null;
  x: number;
  y: number;
  parentX: number;
  parentY: number;
  messages: PlainChatMessage[];
}

interface PlainBubbleTree {
  version: number;
  nodeList: PlainBubbleNode[];
}

// ========== 1. 响应式树 → 纯对象（剥离 @ObservedV2 代理） ==========
// 作用：@ObservedV2 代理对象不能直接 JSON.stringify，必须逐属性手动提取
export function treeToPlainObj(tree: BubbleTree): PlainBubbleTree {
  const plainNodes: PlainBubbleNode[] = [];
  // 遍历每个 BubbleNode，逐属性提取
  for (let i = 0; i < tree.nodeList.length; i++) {
    const node = tree.nodeList[i];
    // 遍历每个 ChatMessage，逐属性提取
    const plainMsgs: PlainChatMessage[] = [];
    for (let j = 0; j < node.messages.length; j++) {
      const msg = node.messages[j];
      const plainMsg: PlainChatMessage = {
        messageId: msg.messageId,
        role: msg.role,
        content: msg.content
      };
      plainMsgs.push(plainMsg);
    }
    // 提取 BubbleNode 全部属性
    const plainNode: PlainBubbleNode = {
      nodeID: node.nodeID,
      parentID: node.parentID,
      x: node.x,
      y: node.y,
      parentX: node.parentX,
      parentY: node.parentY,
      messages: plainMsgs
    };
    plainNodes.push(plainNode);
  }
  // version 字段用于后续数据结构升级迁移
  const result: PlainBubbleTree = { version: 1, nodeList: plainNodes };
  return result;
}

// ========== 2. 纯对象 → 重建响应式 BubbleTree ==========
// 作用：从 JSON 纯对象重新 new 出 @ObservedV2 响应式实例
export function plainObjToTree(obj: PlainBubbleTree): BubbleTree {
  // 数据校验：obj 不存在或 nodeList 不是数组则返回空树
  if (!obj || !obj.nodeList || !Array.isArray(obj.nodeList)) {
    return new BubbleTree([]);
  }
  const nodeList: BubbleNode[] = [];
  for (let i = 0; i < obj.nodeList.length; i++) {
    const n = obj.nodeList[i];
    // 重建 ChatMessage 数组
    const messages: ChatMessage[] = [];
    if (n.messages && Array.isArray(n.messages)) {
      for (let j = 0; j < n.messages.length; j++) {
        const m = n.messages[j];
        messages.push(new ChatMessage(m.messageId, m.role as ChatRole, m.content));
      }
    }
    // 重建 BubbleNode，parentX/parentY 兜底默认 0
    nodeList.push(new BubbleNode(
      n.nodeID,
      n.parentID,
      messages,
      n.x,
      n.y,
      n.parentX || 0,
      n.parentY || 0
    ));
  }
  return new BubbleTree(nodeList);
}

// ========== 3. 保存气泡树到沙盒 JSON ==========
// 流程：tree → treeToPlainObj → JSON.stringify → 写入沙盒文件
export async function saveBubbleTree(tree: BubbleTree, ctx: common.UIAbilityContext): Promise<boolean> {
  try {
    // ① 代理对象 → 纯对象
    const plain = treeToPlainObj(tree);
    // ② 序列化
    const json = JSON.stringify(plain);
    // ③ 获取沙盒路径
    const filePath = ctx.filesDir + '/bubbleTreeData.json';
    // ④ 打开文件，TRUNC 清空旧内容防止残留
    const file = fileIo.openSync(filePath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    // ⑤ 写入 JSON 文本
    fileIo.writeSync(file.fd, json);
    // ⑥ 关闭文件
    fileIo.closeSync(file);
    console.info(`[TreeFileUtil] save OK, nodes=${plain.nodeList.length}`);
    return true;
  } catch (e) {
    console.error(`[TreeFileUtil] save failed: ${e}`);
    return false;
  }
}

// ========== 4. 从沙盒加载气泡树 ==========
// 流程：判断文件存在 → 读取 → 转文本 → JSON.parse → plainObjToTree
export async function loadBubbleTree(ctx: common.UIAbilityContext): Promise<BubbleTree | null> {
  try {
    // ① 获取沙盒路径
    const filePath = ctx.filesDir + '/bubbleTreeData.json';
    // ② 判断文件是否存在，accessSync 抛异常代表不存在
    try {
      fileIo.accessSync(filePath);
    } catch {
      return null;
    }
    // ③ 打开文件读取
    const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
    const stat = fileIo.statSync(filePath);
    // ④ 空文件直接返回 null
    if (stat.size === 0) {
      fileIo.closeSync(file);
      return null;
    }
    // ⑤ 读取 ArrayBuffer
    const arrayBuffer = new ArrayBuffer(stat.size);
    fileIo.readSync(file.fd, arrayBuffer);
    fileIo.closeSync(file);
    // ⑥ ArrayBuffer → 字符串 → JSON 解析
    const text = buffer.from(arrayBuffer).toString();
    const obj = JSON.parse(text) as PlainBubbleTree;
    // ⑦ 纯对象 → 重建响应式 BubbleTree 实例
    const result = plainObjToTree(obj);
    console.info(`[TreeFileUtil] load OK, nodes=${obj.nodeList.length}`);
    return result;
  } catch (e) {
    console.error(`[TreeFileUtil] load failed: ${e}`);
    return null;
  }
}
