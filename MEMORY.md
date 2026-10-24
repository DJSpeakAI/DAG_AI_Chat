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
**★ 真人测试流程库（2026-10-24 用户定稿）**：用户口述的人工实测流程结构化沉淀在 docs/真人测试流程参考.md——**测试台新增/更新用例前必须先读它对齐真实用户路径**（真人走查比 AI 编写更真实，冲突时以它为准）；用户会持续口述新流程，收到即追加该档。首条=手机首启全链路（7 场景，0.305.2/0.305.3 均已修复/实施）。
**★ 代理提醒权益重申（0.302.1）**：首次申请被驳（缺设置场景截图）→ GSD 已补提醒设置区块+截图在桌面「AI交接/代理提醒-设置场景截图.jpeg」；**等用户带截图重新提交 AGC 申请（入口：项目设置→开放能力管理→代理提醒）；通过后必须重建 Profile+重新签名才真正生效**（connect API 通道，见约束#18；获批前 publishReminder 1700002 静默降级零影响）。
**★ 0.300.0 司枢 Agent 3.0 待装机验收（六场景=任务书 §九）**：①「去华为官方查 App 上架资质」零点击自动搜索开网页带资料回答；②喂文档+「优化后发华为开发者论坛」=论坛帖体裁成品可整体复制零分析腔/只说「帮我优化一下」=先反问选择题；③司枢+联网同开不互斥；④模糊需求 1 轮 1~3 题反问/明确需求绝不反问；⑤全程 SP 逐轮可见+取消按已耗结算；⑥成品卡一键切形态立即重写。⚠️御史轮/枢机契约链未经真机验证（build 绿≠链路对）——真机异常先查 PLAN3 契约解析与 streamChat 尾参错位高危区。
**★ 0.299.2.x 云同步战役战果（2026-10-23）**：三端（PC/Pad/手机）SP 200 万全等一致 ✓；bug1/bug5 已根治（根因链全案 grep HISTORY 0.299.2/0.299.2.2）。**连带待修**：①~~bug6 老账号重装误弹「新用户礼包」~~ **✅0.302.3 已修**（见版本表）②bug7 本地空 api-config 以新时间戳 LWW 压制云端好配置（mergeCfgs apply 通道对空值零防御）③手机仍在 0.293.0 待升级（盘值 warn 尾巴）。备份：/data/storage/el2/base/temp/deveco/pcdb-backup/（P2 4MB+旧 RDB 9MB）。
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
|0.305.5|✅**三测四项（全案 docs/真人测试流程参考.md 流程03）**：①**主题「跟随系统」不切深 bug 根治**——根因=app 自身 setColorMode(LIGHT/DARK) 触发 onConfigurationUpdate 回声污染 systemDark 快照；修复=回声哨兵（150ms 窗内同值回声忽略）+跟随档 setColorMode(**COLOR_MODE_NOT_SET**，官方 faqs-ability-156：无 FOLLOW_SYSTEM 枚举，恢复跟随=NOT_SET）②门禁布局三调（顶部弹性 1.6→2.0/中部 1→1.4/底部 0.4→0.3）③协议正文不满屏时段落 SpaceBetween 舒展铺满（minHeight('100%')）④**本地模式一次性告知弹窗**（用户理念：暂不登录=仅词库建立/知识卡手动录入/卡片复习三功能；AppConfirmDialog 承载「登录华为账号/直接进入」双出口；**合规已核官方《Account Kit 登录管理细则》——单次告知+可跳过出口不违规**；agreement_store preferences 加 localModeNoticeShown 键每设备一次）。**S 坑：setColorMode 会自触发 onConfigurationUpdate——凡读 configuration.colorMode 做「系统深浅」判定的链路必须防回声**。四台（含 Pura）冷装 1000458|
|0.305.4|✅**门禁视觉+负反馈修订（用户二测拍板，全案 docs/真人测试流程参考.md 流程02）**：①抖动锚点统一迁到「我已阅读并同意」协议勾选行（未勾选点登录/暂不登录任一按钮=协议行抖两抖，红色提示文字「请先勾选并同意协议」退役——抖"要去勾的地方"最直观）②视觉重心下沉：顶部弹性 1→1.6 上部整块下移；下块缩小一圈（协议行/不同意退出 13→12 行高 20→18、版本号 12→11）+底部 Blank(0.4) 缓冲不贴底。**连带清债**：onboardingHint 状态/onboardingLocalShakeX 双抖动/shakeOnboardingLocal 全链删（回归单一 shakeOnboarding）。**S 坑：大段 edit 替换函数区时先查同名函数旧体是否还在（Duplicate function 编译错——本次 shakeOnboarding 双体实锤）**。三台 1000457|
|0.305.3|✅**首页正常态退役（用户拍板「同意协议后直进气泡树」）**：删 Index 首页正常态整段（进入气泡树按钮/华为账号登录区/loginTip 文本位/首页版本号）→ 三落点直达画布：①冷启已同意（aboutToAppear setTimeout(0)——pathStack aboutToAppear 时未附着立即 push 会静默丢）②暂不登录同意完成 ③首启登录成功；home 已同意态=品牌衬底（Blank+brandHeader+Blank，pop 落回再按返回退出 app）。**连带清债**：getHuaweiAccount/getDisplayName/onHomeAccountClick/loginTip 状态全链删；常规登录/退出失败提示改 toast（删 UI 不删反馈）；HuaweiAccountStore/connectHuaweiAccount unused import 清；app.media.user 图标 base+dark 双份删（零引用）。三台 1000456。**测试台连带待核对：冷启用例/登录入口/版本号核对路径（见 docs/真人测试流程参考.md 0.305.3 连带变更节；testing/ 红线 CLI 未动）**|
|0.305.2|✅**首启门禁合规漏洞修复（用户手机实测报障）**：「暂不登录，先本地使用」原实现（Index.onOnboardingLocalOnly）无勾选守卫直接 markAgreed()=未同意协议静默放行，后续进气泡树/开云同步/性格测试全失守；补 onboardingChecked 守卫+抖动负反馈（新状态 onboardingLocalShakeX）；文案「请先勾选同意上述协议」→「请先勾选并同意协议」（协议在按钮下方无上述关系）；连带清 Index 两处 unused import（refreshSiyiGatePerm/FONT_SIZE_META）。**S 坑再证：check_ets_files 对刚改文件缓存失真，unused 判定必须 grep 现文件复核**。三台已装 1000455。**遗留待用户拍板：首页正常态（进入气泡树+登录华为账号页）去留——用户倾向删（同意协议后直进气泡树），待确认**|
|0.305.1|✅**技术债三连清零（用户军令"技术债绝对不允许存在"）+零技术债军令入档（project_rule 新节+收尾六件套⑥+AGENTS）**：①订阅退役残留全链删（ReminderDialog 组件+Index 挂载/isVip/vipExpire/vipDaysLeft/stampFreeTrial 打戳/到期提醒引擎；**stampFreeTrialOnLogin→改名 onLoginAccountHooks()**——它 0.293/0.256 被塞了账号切换检测+签到引导活职责不能整删，改名留活职删打戳；SubscriptionStore 类与字段按 **Schema 铁律保留占位**（现役=兑换码/IAP 账本载体，freeTrialStart 等退役字段永不写入））②硬编码色值 33 处全量 token 化（AppTheme 补 onBrand/glassTint/glassStroke/successBg/glowBg+样张常量；#4CAF50→success 等语义归位；唯一豁免=透明哨兵注释）③unused 参数 _ 前缀 5 处（存量已随①大部消解）。**S 坑：codelinter 报 deep-clone/Date 复用=性能建议非债（JSON 往返具名化是 arkts 防御定式勿改）；check_ets_files 对刚改过的文件缓存严重失真——unused 清理须 grep 现文件验证后再修**。三债各编译+git 分批上传；四端冷装 1000454|
|0.305.0|（已迁 docs/MEMORY_HISTORY.md；全案 docs/0.165+/0.305.0）|
|0.304.2|（已迁 docs/MEMORY_HISTORY.md）|
|0.304.1|（已迁 docs/MEMORY_HISTORY.md）|

- 版本号纪律：当前 **v0.305.5（versionCode 1000458）**；**★ 0.301.1 起版本同步回三处制**：app.json5 + GSD APP_VERSION（已 export）+ Index 侧边栏（读 GSD 单一来源自动跟）——0.292.1「两处制」认知作废（实锤 Index.ets 824 行 0.293.0 硬编码漏更七版的第四处）；versionCode 每版 +1，定号唯一依据=app.json5 实读（多 AI 并行定号规则见 project_rule §7）
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
21. **★ 看板直连部署通道（2026-10-23 固化，勿再让用户手工上传）**：阿里云 ECS `root@8.152.216.55`（密钥 `~/.ssh/dagai_ecs_key`）→ `/opt/dagai-dash`（systemd `dagai-dash`，端口 8766）；改完正本 `docs/cloud/dashboard-v2/` 直接 `sh scripts/deploy-dashboard.sh`（备份→scp→重启→MD5→健康检查，`--force` 强制）。本机无 bash，脚本为 POSIX sh；热路径数据/测试数据走 `/api/sp/command` 运行时改，不发版。**S 坑：`pullAllReports` 在两接口都失败时不建 `data/reports/` 就写 last.json → ENOENT 崩服务进 restart 风暴（脚本首检会被误判成"服务未运行"，已加建目录兜底）**。
