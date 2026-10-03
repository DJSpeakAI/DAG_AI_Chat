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

## 版本号体系（2026-10-03 起）
- 首页显示 `v0.165.x`，每次改动编译装机递增末位（0.165.1 → 0.165.2 → ...）
- 版本线主文档：docs/0.165.md（历史线：0.164/0.163/0.162/0.161/0.160.md）
- 真机测试设备：MatePad 11.5 S 活力版（平板，主测试机）+ 畅享 90 Pro Max（手机，云同步多设备测试用）

## 全局硬性约束
1. 代码清理规则：全部删除console/hilog调试打印；注释掉的大块死代码直接删除。
2. 开发流程：新增功能优先在docs新建md文档，确认方案后再写代码；全局重构/代码清理新开对话。
3. 网络请求：SSE流式请求支持Abort中断；对话不限制180s超时，仅提炼弹窗180s超时。
