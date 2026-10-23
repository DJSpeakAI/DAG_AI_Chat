# Project Memory（活规则层）
> ★ 2026-10-22 冷热分离治理（同日二次治理）：本文件只放「每次会话必须注入的活规则+当前状态」，目标 ≤20KB；历史迭代简表全量在 docs/MEMORY_HISTORY.md（AI 默认不读，查历史 grep 版本号定位）。
> 新条目写入前自问（CONTEXT_MANAGEMENT 规则 3）：这条下次会话必须知道吗？否→docs/ 迭代文档或 MEMORY_HISTORY.md；已完成改动只记一行结论（版本+一句话+关键教训）。
> ★ 上下文自律与 Prompt 军规见 docs/CONTEXT_MANAGEMENT.md（project_rule.md §8 强制引用）。

## FACT 项目固定基线
1. DAG气泡树项目架构
   BubbleNode 结构：携带parentID（单父模型），节点内部保存 messages: ChatMessage[]。
   技术栈：鸿蒙 ArkUI V2，结构体使用@ObservedV2，新增字段必须添加@Trace。
   页面与组件：BBTreeCanvas.ets、ChatPage.ets、WordBankPage.ets、KnowledgeBankPage.ets、ReviewPage.ets、GlobalSettingsDialog.ets；ApiClient.ets 负责 AI 流式请求（多提供商）。

2. 已定型核心功能清单
- 气泡树对话、流式API、多模态图片上传、本地持久化(PersistenceV2)
- Markdown渲染（含行内格式——utils/MdInline.ets 纯函数+ohosTest 断言），代码块语法高亮，代码块自动换行按钮左对齐
- 图片全屏预览，屏幕圈选截图，图片提炼知识卡片
- 划词翻译、单词库生词复习、知识库卡片管理、知识复习页（ReviewPage，Anki 式单卡）
- TTS语音朗读（本地 CoreSpeechKit 双引擎，云端双引擎失败回退），单词发音单例复用，缩略词播全称
- LaTeX数学公式本地渲染（parse 层剥定界符），画布自动排版
- 全局设置弹窗：API提供商化（华为MaaS/火山方舟/DeepSeek 预设+自定义）、AI偏好、云同步、SP/账单、关于
- 学习统计页（StatisticsStore 按天聚合，只增不减）；流式渲染 ForEach Key 防碰撞；返回键弹窗优先
- 华为账号登录（Account Kit 纯客户端授权，AGC 应用 6917618071300773117）
- 云同步（RDB+cloudSync 快照行模式；与登录态同开同关）
- ~~订阅体系~~（★ 2026-10-22 拍板**订阅概念整体退役**：商业口径只剩 SP 司忆点；SubscriptionStore/freeTrialStart/isVip 等代码尚在=待后续迭代清码，新功能一律不得再引用订阅语义；SP/等级/充值包=账号级资产跟账号走，多账号切换须隔离——0.293.0 落地）
- 司枢模式 2.0（0.290.0 框架先行两段式：规划器→执笔；性格测试 3.0 纯选择题灌画像）；联网问答（0.292.0 FC 工具循环）；AI 读网页/文档加载（0.286/0.291.2）
- 好奇宝宝新手任务体系（0.294.0：七任务+挂账补发+完赛奖，全案见 docs/0.165+）
- UI：暗紫主题锁定暗色；Pixso 设计稿 canvas 线已落地；四主页面背景 BG_CANVAS；UI_GUIDELINES.md+DesignTokens 双真相源
- 编译优先级：本地鸿蒙 PC DevEco 优先；本地失败才切 Windows 服务器（build-server.ps1）
- 测试台交互双轨：用户自用=双击桌面「启动测试台.sh」全自动；AI 驱动=对话里说跑什么，AI 全自动起查盯报；唯一人工=华为授权弹窗

## PENDING 待办与待验收
**★ 代理提醒权益重申（0.302.1）**：首次申请被驳（缺设置场景截图）→ GSD 已补提醒设置区块+截图在桌面「AI交接/代理提醒-设置场景截图.jpeg」；**等用户带截图重新提交 AGC 申请（入口：项目设置→开放能力管理→代理提醒）；通过后必须重建 Profile+重新签名才真正生效**（connect API 通道，见约束#18；获批前 publishReminder 1700002 静默降级零影响）。
**★ 0.300.0 司枢 Agent 3.0 待装机验收（六场景=任务书 §九）**：①「去华为官方查 App 上架资质」零点击自动搜索开网页带资料回答；②喂文档+「优化后发华为开发者论坛」=论坛帖体裁成品可整体复制零分析腔/只说「帮我优化一下」=先反问选择题；③司枢+联网同开不互斥；④模糊需求 1 轮 1~3 题反问/明确需求绝不反问；⑤全程 SP 逐轮可见+取消按已耗结算；⑥成品卡一键切形态立即重写。⚠️御史轮/枢机契约链未经真机验证（build 绿≠链路对）——真机异常先查 PLAN3 契约解析与 streamChat 尾参错位高危区。
**★ 0.299.2.x 云同步战役战果（2026-10-23）**：三端（PC/Pad/手机）SP 200 万全等一致 ✓；bug1/bug5 已根治（根因链全案 grep HISTORY 0.299.2/0.299.2.2）。**连带待修**：①bug6 老账号重装误弹「新用户礼包」仪式弹窗（发放幂等未双花，判定与 merge 顺序竞态）②bug7 本地空 api-config 以新时间戳 LWW 压制云端好配置（mergeCfgs apply 通道对空值零防御）③手机仍在 0.293.0 待升级（盘值 warn 尾巴）。备份：/data/storage/el2/base/temp/deveco/pcdb-backup/（P2 4MB+旧 RDB 9MB）。
**★ 0.301.2 已解：181「登录 SP 为 0」**=PC 云同步下行缺片致闸门永锁（本地 0 非云端无行）——卸载重装+礼包补发 200 万（gift 池）+数据台验证指令 2 万到账；同时修 bug8（cloud-sync-switch P2 水合失败，影子通道）。
**★ bug4/bug3 待现场采集**：bug4 桌面卡片「继续复习」pill 无反应（卡片端 sendContinue/gate 正常、断点疑在 call 通道中段——待采集 `hdc shell hilog | grep -iE 'form|widgetContinue'`）；bug3 新账号云端下两个幽灵根气泡删除无效（需用户发气泡内容截图定性）；bug5 影子通道三台冷启回归抽查（Pad 已实测 ✓）。


**软著遗留**：提交版锁定 0.235.0（versionCode 1000260，commit be9669d）；git 快照分支 v0.235（⚠️ 推 GitHub 失败 publickey，待用户手动 `git push origin v0.235`）；生成脚本可复用 `/data/storage/el2/base/temp/deveco/pdfwork/`。
**★ 0.293.0 SiyiGate 验收余项**：场景①一端签到→三端均显示已签未显式测（其余三场景已随 0.299.2.x 战役隐式覆盖——冷装不重发/门卫引导/新账号礼包链路均已实走）。三台已装。
**★ IAP 退款对账云函数方案（上架前必做）**：AGC 云函数收 REFUND_TRANSACTION→Cloud DB 记退款单→客户端三时机拉退款标记自动核销；云函数须立即返 200+幂等；配套服务端七年 refunded 对账 API。详见 MEMORY_HISTORY 0.291.0/0.290.1 行。
**备案四线（docs-2026.10.22c，等审核）**：ICP 沪ICP备2026055703号-1 已过；官网 dagaichat.com 已上线（源码 website/）；公安联网备案+App 备案（阿里云订单 2030863653111，包名 com.dagaichat.app）已提交待审（≤30 自然日）→备案号下来填 AGC 提审。桌面证书材料已归档配置/signing/（release .cer/.pem/.p7b 勿删）。
**华为工单 D648175**（Pad 最大化自由窗口 NavDestination 左侧黑块）：补充材料包已交（桌面 D648175Demo/ 等），等华为人工回复；**工单闭环后删 D648175Demo 目录与桌面材料包**。
**复习「永远有卡可学」重构（0.200.1 讨论稿）**：buildQueue isDoneToday 一刀切 bug 未修（当日背完再新增的未学习卡被拍进完成页）；全案 docs/0.165+/0.200.1.md。
**记忆引擎一期验收**：0.265.0 已完工，待装机 S1/S2 场景脚本+升级回滚测试；画像云同步转人工（CloudSyncUtil 红线）；新 key 三个+personality-quiz-v1 **均待补录 config.autofix.redlineKeys**。
**云同步遗留小项**：del 标记行传播真机一键验证；僵尸气泡清污待用户画布手动删。0.229.x 测试台系列已全量归档 MEMORY_HISTORY；测试台铁律见 project_rule §12。
**⚠️ 未实测遗留**：0.292.0 腾讯云 tools 透传与 Bing 反爬未真机验证；0.291.2 腾讯云 OCR FileType 枚举/Describe 字段名多键防御式未实测（真测报错先查这两处）。

**★ 钩子模式（两段式长回复）SP 军令（开发前必读 docs/0.165+/0.251.0 第三节）**：两段 token 累加实扣（两次 onDone 累计一次性 consumeSiyiSp）；凡 AI 交互必扣必展示（实扣走 spCostOf 同源公式，禁止隐性扣点；对外禁 token 字样）；②段失败=内容保留本地降级。

## 版本迭代简表（仅最近版本·一行结论制）
> 全量简表 0.1~0.296 见 docs/MEMORY_HISTORY.md（grep 版本号定位）；详细全案见 docs/（总索引 docs/index.md）；文件级教训见 AOCI_INDEX.md 速查层 ⚠S 字段（完整版 docs/AOCI_DETAIL.md）。

|版本|核心能力 / 关键教训|
| ---- | ---- |
|0.302.1.1|✅**测试台板块拆分+看板 AI 数据源**（用户拍板三选择：页内切换+内嵌/本轮做 AI/SP 台挪走）：测试台顶部一级切换「🧪测试台/📈后台数据」，iframe 内嵌阿里云看板；dashboard-v2/server.js 新增 syncUsers（SpMirror 全量+SpLedger 增量）+usersAggregate 注入 AI 快照（注册数/rookie 完成完赛/近 6 周表）——本地冒烟真连 Cloud DB 绿。**✅0.302.1.2 两修**：切换钮挪顶栏凸出胶囊；dataView 漏挂一屏化约束致底部被裁（**教训：新 wrap 容器必须继承一屏化约束**）。**✅0.302.1.3 合版定稿**：①治本 iframe 登不进=浏览器 SameSite 拦第三方 Cookie→看板鉴权三通道（Cookie+X-Dash-Token 头+?k= query，login 返 token 跳 /?k=，前端 fetch 包装+localStorage 分区存储——冒烟全绿含 401）②看板更名「DAGAI 后台数据」+SP 数据台并入（⑦ Tab 四路由平移自测试台 0.301.0.2）③测试台 SP 面板/函数/三路由全删纯测试化。**待办：用户照桌面 AI交接「后台数据合版部署指引.md」上传 server.js+index.html 两文件**；若口令仍进不去→grep 服务器 config.json password（当年可能改过）。周新增精确口径需 SpMirror 加 createdAt（下版 app 侧）。**✅0.302.1.4 用户实测两反馈修复**：①内容区 max-width:1500px 大屏两侧留白→改全宽自适应（.wrap 去 max-width；**教训：一屏化+定宽混用=大屏难看**）②看板口令每次重输→loginPage 加 localStorage token 自动跳转（存过一次免输；冒烟绿：登录页含 location.replace('/?k=')+token 取首页 200），增量部署只传 dashboard-v2/server.js|
|0.302.1|✅**全局设置加每日复习提醒区块**（代理提醒权益 AGC 驳回补场景——审核要「APP内用户主动设置提醒的截图」）：GSD 司忆区 Tab 新增「每日复习提醒」Toggle 开关+提醒时间 19~22 段选，复用 ReviewReminderStore 单通道+refreshReviewReminder 即时生效（不走底部保存）；PC 截图已存桌面「AI交接/代理提醒-设置场景截图.jpeg」待用户重新提交 AGC 申请（**通过后须重建 Profile+签名**，走 connect API 通道）。三台 1000444 ✓|
|0.302.0|✅**SpLedger 事件流水**（运营侧事件级账目——「内容看不到、动作全有数」）：ChatModel 五收口全埋点（consumeSiyiSp 消耗含三池明细/签到/礼包/IAP/grantBonusSp 含 admin·rookie·quiz）；SpLedgerEntry 内存缓冲（≤50 有界）搭镜像上报便车批量上行（快照长度内成功才清防竞态）；云函数 handleReport 顺带入库（**SpLedger 表未建时流水 upsert 单独 try-catch 静默——不影响镜像主链**，2002007 实测）；测试台 /api/sp/ledger+SP tab「事件流水」表（时间/事件/来源/数额/池/事后余额）。**全链已验证（2026-10-23 19:33）**：welcome+200万与 admin+1000 两笔流水自动入库（缓冲把重装期礼包也补带上）。三台 1000443 ✓|
|0.301.2|✅**SP 数据台端到端打通**（真机全链：测试台下指令→app 冷启拉取→闸门→执行→confirm done→镜像余额 2,020,000）。三连修：①**bug8 云同步开关 P2 水合失败**（cloud-sync-switch 盘 true 运行时恒 false——bug5 huawei-account 同族黑盒）→ 新 utils/CloudSwitchShadow.ets 影子通道（preferences 记开过+P2 文件直读迁移+启动/回前台恢复；GSD 两关闭入口写影子 false 防与用户意愿打架）；②AGC SDK 异步初始化抢跑（callFunction 报 not initialized）→ SpAdminUtil 1.5s×3 重试；③**账号标记运行时为空**→spAccountMark 兜底 unionID/openID。**181 SP 显示 0 真凶=云同步下行缺片致闸门永锁**（本地 0 而非云端无行）；PC 卸载重装后礼包补发 200 万（gift 池）+验证指令 2 万到账。S 坑：云函数 callback 单参数（MEMORY #20⑤）；PC 副屏点击不支持 uiInput -d（须主屏操作）。三台 1000442 ✓|
|0.301.1|✅修 Index 侧边栏版本号硬编码 bug（**0.293.0 起 Text('v0.293.0') 漏更七版**——装机实测 UI 显示旧版吓人；GSD APP_VERSION 改 export 单一来源+Index import 自动跟，版本同步点两处制→三处制修正）；**SP-AUDIT 实锤 PC 未登录+本地 RDB 零行**（登录态丢失=云端脱钩体感根因，待用户重登验证拉齐）；云函数依赖 ZIP 两枚已打桌面（依赖层+全量）。三台 1000441 ✓|
|0.301.0|✅**SP 数据台**（方案 A 运营旁路，用户拍板「查任意华为账号 SP/下发指令/合并进测试台」）：新 utils/SpAdminUtil.ets（纯传输层**零 import ChatModel**——0.223.0 防环军令；callFunction report/fetch/confirm 三 action）+ChatModel 尾部区块（markSpAdminDirty 挂 scheduleRowFlush 统一入口+**快照指纹比对**防抖 8s——词卡变更误触发被指纹拦；pullSpAdminCommands 指令执行走 grantBonusSp/consumeSiyiSp 既有收口=gate 防御/埋点继承；gate 未就绪不 confirm=云端 10 分钟超时回收重派）+EntryAbility.onForeground/onBackground+BillingPage 进场三时机+云函数 docs/cloud/sp-admin/（Cloud DB SpMirror/SpCommand 两表+原子 claim+HTTP X-Admin-Token 鉴权；**未部署=全链静默零影响**，部署指引在手把手用户 AGC 操作后 config.json spAdmin.fnUrl/token 即通）+测试台 0.301.0.1（📊 SP tab：查询/最近账号/下指令/流水表+SP-ADMIN-LINK 用例）。**S 坑：bm dump 首个 versionCode 匹配是空值条目——精确 grep '"versionCode": 1000xxx'**；claim 竞态毫秒级窗口=一期已知边界（流水可查人工 deduct 补偿）。三台 1000440 ✓|
|0.300.0|✅**司枢 Agent 3.0 V1**（三角色流水线：枢机契约→执笔→御史，全案=桌面任务书已执行归档 docs/0.165+/0.300.0）：前置验证双绿（**FC+thinking 同请求兼容实锤=0.292 互斥解除**；cn.bing 5/5 稳/www 域 302→searchWeb 改 cn）；TaskContract 契约层（新 common/SishuAgent.ets，会话级不持久化）+PLAN3/buildDeliver/CENSOR 三 prompt+ClarifyCard 反问卡（点选流仿性格测试）+交付卡一键纠偏（存档契约切 form 跳枢机重跑+preferences 纠偏历史注入枢机）+御史 1 轮打回降级告知+SP 分阶段透明（finalizeStream 全并账）+sishu_* 六埋点+经典模式灰度（新 key 'sishu-classic-v1' **待补录 redlineKeys**）+联网胶囊两态 auto/force+预路由正则。**S 坑：preferences 读值是 getSync 非 getStringSync（编译错实锤）**；坑2=streamChat 尾参 tools 位与 thinking 位易错位（参数超长必逐位核对）；坑3=反问挂起用回调恢复非顶层 await（流异步完成前检查必假）；ChatPage 新增 ~700 行全案细节见迭代文档|
|0.299.2.x|✅云同步战役收官（0.299.1 五 bug 首轮/0.299.2 bug5 登录态影子持久化/0.299.2.1 sp 七用例+人工审批项 A1~A5/0.299.2.2 bug1 卸载重装根治——三端 SP 200 万全等一致）。**S 坑活用**：busybox grep 无 \{n,m\} 量词（-E 也不支持）；P2 盘真实路径=haps/entry/files/persistent_storage。全案 grep MEMORY_HISTORY 0.299 各行|
|2026-10-23 文档治理|✅AOCI 两层拆分（INDEX 82.9→27.4KB 速查层全量可读+docs/AOCI_DETAIL.md 83.3KB 保真；新增功能域→文件映射表；S→⚠S 砍叙事留结论）+MEMORY 瘦身回线（简表 0.293~0.296 全量下沉 HISTORY 零删改、PENDING 压缩）+AGENTS 增「跨 AI 交接协议」（桌面「AI交接」文件夹=外部 AI 方案交接区，.ets 改码归本 CLI）|

- 版本号纪律：当前 **v0.302.1（versionCode 1000444）**；**★ 0.301.1 起版本同步回三处制**：app.json5 + GSD APP_VERSION（已 export）+ Index 侧边栏（读 GSD 单一来源自动跟）——0.292.1「两处制」认知作废（实锤 Index.ets 824 行 0.293.0 硬编码漏更七版的第四处）；versionCode 每版 +1，定号唯一依据=app.json5 实读（多 AI 并行定号规则见 project_rule §7）
- 迭代文档命名：版本号 变更内容.md（详见 project_rule §7）
- 真机测试设备（阵容与账号分工定稿）：**三件套常测试=鸿蒙 PC（本机）+ MatePad 11.5 S（hdc 7HZUN26330G02209）+ 畅享90Pro Max（WiFi 192.168.2.17:38611）**，同测同装机；第四台 Pura X View（192.168.2.4:39421）=用户工作机默认不测不装；**手机+Pad 登 180 测试账户、PC+Pura 登 181 主账号**；设备 IP 会变，连不上先问用户；`param get const.product.model` 验身份

## 全局硬性约束
1. 代码清理规则：全部删除console/hilog调试打印；注释掉的大块死代码直接删除。
2. 开发流程：新增功能优先在docs新建md文档，确认方案后再写代码；全局重构/代码清理新开对话。
3. 网络请求：SSE流式请求支持Abort中断；对话不限制180s超时，仅提炼弹窗180s超时；AI 流式后台保活（AiStreamGuard），切后台不断流。
4. UI 开发以根目录 **UI_GUIDELINES.md** 为唯一设计真相源，DesignTokens.ets 为 token 单一来源；禁止页面代码散落写色值。
5. MEMORY.md 记录从简：已完成改动只记一行结论（版本+一句话+关键教训）；仅两类保留完整记录——①未解决 bug 排查链②迭代 3 次以上功能的决策链。
6. **遇到问题第一时间问用户（最高优先级）**：设备连不上/IP 变了/任何异常或不确定——先问用户再动手，禁止盲排查烧 token。
7. 版本注释瘦身：app.json5 / GSD 的版本历史注释只保留最近 2 个版本，更早历史指向 MEMORY.md 版本表。
8. **AGC 控制台操作必须用非无痕窗口**：无痕模式「提交」静默失效（0.206.x 真凶）。凡 AGC 后台操作，AI 必须先提醒用户确认非无痕。
9. 开发机迁移 SOP（如换机）：git 仓库整目录拷贝（含不入 git 的 rawfile/config.json+agconnect-services.json，禁止只 clone）+E:\track-events\ 云函数目录+新机装 DevEco/hdc 重连。MEMORY/project_rule 随仓库迁移无缝续接。
10. 老机器 codearts 同步三层根治（2026-10-11）：SSH key 仓库级指定+safe.directory+SYSTEM 凭据；验证=触发 /build 后 HEAD 自动 reset。
11. **装机不负责卸载**：AI 只覆盖安装；需清数据由用户自行卸载后告知再装。
12. **本机 GitHub 推送通道**：`GIT_SSH_COMMAND="ssh -F ~/.ssh/gh_config" git push origin main`；勿建 ~/.ssh/config（chmod 600 不生效恒 660，StrictModes 会阻断一切 ssh）。
13. **rawfile 双配置永不入 git**（Push Protection）：config.json+agconnect-services.json 已净化出库+.gitignore；unblock 链接绝对勿点；backup-dirty-history 分支=回滚锚（含秘密永不推送）。
14. **用户自觉装机习惯**：「⏳未装机」仅指等用户日常装机消化，不是阻塞待办，AI 不催不盯。
15. **git 推送降级链**：①GitHub（origin）主通道；②失败转测本地服务器；③都推不了→删 codearts remote+本地 commit 保存待推。codearts 已冻结用户永不续费，勿重试。
16. **AOCI 两层索引纪律（★ 2026-10-23 拆分）**：根目录 AOCI_INDEX.md=速查层（全量可读，每文件一行 F/R/⚠S 短句+功能域映射表）；docs/AOCI_DETAIL.md=详叙层（完整契约/版本考古/修复史，按需 grep）。改任何源码前必查速查层条目、按行号区段精读源码、禁止无导航整读大文件（ChatPage/GlobalSettingsDialog/KnowledgeBankPage/ChatModel 尤其如此）；收尾两层同步刷新；新踩坑归位 ⚠S。
17. **MEMORY.md 活规则层体积纪律**：目标 ≤20KB；迭代记录一行制（超一行进 docs 全案）；历史流水一律 docs/MEMORY_HISTORY.md；收尾追加前先 wc -c，超 20KB=下次治理信号。

## 全局约束增补（2026-10-22 后新增条目续编于此）

18. **★ AGC 对话式 API 通道（2026-10-22 建，凭证+私钥均在工程根不入 git）**：skill `hmos-connect-api-cli-skill`（`~/.local/share/deveco/skills/`，内嵌 CLI 免 npm）+`.env`（AGC_AUTH_MODE=service_account + AGC_SA_CREDENTIALS 指向**开发者级**私钥 `1194703931792684689779private.json`——项目级凭证 403 不够用，connect API 须开发者级；应用级 OAuth 凭证是应用侧另一套）。调用：`node <skill>/scripts/connect-api-cli.js <命令>`（project list / provision cert-list / provision profile-list -a 6917618685526149144 等，详见 skill references/）。现资产：debug 证书+调试 Profile（4 设备+READ_PASTEBOARD ACL）2027-10-10 到期；release 证书+发布 Profile 2029-10-22。**代理提醒权益批下来后用本通道重建 Profile**（skill 无「开放能力管理」申请接口——权益申请只能用户网页提交，桌面手册在）。
19. **本机 grep 为 busybox 版：交替匹配必须 -E "a|b"，\\| 语法静默失效零匹配**（0.299.1 排查时三度误判"函数消失"教训——零匹配先怀疑 grep 语法再看代码）。
20. **★ AGC 云函数 cloud-server 五坑（2026-10-23 sp-admin 本地冒烟+官方文档实锤，建同族函数直接抄 docs/cloud/sp-admin/handler.js 勿再踩）**：①实例 API=命名导出 `{cloud}.createInstance`（顶层直调报 not a function，1.0.5 同形态）；②实例方法=`inst.database({zoneName})` 非 cloudDB()，表=`db.collection('表名')`；③行数据必须 `CloudDBZoneGenericObject.build(表名)+addFieldValue` 逐字段（裸类报 2047 缺五元数据方法、纯对象报 3037003 缺主键），查询结果取 `.getObject()` 转 JSON（直 stringify 丢 fieldMap）；④表时间戳字段 Integer=32 位——毫秒戳溢出报 3007007，全链秒级；⑤**回调是单参数 `callback(结果对象)`（官方《Node.js》入口方法明文）——写成 callback(null, result) 平台取首参 null=控制台执行结果显示空串 ""，排一整晚的真凶**。另：HTTP 触发器认证类型二选一（Client适用=端侧网关/app 调用；Server适用=云侧网关/服务端调用）且一个函数只能一个 HTTP 触发器；控制台改代码后必须点「提交」才生效（滚动更新 10~20s）。**本地可直连冒烟**（node+agc-credential.json 真跑 Cloud DB，上传前全链验证）；npm 装包用 --registry=https://registry.npmmirror.com（默认源超时）。
