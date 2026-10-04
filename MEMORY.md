# Project Memory
> 项目基线文档，仅保存架构、定型功能、核心规则、未完成任务；单次调试流水存入docs迭代文档。

## FACT 项目固定基线
1. DAG气泡树项目架构
   BubbleNode 结构：携带parentID（单父模型），节点内部保存 messages: ChatMessage[]。
   技术栈：鸿蒙 ArkUI V2，结构体使用@ObservedV2，新增字段必须添加@Trace。
   页面与组件：BBTreeCanvas.ets、ChatPage.ets、WordBankPage.ets、KnowledgeBankPage.ets、GlobalSettingsDialog.ets；ApiClient.ets 负责火山方舟API请求。

2. 已定型核心功能清单
- 气泡树对话、火山方舟流式API、多模态图片上传、本地持久化(PersistenceV2)
- Markdown渲染，代码块语法高亮，代码块自动换行按钮左对齐
- 图片全屏预览，屏幕圈选截图，图片提炼知识卡片
- 划词翻译、单词库生词复习、知识库卡片管理
- TTS语音朗读（HTTP合成路线），单词发音单例复用，缩略词播全称
- LaTeX数学公式本地渲染，画布自动排版
- 全局设置弹窗：API Key、Endpoint、模型选择；支持 DeepSeek / GLM / Doubao Seed 模型切换
- 流式渲染：ForEach Key碰撞修复；role映射修复prompt泄漏
- 生命周期：提炼弹窗180s超时，切后台自动中断请求；页面销毁停止定时器
- 返回键拦截：弹窗打开时，返回键优先关闭弹窗
- 华为账号登录（Account Kit 纯客户端授权，AGC 应用 6917618071300773117）
- 云同步（RDB+cloudSync 快照行模式，2026-10-03 双端调测通过）
- UI：暗紫主题锁定暗色（方案A）；Pixso 设计稿 canvas 线已落地（0.167~0.173）

## PENDING 待开发任务
### 任务1：DAG链路回溯与10+15摘要滑动窗口上下文压缩
需求：从当前BubbleNode沿parentID回溯到根收集单分支消息，分支隔离。
压缩规则：消息总数＞25触发；最早10条生成LLM摘要作system消息放头部，保留最近15条；≤25不压缩。
BubbleNode新增historySummary字段（@Trace），子气泡继承父分支摘要。
修改文件：ChatModel.ets、ChatPage.ets；状态：pending

## 版本迭代简表
> 只留核心能力与关键教训；完整记录见 docs/ 主文档。

|版本|核心能力 / 关键教训|
| ---- | ---- |
|0.1|MVP：气泡对话、火山流式API、图片多模态、本地持久化|
|0.114~0.118|图片预览、输入框自适应、DAG上下文压缩（待开发）|
|0.121~0.124|Markdown、代码块高亮、深色模式、画布自动排版|
|0.132|ForEach Key复用bug修复，流式打字机效果|
|0.136~0.142|TTS语音合成（HTTP路线），分段播放、死锁修复|
|0.143|PersistenceV2存储迁移，API Key落盘修复|
|0.145|单词库MVP：划词翻译，生词复习|
|0.146|知识库：划词提炼卡片，知识卡复习|
|0.147|画布气泡自定义标题、长按菜单|
|0.151|LaTeX渲染、画布平铺/选项卡双模式（两池数据互通为语义基准）|
|0.152|矩阵渲染、屏幕圈选截图提炼|
|0.153|提炼弹窗超时、错误中文提示、Token统计（AI回复秒表已按用户决定删除，提炼弹窗读秒保留）|
|0.160.x|Prompt泄漏修复、ForEach Key碰撞修复；**ArkUI V2铁律：ForEach item内visibility/if初始求值必须Visible，None/false组件移出渲染树后通知永不到达**；API key内置默认（**上架前须删**）；主文档docs/0.160.md|
|0.161.x|学习数量设置、API Key外置rawfile/config.json（.gitignore不入库）；**git教训：GitHub Push Protection拦截Key→git reset --soft重写历史；unblock-secret链接绝对勿点**；主文档docs/0.161.md|
|0.162.1|新建分支过渡动画（链式animateTo淡出→切store→淡入共440ms，防同页切换刷屏）；主文档docs/0.162.md|
|0.163.x|代码块按钮icon化、App更名DAG AI Chat、用户logo图标；**教训：bundleName勿动**（调试profile绑死包名，改包名致SignHap失败）；主文档docs/0.163.md|
|0.164.x|华为账号登录跑通；**核心教训：①DevEco自动签名=内部调试通道无有效Client ID，Account Kit登录须AGC手动申请调试Profile+手动签名（只换Profile不换证书）②受限权限须Profile ACL显式授权，没用的直接删③错误码上屏（code+服务端msg）是排查利器**；主文档docs/0.164.md（含错误码速查表）|
|0.165.x|云同步双端调测收官；**踩坑：新SDK删PermissionRequestResult类型名→类型推断；循环依赖用回调注入；下行写池绝不upsert防回环；AGC正确入口是「云空间」（勿配成云数据库for Object）；云端类型名驼峰cloudData/本地表cloud_data可不同名**；遗留v0.165.3=同步状态提示+云空间开关引导；主文档docs/0.165.md|
|0.166.x|圈注标注图丢失修复（**根因：0.162.1动画把清空pendingImages挪进140ms回调，同步塞图被回调清空；修复：addBubble加carryImages参数，塞图与清空同回调执行**）；平板首页占左栏修复（**Navigation Auto宽屏自动分栏→Stack强制单栏**）；主题锁定暗色方案A（setColorMode(DARK)+isDark恒true+删onConfigurationUpdate，亮色分支代码保留勿删）；Pixso设计稿交付后转入0.167线落地|
|0.167.x|Pixso 设计稿 canvas 落地（v0.167.1~8）：UI_GUIDELINES.md+DesignTokens.ets 双真相源、信息条/节点卡片/缩放控件/弹窗换肤、连线 Canvas 命令式绘制、子树占位法防重叠、整体等比缩放+限幅方向感知（修复缩放锁死）、小屏顶栏极简 4 图标、topSafe 排除底板；**教训：①Path 无 viewport 属性自动缩放 commands 是连线飞左上角真根因 ②topSafe 与信息条 padding 联动，改底板必须同步重算**；遗留：缩放放大恢复路径待补验（缩小已验）；主文档 docs/0.167.md|
|0.168.x|画布页左侧边栏落地：平板 208 常驻 / 手机 72 抽屉默认隐藏（v0.168.4 拍板：☰ 按钮唤出、删边缘右滑热区）；⚙ 移边栏底部；导航「哪进哪回」；双真机验证全通过；**平台坑（真机实证）：①ArkUI overlay 层不参与 hit test，浮层手势须用 Stack 子节点承载 ②系统手势区占左缘 0~65px，快滑=返回、慢拖被吞不透传 ③手势中途挂载带 onClick 新组件致触摸流重路由、抬手即触发其 onClick（抽屉自关根因，修复=唤出判定移 onActionEnd）**|
|0.169~0.171|复习区划词悬浮栏（翻译/入知识库/复制三项版）、边栏信息与 UI 微调、连线高度缩短启动|
|0.172.x|连线高度缩短（verticalSpacing 160→136→113，层间距公式 113×s）；气泡卡片加「N 条对话 · X分钟前」最近消息时间（**方案：从最后一条消息 messageId（msg_${Date.now()}_xxx）解析时间戳，零模型改动、旧数据天然支持**）|
|0.173.x|气泡拉宽 NODE_W 150→170 完整显示时间；单击气泡选中态（getFocusNodeId 焦点语义：selectedNodeId 优先、回落 current，复用进入后返回样式）；边栏副标题改「你的AI学习伴侣」+删「工作区」标签；**核心教训：ArkUI TapGesture(count:1) 与 count:2 并列绑定时单击抢先阻断双击（手势仲裁），单双击并存须只绑 count:1 手动判定（同目标两次 tap <300ms=双击、执行后 return 不记录本次 tap），参考 BBTreeCanvas v0.173.2**；用户实测全部通过收官|
|0.174.x|首页+全局设置弹窗 UI 优化（弹窗 Tab 分段控件、isDark 三元全收敛 token、标题 600+SemiBold、保存/开启云同步主紫按钮、Toggle、面板 SURFACE_NODE+描边）；删首页「图结构对话 · 多分支推理」文案；**满屏教训：Navigation NavBarContent 底部 420px 是 toolbar 预留且被 clip 裁剪，页面组件背景无法突破——Stack 包 Navigation 做全局背景层+expandSafeArea 一层铺满全屏（顺带消除全 app 手势条黑区）；setWindowBackgroundColor 手机端不可用（编译警告属实、运行时静默失败勿用）**；新建 media/user.svg；FontWeight.SemiBold 枚举不存在→数字 600+fontFamily 切 Inter-SemiBold；真机像素采样实证全通过|
|0.175.0|设置弹窗三 Tab 统一协调——①保存右侧加「返回」按钮（次级样式 SURFACE_SOFT/TEXT_SECONDARY、走 requestClose 未保存确认；云同步 Tab 补全宽返回、三 Tab 底部不空）②**小字行间距以云同步 Tab 为标准入 UI_GUIDELINES 四章（字号 11/副标题距 2/提示条目距 4/连续多行提示 lineHeight 18——乱源=多行长文本默认行高挤，云同步条目单行无此问题）**③称呼示例「大明」→「好奇宝宝」|
|0.176.0|画布页信息条左上角返回箭头「←」删除（用户拍板，全设备尺寸——信息条全设备共用一处、仅 padding 分档，删一处即全删；侧边栏工作台 0.168 落地后画布即主页面，原 pop() 回 Index 入口已由边栏导航承担；pathStack 仍有 pushPath 引用保留）|
|0.177.0|两修：①IDE 警告「请使用分层图标」——app.json5 icon 从 $media:app_logo 改指 $media:layered_image（AppScope 分层图标配置 background=新 logo 深紫版+foreground 透明；app_logo.png 与 background.png 本就同图 121489 字节，桌面图标视觉零变化；app_logo.png 保留未删）②**冷启动旧 logo 闪现 0.1s——根因=startWindowIcon 引用的 startIcon.png 仍是 0.163 旧 DAG 气泡 logo（0.174.4 换新 logo 时只换了 app_logo+两处 background 三资源位、漏了 startIcon），用 background.png 同图替换（字节级一致）**；装机 pad（192.168.2.16:33685）冷启动实证 v0.177.0 首页正常|
|0.178.0|两改一确认：①**冷启动 logo 闪现根治——0.177.0「换新 logo」方向错误被用户否决（「绝对不允许」闪任何 logo），正解=startWindowIcon 透明化（startIcon.png 换 108×108 全透明 png、GDI+ 生成 175 字节 alpha=0 已验证，冷启动只显示背景色不闪任何图形）+ start_window_background base/dark 两处 #FFFFFF/#000000→#120B1F（=BG_APP 应用底色，启动页与首页无缝；启动页在应用进程前由系统按系统深浅色选资源、两处都改保证任何模式暗紫）**②画布页信息条标题「知识画布」→「气泡树」（用户拍板）③桌面短名 DAGAI 用户确认保留不动；装机 pad 杀进程冷启动实证 v0.178.0 首页正常+画布页「气泡树」标题显示|

## 版本号体系（2026-10-03 起）
- 首页显示版本号，每次改动编译装机递增末位；当前 **v0.178.0（versionCode 1000040）**
- 版本线主文档：docs/0.167.md（历史线仅存 0.165.md，0.160~0.164 已清理）
- 真机测试设备：MatePad 11.5 S 活力版（平板，192.168.2.16 无线调试，2026-10-04 端口 33685）+ 畅享 90 Pro Max（手机，192.168.2.9 无线调试）；**2026-10-04 用户指示：装机测试用 pad，手机用户日常自用勿占用**

## 全局硬性约束
1. 代码清理规则：全部删除console/hilog调试打印；注释掉的大块死代码直接删除。
2. 开发流程：新增功能优先在docs新建md文档，确认方案后再写代码；全局重构/代码清理新开对话。
3. 网络请求：SSE流式请求支持Abort中断；对话不限制180s超时，仅提炼弹窗180s超时。
4. UI 开发以根目录 **UI_GUIDELINES.md** 为唯一设计真相源（色值/圆角/文字/间距/组件规格/布局），禁止在页面代码散落写色值；DesignTokens.ets 为 token 单一来源；大纲未覆盖场景按同组件规格类推，落地后回填。
5. MEMORY.md 记录从简（2026-10-04 拍板）：已完成的改动/功能只记一行结论（版本+一句话+关键教训），不记过程细节；仅两类保留完整记录——①未解决的 bug（排查链：根因/已排除假设/当前状态，解决后立即压缩为一行）②迭代 3 次以上的功能（定案前保留决策链）。原因：memory 是给 AI 看的，已做好的功能知道就行，只有未解决的问题才需要细节供 AI 续接。
