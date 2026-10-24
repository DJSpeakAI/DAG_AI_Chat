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
import { SketchPage } from '../components/SketchPage'; // ★ 0.297.0：数学证明画板页路由
import { StatisticsPage } from '../components/StatisticsPage'; // ★ 0.192.0：学习统计页路由
import { BillingPage } from '../components/BillingPage'; // ★ 0.194.0：账单/订阅页路由
import { APP_VERSION } from '../components/GlobalSettingsDialog'; // ★ 0.301.0：版本号单一来源（GSD export 常量——修 Index 硬编码漏更七版 bug，版本同步点从两处制回三处制）
import { ReviewPage } from '../components/ReviewPage'; // ★ 0.196.1：知识复习页路由（Anki 式单卡，边栏「复习」入口）
import { WindowMode, connectWindowMode, IndexSidebarState, connectIndexSidebarState } from '../common/WindowMode'; // ★ 0.196.4：窗口宽度模式共享真相源；★ 0.219.0：IndexSidebarState 宽屏边栏收起状态；★ 0.220.0：SidebarSectionState 折叠态+KbFolderNavStore 文件夹导航
import { BubbleNode, BubbleTree, ApiConfig, PersistData, generateNodeId, deserializeBubbleTree, serializeBubbleTree, migrateLegacyDemoSeed, TabMeta, connectCanvasMode, connectTabForest, parseTabs, migrateLegacyPoolsIfNeeded, onLoginAccountHooks, wipeHistoricalTestStats, maybeShowSignInAfterGateReady, ensureSpAuth } from '../common/ChatModel'; // ★ 0.305.1：订阅语义清零（stampFreeTrialOnLogin→onLoginAccountHooks；ReminderDialog/isVip/倒计时引擎随订阅退役删除）；★ 0.279.1：wipeHistoricalTestStats 启动清理测试统计；★ 0.310.1：ChatMessage/generateMessageId 随默认示例气泡退役删除；serializeBubbleTree/migrateLegacyDemoSeed=示例气泡一次性迁移；★ 0.311.0：maybeShowSignInAfterGateReady（礼包关闭后补弹首日签到）
import { SidebarSectionState, connectSidebarSection, KbFolderNavStore, connectKbFolderNav } from '../common/KnowledgeModel'; // ★ 0.220.0：边栏折叠态+文件夹导航共享 store（AppSideBar 树与页内视图同源）
import { WordSidebarSectionState, connectWordSidebarSection } from '../common/WordModel'; // ★ 0.222.19：单词库边栏折叠态共享 store（独立 key，与知识库隔离）
import { shouldPromptCloudSyncAfterLogin, disableCloudSyncOnLogout } from '../utils/CloudSyncUtil'; // ★ 0.196.8：云同步↔华为账号耦合；★ 0.196.9：弹窗 UI 移 AppConfirmDialog（暗紫）；★ 0.311.1：开启动作统一走 CloudSyncPermissionGuide
import { enableCloudSyncWithGuide } from '../utils/CloudSyncPermissionGuide'; // ★ 0.311.1：云同步授权统一入口（拒绝→直达权限面板+指路，门卫/GSD 同款）
import { siyiGateBlockReason } from '../utils/SiyiGate'; // ★ 0.293.0：SP 云同步门卫（引导弹窗文案/动作分支；权限刷新在 GSD/EntryAbility——0.305.2 清 unused import）
import { AppConfirmDialog, ConfirmDialogStore, connectConfirmDialog } from '../components/AppConfirmDialog'; // ★ 0.196.9：通用确认弹窗（退出账号/云同步询问——Index 根唯一挂载点）
import { SignInDialog, LevelUpDialog } from '../components/SignInDialog'; // ★ 0.256.0：签到弹窗+称号升级弹窗（桥驱动，Index 根唯一挂载点）
import { AppSideBar } from '../components/AppSideBar'; // ★ 0.195.0：大屏常驻边栏（用户定稿：边栏一直存在，页面平移）
import { GlobalSettingsDialog, GlobalSettingsSharedStore, connectGlobalSettingsShared } from '../components/GlobalSettingsDialog'; // ★ 0.195.0：常驻边栏「设置」入口（与画布/对话页实例共用 PersistenceV2 数据）；★ 0.230.0：加共享开态 store
import display from '@ohos.display'; // ★ 0.195.0：大屏断点检测（屏宽 ≥600vp 渲染常驻边栏，同 BBTreeCanvas 判定）
import { connectUndoStack, UndoStore } from '../common/UndoStack'; // ★ 0.287.0：操作撤销栈（Ctrl+Z/Ctrl+Shift+Z 全局键——Index 根挂载覆盖全部子页）
import { deviceInfo } from '@kit.BasicServicesKit'; // ★ 0.222.11：设备类型兜底——畅享90pro 屏宽 600.6vp 踩线误判平板，手机端恒手机模式（抽屉导航）
import { loginWithHuaweiID, logoutHuaweiID, AUTH_CANCELLED_TIP } from '../utils/HuaweiAccountUtil'; // ★ 0.164：华为账号登录；★ 0.196.9：AUTH_CANCELLED_TIP——用户取消登录静默；★ 0.305.3：HuaweiAccountStore/connectHuaweiAccount 随首页正常态账号区退役清 unused import
import { clearAllLocalUserData } from '../utils/DataWipeUtil'; // ★ 0.263.0：退出登录「同时清空本机数据」（借给他人前场景）
import { RADIUS_CONTROL, FONT_SIZE_CAPTION, FONT_SIZE_BODY, FONT_SIZE_CARD_TITLE_SM, FONT_INTER_SEMIBOLD } from '../common/DesignTokens'; // ★ 0.306.0：RADIUS_NAV 未消费清出（0.305.1 清 import 漏网）
import { common } from '@kit.AbilityKit'; // ★ 0.164：登录接口需要 Context
import { connectWordBank } from '../utils/WordStoreUtil'; // ★ 0.204.0：启动构建桌面卡片快照
import { connectKnowledgeBank } from '../utils/KnowledgeStoreUtil'; // ★ 0.204.0：同上
import { buildWidgetState } from '../utils/WidgetHostBridge'; // ★ 0.204.0：同上；★ 0.204.3：ensureWidgetFormIds formId 自愈
import { ensureWidgetFormIds } from '../utils/WidgetReviewUtil'; // ★ 0.204.3：卸载重装后残留卡片推送自愈
import { connectDailyReviewCount } from '../common/DailyReviewCountStore'; // ★ 0.204.0：每日量（快照按量截断）；★ 0.274.0 外提件（原居 ReviewPage）
import { buildBackupPayload, writeInternalBackup, readInternalBackup, restoreFromPayload, maybeAutoBackup, BackupPayload } from '../utils/BackupUtil'; // ★ 0.205.0：数据安全三道防线（启动备份链+空库恢复弹窗）
import { AgreementDialog } from '../components/AgreementDialog'; // ★ 0.226.0：华为协议登录门禁（非首启路径）
import { AgreementBridge, connectAgreementBridge, connectAgreement, markAgreed, needsAgreement, needsHwAgreement, markHwAgreed, markImprovePromptShown, markLocalModeNoticeShown, AGREEMENT_CHECK_PREFIX, AGREEMENT_USER_NAME, AGREEMENT_PRIVACY_NAME, AGREEMENT_HUAWEI_NAME, HUAWEI_ACCOUNT_AGREEMENT_URL, USER_AGREEMENT_SECTIONS, PRIVACY_SECTIONS, isPrivacySensitiveSection, AgreementStore, AGREEMENT_VERSION } from '../utils/Agreement'; // ★ 0.226.0：同意状态 + 首页勾选框文案；★ 0.264.0：华为协议登录门禁拆分；★ 0.279.5：markImprovePromptShown 落盘收口；★ 0.305.0：门禁并入首页；★ 0.305.3：needsAgreement（冷启直达画布判定）；★ 0.305.5：markLocalModeNoticeShown（本地模式告知弹窗记忆）
import { setTrackingEnabled, trackFirstAuto } from '../utils/TrackUtil'; // ★ 0.226.0：体验改进计划加入；★ 0.260.0：加入后补报 app_first
import { ThemeChooseDialog } from '../components/ThemeChooseDialog'; // ★ 0.262.0：新用户首启主题选择弹窗（协议同意后弹）
import { AppTheme, connectAppTheme, connectThemeMode, ThemeMode } from '../common/AppTheme'; // ★ 0.262.0：theme-mode-v1 空串哨兵（未落盘=新用户待选择）+ 色值真相源成员；★ 0.303.0：ThemeMode 外观页回调

// 首页入口 — V2 全量迁移
@Entry
@ComponentV2
struct Index {
  theme: AppTheme = connectAppTheme();
  pathStack: NavPathStack = new NavPathStack();

  // ★ 0.164：登录/退出请求进行中标记（防连点，官方 1001500002 重复请求错误码要求点击控制）
  @Local isProcessing: boolean = false;
  // ★ 0.303.0：首启合并门禁的登录失败/取消提示（首启一屏独立展示；常规登录失败走 toast——0.305.3）
  @Local onboardingTip: string = '';

  // ★ 0.205.0：空库+有内部备份→恢复询问弹窗（数据安全第二道防线兜底）
  @Local restorePromptVisible: boolean = false;
  pendingRestore: BackupPayload | undefined = undefined; // 待恢复载荷（弹窗确认后消费；大对象不放装饰字段）
  // ★ 0.195.0：大屏常驻边栏——断点检测（≥600vp 平板/PC）+ 设置弹窗（边栏「设置」入口）
  // ★ 0.196.4：isTablet 改窗口宽度共享真相源（WindowMode）——分屏/悬浮窗屏宽不变导致小窗仍渲染
  //   平板布局（用户实测边栏挤压+黑屏）；本页根 onAreaChange 写入窗口实宽，首帧用屏宽猜测
  windowMode: WindowMode = connectWindowMode();
  // ★ 0.222.11：设备类型兜底——手机（deviceType='phone'）永远手机模式（<600 抽屉），
  //   不受 600vp 断点踩线误判影响（畅享90pro 1128px≈600.6vp 被旧断点误判平板）；
  //   Pad/PC(2in1) 维持窗口宽度断点不变
  isPhoneDevice: boolean = deviceInfo.deviceType === 'phone';
  // ★ 0.279.6：PC（2in1）恒按平板布局——用户实测「PC 窗口缩小到很小后边栏直接消失，对话页也没有
  //   任何边栏切换入口」（Pad/手机有抽屉、PC 窄窗走手机布局但对话页无抽屉=导航断头）。
  //   用户拍板：PC 不管窗口多小都要保留边栏。故 PC 恒 isTablet=true，Pad/手机维持原断点/手机布局。
  //   ★ 边栏宽度随窗口自适应（极窄窗按比例收窄，不与内容区抢满），见 sidebarWidth。
  isPcDevice: boolean = deviceInfo.deviceType !== 'phone' && deviceInfo.deviceType !== 'tablet' &&
    deviceInfo.deviceType !== 'tv' && deviceInfo.deviceType !== 'car' && deviceInfo.deviceType !== 'wearable'; // ★ 与 ChatPage/WordBankPage 既有 PC 档判定同口径（非移动设备全算 PC）
  @Local winWidth: number = 0; // 窗口实宽（vp，onAreaChange 写入；PC 窄窗边栏收窄依据）
  undoStack: UndoStore = connectUndoStack(); // ★ 0.287.0：操作撤销栈（Ctrl+Z/Ctrl+Shift+Z 全局键消费；会话级不落盘）
  @Computed get isTablet(): boolean {
    return this.windowMode.isTablet;
  }
  // ★ 0.279.6：边栏宽度自适应——宽窗维持 208 原值；PC 窄窗按 42% 收窄、下限 140（保证导航可读可用），
  //   避免窗口缩到手机宽度时 208 边栏把内容区挤没（用户偏好：布局不写死、随屏幕大小自适应）。
  @Computed get sidebarWidth(): number {
    if (!this.isPcDevice) {
      return 208;
    }
    const w = this.winWidth > 0 ? this.winWidth : 208;
    return Math.max(140, Math.min(208, Math.floor(w * 0.42)));
  }
  // ★ 0.219.0：宽屏边栏收起状态（AppStorageV2 共享实例——气泡树页把手与本页同源，跨页面保持收起）
  indexSidebarState: IndexSidebarState = connectIndexSidebarState();
  // ★ 0.220.0：边栏折叠态+文件夹导航（AppSideBar 与本页共享——点知识库折叠六大模块出文件夹树）
  kbSection: SidebarSectionState = connectSidebarSection();
  folderNav: KbFolderNavStore = connectKbFolderNav();
  wbSection: WordSidebarSectionState = connectWordSidebarSection(); // ★ 0.222.19：单词库边栏折叠态
  // ★ 0.195.0 bugfix：边栏选中态跟踪——didShow 拦截拿目标页名（'navBar'=首页 → 清空无高亮；
  //   用户实测报 bug：停在统计页边栏仍高亮气泡树「对不上」，原画布项硬编码永久高亮已废）
  @Local currentRoute: string = '';
  // ★ 0.230.0：设置弹窗开态升共享真相源（原 @Local——返回键事件只达栈顶 NavDestination，
  //   词库/知识库等页 onBackPressed 不知弹窗开态→返回键不关弹窗；共享后任何页可拦，见 GlobalSettingsDialog.ets）
  gsShared: GlobalSettingsSharedStore = connectGlobalSettingsShared();
  confirmDialog: ConfirmDialogStore = connectConfirmDialog(); // ★ 0.196.9：确认弹窗触发桥（退出账号/云同步询问——根 Stack 挂载消费）
  // ★ 0.226.0：阅读并同意——运行时桥（弹窗可见性 / 待执行动作 / 体验改进引导）+ 首页勾选框本地态
  agreementBridge: AgreementBridge = connectAgreementBridge();
  // ★ 0.279.2：协议同意持久化态（响应式接入——水合迟到翻真时弹窗自动校正的观察源）
  agreement: AgreementStore = connectAgreement();
  // ★ 0.305.0 架构重构（用户拍板「不要在首页上盖一层」）：首启门禁不再做独立全屏覆盖层，
  //   改为**首页未同意态**——同一个首页两态渲染（品牌区共用、零重复）。协议存储 0.279.5 已迁
  //   preferences 同步接口（getSync 即时真值），@Computed 首帧即准，无延迟无水合竞态。
  //   合规不变：未同意时唯一可见内容=门禁态；侧边栏与页面跳转由逻辑守卫拦截（非视觉盖层）。
  @Computed get needsOnboarding(): boolean {
    return !this.agreement.agreed || this.agreement.agreedVersion < AGREEMENT_VERSION;
  }
  // 门禁态交互状态（原 OnboardingGate 组件内状态迁入——组件文件删除）
  @Local onboardingChecked: boolean = false;   // 默认未勾选（合规红线）
  @Local onboardingViewing: number = -1;       // -1=门禁主态 0=用户协议正文 1=隐私政策正文
  @Local onboardingShakeX: number = 0;         // 未勾选点登录/暂不登录=协议勾选行抖动偏移（★0.305.4 锚点自按钮迁到协议行；文字提示 hint 随之退役）
  // ★ 0.279.2 华为协议门禁弹窗同款校正（hwAgreed 水合迟到同理）
  @Computed get showHwAgreementPrompt(): boolean {
    return this.agreementBridge.hwPromptVisible && !this.agreement.hwAgreed;
  }
  @Local themeChooseVisible: boolean = false; // ★ 0.262.0：新用户主题选择弹窗（协议同意后、theme-mode-v1 未落盘时弹）
  @Local localModeNoticeVisible: boolean = false; // ★ 0.305.5：本地模式功能告知弹窗（每设备一次，agreement store 记忆）

  // ★ 0.164：点击华为账号登录
  // ★ 0.196.11：fromSyncEntry 参数——登录来源分流（用户实测反馈：从设置页「开启云同步」
  //   入口进来登录的，入口即意图，登录成功**直接开云同步**，不再弹「是否开启云同步」多此一举；
  //   主页/边栏/账单页等普通登录路径保持询问弹窗）
  doLogin(fromSyncEntry: boolean) {
    if (this.isProcessing) {
      return;
    }
    // ★ 0.305.0：基础协议门禁已由首页未同意态承担（唯一同意入口）——未同意时进不了任何
    //   二级页/侧边栏，故此处只保留华为账号协议门禁（登录门槛）
    if (needsHwAgreement()) {
      this.agreementBridge.pendingAction = fromSyncEntry ? 'sync' : 'login';
      this.agreementBridge.hwPromptVisible = true;
      return;
    }
    this.loginCore(fromSyncEntry, false);
  }

  // ★ 0.303.0：登录核心（门禁检查由调用方完成——首启合并屏 / 常规入口共用同一条链路）
  loginCore(fromSyncEntry: boolean, fromOnboarding: boolean): void {
    this.isProcessing = true;
    if (fromOnboarding) {
      this.onboardingTip = '';
    }
    const context = this.getUIContext().getHostContext() as common.Context;
    loginWithHuaweiID(context).then((tip: string) => {
      this.isProcessing = false;
      // ★ 0.196.9：用户主动取消登录——静默返回（取消是正常行为非错误）
      if (tip === AUTH_CANCELLED_TIP) {
        if (fromOnboarding) {
          this.onboardingTip = '已取消登录，可重试或选择「先本地使用」';
        }
        return;
      }
      if (tip !== '') {
        if (fromOnboarding) {
          this.onboardingTip = tip;
        } else {
          // ★ 0.305.3：常规登录失败提示改 toast（原首页 loginTip 文本位随正常态退役删除）
          try {
            this.getUIContext().getPromptAction().showToast({ message: tip, duration: 2500 });
          } catch (_e) {
            // 静默
          }
        }
        return;
      }
      onLoginAccountHooks(); // ★ 0.305.1：登录后账号钩子（账号切换检测+签到引导；订阅打戳已随退役删除）
      if (fromOnboarding) {
        // ★ 0.303.0：首启登录成功=同意全部协议 + 入口即意图开启云同步 → 外观选择
        markHwAgreed();
        markAgreed();
        enableCloudSyncWithGuide(this.getUIContext());
        this.pathStack.pushPath({ name: 'BBTreeCanvas' }); // ★ 0.305.3：登录成功直进气泡树（首页正常态已退役）
        setTimeout(() => {
          this.maybeShowThemeChoose();
        }, 300);
        return;
      }
      if (fromSyncEntry) {
        enableCloudSyncWithGuide(this.getUIContext());
      } else if (shouldPromptCloudSyncAfterLogin(true)) {
        this.confirmDialog.cloudSyncPromptVisible = true;
      }
    });
  }

  // ★ 0.303.0：首启合并门禁——勾选协议后点「华为账号登录」
  onOnboardingLogin(): void {
    if (this.isProcessing) {
      return;
    }
    markHwAgreed(); // 勾选即同意《华为账号用户认证协议》（登录失败不重复征求）
    this.loginCore(true, true);
  }

  // ★ 0.303.0：首启「暂不登录，先本地使用」——协议已同意，本地三板块照用
  // ★ 0.305.2：未勾选协议不得放行（合规守卫——「暂不登录」≠「不同意协议」）
  // ★ 0.305.4：负反馈=协议勾选行抖动（不再抖按钮+文字提示，用户二次实测拍板）
  onOnboardingLocalOnly(): void {
    if (!this.onboardingChecked) {
      this.shakeOnboarding();
      return;
    }
    markHwAgreed();
    markAgreed();
    this.onboardingTip = '';
    this.pathStack.pushPath({ name: 'BBTreeCanvas' }); // ★ 0.305.3：同意完成直进气泡树（首页正常态已退役）
    setTimeout(() => {
      // ★ 0.305.6：本地模式告知弹窗**前置**（用户四测拍板「暂不登录点击进去立即弹」——
      //   原排在主题选择之后接力，用户在主题弹窗阶段感知=「没弹」）；主题选择改由
      //   告知弹窗「直接进入」收尾后接力。已弹过（每设备一次）直落主题选择。
      if (!this.agreement.localModeNoticeShown) {
        this.maybeShowLocalModeNotice();
      } else {
        this.maybeShowThemeChoose();
      }
    }, 200);
  }

  // ★ 0.305.5：本地模式功能告知弹窗（每设备一次）——合规依据：Account Kit 管理细则仅要求
  //   「支持第三方登录须提供华为账号登录选项」；单次告知+「直接进入」出口不构成强制操作
  maybeShowLocalModeNotice(): void {
    if (this.agreement.localModeNoticeShown) {
      return;
    }
    markLocalModeNoticeShown();
    this.localModeNoticeVisible = true;
  }

  // ★ 0.303.0：不同意=直接退出（官方 FAQ：不得通过多次弹窗强制用户操作）
  onOnboardingExit(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.terminateSelf();
    } catch (_e) {
      // 退出失败静默——用户重进再走门禁
    }
  }

  // ★ 0.164：点击退出账号；★ 0.263.0：wipe=true 一并清空本机数据（借给他人前场景）
  doLogout(wipe: boolean) {
    if (this.isProcessing) {
      return;
    }
    this.isProcessing = true;
    // ★ 0.263.0：先关云同步开关再登出再清数据（顺序铁律——清零必须在同步停止后进行，
    //   否则墓碑上行会把云端数据一并删掉，换设备登录无法恢复）
    disableCloudSyncOnLogout(this.getUIContext());
    const context = this.getUIContext().getHostContext() as common.Context;
    logoutHuaweiID(context).then((tip: string) => {
      this.isProcessing = false;
      if (tip !== '') {
        // ★ 0.305.3：退出失败提示改 toast（原首页 loginTip 文本位随正常态退役删除）
        try {
          this.getUIContext().getPromptAction().showToast({ message: tip, duration: 2500 });
        } catch (_e) {
          // 静默
        }
      }
      if (wipe) {
        // 清空本机数据（词库/知识库/气泡树/统计/SP/签到等）→ 云端不受影响 → 重启到干净状态
        clearAllLocalUserData(context).then(() => {
          try {
            this.getUIContext().getPromptAction().showToast({
              message: '已退出登录，本机数据已清空', duration: 1500
            });
          } catch (_e) {
            // 静默
          }
          // 落盘完成后再自退（重开=未登录空库全新状态；内存工作区随进程一并清干净）
          setTimeout(() => {
            try {
              (context as common.UIAbilityContext).terminateSelf();
            } catch (_e) {
              // 自退失败静默——数据已清，用户手动重开同样干净
            }
          }, 1200);
        });
      }
    });
  }

  // ============================================================
  // ★ 0.293.0：SP 云服务门卫引导弹窗（文案与确认动作按阻塞原因分支）
  // ★ 0.313.0（Phase2）：门卫改为「登录 ∧ 云函数账本通道就绪」——云空间开关不再是 SP 闸门
  //   r=1 未登录：标题「登录华为账号后可用」，确认「登录华为账号」；
  //   r=2 网络不可用：确认「重试连接」；r=3 账本同步/服务升级中：确认「重试」。
  //   确认钮（主行动）恒在左、取消在右（0.310.1 用户拍板）。
  // ============================================================
  syncGateTitle(): string {
    const r = siyiGateBlockReason();
    if (r === 1) {
      return '登录华为账号后可用';
    }
    return r === 2 ? '云服务连接失败' : '司忆点服务准备中';
  }

  syncGateConfirmText(): string {
    const r = siyiGateBlockReason();
    if (r === 1) {
      return '登录华为账号';
    }
    return '重试';
  }

  syncGateCancelText(): string {
    return siyiGateBlockReason() === 1 ? '暂不使用' : '取消';
  }

  syncGateMessage(): string {
    const r = siyiGateBlockReason();
    if (r === 1) {
      return '此功能涉及司忆点（SP），需登录华为账号后使用。点击下方按钮登录华为账号。';
    }
    if (r === 2) {
      return '司忆点账本需要连接云端服务，当前网络不可用。请检查网络后点击「重试」。';
    }
    // r === 3：账本初始化/服务升级中（新账号建账、旧账号迁移尚未完成）
    return '司忆点账本正在与云端同步，请稍后点击「重试」。';
  }

  onSyncGateConfirm(): void {
    this.confirmDialog.syncGatePromptVisible = false;
    const r = siyiGateBlockReason();
    if (r === 1) {
      this.doLogin(true); // 未登录→登录
    } else {
      ensureSpAuth(true); // 网络重试 / 账本重建（成功后再点原功能即可）
    }
  }

  // ★ 0.195.0：常驻边栏导航（大屏）——气泡树=回画布页：栈顶已是则不动 / 深栈 pop 一层 / 根栈 push；
  //   其余项 pushPath（页面在边栏右侧 Navigation 区域平移，边栏恒在——用户定稿）
  sideBarNav(kind: string): void {
    // ★ 0.305.0：未同意协议=首页门禁态唯一可见内容——侧边栏导航逻辑守卫（防绕过同意进入业务页）
    if (this.needsOnboarding) {
      return;
    }
    if (kind === 'wordbank') {
      // ★ 0.222.19：进单词库=首次自动配置默认态（导航收起+文件夹展开）；用户手动改动后 autoConfigured=true 不再自动干预
      if (!this.wbSection.autoConfigured) {
        this.wbSection.navExpanded = false;
        this.wbSection.folderExpanded = true;
        this.wbSection.autoConfigured = true;
      }
      this.pathStack.pushPath({ name: 'WordBankPage' });
    } else if (kind === 'knowledge') {
      // ★ 0.220.1 用户拍板终版：进知识库=首次自动配置默认态（导航收起+文件夹展开）；用户手动改动后 autoConfigured=true 不再自动干预（"用户自己选择+记忆"）
      if (!this.kbSection.autoConfigured) {
        this.kbSection.navExpanded = false;
        this.kbSection.folderExpanded = true;
        this.kbSection.autoConfigured = true;
      }
      this.pathStack.pushPath({ name: 'KnowledgeBankPage' });
    } else if (kind === 'review') {
      this.pathStack.pushPath({ name: 'ReviewPage' }); // ★ 0.196.1：知识复习页（Anki 式单卡）
    } else if (kind === 'statistics') { // ★ 0.196.2：account 分支删除（头像改退出确认，不再发 onNavClick）
      this.pathStack.pushPath({ name: 'StatisticsPage' });
    } else if (kind === 'billing') {
      this.pathStack.pushPath({ name: 'BillingPage' });
    } else if (kind === 'settings') {
      this.gsShared.visible = true; // ★ 0.230.0：共享开态（跨页返回键拦截）
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
      const screenW = d.densityPixels > 0 ? d.width / d.densityPixels : 0;
      this.winWidth = screenW;
      // ★ 0.279.6：PC 恒平板布局（窄窗也保留边栏）；手机恒手机布局；Pad 维持 600vp 断点
      this.windowMode.isTablet = !this.isPhoneDevice && (this.isPcDevice || screenW >= 600);
    } catch (_e) {
      this.windowMode.isTablet = this.isPcDevice; // ★ 0.279.6：PC 取显示信息失败也保留边栏；其余保守按手机处理
    }
    // ★ 0.195.0 bugfix：边栏选中态动态跟踪——didShow 拿目标页名（'navBar'=首页清空高亮；
    //   push/pop/replacePath 全走这里，边栏高亮恒与主界面页面一致）
    this.pathStack.setInterception({
      didShow: (_from: NavDestinationContext | NavBar, to: NavDestinationContext | NavBar, _operation: NavigationOperation, _isAnimated: boolean) => { // ★ 0.305.1：未用参数 _ 前缀
        if (to === 'navBar') {
          this.currentRoute = '';
        } else {
          this.currentRoute = to.pathInfo.name;
        }
      }
    });
    onLoginAccountHooks(); // ★ 0.305.1：老用户补跑账号钩子（升级前已登录的账号不会再触发 doLogin 回调）
    // ★ 0.204.0 bugfix（bug2 根因）：启动即构建桌面卡片快照——原只在进复习页时写快照，
    //   新添加卡片/未进过复习页时快照为空 → 卡片误显「今日复习已完成」。
    //   延迟 800ms 等 PersistenceV2 磁盘水合完成再构建（冷启动首帧 store 可能未就绪）。
    setTimeout(() => {
      try {
        wipeHistoricalTestStats(); // ★ 0.279.1：一次性清理今天之前的历史测试统计（保留当日真实数据；云端旧行同步自愈）
        // ★ 0.279.4：存量已登录 hwAgreed 对齐**已挪 needsHwAgreement() 内**（0.279.3 曾放此处——
        //   启动 800ms 时 agreement-v1 水合未完成，写实例触发 factory 默认值整体落盘覆盖盘上
        //   agreed:true（写侧水合竞态实锤事故，盘值已直修回）。教训：启动回调内禁止写 PersistenceV2）
        const wb = connectWordBank();
        const kb = connectKnowledgeBank();
        const dc = connectDailyReviewCount();
        buildWidgetState(this.getUIContext().getHostContext() as common.Context, 'knowledge',
          wb, kb, dc.wordCount, dc.knowledgeCount);
        // ★ 0.204.3：formId 自愈——卸载重装后 preferences 清空，桌面残留卡片收不到推送（用户实测）；
        //   查询系统已发布卡片回写 form_ids + 补推（幂等：已有记录直接返回）
        ensureWidgetFormIds(this.getUIContext().getHostContext() as common.Context);
        // ★ 0.205.0 三道防线·启动链：①内部双备份 ②空库+有备份→询问恢复（第二道兜底）③超 24h 外部自动备份
        const ctx = this.getUIContext().getHostContext() as common.Context;
        if (wb.words.length > 0 || kb.cards.length > 0) {
          writeInternalBackup(ctx, buildBackupPayload(wb, kb)); // 正常有数据→备份
        } else {
          const p = readInternalBackup(ctx); // 库空但有备份→可能升级异常清空/误删→询问恢复
          // ★ 0.305.0：未同意协议时不弹任何业务弹窗（首页门禁态独占）
          if (!this.needsOnboarding && p !== undefined && (p.words.length > 0 || p.cards.length > 0)) {
            this.pendingRestore = p;
            this.restorePromptVisible = true;
          }
        }
        maybeAutoBackup(ctx, wb, kb);
      } catch (_e) {
        // 静默（下次进复习页会重建）
      }
    }, 800);
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
        // ★ 0.310.1：老装机「你好/1」示例气泡→「用户画像」空气泡（判定极窄，见 ChatModel）
        if (migrateLegacyDemoSeed(loaded)) {
          persist.bubbleTreeJson = serializeBubbleTree(loaded); // 迁移即落盘（幂等：迁移后不再命中）
        }
        AppStorageV2.connect(BubbleTree, 'bubble-tree', () => loaded);
      } else {
        // 首次启动，创建默认气泡树
        // ★ 0.310.1：默认根气泡改「用户画像」气泡——空对话（原「你好/1」示例退役，用户拍板）；
        //   标题走 nodeTitle 手动标题位，进入后由 ChatPage 空态引导用户做自我介绍
        AppStorageV2.connect(BubbleTree, 'bubble-tree', () => {
          const rootId = generateNodeId();
          return new BubbleTree([
            new BubbleNode(rootId, null, [], 200, 200, 0, 0, '', 0, '用户画像')
          ]);
        });
      }
    }
    // PersistenceV2：API 配置持久化，跨重启保存
    PersistenceV2.connect(ApiConfig, 'api-config', () => new ApiConfig());
    // ★ 0.305.0：首启门禁不再需要弹窗判定——首页 @Computed needsOnboarding 首帧即按
    //   preferences 同步真值渲染未同意态（0.304.2 的同步判定块随覆盖层一并删除）。
    // ★ 0.305.3：已同意老用户冷启直达气泡树（首页正常态退役）；延迟一帧等 Navigation
    //   栈附着（aboutToAppear 时 pathStack 尚未 bind，立即 push 会静默丢）
    if (!needsAgreement()) {
      setTimeout(() => {
        this.pathStack.pushPath({ name: 'BBTreeCanvas' });
      }, 0);
    }
  }

  // ============================================================
  // ★ 0.303.0：首启合并门禁（OnboardingGate）+ 非首启两段式门禁（AgreementDialog hw 形态）
  // ============================================================

  // ★ 0.262.0：新用户主题选择弹窗判定——mode 空串=从未落盘（新用户首启待选择；
  //   老用户已静默落盘 dark 不弹；用户选择后落盘、此后永不弹）
  maybeShowThemeChoose(): void {
    if (connectThemeMode().mode === '') {
      this.themeChooseVisible = true;
    }
  }

  // ★ 0.264.0：华为协议登录门禁——同意并登录（落 hwAgreed 再按 pendingAction 续跑登录/云同步）
  onHwAgreementAgree(): void {
    this.agreementBridge.hwPromptVisible = false;
    markHwAgreed();
    const action = this.agreementBridge.pendingAction;
    this.agreementBridge.pendingAction = '';
    if (action === 'sync') {
      this.doLogin(true);
    } else {
      this.doLogin(false);
    }
  }

  // ★ 0.264.0：华为协议登录门禁——不同意（仅取消登录，本地三板块照用，不退出应用）
  onHwAgreementReject(): void {
    this.agreementBridge.hwPromptVisible = false;
    this.agreementBridge.pendingAction = '';
  }

  // ★ 0.305.0：门禁态交互（原 OnboardingGate 组件逻辑迁入首页——单一入口、零重复）
  onboardingViewSections(): string[] {
    return this.onboardingViewing === 0 ? USER_AGREEMENT_SECTIONS : PRIVACY_SECTIONS;
  }

  onboardingViewTitle(): string {
    return this.onboardingViewing === 0 ? AGREEMENT_USER_NAME : AGREEMENT_PRIVACY_NAME;
  }

  // 华为账号用户认证协议：系统浏览器打开华为官方页（不用应用内 WebView）
  openHuaweiAgreement(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ctx.openLink(HUAWEI_ACCOUNT_AGREEMENT_URL).catch(() => {
        // 打开失败静默
      });
    } catch (_e) {
      // 静默
    }
  }

  // 未勾选点登录/暂不登录=协议勾选行抖动负反馈（★0.305.4 唯一抖动锚点——逐帧偏移末尾归零）
  shakeOnboarding(): void {
    const seq: number[] = [8, -8, 6, -6, 3, -3, 0];
    for (let i = 0; i < seq.length; i++) {
      setTimeout(() => {
        this.onboardingShakeX = seq[i];
      }, 40 * i);
    }
  }

  toggleOnboardingChecked(): void {
    if (this.isProcessing) {
      return;
    }
    this.onboardingChecked = !this.onboardingChecked;
  }

  // 门禁态点「华为账号登录」：未勾选=协议勾选行抖动（不发任何请求），勾选=走登录
  requestOnboardingLogin(): void {
    if (this.isProcessing) {
      return;
    }
    if (!this.onboardingChecked) {
      this.shakeOnboarding();
      return;
    }
    this.onOnboardingLogin();
  }

  // ★ 0.305.0：品牌区——门禁态/衬底共用一份（消除原「首页 + 独立门禁层」两套视觉重复）
  @Builder
  brandHeader() {
    Text('DAG AI Chat')
      .fontSize(32)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.theme.textPrimary)
      .fontFamily(FONT_INTER_SEMIBOLD)
    Text('你的AI学习伴侣')
      .fontSize(FONT_SIZE_CARD_TITLE_SM) // ★ 0.305.0：副标题 14→13（与门禁辅助文字同号——用户拍板字号对齐）
      .fontColor(this.theme.textSecondary)
      .margin({ top: 8 })
  }

  // ★ 0.305.0：首页未同意态（首启/协议升版）= 门禁内容直接作为首页本体渲染
  //   （版式见 UI_GUIDELINES 12c：品牌 → 登录按钮 → 暂不登录 → 协议两行 → 不同意退出）
  @Builder
  onboardingPanel() {
    Column() {
      Blank().layoutWeight(2.0) // ★ 0.305.4：1→1.6；★ 0.305.5：1.6→2.0（用户三测：上部再下移一点）
      this.brandHeader()

      // 主按钮（未勾选=品牌描边透底 + 抖动负反馈；已勾选=品牌实底白字）
      Column({ space: 3 }) {
        Text(this.isProcessing ? '登录中…' : '华为账号登录')
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.onboardingChecked ? Color.White : this.theme.textSecondary)
        Text('登录后开启云同步')
          .fontSize(FONT_SIZE_CAPTION)
          .fontColor(this.onboardingChecked ? Color.White : this.theme.textTertiary)
      }
      .width('100%')
      .constraintSize({ maxWidth: 420 })
      .padding({ top: 14, bottom: 14 })
      .borderRadius(RADIUS_CONTROL)
      .backgroundColor(this.onboardingChecked ? this.theme.brandPrimary : this.theme.surfaceSoft)
      .border({ width: 1, color: this.onboardingChecked ? Color.Transparent : this.theme.strokeBrand })
      .alignItems(HorizontalAlign.Center)
      .enabled(!this.isProcessing)
      .onClick(() => {
        this.requestOnboardingLogin();
      })
      .margin({ top: 28 })

      if (this.onboardingTip !== '') {
        Text(this.onboardingTip)
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .lineHeight(20)
          .fontColor(this.theme.danger)
          .textAlign(TextAlign.Center)
          .constraintSize({ maxWidth: 420 })
          .margin({ top: 12 })
      }

      Text('暂不登录，先本地使用')
        .fontSize(FONT_SIZE_CARD_TITLE_SM)
        .fontColor(this.theme.textSecondary)
        .margin({ top: 20 })
        .onClick(() => {
          if (!this.isProcessing) {
            this.onOnboardingLocalOnly();
          }
        })

      Blank().layoutWeight(1.4) // ★ 0.305.4：1；★ 0.305.5：1→1.4（用户三测：下块再下移两倍距离）

      // 协议勾选行（固定两行：用户/隐私协议一行 + 华为认证协议另起；整组 X 轴居中、
      //   勾选框与两行文字块纵向居中；协议名点击不改变勾选态）
      // ★ 0.305.4：未勾选点「华为账号登录/暂不登录」的抖动负反馈统一锚定在本行（用户二次实测
      //   拍板——抖"要去勾的地方"比抖按钮+文字提示更直观；onboardingHint 提示文字随之退役）
      Row({ space: 8 }) {
        if (this.onboardingChecked) {
          Image($r('app.media.checkbox_on'))
            .width(18)
            .height(18)
            .onClick(() => {
              this.toggleOnboardingChecked();
            })
        } else {
          Image($r('app.media.checkbox_off'))
            .width(18)
            .height(18)
            .onClick(() => {
              this.toggleOnboardingChecked();
            })
        }
        Column({ space: 2 }) {
          Text() {
            Span(AGREEMENT_CHECK_PREFIX)
              .fontColor(this.theme.textSecondary)
              .onClick(() => {
                this.toggleOnboardingChecked();
              })
            Span('《' + AGREEMENT_USER_NAME + '》')
              .fontColor(this.theme.brandPrimary)
              .onClick(() => {
                this.onboardingViewing = 0;
              })
            Span('《' + AGREEMENT_PRIVACY_NAME + '》')
              .fontColor(this.theme.brandPrimary)
              .onClick(() => {
                this.onboardingViewing = 1;
              })
          }
          .fontSize(12) // ★ 0.305.4：下块缩字号 13→12+行高 20→18（用户拍板下块整体缩小一圈下移）
          .lineHeight(18)
          Text() {
            Span('《' + AGREEMENT_HUAWEI_NAME + '》')
              .fontColor(this.theme.brandPrimary)
              .onClick(() => {
                this.openHuaweiAgreement();
              })
          }
          .fontSize(12)
          .lineHeight(18)
        }
        .alignItems(HorizontalAlign.Start)
      }
      .constraintSize({ maxWidth: 460 })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .translate({ x: this.onboardingShakeX })

      Text('不同意，退出')
        .fontSize(12)
        .fontColor(this.theme.textTertiary)
        .margin({ top: 20 })
        .onClick(() => {
          if (!this.isProcessing) {
            this.onOnboardingExit();
          }
        })

      // 门禁态也显示版本号（装机验收/反馈报障定位用）
      Text(APP_VERSION)
        .fontSize(11)
        .fontColor(this.theme.textTertiary)
        .margin({ top: 12 })

      // ★ 0.305.4：底部弹性缓冲——下块（协议行/不同意退出/版本号）随内容整体下沉且不贴底
      // ★ 0.305.5：0.4→0.3（微收防贴底——下沉量让给中部弹性）
      Blank().layoutWeight(0.3)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 16, bottom: 24 })
    .alignItems(HorizontalAlign.Center)
  }

  // ★ 0.305.0：协议正文整页（门禁态内点协议名进入；标题行「返回」回门禁主态）
  @Builder
  agreementTextPanel() {
    Column() {
      Row() {
        Text(this.onboardingViewTitle())
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontWeight(600)
          .fontFamily(FONT_INTER_SEMIBOLD)
          .fontColor(this.theme.textPrimary)
          .layoutWeight(1)
        Text('返回')
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontColor(this.theme.brandPrimary)
          .onClick(() => {
            this.onboardingViewing = -1;
          })
      }
      .width('100%')
      .margin({ bottom: 12 })

      Scroll() {
        Column() {
          ForEach(this.onboardingViewSections(), (sec: string) => {
            Text(sec)
              .fontSize(FONT_SIZE_BODY)
              .lineHeight(21)
              .fontColor(isPrivacySensitiveSection(sec) ? this.theme.textPrimary : this.theme.textSecondary)
              .fontWeight(isPrivacySensitiveSection(sec) ? FontWeight.Medium : FontWeight.Normal)
              .width('100%')
              .margin({ bottom: 10 })
          }, (_sec: string, idx: number) => `${idx}`)
        }
        .width('100%')
        // ★ 0.305.5：正文不满屏时段落间距舒展铺满全屏（用户三测「下面空一段拉到全屏」）；
        //   超屏时 minHeight 失效、间距回落 margin 自然滚动——两态兼容
        .constraintSize({ minHeight: '100%' })
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 16, bottom: 20 })
    .alignItems(HorizontalAlign.Center)
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
    } else if (name === 'SketchPage') { // ★ 0.297.0：数学证明画板页（输入区 + 号入口）
      SketchPage({ pathStack: this.pathStack })
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
      // ★ 0.278.10：平板边栏安全区垫层——边栏本体 bgNav，上下安全区原本露根 Stack 的 bgApp，
      //   造成边栏上下颜色与本体不一致（用户 Pad 实测指认）；垫层只占边栏宽度并用 expandSafeArea
      //   把 bgNav 铺进状态栏/手势条区，折叠时宽 0 自动消失；置于 Row 之下、hitTest 穿透不挡事件
      if (this.isTablet && !this.needsOnboarding) {
        Column()
          .width(this.indexSidebarState.collapsed ? 0 : this.sidebarWidth) // ★ 0.279.6：PC 窄窗自适应收窄
          .height('100%')
          .backgroundColor(this.theme.bgNav)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .position({ x: 0, y: 0 })
          .hitTestBehavior(HitTestMode.None)
      }
      // ★ 0.195.0：大屏边栏常驻；★ 0.219.0 用户拍板改版：右缘竖把手点击→边栏滑向左侧隐藏，
      //   把手浮在左缘变右箭头，再点恢复（滑入滑出带动画）；收起状态 AppStorageV2 共享——
      //   跳到对话页等任何页面边栏保持隐藏，跨页面一致；手机不渲染边栏（画布抽屉承担导航）
      Row() {
        if (this.isTablet && !this.needsOnboarding) {
          Column() {
            AppSideBar({
              currentRoute: this.currentRoute, // ★ 0.195.0 bugfix：选中态动态跟踪（高亮恒与主界面一致）
              sidebarWidth: this.sidebarWidth, // ★ 0.279.6：PC 窄窗自适应收窄（其余宿主不传=默认 208）

              settingsOpen: this.gsShared.visible, // ★ 0.230.0
              onNavClick: (kind: string) => {
                this.sideBarNav(kind);
              },
              onFolderClick: (_folderId: string) => { // ★ 0.306.0：参数未消费 _ 前缀（视图切换走共享 store，见内注释）
                // ★ 0.220.0：文件夹树点击——视图切换已由共享 store（folderNav.folderId）生效，
                //   此处只需确保路由在当前库页（树仅在库页显示，正常恒在；兜底 pushPath）
                // ★ 0.222.19：按当前路由区分知识库/单词库
                const target = this.currentRoute === 'WordBankPage' ? 'WordBankPage' : 'KnowledgeBankPage';
                const names = this.pathStack.getAllPathName();
                if (names.indexOf(target) < 0) {
                  this.pathStack.pushPath({ name: target });
                }
              }
            })
          }
          .width(this.indexSidebarState.collapsed ? 0 : this.sidebarWidth) // ★ 0.279.6：PC 窄窗自适应收窄
          .opacity(this.indexSidebarState.collapsed ? 0 : 1)
          .clip(true)
          .alignItems(HorizontalAlign.Start)
        }
    Navigation(this.pathStack) {
      // 首页内容（★ 0.174.1：按 UI_GUIDELINES 重做——this.theme.bgApp 暗紫底 + expandSafeArea 满屏 +
      // Logo 区/主按钮/账号区对齐组件规格；删「图结构对话 · 多分支推理」（用户拍板））
      Column() {
        if (this.needsOnboarding && this.onboardingViewing >= 0) {
          this.agreementTextPanel() // ★ 0.305.0：协议正文整页（门禁态内查看，非弹窗）
        } else if (this.needsOnboarding) {
          this.onboardingPanel() // ★ 0.305.0：首页未同意态（门禁内容=首页本体，非覆盖层）
        } else {
        // ★ 0.305.3：首页正常态退役（用户拍板「同意协议后直进气泡树」）——原「进入气泡树+
        //   华为登录区+版本号」整段删除（登录入口走设置/边栏，版本号门禁态与设置-关于均有）。
        //   本衬底仅两处短暂可见：①冷启已同意用户 pushPath 画布前的首帧衔接；
        //   ②用户从画布按返回 pop 落回（衬底上再按一次返回=退出 app，无空白闪屏）
        // ★ 0.311.5（用户实测拍板）：pop 落回首页=死路（只有品牌字，无任何入口回气泡树，
        //   只能杀 app 重开）——补「进入 DAG AI Chat」主按钮，点击直推画布
        Blank().layoutWeight(1)
        this.brandHeader()
        Text('进入 DAG AI Chat')
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .width('100%')
          .constraintSize({ maxWidth: 260 }) // ★ 0.311.6：用户实测全屏太宽——收窄居中与标题/副标题视觉协调
          .padding({ top: 14, bottom: 14 })
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(this.theme.brandPrimary)
          .margin({ top: 28 })
          .onClick(() => {
            this.pathStack.pushPath({ name: 'BBTreeCanvas' });
          })
        Blank().layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      // ★ 0.179.0：删 justifyContent(Center)——垂直布局改由 Blank 弹性占位（2.5:2.5:1，★ 0.181.1 原 2:3:1）接管
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.theme.bgApp) // ★ 0.174.1：应用底色暗紫（UI_GUIDELINES Token，替换旧深灰 #1A1A1A）
      .expandSafeArea([SafeAreaType.SYSTEM]) // ★ 0.174.1：背景延伸进状态栏/导航条安全区——首页满屏高度（用户报「高度是短的」；省略 edges 参数=默认全部边，第二参数类型是 SafeAreaEdge 非 SafeAreaType）
    }
    .navDestination(this.pageMap)
    // ★ 0.166.2：Auto 模式下平板宽屏自动切分栏——首页一直占左栏、画布只占右栏（用户实测
    // 「首页一直出现在屏幕左边」）；改 Stack 强制单栏，push 后目标页全屏覆盖，平板与手机一致
    .mode(NavigationMode.Stack)
    .layoutWeight(1) // ★ 0.195.0：边栏常驻布局——Navigation 占边栏右侧剩余区域（页面在此平移不遮边栏）
    // ★ 0.278.9：Navigation 容器补 bgApp 底——页面 push/pop 平移转场时容器默认背景露黑，
    //   用户实测「首页滑到气泡树左侧一大块黑」即此；与页面 bgApp 同色后转场无黑块
    .backgroundColor(this.theme.bgApp)
      }
      // ★ 0.219.1 用户拍板（0.219.0 大块头"太难看"）：把手重设计=**极细竖胶囊**——无外框无阴影无三角字符
      //   （细条本身即表意），底色 this.theme.strokeCard 与边栏描边同色系克制；交互=点击 220ms 滑入滑出
      // ★ 0.222.14 用户拍板再精化：更细更长（宽 7/高 112→224）
      // ★ 0.278.14 用户三诉求：①垂直居中（y:'50%' 是左上角对齐中线，高度越大偏下越明显——translate 半高回退）
      //   ②长度翻倍 112→224 ③触发热区扩大（7vp 太难点中）——透明热区容器 27×240 包住 7×224 细胶囊，
      //   视觉不变、可点范围横向翻近 4 倍；onClick 挂热区容器（子组件无点击事件，冒泡到容器）
      if (this.isTablet && !this.needsOnboarding) {
        Row() {
          Column()
            .width(7)
            .height(224)
            .borderRadius(4)
            .backgroundColor(this.theme.strokeCard)
        }
        .width(27)
        .height(240)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .position({ x: this.indexSidebarState.collapsed ? -8 : this.sidebarWidth - 12, y: '50%' }) // ★ 0.279.6：把手跟随边栏宽度
        .translate({ y: -120 })
        .onClick(() => {
          this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
            this.indexSidebarState.collapsed = !this.indexSidebarState.collapsed;
          });
        })
      }
      // ★ 0.195.0：全局设置弹窗（常驻边栏「设置」入口；实例与画布/对话页共用 PersistenceV2 数据）
      if (this.gsShared.visible) { // ★ 0.230.0
        GlobalSettingsDialog({
          onClose: () => {
            this.gsShared.visible = false;
          }
        })
      }
    // ★ 0.196.9：退出华为账号确认（边栏头像触发——原系统 AlertDialog 灰底，用户实测反馈
    //   与暗紫风格不符；确认走 doLogout：退出 + 云同步强制关一条龙）
    AppConfirmDialog({
      visible: this.restorePromptVisible, // ★ 0.205.0：空库检测到内部备份→询问恢复
      title: '发现应用内部备份',
      message: '当前单词库与知识库为空，但检测到之前的内部备份。是否恢复？',
      confirmText: '恢复数据',
      cancelText: '暂不恢复',
      onConfirm: () => {
        this.restorePromptVisible = false;
        const p = this.pendingRestore;
        this.pendingRestore = undefined;
        if (p !== undefined) {
          const wb = connectWordBank();
          const kb = connectKnowledgeBank();
          const n = restoreFromPayload(wb, kb, p);
          writeInternalBackup(this.getUIContext().getHostContext() as common.Context, buildBackupPayload(wb, kb));
          this.getUIContext().getPromptAction().showToast({ message: `已恢复 ${n} 条数据`, duration: 2000 });
        }
      },
      onCancel: () => {
        this.restorePromptVisible = false;
        this.pendingRestore = undefined; // 用户明确选择空库——保留备份不删（下次仍可从设置恢复）
      }
    })
    // ★ 0.196.9：退出华为账号确认（原注释位——上移为恢复弹窗让位）
    // ★ 0.263.0：加「同时清空本机数据」勾选框（借给他人前场景——云端数据不受影响，重新登录可恢复）
    AppConfirmDialog({
      visible: this.confirmDialog.logoutConfirmVisible,
      title: '退出华为账号',
      message: '退出后将停止云同步。云空间数据不受影响，重新登录可恢复。',
      checkboxLabel: '同时清空本机全部数据（借给他人前勾选）',
      checkedConfirmText: '退出并清空',
      confirmText: '退出',
      cancelText: '取消',
      onConfirm: () => {
        this.confirmDialog.logoutConfirmVisible = false;
        this.doLogout(false);
      },
      onConfirmChecked: (checked: boolean) => {
        this.confirmDialog.logoutConfirmVisible = false;
        this.doLogout(checked);
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
        enableCloudSyncWithGuide(this.getUIContext());
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
    // ★ 0.248.2：未登录发消息问 AI → 登录引导弹窗（上架合规：AI 生成内容仅限实名华为账号用户；
    //   中国区华为账号注册即强制实名，登录守卫=实名等效闭环。ChatPage 发送/重生成触发；
    //   fromSyncEntry=false 普通路径登录，协议门禁由 doLogin 内 AgreementDialog 链继承）
    // ★ 0.311.0：文案改「SP 消耗类功能」口径（用户拍板——不在对话页时弹「AI 对话」显得突兀）
    AppConfirmDialog({
      visible: this.confirmDialog.aiLoginPromptVisible,
      title: '需要登录',
      message: 'AI 对话等消耗司忆点（SP）的功能，需先登录华为账号。',
      confirmText: '登录华为账号',
      cancelText: '取消',
      confirmOnLeft: true,
      onConfirm: () => {
        this.confirmDialog.aiLoginPromptVisible = false;
        this.doLogin(false);
      },
      onCancel: () => {
        this.confirmDialog.aiLoginPromptVisible = false;
      }
    })
    // ★ 0.248.7：SP 余额为 0 发消息 → 充能引导（实扣链路上线；确认跳账单页充能 SP）
    AppConfirmDialog({
      visible: this.confirmDialog.spRechargePromptVisible,
      title: '司忆点已用完',
      message: '继续使用 AI 对话需要司忆点（SP），前往账单页充能后即可继续。',
      confirmText: '去充能',
      cancelText: '取消',
      confirmOnLeft: true,
      onConfirm: () => {
        this.confirmDialog.spRechargePromptVisible = false;
        this.pathStack.pushPath({ name: 'BillingPage' });
      },
      onCancel: () => {
        this.confirmDialog.spRechargePromptVisible = false;
      }
    })
    // ★ 0.313.0：SP 云服务门卫引导（SiyiGate——AI 发送/重生成/划词/圈注/签到/充值在账本通道
    //   未就绪时触发；文案与确认动作按 siyiGateBlockReason 三分支：未登录/网络/账本同步中）
    // ★ 0.306.0：标题/按钮文字/位次随阻塞原因动态化
    // ★ 0.310.1：确认钮（主行动）恒左位——用户拍板「主行动放左边」，与首启登录门禁统一手势习惯
    AppConfirmDialog({
      visible: this.confirmDialog.syncGatePromptVisible,
      title: this.syncGateTitle(),
      message: this.syncGateMessage(),
      confirmText: this.syncGateConfirmText(),
      cancelText: this.syncGateCancelText(),
      confirmOnLeft: true,
      onConfirm: () => {
        this.onSyncGateConfirm();
      },
      onCancel: () => {
        this.confirmDialog.syncGatePromptVisible = false;
      }
    })
    // ★ 0.293.0：新用户礼包仪式感弹窗（云首拉完成+云端确认无发放记录才发放——发放即弹窗
    //   明示赠送，绝不后台默默到账；用户拍板「您是新用户，免费赠送您 200 万 SP」）
    // ★ 0.306.0：单按钮化（cancelText 空串=单按钮模式——SP 已入账，关闭/收下结果相同，
    //   关闭出口纯属误导；点遮罩也不关，唯一出口「开心收下」——用户四测拍板）
    AppConfirmDialog({
      visible: this.confirmDialog.welcomeBonusVisible,
      title: '🎁 新用户礼包',
      message: `您是新用户，免费赠送您 ${(this.confirmDialog.welcomeBonusAmount / 10000).toLocaleString()} 万 SP，已入账。祝学习愉快！`,
      confirmText: '开心收下',
      cancelText: '',
      onConfirm: () => {
        this.confirmDialog.welcomeBonusVisible = false;
        // ★ 0.311.0：礼包关闭后接力首日签到（gate 就绪时礼包优先，签到让位防双层弹窗叠加）
        maybeShowSignInAfterGateReady();
      }
    })
    // ★ 0.305.0：首启门禁=首页未同意态（OnboardingGate 独立覆盖层已删除——技术债清理：
    //   原「首页 + 门禁层」两套视觉重复，现首页 @Computed needsOnboarding 双态渲染）
    // ★ 0.264.0：华为协议登录门禁弹窗（hw 形态；同意=markHwAgreed+续跑登录，不同意=仅取消登录）
    // ★ 0.279.2：visible 同接 @Computed 自动校正
    AgreementDialog({
      visible: this.showHwAgreementPrompt,
      mode: 'hw',
      onAgree: () => {
        this.onHwAgreementAgree();
      },
      onReject: () => {
        this.onHwAgreementReject();
      }
    })
    // ★ 0.262.0：新用户主题选择弹窗（★ 0.303.0：内置体验改进计划开关，默认关；选择即确认即落盘）
    ThemeChooseDialog({
      visible: this.themeChooseVisible,
      onChoose: (_mode: ThemeMode, improve: boolean) => {
        this.themeChooseVisible = false;
        markImprovePromptShown();
        if (improve) {
          setTrackingEnabled(this.getUIContext().getHostContext() as common.Context, true);
          trackFirstAuto();
        }
      }
    })
    // ★ 0.305.5：本地模式功能告知弹窗（用户三测拍板——「暂不登录」进入后一次性告知可用范围）
    // ★ 0.305.6：前置到暂不登录进入即刻弹（用户四测拍板）；「直接进入」收尾后接力主题选择
    AppConfirmDialog({
      visible: this.localModeNoticeVisible,
      title: '当前为本地模式',
      message: '您未登录华为账号、未开启云同步，现可使用以下功能：\n\n· 单词库建立\n· 知识卡片手动录入\n· 卡片复习（含复习记录）\n\nAI 对话、云同步等功能，登录华为账号后即可使用。',
      confirmText: '登录华为账号',
      cancelText: '直接进入',
      confirmOnLeft: true, // ★ 0.310.2：主行动（登录华为账号）放左，直接进入放右（用户拍板——内心希望用户更多登录）
      onConfirm: () => {
        this.localModeNoticeVisible = false;
        this.doLogin(false); // 走常规登录链（hwAgreed 已同意，成功后询问开启云同步）
      },
      onCancel: () => {
        this.localModeNoticeVisible = false;
        this.maybeShowThemeChoose(); // ★ 0.305.6：告知收尾接力主题选择（原暂不登录直弹让位告知）
      }
    })
    // ★ 0.256.0：签到弹窗（边栏签到入口/首登引导判定触发——SignInDialogBridge 驱动）
    SignInDialog()
    // ★ 0.256.0：称号升级弹窗（学习天数落盘/云下行吸收触发——LevelUpBridge 驱动）
    LevelUpDialog()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.bgApp) // ★ 0.174.1：全局兜底底色（各页背景未铺到的安全区露暗紫不露黑）
    .expandSafeArea([SafeAreaType.SYSTEM]) // ★ 0.174.1：背景延伸进状态栏/导航条安全区——满屏
    // ★ 0.287.0：全局撤销/重做键（P2 撤销栈）——Index 根挂载覆盖全部子页；keyboardShortcut
    //   「窗口获焦即响应不依赖组件焦点」（0.285.2 先例）；toast 反馈对应操作 label；
    //   空栈静默（不弹「无可撤销」防打扰）。⚠️ Ctrl+Z 若被系统文本框架保留不响应，真机
    //   验证后改绑 Ctrl+Alt+Z（备选已记迭代文档）
    .keyboardShortcut('z', [ModifierKey.CTRL], (): void => {
      const label = this.undoStack.undo();
      if (label.length > 0) {
        this.getUIContext().getPromptAction().showToast({ message: `已撤销：${label}`, duration: 1500 });
      }
    })
    .keyboardShortcut('z', [ModifierKey.CTRL, ModifierKey.SHIFT], (): void => {
      const label = this.undoStack.redo();
      if (label.length > 0) {
        this.getUIContext().getPromptAction().showToast({ message: `已重做：${label}`, duration: 1500 });
      }
    })
    // ★ 0.196.4：窗口实宽写入共享模式——根 Stack 满窗，onAreaChange 在分屏/悬浮窗 resize 时
    // 实时纠正（首帧用 aboutToAppear 屏宽猜测，此处一帧内校正；≥600vp=平板布局）
    .onAreaChange((_oldVal: Area, newVal: Area) => { // ★ 0.305.1：未用参数 _ 前缀
      const w = newVal.width as number;
      // ★ 0.279.6：窗口实宽记录 + PC 恒平板布局（窄窗保留边栏）；手机恒手机布局；Pad 维持 600vp 断点
      this.winWidth = w;
      this.windowMode.isTablet = this.isPhoneDevice ? false : (this.isPcDevice ? true : w >= 600);
    })
  }
}
