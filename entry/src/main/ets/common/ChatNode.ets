// 角色类型：用户 / AI
export type ChatRole = 'user' | 'AI';

// 单条对话消息
@ObservedV2
export class ChatMessage {
  @Trace messageId: string;
  @Trace role: ChatRole;
  @Trace content: string;

  constructor(messageId: string, role: ChatRole, content: string) {
    this.messageId = messageId;
    this.role = role;
    this.content = content;
  }
}

// 气泡节点（对话树中的一个节点）
@ObservedV2
export class BubbleNode {
  @Trace nodeId: string;
  @Trace parentId: string | null;
  @Trace messages: ChatMessage[];
  @Trace x: number;
  @Trace y: number;

  constructor(nodeId: string, parentId: string | null, messages: ChatMessage[], x: number, y: number) {
    this.nodeId = nodeId;
    this.parentId = parentId;
    this.messages = messages;
    this.x = x;
    this.y = y;
  }
}

// V2 全局状态：包装 bubbleList，配合 AppStorageV2 使用
@ObservedV2
export class BubbleTree {
  @Trace bubbleList: BubbleNode[] = [];

  constructor(bubbleList: BubbleNode[] = []) {
    this.bubbleList = bubbleList;
  }
}

// 生成唯一气泡 ID
export function generateNodeId(): string {
  return `bubble_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
}

// 生成唯一消息 ID
export function generateMessageId(): string {
  return `msg_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
}
