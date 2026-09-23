import { AppStorageV2 } from '@kit.ArkUI';
import { BBTreeCanvas } from '../components/BBTreeCanvas';
import { ChatPage } from '../components/ChatPage';
import { BubbleNode, ChatMessage, BubbleTree, generateNodeId, generateMessageId } from '../common/ChatModel';

// 首页入口 — V2 全量迁移
@Entry
@ComponentV2
struct Index {
  pathStack: NavPathStack = new NavPathStack();

  aboutToAppear() {
    // V2：AppStorageV2.connect 初始化全局状态
    AppStorageV2.connect(BubbleTree, 'bubble-tree', () => {
      const rootId = generateNodeId();
      return new BubbleTree([
        new BubbleNode(rootId, null, [
          new ChatMessage(generateMessageId(), 'user', '你好'),
          new ChatMessage(generateMessageId(), 'AI', '1')
        ], 200, 200)
      ]);
    });
  }

  @Builder
  pageMap(name: string) {
    if (name === 'BBTreeCanvas') {
      BBTreeCanvas({ pathStack: this.pathStack })
    } else if (name === 'ChatPage') {
      ChatPage({ pathStack: this.pathStack })
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

        Text('图结构对话 · 多分支推演')
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
