// ============================================================
// ThemeChooseDialog.ets — ★ 0.262.0 新用户首启主题选择弹窗（三选一）
// ============================================================
// 触发链：新用户（needsAgreement()=true）→ 协议同意（markAgreed）→
//   theme-mode-v1 仍为空（未落盘）→ 弹出本弹窗；主按钮点击即落盘确认，无二次确认。
// 老用户升级静默落盘深色不弹（Q4 终裁）；卸载重装=协议 key 清零=按新用户走。
// ★ 0.296.0：点选即预览——点哪张卡全局立即切到对应外观（applyMode persist=false 不落盘，
//   所见即所得；落盘+角标消除仍由主按钮统一执行）；弹窗自身随 token 即时变色。
// UI：标题「选择外观」+ 三张卡片（跟随系统默认高亮/深色/浅色），每卡 40vp mini
//   预览块；选中卡=主紫描边+柔面高亮；底部主按钮「进入 DAG AI Chat」。
// 宽度断点制：手机 86% / 平板 PC 固定 400（UI_GUIDELINES 六-12a，禁裸百分比）。
// 弹窗初始（未点选前）暗紫渲染与协议弹窗连贯（新用户此时必为暂深色态，直接读
//   theme token 即可）；点选后随 applyMode 即时切换深浅（0.296.0）。
// ============================================================

import { AppTheme, ThemeMode, connectAppTheme, chooseThemeMode, THEME_PREVIEW_DARK_BG, THEME_PREVIEW_LIGHT_BG } from '../common/AppTheme'; // ★ 0.305.1：主题样张色常量（AppTheme 单一真相源）
import { WindowMode, connectWindowMode } from '../common/WindowMode';
import { RADIUS_CONTROL, RADIUS_NODE, FONT_SIZE_CARD_TITLE_SM, FONT_SIZE_CAPTION, FONT_SIZE_BODY, FONT_INTER_SEMIBOLD } from '../common/DesignTokens';
import { common } from '@kit.AbilityKit'; // ★ 0.311.0：通知授权（UIAbilityContext）
import { notificationManager } from '@kit.NotificationKit'; // ★ 0.311.0：是否允许通知（学习提醒）
import Want from '@ohos.app.ability.Want'; // ★ 0.311.2：授权弹窗用尽后跳系统通知设置页（GSD openNotificationSettings 同款范式）

@ComponentV2
export struct ThemeChooseDialog {
  @Param visible: boolean = false;
  @Event onChoose: (mode: ThemeMode, improve: boolean) => void = (_mode: ThemeMode, _improve: boolean) => {
  };
  @Local selected: ThemeMode = 'system'; // 默认高亮「跟随系统」（任务书定稿）
  // ★ 0.303.0：体验改进计划并入外观页（单独控件、默认关、不与必选协议混排）
  @Local improveOn: boolean = false;
  // ★ 0.311.0：允许通知（学习提醒）——真实状态=系统通知授权，默认关由系统决定
  @Local notifyOn: boolean = false;
  // ★ 0.311.3：授权请求进行中标志（防轮询竞态把乐观置位打回）+ 系统真值轮询定时器
  @Local notifyRequesting: boolean = false;
  // ★ 0.311.4：本安装内已请求过授权标志（确定性主判——二次点击必跳设置，不依赖耗时启发式）
  // ⚠0.311.5 实测修正：**冷装/重置都不清系统侧「已询问」状态**（询问机会是系统级永久消耗，
  //   本机多次冷装后首点仍不弹）——此标志只代表「本组件实例已问过」，不能假设等于系统首次
  @Local notifyAsked: boolean = false;
  notifyPollTimer: number = -1;
  theme: AppTheme = connectAppTheme();
  windowMode: WindowMode = connectWindowMode();

  @Monitor('visible')
  onVisibleChange(): void {
    if (this.visible) {
      this.improveOn = false;
      this.refreshNotifyState();
      this.startNotifyPoll();
    } else {
      this.stopNotifyPoll();
    }
  }

  aboutToDisappear(): void {
    this.stopNotifyPoll(); // 定时器纪律：组件销毁必清（防内存泄漏军令）
  }

  // 系统通知授权真值查询（失败静默保持关闭——宁可漏显已开启也不误报可发送）
  refreshNotifyState(): void {
    notificationManager.isNotificationEnabled().then((on: boolean) => {
      this.notifyOn = on;
    }).catch(() => {
    });
  }

  // ★ 0.311.3：开关跟系统后台走（用户实测：系统设置里手动开启，返回 app 开关不变）——弹窗可见期
  //   2s 轻轮询对齐系统真值；请求进行中（notifyRequesting）暂停轮询，防授权弹窗挂起期迟到的 false
  //   轮询把乐观置位打回造成视觉错乱
  startNotifyPoll(): void {
    if (this.notifyPollTimer >= 0) {
      return;
    }
    this.notifyPollTimer = setInterval((): void => {
      if (!this.notifyRequesting) {
        this.refreshNotifyState();
      }
    }, 2000);
  }

  stopNotifyPoll(): void {
    if (this.notifyPollTimer >= 0) {
      clearInterval(this.notifyPollTimer);
      this.notifyPollTimer = -1;
    }
  }

  // 开=官方授权弹窗（仅首次弹）/ 关=应用无权静默撤销，开关回弹真值并指路系统设置
  // ★ 0.311.1：先乐观置 true 再回查（否则拒绝回查 false 状态无变化=Toggle 视觉不回弹）
  // ★ 0.311.5（用户实测拍板「第一次点也没弹，傻逼」）：系统授权询问机会是**系统级永久消耗**
  //   （华为规定每应用仅弹一次，冷装/重置都不清系统侧状态）——首次点击必须先尽力请求（系统肯弹就弹），
  //   系统不弹时**弹我们自己的引导框**（说明原因+「去设置」/「暂不开启」），用户主动点才跳转，
  //   绝不「点一下就飞走/毫无反应」；二次点击（notifyAsked=true）确定必跳系统设置页。
  //   判定：notifyAsked 标志为主（组件内首次请求机会消耗即置位）+ 请求耗时≥800ms 为用户操作过（拒绝=只回弹不骚扰）。
  onNotifyToggle(on: boolean): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!on) {
      this.notifyOn = false; // 先落一次状态（触发重绘），再回查系统真值回弹
      try {
        this.getUIContext().getPromptAction().showToast({
          message: '通知由系统管理，请前往 设置 > 通知和状态栏 > DAG AI Chat 关闭',
          duration: 5000 // ★ 0.311.4：用户实测 3 秒看不清，加长到 5 秒（范围内 1500~10000 合法）
        });
      } catch (_e) {
      }
      this.refreshNotifyState();
      return;
    }
    this.notifyOn = true; // 乐观置位：确保「系统拒绝→回查 false」是可观测的状态变化（否则开关卡在开态）
    this.notifyRequesting = true;
    notificationManager.isNotificationEnabled().then((enabled: boolean) => {
      if (enabled) {
        this.notifyRequesting = false; // 系统已开——直接对齐（无需弹窗/跳设置）
        return;
      }
      if (this.notifyAsked) {
        // 本安装内已请求过（官方：非首次不弹直接返 success）——确定必跳系统开关页
        this.refreshNotifyStateAfterRequest(true);
        return;
      }
      // 首次请求：系统弹窗（用户交互）或已用尽（快速返回）——统一只回弹，跳转留给下一次点击
      notificationManager.requestEnableNotification(context).then(() => {
        this.notifyAsked = true; // 询问机会已消耗（无论本次弹没弹）
        this.refreshNotifyStateAfterRequest(false);
      }).catch(() => {
        this.notifyAsked = true;
        this.refreshNotifyStateAfterRequest(false);
      });
    }).catch(() => {
      this.notifyOn = false;
      this.notifyRequesting = false;
    });
  }

  // 授权请求结束后的真值回查（★ 0.311.1）：仍关时按场景给出路——
  //   forceJump=true（notifyAsked 二次点击/弹窗机会已消耗）：直接跳系统通知开关页；
  //   forceJump=false（首次：系统弹了被拒 / 系统没弹）：只回弹（★ 0.311.6 用户拍板删除引导框——
  //   「这个提醒真的可以删除掉，用户体验也不好」，明确拒绝后不再弹任何说明）
  refreshNotifyStateAfterRequest(forceJump: boolean): void {
    notificationManager.isNotificationEnabled().then((on: boolean) => {
      this.notifyOn = on;
      this.notifyRequesting = false;
      if (!on && forceJump) {
        this.jumpToNotificationSettings();
      }
    }).catch(() => {
      this.notifyOn = false;
      this.notifyRequesting = false;
    });
  }

  // ★ 0.311.2：直达本应用系统通知设置页（uri=systemui_notification_settings+pushParams 包名——官方 settings 范式）
  jumpToNotificationSettings(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const want: Want = {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
      uri: 'systemui_notification_settings',
      parameters: { pushParams: 'com.dagaichat.app' }
    };
    context.startAbility(want).catch(() => {
      try {
        this.getUIContext().getPromptAction().showToast({
          message: '跳转失败，请到 设置 > 通知和状态栏 > DAG AI Chat 允许通知',
          duration: 4000
        });
      } catch (_e) {
      }
    });
  }

  build() {
    if (this.visible) {
      Stack({ alignContent: Alignment.Center }) {
        Column({ space: 16 }) {
          Text('选择外观')
            .fontSize(16)
            .fontWeight(600)
            .fontFamily(FONT_INTER_SEMIBOLD)
            .fontColor(this.theme.textPrimary)

          // 三张卡片（跟随系统/深色/浅色）
          Row({ space: 10 }) {
            this.themeCard('system', '跟随系统', '随系统深浅色自动切换', true)
            this.themeCard('dark', '深色', '暗紫经典', false)
            this.themeCard('light', '浅色', '清新明亮', false)
          }
          .width('100%')

          // ★ 0.303.0：体验改进计划（单独同意、默认关——不与必选协议混排）
          Row({ space: 10 }) {
            Column({ space: 2 }) {
              Text('加入体验改进计划')
                .fontSize(FONT_SIZE_BODY)
                .fontColor(this.theme.textPrimary)
              Text('仅收集匿名功能使用频次，不含对话与学习内容，可随时在设置中关闭')
                .fontSize(FONT_SIZE_CAPTION)
                .lineHeight(16)
                .fontColor(this.theme.textTertiary)
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.improveOn })
              .onChange((on: boolean) => {
                this.improveOn = on;
              })
          }
          .width('100%')
          .padding(10)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(this.theme.surfaceSoft)
          .alignItems(VerticalAlign.Center)

          // ★ 0.311.0：允许通知（学习提醒）——UI 与体验改进计划同款；开关真值=系统通知授权
          Row({ space: 10 }) {
            Column({ space: 2 }) {
              Text('允许通知')
                .fontSize(FONT_SIZE_BODY)
                .fontColor(this.theme.textPrimary)
              Text('接收背单词、识字卡片等学习提醒，可随时在系统设置中关闭')
                .fontSize(FONT_SIZE_CAPTION)
                .lineHeight(16)
                .fontColor(this.theme.textTertiary)
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.notifyOn })
              .onChange((on: boolean) => {
                this.onNotifyToggle(on);
              })
          }
          .width('100%')
          .padding(10)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(this.theme.surfaceSoft)
          .alignItems(VerticalAlign.Center)

          // 主按钮（进入 DAG AI Chat——选择即确认即落盘）
          Text('进入 DAG AI Chat')
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .width('100%')
            .padding({ top: 10, bottom: 10 })
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(this.theme.brandPrimary)
            .onClick(() => {
              chooseThemeMode(this.selected);
              this.onChoose(this.selected, this.improveOn);
            })
        }
        .padding(20)
        .borderRadius(RADIUS_NODE)
        .backgroundColor(this.theme.surfaceNode)
        .width(this.windowMode.isTablet ? 400 : '86%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.overlay)
    }
  }

  // 单张主题卡：40vp mini 预览块（跟随=左暗右浅对半 / 深=暗紫底 / 浅=白底，中间小紫块示意主紫贯穿）
  @Builder
  themeCard(mode: string, title: string, subtitle: string, half: boolean) {
    Column({ space: 6 }) {
      Stack() {
        if (half) {
          Row() {
            Column().backgroundColor(THEME_PREVIEW_DARK_BG).layoutWeight(1).height('100%')
            Column().backgroundColor(THEME_PREVIEW_LIGHT_BG).layoutWeight(1).height('100%')
          }
          .width('100%')
          .height('100%')
        } else {
          Column()
            .backgroundColor(mode === 'dark' ? THEME_PREVIEW_DARK_BG : THEME_PREVIEW_LIGHT_BG)
            .width('100%')
            .height('100%')
        }
        // 主紫贯穿示意（居中小紫块）
        Column()
          .backgroundColor(this.theme.brandPrimary)
          .width(10)
          .height(10)
          .borderRadius(3)
      }
      .width('100%')
      .height(40)
      .borderRadius(RADIUS_CONTROL - 4)
      .clip(true)

      Text(title)
        .fontSize(FONT_SIZE_BODY)
        .fontWeight(this.selected === mode ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.selected === mode ? this.theme.textPrimary : this.theme.textSecondary)

      Text(subtitle)
        .fontSize(FONT_SIZE_CAPTION)
        .fontColor(this.theme.textTertiary)
    }
    .layoutWeight(1)
    .padding(10)
    .borderRadius(RADIUS_CONTROL)
    .backgroundColor(this.selected === mode ? this.theme.surfaceSoft : Color.Transparent)
    .border({
      width: this.selected === mode ? 1.5 : 1,
      color: this.selected === mode ? this.theme.strokeBrand : this.theme.strokeCard
    })
    .onClick(() => {
      if (mode === 'system' || mode === 'dark' || mode === 'light') {
        this.selected = mode;
        // ★ 0.296.0：点选即预览——全局立即切到该外观（不落盘；落盘仍由主按钮 chooseThemeMode 统一执行）
        this.theme.applyMode(mode, this.theme.systemDark, false);
      }
    })
  }
}
