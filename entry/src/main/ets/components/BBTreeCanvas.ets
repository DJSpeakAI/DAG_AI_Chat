// ============================================================
// BBTreeCanvas.ets — 气泡树画布页面
// ============================================================
// 本文件是 DAG 气泡树的可视化画布，功能包括：
//   - 气泡节点渲染（圆形气泡，显示节点名称和消息数）
//   - 父子节点连线绘制（贝塞尔曲线）
//   - 气泡拖拽（长按拖动改变位置）
//   - 点击气泡进入 ChatPage 对话页面
//   - 添加子气泡（从父气泡分叉出新节点）
//   - 删除气泡及其子树
//   - 持久化：位置变更自动保存到 PersistenceV2
//
// 技术栈：鸿蒙 ArkUI V2 + Canvas 绘图
// ============================================================

import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import { BubbleNode, BubbleTree, CurrentBubble, PersistData, serializeBubbleTree } from '../common/ChatModel';

// 气泡树页面 — V2 全量迁移
@ComponentV2
export struct BBTreeCanvas {
  @Param pathStack: NavPathStack = new NavPathStack();
  store: BubbleTree = AppStorageV2.connect(BubbleTree, 'bubble-tree', () => new BubbleTree()) as BubbleTree;
  persistData: PersistData = PersistenceV2.connect(PersistData, 'persist-data', () => new PersistData()) as PersistData;
  currentBubbleStore: CurrentBubble = AppStorageV2.connect(CurrentBubble, 'current-bubble', () => new CurrentBubble()) as CurrentBubble;
  @Local dragBubbleId: string = '';
  @Local dragOffsetX: number = 0;
  @Local dragOffsetY: number = 0;
  @Local isDragging: boolean = false;
  @Local canvasOffsetX: number = 0;
  @Local canvasOffsetY: number = 0;
  @Local canvasPanStartX: number = 0;
  @Local canvasPanStartY: number = 0;
  @Local canvasScale: number = 1.0;
  @Local pinchStartScale: number = 1.0;

  // ── 坐标变换（手动，弃用容器 scale/translate） ──

  /** 画布坐标 → 屏幕坐标 X */
  c2sX(cx: number): number {
    return cx * this.canvasScale + this.canvasOffsetX;
  }
  /** 画布坐标 → 屏幕坐标 Y */
  c2sY(cy: number): number {
    return cy * this.canvasScale + this.canvasOffsetY;
  }
  /** 屏幕偏移 → 画布偏移 X */
  s2cDx(dx: number): number {
    return dx / this.canvasScale;
  }
  /** 屏幕偏移 → 画布偏移 Y */
  s2cDy(dy: number): number {
    return dy / this.canvasScale;
  }

  // ── 连线计算（屏幕坐标，已扣除气泡半径 30px） ──

  /** 获取父圆心屏幕坐标 X（半径 30px 是屏幕像素，不随缩放变化） */
  getParentCX(bubble: BubbleNode): number {
    const pDragX = bubble.parentID === this.dragBubbleId ? this.dragOffsetX : 0;
    return this.c2sX(bubble.parentX + pDragX) + 30;
  }
  /** 获取父圆心屏幕坐标 Y */
  getParentCY(bubble: BubbleNode): number {
    const pDragY = bubble.parentID === this.dragBubbleId ? this.dragOffsetY : 0;
    return this.c2sY(bubble.parentY + pDragY) + 30;
  }
  /** 获取子圆心屏幕坐标 X */
  getChildCX(bubble: BubbleNode): number {
    const cDragX = bubble.nodeID === this.dragBubbleId ? this.dragOffsetX : 0;
    return this.c2sX(bubble.x + cDragX) + 30;
  }
  /** 获取子圆心屏幕坐标 Y */
  getChildCY(bubble: BubbleNode): number {
    const cDragY = bubble.nodeID === this.dragBubbleId ? this.dragOffsetY : 0;
    return this.c2sY(bubble.y + cDragY) + 30;
  }
  /** 连线中点 X（线段中心位置，用于居中渲染） */
  getEdgeMidX(bubble: BubbleNode): number {
    return (this.getParentCX(bubble) + this.getChildCX(bubble)) / 2;
  }
  /** 连线中点 Y */
  getEdgeMidY(bubble: BubbleNode): number {
    return (this.getParentCY(bubble) + this.getChildCY(bubble)) / 2;
  }
  /** 连线长度（圆心到圆心，气泡实心覆盖多余部分） */
  getEdgeLength(bubble: BubbleNode): number {
    const dx = this.getChildCX(bubble) - this.getParentCX(bubble);
    const dy = this.getChildCY(bubble) - this.getParentCY(bubble);
    return Math.sqrt(dx * dx + dy * dy);
  }
  /** 连线角度（度） */
  getEdgeAngle(bubble: BubbleNode): number {
    const dx = this.getChildCX(bubble) - this.getParentCX(bubble);
    const dy = this.getChildCY(bubble) - this.getParentCY(bubble);
    return Math.atan2(dy, dx) * 180 / Math.PI;
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        // ── 连线层（从父圆心到子圆心，气泡实心覆盖多余部分） ──
        ForEach(this.store.nodeList, (bubble: BubbleNode) => {
          if (bubble.parentID !== null) {
            Column()
              .width(this.getEdgeLength(bubble))
              .height(2)
              .backgroundColor('#CCCCCC')
              .position({
                x: this.getParentCX(bubble),
                y: this.getParentCY(bubble) - 1
              })
              .rotate({
                angle: this.getEdgeAngle(bubble),
                centerX: 0,
                centerY: 1
              })
          }
        }, (bubble: BubbleNode) => bubble.nodeID)

        // ── 气泡层（屏幕坐标） ──
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
              // 0.101 高亮：当前选中气泡加橙色边框
              .border({
                width: bubble.nodeID === this.currentBubbleStore.nodeID ? 3 : 0,
                color: bubble.nodeID === this.currentBubbleStore.nodeID ? '#FF6600' : Color.Transparent
              })
          }
          .position({
            x: this.c2sX(bubble.x + (bubble.nodeID === this.dragBubbleId ? this.dragOffsetX : 0)),
            y: this.c2sY(bubble.y + (bubble.nodeID === this.dragBubbleId ? this.dragOffsetY : 0))
          })
          // ── 拖拽手势（屏幕偏移 → 画布偏移） ──
          .gesture(
            PanGesture({ distance: 5 })
              .onActionStart(() => {
                this.dragBubbleId = bubble.nodeID;
                this.dragOffsetX = 0;
                this.dragOffsetY = 0;
                this.isDragging = true;
              })
              .onActionUpdate((event: GestureEvent) => {
                this.dragOffsetX = this.s2cDx(event.offsetX);
                this.dragOffsetY = this.s2cDy(event.offsetY);
              })
              .onActionEnd(() => {
                const draggedBubble = this.store.nodeList.find(b => b.nodeID === this.dragBubbleId);
                if (draggedBubble) {
                  const newX = Math.max(0, draggedBubble.x + this.dragOffsetX);
                  const newY = Math.max(0, draggedBubble.y + this.dragOffsetY);
                  draggedBubble.x = newX;
                  draggedBubble.y = newY;
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
                setTimeout(() => {
                  this.isDragging = false;
                }, 200);
                this.persistData.bubbleTreeJson = serializeBubbleTree(this.store);
              })
          )
          // ── 双击导航到对话 ──
          .gesture(
            TapGesture({ count: 2 })
              .onAction(() => {
                if (this.isDragging) {
                  return;
                }
                this.currentBubbleStore.nodeID = bubble.nodeID;
                this.currentBubbleStore.bubbleX = bubble.x;
                this.currentBubbleStore.bubbleY = bubble.y;
                this.pathStack.pushPath({ name: 'ChatPage' });
              })
          )
          // ── 长按删除 ──
          .gesture(
            LongPressGesture({ duration: 500 })
              .onAction(() => {
                if (this.isDragging) {
                  return;
                }
                if (bubble.parentID === null) {
                  return;
                }
                AlertDialog.show({
                  title: '删除节点',
                  message: '确认删除此节点及其所有子节点？',
                  primaryButton: {
                    value: '取消',
                    action: () => {}
                  },
                  secondaryButton: {
                    value: '删除',
                    fontColor: '#F44336',
                    action: () => {
                      const idsToDelete: string[] = [bubble.nodeID];
                      let changed = true;
                      while (changed) {
                        changed = false;
                        for (let i = 0; i < this.store.nodeList.length; i++) {
                          const node = this.store.nodeList[i];
                          const pid = node.parentID !== null ? node.parentID : '';
                          if (idsToDelete.includes(pid) && !idsToDelete.includes(node.nodeID)) {
                            idsToDelete.push(node.nodeID);
                            changed = true;
                          }
                        }
                      }
                      const newList: BubbleNode[] = [];
                      for (let i = 0; i < this.store.nodeList.length; i++) {
                        if (!idsToDelete.includes(this.store.nodeList[i].nodeID)) {
                          newList.push(this.store.nodeList[i]);
                        }
                      }
                      this.store.nodeList = newList;
                      this.persistData.bubbleTreeJson = serializeBubbleTree(this.store);
                    }
                  }
                });
              })
          )
        }, (bubble: BubbleNode) => bubble.nodeID)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FAFAFA')
      // ── 画布平移手势 ──
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
      // ── 双指缩放（0.102） ──
      .gesture(
        PinchGesture({ fingers: 2 })
          .onActionStart(() => {
            this.pinchStartScale = this.canvasScale;
          })
          .onActionUpdate((event: GestureEvent) => {
            const newScale = this.pinchStartScale * event.scale;
            if (newScale >= 0.3 && newScale <= 2.0) {
              // 以捏合中心为锚点，保持该点不动调整 offset
              const ratio = newScale / this.canvasScale;
              this.canvasOffsetX = event.pinchCenterX - (event.pinchCenterX - this.canvasOffsetX) * ratio;
              this.canvasOffsetY = event.pinchCenterY - (event.pinchCenterY - this.canvasOffsetY) * ratio;
              this.canvasScale = newScale;
            }
          })
      )
      // ❌ 不再使用容器级 .translate() 和 .scale()
    }
    .title('气泡树')
  }
}
