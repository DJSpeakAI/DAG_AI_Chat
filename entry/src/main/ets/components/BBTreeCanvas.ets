// ============================================================
// BBTreeCanvas.ets — 气泡树画布页面
// ============================================================
// 本文件是 DAG 气泡树的可视化画布，功能包括：
//   - 气泡节点渲染（圆角矩形组件：节点标题 + 消息计数，★ 0.147）
//   - 父子节点连线（★ 0.167.2：Canvas 命令式绘制贝塞尔 + 箭头，弃 Path——其自动缩放 commands 是连线飞左上角的真根因）
//   - 双击气泡进入 ChatPage 对话页面
//   - 长按气泡弹操作菜单（修改气泡标题 / 删除气泡，★ 0.147）
//   - 删除气泡及其子树（根节点不可删）
//   - 纵向树形自动排版 + 「显示全部」视口自适应（0.124/0.130）
//   - 画布平移（PanGesture）+ 双指缩放（PinchGesture）
//   - 持久化：布局/标题变更自动保存到 PersistenceV2
//
// 技术栈：鸿蒙 ArkUI V2（气泡组件渲染 + 连线 Canvas 绘制）
// ============================================================

import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI'; // ★ 0.196.4：display 移除（isTablet 改读 WindowMode）
import { WindowMode, connectWindowMode } from '../common/WindowMode'; // ★ 0.196.4：窗口宽度模式共享真相源（分屏/悬浮窗切手机布局） ★ 0.168：display 屏宽断点（平板/手机边栏形态）
import { BubbleNode, BubbleTree, CurrentBubble, PersistData, serializeBubbleTree, deserializeBubbleTree, generateNodeId, CanvasMode, CanvasModeStore, connectCanvasMode, TabMeta, TabForestStore, connectTabForest, parseTabs, serializeTabs, getRootDisplayName, layoutFlatForest, applyCanvasModeSwitch, StatisticsStore, connectStatistics, recordStat } from '../common/ChatModel'; // ★ 0.192.0：StatisticsStore/recordStat（学习统计埋点）
import { BG_APP, BG_NAV, BG_CANVAS, SURFACE_NODE, SURFACE_HOVER, SURFACE_SOFT, BRAND_PRIMARY, BRAND_SECONDARY, TEXT_PRIMARY, TEXT_SECONDARY, TEXT_TERTIARY, STROKE_CARD, STROKE_BRAND, SEGMENTED_TRACK, EDGE_COLOR, EDGE_COLOR_HIGHLIGHT, RADIUS_NAV, RADIUS_NODE, RADIUS_CANVAS, RADIUS_CONTROL, RADIUS_LOGO, FONT_INTER, FONT_INTER_SEMIBOLD, FONT_SIZE_SCREEN_TITLE, FONT_SIZE_CARD_TITLE, FONT_SIZE_CARD_TITLE_SM, FONT_SIZE_NAV_LABEL, FONT_SIZE_CAPTION, FONT_SIZE_BODY, FONT_SIZE_META, NODE_W, NODE_H, NODE_ICON } from '../common/DesignTokens'; // ★ 0.167：UI token 单一来源（UI_GUIDELINES.md，禁止散落写色值）；★ 0.168 增补边栏 token；★ 0.173.1：删「工作区」标签后 FONT_SIZE_LABEL 无使用处，移出 import
import { GlobalSettingsDialog } from './GlobalSettingsDialog'; // ★ 0.150：全局设置弹窗（画布 ⚙ 唤起，与 ChatPage 共用同一持久化实例）
import { AppSideBar } from './AppSideBar'; // ★ 0.195.0：共享边栏组件（手机抽屉用；平板常驻边栏已升 Index 级）
import { upsertCloudData } from '../utils/CloudSyncUtil'; // ★ 0.165.1：云同步桥接（持久化点追加写 RDB 快照行，autoSync 自动上云）
import { HuaweiAccountStore, connectHuaweiAccount } from '../utils/HuaweiAccountUtil'; // ★ 0.168：边栏底部账号头像/昵称（华为账号登录态）

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

  // ★ 0.168：左侧边栏（Pixso 工作台稿落地）——平板 208 常驻 / 手机抽屉（★ 0.170.2 抽屉内容对齐平板完整版，同宽 208）
  // ★ 0.196.4：isTablet 改读窗口宽度共享真相源（WindowMode，Index 根 onAreaChange 写入）——
  //   原屏宽判定在分屏/悬浮窗时不变（仍≥600vp）导致小窗仍渲染平板布局（用户实测黑屏+挤压）
  windowMode: WindowMode = connectWindowMode();
  @Computed get isTablet(): boolean {
    return this.windowMode.isTablet;
  }
  @Local sidebarVisible: boolean = false;  // 手机抽屉开关（平板常驻不用）
  // ★ 0.173.1：单击选中气泡（画布页本地视觉焦点，不污染全局 currentBubbleStore 对话语义）
  @Local selectedNodeId: string = '';
  // ★ 0.173.2：手动双击判定状态——单击手势与系统 TapGesture(count:2) 并列绑定时，
  //   ArkUI 手势仲裁让单击在第一击抬起即识别成功、吃掉双击识别流（真机实证双击失效），
  //   故删系统双击手势，同一气泡两次单击间隔 <300ms 手动判定为双击
  @Local lastTapNodeId: string = '';
  @Local lastTapTime: number = 0;
  // ★ 0.182.0：画布空白双击判定——上次点击时间戳（纯逻辑判定不驱动 UI，private 非 @Local）
  private lastCanvasTapTime: number = 0;
  account: HuaweiAccountStore = connectHuaweiAccount(); // 边栏底部头像/昵称（华为账号登录态）
  statStore: StatisticsStore = connectStatistics(); // ★ 0.192.0：学习统计埋点（新建树/Tab）

  aboutToAppear(): void {
    // ★ 0.168：断点判断（≥600vp 平板走宽边栏，否则手机抽屉窄栏）。
    // ★ 0.196.4：isTablet 屏宽检测删除——改读 WindowMode 共享真相源（Index 根 onAreaChange
    //   按窗口实宽写入；分屏/悬浮窗实时切换手机/平板布局）
  }

  // ★ 0.167.2：连线层 Canvas 命令式绘制（弃 Path——Path 无 viewport 属性，未设时 ArkUI 自动把
  // commands 包围盒缩放适配到组件尺寸（实测因子≈0.32），连线被二次缩放飞到画布左上角，真根因；
  // Canvas 2D 绘制坐标 1:1 映射组件 vp 坐标系，无任何隐式变换）
  edgeSettings: RenderingContextSettings = new RenderingContextSettings(true);
  edgeContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.edgeSettings);
  edgeReady: boolean = false; // Canvas onReady 前绘制无效（SDK 文档：onAttach 阶段不可绘制）

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

  // ── 连线计算（★ 0.167：贝塞尔曲线 + 箭头，UI_GUIDELINES 六-7 矢量真相源 Frame_2_664.svg）──
  // 端点：父卡片边缘中点 → 子卡片边缘中点；水平/垂直 S 型按父子相对位置自动选择；
  // 控制点偏移 35×scale；箭头实心三角 7×8.4 指向子卡片
  /** 找父节点（无父返回 null） */
  findParentNode(bubble: BubbleNode): BubbleNode | null {
    if (bubble.parentID === null) {
      return null;
    }
    const parent = this.store.nodeList.find((n: BubbleNode): boolean => n.nodeID === bubble.parentID);
    return parent !== undefined ? parent : null;
  }

  /** ★ 0.167.3：连线层重绘（Canvas 命令式）——统一「父下缘中点 → 子上缘中点」垂直 S 贝塞尔 + 箭头
   *  ★ 0.167.3 用户拍板：出发点全部统一到中间——旧版按父子相对位置自动选水平/垂直 S 型，
   *    多子气泡时出发点分散在左缘/右缘/下缘且随布局切换跳动（用户形容「像抽风」）；
   *    统一后出发点恒为父底部中间、进入点恒为子顶部中间，任何缩放/布局下稳定不跳
   *  ★ 0.167.4 用户拍板：整体等比缩放（传统思维导图模式）——气泡视觉尺寸随 canvasScale
   *    缩放（气泡 .scale 变换锚点左上），端点补偿随之乘 s（回到最初版本公式），线宽/箭头等比。
   *    旧「气泡固定尺寸+间距缩放」方案废弃：缩小时气泡必然相撞（用户绝不接受重叠），压缩间距
   *    则端点重算复杂且连线歪；等比缩放下公式固定——100 个 200 个气泡同一套计算，连线永不歪。
   *  Canvas 无状态绑定 → 所有几何/颜色变化点必须手动调用：
   *  Canvas onReady / onAreaChange / 平移·捏合手势 / zoomBy / fitViewport / autoLayout /
   *  confirmDeleteBubble / onShown（切换分支后高亮变化） */
  redrawEdges(): void {
    if (!this.edgeReady) return;
    const ctx = this.edgeContext;
    ctx.clearRect(0, 0, ctx.width, ctx.height);
    const s = this.canvasScale;
    for (const bubble of this.store.nodeList) {
      const parent = this.findParentNode(bubble);
      if (parent === null) continue; // 根节点无入边
      // 起点：父气泡下缘中点；终点：子气泡上缘中点（统一中间，稳定不跳）
      // ★ 0.167.4：气泡视觉尺寸 = NODE_W*s × NODE_H*s（scale 变换锚点左上）→ 端点补偿乘 s
      const sx = this.c2sX(parent.x) + NODE_W / 2 * s;
      const sy = this.c2sY(parent.y) + NODE_H * s;
      const ex = this.c2sX(bubble.x) + NODE_W / 2 * s;
      const ey = this.c2sY(bubble.y);
      const color = this.isHighlightedLine(bubble) ? EDGE_COLOR_HIGHLIGHT : EDGE_COLOR;
      ctx.strokeStyle = color;
      ctx.fillStyle = color;
      ctx.lineWidth = 2 * s; // ★ 0.167.4：线宽等比（传统思维导图模式）
      // 垂直 S 控制点偏移：随缩放等比，且不超过半程（父子很近时防曲线过弯、异常布局时防反向）
      const off = Math.max(0, Math.min(35 * s, (ey - sy) / 2));
      ctx.beginPath();
      ctx.moveTo(sx, sy);
      ctx.bezierCurveTo(sx, sy + off, ex, ey - off, ex, ey);
      ctx.stroke();
      // 箭头：实心三角 7×8.4 基准随缩放等比，指向子气泡上缘中点（向下）
      const len = 7 * s;
      const half = 4.2 * s;
      ctx.beginPath();
      ctx.moveTo(ex, ey);
      ctx.lineTo(ex - half, ey - len);
      ctx.lineTo(ex + half, ey - len);
      ctx.closePath();
      ctx.fill();
    }
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

  // ★ 0.172.3：气泡最近消息时间——取最后一条消息 messageId 内嵌时间戳（generateMessageId 格式 msg_${Date.now()}_xxx，
  //   全项目所有消息同格式）→ 零模型改动、旧持久化数据天然支持；空气泡/解析失败兜底 0
  getBubbleLastTime(bubble: BubbleNode): number {
    const last = bubble.messages[bubble.messages.length - 1];
    if (!last) {
      return 0;
    }
    const parts = last.messageId.split('_');
    if (parts.length < 2 || parts[0] !== 'msg') {
      return 0;
    }
    const ts = Number(parts[1]);
    if (isNaN(ts) || ts <= 0) {
      return 0;
    }
    return ts;
  }

  // ★ 0.172.3：相对时间格式化（参考图惯例：刚刚 / X分钟前 / X小时前 / 昨天 / X天前 / X周前 / X个月前）
  formatRelativeTime(ts: number): string {
    if (ts <= 0) {
      return '';
    }
    const diff = Date.now() - ts;
    if (diff < 60 * 1000) {
      return '刚刚';
    }
    if (diff < 60 * 60 * 1000) {
      return `${Math.floor(diff / (60 * 1000))}分钟前`;
    }
    // 今天内按小时；昨天按日历日判断（跨 0 点即「昨天」，参考图语义）
    const now = new Date();
    const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    if (ts >= startOfToday) {
      return `${Math.floor(diff / (60 * 60 * 1000))}小时前`;
    }
    if (ts >= startOfToday - 24 * 60 * 60 * 1000) {
      return '昨天';
    }
    const days = Math.floor(diff / (24 * 60 * 60 * 1000));
    if (days < 7) {
      return `${days}天前`;
    }
    if (days < 30) {
      return `${Math.floor(days / 7)}周前`;
    }
    return `${Math.floor(days / 30)}个月前`;
  }

  // ★ 0.172.3：卡片元信息行——「N 条对话 · 最近消息时间」（参考图格式；无时间数据时只显示条数）
  getBubbleMeta(bubble: BubbleNode): string {
    const time = this.formatRelativeTime(this.getBubbleLastTime(bubble));
    if (time === '') {
      return `${bubble.messages.length} 条对话`;
    }
    return `${bubble.messages.length} 条对话 · ${time}`;
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
        upsertCloudData('tabs_pool', this.tabForest.tabsJson); // ★ 0.165.1：云同步桥接（Tab 池快照上云）
      }
      // 无 activeTab：无主工作区无可保存内容，直接跳过（不写任何池）
    } else {
      this.persistData.bubbleTreeJson = serializeBubbleTree(this.store);
      upsertCloudData('flat_pool', this.persistData.bubbleTreeJson); // ★ 0.165.1：云同步桥接（平铺池快照上云）
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
    // ★ 0.182.0：选项卡模式根节点删除放开——原静默 return（旧决策「删树走长按 Tab 删除」），
    //   用户实测长按根气泡点【删除气泡】无反应视为 bug；改走 deleteTab(activeTabId)：
    //   自带确认弹窗（文案「删除选项卡」语义更准）、删当前 Tab 自动切相邻、云同步，不会双重弹窗
    if (isRoot && this.canvasModeStore.mode !== 'flat') {
      this.deleteTab(this.tabForest.activeTabId);
      return;
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
          this.redrawEdges(); // ★ 0.167.2：节点删除后连线重绘（此路径不重排，需手动刷新）
        }
      }
    });
  }

  // ★ 0.173.1：视觉焦点节点——单击选中优先（单选替换语义），无单击时回落「当前对话气泡」
  //   （双击进入对话后返回的选中态，原行为保留）；双击导航时清 selectedNodeId 无缝交棒
  getFocusNodeId(): string {
    return this.selectedNodeId !== '' ? this.selectedNodeId : this.currentBubbleStore.nodeID;
  }

  // ★ 0.173.1：气泡是否处于选中态（卡片高亮/「双击进入对话」/chevron/连线高亮共用判断）
  isBubbleSelected(bubble: BubbleNode): boolean {
    return bubble.nodeID === this.getFocusNodeId();
  }

  // ★ 判断连线是否属于选中分支（0.123；★ 0.173.1：焦点跟随单击选中）
  isHighlightedLine(bubble: BubbleNode): boolean {
    const focus = this.getFocusNodeId();
    // 焦点节点自身的入边高亮
    if (bubble.nodeID === focus) return true;
    // 焦点节点的出边高亮
    if (bubble.parentID === focus) return true;
    return false;
  }

  // ★ 纵向树形自动排版（0.124：全节点参与，无 isUserDragged 判断；★ 0.151：多根平铺支持）
  // ★ 0.151-bugfix3：布局算法提取到 ChatModel.layoutFlatForest 单一来源
  //   （applyCanvasModeSwitch tabs→flat 合并树也用它先排好再落盘），这里只负责调用 + 持久化
  autoLayout(): void {
    layoutFlatForest(this.store.nodeList); // 空树/无根时内部直接 return（无操作）
    // 持久化（★ 0.151：按模式分池）
    this.saveTree();
    this.redrawEdges(); // ★ 0.167.2：重排改 node.x/y → 连线重绘
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
    // ★ 0.167：节点卡片 150×68（★ 0.167.3 砍 1/4；UI_GUIDELINES 六-5），包围盒余量随之更新
    // ★ 0.167.6：垂直可用区排除顶部信息条底板（0.167.5 不透明底板盖住树 1 根气泡实测回归）——
    //   缩放与居中都基于剩余区；★ 0.167.7：底板 padding top 24→8 后高度重算——
    //   flat 底板 8+40+8=56 取 64；tabs 再加 space 8 + Tab 栏 36 = 100 取 108
    const topSafe = this.canvasModeStore.mode === 'tabs' ? 108 : 64;
    const treeW = maxX - minX + NODE_W + 32;
    const treeH = maxY - minY + NODE_H + 32;
    this.canvasScale = Math.min(this.viewW / treeW, (this.viewH - topSafe) / treeH, 1.0);

    // ★ 树几何中心对齐画布正中，-NODE_W/2 / -NODE_H/2 气泡左上角→中心补偿；去掉 Math.max 截断，树再大中心也对齐（0.130）
    // ★ 0.151-bugfix5：补偿必须乘 scale——treeCenterX 是气泡左上角坐标中心，视觉中心 = treeCenterX + NODE_W/2，
    //   居中要求 (treeCenterX + NODE_W/2) * scale + offsetX = viewW/2
    // ★ 0.167.6：垂直居中区从 topSafe 起（信息条底板下方），树顶不再钻进底板被盖
    this.canvasOffsetX = this.viewW / 2 - treeCenterX * this.canvasScale - NODE_W / 2 * this.canvasScale;
    this.canvasOffsetY = topSafe + (this.viewH - topSafe) / 2 - treeCenterY * this.canvasScale - NODE_H / 2 * this.canvasScale;
    this.redrawEdges(); // ★ 0.167.2：视口变化 → 连线重绘
  }

  // ★ 0.167：缩放控件按钮缩放（以画布中心为锚点，公式同 PinchGesture）
  // ★ 0.167.4-bugfix：限幅改方向感知——放大只拦上限 2.0、缩小只拦绝对下限 0.05。
  //   旧 0.3~2.0 双向限幅与 fitViewport（早已去掉 0.3 下限）不一致：平铺模式新建根气泡后
  //   多树并排、fitViewport 把 scale 压到 0.3 以下，此时放大（×1.2 仍 <0.3）与缩小全被
  //   return 拦死 = 缩放功能整体锁死（用户实测报 bug）。方向感知后任何 fitViewport 结果
  //   都能自由缩回正常区间。
  zoomBy(factor: number): void {
    const newScale = this.canvasScale * factor;
    if (factor > 1.0 && newScale > 2.0) {
      return; // 放大：只拦上限
    }
    if (factor < 1.0 && newScale < 0.05) {
      return; // 缩小：只拦绝对下限（防无限缩没）
    }
    const cx = this.viewW / 2;
    const cy = this.viewH / 2;
    const ratio = newScale / this.canvasScale;
    this.canvasOffsetX = cx - (cx - this.canvasOffsetX) * ratio;
    this.canvasOffsetY = cy - (cy - this.canvasOffsetY) * ratio;
    this.canvasScale = newScale;
    this.redrawEdges(); // ★ 0.167.2：缩放控件 → 连线重绘
  }

  // ★ 0.167：信息条统计——全树对话总条数
  getTotalMsgCount(): number {
    let count = 0;
    for (const node of this.store.nodeList) {
      count += node.messages.length;
    }
    return count;
  }

  // ★ 0.167：信息条分段控件切换画布模式——核心置换走 applyCanvasModeSwitch
  // （两池互转 + 落盘，同 GlobalSettingsDialog 保存路径），随后重布局 + 适配视口
  // （applyCanvasModeSwitch 置 needsRelayout，这里消费掉，避免 onShown 二次重排）
  switchCanvasMode(targetMode: CanvasMode): void {
    if (this.canvasModeStore.mode === targetMode) return;
    applyCanvasModeSwitch(targetMode);
    // ★ 0.167.8-bugfix（用户实测：点一下切过去后点不回来）：applyCanvasModeSwitch 只做
    //   两池数据置换、不写 mode（写 mode 是调用方职责，旧设置弹窗路径即两步走）——
    //   此前漏写导致切后 mode 仍为旧值：Tab 栏/分段高亮不刷新，再点目标按钮被
    //   「mode === targetMode」守卫直接 return = 切换单向锁死。补写 mode 对齐旧路径。
    this.canvasModeStore.mode = targetMode;
    if (this.store.needsRelayout) {
      this.autoLayout();
      this.fitViewport();
      this.store.needsRelayout = false;
    }
  }

  // ★ 0.151：模式 A【添加根气泡】——新增顶级根节点（=一棵新树）
  // ★ 0.151-bugfix3：新根加入后统一 autoLayout 重排（多根 y=0 并排）——旧逻辑只把新根
  //   放 maxX+200、y=0，不重排既有根（默认气泡 y=200 与新根 y=0 不同排，用户实测 bug1）；
  //   autoLayout 末尾自带 saveTree，无需单独保存
  addRootBubble(): void {
    const root = new BubbleNode(generateNodeId(), null, [], 200, 0); // x 初始值无所谓，autoLayout 会重排
    this.store.nodeList.push(root);
    recordStat(this.statStore, 'bubble', 0, 0); // ★ 0.192.0：统计埋点——新建树（根气泡）+1
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
    recordStat(this.statStore, 'bubble', 0, 0); // ★ 0.192.0：统计埋点——新增 Tab（自带新树）+1
    tabs.push({ id: tabId, name: getRootDisplayName(root), treeJson: serializeBubbleTree(tree) }); // ★ 0.151-bugfix2：Tab 名 = 树根显示名（空白新根 =「空气泡」，与根气泡文字一致；重命名 Tab 即给树起名）
    this.tabForest.tabsJson = serializeTabs(tabs);
    upsertCloudData('tabs_pool', this.tabForest.tabsJson); // ★ 0.165.1：云同步桥接（新增 Tab 后 Tab 池上云）
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
          upsertCloudData('tabs_pool', this.tabForest.tabsJson); // ★ 0.165.1：云同步桥接（删 Tab 后 Tab 池上云）
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
        upsertCloudData('tabs_pool', this.tabForest.tabsJson); // ★ 0.165.1：云同步桥接（Tab 重命名后 Tab 池上云）
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

  // ══════════════════════════════════════════════════════════
  // ★ 0.168：左侧边栏（Pixso 工作台稿：平板 Frame_2_59 宽 208 / 手机 Frame_2_215 宽 72）
  // 导航：画布（当前页选中态）/ 单词库 / 知识库（pushPath 压栈——目标页返回按钮是 pop()，
  // 天然「哪进哪回」：边栏进回画布、对话页右上角进回对话页，用户拍板）；底部：设置 + 账号
  // ══════════════════════════════════════════════════════════


  /** 边栏导航分发（★ 0.168「哪进哪回」：pushPath 压栈 + 目标页 pop 返回 = 从哪个入口进就回哪个入口；
      ★ 0.180：跳转单词库/知识库不收抽屉——页面被覆盖期间 sidebarVisible 保留，返回画布时边栏保持打开） */
  onNavClick(kind: string): void {
    if (kind === 'wordbank') {
      // 不收抽屉：pop 返回后边栏原样在
      this.pathStack.pushPath({ name: 'WordBankPage' });
    } else if (kind === 'knowledge') {
      // 不收抽屉：同上，返回时边栏保持
      this.pathStack.pushPath({ name: 'KnowledgeBankPage' });
    } else if (kind === 'review') {
      // ★ 0.196.1：知识复习页（不收抽屉，同词库/知识库）
      this.pathStack.pushPath({ name: 'ReviewPage' });
    } else if (kind === 'statistics') {
      // ★ 0.192.0：统计页（不收抽屉，同词库/知识库）
      this.pathStack.pushPath({ name: 'StatisticsPage' });
    } else if (kind === 'billing') {
      // ★ 0.194.0：账单页（不收抽屉，同词库/知识库）
      this.pathStack.pushPath({ name: 'BillingPage' });
    } else if (kind === 'settings') {
      this.closeSidebar();
      this.globalSettingsVisible = true;
    } else if (kind === '') {
      // ★ 0.195.0：点边栏空白（AppSideBar 根 onClick）——手机收抽屉
      this.closeSidebar();
    } else {
      // 气泡树 = 当前页：手机收抽屉回画布
      this.closeSidebar();
    }
  }


  /** 手机抽屉开（translate 滑入动画） */
  openSidebar(): void {
    if (this.sidebarVisible) {
      return;
    }
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.sidebarVisible = true;
    });
  }

  /** 手机抽屉收（translate 滑出动画；平板常驻态幂等） */
  closeSidebar(): void {
    if (!this.sidebarVisible) {
      return;
    }
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseIn }, () => {
      this.sidebarVisible = false;
    });
  }





  // ★ 0.168：手机抽屉层（Stack 挂画布区顶层）——点遮罩收起；平板不渲染
  // ★ 0.168.4：唤出改画布左下角固定 ☰ 按钮（用户拍板）——边缘右滑热区整块删除：
  //   系统手势区占用左缘约 0~65px（快滑=系统返回/慢拖被吞不透传），右滑唤出真机体验受限；
  //   ☰ 按钮落在画布内容层缩放控件旁（同坐标系保证底缘对齐），不在此层
  @Builder
  MobileDrawerLayer() {
    if (!this.isTablet) {
      // 遮罩（点按收起；进出场淡入淡出）
      if (this.sidebarVisible) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.45)')
          .onClick(() => {
            this.closeSidebar();
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 220 }))
      }
      // ★ 0.195.0：边栏浮层改共享组件 AppSideBar（translate 由包裹层承担，随 sidebarVisible 滑入滑出）
      Column() {
        AppSideBar({
          currentRoute: 'BBTreeCanvas', // ★ 0.195.0 bugfix：抽屉只能从画布唤出——人就在画布上，恒高亮气泡树
          onNavClick: (kind: string) => {
            this.onNavClick(kind);
          }
        })
      }
      .translate({ x: this.sidebarVisible ? 0 : -208 })
    }
  }

  // ★ 0.167.2：分段控件 @Builder（画布/选项卡模式切换，UI_GUIDELINES 六-8）
  // ★ 0.167.6 用户拍板：小屏（viewW<520）icon-only——删「画布/选项卡」文字只留图标
  //   （呼应手机稿图标式双按钮：gitbranch + layers），选项固定 30×30、track 总高 36
  //   与 ⚙/➕ 等高对齐；中大屏保持 icon+文字
  @Builder
  SegmentedControl() {
    Row({ space: 4 }) {
      if (this.viewW >= 520) {
        // 中大屏：icon + 文字（0.167.2 原版）
        Row({ space: 4 }) {
          Image($r('app.media.gitbranch'))
            .width(14)
            .height(14)
            .objectFit(ImageFit.Contain)
          Text('平铺') // ★ 0.167.8 用户拍板：「画布」改「平铺」（与「选项卡」对仗，模式语义更准）
            .fontSize(FONT_SIZE_BODY)
            .fontWeight(this.canvasModeStore.mode === 'flat' ? 600 : 500)
            .fontFamily(this.canvasModeStore.mode === 'flat' ? FONT_INTER_SEMIBOLD : FONT_INTER)
            .fontColor(this.canvasModeStore.mode === 'flat' ? TEXT_PRIMARY : TEXT_SECONDARY)
        }
        .padding({ left: 12, right: 12 })
        .height(30) // ★ 0.167.8：固定高 30（track padding 3 总高 36），与 ⚙/➕ 等高对齐（用户实测报高度不齐）
        .borderRadius(8)
        .backgroundColor(this.canvasModeStore.mode === 'flat' ? BRAND_PRIMARY : Color.Transparent)
        .onClick(() => {
          this.switchCanvasMode('flat');
        })
        Row({ space: 4 }) {
          Image($r('app.media.layers'))
            .width(14)
            .height(14)
            .objectFit(ImageFit.Contain)
          Text('选项卡')
            .fontSize(FONT_SIZE_BODY)
            .fontWeight(this.canvasModeStore.mode === 'tabs' ? 600 : 500)
            .fontFamily(this.canvasModeStore.mode === 'tabs' ? FONT_INTER_SEMIBOLD : FONT_INTER)
            .fontColor(this.canvasModeStore.mode === 'tabs' ? TEXT_PRIMARY : TEXT_SECONDARY)
        }
        .padding({ left: 12, right: 12 })
        .height(30) // ★ 0.167.8：固定高 30（track padding 3 总高 36），与 ⚙/➕ 等高对齐（用户实测报高度不齐）
        .borderRadius(8)
        .backgroundColor(this.canvasModeStore.mode === 'tabs' ? BRAND_PRIMARY : Color.Transparent)
        .onClick(() => {
          this.switchCanvasMode('tabs');
        })
      } else {
        // 小屏：icon-only 30×30（★ 0.167.6）——无文字，居中
        Row() {
          Image($r('app.media.gitbranch'))
            .width(14)
            .height(14)
            .objectFit(ImageFit.Contain)
        }
        .width(30)
        .height(30)
        .justifyContent(FlexAlign.Center)
        .borderRadius(8)
        .backgroundColor(this.canvasModeStore.mode === 'flat' ? BRAND_PRIMARY : Color.Transparent)
        .onClick(() => {
          this.switchCanvasMode('flat');
        })
        Row() {
          Image($r('app.media.layers'))
            .width(14)
            .height(14)
            .objectFit(ImageFit.Contain)
        }
        .width(30)
        .height(30)
        .justifyContent(FlexAlign.Center)
        .borderRadius(8)
        .backgroundColor(this.canvasModeStore.mode === 'tabs' ? BRAND_PRIMARY : Color.Transparent)
        .onClick(() => {
          this.switchCanvasMode('tabs');
        })
      }
    }
    .padding(3)
    .borderRadius(RADIUS_CONTROL)
    .backgroundColor(SEGMENTED_TRACK)
  }

  build() {
    NavDestination() {
      // ★ 0.168：根 Row——平板 [边栏 208 常驻 + 画布区]；手机画布区全宽 + 抽屉层挂 Stack 顶层（Pixso 工作台稿）
      Row() {
        // ★ 0.195.0：平板边栏常驻分支删除——边栏升 Index 级（大屏全页面常驻，页面平移不遮，用户定稿）；
        //   本页只留画布区（手机抽屉层不变），画布区自动占满 Navigation 右侧区域
      // ★ 0.168.3：抽屉层容器 overlay→Stack——overlay 层内容真机实证不参与 hit test（当时左缘
      //   热区 drag 穿透到画布平移手势；热区已于 0.168.4 删除），Stack 子节点命中是标准行为
      //   （同画布内四弹窗结构），结构保留供遮罩/边栏命中优先于画布
      Stack({ alignContent: Alignment.TopStart }) {
      // ★ 0.167：全屏 BG_APP 底 + 画布容器（margin 24 / 圆角 24 / BG_CANVAS，UI_GUIDELINES 五-平板）
      Column() {
        Stack() {
          Stack({ alignContent: Alignment.TopStart }) {
        // ── 连线层（★ 0.167：贝塞尔 + 箭头，UI_GUIDELINES 六-7；普通=主紫 85%，高亮分支=辅助紫） ──
        // ★ 0.167.2 真根因修复：弃 Path 改 Canvas 命令式绘制——Path 无 viewport 属性（编译报错证实），
        //   且未设 viewport 时 ArkUI 自动把 commands 包围盒缩放适配到组件尺寸（实测因子≈0.32），
        //   连线被二次缩放飞到画布左上角；Canvas 2D 绘制坐标 1:1 映射组件 vp 坐标系，无隐式变换。
        //   Canvas 无状态绑定 → 所有几何/颜色变化点手动调 redrawEdges()（见该方法注释）
        Canvas(this.edgeContext)
          .width('100%')
          .height('100%')
          .onReady(() => {
            this.edgeReady = true;
            this.redrawEdges();
          })

        // ── 气泡层（屏幕坐标；★ 0.167：节点卡片 200×68，UI_GUIDELINES 六-5/六-6） ──
        ForEach(this.store.nodeList, (bubble: BubbleNode) => {
          Row({ space: 10 }) {
            // ★ 0.167.3：根节点保留图标容器（树的视觉锚点），子节点改竖线（用户拍板：美观 + 节约左右空间）
            if (bubble.parentID === null) {
              Column() {
                Image($r('app.media.gitbranch'))
                  .width(18)
                  .height(18)
              }
              .width(NODE_ICON)
              .height(NODE_ICON)
              .borderRadius(RADIUS_LOGO)
              .linearGradient({ angle: 225, colors: [[BRAND_PRIMARY, 0], [BRAND_SECONDARY, 1]] })
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            } else {
              // 竖线：与连线同色（EDGE_COLOR）——视觉语言「连线的化身」；宽 3 高 40 圆角 1.5，
              // 比图标容器省 37vp 宽度给文字区（layoutWeight(1) 自动扩展）
              Column()
                .width(3)
                .height(NODE_ICON)
                .borderRadius(1.5)
                .backgroundColor(EDGE_COLOR)
            }
            // 标题 + 信息行（选中态信息行换「双击进入对话」辅助紫，UI_GUIDELINES 六-6）
            Column({ space: 3 }) {
              Text(this.getBubbleTitle(bubble))
                .fontSize(FONT_SIZE_CARD_TITLE)
                .fontWeight(600)
                .fontFamily(FONT_INTER_SEMIBOLD)
                .fontColor(TEXT_PRIMARY)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.isBubbleSelected(bubble)) {
                Text('双击进入') // ★ 0.195.0：「双击进入对话」→「双击进入」（用户拍板：根气泡两行不可接受，砍字保一行）
                  .fontSize(FONT_SIZE_META)
                  .fontFamily(FONT_INTER)
                  .fontColor(BRAND_SECONDARY)
              } else {
                // ★ 0.172.3：元信息行加最近消息时间（参考图「N 条对话 · X小时前」）；maxLines(1) 防长文本撑破 68 高卡片
                Text(this.getBubbleMeta(bubble))
                  .fontSize(FONT_SIZE_META)
                  .fontFamily(FONT_INTER)
                  .fontColor(TEXT_SECONDARY)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            // 选中态右侧 chevron（UI_GUIDELINES 六-6；★ 0.173.1：判断统一走 isBubbleSelected）
            if (this.isBubbleSelected(bubble)) {
              Image($r('app.media.chevronright'))
                .width(16)
                .height(16)
            }
          }
          .width(NODE_W)
          .height(NODE_H)
          .padding({ top: 12, bottom: 12, left: 14, right: 14 })
          .borderRadius(RADIUS_NODE)
          // 选中态 = 悬停态规格：SURFACE_HOVER 底 + STROKE_BRAND 描边 + 阴影（UI_GUIDELINES 六-6；★ 0.173.1：单击选中同款）
          .backgroundColor(this.isBubbleSelected(bubble) ? SURFACE_HOVER : SURFACE_NODE)
          .border({
            width: 1,
            color: this.isBubbleSelected(bubble) ? STROKE_BRAND : STROKE_CARD
          })
          .shadow(this.isBubbleSelected(bubble)
            ? { radius: 24, color: 'rgba(0,0,0,0.45)', offsetX: 0, offsetY: 10 }
            : { radius: 0, color: 'rgba(0,0,0,0)', offsetX: 0, offsetY: 0 })
          .position({
            x: this.c2sX(bubble.x),
            y: this.c2sY(bubble.y)
          })
          // ★ 0.167.4：整体等比缩放（传统思维导图模式，用户拍板）——渲染层 scale 变换锚点左上，
          //   气泡视觉尺寸 = NODE_W*s × NODE_H*s（内部字号/图标/竖线零改动，整体等比）；
          //   布局层间隙 siblingGap=40 恒正 → 等比变换下间隙 40*s 永远为正，重叠在数学上不可能
          .scale({
            x: this.canvasScale,
            y: this.canvasScale,
            centerX: 0,
            centerY: 0
          })
          // ── 单击选中 + 手动双击进入（★ 0.173.2：系统 TapGesture(count:2) 与单击手势并列绑定时，
          //    ArkUI 手势仲裁让单击第一击抬起即识别成功、吃掉双击识别流（真机实证双击失效），
          //    改为单击手势内手动判定：同一气泡两次单击间隔 <300ms = 双击进入对话；否则 = 单击选中。
          //    单击选中即时反馈；双击时第一击先高亮、第二击进入，视觉衔接自然） ──
          .gesture(
            TapGesture({ count: 1 })
              .onAction(() => {
                const now = Date.now();
                // 双击路径：进入对话（导航前清本地选中，交棒 current 选中语义）
                if (this.lastTapNodeId === bubble.nodeID && now - this.lastTapTime < 300) {
                  this.lastTapNodeId = '';
                  this.lastTapTime = 0;
                  this.selectedNodeId = '';
                  this.currentBubbleStore.nodeID = bubble.nodeID;
                  this.currentBubbleStore.bubbleX = bubble.x;
                  this.currentBubbleStore.bubbleY = bubble.y;
                  this.pathStack.pushPath({ name: 'ChatPage' });
                  return; // 双击路径不记录本次 tap（防从对话页返回后再点同气泡误判双击）
                }
                // 单击路径：立即选中（高亮卡片+「双击进入对话」+连线高亮，与「进入后返回」选中样式一致）
                this.selectedNodeId = bubble.nodeID;
                this.redrawEdges(); // Canvas 无状态绑定 → 焦点变化手动重绘连线高亮
                this.lastTapNodeId = bubble.nodeID;
                this.lastTapTime = now;
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
          .clip(true) // ★ 0.126：裁剪画布溢出内容（连线/气泡不越出画布容器圆角）
          // ★ 0.130 获取画布可视区真实宽高；首次拿到尺寸时自动适配全树视口（替代原 aboutToAppear）
          .onAreaChange((oldVal: Area, newVal: Area) => {
            this.viewW = newVal.width as number;
            this.viewH = newVal.height as number;
            if ((oldVal.width as number) <= 0 && this.viewW > 0) {
              // ★ 0.195.0 bugfix：首次就绪先重排再适配视口——冷启动直接渲染持久化旧坐标，
              //   历史遗留散落坐标（模式切换池重建/旧版布局算法产物）不重排就散落各处
              //   （用户实测：4 根气泡右上/中/下散布，新建根正常=新建自带 autoLayout）。
              //   画布无手动拖拽定位特性，入场规范化安全；空树内部 no-op
              this.autoLayout();
              this.fitViewport();
            }
            this.redrawEdges(); // ★ 0.167.2：组件尺寸变化 Canvas 缓冲区跟随 → 重绘
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
                this.redrawEdges(); // ★ 0.167.2：平移 → 连线跟随重绘
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
                // ★ 0.167.4-bugfix：限幅改方向感知（同 zoomBy）——放大只拦上限 2.0、缩小只拦
                //   绝对下限 0.05；旧 0.3~2.0 双向限幅在 fitViewport 压低 scale 后把捏合锁死
                const isZoomIn = newScale > this.canvasScale;
                if ((isZoomIn && newScale > 2.0) || (!isZoomIn && newScale < 0.05)) {
                  return;
                }
                // 以捏合中心为锚点，保持该点不动调整 offset
                const ratio = newScale / this.canvasScale;
                this.canvasOffsetX = event.pinchCenterX - (event.pinchCenterX - this.canvasOffsetX) * ratio;
                this.canvasOffsetY = event.pinchCenterY - (event.pinchCenterY - this.canvasOffsetY) * ratio;
                this.canvasScale = newScale;
                this.redrawEdges(); // ★ 0.167.2：捏合缩放 → 连线跟随重绘
              })
          )
          // ── 空白双击放大（★ 0.182.0 需求5；★ 0.182.1 用户实测两连调）──
          // 双击 = 按一次 + 号（1.25，0.182.1 从两档 1.25² 收敛——两档太猛），与 + 号共用 2.0 上限（不无限放大）；
          // 中心移动：双击点只向视口中心走近 1/3 距离（0.182.1——直接跳到中心太唐突，走 1/3 缓动更流畅舒服）。
          // 实现：容器 onClick + 手动 <300ms 双击判定（同气泡 0.173.2 先例模式）——
          // TapGesture 的 GestureEvent 无 x/y 位置属性（编译实证），ClickEvent.x/y 为组件局部坐标
          // 与 viewW/viewH 同系；点气泡被气泡自身手势消费不落此处，正好符合「空白处」语义；
          // 与 PanGesture 共存：拖动超阈值后点击识别失败不误触。
          .onClick((event: ClickEvent) => {
            const now = Date.now();
            const isDoubleTap = now - this.lastCanvasTapTime < 300;
            this.lastCanvasTapTime = now;
            if (!isDoubleTap) {
              return; // 单击：只记录时间戳（双击判定窗口），无副作用
            }
            this.lastCanvasTapTime = 0; // 双击后清零（防三击连触再放大）
            const oldScale = this.canvasScale;
            let newScale = oldScale * 1.25; // 一档（0.182.1：原两档 1.25² 用户实测太猛收敛）
            if (newScale > 2.0) {
              newScale = 2.0; // 与 + 号同上限
            }
            if (newScale <= oldScale) {
              return; // 已到上限：双击无效果（与 + 号到顶行为一致）
            }
            // 组件 → 画布：c = (p - offset) / scale；目标屏点 p' = p + (C - p)/3（向中心走 1/3），
            // offset' = p' - c × scale'（放大后该画布点正好落在 p'——双击点向中心缓动 1/3 而非跳到中心）
            const cx = (event.x - this.canvasOffsetX) / oldScale;
            const cy = (event.y - this.canvasOffsetY) / oldScale;
            const targetX = event.x + (this.viewW / 2 - event.x) / 3;
            const targetY = event.y + (this.viewH / 2 - event.y) / 3;
            this.canvasOffsetX = targetX - cx * newScale;
            this.canvasOffsetY = targetY - cy * newScale;
            this.canvasScale = newScale;
            this.redrawEdges(); // 缩放 → 连线跟随重绘
          })

          // ★ 0.167：信息条 + Tab 栏（UI_GUIDELINES 五/六-8/六-9；悬浮画布容器内 position(28,24)）
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              // ★ 0.176.0：返回箭头「←」删除（用户拍板，全设备尺寸）——侧边栏工作台 0.168
              //   落地后画布即主页面，无上级页面可返（原 pop() 回 Index 入口已由边栏导航承担）
              // 标题 + 统计（ScreenTitle 16 SemiBold + Meta 11，UI_GUIDELINES 三/六）
              // ★ 0.167.6 曾小屏不渲染标题（只留 4 图标）；★ 0.167.8 用户拍板加回——
              //   「气泡树 + N 个气泡 · N 条对话」小屏左上方也要显示（用户夸平板好看），
              //   layoutWeight(1) 弹性收缩 + maxLines(1) 保证右侧 4 图标永不溢出
              // ★ 0.178.0：标题「知识画布」→「气泡树」（用户拍板）
              Column({ space: 2 }) {
                Text('气泡树')
                  .fontSize(FONT_SIZE_SCREEN_TITLE)
                  .fontWeight(600)
                  .fontFamily(FONT_INTER_SEMIBOLD)
                  .fontColor(TEXT_PRIMARY)
                  .maxLines(1)
                Text(`${this.store.nodeList.length} 个气泡 · ${this.getTotalMsgCount()} 条对话`)
                  .fontSize(FONT_SIZE_META)
                  .fontFamily(FONT_INTER)
                  .fontColor(TEXT_SECONDARY)
                  .maxLines(1)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              // 分段控件（★ 0.167.5 用户拍板：全设备放主行 ⚙ 左边——收回 0.167.2 手机挪第二行方案）
              this.SegmentedControl()
              // ★ 0.168：⚙ 设置按钮删除——设置入口移至左侧边栏底部（用户拍板，顺带缓解右上角拥挤）
              // + 新建气泡（UI_GUIDELINES 六-9；行为按模式：平铺=新树 / 选项卡=新 Tab）
              // ★ 0.167.5 用户拍板：恢复双态（收回 0.167.3 统一纯图标）——小屏（viewW<520）
              //   36×36 纯 icon；中大屏 icon+文字「新建气泡」充实一点
              // ★ 0.195.0：新建按钮改单词库同款 +（用户拍板：「单词库的加号很漂亮很显眼，放到气泡树右边」）——
              //   Button('+') fontSize 20 透明底白字与单词库顶栏完全同款；行为不变（平铺=新树/选项卡=新 Tab），
              //   原 plus0 svg+文字 pill 双态分支随删（UI 统一不分屏宽）
              Button('+')
                .fontSize(20)
                .backgroundColor(Color.Transparent)
                .fontColor(TEXT_PRIMARY)
                .padding({ left: 8, right: 8 })
                .onClick(() => {
                  if (this.canvasModeStore.mode === 'tabs') {
                    this.addTab();
                  } else {
                    this.addRootBubble();
                  }
                })
            }
            .width('100%')

            // Tab 栏（仅选项卡模式；横向滚动、✕ 删除、长按重命名——交互全保留）
            if (this.canvasModeStore.mode === 'tabs') {
              Row() {
                Scroll() {
                  Row({ space: 8 }) {
                    ForEach(parseTabs(this.tabForest.tabsJson), (tab: TabMeta) => {
                      // ★ 0.191.0：Tab 栏 pill 重设计已回滚（用户验收不通过，等参考其他 UI 后再定方案）
                      Row() {
                        Text(tab.name)
                          .fontSize(FONT_SIZE_BODY)
                          .fontWeight(tab.id === this.tabForest.activeTabId ? 600 : 400)
                          .fontFamily(tab.id === this.tabForest.activeTabId ? FONT_INTER_SEMIBOLD : FONT_INTER)
                          .fontColor(tab.id === this.tabForest.activeTabId ? TEXT_PRIMARY : TEXT_SECONDARY)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .constraintSize({ maxWidth: 72 })
                        Text('✕')
                          .fontSize(11)
                          .fontColor(tab.id === this.tabForest.activeTabId ? 'rgba(255,255,255,0.75)' : TEXT_TERTIARY)
                          .margin({ left: 4 })
                          .onClick(() => {
                            this.deleteTab(tab.id);
                          })
                      }
                      .padding({ left: 10, right: 6, top: 8, bottom: 8 })
                      .borderRadius(8)
                      .backgroundColor(tab.id === this.tabForest.activeTabId ? BRAND_PRIMARY : SURFACE_HOVER)
                      .border({ width: 1, color: tab.id === this.tabForest.activeTabId ? BRAND_PRIMARY : STROKE_CARD })
                      .onClick(() => {
                        this.switchTab(tab.id);
                      })
                      .gesture(
                        LongPressGesture({ duration: 500 })
                          .onAction(() => {
                            this.openTabRename(tab.id);
                          })
                      )
                    }, (tab: TabMeta) => tab.id)
                  }
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
                .layoutWeight(1)
                .height(36)
                .align(Alignment.Start)
              }
              .width('100%')
            }
          }
          // ★ 0.167.5 用户拍板：信息条加不透明底板（BG_CANVAS 与画布同色=视觉隐形）——
          //   气泡树平移/缩放时永远被压在底板下面，不再穿透重叠（用户要的「隐形的线」）；
          //   底板从画布 (0,0) 全宽铺开（原 position(28,24) 改 padding 内缩，内容视觉位置不变）
          .width('100%')
          // ★ 0.167.7：①上方留白 24→8 与下方对齐 ②right 28→14 右上角 4 按钮右移
          // ★ 0.167.8：小屏 left 28→14——返回箭头左移，左留白与右边 ➕（14）一致（用户拍板）
          // ★ 0.176.0：返回箭头已删（全设备），padding 保持不变——标题成为行首元素
          .padding({ left: this.viewW >= 520 ? 28 : 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor(BG_CANVAS)
          .position({ x: 0, y: 0 })

          // ★ 0.167：缩放控件（UI_GUIDELINES 六-10；右下角悬浮：放大/缩小/适应全图）
          Column({ space: 4 }) {
            Row() {
              Image($r('app.media.plus'))
                .width(20)
                .height(20)
            }
            .width(40)
            .height(40)
            .borderRadius(RADIUS_CONTROL)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.zoomBy(1.25);
            })
            Row() {
              Image($r('app.media.minus'))
                .width(20)
                .height(20)
            }
            .width(40)
            .height(40)
            .borderRadius(RADIUS_CONTROL)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.zoomBy(1 / 1.25);
            })
            Row() {
              Image($r('app.media.maximize'))
                .width(20)
                .height(20)
            }
            .width(40)
            .height(40)
            .borderRadius(RADIUS_CONTROL)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.fitViewport();
            })
          }
          .padding(4)
          .borderRadius(14)
          .border({ width: 1, color: STROKE_CARD })
          .backgroundColor(SURFACE_NODE)
          .shadow({ radius: 20, color: 'rgba(0,0,0,0.35)', offsetX: 0, offsetY: 8 })
          .visibility(this.viewW > 0 ? Visibility.Visible : Visibility.None)
          .position({ x: this.viewW - 14 - 48, y: this.viewH - 24 - 132 }) // ★ 0.170.1：右缘贴边 24→14（用户要求往右靠边一点，与信息条边距 14 对齐）

          // ★ 0.168.4：左下角固定 ☰ 唤出按钮（手机抽屉唯一入口；用户拍板取消边缘右滑——
          //   系统手势区占用左缘约 0~65px，快滑=系统返回/慢拖被吞，右滑唤出真机体验受限）；
          //   样式对齐右下角缩放控件（40×40 圆角按钮 + padding 4 容器 + SURFACE_NODE 底/描边/阴影），
          //   同坐标系：x 14 与缩放控件右缘 14 镜像（★ 0.170.1 双双贴边 24→14，用户要求靠边一点）；
          //   y=viewH-24-44（高 48 → 底缘 viewH-20，
          //   与缩放控件底缘 viewH-24-132+136 严格对齐）；抽屉开时被遮罩盖住变暗（同缩放控件行为）
          if (!this.isTablet) {
            Column() {
              Row() {
                // ★ 0.190.2：Text('☰') 字符换回 0.168.4 原始 menu.svg 图标资源（用户反馈：字符
                //   版偏小且不居中，「之前那个就很好看」——git 考古 4bba3c9 实锤原始即此图标 18×18）
                Image($r('app.media.menu'))
                  .width(20)
                  .height(20)
              }
              .width(40)
              .height(40)
              .borderRadius(RADIUS_CONTROL)
              .justifyContent(FlexAlign.Center)
              .onClick(() => {
                this.openSidebar();
              })
            }
            .padding(4)
            .borderRadius(14)
            .border({ width: 1, color: STROKE_CARD })
            .backgroundColor(SURFACE_NODE)
            .shadow({ radius: 20, color: 'rgba(0,0,0,0.35)', offsetX: 0, offsetY: 8 })
            .visibility(this.viewW > 0 ? Visibility.Visible : Visibility.None)
            .position({ x: 14, y: this.viewH - 24 - 44 }) // ★ 0.170.1：左缘贴边 24→14（用户要求往左靠边一点）
          }

      // ★ 0.167：平铺/选项卡两套自绘标题行（0.151-D）已删除——统一由上方信息条
      //   （分段控件切换模式 + 新建气泡按钮）+ Tab 栏 + 右下角缩放控件承担（UI_GUIDELINES 五/六）

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

      // ★ 0.147：长按气泡操作菜单（修改标题 / 删除气泡；★ 0.167 换肤 UI_GUIDELINES，token 单一来源）
      if (this.menuVisible) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.45)') // ★ 0.167：遮罩加深（原 0.25）
            .onClick(() => {
              this.menuVisible = false;
            })
          Column() {
            Text('修改气泡标题')
              .fontSize(FONT_SIZE_CARD_TITLE)
              .fontFamily(FONT_INTER)
              .fontColor(TEXT_PRIMARY)
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
              .color(STROKE_CARD)
            Text('删除气泡')
              .fontSize(FONT_SIZE_CARD_TITLE)
              .fontFamily(FONT_INTER)
              .fontColor('#F44336') // 删除项警示红（UI_GUIDELINES 无 token，保留）
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
          .borderRadius(12) // 弹窗浮层圆角（UI_GUIDELINES 无弹窗规格，沿用 12）
          .backgroundColor(SURFACE_NODE)
          .border({ width: 1, color: STROKE_CARD })
          .shadow({ radius: 24, color: 'rgba(0,0,0,0.45)', offsetX: 0, offsetY: 10 })
        }
      }

      // ★ 0.147：标题编辑弹窗（最多 15 字，清空保存恢复自动标题；★ 0.167 换肤 UI_GUIDELINES）
      if (this.titleEditVisible) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.45)') // ★ 0.167：遮罩加深（原 0.25）
            .onClick(() => {
              this.titleEditVisible = false;
            })
          Column() {
            Text('修改气泡标题')
              .fontSize(FONT_SIZE_SCREEN_TITLE)
              .fontWeight(600)
              .fontFamily(FONT_INTER_SEMIBOLD)
              .fontColor(TEXT_PRIMARY)
              .margin({ bottom: 12 })
            TextInput({ text: this.titleEditText, placeholder: '输入标题（最多15字，清空恢复自动）' })
              .fontSize(FONT_SIZE_BODY)
              .fontFamily(FONT_INTER)
              .fontColor(TEXT_PRIMARY)
              .placeholderColor(TEXT_TERTIARY)
              .maxLength(15)
              .onChange((value: string) => {
                this.titleEditText = value;
              })
              .width('100%')
              .height(44)
              .borderRadius(RADIUS_CONTROL)
              .backgroundColor(SURFACE_HOVER)
              .margin({ bottom: 16 })
            Row({ space: 12 }) {
              Button('取消')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontFamily(FONT_INTER)
                .height(38)
                .layoutWeight(1)
                .backgroundColor(SURFACE_HOVER)
                .fontColor(TEXT_PRIMARY)
                .onClick(() => {
                  this.titleEditVisible = false;
                })
              Button('确定')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontFamily(FONT_INTER)
                .height(38)
                .layoutWeight(1)
                .backgroundColor(BRAND_PRIMARY)
                .fontColor('#FFFFFF')
                .onClick(() => {
                  this.saveNodeTitle();
                })
            }
            .width('100%')
          }
          .width('70%')
          .padding(20)
          .borderRadius(12) // 弹窗浮层圆角（UI_GUIDELINES 无弹窗规格，沿用 12）
          .backgroundColor(SURFACE_NODE)
          .border({ width: 1, color: STROKE_CARD })
          .shadow({ radius: 24, color: 'rgba(0,0,0,0.45)', offsetX: 0, offsetY: 10 })
        }
      }

      // ★ 0.151：Tab 重命名弹窗（长按 Tab 触发；最多 12 字，空名不覆盖；★ 0.167 换肤 UI_GUIDELINES）
      if (this.tabRenameVisible) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.45)') // ★ 0.167：遮罩加深（原 0.25）
            .onClick(() => {
              this.tabRenameVisible = false;
            })
          Column() {
            Text('重命名选项卡')
              .fontSize(FONT_SIZE_SCREEN_TITLE)
              .fontWeight(600)
              .fontFamily(FONT_INTER_SEMIBOLD)
              .fontColor(TEXT_PRIMARY)
              .margin({ bottom: 12 })
            TextInput({ text: this.tabRenameText, placeholder: '输入名称（最多12字）' })
              .fontSize(FONT_SIZE_BODY)
              .fontFamily(FONT_INTER)
              .fontColor(TEXT_PRIMARY)
              .placeholderColor(TEXT_TERTIARY)
              .maxLength(12)
              .onChange((value: string) => {
                this.tabRenameText = value;
              })
              .width('100%')
              .height(44)
              .borderRadius(RADIUS_CONTROL)
              .backgroundColor(SURFACE_HOVER)
              .margin({ bottom: 16 })
            Row({ space: 12 }) {
              Button('取消')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontFamily(FONT_INTER)
                .height(38)
                .layoutWeight(1)
                .backgroundColor(SURFACE_HOVER)
                .fontColor(TEXT_PRIMARY)
                .onClick(() => {
                  this.tabRenameVisible = false;
                })
              Button('确定')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontFamily(FONT_INTER)
                .height(38)
                .layoutWeight(1)
                .backgroundColor(BRAND_PRIMARY)
                .fontColor('#FFFFFF')
                .onClick(() => {
                  this.saveTabRename();
                })
            }
            .width('100%')
          }
          .width('70%')
          .padding(20)
          .borderRadius(12) // 弹窗浮层圆角（UI_GUIDELINES 无弹窗规格，沿用 12）
          .backgroundColor(SURFACE_NODE)
          .border({ width: 1, color: STROKE_CARD })
          .shadow({ radius: 24, color: 'rgba(0,0,0,0.45)', offsetX: 0, offsetY: 10 })
        }
      }
        }
        // ★ 0.167：画布容器属性（UI_GUIDELINES 五-平板：margin 24 / 圆角 24 / BG_CANVAS）
        .width('100%')
        .layoutWeight(1)
        // ★ 0.195.0：顶格修复——顶边距 24→0（用户多次报「信息条上方空一行」：Pad 实测 88→147px
        //   共 59px BG_APP 色带露在 BG_CANVAS 信息条上方，即本 margin 顶边；左右/底 24 保留）
        .margin({ left: 24, right: 24, top: 0, bottom: 24 })
        // ★ 0.195.0：顶部圆角随顶格归零（面板贴顶不露角缺口），底部圆角保留
        .borderRadius({ topLeft: 0, topRight: 0, bottomLeft: RADIUS_CANVAS, bottomRight: RADIUS_CANVAS })
        .backgroundColor(BG_CANVAS)
      }
      // ★ 0.167：全屏底色（UI_GUIDELINES 五-平板：应用底 BG_APP）
      // ★ 0.168.3：Column 改 width/height 100%——layoutWeight 仅 Row/Column/Flex 子节点有效，
      //   随 Column 外包 Stack 移交外层 Stack；Stack 内 Column 100% 撑满即原全宽效果
      .width('100%')
      .height('100%')
      .backgroundColor(BG_APP)
      // ★ 0.168.3：手机抽屉层（点遮罩或边栏空白收起；平板不渲染；唤出=左下角 ☰ 按钮 ★ 0.168.4）——
      //   从 overlay 迁至 Stack 顶层子节点，命中优先于画布
      this.MobileDrawerLayer()
      }
      // ★ 0.168：平板给边栏 208 让位；手机 Row 内独占即全宽（layoutWeight 随 Column 移至 Stack）
      .layoutWeight(1)
      .height('100%')
      }
      .width('100%')
      .height('100%')
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
      // ★ 0.168：手机抽屉打开时返回键先收抽屉（回画布），不直接退出
      if (this.sidebarVisible) {
        this.closeSidebar();
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
      // ★ 0.167.2：从 ChatPage 返回时选中节点可能变化 → 连线高亮色需重绘
      // （needsRelayout 为 false 时 autoLayout/fitViewport 不触发，此处无条件兜底）
      this.redrawEdges();
    })
  }
}
