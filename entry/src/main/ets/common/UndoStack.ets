// UndoStack.ets — ★ 0.287.0 操作撤销栈（命令模式，P2）
// 设计定稿（用户拍板）：三类操作进栈（删除/移动文件夹/重命名），50 步线性历史（超深裁头），
//   会话级不持久化（重启清空——闭包不可序列化恰好匹配语义）；Ctrl+Z 撤销 / Ctrl+Shift+Z 重做。
// 不进栈（业界共识+用户认可）：设置修改（即时可改回）、发送消息（计费请求不可逆）、
//   新建（撤销=删新建有丢内容风险）、导入、文本打字级（P3 缓）。
// undo/redo 返回 label 供调用层 toast「已撤销：××」；空栈/尾端返回空串（调用层静默）。

import { AppStorageV2 } from '@kit.ArkUI';

// 撤销条目：label=toast 文案；undo/redo=逆/正操作（闭包捕获完整对象引用快照）
export interface UndoEntry {
  label: string;
  undo: () => void;
  redo: () => void;
}

// 历史上限（PS 默认档；Office 100 / Figma 无限吃内存——环形裁头折中）
export const UNDO_MAX_ENTRIES: number = 50;

@ObservedV2
export class UndoStore {
  @Trace count: number = 0; // 当前可撤销步数（undo 后递减——驱动潜在 UI 态）
  private entries: UndoEntry[] = [];
  private pointer: number = -1; // 线性历史指针（已执行到的下标；undo 后退一位，push 截断其后）

  // 入栈：截断 pointer 之后的「已撤销分支」（标准线性历史模型）再追加；超上限裁最旧
  push(label: string, undo: () => void, redo: () => void): void {
    if (this.pointer < this.entries.length - 1) {
      this.entries = this.entries.slice(0, this.pointer + 1);
    }
    const entry: UndoEntry = { label: label, undo: undo, redo: redo };
    this.entries.push(entry);
    if (this.entries.length > UNDO_MAX_ENTRIES) {
      this.entries = this.entries.slice(this.entries.length - UNDO_MAX_ENTRIES);
    }
    this.pointer = this.entries.length - 1;
    this.count = this.entries.length;
  }

  // 撤销：执行栈顶逆操作，指针后退；返回 label（空串=无可撤销）
  undo(): string {
    if (this.pointer < 0 || this.pointer >= this.entries.length) {
      return '';
    }
    const entry = this.entries[this.pointer];
    entry.undo();
    this.pointer -= 1;
    this.count = this.pointer + 1;
    return entry.label;
  }

  // 重做：执行下一个正操作，指针前进；返回 label（空串=无可重做）
  redo(): string {
    if (this.pointer >= this.entries.length - 1) {
      return '';
    }
    const entry = this.entries[this.pointer + 1];
    entry.redo();
    this.pointer += 1;
    this.count = this.pointer + 1;
    return entry.label;
  }

  canUndo(): boolean {
    return this.pointer >= 0 && this.entries.length > 0;
  }

  canRedo(): boolean {
    return this.pointer < this.entries.length - 1;
  }

  // 清空（会话结束/数据级操作如恢复导入后防错位）
  clear(): void {
    this.entries = [];
    this.pointer = -1;
    this.count = 0;
  }
}

// 连接应用级单例（key 'undo-stack-v1'——AppStorageV2 内存共享不落盘，闭包安全）
export function connectUndoStack(): UndoStore {
  return AppStorageV2.connect(UndoStore, 'undo-stack-v1', () => new UndoStore()) as UndoStore;
}
