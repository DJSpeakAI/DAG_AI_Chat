// ============================================================
// GlobalSettingsDialog.ets — 全局设置弹窗（★ 0.150）
// ============================================================
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
import { ApiConfig, AiPreference, connectApiConfig, connectAiPreference, inferProviderFromEndpoint, LearnCountStore, connectLearnCount, KnowledgeCountStore, connectKnowledgeCount } from '../common/ChatModel'; // ★ 0.190.0：加 inferProviderFromEndpoint（provider 异常值兜底推断）；★ 0.167.8：删画布 Tab——CanvasMode/CanvasModeStore/applyCanvasModeSwitch 引用随删（逻辑已由画布页顶部分段控件承担）；★ 0.195.0：加复习显示两库计数 store（全局设置直达 0=关闭复习区）
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
// ★ 0.174.1：UI 规格化——散落色值/isDark 三元收敛到 DesignTokens（0.166.3 锁暗色后浅色分支是死代码；AppStorageV2/ThemeStore 引用随 getThemeStore 删除）
import { SURFACE_NODE, SURFACE_HOVER, SURFACE_SOFT, BRAND_PRIMARY, BRAND_SECONDARY, TEXT_PRIMARY, TEXT_SECONDARY, TEXT_TERTIARY, STROKE_CARD, SEGMENTED_TRACK, RADIUS_CONTROL, RADIUS_NAV, FONT_SIZE_SCREEN_TITLE, FONT_SIZE_CARD_TITLE_SM, FONT_INTER_SEMIBOLD, DANGER } from '../common/DesignTokens'; // ★ 0.190.1：加 BRAND_SECONDARY（模型多模态标注高亮）；★ 0.195.0：加 DANGER（复习显示输入校验错误）

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

// ★ 0.190.6：应用版本常量（关于 Tab 显示 + 反馈邮件预填）——与 Index.ets 版本号、app.json5
// versionCode 三处同步（改版本时同步更新此处）
const APP_VERSION: string = 'v0.216.2';
// ★ 0.190.6：反馈邮箱（用户提供）
const FEEDBACK_EMAIL: string = '1725912449@qq.com';

// ★ 0.190.8：隐私政策正文分段（自定义暗紫弹窗渲染；华为只要求应用内有便捷查看入口+内容合规，
// 不规定 UI 样式——系统 AlertDialog 灰色弹窗按用户指示换成应用设计语言）
const PRIVACY_SECTIONS: string[] = [
  'DAGAI 尊重并保护你的隐私。本应用不收集、不上传任何个人信息。',
  '1. 本地存储：对话、单词库、知识库及 AI 配置（含 API Key）全部存储在设备本地，卸载即清除。',
  '2. AI 服务：对话内容仅在你主动发送时，按你配置的 AI 服务商（火山方舟 / 华为云 MaaS / DeepSeek / 自定义）接口直接传输，用于生成回复，本应用不经手留存。',
  '3. 云同步：如你开启云同步，数据经华为云空间加密，仅在你登录的华为账号设备间同步。',
  '4. 权限：仅在你主动选择图片时访问相册，无其他敏感权限。',
  '5. 联系我们：' + '1725912449@qq.com'
];

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

// 全局设置弹窗 — Tab1 API 配置（原 SettingsPage 搬入）+ Tab2 AI 偏好（★ 0.150 新增）
@ComponentV2
export struct GlobalSettingsDialog {
  @Param onClose: () => void = () => {}; // 关闭回调（父组件置 visible=false；✕/确认关闭统一走这里）
  @Param closeReq: number = 0; // ★ 0.150：外部请求关闭计数器（父组件返回键路径递增触发；走 requestClose 含未保存确认）

  apiConfig: ApiConfig = connectApiConfig();       // ★ 0.143：换 key 'api-config-v2' 工厂
  aiPreference: AiPreference = connectAiPreference(); // ★ 0.150：全新 key 'ai-preference-v1'
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

  // ★ 0.150 Tab2 编辑副本（AI 偏好）
  @Local editNickname: string = '';   // 自定义称呼（空 = 不添加称呼）
  @Local editEncourageMode: string = 'light'; // ★ 0.191.0：鼓励三档（off/light/heavy，默认轻度=原开关开）
  // ★ 0.196.10：云同步状态改响应式——permGranted（系统权限，开弹窗时异步查一次）&&
  //   cloudSwitch.enabled（应用级开关 @Trace，登录弹窗开启/退出强制关时**实时刷新**状态卡，
  //   不用重开设置弹窗；原 @Local syncGranted 开弹窗快照一次，开启后状态卡滞留「未开启」）
  @Local permGranted: boolean = false;
  cloudSwitch: CloudSyncStore = connectCloudSync();
  @Computed
  get syncOn(): boolean {
    return this.permGranted && this.cloudSwitch.enabled;
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
  // ★ 0.190.8：隐私政策自定义弹窗显隐（替代系统 AlertDialog 灰弹窗，按应用设计语言）
  @Local privacyVisible: boolean = false;

  // ★ 0.189.1：audioModelDisplayName（音频模型 id→名称映射）已随云端 TTS 配置区移除

  aboutToAppear() {
    // ★ 0.190.0：Tab1 提供商化初始化——回显持久化配置
    this.editKey = this.apiConfig.apiKey;
    this.editProvider = this.apiConfig.provider;
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
      this.editNickname.trim() !== this.aiPreference.aiNickname || // ★ 0.150：称呼
      this.editEncourageMode !== this.aiPreference.encourageMode || // ★ 0.191.0：鼓励三档
      this.editReviewLearn !== this.learnCountStore.learnCount || // ★ 0.197.2：复习显示（保存模式）
      this.editReviewKnowledge !== this.knowledgeCountStore.knowledgeCount;
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

  // ★ 0.150：保存——两 Tab 全部修改一次写入持久化 + toast 提示，不关弹窗（用户自己 ✕）
  saveAll(): void {
    // ★ 0.190.0：Tab1 提供商化写入（预设端点强制回内置值，防旧数据残留）
    this.apiConfig.provider = this.editProvider;
    this.apiConfig.apiKey = this.editKey.trim();
    this.apiConfig.model = this.currentModelValue();
    this.apiConfig.endpoint = this.currentEndpointValue();
    // Tab2：AI 偏好写入持久化（★ 0.150）
    this.aiPreference.aiNickname = this.editNickname.trim();
    this.aiPreference.encourageMode = this.editEncourageMode;
    // ★ 0.197.2：Tab5 复习显示写入（编辑副本→store，PersistenceV2 即时落盘，两处复习区即时生效）
    this.learnCountStore.learnCount = this.editReviewLearn;
    this.knowledgeCountStore.knowledgeCount = this.editReviewKnowledge;
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
    }
    .width('100%')
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
            .fontSize(12)
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
        // ★ 0.216.0 端侧兜底说明（同自定义 Key 区，两处 Key 输入框下统一）
        Text('未填 Key 时对话将使用本机端侧大模型（免费离线，效果较云端弱、暂不支持图片）。')
          .fontSize(11)
          .lineHeight(18)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
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
        // ★ 0.216.0 端侧兜底说明（用户拍板：Key 下方一行说明，前台零配置）——未配 Key 时对话自动
        //   使用本机免费端侧大模型（离线；能力较云端弱、不支持图片），支持机型开箱即用零门槛
        Text('未填 Key 时对话将使用本机端侧大模型（免费离线，效果较云端弱、暂不支持图片）。')
          .fontSize(11)
          .lineHeight(18)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
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

      // 自动鼓励三档（★ 0.191.0：开关→分段控件，用户定稿）
      // ★ 0.190.5：排版对齐「自定义称呼」区节奏——label 行（14/TEXT_SECONDARY）+ 下方提示小字
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

        Text('💡 轻度：回复开头 1~2 句温和鼓励；重度：2~4 句热情夸张的喝彩（「未来的爱因斯坦」式吹捧）；关闭：不生成鼓励。仅中/长回复模式生成，短回复模式不生成。') // ★ 0.191.0：三档说明
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

  // ★ 0.190.6：隐私政策入口；★ 0.190.8：AlertDialog 系统灰弹窗 → 自定义暗紫弹窗
  // （privacyVisible 驱动 build Stack 顶层渲染；华为不强制样式，按应用设计语言走）
  showPrivacyPolicy(): void {
    this.privacyVisible = true;
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
  @Builder
  aboutTabContent() {
    Column() {
      // 版本
      Column() {
        Text('版本')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })
        Text(APP_VERSION)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_PRIMARY)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 16 })

      // ★ 0.206.0：体验改进计划（埋点隐私开关，默认关——用户拍板）
      Column() {
        Text('体验改进计划')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })
        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text('共享匿名使用数据')
              .fontSize(15)
              .fontColor(TEXT_PRIMARY)
            Text('帮助我们了解哪些功能被使用（仅匿名功能点击次数，不含任何对话/学习内容）。可随时关闭。')
              .fontSize(11)
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
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 16 })

      // 反馈与联系
      Column() {
        Text('反馈与联系')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })

        // 邮箱行（点击复制）
        Row() {
          Text(FEEDBACK_EMAIL)
            .fontSize(14)
            .fontColor(BRAND_PRIMARY)
            .layoutWeight(1)
          Text('复制')
            .fontSize(12)
            .fontColor(TEXT_SECONDARY)
        }
        .width('100%')
        .height(48)
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
          .height(48)
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(BRAND_PRIMARY)
          .fontColor(TEXT_PRIMARY)
          .borderRadius(RADIUS_CONTROL)
          .margin({ top: 8 })
          .onClick(() => {
            this.openFeedbackMail();
          })

        Text('💡 建议附上问题描述与截图，便于快速定位；设备型号、系统版本、应用版本已自动填入邮件。')
          .fontSize(11)
          .lineHeight(18)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 16 })

      // 隐私政策
      Column() {
        Text('隐私政策')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })
        Button('查看隐私政策')
          .width('100%')
          .height(48)
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(SURFACE_SOFT)
          .fontColor(TEXT_SECONDARY)
          .borderRadius(RADIUS_CONTROL)
          .onClick(() => {
            this.showPrivacyPolicy();
          })
        Text('💡 本应用不收集任何个人信息，数据全部存储在设备本地。')
          .fontSize(11)
          .lineHeight(18)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
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
        .padding(3)
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
      .width('94%')
      .height('88%')
      .padding(16)
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
      .border({ width: 1, color: STROKE_CARD })

      // ★ 0.190.8：隐私政策自定义弹窗（Stack 顶层，暗紫设计语言替代系统 AlertDialog 灰弹窗）
      if (this.privacyVisible) {
        // 遮罩（点击关闭——纯阅读无输入，不怕误触）
        Column() {
          Blank()
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => {
          this.privacyVisible = false;
        })

        // 面板
        Column() {
          Text('隐私政策')
            .fontSize(FONT_SIZE_SCREEN_TITLE)
            .fontWeight(600)
            .fontColor(TEXT_PRIMARY)
            .fontFamily(FONT_INTER_SEMIBOLD)
            .margin({ bottom: 12 })

          Scroll() {
            Column() {
              ForEach(PRIVACY_SECTIONS, (section: string, idx: number) => {
                Text(section)
                  .fontSize(13)
                  .lineHeight(20)
                  .fontColor(idx === 0 ? TEXT_PRIMARY : TEXT_SECONDARY)
                  .fontWeight(idx === 0 ? FontWeight.Medium : FontWeight.Normal)
                  .margin({ bottom: 10 })
                  .width('100%')
              }, (section: string) => section)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollable(ScrollDirection.Vertical)
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
              this.privacyVisible = false;
            })
        }
        .width('88%')
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



