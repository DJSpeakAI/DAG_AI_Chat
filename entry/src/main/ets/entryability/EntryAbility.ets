// ============================================================
// EntryAbility.ets — 应用入口 Ability
// ============================================================
// 本文件是应用的 UI Ability（生命周期入口），负责：
//   - 加载主页面（pages/Index）
//   - 全局主题状态管理（ThemeStore，深浅色切换）
//   - 系统配置变化监听（深浅色主题跟随系统切换）
//
// ThemeStore 是全局 UI 运行时状态（非持久化），
// 通过 AppStorageV2 在所有页面间共享。
// ============================================================

import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { AppStorageV2, window } from '@kit.ArkUI';
import { loadBuiltinApiConfig, setupCloudDownlink } from '../common/ChatModel'; // ★ 0.161.3：启动时从 rawfile/config.json 加载内置 API Key；★ 0.165.2：注册云端下行处理器
import { initCloudDb } from '../utils/CloudSyncUtil'; // ★ 0.165.1：启动时初始化云同步 RDB（建库建表+设分布式表）

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
    });

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      // 设置失败静默忽略（跟随系统默认色模式）
    }

    // ★ 初始化主题状态：读取当前系统深浅色模式
    try {
      const themeStore = AppStorageV2.connect(ThemeStore, 'theme-store', () => new ThemeStore()) as ThemeStore;
      themeStore.isDark = this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } catch (err) {
      // 主题初始化失败静默忽略（默认浅色）
    }
  }

  // ★ 系统主题变化时实时更新全局 ThemeStore
  onConfigurationUpdate(newConfig: Configuration): void {
    const themeStore = AppStorageV2.connect(ThemeStore, 'theme-store', () => new ThemeStore()) as ThemeStore;
    themeStore.isDark = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  onWindowStageDestroy(): void {
  }

  onForeground(): void {
    // ★ 0.153：回前台——清除全局后台标志
    const lifecycle = AppStorageV2.connect(AppLifecycleStore, 'app-lifecycle', () => new AppLifecycleStore()) as AppLifecycleStore;
    lifecycle.isBackground = false;
  }

  onBackground(): void {
    // ★ 0.153：切后台——置全局后台标志（ChatPage @Monitor 感知后中断 AI 提炼：
    // 鸿蒙限制后台网络，长连接必断，干等只会白耗输入 token）
    const lifecycle = AppStorageV2.connect(AppLifecycleStore, 'app-lifecycle', () => new AppLifecycleStore()) as AppLifecycleStore;
    lifecycle.isBackground = true;
  }
}
