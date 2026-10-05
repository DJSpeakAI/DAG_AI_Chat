// WindowMode.ets — ★ 0.196.4 窗口宽度模式（全项目 isTablet 共享真相源）
// 背景（用户实测报 bug）：各页原用 display 屏宽判定 isTablet——分屏/悬浮窗时**屏宽不变**
// （Pad 仍 2800px=1120vp≥600），App 在小窗里仍渲染平板布局（边栏挤压内容+黑屏）；
// 用户拍板：悬浮/分屏必须 100% 手机模式。改用**窗口实际宽度**：
//   Index 根 Stack onAreaChange 写入（窗口 resize 实时跟随），各页 @Computed 读同一实例。
// 阈值不变：窗口宽 ≥600vp = 平板布局（常驻边栏），<600vp = 手机布局（画布抽屉）。

import { AppStorageV2 } from '@kit.ArkUI';

@ObservedV2
export class WindowMode {
  @Trace isTablet: boolean = false; // 窗口宽 ≥600vp；Index 首帧用屏宽做初始猜测后由 onAreaChange 纠正
}

export function connectWindowMode(): WindowMode {
  return AppStorageV2.connect(WindowMode, 'window-mode', () => new WindowMode()) as WindowMode;
}
