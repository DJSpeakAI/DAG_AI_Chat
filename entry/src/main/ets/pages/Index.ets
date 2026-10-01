// ============================================================
// Index.ets — 应用首页入口
// ============================================================
// 本文件是应用的入口页面，负责：
//   - 初始化持久化数据（PersistenceV2 连接）
//   - 从 JSON 恢复气泡树（反序列化）
//   - 首次启动时创建默认气泡树（根节点）
//   - 配置 NavPathStack 导航路由（气泡画布 / 对话页 / 设置页）
//
// 页面导航关系：
//   Index → BBTreeCanvas（气泡画布）→ ChatPage（对话页）
//                                  → SettingsPage（设置页）
// ============================================================

import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import { BBTreeCanvas } from '../components/BBTreeCanvas';
import { ChatPage } from '../components/ChatPage';
import { SettingsPage } from '../components/SettingsPage';
import { BubbleNode, ChatMessage, BubbleTree, ApiConfig, PersistData, generateNodeId, generateMessageId, deserializeBubbleTree } from '../common/ChatModel';

// 首页入口 — V2 全量迁移
@Entry
@ComponentV2
struct Index {
  pathStack: NavPathStack = new NavPathStack();

  aboutToAppear() {
    // PersistenceV2: 持久化 JSON 字符串
    const persist = PersistenceV2.connect(PersistData, 'persist-data', () => new PersistData()) as PersistData;
    // 尝试从 JSON 恢复 BubbleTree
    const loaded = deserializeBubbleTree(persist.bubbleTreeJson);
    if (loaded) {
      AppStorageV2.connect(BubbleTree, 'bubble-tree', () => loaded);
    } else {
      // 首次启动，创建默认气泡树
      AppStorageV2.connect(BubbleTree, 'bubble-tree', () => {
        const rootId = generateNodeId();
        return new BubbleTree([
          new BubbleNode(rootId, null, [
            new ChatMessage(generateMessageId(), 'user', '你好'),
            new ChatMessage(generateMessageId(), 'assistant', '1')
          ], 200, 200)
        ]);
      });
    }
    // PersistenceV2：API 配置持久化，跨重启保存
    PersistenceV2.connect(ApiConfig, 'api-config', () => new ApiConfig());
  }

  @Builder
  pageMap(name: string) {
    if (name === 'BBTreeCanvas') {
      BBTreeCanvas({ pathStack: this.pathStack })
    } else if (name === 'ChatPage') {
      ChatPage({ pathStack: this.pathStack })
    } else if (name === 'SettingsPage') {
      SettingsPage({ pathStack: this.pathStack })
    }
  }

  build() {
    Navigation(this.pathStack) {
      // 首页内容
      Column() {
        Text('DAG AI Chat')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')

        Text('图结构对话 · 多分支推理')
          .fontSize(14)
          .fontColor('#999999')
          .margin({ top: 8 })

        Button('进入对话画布')
          .margin({ top: 40 })
          .onClick(() => {
            this.pathStack.pushPath({ name: 'BBTreeCanvas' });
          })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .navDestination(this.pageMap)
    .mode(NavigationMode.Auto)
  }
}
