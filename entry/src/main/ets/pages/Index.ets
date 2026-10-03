// ============================================================
// Index.ets — 应用首页入口
// ============================================================
// 本文件是应用的入口页面，负责：
//   - 初始化持久化数据（PersistenceV2 连接）
//   - 从 JSON 恢复气泡树（反序列化）
//   - 首次启动时创建默认气泡树（根节点）
//   - 配置 NavPathStack 导航路由（气泡画布 / 对话页 / 设置页）
//
// 页面导航关系：
//   Index → BBTreeCanvas（气泡画布）→ ChatPage（对话页）→ AnnotationPage（屏幕标注，★ 0.152）
//                                  → SettingsPage（设置页）
//                                  → WordBankPage（单词库，★ 0.145）
//                                  → KnowledgeBankPage（知识库，★ 0.146）
// ============================================================

import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import { BBTreeCanvas } from '../components/BBTreeCanvas';
import { ChatPage } from '../components/ChatPage';
import { SettingsPage } from '../components/SettingsPage';
import { WordBankPage } from '../components/WordBankPage'; // ★ 0.145：单词库页面路由
import { KnowledgeBankPage } from '../components/KnowledgeBankPage'; // ★ 0.146：知识库页面路由
import { AnnotationPage } from '../components/AnnotationPage'; // ★ 0.152：屏幕圈选标注页路由
import { BubbleNode, ChatMessage, BubbleTree, ApiConfig, PersistData, generateNodeId, generateMessageId, deserializeBubbleTree, TabMeta, connectCanvasMode, connectTabForest, parseTabs, migrateLegacyPoolsIfNeeded } from '../common/ChatModel';
import { ThemeStore } from '../entryability/EntryAbility'; // ★ 0.131：深浅色适配
import { HuaweiAccountStore, connectHuaweiAccount, loginWithHuaweiID, logoutHuaweiID } from '../utils/HuaweiAccountUtil'; // ★ 0.164：华为账号登录
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

  // ★ 0.131：获取全局主题状态（与 BBTreeCanvas/ChatPage 相同模式）
  getThemeStore(): ThemeStore {
    return AppStorageV2.connect(ThemeStore, 'theme-store', () => new ThemeStore()) as ThemeStore;
  }

  // ★ 0.164：获取华为账号登录态（PersistenceV2 单例）
  getHuaweiAccount(): HuaweiAccountStore {
    return connectHuaweiAccount();
  }

  // ★ 0.164：点击华为账号登录
  doLogin() {
    if (this.isProcessing) {
      return;
    }
    this.isProcessing = true;
    this.loginTip = '';
    const context = this.getUIContext().getHostContext() as common.Context;
    loginWithHuaweiID(context).then((tip: string) => {
      this.isProcessing = false;
      if (tip !== '') {
        this.loginTip = tip;
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

  aboutToAppear() {
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
    } else if (name === 'SettingsPage') {
      SettingsPage({ pathStack: this.pathStack })
    } else if (name === 'WordBankPage') { // ★ 0.145：单词库页面
      WordBankPage({ pathStack: this.pathStack })
    } else if (name === 'KnowledgeBankPage') { // ★ 0.146：知识库页面
      KnowledgeBankPage({ pathStack: this.pathStack })
    } else if (name === 'AnnotationPage') { // ★ 0.152：屏幕圈选标注页
      AnnotationPage({ pathStack: this.pathStack })
    }
  }

  build() {
    Navigation(this.pathStack) {
      // 首页内容
      Column() {
        Text('DAG AI Chat')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333') // ★ 0.131：深浅色适配

        Text('图结构对话 · 多分支推理')
          .fontSize(14)
          .fontColor(this.getThemeStore().isDark ? '#888888' : '#999999') // ★ 0.131：深浅色适配
          .margin({ top: 8 })

        Button('进入对话画布')
          .margin({ top: 40 })
          .onClick(() => {
            this.pathStack.pushPath({ name: 'BBTreeCanvas' });
          })

        // ★ 0.164：华为账号登录区（进入对话画布下方）
        if (this.getHuaweiAccount().isLoggedIn) {
          // 已登录：显示昵称（或 ID）+ 退出账号按钮
          Row() {
            Text(this.getDisplayName())
              .fontSize(14)
              .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 180 })
            Button('退出账号')
              .fontSize(13)
              .height(32)
              .margin({ left: 12 })
              .backgroundColor(this.getThemeStore().isDark ? '#3A3A3A' : '#E0E0E0')
              .fontColor(this.getThemeStore().isDark ? '#CCCCCC' : '#666666')
              .enabled(!this.isProcessing)
              .onClick(() => {
                this.doLogout();
              })
          }
          .margin({ top: 16 })
          .alignItems(VerticalAlign.Center)
        } else {
          // 未登录：华为账号登录按钮
          Button(this.isProcessing ? '登录中…' : '华为账号登录')
            .margin({ top: 16 })
            .backgroundColor(this.getThemeStore().isDark ? '#2E5A88' : '#1976D2')
            .enabled(!this.isProcessing)
            .onClick(() => {
              this.doLogin();
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
        Text('v0.168.4') // ★ 0.168.4 抽屉唤出改左下角固定 ☰ 按钮（样式同右下角缩放控件、底缘对齐）+删边缘右滑热区与诊断日志（系统手势区占左缘 0~65px：快滑=系统返回/慢拖被吞）；★ 0.168.3 抽屉层 overlay→Stack（overlay 不参与 hit test 真机实证）；0.168.2 唤出判定 onActionEnd（中途唤出→热区卸载触摸流重路由→抬手落点自关死循环）；0.168.1 热区透明穿透修复；0.168 左侧边栏落地：平板 208 常驻（Logo+应用名+工作区+画布/单词库/知识库+设置+账号）/ 手机 72 窄栏抽屉（左下角 ☰ 按钮唤出、点遮罩或空白收起、返回键先收抽屉）；⚙ 移边栏底部；导航 pushPath「哪进哪回」；0.167.8 七项：①大屏分段控件选项固定高 30（track 总高 36 与⚙/➕等高对齐）②小屏加回「知识画布+N个气泡·N条对话」标题统计③小屏信息条 left 28→14 返回箭头左移与➕留白一致④分段控件「画布」改「平铺」⑤删设置弹窗「画布」Tab（切换逻辑归画布页分段控件）⑥bugfix 分段控件切后点不回（applyCanvasModeSwitch 不写 mode、switchCanvasMode 漏写致守卫单向锁死，补 canvasModeStore.mode=targetMode）⑦app图标换新LOGO（app.json5 icon 改指 $media:app_logo，1024×1024 深底白字 DAG 气泡）；0.167.7：①信息条上方留白 24→8 与下方对齐 ②右上角 4 按钮右移（right 28→14）③fitViewport topSafe 随底板新高度重算（flat 64 / tabs 108）；0.167.6：小屏顶栏极简 4 图标 + fitViewport 垂直居中区排除信息条底板；0.167.5：①信息条不透明底板 ②新建按钮恢复双态 ③分段控件全设备放主行⚙左边 ④根气泡 x 轴恒对齐；0.167.4：整体等比缩放 + 缩放限幅方向感知 + 多根纵向堆叠；0.167.3：连线统一中间出发 + 子树占位法防重叠 + 气泡宽 150
          .fontSize(12)
          .fontColor(this.getThemeStore().isDark ? '#666666' : '#AAAAAA')
          .margin({ top: 12 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.getThemeStore().isDark ? '#1A1A1A' : '#FAFAFA') // ★ 0.131：深浅色适配（与其他页面一致）
    }
    .navDestination(this.pageMap)
    // ★ 0.166.2：Auto 模式下平板宽屏自动切分栏——首页一直占左栏、画布只占右栏（用户实测
    // 「首页一直出现在屏幕左边」）；改 Stack 强制单栏，push 后目标页全屏覆盖，平板与手机一致
    .mode(NavigationMode.Stack)
  }
}
