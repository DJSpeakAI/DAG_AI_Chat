// ============================================================
// Index.ets — 应用首页入口
// ============================================================
// 本文件是应用的入口页面，负责：
//   - 初始化持久化数据（PersistenceV2 连接）
//   - 从 JSON 恢复气泡树（反序列化）
//   - 首次启动时创建默认气泡树（根节点）
//   - 配置 NavPathStack 导航路由（气泡画布 / 对话页 / 单词库 / 知识库 / 标注页）
//
// 页面导航关系：
//   Index → BBTreeCanvas（气泡画布）→ ChatPage（对话页）→ AnnotationPage（屏幕标注，★ 0.152）
//                                  → WordBankPage（单词库，★ 0.145）
//                                  → KnowledgeBankPage（知识库，★ 0.146）
//   ★ 0.189.1：SettingsPage（设置页）已删除——0.150 起设置走 GlobalSettingsDialog 弹窗，
//   页面零入口成僵尸代码（含已取消的云端 TTS 配置区），随 0.189.1 音频配置移除一并清理
// ============================================================

import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import { BBTreeCanvas } from '../components/BBTreeCanvas';
import { ChatPage } from '../components/ChatPage';
import { WordBankPage } from '../components/WordBankPage'; // ★ 0.145：单词库页面路由
import { KnowledgeBankPage } from '../components/KnowledgeBankPage'; // ★ 0.146：知识库页面路由
import { AnnotationPage } from '../components/AnnotationPage'; // ★ 0.152：屏幕圈选标注页路由
import { StatisticsPage } from '../components/StatisticsPage'; // ★ 0.192.0：学习统计页路由
import { BubbleNode, ChatMessage, BubbleTree, ApiConfig, PersistData, generateNodeId, generateMessageId, deserializeBubbleTree, TabMeta, connectCanvasMode, connectTabForest, parseTabs, migrateLegacyPoolsIfNeeded } from '../common/ChatModel';
import { HuaweiAccountStore, connectHuaweiAccount, loginWithHuaweiID, logoutHuaweiID } from '../utils/HuaweiAccountUtil'; // ★ 0.164：华为账号登录
import { BG_APP, SURFACE_HOVER, SURFACE_SOFT, BRAND_PRIMARY, TEXT_PRIMARY, TEXT_SECONDARY, TEXT_TERTIARY, STROKE_BRAND, RADIUS_NAV, RADIUS_CONTROL, FONT_SIZE_META, FONT_SIZE_CAPTION, FONT_SIZE_CARD_TITLE_SM, FONT_INTER_SEMIBOLD } from '../common/DesignTokens'; // ★ 0.174.1：UI Token 单一来源（删 isDark 三元——v0.166.3 锁暗色后浅色分支是死代码）；★ 0.174.2：删 BRAND_SECONDARY/RADIUS_LOGO（首页 Logo 区移除后无引用）
import { common } from '@kit.AbilityKit'; // ★ 0.164：登录接口需要 Context

// 首页入口 — V2 全量迁移
@Entry
@ComponentV2
struct Index {
  pathStack: NavPathStack = new NavPathStack();

  // ★ 0.164：登录/退出请求进行中标记（防连点，官方 1001500002 重复请求错误码要求点击控制）
  @Local isProcessing: boolean = false;
  // ★ 0.164：登录/退出的结果提示（空串 = 无提示）
  @Local loginTip: string = '';

  // ★ 0.164：获取华为账号登录态（PersistenceV2 单例）
  getHuaweiAccount(): HuaweiAccountStore {
    return connectHuaweiAccount();
  }

  // ★ 0.164：点击华为账号登录
  doLogin() {
    if (this.isProcessing) {
      return;
    }
    this.isProcessing = true;
    this.loginTip = '';
    const context = this.getUIContext().getHostContext() as common.Context;
    loginWithHuaweiID(context).then((tip: string) => {
      this.isProcessing = false;
      if (tip !== '') {
        this.loginTip = tip;
      }
    });
  }

  // ★ 0.164：点击退出账号
  doLogout() {
    if (this.isProcessing) {
      return;
    }
    this.isProcessing = true;
    this.loginTip = '';
    const context = this.getUIContext().getHostContext() as common.Context;
    logoutHuaweiID(context).then((tip: string) => {
      this.isProcessing = false;
      if (tip !== '') {
        this.loginTip = tip;
      }
    });
  }

  // ★ 0.164：登录后显示名（昵称优先；无昵称显示 ID 前 10 位；都没有显示"已登录"）
  getDisplayName(): string {
    const account = this.getHuaweiAccount();
    if (account.nickName !== '') {
      return account.nickName;
    }
    if (account.openID !== '') {
      return `ID: ${account.openID.substring(0, 10)}…`;
    }
    return '已登录';
  }

  aboutToAppear() {
    // PersistenceV2: 持久化 JSON 字符串
    const persist = PersistenceV2.connect(PersistData, 'persist-data', () => new PersistData()) as PersistData;
    // ★ 0.151：按画布模式分支恢复工作区（★ 0.151-bugfix2：互通设计——当前模式的池是权威数据源）
    const canvasModeStore = connectCanvasMode();
    // ★ 0.151-bugfix2：旧版两池隔离遗留数据一次性迁移（互通版切换会全量重建目标池，
    // 不迁移则首次切换即丢非权威池的独立数据；migrated 标记保证仅执行一次）
    migrateLegacyPoolsIfNeeded(canvasModeStore.mode);
    if (canvasModeStore.mode === 'tabs') {
      // 选项卡模式：工作区加载当前选中 Tab 的树（无 Tab = 空树，等用户点 ➕ 创建）
      const forest = connectTabForest();
      const tabs = parseTabs(forest.tabsJson);
      const active = tabs.find((t: TabMeta): boolean => t.id === forest.activeTabId);
      const tabTree = active ? deserializeBubbleTree(active.treeJson) : null;
      if (tabTree) {
        AppStorageV2.connect(BubbleTree, 'bubble-tree', () => tabTree);
      } else {
        AppStorageV2.connect(BubbleTree, 'bubble-tree', () => new BubbleTree());
      }
    } else {
      // 平铺模式（现状路径）：尝试从平铺池 JSON 恢复 BubbleTree
      const loaded = deserializeBubbleTree(persist.bubbleTreeJson);
      if (loaded) {
        AppStorageV2.connect(BubbleTree, 'bubble-tree', () => loaded);
      } else {
        // 首次启动，创建默认气泡树
        AppStorageV2.connect(BubbleTree, 'bubble-tree', () => {
          const rootId = generateNodeId();
          return new BubbleTree([
            new BubbleNode(rootId, null, [
              new ChatMessage(generateMessageId(), 'user', '你好'),
              new ChatMessage(generateMessageId(), 'assistant', '1')
            ], 200, 200)
          ]);
        });
      }
    }
    // PersistenceV2：API 配置持久化，跨重启保存
    PersistenceV2.connect(ApiConfig, 'api-config', () => new ApiConfig());
  }

  @Builder
  pageMap(name: string) {
    if (name === 'BBTreeCanvas') {
      BBTreeCanvas({ pathStack: this.pathStack })
    } else if (name === 'ChatPage') {
      ChatPage({ pathStack: this.pathStack })
    } else if (name === 'WordBankPage') { // ★ 0.145：单词库页面（★ 0.189.1：SettingsPage 分支随僵尸页面删除）
      WordBankPage({ pathStack: this.pathStack })
    } else if (name === 'KnowledgeBankPage') { // ★ 0.146：知识库页面
      KnowledgeBankPage({ pathStack: this.pathStack })
    } else if (name === 'AnnotationPage') { // ★ 0.152：屏幕圈选标注页
      AnnotationPage({ pathStack: this.pathStack })
    } else if (name === 'StatisticsPage') { // ★ 0.192.0：学习统计页（边栏「统计」+ 账号行点击）
      StatisticsPage({ pathStack: this.pathStack })
    }
  }

  build() {
    // ★ 0.174.1：Stack 全局背景层——页面根组件 origBounds 全屏，expandSafeArea 背景可铺满
    // 含手势条区（真机实证：Navigation 的 NavBarContent 布局高度只到 y2024，底部 420px 为
    // NavBar toolbar 预留且 clip 裁剪，Column 在其内 expandSafeArea 底部无法突破露黑；
    // Stack 在 Navigation 外不受 NavBar 裁剪，背景直达全屏——各页安全区统一露暗紫不露黑）
    Stack() {
    Navigation(this.pathStack) {
      // 首页内容（★ 0.174.1：按 UI_GUIDELINES 重做——BG_APP 暗紫底 + expandSafeArea 满屏 +
      // Logo 区/主按钮/账号区对齐组件规格；删「图结构对话 · 多分支推理」（用户拍板））
      Column() {
        // ★ 0.179.0：布局改「上标题 + 下按钮组」双区结构——顶部/中部/底部弹性占位 2.5:2.5:1
        //   （★ 0.181.1：原 2:3:1，用户要求标题往下挪一点点——顶部 2→2.5 标题区下移约半份弹性、
        //   中部 3→2.5 对冲，按钮组/版本号位置纹丝不动），
        //   主按钮+登录区落至屏幕下部左手拇指区（用户拍板：左手持握大拇指直接按得到，
        //   原垂直居中布局需另一只手按、体验割裂）；标题/副标题同步放大（24→32 / 11→14）
        Blank().layoutWeight(2.5) // ★ 0.181.1：顶部弹性 2→2.5（标题往下挪）；★ 0.179.0：顶部弹性（标题区悬于上部、不贴顶）
        // ★ 0.174.2：删 Logo 区（用户要求去掉首页分叉图标），标题成为首元素
        Text('DAG AI Chat')
          .fontSize(32) // ★ 0.179.0：标题放大 24→32（用户拍板）
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .fontFamily(FONT_INTER_SEMIBOLD)

        Text('你的AI学习伴侣')
          .fontSize(14) // ★ 0.179.0：副标题放大 11→14（用户拍板）
          .fontColor(TEXT_SECONDARY)
          .margin({ top: 8 })

        Blank().layoutWeight(2.5) // ★ 0.181.1：中部弹性 3→2.5（与顶部增量对冲，按钮组位置不动）；★ 0.179.0：中部弹性——把按钮组推至下部拇指区
        // 主按钮（UI_GUIDELINES 六-9 类推：主紫底 + RADIUS_CONTROL 圆角）
        Button('进入气泡树') // ★ 0.179.0：文案「进入对话画布」→「进入气泡树」（与画布页标题统一，用户拍板）
          .height(44)
          .padding({ left: 24, right: 24 })
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(BRAND_PRIMARY)
          .fontColor(TEXT_PRIMARY)
          .borderRadius(RADIUS_CONTROL)
          .onClick(() => {
            this.pathStack.pushPath({ name: 'BBTreeCanvas' });
          })

        // ★ 0.164：华为账号登录区（★ 0.174.1：对齐 UI_GUIDELINES 六-3/4 账号区规格——
        // 容器 SURFACE_SOFT 柔面 + RADIUS_NAV 圆角；未登录=user 图标容器（描边 STROKE_BRAND）+
        // 双行文案；已登录=头像 36 圆形 + 昵称 + 退出按钮）
        if (this.getHuaweiAccount().isLoggedIn) {
          // 已登录：头像 + 显示名 + 退出账号按钮
          Row() {
            if (this.getHuaweiAccount().avatarUri !== '') {
              Image(this.getHuaweiAccount().avatarUri)
                .width(36)
                .height(36)
                .borderRadius(18)
                .clip(true)
            } else {
              Row() {
                Image($r('app.media.user'))
                  .width(18)
                  .height(18)
              }
              .width(36)
              .height(36)
              .borderRadius(18)
              .backgroundColor(SURFACE_HOVER)
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
            }
            Column() {
              Text(this.getDisplayName())
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(FontWeight.Medium)
                .fontColor(TEXT_PRIMARY)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 160 })
              Text('华为账号已登录')
                .fontSize(FONT_SIZE_CAPTION)
                .fontColor(TEXT_TERTIARY)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 10 })
            Button('退出账号')
              .fontSize(FONT_SIZE_CAPTION)
              .height(30)
              .padding({ left: 12, right: 12 })
              .margin({ left: 12 })
              .backgroundColor(SURFACE_HOVER)
              .fontColor(TEXT_SECONDARY)
              .borderRadius(RADIUS_CONTROL)
              .enabled(!this.isProcessing)
              .onClick(() => {
                this.doLogout();
              })
          }
          .margin({ top: 24 })
          .padding(10)
          .borderRadius(RADIUS_NAV)
          .backgroundColor(SURFACE_SOFT)
          .alignItems(VerticalAlign.Center)
        } else {
          // 未登录：图标容器 + 双行文案（组件规格 4：描边 STROKE_BRAND +「同步知识画布到云端」）
          Row() {
            Row() {
              Image($r('app.media.user'))
                .width(18)
                .height(18)
            }
            .width(36)
            .height(36)
            .borderRadius(18)
            .border({ width: 1, color: STROKE_BRAND })
            .backgroundColor(SURFACE_HOVER)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            Column() {
              Text(this.isProcessing ? '登录中…' : '登录华为账号')
                .fontSize(FONT_SIZE_CARD_TITLE_SM)
                .fontWeight(FontWeight.Medium)
                .fontColor(TEXT_PRIMARY)
              Text('同步到云端') // ★ 0.191.0：文案精简（用户指示：删「知识画布」）
                .fontSize(FONT_SIZE_CAPTION)
                .fontColor(TEXT_TERTIARY)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 10 })
          }
          .margin({ top: 24 })
          .padding(10)
          .borderRadius(RADIUS_NAV)
          .backgroundColor(SURFACE_SOFT)
          .alignItems(VerticalAlign.Center)
          .enabled(!this.isProcessing)
          .onClick(() => {
            this.doLogin();
          })
        }
        // ★ 0.164：登录/退出结果提示（错误时显示，深浅色适配）
        if (this.loginTip !== '') {
          Text(this.loginTip)
            .fontSize(12)
            .fontColor('#E53935')
            .margin({ top: 8 })
            .maxLines(8) // ★ 0.164.4：调试期 2→8 行，容纳错误码+服务端 message 完整显示
            .textAlign(TextAlign.Center)
        }

        // ★ 版本号体系（0.160.x）：装机后一眼确认设备代码版本；每次改动编译装机递增末位（0.160.1 → 0.160.2 → ...）
        Text('v0.193.0') // ★ 0.193.0：上下文工程五项（摘要结构化+prompt集中+军规复查+MEMORY瘦身+压缩token化）；——①方案A 会话级高度记忆（模块级Map，读一半离开回来还在原位）②方案B 手动书签（划词「标记」→🔖紫色标记线，跨重启持久化，无记忆时跳书签）③多模态模型高亮（强烈推荐使用+紫色高亮）； // ★ 0.190.8：隐私政策弹窗自定义化——系统灰弹窗→应用暗紫设计语言（华为不强制样式，用户指示按我们的格式）； // ★ 0.190.7：等待态模式小字精简——中回复模式（默认）不显示模式小字，仅短/长特殊模式显示； // ★ 0.190.6：错误场景分类+关于Tab——①classifyStreamError 9场景分类（中文说明+建议+保留原始错误，兜底引导反馈）②设置「关于」Tab：版本号+反馈与联系（邮箱复制/mailto预填设备信息）+隐私政策（上架接AGC隐私声明托管）； // ★ 0.190.5：等待态模式提示+三点动画+AI偏好排版——①等待态视图：三点跳动动画+「AI 正在回复/深度思考 · 短/中/长回复模式」，长模式加「请耐心等待」②WaitingDots 组件自管定时器（0.160.2 秒表失败教训=页级定时器难清理，组件级生命周期零泄漏）③AI 偏好：删自动鼓励描述小字+排版对齐称呼区； // ★ 0.190.4：GLM-5.3-Flash 长回复超时+发送卡死修复——①readTimeout 60s→300s（GLM-5.3-Flash 深度思考不可关闭+长回复生成超60s，DeepSeek 思考可开关不触发）②requestInStream try-catch 兜底（同步异常不再卡死 isLoading）③卡死自愈（isLoading=true && streamController=null 异常态自动恢复，发送永远不再卡死）； // ★ 0.190.3：对话气泡加宽——用户/AI 气泡 maxWidth 85%→90%（用户要求「对话列表宽度再加长一点点」）； // ★ 0.190.2：发图拦截+☰图标回归——①纯文本模型发图拦截（isKnownTextOnlyModel 查预设清单，已知纯文本+含图→弹窗「取消发送/仍要发送」；能力未知不拦截）②两处 onError 检测 image/vision/图片关键词→附加「建议切换多模态模型」③画布左下角 Text('☰') 字符→menu.svg 图标 18×18（git 考古 0.168.4 原始图标，用户说之前那个好看）； // ★ 0.190.1：API配置实测七连调+☰回归——①修 @Builder 按值传参不刷新 bug（切换提供商后模型清单/获取Key链接仍是旧提供商；无参化改读 curPresetIdx 状态驱动）②获取API Key 各跳各自官网③火山引擎→火山方舟+用户指定2模型（deepseek-v4-flash-ga-260731 正式版/glm-5-3-flash-260828），旧260910自动映射④华为MaaS模型ID官方修正（全小写）+补deepseek-v4.1-flash多模态⑤模型小字只标多模态（可发图）/纯文本（多模态高亮紫），价格删+推荐多模态提示⑥删「接口地址已内置」小字⑦画布左下角分叉icon→☰三横线； // ★ 0.190.0：API配置提供商化——①模型提供商2×2卡片（华为云MaaS/火山引擎/DeepSeek 3预设+自定义配置）②预设=模型下拉（预置+「自定义…」填ID）+API Key+「获取API Key ↗」跳官网+内置端点小字；火山=现网2模型、华为=抄CodeArts清单、DeepSeek=官方ID③自定义配置=模型URL（必填）+模型ID+API Key，上下文窗口Tokens不要（用户指示）④ApiConfig加provider（key v2→v3迁移，端点推断）⑤会话级按提供商缓存Key/URL⑥ApiClient零改动（三家均OpenAI兼容+Bearer）； // ★ 0.189.2：口音提示弹窗化+⚙弹窗排版重构——①英式无包提示改 AlertDialog（用户强调：切英式却播美式是重要信息，toast 一闪而过太轻——「系统暂无英式语音包，当前将按美式发音播放」+确定按钮）②美式缺包引导同步弹窗化（引导 ⚙ 下载 Laura）③showAccentDialogs(ui) 共用工厂（WordSpeaker 导出，4 处调用点一行接入）④单词库 ⚙ 设置弹窗三区卡片化（复习显示数量/音标口音/发音语音包各成 SURFACE_SOFT 卡片+RADIUS_CONTROL 圆角，区块标题 14 半粗主色+描述 11 弱化，输入框 SURFACE_NODE 与卡片底形成对比）； // ★ 0.189.1：口音联动+设置页TTS清理——①LocalTtsEngine双引擎（zh聆小珊消息朗读+en-US Laura单词发音真美式）②listVoices运行时查Laura状态（清单不写死，华为上新音色零代码升级）③downloadVoice应用内下载美式语音包（单词库⚙「发音语音包」区）④WordSpeaker口音路由（美式缺包→提示⚙下载；英式无en-GB→一次性提示后照常播）⑤设置页音频API配置区整体删除（GlobalSettingsDialog三区+僵尸SettingsPage整文件）； // ★ 0.189.0：本地TTS免费离线（CoreSpeechKit，云端火山按用户指示取消）——①新建LocalTtsEngine（canIUse探测/懒创建可重试/280字分段/首段抢占+后续排队无缝连播/会话回调requestId集合防旧会话串扰）②WordSpeaker本地引擎化（HTTP合成→base64→临时文件→AVPlayer链路全删，speak签名简化onUnavailable提示）③消息朗读直连本地引擎（云端分段管线+11个管线状态全删，stopTTS简化）④火山TTS配置存档docs/0.165+/0.189.0 §9（端点openspeech 2.0/鉴权三件套/音色bigtts/历史教训，恢复照抄+git历史be98570）⑤设置页音频字段保留休眠（未来恢复云端现成用）； // ★ 0.188.0：知识库复刻记忆算法+三角图标+AI报错诊断——①知识卡同款4字段+遗忘曲线选卡+展示即复习+3档评分（📖→▼/▲紫三角，气泡/提炼弹窗两处）②知识库列表加「下次复习」行+排序3态移顶栏右上角（单词库同款）③单词复习区👆→▼/▲紫色三角（BRAND_SECONDARY，展开态转▲）④streamChat零内容流诊断（extractStreamError：4xx错误体不再被吞成「AI未返回文本内容」，真实原因走onError展示）⑤MemoryAlgorithm核心函数泛化MemoryItem（WordItem|KnowledgeCard联合类型）； // ★ 0.187.0：单词库记忆算法（简化遗忘曲线R=e^(-t/S)，方案B：下次复习=现在+S）——①复习区👆点词展开3档评分（生疏首评10分钟/尚可12小时/熟知2天，复评×0.5/×1.6/×2.4，S上限365天下限10分钟）②展示即复习（抽进复习区即计数，不点评固定顺延6h；到期闸门防抖防重启重抽虚增）③选词替换纯随机（到期词按遗忘风险R升序→新词→未来词）④单词本列表加「下次复习」行+排序3态（最新↓/最早↑/需复习↑）⑤算法纯后台隐藏（MemoryAlgorithm.ets），完整文档docs/0.165+/0.187.0； // ★ 0.186.0：文档管理+AI token优化+核心文档精简线——①docs/按版本段重组织（0.140-0.152/0.160-0.164/0.165+三段+归档archive/），加总索引index.md②分层按需加载（L1总索引/L2段索引/L3详情/L4归档，project_rule.md加§5）③0.164.md 32.6KB→5.2KB精简（砍已排除项细表/错误码速查/AGC步骤/签名执行记录）； // ★ 0.185.0：单词库设置弹窗音标口音切换——美式（默认）/英式两选项，切换先确认（「切换音标后，原先的音标将会被删除」），确认后清空现有音标、后续查词按新口音生成（API 双提示词口音参数化，PersistenceV2 全新 key phonetic-accent-v1）； // ★ 0.184.0：屏幕标注页双升级——①补充要求输入框（圈注后写「标题写什么/内容围绕什么展开」，存入知识库时图+文一起发 AI 按用户要求精准提炼；导入对话/创建子气泡时文字填入对话输入框，addBubble 扩 carryText 随切换回调带入防动画清空）②标注页 UI 对齐暗紫 DesignTokens（isDark 三元/getThemeStore 全清、旧蓝色系→暗紫 token、顶栏撤销/清空 icon 化、返回确认弹窗覆盖补充要求）； // ★ 0.183.0：单词库/知识库两页（含各自设置弹窗）按 UI_GUIDELINES 收敛 DesignTokens——①isDark 三元死代码全清（getThemeStore 方法删除，v0.166.3 锁暗色后亮色分支为死代码）②散落色值全量收敛（操作蓝 #1976D2→BRAND_PRIMARY、删除红 #F44336→DANGER、面板灰 #2C2C2C→SURFACE_NODE、输入框灰 #1E1E1E→SURFACE_SOFT、遮罩 rgba(0,0,0,0.5)→OVERLAY）③圆角字重对齐（8/6/4→RADIUS_CONTROL、12→RADIUS_NAV、FontWeight.Bold→600、顶栏标题 18→FONT_SIZE_SCREEN_TITLE）④列表卡片升级（SURFACE_NODE 底+STROKE_CARD 描边，对齐节点卡片规格）； // ★ 0.182.1：用户实测两连调——①画布空白双击放大两档→一档（1.25），中心移动改走 1/3 距离（直接跳中心太唐突，缓动更流畅）②对话页输入区 🌿 emoji 换 gitbranch 分叉符号 svg（0.182.0 需求1 本意即此处，与 logo 视觉统一）； // ★ 0.182.0：对话页/画布六项体验——①左下角☰换gitbranch分叉符号（与logo视觉统一）②发送按钮与▾合体（内嵌右侧稍大）③喇叭icon调亮（空闲态TEXT_TERTIARY→TEXT_SECONDARY，四处）④点击输入框外任意处收起软键盘（根容器兜底clearFocus+🌿/✏️显式收）⑤画布空白双击=放大两档（1.25²，与+号共用2.0上限）+中心移到双击点⑥选项卡模式根节点删除修复（原静默return，改走deleteTab(activeTabId)自带确认弹窗）； // ★ 0.181.1：首页标题/副标题下移——弹性占位顶部 2→2.5、中部 3→2.5 对冲（用户要求「往下挪动一点点」，标题区下移约半份弹性，按钮组/版本号位置纹丝不动）；★ 0.181.0：ChatPage 按 UI_GUIDELINES 规格化——①约 175 处散落色值全量收敛 DesignTokens（用户气泡主紫+白字、代码高亮语义常量、遮罩分级）②isDark 三元死代码全清（getThemeStore/CodeBlockView isDark 链路删除）③圆角字重对齐（弹窗 RADIUS_NAV/控件 RADIUS_CONTROL/气泡 RADIUS_NODE/标题 600）④发送按钮补主紫背景（原未设背景走系统默认蓝，Material 蓝残留清除）；★ 0.180.0：边栏跳转「单词库/知识库」不再收抽屉——pushPath 覆盖期间 sidebarVisible 保留，返回画布时边栏保持打开（用户要求：从边栏进的页面，返回时边栏继续保持）；★ 0.179.0：①首页主按钮「进入对话画布」→「进入气泡树」（与画布页标题统一）②主按钮+华为账号登录区下移至左手拇指区（Column 改「上标题+下按钮组」双区结构、Blank 弹性占位 2:3:1，用户左手持握大拇指直接按得到、不再需另一只手）③标题放大 24→32、副标题放大 11→14；★ 0.178.0：①冷启动 logo 闪现根治——startWindowIcon 透明化（startIcon.png 换 108×108 全透明图，冷启动只显示背景色不闪任何图形；0.177.0「换新 logo」方向错误被用户否决「绝对不允许」）+ start_window_background base/dark 两处 #FFFFFF/#000000→#120B1F（=BG_APP 应用底色，启动页与首页无缝衔接；启动页在应用进程前由系统按系统深浅色选资源、两处都改保证任何模式暗紫）②画布页信息条标题「知识画布」→「气泡树」（用户拍板）③桌面短名 DAGAI 用户确认保留不动；★ 0.177.0：①IDE 警告「请使用分层图标」修复——app.json5 icon 从 $media:app_logo 改指 $media:layered_image（AppScope 分层图标配置 background=新 logo 深紫版，视觉零变化）②冷启动旧 logo 闪现 0.1s 修复——startWindowIcon 引用的 startIcon.png 仍是 0.163 旧 DAG 气泡 logo（0.174.4 换新 logo 时漏换），用新 logo 深紫版（background.png 同图）替换；★ 0.176.0：画布页信息条左上角返回箭头「←」删除（用户拍板，全设备尺寸——侧边栏工作台落地后画布即主页面，原 pop() 回 Index 入口已由边栏导航承担）；★ 0.175.0：设置弹窗三 Tab 统一协调——①保存右侧加「返回」按钮（次级样式走 requestClose 未保存确认；云同步 Tab 补全宽返回、三 Tab 底部不空）②小字行间距以云同步 Tab 为标准入 UI_GUIDELINES 四章（多行提示小字 lineHeight 18，margin 2/4 节奏不变）③称呼示例「大明」→「好奇宝宝」；★ 0.174.4：纠正 0.174.3 图标方向——app 图标改分叉 logo（用户拍板：gitbranch 视觉锚点，复刻 app 内视觉语言=225° 渐变 #7C4DFF→#A78BFA 底 + 白色分叉图标，GDI+ 生成 1024×1024），app_logo.png + AppScope/entry 两处 background.png 三资源位替换（0.174.3 误换成 DAG 气泡图已覆盖纠正；DAGAI 桌面名保留）；0.174.3：app 图标整体换新 LOGO（白色 DAG 气泡）——app_logo.png（深黑版，大图 3552 高质量缩放 1024×1024）+ AppScope/entry 两处 background.png（深紫版 1024×1024）三资源位替换，桌面/分层图标/申请用 logo 统一视觉锚点；桌面名三处统一改 "DAGAI"（app_name/EntryAbility_label/app_short_name）；0.174.2：删首页 Logo 区（56×56 渐变容器+gitbranch 分叉图标，用户要求去掉），标题成首元素去 margin top 16 保持垂直居中；import 清 BRAND_SECONDARY/RADIUS_LOGO；0.174.1 首页+全局设置按 UI_GUIDELINES 重做——首页 BG_APP 暗紫底 + expandSafeArea 满屏（修高度不满屏）+ Logo 区渐变图标/主按钮/账号区对齐组件规格、删「图结构对话 · 多分支推理」；设置弹窗色值全收敛 DesignTokens（删 isDark 三元）、Tab 行分段控件化、按钮/开关主紫化、面板 SURFACE_NODE+描边；★ 0.173.2 bugfix：双击进不了气泡——单击手势与系统 TapGesture(count:2) 并列绑定时被手势仲裁吃掉识别流，删系统双击手势改单击内手动判定（同气泡两次单击 <300ms=双击进入；单击选中即时反馈不受影响）；0.173.1 四项：①气泡宽 150→170（元信息行「N 条对话 · X分钟前」完整显示不再截断）②单击任意气泡即选中——高亮卡片+「双击进入对话」+连线高亮（与进入后返回选中样式一致，双击仍进对话）③边栏副标题改「你的AI学习伴侣」④删边栏「工作区」标签；0.172.3 气泡树所有节点卡片加最近消息时间——元信息行「N 条对话 · X小时前/昨天/X天前」（最后一条消息 messageId 内嵌时间戳解析，零模型改动、旧数据天然支持）；0.172.2 气泡树间距再减 1/3——verticalSpacing 136→113（气泡间净空 68→45 ≈ 气泡高度×2/3，连线更短；已有树点「重新排列」生效）；0.172.1 气泡树连线缩短——层级间垂直间距 160→136（气泡间净空=气泡高度 68，用户拍板）；0.170.2 手机抽屉内容对齐平板完整版——Logo+应用名+副标题/工作区标签/导航带中文文字/设置/账号行全放开，抽屉同宽 208（原 72 窄栏纯图标分支删除：点击唤出浮层宽度不再是约束）；0.170.1 画布左下角 ☰ 按钮左缘贴边 24→14、右下角缩放控件右缘贴边 24→14（与信息条边距 14 对齐，底缘对齐不变）；0.169.1 AI 回复底部复习区（生词+知识卡）加划词：词/全称/释义/标题/定义行长按弹「翻译/入知识库/复制」三项悬浮栏（无全选/删除，音标行不加）；0.168.4 抽屉唤出改左下角固定 ☰ 按钮（样式同右下角缩放控件、底缘对齐）+删边缘右滑热区与诊断日志（系统手势区占左缘 0~65px：快滑=系统返回/慢拖被吞）；★ 0.168.3 抽屉层 overlay→Stack（overlay 不参与 hit test 真机实证）；0.168.2 唤出判定 onActionEnd（中途唤出→热区卸载触摸流重路由→抬手落点自关死循环）；0.168.1 热区透明穿透修复；0.168 左侧边栏落地：平板 208 常驻（Logo+应用名+工作区+画布/单词库/知识库+设置+账号）/ 手机 72 窄栏抽屉（左下角 ☰ 按钮唤出、点遮罩或空白收起、返回键先收抽屉）；⚙ 移边栏底部；导航 pushPath「哪进哪回」；0.167.8 七项：①大屏分段控件选项固定高 30（track 总高 36 与⚙/➕等高对齐）②小屏加回「知识画布+N个气泡·N条对话」标题统计③小屏信息条 left 28→14 返回箭头左移与➕留白一致④分段控件「画布」改「平铺」⑤删设置弹窗「画布」Tab（切换逻辑归画布页分段控件）⑥bugfix 分段控件切后点不回（applyCanvasModeSwitch 不写 mode、switchCanvasMode 漏写致守卫单向锁死，补 canvasModeStore.mode=targetMode）⑦app图标换新LOGO（app.json5 icon 改指 $media:app_logo，1024×1024 深底白字 DAG 气泡）；0.167.7：①信息条上方留白 24→8 与下方对齐 ②右上角 4 按钮右移（right 28→14）③fitViewport topSafe 随底板新高度重算（flat 64 / tabs 108）；0.167.6：小屏顶栏极简 4 图标 + fitViewport 垂直居中区排除信息条底板；0.167.5：①信息条不透明底板 ②新建按钮恢复双态 ③分段控件全设备放主行⚙左边 ④根气泡 x 轴恒对齐；0.167.4：整体等比缩放 + 缩放限幅方向感知 + 多根纵向堆叠；0.167.3：连线统一中间出发 + 子树占位法防重叠 + 气泡宽 150
          .fontSize(12)
          .fontColor(TEXT_TERTIARY) // ★ 0.174.1：版本号小字收敛 Token（原 isDark 三元随 getThemeStore 删除）
          .margin({ top: 12 })

        Blank().layoutWeight(1) // ★ 0.179.0：底部弹性——版本号与底部留白
      }
      .width('100%')
      .height('100%')
      // ★ 0.179.0：删 justifyContent(Center)——垂直布局改由 Blank 弹性占位（2.5:2.5:1，★ 0.181.1 原 2:3:1）接管
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(BG_APP) // ★ 0.174.1：应用底色暗紫（UI_GUIDELINES Token，替换旧深灰 #1A1A1A）
      .expandSafeArea([SafeAreaType.SYSTEM]) // ★ 0.174.1：背景延伸进状态栏/导航条安全区——首页满屏高度（用户报「高度是短的」；省略 edges 参数=默认全部边，第二参数类型是 SafeAreaEdge 非 SafeAreaType）
    }
    .navDestination(this.pageMap)
    // ★ 0.166.2：Auto 模式下平板宽屏自动切分栏——首页一直占左栏、画布只占右栏（用户实测
    // 「首页一直出现在屏幕左边」）；改 Stack 强制单栏，push 后目标页全屏覆盖，平板与手机一致
    .mode(NavigationMode.Stack)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG_APP) // ★ 0.174.1：全局兜底底色（各页背景未铺到的安全区露暗紫不露黑）
    .expandSafeArea([SafeAreaType.SYSTEM]) // ★ 0.174.1：背景延伸进状态栏/导航条安全区——满屏
  }
}
