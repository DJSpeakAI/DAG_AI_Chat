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

## PENDING 待开发任务
### 任务1：DAG链路回溯与10+15摘要滑动窗口上下文压缩
需求：从当前BubbleNode沿parentID回溯到根节点收集单分支消息，分支之间相互隔离。
压缩规则：消息总数＞25触发压缩；取最早10条生成LLM摘要，摘要作为system消息放头部，保留最近15条原始消息；≤25条不压缩。
BubbleNode新增historySummary字段（@Trace）保存摘要，子气泡继承父分支摘要。
修改文件：ChatModel.ets、ChatPage.ets
状态：pending

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
|0.160.1|秒表修复实测通过（isStreaming模式：@Trace isStreaming在messages赋值前置true→item初始Visible在树上，@Trace通知驱动后续切换；ArkUI V2铁律：ForEach item内visibility/if初始求值必须Visible，None/false组件被移出渲染树后通知永不到达；同帧内@Local变化同样驱动不了item内visibility）、占位文字重复两次修复（删占位行Row+删Markdown反向visibility，回归原始单通道渲染）、API key内置默认（上架前须删除）、模型列表精简为DeepSeek/GLM两款、首页版本号v0.160.1（版本体系0.160.x，每次装机递增末位，主文档docs/0.160.md）|
|0.161|学习数量设置：单词库顶栏⚙弹窗（1/2（默认）/3/自由输入1~20，PersistenceV2独立key learn-count-v1），驱动AI气泡生词区+提炼弹窗复习区词条数，缓存version双维度编码length*100+count（count≤20无碰撞）；0.161.2知识卡片数量设置：知识库顶栏⚙弹窗（1（默认）/2/3/自由输入，key knowledge-count-v1，默认1保持现状），getKnowledgeCard→getKnowledgeCards多卡化，两处复习区改ForEach多卡（每卡独立横向滚动行，与生词区同款，key `${idx}_${title}`）；秒表代码整体移除（三轮修复未达标，用户决定放弃；提炼弹窗读秒knowledgeExtractSeconds一套保留勿删）；首页v0.161.2，主文档docs/0.161.md|
|0.161.3|API Key外置：硬编码Key挪到resources/rawfile/config.json（.gitignore忽略不入库，源码可安全上传GitHub），apiKey/audioKey默认值改空串，EntryAbility启动loadContent前调loadBuiltinApiConfig读rawfile仅填空位（用户自定义Key优先不被覆盖；文件缺失catch静默走设置页自填）；TextDecoder用decodeToString（decodeWithStream已deprecated，API 12+）；.gitignore重建（原文件UTF-16脏字节损坏）；git历史仅1c338af（0.161.1）引入过Key且未推送（远程停在fd0666e/0.149）；config.json会打进HAP——上架/公开分发HAP前仍须移除；首页v0.161.3|
|0.161.4|推送修复：用户未先amend直接push被GitHub Push Protection（GH013）拦截（检测到VolcEngine Ark API Key在1c338af的ChatModel.ets:192），推送整体拒绝、远程仍停fd0666e、Key未泄露；三重根因与修复——①用户已提交42ee261使含Key提交卡历史中间amend够不着→git reset --soft fd0666e合并重写；②docs/0.160.md:12与0.161.md验证清单含Key明文（文档记录时写入）→脱敏为ark-****/****；③.hmos-debug/调试产物（解包HAP字节码/截图/控件树）被add -A收进提交→git rm --cached清出+.gitignore加规则；环境坑：本机git版本不支持--noedit（unknown option静默断链，分号后命令照跑掩盖失败），amend须用-m显式传消息；最终b79164d单提交（fd0666e→b79164d），git log -S两Key --all零命中、git grep HEAD零命中；GitHub报错unblock-secret链接绝对勿点（=允许Key公开）；首页v0.161.4|
|0.162.1|分支树杈icon+新建分支过渡动画：根因——addBubble非页面跳转，同页切currentBubbleStore三属性，@Computed currentMessages瞬间清空重载，刷屏过快空消息页无感知；改动——①底栏＋→🌿（emoji树杈，语义「另起一个树杈」，32×32圆角8样式不变，与✏️/🖼️ emoji风格统一）；②新增@Local msgAreaOpacity/branchAnimating；③addBubble链式animateTo：淡出140ms（EaseIn，模拟页面关闭）→onFinish里切气泡+清输入（清空重载发生在透明态看不见闪变）→淡入300ms（EaseOut，模拟页面打开）→解锁，总≈440ms落0.3~0.5s区间；④空态Column与消息List两分支根容器各挂.opacity(msgAreaOpacity)（不动布局层级）；防抖：branchAnimating播完前忽略重复点击，isLoading流式防御保留优先在前；切换在onFinish而非setTimeout（无定时器竞态）；首页v0.162.1，主文档docs/0.162.md|

## 版本号体系（2026-10-03 起）
- 首页显示 `v0.162.x`，每次改动编译装机递增末位（0.162.1 → 0.162.2 → ...）
- 版本线主文档：docs/0.162.md（0.161 线见 docs/0.161.md，0.160 线见 docs/0.160.md）
- 真机测试统一用平板（MatePad 11.5 S，用户常开）；手机用户日常使用勿动

## 全局硬性约束
1. 代码清理规则：全部删除console/hilog调试打印；注释掉的大块死代码直接删除。
2. 开发流程：新增功能优先在docs新建md文档，确认方案后再写代码；全局重构/代码清理新开对话。
3. 网络请求：SSE流式请求支持Abort中断；对话不限制180s超时，仅提炼弹窗180s超时。