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

import { AppStorageV2 } from '@kit.ArkUI';
import { ApiConfig, AiPreference, connectApiConfig, connectAiPreference, CanvasMode, CanvasModeStore, connectCanvasMode, applyCanvasModeSwitch } from '../common/ChatModel';
import { ThemeStore } from '../entryability/EntryAbility';

// 模型选项接口（与原 SettingsPage 一致，搬入保持组件自包含）
interface ModelOption {
  id: string;       // 模型ID（传给 API 的值）
  name: string;     // 显示名称
  type: string;     // 类型描述
  price: string;    // 百万 token 价格描述
}

// 已开通模型列表（硬编码，5 个；与原 SettingsPage 一致）
const MODEL_LIST: ModelOption[] = [
  { id: 'doubao-seed-2-1-lite-260915', name: 'Doubao-Seed-2.1-lite', type: '纯文本', price: '基础0.8 / 低延迟1.6 / 音频输入12 元/百万token' },
  { id: 'deepseek-v4-1-flash-260910', name: 'DeepSeek-V4.1-Flash', type: '多模态（图片理解）', price: '1~2 元/百万token' },
  { id: 'glm-5-3-flash-260828', name: 'GLM-5.3-Flash', type: '多模态（图片理解）', price: '0.8 元/百万token' },
  { id: 'deepseek-v4-pro-260425', name: 'DeepSeek-V4-Pro正式版', type: '纯文本', price: '基础9 / 低优4.5 元/百万token' },
  { id: 'deepseek-v4-flash-260425', name: 'DeepSeek-V4-Flash正式版', type: '纯文本', price: '基础2 / 低优1 元/百万token' },
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
  canvasModeStore: CanvasModeStore = connectCanvasMode(); // ★ 0.151：全新 key 'canvas-mode-v1'

  // Tab 切换（自绘按钮 + 条件渲染，不用 Tabs 组件）
  @Local currentTab: number = 0; // 0=API 配置，1=AI 偏好，2=画布（★ 0.151-bugfix4：画布多树模式独立成第三个 Tab）

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
  // ★ 0.151 Tab2 编辑副本（画布模式；点保存才执行切换——切换涉及工作区数据搬移，不宜点选即切）
  @Local editCanvasMode: CanvasMode = 'flat'; // 'flat' 平铺 / 'tabs' 选项卡

  // ★ 0.131：获取全局主题状态（与 ChatPage/BBTreeCanvas 相同模式）
  getThemeStore(): ThemeStore {
    return AppStorageV2.connect(ThemeStore, 'theme-store', () => new ThemeStore()) as ThemeStore;
  }

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
    // ★ 0.151：画布模式编辑副本
    this.editCanvasMode = this.canvasModeStore.mode;

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
      this.editEncourage !== this.aiPreference.encourageEnabled || // ★ 0.150：鼓励开关
      this.editCanvasMode !== this.canvasModeStore.mode;           // ★ 0.151：画布模式
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
    // ★ 0.151：画布模式切换——先执行工作区切换（两池数据各归其位），再写 mode 持久化
    if (this.editCanvasMode !== this.canvasModeStore.mode) {
      applyCanvasModeSwitch(this.editCanvasMode);
      this.canvasModeStore.mode = this.editCanvasMode;
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

  // ★ 0.150：Tab1 内容——API 配置表单（原 SettingsPage L135-356 整体搬入，保存按钮除外）
  @Builder
  apiTabContent() {
    Column() {
      // API Key 输入
      Column() {
        Text('API Key')
          .fontSize(14)
          .fontColor(this.getThemeStore().isDark ? '#888888' : '#666')
          .margin({ bottom: 6 })
        TextInput({ text: $$this.editKey, placeholder: '填入火山方舟 API Key' })
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
          .placeholderColor(this.getThemeStore().isDark ? '#777777' : '#666666')
          .borderRadius(8)
          .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#F5F5F5')
      }
      .width('100%')
      .margin({ bottom: 16 })

      // Endpoint 输入
      Column() {
        Text('Endpoint')
          .fontSize(14)
          .fontColor(this.getThemeStore().isDark ? '#888888' : '#666')
          .margin({ bottom: 6 })
        TextInput({ text: $$this.editEndpoint, placeholder: 'API 地址' })
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
          .placeholderColor(this.getThemeStore().isDark ? '#777777' : '#666666')
          .borderRadius(8)
          .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#F5F5F5')
      }
      .width('100%')
      .margin({ bottom: 16 })

      // Model 下拉选择
      Column() {
        Text('Model')
          .fontSize(14)
          .fontColor(this.getThemeStore().isDark ? '#888888' : '#666')
          .margin({ bottom: 6 })

        // 下拉触发器：显示当前选中模型名称 + 箭头
        Row() {
          Text(MODEL_LIST[this.selectedModelIndex].name)
            .fontSize(14)
            .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
            .layoutWeight(1)
          Text(this.isDropdownOpen ? '▲' : '▼')
            .fontSize(12)
            .fontColor(this.getThemeStore().isDark ? '#777777' : '#999')
        }
        .width('100%')
        .height(48)
        .borderRadius(8)
        .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#F5F5F5')
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
                  .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
                // 小字：类型 + 价格
                Text(`${model.type} · ${model.price}`)
                  .fontSize(12)
                  .fontColor(this.getThemeStore().isDark ? '#777777' : '#999')
                  .margin({ top: 2 })
              }
              .width('100%')
              .padding(12)
              .backgroundColor(index === this.selectedModelIndex
                ? (this.getThemeStore().isDark ? '#1E3A5F' : '#E3F2FD')
                : (this.getThemeStore().isDark ? '#2C2C2C' : '#FFFFFF'))
              .onClick(() => {
                this.selectedModelIndex = index;
                this.editModel = model.id;
                this.isDropdownOpen = false;
              })
            }, (model: ModelOption) => model.id)
          }
          .width('100%')
          .borderRadius(8)
          .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#FFFFFF')
          .border({ width: 1, color: this.getThemeStore().isDark ? '#555555' : '#E0E0E0' })
          .margin({ top: 4 })
        }

        // 提示：模型 ID 说明
        Text('⚠️ 控制台展示名称≠API调用ID，预置模型示例：doubao-seed-2-1-lite-260915；数字之间是短横线`-`，禁止小数点，直接复制上表ID使用。')
          .fontSize(11)
          .fontColor(this.getThemeStore().isDark ? '#777777' : '#999')
          .margin({ top: 4 })
      }
      .width('100%')
      .margin({ bottom: 24 })

      // ★ 0.140：音频 API Key 输入（豆包语音控制台 Key，与对话方舟 Key 相互独立——两套体系不通用）
      Column() {
        Text('音频 API Key')
          .fontSize(14)
          .fontColor(this.getThemeStore().isDark ? '#888888' : '#666')
          .margin({ bottom: 6 })
        TextInput({ text: $$this.editAudioKey, placeholder: '填入豆包语音控制台新建的 Key' })
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
          .placeholderColor(this.getThemeStore().isDark ? '#777777' : '#666666')
          .borderRadius(8)
          .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#F5F5F5')
        // 提示：音频 Key 与对话 Key 相互独立
        Text('⚠️ 语音合成走豆包语音（openspeech）体系，Key 需在豆包语音控制台新建，与上方对话用的方舟 API Key 相互独立、不通用。')
          .fontSize(11)
          .fontColor(this.getThemeStore().isDark ? '#777777' : '#999')
          .margin({ top: 4 })
      }
      .width('100%')
      .margin({ bottom: 16 })

      // ★ 0.133：音频模型配置（TTS 朗读用，预置下拉 + 手动编辑，单一数据源 editAudioModel）
      Column() {
        Text('音频模型（TTS 朗读）')
          .fontSize(14)
          .fontColor(this.getThemeStore().isDark ? '#888888' : '#666')
          .margin({ bottom: 6 })

        // 下拉触发器：显示当前音频模型 ID
        Row() {
          Text(this.audioModelDisplayName(this.editAudioModel))
            .fontSize(14)
            .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
            .layoutWeight(1)
          Text(this.isAudioDropdownOpen ? '▲' : '▼')
            .fontSize(12)
            .fontColor(this.getThemeStore().isDark ? '#777777' : '#999')
        }
        .width('100%')
        .height(48)
        .borderRadius(8)
        .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#F5F5F5')
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
                  .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
                Text(`${model.type} · ${model.price}`)
                  .fontSize(12)
                  .fontColor(this.getThemeStore().isDark ? '#777777' : '#999')
                  .margin({ top: 2 })
              }
              .width('100%')
              .padding(12)
              .backgroundColor(model.id === this.editAudioModel
                ? (this.getThemeStore().isDark ? '#1E3A5F' : '#E3F2FD')
                : (this.getThemeStore().isDark ? '#2C2C2C' : '#FFFFFF'))
              .onClick(() => {
                this.editAudioModel = model.id;
                this.isAudioDropdownOpen = false;
              })
            }, (model: ModelOption) => model.id)
          }
          .width('100%')
          .borderRadius(8)
          .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#FFFFFF')
          .border({ width: 1, color: this.getThemeStore().isDark ? '#555555' : '#E0E0E0' })
          .margin({ top: 4 })
        }

        // 手动编辑：可输入自定义音频模型 ID（覆盖下拉选择）
        TextInput({ text: $$this.editAudioModel, placeholder: '可手动输入自定义音频模型 ID' })
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
          .placeholderColor(this.getThemeStore().isDark ? '#777777' : '#666666')
          .borderRadius(8)
          .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#F5F5F5')
          .margin({ top: 8 })

        // 提示：音频模型说明
        Text('⚠️ 用于 AI 消息喇叭朗读。语音合成 2.0 走 openspeech HTTP 接口，音色使用内置默认值（zh_female_vv_uranus_bigtts），无需填写音色 ID。')
          .fontSize(11)
          .fontColor(this.getThemeStore().isDark ? '#777777' : '#999')
          .margin({ top: 4 })
      }
      .width('100%')
      .margin({ bottom: 16 })

      // ★ 0.133：音频 Endpoint 输入（TTS 接口地址，与对话 Endpoint 相互独立）
      Column() {
        Text('音频 Endpoint')
          .fontSize(14)
          .fontColor(this.getThemeStore().isDark ? '#888888' : '#666')
          .margin({ bottom: 6 })
        TextInput({ text: $$this.editAudioEndpoint, placeholder: 'TTS 接口地址' })
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
          .placeholderColor(this.getThemeStore().isDark ? '#777777' : '#666666')
          .borderRadius(8)
          .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#F5F5F5')
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
          .fontColor(this.getThemeStore().isDark ? '#888888' : '#666')
          .margin({ bottom: 6 })
        TextInput({ text: $$this.editNickname, placeholder: '如：大明（AI 回复会以此称呼你）' })
          .width('100%')
          .height(48)
          .fontSize(14)
          .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
          .placeholderColor(this.getThemeStore().isDark ? '#777777' : '#666666')
          .borderRadius(8)
          .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#F5F5F5')
        Text('💡 填写后 AI 在短/中/长全部回复模式都会以此称呼你；留空则不添加称呼。')
          .fontSize(11)
          .fontColor(this.getThemeStore().isDark ? '#777777' : '#999')
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
              .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
            Text('回复开头附 1~2 句学习鼓励')
              .fontSize(11)
              .fontColor(this.getThemeStore().isDark ? '#777777' : '#999')
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          // Toggle 用 onChange 回调写 @Local（isOn 仅初始值参数；不用 $$ 双向绑定，回调模式最稳）
          Toggle({ type: ToggleType.Switch, isOn: this.editEncourage })
            .selectedColor('#1976D2')
            .onChange((isOn: boolean) => {
              this.editEncourage = isOn;
            })
        }
        .width('100%')

        Text('💡 开启后 AI 会在回复开头（称呼之后、主体内容之前）结合当前学习主题给你 1~2 句鼓励（短回复不生成）；关闭后所有回复都不生成鼓励，仅保留称呼。')
          .fontSize(11)
          .fontColor(this.getThemeStore().isDark ? '#777777' : '#999')
          .margin({ top: 4 })
      }
      .width('100%')
      .margin({ bottom: 24 })
    }
    .width('100%')
  }

  // ★ 0.151-bugfix4：Tab3 内容——画布多树模式（用户需求：从 AI 偏好 Tab 挪出，独立成顶部第三个选项卡）
  @Builder
  canvasTabContent() {
    Column() {
      // ★ 0.151：画布多树模式单选（平铺 / 选项卡）
      Column() {
        Text('画布多树模式')
          .fontSize(14)
          .fontColor(this.getThemeStore().isDark ? '#888888' : '#666')
          .margin({ bottom: 6 })

        // 选项 1：多根平铺模式（默认）
        Row() {
          Text(this.editCanvasMode === 'flat' ? '●' : '○')
            .fontSize(16)
            .fontColor(this.editCanvasMode === 'flat' ? '#1976D2' : (this.getThemeStore().isDark ? '#777777' : '#999'))
          Column() {
            Text('多根平铺模式')
              .fontSize(14)
              .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
            Text('多棵树的根气泡同一行并排，右上角「添加根气泡」可新增树')
              .fontSize(11)
              .fontColor(this.getThemeStore().isDark ? '#777777' : '#999')
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 10 })
        }
        .width('100%')
        .padding(12)
        .borderRadius(8)
        .backgroundColor(this.editCanvasMode === 'flat'
          ? (this.getThemeStore().isDark ? '#1E3A5F' : '#E3F2FD')
          : (this.getThemeStore().isDark ? '#2C2C2C' : '#F5F5F5'))
        .onClick(() => {
          this.editCanvasMode = 'flat';
        })

        // 选项 2：选项卡多树模式
        Row() {
          Text(this.editCanvasMode === 'tabs' ? '●' : '○')
            .fontSize(16)
            .fontColor(this.editCanvasMode === 'tabs' ? '#1976D2' : (this.getThemeStore().isDark ? '#777777' : '#999'))
          Column() {
            Text('选项卡多树模式')
              .fontSize(14)
              .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
            Text('画布顶部 Tab 栏，一个 Tab = 一棵独立树，可增删改名')
              .fontSize(11)
              .fontColor(this.getThemeStore().isDark ? '#777777' : '#999')
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 10 })
        }
        .width('100%')
        .padding(12)
        .borderRadius(8)
        .backgroundColor(this.editCanvasMode === 'tabs'
          ? (this.getThemeStore().isDark ? '#1E3A5F' : '#E3F2FD')
          : (this.getThemeStore().isDark ? '#2C2C2C' : '#F5F5F5'))
        .margin({ top: 8 })
        .onClick(() => {
          this.editCanvasMode = 'tabs';
        })

        // 提示：切换规则（数据互通）
        Text('💡 两模式是同一批树数据的两种展示：切到选项卡时每棵树自动变成一个 Tab（Tab 名 = 树根名）；切回平铺时全部 Tab 的树合并平铺显示。切换在点「保存」后生效。')
          .fontSize(11)
          .fontColor(this.getThemeStore().isDark ? '#777777' : '#999')
          .margin({ top: 6 })
      }
      .width('100%')
      .margin({ bottom: 16 })
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
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
          Blank()
            .layoutWeight(1)
          Text('✕')
            .fontSize(16)
            .fontColor(this.getThemeStore().isDark ? '#AAAAAA' : '#999999')
            .onClick(() => {
              this.requestClose();
            })
        }
        .width('100%')
        .margin({ bottom: 12 })

        // Tab 切换行（自绘按钮，选中态高亮；★ 0.151-bugfix4：三 Tab——API 配置 / AI 偏好 / 画布）
        Row() {
          Text('API 配置')
            .fontSize(15)
            .fontWeight(this.currentTab === 0 ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.currentTab === 0 ? '#1976D2' : (this.getThemeStore().isDark ? '#AAAAAA' : '#666'))
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .borderRadius(6)
            .backgroundColor(this.currentTab === 0
              ? (this.getThemeStore().isDark ? '#1E3A5F' : '#E3F2FD')
              : Color.Transparent)
            .onClick(() => {
              this.currentTab = 0;
            })
          Text('AI 偏好')
            .fontSize(15)
            .fontWeight(this.currentTab === 1 ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.currentTab === 1 ? '#1976D2' : (this.getThemeStore().isDark ? '#AAAAAA' : '#666'))
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .borderRadius(6)
            .backgroundColor(this.currentTab === 1
              ? (this.getThemeStore().isDark ? '#1E3A5F' : '#E3F2FD')
              : Color.Transparent)
            .margin({ left: 8 })
            .onClick(() => {
              this.currentTab = 1;
            })
          Text('画布')
            .fontSize(15)
            .fontWeight(this.currentTab === 2 ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.currentTab === 2 ? '#1976D2' : (this.getThemeStore().isDark ? '#AAAAAA' : '#666'))
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .borderRadius(6)
            .backgroundColor(this.currentTab === 2
              ? (this.getThemeStore().isDark ? '#1E3A5F' : '#E3F2FD')
              : Color.Transparent)
            .margin({ left: 8 })
            .onClick(() => {
              this.currentTab = 2;
            })
        }
        .width('100%')
        .margin({ bottom: 12 })

        // 内容区：Scroll 包裹（Tab1 表单超屏可滚动，0.140 教训——保存按钮固定底部不被推出）
        Scroll() {
          if (this.currentTab === 0) {
            this.apiTabContent()
          } else if (this.currentTab === 1) {
            this.prefTabContent()
          } else {
            this.canvasTabContent() // ★ 0.151-bugfix4：Tab3 画布多树模式
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollable(ScrollDirection.Vertical)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)

        // 保存按钮（两 Tab 共用，固定底部；保存不关弹窗）
        Button('保存')
          .width('100%')
          .height(48)
          .fontSize(16)
          .backgroundColor('#1976D2')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .margin({ top: 12 })
          .onClick(() => {
            this.saveAll();
          })
      }
      .width('94%')
      .height('88%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#FFFFFF')
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }
}
