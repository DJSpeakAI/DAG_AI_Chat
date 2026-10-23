// ============================================================
// testing/console/server.js — 0.229.26 UI 规范审计套件（ui-audit：A 类页面巡检 + B 类弹窗体系）
// 架构：桌面/浏览器 HTML → 本服务(127.0.0.1:8766) → spawn hdc → Pad/PC/手机
//
// 0.229.26 新增（评审定稿：DeepSeek 意见采纳——一期 ~24 断言族压缩为 3 用例承载；组件族=断言函数
//   （auditRules.js 独立引擎）+页面=执行单元（巡检一次 dump 多次断言）；里程碑=首份审计报告发现≥3 真实不一致）：
//   ①UI-CALIBRATE：dump 通道自检（fontSize/fontWeight dump 不可达实证如实报）+density 标定（边栏 240vp 锚）
//     +DesignTokens 版本锚定（新增常量报警不静默扩展——评审补充建议 1）
//   ②UI-AUDIT-PAGES：七页巡检（首页/气泡树/词库/知识库/复习/统计/账单）——A1 背景/A5 边栏/A11 色值白名单
//     /A15 热区 + 跨页一致性（边栏宽/背景色）；页面 dump 全量存 artifacts 供人工复核
//   ③UI-AUDIT-DIALOGS：弹窗体系审计（B1/B2 宽度断点 400/520/B4 双按钮等宽 48/B5 层级色/B9 返回键关闭
//     /B11 键盘适配/B13 删除确认链路）——触发全走真实路径；fresh 专属弹窗（协议/门禁/堆叠）skip 守卫
//   ④安全前置（0.228.0 数据 bug 未修期间）：跑 UI 审计前双端云同步已关（persistent_storage 落盘
//     enabled:false 实证）——墓碑链已断，UI 巡检零数据风险
//   ⑤审计≠修复：违规清单输出（fail/warn 分级+豁免裁决建议），修复走 app 独立迭代
//
// 0.229.25 新增（用户拍板"按专业测试做，先测后修，AI 盯屏全自动"——全案 docs/0.165+/0.229.25）：
//   ①SYNC-FLOW 编排套件（跨端数据链端到端）：UI 操作端(Pad，真实用户路径)产生数据 → settle 轮询 →
//     数据断言端(PC，sqlite 行数收敛)——四域各 1 条 + 删除传播（补 0.228.0 PENDING 遗留验证项①）。
//     与 SYNC-DOMAIN（静态快照比对）互补：SYNC-DOMAIN 双端一致的空库也能绿，SYNC-FLOW 验证"链路活不活"
//   ②新原语：uiLongPress（长按弹菜单）/ uiInputText（点输入框+注入文本）/ findNodeHintAll
//     （TextInput placeholder 落 attributes.hint，text 恒空）/ flowPrep（编排前置：操作端登录+同步活、
//     断言端剔除未登录）/ 断言端用例结束 aa force-stop 收窗（PC 外接屏遮挡缓解——窗口只在断言期间在场）
//   ③LOGIN-LOGOUT 测完自动登回（用户裁决"离开时保持登录"）：退出断言完成→点头像静默授权登回——
//     整个 login 矩阵收尾=已登录，下轮任意套件起点即已登录，覆盖装机后 LOGIN-KEEP 可真断言
//   ④LOGIN-KEEP 前置快照根治无脑 skip：/api/prep 装机前实录登录态（PREP_STATE）——
//     装机前已登录→装后必须已登录（丢失=fail 真红线）；装机前未登录→如实 skip（无从验证"保留"）
//   ⑤设备编排角色路由：canUiDump 设备=UI 操作端、其余=数据断言端（能力档案最小落地，缺端自适应 skip）
//
// 0.229.24 新增（用户 07:06 报告实锤两连败 + 用户定稿「对测试台的测试」工作法：测试台反馈 vs 设备实际逐字对照）：
//   ①findNodeBoundsAll + uiClickText opts.near 同列最近命中——修「协议弹窗勾选框误点首页底层同名控件→点中遮罩=
//     暂不同意→模态关闭→同意并继续找不到」两连败真凶（findNodeBounds 只取第一个命中的先天缺陷）
//   ②agreeDialogIfAny 同意后自动关「体验改进计划」引导（暂不加入）——0.226.0 同意后首弹，此前会挡住登录按钮点击
//   ③/api/dump?dev=pad——任意时刻读设备当前屏幕 dump（AI 盯屏通道：对测试台的测试=后台看屏幕 vs 测试台日志逐字对照）
//   ④LOGIN-AGREE 前置状态守卫：协议已同意态（无模态且首页勾选框不显示）= 前置不符，如实 skip 不虚构拦截断言
//   ⑤检查点文案基线对齐（用户核心痛点"没有显示器清楚"）：写明测试台已做什么、屏幕此刻该显示什么、你点哪一步
//   ⑥版本字符串统一 VERSION 常量（banner/health/报告头三处曾各自写死致 0.229.22/23 混报）
//
// 0.229.23 新增（用户 PAD 实测反馈"提示内容与设备实际表现完全不一样"+拍板"测试台必须与用户体验基线对齐"）：
//   ①LOGIN-AGREE 假绿根治——旧流程"先自动同意协议→再不勾选点登录→断言未登录"根本没触发门禁
//     （app 真实逻辑：全局同意后首页勾选框直接隐藏、点登录直接拉华为授权——Index.ets onHomeAccountClick
//      needsAgreement()=false 分支；"未登录"断言恒真=测了个寂寞）。修=复刻真实拒绝路径：
//     首启模态点「暂不同意」→ 未勾选点登录 → 断言拦截提示文案（PAD=红字"请先阅读并勾选同意下方协议"+抖动；
//     手机=协议弹窗重弹"同意并继续"）+ 仍停在未登录
//   ②LOGIN-HOME 死步骤修复——模态自动同意后首页勾选框已隐藏（真实行为），旧代码仍硬找勾选框必报
//     "定位失败请人工勾选" warn 误导用户介入；修=找到才点（PAD 拒绝路径后确实存在），找不到如实说明
//     "协议已同意·勾选框已隐藏·点登录直接放行"（与 app 真实状态一致，用户看描述即能对上设备）
//   ③旧服务盲区守卫（治本 0.229.17 事故：页面+服务同为旧版时 0.229.21 版本守卫无感知）——
//     启动时记正本 server.js 的 mtime，/api/health 实时比对磁盘正本；正本被更新（AI 改码/git 更新）
//     → stale:true → 前端 30s 轮询标红顶栏 + startRun 前置确认（"跑旧码测不到新逻辑"）
//   ④login 套件用例名+步骤日志全面基线对齐：每条用例写明【前置状态→真实步骤→预期表现】三要素
//
// 0.229.22 新增：/api/prep 装机链路删掉 coldStart 步骤——"装完弹一次（验收）+ 第一条用例又弹一次（隔离）"
//   连续两次弹合并为一次（首次启动由第一条用例完成）；单独【装机】不跑测试时想验证就手动点开 app。
//
// 0.229.21 新增：①agreeDialogIfAny 先点「我已阅读并同意」勾选再点「同意并继续」（用户截图实锤：未勾选时同意按钮禁用点不动——
//   0.229.19 直点灰按钮=真缺陷）②（前端）stopRun 404 时明确提示"服务是旧版本请重启"（用户撞 /api/stop 404 即因服务停在旧版未重启）
//   ③（前端）boot 比对 /api/health 服务版本 vs PAGE_VER，旧于页面立即提示重启——治本"旧服务跑新页面"全面错位
//   ④（前端）srvState 顶栏显示服务版本号；弹两次现象澄清=装机验收冷启+每用例隔离冷启各司其职（非 bug，连续两次属可优化冗余待用户拍板）
//
// 0.229.20 新增：①「停止测试」——/api/stop 设 abortRequested，executeMatrix 每条用例前检查、当前步骤跑完即停、
//   summary 标 aborted（"打开即执行中"根因=上一轮还在后台跑+无停止手段失控，非自动开跑——前端 startRun 仅挂在按钮上已实证）
//   ②autoLogout 入口隔离收尾：三入口用例末尾自动退出登录（用户"测完一条入口必须先退出才能测下一条"）
//   ③（前端）删【关闭服务】按钮（关页签 30s 自动停=主关闭路径，按钮冗余——用户拍板删）；打开页面若 running=知情 toast
//   ④（前端）问题报告头部加「接手 AI 判别框架」（先分清 app 代码问题 vs 测试台流程问题再动手）
//
// 0.229.19 新增：①uiClickText/findNodeBounds/agreeDialogIfAny UI 自动点击原语（dumpLayout 找文本控件 bounds→uitest uiInput click）
//   ②login 套件重构：协议模态自动同意+首页协议勾选/登录按钮自动点+协议门禁全自动+退出登录尽力自动；
//   人工仅保留华为系统授权页（系统级无法自动化）、边栏头像（无文字坐标不可靠）、设置多步导航（暂留）
//   ③新增 LOGIN-KEEP 覆盖安装登录态保留用例（覆盖模式专属）
//
// 0.229.18 修复三层：①bmUninstall 假成功（旧正则 /successfully|Uninstall/ 把 "Uninstall failed" 也判成功）→
//   改「有成功标志且无失败标志」+ 卸载前 force-stop；②/api/prep 卸载失败→中止安装（防旧数据残留假成功）；
//   ③（前端）开始测试时 fresh 模式自动先全新安装（模式下拉此前只对【装机】按钮生效，"从零"用例没真正从零）
//
// 0.229.17 新增：①readAppVersionCode()+EXPECTED_VC——装机版本核验期望值从 app.json5 自动跟读（JSON5 注释容忍正则），
//   读不到回退 config.expectedVersionCode；APP 发版自动跟上、永不误报（落实"版本跟 APP 走"）
//   ②runCase 用例级超时（config.caseTimeoutMs 默认 300s）——超时自动标失败、写明"超时中止已跳过"、继续后续用例（防傻等）
//
// 0.229.16 新增：前端「▶ 实时执行 / ✓ 结果」双 Tab（switchTab）+「● 执行中·最近活动 Xs 前」活动指示（>10s 黄、>30s 红）；跑测自动切实时、跑完自动切结果并加「新」徽章；server.js 无功能改动
//
// 0.229.15 新增：shutdown 支持 ?delay=ms（延迟关闭）+ /api/shutdown/cancel（页面回来取消）——
//   根除 0.229.14 首版"刷新也触发 pagehide→立即停服务"的误停：刷新后 boot 成功即取消，只有真关页签才 30s 后停
//
// 0.229.14 新增：①summarizeAaTest 重写——ResultCode 硬判 + [fail] 精确行 + 统计数值化（根除"failure: 0 被关键词误判成失败"的假失败）
//   ②（前端）pagehide + sendBeacon 关页签自动停后台（用户拍板 B；最小化不触发）③（前端）【下载报告】.txt（DevEco 终端 AI 读文件）
//
// 0.229.12 新增：①hdcTconn + autoConnectTcpDevices——对 ip:port 形态（PC 本机调试口/手机 WiFi）未在线设备自动 tconn，落实"线连优先→IP 兜底"
//   ②（前端）页面一进来若设备未全连，自动弹出可复制的连接诊断报告——用户点「复制报告给 AI」即可，无需每次靠对话口述
//
// 0.229.11 新增（用户拍板 A+B）：①顶栏去掉 versionCode 期望值，只显 APP 版本 ②设备卡统一「连接状态：已连接/未连接」+ 显示已保存地址
//   ③PC 卡片去掉「填写IP连接」（本机不需填）④未连设备弹窗改为可复制的诊断报告（含 hdc list targets 原始结果）⑤设备区常驻「连接诊断」按钮
//   /api/devices 新增 targets 字段（hdc list targets 原始结果，供诊断报告）
//
// 0.229.10 修复：设备地址自动建连命令 connect→tconn（hdc 无 connect 子命令，实测报 Unknown operation command，
//   致手机 WiFi 永远连不上）；PC/Pad 灰显非本服务 bug——hdc list targets 为空（PC 需开 DevEco Studio 现调试口、Pad 需 USB 调试授权）
//
// 0.229.9 新增（用户三诉求，见桌面「测试台待修问题清单.md」）：
//   - /api/suites config 增 appVersionName：读 entry/.../Index.ets 首页 Text('vX.Y.Z')，顶栏显示 APP 界面版本
//   - 前端：设备离线时显示醒目「填写IP连接」按钮；移除「本地/服务器」环境切换（固定本地）
//
// 0.229.2 新增（方案 docs/0.165+/0.229.2 测试台自动化重构.md）：
//   - 启动自愈：已有健康实例→幂等复用退出；端口被僵尸占用→自动清障重试（EADDRINUSE 永不再现）
//   - /api/health 轻量探活（启动器/前端自动等待三用）
//   - /api/devices/update 设备串号热更新（保存后自动 hdc tconn，config.json 落盘）
//   - 桌面交付同步启动器（启动测试台.sh，双击=自动起服务+自动开浏览器）
//
// 安全模型（DeepSeek P0-1 适配）：
//   - 只监听 127.0.0.1（绝不上 0.0.0.0）
//   - /api/* 校验 Origin 白名单：null（file:// 桌面副本）+ http://localhost:8766
//     （Origin 白名单即 CSRF 防线——外部网页带自身 Origin 的 fetch 直接 403；
//       未采用 X-Test-Token：file:// 页面加载 token.js 存在浏览器兼容分叉，
//       Origin 校验已覆盖「任意网页调本地服务」威胁面，特此留档）
//   - spawn(cmd, args[]) 数组参数，禁 exec 字符串拼接（一期 bm dump 报错根因）
//   - 只 spawn hdc；子命令白名单 shell/install/file；serial 只取自 config
//
// 断言纪律（假绿根治，一期 sync 套件双错判过教训）：
//   - 数值断言必须 parseInt 成功且输出无 shell 报错痕迹，否则红灯
//   - 持久化文件 grep 是「尽力确认」通道（路径候选探测），失败=warn 不误报红
//   - dumpLayout 文案 / sqlite3 / bm dump / hilog 为四大断言主通道（0.229.1 双端实证）
// ============================================================
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawn } = require('child_process');

const ROOT = __dirname;
const PROJECT = path.resolve(ROOT, '..', '..');
const CFG = JSON.parse(fs.readFileSync(path.join(ROOT, 'config.json'), 'utf8'));
// 本机 node/hdc 不在默认 PATH：补上本地工具链目录（否则 spawn('hdc') 找不到、设备永远探测不到）
if (CFG.localBuild) {
  const extra = [CFG.localBuild.nodeBin, CFG.localBuild.toolchains].filter(Boolean).join(path.delimiter);
  if (extra) process.env.PATH = extra + path.delimiter + (process.env.PATH || '');
}
const RESULTS_PATH = path.join(ROOT, 'results.json');
const ART_DIR = path.join(ROOT, 'artifacts');
const HAP_PATH = path.resolve(PROJECT, CFG.hap);
const VERSION = '0.302.4.1'; // ★ 0.302.4.1：顶栏读 GSD 版本 + 去掉 iframe title 悬浮提示（消息最多 5 秒）；0.302.3.1：修版本读取；0.302.1.4：与页面同步 // 更早历史见 MEMORY.md 版本表
const AUDIT = require('./auditRules'); // ★ 0.229.26 UI 规范审计引擎（组件族断言函数库）
// ★ 0.229.23 旧服务盲区守卫：启动时记正本 server.js 的 mtime；/api/health 实时比对磁盘正本——
//   正本被更新（AI 改码/git pull）而服务未重启 → stale:true（前端标红顶栏+开跑前置确认）。
//   治本 0.229.17 事故：页面副本随旧服务同步（页面+服务同旧），0.229.21 的"页面对比服务版本"守卫全程无感知
const SELF_MTIME = (() => { try { return fs.statSync(__filename).mtimeMs; } catch (_) { return 0; } })();
function isStale() {
  try { return fs.statSync(__filename).mtimeMs > SELF_MTIME; } catch (_) { return false; }
}

// ---------- 应用界面版本号（顶栏展示用） ----------
// ★ 0.302.3.1：版本真相源自 0.301.1 起迁到 GSD export const APP_VERSION（Index 只 import）——
//   旧逻辑仍去 Index.ets 找 Text('vX.Y.Z')，迁版后永远读不到（顶栏「读不到 Index.ets 版本」根因）。
//   现优先读 GSD APP_VERSION，旧 Index 写法仅作历史兜底。
const INDEX_ETS = path.join(PROJECT, 'entry', 'src', 'main', 'ets', 'pages', 'Index.ets');
const GSD_ETS = path.join(PROJECT, 'entry', 'src', 'main', 'ets', 'components', 'GlobalSettingsDialog.ets');
function readAppVersionName() {
  try {
    const src = fs.readFileSync(GSD_ETS, 'utf8');
    const m = src.match(/APP_VERSION:\s*string\s*=\s*'v([\d.]+)'/);
    if (m) return 'v' + m[1];
  } catch (_) {}
  try {
    const src = fs.readFileSync(INDEX_ETS, 'utf8');
    const m = src.match(/Text\('v(\d+\.\d+\.\d+)'\)/);
    return m ? 'v' + m[1] : null;
  } catch (_) { return null; }
}
// ★ 0.229.17：装机版本核验期望值自动跟读——从 AppScope/app.json5 正则提 versionCode（JSON5 带注释、不能 JSON.parse），
//   读不到回退 config.expectedVersionCode；APP 发版只动 app.json5，期望值自动跟上、永不因写死而误报（落实"版本跟 APP 走"）
const APP_JSON5 = path.join(PROJECT, 'AppScope', 'app.json5');
function readAppVersionCode() {
  try {
    const src = fs.readFileSync(APP_JSON5, 'utf8');
    const m = src.match(/"versionCode"\s*:\s*(\d+)/);
    return m ? parseInt(m[1], 10) : null;
  } catch (_) { return null; }
}
const EXPECTED_VC = readAppVersionCode() ?? (CFG.expectedVersionCode || 0);

const RUN_ID = () => 'R' + new Date().toISOString().replace(/[-:T.]/g, '').slice(0, 14);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const now = () => new Date().toLocaleString('zh-CN');

// ---------- SSE 客户端注册表 ----------
const sseClients = new Set();
function sseSend(obj) {
  const data = 'data: ' + JSON.stringify(obj) + '\n\n';
  for (const res of sseClients) { try { res.write(data); } catch (_) { /* 断开的连接下轮清除 */ } }
}

// ---------- hdc 执行核心（spawn 数组参数，命令白名单） ----------
const HDC_SUBCMDS = new Set(['shell', 'install', 'file']);
function hdcSpawn(serial, args, timeoutMs = 30000) {
  return new Promise((resolve) => {
    if (!HDC_SUBCMDS.has(args[0])) return resolve({ code: -1, out: '', err: 'subcommand not allowed: ' + args[0] });
    const p = spawn('hdc', ['-t', serial, ...args], { timeout: timeoutMs });
    let out = '', err = '';
    p.stdout.on('data', (d) => { out += d.toString(); if (out.length > 16 * 1024 * 1024) p.kill(); });
    p.stderr.on('data', (d) => { err += d.toString(); });
    p.on('close', (code) => resolve({ code: code ?? -1, out, err }));
    p.on('error', (e) => resolve({ code: -1, out: '', err: String(e) }));
  });
}
async function sh(serial, cmd, timeoutMs = 30000) {
  const r = await hdcSpawn(serial, ['shell', cmd], timeoutMs);
  return (r.out || '') + (r.err || '');
}
const SH_ERR_RE = /not found|Permission denied|syntax error|No such file|unable to open|error:/i;

// ---------- 自动连接（ip:port 形态设备：鸿蒙 PC 本机调试口 / 手机 WiFi）★ 0.229.12 连接自动化 ----------
// 设备连接「线连优先→IP 兜底」的落地点：对配置为 ip:port 且当前未在线的设备自动 hdc tconn，让它自己现身
function hdcTconn(serial) {
  return new Promise((resolve) => {
    const cp = spawn('hdc', ['tconn', serial], { timeout: 2500 });
    let o = '';
    cp.stdout.on('data', (d) => { o += d.toString(); });
    cp.stderr.on('data', (d) => { o += d.toString(); });
    cp.on('close', () => resolve(o.trim().slice(0, 200)));
    cp.on('error', () => resolve('spawn fail'));
  });
}
async function autoConnectTcpDevices() {
  const targets = await listTargets();
  const offline = CFG.devices.filter((d) => d.serial && /^\d+\.\d+\.\d+\.\d+:\d+$/.test(d.serial) && !targets.includes(d.serial));
  if (!offline.length) return;
  await Promise.all(offline.map((d) => hdcTconn(d.serial)));
}

// ---------- 设备注册表 ----------

// ★ 0.229.1 能力矩阵：PC 端实测 dumpLayout 只抓桌面树（含 -b 定向空壳）→ UI 断言仅移动端
const canUiDump = (dev) => !(dev.caps && dev.caps.uiDump === false);
function uiSkip(log, dev, what) {
  log(`${what}（UI 断言）`, 'warn', `${dev.label} 无 UI 断言通道（dumpLayout 平台限制，见 config caps.note）——本项以 Pad 端结果为准`);
}
async function listTargets() {
  // list targets 不带 -t：直接 spawn hdc list targets（唯一豁免——只读探测）
  return await new Promise((resolve) => {
    const p = spawn('hdc', ['list', 'targets']);
    let out = '';
    p.stdout.on('data', (d) => { out += d.toString(); });
    p.on('close', () => resolve(out.split('\n').map((s) => s.trim()).filter((s) => s && s !== '[Empty]')));
    p.on('error', () => resolve([]));
  });
}
async function probeDevices() {
  const targets = await listTargets();
  return CFG.devices.map((d) => ({
    ...d,
    online: d.serial !== '' && targets.includes(d.serial),
    reason: d.serial === '' ? '未注册（USB 一次 → tmode port 5555 → hdc tconn <ip>:5555）' : (!targets.includes(d.serial) ? 'hdc 未发现（连线/WiFi 检查）' : '')
  }));
}

// ---------- 断言原语（四大主通道） ----------
async function sqliteQuery(serial, sql) {
  const cmd = `sqlite3 ${CFG.rdb} "${sql};"`;
  const out = await sh(serial, cmd);
  return { out: out.trim(), bad: SH_ERR_RE.test(out) };
}
async function dbCount(serial, prefix) {
  const where = prefix ? `where key like '${prefix}%'` : '';
  const { out, bad } = await sqliteQuery(serial, `select count(*) from cloud_data ${where}`);
  const n = parseInt(out, 10);
  return { ok: !bad && Number.isInteger(n), n, raw: out };
}
async function dbSignature(serial, prefix) {
  const where = prefix ? `where key like '${prefix}%'` : '';
  // ★ 0.241.0.5 修假红：签名去掉 updated_at——它是各端【本地拉取/落库时刻】，三端必然互异（首轮 BOOT-CONVERGE 实锤：
  //   行数/键集/值内容逐字一致而签名红）。口径改 key|length(value)——键集+值长度双校验，内容分叉（键异/值截断）仍必现
  const { out, bad } = await sqliteQuery(serial, `select key || '|' || length(value) from cloud_data ${where} order by key`);
  const hash = bad || out === '' ? null : crypto.createHash('md5').update(out).digest('hex').slice(0, 12);
  return { ok: !bad, hash, lines: bad ? -1 : (out === '' ? 0 : out.split('\n').length), raw: out.slice(0, 2000) };
}
async function dumpLayout(serial) {
  await sh(serial, `rm -f ${CFG.dumpRemote}`);
  const r = await sh(serial, `uitest dumpLayout -p ${CFG.dumpRemote}`, 20000);
  await sleep(1500);
  const text = await sh(serial, `cat ${CFG.dumpRemote}`);
  return { ok: text.length > 100 && !/DumpLayout fail|No such file/.test(r + text), text };
}
// ★ 0.235.2.1 快捕 dump（toast 仅显 ~1500ms——dumpLayout 内含 sleep1500 必错过）：命令本身同步落盘，
//   点完按钮 +400ms 即读；未读到再补一次（覆盖 0~5s 两个窗口）
async function dumpFast(serial) {
  await sh(serial, `rm -f ${CFG.dumpRemote}`);
  const r = await sh(serial, `uitest dumpLayout -p ${CFG.dumpRemote}`, 20000);
  await sleep(400);
  const text = await sh(serial, `cat ${CFG.dumpRemote}`);
  return { ok: text.length > 100 && !/DumpLayout fail|No such file/.test(r + text), text };
}
// ★ 0.229.26 审计专用 dump：-a 全属性 + app 窗口子树节点收集（auditRules 引擎输入）
//   spike 实证：-a 下 fontSize/fontWeight 仍不输出（26 属性键全景见 auditRules.js 头注）；backgroundColor/bounds 可靠
//   includeInvisible=true：键盘态等场景控件可能被移出渲染树/visible=false——B11 须收集后判定
async function dumpAuditNodes(serial, displayId, includeInvisible) {
  const d = displayId !== undefined ? `-d ${displayId} ` : '';
  await sh(serial, `rm -f ${CFG.dumpRemote}`);
  const r = await sh(serial, `uitest dumpLayout -a ${d}-p ${CFG.dumpRemote}`, 25000);
  await sleep(1600);
  const text = await sh(serial, `cat ${CFG.dumpRemote}`);
  const ok = text.length > 100 && !/DumpLayout fail|No such file/.test(r + text);
  if (!ok) return { ok, text, nodes: [] };
  const nodes = [];
  const walk = (n, inApp) => {
    if (!n || typeof n !== 'object') return;
    const a = n.attributes || {};
    const nowIn = inApp || a.bundleName === CFG.bundle;
    if (nowIn) {
      const m = String(a.bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
      if (m && (includeInvisible || a.visible !== 'false')) {
        const b = { x: +m[1], y: +m[2], w: +m[3] - +m[1], h: +m[4] - +m[2], x2: +m[3], y2: +m[4] };
        nodes.push({ ...a, ...b, xc: b.x + b.w / 2, yc: b.y + b.h / 2 });
      }
    }
    for (const k of Object.keys(n)) if (n[k] && typeof n[k] === 'object') walk(n[k], nowIn);
  };
  try { walk(JSON.parse(text), false); } catch (_) { /* dump 非 JSON */ }
  return { ok, text, nodes };
}
async function dumpCountText(serial, word) {
  const d = await dumpLayout(serial);
  const n = (d.text.match(new RegExp(word, 'g')) || []).length;
  return { ok: d.ok, n, text: d.text };
}
// ---------- ★ 0.229.19 UI 自动点击原语（用户拍板"能不让我点就不点"：app 内一切有文本的按钮自动点，仅华为系统授权页保留人工） ----------
// ★ 0.229.24 误点根治（用户 07:06 报告实锤）：findNodeBounds 只取【第一个】命中——协议模态开着时，首页勾选框
//   （底层，文本同为"我已阅读并同意…"）在 dump 树前部被先命中 → 点它=点到模态遮罩=「暂不同意」→ 模态关闭 →
//   「同意并继续」找不到 → 报告两连败真凶。修=findNodeBoundsAll 收集全部命中 + uiClickText opts.near 同列最近。
function findNodeBoundsAll(jsonText, keyword) {
  const hits = [];
  const walk = (node) => {
    if (!node || typeof node !== 'object') return;
    if (node.attributes) {
      const t = String(node.attributes.text || '');
      if (t && t.includes(keyword)) {
        const m = String(node.attributes.bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
        if (m) hits.push({ x: Math.round((+m[1] + +m[3]) / 2), y: Math.round((+m[2] + +m[4]) / 2), text: t.slice(0, 30) });
      }
    }
    for (const k of Object.keys(node)) if (node[k] && typeof node[k] === 'object') walk(node[k]);
  };
  try { walk(JSON.parse(jsonText)); } catch (_) { /* dump 非 JSON 则放弃定位 */ }
  return hits;
}
function findNodeBounds(jsonText, keyword) { const h = findNodeBoundsAll(jsonText, keyword); return h.length ? h[0] : null; }
// ★ 0.235.0：含关键字节点的完整矩形（findNodeBoundsAll 只回中心——× 等右端子控件定位需要右缘坐标）
function findTextRect(jsonText, keyword) {
  let out = null;
  const walk = (node) => {
    if (!node || typeof node !== 'object') return;
    if (node.attributes) {
      const t = String(node.attributes.text || '');
      if (t.includes(keyword)) {
        const m = String(node.attributes.bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
        if (m) out = { x1: +m[1], y1: +m[2], x2: +m[3], y2: +m[4], x: Math.round((+m[1] + +m[3]) / 2), y: Math.round((+m[2] + +m[4]) / 2), text: t.slice(0, 30) };
      }
    }
    for (const k of Object.keys(node)) if (node[k] && typeof node[k] === 'object') walk(node[k]);
  };
  try { walk(JSON.parse(jsonText)); } catch (_) { /* dump 非 JSON 则放弃定位 */ }
  return out;
}
// ★ 0.229.24 勾选框图标点击原语（盯屏破案实锤）：勾选行=Row[Image(无文字,onClick 承载体) + Text(文字仅展示)]——
//   旧 uiClickText 点文字中心=点了个寂寞（首页文字无 onClick；弹窗文字 span 中心落在协议名上会误开正文）。
//   必须点文字左侧的 Image 图标本体（dump 兄弟数组里文字前方最近的无文字节点）；兜底几何近似（文字左缘-40px）
function parseBoundsStr(s) {
  const m = String(s || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
  return m ? { x: Math.round((+m[1] + +m[3]) / 2), y: Math.round((+m[2] + +m[4]) / 2), left: +m[1], top: +m[2] } : null;
}
function collectTextNodesWithSibs(jsonText, keyword) {
  const out = [];
  // sibs=节点所在兄弟数组；owner=该数组的父节点；ownerSibs=父节点所在兄弟数组（两级向上找行首图标用）
  const walk = (node, sibs, owner, ownerSibs) => {
    if (!node || typeof node !== 'object') return;
    if (node.attributes && String(node.attributes.text || '').includes(keyword)) out.push({ node, sibs, owner, ownerSibs });
    for (const k of Object.keys(node)) {
      const v = node[k];
      if (Array.isArray(v)) v.forEach((c) => walk(c, v, node, sibs));
      else if (v && typeof v === 'object') walk(v, sibs, owner, ownerSibs);
    }
  };
  try { walk(JSON.parse(jsonText), null, null, null); } catch (_) { /* dump 非 JSON 则放弃 */ }
  return out;
}
function checkboxImageCenter(hit) {
  // L1：文字节点自己的兄弟数组里，前方最近的无文字节点（Row[Image, Text] 勾选框行）
  // L2：文字父容器（如 Column）的兄弟数组里，前方最近的无文字节点（边栏账号行=Row[Image(头像), Column(未登录/昵称)]）
  const tryArr = (arr, refNode) => {
    if (!Array.isArray(arr) || !refNode) return null;
    const idx = arr.indexOf(refNode);
    if (idx < 0) return null;
    for (let i = idx - 1; i >= 0; i--) {
      const s = arr[i];
      if (s && typeof s === 'object' && s.attributes && !String(s.attributes.text || '').trim()) {
        const c = parseBoundsStr(s.attributes.bounds);
        if (c) return c;
      }
    }
    return null;
  };
  const c = tryArr(hit.sibs, hit.node) || tryArr(hit.ownerSibs, hit.owner);
  if (c) return { x: c.x, y: c.y, how: '行内图标本体' };
  const b = parseBoundsStr(hit.node.attributes && hit.node.attributes.bounds);
  return b ? { x: b.left - 40, y: b.top + 20, how: '几何近似' } : null;
}
// ★ 0.229.24 最上层弹窗按钮定位（双层弹窗堆叠根治）：树序最后的命中=最上层（后绘制在上），
//   点它关最上层弹窗、露出下一层——循环即可逐层清干净；旧「顺序点关键字」在堆叠时点空
function findTopmostButton(dumpText, keywords) {
  let last = null;
  const walk = (node) => {
    if (!node || typeof node !== 'object') return;
    if (node.attributes) {
      const t = String(node.attributes.text || '');
      if (keywords.some((k) => t.includes(k))) {
        const m = String(node.attributes.bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
        if (m) last = { x: Math.round((+m[1] + +m[3]) / 2), y: Math.round((+m[2] + +m[4]) / 2), text: t.slice(0, 20) };
      }
    }
    for (const k of Object.keys(node)) if (node[k] && typeof node[k] === 'object') walk(node[k]);
  };
  try { walk(JSON.parse(dumpText)); } catch (_) { /* dump 非 JSON */ }
  return last;
}
async function dismissLoginDialogs(serial, log) {
  // 登录后弹窗（30天试用「知道了」/云同步询问「暂不开启」）逐层关；最多 6 轮，每轮点树序最后的按钮（最上层）
  for (let i = 0; i < 6; i++) {
    const dd = await dumpLayout(serial);
    if (!dd.ok) break;
    const b = findTopmostButton(dd.text, ['知道了', '暂不开启']);
    if (!b) break;
    await sh(serial, `uitest uiInput click ${b.x} ${b.y}`, 15000);
    if (log) log('关登录后弹窗·点最上层「' + b.text + '」', 'pass', `已点击 (${b.x},${b.y})`);
    await sleep(1200);
  }
}
async function uiClickCheckbox(serial, textKeyword, opts = {}) {
  const d = await dumpLayout(serial);
  if (!d.ok) return { ok: false, err: 'dumpLayout 失败（无法定位勾选框）' };
  const hits = collectTextNodesWithSibs(d.text, textKeyword);
  if (!hits.length) return { ok: false, err: `页面未找到「${textKeyword}」勾选行` };
  let pick = hits[0];
  if (opts.near) { // 弹窗内勾选行 vs 首页底层勾选行：与参照按钮纵向距离最近者胜
    const ref = findNodeBoundsAll(d.text, opts.near)[0];
    if (ref) pick = hits.map((h) => ({ h, c: parseBoundsStr(h.node.attributes && h.node.attributes.bounds) }))
      .filter((x) => x.c).reduce((m, x) => (Math.abs(x.c.y - ref.y) < Math.abs(m.c.y - ref.y) ? x : m)).h;
  }
  const target = checkboxImageCenter(pick);
  if (!target) return { ok: false, err: '勾选框图标定位失败（兄弟无 Image 且文字无 bounds）' };
  const r = await sh(serial, `uitest uiInput click ${target.x} ${target.y}`, 15000);
  await sleep(opts.waitMs || 900);
  return { ok: !SH_ERR_RE.test(r), x: target.x, y: target.y, how: target.how, nHits: hits.length, raw: r.trim().slice(0, 120) };
}
async function uiClickText(serial, keyword, opts = {}) {
  const d = await dumpLayout(serial);
  if (!d.ok) return { ok: false, err: 'dumpLayout 失败（无法定位控件）' };
  let hits = findNodeBoundsAll(d.text, keyword);
  // ★ 0.229.24 exact 精确匹配（包含陷阱根治）：'登录华为账号'会同时命中引导窗正文「请先登录华为账号。」——
  //   点正文=无效点击；exact 只留全文恰等于关键字的控件（按钮文案天然短正文长）
  if (opts.exact) hits = hits.filter((h) => h.text === keyword);
  if (!hits.length) return { ok: false, err: `页面未找到含「${keyword}」的控件${opts.exact ? '（精确匹配）' : ''}` };
  let b = hits[0];
  if (opts.near) {
    // ★ 同列最近命中：取与参照按钮（唯一文本）纵向距离最近的命中——弹窗内目标 vs 底层同名控件天然分离；
    //   兜底取最后一个命中（上层节点在 dump 树后部）
    const ref = findNodeBoundsAll(d.text, opts.near)[0];
    if (ref) {
      b = hits.reduce((m, h) => (Math.abs(h.y - ref.y) < Math.abs(m.y - ref.y) ? h : m), hits[0]);
    }
  } else if (opts.pick === 'last') b = hits[hits.length - 1];
  const r = await sh(serial, `uitest uiInput click ${b.x} ${b.y}`, 15000);
  await sleep(opts.waitMs || 1200);
  return { ok: !SH_ERR_RE.test(r), x: b.x, y: b.y, text: b.text, raw: r.trim().slice(0, 120), nHits: hits.length };
}
// 协议模态弹窗自动同意（fresh 全新安装后首启必弹「阅读并同意」模态，0.226.0）
// ★ 0.229.21 真缺陷修复（用户截图实锤）：未勾选复选框时「同意并继续」是禁用态、点不动——必须先点「我已阅读并同意」勾选、再点同意（100% 复刻 app 真实交互序列）
// ★ 0.229.24 两修：①勾选=点 Image 图标本体（uiClickCheckbox near 同列定位；旧点文字=点了寂寞/误开协议正文）
//   ②勾选后验证「同意并继续」已从禁用变可用（dump enabled 属性）再点；③同意后自动关「体验改进计划」引导
async function agreeDialogIfAny(serial, log) {
  const d = await dumpLayout(serial);
  if (!d.ok || !d.text.includes('同意并继续')) return { agreed: false };
  const chk = await uiClickCheckbox(serial, '我已阅读并同意', { waitMs: 900, near: '同意并继续' });
  if (log) log('协议弹窗·自动勾选「我已阅读并同意」', chk.ok ? 'pass' : 'warn', chk.ok ? `已点击勾选框图标 (${chk.x},${chk.y})（${chk.how}·同名行${chk.nHits}处）` : (chk.err || '勾选框定位失败——继续尝试直接点同意'));
  // 勾选生效验证：dump「同意并继续」节点 enabled 应已从 false 变 true（0.229.21：未勾选=禁用态）
  const dv = await dumpLayout(serial);
  const btnNode = collectTextNodesWithSibs(dv.text, '同意并继续')[0];
  const enabledOk = btnNode && String((btnNode.node.attributes || {}).enabled || '') !== 'false';
  if (log && chk.ok) log('勾选生效验证（同意按钮已可用）', enabledOk ? 'pass' : 'warn', enabledOk ? 'enabled=true——勾选真实生效' : '同意按钮仍禁用——勾选可能未生效，点击可能点不动');
  const c = await uiClickText(serial, '同意并继续', { waitMs: 1800 });
  if (log) log('协议弹窗·自动点「同意并继续」', c.ok ? 'pass' : 'fail', c.ok ? `已点击 (${c.x},${c.y})「${c.text}」` : (c.err || c.raw || '点击失败'));
  if (c.ok) {
    const imp = await uiClickText(serial, '暂不加入', { waitMs: 1200 });
    if (log && imp.ok) log('体验改进弹窗·自动点「暂不加入」', 'pass', `已点击 (${imp.x},${imp.y})（0.226.0 同意后首弹引导，默认关=合规默认）`);
  }
  return { agreed: true, ok: c.ok };
}
// ★ 0.229.20 入口隔离收尾：自动退出登录（用户拍板"测完一条入口必须先退出，才能测下一条入口"——否则登录态互相污染）
// ★ 0.229.24 产物对照实锤重写：①实际按钮文案=「退出账号」（Index.ets Button('退出账号')；旧关键字「退出登录」页面上
//   不存在=永远找不到）；②无二次确认（0.164 doLogout 直退，删确认点击）；③登录后双层弹窗（🎉30天试用+是否开启云同步）
//   逐层关闭（dismissLoginDialogs：每轮点树序最后的按钮=最上层弹窗，堆叠也不点空）；④设置弹窗开着先关再退（防点空）
async function autoLogout(ctx, serial, dev) {
  if (!canUiDump(dev)) { ctx.log('收尾·退出登录', 'skip', 'PC 无 UI 通道，跳过（下一条入口用例的 coldStart+autoLogout 会兜底）'); return; }
  const n0 = (await dumpCountText(serial, '已登录')).n;
  if (n0 === 0) { ctx.log('收尾·退出登录', 'pass', '当前已处于未登录（入口隔离已满足）'); return; }
  // ★ 0.229.24（SYNC 收尾翻车点）：设置弹窗开着时其面板盖住首页「退出账号」按钮——先点「返回」关弹窗再退
  const dc = await dumpLayout(serial);
  if (dc.ok && dc.text.includes('全局设置')) {
    const back = await uiClickText(serial, '返回', { waitMs: 2200, exact: true });
    if (back.ok) ctx.log('收尾·自动点「返回」关设置弹窗', 'pass', `已点击 (${back.x},${back.y})（弹窗面板盖着退出账号按钮，不关会点空）`);
  }
  // ★ 0.229.24 登录后双层弹窗逐层关（fresh 首登=30天试用+云同步询问堆叠，顺序点会点空）
  await dismissLoginDialogs(serial, ctx.log);
  let a1 = await uiClickText(serial, '退出账号', { waitMs: 2000 });
  // ★ 0.241.0.4 手机适配：抽屉/画布页无「退出账号」（按钮在首页已登录卡）——Back 回首页重试
  if (!a1.ok && dev.id === 'phone') {
    for (let i = 0; i < 3 && !a1.ok; i++) {
      await sh(serial, `uitest uiInput keyEvent Back`, 15000);
      await sleep(1400);
      const dk = await dumpLayout(serial);
      if (dk.ok && dk.text.includes('退出账号')) a1 = await uiClickText(serial, '退出账号', { waitMs: 2000 });
      else break;
    }
  }
  if (a1.ok) {
    ctx.log('收尾·自动点「退出账号」', 'pass', `已点击 (${a1.x},${a1.y})（实际文案=退出账号，无二次确认直退）`);
    await sleep(2000);
    const n = (await dumpCountText(serial, '已登录')).n;
    ctx.log('★收尾·已退出（下一入口从未登录基线开始）', n === 0 ? 'pass' : 'fail', n === 0 ? '退出成功——入口隔离达成' : `已登录×${n}（未退出，将污染下一入口用例）`);
    return;
  }
  ctx.log('收尾·退出登录', 'warn', '当前页未找到「退出账号」按钮（可能被弹窗遮挡或需进入账号页）——请人工退出，否则污染下一入口用例');
}
async function bmVersionCode(serial) {
  const out = await sh(serial, `bm dump -n ${CFG.bundle}`);
  const codes = [...out.matchAll(/"versionCode": (\d+)/g)].map((m) => parseInt(m[1], 10)).filter((n) => n > 0);
  return { ok: codes.length > 0, code: codes.length ? Math.max(...codes) : null, raw: out.slice(0, 300) };
}
async function hilogErrors(serial) {
  const tags = CFG.hilogTags.join('|');
  const out = await sh(serial, `hilog -x 2>/dev/null | grep -E "${tags}" | grep -icE "error|fail"`, 15000);
  const n = parseInt(out.trim(), 10);
  return { ok: Number.isInteger(n), n };
}
// 持久化文件尽力确认通道（路径候选探测——EL2 默认区，登录产生数据后生效）
// ★ 0.229.24 实测修正：真实路径=haps/entry/files/persistent_storage（旧三条候选全错=通道恒 warn 的真凶）
const PREF_CANDIDATES = [
  'haps/entry/files/persistent_storage',
  'preferences/persistent_storage',
  'haps/entry/preferences/persistent_storage',
  'files/persistent_storage'
];
async function grepPref(serial, needle) {
  for (const p of PREF_CANDIDATES) {
    const full = `${CFG.sandboxBase}/${p}`;
    const out = await sh(serial, `grep -o '${needle}.\\{0,40\\}' '${full}' 2>/dev/null | head -3`);
    if (out.trim() !== '') return { found: true, path: full, sample: out.trim().slice(0, 300) };
  }
  return { found: false, tried: PREF_CANDIDATES };
}

// ★ 0.240.2 拉盘全量解析通道：persistent_storage 的 v5 值=XML 实体（&quot;）+ 双层 JSON.stringify
//   三层转义膨胀——BusyBox grep BRE 量词上限 256，240 字符窗口到不了 provider 字段（首跑实锤：
//   KMARK 在 apiKey 命中而 provider 恒空）。拉到本地 node 解析：去实体→剥两层 stringify 包裹→
//   cfgJson 再 parse，直接拿全 13 字段（provider/apiKey/modelAlias 等全字段断言一次到位）。
async function pullPrefCfg(serial, key) {
  for (const p of PREF_CANDIDATES) {
    const tmp = path.join(ART_DIR, `pref-${serial.replace(/[^a-zA-Z0-9]/g, '')}-${Date.now()}.xml`);
    const r = await hdcSpawn(serial, ['file', 'recv', `${CFG.sandboxBase}/${p}`, tmp], 20000);
    if (r.code === 0 && fs.existsSync(tmp) && fs.statSync(tmp).size > 0) {
      try {
        const raw = fs.readFileSync(tmp, 'utf8');
        const m = raw.match(new RegExp(`key="${key}">([^<]*)<`));
        if (!m) return { ok: false, err: `盘上无 ${key} 条目`, sample: raw.slice(0, 200) };
        let v = m[1].replace(/&quot;/g, '"').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>');
        let parsed = JSON.parse(v); // 剥第一层 stringify 包裹（字符串形态）
        if (typeof parsed === 'string') parsed = JSON.parse(parsed); // 双层包裹形态再剥一层
        const cfg = typeof parsed === 'object' && parsed !== null && typeof parsed.cfgJson === 'string'
          ? JSON.parse(parsed.cfgJson) : parsed;
        return { ok: typeof cfg === 'object' && cfg !== null, cfg, path: `${CFG.sandboxBase}/${p}` };
      } catch (e) {
        return { ok: false, err: '解析失败: ' + String(e && e.message) };
      } finally {
        try { fs.unlinkSync(tmp); } catch (_e) { /* 临时文件清理尽力 */ }
      }
    }
  }
  return { ok: false, err: 'persistent_storage 全候选路径 file recv 失败' };
}

// ---------- bm / aa 环境动作 ----------
async function coldStart(serial, waitMs = 9000) {
  await sh(serial, `aa force-stop ${CFG.bundle}`);
  await sleep(1200);
  const r = await sh(serial, `aa start -b ${CFG.bundle} -a ${CFG.ability}`);
  await sleep(waitMs);
  return /successfully/.test(r);
}
async function bmInstall(serial, overwrite = false) {
  if (!fs.existsSync(HAP_PATH)) return { ok: false, detail: 'HAP 不存在：' + HAP_PATH + '（请先编译）' };
  const args = overwrite ? ['install', '-r', HAP_PATH] : ['install', HAP_PATH];
  const r = await hdcSpawn(serial, args, 180000);
  return { ok: /successfully/.test(r.out + r.err), detail: (r.out + r.err).trim().slice(0, 300) };
}

// ---------- 编译来源（Q2：鸿蒙PC 本地编译 / 老机器服务器编译） ----------
function runCmd(cmd, args, cwd, timeoutMs, env) {
  return new Promise((resolve) => {
    const p = spawn(cmd, args, { cwd, timeout: timeoutMs, env: env || process.env });
    let out = '';
    const push = (d) => { out += d.toString(); if (out.length > 4 * 1024 * 1024) out = out.slice(-2 * 1024 * 1024); };
    p.stdout.on('data', push); p.stderr.on('data', push);
    p.on('close', (code) => resolve({ code: code ?? -1, out }));
    p.on('error', (e) => resolve({ code: -1, out: String(e) }));
  });
}
function pickHap() {
  const outDir = path.dirname(HAP_PATH);
  try {
    const list = fs.readdirSync(outDir).filter((f) => /-signed\.hap$/.test(f)).map((f) => path.join(outDir, f));
    if (!list.length) return null;
    list.sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
    return list[0];
  } catch (_) { return null; }
}
async function localBuild() {
  const lb = CFG.localBuild || {};
  const hvigorw = lb.hvigorw;
  if (!hvigorw || !fs.existsSync(hvigorw)) return { ok: false, err: '本机 hvigorw 未配置/不存在（config.localBuild.hvigorw）' };
  const env = { ...process.env };
  if (lb.sdkHome) env.DEVECO_SDK_HOME = lb.sdkHome;
  if (lb.nodeBin) env.PATH = lb.nodeBin + path.delimiter + (env.PATH || '');
  try { const outDir = path.dirname(HAP_PATH); for (const f of fs.readdirSync(outDir)) if (/-signed\.hap$/.test(f)) fs.unlinkSync(path.join(outDir, f)); } catch (_) { /* 目录不存在 */ }
  const r = await runCmd(hvigorw, ['assembleHap', '--mode', 'module', '-p', 'product=default', '-p', 'debuggable=true', '--no-daemon'], PROJECT, 900000, env);
  if (r.code !== 0) return { ok: false, err: `本机编译失败（hvigorw exit ${r.code}）`, log: r.out.slice(-4000) };
  const hap = pickHap();
  return hap ? { ok: true, hap, log: r.out.slice(-2000) } : { ok: false, err: '编译完成但未产出 *-signed.hap', log: r.out.slice(-3000) };
}
// ---------- ArkUI Test（hypium 设备内真断言：编译测试包 → 安装 → aa test） ----------
function testHapDir() { return path.resolve(PROJECT, 'entry/build/default/outputs/ohosTest'); }
function pickTestHap() {
  try {
    const list = fs.readdirSync(testHapDir()).filter((f) => /-signed\.hap$/.test(f)).map((f) => path.join(testHapDir(), f));
    if (!list.length) return null;
    list.sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
    return list[0];
  } catch (_) { return null; }
}
// ★ 0.241.0.10 新增：读已编译测试包的 versionCode——pack.info 与 hap 同批产出（纯 JSON，免解包 hap）。
//   app 每次发版递增 versionCode 后旧测试包必装不上（hdc install 9568263 版本不匹配，0.235.0/0.237.1/0.237.2 三踩）；
//   本函数供 ARKUI-TEST 复用前比对，读不到/解析失败一律返回 null（=视为过期强制重编，安全侧倒）
function testHapVersionCode() {
  try {
    const info = JSON.parse(fs.readFileSync(path.join(testHapDir(), 'pack.info'), 'utf8'));
    const code = info && info.summary && info.summary.app && info.summary.app.version && info.summary.app.version.code;
    return Number.isInteger(code) ? code : null;
  } catch (_) { return null; }
}
async function buildTestHap() {
  const lb = CFG.localBuild || {};
  const hvigorw = lb.hvigorw;
  if (!hvigorw || !fs.existsSync(hvigorw)) return { ok: false, err: '本机 hvigorw 未配置（config.localBuild.hvigorw）' };
  const env = { ...process.env };
  if (lb.sdkHome) env.DEVECO_SDK_HOME = lb.sdkHome;
  if (lb.nodeBin) env.PATH = lb.nodeBin + path.delimiter + (env.PATH || '');
  try { const d = testHapDir(); for (const f of fs.readdirSync(d)) if (/-signed\.hap$/.test(f)) fs.unlinkSync(path.join(d, f)); } catch (_) { /* 目录不存在 */ }
  const r = await runCmd(hvigorw, ['assembleHap', '--mode', 'module', '-p', 'module=entry@ohosTest', '-p', 'product=default', '-p', 'debuggable=true', '--no-daemon'], PROJECT, 900000, env);
  if (r.code !== 0) return { ok: false, err: `测试包编译失败（hvigorw exit ${r.code}）`, log: r.out.slice(-3000) };
  const hap = pickTestHap();
  return hap ? { ok: true, hap, log: r.out.slice(-1500) } : { ok: false, err: '测试包编译完成但未产出 -ohosTest-signed.hap', log: r.out.slice(-2000) };
}
async function aaTestRun(serial) {
  return await sh(serial, `aa test -b ${CFG.bundle} -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 60000`, 150000);
}
function summarizeAaTest(out) {
  const t = String(out || '');
  // ★ 0.229.14 修「假失败」：旧逻辑剥离统计时正则没剥净（failure/failures 残留）再拿 /failure/i 关键词判失败，
  //   "failure: 0"（0 个失败）被误判成失败。改为三层判据：ResultCode 硬判 → [fail] 精确行 → 统计数值化（N>0 才失败）
  const rc = t.match(/TestFinished-ResultCode\s*[:=]\s*(\d+)/i);
  if (rc && parseInt(rc[1], 10) !== 0) return { level: 'fail', note: '测试框架 ResultCode=' + rc[1] + '（非 0=异常结束，详见原始日志）' };
  const failLines = (t.match(/\[fail\]/gi) || []).length;
  if (failLines > 0) return { level: 'fail', note: 'hypium 有 ' + failLines + ' 条用例失败（详见原始日志）' };
  const f = t.match(/fail(?:ures?|ed)?\s*[:=]\s*(\d+)/i) || t.match(/(\d+)\s+failures?/i);
  if (f && parseInt(f[1], 10) > 0) return { level: 'fail', note: '统计 failure=' + f[1] + '（有用例失败，详见原始日志）' };
  const finished = /your test finished/i.test(t) || (!!rc && rc[1] === '0');
  // ★ 0.248.7.1：断言清单动态化（原「2 条真断言」名单写死——新增 SiyiPoint 5 条后旧判定仍报绿但新用例
  //   是否真执行不可见，同族 0.241.0.10「缓存复用无身份校验」坑）；名单=全部已注册 hypium 用例名，
  //   有缺=warn 提示（测试包未重编/用例漏注册），全命中才 pass
  const KNOWN = ['app_context_ready', 'bundle_versioncode_valid', 'balance_grant_minus_consumed',
    'consume_order_gift_bonus_permanent', 'consume_over_balance_clamp_to_zero', 'consume_zero_balance_rejected',
    'balance_never_negative_on_weird_consumed', 'inline_bold', 'inline_code_span'];
  const hit = KNOWN.filter((k) => t.includes(k));
  const miss = KNOWN.filter((k) => !t.includes(k));
  if (finished && hit.length > 0 && miss.length === 0) return { level: 'pass', note: `测试框架正常结束（ResultCode 0）+ ${hit.length} 条断言名全部执行` };
  if (finished && hit.length > 0) return { level: 'warn', note: `框架正常结束+${hit.length} 条断言命中，但缺 ${miss.length} 条（${miss.slice(0, 3).join('/')}…）——测试包可能未重编或用例漏注册` };
  if (finished) return { level: 'warn', note: '框架正常结束但未识别到用例名（附原始日志尾供核对）' };
  return { level: 'warn', note: '未能从输出识别结果（附原始日志尾供核对）' };
}
function serverBuild() {
  return new Promise((resolve) => {
    const base = CFG.buildServer;
    if (!base) return resolve({ ok: false, err: '未配置服务器编译地址（config.buildServer）' });
    let u; try { u = new URL('/build', base); } catch (_) { return resolve({ ok: false, err: '服务器编译地址非法：' + base }); }
    const req = http.request({ host: u.hostname, port: u.port, path: u.pathname, method: 'POST', timeout: 900000, headers: { 'content-length': 0 } }, (r) => {
      if (r.statusCode !== 200) { let t = ''; r.on('data', (d) => { t += d; }); r.on('end', () => resolve({ ok: false, err: `服务器编译失败 HTTP ${r.statusCode}：` + t.slice(0, 800) })); return; }
      const chunks = []; let len = 0;
      r.on('data', (d) => { chunks.push(d); len += d.length; if (len > 200 * 1024 * 1024) req.destroy(); });
      r.on('end', () => {
        try { fs.writeFileSync(HAP_PATH, Buffer.concat(chunks)); resolve({ ok: true, hap: HAP_PATH, bytes: len }); }
        catch (e) { resolve({ ok: false, err: '写 HAP 失败：' + String(e) }); }
      });
    });
    req.on('timeout', () => { req.destroy(); resolve({ ok: false, err: '服务器编译超时' }); });
    req.on('error', (e) => resolve({ ok: false, err: '连不上服务器编译服务：' + String(e) }));
    req.end();
  });
}
async function bmUninstall(serial) {
  // ★ 0.229.18 修「全新安装没卸载」假成功：①卸载前先 force-stop（app 运行中时部分版本卸载会失败）
  //   ②旧成功正则 /successfully|Uninstall/ 会把含 "Uninstall failed" 的失败输出也判成成功——改为「有成功标志且无失败标志」
  await sh(serial, `aa force-stop ${CFG.bundle}`, 10000);
  const r = await sh(serial, `bm uninstall -n ${CFG.bundle}`, 60000);
  const ok = /(successfully|finish)/i.test(r) && !/(failure|failed|error)/i.test(r);
  // ★ 0.241.0.3 新设备首装修复：设备从未装过该 app 时卸载报 code:9568386 "missing installed bundle"=设备本来就是干净状态，非真失败（Pura X View 首装实锤：卸载失败被中止=永远装不上）
  const clean = /missing installed bundle|9568386/i.test(r);
  return { ok, clean, detail: r.trim().slice(0, 200) };
}

// ---------- artifacts 证据留存 ----------
let curRun = null;
function artPath(caseKey) {
  const p = path.join(ART_DIR, curRun.runId, caseKey.replace(/[^a-zA-Z0-9_-]/g, '_'));
  fs.mkdirSync(p, { recursive: true });
  return p;
}
function artSave(caseKey, name, data) {
  try {
    const p = path.join(artPath(caseKey), name);
    fs.writeFileSync(p, typeof data === 'string' ? data : JSON.stringify(data, null, 2));
    return `artifacts/${curRun.runId}/${path.basename(path.dirname(p))}/${name}`;
  } catch (e) { return 'artifacts写失败:' + String(e); }
}
async function artDump(caseKey, name, serial) {
  const d = await dumpLayout(serial);
  if (d.ok) artSave(caseKey, name, d.text);
  return d;
}

// ---------- 人工检查点协议状态机（pending→waiting→done/timeout/skipped） ----------
const checkpoints = new Map();
let cpSeq = 0;
function checkpoint(opt) {
  // opt: {label, deviceId, detect?: async()=>boolean, verdict?: ['pass','fail'], timeoutMs}
  const id = 'cp' + (++cpSeq);
  const cp = { id, state: 'waiting', label: opt.label, device: opt.deviceId, startedAt: Date.now(),
    timeoutMs: opt.timeoutMs || CFG.checkpoint.timeoutMs, hasVerdict: !!opt.verdict };
  checkpoints.set(id, cp);
  sseSend({ type: 'checkpoint', cp: { ...cp } });
  return new Promise(async (resolve) => {
    let settled = false;
    const finish = (state, extra) => {
      if (settled) return; settled = true;
      cp.state = state; clearTimeout(timer); clearInterval(poller);
      Object.assign(cp, extra || {});
      checkpoints.delete(id);
      sseSend({ type: 'checkpoint', cp: { ...cp } });
      // ★ 0.229.24：resolve 必须带 auto——旧版只回 {state, verdict}，用例读 r.auto 恒 undefined，
      //   明明 detect 秒级自动确认却恒显「用户确认完成」（日志级假象，对测试台的测试盯出来的）
      resolve({ state, verdict: cp.verdict, auto: !!cp.auto });
    };
    cp.finish = finish; // API 按钮入口
    const timer = setTimeout(() => finish('timeout'), cp.timeoutMs);
    const poller = opt.detect ? setInterval(async () => {
      try { if (await opt.detect()) finish('done', { auto: true }); } catch (_) { /* 探测异常继续等 */ }
    }, CFG.poll.intervalMs) : null;
    if (opt.detect) { try { if (await opt.detect()) finish('done', { auto: true }); } catch (_) {} }
  });
}

// ---------- 用例执行器 ----------
const STEP = (name, status, detail, ms) => ({ name, status, detail: String(detail ?? '').slice(0, 500), ms });
async function runCase(devices, caseDef) {
  const steps = [];
  const log = (name, status, detail, ms) => { const s = STEP(name, status, detail, ms); steps.push(s); sseSend({ type: 'step', runId: curRun.runId, case: caseDef.id, step: s }); return s; };
  const t0 = Date.now();
  let status = 'pass';
  // ★ 0.229.17：用例级超时保护（用户"停止了不可能一直等、卡住要有反馈"）——超时自动标失败并写明原因、跳过继续后续用例
  // ★ 0.241.0.10：用例可带 timeoutMs 覆盖全局值（ARKUI-TEST 需现场重编测试包，数分钟，给 900s 专属档）
  const timeoutMs = caseDef.timeoutMs || CFG.caseTimeoutMs || 300000;
  let timer = null;
  try {
    await Promise.race([
      caseDef.run({ devices, log, checkpoint, art: { save: artSave, dump: artDump } }),
      new Promise((resolve) => {
        timer = setTimeout(() => {
          log('用例超时中止', 'fail', `本条用例超过 ${Math.round(timeoutMs / 1000)}s 未完成——已自动中止并跳过，继续跑后续用例（防傻等；底层命令会在其自身超时后释放）`);
          resolve();
        }, timeoutMs);
      }),
    ]);
  } catch (e) {
    log('执行异常', 'fail', String(e));
  } finally {
    if (timer) clearTimeout(timer);
  }
  for (const s of steps) {
    if (s.status === 'fail') { status = 'fail'; break; }
    if (s.status === 'warn') status = status === 'pass' ? 'warn' : status;
    if (s.status === 'skip' && status === 'pass') status = 'skip';
  }
  return { case: caseDef.id, name: caseDef.name, status, steps, ms: Date.now() - t0 };
}

// ---------- 用例前置助手（用例间隔离，DeepSeek P0-2） ----------
// ★ 0.229.24：ensureLoggedOut（人工检查点退出）已删——三入口用例统一改 coldStart→autoLogout 全自动复位
//   （实际按钮文案=退出账号+登录后双层弹窗处理，见 autoLogout 注释）
async function pollUntil(fn, timeoutMs, intervalMs = CFG.poll.intervalMs) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) { if (await fn()) return true; await sleep(intervalMs); }
  return false;
}

// ============================================================
// ★ 0.229.25 SYNC-FLOW 编排基建（跨端数据链：UI 操作端 → 云端 → 数据断言端）
// ============================================================
async function forceStopApp(serial) { await sh(serial, `aa force-stop ${CFG.bundle}`, 10000); }
// 长按原语（气泡长按 500ms 弹操作菜单 / PC 右键同款——PC 无 UI 通道，长按仅移动端）
async function uiLongPress(serial, x, y, waitMs = 1500) {
  const r = await sh(serial, `uitest uiInput longClick ${x} ${y}`, 15000);
  await sleep(waitMs);
  return { ok: !SH_ERR_RE.test(r) && !/fail|unknown/i.test(r), raw: r.trim().slice(0, 120) };
}
// 文本注入原语（先点输入框聚焦再 inputText——参数序 x y text，0.229.25 首跑盯屏校准点）
async function uiInputText(serial, x, y, text) {
  const c = await sh(serial, `uitest uiInput click ${x} ${y}`, 15000);
  await sleep(700);
  const r = await sh(serial, `uitest uiInput inputText ${x} ${y} ${text}`, 15000);
  return { ok: !SH_ERR_RE.test(r) && !/fail|unknown/i.test(r), raw: (c + ' | ' + r).trim().slice(0, 200) };
}
// TextInput 占位符定位（placeholder 在 attributes.hint——text 恒空，findNodeBoundsAll 查不到）
function findNodeHintAll(jsonText, keyword) {
  const hits = [];
  const walk = (node) => {
    if (!node || typeof node !== 'object') return;
    if (node.attributes && String(node.attributes.hint || '').includes(keyword)) {
      const m = String(node.attributes.bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
      if (m) hits.push({ x: Math.round((+m[1] + +m[3]) / 2), y: Math.round((+m[2] + +m[4]) / 2), hint: String(node.attributes.hint).slice(0, 30) });
    }
    for (const k of Object.keys(node)) if (node[k] && typeof node[k] === 'object') walk(node[k]);
  };
  try { walk(JSON.parse(jsonText)); } catch (_) { /* dump 非 JSON */ }
  return hits;
}
// 多 prefix 行数总和（新建气泡按钮平铺=addRootBubble(node:)/选项卡=addTab——node:+tab: 联合免疫模式差异）
async function nodeCountSum(serial) {
  const cn = await dbCount(serial, 'node:'); const ct = await dbCount(serial, 'tab:');
  if (!cn.ok || !ct.ok) return { ok: false, n: -1, detail: `node=${cn.raw} tab=${ct.raw}` };
  return { ok: true, n: cn.n + ct.n, detail: `node=${cn.n}+tab=${ct.n}` };
}
// settle 轮询：等断言端行数收敛到期望值（同步是异步的，立即断言必撞假红）
async function settleCountEquals(serial, prefix, expectN, timeoutMs, label) {
  const ok = await pollUntil(async () => { const c = await dbCount(serial, prefix); return c.ok && c.n === expectN; }, timeoutMs);
  const c = await dbCount(serial, prefix);
  return { ok: ok && c.ok && c.n === expectN, n: c.ok ? c.n : null, raw: c.raw, label };
}
// 编排前置：角色路由（canUiDump=UI 操作端，其余=数据断言端）+ 双端同步活检查；不符返回 null（用例已如实 log）
// ★ 0.241.0.4：opts.prefer 指定操作端设备 id（如 'phone'——手机操作端用例；指定端不在线/无 UI 通道如实 skip）
//   登录块改 ensureLoginFlow 统一链（三端首页「登录华为账号」，替代边栏头像路径——手机抽屉默认关恒 miss）
async function flowPrep(ctx, opts = {}) {
  const devs = ctx.devices;
  let op = null;
  if (opts.prefer) {
    const p = devs.find((d) => d.id === opts.prefer && canUiDump(d));
    if (!p) { ctx.log('前置', 'skip', `指定操作端 ${opts.prefer} 未勾选/离线/无 UI 通道（手机操作端用例须勾选手机+≥1 台断言端）`); return null; }
    op = p;
  } else op = devs.find((d) => canUiDump(d));
  const asserts = devs.filter((d) => d !== op);
  if (!op) { ctx.log('前置', 'skip', '无 UI 操作端（需 Pad/手机在线——PC 无 UI 自动化通道，dumpLayout 平台限制）'); return null; }
  if (!asserts.length) { ctx.log('前置', 'skip', '需 ≥1 台数据断言端与操作端同时勾选（如 PC+Pad）——单端无法验证跨端传播'); return null; }
  // ★ 0.241.0.5 修复：操作端无条件冷启拉起 app（同步活也必须——上一轮用例/ARKUI-TEST 的 aa test 会把 app
  //   停在桌面/测试态，导航原语对着桌面 dump 必然全 miss；首轮 R20261015120120 实锤「单词库未找到」根因）
  await coldStart(op.serial, 6000);
  // 操作端：协议 + 登录 + 同步活（ensureLoginFlow 内含；同步活兜底=登录询问自动「开启」）
  let oc = await dbCount(op.serial, null);
  if (!(oc.ok && oc.n > 0)) {
    ctx.log('操作端·同步未活→自动登录+开同步', 'info', `${op.label} cloud_data=${oc.ok ? oc.n : oc.raw}——走统一登录链`);
    const lok = await ensureLoginFlow(ctx, op, true); // skipCold=true：flowPrep 已冷启
    if (!lok) return null;
    if (canUiDump(op)) await acceptSyncAsk(op.serial, ctx.log);
    oc = await dbCount(op.serial, null);
  }
  if (!(oc.ok && oc.n > 0)) { ctx.log('操作端·云同步未活', 'fail', `${op.label} cloud_data=${oc.ok ? oc.n : oc.raw} 行——登录后同步应自动开启（0.196.11）；0 行=app 侧同步链路问题（先测后修，报告不修）；若已登录未开同步，先跑 sync-boot 套件 BOOT-LOGIN`); return null; }
  ctx.log('操作端就绪', 'pass', `${op.label} 已登录·cloud_data=${oc.n} 行（同步活）`);
  // 断言端：同步活（app 未开则拉起再查；未登录如实剔除——PC 无 UI 自动登录通道）
  const alive = [];
  for (const d of asserts) {
    let c = await dbCount(d.serial, null);
    if (!(c.ok && c.n > 0)) {
      await sh(d.serial, `aa start -b ${CFG.bundle} -a ${CFG.ability}`);
      await sleep(9000);
      c = await dbCount(d.serial, null);
    }
    if (c.ok && c.n > 0) { alive.push(d); ctx.log(`断言端就绪·${d.label}`, 'pass', `cloud_data=${c.n} 行${d.caps && d.caps.uiDump === false ? '（本机窗口仅断言期间在场，用例结束自动收起）' : ''}`); }
    else ctx.log(`断言端剔除·${d.label}`, 'skip', `cloud_data=${c.ok ? c.n : c.raw}——未登录或同步未开（${d.label} 无 UI 自动登录通道，人工登录一次后重跑本条；其余端继续）`);
  }
  if (!alive.length) { ctx.log('前置', 'skip', '所有断言端同步均未活——本条跳过（不算失败）'); return null; }
  return { op, asserts: alive };
}
// 装机前状态实录（★ 0.229.25 LOGIN-KEEP 前置快照——/api/prep 装机前记录，根治"上一轮 LOGOUT 收尾登出→覆盖装机 KEEP 必 skip"的编排缺陷）
const PREP_STATE = {};

// ============================================================
// 用例矩阵（用户拍板范围：从零登录三入口 + 四域云同步 + 版本核验）
// ============================================================
// ★ 0.229.26 审计违规输出助手（ui-audit 用例共用）
function report2(ctx, list) { for (const v of list) ctx.log(`${v.rule}·${v.where}`, v.level, `期望=${v.expect} | 实际=${v.actual}`); }
// ★ 0.229.26 navTo 导航助手（★0.220.0 边栏折叠适配——首跑实锤：单词库页起边栏折叠为「导航 ›」窄条，
//   导航失败自动点「导航」展开后重试）
async function navTo(serial, text, log) {
  let r = await uiClickText(serial, text, { waitMs: 2200, exact: true });
  if (!r.ok) {
    const exp = await uiClickText(serial, '导航', { waitMs: 1800 });
    if (exp.ok && log) log(`边栏折叠→自动点「导航」展开`, 'info', `已点击 (${exp.x},${exp.y})——0.220.0 折叠态适配，重试「${text}」`);
    if (exp.ok) r = await uiClickText(serial, text, { waitMs: 2200, exact: true });
  }
  return r;
}

// ★ 0.232.0 双击原语（画布气泡双击=进入对话页——0.173 单双击并存判定；uiInput doubleClick）
// ★ 0.233.0.2 修复：`uitest uiInput doubleClick` 原语在 Pad 实测无效（CHAT-KEEP 历史零 pass、
//   三轮 dump 实锤双击后仍停留画布）。改单次 shell 会话内串联两次 click（间隔 150ms=双击窗口内）
async function uiDoubleClick(serial, x, y, waitMs = 2400) {
  const r = await sh(serial, `uitest uiInput click ${x} ${y}; sleep 0.15; uitest uiInput click ${x} ${y}`, 15000);
  await sleep(waitMs);
  return { ok: !SH_ERR_RE.test(r), raw: r.trim().slice(0, 120) };
}

// ============================================================
// ★ 0.241.0.4 三端云同步原语（手机入列·从零引导；全案 docs/0.165+/0.241.0.4）
// ============================================================
// 进画布（三端通用）：首页点「进入气泡树」主按钮（0.179 三端首页同款）；已在画布（信息条「N 个气泡」特征）跳过；
//   不在首页也不在画布（如单词库页）→ Back 回退重试（手机抽屉只在画布——导航必经此步）
async function ensureCanvas(serial, log) {
  let d = await dumpLayout(serial);
  if (d.ok && d.text.includes('个气泡')) { if (log) log('已在画布', 'pass', '信息条「N 个气泡」特征命中——跳过导航'); return true; }
  if (d.ok && !d.text.includes('进入气泡树')) {
    for (let i = 0; i < 3; i++) {
      if (log) log('返回画布·Back 回退', 'info', '当前不在首页/画布（子页面）——Back 回退重试');
      await sh(serial, `uitest uiInput keyEvent Back`, 15000);
      await sleep(1400);
      d = await dumpLayout(serial);
      if (d.ok && (d.text.includes('个气泡') || d.text.includes('进入气泡树'))) break;
    }
  }
  if (d.ok && d.text.includes('个气泡')) return true;
  const btn = await uiClickText(serial, '进入气泡树', { waitMs: 2800 });
  if (log) log('进画布·点「进入气泡树」', btn.ok ? 'pass' : 'fail', btn.ok ? `已点击 (${btn.x},${btn.y})（0.179 首页主按钮，三端同款）` : (btn.err || '首页未找到主按钮'));
  return btn.ok;
}
// 手机抽屉唤出（幂等）：抽屉开=dump 可见边栏项「单词库」；未开=点画布左下角抽屉按钮
//   （BBTreeCanvas:1532 `!isTablet` 渲染：40×40 sidebar.svg + padding4 容器≈48vp，position x=14/y=viewH-68——
//    dump 启发式=左下角区域 x<30%W、y>66%H 内 40~150px 的无文字 Image；屏幕宽高=dump 全树最大 bounds 近似）
async function openPhoneDrawer(serial, log) {
  const d0 = await dumpLayout(serial);
  if (!d0.ok) return { ok: false, err: 'dumpLayout 失败' };
  if (d0.text.includes('单词库') && d0.text.includes('知识库')) { if (log) log('抽屉已开', 'pass', '边栏项「单词库/知识库」可见——跳过唤出'); return { ok: true }; }
  const cands = []; let W = 0, H = 0;
  const walk = (node) => {
    if (!node || typeof node !== 'object') return;
    const a = node.attributes || {};
    const m = String(a.bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
    if (m) { W = Math.max(W, +m[3]); H = Math.max(H, +m[4]); }
    if (String(a.type || '').toLowerCase() === 'image' && !String(a.text || '').trim() && m) {
      cands.push({ x: Math.round((+m[1] + +m[3]) / 2), y: Math.round((+m[2] + +m[4]) / 2), x1: +m[1], y1: +m[2], w: +m[3] - +m[1], h: +m[4] - +m[2] });
    }
    for (const k of Object.keys(node)) if (node[k] && typeof node[k] === 'object') walk(node[k]);
  };
  try { walk(JSON.parse(d0.text)); } catch (_) { return { ok: false, err: 'dump 非 JSON' }; }
  const zone = cands.filter((c) => c.x1 < W * 0.3 && c.y1 > H * 0.66 && c.w >= 40 && c.w <= 150 && c.h >= 40 && c.h <= 150)
    .sort((a, b) => a.x1 - b.x1);
  if (!zone.length) return { ok: false, err: `左下角未找到抽屉按钮候选（W=${W} H=${H}，Image 候选 ${cands.length} 个均出界）——盯屏校准 /api/dump?dev=phone` };
  const t = zone[0];
  const r = await sh(serial, `uitest uiInput click ${t.x} ${t.y}`, 15000);
  await sleep(1800);
  const d1 = await dumpLayout(serial);
  const opened = d1.ok && d1.text.includes('单词库') && d1.text.includes('知识库');
  if (log) log('点左下角抽屉按钮', opened ? 'pass' : 'fail', `已点击 (${t.x},${t.y})（启发式：左下角 ${t.w}×${t.h}px Image）——${opened ? '抽屉已开' : '抽屉未开（坐标偏差——盯屏校准）'}`);
  return { ok: opened, raw: r.trim().slice(0, 100) };
}
// 手机导航（抽屉版 navTo）：ensureCanvas → openPhoneDrawer → 点目标边栏项
async function navToM(serial, text, log) {
  const c = await ensureCanvas(serial, log);
  if (!c) return { ok: false, err: '进画布失败（导航链断）' };
  const dr = await openPhoneDrawer(serial, log);
  if (!dr.ok) return { ok: false, err: dr.err || '抽屉未开' };
  return await uiClickText(serial, text, { waitMs: 2600 });
}
// 通用导航分流：手机=抽屉（navToM）/ Pad=常驻边栏（navTo 自带 0.220.0 折叠展开适配）——0.241.0.4 手机操作端用
async function navAnywhere(dev, serial, text, log) {
  if (dev.id === 'phone') return await navToM(serial, text, log);
  return await navTo(serial, text, log);
}
// ★ 登录后云同步询问·主动开启（BOOT 引导专用——与 dismissLoginDialogs「暂不开启」测试隔离语义互补）
// ★ 0.241.0.5 堆叠修复（首轮真机实锤 R20261015105027：先点「开启云同步」时它常在 30 天试用弹窗【下层】，
//   坐标点击被上层弹窗全屏遮罩拦截=点空，开关滞留 false）——改 findTopmostButton 最上层优先逐层清：
//   每轮取「开启云同步/知道了」树序最后命中（=最上层弹窗的按钮）点它，上层清完下层自然露出；系统权限弹窗独立处理
async function acceptSyncAsk(serial, log) {
  let opened = false, allowed = false, knowed = 0;
  for (let i = 0; i < 10; i++) {
    const d = await dumpLayout(serial);
    if (!d.ok) break;
    if (d.text.includes('附近的设备')) {
      const allow = findNodeBoundsAll(d.text, '允许').filter((h) => h.text === '允许');
      const t = allow.length ? allow[allow.length - 1] : null;
      if (t) { await sh(serial, `uitest uiInput click ${t.x} ${t.y}`, 15000); if (log) log('系统权限·自动点「允许」', 'pass', `已点击 (${t.x},${t.y})（发现和连接附近的设备——同步所需，系统弹窗在所有 app 弹窗之上）`); allowed = true; await sleep(1500); continue; }
    }
    const b = findTopmostButton(d.text, ['开启云同步', '知道了']);
    if (!b) break;
    if (b.text === '开启云同步') opened = true;
    else knowed++;
    await sh(serial, `uitest uiInput click ${b.x} ${b.y}`, 15000);
    if (log) log(b.text === '开启云同步' ? '云同步询问·自动点「开启云同步」（最上层）' : '30天试用·自动点「知道了」（最上层）', 'pass', `已点击 (${b.x},${b.y})——逐层清弹窗，上层优先防遮罩拦截`);
    await sleep(1500);
  }
  return { opened, allowed, knowed };
}
// ★ PC 多屏注入点击（0.229.25 实证通道固化：`dumpLayout -d <disp>` 定向 dump（dumpAuditNodes 已限 app 子树）
//   + `uitest uiInput click x y <disp>` 多屏注入；窗口所在屏漂移=15→0 双屏尝试兜底）
async function pcClickText(serial, keyword, opts = {}) {
  const disps = opts.displayId !== undefined ? [opts.displayId] : [15, 0];
  for (const disp of disps) {
    const d = await dumpAuditNodes(serial, disp);
    if (!d.ok || !d.nodes.length) continue;
    let hits = d.nodes.filter((n) => String(n.text || '').includes(keyword));
    if (opts.exact) hits = hits.filter((n) => String(n.text) === keyword);
    if (!hits.length) continue;
    const b = opts.pick === 'last' ? hits[hits.length - 1] : hits[0];
    const r = await sh(serial, `uitest uiInput click ${Math.round(b.xc)} ${Math.round(b.yc)} ${disp}`, 15000);
    await sleep(opts.waitMs || 1600);
    return { ok: !SH_ERR_RE.test(r), x: Math.round(b.xc), y: Math.round(b.yc), disp, text: String(b.text).slice(0, 30), raw: r.trim().slice(0, 120) };
  }
  return { ok: false, err: `PC 两屏（${disps.join('/')}）app 子树内未找到含「${keyword}」控件${opts.exact ? '（精确）' : ''}——窗口可能在别的屏或文案变化，盯屏 /api/dump?dev=pc` };
}
// ★ 0.266.0.1：华为账号认证协议门禁自动同意（0.264.0 门禁拆分的测试台配套遗留——
//   点「登录华为账号」后 app 先弹 hw 形态 AgreementDialog「华为账号登录/同意并登录」，
//   不点掉它授权页永不拉起、checkpoint 必 180s 假超时；hwAgreed 持久化同意一次不再弹，
//   本函数幂等「有则点之」，已同意设备零打扰）
async function hwAgreeIfAny(dev, serial, log) {
  const isPc = !canUiDump(dev);
  if (isPc) {
    // PC 双屏通道：两屏子树找「同意并登录」（pcClickText 自带 contains 匹配）
    const c = await pcClickText(serial, '同意并登录', { waitMs: 2200 });
    if (c.ok) { if (log) log('华为协议门禁·自动点「同意并登录」', 'pass', `已点击 (${c.x},${c.y})@屏${c.disp}（0.264.0 登录前单独征求；同意一次不再弹）`); return true; }
    return false; // 未弹出=已同意过，正常
  }
  const d = await dumpLayout(serial);
  if (!d.ok || !d.text.includes('同意并登录')) return false;
  const c = await uiClickText(serial, '同意并登录', { exact: true, waitMs: 2200 });
  if (log) log('华为协议门禁·自动点「同意并登录」', c.ok ? 'pass' : 'fail', c.ok ? `已点击 (${c.x},${c.y})（0.264.0 登录前单独征求；同意一次不再弹）` : (c.err || '点击失败'));
  return c.ok;
}
// ★ 统一登录引导（三端）：coldStart → 协议模态自动同意 → 点首页「登录华为账号」（三端首页账号卡同款，
//   Index.ets:589——手机无首页勾选框走协议模态放行路径已由 agreeDialogIfAny 覆盖）→
//   唯一人工=华为授权页（checkpoint 自动探测；'华为账号已登录'含子串'已登录'，dumpCountText 三端通用）→
//   收尾 dismissLoginDialogs（BOOT 场景由调用方接 acceptSyncAsk 主动开启）
async function ensureLoginFlow(ctx, dev, skipCold) {
  const serial = dev.serial;
  const isPc = !canUiDump(dev);
  if (!skipCold) await coldStart(serial, 6000); // ★ skipCold：flowPrep 等调用方已冷启过（重复 force-stop 白耗 8s）
  const ag = await agreeDialogIfAny(serial, ctx.log);
  if (ag.agreed) ctx.log('协议模态·自动同意', ag.ok ? 'pass' : 'fail', ag.ok ? '勾选+「同意并继续」+「暂不加入」体验改进 全自动完成（fresh 首启路径）' : '同意点击未生效');
  else ctx.log('协议已同意（无模态）', 'info', '覆盖安装/此前已同意——直接登录');
  if (isPc) {
    const loginOk = (await grepPref(serial, 'huawei-account')).found; // ★ 0.241.0.5：登录态=持久化通道（cloud_data 是同步活≠登录态——PC 已登录但同步未开时误走登录分支找不到按钮）
    if (loginOk) { ctx.log('PC 已登录（huawei-account 落盘）', 'pass', '跳过登录——同步未活由设置页自愈链接管'); return true; }
    const c0 = await dbCount(serial, null);
    if (c0.ok && c0.n > 0) { ctx.log('PC 已登录+同步活', 'pass', `cloud_data=${c0.n} 行——跳过登录`); return true; }
    const b = await pcClickText(serial, '登录华为账号', { exact: true, waitMs: 2500 });
    ctx.log('① 点首页「登录华为账号」（PC 多屏通道）', b.ok ? 'pass' : 'fail', b.ok ? `已点击 (${b.x},${b.y})@屏${b.disp}（0.229.25 实证通道固化）` : (b.err || ''));
    if (!b.ok) return false;
    // ★ 0.266.0.1：华为协议门禁（0.264.0 拆分）——fresh 首登会弹，不点掉授权页不来
    await hwAgreeIfAny(dev, serial, ctx.log);
  } else {
    const n0 = (await dumpCountText(serial, '已登录')).n;
    if (n0 >= 1) { ctx.log('已登录', 'pass', '首页「华为账号已登录」——跳过登录（fresh 场景跑 BOOT 前应未登录）'); return true; }
    const b = await uiClickText(serial, '登录华为账号', { exact: true, waitMs: 2500 });
    ctx.log('① 点首页「登录华为账号」', b.ok ? 'pass' : 'fail', b.ok ? `已点击 (${b.x},${b.y})（三端首页账号卡同款）` : (b.err || ''));
    if (!b.ok) return false;
    // 手机/协议未同意路径：点登录弹协议模态（pendingAction=login）——同意后续跑授权
    const d1 = await dumpLayout(serial);
    if (d1.ok && d1.text.includes('同意并继续')) {
      const ag2 = await agreeDialogIfAny(serial, ctx.log);
      if (ag2.agreed && ag2.ok) ctx.log('② 协议模态自动同意续跑登录', 'pass', 'pendingAction=login 续跑拉华为授权（0.226.0 手机路径）');
    }
    // ★ 0.266.0.1：华为协议门禁（0.264.0 拆分）——基础协议同意后/已同意态点登录，还会弹华为协议征求
    await hwAgreeIfAny(dev, serial, ctx.log);
  }
  const r = await ctx.checkpoint({ label: `【人工仅授权·请看 ${dev.label}】测试台已自动点完协议与「登录华为账号」。静默授权零点击；若弹华为授权页点「同意并继续」（有「阅读并同意」勾选框先勾再点）`, deviceId: dev.id,
    detect: isPc ? (async () => (await grepPref(serial, 'huawei-account')).found) // ★ 0.241.0.5：PC 登录态探测改持久化通道——cloud_data 是"同步活"不是"登录态"（首轮实锤：登录成功但同步未开=0 行恒不通过→180s 假超时）
      : (async () => (await dumpCountText(serial, '已登录')).n >= 1) });
  if (r.state === 'timeout') { ctx.log('人工授权', 'fail', '180s 内未完成授权（华为授权页未点同意）'); return false; }
  ctx.log('② 华为授权完成', 'pass', r.auto ? '自动确认（静默授权零点击·全程无人工）' : '用户确认完成');
  return true;
}
// ★ 0.241.0.5 编辑器保存·键盘遮挡处置（0.229.25 遗留坑——inputText 注入后软键盘把「保存」顶出 dump 可视区，
//   R20261015120525 实锤单词编辑器同病）：先直找「保存」→找不到点编辑器标题收键盘（点输入框外收键盘 0.182.x；
//   禁用 keyEvent Back——B9 返回键会直接关编辑器丢输入）
async function saveEditorSafe(serial, ctx, editorTitle) {
  let sv = await uiClickText(serial, '保存', { exact: true, waitMs: 1600 });
  if (sv.ok) { ctx.log('④ 点「保存」', 'pass', `已点击 (${sv.x},${sv.y})`); return sv; }
  const t = await uiClickText(serial, editorTitle, { exact: true, waitMs: 1200 });
  ctx.log('④ 保存被键盘遮挡→点「' + editorTitle + '」标题收键盘', t.ok ? 'info' : 'warn', t.ok ? `已点击 (${t.x},${t.y})（点输入框外收键盘，Back 会误关编辑器）` : (t.err || ''));
  if (t.ok) {
    await sleep(1500);
    sv = await uiClickText(serial, '保存', { exact: true, waitMs: 1600 });
  }
  ctx.log('④ 点「保存」', sv.ok ? 'pass' : 'fail', sv.ok ? `已点击 (${sv.x},${sv.y})（键盘已收，保存回屏）` : (sv.err || '仍不可见——盯屏 /api/dump 校准'));
  return sv;
}
// ★ 0.241.0.5 分布式同步权限 CLI 预授权（PC 首轮 BOOT-LOGIN 三连败终案：DISTRIBUTED_DATASYNC grantStatus=-1——
//   系统权限弹窗在 PC 双屏环境未被允许（弹窗不可见/被焦点窗口吞），requestPermissionsFromUser 恒拒 → 开关恒 false。
//   0.223.1 方法论「atm perm -g 可给 debug hap 预授权」：动态取 tokenId → 查 grantStatus → 非 0 则预授权（幂等无害）。
//   预授权后 requestPermissionsFromUser 直接 granted 不弹窗——UI 设备同样受益（少一个弹窗变量）
async function ensureSyncPerm(serial, log) {
  try {
    const dumpOut = await sh(serial, `atm dump -t token-info -b ${CFG.bundle}`, 15000);
    const tid = (dumpOut.match(/"tokenID": (\d+)/) || [])[1];
    if (!tid) { if (log) log('权限预授权·tokenId 获取', 'warn', 'atm dump 未取到 tokenID（设备工具链差异）——跳过预授权，走弹窗路径'); return { ok: false }; }
    const granted = /DISTRIBUTED_DATASYNC[\s\S]{0,80}?"grantStatus": 0/.test(dumpOut);
    if (granted) { if (log) log('权限预授权·已授权', 'pass', `tokenID=${tid} DISTRIBUTED_DATASYNC grantStatus=0——无需处理`); return { ok: true }; }
    const r = await sh(serial, `atm perm -g -i ${tid} -p ohos.permission.DISTRIBUTED_DATASYNC`, 15000);
    const okNow = /Success/i.test(r);
    if (log) log('权限预授权·atm perm -g', okNow ? 'pass' : 'warn', `tokenID=${tid} → ${r.trim().slice(0, 80)}${okNow ? '（后续 requestPermissionsFromUser 直接 granted 不弹窗——PC 双屏系统弹窗不可靠的根治）' : '（预授权未成功——保留系统弹窗路径兜底）'}`);
    return { ok: okNow };
  } catch (e) { if (log) log('权限预授权·异常', 'warn', String(e).slice(0, 80)); return { ok: false }; }
}
// ★ 0.241.0.5 设置页开同步自愈链（真实用户路径：边栏/抽屉「设置」→云同步 Tab→「开启云同步」→系统权限「允许」）——
//   适用于「已登录但登录询问弹窗已错过」的存量态（首轮 acceptSyncAsk 点空/用户手动关过弹窗）：此时弹窗不会再弹，
//   唯一正路=设置页手动开。已登录点「开启云同步」不再弹登录引导（0.196.10 只拦未登录）直接开。
async function openSyncViaSettings(ctx, dev) {
  const serial = dev.serial;
  const isPc = !canUiDump(dev);
  await ensureSyncPerm(serial, ctx.log); // ★ 点「开启云同步」前先 CLI 预授权——PC 双屏系统弹窗不可靠的根治
  const click = isPc ? (kw, o) => pcClickText(serial, kw, o) : (kw, o) => uiClickText(serial, kw, o);
  const s1 = isPc ? await click('设置', { waitMs: 2200 }) : await navAnywhere(dev, serial, '设置', ctx.log);
  ctx.log('自愈① 「设置」入口', s1.ok ? 'pass' : 'fail', s1.ok ? `已点击 (${s1.x},${s1.y})——全局设置弹窗${dev.id === 'phone' ? '（抽屉内入口）' : ''}` : (s1.err || ''));
  if (!s1.ok) return false;
  const s2 = await click('云同步', { waitMs: 2000 });
  ctx.log('自愈② 「云同步」Tab', s2.ok ? 'pass' : 'fail', s2.ok ? `已点击 (${s2.x},${s2.y})` : (s2.err || ''));
  if (!s2.ok) return false;
  const s3 = await click('开启云同步', { waitMs: 2500 });
  ctx.log('自愈③ 「开启云同步」', s3.ok ? 'pass' : 'fail', s3.ok ? `已点击 (${s3.x},${s3.y})（已登录不再弹登录引导，直接开）` : (s3.err || '可能已开启'));
  if (!s3.ok) return false;
  await sleep(2500);
  // 系统权限弹窗（首次开同步才弹；已授权过则跳过）
  if (!isPc) {
    const d = await dumpLayout(serial);
    if (d.ok && d.text.includes('附近的设备')) {
      const s5 = await uiClickText(serial, '允许', { pick: 'last', waitMs: 2500 });
      ctx.log('自愈④ 系统弹窗·「允许」', s5.ok ? 'pass' : 'fail', s5.ok ? `已点击 (${s5.x},${s5.y})` : (s5.err || ''));
    } else ctx.log('自愈④ 系统权限弹窗未出现', 'info', '此前已授权（仅首次开同步弹）');
  } else {
    const d = await dumpAuditNodes(serial, 15);
    if (d.ok && d.nodes.some((n) => String(n.text || '').includes('附近的设备'))) await pcClickText(serial, '允许', { exact: true, pick: 'last', waitMs: 2000 });
  }
  return true;
}

// ★ 0.232.0 读持久化字段值（persistent_storage 实为 XML <preferences>：值内嵌 JSON 且 HTML 实体转义
//   \&quot; ——2026-10-14 手机实测格式；grep 宽窗多行 → 逐行去实体转义后正则提值，取首个 ≥8 长真值
//   （v2/v3 两代 key 块并存，旧块空值跳过）；与 grepPref 同通道，返回 value 供 TTS-API 用）
async function prefField(serial, field) {
  for (const p of PREF_CANDIDATES) {
    const full = `${CFG.sandboxBase}/${p}`;
    const out = await sh(serial, `grep -o '${field}'.\\{0,120\\}' '${full}' 2>/dev/null | head -4`, 15000);
    if (out.trim() !== '') {
      for (const lineRaw of out.split('\n')) {
        const line = lineRaw.replace(/&quot;/g, '"').replace(/&amp;/g, '&').replace(/\\\\/g, '');
        const m = line.match(new RegExp(field + '[\\\\": ]+([A-Za-z0-9_\\-./]+)'));
        if (m && m[1].length >= 8) return { found: true, value: m[1], raw: lineRaw.trim().slice(0, 300) };
      }
      return { found: true, value: '', raw: out.trim().slice(0, 300) };
    }
  }
  return { found: false, value: '' };
}

// ★ 0.232.0 服务端直打 openspeech 云端 TTS（与 App CloudTtsEngine 同协议——含 55000000
//   合成音色资源未开通→官方音色回退；2026-10-13 本机 curl 实证协议）
async function probeCloudTts(key, model, voice) {
  const https = require('https');
  const endpoint = 'https://openspeech.bytedance.com/api/v3/tts/unidirectional';
  const call = (spk) => new Promise((resolve) => {
    const body = JSON.stringify({ req_params: { text: '测试朗读。', speaker: spk, audio_params: { format: 'mp3', sample_rate: 24000 } } });
    const u = new URL(endpoint);
    const req = https.request({
      hostname: u.hostname, path: u.pathname, method: 'POST', timeout: 30000,
      headers: {
        'Content-Type': 'application/json', 'X-Api-Key': key, 'X-Api-Resource-Id': model,
        'X-Api-Request-Id': 'test-' + Date.now() + '-' + Math.floor(Math.random() * 1000)
      }
    }, (res) => {
      let buf = '';
      res.on('data', (c) => { buf += c; });
      res.on('end', () => resolve({ status: res.statusCode, body: buf }));
    });
    req.on('error', (e) => resolve({ status: 0, body: String(e.message) }));
    req.on('timeout', () => { req.destroy(); resolve({ status: 0, body: 'timeout' }); });
    req.write(body); req.end();
  });
  const okBody = (r) => r.status === 200 && /"code"\s*:\s*0/.test(r.body) && /"data"\s*:/.test(r.body);
  let r = await call(voice);
  let usedVoice = voice, fallback = false, first = '';
  const code = Number((r.body.match(/"code"\s*:\s*(-?\d+)/) || [])[1]);
  if (r.status === 200 && code === 55000000 && voice.startsWith('S_')) {
    first = r.body.slice(0, 150);
    const r2 = await call('zh_female_vv_uranus_bigtts');
    return { ok: okBody(r2), fallback: true, usedVoice: 'zh_female_vv_uranus_bigtts', first, body: r2.body.slice(0, 150) };
  }
  return { ok: okBody(r), fallback, usedVoice, first, body: r.body.slice(0, 150) };
}
// ---------- ★ 0.235.0 划词两用例共用助手 ----------
// 进对话页：冷启 → 画布 → 双击「N条对话」气泡（复刻 CHAT-KEEP ⓪①② 链路，返回 false=前置失败已记 log）
async function navIntoChat(ctx, serial) {
  let nav = await uiClickText(serial, '气泡树', { waitMs: 2200 });
  if (!nav.ok) nav = await uiClickText(serial, '进入气泡树', { waitMs: 2600 });
  if (!nav.ok) {
    await sh(serial, `uitest uiInput keyEvent Back`, 15000);
    await sleep(1500);
    nav = await uiClickText(serial, '气泡树', { waitMs: 2200 });
  }
  if (!nav.ok) { ctx.log('⓪ 进入气泡树画布', 'fail', '「气泡树」与「进入气泡树」均未命中（可能已在画布或首页改版）'); return false; }
  ctx.log('⓪ 进入气泡树画布', 'pass', `已点击 (${nav.x},${nav.y})`);
  const d = await dumpLayout(serial);
  // ★ 0.235.0.1：取最后一个命中会撞画布信息条「N 个气泡 · N 条对话」（树序在气泡卡之后，双击它=点空）——
  //   排除含「个气泡」的信息条，只留气泡卡「N 条对话 · X前」
  //   ★ 0.235.2.1：再排除「0 条对话」空气泡（R20261014144610 实锤：SYNC-FLOW 遗留空气泡被取 last 命中，
  //   双击进空对话页→无正文→后续全 fail）——只进有对话的气泡
  const hits = findNodeBoundsAll(d.text, '条对话').filter((h) => !String(h.text).includes('个气泡') && !String(h.text).startsWith('0 条对话'));
  if (!hits.length) { ctx.log('① 定位有对话的气泡', 'fail', '画布未见「N条对话」气泡卡（信息条已排除）——先在某气泡发一条消息再跑本用例'); return false; }
  const target = hits[hits.length - 1];
  ctx.log('① 定位有对话的气泡', 'pass', `(${target.x},${target.y})「${String(target.text).slice(0, 24)}」`);
  await uiDoubleClick(serial, target.x, target.y);
  await sleep(2200);
  const dc = await dumpLayout(serial);
  const ok = /"text":\s*"\d+ 条对话"/.test(dc.text) || dc.text.includes('暂无对话');
  ctx.log('② 双击进入对话页', ok ? 'pass' : 'fail', ok ? '对话页标题特征命中（顶栏「N 条对话」无时间后缀）' : '双击后仍在画布（双击未生效）');
  return ok;
}
// 消息正文定位：app 窗口子树内取「文本最长」的可见节点（AI 回复正文天然最长；顶栏/按钮/提示均为短文本；
// 输入框 placeholder 在 attributes.hint 不在 text）——CHROME 排除 UI 骨架文案防误取
function pickBodyTextNode(nodes) {
  const CHROME = ['条对话', '输入问题', '发送', '返回', '气泡', '朗读', '刷新', '条回复', '个模型'];
  let best = null;
  for (const n of nodes) {
    const t = String(n.text || '').trim();
    if (t.length < 12) continue;
    if (CHROME.some((k) => t.includes(k))) continue;
    if (!best || t.length > String(best.text || '').length) best = n;
  }
  return best;
}
// ---------- ★ 0.239.0 kbview 套件助手（KB-VIEW/KB-PLUS/WB-PLUS 共用） ----------
// 顶栏 ＋ 按钮 Text 节点（exact '+'）
function o0plus(nodes) {
  const hits = nodes.filter((n) => String(n.text || '').trim() === '+');
  return hits.length ? hits[0] : null;
}
// 排序文字右缘与＋左缘之间的 20vp 图标（w 30~80px 覆盖 1.5~3.5 密度；左一枚=视图切换）
function o0icons(nodes, sortNode, plusNode) {
  return nodes.filter((n) => String(n.type || '').toLowerCase() === 'image'
    && n.x > sortNode.x2 && n.x2 < plusNode.x && Math.abs(n.yc - sortNode.yc) < 40 && n.w >= 30 && n.w <= 80)
    .sort((a, b) => a.x - b.x);
}
// 网格多列判定：复习状态小字里存在「同一横带（yc 差<60px）且横向错开（x 差>150px）」的两条=多列铁证
function gridColsOf(d) {
  const labels = d.nodes.filter((n) => /^(未学习|需复习|下次复习：)/.test(String(n.text || '').trim()));
  let multi = false; let pair = '';
  outer:
  for (let i = 0; i < labels.length; i++) {
    for (let j = i + 1; j < labels.length; j++) {
      if (Math.abs(labels[i].yc - labels[j].yc) < 60 && Math.abs(labels[i].x - labels[j].x) > 150) {
        multi = true; pair = `(${Math.round(labels[i].x)},${Math.round(labels[i].yc)})↔(${Math.round(labels[j].x)},${Math.round(labels[j].yc)})`;
        break outer;
      }
    }
  }
  return { labels: labels.length, multi, pair };
}
// ---------- ★ 0.244.0 云同步陈旧渲染双 bug 回归（NODE-LAYOUT / NODE-CHILD-INTACT 共用助手） ----------
// 修前实锤（2026-10-16 手机复现全链）：聊天页 ＋/划词新建子气泡 → 云同步 reconcile 在页面隐藏期
//   refreshWorkspaceFromPools 整体替换 store.nodeList（全新对象）→ 画布 ForEach 稳定 nodeID key 复用条目、
//   条目闭包持有旧对象 → 返回画布后渲染冻结在创建随机偏移坐标（气泡重叠+连线悬空=用户 bug2；
//   重叠遮挡下点错气泡进错对话=用户 bug3「父回复搬进子气泡/父气泡重新生成」）。
// 0.244.0 修法：BubbleTree.rebuildEpoch 渲染世代（nodeList 整体替换/重排处 +1）+ ForEach key 拼入 epoch。
// ＋按钮定位：输入框（hint=输入问题）左侧的近方形无文字容器（w/h 55~140、右缘贴输入框左缘）
function findChatPlusBtn(d) {
  const input = d.nodes.find((n) => String(n.hint || '').includes('输入问题'));
  if (!input) return null;
  const cands = d.nodes.filter((n) => !String(n.text || '').trim()
    && n.w >= 55 && n.w <= 140 && n.h >= 55 && n.h <= 140
    && n.x2 <= input.x + 16 && Math.abs(n.yc - input.yc) < 70);
  if (!cands.length) return null;
  return cands.sort((a, b) => b.x2 - a.x2)[0]; // 最右一枚=＋（gitbranch 图标容器）
}
  // 气泡卡收集：含「N 条对话」或「双击进入」（当前选中态的元信息行替代文案——0.244.0.1 首跑实锤：
  // 新建子气泡=当前选中卡，元信息行显示「双击进入」而非「N 条对话」，漏锚=卡数断言假红）文本
  // （排除信息条「个气泡」）的最内层无文字容器（卡矩形——重叠断言基准）
  // ★ 卡矩形≠文本矩形：修前重叠时两卡文本行互相错开（文本级断言会漏检），必须用卡容器矩形两两判交
  function bubbleCardsOf(d) {
    const metas = d.nodes.filter((n) => (String(n.text || '').trim() === '双击进入' || /条对话/.test(String(n.text || '')) && !String(n.text).includes('个气泡')));
  const cards = [];
  for (const m of metas) {
    const holders = d.nodes.filter((n) => !String(n.text || '').trim()
      && n.w >= 90 && n.w <= 520 && n.h >= 36 && n.h <= 200
      && (n.w / n.h) >= 1.6 && (n.w / n.h) <= 3.6
      && m.x >= n.x && m.x2 <= n.x2 && m.y >= n.y && m.y2 <= n.y2);
    if (!holders.length) continue;
    holders.sort((a, b) => (a.w * a.h) - (b.w * b.h)); // 最小含者=最内层卡
    const c = holders[0];
    if (!cards.some((k) => k.x === c.x && k.y === c.y)) cards.push(c);
  }
  return cards;
}
// 清理：删除「双击进入」徽标所在气泡（当前选中=测试新建的子气泡）——长按→删除气泡→确认
async function deleteBadgeBubble(ctx, serial, tag) {
  const d = await dumpAuditNodes(serial);
  const badge = d.nodes.find((n) => String(n.text || '').trim() === '双击进入');
  if (!badge || !d.ok) { ctx.log('⑧ 清理·删除测试子气泡', 'warn', '未见「双击进入」徽标（当前无选中或已删）——人工核对画布'); return; }
  const card = bubbleCardsOf(d).find((c) => badge.x >= c.x && badge.x2 <= c.x2 && badge.y >= c.y && badge.y2 <= c.y2);
  const px = card ? Math.round(card.xc) : Math.round(badge.xc);
  const py = card ? Math.round(card.yc) : Math.round(badge.yc);
  await uiLongPress(serial, px, py, 1600);
  const dm = await uiClickText(serial, '删除气泡', { exact: true, waitMs: 2500 });
  if (!dm.ok) { ctx.log('⑧ 清理·删除测试子气泡', 'warn', `长按 (${px},${py}) 菜单未弹出——人工删除（dump 已存证 ${tag}）`); return; }
  await sleep(1000);
  const cf = await uiClickText(serial, '删除', { exact: true, waitMs: 2500 });
  await sleep(1500);
  ctx.log('⑧ 清理·删除测试子气泡', cf.ok ? 'pass' : 'warn', cf.ok ? `已删（长按 ${px},${py}→删除气泡→确认）——画布恢复测试前状态` : '确认按钮未命中——人工删除（不影响断言结论）');
}

const CASES = [
  // ---------- 功能⓪ 版本核验（用户需求 1/2：移到最上面，最先可见、可单独秒跑） ----------
  { id: 'VERSION', suite: 'version', name: '装机版本核验（假成功防线·显示真身）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0];
      const v = await bmVersionCode(dev.serial);
      // ★ 0.229.17：期望值=EXPECTED_VC（app.json5 自动跟读，回退 config）——APP 发版自动跟上，永不误报
      ctx.log(`${dev.label} versionCode`, v.ok ? (v.code === EXPECTED_VC ? 'pass' : 'fail') : 'fail',
        v.ok ? `实际=${v.code} 期望=${EXPECTED_VC}（跟读 app.json5）` : `bm dump 失败：${v.raw}`);
    } },

  // ---------- 功能① 账号登录（每设备各跑一遍；★ 0.229.23 基线对齐：每条用例写明【前置状态→真实步骤→预期表现】） ----------
  { id: 'LOGIN-STATE', suite: 'login', name: '基线·冷启后三入口均未登录（后续登录用例的统一起点）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      const started = await coldStart(serial);
      ctx.log('冷启动（force-stop 后重启）', started ? 'pass' : 'fail', started ? 'aa start 成功' : 'aa start 失败');
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '三入口未登录基线'); }
      else {
        // ★ 0.229.24 基线不消耗零状态：首启模态点「暂不同意」回到首页（真实用户 dismiss 行为）——
        //   旧版点「同意并继续」会把协议态翻成已同意，后面 LOGIN-AGREE（需未同意态）永远测不到拦截
        const d0 = await dumpLayout(serial);
        if (d0.ok && d0.text.includes('同意并继续')) {
          const rj = await uiClickText(serial, '暂不同意', { waitMs: 1500 });
          ctx.log('首启协议模态·自动点「暂不同意」', rj.ok ? 'pass' : 'fail', rj.ok ? `已点击 (${rj.x},${rj.y})——dismiss 回首页，协议保持未同意（零状态留给 LOGIN-AGREE 测拦截）` : (rj.err || '点击失败'));
        } else ctx.log('首启协议模态未出现', 'info', '协议已同意或已 dismiss——直接取基线');
        const d = await ctx.art.dump(`LOGIN-STATE-${dev.id}`, 'dump-cold.json', serial);
        const nLogin = (d.text.match(/未登录/g) || []).length;
        ctx.log('★三入口「未登录」基线', nLogin >= 1 ? 'pass' : 'fail',
          `dumpLayout 命中未登录×${nLogin}（目的：确认起点干净——防止上一轮登录残留污染后面三入口用例的判断）`);
      }
      const h = await hilogErrors(serial);
      ctx.log('启动 hilog 无错误', h.ok ? (h.n === 0 ? 'pass' : 'fail') : 'warn', h.ok ? `ERROR 计数=${h.n}` : 'hilog 读取异常');
    } },
  // ★ 0.229.23 假绿根治（基线对齐）：真实拒绝路径 = 首启模态点「暂不同意」→ 未勾选协议点登录 → app 必须拦住。
  //   旧流程"先自动同意协议再不勾选点登录"根本没触发门禁——app 真实逻辑（Index.ets onHomeAccountClick）：
  //   全局同意后 needsAgreement()=false，首页勾选框直接隐藏、点登录直接拉华为授权，"未登录"断言恒真=假绿。
  { id: 'LOGIN-AGREE', suite: 'login', name: '协议门禁·未同意点登录必被拦截（全自动：真实拒绝路径，测合规红线）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '协议门禁（UI 断言专属，PC 无 UI 通道）'); return; }
      await coldStart(serial);
      ctx.log('前置状态', 'info', '协议未同意+未登录（0.226.0 合规：未同意只拦登录与云同步，本地功能不受影响）');
      // ① 首启协议模态（未同意时每次冷启必弹）→ 复刻真实用户点「暂不同意」回到首页
      const d0 = await dumpLayout(serial);
      if (d0.ok && d0.text.includes('同意并继续')) {
        const rj = await uiClickText(serial, '暂不同意', { waitMs: 1500 });
        ctx.log('① 协议弹窗·自动点「暂不同意」', rj.ok ? 'pass' : 'fail', rj.ok ? `已点击 (${rj.x},${rj.y})——复刻真实用户拒绝路径` : (rj.err || '点击失败'));
      } else if (d0.ok && !d0.text.includes('我已阅读并同意')) {
        // ★ 0.229.24 前置状态守卫（基线对齐）：无模态且首页勾选框也不显示=协议已是同意态——点登录会被正常放行（app 正确行为），
        //   此态测不了"拦截"——如实 skip（须「全新安装」模式重置协议后再跑），不虚构断言
        ctx.log('★前置状态不符', 'skip', '协议已是同意态（无模态、首页勾选框不显示）——点登录将直接拉华为授权（app 正确行为）。本用例须「全新安装」模式跑（fresh 重置协议）');
        return;
      } else ctx.log('① 协议弹窗未出现', 'info', '协议此前已被拒（未同意但模态已手动关过）——继续直接测首页登录按钮门禁');
      // ② 未勾选协议（首页勾选框保持未勾）直接点登录
      const btn = await uiClickText(serial, '登录华为账号', { waitMs: 2500 });
      if (!btn.ok) { ctx.log('② 未勾选自动点「登录华为账号」', 'fail', btn.err || '定位失败（页面无该按钮？可能已在别的页面）'); return; }
      ctx.log('② 未勾选自动点「登录华为账号」', 'pass', `已点击 (${btn.x},${btn.y})`);
      // ③ 断言拦截生效：PAD=红字提示「请先阅读并勾选同意下方协议」+勾选框抖动；手机=协议弹窗重弹（不同意仅拦登录/云同步）
      const d = await ctx.art.dump(`LOGIN-AGREE-${dev.id}`, 'dump-after.json', serial);
      const logged = (d.text.match(/已登录/g) || []).length;
      const tip = d.text.includes('请先阅读并勾选同意下方协议');
      const modal = d.text.includes('同意并继续');
      const blocked = logged === 0 && (tip || modal);
      ctx.log('★拦截生效（app 真实表现）', blocked ? 'pass' : 'fail',
        blocked ? (tip ? '出现红字「请先阅读并勾选同意下方协议」+抖动，仍停在未登录=门禁拦截 ✓' : '手机路径：协议弹窗重弹（不同意仅拦登录与云同步）✓') :
          `未捕获拦截提示且未登录=${logged === 0}（tip=${tip} modal=${modal}）——若实际跳到了华为授权页=门禁失效，属 app 问题`);
    } },
  { id: 'LOGIN-HOME', suite: 'login', name: '首页入口·勾选协议放行并登录（真实路径：dismiss 模态→勾选→登录；人工仅华为授权）', semi: true, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      await coldStart(serial);
      await autoLogout(ctx, serial, dev); // ★ 0.229.24：先冷启见真实态；已登录→关弹窗+点「退出账号」全自动复位
      if (canUiDump(dev)) {
        // ★ 0.229.24 基线对齐（真实用户旅程）：①模态在→点「暂不同意」回首页 ②勾首页勾选框图标 ③点登录（勾选放行）
        //   手机无首页勾选框→回退模态放行路径；协议已同意态→勾选框已隐藏、点登录直接放行（均为 app 真实分支）
        const d0 = await dumpLayout(serial);
        let viaCheckbox = false;
        if (d0.ok && d0.text.includes('同意并继续')) {
          const rj = await uiClickText(serial, '暂不同意', { waitMs: 1500 });
          ctx.log('① 首启协议模态·自动点「暂不同意」', rj.ok ? 'pass' : 'fail', rj.ok ? `已点击 (${rj.x},${rj.y})——回首页走勾选放行` : (rj.err || '点击失败'));
        }
        const chk = await uiClickCheckbox(serial, '我已阅读并同意', { waitMs: 1000 });
        if (chk.ok) {
          viaCheckbox = true;
          ctx.log('② 自动勾选首页协议（点勾选框图标）', 'pass', `已点击 (${chk.x},${chk.y})（${chk.how}——勾选生效后登录按钮放行）`);
        } else {
          ctx.log('② 首页勾选框不显示（真实状态）', 'pass', '手机端或协议已同意态→勾选框不渲染（0.226.0 真实行为），改走模态/直接放行');
        }
        const btn = await uiClickText(serial, '登录华为账号', { waitMs: 2200 }); // ★ 自动点首页登录按钮
        ctx.log('③ 自动点「登录华为账号」', btn.ok ? 'pass' : 'warn', btn.ok ? `已点击 (${btn.x},${btn.y})${viaCheckbox ? '（勾选放行路径）' : ''}` : (btn.err || '定位失败——请人工点'));
        // 手机分支：未同意态点登录会弹协议模态（pendingAction=login）——自动同意后续跑授权
        const d1 = await dumpLayout(serial);
        if (d1.ok && d1.text.includes('同意并继续')) {
          const ag = await agreeDialogIfAny(serial, ctx.log);
          if (ag.agreed && ag.ok) ctx.log('④ 手机路径·协议模态自动同意续跑登录', 'pass', '同意并继续已点（pendingAction=login 续跑）');
        }
      }
      const r = await ctx.checkpoint({ label: '【唯一人工·请看 Pad 屏幕】测试台已自动完成：协议同意+体验改进关闭+点「登录华为账号」。此刻 Pad 应显示华为授权页（若你系统华为账号已登录过本应用，可能静默完成、屏幕直接回到应用=无需点击）→ 弹了授权页就点「同意并继续」（页面上若有「阅读并同意」勾选框，先勾选再点同意；只有取消/同意两个按钮就直接点同意）', deviceId: dev.id,
        detect: canUiDump(dev) ? (async () => (await dumpCountText(serial, '已登录')).n >= 1) : null });
      if (r.state === 'timeout') { ctx.log('人工授权', 'fail', '180s 内未完成授权'); return; }
      if (canUiDump(dev)) {
        const d = await ctx.art.dump(`LOGIN-HOME-${dev.id}`, 'dump-login.json', serial);
        const logged = (d.text.match(/已登录/g) || []).length;
        const unlogged = (d.text.match(/未登录/g) || []).length;
        ctx.log('★边栏账号行=已登录', logged >= 1 ? 'pass' : 'fail', `已登录×${logged}（bug 红灯位：登录后边栏仍灰=未登录×${unlogged}）`);
      } else uiSkip(ctx.log, dev, '★边栏账号行=已登录');
      const g = await grepPref(serial, 'huawei-account');
      ctx.log('登录态落盘（尽力确认）', g.found ? 'pass' : 'warn', g.found ? `${g.path} → ${g.sample}` : '候选路径未命中（UI 断言已兜底，登录后文件才生成）');
      const h = await hilogErrors(serial);
      ctx.log('登录链路 hilog 无错误', h.ok ? (h.n === 0 ? 'pass' : 'fail') : 'warn', h.ok ? `ERROR 计数=${h.n}` : 'hilog 读取异常');
      await autoLogout(ctx, serial, dev); // ★ 0.229.20 入口隔离收尾：测完本入口自动退出，下一条入口从未登录基线开始
    } },
  { id: 'LOGIN-SIDEBAR', suite: 'login', name: '边栏入口·点头像登录（前置：协议已同意+未登录，直接拉授权）', semi: true, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '边栏入口登录（核心断言为边栏 UI 翻转）'); return; }
      await coldStart(serial);
      await autoLogout(ctx, serial, dev); // ★ 0.229.24：先冷启见真实态；已登录→全自动退出复位（旧版人工检查点退出）
      // ★ 前置状态写实：协议已同意+未登录（真实状态：点头像直接拉华为授权，无协议拦截）。
      //   若单独在 fresh 态跑（协议未同意）：点头像会先弹协议模态——agreeDialogIfAny 自动同意后照常续跑
      const ag = await agreeDialogIfAny(serial, ctx.log);
      ctx.log('前置状态', 'info', ag.agreed ? '协议未同意→点头像先弹协议（已自动同意续跑）' : '协议已同意+未登录（点头像直接拉华为授权——0.226.0 真实路径）');
      // ★ 0.229.24 头像自动点：账号行=Row[Image(头像), Column(未登录/昵称)]——uiClickCheckbox 两级向上找行首图标
      //   （0.196.3：未登录点头像拉起登录；系统账号已授权时静默完成=零人工）
      // ★ 0.241.0.4 手机适配：边栏=画布抽屉（默认关）——先 ensureCanvas+openPhoneDrawer 再点头像
      if (dev.id === 'phone') {
        const csOk = await ensureCanvas(serial, ctx.log);
        const drOk = csOk ? await openPhoneDrawer(serial, ctx.log) : { ok: false };
        if (!drOk.ok) { const dk = await dumpLayout(serial); if (!dk.text.includes('未登录')) { ctx.log('① 手机抽屉未开', 'fail', '抽屉唤出失败——头像定位无从谈起'); return; } }
      }
      const av = await uiClickCheckbox(serial, '未登录', { waitMs: 3000 });
      if (av.ok) ctx.log('① 自动点边栏账号头像（行首图标）', 'pass', `已点击 (${av.x},${av.y})（${av.how}——0.196.3 未登录点头像拉起登录）`);
      else ctx.log('① 头像自动定位失败', 'warn', (av.err || '') + '——请人工点边栏底部账号头像');
      // ★ 0.266.0.1：头像点击后 0.264.0 华为协议门禁先弹（fresh 首登）——不点掉授权页不来
      await hwAgreeIfAny(dev, serial, ctx.log);
      const r = await ctx.checkpoint({ label: '【人工仅授权·请看 Pad】头像已自动点（失败才需人工点边栏底部账号头像）→ 华为授权页弹出时点「同意并继续」（有「阅读并同意」勾选框先勾再点；系统账号已授权=静默完成、无需任何点击）', deviceId: dev.id,
        detect: async () => (await dumpCountText(serial, '已登录')).n >= 1 });
      if (r.state === 'timeout') { ctx.log('人工授权', 'fail', '180s 内未完成授权'); return; }
      const d = await ctx.art.dump(`LOGIN-SIDEBAR-${dev.id}`, 'dump-login.json', serial);
      const logged = (d.text.match(/已登录/g) || []).length;
      ctx.log('★边栏自身转已登录', logged >= 1 ? 'pass' : 'fail', `已登录×${logged}（0.217.2 同族 bug 位：边栏入口登录后边栏自身必须翻转）`);
      const h = await hilogErrors(serial);
      ctx.log('登录链路 hilog 无错误', h.ok ? (h.n === 0 ? 'pass' : 'fail') : 'warn', h.ok ? `ERROR 计数=${h.n}` : 'hilog 读取异常');
      await autoLogout(ctx, serial, dev); // ★ 0.229.20 入口隔离收尾：测完本入口自动退出，下一条入口从未登录基线开始
    } },
  { id: 'LOGIN-SYNC', suite: 'login', name: '设置→云同步入口·登录即开同步（导航全自动：设置→云同步→开启→登录引导→授权）', semi: true, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      await coldStart(serial);
      await autoLogout(ctx, serial, dev); // ★ 0.229.24：先冷启见真实态；已登录→关弹窗+「退出账号」+同步开关强制关（0.196.8）
      const ag = await agreeDialogIfAny(serial, ctx.log);
      ctx.log('前置状态', 'info', (ag.agreed ? '协议未同意→云同步入口先弹协议（已自动同意续跑）' : '协议已同意+未登录') + '（0.196.11：fromSyncEntry 登录成功直接开云同步，不再弹询问）');
      // ★ 0.229.24 全自动导航（实机 dump 探索固化关键词——「对测试台的测试」产物；此前人工导航 180s 超时翻车主因）：
      //   边栏「设置」→ 弹窗「云同步」Tab → 「开启云同步」→ 未登录弹「登录华为账号」引导窗（0.196.10）→ 静默授权
      // ★ 0.241.0.4 手机适配：设置入口在画布抽屉内（默认关）——先 ensureCanvas+openPhoneDrawer
      if (dev.id === 'phone') {
        const csOk = await ensureCanvas(serial, ctx.log);
        const drOk = csOk ? await openPhoneDrawer(serial, ctx.log) : { ok: false };
        if (!drOk.ok) { const dk = await dumpLayout(serial); if (!dk.text.includes('设置')) { ctx.log('⓪ 手机抽屉唤出', 'fail', '抽屉未开——设置入口不可达'); return; } }
      }
      const s1 = await uiClickText(serial, '设置', { waitMs: 2500 });
      ctx.log('① 自动点边栏「设置」', s1.ok ? 'pass' : 'fail', s1.ok ? `已点击 (${s1.x},${s1.y})——全局设置弹窗（默认 API Tab）` : (s1.err || ''));
      if (!s1.ok) return;
      const s2 = await uiClickText(serial, '云同步', { waitMs: 2000 });
      ctx.log('② 自动点「云同步」Tab', s2.ok ? 'pass' : 'fail', s2.ok ? `已点击 (${s2.x},${s2.y})——云同步面板（状态卡+开启按钮+同步条件）` : (s2.err || ''));
      if (!s2.ok) return;
      const s3 = await uiClickText(serial, '开启云同步', { waitMs: 2500 });
      ctx.log('③ 自动点「开启云同步」', s3.ok ? 'pass' : 'fail', s3.ok ? `已点击 (${s3.x},${s3.y})——未登录触发登录引导弹窗（0.196.10 登录引导）` : (s3.err || ''));
      if (!s3.ok) return;
      // ④ 引导窗按钮用 exact 精确匹配（正文「请先登录华为账号。」也含该关键字——点正文=无效点击，上轮翻车点）
      //   + near:'需要登录'（引导窗标题）取同列最近，防点到被遮罩的首页底层同名按钮
      const s4 = await uiClickText(serial, '登录华为账号', { waitMs: 2500, near: '需要登录', exact: true });
      ctx.log('④ 自动点引导窗「登录华为账号」', s4.ok ? 'pass' : 'fail', s4.ok ? `已点击 (${s4.x},${s4.y})（fromSyncEntry 入口即意图）` : (s4.err || ''));
      if (!s4.ok) return;
      // ★ 0.266.0.1：引导窗点登录后 0.264.0 华为协议门禁先弹（fresh 首登）——不点掉授权页不来
      await hwAgreeIfAny(dev, serial, ctx.log);
      // ⑤ 系统权限弹窗（首次开同步弹「发现和连接附近的设备」）：两按钮都含'允许'关键字（不允许/允许）——必须取最后命中
      await sleep(3000);
      const dp = await dumpLayout(serial);
      if (dp.ok && dp.text.includes('附近的设备')) {
        const s5 = await uiClickText(serial, '允许', { pick: 'last', waitMs: 2500 });
        ctx.log('⑤ 系统弹窗·自动点「允许」（发现和连接附近设备）', s5.ok ? 'pass' : 'fail', s5.ok ? `已点击 (${s5.x},${s5.y})（同步所需系统权限）` : (s5.err || ''));
      } else ctx.log('⑤ 系统权限弹窗未出现', 'info', '此前已授权（仅首次开同步弹）');
      // ⑥ 兜底人工检查点：静默授权通常零操作；非静默弹华为授权页时人工点同意
      const r = await ctx.checkpoint({ label: '【人工仅授权·请看 Pad】导航已全自动（设置→云同步→开启→登录引导已自动点完）。静默授权零点击；若弹华为授权页点「同意并继续」（有勾选框先勾再点）', deviceId: dev.id,
        detect: async () => { const c = await dbCount(serial, null); return c.ok && c.n > 0; },
        timeoutMs: 240000 });
      if (r.state === 'timeout') { ctx.log('人工授权', 'fail', '240s 内未完成授权/云端未见数据'); return; }
      ctx.log('登录+同步链路完成', 'pass', r.auto ? 'cloud_data 行数>0 自动确认（全程零人工）' : '用户确认完成');
      const c = await dbCount(serial, null);
      ctx.log('★云同步自动开启（RDB 有行）', c.ok && c.n > 0 ? 'pass' : 'fail', c.ok ? `cloud_data 总行数=${c.n}（bug 红灯位：需手动开才同步=0 行）` : `sqlite 读取异常：${c.raw}`);
      // ★ 0.229.24 开关落盘断言带重试轮询：PersistenceV2 内存态先行（同步已开=73 行实锤）、磁盘 flush 有秒级延迟——
      //   退出后 enabled:false → 登录开同步 enabled:true 落盘需等 flush，单次 grep 会撞旧值竞态误报红
      let g = null, switchOn = false;
      for (let i = 0; i < 6 && !switchOn; i++) {
        g = await grepPref(serial, 'cloud-sync-switch');
        switchOn = g.found && g.sample.includes('true');
        if (!switchOn) await sleep(2000);
      }
      ctx.log('★cloud-sync-switch 开关落盘', switchOn ? 'pass' : (g && g.found ? 'fail' : 'warn'),
        g && g.found ? `${g.path} → ${g.sample.slice(0, 200)}${switchOn ? '' : '（12s 内磁盘未见 true——同步行数已实证开启，此为 flush 延迟或开关未落盘，人工复核）'}` : '候选路径未命中（RDB 行数断言已兜底）');
      const h = await hilogErrors(serial);
      ctx.log('同步链路 hilog 无错误', h.ok ? (h.n === 0 ? 'pass' : 'fail') : 'warn', h.ok ? `ERROR 计数=${h.n}` : 'hilog 读取异常');
      await autoLogout(ctx, serial, dev); // ★ 0.229.20 入口隔离收尾：退出账号+同步开关强制关（0.196.8）
    } },
  // ★ 0.263.0 新功能配套（§12.13 军令）：退出华为账号确认弹窗可勾选「同时清空本机数据」——
  //   路径=边栏头像（logoutConfirmVisible 弹窗，与 LOGIN-LOGOUT 测的首页「退出账号」直退按钮是两条不同链路）
  { id: 'LOGIN-WIPE', suite: 'login', name: '退出并清空·勾选清零本机数据（弹窗勾选→按钮变「退出并清空」→自退重启→未登录+空库+RDB清零）', semi: true, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '退出并清空（全链路 UI 断言）'); return; }
      await coldStart(serial);
      let d0 = await dumpCountText(serial, '已登录');
      if (d0.n === 0) {
        ctx.log('前置·未登录', 'info', '自动点头像登录（静默授权）造出已登录态，再测退出并清空');
        if (dev.id === 'phone') {
          const csOk = await ensureCanvas(serial, ctx.log);
          const drOk = csOk ? await openPhoneDrawer(serial, ctx.log) : { ok: false };
          if (!drOk.ok) { const dk = await dumpLayout(serial); if (!dk.text.includes('未登录')) { ctx.log('⓪ 手机抽屉未开', 'fail', '抽屉唤出失败——头像不可达'); return; } }
        }
        const av = await uiClickCheckbox(serial, '未登录', { waitMs: 3000 });
        if (av.ok) ctx.log('自动点边栏账号头像（登录）', 'pass', `已点击 (${av.x},${av.y})（${av.how}）`);
        await hwAgreeIfAny(dev, serial, ctx.log); // ★ 0.266.0.1：fresh 首登华为协议门禁先弹——不点掉授权页不来
        await ctx.checkpoint({ label: '【人工仅授权·请看屏幕】静默授权通常零点击；若弹华为授权页点「同意并继续」', deviceId: dev.id,
          detect: async () => (await dumpCountText(serial, '已登录')).n >= 1 });
        d0 = await dumpCountText(serial, '已登录');
      }
      if (d0.n === 0) { ctx.log('前置：已登录态', 'skip', '未能进入已登录态（授权未完成）——排查后重跑'); return; }
      await dismissLoginDialogs(serial, ctx.log);
      // ① 已登录态点边栏头像 → 弹「退出华为账号」确认弹窗（0.196.9 确认弹窗 + 0.263.0 勾选框）
      if (dev.id === 'phone') {
        const csOk = await ensureCanvas(serial, ctx.log);
        const drOk = csOk ? await openPhoneDrawer(serial, ctx.log) : { ok: false };
        if (!drOk.ok) { const dk = await dumpLayout(serial); if (!dk.text.includes('已登录')) { ctx.log('① 手机抽屉未开', 'fail', '抽屉唤出失败——头像不可达'); return; } }
      }
      const av2 = await uiClickCheckbox(serial, '已登录', { waitMs: 2500 });
      if (!av2.ok) { ctx.log('① 点边栏头像', 'fail', av2.err || '定位失败——「华为账号已登录」行不可见'); return; }
      ctx.log('① 点边栏头像（已登录态）', 'pass', `已点击 (${av2.x},${av2.y})——拉起「退出华为账号」确认弹窗`);
      await sleep(1200);
      const d1 = await ctx.art.dump(`LOGIN-WIPE-${dev.id}`, 'dump-dialog.json', serial);
      const hasTitle = d1.text.includes('退出华为账号');
      const hasCheck = d1.text.includes('同时清空本机全部数据');
      ctx.log('★确认弹窗含勾选项', hasTitle && hasCheck ? 'pass' : 'fail',
        hasTitle && hasCheck ? '标题「退出华为账号」+勾选行「同时清空本机全部数据（借给他人前勾选）」均在' : `标题=${hasTitle} 勾选行=${hasCheck}（0.263.0 新 UI 缺失）`);
      if (!hasCheck) return;
      // ② 点勾选行 → 确认钮文案翻转为「退出并清空」（防误触高危确认设计）
      const ck = await uiClickText(serial, '同时清空本机全部数据', { waitMs: 1200 });
      if (!ck.ok) { ctx.log('② 点勾选行', 'fail', ck.err || '定位失败'); return; }
      const d2 = await dumpLayout(serial);
      const armed = d2.ok && d2.text.includes('退出并清空');
      ctx.log('★勾选后确认钮=「退出并清空」', armed ? 'pass' : 'fail', armed ? '按钮文案已随勾选态切换（高危动作明确化）' : 'dump 未见「退出并清空」——勾选未生效或按钮文案未切换');
      if (!armed) return;
      // ③ 点「退出并清空」→ toast+1.2s 后自退 → coldStart 重开兜底
      const go = await uiClickText(serial, '退出并清空', { waitMs: 1500 });
      ctx.log('③ 点「退出并清空」', go.ok ? 'pass' : 'fail', go.ok ? `已点击 (${go.x},${go.y})——登出+清零+自退` : (go.err || '定位失败'));
      if (!go.ok) return;
      await sleep(3500); // toast 1.5s + 自退 1.2s + 余量
      await coldStart(serial);
      await sleep(1500);
      // ④ 断言终态：未登录 + 词库空 + RDB 清零（云端零影响——结构性保证=先停同步再清+不产生墓碑，见 DataWipeUtil）
      const d3 = await ctx.art.dump(`LOGIN-WIPE-${dev.id}`, 'dump-after.json', serial);
      const loggedN = (d3.text.match(/已登录/g) || []).length;
      ctx.log('★清空重启后=未登录', loggedN === 0 ? 'pass' : 'fail', `已登录×${loggedN}${loggedN > 0 ? '（登出未生效）' : ''}`);
      const g = await grepPref(serial, 'word-bank');
      const emptyWords = g.found && /"words":\s*\[\s*\]/.test(g.sample);
      ctx.log('★词库落盘=空数组', g.found ? (emptyWords ? 'pass' : 'fail') : 'warn',
        g.found ? `${g.path} → ${g.sample.slice(0, 160)}${emptyWords ? '' : '（words 非空——清零未落盘或 preset 复活）'}` : '候选路径未命中（UI 断言已兜底）');
      const c = await dbCount(serial, null);
      ctx.log('★云同步 RDB=0 行', c.ok ? (c.n === 0 ? 'pass' : 'fail') : 'warn',
        c.ok ? `cloud_data 总行数=${c.n}（行=上行事实，清零=与卸载重装等价；云端数据不受影响——重新登录开同步全量恢复）` : `sqlite 读取异常：${c.raw}`);
      ctx.log('收尾说明', 'info', '本机数据已清（借人场景语义）。云端零影响：重新登录+开云同步即全量恢复。设备留在未登录空库态——后续 LOGIN-LOGOUT 会自动登录复位');
    } },
  { id: 'LOGIN-LOGOUT', suite: 'login', name: '退出登录·回到未登录基线（自包含：未登录先自动头像登录，再测退出）', semi: true, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '退出登录（前后态均为 UI 断言）'); return; }
      await coldStart(serial); // ★ 0.229.24：先冷启见真实登录态（app 未开时 dump 到的是桌面，旧版会误判未登录）
      let d0 = await dumpCountText(serial, '已登录');
      if (d0.n === 0) {
        // ★ 0.229.24 自包含：入口用例收尾都会自动退出（入口隔离）——本用例独立跑时先自动点头像登录（静默授权）
        //   造出已登录态再测退出流程；登录不成功（非静默且无人点授权）才如实 skip
        ctx.log('前置·未登录', 'info', '自动点头像登录（静默授权）造出已登录态，再测退出流程');
        const av = await uiClickCheckbox(serial, '未登录', { waitMs: 3000 });
        if (av.ok) {
          ctx.log('自动点边栏账号头像（行首图标）', 'pass', `已点击 (${av.x},${av.y})（${av.how}）`);
          await hwAgreeIfAny(dev, serial, ctx.log); // ★ 0.266.0.1：fresh 首登华为协议门禁先弹——不点掉授权页不来
          await ctx.checkpoint({ label: '【人工仅授权·请看 Pad】静默授权通常零点击；若弹出华为授权页点「同意并继续」', deviceId: dev.id,
            detect: async () => (await dumpCountText(serial, '已登录')).n >= 1 });
        }
        d0 = await dumpCountText(serial, '已登录');
      }
      if (d0.n === 0) { ctx.log('前置：已登录态', 'skip', '未能进入已登录态（头像定位失败或授权未完成）——排查后重跑'); return; }
      // ★ 0.229.24 基线对齐（产物对照实锤）：①先逐层关登录后双层弹窗（30天试用「知道了」+云同步询问「暂不开启」堆叠）
      //   ②实际按钮=「退出账号」（Index.ets Button('退出账号')，旧关键字「退出登录」页面上不存在）；③无二次确认（0.164 直退）
      await dismissLoginDialogs(serial, ctx.log);
      const a1 = await uiClickText(serial, '退出账号', { waitMs: 2000 });
      if (a1.ok) {
        ctx.log('自动点「退出账号」', 'pass', `已点击 (${a1.x},${a1.y})（实际文案=退出账号；无二次确认，0.164 doLogout 直退）`);
        await sleep(2000);
        const n = (await dumpCountText(serial, '已登录')).n;
        ctx.log('★退出后回到未登录', n === 0 ? 'pass' : 'fail', `已登录×${n}${n > 0 ? '（退出未生效）' : '——边栏/首页账号行均翻转回未登录'}`);
        const d = await ctx.art.dump(`LOGIN-LOGOUT-${dev.id}`, 'dump-logout.json', serial);
        const unlogged = (d.text.match(/未登录/g) || []).length;
        ctx.log('三入口复位未登录', unlogged >= 1 ? 'pass' : 'fail', `未登录×${unlogged}`);
        const g = await grepPref(serial, 'cloud-sync-switch');
        ctx.log('cloud-sync-switch 强制关（尽力确认）', g.found ? 'pass' : 'warn', g.found ? `${g.path} → ${g.sample}` : '候选路径未命中（0.196.8 退出强制关，文件存在才可读）');
        // ★ 0.229.25 收尾保持登录（用户裁决"离开时尽量保持登录，下一轮任何测试不用再点登录"）：
        //   退出断言完成后自动点头像静默授权登回——整个 login 矩阵收尾=已登录（矩阵内部入口隔离不变，
        //   只有末条 LOGOUT 负责把设备留在已登录态），覆盖装机后 LOGIN-KEEP 从此可真断言
        const back = await uiClickCheckbox(serial, '未登录', { waitMs: 3000 });
        if (back.ok) {
          ctx.log('收尾·自动登回（点头像·静默授权）', 'pass', `已点击 (${back.x},${back.y})（${back.how}——矩阵收尾保持登录，用户裁决）`);
          const r2 = await ctx.checkpoint({ label: '【人工仅授权】静默授权通常零点击；若弹华为授权页点「同意并继续」（收尾保持登录）', deviceId: dev.id,
            detect: async () => (await dumpCountText(serial, '已登录')).n >= 1, timeoutMs: 90000 });
          if (r2.state !== 'timeout') {
            await dismissLoginDialogs(serial, ctx.log);
            const n1 = (await dumpCountText(serial, '已登录')).n;
            ctx.log('★收尾登录态=已登录', n1 >= 1 ? 'pass' : 'fail', `已登录×${n1}（下一轮任意套件起点即已登录，覆盖装机后 LOGIN-KEEP 可真断言）`);
          } else ctx.log('收尾登回', 'warn', '90s 内未完成授权——登录态未保持（下轮套件前置会再自动登录兜底）');
        } else ctx.log('收尾登回', 'warn', '头像定位失败——登录态未保持（下轮套件前置会再自动登录兜底）');
        return;
      }
      const r = await ctx.checkpoint({ label: '【人工】点「退出账号」按钮（首页账号行右侧；当前页未自动找到——可能被弹窗遮挡）', deviceId: dev.id,
        detect: async () => (await dumpCountText(serial, '已登录')).n === 0 });
      if (r.state === 'timeout') { ctx.log('退出操作', 'fail', '180s 内未完成退出'); return; }
      const d = await ctx.art.dump(`LOGIN-LOGOUT-${dev.id}`, 'dump-logout.json', serial);
      const unlogged = (d.text.match(/未登录/g) || []).length;
      ctx.log('三入口复位未登录', unlogged >= 1 ? 'pass' : 'fail', `未登录×${unlogged}`);
      const g = await grepPref(serial, 'cloud-sync-switch');
      ctx.log('cloud-sync-switch 强制关（尽力确认）', g.found ? 'pass' : 'warn', g.found ? `${g.path} → ${g.sample}` : '候选路径未命中');
    } },
  { id: 'LOGIN-KEEP', suite: 'login', name: '覆盖安装·登录态与协议同意均保留（覆盖模式专属，不卸载）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '覆盖安装登录态保留（UI 断言）'); return; }
      await coldStart(serial);
      const d = await ctx.art.dump(`LOGIN-KEEP-${dev.id}`, 'dump-keep.json', serial);
      if (d.text.includes('同意并继续')) { ctx.log('★覆盖安装不应弹协议', 'fail', '出现协议模态=agreement-v1 被清（覆盖安装应保留同意状态）'); return; }
      const logged = (d.text.match(/已登录/g) || []).length;
      // ★ 0.229.25 前置快照（/api/prep 装机前实录 PREP_STATE）——根治"上一轮 LOGOUT 收尾登出→覆盖装机 KEEP 必 skip"：
      //   装机前已登录→装后必须已登录（丢=fail 真红线）；装机前未登录→如实 skip（无从验证"保留"）；无快照（旧流程装机）→维持原行为
      const pre = PREP_STATE[dev.id];
      if (pre && pre.login === false) { ctx.log('登录态保留', 'skip', `装机前快照=未登录（${pre.at}实录）——无从验证"保留"。跑一轮 login 套件（LOGOUT 会自动登回）后再覆盖装机，本条即真断言`); return; }
      if (pre && pre.login === true && logged === 0) { ctx.log('★覆盖安装登录态保留', 'fail', '装机前快照=已登录、装后已登录×0——登录态被覆盖安装丢失（真红线：不卸载的 -r 安装绝不该清沙箱）'); return; }
      if (logged === 0) { ctx.log('登录态保留', 'skip', '当前未登录——本用例须【覆盖安装】模式且此前已登录时跑（fresh 模式必清）'); return; }
      ctx.log('★覆盖安装登录态保留', 'pass', `已登录×${logged}${pre && pre.login ? '（装机前快照=已登录，装后保留 ✓）' : ''}（覆盖安装不清沙箱，华为登录态与协议同意均保留）`);
    } },
  // ★ 0.266.0.1 新增（§12.13 军令，app 0.266.0 配套）：撤回同意=全撤+立即弹首启门禁（方案 A）——
  //   真实路径复刻：设置→关于→法律条款→撤回同意→确认弹窗「撤回并重新阅读」→ 首启门禁立即弹出
  //   （设置弹窗同帧关闭）→ 重新同意恢复 → 登录态保留。数据侧尽力断言 agreement-v1 / cloud-sync-switch 落盘翻转。
  //   全自动零人工（撤回不触发华为授权页）semi:false；PC 无 UI 通道走数据侧尽力（BOOT-AGREE 同款模式）
  { id: 'LOGIN-REVOKE', suite: 'login', name: '撤回同意·全撤+首启门禁立即重弹+重新同意恢复（0.266.0 方案A：关云同步+回门禁，数据不删）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      // 撤前状态实录（恢复判据+断言基线）：登录态 / 同步开关
      const preSwitch = await grepPref(serial, 'cloud-sync-switch');
      const preSwitchOn = preSwitch.found && preSwitch.sample.includes('true');
      if (!canUiDump(dev)) {
        // PC 数据侧尽力：agreement-v1 撤回后 agreed:false（UI 链路已由 Pad/手机验证）
        ctx.log('PC 数据侧尽力', 'info', '撤回 UI 链路（设置→关于→撤回同意）须人工/Pad 通道——此处仅核协议态数据');
        const g = await grepPref(serial, 'agreement-v1');
        ctx.log('agreement-v1 现态', g.found ? 'pass' : 'info', g.found ? `${g.path} → ${g.sample.slice(0, 160)}` : '盘上无 agreement-v1（未同意或未落盘）');
        return;
      }
      await coldStart(serial);
      await agreeDialogIfAny(serial, ctx.log); // 前置自愈：未同意先同意（撤回得有东西可撤）
      // 导航：设置弹窗（手机=画布抽屉内入口，LOGIN-SYNC 同款）
      if (dev.id === 'phone') {
        const csOk = await ensureCanvas(serial, ctx.log);
        const drOk = csOk ? await openPhoneDrawer(serial, ctx.log) : { ok: false };
        if (!drOk.ok) { const dk = await dumpLayout(serial); if (!dk.text.includes('设置')) { ctx.log('⓪ 手机抽屉未开', 'fail', '抽屉未开——设置入口不可达'); return; } }
      }
      const s1 = await uiClickText(serial, '设置', { waitMs: 2500 });
      ctx.log('① 点「设置」开全局设置弹窗', s1.ok ? 'pass' : 'fail', s1.ok ? `已点击 (${s1.x},${s1.y})` : (s1.err || ''));
      if (!s1.ok) return;
      // 关于 Tab（Tab 栏横向 Scroll——手机 7 Tab「关于」可能被裁，点不到先左滑 Tab 栏再点）
      let tab = await uiClickText(serial, '关于', { exact: true, waitMs: 1800 });
      if (!tab.ok) {
        const dt = await dumpLayout(serial);
        const tm = String((JSON.parse(dt.text).attributes || {}).bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
        const tw = tm ? +tm[3] : 2560, th = tm ? +tm[4] : 1700;
        await sh(serial, `uitest uiInput swipe ${Math.round(tw * 0.8)} ${Math.round(th * 0.16)} ${Math.round(tw * 0.2)} ${Math.round(th * 0.16)} 400`, 15000);
        await sleep(900);
        tab = await uiClickText(serial, '关于', { exact: true, waitMs: 1800 });
      }
      ctx.log('② 点「关于」Tab', tab.ok ? 'pass' : 'fail', tab.ok ? `已点击 (${tab.x},${tab.y})` : (tab.err || 'Tab 栏滚动后仍不可见'));
      if (!tab.ok) return;
      // 法律条款区在关于 Tab 底部——上滑两屏露出「撤回同意」（scrW/scrH 取 dump 根节点 bounds，CHAT-ACTIONS 同款）
      let rv = await uiClickText(serial, '撤回同意', { exact: true, waitMs: 1500 });
      if (!rv.ok) {
        const dm = await dumpLayout(serial);
        const scrM = String((JSON.parse(dm.text).attributes || {}).bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
        const scrW = scrM ? +scrM[3] : 2560, scrH = scrM ? +scrM[4] : 1700;
        const sw2 = `uitest uiInput swipe ${Math.round(scrW / 2)} ${Math.round(scrH * 0.35)} ${Math.round(scrW / 2)} ${Math.round(scrH * 0.8)} 450`;
        await sh(serial, sw2, 20000); await sleep(700);
        await sh(serial, sw2, 20000); await sleep(700);
        rv = await uiClickText(serial, '撤回同意', { exact: true, waitMs: 1500 });
      }
      ctx.log('③ 点「撤回同意」（滚动露出法律条款区）', rv.ok ? 'pass' : 'fail', rv.ok ? `已点击 (${rv.x},${rv.y})` : (rv.err || '未找到——盯屏 /api/dump 校准'));
      if (!rv.ok) return;
      // 确认弹窗（0.266.0 二次确认）→「撤回并重新阅读」
      const cf = await uiClickText(serial, '撤回并重新阅读', { exact: true, waitMs: 1800 });
      ctx.log('④ 确认弹窗·点「撤回并重新阅读」', cf.ok ? 'pass' : 'fail', cf.ok ? `已点击 (${cf.x},${cf.y})（高危二次确认）` : (cf.err || '确认弹窗未弹出'));
      if (!cf.ok) return;
      await sleep(1500);
      // ★主断言：首启门禁立即重弹 + 设置弹窗同帧关闭
      const d2 = await ctx.art.dump(`LOGIN-REVOKE-${dev.id}`, 'dump-gate.json', serial);
      const gateUp = d2.text.includes('同意并继续');
      const gsdGone = !d2.text.includes('全局设置');
      ctx.log('★首启门禁立即重弹', gateUp ? 'pass' : 'fail', gateUp ? '「同意并继续」在屏（0.266.0 四连动作④）' : '门禁未弹出——撤回只 toast 未拉门禁（旧版行为回归）');
      ctx.log('★设置弹窗同帧关闭', gsdGone ? 'pass' : 'fail', gsdGone ? '「全局设置」标题已消失（onClose 先于弹门禁）' : '设置弹窗仍开着——可能遮挡门禁');
      // 数据侧尽力：agreement-v1 翻回未同意（flush 有延迟，重试 6 次）
      let gAg = null, agOff = false;
      for (let i = 0; i < 6 && !agOff; i++) {
        gAg = await grepPref(serial, 'agreement-v1');
        agOff = gAg.found && gAg.sample.includes('false');
        if (!agOff) await sleep(2000);
      }
      ctx.log('agreement-v1 撤回落盘（尽力）', gAg && gAg.found ? (agOff ? 'pass' : 'warn') : 'warn',
        gAg && gAg.found ? `${gAg.path} → ${gAg.sample.slice(0, 160)}${agOff ? '' : '（12s 内未见 false——门禁 UI 断言已兜底，此为 flush 延迟）'}` : '盘上无 agreement-v1（未同意态本来就没有——撤回即删字段）');
      // 恢复：重新同意（勾选+同意并继续+暂不加入体验改进）
      const re = await agreeDialogIfAny(serial, ctx.log);
      if (!re.agreed) { ctx.log('恢复·重新同意', 'fail', '门禁重弹后自动同意未生效——后续用例协议态将异常'); return; }
      ctx.log('⑤ 重新同意恢复', 'pass', '勾选+「同意并继续」+「暂不加入」全自动完成');
      // 登录态保留断言（撤回不退登录——次断言：仅撤前已登录时报）
      const d3 = await dumpLayout(serial);
      const loggedNow = (d3.text.match(/已登录/g) || []).length;
      ctx.log('撤回不退登录（撤前已登录时）', loggedNow >= 1 ? 'pass' : 'info', `已登录×${loggedNow}（撤回只重置协议态不动账号会话）`);
      // 云同步联动断言+恢复：撤前开着→撤后必关（0.266.0 四连动作②）→ openSyncViaSettings 重开
      if (preSwitchOn) {
        let swOff = false, gSw = null;
        for (let i = 0; i < 6 && !swOff; i++) {
          gSw = await grepPref(serial, 'cloud-sync-switch');
          swOff = !gSw.found || gSw.sample.includes('false');
          if (!swOff) await sleep(2000);
        }
        ctx.log('★撤回联动关云同步（落盘尽力）', swOff ? 'pass' : 'warn', gSw && gSw.found ? `${gSw.path} → ${gSw.sample.slice(0, 140)}` : '开关文件未生成（关态本就可能不落盘）——UI 门禁断言为主');
        const reopen = await openSyncViaSettings(ctx, dev);
        ctx.log('恢复·重开云同步', reopen ? 'pass' : 'fail', reopen ? '设置页自愈链已重开（后续 sync 套件前置不受污染）' : 'openSyncViaSettings 未成功——后续 sync 用例可能受影响');
      }
    } },

  // ---------- ★ 0.241.0.4 sync-boot 三端从零引导（fresh 装机后：协议→登录→开同步→三端收敛；用户拍板唯一人工=华为授权页） ----------
  // 配套全流程（前端指引同步更新）：①装机模式选「全新安装」+勾三台→【装机】 ②跑本套件 ③跑 sync+syncflow 完成三端验证
  { id: 'BOOT-AGREE', suite: 'sync-boot', name: '从零①·首启协议全自动同意+未登录基线（fresh 装机第一步）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) {
        const g = await grepPref(serial, 'agreement-v1');
        ctx.log('PC 协议态（数据侧尽力）', g.found ? 'pass' : 'info', g.found ? '盘上有 agreement-v1（已同意）' : '盘上无 agreement-v1（未同意或未落盘——PC 无 UI 通道，协议链已由 Pad/手机验证，BOOT-LOGIN 数据断言兜底）');
        return;
      }
      await coldStart(serial, 7000);
      const d0 = await dumpLayout(serial);
      const hadModal = d0.ok && d0.text.includes('同意并继续');
      if (!hadModal) { ctx.log('★协议模态未出现', 'warn', '非 fresh 装机或协议已同意（本用例验证 fresh 首启路径——覆盖安装场景直接跑 BOOT-LOGIN）'); return; }
      const ag = await agreeDialogIfAny(serial, ctx.log);
      if (!(ag.agreed && ag.ok)) { ctx.log('★协议自动同意', 'fail', '同意链失败（勾选/点击未生效）'); return; }
      const d1 = await dumpLayout(serial);
      const gone = d1.ok && !d1.text.includes('同意并继续');
      ctx.log('★协议已同意（模态消失）', gone ? 'pass' : 'fail', gone ? '勾选+「同意并继续」+「暂不加入」体验改进 全自动完成' : '模态仍在（同意未生效）');
      const unlogged = d1.ok && d1.text.includes('登录华为账号');
      ctx.log('★未登录基线', unlogged ? 'pass' : 'fail', unlogged ? '首页「登录华为账号」在场——三端从零起点一致' : '首页未见登录入口（状态异常，盯屏 /api/dump）');
    } },
  { id: 'BOOT-LOGIN', suite: 'sync-boot', name: '从零②·全自动登录+开云同步（唯一人工=华为授权页；登录询问自动「开启」+系统权限自动「允许」）', semi: true, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      const lok = await ensureLoginFlow(ctx, dev);
      if (!lok) return;
      await ensureSyncPerm(serial, ctx.log); // ★ 登录后先 CLI 预授权同步权限（幂等）——后续「开启云同步」点击直接 granted，少一个系统弹窗变量
      // 登录后三连弹窗主动开启（PC=pcClickText 版；UI 设备=acceptSyncAsk）
      if (canUiDump(dev)) {
        const ac = await acceptSyncAsk(serial, ctx.log);
        if (!ac.opened) ctx.log('云同步询问未出现', 'info', '此前已开过同步或弹窗已过——以数据断言为准（三重断言兜底）');
      } else {
        for (let i = 0; i < 4; i++) {
          const d = await dumpAuditNodes(serial, 15);
          if (!d.ok || !d.nodes.length) break;
          if (d.nodes.some((n) => String(n.text) === '开启云同步')) { const b = await pcClickText(serial, '开启云同步', { exact: true, waitMs: 1800 }); if (b.ok) ctx.log('云同步询问·自动点「开启云同步」（PC）', 'pass', `已点击 (${b.x},${b.y})@屏${b.disp}`); continue; }
          if (d.nodes.some((n) => String(n.text) === '知道了')) { const b = await pcClickText(serial, '知道了', { pick: 'last', waitMs: 1500 }); if (b.ok) ctx.log('30天试用·自动点「知道了」（PC）', 'pass', `已点击 (${b.x},${b.y})@屏${b.disp}`); continue; }
          if (d.nodes.some((n) => String(n.text || '').includes('附近的设备'))) { const b = await pcClickText(serial, '允许', { exact: true, pick: 'last', waitMs: 1800 }); if (b.ok) ctx.log('系统权限·自动点「允许」（PC）', 'pass', `已点击 (${b.x},${b.y})@屏${b.disp}`); continue; }
          break;
        }
      }
      // ★ 0.241.0.5 自愈：已登录但弹窗已错过（存量态）——走设置页真实路径开启，等待首拉
      let cNow = await dbCount(serial, null);
      if (!(cNow.ok && cNow.n > 0)) {
        ctx.log('同步未活→设置页自愈链', 'info', `cloud_data=${cNow.ok ? cNow.n : cNow.raw}——登录询问弹窗已错过，走 设置→云同步→开启 真实用户路径`);
        const sv = await openSyncViaSettings(ctx, dev);
        if (sv) {
          ctx.log('自愈·等待同步激活+首拉', 'info', '最多 90s（含云端全量下拉）');
          await pollUntil(async () => { const c = await dbCount(serial, null); return c.ok && c.n > 0; }, 90000);
          cNow = await dbCount(serial, null);
          ctx.log('★自愈结果', cNow.ok && cNow.n > 0 ? 'pass' : 'fail', `cloud_data=${cNow.ok ? cNow.n : cNow.raw} 行${cNow.ok && cNow.n > 0 ? '（设置页路径开启成功+首拉完成）' : '——设置页开启未生效（app 侧问题，先测后修）'}`);
        }
      }
      // ★ 三重断言：UI 登录态 + RDB 同步活 + 开关落盘（PersistenceV2 flush 秒级延迟=12s 轮询重试，同 LOGIN-SYNC）
      if (canUiDump(dev)) {
        const n = (await dumpCountText(serial, '已登录')).n;
        ctx.log('★UI 登录态', n >= 1 ? 'pass' : 'fail', n >= 1 ? '首页「华为账号已登录」（含子串命中，三端通用）' : '首页仍未见登录态特征');
      }
      const alive = await pollUntil(async () => { const c = await dbCount(serial, null); return c.ok && c.n > 0; }, 90000);
      const c = await dbCount(serial, null);
      ctx.log('★云同步活（RDB 有行）', alive && c.ok && c.n > 0 ? 'pass' : 'fail', c.ok ? `cloud_data=${c.n} 行（>0=登录+同步链路开；90s 等待含首拉）` : `sqlite 读取异常：${c.raw}`);
      let g = null, switchOn = false;
      for (let i = 0; i < 6 && !switchOn; i++) {
        g = await grepPref(serial, 'cloud-sync-switch');
        switchOn = g.found && g.sample.includes('true');
        if (!switchOn) await sleep(2000);
      }
      ctx.log('★cloud-sync-switch 开关落盘', switchOn ? 'pass' : (g && g.found ? 'fail' : 'warn'),
        g && g.found ? `${g.path} → ${g.sample.slice(0, 200)}${switchOn ? '' : '（12s 内磁盘未见 true——行数已实证同步活，flush 延迟或开关未落盘，人工复核）'}` : '候选路径未命中（RDB 行数断言已兜底）');
    } },
  { id: 'BOOT-CONVERGE', suite: 'sync-boot', name: '从零③·三端收敛（settle 总行数一致+全域行数/签名三端一致·含账户资产域）', semi: false, scope: 'cross',
    run: async (ctx) => {
      const devs = ctx.devices;
      if (devs.length < 2) { ctx.log('前置', 'skip', '三端收敛需 ≥2 台在线设备（建议三台全勾——本条是「手机与 Pad/PC 不同步」的总闸断言）'); return; }
      const base = []; for (const d of devs) base.push({ d, n: (await dbCount(d.serial, null)).n });
      ctx.log('基线', 'info', base.map((x) => `${x.d.id}=${x.n}`).join(' ') + '（fresh 三端并发首拉有先后——settle 等待收敛）');
      const eq = await pollUntil(async () => {
        const cs = []; for (const d of devs) cs.push(await dbCount(d.serial, null));
        return cs.every((c) => c.ok) && cs.every((c) => c.n === cs[0].n);
      }, 180000);
      const afters = []; for (const d of devs) afters.push({ d, c: await dbCount(d.serial, null) });
      const allOk = afters.every((x) => x.c.ok) && afters.every((x) => x.c.n === afters[0].c.n);
      ctx.log('★三端总行数收敛', allOk ? 'pass' : 'fail', afters.map((x) => `${x.d.id}=${x.c.ok ? x.c.n : x.c.raw}`).join(' ') + (allOk ? `（一致=${afters[0].c.n}）` : '——180s 内未达一致：某端未拉完/未登录/同步未开（先跑 BOOT-LOGIN；仍不一致=app 同步问题实锤，先测后修）'));
      // 四域行数+键集签名（三端版 SYNC-DOMAIN；del 墓碑域含在内——收敛后墓碑也应一致）
      for (const [domain, prefixes] of Object.entries(CFG.domains)) {
        for (const p of prefixes) {
          const res = []; for (const d of devs) res.push({ d, c: await dbCount(d.serial, p) });
          if (res.some((x) => !x.c.ok)) { ctx.log(`${domain} [${p}] 行数`, 'fail', res.map((x) => `${x.d.id}=${x.c.raw}`).join(' ')); continue; }
          const ns = res.map((x) => x.c.n);
          const equal = ns.every((n) => n === ns[0]);
          ctx.log(`${domain} [${p}] 行数`, equal ? 'pass' : 'fail', res.map((x) => `${x.d.id}=${x.c.n}`).join(' '));
          artSave('BOOT-CONVERGE', `${p.replace(/[:%]/g, '_')}-counts.json`, res.map((x) => { return { device: x.d.id, n: x.c.n }; }));
          if (equal && ns[0] > 0) {
            // ★ 0.241.0.7 修瞬态假红（R20261015115552 实锤：行数已收敛而键集/值长仍在途——单次快照判死，下一轮自愈）：
            //   签名一致也走 settle 轮询（≤120s，每 12s 复查三端）——fresh 后云端增量分批下行有先后，瞬态在途自愈为绿；
            //   持续分叉（120s 仍不一致）才定性 fail（LWW 残留/墓碑压制转 app 修复迭代）
            let sigs = [], sigEq = false;
            for (let t = 0; t < 10 && !sigEq; t++) {
              sigs = []; for (const d of devs) sigs.push({ d, s: await dbSignature(d.serial, p) });
              const hs = sigs.map((x) => x.s.hash);
              sigEq = hs.every((h) => h === hs[0]);
              if (!sigEq && t < 9) await sleep(12000);
            }
            ctx.log(`${domain} [${p}] 键集签名`, sigEq ? 'pass' : 'fail', sigs.map((x) => `${x.d.id}=${x.s.hash}(${x.s.lines})`).join(' ') + (sigEq ? '' : '——120s 轮询后仍分叉（行数同而内容异）：LWW 残留/墓碑压制问题，转 app 修复迭代'));
          }
        }
      }
    } },

  // ---------- 功能② 云同步四域数据链 ----------
  { id: 'SYNC-SWITCH', suite: 'sync', name: '云同步开关落盘核验', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      const g = await grepPref(serial, 'cloud-sync-switch');
      if (g.found) ctx.log('cloud-sync-switch', 'pass', `${g.path} → ${g.sample}`);
      else ctx.log('cloud-sync-switch', 'warn', `候选路径未命中（${g.tried.join(' / ')}）——持久化文件登录/开同步后生成，此通道为尽力确认`);
      if (canUiDump(dev)) { const d = await ctx.art.dump(`SYNC-SWITCH-${dev.id}`, 'dump-ui.json', serial); ctx.log('UI 状态快照', d.ok ? 'pass' : 'warn', 'dumpLayout 已存证（设置页开关态人工抽查）'); }
      else uiSkip(ctx.log, dev, 'UI 状态快照');
    } },
  // ★ 0.266.0.1 新增（§12.13 军令，app 0.266.0 配套）：云同步页「关闭云同步」入口——
  //   真实路径复刻：设置→云同步 Tab→（前置自愈：未开则先开）→断言「关闭云同步」按钮在→点击→
  //   状态卡翻「云同步未开启」+「开启云同步」回归→重开恢复（收尾不留脏态）。
  //   前置=已登录+已授权设备（sync 套件 BOOT 链后标准态；未登录如实 skip 不虚构）；全程无授权页 semi:false
  { id: 'SYNC-CLOSE', suite: 'sync', name: '云同步关闭入口·关→状态翻转→重开恢复（0.266.0 新 UI：开启态渲染「关闭云同步」按钮）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      const isPc = !canUiDump(dev);
      const click = (kw, o) => (isPc ? pcClickText(serial, kw, o) : uiClickText(serial, kw, o));
      // 前置①：已登录（未登录如实 skip——本用例不动登录链路，避免与 login 套件边界纠缠）
      if (isPc) {
        const loginOk = (await grepPref(serial, 'huawei-account')).found;
        if (!loginOk) { ctx.log('前置·登录态', 'skip', 'PC 未登录——先跑 sync-boot/login 套件造登录态'); return; }
      } else {
        await coldStart(serial);
        const n = (await dumpCountText(serial, '已登录')).n;
        if (n === 0) { ctx.log('前置·登录态', 'skip', '未登录——先跑 sync-boot/login 套件造登录态（本用例只测开/关翻转不碰授权）'); return; }
        await agreeDialogIfAny(serial, ctx.log); // 前置自愈（协议撤回态跑 sync 套件时兜底）
      }
      // 前置②：同步须为开启态——导航到云同步 Tab 看状态卡，未开则先开
      if (!isPc && dev.id === 'phone') {
        const csOk = await ensureCanvas(serial, ctx.log);
        const drOk = csOk ? await openPhoneDrawer(serial, ctx.log) : { ok: false };
        if (!drOk.ok) { const dk = await dumpLayout(serial); if (!dk.text.includes('设置')) { ctx.log('⓪ 手机抽屉未开', 'fail', '设置入口不可达'); return; } }
      }
      const s1 = await click('设置', { waitMs: 2500 });
      ctx.log('① 点「设置」', s1.ok ? 'pass' : 'fail', s1.ok ? `已点击 (${s1.x},${s1.y})${isPc ? '@PC 通道' : ''}` : (s1.err || ''));
      if (!s1.ok) return;
      const s2 = await click('云同步', { waitMs: 2200 });
      ctx.log('② 点「云同步」Tab', s2.ok ? 'pass' : 'fail', s2.ok ? `已点击 (${s2.x},${s2.y})` : (s2.err || ''));
      if (!s2.ok) return;
      const has = async (kw) => {
        if (isPc) { for (const disp of [15, 0]) { const d = await dumpAuditNodes(serial, disp); if (d.ok && d.nodes.some((x) => String(x.text || '').includes(kw))) return true; } return false; }
        const d = await dumpLayout(serial);
        return d.ok && d.text.includes(kw);
      };
      if (!(await has('关闭云同步'))) {
        ctx.log('前置·同步未开（无关闭按钮）', 'info', '先开同步造出开启态——点「开启云同步」');
        await ensureSyncPerm(serial, ctx.log); // CLI 预授权（PC 双屏系统弹窗不可靠的根治，openSyncViaSettings 同款）
        const on1 = await click('开启云同步', { waitMs: 3000 });
        if (!on1.ok) { ctx.log('前置·开同步', 'fail', on1.err || '「开启云同步」不可见——状态卡异常，盯屏 /api/dump'); return; }
        await sleep(2500);
        const nowOn = await has('关闭云同步');
        ctx.log('前置·同步已开', nowOn ? 'pass' : 'fail', nowOn ? '「关闭云同步」按钮已渲染（0.266.0 开启态新 UI）' : '开启后仍无关闭按钮——同步开启未生效');
        if (!nowOn) return;
      } else {
        ctx.log('前置·同步已开', 'pass', '「关闭云同步」按钮在屏（0.266.0 开启态新 UI）');
      }
      // ★主链路：点「关闭云同步」→ 状态卡翻「云同步未开启」+「开启云同步」回归
      const c1 = await click('关闭云同步', { exact: true, waitMs: 2600 });
      ctx.log('③ 点「关闭云同步」', c1.ok ? 'pass' : 'fail', c1.ok ? `已点击 (${c1.x},${c1.y})——setCloudSyncEnabled(false) 登录态保持` : (c1.err || ''));
      if (!c1.ok) return;
      await sleep(1800);
      const closed = await has('开启云同步');
      const stillClose = await has('关闭云同步');
      ctx.log('★关闭后状态翻转', closed && !stillClose ? 'pass' : 'fail',
        closed && !stillClose ? '「开启云同步」回归=未开启态 ✓（状态卡+按钮双证）' : `开启钮=${closed} 关闭钮仍在=${stillClose}——盯屏 /api/dump`);
      // 开关落盘（尽力，flush 延迟重试 6 次——0.259.x 同款竞态防御）
      let swOff = false, gSw = null;
      for (let i = 0; i < 6 && !swOff; i++) {
        gSw = await grepPref(serial, 'cloud-sync-switch');
        swOff = !gSw.found || gSw.sample.includes('false');
        if (!swOff) await sleep(2000);
      }
      ctx.log('cloud-sync-switch 关态落盘（尽力）', swOff ? 'pass' : 'warn',
        gSw && gSw.found ? `${gSw.path} → ${gSw.sample.slice(0, 140)}` : '开关文件未生成（关态不落盘）——UI 双证已兜底');
      // 恢复：重开同步（收尾不留脏态——后续 cross 用例依赖同步活）
      await ensureSyncPerm(serial, ctx.log);
      const c2 = await click('开启云同步', { exact: true, waitMs: 2600 });
      ctx.log('④ 恢复·重开云同步', c2.ok ? 'pass' : 'fail', c2.ok ? `已点击 (${c2.x},${c2.y})——恢复开启态` : (c2.err || ''));
      if (!c2.ok) return;
      await sleep(2500);
      const backOn = await has('关闭云同步');
      ctx.log('★重开成功（关闭按钮回归）', backOn ? 'pass' : 'fail', backOn ? '开启态恢复——同步链路完好' : '重开后无「关闭云同步」——开启未生效');
    } },
  { id: 'SYNC-DOMAIN', suite: 'sync', name: '全域多端一致·行数+键集签名（词库/卡片/气泡/墓碑/账户资产）', semi: false, scope: 'cross',
    run: async (ctx) => {
      const devs = ctx.devices;
      if (devs.length < 2) { ctx.log('前置', 'skip', '跨端比对需 ≥2 台在线设备'); return; }
      for (const [domain, prefixes] of Object.entries(CFG.domains)) {
        for (const p of prefixes) {
          const res = [];
          for (const d of devs) { const c = await dbCount(d.serial, p); res.push({ d, c }); }
          const anyBad = res.some((x) => !x.c.ok);
          if (anyBad) { ctx.log(`${domain} ${p}行数`, 'fail', res.map((x) => `${x.d.id}=${x.c.raw}`).join(' ')); continue; }
          const counts = res.map((x) => x.c.n);
          const equal = counts.every((n) => n === counts[0]);
          ctx.log(`${domain} [${p}] 行数`, equal ? 'pass' : 'fail', res.map((x) => `${x.d.id}=${x.c.n}`).join(' '));
          artSave(`SYNC-DOMAIN`, `${p.replace(/[:%]/g, '_')}-counts.json`, res.map((x) => { return { device: x.d.id, n: x.c.n }; }));
          if (equal && counts[0] > 0) {
            const sigs = [];
            for (const d of devs) { const s = await dbSignature(d.serial, p); sigs.push({ d, s }); }
            const hashes = sigs.map((x) => x.s.hash);
            const sigEqual = hashes.every((h) => h === hashes[0]);
            ctx.log(`${domain} [${p}] 键集签名（key|mtime|len）`, sigEqual ? 'pass' : 'fail',
              sigEqual ? `md5=${hashes[0]} ×${devs.length} 端` : res.map((x, i) => `${x.d.id}=${hashes[i]}`).join(' '));
          }
        }
      }
      const h = await hilogErrors(devs[0].serial);
      ctx.log('同步链路 hilog 无错误', h.ok ? (h.n === 0 ? 'pass' : 'fail') : 'warn', h.ok ? `ERROR 计数=${h.n}` : 'hilog 读取异常');
    } },
  { id: 'SYNC-GUARD', suite: 'sync', name: '墓碑纪律回归（0.230.1 四连环修复：重启冲击零自动墓碑+实体行不缩水）', semi: false, scope: 'local',
    // ★ 0.231.0.1 新增（§12.13 测试覆盖军令）：0.228.0 Bug B 复现路径=重启后 flush 以残缺池对账
    //   → del 墓碑批量自动出生+本地物理删行。修后断言：force-stop→冷启 冲击一轮，del 行数不增、
    //   实体行（node/card）不减。云端合法 del 行重下行为基线数（不误报），新增才算违规出生。
    run: async (ctx) => {
      const devs = ctx.devices;
      if (devs.length < 1) { ctx.log('前置', 'skip', '需 ≥1 台在线设备'); return; }
      for (const d of devs) {
        ctx.log(`${d.id} 冲击前基线采集`, 'pass', 'force-stop → 冷启 → 等待首拉 settle（25s）');
        await sh(d.serial, 'aa force-stop ' + CFG.bundle);
        await sleep(1500);
        await coldStart(d.serial, 8000);
        await sleep(25000);
        const delPre = await dbCount(d.serial, 'del:');
        const nodePre = await dbCount(d.serial, 'node:');
        const cardPre = await dbCount(d.serial, 'card:');
        if (!delPre.ok || !nodePre.ok || !cardPre.ok) { ctx.log(`${d.id} sqlite 读取`, 'fail', `del=${delPre.raw} node=${nodePre.raw} card=${cardPre.raw}（未登录/未开同步=空库？）`); continue; }
        ctx.log(`${d.id} 基线`, 'pass', `del=${delPre.n} node=${nodePre.n} card=${cardPre.n}（del 基线含云端合法墓碑重下行）`);
        // Bug B 复现冲击：再来一轮 force-stop→冷启（0.228.0 实锤「无需用户操作重启即触发」）
        await sh(d.serial, 'aa force-stop ' + CFG.bundle);
        await sleep(1500);
        await coldStart(d.serial, 8000);
        await sleep(25000);
        const delPost = await dbCount(d.serial, 'del:');
        const nodePost = await dbCount(d.serial, 'node:');
        const cardPost = await dbCount(d.serial, 'card:');
        ctx.log(`★${d.id} 重启后墓碑纪律`, (delPost.ok && delPost.n <= delPre.n) ? 'pass' : 'fail',
          delPost.ok ? `del ${delPre.n}→${delPost.n}（自动路径出生=违规，修前实测单轮 41 个）` : `读取失败 ${delPost.raw}`);
        ctx.log(`★${d.id} 重启后实体行不缩水`, (nodePost.ok && cardPost.ok && nodePost.n >= nodePre.n && cardPost.n >= cardPre.n) ? 'pass' : 'fail',
          `node ${nodePre.n}→${nodePost.n}，card ${cardPre.n}→${cardPost.n}（缩水=物理删行复活）`);
        artSave('SYNC-GUARD', `${d.id}-restart-impact.json`, { delPre: delPre.n, delPost: delPost.n, nodePre: nodePre.n, nodePost: nodePost.n, cardPre: cardPre.n, cardPost: cardPost.n });
      }
    } },
  { id: 'SYNC-DELETE', suite: 'sync', name: '删除传播（A 删→B 压制，0.228.0 未验项）', semi: true, scope: 'cross',
    run: async (ctx) => {
      const devs = ctx.devices;
      if (devs.length < 2) { ctx.log('前置', 'skip', '跨端验证需 ≥2 台在线设备'); return; }
      const [a, b] = devs;
      const pre = await dbCount(a.serial, 'node:');
      if (!pre.ok || pre.n === 0) { ctx.log('前置：A 端有气泡数据', 'skip', `node 行=${pre.raw}（先登录+造数据）`); return; }
      ctx.log('A 端基线', 'pass', `${a.id} node 行=${pre.n}`);
      const cp = await ctx.checkpoint({ label: `请在【${a.label}】上删除一个气泡（返回画布长按删除）`, deviceId: a.id,
        detect: async () => { const c = await dbCount(a.serial, 'node:'); return c.ok && c.n < pre.n; },
        timeoutMs: CFG.poll.syncTimeoutMs + 60000 });
      if (cp.state === 'timeout') { ctx.log('A 端删除', 'fail', '120s 内未探测到 node 行减少'); return; }
      const after = await dbCount(a.serial, 'node:');
      const del = await dbCount(a.serial, 'del:');
      ctx.log('A 端删除生效', after.n < pre.n ? 'pass' : 'fail', `node ${pre.n}→${after.n}，del 墓碑行=${del.ok ? del.n : del.raw}`);
      const ok = await pollUntil(async () => { const c = await dbCount(b.serial, 'node:'); return c.ok && c.n === after.n; }, CFG.poll.syncTimeoutMs);
      const bAfter = await dbCount(b.serial, 'node:');
      const bDel = await dbCount(b.serial, 'del:');
      ctx.log('★删除传播到 B 端', ok ? 'pass' : 'fail', `${b.id} node=${bAfter.ok ? bAfter.n : bAfter.raw}（期望=${after.n}），del=${bDel.ok ? bDel.n : bDel.raw}`);
      if (canUiDump(b)) await ctx.art.dump('SYNC-DELETE', `dump-b-${b.id}.json`, b.serial);
    } },
  { id: 'SYNC-PULL-ZERO', suite: 'sync', name: '从零全量下拉（不复活僵尸——乱象正面测试）', semi: true, scope: 'cross',
    run: async (ctx) => {
      const devs = ctx.devices;
      if (devs.length < 2) { ctx.log('前置', 'skip', '需 ≥2 台（A 端做云端基线，B 端从零拉取）'); return; }
      const [a, b] = devs;
      const base = {};
      for (const [domain, prefixes] of Object.entries(CFG.domains)) {
        base[domain] = [];
        for (const p of prefixes) { const c = await dbCount(a.serial, p); base[domain].push({ p, n: c.ok ? c.n : null }); }
      }
      artSave('SYNC-PULL-ZERO', 'baseline-a.json', base);
      ctx.log('A 端云端基线', 'pass', `node=${base['气泡树+聊天内容'][0].n} word=${base['单词库'][0].n} card=${base['知识库'][0].n}`);
      const un = await bmUninstall(b.serial);
      ctx.log('B 端卸载', un.ok ? 'pass' : 'fail', un.detail);
      const ins = await bmInstall(b.serial);
      ctx.log('B 端重装最新 HAP', ins.ok ? 'pass' : 'fail', ins.detail);
      if (!ins.ok) return;
      await coldStart(b.serial, 12000);
      const cp = await ctx.checkpoint({ label: `请在【${b.label}】上完成登录（建议设置→云同步入口），等待全量下拉`, deviceId: b.id,
        detect: async () => { const c = await dbCount(b.serial, null); return c.ok && c.n > 0; },
        timeoutMs: 300000 });
      if (cp.state === 'timeout') { ctx.log('B 端登录/下拉', 'fail', '300s 内 cloud_data 仍为空'); return; }
      ctx.log('B 端全量下拉启动', 'pass', 'cloud_data 行数>0');
      await pollUntil(async () => { const x = await dbCount(b.serial, 'node:'); const y = await dbCount(a.serial, 'node:'); return x.ok && y.ok && x.n === y.n; }, CFG.poll.syncTimeoutMs);
      for (const [domain, prefixes] of Object.entries(CFG.domains)) {
        for (const p of prefixes) {
          const ca = await dbCount(a.serial, p); const cb = await dbCount(b.serial, p);
          if (!ca.ok || !cb.ok) { ctx.log(`${domain} [${p}] 对齐`, 'fail', `A=${ca.raw} B=${cb.raw}`); continue; }
          ctx.log(`${domain} [${p}] 对齐`, ca.n === cb.n ? 'pass' : 'fail', `A=${ca.n} B=${cb.n}`);
        }
      }
      const sa = await dbSignature(a.serial, 'node:'); const sb = await dbSignature(b.serial, 'node:');
      ctx.log('★node 键集签名对齐', sa.hash && sb.hash && sa.hash === sb.hash ? 'pass' : 'fail', `A=${sa.hash} B=${sb.hash}（不一致=复活/丢失行）`);
      if (canUiDump(b)) await ctx.art.dump('SYNC-PULL-ZERO', 'dump-b-pulled.json', b.serial);

    } },
  // ★ 0.248.7 SP 实扣链路配套（§12.13 军令）：真机发一条 AI 消息 → 操作端 cfg:siyi-points 行 consumed 三项之和
  //   增大（回复完成实扣+3s 防抖上行）→ 其余端冷启拉取后同步到同值。余额为 0 时发送被拦（本条应跳过并提示充值）。
  { id: 'SP-CONSUME', suite: 'sync', name: 'SP 实扣+多端同步（★0.248.7：发 AI 消息→操作端 consumed 增→其余端一致）', semi: true, scope: 'cross',
    run: async (ctx) => {
      const devs = ctx.devices;
      const op = devs[0];
      if (!canUiDump(op)) { uiSkip(ctx.log, op, 'SP 实扣（UI 操作专属——操作端须可 dump）'); return; }
      const readSiyi = async (serial) => {
        const { out, bad } = await sqliteQuery(serial, "select value from cloud_data where key='cfg:siyi-points'");
        if (bad || !out.trim()) { return { ok: false, raw: String(out).slice(0, 80) }; }
        try {
          const v = JSON.parse(out.trim());
          const consumed = (v.consumedGiftSp || 0) + (v.consumedBonusSp || 0) + (v.consumedPermanentSp || 0);
          const balance = Math.max(0, (v.permanentSp || 0) - (v.consumedPermanentSp || 0)) + Math.max(0, (v.bonusSp || 0) - (v.consumedBonusSp || 0)) + Math.max(0, (v.giftSp || 0) - (v.consumedGiftSp || 0));
          return { ok: true, consumed, balance, raw: JSON.stringify(v).slice(0, 180) };
        } catch (e) { return { ok: false, raw: 'JSON坏行：' + String(out).slice(0, 60) }; }
      };
      const b0 = await readSiyi(op.serial);
      if (!b0.ok) { ctx.log('前置·操作端 siyi 行', 'fail', `读取失败（${b0.raw}）——未登录/未开同步=空库，先跑 sync-boot`); return; }
      ctx.log('前置·基线', 'pass', `consumed 合计=${b0.consumed} · 余额=${b0.balance}（${op.label}）`);
      if (b0.balance <= 0) { ctx.log('前置·余额闸门', 'fail', '余额=0——发送应被拦截（0.248.7 闸门）；先充能/兑换后再测实扣'); return; }
      // ① 冷启→画布→有对话气泡→双击进对话页（复刻 CHAT-KEEP 路径）
      await coldStart(op.serial);
      let nav = await uiClickText(op.serial, '气泡树', { waitMs: 2200 });
      if (!nav.ok) { nav = await uiClickText(op.serial, '进入气泡树', { waitMs: 2600 }); }
      if (!nav.ok) { await sh(op.serial, 'uitest uiInput keyEvent Back', 15000); await sleep(1500); nav = await uiClickText(op.serial, '气泡树', { waitMs: 2200 }); }
      if (!nav.ok) { ctx.log('① 进画布', 'fail', '「气泡树」入口未命中'); return; }
      const d0 = await dumpLayout(op.serial);
      const hits = findNodeBoundsAll(d0.text, '条对话').filter((h) => !String(h.text).includes('个气泡'));
      if (!hits.length) { ctx.log('① 找对话气泡', 'fail', '画布无「N条对话」气泡卡——先造一条对话'); return; }
      const target = hits[hits.length - 1];
      await uiDoubleClick(op.serial, target.x, target.y);
      await sleep(2200);
      // ② 找输入框（hint「输入问题...」）注入并点「发送」
      const d1 = await dumpLayout(op.serial);
      const inBox = findNodeHintAll(d1.text, '输入问题')[0];
      if (!inBox) { ctx.log('② 定位输入框', 'fail', '未命中 hint「输入问题...」（未进对话页？）'); return; }
      const probe = 'SP' + String(Date.now()).slice(-6);
      const it = await uiInputText(op.serial, inBox.x, inBox.y, probe);
      if (!it.ok) { ctx.log('② 注入文本', 'fail', it.raw || 'inputText 失败'); return; }
      const sd = await uiClickText(op.serial, '发送', { waitMs: 2000 });
      ctx.log('② 发送', sd.ok ? 'pass' : 'fail', sd.ok ? `已发送「${probe}」(${op.label})` : '「发送」按钮未命中');
      if (!sd.ok) { return; }
      // ③ 轮询操作端 consumed 增大（AI 回复完成才扣——0.248.7 实扣时点）
      const grown = await pollUntil(async () => { const c = await readSiyi(op.serial); return c.ok && c.consumed > b0.consumed; }, 150000);
      const b1 = await readSiyi(op.serial);
      ctx.log('★操作端 SP 实扣', grown && b1.ok ? 'pass' : 'fail',
        grown && b1.ok ? `consumed ${b0.consumed} → ${b1.consumed}（+${b1.consumed - b0.consumed}，余额 ${b1.balance}）——AI 回复完成实扣实锤` : `150s 内 consumed 未增（${b1.ok ? b1.raw : b1.raw}）——回复未完成/未扣点/上行未落，结合 chat 套件排查`);
      // ④ 其余端冷启拉取→同步到新 consumed（cross 一致性）
      const rest = devs.slice(1);
      for (const rd of rest) {
        await sh(rd.serial, 'aa force-stop ' + CFG.bundle);
        await sleep(1200);
        await coldStart(rd.serial, 10000);
      }
      if (rest.length) {
        const synced = await pollUntil(async () => {
          for (const rd of rest) { const c = await readSiyi(rd.serial); if (!c.ok || c.consumed < b1.consumed) { return false; } }
          return true;
        }, 150000);
        const finals = [];
        for (const rd of devs) { const c = await readSiyi(rd.serial); finals.push(`${rd.id}=${c.ok ? c.consumed : 'ERR'}`); }
        ctx.log('★多端 consumed 一致', synced ? 'pass' : 'fail', finals.join(' ') + (synced ? '（实扣已同步）' : '——150s 未同步到（该端未登录/未开同步？）'));
      }
      artSave('SP-CONSUME', 'siyi-points.json', { before: b0, after: b1, at: now() });
    } },

  // ============================================================
  // ★ 0.299.2.1 SP 司忆点云同步专项套件（bug1 定性五件套——用户 2026-10-23 指派：
  //   现象=PC 200万 SP / Pad 冷装登录气泡全到但 SP=0 / 设备重启 SP 归 0。
  //   嫌疑链三条：①云端 cfg:siyi-points 行缺失或过期（上行链断）②P2 'siyi-points-v1'
  //   单 key 水合失败（0.299.2 bug5 同族——盘值真运行时恒 0）③首拉闸门未开 SP 变动从未上行。
  //   五条用例：审计（静态定性）/重启恢复/冷装首拉/签到跨端/长时监控。
  // ============================================================

  // SP-AUDIT ①：三端静态审计（零破坏）——行存在性+内容+chunk 分片+P2 盘值 四位一体，一次跑完定性
  { id: 'SP-AUDIT', suite: 'sp', name: 'SP 资产静态审计（三端行值+chunk 分片+P2 盘值——bug1 定性主刀·零破坏）', semi: false, scope: 'cross',
    run: async (ctx) => {
      const devs = ctx.devices;
      if (!devs.length) { ctx.log('前置', 'skip', '无在线设备'); return; }
      // 行值解析（含余额口径——与 app BillingPage 同源：max(0,池-消耗) 三池合计）
      const parseSiyi = (raw) => {
        try {
          const v = JSON.parse(raw);
          const balance = Math.max(0, (v.permanentSp || 0) - (v.consumedPermanentSp || 0))
            + Math.max(0, (v.bonusSp || 0) - (v.consumedBonusSp || 0))
            + Math.max(0, (v.giftSp || 0) - (v.consumedGiftSp || 0));
          let signed = -1;
          try { signed = (JSON.parse(v.signedDates || '[]') || []).length; } catch (_e) { signed = -1; }
          let pkgs = -1;
          try { pkgs = (JSON.parse(v.iapPackages || '[]') || []).length; } catch (_e) { pkgs = -1; }
          return { ok: true, permanentSp: v.permanentSp || 0, bonusSp: v.bonusSp || 0, giftSp: v.giftSp || 0,
            consumed: (v.consumedPermanentSp || 0) + (v.consumedBonusSp || 0) + (v.consumedGiftSp || 0),
            balance, welcomeGranted: !!v.welcomeGranted, signed, pkgs, rookieDone: v.rookieDoneJson || '', rookieGranted: v.rookieGrantedJson || '' };
        } catch (e) { return { ok: false, raw: String(raw).slice(0, 60) }; }
      };
      // P2 盘值抽取（★实测盘路径=haps/entry/files/persistent_storage——0.299.2.1 首跑实锤少了 haps/entry 层；
      //   busybox grep 不支持 \{0,N\} 量词——改无量词特征串，实测可用）
      const readDisk = async (serial) => {
        const out = await sh(serial, `grep -o -E '(permanentSp|bonusSp|giftSp|consumedPermanentSp|consumedBonusSp|consumedGiftSp|welcomeGranted)[^,}]*' ${CFG.sandboxBase}/haps/entry/files/persistent_storage 2>/dev/null | head -8`, 15000);
        if (!out || SH_ERR_RE.test(out)) return { hit: false, raw: String(out).slice(0, 60) };
        const num = (k) => { const m = out.match(new RegExp(k + '\\\\?&?quot;?:([0-9]+|true|false)')); return m ? m[1] : null; };
        const p = num('permanentSp'); const c = num('consumedPermanentSp'); const w = num('welcomeGranted');
        return { hit: p !== null, permanentSp: p, consumedPermanentSp: c, welcomeGranted: w, raw: '盘数字命中 len=' + out.length };
      };
      const snaps = [];
      for (const d of devs) {
        const r = await sqliteQuery(d.serial, "select value || '|' || updated_at from cloud_data where key='cfg:siyi-points'");
        if (r.bad || !r.out.trim()) {
          ctx.log(`①行存在性·${d.label}`, 'fail', `cfg:siyi-points 行缺失（${(r.out || r.raw || '空').toString().slice(0, 40)}）——该端本地 RDB 无 SP 行=云端行从未拉到或从未上行（未登录/未开同步先跑 sync-boot；已开=上行链断实锤）`);
          snaps.push({ dev: d, row: null });
          continue;
        }
        const [val, ts] = r.out.split('|');
        const p = parseSiyi(val);
        if (!p.ok) { ctx.log(`①行解析·${d.label}`, 'fail', `JSON 坏行：${p.raw}`); snaps.push({ dev: d, row: null }); continue; }
        const age = Math.round((Date.now() - parseInt(ts, 10)) / 60000);
        ctx.log(`①行值·${d.label}`, 'pass', `余额=${p.balance.toLocaleString()}（永久${p.permanentSp.toLocaleString()}+嘉奖${p.bonusSp.toLocaleString()}+赠${p.giftSp.toLocaleString()}·已耗${p.consumed.toLocaleString()}）·签${p.signed}天·包${p.pkgs}个·礼包${p.welcomeGranted ? '已发' : '未发'}·行龄${age}分钟`);
        const ch = await dbCount(d.serial, 'cfg:siyi-points~');
        if (ch.ok && ch.n > 0) ctx.log(`②chunk 分片·${d.label}`, 'warn', `检测到 ${ch.n} 条 cfg:siyi-points~N 分片行——SP 行超 512KB 被应用层拆片，缺片=整行丢弃+闸门不开（SP 恒 0 嫌疑之一），结合 SP-MONITOR 观察`);
        const disk = await readDisk(d.serial);
        if (!disk.hit) ctx.log(`③P2 盘值·${d.label}`, 'warn', `persistent_storage 未抽出 siyi-points-v1 条目（${disk.raw}）——条目缺失=重启 SP 归 0 实锤方向；grep 格式不适配也可能，人工复核：hdc shell cat ${CFG.sandboxBase}/files/persistent_storage`);
        else if (disk.permanentSp !== null && disk.permanentSp < p.permanentSp) ctx.log(`③P2 盘值·${d.label}`, 'fail', `盘值落后：盘 permanentSp=${disk.permanentSp} < 行值=${p.permanentSp}——下行 merge 后写回 P2 失败/未持久化（水合族嫌疑），重启将回退旧值`);
        else ctx.log(`③P2 盘值·${d.label}`, 'pass', `盘 permanentSp=${disk.permanentSp}（≥行值 ${p.permanentSp}）——盘账本在位`);
        snaps.push({ dev: d, row: p });
      }
      // 跨端一致性（max/union 收敛后各行六数字应全等）
      const rows = snaps.filter((s) => s.row);
      if (rows.length >= 2) {
        const base = rows[0].row;
        let allEq = true;
        for (const s of rows.slice(1)) {
          const diffs = [];
          for (const k of ['permanentSp', 'bonusSp', 'giftSp', 'consumed', 'balance']) if (s.row[k] !== base[k]) diffs.push(`${k} ${base[k]}↔${s.row[k]}`);
          if (s.row.signed !== base.signed) diffs.push(`签天数 ${base.signed}↔${s.row.signed}`);
          if (s.row.welcomeGranted !== base.welcomeGranted) diffs.push(`礼包标记 ${base.welcomeGranted}↔${s.row.welcomeGranted}`);
          if (diffs.length) { allEq = false; ctx.log(`④跨端一致·${rows[0].dev.label}↔${s.dev.label}`, 'fail', diffs.join('，') + '——max/union 合并未收敛（某端行龄旧=该端拉取滞后；值小端=云端行旧或上行断）'); }
        }
        if (allEq) ctx.log('④跨端一致', 'pass', `${rows.length} 端 SP 账本六数字+签天数+礼包标记全等——云同步收敛达成`);
      } else if (rows.length === 1) {
        ctx.log('④跨端一致', 'warn', '仅 1 端有 SP 行——单端无法比对（其余端见 ① 失败原因）');
      }
      artSave('SP-AUDIT', 'sp-audit.json', { at: now(), snaps: snaps.map((s) => ({ dev: s.dev.id, row: s.row })) });
    } },

  // ★ 0.301.0 SP-ADMIN：SP 数据台链路健康（装机版本+回前台拉取零崩溃+测试台代理配置三断言；
  //   云函数未部署=常态（fetch 静默返 []），本用例只证端侧旁路在位不炸）
  { id: 'SP-ADMIN-LINK', suite: 'sp', name: 'SP 数据台链路健康（0.301.0：版本≥1000440+冷启拉取零 JSError+测试台代理状态）', semi: false, scope: 'cross',
    run: async (ctx) => {
      const devs = ctx.devices;
      if (!devs.length) { ctx.log('前置', 'skip', '无在线设备'); return; }
      for (const d of devs) {
        // ①装机版本（bm dump 实读——SpAdminUtil+三挂点随 1000440 上车）
        const bm = await sh(d.serial, 'bm dump -n com.dagaichat.app', 15000);
        const m = String(bm).match(/"versionCode":\s*(\d+)/);
        const vc = m ? parseInt(m[1], 10) : 0;
        if (vc >= 1000440) ctx.log(`①版本·${d.label}`, 'pass', `versionCode ${vc} ≥ 1000440（SpAdminUtil 镜像上报/指令拉取已上车）`);
        else ctx.log(`①版本·${d.label}`, 'fail', `versionCode ${vc} < 1000440——SP 数据台端侧未上车，装机最新 HAP 后重跑`);
        // ②冷启拉取链路零崩溃（onCreate→onForeground 触发 pullSpAdminCommands；未部署=静默降级，任何 JSError=红）
        await sh(d.serial, 'aa start -a EntryAbility -b com.dagaichat.app', 10000);
        await sleep(4000);
        const hlog = await sh(d.serial, 'hilog -x -z 5000 2>/dev/null | grep -i -E "JsError|sp-admin" | head -5', 15000);
        if (/JsError/i.test(String(hlog))) ctx.log(`②拉取零崩溃·${d.label}`, 'fail', `捕获 JSError：${String(hlog).slice(0, 120)}`);
        else ctx.log(`②拉取零崩溃·${d.label}`, 'pass', '冷启+回前台链路无 JSError（sp-admin 未部署时 fetch 静默属预期，部署后自动全链生效）');
      }
      // ③服务端代理配置（本机测试台 config——fnUrl 空=未部署属常态非缺陷）
      const cfg = CFG.spAdmin || {};
      if (cfg.fnUrl && cfg.token) ctx.log('③测试台代理', 'pass', 'spAdmin.fnUrl/token 已配置——「📊 SP 数据」tab 可直接查询/下指令');
      else ctx.log('③测试台代理', 'warn', 'spAdmin.fnUrl/token 未配置——SP tab 将提示未部署（部署指引 docs/cloud/sp-admin/部署指引.md；app 侧零改动权益式生效）');
    } },

  // SP-RESTART ②：冷启 SP 恢复监控——「重启归 0」专项（数据层三快照 + UI 层余额锚点）
  { id: 'SP-RESTART', suite: 'sp', name: '冷启动 SP 恢复（重启归 0 专项：force-stop→冷启→盘值/行值/不降断言+UI 余额锚点）', semi: true, scope: 'cross',
    run: async (ctx) => {
      const devs = ctx.devices;
      if (!devs.length) { ctx.log('前置', 'skip', '无在线设备'); return; }
      const readBal = async (serial) => {
        const { out, bad } = await sqliteQuery(serial, "select value from cloud_data where key='cfg:siyi-points'");
        if (bad || !out.trim()) return { ok: false, n: 0 };
        try { const v = JSON.parse(out); return { ok: true, n: Math.max(0, (v.permanentSp || 0) - (v.consumedPermanentSp || 0)) + Math.max(0, (v.bonusSp || 0) - (v.consumedBonusSp || 0)) + Math.max(0, (v.giftSp || 0) - (v.consumedGiftSp || 0)), permanentSp: v.permanentSp || 0 }; }
        catch (e) { return { ok: false, n: 0 }; }
      };
      for (const d of devs) {
        const b0 = await readBal(d.serial);
        if (!b0.ok) { ctx.log(`前置·${d.label}`, 'skip', '无 SP 行/坏行（先跑 SP-AUDIT 定性）'); continue; }
        if (b0.n <= 0) { ctx.log(`前置·${d.label}`, 'skip', `当前行余额=0（发送会被闸门拦）——充值/兑换后再测本端`); continue; }
        await coldStart(d.serial, 9000);
        const b1 = await readBal(d.serial);
        const disk = await sh(d.serial, `grep -o -E 'permanentSp[^,}]*' ${CFG.sandboxBase}/haps/entry/files/persistent_storage 2>/dev/null | head -2`, 15000);
        const diskSp = (() => { const m = disk.match(/permanentSp\\?&?quot?:([0-9]+)/); return m ? parseInt(m[1], 10) : null; })();
        ctx.log(`①冷启后行值·${d.label}`, b1.ok && b1.n >= b0.n ? 'pass' : 'fail',
          b1.ok ? `余额 ${b0.n.toLocaleString()} → ${b1.n.toLocaleString()}（${b1.n >= b0.n ? '未回退' : '回退！下行 reconcile 未拉回/闸门链断'}）` : '冷启后行读取失败');
        if (diskSp !== null) ctx.log(`②冷启后盘值·${d.label}`, diskSp >= b0.permanentSp ? 'pass' : 'fail', `盘 permanentSp=${diskSp.toLocaleString()}（行值 ${b0.permanentSp.toLocaleString()}）——盘小=水合写入链断（重启归 0 根因方向）`);
        else ctx.log(`②冷启后盘值·${d.label}`, 'warn', '盘条目未抽出（格式不适配/条目缺失——人工 cat 复核）');
        const steady = await pollUntil(async () => { const c = await readBal(d.serial); return c.ok && c.n >= b0.n; }, 90000);
        ctx.log(`③90s 稳定性·${d.label}`, steady ? 'pass' : 'fail', steady ? '余额持续不低于冷启前——无闪断回 0' : '90s 内余额跌破基线（意外归 0 活体证据——结合 SP-MONITOR 时间线）');
        // UI 层锚点（仅 UI 通道端；无通道如实 skip）
        if (canUiDump(d)) {
          const cp = await ctx.checkpoint({ label: `请在【${d.label}】进入「设置 → SP与账单（账单页）」，停在能看到 SP 余额的位置`, deviceId: d.id,
            detect: async () => { const t = await dumpLayout(d.serial); return /嘉奖 SP|充能 SP|暂无余额/.test(t.text); },
            timeoutMs: 120000 });
          if (cp.state === 'timeout') { ctx.log(`④UI 余额显示·${d.label}`, 'skip', '120s 未就位（跳过 UI 断言，数据层结论仍有效）'); continue; }
          const t = await dumpLayout(d.serial);
          await ctx.art.dump('SP-RESTART', `dump-${d.id}.json`, d.serial);
          const zero = /暂无余额/.test(t.text);
          const hasSp = /嘉奖 SP|充能 SP/.test(t.text);
          ctx.log(`④UI 余额显示·${d.label}`, zero ? 'fail' : (hasSp ? 'pass' : 'warn'),
            zero ? `界面显示「暂无余额」而行余额=${b0.n.toLocaleString()}——★重启归 0 用户现象活体复现（UI 读 store 与行/RDB 脱节——P2 水合族）`
              : (hasSp ? '界面正常展示 SP 余额（嘉奖/充能行在位）' : '未识别到余额锚点文本（页面可能未到位）'));
        } else ctx.log(`④UI 余额显示·${d.label}`, 'skip', '无 UI 断言通道（数据层结论为准）');
      }
    } },

  // SP-COLD-FULL ③：冷装首拉 SP 到位——用户 Pad 场景复刻（B 端卸载重装→登录→SP 行必须到且与云端全等）
  { id: 'SP-COLD-FULL', suite: 'sp', name: '冷装首拉 SP（卸载重装→登录→SP 行到位且全等+礼包不重发——用户 Pad 场景）', semi: true, scope: 'cross',
    run: async (ctx) => {
      const devs = ctx.devices;
      if (devs.length < 2) { ctx.log('前置', 'skip', '需 ≥2 台（A 端云端基线，B 端冷装验证）'); return; }
      const [a, b] = devs;
      const readRaw = async (serial) => { const { out, bad } = await sqliteQuery(serial, "select value from cloud_data where key='cfg:siyi-points'"); return { bad, out: out.trim() }; };
      const ra = await readRaw(a.serial);
      if (ra.bad || !ra.out) { ctx.log('前置·A 端基线', 'fail', `A 端（${a.label}）无 SP 行——云端账本不存在，冷装端必为 0（先在 A 端登录开同步跑 SP-AUDIT）`); return; }
      let va = null; try { va = JSON.parse(ra.out); } catch (e) { ctx.log('前置·A 端基线', 'fail', 'A 端 SP 行 JSON 坏'); return; }
      ctx.log('前置·A 端云端基线', 'pass', `permanentSp=${(va.permanentSp || 0).toLocaleString()}·welcomeGranted=${va.welcomeGranted}（${a.label}）`);
      ctx.log('⚠️破坏性提示', 'info', `本条将卸载重装【${b.label}】（B 端本地数据全清——与用户冷装路径一致）`);
      const un = await bmUninstall(b.serial);
      ctx.log('①B 端卸载', un.ok ? 'pass' : 'fail', un.detail);
      const ins = await bmInstall(b.serial);
      ctx.log('②B 端重装', ins.ok ? 'pass' : 'fail', ins.detail);
      if (!ins.ok) return;
      await coldStart(b.serial, 12000);
      const cp = await ctx.checkpoint({ label: `请在【${b.label}】上完成：协议同意 → 登录华为账号（同 A 端账号）→ 云同步开启`, deviceId: b.id,
        detect: async () => { const c = await dbCount(b.serial, null); return c.ok && c.n > 0; },
        timeoutMs: 300000 });
      if (cp.state === 'timeout') { ctx.log('③B 端登录/首拉', 'fail', '300s 内 cloud_data 仍为空（登录未完成或首拉链死）'); return; }
      const ok = await pollUntil(async () => { const r = await readRaw(b.serial); return !r.bad && !!r.out; }, CFG.poll.syncTimeoutMs);
      const rb = await readRaw(b.serial);
      if (!ok || !rb.out) { ctx.log('★冷装 SP 行到位', 'fail', `气泡行已到而 SP 行 90s 未到——★用户现象（Pad SP=0）活体复现：云端行缺失或 SP 行下行滞后（对照 A 端基线与 SP-AUDIT 结论定性）`); return; }
      let vb = null; try { vb = JSON.parse(rb.out); } catch (e) { ctx.log('★冷装 SP 行解析', 'fail', 'B 端 SP 行 JSON 坏'); return; }
      const diffs = [];
      for (const k of ['permanentSp', 'bonusSp', 'giftSp', 'consumedPermanentSp', 'consumedBonusSp', 'consumedGiftSp']) {
        if ((va[k] || 0) !== (vb[k] || 0)) diffs.push(`${k} 云${va[k] || 0}↔B${vb[k] || 0}`);
      }
      ctx.log('★冷装 SP 全等', diffs.length ? 'fail' : 'pass',
        diffs.length ? diffs.join('，') + '——max 合并未收敛（90s 窗口短或行旧）' : `六数字与云端全等（permanentSp=${(vb.permanentSp || 0).toLocaleString()}）——冷装首拉 SP 到位 ✓`);
      ctx.log('★礼包不重发', va.welcomeGranted && vb.welcomeGranted ? 'pass' : 'warn',
        `云端=${va.welcomeGranted} 冷装=${vb.welcomeGranted}（老账号重装须保持 true——false+余额突增=礼包重发 Bug A 复发）`);
      artSave('SP-COLD-FULL', 'sp-cold.json', { a: va, b: vb, at: now() });
    } },

  // SP-SIGNIN-CROSS ④：签到跨端一致（0.293.0 场景①——一端签到→三端已签）
  { id: 'SP-SIGNIN-CROSS', suite: 'sp', name: '签到跨端一致（操作端签到→行 signedDates 增→其余端冷启后并集一致）', semi: true, scope: 'cross',
    run: async (ctx) => {
      const devs = ctx.devices;
      if (devs.length < 2) { ctx.log('前置', 'skip', '需 ≥2 台'); return; }
      const op = devs.find((d) => canUiDump(d)) || devs[0];
      const rest = devs.filter((d) => d !== op);
      const readSign = async (serial) => {
        const { out, bad } = await sqliteQuery(serial, "select value from cloud_data where key='cfg:siyi-points'");
        if (bad || !out.trim()) return { ok: false, n: -1 };
        try { const v = JSON.parse(out); let n = -1; try { n = (JSON.parse(v.signedDates || '[]') || []).length; } catch (_e) { } return { ok: true, n }; }
        catch (e) { return { ok: false, n: -1 }; }
      };
      const b0 = await readSign(op.serial);
      if (!b0.ok) { ctx.log('前置·操作端', 'fail', `SP 行缺失（${op.label}——先跑 sync-boot/SP-AUDIT）`); return; }
      ctx.log('前置·基线', 'pass', `signedDates=${b0.n} 天（${op.label}）`);
      const cp = await ctx.checkpoint({ label: `请在【${op.label}】上完成一次签到（画布右上角任务入口/签到弹窗——若今日已签，本条只能验证已签状态跨端一致）`, deviceId: op.id,
        detect: async () => { const c = await readSign(op.serial); return c.ok && c.n > b0.n; },
        timeoutMs: 180000 });
      const b1 = await readSign(op.serial);
      if (cp.state === 'timeout' && b1.n <= b0.n) {
        ctx.log('①操作端签到', 'warn', `180s signedDates 未增（今日已签或未操作）——降级为「已签状态跨端一致」断言`);
      } else {
        ctx.log('①操作端签到', 'pass', `signedDates ${b0.n} → ${b1.n}（+1 上行实锤）`);
      }
      for (const rd of rest) { await sh(rd.serial, 'aa force-stop ' + CFG.bundle); await sleep(1000); await coldStart(rd.serial, 9000); }
      const synced = await pollUntil(async () => { for (const rd of rest) { const c = await readSign(rd.serial); if (!c.ok || c.n < b1.n) return false; } return true; }, 150000);
      const finals = [];
      for (const d of devs) { const c = await readSign(d.serial); finals.push(`${d.id}=${c.ok ? c.n : 'ERR'}`); }
      ctx.log('★签到跨端一致', synced ? 'pass' : 'fail', finals.join(' ') + (synced ? '（并集已传播）' : '——150s 未收敛（未签端=下行滞后或行旧，结合 SP-AUDIT 行龄）'));
    } },

  // SP-MONITOR ⑤：长时旁路监控（5 分钟 5s 采样——捕捉上行时点/传播延迟/意外闪断归 0）
  { id: 'SP-MONITOR', suite: 'sp', name: 'SP 长时监控（5 分钟旁路采样：行值/updated_at/签天数变化时间线——零打扰）', semi: false, scope: 'cross', timeoutMs: 340000,
    run: async (ctx) => {
      const devs = ctx.devices;
      if (!devs.length) { ctx.log('前置', 'skip', '无在线设备'); return; }
      const snap = async (serial) => {
        const { out, bad } = await sqliteQuery(serial, "select value || '|' || updated_at from cloud_data where key='cfg:siyi-points'");
        if (bad || !out.trim()) return null;
        try { const [v, ts] = out.split('|'); const j = JSON.parse(v); let s = -1; try { s = (JSON.parse(j.signedDates || '[]') || []).length; } catch (_e) { }
          return { ts: parseInt(ts, 10), p: j.permanentSp || 0, c: (j.consumedPermanentSp || 0) + (j.consumedBonusSp || 0) + (j.consumedGiftSp || 0), s }; }
        catch (e) { return null; }
      };
      const prev = {}; const timeline = [];
      for (const d of devs) { prev[d.id] = await snap(d.serial); if (prev[d.id]) ctx.log(`基线·${d.label}`, 'info', `余额=${(prev[d.id].p - prev[d.id].c).toLocaleString()}·行龄=${Math.round((Date.now() - prev[d.id].ts) / 60000)}分钟`); else ctx.log(`基线·${d.label}`, 'warn', '无 SP 行（该端采样空转）'); }
      const t0 = Date.now(); const DUR = 5 * 60 * 1000;
      while (Date.now() - t0 < DUR) {
        await sleep(5000);
        for (const d of devs) {
          const cur = await snap(d.serial);
          if (!cur) continue;
          const p0 = prev[d.id];
          if (!p0 || cur.ts !== p0.ts || cur.p !== p0.p || cur.c !== p0.c || cur.s !== p0.s) {
            const dlt = [];
            if (cur.p !== (p0 && p0.p)) dlt.push(`池${(p0 ? p0.p : 0).toLocaleString()}→${cur.p.toLocaleString()}`);
            if (cur.c !== (p0 ? p0.c : 0)) dlt.push(`耗${(p0 ? p0.c : 0).toLocaleString()}→${cur.c.toLocaleString()}`);
            if (cur.s !== (p0 ? p0.s : 0)) dlt.push(`签${p0 ? p0.s : 0}→${cur.s}`);
            if (cur.ts !== (p0 && p0.ts)) dlt.push(`行戳+${Math.round((cur.ts - (p0 ? p0.ts : cur.ts)) / 1000)}s`);
            const tag = cur.p === 0 && cur.c === 0 ? '【⚠️归 0 闪断！】' : '';
            ctx.log(`变化·${d.label}@+${Math.round((Date.now() - t0) / 1000)}s`, 'info', tag + (dlt.join(' ') || '行戳更新'));
            timeline.push({ dev: d.id, at: Date.now(), cur, prev: p0 });
          }
          prev[d.id] = cur;
        }
      }
      const finals = devs.map((d) => ({ id: d.id, s: prev[d.id] }));
      const vals = finals.filter((f) => f.s).map((f) => `${f.id}:池${f.s.p.toLocaleString()}/耗${f.s.c}`);
      ctx.log('监控结束·终态', 'info', vals.join(' ') + (timeline.length ? `·共 ${timeline.length} 次变化` : '·全程静默（无 SP 变动——监控期未操作 app 属正常）'));
      if (timeline.length) artSave('SP-MONITOR', 'sp-monitor.json', { at: now(), timeline, finals });
      const eq = (() => { const vs = finals.filter((f) => f.s).map((f) => f.s.p + '/' + f.s.c); return vs.length >= 2 && vs.every((v) => v === vs[0]); })();
      if (finals.filter((f) => f.s).length >= 2) ctx.log('★终态跨端一致', eq ? 'pass' : 'warn', eq ? '监控期末多端账本一致' : '期末不一致（可能收敛窗口未到——重跑 SP-AUDIT 看行龄）');
    } },

  // SP-HYDRATION ⑥：P2 水合哨兵（★华为官方 2026-10-23 答复落地：PersistenceV2 反序列化失败=静默丢弃
  //   条目回退 factory 默认值（错误码 140107 仅日志上报），唯一官方观测通道=notifyOnError——app 已注册
  //   （EntryAbility tag 'DagChat'，msg 形如 'persistence error key=... reason=... msg=...'）。
  //   本用例=冷启窗口抓该日志：命中 siyi-points-v1/huawei-account =「重启 SP 归 0 / 冷启掉登录态」根因活体实锤）
  { id: 'SP-HYDRATION', suite: 'sp', name: 'P2 水合哨兵（清 hilog→冷启→抓 notifyOnError——140107 静默丢弃实锤通道）', semi: false, scope: 'cross',
    run: async (ctx) => {
      const devs = ctx.devices;
      if (!devs.length) { ctx.log('前置', 'skip', '无在线设备'); return; }
      for (const d of devs) {
        await sh(d.serial, 'hilog -r', 12000);
        await coldStart(d.serial, 12000);
        const out = await sh(d.serial, `hilog -x 2>/dev/null | grep -i "persistence error" | head -20`, 25000);
        const lines = String(out).split('\n').map((s) => s.trim()).filter((s) => s && /persistence error/i.test(s));
        if (!lines.length) {
          ctx.log(`①水合哨兵·${d.label}`, 'pass', '冷启窗口无 P2 反序列化/配额错误（本会话水合健康）');
        } else {
          const keys = lines.map((l) => (l.match(/key=([^ ]+)/) || [])[1]).filter(Boolean);
          const hitSiyi = keys.some((k) => /siyi|huawei-account/.test(k || ''));
          ctx.log(`①水合哨兵·${d.label}`, hitSiyi ? 'fail' : 'warn',
            `捕获 ${lines.length} 条 persistence error：${[...new Set(keys)].join(',') || lines[0].slice(0, 120)}`
            + (hitSiyi ? '——★命中 SP/账号 key=「重启归 0 / 掉登录态」根因实锤（reason=serialization=类结构不一致被静默丢弃；quota=超配额）' : '（非 SP key——知识库 base64 图等已知场景，另案）'));
          artSave('SP-HYDRATION', `hilog-${d.id}.txt`, { at: now(), lines });
        }
        const disk = await sh(d.serial, `grep -c -E 'permanentSp' ${CFG.sandboxBase}/haps/entry/files/persistent_storage 2>/dev/null`, 15000);
        ctx.log(`②盘条目在位·${d.label}`, disk && !SH_ERR_RE.test(disk) && parseInt(disk, 10) > 0 ? 'pass' : 'warn',
          disk && parseInt(disk, 10) > 0 ? 'persistent_storage 含 siyi-points-v1 条目（haps/entry 真实路径）' : '盘条目未抽出（条目缺失=重启必归 0 实锤方向；格式不适配人工复核）');
      }
    } },

  // SP-GATE-BRANCH ⑦：SP 云服务门卫三分支（★用户 2026-10-23 指派「功能不开/后台不开各种情况全测」+
  //   project_rule SP 铁律：不开云服务=不能获得也不能消耗 SP。三分支：关 app 内云同步开关→
  //   发消息必弹「涉及司忆点」引导（不扣不增）→重开→恢复正常。semi=用户在场配合点开关）
  { id: 'SP-GATE-BRANCH', suite: 'sp', name: 'SP 门卫三分支（关同步→发消息弹引导不扣点→重开恢复——需人工配合点开关）', semi: true, scope: 'cross', timeoutMs: 420000,
    run: async (ctx) => {
      const devs = ctx.devices;
      const op = devs.find((d) => canUiDump(d));
      if (!op) { ctx.log('前置', 'skip', '无 UI 操作端（需 Pad/手机在线）'); return; }
      const readSiyi = async (serial) => {
        const { out, bad } = await sqliteQuery(serial, "select value || '|' || updated_at from cloud_data where key='cfg:siyi-points'");
        if (bad || !out.trim()) return null;
        try { const [v, ts] = out.split('|'); const j = JSON.parse(v); return { ts: parseInt(ts, 10), p: j.permanentSp || 0, c: (j.consumedPermanentSp || 0) + (j.consumedBonusSp || 0) + (j.consumedGiftSp || 0) }; }
        catch (e) { return null; }
      };
      const b0 = await readSiyi(op.serial);
      if (!b0) { ctx.log('前置·基线', 'fail', `操作端（${op.label}）无 SP 行——先跑 sync-boot/SP-AUDIT`); return; }
      ctx.log('前置·基线', 'pass', `余额=${(b0.p - b0.c).toLocaleString()}·行龄=${Math.round((Date.now() - b0.ts) / 60000)}分钟（${op.label}）`);
      // ① 用户关闭云同步开关（GSD 云同步 Tab 关闭，或系统设置-云空间-应用数据同步关）
      const cp1 = await ctx.checkpoint({ label: `请在【${op.label}】上关闭云同步：设置(⚙) → 云同步 → 关闭开关（若弹确认请确认）`, deviceId: op.id, timeoutMs: 240000 });
      if (cp1.state === 'timeout') { ctx.log('①关闭云同步', 'skip', '240s 未确认——本条中止（不判失败）'); return; }
      await coldStart(op.serial, 10000);
      // ② 发消息→必弹「涉及司忆点」引导（不消耗；文案锚点=Index.syncGateMessage 三分支公共词）
      let nav = await uiClickText(op.serial, '气泡树', { waitMs: 2200 });
      if (!nav.ok) { nav = await uiClickText(op.serial, '进入气泡树', { waitMs: 2600 }); }
      if (!nav.ok) { await sh(op.serial, 'uitest uiInput keyEvent Back', 15000); await sleep(1500); nav = await uiClickText(op.serial, '气泡树', { waitMs: 2200 }); }
      if (!nav.ok) { ctx.log('②进画布', 'fail', '「气泡树」入口未命中'); return; }
      const d0 = await dumpLayout(op.serial);
      const hits = findNodeBoundsAll(d0.text, '条对话').filter((h) => !String(h.text).includes('个气泡'));
      if (!hits.length) { ctx.log('②找对话气泡', 'fail', '画布无「N条对话」气泡卡——先造一条对话'); return; }
      await uiDoubleClick(op.serial, hits[hits.length - 1].x, hits[hits.length - 1].y);
      await sleep(2200);
      const d1 = await dumpLayout(op.serial);
      const inBox = findNodeHintAll(d1.text, '输入问题')[0];
      if (!inBox) { ctx.log('②定位输入框', 'fail', '未命中 hint「输入问题...」'); return; }
      const probe = 'GATE' + String(Date.now()).slice(-6);
      await uiInputText(op.serial, inBox.x, inBox.y, probe);
      const sd = await uiClickText(op.serial, '发送', { waitMs: 2500 });
      if (!sd.ok) { ctx.log('②发送', 'fail', '「发送」按钮未命中'); return; }
      await sleep(1800);
      const d2 = await dumpLayout(op.serial);
      await ctx.art.dump('SP-GATE-BRANCH', `dump-guide-${op.id}.json`, op.serial);
      const guided = /涉及司忆点/.test(d2.text);
      ctx.log('★关同步·发送被门卫拦截', guided ? 'pass' : 'fail',
        guided ? '弹出「此功能涉及司忆点（SP）…」引导——SP 铁律生效（未开云服务不消耗）'
          : '未检出引导弹窗（锚点「涉及司忆点」）——可能弹窗已关/文案变更/门卫失效，看 dump 人工定性');
      const b1 = await readSiyi(op.serial);
      const noSpend = b1 ? (b1.c <= b0.c && b1.ts === b0.ts) : true;
      ctx.log('★关同步·零 SP 事务', noSpend ? 'pass' : 'fail',
        b1 ? `消耗 ${b0.c}→${b1.c}·行戳${b1.ts === b0.ts ? '未动' : '变动！'}（关同步期须冻结：不扣不增不上行）` : '行读取失败（关同步后行保留属正常——本地 RDB 不清）');
      // ③ 用户重开云同步→引导应消失可正常发送
      const cp2 = await ctx.checkpoint({ label: `请在【${op.label}】上重新开启云同步（设置 ⚙ → 云同步），等 30s 让首拉闸门完成`, deviceId: op.id, timeoutMs: 240000 });
      if (cp2.state === 'timeout') { ctx.log('③重开云同步', 'warn', '240s 未确认——恢复分支未验证（前两分支结论仍有效）'); return; }
      const recov = await pollUntil(async () => { const c = await dbCount(op.serial, null); return c.ok && c.n > 0; }, 60000);
      ctx.log('③重开·同步恢复', recov ? 'pass' : 'warn', recov ? 'cloud_data 行在位——通路恢复（首拉闸门开后台自动完成，SP 功能随之恢复）' : '60s cloud_data 空——重开未生效或权限/账号态异常（跑 SP-AUDIT 定性）');
    } },


  // ---------- ★ 0.229.25 功能②b 云同步数据链·跨端编排（SYNC-FLOW：真实 UI 产生→云端→对端收敛，验证"链路活不活"） ----------
  // 基线对齐铁律（§12.11）：每条用例复刻真实用户路径——边栏导航→顶栏 +→弹窗输入→保存；断言=settle 轮询对端行数收敛
  { id: 'SYNC-FLOW-WORD', suite: 'syncflow', name: '生词链路·Pad 建词→PC 收敛（边栏→单词库→+→输入→保存）', semi: true, scope: 'cross',
    run: async (ctx) => {
      const fp = await flowPrep(ctx); if (!fp) return;
      const { op, asserts } = fp;
      const word = 'TFW' + String(Date.now()).slice(-6); // 纯字母数字：inputText/转义零风险
      try {
        const baseOp = await dbCount(op.serial, 'word:');
        const bases = []; for (const d of asserts) bases.push({ d, n: (await dbCount(d.serial, 'word:')).n });
        ctx.log('基线', 'pass', `${op.id} word=${baseOp.n}，` + bases.map((x) => `${x.d.id}=${x.n}`).join(' '));
        const nav = await navAnywhere(op, op.serial, '单词库', ctx.log);
        ctx.log('① 边栏「单词库」', nav.ok ? 'pass' : 'warn', nav.ok ? `已点击 (${nav.x},${nav.y})` : (nav.err || '未命中——继续找 +'));
        const plus = await uiClickText(op.serial, '+', { exact: true, waitMs: 1500 });
        if (!plus.ok) { ctx.log('② 顶栏「+」', 'fail', plus.err || '未找到 + 按钮'); return; }
        ctx.log('② 顶栏「+」', 'pass', `已点击 (${plus.x},${plus.y})——弹 + 菜单（0.208.0 bindMenu）`);
        const mi = await uiClickText(op.serial, '新建单词', { exact: true, waitMs: 1800 });
        if (!mi.ok) { ctx.log('③ 菜单「新建单词」', 'fail', mi.err || ''); return; }
        ctx.log('③ 菜单「新建单词」', 'pass', `已点击 (${mi.x},${mi.y})——弹「新增单词」编辑器`);
        await sleep(1000);
        const ed = (await dumpLayout(op.serial));
        const inBox = findNodeHintAll(ed.text, '单词（必填）')[0];
        if (!inBox) { ctx.log('③ 单词输入框定位', 'fail', 'dump 未命中 hint「单词（必填）」（编辑器未弹出或 dump 结构变化）'); return; }
        const it = await uiInputText(op.serial, inBox.x, inBox.y, word);
        ctx.log(`③ 输入单词 ${word}`, it.ok ? 'pass' : 'fail', it.ok ? `已注入 (${inBox.x},${inBox.y})` : (it.raw || 'inputText 失败'));
        if (!it.ok) return;
        // ★ 0.241.0.7 修稳定复现红（R20261015120120/120525 两轮同点位「保存」找不到）：inputText 后软键盘在屏=uitest dump 盲区
        //   （0.230.0.1 实锤：窗口 RESIZE 后 app 子树抓不到——「树中无保存」≠不可达）。keyEvent Back 收键盘再点保存
        //   （编辑器返回键拦截在第二层：Back 只收键盘不关弹窗——B11 0.230.0.1 同款实证修法，0.229.25 遗留项落地）
        await sh(op.serial, 'uitest uiInput keyEvent Back', 15000);
        await sleep(1500);
        ctx.log('④ 收键盘', 'pass', 'keyEvent Back——键盘态 dump 抓不到「保存」（盲区），收起后可达（编辑器不关：拦截在第二层）');
        const sv = await uiClickText(op.serial, '保存', { exact: true, waitMs: 2500 });
        ctx.log('④ 点「保存」', sv.ok ? 'pass' : 'fail', sv.ok ? `已点击 (${sv.x},${sv.y})` : (sv.err || '未找到保存按钮'));
        if (!sv.ok) return;
        const localOk = await pollUntil(async () => { const c = await dbCount(op.serial, 'word:'); return c.ok && c.n === baseOp.n + 1; }, 30000);
        const afterOp = await dbCount(op.serial, 'word:');
        ctx.log('⑤ 操作端落盘', localOk && afterOp.n === baseOp.n + 1 ? 'pass' : 'fail', `${op.id} word ${baseOp.n}→${afterOp.n}（期望 +1）`);
        let all = true;
        for (const b of bases) {
          // ★ 增量断言：期望=断言端自身基线+1（非绝对相等）——存量下拉不齐时增量传播仍可独立验证，
          //   存量差值单独 warn 如实上报（混用绝对相等会把「存量拉取不全」误报成「增量传播失败」）
          const s = await settleCountEquals(b.d.serial, 'word:', b.n + 1, CFG.poll.syncTimeoutMs + 30000, b.d.label);
          const gap = s.ok ? '' : `（存量参考：${b.d.label} 基线=${b.n} vs ${op.label}=${baseOp.n}${b.n !== baseOp.n ? '，存量未齐——存量下拉问题另行定性，本条只验增量' : ''}）`;
          ctx.log(`⑥ ${b.d.label} 云端收敛（基线+1）`, s.ok ? 'pass' : 'fail', `word ${b.n}→${s.n}（期望=${b.n + 1}）${s.ok ? '——上行→云端→下行增量链路活' : gap}`);
          if (!s.ok) all = false;
        }
        if (all && canUiDump(op)) {
          const u = await dumpCountText(op.serial, word);
          ctx.log('⑦ 操作端 UI 可见', u.n >= 1 ? 'pass' : 'warn', `dump 命中「${word}」×${u.n}（列表可能需返回重进——warn 不误报红，数据断言已实证）`);
        }
      } finally {
        for (const d of asserts) { await forceStopApp(d.serial); ctx.log(`收尾·${d.label} 窗口收起`, 'info', 'aa force-stop（PC 外接屏不遮挡——断言已完，同步数据已落盘）'); }
      }
    } },
  { id: 'SYNC-FLOW-CARD', suite: 'syncflow', name: '知识卡链路·Pad 建卡→PC 收敛（边栏→知识库→+→新建卡片→保存）', semi: true, scope: 'cross',
    run: async (ctx) => {
      const fp = await flowPrep(ctx); if (!fp) return;
      const { op, asserts } = fp;
      const title = 'TFC' + String(Date.now()).slice(-6);
      try {
        const baseOp = await dbCount(op.serial, 'card:');
        const bases = []; for (const d of asserts) bases.push({ d, n: (await dbCount(d.serial, 'card:')).n });
        ctx.log('基线', 'pass', `${op.id} card=${baseOp.n}，` + bases.map((x) => `${x.d.id}=${x.n}`).join(' '));
        const nav = await navAnywhere(op, op.serial, '知识库', ctx.log);
        ctx.log('① 边栏「知识库」', nav.ok ? 'pass' : 'warn', nav.ok ? `已点击 (${nav.x},${nav.y})` : (nav.err || '未命中——继续找 +'));
        const plus = await uiClickText(op.serial, '+', { exact: true, waitMs: 1500 });
        if (!plus.ok) { ctx.log('② 顶栏「+」', 'fail', plus.err || '未找到 + 按钮'); return; }
        ctx.log('② 顶栏「+」', 'pass', `已点击 (${plus.x},${plus.y})——弹菜单（0.207.0 + 升级为菜单）`);
        const mi = await uiClickText(op.serial, '新建卡片', { exact: true, waitMs: 2000 });
        if (!mi.ok) { ctx.log('③ 菜单「新建卡片」', 'fail', mi.err || ''); return; }
        ctx.log('③ 菜单「新建卡片」', 'pass', `已点击 (${mi.x},${mi.y})——弹「新增知识卡」编辑器`);
        const ed = (await dumpLayout(op.serial));
        const inBox = findNodeHintAll(ed.text, '标题（必填）')[0];
        if (!inBox) { ctx.log('④ 标题输入框定位', 'fail', 'dump 未命中 hint「标题（必填）」'); return; }
        const it = await uiInputText(op.serial, inBox.x, inBox.y, title);
        ctx.log(`④ 输入标题 ${title}`, it.ok ? 'pass' : 'fail', it.ok ? `已注入 (${inBox.x},${inBox.y})` : (it.raw || 'inputText 失败'));
        if (!it.ok) return;
        // ★ 0.241.0.7 收键盘（同 WORD——键盘态 dump 盲区，Back 只收键盘不关编辑器）
        await sh(op.serial, 'uitest uiInput keyEvent Back', 15000);
        await sleep(1500);
        ctx.log('⑤ 收键盘', 'pass', 'keyEvent Back——收起软键盘，「保存」可达（编辑器不关）');
        const sv = await uiClickText(op.serial, '保存', { exact: true, waitMs: 2500 });
        ctx.log('⑤ 点「保存」', sv.ok ? 'pass' : 'fail', sv.ok ? `已点击 (${sv.x},${sv.y})` : (sv.err || ''));
        if (!sv.ok) return;
        const localOk = await pollUntil(async () => { const c = await dbCount(op.serial, 'card:'); return c.ok && c.n === baseOp.n + 1; }, 30000);
        const afterOp = await dbCount(op.serial, 'card:');
        ctx.log('⑥ 操作端落盘', localOk && afterOp.n === baseOp.n + 1 ? 'pass' : 'fail', `${op.id} card ${baseOp.n}→${afterOp.n}（期望 +1）`);
        for (const b of bases) {
          const s = await settleCountEquals(b.d.serial, 'card:', b.n + 1, CFG.poll.syncTimeoutMs + 30000, b.d.label); // ★ 增量断言：基线+1（存量不齐独立定性）
          ctx.log(`⑦ ${b.d.label} 云端收敛（基线+1）`, s.ok ? 'pass' : 'fail', `card ${b.n}→${s.n}（期望=${b.n + 1}）`);
        }
      } finally {
        for (const d of asserts) { await forceStopApp(d.serial); ctx.log(`收尾·${d.label} 窗口收起`, 'info', 'aa force-stop（断言已完）'); }
      }
    } },
  { id: 'SYNC-FLOW-NODE', suite: 'syncflow', name: '气泡链路·Pad 建气泡→PC 收敛（边栏→气泡树→顶栏 +；node+tab 联合断言）', semi: true, scope: 'cross',
    run: async (ctx) => {
      const fp = await flowPrep(ctx); if (!fp) return;
      const { op, asserts } = fp;
      try {
        const baseOp = await nodeCountSum(op.serial);
        const bases = []; for (const d of asserts) bases.push({ d, n: (await nodeCountSum(d.serial)).n });
        ctx.log('基线', 'pass', `${op.id} ${baseOp.detail}，` + bases.map((x) => `${x.d.id}=${x.n}`).join(' ') + '（+ 按钮平铺=新树/选项卡=新 Tab，node+tab 联合免疫模式差异）');
        const nav = await navAnywhere(op, op.serial, '气泡树', ctx.log);
        ctx.log('① 边栏「气泡树」', nav.ok ? 'pass' : 'warn', nav.ok ? `已点击 (${nav.x},${nav.y})` : (nav.err || '未命中——继续找 +'));
        const plus = await uiClickText(op.serial, '+', { exact: true, waitMs: 1800 });
        if (!plus.ok) { ctx.log('② 顶栏「+」', 'fail', plus.err || '未找到 + 按钮'); return; }
        ctx.log('② 顶栏「+」新建气泡', 'pass', `已点击 (${plus.x},${plus.y})——新建即落盘（不等对话内容）`);
        const localOk = await pollUntil(async () => { const c = await nodeCountSum(op.serial); return c.ok && c.n === baseOp.n + 1; }, 30000);
        const afterOp = await nodeCountSum(op.serial);
        ctx.log('③ 操作端落盘', localOk && afterOp.n === baseOp.n + 1 ? 'pass' : 'fail', `${op.id} ${afterOp.detail}（期望总和 ${baseOp.n + 1}）`);
        if (!(localOk && afterOp.n === baseOp.n + 1)) return;
        for (const b of bases) {
          const ok = await pollUntil(async () => { const c = await nodeCountSum(b.d.serial); return c.ok && c.n === b.n + 1; }, CFG.poll.syncTimeoutMs + 30000); // ★ 增量断言：基线+1
          const c = await nodeCountSum(b.d.serial);
          ctx.log(`④ ${b.d.label} 云端收敛（基线+1）`, ok && c.n === b.n + 1 ? 'pass' : 'fail', `总和 ${b.n}→${c.n}（期望=${b.n + 1}，${c.detail}）`);
        }
      } finally {
        for (const d of asserts) { await forceStopApp(d.serial); ctx.log(`收尾·${d.label} 窗口收起`, 'info', 'aa force-stop（断言已完）'); }
      }
    } },
  // ★ 0.228.0 PENDING 遗留验证项①：删除 del 标记行传播（写通道探针实证过"物理删行不传播→del 标记行"，app 真实 UI 删除→对端收敛从未真机验证）
  // 自包含：先建后删（建树传播→删树传播，两段都断言）；删除目标=任意「空气泡」（新建根无消息时显示，nodeTitle 默认空）
  { id: 'SYNC-FLOW-DELETE', suite: 'syncflow', name: '删除链路·Pad 建后删→PC 收敛（长按→删除气泡→确认；0.228.0 未验项）', semi: true, scope: 'cross',
    run: async (ctx) => {
      const fp = await flowPrep(ctx); if (!fp) return;
      const { op, asserts } = fp;
      try {
        const baseOp = await nodeCountSum(op.serial);
        const bases = []; for (const d of asserts) bases.push({ d, n: (await nodeCountSum(d.serial)).n });
        const delOp0 = await dbCount(op.serial, 'del:');
        ctx.log('基线', 'pass', `${op.id}=${baseOp.detail} del=${delOp0.n}，` + bases.map((x) => `${x.d.id}=${x.n}`).join(' '));
        // ① 建树（同 NODE 路径）
        const nav = await navAnywhere(op, op.serial, '气泡树', ctx.log);
        if (nav.ok) ctx.log('① 边栏「气泡树」', 'pass', `已点击 (${nav.x},${nav.y})`);
        const plus = await uiClickText(op.serial, '+', { exact: true, waitMs: 1800 });
        if (!plus.ok) { ctx.log('② 顶栏「+」建树', 'fail', plus.err || ''); return; }
        const built = await pollUntil(async () => { const c = await nodeCountSum(op.serial); return c.ok && c.n === baseOp.n + 1; }, 30000);
        if (!built) { const c = await nodeCountSum(op.serial); ctx.log('② 建树落盘', 'fail', `${c.detail}（期望 ${baseOp.n + 1}）`); return; }
        ctx.log('② 建树落盘', 'pass', `${op.id} 总和 ${baseOp.n}→${baseOp.n + 1}`);
        // 建树先传播到断言端（删树传播才有意义——建就没传播=建链路问题，如实红）；★ 增量断言=各自基线+1
        for (const b of bases) {
          const ok = await pollUntil(async () => { const c = await nodeCountSum(b.d.serial); return c.ok && c.n === b.n + 1; }, CFG.poll.syncTimeoutMs + 30000);
          if (!ok) { const c = await nodeCountSum(b.d.serial); ctx.log(`③ ${b.d.label} 建树收敛`, 'fail', `总和=${c.n}（期望 ${b.n + 1}）——建链路未达，删除段无法验证`); return; }
          ctx.log(`③ ${b.d.label} 建树收敛`, 'pass', `总和 ${b.n}→${b.n + 1}（基线+1）`);
        }
        // ④ 长按「空气泡」弹菜单（0.147 长按 500ms；新建根 nodeTitle 空→显示「空气泡」）
        const dd = await dumpLayout(op.serial);
        const bubbles = findNodeBoundsAll(dd.text, '空气泡');
        const target = bubbles.length ? bubbles[bubbles.length - 1] : null;
        if (!target) { ctx.log('④ 定位「空气泡」', 'fail', '画布无空气泡（新建根应显示「空气泡」——可能画布有滚动/其他态，盯屏排查）'); return; }
        const lp = await uiLongPress(op.serial, target.x, target.y);
        if (!lp.ok) { ctx.log('④ 长按气泡', 'fail', lp.raw || 'longClick 失败'); return; }
        ctx.log('④ 长按「空气泡」', 'pass', `(${target.x},${target.y})——弹操作菜单（0.147 长按 500ms）`);
        const mi = await uiClickText(op.serial, '删除气泡', { exact: true, waitMs: 2000 });
        if (!mi.ok) { ctx.log('⑤ 菜单「删除气泡」', 'fail', mi.err || ''); return; }
        ctx.log('⑤ 菜单「删除气泡」', 'pass', `已点击 (${mi.x},${mi.y})——弹确认框「删除节点」`);
        const cf = await uiClickText(op.serial, '删除', { exact: true, waitMs: 2200 });
        if (!cf.ok) { ctx.log('⑥ 确认「删除」', 'fail', cf.err || ''); return; }
        ctx.log('⑥ 确认「删除」', 'pass', `已点击 (${cf.x},${cf.y})（secondaryButton 红字，非「取消」）`);
        // ⑦ 操作端删除落盘
        const delOk = await pollUntil(async () => { const c = await nodeCountSum(op.serial); return c.ok && c.n === baseOp.n; }, 30000);
        const afterDel = await nodeCountSum(op.serial);
        const delOp1 = await dbCount(op.serial, 'del:');
        ctx.log('⑦ 操作端删除生效', delOk && afterDel.n === baseOp.n ? 'pass' : 'fail', `${afterDel.detail}（期望回基线 ${baseOp.n}），del 墓碑 ${delOp0.n}→${delOp1.n}`);
        if (!(delOk && afterDel.n === baseOp.n)) return;
        // ⑧ 断言端收敛（★ 0.228.0 遗留项：del 标记行传播——红了=实锤转 app 修复迭代，先测后修）；★ 增量断言=回各自基线
        for (const b of bases) {
          const ok = await pollUntil(async () => { const c = await nodeCountSum(b.d.serial); return c.ok && c.n === b.n; }, CFG.poll.syncTimeoutMs + 30000);
          const c = await nodeCountSum(b.d.serial);
          const bDel = await dbCount(b.d.serial, 'del:');
          ctx.log(`⑧ ★${b.d.label} 删除传播`, ok && c.n === b.n ? 'pass' : 'fail',
            `总和 ${b.n + 1}→${c.n}（期望回基线 ${b.n}，${c.detail}），del=${bDel.ok ? bDel.n : bDel.raw}${ok && c.n === b.n ? '——墓碑行传播收敛（0.228.0 遗留项验证通过）' : '——未收敛=删除传播实锤问题（0.228.0 PENDING 转 app 修复迭代，先测后修）'}`);
        }
      } finally {
        for (const d of asserts) { await forceStopApp(d.serial); ctx.log(`收尾·${d.label} 窗口收起`, 'info', 'aa force-stop（断言已完）'); }
      }
    } },

  // ---------- ★ 0.241.0.4 手机操作端链路（用户实测「手机 APP 与 Pad/PC 不同步」的正向验证——手机建数据→其余端收敛） ----------
  // flowPrep prefer:'phone'——手机为操作端，Pad/PC 全部成为断言端；导航走 navAnywhere（抽屉链）
  { id: 'SYNC-FLOW-WORD-M', suite: 'syncflow', name: '生词链路·手机建词→其余端收敛（★手机操作端：抽屉→单词库→+→新建单词→保存）', semi: true, scope: 'cross',
    run: async (ctx) => {
      const fp = await flowPrep(ctx, { prefer: 'phone' }); if (!fp) return;
      const { op, asserts } = fp;
      const word = 'TFM' + String(Date.now()).slice(-6); // 纯字母数字：inputText/转义零风险
      try {
        const baseOp = await dbCount(op.serial, 'word:');
        const bases = []; for (const d of asserts) bases.push({ d, n: (await dbCount(d.serial, 'word:')).n });
        ctx.log('基线', 'pass', `${op.id} word=${baseOp.n}，` + bases.map((x) => `${x.d.id}=${x.n}`).join(' '));
        const nav = await navAnywhere(op, op.serial, '单词库', ctx.log);
        ctx.log('① 手机抽屉→「单词库」', nav.ok ? 'pass' : 'fail', nav.ok ? `已点击 (${nav.x},${nav.y})（画布左下角抽屉按钮→边栏项）` : (nav.err || '导航失败'));
        if (!nav.ok) return;
        const plus = await uiClickText(op.serial, '+', { exact: true, waitMs: 1500 });
        if (!plus.ok) { ctx.log('② 顶栏「+」', 'fail', plus.err || '未找到 + 按钮'); return; }
        ctx.log('② 顶栏「+」', 'pass', `已点击 (${plus.x},${plus.y})——弹 + 菜单（0.239.0 bindPopup）`);
        const mi = await uiClickText(op.serial, '新建单词', { exact: true, waitMs: 1800 });
        if (!mi.ok) { ctx.log('③ 菜单「新建单词」', 'fail', mi.err || ''); return; }
        ctx.log('③ 菜单「新建单词」', 'pass', `已点击 (${mi.x},${mi.y})——弹「新增单词」编辑器（手机 86% 宽）`);
        await sleep(1000);
        const ed = (await dumpLayout(op.serial));
        const inBox = findNodeHintAll(ed.text, '单词（必填）')[0];
        if (!inBox) { ctx.log('③ 单词输入框定位', 'fail', 'dump 未命中 hint「单词（必填）」（编辑器未弹出或 dump 结构变化）'); return; }
        const it = await uiInputText(op.serial, inBox.x, inBox.y, word);
        ctx.log(`③ 输入单词 ${word}`, it.ok ? 'pass' : 'fail', it.ok ? `已注入 (${inBox.x},${inBox.y})` : (it.raw || 'inputText 失败'));
        if (!it.ok) return;
        // ★ 0.241.0.7 收键盘（同 WORD——手机键盘态 dump 盲区更甚：86% 宽编辑器+键盘双压窗口，Back 收键盘保编辑器）
        await sh(op.serial, 'uitest uiInput keyEvent Back', 15000);
        await sleep(1500);
        ctx.log('④ 收键盘', 'pass', 'keyEvent Back——键盘态 dump 抓不到「保存」（盲区），收起后可达（编辑器不关：拦截在第二层）');
        const sv = await uiClickText(op.serial, '保存', { exact: true, waitMs: 2500 });
        ctx.log('④ 点「保存」', sv.ok ? 'pass' : 'fail', sv.ok ? `已点击 (${sv.x},${sv.y})` : (sv.err || '未找到保存按钮'));
        if (!sv.ok) return;
        const localOk = await pollUntil(async () => { const c = await dbCount(op.serial, 'word:'); return c.ok && c.n === baseOp.n + 1; }, 30000);
        const afterOp = await dbCount(op.serial, 'word:');
        ctx.log('⑤ 手机端落盘', localOk && afterOp.n === baseOp.n + 1 ? 'pass' : 'fail', `${op.id} word ${baseOp.n}→${afterOp.n}（期望 +1）——手机上行链路起点`);
        let all = true;
        for (const b of bases) {
          const s = await settleCountEquals(b.d.serial, 'word:', b.n + 1, CFG.poll.syncTimeoutMs + 30000, b.d.label);
          ctx.log(`⑥ ${b.d.label} 云端收敛（基线+1）`, s.ok ? 'pass' : 'fail', `word ${b.n}→${s.n}（期望=${b.n + 1}）${s.ok ? '——手机上行→云端→对端下行 全链路活（用户「手机不同步」疑云的正向验证）' : '——手机上行传播未达（app 同步问题实锤，先测后修）'}`);
          if (!s.ok) all = false;
        }
        if (all) { const u = await dumpCountText(op.serial, word); ctx.log('⑦ 手机 UI 可见', u.n >= 1 ? 'pass' : 'warn', `dump 命中「${word}」×${u.n}`); }
      } finally {
        for (const d of asserts) { await forceStopApp(d.serial); ctx.log(`收尾·${d.label} 窗口收起`, 'info', 'aa force-stop（断言已完，同步数据已落盘）'); }
      }
    } },
  { id: 'SYNC-FLOW-NODE-M', suite: 'syncflow', name: '气泡链路·手机建气泡→其余端收敛（★手机操作端：画布顶栏 +；node+tab 联合断言）', semi: true, scope: 'cross',
    run: async (ctx) => {
      const fp = await flowPrep(ctx, { prefer: 'phone' }); if (!fp) return;
      const { op, asserts } = fp;
      try {
        const baseOp = await nodeCountSum(op.serial);
        const bases = []; for (const d of asserts) bases.push({ d, n: (await nodeCountSum(d.serial)).n });
        ctx.log('基线', 'pass', `${op.id} ${baseOp.detail}，` + bases.map((x) => `${x.d.id}=${x.n}`).join(' ') + '（+ 按钮平铺=新树/选项卡=新 Tab，node+tab 联合免疫模式差异）');
        const csOk = await ensureCanvas(op.serial, ctx.log);
        if (!csOk) { ctx.log('① 手机进画布', 'fail', '进画布失败——顶栏 + 不可达'); return; }
        const plus = await uiClickText(op.serial, '+', { exact: true, waitMs: 1800 });
        if (!plus.ok) { ctx.log('② 顶栏「+」', 'fail', plus.err || '未找到 + 按钮'); return; }
        ctx.log('② 画布顶栏「+」新建气泡', 'pass', `已点击 (${plus.x},${plus.y})——新建即落盘（不等对话内容）`);
        const localOk = await pollUntil(async () => { const c = await nodeCountSum(op.serial); return c.ok && c.n === baseOp.n + 1; }, 30000);
        const afterOp = await nodeCountSum(op.serial);
        ctx.log('③ 手机端落盘', localOk && afterOp.n === baseOp.n + 1 ? 'pass' : 'fail', `${op.id} ${afterOp.detail}（期望总和 ${baseOp.n + 1}）`);
        if (!(localOk && afterOp.n === baseOp.n + 1)) return;
        for (const b of bases) {
          const ok = await pollUntil(async () => { const c = await nodeCountSum(b.d.serial); return c.ok && c.n === b.n + 1; }, CFG.poll.syncTimeoutMs + 30000);
          const c = await nodeCountSum(b.d.serial);
          ctx.log(`④ ${b.d.label} 云端收敛（基线+1）`, ok && c.n === b.n + 1 ? 'pass' : 'fail', `总和 ${b.n}→${c.n}（期望=${b.n + 1}，${c.detail}）`);
        }
      } finally {
        for (const d of asserts) { await forceStopApp(d.serial); ctx.log(`收尾·${d.label} 窗口收起`, 'info', 'aa force-stop（断言已完）'); }
      }
    } },

  // ---------- ★ 0.229.26 功能④ UI 规范审计（ui-audit 套件：评审定稿混合组织——组件族=断言函数+页面=执行单元） ----------
  // 审计≠修复：违规清单 fail/warn 分级输出（warn=人工裁决豁免/补 token；fail=规范硬违规），修复走 app 独立迭代
  { id: 'UI-CALIBRATE', suite: 'ui-audit', name: '审计自检·dump 通道能力+density 标定+DesignTokens 版本锚定', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      // ① DesignTokens 版本锚定（评审补充建议：新增常量报警不静默扩展）
      const tk = AUDIT.parseDesignTokens();
      const anchor = (CFG.audit && CFG.audit.tokenAnchor) || null;
      if (anchor && anchor.count !== undefined && anchor.count !== tk.count) {
        ctx.log('★DesignTokens 版本锚定', 'fail', `常量数变化 ${anchor.count}→${tk.count}——新增 token 未确认纳入审计（人工裁决：新色是补白名单还是违规？）`);
      } else ctx.log('DesignTokens 版本锚定', anchor ? 'pass' : 'warn', `常量数=${tk.count} hash=${tk.hash}${anchor ? '（与锚定一致）' : '（config.audit.tokenAnchor 未设置——首跑后回填锚定）'}`);
      // ② dump 通道自检 + density 标定
      const cold = await coldStart(serial, 7000);
      ctx.log('冷启动', cold ? 'pass' : 'fail', cold ? 'aa start 成功' : 'aa start 失败');
      // ★ PC 多屏：app 窗口常驻外接屏（0.229.25 实证）——caps.auditDisplay 指定 dump 屏；未指定=默认主屏
      const disp = dev.caps && dev.caps.auditDisplay !== undefined ? dev.caps.auditDisplay : undefined;
      const d = await dumpAuditNodes(serial, disp);
      if (!d.ok) { ctx.log('审计 dump 自检', 'fail', 'dumpLayout -a 失败——本设备审计通道不可用'); return; }
      const fontOk = d.nodes.some((n) => n.fontSize !== undefined && n.fontSize !== '');
      ctx.log('fontSize 通道', fontOk ? 'pass' : 'skip', fontOk ? 'dump -a 输出 fontSize（文字样式断言可用！）' : 'dump -a 不输出 fontSize/fontWeight（0.229.26 spike 实证）——A12 文字样式审计一期不做，留三期 hypium 通道');
      const cal = AUDIT.calibrateDensity(d.nodes);
      if (cal.ok) ctx.log('density 标定', 'pass', `边栏 240vp 锚=${cal.sidebarPx}px → density=${cal.density.toFixed(4)}（尺寸断言全部经此标尺换算）`);
      else ctx.log('density 标定', 'fail', cal.reason + '——后续尺寸断言将跳过');
      ctx.log('★app 节点规模', 'pass', `首屏 ${d.nodes.length} 节点（dump 全文已存证）`);
      artSave('UI-CALIBRATE', `dump-${dev.id}.json`, d.text);
    } },
  { id: 'UI-AUDIT-PAGES', suite: 'ui-audit', name: '七页巡检·A1 背景/A5 边栏/A11 色值白名单/A15 热区+跨页一致性', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, 'UI 巡检（★一期 Pad 专属——PC 窗口导航需 uiInput displayId 支持，二期开）'); return; }
      await coldStart(serial, 7000);
      // ★ 0.243.0.2 修 A5 存量红（R20261015180932AF-T0 实锤）：冷启后协议弹窗蒙层全屏，吃掉 navTo('气泡树')
      //   的边栏点击 → 「气泡树」页 dump 实为关弹窗后的首页 → 首页边栏六项无选中高亮（Index 无路由=设计使然）
      //   → A5 误报 fail。修=巡检前清弹窗（DIALOGS 用例同款前置：协议自动同意+堆叠弹窗逐层关）
      await agreeDialogIfAny(serial, ctx.log);
      await dismissLoginDialogs(serial, ctx.log);
      const pages = [
        { key: '首页', nav: null, bg: '#120B1F' },
        { key: '气泡树', nav: '气泡树', bg: '#160D26' },
        { key: '单词库', nav: '单词库', bg: '#160D26' },
        { key: '知识库', nav: '知识库', bg: '#160D26' },
        { key: '卡片复习', nav: '卡片复习', bg: '#160D26' },
        { key: '统计', nav: '统计', bg: '#160D26' }, // ★ 0.230.0：app 已补 BG_CANVAS（0.196.5 对齐），期望回填
        { key: '账单', nav: '账单', bg: '#160D26' },
      ];
      let density = null, sidebarPx = null;
      const pageSnap = []; // 跨页一致性数据
      let fails = 0, warns = 0;
      const report = (list, tag) => {
        for (const v of list) {
          if (v.level === 'fail') fails++; else warns++;
          ctx.log(`${v.rule}·${v.where}`, v.level, `期望=${v.expect} | 实际=${v.actual}`);
        }
        if (!list.length) artSave('UI-AUDIT-PAGES', `${tag}-clean.json`, { ok: true });
      };
      for (const p of pages) {
        if (p.nav) {
          const nav = await navTo(serial, p.nav, ctx.log);
          if (!nav.ok) { ctx.log(`导航「${p.nav}」`, 'warn', (nav.err || '') + '——本页跳过'); continue; }
        }
        const d = await dumpAuditNodes(serial);
        if (!d.ok) { ctx.log(`${p.key} dump`, 'warn', 'dump 失败——本页跳过'); continue; }
        artSave('UI-AUDIT-PAGES', `dump-${p.key}-${dev.id}.json`, d.text);
        const cal = AUDIT.calibrateDensity(d.nodes);
        if (cal.ok) { density = cal.density; sidebarPx = cal.sidebarPx; }
        const c = { density, sidebarPx };
        const violations = [
          ...AUDIT.auditPageBackground(d.nodes, c, p.key, p.bg),
          ...AUDIT.auditColorWhitelist(d.nodes, c, p.key),
          ...AUDIT.auditHotzone(d.nodes, c, p.key),
          ...(p.key === '首页' ? [] : AUDIT.auditSidebar(d.nodes, c, p.key)), // ★首页无路由映射（Index 不归边栏六项）不断言选中态
        ];
        report(violations, p.key);
        pageSnap.push({ page: p.key, n: d.nodes.length, bgOk: !violations.some((v) => v.rule.startsWith('A1')), sidebarPx: cal.ok ? cal.sidebarPx : null });
        ctx.log(`巡检·${p.key}`, violations.some((v) => v.level === 'fail') ? 'fail' : (violations.length ? 'warn' : 'pass'), `${d.nodes.length} 节点，违规 ${violations.length} 项（dump 已存证）`);
      }
      // 跨页一致性（全局断言——评审 Q4：所有页面巡检完成后比对）
      const sbs = pageSnap.filter((x) => x.sidebarPx);
      if (sbs.length >= 2) {
        const w = new Set(sbs.map((x) => x.sidebarPx));
        if (w.size > 1) { ctx.log('★跨页边栏宽一致', 'fail', [...w].join(' vs ') + 'px——同设备边栏宽度跨页漂移'); fails++; }
        else ctx.log('跨页边栏宽一致', 'pass', `${[...w][0]}px × ${sbs.length} 页`);
      }
      ctx.log('★巡检汇总', fails + warns === 0 ? 'pass' : (fails ? 'fail' : 'warn'), `7 页 ${pageSnap.length} 页成功，fail=${fails} warn=${warns}——warn 项为人工裁决候选（补 token/豁免清单），fail 项为规范硬违规（修复走 app 迭代）`);
    } },
  { id: 'UI-AUDIT-DIALOGS', suite: 'ui-audit', name: '弹窗体系·B1/B2 宽度+B4 等宽+B5 层级色+B9 返回键+B11 键盘+B13 删除确认+A16 左右留白+A17 三角规格+A18 轨道留白+C0 默认档+C1 自定义模型三字段+C2 自定义档如式提示+C3 模型别名+C4 测试连接（0.238.0）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '弹窗审计（UI 断言）'); return; }
      await coldStart(serial, 6000);
      await agreeDialogIfAny(serial, ctx.log);
      await dismissLoginDialogs(serial, ctx.log);
      let density = null;
      const calOnce = async () => {
        if (density) return { density };
        const d = await dumpAuditNodes(serial);
        const cal = AUDIT.calibrateDensity(d.nodes);
        density = cal.ok ? cal.density : null;
        if (!cal.ok) ctx.log('density 标定', 'warn', cal.reason + '——宽度断言跳过');
        return { density };
      };
      const backKey = async (dialogName, goneText) => {
        // ★ 0.230.0.1：编辑器场景双 Back（键盘开着时第一次 Back 收键盘、第二次关弹窗——分层正确行为）
        await sh(serial, 'uitest uiInput keyEvent Back', 15000);
        await sleep(1400);
        await sh(serial, 'uitest uiInput keyEvent Back', 15000);
        await sleep(1600);
        const d = await dumpAuditNodes(serial);
        const gone = !d.nodes.some((n) => (n.text || '').includes(goneText));
        const alive = await bmVersionCode(serial);
        const vs = AUDIT.verdictBackKey(gone, alive.ok);
        for (const v of vs) ctx.log(`B9 返回键·${dialogName}`, v.level, v.actual);
        if (!vs.length) ctx.log(`B9 返回键关「${dialogName}」`, 'pass', '返回键关闭弹窗且 app 存活 ✓（编辑器场景双 Back：先收键盘再关弹窗）');
        return gone;
      };
      // ── ① 词库编辑器弹窗（520 断点 + B4 双按钮 + B11 键盘适配 + B9 返回键）──
      // ★0.229.26 首跑修正：词库 + 也是 bindMenu 菜单（0.208.0）——须先点菜单项「新建单词」（SYNC-FLOW 旧 WORD 用例同病待下轮修）
      let nav = await navTo(serial, '单词库', ctx.log);
      if (nav.ok) {
        const plus = await uiClickText(serial, '+', { exact: true, waitMs: 1500 });
        if (plus.ok) {
          const mi = await uiClickText(serial, '新建单词', { exact: true, waitMs: 1800 });
          if (mi.ok) ctx.log('词库 + 菜单·自动点「新建单词」', 'pass', `已点击 (${mi.x},${mi.y})`);
          else ctx.log('词库 + 菜单「新建单词」', 'warn', mi.err || '');
          await sleep(1200);
          const d = await dumpAuditNodes(serial);
          artSave('UI-AUDIT-DIALOGS', `dump-word-editor-${dev.id}.json`, d.text);
          const c = await calOnce();
          report2(ctx, AUDIT.auditDialogWidth(d.nodes, c, '新增单词编辑器', '新增单词', 520));
          report2(ctx, AUDIT.auditDialogButtons(d.nodes, c, '新增单词编辑器', ['取消', '保存']));
          // ★ B11 键盘适配（评审点名一期做扎实）：聚焦输入框→键盘弹出→保存按钮必须仍在可视区
          const box = AUDIT.collectAppNodes(d.text, CFG.bundle).filter((n) => n.hint && n.hint.includes('单词（必填）'))[0]
            || AUDIT.collectAppNodes(d.text, CFG.bundle).filter((n) => n.text === '新增单词')[0];
          if (box) {
            // ★ 0.243.0.2 修 B11 存量红（R20261015180932AF-T0 实锤）：裸 click 聚焦不保证输入法会话在场
            //   （Pad 无软键盘/物理键盘场景 Back 直达 app → onBackPressed 关弹窗=「无键盘可收」的正常分层，
            //   被误判「分层失效」）。改 uiInputText 注入 1 字符强制拉起输入法会话（0.241.0.7 SYNC-FLOW WORD
            //   实证：inputText 后 Back=只收键盘不关弹窗）；注入字符随弹窗关闭丢弃，零数据污染
            const inj = await uiInputText(serial, box.xc, box.yc, '测');
            await sleep(1600);
            // ★ 0.230.0.1 断言通道修正（沿用）：键盘态 dump 抓不到 app 子树（窗口 RESIZE 后节点数 0=uitest 盲区，
            //   0.230.0 实测实锤）——"树中无保存"≠不可达。改行为验证：收键盘→弹窗须仍在+保存 bounds 可达
            //   （0.230.0 app 侧已加 Scroll+maxHeight 96%：键盘压矮窗口时弹窗收缩在键盘上方区域内）
            await sh(serial, 'uitest uiInput keyEvent Back', 15000); // 收键盘（输入法会话活跃——Back 只收键盘）
            await sleep(1800);
            const dk = await dumpAuditNodes(serial, undefined, true);
            const stillOpen = dk.nodes.some((n) => (n.text || '').includes('新增单词'));
            const svBtn = dk.nodes.filter((n) => n.text === '保存').sort((a, b) => a.w * b.h - b.w * a.h)[0] || dk.nodes.filter((n) => n.text === '保存')[0];
            const rm = (() => { const m = String((JSON.parse(dk.text).attributes || {}).bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/); return m; })();
            const hLimit = rm ? +rm[4] : 2000;
            if (!stillOpen) { ctx.log('★B11 键盘收起后弹窗仍在', 'fail', '收键盘的 Back 把编辑器也关了（分层失效——键盘与弹窗同层被关）'); }
            else if (svBtn) {
              const visible = svBtn.y2 <= hLimit;
              ctx.log('★B11 键盘收起后保存可达', visible ? 'pass' : 'fail', `保存按钮 y2=${svBtn.y2} vs 屏高=${hLimit}${visible ? '——键盘交互后保存行可达（0.230.0 Scroll+maxHeight 适配闭环）' : '——仍出可视区'}`);
            } else ctx.log('★B11 键盘收起后保存可达', 'fail', '收键盘后 dump 树中仍无「保存」节点（弹窗渲染异常）');
          }
          await backKey('新增单词编辑器', '新增单词');
        } else ctx.log('词库 + 触发', 'warn', plus.err || '');
      }
      // ── ② 知识库编辑器弹窗（520 断点抽查 + B9 返回键）──
      nav = await navTo(serial, '知识库', ctx.log);
      if (nav.ok) {
        const plus = await uiClickText(serial, '+', { exact: true, waitMs: 1500 });
        if (plus.ok) {
          const mi = await uiClickText(serial, '新建卡片', { exact: true, waitMs: 1800 });
          if (mi.ok) {
            await sleep(1000);
            const d = await dumpAuditNodes(serial);
            artSave('UI-AUDIT-DIALOGS', `dump-kb-editor-${dev.id}.json`, d.text);
            const c = await calOnce();
            const kbW = AUDIT.auditDialogWidth(d.nodes, c, '新增知识卡编辑器', '新增知识卡', 520);
            for (const v of kbW) v.actual += '（代码 KnowledgeBankPage.ets:1238 有 520 断点——实测超宽=定位容器可能含父层/实际违规，人工复核 dump 证据定性）';
            report2(ctx, kbW);
            report2(ctx, AUDIT.auditDialogButtons(d.nodes, c, '新增知识卡编辑器', ['取消', '保存']));
            await backKey('新增知识卡编辑器', '新增知识卡');
          }
        }
      }
      // ── ③ 气泡删除确认弹窗（AlertDialog 400 断点 + B4 + B5 危险色 + B13 删除必经确认 + 取消关闭不破坏数据）──
      nav = await navTo(serial, '气泡树', ctx.log);
      if (nav.ok) {
        const d0 = await dumpAuditNodes(serial);
        // ★气泡定位：气泡卡片长按是 LongPressGesture（非 longClickable 属性，dump 拿不到）——
        //   改用气泡标题文本定位（新建根显示「空气泡」0.147 规则；取最后一个=text 节点树序最后=最新）
        const bub = [...d0.nodes].reverse().find((n) => (n.text === '空气泡' || /^(新气泡|气泡)/.test(n.text || '')) && n.w > 30 && n.h > 15)
          || d0.nodes.filter((n) => n.text && n.text.includes('条对话') === false && n.type !== 'Button' && n.w > 100 && n.h > 40).slice(-1)[0];
        if (bub) {
          const lp = await sh(serial, `uitest uiInput longClick ${bub.xc} ${bub.yc}`, 15000);
          await sleep(1500);
          const dm = await dumpAuditNodes(serial);
          const del = dm.nodes.filter((n) => n.text === '删除气泡')[0];
          if (del) {
            ctx.log('B13 删除必经确认·长按菜单出现', 'pass', `「删除气泡」菜单项已弹（删除不直达 ✓）`);
            const cd = await uiClickText(serial, '删除气泡', { exact: true, waitMs: 2000 });
            if (cd.ok) {
              await sleep(1000);
              const dd = await dumpAuditNodes(serial);
              artSave('UI-AUDIT-DIALOGS', `dump-del-confirm-${dev.id}.json`, dd.text);
              const hasConfirm = dd.nodes.some((n) => (n.text || '').includes('确认删除'));
              ctx.log('★B13 删除确认弹窗出现', hasConfirm ? 'pass' : 'fail', hasConfirm ? '点删除后弹确认（危险操作有拦截 ✓）' : '未捕获确认弹窗（删除直达=危险操作无拦截）');
              if (hasConfirm) {
                const c = await calOnce();
                report2(ctx, AUDIT.auditDialogWidth(dd.nodes, c, '删除确认 AlertDialog', '确认删除', 400));
                report2(ctx, AUDIT.auditDialogButtons(dd.nodes, c, '删除确认 AlertDialog', ['取消', '删除']));
                report2(ctx, AUDIT.auditDialogButtonColor(dd.nodes, c, '删除确认 AlertDialog', '删除', 'DANGER'));
                // 取消关闭（审计不破坏数据）
                const cancel = await uiClickText(serial, '取消', { exact: true, waitMs: 1800 });
                ctx.log('收尾·点「取消」关闭删除确认', cancel.ok ? 'pass' : 'warn', cancel.ok ? '已取消（不真删——审计零数据破坏）' : '取消按钮定位失败');
              }
            }
          } else ctx.log('长按菜单', 'warn', '长按后未见「删除气泡」菜单（定位目标可能非气泡节点）');
        } else ctx.log('气泡定位', 'warn', '画布未找到可长按气泡节点');
      }
      // ── ④ 设置弹窗（A14 保存行等宽 + 宽度 + B9 返回键 + ★0.233.0 A16/A17/A18/C1 用户四条 UI 反馈）──
      nav = await navTo(serial, '设置', ctx.log);
      if (nav.ok) {
        await sleep(1200);
        const d = await dumpAuditNodes(serial);
        artSave('UI-AUDIT-DIALOGS', `dump-settings-${dev.id}.json`, d.text);
        const c = await calOnce();
        report2(ctx, AUDIT.auditDialogButtons(d.nodes, c, '全局设置弹窗·保存行', ['保存', '返回']));
        report2(ctx, AUDIT.auditDialogButtonColor(d.nodes, c, '全局设置弹窗·保存', '保存', 'BRAND_PRIMARY'));
        // ★ 0.233.0 A16 弹窗左右留白（用户实锤「右边顶格」——弹窗与屏幕左右必须各留空地不贴边）
        const scrM = String((JSON.parse(d.text).attributes || {}).bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
        const screenW = scrM ? +scrM[3] : 0;
        report2(ctx, AUDIT.auditDialogSideMargins(d.nodes, c, '全局设置弹窗', '全局设置', screenW));
        // ★ 0.233.0 A17 TTS 折叠三角规格（大三角 22vp——用户「小三角太小」拍板）
        report2(ctx, AUDIT.auditCollapseTriangle(d.nodes, c, '语音朗读（TTS）'));
        // ★ 0.233.0 A18 Tab 轨道两端留白 12vp（用户拍板「导航栏左右留空地」）
        report2(ctx, AUDIT.auditTabTrackPadding(d.nodes, c, '全局设置弹窗', '全局设置'));
        // ★ 0.237.2 C0/C1/C2 TTS 设置区三 bug 回归（app 0.237.2 配套——§12.11 基线对齐/§12.13 军令）：
        //   C0 音频模型默认档（空值/异档残留默认回「声音复刻 2.0」，不落「自定义模型」）
        //   C1 音频模型=「自定义模型」→ 三字段齐全（模型 ID/音频 API Key/音色 ID）+「如 …」灰提示
        //      （★ 0.237.2 反转 0.233.0 旧断言：音色 ID 从「必须隐藏」改「必须显示」——用户改拍板三字段）
        //   C2 自定义提供商档 → 接口地址空值露「如 https://…」灰提示（0.236.2 前预填真地址占位=bug）
        const ttsRow = d.nodes.find((n) => (n.text || '').includes('语音朗读（TTS）'));
        if (ttsRow) {
          await sh(serial, `uitest uiInput click ${ttsRow.xc} ${ttsRow.yc}`, 15000);
          await sleep(1300);
          // ★ 0.233.0.2：展开表单在弹窗 Scroll 视口下方（dump 只含可视节点，首轮 C1 实锤）——上滑滚到底再 dump
          // ★ 0.233.0.4：滚到底后「音频模型」贴视口底缘，下拉面板向下弹出仍超出可视区（二轮实锤「自定义模型」
          //   定位失败）——再小幅下滑让下拉行居于视口中部，面板向下弹有半屏空间
          const scrH = scrM ? +scrM[4] : 1600;
          await sh(serial, `uitest uiInput swipe ${Math.round(screenW / 2)} ${Math.round(scrH * 0.72)} ${Math.round(screenW / 2)} ${Math.round(scrH * 0.2)} 800`, 15000);
          await sleep(700);
          await sh(serial, `uitest uiInput swipe ${Math.round(screenW / 2)} ${Math.round(scrH * 0.3)} ${Math.round(screenW / 2)} ${Math.round(scrH * 0.55)} 600`, 15000);
          await sleep(900);
          const d2 = await dumpAuditNodes(serial);
          artSave('UI-AUDIT-DIALOGS', `dump-tts-open-${dev.id}.json`, d2.text);
          // ★ C0 默认档断言：期望值从持久化真值推导（prefField 读 persistent_storage 的 audioModel，
          //   XML 实体转义已处理——比裸 grep 稳），与 app 回显逻辑逐字对齐（§12.11）——
          //   seed-tts-2.0→豆包；空/seed-icl-2.0/cosyvoice 残留→声音复刻2.0；其他非空→自定义模型
          const pref = await prefField(serial, 'audioModel');
          let expectModel = '声音复刻 2.0';
          let prefNote = '持久化通道不可读——按默认档「声音复刻 2.0」断言（尽力通道）';
          if (pref.found) {
            const am = pref.value;
            if (am === 'seed-tts-2.0') expectModel = '豆包语音合成 2.0';
            else if (am === '' || am === 'seed-icl-2.0' || am === 'cosyvoice-v3.5-plus') expectModel = '声音复刻 2.0';
            else expectModel = '自定义模型';
            prefNote = `持久化 audioModel=${am === '' ? '（空）' : am}`;
          }
          const modelShown = d2.nodes.find((n) => n.text === expectModel);
          const shownCustom = d2.nodes.some((n) => n.text === '自定义模型');
          if (modelShown) {
            ctx.log('★C0 音频模型默认档', 'pass',
              `下拉显示「${expectModel}」✓（${prefNote}）` + (expectModel === '声音复刻 2.0' && shownCustom ? '（注意：同屏另有「自定义模型」文本，人工复核 dump）' : ''));
          } else {
            ctx.log('★C0 音频模型默认档', 'fail',
              `期望「${expectModel}」（${prefNote}）实际未命中——` + (shownCustom ? '显示「自定义模型」=bug1 复现（空值/残留落自定义未回默认）' : 'dump 未见任何预设名（结构变化复核）'));
          }
          const lbl = d2.nodes.find((n) => n.text === '音频模型');
          const row = lbl ? d2.nodes.filter((n) => n.y >= lbl.y2 && n.y - lbl.y2 < 60 && n.h > 30 && n.h < 70).sort((a, b) => a.y - b.y)[0] : null;
          if (row) {
            await sh(serial, `uitest uiInput click ${row.xc} ${row.yc}`, 15000);
            await sleep(1000);
            // ★ 0.233.0.5：下拉面板向下弹出且「自定义模型」是面板最后一项——Scroll 裁剪致其落在可视区外
            //   （三轮 dump 存证实锤）——展开后再上滑一段把面板尾部滚进视口
            await sh(serial, `uitest uiInput swipe ${Math.round(screenW / 2)} ${Math.round(scrH * 0.7)} ${Math.round(screenW / 2)} ${Math.round(scrH * 0.35)} 600`, 15000);
            await sleep(700);
            const cust = await uiClickText(serial, '自定义模型', { exact: true, waitMs: 1500 });
            if (cust.ok) {
              const d3 = await dumpAuditNodes(serial);
              artSave('UI-AUDIT-DIALOGS', `dump-tts-custom-model-${dev.id}.json`, d3.text);
              // C1a 三字段齐全（0.237.2 用户拍板：模型 ID + 音频 API Key + 音色 ID）
              const hasModelId = d3.nodes.some((n) => n.text === '模型 ID');
              const hasKey = d3.nodes.some((n) => n.text === '音频 API Key');
              const hasVoiceAfter = d3.nodes.some((n) => n.text === '音色 ID');
              const threeOk = hasModelId && hasKey && hasVoiceAfter;
              ctx.log('★C1a 自定义模型·三字段齐全', threeOk ? 'pass' : 'fail',
                `模型 ID=${hasModelId ? '✓' : '缺'} / 音频 API Key=${hasKey ? '✓' : '缺'} / 音色 ID=${hasVoiceAfter ? '✓（0.237.2 恢复显示，推翻 0.233.0 隐藏）' : '缺（仍隐藏=旧版行为）'}`);
              // C1b 三字段「如 …」灰提示（placeholder 在 attributes.hint——dump -a 可读）
              const hints = d3.nodes.filter((n) => n.hint).map((n) => String(n.hint));
              const hintModel = hints.find((h) => h.startsWith('如 seed-tts-2.0'));
              const hintKey = hints.find((h) => h.startsWith('如 d30edab3') || h.startsWith('填入豆包语音'));
              const hintVoice = hints.find((h) => h.startsWith('如 S_'));
              const hintOk = hintModel && hintKey && hintVoice;
              ctx.log('★C1b 自定义模型·如式灰提示', hintOk ? 'pass' : 'fail',
                `模型 ID=${hintModel ? '✓' : '缺'} / Key=${hintKey ? (hintKey.startsWith('如') ? '✓' : '回退文案（内置 Key 快照缺失——config.json 未打包）') : '缺'} / 音色 ID=${hintVoice ? '✓' : '缺'}`);
            } else ctx.log('C1 下拉「自定义模型」', 'warn', (cust.err || '') + '——下拉面板定位失败（结构变化人工复核 dump 存证）');
            // C2 自定义提供商档：接口地址「如 https://…」灰提示（0.237.2 bug4 回归——
            //   旧版切档预填火山真地址占位，placeholder 永不露出）
            await sh(serial, `uitest uiInput swipe ${Math.round(screenW / 2)} ${Math.round(scrH * 0.3)} ${Math.round(screenW / 2)} ${Math.round(scrH * 0.6)} 600`, 15000);
            await sleep(800);
            const segCustom = await uiClickText(serial, '自定义', { exact: true, waitMs: 1500 });
            if (segCustom.ok) {
              const d4 = await dumpAuditNodes(serial);
              artSave('UI-AUDIT-DIALOGS', `dump-tts-custom-provider-${dev.id}.json`, d4.text);
              const hasEpLabel = d4.nodes.some((n) => n.text === '接口地址');
              const epHint = d4.nodes.filter((n) => n.hint).map((n) => String(n.hint)).find((h) => h.startsWith('如 https://'));
              const c2Ep = hasEpLabel && epHint;
              ctx.log('★C2 自定义档·接口地址如式提示', c2Ep ? 'pass' : 'fail',
                `字段=${hasEpLabel ? '✓' : '缺'} / placeholder=${epHint ? '「' + epHint.slice(0, 24) + '…」✓' : '未命中「如 https://」灰提示'}`);
            } else ctx.log('C2 切「自定义」分段', 'warn', (segCustom.err || '') + '——分段行定位失败（可能滚出视口，人工复核 dump 存证）');
          } else ctx.log('C1 音频模型下拉行', 'warn', '未定位到下拉触发行（TTS 未展开或结构变化）');
          // 收尾·还原：不保存关闭（切了模型/档位未保存——backKey 会弹「修改未保存」，先主动点掉防卡）
          const discard = await uiClickText(serial, '不保存关闭', { exact: true, waitMs: 1200 });
          if (discard.ok) ctx.log('C1/C2 收尾·不保存关闭', 'pass', '已还原（切模型/切档未落盘，零数据破坏）');
        } else ctx.log('C0/C1/C2 TTS 折叠行', 'warn', '未见「语音朗读（TTS）」行——跳过 TTS 设置区测试');
        await backKey('全局设置弹窗', '全局设置');
      }
      // ── ④b 设置弹窗·API 表单尾（★ 0.238.0 C3/C4：测试连接+模型别名回归——§12.13 军令）──
      //   独立重开（④ 段 TTS 测试已 backKey 关闭）：滚到 API Tab 表单尾断言 C3 别名字段（标签+灰提示）、
      //   C4 测试连接按钮；C4 真点一次（表单当前值发最小请求 max_tokens 1——0.236.0 试听同哲学；
      //   结果行三态「成功绿/失败红/Key 守卫」任一出现=按钮→请求→结果行全链路通；测试连接不改表单值=收尾无脏态）
      nav = await navTo(serial, '设置', ctx.log);
      if (nav.ok) {
        await sleep(1200);
        const db0 = await dumpAuditNodes(serial);
        const rm2 = String((JSON.parse(db0.text).attributes || {}).bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
        const sw2 = rm2 ? +rm2[3] : 1000;
        const sh2 = rm2 ? +rm2[4] : 1600;
        await sh(serial, `uitest uiInput swipe ${Math.round(sw2 / 2)} ${Math.round(sh2 * 0.68)} ${Math.round(sw2 / 2)} ${Math.round(sh2 * 0.3)} 700`, 15000);
        await sleep(800);
        const dA = await dumpAuditNodes(serial);
        artSave('UI-AUDIT-DIALOGS', `dump-api-tail-${dev.id}.json`, dA.text);
        const hasAliasLbl = dA.nodes.some((n) => n.text === '模型别名');
        const aliasHint = dA.nodes.filter((n) => n.hint).map((n) => String(n.hint)).find((h) => h.includes('给模型起个展示名'));
        ctx.log('★C3 模型别名字段（标签+灰提示）', hasAliasLbl && aliasHint ? 'pass' : 'fail',
          `标签=${hasAliasLbl ? '✓' : '缺'} / placeholder=${aliasHint ? '「' + aliasHint + '」✓（留空显示官方模型名）' : '未命中（未滚到表单尾或字段缺失——对照 dump-api-tail 存证复核）'}`);
        const testBtn = dA.nodes.find((n) => (n.text || '').includes('测试连接'));
        if (testBtn) {
          ctx.log('C4 测试连接按钮在场', 'pass', `已定位 (${testBtn.xc},${testBtn.yc})——presetFormContent 插一次覆盖预设 3 家`);
          await sh(serial, `uitest uiInput click ${testBtn.xc} ${testBtn.yc}`, 15000);
          let resNode = null;
          for (let i = 0; i < 7 && !resNode; i++) {
            await sleep(2500);
            const dr = await dumpAuditNodes(serial);
            resNode = dr.nodes.find((n) => ['连接成功', '连接失败', '连接超时', '请先填写 API Key'].some((k) => (n.text || '').includes(k)));
            if (resNode) artSave('UI-AUDIT-DIALOGS', `dump-conn-result-${dev.id}.json`, dr.text);
          }
          if (resNode) {
            ctx.log('★C4 测试连接·结果行出现', 'pass',
              `「${(resNode.text || '').slice(0, 44)}」——三态（成功绿/失败红/Key 守卫）任一=表单当前值→最小真实请求→结果行全链路通（0.238.0）`);
          } else ctx.log('★C4 测试连接·结果行', 'fail', '17.5s 内未见结果文本（15s 超时+2.5s 缓冲必出结果）——按钮点击无效或请求悬挂');
        } else ctx.log('★C4 测试连接按钮', 'fail', 'API 表单尾未见「测试连接」按钮（0.238.0 新增缺失或未滚到位——对照 dump-api-tail 存证复核）');
        await backKey('全局设置弹窗·API 尾段', '全局设置');
      }
      // ── ⑤ fresh 专属弹窗（协议/门禁/堆叠）非 fresh 态如实 skip（守卫基线对齐铁律 §12.11）──
      const dg = await dumpAuditNodes(serial);
      const agreed = !dg.nodes.some((n) => (n.text || '').includes('同意并继续'));
      if (agreed) ctx.log('B3/B7/B16 协议族弹窗', 'skip', '协议已同意态（非 fresh）——宽度/门禁/首启弹窗链须「全新安装」模式跑（fresh 轮覆盖，如实跳过不虚构断言）');
    } },

  // ---------- ★ 0.240.2 ALIAS-KEEP：配置三件套·保存→重启存活回归（0.240.1 用户实锤 bug：别名/Key/提供商保存后重启丢）----------
  // 根因终案（0.240.2 方案B拍平存储，豆包+华为AI双评审）：PersistenceV2「带 factory 的 connect」对多
  // @Trace 字段类冷启盘值被工厂值回滚（B1）+嵌套 connect 毒害水合（B2）+行为自相矛盾（B3）——换 key
  // 四连败后放弃对象映射，api-config 整体改「单 string 存 JSON」（'api-config-v5'，model-alias-v1 同款
  // 全天唯一 100% 可靠实证模式）。本用例复刻用户真实路径断言三件套重启存活：①别名（map+v5 双通道）
  // ②API Key（v5 JSON+回显）③提供商档位（v5 JSON+回显高亮）。「献祭模型」法零污染：切非当前提供商
  // 档做注入/断言，收尾完整还原提供商+模型+别名+Key（Key 经 providerKeyCache 会话缓存自动还原）。
  // ★ 实测注入语义：inputText=追加（X1+Y2=X1Y2）——断言用 contains；清空=注空格（app 侧 trim 落空串）。
  // ★ 假绿纪律（0.240.1 血泪）：KMARK 用唯一时间戳（防历史残留命中）；断言=盘值生效校验+回显档位双保险。
  { id: 'ALIAS-KEEP', suite: 'ui-audit', name: '配置三件套·保存→重启存活（0.240.2 方案B拍平存储回归——别名+Key+提供商档位）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '配置三件套重启存活（UI 断言专属，PC 无 UI 通道）'); return; }
      const MARK = 'AKT'; // 固定短标记（★实测 inputText=纯追加、keyEvent DEL/Ctrl+A/双击选区全无效——UI 无删除
      // 通道，献祭模型名下标记逐轮累积不可清；固定标记让 contains 断言跨轮恒真，累积+3字符/轮可容忍）
      const KMARK = 'K' + String(Date.now()).slice(-5); // ★ 0.240.2：Key 注入唯一时间戳标记（追加语义累积不可清——唯一防历史残留假绿）
      const PROVIDERS = ['华为云 MaaS', '火山方舟', 'DeepSeek', '自定义配置'];
      // 别名输入框定位（hint 通道；未命中先上滑一段再试——弹窗 Scroll 视口裁剪）
      const aliasBox = async () => {
        let d = await dumpAuditNodes(serial);
        let hit = findNodeHintAll(d.text, '给模型起个展示名')[0];
        if (!hit) {
          const rm = String((JSON.parse(d.text).attributes || {}).bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
          const sw = rm ? +rm[3] : 1000, shh = rm ? +rm[4] : 1600;
          await sh(serial, `uitest uiInput swipe ${Math.round(sw / 2)} ${Math.round(shh * 0.6)} ${Math.round(sw / 2)} ${Math.round(shh * 0.3)} 600`, 15000);
          await sleep(900);
          d = await dumpAuditNodes(serial);
          hit = findNodeHintAll(d.text, '给模型起个展示名')[0];
        }
        return { d, hit };
      };
      const fieldText = (d) => { const n = d.nodes.find((x) => String(x.hint || '').includes('给模型起个展示名')); return { text: String((n && n.text) || '').trim(), node: n }; };
      // ★ 0.240.1.2 状态三读 helper（防漂移假绿）：当前高亮提供商（品牌容器 containment）/当前模型触发器名
      const curProvider = (d) => {
        const sel = d.nodes.find((t) => PROVIDERS.includes(String(t.text)) && d.nodes.some(
          (c) => /7c4dff/i.test(String(c.backgroundColor || '')) && c.x <= t.x && c.x2 >= t.x2 && c.y <= t.y && c.y2 >= t.y2));
        return sel ? String(sel.text) : '';
      };
      const curModelName = (d) => {
        const t = d.nodes.find((n) => n.text === '▼');
        if (!t) return '';
        const mn = d.nodes.filter((n) => n.text && n !== t && n.y < t.y2 && n.y2 > t.y && n.x2 <= t.x).sort((a, b) => b.x2 - a.x2)[0];
        return mn ? String(mn.text) : '';
      };
      await coldStart(serial);
      // ① 开设置（默认 API Tab）+ 记录原状态（提供商/模型触发器名/自定义模型 ID/别名原值——收尾还原用）
      let nav = await navTo(serial, '设置', ctx.log);
      if (!nav.ok) { ctx.log('① 打开设置弹窗', 'fail', '边栏「设置」未命中——' + (nav.err || '')); return; }
      await sleep(1800);
      const d0 = await dumpAuditNodes(serial);
      artSave('ALIAS-KEEP', `dump-open-${dev.id}.json`, d0.text);
      // ★ 0.240.1.1 提供商高亮检测：品牌紫在父容器（文字节点 bg 恒透明 #00000000——dump-open 实锤），
      //   改「品牌色容器的 bounds 包住哪家提供商文字」 containment 检测（遍历四家文字找被品牌容器包裹者）
      const provEntries = d0.nodes.filter((n) => PROVIDERS.includes(String(n.text)));
      const provSel = provEntries.find((t) => d0.nodes.some(
        (c) => /7c4dff/i.test(String(c.backgroundColor || '')) && c.x <= t.x && c.x2 >= t.x2 && c.y <= t.y && c.y2 >= t.y2));
      const origProvider = provSel ? String(provSel.text) : '';
      const tri = d0.nodes.find((n) => n.text === '▼');
      const origModelName = tri ? (d0.nodes.filter((n) => n.text && n !== tri && n.y < tri.y2 && n.y2 > tri.y && n.x2 <= tri.x).sort((a, b) => b.x2 - a.x2)[0] || {}).text : '';
      const customField = d0.nodes.find((n) => String(n.hint || '').includes('填入模型 ID'));
      const origCustomModel = customField ? String(customField.text || '').trim() : '';
      const origV = fieldText(d0);
      if (!origProvider || !tri) { ctx.log('① 记录原状态', 'fail', `提供商高亮卡=${JSON.stringify(origProvider)} / 模型触发器=${tri ? '✓' : '缺'}——结构变化对照 dump-open 存证复核`); return; }
      ctx.log('① 记录原状态', 'pass', `提供商=${origProvider} / 模型=${JSON.stringify(origModelName)}${origCustomModel ? '（自定义 ID ' + origCustomModel + '）' : ''} / 别名原值=${JSON.stringify(origV.text)}`);
      // ② 切献祭提供商（≠当前；预设二选一——自定义档模型 ID 空手填无法断言）+ 记录其原别名
      const sacrifice = origProvider === '华为云 MaaS' ? 'DeepSeek' : '华为云 MaaS';
      const sw1 = await uiClickText(serial, sacrifice, { exact: true, waitMs: 2000 });
      if (!sw1.ok) { ctx.log('② 切献祭提供商', 'fail', `「${sacrifice}」卡片未命中——` + (sw1.err || '')); return; }
      await sleep(1300);
      const d1 = await dumpAuditNodes(serial);
      const sacOld = fieldText(d1).text;
      ctx.log('② 切献祭提供商', 'pass', `已切「${sacrifice}」（默认模型档 ${JSON.stringify(curModelName(d1))}）——该模型原别名=${JSON.stringify(sacOld)}${sacOld ? '（测试后将清空——测试副作用）' : '（空，零污染）'}`);
      // ③ 前防漂移校验（★ 0.240.1.2：首轮实锤 provider 在 ②③ 间漂回原档致「标记记到原模型名下」假绿——
      //    注入前必须确认献祭档在场；献祭默认模型与原模型同名（跨提供商同 ID）时换选下拉另一预设项）
      let a1 = await aliasBox();
      if (!a1.hit) { ctx.log('③ 定位别名输入框', 'fail', 'hint「给模型起个展示名」未命中——对照 dump 存证复核'); return; }
      let guard = curProvider(a1.d) === sacrifice && curModelName(a1.d) !== origModelName;
      if (!guard) {
        ctx.log('③ 防漂移·重切献祭档', 'warn', `校验时 provider=${JSON.stringify(curProvider(a1.d))} / 模型=${JSON.stringify(curModelName(a1.d))}（期望 ${sacrifice} 且 ≠${JSON.stringify(origModelName)}）——重新点击后重试`);
        const sw2 = await uiClickText(serial, sacrifice, { exact: true, waitMs: 2000 });
        await sleep(1400);
        a1 = await aliasBox();
        guard = sw2.ok && a1.hit && curProvider(a1.d) === sacrifice;
        if (guard && curModelName(a1.d) === origModelName) {
          // 献祭默认模型与原模型同名（跨提供商同 ID）——下拉换选一个不同的预设模型项
          const t2 = a1.d.nodes.find((n) => n.text === '▼');
          if (t2) {
            await sh(serial, `uitest uiInput click ${Math.round(t2.xc)} ${Math.round(t2.yc)}`, 15000);
            await sleep(1100);
            const dd = await dumpAuditNodes(serial);
            const items = dd.nodes.filter((n) => n.text && n.y > t2.y2 && String(n.text) !== '自定义…'
              && String(n.text) !== origModelName && !String(n.text).includes('填入列表外')
              && !String(n.text).includes('强烈推荐') && !String(n.text).includes('可发图'));
            const pick = items.length ? await uiClickText(serial, String(items[0].text), { exact: true, waitMs: 2000 }) : { ok: false };
            guard = pick.ok;
            await sleep(700);
          }
        }
        if (!guard) {
          const dchk = await dumpAuditNodes(serial);
          ctx.log('③ 防漂移校验', 'fail', `献祭档未能稳定在场（provider=${JSON.stringify(curProvider(dchk))} / 模型=${JSON.stringify(curModelName(dchk))}）——环境不稳定，本条中止防污染用户配置`);
          return;
        }
      }
      // 注入唯一标记 + ★ 0.240.2 Key 框注入 KMARK（献祭档 placeholder 定位；表单上部不在视口则下滑露出）
      //   + 收键盘（IME 候选条遮挡保存按钮）+ 保存（按钮随滚动位移——dump 实时定位）
      await uiInputText(serial, a1.hit.x, a1.hit.y, MARK);
      await sleep(800);
      const keyHint = sacrifice === '华为云 MaaS' ? '填入华为云 MaaS API Key' : '填入 DeepSeek API Key';
      const keyBox = async () => {
        let d = await dumpAuditNodes(serial);
        let hit = findNodeHintAll(d.text, keyHint)[0];
        if (!hit) {
          const rm = String((JSON.parse(d.text).attributes || {}).bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
          const sw = rm ? +rm[3] : 1000, shh = rm ? +rm[4] : 1600;
          await sh(serial, `uitest uiInput swipe ${Math.round(sw / 2)} ${Math.round(shh * 0.35)} ${Math.round(sw / 2)} ${Math.round(shh * 0.65)} 600`, 15000);
          await sleep(900);
          d = await dumpAuditNodes(serial);
          hit = findNodeHintAll(d.text, keyHint)[0];
        }
        return { d, hit };
      };
      const kb = await keyBox();
      let keyNote = '';
      if (kb.hit) {
        await uiInputText(serial, kb.hit.x, kb.hit.y, KMARK);
        await sleep(800);
        keyNote = ` / Key 框已注「${KMARK}」`;
      } else {
        keyNote = ' / ⚠️ Key 框未命中（KMARK 未注入——⑤ Key 断言将如实红）';
      }
      await sh(serial, `uitest uiInput keyEvent Back`, 15000);
      await sleep(1000);
      // ★ 0.243.0.2 修 ③ 存量红（R20261015180932AF-T0 实锤「保存未命中+provider/模型读空」）：Key 框下滑后
      //   视口停在中段——保存按钮（表单底部）与提供商卡（顶部）同时滚出 dump 视口 → 定位必空。修=保存按钮
      //   双向滚动重试：原位找不到→下滑找（保存近底部）→上滑回顶找；每步 dump 实时重定位（表单节点随滚动位移）
      const svFind = async () => {
        let d = await dumpAuditNodes(serial);
        let n = d.nodes.find((x) => x.text === '保存');
        if (n) return { ok: true, x: n.xc, y: n.yc, ctx: d };
        const rm = String((JSON.parse(d.text).attributes || {}).bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
        const sw = rm ? +rm[3] : 1000, shh = rm ? +rm[4] : 1600;
        await sh(serial, `uitest uiInput swipe ${Math.round(sw / 2)} ${Math.round(shh * 0.55)} ${Math.round(sw / 2)} ${Math.round(shh * 0.3)} 600`, 15000);
        await sleep(900);
        d = await dumpAuditNodes(serial);
        n = d.nodes.find((x) => x.text === '保存');
        if (n) return { ok: true, x: n.xc, y: n.yc, ctx: d };
        await sh(serial, `uitest uiInput swipe ${Math.round(sw / 2)} ${Math.round(shh * 0.35)} ${Math.round(sw / 2)} ${Math.round(shh * 0.7)} 600`, 15000);
        await sleep(900);
        d = await dumpAuditNodes(serial);
        n = d.nodes.find((x) => x.text === '保存');
        return n ? { ok: true, x: n.xc, y: n.yc, ctx: d } : { ok: false, ctx: d };
      };
      const svHit = await svFind();
      const sv = svHit.ok ? await (async () => { const r = await sh(serial, `uitest uiInput click ${svHit.x} ${svHit.y}`, 15000); await sleep(600); return { ok: !SH_ERR_RE.test(r), x: svHit.x, y: svHit.y }; })() : { ok: false };
      const preSave = svHit.ctx;
      const saveCtx = `provider=${JSON.stringify(curProvider(preSave))} / 模型=${JSON.stringify(curModelName(preSave))}`;
      ctx.log('③ 注入标记并保存', sv.ok ? 'pass' : 'fail', sv.ok ? `已输入「${MARK}」${keyNote}（追加语义）→点「保存」(${sv.x},${sv.y})·保存时表单=${saveCtx}` : `「保存」按钮未命中（键盘未收/滚动位移——人工复核）·表单=${saveCtx}`);
      if (!sv.ok) return;
      await sleep(1800);
      // ④ 写通道断言：v5 落盘三校验（★ 0.240.2 方案B——api-config-v5 单string JSON 为唯一主真相源：
      //   provider=献祭档 + apiKey 含本轮唯一 KMARK + modelAlias 含标记；防「保存点击落空+残留子串」
      //   双假绿，未生效重试保存≤3 次。拉盘本地 node 解析——三层转义膨胀后 BusyBox grep 240 窗口
      //   到不了 provider（首跑实锤），file recv 全量解析一次拿全字段）
      const SAC_ID = sacrifice === '华为云 MaaS' ? 'huawei' : 'deepseek';
      const v5OnDisk = async () => {
        const r = await pullPrefCfg(serial, 'api-config-v5');
        if (!r.ok) return { ok: false, why: r.err || '解析失败' };
        const c = r.cfg || {};
        return {
          ok: String(c.provider || '') === SAC_ID && String(c.apiKey || '').includes(KMARK),
          provider: String(c.provider || ''), apiKeyHas: String(c.apiKey || '').includes(KMARK),
          aliasHas: String(c.modelAlias || '').includes(MARK), model: String(c.model || '')
        };
      };
      let v5Saved = await v5OnDisk();
      for (let t = 0; t < 3 && !v5Saved.ok; t++) {
        ctx.log('④ 保存生效校验·重试', 'warn', `盘上 v5=${JSON.stringify(v5Saved)}（期望 provider=${SAC_ID}+Key含「${KMARK}」）——保存点击疑似落空，重点「保存」第 ${t + 1} 次`);
        const retryFind = await svFind();
        if (retryFind.ok) { await sh(serial, `uitest uiInput click ${retryFind.x} ${retryFind.y}`, 15000); await sleep(600); }
        await sleep(2200);
        const again = await v5OnDisk();
        v5Saved = again.ok ? again : (retryFind.ok ? again : v5Saved);
      }
      ctx.log('④ 保存生效校验（v5 主真相源·全字段）', v5Saved.ok ? 'pass' : 'fail',
        v5Saved.ok ? `盘上 api-config-v5：provider=${SAC_ID} + apiKey 含本轮唯一「${KMARK}」${v5Saved.aliasHas ? ' + modelAlias 含「' + MARK + '」' : ''}（方案B 单string JSON 真实落盘——防「点击落空+残留巧合」双假绿）` : `3 次保存后 v5=${JSON.stringify(v5Saved)}——保存链路异常（点击落空或 saveAll 未写 v5），本条中止防污染`);
      if (!v5Saved.ok) return;
      let diskHit = false, diskNote = '';
      for (const p of PREF_CANDIDATES) {
        const full = `${CFG.sandboxBase}/${p}`;
        const c1 = await sh(serial, `grep -c '${MARK}' '${full}' 2>/dev/null`, 15000);
        if (c1.trim() !== '' && Number(c1.trim()) > 0) diskHit = true;
        if (c1.trim() !== '') diskNote += `${p.split('/').slice(-2).join('/')}:mark=${c1.trim()}; `;
      }
      ctx.log('④ 写通道·别名 map 落盘含标记', diskHit ? 'pass' : 'fail', diskHit ? `persistent_storage 命中「${MARK}」×≥1（别名持久化真相=map，onChange 实时落盘）` : `全候选路径未命中标记（map 写通道坏=新 bug）——${diskNote || '通道不可读'}`);
      // ⑤ 核心：force-stop 冷启 → 重开设置 → 三件套必须全存活（用户所见=读通道；0.240.2 前此处必红）
      //   ★ 0.240.2 三重校验：别名框含标记 + 回显 provider=献祭档（防「标记追加进原模型名下」漂移假绿）
      //   + Key 框含本轮唯一 KMARK（用户报障症状②「Key 保存→重启变空」的直接断言）
      await coldStart(serial);
      nav = await navTo(serial, '设置', ctx.log);
      if (!nav.ok) { ctx.log('⑤ 重启后打开设置', 'fail', '「设置」未命中——' + (nav.err || '')); return; }
      await sleep(1800);
      const a2 = await aliasBox();
      artSave('ALIAS-KEEP', `dump-restart-${dev.id}.json`, a2.d.text);
      if (!a2.hit) { ctx.log('★⑤ 重启后配置存活', 'fail', '别名输入框未命中（结构变化对照 dump-restart 存证）'); return; }
      const now = fieldText(a2.d).text;
      const provNow = curProvider(a2.d);
      let keyNode = a2.d.nodes.find((x) => String(x.hint || '').includes('API Key'));
      if (!keyNode) {
        // 别名框在上部滚动后 Key 框被滚出视口——回滚顶部重找（keyBox 含下滑重试逻辑）
        const kb2 = await keyBox();
        keyNode = kb2.hit ? { text: String((kb2.d.nodes.find((x) => String(x.hint || '').includes('API Key')) || {}).text || '') } : null;
      }
      const keyNow = keyNode ? String(keyNode.text || '') : '';
      const aliasOk = now.includes(MARK);
      const provOk = provNow === sacrifice;
      const keyOk = keyNode ? keyNow.includes(KMARK) : false;
      const alive = aliasOk && provOk && keyOk;
      ctx.log('★⑤ 重启后配置存活（别名+档位+Key 三重）', alive ? 'pass' : 'fail',
        alive ? `别名框=「${now.slice(0, 30)}」含「${MARK}」+ 回显「${sacrifice}」档 + Key 框含本轮唯一「${KMARK}」——保存→重启→回显全链路通（0.240.2 方案B拍平存储生效；修前实测=回滚/恒空）`
          : `别名=${aliasOk ? '✓' : '✗(' + JSON.stringify(now.slice(0, 30)) + ')'} / 档位=${provOk ? '✓' : '✗(' + JSON.stringify(provNow) + ')'} / Key=${keyOk ? '✓' : keyNode ? '✗(' + JSON.stringify(keyNow.slice(0, 20)) + ')' : '✗框未命中'}——${aliasOk ? 'Key/档位重启丢失（0.240.1 前实测形态：保存→重启回滚/变空）' : '别名重启丢失 bug 复现'}`);
      // ★ 0.240.2 取证探针：⑤ 失败时立即 force-stop 拉盘存 v5 快照——定性「冷启覆写盘」（v5≠④保存值）
      //   还是「读侧读旧值」（v5=④保存值但表单回显旧值）。修绿后此步静默保留（artifacts 常规存证）。
      if (!alive) {
        await sh(serial, 'aa force-stop com.dagaichat.app', 15000);
        await sleep(1200);
        const probe = await pullPrefCfg(serial, 'api-config-v5');
        const probeStr = probe.ok ? JSON.stringify(probe.cfg) : String(probe.err);
        artSave('ALIAS-KEEP', `v5-probe-restart-${dev.id}.json`, probeStr);
        ctx.log('⑤·取证 v5 盘值（回显后 force-stop 拉盘）', 'info',
          `v5=${probeStr.slice(0, 220)} —— 对比④保存值（provider=${SAC_ID}+K${KMARK}）：盘≠保存值=冷启期间被覆写（写回/迁移落盘嫌疑）；盘=保存值=纯读侧问题（水合/回显读了旧源）`);
      }
      // ⑥ 收尾还原：切回原提供商→重选原模型（含自定义 ID 回填）→保存→关弹窗
      //   ★ 0.240.1.2 实测放弃「清空献祭别名」：inputText 纯追加、keyEvent DEL/Ctrl+A/双击选区全无效
      //   （TextInput 编辑不吃注入——0.200.0「真 Button 不吃注入」同族）——献祭模型名下残留 'AKT' 标记
      //   （固定短标记，纯测试副作用、仅切到该模型时表单可见；原模型别名全程未被触碰）
      ctx.log('⑥ 献祭模型残留声明', 'info', `「${sacrifice}」当前模型名下残留测试标记「AKT」（UI 无删除通道不可自动清——用户长按手动删或无视）；Key 标记「${KMARK}」仅存于测试轮 v5 快照、收尾保存即被原档覆盖（零残留）；原模型「${origModelName}」别名与原档 Key 未被本用例触碰`);
      const back = await uiClickText(serial, origProvider, { exact: true, waitMs: 2000 });
      if (back.ok) {
        await sleep(1300);
        let modelOk = false;
        if (origModelName && origModelName !== '自定义…') {
          const trig = (await dumpAuditNodes(serial)).nodes.find((n) => n.text === '▼');
          if (trig) {
            await sh(serial, `uitest uiInput click ${Math.round(trig.xc)} ${Math.round(trig.yc)}`, 15000);
            await sleep(1100);
            const pick = await uiClickText(serial, origModelName, { exact: true, waitMs: 2000 });
            modelOk = pick.ok;
            await sleep(700);
          }
          if (modelOk) await sleep(700);
        } else if (origModelName === '自定义…' && origCustomModel) {
          const trig = (await dumpAuditNodes(serial)).nodes.find((n) => n.text === '▼');
          if (trig) {
            await sh(serial, `uitest uiInput click ${Math.round(trig.xc)} ${Math.round(trig.yc)}`, 15000);
            await sleep(1100);
            const pick = await uiClickText(serial, '自定义…', { exact: true, waitMs: 2000 });
            if (pick.ok) {
              await sleep(900);
              const cid = findNodeHintAll((await dumpAuditNodes(serial)).text, '填入模型 ID')[0];
              if (cid) { await uiInputText(serial, cid.x, cid.y, origCustomModel); await sleep(700); modelOk = true; }
            }
          }
        } else modelOk = true; // 无模型名记录（兜底：默认档即原档）
        const sv3 = await uiClickText(serial, '保存', { exact: true, waitMs: 2500 });
        await sleep(1400);
        // ★ 0.240.1.2 还原结果改实测回读（旧版打的是 ① 记录的 origV 变量=文案自说自话）
        const dEnd = await dumpAuditNodes(serial);
        const endV = fieldText(dEnd).text;
        const endOk = sv3.ok && modelOk && endV === origV.text;
        ctx.log('⑥ 还原提供商+模型', endOk ? 'pass' : 'warn',
          `已切回「${origProvider}」` + (origModelName ? ` + 重选「${origModelName}」` : '') + ` + 保存——别名实测=${JSON.stringify(endV)}（原值=${JSON.stringify(origV.text)}）` + (endOk ? '✓' : ' ✗不一致（人工核对设置）'));
      } else ctx.log('⑥ 还原提供商', 'warn', `「${origProvider}」卡片未命中——人工核对设置（当前停在 ${sacrifice}）`);
      await sh(serial, `uitest uiInput keyEvent Back`, 15000);
      await sleep(1200);
      const dirty = await uiClickText(serial, '不保存关闭', { exact: true, waitMs: 1500 });
      if (dirty.ok) ctx.log('⑥ 收尾·关弹窗', 'info', '检测到未保存提示已点「不保存关闭」（正常应已保存=清洁态，此为兜底）');
    } },

  // ---------- 功能④ 对话稳定性（★ 0.232.0 bug 回归：切后台开别的 APP 再回来对话清零修复） ----------
  // 复刻用户真实路径：画布双击气泡进对话 → 起浏览器（=打开另一个 APP）→ aa start 热回 → 对话必须原样保留。
  // 修复前实锤链路：onForeground forceCloudSyncNow → reconcile 重建工作区 → refreshWorkspaceFromPools
  // 无条件清 current.nodeID → ChatPage 消息绑定变空（0.232.0 保留仍存在的选中=根治）。
  { id: 'CHAT-KEEP', suite: 'chat', name: '对话保留·压后台开别的APP再回来消息不丢（0.232.0 修复回归）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '对话保留（UI 断言专属，PC 无 UI 通道）'); return; }
      await coldStart(serial);
      ctx.log('前置状态', 'info', '已装机真实数据态——须存在一个「有 AI 回复」的气泡（画布气泡卡带「N条对话」标记）');
      // ⓪ 先进画布（★ 0.232.1 修：冷启停在首页——大屏点边栏「气泡树」/手机点「进入气泡树」主按钮）
      // ★ 0.233.0.7：冷启=拉回前台（非真冷启）——上轮结束若留在对话页则无边栏，两入口全空 →
      //   先 Back 键清场（对话页退回画布）再重试定位
      let nav = await uiClickText(serial, '气泡树', { waitMs: 2200 });
      if (!nav.ok) {
        nav = await uiClickText(serial, '进入气泡树', { waitMs: 2600 });
      }
      if (!nav.ok) {
        await sh(serial, `uitest uiInput keyEvent Back`, 15000);
        await sleep(1500);
        nav = await uiClickText(serial, '气泡树', { waitMs: 2200 });
      }
      ctx.log('⓪ 进入气泡树画布', nav.ok ? 'pass' : 'fail',
        nav.ok ? `已点击 (${nav.x},${nav.y})——冷启首页→画布（找对话气泡的前提）` : '「气泡树」与「进入气泡树」均未命中（可能已在画布或首页改版）');
      // ① 定位有对话的气泡（★ 0.235.0.1：排除画布信息条「N 个气泡 · N 条对话」——树序在气泡卡之后，
      //   取最后命中会双击信息条=点空；只留气泡卡「N 条对话 · X前」）
      const d = await dumpLayout(serial);
      const hits = findNodeBoundsAll(d.text, '条对话').filter((h) => !String(h.text).includes('个气泡'));
      if (!hits.length) { ctx.log('① 定位有对话的气泡', 'fail', '画布未见「N条对话」气泡卡（信息条已排除）——先在某气泡发一条消息再跑本用例'); return; }
      const target = hits[hits.length - 1];
      ctx.log('① 定位有对话的气泡', 'pass', `(${target.x},${target.y})「${String(target.text).slice(0, 24)}」`);
      // ② 双击进对话页（0.173 双击语义）
      await uiDoubleClick(serial, target.x, target.y);
      const dc = await ctx.art.dump(`CHAT-KEEP-${dev.id}`, 'dump-chat.json', serial);
      // ★ 0.233.0.2 判定修正：0.195.0 喇叭 emoji 已换单色 svg（dump 无 🔊/🔈）——补对话页标题特征：
      //   对话页顶栏副标题=「N 条对话」（无时间后缀）；画布气泡卡=「N 条对话 · X天前」（带 ·）
      const speak0 = (dc.text.match(/🔊|🔈/g) || []).length;
      const enterOk = speak0 >= 1 || /"text":\s*"\d+ 条对话"/.test(dc.text) || dc.text.includes('暂无对话');
      ctx.log('② 双击进入对话页', enterOk ? 'pass' : 'fail',
        enterOk ? (speak0 >= 1 ? `AI 消息喇叭标记×${speak0}（对话内容在屏）` : '对话页标题特征命中（双击进页 ✓，svg 时代判定）')
          : '双击后仍在画布（双击未生效——目标气泡定位或双击模拟失效）');
      if (!enterOk) return;
      // ③ 压后台：起系统设置（复刻「打开另一个APP」；华为冻结即时生效）
      // ★ 0.233.0.4：去掉悬空 -U（aa start -U 须配 URL 值）；★ 0.233.0.5：Pad 实锤无 com.huawei.hmos.browser
      //   （10103101 Failed to find a matching application）——压后台载体改必装的系统设置 app
      const bg = await sh(serial, `uitest uiInput keyEvent Home`, 15000);
      ctx.log('③ Home 键回桌面压后台', /error:|fail/i.test(bg) ? 'warn' : 'pass', bg.trim().slice(0, 100) || 'aa start 已发（复刻用户开别的 APP）');
      await sleep(5000);
      // ④ 热回（aa start 已有实例拉回前台——非冷启，等同用户滑回来）
      await sh(serial, `aa start -a ${CFG.ability} -b ${CFG.bundle}`, 15000);
      await sleep(4500);
      // ⑤ 断言：仍在对话页且消息保留（0.232.0 修复点——云同步重建工作区不再清空 current）
      // ★ 0.233.0.2：判定同②修正（svg 时代）——对话页特征仍在=保留
      const dw = await ctx.art.dump(`CHAT-KEEP-${dev.id}`, 'dump-warm.json', serial);
      const speak1 = (dw.text.match(/🔊|🔈/g) || []).length;
      const inChat1 = speak1 >= speak0 || /"text":\s*"\d+ 条对话"/.test(dw.text) || dw.text.includes('暂无对话');
      ctx.log('★热回后对话保留', inChat1 ? 'pass' : 'fail',
        inChat1 ? `对话页特征保留（喇叭 ${speak0}→${speak1}）——消息原样（0.232.0 修复生效）`
          : '热回后不在对话页——对话被清零/丢失（0.232.0 前旧病：refreshWorkspaceFromPools 清空 current.nodeID 复发）');
      const h = await hilogErrors(serial);
      ctx.log('链路 hilog 无错误', h.ok ? (h.n === 0 ? 'pass' : 'warn') : 'warn', h.ok ? `ERROR 计数=${h.n}` : 'hilog 读取异常');
    } },

  // ---------- ★ 0.235.0 划词高亮清除回归（手机实测 bug：点空白高亮/工具栏滞留、两段同时高亮；Pad 保不回归） ----------
  // dump 抓不到系统选中高亮属性（0.229.26 spike：26 属性键无 selection）——以自研悬浮工具栏
  // 「入知识库」文案作为选中激活的可观测代理：长按出现 → 点空白必须消失（滞留=清除链失效）
  { id: 'SEL-CLEAR', suite: 'chat', name: '划词清除·长按选词→点空白，工具栏/选中必须消失（0.235.0 修复回归）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '划词清除（UI 断言专属，PC 无 UI 通道）'); return; }
      await coldStart(serial);
      if (!(await navIntoChat(ctx, serial))) return;
      // ③ 长按消息正文进入划词态（悬浮工具栏弹出）
      const nodes = await dumpAuditNodes(serial);
      const body = pickBodyTextNode(nodes.nodes);
      if (!body) { ctx.log('③ 定位消息正文', 'fail', '未见≥12字正文节点（消息过短或结构变化——先让 AI 回复一段长文本再跑）'); return; }
      ctx.log('③ 定位消息正文', 'pass', `(${Math.round(body.xc)},${Math.round(body.yc)})「${String(body.text).slice(0, 20)}…」共 ${String(body.text).length} 字`);
      await uiLongPress(serial, Math.round(body.xc), Math.round(body.yc), 1800);
      const ds = await ctx.art.dump(`SEL-CLEAR-${dev.id}`, 'dump-sel.json', serial);
      const toolbarOn = ds.text.includes('入知识库');
      ctx.log('④ 长按后悬浮工具栏弹出', toolbarOn ? 'pass' : 'fail',
        toolbarOn ? '「翻译/入知识库/引用/复制/删除」在屏——划词选中已激活' : '未见工具栏（长按未触发选择或正文定位偏移）');
      if (!toolbarOn) return;
      // ⑤ 点空白：顶栏标题「气泡」=无自身 onClick 的空白落点（点击落到根容器兜底 onClick → 清理链）
      const blank = await uiClickText(serial, '气泡', { exact: true, waitMs: 1200 });
      ctx.log('⑤ 点顶栏空白（标题区）', blank.ok ? 'pass' : 'warn', blank.ok ? `已点击 (${blank.x},${blank.y})` : (blank.err || '未定位到标题——点空白未执行，看最终断言'));
      const de = await ctx.art.dump(`SEL-CLEAR-${dev.id}`, 'dump-cleared.json', serial);
      const toolbarGone = !de.text.includes('入知识库') && !de.text.includes('引用到本聊天');
      ctx.log('★点空白后工具栏/选中清除', toolbarGone ? 'pass' : 'fail',
        toolbarGone ? '悬浮工具栏已消失——选中态被清理（0.235.0 修法 A/B/C 生效，无滞留）'
          : '工具栏仍滞留——清除链失效（0.235.0 前「点空白无效」同族；手机复现路径的 Pad 回归红线）');
    } },

  // ---------- ★ 0.235.0 划词引用新功能（工具栏「引用」→ 二选一 → 引用栏 → × 撤销；零数据破坏路径） ----------
  // 覆盖验收 Q1~Q4/Q8/Q9（引用按钮/二选一弹窗/引用栏出现/× 取消/纯提示不跳转/复习区与放大弹窗不显示）；
  // Q5/Q6/Q7（新子气泡/发送注入/发送后清空）涉真实建气泡+消耗 AI 请求，归 Pad 人工验收（docs §五）
  { id: 'CHAT-QUOTE', suite: 'chat', name: '划词引用·工具栏「引用」→二选一→引用栏→×撤销（0.235.0 新功能）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '划词引用（UI 断言专属，PC 无 UI 通道）'); return; }
      await coldStart(serial);
      if (!(await navIntoChat(ctx, serial))) return;
      // ① 长按正文 → 工具栏须含「引用」（Q1；入知识库右侧）
      const nodes = await dumpAuditNodes(serial);
      const body = pickBodyTextNode(nodes.nodes);
      if (!body) { ctx.log('① 定位消息正文', 'fail', '未见≥12字正文节点（消息过短或结构变化）'); return; }
      await uiLongPress(serial, Math.round(body.xc), Math.round(body.yc), 1800);
      const d1 = await ctx.art.dump(`CHAT-QUOTE-${dev.id}`, 'dump-toolbar.json', serial);
      const hasQuote = d1.text.includes('引用') && d1.text.includes('入知识库');
      ctx.log('★① 工具栏含「引用」', hasQuote ? 'pass' : 'fail',
        hasQuote ? '「引用」与「翻译/入知识库」同栏在屏（入知识库右侧，Q1 ✓）' : '工具栏未见「引用」（按钮未渲染或工具栏未弹出）');
      if (!hasQuote) return;
      // ② 点「引用」→ 二选一弹窗（Q2）
      const q = await uiClickText(serial, '引用', { exact: true, waitMs: 1200 });
      const d2 = await ctx.art.dump(`CHAT-QUOTE-${dev.id}`, 'dump-picker.json', serial);
      const pickerOk = d2.text.includes('引用到本聊天') && d2.text.includes('引用为新子气泡');
      ctx.log('★② 点「引用」弹二选一', pickerOk ? 'pass' : 'fail',
        pickerOk ? `已点击 (${q.x},${q.y})——「引用到本聊天/引用为新子气泡」在屏（Q2 ✓）` : '二选一弹窗未出现（引用按钮点击未生效）');
      if (!pickerOk) return;
      // ③ 选「引用到本聊天」→ 输入框上方引用栏出现（Q3）
      const c1 = await uiClickText(serial, '引用到本聊天', { exact: true, waitMs: 1200 });
      const d3 = await ctx.art.dump(`CHAT-QUOTE-${dev.id}`, 'dump-quotebar.json', serial);
      const barOk = d3.text.includes('引用：');
      ctx.log('★③ 引用栏出现（输入框上方）', barOk ? 'pass' : 'fail',
        barOk ? `已点击 (${c1.x},${c1.y})——「引用：前5字…」小栏在屏（Q3 ✓）` : '引用栏未出现（quoteText 未生效）');
      if (!barOk) return;
      // ④ 点引用栏右端 × 撤销 → 引用栏消失（Q4；引用栏 Text 因 layoutWeight 拉伸满行、右缘紧贴 × 图标，
      //    bounds 右缘 +36px = 24vp × 图标中心——精确矩形定位，弃首轮 +120px 近似）
      const bar = findTextRect(d3.text, '引用：');
      if (!bar) { ctx.log('④ × 撤销引用', 'warn', '引用栏 bounds 解析失败'); return; }
      await sh(serial, `uitest uiInput click ${bar.x2 + 36} ${bar.y}`, 15000);
      await sleep(1200);
      const d4 = await ctx.art.dump(`CHAT-QUOTE-${dev.id}`, 'dump-cancelled.json', serial);
      const gone = !d4.text.includes('引用：');
      ctx.log('★④ × 撤销引用栏消失', gone ? 'pass' : 'fail',
        gone ? `已点 (${bar.x2 + 36},${bar.y})——引用栏已清（Q4 ✓，一次性会话态可重引）` : `引用栏仍在（× 未命中——点(${bar.x2 + 36},${bar.y})，dump 存证人工复核）`);
    } },

  // ---------- ★ 0.237.1 划词取词准确性回归（用户实锤：划词没对准划选的词、反而取到前面几个词） ----------
  // 根因：MdBlockText 取词基准=blockPlainText（原始行含 **/~~/[链](url) 标记、无列表前缀），而选区偏移按
  //   渲染 Span 序列计（剥标记+前缀 '• '/'1. '）→ 凡消息带行内标记，取词整体前移。修复=blockRenderedText。
  // 测法（自洽对照，无需固定 fixture）：长按正文行尾附近字符 → 系统按渲染文本选中该词 → 点「翻译」→
  //   浮窗标题（wordPopupQuery）=取词结果 → 与 dump 实录的渲染文本对照：①必须是渲染文本的子串
  //   ②必须落在行尾窗口内（旧 bug 整体前移=取到前面的词，必出窗）③不得含 markdown 标记字符。
  //   确定性保证由 ohosTest MdInline.test（rendered_* 三断言）承担；本用例=设备端真链路回归。
  // 收尾：点遮罩关浮窗（closeWordPopup 同时取消查词请求——token 消耗≈0；零数据写入）。
  { id: 'SEL-ACCURACY', suite: 'chat', name: '划词取词·长按行尾词→翻译浮窗原文=所划之词（0.237.1 修复回归）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '划词取词（UI 断言专属，PC 无 UI 通道）'); return; }
      await coldStart(serial);
      if (!(await navIntoChat(ctx, serial))) return;
      // ① 选目标正文节点：单行（origBounds 全高≤80px≈1 行 lineHeight）、≥8 字、CJK 为主（字宽可估）——取最长者（偏 AI 消息）
      //    ★ R20261014194848 首跑实锤坑：司忆区词条行=单行省略号节点（dump text 含全文但屏显截断「…」）→ 排除尾部省略号
      //    ★ R20261014195159 二跑实锤坑：多行正文块滚出屏只剩「残条」（bounds h=19px、origBounds h=120px）——
      //      bounds 是可视残条高度，单行判定/字宽估算全错 → 必须用 origBounds 全高判单行 + bounds≈origBounds（完全可见）
      const nodes = await dumpAuditNodes(serial);
      const CHROME = ['条对话', '输入问题', '发送', '返回', '气泡', '朗读', '刷新', '条回复', '个模型', '引用：', '复制全文'];
      const cjkOf = (t) => (String(t).match(/[\u4e00-\u9fff\uff00-\uffef\u3000-\u303f]/g) || []).length;
      const isCjkCh = (ch) => /[\u4e00-\u9fff\uff00-\uffef\u3000-\u303f]/.test(ch);
      const parseRect = (s) => { const m = String(s || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/); return m ? { h: +m[4] - +m[2], w: +m[3] - +m[1] } : null; };
      const estW = (t, fs) => { let w = 0; for (let i = 0; i < t.length; i++) w += isCjkCh(t.charAt(i)) ? fs : fs * 0.55; return w; };
      const cand = nodes.nodes.filter((n) => {
        const t = String(n.text || '').trim();
        if (t.length < 8) return false;
        const ob = parseRect(n.origBounds);
        const fullH = ob ? ob.h : n.h;                                       // origBounds=完整高度（bounds=可视残条）
        if (fullH <= 0 || fullH > 80) return false;                          // 单行（按完整高度判）
        if (ob && n.h < fullH - 2) return false;                             // 滚出屏残条——只测完全可见的行
        if (cjkOf(t) / t.length < 0.5) return false;
        if (CHROME.some((k) => t.includes(k))) return false;
        if (t.endsWith('…') || t.endsWith('...')) return false;               // 省略号截断行（司忆区词条行同款）
        if (estW(t, Math.max(14, fullH / 1.5)) > n.w * 1.06) return false;    // 全文宽超节点宽=显示不全（横滑/截断）
        return true;
      }).sort((a, b) => String(b.text).length - String(a.text).length);
      if (!cand.length) { ctx.log('① 定位单行正文节点', 'fail', '未见「单行完整显示」的正文节点（司忆区截断行/滚屏残条已排除）——下滑露出更多正文再跑'); return; }
      const body = cand[0];
      const bodyText = String(body.text).trim();
      const L = bodyText.length;
      ctx.log('① 定位单行正文节点', 'pass', `(${Math.round(body.xc)},${Math.round(body.yc)})「${bodyText.slice(0, 18)}…」共 ${L} 字（h=${Math.round(body.h)}px 宽${Math.round(body.w)}px）`);
      // ② 按字符宽度估算行尾第 L-2 字的落点（CJK≈fontSizePx、其他≈0.55×；fontSizePx≈完整高/1.5——lineHeight=1.5×fontSize）
      const fsPx = (() => { const ob = parseRect(body.origBounds); return Math.max(14, (ob ? ob.h : body.h) / 1.5); })();
      const wOf = (ch) => (/[\u4e00-\u9fff\uff00-\uffef\u3000-\u303f]/.test(ch) ? fsPx : fsPx * 0.55);
      let cum = 0;
      for (let i = 0; i < L - 2; i++) cum += wOf(bodyText.charAt(i));
      const pressX = Math.min(body.x + cum + wOf(bodyText.charAt(L - 2)) / 2, body.x2 - 8);
      const pressY = Math.round(body.yc);
      ctx.log('② 估算行尾字符落点', 'pass', `长按 (${Math.round(pressX)},${pressY})（目标=倒数第 2 字「${bodyText.charAt(L - 2)}」附近，字宽≈${Math.round(fsPx)}px）`);
      await uiLongPress(serial, Math.round(pressX), pressY, 1600);
      // ③ 工具栏弹出（选中激活的可观测代理——同 SEL-CLEAR）
      const d1 = await ctx.art.dump(`SEL-ACCURACY-${dev.id}`, 'dump-toolbar.json', serial);
      const toolbarOn = d1.text.includes('入知识库');
      ctx.log('③ 长按后悬浮工具栏弹出', toolbarOn ? 'pass' : 'fail', toolbarOn ? '划词选中已激活' : '未见工具栏（长按未触发选择或落点在字外）');
      if (!toolbarOn) return;
      // ④ 点「翻译」→ 浮窗标题（wordPopupQuery）立即显示取词结果（不等 AI 返回）
      await uiClickText(serial, '翻译', { exact: true, waitMs: 900 });
      const d2 = await dumpFast(serial);
      await ctx.art.save(`SEL-ACCURACY-${dev.id}`, 'dump-popup.json', d2.text);
      const titleAndLoading = (() => {
        const hits = [];
        try {
          const walk = (n) => {
            if (!n || typeof n !== 'object') return;
            if (n.attributes) {
              const t = String(n.attributes.text || '').trim();
              const m = String(n.attributes.bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
              if (t && m) hits.push({ t, y: (+m[2] + +m[4]) / 2, x: (+m[1] + +m[3]) / 2 });
            }
            for (const k of Object.keys(n)) if (n[k] && typeof n[k] === 'object') walk(n[k]);
          };
          walk(JSON.parse(d2.text));
        } catch (_) { /* dump 非 JSON */ }
        const loading = hits.find((h) => h.t === '查询中...');
        if (!loading) return { loading: null, title: null };
        const above = hits.filter((h) => h.t !== '查询中...' && h.y < loading.y && Math.abs(h.x - loading.x) < 260 && h.t.length <= 12 && h.t !== bodyText);
        above.sort((a, b) => b.y - a.y);
        return { loading, title: above.length ? above[0] : null };
      })();
      if (!titleAndLoading.loading) { ctx.log('④ 翻译浮窗出现', 'fail', '未见「查询中...」（浮窗未弹出或翻译点击未生效）'); return; }
      if (!titleAndLoading.title) { ctx.log('④ 浮窗标题定位', 'fail', '浮窗在屏但标题节点未定位到（dump 存证人工复核）'); return; }
      const got = titleAndLoading.title.t;
      // ⑤ 三断言：子串 / 行尾窗口 / 无标记字符（重复字词取最后出现位置判尾部窗口——首次出现会误判）
      const isSub = bodyText.includes(got);
      const tailWin = Math.max(5, Math.ceil(L * 0.25));
      const pos = isSub ? bodyText.lastIndexOf(got) : -1;
      const inTail = pos >= L - tailWin;
      const noMark = !/[*~`\[]/.test(got);
      ctx.log('★取词=所划之词（渲染文本子串）', isSub ? 'pass' : 'fail',
        isSub ? `「${got}」∈ 渲染正文 ✓` : `取词「${got}」不是渲染文本的子串（取到标记/跨界文本——取词基准错位实锤）`);
      ctx.log('★取词落在划选位置（行尾窗口）', inTail ? 'pass' : 'fail',
        inTail ? `「${got}」位于倒数 ${L - pos}/${tailWin} 字窗口内（划哪取哪 ✓）` : `「${got}」位于第 ${pos + 1} 字——整体前移到划选位置之前（0.237.1 前「取到前面几个词」用户实锤复现）`);
      ctx.log('★取词无 markdown 标记残留', noMark ? 'pass' : 'warn',
        noMark ? '不含 * ~ ` [ 等标记字符 ✓' : `「${got}」含标记字符（旧基准=原始行含 ** 的直接证据）`);
      // ⑥ 收尾：点浮窗上方遮罩关闭（closeWordPopup 同时 cancel 查词请求——省 token + 零数据写入）
      await sh(serial, `uitest uiInput click ${Math.round(titleAndLoading.loading.x)} ${Math.round(Math.max(120, titleAndLoading.loading.y - 420))}`, 15000);
      await sleep(900);
      const d3 = await dumpFast(serial);
      ctx.log('⑥ 收尾关浮窗（取消查词）', d3.text.includes('查询中') ? 'warn' : 'pass', d3.text.includes('查询中') ? '浮窗仍在（遮罩点击未关——人工关一下，不阻断结果）' : '浮窗已关闭，查词请求已取消 ✓');
    } },

  // ---------- ★ 0.235.2 消息操作行（AI/用户消息下方「复制全文+删除」按钮；用户拍板刷新左边第 1 复制第 2 删除+整行左对齐） ----------
  // 操作行按钮=无文字 svg 图标（dump 无 text）——几何聚类定位：与正文左缘对齐、成行排列的近正方形小节点群
  //   （AI 行 4：复制/删除/刷新/喇叭；用户行恰 2：复制/删除）；fontSize dump 不可达（0.229.26 实证），
  //   左对齐断言用行首按钮 x ≈ 正文左缘 x 的相对几何（±60px 容 density 与半像素误差）
  // ★ 首轮盯屏三实锤（R20261014143634）：①按钮=容器(55px)+图标(35px)两层嵌套节点——去重合并（xc 差<25px 同一按钮）
  //   ②toast「已复制全文」仅显 1500ms——dumpLayout 内含 sleep1500 太慢，点后走 dumpFast 快捕（+400ms 即读）
  //   ③对话页大屏边栏常驻（x<480px 是边栏）——用户消息在列表上方常滚出屏，先测完 AI 行再下滑露出用户行
  // 数据安全红线（project_rule 持久化铁律）：删除只断言到「确认弹窗出现+取消保留」，不真删设备上的用户对话数据
  { id: 'CHAT-ACTIONS', suite: 'chat', name: '操作行·AI/用户消息下复制全文+删除按钮存在、左对齐、点击链路（0.235.2 新功能）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '操作行断言（UI 断言专属，PC 无 UI 通道）'); return; }
      await coldStart(serial);
      if (!(await navIntoChat(ctx, serial))) return;
      const d = await dumpAuditNodes(serial);
      if (!d.ok) { ctx.log('① 审计 dump', 'fail', 'dumpLayout -a 失败'); return; }
      const body = pickBodyTextNode(d.nodes);
      if (!body) { ctx.log('① 定位 AI 正文', 'fail', '未见≥12字正文节点（消息过短或结构变化）'); return; }
      ctx.log('① 定位 AI 正文', 'pass', `左缘 x=${Math.round(body.x)}——0.235.2 操作行应与其左对齐（margin left 10 = 气泡 padding 10）`);
      // ② 操作行聚类（去重版）：无文字近正方形小节点按 y 聚行；行内 xc 差<25px 的节点=同一按钮容器+图标嵌套，
      //   合并取外层（容器 x1 更小者）——首轮 8 节点实为 4 按钮×2 层
      const clusterRows = (nodes) => {
        const cands = nodes.filter((n) => !String(n.text || '').trim() && n.w >= 12 && n.h >= 12 && n.w <= 60 && n.h <= 60
          && Math.abs(n.w - n.h) <= Math.max(n.w, n.h) * 0.35).sort((a, b) => a.yc - b.yc);
        const raw = [];
        for (const n of cands) {
          const r = raw[raw.length - 1];
          if (r && Math.abs(n.yc - r.yc) <= Math.max(n.h, r.items[0].h) * 0.6) r.items.push(n);
          else raw.push({ items: [n], yc: n.yc });
        }
        return raw.filter((r) => r.items.length >= 2).map((r) => {
          const btns = [];
          for (const n of r.items.sort((a, b) => a.x - b.x)) {
            const last = btns[btns.length - 1];
            if (last && Math.abs(n.xc - last.xc) < 25) continue; // 容器+图标嵌套去重
            btns.push(n);
          }
          return { items: btns, yc: r.yc };
        }).filter((r) => r.items.length >= 2);
      };
      const rows = clusterRows(d.nodes);
      const aligned = rows.filter((r) => Math.abs(r.items[0].x - body.x) < 60); // 左对齐筛：行首与正文左缘对齐（边栏/顶栏图标 x 分散两侧天然出局）
      const aiRow = aligned.filter((r) => r.yc > body.y2).sort((a, b) => a.yc - b.yc)[0] || null;
      artSave('CHAT-ACTIONS', `rows-${dev.id}.json`, { body: { x: body.x, y2: body.y2 }, aligned });
      if (!aiRow) { ctx.log('★② AI 操作行存在', 'fail', '正文下方未找到与正文左对齐的按钮行（0.235.2 应有复制/删除/刷新/喇叭 4 按钮）'); return; }
      ctx.log('★② AI 操作行存在', aiRow.items.length >= 4 ? 'pass' : (aiRow.items.length === 3 ? 'warn' : 'fail'),
        `${aiRow.items.length} 个图标按钮在行（期望 4：复制+删除+刷新+喇叭；容器/图标嵌套已去重），行首 x=${Math.round(aiRow.items[0].x)} vs 正文左缘 ${Math.round(body.x)}（左对齐 0.235.2 拍板 ✓）`);
      // ③ 功能·AI 复制全文：点行首按钮（顺序=复制→删除→刷新）→ toast「已复制全文」（1500ms 短命——快捕）
      const copyBtn = aiRow.items[0];
      await sh(serial, `uitest uiInput click ${Math.round(copyBtn.xc)} ${Math.round(copyBtn.yc)}`, 15000);
      const t1 = await dumpFast(serial);
      let toastOk = t1.ok && t1.text.includes('已复制全文');
      if (!toastOk) { await sleep(600); const t2 = await dumpFast(serial); toastOk = t2.ok && t2.text.includes('已复制全文'); }
      artSave('CHAT-ACTIONS', `dump-copy-toast-${dev.id}.json`, t1.text);
      ctx.log('★③ AI 复制全文点击', toastOk ? 'pass' : 'fail',
        toastOk ? `已点 (${Math.round(copyBtn.xc)},${Math.round(copyBtn.yc)})——toast「已复制全文」在屏（copyFullMessage 链路活）` : '快捕×2 未见 toast「已复制全文」（按钮顺序变化或复制链路死——dump 已存证）');
      // ④ 功能·AI 删除确认弹窗：点第 2 按钮（删除）→「删除这条消息？」→ 取消（数据安全红线：不真删）
      if (aiRow.items.length >= 2) {
        const delBtn = aiRow.items[1];
        await sleep(800); // 等 toast 落幕防叠屏
        await sh(serial, `uitest uiInput click ${Math.round(delBtn.xc)} ${Math.round(delBtn.yc)}`, 15000);
        await sleep(1200);
        const dd = await ctx.art.dump(`CHAT-ACTIONS-${dev.id}`, 'dump-del-dialog.json', serial);
        const dlgOk = dd.text.includes('删除这条消息？') && dd.text.includes('此次对话不再提示');
        ctx.log('★④ AI 删除确认弹窗', dlgOk ? 'pass' : 'fail',
          dlgOk ? `已点 (${Math.round(delBtn.xc)},${Math.round(delBtn.yc)})——防误触确认弹窗在屏（复用 requestDeleteMessage 原链路）` : '未见删除确认弹窗（第 2 按钮非删除或链路断）');
        if (dlgOk) {
          const c = await uiClickText(serial, '取消', { exact: true, waitMs: 1000 });
          const dc2 = await dumpLayout(serial);
          ctx.log('⑤ 取消保留消息', !dc2.text.includes('删除这条消息？') ? 'pass' : 'fail',
            `已点「取消」(${c.x},${c.y})——弹窗关闭、消息保留（数据安全红线：自动用例不真删用户对话）`);
        }
      }
      // ⑥ 用户消息操作行（滚出屏补救）：列表默认滚到底，用户消息在上方——下滑×2 露出后重新 dump 聚类
      //    ★二轮实锤：行首 x=553 是复习区图标列（缩进不同）非用户行——收紧 x 差 <20px（真实用户行首
      //    =气泡 padding+margin 同链路，必与正文左缘 585 同 x）；dump 存证供盯屏
      const scrM = String((JSON.parse(d.text).attributes || {}).bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
      const scrW = scrM ? +scrM[3] : 2560, scrH = scrM ? +scrM[4] : 1700;
      const scrollUp = `uitest uiInput swipe ${Math.round(scrW / 2)} ${Math.round(scrH * 0.35)} ${Math.round(scrW / 2)} ${Math.round(scrH * 0.8)} 500`;
      await sh(serial, scrollUp, 20000);
      await sleep(900);
      await sh(serial, scrollUp, 20000);
      await sleep(1200);
      const dU = await dumpAuditNodes(serial);
      artSave('CHAT-ACTIONS', `dump-scrolled-${dev.id}.json`, dU.text);
      const rowsU = dU.ok ? clusterRows(dU.nodes) : [];
      artSave('CHAT-ACTIONS', `rowsU-${dev.id}.json`, rowsU.map((r) => ({ n: r.items.length, yc: Math.round(r.yc), xs: r.items.map((i) => Math.round(i.x)) })));
      const userRow = rowsU.filter((r) => r.items.length === 2 && Math.abs(r.items[0].x - body.x) < 20).sort((a, b) => b.yc - a.yc)[0] || null;
      if (!userRow) {
        ctx.log('★⑥ 用户操作行存在', 'fail', '下滑露出上方后仍未找到左对齐 2 按钮行（0.235.2 用户消息下方应有复制+删除两按钮）');
      } else {
        ctx.log('★⑥ 用户操作行存在', 'pass',
          `下滑后 ${userRow.items.length} 个图标按钮在行（复制+删除；用户消息无刷新/喇叭/token），行首 x=${Math.round(userRow.items[0].x)}（左对齐 ✓）`);
        // ⑦ 功能·用户消息复制全文（同 toast 文案——用户分支 content 直取）
        const uBtn = userRow.items[0];
        await sh(serial, `uitest uiInput click ${Math.round(uBtn.xc)} ${Math.round(uBtn.yc)}`, 15000);
        const tu = await dumpFast(serial);
        let toast2 = tu.ok && tu.text.includes('已复制全文');
        if (!toast2) { await sleep(600); const tu2 = await dumpFast(serial); toast2 = tu2.ok && tu2.text.includes('已复制全文'); }
        artSave('CHAT-ACTIONS', `dump-user-copy-toast-${dev.id}.json`, tu.text);
        ctx.log('★⑦ 用户消息复制全文', toast2 ? 'pass' : 'fail',
          toast2 ? `已点 (${Math.round(uBtn.xc)},${Math.round(uBtn.yc)})——toast 在屏（用户消息操作行链路活）` : '快捕×2 未见 toast（用户行首按钮非复制或链路断）');
        // ⑧ 用户消息删除弹窗→取消
        await sleep(800);
        await sh(serial, `uitest uiInput click ${Math.round(userRow.items[1].xc)} ${Math.round(userRow.items[1].yc)}`, 15000);
        await sleep(1200);
        const dd2 = await dumpLayout(serial);
        const dlg2 = dd2.text.includes('删除这条消息？');
        ctx.log('⑧ 用户消息删除弹窗', dlg2 ? 'pass' : 'fail', dlg2 ? '确认弹窗在屏（与 AI 删除同一确认链路 ✓）' : '未见确认弹窗');
        if (dlg2) await uiClickText(serial, '取消', { exact: true, waitMs: 900 });
      }
      const h = await hilogErrors(serial);
      ctx.log('链路 hilog 无错误', h.ok ? (h.n === 0 ? 'pass' : 'warn') : 'warn', h.ok ? `ERROR 计数=${h.n}` : 'hilog 读取异常');
    } },

  // ---------- ★ 0.235.2 滑动删除方向统一（用户拍板「往右滑」——AI 消息 swipeAction end→start，用户/AI 同向） ----------
  // ★ 首轮盯屏实锤：对话页大屏边栏常驻（x<480px 是边栏导航，点 72=跳页）——swipeAction start 面板出现在
  //   **列表区左缘**（边栏右侧），圆钮 44vp≈88px 独特大节点（普通按钮 55px 容器）——swipe 后 dump 找
  //   70~120px 方形节点即圆钮，点其中心弹防误触确认；取消保留（数据安全红线：不真删）
  { id: 'CHAT-SWIPE', suite: 'chat', name: '滑动删除·AI/用户消息右滑出回收站面板+确认链路（0.235.2 方向统一回归）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '滑动删除（UI 断言专属，PC 无 UI 通道）'); return; }
      await coldStart(serial);
      if (!(await navIntoChat(ctx, serial))) return;
      const d = await dumpAuditNodes(serial);
      if (!d.ok) { ctx.log('① 审计 dump', 'fail', 'dumpLayout -a 失败'); return; }
      const body = pickBodyTextNode(d.nodes);
      if (!body) { ctx.log('① 定位 AI 正文', 'fail', '未见≥12字正文节点'); return; }
      ctx.log('① 定位 AI 正文', 'pass', `中心 (${Math.round(body.xc)},${Math.round(body.yc)})——右滑目标行`);
      // ② 右滑 AI 消息（0.235.2 统一方向：start 侧面板从左滑出）
      // ★ 三轮盯屏实锤：①快速 swipe 在 Markdown 富文本正文上被 Text 手势拦截——必须 drag（velocity 300 慢拖）
      //   且起点避开正文区（body.y2 下方气泡底/操作行区）；②圆钮实测 110px（44vp×2.5）——判定窗 90~130px
      //   独尺寸（旧 70~130 误中复习区 80px 缩略图）；③紫色 #FF7C4DFF 圆钮在 (595,856) 类位置（列表左缘）
      const dragY = Math.round(body.y2 + 80);
      await sh(serial, `uitest uiInput drag ${Math.round(body.xc)} ${dragY} ${Math.round(body.xc + 560)} ${dragY} 300`, 20000);
      await sleep(1200);
      const dp = await dumpAuditNodes(serial);
      artSave('CHAT-SWIPE', `dump-ai-swiped-${dev.id}.json`, dp.text);
      // ★ 四轮实锤：拖拽过渡态圆钮可能非正方（110×55 压扁态）——判定改抓紫色 #FF7C4DFF 节点本体
      //   （BRAND_PRIMARY 圆钮/面板唯一紫；复习区缩略图是深紫 #FF2C1B4D 不误中），功能证据=点击后弹确认弹窗
      const knob = dp.ok ? dp.nodes.find((n) => !String(n.text || '').trim()
        && String(n.backgroundColor || '').toUpperCase() === '#FF7C4DFF' && n.x > 480 && n.x < 1500 && n.w >= 60) : null;
      let dlg = false;
      if (knob) {
        await sh(serial, `uitest uiInput click ${Math.round(knob.xc)} ${Math.round(knob.yc)}`, 15000);
        await sleep(1200);
        const dd = await dumpLayout(serial);
        dlg = dd.text.includes('删除这条消息？');
      }
      ctx.log('★② AI 消息右滑→面板→确认弹窗', dlg ? 'pass' : 'fail',
        dlg ? `右滑出回收站圆钮(${Math.round(knob.xc)},${Math.round(knob.yc)})、点击弹防误触确认（0.235.2 end→start 统一生效）`
            : knob ? '面板圆钮在屏但点击未弹确认（圆钮定位偏差或点击失效——dump 已存证）'
                   : '右滑后未找到 44vp 回收站圆钮（面板未出——0.235.2 方向统一回归红线；dump 已存证）');
      if (dlg) {
        const c = await uiClickText(serial, '取消', { exact: true, waitMs: 1000 });
        ctx.log('③ 取消保留消息', 'pass', `已点「取消」(${c.x},${c.y})——消息保留（数据安全红线）`);
        await sleep(600);
        await sh(serial, `uitest uiInput click ${Math.round(body.xc)} ${Math.round(body.y2 + 80)}`, 15000); // 点气泡底空白收面板
        await sleep(700);
      }
      // ④ 用户消息右滑（同面板同链路）：下滑×2 露出用户消息区，取左对齐 2 按钮行 y 为滑动手势 y
      const scrM = String((JSON.parse(d.text).attributes || {}).bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
      const scrW = scrM ? +scrM[3] : 2560, scrH = scrM ? +scrM[4] : 1700;
      const scrollUpS = `uitest uiInput swipe ${Math.round(scrW / 2)} ${Math.round(scrH * 0.35)} ${Math.round(scrW / 2)} ${Math.round(scrH * 0.8)} 500`;
      await sh(serial, scrollUpS, 20000);
      await sleep(900);
      await sh(serial, scrollUpS, 20000);
      await sleep(1200);
      const dU = await dumpAuditNodes(serial);
      const candsU = dU.ok ? dU.nodes.filter((n) => !String(n.text || '').trim() && n.w >= 12 && n.h >= 12 && n.w <= 60 && n.h <= 60
        && Math.abs(n.w - n.h) <= Math.max(n.w, n.h) * 0.35 && Math.abs(n.x - body.x) < 20) : [];
      const uY = candsU.length ? Math.round(candsU.map((n) => n.yc).sort((a, b) => a - b)[Math.floor(candsU.length / 2)]) : 0;
      if (!uY) {
        ctx.log('★④ 用户消息右滑→面板→确认弹窗', 'skip', '下滑后未找到用户消息操作行（无法定位用户消息行 y）——用户行存在性已由 CHAT-ACTIONS ⑥ 断言');
      } else {
        await sh(serial, `uitest uiInput drag ${Math.round(body.xc)} ${uY} ${Math.round(body.xc + 560)} ${uY} 300`, 20000);
        await sleep(1200);
        const du = await dumpAuditNodes(serial);
        const knob2 = du.ok ? du.nodes.find((n) => !String(n.text || '').trim()
          && String(n.backgroundColor || '').toUpperCase() === '#FF7C4DFF' && n.x > 480 && n.x < 1500 && n.w >= 60) : null;
        let dlg2 = false;
        if (knob2) {
          await sh(serial, `uitest uiInput click ${Math.round(knob2.xc)} ${Math.round(knob2.yc)}`, 15000);
          await sleep(1200);
          const dd2 = await dumpLayout(serial);
          dlg2 = dd2.text.includes('删除这条消息？');
        }
        ctx.log('★④ 用户消息右滑→面板→确认弹窗', dlg2 ? 'pass' : 'fail',
          `用户行 y=${uY} 右滑——` + (dlg2 ? '面板+确认链路通（用户消息 start 侧原有行为保持 ✓）' : '未见确认弹窗（面板未出或圆钮定位偏差；dump 已存证）'));
        if (dlg2) await uiClickText(serial, '取消', { exact: true, waitMs: 900 });
      }
    } },

  // ---------- ★ 0.244.0 bug2 回归：聊天页 ＋ 建子气泡→返回画布，气泡卡两两零重叠 ----------
  // 复刻用户手机实测路径（第二个子气泡重叠+连线没连上）；连线为 Canvas 不可 dump——重叠即连线悬空的可观测
  // 代理（修前实锤：新子气泡钉死在创建随机偏移位、与既有子气泡大面积相交）。
  { id: 'NODE-LAYOUT', suite: 'chat', name: '画布布局·聊天页建子气泡→返回画布零重叠（0.244.0 修复回归：云同步隐藏期替换 nodeList 致 ForEach 陈旧渲染）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '画布布局断言（UI 断言专属，PC 无 UI 通道）'); return; }
      await coldStart(serial);
      // ⓪ 进画布（复刻 CHAT-KEEP ⓪：冷启可能停首页/上轮残留页）
      let nav = await uiClickText(serial, '气泡树', { waitMs: 2200 });
      if (!nav.ok) nav = await uiClickText(serial, '进入气泡树', { waitMs: 2600 });
      if (!nav.ok) {
        await sh(serial, `uitest uiInput keyEvent Back`, 15000);
        await sleep(1500);
        nav = await uiClickText(serial, '气泡树', { waitMs: 2200 });
      }
      if (!nav.ok) { ctx.log('⓪ 进入气泡树画布', 'fail', '「气泡树」与「进入气泡树」均未命中（可能已在画布或首页改版）'); return; }
      ctx.log('⓪ 进入气泡树画布', 'pass', `已点击 (${nav.x},${nav.y})`);
      // ① 基线气泡卡收集（卡容器矩形口径——重叠断言基准）
      const d0 = await dumpAuditNodes(serial);
      if (!d0.ok) { ctx.log('① 基线 dump', 'fail', 'dumpLayout -a 失败'); return; }
      const cards0 = bubbleCardsOf(d0);
      if (!cards0.length) { ctx.log('① 基线气泡卡收集', 'fail', '未收集到气泡卡（「N 条对话」锚点未命中——画布结构变化？）'); return; }
      artSave('NODE-LAYOUT', `base-${dev.id}.json`, cards0.map((c) => ({ x: c.x, y: c.y, w: c.w, h: c.h })));
      ctx.log('① 基线气泡卡收集', 'pass', `${cards0.length} 张卡（卡容器矩形口径）`);
      // ② 进「有对话」的气泡（复刻 navIntoChat 定位口径：排除信息条与空气泡）
      const hits = findNodeBoundsAll(d0.text, '条对话').filter((h) => !String(h.text).includes('个气泡') && !String(h.text).startsWith('0 条对话'));
      if (!hits.length) { ctx.log('② 定位有对话的气泡', 'fail', '画布未见有对话气泡——先在某气泡发一条消息再跑本用例'); return; }
      const target = hits[hits.length - 1];
      ctx.log('② 定位有对话的气泡', 'pass', `(${target.x},${target.y})「${String(target.text).slice(0, 24)}」`);
      await uiDoubleClick(serial, target.x, target.y);
      await sleep(2400);
      const dc0 = await dumpLayout(serial);
      const inChat0 = /"text":\s*"\d+ 条对话"/.test(dc0.text) || dc0.text.includes('暂无对话');
      if (!inChat0) { ctx.log('③ 双击进入对话页', 'fail', '双击后仍在画布（双击未生效）'); return; }
      ctx.log('③ 双击进入对话页', 'pass', '对话页标题特征命中');
      // ④ 点 ＋ 新建子气泡（自动切换进新子气泡对话页——addBubble 链路）
      const da = await dumpAuditNodes(serial);
      if (!da.ok) { ctx.log('④ 定位＋按钮', 'fail', 'dumpLayout -a 失败'); return; }
      const plus = findChatPlusBtn(da);
      if (!plus) { ctx.log('④ 定位＋按钮', 'fail', '输入框左侧未见近方形 ＋ 容器（底栏结构变化？）'); return; }
      await sh(serial, `uitest uiInput click ${Math.round(plus.xc)} ${Math.round(plus.yc)}`, 15000);
      await sleep(3200); // 0.162 切换动画淡出 140ms+淡入 300ms + 余量
      const dc1 = await dumpLayout(serial);
      const childOk = /"text":\s*"0 条对话"/.test(dc1.text) && dc1.text.includes('暂无对话');
      ctx.log('★⑤ 新子气泡对话页（空）', childOk ? 'pass' : 'fail',
        childOk ? `已点 ＋ (${Math.round(plus.xc)},${Math.round(plus.yc)})——切进空子气泡（0 条对话+暂无对话）`
          : '未进入新子气泡对话页（＋点击未生效或切换失败）');
      if (!childOk) return;
      // ⑥ 停留 10s——云同步 flush（3s 防抖）+云往返+reconcile 触发窗（修前实锤：隐藏期 refreshWorkspaceFromPools
      //   整体替换 nodeList = 陈旧渲染的触发条件；测试等待最大化复现窗口）
      await sleep(10000);
      // ⑦ 返画布（onShown 消费 needsRelayout→autoLayout+fitViewport）
      await sh(serial, `uitest uiInput keyEvent Back`, 15000);
      await sleep(3000);
      // ⑧ 核心断言：气泡卡两两零重叠 + 数量 +1
      const d1 = await dumpAuditNodes(serial);
      if (!d1.ok) { ctx.log('⑧ 返画布 dump', 'fail', 'dumpLayout -a 失败'); return; }
      const cards1 = bubbleCardsOf(d1);
      artSave('NODE-LAYOUT', `after-${dev.id}.json`, cards1.map((c) => ({ x: c.x, y: c.y, w: c.w, h: c.h })));
      const countOk = cards1.length === cards0.length + 1;
      ctx.log('★⑧-1 子气泡已建（卡数 +1）', countOk ? 'pass' : 'fail',
        `基线 ${cards0.length} → 返画布 ${cards1.length}（期望 +1）`);
      let overlaps = [];
      for (let i = 0; i < cards1.length; i++) {
        for (let j = i + 1; j < cards1.length; j++) {
          const a = cards1[i]; const b = cards1[j];
          const ox = Math.min(a.x2, b.x2) - Math.max(a.x, b.x);
          const oy = Math.min(a.y2, b.y2) - Math.max(a.y, b.y);
          if (ox > 5 && oy > 5) overlaps.push(`卡${i}×卡${j} 交叠 ${Math.round(ox)}×${Math.round(oy)}px`);
        }
      }
      ctx.log('★⑧-2 气泡卡两两零重叠', overlaps.length ? 'fail' : 'pass',
        overlaps.length ? `重叠 ${overlaps.length} 对：${overlaps.join('；')}（0.244.0 前形态：新子气泡钉死创建随机偏移位=ForEach 陈旧渲染复发）`
          : `${cards1.length} 张卡全部无交叠（画布渲染与数据一致——0.244.0 rebuildEpoch 修复生效）`);
      // ⑨ 清理：删测试子气泡（双击进入徽标卡）+ hilog
      await deleteBadgeBubble(ctx, serial, `NODE-LAYOUT-${dev.id}`);
      const h = await hilogErrors(serial);
      ctx.log('链路 hilog 无错误', h.ok ? (h.n === 0 ? 'pass' : 'warn') : 'warn', h.ok ? `ERROR 计数=${h.n}` : 'hilog 读取异常');
    } },

  // ---------- ★ 0.244.0 bug3 回归：子气泡隔离（初始为空·父回复不搬入）+ 父气泡内容零改动（无重新生成） ----------
  // 用户实测两症状的数据级不变量：①新子气泡对话初始必为空（父 AI 回复「原封不动搬进来」=病）②返回父气泡
  // 消息数不变（「重新生成了内容」=病——真身=重叠遮挡点错气泡把追问发进了父/流尾孤儿化丢内容，两根已修）。
  // 全程零 AI 请求零 token；子回复独立性（AI 行为级）归人工验收。
  { id: 'NODE-CHILD-INTACT', suite: 'chat', name: '子气泡隔离·新建子气泡对话为空、父气泡内容零改动（0.244.0 修复回归）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '子气泡隔离断言（UI 断言专属，PC 无 UI 通道）'); return; }
      await coldStart(serial);
      let nav = await uiClickText(serial, '气泡树', { waitMs: 2200 });
      if (!nav.ok) nav = await uiClickText(serial, '进入气泡树', { waitMs: 2600 });
      if (!nav.ok) {
        await sh(serial, `uitest uiInput keyEvent Back`, 15000);
        await sleep(1500);
        nav = await uiClickText(serial, '气泡树', { waitMs: 2200 });
      }
      if (!nav.ok) { ctx.log('⓪ 进入气泡树画布', 'fail', '「气泡树」与「进入气泡树」均未命中'); return; }
      // ① 进有对话的父气泡 + 记录父消息数 P0（顶栏「N 条对话」无时间后缀=对话页特征）
      const d0 = await dumpAuditNodes(serial);
      if (!d0.ok) { ctx.log('① 画布 dump', 'fail', 'dumpLayout -a 失败'); return; }
      const hits = findNodeBoundsAll(d0.text, '条对话').filter((h) => !String(h.text).includes('个气泡') && !String(h.text).startsWith('0 条对话'));
      if (!hits.length) { ctx.log('① 定位有对话的父气泡', 'fail', '画布未见有对话气泡——先在某气泡发一条消息再跑本用例'); return; }
      const target = hits[hits.length - 1];
      const P0 = parseInt(String(target.text).match(/^(\d+) 条对话/)[1], 10);
      ctx.log('① 定位有对话的父气泡', 'pass', `(${target.x},${target.y})「${String(target.text).slice(0, 24)}」父消息数=${P0}`);
      await uiDoubleClick(serial, target.x, target.y);
      await sleep(2400);
      const dc0 = await dumpLayout(serial);
      const m0 = dc0.text.match(/"text":\s*"(\d+) 条对话"/);
      if (!m0) { ctx.log('② 双击进入父对话页', 'fail', '双击后仍在画布（双击未生效）'); return; }
      const P0live = parseInt(m0[1], 10);
      ctx.log('② 双击进入父对话页', 'pass', `顶栏「${P0live} 条对话」（画布计数 ${P0}${P0live === P0 ? ' 一致' : ' 不一致（含空气泡排除误差）'}）`);
      // ③ ＋ 新建子气泡 → 断言 A：子气泡初始为空（父回复未搬入）
      const da = await dumpAuditNodes(serial);
      const plus = da.ok ? findChatPlusBtn(da) : null;
      if (!plus) { ctx.log('③ 定位＋按钮', 'fail', '输入框左侧未见 ＋ 容器（底栏结构变化？）'); return; }
      await sh(serial, `uitest uiInput click ${Math.round(plus.xc)} ${Math.round(plus.yc)}`, 15000);
      await sleep(3200);
      const dc1 = await dumpLayout(serial);
      const childEmpty = /"text":\s*"0 条对话"/.test(dc1.text) && dc1.text.includes('暂无对话');
      const parentLeak = new RegExp(`"text":\\s*"${P0live} 条对话"`).test(dc1.text) && /·\s*(刚刚|\d+分钟前|\d+小时前|昨天)/.test(dc1.text);
      ctx.log('★断言A 子气泡初始为空（父回复不搬入）', childEmpty ? 'pass' : 'fail',
        childEmpty ? '新子气泡=0 条对话+暂无对话（父气泡 AI 回复零搬入——0.244.0 前用户实测「父回复原封不动搬进子气泡」未复发）'
          : (parentLeak ? '新子气泡页出现父气泡特征（N 条对话·时间）——切气泡失败/父内容泄漏（bug3 形态复发）' : '未进入新子气泡对话页（＋点击未生效）'));
      if (!childEmpty) return;
      // ④ 停留 10s（云同步 reconcile 触发窗）→ 返画布
      await sleep(10000);
      await sh(serial, `uitest uiInput keyEvent Back`, 15000);
      await sleep(3000);
      // ⑤ 重进父气泡：按「P0 条对话」前缀匹配（排除信息条/空气泡）
      const d2 = await dumpLayout(serial);
      const parentHits = findNodeBoundsAll(d2.text, '条对话').filter((h) => !String(h.text).includes('个气泡') && String(h.text).startsWith(`${P0} 条对话`));
      if (!parentHits.length) { ctx.log('⑤ 重进父气泡', 'fail', `返画布未见「${P0} 条对话」气泡卡（父气泡丢失?!——dump 已存证）`); return; }
      await uiDoubleClick(serial, parentHits[0].x, parentHits[0].y);
      await sleep(2400);
      const dc2 = await dumpLayout(serial);
      const m2 = dc2.text.match(/"text":\s*"(\d+) 条对话"/);
      // ⑥ 断言 B：父消息数不变（内容零改动——无重新生成/无搬走）
      const intact = m2 !== null && parseInt(m2[1], 10) === P0live;
      ctx.log('★断言B 父气泡内容零改动', intact ? 'pass' : 'fail',
        intact ? `父气泡仍 ${P0live} 条对话（建子气泡+云同步往返后消息数不变——0.244.0 前用户实测「返回父气泡重新生成了内容」未复发）`
          : `父消息数 ${P0live} → ${m2 ? m2[1] : '?'}（消息被增删=内容改动实锤——流尾孤儿化/误入父对话复发）`);
      // ⑦ 清理：删测试子气泡
      await sh(serial, `uitest uiInput keyEvent Back`, 15000);
      await sleep(2500);
      await deleteBadgeBubble(ctx, serial, `NODE-CHILD-INTACT-${dev.id}`);
    } },

  // ---------- ★ 0.237.0 折叠指示器军令断言（用户拍板「全项目只许一套折叠三角」→ SVG chevron 唯一） ----------
  // 三断言：① 折叠行右侧只留「约 X 字」（去「共 N 节」）② 折叠类字符三角（▸▶▼▲）全屏清零（发送▾=菜单语义
  //   合法 ≤1）③ 折叠行行首=FoldChevron Image 在位（≈12vp，同一颗 chevron_fold 旋转两态——同源即无「另一个型号」）
  { id: 'CHAT-FOLD', suite: 'chat', name: '折叠指示器·SVG 同源+字符三角清零+去共N节（0.237.0 军令回归）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '折叠指示器断言（UI 断言专属，PC 无 UI 通道）'); return; }
      await coldStart(serial);
      if (!(await navIntoChat(ctx, serial))) return;
      const d = await dumpAuditNodes(serial);
      if (!d.ok) { ctx.log('① 审计 dump', 'fail', 'dumpLayout -a 失败'); return; }
      artSave('CHAT-FOLD', `dump-${dev.id}.json`, d.text);
      // ① 折叠行存在性（0.237.0 起特征文案=「约 N 字」——「共 N 节」已删）
      const foldRows = d.nodes.filter((n) => /约 \d+ 字/.test(String(n.text || '')));
      if (foldRows.length === 0) { ctx.log('★折叠指示器', 'skip', '当前对话无章节折叠行（无 ≥3 节长回复或折叠开关关）——换有长 AI 回复的气泡再跑本用例'); return; }
      ctx.log('① 折叠行在屏', 'pass', `${foldRows.length} 行（首行「${String(foldRows[0].text).slice(0, 24)}」）`);
      // ② 去「共 N 节」
      const hasN = d.nodes.some((n) => /共 \d+ 节/.test(String(n.text || '')));
      ctx.log('★② 去共N节', hasN ? 'fail' : 'pass',
        hasN ? '折叠行仍显示「共 N 节」（0.237.0 应只留「约 X 字」）' : '折叠行右侧只留「约 X 字」✓（0.237.0 用户拍板）');
      // ③ 折叠类字符三角清零（发送 ▾ 下拉=菜单语义合法保留 ≤1；GSD 下拉不在对话页）
      //   ★节点计数（非原始文本 match）——dump -a 的 text/originalText 双字段含同一字符，raw match 会双计
      const triNode = (ch) => d.nodes.filter((n) => String(n.text || '').trim() === ch);
      const legacy = ['▸', '▶', '▼', '▲'].map((ch) => ({ ch, n: triNode(ch).length })).filter((x) => x.n > 0);
      const downN = triNode('▾').length;
      const legacyBad = legacy.length > 0 || downN > 1;
      ctx.log('★③ 字符三角清零', legacyBad ? 'fail' : 'pass',
        legacyBad
          ? `残留：${legacy.map((x) => `${x.ch}×${x.n}`).join(' ')}${downN > 1 ? ` ▾×${downN}（>1，仅发送下拉 1 处合法）` : ''}——0.237.0 UI_GUIDELINES §13 军令红线（折叠指示器必须 SVG 唯一）`
          : `▸▶▼▲ 全零；▾=${downN} 处（≤1=发送下拉，合法）——折叠三角已 SVG 化 ✓`);
      // ④ 折叠行行首=FoldChevron Image（同线左侧小 Image，与行内文本同高域）
      const chevs = d.nodes.filter((n) => String(n.type || '').toLowerCase() === 'image' && n.w >= 15 && n.w <= 70 &&
        foldRows.some((r) => Math.abs(n.yc - r.yc) < Math.max(r.h, 24)));
      artSave('CHAT-FOLD', `chevs-${dev.id}.json`, chevs.map((n) => ({ x: n.x, y: n.y, w: n.w, h: n.h })));
      if (chevs.length === 0) {
        ctx.log('★④ 折叠行 SVG 指示器', 'fail', `折叠行在屏但行首未见 FoldChevron Image（${foldRows.length} 行均无——指示器未渲染或 dump 缺失）`);
      } else {
        const ws = chevs.map((n) => n.w);
        const ratio = chevs.length > 1 ? Math.max(...ws) / Math.min(...ws) : 1;
        ctx.log('★④ 折叠行 SVG 指示器', ratio < 1.35 ? 'pass' : 'fail',
          `${chevs.length} 处行首 Image 宽 ${Math.round(Math.min(...ws))}~${Math.round(Math.max(...ws))}px${chevs.length > 1 ? ` max/min=${ratio.toFixed(2)}` : ''}（<1.35=同 12vp 族——同一颗 chevron_fold 旋转两态，物理上不可能出现另一个型号）`);
      }
    } },


  // ---------- ★ 0.239.0 知识库双视图 + 加号菜单双库统一（kbview 套件；Pad 专属——手机端不渲染切换按钮、PC 无 uiClick 通道） ----------
  { id: 'KB-VIEW', suite: 'kbview', name: '双视图·切换按钮在场+网格封面卡多列+无图占位+跨页记忆+切回列表（0.239.0 新功能）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '双视图断言（UI 断言专属，PC 无 uiClick 通道）'); return; }
      if (dev.id === 'phone') { ctx.log('★双视图', 'skip', '手机端不渲染切换按钮（0.239.0 既定设计，与单词库一致——手机恒列表）'); return; }
      await coldStart(serial);
      const nav = await navTo(serial, '知识库', ctx.log);
      if (!nav.ok) { ctx.log('★双视图', 'fail', '未能进入知识库页（边栏「知识库」未命中）'); return; }
      const d0 = await dumpAuditNodes(serial);
      if (!d0.ok) { ctx.log('① dump', 'fail', 'dumpLayout -a 失败'); return; }
      if (d0.text.includes('知识库为空')) { ctx.log('★双视图', 'skip', '设备知识库为空——先导入/新建卡片再跑本用例'); return; }
      // ① 切换按钮定位：排序文字（最新/需复习）与 ＋ 之间的 Image 图标（左一枚=视图切换，右一枚=⚙ 设置）
      const sortT = d0.nodes.filter((n) => /^(最新|需复习) [↑↓]$/.test(String(n.text || '').trim()));
      const plusT = o0plus(d0.nodes);
      if (!sortT.length || !plusT) { ctx.log('★① 切换按钮定位', 'fail', `排序文字×${sortT.length} / ＋×${plusT ? 1 : 0}——锚点缺失`); return; }
      const s = sortT[0]; const p = plusT;
      const icons = o0icons(d0.nodes, s, p);
      if (!icons.length) { ctx.log('★① 切换按钮在场', 'fail', `排序与＋之间未找到 28vp 图标（仅 ${icons.length} 枚）——视图切换按钮未渲染（宽屏条件 isTablet||isPcDevice 未满足？）`); return; }
      const toggle = icons[0];
      ctx.log('★① 切换按钮在场', 'pass', `排序与＋之间 ${icons.length} 枚图标，左一枚=视图切换 (${Math.round(toggle.xc)},${Math.round(toggle.yc)}) ${Math.round(toggle.w)}px——次序=排序→视图→设置→＋`);
      artSave('KB-VIEW', `anchors-${dev.id}.json`, { sort: [s.x, s.y, s.w, s.h], plus: [p.x, p.y, p.w, p.h], icons: icons.map((i) => [i.x, i.y, i.w, i.h]) });
      // ② 点切换 → 网格断言：复习状态小字同行 ≥2 列（多列布局铁证）
      await sh(serial, `uitest uiInput click ${Math.round(toggle.xc)} ${Math.round(toggle.yc)}`, 15000);
      await sleep(1600);
      const d2 = await dumpAuditNodes(serial);
      if (!d2.ok) { ctx.log('② 网格 dump', 'fail', 'dumpLayout -a 失败'); return; }
      artSave('KB-VIEW', `grid-${dev.id}.json`, d2.nodes.map((n) => ({ t: n.text, x: n.x, y: n.y, w: n.w, h: n.h })));
      const g = gridColsOf(d2);
      if (g.labels === 0) { ctx.log('★② 网格多列封面卡', 'fail', '网格下未见复习状态小字（未学习/需复习/下次复习：）——网格未渲染'); return; }
      ctx.log('★② 网格多列封面卡', g.multi ? 'pass' : 'fail',
        g.multi ? `同一横带两列复习状态 ${g.pair}——多列网格生效（${g.labels} 条状态在屏）` : `复习状态 ${g.labels} 条但全在同一竖列——仍是列表布局（切换未生效？）`);
      // ③ 无图占位：34vp 大号单字 Text（高 ≥60px；库内卡全有图=skip）
      const ph = d2.nodes.filter((n) => /^.{1}$/.test(String(n.text || '').trim()) && n.h >= 60);
      ctx.log('③ 无图卡紫渐变占位', ph.length ? 'pass' : 'skip',
        ph.length ? `${ph.length} 处大号首字占位（高 ${Math.round(ph[0].h)}px=34vp 档）——无图卡不空不单调` : '在屏卡片全有封面图（占位分支本轮未覆盖——留一张无图卡再跑可验）');
      // ④ 跨页记忆：Back 退出 → 重进 → 仍多列
      await sh(serial, `uitest uiInput keyEvent Back`, 15000);
      await sleep(1600);
      const nav2 = await navTo(serial, '知识库', ctx.log);
      if (!nav2.ok) { ctx.log('★④ 跨页记忆', 'fail', '退出后重进知识库失败'); return; }
      const d3 = await dumpAuditNodes(serial);
      const g3 = d3.ok ? gridColsOf(d3) : { labels: 0, multi: false, pair: '' };
      ctx.log('★④ 跨页记忆', g3.multi ? 'pass' : 'fail',
        g3.multi ? '退出重进后仍多列网格——knowledge-view-mode 跨页面记忆生效（AppStorageV2）' : `重进后回到单列（${g3.labels} 条状态）——跨页面记忆失效`);
      // ⑤ 切回列表：再点切换 → 复习状态全部左对齐同列
      await sh(serial, `uitest uiInput click ${Math.round(toggle.xc)} ${Math.round(toggle.yc)}`, 15000);
      await sleep(1600);
      const d4 = await dumpAuditNodes(serial);
      const labels4 = d4.ok ? d4.nodes.filter((n) => /^(未学习|需复习|下次复习：)/.test(String(n.text || '').trim())) : [];
      const xs = labels4.map((n) => n.x);
      const spread = xs.length > 1 ? Math.max(...xs) - Math.min(...xs) : -1;
      ctx.log('★⑤ 切回列表', (labels4.length > 0 && spread >= 0 && spread < 60) ? 'pass' : 'fail',
        labels4.length === 0 ? '列表下未见复习状态（dump 异常？）' : `复习状态 x 极差 ${Math.round(spread)}px（<60=全部左对齐同列）——列表模式完整恢复`);
    } },

  { id: 'KB-PLUS', suite: 'kbview', name: '知识库+菜单·紧凑宽度+左下方弹出+二级drill-down往返（0.239.0 双库统一）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '+菜单断言（UI 断言专属，PC 无 uiClick 通道）'); return; }
      await coldStart(serial);
      const nav = await navTo(serial, '知识库', ctx.log);
      if (!nav.ok) { ctx.log('★+菜单', 'fail', '未能进入知识库页'); return; }
      const dRaw = await dumpLayout(serial);
      const pr = findTextRect(dRaw.text, '+');
      if (!pr) { ctx.log('★+菜单', 'fail', '未找到 ＋ 按钮'); return; }
      const estW = pr.x2 + 40; // 顶栏右 padding ≈14vp → 屏宽近似
      const open = await uiClickText(serial, '+', { exact: true, waitMs: 1300 });
      if (!open.ok) { ctx.log('★① 菜单弹出', 'fail', open.err || '点击 ＋ 后未弹出'); return; }
      const d1 = await dumpAuditNodes(serial);
      artSave('KB-PLUS', `menu-${dev.id}.json`, d1.nodes.map((n) => ({ t: n.text, x: n.x, y: n.y, w: n.w, h: n.h })));
      const items = ['新建卡片', '导入 ›', '导出 ›'].filter((k) => d1.text.includes(k));
      if (items.length < 3) { ctx.log('★① 菜单弹出', 'fail', `三主项只命中 ${items.length}/3（${items.join('/')}）——弹层未开或文案变了`); return; }
      // ② 紧凑宽度 + BottomRight 左下方（菜单文字并集矩形 vs ＋ 矩形）
      const mNodes = d1.nodes.filter((n) => ['新建卡片', '导入 ›', '导出 ›'].includes(String(n.text || '').trim()));
      const minL = Math.min(...mNodes.map((n) => n.x)); const maxR = Math.max(...mNodes.map((n) => n.x2));
      const minT = Math.min(...mNodes.map((n) => n.y));
      const menuW = maxR - minL;
      const narrow = menuW < estW * 0.42;
      ctx.log('★② 宽度收窄', narrow ? 'pass' : 'fail',
        narrow ? `菜单宽 ${Math.round(menuW)}px ≈ ${Math.round(menuW / estW * 100)}% 屏宽（<42%）——按最长项自适应，无全宽铺满` : `菜单宽 ${Math.round(menuW)}px（≥42% 屏宽 ${Math.round(estW)}）——仍是全宽弹层（.width('100%') 未删净？）`);
      const below = minT > pr.y2 - 10;
      // ★ 面板右缘断言（文字右缘≠面板右缘——文字受左右 padding 内缩；面板=SURFACE_NODE 底色容器）：
      //   dump -a 的 backgroundColor 归一化小写 #ff241640，取＋正下方、宽 <45% 屏的最大命中=弹层面板
      const panel = d1.nodes.filter((n) => String(n.backgroundColor || '').toLowerCase() === '#ff241640'
        && n.y >= pr.y2 - 10 && (n.x2 - n.x) > 50 && (n.x2 - n.x) < estW * 0.45)
        .sort((a, b) => (b.x2 - b.x) - (a.x2 - a.x))[0];
      const rightAlign = panel ? Math.abs(panel.x2 - pr.x2) <= 60 : false;
      ctx.log('★③ 左下方弹出', (below && rightAlign) ? 'pass' : 'fail',
        panel
          ? `面板 ${Math.round(panel.x2 - panel.x)}×${Math.round(panel.y2 - panel.y)}px 右缘 ${Math.round(panel.x2)} vs ＋右缘 ${Math.round(pr.x2)}（差 ${Math.round(Math.abs(panel.x2 - pr.x2))}px ≤60=右缘对齐）；面板顶 ${Math.round(panel.y)} > ＋底 ${Math.round(pr.y2)}=${below ? '在下方 ✓' : '未在下方 ✗'}——Placement.BottomRight`
          : `未定位到弹层面板（SURFACE_NODE 底色容器）——人工复核 dump 存证`);
      // ④ 二级 drill-down 往返：导入 › → 5 项 + ‹ 返回 → 回主级
      await uiClickText(serial, '导入 ›', { exact: true, waitMs: 1300 });
      const d2 = await dumpAuditNodes(serial);
      const impItems = ['DAG（知识库包）', 'APKG（Anki 包）', 'TXT', 'CSV', 'XLSX'].filter((k) => d2.text.includes(k));
      const hasBack = d2.text.includes('‹ 返回');
      ctx.log('★④ 二级导入菜单', (impItems.length === 5 && hasBack) ? 'pass' : 'fail',
        `导入 5 项命中 ${impItems.length}/5${hasBack ? ' + ‹返回 ✓' : '（无返回行）'}——drill-down 层级正常`);
      if (hasBack) {
        await uiClickText(serial, '‹ 返回', { exact: true, waitMs: 1300 });
        const d3 = await dumpAuditNodes(serial);
        ctx.log('★⑤ 返回主级', d3.text.includes('新建卡片') ? 'pass' : 'fail', d3.text.includes('新建卡片') ? '‹ 返回回主级三主项 ✓' : '返回后未见主级（drill-down 状态错乱）');
      }
      // ⑥ 点遮罩关闭（几何点击＋左下方内容区——TextInput placeholder 在 attributes.hint 不在 text，findTextRect 定位不到搜索框）
      await sh(serial, `uitest uiInput click ${Math.round(pr.x1 - 300)} ${Math.round(pr.y2 + 300)}`, 15000);
      await sleep(1000);
      const d4 = await dumpLayout(serial);
      ctx.log('⑥ 遮罩关闭', !d4.text.includes('新建卡片') ? 'pass' : 'warn', !d4.text.includes('新建卡片') ? '点遮罩后菜单收起 ✓（重开应从 main 开始）' : '菜单仍在屏（点击未落遮罩——人工复核）');
    } },

  { id: 'WB-PLUS', suite: 'kbview', name: '单词库+菜单·bindPopup 统一规格三项+紧凑+左下方（0.239.0 换掉系统 bindMenu）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '+菜单断言（UI 断言专属，PC 无 uiClick 通道）'); return; }
      await coldStart(serial);
      const nav = await navTo(serial, '单词库', ctx.log);
      if (!nav.ok) { ctx.log('★+菜单', 'fail', '未能进入单词库页'); return; }
      const dRaw = await dumpLayout(serial);
      const pr = findTextRect(dRaw.text, '+');
      if (!pr) { ctx.log('★+菜单', 'fail', '未找到 ＋ 按钮'); return; }
      const estW = pr.x2 + 40;
      const open = await uiClickText(serial, '+', { exact: true, waitMs: 1300 });
      if (!open.ok) { ctx.log('★① 菜单弹出', 'fail', open.err || '点击 ＋ 后未弹出'); return; }
      const d1 = await dumpAuditNodes(serial);
      artSave('WB-PLUS', `menu-${dev.id}.json`, d1.nodes.map((n) => ({ t: n.text, x: n.x, y: n.y, w: n.w, h: n.h })));
      const want = ['新建单词', '导入 DagPack（单词包）', '导出 DagPack（整库单词）'];
      const items = want.filter((k) => d1.text.includes(k));
      if (items.length < 3) { ctx.log('★① 三项在场', 'fail', `三项只命中 ${items.length}/3（${items.join('/')}）——bindPopup 菜单未弹出或文案变了`); return; }
      ctx.log('★① 三项在场', 'pass', `${items.join(' / ')}——系统 bindMenu 已换 bindPopup 且文字 action 原样保留`);
      const mNodes = d1.nodes.filter((n) => want.includes(String(n.text || '').trim()));
      const minL = Math.min(...mNodes.map((n) => n.x)); const maxR = Math.max(...mNodes.map((n) => n.x2));
      const minT = Math.min(...mNodes.map((n) => n.y));
      const menuW = maxR - minL;
      ctx.log('★② 宽度收窄', menuW < estW * 0.42 ? 'pass' : 'fail',
        `菜单宽 ${Math.round(menuW)}px ≈ ${Math.round(menuW / estW * 100)}% 屏宽${menuW < estW * 0.42 ? '（<42%）——内容自适应，无系统菜单右侧大留白' : '——仍偏宽（复核）'}`);
      const below = minT > pr.y2 - 10;
      const panel = d1.nodes.filter((n) => String(n.backgroundColor || '').toLowerCase() === '#ff241640'
        && n.y >= pr.y2 - 10 && (n.x2 - n.x) > 50 && (n.x2 - n.x) < estW * 0.45)
        .sort((a, b) => (b.x2 - b.x) - (a.x2 - a.x))[0];
      const rightAlign = panel ? Math.abs(panel.x2 - pr.x2) <= 60 : false;
      ctx.log('★③ 左下方弹出', (below && rightAlign) ? 'pass' : 'fail',
        panel
          ? `面板 ${Math.round(panel.x2 - panel.x)}px 右缘 vs ＋右缘差 ${Math.round(Math.abs(panel.x2 - pr.x2))}px（≤60=右缘对齐）；在＋下方=${below ? '✓' : '✗'}——BottomRight 统一规格`
          : `未定位到弹层面板（SURFACE_NODE 底色容器）——人工复核 dump 存证`);
      // ④ 点遮罩关闭（点 ＋ 左下方内容区）
      await sh(serial, `uitest uiInput click ${Math.round(pr.x1 - 300)} ${Math.round(pr.y2 + 300)}`, 15000);
      await sleep(1000);
      const d2 = await dumpLayout(serial);
      ctx.log('④ 遮罩关闭', !d2.text.includes('新建单词') ? 'pass' : 'warn', !d2.text.includes('新建单词') ? '点遮罩后菜单收起 ✓' : '菜单仍在屏（点击未落遮罩——人工复核）');
    } },

  // ---------- ★ 0.240.0 排序按钮图标化 + 手机端搜索栏滚动隐藏（两库同款改造；测试覆盖军令 §12.13） ----------
  { id: 'KB-SORT-ICON', suite: 'kbview', name: '知识库排序·图标化按钮+弹层紫底高亮+切换/反转链路（0.240.0 改造）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '排序断言（UI 断言专属，PC 无 uiClick 通道）'); return; }
      await coldStart(serial);
      const nav = await navTo(serial, '知识库', ctx.log);
      if (!nav.ok) { ctx.log('★排序', 'fail', '未能进入知识库页'); return; }
      const d0 = await dumpLayout(serial);
      // ① 旧紫底文字按钮拆净（图标化后屏上应无「最新 ↓」按钮文字）
      const noOldBtn = !d0.text.includes('最新 ↓');
      ctx.log('★① 文字按钮已拆', noOldBtn ? 'pass' : 'fail',
        noOldBtn ? '屏上无「最新 ↓」文字按钮——已换 sort.svg 图标' : '「最新 ↓」仍在屏（图标化未生效/装了旧包）');
      const pr = findTextRect(d0.text, '+');
      if (!pr) { ctx.log('★② 打开排序弹层', 'fail', '未找到 ＋ 按钮（排序图标定位基准）'); return; }
      // ② 图标按钮试探测点击（图标无文字——按 ＋ 左侧顶栏带偏移逐个试，覆盖手机/宽屏 × density2/3 的排序位；
      //    弹层特征=「最新 ↓」+「需复习 ↑」双在场；误触 ＋菜单/设置弹窗则点遮罩先关再续）
      let opened = false; let hitOff = 0;
      for (const off of [170, 105, 215, 260, 140]) {
        await sh(serial, `uitest uiInput click ${Math.round(pr.x1 - off)} ${Math.round((pr.y1 + pr.y2) / 2)}`, 15000);
        await sleep(1100);
        const dt = await dumpLayout(serial);
        if (dt.text.includes('最新 ↓') && dt.text.includes('需复习 ↑')) { opened = true; hitOff = off; break; }
        if (dt.text.includes('新建卡片') || dt.text.includes('每次复习展示的卡片数')) {
          await sh(serial, `uitest uiInput click ${Math.round(pr.x1 - 300)} ${Math.round(pr.y2 + 300)}`, 15000);
          await sleep(800);
        }
      }
      if (!opened) { artSave('KB-SORT-ICON', `probe-fail-${dev.id}.json`, d0.text); ctx.log('★② 打开排序弹层', 'fail', '顶栏偏移试探 5 点未弹排序层（图标定位失败——人工盯屏校准偏移，dump 已存证）'); return; }
      const d1 = await dumpAuditNodes(serial);
      artSave('KB-SORT-ICON', `menu-${dev.id}.json`, d1.nodes.map((n) => ({ t: n.text, bg: n.backgroundColor, x: n.x, y: n.y })));
      ctx.log('★② 打开排序弹层', 'pass', `排序图标位于＋左侧 ${hitOff}px——弹层「最新 ↓/需复习 ↑」双在场`);
      // ③ 当前项紫底高亮（0.240.0：BRAND_SECONDARY 紫字 + SURFACE_HOVER #FF2C1B4D 紫底双标识）
      const hl = (nodes, kw) => nodes.filter((n) => String(n.text || '').trim() === kw && String(n.backgroundColor || '').toLowerCase() === '#ff2c1b4d').length > 0;
      ctx.log('★③ 当前项紫底高亮', hl(d1.nodes, '最新 ↓') ? 'pass' : 'fail',
        hl(d1.nodes, '最新 ↓') ? '「最新 ↓」节点底色 #FF2C1B4D（SURFACE_HOVER）——紫字+紫底双标识' : '「最新 ↓」未见紫底（高亮未挂或装旧包）');
      // ④ 切换排序：点「需复习 ↑」→ 弹层不收起 + 高亮跟手
      await uiClickText(serial, '需复习 ↑', { exact: true, waitMs: 1000 });
      const d2 = await dumpAuditNodes(serial);
      const stayOpen = d2.text.includes('最新 ↓') && d2.text.includes('需复习');
      ctx.log('★④ 切换不收起', stayOpen ? 'pass' : 'fail', stayOpen ? '点选项后弹层仍在（可连续切换交互保留）' : '弹层收起（点选项不收起被破坏）');
      ctx.log('★④b 高亮跟手', hl(d2.nodes, '需复习 ↑') ? 'pass' : 'fail', hl(d2.nodes, '需复习 ↑') ? '切到需复习后紫底跳至「需复习 ↑」行' : '需复习行未见紫底（高亮未跟手）');
      // ⑤ 点当前项反转方向（需复习 ↑ → 需复习 ↓，仍高亮）
      await uiClickText(serial, '需复习 ↑', { exact: true, waitMs: 1000 });
      const d3 = await dumpAuditNodes(serial);
      const flipped = d3.text.includes('需复习 ↓') && !d3.text.includes('需复习 ↑');
      ctx.log('★⑤ 点当前项反转', flipped && hl(d3.nodes, '需复习 ↓') ? 'pass' : 'fail',
        flipped ? `反转后「需复习 ↓」${hl(d3.nodes, '需复习 ↓') ? '且紫底在 ✓' : '但紫底丢失'}` : '未见反转（屏上仍「需复习 ↑」或两者并存）');
      // ⑥ 点遮罩关闭
      await sh(serial, `uitest uiInput click ${Math.round(pr.x1 - 300)} ${Math.round(pr.y2 + 300)}`, 15000);
      await sleep(1000);
      const d4 = await dumpLayout(serial);
      ctx.log('⑥ 遮罩关闭', !d4.text.includes('需复习') ? 'pass' : 'warn', !d4.text.includes('需复习') ? '点遮罩后排序层收起 ✓' : '排序项仍在屏（点击未落遮罩——人工复核）');
    } },

  { id: 'WB-SORT-ICON', suite: 'kbview', name: '单词库排序·图标化按钮+三选项弹层紫底高亮+切字母+反转（0.240.0 改造）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '排序断言（UI 断言专属，PC 无 uiClick 通道）'); return; }
      await coldStart(serial);
      const nav = await navTo(serial, '单词库', ctx.log);
      if (!nav.ok) { ctx.log('★排序', 'fail', '未能进入单词库页'); return; }
      const d0 = await dumpLayout(serial);
      const noOldBtn = !d0.text.includes('最新 ↓');
      ctx.log('★① 文字按钮已拆', noOldBtn ? 'pass' : 'fail',
        noOldBtn ? '屏上无「最新 ↓」文字按钮——已换 sort.svg 图标' : '「最新 ↓」仍在屏（图标化未生效/装了旧包）');
      const pr = findTextRect(d0.text, '+');
      if (!pr) { ctx.log('★② 打开排序弹层', 'fail', '未找到 ＋ 按钮（排序图标定位基准）'); return; }
      let opened = false; let hitOff = 0;
      for (const off of [170, 105, 215, 260, 140]) {
        await sh(serial, `uitest uiInput click ${Math.round(pr.x1 - off)} ${Math.round((pr.y1 + pr.y2) / 2)}`, 15000);
        await sleep(1100);
        const dt = await dumpLayout(serial);
        if (dt.text.includes('最新 ↓') && dt.text.includes('需复习 ↑') && dt.text.includes('字母 ↑')) { opened = true; hitOff = off; break; }
        if (dt.text.includes('新建单词') || dt.text.includes('每次展示的词条数')) {
          await sh(serial, `uitest uiInput click ${Math.round(pr.x1 - 300)} ${Math.round(pr.y2 + 300)}`, 15000);
          await sleep(800);
        }
      }
      if (!opened) { artSave('WB-SORT-ICON', `probe-fail-${dev.id}.json`, d0.text); ctx.log('★② 打开排序弹层', 'fail', '顶栏偏移试探 5 点未弹排序层（图标定位失败——人工盯屏校准，dump 已存证）'); return; }
      const d1 = await dumpAuditNodes(serial);
      artSave('WB-SORT-ICON', `menu-${dev.id}.json`, d1.nodes.map((n) => ({ t: n.text, bg: n.backgroundColor, x: n.x, y: n.y })));
      ctx.log('★② 打开排序弹层', 'pass', `排序图标位于＋左侧 ${hitOff}px——三选项「最新 ↓/需复习 ↑/字母 ↑」全在场`);
      const hl = (nodes, kw) => nodes.filter((n) => String(n.text || '').trim() === kw && String(n.backgroundColor || '').toLowerCase() === '#ff2c1b4d').length > 0;
      ctx.log('★③ 当前项紫底高亮', hl(d1.nodes, '最新 ↓') ? 'pass' : 'fail',
        hl(d1.nodes, '最新 ↓') ? '「最新 ↓」底色 #FF2C1B4D——紫字+紫底双标识' : '「最新 ↓」未见紫底（高亮未挂或装旧包）');
      // ④ 切到字母排序（三选项特有路径）：点「字母 ↑」→ 高亮跳字母行、弹层不收
      await uiClickText(serial, '字母 ↑', { exact: true, waitMs: 1000 });
      const d2 = await dumpAuditNodes(serial);
      const stayOpen = d2.text.includes('最新 ↓') && d2.text.includes('字母 ↑');
      ctx.log('★④ 切字母不收起', stayOpen ? 'pass' : 'fail', stayOpen ? '点字母后弹层仍在（连续切换保留）' : '弹层收起（点选项不收起被破坏）');
      ctx.log('★④b 高亮跟手', hl(d2.nodes, '字母 ↑') ? 'pass' : 'fail', hl(d2.nodes, '字母 ↑') ? '紫底跳至「字母 ↑」行 ✓' : '字母行未见紫底（高亮未跟手）');
      // ⑤ 点当前项反转（字母 ↑ → 字母 ↓）
      await uiClickText(serial, '字母 ↑', { exact: true, waitMs: 1000 });
      const d3 = await dumpAuditNodes(serial);
      const flipped = d3.text.includes('字母 ↓') && !d3.text.includes('字母 ↑');
      ctx.log('★⑤ 点当前项反转', flipped && hl(d3.nodes, '字母 ↓') ? 'pass' : 'fail',
        flipped ? `反转后「字母 ↓」${hl(d3.nodes, '字母 ↓') ? '且紫底在 ✓' : '但紫底丢失'}` : '未见反转（屏上仍「字母 ↑」或并存）');
      await sh(serial, `uitest uiInput click ${Math.round(pr.x1 - 300)} ${Math.round(pr.y2 + 300)}`, 15000);
      await sleep(1000);
      const d4 = await dumpLayout(serial);
      ctx.log('⑥ 遮罩关闭', !d4.text.includes('字母 ↓') ? 'pass' : 'warn', !d4.text.includes('字母 ↓') ? '点遮罩后排序层收起 ✓' : '排序项仍在屏（人工复核）');
    } },

  { id: 'KB-SEARCH-HIDE', suite: 'kbview', name: '知识库搜索栏·手机上滑收起/下滑呼回/回顶强制显示+宽屏常驻红线（0.240.0 新功能）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '搜索栏断言（UI 断言专属，PC 无 uiClick 通道）'); return; }
      await coldStart(serial);
      const nav = await navTo(serial, '知识库', ctx.log);
      if (!nav.ok) { ctx.log('★搜索栏', 'fail', '未能进入知识库页'); return; }
      const d0 = await dumpLayout(serial);
      const scrM = String((JSON.parse(d0.text).attributes || {}).bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
      const W = scrM ? +scrM[3] : 2560, H = scrM ? +scrM[4] : 1600;
      const hint = (t) => findNodeHintAll(t, '搜索标题').length;
      const base = hint(d0.text);
      ctx.log('★① 搜索栏在场', base > 0 ? 'pass' : 'fail', base > 0 ? 'placeholder「搜索标题 / 内容」在树 ✓' : '未见搜索框（hint 未捕获或未渲染）');
      const pr = findTextRect(d0.text, '+');
      const isWide = (pr ? pr.x2 + 40 : W) > 1800;
      const upSwipe = `uitest uiInput swipe ${Math.round(W / 2)} ${Math.round(H * 0.72)} ${Math.round(W / 2)} ${Math.round(H * 0.25)} 600`;
      const downSwipe = `uitest uiInput swipe ${Math.round(W / 2)} ${Math.round(H * 0.3)} ${Math.round(W / 2)} ${Math.round(H * 0.68)} 600`;
      await sh(serial, upSwipe, 20000); await sleep(700);
      await sh(serial, upSwipe, 20000); await sleep(1100);
      const d1 = await dumpLayout(serial);
      artSave('KB-SEARCH-HIDE', `after-up-${dev.id}.json`, d1.text);
      if (isWide) {
        ctx.log('★② 宽屏常驻红线', hint(d1.text) > 0 ? 'pass' : 'fail', hint(d1.text) > 0 ? '宽屏上滑后搜索栏仍在（常驻不动 ✓）' : '宽屏上滑后搜索栏消失（收放逻辑误挂宽屏——红线违规）');
      } else {
        let hid = hint(d1.text) === 0;
        if (!hid) { // 重试更长上滑（首轮滚动量可能不足或键盘态干扰）
          await sh(serial, `uitest uiInput swipe ${Math.round(W / 2)} ${Math.round(H * 0.85)} ${Math.round(W / 2)} ${Math.round(H * 0.12)} 500`, 20000); await sleep(1100);
          const d1b = await dumpLayout(serial); hid = hint(d1b.text) === 0;
        }
        ctx.log('★② 上滑收起', hid ? 'pass' : 'fail', hid ? '上滑后搜索框出树（收起 ✓）' : '上滑后搜索框仍在（未收起——收放失效或列表不足一屏无法滚动，人工复核）');
        await sh(serial, downSwipe, 20000); await sleep(1100);
        const d2 = await dumpLayout(serial);
        ctx.log('★③ 下滑呼回', hint(d2.text) > 0 ? 'pass' : 'fail', hint(d2.text) > 0 ? '下滑后搜索框回树 ✓' : '下滑后搜索框未回（呼回失效）');
        await sh(serial, downSwipe, 20000); await sleep(600);
        await sh(serial, downSwipe, 20000); await sleep(1100);
        const d3 = await dumpLayout(serial);
        ctx.log('★④ 回顶强制显示', hint(d3.text) > 0 ? 'pass' : 'fail', hint(d3.text) > 0 ? '滚回顶部搜索栏在场 ✓' : '回顶后搜索栏仍隐藏（强制显示失效）');
        // ⑤ 搜索词不清空（自洽探测：注入 A240 → 收起→呼回 → dump 回显比对；dump 不回显输入文本则 info 降级人工）
        const box = findNodeHintAll(d3.text, '搜索标题')[0];
        if (box) {
          await uiInputText(serial, box.x, box.y, 'A240');
          await sleep(700);
          const dw = await dumpLayout(serial);
          const shown0 = dw.text.includes('A240');
          await sh(serial, upSwipe, 20000); await sleep(1000);
          await sh(serial, downSwipe, 20000); await sleep(1100);
          const dr = await dumpLayout(serial);
          const shown1 = dr.text.includes('A240');
          ctx.log('⑤ 搜索词保留', shown1 ? 'pass' : (shown0 ? 'fail' : 'info'),
            shown0 ? `注入 A240 → 收起→呼回后词${shown1 ? '仍显示（不丢 ✓）' : '丢失（清空违规）'}` : 'dump 不回显输入框文本——本项人工抽查（呼回后框内词应原样在）');
        }
      }
      ctx.log('备注', 'info', '10vp 轻蹭防抖为细粒度手势（自动化无法精确注入 <10vp 位移）——保留人工验收项「轻蹭不抖动」');
    } },

  { id: 'WB-SEARCH-HIDE', suite: 'kbview', name: '单词库搜索栏·手机上滑收起/下滑呼回/回顶强制显示+宽屏常驻红线（0.240.0 新功能）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '搜索栏断言（UI 断言专属，PC 无 uiClick 通道）'); return; }
      await coldStart(serial);
      const nav = await navTo(serial, '单词库', ctx.log);
      if (!nav.ok) { ctx.log('★搜索栏', 'fail', '未能进入单词库页'); return; }
      const d0 = await dumpLayout(serial);
      const scrM = String((JSON.parse(d0.text).attributes || {}).bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
      const W = scrM ? +scrM[3] : 2560, H = scrM ? +scrM[4] : 1600;
      const hint = (t) => findNodeHintAll(t, '搜索单词').length;
      const base = hint(d0.text);
      ctx.log('★① 搜索栏在场', base > 0 ? 'pass' : 'fail', base > 0 ? 'placeholder「搜索单词 / 音标 / 释义」在树 ✓' : '未见搜索框（hint 未捕获或未渲染）');
      const pr = findTextRect(d0.text, '+');
      const isWide = (pr ? pr.x2 + 40 : W) > 1800;
      const upSwipe = `uitest uiInput swipe ${Math.round(W / 2)} ${Math.round(H * 0.72)} ${Math.round(W / 2)} ${Math.round(H * 0.25)} 600`;
      const downSwipe = `uitest uiInput swipe ${Math.round(W / 2)} ${Math.round(H * 0.3)} ${Math.round(W / 2)} ${Math.round(H * 0.68)} 600`;
      await sh(serial, upSwipe, 20000); await sleep(700);
      await sh(serial, upSwipe, 20000); await sleep(1100);
      const d1 = await dumpLayout(serial);
      artSave('WB-SEARCH-HIDE', `after-up-${dev.id}.json`, d1.text);
      if (isWide) {
        ctx.log('★② 宽屏常驻红线', hint(d1.text) > 0 ? 'pass' : 'fail', hint(d1.text) > 0 ? '宽屏上滑后搜索栏仍在（常驻不动 ✓）' : '宽屏上滑后搜索栏消失（收放逻辑误挂宽屏——红线违规）');
      } else {
        let hid = hint(d1.text) === 0;
        if (!hid) {
          await sh(serial, `uitest uiInput swipe ${Math.round(W / 2)} ${Math.round(H * 0.85)} ${Math.round(W / 2)} ${Math.round(H * 0.12)} 500`, 20000); await sleep(1100);
          const d1b = await dumpLayout(serial); hid = hint(d1b.text) === 0;
        }
        ctx.log('★② 上滑收起', hid ? 'pass' : 'fail', hid ? '上滑后搜索框出树（收起 ✓）' : '上滑后搜索框仍在（未收起——收放失效或列表不足一屏无法滚动，人工复核）');
        await sh(serial, downSwipe, 20000); await sleep(1100);
        const d2 = await dumpLayout(serial);
        ctx.log('★③ 下滑呼回', hint(d2.text) > 0 ? 'pass' : 'fail', hint(d2.text) > 0 ? '下滑后搜索框回树 ✓' : '下滑后搜索框未回（呼回失效）');
        await sh(serial, downSwipe, 20000); await sleep(600);
        await sh(serial, downSwipe, 20000); await sleep(1100);
        const d3 = await dumpLayout(serial);
        ctx.log('★④ 回顶强制显示', hint(d3.text) > 0 ? 'pass' : 'fail', hint(d3.text) > 0 ? '滚回顶部搜索栏在场 ✓' : '回顶后搜索栏仍隐藏（强制显示失效）');
        const box = findNodeHintAll(d3.text, '搜索单词')[0];
        if (box) {
          await uiInputText(serial, box.x, box.y, 'A240');
          await sleep(700);
          const dw = await dumpLayout(serial);
          const shown0 = dw.text.includes('A240');
          await sh(serial, upSwipe, 20000); await sleep(1000);
          await sh(serial, downSwipe, 20000); await sleep(1100);
          const dr = await dumpLayout(serial);
          const shown1 = dr.text.includes('A240');
          ctx.log('⑤ 搜索词保留', shown1 ? 'pass' : (shown0 ? 'fail' : 'info'),
            shown0 ? `注入 A240 → 收起→呼回后词${shown1 ? '仍显示（不丢 ✓）' : '丢失（清空违规）'}` : 'dump 不回显输入框文本——本项人工抽查（呼回后框内词应原样在）');
        }
      }
      ctx.log('备注', 'info', '10vp 轻蹭防抖为细粒度手势——保留人工验收项「轻蹭不抖动」');
    } },

  // ---------- ★ 0.274.0 桌面服务卡片（用户需求「桌面卡片测试进测试台」；切库死锁修复回归） ----------
  // 复现链（修前真机实锤）：switchPill @Builder 按值传参 active 快照冻结 + onClick !active 拦截
  // = 「只能切换一次，再也切不回」+「左上角标签不变」；叠加完成态无 pill=第二死锁。
  // 修后断言：知识卡→单词库→知识卡 三连切，每切指纹必变；完成态若现身必须带双 pill。
  { id: 'WIDGET-SWITCH', suite: 'widget', name: '切库死锁回归·知识卡→单词库→知识卡三连切每切必变+完成态pill常驻（0.274.0 修复）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '桌面卡片切库（UI 断言专属，PC 无 UI 通道）'); return; }
      // ① 回桌面
      await sh(serial, `uitest uiInput keyEvent Home`, 15000); await sleep(1800);
      // ② 卡片存在性：找 pill「单词库」；不存在→自举添加（长按图标→卡片→添加至桌面）
      let d = await dumpLayout(serial);
      if (!d.ok) { ctx.log('★切库死锁回归', 'fail', 'dumpLayout 失败（桌面不可读）'); return; }
      if (!findNodeBoundsAll(d.text, '单词库').length) {
        ctx.log('② 桌面未见 DAG 卡片', 'info', '自举添加：长按图标→卡片→添加至桌面');
        const ico = findNodeBoundsAll(d.text, 'DAGAI')[0];
        if (!ico) { ctx.log('★切库死锁回归', 'skip', '桌面未见 DAGAI 图标（在其他页）——手动滑到图标所在页再跑'); return; }
        await uiLongPress(serial, ico.x, Math.max(ico.y - 70, 50), 2600);
        const m = await dumpLayout(serial);
        const cardBtn = m.ok && m.text.includes('卡片') ? await uiClickText(serial, '卡片', { exact: true, waitMs: 2200 }) : { ok: false };
        if (!cardBtn.ok) { ctx.log('★切库死锁回归', 'skip', '长按图标未出「卡片」菜单（图标位置或长按不稳定）——手动添加卡片后重跑'); return; }
        const add = await uiClickText(serial, '添加至桌面', { exact: true, waitMs: 2500 });
        ctx.log('② 自举添加卡片', add.ok ? 'pass' : 'skip', add.ok ? '已点「添加至桌面」' : (add.err || '未找到添加按钮——手动添加后重跑'));
        await sh(serial, `uitest uiInput keyEvent Home`, 15000); await sleep(1800);
        d = await dumpLayout(serial);
        if (!d.ok || !findNodeBoundsAll(d.text, '单词库').length) { ctx.log('★切库死锁回归', 'skip', '添加后仍未见卡片 pill——手动确认卡片已上桌面再跑'); return; }
      }
      // ③ 卡片区指纹：以「单词库」pill 为锚，收集周边文本集合（title/progress/完成态文案全在内）
      const fpOf = async () => {
        const dd = await dumpLayout(serial);
        if (!dd.ok) return null;
        const anchor = findNodeBoundsAll(dd.text, '单词库')[0];
        if (!anchor) return null;
        const near = [];
        const walk = (node) => {
          if (!node || typeof node !== 'object') return;
          if (node.attributes) {
            const t = String(node.attributes.text || '').trim();
            const m = String(node.attributes.bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
            if (t && m && Math.abs((+m[2] + +m[4]) / 2 - anchor.y) < 420 && Math.abs((+m[1] + +m[3]) / 2 - anchor.x) < 620) near.push(t.slice(0, 40));
          }
          for (const k of Object.keys(node)) if (node[k] && typeof node[k] === 'object') walk(node[k]);
        };
        try { walk(JSON.parse(dd.text), false); } catch (_) { return null; }
        near.sort();
        return { fp: near.join('|'), done: /今日复习已完成|全部学完|暂无复习内容/.test(near.join('|')), pills: near.includes('单词库') && near.includes('知识卡') };
      };
      // ④ 三连切：知识卡→单词库→知识卡（首点可能幂等，断言只看后两切）
      const f1 = await (async () => { const c = await uiClickText(serial, '知识卡', { exact: true, waitMs: 2600 }); return c.ok ? await fpOf() : null; })();
      if (!f1) { ctx.log('④ 点「知识卡」pill', 'fail', 'pill 未找到或 dump 失败（卡片结构异常）'); return; }
      ctx.log('④ 点「知识卡」', 'pass', `指纹 ${f1.fp.slice(0, 60)}…`);
      artSave('WIDGET-SWITCH', `fp1-${dev.id}.json`, f1.fp);
      const c2 = await uiClickText(serial, '单词库', { exact: true, waitMs: 2600 });
      const f2 = c2.ok ? await fpOf() : null;
      if (!f2) { ctx.log('⑤ 点「单词库」pill', 'fail', 'pill 未找到或 dump 失败'); return; }
      const sw2 = f2.fp !== f1.fp;
      ctx.log('★⑤ 切回单词库生效（死锁主断言）', sw2 ? 'pass' : 'fail',
        sw2 ? `指纹已变 ${f2.fp.slice(0, 60)}…——第二切未被拦截（0.274.0 修前：active 快照冻结致此切永远锁死）`
          : `指纹与切前完全一致——切库被拦截（0.274.0 前「只能切一次」死锁复现）`);
      if (f2.done && !f2.pills) ctx.log('★完成态pill常驻', 'fail', '完成态未见「单词库/知识卡」pill——0.274.0 完成态切换入口缺失');
      if (f2.done && f2.pills) ctx.log('完成态pill常驻', 'pass', '完成态下双 pill 在场——切走入口常驻');
      const c3 = await uiClickText(serial, '知识卡', { exact: true, waitMs: 2600 });
      const f3 = c3.ok ? await fpOf() : null;
      const sw3 = f3 !== null && f2 !== null && f3.fp !== f2.fp;
      ctx.log('★⑥ 再切回知识卡（第三切）', f3 === null ? 'fail' : (sw3 ? 'pass' : 'fail'),
        f3 === null ? 'pill 未找到或 dump 失败' : (sw3 ? '指纹再变——往复切换全通（无一次性锁死）' : '指纹未变——第三切又锁死'));
      if (f3 && f3.done && !f3.pills) ctx.log('★完成态pill常驻', 'fail', '完成态未见双 pill——0.274.0 完成态切换入口缺失');
    } },

  // ---------- ★ 0.274.0 种子数据 v4 回归（知识卡 6 域新卡 + 单词 6 词；标题图链路人工抽查） ----------
  { id: 'SEED-V4', suite: 'kbview', name: '种子v4·知识库/单词库新测试数据在场（艾宾浩斯遗忘曲线等6卡+熵/Blockchain等6词；0.274.0 新功能）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '种子数据断言（UI 断言专属，PC 无 UI 通道）'); return; }
      await coldStart(serial);
      // ① 知识库：v4 新卡 6 张（最新排序插队首，首屏必见）
      const nav = await navTo(serial, '知识库', ctx.log);
      if (!nav.ok) { ctx.log('★种子v4·知识库', 'fail', '未能进入知识库页'); return; }
      const dk = await dumpLayout(serial);
      if (!dk.ok) { ctx.log('★种子v4·知识库', 'fail', 'dump 失败'); return; }
      const kHits = ['艾宾浩斯遗忘曲线', '熵增定律', '供给与需求', '英语习语', '古腾堡印刷术', '极限'].filter((t) => dk.text.includes(t));
      ctx.log('★① 知识库 v4 新卡在场', kHits.length > 0 ? 'pass' : 'fail',
        kHits.length > 0 ? `命中 ${kHits.length}/6：${kHits.join('、')}（v3→v4 seed 合并生效；标题图/内容图为视觉项——人工抽查）`
          : '首屏未见任何 v4 新卡——seed v4 未合并（检查 KNOWLEDGE_SEED_VERSION=4 与装机版本，或列表非「最新」排序）');
      // ② 单词库：v4 新词（选低误判词断言）
      await sh(serial, `uitest uiInput keyEvent Back`, 15000); await sleep(1500);
      const nav2 = await navTo(serial, '单词库', ctx.log);
      if (!nav2.ok) { ctx.log('★② 单词库 v4 新词', 'fail', '未能进入单词库页'); return; }
      const dw = await dumpLayout(serial);
      if (!dw.ok) { ctx.log('★② 单词库 v4 新词', 'fail', 'dump 失败'); return; }
      const wHits = ['Blockchain', '深度学习', 'Cache', 'Application Programming Interface'].filter((t) => dw.text.includes(t));
      ctx.log('★② 单词库 v4 新词在场', wHits.length > 0 ? 'pass' : 'fail',
        wHits.length > 0 ? `命中 ${wHits.length}/4：${wHits.join('、')}` : '首屏未见 v4 新词——WORD_SEED_VERSION=4 未生效或排序不符（下滑人工确认）');
    } },

  // ---------- 功能⑤ 云端语音朗读 API（★ 0.232.0；用户规则：没填 Key 的设备不测） ----------
  { id: 'TTS-API', suite: 'tts', name: '云端TTS·openspeech 直打验证（读设备已填配置；未填 Key=skip；55000000 自动官方音色回退）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      // ① 读设备持久化 TTS 配置（api-config-v3 内嵌 JSON）
      const key = await prefField(serial, 'audioKey');
      const model = await prefField(serial, 'audioModel');
      const voice = await prefField(serial, 'audioVoice');
      if (!key.found || key.value.length < 8) {
        ctx.log('★云端 TTS', 'skip', '设备未填写音频 API Key——按用户规则不测（填过 Key 的设备才验证云端链路；未配置时 App 自动走本机语音）');
        return;
      }
      ctx.log('① 设备配置读取', 'pass', `audioKey=${key.value.slice(0, 6)}…（raw：${key.raw.slice(0, 80)}）audioModel=${model.value || '(空)'} audioVoice=${voice.value || '(空)'}`);
      if (model.value.length === 0) {
        ctx.log('★云端 TTS', 'skip', 'audioModel 未填——App configured() 判未配置（朗读走本机语音），无云端链路可测');
        return;
      }
      // ② 服务端直打 openspeech（与 App CloudTtsEngine 同协议同回退——2026-10-13 curl 实证）
      const r = await probeCloudTts(key.value, model.value, voice.value.length > 0 ? voice.value : 'S_bv8H32Sg2');
      ctx.log(`★云端合成${r.fallback ? '（合成音色资源未开通→自动回退官方音色——控制台开通后自动启用）' : ''}`,
        r.ok ? 'pass' : 'fail',
        `voice=${r.usedVoice} ${r.ok ? 'HTTP 200 + code=0 + 音频数据（App 朗读云端链路可用）' : '响应：' + String(r.body).slice(0, 140)}`);
    } },

  // ---------- 功能③ ArkUI Test（设备内真断言，hypium；工程 entry/src/ohosTest） ----------
  { id: 'ARKUI-TEST', suite: 'arkui', name: 'ArkUI Test 设备内真断言（hypium 2 条）', semi: false, scope: 'each', timeoutMs: 900000,
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      // ★ 0.241.0.10：复用前比对测试包 versionCode 与工程当前值（现读 app.json5，防服务跨发版未重启用旧期望）——
      //   app 发版递增 versionCode 后旧测试包必装不上（9568263），此前 0.235.0/0.237.1/0.237.2 三踩全靠人工重编
      const curVc = readAppVersionCode() ?? EXPECTED_VC;
      let testHap = pickTestHap();
      const hapVc = testHap ? testHapVersionCode() : null;
      if (testHap && hapVc === curVc) {
        ctx.log('① 测试包已存在', 'pass', testHap.split('/').pop() + `（复用已编译测试包，versionCode=${hapVc} 与工程一致）`);
      } else {
        ctx.log('① 编译测试包', 'info', testHap ? `已编译测试包 versionCode=${hapVc} ≠ 工程当前 ${curVc}（app 已发版）——9568263 版本不匹配防线，强制重编` : '首次需编译 ohosTest（可能数分钟）…');
        const b = await buildTestHap();
        if (!b.ok) { ctx.log('① 测试包编译', 'fail', b.err + (b.log ? ' | ' + String(b.log).split('\n').slice(-3).join(' ').slice(0, 300) : '')); return; }
        testHap = b.hap; ctx.log('① 测试包编译', 'pass', testHap.split('/').pop() + `（versionCode=${curVc}）`);
      }
      // ★ 0.241.0.10：设备侧预检——设备主应用版本落后于工程时，测试包（=工程版本）必装不上（9568263）；
      //   红字指路先【装机】升级主应用，不硬撞 hdc 报错（bmVersionCode=VERSION 用例已验证通道）
      const dv = await bmVersionCode(serial);
      if (!dv.ok || dv.code !== curVc) {
        ctx.log('② 测试包安装到 ' + dev.id, 'fail', !dv.ok
          ? '设备上未查询到主应用 versionCode（bm dump 失败）——请先【装机】装好主应用再跑本用例'
          : `设备应用 versionCode=${dv.code} ≠ 工程 ${curVc}——测试包版本随工程走，请先【装机】升级设备主应用后重跑本用例`);
        return;
      }
      const ins = await hdcSpawn(serial, ['install', '-r', testHap], 180000);
      const insTxt = (ins.out + ins.err).trim();
      const insOk = /successfully/.test(insTxt);
      const hintVc = /9568263/.test(insTxt) ? '【9568263=测试包与设备应用 versionCode 不一致——app 发版后测试包须重编】' : '';
      ctx.log('② 测试包安装到 ' + dev.id, insOk ? 'pass' : 'fail', (insTxt.slice(0, 200) + ' ' + hintVc).trim());
      if (!insOk) return;
      ctx.log('③ 执行 aa test', 'info', '-m entry_test · hypium runner');
      const out = await aaTestRun(serial);
      const s = summarizeAaTest(out);
      ctx.log('★ArkUI Test 结果', s.level, s.note + ' | 输出尾：' + String(out).trim().split('\n').slice(-4).join(' / ').slice(0, 400));
    } }
];

// ---------- 矩阵执行（设备主序串行：同一设备用例有先后依赖） ----------
let running = false;
let abortRequested = false; // ★ 0.229.20「停止测试」请求——当前步骤跑完即停（不硬杀正在执行的 hdc 命令）
function startRun(deviceIds, caseIds) {
  if (AF.state !== 'idle') return { error: '自动修复闭环正在运行（' + AF.phase + '）——等它结束或先停止闭环' }; // ★ 0.243.0.1 互斥
  if (running) return { error: '已有测试在跑（页面刷新/重开不会中断后台执行——等它跑完，或点【停止测试】）' };
  const devs = CFG.devices.filter((d) => deviceIds.includes(d.id));
  const cases = CASES.filter((c) => c.builtin || caseIds.includes(c.id));
  curRun = { runId: RUN_ID(), startedAt: now(), env: { versionCode: EXPECTED_VC, node: process.version },
    plan: { devices: devs.map((d) => d.id), cases: cases.map((c) => c.id) }, runs: [], summary: {} };
  running = true;
  // 后台执行（HTTP 立即返回 runId，进度走 SSE——检查点等待不阻塞请求）
  executeMatrix(devs, cases).catch((e) => {
    try { sseSend({ type: 'run-end', runId: curRun.runId, summary: { error: String(e) } }); } catch (_) {}
    running = false;
  });
  return { runId: curRun.runId };
}
async function executeMatrix(devs, cases) {
  try {
    sseSend({ type: 'run-start', runId: curRun.runId, plan: curRun.plan });
    outer: for (const dev of devs) {
      const devCases = cases.filter((c) => c.scope === 'each');
      for (const c of devCases) {
        if (abortRequested) { sseSend({ type: 'step', runId: curRun.runId, case: c.id, step: { name: '用户请求中止', status: 'skip', detail: '用户点了【停止测试】——剩余用例全部跳过', ms: 0 } }); break outer; }
        sseSend({ type: 'case-start', runId: curRun.runId, device: dev.id, case: c.id, name: c.name });
        const r = await runCase([dev], c);
        r.device = dev.id;
        curRun.runs.push(r);
        sseSend({ type: 'case-end', runId: curRun.runId, device: dev.id, result: r });
      }
    }
    for (const c of cases.filter((x) => x.scope === 'cross')) {
      if (abortRequested) break;
      sseSend({ type: 'case-start', runId: curRun.runId, device: '跨端', case: c.id, name: c.name });
      const r = await runCase(devs, c);
      r.device = 'cross';
      curRun.runs.push(r);
      sseSend({ type: 'case-end', runId: curRun.runId, device: 'cross', result: r });
    }
  } finally {
    curRun.endedAt = now();
    const cnt = (s) => curRun.runs.filter((r) => r.status === s).length;
    curRun.summary = { pass: cnt('pass'), fail: cnt('fail'), warn: cnt('warn'), skip: cnt('skip'), total: curRun.runs.length, aborted: abortRequested };
    saveResults(curRun);
    sseSend({ type: 'run-end', runId: curRun.runId, summary: curRun.summary });
    running = false;
    abortRequested = false;
  }
  return { runId: curRun.runId };
}

// ---------- results v2 持久化（兼容一期 v1 数据） ----------
function loadResults() {
  if (!fs.existsSync(RESULTS_PATH)) return { schemaVersion: 2, history: [] };
  try {
    const j = JSON.parse(fs.readFileSync(RESULTS_PATH, 'utf8'));
    if (j.schemaVersion === 2) return j;
    return { schemaVersion: 2, legacy: j, history: [] };
  } catch (e) { return { schemaVersion: 2, legacyError: String(e), history: [] }; }
}
function saveResults(run) {
  const all = loadResults();
  all.history.push(run);
  while (all.history.length > CFG.historyCap) all.history.shift();
  fs.writeFileSync(RESULTS_PATH, JSON.stringify(all, null, 2));
}

// ---------- 桌面交付物同步（唯一入口：测试台.html 双击即用） ----------
function syncDesktop() {
  try {
    if (!fs.existsSync(CFG.desktopDir)) return { ok: false, reason: '桌面目录不存在' };
    const html = fs.readFileSync(path.join(ROOT, 'public', 'index.html'), 'utf8');
    const stamped = html.replace('</title>', ` · ${VERSION}</title>`)
      .replace('</body>', `\n<!-- testing-console ${VERSION} 同源副本 ${now()} 生成，正本 testing/console/public/index.html，勿直接改本副本 -->\n</body>`);
    fs.writeFileSync(path.join(CFG.desktopDir, '测试台.html'), stamped);
    const launcher = path.join(ROOT, '启动测试台.sh');
    if (fs.existsSync(launcher)) {
      fs.copyFileSync(launcher, path.join(CFG.desktopDir, '启动测试台.sh'));
      try { fs.chmodSync(path.join(CFG.desktopDir, '启动测试台.sh'), 0o755); } catch (_) { /* 权限位尽力设置 */ }
    }
    return { ok: true };
  } catch (e) { return { ok: false, reason: String(e) }; }
}

// ============================================================
// ★ 0.243.0.1 自动修复闭环（autofix：测试 → CLI agent 改码 → 编译 → 装机 → 重测；全案 docs/0.165+/0.243.0）
//   Phase 0 已实锤（2026-10-16）：deveco run "<任务>" --dir <PROJECT> --dangerously-skip-permissions
//   = 非交互一次性执行、自动退出、退出码可判（类 claude -p / codex exec）。
//   止损熔断五判据（写死服务端，不靠 CLI 自觉——方案 §4.2）：
//     ① 同一 bug 连续 maxRounds(2) 轮修复后仍失败 → 熔断+死胡同报告（五部分求援定式）落桌面
//     ② 本轮 git diff 为空（CLI 没改成任何东西）= 死轮，计入熔断连击
//     ③ diff 触碰红线清单（config.autofix.redlineFiles）→ 回滚当轮+熔断转人工
//     ④ CLI 进程超时 600s → 强杀+判死轮
//     ⑤ 编译失败连续 2 轮 → 熔断（编译报错喂给下一轮任务包，两轮机会）
//   成败判定一律以 git diff + 编译 + 重跑测试为准（不信 CLI 自述）。
// ============================================================
const AF = {
  state: 'idle', runId: null, round: 0, phase: '', devices: [], suites: [],
  bootSnap: null, abort: false, startedAt: 0, rounds: [], result: null,
  lastHealth: null, healthAt: 0, cliProc: null, stream: undefined,
};
function afSend(phase, text, extra) {
  AF.phase = phase;
  sseSend({ type: 'autofix', runId: AF.runId, phase, round: AF.round, text, ...(extra || {}) });
}
function afStatusLite() {
  return { state: AF.state, runId: AF.runId, round: AF.round, phase: AF.phase, result: AF.result, startedAt: AF.startedAt, stream: afUseStream(),
    rounds: AF.rounds.map((r) => ({ round: r.round, files: r.files, outcome: r.outcome, summary: r.summary })) };
}
// ---------- git 工具（打点/回滚/diff；子命令白名单——安全模型从「只 spawn hdc」扩展出 git，仅限以下只读+快照操作） ----------
const GIT_SUBCMDS = new Set(['rev-parse', 'add', 'commit', 'status', 'diff', 'reset', 'clean']);
function git(args, timeoutMs = 30000) {
  if (!GIT_SUBCMDS.has(args[0])) return Promise.resolve({ code: -1, out: '', err: 'git subcommand not allowed: ' + args[0] });
  // commit 身份=仓库默认（DJ_ShangGanLing）；显式带 -c 兜底防环境缺省（勿用 autofix@local——codearts pre-receive 拒非法邮箱作者，0.243.0.1 实锤）
  if (args[0] === 'commit') args = ['-c', 'user.name=DJ_ShangGanLing', '-c', 'user.email=1725912449@qq.com', ...args];
  return runCmd('git', args, PROJECT, timeoutMs);
}
async function gitAvailable() {
  const r = await git(['rev-parse', 'HEAD']);
  return { ok: r.code === 0, head: r.out.trim().slice(0, 12), err: r.out.slice(0, 120) };
}
// 打点快照：把当前工作区全部改动 add -A + commit（保护用户未提交工作=入历史不丢）；无可提交则只取 HEAD
async function gitSnap(label) {
  const st = await git(['status', '--porcelain']);
  if (!st.out.trim()) { const h = await git(['rev-parse', 'HEAD']); return { hash: h.out.trim(), empty: true }; }
  await git(['add', '-A']);
  const c = await git(['commit', '-m', label]);
  const h = await git(['rev-parse', 'HEAD']);
  return { hash: h.out.trim(), empty: false, commitOk: c.code === 0, commitOut: (c.out || '').slice(0, 200) };
}
// 当前改动文件（含新增/删除/未跟踪——porcelain 全态，比 git diff --name-only 全）
async function gitChangedFiles() {
  const r = await git(['status', '--porcelain']);
  return r.out.split('\n').map((l) => l.slice(3).trim()).filter(Boolean);
}
// 回滚到指定快照：reset --hard + clean -fd（clean 不带 -x=不碰 ignored 文件，rawfile/config.json 等本地密钥配置安全）
async function gitRollback(hash) {
  const a = await git(['reset', '--hard', hash]);
  const b = await git(['clean', '-fd']);
  return { ok: a.code === 0, out: (a.out + b.out).slice(0, 200) };
}
// 红线匹配：目录前缀（以 / 结尾）/ 精确文件 / 尾部 * 通配
function afRedlineHit(files) {
  const rl = (CFG.autofix && CFG.autofix.redlineFiles) || [];
  const hits = [];
  for (const f of files) {
    for (const r of rl) {
      let m = false;
      if (r.endsWith('/')) m = f.startsWith(r);
      else if (r.includes('*')) m = new RegExp('^' + r.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '[^/]*') + '$').test(f);
      else m = f === r;
      if (m) { hits.push(f + '（红线：' + r + '）'); break; }
    }
  }
  return hits;
}
// ★ 0.243.0.2 红线内容级校验（持久化 key 禁改铁律自动化）：diff 删除/修改行中出现已知
//   PersistenceV2/AppStorageV2 key 字符串（单/双引号形态）= 命中——防 CLI 换 key 等于毁数据
//   （0.185/0.224.1 两次实锤：key 一改盘值即空）。多文件 diff 整体逐行扫描。
function afRedlineKeysHit(diffOut) {
  const keys = (CFG.autofix && CFG.autofix.redlineKeys) || [];
  if (!keys.length || !diffOut) return [];
  const hits = [];
  for (const line of String(diffOut).split('\n')) {
    if (line.startsWith('---') || line.startsWith('+++')) continue;
    if (!line.startsWith('-')) continue; // 只看删除/修改行（- 侧）；新增行改不回旧 key 的数据
    for (const k of keys) {
      if (line.includes("'" + k + "'") || line.includes('"' + k + '"')) {
        hits.push(k + '（持久化 key 出现在删除/修改行：' + line.slice(0, 90) + '）');
        break;
      }
    }
  }
  return [...new Set(hits)];
}
// ---------- ★ 0.243.0.2 非流式适配代理（stream terminator proxy；救生艇资产，默认关闭） ----------
// 背景实锤（2026-10-16 侦察）：deveco 0.2.3 无非流式开关（OpenAI/Anthropic 适配器 stream:!0 硬编码），
// CLI×阿里 token 计划网关流式 SSE 间歇性 JSON 截断（一期卡点；截断点实测=响应尾 usage.prompt_tokens_details 处）。
// ★ 治本=闭环切官方通道：autofix.model 默认 deveco/GLM-5.3——本期实测 120 字长回复+两轮 Read 工具任务
//   全绿零截断（官方网关无此缺陷；0.243.0.1 只试了阿里通道下换模型，漏了官方通道这一正解）。
// ★ 本代理=救生艇资产（proxy.enabled=true 才挂载，默认 false）：CLI 的 provider baseURL 若被指到本代理，
//   代理把「stream:true」改写为「stream:false」发给上游网关，等模型完整生成拿到整包 JSON，
//   再在本地拼装成标准 OpenAI SSE 流回给 CLI——环回收流零截断，物理绕开上游流式缺陷。
// ⚠️ 实测局限（如实入档，防后人踩坑）：deveco.jsonc 的 provider 覆盖对「已认证内置 provider」三形态
//   （options.baseURL / api 字符串 / 完整重定义）均不生效（auth+models.dev 定义短路 config 覆盖）；
//   DEVECO_CONFIG_DIR 环境变量不加载配置（model 标记实证）。打通需「全新自定义 provider+auth 复制」
//   或「项目插件 catalog.transform 改 api.url」——未投入，转发/拼装基础设施保留待用。
function afUseStream() {
  const af = CFG.autofix || {};
  return AF.stream !== undefined ? AF.stream : (af.stream !== undefined ? !!af.stream : false);
}
function afProxyWanted() {
  const af = CFG.autofix || {};
  return !!(af.proxy && af.proxy.enabled === true) && !afUseStream();
}
const AF_PROJ_DEVECO = path.join(PROJECT, '.deveco');
function afProxyCfg() {
  const af = CFG.autofix || {};
  return { host: '127.0.0.1', port: 8989, providerId: 'alibaba-token-plan-cn', upstream: '', model: '', enabled: false, ...(af.proxy || {}) };
}
// 项目级 .deveco/deveco.jsonc 动态挂载/卸载（★ 实测唯一生效的配置注入通道：项目级加载实证 model 标记可生效；
//   DEVECO_CONFIG_DIR 无效）。仅 proxy.enabled=true 时使用；挂载窗口=CLI 运行期，退出即删配置文件
//   （目录可能残留 CLI 自动安装的 node_modules——已入 .gitignore 不污染 git）
function afMountProjConfig() {
  try {
    const pc = afProxyCfg();
    fs.mkdirSync(AF_PROJ_DEVECO, { recursive: true });
    const base = 'http://' + pc.host + ':' + pc.port + String(new URL(pc.upstream).pathname).replace(/\/$/, '');
    const cfg = { $schema: 'https://opencode.ai/config.json', provider: {} };
    cfg.provider[pc.providerId] = { options: { baseURL: base } };
    fs.writeFileSync(path.join(AF_PROJ_DEVECO, 'deveco.jsonc'), JSON.stringify(cfg, null, 2));
    return { ok: true, baseURL: base };
  } catch (e) { return { ok: false, err: String(e) }; }
}
function afUnmountProjConfig() {
  try { fs.unlinkSync(path.join(AF_PROJ_DEVECO, 'deveco.jsonc')); return true; } catch (_) { return false; }
}
// 把上游非流式整包 JSON 拼装成标准 OpenAI SSE 流（role→reasoning→content→tool_calls→finish→usage→[DONE]）
function afSseFromFull(obj) {
  const chunk = (delta, finish, extra) => 'data: ' + JSON.stringify({
    id: obj.id || 'afproxy', object: 'chat.completion.chunk', created: obj.created || Math.floor(Date.now() / 1000),
    model: obj.model || '', choices: finish === undefined && extra === 'usage' ? [] : [{ index: 0, delta, finish_reason: finish === undefined ? null : finish }],
    ...(extra === 'usage' ? { usage: obj.usage } : {}),
  }) + '\n\n';
  const out = [];
  const msg = obj.choices && obj.choices[0] && obj.choices[0].message || {};
  const fin = (obj.choices && obj.choices[0] && obj.choices[0].finish_reason) || 'stop';
  out.push(chunk({ role: 'assistant' }));
  if (msg.reasoning_content) out.push(chunk({ reasoning_content: String(msg.reasoning_content) }));
  if (msg.content) {
    const c = String(msg.content);
    for (let i = 0; i < c.length; i += 4096) out.push(chunk({ content: c.slice(i, i + 4096) }));
  }
  if (Array.isArray(msg.tool_calls)) {
    msg.tool_calls.forEach((tc, i) => {
      out.push(chunk({ tool_calls: [{ index: tc.index ?? i, id: tc.id, type: 'function', function: { name: tc.function && tc.function.name, arguments: (tc.function && tc.function.arguments) || '' } }] }));
    });
  }
  out.push(chunk({}, fin));
  if (obj.usage) out.push(chunk({}, undefined, 'usage'));
  out.push('data: [DONE]\n\n');
  return out.join('');
}
const AF_PROXY = { server: null, port: 0, stats: { n: 0, bytes: 0, errs: 0 } };
async function afProxyEnsure() {
  if (AF_PROXY.server) return { ok: true, port: AF_PROXY.port };
  const pc = afProxyCfg();
  return new Promise((resolve) => {
    const https = require('https');
    const up = new URL(pc.upstream);
    const srv = http.createServer((req, res) => {
      const chunks = [];
      req.on('data', (d) => chunks.push(d));
      req.on('end', () => {
        const bodyRaw = Buffer.concat(chunks);
        let bodyJson = null;
        try { bodyJson = JSON.parse(bodyRaw.toString('utf8')); } catch (_) { /* 非体 JSON 原样透传 */ }
        const fwdBody = bodyJson ? Buffer.from(JSON.stringify({ ...bodyJson, stream: false, stream_options: undefined })) : bodyRaw;
        const fwd = https.request({
          hostname: up.hostname, port: up.port || 443, path: req.url, method: req.method,
          headers: { ...req.headers, host: up.host, 'content-length': String(fwdBody.length) },
        }, (ur) => {
          if (ur.statusCode !== 200) {
            AF_PROXY.stats.errs++;
            res.writeHead(ur.statusCode, { 'content-type': ur.headers['content-type'] || 'application/json' });
            ur.pipe(res); // 上游真实错误原样透传（SDK 可读出错误信息）
            return;
          }
          const cs = [];
          ur.on('data', (d) => cs.push(d));
          ur.on('end', () => {
            try {
              const full = JSON.parse(Buffer.concat(cs).toString('utf8'));
              const sse = afSseFromFull(full);
              AF_PROXY.stats.n++; AF_PROXY.stats.bytes += sse.length;
              res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache', 'connection': 'keep-alive' });
              res.end(sse);
              if (AF.state === 'running') afSend(AF.phase === 'fix' ? 'fix' : 'health', '[代理] 非流式整包 ' + sse.length + ' 字回拼 SSE 完成（累计 ' + AF_PROXY.stats.n + ' 次）');
            } catch (e) {
              AF_PROXY.stats.errs++;
              res.writeHead(502, { 'content-type': 'application/json' });
              res.end(JSON.stringify({ error: { message: 'afproxy 拼装失败：' + String(e) } }));
            }
          });
        });
        fwd.on('error', (e) => {
          AF_PROXY.stats.errs++;
          try { res.writeHead(502, { 'content-type': 'application/json' }); res.end(JSON.stringify({ error: { message: 'afproxy 转发失败：' + String(e) } })); } catch (_) { /* 已回 */ }
        });
        fwd.end(fwdBody);
      });
    });
    srv.on('error', (e) => { AF_PROXY.server = null; resolve({ ok: false, err: '代理监听失败（' + pc.host + ':' + pc.port + '）：' + String(e) }); });
    srv.listen(pc.port, pc.host, () => { AF_PROXY.server = srv; AF_PROXY.port = pc.port; AF_PROXY.stats = { n: 0, bytes: 0, errs: 0 }; resolve({ ok: true, port: pc.port }); });
  });
}
// ---------- CLI headless 调用（deveco run；spawn 数组参数；超时强杀） ----------
function stripAnsi(s) { return String(s || '').replace(/\x1b\[[0-9;]*m/g, ''); }
async function afRunCli(prompt, timeoutMs) {
  return new Promise(async (resolve) => {
    try {
    const af = CFG.autofix || {};
    if (!af.cliCmd) return resolve({ code: -1, out: '未配置 autofix.cliCmd' });
    const env = { ...process.env };
    if (CFG.localBuild && CFG.localBuild.nodeBin) env.PATH = CFG.localBuild.nodeBin + path.delimiter + (env.PATH || '');
    const args = ['run', prompt, '--dir', PROJECT, '--dangerously-skip-permissions'];
    // ★ 0.243.0.2 闭环模型通道：autofix.model 默认 deveco/GLM-5.3（官方通道实测无流式截断——治本；
    //   阿里 token 计划网关 glm-5.3 有间歇性 JSON 截断，0.243.0.1 卡点的网关侧根因）。空=不传 -m（CLI 默认模型）
    const am = String(af.model || '').trim();
    if (am) args.splice(2, 0, '-m', am);
    // ★ 救生艇（默认关闭）：proxy.enabled=true 且 stream=false 时挂载项目级 .deveco 配置 + 本地非流式代理
    //   （provider 覆盖通道实测未打通，见模块头注释——代理监听与转发基础设施保留）
    let mounted = false;
    if (afProxyWanted()) {
      const pe = await afProxyEnsure();
      if (!pe.ok) return resolve({ code: -1, out: '非流式代理不可用：' + pe.err });
      const mc = afMountProjConfig();
      if (!mc.ok) return resolve({ code: -1, out: '挂载 .deveco 配置失败：' + mc.err });
      mounted = true;
    }
    let p = null;
    try {
      // ★ stdin 必须 ignore：deveco 真身（bun 二进制）对「开放的空 pipe stdin」会阻塞等待（实测挂死零输出，spawn
      //   timeout 杀掉才现形 close(null)）；bash 下 stdin=TTY/EOF 均正常——node spawn 场景显式断开 stdin 即通
      p = spawn(af.cliCmd, args, { cwd: PROJECT, timeout: timeoutMs, env, stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (e) {
      if (mounted) afUnmountProjConfig();
      return resolve({ code: -1, out: 'afRunCli spawn 异常：' + String(e) });
    }
    AF.cliProc = p;
    let out = '';
    // ★ 0.243.0.2：4MB 上限（原 2MB）——长输出/多轮工具任务防截尾丢崩特征
    const push = (d) => { out += d.toString(); if (out.length > 4 * 1024 * 1024) out = out.slice(-2 * 1024 * 1024); };
    p.stdout.on('data', push); p.stderr.on('data', push);
    p.on('close', (code) => { AF.cliProc = null; if (mounted) afUnmountProjConfig(); resolve({ code: code ?? -1, out, timedOut: code === null }); });
    p.on('error', (e) => { AF.cliProc = null; if (mounted) afUnmountProjConfig(); resolve({ code: -1, out: String(e) }); });
    } catch (e) { resolve({ code: -1, out: 'afRunCli 异常：' + String(e) }); }
  });
}
// ★ 0.243.0.1 CLI 重试封装 / ★ 0.243.0.2 三类异常分策重试：
//   网络异常（连接拒绝/超时/DNS/socket 复位）→ 间隔 5s 重试 2 次（网络抖动自愈）
//   JSON 解析失败（流式截断特征——非流式代理后应消失，保底）→ 间隔 3s 重试 2 次
//   其他（真实任务失败/CLI 退出非零）→ 不重试，交死轮判定（重试只会烧时间）
const AF_NET_FAIL = /ECONNREFUSED|ETIMEDOUT|ENOTFOUND|ECONNRESET|EAI_AGAIN|socket hang up|fetch failed|ECONNABORTED/i;
const AF_JSON_FAIL = /JSON parsing failed|JSON Parse error|JSON\.parse|Unterminated string|Unexpected EOF|Unexpected end of/i;
function afClassifyCliFail(out) {
  const s = String(out || '');
  if (AF_NET_FAIL.test(s)) return 'network';
  if (AF_JSON_FAIL.test(s)) return 'json';
  return 'other';
}
async function afRunCliRetry(prompt, timeoutMs, retries) {
  let last = { code: -1, out: '' };
  const maxByKind = { network: 2, json: 2, other: 0 };
  let kind = null, tried = 0;
  for (let i = 0; ; i++) {
    last = await afRunCli(prompt, timeoutMs);
    if (last.code === 0 && !AF_JSON_FAIL.test(last.out)) return last;
    kind = afClassifyCliFail(last.out);
    tried = i;
    const max = maxByKind[kind];
    if (tried >= max) {
      afSend('fix', 'CLI 调用失败（' + (kind === 'network' ? '网络异常' : kind === 'json' ? 'JSON 解析失败（流式截断特征）' : '任务失败（exit ' + last.code + '）') + '，' + (max > 0 ? '重试用尽' : '按策略不重试') + '）：' + stripAnsi(last.out).slice(-100));
      return last;
    }
    afSend('fix', 'CLI 调用异常（' + (kind === 'network' ? '网络异常' : 'JSON 解析失败（流式截断嫌疑）') + '，重试 ' + (tried + 1) + '/' + max + '）：' + stripAnsi(last.out).slice(-100));
    await sleep(kind === 'network' ? 5000 : 3000);
  }
}
// ---------- autofix 跑测（复用 runCase/saveResults/artifacts；与手动跑测共用 running 锁互斥） ----------
async function afRunTests(tag) {
  const devs = CFG.devices.filter((d) => AF.devices.includes(d.id));
  const cases = CASES.filter((c) => AF.suites.includes(c.suite) || c.builtin);
  curRun = { runId: AF.runId + '-' + tag, startedAt: now(), env: { versionCode: EXPECTED_VC, node: process.version, autofix: true },
    plan: { devices: devs.map((d) => d.id), cases: cases.map((c) => c.id) }, runs: [], summary: {} };
  running = true;
  outer: for (const dev of devs) {
    for (const c of cases.filter((x) => x.scope === 'each')) {
      if (AF.abort || abortRequested) break outer;
      sseSend({ type: 'case-start', runId: curRun.runId, device: dev.id, case: c.id, name: c.name });
      const r = await runCase([dev], c);
      r.device = dev.id; curRun.runs.push(r);
      sseSend({ type: 'case-end', runId: curRun.runId, device: dev.id, result: r });
      afSend('test', (r.status === 'pass' ? '✓' : r.status === 'fail' ? '✗' : '⚠') + ' ' + c.id + ' @ ' + dev.label + '（' + r.status + '）');
    }
  }
  for (const c of cases.filter((x) => x.scope === 'cross')) {
    if (AF.abort || abortRequested) break;
    sseSend({ type: 'case-start', runId: curRun.runId, device: '跨端', case: c.id, name: c.name });
    const r = await runCase(devs, c);
    r.device = 'cross'; curRun.runs.push(r);
    sseSend({ type: 'case-end', runId: curRun.runId, device: 'cross', result: r });
    afSend('test', (r.status === 'pass' ? '✓' : r.status === 'fail' ? '✗' : '⚠') + ' ' + c.id + '（跨端·' + r.status + '）');
  }
  curRun.endedAt = now();
  const cnt = (s) => curRun.runs.filter((r) => r.status === s).length;
  curRun.summary = { pass: cnt('pass'), fail: cnt('fail'), warn: cnt('warn'), skip: cnt('skip'), total: curRun.runs.length, aborted: !!(AF.abort || abortRequested) };
  saveResults(curRun);
  running = false;
  const fails = curRun.runs.filter((r) => r.status === 'fail').map((r) => ({ case: r.case, name: r.name, device: r.device, steps: r.steps.filter((s) => s.status === 'fail') }));
  return { summary: curRun.summary, fails };
}
// ---------- 修复任务包（喂 CLI 的完整上下文：失败详情+红线禁令+止损令+基线三读） ----------
function afBuildTask(testRes, buildLog, round, note) {
  const af = CFG.autofix || {};
  const L = [];
  L.push('你是 DAG AI Chat（鸿蒙 ArkUI V2）项目的自动修复 agent，闭环第 ' + round + ' 轮。工作目录即项目根。');
  L.push('【强制第一步】先读 project_rule.md、AGENTS.md、MEMORY.md（只读最新迭代条目）、docs/CONTEXT_MANAGEMENT.md 对齐项目基线，再动手。');
  if (note) L.push('【上轮情况】' + note);
  L.push('【失败用例】（只修这些，修完要能通过对应断言）');
  for (const f of testRes.fails) {
    const dev = CFG.devices.find((d) => d.id === f.device);
    L.push('◆ ' + f.case + '「' + f.name + '」@' + (dev ? dev.label : f.device));
    for (const s of f.steps.slice(0, 8)) L.push('   ✗ ' + s.name + '：' + String(s.detail || '').slice(0, 300));
  }
  if (buildLog) L.push('【上轮编译报错（优先修编译错误）】\n' + String(buildLog).slice(-2500));
  L.push('【硬性禁令（违反=当轮自动回滚+熔断转人工）】');
  L.push('- 禁改红线文件：' + ((af.redlineFiles || []).join('、')));
  L.push('- 禁改任何 PersistenceV2/AppStorageV2 的 key 字符串；数据 Schema 字段只许尾部追加+默认值，禁止改名/改类型/删除');
  L.push('- 禁止执行 git commit/push（打点与回滚由闭环负责）；禁止重构；改动控制在 2 个文件以内（≥3 文件=超出原始 bug 范围，判死轮）');
  L.push('【止损令】只修上面列出的失败；修不动就保持原样，输出你认为的原因，不要硬凑改法。');
  L.push('【输出要求】末尾输出：修改了哪些文件 + 每个文件一句话原因。');
  return L.join('\n');
}
// ---------- 报告生成（绿报告 / 死胡同报告五部分，均落 desktopDir 桌面） ----------
function afWriteReport(name, text) {
  try {
    const p = path.join(CFG.desktopDir, name);
    fs.writeFileSync(p, text);
    return p;
  } catch (e) { return '写入失败:' + String(e); }
}
function afGreenReport(round, testRes) {
  const files = [...new Set(AF.rounds.flatMap((r) => r.files || []))];
  const L = [];
  L.push('# 自动修复报告 ' + AF.runId + '（全绿收工）');
  L.push('');
  L.push('- 应用版本：' + (readAppVersionName() || '?') + '（versionCode ' + EXPECTED_VC + '）· 工具 ' + VERSION);
  L.push('- 设备：' + AF.devices.join('、') + ' · 套件：' + AF.suites.join('、'));
  L.push('- 修复轮次：' + round + ' · 起止：' + new Date(AF.startedAt).toLocaleString('zh-CN') + ' → ' + new Date().toLocaleString('zh-CN'));
  L.push('- 最终测试：✓' + testRes.summary.pass + ' 通过 / ✗' + testRes.summary.fail + ' 失败 / ⚠' + testRes.summary.warn + ' 警告 / −' + testRes.summary.skip + ' 跳过');
  L.push('- 修改文件（git 打点链可回滚）：');
  for (const f of files) L.push('  · ' + f);
  L.push('');
  L.push('每轮实录：');
  for (const r of AF.rounds) L.push('  第 ' + r.round + ' 轮：' + (r.outcome || '') + (r.files && r.files.length ? '（改 ' + r.files.join('、') + '）' : ''));
  L.push('');
  L.push('> 工作区已留修复成果（含 git 快照），请验收；不满意可 git reset 回退。');
  return L.join('\n');
}
function afDeadEndReport(reason, lastCliOut, lastBuildLog) {
  const files = [...new Set(AF.rounds.flatMap((r) => r.files || []))];
  const L = [];
  L.push('# 死胡同报告 ' + AF.runId + '（自动修复闭环熔断，求援外发用）');
  L.push('');
  L.push('## ① 环境与现象');
  L.push('- 应用：' + (readAppVersionName() || '?') + '（versionCode ' + EXPECTED_VC + '，bundle ' + CFG.bundle + '）· 设备：' + AF.devices.join('、') + ' · 套件：' + AF.suites.join('、'));
  L.push('- 熔断原因：**' + reason + '**');
  const lastRes = AF.rounds.length ? AF.rounds[AF.rounds.length - 1].summary : null;
  if (lastRes) L.push('- 最后一轮测试：✓' + (lastRes.pass || 0) + ' / ✗' + (lastRes.fail || 0) + ' / ⚠' + (lastRes.warn || 0) + ' / −' + (lastRes.skip || 0));
  L.push('');
  L.push('## ② 相关代码骨架（CLI 本轮触碰过的文件）');
  L.push(files.length ? files.map((f) => '- ' + f).join('\n') : '（无——CLI 未成功改动任何文件）');
  L.push('');
  L.push('## ③ 已实锤证据');
  for (const r of AF.rounds) {
    L.push('- 第 ' + r.round + ' 轮：' + (r.outcome || ''));
    if (r.failLines && r.failLines.length) L.push('  失败断言：\n' + r.failLines.map((x) => '    ✗ ' + x).join('\n'));
    if (r.buildErr) L.push('  编译报错尾：' + String(r.buildErr).slice(-400).replace(/\n/g, ' | '));
  }
  L.push('- 测试全程明细与 dump 证据：testing/console/artifacts/ 下按 runId 查（' + AF.runId + '-*）');
  L.push('');
  L.push('## ④ 已试方案 + 死因表');
  for (const r of AF.rounds) {
    L.push('| 第 ' + r.round + ' 轮 | 改动：' + (r.files && r.files.length ? r.files.join('、') : '（无改动）') + ' | 死因：' + (r.outcome || '') + ' |');
  }
  L.push('');
  L.push('## ⑤ 怀疑方向与求解点');
  L.push('- CLI agent 最后输出（尾 500 字，含其自述原因）：');
  L.push('```');
  L.push(stripAnsi(lastCliOut || '（无输出）').trim().slice(-500));
  L.push('```');
  if (lastBuildLog) { L.push('- 编译报错（尾 800 字）：'); L.push('```'); L.push(String(lastBuildLog).slice(-800)); L.push('```'); }
  L.push('');
  L.push('> 请把本报告整段发给任意 AI（豆包/DeepSeek/CodeArts 等）求方案；方案回来后可把要点贴回 DevEco Code 继续修。');
  L.push('> 仓库已自动回滚到闭环启动前的快照（' + String(AF.bootSnap || '').slice(0, 12) + '），数据安全无损。');
  return L.join('\n');
}
async function afDeadEnd(reason, lastCliOut, lastBuildLog) {
  AF.phase = 'deadend';
  afSend('deadend', '熔断：' + reason + ' —— 生成死胡同报告…');
  const rpt = afDeadEndReport(reason, lastCliOut, lastBuildLog);
  const p = afWriteReport('死胡同报告_' + AF.runId + '.md', rpt);
  AF.result = { outcome: 'deadend', reason, report: p };
  if (AF.bootSnap) {
    const rb = await gitRollback(AF.bootSnap);
    afSend('deadend', '已回滚到启动前快照 ' + String(AF.bootSnap).slice(0, 12) + '（' + (rb.ok ? '成功' : '失败:' + rb.out) + '）；报告已放桌面：' + p);
  } else afSend('deadend', '报告已放桌面：' + p);
}
// ---------- 闭环主状态机 ----------
async function afLoop() {
  const af = CFG.autofix || {};
  const maxRounds = af.maxRounds || 2;
  // ★ 0.243.0.2：CLI 超时分档——非流式（代理整包生成）更慢独立放大（默认 900s）；流式保持 600s
  const cliTimeout = afUseStream() ? (af.cliTimeoutStreamMs || af.timeoutMs || 600000) : (af.cliTimeoutNonStreamMs || af.timeoutMs || 900000);
  let lastCliOut = '', lastBuildLog = '';
  try {
    // 轮 0：基线测试（确认有红才修）
    AF.phase = 'test';
    afSend('test', '第 0 轮：跑基线测试（套件：' + AF.suites.join(' + ') + '）');
    let testRes = await afRunTests('T0');
    AF.rounds.push({ round: 0, outcome: testRes.fails.length ? '基线有红（✗' + testRes.summary.fail + '）' : '基线全绿', files: [], summary: testRes.summary,
      failLines: testRes.fails.map((f) => f.case + '@' + f.device + '：' + (f.steps[0] ? f.steps[0].name + '—' + String(f.steps[0].detail || '').slice(0, 120) : '无失败步骤')) });
    if (!testRes.fails.length) {
      // ★ 0.243.0.2：基线全绿也落绿报告（此前只有修复后全绿才写——闭环跑完桌面上该有产物）
      const rpt0 = afGreenReport(0, testRes);
      const p0 = afWriteReport('自动修复报告_' + AF.runId + '.md', rpt0);
      AF.result = { outcome: 'green', rounds: 0, note: '基线测试全绿，无需修复——直接收工', report: p0 };
      afSend('done', '✅ 基线测试全绿——无需修复，闭环收工；报告已放桌面：' + p0);
      return;
    }
    afSend('test', '基线：✗' + testRes.summary.fail + ' 项失败——开始修复循环（上限 ' + maxRounds + ' 轮）');
    // 启动快照（含用户未提交工作=入历史不丢；死胡同回滚锚点）
    const snap0 = await gitSnap('autofix 启动基线快照(' + AF.runId + ')');
    AF.bootSnap = snap0.hash;
    afSend('snapshot', '启动快照 ' + snap0.hash.slice(0, 12) + (snap0.empty ? '（工作区干净）' : '（已把当前未提交改动入历史保护）'));
    let noConv = 0, buildFail = 0;
    for (let round = 1; round <= maxRounds; round++) {
      if (AF.abort) break;
      AF.round = round;
      // 打点
      const snap = await gitSnap('autofix-round-' + round + ' 修复前快照(' + AF.runId + ')');
      afSend('snapshot', '第 ' + round + ' 轮打点 ' + snap.hash.slice(0, 12));
      // 任务包 + CLI 改码
      AF.phase = 'fix';
      const note = round > 1 ? (noConv > 0 ? '上一轮未收敛，仍失败' : '') : '';
      const pkg = afBuildTask(testRes, lastBuildLog, round, note || undefined);
      try {
        const dir = path.join(ART_DIR, AF.runId); fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(path.join(dir, 'task-round-' + round + '.md'), pkg);
      } catch (_) { /* 存档尽力 */ }
      afSend('fix', '派单 CLI agent（deveco headless，通道=' + ((CFG.autofix && CFG.autofix.model) || 'CLI 默认') + (afProxyWanted() ? '+非流式代理' : '') + '，超时 ' + Math.round(cliTimeout / 1000) + 's 强杀）…');
      const tCli0 = Date.now();
      const cli = await afRunCliRetry(pkg, cliTimeout, 2);
      lastCliOut = cli.out;
      try { fs.writeFileSync(path.join(ART_DIR, AF.runId, 'cli-round-' + round + '.log'), cli.out); } catch (_) { /* 存档尽力 */ }
      afSend('fix', 'CLI 退出 code=' + cli.code + (cli.timedOut ? '（超时被强杀）' : '') + '，输出 ' + cli.out.length + ' 字，用时 ' + Math.round((Date.now() - tCli0) / 1000) + 's（已存档）');
      if (AF.abort) break;
      // diff 检查（死轮 / 红线）
      const files = await gitChangedFiles();
      if (!files.length) {
        noConv++;
        AF.rounds.push({ round, outcome: '死轮：CLI 未改动任何文件', files: [], summary: testRes.summary });
        afSend('fix', '✗ 死轮：CLI 没改任何文件（连击 ' + noConv + '/' + maxRounds + '）');
        if (noConv >= maxRounds) { await afDeadEnd('连续 ' + noConv + ' 轮 CLI 零改动（修不动或无解）', lastCliOut, lastBuildLog); return; }
        continue;
      }
      const hits = afRedlineHit(files);
      // ★ 0.243.0.2 内容级红线：diff（基准=本轮打点快照）删除/修改行扫描持久化 key——多文件整体逐行校验
      const diffOut = await git(['diff', snap.hash, '--unified=0']);
      const keyHits = afRedlineKeysHit(diffOut.out);
      if (hits.length || keyHits.length) {
        const all = hits.concat(keyHits);
        afSend('redline', '✗ 红线命中：' + all.join('、') + ' —— 自动回滚当轮+熔断转人工');
        await gitRollback(snap.hash);
        AF.rounds.push({ round, outcome: '红线命中已回滚：' + all.join('、'), files, summary: testRes.summary });
        await afDeadEnd('改动触碰红线文件（已自动回滚）：' + all.join('、'), lastCliOut, lastBuildLog);
        return;
      }
      afSend('fix', '本轮改动 ' + files.length + ' 个文件：' + files.join('、'));
      // 编译
      AF.phase = 'build';
      afSend('build', '编译（本地 hvigorw，最长 15 分钟）…');
      const b = await localBuild();
      if (!b.ok) {
        buildFail++;
        lastBuildLog = b.log || b.err || '';
        afSend('build', '✗ 编译失败（连击 ' + buildFail + '/2）：' + String(b.err || '').slice(0, 150));
        AF.rounds.push({ round, outcome: '编译失败（报错已喂下一轮）', files, summary: testRes.summary, buildErr: lastBuildLog });
        if (buildFail >= 2) { await afDeadEnd('编译连续 2 轮失败（CLI 改崩了）', lastCliOut, lastBuildLog); return; }
        continue; // 编译报错进下一轮任务包（afBuildTask 的 buildLog 参数）
      }
      buildFail = 0;
      afSend('build', '✓ 编译通过');
      // 装机（覆盖安装到参测设备）
      AF.phase = 'install';
      for (const devId of AF.devices) {
        const dev = CFG.devices.find((d) => d.id === devId);
        afSend('install', dev.label + ' 覆盖安装…');
        const ins = await bmInstall(dev.serial, true);
        if (!ins.ok) {
          AF.rounds.push({ round, outcome: '装机失败：' + dev.label, files, summary: testRes.summary });
          await afDeadEnd('装机失败（' + dev.label + '）：' + ins.detail, lastCliOut, lastBuildLog);
          return;
        }
        afSend('install', '✓ ' + dev.label + ' 安装成功');
      }
      // 重跑
      AF.phase = 'test';
      afSend('test', '第 ' + round + ' 轮修复完成——重跑测试…');
      testRes = await afRunTests('T' + round);
      const failLines = testRes.fails.map((f) => f.case + '@' + f.device + '：' + (f.steps[0] ? f.steps[0].name + '—' + String(f.steps[0].detail || '').slice(0, 120) : '无失败步骤'));
      AF.rounds.push({ round, outcome: testRes.fails.length ? '修后仍失败（✗' + testRes.summary.fail + '）' : '全绿', files, summary: testRes.summary, failLines });
      if (!testRes.fails.length) {
        const snapDone = await gitSnap('autofix: 修复完成 round-' + round + '(' + AF.runId + ')');
        const rpt = afGreenReport(round, testRes);
        const p = afWriteReport('自动修复报告_' + AF.runId + '.md', rpt);
        AF.result = { outcome: 'green', rounds: round, files, report: p, snap: snapDone.hash };
        afSend('done', '✅ 第 ' + round + ' 轮修复后全绿！成果已打点 ' + snapDone.hash.slice(0, 12) + '，报告已放桌面');
        return;
      }
      noConv++;
      afSend('test', '✗ 修后仍有 ' + testRes.summary.fail + ' 项失败（不收敛连击 ' + noConv + '/' + maxRounds + '）');
      if (noConv >= maxRounds) { await afDeadEnd('连续 ' + noConv + ' 轮修复后测试仍失败', lastCliOut, lastBuildLog); return; }
    }
    if (AF.abort) { AF.result = { outcome: 'aborted' }; afSend('done', '用户请求中止——闭环停止'); return; }
    await afDeadEnd('修复轮次用尽（' + maxRounds + ' 轮）仍未全绿', lastCliOut, lastBuildLog);
  } catch (e) {
    AF.result = { outcome: 'error', error: String(e) };
    afSend('error', '闭环异常：' + String(e));
  } finally {
    running = false;
    AF.state = 'idle'; AF.phase = '';
    abortRequested = false;
    sseSend({ type: 'autofix-end', runId: AF.runId, result: AF.result });
  }
}
// ---------- 健康检查（★ 0.243.0.2 六灯：CLI/git/模型探针/编译链/设备在线/非流式代理（stream=true 时恒绿标未启用）；缓存 5 分钟，?refresh=1 强制重探） ----------
async function afHealthCheck(force) {
  if (!force && AF.lastHealth && Date.now() - AF.healthAt < 300000) return { ...AF.lastHealth, cached: true };
  const af = CFG.autofix || {};
  const r = { cli: { ok: false, detail: '' }, git: { ok: false, detail: '' }, model: { ok: false, detail: '' }, build: { ok: false, detail: '' }, device: { ok: false, detail: '' }, proxy: { ok: false, detail: '' }, at: now() };
  // 灯1 CLI 存在性
  const v = await new Promise((resolve) => {
    if (!af.cliCmd) return resolve({ code: -1, out: '未配置 autofix.cliCmd（config.json）' });
    const p = spawn(af.cliCmd, ['-v'], { timeout: 15000 });
    let o = ''; p.stdout.on('data', (d) => { o += d; }); p.stderr.on('data', (d) => { o += d; });
    p.on('close', (c) => resolve({ code: c ?? -1, out: o })); p.on('error', (e) => resolve({ code: -1, out: String(e) }));
  });
  r.cli = { ok: v.code === 0, detail: v.code === 0 ? 'deveco ' + stripAnsi(v.out).trim().slice(0, 30) : '不可执行：' + stripAnsi(v.out).slice(0, 120) };
  // 灯2 git（打点/回滚依赖）
  const g = await gitAvailable();
  r.git = { ok: g.ok, detail: g.ok ? 'HEAD ' + g.head : 'git 不可用：' + g.err };
  // 灯3 模型连通（最小探针任务，~15s；带重试——上游流式截断间歇性）
  if (r.cli.ok) {
    const probe = await afRunCliRetry('连通性探针：只回复两个字「正常」，不要做任何其他事', 90000, 1);
    r.model = { ok: probe.code === 0 && /正常/.test(stripAnsi(probe.out)), detail: probe.code === 0 ? '探针回显：' + stripAnsi(probe.out).trim().slice(0, 60) : '探针失败（exit ' + probe.code + '）：' + stripAnsi(probe.out).slice(-100) };
  } else r.model = { ok: false, detail: 'CLI 不可用，跳过' };
  // 灯4 编译链
  const lb = CFG.localBuild || {};
  r.build = { ok: !!(lb.hvigorw && fs.existsSync(lb.hvigorw)), detail: lb.hvigorw && fs.existsSync(lb.hvigorw) ? 'hvigorw 就绪' : 'hvigorw 未配置/不存在（config.localBuild）' };
  // 灯5 设备（至少一台非工作机在线）
  const devs = await probeDevices();
  const online = devs.filter((d) => d.online && !d.workMachine);
  r.device = { ok: online.length > 0, detail: online.length ? '在线：' + online.map((d) => d.label).join('、') : '全部设备离线（PC 开 DevEco/Pad 插线/手机连 WiFi）' };
  // 灯6 非流式适配代理（★ 0.243.0.2：仅 proxy.enabled=true 才真探——救生艇默认关闭；否则恒绿标未启用）
  if (!afProxyWanted()) {
    r.proxy = { ok: true, detail: '代理未启用（默认关闭；闭环模型通道=' + ((CFG.autofix && CFG.autofix.model) || 'CLI 默认') + '）' };
  } else {
    const pc = afProxyCfg();
    const pe = await afProxyEnsure();
    r.proxy = pe.ok
      ? { ok: true, detail: '非流式代理监听 ' + pc.host + ':' + pe.port + '（CLI baseURL 覆盖→' + pc.upstream + '）' }
      : { ok: false, detail: pe.err };
  }
  AF.lastHealth = r; AF.healthAt = Date.now();
  return r;
}

// ---------- HTTP 服务 ----------
const ORIGIN_OK = new Set(['null', `http://localhost:${CFG.port}`, `http://127.0.0.1:${CFG.port}`]);
function apiGuard(req) {
  const o = req.headers.origin;
  if (o === undefined) return true; // 同源 GET / curl（无 Origin 头=非浏览器跨页）
  return ORIGIN_OK.has(o);
}
function json(res, code, obj) { res.writeHead(code, { 'content-type': 'application/json; charset=utf-8', 'access-control-allow-origin': '*' }); res.end(JSON.stringify(obj)); }

let pendingShutdown = null;
async function handler(req, res) {
  const u = new URL(req.url, `http://127.0.0.1:${CFG.port}`);
  if (req.method === 'OPTIONS') { res.writeHead(204, { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'content-type' }); return res.end(); }
  if (u.pathname === '/api/health') return json(res, 200, { ok: true, pid: process.pid, version: VERSION, running, stale: isStale() });
  // ★ 0.229.24 /api/dump：任意时刻读设备当前屏幕 dump——「对测试台的测试」盯屏通道
  //   （AI 后台看屏幕实际显示 vs 测试台日志逐字对照；?dev=pad&keys=同意 癲过滤只留含关键字的行）
  if (u.pathname === '/api/dump' && req.method === 'GET') {
    const devId = u.searchParams.get('dev') || 'pad';
    const dev = (CFG.devices || []).find((x) => x.id === devId);
    if (!dev) return json(res, 404, { ok: false, error: '未知设备：' + devId });
    const d = await dumpLayout(dev.serial);
    if (!d.ok) return json(res, 200, { ok: false, error: 'dumpLayout 失败', len: d.text.length });
    const keys = (u.searchParams.get('keys') || '').split(',').map((s) => s.trim()).filter(Boolean);
    let text = d.text;
    if (keys.length) {
      // 关键字过滤：只留包含任一关键字的 "text" 片段（便于快速核对屏幕上有哪些文案）
      const texts = [...d.text.matchAll(/"text"\s*:\s*"([^"]*)"/g)].map((m) => m[1]).filter((t) => keys.some((k) => t.includes(k)));
      text = texts.join(' | ');
    }
    return json(res, 200, { ok: true, len: d.text.length, text: text.slice(0, 60000) });
  }
  if (u.pathname === '/' ) {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    return res.end(fs.readFileSync(path.join(ROOT, 'public', 'index.html')));
  }
  if (u.pathname === '/api/events') {
    res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache', 'connection': 'keep-alive' });
    res.write('data: {"type":"hello"}\n\n');
    sseClients.add(res); req.on('close', () => sseClients.delete(res));
    return;
  }
  if (!apiGuard(req)) return json(res, 403, { error: 'Origin 不在白名单' });
  // ★ 0.229.15 延迟关闭+取消：pagehide 带 ?delay=ms → 延迟执行；页面回来 /api/shutdown/cancel 取消
  //   解决"刷新也触发 pagehide"的误停——刷新后 boot 成功即取消，只有真关页签才延迟后停
  if (u.pathname === '/api/shutdown' && req.method === 'POST') {
    if (running) return json(res, 409, { error: '测试正在运行，请等它结束后再关闭' });
    // ★ 0.233.0.3 看护协作标记：主动关闭（页面按钮/关 html 延迟关/agent curl）=用户意图关闭——
    //   写 .watchdog-skip，watch-server.sh 看到标记保持关闭不拉起；新实例启动时清标记恢复看护
    try { fs.writeFileSync(path.join(ROOT, '.watchdog-skip'), String(Date.now())); } catch (_) { /* 尽力写 */ }
    const delay = parseInt(u.searchParams.get('delay') || '0', 10);
    if (delay > 0) {
      if (pendingShutdown) clearTimeout(pendingShutdown);
      json(res, 200, { ok: true, delayed: delay });
      console.log(`[关闭] 页面离开——${delay / 1000}s 后自动关闭（页面回来会自动取消）`);
      pendingShutdown = setTimeout(() => {
        pendingShutdown = null;
        if (running) { console.log('[关闭] 延迟到期但测试在跑——取消，不关'); return; }
        try { fs.unlinkSync(PID_FILE); } catch (_) { /* 无 pid 文件 */ }
        console.log(`[关闭] 延迟到期，测试台服务 ${process.pid} 退出`);
        process.exit(0);
      }, delay);
      return;
    }
    json(res, 200, { ok: true, pid: process.pid });
    console.log(`[关闭] 收到前端关闭指令，测试台服务 ${process.pid} 即将退出`);
    setTimeout(() => {
      try { fs.unlinkSync(PID_FILE); } catch (_) { /* 无 pid 文件 */ }
      process.exit(0);
    }, 300);
    return;
  }
  if (u.pathname === '/api/shutdown/cancel' && req.method === 'POST') {
    if (pendingShutdown) { clearTimeout(pendingShutdown); pendingShutdown = null; console.log('[关闭] 页面已回来——自动关闭已取消'); }
    // ★ 0.233.0.3：取消关闭=无关闭意图——清看护跳过标记（防残留标记挡住意外退出的自动拉起）
    try { fs.unlinkSync(path.join(ROOT, '.watchdog-skip')); } catch (_) { /* 无标记跳过 */ }
    return json(res, 200, { ok: true, cancelled: true });
  }
  if (u.pathname === '/api/suites') {
    const suites = {};
    const SUITE_NAME = { version: '版本核验（装机真身）', login: '账号登录（三入口×真实状态：门禁→各入口登录→退出→覆盖保留）', 'sync-boot': '云同步·三端从零引导（★0.241.0.4：fresh 装机后 协议→登录→开同步→三端收敛；唯一人工=华为授权页）', sync: '云同步四域数据链', syncflow: '云同步数据链·跨端编排（Pad UI 产生→PC 云端收敛；0.229.25 新增）+ 手机操作端链路（0.241.0.4 新增）', 'ui-audit': 'UI 规范审计（A 类页面巡检+B 类弹窗体系；0.229.26 新增）', chat: '对话稳定性与划词（压后台保留/划词清除/划词引用/划词取词准确；0.232.0 起）', tts: '云端语音朗读 API（openspeech；0.232.0 新增）', kbview: '知识库双视图与加号菜单（网格封面卡/跨页记忆/+菜单双库统一；0.239.0 新增）', widget: '桌面服务卡片（切库死锁回归+完成态切换入口；0.274.0 新增）', arkui: 'ArkUI Test（设备内真断言）', sp: 'SP 司忆点云同步专项（★0.299.2.1 bug1 定性五件套：静态审计/冷启恢复/冷装首拉/签到跨端/长时监控）' };
    for (const c of CASES) { if (c.builtin) continue; (suites[c.suite] = suites[c.suite] || { name: SUITE_NAME[c.suite] || c.suite, cases: [] }).cases.push({ id: c.id, name: c.name, semi: c.semi, scope: c.scope }); }
    return json(res, 200, { suites, running, config: { bundle: CFG.bundle, expectedVersionCode: EXPECTED_VC, appVersionName: readAppVersionName(), hap: CFG.hap } });
  }
  if (u.pathname === '/api/version') {
    const devs = await probeDevices();
    const dev = devs.find((d) => d.online) || null;
    if (!dev) return json(res, 200, { ok: false, expected: EXPECTED_VC, actual: null, device: null, reason: '无在线设备（PC/Pad 未连接）' });
    const v = await bmVersionCode(dev.serial);
    return json(res, 200, { ok: v.ok && v.code === EXPECTED_VC, expected: EXPECTED_VC, actual: v.code, device: dev.id, label: dev.label, raw: v.raw });
  }
  if (u.pathname === '/api/devices') {
    await autoConnectTcpDevices();
    const targets = await listTargets();
    const devices = await probeDevices();
    // ★ 0.248.7.1：常亮自愈驱动（前端 30s 轮询即节拍——持久 on 的设备上线边沿重放完整序列、在线 60s 节流续命；不阻塞响应）
    keepaliveMaintain(devices).catch(() => { /* 自愈尽力，不影响设备探测 */ });
    return json(res, 200, { devices: devices.map((d) => ({ ...d, ka: KEEPALIVE_SET.has(d.id) })), running, targets });
  }
  // ★ 0.241.0.5 设备常亮（用户需求：手机测试期一直锁屏卡流程——仿 DevEco 连上设备保持常开）
  // ★ 0.241.0.8 重写（用户实测翻车：点常亮手机被切进深色省电界面+常亮根本没生效外出仍熄屏）——
  //   真凶①=power-shell setmode 602 根本不是「永不休眠」：鸿蒙 PowerMode 枚举 600=正常/601=省电/602=**超省电**——此前实现是切超省电模式（回显 Success 只是切换成功、语义全错，深色界面即其表现）；
  //   真凶②=中部上滑手势（600,2400→600,600）在已解锁桌面上=拉起桌面上滑全局搜索浮层（用户截图半透明侧边栏实锤）——前台扰动。
  //   正解：常亮=power-shell timeout -o 2147483647（临时覆盖休眠超时≈24.8 天，不动用户设置）；off=timeout -r 恢复原值 + setmode 600 救回残留省电模式；
  //   上滑改底部区域（600,2000→600,1200）：锁屏解锁到主屏 / 已解锁桌面底部上滑不触发全局搜索。
  // ★ 0.248.7.1 常亮持久化+自愈（用户报「测试台显示常亮但手机还是黑屏」）——持久化/边沿检测/续命节流的
  //   模块级实现在文件尾部 KEEPALIVE_* 区（handler 内定义会在每次请求重建 Map 致边沿失效、30s 重放全套=前台灾难）。
  if (u.pathname === '/api/keepalive' && req.method === 'POST') {
    let body = ''; req.on('data', (d) => { body += d; });
    req.on('end', async () => {
      try {
        const p = JSON.parse(body || '{}');
        const dev = (CFG.devices || []).find((x) => x.id === p.device);
        if (!dev) return json(res, 404, { ok: false, error: '未知设备：' + p.device });
        if (!p.on) {
          const t = await sh(dev.serial, 'power-shell timeout -r', 12000); // 恢复用户原始休眠超时
          const r = await sh(dev.serial, 'power-shell setmode 600', 12000); // 切回正常模式（顺带救回旧版 602 误切的超省电）
          // ★ 0.248.7.1：关=持久态摘除（自愈停转；下次再点=重新落盘）
          KEEPALIVE_SET.delete(dev.id);
          KA_WAS_ONLINE.delete(dev.id);
          saveKeepalive();
          return json(res, 200, { ok: /success|restore|600/i.test(r + ' ' + t), detail: (r.trim() + ' | ' + t.trim()).slice(0, 120), mode: 'normal' });
        }
        const w = await sh(dev.serial, 'power-shell wakeup', 12000);
        await sh(dev.serial, 'power-shell setmode 600', 12000); // 确保正常模式（防残留省电态干扰常亮观感）
        const t = await sh(dev.serial, 'power-shell timeout -o 2147483647', 12000); // ★ 常亮正解=临时覆盖休眠超时
        await sleep(600);
        await sh(dev.serial, 'uitest uiInput swipe 600 2000 600 1200', 12000); // 底部上滑解锁（锁屏→解锁到主屏；已解锁桌面=底部上滑回主屏，不触发中部全局搜索浮层）
        await sleep(800);
        // ★ 0.241.0.9 修「成功被误报失败」：timeout -o 成功回显=「Override screen off time to …」不含 success 字样（用户真机实锤），判定补 override/restore 关键词；失败时给中文 error（§4 禁裸英文）
        const ok0 = /success|override/i.test(t);
        if (ok0) {
          // ★ 0.248.7.1：开=持久态登记（服务/设备/页面任一重启后自愈续命）
          KEEPALIVE_SET.add(dev.id);
          KA_WAS_ONLINE.set(dev.id, true);
          KA_LAST_APPLY.set(dev.id, Date.now());
          saveKeepalive();
        }
        return json(res, 200, { ok: ok0, error: ok0 ? '' : '设备未确认常亮（回显：' + (t.trim() || w.trim()).slice(0, 80) + '）', detail: (w.trim() + ' | ' + t.trim()).slice(0, 200), mode: 'always-on' });
      } catch (e) { return json(res, 400, { ok: false, error: String(e) }); }
    });
    return;
  }
  // ★ 0.241.0.5 从零进度探测（用户需求：分清设备处于「全新安装还没走完流程」还是「协议/登录/同步已全部就绪」——
  //   否则后面的测试进度全卡住也不知道卡在哪步）。全 CLI 通道（grepPref 持久化 + sqlite 行数），锁屏/无 UI 通道设备照样可测：
  //   协议=agreement-v1 落盘；登录=huawei-account 落盘；同步=cloud_data 行数（>0=同步活）
  if (u.pathname === '/api/bootstate') {
    const devs = await probeDevices();
    const out = await Promise.all(devs.filter((d) => d.online).map(async (d) => {
      const [agree, login, sync] = await Promise.all([
        grepPref(d.serial, 'agreement-v1'),
        grepPref(d.serial, 'huawei-account'),
        dbCount(d.serial, null)
      ]);
      return { id: d.id, label: d.label, agree: agree.found, login: login.found, syncRows: sync.ok ? sync.n : null, syncErr: sync.ok ? '' : String(sync.raw).slice(0, 80) };
    }));
    return json(res, 200, { states: out, at: now() });
  }
  if (u.pathname === '/api/results') return json(res, 200, loadResults());
  // ★ 0.229.20 停止测试：用户拍板"打开不能是失控的执行中"——后台在跑的那轮可随时请求中止
  if (u.pathname === '/api/stop' && req.method === 'POST') {
    if (!running) return json(res, 200, { ok: true, note: '当前没有在跑的测试' });
    abortRequested = true;
    return json(res, 200, { ok: true, note: '已请求中止——当前步骤跑完即停（不硬杀正在执行的命令），稍等片刻' });
  }
  if (u.pathname === '/api/run' && req.method === 'POST') {
    if (running) return json(res, 409, { error: '已有测试在跑（页面刷新/重开不会中断后台执行——等它跑完，或点【停止测试】）' });
    let body = '';
    req.on('data', (d) => { body += d; });
    req.on('end', async () => {
      try {
        const p = JSON.parse(body || '{}');
        if (!Array.isArray(p.devices) || !p.devices.length) return json(res, 400, { error: '至少勾选一台设备' });
        if (!Array.isArray(p.cases) || !p.cases.length) return json(res, 400, { error: '至少勾选一个用例' });
        const r = startRun(p.devices, p.cases);
        if (r.error) return json(res, 409, r);
        json(res, 200, r);
      } catch (e) { json(res, 400, { error: String(e) }); }
    });
    return;
  }
  if (u.pathname.startsWith('/api/checkpoint/') && req.method === 'POST') {
    const id = u.pathname.split('/')[3]; const action = u.searchParams.get('action');
    const cp = checkpoints.get(id);
    if (!cp || !cp.finish) return json(res, 404, { error: '检查点不存在或已结束' });
    if (action === 'ack') cp.finish('done', { auto: false });
    else if (action === 'skip') cp.finish('skipped');
    else if (action === 'extend') { cp.timeoutMs += 120000; sseSend({ type: 'checkpoint', cp: { ...cp } }); }
    else if (action === 'verdict') { cp.verdict = u.searchParams.get('v'); cp.finish('done', { auto: false }); }
    return json(res, 200, { ok: true, state: cp.state });
  }
  if (u.pathname === '/api/prep' && req.method === 'POST') {
    let body = '';
    req.on('data', (d) => { body += d; });
    req.on('end', async () => {
      try {
        const p = JSON.parse(body || '{}');
        const dev = CFG.devices.find((d) => d.id === p.device);
        if (!dev) return json(res, 400, { error: '设备不存在' });
        // ★ 0.229.25 装机前状态实录（须在卸载/安装前查——fresh 卸载后数据即清）：LOGIN-KEEP 前置快照用
        try { PREP_STATE[dev.id] = { login: (await grepPref(dev.serial, 'huawei-account')).found, at: now() }; } catch (_) { /* 快照尽力记录 */ }
        const mode = p.mode === 'fresh' ? 'fresh' : 'overwrite'; // 默认覆盖安装（用户需求 6）
        let un = null;
        if (mode === 'fresh') {
          un = await bmUninstall(dev.serial);
          // ★ 0.229.18：卸载失败→中止安装（防「未卸载却报装机成功」假成功——用户实测 PC 全新安装后登录态还在即此因）
          // ★ 0.241.0.3：un.clean=true（code:9568386 missing installed bundle）=设备从未装过该 app、本来就是干净状态——放行继续安装（新设备首装必踩，此前 Pura X View 被中止即此因）
          if (!un.ok && !un.clean) return json(res, 200, { mode, uninstall: un, install: null, coldStart: null, aborted: true, error: '卸载失败——已中止安装（防旧数据残留的假成功；原始输出见 uninstall.detail）' });
        }
        const ins = await bmInstall(dev.serial, mode === 'overwrite');
        // ★ 0.229.22（用户拍板 A）：装机后不再自动冷启——首次启动交给第一条用例的 coldStart 完成（"装完弹一次+用例又弹一次"→只弹一次）；单独装机想验证就手动点开 app
        json(res, 200, { mode, uninstall: un, install: ins, coldStart: null, coldNote: '装机后不冷启（首次启动交给第一条用例，少弹一次）' });
      } catch (e) { json(res, 400, { error: String(e) }); }
    });
    return;
  }
  if (u.pathname === '/api/build' && req.method === 'POST') {
    let body = '';
    req.on('data', (d) => { body += d; });
    req.on('end', async () => {
      try {
        const p = JSON.parse(body || '{}');
        const source = p.source === 'local' ? 'local' : (p.source === 'server' ? 'server' : 'auto');
        let r;
        if (source === 'local') r = await localBuild();
        else if (source === 'server') r = await serverBuild();
        else {
          const local = await localBuild();
          if (local.ok) r = { ...local, via: 'local' };
          else {
            const srv = await serverBuild();
            r = srv.ok ? { ...srv, via: 'server', localErr: local.err }
                       : { ok: false, err: '本地编译失败（' + local.err + '）；服务器编译也失败（' + srv.err + '）', log: local.log || '' };
          }
        }
        json(res, r.ok ? 200 : 500, { source, ...r });
      } catch (e) { json(res, 500, { error: String(e) }); }
    });
    return;
  }
  if (u.pathname === '/api/devices/update' && req.method === 'POST') {
    let body = '';
    req.on('data', (d) => { body += d; });
    req.on('end', async () => {
      try {
        const p = JSON.parse(body || '{}');
        const dev = CFG.devices.find((d) => d.id === p.id);
        if (!dev) return json(res, 400, { error: '设备不存在' });
        const serial = String(p.serial || '').trim();
        dev.serial = serial;
        if (serial && (dev.conn === 'WiFi 待注册' || dev.conn === 'WiFi')) dev.conn = 'WiFi';
        if (!serial) dev.conn = 'WiFi 待注册';
        // 串号为 ip:port 形态时自动 hdc tconn 建连（hdc 正确命令是 tconn 而非 connect；幂等）
        let connect = null;
        if (/^\d+\.\d+\.\d+\.\d+:\d+$/.test(serial)) connect = await hdcTconn(serial);
        fs.writeFileSync(path.join(ROOT, 'config.json'), JSON.stringify(CFG, null, 2));
        return json(res, 200, { devices: await probeDevices(), running, connect });
      } catch (e) { return json(res, 400, { error: String(e) }); }
    });
    return;
  }
  // ★ 0.243.0.1 自动修复闭环四接口（全案 docs/0.165+/0.243.0）
  if (u.pathname === '/api/autofix/health') {
    const force = u.searchParams.get('refresh') === '1';
    return json(res, 200, await afHealthCheck(force));
  }
  if (u.pathname === '/api/autofix/status') return json(res, 200, afStatusLite());
  if (u.pathname === '/api/autofix/stop' && req.method === 'POST') {
    if (AF.state === 'idle') return json(res, 200, { ok: true, note: '闭环当前不在运行' });
    AF.abort = true; abortRequested = true;
    if (AF.cliProc) { try { AF.cliProc.kill('SIGKILL'); } catch (_) { /* 已退出 */ } }
    return json(res, 200, { ok: true, note: '已请求中止——当前环节完成即停（CLI 子进程已强杀）' });
  }
  if (u.pathname === '/api/autofix/start' && req.method === 'POST') {
    if (AF.state !== 'idle') return json(res, 409, { error: '自动修复闭环正在运行（' + AF.phase + ' 第 ' + AF.round + ' 轮）——等它结束或点停止' });
    if (running) return json(res, 409, { error: '有测试正在跑——等它跑完或点【停止测试】，再启动自动修复' });
    let body = '';
    req.on('data', (d) => { body += d; });
    req.on('end', async () => {
      try {
        const p = JSON.parse(body || '{}');
        // 套件校验（默认快速档：version+ui-audit，方案开放问题 3 建议值）
        const validSuites = [...new Set(CASES.map((c) => c.suite))];
        const suites = (Array.isArray(p.suites) ? p.suites : (CFG.autofix && CFG.autofix.defaultSuites) || ['version', 'ui-audit']).filter((s) => validSuites.includes(s));
        if (!suites.length) return json(res, 400, { error: '未选择有效套件' });
        // 设备校验：必须勾选且全部在线（离线=拒绝启动，方案三灯纪律）
        const devs = await probeDevices();
        const want = (Array.isArray(p.devices) ? p.devices : []).filter(Boolean);
        if (!want.length) return json(res, 400, { error: '至少勾选一台设备' });
        const off = want.map((id) => devs.find((d) => d.id === id)).filter((d) => !d || !d.online);
        if (off.length) return json(res, 409, { error: '设备离线，拒绝启动：' + off.map((d) => d ? d.label : '未知设备').join('、') + '——先连设备（连接诊断可复制报告）' });
        // ★ 0.243.0.2 流式开关（面板可勾选覆盖 config 默认；须在健康检查前定——探针/代理灯/CLI 超时分档都读它）
        if (typeof p.stream === 'boolean') AF.stream = p.stream;
        // 健康检查（强制全探，任一红=拒绝并亮原因）
        const h = await afHealthCheck(true);
        const reds = Object.entries(h).filter(([k, v]) => v && typeof v === 'object' && v.ok === false).map(([k, v]) => ({ lamp: k, detail: v.detail }));
        if (reds.length) return json(res, 409, { error: '健康检查红灯，拒绝启动：' + reds.map((x) => x.lamp + '→' + x.detail).join('；'), health: h });
        // 启动
        AF.state = 'running'; AF.runId = RUN_ID() + 'AF'; AF.round = 0; AF.phase = 'health';
        AF.devices = want; AF.suites = suites; AF.bootSnap = null; AF.abort = false;
        AF.startedAt = Date.now(); AF.rounds = []; AF.result = null; AF.lastHealth = h;
        afSend('health', '六灯全绿（CLI/git/模型/编译/设备' + (afProxyWanted() ? '/代理' : '') + '·通道=' + ((CFG.autofix && CFG.autofix.model) || 'CLI 默认') + '）——闭环启动：' + suites.join('+') + ' × ' + want.join('、'));
        afLoop().catch(async (e) => { AF.state = 'idle'; running = false; sseSend({ type: 'autofix-end', runId: AF.runId, result: { outcome: 'error', error: String(e) } }); });
        return json(res, 200, { ok: true, runId: AF.runId });
      } catch (e) { return json(res, 400, { error: String(e) }); }
    });
    return;
  }
  res.writeHead(404); res.end();
}

// ---------- 启动自愈（0.229.2）：健康实例幂等复用 + 僵尸占用自动清障 ----------
// 本机实情（2026-10-12 实测）：/proc/net/tcp 用户态 Permission denied，但 hdc 本机调试口（shell uid）可读
// 且 /usr/bin/lsof 的 -t/-p 模式平台 bug（空输出/卡死）——故 PID 定位走 inode 双通道：
//   通道① pid 文件（自己旧实例）  通道② hdc shell 读 /proc/net/tcp 拿 inode → 本机扫 /proc/*/fd 匹配
const PID_FILE = path.join(ROOT, 'server.pid');

// ============================================================
// ★ 0.248.7.1 常亮持久化+自愈（模块级——用户报「测试台显示常亮但手机还是黑屏」）
//   真因=timeout -o 覆盖是 PowerMgr 内存态：手机重启/服务重启/页面刷新（前端 KEEPON 曾是 session 级）
//   任何一环都让「显示常亮」与「实际常亮」脱节，脱节后无人自愈（手机照常熄屏）。
//   真机实测实锤：覆盖本身稳定生效（90s 后 dump 仍 OverrideTimeout=2147483647ms），缺的是持久+自愈：
//   ①状态落盘 keepalive.json（服务重启不丢）；②设备上线边沿（重启/重连后）自动重放完整常亮序列；
//   ③在线设备 60s 节流续命重刷 timeout -o（幂等，不 wakeup 不上滑不打扰前台）——前端 30s 轮询 /api/devices 即驱动节拍。
//   ⚠️ 必须模块级：handler 内定义会在每次请求重建 Map → 边沿检测失效 → 每 30s 重放全套序列=前台灾难。
// ============================================================
const KEEPALIVE_FILE = path.join(ROOT, 'keepalive.json');
let KEEPALIVE_SET = new Set();
try { KEEPALIVE_SET = new Set(JSON.parse(fs.readFileSync(KEEPALIVE_FILE, 'utf8'))); } catch (_) { /* 无文件=空集 */ }
function saveKeepalive() {
  try { fs.writeFileSync(KEEPALIVE_FILE, JSON.stringify([...KEEPALIVE_SET])); } catch (e) { console.log('[常亮] 状态落盘失败：' + String(e).slice(0, 80)); }
}
const KA_LAST_APPLY = new Map(); // devId → ms（续命节流）
const KA_WAS_ONLINE = new Map(); // devId → bool（上线边沿检测）
const KA_BUSY = new Set(); // 防重入
async function keepaliveMaintain(devs) {
  for (const d of devs) {
    if (!KEEPALIVE_SET.has(d.id)) { KA_WAS_ONLINE.set(d.id, d.online); continue; }
    if (!d.online) { KA_WAS_ONLINE.set(d.id, false); continue; }
    if (KA_BUSY.has(d.id)) { continue; }
    const was = KA_WAS_ONLINE.get(d.id) === true;
    KA_WAS_ONLINE.set(d.id, true);
    const t = Date.now();
    if (!was || t - (KA_LAST_APPLY.get(d.id) || 0) > 60000) {
      KA_BUSY.add(d.id);
      (async () => {
        try {
          if (!was) {
            // 上线边沿：设备重启/重连 override 必丢——完整序列重放（亮屏+覆盖+底部上滑解锁）
            await sh(d.serial, 'power-shell wakeup', 12000);
            await sh(d.serial, 'power-shell setmode 600', 12000);
            await sh(d.serial, 'power-shell timeout -o 2147483647', 12000);
            await sleep(600);
            await sh(d.serial, 'uitest uiInput swipe 600 2000 600 1200', 12000);
            console.log(`[常亮自愈] ${d.label} 上线边沿——完整常亮序列已重放`);
          } else {
            const r = await sh(d.serial, 'power-shell timeout -o 2147483647', 12000); // 在线续命：仅刷覆盖（幂等）
            if (!/override|success/i.test(r)) { console.log(`[常亮自愈] ${d.label} 续命回显异常：${r.trim().slice(0, 60)}`); }
          }
          KA_LAST_APPLY.set(d.id, Date.now());
        } catch (e) {
          console.log(`[常亮自愈] ${d.label} 维持失败：${String(e).slice(0, 80)}`);
        } finally { KA_BUSY.delete(d.id); }
      })();
    }
  }
}
function pidAlive(pid) { try { process.kill(pid, 0); return true; } catch (e) { return e.code === 'EPERM'; } }
async function localDebugSerial() {
  const targets = await listTargets();
  return targets.find((t) => /^127\.0\.0\.1:\d+$/.test(t)) || null;
}
async function portInode(port) {
  const serial = await localDebugSerial();
  if (!serial) return null;
  const hex = port.toString(16).toUpperCase().padStart(4, '0');
  const out = await sh(serial, `grep ' 0100007F:${hex} ' /proc/net/tcp`);
  const m = out.match(new RegExp('0100007F:' + hex + '\\s+\\S+\\s+0A\\s+\\S+\\s+\\S+\\s+\\S+\\s+\\d+\\s+\\d+\\s+(\\d+)'));
  return m ? m[1] : null;
}
function pidsByInode(inode) {
  const want = 'socket:[' + inode + ']';
  const pids = [];
  try {
    for (const ent of fs.readdirSync('/proc')) {
      if (!/^\d+$/.test(ent)) continue;
      try {
        for (const fd of fs.readdirSync('/proc/' + ent + '/fd')) {
          if (fs.readlinkSync('/proc/' + ent + '/fd/' + fd) === want) { pids.push(parseInt(ent, 10)); break; }
        }
      } catch (_) { /* 权限不足/进程已退 */ }
    }
  } catch (_) { /* /proc 读取异常 */ }
  return pids;
}
async function findPortPids(port) {
  // 通道①：pid 文件（本服务上一次实例，卡死但占端口的场景）
  const out = [];
  try {
    const old = parseInt(fs.readFileSync(PID_FILE, 'utf8').trim(), 10);
    if (Number.isInteger(old) && pidAlive(old) && old !== process.pid) out.push(old);
  } catch (_) { /* 无 pid 文件 */ }
  // 通道②：hdc shell inode → /proc 扫描
  const inode = await portInode(port);
  if (inode) for (const p of pidsByInode(inode)) if (!out.includes(p) && p !== process.pid) out.push(p);
  return out;
}
function probeSelf() {
  return new Promise((resolve) => {
    const req = http.get({ host: '127.0.0.1', port: CFG.port, path: '/api/health', timeout: 1500 }, (r) => {
      if (r.statusCode !== 200) return resolve(false);
      let body = '';
      r.on('data', (d) => { body += d.toString(); });
      r.on('end', () => {
        try { const j = JSON.parse(body); resolve(j.ok === true && !!j.version); }
        catch (_) { resolve(false); } // 200 但非本服务 health JSON（僵尸/其他程序）= 不健康
      });
      r.resume();
    });
    req.on('timeout', () => { req.destroy(); resolve(false); });
    req.on('error', () => resolve(false));
  });
}
async function startListen(attempt) {
  if (attempt === 0 && await probeSelf()) {
    console.log(`[测试台 ${VERSION}] 服务已在线（http://127.0.0.1:${CFG.port}）——自动复用，本进程退出，无需重复启动`);
    process.exit(0);
  }
  const srv = http.createServer(handler);
  srv.on('error', async (err) => {
    if (err.code === 'EADDRINUSE' && attempt < 3) {
      console.log(`[自愈] 端口 ${CFG.port} 被占用，自动排查…`);
      if (await probeSelf()) { console.log('[自愈] 占用者是健康服务实例——复用，本进程退出'); process.exit(0); }
      const pids = await findPortPids(CFG.port);
      if (pids.length) {
        console.log(`[自愈] 僵尸进程 PID=${pids.join(',')}——自动清理后重新监听`);
        for (const pid of pids) { try { process.kill(pid, 'SIGKILL'); } catch (_) { /* 已死 */ } }
        await sleep(1200);
      } else {
        console.log('[自愈] 未定位到占用进程（外部用户进程），稍后自动重试…');
        await sleep(2000);
      }
      return startListen(attempt + 1);
    }
    console.error('[启动失败]', err); process.exit(1);
  });
  srv.listen(CFG.port, '127.0.0.1', () => {
    try { fs.writeFileSync(PID_FILE, String(process.pid)); } catch (_) { /* 尽力写 */ }
    // ★ 0.233.0.3：新实例启动=恢复看护——清看护跳过标记（watch-server.sh 恢复自动重启/拉起）
    try { fs.unlinkSync(path.join(ROOT, '.watchdog-skip')); } catch (_) { /* 无标记跳过 */ }
    console.log(`[测试台 ${VERSION}] http://127.0.0.1:${CFG.port}  正本 testing/console/  HAP=${CFG.hap}`);
    const d = syncDesktop();
    console.log(d.ok ? `[桌面交付] 测试台.html + 启动测试台.sh（双击全自动：起服务+开浏览器）→ ${CFG.desktopDir}` : `[桌面交付] 跳过：${d.reason}`);
    setTimeout(() => autoConnectTcpDevices().catch(() => { /* 尽力连，失败不影响服务 */ }), 3000);
  });
}
startListen(0);
