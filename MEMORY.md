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
|0.163.1|代码块按钮纯icon化：用户嫌「⧉复制/自动换行/⤢放大」icon+文字按钮难看（文字长短不一宽窄不齐）；6处同款按钮全同步改造（CodeBlockView三键+表格放大键+代码/表格放大弹窗换行键，防一处纯icon一处带文字割裂）——去文字Text留纯icon（⧉/↩⇄动态/⤢语义自明），icon fontSize 11→13，固定24×22+justifyContent/alignItems Center（弃padding自适应根除宽窄不齐），三键间距统一margin right 6（原复制right6/换行无/放大left6混排），borderRadius4/深浅底色/边框全保留，语言标签（python/text/plaintext）非按钮不动；首页v0.163.1，主文档docs/0.163.md|
|0.163.2|App显示名定名DAG AI Chat（免md直接改）：桌面图标下一直显示默认「label」——根因=entry/src/main/resources/base/element/string.json的EntryAbility_label值为字面"label"从未改过；两处资源同步改名——①EntryAbility_label "label"→"DAG AI Chat"（module.json5的ability label=桌面图标名）；②AppScope/resources/base/element/string.json的app_name "DAG_AI_Chat"→"DAG AI Chat"（app.json5的label=设置/应用管理里显示名）；两处均只有base目录无多语言目录；bundleName（com.example.dag_ai_chat）不动（动了=新应用丢数据）；首页v0.163.2|
|0.163.3|App图标换成用户logo（深紫底+白气泡+DAG字样，1024×1024）+包名回退：源文件「1024-1024 LOGO.png」用户放项目根目录（已用完删除，文件名带空格bash引用须引号）；分层图标方案——logo整图作background层（裁圆后深紫底气泡DAG居中）+PowerShell System.Drawing生成1024×1024全透明PNG作foreground层（layered_image.json引用名不变无需改）；两处目录同步替换（AppScope与entry的media目录background.png+foreground.png）+entry的startIcon.png（启动页）一并换；**插曲：用户中途把bundleName改成com.example.dagaichat（去下划线）导致SignHap 00303074**（调试profile绑死com.example.dag_ai_chat，openssl解析.p7b实证），用户先选保留新包名等DevEco Studio签名Fix（File>Project Structure>Signing Configs>Fix需登录华为账号），但Fix始终未做成（.ohos/config无新材料、build-profile.json5未变），用户最终决策**改回旧包名**（最快解法：签名立即生效+设备旧数据保住），app.json5回退com.example.dag_ai_chat后编译BUILD SUCCESSFUL（SignHap 182ms直过）；教训：**bundleName勿动**（=应用身份=数据归属，调试签名profile绑死包名，改包名必须重配签名）；将来真要改包名：DevEco Studio签名Fix重配+接受数据从零+AGC创建新包名应用；首页v0.163.3|
|0.163.4|桌面短名DAG AI：桌面图标下「DAG AI Chat」太长被截断成「DAGAI...」；鸿蒙应用名双层结构——桌面图标名=module.json5里ability的label（优先级最高），设置/应用管理名=app.json5的label；改动——①entry string.json新增资源app_short_name="DAG AI"；②module.json5里EntryAbility的label引用从$string:EntryAbility_label改为$string:app_short_name（桌面图标下显示短名）；③app.json5全局label（app_name="DAG AI Chat"）不动（应用详情/AGC后台仍显示完整名，与桌面短名互不冲突）；EntryAbility_label资源保留不删（改引用后无人用但无害）；装机注意：**覆盖安装有时不刷新桌面label，卸载重装才一定刷新但清数据（对话树/词库/知识库）**——先覆盖安装+重启桌面试，不行再权衡卸载重装；首页v0.163.4|
|0.163.5|桌面短名DAG AI→AI Chat（免md微调）：用户装机验证0.163.4生效（截图桌面已显示「DAG AI」不截断）后拍板改名——logo图标里已有DAG字样，桌面再说DAG重复麻烦；改动极小仅一处——entry string.json里app_short_name值"DAG AI"→"AI Chat"（module.json5的label引用$string:app_short_name不动，app_name="DAG AI Chat"应用详情名不动）；装机注意同0.163.4：覆盖安装可能不刷新桌面label，先覆盖安装+重启桌面试；首页v0.163.5|
|0.164.1|华为账号登录（云同步第一步，Account Kit）：官方文档查证后定方案——授权请求createAuthorizationWithHuaweiIDRequest+scopes=['openid','profile']（个人开发者可用无需申请权限，纯客户端直接拿nickName/avatarUri/openID/unionID无需服务端），退出=createCancelAuthorizationRequest取消授权；公钥指纹无需配置（compatibleSdkVersion 24≥20官方免配）；新建utils/HuaweiAccountUtil.ets（HuaweiAccountStore持久化PersistenceV2 key'huawei-account'，loginWithHuaweiID/logoutHuaweiID返回空串=成功非空=中文错误提示，errorToTip官方错误码映射1001502001未登录/1001502005网络/1001502012取消/1001500002重复/1001500001指纹/12300001系统，state一致性校验generateRandomUUID防跨站）；Index.ets进入对话画布下方加登录区（未登录=蓝色华为账号登录按钮，已登录=昵称或ID前10位+退出账号小按钮，isProcessing防连点，loginTip红字提示，深浅色适配）；module.json5加metadata client_id（**已配置真实值6917618071300773117**）；AGC应用创建成功——包名com.example.dag_ai_chat被接受（com.example前缀风险解除，0.163.3教训未触发）；**新版AGC中Client ID与APP ID是同一个值**（官方文档：相同则无需单独配置Client ID，用户在AGC界面看到的标签叫"APP ID"）；替换后重新编译BUILD SUCCESSFUL（0新增警告）；**待用户装机实测登录**：点华为账号登录→拉起授权页→显示昵称+退出按钮；若报1001500001指纹校验失败需在AGC补配调试证书SHA256公钥指纹（25小时生效，改versionCode可提前生效）；首页v0.164.1，主文档docs/0.164.md|
|0.164.2|修复装机实测1001502003（登录参数异常）：根因——'openid'是**默认scope无需显式传**（官方注释原文「'openid'为默认值可不传」），原scopes=['openid','profile']组合**无任何官方示例支持**，触发服务端参数校验失败；官方错误码表1001502003=SIGN_IN_PARAMS_ERROR/PARAMETER_INVALID「输入参数值无效」；正确写法scopes=['profile']（官方获取头像昵称示例），openID/unionID由AuthorizationWithHuaweiIDCredential**默认返回**无需显式申请openid；排除项forceAuthorization=true与state=UUID均官方标配非问题源；改动——HuaweiAccountUtil.ets scopes修复（含★注释）+errorToTip补1001502002应用未授权/1001502003参数异常/1001502009内部错误三条中文提示，Index.ets v0.164.2；编译BUILD SUCCESSFUL 0新增警告；**装机实测仍报1001502003**（新文案证实已装v0.164.2新包）→**scopes修复无效，scopes非根因**；已排除：scopes组合/forceAuthorization/state格式/装错包/编译问题；**排查未完中断（会话内存问题），交接文档=docs/0.164.md「0.164.3排查计划」章节，新会话从那续接勿重查**——嫌疑清单：①permissions=['serviceauthcode']缺失（官方获取头像昵称示例带此字段，最大嫌疑）②client_id配置位置格式（当前module层metadata）③AGC侧未开通华为账号服务④debug签名公钥指纹⑤设备服务版本；下一步：重读account-get-avatar-nickname看前提条件→查配置ClientID文档→查FAQ系列→设备日志；下次代码改动版本号v0.164.3；完整错误码速查表见docs/0.164.md；首页v0.164.2，主文档docs/0.164.md|
|0.164.3|华为登录1001502003根因收口（免md续接排查）：errorcode-account-kit官方文档1001502003可能原因4条中第2条**「Profile文件无效」**命中，处理步骤原文「请在AGC重新申请Profile文件并重新签名」；**时间线实证**——调试Profile生成于2026-09-19 19:35（.ohos/config文件时间戳），AGC应用创建于2026-10-03，**Profile比应用早生14天**→Profile与APP ID=6917618071300773117无关联→服务端无法把安装包关联到AGC应用→报「Profile文件无效」；完美解释0.164.2所有代码修复无效（问题不在代码在签名Profile）；本轮排除（勿再查）——permissions缺失（官方注释明说仅服务端开发需要）/client_id配置格式（与官方配置Client ID文档逐项一致）/AGC未开通服务（获取头像昵称开发前提明示无需申请账号权限）/debug公钥指纹（compatibleSdkVersion≥20免配，且指纹错误报1001500001非1001502003）/context传参（getHostContext与官方示例一致）/必填字段遗漏（API参考字段表全部可选）；**修复=用户在DevEco重新生成自动签名**（旧签名文件已由AI备份至C:\Users\Administrator\.ohos\config-backup-20261003\并清空config目录，强制DevEco重新生成新Profile关联AGC应用）：File>Project Structure>Signing Configs>取消勾选自动签名Apply>重新勾选>登录华为账号>自动生成>重新编译装机；**装机必须先卸载旧包**（新调试证书与旧包签名不一致，覆盖安装会失败；卸载清本地数据开发阶段可接受）；备选方案（重新自动签名后仍报错时）：AGC用户中心>证书、APP ID与Profile>Profile>新增调试Profile（选应用com.example.dag_ai_chat+调试证书+调试设备）>下载.p7b>DevEco手动签名；代码改动仅版本标识——Index.ets v0.164.3+app.json5 versionCode 1000000→1000001；编译BUILD SUCCESSFUL 0新增警告；待用户重新签名后装机重测；首页v0.164.3，主文档docs/0.164.md|
|0.164.4|重新签名后仍报1001502003+错误码上屏（用户提议）：用户完成DevEco重新自动签名（10-03 20:21新Profile生成，.p7b 4181→4182字节）→删旧包新签名装机→**仍报「登录参数异常」**（该文案=1001502003分支专属→错误码未变）；**重大发现（openssl解析.p7b内JSON实证）**——新旧Profile的app-identifier均=**6918742736119759756**，而module.json5的client_id（=AGC APP ID）=**6917618071300773117**，**两者不匹配**；推论：09-19首次自动签名时DevEco自动创建了AGC应用（6918742736119759756），10-03用户手动创建另一个（6917618071300773117），Profile绑前者client_id配后者→服务端校验不匹配→1001502003持续；改动——①errorToTip所有提示附【code=xxx｜服务端原始message截断200字符】+console.error日志（DevEco Log窗口可见）②Index.ets loginTip maxLines 2→8③首页v0.164.4④versionCode 1000002；编译BUILD SUCCESSFUL 0新增警告；**待装机（签名未变覆盖安装即可）截图完整错误信息+AGC核实**：我的项目是否存在APP ID=6918742736119759756应用及其包名、手动创建的6917618071300773117应用包名是否com.example.dag_ai_chat；修复方向二选一（视核实结果）：client_id改6918742736119759756 或 AGC手动申请绑定6917618071300773117的调试Profile；首页v0.164.4，主文档docs/0.164.md|
|0.164.5|根因闭环+client_id对齐Profile（方向A快路）：装机截图实证（0.164.4错误码上屏生效）——红字完整显示**【code=1001502003｜Invalid input parameter value. Invalid clientId or profile.】**，服务端message直指「Invalid clientId or profile」与openssl解析发现完全吻合，根因链闭环=安装包Profile的app-identifier（6918742736119759756，DevEco首次自动签名自动创建的应用）≠代码client_id（6917618071300773117，用户10-03手动创建的应用）→服务端校验两应用非同一个→报1001502003；AGC截图证据——项目DAG AI Chat Project（ID 101653523865204271）、应用6917618071300773117包名com.example.dag_ai_chat、OAuth Client ID=APP ID同值、项目级Client ID=2053081307533017088（项目凭据与本场景无关勿混淆）、指纹未配置（≥20免配结论仍立）；**修复=module.json5 client_id 6917618071300773117→6918742736119759756**（对齐Profile app-identifier，一行代码最快验证）；Index.ets v0.164.5+versionCode 1000003；编译BUILD SUCCESSFUL 0新增警告；**待装机（签名未变覆盖安装即可）**：v0.164.5→点登录→预期拉起授权页；若仍报错走方向B（AGC用户中心>证书、APP ID与Profile>新增调试Profile选应用6917618071300773117+调试证书+设备>下载.p7b>DevEco手动签名+client_id改回）；A成功后的长期决策：直接用6918742736119759756（需去AGC找到该应用确认可管理）或走B换回自管应用；首页v0.164.5，主文档docs/0.164.md|
|0.164.6|方向A证伪→方向B（AGC手动申请调试Profile+手动签名，官方唯一指定路径）：装机实测v0.164.5**仍报1001502003同样错误**→方向A死刑——6918742736119759756不是有效Client ID，**DevEco自动签名走内部「调试应用」通道**（非正常AGC应用无Client ID），自动签名+Account Kit登录这条路走不通；官方errorcode-account-kit 1001502003处理步骤2原文「请在AGC中重新申请Profile文件并重新签名。调试阶段请参考申请调试Profile，完成Profile申请并重新**手动签名**」——注意是「手动签名」非自动签名；「申请调试Profile」文档要点：一应用最多100个Profile、申请成功即生效、须选调试证书（不支持发布证书）、最多100设备、可能提示配公钥指纹可忽略（≥20免配，报1001500001再配）；本轮改动（方向B代码侧就位）——module.json5 client_id改回**6917618071300773117**（★0.164.6注释）+Index.ets v0.164.6+versionCode 1000004；编译BUILD SUCCESSFUL 0新增警告；**用户已完成AGC申请**（20:48放入C:\Users\Administrator\.ohos\config\dag_ai_chat_debugDebug.p7b，4181字节）；**AI侧关键决策=只换Profile不换证书已执行**：build-profile.json5的profile字段指向新.p7b（含★0.164.6注释），certpath/storeFile/storePassword/keyPassword全不动（绕开用户不知道.p12明文密码问题，自动签名生成的是加密串）；**三重实证闭环**——①新.p7b二进制grep出app-identifier=6917618071300773117✅②编译BUILD SUCCESSFUL 2s359ms（SignHap 161ms通过=新Profile与现有证书/密钥库配套成功签名链完整）③HAP整包二进制grep内嵌签名Profile app-identifier=6917618071300773117✅——安装包Profile与代码client_id**首次完全指向同一AGC应用**，1001502003「Invalid clientId or profile」根因（两者不匹配）物理消除；**待装机**：覆盖安装（签名证书未变应该可以，失败卸载重装）→首页确认v0.164.6→点「华为账号登录」预期拉起授权页→授权后显示昵称+退出账号→杀进程重启登录态保持；**装机失败插曲（9568289权限授予失败，新根因已闭环）**：装机报code:9568289｜grant request permissions failed｜PermissionName: ohos.permission.READ_PASTEBOARD——grep新旧.p7b权限段对比实证：旧自动签名Profile的allowed-acls=["ohos.permission.READ_PASTEBOARD"]✅、新AGC手动申请Profile的allowed-acls=[]❌空的；根因=READ_PASTEBOARD是**受限权限**须Profile的ACL显式授权，DevEco自动签名自动带上、**AGC手动申请调试Profile界面有「选择申请权限」步骤用户未勾选**→安装时授权失败；module.json5共2权限：INTERNET（normal无需ACL）+READ_PASTEBOARD（受限需勾）**只需勾这一个**；修复=用户回AGC重新申请Profile（同流程+「选择申请权限」步骤勾选ohos.permission.READ_PASTEBOARD）→下载新.p7b放入config→AI侧grep验证allowed-acls含READ_PASTEBOARD且app-identifier仍=6917618071300773117→改profile路径（若文件名变）→编译→装机；装机错误码预案：1001500001=指纹→AGC补配调试证书SHA256（25h生效改versionCode重装可提前）、1001502012=用户取消（正常）、其他查docs/0.164.md速查表；首页v0.164.6，主文档docs/0.164.md|
|0.164.7|9568289最优解：删除误加的READ_PASTEBOARD权限申请（免ACL审批）：用户AGC截图揭示READ_PASTEBOARD的ACL申请**需人工审批3个工作日**且「使用场景」必填（下拉六选项：银行卡号复制/口令复制/文档编辑类/输入法/flutter开源框架/例外场景，无一匹配AI聊天应用）——若走此路登录验证阻塞3天+通过率存疑（华为审核逻辑：能用PasteButton粘贴控件的场景不批ACL）；**决定性代码审查推翻前提**：grep全项目pasteboard仅2处调用**全是setData（写剪贴板：ChatPage.ets:157划词复制+1362长按复制）、无任何getData（读剪贴板）**；鸿蒙剪贴板权限机制**非对称**——写剪贴板（setData）不需要任何权限、读剪贴板（getData）才需要READ_PASTEBOARD（受限须Profile的ACL授权）；**结论=该权限属早期误加，申请了但代码根本没用到**，删除后复制功能零影响、无需等ACL审批；改动——①module.json5删READ_PASTEBOARD权限申请（requestPermissions只留INTERNET，含★0.164.7根因注释）②string.json删read_pasteboard_reason资源③Index.ets v0.164.7④versionCode 1000005；编译BUILD SUCCESSFUL（2s627ms，0新增警告）+HAP内module.json实证requestPermissions只剩INTERNET删干净；**现有dag_ai_chat_debugDebug.p7b（allowed-acls空）即可安装**（不再申请受限权限无需ACL授权）；待装机：v0.164.7→点登录预期拉起授权页→顺带验证复制功能正常（写剪贴板无需权限）；遗留决策：未来若真需读剪贴板（如粘贴文本到输入框）优先用PasteButton粘贴控件（免权限官方推荐），仅当无法用控件才走ACL申请；首页v0.164.7，主文档docs/0.164.md|

## 版本号体系（2026-10-03 起）
- 首页显示 `v0.164.x`，每次改动编译装机递增末位（0.164.1 → 0.164.2 → ...）
- 版本线主文档：docs/0.164.md（0.163 线见 docs/0.163.md，0.162 线见 docs/0.162.md，0.161 线见 docs/0.161.md，0.160 线见 docs/0.160.md）
- 真机测试统一用平板（MatePad 11.5 S，用户常开）；手机用户日常使用勿动

## 全局硬性约束
1. 代码清理规则：全部删除console/hilog调试打印；注释掉的大块死代码直接删除。
2. 开发流程：新增功能优先在docs新建md文档，确认方案后再写代码；全局重构/代码清理新开对话。
3. 网络请求：SSE流式请求支持Abort中断；对话不限制180s超时，仅提炼弹窗180s超时。