import { AppStorageV2 } from '@kit.ArkUI';
import { BubbleNode, BubbleTree, CurrentBubble } from '../common/ChatModel';
import { saveBubbleTree, loadBubbleTree } from '../utils/TreeFileUtil';

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

  aboutToAppear() {
    // 从沙盒加载持久化数据，成功则替换 nodeList
    loadBubbleTree().then((tree) => {
      if (tree && tree.nodeList.length > 0) {
        this.store.nodeList = tree.nodeList;
      }
    });
  }

  // 连线 helper：所有读取来自 bubble 参数（ForEach item）
  getEdgeStartX(bubble: BubbleNode): number {
    const pDragX = bubble.parentID === this.dragBubbleId ? this.dragOffsetX : 0;
    return bubble.parentX + pDragX + 30 + this.canvasOffsetX;
  }
  getEdgeStartY(bubble: BubbleNode): number {
    const pDragY = bubble.parentID === this.dragBubbleId ? this.dragOffsetY : 0;
    return bubble.parentY + pDragY + 30 + this.canvasOffsetY;
  }
  getEdgeEndX(bubble: BubbleNode): number {
    const cDragX = bubble.nodeID === this.dragBubbleId ? this.dragOffsetX : 0;
    return bubble.x + cDragX + 30 + this.canvasOffsetX;
  }
  getEdgeEndY(bubble: BubbleNode): number {
    const cDragY = bubble.nodeID === this.dragBubbleId ? this.dragOffsetY : 0;
    return bubble.y + cDragY + 30 + this.canvasOffsetY;
  }
  getEdgeLength(bubble: BubbleNode): number {
    const dx = this.getEdgeEndX(bubble) - this.getEdgeStartX(bubble);
    const dy = this.getEdgeEndY(bubble) - this.getEdgeStartY(bubble);
    return Math.sqrt(dx * dx + dy * dy);
  }
  getEdgeAngle(bubble: BubbleNode): number {
    const dx = this.getEdgeEndX(bubble) - this.getEdgeStartX(bubble);
    const dy = this.getEdgeEndY(bubble) - this.getEdgeStartY(bubble);
    return Math.atan2(dy, dx) * 180 / Math.PI;
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        // 1. 连线 — Column + position + rotate（弃用 Path）
        ForEach(this.store.nodeList, (bubble: BubbleNode, index: number) => {
          if (bubble.parentID !== null) {
            Column()
              .width(this.getEdgeLength(bubble))
              .height(2)
              .backgroundColor('#CCCCCC')
              .position({
                x: this.getEdgeStartX(bubble),
                y: this.getEdgeStartY(bubble) - 1
              })
              .rotate({
                angle: this.getEdgeAngle(bubble),
                centerX: 0,
                centerY: 1
              })
          } else {
            Blank()
          }
        }, (bubble: BubbleNode) => bubble.nodeID)

        // 2. 气泡 — 内层 Stack，保留 .translate() 画布平移（不动）
        Stack({ alignContent: Alignment.TopStart }) {
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
                    const newX = Math.max(0, draggedBubble.x + this.dragOffsetX);
                    const newY = Math.max(0, draggedBubble.y + this.dragOffsetY);
                    draggedBubble.x = newX;
                    draggedBubble.y = newY;
                    // 更新所有直接子节点的 parentX/parentY
                    for (let i = 0; i < this.store.nodeList.length; i++) {
                      const child = this.store.nodeList[i];
                      if (child.parentID === this.dragBubbleId) {
                        child.parentX = newX;
                        child.parentY = newY;
                      }
                    }
                  }
                  this.dragBubbleId = '';
                  this.dragOffsetX = 0;
                  this.dragOffsetY = 0;
                  console.info(`[BBTree] drag end, committed`);
                  saveBubbleTree(this.store);
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
                  this.currentBubbleStore.bubbleX = bubble.x;
                  this.currentBubbleStore.bubbleY = bubble.y;
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
