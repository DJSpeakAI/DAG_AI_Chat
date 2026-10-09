# AGC 云函数 track-events 部署指引（最终版）

> 2026-10-07 全链路竣工实录。本文档 = 日常改代码流程 + 从零重建手册 + 踩坑档案。
> 本地工作目录：`E:\track-events\`（在 git 仓库外——**含凭证文件，绝不入 git**）

## 架构总览

```
Pad（TrackUtil.ets 攒批/回前台补发）
  → cloud.callFunction('track-events', {events: JSON串})
  → AGC 云函数 track-events（函数包 + 依赖层 cloud-server-deps + 凭证）
  → Cloud DB 存储区 default / 对象类型 events（upsert 幂等）
  → AGC 控制台「数据管理」查看 / 导出
```

## 本地文件（E:\track-events\）

| 文件 | 用途 |
|------|------|
| `handler.js` | 云函数代码（唯一需要改的文件） |
| `package.json` | 依赖声明（@hw-agconnect/cloud-server@1.0.5） |
| `agc-credential.json` | **项目级凭证**（含 client_secret，绝不入 git/外传） |
| `node_modules\` | 依赖实体（打层包用） |
| `build-zip.ps1` | 一键重打包脚本 |

## 日常改代码流程（1 分钟）

1. 改 `E:\track-events\handler.js`
2. PowerShell：`E:\track-events\build-zip.ps1`（只重打函数包；加 `-layer` 参数连层包一起重打——只在增删依赖时需要）
3. 本地冒烟（可选但推荐，凭证在本地可直连华为云真写库）：
   ```powershell
   cd E:\track-events
   node -e "const h=require('./handler.js').myHandler; h({events:[{e:'smoke',p:'',t:Date.now()}]},{},r=>{console.log(JSON.stringify(r));process.exit(0)},{info:console.log,warn:console.warn,error:console.error})"
   ```
4. AGC 控制台 → track-events → 函数代码 → 上传 `E:\track-events-deploy.zip` → **提交**
5. 测试面板贴：`{"events":[{"e":"zip_test","p":"","t":1}]}` 验证

## 从零重建手册（换账号/换正式应用时）

### ① Cloud DB 表
- 控制台 → 云开发 → Cloud DB → 对象类型 → 新建 `events`：
  | 字段 | 类型 | 主键 | 非空 |
  |------|------|------|------|
  | e | String | ✓ | ✓ |
  | p | String | | |
  | t | **Long** | ✓ | ✓ |
- 存储 → 新建存储区 `default`
- **t 必须 Long**：Integer 是 32 位装不下 13 位毫秒时间戳（报 3007007 out of range）

### ② 依赖层（解决 Cannot find module）
- 云函数主界面 → 「层」页签 → 创建层：
  - 名称 `cloud-server-deps`、兼容运行时 **nodejs**、上传 `E:\node-modules-layer.zip`（`build-zip.ps1 -layer` 产出）
- **机制**：函数运行目录是 `/dcache/layer/func/`，层解压到 `/dcache/layer/`——Node 向上找一层命中 `node_modules`。**函数 zip 里的 node_modules 会被平台无视**（坑 #3）

### ③ 凭证
- AGC 控制台 → **项目设置 → 「Server SDK」页签** → 认证凭据 → 创建 → 下载
- 得到 `agc-apiclient-xxx.json` → 复制到 `E:\track-events\` 并改名 `agc-credential.json`
- handler.js 里 `cloud.createInstance(__dirname+'/agc-credential.json', 'trackEvents', Region.REGION_CN)`

### ④ 函数
- 创建函数：名称 `track-events`（**仅小写/数字/中划线**，trackEvents 会被拒）、入口 `handler.myHandler`、运行时 nodejs、代码输入类型 **.zip 文件** 上传 `E:\track-events-deploy.zip`
- 层配置 Tab → 绑定层 `cloud-server-deps` v1
- 测试面板验证 `TE wrote n=1`

### ⑤ 写库要点（CloudDBZoneGenericObject）
- `collection.upsert(普通对象)` 不带主键标记 → 服务端报 **3037003 缺主键**
- 必须用 `CloudDBZoneGenericObject.build('events')` + `addFieldValue(字段, 值, isPrimaryKey)`（它在 `database-service/request/` 下导出）
- `collection('events')` 用字符串集合名即可

## 踩坑档案（六座山，血泪实录）

| # | 现象 | 真相 |
|---|------|------|
| 1 | 提交代码不生效、测试面板转圈、Cloud DB 导出失败 | **浏览器无痕模式**——提交静默不保存（不报错！）。一切 AGC 后台操作必须用**非无痕窗口** |
| 2 | @@Start→@@End 2ms 无用户日志 | 函数跑的是空模板（#1 的后果）；另在线编辑器不内置 cloud-server 依赖 |
| 3 | zip 传了 node_modules 仍 Cannot find module | ①PS5.1 Compress-Archive 条目用反斜杠（Linux 解压毁目录结构）②**平台本就无视函数包内 node_modules，依赖必须走层** |
| 4 | Please create instance with path or AGC_CONFIG | SDK 需项目级凭证：Server SDK 页签下载 + `cloud.createInstance()` |
| 5 | 3037003 缺主键 | plain object 路径不标记主键，必须 CloudDBZoneGenericObject.addFieldValue(…, true) |
| 6 | 3007007 data out of range | 表字段 Integer(32位) 装不下毫秒时间戳 → 改 Long |

## 数据查看

- AGC 控制台 → 云开发（Serverless）→ **Cloud DB → 数据管理** → 存储区 `default` → 对象类型 `events`
- 字段含义见 **docs/埋点字典.md**（事件 ID ↔ 中文按钮对照）
- 导出：数据管理页导出 CSV → Excel 分析
