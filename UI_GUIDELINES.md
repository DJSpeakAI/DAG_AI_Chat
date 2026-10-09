# UI_GUIDELINES — DAG AI Chat UI 大纲总则

> **定位**：项目级 UI 设计真相源（与 README.md / MEMORY.md 齐平）。
> **⚠️ 所有 UI 开发必须遵守本大纲**：新页面、页面改版、UI bug 修复，一律以本文档参数为准；本文档未覆盖的场景按同组件规格类推，落地后回填本文档。
> **真相源优先级**：Pixso 导出代码参数 > 代码内图例标注 > 截图标注页。
> **来源**：`PixsoUI/` 三份导出工程（状态与规格 / 平板二稿 / 手机二稿），2026-10-04 提取合并。
> **主题**：锁暗紫（v0.166.3 起 EntryAbility 强制 `COLOR_MODE_DARK`，无浅色模式，不做浅色分支）。

---

## 一、色值 Token（14 个）

落地常量收敛到 `DesignTokens.ets`（唯一来源，**禁止在页面代码里散落写色值 / isDark 三元**）。

| 常量名 | Pixso 变量 | 值 | 用途 |
|------|------|------|------|
| BG_APP | color/bg-app | `#120B1F` | 应用底色 |
| BG_NAV | color/bg-nav | `#1A1030` | 左侧导航层 |
| BG_CANVAS | color/bg-canvas | `#160D26` | 画布容器 |
| SURFACE_NODE | color/surface-node | `#241640` | 气泡节点卡片底色 |
| SURFACE_HOVER | color/surface-hover | `#2C1B4D` | 悬停态底色 |
| SURFACE_SOFT | color/surface-soft | `#FFFFFF` 4% | 账号区等柔面 |
| BRAND_PRIMARY | color/brand-primary | `#7C4DFF` | 主紫：品牌 / 选中 / 连线 |
| BRAND_SECONDARY | color/brand-secondary | `#A78BFA` | 辅助紫：悬停强调 / 提示文字 |
| TEXT_PRIMARY | color/text-primary | `#FFFFFF` 100% | 主文字 |
| TEXT_SECONDARY | color/text-secondary | `#FFFFFF` 65% | 次级文字（导航默认 / 节点信息） |
| TEXT_TERTIARY | color/text-tertiary | `#FFFFFF` 40% | 弱化文字（时间戳 / 说明） |
| STROKE_CARD | color/stroke-card | `#FFFFFF` 8% | 卡片描边 |
| STROKE_BRAND | color/stroke-brand | `#7C4DFF` 40% | 悬停描边 / 未登录图标容器描边 |
| SEGMENTED_TRACK | color/segmented-track | `#FFFFFF` 6% | 分段控件轨道底色（平板二稿新增） |

## 二、圆角 Token（5 档）

| 常量名 | 值 | 用途 |
|------|------|------|
| RADIUS_NAV | 12 | 导航项 / 图标按钮 |
| RADIUS_NODE | 18 | 气泡节点卡片 |
| RADIUS_CANVAS | 24 | 画布容器 |
| RADIUS_CONTROL | 10 | 控件（按钮 / 输入框 / 分段控件内段） |
| RADIUS_LOGO | 12 | Logo / 节点图标容器 |

## 三、文字样式（8 个）与字体策略

| 样式 | 字号 | 字重 | 行高 | 字距 | 用途 |
|------|------|------|------|------|------|
| ScreenTitle | 16 | SemiBold(600) | 140% | 0 | 画布页标题（平板） |
| CardTitle | 14 | SemiBold(600) | 140% | 0 | 节点标题 / 手机画布标题 |
| CardTitleSm | 13 | SemiBold(600) | 140% | 0 | 手机节点标题 / 账号昵称 / 按钮文字 |
| NavLabel | 14 | Medium(500) | 140% | 0 | 导航项 |
| Body | 13 | Regular(400) | 150% | 0 | 正文（手机状态栏时间） |
| Meta | 11 | Regular(400) | 140% | 0 | 节点信息（X 条对话 · 时间） |
| Label | 10 | Medium(500) | 120% | 0.5 | 分组标题（工作区） |
| Caption | 10 | Regular(400) | 120% | 0 | 弱化说明 |

**字体策略**：统一注册 **Inter** 字体族（rawfile/font：Regular / Medium / SemiBold 三个字重文件）。中文文本无需打包字体——Inter 无中文字形，系统自动 fallback 到 HarmonyOS Sans SC，与设计稿渲染一致。**禁止**单独引入 HarmonyOS Sans SC 字体文件。

## 四、间距

**语义档位（4 档）**：xs=8（图标与文字）/ sm=12（节点内元素）/ md=16（组件间）/ lg=24（区块间）。

**组件级间距**：

| 区域 | 参数 | 值 |
|------|------|------|
| 侧边栏 | 容器内边距 | 上 24 / 下 20 / 左右 16（平板）；上 20 / 下 16（手机） |
| 侧边栏 | 导航项之间 gap | 4 |
| 侧边栏 | Logo 区与导航区 | 24 |
| 导航项 | 图标与文字 | 10 |
| 节点卡片 | 图标容器与文字 | 10 |
| 节点卡片 | 标题与信息行 | 3（平板稿）/ 4（状态页） |
| 画布容器 | 内边距 | 24 |
| 画布容器 | 信息条与画布区 | 24 |
| 手机 | 列表左右边距 | 14 |
| 手机 | 缩进步长 | 20 / 层级 |
| 手机 | 兄弟节点间距 | 12 |
| 设置弹窗 | 小字行间距（★ 0.175.0 入规则，以云同步 Tab 为标准） | 字号 11 / TEXT_TERTIARY；副标题与主标题距 2；提示/条目与上方内容距 4、条目间 4；连续多行提示小字 lineHeight 18（行隙节奏与条目间距一致，勿用默认行高） |
| 设置弹窗 | 底部保存按钮行（★ 0.197.2 入规则——复习 Tab 加入保存模式后全弹窗统一，以 API/AI 偏好 Tab 为标准；★ 0.197.3 等宽强制） | 双按钮**必须像素级等宽等高**：`Row({ space: 12 })` 内各 `.layoutWeight(1)` + `.height(48)`——**间隙一律用 Row space，禁止挂单侧 margin**（margin 参与 layoutWeight 分配会把该侧按钮挤窄，0.197.3 用户实测不等宽 bug）。**保存（左）= BRAND_PRIMARY 底 + TEXT_PRIMARY 字**，**返回（右）= SURFACE_SOFT 底 + TEXT_SECONDARY 字**；统一 fontSize CardTitleSm(13) / FontWeight Medium / 圆角 RADIUS_CONTROL，行 margin top 12。按钮行固定在内容区（Scroll）**之外**的弹窗底部——表单超屏滚动时保存不被推出（0.140 教训）。保存不关弹窗 + toast「已保存」；返回走 requestClose（有未保存修改时 AlertDialog 二次确认）。无保存概念 Tab（云同步/关于）用全宽「返回」同规格 |
| 模态弹窗与操作按钮（★ 0.201.2 入规则——问AI面板/编辑弹窗平板实测按钮超宽拉满，用户拍板收敛） | **宽屏/小屏双断点制（isTablet 三元，禁用裸百分比宽）**：①底部弹起面板（bottom sheet）——手机 `width('100%')` 贴底 / 平板固定 **460** 居中，圆角四角 RADIUS_NAV（手机贴底时下圆角贴屏不可见无副作用）；②居中模态弹窗——手机 `width('86%')` / 平板固定 **520**；③面板内纵排操作按钮（主操作/次操作/取消）——手机 `width('100%')` / 平板固定 **280** 居中。**禁止按钮裸 `width('100%')` 在宽屏拉伸**（用户实测「太长了」）；**禁止用 constraintSize 钳显式 width**（0.198.4 教训：constraintSize 在显式 width 面前失效）——固定值断点制是唯一可靠姿势；三按钮层级：主操作 BRAND_PRIMARY 底白字、次操作透明底 BRAND_SECONDARY 描边、取消透明底 TEXT_SECONDARY 无框 |
| 弱化功能入口标签（★ 0.201.3 入规则，0.201.4 补文案规则——通用标准；案例=知识库列表卡「问AI?」入口，用户验收「看上去很舒服，非常棒」） | **适用场景：功���需要入口、但不可凸显抢视觉**——弱化标签与页面既有弱化文字（如「未学习」状态行）同层级。规格：**高度=相邻弱化文字等高**（height 16，`.height` 含 border——0.196.7 教训）；fontSize **比该文字小一号**（11→10）补偿描边框体视觉；padding 仅左右 5（上下 0，垂直居中由 height 保证）；描边 1 / TEXT_TERTIARY / 圆角 RADIUS_CONTROL；文字全灰同色（辅助紫等强调色在此层级禁用）；位置=所在行右端（Row 内 layoutWeight(1) 主文字 + 入口标签）。**配套面板文案规则：从入口进来意图已明确——禁止再写「把这张卡片…？」类解释性标题与对象回显（废话），面板直接从操作按钮开路** |

## 五、布局规格

### 平板（designWidth 1280，1280×800）

- **侧边栏**：240×800，底色 BG_NAV；内容区宽 208
- **画布区**：外容器 1040×800 padding 24；**画布容器 992×752**，圆角 RADIUS_CANVAS(24)，底色 BG_CANVAS，clip
- **信息条**：position(28,24)，宽 936 高 40——标题 ScreenTitle + 统计 Meta 行距 2；右侧分段控件 + 新建按钮
- **缩放控件**：position(920,596)，48×132
- **节点卡片**：150×68（★ 0.167.3：200→150 砍 1/4），绝对定位；水平树布局 X 层级差 270（参考稿：根(40,316) → L2(310,160~448) → L3(580,160~530) → L4(850,432~604)）

### 手机（designWidth 360）

- **状态栏**：高 44（时间 Body 13 + signal/wifi/电池图标 14）——系统状态栏，无需自绘，仅参考
- **左边栏**：**72×736**（图标按钮 48×48 圆角 RADIUS_NAV，间距 10；头像 34×34）
- **⚠️ 手机左边栏支持大拇指左右滑动隐藏/呼出**（屏幕宽度不够，PAD 不需要此交互）
- **信息条**：标题 CardTitle(14) + 统计 Caption(10) 行距 2；**图标式双模式切换**（DAG 图标按钮 32×32 圆角 RADIUS_CONTROL 选中=BRAND_PRIMARY 底 / layers 图标按钮 32×32 =SURFACE_HOVER 底，间距 4）；新建按钮 32×32 圆角 10 BRAND_PRIMARY
- **画布双模式（已拍板 B+C）**：默认 B=垂直图状树（从上往下、卡片+贝塞尔连线、可读性优先）；可切 C=自由画布（fit 全图 + 双指缩放，复用现有画布）

## 六、组件规格

**1. Logo 区**
- 图标容器 36×36 圆角 RADIUS_LOGO(12)，**linearGradient 225°：BRAND_PRIMARY → BRAND_SECONDARY**，gitbranch 图标 20
- 标题 CardTitle + 副标题 Meta，行距 2，图标与文字距 10

**2. 导航项**
- 高 44 宽 208，内边距左右 12，圆角 RADIUS_NAV(12)；图标 18，图标与文字距 10
- 默认态文字 TEXT_SECONDARY；**选中态：BRAND_PRIMARY 整块填充 + 文字纯白**

**3. 账号区（已登录）**
- 头像 36×36 圆形 clip；昵称 CardTitleSm + 说明 Caption 行距 2；右侧 chevron 16
- 容器：内边距 10，圆角 12，底色 SURFACE_SOFT

**4. 账号区（未登录）**
- 图标容器 36×36 圆形，描边 1px STROKE_BRAND，底色 SURFACE_HOVER，user 图标 18
- 文案「登录华为账号」CardTitleSm +「同步知识画布到云端」Caption；容器同已登录

**5. 气泡节点卡片（默认态）**
- **150×68**（★ 0.167.3：200→150），内边距上下 12 左右 14，圆角 RADIUS_NODE(18)，描边 1px STROKE_CARD，底色 SURFACE_NODE
- **图标容器 40×40** 圆角 RADIUS_LOGO(12)，225° 渐变主紫→辅助紫，gitbranch 图标 18
- 标题 14 SemiBold + 信息 11 Regular，行距 3

**6. 气泡节点卡片（悬停态）**
- 底色 → SURFACE_HOVER，描边 → STROKE_BRAND
- **阴影：radius 24 / offsetX 0 / offsetY 10 / 黑 45%**
- 信息行 →「双击进入对话」BRAND_SECONDARY；右侧出现 chevron 16

**7. 连线（矢量真相源：平板稿 Frame_2_664.svg）**
- 颜色 BRAND_PRIMARY **85% 透明度**，宽 2
- **水平 S 型贝塞尔**：父卡片右边缘中点 → 子卡片左边缘中点；控制点 = 端点各向内水平偏移 35（`M x1 y1 C x1+35 y1, x2-35 y2, x2 y2`）
- **箭头**：实心三角 7×8.4，BRAND_PRIMARY 填充，指向子卡片
- 落地用 Canvas 自绘（勿用图标/图片拼线）

**8. 分段控件（平板）/ 图标式切换（手机）**
- 平板：外容器 padding 3 圆角 RADIUS_CONTROL(10) 底色 SEGMENTED_TRACK；选中段 padding 5/12 圆角 8 底色 BRAND_PRIMARY + 文字白 + 自绘 DAG 图标 14；未选中段 layers 图标 14 + TEXT_SECONDARY
- 手机：见「五、布局规格-手机」

**9. 新建气泡按钮（平板）**
- padding 10/16，圆角 10，底色 BRAND_PRIMARY；plus 图标 16 + 文字 CardTitleSm 白，图标文字距 8

**10. 缩放控件**
- 容器 48×132，padding 4，圆角 14，描边 STROKE_CARD，底色 SURFACE_NODE
- **阴影：radius 20 / offsetY 8 / 黑 35%**
- 竖排三按钮 40×40 圆角 10：放大 plus / 缩小 minus / 适应 maximize

**11. 列表滑动操作面板（★ 0.212.2 定稿 / ★ 0.213.0 扩容双钮）**
- **禁满高色块、禁红色大面板**——视觉走「显眼紫+小巧按钮」：**双圆钮并排**，各 44×44 **圆形**（borderRadius 22）品牌紫 BRAND_PRIMARY 底 + 白图标 20，垂直居中（外容器满高 Center，露出区宽 120、钮间距 12）
- **左钮=问AI**（ask_ai.svg 气泡问号，功能=知识卡重新带入对话框问AI）、**右钮=删除**（trash.svg 回收站）——用户定稿"问AI 放删除左边，滑块工具凸显问AI 概念"
- 左滑右滑均滑出（swipeAction start+end 双向挂 **ListItem**，该属性挂 Row 无效）
- 点击均不直接执行——问AI 走面板链路、删除走确认弹窗链路；多选模式下两钮点击均无动作
- 图标语义优先用系统既有华为风格图标（ask_ai/trash 等 media 资产），不自造简陋图形

**11a. 知识库列表卡片标题行——Stack 叠层终式（★ 0.213.2 宽屏定稿，推翻 0.213.0 两列式）**
- **标题轴线=卡片几何正中（50%）**：`Stack({ alignContent: Center })` 叠层——**标题层**自然宽+textAlign Center+maxWidth 60%（Container 被 Stack 居中=恒 50% 轴，与标签数量/列宽完全无关，上下永远一条线）；**标签层**（底层）=Blank 弹性推右 + **38% 定宽列、内容左对齐**（用户"标签在标题右边，左对齐不是居中"）
- 标题层 maxWidth 60% 与标签区（62% 起）零重叠；超长标题在 60% 内省略
- **标题与内容行距=4**（0.213.2 用户拍板"太挤，大一两个像素"，原 2）
- **手机**：标题左对齐 62% 上限 + 标签弹性撑满（左对齐原样）；标题行内不放操作按钮——问AI 等入口全在滑出面板（六-11）
- ⚠️ 教训：0.213.0"标题列弹性居中"的轴线在列中心（约 31%）且随布局漂移——**凡"必须几何居中"的元素一律 Stack Center，勿用弹性列 textAlign 近似**

**12. 确认类对话框（删除确认等）——宽高比定稿（★ 0.212.2）**
- 宽度：**手机 86% / 平板与 PC 固定 400**（比编辑弹窗 520 窄一档；百分比宽度在宽屏会把双按钮拉成面条——0.212.2 用户实锤）
- 结构：标题 16/600 → 勾选行（checkbox svg 20 + 13 说明字）→ 双按钮行（取消=透明底 TEXT_SECONDARY / 确认=DANGER 底 TEXT_PRIMARY，layoutWeight 等分，间距 12）
- 内边距 20，圆角 RADIUS_NAV，底色 SURFACE_NODE，遮罩 OVERLAY

## 七、图标资源

`PixsoUI/*/arkui/entry/src/main/resources/base/media/` 下 svg 可直接拷入工程 media/（描边风格 1.5px）：

| 图标 | 用途 | 颜色 |
|------|------|------|
| gitbranch.svg（+0~8 变体） | DAG 分支 / Logo | 白 100% |
| bookopen.svg | 单词库 | 白 65% |
| library.svg | 知识库 | 白 65% |
| settings.svg | 设置 | 白 65% |
| layers.svg | 选项卡/自由画布模式 | 白 65% |
| plus.svg / plus0.svg / minus.svg / maximize.svg | 新建/缩放 | 白 |
| chevronright.svg | 进入指示 | 白 40% |
| user.svg | 未登录账号 | 辅助紫 #A78BFA |
| signal.svg / wifi.svg / Vector_2_23x.svg | 手机状态栏 | 白 |

注意：svg 颜色写死在文件内，需换色的同形图标另存版本。分段控件/模式切换里的 DAG 图标为**自绘 Path**（非 svg）。

## 八、不一致裁决记录（已定案）

| # | 项 | 冲突值 | 裁决 |
|---|------|------|------|
| 1 | 节点卡片内边距 | 12（状态页）/ 14（图例）/ 上下12左右14（平板二稿） | **以平板二稿为准：上下 12 左右 14** |
| 2 | 节点图标容器 | 36（状态页）/ 40（平板二稿） | **以平板二稿为准：40×40** |
| 3 | 画布标题字号 | 16（代码+图例）/ 18（截图） | **16** |
| 4 | 手机画布标题 | ScreenTitle 16（平板）/ CardTitle 14（手机稿） | **手机用 14**（手机整体缩小，合理） |

## 九、落地规则

1. **DesignTokens.ets 单一来源**：色/圆角/文字样式/间距全部落常量；替换全项目散落的 isDark 三元色值（v0.166.3 后亮色分支已是死代码，收敛时一并删除）
2. **Pixso 导出代码不可直接编译进工程**（文案写死、toPx 缩放、零交互零数据绑定）——正确用法 = 提取参数（本文档）+ 手写移植，保留现有拖拽/双击/长按交互与 ChatModel 绑定
3. **手机端 B+C 双模式**：B 垂直图状树（默认）/ C 自由画布（现有画布 fit+缩放）；切换控件参考手机稿信息条图标式切换
4. **手机左边栏滑动隐藏**：大拇指左右滑动隐藏/呼出，PAD 不做
5. 账号区接入现有华为账号登录态（Account Kit），头像用真实头像
6. 改动较大时按「先 canvas → 侧边栏工作台 → 手机端」顺序推进

## 十、导航栏与图标统一规范（★ 0.195.0 用户定稿——跨页 100% 一致，不允许一页一风格）

### 10.1 顶栏（导航栏）规格——所有页面强制统一

| 项 | 规格值 | 说明 |
|----|--------|------|
| 上下留白 | **8 / 8（对称）** | 以气泡树信息条为基准（0.195.0 用户拍板：顶栏左/上间距以气泡树页为准）；原 6/6 已废 |
| 左右留白 | **left 大屏 28 / 小屏 14，right 14** | 对齐画布信息条 `viewW≥520 ? 28 : 14` 双分支（Pad 实测：信息条标题 590px，对话页原 540px 差 20vp 已对齐）；对话页/单词库/知识库三页同步 |
| **Row 高度机制（0.196.7 用户拍板：以气泡树页为逐像素基准）** | **顶栏 Row 显式 `.height(56)` 固定高**（= 8padding + 40内容 + 8padding，四主页面统一），➕ 按钮显式 `.height(40)`，标题列在 Row 内**垂直居中**，顶栏总高 56vp；气泡树页为**外层等效结构**：外层 Column padding 8/8 + 内层 Row `.height(40)`（无 padding）——两者 frame 等效（y88-228 ≈ 树页 88-227，Pad 实测） | 0.196.6 原 `.height(40)` + padding 8/8 → ArkUI height 含 padding，把内容区压到 24vp，icon 包裹行 40vp 溢出居中，顶栏整体比树页高 8vp（icons 中心 y137 vs 树页 ➕ y157）；任何新页顶栏 Row 必须显式 `.height(56)`，禁止依赖隐式撑高 |
| **标题列结构** | `Column({ space: 2 }) { 标题, 统计行 }`——标题 16/600/Inter-SemiBold/TEXT_PRIMARY + 统计 11/TEXT_SECONDARY/Inter | 列内 space 2 + 内容规格全页一致 → 同高 Row 居中后标题 y 像素级一致 |
| 副标题统计行（可选） | 11px + TEXT_SECONDARY + Inter，标题正下方 | 对话页「N 条对话」/气泡树「N 个气泡 · N 条对话」同款模式（0.196.3：原 TEXT_TERTIARY 一亮一暗已废） |
| **页面背景（0.196.5 用户拍板：叠图颜色统一）** | **四主页面（对话/单词库/知识库/复习）根底色 = BG_CANVAS `#160D26`**（与画布面板同色） | 原各页 BG_APP `#120B1F` 与画布面板有色差（用户 PS 叠图实锤）；首页仍 BG_APP |
| 画布信息条 | **基准本尊**（left 28/14 + 8/8 + right 14 + BG_CANVAS 底板） | 其余页顶栏向它看齐 |

### 10.2 图标尺寸——全项目最多两档，禁止一个大一个小

| 档位 | 尺寸 | 适用 |
|------|------|------|
| **常规档 20×20** | 顶栏 icon（对话页 3 个 / 两库 ⚙ / 画布 ➕）+ 角标悬浮控件（☰ / 放大 / 缩小 / 适应全图） | 所有导航栏与悬浮控件 |
| **小档 18×18** | 行内/列表 icon（边栏导航行、复习区喇叭、音标发音等） | 内容区行内元素 |

- 新建按钮统一 `Button('+')` fontSize 20 透明底白字（单词库/气泡树同款，用户拍板「很显眼很漂亮」）
- **顶栏 icon 横向间距：相邻 icon 边缘间距 8vp**（wrapper padding 4+4、无 margin）——对话页 3 icon 与两库 ⚙↔➕ 同距（0.195.0 实测统一：原对话页 12vp / 单词库 8vp 不一致，用户肉眼抓出）
- svg 描边风格 1.5px 白 65%（见第七章）；新增图标必须落两档之一，违者回退

### 10.3 排序按钮（两库顶栏）

- 高度 **28**（与 ⚙ 图标视觉对齐），fontSize 12，激活态 SURFACE_HOVER 底 + BRAND_SECONDARY 字
- **互斥**：三按钮（最新/需复习/字母）显式 `===` 判等，禁止 `>=` 区间误亮（0.195.0 bug 教训：字母模式 4/5 时需复习按钮跟着亮）
