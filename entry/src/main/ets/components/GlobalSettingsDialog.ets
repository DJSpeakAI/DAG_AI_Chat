// ============================================================
// GlobalSettingsDialog.ets — 全局设置弹窗（★ 0.150）
// ============================================================
// ★ 0.230.0：设置弹窗开态共享真相源 GlobalSettingsSharedStore——弹窗实例挂 Index 宿主（边栏「设置」
//   入口）/画布 ⚙/对话页 ⚙ 三处，但返回键事件只送达栈顶 NavDestination（词库/知识库/复习/统计/账单页），
//   各页 onBackPressed 原先不知弹窗开态→返回键不关弹窗（0.229.26 审计 B9 实锤：仅画布页有拦截分支）。
//   共享 store 后：任何页 onBackPressed 首分支 connectGlobalSettingsShared().closeReq++ 即触发
//   requestClose（含未保存修改二次确认，0.150 语义原样）。
// 本文件是应用的全局设置弹窗（ChatPage 顶栏 ⚙ 与 BBTreeCanvas 画布 ⚙ 共用同一实例数据）：
//   - Tab 1「API 配置」：★ 0.190.0 提供商化——模型提供商 2×2 卡片（华为云 MaaS / 火山引擎 /
//     DeepSeek 3 预设 + 自定义配置，其他服务商全走自定义）；预设=模型下拉（预置清单+「自定义」
//     填 ID）+ API Key +「获取 API Key ↗」跳官网（端点内置不可编辑）；自定义=模型 URL+模型 ID+
//     API Key 三字段；上下文窗口 Tokens 不要（用户指示：那是开发代码用配置，AI 回复用不到）
//     （★ 0.189.1：音频 Key/音频模型/音频 Endpoint 随云端 TTS 取消整体移除——发音/朗读已走
//     本地 CoreSpeechKit，火山配置存档见 docs/0.165+/0.189.0 §9）
//   - Tab 2「AI 偏好」：自定义称呼（默认空，填写后短/中/长全部回复模式生效）+
//     自动鼓励开关（默认开启，仅中/长回复生成鼓励，短回复不生成）
//   - 保存：两 Tab 全部修改一次写入持久化 + toast「已保存」，不关弹窗（用户自己 ✕）
//   - ✕ 关闭：有未保存修改时 AlertDialog 二次确认（0.135 防误触丢输入教训沿用）
//   - 遮罩点击不关闭（0.148 教训：弹窗内输入中误触遮罩会丢输入）
//
// 设计说明：
//   - 单组件自包含（不拆 ApiConfigPanel 子组件）——未保存状态八项组件内直接可查，
//     避免跨组件传递编辑副本的复杂度
//   - SettingsPage.ets 保留原样（ChatPage ⚙ 改弹窗后无入口引用，零回归风险，未来可清理）
//   - AiPreference 独立 PersistenceV2 key 'ai-preference-v1'（0.143 教训：往已有磁盘
//     快照的类新增字段不落盘；全新 key 首次创建即含全部字段，无此坑）
//
// 技术栈：鸿蒙 ArkUI V2（@ComponentV2 / @Local / @Param）
// ============================================================

import { common } from '@kit.AbilityKit'; // ★ 0.165.2：requestSyncPermission 需要 UIAbilityContext
import deviceInfo from '@ohos.deviceInfo'; // ★ 0.190.6：反馈邮件预填设备型号/系统版本（@kit.BasicKit 在本 SDK 无配置文件，改直接模块导入）
import pasteboard from '@ohos.pasteboard'; // ★ 0.190.6：复制反馈邮箱
import { ApiConfig, AiPreference, connectApiConfig, connectAiPreference, AnchorPref, connectAnchorPref, inferProviderFromEndpoint, LearnCountStore, connectLearnCount, KnowledgeCountStore, connectKnowledgeCount, connectTtsHint, getBuiltinQwenTtsKey, getBuiltinVolcanoTtsKey, getBuiltinVolcanoTtsVoice, ModelAliasStore, connectModelAlias } from '../common/ChatModel'; // ★ 0.190.0：加 inferProviderFromEndpoint（provider 异常值兜底推断）；★ 0.167.8：删画布 Tab——CanvasMode/CanvasModeStore/applyCanvasModeSwitch 引用随删（逻辑已由画布页顶部分段控件承担）；★ 0.195.0：加复习显示两库计数 store（全局设置直达 0=关闭复习区）；★ 0.232.0：connectTtsHint（云端朗读首次配置提示 flag）；★ 0.234.0：AnchorPref/connectAnchorPref（锚点/折叠偏好 anchor-pref-v1）；★ 0.236.0：getBuiltinQwenTtsKey（千问档 Key 预填）；★ 0.236.1：getBuiltinVolcanoTtsKey/Voice（火山档切回兜底回填）；★ 0.238.1：ModelAliasStore/connectModelAlias（别名按模型 ID 一一对应）
import { requestSyncPermission, isCloudSyncGranted, CloudSyncStore, connectCloudSync } from '../utils/CloudSyncUtil'; // ★ 0.165.2：云同步 Tab（权限弹窗 + 状态查询）；★ 0.196.10：状态改响应式——permGranted（权限，开弹窗时查）&& cloudSwitch.enabled（@Trace 开关，实时）
import { connectConfirmDialog } from './AppConfirmDialog'; // ★ 0.196.10：未登录点「开启云同步」→ 登录引导弹窗（Index 根挂载）
import { HuaweiAccountStore, connectHuaweiAccount } from '../utils/HuaweiAccountUtil'; // ★ 0.196.8：云同步与账号绑定——未登录拦截「开启」
import { SubscriptionStore, connectSubscription, isVip } from '../common/ChatModel'; // ★ 0.194.0：云同步 VIP 守卫（到期只锁云同步）
import { connectWordBank } from '../utils/WordStoreUtil'; // ★ 0.205.0：备份 Tab（恢复合并写词库）
import { connectKnowledgeBank } from '../utils/KnowledgeStoreUtil'; // ★ 0.205.0：备份 Tab（恢复合并写知识库）
import {
  buildBackupPayload, writeInternalBackup, restoreFromPayload,
  getBackupSettings, setAutoBackupEnabled, setExternalUri, pickBackupFile, pickAndReadBackupFile,
  writeExternalBackup, maybeAutoBackup, BackupPayload
} from '../utils/BackupUtil'; // ★ 0.205.0数据安全三道防线；★ 0.205.3：删 readInternalBackup/getLastInternalTime（设置页内部备份卡随删）
import { track, isTrackingEnabled, setTrackingEnabled } from '../utils/TrackUtil'; // 0.206.0 埋点+隐私开关
import { FaceModeStore, connectFaceMode } from '../common/FaceModeStore'; // ★ 0.224.0：卡面模式全局单通道（司忆区 Tab 即时控件）
import { FoldChevron } from './FoldChevron'; // ★ 0.237.0：全项目唯一折叠指示器（军令统一）
import { WindowMode, connectWindowMode } from '../common/WindowMode'; // ★ 0.232.1：弹窗宽度断点制（PC/Pad 固定 560 不做屏宽自适应——用户拍板「配置类 UI 自适应宽度难看」）
import { setWidgetFace } from '../utils/WidgetReviewUtil'; // ★ 0.224.0：卡面变更即时推桌面卡片
import { qianwenTts, fetchQwenVoiceList, QwenVoiceItem } from '../utils/QianwenTtsEngine'; // ★ 0.236.0：千问 TTS 引擎（试听 speakWithParams + 复刻音色列表拉取）
import { cloudTts } from '../utils/CloudTtsEngine'; // ★ 0.236.1：火山/自定义档试听（speakWithParams 显式传参）
import { http } from '@kit.NetworkKit'; // ★ 0.238.0：测试连接（非流式轻量 POST，零侵入 streamChat 主链路）

import { USER_AGREEMENT_SECTIONS, PRIVACY_SECTIONS, HUAWEI_ACCOUNT_AGREEMENT_URL, needsAgreement, connectAgreementBridge, revokeAgreement, AGREEMENT_USER_NAME, AGREEMENT_HUAWEI_NAME } from '../utils/Agreement'; // ★ 0.226.0：协议正文单一来源 + 同意拦截/撤回
// ★ 0.174.1：UI 规格化——散落色值/isDark 三元收敛到 DesignTokens（0.166.3 锁暗色后浅色分支是死代码；AppStorageV2/ThemeStore 引用随 getThemeStore 删除）
import { SURFACE_NODE, SURFACE_HOVER, SURFACE_SOFT, BRAND_PRIMARY, BRAND_SECONDARY, TEXT_PRIMARY, TEXT_SECONDARY, TEXT_TERTIARY, STROKE_CARD, SEGMENTED_TRACK, RADIUS_CONTROL, RADIUS_NAV, RADIUS_LOGO, FONT_SIZE_SCREEN_TITLE, FONT_SIZE_CARD_TITLE_SM, FONT_INTER_SEMIBOLD, DANGER, SUCCESS } from '../common/DesignTokens'; // ★ 0.190.1：加 BRAND_SECONDARY（模型多模态标注高亮）；★ 0.195.0：加 DANGER（复习显示输入校验错误）；★ 0.238.0：加 SUCCESS（测试连接成功绿）
import { AppStorageV2 } from '@kit.ArkUI'; // ★ 0.230.0：GlobalSettingsSharedStore（开态跨页共享——返回键拦截）
import { BusinessError } from '@kit.BasicServicesKit'; // ★ 0.238.0：测试连接 http 异常捕获

// ============================================================
// ★ 0.190.0/0.190.1：模型提供商预设（3 预设 + 自定义配置）
// ============================================================
// 用户拍板：默认只做 3 个提供商（华为云 MaaS / 火山方舟 / DeepSeek），其他全部走「自定义
// 配置」；上下文窗口 Tokens 不要（那是开发代码用配置）；每个预设带「获取 API Key」链接
// 跳**各自**官网；模型小字只标「多模态（可发图）/纯文本」——价格不标（太乱，用户自己上
// 官网对比）；推荐使用多模态模型（可发图片，AI 能识别图片内容）。
// 模型 ID 事实（2026-10 官方文档核实，ID≠展示名，全小写为主）：
//   - 华为云 MaaS 模型列表页：glm-5.2 / glm-5.1 / kimi-k2.6 / deepseek-v4-pro /
//     deepseek-v4-flash / deepseek-v4.1-flash（★0.190.1 修正：Kimi/DeepSeek 此前误大写；
//     deepseek-v4.1-flash 是 MaaS 文档图片理解示例模型=多模态，其余五个能力表无视觉=纯文本）
//   - DeepSeek 官方：deepseek-v4-pro / deepseek-v4-flash（旧 deepseek-chat/reasoner
//     2026-07-24 弃用；deepseek-v4-flash 现由多模态的 V4.1-Flash 服务）
//   - 火山方舟（★0.190.1 用户指定）：deepseek-v4-flash-ga-260731（V4-Flash 正式版，
//     用户确认多模态）/ glm-5-3-flash-260828（多模态）
// 端点（三家均 OpenAI 兼容 + Bearer 鉴权 → ApiClient 零改动）：
//   - 华为云 MaaS：https://api.modelarts-maas.com/openai/v1/chat/completions
//   - DeepSeek：  https://api.deepseek.com/chat/completions
//   - 火山方舟：  https://ark.cn-beijing.volces.com/api/v3/chat/completions
interface PresetModel {
  id: string;    // 模型 ID（传给 API 的值）
  name: string;  // 显示名称
  desc: string;  // 能力标注：多模态（可发图）/ 纯文本
}

// ★ 0.238.0：测试连接请求体（非流式最小请求——OpenAI 兼容 chat/completions）
interface ConnTestMessage {
  role: string;
  content: string;
}
interface ConnTestRequestBody {
  model: string;
  messages: ConnTestMessage[];
  max_tokens: number;
  stream: boolean;
}

interface ProviderPreset {
  id: string;            // 'huawei' | 'volcano' | 'deepseek'
  name: string;          // 卡片显示名
  desc: string;          // 卡片小字
  endpoint: string;      // 内置端点（OpenAI 兼容 chat/completions，预设不可编辑）
  keyUrl: string;        // 「获取 API Key」跳转链接（各自官网）
  keyPlaceholder: string; // API Key 输入框占位文案
  models: PresetModel[]; // 预置模型（下拉末位 UI 层另挂「自定义…」选项）
}

const PROVIDER_PRESETS: ProviderPreset[] = [
  {
    id: 'huawei', name: '华为云 MaaS', desc: 'ModelArts 模型即服务',
    endpoint: 'https://api.modelarts-maas.com/openai/v1/chat/completions',
    keyUrl: 'https://console.huaweicloud.com/maas/',
    keyPlaceholder: '填入华为云 MaaS API Key',
    models: [ // ID 全部来自华为云 MaaS 官方「模型列表」页（2026-10 核实）
      { id: 'deepseek-v4.1-flash', name: 'DeepSeek-V4.1-Flash', desc: '多模态（可发图）' },
      { id: 'glm-5.2', name: 'GLM-5.2', desc: '纯文本' },
      { id: 'glm-5.1', name: 'GLM-5.1', desc: '纯文本' },
      { id: 'kimi-k2.6', name: 'Kimi-K2.6', desc: '纯文本' },
      { id: 'deepseek-v4-pro', name: 'DeepSeek-V4-Pro', desc: '纯文本' },
      { id: 'deepseek-v4-flash', name: 'DeepSeek-V4-Flash', desc: '纯文本' },
    ]
  },
  {
    id: 'volcano', name: '火山方舟', desc: '方舟大模型 · 现网默认', // ★ 0.190.1：火山引擎→火山方舟（用户改名）
    endpoint: 'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
    keyUrl: 'https://console.volcengine.com/ark',
    keyPlaceholder: '填入火山方舟 API Key',
    models: [ // ★ 0.190.1：用户指定 2 模型（V4-Flash 正式版替换旧 260910 预览版）
      { id: 'deepseek-v4-flash-ga-260731', name: 'DeepSeek-V4-Flash 正式版', desc: '多模态（可发图）' },
      { id: 'glm-5-3-flash-260828', name: 'GLM-5.3-Flash', desc: '多模态（可发图）' },
    ]
  },
  {
    id: 'deepseek', name: 'DeepSeek', desc: 'DeepSeek 开放平台',
    endpoint: 'https://api.deepseek.com/chat/completions',
    keyUrl: 'https://platform.deepseek.com/api_keys',
    keyPlaceholder: '填入 DeepSeek API Key',
    models: [ // 官方文档 ID（deepseek-v4-flash 现由多模态 V4.1-Flash 服务）
      { id: 'deepseek-v4-pro', name: 'DeepSeek-V4-Pro', desc: '纯文本' },
      { id: 'deepseek-v4-flash', name: 'DeepSeek-V4-Flash', desc: '多模态（可发图）' },
    ]
  },
];

const PROVIDER_CUSTOM: string = 'custom'; // 自定义配置（任意 OpenAI 兼容服务）

// ★ 0.232.0：云端语音朗读（火山 openspeech）内置端点——TTS 配置区「火山引擎」预设
const TTS_VOLCANO_ENDPOINT: string = 'https://openspeech.bytedance.com/api/v3/tts/unidirectional';

// ★ 0.232.1：音频模型预设（用户提供官方体系；2026-10-14 实证 seed-icl-2.0+S_ 音色 code=0 直连）
interface TtsModelPreset {
  id: string;
  name: string;
  desc: string;
}

const TTS_MODEL_PRESETS: TtsModelPreset[] = [
  { id: 'seed-icl-2.0', name: '声音复刻 2.0', desc: '合成音色（音色 ID 可填，S_ 前缀）' },
  { id: 'seed-tts-2.0', name: '豆包语音合成 2.0', desc: '官方音色（音色 ID 置灰不可填）' },
];

// 官方音色（seed-tts-2.0 专用——2.0 模型只能用 2.0 官方音色，0.139 教训）
const TTS_OFFICIAL_VOICE: string = 'zh_female_vv_uranus_bigtts';

// ★ 0.236.2：开发期临时默认音色（用户拍板「音色 ID 默认填写，上线之前我会命令给删除的」）
const TTS_DEFAULT_VOICE: string = 'S_bv8H32Sg2';

// ★ 0.236.0：千问 TTS（百炼 CosyVoice 复刻音色）预设
const TTS_PROVIDER_QWEN: string = 'qianwen'; // ttsProvider 三值之一（volcano/qianwen/custom 三引擎物理互斥）
const TTS_QWEN_DEFAULT_MODEL: string = 'cosyvoice-v3.5-plus'; // 空值兜底（引擎内同款常量）
// 情感档位（引擎内映射百炼 instruction 自然语言指令——2026-10-14 实测无 emotion 枚举字段）
const TTS_EMOTION_PRESETS: string[] = ['默认', '开心', '中立', '生气', '悲伤', '惊讶'];

// ★ 0.236.0：TTS 三档会话级缓存（切档快照/恢复——档内编辑值不丢；仅会话存活不持久化）
class TtsTabCache {
  key: string = '';
  voice: string = '';
  endpoint: string = '';
  modelSel: number = 0;      // 火山/自定义档：模型下拉选中（TTS_MODEL_PRESETS.length=自定义模型）
  modelText: string = '';    // 火山/自定义档：「自定义模型」手填模型 ID
  qwenModel: string = TTS_QWEN_DEFAULT_MODEL; // 千问档：模型 TextInput
  emotion: string = '开心';  // 千问档：情感档位
  speed: number = 1.0;       // 千问档：语速
  volume: number = 50;       // 千问档：音量
}

// ★ 0.190.6：应用版本常量（关于 Tab 显示 + 反馈邮件预填）——与 Index.ets 版本号、app.json5
// versionCode 三处同步（改版本时同步更新此处）
const APP_VERSION: string = 'v0.240.0'; // ★ 0.240.0：手机端搜索栏滚动隐藏 + 排序按钮图标化（两库同款）；上一版 0.239.0：知识库双视图+加号菜单
// ★ 0.190.6：反馈邮箱（用户提供）
const FEEDBACK_EMAIL: string = '1725912449@qq.com';

// ★ 0.226.0：隐私政策 / 用户协议正文改由 utils/Agreement.ets 单一来源提供
// （原 0.190.8 本地 PRIVACY_SECTIONS「本应用不收集、不上传任何个人信息」与体验改进埋点矛盾，
//  已随本次同意机制统一改写并迁移；关于页正文弹窗按 legalViewing 选择展示哪一份）

// ★ 0.190.1：旧版模型 ID → 新清单映射（火山 260910 预览版已被 260731 正式版替代，
// 用户明确「改成我用那个 Flash 正式版」——回显时自动落新模型，保存即生效）
function mapLegacyModel(id: string): string {
  if (id === 'deepseek-v4-1-flash-260910') {
    return 'deepseek-v4-flash-ga-260731';
  }
  return id;
}

// ★ 0.190.2：预设模型能力查询（ChatPage 发图拦截用，用户批准方案）——
// 已知纯文本返回 true；多模态 / 自定义配置 / 预设清单外手填 ID 一律返回 false
// （能力未知不拦截——等对方 API 报错走 onError 关键词提示，不误伤）
export function isKnownTextOnlyModel(provider: string, model: string): boolean {
  for (let i = 0; i < PROVIDER_PRESETS.length; i++) {
    if (PROVIDER_PRESETS[i].id === provider) {
      for (let j = 0; j < PROVIDER_PRESETS[i].models.length; j++) {
        if (PROVIDER_PRESETS[i].models[j].id === model) {
          return !PROVIDER_PRESETS[i].models[j].desc.startsWith('多模态');
        }
      }
      return false; // 预设提供商 + 清单外手填 ID：能力未知，不拦截
    }
  }
  return false; // 自定义配置：能力未知，不拦截
}

// ★ 0.189.1：AUDIO_MODEL_LIST（预置音频模型）已随云端 TTS 配置区移除

// ★ 0.230.0：设置弹窗开态共享真相源（会话级 AppStorageV2——见文件头注释）
@ObservedV2
export class GlobalSettingsSharedStore {
  @Trace visible: boolean = false;
  @Trace closeReq: number = 0; // 外部请求关闭计数器（onBackPressed 递增→挂载点传参→requestClose 含未保存确认）
}
export function connectGlobalSettingsShared(): GlobalSettingsSharedStore {
  return AppStorageV2.connect(GlobalSettingsSharedStore, 'global-settings-shared', () => new GlobalSettingsSharedStore()) as GlobalSettingsSharedStore;
}

// 全局设置弹窗 — Tab1 API 配置（原 SettingsPage 搬入）+ Tab2 AI 偏好（★ 0.150 新增）
@ComponentV2
export struct GlobalSettingsDialog {
  @Param onClose: () => void = () => {}; // 关闭回调（父组件置 visible=false；✕/确认关闭统一走这里）
  @Param closeReq: number = 0; // ★ 0.150：外部请求关闭计数器（父组件返回键路径递增触发；走 requestClose 含未保存确认）

  apiConfig: ApiConfig = connectApiConfig();       // ★ 0.143：换 key 'api-config-v2' 工厂
  aiPreference: AiPreference = connectAiPreference(); // ★ 0.150：全新 key 'ai-preference-v1'
  anchorPref: AnchorPref = connectAnchorPref(); // ★ 0.234.0：全新 key 'anchor-pref-v1'（锚点卡片/密度/分章折叠）
  wordBank = connectWordBank(); // ★ 0.205.0：备份恢复合并写词库
  knowledgeBank = connectKnowledgeBank(); // ★ 0.205.0：备份恢复合并写知识库
  // ★ 0.205.0 备份 Tab 状态快照（进 Tab 时从 preferences 刷新——非响应式存储，手动同步）
  @Local bkAutoEnabled: boolean = false;
  @Local bkUriReady: boolean = false;   // 已选目录（uri 只存不显示——系统 uri 串对用户无意义）
  @Local bkLastExt: number = 0;         // 上次外部备份时间戳
  @Local bkBusy: boolean = false;       // picker/写入进行中（防重复点击）
  // ★ 0.206.0：体验改进计划开关（埋点隐私闸门，默认关——开弹窗见关于 Tab）
  @Local trkEnabled: boolean = false;

  // Tab 切换（自绘按钮 + 条件渲染，不用 Tabs 组件）
  // ★ 0.167.8 用户拍板：删「画布」Tab（画布多树模式切换已由画布页顶部分段控件承担，此处重复）；
  //   currentTab 索引保持 0=API 配置 / 1=AI 偏好 / 3=云同步 不重排（避免误伤云同步分支）
  @Local currentTab: number = 0;

  // ★ 0.224.0：卡面模式全局单通道（司忆区 Tab 即时控件——与复习页 ⚙ 同一 @ObservedV2 实例，
  //   两处任一变更互相同步+即时推桌面卡片；@Local 接管 0.221.4 铁律）
  @Local faceMode: FaceModeStore = connectFaceMode();

  // Tab1 编辑副本（点保存才写入持久化）★ 0.190.0：提供商化重构
  @Local editProvider: string = 'volcano';     // huawei / volcano / deepseek / custom
  @Local curPresetIdx: number = 1;             // ★ 0.190.1：当前预设下标（0=华为/1=火山/2=DeepSeek；custom 时保持旧值不渲染）——@Builder 按值传参不刷新（真机实测：切换提供商后模型清单/获取Key链接仍是旧提供商），改由状态驱动
  @Local selectedModelIndex: number = 0;        // 预设模型下拉选中索引（=models.length 表示「自定义…」）
  @Local isModelDropdownOpen: boolean = false;  // 模型下拉面板展开状态
  @Local editCustomModel: string = '';          // 「自定义…」模型 ID / 自定义配置的模型 ID
  @Local editKey: string = '';                  // API Key
  @Local editEndpoint: string = '';             // 自定义配置的模型 URL（预设端点内置不可编辑）
  // ★ 0.190.0：会话级按提供商缓存 Key/URL——切换提供商不丢已输入内容（仅「保存」才落盘）
  providerKeyCache: Map<string, string> = new Map();
  providerEndpointCache: Map<string, string> = new Map();

  // ★ 0.238.0：模型别名编辑副本（全局单值——不随提供商切换快照/恢复，4 提供商共用一份）
  //   ★ 0.238.1：升级「按模型 ID 一一对应」——editAlias 仍单值（当前表单选中模型的别名），
  //   切提供商/切模型时自动从 aliasStore 带出对应模型的别名（输入实时记录，跨重启保留）
  @Local editAlias: string = '';
  // ★ 0.238.1：别名映射表（模型 ID→别名，独立 key 'model-alias-v1'——表单回显用）
  @Local aliasStore: ModelAliasStore = connectModelAlias();
  // ★ 0.238.0：测试连接（表单当前值发一次最小真实请求；进行中按钮禁用防连点）
  @Local testing: boolean = false;      // 执行中（按钮禁用）
  @Local testResult: string = '';       // 结果文案（空=未测过）
  @Local testOk: boolean = false;       // 结果着色（true 绿 / false 红）

  // ★ 0.232.0：TTS 编辑副本（API Tab 底部「语音朗读」区——点保存才落盘；提供商从端点推导，零新持久化字段）
  // ★ 0.236.0：提供商三档化（volcano / qianwen / custom 三引擎物理互斥——editTtsProvider 从
  //   apiConfig.ttsProvider 直读，端点推导仅作旧数据首迁兜底）
  @Local editTtsProvider: string = 'volcano'; // volcano / qianwen / custom
  @Local editTtsModelSel: number = 0;         // 模型下拉选中（0=声音复刻2.0 默认 / 1=豆包语音合成2.0 / 2=自定义模型（0.237.2 改名））
  @Local editTtsModel: string = '';           // 「自定义模型」模型 ID（手填；sel=2 时生效）
  @Local editTtsKey: string = '';             // API Key（三档各自语义：火山=豆包语音 Key / 千问=sk-ws- Key / 自定义）
  @Local editTtsVoice: string = '';           // 音色 ID（火山=S_ 合成音色 / 千问=复刻 voice_id；自定义隐藏）
  @Local editTtsEndpoint: string = '';        // 自定义端点 URL（千问/火山端点内置）
  @Local isTtsModelDropdownOpen: boolean = false; // 模型下拉面板展开状态
  // ★ 0.236.0：千问档专属字段（情感/语速/音量只给千问档暴露——用户拍板 #4）
  @Local editTtsQwenModel: string = TTS_QWEN_DEFAULT_MODEL; // 千问模型 TextInput（默认 cosyvoice-v3.5-plus）
  @Local editTtsEmotion: string = '开心';     // 情感档位（默认开心——用户拍板）
  @Local editTtsSpeed: number = 1.0;          // 语速 0.5~2.0 步进 0.05
  @Local editTtsVolume: number = 50;          // 音量 0~100 步进 5
  // ★ 0.236.0：千问档音色拉取（会话内存——每次开弹窗重拉，音色列表不是持久数据）
  @Local ttsVoiceList: QwenVoiceItem[] = []; // 拉取到的复刻音色（status=OK；多个音色=多行渲染）
  @Local ttsVoiceLoading: boolean = false;   // 拉取中
  @Local isTtsVoiceDropdownOpen: boolean = false; // 音色下拉面板展开
  @Local isTtsEmotionDropdownOpen: boolean = false; // 情感下拉面板展开
  // ★ 0.236.0：千问档试听（以当前表单值走引擎完整链路——出声=配置即验）
  @Local ttsPreviewing: boolean = false;
  // ★ 0.236.0：三档会话级缓存（切档快照恢复——取代 0.232.2 火山双字段缓存）
  ttsTabCaches: Map<string, TtsTabCache> = new Map();
  // ★ 0.232.2：TTS 区折叠态（默认收起——低频功能不占屏，用户拍板：一行提示+小三角点击展开）
  @Local ttsCollapsed: boolean = true;
  // ★ 0.232.1：窗口宽度共享真相源（弹窗宽度断点制；@Local 接管 0.221.4 铁律，分档直读实例字段）
  @Local windowMode: WindowMode = connectWindowMode();

  // ★ 0.150 Tab2 编辑副本（AI 偏好）
  @Local editNickname: string = '';   // 自定义称呼（空 = 不添加称呼）
  @Local editEncourageMode: string = 'light'; // ★ 0.191.0：鼓励三档（off/light/heavy，默认轻度=原开关开）
  // ★ 0.234.0：注意力锚点编辑副本（锚点卡片开关/密度档/分章折叠开关——保存模式同称呼/鼓励）
  @Local editAnchorMode: string = 'on';       // off / on（默认开=钩子模式）
  @Local editAnchorDensity: string = 'standard'; // dense 密 / standard 中（默认）/ sparse 疏
  @Local editFoldMode: string = 'on';         // off / on（默认开=折叠模式）
  // ★ 0.196.10：云同步状态改响应式——permGranted（系统权限，开弹窗时异步查一次）&&
  //   cloudSwitch.enabled（应用级开关 @Trace，登录弹窗开启/退出强制关时**实时刷新**状态卡，
  //   不用重开设置弹窗；原 @Local syncGranted 开弹窗快照一次，开启后状态卡滞留「未开启」）
  @Local permGranted: boolean = false;
  cloudSwitch: CloudSyncStore = connectCloudSync();
  @Computed
  get syncOn(): boolean {
    return this.permGranted && this.cloudSwitch.enabled;
  }
  // ★ 0.232.0：云端朗读已启用（读持久化真值——保存后即时翻转状态标签）
  // ★ 0.236.0：三档分判 + 显示引擎名（volcano/qianwen=Key+模型（qwen 另需音色——cosyvoice 无系统音色）；custom=端点+模型+Key）
  @Computed
  get ttsCloudOn(): boolean {
    if (this.apiConfig.ttsProvider === TTS_PROVIDER_QWEN) {
      return this.apiConfig.audioKey.trim().length > 0 && this.apiConfig.audioVoice.trim().length > 0;
    }
    return this.apiConfig.audioKey.trim().length > 0 && this.apiConfig.audioModel.trim().length > 0;
  }

  // ★ 0.236.0：云端引擎名（状态卡标签用——「云端已启用·千问/火山/自定义」）
  ttsProviderLabel(): string {
    if (this.apiConfig.ttsProvider === TTS_PROVIDER_QWEN) {
      return '云端已启用·千问';
    }
    if (this.apiConfig.ttsProvider === 'custom') {
      return '云端已启用·自定义';
    }
    return '云端已启用·火山';
  }
  subscription: SubscriptionStore = connectSubscription(); // ★ 0.194.0：云同步 VIP 守卫
  account: HuaweiAccountStore = connectHuaweiAccount(); // ★ 0.196.8：云同步↔账号绑定——未登录拦截「开启」
  learnCountStore: LearnCountStore = connectLearnCount(); // ★ 0.195.0：复习显示（全局设置直达——0=关闭复习区）
  knowledgeCountStore: KnowledgeCountStore = connectKnowledgeCount(); // ★ 0.195.0：同上（知识卡）
  // ★ 0.195.0：复习显示 Tab 输入态（0/1/2 快速项 + 自由输入框——与两库 ⚙ 设置同款布局）
  @Local reviewWordInput: string = '';
  @Local reviewWordError: string = '';
  @Local reviewCardInput: string = '';
  @Local reviewCardError: string = '';
  // ★ 0.197.2：复习显示编辑副本——原即时生效无保存概念（用户反馈：要保存按钮，与 API/AI 偏好
  //   Tab 交互统一）；快速项/输入确定只写副本，底部「保存」统一落 store（saveAll）
  @Local editReviewLearn: number = 0;
  @Local editReviewKnowledge: number = 0;
  // ★ 0.226.0：法律条款正文弹窗（-1=关闭 / 0=用户协议 / 1=隐私政策；替代系统 AlertDialog 灰弹窗）
  @Local legalViewing: number = -1;

  // ★ 0.189.1：audioModelDisplayName（音频模型 id→名称映射）已随云端 TTS 配置区移除

  aboutToAppear() {
    // ★ 0.190.0：Tab1 提供商化初始化——回显持久化配置
    this.editKey = this.apiConfig.apiKey;
    this.editProvider = this.apiConfig.provider;
    // ★ 0.238.0：模型别名回显 + 测试结果复位（每次开弹窗清零上次结果）
    // ★ 0.238.1：回显后同步把「当前生效模型的落盘别名」灌进映射表（0.238.0 用户已保存过的别名
    //   在 map 里还没有记录——灌一次保证切换再切回能自动带出）
    this.editAlias = this.apiConfig.modelAlias;
    if (this.apiConfig.model.length > 0 && this.apiConfig.modelAlias.length > 0 &&
      this.aliasStore.aliasFor(this.apiConfig.model).length === 0) {
      this.aliasStore.setAlias(this.apiConfig.model, this.apiConfig.modelAlias);
    }
    this.testing = false;
    this.testResult = '';
    this.testOk = false;
    // 0.206.0：体验改进计划开关回显（默认关）
    this.trkEnabled = isTrackingEnabled(this.getUIContext().getHostContext() as common.UIAbilityContext);
    // provider 合法性兜底（防异常值；不合法按端点重新推断）
    let providerValid = this.editProvider === PROVIDER_CUSTOM;
    for (let i = 0; i < PROVIDER_PRESETS.length; i++) {
      if (PROVIDER_PRESETS[i].id === this.editProvider) {
        providerValid = true;
        break;
      }
    }
    if (!providerValid) {
      this.editProvider = inferProviderFromEndpoint(this.apiConfig.endpoint);
    }
    // 按提供商回显模型/端点
    let presetIdx = -1;
    for (let i = 0; i < PROVIDER_PRESETS.length; i++) {
      if (PROVIDER_PRESETS[i].id === this.editProvider) {
        presetIdx = i;
        break;
      }
    }
    // ★ 0.190.1：旧版模型 ID 先映射到新清单（260910 预览版→260731 正式版）
    const persistedModel = mapLegacyModel(this.apiConfig.model);
    if (presetIdx >= 0) {
      this.curPresetIdx = presetIdx;
      this.editEndpoint = PROVIDER_PRESETS[presetIdx].endpoint;
      let found = false;
      for (let i = 0; i < PROVIDER_PRESETS[presetIdx].models.length; i++) {
        if (PROVIDER_PRESETS[presetIdx].models[i].id === persistedModel) {
          this.selectedModelIndex = i;
          found = true;
          break;
        }
      }
      if (!found) {
        // 持久化模型不在预置清单（如旧版手填模型）→ 落在「自定义…」选项回显
        this.selectedModelIndex = PROVIDER_PRESETS[presetIdx].models.length;
        this.editCustomModel = this.apiConfig.model;
      }
    } else {
      // 自定义配置：端点/模型全手填回显
      this.editEndpoint = this.apiConfig.endpoint;
      this.editCustomModel = this.apiConfig.model;
      this.selectedModelIndex = 0;
    }
    // ★ 0.150：Tab2 AI 偏好编辑副本
    this.editNickname = this.aiPreference.aiNickname;
    this.editEncourageMode = this.aiPreference.encourageMode;
    // ★ 0.234.0：注意力锚点编辑副本回显；★ 0.237.0 两档制归一——遗留 'standard'（旧中档）归疏，
    //   不改写已落盘数据（保存时随选择落新值）
    this.editAnchorMode = this.anchorPref.anchorMode;
    this.editAnchorDensity = this.anchorPref.anchorDensity === 'dense' ? 'dense' : 'sparse';
    this.editFoldMode = this.anchorPref.foldMode;
    // ★ 0.232.0：TTS 配置回显（提供商从端点推导——含 bytedance.com=火山预设）
    // ★ 0.232.1：模型改下拉预设回显（icl/tts 两预设 + 清单外手填落「自定义模型」）
    // ★ 0.236.0：三档化——editTtsProvider 从 apiConfig.ttsProvider 直读（非法值→端点推导兜底）；
    //   持久化只存当前档的值（audioKey/audioModel/audioVoice 三档复用承载），非当前档字段用档默认
    const savedTtsProvider = this.apiConfig.ttsProvider;
    this.editTtsProvider = (savedTtsProvider === 'volcano' || savedTtsProvider === TTS_PROVIDER_QWEN ||
      savedTtsProvider === 'custom') ? savedTtsProvider :
      (this.apiConfig.audioEndpoint.includes('bytedance.com') ? 'volcano' : 'custom');
    this.editTtsKey = this.apiConfig.audioKey;
    this.editTtsVoice = this.apiConfig.audioVoice;
    // ★ 0.237.2：端点回显不再预填火山地址——自定义档空值露出「如 …」灰提示（用户拍板）；
    //   火山档端点内置不走此值（currentTtsEndpointValue 恒返内置常量）
    this.editTtsEndpoint = this.apiConfig.audioEndpoint;
    if (this.editTtsProvider === TTS_PROVIDER_QWEN) {
      // 千问档回显：模型（空值兜底默认）/情感/语速/音量；火山下拉侧留默认（值在切档时靠缓存/重填）
      this.editTtsQwenModel = this.apiConfig.audioModel.trim().length > 0
        ? this.apiConfig.audioModel : TTS_QWEN_DEFAULT_MODEL;
      this.editTtsEmotion = this.apiConfig.ttsEmotion;
      this.editTtsSpeed = this.apiConfig.ttsSpeed;
      this.editTtsVolume = this.apiConfig.ttsVolume;
      this.editTtsModelSel = 0;
      this.editTtsModel = '';
    } else {
      // 火山/自定义档：模型回显（★ 0.236.1：火山=预设下拉匹配；自定义=空手填直读持久化值）；
      // 千问侧字段留默认
      if (this.editTtsProvider === 'custom') {
        this.editTtsModelSel = TTS_MODEL_PRESETS.length;
        this.editTtsModel = this.apiConfig.audioModel;
        // ★ 0.236.0 bug 修复：自定义档音色隐藏——回显为空（存盘侧本就存空串）
        this.editTtsVoice = '';
      } else {
        if (this.apiConfig.audioModel === TTS_MODEL_PRESETS[1].id) {
          this.editTtsModelSel = 1;
        } else if (this.apiConfig.audioModel === TTS_MODEL_PRESETS[0].id ||
          this.apiConfig.audioModel.trim().length === 0 ||
          this.apiConfig.audioModel === TTS_QWEN_DEFAULT_MODEL) {
          // ★ 0.237.2：空值/异档残留默认回「声音复刻 2.0」（用户拍板——此前空值落「自定义模型」
          //   显示不对；qwen 模型值=三档复用 audioModel 的千问档存储残留，非火山自定义模型）
          this.editTtsModelSel = 0;
        } else {
          this.editTtsModelSel = 2;
          this.editTtsModel = this.apiConfig.audioModel;
        }
      }
    }
    // ★ 0.237.2：火山档空值回填收口（用户拍板：选「声音复刻 2.0」即见内置 Key d30edab3…与默认音色
    //   S_bv8H32Sg2——回显入口统一走 refillVolcanoDefaults，切档/下拉选中另两入口同函数；
    //   0.236.2 音色回填与 0.236.1 切档 Key 回填一并收编；用户已填值不动）
    if (this.editTtsProvider === 'volcano') {
      this.refillVolcanoDefaults();
    }
    // 千问档首次进入预填内置 Key（用户自定义值优先纪律——仅表单预填不写持久化）
    if (this.editTtsProvider === TTS_PROVIDER_QWEN && this.editTtsKey.length === 0) {
      this.editTtsKey = getBuiltinQwenTtsKey();
    }
    this.ttsCollapsed = true; // ★ 0.232.2：每次开弹窗 TTS 区默认收起（低频功能）
    // ★ 0.195.0：复习显示 Tab 编辑副本回显（0.197.2 保存模式——脏检查对比副本 vs store）
    this.editReviewLearn = this.learnCountStore.learnCount;
    this.editReviewKnowledge = this.knowledgeCountStore.knowledgeCount;
    // ★ 0.196.10：系统权限状态（开弹窗时查一次；开关侧 cloudSwitch.enabled 是 @Trace 实时）
    isCloudSyncGranted().then((granted: boolean) => {
      this.permGranted = granted;
    });
  }

  // ★ 0.135/0.150/0.151：是否有未保存的修改（✕ 关闭拦截判断；★ 0.190.0：提供商化四项对比）
  hasUnsavedChanges(): boolean {
    return this.editProvider !== this.apiConfig.provider ||
      this.editKey.trim() !== this.apiConfig.apiKey ||
      this.currentModelValue() !== this.apiConfig.model ||
      this.currentEndpointValue() !== this.apiConfig.endpoint ||
      this.editAlias.trim() !== this.apiConfig.modelAlias || // ★ 0.238.0：模型别名
      this.editNickname.trim() !== this.aiPreference.aiNickname || // ★ 0.150：称呼
      this.editEncourageMode !== this.aiPreference.encourageMode || // ★ 0.191.0：鼓励三档
      this.editAnchorMode !== this.anchorPref.anchorMode || // ★ 0.234.0：锚点卡片开关
      this.editAnchorDensity !== (this.anchorPref.anchorDensity === 'dense' ? 'dense' : 'sparse') || // ★ 0.237.0：密度档两档归一比较（遗留 standard 按疏算——防开弹窗即恒脏误报「修改未保存」）
      this.editFoldMode !== this.anchorPref.foldMode || // ★ 0.234.0：分章折叠开关
      this.editReviewLearn !== this.learnCountStore.learnCount || // ★ 0.197.2：复习显示（保存模式）
      this.editReviewKnowledge !== this.knowledgeCountStore.knowledgeCount ||
      this.editTtsProvider !== this.apiConfig.ttsProvider || // ★ 0.236.0：TTS 提供商三档
      this.hasUnsavedTtsChanges(); // ★ 0.232.0/0.236.0：TTS 档内字段分档比较（见方法）
  }

  // ★ 0.236.0：TTS 档内字段脏检查（分档比较——audioKey/audioModel/audioVoice 三档复用承载，
  //   持久化值属当前生效档，跨档直比会误报恒脏）
  hasUnsavedTtsChanges(): boolean {
    if (this.editTtsKey.trim() !== this.apiConfig.audioKey) {
      return true;
    }
    if (this.editTtsProvider === TTS_PROVIDER_QWEN) {
      const modelVal = this.editTtsQwenModel.trim().length > 0
        ? this.editTtsQwenModel.trim() : TTS_QWEN_DEFAULT_MODEL;
      return modelVal !== this.apiConfig.audioModel ||
        this.editTtsVoice.trim() !== this.apiConfig.audioVoice ||
        this.editTtsEmotion !== this.apiConfig.ttsEmotion ||
        this.editTtsSpeed !== this.apiConfig.ttsSpeed ||
        this.editTtsVolume !== this.apiConfig.ttsVolume;
    }
    if (this.editTtsProvider === 'custom') {
      // ★ 0.236.1：自定义档=端点+Key+手填模型资源 ID 三字段（无火山预设）
      return this.editTtsModel.trim() !== this.apiConfig.audioModel ||
        this.currentTtsEndpointValue() !== this.apiConfig.audioEndpoint;
    }
    if (this.currentTtsModelValue() !== this.apiConfig.audioModel) {
      return true;
    }
    // ★ 0.232.2：自定义档音色字段隐藏——不参与脏检查/保存（火山音色体系不适用）
    if (this.editTtsProvider === 'volcano' && this.ttsVoiceEditable() &&
      this.editTtsVoice.trim() !== this.apiConfig.audioVoice) {
      return true;
    }
    return this.currentTtsEndpointValue() !== this.apiConfig.audioEndpoint;
  }

  // ★ 0.232.0：当前 TTS 表单端点（火山=内置端点；自定义=手填 URL）
  currentTtsEndpointValue(): string {
    if (this.editTtsProvider === 'volcano') {
      return TTS_VOLCANO_ENDPOINT;
    }
    return this.editTtsEndpoint.trim();
  }

  // ★ 0.232.1：当前 TTS 表单模型（预设下拉或「自定义模型」手填）
  // ★ 0.236.1：自定义档=空手填模型资源 ID（无火山预设下拉——用户拍板「变空」；试听/合成必填）
  currentTtsModelValue(): string {
    if (this.editTtsProvider === TTS_PROVIDER_QWEN) {
      return this.editTtsQwenModel.trim().length > 0 ? this.editTtsQwenModel.trim() : TTS_QWEN_DEFAULT_MODEL;
    }
    if (this.editTtsProvider === 'custom') {
      return this.editTtsModel.trim();
    }
    if (this.editTtsModelSel < TTS_MODEL_PRESETS.length) {
      return TTS_MODEL_PRESETS[this.editTtsModelSel].id;
    }
    return this.editTtsModel.trim();
  }

  // ★ 0.232.1：音色可填判定（豆包语音合成2.0=官方音色体系，音色置灰；声音复刻/自定义模型可填 S_ 音色）
  ttsVoiceEditable(): boolean {
    return this.editTtsModelSel !== 1;
  }

  // ★ 0.237.2：音频 API Key 占位示例「如 + 内置 Key 快照」（用户拍板三字段如式灰提示；
  //   不在源码硬编码 Key 明文——config.json 本就不进 git，快照缺失时回退普通提示）
  ttsKeyPlaceholder(): string {
    if (this.editTtsProvider === TTS_PROVIDER_QWEN) {
      return '填入千问平台 API Key（sk-ws- 开头）';
    }
    const builtinKey = getBuiltinVolcanoTtsKey();
    return builtinKey.length > 0 ? `如 ${builtinKey}（与对话 Key 相互独立）` : '填入豆包语音 API Key（与对话 Key 相互独立）';
  }

  // ★ 0.237.2：火山档空值回填（回显/切档/下拉选中「声音复刻 2.0」三入口统一——用户拍板：
  //   选声音复刻 2.0 即见内置 Key 与默认音色；仅在空值时补位，用户自定义值优先）
  //   ★ 开发期临时纪律：TTS_DEFAULT_VOICE（含本函数音色回填）上线前随用户命令删除（0.236.2 定稿）
  refillVolcanoDefaults(): void {
    if (this.editTtsKey.trim().length === 0) {
      const builtinKey = getBuiltinVolcanoTtsKey();
      if (builtinKey.length > 0) {
        this.editTtsKey = builtinKey;
      }
    }
    // 音色回填仅「声音复刻 2.0」档（豆包合成=官方音色固定；自定义模型音色用户自填不干预）
    if (this.editTtsModelSel === 0 &&
      (this.editTtsVoice.trim().length === 0 || this.editTtsVoice.trim() === TTS_OFFICIAL_VOICE)) {
      const builtinVoice = getBuiltinVolcanoTtsVoice();
      this.editTtsVoice = builtinVoice.length > 0 ? builtinVoice : TTS_DEFAULT_VOICE;
    }
  }

  // ★ 0.236.0：切 TTS 档——三档会话级缓存快照/恢复（切换不丢输入，仅「保存」才落盘）
  //   目标档无缓存=干净起点：火山=模型下拉默认 / 千问=cosyvoice-v3.5-plus+内置 Key 预填 /
  //   自定义=清空+模型落「自定义模型」（0.236.0 bug 修复：切自定义 editTtsModelSel 重置，
  //   此前残留火山下拉值会把 seed-icl-2.0 存进自定义档 audioModel）
  onTtsProviderTap(target: string): void {
    if (target === this.editTtsProvider) {
      return;
    }
    // 1) 快照当前档
    const snap = new TtsTabCache();
    snap.key = this.editTtsKey;
    snap.voice = this.editTtsVoice;
    snap.endpoint = this.editTtsEndpoint;
    snap.modelSel = this.editTtsModelSel;
    snap.modelText = this.editTtsModel;
    snap.qwenModel = this.editTtsQwenModel;
    snap.emotion = this.editTtsEmotion;
    snap.speed = this.editTtsSpeed;
    snap.volume = this.editTtsVolume;
    this.ttsTabCaches.set(this.editTtsProvider, snap);
    // 2) 恢复目标档（无缓存=档默认值）
    const cached = this.ttsTabCaches.get(target);
    this.editTtsProvider = target;
    this.isTtsModelDropdownOpen = false;
    this.isTtsVoiceDropdownOpen = false;
    this.isTtsEmotionDropdownOpen = false;
    if (cached !== undefined) {
      this.editTtsKey = cached.key;
      this.editTtsVoice = cached.voice;
      this.editTtsEndpoint = cached.endpoint;
      this.editTtsModelSel = cached.modelSel;
      this.editTtsModel = cached.modelText;
      this.editTtsQwenModel = cached.qwenModel;
      this.editTtsEmotion = cached.emotion;
      this.editTtsSpeed = cached.speed;
      this.editTtsVolume = cached.volume;
    } else {
      this.editTtsKey = '';
      this.editTtsVoice = '';
      // ★ 0.237.2：自定义档端点干净起点改空串——不预填火山地址，空值露出「如 …」灰提示
      this.editTtsEndpoint = '';
      this.editTtsModel = '';
      this.editTtsQwenModel = TTS_QWEN_DEFAULT_MODEL;
      this.editTtsEmotion = '开心';
      this.editTtsSpeed = 1.0;
      this.editTtsVolume = 50;
      if (target === 'volcano') {
        this.editTtsModelSel = 0;
        // ★ 0.236.1：内置 Key/音色兜底回填（用户实测痛点：切回火山档 Key/音色 ID 全空——
        //   audioKey/audioVoice 被千问档保存覆盖，config.json 内置快照补位显示）；
        //   ★ 0.237.2：统一收口 refillVolcanoDefaults
        this.refillVolcanoDefaults();
      } else if (target === 'custom') {
        this.editTtsModelSel = TTS_MODEL_PRESETS.length; // bug 修复：自定义档干净起点落「自定义模型」
      } else {
        this.editTtsModelSel = 0;
        const builtinKey = getBuiltinQwenTtsKey(); // 千问档：内置 Key 预填（开发期；用户自定义值优先）
        if (builtinKey.length > 0) {
          this.editTtsKey = builtinKey;
        }
      }
    }
  }

  // ★ 0.236.0：拉取千问复刻音色列表（官方 customization 接口；失败中文提示）
  fetchTtsVoices(): void {
    const key = this.editTtsKey.trim();
    if (key.length === 0) {
      this.showToastSafe('请先填写 API Key 再拉取音色');
      return;
    }
    if (this.ttsVoiceLoading) {
      return;
    }
    this.ttsVoiceLoading = true;
    fetchQwenVoiceList(key).then((list: QwenVoiceItem[]) => {
      this.ttsVoiceLoading = false;
      this.ttsVoiceList = list;
      if (list.length === 0) {
        this.showToastSafe('该 Key 下暂无复刻音色——可先选「手动输入」或去千问平台复刻');
        return;
      }
      // 默认选中列表第一个复刻音色（用户拍板 #5）；当前值恰在列表中则保持
      const cur = this.editTtsVoice.trim();
      let hit = false;
      for (let i = 0; i < list.length; i++) {
        if (list[i].voiceId === cur) {
          hit = true;
          break;
        }
      }
      if (!hit) {
        this.editTtsVoice = list[0].voiceId;
      }
    }).catch((err: string) => {
      this.ttsVoiceLoading = false;
      this.showToastSafe(err.length > 0 ? err : '拉取失败：请检查 API Key');
    });
  }

  // ★ 0.236.0：音色下拉开合（打开时 Key 非空且列表未拉过→自动拉取——少一次手动点击）
  onTtsVoiceDropdownTap(): void {
    if (this.isTtsVoiceDropdownOpen) {
      this.isTtsVoiceDropdownOpen = false;
      return;
    }
    this.isTtsVoiceDropdownOpen = true;
    if (this.ttsVoiceList.length === 0 && !this.ttsVoiceLoading && this.editTtsKey.trim().length > 0) {
      this.fetchTtsVoices();
    }
  }

  // ★ 0.236.0：千问档试听（当前表单值直接走引擎完整合成+播放链路——未保存也可验证）
  // ★ 0.236.1：三档全上试听（用户拍板「没试听很傻」）——千问=qianwenTts；火山/自定义=cloudTts
  //   显式传参（火山=内置端点+下拉模型+联动音色；自定义=手填端点+Key+模型，音色空兜底官方）
  onTtsPreviewTap(): void {
    if (this.ttsPreviewing) {
      qianwenTts.stop(); // 双引擎齐停（幂等——只停当前生效引擎，另一个空转无害）
      cloudTts.stop();
      this.ttsPreviewing = false;
      return;
    }
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined || ctx === null) {
      this.showToastSafe('试听失败：上下文不可用');
      return;
    }
    const key = this.editTtsKey.trim();
    if (key.length === 0) {
      this.showToastSafe('请先填写 API Key');
      return;
    }
    this.ttsPreviewing = true;
    let started = false;
    if (this.editTtsProvider === TTS_PROVIDER_QWEN) {
      const voice = this.editTtsVoice.trim();
      if (voice.length === 0) {
        this.ttsPreviewing = false;
        this.showToastSafe('请先选择复刻音色');
        return;
      }
      started = qianwenTts.speakWithParams('你好，这是千问语音试听。', key,
        this.editTtsQwenModel.trim(), voice, this.editTtsEmotion,
        this.editTtsSpeed, this.editTtsVolume, ctx.cacheDir, {
        onStart: () => {},
        onComplete: () => {
          this.ttsPreviewing = false; // 试听播完自动复位
        },
        onError: (message: string) => {
          this.ttsPreviewing = false;
          this.showToastSafe(message.substring(0, 80)); // 引擎已转友好中文
        }
      });
    } else if (this.editTtsProvider === 'custom') {
      const endpoint = this.editTtsEndpoint.trim();
      const model = this.editTtsModel.trim();
      if (endpoint.length === 0 || model.length === 0) {
        this.ttsPreviewing = false;
        this.showToastSafe('请先填写接口地址和模型资源 ID');
        return;
      }
      started = cloudTts.speakWithParams('你好，这是自定义语音试听。', endpoint, key, model, '',
        ctx.cacheDir, {
        onStart: () => {},
        onComplete: () => {
          this.ttsPreviewing = false;
        },
        onError: (message: string) => {
          this.ttsPreviewing = false;
          this.showToastSafe(message.substring(0, 80));
        }
      });
    } else {
      const model = this.currentTtsModelValue();
      if (model.length === 0) {
        this.ttsPreviewing = false;
        this.showToastSafe('请先选择音频模型');
        return;
      }
      const voice = this.ttsVoiceEditable() ? this.editTtsVoice.trim() : TTS_OFFICIAL_VOICE;
      started = cloudTts.speakWithParams('你好，这是火山语音试听。', TTS_VOLCANO_ENDPOINT, key,
        model, voice, ctx.cacheDir, {
        onStart: () => {},
        onComplete: () => {
          this.ttsPreviewing = false;
        },
        onError: (message: string) => {
          this.ttsPreviewing = false;
          this.showToastSafe(message.substring(0, 80));
        }
      });
    }
    if (!started) {
      this.ttsPreviewing = false;
      this.showToastSafe('试听失败：参数不完整');
    }
  }

  // ★ 0.150：外部请求关闭（返回键/返回按钮路径）——父组件递增 closeReq 触发，走 requestClose（有未保存修改时二次确认）
  @Monitor('closeReq')
  onCloseReqChange(): void {
    this.requestClose();
  }

  // ★ 0.150：关闭请求——有未保存修改时 AlertDialog 二次确认，无修改直接关闭
  requestClose(): void {
    if (this.hasUnsavedChanges()) {
      this.getUIContext().showAlertDialog({
        title: '修改未保存',
        message: '有修改尚未保存，确定要关闭吗？',
        primaryButton: {
          value: '继续编辑',
          action: () => {}
        },
        secondaryButton: {
          value: '不保存关闭',
          action: () => {
            this.onClose();
          }
        }
      });
    } else {
      this.onClose();
    }
  }

  // ★ 0.224.0：切换卡面模式（即时生效全局单通道——写共享 store 即同步复习页 ⚙；即时推桌面卡片）
  applyFaceMode(mode: string): void {
    this.faceMode.mode = mode;
    try {
      setWidgetFace(this.getUIContext().getHostContext() as common.Context, mode);
    } catch (_e) {
      // 桌面卡片推送失败静默（下次快照重建自然携带）
    }
  }

  // ★ 0.150：保存——两 Tab 全部修改一次写入持久化 + toast 提示，不关弹窗（用户自己 ✕）
  saveAll(): void {
    // ★ 0.190.0：Tab1 提供商化写入（预设端点强制回内置值，防旧数据残留）
    this.apiConfig.provider = this.editProvider;
    this.apiConfig.apiKey = this.editKey.trim();
    this.apiConfig.model = this.currentModelValue();
    this.apiConfig.endpoint = this.currentEndpointValue();
    this.apiConfig.modelAlias = this.editAlias.trim(); // ★ 0.238.0：模型别名（空=回落官方模型 ID）
    // Tab2：AI 偏好写入持久化（★ 0.150）
    this.aiPreference.aiNickname = this.editNickname.trim();
    this.aiPreference.encourageMode = this.editEncourageMode;
    // ★ 0.234.0：注意力锚点写入（独立 key anchor-pref-v1 即时落盘；ChatPage 读 @Trace 即时生效）
    this.anchorPref.anchorMode = this.editAnchorMode;
    this.anchorPref.anchorDensity = this.editAnchorDensity;
    this.anchorPref.foldMode = this.editFoldMode;
    // ★ 0.197.2：Tab5 复习显示写入（编辑副本→store，PersistenceV2 即时落盘，两处复习区即时生效）
    this.learnCountStore.learnCount = this.editReviewLearn;
    this.knowledgeCountStore.knowledgeCount = this.editReviewKnowledge;
    // ★ 0.232.0：TTS 配置写入（火山=端点强制回内置值，防旧数据残留——与 LLM 预设同款纪律）
    // ★ 0.232.1：豆包语音合成2.0 强制官方音色（2.0 模型只能用 2.0 官方音色，0.139 教训；置灰输入框的落盘侧闭环）
    // ★ 0.236.0：三档分写——ttsProvider 落盘；千问档写 Key/模型/音色/情感/语速/音量
    //   （audioEndpoint 不动——该字段留给火山/自定义体系）；三引擎物理互斥（引擎只认 ttsProvider）
    this.apiConfig.ttsProvider = this.editTtsProvider;
    this.apiConfig.audioKey = this.editTtsKey.trim();
    if (this.editTtsProvider === TTS_PROVIDER_QWEN) {
      this.apiConfig.audioModel = this.editTtsQwenModel.trim().length > 0
        ? this.editTtsQwenModel.trim() : TTS_QWEN_DEFAULT_MODEL;
      this.apiConfig.audioVoice = this.editTtsVoice.trim();
      this.apiConfig.ttsEmotion = this.editTtsEmotion;
      this.apiConfig.ttsSpeed = this.editTtsSpeed;
      this.apiConfig.ttsVolume = this.editTtsVolume;
    } else {
      this.apiConfig.audioModel = this.currentTtsModelValue();
      // ★ 0.232.2：自定义提供商音色不适用（字段已隐藏）——存空串，引擎空值自动兜底官方音色；
      //   豆包语音合成2.0 仍强制官方音色（0.232.1 置灰闭环）
      // ★ 0.237.2：音频模型选「自定义模型」音色恢复可填（推翻 0.233.0 存空串——三字段配套落盘）
      this.apiConfig.audioVoice = this.editTtsProvider !== 'volcano' ? '' :
        (this.ttsVoiceEditable() ? this.editTtsVoice.trim() : TTS_OFFICIAL_VOICE);
      this.apiConfig.audioEndpoint = this.currentTtsEndpointValue();
    }
    // ★ 0.232.0：首次启用云端朗读一次性提示（用户规则：第一次填写音频配置时提示，之后不再）
    const ttsHint = connectTtsHint();
    if (!ttsHint.cloudHintShown && this.ttsCloudOn) {
      ttsHint.cloudHintShown = true;
      this.getUIContext().showAlertDialog({
        title: '云端语音朗读已启用',
        message: '朗读将优先使用云端语音，音色更自然，并自动跳过 Markdown 符号（**、#、代码块不再被读出）。\n未填写 Key 或请求失败时，自动回退本机语音。',
        confirm: {
          value: '知道了',
          action: () => {}
        }
      });
    }
    this.showToastSafe('已保存');
  }

  // ★ 0.149：showToast 可能抛异常（编译器警告「Function may throw exceptions」），try-catch 静默包裹
  showToastSafe(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1500 });
    } catch (_e) {
      // 静默失败（toast 非关键路径）
    }
  }

  // ★ 0.190.0：当前提供商在 PROVIDER_PRESETS 中的下标（-1 = 自定义配置）
  presetIndex(): number {
    for (let i = 0; i < PROVIDER_PRESETS.length; i++) {
      if (PROVIDER_PRESETS[i].id === this.editProvider) {
        return i;
      }
    }
    return -1;
  }

  // ★ 0.190.0：当前表单的模型 ID（保存/未保存对比共用；预设=下拉选中或「自定义」手填，自定义配置=手填）
  currentModelValue(): string {
    const idx = this.presetIndex();
    if (idx < 0) {
      return this.editCustomModel.trim();
    }
    const models = PROVIDER_PRESETS[idx].models;
    if (this.selectedModelIndex < models.length) {
      return models[this.selectedModelIndex].id;
    }
    return this.editCustomModel.trim();
  }

  // ★ 0.190.0：当前表单的端点（预设=内置端点；自定义配置=手填 URL）
  currentEndpointValue(): string {
    const idx = this.presetIndex();
    if (idx < 0) {
      return this.editEndpoint.trim();
    }
    return PROVIDER_PRESETS[idx].endpoint;
  }

  // ★ 0.238.0：测试连接——用表单当前值（未保存也可测）发一次最小真实请求（非流式 + max_tokens 1
  //   + 一句 ping，消耗仅几个 token），成功=配置可用；15s 超时（连接测试不等长请求）；零侵入
  //   streamChat 流式主链路；错误一律中文（项目网络规范 §4 铁律）；testing 状态防连点
  async testConnection(): Promise<void> {
    if (this.testing) {
      return;
    }
    const key = this.editKey.trim();
    if (key.length === 0) {
      this.testOk = false;
      this.testResult = '请先填写 API Key';
      return;
    }
    const endpoint = this.currentEndpointValue();
    const modelId = this.currentModelValue();
    if (endpoint.length === 0 || modelId.length === 0) {
      this.testOk = false;
      this.testResult = '请先填写完整的接口地址与模型';
      return;
    }
    this.testing = true;
    this.testResult = '';
    const start = Date.now();
    const pingMsg: ConnTestMessage = { role: 'user', content: 'ping' };
    const body: ConnTestRequestBody = { model: modelId, messages: [pingMsg], max_tokens: 1, stream: false };
    const req = http.createHttp();
    req.request(endpoint, {
      method: http.RequestMethod.POST,
      header: {
        'Authorization': `Bearer ${key}`,
        'Content-Type': 'application/json'
      },
      extraData: JSON.stringify(body),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 15000
    }).then((resp: http.HttpResponse) => {
      req.destroy();
      const code = resp.responseCode;
      if (code >= 200 && code < 300) {
        this.testOk = true;
        this.testResult = `✓ 连接成功（耗时 ${Date.now() - start} ms）`;
      } else {
        this.testOk = false;
        this.testResult = this.connErrorText(code, '');
      }
    }).catch((err: BusinessError) => {
      req.destroy();
      this.testOk = false;
      this.testResult = this.connErrorText(0, `${err.code} ${err.message}`);
    }).finally(() => {
      this.testing = false;
    });
  }

  // ★ 0.238.0：测试连接错误中文化映射（禁止展示原始英文报错）
  connErrorText(code: number, detail: string): string {
    if (code === 401 || code === 403) {
      return 'API Key 无效或无权限';
    }
    if (code === 404) {
      return '模型 ID 或接口地址不存在';
    }
    if (code === 429) {
      return '请求过于频繁或额度不足';
    }
    if (code >= 500 && code < 600) {
      return '服务商服务异常，稍后再试';
    }
    if (code === 0) {
      // 网络层异常（BusinessError）——超时单列，其余附简短原因（40 字内）
      if (detail.includes('timeout') || detail.includes('2300028')) {
        return '连接超时，请检查网络或接口地址';
      }
      const brief = detail.trim().length > 0 ? detail.trim().substring(0, 40) : '';
      return brief.length > 0 ? `连接失败（${brief}）` : '连接失败，请检查网络与配置';
    }
    return `连接失败（HTTP ${code}）`;
  }

  // ★ 0.190.0：切换提供商——会话级缓存当前 Key/URL（切换不丢输入，仅「保存」才落盘）
  onProviderTap(target: string): void {
    if (target === this.editProvider) {
      return;
    }
    this.providerKeyCache.set(this.editProvider, this.editKey);
    if (this.presetIndex() < 0) {
      this.providerEndpointCache.set(this.editProvider, this.editEndpoint);
    }
    this.editProvider = target;
    this.isModelDropdownOpen = false;
    this.editKey = this.providerKeyCache.get(target) ?? '';
    let targetIdx = -1;
    for (let i = 0; i < PROVIDER_PRESETS.length; i++) {
      if (PROVIDER_PRESETS[i].id === target) {
        targetIdx = i;
        break;
      }
    }
    if (targetIdx >= 0) {
      this.curPresetIdx = targetIdx; // ★ 0.190.1：状态驱动表单刷新（@Builder 按值传参不刷新 bug 根治）
      this.selectedModelIndex = 0;
      this.editCustomModel = '';
      this.editEndpoint = PROVIDER_PRESETS[targetIdx].endpoint;
    } else {
      this.editEndpoint = this.providerEndpointCache.get(target) ?? '';
    }
    // ★ 0.238.1：别名跟随模型——切换后自动带出新表单当前模型的别名（一一对应，输入时已实时记录；
    //   未设过=空串清空，用户原话「之前没设置过就变空」）
    this.editAlias = this.aliasStore.aliasFor(this.currentModelValue());
  }

  // ★ 0.190.0：跳浏览器打开「获取 API Key」官网（openLink API12+；失败 toast 不崩溃）
  openApiKeyUrl(url: string): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined || context === null) {
      this.showToastSafe('打开链接失败');
      return;
    }
    try {
      context.openLink(url).catch(() => {
        this.showToastSafe('打开链接失败，请检查网络');
      });
    } catch (_e) {
      this.showToastSafe('打开链接失败');
    }
  }

  // ★ 0.190.0：Tab1 内容——模型提供商（2×2 卡片）+ 预设/自定义表单
  @Builder
  apiTabContent() {
    Column() {
      // 模型提供商（2×2 卡片，选中=主紫底）
      Column() {
        Text('模型提供商')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })
        Row({ space: 8 }) {
          this.providerCard(0)
          this.providerCard(1)
        }
        .width('100%')
        Row({ space: 8 }) {
          this.providerCard(2)
          this.providerCardCustom()
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 16 })

      // 表单：预设提供商（下标>=0）/ 自定义配置
      if (this.presetIndex() >= 0) {
        this.presetFormContent() // ★ 0.190.1：无参化——内部读 curPresetIdx 状态驱动刷新（按值传参不刷新 bug 根治）
      } else {
        this.customFormContent()
      }

      // ★ 0.232.0：语音朗读（TTS）配置区（API 填写区最下方——用户指定位置）
      this.ttsSectionContent()
    }
    .width('100%')
  }

  // ★ 0.232.0：语音朗读（TTS）配置区——火山引擎（端点内置）/ 自定义双选择；
  //   模型/Key/音色用户自填；未配置或失败自动用本机语音（常驻小字说明）
  //   ★ 0.232.2 去卡片化（用户实锤「上面宽度和下面宽度没对齐」）：与上方 LLM 表单同构裸 100% 字段，
  //   Divider 分隔——上下输入框宽度天然逐像素对齐，杜绝卡片 padding 内缩 28vp 的错位
  @Builder
  ttsSectionContent() {
    Column() {
      Divider()
        .strokeWidth(0.5)
        .color(STROKE_CARD)
        .margin({ top: 20, bottom: 14 })

      // ★ 0.232.2：标题行整行可点折叠（默认收起——低频功能不占屏，用户拍板）
      // ★ 0.237.0 军令：折叠三角字符 ▸/▾ → FoldChevron SVG（全项目唯一折叠指示器，废弃 0.233.0 的 16/22 字符档）
      Row() {
        FoldChevron({ expanded: !this.ttsCollapsed })
        Text('语音朗读（TTS）')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
        Blank()
          .layoutWeight(1)
        Text(this.ttsCloudOn ? this.ttsProviderLabel() : '本机语音')
          .fontSize(11)
          .fontColor(this.ttsCloudOn ? BRAND_SECONDARY : TEXT_TERTIARY)
      }
      .width('100%')
      .margin({ bottom: 8 })
      .onClick(() => {
        this.ttsCollapsed = !this.ttsCollapsed;
      })

      if (this.ttsCollapsed) {
        // ★ 0.232.2：收起态一行提示（用户口述文案）——不填 = 系统内置本机语音
        Text('需要 TTS 语音朗读时，展开填写下方 API；不填则使用系统内置的本机语音。')
          .fontSize(11)
          .lineHeight(18)
          .fontColor(TEXT_TERTIARY)
      }

      // ★ 0.232.2：以下配置表单仅在展开态渲染（默认收起）
      if (!this.ttsCollapsed) {
      // ★ 0.236.0：提供商三段：火山引擎 / 通义千问 / 自定义（三引擎物理互斥——切档走会话级缓存）
      Row({ space: 8 }) {
        Text('火山引擎')
          .fontSize(13)
          .fontColor(this.editTtsProvider === 'volcano' ? Color.White : TEXT_SECONDARY)
          .layoutWeight(1)
          .height(40)
          .textAlign(TextAlign.Center)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(this.editTtsProvider === 'volcano' ? BRAND_PRIMARY : SURFACE_SOFT)
          .onClick(() => {
            this.onTtsProviderTap('volcano');
          })
        Text('通义千问')
          .fontSize(13)
          .fontColor(this.editTtsProvider === TTS_PROVIDER_QWEN ? Color.White : TEXT_SECONDARY)
          .layoutWeight(1)
          .height(40)
          .textAlign(TextAlign.Center)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(this.editTtsProvider === TTS_PROVIDER_QWEN ? BRAND_PRIMARY : SURFACE_SOFT)
          .onClick(() => {
            this.onTtsProviderTap(TTS_PROVIDER_QWEN);
          })
        Text('自定义')
          .fontSize(13)
          .fontColor(this.editTtsProvider === 'custom' ? Color.White : TEXT_SECONDARY)
          .layoutWeight(1)
          .height(40)
          .textAlign(TextAlign.Center)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(this.editTtsProvider === 'custom' ? BRAND_PRIMARY : SURFACE_SOFT)
          .onClick(() => {
            this.onTtsProviderTap('custom');
          })
      }
      .width('100%')
      .margin({ bottom: 12 })

      // 自定义端点（仅自定义提供商显示；火山/千问端点内置）
      if (this.editTtsProvider === 'custom') {
        Column() {
          Text('接口地址')
            .fontSize(14)
            .fontColor(TEXT_SECONDARY)
            .margin({ bottom: 6 })
          TextInput({ text: $$this.editTtsEndpoint, placeholder: '如 https://openspeech.bytedance.com/api/v3/tts/unidirectional' })
            .width('100%')
            .height(48)
            .fontSize(14)
            .fontColor(TEXT_PRIMARY)
            .placeholderColor(TEXT_TERTIARY)
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(SURFACE_SOFT)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: 12 })

        // ★ 0.236.1：自定义档模型资源 ID（空手填 TextInput——不带火山预设下拉，用户拍板「变空」；
        //   openspeech 协议资源 ID 必填，试听/朗读生效都需要它；★ 0.237.2 label 改「模型 ID」统一命名）
        Column() {
          Text('模型 ID')
            .fontSize(14)
            .fontColor(TEXT_SECONDARY)
            .margin({ bottom: 6 })
          TextInput({ text: $$this.editTtsModel, placeholder: '如 seed-tts-2.0' })
            .width('100%')
            .height(48)
            .fontSize(14)
            .fontColor(TEXT_PRIMARY)
            .placeholderColor(TEXT_TERTIARY)
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(SURFACE_SOFT)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: 12 })
      }

      // 音频模型下拉（★ 0.232.1 用户拍板：两预设——声音复刻 2.0 默认 / 豆包语音合成 2.0 + 「自定义模型」（0.237.2 改名）；
      //   复刻可填 S_ 音色，豆包合成音色置灰——两种音色体系的入口分岔）
      // ★ 0.236.0：火山档模型下拉（★ 0.236.1：自定义档删模型字段——用户拍板「音频模型也是不应该
      //   啊」，火山预设（声音复刻/豆包2.0）与自定义端点无关；千问档模型走 TextInput）
      if (this.editTtsProvider === 'volcano') {
      Column() {
        Text('音频模型')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })

        Row() {
          Text(this.editTtsModelSel < TTS_MODEL_PRESETS.length
            ? TTS_MODEL_PRESETS[this.editTtsModelSel].name
            : '自定义模型')
            .fontSize(14)
            .fontColor(TEXT_PRIMARY)
            .layoutWeight(1)
          Text(this.isTtsModelDropdownOpen ? '▲' : '▼')
            .fontSize(16)
            .fontColor(TEXT_TERTIARY)
        }
        .width('100%')
        .height(48)
        .borderRadius(RADIUS_CONTROL)
        .backgroundColor(SURFACE_SOFT)
        .padding({ left: 12, right: 12 })
        .onClick(() => {
          this.isTtsModelDropdownOpen = !this.isTtsModelDropdownOpen;
        })

        if (this.isTtsModelDropdownOpen) {
          Column() {
            ForEach(TTS_MODEL_PRESETS, (m: TtsModelPreset, idx: number) => {
              Column() {
                Text(m.name)
                  .fontSize(14)
                  .fontColor(TEXT_PRIMARY)
                Text(m.desc)
                  .fontSize(12)
                  .fontColor(idx === 1 ? BRAND_SECONDARY : TEXT_TERTIARY)
                  .margin({ top: 2 })
              }
              .width('100%')
              .padding(12)
              .backgroundColor(idx === this.editTtsModelSel ? SURFACE_HOVER : SURFACE_NODE)
              .onClick(() => {
                this.editTtsModelSel = idx;
                this.isTtsModelDropdownOpen = false;
                // ★ 0.237.2：选「声音复刻 2.0」即回填默认 Key/音色（空值补位——用户拍板）
                if (idx === 0) {
                  this.refillVolcanoDefaults();
                }
              })
            }, (m: TtsModelPreset) => m.id)

            Column() {
              Text('自定义模型')
                .fontSize(14)
                .fontColor(TEXT_PRIMARY)
              Text('填入列表外的模型资源 ID')
                .fontSize(12)
                .fontColor(TEXT_TERTIARY)
                .margin({ top: 2 })
            }
            .width('100%')
            .padding(12)
            .backgroundColor(this.editTtsModelSel >= TTS_MODEL_PRESETS.length
              ? SURFACE_HOVER : SURFACE_NODE)
            .onClick(() => {
              this.editTtsModelSel = TTS_MODEL_PRESETS.length;
              this.isTtsModelDropdownOpen = false;
            })
          }
          .width('100%')
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_NODE)
          .border({ width: 1, color: STROKE_CARD })
          .margin({ top: 4 })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 12 })
      } // ★ 0.236.0：非千问档模型下拉块结束（★ 0.236.1：仅火山档）

      // 「自定义模型」模型 ID（火山档选中「自定义模型」时显示；★ 0.236.1：自定义/千问档不渲染）
      // ★ 0.237.2：label 模型资源 ID→模型 ID（与音色 ID/音频 API Key 三字段统一命名——用户拍板）
      if (this.editTtsProvider === 'volcano' && this.editTtsModelSel >= TTS_MODEL_PRESETS.length) {
        Column() {
          Text('模型 ID')
            .fontSize(14)
            .fontColor(TEXT_SECONDARY)
            .margin({ bottom: 6 })
          TextInput({ text: $$this.editTtsModel, placeholder: '如 seed-tts-2.0' })
            .width('100%')
            .height(48)
            .fontSize(14)
            .fontColor(TEXT_PRIMARY)
            .placeholderColor(TEXT_TERTIARY)
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(SURFACE_SOFT)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: 12 })
      }

      // 音频 API Key（三档各自语义：火山=豆包语音 Key / 千问=sk-ws- Key / 自定义；均与对话 Key 相互独立）
      Column() {
        Text('音频 API Key')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })
        TextInput({
          text: $$this.editTtsKey,
          placeholder: this.ttsKeyPlaceholder()
        })
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .placeholderColor(TEXT_TERTIARY)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 12 })

      // ★ 0.236.0：千问档模型 TextInput（默认 cosyvoice-v3.5-plus；空值引擎兜底该常量——
      //   平台模型迭代快不做下拉，手填最灵活）
      if (this.editTtsProvider === TTS_PROVIDER_QWEN) {
        Column() {
          Text('合成模型')
            .fontSize(14)
            .fontColor(TEXT_SECONDARY)
            .margin({ bottom: 6 })
          TextInput({ text: $$this.editTtsQwenModel, placeholder: TTS_QWEN_DEFAULT_MODEL })
            .width('100%')
            .height(48)
            .fontSize(14)
            .fontColor(TEXT_PRIMARY)
            .placeholderColor(TEXT_TERTIARY)
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(SURFACE_SOFT)
          Text('CosyVoice 复刻音色专用模型；留空默认 cosyvoice-v3.5-plus。')
            .fontSize(11)
            .lineHeight(18)
            .fontColor(TEXT_TERTIARY)
            .margin({ top: 4 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: 12 })
      }

      // ★ 0.236.0：千问档复刻音色（拉取式下拉——cosyvoice 无系统音色，voice 必须是复刻 voice_id；
      //   下拉=复刻音色列表（默认第一个）+ 手动输入… + 去千问平台复刻外链）
      if (this.editTtsProvider === TTS_PROVIDER_QWEN) {
        Column() {
          Row() {
            Text('复刻音色')
              .fontSize(14)
              .fontColor(TEXT_SECONDARY)
              .layoutWeight(1)
            Text('拉取')
              .fontSize(12)
              .fontColor(BRAND_SECONDARY)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .onClick(() => {
                this.fetchTtsVoices();
              })
          }
          .width('100%')
          .margin({ bottom: 6 })

          Row() {
            Text(this.editTtsVoice.trim().length > 0 ? this.editTtsVoice.trim() : '点击拉取选择复刻音色')
              .fontSize(12)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(this.editTtsVoice.trim().length > 0 ? TEXT_PRIMARY : TEXT_TERTIARY)
              .layoutWeight(1)
            Text(this.ttsVoiceLoading ? '拉取中…' : (this.isTtsVoiceDropdownOpen ? '▲' : '▼'))
              .fontSize(14)
              .fontColor(TEXT_TERTIARY)
          }
          .width('100%')
          .height(48)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.onTtsVoiceDropdownTap();
          })

          if (this.isTtsVoiceDropdownOpen) {
            Column() {
              ForEach(this.ttsVoiceList, (v: QwenVoiceItem) => {
                Column() {
                  Text(v.voiceId)
                    .fontSize(12)
                    .fontColor(TEXT_PRIMARY)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(v.targetModel)
                    .fontSize(11)
                    .fontColor(TEXT_TERTIARY)
                    .margin({ top: 2 })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding(10)
                .backgroundColor(this.editTtsVoice === v.voiceId ? SURFACE_HOVER : SURFACE_NODE)
                .onClick(() => {
                  this.editTtsVoice = v.voiceId;
                  this.isTtsVoiceDropdownOpen = false;
                })
              }, (v: QwenVoiceItem) => v.voiceId)

              // ★ 0.236.1：空态行（拉取完仍无音色——Key 工作空间无复刻音色）
              if (this.ttsVoiceList.length === 0) {
                Text(this.ttsVoiceLoading ? '正在拉取…' : '暂无复刻音色：请核对 API Key，或先在平台完成音色复刻')
                  .fontSize(12)
                  .fontColor(TEXT_TERTIARY)
                  .width('100%')
                  .padding(10)
              }
            }
            .width('100%')
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(SURFACE_NODE)
            .border({ width: 1, color: STROKE_CARD })
            .margin({ top: 4 })
          }

          Text('复刻音色须与 API Key 属同一工作空间；多个音色全部列出逐行选择。')
            .fontSize(11)
            .lineHeight(18)
            .fontColor(TEXT_TERTIARY)
            .margin({ top: 4 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: 12 })
      }

      // 音色 ID（★ 0.232.1 联动：声音复刻/自定义模型可填 S_ 音色；豆包语音合成2.0 置灰=官方音色体系）
      // ★ 0.232.2：自定义提供商整块隐藏（火山音色体系不适用——用户拍板「自定义了音色 ID 就取消掉」）
      // ★ 0.237.2：音频模型选「自定义模型」时恢复显示（推翻 0.233.0 隐藏——用户拍板自定义模型下
      //   三字段齐全：模型 ID / 音频 API Key / 音色 ID，各带「如 …」灰提示；仅豆包合成置灰）
      if (this.editTtsProvider === 'volcano') {
      Column() {
        Text('音色 ID')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })
        TextInput({
          text: this.ttsVoiceEditable() ? this.editTtsVoice : TTS_OFFICIAL_VOICE,
          placeholder: '如 S_bv8H32Sg2'
        })
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(this.ttsVoiceEditable() ? TEXT_PRIMARY : TEXT_TERTIARY)
          .placeholderColor(TEXT_TERTIARY)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
          .enabled(this.ttsVoiceEditable())
        Text(this.editTtsModelSel === 1 ? '豆包语音合成 2.0 使用官方音色（音色 ID 固定，不可自定义）。'
          : (this.editTtsModelSel >= TTS_MODEL_PRESETS.length
            ? '自定义模型的音色 ID；留空自动使用官方音色。'
            : '声音复刻 2.0 的合成音色 ID（火山控制台·声音复刻获取）。'))
          .fontSize(11)
          .lineHeight(18)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 8 })
      }

      // ★ 0.236.0：千问档专属——情感下拉（引擎内映射百炼 instruction 自然语言指令）
      if (this.editTtsProvider === TTS_PROVIDER_QWEN) {
        Column() {
          Text('情感')
            .fontSize(14)
            .fontColor(TEXT_SECONDARY)
            .margin({ bottom: 6 })
          Row() {
            Text(this.editTtsEmotion)
              .fontSize(14)
              .fontColor(TEXT_PRIMARY)
              .layoutWeight(1)
            Text(this.isTtsEmotionDropdownOpen ? '▲' : '▼')
              .fontSize(16)
              .fontColor(TEXT_TERTIARY)
          }
          .width('100%')
          .height(48)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.isTtsEmotionDropdownOpen = !this.isTtsEmotionDropdownOpen;
          })

          if (this.isTtsEmotionDropdownOpen) {
            Column() {
              ForEach(TTS_EMOTION_PRESETS, (e: string, idx: number) => {
                Text(e)
                  .fontSize(14)
                  .fontColor(idx === 0 ? TEXT_TERTIARY : TEXT_PRIMARY)
                  .width('100%')
                  .padding(12)
                  .backgroundColor(e === this.editTtsEmotion ? SURFACE_HOVER : SURFACE_NODE)
                  .onClick(() => {
                    this.editTtsEmotion = e;
                    this.isTtsEmotionDropdownOpen = false;
                  })
              }, (e: string) => e)
            }
            .width('100%')
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(SURFACE_NODE)
            .border({ width: 1, color: STROKE_CARD })
            .margin({ top: 4 })
          }
          Text('「默认」=不带情感指令；其余档位转自然语言指令（复刻音色支持指令控情）。')
            .fontSize(11)
            .lineHeight(18)
            .fontColor(TEXT_TERTIARY)
            .margin({ top: 4 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: 12 })

        // 语速滑条（0.5~2.0 步进 0.05；旁显 ×倍速）
        Column() {
          Row() {
            Text('语速')
              .fontSize(14)
              .fontColor(TEXT_SECONDARY)
              .layoutWeight(1)
            Text(`×${this.editTtsSpeed.toFixed(2)}`)
              .fontSize(13)
              .fontColor(BRAND_SECONDARY)
          }
          .width('100%')
          .margin({ bottom: 2 })
          Slider({ value: this.editTtsSpeed, min: 0.5, max: 2.0, step: 0.05 })
            .width('100%')
            .blockColor(BRAND_PRIMARY)
            .trackColor(SURFACE_SOFT)
            .selectedColor(BRAND_PRIMARY)
            .onChange((value: number) => {
              this.editTtsSpeed = Math.round(value * 100) / 100;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: 10 })

        // 音量滑条（0~100 步进 5）
        Column() {
          Row() {
            Text('音量')
              .fontSize(14)
              .fontColor(TEXT_SECONDARY)
              .layoutWeight(1)
            Text(`${this.editTtsVolume}`)
              .fontSize(13)
              .fontColor(BRAND_SECONDARY)
          }
          .width('100%')
          .margin({ bottom: 2 })
          Slider({ value: this.editTtsVolume, min: 0, max: 100, step: 5 })
            .width('100%')
            .blockColor(BRAND_PRIMARY)
            .trackColor(SURFACE_SOFT)
            .selectedColor(BRAND_PRIMARY)
            .onChange((value: number) => {
              this.editTtsVolume = Math.round(value / 5) * 5;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: 12 })

        Text('千问档走百炼 CosyVoice 复刻音色（仅支持复刻音色，无官方音色）；情感/语速/音量即时生效于下次朗读。未配置或失败自动使用本机语音。')
          .fontSize(11)
          .lineHeight(18)
          .fontColor(TEXT_TERTIARY)
      } else {
        Text('填写 Key 和模型后朗读优先走云端（自动跳过 Markdown 符号，代码块不朗读）；未配置或请求失败自动使用本机语音。合成音色需在火山控制台开通对应资源，未开通时自动回退官方音色。')
          .fontSize(11)
          .lineHeight(18)
          .fontColor(TEXT_TERTIARY)
      }

      // ★ 0.236.1：试听按钮（三档公共——当前表单值走对应引擎完整链路，出声=配置即验；
      //   icon=项目喇叭 svg 三件套同款（消息喇叭/单词发音同源）；试听中变「停止」）
      Button() {
        Row({ space: 6 }) {
          Image(this.ttsPreviewing ? $r('app.media.speaker_playing') : $r('app.media.speaker'))
            .width(14)
            .height(14)
            .objectFit(ImageFit.Contain)
          Text(this.ttsPreviewing ? '停止试听' : '试听')
            .fontSize(14)
            .fontColor(Color.White)
        }
      }
      .type(ButtonType.Normal)
      .width('100%')
      .height(40)
      .borderRadius(RADIUS_CONTROL)
      .backgroundColor(this.ttsPreviewing ? SURFACE_HOVER : BRAND_PRIMARY)
      .onClick(() => {
        this.onTtsPreviewTap();
      })
      .margin({ top: 12 })
      } // ★ 0.232.2：展开态表单块结束（与上方 if (!this.ttsCollapsed) 配对）
    }
    .width('100%')
    .padding(14)
    .borderRadius(RADIUS_CONTROL)
    .backgroundColor(SURFACE_NODE)
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 8 })
  }

  // ★ 0.190.0：提供商卡片（预设，index 对应 PROVIDER_PRESETS）
  @Builder
  providerCard(index: number) {
    Column() {
      Text(PROVIDER_PRESETS[index].name)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_PRIMARY)
      Text(PROVIDER_PRESETS[index].desc)
        .fontSize(11)
        .fontColor(this.editProvider === PROVIDER_PRESETS[index].id ? 'rgba(255,255,255,0.8)' : TEXT_TERTIARY)
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .borderRadius(RADIUS_CONTROL)
    .backgroundColor(this.editProvider === PROVIDER_PRESETS[index].id ? BRAND_PRIMARY : SURFACE_SOFT)
    .onClick(() => {
      this.onProviderTap(PROVIDER_PRESETS[index].id);
    })
  }

  // ★ 0.190.0：提供商卡片（自定义配置）
  @Builder
  providerCardCustom() {
    Column() {
      Text('自定义配置')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_PRIMARY)
      Text('任意 OpenAI 兼容接口')
        .fontSize(11)
        .fontColor(this.editProvider === PROVIDER_CUSTOM ? 'rgba(255,255,255,0.8)' : TEXT_TERTIARY)
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .borderRadius(RADIUS_CONTROL)
    .backgroundColor(this.editProvider === PROVIDER_CUSTOM ? BRAND_PRIMARY : SURFACE_SOFT)
    .onClick(() => {
      this.onProviderTap(PROVIDER_CUSTOM);
    })
  }

  // ★ 0.190.0/0.190.1：预设提供商表单——模型下拉（预置+「自定义…」）+ API Key（含各自官网获取链接）
  //   ★ 0.190.1：无参化——@Builder 按值传参在预设间切换时不刷新（真机实测模型清单/获取Key链接
  //   显示旧提供商），改读 @Local curPresetIdx 状态驱动；「接口地址已内置」小字删除（用户指示：
  //   选了预设端点就默认了，不需要提示）；模型小字只标多模态/纯文本，价格不标（用户指示）
  @Builder
  presetFormContent() {
    Column() {
      // 模型名称下拉
      Column() {
        Text('模型名称')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })

        // 下拉触发器：当前选中模型名称 + 箭头
        Row() {
          Text(this.selectedModelIndex < PROVIDER_PRESETS[this.curPresetIdx].models.length
            ? PROVIDER_PRESETS[this.curPresetIdx].models[this.selectedModelIndex].name
            : '自定义…')
            .fontSize(14)
            .fontColor(TEXT_PRIMARY)
            .layoutWeight(1)
          Text(this.isModelDropdownOpen ? '▲' : '▼')
            .fontSize(16)
            .fontColor(TEXT_TERTIARY)
        }
        .width('100%')
        .height(48)
        .borderRadius(RADIUS_CONTROL)
        .backgroundColor(SURFACE_SOFT)
        .padding({ left: 12, right: 12 })
        .onClick(() => {
          this.isModelDropdownOpen = !this.isModelDropdownOpen;
        })

        // 下拉面板：预置模型 + 末位「自定义…」
        if (this.isModelDropdownOpen) {
          Column() {
            ForEach(PROVIDER_PRESETS[this.curPresetIdx].models, (m: PresetModel, idx: number) => {
              Column() {
                Text(m.name)
                  .fontSize(14)
                  .fontColor(TEXT_PRIMARY)
                Text(m.desc)
                  .fontSize(12)
                  .fontColor(m.desc.startsWith('多模态') ? BRAND_SECONDARY : TEXT_TERTIARY) // ★ 0.190.1：多模态高亮辅助紫（推荐语义）
                  .margin({ top: 2 })
              }
              .width('100%')
              .padding(12)
              .backgroundColor(idx === this.selectedModelIndex ? SURFACE_HOVER : SURFACE_NODE)
              .onClick(() => {
                this.selectedModelIndex = idx;
                this.isModelDropdownOpen = false;
                // ★ 0.238.1：别名跟随模型——切下拉自动带出该模型的别名（输入时已实时记录）
                this.editAlias = this.aliasStore.aliasFor(this.currentModelValue());
              })
            }, (m: PresetModel) => m.id)

            // 「自定义…」选项（列表外模型手填 ID）
            Column() {
              Text('自定义…')
                .fontSize(14)
                .fontColor(TEXT_PRIMARY)
              Text('填入列表外的模型 ID')
                .fontSize(12)
                .fontColor(TEXT_TERTIARY)
                .margin({ top: 2 })
            }
            .width('100%')
            .padding(12)
            .backgroundColor(this.selectedModelIndex >= PROVIDER_PRESETS[this.curPresetIdx].models.length
              ? SURFACE_HOVER : SURFACE_NODE)
            .onClick(() => {
              this.selectedModelIndex = PROVIDER_PRESETS[this.curPresetIdx].models.length;
              this.isModelDropdownOpen = false;
              // ★ 0.238.1：别名跟随模型——切「自定义…」模型 ID 待填，别名先清空（填入 ID 后带出）
              this.editAlias = this.aliasStore.aliasFor(this.currentModelValue());
            })
          }
          .width('100%')
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_NODE)
          .border({ width: 1, color: STROKE_CARD })
          .margin({ top: 4 })
        }

        // ★ 0.191.0：多模态模型高亮（用户指示：强烈推荐+高亮——后续图表上传等 AI 辅助功能依赖多模态）
        Text() {
          Span('强烈推荐使用')
            .fontColor(TEXT_TERTIARY)
          Span('多模态模型')
            .fontColor(BRAND_SECONDARY)
            .fontWeight(FontWeight.Medium)
          Span('（可发送图片，AI 能识别图片内容）；列表外模型可选「自定义…」。')
            .fontColor(TEXT_TERTIARY)
        }
          .fontSize(11)
          .lineHeight(18)
          .margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 16 })

      // 自定义模型 ID（选中「自定义…」时显示）
      if (this.selectedModelIndex >= PROVIDER_PRESETS[this.curPresetIdx].models.length) {
        Column() {
          Text('模型 ID')
            .fontSize(14)
            .fontColor(TEXT_SECONDARY)
            .margin({ bottom: 6 })
          TextInput({ text: $$this.editCustomModel, placeholder: '填入模型 ID' })
            .width('100%')
            .height(48)
            .fontSize(14)
            .fontColor(TEXT_PRIMARY)
            .placeholderColor(TEXT_TERTIARY)
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(SURFACE_SOFT)
            .onChange((value: string) => {
              // ★ 0.238.1：手填模型 ID 变化→别名框带出该模型的别名（一一对应）
              this.editAlias = this.aliasStore.aliasFor(value.trim());
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: 16 })
      }

      // API Key + 「获取 API Key」跳**各自**官网链接（★ 0.190.1 bug 修复：此前因 @Builder
      //   按值传参不刷新，切换提供商后链接仍是旧提供商的官网）
      Column() {
        Row() {
          Text('API Key')
            .fontSize(14)
            .fontColor(TEXT_SECONDARY)
          Blank()
            .layoutWeight(1)
          Text('获取 API Key ↗')
            .fontSize(12)
            .fontColor(BRAND_PRIMARY)
            .onClick(() => {
              this.openApiKeyUrl(PROVIDER_PRESETS[this.curPresetIdx].keyUrl);
            })
        }
        .width('100%')
        .margin({ bottom: 6 })

        TextInput({ text: $$this.editKey, placeholder: PROVIDER_PRESETS[this.curPresetIdx].keyPlaceholder })
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .placeholderColor(TEXT_TERTIARY)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)

      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // ★ 0.238.0：模型别名（应用内展示名——4 提供商共用一份全局配置；留空显示官方模型名）
      //   ★ 0.238.1：按模型 ID 一一对应——输入即实时记录进 aliasStore（切换提供商/模型自动带出）
      Column() {
        Text('模型别名')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })
        TextInput({ text: $$this.editAlias, placeholder: '给模型起个展示名（可留空）' })
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .placeholderColor(TEXT_TERTIARY)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
          .onChange((value: string) => {
            // ★ 0.238.1：实时记录到当前表单模型名下（未保存也记——切走再切回自动带出）
            this.aliasStore.setAlias(this.currentModelValue(), value);
          })
        Text('给模型起个应用内展示名称，对话记录里会显示它（类似司忆区的展示名）；留空则显示官方模型名。')
          .fontSize(11)
          .lineHeight(18)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 16 })

      // ★ 0.238.0：测试连接（表单当前值发最小真实请求——未保存也可测；4 提供商共用块）
      this.testConnectionBlock()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ★ 0.190.0：自定义配置表单——模型 URL（必填）+ 模型 ID + API Key
  //   （上下文窗口 Tokens 按用户指示不要——那是开发代码用配置；温度等参数走 AI 偏好/默认值）
  @Builder
  customFormContent() {
    Column() {
      // 模型 URL（自定义服务必须提供，否则无法调用）
      Column() {
        Text('模型 URL')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })
        TextInput({ text: $$this.editEndpoint, placeholder: 'https://api.example.com/v1/chat/completions' })
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .placeholderColor(TEXT_TERTIARY)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
        Text('须为 OpenAI 兼容的 chat/completions 完整地址。')
          .fontSize(11)
          .lineHeight(18)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 16 })

      // 模型 ID
      Column() {
        Text('模型 ID')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })
        TextInput({ text: $$this.editCustomModel, placeholder: '如 qwen-max / gpt-4o' })
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .placeholderColor(TEXT_TERTIARY)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
          .onChange((value: string) => {
            // ★ 0.238.1：手填模型 ID 变化→别名框带出该模型的别名（一一对应）
            this.editAlias = this.aliasStore.aliasFor(value.trim());
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 16 })

      // API Key（部分本地/免费网关无需 Key，可留空）
      Column() {
        Text('API Key')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })
        TextInput({ text: $$this.editKey, placeholder: '填入该服务的 API Key' })
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .placeholderColor(TEXT_TERTIARY)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
        Text('部分本地/免费网关无需 Key，可留空。')
          .fontSize(11)
          .lineHeight(18)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })

      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // ★ 0.238.0：模型别名（自定义配置=第 4 提供商同款；与预设共用全局单值 editAlias）
      //   ★ 0.238.1：按模型 ID 一一对应——输入即实时记录，切提供商/模型自动带出
      Column() {
        Text('模型别名')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })
        TextInput({ text: $$this.editAlias, placeholder: '给模型起个展示名（可留空）' })
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .placeholderColor(TEXT_TERTIARY)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
          .onChange((value: string) => {
            // ★ 0.238.1：实时记录到当前表单模型名下（未保存也记——切走再切回自动带出）
            this.aliasStore.setAlias(this.currentModelValue(), value);
          })
        Text('给模型起个应用内展示名称，对话记录里会显示它（类似司忆区的展示名）；留空则显示官方模型名。')
          .fontSize(11)
          .lineHeight(18)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 16 })

      // ★ 0.238.0：测试连接（自定义配置同款；Key 允许为空的本地网关守卫文案见函数内）
      this.testConnectionBlock()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ★ 0.238.0：测试连接按钮+结果行（无参 @Builder 直读状态——预设 3 家与自定义两处共用一份逻辑；
  //   成功绿/失败红；进行中按钮禁用防连点；结果行未测时不渲染）
  @Builder
  testConnectionBlock() {
    Column() {
      Button(this.testing ? '测试中…' : '测试连接')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .height(40)
        .padding({ left: 20, right: 20 })
        .backgroundColor(this.testing ? SURFACE_HOVER : BRAND_PRIMARY)
        .fontColor(TEXT_PRIMARY)
        .borderRadius(RADIUS_CONTROL)
        .enabled(!this.testing)
        .onClick(() => {
          this.testConnection();
        })
      if (this.testResult.length > 0) {
        Text(this.testResult)
          .fontSize(12)
          .lineHeight(18)
          .fontColor(this.testOk ? SUCCESS : DANGER)
          .margin({ top: 6 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 16 })
  }

  // ★ 0.150：Tab2 内容——AI 对话偏好表单（自定义称呼 + 自动鼓励开关）
  @Builder
  prefTabContent() {
    Column() {
      // 自定义称呼输入
      Column() {
        Text('自定义称呼')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })
        TextInput({ text: $$this.editNickname, placeholder: '如：好奇宝宝（AI 回复会以此称呼你）' }) // ★ 0.175.0：称呼示例「大明」改「好奇宝宝」
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .placeholderColor(TEXT_TERTIARY)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
        Text('💡 填写后 AI 在短/中/长全部回复模式都会以此称呼你；留空则不添加称呼。')
          .fontSize(11)
          .lineHeight(18) // ★ 0.175.0：小字行间距规则（同上）
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .margin({ bottom: 24 })

      // ★ 0.234.0 ②：注意力锚点（钩子模式）——开关 + 密度档 + 提示小字（任务书 §6.3）
      Column() {
        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text('锚点卡片')
              .fontSize(14)
              .fontColor(TEXT_PRIMARY)
            Text('中/长回复中插入考考你、前方高能、换个说法等锚点卡片')
              .fontSize(11)
              .lineHeight(18)
              .fontColor(TEXT_TERTIARY)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.editAnchorMode === 'on' })
            .selectedColor(BRAND_PRIMARY)
            .onChange((on: boolean) => {
              this.editAnchorMode = on ? 'on' : 'off';
            })
        }
        .width('100%')

        // 密度分段控件（★ 0.237.0 两档制——用户拍板去掉「中」：密 400 / 疏 800 字，默认疏；
        //   疏档 AI 全文 2~3 个锚点、密档 3~5 个；SEGMENTED_TRACK 轨道+激活段主紫）
        Row() {
          Text('密')
            .fontSize(13)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 7, bottom: 7 })
            .borderRadius(RADIUS_CONTROL - 2)
            .fontColor(this.editAnchorDensity === 'dense' ? TEXT_PRIMARY : TEXT_SECONDARY)
            .backgroundColor(this.editAnchorDensity === 'dense' ? BRAND_PRIMARY : Color.Transparent)
            .onClick(() => {
              this.editAnchorDensity = 'dense';
            })
          Text('疏')
            .fontSize(13)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 7, bottom: 7 })
            .borderRadius(RADIUS_CONTROL - 2)
            .fontColor(this.editAnchorDensity === 'sparse' ? TEXT_PRIMARY : TEXT_SECONDARY)
            .backgroundColor(this.editAnchorDensity === 'sparse' ? BRAND_PRIMARY : Color.Transparent)
            .onClick(() => {
              this.editAnchorDensity = 'sparse';
            })
        }
        .width('100%')
        .padding(4)
        .margin({ top: 10 })
        .borderRadius(RADIUS_CONTROL)
        .backgroundColor(SEGMENTED_TRACK)

        Text('💡 开启后，中/长回复中会插入考考你、前方高能、换个说法等锚点卡片，读长文时轻轻拉回注意力；密档锚点更频繁、疏档更克制。关闭后 AI 按原文回复。短回复与听播模式不插入。')
          .fontSize(11)
          .lineHeight(18)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 24 })

      // ★ 0.234.0 ③：长文分章折叠（折叠模式）——开关 + 提示小字（与锚点卡片互相独立，可分别开关）
      Column() {
        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text('分章折叠')
              .fontSize(14)
              .fontColor(TEXT_PRIMARY)
            Text('中/长回复生成完毕后自动按章节折叠呈现')
              .fontSize(11)
              .lineHeight(18)
              .fontColor(TEXT_TERTIARY)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.editFoldMode === 'on' })
            .selectedColor(BRAND_PRIMARY)
            .onChange((on: boolean) => {
              this.editFoldMode = on ? 'on' : 'off';
            })
        }
        .width('100%')

        Text('💡 中/长回复生成完毕后自动按章节折叠（默认展开前 1/3，其余收起），点章节行展开继续读；生成过程中仍为流式直显。与锚点卡片互相独立，可分别开关。')
          .fontSize(11)
          .lineHeight(18)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 24 })

      // ★ 0.234.0 ④：自动鼓励（移到第四位，三档控件不动，仅改说明小字——只在学习统计页/复习完成页出现）
      Column() {
        Text('自动鼓励')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 8 })

        // 三档分段控件（SEGMENTED_TRACK 轨道 + 激活段 BRAND_PRIMARY，对齐 UI_GUIDELINES 六-8 分段规格）
        Row() {
          Text('关闭')
            .fontSize(13)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 7, bottom: 7 })
            .borderRadius(RADIUS_CONTROL - 2)
            .fontColor(this.editEncourageMode === 'off' ? TEXT_PRIMARY : TEXT_SECONDARY)
            .backgroundColor(this.editEncourageMode === 'off' ? BRAND_PRIMARY : Color.Transparent)
            .onClick(() => {
              this.editEncourageMode = 'off';
            })
          Text('轻度')
            .fontSize(13)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 7, bottom: 7 })
            .borderRadius(RADIUS_CONTROL - 2)
            .fontColor(this.editEncourageMode === 'light' ? TEXT_PRIMARY : TEXT_SECONDARY)
            .backgroundColor(this.editEncourageMode === 'light' ? BRAND_PRIMARY : Color.Transparent)
            .onClick(() => {
              this.editEncourageMode = 'light';
            })
          Text('重度')
            .fontSize(13)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 7, bottom: 7 })
            .borderRadius(RADIUS_CONTROL - 2)
            .fontColor(this.editEncourageMode === 'heavy' ? TEXT_PRIMARY : TEXT_SECONDARY)
            .backgroundColor(this.editEncourageMode === 'heavy' ? BRAND_PRIMARY : Color.Transparent)
            .onClick(() => {
              this.editEncourageMode = 'heavy';
            })
        }
        .width('100%')
        .padding(4)
        .borderRadius(RADIUS_CONTROL)
        .backgroundColor(SEGMENTED_TRACK)

        Text('💡 轻度：1~2 句温和鼓励；重度：2~4 句热情喝彩；关闭：不生成。仅在学习统计页与复习完成页出现，不插入 AI 回复。') // ★ 0.234.0：改口——鼓励不再进 AI 回复
          .fontSize(11)
          .lineHeight(18) // ★ 0.175.0：小字行间距规则（同上）
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 24 })

      
    }
    .width('100%')
  }

  // ★ 0.195.0：复习显示 Tab（用户拍板：从 AI 偏好挪到顶层——与云同步/关于齐平）。
  //   布局与两库 ⚙ 设置完全同款：0/1/2 快速项 + 自由输入框一行（界面统一）。
  //   ★ 0.197.2：改保存模式（用户反馈：要保存按钮）——快速项/确定写编辑副本，底部「保存」统一落 store
  @Builder
  reviewTabContent() {
    Column() {
      // ── ★ 0.224.0：卡面模式（全局单通道——即时生效，不走下方编辑副本+保存流程；
      //    与复习页 ⚙ 同一真相源互相同步，司忆区两处/桌面卡片全跟随）──
      Text('卡面模式')
        .fontSize(14)
        .fontColor(TEXT_PRIMARY)
        .margin({ bottom: 6 })
      Text('正反两面：先看题面，点击翻面后再评分；全局生效（复习页/司忆区/桌面卡片跟随），与复习页设置同步')
        .fontSize(11)
        .fontColor(TEXT_TERTIARY)
        .margin({ bottom: 10 })
      Row({ space: 6 }) {
        Text('单面')
          .fontSize(12)
          .fontWeight(this.faceMode.mode !== 'double' ? 600 : 400)
          .fontColor(this.faceMode.mode !== 'double' ? Color.White : TEXT_SECONDARY)
          .height(30)
          .padding({ left: 14, right: 14 })
          .borderRadius(8)
          .backgroundColor(this.faceMode.mode !== 'double' ? BRAND_PRIMARY : Color.Transparent)
          .onClick(() => {
            this.applyFaceMode('single');
          })
        Text('正反两面')
          .fontSize(12)
          .fontWeight(this.faceMode.mode === 'double' ? 600 : 400)
          .fontColor(this.faceMode.mode === 'double' ? Color.White : TEXT_SECONDARY)
          .height(30)
          .padding({ left: 14, right: 14 })
          .borderRadius(8)
          .backgroundColor(this.faceMode.mode === 'double' ? BRAND_PRIMARY : Color.Transparent)
          .onClick(() => {
            this.applyFaceMode('double');
          })
      }
      .padding(3)
      .borderRadius(RADIUS_CONTROL)
      .backgroundColor(SURFACE_SOFT)
      .margin({ bottom: 16 })

      // ── 单词库词条数 ──
      Column() {
        Text('单词库词条数')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })
        Row() {
          Button('0')
            .fontSize(14)
            .width(44)
            .height(40)
            .fontColor(this.editReviewLearn === 0 ? TEXT_PRIMARY : TEXT_SECONDARY)
            .backgroundColor(this.editReviewLearn === 0 ? BRAND_PRIMARY : Color.Transparent)
            .borderRadius(RADIUS_CONTROL)
            .onClick(() => {
              this.editReviewLearn = 0;
            })
          Button('1')
            .fontSize(14)
            .width(44)
            .height(40)
            .fontColor(this.editReviewLearn === 1 ? TEXT_PRIMARY : TEXT_SECONDARY)
            .backgroundColor(this.editReviewLearn === 1 ? BRAND_PRIMARY : Color.Transparent)
            .borderRadius(RADIUS_CONTROL)
            .margin({ left: 8 })
            .onClick(() => {
              this.editReviewLearn = 1;
            })
          Button('2')
            .fontSize(14)
            .width(44)
            .height(40)
            .fontColor(this.editReviewLearn === 2 ? TEXT_PRIMARY : TEXT_SECONDARY)
            .backgroundColor(this.editReviewLearn === 2 ? BRAND_PRIMARY : Color.Transparent)
            .borderRadius(RADIUS_CONTROL)
            .margin({ left: 8 })
            .onClick(() => {
              this.editReviewLearn = 2;
            })
          TextInput({ text: this.reviewWordInput, placeholder: '0~20' })
            .fontSize(14)
            .layoutWeight(1)
            .height(40)
            .padding({ left: 12, right: 12 })
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(SURFACE_NODE)
            .type(InputType.Number)
            .margin({ left: 8 })
            .onChange((v: string) => {
              this.reviewWordInput = v;
              this.reviewWordError = '';
            })
          Button('确定')
            .fontSize(14)
            .height(40)
            .fontColor(TEXT_PRIMARY)
            .backgroundColor(BRAND_PRIMARY)
            .borderRadius(RADIUS_CONTROL)
            .margin({ left: 8 })
            .padding({ left: 14, right: 14 })
            .onClick(() => {
              const n = parseInt(this.reviewWordInput, 10);
              if (!Number.isNaN(n) && n >= 0 && n <= 20) {
                this.editReviewLearn = n; // ★ 0.197.2：写编辑副本，保存统一落 store
              } else {
                this.reviewWordError = '请输入 0~20 的整数';
              }
            })
        }
        .width('100%')
        if (this.reviewWordError.length > 0) {
          Text(this.reviewWordError)
            .fontSize(12)
            .fontColor(DANGER)
            .margin({ top: 6 })
        }
        Text('AI 回复底部复习区、提炼等待页每次展示的词条数；0=关闭（对话页只看对话）')
          .fontSize(11)
          .lineHeight(18)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 20 })

      // ── 知识库卡片数 ──
      Column() {
        Text('知识库卡片数')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })
        Row() {
          Button('0')
            .fontSize(14)
            .width(44)
            .height(40)
            .fontColor(this.editReviewKnowledge === 0 ? TEXT_PRIMARY : TEXT_SECONDARY)
            .backgroundColor(this.editReviewKnowledge === 0 ? BRAND_PRIMARY : Color.Transparent)
            .borderRadius(RADIUS_CONTROL)
            .onClick(() => {
              this.editReviewKnowledge = 0;
            })
          Button('1')
            .fontSize(14)
            .width(44)
            .height(40)
            .fontColor(this.editReviewKnowledge === 1 ? TEXT_PRIMARY : TEXT_SECONDARY)
            .backgroundColor(this.editReviewKnowledge === 1 ? BRAND_PRIMARY : Color.Transparent)
            .borderRadius(RADIUS_CONTROL)
            .margin({ left: 8 })
            .onClick(() => {
              this.editReviewKnowledge = 1;
            })
          Button('2')
            .fontSize(14)
            .width(44)
            .height(40)
            .fontColor(this.editReviewKnowledge === 2 ? TEXT_PRIMARY : TEXT_SECONDARY)
            .backgroundColor(this.editReviewKnowledge === 2 ? BRAND_PRIMARY : Color.Transparent)
            .borderRadius(RADIUS_CONTROL)
            .margin({ left: 8 })
            .onClick(() => {
              this.editReviewKnowledge = 2;
            })
          TextInput({ text: this.reviewCardInput, placeholder: '0~20' })
            .fontSize(14)
            .layoutWeight(1)
            .height(40)
            .padding({ left: 12, right: 12 })
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(SURFACE_NODE)
            .type(InputType.Number)
            .margin({ left: 8 })
            .onChange((v: string) => {
              this.reviewCardInput = v;
              this.reviewCardError = '';
            })
          Button('确定')
            .fontSize(14)
            .height(40)
            .fontColor(TEXT_PRIMARY)
            .backgroundColor(BRAND_PRIMARY)
            .borderRadius(RADIUS_CONTROL)
            .margin({ left: 8 })
            .padding({ left: 14, right: 14 })
            .onClick(() => {
              const n = parseInt(this.reviewCardInput, 10);
              if (!Number.isNaN(n) && n >= 0 && n <= 20) {
                this.editReviewKnowledge = n; // ★ 0.197.2：写编辑副本，保存统一落 store
              } else {
                this.reviewCardError = '请输入 0~20 的整数';
              }
            })
        }
        .width('100%')
        if (this.reviewCardError.length > 0) {
          Text(this.reviewCardError)
            .fontSize(12)
            .fontColor(DANGER)
            .margin({ top: 6 })
        }
        Text('AI 回复底部复习区、提炼等待页每次展示的卡片数；0=关闭（对话页只看对话）')
          .fontSize(11)
          .lineHeight(18)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 20 })

      // ★ 0.202.2 彩蛋（用户定稿文案，位于保存/返回按钮上方）：仓颉司文，此区司忆
      Text('昔仓颉造字以载文，今司忆守学而存忆')
        .fontSize(10)
        .fontColor(TEXT_TERTIARY)
        .opacity(0.75)
        .textAlign(TextAlign.Center)
        .margin({ top: 8, bottom: 8 })
    }
    .width('100%')
  }

  // ★ 0.167.8 用户拍板：原 Tab3「画布多树模式」内容整体删除——模式切换逻辑已由画布页
  //   顶部分段控件（平铺/选项卡）即时承担，设置内重复入口移除（canvasTabContent @Builder 随删）

  // ★ 0.165.2：Tab4 内容——云同步（分布式同步权限授权入口 + 状态显示；点按钮即时生效，无「保存」概念）
  @Builder
  cloudTabContent() {
    Column() {
      // 状态卡片
      Row() {
        // ★ 0.196.10 用户拍板：状态图标改「圈+勾」——未开启=描边圈+淡色勾（透明感，纯状态
        //   指示不可点；原空心圆「○」像可点按钮，用户实测「让我去点，实际点了没用」）；
        //   开启=绿圈+绿勾+淡绿底
        Stack() {
          Text('✓')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.syncOn ? '#4CAF50' : TEXT_TERTIARY)
        }
        .width(22)
        .height(22)
        .borderRadius(11)
        .border({ width: 1.5, color: this.syncOn ? '#4CAF50' : STROKE_CARD })
        .backgroundColor(this.syncOn ? 'rgba(76,175,80,0.12)' : Color.Transparent)
        Column() {
          Text(this.syncOn ? '云同步已开启' : '云同步未开启')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
          Text(this.syncOn
            ? '本设备对话数据将自动与云端保持一致'
            : (!this.account.isLoggedIn
              ? '云同步与华为账号绑定——请先登录华为账号' // ★ 0.196.8：未登录优先提示（用户拍板：先登录再开同步）
              : (isVip(this.subscription)
                ? '开启后，登录同一华为账号的多台设备共享对话数据'
                : '云同步为会员功能——订阅后开启（其他功能永久免费）'))) // ★ 0.194.0：非 VIP 提示
            .fontSize(11)
            .fontColor(TEXT_TERTIARY)
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 10 })
      }
      .width('100%')
      .padding(12)
      .borderRadius(RADIUS_CONTROL)
      .backgroundColor(this.syncOn
        ? ('rgba(76,175,80,0.12)')
        : (SURFACE_SOFT))
      .margin({ bottom: 16 })

      // 开启按钮（已开启则不显示——重复弹窗无意义；拒绝过可再点重试）
      // ★ 0.194.0：非 VIP 时按钮替换为「订阅后开启」——云同步是唯一会员功能，到期只锁这里
      // ★ 0.196.8：未登录时按钮点击拦截——云同步与华为账号绑定，先登录（用户拍板）
      // ★ 0.196.10：拦截 toast 升级登录引导弹窗——「登录华为账号」直拉登录（用户拍板：
      //   原让用户回主页/边栏登录多此一举）；弹窗 Index 根挂载
      // ★ 0.196.12：未登录/VIP 两分支按钮样式完全相同——合并为一个 Button，onClick 内分流
      //   （原两分支重复 12 行样式代码；非 VIP 分支样式不同保持独立）
      if (!this.account.isLoggedIn || isVip(this.subscription)) {
        Button('开启云同步')
          .width('100%')
          .height(48)
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(BRAND_PRIMARY)
          .fontColor(TEXT_PRIMARY)
          .borderRadius(RADIUS_CONTROL)
          .margin({ bottom: 16 })
          .onClick(() => {
            // 未登录：登录引导弹窗（Index 根挂载；登录成功直接开云同步——入口即意图 0.196.11）
            if (!this.account.isLoggedIn) {
              // ★ 0.226.0：未同意协议 → 先弹同意弹窗（Index 根挂载），同意后由 Index 续跑云同步登录
              if (needsAgreement()) {
                connectAgreementBridge().pendingAction = 'sync';
                connectAgreementBridge().promptVisible = true;
                return;
              }
              connectConfirmDialog().loginPromptVisible = true;
              return;
            }
            // 已登录 VIP：直接弹系统授权窗（授权即开；开关侧 enabled 已在 requestSyncPermission 内落 true）
            const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
            if (context === undefined || context === null) {
              this.showToastSafe('获取上下文失败，请重试');
              return;
            }
            requestSyncPermission(context).then((granted: boolean) => {
              this.permGranted = granted; // ★ 0.196.10：状态卡实时刷新
              this.showToastSafe(granted ? '云同步已开启' : '未授权，云同步保持关闭');
            });
          })
      } else {
        Button('订阅后开启')
          .width('100%')
          .height(48)
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(SURFACE_HOVER)
          .fontColor(TEXT_SECONDARY)
          .borderRadius(RADIUS_CONTROL)
          .margin({ bottom: 16 })
          .onClick(() => {
            this.showToastSafe('云同步为会员功能，请到边栏「账单」页订阅');
          })
      }

      // 使用条件说明
      Column() {
        Text('同步条件')
          .fontSize(13)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })
        Text('1. 各台设备均开启云同步，且登录同一个华为账号')
          .fontSize(11)
          .fontColor(TEXT_TERTIARY)
        Text('2. 系统「设置 → 华为账号 → 云空间」开关已打开')
          .fontSize(11)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
        Text('3. 云空间默认仅 WLAN 下同步（系统「云空间 → 高级设置」可改）')
          .fontSize(11)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
        Text('4. 对话数据经华为云空间加密存储，本地功能永久免费离线可用')
          .fontSize(11)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .padding(12)
      .borderRadius(RADIUS_CONTROL)
      .backgroundColor(SURFACE_SOFT)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  // ★ 0.190.6：复制反馈邮箱到剪贴板
  copyFeedbackEmail(): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, FEEDBACK_EMAIL);
      pasteboard.getSystemPasteboard().setData(data).catch(() => {});
      this.showToastSafe('邮箱已复制');
    } catch (_e) {
      this.showToastSafe('复制失败，请手动记录邮箱');
    }
  }

  // ★ 0.190.6：写反馈邮件——mailto 跳系统邮件应用，主题+设备信息（型号/系统/版本）自动预填，
  //   用户只需补问题描述与截图（应用内无法直接带附件发邮件，截图在邮件应用里添加）；
  //   无邮件应用时降级：复制邮箱 + toast 提示手动发送
  openFeedbackMail(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined || context === null) {
      this.copyFeedbackEmail();
      return;
    }
    const subject = encodeURIComponent(`DAGAI 反馈（${APP_VERSION}）`);
    const body = encodeURIComponent(
      `问题描述：\n\n\n—— 以下信息自动附加 ——\n应用版本：${APP_VERSION}\n设备型号：${deviceInfo.productModel}\n系统：${deviceInfo.osFullName}（API ${deviceInfo.sdkApiVersion}）\n（建议附上问题截图）`);
    const url = `mailto:${FEEDBACK_EMAIL}?subject=${subject}&body=${body}`;
    try {
      context.openLink(url).catch(() => {
        this.copyFeedbackEmail();
        this.showToastSafe('未找到邮件应用，邮箱已复制请手动发送');
      });
    } catch (_e) {
      this.copyFeedbackEmail();
      this.showToastSafe('未找到邮件应用，邮箱已复制请手动发送');
    }
  }

  // ★ 0.226.0：法律条款正文入口（0=用户协议 / 1=隐私政策）；
  // ★ 0.190.8：AlertDialog 系统灰弹窗 → 自定义暗紫弹窗（legalViewing 驱动 build Stack 顶层渲染）
  openLegal(idx: number): void {
    this.legalViewing = idx;
  }

  // ★ 0.226.0：华为账号用户认证协议——系统浏览器打开（不自行撰写；与 AgreementDialog 一致）
  openHuaweiAgreement(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ctx.openLink(HUAWEI_ACCOUNT_AGREEMENT_URL).catch(() => {
        // 打开失败静默
      });
    } catch (_e) {
      // 静默
    }
  }

  // ★ 0.226.0：撤回同意——回到未同意态（重新 gate 登录/云同步），本地功能不受影响
  revokeAgreementNow(): void {
    revokeAgreement();
    this.showToastSafe('已撤回同意，登录/云同步将重新要求同意');
  }

  // ============================================================
  // ★ 0.205.0：备份 Tab——数据安全三道防线
  // ============================================================

  // ★ 0.206.0：Tab 统一切换入口（埋点+原赋值；备份 Tab 进 Tab 时刷新备份快照）
  switchTab(n: number, name: string): void {
    this.currentTab = n;
 const _tp1: Record<string, string> = {}; _tp1['tab'] = name;
    track(this.getUIContext().getHostContext() as common.UIAbilityContext, 'settings_tab', _tp1); // 0.206.0 埋点
    if (n === 6) {
      this.refreshBackupSnapshot();
    }
  }

  // 备份状态快照刷新（preferences 非响应式，进 Tab/操作后手动同步）
  refreshBackupSnapshot(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const s = getBackupSettings(ctx);
    this.bkAutoEnabled = s.autoEnabled;
    this.bkUriReady = s.uri.length > 0;
    this.bkLastExt = s.lastExternalAt;
  }

  formatBkTime(ts: number): string {
    if (ts <= 0) {
      return '尚未备份';
    }
    const d = new Date(ts);
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }

  // 每日自动备份开关（开=弹系统选择器选目录+立即备份一份；取消=回弹关闭）
  onAutoToggle(on: boolean): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
 const _tp2: Record<string, string> = {}; _tp2['on'] = on ? 'y' : 'n';
    track(ctx, 'backup_auto_toggle', _tp2); // 0.206.0 埋点
    if (!on) {
      setAutoBackupEnabled(ctx, false);
      this.bkAutoEnabled = false;
      return;
    }
    this.bkBusy = true;
    pickBackupFile(ctx).then((uri: string) => {
      this.bkBusy = false;
      if (uri.length === 0) {
        this.bkAutoEnabled = false; // 用户取消——开关回弹
        setAutoBackupEnabled(ctx, false);
        this.showToastSafe('未选择目录，未开启自动备份');
        return;
      }
      setExternalUri(ctx, uri);
      setAutoBackupEnabled(ctx, true);
      this.bkAutoEnabled = true;
      this.bkUriReady = true;
      // 选完目录立即备份一份（验证可写+给用户即时正反馈）
      writeExternalBackup(ctx, buildBackupPayload(this.wordBank, this.knowledgeBank)).then((ok: boolean) => {
        if (ok) {
          this.showToastSafe('已开启：备份文件已保存到所选位置');
        } else {
          this.showToastSafe('目录不可写，请尝试更改目录');
        }
        this.refreshBackupSnapshot();
      });
    });
  }

  // 更改目录（新目录立即备份一份；旧目录文件不删不管——用户拍板）
  onChangeDir(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    track(ctx, 'backup_change_dir'); // 0.206.0 埋点
    this.bkBusy = true;
    pickBackupFile(ctx).then((uri: string) => {
      this.bkBusy = false;
      if (uri.length === 0) {
        return; // 取消保持原目录
      }
      setExternalUri(ctx, uri);
      this.bkUriReady = true;
      writeExternalBackup(ctx, buildBackupPayload(this.wordBank, this.knowledgeBank)).then((ok: boolean) => {
        this.showToastSafe(ok ? '已切换目录并备份' : '新目录不可写，请重试');
        this.refreshBackupSnapshot();
      });
    });
  }

  // 立即备份（手动）
  onBackupNow(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    track(ctx, 'backup_now'); // 0.206.0 埋点
    if (!this.bkUriReady) {
      this.showToastSafe('请先开启每日自动备份并选择目录');
      return;
    }
    writeExternalBackup(ctx, buildBackupPayload(this.wordBank, this.knowledgeBank)).then((ok: boolean) => {
      this.showToastSafe(ok ? '备份成功' : '目录不可写，请更改目录');
      this.refreshBackupSnapshot();
    });
  }

  // ★ 0.205.3 删 onRestoreInternal/bkLastInternal——内部备份完全后台静默（用户拍板：设置页露出只会让用户混乱）

  // 从备份文件导入（用户手里的 .dagbak——卸载重装/换机恢复用）
  onImportFile(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    track(ctx, 'backup_import'); // 0.206.0 埋点
    this.bkBusy = true;
    pickAndReadBackupFile(ctx).then((p: BackupPayload | undefined) => {
      this.bkBusy = false;
      if (p === undefined) {
        this.showToastSafe('已取消或文件无效');
        return;
      }
      const n = restoreFromPayload(this.wordBank, this.knowledgeBank, p);
      writeInternalBackup(ctx, buildBackupPayload(this.wordBank, this.knowledgeBank)); // 导入后立即内部备份
      this.showToastSafe(`已合并导入 ${n} 条`);
      this.refreshBackupSnapshot();
    });
  }

  // ★ 0.205.0：备份 Tab UI
  @Builder
  backupTabContent() {
    Column({ space: 12 }) {
      // 推荐横幅（用户拍板：好意推荐——备份文件是卸载/换机后唯一能救的）
      Row({ space: 8 }) {
        Text('💡')
          .fontSize(16)
        Column({ space: 2 }) {
          Text('推荐：开启每日自动备份')
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(FontWeight.Medium)
            .fontColor(BRAND_SECONDARY)
          Text('应用更新不会丢数据；但卸载/换机后，备份文件是唯一恢复方式')
            .fontSize(11)
            .fontColor(TEXT_TERTIARY)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding(10)
      .borderRadius(RADIUS_CONTROL)
      .backgroundColor(SURFACE_SOFT)

      // ── 卡片一：外部备份（用户目录）──
      Column({ space: 10 }) {
        Row() {
          Text('备份文件（推荐）')
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(FontWeight.Medium)
            .fontColor(TEXT_PRIMARY)
          Blank()
            .layoutWeight(1)
          if (this.bkUriReady) {
            Text('更改目录')
              .fontSize(12)
              .fontColor(BRAND_SECONDARY)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(RADIUS_CONTROL)
              .backgroundColor(SURFACE_HOVER)
              .onClick(() => {
                if (!this.bkBusy) {
                  this.onChangeDir();
                }
              })
          }
        }
        .width('100%')

        // 每日自动备份开关（默认关）
        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text('每日自动备份')
              .fontSize(FONT_SIZE_CARD_TITLE_SM)
              .fontColor(TEXT_PRIMARY)
            Text('每晚 0 点自动备份；错过则下次打开应用时补备')
              .fontSize(11)
              .fontColor(TEXT_TERTIARY)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.bkAutoEnabled })
            .selectedColor(BRAND_PRIMARY)
            .onChange((on: boolean) => {
              if (!this.bkBusy) {
                this.onAutoToggle(on);
              }
            })
        }
        .width('100%')

        Text(this.bkUriReady ? `备份位置：已选择 ✓　上次备份：${this.formatBkTime(this.bkLastExt)}` : '备份位置：未选择（开启开关后选择保存位置）')
          .fontSize(11)
          .fontColor(TEXT_TERTIARY)
          .width('100%')

        Button('立即备份')
          .width('100%')
          .height(40)
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(this.bkUriReady ? BRAND_PRIMARY : SURFACE_HOVER)
          .fontColor(this.bkUriReady ? TEXT_PRIMARY : TEXT_TERTIARY)
          .borderRadius(RADIUS_CONTROL)
          .onClick(() => {
            this.onBackupNow();
          })
      }
      .width('100%')
      .padding(14)
      .borderRadius(RADIUS_CONTROL)
      .backgroundColor(SURFACE_NODE)
      .alignItems(HorizontalAlign.Start)

      // ── 卡片二：导入（卸载重装/换机恢复）──
      // ★ 0.205.3 用户拍板：删「应用内部备份」卡——后台静默自动，不需要用户感知
      //   （恢复兜底仍在：启动检测空库+有备份自动弹「发现应用内部备份」）
      Column({ space: 10 }) {
        Text('导入备份文件')
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_PRIMARY)
          .width('100%')
        Text('选择之前导出的 .dagbak 文件，合并导入（同 ID 以备份为准，现有数据不会被删除）')
          .fontSize(11)
          .fontColor(TEXT_TERTIARY)
          .width('100%')
        Button('选择文件并导入')
          .width('100%')
          .height(40)
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(SURFACE_SOFT)
          .fontColor(TEXT_SECONDARY)
          .borderRadius(RADIUS_CONTROL)
          .onClick(() => {
            if (!this.bkBusy) {
              this.onImportFile();
            }
          })
      }
      .width('100%')
      .padding(14)
      .borderRadius(RADIUS_CONTROL)
      .backgroundColor(SURFACE_NODE)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  // ★ 0.190.6：Tab5 关于——版本号 + 反馈与联系（邮箱复制 / mailto 预填设备信息）+ 隐私政策入口
  // ★ 0.222.9：关于页 UI 卡片化重排——品牌信息卡（Logo+应用名+版本号+版权）+ 体验改进 + 反馈 + 隐私
  @Builder
  aboutTabContent() {
    Column({ space: 12 }) {
      // 品牌信息卡（Logo 渐变容器同边栏视觉语言；版本号下挂版权行）
      Column({ space: 4 }) {
        Column() {
          Image($r('app.media.gitbranch'))
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
        }
        .width(48)
        .height(48)
        .borderRadius(RADIUS_LOGO)
        .linearGradient({ angle: 225, colors: [[BRAND_PRIMARY, 0], [BRAND_SECONDARY, 1]] })
        .justifyContent(FlexAlign.Center)
        .margin({ bottom: 4 })

        Text('DAG AI Chat')
          .fontSize(15)
          .fontWeight(600)
          .fontFamily(FONT_INTER_SEMIBOLD)
          .fontColor(TEXT_PRIMARY)

        Text(APP_VERSION)
          .fontSize(12)
          .fontColor(TEXT_SECONDARY)
          .margin({ top: 2 })

        Text('本应用由孙加腾独立开发，版权所有')
          .fontSize(11)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 2 })
      }
      .width('100%')
      .padding({ top: 20, bottom: 18 })
      .borderRadius(RADIUS_CONTROL)
      .backgroundColor(SURFACE_SOFT)
      .alignItems(HorizontalAlign.Center)

      // ★ 0.206.0：体验改进计划（埋点隐私开关，默认关——用户拍板）
      Column({ space: 10 }) {
        Text('体验改进计划')
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_SECONDARY)
          .width('100%')

        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text('共享匿名使用数据')
              .fontSize(14)
              .fontColor(TEXT_PRIMARY)
            Text('帮助我们了解哪些功能被使用（仅匿名功能点击次数，不含任何对话/学习内容）。可随时关闭。')
              .fontSize(11)
              .lineHeight(18)
              .fontColor(TEXT_TERTIARY)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.trkEnabled })
            .selectedColor(BRAND_PRIMARY)
            .onChange((on: boolean) => {
              this.trkEnabled = on;
              setTrackingEnabled(this.getUIContext().getHostContext() as common.UIAbilityContext, on);
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding(14)
      .borderRadius(RADIUS_CONTROL)
      .backgroundColor(SURFACE_NODE)
      .alignItems(HorizontalAlign.Start)

      // 反馈与联系
      Column({ space: 10 }) {
        Text('反馈与联系')
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_SECONDARY)
          .width('100%')

        // 邮箱行（点击复制）
        Row() {
          Text(FEEDBACK_EMAIL)
            .fontSize(13)
            .fontColor(BRAND_PRIMARY)
            .layoutWeight(1)
          Text('复制')
            .fontSize(11)
            .fontColor(TEXT_TERTIARY)
        }
        .width('100%')
        .height(40)
        .borderRadius(RADIUS_CONTROL)
        .backgroundColor(SURFACE_SOFT)
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.copyFeedbackEmail();
        })

        // 写反馈邮件（mailto 预填设备信息）
        Button('✉ 写反馈邮件')
          .width('100%')
          .height(40)
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(BRAND_PRIMARY)
          .fontColor(TEXT_PRIMARY)
          .borderRadius(RADIUS_CONTROL)
          .onClick(() => {
            this.openFeedbackMail();
          })

        Text('💡 建议附上问题描述与截图，便于快速定位；设备型号、系统版本、应用版本已自动填入邮件。')
          .fontSize(11)
          .lineHeight(18)
          .fontColor(TEXT_TERTIARY)
          .width('100%')
      }
      .width('100%')
      .padding(14)
      .borderRadius(RADIUS_CONTROL)
      .backgroundColor(SURFACE_NODE)
      .alignItems(HorizontalAlign.Start)

      // 法律条款（★ 0.226.0：原「隐私政策」卡扩为三协议入口 + 撤回同意）
      Column({ space: 10 }) {
        Text('法律条款')
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_SECONDARY)
          .width('100%')

        Row() {
          Text(AGREEMENT_USER_NAME)
            .fontSize(13)
            .fontColor(TEXT_PRIMARY)
            .layoutWeight(1)
          Text('›')
            .fontSize(14)
            .fontColor(TEXT_TERTIARY)
        }
        .width('100%')
        .height(40)
        .borderRadius(RADIUS_CONTROL)
        .backgroundColor(SURFACE_SOFT)
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.openLegal(0);
        })

        Row() {
          Text('隐私政策')
            .fontSize(13)
            .fontColor(TEXT_PRIMARY)
            .layoutWeight(1)
          Text('›')
            .fontSize(14)
            .fontColor(TEXT_TERTIARY)
        }
        .width('100%')
        .height(40)
        .borderRadius(RADIUS_CONTROL)
        .backgroundColor(SURFACE_SOFT)
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.openLegal(1);
        })

        Row() {
          Text(AGREEMENT_HUAWEI_NAME)
            .fontSize(13)
            .fontColor(TEXT_PRIMARY)
            .layoutWeight(1)
          Text('↗')
            .fontSize(13)
            .fontColor(TEXT_TERTIARY)
        }
        .width('100%')
        .height(40)
        .borderRadius(RADIUS_CONTROL)
        .backgroundColor(SURFACE_SOFT)
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.openHuaweiAgreement();
        })

        Text('💡 协议内容与首次启动的同意弹窗一致；数据默认存储在设备本地，登录后才可能云同步。')
          .fontSize(11)
          .lineHeight(18)
          .fontColor(TEXT_TERTIARY)
          .width('100%')

        Button('撤回同意')
          .width('100%')
          .height(36)
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .backgroundColor(SURFACE_SOFT)
          .fontColor(TEXT_SECONDARY)
          .borderRadius(RADIUS_CONTROL)
          .onClick(() => {
            this.revokeAgreementNow();
          })
      }
      .width('100%')
      .padding(14)
      .borderRadius(RADIUS_CONTROL)
      .backgroundColor(SURFACE_NODE)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  build() {
    Stack() {
      // 遮罩：★ 0.196.2 用户拍板——点击空白关闭（走 requestClose 安全路径：有未保存改动先弹确认，无改动直接关；
      //   0.148 教训「误触丢输入」由未保存确认兜底，不再一刀切禁点）
      Column() {
        Blank()
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0,0,0,0.5)')
      .onClick(() => {
        this.requestClose();
      })

      // 面板
      Column() {
        // 标题行：全局设置 + ✕ 关闭
        Row() {
          Text('全局设置')
            .fontSize(FONT_SIZE_SCREEN_TITLE)
            .fontWeight(600) // ★ 0.174.1：SemiBold 枚举本 API 版本不存在，数字 600 等效（fontFamily 已切 Inter-SemiBold）
            .fontColor(TEXT_PRIMARY)
            .fontFamily(FONT_INTER_SEMIBOLD)
          Blank()
            .layoutWeight(1)
          Text('✕')
            .fontSize(16)
            .fontColor(TEXT_SECONDARY)
            .onClick(() => {
              this.requestClose();
            })
        }
        .width('100%')
        .margin({ bottom: 12 })

        // Tab 切换行（★ 0.174.1：改分段控件——轨道 SEGMENTED_TRACK + 选中段 BRAND_PRIMARY，与画布页分段控件同规格；★ 0.167.8：删「画布」Tab）
        // ★ 0.205.3：①「备份」移到司忆区后（用户拍板）②横向 Scroll 包裹——6 个 Tab 超出弹窗最大宽度时可滑动（用户实测溢出）
        Scroll() {
          Row() {
            Text('API 配置')
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(this.currentTab === 0 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.currentTab === 0 ? TEXT_PRIMARY : TEXT_SECONDARY)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(this.currentTab === 0 ? BRAND_PRIMARY : Color.Transparent)
            .onClick(() => {
              this.switchTab(0, 'api');
            })
          Text('AI 偏好')
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(this.currentTab === 1 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.currentTab === 1 ? TEXT_PRIMARY : TEXT_SECONDARY)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(this.currentTab === 1 ? BRAND_PRIMARY : Color.Transparent)
            .margin({ left: 4 })
            .onClick(() => {
              this.switchTab(1, 'pref');
            })
          Text('司忆区') // ★ 0.202.1：改名「复习区」→「司忆区」（用户拍板——取「仓颉司文、此区司忆」之意，凸显注意力驱动记忆的独创性）
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(this.currentTab === 5 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.currentTab === 5 ? TEXT_PRIMARY : TEXT_SECONDARY)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(this.currentTab === 5 ? BRAND_PRIMARY : Color.Transparent)
            .margin({ left: 4 })
            .onClick(() => {
              this.switchTab(5, 'review');
              // 进 Tab 预填自定义值（>2 显示当前值，≤2 走快速项留空）
              this.reviewWordInput = this.learnCountStore.learnCount > 2 ? `${this.learnCountStore.learnCount}` : '';
              this.reviewCardInput = this.knowledgeCountStore.knowledgeCount > 2 ? `${this.knowledgeCountStore.knowledgeCount}` : '';
              this.reviewWordError = '';
              this.reviewCardError = '';
              // ★ 0.197.2：编辑副本回显（保存模式——每次进 Tab 重置为已保存值）
              this.editReviewLearn = this.learnCountStore.learnCount;
              this.editReviewKnowledge = this.knowledgeCountStore.knowledgeCount;
            })
          Text('备份') // ★ 0.205.3：移到司忆区后（用户拍板；currentTab=6 不重排既有索引）
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(this.currentTab === 6 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.currentTab === 6 ? TEXT_PRIMARY : TEXT_SECONDARY)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(this.currentTab === 6 ? BRAND_PRIMARY : Color.Transparent)
            .margin({ left: 4 })
            .onClick(() => {
              this.switchTab(6, 'backup');
              this.refreshBackupSnapshot(); // 进 Tab 刷新备份状态快照
            })
          Text('云同步') // ★ 0.165.2：Tab4 云同步（权限授权入口）
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(this.currentTab === 3 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.currentTab === 3 ? TEXT_PRIMARY : TEXT_SECONDARY)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(this.currentTab === 3 ? BRAND_PRIMARY : Color.Transparent)
            .margin({ left: 4 })
            .onClick(() => {
              this.switchTab(3, 'cloud');
            })
          Text('关于') // ★ 0.190.6：Tab5 关于（版本号+反馈与联系+隐私政策）
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(this.currentTab === 4 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.currentTab === 4 ? TEXT_PRIMARY : TEXT_SECONDARY)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(this.currentTab === 4 ? BRAND_PRIMARY : Color.Transparent)
            .margin({ left: 4 })
            .onClick(() => {
              this.switchTab(4, 'about');
            })
          }
        }
        .scrollable(ScrollDirection.Horizontal) // 0.205.3：Tab 超宽可横向滑动（Row 内容自适应宽度）
        .scrollBar(BarState.Off) // 0.205.4 用户拍板：滚动杠不要
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
        .padding({ left: 12, right: 12, top: 3, bottom: 3 }) // ★ 0.232.1/0.232.2 轨道两端留白（用户两轮拍板：首尾 Tab 贴轨道边缘难看——8 仍不够显眼，定 12）
        .borderRadius(RADIUS_CONTROL)
        .backgroundColor(SEGMENTED_TRACK)
        .margin({ bottom: 12 })

        // 内容区：Scroll 包裹（Tab1 表单超屏可滚动，0.140 教训——保存按钮固定底部不被推出）
        Scroll() {
          if (this.currentTab === 6) {
            this.backupTabContent() // ★ 0.205.0：备份 Tab（三道防线）
          } else if (this.currentTab === 0) {
            this.apiTabContent()
          } else if (this.currentTab === 1) {
            this.prefTabContent()
          } else if (this.currentTab === 5) {
            this.reviewTabContent() // ★ 0.195.0：复习显示 Tab（★ 0.197.2：保存模式——底部有保存按钮）
          } else if (this.currentTab === 4) {
            this.aboutTabContent() // ★ 0.190.6：Tab5 关于
          } else {
            this.cloudTabContent() // ★ 0.165.2：Tab4 云同步（★ 0.167.8：画布分支随 Tab 删除）
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Off) // ★ 0.235.1：右侧滚动杠取消（0.205.4 用户拍板「滚动杠不要」同族补齐——AI 偏好页右侧灰线难看，0.235.1 圈注）
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)

        // 底部按钮行（固定底部；保存不关弹窗）
        // ★ 0.175.0：①保存右侧加「返回」按钮（次级样式，走 requestClose——有未保存修改时二次确认）
        //   ②云同步 Tab 无保存概念，补全宽「返回」——三 Tab 底部不空、统一协调
        // ★ 0.190.6：关于 Tab（4）同云同步——无保存概念，全宽返回
        // ★ 0.197.2：复习 Tab(5) 改保存模式（用户反馈：要保存按钮）——与 API/AI 偏好同款保存+返回
        // ★ 0.197.3：等宽修复——间隙从「返回」按钮的 margin left 12 改为 Row({ space: 12 })：
        //   margin 参与布局会把返回挤窄 12vp（用户实测两按钮宽度不一样）；space 均分剩余空间，
        //   双按钮 layoutWeight(1) 像素级等宽等高（UI_GUIDELINES 设置弹窗·底部保存按钮行）
        if (this.currentTab !== 3 && this.currentTab !== 4 && this.currentTab !== 6) {
          Row({ space: 12 }) {
            Button('保存')
              .layoutWeight(1)
              .height(48)
              .fontSize(FONT_SIZE_CARD_TITLE_SM)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(BRAND_PRIMARY)
              .fontColor(TEXT_PRIMARY)
              .borderRadius(RADIUS_CONTROL)
              .onClick(() => {
                this.saveAll();
              })
            Button('返回')
              .layoutWeight(1)
              .height(48)
              .fontSize(FONT_SIZE_CARD_TITLE_SM)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(SURFACE_SOFT)
              .fontColor(TEXT_SECONDARY)
              .borderRadius(RADIUS_CONTROL)
              .onClick(() => {
                this.requestClose();
              })
          }
          .width('100%')
          .margin({ top: 12 })
        } else {
          Button('返回')
            .width('100%')
            .height(48)
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(SURFACE_SOFT)
            .fontColor(TEXT_SECONDARY)
            .borderRadius(RADIUS_CONTROL)
            .margin({ top: 12 })
            .onClick(() => {
              this.requestClose();
            })
        }
      }
      .width(this.windowMode.isTablet ? 560 : '92%') // ★ 0.232.1 断点制（用户拍板：配置类弹窗 PC/Pad 固定 560，不做屏宽自适应——聊天页才需要自适应）；★ 0.233.0：手机 94%→92%（用户实锤「右边顶格」——弹窗左右必须各留空地不贴边）
      .height('88%')
      .padding(16)
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
      .border({ width: 1, color: STROKE_CARD })

      // ★ 0.226.0：法律条款正文弹窗（用户协议/隐私政策共用；legalViewing 驱动）
      // ★ 0.190.8：原隐私政策自定义弹窗（Stack 顶层，暗紫设计语言替代系统 AlertDialog 灰弹窗）
      if (this.legalViewing >= 0) {
        // 遮罩（点击关闭——纯阅读无输入，不怕误触）
        Column() {
          Blank()
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => {
          this.legalViewing = -1;
        })

        // 面板
        Column() {
          Text(this.legalViewing === 0 ? AGREEMENT_USER_NAME : '隐私政策')
            .fontSize(FONT_SIZE_SCREEN_TITLE)
            .fontWeight(600)
            .fontColor(TEXT_PRIMARY)
            .fontFamily(FONT_INTER_SEMIBOLD)
            .margin({ bottom: 12 })

          Scroll() {
            Column() {
              ForEach(this.legalViewing === 0 ? USER_AGREEMENT_SECTIONS : PRIVACY_SECTIONS, (section: string, idx: number) => {
                Text(section)
                  .fontSize(13)
                  .lineHeight(20)
                  .fontColor(idx === 0 ? TEXT_PRIMARY : TEXT_SECONDARY)
                  .fontWeight(idx === 0 ? FontWeight.Medium : FontWeight.Normal)
                  .margin({ bottom: 10 })
                  .width('100%')
              }, (section: string, idx: number) => `${idx}`)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollable(ScrollDirection.Vertical)
          .scrollBar(BarState.Off) // ★ 0.235.1：滚动杠取消（0.205.4 拍板同族——法律条款纯阅读弹窗一并统一）
          .edgeEffect(EdgeEffect.Spring)
          .align(Alignment.Top)

          Button('我知道了')
            .width('100%')
            .height(48)
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(BRAND_PRIMARY)
            .fontColor(TEXT_PRIMARY)
            .borderRadius(RADIUS_CONTROL)
            .margin({ top: 12 })
            .onClick(() => {
              this.legalViewing = -1;
            })
        }
        .width(this.windowMode.isTablet ? 520 : '88%') // ★ 0.232.1 断点制（同设置弹窗——PC/Pad 固定 520 不自适应）
        .height('80%')
        .padding(20)
        .borderRadius(RADIUS_NAV)
        .backgroundColor(SURFACE_NODE)
        .border({ width: 1, color: STROKE_CARD })
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }
}



