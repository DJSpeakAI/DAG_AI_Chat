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
import { HuaweiAccountStore, connectHuaweiAccount, loginWithHuaweiID, logoutHuaweiID } from '../utils/HuaweiAccountUtil'; // ★ 0.164：华为账号登录
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
    // ★ 0.174.1：Stack 全局背景层——页面根组件 origBounds 全屏，expandSafeArea 背景可铺满
    // 含手势条区（真机实证：Navigation 的 NavBarContent 布局高度只到 y2024，底部 420px 为
    // NavBar toolbar 预留且 clip 裁剪，Column 在其内 expandSafeArea 底部无法突破露黑；
    // Stack 在 Navigation 外不受 NavBar 裁剪，背景直达全屏——各页安全区统一露暗紫不露黑）
    Stack() {
    Navigation(this.pathStack) {
      // 首页内容（★ 0.174.1：按 UI_GUIDELINES 重做——BG_APP 暗紫底 + expandSafeArea 满屏 +
      // Logo 区/主按钮/账号区对齐组件规格；删「图结构对话 · 多分支推理」（用户拍板））
      Column() {
        // ★ 0.174.2：删 Logo 区（用户要求去掉首页分叉图标），标题成为首元素、去顶部间距保持居中
        Text('DAG AI Chat')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .fontFamily(FONT_INTER_SEMIBOLD)

        Text('你的AI学习伴侣')
          .fontSize(FONT_SIZE_META)
          .fontColor(TEXT_SECONDARY)
          .margin({ top: 6 })

        // 主按钮（UI_GUIDELINES 六-9 类推：主紫底 + RADIUS_CONTROL 圆角）
        Button('进入对话画布')
          .height(44)
          .padding({ left: 24, right: 24 })
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(BRAND_PRIMARY)
          .fontColor(TEXT_PRIMARY)
          .borderRadius(RADIUS_CONTROL)
          .margin({ top: 40 })
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
              Text('同步知识画布到云端')
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
        Text('v0.174.4') // ★ 0.174.4：纠正 0.174.3 图标方向——app 图标改分叉 logo（用户拍板：gitbranch 视觉锚点，复刻 app 内视觉语言=225° 渐变 #7C4DFF→#A78BFA 底 + 白色分叉图标，GDI+ 生成 1024×1024），app_logo.png + AppScope/entry 两处 background.png 三资源位替换（0.174.3 误换成 DAG 气泡图已覆盖纠正；DAGAI 桌面名保留）；0.174.3：app 图标整体换新 LOGO（白色 DAG 气泡）——app_logo.png（深黑版，大图 3552 高质量缩放 1024×1024）+ AppScope/entry 两处 background.png（深紫版 1024×1024）三资源位替换，桌面/分层图标/申请用 logo 统一视觉锚点；桌面名三处统一改 "DAGAI"（app_name/EntryAbility_label/app_short_name）；0.174.2：删首页 Logo 区（56×56 渐变容器+gitbranch 分叉图标，用户要求去掉），标题成首元素去 margin top 16 保持垂直居中；import 清 BRAND_SECONDARY/RADIUS_LOGO；0.174.1 首页+全局设置按 UI_GUIDELINES 重做——首页 BG_APP 暗紫底 + expandSafeArea 满屏（修高度不满屏）+ Logo 区渐变图标/主按钮/账号区对齐组件规格、删「图结构对话 · 多分支推理」；设置弹窗色值全收敛 DesignTokens（删 isDark 三元）、Tab 行分段控件化、按钮/开关主紫化、面板 SURFACE_NODE+描边；★ 0.173.2 bugfix：双击进不了气泡——单击手势与系统 TapGesture(count:2) 并列绑定时被手势仲裁吃掉识别流，删系统双击手势改单击内手动判定（同气泡两次单击 <300ms=双击进入；单击选中即时反馈不受影响）；0.173.1 四项：①气泡宽 150→170（元信息行「N 条对话 · X分钟前」完整显示不再截断）②单击任意气泡即选中——高亮卡片+「双击进入对话」+连线高亮（与进入后返回选中样式一致，双击仍进对话）③边栏副标题改「你的AI学习伴侣」④删边栏「工作区」标签；0.172.3 气泡树所有节点卡片加最近消息时间——元信息行「N 条对话 · X小时前/昨天/X天前」（最后一条消息 messageId 内嵌时间戳解析，零模型改动、旧数据天然支持）；0.172.2 气泡树间距再减 1/3——verticalSpacing 136→113（气泡间净空 68→45 ≈ 气泡高度×2/3，连线更短；已有树点「重新排列」生效）；0.172.1 气泡树连线缩短——层级间垂直间距 160→136（气泡间净空=气泡高度 68，用户拍板）；0.170.2 手机抽屉内容对齐平板完整版——Logo+应用名+副标题/工作区标签/导航带中文文字/设置/账号行全放开，抽屉同宽 208（原 72 窄栏纯图标分支删除：点击唤出浮层宽度不再是约束）；0.170.1 画布左下角 ☰ 按钮左缘贴边 24→14、右下角缩放控件右缘贴边 24→14（与信息条边距 14 对齐，底缘对齐不变）；0.169.1 AI 回复底部复习区（生词+知识卡）加划词：词/全称/释义/标题/定义行长按弹「翻译/入知识库/复制」三项悬浮栏（无全选/删除，音标行不加）；0.168.4 抽屉唤出改左下角固定 ☰ 按钮（样式同右下角缩放控件、底缘对齐）+删边缘右滑热区与诊断日志（系统手势区占左缘 0~65px：快滑=系统返回/慢拖被吞）；★ 0.168.3 抽屉层 overlay→Stack（overlay 不参与 hit test 真机实证）；0.168.2 唤出判定 onActionEnd（中途唤出→热区卸载触摸流重路由→抬手落点自关死循环）；0.168.1 热区透明穿透修复；0.168 左侧边栏落地：平板 208 常驻（Logo+应用名+工作区+画布/单词库/知识库+设置+账号）/ 手机 72 窄栏抽屉（左下角 ☰ 按钮唤出、点遮罩或空白收起、返回键先收抽屉）；⚙ 移边栏底部；导航 pushPath「哪进哪回」；0.167.8 七项：①大屏分段控件选项固定高 30（track 总高 36 与⚙/➕等高对齐）②小屏加回「知识画布+N个气泡·N条对话」标题统计③小屏信息条 left 28→14 返回箭头左移与➕留白一致④分段控件「画布」改「平铺」⑤删设置弹窗「画布」Tab（切换逻辑归画布页分段控件）⑥bugfix 分段控件切后点不回（applyCanvasModeSwitch 不写 mode、switchCanvasMode 漏写致守卫单向锁死，补 canvasModeStore.mode=targetMode）⑦app图标换新LOGO（app.json5 icon 改指 $media:app_logo，1024×1024 深底白字 DAG 气泡）；0.167.7：①信息条上方留白 24→8 与下方对齐 ②右上角 4 按钮右移（right 28→14）③fitViewport topSafe 随底板新高度重算（flat 64 / tabs 108）；0.167.6：小屏顶栏极简 4 图标 + fitViewport 垂直居中区排除信息条底板；0.167.5：①信息条不透明底板 ②新建按钮恢复双态 ③分段控件全设备放主行⚙左边 ④根气泡 x 轴恒对齐；0.167.4：整体等比缩放 + 缩放限幅方向感知 + 多根纵向堆叠；0.167.3：连线统一中间出发 + 子树占位法防重叠 + 气泡宽 150
          .fontSize(12)
          .fontColor(TEXT_TERTIARY) // ★ 0.174.1：版本号小字收敛 Token（原 isDark 三元随 getThemeStore 删除）
          .margin({ top: 12 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(BG_APP) // ★ 0.174.1：应用底色暗紫（UI_GUIDELINES Token，替换旧深灰 #1A1A1A）
      .expandSafeArea([SafeAreaType.SYSTEM]) // ★ 0.174.1：背景延伸进状态栏/导航条安全区——首页满屏高度（用户报「高度是短的」；省略 edges 参数=默认全部边，第二参数类型是 SafeAreaEdge 非 SafeAreaType）
    }
    .navDestination(this.pageMap)
    // ★ 0.166.2：Auto 模式下平板宽屏自动切分栏——首页一直占左栏、画布只占右栏（用户实测
    // 「首页一直出现在屏幕左边」）；改 Stack 强制单栏，push 后目标页全屏覆盖，平板与手机一致
    .mode(NavigationMode.Stack)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG_APP) // ★ 0.174.1：全局兜底底色（各页背景未铺到的安全区露暗紫不露黑）
    .expandSafeArea([SafeAreaType.SYSTEM]) // ★ 0.174.1：背景延伸进状态栏/导航条安全区——满屏
  }
}
