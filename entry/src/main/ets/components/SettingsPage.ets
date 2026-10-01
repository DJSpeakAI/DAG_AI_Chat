// ============================================================
// SettingsPage.ets — API 配置页面
// ============================================================
// 本文件是应用的设置页面，功能包括：
//   - 火山引擎 API Key 输入
//   - API Endpoint 地址输入
//   - 模型选择（下拉列表，硬编码 5 个已开通模型）
//   - 保存配置到 PersistenceV2 持久化存储
//
// 技术栈：鸿蒙 ArkUI V2
// ============================================================

import { PersistenceV2 } from '@kit.ArkUI'; // ★ 删除未使用 AppStorageV2（0.122 清理）
import { ApiConfig } from '../common/ChatModel';

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

// API 配置页面 — 真机填写火山引擎 Key / Endpoint / Model
@ComponentV2
export struct SettingsPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  apiConfig: ApiConfig = PersistenceV2.connect(ApiConfig, 'api-config', () => new ApiConfig()) as ApiConfig;

  // 本地编辑副本，点保存才写入 AppStorageV2
  @Local editKey: string = '';
  @Local editEndpoint: string = '';
  @Local editModel: string = '';
  @Local selectedModelIndex: number = 0;   // 下拉选中索引
  @Local isDropdownOpen: boolean = false;   // 下拉面板展开状态

  aboutToAppear() {
    // 初始化编辑副本
    this.editKey = this.apiConfig.apiKey;
    this.editEndpoint = this.apiConfig.endpoint;
    this.editModel = this.apiConfig.model;

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
  }

  build() {
    NavDestination() {
      Column() {
        // API Key 输入
        Column() {
          Text('API Key')
            .fontSize(14)
            .fontColor('#666')
            .margin({ bottom: 6 })
          TextInput({ text: $$this.editKey, placeholder: '填入火山方舟 API Key' })
            .width('100%')
            .height(48)
            .fontSize(14)
            .fontColor('#333333')
            .placeholderColor('#666666')
            .borderRadius(8)
            .backgroundColor('#F5F5F5')
        }
        .width('100%')
        .margin({ bottom: 16 })

        // Endpoint 输入
        Column() {
          Text('Endpoint')
            .fontSize(14)
            .fontColor('#666')
            .margin({ bottom: 6 })
          TextInput({ text: $$this.editEndpoint, placeholder: 'API 地址' })
            .width('100%')
            .height(48)
            .fontSize(14)
            .fontColor('#333333')
            .placeholderColor('#666666')
            .borderRadius(8)
            .backgroundColor('#F5F5F5')
        }
        .width('100%')
        .margin({ bottom: 16 })

        // Model 下拉选择
        Column() {
          Text('Model')
            .fontSize(14)
            .fontColor('#666')
            .margin({ bottom: 6 })

          // 下拉触发器：显示当前选中模型名称 + 箭头
          Row() {
            Text(MODEL_LIST[this.selectedModelIndex].name)
              .fontSize(14)
              .fontColor('#333333')
              .layoutWeight(1)
            Text(this.isDropdownOpen ? '▲' : '▼')
              .fontSize(12)
              .fontColor('#999')
          }
          .width('100%')
          .height(48)
          .borderRadius(8)
          .backgroundColor('#F5F5F5')
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
                    .fontColor('#333333')
                  // 小字：类型 + 价格
                  Text(`${model.type} · ${model.price}`)
                    .fontSize(12)
                    .fontColor('#999')
                    .margin({ top: 2 })
                }
                .width('100%')
                .padding(12)
                .backgroundColor(index === this.selectedModelIndex ? '#E3F2FD' : '#FFFFFF')
                .onClick(() => {
                  this.selectedModelIndex = index;
                  this.editModel = model.id;
                  this.isDropdownOpen = false;
                })
              }, (model: ModelOption) => model.id)
            }
            .width('100%')
            .borderRadius(8)
            .backgroundColor('#FFFFFF')
            .border({ width: 1, color: '#E0E0E0' })
            .margin({ top: 4 })
          }

          // 提示：模型 ID 说明
          Text('⚠️ 控制台展示名称≠API调用ID，预置模型示例：doubao-seed-2-1-lite-260915；数字之间是短横线`-`，禁止小数点，直接复制上表ID使用。')
            .fontSize(11)
            .fontColor('#999')
            .margin({ top: 4 })
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
            console.info('[SettingsPage] API config saved');
            this.pathStack.pop();
          })
      }
      .width('100%')
      .height('100%')
      .padding(16)
    }
    .title('API 配置')
  }
}
