# Project Memory
> 项目基线文档，仅保存架构、定型功能、核心规则、未完成任务；单次调试流水存入docs迭代文档。

## FACT 项目固定基线
1. DAG气泡树项目架构
   BubbleNode 结构：携带parentID，节点内部保存 messages: ChatMessage[]。
   技术栈：鸿蒙 ArkUI V2，结构体使用@ObservedV2，新增字段必须添加@Trace。
   页面与组件清单：BBTreeCanvas.ets、ChatPage.ets、WordBankPage.ets、KnowledgeBankPage.ets、GlobalSettingsDialog.ets，ApiClient.ets 负责火山方舟API请求。

2. 已定型核心功能清单
- 气泡树对话、火山方舟流式API、多模态图片上传、本地持久化(PersistenceV2)
- Markdown渲染，代码块语法高亮，代码块自动换行按钮左对齐
- 图片全屏预览，屏幕圈选截图，图片提炼知识卡片
- 划词翻译、单词库生词复习、知识库卡片管理
- TTS语音朗读，单词发音单例复用
- LaTeX数学公式本地渲染，画布自动排版；修复画布手势PanGesture拦截按钮点击问题
- 全局设置弹窗：API Key、Endpoint、模型选择；支持 DeepSeek / GLM / Doubao Seed 模型切换
- 流式渲染：修复ForEach Key碰撞导致AI回复无法刷新bug；role映射修复prompt泄漏问题
- 生命周期：提炼弹窗180s超时，切后台自动中断请求；页面销毁停止定时器，防止内存泄漏
- 返回键拦截：弹窗打开时，返回键优先关闭弹窗
- 华为账号登录（Account Kit 纯客户端授权：昵称/unionID/openID，PersistenceV2 持久化，AGC 应用 6917618071300773117）
- 云同步（端云数据同步 RDB+cloudSync 快照行模式：设置页「云同步」Tab 授权入口 + autoSync 上云 + dataChange 订阅下行刷新重建工作区，2026-10-03 双端调测通过）

## PENDING 待开发任务
### 任务1：DAG链路回溯与10+15摘要滑动窗口上下文压缩
需求：从当前BubbleNode沿parentID回溯到根节点收集单分支消息，分支之间相互隔离。
压缩规则：消息总数＞25触发压缩；取最早10条生成LLM摘要，摘要作为system消息放头部，保留最近15条原始消息；≤25条不压缩。
BubbleNode新增historySummary字段（@Trace）保存摘要，子气泡继承父分支摘要。
修改文件：ChatModel.ets、ChatPage.ets
状态：pending

（任务2 已完成：0.165 云同步 2026-10-03 双端调测成功收官，功能进上方 FACT 清单；完整记录见 docs/0.165.md 与版本简表 0.165.x 行）

## 版本迭代简表
|版本|核心能力|
| ---- | ---- |
|0.1|MVP：气泡对话、火山流式API、图片多模态、本地持久化|
|0.114~0.118|图片预览、输入框自适应、DAG上下文压缩（待开发）|
|0.121~0.124|Markdown、代码块高亮、深色模式、画布自动排版|
|0.132|修复ForEach Key复用bug，流式打字机效果|
|0.136~0.142|TTS语音合成，分段播放、死锁修复|
|0.143|PersistenceV2存储迁移，修复API Key落盘问题|
|0.145|单词库MVP：划词翻译，生词复习|
|0.146|知识库：划词提炼卡片，知识卡复习|
|0.147|画布气泡自定义标题、长按菜单|
|0.151|LaTeX渲染、画布平铺/选项卡双模式|
|0.152|矩阵渲染、屏幕圈选截图提炼|
|0.153|提炼弹窗超时控制、错误中文提示、AI回复秒表+Token统计|
|0.160|Prompt泄漏修复，ForEach Key碰撞bug修复，知识库/单词库UI优化|
|0.160.1|秒表修复（**ArkUI V2铁律：ForEach item内visibility/if初始求值必须Visible，None/false组件移出渲染树后通知永不到达**）+API key内置默认（上架前须删）+模型精简DeepSeek/GLM；主文档docs/0.160.md|
|0.161.x|学习数量设置（单词库/知识库⚙弹窗1/2/3/自由输入，PersistenceV2独立key）+API Key外置rawfile/config.json（.gitignore不入库）+推送修复（GitHub Push Protection拦截Key→git reset --soft合并重写历史；**本机git不支持--noedit须用-m；GitHub unblock-secret链接绝对勿点**）；主文档docs/0.161.md|
|0.162.1|新建分支过渡动画（同页切store刷屏过快→链式animateTo淡出140ms→onFinish切气泡→淡入300ms，总440ms）；主文档docs/0.162.md|
|0.163.x|代码块按钮纯icon化+App显示名DAG AI Chat/桌面短名AI Chat（**桌面名=module.json5 ability label，设置名=app.json5 label**）+图标换用户logo；**教训：bundleName勿动**（调试profile绑死包名，0.163.3改包名致SignHap失败回退）；主文档docs/0.163.md|
|0.164.x|华为账号登录完整跑通（0.164.1开发→0.164.2~.6六轮排查1001502003→0.164.7删误加READ_PASTEBOARD解决9568289装机失败→**装机登录成功收官**）；核心教训：①**DevEco自动签名=内部「调试应用」通道无有效Client ID**，Account Kit登录必须AGC手动申请调试Profile+手动签名（**只换Profile不换证书**：build-profile.json5改profile路径即可，证书/密码全不动）②**受限权限须Profile的ACL显式授权**，申请了没用的直接删（写剪贴板setData无需权限，读才需要）③错误码上屏（code+服务端原始msg）是排查利器；主文档docs/0.164.md（含完整错误码速查表+签名排查全记录）|
|0.165.x|云同步（端云数据同步 RDB+cloudSync，快照行模式不拆节点表）：v0.165.1 基础设施（CloudSyncUtil 建库建表+持久化点桥接 fire-and-forget+权限链路）；v0.165.2 激活链路（设置页第 4 Tab「云同步」授权入口+SUBSCRIBE_TYPE_CLOUD 订阅+下行写回池重建工作区）；**踩坑①新 SDK 移除 abilityAccessCtrl.PermissionRequestResult 类型名→async/await+类型推断；②循环依赖防护=CloudSyncUtil 回调注入（registerCloudDataHandler），ChatModel 注册处理器；③下行写池绝不 upsert 防回环，值比较挡本机回声；④用户把云侧配到「云数据库(for Object)」配错产品——正确入口是「云空间」服务；⑤AGC 新界面「数据类型名称」不允许下划线→填驼峰 cloudData，「高级设置→本地表名称」填 cloud_data 承接映射（云端类型名可≠本地表名，端侧代码不用改），「高级设置」无加密勾选框、类型下拉无 Encrypted String 就保持 String，主键勾端侧去重 key**；**2026-10-03 双端同步调测成功收官**（收官清理：删零调用 triggerCloudSync/isCloudSyncActive、queryCloudData 降内部函数、删调试打印，BUILD SUCCESSFUL 0 新增警告；遗留 v0.165.3 待定=同步状态提示+云空间开关引导）；主文档docs/0.165.md|
|0.166.x|圈注「创建子气泡」标注图丢失修复（v0.166.1）：**根因=0.162.1 分支过渡动画把 pendingImages 清空挪进 140ms onFinish 回调，consumeAnnotationResult「addBubble 后同步塞图」在 t=0 塞入、t=140ms 被回调清空**（旧注释「内部会清空」是动画改造前的过时认知）；修复=addBubble 加 carryImages 可选参数，图片带入与清空同回调执行（carryImages 覆盖清空，竞态彻底消除），工具栏 ➕ 不传参行为不变；BUILD SUCCESSFUL 11s796ms + 0 新增警告；平板首页残留左栏修复（v0.166.2）：**根因=Index.ets Navigation `.mode(NavigationMode.Auto)` 宽屏自动切分栏——平板上首页一直占左栏、画布只占右栏**（手机窄屏走单栏所以正常）；修复=Auto→Stack 强制单栏，push 后目标页全屏覆盖，平板与手机行为一致（画布全屏空间更大）；BUILD SUCCESSFUL 2s861ms + 0 新增警告；主题固定暗紫·方案A（v0.166.3）：EntryAbility `setColorMode(COLOR_MODE_DARK)` 锁死应用暗色模式 + isDark 恒 true（不读系统 colorMode）+ 删 onConfigurationUpdate（不再响应系统深浅色切换，Configuration 类型从 import 移除）——亮色系统用户也统一暗色配色，系统状态栏/弹窗随 DARK 走暗色风格；全项目 isDark 三元的亮色分支代码保留（未来做双套色可复用）；BUILD SUCCESSFUL 7s968ms + 0 新增警告；**待办：用户 Pixso 暗紫设计稿到位后套 UI——先收敛全项目散落的 isDark 三元色值为统一色表再按稿套色（方案 B/C 已明确不考虑）；设计需求书已出：docs/UI/0.1-主画布工作台-Pixso设计需求书.md（2026-10-03 首版，含可直接发 Pixso 的正式需求书+现状对照分析两部分；修正 7 处：组件库矛盾改「已添加鸿蒙官方组件库优先用官方组件+暗紫覆盖」/产品名统一 DAG AI Chat/「单词本」→「单词库」/手机基准改 360×780 vp/注明锁暗色无需浅色稿/导航补账号区/限定仅设计平铺模式）；**Pixso 初稿已回（2026-10-04，平板/手机/标注 3 图，用户评 82 分）：0.1 修正项全部落实（色板 8 色全对/圆角 4 规格/账号区双态/锁暗色/360×780）；初稿两 bug=平板双父连线（神经网络基础/聚类算法/特征工程双来源入线违反 BubbleNode 单父模型）+手机列表无层级；评审与二轮修复 prompt 已出：docs/UI/0.11-初稿评审与二轮修复需求书.md（修正用户 prompt 三硬伤：①「DAG 规则单父」是概念错误——DAG 图论允许多父，单父是本产品 parentID 数据模型约束 ②「子节点指向父节点」方向反了应为父→子 ③「特征工程第三条独立子节点」歧义→拓扑唯一化 5 条连线；色值漂移 #7C3AED→统一 #7C4DFF；AI 补充问题=手机列表模式应删缩放控件/标注页间距无数值待补/连线是图标字体拼的应换真贝塞尔；文案修正=「+新建节点」→「+新建气泡」/「知识画布」统一（落地时首页「进入对话画布」按钮文案同步改，待用户最终定名）/状态栏 9:41 苹果彩蛋换 10:08）；设计策略已定=两阶段法：阶段1 主画布磨到 95 分定型设计 token（用最强模型）→阶段2 其他页面拿 token 批量出稿（可便宜模型）；**Pixso「状态与规格」页 ArkUI 导出工程已到位（PixsoUI/状态与规格-设计文件/arkui/，2026-10-04），token 全量提取完成：docs/UI/0.12-设计Token提取-状态与规格导出.md——色 13（含标注页未明说的 surface-hover #2C1B4D 悬停底色/stroke-brand 主紫40%描边/surface-soft 白4%柔面）/间距 4 档+组件级 12 项（0.11 要的数值全齐：导航项 gap4/导航区 padding16/卡片 padding12vs图例14 不一致待定/手机列表边距14/缩进20/级）/圆角 4 档/文字 7 样式（ScreenTitle 16 SemiBold——截图标 18 是错的以代码为准）/组件规格 5 类（气泡图标容器=36×36 圆角12 **225° 渐变主紫→辅助紫**；悬停阴影 radius24 offsetY10 黑45%）/图标 svg 5 个可直接复用（gitbranch 气泡logo/bookopen 单词库/user 未登录辅助紫描边/chevronright）；**导出代码定位=不能直接用（写死文案+toPx 缩放适配+无交互无数据绑定），正确用法=提取参数+手写移植**；落地五步计划已定（DesignTokens.ets 收敛散落色值→提取平板/手机布局→重构侧边栏工作台→图标字体拷入→账号区接 Account Kit）；等用户发平板/手机导出文件**（**已到位，2026-10-04 提取完成**：平板稿=侧边栏240/画布容器992×752圆角24/节点卡片200×68图标容器40渐变/分段控件segmented-track白6%/缩放控件48×132/9节点水平树X层级差270；手机稿=左边栏72×736图标式48×48/信息条CardTitle14/双模式图标切换32×32，文件夹树部分按用户指令忽略；**连线矢量真相源Frame_2_664.svg=主紫85%宽2水平S贝塞尔（控制点水平偏移35）+实心三角箭头7×8.4，父卡片右缘中点→子卡片左缘中点**；字体策略=统一Inter中文系统fallback勿打包HarmonyOS Sans SC；截图OCR三瑕疵系VLM误读导出代码文案全对；**UI大纲总则已建立=根目录UI_GUIDELINES.md**（0.12内容+平板/手机参数合并精简，原docs/UI/0.12已删，全局硬性约束新增第4条UI开发必须遵守UI大纲）；手机新交互=左边栏大拇指滑动隐藏PAD不做；UI改造顺序=先canvas→侧边栏工作台→手机端B+C双模式）；0.166 线暂未建主文档（bug 修复线，后续有功能迭代再建 docs/0.166.md）|
|0.167.x|Pixso 设计稿落地套 UI 开线（v0.167.1 canvas 改造第一站，2026-10-04）：①**UI 真相源双文件**=根目录 UI_GUIDELINES.md（项目级大纲总则：色14/圆角5/文字8+字体策略/间距/平板手机布局/组件规格10类/不一致裁决4项/落地规则6条；替代 docs/UI/0.12 已删）+ common/DesignTokens.ets（token 单一来源，**禁止页面散落写色值**=全局约束第4条）；②资源：10 svg（gitbranch/bookopen/library/settings/layers/plus/plus0/minus/maximize/chevronright，白色系适配暗底）+3 otf（Inter 三字重）拷入；③字体注册 **三个不同 familyName**（Pixso 导出三份同名注册互相覆盖是瑕疵勿照抄），中文自动 fallback 系统 HarmonyOS Sans SC；**顶层 font.registerFont since18 废弃（编译 WARN）→ UIContext.Font#registerFont**（windowStage.getMainWindowSync().getUIContext().getFont()，@ohos.font.d.ts @useinstead 指定替代）；④BBTreeCanvas 全面改造（902→1066 行）：结构 NavDestination>Column(BG_APP)>Stack(画布容器 margin24/圆角24/BG_CANVAS)>Stack(内容层)；连线 Column rotate 直线→**双 Path 贝塞尔+箭头**（矢量真相源 Frame_2_664.svg：主紫85%宽2/控制点偏移35/实心三角7×8.4；**|dx|≥|dy| 水平S 否则垂直S**——兼容现有纵向树又为水平树铺路）；气泡→**节点卡片 200×68**（图标容器40×40圆角12 225°渐变+标题14 SemiBold+信息11；**选中态=悬停态规格**：SURFACE_HOVER+STROKE_BRAND+阴影，触屏无hover）；新增信息条（←返回+「知识画布」+统计+**分段控件**模式切换+⚙+新建气泡按钮+Tab栏）+右下角缩放控件（zoomBy 画布中心锚点 0.3~2.0）；删两套自绘标题行 161 行；三弹窗换肤（遮罩0.45+SURFACE_NODE底+STROKE_CARD描边+token化，isDark 三元全清）；switchCanvasMode 方法（applyCanvasModeSwitch+消费 needsRelayout）；⑤v0.167.1/versionCode 1000011；BUILD SUCCESSFUL 2s261ms+0 新增警告（registerFont 废弃警告当轮修复）；**遗留：←和⚙暂留信息条（侧边栏工作台落地后移除）→下一站侧边栏工作台→手机端 B+C 双模式；弹窗圆角12无token（大纲无弹窗规格待回填）；真机视觉验证待做**；主文档 docs/0.167.md|

## 版本号体系（2026-10-03 起）
- 首页显示 `v0.167.x`，每次改动编译装机递增末位（0.167.1 → 0.167.2 → ...）
- 版本线主文档：docs/0.167.md（Pixso 设计稿落地套 UI：canvas 改造 → 侧边栏工作台 → 手机端）（历史线：0.165/0.164/0.163/0.162/0.161/0.160.md；0.166 单 bug 修复线未建主文档）
- 真机测试设备：MatePad 11.5 S 活力版（平板，主测试机）+ 畅享 90 Pro Max（手机，云同步多设备测试用）

## 全局硬性约束
1. 代码清理规则：全部删除console/hilog调试打印；注释掉的大块死代码直接删除。
2. 开发流程：新增功能优先在docs新建md文档，确认方案后再写代码；全局重构/代码清理新开对话。
3. 网络请求：SSE流式请求支持Abort中断；对话不限制180s超时，仅提炼弹窗180s超时。
4. UI 开发必须遵守 UI 大纲总则：所有 UI 开发（新页面/改版/UI bug 修复）以根目录 **UI_GUIDELINES.md** 为唯一设计真相源（色值/圆角/文字/间距/组件规格/布局），禁止在页面代码散落写色值；大纲未覆盖场景按同组件规格类推，落地后回填大纲。
