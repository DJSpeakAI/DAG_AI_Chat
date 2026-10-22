# Project Memory（活规则层）
> ★ 2026-10-22 冷热分离治理：本文件只放「每次会话必须注入的活规则+当前状态」，目标 ≤20KB；完整迭代简表（0.1~0.288 全量）已归档 docs/MEMORY_HISTORY.md（AI 默认不读，查历史才读）。
> 新条目写入前自问（CONTEXT_MANAGEMENT 规则 3）：这条下次会话必须知道吗？否→docs/ 迭代文档或 MEMORY_HISTORY.md；已完成改动只记一行结论（版本+一句话+关键教训），不记过程细节（全局约束#5）。
> 仅保存架构、定型功能、核心规则、未完成任务；单次调试流水存 docs 迭代文档。
> ★ 上下文自律与 Prompt 军规见 docs/CONTEXT_MANAGEMENT.md（project_rule.md §8 强制引用）。

## FACT 项目固定基线
1. DAG气泡树项目架构
   BubbleNode 结构：携带parentID（单父模型），节点内部保存 messages: ChatMessage[]。
   技术栈：鸿蒙 ArkUI V2，结构体使用@ObservedV2，新增字段必须添加@Trace。
   页面与组件：BBTreeCanvas.ets、ChatPage.ets、WordBankPage.ets、KnowledgeBankPage.ets、ReviewPage.ets、GlobalSettingsDialog.ets；ApiClient.ets 负责 AI 流式请求（多提供商）。

2. 已定型核心功能清单
- 气泡树对话、流式API、多模态图片上传、本地持久化(PersistenceV2)
- Markdown渲染（0.231.0 起含行内格式：#标题/**粗**/列表/引用/分割线/链接——utils/MdInline.ets 纯函数+ohosTest 断言），代码块语法高亮，代码块自动换行按钮左对齐
- 图片全屏预览，屏幕圈选截图，图片提炼知识卡片
- 划词翻译、单词库生词复习、知识库卡片管理、知识复习页（ReviewPage，Anki 式单卡）
- TTS语音朗读（本地 CoreSpeechKit 双引擎：中文聆小珊+英文Laura，0.189.0 起替代云端），单词发音单例复用，缩略词播全称
- LaTeX数学公式本地渲染，画布自动排版
- 全局设置弹窗：API提供商化（华为MaaS/火山方舟/DeepSeek 预设+自定义）、AI偏好、云同步、SP/账单、关于
- 学习统计页（StatisticsStore 按天聚合，只增不减）
- 流式渲染：ForEach Key碰撞修复；role映射修复prompt泄漏
- 生命周期：提炼弹窗180s超时，切后台自动中断请求；页面销毁停止定时器
- 返回键拦截：弹窗打开时，返回键优先关闭弹窗
- 华为账号登录（Account Kit 纯客户端授权，AGC 应用 6917618071300773117）
- 云同步（RDB+cloudSync 快照行模式；与华为账号登录态耦合，同开同关，0.196.8）
- ~~订阅体系~~（★ 2026-10-22 用户拍板**订阅概念整体退役**：商业口径只剩 SP 司忆点消耗，无订阅/免费试用/到期锁概念；SubscriptionStore/freeTrialStart/isVip 等代码尚在=待后续迭代清码，新功能一律不得再引用订阅语义；★同拍板：SP/等级/充值包=账号级资产跟着账号走不跟设备走，多账号切换须隔离——0.293.0 方案落地）
 - UI：暗紫主题锁定暗色（方案A）；Pixso 设计稿 canvas 线已落地；四主页面背景 BG_CANVAS
 - 编译优先级（2026-10-12 用户定稿）：**本地鸿蒙 PC DevEco 优先**（用户常开）；本地失败/不可用才切 Windows 服务器（build-server.ps1）
 - 测试台交互模式（★ 0.229.2 用户重裁定）：**双轨并行**——①用户自用=双击桌面「DAG AI Chat/启动测试台.sh」**全自动**（自动起服务+自动开浏览器+服务自愈）；页面绝不出现「复制命令」「去对话喊 AI」类引导②AI 驱动=对话里说跑什么，AI 全自动起查盯报。唯一人工=华为授权弹窗（系统安全红线）。跑完页面一键「复制问题报告」粘给 AI 排查

## COPYRIGHT 软件著作权申请（2026-10-14 定稿）
- **软著提交版本锁定：0.235.0**（versionCode 1000260，提交 be9669d）
- git 快照分支：**v0.235**（本地已建，指向 0.235.0 提交；⚠️ 推 GitHub 失败 publickey，待用户手动 `git push origin v0.235`）。主线继续开发不受影响；若需回滚/查阅软著版代码用此分支
- 申请材料（桌面「软著申请」文件夹）：源代码 PDF 60 页（前 30+后 30，每页 50 行）+用户操作手册 PDF 14 页+设计文档 PDF 60 页（用途：证明产品设计全程由著作权人构思主导，应对审查"设计智力归属"举证）
- **脱敏规则（提交材料强制）**：邮箱已替换 `****@qq.com`；源码无 API 密钥/token/手机号
- 生成脚本（可复用）：`/data/storage/el2/base/temp/deveco/pdfwork/`（node+pdfkit）

## PENDING 待开发任务
**★ IAP 退款对账云函数方案（上架前必做，2026-10-22 华为 AI 答实锤纯客户端不可靠——已 finish 发货的消耗型订单客户端查不到）**：AGC 云函数 HTTP 触发器收 REFUND_TRANSACTION 退款事件通知（复用 trackEvents 云函数链路先例）→ Cloud DB 记退款单 → 客户端进账单页拉退款标记自动核销；配套服务端七年 refunded=true 对账 API 定期兜底。注意：云函数须立即返 200 防重发堆积+幂等处理；AGC 配置入口=应用内支付服务通知接收地址。
**★ 好奇宝宝新手引导体系（2026-10-21 用户提出、拍板性格测试后单独讨论）**：引导新用户逐步用核心功能——新建气泡树/问两个问题/使用司枢模式等，每完成一个功能发 SP 奖励（「好奇宝宝任务」；Lv1 头衔即好奇宝宝）；形态与任务清单待用户下一轮讨论定稿（性格测试 0.288.0 已先行落地，引导体系独立迭代）。

**★ 钩子模式（两段式长回复）SP 军令（2026-10-18 用户拍板，开发前必读 docs/0.165+/0.251.0 第三节）**：
- 架构定案：两次串联非三次——①DeepSeek 深度生成高质量内容 → ②拿①结果再申请一次 AI 做钩子模式加工（钩子 prompt 用户另行设计）；两段式时长必翻倍（2~4 分钟级），0.251.0 后台保活是前置依赖
- **SP 军令两条**：①两段 token 消耗必须**累加实扣**（两次 onDone 累计后一次性 consumeSiyiSp，禁止只扣一段）；②**凡 AI 交互必扣必展示**——包括司忆区问 AI 等任何新增 AI 点，实扣走 spCostOf 同源公式+必须有 SP 消耗展示（禁止无展示隐性扣点；对外禁 token 字样）
- 失败语义：①段失败=直接报错；②段失败=内容保留、钩子降级本地规则（0.234.0 锚点基建），不让②失败毁掉①的优质内容

**知识复习「永远有卡可学」重构（0.200.1 讨论稿已建，交 GLM 5.3 讨论方案后实施；全部上下文+代码地图+参数表+开放问题见 docs/0.165+/0.200.1.md）**：
- Bug 根因（未解决）：ReviewPage.buildQueue 的 isDoneToday 一刀切——当日背完过一轮后再新增的未学习卡被直接拍进完成页（不进队列）；且完成页 hasFutureContent 只认已评分未来卡（新卡 reviewCount=0 不算）→「继续复习」按钮也不渲染（真机铁证：手机完成页 UI 树无该节点）
- 用户业务铁律：未学习卡当日点复习必须出现；永远不可能没有卡可复习（按钮不隐藏）；继续复习=提前学未来卡+顺延系数大幅下降；当日队列 3+1 穿插（3 到期+1 新卡）；知识库空库→直接弹新建卡片引导

**★ 0.293.0 SiyiGate 待装机验收（2026-10-22 四场景）**：①一端签到→三端均显示已签；②手机卸载重装登录 181→首拉后 SP=云端值不重发 200w 不弹礼包；③关系统云空间开关→发消息弹引导；④新账号→首拉后弹「新用户礼包」仪式感。三台已装 0.293.0（PC/Pad/手机全 181）。0.229.24 已随 0.293.0 根治（原条目删除）。

**记忆引擎一期（0.265.0 已完工待装机验收，全案 docs/0.165+/0.265.0）**：五工作包全落地（WP1 画像观察行/WP2 分支摘要头/WP3 SUMMARY_PROMPT 六部分/WP4 注入埋点/WP5 深度记忆总开关）；⏳ 待装机验收=S1/S2 场景脚本与升级回滚测试；画像云同步转人工未动（CloudSyncUtil 红线）；两周后按 P90 决策摘要头裁剪；新 key 三个（`profile-observations-v1` / `memory-pref-v1` / `memory-inject-stats-v1`）+ `personality-quiz-v1`（0.288.0）**均待补录 config.autofix.redlineKeys**。

**云同步 0.230.1 遗留小项**：删除 del 标记行传播真机一键验证、手机未装（用户占用）、僵尸气泡清污待用户画布手动删+「适应全图」。（0.228.0/0.230.1 云同步四连环修复已收官，全案 docs/0.165+/0.228.0 与 0.230.1；数据保险 `testing/console/artifacts/数据抢救备份_20261013/` 不删）

**0.229.x 测试台系列（20+ 条过程记录）**：已全量归档 docs/MEMORY_HISTORY.md；测试台维护铁律见 project_rule.md §12；正本 testing/console/。

## 版本迭代简表（仅最近版本·一行结论制）
> 完整简表 0.1~0.288 见 docs/MEMORY_HISTORY.md（查历史 grep 版本号定位）；详细全案见 docs/（总索引 docs/index.md，0.165+ 段在 docs/0.165+/）；文件级教训见 AOCI_INDEX.md 的 S 字段。

|版本|核心能力 / 关键教训|
| ---- | ---- |
|0.293.0|✅SP 云同步门卫 SiyiGate（用户拍板军令：SP 双向变动——消耗[AI 发送/重生成/划词×2/圈注/IAP 充值]+增加[签到/礼包/grantBonusSp]全收口；ready=登录∧app 开关∧权限∧首拉闸门 rowInitDone；未就绪弹引导三分支[登录/一键开启/Deeplink 跳云空间 hicloud://]）+新用户礼包改**云下行后发放+弹窗仪式感**（挂 reconcile 闸门开启点 maybeGrantWelcomeAfterFirstPull——老账号重装由云端 welcomeGranted 拦截=冷装重领 200w 根治；stamp 链路直发退役）+签到口径统一（isSignedToday 双查本地∪云端 siyi.signedDates——修「手机显示可签点击没反应」UI/执行口径分裂）+账号切换资产隔离（lastAccountMark 尾追华为账号 store；换登重置 SP/统计/签到+RDB 资产行 deleteRowLocal+rowCache 清+**闸门重开防 0 值 LWW 压云端**；内容数据默认合并不动）+订阅概念退役落地（登录订阅墙拆掉/全员引导开同步；SubscriptionStore 清码待后续迭代）+0.229.24 根治（GSD permGranted 接 SiyiGateStore 共享真值源+EntryAbility 启动/前台刷新——华为实锤无权限变化推送 API，onForeground 重查是官方推荐）；⚠️未装机验收（用户自测四场景：签到口径/冷装不重发/门卫引导/新用户仪式感）；autoSyncProgress 云空间满监听需改 CloudSyncUtil（红线）转后续人工审批——华为实锤满时不丢数据仅暂停|
|0.292.1|✅性格测试 3.0 回归纯选择题（用户拍板「不要开放性题目只能单选/多选」，方案 B：12 单选+3 多选）——PersonalityQuiz.ets 题库封闭化（q3/q11/q15 多选 4~5 选项，题干去开放尾巴，QuizQuestion 加 multi）+choiceAnswers 尾追字段（字母升序拼接串 'ac'；answerTexts 0.292.1 起停写保留兼容）+quizAnswerTotal/buildReviewInputs 三段口径（letters+texts+choices，选择题答案转选项文案顿号拼接喂 AI 评阅+关键词兜底照常命中）；Dialog TextArea→选项列表点选流（单选换选/多选增减+统一确认钮，选项 key 掺题索引+字母防 0.288.2 碰撞雷）；Prompts QUIZ_REVIEW_PROMPT 措辞适配；测试断言同步（题库 multi 完整性/choice 存储续做/三段进度/评阅选择段）；版本 1000429（⚠️Index.ets 已无版本点——并行线把版本显示收口到 GSD 关于页，「三处同步」实为两处）；双模块编译过、三台（PC/手机/Pura）VERSION 实测 1000429、failure=10 持平基线零新增；Pad 离线未装待补；⚠️edit/write 工具本会话全量快照异常——文件改动走 /tmp 中转+cp+md5 验证定式|
|0.291.4|✅删「查看思维链」入口（用户拍板：司忆区+锚点已覆盖其价值）——ChatPage 思考收起行改纯状态「已深度思考 Ns」+reasoningViewerMsgId 全链退役（半屏弹窗 73 行+返回键分支+复位+声明）；thinkingTraceByMsg 保留（thinking_use 埋点消费）；⚠️教训=删 if 分支须连闭合 } 一起删（漏删孤立括号→全文件级联 2312 错、测试台 /api/build 日志截尾吞详情——完整报错去 .hvigor/report/ 最新 json 捞）；编译过、四台实测 1000427、ARKUI-TEST failure=10 与基线持平|
|0.291.3|✅文档超长截断计费透明（用户拍板「成本必须赚回来但体验要做好」）——DocParseResult 尾追 truncated 标志（三解析路径置位）+ChatPage showToastLong 10 秒顶格提示「N 个超长已截断至 3 万字，页费仍按全文页数计」；⚠️教训=ChatPage.ets 同文件多 struct 同名方法（340 区子组件与 2850 主 struct 各有 showToastSafe）——grep 方法名定位定义必漏，须按 struct 区段定位（本轮两连编译错根因，曾误判编译器缓存）|
|0.291.2|✅文档加载（方案 docs/0.165+/0.291.0，用户全链拍板）：+号 DocumentViewPicker 图片/文档混选（图+文共9）；txt/md 本地直读+xlsx ExcelJS 全量转 md；docx/pdf 腾讯云 OCR 异步接口（FileBase64≤6MB→Submit→轮询 Describe→ZIP 解压取 .md）；system 一次性注入零 Schema（0.286 读网页先例）；页费嫁接=0.04 元/页折 2 万 token 并账 inputTokens 实扣（失败免费）；双提醒=云端格式 2~6MB 强确认+冷启首弹计费告知；A 模式用户自配 CAM SecretId/Key（GSD Tab1 配置区；ApiConfig 尾追两字段+四处序列化补齐，非新 key）；新增 TcCrypto/Tc3Signer/DocParseUtil 三件（TcCrypto=纯 TS SHA256/HMAC——系统 Mac 仅收固定长 AES key，变长"TC3"+SK 走不通才自实现）；⚠️ FileType 枚举/Describe 字段名=多键防御式**未实测**，装机真测后收敛|
|0.291.1|✅锚点胶囊完整展开换行（用户发截图报「后面是点点点」）——AnchorCard 去 maxLines(1)/Ellipsis/maxWidth40%/flexShrink 截断三连，改 Column+alignItems Start 自适应折行，bait「→拉分支深挖」移胶囊下方独立行；编译（测试台 /api/build）一次过，四台（PC/Pad/手机/Pura）覆盖安装逐台 VERSION 实测 1000424；⚠️ARKUI-TEST failure=10>基线8 的 +2 归因并行线退款闭环（工作区 IapUtil/IapPackage.test 未提交改动，本轮 AnchorCard UI 与 183 断言覆盖面零交集）|
|0.291.0|✅退款闭环四件（用户拍板流程：app 点申请→本地锁包 7 天+指引华为侧申请（自助/客服 950180）→退款成功华为推 REVOKE 事件→云函数记 Cloud DB→**app 三时机（启动/回前台/进账单页）自动拉取核销，用户零操作**——白嫖闭环=用 SP 必开 app，开 app 即拉取先于扣费）——①IapPackage 尾追 frozenUntil（时间戳 max 云同步自洽，7 天到期自动解锁）②冻结额三处同源排除（siyiTotalSp/consumeSiyiSp/BillingPage 资产卡，防池级包级裂账）③IapUtil.pullRefundMarks（callFunction 查 refund-events；getValue 返 any 被 arkts 拍=stringify 整响应双路径读 responseBody 定式）④云函数源码+部署指引 docs/cloud/refund-events/（**未部署**：老机器 E:\track-events 同基建，AGC 建 refunds 表+HTTP 触发器+通知地址 v3，⚠️非无痕窗口；上线前补 JWS 验签+对账 API）；check_ets_files 有缓存误报行号纹丝不动——权威只认 devecocli build|
|0.290.2|✅旧测试充能账清零根治（0.289.1 归零方案实测失败：写减法被云同步下行 max 复活 600 万+触发条件 history 充能行首轮已删且不同步=永不触发）——ensureIapPackagesMigrated 改**写销语义**：consumedPermanentSp 写满至 permanentSp（余额 0+双侧单调，max 合并下永不复活，writeOffRefundedPackage 同族）+删 grantSiyiSpFromIap 内清零调用（雷：第二笔新购会误清第一笔新购账）；⚠️ 上线前必删军令不变|
|docs-2026.10.22c|✅备案四线一天收官（零代码改动）：①网站ICP=沪ICP备2026055703号-1（已通过）②官网 dagaichat.com 上线（阿里云 ECS 8.152.216.55 nginx，暗紫品牌页+底部备案号超链工信部，源码 website/index.html）③公安联网备案已提交（新办网站 dagaichat.com，生成式AI=是/人脸识别=否，审核地上海黄浦区网安支队，30自然日内）④App备案已提交阿里云（订单 2030863653111，新增互联网信息服务-APP/鸿蒙，包名 com.dagaichat.app，发布证书公钥+32位MD5 a2f554b97bcbba0128a6af9920a04c58，ECS 免费服务码）→ 阿里云初审中→工信部短信核验→管局（≤30自然日）→ 备案号填 AGC 提审。★证书 MD5 栏必须 32 位无冒号（带冒号报格式错）；桌面证书材料已归档 配置/signing/ohos/config/（release .cer/.pem/.p7b 勿删，打包发布 p12 要用），图标/CSR 已删，操作指南移至 docs/App备案与公安备案操作指南-20261022.md||docs-2026.10.22b|✅华为工单 D648175（Pad 最大化自由窗口 NavDestination 左侧黑块）人工客服补充材料包产出（桌面「D648175工单补充材料/」五件套：复现 Demo zip（源工程 /storage/Users/currentUser/D648175Demo，编译通过——复刻 208vp 边栏+Navigation 结构+EntryAbility 窗口链+深浅主题；黑块 800px≈边栏 208vp×密度4=复现头号线索）+主 app 复现时段 Hilog 22MB（INFO+，★新线索=启动链 `SCBSceneTitleBar: calAvoidanceWidth err` E 级错误，sceneboard 系统 Window tag）+snapshot 对照 jpeg（快照无黑块实证）+给华为复现说明 md+回复客服要点 txt）；主工程零代码改动不占版本号；**工单闭环后删 D648175Demo 目录与桌面材料包**|
|0.290.1|✅退款感知接口按华为官方答复修正（2026-10-22 华为 AI 实锤：queryPurchaseRecords 已废弃→queryPurchases；退款=JWS payload revocationTime 非 purchaseState=2；**已 finishPurchase 发货的消耗型订单客户端查不到=纯客户端退款感知本质不可靠**）——detectRefundedIapPurchases 改 queryPurchases(ALL) 仅兜未发货极端场景；**可靠方案=AGC 云函数 HTTP 触发器收 REFUND_TRANSACTION+服务端七年 refunded 对账 API（上架前实施，见 PENDING）**|
|0.290.0|✅司枢模式2.0 四包（任务书 docs 0.290.0 司枢模式2.0）：①性格测试开放题（15 题自由文本，Store 尾追 answerTexts/profileWritten 字段；AI 评阅 QUIZ_REVIEW_PROMPT 隐式不扣 SP+25s 超时+本地关键词兜底 localReviewQuizTexts 防空画像；done 即置位不阻塞 SP）②框架先行两段式（PLAN_PROMPT 规划器→sanitizePlan 防弹衣（MdInline 纯函数，幻觉拦截/重试一次/fallback 直写）→buildWritePrompt 执笔（brief 关思考+字数 80%~150% 硬约束）→mergeSectionHooks 节号制渲染期插钩；两段 token 累加一次性实扣；planning 态规划卡浅紫底+流式预览+取消；HOOK_SYSTEM_PROMPT/buildAnchorLongPrompt 退役）③设置简化（AI 偏好区锚点伴读/深度思考/分章折叠/深度记忆四卡 UI 隐藏恒写定值 companion/sparse/on/auto/on，保存洗白老用户；**清空画像入口删除=用户终裁**（退出账号已有「同时清空本机全部数据」即合规入口，clearAllObservations 保留代码层）；isMemoryOn 恒 true）④钩子纯胶囊（AnchorCard 形态 A：删竖线+底色层，紫底白字胶囊 ≤40% 宽截断；progress 类全链绝迹，终态四类 digest/breath/quiz/bait；②段伴读四函数+hook 状态机整体移除，埋点 hook_two_stage→plan_two_stage）|
|0.289.1|❌旧测试充能账一次性清零（归零方案——**0.290.2 实锤失败：被云同步 max 复活+触发条件失效，教训见 0.290.2 行**）；iapConsumedTokens 保留防 token 重放；⚠️ 上线前必删该函数+调用（正式用户充值账绝不能清）|
|0.289.0|✅充能包账本（用户政策三条：嘉奖先扣→按购买顺序 FIFO 扣包→整包未消耗可退）——SiyiPointStore 尾追 iapPackages 按包记账+迁移拆包（旧 600 万池级账从 purchaseHistory 重建独立包）+consumeSiyiSp 包 FIFO（池级/包级守恒）+退款申请弹窗（凭据+引导华为市场）+**退款自动核销**（queryPurchaseRecords 检测已退款→writeOffRefundedPackage 剩余作废，用户零操作；注意该接口返回老模型 inAppPurchaseDataList 顶层字段）+账单页版面重做（删「账单」标题/删旧记录卡/「我的充能包」卡几点几秒账本）；云同步行 union+包级 max 合并|
|0.288.4|✅IAP「存在未完成订单」死锁根治（181 主账号实测）——API11+ createPurchase/queryPurchases 返回 PurchaseData{type,jwsPurchaseOrder,...}，productId/purchaseToken 全在 jwsPurchaseOrder 的 JWS payload（base64url 第 2 段），顶层直读全空→补单整单跳过挂单永不清；parsePurchaseRecord 统一解析（JWS 解码+老格式兜底）两条链路共用+已付挂单自动补入账；教训=华为平台数据模型「沙盒验收通过≠生产环境一致」，JWS 嵌套结构必须解码 payload 再读字段|
|0.288.3|✅LaTeX「公式显示不出」根治——MathRender 主入口前置 stripMathDelimiters 剥 `$/$$` 定界符（0.151 起只转命令从不剥定界符=根因；成对才剥防价格 `$5 和 $6` 误伤、`\$` 转义跳过）|
|0.288.2|✅双 bug：性格测试选项不动（ForEach key 碰撞——keyGen 掺题号根治，历史雷复发）+IAP「订单商品不匹配」误拦付款成功永不到账（readProductId 双读 productId/product_Id+补单追回；外部平台 JSON 字段防御性解析）+购买结果自绘弹框（付款级禁 toast）|
|0.288.1|✅中翻英词条喇叭无声（word 存中文、英文引擎读不了）|
|0.288.0|✅性格测试 15 题混合穿插·画布信号灯入口·画像灌入记忆引擎（PersonalityQuiz.ets，key `personality-quiz-v1`，每 5 题 SP 节点发放；做完信号灯消失）|
|0.287.6|✅喇叭图标双波纹+播放中波纹动画|
|0.287.3~0.287.5|✅输入区排版系列微调（对照参考图+用户截图口述，versionCode 1000409~1000411）|
|0.287.0~0.287.2|✅操作撤销栈 Ctrl+Z（UndoStack.ets 命令模式 50 步，key `undo-stack-v1` 内存态不落盘）+回车确定全套+删除气泡确认弹窗暗紫化+输入框占位与光标同轴|
|0.286.0~0.286.2|✅AI 读网页两级瀑布（静态 GET 抽正文→<300 字判壳→隐形 Web 组件渲染取 innerText；SPA 轮询 innerText≥300 字×5 轮+15s 超时）+AI 消息举报入口（mailto 预填模型 ID）+重命名弹窗宽度断点制|
|0.285.0~0.285.5|✅Ctrl+C/划词复制三连修（终修=focusOnTouch(true) 半步补齐，华为两轮答复）+表格整体划选三件套（放大弹窗「文本模式」+「复制整表」）+正文行高 1.5→1.75+PC 划词菜单纵向化定宽 180vp|
|0.284.0|✅PC 划词右键菜单纵向化+新序|
|0.283.0~0.283.1|✅知识卡编辑弹窗 Ctrl+V 贴图（标题/内容双区 onKeyPreIme 2038+ctrl）+新调试证书|
|0.292.0|✅联网问答一期（方案 C 混合：AI 自主搜索+工具调用循环）——「联网」胶囊（webMode 会话态）开=FC agentic loop：tools=[search_web(Bing 解析零Key)/open_url(复用 0.286.2 两级瀑布)] 声明→AI tool_calls→客户端执行→回填递归（上限 3 轮）；多轮 token 累加一次性实扣+onError 已耗照扣；400+工具词窄门自动降级纯聊天；联网与司枢/深度思考互斥；重生成不带 tools=一期边界；⚠️ 腾讯云 tools 透传与 Bing 反爬未真机验证（全案 docs/0.165+/0.292.0）|
|docs-2026.10.22|**✅MEMORY.md 冷热分离治理+project_rule.md 瘦身（2026-10-22 用户拍板方案 C——「每次完成任务消耗 token 偏多」诊断：基线五文档注入 410KB≈12万+ token/会话，MEMORY.md 328KB 占大头，违反 CONTEXT_MANAGEMENT 规则 3）**：①MEMORY.md 拆双层=活规则层（本文件，328KB→~22KB）+docs/MEMORY_HISTORY.md 冷归档（全量纯搬运零删改，AI 默认不读）②project_rule.md §12 测试台 15 条压缩+U+FFFD 乱码两段重写（Schema 铁律/@ObservedV2 序列化铁律），25KB→~16KB③docs/index.md 登记 MEMORY_HISTORY④零代码改动不占 app 版本号。**防复发军令：迭代记录一律一行制（超一行进 docs 全案）；MEMORY.md 超 20KB=下次治理信号**|

- 版本号纪律：首页显示版本号，每次改动编译装机递增末位；当前 **v0.293.0（versionCode 1000430，app.json5 实读 2026-10-22——多 AI 并行定号铁律：定号唯一依据=AppScope/app.json5 实读，记忆/文档预定号不可信）**；版本三处同步=app.json5 / Index.ets / GlobalSettingsDialog APP_VERSION；**⚠️ MEMORY.md 已超 20KB 治理线（33KB+）——下轮会话应做冷热分离二次治理（0.29x 新条目迁 MEMORY_HISTORY）**
- 迭代文档命名：版本号 变更内容.md（同功能迭代末位+0.1，验收后新需求次位+1，用户可直接指定版本号；详见 project_rule.md §7）
- 版本线主文档：docs/0.165+/0.167.md（历史段 0.140-0.152/、0.160-0.164/ 归档，docs/index.md 为总索引）
- 真机测试设备（★ 2026-10-15 阵容定稿+同日 0.241.0.2 勘误，project_rule §12.14；★ 2026-10-16 IP 勘误：手机 2.14→**2.17**:38611（CHZ-AL00 机型验证）、Pura 2.16→**2.4**:39421，config.json 已同步；★ 2026-10-20 用户定稿**测试账户分工**：手机+Pad 登 **180 测试账户**（+8618051890752）、PC+Pura 登 **181 主账号**（+8618115530752）——两账户分跑便于用户统计各端一周 token 花费；装机/登录流程按此账号落位，勿混登）：**三件套常测试=鸿蒙 PC（本机）+ MatePad 11.5 S 活力版（平板，数据线 USB 直连，hdc 序列号 7HZUN26330G02209）+ 畅享90Pro Max（手机，常测试设备，WiFi 无线调试 192.168.2.17:38611，三端同测同装机）**；**第四台 Pura X View（192.168.2.4:39421，workMachine:true）=用户工作机，入列仅展示、默认不勾选不测不装（用户手动勾选才参与；动不了就跳过别折腾——用户要在上面工作）**；实测教训：设备 IP 会变勿搞反（0.241.0.1 就搞反过一轮：把 2.16:39421 误记为畅享地址），`param get const.product.model` 可验身份

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
10. **老机器→codearts git 同步失效根治（2026-10-11，「编译卡住」真凶）**：三层根因=①HTTPS 凭据 SYSTEM 会话失效②老机器 id_ed25519 是 GitHub key 未注册 codearts③build-server 以 SYSTEM 跑报 dubious ownership。根治三层=①codearts 私钥 scp 至老机器 C:\Users\Administrator\.ssh\codearts_key（icacls 授权）②仓库级 remote 改 SSH+core.sshCommand 指定 key③git config --system --add safe.directory。三坑=StrictModes 非 Windows 选项勿加；配置须仓库级/系统级（SYSTEM 读不到 Administrator 全局）；ssh -T 超时是假象（带 -i 明确 key 重测）。**验证=触发 /build 后老机器 HEAD 自动 reset 到 codearts/main** |

 11. **装机不负责卸载（2026-10-12 用户拍板）**：老机器一键装机服务只支持**覆盖安装**（仅 `/devices`、`/install` 两个端点，无卸载能力，且 AI 侧无 hdc），故 AI **不执行卸载/清数据步骤**——直接 `POST /install` 覆盖安装即可。需要清空本地数据（如测试期从头体验）时，**由用户自行在设备上卸载**，卸载后告知 AI 再装一次；AI 不得为"删数据"再折腾卸载。
 12. **本机（MateBook 鸿蒙 PC）GitHub 推送通道（2026-10-12 定档）**：`GIT_SSH_COMMAND="ssh -F ~/.ssh/gh_config" git push origin main`——gh_config 内含 github.com→github_key 映射（GitHub 账号 DJSpeakAI），codearts 推送走默认 id_ed25519 零配置；**勿试图建 ~/.ssh/config**：本机文件系统 chmod 600 不生效（恒 660），ssh StrictModes 报「Bad owner or permissions」会阻断一切 ssh（含 codearts）。
 13. **rawfile 双配置永不入 git（2026-10-12 Push Protection 二次拦截根治）**：d7f463e「cloud-build: include rawfile configs」（10-09 老机器构建便利）把 config.json（火山 Key）+agconnect-services.json 提交进库 → GitHub Push Protection 拦推送（**0.161.x 同族复发，unblock 链接照旧绝对勿点**）。化解=filter-branch 重写 d7f463e~1..HEAD（239 提交）净化两文件+出库+.gitignore 防再犯（磁盘活文件从本地备份分支恢复）；GitHub main=a8a6352 干净快照（fast-forward 续接）。**⚠️ 老机器下次 sync 后 reset --hard 会删其磁盘两文件——须按约束#9 SOP 手工回拷才能恢复老机器构建默认 Key/云配置**；本地 backup-dirty-history 分支=回滚锚（含秘密，永不推送/分享）。
 14. **用户自觉装机习惯（2026-10-19 用户澄清定稿）**：「装机」=把新编译 HAP 安装到测试设备（PC/Pad/手机三端）。用户**绝大部分新版本都会自觉装机测试**——MEMORY 里「⏳未装机」仅指「等用户日常装机消化」，**不是阻塞待办、AI 不催不盯不设装机类任务卡**；装机后的 bug 由用户反馈、新会话修。
 15. **git 推送降级链（2026-10-20 用户定稿——codearts 免费版过期冻结、用户永不续费）**：收尾推送**不再强推双远端**，按降级链执行：① **GitHub（origin）= 主通道**（`GIT_SSH_COMMAND="ssh -F ~/.ssh/gh_config" git push origin main`，见约束#12）；② codearts 推送失败（冻结/拒绝）→ **不折腾续费、不重试**（用户原话「永远不会续费」），转测**本地服务器**（老机器，用户开着时）推送通道能否备份；③ 本地服务器也推不了 → **直接删除 codearts remote**（`git remote remove codearts`，永不续费已定局，留着只会每次白撞）+ **commit 本地保存**（提交在本地 main 零丢失），等用户本地服务器再开时一并推送备份。现状实锤：2026-10-20 codearts 冻结（remote rejected: Free Edition expired and been frozen）、GitHub 通道正常（a280302 已推）。
 16. **AOCI_INDEX.md 项目认知索引上线（2026-10-21 用户拍板「你来决定直接改」，方案=B 自建 AOCI-lite，源自 github.com/aoci-spec/aoci-code FRAS 思想）**：根目录 AOCI_INDEX.md = 63 个源码文件各一条 F/R/A/S 条目（F 职责/R 连带看什么/A 对外契约/S 血泪教训归位）+ 持久化 key 红线区 + 快速定位口诀。**纪律三条**：①改任何源码前必读其条目、按行号区段精读、禁止无导航整读大文件（ChatPage 6698 行/GlobalSettingsDialog 3406/KnowledgeBankPage 3090/ChatModel 2959 尤其如此）；②收尾五件套第⑤件=刷新受影响条目；③新踩坑教训归位 S 字段（v1 由 GLM-5.3 基于 import/export 代码实锤+MEMORY 教训生成，基线 0.278.0 时点 36090 行/63 文件）。背景：治「AI 越来越笨」三层根因（MEMORY 260KB 注入膨胀/巨型文件整读/36K 行超窗）——本轮同时把对齐基线从三文档升为五文档制（AGENTS.md/project_rule.md 已同步改）。**遗留待办：MEMORY.md 减肥归档（0.1x~0.21x 老条目迁 docs/MEMORY_ARCHIVE.md，260KB→目标 80KB 内）本轮未做，下轮项目基建实施**。

 17. **MEMORY.md 活规则层体积纪律（2026-10-22 冷热分离治理定稿）**：本文件目标 ≤20KB；迭代记录一行制（超一行进 docs 全案文档）；历史流水一律 docs/MEMORY_HISTORY.md（AI 默认不读，查历史才读）；**收尾追加前先量体积（wc -c），超 20KB 即触发下次治理**。
