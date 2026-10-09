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
**知识复习「永远有卡可学」重构（0.200.1 讨论稿已建，交 GLM 5.3 讨论方案后实施）**：
- Bug 根因已定位（未解决，约束#5① 保留完整记录）：ReviewPage.buildQueue 的 isDoneToday 一刀切——当日背完过一轮（knowledgeDate 落盘今天）后，**再新增的未学习卡被直接拍进完成页**（不进队列）→「都不学习了」；且完成页 hasFutureContent 只认已评分未来卡（新卡 reviewCount=0 不算）→「继续复习」按钮也不显示。pad 有按钮=pad 卡有未来排期。**真机铁证**：手机完成页 UI 树无「继续复习」节点（非挤出，是未渲染）
- 用户业务铁律：未学习卡当日点复习必须出现；永远不可能没有卡可复习（按钮不隐藏）；继续复习=提前学未来卡+顺延系数大幅下降；当日队列 3+1 穿插（3 到期+1 新卡）；知识库空库→直接弹新建卡片引导
- 全部上下文+代码地图+参数表+开放问题：**docs/0.165+/0.200.1.md**（GLM 5.3 讨论稿）
- 实施版本号待定（讨论后定）；验收清单见文档第五节

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
|0.202.0|艾宾浩斯2.0一阶段（用户拍板四件套直做；方案讨论见 docs/0.165+/0.200.1.md）：①**提前背两层惩罚**——good/easy 强度增长按「实际间隔/应有间隔」打折（下限15%，"大幅下降"）+提前背排期保底=原排期+1天（"永远滚明天"数学上不可能）；hard 全额缩短不折；到期背零回归②**标签+注意力加权**——KnowledgeCard.tags 字段（逗号分隔+normalize兜底）+编辑弹窗标签输入+列表#标签行；AttentionStore（'attention-v1'，热度×0.5/天衰减）——sendMessage 时本地子串匹配卡标题/标签→命中卡全部标签+1（问"幺半群"→抽象代数域点亮）；pickReviewCards 三段内命中且S<30的卡排最前（很熟的卡不打扰）③**每日复习量⚙**——复习页右上角设置弹窗（单词库/知识库 10默认/20/自定义1~500，卡片化样式，DailyReviewCountStore 'daily-review-count-v1'）+buildQueue slice；全局设置Tab改名「复习」→「复习区」（语义分开防混淆）④**继续复习bug修复**（铁律1/2/5）——isDoneToday 一刀切删除（队列有卡永远开背，新卡当日必学）；继续复习按钮库非空常驻；future空兜底重拉当日队列+toast；空库「去建卡」引导（跳两库）；**教训：双AI并行开发撞版本号——Flash 同期占 0.201.x，我的功能改定 0.202.0+代码注释批量替换统一（先查最新版本号再定版）**|
|0.201.4|问AI面板文案精简（用户拍板「两句是废话」）：删「把这张卡片导入气泡去问AI?」标题+卡片名回显——从入口进来意图已明确，面板直接按钮开路；**UI_GUIDELINES「问AI?入口」条目升格「弱化功能入口标签」通用标准**（适用场景=功能需入口但不凸显；配套面板文案规则；问AI 为案例，用户验收「看上去很舒服，非常棒」）|
|0.201.3|问AI?标签等高未学习（用户实测描边框比「未学习」视觉大一圈）：height 16（.height 含 border，0.196.7 教训）+fontSize 11→10 补偿框体+padding 仅左右 5；**UI_GUIDELINES 新增「问AI?入口标签」条目**（等高/字号/描边/位置/交互全规格）|
|0.201.2|问AI面板/编辑弹窗宽屏收敛（用户实测平板按钮拉满太长，两连问 UI_GUIDELINES 是否入档）：底部面板手机100%/平板460居中+四角RADIUS_NAV、纵排按钮手机100%/平板280居中、编辑弹窗手机86%/平板520——**isTablet 三元断点制**；**UI_GUIDELINES 新增「模态弹窗与操作按钮」条目**（禁按钮裸百分比宽拉伸/禁 constraintSize 钳显式 width 引 0.198.4 教训——固定值断点制唯一可靠）|
|0.201.0|问AI入口改版+卡片复习改名（用户拍板「紫渐变钮像坨屎」+「知识复习→卡片复习」）：知识库列表卡片标题行右端灰字入口（紫渐变钮删除）——方案E气泡描边+右下尾巴+紫问号 → 0.201.1 用户三点反馈过渡（尾巴取消像箭头/「?」同灰/边框收一圈 padding 9/4→6/2），**UI 定稿待用户 Pixso 稿**；边栏+复习页标题+AI鼓励语口径三处「知识复习」→「卡片复习」|
|0.200.1|导入动画重做（用户实测 0.200.0 动画翻车「不想用语言解释」——三大根因全修）：①**弹跳锚点左上=向右下窜**→scale 锚点保持左上（0.167.4 缩放语义不动）+**负 translate 数学补偿**（bounceTx/bounceTy，中心原地弹跳）②**发光/弹跳瞬切无过渡**→importGlow 连续值 0~1 渐变（border 宽 1+glow/shadow radius 12+glow×22 数值插值）+keyframeAnimateTo 四段回弹 1→1.14→0.98→1 ③**直线匀速飞行无质感**→keyframe 三段弧线（中点抬高 60 抛物线）+微旋转 -6°→4°→0°+缩放 1→0.7→0.3；另：变暗 0.55→0.4（原太重）、横幅顶部滑入/确认条底部滑入（TransitionEffect）、导航等待 430→300ms（回弹峰值即交棒）；**教训：ArkUI scale 锚点与 position 语义强耦合（c2s 坐标换算假设锚点左上），动画改锚点=破坏缩放交互——用 translate 补偿替代改锚点；keyframeAnimateTo 全局名 ArkTS 不可见，须 UIContext 实例+（param,keyframes）双参数签名**|
|0.200.0|知识卡片导入气泡对话（灵魂功能·业务闭环：卡片→提问，用户拍板三入口+L3 特效全量；docs/0.165+/0.200.0 文档）：①**三入口**——知识库列表「问 AI」icon（用户强理由：浏览即产生问题，点进去才能问不可接受）+编辑弹窗双按钮（传编辑器当前字段，未保存也能导）+复习页知识卡右上 icon（Stack TopEnd 不占版面），均弹二选一「导入气泡对话/创建子气泡」②**画布选择模式**——CardImportStore（AppStorageV2）+navBackToCanvas 四态回画布；变暗层 hitTestBehavior None 穿透（拖拽缩放保留）；单击=锁定（复用 selectedNodeId 高亮+信息行换「导入目标」）+底部确认条（✓导入/重选/点空白解锁）；横幅取消/返回键清 store 零残留③**L3 动画链**——飞行卡片（横幅位→气泡中心，与气泡同层画布坐标系零··算，450ms 缩至 0.25）→气泡弹跳 1.15+紫光晕（isImportGlow）→进对话输入区渐显 300ms④**落地复用圈注 0.184.0 全套**（import 填 inputText/pendingImages；branch 走 addBubble carryText/carryImages+isLoading 降级 toast）；文字格式「📚 知识卡片｜标题+定义+（我想问：）」**不自动发送**；**教训：①@Builder 内 if/else 块后禁止直接链属性（须先闭合容器再链）②svg 资源名=文件名，连字符禁用（ask-ai.svg→ask_ai.svg）③ArkUI 点击不冒泡=按钮自身消费，无需 stopPropagation④uitest uiInput 注入对 Button 组件不响应（存量按钮同样点不动）=设备自动化环境限制，容器 onClick 可注入**|

|0.202.1|司忆区命名+标签体验+多图（用户六件套直做）：①**「复习区」→「司忆区」**（用户拍板——仓颉司文、此区司忆，豆包AI典故；凸显注意力驱动记忆独创性）+设置底部仓颉彩蛋小字+README核心理念段②**列表标签chip化**（标题旁空区/高20≤问AI/圆角4偏方/横向滑动——0.198.3铁律合规）③**AI建议标签**——三提炼prompt加tags规则（2~4个学科词）+宽松解析（缺失不阻断）+ChatPage弹窗勾选区（选中主紫底）④**卡片多图**——images JSON数组+getCardImages两代兼容+编辑弹窗多选9张/横排缩略/单张删+列表首图+复习页横滑；**导入气泡暂带首图（CardImportStore单图字段，多图导入下轮）**；**教训：多行Replace的
在CRLF文件失配——须按行数组或双换行格式重试**|
|0.202.2|标签体验定稿+测试数据（用户六条直做）：①彩蛋文案定稿「昔仓颉造字以载文，今司忆守学而存忆」移保存/返回按钮上方②**提炼页标签长按改文字+「+自定义」添加**（mini输入弹窗，改名同步勾选串）③**编辑弹窗标签弃逗号输入改chip交互**（×删/长按改/+添加——用户拍板：逗号大小写心智负担）④**删编辑弹窗入口B两按钮**（用户逻辑：进来是编辑的，导入=不保存直接创建？保存呢——逻辑冲突，0.200.0 B入口撤销）⑤**导入气泡多图全链路**（CardImportStore.imageUri→imageUrisJson，三入口传getCardImages全部，consume解析全挂输入区）⑥**编程测试数据v3**（10张卡：算法/数据结构/设计模式/HTTP/索引/正则/并发/Git/递归/SOLID，标签0~9个递增，3张渐变头像PNG占位1~3图；seed v3同id更新内容保留记忆字段）|
|0.202.3|统计页三升级（用户三条直做）：①**四卡联动图表**——柱状图随下方卡点击切换指标（对话=条数/学习资产=新建气泡/Token/司忆量），图表标题显当前指标+单位，token≥1万显示 x.xk，选中卡主紫描边②**司忆量指标**（产品特色——单词/知识卡被司忆区展示次数）：StatDayEntry.siyi 字段+recordStat kind='siyi'（批量次数走 inTok 且提前 return 防污染 token 统计——自纠 bug）+埋点五处（ReviewPage 两处+ChatPage 复习区三处）+统计第④卡（累计/本周上周+理念小字）③**一年测试数据**（seedTestData：360→4 天前，增长趋势 25%→100%+周末×0.4 低谷+随机波动，近 3 天保真实；marker 'stats-test-seed-v1' 一次性；**上线清零=删 seedTestData 调用+marker 类**）|
|0.203.0|**桌面服务卡片**（用户需求：边栏账户行右边小字入口，点击生成桌面卡片展示复习内容，可放大缩小）：①数据桥 WidgetReviewUtil（preferences 快照读写跨进程共享+formProvider.setFormData 推送全部已添加卡片+formId 管理）②EntryFormAbility（FormExtensionAbility：onAddForm 读快照 formBindingData+记录 formId，onRemoveForm 清理）③ReviewWidgetCard 卡片 UI（暗紫风格双规格自适应 1×2/2×4，postCardAction router 拉起应用）④form_config.json（supportDimensions ["1*2","2*4"]）+module.json5 extensionAbilities 注册⑤边栏 AppSideBar 账户行右侧「桌面卡片」小字 pill 入口（requestPublishForm 免进入卡片市场直接上桌面，默认 2×4）⑥ReviewPage 接线（pushWidgetSnapshot：buildQueue/continueReview/onRate 后推快照——进度实时刷新，完成转 empty 引导态）⑦**编译坑**：本 SDK（API 26）FormProvider 无 requestPublishForm/setFormData——改 openFormManager（系统卡片管理器选规格添加，since 18）+updateForm；preferences 无 getSync——getPreferencesSync；form_config 必填 updateEnabled/defaultDimension，禁 windowingMode/defaultFlag；DEVECO_SDK_HOME 指向 `sdk\`（非 `sdk\default`）|
|0.204.0|**桌面卡片 2.0——卡片上直接复习**（用户拍板：跳APP是傻逼动作必须去掉；空闲速刷定位）：①架构改自闭环——快照升级双队列状态（WidgetState：word/knowledge 各含 items+idx+done+三档计数，卡片进程可独立跑 applyRating 纯函数复用主应用记忆算法含两层惩罚）②交互全 message：onFormEvent(formId,message)（非 onFormMessage——SDK 实名）分发 rate/switch；评分记 pending{happenedAt}，ReviewPage.aboutToAppear 先 mergeWidgetPending 回放真数据再 buildQueue（时间戳保间隔排期精确）；500ms 防连点③三规格（用户拍板 1×2 删）：2×2 紧凑（标签+1行+小按钮）/2×4 标准（切库 pill+三按钮）/4×4 大卡（统计行+大按钮+副文案）——onSizeChanged(since 20) 记 dimension 驱动排版分支（比 mediaquery 可靠）④文件拆分：WidgetReviewUtil（卡片安全——禁 connect store）+WidgetHostBridge（主应用侧构建/合并，收 store 参数防跨进程写冲突）+reviveWord/reviveCard 复活实例过 applyRating|
|0.204.1|**卡片三 bug 修复+call 通道真相**（用户实测+自主 Pad 自动化验证——uitest dumpLayout 抓坐标/uiInput 注入点击/hilog 追链路）：①评分无反应根因链（三层洋葱）：(a)@ObservedV2 装饰器类在卡片进程（无 ArkUI 运行时）加载崩——改纯字段版 widgetApplyRating (b)message 通道 msg 被本机桌面 IPC 剥空（对象/纯串/官方 params 键三形态实验均 ''）(c)**定稿=call 通道**：postCardAction{'action':'call','abilityName','method',**'params'里必须再嵌 method**}（form_event_adapter 报 fail get method from params 实证）+ **module.json5 加 KEEP_BACKGROUND_RUNNING 权限**（否则 The app does not have permission for keeping background running 拒绝拉起）+ **UIAbility.onCreate 注册 callee.on(method)**（进程存活/冻结态系统 ByCall→自动 Thaw→Callee 投递，未注册报 get func is undefined；回调必须返回 rpc.Parcelable——EmptyParcelable 空实现）+ 冷启动走 onCreate want.parameters（method/params 在 parameters）→评分即时落 PersistenceV2 真数据+快照 idx 推进+updateForm（7-14ms）。华为冻结激进：切后台 1 秒即 Freeze，但 call 会触发系统自动解冻投递 Callee（日志实证）②初始误显已完成——Index.aboutToAppear 延迟 800ms buildWidgetState ③空库文案区分。**调试方法论沉淀：uitest dumpLayout+uiInput click+hilog 三件套可全自动端到端验证卡片**（无视觉也能测：布局 JSON 含文本+bounds）|
|0.204.2|**卡片「继续复习」按钮**（用户拍板三规格必加）：①完成态加「继续复习 ›」pill（半透明紫底胶囊，2×2 小号）→ call method 'widgetContinue'（params 嵌 method 同规）→ EntryAbility Callee+onCreate want 双路径 → handleWidgetContinue：未来队列（reviewCount>0 且 nextReviewAt>now，pick 升序，截 30 张）→ 空则回退当日队列（同主应用 continueReview 兜底）→ 仍空 noMore='y'②noMore 态：有评分=「🏅全部学完啦」/ 零评分=「📚暂无复习内容」（空库引导回归）——均无按钮；主应用 buildWidgetState 新对象整体覆盖即重置 noMore③WidgetState.noMore 可选字段+binding noMore 键+卡片 @LocalStorageProp|
|0.204.3|**formId 自愈+重装链路**（用户实测：卸载重装后点按钮没反应）：根因=卸载清 preferences→form_ids 空→卡片收不到推送。**getPublishedRunningFormInfos 自愈被 systemapi 拒**（错误 2293765，保留代码幂等无害）→ 改事件驱动三通道：①onUpdateForm 兜底 addWidgetFormId+push②**onSizeChanged 也记 formId**（卸载重装后系统不重触发 onAddForm，但残留/重加卡片任何生命周期回调都带 formId）③form_config updateEnabled=true+updateDuration=1（30 分钟定期触发 onUpdateForm 兜底自愈）。**真机全链路验证**（自动化）：卸载→重装→空库自··· seed 10 卡→长按图标重加卡片→显示 1/10→评分翻页✓→点穿→完成态+继续按钮✓→继续→新队列✓。附：卡片评分路径 reviewCount 不增长（主应用靠 applyPassiveReview 展示计数，卡片无此环节）——pick 段位归类影响极小，后续可补|
|0.204.4|**多卡片 bug**（用户实测：第二块屏加卡片→新卡不动、点新卡旧卡动）：根因=**preferences 进程内存缓存**——卡片进程 onAddForm 写盘的新 formId，已启动的主进程缓存看不到→updateForm 只推旧卡。修复=formId/dimension 挪 **filesDir JSON 文件直存**（fileIo 直读写无缓存，跨进程永远最新；写者=卡片进程生命周期回调+主进程自愈；state/pending 留 preferences——主进程单写者+卡片进程冷读无并发）；readWidgetMeta/writeWidgetMeta（TextDecoder utf-8+TRUNC 写）+ensure 自愈改重读合并防覆盖|
|0.205.0|**数据安全三道防线**（用户红线：更新绝不丢数据，100% 本地方案）：①**第一道=Schema 铁律**（project_rule.md 成文：@Type 类字段只尾部追加/PersistenceV2 key 永不改/破坏性变更必须 migration+SCHEMA_VERSION 递增）②**第二道=内部双备份**（BackupUtil.writeInternalBackup：filesDir/backups/backup_a/b 轮换+tmp→rename 原子写；触发=Index 启动 800ms+EntryAbility.onBackground；空库+有备份→AppConfirmDialog 询问恢复「发现应用内部备份」）③**第三道=外部 .dagbak**（picker.save 用户选目录——应用创建的文件持续可写无需 persistPermission（systemapi）；每日自动备份开关默认关+开=选目录即备份+超 24h 打开应用补备+更改目录即备份不删旧；恢复=合并导入同 id 备份为准绝不删现有）④设置弹窗加「备份」Tab（currentTab=6 不重排）⑤范围=词库+知识库（含记忆字段/标签/图片），气泡树后续扩展 |
|0.205.1~0.205.3|备份链三轮修：①空文件（picker save autoCreateEmptyFile 预创建 0 字节壳+READ_WRITE\|TRUNC 假成功→关预创建+WRITE_ONLY\|CREATE\|TRUNC+写入字节数校验+读回验证闭环）②文件名定稿 Dag_AI_Chat_Backup（覆盖式不带时间戳防误导——时间戳让用户误以为时刻快照）③导入发现不了文件（fileSuffixFilters 过滤格式把列表筛空→去掉过滤显示全部）+删设置页内部备份卡（后��静默不暴露——用户拍板防混乱）+备份 Tab 移司忆区后+Tab 栏横向 Scroll 防溢出|
|0.205.4|**备份序列化根因修复**（用户实测重大 bug：恢复后卡片条数对但内容全空）：根因=**@ObservedV2 类的 @Trace 字段 JSON.stringify 不可枚举→实例序列化成 {}**。修复：导出端 wordToPlain/cardToPlain 手写字段映射（内外备份同一流水线一处修两处）+revive 端 Record 键读+jsonToPayload 拦截坏备份（空壳拒收）+Tab 滚动条隐藏。教训入 project_rule：@ObservedV2 实例禁止直接 JSON.stringify|
|0.205.5|恢复端第二道网：restoreFromPayload 逐条丢弃空壳（word+id 或 title+id 双空跳过）——闸门一漏网混合文件也进不了库|
|0.206.0|**用户行为埋点体系**（用户红线需求：数据驱动决策——播客模式等伪需求验证，两周没人点就删）：①调研真相：**华为分析无 NEXT 原生 SDK**（@kit.AnalyticsKit 不存在+ohpm analytics 404+hiAppEvent 自定义事件不上云——华为AI两次给假代码）；定稿方案 C=**hmcore+cloud（ohpm 真实包）+云函数 trackEvents+Cloud DB events 表**②TrackUtil（track 统一接口+隐私闸门默认关+攒批 20 条自动上报+退后台 flush+hiAppEvent 本地双落+失败静默留队列）③EntryAbility.initAgc（rawfile json 异步 initialize；agconnect-services.json **不进 git**）④17 事件第一批（全表见 **docs/埋点字典.md**：加埋点必须同步登记铁律）⑤设置·关于 Tab「体验改进计划」Toggle（默认关=合规，关时清队列）⑥云函数部署指引 docs/cloud/trackEvents部署指引.md（用户贴控制台：函数 trackEvents+Cloud DB 表 events e/p/t）|
|0.206.1|云函数名 trackEvents→**track-events**（AGC 命名规则：仅小写/数字/中划线，大写被拒）|
|0.206.2|**埋点链路全线打通（两座大山）**：①**云函数侧灵异真相=无痕模式假提交**（豆包 2026-10-08 定位真凶）——无痕窗口点「提交」不报错但代码根本没保存，函数一直跑空模板（@@Start→@@End 2ms 无用户日志）；换浏览器提交即生效，测试面板复活（转圈同因）；另在线编辑器**不内置 @hw-agconnect/cloud-server**（require 失败→入口加载失败静默空跑），CloudDB 完整版须 **zip 部署包**（handler.js+package.json+node_modules 根目录平铺，npm install 后全选压缩）——待做；发布版本/别名均非必需（callFunction 默认 $latest，测试 $latest 免发布）②**客户端侧=退后台 flush 被鸿蒙掐网**（onBackground 发网络必败——与 0.153 教训同源，自己埋的雷）；修复三件套：**onForeground 补发**（可靠点）+**失败回滚队列**（0.206.0"先清后发"失败即丢，注释承诺未兑现——真·断网不丢，QUEUE_MAX=200 防膨胀）+hilog 诊断日志（TAG=DAGAI_TE，flush ok/fail 可查，0.206.2 前全静默无法���查）。验证法沉淀：前台满批（切 Tab 25 次）实测秒到=通路铁证|
|0.206.x竣工|**云函数全链路竣工（2026-10-07，六座山完整档案见 docs/cloud/trackEvents部署指引.md）**：③函数包内 node_modules 被**平台无视，依赖必须走「层配置」**（层解压到 /dcache/layer=函数目录上一级，Node 向上命中；另 PS5.1 Compress-Archive 条目反斜杠坑——手写 ZipArchive 正斜杠，打包脚本 E:\track-events\build-zip.ps1）④SDK 需**项目级凭证**（项目设置→Server SDK 页签下载 agc-apiclient.json→cloud.createInstance(path,'trackEvents',Region.REGION_CN)；含 client_secret 绝不入 git——E:\track-events 工作目录在仓库外）⑤plain object upsert **不标记主键**（报 3037003）——必须 CloudDBZoneGenericObject.build+addFieldValue(字段,值,主键?)（真实存在于 database-service/request/ 下，华为AI首版给的 API 没骗人）⑥**t 字段必须 Long**（Integer 32位装不下毫秒时间戳，报 3007007）。数据看板：AGC→云开发→Cloud DB→数据管理→存储区 default/events，可导出 CSV→Excel。云端终态=层 cloud-server-deps（node_modules）+函数包三件套（handler.js/package.json/agc-credential.json）|
|0.206.dash|**埋点可视化看板（2026-10-08，用户验收满意——"最重要的一步流程跑通"）**：本地 Node 服务零新依赖（E:\track-events\dashboard\，双击桌面「埋点看板.bat」→ localhost:8765）；①热区还原——Pad 真机截图+坐标徽章（x/y 比例坐标）+时间窗计数+点徽章跳图表，12/17 事件已标注（对话页 5 事件+widget 3 事件待补图）②ECharts 柱状图（npmmirror CDN）——事件下拉+小时/天/周/月/年粒度+参数分色堆叠+汇总卡。技术沉淀：uitest dumpLayout+extract-marks.js 提取控件中心比例坐标（界面变更重跑即换图）；query().get() 返回 CloudDBZoneGenericObject（fieldMap 是 Map 序列化成 {}，必须 getFieldValue 逐字段转平铺）；**代码快照存档 docs/cloud/（handler.archive.js + dashboard-archive/），真身 E:\track-events 以真身为准**；维护流程=用户喊"底图过期"→AI 重截图+extract-marks 更新 coords.json→刷新即生效（不做系统按钮——用户拍板）|
|0.207.0|**anything 导入一期（2026-10-08，用户拍板 B 三步走：0.207.0 文件夹+CSV/TXT → 0.207.1 xlsx/dagpack → 0.208.0 apkg）**：①**文件夹体系**——KFolder(id/name/parentId)+KnowledgeCard 尾部加 folderId（Schema 铁律）+KnowledgeBankStore.folders；CRUD（addFolder/renameFolder/**deleteFolder 卡片子上移绝不删卡**/moveCards/copyCards 复制=内容复制记忆清零/ensureFolderPath 幂等建链——apkg deck 映射预留）；UI：面包屑+文件夹行（⋯菜单重命名/删除）+多选工具条加移动/复制（目标选择弹窗全路径列表）+返回键逐级上跳 ②**批量导入 TXT/CSV**——ImportUtil（readTextFile UTF-8优先GBK回落+BOM剥除/parseCsvLine 引号状态机/parseTextToRows 表头启发式丢弃）+预览弹窗前10条+确认入当前文件夹 ③**导出 CSV**（UTF-8 BOM Excel直开；导出所见=当前文件夹或搜索结果）④埋点+5（folder_create/card_move/card_copy/batch_import/export_csv）⑤备份兼容（payload 加可选 folders+reviveFolder；旧备份无字段→不动目录）⑥ ArkTS 坑实录：Scroll 构造只收 Scroller（水平滚动用 .scrollable）/maxHeight 只在 constraintSize/Record 字面量带属性赋值禁止（必须空对象+键赋值——0.206 铁律再犯）/picker 无 DocumentSavePicker 类（DocumentViewPicker.save+Options 实例——0.205.1 同款）|
|0.207.1|**xlsx 导入 + DagPack v1（2026-10-08，用户设计拍板「发送端粗粒度·接收端勾选细粒度」）**：①xlsx——@archermind/exceljs（ohpm 1s 装好，附赠 @ohos/jszip 备 v2 zip 化）读首表 A/B/C 列同 CSV 约定 ②**DagPack v1=单 JSON**（图片 base64 内联；version 字段留 zip v2 升级位）：导出=点文件夹即全子树打包零选择器（+菜单/文件夹⋯入口；refId 一次性生成防跨设备撞 id）；导入=勾选树弹窗（顶层文件夹☑各含子树+根级散卡独立勾，默认全选）→ 新子树挂当前文件夹**绝不合并现有目录**（同名并存用户自移——为气泡树包「导入即新选项卡」心智铺路）；kind 字段预留 bubble 类（0.208 专项）③远景地基：卡片集市（文件夹包+描述/心得分享）/碰一碰快传——格式即为此设计 ④坑实录：PowerShell -replace/Set-Content 改中文注释文件必乱码（Get-Content 默认编码坑）——**中文文件一律用 edit 工具改**，出错 git checkout 还原 |
|0.208.0|**Anki apkg 导入 + 单词库 DagPack（2026-10-08，anything 导入体系收官）**：①**apkg→知识库**（用户拍板映射：正面=title/背=definition/图全提/[sound:]丢弃/App 自带语音/复习进度丢弃新卡开始）——解析链 ApkgUtil：uri→拷沙箱→**zlib.unzipFile**（系统 zip 解压）→**relationalStore.getRdbStore({name:'collection.anki2', rootDir:解压目录})**（★ API18+ rootDir 只读开任意路径 SQLite——破局关键，本地 d.ts 实查）→col.decks JSON（did→牌组名）+cards（nid→首卡 did 同 note 多卡只导一）+notes（flds \x1f 分段+tags 空格转逗号）；HTML 清洗（br/div→换行剥标签解码实体）；media JSON 真名→编号文件→base64；**deck「A::B::C」→ensureFolderPath 幂等文件夹链**（重复导入复用）②**单词库 DagPack**（kind:'wordbank'，全量平铺；导入重词幂等跳过保留原进度——addWordToBank 自带拒绝）③坑实录：CompressLevel 枚举实名 COMPRESS_LEVEL_NO_COMPRESSION（前缀全称）④用户拍板：单词库**不做** Anki/表格导入（单词库格式私有场景；Anki 单词走知识库导入后手动重建）|
|0.209.0|复习卡「单面/正反两面」卡面模式（用户重要需求，评分三按钮逻辑零改动）：FaceModeStore（**全新 PersistenceV2 key 'review-face-mode-v1'**——数据安全铁律）+单词卡正面单词音标/知识卡正面标题、翻面出答案可翻回+⚙设置弹窗顶部卡面模式区（单词库/知识库独立选）+默认单面；双面未翻时隐藏答案显示「点击卡片查看答案」|
|0.209.1|**修复卡面模式/每日复习量设置「后台能切前台不动」**（用户报 bug）：双根因——①带参 @Builder 按值传参不刷新（**0.190.1 铁律复发**：faceSegment/countSegment 高亮点击后不动）②faceMode/dailyCount 是普通成员未挂 @Local（@Computed isDoubleFace 依赖链真机不可靠）。修复=两 Builder 无参化拆四个直读状态+connect 的 store 挂组件必须 @Local；**教训：新 @Builder 一律无参化内部直读状态，@ObservedV2 connect 实例挂 @ComponentV2 必须 @Local 接管**|
|0.209.2|**修复双面模式「点反面误跳卡」**（用户报 bug：翻面后再点反面直接跳下一张，"默认选了哪一档？"）：根因=评分区动态 if 插入挤占 Blank 弹性空间→**翻面瞬间卡片整体上移、评分按钮窜到用户刚点过正面区域的位置**→第二次点击误触评分按钮。修复=评分区改**固定高度占位**（88vp 容器 justifyContent End，翻面前就预留按钮空间，卡片纹丝不动，按钮永远在页面底部远离卡片）；Pad uitest 全链路自动化验证通过（翻面卡片位移仅 7vp/点反面 1/4 不变/评分按钮位置固定）；**教训：动态出现的操作区必须固定占位，否则布局重排会让按钮"窜"进用户操作惯性区**|
|0.209.3|**双面交互定稿（用户拍板两连改）**：①**评分按钮紧贴卡片下方成组居中**（0.209.2 按钮贴屏幕底→与卡片间被 Blank 隔出大片空白，用户骂"上面的空格太多非常难看"；占位区从第二 Blank 后挪到卡片正下方 92vp+paddingTop12，翻面瞬间卡片仍纹丝不动——跳卡修复不回归）②**翻面后点反面无动作**（反面=终态"标题+内容组合"完整展示，用户"没有任何理由再跳回去"——评分三按钮是唯一跳卡出口）。Pad 自动化双验证通过（按钮 1580→1186 紧贴卡片/点反面界面纹丝不动进度不变）；**教训：固定占位≠贴屏底，占位区要放操作对象旁边成组**|
|0.209.4|**修复评分按钮第三行被裁剪**（用户手机截图实锤："第三行超出边界了"）：占位 92（paddingTop12 后可用 80）< 按钮实测高 **120vp**（Pad uitest dump 实量：三行文字+Button 自身 padding，0.196.x 起一直存在只是动态布局下被 Blank 吸收无感，0.209.3 固定占位后暴露）→ 第三行「X分钟后」整个在裁剪区。修复=占位 92→**136**（12+120+4）。Pad 截屏（uitest screenCap）实证三行全部完整；**教训：固定占位高度必须用 dump 实量按钮 bounds，禁止估字号×行数——Button 自身 padding/最小高度比目测大得多**|
|0.210.1|**标签 mini 弹窗下坠首修+图片 emoji 全换透明 svg**（用户报："点标签添加按钮下面的方框一直往下，很大的 bug"+"添加图片左边彩色按钮换华为官方透明样式"）：①mini 弹窗 Blank() 删（推底+键盘避让反复下沉）改 justifyContent Center ②🖼️ 彩色 emoji → 自建 image.svg（白 65% 描边山形画框，同 settings.svg 约定）×5 处（KnowledgeBankPage 标题图/内容图 + ChatPage 卡片指示×2/下拉菜单）③补 0.210.0 漏掉的版本号三处同步（Index/GSD 还停在 v0.209.4）|
|0.210.2|**mini 弹窗真居中二修**（Pad dump 实锤 0.210.1 标题仍在 y=1640 贴底）：根因=mini 遮罩挂**编辑弹窗内部**（自适应高度父），height('100%') 无参照永不居中。修复=块上移到全屏遮罩层与编辑弹窗同级（后绘制保持上层）；仍不铺满 [520,1049] 起——**教训：挂错父层/布局流的 height('100%') 不可救药，先看挂载点**|
|0.210.3|**mini 弹窗真居中三修（收官）**：editorDialog 根 Column+Center → **Stack({alignContent: Center})**——Column 布局流里兄弟元素使子项 100% 尺寸解析怪异（遮罩 [520,88] 起），Stack 子项百分比铺满语义可靠。Pad dump 终验：弹窗中心 y=929≈屏幕中线 920，"一直往下"根治；**教训：多层弹窗嵌套一律 Stack 化，Column 弹性流+百分比尺寸组合在弹窗场景不可靠**|
|0.211.0|图片额度检测+列表标题图全展示（用户四点：手机超限崩溃/额度预检/列表排版/颜色统一+双击放大）：选图 picker maxSelectNumber 动态额度 9-已有（源头截断）；列表卡=标题行去缩略、标题下全部标题图横滑条；编辑弹窗两按钮颜色字号统一浅色 13；image.svg 华为透明风；全页查看器 imagePreviewViewer（Swiper+双击/捏合缩放+×+右滑关）|
|0.211.1|**修复手机端「9 张点保存崩溃」**（用户实测：3+6=9 显示正常，点保存即闪退，仅手机端）：根因=9 张**原图** base64（单张 5-10MB×1.37 膨胀）直塞卡 → 保存全库序列化+PersistenceV2 写盘内存峰值爆（PC 内存大不崩）。根治=**选图压缩**（image API 解码→最长边 1280→JPEG q80，单张落盘 ~200-400KB）；data URI 前缀不变全链兼容。另：编辑弹窗标题图缩略点击补预览（原无响应）+预览改"点哪张看哪张"（原固定 [0]）+列表图片**单击**放大（原双击被误判为拦截）+内容图 9 张全部横滑展示（原仅首图缩略）；**教训：图片类持久化必须选图时压缩，原图 base64 直塞 @ObservedV2 全库=手机端定时炸弹**|
|0.211.2|**四场景图片预览统一+右滑误退页修复**（用户实测四点）：①列表标题图/内容图+编辑弹窗标题图/内容图四场景全部走同一个 imagePreviewViewer（编辑弹窗旧单图预览器删除）；②**右滑直接退出知识库页根治**=查看器没挂 onBackPressed 拦截（系统侧滑透传退页）——拦截后侧滑只关查看器；失灵的 PanGesture 删除（与 Swiper 翻页手势竞争恒吃不到）；③退出三重冗余落地：单击图片关（0.173.x 铁律 count:1 手动判双击+320ms 延迟关）/×按钮/右滑侧滑；④双击缩放缓动 250ms EaseOut（用户报"放大太快"）+PC 鼠标滚轮缩放（onMouse scrollDelta）；旧预览链路死代码清除（状态/Builder/挂载点/返回分支）；**教训：全屏查看器必须挂返回键拦截，PanGesture 与 Swiper 并存恒失灵勿再试**|
|0.211.3|**0.211.2 假装机事故根治**（用户反馈三 bug→查实 Pad 显示还是 v0.211.1）：0.211.2 代码带编译错误（UI 层 MouseEvent 无 scrollDelta 属性+handlePreviewTap/previewTapHandled 方法名不匹配），hvigor 增量缓存下 CompileArkTS up-to-date **跳过编译→旧 HAP 原样装机并报 ok:true**（装机"成功"是假象，三台全装旧包）。修复=删滚轮缩放（SDK 无 UI 层滚轮 API，PC 用双击缩放替代）+方法名修正+**清 entry/build 缓存强制全量重编**（新 HAP 时间戳 22:34+大小变化+Pad dump 实锤 v0.211.3）；**铁律入档：①装机后必须 Pad/设备 dump 验版本号（假成功防线）②hvigor"签名同名不重签"坑的扩展形态=缓存命中连编译都跳过 ③滚轮缩放无 UI 层 API 勿再试 onMouse.scrollDelta**|
|0.212.0|**知识库卡片滑出式删除+勾选框图标化**（用户拍板：常驻红 ×"太难看特别是红色"→左右滑露回收站标识，"注意 UI 不要叉叉"；多选 ☑ 打勾 logo 太丑）：①ListItem.swipeAction start+end 双向挂 swipeDeletePanel（警示红底+trash.svg 白图标 76vp，点击走 requestDeleteCard 原确认链路，多选中点击 guard 无动作）②☑/☐ 字符勾选框 4 处全换 checkbox_on/off.svg（列表多选/删除确认"不再提示"/DagPack 勾选×2，品牌紫底白勾+灰描边空框）。Pad 实测：红 × 清零+左滑露出回收站（右侧新 Image 实锤）；**踩坑三连：①swipeAction 是 ListItem 专属属性挂 Row 上编译器不认 ②@Builder 不能在 swipeAction 里直调须箭头函数包（直调破坏解析→1797 个级联误报）③edit 事故：oldString 尾换行把方法签名并进注释行致全文件解析崩坏（大括号配平≠嵌套正确，靠读缩进定位）**|
|0.212.1|**回收站面板 UI 微调**（用户验收 0.212.0"功能逻辑非常棒"但 UI 不满："不想要红色""不用特别大"）：警示红→**品牌紫 BRAND_PRIMARY**（与暗紫 UI 同语言）+面板 76→56vp、图标 24→20（回收站符号本身已表意）。一条龙收官三台齐装+Pad 版本号实锤 v0.212.1|
|0.212.2|**滑出删除圆钮化+确认弹窗限宽（PC 截图实锤两诉求）**：①面板"高度太高一大块色块"→改 **44×44 圆形小钮**（外容器满高 Center 露出区宽 72）②确认弹窗"PC 上太宽双按钮被拉成面条"→宽度 `isTablet ? 400 : '86%'`（比编辑弹窗 520 窄一档）。Pad 实测：圆钮 50×50px 居中露出 ✓、弹窗 900px=400vp（屏幕仅 1/3 宽）✓；**规格已入 UI_GUIDELINES 六-11/12**（滑出删除=显眼紫+小巧圆钮、确认类对话框宽高比）|
|0.212.3|**宽屏卡片标题居中+标签间距**（用户以"算法复杂度"卡举例：宽屏左对齐"瞄左上角难受，标题居中更舒服"；手机左对齐已好评不动）：①标题 textAlign/layoutWeight/constraintSize 三属性 isTablet 三元（宽屏=行内居中+占满弹性；手机=左对齐+62% 上限）②标签往后排自然宽（宽屏上限 38% 防溢出，手机维持弹性）③问AI? 按钮 margin left 12（原贴边 6——用户"标签右边距离与问AI 要对称呼吸"）。属性三元写法避 if 链属性雷|
|0.213.0|**滑出面板双圆钮+宽屏标题同轴定式**（用户验收 0.212.3 居中方向 OK 但三连精化）：①标题居中跟着标签宽度漂移（"上下不整齐"）→宽屏标签列改**定宽 width 38% 内容左对齐**（用户"标签不要右对齐要左对齐，放在标题右边"），标题列剩余全弹性→**所有卡片标题同一垂直轴线**②"问AI?"文字按钮撤除→挪进滑出面板：**swipeActionsPanel 双圆钮**（左问AI ask_ai.svg+右删除 trash，同款 44×44 品牌紫圆钮露出区 120，用户点名"问AI 放删除左边，设计个鸿蒙 logo 凸显问AI 概念"），规格入 UI_GUIDELINES 六-11/11a。**⚠️ 连环编译事故五轮复盘（0.213.0 一条龙跑五遍才收官）**：①scrollDelta 不存在于 UI MouseEvent ②方法名 handlePreviewTap/previewTapHandled 不匹配 ③撤问AI edit 的 oldString/newString 把**双层 Row 嵌套**（外层标题行+内层 title/tags 行）的闭合错位——外层闭合被删、Entry Column 被提前闭合，图条/定义/复习时间全成孤儿 ④swipeDeletePanel 替换时**残留旧面板后半段**（struct 级孤儿属性致深度归零）⑤**build 内空 if 块（只注释无组件）非法**。修复利器=**awk 括号深度追踪（字符串内 {} 需 gsub 屏蔽但注释会干扰，定位准星以老机器编译器报错为准）**；**铁律：双层 Row 嵌套区改结构必须整段重读缩进逐层核对闭合，禁盲删闭合括号；build 内禁空 if 块**|
|0.213.1|**标题同轴彻底版+手机排版复原+图标透明度对齐**（用户截图实锤 0.213.0 仍不齐："标题一定要在方框的正中间，标签在标题右侧左对齐"+"问AI 图标白色有点亮，透明度跟回收站对齐"）：①**不齐真凶=标签列挂在 if(tags) 里**——无标签卡右列不渲染→标题占满全行（中心 50%）vs 有标签卡标题列压缩（中心 ~31%）→上下漂移。修复=组件级 if 平台分治：宽屏两列定式**标签列恒渲染**（无标签=38% 空占位）→标题列恒 62%、全部卡片标题同轴线 ✓；标签列 alignItems(Start) 左对齐 ✓②手机恢复 0.212.3 前好评原样（左对齐 62%+标签弹性），并顺手修 0.213.0 的 width(undefined) 雷③ask_ai.svg 三处 opacity 1→0.65（与 trash 同款白 65%——用户"回收站透明度比较低比较好看"）。三重验证收官：/install 日志 0 错误+ok:true+Pad 版本实锤 v0.213.1|
|0.213.2|**标题=卡片几何正中 Stack 终式+行距加大**（用户指出 0.213.1 的轴线是"标题列中心 31%"不是卡片正中"50%"，且拍板"标题在方框正中间、标签在标题右侧左对齐往后排"+标题内容行距"大一两个像素"）：①宽屏标题行改 **Stack({alignContent: Center}) 叠层**——标题层（textAlign Center+maxWidth 60% 与标签区零重叠）恒定卡片几何正中，**与标签列完全解耦上下永远一条线**；标签层（底层）=Blank 弹性推右+38% 定宽列内容左对齐②标题与内容行距 2→4③UI_GUIDELINES 11a 更新为 Stack 终式（并沉淀"凡'必须几何居中'的元素一律 Stack Center，勿用弹性列 textAlign 近似"）。⚠️ 两连编译坑：标签 Scroll 属性链曾缩进到 if 块外（挂 if 语句上非法："Cannot find name 'scrollable'"）；**本轮再实证 /build 200 假成功（HAP 时间戳不变即未重编，装机前必查 HAP 时间戳+/install 日志）**。三重验证收官：日志 0 错误+ok:true+Pad 实锤 v0.213.2|
|0.214.3|**气泡长按菜单增「增加子气泡」+菜单限宽**（用户长按截图反馈：菜单只有改标题/删除两项要加加子气泡+PC 上 62% 太宽）：①菜单三连=修改标题/增加子气泡/删除气泡（新增项白字居中同款，插删除之前）；addChildBubble 复刻 ChatPage createChildBubble 链路（generateNodeId+parentID+冗余 parentX/Y+随机偏移 80+0~40+埋点+saveTree+autoLayout，画布端不切对话页）②菜单限宽 `isTablet ? 280 : '62%'`（宽屏固定 280=确认弹窗 400 定式窄档）。**⚠️ 同族重复标识符雷第三踩**：插入 windowMode/isTablet 前未查 BBTreeCanvas 已有同名成员（0.214.1 入档的教训执行不到位）——Duplicate identifier 6 错，秒删复用已有成员；**三台 bm dump 全部实锤 versionCode=1000148**（最硬验证定式全线落地）|

## 版本号体系（2026-10-03 起）
- 首页显示版本号，每次改动编译装机递增末位；当前 **v0.214.3（versionCode 1000148）**；★ 0.190.6 起版本号**多处同步**（app.json5 versionCode / Index.ets Text / GlobalSettingsDialog APP_VERSION 常量 / MEMORY.md 本行）；★ 0.195.0 起装机**必须递增 versionCode**
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
8. **AGC 控制台操作必须用非无痕窗口（2026-10-08 定位，豆包贡献）**：无痕模式导致「提交」静默失效（代码根本没保存——0.206.x 假提交灵异事件真凶）、测试面板永远转圈、Cloud DB 导出失败。**以后凡涉及 AGC 后台操作（提交/测试/导出/创建资源），AI 必须先提醒用户确认浏览器为非无痕模式。**
9. **开发机迁移待办（2026-10-08 下午计划：Windows PC → MateBook 14，用户主动报备）**：迁移时 AI 必须给完整 SOP，清单——①git 仓库整目录拷贝（含被 .gitignore 的 rawfile/config.json + rawfile/agconnect-services.json 两枚**不入 git 的关键文件**，拷目录自然带走，**禁止只 git clone**）②**E:\track-events\ 整目录**（云函数源码+agc-credential.json 凭证+build-zip.ps1+dashboard 看板）③E 盘两个部署 zip（可带可不带——build-zip.ps1 能重生成）④新机装：DevEco Studio+SDK、CodeArts、Node.js、hdc 无线调试重新 connect（Pad IP 会变，先 `hdc tconn IP:5555`）⑤鸿蒙 PC 上 DevEco/CodeArts 兼容性未实测——遇到问题现场解决。换机后用户会告知 AI；MEMORY.md/project_rule.md 即 AI 记忆，随仓库迁移无缝续接。
