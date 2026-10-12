// ============================================================
// testing/console/server.js — 0.229.16（本轮纯前端：实时执行/结果双 Tab + 活动指示；server.js 仅同步版本号）
// 架构：桌面/浏览器 HTML → 本服务(127.0.0.1:8766) → spawn hdc → Pad/PC/手机
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

// ---------- 应用界面版本号（顶栏展示用；读 APP 首页 Index.ets 的 Text('vX.Y.Z')，发版自动跟读无需手工同步） ----------
const INDEX_ETS = path.join(PROJECT, 'entry', 'src', 'main', 'ets', 'pages', 'Index.ets');
function readAppVersionName() {
  try {
    const src = fs.readFileSync(INDEX_ETS, 'utf8');
    const m = src.match(/Text\('v(\d+\.\d+\.\d+)'\)/);
    return m ? 'v' + m[1] : null;
  } catch (_) { return null; }
}

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
async function dumpCountText(serial, word) {
  const d = await dumpLayout(serial);
  const n = (d.text.match(new RegExp(word, 'g')) || []).length;
  return { ok: d.ok, n, text: d.text };
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
const PREF_CANDIDATES = [
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
  const r = await sh(serial, `bm uninstall -n ${CFG.bundle}`, 60000);
  return { ok: /successfully|Uninstall/.test(r), detail: r.trim().slice(0, 200) };
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
      resolve({ state, verdict: cp.verdict });
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
  try {
    await caseDef.run({ devices, log, checkpoint, art: { save: artSave, dump: artDump } });
  } catch (e) {
    log('执行异常', 'fail', String(e));
  }
  for (const s of steps) {
    if (s.status === 'fail') { status = 'fail'; break; }
    if (s.status === 'warn') status = status === 'pass' ? 'warn' : status;
    if (s.status === 'skip' && status === 'pass') status = 'skip';
  }
  return { case: caseDef.id, name: caseDef.name, status, steps, ms: Date.now() - t0 };
}

// ---------- 用例前置助手（用例间隔离，DeepSeek P0-2） ----------
async function ensureLoggedOut(ctx, serial, deviceId, dev) {
  if (!canUiDump(dev)) return true; // PC 无 UI 通道：不预检，靠检查点文案引导
  const d = await dumpCountText(serial, '已登录');
  if (d.n === 0) return true;
  const r = await ctx.checkpoint({ label: '该设备处于已登录态，请先退出登录（头像 → 退出登录 → 确认）', deviceId,
    detect: canUiDump(dev) ? (async () => (await dumpCountText(serial, '已登录')).n === 0) : null });
  return r.state === 'done';
}
async function pollUntil(fn, timeoutMs, intervalMs = CFG.poll.intervalMs) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) { if (await fn()) return true; await sleep(intervalMs); }
  return false;
}

// ============================================================
// 用例矩阵（用户拍板范围：从零登录三入口 + 四域云同步 + 版本核验）
// ============================================================
const CASES = [
  // ---------- 功能⓪ 版本核验（用户需求 1/2：移到最上面，最先可见、可单独秒跑） ----------
  { id: 'VERSION', suite: 'version', name: '装机版本核验（假成功防线·显示真身）', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0];
      const v = await bmVersionCode(dev.serial);
      ctx.log(`${dev.label} versionCode`, v.ok ? (v.code === CFG.expectedVersionCode ? 'pass' : 'fail') : 'fail',
        v.ok ? `实际=${v.code} 期望=${CFG.expectedVersionCode}` : `bm dump 失败：${v.raw}`);
    } },

  // ---------- 功能① 账号登录（每设备各跑一遍） ----------
  { id: 'LOGIN-STATE', suite: 'login', name: '冷启三入口未登录基线', semi: false, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      const started = await coldStart(serial);
      ctx.log('冷启动', started ? 'pass' : 'fail', started ? 'aa start 成功' : 'aa start 失败');
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '三入口未登录基线'); }
      else {
        const d = await ctx.art.dump(`LOGIN-STATE-${dev.id}`, 'dump-cold.json', serial);
        const nLogin = (d.text.match(/未登录/g) || []).length;
        ctx.log('边栏/首页「未登录」基线', nLogin >= 1 ? 'pass' : 'fail', `dumpLayout 命中未登录×${nLogin}`);
      }
      const h = await hilogErrors(serial);
      ctx.log('启动 hilog 无错误', h.ok ? (h.n === 0 ? 'pass' : 'fail') : 'warn', h.ok ? `ERROR 计数=${h.n}` : 'hilog 读取异常');
    } },
  { id: 'LOGIN-AGREE', suite: 'login', name: '协议门禁（未勾选点登录须拦截）', semi: true, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '协议门禁（需观察拦截弹窗）'); return; }
      await coldStart(serial);
      const r = await ctx.checkpoint({ label: '请【不勾选协议】直接点登录按钮，观察是否弹出同意协议提示', deviceId: dev.id,
        verdict: ['pass', 'fail'], timeoutMs: 120000 });
      await ctx.art.dump(`LOGIN-AGREE-${dev.id}`, 'dump-after.json', serial);
      if (r.state === 'timeout') { ctx.log('人工确认', 'fail', '等待超时（120s）未确认'); return; }
      if (r.state === 'skipped') { ctx.log('人工确认', 'skip', '用户跳过'); return; }
      ctx.log('协议拦截（用户判定）', r.verdict === 'pass' ? 'pass' : 'fail', r.verdict === 'pass' ? '未勾选被拦截 ✓（0.226.0 门禁生效）' : '未勾选未被拦截 ✗');
    } },
  { id: 'LOGIN-HOME', suite: 'login', name: '首页入口登录（红灯位：边栏仍灰）', semi: true, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      await ensureLoggedOut(ctx, serial, dev.id, dev);
      await coldStart(serial);
      const r = await ctx.checkpoint({ label: '请【勾选协议】后从【首页登录按钮】完成华为账号授权', deviceId: dev.id,
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
    } },
  { id: 'LOGIN-SIDEBAR', suite: 'login', name: '边栏入口登录（0.217.2 同族位）', semi: true, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '边栏入口登录（核心断言为边栏 UI 翻转）'); return; }
      await ensureLoggedOut(ctx, serial, dev.id, dev);
      await coldStart(serial);
      const r = await ctx.checkpoint({ label: '请点击【边栏底部账号头像】（未登录点头像直接拉起登录）完成华为账号授权', deviceId: dev.id,
        detect: async () => (await dumpCountText(serial, '已登录')).n >= 1 });
      if (r.state === 'timeout') { ctx.log('人工授权', 'fail', '180s 内未完成授权'); return; }
      const d = await ctx.art.dump(`LOGIN-SIDEBAR-${dev.id}`, 'dump-login.json', serial);
      const logged = (d.text.match(/已登录/g) || []).length;
      ctx.log('★边栏自身转已登录', logged >= 1 ? 'pass' : 'fail', `已登录×${logged}（0.217.2 同族 bug 位：边栏入口登录后边栏自身必须翻转）`);
      const h = await hilogErrors(serial);
      ctx.log('登录链路 hilog 无错误', h.ok ? (h.n === 0 ? 'pass' : 'fail') : 'warn', h.ok ? `ERROR 计数=${h.n}` : 'hilog 读取异常');
    } },
  { id: 'LOGIN-SYNC', suite: 'login', name: '设置→云同步入口登录（红灯位：开关不自动落盘）', semi: true, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      await ensureLoggedOut(ctx, serial, dev.id);
      await coldStart(serial);
      const r = await ctx.checkpoint({ label: '请从【设置 → 云同步入口】登录（fromSyncEntry：登录成功应直接开启云同步，不再弹询问）', deviceId: dev.id,
        detect: async () => { const c = await dbCount(serial, null); return c.ok && c.n > 0; } });
      if (r.state === 'timeout') { ctx.log('人工授权', 'fail', '180s 内未完成授权/云端未见数据'); return; }
      ctx.log('人工授权完成', 'pass', r.auto ? 'cloud_data 行数>0 自动确认' : '用户点击完成');
      const c = await dbCount(serial, null);
      ctx.log('★云同步自动开启（RDB 有行）', c.ok && c.n > 0 ? 'pass' : 'fail', c.ok ? `cloud_data 总行数=${c.n}（bug 红灯位：需手动开才同步=0 行）` : `sqlite 读取异常：${c.raw}`);
      const g = await grepPref(serial, 'cloud-sync-switch');
      ctx.log('★cloud-sync-switch 落盘（尽力确认）', g.found ? 'pass' : 'warn', g.found ? `${g.path} → ${g.sample}` : '候选路径未命中（RDB 行数断言已兜底）');
      const h = await hilogErrors(serial);
      ctx.log('同步链路 hilog 无错误', h.ok ? (h.n === 0 ? 'pass' : 'fail') : 'warn', h.ok ? `ERROR 计数=${h.n}` : 'hilog 读取异常');
    } },
  { id: 'LOGIN-LOGOUT', suite: 'login', name: '退出登录（三入口复位+开关强制关）', semi: true, scope: 'each',
    run: async (ctx) => {
      const dev = ctx.devices[0]; const serial = dev.serial;
      if (!canUiDump(dev)) { uiSkip(ctx.log, dev, '退出登录（前后态均为 UI 断言）'); return; }
      const d0 = await dumpCountText(serial, '已登录');
      if (d0.n === 0) { ctx.log('前置：已登录态', 'skip', '当前未登录——请先跑任一登录用例或手动登录后再跑本用例'); return; }
      const r = await ctx.checkpoint({ label: '请点击【头像 → 退出登录 → 确认】', deviceId: dev.id,
        detect: async () => (await dumpCountText(serial, '已登录')).n === 0 });
      if (r.state === 'timeout') { ctx.log('退出操作', 'fail', '180s 内未完成退出'); return; }
      const d = await ctx.art.dump(`LOGIN-LOGOUT-${dev.id}`, 'dump-logout.json', serial);
      const unlogged = (d.text.match(/未登录/g) || []).length;
      ctx.log('三入口复位未登录', unlogged >= 1 ? 'pass' : 'fail', `未登录×${unlogged}`);
      const g = await grepPref(serial, 'cloud-sync-switch');
      ctx.log('cloud-sync-switch 强制关（尽力确认）', g.found ? 'pass' : 'warn', g.found ? `${g.path} → ${g.sample}` : '候选路径未命中');
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
function startRun(deviceIds, caseIds) {
  if (running) return { error: '已有测试在跑' };
  const devs = CFG.devices.filter((d) => deviceIds.includes(d.id));
  const cases = CASES.filter((c) => c.builtin || caseIds.includes(c.id));
  curRun = { runId: RUN_ID(), startedAt: now(), env: { versionCode: CFG.expectedVersionCode, node: process.version },
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
    for (const dev of devs) {
      const devCases = cases.filter((c) => c.scope === 'each');
      for (const c of devCases) {
        sseSend({ type: 'case-start', runId: curRun.runId, device: dev.id, case: c.id, name: c.name });
        const r = await runCase([dev], c);
        r.device = dev.id;
        curRun.runs.push(r);
        sseSend({ type: 'case-end', runId: curRun.runId, device: dev.id, result: r });
      }
    }
    for (const c of cases.filter((x) => x.scope === 'cross')) {
      sseSend({ type: 'case-start', runId: curRun.runId, device: '跨端', case: c.id, name: c.name });
      const r = await runCase(devs, c);
      r.device = 'cross';
      curRun.runs.push(r);
      sseSend({ type: 'case-end', runId: curRun.runId, device: 'cross', result: r });
    }
  } finally {
    curRun.endedAt = now();
    const cnt = (s) => curRun.runs.filter((r) => r.status === s).length;
    curRun.summary = { pass: cnt('pass'), fail: cnt('fail'), warn: cnt('warn'), skip: cnt('skip'), total: curRun.runs.length };
    saveResults(curRun);
    sseSend({ type: 'run-end', runId: curRun.runId, summary: curRun.summary });
    running = false;
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
    const stamped = html.replace('</title>', ` · 0.229.16</title>`)
      .replace('</body>', `\n<!-- testing-console 0.229.16 同源副本 ${now()} 生成，正本 testing/console/public/index.html，勿直接改本副本 -->\n</body>`);
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
  if (u.pathname === '/api/health') return json(res, 200, { ok: true, pid: process.pid, version: '0.229.16', running });
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
    const SUITE_NAME = { version: '版本核验（装机真身）', login: '账号登录（从零开始）', sync: '云同步四域数据链', arkui: 'ArkUI Test（设备内真断言）' };
    for (const c of CASES) { if (c.builtin) continue; (suites[c.suite] = suites[c.suite] || { name: SUITE_NAME[c.suite] || c.suite, cases: [] }).cases.push({ id: c.id, name: c.name, semi: c.semi, scope: c.scope }); }
    return json(res, 200, { suites, running, config: { bundle: CFG.bundle, expectedVersionCode: CFG.expectedVersionCode, appVersionName: readAppVersionName(), hap: CFG.hap } });
  }
  if (u.pathname === '/api/version') {
    const devs = await probeDevices();
    const dev = devs.find((d) => d.online) || null;
    if (!dev) return json(res, 200, { ok: false, expected: CFG.expectedVersionCode, actual: null, device: null, reason: '无在线设备（PC/Pad 未连接）' });
    const v = await bmVersionCode(dev.serial);
    return json(res, 200, { ok: v.ok && v.code === CFG.expectedVersionCode, expected: CFG.expectedVersionCode, actual: v.code, device: dev.id, label: dev.label, raw: v.raw });
  }
  if (u.pathname === '/api/devices') { await autoConnectTcpDevices(); const targets = await listTargets(); return json(res, 200, { devices: await probeDevices(), running, targets }); }
  if (u.pathname === '/api/results') return json(res, 200, loadResults());
  if (u.pathname === '/api/run' && req.method === 'POST') {
    if (running) return json(res, 409, { error: '已有测试在跑，等它结束' });
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
        const mode = p.mode === 'fresh' ? 'fresh' : 'overwrite'; // 默认覆盖安装（用户需求 6）
        let un = null;
        if (mode === 'fresh') un = await bmUninstall(dev.serial);
        const ins = await bmInstall(dev.serial, mode === 'overwrite');
        const cold = await coldStart(dev.serial, 10000);
        json(res, 200, { mode, uninstall: un, install: ins, coldStart: cold });
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
    console.log(`[测试台 0.229.16] 服务已在线（http://127.0.0.1:${CFG.port}）——自动复用，本进程退出，无需重复启动`);
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
    console.log(`[测试台 0.229.16] http://127.0.0.1:${CFG.port}  正本 testing/console/  HAP=${CFG.hap}`);
    const d = syncDesktop();
    console.log(d.ok ? `[桌面交付] 测试台.html + 启动测试台.sh（双击全自动：起服务+开浏览器）→ ${CFG.desktopDir}` : `[桌面交付] 跳过：${d.reason}`);
    setTimeout(() => autoConnectTcpDevices().catch(() => { /* 尽力连，失败不影响服务 */ }), 3000);
  });
}
startListen(0);
