# DAG AI Chat — 气泡树多分支 AI 对话工具

> **版本：0.16 (MVP 持续迭代)**  
> 鸿蒙 HarmonyOS ArkUI V2 原生应用，气泡树（DAG）多分支 AI 对话，接入火山方舟大模型 API。

---

## 项目介绍

DAG AI Chat 是基于鸿蒙 ArkUI V2 开发的原生 AI 对话应用，核心创新是**气泡树（DAG 有向无环图）对话模型**，打破普通 AI 聊天只能单线对话的限制。

传统对话是一条直线，每次提问只能沿着当前上下文继续；在 DAG AI Chat 中，你可以在任意气泡节点分叉，衍生多条独立对话分支，并行探索不同思路、不同提问角度，非常适合自学、数学推演、代码调试、知识拆解等深度思考场景。

## ✨ 核心特性

- 🌳 **DAG 气泡树对话**：任意对话节点新建分支，多路并行探索 AI，保留全部思考脉络
- 🖼️ **Canvas 可视化画布**：图形化查看整棵对话树，支持节点拖拽、双指捏合缩放、选中气泡高亮
- 💬 **气泡自定义标题**：节点自动提取首句问题做预览，支持手动重命名气泡，快速识别每一段对话主题
- 💾 **本地持久化**：对话气泡树保存在本机，无网络也可以完整使用 App 全部基础能力
- 📱 **鸿蒙原生开发**，同时适配鸿蒙手机、鸿蒙 PC

## 💰 商业化说明

本项目所有本地功能永久免费，离线可用，不强制登录。

【多端云同步】为可选增值订阅服务：新用户享有 30 天免费试用；包月 9.9 元，年费 99 元。

订阅到期仅暂停云端同步，设备本地所有对话、气泡数据完整保留，不会删除。

云同步仅支持华为账号登录，不接入微信、手机号等第三方登录。

## 🎯 适合人群

深度自学者、数学 / 理科学习者、程序员、知识整理爱好者。

适合一边和 AI 对话，一边分叉验证不同猜想，沉淀成个人知识库。

## ⚠️ 当前状态

MVP 持续迭代开发中。目前已实现画布、分支对话、本地存储、主题深浅色跟随、气泡标题等基础能力；云同步功能为后续迭代模块。

---

## 一、技术栈

| 技术 | 说明 |
|------|------|
| 语言 | ArkTS（TypeScript 超集） |
| UI 框架 | ArkUI V2（@ComponentV2 / @ObservedV2 / @Trace） |
| 状态管理 | AppStorageV2 + PersistenceV2 + @Local + @Computed |
| 网络 | @kit.NetworkKit（http SSE 流式请求 + TTS 合成） |
| 文件 | @kit.CoreFileKit（沙盒 JSON 持久化 + TTS 音频临时文件） |
| 相册 | @kit.MediaLibraryKit（photoAccessHelper 图片选择） |
| 媒体 | @kit.MediaKit（AVPlayer 音频播放，TTS 朗读） |
| API | 火山方舟 OpenAI 兼容接口 v3 + openspeech 语音合成 2.0 |
| 构建 | hvigor |
| 设备 | phone / tablet / 2in1 |

---

## 二、项目目录结构

```
DAG_AI_Chat/
├── AppScope/
│   └── app.json5                          # 应用全局配置（bundleName、版本）
├── entry/
│   └── src/main/
│       ├── ets/
│       │   ├── pages/
│       │   │   └── Index.ets              # 首页入口（Navigation 导航 + 持久化恢复）
│       │   ├── components/
│       │   │   ├── BBTreeCanvas.ets       # 气泡树画布（组件渲染 + 自动排版 + 视口适配 + 平铺/选项卡双模式）
│       │   │   ├── ChatPage.ets           # 对话页（消息列表 + 划词翻译 + TTS + 复习区 + 知识提炼弹窗）
│       │   │   ├── SettingsPage.ets       # 设置页（API 配置 + 模型选择 + 诊断）
│       │   │   ├── GlobalSettingsDialog.ets # 全局设置弹窗（API 配置 + AI 偏好 + 画布模式，0.150/0.151）
│       │   │   ├── WordBankPage.ets       # 单词库页（0.145）
│       │   │   ├── KnowledgeBankPage.ets  # 知识库页（0.146）
│       │   │   └── AnnotationPage.ets     # 屏幕圈选标注页（0.152）
│       │   ├── common/
│       │   │   ├── ChatModel.ets          # 对话数据模型（ChatMessage / BubbleNode / 序列化 / Tab 森林）
│       │   │   ├── WordModel.ets          # 单词库数据模型（0.145）
│       │   │   ├── KnowledgeModel.ets     # 知识库数据模型（0.146）
│       │   │   └── AnnotationModel.ets    # 标注数据模型（0.152）
│       │   ├── utils/
│       │   │   ├── ApiClient.ets          # API 客户端（SSE 流式 + 查词 + 知识提炼 + TTS 合成）
│       │   │   ├── WordStoreUtil.ets      # 单词库持久化操作（0.145）
│       │   │   ├── KnowledgeStoreUtil.ets # 知识库持久化操作（0.146）
│       │   │   ├── WordSpeaker.ets        # 单词发音 TTS 单例（0.149）
│       │   │   ├── MathRender.ets         # LaTeX 数学符号本地渲染（0.151）
│       │   │   └── SyntaxHighlight.ets    # 代码块语法高亮（0.149）
│       │   ├── entryability/
│       │   │   └── EntryAbility.ets       # 入口 Ability（全局 ThemeStore 深浅色 + AppLifecycleStore 前后台标志）
│       │   └── entrybackupability/
│       │       └── EntryBackupAbility.ets # 备份恢复扩展 Ability
│       ├── resources/
│       │   └── base/                      # 资源（profile / element / media）
│       └── module.json5                   # 模块配置（权限、设备类型）
├── docs/                                  # 版本迭代文档
├── build-profile.json5                    # 构建配置（签名、SDK 版本）
├── oh-package.json5                       # 依赖管理
└── hvigorfile.ts                          # hvigor 构建任务
```

---

## 三、核心数据模型

### ChatMessage — 单条对话消息
```typescript
@ObservedV2
export class ChatMessage {
  @Trace messageId: string;       // 唯一消息 ID
  @Trace role: ChatRole;          // 'user' | 'assistant' | 'system'
  @Trace content: string;         // 文字内容
  @Trace imageUrl: string[];      // 图片 URL 数组（Base64 内联），空数组=无图片
  @Trace inputTokens: number;     // 输入 token 数
  @Trace outputTokens: number;    // 输出 token 数
  @Trace isPodcastMode: boolean;  // 播客模式标记（0.133）
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
  @Trace historySummary: string;          // 分支链路摘要（0.117）
  @Trace historySummaryCount: number;     // 摘要生成时的消息总数（0.117）
  @Trace nodeTitle: string;       // 节点标题：空=自动取首句，非空=手动覆盖（0.147）
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
  @Trace apiKey: string;          // 火山方舟 API Key（对话）
  @Trace endpoint: string;        // 对话 API Endpoint
  @Trace model: string;           // 对话模型 ID
  @Trace audioModel: string;      // TTS 模型资源 ID（0.139）
  @Trace audioVoice: string;      // TTS 音色 ID（0.139）
  @Trace audioEndpoint: string;   // TTS 端点（openspeech，与对话端点独立）
  @Trace audioKey: string;        // TTS 专用 Key（0.140，与对话 Key 相互独立）
}
```

---

## 四、功能详解

### 4.1 气泡树画布（BBTreeCanvas.ets）
- 圆角矩形气泡组件（节点标题 + 消息计数，0.147）
- 父子连线（直线组件，选中分支橙色高亮）
- 双击气泡进入对话页；长按弹操作菜单（修改标题 / 删除）
- 纵向树形自动排版 + 「显示全部」视口自适应
- 画布平移 + 双指缩放

### 4.2 对话页面（ChatPage.ets）
- 流式对话：SSE 实时追加 AI 回复（打字机效果）
- Markdown 渲染：代码块（换行/横滚切换 + 放大弹窗）、表格（放大 + 换行切换）、语法高亮（0.149）
- LaTeX 数学符号本地渲染（0.151/0.152：\frac、\sqrt、上下标、pmatrix 矩阵等）
- 划词翻译：自定义选词工具栏（翻译 / 入知识库 / 删除 / 复制 / 全选），屏蔽系统菜单
- 单词入库 + AI 气泡底部生词复习区（随机 2 词）
- 知识卡片提炼 + AI 气泡底部知识复习区
- 提炼弹窗体验优化（0.153）：秒表计时、180s 业务超时、切后台自动中断、异常三分类中文提示、保存按钮状态规则、流式实时填充
- TTS 朗读：AI 回复分段语音合成播放；单词发音三处共用单例（0.149）
- 回复长度选择（短/中/长）+ 播客模式
- 多模态图片：相册多选 → Base64 → 全屏预览（滑动/缩放/右滑关闭）
- 屏幕圈选标注 → 截图入知识库（多模态提炼，0.152）
- 消息删除防误触（首次确认 + 「不再提示」勾选）

### 4.3 API 客户端（ApiClient.ets）
- streamChat：火山方舟 OpenAI 兼容 v3，SSE 流式解析
- queryWord / queryKnowledge：复用流式请求累积全文，严格 JSON 解析；支持 onPartial 流式部分字段回调（0.153）
- synthesizeTTS：openspeech 语音合成 2.0，HTTP 分段请求
- StreamController 支持手动取消
- 数据卫生：TTS 调试遗留消息不进入 LLM 上下文

### 4.4 设置页面（SettingsPage.ets）
- 对话配置：API Key（脱敏）/ Endpoint / 模型下拉（5 个预置模型）
- 音频配置：TTS Key / 模型资源 ID / 音色（0.139/0.140）
- 「测试」按钮一键诊断 API 连通性

### 4.5 预置模型列表

| 显示名称 | API Model ID | 类型 |
|----------|-------------|------|
| Doubao-Seed-2.1-lite | `doubao-seed-2-1-lite-260915` | 纯文本 |
| DeepSeek-V4.1-Flash | `deepseek-v4-1-flash-260910` | 多模态 |
| GLM-5.3-Flash | `glm-5-3-flash-260828` | 多模态 |
| DeepSeek-V4-Pro正式版 | `deepseek-v4-pro-260425` | 纯文本 |
| DeepSeek-V4-Flash正式版 | `deepseek-v4-flash-260425` | 纯文本 |

### 4.6 本地持久化（PersistenceV2 多 key 隔离）

| Key | 内容 |
|-----|------|
| `persist-data` | 气泡树 JSON（`serializeBubbleTree` / `deserializeBubbleTree`，可选字段 `??` 兜底兼容旧数据） |
| `api-config-v2` | API 配置（0.143 换 key 迁移修复新增属性不落盘，工厂函数内自动迁移旧 `api-config`） |
| `ai-preference-v1` | AI 偏好（称呼 / 鼓励开关，0.150） |
| `canvas-mode-v1` | 画布模式（平铺 / 选项卡，0.151） |
| `tab-forest-v1` | 选项卡模式 Tab 森林（0.151） |
| `canvas-interop-v1` | 画布互操作标志（0.151） |
| `annotation-pref-v1` | 标注首次提示 flag（0.152） |
| `word-bank` | 单词库（独立持久化，0.145） |
| `knowledge-bank` | 知识库（独立持久化，0.146） |

---

## 五、多模态请求格式

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

## 六、状态管理架构

```
AppStorageV2（全局响应式存储）
├── BubbleTree ('bubble-tree')        # 气泡树数据
├── CurrentBubble ('current-bubble')  # 当前选中气泡 ID + 坐标
├── ThemeStore ('theme-store')        # 深浅色主题
└── AppLifecycleStore ('app-lifecycle')  # 前后台标志（0.153，切后台中断提炼）

PersistenceV2（磁盘持久化）
├── PersistData ('persist-data')      # 气泡树 JSON 字符串
├── ApiConfig ('api-config-v2')       # API 配置（工厂函数内迁移旧 key 数据）
├── AiPreference ('ai-preference-v1') # AI 偏好
├── CanvasModeStore ('canvas-mode-v1') / TabForestStore ('tab-forest-v1')  # 画布模式 / Tab 森林
├── AnnotationPrefStore ('annotation-pref-v1')  # 标注首次提示 flag
├── WordBankStore ('word-bank')       # 单词库
└── KnowledgeBankStore ('knowledge-bank')  # 知识库

@ComponentV2 组件内
├── @Local                            # 组件局部状态
├── @Computed                         # 计算属性
├── @Monitor                          # 状态变化监听（如切后台中断提炼）
├── @Param                            # 父组件传参（pathStack）
└── @ObservedV2 + @Trace              # 深度响应式（ChatMessage, BubbleNode, BubbleTree）
```

---

## 七、运行环境

- **IDE**：DevEco Studio
- **SDK**：HarmonyOS NEXT（compatibleSdkVersion 6.1.1，API 24+；targetSdkVersion 26.0.0）
- **设备**：phone / tablet / 2in1
- **签名**：默认 debug 签名配置

---

## 八、快速开始

1. 用 DevEco Studio 打开项目
2. 在设置页填入火山方舟 API Key（对话）
3. 选择预置模型（推荐 `Doubao-Seed-2.1-lite`）
4. 点击「测试」验证 API 连通性
5. 开始对话，在气泡树上探索多分支对话

> 版本迭代历史已迁至根目录 `MEMORY.md`（迭代记录章节）。
