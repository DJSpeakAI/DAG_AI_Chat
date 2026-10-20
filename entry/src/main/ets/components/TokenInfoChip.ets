// TokenInfoChip.ets — ★ 0.272.0 通用感叹号信息卡（AI 调用全场景 SP 透明化）
// 形态：小感叹号图标（12×12 info.svg，对齐 ChatPage 消息操作行图标规格）+ bindPopup 自绘明细卡。
// 明细卡版式照 ChatPage.tokenInfoBuilder（272 定宽 + radius 12 + surfaceNode 底 + strokeCard 描边）：
//   第一行「输入 X SP · 输出 Y SP」（spCostOfTokens 公共公式换算——展示与扣点同源军令）；
//   第二行 SP 行=调用侧拼好传入（实扣场景「消耗 N SP」/ 鼓励「AI 鼓励 · 免费」紫字 / Lv8「Lv8 免费」）；
//   无缓存行（任务书拍板：新场景输入各不相同缓存命中期短，不展示缓存）。
// 零业务逻辑：不做扣费、不做埋点、不做免扣判定——全部由调用侧完成；
// ChatPage 主链路 tokenInfoBuilder 不动不换（防回归，本组件只给四个新点位用）。
import { spCostOfTokens, SP_TTS_PER_KCHAR } from '../common/ChatModel';
import { AppTheme, connectAppTheme } from '../common/AppTheme';

@ComponentV2
export struct TokenInfoChip {
  theme: AppTheme = connectAppTheme();
  @Param inputTokens: number = 0;  // 输入 token（第一行换算用）
  @Param outputTokens: number = 0; // 输出 token（第一行换算用）
  @Param spText: string = '';      // SP 行文本（调用侧拼好；空串=整卡不渲染）
  @Local popupOn: boolean = false;

  build() {
    if (this.spText.length > 0) {
      Image($r('app.media.info'))
        .width(12)
        .height(12)
        .objectFit(ImageFit.Contain)
        .opacity(0.65)
        .onClick(() => {
          this.popupOn = !this.popupOn;
        })
        .bindPopup(this.popupOn, {
          builder: this.popupBuilder(),
          placement: Placement.Top,
          popupColor: Color.Transparent, // 自绘卡全掌控（0.247.5 定式）
          radius: 12,
          mask: { color: this.theme.overlayLight },
          onStateChange: (e: PopupStateChangeParam) => {
            if (!e.isVisible) {
              this.popupOn = false;
            }
          }
        })
    }
  }

  // 明细卡（版式对齐 tokenInfoBuilder：272 定宽 + 两行居中）
  @Builder
  popupBuilder() {
    Column() {
      Text(`输入 ${spCostOfTokens(this.inputTokens, 0, 0)} SP · 输出 ${spCostOfTokens(0, this.outputTokens, 0)} SP`)
        .fontSize(13)
        .fontColor(this.theme.textPrimary)
        .textAlign(TextAlign.Center)
        .width('100%')
      Divider()
        .color(this.theme.strokeCard)
        .margin({ top: 9, bottom: 9 })
      Text(this.spText)
        .fontSize(13)
        .fontColor(this.theme.brandSecondary)
        .textAlign(TextAlign.Center)
        .width('100%')
      // ★ 0.279.0：音频计价说明行（与 ChatPage.tokenInfoBuilder 同款文案——两卡口径一致）；
      //   灰 12 号弱化：计价规则说明非本次消耗数字
      Divider()
        .color(this.theme.strokeCard)
        .margin({ top: 9, bottom: 9 })
      Text(`音频输出 · 本机免费 / 云端 ${SP_TTS_PER_KCHAR} SP/千字`)
        .fontSize(12)
        .fontColor(this.theme.textTertiary)
        .textAlign(TextAlign.Center)
        .width('100%')
      Text('音频输入 · 免费（语音转文字走系统输入法）')
        .fontSize(12)
        .fontColor(this.theme.textTertiary)
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width(272)
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .borderRadius(12)
    .border({ width: 1, color: this.theme.strokeCard })
    .backgroundColor(this.theme.surfaceNode)
  }
}
