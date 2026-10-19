// ============================================================
// DesignTokens.ets — UI 设计 Token（字号/圆角/字体/尺寸）
// ============================================================
// 真相源：根目录 UI_GUIDELINES.md（Pixso 三份导出工程提取合并）
// 规则（MEMORY.md 全局硬性约束第 4 条）：所有页面 UI 一律引用
// 本文件常量，禁止在页面代码散落写字号/圆角/尺寸。
// ★ 0.262.0：色值职责整体移交 common/AppTheme.ets（三态主题运行时
// 真相源——深浅两套 @Trace 切换；本文件仅保留非色值 token）。
// ============================================================

// ── 圆角 Token（5 档）──
export const RADIUS_NAV: number = 12;      // 导航项/图标按钮
export const RADIUS_NODE: number = 18;     // 气泡节点卡片
export const RADIUS_CANVAS: number = 24;   // 画布容器
export const RADIUS_CONTROL: number = 10;  // 控件（按钮/输入框/分段段）
export const RADIUS_LOGO: number = 12;     // Logo/节点图标容器

// ── 字体（Inter 三字重分别注册，注册见 EntryAbility；中文系统 fallback）──
export const FONT_INTER: string = 'Inter';                    // Regular(400)
export const FONT_INTER_MEDIUM: string = 'Inter-Medium';      // Medium(500)
export const FONT_INTER_SEMIBOLD: string = 'Inter-SemiBold';  // SemiBold(600)

// ── 字号 Token（UI_GUIDELINES 三）──
export const FONT_SIZE_SCREEN_TITLE: number = 16;  // ScreenTitle：画布页标题（平板）
export const FONT_SIZE_CARD_TITLE: number = 14;    // CardTitle：节点标题/手机画布标题
export const FONT_SIZE_CARD_TITLE_SM: number = 13; // CardTitleSm：按钮文字/账号昵称
export const FONT_SIZE_NAV_LABEL: number = 14;     // NavLabel：导航项
export const FONT_SIZE_BODY: number = 13;          // Body：正文
export const FONT_SIZE_META: number = 11;          // Meta：节点信息
export const FONT_SIZE_LABEL: number = 10;         // Label：分组标题（字距 0.5）
export const FONT_SIZE_CAPTION: number = 10;       // Caption：弱化说明

// ── 画布组件尺寸（UI_GUIDELINES 六-5）──
export const NODE_W: number = 170;    // 节点卡片宽（★ 0.173.1：150→170 拉宽，容纳元信息行「N 条对话 · X分钟前」完整显示，用户拍板；0.167.3 曾 200→150 砍 1/4）
export const NODE_H: number = 68;     // 节点卡片高
export const NODE_ICON: number = 40;  // 节点图标容器（圆角 RADIUS_LOGO，225° 渐变）
