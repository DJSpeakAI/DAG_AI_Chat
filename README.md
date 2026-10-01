# DAG AI Chat — 气泡树 AI 对话应用

> **版本：0.1 (MVP)**  
> 鸿蒙 HarmonyOS ArkUI V2 气泡树多分支 AI 对话应用，接入火山方舟大模型 API，支持流式对话、多模态图片上传、对话树可视化与本地持久化。

---

## 一、项目概述

DAG AI Chat 是一款基于鸿蒙 HarmonyOS ArkUI V2 的 AI 对话应用，核心创新点是将传统线性对话升级为**气泡树（Bubble Tree）**结构，用户可以在任意对话节点分叉出新的对话分支，实现多路探索式 AI 交互。

### 核心能力

| 能力 | 说明 |
|------|------|
| 🌳 气泡树对话 | 对话以树形 DAG 结构组织，支持任意节点分叉子气泡 |
| 🎨 画布可视化 | Canvas 绘制气泡节点 + 父子连线，支持拖拽布局 |
| 💬 流式对话 | 接入火山方舟 API，SSE 流式实时返回 AI 回复 |
| 🖼️ 多模态图片 | 支持相册多选图片，Base64 内联发送给多模态模型 |
| 🖼️ 图片全屏预览 | 点击图片全屏浏览，支持左右滑动、双指缩放、右滑关闭 |
| ⏳ 加载/错误状态 | 占位气泡「AI正在回复中...」+ 错误气泡提示 |
| 💾 本地持久化 | 对话树 JSON 序列化存储到应用沙盒 |
| 📝 Markdown 渲染 | AI 回复支持代码块、表格等 Markdown 格式 |
| 🔄 代码块自动换行 | 代码块上方按钮切换换行/横向滚动，默认换行 |
| 📏 输入框自适应 | ≤5 行自适应高度，>5 行内部滚动 |
| 🔗 DAG 链路回溯 | 从当前气泡沿 parentID 回溯构建完整对话上下文 |
| 📦 上下文压缩 | 超 25 条消息自动生成摘要，滑动窗口压缩历史 |
| 🌓 深浅色主题 | 跟随系统深浅色切换，全页面适配 |
| 🔧 API 配置 | 设置页配置 API Key / Endpoint / Model，内置 5 个预置模型 |

---

## 二、技术栈

| 技术 | 说明 |
|------|------|
| 语言 | ArkTS（TypeScript 超集） |
| UI 框架 | ArkUI V2（@ComponentV2 / @ObservedV2 / @Trace） |
| 状态管理 | AppStorageV2 + PersistenceV2 + @Local + @Computed |
| 网络 | @kit.NetworkKit（http SSE 流式请求） |
| 文件 | @kit.CoreFileKit（沙盒 JSON 持久化） |
| 相册 | @kit.MediaLibraryKit（photoAccessHelper 图片选择） |
| API | 火山方舟 OpenAI 兼容接口 v3 |
| 构建 | hvigor |
| 设备 | phone / tablet / 2in1 |

---

## 三、项目目录结构

```
DAG_AI_Chat/
├── AppScope/
│   └── app.json5                          # 应用全局配置（bundleName、版本）
├── entry/
│   └── src/main/
│   ├── ets/
│   │   ├── pages/
│   │   │   └── Index.ets              # 首页入口（Navigation 导航）
│   │   ├── components/
│   │   │   ├── BBTreeCanvas.ets       # 气泡树画布（Canvas 绘制 + 拖拽 + 连线）
│   │   │   ├── ChatPage.ets           # 对话页面（消息列表 + 输入 + 图片 + 流式）
│   │   │   └── SettingsPage.ets       # 设置页面（API 配置 + 模型选择 + 诊断）
│   │   ├── common/
│   │   │   └── ChatModel.ets          # 数据模型（ChatMessage / BubbleNode / BubbleTree / 序列化 / PersistenceV2 持久化）
│   │   ├── utils/
│   │   │   └── ApiClient.ets          # API 客户端（SSE 流式 + 多模态 + 诊断测试）
│   │   ├── entryability/
│   │   │   └── EntryAbility.ets       # 入口 Ability（含全局 ThemeStore 深浅色）
│   │   └── entrybackupability/
│   │       └── EntryBackupAbility.ets # 备份恢复扩展 Ability
│   ├── resources/
│   │   └── base/
│   │       ├── profile/
│   │       │   ├── main_pages.json    # 页面路由配置
│   │       ├── element/
│   │       │   ├── string.json        # 字符串资源
│   │       │   └── color.json         # 颜色资源
│   │       └── media/                 # 图标资源
│   └── module.json5                   # 模块配置（权限、设备类型）
├── docs/                                  # 版本文档（0.40 ~ 0.131）
├── build-profile.json5                    # 构建配置（签名、SDK 版本）
├── oh-package.json5                       # 依赖管理
└── hvigorfile.ts                          # hvigor 构建任务
```

---

## 四、核心数据模型

### ChatMessage — 单条对话消息
```typescript
@ObservedV2
export class ChatMessage {
  @Trace messageId: string;       // 唯一消息 ID
  @Trace role: ChatRole;          // 'user' | 'assistant'
  @Trace content: string;         // 文字内容
  @Trace imageUrl: string[];      // 图片 URL 数组（Base64 内联），空数组=无图片
}
```

### BubbleNode — 气泡节点（对话树节点）
```typescript
@ObservedV2
export class BubbleNode {
  @Trace nodeID: string;          // 节点 ID
  @Trace parentID: string | null; // 父节点 ID（根节点为 null）
  @Trace messages: ChatMessage[]; // 该节点下的消息列表
  @Trace x: number;               // 画布 x 坐标
  @Trace y: number;               // 画布 y 坐标
  @Trace parentX: number;         // 父节点 x（冗余存储）
  @Trace parentY: number;         // 父节点 y
}
```

### BubbleTree — 气泡树
```typescript
@ObservedV2
export class BubbleTree {
  @Trace nodeList: BubbleNode[];  // 所有节点
}
```

### ApiConfig — API 配置
```typescript
@ObservedV2
export class ApiConfig {
  @Trace apiKey: string;          // 火山方舟 API Key
  @Trace endpoint: string;        // API Endpoint URL
  @Trace model: string;           // 模型 ID
}
```

---

## 五、功能详解

### 5.1 气泡树画布（BBTreeCanvas.ets）
- Canvas 绘制气泡节点（圆角矩形 + 文字预览）
- 父子节点之间绘制贝塞尔曲线连线
- 手势拖拽节点，实时更新坐标
- 点击节点切换当前对话气泡
- 「+」按钮在当前节点下新增子气泡

### 5.2 对话页面（ChatPage.ets）
- 消息列表：用户消息蓝色气泡 / AI 消息灰色气泡
- 用户气泡支持文字 + 图片缩略图同时展示
- 流式对话：SSE 实时追加 AI 回复内容
- 加载占位：发送后 AI 气泡显示「AI正在回复中，请稍候...」
- 错误提示：请求失败显示「请求出错，请检查网络/API配置」
- 图片选择：📷 按钮 → 相册多选 → Base64 → 预览 → 发送
- 发送按钮置灰防重复点击
- 消息删除：× 按钮单条删除

### 5.3 API 客户端（ApiClient.ets）
- 火山方舟 OpenAI 兼容接口 v3
- SSE 流式解析（parseSSEChunk）
- 多模态请求体构造（content 数组格式）
- 全链路诊断日志（请求构建 → 发送 → 数据接收 → SSE 解析 → 错误）
- `testApiWithDiagnostics` 诊断测试函数
- `StreamController` 支持手动取消请求

### 5.4 设置页面（SettingsPage.ets）
- API Key 输入（脱敏显示）
- Endpoint URL 输入
- 模型下拉选择（5 个预置模型）
- 「测试」按钮一键诊断 API 连通性
- 诊断结果直接显示在消息气泡中

### 5.5 预置模型列表

| 显示名称 | API Model ID | 类型 |
|----------|-------------|------|
| Doubao-Seed-2.1-lite | `doubao-seed-2-1-lite-260915` | 纯文本 |
| DeepSeek-V4.1-Flash | `deepseek-v4-1-flash-260910` | 多模态 |
| GLM-5.3-Flash | `glm-5-3-flash-260828` | 多模态 |
| DeepSeek-V4-Pro正式版 | `deepseek-v4-pro-260425` | 纯文本 |
| DeepSeek-V4-Flash正式版 | `deepseek-v4-flash-260425` | 纯文本 |

### 5.6 本地持久化（ChatModel.ets + PersistenceV2）
- `serializeBubbleTree`：响应式树 → 纯对象（剥离 @ObservedV2 代理）→ JSON 字符串
- `deserializeBubbleTree`：JSON 字符串 → 重建响应式 BubbleTree（启动时由 Index 恢复）
- 持久化载体：PersistenceV2 存储单一 JSON 字符串（`PersistData.bubbleTreeJson`），坐标/消息变更即写回
- 版本字段支持后续数据结构迁移（`historySummary` 等字段带 `??` 兜底）

---

## 六、多模态请求格式

### 纯文本消息
```json
{
  "model": "doubao-seed-2-1-lite-260915",
  "messages": [{ "role": "user", "content": "你好" }],
  "stream": true
}
```

### 多模态消息（文字 + 图片）
```json
{
  "model": "deepseek-v4-1-flash-260910",
  "messages": [{
    "role": "user",
    "content": [
      { "type": "text", "text": "描述这张图片" },
      { "type": "image_url", "image_url": { "url": "data:image/jpeg;base64,..." } }
    ]
  }],
  "stream": true
}
```

---

## 七、状态管理架构

```
AppStorageV2（全局响应式存储）
├── BubbleTree ('bubble-tree')        # 气泡树数据
├── CurrentBubble ('current-bubble')  # 当前选中气泡 ID
└── ApiConfig ('api-config')          # API 配置（PersistenceV2 持久化）

@ComponentV2 组件内
├── @Local                            # 组件局部状态（inputText, isLoading, pendingImages）
├── @Computed                         # 计算属性（currentBubbleId, currentBubble, currentMessages）
├── @Param                            # 父组件传参（pathStack）
└── @ObservedV2 + @Trace              # 深度响应式（ChatMessage, BubbleNode, BubbleTree）
```

---

## 八、版本历史

| 版本 | 说明 |
|------|------|
| 0.1 (MVP) | 气泡树对话 + 火山方舟流式 API + 多模态图片 + 加载/错误状态 + 本地持久化 + 画布拖拽 |
| 0.40 | 修复模型名大小写 404 问题 |
| 0.41 | 修正 5 个预置模型 API Model ID |
| 0.42 | 新增加载占位气泡 + 错误气泡 + 多模态图片上传 |
| 0.114 | 图片显示优化 + 全屏浏览（左右滑动、双指缩放） |
| 0.115 | 图片全屏预览交互优化（右滑关闭、点击关闭） |
| 0.116 | 输入框多行自适应（≤5 行自适应，>5 行内部滚动） |
| 0.117 | DAG 链路回溯 + 滑动窗口上下文压缩（超 25 条自动摘要） |
| 0.118 | 输入框动态高度优化 |
| 0.121 | AI 回复 Markdown 渲染（代码块、表格） |
| 0.122 | 代码块自动换行按钮 + 代码清理（删除死代码、未使用导入） |
| 0.123 | 气泡树画布深浅色适配 + 阴影 + 高亮连线 |
| 0.124 | 纵向树形自动排版 + 「显示全部」按钮 |
| 0.126 | fitViewport 自动缩放 + 画布裁剪（clip） |
| 0.130 | fitViewport 重构：以画布真实尺寸居中（「显示全部」+ 清零默认节点位置修复） |
| 0.131 | 全项目代码清理：弃用 API 迁移（headersReceive / UIContext.showAlertDialog / focusControl）+ 默认模型对齐 + 首页/设置页深浅色补齐 + 显示全部按钮右缘自适应 |

---

## 九、运行环境

- **IDE**：DevEco Studio
- **SDK**：HarmonyOS API 12+
- **设备**：phone / tablet / 2in1
- **签名**：默认 debug 签名配置

---

## 十、快速开始

1. 用 DevEco Studio 打开项目
2. 在设置页填入火山方舟 API Key
3. 选择预置模型（推荐 `Doubao-Seed-2.1-lite`）
4. 点击「测试」验证 API 连通性
5. 开始对话，在气泡树上探索多分支对话
