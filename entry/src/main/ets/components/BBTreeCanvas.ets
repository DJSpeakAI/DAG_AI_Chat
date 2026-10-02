// ============================================================
// BBTreeCanvas.ets — 气泡树画布页面
// ============================================================
// 本文件是 DAG 气泡树的可视化画布，功能包括：
//   - 气泡节点渲染（圆角矩形组件：节点标题 + 消息计数，★ 0.147）
//   - 父子节点连线（Column + rotate 直线组件，端点补偿到气泡中心）
//   - 双击气泡进入 ChatPage 对话页面
//   - 长按气泡弹操作菜单（修改气泡标题 / 删除气泡，★ 0.147）
//   - 删除气泡及其子树（根节点不可删）
//   - 纵向树形自动排版 + 「显示全部」视口自适应（0.124/0.130）
//   - 画布平移（PanGesture）+ 双指缩放（PinchGesture）
//   - 持久化：布局/标题变更自动保存到 PersistenceV2
//
// 技术栈：鸿蒙 ArkUI V2（组件渲染，非 Canvas 绘图）
// ============================================================

import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import { BubbleNode, BubbleTree, CurrentBubble, PersistData, serializeBubbleTree } from '../common/ChatModel';
import { ThemeStore } from '../entryability/EntryAbility'; // ★ 0.123 深浅色主题
import { GlobalSettingsDialog } from './GlobalSettingsDialog'; // ★ 0.150：全局设置弹窗（画布 ⚙ 唤起，与 ChatPage 共用同一持久化实例）

// 气泡树页面 — V2 全量迁移
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
  // ★ 0.130 画布可视区真实宽高（onAreaChange 获取，替代整屏尺寸 + 写死标题栏高度估算）
  @Local viewW: number = 0;
  @Local viewH: number = 0;
  // ★ 0.147：长按气泡操作菜单状态（修改标题 / 删除气泡）
  @Local menuVisible: boolean = false;
  @Local menuNodeId: string = '';
  // ★ 0.147：标题编辑弹窗状态
  @Local titleEditVisible: boolean = false;
  @Local titleEditNodeId: string = '';
  @Local titleEditText: string = '';

  // ★ 0.150：全局设置弹窗状态（画布右上角 ⚙ 唤起；与 ChatPage 顶栏 ⚙ 共用同一持久化实例，修改一处两处同步）
  @Local globalSettingsVisible: boolean = false;
  @Local globalSettingsCloseReq: number = 0; // 外部请求关闭计数器（onBackPressed 递增 → 弹窗 @Monitor 触发 requestClose）

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

  // ── 连线计算（屏幕坐标，端点补偿到气泡中心区域） ──
  // ★ 0.147：气泡改圆角矩形（宽 72~132、高约 50），补偿取 maxWidth/2 与高度/2，
  // 保证任意内容宽度下连线端点都落在气泡内部（多余部分被气泡实心覆盖）
  /** 获取父气泡中心屏幕坐标 X（+66 为 maxWidth 132 的一半，不随缩放变化） */
  getParentCX(bubble: BubbleNode): number {
    return this.c2sX(bubble.parentX) + 66;
  }
  /** 获取父气泡中心屏幕坐标 Y（+25 为气泡高度约 50 的一半） */
  getParentCY(bubble: BubbleNode): number {
    return this.c2sY(bubble.parentY) + 25;
  }
  /** 获取子气泡中心屏幕坐标 X */
  getChildCX(bubble: BubbleNode): number {
    return this.c2sX(bubble.x) + 66;
  }
  /** 获取子气泡中心屏幕坐标 Y */
  getChildCY(bubble: BubbleNode): number {
    return this.c2sY(bubble.y) + 25;
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

  // ★ 0.147：气泡显示标题——手动标题优先；否则自动取第一条用户提问（截 15 字符，超出加省略号）；无用户消息显示「空气泡」
  getBubbleTitle(bubble: BubbleNode): string {
    if (bubble.nodeTitle !== '') {
      return bubble.nodeTitle;
    }
    for (const msg of bubble.messages) {
      if (msg.role === 'user') {
        const raw = msg.content.trim();
        if (raw.length > 15) {
          return raw.substring(0, 15) + '…';
        }
        return raw;
      }
    }
    return '空气泡';
  }

  // ★ 0.147：保存手动标题（截 15 字符上限）并持久化；清空保存即恢复自动标题
  saveNodeTitle(): void {
    const node = this.store.nodeList.find((n: BubbleNode) => n.nodeID === this.titleEditNodeId);
    if (node !== undefined) {
      node.nodeTitle = this.titleEditText.trim().substring(0, 15);
      this.persistData.bubbleTreeJson = serializeBubbleTree(this.store);
    }
    this.titleEditVisible = false;
  }

  // ★ 0.147：删除确认（原长按 AlertDialog 逻辑提取成方法，菜单【删除气泡】项复用；根节点不可删）
  confirmDeleteBubble(bubble: BubbleNode): void {
    if (bubble.parentID === null) {
      return;
    }
    this.getUIContext().showAlertDialog({
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

    const horizontalSpacing = 160; // ★ 0.147：气泡加宽（maxWidth 132），同层间距 120 → 160 防重叠
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

  // ★ 排版后视口自适应：缩放 + 平移使整棵树居中可见（0.130 重构）
  fitViewport(): void {
    if (this.store.nodeList.length === 0) return;
    // ★ 画布尺寸未就绪（onAreaChange 尚未回调）时跳过，由 onAreaChange 首次回调补调（0.130）
    if (this.viewW <= 0 || this.viewH <= 0) return;

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

    // ★ 自动缩放：以画布真实尺寸为准，去掉 0.3 下限，任何大小的树都完整可见（0.130）
    const treeW = maxX - minX + 132; // ★ 0.147：气泡 maxWidth 132 余量（原 60 圆直径）
    const treeH = maxY - minY + 50;  // ★ 0.147：气泡高度约 50 余量
    this.canvasScale = Math.min(this.viewW / treeW, this.viewH / treeH, 1.0);

    // ★ 树几何中心对齐画布正中，-66/-25 气泡左上角→中心补偿（0.147 随矩形尺寸更新）；去掉 Math.max 截断，树再大中心也对齐（0.130）
    this.canvasOffsetX = this.viewW / 2 - treeCenterX * this.canvasScale - 66;
    this.canvasOffsetY = this.viewH / 2 - treeCenterY * this.canvasScale - 25;
  }

  build() {
    NavDestination() {
      Stack() { // ★ 外层 Stack：包裹画布 + 悬浮按钮（0.123）
        Stack({ alignContent: Alignment.TopStart }) {
        // ── 连线层（从父中心到子中心，气泡实心覆盖多余部分） ──
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
        // ★ 0.147：圆形 60×60 → 圆角矩形（节点标题 + 消息计数），minWidth 72 / maxWidth 132 防尺寸极端
        ForEach(this.store.nodeList, (bubble: BubbleNode) => {
          Column() {
            Text(this.getBubbleTitle(bubble))
              .fontSize(13)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 112 })
            Text(`${bubble.messages.length} 条`)
              .fontSize(10)
              .fontColor('rgba(255,255,255,0.75)')
              .margin({ top: 2 })
          }
          .constraintSize({ minWidth: 72, maxWidth: 132 })
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .borderRadius(12)
          .backgroundColor(this.getThemeStore().isDark ? '#42A5F5' : '#1976D2') // ★ 深浅色适配（0.123）
          .alignItems(HorizontalAlign.Center)
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
          .position({
            x: this.c2sX(bubble.x),
            y: this.c2sY(bubble.y)
          })
          // ── 双击导航到对话（保留原有逻辑） ──
          .gesture(
            TapGesture({ count: 2 })
              .onAction(() => {
                this.currentBubbleStore.nodeID = bubble.nodeID;
                this.currentBubbleStore.bubbleX = bubble.x;
                this.currentBubbleStore.bubbleY = bubble.y;
                this.pathStack.pushPath({ name: 'ChatPage' });
              })
          )
          // ── 长按弹操作菜单（★ 0.147：原直接弹删除确认改为两项菜单） ──
          .gesture(
            LongPressGesture({ duration: 500 })
              .onAction(() => {
                this.menuNodeId = bubble.nodeID;
                this.menuVisible = true;
              })
          )
        }, (bubble: BubbleNode) => bubble.nodeID)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getThemeStore().isDark ? '#1A1A1A' : '#FAFAFA') // ★ 深浅色适配（0.123）
      .clip(true) // ★ 0.126：裁剪画布溢出内容，防止绘制跑到标题栏
      // ★ 0.130 获取画布可视区真实宽高；首次拿到尺寸时自动适配全树视口（替代原 aboutToAppear）
      .onAreaChange((oldVal: Area, newVal: Area) => {
        this.viewW = newVal.width as number;
        this.viewH = newVal.height as number;
        if ((oldVal.width as number) <= 0 && this.viewW > 0) {
          this.fitViewport();
        }
      })
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
        .position({ x: '100%', y: 10 }) // ★ 0.131/V1：右缘自适应（替代写死 x:260，任意屏宽都贴右侧）
        .markAnchor({ x: '100%', y: 0 }) // ★ 锚点为按钮右缘，使 position 100% 对齐父容器右缘
        .translate({ x: -12 }) // ★ 距右缘 12vp 边距
        .gesture(
          TapGesture()
            .onAction(() => {
              this.fitViewport(); // ★ 0.124：仅适配视口，不改动气泡坐标
            })
        )

      // ★ 0.150：右上角悬浮【⚙ 设置】按钮（「显示全部」正下方同款样式；唤起全局设置弹窗，
      // 与 ChatPage 顶栏 ⚙ 共用同一持久化实例，修改一处两处同步、重启保留）
      Text('⚙')
        .fontSize(16)
        .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .borderRadius(8)
        .backgroundColor(this.getThemeStore().isDark ? '#333333' : '#FFFFFF')
        .border({ width: 1, color: this.getThemeStore().isDark ? '#555555' : '#DDDDDD' })
        .shadow({ radius: 4, color: 'rgba(0,0,0,0.2)', offsetX: 0, offsetY: 2 })
        .position({ x: '100%', y: 52 }) // 「显示全部」（y:10 + 高约 34）正下方，间距 8vp
        .markAnchor({ x: '100%', y: 0 })
        .translate({ x: -12 }) // 距右缘 12vp 边距（与「显示全部」对齐）
        .gesture(
          TapGesture()
            .onAction(() => {
              this.globalSettingsVisible = true;
            })
        )

      // ★ 0.150：全局设置弹窗（画布 ⚙ 唤起；遮罩点击不关闭，✕/返回键走弹窗内未保存确认）
      if (this.globalSettingsVisible) {
        GlobalSettingsDialog({
          onClose: () => {
            this.globalSettingsVisible = false;
          },
          closeReq: this.globalSettingsCloseReq
        })
      }

      // ★ 0.147：长按气泡操作菜单（修改标题 / 删除气泡）
      if (this.menuVisible) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.25)')
            .onClick(() => {
              this.menuVisible = false;
            })
          Column() {
            Text('修改气泡标题')
              .fontSize(15)
              .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 14, bottom: 14 })
              .onClick(() => {
                this.menuVisible = false;
                const node = this.store.nodeList.find((n: BubbleNode) => n.nodeID === this.menuNodeId);
                if (node !== undefined) {
                  this.titleEditNodeId = node.nodeID;
                  this.titleEditText = this.getBubbleTitle(node); // 预填当前标题，清空保存即恢复自动标题
                  this.titleEditVisible = true;
                }
              })
            Divider()
              .color(this.getThemeStore().isDark ? '#444444' : '#EEEEEE')
            Text('删除气泡')
              .fontSize(15)
              .fontColor('#F44336')
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 14, bottom: 14 })
              .onClick(() => {
                this.menuVisible = false;
                const node = this.store.nodeList.find((n: BubbleNode) => n.nodeID === this.menuNodeId);
                if (node !== undefined) {
                  this.confirmDeleteBubble(node);
                }
              })
          }
          .width('62%')
          .borderRadius(12)
          .backgroundColor(this.getThemeStore().isDark ? '#2A2A2A' : '#FFFFFF')
          .shadow({ radius: 12, color: 'rgba(0,0,0,0.3)', offsetX: 0, offsetY: 4 })
        }
      }

      // ★ 0.147：标题编辑弹窗（最多 15 字，清空保存恢复自动标题）
      if (this.titleEditVisible) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.25)')
            .onClick(() => {
              this.titleEditVisible = false;
            })
          Column() {
            Text('修改气泡标题')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
              .margin({ bottom: 12 })
            TextInput({ text: this.titleEditText, placeholder: '输入标题（最多15字，清空恢复自动）' })
              .fontSize(14)
              .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
              .maxLength(15)
              .onChange((value: string) => {
                this.titleEditText = value;
              })
              .width('100%')
              .height(44)
              .borderRadius(8)
              .backgroundColor(this.getThemeStore().isDark ? '#333333' : '#F5F5F5')
              .margin({ bottom: 16 })
            Row({ space: 12 }) {
              Button('取消')
                .fontSize(14)
                .height(38)
                .layoutWeight(1)
                .backgroundColor(this.getThemeStore().isDark ? '#444444' : '#EEEEEE')
                .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
                .onClick(() => {
                  this.titleEditVisible = false;
                })
              Button('确定')
                .fontSize(14)
                .height(38)
                .layoutWeight(1)
                .backgroundColor('#1976D2')
                .fontColor('#FFFFFF')
                .onClick(() => {
                  this.saveNodeTitle();
                })
            }
            .width('100%')
          }
          .width('70%')
          .padding(20)
          .borderRadius(12)
          .backgroundColor(this.getThemeStore().isDark ? '#2A2A2A' : '#FFFFFF')
          .shadow({ radius: 12, color: 'rgba(0,0,0,0.3)', offsetX: 0, offsetY: 4 })
        }
      }
      } // ★ 外层 Stack 结束（0.123）
    }
    .title('气泡树')
    .onBackPressed(() => {
      // ★ 0.150：全局设置弹窗打开时拦截返回键——递增计数器触发弹窗内 requestClose
      // （有未保存修改时二次确认，不直接丢弃）；无弹窗返回 false 走默认行为（退出应用）
      if (this.globalSettingsVisible) {
        this.globalSettingsCloseReq++;
        return true;
      }
      return false;
    })
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
