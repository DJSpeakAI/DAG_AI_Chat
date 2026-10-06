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
import { requestSyncPermission, isCloudSyncOn } from '../utils/CloudSyncUtil'; // ★ 0.165.2：云同步 Tab（权限弹窗 + 状态查询）；★ 0.196.8：isCloudSyncOn——状态=权限&&应用级开关
import { HuaweiAccountStore, connectHuaweiAccount } from '../utils/HuaweiAccountUtil'; // ★ 0.196.8：云同步与账号绑定——未登录拦截「开启」
import { SubscriptionStore, connectSubscription, isVip } from '../common/ChatModel'; // ★ 0.194.0：云同步 VIP 守卫（到期只锁云同步）
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
const APP_VERSION: string = 'v0.196.9';
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
  // ★ 0.165.2 Tab3 云同步：是否真正开着（★ 0.196.8 语义升级：系统权限授予 && 应用级开关开——
  //   退出账号后开关强制关，权限仍在也显示未开启，与账号登录态一致）
  @Local syncGranted: boolean = false;
  subscription: SubscriptionStore = connectSubscription(); // ★ 0.194.0：云同步 VIP 守卫
  account: HuaweiAccountStore = connectHuaweiAccount(); // ★ 0.196.8：云同步↔账号绑定——未登录拦截「开启」
  learnCountStore: LearnCountStore = connectLearnCount(); // ★ 0.195.0：复习显示（全局设置直达——0=关闭复习区）
  knowledgeCountStore: KnowledgeCountStore = connectKnowledgeCount(); // ★ 0.195.0：同上（知识卡）
  // ★ 0.195.0：复习显示 Tab 输入态（0/1/2 快速项 + 自由输入框——与两库 ⚙ 设置同款布局）
  @Local reviewWordInput: string = '';
  @Local reviewWordError: string = '';
  @Local reviewCardInput: string = '';
  @Local reviewCardError: string = '';
  // ★ 0.190.8：隐私政策自定义弹窗显隐（替代系统 AlertDialog 灰弹窗，按应用设计语言）
  @Local privacyVisible: boolean = false;

  // ★ 0.189.1：audioModelDisplayName（音频模型 id→名称映射）已随云端 TTS 配置区移除

  aboutToAppear() {
    // ★ 0.190.0：Tab1 提供商化初始化——回显持久化配置
    this.editKey = this.apiConfig.apiKey;
    this.editProvider = this.apiConfig.provider;
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
    // ★ 0.196.8：云同步状态 = 权限授予 && 应用级开关开（退出账号后开关已关 → 显示未开启）
    isCloudSyncOn().then((on: boolean) => {
      this.syncGranted = on;
    });
  }

  // ★ 0.135/0.150/0.151：是否有未保存的修改（✕ 关闭拦截判断；★ 0.190.0：提供商化四项对比）
  hasUnsavedChanges(): boolean {
    return this.editProvider !== this.apiConfig.provider ||
      this.editKey.trim() !== this.apiConfig.apiKey ||
      this.currentModelValue() !== this.apiConfig.model ||
      this.currentEndpointValue() !== this.apiConfig.endpoint ||
      this.editNickname.trim() !== this.aiPreference.aiNickname || // ★ 0.150：称呼
      this.editEncourageMode !== this.aiPreference.encourageMode;   // ★ 0.191.0：鼓励三档
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
  //   布局与两库 ⚙ 设置完全同款：0/1/2 快速项 + 自由输入框一行（界面统一）；即时生效无保存概念。
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
            .fontColor(this.learnCountStore.learnCount === 0 ? TEXT_PRIMARY : TEXT_SECONDARY)
            .backgroundColor(this.learnCountStore.learnCount === 0 ? BRAND_PRIMARY : Color.Transparent)
            .borderRadius(RADIUS_CONTROL)
            .onClick(() => {
              this.learnCountStore.learnCount = 0; // PersistenceV2 即时落盘，两处复习区即时生效
            })
          Button('1')
            .fontSize(14)
            .width(44)
            .height(40)
            .fontColor(this.learnCountStore.learnCount === 1 ? TEXT_PRIMARY : TEXT_SECONDARY)
            .backgroundColor(this.learnCountStore.learnCount === 1 ? BRAND_PRIMARY : Color.Transparent)
            .borderRadius(RADIUS_CONTROL)
            .margin({ left: 8 })
            .onClick(() => {
              this.learnCountStore.learnCount = 1;
            })
          Button('2')
            .fontSize(14)
            .width(44)
            .height(40)
            .fontColor(this.learnCountStore.learnCount === 2 ? TEXT_PRIMARY : TEXT_SECONDARY)
            .backgroundColor(this.learnCountStore.learnCount === 2 ? BRAND_PRIMARY : Color.Transparent)
            .borderRadius(RADIUS_CONTROL)
            .margin({ left: 8 })
            .onClick(() => {
              this.learnCountStore.learnCount = 2;
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
                this.learnCountStore.learnCount = n;
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
            .fontColor(this.knowledgeCountStore.knowledgeCount === 0 ? TEXT_PRIMARY : TEXT_SECONDARY)
            .backgroundColor(this.knowledgeCountStore.knowledgeCount === 0 ? BRAND_PRIMARY : Color.Transparent)
            .borderRadius(RADIUS_CONTROL)
            .onClick(() => {
              this.knowledgeCountStore.knowledgeCount = 0;
            })
          Button('1')
            .fontSize(14)
            .width(44)
            .height(40)
            .fontColor(this.knowledgeCountStore.knowledgeCount === 1 ? TEXT_PRIMARY : TEXT_SECONDARY)
            .backgroundColor(this.knowledgeCountStore.knowledgeCount === 1 ? BRAND_PRIMARY : Color.Transparent)
            .borderRadius(RADIUS_CONTROL)
            .margin({ left: 8 })
            .onClick(() => {
              this.knowledgeCountStore.knowledgeCount = 1;
            })
          Button('2')
            .fontSize(14)
            .width(44)
            .height(40)
            .fontColor(this.knowledgeCountStore.knowledgeCount === 2 ? TEXT_PRIMARY : TEXT_SECONDARY)
            .backgroundColor(this.knowledgeCountStore.knowledgeCount === 2 ? BRAND_PRIMARY : Color.Transparent)
            .borderRadius(RADIUS_CONTROL)
            .margin({ left: 8 })
            .onClick(() => {
              this.knowledgeCountStore.knowledgeCount = 2;
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
                this.knowledgeCountStore.knowledgeCount = n;
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
        Text(this.syncGranted ? '✓' : '○')
          .fontSize(18)
          .fontColor(this.syncGranted ? '#4CAF50' : (TEXT_TERTIARY))
        Column() {
          Text(this.syncGranted ? '云同步已开启' : '云同步未开启')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
          Text(this.syncGranted
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
      .backgroundColor(this.syncGranted
        ? ('rgba(76,175,80,0.12)')
        : (SURFACE_SOFT))
      .margin({ bottom: 16 })

      // 开启按钮（已开启则不显示——重复弹窗无意义；拒绝过可再点重试）
      // ★ 0.194.0：非 VIP 时按钮替换为「订阅后开启」——云同步是唯一会员功能，到期只锁这里
      // ★ 0.196.8：未登录时按钮点击拦截——云同步与华为账号绑定，先登录（用户拍板）
      if (!this.syncGranted) {
        if (!this.account.isLoggedIn) {
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
              this.showToastSafe('云同步需登录华为账号，请先登录后再开启');
            })
        } else if (isVip(this.subscription)) {
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
              const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
              if (context === undefined || context === null) {
                this.showToastSafe('获取上下文失败，请重试');
                return;
              }
              requestSyncPermission(context).then((granted: boolean) => {
                this.syncGranted = granted;
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
        Row() {
          Text('API 配置')
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(this.currentTab === 0 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.currentTab === 0 ? TEXT_PRIMARY : TEXT_SECONDARY)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(this.currentTab === 0 ? BRAND_PRIMARY : Color.Transparent)
            .onClick(() => {
              this.currentTab = 0;
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
              this.currentTab = 1;
            })
          Text('复习') // ★ 0.195.0：复习显示 Tab（用户拍板：从 AI 偏好挪顶层——与云同步/关于齐平，重要设置不能藏）
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(this.currentTab === 5 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.currentTab === 5 ? TEXT_PRIMARY : TEXT_SECONDARY)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(RADIUS_CONTROL)
            .backgroundColor(this.currentTab === 5 ? BRAND_PRIMARY : Color.Transparent)
            .margin({ left: 4 })
            .onClick(() => {
              this.currentTab = 5;
              // 进 Tab 预填自定义值（>2 显示当前值，≤2 走快速项留空）
              this.reviewWordInput = this.learnCountStore.learnCount > 2 ? `${this.learnCountStore.learnCount}` : '';
              this.reviewCardInput = this.knowledgeCountStore.knowledgeCount > 2 ? `${this.knowledgeCountStore.knowledgeCount}` : '';
              this.reviewWordError = '';
              this.reviewCardError = '';
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
              this.currentTab = 3;
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
              this.currentTab = 4;
            })
        }
        .width('100%')
        .padding(3)
        .borderRadius(RADIUS_CONTROL)
        .backgroundColor(SEGMENTED_TRACK)
        .margin({ bottom: 12 })

        // 内容区：Scroll 包裹（Tab1 表单超屏可滚动，0.140 教训——保存按钮固定底部不被推出）
        Scroll() {
          if (this.currentTab === 0) {
            this.apiTabContent()
          } else if (this.currentTab === 1) {
            this.prefTabContent()
          } else if (this.currentTab === 5) {
            this.reviewTabContent() // ★ 0.195.0：复习显示 Tab（即时生效无保存概念）
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
        if (this.currentTab !== 3 && this.currentTab !== 4 && this.currentTab !== 5) { // ★ 0.195.0：复习 Tab(5) 同云同步/关于——即时生效，全宽返回
          Row() {
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
              .margin({ left: 12 })
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
