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
import { BubbleNode, BubbleTree, CurrentBubble, PersistData, serializeBubbleTree, deserializeBubbleTree, generateNodeId, CanvasModeStore, connectCanvasMode, TabMeta, TabForestStore, connectTabForest, parseTabs, serializeTabs, getRootDisplayName, layoutFlatForest } from '../common/ChatModel';
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

  // ★ 0.151：画布多树模式状态（两池隔离：平铺池 bubbleTreeJson / Tab 池 tabsJson，工作区='bubble-tree' 单例）
  canvasModeStore: CanvasModeStore = connectCanvasMode(); // 'flat' 平铺 / 'tabs' 选项卡
  tabForest: TabForestStore = connectTabForest();         // Tab 池（tabsJson + activeTabId）
  // ★ 0.151：Tab 重命名弹窗状态（长按 Tab 触发）
  @Local tabRenameVisible: boolean = false;
  @Local tabRenameId: string = '';
  @Local tabRenameText: string = '';

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

  // ★ 0.151-bugfix：按模式分池保存工作区（两池隔离核心写路径）
  // flat：工作区 = 平铺树 → 存回 bubbleTreeJson（现状路径）
  // tabs：工作区 = 当前 Tab 树 → 存回该 Tab 的 treeJson；
  //       无 activeTab 时【不写任何池】——此时工作区必为空（applyCanvasModeSwitch 保证），
  //       若写平铺池会把空树覆盖平铺池真实数据（用户实测丢树根因）
  saveTree(): void {
    if (this.canvasModeStore.mode === 'tabs') {
      const tabs = parseTabs(this.tabForest.tabsJson);
      const idx = tabs.findIndex((t: TabMeta): boolean => t.id === this.tabForest.activeTabId);
      if (idx >= 0) {
        tabs[idx].treeJson = serializeBubbleTree(this.store);
        // ★ 0.151-bugfix2：Tab 名同步为树根显示名（Tab 名与树根绑定——画布改标题/聊天后 Tab 名跟随）
        const root = this.store.nodeList.find((n: BubbleNode): boolean => n.parentID === null);
        if (root !== undefined) {
          tabs[idx].name = getRootDisplayName(root);
        }
        this.tabForest.tabsJson = serializeTabs(tabs);
      }
      // 无 activeTab：无主工作区无可保存内容，直接跳过（不写任何池）
    } else {
      this.persistData.bubbleTreeJson = serializeBubbleTree(this.store);
    }
  }

  // ★ 0.147：保存手动标题（截 15 字符上限）并持久化；清空保存即恢复自动标题
  saveNodeTitle(): void {
    const node = this.store.nodeList.find((n: BubbleNode) => n.nodeID === this.titleEditNodeId);
    if (node !== undefined) {
      node.nodeTitle = this.titleEditText.trim().substring(0, 15);
      this.saveTree(); // ★ 0.151：按模式分池保存
    }
    this.titleEditVisible = false;
  }

  // ★ 0.147：删除确认（原长按 AlertDialog 逻辑提取成方法，菜单【删除气泡】项复用）
  // ★ 0.151-bugfix4：平铺模式放开根节点删除（= 删除整棵树）——旧版「根不可删」在单树时代
  //   防误删唯一树，但平铺模式多树后用户无删树入口（长按根气泡删除静默无反应，用户实测 bug）；
  //   选项卡模式仍禁删根（删整棵树走长按 Tab 删除）
  confirmDeleteBubble(bubble: BubbleNode): void {
    const isRoot = bubble.parentID === null;
    if (isRoot && this.canvasModeStore.mode !== 'flat') {
      return; // 选项卡模式：根不可删（删树走长按 Tab 删除）
    }
    this.getUIContext().showAlertDialog({
      title: isRoot ? '删除树' : '删除节点',
      message: isRoot ? '确认删除此树（根气泡及其所有子节点）？' : '确认删除此节点及其所有子节点？',
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
          this.saveTree(); // ★ 0.151：按模式分池保存
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

  // ★ 纵向树形自动排版（0.124：全节点参与，无 isUserDragged 判断；★ 0.151：多根平铺支持）
  // ★ 0.151-bugfix3：布局算法提取到 ChatModel.layoutFlatForest 单一来源
  //   （applyCanvasModeSwitch tabs→flat 合并树也用它先排好再落盘），这里只负责调用 + 持久化
  autoLayout(): void {
    layoutFlatForest(this.store.nodeList); // 空树/无根时内部直接 return（无操作）
    // 持久化（★ 0.151：按模式分池）
    this.saveTree();
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
    // ★ 0.151-bugfix5：+32 四周呼吸边距（16×2）——树铺满画布时气泡不贴屏幕边缘
    const treeW = maxX - minX + 132 + 32; // ★ 0.147：气泡 maxWidth 132 余量（原 60 圆直径）
    const treeH = maxY - minY + 50 + 32;  // ★ 0.147：气泡高度约 50 余量
    this.canvasScale = Math.min(this.viewW / treeW, this.viewH / treeH, 1.0);

    // ★ 树几何中心对齐画布正中，-66/-25 气泡左上角→中心补偿（0.147 随矩形尺寸更新）；去掉 Math.max 截断，树再大中心也对齐（0.130）
    // ★ 0.151-bugfix5：补偿必须乘 scale——treeCenterX 是气泡左上角坐标中心，视觉中心 = treeCenterX + 66，
    //   居中要求 (treeCenterX + 66) * scale + offsetX = viewW/2，即 offsetX = viewW/2 - treeCenterX*scale - 66*scale；
    //   旧版写死 -66（未乘 scale），scale<1 时整棵树左偏 66×(1-scale)、上偏 25×(1-scale)
    //   （scale=1 单树时代无偏差从未暴露；多树并排树宽超屏、scale≈0.6 时最左气泡左缘
    //   到 -27vp 屏幕外，用户实测「左边一棵树一半超出屏幕」根因）
    this.canvasOffsetX = this.viewW / 2 - treeCenterX * this.canvasScale - 66 * this.canvasScale;
    this.canvasOffsetY = this.viewH / 2 - treeCenterY * this.canvasScale - 25 * this.canvasScale;
  }

  // ★ 0.151：模式 A【添加根气泡】——新增顶级根节点（=一棵新树）
  // ★ 0.151-bugfix3：新根加入后统一 autoLayout 重排（多根 y=0 并排）——旧逻辑只把新根
  //   放 maxX+200、y=0，不重排既有根（默认气泡 y=200 与新根 y=0 不同排，用户实测 bug1）；
  //   autoLayout 末尾自带 saveTree，无需单独保存
  addRootBubble(): void {
    const root = new BubbleNode(generateNodeId(), null, [], 200, 0); // x 初始值无所谓，autoLayout 会重排
    this.store.nodeList.push(root);
    this.autoLayout();
    this.fitViewport();
  }

  // ★ 0.151：模式 B 切换 Tab——先存回当前 Tab 树，再加载目标 Tab 树 + 重布局 + 适配视口
  switchTab(tabId: string): void {
    if (tabId === this.tabForest.activeTabId) return;
    this.saveTree(); // 当前工作区存回当前 Tab
    this.tabForest.activeTabId = tabId;
    const tabs = parseTabs(this.tabForest.tabsJson);
    const target = tabs.find((t: TabMeta): boolean => t.id === tabId);
    const loaded = target ? deserializeBubbleTree(target.treeJson) : null;
    this.store.nodeList = loaded ? loaded.nodeList : [];
    // 清空选中（旧 Tab 选中节点在新 Tab 必然失效）
    this.currentBubbleStore.nodeID = '';
    this.currentBubbleStore.bubbleX = 0;
    this.currentBubbleStore.bubbleY = 0;
    this.autoLayout();
    this.fitViewport();
  }

  // ★ 0.151：模式 B 新增 Tab——自带一棵全新树（空白根气泡「空气泡」，对话为空）
  addTab(): void {
    this.saveTree(); // 先存回当前 Tab（若有）
    const tabId = `tab_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
    const tabs = parseTabs(this.tabForest.tabsJson);
    const root = new BubbleNode(generateNodeId(), null, [], 200, 0);
    const tree = new BubbleTree([root]);
    tabs.push({ id: tabId, name: getRootDisplayName(root), treeJson: serializeBubbleTree(tree) }); // ★ 0.151-bugfix2：Tab 名 = 树根显示名（空白新根 =「空气泡」，与根气泡文字一致；重命名 Tab 即给树起名）
    this.tabForest.tabsJson = serializeTabs(tabs);
    this.tabForest.activeTabId = tabId;
    // 工作区加载新 Tab 的树
    this.store.nodeList = [root];
    this.currentBubbleStore.nodeID = '';
    this.currentBubbleStore.bubbleX = 0;
    this.currentBubbleStore.bubbleY = 0;
    this.autoLayout();
    this.fitViewport();
  }

  // ★ 0.151：模式 B 删除 Tab——确认后同步删除整棵树数据；删当前 Tab 切相邻（优先右侧），删非当前 Tab 工作区不动
  deleteTab(tabId: string): void {
    const tabs = parseTabs(this.tabForest.tabsJson);
    const target = tabs.find((t: TabMeta): boolean => t.id === tabId);
    if (target === undefined) return;
    this.getUIContext().showAlertDialog({
      title: '删除选项卡',
      message: `确认删除「${target.name}」？该 Tab 对应的整棵树及其全部对话数据将同步删除。`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#F44336',
        action: () => {
          const current = parseTabs(this.tabForest.tabsJson);
          const idx = current.findIndex((t: TabMeta): boolean => t.id === tabId);
          if (idx < 0) return;
          current.splice(idx, 1);
          this.tabForest.tabsJson = serializeTabs(current);
          if (tabId === this.tabForest.activeTabId) {
            // 删的是当前 Tab：切到相邻 Tab（优先原位置右侧，否则左边；全空 = 空树）
            if (current.length === 0) {
              this.tabForest.activeTabId = '';
              this.store.nodeList = [];
            } else {
              const nextIdx = Math.min(idx, current.length - 1);
              const next = current[nextIdx];
              this.tabForest.activeTabId = next.id;
              const loaded = deserializeBubbleTree(next.treeJson);
              this.store.nodeList = loaded ? loaded.nodeList : [];
            }
            this.currentBubbleStore.nodeID = '';
            this.currentBubbleStore.bubbleX = 0;
            this.currentBubbleStore.bubbleY = 0;
            this.autoLayout();
            this.fitViewport();
          }
          // 删的是非当前 Tab：工作区不动（当前树不受影响）
        }
      }
    });
  }

  // ★ 0.151：模式 B 打开 Tab 重命名弹窗（长按 Tab 触发）
  openTabRename(tabId: string): void {
    const tabs = parseTabs(this.tabForest.tabsJson);
    const target = tabs.find((t: TabMeta): boolean => t.id === tabId);
    if (target === undefined) return;
    this.tabRenameId = tabId;
    this.tabRenameText = target.name;
    this.tabRenameVisible = true;
  }

  // ★ 0.151-bugfix2：保存 Tab 重命名（截 12 字上限；空名不覆盖）——Tab 名与树根绑定：
  // 同步写入该 Tab 树根的 nodeTitle（切回平铺根气泡显示同名，往返切换名字不丢）
  saveTabRename(): void {
    const tabs = parseTabs(this.tabForest.tabsJson);
    const idx = tabs.findIndex((t: TabMeta): boolean => t.id === this.tabRenameId);
    if (idx >= 0) {
      const trimmed = this.tabRenameText.trim();
      if (trimmed.length > 0) {
        const newName = trimmed.substring(0, 12);
        tabs[idx].name = newName;
        // 同步写入该 Tab 树根的 nodeTitle（treeJson 内，保证切回平铺时根气泡显示同名）
        const loaded = deserializeBubbleTree(tabs[idx].treeJson);
        if (loaded !== null) {
          const root = loaded.nodeList.find((n: BubbleNode): boolean => n.parentID === null);
          if (root !== undefined) {
            root.nodeTitle = newName;
            tabs[idx].treeJson = serializeBubbleTree(loaded);
          }
        }
        this.tabForest.tabsJson = serializeTabs(tabs);
        // 重命名的是当前 Tab：工作区根标题同步刷新（画布气泡文字立即变）
        if (this.tabRenameId === this.tabForest.activeTabId) {
          const liveRoot = this.store.nodeList.find((n: BubbleNode): boolean => n.parentID === null);
          if (liveRoot !== undefined) {
            liveRoot.nodeTitle = newName;
          }
        }
      }
    }
    this.tabRenameVisible = false;
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
      .clip(true) // ★ 0.126：裁剪画布溢出内容，防止绘制跑到顶部自绘标题行（0.151-D）
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

      // ★ 0.151-D：顶部自绘标题行（弃用 NavDestination 默认标题栏 .title('气泡树') → hideTitleBar，
      // 沿用 ChatPage 0.159 topBarTitle 先例：内容区自绘、宽度参照系=屏幕宽、按钮右对齐间距收紧）
      // 平铺模式：← 返回 + 「气泡树」标题 + [＋ All ⚙] 一行（需求 1/2/4：三按钮与返回按钮齐平、icon 化）
      if (this.canvasModeStore.mode === 'flat') {
        Row() {
          // 自定义返回按钮（替代被 hideTitleBar 隐藏的系统返回）——返回 Index
          Button('←')
            .fontSize(18)
            .backgroundColor(Color.Transparent)
            .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
            .padding({ left: 4, right: 4 })
            .margin({ right: 4 })
            .onClick(() => {
              this.pathStack.pop();
            })
          Text('气泡树')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
          Blank()
            .layoutWeight(1)
          // ＋ 添加根气泡（仅平铺模式；点击新增顶级根节点 = 一棵新树）
          Text('+')
            .fontSize(18)
            .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
            .width(32)
            .height(32)
            .textAlign(TextAlign.Center)
            .borderRadius(8)
            .backgroundColor(this.getThemeStore().isDark ? '#333333' : '#FFFFFF')
            .border({ width: 1, color: this.getThemeStore().isDark ? '#555555' : '#DDDDDD' })
            .margin({ right: 6 })
            .onClick(() => {
              this.addRootBubble();
            })
          // All 显示全部（0.124：仅适配视口，不改动气泡坐标）
          Text('All')
            .fontSize(13)
            .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
            .padding({ left: 10, right: 10, top: 7, bottom: 7 })
            .borderRadius(8)
            .backgroundColor(this.getThemeStore().isDark ? '#333333' : '#FFFFFF')
            .border({ width: 1, color: this.getThemeStore().isDark ? '#555555' : '#DDDDDD' })
            .margin({ right: 6 })
            .onClick(() => {
              this.fitViewport();
            })
          // ⚙ 设置（唤起全局设置弹窗，与 ChatPage 顶栏 ⚙ 共用同一持久化实例，修改一处两处同步、重启保留）
          Text('⚙')
            .fontSize(16)
            .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(8)
            .backgroundColor(this.getThemeStore().isDark ? '#333333' : '#FFFFFF')
            .border({ width: 1, color: this.getThemeStore().isDark ? '#555555' : '#DDDDDD' })
            .onClick(() => {
              this.globalSettingsVisible = true;
            })
        }
        .width('100%')
        .height(44)
        .position({ x: 0, y: 0 }) // 顶部全宽（外层 Stack 默认居中对齐，需 position 钉在左上）
        .padding({ left: 4, right: 12 })
        .backgroundColor(this.getThemeStore().isDark ? 'rgba(26,26,26,0.92)' : 'rgba(250,250,250,0.92)')
      }

      // ★ 0.151-D：选项卡模式标题行（仅 tabs 模式显示；需求 3：取消左上角返回按钮；
      // 需求 4：所有按钮与选项卡齐平一行 = Tab 栏 + [＋ All ⚙]）
      // 一个 Tab = 一棵独立树；Scroll 横向滚动支持 10/20 个 Tab；Tab 名溢出省略号截断；✕ 删除；长按重命名
      if (this.canvasModeStore.mode === 'tabs') {
        Row() {
          // Tab 列表（横向滚动区域）
          Scroll() {
            Row({ space: 8 }) {
              ForEach(parseTabs(this.tabForest.tabsJson), (tab: TabMeta) => {
                Row() {
                  Text(tab.name)
                    .fontSize(13)
                    .fontColor(tab.id === this.tabForest.activeTabId ? '#1976D2' : (this.getThemeStore().isDark ? '#CCCCCC' : '#333333'))
                    .fontWeight(tab.id === this.tabForest.activeTabId ? FontWeight.Bold : FontWeight.Normal)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .constraintSize({ maxWidth: 72 }) // ★ 需求 2.3.3：Tab 标签溢出截断省略号
                  // ✕ 删除 Tab（确认后同步删除整棵树数据）
                  Text('✕')
                    .fontSize(11)
                    .fontColor(this.getThemeStore().isDark ? '#888888' : '#999999')
                    .margin({ left: 4 })
                    .onClick(() => {
                      this.deleteTab(tab.id);
                    })
                }
                .padding({ left: 10, right: 6, top: 8, bottom: 8 })
                .borderRadius(8)
                .backgroundColor(tab.id === this.tabForest.activeTabId
                  ? (this.getThemeStore().isDark ? '#1E3A5F' : '#E3F2FD')
                  : (this.getThemeStore().isDark ? '#333333' : '#FFFFFF'))
                .border({ width: 1, color: this.getThemeStore().isDark ? '#555555' : '#DDDDDD' })
                .onClick(() => {
                  this.switchTab(tab.id); // 点击切换 Tab（切树）
                })
                .gesture(
                  // ★ 需求 2.3.4：长按 Tab 重命名
                  LongPressGesture({ duration: 500 })
                    .onAction(() => {
                      this.openTabRename(tab.id);
                    })
                )
              }, (tab: TabMeta) => tab.id)
            }
            .padding({ left: 12, right: 8 })
          }
          .scrollable(ScrollDirection.Horizontal) // ★ 需求 2.3.5：Tab 栏左右横向滚动
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .height(44)
          .align(Alignment.Start)

          // ＋ 新增 Tab（自带一棵全新树：空白根气泡；0.151-D 压至 32×32 与平铺 ＋ 同款）
          Text('＋')
            .fontSize(18)
            .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
            .width(32)
            .height(32)
            .textAlign(TextAlign.Center)
            .borderRadius(8)
            .backgroundColor(this.getThemeStore().isDark ? '#333333' : '#FFFFFF')
            .border({ width: 1, color: this.getThemeStore().isDark ? '#555555' : '#DDDDDD' })
            .margin({ left: 6 })
            .onClick(() => {
              this.addTab();
            })
          // All 显示全部（0.151-D：与选项卡齐平一行；0.124：仅适配视口，不改动气泡坐标）
          Text('All')
            .fontSize(13)
            .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
            .padding({ left: 10, right: 10, top: 7, bottom: 7 })
            .borderRadius(8)
            .backgroundColor(this.getThemeStore().isDark ? '#333333' : '#FFFFFF')
            .border({ width: 1, color: this.getThemeStore().isDark ? '#555555' : '#DDDDDD' })
            .margin({ left: 6 })
            .onClick(() => {
              this.fitViewport();
            })
          // ⚙ 设置（0.151-D：与选项卡齐平一行；唤起全局设置弹窗，与 ChatPage 顶栏 ⚙ 共用同一持久化实例）
          Text('⚙')
            .fontSize(16)
            .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(8)
            .backgroundColor(this.getThemeStore().isDark ? '#333333' : '#FFFFFF')
            .border({ width: 1, color: this.getThemeStore().isDark ? '#555555' : '#DDDDDD' })
            .margin({ left: 6, right: 12 })
            .onClick(() => {
              this.globalSettingsVisible = true;
            })
        }
        .width('100%')
        .height(44)
        .position({ x: 0, y: 0 }) // 顶部全宽
        .backgroundColor(this.getThemeStore().isDark ? 'rgba(26,26,26,0.92)' : 'rgba(250,250,250,0.92)')
      }

      // ★ 0.150：全局设置弹窗（画布 ⚙ 唤起；遮罩点击不关闭，✕/返回键走弹窗内未保存确认）
      if (this.globalSettingsVisible) {
        GlobalSettingsDialog({
          onClose: () => {
            this.globalSettingsVisible = false;
            // ★ 0.151：画布前台切模式后关弹窗——工作区内容已换（applyCanvasModeSwitch），
            // 立即重布局 + 适配视口（onShown 只在从 ChatPage 返回时触发，覆盖不了此场景）
            if (this.store.needsRelayout) {
              this.autoLayout();
              this.fitViewport();
              this.store.needsRelayout = false;
            }
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

      // ★ 0.151：Tab 重命名弹窗（长按 Tab 触发；最多 12 字，空名不覆盖）
      if (this.tabRenameVisible) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.25)')
            .onClick(() => {
              this.tabRenameVisible = false;
            })
          Column() {
            Text('重命名选项卡')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
              .margin({ bottom: 12 })
            TextInput({ text: this.tabRenameText, placeholder: '输入名称（最多12字）' })
              .fontSize(14)
              .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
              .maxLength(12)
              .onChange((value: string) => {
                this.tabRenameText = value;
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
                  this.tabRenameVisible = false;
                })
              Button('确定')
                .fontSize(14)
                .height(38)
                .layoutWeight(1)
                .backgroundColor('#1976D2')
                .fontColor('#FFFFFF')
                .onClick(() => {
                  this.saveTabRename();
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
    // ★ 0.151-D：弃用默认标题栏（.title('气泡树')）——其左上角系统返回按钮即需求 3 要取消的
    // 「返回气泡树」按钮；改 hideTitleBar + 内容区自绘标题行（平铺：←+标题+按钮组；选项卡：Tab 栏+按钮组）
    .hideTitleBar(true)
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
