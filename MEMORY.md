# Project Memory
> 项目基线文档，仅保存架构、定型功能、核心规则、未完成任务；单次调试流水存入docs迭代文档。
> ★ 0.192.0：AI 助手上下文自律与 Prompt 编写军规见 **docs/CONTEXT_MANAGEMENT.md**（project_rule.md §8 强制引用）。

## FACT 项目固定基线
1. DAG气泡树项目架构
   BubbleNode 结构：携带parentID（单父模型），节点内部保存 messages: ChatMessage[]。
   技术栈：鸿蒙 ArkUI V2，结构体使用@ObservedV2，新增字段必须添加@Trace。
   页面与组件：BBTreeCanvas.ets、ChatPage.ets、WordBankPage.ets、KnowledgeBankPage.ets、ReviewPage.ets、GlobalSettingsDialog.ets；ApiClient.ets 负责 AI 流式请求（多提供商）。

2. 已定型核心功能清单
- 气泡树对话、流式API、多模态图片上传、本地持久化(PersistenceV2)
- Markdown渲染，代码块语法高亮，代码块自动换行按钮左对齐
- 图片全屏预览，屏幕圈选截图，图片提炼知识卡片
- 划词翻译、单词库生词复习、知识库卡片管理、知识复习页（ReviewPage，Anki 式单卡）
- TTS语音朗读（本地 CoreSpeechKit 双引擎：中文聆小珊+英文Laura，0.189.0 起替代云端），单词发音单例复用，缩略词播全称
- LaTeX数学公式本地渲染，画布自动排版
- 全局设置弹窗：API提供商化（华为MaaS/火山方舟/DeepSeek 预设+自定义）、AI偏好、云同步、订阅、关于
- 学习统计页（StatisticsStore 按天聚合，只增不减）
- 流式渲染：ForEach Key碰撞修复；role映射修复prompt泄漏
- 生命周期：提炼弹窗180s超时，切后台自动中断请求；页面销毁停止定时器
- 返回键拦截：弹窗打开时，返回键优先关闭弹窗
- 华为账号登录（Account Kit 纯客户端授权，AGC 应用 6917618071300773117）
- 云同步（RDB+cloudSync 快照行模式；与华为账号登录态耦合，同开同关，0.196.8）
- 订阅体系（¥9.9/月+¥99/年 IAP 占位；到期只锁云同步其他可用，0.194.0）
- UI：暗紫主题锁定暗色（方案A）；Pixso 设计稿 canvas 线已落地；四主页面背景 BG_CANVAS

## PENDING 待开发任务
（当前无待开发任务；2.0 学习模块方向见对话记录）

## 版本迭代简表
> 一行结论（版本+一句话+关键教训），不记过程细节（约束#5）；完整记录见 docs/（总索引 docs/index.md，0.165+ 段在 docs/0.165+/）。

|版本|核心能力 / 关键教训|
| ---- | ---- |
|0.1|MVP：气泡对话、火山流式API、图片多模态、本地持久化|
|0.114~0.118|图片预览、输入框自适应、DAG上下文压缩（待开发）|
|0.121~0.124|Markdown、代码块高亮、深色模式、画布自动排版|
|0.132|ForEach Key复用bug修复，流式打字机效果|
|0.136~0.142|TTS语音合成（HTTP路线，0.189.0 起被本地引擎替代），分段播放、死锁修复|
|0.143|PersistenceV2存储迁移，API Key落盘修复|
|0.145|单词库MVP：划词翻译，生词复习|
|0.146|知识库：划词提炼卡片，知识卡复习|
|0.147|画布气泡自定义标题、长按菜单|
|0.151|LaTeX渲染、画布平铺/选项卡双模式（两池数据互通为语义基准）|
|0.152|矩阵渲染、屏幕圈选截图提炼|
|0.153|提炼弹窗超时、错误中文提示、Token统计|
|0.160.x|Prompt泄漏修复；**铁律：ForEach item内visibility/if初始求值必须Visible，None/false移出渲染树后通知永不到达**；API key内置默认（上架前须删）|
|0.161.x|学习数量设置、API Key外置rawfile/config.json；教训：GitHub Push Protection拦截Key→reset --soft重写历史，unblock-secret链接绝对勿点|
|0.162.1|新建分支过渡动画（链式animateTo淡出→切store→淡入440ms防刷屏）|
|0.163.x|代码块按钮icon化、更名DAG AI Chat；教训：bundleName勿动（调试profile绑死包名）|
|0.164.x|华为账号登录跑通；教训：Account Kit须AGC手动Profile+手动签名、受限权限须Profile ACL显式授权、错误码上屏是排查利器|
|0.165.x|云同步双端调测收官；教训：下行写池绝不upsert防回环、AGC入口是「云空间」非云数据库|
|0.166.x|圈注图丢失修复（动画回调清空pendingImages→addBubble加carryImages参数）；平板首页占左栏；主题锁定暗色方案A|
|0.167.x|Pixso canvas落地：UI_GUIDELINES+DesignTokens双真相源、连线Canvas命令式绘制；教训：Path无viewport自动缩放时commands错位（连线飞左上角）|
|0.168.x|画布左侧边栏（平板208常驻/手机抽屉）；教训：overlay不参与hit test、手势中途挂载onClick组件致触摸流重路由（唤出判定移onActionEnd）|
|0.169~0.171|复习区划词悬浮栏（翻译/入知识库/复制）、边栏信息与UI微调、连线高度缩短启动|
|0.172.x|连线缩短（verticalSpacing 113）；气泡卡片加「N条对话·X分钟前」（messageId解析时间戳，零模型改动）|
|0.173.x|气泡拉宽+单击选中态；**教训：单双击并存须只绑count:1手动判定（两次tap<300ms=双击）**|
|0.174.x|首页+设置弹窗UI优化；教训：满屏须Stack包Navigation+expandSafeArea（NavBarContent底部被clip）、SemiBold=数字600+Inter-SemiBold|
|0.175.0|设置三Tab协调（保存右侧加「返回」）；小字行距标准 lineHeight 18；称呼示例「好奇宝宝」|
|0.176.0|信息条返回箭头删除（边栏落地后画布即主页面）|
|0.177.0|IDE分层图标警告修复（icon改指layered_image）；冷启动旧logo闪现修复（startIcon.png漏换）|
|0.178.0|冷启动logo根治：startWindowIcon透明化；信息条标题「气泡树」；桌面短名DAGAI保留|
|0.179.0|首页改版（主按钮「进入气泡树」、拇指区、标题32）；教训：有layoutWeight子元素时justifyContent Center失效，用Blank弹性占位|
|0.180.0|边栏跳转不收抽屉（哪进哪回）；教训：pushPath压栈不销毁源页、跳转前勿主动重置入口UI状态|
|0.181.x|ChatPage按稿收敛（DesignTokens批量套色、圆角/字重对齐）；教训：版本号同步点三处（0.190.6 扩为四处）|
|0.182.x|画布/对话页六项打磨（☰、发送+▾合体、点输入框外收键盘、双击放大等）；**教训：GestureEvent无x/y，取点击位置须用onClick的ClickEvent；交互位移须缓动勿突变**|
|0.183.x|单词库/知识库按稿收敛（isDark清零、DesignTokens全对齐）；**教训：NavDestination自带黑底，页面根容器不设底色即透黑**|
|0.184.0|屏幕标注页双升级（补充要求输入框+暗紫对齐）；教训：addBubble扩carryText随切换回调带入（同carryImages模式）|
|0.185.0|单词库音标口音切换（美式默认/英式，切换确认+清空+双提示词参数化）；**教训：PersistenceV2新字段必须全新key，挂旧key读取为undefined**|
|0.186.0|docs按版本段重组织+AI token优化：分层按需加载（L1总索引/L2段索引/L3详情/L4归档）|
|0.187.0|单词库记忆算法（简化遗忘曲线R=e^(-t/S)，方案B用户拍板）：3档评分/展示即复习/到期闸门防抖/复习缓存按消息ID永久固定；**单位统一存「天」浮点防混用BUG**；详见 docs/0.165+/0.187.0|
|0.188.0|知识库复刻记忆算法+紫色三角图标（BRAND_SECONDARY辅助紫=提示语义）+extractStreamError零内容流诊断（HTTP错误体不再被SSE解析器静默吞掉）|
|0.189.0|本地TTS免费离线（CoreSpeechKit，用户拍板取消云端火山）：双引擎zh聆小珊+en Laura、requestId会话严格限定、单例互斥；文本上限10000字符（500是API11旧限制）|
|0.189.1|口音联动（listVoices运行时查Laura、应用内下载语音包、设置页音频API区整体删除）；**教训：ArkTS严格模式Record字面量被拒，须程序化构建 extra['key']=value**|
|0.189.2|口音提示toast→AlertDialog弹窗化（重要信息用户偏好弹窗）+⚙弹窗三区卡片化|
|0.190.0|API配置提供商化（华为MaaS/火山方舟/DeepSeek 3预设+自定义；ApiConfig provider字段key 'api-config-v2'→'v3'；三家全OpenAI兼容ApiClient零改动）|
|0.190.1|API配置实测七连调（获取Key各跳官网、模型清单官方修正、价格删除）；**教训：@Builder需要随状态变化的渲染必须无参化、内部读@Local（按值传参不刷新）**|
|0.190.2|纯文本模型发图拦截（isKnownTextOnlyModel+AlertDialog）+错误关键词提示；**教训：图标优先用svg资源不用字符（字形基线偏移不居中）**|
|0.190.3|对话气泡加宽 maxWidth 85%→90%|
|0.190.4|GLM-5.3-Flash长回复超时修复：readTimeout 60s→300s（深度思考不可关闭）+requestInStream try-catch兜底+**卡死自愈逻辑必须放guard前**|
|0.190.5|等待态模式提示+WaitingDots三点动画（组件级定时器aboutToAppear启动/aboutToDisappear清理零泄漏）|
|0.190.6|classifyStreamError错误分类9场景（保留原始错误便于定位）+关于Tab（版本号四处同步、反馈邮箱、隐私政策、mailto预填）|
|0.190.7|中回复模式小字精简（仅短/长特殊模式显示提示）|
|0.190.8|隐私政策弹窗自定义化（暗紫设计语言；华为只要求内容合规+应用内便捷入口，不规定UI样式）|
|0.191.0|阅读位置记忆A+B：会话级高度Map（不持久化，A记忆→B书签→底部兜底）+段落书签ChatBookmarkStore（独立key单JSON字段）+多模态高亮|
|0.192.0|学习统计页：StatisticsStore按天聚合只增不减+AI鼓励找亮点+四维柱状图+双入口；**教训：Navigation路由页根组件必须NavDestination+hideTitleBar(true)，直接Column作根=全黑屏**|
|0.193.0|上下文工程五项：摘要结构化SUMMARY_PROMPT/Prompts.ts集中管理/卡片提炼prompt数字锚定/MEMORY瘦身/压缩阈值token化（24000估算token触发线）|
|0.194.0|订阅体系（¥9.9/月+¥99/年IAP占位；到期只锁云同步）：SubscriptionStore+200种子码SHA256哈希白名单离线校验+30天试用（兑码叠加基准含试用期）+兑码前置登录+云同步VIP守卫|
|0.195.0|到期提醒ReminderDialog+UI大统一（顶栏间距以信息条为基准/icon两档20·18/emoji→svg）+大屏常驻边栏AppSideBar共享组件（选中态setInterception动态跟踪）；**教训：hdc装机必须递增versionCode（HAP验尸法：解包modules.abc搜字符串定责）**|
|0.195.1|版本注释瘦身（只留近2版）+协作铁律入档（约束#6先问用户）+缩进修正|
|0.196.0|知识复习开工：previewIntervalDays+评分按钮时间化（灰色描述→复习时间）+固定窄宽96；**教训：用户DevEco开着的旧缓冲区会覆盖AI的文件修改——改代码期间用户勿保存旧文件**|
|0.196.1|ReviewPage上线（Anki式单卡/背完不循环/完成页AI鼓励档位off兜底「鼓励永远要有」/边栏「知识复习」唯一入口）；元服务搁置（沙箱读不到本地词库）→桌面走主应用服务卡片|
|0.196.2|复习以天为单位（用户拍板核心逻辑）：当日队列=到期+新词、ReviewDailyState当日完成落盘再进跳完成页、完成页总结独立卡+WaitingDots、喇叭发音、头像点击=退出确认、三设置弹窗点空白关闭|
|0.196.3|顶栏颜色字体对齐气泡树+待发图片直开查看器bugfix+未登录点头像拉起登录+复习卡喇叭移音标旁+知识卡显示图片+「恭喜你！」标点悬挂|
|0.196.4|WindowMode.ets窗口宽度模式：**分屏/悬浮窗时屏宽不变窗宽变**（isTablet误判根因），Index onAreaChange按窗口实宽写AppStorageV2共享真相源，五页@Computed读|
|0.196.5|顶栏像素级对齐（icons行.height(40)撑高+标题列space:2）+四主页面背景统一BG_CANVAS #160D26|
|0.196.6|顶栏Row高度全页统一.height(40)（气泡页为基准本尊，禁止依赖隐式撑高）|
|0.196.7|顶栏.height(40)→56（**ArkUI .height含padding**，40把内容压到24vp致溢出错位）+适应全图=autoLayout()+fitViewport()（重排填补空洞）|
|0.196.8|云同步↔登录态耦合同开同关（用户拍板）：CloudSyncStore应用级开关（key 'cloud-sync-switch'）+登录后询问+退出强制关+设置页未登录toast拦截|
|0.196.9|取消登录静默（AUTH_CANCELLED_TIP对1001502012固定短提示）+AppConfirmDialog通用暗紫确认弹窗+ConfirmDialogStore（**挂载点唯一=Index根Stack顶层**）|
|0.196.10|云同步状态圈勾图标（纯状态指示不可点）+未登录点开启→登录引导弹窗（confirmOnLeft确认钮放左）+状态卡@Computed响应式实时刷新|
|0.196.11|云同步入口登录分流：入口即意图（fromSyncEntry=true登录成功直接开同步，不再弹询问）|
|0.196.12|代码优化轮：删isCloudSyncOn死代码/设置页开启按钮两分支去重/BillingPage showToastSafe收口|
|0.197.0|复习卡面两修：**英文展示词自适应缩字号（minFontSize16/maxLines3，用户拍板截断绝对不允许）**+卡片组padding bottom 32|
|0.197.1|评分按钮内部留白padding top/bottom 12（文字离框边）|
|0.197.2|全局设置复习Tab保存按钮：编辑副本+保存统一落store+脏检查纳入hasUnsavedChanges|
|0.197.3|保存/返回按钮等宽修复：**间隙一律用Row({space:12})禁止挂单侧margin**（margin参与layoutWeight分配挤窄按钮）|
|0.198.0|复习完成页删副标题「今天的复习任务已经完成」（下方AI鼓励已表达同义）|
|0.198.1|评分按钮手机溢出首修（**真机翻车**）：固定 .width(96)×3+间距=300vp 超手机气泡内容区→改 layoutWeight(1)+maxWidth 96 钳制，实测反而更溢出——**ArkUI 平台坑：layoutWeight 与 constraintSize 组合测量不可靠（constraintSize 使按钮退出权重精确分配、被内容撑开），此组合禁用**|
|0.198.2|评分按钮二修（**在 Scroll 内无效**）：.width('30%')+maxWidth 96——百分比本身没错，但 ratingArea 在横向 Scroll 内，**Scroll 给子组件宽度约束无上限，百分比/layoutWeight/100% 全部失效**回退内容自适应（96 钳制恒 300vp），真机依旧溢出|
|0.198.3|评分区溢出**真根因修复**（用户三次实测反馈逼出）：ratingArea 在 ForEach 的横向 Scroll（scrollable Horizontal）内部是溢出真因——评分区移出 Scroll 放 ForEach item 的 Scroll 之后（4 处同构：气泡生词区/气泡知识卡区/编辑弹窗两区），恢复气泡内容区约束后 '30%'+maxWidth 96 生效（手机自动缩窄/平板钳 96 窄胶囊）；**铁律：横向 Scroll 子组件内禁止依赖 width 百分比与 layoutWeight 做自适应布局——约束无上限全失效，需自适应的组件必须放 Scroll 外**|
|0.198.4|评分按钮宽度固定 96|
|0.198.5|评分按钮 layoutWeight 均分对齐词卡右缘+maxWidth96 兜底（density3.0 实锤：屏幕 376vp，气泡内容区 289.7vp，300vp 五轮溢出总根源）|
|0.199.0|上下文压缩升级（用户拍板双需求）：①**触发线 TOKEN_TRIGGER 24000→48000**（≈3.2 万字、~100 轮对话才压缩；flash 输入 1M≈1 元上调无感+模型 128K 窗口余量足；保留预算 8000 不变）②**等待态新增阶段 3「整理历史记忆中」**（摘要生成是一次完整 LLM 调用 5~15s，此前该期间误显示"已提交请求"而请求实际未发出——buildBranchMessageList 摘要 try/finally 置 phase=3→恢复 1，waitingView 四元分支，文案无省略号遵循 0.191.0 定稿）；**决策依据：压缩是质量策略非省钱妥协（Lost in the Middle 中部衰减+摘要=蒸馏信噪比更高），消费端不暴露上下文档位是行业共识（ChatGPT/Claude 只给开关不给档位）**|
|0.200.2|导入动画调参（用户实测 0.200.1「还不错但没惊艳到」三指示）：①**弹跳峰值 1.14→2.8**（用户原话「都做动画了索性夸张一点，放大 3 倍」——translate 补偿公式自动适配）②**整体放慢 ~3 倍**（飞行 520→1400ms/弹跳 460→1050ms/导航等待 300→750ms——用户「嗖一下没感觉」）③**飞行卡片 120×48→200×84+字号15**+终点缩放 0.3→0.5（用户「像一粒东西看不清内容」）+光晕 ×22→×60 同步夸张；**动画调参方法论：时长/幅度/可读性三轴独立调**|
|0.200.1|导入动画重做（用户实测 0.200.0 动画翻车「不想用语言解释」——三大根因全修）：①**弹跳锚点左上=向右下窜**→scale 锚点保持左上（0.167.4 缩放语义不动）+**负 translate 数学补偿**（bounceTx/bounceTy，中心原地弹跳）②**发光/弹跳瞬切无过渡**→importGlow 连续值 0~1 渐变（border 宽 1+glow/shadow radius 12+glow×22 数值插值）+keyframeAnimateTo 四段回弹 1→1.14→0.98→1 ③**直线匀速飞行无质感**→keyframe 三段弧线（中点抬高 60 抛物线）+微旋转 -6°→4°→0°+缩放 1→0.7→0.3；另：变暗 0.55→0.4（原太重）、横幅顶部滑入/确认条底部滑入（TransitionEffect）、导航等待 430→300ms（回弹峰值即交棒）；**教训：ArkUI scale 锚点与 position 语义强耦合（c2s 坐标换算假设锚点左上），动画改锚点=破坏缩放交互——用 translate 补偿替代改锚点；keyframeAnimateTo 全局名 ArkTS 不可见，须 UIContext 实例+（param,keyframes）双参数签名**|
|0.200.0|知识卡片导入气泡对话（灵魂功能·业务闭环：卡片→提问，用户拍板三入口+L3 特效全量；docs/0.165+/0.200.0 文档）：①**三入口**——知识库列表「问 AI」icon（用户强理由：浏览即产生问题，点进去才能问不可接受）+编辑弹窗双按钮（传编辑器当前字段，未保存也能导）+复习页知识卡右上 icon（Stack TopEnd 不占版面），均弹二选一「导入气泡对话/创建子气泡」②**画布选择模式**——CardImportStore（AppStorageV2）+navBackToCanvas 四态回画布；变暗层 hitTestBehavior None 穿透（拖拽缩放保留）；单击=锁定（复用 selectedNodeId 高亮+信息行换「导入目标」）+底部确认条（✓导入/重选/点空白解锁）；横幅取消/返回键清 store 零残留③**L3 动画链**——飞行卡片（横幅位→气泡中心，与气泡同层画布坐标系零��算，450ms 缩至 0.25）→气泡弹跳 1.15+紫光晕（isImportGlow）→进对话输入区渐显 300ms④**落地复用圈注 0.184.0 全套**（import 填 inputText/pendingImages；branch 走 addBubble carryText/carryImages+isLoading 降级 toast）；文字格式「📚 知识卡片｜标题+定义+（我想问：）」**不自动发送**；**教训：①@Builder 内 if/else 块后禁止直接链属性（须先闭合容器再链）②svg 资源名=文件名，连字符禁用（ask-ai.svg→ask_ai.svg）③ArkUI 点击不冒泡=按钮自身消费，无需 stopPropagation④uitest uiInput 注入对 Button 组件不响应（存量按钮同样点不动）=设备自动化环境限制，容器 onClick 可注入**|

## 版本号体系（2026-10-03 起）
- 首页显示版本号，每次改动编译装机递增末位；当前 **v0.200.1（versionCode 1000100）**；★ 0.190.6 起版本号**四处同步**（app.json5 versionCode / Index.ets Text / GlobalSettingsDialog APP_VERSION 常量 / MEMORY.md）；★ 0.195.0 起装机**必须递增 versionCode**
- 迭代文档命名：版本号 变更内容.md（同功能迭代末位+0.1，验收后新需求次位+1，用户可直接指定版本号；详见 project_rule.md §7）
- 版本线主文档：docs/0.165+/0.167.md（历史段 0.140-0.152/、0.160-0.164/ 归档，docs/index.md 为总索引）
- 真机测试设备：MatePad 11.5 S 活力版（平板，192.168.2.16 无线调试，装机测试用）+ 畅享 90 Pro Max（手机，192.168.2.9，用户日常自用勿占用）；★ 实测教训：两台 IP 勿搞反（搞反白折腾一轮），`param get const.product.model` 可验身份

## 全局硬性约束
1. 代码清理规则：全部删除console/hilog调试打印；注释掉的大块死代码直接删除。
2. 开发流程：新增功能优先在docs新建md文档，确认方案后再写代码；全局重构/代码清理新开对话。
3. 网络请求：SSE流式请求支持Abort中断；对话不限制180s超时，仅提炼弹窗180s超时。
4. UI 开发以根目录 **UI_GUIDELINES.md** 为唯一设计真相源（色值/圆角/文字/间距/组件规格），禁止页面代码散落写色值；DesignTokens.ets 为 token 单一来源；大纲未覆盖场景按同组件规格类推，落地后回填。
5. MEMORY.md 记录从简（2026-10-04 拍板）：已完成的改动只记一行结论（版本+一句话+关键教训），不记过程细节；仅两类保留完整记录——①未解决的 bug（排查链）②迭代 3 次以上的功能（定案前决策链）。
6. **遇到问题第一时间问用户（2026-10-06 拍板，最高优先级）**：设备连不上/IP 变了/任何异常或不确定——**先问用户再动手**，禁止盲排查烧 token；设备 IP 会经常变，连不上≠设备没了。
7. 版本注释瘦身（2026-10-06 拍板）：app.json5 / Index.ets 的版本历史注释**只保留最近 2 个版本**，更早历史一律指向 MEMORY.md 版本表（唯一真相源），禁止逐版本无限追加注释墙。
