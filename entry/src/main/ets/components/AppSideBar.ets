// AppSideBar.ets — ★ 0.195.0：应用边栏共享组件（从 BBTreeCanvas.SideBarPanel 抽取）
// 宿主两种形态（用户定稿「大屏边栏常驻，页面平移，体验非常棒」）：
//   ① Index 大屏常驻——平板/PC 边栏一直存在，页面在右侧 Navigation 区域平移不遮边栏
//   ② BBTreeCanvas 手机抽屉——translate 滑入滑出由宿主包裹层承担
// 导航逻辑全部经 onNavClick(kind) 注入宿主（本组件零导航）：
//   canvas/wordbank/knowledge/statistics/billing/settings/account；kind='' = 点边栏空白（手机收抽屉）

import { HuaweiAccountStore, connectHuaweiAccount, loginWithHuaweiID } from '../utils/HuaweiAccountUtil'; // ★ 0.196.9：logoutHuaweiID 删——退出确认弹窗移 Index 根挂载，确认后走 doLogout
import { onLoginAccountHooks,
  SiyiPointStore, connectSiyiPoints, siyiLevelTitle, siyiBalanceDisplay,
  StatisticsStore, connectStatistics, getStatDays,
  SignInStore, connectSignIn, isSignedToday, connectSignInDialog } from '../common/ChatModel'; // ★ 0.248.0：司忆点资产显示（账户区等级头衔+SP 余额）；★ 0.256.0：签到入口（红点驱动）；★ 0.259.0：Lv8 SP 显示恒 999,999（siyiBalanceDisplay 收口）；★ 0.305.1：订阅语义清零（onLoginAccountHooks 替代试用打戳）
import { shouldPromptCloudSyncAfterLogin } from '../utils/CloudSyncUtil'; // ★ 0.196.8：云同步↔账号耦合；★ 0.196.9：弹窗 UI 移 AppConfirmDialog（暗紫）
import { openSettingsTab } from './GlobalSettingsDialog'; // ★ 0.248.0：账户区 SP 行点击→设置弹窗司忆点 Tab
import deviceInfo from '@ohos.deviceInfo'; // ★ 0.248.0：PC(2in1) 隐藏「桌面卡片」入口（系统不提供桌面卡片）
import { connectConfirmDialog } from './AppConfirmDialog'; // ★ 0.196.9：确认弹窗触发桥（退出账号/云同步询问——Index 根挂载消费）
import { common } from '@kit.AbilityKit'; // ★ 0.196.2：头像登录（getHostContext 转 common.Context 调 loginWithHuaweiID）
import { requestPublishReviewWidget } from '../utils/WidgetReviewUtil'; // ★ 0.203.0：桌面卡片入口（请求发布复习卡片到桌面）
import { track } from '../utils/TrackUtil'; // 0.206.0 埋点
import { needsHwAgreement, connectAgreementBridge } from '../utils/Agreement'; // ★ 0.226.0：登录前同意拦截；★ 0.264.0：华为协议门禁拆分；★ 0.305.0：基础协议由首页未同意态承担
import { RADIUS_LOGO, RADIUS_NAV, FONT_SIZE_NAV_LABEL, FONT_SIZE_CARD_TITLE, FONT_SIZE_CARD_TITLE_SM, FONT_SIZE_CAPTION, FONT_INTER, FONT_INTER_SEMIBOLD } from '../common/DesignTokens';
import { AppTheme, connectAppTheme } from '../common/AppTheme';

import { connectKnowledgeBank, deleteFolder } from '../utils/KnowledgeStoreUtil'; // ★ 0.220.0：文件夹树数据（新建功能 0.220.2 挪页内右键菜单）
import { KnowledgeBankStore, KFolder, KbFolderNavStore, connectKbFolderNav, SidebarSectionState, connectSidebarSection } from '../common/KnowledgeModel'; // ★ 0.220.0：折叠态+文件夹导航共享 store
import { connectWordBank } from '../utils/WordStoreUtil'; // ★ 0.222.19：单词库文件夹树数据
import { WordBankStore, WordFolder, WordFolderNavStore, connectWordFolderNav, WordSidebarSectionState, connectWordSidebarSection } from '../common/WordModel'; // ★ 0.222.19：单词库折叠态+文件夹导航共享 store
import { FoldChevron } from './FoldChevron'; // ★ 0.237.0：全项目唯一折叠指示器（军令统一）

const TREE_CELL: number = 14; // ★ 0.222.17：树形连接线每层缩进宽度（vp）

// ★ 0.222.19：边栏树统一项——知识库 KFolder / 单词库 WordFolder 字段同构，抽共同字段供同一渲染逻辑复用
interface SideFolderTreeItem {
  id: string;
  name: string;
  parentId: string;
  depth: number;
  isLast: boolean;
  ancestorIds: string[];
  ancestorHasNext: boolean[];
}
@ComponentV2
export struct AppSideBar {
  theme: AppTheme = connectAppTheme();
  @Event onNavClick: (kind: string) => void = (kind: string) => {};
  // ★ 0.220.0：文件夹树点击回调（宿主消费：确保路由在知识库页+视图切换已在共享 store 生效）
  @Event onFolderClick: (folderId: string) => void = (folderId: string) => {};
  // ★ 0.195.0 bugfix：选中态动态跟踪（用户实测报 bug：停在统计页边栏仍高亮气泡树「对不上」——
  //   原画布项硬编码永久高亮已废）。宿主注入当前路由名，本组件按映射判定高亮；
  //   BBTreeCanvas 手机抽屉形态固定传 'BBTreeCanvas'（抽屉只能从画布唤出，人就在画布上）
  @Param currentRoute: string = '';
  // ★ 0.279.6：边栏宽度由宿主注入——PC 窄窗自适应收窄（Index 传 sidebarWidth），
  //   手机抽屉/其余宿主不传=默认 208 原样
  @Param sidebarWidth: number = 208;
  @Param settingsOpen: boolean = false; // 设置是弹窗非页面：弹窗开着时高亮设置项
  account: HuaweiAccountStore = connectHuaweiAccount();
  siyi: SiyiPointStore = connectSiyiPoints(); // ★ 0.248.0：司忆点资产（账户区显示余额+头衔）
  statStore: StatisticsStore = connectStatistics(); // ★ 0.248.0：等级推导数据源
  signIn: SignInStore = connectSignIn(); // ★ 0.256.0：签到状态（入口红点判定）

  siyiLearnDays(): number {
    return getStatDays(this.statStore).length; // 累计学习天数=有学习活动的天数
  }
  // ★ 0.220.0：知识库折叠态+文件夹树
  kbSection: SidebarSectionState = connectSidebarSection();
  folderNav: KbFolderNavStore = connectKbFolderNav();
  kbStore: KnowledgeBankStore = connectKnowledgeBank();
// ★ 0.222.19：单词库折叠态+文件夹树（与知识库完全隔离的独立 store，key 不同避免状态污染）
  wbSection: WordSidebarSectionState = connectWordSidebarSection();
  wbFolderNav: WordFolderNavStore = connectWordFolderNav();
  wbStore: WordBankStore = connectWordBank();
  @Local selFolderId: string = ''; // 树内选中文件夹（新建子文件夹的父级）
  @Local collapsedFolderIds: string[] = []; // ★ 0.222.1 文件夹树折叠状态（id → 是否折叠）

  // ★ 0.222.12: 文件夹树触摸长按菜单（Pad/手机）——PC 走右键，触摸设备 RightClick 不映射长按（用户实测无反应），
  //   补 LongPressGesture+bindPopup 双通道（透明复刻知识库页创建菜单 0.220.2 已验证模式）
  @Local treeMenuVisible: boolean = false;   // bindPopup 开关
  @Local treeMenuFolderId: string = '';      // 长按目标文件夹（菜单 action 写 folderNav 共享 store）
  @Local treeMenuFolderName: string = '';    // 目标原名（重命名弹窗预填）
  @Local rootTreeMenuVisible: boolean = false; // ★ 0.222.13：根目录「全部卡片」行触摸长按菜单开关（Pad/手机）
  @Local focusTreeId: string = 'none'; // ★ 0.222.14：右键/长按焦点高亮（指哪打哪）——onMouse Right Press 或 LongPress 时置目标文件夹 id（根=''），菜单项/点击/弹窗关闭后复位 'none'
  @Local hoverTreeId: string = 'none'; // ★ 0.222.17：PC 鼠标悬停行 id（路径高亮 B 悬停触发；离开复位 'none'）
  // ★ 0.222.19：边栏树按路由分流（知识库/单词库共用同一套渲染与菜单，仅数据源/导航 store 不同）
  /** 当前是否单词库边栏树上下文 */
  isWordBankTree(): boolean {
    return this.currentRoute === 'WordBankPage';
  }
  /** 是否任一库页（知识库/单词库）——折叠树区显示条件 */
  isBankRoute(): boolean {
    return this.currentRoute === 'KnowledgeBankPage' || this.currentRoute === 'WordBankPage';
  }
  /** 当前库导航共享 store 的 folderId */
  activeNavFolderId(): string {
    return this.isWordBankTree() ? this.wbFolderNav.folderId : this.folderNav.folderId;
  }
  /** 写当前库导航共享 store 的 folderId */
  setActiveNavFolderId(folderId: string): void {
    if (this.isWordBankTree()) { this.wbFolderNav.folderId = folderId; } else { this.folderNav.folderId = folderId; }
  }
  /** 当前库导航 nonce 递增 */
  bumpActiveNavNonce(): void {
    if (this.isWordBankTree()) { this.wbFolderNav.nonce++; } else { this.folderNav.nonce++; }
  }
  /** 写当前库导航文件夹操作请求（边栏菜单 → 页面弹窗消费） */
  setActiveFolderAction(action: string, id: string, name: string = ''): void {
    if (this.isWordBankTree()) {
      this.wbFolderNav.folderAction = action; this.wbFolderNav.folderActionId = id; this.wbFolderNav.folderActionName = name;
    } else {
      this.folderNav.folderAction = action; this.folderNav.folderActionId = id; this.folderNav.folderActionName = name;
    }
  }
  /** 当前库六大模块展开态 */
  activeNavExpanded(): boolean {
    return this.isWordBankTree() ? this.wbSection.navExpanded : this.kbSection.navExpanded;
  }
  /** 切换当前库六大模块展开态 */
  toggleActiveNavExpanded(): void {
    if (this.isWordBankTree()) { this.wbSection.navExpanded = !this.wbSection.navExpanded; } else { this.kbSection.navExpanded = !this.kbSection.navExpanded; }
  }
  /** 根入口文案（知识库=全部卡片；单词库=全部单词） */
  activeRootLabel(): string {
    return this.isWordBankTree() ? '全部单词' : '全部卡片';
  }
  /** 根入口计数 */
  activeRootCount(): number {
    return this.isWordBankTree() ? this.wbStore.words.length : this.kbStore.cards.length;
  }
  /** 新建项文案（知识库=新建卡片；单词库=新建单词） */
  newEntryLabel(): string {
    return this.isWordBankTree() ? '新建单词' : '新建卡片';
  }
  /** ★ 0.220.0：文件夹树顺序（DFS：根('')→子层级；同层新在前）——产平铺数组供边栏树渲染 */
  /** ★ 0.222.17：补 isLast/ancestorIds/ancestorHasNext（经典树形连接线 A + 路径高亮 B） */
  kbFolderTreeItems(): SideFolderTreeItem[] {
    const out: SideFolderTreeItem[] = [];
    const walk = (parentId: string, depth: number, ancestorIds: string[], ancestorHasNext: boolean[]): void => {
      const kids = this.kbStore.folders
        .filter((f: KFolder): boolean => f.parentId === parentId)
        .sort((a: KFolder, b: KFolder): number => b.createdAt - a.createdAt);
      for (let i = 0; i < kids.length; i++) {
        const isLast = i === kids.length - 1;
        out.push({ id: kids[i].id, name: kids[i].name, parentId: kids[i].parentId, depth: depth, isLast: isLast, ancestorIds: ancestorIds, ancestorHasNext: ancestorHasNext });
        if (!this.isFolderCollapsed(kids[i].id)) {
          walk(kids[i].id, depth + 1, [...ancestorIds, kids[i].id], [...ancestorHasNext, !isLast]);
        }
      }
    };
    walk('', 0, [], []);
    return out;
  }

  /** ★ 0.222.19：单词库文件夹树顺序（DFS；同层新在前）——产平铺数组供边栏树渲染 */
  wbFolderTreeItems(): SideFolderTreeItem[] {
    const out: SideFolderTreeItem[] = [];
    const walk = (parentId: string, depth: number, ancestorIds: string[], ancestorHasNext: boolean[]): void => {
      const kids = this.wbStore.folders
        .filter((f: WordFolder): boolean => f.parentId === parentId)
        .sort((a: WordFolder, b: WordFolder): number => b.createdAt - a.createdAt);
      for (let i = 0; i < kids.length; i++) {
        const isLast = i === kids.length - 1;
        out.push({ id: kids[i].id, name: kids[i].name, parentId: kids[i].parentId, depth: depth, isLast: isLast, ancestorIds: ancestorIds, ancestorHasNext: ancestorHasNext });
        if (!this.isFolderCollapsed(kids[i].id)) {
          walk(kids[i].id, depth + 1, [...ancestorIds, kids[i].id], [...ancestorHasNext, !isLast]);
        }
      }
    };
    walk('', 0, [], []);
    return out;
  }

  /** ★ 0.222.19：当前库的树平铺项（按路由分流） */
  activeTreeItems(): SideFolderTreeItem[] {
    return this.isWordBankTree() ? this.wbFolderTreeItems() : this.kbFolderTreeItems();
  }

  /** ★ 0.222.17：树形连接线当前激活 id（右键/长按焦点 > 鼠标悬停 > 导航选中） */
  treeActiveId(): string {
    if (this.focusTreeId !== 'none') {
      return this.focusTreeId;
    }
    if (this.hoverTreeId !== 'none') {
      return this.hoverTreeId;
    }
    return this.activeNavFolderId();
  }

  /** ★ 0.222.17：某行第 colIndex 段引导线是否属于当前激活路径（B 路径高亮） */
  treeGuideActive(item: SideFolderTreeItem, colIndex: number): boolean {
    const active = this.treeActiveId();
    if (active === '') {
      return false;
    }
    if (item.id === active) {
      return true;
    }
    return colIndex < item.ancestorIds.length && item.ancestorIds[colIndex] === active;
  }

  /** ★ 0.222.17：行是否激活（右键焦点/鼠标悬停/导航选中）——背景与文字高亮 */
  treeRowActive(id: string): boolean {
    if (this.focusTreeId !== 'none' && this.focusTreeId === id) {
      return true;
    }
    if (this.hoverTreeId !== 'none' && this.hoverTreeId === id) {
      return true;
    }
    return this.activeNavFolderId() === id;
  }
  /** ★ 0.222.1/0.222.19：当前库文件夹是否有子文件夹（决定折叠三角显隐） */
  hasChildren(folderId: string): boolean {
    if (this.isWordBankTree()) {
      for (let i = 0; i < this.wbStore.folders.length; i++) {
        if (this.wbStore.folders[i].parentId === folderId) {
          return true;
        }
      }
      return false;
    }
    for (let i = 0; i < this.kbStore.folders.length; i++) {
      if (this.kbStore.folders[i].parentId === folderId) {
        return true;
      }
    }
    return false;
  }

  /** ★ 0.222.1：文件夹是否处于折叠态 */
  isFolderCollapsed(folderId: string): boolean {
    return this.collapsedFolderIds.indexOf(folderId) >= 0;
  }

  /** ★ 0.222.1：切换文件夹折叠状态（string[] 替换引用触发重渲染——Record 属性改不触发） */
  toggleFolderCollapse(folderId: string): void {
    if (this.isFolderCollapsed(folderId)) {
      this.collapsedFolderIds = this.collapsedFolderIds.filter((id: string): boolean => id !== folderId);
    } else {
      this.collapsedFolderIds = [...this.collapsedFolderIds, folderId];
    }
  }
  /** ★ 0.220.0：树内新建文件夹（父级=树内选中项；未选中=根）。空名忽略；成功后选中新文件夹 */

  /** ★ 0.220.0/0.222.19：当前库文件夹递归计数（统计整个子树，含所有子孙文件夹的词条/卡片） */
  activeCount(folderId: string): number {
    const ids: string[] = [folderId];
    let guard = 0;
    if (this.isWordBankTree()) {
      for (let i = 0; i < ids.length && guard < 1000; i++) {
        const pid = ids[i];
        for (let j = 0; j < this.wbStore.folders.length; j++) {
          const cid = this.wbStore.folders[j].id;
          if (this.wbStore.folders[j].parentId === pid && !ids.includes(cid)) {
            ids.push(cid);
          }
        }
        guard++;
      }
      let n = 0;
      for (let k = 0; k < this.wbStore.words.length; k++) {
        if (ids.includes(this.wbStore.words[k].folderId)) {
          n++;
        }
      }
      return n;
    }
    for (let i = 0; i < ids.length && guard < 1000; i++) {
      const pid = ids[i];
      const children = this.kbStore.folders.filter((f: KFolder): boolean => f.parentId === pid);
      for (let j = 0; j < children.length; j++) {
        if (!ids.includes(children[j].id)) {
          ids.push(children[j].id);
        }
      }
      guard++;
    }
    let n = 0;
    for (let k = 0; k < this.kbStore.cards.length; k++) {
      if (ids.includes(this.kbStore.cards[k].folderId)) {
        n++;
      }
    }
    return n;
  }
  /** ★ 0.220.2：边栏树删除文件夹（卡片移到上一级；当前视图文件夹被删则视图回退到其父级） */
  deleteTreeFolder(f: KFolder): void {
    deleteFolder(this.kbStore, f.id);
    if (this.folderNav.folderId === f.id) {
      const parentId = this.kbStore.folders.find((x: KFolder): boolean => x.id === f.parentId)?.parentId ?? '';
      this.folderNav.folderId = parentId;
    }
    this.getUIContext().getPromptAction().showToast({ message: `已删除「${f.name}」——卡片已移到上一级`, duration: 2000 });
  }

  /** ★ 0.222.18：树内选中统一切换（左键点击外，右键/长按也同步调用）——
   *  同步父级 selFolderId + 共享视图 nav.folderId（知识库/单词库页随之切换），
   *  并让「原先选中的文件夹」立即失焦（消除新旧两个文件夹同时高亮）；
   *  ⚠️ 不调用 onFolderClick——手机抽屉版该回调=closeSidebar，会让长按菜单来不及显示 */
  selectTreeFolder(folderId: string): void {
    this.selFolderId = folderId;
    this.setActiveNavFolderId(folderId);
    this.bumpActiveNavNonce();
  }

  /** ★ 0.222.12: 文件夹树触摸长按弹菜单（Pad/手机）——记录目标后 visible=true 唤起 bindPopup */
  openTreeMenu(folderId: string, folderName: string): void {
    this.treeMenuFolderId = folderId;
    this.treeMenuFolderName = folderName;
    this.focusTreeId = folderId;
    this.selectTreeFolder(folderId);
    this.treeMenuVisible = true;
  }

  /** ★ 0.222.12: 文件夹树长按菜单浮层（无参 @Builder——6 项 action 与 PC 右键 MenuElement 完全一致；点击写 folderNav 由 KnowledgeBankPage 消费弹对应操作弹窗） */
  @Builder
  folderTreeMenuBuilder() {
    Column({ space: 2 }) {
      Row() {
        Text(this.newEntryLabel())
          .fontSize(13)
          .fontColor(this.theme.textSecondary)
      }
      .width('100%')
      .height(36)
      .padding({ left: 12, right: 12 })
      .borderRadius(RADIUS_NAV)
      .onClick(() => {
        this.setActiveNavFolderId(this.treeMenuFolderId); this.setActiveFolderAction('newcard', this.treeMenuFolderId);
        this.treeMenuVisible = false;
        this.focusTreeId = 'none';
        this.onNavClick('');
      })
      Row() {
        Text('新建文件夹')
          .fontSize(13)
          .fontColor(this.theme.textSecondary)
      }
      .width('100%')
      .height(36)
      .padding({ left: 12, right: 12 })
      .borderRadius(RADIUS_NAV)
      .onClick(() => {
        this.setActiveFolderAction('newfolder', this.treeMenuFolderId);
        this.treeMenuVisible = false;
        this.focusTreeId = 'none';
        this.onNavClick('');
      })
      Row() {
        Text('移动')
          .fontSize(13)
          .fontColor(this.theme.textSecondary)
      }
      .width('100%')
      .height(36)
      .padding({ left: 12, right: 12 })
      .borderRadius(RADIUS_NAV)
      .onClick(() => {
        this.setActiveFolderAction('move', this.treeMenuFolderId);
        this.treeMenuVisible = false;
        this.focusTreeId = 'none';
        this.onNavClick('');
      })
      Row() {
        Text('复制')
          .fontSize(13)
          .fontColor(this.theme.textSecondary)
      }
      .width('100%')
      .height(36)
      .padding({ left: 12, right: 12 })
      .borderRadius(RADIUS_NAV)
      .onClick(() => {
        this.setActiveFolderAction('copy', this.treeMenuFolderId);
        this.treeMenuVisible = false;
        this.focusTreeId = 'none';
        this.onNavClick('');
      })
      Row() {
        Text('重命名')
          .fontSize(13)
          .fontColor(this.theme.textSecondary)
      }
      .width('100%')
      .height(36)
      .padding({ left: 12, right: 12 })
      .borderRadius(RADIUS_NAV)
      .onClick(() => {
        this.setActiveFolderAction('rename', this.treeMenuFolderId, this.treeMenuFolderName);
        this.treeMenuVisible = false;
        this.focusTreeId = 'none';
        this.onNavClick('');
      })
      Row() {
        Text('删除')
          .fontSize(13)
          .fontColor(this.theme.textSecondary)
      }
      .width('100%')
      .height(36)
      .padding({ left: 12, right: 12 })
      .borderRadius(RADIUS_NAV)
      .onClick(() => {
        this.setActiveFolderAction('delete', this.treeMenuFolderId);
        this.treeMenuVisible = false;
        this.focusTreeId = 'none';
        this.onNavClick('');
      })
    }
    .width(160)
    .padding({ top: 6, bottom: 6 })
    .backgroundColor(this.theme.surfaceNode)
    .borderRadius(RADIUS_NAV)
  }

  // ★ 0.222.12: 手机/Pad 抽屉与 PC 统一——进知识库首次自动配置默认态（导航收起+文件夹展开），与 Index.sideBarNav('knowledge') 同款（autoConfigured 确保有效一次）
  // ★ 0.222.13：根目录「全部卡片」行触摸长按菜单（Pad/手机）——4 项，根目录裁剪版（无移动/无重命名；删除=清空内容保留入口；复制=根全部内容到子文件夹）；action 写 folderNav 由 KnowledgeBankPage 消费
  @Builder
  rootTreeMenuBuilder() {
    Column({ space: 2 }) {
      Row() {
        Text(this.newEntryLabel())
          .fontSize(13)
          .fontColor(this.theme.textSecondary)
      }
      .width('100%')
      .height(36)
      .padding({ left: 12, right: 12 })
      .borderRadius(RADIUS_NAV)
      .onClick(() => {
        this.setActiveNavFolderId(''); this.setActiveFolderAction('newcard', '');
        this.rootTreeMenuVisible = false;
        this.focusTreeId = 'none';
        this.onNavClick('');
      })
      Row() {
        Text('新建文件夹')
          .fontSize(13)
          .fontColor(this.theme.textSecondary)
      }
      .width('100%')
      .height(36)
      .padding({ left: 12, right: 12 })
      .borderRadius(RADIUS_NAV)
      .onClick(() => {
        this.setActiveFolderAction('newfolder', '');
        this.rootTreeMenuVisible = false;
        this.focusTreeId = 'none';
        this.onNavClick('');
      })
      Row() {
        Text('复制')
          .fontSize(13)
          .fontColor(this.theme.textSecondary)
      }
      .width('100%')
      .height(36)
      .padding({ left: 12, right: 12 })
      .borderRadius(RADIUS_NAV)
      .onClick(() => {
        this.setActiveFolderAction('copy', '');
        this.rootTreeMenuVisible = false;
        this.focusTreeId = 'none';
        this.onNavClick('');
      })
      Row() {
        Text('删除')
          .fontSize(13)
          .fontColor(this.theme.textSecondary)
      }
      .width('100%')
      .height(36)
      .padding({ left: 12, right: 12 })
      .borderRadius(RADIUS_NAV)
      .onClick(() => {
        this.setActiveFolderAction('delete', '');
        this.rootTreeMenuVisible = false;
        this.focusTreeId = 'none';
        this.onNavClick('');
      })
    }
    .width(160)
    .padding({ top: 6, bottom: 6 })
    .backgroundColor(this.theme.surfaceNode)
    .borderRadius(RADIUS_NAV)
  }

  aboutToAppear(): void {
    if (this.currentRoute === 'KnowledgeBankPage' && !this.kbSection.autoConfigured) {
      this.kbSection.navExpanded = false;
      this.kbSection.folderExpanded = true;
      this.kbSection.autoConfigured = true;
    }
    // ★ 0.222.19：进单词库首次同样自动配置默认态（导航收起+文件夹展开），与 Index.sideBarNav('wordbank') 同款（autoConfigured 确保有效一次）
    if (this.currentRoute === 'WordBankPage' && !this.wbSection.autoConfigured) {
      this.wbSection.navExpanded = false;
      this.wbSection.folderExpanded = true;
      this.wbSection.autoConfigured = true;
    }
  }

  /** ★ 0.195.0：导航项高亮判定——当前路由映射（ChatPage/AnnotationPage 是气泡树子页，归气泡树） */
  isItemActive(kind: string): boolean {
    if (kind === 'canvas') {
      return this.currentRoute === 'BBTreeCanvas' || this.currentRoute === 'ChatPage' || this.currentRoute === 'AnnotationPage';
    }
    if (kind === 'wordbank') {
      return this.currentRoute === 'WordBankPage';
    }
    if (kind === 'knowledge') {
      return this.currentRoute === 'KnowledgeBankPage';
    }
    if (kind === 'review') {
      return this.currentRoute === 'ReviewPage'; // ★ 0.196.1：知识复习页
    }
    if (kind === 'statistics') {
      return this.currentRoute === 'StatisticsPage';
    }
    if (kind === 'billing') {
      return this.currentRoute === 'BillingPage';
    }
    if (kind === 'settings') {
      return this.settingsOpen;
    }
    return false;
  }

  /** 边栏导航项图标（canvas 走 bubbles.svg，其余同原 navIcon 映射） */
  navIcon(kind: string): Resource {
    if (kind === 'wordbank') {
      return $r('app.media.bookopen');
    }
    if (kind === 'knowledge') {
      return $r('app.media.library');
    }
    if (kind === 'review') {
      return $r('app.media.refresh'); // ★ 0.196.1：复习（循环箭头=重复记忆语义；后续可换专属图标）
    }
    if (kind === 'statistics') {
      return $r('app.media.chart');
    }
    if (kind === 'billing') {
      return $r('app.media.receipt');
    }
    return $r('app.media.settings');
  }

  /** 边栏导航项文字 */
  navLabel(kind: string): string {
    if (kind === 'wordbank') {
      return '单词库';
    }
    if (kind === 'knowledge') {
      return '知识库';
    }
    if (kind === 'review') {
      return '卡片复习'; // ★ 0.201.0：用户拍板「知识复习」→「卡片复习」（页面同改，复习页覆盖单词+知识卡两类）
    }
    if (kind === 'statistics') {
      return '统计';
    }
    if (kind === 'billing') {
      return '账单';
    }
    if (kind === 'settings') {
      return '设置';
    }
    return '气泡树'; // ★ 0.195.0：边栏「画布」→「气泡树」（用户定稿——命名与页面主体统一）
  }

  /** 账号显示名（未登录显示「未登录」） */
  getAccountDisplayName(): string {
    if (!this.account.isLoggedIn) {
      return '未登录';
    }
    if (this.account.nickName !== '') {
      return this.account.nickName;
    }
    if (this.account.openID !== '') {
      return `ID: ${this.account.openID.substring(0, 10)}…`;
    }
    return '已登录';
  }

  // 边栏 Logo（36×36 容器 225° 主紫渐变 + gitbranch，同节点图标容器视觉语言）
  @Builder
  SideBarLogo(size: number) {
    Column() {
      Image($r('app.media.gitbranch'))
        .width(size * 0.55)
        .height(size * 0.55)
        .objectFit(ImageFit.Contain)
    }
    .width(size)
    .height(size)
    .borderRadius(RADIUS_LOGO)
    .linearGradient({ angle: 225, colors: [[this.theme.brandPrimary, 0], [this.theme.brandSecondary, 1]] })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 边栏头像（登录态 avatarUri 圆形裁切；无头像/未登录柔面圆占位）
  @Builder
  SideBarAvatar(size: number) {
    if (this.account.avatarUri !== '') {
      Image(this.account.avatarUri)
        .width(size)
        .height(size)
        .borderRadius(size / 2)
        .clip(true)
        .objectFit(ImageFit.Cover)
    } else {
      Column() {
        Image($r('app.media.gitbranch'))
          .width(size * 0.5)
          .height(size * 0.5)
          .objectFit(ImageFit.Contain)
      }
      .width(size)
      .height(size)
      .borderRadius(size / 2)
      .backgroundColor(this.theme.surfaceSoft)
      .border({ width: 1, color: this.theme.strokeCard })
      .justifyContent(FlexAlign.Center)
    }
  }

  // 边栏导航项（气泡树=主选中态样式；点击经 onNavClick 交宿主裁决）
  @Builder
  SideBarNavItem(kind: string) {
    Row({ space: 10 }) {
      if (kind === 'canvas') {
        // ★ 0.195.0：DagIcon 自绘 → bubbles.svg（三气泡+连线，与画布实际视觉同构）
        Image($r('app.media.bubbles'))
          .width(18)
          .height(18)
          .objectFit(ImageFit.Contain)
      } else {
        Image(this.navIcon(kind))
          .width(18)
          .height(18)
          .objectFit(ImageFit.Contain)
      }
      Text(this.navLabel(kind))
        .fontSize(FONT_SIZE_NAV_LABEL)
        .fontFamily(this.isItemActive(kind) ? FONT_INTER_SEMIBOLD : FONT_INTER) // ★ 0.195.0 bugfix：硬编码 canvas 永久高亮 → 动态跟踪
        .fontColor(this.isItemActive(kind) ? this.theme.textPrimary : this.theme.textSecondary)
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .borderRadius(RADIUS_NAV)
    .backgroundColor(this.isItemActive(kind) ? this.theme.surfaceHover : Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
 const _tp1: Record<string, string> = {}; _tp1['item'] = kind;
      track(this.getUIContext().getHostContext() as common.Context, 'sidebar_nav', _tp1); // 0.206.0 埋点：边栏导航
      this.onNavClick(kind);
    })
  }



  build() {
    Column() {
      // ── 顶部 Logo 区（Logo + 应用名 + 副标题）──
      Row({ space: 10 }) {
        this.SideBarLogo(36)
        Column({ space: 2 }) {
          Text('DAG AI Chat')
            .fontSize(FONT_SIZE_CARD_TITLE)
            .fontWeight(600)
            .fontFamily(FONT_INTER_SEMIBOLD)
            .fontColor(this.theme.textPrimary)
            .maxLines(1)
          Text('你的AI学习伴侣')
            .fontSize(FONT_SIZE_CAPTION)
            .fontFamily(FONT_INTER)
            .fontColor(this.theme.textTertiary)
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 20, bottom: 24 })

      // ── 导航区（★ 0.220.1 用户拍板终版：两区块独立收放——「导航」归导航、「文件夹」归文件夹）──
      //   宽屏知识库页=折叠形态：「导航」条（点击切换六大模块展开/收起，箭头随态）+「文件夹」标题行
      //   （点击切换树收放）——两者独立、状态 AppStorageV2 记忆（切页面/重进保持用户选择）；
      //   非知识库页=六大模块常显原样；★ 0.222.12：知识库页（含手机/Pad 抽屉）统一显示「导航」折叠条——三端一致
      // （kbFolded 条件内联于下方两处 if——build 内禁 const 局部声明，0.220.1 编译实锤）
      if (this.isBankRoute()) {
        // 「导航」条（顶部——0.220.2 用户拍板：展开时也放在上面）：点击切换六大模块展开/收起
        Row() {
          Text('导航')
            .fontSize(FONT_SIZE_NAV_LABEL)
            .fontFamily(FONT_INTER_SEMIBOLD)
            .fontColor(this.theme.textPrimary)
          Blank()
          // ★ 0.237.0 军令：导航条折叠三角字符 ▾/▸ → FoldChevron SVG
          FoldChevron({ expanded: this.activeNavExpanded() })
        }
        .width('100%')
        .height(36)
        .padding({ left: 12, right: 12 })
        .borderRadius(RADIUS_NAV)
        .backgroundColor(this.theme.surfaceSoft)
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 6 })
        .onClick(() => {
          this.toggleActiveNavExpanded();
        })
      }
      if (!this.isBankRoute() || this.activeNavExpanded()) {
        this.SideBarNavItem('canvas')
        this.SideBarNavItem('wordbank')
        this.SideBarNavItem('knowledge')
        this.SideBarNavItem('review') // ★ 0.196.1：知识复习（用户定稿：知识库下方）
        this.SideBarNavItem('statistics')
        this.SideBarNavItem('billing')
      }

      // ── ★ 0.220.1：文件夹树区（折叠形态+当前在知识库页时显示；标题行点击切换树收放——独立于导航区）──
      if (this.isBankRoute()) {
        Column() {
        // 「全部卡片」= 根目录视图入口
        Row({ space: 8 }) {
          Text(this.activeRootLabel())
            .fontSize(13)
            .fontColor(this.treeRowActive('') ? this.theme.textPrimary : this.theme.textSecondary)
            .layoutWeight(1)
          Text(`${this.activeRootCount()}`)
            .fontSize(10)
            .fontColor(this.theme.textTertiary)
        }
        .height(32)
        .padding({ left: 8, right: 8 })
        .borderRadius(RADIUS_NAV)
        .backgroundColor(this.treeRowActive('') ? this.theme.surfaceHover : Color.Transparent)
        .onHover((isHover: boolean) => {
          this.hoverTreeId = isHover ? '' : 'none';
        })
        .onClick(() => {
          this.selFolderId = '';
          this.setActiveNavFolderId('');
          this.bumpActiveNavNonce();
          this.onFolderClick('');
          this.focusTreeId = 'none';
        })
          .onMouse((e: MouseEvent) => {
            if (e.action === MouseAction.Press && e.button === MouseButton.Right) {
              this.focusTreeId = '';
              this.selectTreeFolder('');
              this.onFolderClick('');
            }
          })
          .bindContextMenuByResponseType([
            { value: this.newEntryLabel(), action: () => { this.setActiveNavFolderId(''); this.setActiveFolderAction('newcard', ''); this.focusTreeId = 'none'; } },
            { value: '新建文件夹', action: () => { this.setActiveFolderAction('newfolder', ''); this.focusTreeId = 'none'; } },
            { value: '复制', action: () => { this.setActiveFolderAction('copy', ''); this.focusTreeId = 'none'; } },
            { value: '删除', action: () => { this.setActiveFolderAction('delete', ''); this.focusTreeId = 'none'; } }
          ], ResponseType.RightClick)
          .bindPopup(this.rootTreeMenuVisible, {
            builder: this.rootTreeMenuBuilder(),
            placement: Placement.Bottom,
            popupColor: this.theme.surfaceNode,
            radius: 12,
            mask: { color: this.theme.overlayLight },
            onStateChange: (e: PopupStateChangeParam) => {
              this.rootTreeMenuVisible = e.isVisible;
              if (!e.isVisible) { this.focusTreeId = 'none'; }
            }
          })
          .gesture(
            LongPressGesture({ duration: 500 })
              .onAction(() => {
                this.focusTreeId = '';
                this.selectTreeFolder('');
                this.rootTreeMenuVisible = true;
              })
          )
        // 文件夹树（DFS 层级缩进+卡片数徽标；点击=切换视图+高亮；★ 0.222.17 经典树形连接线）
        ForEach(this.activeTreeItems(), (item: SideFolderTreeItem) => {
          Row({ space: 6 }) {
            // ★ 0.222.17：经典树形连接线（A）——按深度绘制祖先竖线 + L 型拐角（├/└），色走 this.theme.strokeCard
            Row() {
              ForEach(item.ancestorHasNext, (cont: boolean, k: number) => {
                Stack({ alignContent: Alignment.Top }) {
                  if (cont) {
                    Column()
                      .width(1)
                      .height('100%')
                      .backgroundColor(this.treeGuideActive(item, k) ? this.theme.brandSecondary : this.theme.strokeCard)
                  }
                }
                .width(TREE_CELL)
                .height('100%')
              }, (cont: boolean, k: number) => `${k}_${cont}`)
              Row() {
                Stack({ alignContent: Alignment.TopEnd }) {
                  Column()
                    .width(1)
                    .height(item.isLast ? '50%' : '100%')
                    .backgroundColor(this.treeGuideActive(item, item.depth) ? this.theme.brandSecondary : this.theme.strokeCard)
                }
                .width('50%')
                .height('100%')
                Stack({ alignContent: Alignment.Center }) {
                  Row()
                    .width('100%')
                    .height(1)
                    .backgroundColor(this.treeGuideActive(item, item.depth) ? this.theme.brandSecondary : this.theme.strokeCard)
                }
                .width('50%')
                .height('100%')
              }
              .width(TREE_CELL)
              .height('100%')
            }
            .height('100%')
            // ★ 0.237.0 军令：树行折叠三角字符 ▸/▾ → FoldChevron SVG；叶子行空占位同宽对齐
            if (this.hasChildren(item.id)) {
              FoldChevron({ expanded: !this.isFolderCollapsed(item.id) })
                .onClick(() => {
                  this.toggleFolderCollapse(item.id);
                })
            } else {
              Row().width(12)
            }
            Text(item.name)
              .fontSize(13)
              .fontColor(this.treeRowActive(item.id) ? this.theme.textPrimary : this.theme.textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(`${this.activeCount(item.id)}`)
              .fontSize(10)
              .fontColor(this.theme.textTertiary)
          }
          .width('100%')
          .height(32)
          .padding({ left: 8, right: 8 })
          .borderRadius(RADIUS_NAV)
          .backgroundColor(this.treeRowActive(item.id) ? this.theme.surfaceHover : Color.Transparent)
          .onHover((isHover: boolean) => {
            this.hoverTreeId = isHover ? item.id : 'none';
          })
          .onClick(() => {
            this.selFolderId = item.id;
            this.setActiveNavFolderId(item.id);
            this.bumpActiveNavNonce();
            this.onFolderClick(item.id);
            this.focusTreeId = 'none';
          })
          .onMouse((e: MouseEvent) => {
            if (e.action === MouseAction.Press && e.button === MouseButton.Right) {
              this.focusTreeId = item.id;
              this.selectTreeFolder(item.id);
              this.onFolderClick(item.id);
            }
          })
          .bindContextMenuByResponseType([
            { value: this.newEntryLabel(), action: () => { this.setActiveNavFolderId(item.id); this.setActiveFolderAction('newcard', item.id); this.focusTreeId = 'none'; } },
            { value: '新建文件夹', action: () => { this.setActiveFolderAction('newfolder', item.id); this.focusTreeId = 'none'; } },
            { value: '移动', action: () => { this.setActiveFolderAction('move', item.id); this.focusTreeId = 'none'; } },
            { value: '复制', action: () => { this.setActiveFolderAction('copy', item.id); this.focusTreeId = 'none'; } },
            { value: '重命名', action: () => { this.setActiveFolderAction('rename', item.id, item.name); this.focusTreeId = 'none'; } },
            { value: '删除', action: () => { this.setActiveFolderAction('delete', item.id); this.focusTreeId = 'none'; } }
          ], ResponseType.RightClick)
          .bindPopup(this.treeMenuVisible && this.treeMenuFolderId === item.id, {
            builder: this.folderTreeMenuBuilder(),
            placement: Placement.Bottom,
            popupColor: this.theme.surfaceNode,
            radius: 12,
            mask: { color: this.theme.overlayLight },
            onStateChange: (e: PopupStateChangeParam) => {
              if (this.treeMenuFolderId === item.id) {
                this.treeMenuVisible = e.isVisible;
                if (!e.isVisible) { this.focusTreeId = 'none'; }
              }
            }
          })
          .gesture(
            LongPressGesture({ duration: 500 })
              .onAction(() => {
                this.openTreeMenu(item.id, item.name);
              })
          )
        }, (item: SideFolderTreeItem) => item.id)
      }
      }

      // ── 弹性空隙（底部设置 + 账号沉底）──
      Blank()

      // ── 底部：设置 + 账号 ──
      this.SideBarNavItem('settings')
      Divider()
        .color(this.theme.strokeCard)
        .width('100%')
        .margin({ top: 6, bottom: 6 })
      Row({ space: 10 }) {
        this.SideBarAvatar(36)
        Text(this.getAccountDisplayName())
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontFamily(FONT_INTER)
          .fontColor(this.theme.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        // ★ 0.203.0：桌面卡片小字入口（用户拍板：账户行右边小字「桌面卡片」，点击打开卡片管理器选规格添加）
        //   子组件 onClick 消费不冒泡——不会误触账户行的登录/退出逻辑
        // ★ 0.248.0：PC(2in1) 隐藏——系统不提供桌面卡片（用户拍板「PC 的桌面卡片可以删除了」）
        if (deviceInfo.deviceType !== '2in1') {
          Text('桌面卡片')
            .fontSize(10)
            .fontFamily(FONT_INTER_SEMIBOLD)
            .fontColor(this.theme.brandPrimary)
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .border({ width: 0.5, color: this.theme.brandSecondary })
            .borderRadius(8)
            .onClick(() => {
              requestPublishReviewWidget();
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        // ★ 0.196.2 用户拍板：点头像=华为账号退出确认弹窗（原跳统计页废弃——统计已有边栏独立入口）
        // ★ 0.196.3 bugfix（用户实测「退出后再点没反应」）：未登录点头像=直接拉起登录
        if (!this.account.isLoggedIn) {
          // ★ 0.305.0：基础协议门禁=首页未同意态（唯一同意入口，未同意时边栏不渲染）——此处只留华为协议门禁
          // ★ 0.264.0：华为账号用户认证协议门禁（登录前单独征求；不同意仅取消登录）
          if (needsHwAgreement()) {
            connectAgreementBridge().pendingAction = 'login';
            connectAgreementBridge().hwPromptVisible = true;
            return;
          }
          track(this.getUIContext().getHostContext() as common.Context, 'login_huawei'); // 0.206.0 埋点：登录入口点击
          const loginContext = this.getUIContext().getHostContext() as common.Context;
          // ★ 0.196.8：登录成功 → 弹「是否开启云同步」（云同步与账号绑定，用户拍板流程）
          // ★ 0.196.9：弹窗 UI 换 AppConfirmDialog 暗紫（Index 根挂载，store 触发）
          loginWithHuaweiID(loginContext).then((tip: string) => {
            if (tip === '') {
              onLoginAccountHooks(); // ★ 0.305.1：登录后账号钩子（订阅打戳已随退役删除）
              if (shouldPromptCloudSyncAfterLogin(true)) {
                connectConfirmDialog().cloudSyncPromptVisible = true;
              }
            }
          });
          return;
        }
        // ★ 0.196.9：退出确认换 AppConfirmDialog 暗紫（原系统 AlertDialog 灰底，用户实测反馈
        //   与暗紫风格不符）——弹窗 Index 根挂载；确认后走 doLogout（退出 + 云同步强制关一条龙）
        connectConfirmDialog().logoutConfirmVisible = true;
      })
      // ★ 0.248.0：司忆点资产行（登录后显示；点击进设置弹窗司忆点 Tab——三端统一，
      //   手机/Pad 额外由桌面卡片承载，PC 无桌面卡片故边栏为唯一常驻入口）
      if (this.account.isLoggedIn) {
        Row({ space: 6 }) {
          Text(siyiLevelTitle(this.siyiLearnDays()))
            .fontSize(FONT_SIZE_CAPTION)
            .fontColor(this.theme.textTertiary)
          Blank()
          // ★ 0.256.0：签到入口 pill（未签亮红点；子组件 onClick 消费不冒泡——0.203.0 桌面卡片小字先例）
          Stack({ alignContent: Alignment.TopEnd }) {
            Row({ space: 3 }) {
              Image($r('app.media.sign'))
                .width(12)
                .height(12)
                .objectFit(ImageFit.Contain)
              Text(isSignedToday(this.signIn) ? '已签' : '签到')
                .fontSize(10)
                .fontColor(isSignedToday(this.signIn) ? this.theme.textTertiary : this.theme.brandSecondary)
            }
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .borderRadius(9)
            .backgroundColor(this.theme.surfaceHover)
            .onClick(() => {
              connectSignInDialog().visible = true;
            })
            if (!isSignedToday(this.signIn)) {
              Circle()
                .width(6)
                .height(6)
                .fill('#FF4D4F')
                .offset({ x: 3, y: -2 })
            }
          }
          Text(`${siyiBalanceDisplay(this.siyi, this.siyiLearnDays())} SP`) // ★ 0.259.0：Lv8 满级恒显 999,999（显示层收口，真实余额不动）
            .fontSize(FONT_SIZE_CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme.brandSecondary)
        }
        .width('100%')
        .margin({ top: 4 })
        .onClick(() => {
          openSettingsTab(2); // 司忆点 Tab（index 2）
        })
      }
    }
    .width(this.sidebarWidth)
    .height('100%')
    .padding({ left: 12, right: 12, bottom: 16 })
    .backgroundColor(this.theme.bgNav)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onNavClick(''); // 点边栏空白（手机抽屉收起；按钮 onClick 已消费不冒泡至此）
    })
  }
}

