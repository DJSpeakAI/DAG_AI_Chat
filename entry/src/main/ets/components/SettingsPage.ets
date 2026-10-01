// ============================================================
// SettingsPage.ets — API 配置页面
// ============================================================
// 本文件是应用的设置页面，功能包括：
//   - 火山引擎 API Key 输入
//   - API Endpoint 地址输入
//   - 模型选择（下拉列表，硬编码 5 个已开通模型）
//   - ★ 0.133：音频模型配置（TTS 朗读用，预置列表 + 手动编辑）+ 音频 Endpoint
//   - 保存配置到 PersistenceV2 持久化存储
//
// 技术栈：鸿蒙 ArkUI V2
// ============================================================

import { AppStorageV2 } from '@kit.ArkUI'; // ★ 0.131：追加 AppStorageV2（ThemeStore 共享）；★ 0.143：PersistenceV2 移入 connectApiConfig 内部使用
import { ApiConfig, connectApiConfig } from '../common/ChatModel'; // ★ 0.143：connectApiConfig 换 key 迁移
import { ThemeStore } from '../entryability/EntryAbility'; // ★ 0.131：深浅色适配

// 模型选项接口
interface ModelOption {
  id: string;       // 模型ID（传给 API 的值）
  name: string;     // 显示名称
  type: string;     // 类型描述
  price: string;    // 百万 token 价格描述
}

// 已开通模型列表（硬编码，5 个）
const MODEL_LIST: ModelOption[] = [
  { id: 'doubao-seed-2-1-lite-260915', name: 'Doubao-Seed-2.1-lite', type: '纯文本', price: '基础0.8 / 低延迟1.6 / 音频输入12 元/百万token' },
  { id: 'deepseek-v4-1-flash-260910', name: 'DeepSeek-V4.1-Flash', type: '多模态（图片理解）', price: '1~2 元/百万token' },
  { id: 'glm-5-3-flash-260828', name: 'GLM-5.3-Flash', type: '多模态（图片理解）', price: '0.8 元/百万token' },
  { id: 'deepseek-v4-pro-260425', name: 'DeepSeek-V4-Pro正式版', type: '纯文本', price: '基础9 / 低优4.5 元/百万token' },
  { id: 'deepseek-v4-flash-260425', name: 'DeepSeek-V4-Flash正式版', type: '纯文本', price: '基础2 / 低优1 元/百万token' },
];

// ★ 0.139：预置音频模型列表（TTS 朗读用）——「Doubao-语音合成2.0」（openspeech HTTP 单向流，官方文档实证）
// 0.134/0.137 两次真机实测方舟 /audio/speech + doubao-tts 均 404；用户提供官方文档确认 2.0 协议走 openspeech 端点（docs/0.139）
const AUDIO_MODEL_LIST: ModelOption[] = [
  { id: 'seed-tts-2.0', name: 'Doubao-语音合成2.0', type: '通用语音合成', price: 'openspeech HTTP 接口，官方文档实证' },
];

// API 配置页面 — 真机填写火山引擎 Key / Endpoint / Model
@ComponentV2
export struct SettingsPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  apiConfig: ApiConfig = connectApiConfig(); // ★ 0.143：换 key 'api-config-v2'（旧快照无 audioKey 字段致新增属性不落盘，工厂迁移历史配置）

  // 本地编辑副本，点保存才写入 AppStorageV2
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

  // ★ 0.131：获取全局主题状态（与 BBTreeCanvas/ChatPage 相同模式）
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
    // 初始化编辑副本
    this.editKey = this.apiConfig.apiKey;
    this.editEndpoint = this.apiConfig.endpoint;
    this.editModel = this.apiConfig.model;
    // ★ 0.133：音频配置编辑副本
    this.editAudioModel = this.apiConfig.audioModel;
    this.editAudioEndpoint = this.apiConfig.audioEndpoint;
    this.editAudioKey = this.apiConfig.audioKey; // ★ 0.140：音频 Key 编辑副本初始化
    // ★ 0.139：旧值迁移——方舟端点组合（doubao-tts，两次真机实测 404）与播客 ID 一并迁移到 openspeech 2.0 协议
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

  // ★ 0.135：是否有未保存的修改（返回键拦截判断）
  hasUnsavedChanges(): boolean {
    return this.editKey.trim() !== this.apiConfig.apiKey ||
      this.editEndpoint.trim() !== this.apiConfig.endpoint ||
      this.editModel.trim() !== this.apiConfig.model ||
      this.editAudioModel.trim() !== this.apiConfig.audioModel ||
      this.editAudioEndpoint.trim() !== this.apiConfig.audioEndpoint ||
      this.editAudioKey.trim() !== this.apiConfig.audioKey; // ★ 0.140：音频 Key 纳入未保存判断
  }

  build() {
    NavDestination() {
      // ★ 0.140：Scroll 包裹——设置项累计超出单屏（0.140 新增音频 Key 区块后保存按钮被推出屏幕外），
      // 页面不能滚动且保存按钮点不到；Scroll 让页面可上下滑动（内层 Column 高度自适应内容，不设 height 100%）
      Scroll() {
        Column() {
        // API Key 输入
        Column() {
          Text('API Key')
            .fontSize(14)
            .fontColor(this.getThemeStore().isDark ? '#888888' : '#666') // ★ 0.131：深浅色适配
            .margin({ bottom: 6 })
          TextInput({ text: $$this.editKey, placeholder: '填入火山方舟 API Key' })
            .width('100%')
            .height(48)
            .fontSize(14)
            .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333') // ★ 0.131
            .placeholderColor(this.getThemeStore().isDark ? '#777777' : '#666666') // ★ 0.131
            .borderRadius(8)
            .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#F5F5F5') // ★ 0.131
        }
        .width('100%')
        .margin({ bottom: 16 })

        // Endpoint 输入
        Column() {
          Text('Endpoint')
            .fontSize(14)
            .fontColor(this.getThemeStore().isDark ? '#888888' : '#666') // ★ 0.131：深浅色适配
            .margin({ bottom: 6 })
          TextInput({ text: $$this.editEndpoint, placeholder: 'API 地址' })
            .width('100%')
            .height(48)
            .fontSize(14)
            .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333') // ★ 0.131
            .placeholderColor(this.getThemeStore().isDark ? '#777777' : '#666666') // ★ 0.131
            .borderRadius(8)
            .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#F5F5F5') // ★ 0.131
        }
        .width('100%')
        .margin({ bottom: 16 })

        // Model 下拉选择
        Column() {
          Text('Model')
            .fontSize(14)
            .fontColor(this.getThemeStore().isDark ? '#888888' : '#666') // ★ 0.131：深浅色适配
            .margin({ bottom: 6 })

          // 下拉触发器：显示当前选中模型名称 + 箭头
          Row() {
            Text(MODEL_LIST[this.selectedModelIndex].name)
              .fontSize(14)
              .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333') // ★ 0.131
              .layoutWeight(1)
            Text(this.isDropdownOpen ? '▲' : '▼')
              .fontSize(12)
              .fontColor(this.getThemeStore().isDark ? '#777777' : '#999') // ★ 0.131
          }
          .width('100%')
          .height(48)
          .borderRadius(8)
          .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#F5F5F5') // ★ 0.131
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
                    .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333') // ★ 0.131
                  // 小字：类型 + 价格
                  Text(`${model.type} · ${model.price}`)
                    .fontSize(12)
                    .fontColor(this.getThemeStore().isDark ? '#777777' : '#999') // ★ 0.131
                    .margin({ top: 2 })
                }
                .width('100%')
                .padding(12)
                .backgroundColor(index === this.selectedModelIndex
                  ? (this.getThemeStore().isDark ? '#1E3A5F' : '#E3F2FD') // ★ 0.131：选中项高亮深浅色
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
            .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#FFFFFF') // ★ 0.131：面板背景
            .border({ width: 1, color: this.getThemeStore().isDark ? '#555555' : '#E0E0E0' }) // ★ 0.131：边框
            .margin({ top: 4 })
          }

          // 提示：模型 ID 说明
          Text('⚠️ 控制台展示名称≠API调用ID，预置模型示例：doubao-seed-2-1-lite-260915；数字之间是短横线`-`，禁止小数点，直接复制上表ID使用。')
            .fontSize(11)
            .fontColor(this.getThemeStore().isDark ? '#777777' : '#999') // ★ 0.131
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
        .margin({ bottom: 24 })

        // 保存按钮
        Button('保存')
          .width('100%')
          .height(48)
          .fontSize(16)
          .backgroundColor('#1976D2')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .onClick(() => {
            // 写入 AppStorageV2 持久化
            this.apiConfig.apiKey = this.editKey.trim();
            this.apiConfig.endpoint = this.editEndpoint.trim();
            this.apiConfig.model = this.editModel.trim();
            this.apiConfig.audioModel = this.editAudioModel.trim(); // ★ 0.133
            this.apiConfig.audioEndpoint = this.editAudioEndpoint.trim(); // ★ 0.133
            this.apiConfig.audioKey = this.editAudioKey.trim(); // ★ 0.140：音频 Key 写入持久化
            console.info('[SettingsPage] API config saved');
            this.pathStack.pop();
          })
        }
        .width('100%')
        .padding(16)
      }
      .width('100%')
      .height('100%')
      .scrollable(ScrollDirection.Vertical)
      .edgeEffect(EdgeEffect.Spring)
      .backgroundColor(this.getThemeStore().isDark ? '#1A1A1A' : '#FFFFFF') // ★ 0.131：页面背景深浅色
    }
    .title('API 配置')
    .onBackPressed(() => {
      // ★ 0.135：未保存提醒——改了下拉/输入框没点「保存」就返回时弹确认框
      // （0.135 真机复测踩坑：改完音频模型没点保存就返回，实际请求仍用旧值）
      if (this.hasUnsavedChanges()) {
        this.getUIContext().showAlertDialog({
          title: '修改未保存',
          message: '有修改尚未保存，确定要退出吗？',
          primaryButton: {
            value: '继续编辑',
            action: () => {}
          },
          secondaryButton: {
            value: '不保存退出',
            action: () => {
              this.pathStack.pop();
            }
          }
        });
        return true; // 拦截返回，等用户选择
      }
      return false; // 无修改，正常返回
    })
  }
}
