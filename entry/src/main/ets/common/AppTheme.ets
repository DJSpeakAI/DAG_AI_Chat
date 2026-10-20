// ============================================================
// AppTheme.ets — ★ 0.262.0 运行时主题源（唯一色值真相源）
// ============================================================
// 三态主题模型（docs/0.262.0 总方案）：
//   themeMode（用户意图，PersistenceV2 key 'theme-mode-v1'）: system | dark | light
//   effectiveDark（运行时生效态）: system→按系统 colorMode 换算；dark→true；light→false
// 色值职责自 DesignTokens.ets 移交（DesignTokens 保留字号/圆角/字体/尺寸）；
// 深色=原暗紫原样（品牌延续），浅色=新设计一套（WCAG AA 达标）。
// 运行时态走 AppStorageV2 key 'app-theme-v1'（全项目同实例，@Trace 切换即时生效）；
// 持久态走 PersistenceV2 key 'theme-mode-v1'（Schema 铁律：全新 key 不碰存量）。
// ============================================================

import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';

export type ThemeMode = 'system' | 'dark' | 'light';

// 持久化：用户主题意图（'' = 从未落盘——新用户首启待弹窗选择的哨兵值）
@ObservedV2
export class ThemeModeStore {
  @Trace mode: string = '';
}

export function connectThemeMode(): ThemeModeStore {
  return PersistenceV2.connect(ThemeModeStore, 'theme-mode-v1',
    () => new ThemeModeStore()) as ThemeModeStore;
}

// 持久化：「外观」卡「新」角标消除状态（用户主动选过任意主题即置 true，静默落盘用户保持 false）
@ObservedV2
export class ThemeBadgeStore {
  @Trace seen: boolean = false;
}

export function connectThemeBadge(): ThemeBadgeStore {
  return PersistenceV2.connect(ThemeBadgeStore, 'theme-badge-seen-v1',
    () => new ThemeBadgeStore()) as ThemeBadgeStore;
}

// 系统级联动钩子（setColorMode + 状态栏文字色）——由 EntryAbility 注入
// （Ability 层持有 windowStage/applicationContext；组件层无法反向获取，走注入先例：
//  同 EntryAbility.initRowBridgeProviders 的 provider 注入模式）
let chromeSync: ((isDark: boolean) => void) | undefined = undefined;

export function setChromeSyncHook(fn: (isDark: boolean) => void): void {
  chromeSync = fn;
}

@ObservedV2
export class AppTheme {
  @Trace mode: ThemeMode = 'dark';      // 用户意图三态
  @Trace isDark: boolean = true;        // effectiveDark（运行时生效态）
  @Trace systemDark: boolean = true;    // 系统当前深浅（EntryAbility 初始化/变更时写入，组件层弹窗换算用）

  // 全色值字段（与原 DesignTokens 常量一一对应，字段类型全 string 同型替换）
  @Trace bgApp: string = '#120B1F';
  @Trace bgNav: string = '#1A1030';
  @Trace bgCanvas: string = '#160D26';
  @Trace surfaceNode: string = '#241640';
  @Trace surfaceHover: string = '#2C1B4D';
  @Trace surfaceSoft: string = 'rgba(255,255,255,0.04)';
  // ★ 0.278.13：对话气泡独立底色——AI 气泡比原 surfaceNode 暗一档（用户反馈「太亮、影响阅读集中力」），
  //   用户气泡再暗一档（用户拍板「用户发的至少要比 AI 的暗」）；原 0.195.0「两者一律 surfaceNode」作废
  @Trace bubbleAiBg: string = '#1E1236';
  @Trace bubbleUserBg: string = '#190F2A';
  // ★ 0.278.13：用户消息正文色——比 AI 正文（textPrimary）暗一档，用文字明度做角色区分
  @Trace userMsgText: string = 'rgba(255,255,255,0.88)';
  @Trace brandPrimary: string = '#7C4DFF';
  @Trace brandSecondary: string = '#A78BFA';
  @Trace textPrimary: string = '#FFFFFF';
  @Trace textSecondary: string = 'rgba(255,255,255,0.65)';
  @Trace textTertiary: string = 'rgba(255,255,255,0.40)';
  @Trace strokeCard: string = 'rgba(255,255,255,0.08)';
  @Trace strokeBrand: string = 'rgba(124,77,255,0.40)';
  @Trace segmentedTrack: string = 'rgba(255,255,255,0.06)';
  @Trace edgeColor: string = 'rgba(124,77,255,0.85)';
  @Trace edgeHighlight: string = '#A78BFA';
  @Trace danger: string = '#F44336';
  @Trace success: string = '#3BB273';
  @Trace reviewHard: string = '#E5484D';
  @Trace reviewGood: string = '#F5A623';
  @Trace reviewEasy: string = '#3BB273';
  @Trace reviewHardBg: string = 'rgba(229,72,77,0.15)';
  @Trace reviewGoodBg: string = 'rgba(245,166,35,0.15)';
  @Trace reviewEasyBg: string = 'rgba(59,178,115,0.15)';
  @Trace codeKeyword: string = '#569CD6';
  @Trace codeString: string = '#98C379';
  @Trace codeComment: string = '#8A8A8A';
  @Trace codeNumber: string = '#D19A66';
  @Trace codeText: string = '#D4D4D4';
  @Trace overlay: string = 'rgba(0,0,0,0.5)';
  @Trace overlayLight: string = 'rgba(0,0,0,0.25)';
  @Trace shadowColor: string = 'rgba(0,0,0,0.40)'; // ★ 0.262.0 新增：卡片/菜单阴影基色（暗=黑系，浅=深紫黑 8%）
  @Trace shadowColorSoft: string = 'rgba(0,0,0,0.25)'; // 轻阴影档（浮层小阴影——浅色同挂浅基色）
  @Trace hookBg: string = 'rgba(124,77,255,0.08)'; // ★ 0.269.0 新增：钩子竖线块背景（品牌紫 8% 透明叠加——深浅色各自基色，禁硬编码）

  // 切换主题：重算生效态 + 整表赋值 + 落盘（persist=false 用于新用户「暂 dark 待弹窗」不落盘）
  applyMode(m: ThemeMode, sysDark: boolean, persist: boolean = true): void {
    this.mode = m;
    this.systemDark = sysDark;
    this.isDark = m === 'dark' || (m === 'system' && sysDark);
    if (this.isDark) {
      this.applyDarkPalette();
    } else {
      this.applyLightPalette();
    }
    if (persist) {
      connectThemeMode().mode = m;
    }
    if (chromeSync !== undefined) {
      chromeSync(this.isDark);
    }
  }

  // 系统深浅变化（仅跟随系统模式生效；主动 dark/light 不受影响）
  refreshFromSystem(sysDark: boolean): void {
    this.systemDark = sysDark;
    if (this.mode !== 'system') {
      return;
    }
    const wasDark = this.isDark;
    this.isDark = sysDark;
    if (this.isDark) {
      this.applyDarkPalette();
    } else {
      this.applyLightPalette();
    }
    if (wasDark !== this.isDark && chromeSync !== undefined) {
      chromeSync(this.isDark);
    }
  }

  // 深色=原暗紫原样（0.166.3 起几十版用户验收配色，token 原样搬家）
  private applyDarkPalette(): void {
    this.bgApp = '#120B1F';
    this.bgNav = '#1A1030';
    this.bgCanvas = '#160D26';
    this.surfaceNode = '#241640';
    this.surfaceHover = '#2C1B4D';
    this.surfaceSoft = 'rgba(255,255,255,0.04)';
    this.bubbleAiBg = '#1E1236';
    this.bubbleUserBg = '#190F2A';
    this.userMsgText = 'rgba(255,255,255,0.88)';
    this.brandPrimary = '#7C4DFF';
    this.brandSecondary = '#A78BFA';
    this.textPrimary = '#FFFFFF';
    this.textSecondary = 'rgba(255,255,255,0.65)';
    this.textTertiary = 'rgba(255,255,255,0.40)';
    this.strokeCard = 'rgba(255,255,255,0.08)';
    this.strokeBrand = 'rgba(124,77,255,0.40)';
    this.segmentedTrack = 'rgba(255,255,255,0.06)';
    this.edgeColor = 'rgba(124,77,255,0.85)';
    this.edgeHighlight = '#A78BFA';
    this.danger = '#F44336';
    this.success = '#3BB273';
    this.reviewHard = '#E5484D';
    this.reviewGood = '#F5A623';
    this.reviewEasy = '#3BB273';
    this.reviewHardBg = 'rgba(229,72,77,0.15)';
    this.reviewGoodBg = 'rgba(245,166,35,0.15)';
    this.reviewEasyBg = 'rgba(59,178,115,0.15)';
    this.codeKeyword = '#569CD6';
    this.codeString = '#98C379';
    this.codeComment = '#8A8A8A';
    this.codeNumber = '#D19A66';
    this.codeText = '#D4D4D4';
    this.overlay = 'rgba(0,0,0,0.5)';
    this.overlayLight = 'rgba(0,0,0,0.25)';
    this.shadowColor = 'rgba(0,0,0,0.40)';
    this.shadowColorSoft = 'rgba(0,0,0,0.25)';
    this.hookBg = 'rgba(124,77,255,0.08)'; // ★ 0.269.0：钩子竖线块背景（深色档紫基 8%）
  }

  // 浅色=新设计一套（0.262.0 终值表：紫味浅灰底/白卡；主紫加深达标；透明度基色统一 29,18,48）
  private applyLightPalette(): void {
    this.bgApp = '#F7F5FA';
    this.bgNav = '#FBFAFE';
    this.bgCanvas = '#F2EEF8';
    this.surfaceNode = '#FFFFFF';
    this.surfaceHover = '#EFE9FA';
    this.surfaceSoft = 'rgba(29,18,48,0.04)';
    this.bubbleAiBg = '#FFFFFF';
    this.bubbleUserBg = '#F1ECFA';
    this.userMsgText = 'rgba(29,18,48,0.88)';
    this.brandPrimary = '#6C3EE8';
    this.brandSecondary = '#5D3FD3';
    this.textPrimary = '#1D1230';
    this.textSecondary = 'rgba(29,18,48,0.65)';
    this.textTertiary = 'rgba(29,18,48,0.40)';
    this.strokeCard = 'rgba(29,18,48,0.08)';
    this.strokeBrand = 'rgba(108,62,232,0.35)';
    this.segmentedTrack = 'rgba(29,18,48,0.06)';
    this.edgeColor = 'rgba(124,77,255,0.55)';
    this.edgeHighlight = '#5D3FD3';
    this.danger = '#D93025';
    this.success = '#2E9660';
    this.reviewHard = '#D63A3F';
    this.reviewGood = '#D98E12';
    this.reviewEasy = '#2E9660';
    this.reviewHardBg = 'rgba(214,58,63,0.15)';
    this.reviewGoodBg = 'rgba(217,142,18,0.15)';
    this.reviewEasyBg = 'rgba(46,150,96,0.15)';
    this.codeKeyword = '#0000FF';
    this.codeString = '#A31515';
    this.codeComment = '#008000';
    this.codeNumber = '#098658';
    this.codeText = '#1F1F1F';
    this.overlay = 'rgba(0,0,0,0.30)';
    this.overlayLight = 'rgba(0,0,0,0.18)';
    this.shadowColor = 'rgba(29,18,48,0.08)';
    this.shadowColorSoft = 'rgba(29,18,48,0.08)';
    this.hookBg = 'rgba(108,62,232,0.08)'; // ★ 0.269.0：钩子竖线块背景（浅色档浅紫基 8%）
  }
}

export function connectAppTheme(): AppTheme {
  return AppStorageV2.connect(AppTheme, 'app-theme-v1', () => new AppTheme()) as AppTheme;
}

// 盘值 string→ThemeMode 收窄（脏值/空串一律归 dark——降级深色总则）
export function toThemeMode(s: string): ThemeMode {
  return s === 'system' || s === 'light' ? s : 'dark';
}

// 主动选择主题（GSD 外观卡 / ThemeChooseDialog 调用）——落盘 + 角标消除
export function chooseThemeMode(m: ThemeMode): void {
  const theme = connectAppTheme();
  theme.applyMode(m, theme.systemDark);
  connectThemeBadge().seen = true;
}
