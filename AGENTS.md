# AGENTS.md — DAG AI Chat 项目 AI 协作规则（所有 AI 工具通用）

## 强制第一步
任何任务开始前，先读五文档对齐基线（★ 2026-10-21 起五文档制）：
1. project_rule.md（全局开发规则）
2. MEMORY.md（项目基线+迭代记录，**★ 2026-10-22 起为活规则层 ≤20KB——迭代记录一行制，追加前先 `wc -c` 量体积，超 20KB=治理信号**；历史迭代全量在 docs/MEMORY_HISTORY.md，默认不读、查历史 grep 版本号定位）
3. docs/CONTEXT_MANAGEMENT.md（上下文纪律）
4. **AOCI_INDEX.md（★ 项目认知索引：63 个源码文件的 F/R/A/S 条目——F 干什么/R 连带看什么/A 契约/S 血泪教训。改任何源码前必读其条目，按行号区段精读，禁止无导航整读大文件；改完收尾刷新受影响条目）**
5. （上下文仍有余力时）UI_GUIDELINES.md——UI 改动任务必读

## 开发铁律（摘要，细节以 project_rule.md 为准）
- 技术栈：鸿蒙 ArkUI V2 + @ObservedV2/@Trace；禁止混用 V1 老语法
- 数据 Schema 字段只许尾部追加+默认值，禁止改名/改类型/删除（数据安全第一）
- PersistenceV2/AppStorageV2 的 key 一律禁改
- 发版版本号三处同步：AppScope/app.json5 + Index.ets + GlobalSettingsDialog.ets；versionCode 每版 +1
- 收尾五件套：MEMORY.md 迭代记录 / 桌面清理 / git push 降级链（GitHub 主通道）/ 版本号三处同步 / **AOCI_INDEX.md 受影响条目刷新（★ 2026-10-21 起）**
- 一任务一会话：任务完成即收尾，bug 修复新开会话

## 止损熔断（强制，防死循环烧资源）
同一 bug 出现以下任一情况，立即停止修改，产出「死胡同报告.md」（放桌面）：
1. 连续 3 轮修改+编译仍未解决
2. 同一处代码第 2 次改回原样
3. 修改范围超出原始 bug（≥3 文件或开始重构式改动）
4. 编译报错数连续 2 轮不降反升
死胡同报告五部分：①环境与现象 ②相关代码骨架 ③已实锤证据 ④已试方案+死因表 ⑤怀疑方向。
报告产出后必须停手，等人工决定下一步。

## 红线（禁改，改动须转人工）
数据模型 Schema / CloudSyncUtil.ets / BackupUtil.ets / 持久化 key / signing/ / module.json5 / 测试台 testing/console/（用户明确指派的测试台迭代除外——闭环 CLI 仍禁改 testing/，防改考卷骗绿）

## 其他
- 未经用户明确要求不执行 git commit
- 桌面「测试台.html」是副本禁手改（正本 testing/console/）；桌面「埋点看板.html」禁删
- 自动修复闭环（测试台 autofix）CLI 一律走官方 deveco/GLM-5.3 通道（阿里 token 计划网关流式 JSON 截断，勿切回）
- 全程简体中文