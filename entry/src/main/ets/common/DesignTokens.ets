// ============================================================
// DesignTokens.ets — UI 设计 Token 单一来源（★ 0.167）
// ============================================================
// 真相源：根目录 UI_GUIDELINES.md（Pixso 三份导出工程提取合并）
// 规则（MEMORY.md 全局硬性约束第 4 条）：所有页面 UI 一律引用
// 本文件常量，禁止在页面代码散落写色值/字号/圆角。
// 主题：锁暗紫（v0.166.3 起 COLOR_MODE_DARK，无浅色分支）。
// ============================================================

// ── 色值 Token（14）──
export const BG_APP: string = '#120B1F';             // 应用底色
export const BG_NAV: string = '#1A1030';             // 左侧导航层
export const BG_CANVAS: string = '#160D26';          // 画布容器
export const SURFACE_NODE: string = '#241640';       // 节点卡片底色
export const SURFACE_HOVER: string = '#2C1B4D';      // 悬停/按压态底色
export const SURFACE_SOFT: string = 'rgba(255,255,255,0.04)';   // 柔面（账号区等）
export const BRAND_PRIMARY: string = '#7C4DFF';      // 主紫：品牌/选中/连线
export const BRAND_SECONDARY: string = '#A78BFA';    // 辅助紫：悬停强调/提示文字
export const TEXT_PRIMARY: string = '#FFFFFF';       // 主文字（白 100%）
export const TEXT_SECONDARY: string = 'rgba(255,255,255,0.65)'; // 次级文字
export const TEXT_TERTIARY: string = 'rgba(255,255,255,0.40)';  // 弱化文字
export const STROKE_CARD: string = 'rgba(255,255,255,0.08)';    // 卡片描边（白 8%）
export const STROKE_BRAND: string = 'rgba(124,77,255,0.40)';    // 悬停描边（主紫 40%）
export const SEGMENTED_TRACK: string = 'rgba(255,255,255,0.06)';// 分段控件轨道（白 6%）

// ── 连线专用色（UI_GUIDELINES 六-7：主紫 85%，高亮分支辅助紫）──
export const EDGE_COLOR: string = 'rgba(124,77,255,0.85)';
export const EDGE_COLOR_HIGHLIGHT: string = '#A78BFA';

// ── 语义色（★ 0.181.0 ChatPage 收敛：UI_GUIDELINES 14 token 未覆盖的内容语义色，
//    按总则「未覆盖场景按同组件规格类推」收敛为常量，禁止页面散落写值）──
export const DANGER: string = '#F44336';            // 删除/破坏性操作警示红
export const CODE_KEYWORD: string = '#569CD6';      // 代码高亮：关键字
export const CODE_STRING: string = '#98C379';       // 代码高亮：字符串
export const CODE_COMMENT: string = '#8A8A8A';      // 代码高亮：注释
export const CODE_NUMBER: string = '#D19A66';       // 代码高亮：数字
export const CODE_TEXT: string = '#D4D4D4';         // 代码高亮：普通文本
export const OVERLAY: string = 'rgba(0,0,0,0.5)';   // 弹窗遮罩（对齐 GlobalSettingsDialog）
export const OVERLAY_LIGHT: string = 'rgba(0,0,0,0.25)'; // 轻量浮窗遮罩（翻译浮窗/删除确认——底层对话保持可读）

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
