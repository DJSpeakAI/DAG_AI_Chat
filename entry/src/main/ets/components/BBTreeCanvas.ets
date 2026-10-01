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
import { ThemeStore } from '../entryability/EntryAbility'; // ★ 0.123 深浅色主题

// 气泡树页面 — V2 全量迁移
import { display } from '@kit.ArkUI'; // ★ 屏宽适配（0.123fix7）
@ComponentV2
export struct BBTreeCanvas {
  @Param pathStack: NavPathStack = new NavPathStack();
  store: BubbleTree = AppStorageV2.connect(BubbleTree, 'bubble-tree', () => new BubbleTree()) as BubbleTree;
  persistData: PersistData = PersistenceV2.connect(PersistData, 'persist-data', () => new PersistData()) as PersistData;
  currentBubbleStore: CurrentBubble = AppStorageV2.connect(CurrentBubble, 'current-bubble', () => new CurrentBubble()) as CurrentBubble;
  @Local canvasOffsetX: number = 0;
  @Local canvasOffsetY: number = 0;
  @Local canvasPanStartX: number = 0;
  @Local canvasPanStartY: number = 0;
  @Local canvasScale: number = 1.0;
  @Local pinchStartScale: number = 1.0;

  // ★ 顶层安全边距常量，fitViewport 与 Pan 手势共用（0.126）
  private readonly topSafePadding: number = 120;

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
    return this.c2sX(bubble.parentX) + 30;
  }
  /** 获取父圆心屏幕坐标 Y */
  getParentCY(bubble: BubbleNode): number {
    return this.c2sY(bubble.parentY) + 30;
  }
  /** 获取子圆心屏幕坐标 X */
  getChildCX(bubble: BubbleNode): number {
    return this.c2sX(bubble.x) + 30;
  }
  /** 获取子圆心屏幕坐标 Y */
  getChildCY(bubble: BubbleNode): number {
    return this.c2sY(bubble.y) + 30;
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

  // ★ 获取 ThemeStore（0.123 深浅色主题）
  getThemeStore(): ThemeStore {
    return AppStorageV2.connect(ThemeStore, 'theme-store', () => new ThemeStore()) as ThemeStore;
  }

  // ★ 判断连线是否属于选中分支（0.123）
  isHighlightedLine(bubble: BubbleNode): boolean {
    // 选中节点自身的入边高亮
    if (bubble.nodeID === this.currentBubbleStore.nodeID) return true;
    // 选中节点的出边高亮
    if (bubble.parentID === this.currentBubbleStore.nodeID) return true;
    return false;
  }

  // ★ 纵向树形自动排版（0.124：全节点参与，无 isUserDragged 判断）
  autoLayout(): void {
    const root = this.store.nodeList.find(n => n.parentID === null);
    if (!root) return;

    const horizontalSpacing = 120; // 同层级水平间距
    const verticalSpacing = 160;   // 层级间垂直间距

    // 构建父→子映射
    const childrenMap = new Map<string, BubbleNode[]>();
    for (const node of this.store.nodeList) {
      if (node.parentID !== null) {
        const children = childrenMap.get(node.parentID) || [];
        children.push(node);
        childrenMap.set(node.parentID, children);
      }
    }

    // ★ 递归布局：子节点在父节点正下方居中排列（0.124）
    const layoutChildren = (parent: BubbleNode, depth: number): void => {
      const children = childrenMap.get(parent.nodeID);
      if (!children || children.length === 0) return;

      // ★ 均分居中排布（0.126）：同层子节点整体居中于父节点正下方
      const childCount = children.length;
      const totalWidth = (childCount - 1) * horizontalSpacing;
      const startX = parent.x - totalWidth / 2;
      for (let i = 0; i < childCount; i++) {
        children[i].x = startX + i * horizontalSpacing;
        children[i].y = (depth + 1) * verticalSpacing;
        layoutChildren(children[i], depth + 1);
      }
    };

    root.y = 0;
    layoutChildren(root, 0);

    // 更新所有子节点的 parentX/parentY
    for (const node of this.store.nodeList) {
      if (node.parentID !== null) {
        const parent = this.store.nodeList.find(n => n.nodeID === node.parentID);
        if (parent) {
          node.parentX = parent.x;
          node.parentY = parent.y;
        }
      }
    }

    // 持久化
    this.persistData.bubbleTreeJson = serializeBubbleTree(this.store);
  }

  // ★ 排版后视口自适应：平移使整棵树居中可见（0.123）
  fitViewport(): void {
    if (this.store.nodeList.length === 0) return;

    // 计算画布坐标包围盒
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    for (const node of this.store.nodeList) {
      minX = Math.min(minX, node.x);
      maxX = Math.max(maxX, node.x);
      minY = Math.min(minY, node.y);
      maxY = Math.max(maxY, node.y);
    }

    const treeCenterX = (minX + maxX) / 2;
    const treeCenterY = (minY + maxY) / 2;

    const screenWidth = px2vp(display.getDefaultDisplaySync().width);
    const screenHeight = px2vp(display.getDefaultDisplaySync().height);
    const viewHeight = screenHeight - this.topSafePadding;

    // ★ 自动缩放，让整棵树塞进可视画布（0.126）
    const treeW = maxX - minX + 60;
    const treeH = maxY - minY + 60;
    const scaleX = screenWidth / treeW;
    const scaleY = viewHeight / treeH;
    this.canvasScale = Math.max(0.3, Math.min(scaleX, scaleY, 1.0)); // 约束 [0.3, 1.0]

    // ★ 树中心对齐可视画布中心，-30 气泡半径补偿（0.126）
    this.canvasOffsetX = screenWidth / 2 - treeCenterX * this.canvasScale - 30;
    const calculatedY = this.topSafePadding + viewHeight / 2 - treeCenterY * this.canvasScale - 30;
    this.canvasOffsetY = Math.max(this.topSafePadding, calculatedY); // ★ 不低于安全区，防 Pan 跳变
  }

  // ★ 页面加载自动适配全树视口（0.124）
  aboutToAppear(): void {
    this.fitViewport();
  }

  build() {
    NavDestination() {
      Stack() { // ★ 外层 Stack：包裹画布 + 悬浮按钮（0.123）
        Stack({ alignContent: Alignment.TopStart }) {
        // ── 连线层（从父圆心到子圆心，气泡实心覆盖多余部分） ──
        ForEach(this.store.nodeList, (bubble: BubbleNode) => {
          if (bubble.parentID !== null) {
            // ★ 连线：区分普通/选中分支颜色（0.123）
            Column()
              .width(this.getEdgeLength(bubble))
              .height(2)
              .backgroundColor(this.isHighlightedLine(bubble) ? '#FF6600' : '#CCCCCC')
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
              .borderRadius(30) // ★ 圆角（0.123）
              .backgroundColor(this.getThemeStore().isDark ? '#42A5F5' : '#1976D2') // ★ 深浅色适配（0.123）
              .textAlign(TextAlign.Center)
              // ★ 阴影样式（0.123）
              .shadow({
                radius: this.getThemeStore().isDark ? 8 : 6,
                color: this.getThemeStore().isDark ? 'rgba(0,0,0,0.5)' : 'rgba(0,0,0,0.3)',
                offsetX: 0,
                offsetY: 2
              })
              // 0.101 高亮：当前选中气泡加橙色边框
              .border({
                width: bubble.nodeID === this.currentBubbleStore.nodeID ? 3 : 0,
                color: bubble.nodeID === this.currentBubbleStore.nodeID ? '#FF6600' : Color.Transparent
              })
          }
          .position({
            x: this.c2sX(bubble.x),
            y: this.c2sY(bubble.y)
          })
          // ── 双击导航到对话 ──
          .gesture(
            TapGesture({ count: 2 })
              .onAction(() => {
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
      .backgroundColor(this.getThemeStore().isDark ? '#1A1A1A' : '#FAFAFA') // ★ 深浅色适配（0.123）
      .clip(true) // ★ 0.126：裁剪画布溢出内容，防止绘制跑到标题栏
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

      // ★ 右上角悬浮【显示全部】按钮（0.124：仅适配视口，不改动气泡坐标）
      Text('显示全部')
        .fontSize(14)
        .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .borderRadius(8)
        .backgroundColor(this.getThemeStore().isDark ? '#333333' : '#FFFFFF')
        .border({ width: 1, color: this.getThemeStore().isDark ? '#555555' : '#DDDDDD' })
        .shadow({ radius: 4, color: 'rgba(0,0,0,0.2)', offsetX: 0, offsetY: 2 })
        .position({ x: 260, y: 10 })
        .gesture(
          TapGesture()
            .onAction(() => {
              this.fitViewport(); // ★ 0.124：仅适配视口，不改动气泡坐标
            })
        )
      } // ★ 外层 Stack 结束（0.123）
    }
    .title('气泡树')
    .onShown(() => {
      // ★ 0.126：从 ChatPage 返回时，若 needsRelayout 则重新布局 + 适配视口
      if (this.store.needsRelayout) {
        this.autoLayout();
        this.fitViewport();
        this.store.needsRelayout = false;
      }
    })
  }
}
