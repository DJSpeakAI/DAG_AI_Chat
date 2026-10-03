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
- UI：暗紫主题锁定暗色（方案A）；Pixso 设计稿落地中（0.167 线，canvas 已完成）

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
|0.167.x|Pixso设计稿落地线（canvas改造，v0.167.1~6）：UI_GUIDELINES.md+DesignTokens.ets双真相源、BBTreeCanvas全面改造（信息条/节点卡片150×68/缩放控件/弹窗换肤）；v0.167.2连线Canvas命令式绘制（**Path无viewport属性自动缩放commands是连线飞左上角真根因**）；v0.167.3子树占位法防重叠（siblingGap=40）+连线统一父下缘→子上缘垂直S；v0.167.4整体等比缩放（尺寸/线宽/端点全乘s）+缩放限幅方向感知（放大拦2.0/缩小拦0.05，修复锁死）+多根纵向堆叠（treeGap=120）+根x恒对齐；v0.167.5信息条不透明底板+新建按钮双态（小屏纯icon36）；v0.167.6小屏顶栏极简4图标（icon-only 30×30与⚙/➕等高、标题不渲染）+fitViewport topSafe排除底板（flat=80/tabs=128）——装机验证通过；**遗留：缩放放大恢复路径待补验（缩小已验0.566）、v0.167.5/6未git commit（最后提交停在0.167.4）、下一站侧边栏工作台→手机端B+C双模式、UI_GUIDELINES回填小屏顶栏与弹窗规格**；主文档docs/0.167.md（精简版）|

## 版本号体系（2026-10-03 起）
- 首页显示版本号，每次改动编译装机递增末位；当前 **v0.167.6（versionCode 1000017）**
- 版本线主文档：docs/0.167.md（历史线：0.165/0.164/0.163/0.162/0.161/0.160.md）
- 真机测试设备：MatePad 11.5 S 活力版（平板）+ 畅享 90 Pro Max（手机，192.168.2.9 无线调试）

## 全局硬性约束
1. 代码清理规则：全部删除console/hilog调试打印；注释掉的大块死代码直接删除。
2. 开发流程：新增功能优先在docs新建md文档，确认方案后再写代码；全局重构/代码清理新开对话。
3. 网络请求：SSE流式请求支持Abort中断；对话不限制180s超时，仅提炼弹窗180s超时。
4. UI 开发以根目录 **UI_GUIDELINES.md** 为唯一设计真相源（色值/圆角/文字/间距/组件规格/布局），禁止在页面代码散落写色值；DesignTokens.ets 为 token 单一来源；大纲未覆盖场景按同组件规格类推，落地后回填。
