// ============================================================
// WaitingDots.ets — 三点跳动等待动画（★ 0.190.5 原创，★ 拆分自 ChatPage.ets）
// ============================================================
// 用户选定方案：非静态等待，三点滚动表示正在等 AI 回复。
// 0.160.2 秒表（⏱ 读秒）失败教训=页级定时器难清理；本组件**自管定时器**——
// aboutToAppear 启动 / aboutToDisappear 必然清理（组件随占位气泡卸载），零泄漏。
// phase 0→1→2 循环点亮三个点，属性动画 300ms 平滑过渡大小与颜色。
// 消费方：ChatPage（流式占位气泡）/ ReviewPage（完成页总结生成中）/ 弹窗内轻量场景。
import { AppTheme, connectAppTheme } from '../common/AppTheme';

@ComponentV2
export struct WaitingDots {
  theme: AppTheme = connectAppTheme(); // ★ 0.196.2：export——ReviewPage 完成页「总结正在生成」复用（0.190.5 原创组件）
  @Local phase: number = 0;
  private timerId: number = -1;

  aboutToAppear(): void {
    this.timerId = setInterval(() => {
      this.phase = (this.phase + 1) % 3;
    }, 400);
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  build() {
    Row({ space: 4 }) {
      Text('●')
        .fontSize(this.phase === 0 ? 10 : 6)
        .fontColor(this.phase === 0 ? this.theme.brandSecondary : this.theme.textTertiary)
        .animation({ duration: 300, curve: Curve.EaseInOut })
      Text('●')
        .fontSize(this.phase === 1 ? 10 : 6)
        .fontColor(this.phase === 1 ? this.theme.brandSecondary : this.theme.textTertiary)
        .animation({ duration: 300, curve: Curve.EaseInOut })
      Text('●')
        .fontSize(this.phase === 2 ? 10 : 6)
        .fontColor(this.phase === 2 ? this.theme.brandSecondary : this.theme.textTertiary)
        .animation({ duration: 300, curve: Curve.EaseInOut })
    }
    .height(14)
    .alignItems(VerticalAlign.Center)
  }
}
