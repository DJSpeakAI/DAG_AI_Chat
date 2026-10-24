# AOCI_INDEX.md — DAG AI Chat 项目认知索引·速查层（AOCI-lite v2，★ 2026-10-23 两层拆分）

> **两层结构**：本文件=速查层（每文件一行：F 干什么+R 连带+⚠S 最致命短句），全量可读；**完整 F/R/A/S 长条目（契约清单、版本考古、修复史叙事）在 docs/AOCI_DETAIL.md 按需查**——速查层 S 触发"要细节"时 grep 文件名去详叙层读。
> **怎么用（每个 AI 会话必遵）**：①改任何文件前先查本索引条目；②按 R 连带查相关条目；③Read 源码用 offset/limit 只读目标区段，**禁止无导航整读大文件**（ChatPage 8235 行/GlobalSettingsDialog 3926 行/KnowledgeBankPage 3090 行/ChatModel 2959 行尤其如此）；④⚠S 是 200+ 版本踩坑结晶，违反=重蹈覆辙；⑤全项目级规则见 project_rule.md，本文件只放文件级认知。
> **维护纪律（收尾五件套第⑤件）**：改了文件职责/接口/强关系→收尾刷新两层（速查层改一行结论，详叙层补全案）；新增源码文件→两层都补条目。

## 功能域→文件速查表（★ 2026-10-23 新增）

| 功能域 | 主文件 |
|---|---|
| 对话/AI 链路 | ChatPage / ApiClient / Prompts.ts / ChatModel / SishuAgent / ClarifyCard / ChatMdParser / MdInline |
| 气泡树画布 | BBTreeCanvas / ChatModel |
| 词卡两库 | WordBankPage / KnowledgeBankPage / WordModel / KnowledgeModel / WordStoreUtil / KnowledgeStoreUtil |
| 复习体系 | ReviewPage / MemoryAlgorithm / WidgetReviewUtil / WidgetHostBridge / ReviewWidgetCard / ReviewReminderStore / ReminderUtil |
| 云同步/账号 | CloudSyncUtil(🚫红线) / HuaweiAccountUtil / SiyiGate / EntryAbility |
| 备份/数据安全 | BackupUtil(🚫红线) / DataWipeUtil |
| SP/计费/签到 | BillingPage / IapUtil / ChatModel(SiyiPointStore) / SignInDialog / RookieTask |
| 文档加载/联网 | DocParseUtil / Tc3Signer / TcCrypto / WebFetchUtil / ZstdUtil / ApkgUtil / ImportUtil / PackUtil |
| TTS | LocalTtsEngine / CloudTtsEngine / QianwenTtsEngine / WordSpeaker / TtsBackgroundGuard |
| 记忆引擎/画像 | ProfileModel / PersonalityQuiz / PersonalityQuizDialog / MemoryAlgorithm |
| 主题/UI | AppTheme / DesignTokens（+UI_GUIDELINES.md 双真相源） |
| 入口/壳 | EntryAbility / Index / AppSideBar / WindowMode / Agreement |
| 统计/撤销 | StatisticsPage / TrackUtil / UndoStack |

**持久化 key 一览禁改**（红线，详见 config.autofix.redlineKeys 与 project_rule）：`bubble-tree-v2`（树主库）`api-config-v3` `ai-preference-v1` `word-bank-v1` `knowledge-bank-v1` `cloud-sync-switch` `profile-observations-v1` `memory-pref-v1` `memory-inject-stats-v1` `review-face-mode-v1` `theme-mode-v1` `siyi-points-v1` `personality-quiz-v1`（待补录 redlineKeys）`review-reminder-v1`（待补录）`sishu-classic-v1`（0.300 待补录）`sp-cloud-seen-v1`（★0.308.0 SP 云行见过标记——待补录）`sp-pending-spend-v1`（★0.313.0 待扣/待发队列——待补录）等——新 key 落地同步补录 redlineKeys 与本索引（纠偏历史走 preferences 'sishu_agent_v1' 轻通道非 P2）。

---

## entryability/

**EntryAbility.ets** 300+ 行 ｜ F: 应用入口：协议哨兵/AGC+云同步+埋点+保活初始化（initAiStreamGuard+★0.304.0 initTtsGuard）/桌面卡片 call 通道(Callee)/主题初始化/退后台备份+摘要 flush/onForeground 刷 SiyiGate 权限+拉退款标记+拉 SP 运营指令（0.301.0）/onBackground 刷复习提醒+SP 镜像兜底上报（0.301.0）+0.301.2 云同步开关影子恢复（bug8）/★0.307.0 应用接续（onContinue 源端采集桥态→wantParam；onCreate/onNewWant CONTINUATION 分支落 pending+同步 restoreWindowStage；setupMainWindow 单一来源被 onWindowStageCreate/onWindowStageRestore 共用） ｜ R: Agreement、ChatModel、CloudSyncUtil、TrackUtil、BackupUtil、SiyiGate、ReminderUtil、WidgetHostBridge、TtsBackgroundGuard、ContinueBridge ｜ ⚠S: initAgreementPrefs 必须 onCreate 最早同步点执行；卡片 call 热路径=Callee onRemoteMessageRequest 非 onNewWant；**接续迁移启动只走 onWindowStageRestore 不走 onWindowStageCreate——主窗口初始化必须两生命周期同调（不复刻=迁移后白屏）；restoreWindowStage 必须在 onCreate/onNewWant 同步执行体内调用（异步=页面加载失败）**；★0.313.0 onCreate/onForeground 增 `ensureSpAuth`+`flushPendingSp`（账本就绪后补跑新手任务结算/每日首签），退后台镜像上报调用已删

## pages/

**Index.ets** ~1090 行 ｜ F: 主页面：Navigation 路由壳+全局弹窗唯一挂载区+启动链（备份恢复询问/卡片快照）+★0.305.0 首启门禁=首页双态（@Computed needsOnboarding；协议正文=首页内切换页；合规逻辑守卫=未同意不渲染边栏/sideBarNav 拦截；★0.305.2 暂不登录/登录两按钮均前置 onboardingChecked 勾选守卫（★0.305.4 负反馈=协议勾选行抖动单一锚点，红色提示文字退役））+★0.305.3 首页正常态退役（同意完成三落点+冷启已同意 setTimeout(0) 直达 BBTreeCanvas；home 已同意态=品牌衬底，pop 落回再按返回退出 app；登录入口走设置/边栏）+loginCore（门禁检查分离）+SiyiGate 引导弹窗（★0.306.0 标题/按钮文字/位次随 siyiGateBlockReason 动态：未登录=「暂不使用」左+「登录华为账号」右，确认动作 doLogin(true) 登录即开云同步；★0.308.0 r=4 假开启实锤=标题「云同步未真正生效」+「前往云空间开启」直跳系统设置 jumpToCloudSpace）+新用户礼包（★0.306.0 单按钮化 cancelText 空串；★0.311.0 关闭后 maybeShowSignInAfterGateReady 接力签到）+侧边栏版本号（读 GSD APP_VERSION 单一来源）；★0.310.1 默认根气泡=「用户画像」空气泡（原「你好/1」示例退役，老装机 migrateLegacyDemoSeed 窄判定迁移）+SiyiGate 引导弹窗确认钮恒左位+本地模式告知弹窗「登录华为账号」左/「直接进入」右；★0.311.0 AI 登录引导文案改「AI 对话等消耗司忆点（SP）的功能，需先登录华为账号」；★0.311.1 云同步开启统一走 CloudSyncPermissionGuide（门卫/GSD 同款，拒绝直达权限面板）；★0.311.5 首页品牌衬底补「进入 DAG AI Chat」主按钮（pop 回落死路修复——0.305.3 退役时漏留返回入口；★0.311.6 按钮 maxWidth 260 收窄居中） ｜ R: 几乎全部 components/common；BackupUtil、CloudSyncUtil、HuaweiAccountUtil、SiyiGate ｜ ⚠S: 满屏必须 Stack 包 Navigation+expandSafeArea；根 Stack 顶层=全部弹窗桥唯一挂载点；畅享 600.6vp 踩线须 deviceInfo 兜底恒手机模式；主题空串=新用户未选择哨兵；**首启登录必须走 loginCore 直通（走 doLogin 会撞 needsAgreement 弹回同一门禁成死循环）**；**首启门禁=首页双态禁回退成覆盖层/延迟判定；门禁态任何放行按钮（登录/暂不登录）都必须先过勾选守卫——漏一处=协议静默同意合规漏洞（0.305.2 实锤）**；**aboutToAppear 里 pathStack 未附着，push 必须包 setTimeout(0) 否则静默丢（0.305.3）**；**@Param 动态文案（syncGateMessage 族）依赖集=方法内读的 @Trace，visible 翻转不触发重求值——确认动作在 onClick 时重取 blockReason 保新鲜**；**⚠页面退役/简化设计必须自检「用户还能不能回到主功能」——0.305.3 首页只留品牌衬底致 pop 回落死路（0.311.5 用户实测骂点）**；★0.313.0 SiyiGate 弹窗改三分支（未登录/网络重试/账本同步中），r=4 假开启+跳云空间分支与 jumpToCloudSpace 已删

## components/

**ChatPage.ets** 9000+ 行（全项目最大，禁止整读） ｜ F: 对话页主体：消息渲染（Markdown 行内/代码高亮/LaTeX/折叠分章/锚点钩子/**★0.302.2 排版体系——blockMargin 分级段距+列表分层符号+标题 emoji+字距 0.3**）、流式接收管线、发送/重生成/换一批、划词三件套（翻译/入词库/入知识库，PC 右击/触屏选中即弹）、司忆区（复习位+AI 重排序）、图片多模态、联网问答 FC 工具循环（search_web/open_url 三轮上限）、司枢 Agent 3.0 三角色流水线（枢机契约→反问收束卡→执笔→御史）、AI 读网页 system 注入、隐形 Web 渲染通道、举报入口、SP 展示、★0.304.0 朗读后台保活挂点（startTTS→beginTtsPlayback/stopTTS→endTtsPlayback 单点收口+aboutToAppear/Disappear 注册注销 setTtsStopHandler）、★0.307.0 接续桥挂点（saveDraft 每键顺带写 continueBridge.draft；aboutToAppear 写 inChat/nodeId+pendingDraft 宿主匹配回填；aboutToDisappear 清 inChat）/★0.310.0 输入区附件面板（+ 展开：内嵌相册条 PhotoPickerComponent 单行模式+四瓷砖 画板→拍摄→相册→文件；ATTACH_MAX 满格只置灰）；★0.310.1 联网开关 UI 退役（联网恒自动判断）+空态分档（根气泡=「没有任何对话+自我介绍引导」，子气泡=「暂无对话」）；★0.310.2 附件面板 Column 自消费点击（防根容器收面板）+面板展开期工具行常驻+占位提示垂直居中；★0.311.1 拦截态失焦（未登录/门卫/余额不足先收键盘+收面板——原提前 return 跳过 clearFocus）+附件面板展开先收输入法+相册条「连续多选」提示 ｜ R: ChatModel、ApiClient、Prompts、ChatMdParser、MdInline、CodeBlockView、FolderPickerDialogs、ImageViewer、SishuAgent、ClarifyCard、WebFetchUtil、TtsBackgroundGuard、ContinueBridge、DocParseUtil、cameraPicker、PhotoPickerComponent ｜ ⚠S: 深水区（build 内 @Builder 渲染链/TTS 状态机/放大弹窗深耦划词体系/知识卡编辑弹窗）拆动需新会话+装机回归；streamChat 尾参 tools/thinking 位错位高危（参数超长逐位核对）；反问挂起=回调恢复非顶层 await；三背景模糊接口同组件仅最后一生效；**渲染层加的任何前缀（列表符号/标题 emoji）必须同步 blockRenderedText 划词基准，否则划词整体错位**；**附件面板：PickerOptions 无 preselectedUris（回显走 PickerController.setData(SET_SELECTED_URIS)）；系统勾选框上禁叠 overlay；勾选回调内禁同步读大图（setTimeout(0) 旁路）；PC 不渲染内嵌条；**单行相册条必须显式 pickerOptions.orientation=HORIZONTAL（API20+；默认竖直=实机上下滑）** ｜ 全案→DETAIL；★0.313.0 六个 consume 收口全部带 txId+scene（chat/regen/plan/word/extract/tts），发送/重生成/划词/入知识库/圈注前 `await ensureSpAuth()` 再门卫 ⚠S 追加：**重生成每次必须用新 txId（同一 messageId 反复重生成要分别计费）；chat 成功/失败两条结算路径共用同一 txId 防双扣**

**GlobalSettingsDialog.ets** 3956+ 行 ｜ F: ⚙设置弹窗：API 提供商+模型别名+测试连接/AI 偏好（鼓励档三胶囊/称呼/重做性格测试/TTS 三引擎配置试听）/云同步 Tab（★0.306.0 订阅 VIP 死分支已清——else if(true) 哨兵+「订阅后开启」按钮退役）/SP 签到/备份 Tab/复习设置（司忆区 Tab——0.302.1 加每日复习提醒 Toggle+时段段选，ReviewReminderStore 单通道即时生效不走底部保存）/文档解析服务配置/关于（版本号+★0.303.1 debug 包「重置为新用户资产」入口——★0.306.0 重置成功=disableCloudSyncOnLogout+logoutHuaweiID+1.2s terminateSelf 自动退出，重开=未登录全新用户态；★0.308.0 重置两态化恒返 true，「云同步未就绪」死分支已删） ｜ R: ChatModel、CloudSyncUtil、SiyiGate、HuaweiAccountUtil、三 TtsEngine、IapUtil、BackupUtil、ProfileModel、ReviewReminderStore+ReminderUtil（0.302.1）、BuildProfile（0.303.1 debug 判定）、CloudSyncPermissionGuide（0.311.1 授权统一入口） ｜ ⚠S: versionCode 展示=版本三处同步点之二；弹窗宽 PC/Pad 固定 560 断点制；对象字面量必须内联调用参数位（arkts-no-untyped-obj-literals）；隐藏设置项=删 UI 不删 store/key+保存恒写定值；TTS 预设档展示官方值置灰可编辑；**debug 重置入口必须由 BuildProfile.DEBUG 包裹，正式包不渲染**；**debugResetNewUserAssets/logoutHuaweiID 契约=内部全捕获永不 reject——then 链不加 catch 死分支**；★0.313.0 aboutToAppear 预热 ensureSpAuth；debug 重置会先 spAuthSpend 清云端余额（礼包幂等键保留=不会重领）

**KnowledgeBankPage.ets** 3090 行 ｜ F: 知识库页：卡片列表（网格/横条）/文件夹树（抽屉/右键长按 CRUD/移动复制/级联删除）/卡片编辑弹窗（多图/标签 chip/导入气泡）/apkg·CSV·xlsx·DagPack 导入导出/滑出删除/排序/问 AI 入口 ｜ R: KnowledgeModel、KnowledgeStoreUtil、AppSideBar、PackUtil、ApkgUtil、ImportUtil、MemoryAlgorithm ｜ ⚠S: swipeAction 是 ListItem 专属且 @Builder 须箭头函数包裹；递归移动/复制文件夹必须防环否则 ANR；宽屏标题几何居中一律 Stack 叠层；sed 插入后相邻 if 块闭合括号易错位且编译零报错；Ctrl+V 贴图=onKeyPreIme 2038 双挂；本页 toast 名=showToast（非 ChatPage 的 showToastSafe）——跨页复刻先 grep 签名

**ChatModel.ets** 2959 行（数据中枢，被 20+ 文件消费） ｜ F: BubbleNode/BubbleTree/ChatMessage/ApiConfig/AiPreference+全部聚合 store（统计/订阅/司忆点/签到/学习量/书签/TabForest）+持久化序列化+云同步行桥（上下行 provider/墓碑）+SP 账本（consumeSiyiSp 实扣+grantBonusSp 收口）+充能包账本（FIFO/退款冻结）+账号切换资产隔离+★0.301.0 SP 数据台区块（markSpAdminDirty 挂 scheduleRowFlush+pullSpAdminCommands 指令执行+0.302.0 SpLedger 事件流水五收口埋点+0.302.4 grant_perm/deduct_perm 充能池定向发扣）+★0.303.1 debugResetNewUserAssets（★0.308.0 两态化：就绪=清本地+覆盖云端；未就绪=纯本地清零+闸门重开，恒返 true；★0.311.4 **重置=完整新用户终稿**——welcomeGranted/影子/签到引导全清零，落地后可重领礼包重走首签（0.311.2「保留标记」版被用户实测驳回：气泡都落地了却不送））+★0.308.0 假开启检测（SpCloudSeenStore 'sp-cloud-seen-v1' 本地标记+afterFirstPullGateOpen 裁决链挂 reconcile 开闸点+spAdminProbe 探针 fail-open 纪律；礼包判定收口进裁决链）+★0.310.1 migrateLegacyDemoSeed（老装机「你好/1」示例→用户画像空气泡，窄判定幂等）+★0.311.0 maybeShowSignInAfterGateReady（首拉开闸/礼包关闭后补弹首日签到）+★0.311.1 假开启加固（第二问探针 deviceModel='' 查账号任何历史——有历史拉不到 SP 行=不发礼包；探针 err 不 fail-open 改挂账有界重试；SpCloudSeenShadow 影子兜底）+★0.311.4 证真分支定稿直发（**拉到行=落地=行内容即真相**：行带标记=老账号拦、无标记=新/重置账号直发——0.311.2 证真分支「任何历史」探针防御与「重置=新用户」语义冲突已拆，探针仅存无行分支防假开启） ｜ R: CloudSyncUtil（互经 provider 注入防环）、SiyiGate、SpAdminUtil（单向）、WelcomeGiftShadow ｜ ⚠S: **@ObservedV2 @Trace 字段 JSON.stringify 不可枚举→持久化必须手写 plain 映射（wordToPlain 模式）**；Schema 只许尾部追加+默认值；PersistenceV2 新字段必须全新 key（挂旧 key 读 undefined）；合并数组按 idCreateTime 全局确定性排序；云下行绝不 upsert 防回环；flat 池=内容唯一真相 Tab=派生视图；**账号切换检测遇 lastAccountMark 空基线只补基线不重置（空值≠换号，误判=SP 清零）**；**debug 重置只覆盖 cfg:siyi-points+cfg:stat-days，node/tab/word/card 内容行绝不动；debugResetLatched 本会话跳 SP 行合并防旧值回填，重启失效**；**假开启窗口=探针异步回调前（秒级）——reconcile 反复触发靠 60s 节流不重裁决**；**⚠礼包发放守卫=「落地证真」而非「身份考古」（0.311.4 用户终稿）：拉到行才判+行内容即真相（标记在=拦/不在=发），拉不到行绝不发（假开启防线）——在证真分支再加历史探针会把重置用户全拦死（0.311.2→0.311.4 一日两反转的教训：先问清用户对重置的语义定稿再动刀）** ｜ 契约全清单→DETAIL；★0.313.0 云函数权威记账接入层（ensureSpAuth/applyCloudBalance/settleSpCloud/settleSpGrant/flushPendingSp；P2 `sp-pending-spend-v1`；端侧镜像上报与客户端 SpLedger 缓冲整体退役）：**消耗=本地镜像先扣→入队→sp_spend；发放=本地先加→入队→sp_grant（txId 全掺账号）**。⚠S 追加：**云端对象类型缺字段（3037004）会被 callWithRetry 吞成 network——接云函数必先本地直调跑 sp_init/spend/grant 全链自证**；**spend/grant 响应只有 bal 没有四池明细（hasPools=false），绝不能拿来覆盖本地镜像**；**旧账号 no-account 且本机空账（probe=yes）绝不能用 0 初始化云端——等云空间下行再迁移**；★0.314.0（Phase3）：`cfg:siyi-points`=跨端状态标记行（只留 signedDates/milestone/rookieDone/Granted/iapPackages；三池余额停写停读停合并，旧行高值不再复活镜像），上行口 `siyiStateToJson`/`mergeSiyiStateRow`/`noteSpStateMutation`（RookieTask 标记写入显式调用）

**BBTreeCanvas.ets** 2180 行 ｜ F: 气泡树画布：节点绘制连线（Canvas 命令式）/平铺选项卡双模式/缩放拖拽/单双击长按右键菜单/选择模式（卡片导入落点）/自动排版适应全图（★0.306.0 fitViewport 单根小树垂直中心 0.5→0.45 上移——flat 且唯一根且渲染高<剩余区 70% 才生效，纯视口偏移不碰节点坐标）/云同步坐标桥/性格测试信号灯入口/新手任务 sign 入口/★0.307.0 consumeContinuePayload（接续导航消费：aboutToAppear+onShown 双保险幂等→交棒三连进 ChatPage；找不到节点=静默落画布弃草稿）/★0.310.1 新根气泡/新 Tab 默认 nodeTitle「用户画像」 ｜ R: ChatModel、ChatPage、KnowledgeModel、CloudSyncUtil、PersonalityQuiz、SiyiGate、RookieTask、ContinueBridge ｜ ⚠S: 单双击并存只绑 count:1 手动判定（两次 tap<300ms）；云同步排版坐标是真相绝不能 autoLayout 重排；自绘弹窗宽一律断点制 isTablet?400:'70%' 禁裸百分比；★0.311.0 任务入口=外层 Stack 垂直居中+内层 34×34 TopEnd 层（34 高按钮直接贴 40 高行会 Y 偏 3vp）；★0.313.0 aboutToAppear 预热 ensureSpAuth（性格测试/新手任务=SP 发放入口）

**WordBankPage.ets** 2280 行 ｜ F: 单词库页：横条/网格双视图/文件夹树（复刻知识库）/滑出删除/拼音 Collator 排序/编辑弹窗/音标口音/DagPack+CSV·TXT 导入导出/发音语音包管理 ｜ R: WordModel、WordStoreUtil、AppSideBar、PackUtil、ImportUtil、LocalTtsEngine、WordSpeaker ｜ ⚠S: 等高网格一律 Grid+固定 item 高度（WaterFlow 只用于刻意错落）；PC 窄窗保持网格=gridMode&&(isTablet||isPcDevice)；intl.Collator 字母排序（@kit.ArkTS 未导出 intl 须 @ohos.intl 直连）

**ReviewPage.ets** 1042 行 ｜ F: 卡片复习页：Anki 式单卡/单双面/评分三按钮/当日队列（到期+新卡 3+1）/完成页（AI 鼓励+烟花+登录引导；★0.310.2 完成钮=navBackToCanvas 回画布；★0.311.0 当日已完成再进入=完成页，只有「继续复习」force 通道入队并追加未学新卡）/桌面卡片联动/每日提醒⚙开关+时段段选 ｜ R: MemoryAlgorithm、两 Model、两 StoreUtil、ChatModel、ApiClient（鼓励语）、WordSpeaker、ReviewReminderStore、ReminderUtil、FireworksOverlay ｜ ⚠S: **完成页按钮全被烟花层 onClick 抢死过一次——烟花层只能 onTouch 透传**；**buildQueue(force=false) 当日完成闸：任何自动重建（aboutToAppear/switchMode/⚙数量）都落完成页，新卡可达性只走 continueReview 的 force 路径——改队列逻辑先看两处语义**；buildQueue isDoneToday 一刀切旧问题（0.200.1）在显式继续复习路径已由「future+新卡」追加兜住；评分按钮固定宽 96 三档终版；英文词 minFontSize16 自适应禁截断；FaceMode/DailyReviewCount 外提防反向成环

**AppSideBar.ets** 895 行 ｜ F: 共享侧边栏（大屏常驻 208vp/手机抽屉）：导航项/两库文件夹树区（折叠/右键长按/拖拽）/账号区/收起把手 ｜ R: WindowMode、两 Model、HuaweiAccountUtil、CloudSyncUtil、各页面 ｜ ⚠S: 边栏内（208vp 且 clip）勿硬塞弹窗覆盖层→走共享 store 交全屏页消费；手机抽屉=遮罩+面板同包一个定尺寸容器 Stack；触屏长按菜单=LongPressGesture+bindPopup 双通道唯一可靠（RightClick 映射长按是错误旧认知）

**BillingPage.ets** 699+ 行 ｜ F: 账单页：SP 资产卡（冻结额排除）/充能两档 IAP/充能包账本（三态：退款处理中·剩N天/已退款/已消耗）/申请退款弹窗（锁包 7 天）/扣点规则/兑码/发票指路/补单+退款核销+SP 运营指令拉取（0.301.0 进场时机） ｜ R: ChatModel、IapUtil、SiyiGate、HuaweiAccountUtil ｜ ⚠S: 兑换前置登录；付款级结果禁用 toast（自绘居中弹框）；购买前置 requireSiyiGate；退款政策三条=嘉奖先扣/包 FIFO/整包未消耗可退；进场=ensureIapPackagesMigrated 唯一触发点（含上线前必删的测试账写销）；★0.313.0 aboutToAppear 预热 ensureSpAuth（余额以云端镜像为准）

**AnnotationPage.ets** 376 行 ｜ F: 屏幕圈选标注页：截图画笔圈选+补充要求+结果回传 ChatPage ｜ ⚠S: NavDestination 自带黑底——根容器不设底色即透黑

**SketchPage.ets** 521 行 ｜ F: 数学证明手写画板：视口 Canvas+世界坐标矢量重放/单指书写双指 Pan+Pinch/防手掌误触（笔活跃 800ms 内手指全拒）/双色笔/撤销/导出 JPEG 回传 ｜ ⚠S: sourceTool 是 TouchEvent 级属性非 TouchObject 字段（正确=event.sourceTool）；Canvas onReady 尺寸变化必须 fullRedraw 重放；OffscreenCanvas 单位 px 与主 Canvas vp 两系勿混

**StatisticsPage.ets** 624 行 ｜ F: 学习统计页：四卡联动柱状图（对话/资产/Token/司忆量）+AI 鼓励语+测试数据种子 ｜ ⚠S: Navigation 路由页根组件必须 NavDestination+hideTitleBar(true) 否则全黑屏；测试数据 seed 一次性+上线清零

**SignInDialog.ets** 294 行 ｜ F: 签到+称号升级弹窗（桥驱动 Index 根唯一挂载） ｜ ⚠S: 桥模式=Index 根挂载任意页触发（ConfirmDialogStore 同款纪律）；isSignedToday 已改双查本地∪云端——新消费处勿再单查本地

**其余组件**：AgreementDialog 362（仅 hw 登录门禁在用；basic 分支随首启门禁重构退役）｜ThemeChooseDialog（首启外观三选一，体验改进默认关；★0.311.0 加「允许通知」开关——真值=系统通知授权；★0.311.6 定稿：首点尽力 requestEnableNotification（**冷装会重置系统询问态=会弹**，app 内重置不重置）+拒绝只回弹/**二次点击（notifyAsked）必跳系统通知开关页**（uri=systemui_notification_settings+pushParams 包名）——**引导框已按用户拍板删除（0.311.5 曾加，同日驳回：拒绝后不再弹任何说明）**；弹窗可见期 2s 轻轮询 isNotificationEnabled 跟系统真值（notifyRequesting 防乐观位被迟到轮询打回，visible=false+aboutToDisappear 双停定时器）；⚠0.311.1 血泪：必须先乐观置 true 再回查，否则「拒绝→再写 false」状态无变化=Toggle 视觉不回弹）｜AppConfirmDialog 133（通用确认弹窗，挂 Index 根 Stack；含 SiyiGate 引导+新用户礼包桥；★0.306.0 cancelText 空串=单按钮模式——不渲染取消钮+遮罩点击不关，唯一出口确认钮满宽）｜CodeBlockView 343（代码块组件——⚠@ComponentV2+@Event 桥接，禁 @BuilderParam 传父工具栏 this 丢失崩溃）｜FolderPickerDialogs 419（三选择弹窗 @Event 桥接+store 直连单例）｜ImageViewer 178（全屏图浏览器 store 桥+if 挂载）｜WaitingDots 48（三点等待自管定时器）｜FireworksOverlay 258（完成页烟花透传 8s 静默——⚠必须用 onTouch 透传，onClick 非冒泡会抢死下层按钮）｜FoldChevron 16（全项目唯一折叠指示器）｜PersonalityQuizDialog 678（性格测试：点选流/断点续做/自定义行/SP 节点奖励——⚠ForEach key 掺题索引+字母不回退；宽度断点制）｜ClarifyCard 678 内（司枢反问收束卡——⚠选项 key 掺题索引；@Local 接管 connect 实例须显式类型）｜RookieTaskDialog+RookieRewardDialog（新手任务——⚠任务行 ForEach 内联禁带参 @Builder；@Monitor visible 每开必 settleRookieTasks）

## common/

**WordModel.ets** 87 行 ｜ F: WordItem（@ObservedV2+@Trace，Schema 尾部追加红线主战场）/WordFolder/两导航 store ｜ ⚠S: WordItem 构造 11 参尾部 folderId 可省=最易漏传雷；单位统一存「天」浮点防混用

**KnowledgeModel.ets** 221 行 ｜ F: KnowledgeCard（13 参）/KFolder/CardImportStore（跨页导入）/AttentionStore（热度）/两导航 store ｜ ⚠S: 13 参显式传全（images/titleImages 占位 ''）；多图=images JSON 数组+getCardImages 两代兼容

**WindowMode.ets** 15 行 ｜ F: isTablet 断点唯一权威+IndexSidebarState ｜ ⚠S: 分屏/悬浮窗屏宽不变窗宽变——按窗口实宽非屏宽；connect 实例挂 @ComponentV2 必须 @Local 接管

**UndoStack.ets** 75 行 ｜ F: 操作撤销栈（命令模式 UndoEntry，50 步裁头，Ctrl+Z 全局键） ｜ ⚠S: 闭包只捕获应用级单例+数据快照禁捕获页面 this（页面销毁=定时炸弹）；undo 放回复用 add* 路径=云上行自然触发零碰红线；不进栈=设置/发送/新建/导入/Tab 重命名；key 'undo-stack-v1' 内存不落盘（闭包不可序列化恰好）

**AppTheme.ets** 186 行 ｜ F: 主题色真相源+三态主题（跟随/亮/暗）+ThemeBadgeStore；★0.305.1 语义色 token；★0.305.5 chromeSync 钩子带 mode（system 档恢复 setColorMode(NOT_SET)——根治跟随系统不生效） ｜ ⚠S: theme-mode-v1 空串=新用户未选择哨兵；色值真相源在此，UI 常量在 DesignTokens；**全项目禁散落硬编码色值（零技术债军令——widget 卡片进程自有常量表是唯一架构豁免）**；**setColorMode 会自触发 onConfigurationUpdate 污染 systemDark 快照——回声哨兵在 EntryAbility（0.305.5 血泪）**

**ReviewReminderStore.ets**（common） ｜ F: 每日提醒偏好单通道（key 'review-reminder-v1'：on/hour/minute/reminderId/lastDoneDate）——双入口消费：ReviewPage ⚙ 弹窗+GSD 司忆区 Tab（0.302.1，代理提醒 AGC 补场景） ｜ ⚠S: lastDoneDate 格式=yyyy-m-d 不垫零，与 ReviewPage.todayKey 字节级绑定——改任一处必须同步另一处（漂移=恒「未完成」）

**ProfileModel.ets** 574 行 ｜ F: 记忆引擎：画像观察行（每 8 轮隐式 LLM 观察+演变链）/深度记忆总开关（恒 true 用户终裁）/注入埋点/分支摘要 flush ｜ R: ApiClient(implicit)、ChatModel、EntryAbility、GSD、ChatPage、PersonalityQuiz ｜ ⚠S: 隐式调用不扣 SP（implicit 预留位）；超 20 次/日降频；画像云同步=CloudSyncUtil 红线转人工；演变链只增不删

**其余 common**：ChatPageTypes 122（0.295 拆：类型常量层+ChatFontScaleStore/ImageViewerStore+会话级 Map——⚠PLACEHOLDER 两常量字面值=历史持久化过滤判据禁改；**BODY_LINE_HEIGHT_RATIO=1.82（0.302.2 自 1.75 升级）**）｜SketchModel 19（画板回传 store——⚠@ObservedV2/@Trace 是全局装饰器不从 @kit.ArkUI import）｜DailyReviewCountStore 9（每日复习量 1~500 默认 10）｜DesignTokens 19（UI 常量双真相源之一，改样式先查这+UI_GUIDELINES）｜FaceModeStore 12（卡面模式 key 'review-face-mode-v1'）｜Prompts.ts（全部 prompt 单一真相源，新 prompt 必须遵守 CONTEXT_MANAGEMENT 十军规——⚠HOOK_SYSTEM_PROMPT 与 buildAnchorLongPrompt 已退役墓碑留存禁复活）｜PersonalityQuiz.ets 710（性格测试 3.0 数据层：15 题封闭题库/进度存储（choiceAnswers·customAnswers 尾追兼容——Schema 红线适用）/SP 节点三段相加/AI 评阅（implicit 不扣 SP+25s 超时+幂等闸）+本地关键词兜底；★0.313.0 节点奖励 txId=`quiz:<账号>:<节点档>`）｜AnnotationModel 24（圈选三 store）

## utils/

**ApiClient.ets** 1102 行 ｜ F: AI 网络咽喉：streamChat 流式（多提供商 OpenAI 兼容/多模态/implicit 隐式位/FC 工具循环——SSE 解析 delta.tool_calls 分片按 index 拼接）+queryWord/queryKnowledge/queryKnowledgeFromImage+classifyStreamError 九场景+AiStreamGuard 保活+buildToolRoundMessages ｜ R: ChatModel、Prompts、AiStreamGuard、ChatPage(handleToolCalls) ｜ ⚠S: 卡死自愈逻辑必须放 guard 前；readTimeout 300s（深度思考不可关）；extractStreamError 防 HTTP 错误体被 SSE 解析器静默吞；错误必须分类+中文提示禁原始英文；全链 StreamController 可中断；工具拼接不完整走 onError 不静默

**CloudSyncUtil.ets** 329 行 ｜ 🚫**红线文件禁改（改动须转人工）** ｜ F: 云同步（RDB+cloudSync 快照行模式）：initCloudDb/权限/上下行 provider/墓碑/仲裁/nudge/幂等清洗 ｜ ⚠S: 下行写池绝不 upsert 防回环；flush 起手 cache 空从 RDB 播种防全量 churn；删除=flushDeletions 行键差集推导（RDB 行=上行事实）；与登录态同开同关

**BackupUtil.ets** 406 行 ｜ 🚫**红线文件禁改** ｜ F: 数据安全三道防线：内部双备份（filesDir/backups 轮换原子写）/外部 .dagbak 备份恢复/SCHEMA_VERSION+jsonToPayload 校验 ｜ ⚠S: @ObservedV2 序列化必须 wordToPlain/cardToPlain 手写映射；picker.save 禁 autoCreateEmptyFile（0 字节壳假成功）；恢复=合并导入同 id 备份为准绝不删现有；恢复端逐条丢弃空壳

**KnowledgeStoreUtil.ets / WordStoreUtil.ets** 415/416 行 ｜ F: 两库持久化与全部操作：CRUD/文件夹树（防环）/级联删除/种子 marker/noteBankMutation 云钩 ｜ ⚠S: copyFolder/moveFolder 开头防环（目标上溯命中自身返 -1）；单向依赖防环——Bridge 经提供者注入反向取 store；删除走墓碑显式落库（删除语义在操作发生那一刻落库，非 flush 时补）

**MemoryAlgorithm.ets** 178 行 ｜ F: 记忆算法：R=e^(-t/S) 遗忘曲线/提前背惩罚/标签+注意力加权/到期闸门/当日队列 3+1/applyPassiveReview/换一批轮换 ｜ ⚠S: 单位统一存「天」浮点铁律；复习缓存按消息 ID 永久固定；换一批=显式偏移轮换（删缓存重抽换不出内容）

**ReminderUtil.ets** ｜ F: 每日提醒核心：refreshReviewReminder 单入口（cancel 旧+publish 新周期闹钟全选永续）+文案双态（完成=好习惯+1/未完成=约 N 条待复习） ｜ ⚠S: 代理提醒权益待 AGC 审批——通过前 publishReminder 1700002 全链静默降级（权益到即生效零改动）；周期闹钟非华为建议的滚动单日（滚动断档违背天天提醒）；IPC 调用不受退后台网络限制

**AiStreamGuard.ets** 199 行 ｜ F: AI 流式后台保活：dataTransfer 长时任务+实况窗进度 3s+90s 看门狗+完成通知 ｜ ⚠S: 切后台不断流（0.251 反转旧规）；禁止任何页面再对 AI 请求做切后台主动 abort

**TtsBackgroundGuard.ets** 225 行 ｜ F: ★0.304.0 TTS 朗读后台/熄屏续读写守卫：MODE_AUDIO_PLAYBACK 长时任务（**API21+ ContinuousTaskRequest 新接口独立 id**——旧接口单任务限制会与 AiStreamGuard 的 dataTransfer 相撞）+AVSession 懒创建一次永久复用（防 6600101）+播控中心 pause/stop 命令→setTtsStopHandler（ChatPage.stopTTS 全收敛，页面销毁兜底直停三引擎）；begin/end 由 ChatPage.startTTS/stopTTS 单点收口，generation 防异步交错 ｜ R: ChatPage（唯一消费方）、EntryAbility（initTtsGuard 注入）、三 TtsEngine（兜底停） ｜ ⚠S: **结束即停长时任务（系统管控红线）；stopBackgroundRunning 须带 continuousTaskId 精确停（无参版会连 dataTransfer 一起停）；AVSession 一进程仅一个对象勿重复 create**；单词发音/试听秒级短播不挂本守卫

**AiRerank.ets** 242 行 ｜ F: 司忆区 AI 智慧排序（发送预触发+渲染消费） ｜ ⚠S: 失败静默兜底本地序；隐式调用不扣用户 SP

**SiyiGate.ets** 88 行 ｜ F: SP 云服务门卫——一切 SP 消耗/发放功能前置闸（★0.313.0 ready 两条件=登录∧spAuthReady 云函数账本通道就绪；旧五条件里云同步开关/权限/首拉闸门已退役；cloudBlocked 仅保留内容同步提示）+permGranted 仍供 GSD 状态卡+spAuthErr 分支：1 未登录/2 网络/3 账本同步或服务升级+registerSpAuthRefresher（ChatModel 注入，防环） ｜ ⚠S: **新增 SP 消耗/发放口必须接 requireSiyiGate（军令）**；**云空间开关不再阻断 SP——不要再用 connectCloudSync().enabled/rowInitDone 做扣点条件**；华为无权限变化推送——onForeground 主动重查是官方推荐；**假开启证据链仍在 ChatModel afterFirstPullGateOpen（本文件只持有标志位）**

**WebFetchUtil.ets** 414 行 ｜ F: AI 读网页两级瀑布（静态 GET→<300 字判壳→隐形 Web 组件渲染重取）+searchWeb Bing 结果页解析（零 Key 零配置）+ContentFilter 过滤+system 注入块 ｜ ⚠S: resp.header Object 索引访问触发 arkts-no-any-unknown→Content-Type 校验改启发式；域名必须 cn.bing.com（www 域 302 隐患）；iframe 内文档取不到=已知边界；命中 ContentFilter=丢弃该网页块不拦用户消息

**LocalTtsEngine.ets** 376 行 ｜ F: 本地 TTS（CoreSpeechKit 免费离线）：中文聆小珊+英文 Laura 双引擎/requestId 会话限定/单例互斥/语音包管理/splitTextForTts 分段 ｜ ⚠S: 文本上限 10000 字符；requestId 会话严格限定；单例互斥勿并行 speak

**CloudTtsEngine.ets / QianwenTtsEngine.ets** 445/553 行 ｜ F: 云端 TTS 双引擎（火山 openspeech/千问 CosyVoice 复刻音色），云端优先失败回退本地 ｜ ⚠S: speakWithParams 显式传参（试听链路）；文档端点与实测有出入以实测为准

**MdInline.ets** 990+ 行 ｜ F: Markdown 行内渲染纯函数层：#标题/粗体/列表/引用/链接/FoldSection 分章折叠/锚点钩子/表格整表工具+司枢 PlanFrame 防弹衣（sanitizePlan：围栏抠取/越界钳制/幻觉拦截）+mergeSectionHooks 渲染期钩子合成+**★0.302.2 listMarker/headingIcon（列表分层符号 • ◦ ▪/标题 emoji，blockRenderedText 划词基准同源）** ｜ ⚠S: **纯函数零状态——修改必须同步 ohosTest 断言**；folded 状态按 messageId+锚点 id 记忆；JSON 往返具名化（arkts-no-any-unknown 索引防御定式）；**渲染前缀改动必须同步 blockRenderedText（否则划词偏移整体错位）**

**WidgetReviewUtil.ets + WidgetHostBridge.ets** 400+211 行 ｜ F: 桌面卡片双层：ReviewUtil=卡片进程安全层（formId filesDir JSON 直存/状态推送/speak）；HostBridge=主进程业务层（快照/pending 回放/评分/call 分发） ｜ ⚠S: formId 必须 filesDir JSON 文件直存（preferences 进程内存缓存跨进程看不到）；卸载重装自愈=一切生命周期回调记 formId；卡片评分路径 reviewCount 不增长（已知待补）；FaceMode/DailyReviewCount 外提件防反向外环

**TcCrypto.ets** 168 行 ｜ F: 纯 TS SHA-256+HMAC-SHA256（FIPS 180-4/RFC 2104，腾讯云 TC3 签名原语） ｜ ⚠S: 系统 cryptoFramework 的 Mac 只收固定长 AES SymKey——TC3 变长 key 走不通才纯 TS 自实现；定长摘要仍用 cryptoFramework Md 勿合并

**Tc3Signer.ets** 56 行 ｜ F: 腾讯云 TC3-HMAC-SHA256 签名头组装纯函数 ｜ ⚠S: Host 头不显式传（ohos http 默认=签名值，显式传可能重复头）；payload 与 extraData 必须 byte 级同一字符串变量（签名对不上=403）

**DocParseUtil.ets** 470 行 ｜ F: 文档加载核心：格式路由（txt/md 本地直读、xlsx ExcelJS 全量转 MD、docx/pdf 腾讯云 OCR 异步 Submit→轮询 Describe→ZIP 下载解压取 .md）+预过滤+注入块；★0.310.0 后缀常量收敛为文档专用 DOC_SUFFIX_FILTERS（图片入口退役） ｜ ⚠S: FileType 枚举与 Describe 响应字段名=多键防御式**未装机实测——真测报错先查这两处**；ZIP 链接 30 分钟有效须立即下载；readXlsxRows 是卡片导入语义（前 3 列）与 parseXlsxLocal（全量）两套勿混；解析失败 failReason 进注入块+零扣费；**新增格式必须同步 DOC_SUFFIX_FILTERS 与 LOCAL_EXTS/CLOUD_EXTS 双侧**

**ZstdUtil.ets** 743 行 ｜ F: fzstd 纯 TS 解码器移植（apkg+SP 行压缩） ｜ ⚠S: 纯 TS 无依赖移植勿轻改

**ApkgUtil.ets** 402 行 ｜ F: Anki apkg 导入（24.11+ anki21b）：zstd 解码/SQLite 魔数校验/deck 层级归一/media protobuf/图片落盘 ｜ ⚠S: collection.anki21b 才是真数据（anki2 空壳）；标题换行必须展平为空格；接手移交代码第一件事 grep 临时诊断删净

**ImportUtil.ets / PackUtil.ets** 160/183 行 ｜ F: CSV/TXT/xlsx 导入；DagPack 打包（文件夹子树 JSON、refId 防跨设备撞 id） ｜ ⚠S: DagPack 导入挂当前文件夹绝不合并现有目录

**MathRender.ets** 483 行 ｜ F: LaTeX 本地渲染 ｜ ⚠S: 必须在 parse 层转换保证划词偏移一致；主入口前置 stripMathDelimiters 剥 $/$$ 定界符（成对才剥/价格 $5 和 $6 闭$前空白不误伤/\$ 转义跳过）——只转命令不剥定界符=「公式显示不出」根因

**CloudSwitchShadow.ets** ｜ F: ★0.301.2 云同步开关影子通道（bug8：P2 key cloud-sync-switch 冷启水合失败——盘 true 运行时恒 false）：initCloudSwitchShadow/writeCloudSwitchShadow/readCloudSwitchShadow/restoreShadowFromP2File（P2 盘文件直读迁移）｜ R: EntryAbility（启动/回前台恢复）、GSD（开关两处写入）｜ ⚠S: **与 bug5 huawei-account 同族黑盒——凡 P2 单 key 水合失败都用 preferences 影子+盘直读兜底**；恢复只在 isLoggedIn 时执行；用户主动关闭必须写影子 false（否则自动复活打架）

**ContinueBridge.ets** ｜ F: ★0.307.0 应用接续桥（AppStorageV2 'continue-bridge' 不落盘）：源端实时态 inChat/nodeId/draft（ChatPage saveDraft 每键顺带写——EntryAbility.onContinue 隔页读不到页面 @Local，桥是唯一实时通道）+目标端待恢复 pendingNodeId/pendingDraftFor/pendingDraft（宿主匹配防误回填他气泡）｜ R: EntryAbility（onContinue 采集/CONTINUATION 落 pending）、ChatPage（写+回填）、BBTreeCanvas（导航消费）｜ ⚠S: wantParam 自定义 key 用 dag 前缀禁撞系统预置（version/targetDevice）；pending 三字段一次性消费（BBTreeCanvas 清 nodeId、ChatPage 清 draftFor/draft——节点找不到时 BBTreeCanvas 代清草稿防残留误回填）

**SpAdminUtil.ets** ｜ F: ★ 0.301.0 SP 数据台传输层：sp-admin 云函数纯封装（fetch 指令 / confirm 回报 / ★0.308.0 probe 假开启探针——'yes'他设备资产痕迹/'no'无/'err'通道失败三态）+★0.312.0 **SP 云函数权威记账四接口**（spAuthBalance/spAuthInit/spAuthSpend/spAuthGrant——SpMirror=权威余额、SpLedger=流水+txId 幂等，B 方案根除云空间白嫖）；★0.313.0 report 镜像上报退役（端侧不可覆盖权威余额） ｜ R: ChatModel（唯一消费方）、云函数 docs/cloud/sp-admin/ ｜ A: spAdminFetch / spAdminConfirm / spAdminProbe / spAuthBalance / spAuthInit / spAuthSpend / spAuthGrant ｜ ⚠S: **零 import ChatModel（0.223.0 防环军律）**；云函数未部署=全静默；**AGC SDK 异步初始化抢跑→callWithRetry 1.5s×3 重试（not initialized 错误码）**；响应读取 stringify 双路径（responseBody 嵌套）；**云空间容器 dag_chat_cloud 服务端不可读（2057）——探针只能查 default zone Mirror+Ledger**；**⚠SP 记账新铁律（0.312.0）：消耗/发放必须走云函数权威通道（云空间行记账=系统开关一关就白嫖），本地账本只作镜像**；**0.313.0：SpAuthResult.hasPools 区分「四池明细」与「只有 bal」——spend/grant 结果不可当余额快照；callAuth 把 3037004 归 unknown 不归 network**

**CloudSyncPermissionGuide.ets** ｜ F: ★ 0.311.1 云同步授权统一入口 enableCloudSyncWithGuide（requestSyncPermission→成功即开/写开关影子；拒绝→requestPermissionOnSetting 直达权限面板+10s 手动路径）——门卫 r=2 与 GSD「开启云同步」共用 ｜ R: CloudSyncUtil（只消费导出）、SiyiGate、CloudSwitchShadow ｜ ⚠S: **系统授权窗仅首次弹（官方：非首次直接返 success 不弹框）——拒绝后只能 requestPermissionOnSetting，光 toast=用户不知道去哪授权**

**SpCloudSeenShadow.ets** ｜ F: ★ 0.311.1 「SP 云行见过」preferences 影子（'sp_cloud_seen_shadow'）：P2 'sp-cloud-seen-v1' 水合失败兜底 + P2 盘文件一次性种子 ｜ R: ChatModel（假开启证据）、EntryAbility（onCreate 初始化） ｜ ⚠S: **P2 单 key 水合黑盒高发区——凡假开启判定证据必须影子双写（同族：huawei-account/cloud-sync-switch）**

**WelcomeGiftShadow.ets** ｜ F: ★ 0.302.3 新用户礼包「已发放」本地影子（bug6 根治）：preferences 按账号 mark 记已发+启动从 P2 盘文件种子存量用户；clearWelcomeGiftIssued（debug 重置清影子——0.311.2 删/0.311.4 随「重置=完整新用户」终稿恢复） ｜ R: ChatModel（grantSiyiWelcomeBonus 双保险+debug 重置）、EntryAbility（onCreate 初始化） ｜ A: initWelcomeGiftMarker / isWelcomeGiftIssued / markWelcomeGiftIssued / clearWelcomeGiftIssued ｜ ⚠S: **P2 水合可能晚于一次性发放判定——凡一次性发放逻辑必须 preferences 影子+池值(giftSp>0)自愈双保险**；影子写失败静默退化；账号切换天然隔离（mark 比对）；清影子只在 mark 匹配时执行，防误清他账号

**其余 utils**：Agreement.ets 210（协议状态+文案单一来源；★0.305.0 基础门禁=首页双态、promptVisible 退役——⚠initAgreementPrefs 必须 onCreate 最早同步点；AGREEMENT_VERSION=3 勿因 UI 改动误升）｜ChatMdParser 133（Markdown 解析四纯函数——⚠改动连带核对 MdInline ohosTest）｜ContentFilter 88+SensitiveWords 97（敏感词 Trie+三族词表）｜SyntaxHighlight 108（代码块正则高亮）｜TrackUtil 212（埋点 hmcore+cloud、攒批 20、退后台 flush、隐私闸门默认关——⚠region 字段丢失整链静默死）｜WordSpeaker 102（发音单例+口音弹窗，缩略词播全称）｜DataWipeUtil 105（登出清本机数据+widget 快照+preferences）｜HuaweiAccountUtil 198（Account Kit+requireLoginForCloud+账号切换检测——⚠0.299.2 登录态影子 account_shadow；**0.302.3 影子 mark 为空绝不回写 P2（=伪造换号→SP 清零）**；accessSync 返 void 禁作布尔；1001502012 取消静默）｜IapUtil 345（IAP 收银台+JWS 解析——⚠API11+ 字段全在 jwsPurchaseOrder **JWS payload 第 2 段**；queryPurchaseRecords 废弃；退款=revocationTime；纯客户端退款感知不可靠=云函数方案 PENDING；callFunction 靠 stringify 双路径读）｜RookieTask（七任务+幂等三时机——⚠done/granted 集合存 siyi-points 云行=唯一真相源；★0.311.0 奖励标题判据=完赛哨兵是否已发，勿再用「本次总额≥2万」判「全部完成」；★0.313.0 发放 txId=`rookie:<账号>:<任务id>`）｜SishuAgent（契约层 TaskContract+sanitize——⚠契约=会话级临时数据永不持久化/不进 Schema；preferences 用 getSync 非 getStringSync）

## entryformability/ + widget/ + entrybackupability/

**EntryFormAbility.ets** 35 行 ｜ F: 桌面卡片 FormExtensionAbility 生命周期（一切回调记 formId 自愈）+call 入口 ｜ ⚠S: 卡片进程与主进程分离——卡片进程只碰 WidgetReviewUtil 安全层，业务数据经 filesDir 文件交接
**ReviewWidgetCard.ets** 351 行 ｜ F: 卡片 UI（2x2/2x4 三形态、正反面、评分按钮、继续复习 pill、音标发音） ｜ ⚠S: 卡片进程 @LocalStorageProp 消费 binding
**EntryBackupAbility.ets** 9 行 ｜ F: 系统备份扩展空壳（无逻辑勿动）

---

## 附：新会话快速定位口诀

改对话/AI 功能→ChatPage+ApiClient+ChatModel｜改画布→BBTreeCanvas+ChatModel｜改设置→GlobalSettingsDialog｜改文档加载→DocParseUtil+Tc3Signer+TcCrypto｜改词卡库→两 BankPage+两 StoreUtil+两 Model｜改复习→ReviewPage+MemoryAlgorithm｜改同步→CloudSyncUtil（红线）｜改备份→BackupUtil（红线）｜改卡片→WidgetHostBridge+WidgetReviewUtil+EntryFormAbility｜改主题→AppTheme+DesignTokens（双真相源+UI_GUIDELINES）｜改 prompt→Prompts.ts（十军规）
