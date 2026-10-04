// ============================================================
// GlobalSettingsDialog.ets — 全局设置弹窗（★ 0.150）
// ============================================================
// 本文件是应用的全局设置弹窗（ChatPage 顶栏 ⚙ 与 BBTreeCanvas 画布 ⚙ 共用同一实例数据）：
//   - Tab 1「API 配置」：原 SettingsPage 表单整体搬入（对话 Key/Endpoint/模型下拉 +
//     音频 Key/音频模型/音频 Endpoint），含 0.139 旧值迁移逻辑
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
import { ApiConfig, AiPreference, connectApiConfig, connectAiPreference } from '../common/ChatModel'; // ★ 0.167.8：删画布 Tab——CanvasMode/CanvasModeStore/applyCanvasModeSwitch 引用随删（逻辑已由画布页顶部分段控件承担）
import { requestSyncPermission, isCloudSyncGranted } from '../utils/CloudSyncUtil'; // ★ 0.165.2：云同步 Tab（权限弹窗 + 状态查询）
// ★ 0.174.1：UI 规格化——散落色值/isDark 三元收敛到 DesignTokens（0.166.3 锁暗色后浅色分支是死代码；AppStorageV2/ThemeStore 引用随 getThemeStore 删除）
import { SURFACE_NODE, SURFACE_HOVER, SURFACE_SOFT, BRAND_PRIMARY, TEXT_PRIMARY, TEXT_SECONDARY, TEXT_TERTIARY, STROKE_CARD, SEGMENTED_TRACK, RADIUS_CONTROL, RADIUS_NAV, FONT_SIZE_SCREEN_TITLE, FONT_SIZE_CARD_TITLE_SM, FONT_INTER_SEMIBOLD } from '../common/DesignTokens';

// 模型选项接口（与原 SettingsPage 一致，搬入保持组件自包含）
interface ModelOption {
  id: string;       // 模型ID（传给 API 的值）
  name: string;     // 显示名称
  type: string;     // 类型描述
  price: string;    // 百万 token 价格描述
}

// 已开通模型列表（硬编码，2 个；与 SettingsPage 一致）★ 本轮：只留 DeepSeek 4.1 Flash + GLM 5.3 Flash（用户指定）
const MODEL_LIST: ModelOption[] = [
  { id: 'deepseek-v4-1-flash-260910', name: 'DeepSeek-V4.1-Flash', type: '多模态（图片理解）', price: '1~2 元/百万token' },
  { id: 'glm-5-3-flash-260828', name: 'GLM-5.3-Flash', type: '多模态（图片理解）', price: '0.8 元/百万token' },
];

// ★ 0.139：预置音频模型列表（TTS 朗读用）——「Doubao-语音合成2.0」（openspeech HTTP 单向流，官方文档实证）
const AUDIO_MODEL_LIST: ModelOption[] = [
  { id: 'seed-tts-2.0', name: 'Doubao-语音合成2.0', type: '通用语音合成', price: 'openspeech HTTP 接口，官方文档实证' },
];

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

  // Tab1 编辑副本（点保存才写入持久化；与原 SettingsPage 一致）
  @Local editKey: string = '';
  @Local editEndpoint: string = '';
  @Local editModel: string = '';
  @Local selectedModelIndex: number = 0;   // 下拉选中索引
  @Local isDropdownOpen: boolean = false;   // 下拉面板展开状态
  // ★ 0.133：音频模型本地编辑副本（单一数据源：下拉选中与手动输入都写入 editAudioModel）
  @Local editAudioModel: string = '';
  @Local editAudioEndpoint: string = '';
  @Local editAudioKey: string = ''; // ★ 0.140：音频 API Key 编辑副本（豆包语音 Key，与对话方舟 Key 相互独立）
  @Local isAudioDropdownOpen: boolean = false; // 音频模型下拉面板展开状态

  // ★ 0.150 Tab2 编辑副本（AI 偏好）
  @Local editNickname: string = '';   // 自定义称呼（空 = 不添加称呼）
  @Local editEncourage: boolean = true; // 自动鼓励开关（默认开启）
  // ★ 0.165.2 Tab3 云同步：分布式同步权限是否已授予（点「开启云同步」弹窗授权后刷新）
  @Local syncGranted: boolean = false;

  // ★ 0.134：音频模型触发器显示可读名字（预置列表 id→name 映射；自定义 ID 显示 ID 本身；空值显示未配置）
  audioModelDisplayName(id: string): string {
    if (id.length === 0) {
      return '未配置';
    }
    for (let i = 0; i < AUDIO_MODEL_LIST.length; i++) {
      if (AUDIO_MODEL_LIST[i].id === id) {
        return AUDIO_MODEL_LIST[i].name;
      }
    }
    return id;
  }

  aboutToAppear() {
    // 初始化 Tab1 编辑副本
    this.editKey = this.apiConfig.apiKey;
    this.editEndpoint = this.apiConfig.endpoint;
    this.editModel = this.apiConfig.model;
    // ★ 0.133：音频配置编辑副本
    this.editAudioModel = this.apiConfig.audioModel;
    this.editAudioEndpoint = this.apiConfig.audioEndpoint;
    this.editAudioKey = this.apiConfig.audioKey; // ★ 0.140：音频 Key 编辑副本初始化
    // ★ 0.150：Tab2 AI 偏好编辑副本
    this.editNickname = this.aiPreference.aiNickname;
    this.editEncourage = this.aiPreference.encourageEnabled;
    // ★ 0.165.2：云同步权限状态（异步查；已授权则「云同步」Tab 直接显示已开启）
    isCloudSyncGranted().then((granted: boolean) => {
      this.syncGranted = granted;
    });

    // ★ 0.139：旧值迁移——方舟端点组合（doubao-tts，两次真机实测 404）与播客 ID 一并迁移到 openspeech 2.0 协议
    // （原迁移逻辑在 SettingsPage aboutToAppear；SettingsPage 改弹窗后无入口，迁移职责随表单搬入本组件）
    if (this.editAudioModel === 'doubao-tts' || this.editAudioModel === 'doubao-tts-anchor-65-241005') {
      this.editAudioModel = 'seed-tts-2.0';
      this.apiConfig.audioModel = this.editAudioModel; // 迁移直接落持久化（PersistenceV2 自动保存），避免「未保存」误拦
    }
    // ★ 0.139：旧端点迁移——方舟 audio/speech 与播客 wss 端点都重置到 openspeech HTTP 单向流端点
    if (this.editAudioEndpoint === 'https://ark.cn-beijing.volces.com/api/v3/audio/speech' ||
      this.editAudioEndpoint === 'wss://openspeech.bytedance.com/api/v3/sami/podcasttts' ||
      this.editAudioEndpoint.length === 0) {
      this.editAudioEndpoint = 'https://openspeech.bytedance.com/api/v3/tts/unidirectional';
      this.apiConfig.audioEndpoint = this.editAudioEndpoint;
    }
    // ★ 0.139：音色迁移——1.0 音色（zh_female_cancan）配 2.0 模型会报错，重置为 2.0 默认音色（官方注意事项：不可混用）
    if (this.apiConfig.audioVoice === 'zh_female_cancan' || this.apiConfig.audioVoice.length === 0) {
      this.apiConfig.audioVoice = 'zh_female_vv_uranus_bigtts';
    }

    // 回显已保存的模型；找不到则默认第 0 项（Doubao-Seed-2.1-lite）
    let found = false;
    for (let i = 0; i < MODEL_LIST.length; i++) {
      if (MODEL_LIST[i].id === this.editModel) {
        this.selectedModelIndex = i;
        found = true;
        break;
      }
    }
    if (!found) {
      this.selectedModelIndex = 0;
      this.editModel = MODEL_LIST[0].id;
    }
    // ★ 0.133：音频模型不做强制回显覆盖（用户可能保存过自定义 ID，保留原值）
  }

  // ★ 0.135/0.150/0.151：是否有未保存的修改（✕ 关闭拦截判断；九项 = Tab1 六项 + Tab2 三项）
  hasUnsavedChanges(): boolean {
    return this.editKey.trim() !== this.apiConfig.apiKey ||
      this.editEndpoint.trim() !== this.apiConfig.endpoint ||
      this.editModel.trim() !== this.apiConfig.model ||
      this.editAudioModel.trim() !== this.apiConfig.audioModel ||
      this.editAudioEndpoint.trim() !== this.apiConfig.audioEndpoint ||
      this.editAudioKey.trim() !== this.apiConfig.audioKey || // ★ 0.140：音频 Key 纳入未保存判断
      this.editNickname.trim() !== this.aiPreference.aiNickname || // ★ 0.150：称呼
      this.editEncourage !== this.aiPreference.encourageEnabled;   // ★ 0.150：鼓励开关（★ 0.167.8：画布模式判断随 Tab 删除）
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
    // Tab1：API 配置写入持久化
    this.apiConfig.apiKey = this.editKey.trim();
    this.apiConfig.endpoint = this.editEndpoint.trim();
    this.apiConfig.model = this.editModel.trim();
    this.apiConfig.audioModel = this.editAudioModel.trim(); // ★ 0.133
    this.apiConfig.audioEndpoint = this.editAudioEndpoint.trim(); // ★ 0.133
    this.apiConfig.audioKey = this.editAudioKey.trim(); // ★ 0.140：音频 Key 写入持久化
    // Tab2：AI 偏好写入持久化（★ 0.150）
    this.aiPreference.aiNickname = this.editNickname.trim();
    this.aiPreference.encourageEnabled = this.editEncourage;
    // ★ 0.167.8：画布模式切换逻辑删除——模式切换已由画布页顶部分段控件即时承担（用户拍板）
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

  // ★ 0.150：Tab1 内容——API 配置表单（原 SettingsPage L135-356 整体搬入，保存按钮除外）
  @Builder
  apiTabContent() {
    Column() {
      // API Key 输入
      Column() {
        Text('API Key')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })
        TextInput({ text: $$this.editKey, placeholder: '填入火山方舟 API Key' })
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .placeholderColor(TEXT_TERTIARY)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
      }
      .width('100%')
      .margin({ bottom: 16 })

      // Endpoint 输入
      Column() {
        Text('Endpoint')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })
        TextInput({ text: $$this.editEndpoint, placeholder: 'API 地址' })
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .placeholderColor(TEXT_TERTIARY)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
      }
      .width('100%')
      .margin({ bottom: 16 })

      // Model 下拉选择
      Column() {
        Text('Model')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })

        // 下拉触发器：显示当前选中模型名称 + 箭头
        Row() {
          Text(MODEL_LIST[this.selectedModelIndex].name)
            .fontSize(14)
            .fontColor(TEXT_PRIMARY)
            .layoutWeight(1)
          Text(this.isDropdownOpen ? '▲' : '▼')
            .fontSize(12)
            .fontColor(TEXT_TERTIARY)
        }
        .width('100%')
        .height(48)
        .borderRadius(RADIUS_CONTROL)
        .backgroundColor(SURFACE_SOFT)
        .padding({ left: 12, right: 12 })
        .onClick(() => {
          this.isDropdownOpen = !this.isDropdownOpen;
        })

        // 下拉面板：每个选项两行布局
        if (this.isDropdownOpen) {
          Column() {
            ForEach(MODEL_LIST, (model: ModelOption, index: number) => {
              Column() {
                // 主文字：模型名称
                Text(model.name)
                  .fontSize(14)
                  .fontColor(TEXT_PRIMARY)
                // 小字：类型 + 价格
                Text(`${model.type} · ${model.price}`)
                  .fontSize(12)
                  .fontColor(TEXT_TERTIARY)
                  .margin({ top: 2 })
              }
              .width('100%')
              .padding(12)
              .backgroundColor(index === this.selectedModelIndex
                ? (SURFACE_HOVER)
                : (SURFACE_NODE))
              .onClick(() => {
                this.selectedModelIndex = index;
                this.editModel = model.id;
                this.isDropdownOpen = false;
              })
            }, (model: ModelOption) => model.id)
          }
          .width('100%')
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_NODE)
          .border({ width: 1, color: STROKE_CARD })
          .margin({ top: 4 })
        }

        // 提示：模型 ID 说明
        Text('⚠️ 控制台展示名称≠API调用ID，预置模型示例：doubao-seed-2-1-lite-260915；数字之间是短横线`-`，禁止小数点，直接复制上表ID使用。')
          .fontSize(11)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .margin({ bottom: 24 })

      // ★ 0.140：音频 API Key 输入（豆包语音控制台 Key，与对话方舟 Key 相互独立——两套体系不通用）
      Column() {
        Text('音频 API Key')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })
        TextInput({ text: $$this.editAudioKey, placeholder: '填入豆包语音控制台新建的 Key' })
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .placeholderColor(TEXT_TERTIARY)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
        // 提示：音频 Key 与对话 Key 相互独立
        Text('⚠️ 语音合成走豆包语音（openspeech）体系，Key 需在豆包语音控制台新建，与上方对话用的方舟 API Key 相互独立、不通用。')
          .fontSize(11)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .margin({ bottom: 16 })

      // ★ 0.133：音频模型配置（TTS 朗读用，预置下拉 + 手动编辑，单一数据源 editAudioModel）
      Column() {
        Text('音频模型（TTS 朗读）')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })

        // 下拉触发器：显示当前音频模型 ID
        Row() {
          Text(this.audioModelDisplayName(this.editAudioModel))
            .fontSize(14)
            .fontColor(TEXT_PRIMARY)
            .layoutWeight(1)
          Text(this.isAudioDropdownOpen ? '▲' : '▼')
            .fontSize(12)
            .fontColor(TEXT_TERTIARY)
        }
        .width('100%')
        .height(48)
        .borderRadius(RADIUS_CONTROL)
        .backgroundColor(SURFACE_SOFT)
        .padding({ left: 12, right: 12 })
        .onClick(() => {
          this.isAudioDropdownOpen = !this.isAudioDropdownOpen;
        })

        // 下拉面板：预置音频模型选项
        if (this.isAudioDropdownOpen) {
          Column() {
            ForEach(AUDIO_MODEL_LIST, (model: ModelOption) => {
              Column() {
                Text(model.name)
                  .fontSize(14)
                  .fontColor(TEXT_PRIMARY)
                Text(`${model.type} · ${model.price}`)
                  .fontSize(12)
                  .fontColor(TEXT_TERTIARY)
                  .margin({ top: 2 })
              }
              .width('100%')
              .padding(12)
              .backgroundColor(model.id === this.editAudioModel
                ? (SURFACE_HOVER)
                : (SURFACE_NODE))
              .onClick(() => {
                this.editAudioModel = model.id;
                this.isAudioDropdownOpen = false;
              })
            }, (model: ModelOption) => model.id)
          }
          .width('100%')
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_NODE)
          .border({ width: 1, color: STROKE_CARD })
          .margin({ top: 4 })
        }

        // 手动编辑：可输入自定义音频模型 ID（覆盖下拉选择）
        TextInput({ text: $$this.editAudioModel, placeholder: '可手动输入自定义音频模型 ID' })
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .placeholderColor(TEXT_TERTIARY)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
          .margin({ top: 8 })

        // 提示：音频模型说明
        Text('⚠️ 用于 AI 消息喇叭朗读。语音合成 2.0 走 openspeech HTTP 接口，音色使用内置默认值（zh_female_vv_uranus_bigtts），无需填写音色 ID。')
          .fontSize(11)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .margin({ bottom: 16 })

      // ★ 0.133：音频 Endpoint 输入（TTS 接口地址，与对话 Endpoint 相互独立）
      Column() {
        Text('音频 Endpoint')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .margin({ bottom: 6 })
        TextInput({ text: $$this.editAudioEndpoint, placeholder: 'TTS 接口地址' })
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .placeholderColor(TEXT_TERTIARY)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
      }
      .width('100%')
      .margin({ bottom: 16 })
    }
    .width('100%')
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
        TextInput({ text: $$this.editNickname, placeholder: '如：大明（AI 回复会以此称呼你）' })
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .placeholderColor(TEXT_TERTIARY)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(SURFACE_SOFT)
        Text('💡 填写后 AI 在短/中/长全部回复模式都会以此称呼你；留空则不添加称呼。')
          .fontSize(11)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .margin({ bottom: 24 })

      // 自动鼓励开关
      Column() {
        Row() {
          Column() {
            Text('自动鼓励')
              .fontSize(14)
              .fontColor(TEXT_PRIMARY)
            Text('回复开头附 1~2 句学习鼓励')
              .fontSize(11)
              .fontColor(TEXT_TERTIARY)
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          // Toggle 用 onChange 回调写 @Local（isOn 仅初始值参数；不用 $$ 双向绑定，回调模式最稳）
          Toggle({ type: ToggleType.Switch, isOn: this.editEncourage })
            .selectedColor(BRAND_PRIMARY)
            .onChange((isOn: boolean) => {
              this.editEncourage = isOn;
            })
        }
        .width('100%')

        Text('💡 开启后 AI 会在回复开头（称呼之后、主体内容之前）结合当前学习主题给你 1~2 句鼓励（短回复不生成）；关闭后所有回复都不生成鼓励，仅保留称呼。')
          .fontSize(11)
          .fontColor(TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .margin({ bottom: 24 })
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
          Text(this.syncGranted ? '本设备对话数据将自动与云端保持一致' : '开启后，登录同一华为账号的多台设备共享对话数据')
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

      // 开启按钮（已授权则不显示——授权是一次性的，重复弹窗无意义；拒绝过可再点重试）
      if (!this.syncGranted) {
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

  build() {
    Stack() {
      // 遮罩：点击不关闭（0.148 教训——弹窗内输入中误触遮罩会丢输入，故不加 onClick）
      Column() {
        Blank()
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0,0,0,0.5)')

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
          } else {
            this.cloudTabContent() // ★ 0.165.2：Tab4 云同步（★ 0.167.8：画布分支随 Tab 删除）
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollable(ScrollDirection.Vertical)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)

        // 保存按钮（Tab1~3 共用，固定底部；保存不关弹窗；★ 0.165.2：云同步 Tab 点按钮即时生效，无保存概念，隐藏）
        if (this.currentTab !== 3) {
          Button('保存')
            .width('100%')
            .height(48)
            .fontSize(FONT_SIZE_CARD_TITLE_SM)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(BRAND_PRIMARY)
            .fontColor(TEXT_PRIMARY)
            .borderRadius(RADIUS_CONTROL)
            .margin({ top: 12 })
            .onClick(() => {
              this.saveAll();
            })
        }
      }
      .width('94%')
      .height('88%')
      .padding(16)
      .borderRadius(RADIUS_NAV)
      .backgroundColor(SURFACE_NODE)
      .border({ width: 1, color: STROKE_CARD })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }
}
