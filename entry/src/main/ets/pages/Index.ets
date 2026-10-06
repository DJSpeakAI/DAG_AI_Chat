// ============================================================
// Index.ets — 应用首页入口
// ============================================================
// 本文件是应用的入口页面，负责：
//   - 初始化持久化数据（PersistenceV2 连接）
//   - 从 JSON 恢复气泡树（反序列化）
//   - 首次启动时创建默认气泡树（根节点）
//   - 配置 NavPathStack 导航路由（气泡画布 / 对话页 / 单词库 / 知识库 / 标注页）
//
// 页面导航关系：
//   Index → BBTreeCanvas（气泡画布）→ ChatPage（对话页）→ AnnotationPage（屏幕标注，★ 0.152）
//                                  → WordBankPage（单词库，★ 0.145）
//                                  → KnowledgeBankPage（知识库，★ 0.146）
//   ★ 0.189.1：SettingsPage（设置页）已删除——0.150 起设置走 GlobalSettingsDialog 弹窗，
//   页面零入口成僵尸代码（含已取消的云端 TTS 配置区），随 0.189.1 音频配置移除一并清理
// ============================================================

import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import { BBTreeCanvas } from '../components/BBTreeCanvas';
import { ChatPage } from '../components/ChatPage';
import { WordBankPage } from '../components/WordBankPage'; // ★ 0.145：单词库页面路由
import { KnowledgeBankPage } from '../components/KnowledgeBankPage'; // ★ 0.146：知识库页面路由
import { AnnotationPage } from '../components/AnnotationPage'; // ★ 0.152：屏幕圈选标注页路由
import { StatisticsPage } from '../components/StatisticsPage'; // ★ 0.192.0：学习统计页路由
import { BillingPage } from '../components/BillingPage'; // ★ 0.194.0：账单/订阅页路由
import { ReviewPage } from '../components/ReviewPage'; // ★ 0.196.1：知识复习页路由（Anki 式单卡，边栏「复习」入口）
import { WindowMode, connectWindowMode } from '../common/WindowMode'; // ★ 0.196.4：窗口宽度模式共享真相源（分屏/悬浮窗切手机布局）
import { BubbleNode, ChatMessage, BubbleTree, ApiConfig, PersistData, generateNodeId, generateMessageId, deserializeBubbleTree, TabMeta, connectCanvasMode, connectTabForest, parseTabs, migrateLegacyPoolsIfNeeded, SubscriptionStore, connectSubscription, stampFreeTrialOnLogin, checkDailyReminder, markWelcomeShown, markReminderShownToday, isVip } from '../common/ChatModel'; // ★ 0.196.8：isVip——登录后云同步弹窗 VIP 判定
import { shouldPromptCloudSyncAfterLogin, enableCloudSyncNow, disableCloudSyncOnLogout } from '../utils/CloudSyncUtil'; // ★ 0.196.8：云同步↔华为账号耦合；★ 0.196.9：弹窗 UI 移 AppConfirmDialog（暗紫）
import { AppConfirmDialog, ConfirmDialogStore, connectConfirmDialog } from '../components/AppConfirmDialog'; // ★ 0.196.9：通用确认弹窗（退出账号/云同步询问——Index 根唯一挂载点）
import { ReminderDialog } from '../components/ReminderDialog'; // ★ 0.195.0：订阅提醒自定义弹窗（暗紫设计语言，替代系统灰 AlertDialog）
import { AppSideBar } from '../components/AppSideBar'; // ★ 0.195.0：大屏常驻边栏（用户定稿：边栏一直存在，页面平移）
import { GlobalSettingsDialog } from '../components/GlobalSettingsDialog'; // ★ 0.195.0：常驻边栏「设置」入口（与画布/对话页实例共用 PersistenceV2 数据）
import display from '@ohos.display'; // ★ 0.195.0：大屏断点检测（屏宽 ≥600vp 渲染常驻边栏，同 BBTreeCanvas 判定）
import { HuaweiAccountStore, connectHuaweiAccount, loginWithHuaweiID, logoutHuaweiID, AUTH_CANCELLED_TIP } from '../utils/HuaweiAccountUtil'; // ★ 0.164：华为账号登录；★ 0.196.9：AUTH_CANCELLED_TIP——用户取消登录静默
import { BG_APP, SURFACE_HOVER, SURFACE_SOFT, BRAND_PRIMARY, TEXT_PRIMARY, TEXT_SECONDARY, TEXT_TERTIARY, STROKE_BRAND, RADIUS_NAV, RADIUS_CONTROL, FONT_SIZE_META, FONT_SIZE_CAPTION, FONT_SIZE_CARD_TITLE_SM, FONT_INTER_SEMIBOLD } from '../common/DesignTokens'; // ★ 0.174.1：UI Token 单一来源（删 isDark 三元——v0.166.3 锁暗色后浅色分支是死代码）；★ 0.174.2：删 BRAND_SECONDARY/RADIUS_LOGO（首页 Logo 区移除后无引用）
import { common } from '@kit.AbilityKit'; // ★ 0.164：登录接口需要 Context

// 首页入口 — V2 全量迁移
@Entry
@ComponentV2
struct Index {
  pathStack: NavPathStack = new NavPathStack();

  // ★ 0.164：登录/退出请求进行中标记（防连点，官方 1001500002 重复请求错误码要求点击控制）
  @Local isProcessing: boolean = false;
  // ★ 0.164：登录/退出的结果提示（空串 = 无提示）
  @Local loginTip: string = '';

  // ★ 0.164：获取华为账号登录态（PersistenceV2 单例）
  getHuaweiAccount(): HuaweiAccountStore {
    return connectHuaweiAccount();
  }

  // ★ 0.194.0：订阅状态（登录成功时记录免费试用开始时间）
  subscription: SubscriptionStore = connectSubscription();
  // ★ 0.195.0：订阅提醒弹窗状态（ReminderDialog 自定义弹窗驱动：0=首登欢迎 / 1~7=剩余天数）
  @Local reminderVisible: boolean = false;
  @Local reminderMode: number = 0;
  // ★ 0.195.0：大屏常驻边栏——断点检测（≥600vp 平板/PC）+ 设置弹窗（边栏「设置」入口）
  // ★ 0.196.4：isTablet 改窗口宽度共享真相源（WindowMode）——分屏/悬浮窗屏宽不变导致小窗仍渲染
  //   平板布局（用户实测边栏挤压+黑屏）；本页根 onAreaChange 写入窗口实宽，首帧用屏宽猜测
  windowMode: WindowMode = connectWindowMode();
  @Computed get isTablet(): boolean {
    return this.windowMode.isTablet;
  }
  // ★ 0.195.0 bugfix：边栏选中态跟踪——didShow 拦截拿目标页名（'navBar'=首页 → 清空无高亮；
  //   用户实测报 bug：停在统计页边栏仍高亮气泡树「对不上」，原画布项硬编码永久高亮已废）
  @Local currentRoute: string = '';
  @Local globalSettingsVisible: boolean = false;
  confirmDialog: ConfirmDialogStore = connectConfirmDialog(); // ★ 0.196.9：确认弹窗触发桥（退出账号/云同步询问——根 Stack 挂载消费）

  // ★ 0.164：点击华为账号登录
  // ★ 0.196.11：fromSyncEntry 参数——登录来源分流（用户实测反馈：从设置页「开启云同步」
  //   入口进来登录的，入口即意图，登录成功**直接开云同步**，不再弹「是否开启云同步」多此一举；
  //   主页/边栏/账单页等普通登录路径保持询问弹窗）
  doLogin(fromSyncEntry: boolean) {
    if (this.isProcessing) {
      return;
    }
    this.isProcessing = true;
    this.loginTip = '';
    const context = this.getUIContext().getHostContext() as common.Context;
    loginWithHuaweiID(context).then((tip: string) => {
      this.isProcessing = false;
      // ★ 0.196.9：用户主动取消登录——静默返回（原红字「已取消授权【code=1001502012…」
      //   常驻首页，用户实测报 bug；取消是正常行为非错误，不显示不打日志）
      if (tip === AUTH_CANCELLED_TIP) {
        return;
      }
      if (tip !== '') {
        this.loginTip = tip;
      }
      // ★ 0.194.0：登录成功（无错误提示）→ 统一打点（30 天免费试用起点，逻辑收敛到 stampFreeTrialOnLogin）
      // ★ 0.195.0：首次打戳（首登）→ 弹「30 天试用欢迎弹窗」（自定义暗紫弹窗）；重复登录静默
      if (tip === '' && stampFreeTrialOnLogin(this.subscription)) {
        markWelcomeShown(this.subscription); // 弹出即记账（仅 1 次）
        this.reminderMode = 0;
        this.reminderVisible = true;
      }
      if (tip === '') {
        if (fromSyncEntry) {
          // ★ 0.196.11：云同步入口登录——入口即意图，成功直接开（VIP 墙内）；非 VIP 提示订阅
          if (isVip(this.subscription)) {
            enableCloudSyncNow(this.getUIContext());
          } else {
            try {
              this.getUIContext().getPromptAction().showToast({ message: '云同步为会员功能，请到边栏「账单」页订阅', duration: 1500 });
            } catch (_e) {
              // 静默失败（toast 非关键路径）
            }
          }
        } else if (shouldPromptCloudSyncAfterLogin(isVip(this.subscription))) {
          // ★ 0.196.8：普通路径登录成功 → 弹「是否开启云同步」；★ 0.196.9：AppConfirmDialog 暗紫
          this.confirmDialog.cloudSyncPromptVisible = true;
        }
      }
    });
  }

  // ★ 0.164：点击退出账号
  doLogout() {
    if (this.isProcessing) {
      return;
    }
    this.isProcessing = true;
    this.loginTip = '';
    const context = this.getUIContext().getHostContext() as common.Context;
    logoutHuaweiID(context).then((tip: string) => {
      this.isProcessing = false;
      if (tip !== '') {
        this.loginTip = tip;
      }
      // ★ 0.196.8：退出 → 云同步开关强制关（本地登录态无论成败都已清空，云侧已无账号会话）
      disableCloudSyncOnLogout(this.getUIContext());
    });
  }

  // ★ 0.164：登录后显示名（昵称优先；无昵称显示 ID 前 10 位；都没有显示"已登录"）
  getDisplayName(): string {
    const account = this.getHuaweiAccount();
    if (account.nickName !== '') {
      return account.nickName;
    }
    if (account.openID !== '') {
      return `ID: ${account.openID.substring(0, 10)}…`;
    }
    return '已登录';
  }

  // ★ 0.195.0：到期倒计时提醒——页面显示时检查（冷启动/回前台均触发），每日去重最多弹 1 次
  onPageShow(): void {
    const days = checkDailyReminder(this.subscription);
    if (days > 0) {
      markReminderShownToday(this.subscription); // 弹出即记账（每日去重）
      this.reminderMode = days;
      this.reminderVisible = true;
    }
  }

  // ★ 0.195.0：常驻边栏导航（大屏）——气泡树=回画布页：栈顶已是则不动 / 深栈 pop 一层 / 根栈 push；
  //   其余项 pushPath（页面在边栏右侧 Navigation 区域平移，边栏恒在——用户定稿）
  sideBarNav(kind: string): void {
    if (kind === 'wordbank') {
      this.pathStack.pushPath({ name: 'WordBankPage' });
    } else if (kind === 'knowledge') {
      this.pathStack.pushPath({ name: 'KnowledgeBankPage' });
    } else if (kind === 'review') {
      this.pathStack.pushPath({ name: 'ReviewPage' }); // ★ 0.196.1：知识复习页（Anki 式单卡）
    } else if (kind === 'statistics') { // ★ 0.196.2：account 分支删除（头像改退出确认，不再发 onNavClick）
      this.pathStack.pushPath({ name: 'StatisticsPage' });
    } else if (kind === 'billing') {
      this.pathStack.pushPath({ name: 'BillingPage' });
    } else if (kind === 'settings') {
      this.globalSettingsVisible = true;
    } else if (kind === 'canvas') {
      // ★ 0.195.0 bugfix：回画布四态（用户实测「单词库点气泡树跳不回去」——原 length>1 误判：
      //   [WordBankPage] 单页栈走了 pushPath 把画布叠在词库上，再点变 no-op）——
      //   ①画布已在栈顶不动；②画布在栈中连续 pop 到顶；③不在栈中 replacePath 顶页直换（无叠栈无闪屏）；④空栈（首页）pushPath
      const names = this.pathStack.getAllPathName();
      const idx = names.indexOf('BBTreeCanvas');
      if (idx >= 0 && idx === names.length - 1) {
        return; // 已在画布
      }
      if (idx >= 0) {
        const pops = names.length - 1 - idx;
        for (let i = 0; i < pops; i++) {
          this.pathStack.pop(); // 连续 pop 到画布为顶
        }
      } else if (names.length > 0) {
        this.pathStack.replacePath({ name: 'BBTreeCanvas' }); // 画布不在栈：顶页替换（词库/对话等任意页直达）
      } else {
        this.pathStack.pushPath({ name: 'BBTreeCanvas' }); // 空栈（首页）：进画布
      }
    }
    // kind === ''（点边栏空白）：常驻态无操作
  }

  aboutToAppear() {
    // ★ 0.195.0：大屏断点检测（同 BBTreeCanvas 判定：屏宽 ≥600vp = 平板/PC 渲染常驻边栏）
    // ★ 0.196.4：只做首帧初始猜测——真值由根 Stack onAreaChange 按窗口实宽写入（分屏/悬浮窗纠正）
    try {
      const d = display.getDefaultDisplaySync();
      this.windowMode.isTablet = d.densityPixels > 0 && d.width / d.densityPixels >= 600;
    } catch (_e) {
      this.windowMode.isTablet = false; // 取显示信息失败：保守按手机处理（无边栏，画布抽屉承担导航）
    }
    // ★ 0.195.0 bugfix：边栏选中态动态跟踪——didShow 拿目标页名（'navBar'=首页清空高亮；
    //   push/pop/replacePath 全走这里，边栏高亮恒与主界面页面一致）
    this.pathStack.setInterception({
      didShow: (from: NavDestinationContext | NavBar, to: NavDestinationContext | NavBar, operation: NavigationOperation, isAnimated: boolean) => {
        if (to === 'navBar') {
          this.currentRoute = '';
        } else {
          this.currentRoute = to.pathInfo.name;
        }
      }
    });
    // ★ 0.194.0-bugfix：老用户补打免费试用时间戳（升级前已登录的账号不会再触发 doLogin 回调）
    stampFreeTrialOnLogin(this.subscription);
    // PersistenceV2: 持久化 JSON 字符串
    const persist = PersistenceV2.connect(PersistData, 'persist-data', () => new PersistData()) as PersistData;
    // ★ 0.151：按画布模式分支恢复工作区（★ 0.151-bugfix2：互通设计——当前模式的池是权威数据源）
    const canvasModeStore = connectCanvasMode();
    // ★ 0.151-bugfix2：旧版两池隔离遗留数据一次性迁移（互通版切换会全量重建目标池，
    // 不迁移则首次切换即丢非权威池的独立数据；migrated 标记保证仅执行一次）
    migrateLegacyPoolsIfNeeded(canvasModeStore.mode);
    if (canvasModeStore.mode === 'tabs') {
      // 选项卡模式：工作区加载当前选中 Tab 的树（无 Tab = 空树，等用户点 ➕ 创建）
      const forest = connectTabForest();
      const tabs = parseTabs(forest.tabsJson);
      const active = tabs.find((t: TabMeta): boolean => t.id === forest.activeTabId);
      const tabTree = active ? deserializeBubbleTree(active.treeJson) : null;
      if (tabTree) {
        AppStorageV2.connect(BubbleTree, 'bubble-tree', () => tabTree);
      } else {
        AppStorageV2.connect(BubbleTree, 'bubble-tree', () => new BubbleTree());
      }
    } else {
      // 平铺模式（现状路径）：尝试从平铺池 JSON 恢复 BubbleTree
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
    } else if (name === 'WordBankPage') { // ★ 0.145：单词库页面（★ 0.189.1：SettingsPage 分支随僵尸页面删除）
      WordBankPage({ pathStack: this.pathStack })
    } else if (name === 'KnowledgeBankPage') { // ★ 0.146：知识库页面
      KnowledgeBankPage({ pathStack: this.pathStack })
    } else if (name === 'AnnotationPage') { // ★ 0.152：屏幕圈选标注页
      AnnotationPage({ pathStack: this.pathStack })
    } else if (name === 'StatisticsPage') { // ★ 0.192.0：学习统计页（边栏「统计」+ 账号行点击）
      StatisticsPage({ pathStack: this.pathStack })
    } else if (name === 'BillingPage') { // ★ 0.194.0：账单/订阅页（边栏「账单」）
      BillingPage({ pathStack: this.pathStack })
    } else if (name === 'ReviewPage') { // ★ 0.196.1：知识复习页（边栏「复习」，Anki 式单卡）
      ReviewPage({ pathStack: this.pathStack })
    }
  }

  build() {
    // ★ 0.174.1：Stack 全局背景层——页面根组件 origBounds 全屏，expandSafeArea 背景可铺满
    // 含手势条区（真机实证：Navigation 的 NavBarContent 布局高度只到 y2024，底部 420px 为
    // NavBar toolbar 预留且 clip 裁剪，Column 在其内 expandSafeArea 底部无法突破露黑；
    // Stack 在 Navigation 外不受 NavBar 裁剪，背景直达全屏——各页安全区统一露暗紫不露黑）
    Stack() {
      // ★ 0.195.0：大屏边栏常驻（用户定稿「边栏一直存在，页面平移，体验非常棒」）——
      //   Row [AppSideBar 208 | Navigation layoutWeight(1)]；手机不渲染边栏（画布抽屉承担导航）
      Row() {
        if (this.isTablet) {
          AppSideBar({
            currentRoute: this.currentRoute, // ★ 0.195.0 bugfix：选中态动态跟踪（高亮恒与主界面一致）
            settingsOpen: this.globalSettingsVisible,
            onNavClick: (kind: string) => {
              this.sideBarNav(kind);
            }
          })
        }
    Navigation(this.pathStack) {
      // 首页内容（★ 0.174.1：按 UI_GUIDELINES 重做——BG_APP 暗紫底 + expandSafeArea 满屏 +
      // Logo 区/主按钮/账号区对齐组件规格；删「图结构对话 · 多分支推理」（用户拍板））
      Column() {
        // ★ 0.179.0：布局改「上标题 + 下按钮组」双区结构——顶部/中部/底部弹性占位 2.5:2.5:1
        //   （★ 0.181.1：原 2:3:1，用户要求标题往下挪一点点——顶部 2→2.5 标题区下移约半份弹性、
        //   中部 3→2.5 对冲，按钮组/版本号位置纹丝不动），
        //   主按钮+登录区落至屏幕下部左手拇指区（用户拍板：左手持握大拇指直接按得到，
        //   原垂直居中布局需另一只手按、体验割裂）；标题/副标题同步放大（24→32 / 11→14）
        Blank().layoutWeight(2.5) // ★ 0.181.1：顶部弹性 2→2.5（标题往下挪）；★ 0.179.0：顶部弹性（标题区悬于上部、不贴顶）
        // ★ 0.174.2：删 Logo 区（用户要求去掉首页分叉图标），标题成为首元素
        Text('DAG AI Chat')
          .fontSize(32) // ★ 0.179.0：标题放大 24→32（用户拍板）
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .fontFamily(FONT_INTER_SEMIBOLD)

        Text('你的AI学习伴侣')
          .fontSize(14) // ★ 0.179.0：副标题放大 11→14（用户拍板）
          .fontColor(TEXT_SECONDARY)
          .margin({ top: 8 })

        Blank().layoutWeight(2.5) // ★ 0.181.1：中部弹性 3→2.5（与顶部增量对冲，按钮组位置不动）；★ 0.179.0：中部弹性——把按钮组推至下部拇指区
        // 主按钮（UI_GUIDELINES 六-9 类推：主紫底 + RADIUS_CONTROL 圆角）
        Button('进入气泡树') // ★ 0.179.0：文案「进入对话画布」→「进入气泡树」（与画布页标题统一，用户拍板）
          .height(44)
          .padding({ left: 24, right: 24 })
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(BRAND_PRIMARY)
          .fontColor(TEXT_PRIMARY)
          .borderRadius(RADIUS_CONTROL)
          .onClick(() => {
            this.pathStack.pushPath({ name: 'BBTreeCanvas' });
          })

        // ★ 0.164：华为账号登录区（★ 0.174.1：对齐 UI_GUIDELINES 六-3/4 账号区规格——
        // 容器 SURFACE_SOFT 柔面 + RADIUS_NAV 圆角；未登录=user 图标容器（描边 STROKE_BRAND）+
        // 双行文案；已登录=头像 36 圆形 + 昵称 + 退出按钮）
        if (this.getHuaweiAccount().isLoggedIn) {
          // 已登录：头像 + 显示名 + 退出账号按钮
          Row() {
            if (this.getHuaweiAccount().avatarUri !== '') {
              Image(this.getHuaweiAccount().avatarUri)
                .width(36)
                .height(36)
                .borderRadius(18)
                .clip(true)
            } else {
              Row() {
                Image($r('app.media.user'))
                  .width(18)
                  .height(18)
              }
              .width(36)
              .height(36)
              .borderRadius(18)
              .backgroundColor(SURFACE_HOVER)
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
            }
            Column() {
              Text(this.getDisplayName())
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(FontWeight.Medium)
                .fontColor(TEXT_PRIMARY)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 160 })
              Text('华为账号已登录')
                .fontSize(FONT_SIZE_CAPTION)
                .fontColor(TEXT_TERTIARY)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 10 })
            Button('退出账号')
              .fontSize(FONT_SIZE_CAPTION)
              .height(30)
              .padding({ left: 12, right: 12 })
              .margin({ left: 12 })
              .backgroundColor(SURFACE_HOVER)
              .fontColor(TEXT_SECONDARY)
              .borderRadius(RADIUS_CONTROL)
              .enabled(!this.isProcessing)
              .onClick(() => {
                this.doLogout();
              })
          }
          .margin({ top: 24 })
          .padding(10)
          .borderRadius(RADIUS_NAV)
          .backgroundColor(SURFACE_SOFT)
          .alignItems(VerticalAlign.Center)
        } else {
          // 未登录：图标容器 + 双行文案（组件规格 4：描边 STROKE_BRAND +「同步知识画布到云端」）
          Row() {
            Row() {
              Image($r('app.media.user'))
                .width(18)
                .height(18)
            }
            .width(36)
            .height(36)
            .borderRadius(18)
            .border({ width: 1, color: STROKE_BRAND })
            .backgroundColor(SURFACE_HOVER)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            Column() {
              Text(this.isProcessing ? '登录中…' : '登录华为账号')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(FontWeight.Medium)
                .fontColor(TEXT_PRIMARY)
              Text('同步到云端') // ★ 0.191.0：文案精简（用户指示：删「知识画布」）
                .fontSize(FONT_SIZE_CAPTION)
                .fontColor(TEXT_TERTIARY)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 10 })
          }
          .margin({ top: 24 })
          .padding(10)
          .borderRadius(RADIUS_NAV)
          .backgroundColor(SURFACE_SOFT)
          .alignItems(VerticalAlign.Center)
          .enabled(!this.isProcessing)
          .onClick(() => {
            this.doLogin(false); // ★ 0.196.11：普通登录路径——成功后询问是否开云同步
          })
        }
        // ★ 0.164：登录/退出结果提示（错误时显示，深浅色适配）
        if (this.loginTip !== '') {
          Text(this.loginTip)
            .fontSize(12)
            .fontColor('#E53935')
            .margin({ top: 8 })
            .maxLines(8) // ★ 0.164.4：调试期 2→8 行，容纳错误码+服务端 message 完整显示
            .textAlign(TextAlign.Center)
        }

        // ★ 版本号体系（0.160.x）：装机后一眼确认设备代码版本；每次改动编译装机递增末位（0.160.1 → 0.160.2 → ...）
        Text('v0.197.0') // ★ 0.197.0：复习卡英文词自适应缩字号防截断+评分按钮底部留白；★ 0.196.12：代码优化——更早历史见 MEMORY.md 版本表
          .fontSize(12)
          .fontColor(TEXT_TERTIARY) // ★ 0.174.1：版本号小字收敛 Token（原 isDark 三元随 getThemeStore 删除）
          .margin({ top: 12 })

        Blank().layoutWeight(1) // ★ 0.179.0：底部弹性——版本号与底部留白
      }
      .width('100%')
      .height('100%')
      // ★ 0.179.0：删 justifyContent(Center)——垂直布局改由 Blank 弹性占位（2.5:2.5:1，★ 0.181.1 原 2:3:1）接管
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(BG_APP) // ★ 0.174.1：应用底色暗紫（UI_GUIDELINES Token，替换旧深灰 #1A1A1A）
      .expandSafeArea([SafeAreaType.SYSTEM]) // ★ 0.174.1：背景延伸进状态栏/导航条安全区——首页满屏高度（用户报「高度是短的」；省略 edges 参数=默认全部边，第二参数类型是 SafeAreaEdge 非 SafeAreaType）
    }
    .navDestination(this.pageMap)
    // ★ 0.166.2：Auto 模式下平板宽屏自动切分栏——首页一直占左栏、画布只占右栏（用户实测
    // 「首页一直出现在屏幕左边」）；改 Stack 强制单栏，push 后目标页全屏覆盖，平板与手机一致
    .mode(NavigationMode.Stack)
    .layoutWeight(1) // ★ 0.195.0：边栏常驻布局——Navigation 占边栏右侧剩余区域（页面在此平移不遮边栏）
      }
      // ★ 0.195.0：全局设置弹窗（常驻边栏「设置」入口；实例与画布/对话页共用 PersistenceV2 数据）
      if (this.globalSettingsVisible) {
        GlobalSettingsDialog({
          onClose: () => {
            this.globalSettingsVisible = false;
          }
        })
      }
    // ★ 0.195.0：订阅提醒弹窗（Stack 顶层——盖在 Navigation 之上；倒计时「去账单」CTA 直跳订阅页）
    ReminderDialog({
      visible: this.reminderVisible,
      mode: this.reminderMode,
      onClose: () => {
        this.reminderVisible = false;
      },
      onGoBilling: () => {
        this.reminderVisible = false;
        this.pathStack.pushPath({ name: 'BillingPage' });
      }
    })
    // ★ 0.196.9：退出华为账号确认（边栏头像触发——原系统 AlertDialog 灰底，用户实测反馈
    //   与暗紫风格不符；确认走 doLogout：退出 + 云同步强制关一条龙）
    AppConfirmDialog({
      visible: this.confirmDialog.logoutConfirmVisible,
      title: '退出华为账号',
      message: '退出后将停止云同步，本地学习数据不受影响。',
      confirmText: '退出',
      cancelText: '取消',
      onConfirm: () => {
        this.confirmDialog.logoutConfirmVisible = false;
        this.doLogout();
      },
      onCancel: () => {
        this.confirmDialog.logoutConfirmVisible = false;
      }
    })
    // ★ 0.196.9：登录后「是否开启云同步」询问（三条登录路径触发 store——弹窗集中本处挂载）
    AppConfirmDialog({
      visible: this.confirmDialog.cloudSyncPromptVisible,
      title: '开启云同步',
      message: '已登录华为账号。是否开启云同步？开启后，登录同一华为账号的多台设备对话数据自动保持一致。',
      confirmText: '开启云同步',
      cancelText: '暂不开启',
      onConfirm: () => {
        this.confirmDialog.cloudSyncPromptVisible = false;
        enableCloudSyncNow(this.getUIContext());
      },
      onCancel: () => {
        this.confirmDialog.cloudSyncPromptVisible = false;
      }
    })
    // ★ 0.196.10：未登录点「开启云同步」→ 登录引导弹窗（设置页触发；用户拍板：左「登录华为
    //   账号」右「取消」，点登录直拉 doLogin）
    // ★ 0.196.11：fromSyncEntry=true——入口即意图，登录成功**直接开云同步**不再弹询问
    //   （用户实测反馈：从云同步入口进来的，登录完再问「要不要开云同步」多此一举）
    AppConfirmDialog({
      visible: this.confirmDialog.loginPromptVisible,
      title: '需要登录',
      message: '云同步与华为账号绑定，请先登录华为账号。',
      confirmText: '登录华为账号',
      cancelText: '取消',
      confirmOnLeft: true,
      onConfirm: () => {
        this.confirmDialog.loginPromptVisible = false;
        this.doLogin(true);
      },
      onCancel: () => {
        this.confirmDialog.loginPromptVisible = false;
      }
    })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG_APP) // ★ 0.174.1：全局兜底底色（各页背景未铺到的安全区露暗紫不露黑）
    .expandSafeArea([SafeAreaType.SYSTEM]) // ★ 0.174.1：背景延伸进状态栏/导航条安全区——满屏
    // ★ 0.196.4：窗口实宽写入共享模式——根 Stack 满窗，onAreaChange 在分屏/悬浮窗 resize 时
    //   实时纠正（首帧用 aboutToAppear 屏宽猜测，此处一帧内校正；≥600vp=平板布局）
    .onAreaChange((oldVal: Area, newVal: Area) => {
      this.windowMode.isTablet = (newVal.width as number) >= 600;
    })
  }
}
