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
const VERSION = '0.232.1.1'; // ★ 四段制：前三段跟 APP（0.232.1=TTS双预设+弹窗断点制+司忆区交互）、第四段=测试台工具版本 // ★ 0.232.1.1：跟 APP 0.232.1（CHAT-KEEP/TTS-API 用例沿用）
const AUDIT = require('./auditRules'); // ★ 0.229.26 UI 规范审计引擎（组件族断言函数库）
// ★ 0.229.23 旧服务盲区守卫：启动时记正本 server.js 的 mtime；/api/health 实时比对磁盘正本——
//   正本被更新（AI 改码/git pull）而服务未重启 → stale:true（前端标红顶栏+开跑前置确认）。
//   治本 0.229.17 事故：页面副本随旧服务同步（页面+服务同旧），0.229.21 的"页面对比服务版本"守卫全程无感知
const SELF_MTIME = (() => { try { return fs.statSync(__filename).mtimeMs; } catch (_) { return 0; } })();
function isStale() {
  try { return fs.statSync(__filename).mtimeMs > SELF_MTIME; } catch (_) { return false; }
}

// ---------- 应用界面版本号（顶栏展示用；读 APP 首页 Index.ets 的 Text('vX.Y.Z')，发版自动跟读无需手工同步） ----------
const INDEX_ETS = path.join(PROJECT, 'entry', 'src', 'main', 'ets', 'pages', 'Index.ets');
function readAppVersionName() {
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
  const { out, bad } = await sqliteQuery(serial, `select key || '|' || updated_at || '|' || length(value) from cloud_data ${where} order by key`);
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
  const a1 = await uiClickText(serial, '退出账号', { waitMs: 2000 });
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
  const hasA = /app_context_ready/.test(t); const hasB = /bundle_versioncode_valid/.test(t);
  if (finished && hasA && hasB) return { level: 'pass', note: '测试框架正常结束（ResultCode 0）+ 2 条真断言均执行（app_context_ready + bundle_versioncode_valid）' };
  if (finished && (hasA || hasB)) return { level: 'warn', note: '框架正常结束但仅命中部分用例名（可能提前中断）' };
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
  return { ok, detail: r.trim().slice(0, 200) };
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
  const timeoutMs = CFG.caseTimeoutMs || 300000;
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
async function flowPrep(ctx) {
  const devs = ctx.devices;
  const op = devs.find((d) => canUiDump(d));
  const asserts = devs.filter((d) => d !== op);
  if (!op) { ctx.log('前置', 'skip', '无 UI 操作端（需 Pad/手机在线——PC 无 UI 自动化通道，dumpLayout 平台限制）'); return null; }
  if (!asserts.length) { ctx.log('前置', 'skip', '需 ≥1 台数据断言端与操作端同时勾选（如 PC+Pad）——单端无法验证跨端传播'); return null; }
  // 操作端：冷启 + 协议 + 登录 + 同步活
  await coldStart(op.serial, 6000);
  await agreeDialogIfAny(op.serial, ctx.log);
  if ((await dumpCountText(op.serial, '已登录')).n === 0) {
    ctx.log('操作端·未登录→自动登录', 'info', `${op.label} 点头像登录（静默授权；华为授权页弹出才需人工点同意）`);
    const av = await uiClickCheckbox(op.serial, '未登录', { waitMs: 3000 });
    if (!av.ok) { ctx.log('操作端登录', 'fail', '头像定位失败——' + (av.err || '')); return null; }
    const r = await ctx.checkpoint({ label: `【人工仅授权·请看 ${op.label}】静默授权通常零点击；若弹华为授权页点「同意并继续」（登录后云同步自动开）`, deviceId: op.id,
      detect: async () => (await dumpCountText(op.serial, '已登录')).n >= 1 });
    if (r.state === 'timeout') { ctx.log('操作端登录', 'fail', '180s 内未完成授权'); return null; }
    await dismissLoginDialogs(op.serial, ctx.log);
  }
  const oc = await dbCount(op.serial, null);
  if (!(oc.ok && oc.n > 0)) { ctx.log('操作端·云同步未活', 'fail', `${op.label} cloud_data=${oc.ok ? oc.n : oc.raw} 行——登录后同步应自动开启（0.196.11）；0 行=app 侧同步链路问题（先测后修，报告不修）`); return null; }
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
async function uiDoubleClick(serial, x, y, waitMs = 2400) {
  const r = await sh(serial, `uitest uiInput doubleClick ${x} ${y}`, 15000);
  await sleep(waitMs);
  return { ok: !SH_ERR_RE.test(r), raw: r.trim().slice(0, 120) };
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
      const av = await uiClickCheckbox(serial, '未登录', { waitMs: 3000 });
      if (av.ok) ctx.log('① 自动点边栏账号头像（行首图标）', 'pass', `已点击 (${av.x},${av.y})（${av.how}——0.196.3 未登录点头像拉起登录）`);
      else ctx.log('① 头像自动定位失败', 'warn', (av.err || '') + '——请人工点边栏底部账号头像');
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
  { id: 'SYNC-DOMAIN', suite: 'sync', name: '四域双端一致（行数+键集签名）', semi: false, scope: 'cross',
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
        const nav = await navTo(op.serial, '单词库', ctx.log);
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
        const sv = await uiClickText(op.serial, '保存', { exact: true, waitMs: 2000 });
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
        const nav = await uiClickText(op.serial, '知识库', { waitMs: 2500 });
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
        const sv = await uiClickText(op.serial, '保存', { exact: true, waitMs: 2000 });
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
        const nav = await uiClickText(op.serial, '气泡树', { waitMs: 2500 });
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
        const nav = await uiClickText(op.serial, '气泡树', { waitMs: 2500 });
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
  { id: 'UI-AUDIT-DIALOGS', suite: 'ui-audit', name: '弹窗体系·B1/B2 宽度断点+B4 等宽+B5 层级色+B9 返回键+B11 键盘+B13 删除确认', semi: false, scope: 'each',
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
            await sh(serial, `uitest uiInput click ${box.xc} ${box.yc}`, 15000);
            await sleep(1800);
            // ★ 0.230.0.1 断言通道修正：键盘态 dump 抓不到 app 子树（窗口 RESIZE 后节点数 0=uitest 盲区，
            //   0.230.0 实测实锤）——"树中无保存"≠不可达。改行为验证：收键盘→弹窗须仍在+保存 bounds 可达
            //   （0.230.0 app 侧已加 Scroll+maxHeight 96%：键盘压矮窗口时弹窗收缩在键盘上方区域内）
            await sh(serial, 'uitest uiInput keyEvent Back', 15000); // 收键盘（不关弹窗——编辑器返回键拦截在第二层）
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
      // ── ④ 设置弹窗（A14 保存行等宽 + 宽度 + B9 返回键）──
      nav = await navTo(serial, '设置', ctx.log);
      if (nav.ok) {
        await sleep(1200);
        const d = await dumpAuditNodes(serial);
        artSave('UI-AUDIT-DIALOGS', `dump-settings-${dev.id}.json`, d.text);
        const c = await calOnce();
        report2(ctx, AUDIT.auditDialogButtons(d.nodes, c, '全局设置弹窗·保存行', ['保存', '返回']));
        report2(ctx, AUDIT.auditDialogButtonColor(d.nodes, c, '全局设置弹窗·保存', '保存', 'BRAND_PRIMARY'));
        await backKey('全局设置弹窗', '全局设置');
      }
      // ── ⑤ fresh 专属弹窗（协议/门禁/堆叠）非 fresh 态如实 skip（守卫基线对齐铁律 §12.11）──
      const dg = await dumpAuditNodes(serial);
      const agreed = !dg.nodes.some((n) => (n.text || '').includes('同意并继续'));
      if (agreed) ctx.log('B3/B7/B16 协议族弹窗', 'skip', '协议已同意态（非 fresh）——宽度/门禁/首启弹窗链须「全新安装」模式跑（fresh 轮覆盖，如实跳过不虚构断言）');
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
      let nav = await uiClickText(serial, '气泡树', { waitMs: 2200 });
      if (!nav.ok) {
        nav = await uiClickText(serial, '进入气泡树', { waitMs: 2600 });
      }
      ctx.log('⓪ 进入气泡树画布', nav.ok ? 'pass' : 'fail',
        nav.ok ? `已点击 (${nav.x},${nav.y})——冷启首页→画布（找对话气泡的前提）` : '「气泡树」与「进入气泡树」均未命中（可能已在画布或首页改版）');
      // ① 定位有对话的气泡（取最后一个命中=最新上层）
      const d = await dumpLayout(serial);
      const hits = findNodeBoundsAll(d.text, '条对话');
      if (!hits.length) { ctx.log('① 定位有对话的气泡', 'fail', '画布未见「N条对话」标记——先在某气泡发一条消息再跑本用例'); return; }
      const target = hits[hits.length - 1];
      ctx.log('① 定位有对话的气泡', 'pass', `(${target.x},${target.y})「${String(target.text).slice(0, 24)}」`);
      // ② 双击进对话页（0.173 双击语义）
      await uiDoubleClick(serial, target.x, target.y);
      const dc = await ctx.art.dump(`CHAT-KEEP-${dev.id}`, 'dump-chat.json', serial);
      const speak0 = (dc.text.match(/🔊|🔈/g) || []).length;
      const enterOk = speak0 >= 1;
      ctx.log('② 双击进入对话页', enterOk ? 'pass' : 'fail',
        enterOk ? `AI 消息喇叭标记×${speak0}（对话内容在屏）` : '未见消息标记（双击未生效/该气泡无 AI 回复——换气泡或先发消息）');
      if (!enterOk) return;
      // ③ 压后台：起浏览器（复刻「打开另一个APP」；华为冻结即时生效）
      const bg = await sh(serial, `aa start -b com.huawei.hmos.browser -U`, 15000);
      ctx.log('③ 打开浏览器压后台', /error:|fail/i.test(bg) ? 'warn' : 'pass', bg.trim().slice(0, 100) || 'aa start 已发（复刻用户开别的 APP）');
      await sleep(5000);
      // ④ 热回（aa start 已有实例拉回前台——非冷启，等同用户滑回来）
      await sh(serial, `aa start -a ${CFG.ability} -b ${CFG.bundle}`, 15000);
      await sleep(4500);
      // ⑤ 断言：仍在对话页且消息保留（0.232.0 修复点——云同步重建工作区不再清空 current）
      const dw = await ctx.art.dump(`CHAT-KEEP-${dev.id}`, 'dump-warm.json', serial);
      const speak1 = (dw.text.match(/🔊|🔈/g) || []).length;
      ctx.log('★热回后对话保留', speak1 >= speak0 ? 'pass' : 'fail',
        speak1 >= speak0 ? `喇叭标记 ${speak0}→${speak1}——对话原样保留（0.232.0 修复生效）`
          : `喇叭标记 ${speak0}→${speak1}——对话被清零/丢失（0.232.0 前旧病：refreshWorkspaceFromPools 清空 current.nodeID 复发）`);
      const h = await hilogErrors(serial);
      ctx.log('链路 hilog 无错误', h.ok ? (h.n === 0 ? 'pass' : 'warn') : 'warn', h.ok ? `ERROR 计数=${h.n}` : 'hilog 读取异常');
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
  { id: 'ARKUI-TEST', suite: 'arkui', name: 'ArkUI Test 设备内真断言（hypium 2 条）', semi: false, scope: 'each', builtin: true,
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      let testHap = pickTestHap();
      if (!testHap) {
        ctx.log('① 编译测试包', 'info', '首次需编译 ohosTest（可能数分钟）…');
        const b = await buildTestHap();
        if (!b.ok) { ctx.log('① 测试包编译', 'fail', b.err + (b.log ? ' | ' + String(b.log).split('\n').slice(-3).join(' ').slice(0, 300) : '')); return; }
        testHap = b.hap; ctx.log('① 测试包编译', 'pass', testHap.split('/').pop());
      } else ctx.log('① 测试包已存在', 'pass', testHap.split('/').pop() + '（复用已编译测试包）');
      const ins = await hdcSpawn(serial, ['install', '-r', testHap], 180000);
      const insOk = /successfully/.test(ins.out + ins.err);
      ctx.log('② 测试包安装到 ' + dev.id, insOk ? 'pass' : 'fail', (ins.out + ins.err).trim().slice(0, 200));
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
    return json(res, 200, { ok: true, cancelled: true });
  }
  if (u.pathname === '/api/suites') {
    const suites = {};
    const SUITE_NAME = { version: '版本核验（装机真身）', login: '账号登录（三入口×真实状态：门禁→各入口登录→退出→覆盖保留）', sync: '云同步四域数据链', syncflow: '云同步数据链·跨端编排（Pad UI 产生→PC 云端收敛；0.229.25 新增）', 'ui-audit': 'UI 规范审计（A 类页面巡检+B 类弹窗体系；0.229.26 新增）', chat: '对话稳定性（压后台热回保留；0.232.0 新增）', tts: '云端语音朗读 API（openspeech；0.232.0 新增）', arkui: 'ArkUI Test（设备内真断言）' };
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
  if (u.pathname === '/api/devices') { await autoConnectTcpDevices(); const targets = await listTargets(); return json(res, 200, { devices: await probeDevices(), running, targets }); }
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
          if (!un.ok) return json(res, 200, { mode, uninstall: un, install: null, coldStart: null, aborted: true, error: '卸载失败——已中止安装（防旧数据残留的假成功；原始输出见 uninstall.detail）' });
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
  res.writeHead(404); res.end();
}

// ---------- 启动自愈（0.229.2）：健康实例幂等复用 + 僵尸占用自动清障 ----------
// 本机实情（2026-10-12 实测）：/proc/net/tcp 用户态 Permission denied，但 hdc 本机调试口（shell uid）可读
// 且 /usr/bin/lsof 的 -t/-p 模式平台 bug（空输出/卡死）——故 PID 定位走 inode 双通道：
//   通道① pid 文件（自己旧实例）  通道② hdc shell 读 /proc/net/tcp 拿 inode → 本机扫 /proc/*/fd 匹配
const PID_FILE = path.join(ROOT, 'server.pid');
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
    console.log(`[测试台 ${VERSION}] http://127.0.0.1:${CFG.port}  正本 testing/console/  HAP=${CFG.hap}`);
    const d = syncDesktop();
    console.log(d.ok ? `[桌面交付] 测试台.html + 启动测试台.sh（双击全自动：起服务+开浏览器）→ ${CFG.desktopDir}` : `[桌面交付] 跳过：${d.reason}`);
    setTimeout(() => autoConnectTcpDevices().catch(() => { /* 尽力连，失败不影响服务 */ }), 3000);
  });
}
startListen(0);
