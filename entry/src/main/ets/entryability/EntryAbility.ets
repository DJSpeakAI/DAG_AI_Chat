// ============================================================
// EntryAbility.ets — 应用入口 Ability
// ============================================================
// 本文件是应用的 UI Ability（生命周期入口），负责：
//   - 加载主页面（pages/Index）
//   - 全局主题初始化与系统深浅色跟随（★ 0.262.0 三态主题：system/dark/light）
// ★ 0.262.0：主题改三态模型（AppTheme.ets 唯一色值真相源）——老用户静默深色、
//   新用户协议同意后弹窗选择、设置「外观」卡随时可改；系统深浅变化经
//   onConfigurationUpdate 无缝跟随（module.json5 已配 configChanges 不重建）。
// ============================================================

import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { rpc } from '@kit.IPCKit'; // ★ 0.204.1：卡片 call 热路径——UIAbility Callee 机制（真机日志实证：进程存活时 call 走 Callee onRemoteMessageRequest 而非 onNewWant）
import { AppStorageV2, PersistenceV2, window } from '@kit.ArkUI'; // ★ 0.167：Inter 三字重注册（UIContext.Font，见 loadContent 回调）；★ 0.279.5：PersistenceV2.notifyOnError 过渡期排查
import { hilog } from '@kit.PerformanceAnalysisKit'; // ★ 0.279.5：持久化异常日志
import { util } from '@kit.ArkTS'; // 0.206.0：initAgc 读 rawfile json 解码
import { loadBuiltinApiConfig, setupCloudDownlink, initRowBridgeProviders, flushCloudRowsNow } from '../common/ChatModel'; // ★ 0.161.3：启动时从 rawfile/config.json 加载内置 API Key；★ 0.165.2：注册云端下行处理器
import { initCloudDb, forceCloudSyncNow } from '../utils/CloudSyncUtil'; // ★ 0.165.1：启动时初始化云同步 RDB；★ 0.223.0：回前台强制端云同步；★ 0.228.0 行模式传输层；★ 0.230.1：wipeCloudRows 临时钩子已删（止血由 initCloudDb 幂等清洗接管）
import { handleWidgetRate, handleWidgetSwitch, handleWidgetContinue, handleWidgetSpeak } from '../utils/WidgetHostBridge'; // 0.204.1 widget call; 0.204.2 continue; ★ 0.255.0 speak
import { handleWidgetFlip } from '../utils/WidgetReviewUtil'; // ★ 0.224.0：卡面翻面（纯显示态——卡片安全工具层处理）
import { buildBackupPayload, writeInternalBackup } from '../utils/BackupUtil'; // 0.205.0 三道防线：退后台自动内部备份
import { connectWordBank } from '../utils/WordStoreUtil';
import { connectKnowledgeBank } from '../utils/KnowledgeStoreUtil';
import { initialize } from '@hw-agconnect/hmcore'; // 0.206.0 埋点：AGC 核心（云函数通道前置）
import { flushTrackQueue, initTrackContext } from '../utils/TrackUtil'; // 0.206.0 埋点：退后台上报；★ 0.260.0：模块级 context 注入（ChatModel 发放/消耗收口埋点用）
import { pullRefundMarks } from '../utils/IapUtil'; // ★ 0.291.0：退款标记云端拉取（启动/回前台静默核销）
import { initAiStreamGuard, setAiStreamBackground } from '../utils/AiStreamGuard'; // ★ 0.251.0：AI 流式后台保活守卫（上下文注入+前后台标志）
import { flushHeadsOnBackground } from '../common/ProfileModel'; // ★ 0.265.0 记忆引擎：退后台短时任务续跑摘要头 flush
import { AppTheme, ThemeMode, connectAppTheme, connectThemeMode, setChromeSyncHook, toThemeMode } from '../common/AppTheme'; // ★ 0.262.0：三态主题初始化与系统联动
import { initAgreementPrefs } from '../utils/Agreement'; // ★ 0.279.5：协议同意态 preferences 同步初始化（onCreate 最早同步点——此后任意时刻读到的即磁盘真值）
import { needsAgreement } from '../utils/Agreement'; // ★ 0.262.0：新/老用户判定哨兵（协议同意状态）
// 0.204.1 Callee callback must return Parcelable (d.ts enforced) - empty impl
class EmptyParcelable implements rpc.Parcelable {
  marshalling(_dataOut: rpc.MessageSequence): boolean {
    return true;
  }

  unmarshalling(_dataIn: rpc.MessageSequence): boolean {
    return true;
  }
}

// ★ 0.153：全局前后台状态（UI 运行时状态，非持久化）——NavDestination 组件没有
// onPageHide 生命周期，ChatPage 借此标志 + @Monitor 感知切后台，中断进行中的 AI 提炼
@ObservedV2
export class AppLifecycleStore {
  @Trace isBackground: boolean = false;
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    initAgreementPrefs(this.context); // ★ 0.279.5：preferences 同步初始化（getPreferencesSync 返回即完成载入——协议门禁自此零水合竞态）
    // ★ 0.279.5：过渡期持久化异常排查（华为官方建议）——知识库卡 base64 图或触发 API<23 单 key
    //   8KB 配额静默失败（quota）或序列化失败（serialization），有日志才能定位「写不进去」类表象
    try {
      PersistenceV2.notifyOnError((key: string, reason: string, msg: string): void => {
        hilog.error(0x0000, 'DagChat', 'persistence error key=%{public}s reason=%{public}s msg=%{public}s', key, reason, msg);
      });
    } catch (_e) {
      // 注册失败静默
    }
    this.handleWidgetCallWant(want); // ★ 0.204.1：桌面卡片 call（冷启动路径——method/params 在 want.parameters）
    this.registerWidgetCallee(); // ★ 0.204.1：桌面卡片 call（热路径——进程存活/解冻后走 Callee，onCreate 时注册一次）
    this.initAgc(); // ★ 0.206.0：AGC 初始化（埋点云函数通道——rawfile/agconnect-services.json）
    initTrackContext(this.context); // ★ 0.260.0：埋点模块级 context 注入（trackAuto/trackUidAuto/trackFirstAuto）
    initAiStreamGuard(this.context); // ★ 0.251.0：AI 后台保活守卫初始化（长时任务/通知需 UIAbilityContext）
    // ★ 0.291.0：启动即拉云端退款标记（无包账本=零请求；AGC 未初始化完成/失败均静默，
    //   onForeground 是主拉取点——冷启动极早期这次碰运气，成则赚到）
    pullRefundMarks();
    // ★ 0.230.1：0.228.4 临时清洗钩子 wipeCloudRows 已删除（伪墓碑止血改由 initCloudDb 内
    //   一次性幂等清洗接管——正本 server 同步；此入口曾是全量 del 行写入口，数据毁灭地雷拆除）
  }

  // ★ 0.206.0：初始化 AGC 核心（异步不阻塞启动；失败静默——埋点通道降级为仅 hiAppEvent 本地）
  private initAgc(): void {
    try {
      this.context.resourceManager.getRawFileContent('agconnect-services.json').then((buf: Uint8Array) => {
        const decoder = util.TextDecoder.create('utf-8');
        const jsonStr = decoder.decodeWithStream(buf);
        initialize(this.context, JSON.parse(jsonStr));
      }).catch(() => {
        // 配置缺失静默
      });
    } catch (_e) {
      // 静默
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleWidgetCallWant(want); // ★ 0.204.1：桌面卡片 call（主应用存活路径——热调用即时处理）
  }

  // ★ 0.204.1：卡片 call 热路径——UIAbility Callee 注册（真机日志：进程存活时系统的
  //   ByCall 走 Callee.onRemoteMessageRequest(method)，未注册则 "get func is undefined" 丢弃）。
  //   卡片冻结进程场景系统会先 Thaw 再投递（日志实证），故 Callee 覆盖全部存活场景。
  private registerWidgetCallee(): void {
    try {
      this.callee.on('widgetRate', (data: rpc.MessageSequence): rpc.Parcelable => {
        const params = data.readString();
        try {
          const m = JSON.parse(params) as Record<string, string>;
          handleWidgetRate(this.context, m['rating'] ?? 'good');
        } catch (_e) {
          // 参数异常静默
        }
        return new EmptyParcelable();
      });
      this.callee.on('widgetSwitch', (data: rpc.MessageSequence): rpc.Parcelable => {
        const params = data.readString();
        try {
          const m = JSON.parse(params) as Record<string, string>;
          handleWidgetSwitch(this.context, m['mode'] ?? 'knowledge');
        } catch (_e) {
          // 参数异常静默
        }
        return new EmptyParcelable();
      });
      // 0.204.2：卡片完成态「继续复习」——拉未来队列继续背
      this.callee.on('widgetContinue', (_data: rpc.MessageSequence): rpc.Parcelable => {
        handleWidgetContinue(this.context);
        return new EmptyParcelable();
      });
      // ★ 0.224.0：双面模式卡身翻面（纯显示态零数据变更——切 flipped 推回卡片）
      this.callee.on('widgetFlip', (_data: rpc.MessageSequence): rpc.Parcelable => {
        handleWidgetFlip(this.context);
        return new EmptyParcelable();
      });
      // ★ 0.255.0：卡片音标点击发音（主进程发音单例复用——不 updateForm 不占刷新窗）
      this.callee.on('widgetSpeak', (data: rpc.MessageSequence): rpc.Parcelable => {
        const params = data.readString();
        try {
          const m = JSON.parse(params) as Record<string, string>;
          handleWidgetSpeak(m['word'] ?? '');
        } catch (_e) {
          // 参数异常静默
        }
        return new EmptyParcelable();
      });
    } catch (_e) {
      // 注册失败静默（不影响应用启动）
    }
  }

  // 0.204.1 parse widget call want (method/params in want.parameters),
  //   分发到 WidgetHostBridge（真数据评分+推卡片）。非卡片调用（正常启动）parameters 无 method 静默。
  private handleWidgetCallWant(want: Want): void {
    try {
      const p = want.parameters;
      if (p === undefined || p === null) {
        return;
      }
      const method = (p['method'] ?? '') as string;
      if (method !== 'widgetRate' && method !== 'widgetSwitch' && method !== 'widgetContinue' &&
        method !== 'widgetFlip' && method !== 'widgetSpeak') {
        return;
      }
      const params = p['params'];
      const m = (typeof params === 'string' ? JSON.parse(params) : params) as Record<string, string>;
      if (method === 'widgetRate') {
        handleWidgetRate(this.context, m['rating'] ?? 'good');
      } else if (method === 'widgetContinue') {
        handleWidgetContinue(this.context);
      } else if (method === 'widgetFlip') {
        handleWidgetFlip(this.context); // ★ 0.224.0：冷启动翻面（评分同款双路径）
      } else if (method === 'widgetSpeak') {
        handleWidgetSpeak(m['word'] ?? ''); // ★ 0.255.0：冷启动发音（call 同款双路径）
      } else {
        handleWidgetSwitch(this.context, m['mode'] ?? 'knowledge');
      }
    } catch (_e) {
      // 解析失败静默（不影响正常启动）
    }
  }

  onDestroy(): void {
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // ★ 0.281.4：键盘避让不再在 EntryAbility 设全局 RESIZE（0.281.2 真机实测 NavDestination
    //   页面仍被软键盘遮挡、输入卡下半截露不出来）——改由 ChatPage 的 onShown/onHidden 自控：
    //   进对话页设 KeyboardAvoidMode.NONE + 监听 keyboardHeightChange 手动给根容器让位，
    //   离开恢复默认 OFFSET（其他页面行为不变）

    // ★ 0.165.1：初始化云同步 RDB（建库 dag_chat_cloud.db + 建表 cloud_data + 设分布式表 autoSync）——
    // 异步执行不阻塞启动；此后各持久化点的 upsertCloudData 内部等待 init 完成后写入；
    // 云侧 AGC 未配置时本地写入正常、上云失败仅日志（静默降级，不影响本地功能）
    try {
      initCloudDb(this.context);
    } catch (err) {
      // 初始化失败静默——云同步整体降级，本地 PersistenceV2 路径不受影响
    }

    // ★ 0.165.2：注册云端下行处理器（dataChange 事件 → 写回池 → 重建工作区）——
    // 同步注册（非异步），保证早于 initCloudDb 异步链里的订阅挂载（JS 单线程：
    // 本行先执行完，微任务队列才轮到 initPromise 内的 activateCloudSync）
    try {
      setupCloudDownlink();
    } catch (err) {
      // 注册失败静默——仅丢失下行刷新，本地功能与上云不受影响
    }

    // ★ 0.223.0：词/卡池桥提供者注入（防循环依赖——StoreUtil import Bridge 挂变更钩子，
    //   Bridge 不能反向 import StoreUtil 取 connect 函数，由本入口注入）
    try {
      initRowBridgeProviders(connectWordBank, connectKnowledgeBank);
    } catch (err) {
      // 注入失败静默（词/卡池上行降级，气泡树池不受影响）
    }

    // Main window is created, set main page for this ability
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        return;
      }
      // ★ 0.240.2 总根因修复（官方 FAQ-1084 场景一铁证）：PersistenceV2.connect 必须在 loadContent
      //   之后调用——此前 loadBuiltinApiConfig 放 loadContent 之前（0.161.3 设计「早于组件 connect」），
      //   导致 api-config 系 key 冷启恒 factory 值、盘值被无视（0.240.1 全天 B1/B2/B3 怪象的真身；
      //   model-alias-v1 可靠正因只在组件内 connect=loadContent 后）。挪到回调内=页面已加载，
      //   组件字段 connect 已发生（runtimeApiCfg 单例已建、v5 晚 connect 水合正常），此处填内置 Key
      //   空位仍早于用户任何交互（aboutToAppear 回显/发消息读值都在其后）。
      try {
        loadBuiltinApiConfig(this.context);
      } catch (err2) {
        // 加载失败静默——设置页可自填
      }
      // ★ 0.278.12：隐藏自由窗口标题栏装饰（华为官方 AI 归因建议）——平板「最大化自由窗口」
      //   形态下系统 SCBSceneTitleBar 装饰层（Z 序压顶）是左侧黑块/左缘黑条的头号嫌疑层；
      //   隐藏后页面延伸至标题栏区域进入沉浸式布局，鼠标悬停热区仍浮现悬浮标题栏（关窗能力
      //   保留）；非自由窗口形态（手机全屏）调用无副作用；须在 loadContent 生效后调用（华为文档）
      try {
        windowStage.getMainWindowSync().setWindowDecorVisible(false); // 本 SDK 签名为同步 void（无 Promise）
      } catch (_e) {
        // 接口不可用/非自由窗口时静默
      }
      // ★ 0.279.3：maximize 沉浸式全屏**移除**（用户拍板「不要打开默认全屏」——0.278.12 为黑块
      //   嫌疑层加的 ENTER_IMMERSIVE 全屏体验差；黑块已定性系统渲染缺陷转华为工单，应用侧
      //   不再以全屏换黑块规避，恢复默认窗口形态；setWindowDecorVisible 保留非全屏防黑块尝试）
      // ★ 0.167：注册 Inter 三字重（UI_GUIDELINES.md 字体策略）——三个不同 familyName
      //（Pixso 导出代码三份同名注册会互相覆盖，是导出瑕疵勿照抄）；
      // Inter 无中文字形，中文自动 fallback 系统字体，无需打包 HarmonyOS Sans SC
      // ★ 0.167.1：顶层 font.registerFont since 18 废弃（编译 WARN）→ 改 UIContext.Font#registerFont
      //（@ohos.font.d.ts @useinstead 指定替代；loadContent 回调时主窗口已就绪，可取 UIContext）
      const uiFont = windowStage.getMainWindowSync().getUIContext().getFont();
      uiFont.registerFont({ familyName: 'Inter', familySrc: $rawfile('font/Inter-Regular_1.otf') });
      uiFont.registerFont({ familyName: 'Inter-Medium', familySrc: $rawfile('font/Inter-Medium_1.otf') });
      uiFont.registerFont({ familyName: 'Inter-SemiBold', familySrc: $rawfile('font/Inter-SemiBold_1.otf') });
    });

    // ★ 0.262.0：三态主题初始化（取代 0.166.3 固定暗紫）——loadContent 回调内执行：
    //   PersistenceV2 首连必须在 loadContent 之后（0.240.2 FAQ-1084 铁律，先连=盘值被无视恒 factory）；
    //   三分支：已落盘→按盘值 / 新用户（未同意协议）→暂深色不落盘待弹窗 / 老用户→静默落盘深色（Q4 终裁）
    try {
      setChromeSyncHook((isDark: boolean): void => {
        this.syncSystemChrome(windowStage, isDark);
      });
      this.initAppTheme();
    } catch (err) {
      // 主题初始化失败静默降级（AppTheme factory 默认深色兜底）
    }
  }

  // ★ 0.262.0：主题初始化——读 theme-mode-v1 三分支落位（降级兜底=深色，禁白闪）
  private initAppTheme(): void {
    const sysDark = this.readSystemDark();
    const theme = connectAppTheme();
    try {
      const saved = connectThemeMode().mode;
      if (saved === 'system' || saved === 'dark' || saved === 'light') {
        theme.applyMode(toThemeMode(saved), sysDark);
      } else if (needsAgreement()) {
        // 新用户：暂深色渲染**不落盘**——协议同意后 ThemeChooseDialog 选择才落盘（空串=待选择哨兵）
        theme.applyMode('dark', sysDark, false);
      } else {
        // 老用户覆盖升级：静默落盘深色不弹窗（防系统浅色用户升级突变浅色）；「外观」卡「新」角标引导
        theme.applyMode('dark', sysDark);
      }
    } catch (_e) {
      // 读取失败降级深色（不落盘）
      theme.applyMode('dark', sysDark, false);
    }
  }

  // 系统当前深浅（非浅即深兜底——符合「降级深色」总则）
  private readSystemDark(): boolean {
    try {
      return this.context.config?.colorMode !== ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    } catch (_e) {
      return true;
    }
  }

  // ★ 0.262.0：系统级联动（chromeSync 钩子回调）——setColorMode 让系统组件（权限弹窗/
  //   输入法候选栏/系统 Toast）与 app 主题同色系；状态栏文字色跟随（浅色下白字看不清）
  private syncSystemChrome(windowStage: window.WindowStage, isDark: boolean): void {
    try {
      this.context.getApplicationContext().setColorMode(isDark
        ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } catch (_e) {
      // 设置失败静默（页面 token 色不受影响）
    }
    try {
      windowStage.getMainWindowSync().setWindowBackgroundColor(isDark ? '#120B1F' : '#F7F5FA'); // ★ 0.278.8：窗口底色=页面 bgApp——状态栏/导航条区同色不黑边（对标 ChatCube 全屏一色，用户拍板）
    } catch (_e) {
      // 底色设置失败静默
    }
    try {
      windowStage.getMainWindowSync().setWindowSystemBarProperties({
        statusBarContentColor: isDark ? '#FFFFFF' : '#000000',
        navigationBarContentColor: isDark ? '#FFFFFF' : '#000000' // ★ 0.278.8：导航条手势区内容色随主题
      });
    } catch (_e) {
      // 状态栏设置失败静默
    }
  }

  // ★ 0.262.0：系统深浅色变化——mode='system' 时实时跟随（module.json5 configChanges
  //   已配 colorMode，系统切换不销毁重建、走本回调无缝切换）
  onConfigurationUpdate(newConfig: Configuration): void {
    try {
      const sysDark = newConfig.colorMode !== ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      connectAppTheme().refreshFromSystem(sysDark);
    } catch (_e) {
      // 静默（下次回调/重启兜底）
    }
  }

  onWindowStageDestroy(): void {
  }

  onForeground(): void {
    // ★ 0.153：回前台——清除全局后台标志
    const lifecycle = AppStorageV2.connect(AppLifecycleStore, 'app-lifecycle', () => new AppLifecycleStore()) as AppLifecycleStore;
    lifecycle.isBackground = false;
    setAiStreamBackground(false); // ★ 0.251.0：守卫前后台标志（完成通知仅后台发）
    // ★ 0.206.2：回前台补发埋点队列——真机实证 onBackground 里发网络必被鸿蒙后台限制掐掉
    //   （前台满批实测秒到，退后台 flush 全军覆没）；回前台网络已恢复，此处是可靠补发点
    //   （失败仍有 0.206.2 队列回滚兜底 + 下次满批/onForeground 再试）
    flushTrackQueue(this.context);
    // ★ 0.223.0：回前台强制端云同步——手机掉队根治点（下行此前纯等系统同步轮施舍：
    //   后台/冻结错过轮次后永远拿不到新数据；此处主动 cloudSync 拉平四池，
    //   与埋点补发同为「回前台=可靠追赶点」结论——0.206.2 同源经验）
    try {
      forceCloudSyncNow();
    } catch (_e) {
      // 静默（未激活/网络未就绪——下次前台再试）
    }
    // ★ 0.291.0：回前台拉云端退款标记（**主拉取点**——退款核销白嫖闭环论证：用 SP 必开 app，
    //   开 app 即拉取核销先于扣费生效；静默无提示，核销结果进账单页时展示）
    pullRefundMarks();
  }

  onBackground(): void {
    // ★ 0.153：切后台——置全局后台标志（★ 0.251.0 起仅作 UI 状态用：AI 请求不再主动中断，
    //   由 AiStreamGuard 长时任务保活续收——0.153「切后台必断」策略整体反转，用户拍板）
    const lifecycle = AppStorageV2.connect(AppLifecycleStore, 'app-lifecycle', () => new AppLifecycleStore()) as AppLifecycleStore;
    lifecycle.isBackground = true;
    setAiStreamBackground(true); // ★ 0.251.0：守卫前后台标志
    // ★ 0.228.0：行模式全量 flush 上行（本地 RDB 写入不受后台网络限制——推云交给 autoSync 轮/
    //   下次前台 forceCloudSyncNow；3 秒防抖未到点的残余变更由本 flush 兜底收口）
    try {
      flushCloudRowsNow();
    } catch (_e) {
      // 静默（下次启动/前台重试）
    }
    // ★ 0.205.0 三道防线：退后台时内部双备份（本会话最后状态落沙箱——升级异常/损坏的最后兜底）
    try {
      const wb = connectWordBank();
      const kb = connectKnowledgeBank();
      writeInternalBackup(this.context, buildBackupPayload(wb, kb));
    } catch (_e) {
      // 备份失败静默（下次启动会再备）
    }
    // ★ 0.265.0 记忆引擎 WP2.2/Q9：退后台瞬间申请 Background Tasks Kit 短时任务续跑本轮摘要头
    //   flush（防切后台被挂起导致下次无摘要头；结束即取消）
    try {
      flushHeadsOnBackground();
    } catch (_e) {
      // 静默（flush 内部已全降级；下次失活再入队）
    }
    // ★ 0.206.0 埋点：退后台尝试上报（★ 0.206.2 实证：多被鸿蒙后台网络限制掐掉，失败回滚队列——
    // 真正可靠的补发点是 onForeground 回前台；此处保留碰运气，万一发了就赚）
    flushTrackQueue(this.context);
  }
}
