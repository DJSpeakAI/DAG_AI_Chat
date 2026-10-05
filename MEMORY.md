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
|0.153|提炼弹窗超时、错误中文提示、Token统计（AI回复秒表已删，提炼弹窗读秒保留）|
|0.160.x|Prompt泄漏修复、ForEach Key碰撞修复；**ArkUI V2铁律：ForEach item内visibility/if初始求值必须Visible，None/false移出渲染树后通知永不到达**；API key内置默认（**上架前须删**）；docs/0.160.md|
|0.161.x|学习数量设置、API Key外置rawfile/config.json；**git教训：GitHub Push Protection拦截Key→reset --soft重写历史；unblock-secret链接绝对勿点**；docs/0.161.md|
|0.162.1|新建分支过渡动画（链式animateTo淡出→切store→淡入440ms防刷屏）；docs/0.162.md|
|0.163.x|代码块按钮icon化、更名DAG AI Chat、用户logo；**教训：bundleName勿动**（调试profile绑死包名）；docs/0.163.md|
|0.164.x|华为账号登录跑通；**教训：①Account Kit登录须AGC手动申请调试Profile+手动签名（DevEco自动签名无有效Client ID）②受限权限须Profile ACL显式授权③错误码上屏是排查利器**；docs/0.164.md（错误码速查表）|
|0.165.x|云同步双端调测收官；**踩坑：新SDK删类型名→类型推断；循环依赖用回调注入；下行写池绝不upsert防回环；AGC入口是「云空间」非云数据库**；遗留v0.165.3=同步状态提示+云空间开关引导；docs/0.165.md|
|0.166.x|圈注图丢失修复（根因=动画回调清空pendingImages→addBubble加carryImages参数）；平板首页占左栏（Navigation Auto分栏→Stack单栏）；主题锁定暗色方案A（亮色分支代码保留勿删）|
|0.167.x|Pixso canvas落地：UI_GUIDELINES+DesignTokens双真相源、连线Canvas命令式绘制、子树占位防重叠、等比缩放+限幅方向感知；**教训：Path无viewport自动缩放commands=连线飞左上角真根因；topSafe与信息条padding联动**；遗留：缩放放大恢复路径待补验；docs/0.167.md|
|0.168.x|画布左侧边栏：平板208常驻/手机抽屉（☰按钮唤出、删边缘右滑热区）；导航「哪进哪回」；**平台坑：①overlay不参与hit test ②系统手势区占左缘0~65px ③手势中途挂载带onClick组件致触摸流重路由（抽屉自关根因→唤出判定移onActionEnd）**|
|0.169~0.171|复习区划词悬浮栏（翻译/入知识库/复制）、边栏信息与UI微调、连线高度缩短启动|
|0.172.x|连线缩短（verticalSpacing 113，层间距公式113×s）；气泡卡片加「N条对话·X分钟前」（messageId解析时间戳，零模型改动）|
|0.173.x|气泡拉宽NODE_W 170；单击选中态（selectedNodeId优先、回落current）；边栏副标题「你的AI学习伴侣」；**核心教训：TapGesture count:1/count:2并列绑定单击抢先阻断双击，单双击并存须只绑count:1手动判定（两次tap<300ms=双击）**|
|0.174.x|首页+设置弹窗UI优化（token收敛、分段控件、主紫按钮）；**满屏教训：NavBarContent底部420px被clip→Stack包Navigation+expandSafeArea铺满全屏；setWindowBackgroundColor手机端不可用；SemiBold=数字600+Inter-SemiBold**|
|0.175.0|设置三Tab协调：保存右侧加「返回」；小字行间距以云同步为标准（多行提示lineHeight 18）入UI_GUIDELINES；称呼示例「好奇宝宝」|
|0.176.0|信息条左上角返回箭头删除（边栏落地后画布即主页面，pop回Index入口由边栏导航承担）|
|0.177.0|IDE分层图标警告修复（icon改指layered_image）；冷启动旧logo闪现修复（startIcon.png漏换，同图替换）|
|0.178.0|冷启动logo闪现根治：startWindowIcon透明化（全透明png）+start_window_background两处→#120B1F；信息条标题「知识画布」→「气泡树」；桌面短名DAGAI保留|
|0.179.0|首页改版：主按钮「进入气泡树」、按钮+登录区下移拇指区、标题32/副标题14；**布局：Blank弹性占位2:3:1（有layoutWeight子元素时justifyContent Center失效）**|
|0.180.0|边栏跳转单词库/知识库不收抽屉，返回画布边栏保持打开（哪进哪回状态保持）；**教训：pushPath压栈不销毁源页面、组件状态路由往返天然保留，跳转前主动重置入口UI状态反而破坏哪进哪回**|
|0.181.x|ChatPage 按稿收敛（DesignTokens 批量套色、isDark/getThemeStore 清零、圆角/字重对齐：气泡 RADIUS_NODE/面板 RADIUS_NAV/控件 RADIUS_CONTROL/标题字重 600）；首页标题下移 56vp（弹性占位 2.5:2.5 对冲）；**教训：版本号同步点共三处=app.json5+Index.ets 注释+首页显示文本**|
|0.182.x|画布/对话页六项打磨+两连调：☰→gitbranch、发送+▾合体（isLoading 置灰守卫、▾保持可用）、喇叭 icon 调亮四处、点输入框外收键盘（根容器 onClick clearFocus）、画布空白双击放大（一档 1.25、中心移动走 1/3 缓动）、选项卡根节点删除修复（confirmDeleteBubble 改调 deleteTab 复用确认弹窗）；**教训：①GestureEvent 无 x/y 属性，取点击位置须用 onClick 的 ClickEvent.x/y（组件局部坐标）②交互位移类须缓动勿突变跳转（用户嫌「太唐突」）**|
|0.183.x|单词库/知识库两页（含各自设置弹窗）按稿收敛：isDark 三元死代码清零（getThemeStore 方法删）、操作蓝 #1976D2→BRAND_PRIMARY、删除红 #F44336→DANGER、弹窗面板灰→SURFACE_NODE、输入框灰→SURFACE_SOFT、遮罩→OVERLAY、圆角 8/6/4→RADIUS_CONTROL、12→RADIUS_NAV、Bold→600、列表卡片升级 SURFACE_NODE+STROKE_CARD 描边；两页根 Stack 补 BG_APP 底色（原透 NavDestination 纯黑）；**教训：①NavDestination 自带 #FF000000 黑底，页面根容器不设底色即透黑②像素验证以 UI 树 json 的 backgroundColor/bounds 为铁证——截图与 UI 树同一像素坐标系勿做分辨率换算，且遮罩压暗色（#241640×50%≈#120B20）恰与 BG_APP #120B1F 同色、易误判遮罩未生效**|
|0.184.0|屏幕标注页双升级：①补充要求输入框（圈注后写「标题写什么/内容围绕什么展开」——存入知识库图+文一起发 AI 按用户要求精准提炼，ApiClient 双提示词按 note 有无切换；导入对话/创建子气泡时文字填入对话输入框）②标注页 UI 对齐暗紫 DesignTokens（isDark 三元清零、顶栏撤销/清空 icon 化、返回确认弹窗覆盖补充要求）；**教训：addBubble 扩 carryText 随切换回调带入（与 0.166.1 carryImages 同模式，防 140ms 动画回调清空）**|
|0.185.0|单词库设置弹窗（⚙）新增音标口音切换：美式（默认）/英式两选项，切换先确认弹窗「切换音标后，原先的音标将会被删除」，确认后 clearAllPhonetics 清空现有音标+toast、后续查词按新口音生成（ApiClient 双提示词口音参数化 buildWordQueryPrompt(british)/buildWordQueryZhPrompt(british)）；**教训：PersistenceV2 新字段必须全新 key（phonetic-accent-v1 仿 learn-count-v1），挂旧 key 读取为 undefined**|
|0.186.0|文档管理+AI token优化+核心文档精简线：①docs/按版本段重组织（0.140-0.152/0.160-0.164/0.165+三段+归档archive/），加总索引 index.md ②分层按需加载（L1总索引/L2段索引/L3详情/L4归档，project_rule.md 加 §5）③0.164.md 32.6KB→5.2KB 精简（砍已排除项细表/错误码速查/AGC步骤/签名执行记录）|
|0.187.0|单词库记忆算法（简化遗忘曲线 R=e^(-t/S)，方案B：下次复习=现在+S，用户拍板）：①复习区（气泡底部+提炼弹窗）👆点词展开 3 档评分——生疏（首评10分钟/复评×0.5，下限10分钟）、尚可（首评12小时/复评×1.6）、熟知（首评2天/复评×2.4），S 上限365天；评分后显示「下次复习：X」②展示即复习（抽进复习区即 reviewCount++，不点评固定顺延6h；**到期闸门防抖**：仅 now≥nextReviewAt 才计数——替代豆包提的固定24h防抖，24h 会把词卡在到期态霸占复习位18小时）③选词替换纯随机（到期词按遗忘风险R升序→新词→未来词）④单词本列表加「下次复习」行（已到期红/未学习灰）+排序3态（最新↓/最早↑/需复习↑）⑤算法纯后台隐藏（MemoryAlgorithm.ets，WordItem 加 strength/reviewCount/lastReviewAt/nextReviewAt 4字段，存量数据 normalizeMemoryFields 兜底）；**教训：①复习区缓存原按词库长度失效——加1词=全量重抽=几十次虚假复习，改按消息ID永久固定+读取时滤已删词②单位统一存「天」浮点（10分钟=0.00694天），防分钟/小时/天混用BUG**；完整算法文档 docs/0.165+/0.187.0 记忆算法与复习系统.md（含参数表+ArkTS核心代码+未来开放设置构思，用户要单独研究）|
|0.188.0|知识库复刻记忆算法+三角图标+AI报错诊断：①知识卡同款复刻——KnowledgeCard 加4记忆字段、pickReviewCards 遗忘曲线选卡、展示即复习、3档评分UI（气泡/提炼弹窗两处，评分区@Builder 泛化 MemoryItem=WordItem|KnowledgeCard 联合类型共用）②知识库列表加「下次复习」行+排序3态移顶栏右上角（单词库同款，用户要求右上角）③复习区图标 👆→▼/▲ 紫色三角（BRAND_SECONDARY 辅助紫=提示语义，UI_GUIDELINES 对齐；展开态 ▼转▲）④**streamChat 零内容流诊断**（extractStreamError：HTTP 4xx/5xx 的 JSON 错误体无 data: 前缀、此前被 SSE 解析器静默吞掉统一显示「AI 未返回文本内容」——真实原因 key失效/模型下线/限流 不可见；现零内容时解析原始体提取 error.message 走 onError 展示，合法SSE无error才维持通用提示）；**教训：requestInStream 无状态码校验，错误体与正常流同走 dataReceive——诊断要留原始体预览（rawPreview 600字符截断）**；用户报「AI 未返回文本内容」排查结论：非 v0.187.0 回归（发送链路未动），是火山侧变化+错误暴露缺陷，等真机复现看真实错误|
|0.189.0|本地TTS免费离线（CoreSpeechKit，用户拍板：云端火山TTS取消、仅本地）：①新建 LocalTtsEngine.ets——canIUse 探测+createEngine 懒创建（失败置 null 可重试）、splitTextForTts 分段（280字/段，自 ChatPage 迁入单一真相源）、首段抢占 queueMode1+后续排队 queueMode0 无缝连播、会话回调 onStart/onComplete/onError 用 **requestId 集合严格限定当前会话**（旧会话迟到回调一律忽略，免代际号）、stop 幂等；单例 localTts 供 WordSpeaker/ChatPage 共用=引擎级互斥②WordSpeaker 本地引擎化（HTTP合成→base64→临时文件→AVPlayer 链路全删，speak(word, onUnavailable?) 签名简化）③消息朗读直连本地引擎（云端分段管线 4 方法+11 状态全删，stopTTS 简化为停引擎+清状态）④**火山TTS配置存档 docs/0.165+/0.189.0 §9**（端点 openspeech 2.0/鉴权三件套/音色 bigtts/历史教训——用户找 URL 花了很久，恢复照抄+git 历史 be98570）⑤设置页音频字段保留休眠；**关键事实（SDK d.ts 实读）：文本上限 10000 字符（用户 AI 说的 500 是 API11 早期旧限制）、中英都支持（en-US Laura person8 需下载语音包=英文发音升级路径）、requestId 仅字母数字中文禁连字符、全设备引擎实例上限3、MatePad 11.5S活力版=HarmonyOS 7.0.0.109 API26 完全支持**；验收要点：断网发音朗读正常、长文连播无缝、英文单词发音质量试听（不合格→en-US 第二引擎）|
|0.189.1|口音联动+设置页TTS清理（用户批准方案+追加需求）：①**LocalTtsEngine 双引擎**——zhEngine（聆小珊 person13 内置）消息朗读 + enEngine（en-US Laura person8）单词发音真美式，设备实例上限3用2，两引擎 listener 共用会话跟踪器（requestId 全局唯一）②**listVoices 运行时查 Laura 状态**（命名空间级 API19+，INSTALLED/GA/EOM；清单不写死——华为未来上 en-GB/日/韩音色零代码升级，用户语言学习者方向的战略预留）③**downloadVoice 应用内下载**（单词库⚙弹窗「发音语音包」区：状态文案+下载按钮+进度；错误码 1002300010=已下载幂等处理）④**WordSpeaker 口音路由**——Laura 已装→en 引擎；美式+可下载未装→onNeedUsPack 提示（每会话一次，引导⚙下载）；英式→系统无 en-GB 音色（清单封闭仅3个：聆小珊/聆飞哲/Laura）→onNoBritishPack 一次性提示后照常播；未装→聆小珊兜底；hooks 由调用方 toast（单例无 UI）⑤**设置页音频 API 配置区整体删除**（用户指示）——GlobalSettingsDialog 音频三区+0.139迁移逻辑+僵尸 SettingsPage.ets 整文件+Index 路由注册（0.150起零入口）；**教训：ArkTS 严格模式 Record<string,Object> 对象字面量被拒（arkts-no-untyped-obj-literals）——须程序化构建 extra['key']=value；SpeakListener/SpeakParams 字面量须显式类型注解**|
|0.189.2|口音提示弹窗化+⚙弹窗排版重构（用户实测反馈两条）：①**英式无包提示 toast→AlertDialog**（用户强调：好不容易切英式却给美式发音是重要信息，toast 一闪而过太轻——弹窗「系统暂无英式语音包，当前将按美式发音播放」+确定按钮，用户偏好弹窗）②美式缺包引导同步弹窗化（「美式语音包未下载，发音将使用系统默认音色」+「去设置下载」引导⚙）③**showAccentDialogs(ui) 共用工厂**（WordSpeaker.ets 导出，返回 WordSpeakHooks——onNeedUsPack/onNoBritishPack 走 showAlertDialog、onEngineUnavailable 保持 toast；4 处调用点 ChatPage×3+WordBankPage×1 一行接入 `wordSpeaker.speak(text, showAccentDialogs(this.getUIContext()))`，单一真相源）④**单词库 ⚙ 设置弹窗三区卡片化**（原平铺堆叠灰字乱）——复习显示数量/音标口音/发音语音包各成 SURFACE_SOFT 底+RADIUS_CONTROL 圆角卡片+padding12，区块标题 14 半粗主色+描述 11 弱化，卡片内 TextInput 改 SURFACE_NODE 底与卡片形成对比，交互逻辑全保留|

## 版本号体系（2026-10-03 起）
- 首页显示版本号，每次改动编译装机递增末位；当前 **v0.189.2（versionCode 1000055）**
- 迭代文档命名：版本号 变更内容.md（如 0.185.0 音标口音切换.md；同功能迭代末位+0.1，验收后新需求次位+1，用户可直接指定版本号；规则详见 project_rule.md §7，2026-10-04 用户定稿）
- 版本线主文档：docs/0.165+/0.167.md（精简版，0.165+ 段；历史段 0.140-0.152/、0.160-0.164/ 归档，docs/index.md 为总索引）
- 真机测试设备：MatePad 11.5 S 活力版（平板，192.168.2.16 无线调试，2026-10-04 端口 33685）+ 畅享 90 Pro Max（手机，192.168.2.9 无线调试）；**2026-10-04 用户指示：装机测试用 pad，手机用户日常自用勿占用**

## 全局硬性约束
1. 代码清理规则：全部删除console/hilog调试打印；注释掉的大块死代码直接删除。
2. 开发流程：新增功能优先在docs新建md文档，确认方案后再写代码；全局重构/代码清理新开对话。
3. 网络请求：SSE流式请求支持Abort中断；对话不限制180s超时，仅提炼弹窗180s超时。
4. UI 开发以根目录 **UI_GUIDELINES.md** 为唯一设计真相源（色值/圆角/文字/间距/组件规格/布局），禁止在页面代码散落写色值；DesignTokens.ets 为 token 单一来源；大纲未覆盖场景按同组件规格类推，落地后回填。
5. MEMORY.md 记录从简（2026-10-04 拍板）：已完成的改动/功能只记一行结论（版本+一句话+关键教训），不记过程细节；仅两类保留完整记录——①未解决的 bug（排查链：根因/已排除假设/当前状态，解决后立即压缩为一行）②迭代 3 次以上的功能（定案前保留决策链）。原因：memory 是给 AI 看的，已做好的功能知道就行，只有未解决的问题才需要细节供 AI 续接。
