// ============================================================
// EntryAbility.ets — 应用入口 Ability
// ============================================================
// 本文件是应用的 UI Ability（生命周期入口），负责：
//   - 加载主页面（pages/Index）
//   - 全局主题状态管理（ThemeStore）
// ★ 0.166.3：主题固定暗紫（方案 A）——不再跟随系统深浅色，所有用户统一暗色配色
//
// ThemeStore 是全局 UI 运行时状态（非持久化），
// 通过 AppStorageV2 在所有页面间共享。
// ============================================================

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { rpc } from '@kit.IPCKit'; // ★ 0.204.1：卡片 call 热路径——UIAbility Callee 机制（真机日志实证：进程存活时 call 走 Callee onRemoteMessageRequest 而非 onNewWant）
import { AppStorageV2, window } from '@kit.ArkUI'; // ★ 0.167：Inter 三字重注册（UIContext.Font，见 loadContent 回调）
import { util } from '@kit.ArkTS'; // 0.206.0：initAgc 读 rawfile json 解码
import { loadBuiltinApiConfig, setupCloudDownlink } from '../common/ChatModel'; // ★ 0.161.3：启动时从 rawfile/config.json 加载内置 API Key；★ 0.165.2：注册云端下行处理器
import { initCloudDb } from '../utils/CloudSyncUtil'; // ★ 0.165.1：启动时初始化云同步 RDB（建库建表+设分布式表）
import { handleWidgetRate, handleWidgetSwitch, handleWidgetContinue } from '../utils/WidgetHostBridge'; // 0.204.1 widget call; 0.204.2 continue
import { buildBackupPayload, writeInternalBackup } from '../utils/BackupUtil'; // 0.205.0 三道防线：退后台自动内部备份
import { connectWordBank } from '../utils/WordStoreUtil';
import { connectKnowledgeBank } from '../utils/KnowledgeStoreUtil';
import { initialize } from '@hw-agconnect/hmcore'; // 0.206.0 埋点：AGC 核心（云函数通道前置）
import { flushTrackQueue } from '../utils/TrackUtil'; // 0.206.0 埋点：退后台上报
// 0.204.1 Callee callback must return Parcelable (d.ts enforced) - empty impl
class EmptyParcelable implements rpc.Parcelable {
  marshalling(_dataOut: rpc.MessageSequence): boolean {
    return true;
  }

  unmarshalling(_dataIn: rpc.MessageSequence): boolean {
    return true;
  }
}

// ★ 全局主题状态（UI 运行时状态，非持久化数据模型）
@ObservedV2
export class ThemeStore {
  @Trace isDark: boolean = false;
}

// ★ 0.153：全局前后台状态（UI 运行时状态，非持久化）——NavDestination 组件没有
// onPageHide 生命周期，ChatPage 借此标志 + @Monitor 感知切后台，中断进行中的 AI 提炼
@ObservedV2
export class AppLifecycleStore {
  @Trace isBackground: boolean = false;
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleWidgetCallWant(want); // ★ 0.204.1：桌面卡片 call（冷启动路径——method/params 在 want.parameters）
    this.registerWidgetCallee(); // ★ 0.204.1：桌面卡片 call（热路径——进程存活/解冻后走 Callee，onCreate 时注册一次）
    this.initAgc(); // ★ 0.206.0：AGC 初始化（埋点云函数通道——rawfile/agconnect-services.json）
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
      if (method !== 'widgetRate' && method !== 'widgetSwitch' && method !== 'widgetContinue') {
        return;
      }
      const params = p['params'];
      const m = (typeof params === 'string' ? JSON.parse(params) : params) as Record<string, string>;
      if (method === 'widgetRate') {
        handleWidgetRate(this.context, m['rating'] ?? 'good');
      } else if (method === 'widgetContinue') {
        handleWidgetContinue(this.context);
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
    // ★ 0.161.3：加载内置 API Key（rawfile/config.json，本地文件不入 git）——
    // 放在 loadContent 之前，保证早于所有页面组件 connect ApiConfig（填充空位后再被各处读到）
    try {
      loadBuiltinApiConfig(this.context);
    } catch (err) {
      // 加载失败静默——设置页可自填
    }

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

    // Main window is created, set main page for this ability
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        return;
      }
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

    // ★ 0.166.3：主题固定暗紫（方案 A）——应用锁定暗色模式，不跟随系统深浅色：
    // 亮色系统用户也统一看到暗紫配色（Pixso 设计稿为单一暗紫色系）；
    // 系统状态栏/系统弹窗随 COLOR_MODE_DARK 走暗色风格，视觉全局统一
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (err) {
      // 设置失败静默忽略（isDark 仍固定 true，页面配色不受影响）
    }

    // ★ 0.166.3：isDark 固定 true（不再读系统 colorMode）——全项目 isDark 三元恒走
    // 暗色分支；亮色分支代码保留（未来若做双套色可直接复用）
    try {
      const themeStore = AppStorageV2.connect(ThemeStore, 'theme-store', () => new ThemeStore()) as ThemeStore;
      themeStore.isDark = true;
    } catch (err) {
      // 主题初始化失败静默忽略
    }
  }

  // ★ 0.166.3：删除 onConfigurationUpdate——主题固定暗紫后不再响应系统深浅色切换

  onWindowStageDestroy(): void {
  }

  onForeground(): void {
    // ★ 0.153：回前台——清除全局后台标志
    const lifecycle = AppStorageV2.connect(AppLifecycleStore, 'app-lifecycle', () => new AppLifecycleStore()) as AppLifecycleStore;
    lifecycle.isBackground = false;
    // ★ 0.206.2：回前台补发埋点队列——真机实证 onBackground 里发网络必被鸿蒙后台限制掐掉
    //   （前台满批实测秒到，退后台 flush 全军覆没）；回前台网络已恢复，此处是可靠补发点
    //   （失败仍有 0.206.2 队列回滚兜底 + 下次满批/onForeground 再试）
    flushTrackQueue(this.context);
  }

  onBackground(): void {
    // ★ 0.153：切后台——置全局后台标志（ChatPage @Monitor 感知后中断 AI 提炼：
    // 鸿蒙限制后台网络，长连接必断，干等只会白耗输入 token）
    const lifecycle = AppStorageV2.connect(AppLifecycleStore, 'app-lifecycle', () => new AppLifecycleStore()) as AppLifecycleStore;
    lifecycle.isBackground = true;
    // ★ 0.205.0 三道防线：退后台时内部双备份（本会话最后状态落沙箱——升级异常/损坏的最后兜底）
    try {
      const wb = connectWordBank();
      const kb = connectKnowledgeBank();
      writeInternalBackup(this.context, buildBackupPayload(wb, kb));
    } catch (_e) {
      // 备份失败静默（下次启动会再备）
    }
    // ★ 0.206.0 埋点：退后台尝试上报（★ 0.206.2 实证：多被鸿蒙后台网络限制掐掉，失败回滚队列——
    //   真正可靠的补发点是 onForeground 回前台；此处保留碰运气，万一发了就赚）
    flushTrackQueue(this.context);
  }
}
