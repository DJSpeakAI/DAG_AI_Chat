import { AppStorageV2 } from '@kit.ArkUI';
import { BubbleNode, BubbleTree, CurrentBubble } from '../common/ChatModel';

// 气泡树页面 — V2 全量迁移
@ComponentV2
export struct BBTreeCanvas {
  @Param pathStack: NavPathStack = new NavPathStack();
  store: BubbleTree = AppStorageV2.connect(BubbleTree, 'bubble-tree', () => new BubbleTree()) as BubbleTree;
  currentBubbleStore: CurrentBubble = AppStorageV2.connect(CurrentBubble, 'current-bubble', () => new CurrentBubble()) as CurrentBubble;
  @Local dragBubbleId: string = '';
  @Local dragOffsetX: number = 0;
  @Local dragOffsetY: number = 0;
  @Local isDragging: boolean = false;
  @Local canvasOffsetX: number = 0;
  @Local canvasOffsetY: number = 0;
  @Local canvasPanStartX: number = 0;
  @Local canvasPanStartY: number = 0;

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Stack({ alignContent: Alignment.TopStart }) {
          // 1. 连线 — Path 组件
          ForEach(this.store.nodeList.filter(b => b.parentID !== null), (bubble: BubbleNode) => {
            ForEach(this.store.nodeList.filter(p => p.nodeID === bubble.parentID), (parent: BubbleNode) => {
              Path()
                .commands(`M${parent.x + 30} ${parent.y + 30} L${bubble.x + 30} ${bubble.y + 30}`)
                .stroke('#CCCCCC')
                .strokeWidth(2)
                .fillOpacity(0)
                .width('100%')
                .height('100%')
            }, (parent: BubbleNode) => parent.nodeID)
          }, (bubble: BubbleNode) => bubble.nodeID)

          // 2. 气泡 — ForEach key 只用 nodeID，@Trace 自动追踪 x/y/messages
          ForEach(this.store.nodeList, (bubble: BubbleNode) => {
            Column() {
              Text(`${bubble.messages.length}`)
                .fontSize(20)
                .fontColor('#FFFFFF')
                .width(60)
                .height(60)
                .borderRadius(30)
                .backgroundColor('#1976D2')
                .textAlign(TextAlign.Center)
            }
            .position({
              x: bubble.x + (bubble.nodeID === this.dragBubbleId ? this.dragOffsetX : 0),
              y: bubble.y + (bubble.nodeID === this.dragBubbleId ? this.dragOffsetY : 0)
            })
            .gesture(
              PanGesture({ distance: 5 })
                .onActionStart(() => {
                  this.dragBubbleId = bubble.nodeID;
                  this.dragOffsetX = 0;
                  this.dragOffsetY = 0;
                  this.isDragging = true;
                  console.info(`[BBTree] drag start: ${bubble.nodeID}`);
                })
                .onActionUpdate((event: GestureEvent) => {
                  this.dragOffsetX = event.offsetX;
                  this.dragOffsetY = event.offsetY;
                })
                .onActionEnd(() => {
                  const draggedBubble = this.store.nodeList.find(b => b.nodeID === this.dragBubbleId);
                  if (draggedBubble) {
                    draggedBubble.x = Math.max(0, draggedBubble.x + this.dragOffsetX);
                    draggedBubble.y = Math.max(0, draggedBubble.y + this.dragOffsetY);
                  }
                  this.dragBubbleId = '';
                  this.dragOffsetX = 0;
                  this.dragOffsetY = 0;
                  console.info(`[BBTree] drag end, committed`);
                  setTimeout(() => {
                    this.isDragging = false;
                  }, 200);
                })
            )
            .gesture(
              TapGesture({ count: 2 })
                .onAction(() => {
                  if (this.isDragging) {
                    return;
                  }
                  console.info(`[BBTree] double tap: ${bubble.nodeID}`);
                  this.currentBubbleStore.nodeID = bubble.nodeID;
                  this.pathStack.pushPath({ name: 'ChatPage' });
                })
            )
          }, (bubble: BubbleNode) => bubble.nodeID)
        }
        .width('100%')
        .height('100%')
        .translate({ x: this.canvasOffsetX, y: this.canvasOffsetY })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FAFAFA')
      .gesture(
        PanGesture({ distance: 5 })
          .onActionStart(() => {
            this.canvasPanStartX = this.canvasOffsetX;
            this.canvasPanStartY = this.canvasOffsetY;
          })
          .onActionUpdate((event: GestureEvent) => {
            this.canvasOffsetX = this.canvasPanStartX + event.offsetX;
            this.canvasOffsetY = this.canvasPanStartY + event.offsetY;
          })
      )
    }
    .title('气泡树')
  }
}
