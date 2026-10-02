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
