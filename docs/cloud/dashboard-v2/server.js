// ============================================================
// server.js — 埋点可视化看板 v2（★ 0.260.0 后台统计监控台一期）
// ============================================================
// 入口：node server.js → http://localhost:<port>（config.json，默认 8766）
// 新增（相对 0.206.dash 版）：
//   1. 访问口令（全站 Cookie 鉴权——口令页 → /api/login → dag_dash Cookie）
//   2. JSON 按天分卷（data/data-YYYY-MM-DD.json）+ 启动载入内存聚合缓存
//      —— 查询一律走本地缓存，Cloud DB 直查仅限定时增量同步（默认 10 分钟）
//   3. SP 聚合接口 /api/sp（Tab2：消耗曲线/模型分布/uid TOP/P50P90/余额分层/发放消耗比/命中率）
//   4. 配额监控（/api/meta 内 quota：当日 events 写入行数 vs 2 万/天，60% 黄 80% 红）
//   5. 明细滚动清理（保留 90 天明细卷；更早卷文件启动时删除——汇总类数据由 Cloud DB 长期持有）
//   6. Reports API 配置位（config.reports——凭证拿到后 enabled:true 即接入，未配置时前端显示引导）
// ★ 0.273.0 毛利财务报表与看板AI助手：
//   7. /api/fin 财务+运营聚合（Tab3 转正：充值流水/token成本(峰谷单价折算 it/ot/ct)/毛利/净利/
//      11 scene 明细/用户补贴小计/0-23 时段直方/日活/留存/等级分布——等级阈值=ChatModel 实码抄录）
//   8. /api/ai/chat 看板 AI 问答助手（四提供商照抄 app 0.190.0 结构默认火山；快照注入数字锚定；
//      自身成本入账 data/ai-cost.jsonl——tencent 档折 ¥ 扣净利、其余档金额记 0）
//   9. config 新增 pricing/fixedMonthlyCostCny/aiAssistant 三段（默认值内置，零配置可用）
//   10. ★ 0.302.1.1 用户规模数据源（SpMirror+SpLedger 直拉）+ AI 快照注入：注册账号数/新手任务
//       完成数/完赛数/签到用户数/近 6 周活跃与首见周表——问「注册多少、完成新手任务多少、
//       一个月按周给我表格」AI 直接出数字/Markdown 表格（前端 mdToHtml 渲染）。
//       口径：注册=SpMirror 行数（须开云同步）；新手任务≥1=流水 src~rookie_* 去重账号；
//       完赛=src=rookie_bonus；首见周=流水上线(2026-10-23)后首次产生流水所在周。
//   11. ★ 0.302.1.3 更名「后台数据」+SP 数据台并入（自测试台平移）：/api/sp/query·command·commands·
//       ledger 四路由（直连 Cloud DB 同实例）；鉴权三通道（Cookie+X-Dash-Token 头+?k= query）——
//       治本测试台 iframe 内登不进（浏览器 SameSite 拦第三方 Cookie，token 走 localStorage 分区存储）。
// 老能力平移：GET /api/data（内存全量，前端 Tab1 热区+事件分布零改）
// 凭证：../agc-credential.json（track-events 根，绝不入 git）
// ============================================================
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { cloud, Region, CloudDBZoneGenericObject } = require('@hw-agconnect/cloud-server');

// ---------- 配置 ----------
const ROOT = __dirname;
const DATA_DIR = path.join(ROOT, 'data');
const STATE_FILE = path.join(DATA_DIR, 'state.json');
const ALIAS_FILE = path.join(DATA_DIR, 'aliases.json'); // ★ 0.302.4.2 手机号→账号ID 别名（运营绑定，仅服务器本地）

function loadAliases() {
  try {
    const j = JSON.parse(fs.readFileSync(ALIAS_FILE, 'utf-8'));
    return j && typeof j === 'object' ? j : {};
  } catch (_e) { return {}; }
}
function saveAliases(m) {
  try {
    if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
    fs.writeFileSync(ALIAS_FILE, JSON.stringify(m, null, 2));
    return true;
  } catch (_e) { return false; }
}
let CFG = {
  port: 8766,
  password: 'changeme',        // ★ 部署后必改（部署指引第 3 步）
  spCostPer10kCny: 0.05,       // 每 1 万 SP 对应成本 ¥（调参改配置不改码；app 内禁 ¥-SP 换算不受限）
  dailyWriteQuota: 20000,      // Cloud DB 免费配额写 2 万次/天（口径=events 当日行数）
  quotaYellowPct: 60,
  quotaRedPct: 80,
  syncIntervalMs: 10 * 60 * 1000, // 10 分钟增量同步（保护读配额 5 万/天）
  detailRetainDays: 90,
  reports: { enabled: false, clientId: '', clientSecret: '', appId: '' }, // Connect API 凭证（开发者级凭证→API客户端创建；appId=应用 APP ID）
  // ★ 0.273.0 毛利财务（任务书 D3/D7）：单价表元/百万tokens（闲/峰两档）+ 闲时段（北京时间 [时,分]）+
  //   固定月成本按天分摊；per-model 覆盖位预留 pricing["模型名"]（当前主力走 default）
  pricing: {
    default: { inOffPeak: 1, inPeak: 2, outOffPeak: 4, outPeak: 8, cacheOffPeak: 0.02, cachePeak: 0.04 },
    offPeakHours: [[0, 30], [9, 30]]
  },
  fixedMonthlyCostCny: 0,
  aiAssistant: { provider: 'volcano', apiKey: '', customEndpoint: '', customModel: '' } // 四档=volcano/deepseek/tencent/custom；key 只存服务器 config.json（gitignore，同 password 纪律）
};
try {
  const c = JSON.parse(fs.readFileSync(path.join(ROOT, 'config.json'), 'utf-8'));
  CFG = Object.assign(CFG, c);
} catch (_e) { /* 无 config.json 用默认 */ }

// ★ Reports API（华为 AI 2026-10-19 回复实锤 + 本机实测校正）：
//   token：POST https://connect-api.cloud.huawei.com/api/oauth2/v1/token（JSON，48h 有效）
//   报表：GET https://connect-api.cloud.huawei.com/api/report/harmony-report/v1/harmony/{接口}/{appId}
//         双请求头 Authorization: Bearer + client_id；窗口≤180 天，UTC YYYYMMDD；响应含 fileURL 下载 CSV
//   ⚠️ 项目设置→常规的 Client ID/Secret 是应用级凭证——实测调 Reports 报「client id or secret error」，
//     必须用「开发者中心→开发者管理→ID、证书和Profile→凭证→开发者级凭证→API客户端凭证」创建的一套
const REPORT_API = 'https://connect-api.cloud.huawei.com';
let rptToken = '', rptTokenExp = 0;

function rptCfgOk() { return !!(CFG.reports && CFG.reports.enabled && CFG.reports.clientId && CFG.reports.clientSecret && CFG.reports.appId); }

async function getRptToken() {
  if (rptToken && Date.now() < rptTokenExp) return rptToken;
  const body = JSON.stringify({ grant_type: 'client_credentials', client_id: CFG.reports.clientId, client_secret: CFG.reports.clientSecret });
  const r = await new Promise((resolve) => {
    const u = new URL(REPORT_API + '/api/oauth2/v1/token');
    const req = require('https').request({ hostname: u.hostname, path: u.pathname, method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) } }, (res) => {
      let d = ''; res.on('data', c => d += c); res.on('end', () => resolve({ code: res.statusCode, body: d }));
    });
    req.on('error', () => resolve({ code: 0, body: '' }));
    req.end(body);
  });
  try {
    const j = JSON.parse(r.body);
    if (j.access_token) {
      rptToken = j.access_token;
      rptTokenExp = Date.now() + ((Number(j.expires_in) || 172800) * 1000) - 300000;
      return rptToken;
    }
    throw new Error('auth: ' + (j.ret && j.ret.msg ? j.ret.msg : r.body.slice(0, 120)));
  } catch (e) { throw new Error('token 失败——凭证无效或网络异常：' + e.message); }
}

function httpGet(url, headers) {
  return new Promise((resolve, reject) => {
    const req = require('https').request(url, { method: 'GET', headers: headers || {} }, (res) => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve({ code: res.statusCode, buf: Buffer.concat(chunks), location: res.headers.location || '' }));
    });
    req.on('error', reject);
    req.end();
  });
}

// 拉一类报表 → fileURL → 下载 CSV → 存 data/reports/ 并解析（首行表头）
async function pullReport(kind, startDay, endDay) {
  const token = await getRptToken();
  const url = REPORT_API + '/api/report/harmony-report/v1/harmony/' + kind + '/' + CFG.reports.appId +
    '?language=zh-CN&startTime=' + startDay + '&endTime=' + endDay;
  const r = await httpGet(url, { 'Authorization': 'Bearer ' + token, 'client_id': CFG.reports.clientId });
  if (r.code !== 200) throw new Error(kind + ' 接口 HTTP ' + r.code + '：' + r.buf.toString('utf-8').slice(0, 150));
  let j = null;
  try { j = JSON.parse(r.buf.toString('utf-8')); } catch (_e) { throw new Error(kind + ' 响应非 JSON'); }
  if (!j.fileURL) throw new Error(kind + ' 无 fileURL：' + JSON.stringify(j).slice(0, 200));
  // 下载 CSV（先裸下载，403 再带 token 重试）
  let f = await httpGet(j.fileURL, {});
  if (f.code !== 200) f = await httpGet(j.fileURL, { 'Authorization': 'Bearer ' + token });
  if (f.code !== 200) throw new Error(kind + ' CSV 下载 HTTP ' + f.code);
  let text = f.buf.toString('utf-8');
  if (text.charCodeAt(0) === 0xFEFF) text = text.slice(1); // 去 BOM
  const lines = text.split(/\r?\n/).filter(x => x.trim() !== '');
  const header = lines.length ? lines[0].split(',') : [];
  const rows = lines.slice(1).map(x => x.split(','));
  if (!fs.existsSync(path.join(DATA_DIR, 'reports'))) fs.mkdirSync(path.join(DATA_DIR, 'reports'), { recursive: true });
  fs.writeFileSync(path.join(DATA_DIR, 'reports', kind + '.csv'), text);
  return { kind, startDay, endDay, pulledAt: Date.now(), header, rows };
}

async function pullAllReports() {
  const today = new Date(Date.now() - 864e5); // 昨天为止（当天数据未结算）
  const end = today.getFullYear() + String(today.getMonth() + 1).padStart(2, '0') + String(today.getDate()).padStart(2, '0');
  const s = new Date(today.getTime() - 29 * 864e5); // 近 30 天窗
  const start = s.getFullYear() + String(s.getMonth() + 1).padStart(2, '0') + String(s.getDate()).padStart(2, '0');
  const out = { ok: true, pulledAt: Date.now(), appDownload: null, userAnalysis: null, error: null };
  try { out.appDownload = await pullReport('appDownloadAnalysisExport', start, end); } catch (e) { out.error = String(e.message || e); }
  try { out.userAnalysis = await pullReport('userAnalysisExport', start, end); } catch (e) { if (out.error) out.error += ' | '; out.error = (out.error || '') + String(e.message || e); }
  // ★ 报表目录兜底：两接口都失败时 pullReport 不会建目录，直接写 last.json 会 ENOENT 崩服务（重启风暴）
  if (!fs.existsSync(path.join(DATA_DIR, 'reports'))) fs.mkdirSync(path.join(DATA_DIR, 'reports'), { recursive: true });
  fs.writeFileSync(path.join(DATA_DIR, 'reports', 'last.json'), JSON.stringify(out));
  return out;
}

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.png': 'image/png', '.jpg': 'image/jpeg'
};

// ---------- 鉴权（口令 → 固定 token Cookie，重启不掉线） ----------
const TOKEN = crypto.createHash('sha256').update(String(CFG.password) + '::dagai-dash').digest('hex');

function cookieToken(req) {
  const m = /dag_dash=([0-9a-f]+)/.exec(req.headers.cookie || '');
  return m ? m[1] : '';
}
function authed(req) {
  // ★ 0.302.1.3 三通道：Cookie（顶级窗口直开）+ X-Dash-Token 头（iframe 内 fetch——第三方 Cookie 被
  //   浏览器 SameSite 拦截，token 存 iframe 分区 localStorage）+ ?k= query（登录后跳转/iframe 首开）
  if (req.headers['x-dash-token'] === TOKEN) return true;
  const u = req.url || '';
  const qi = u.indexOf('?k=');
  if (qi >= 0 && u.slice(qi + 3, qi + 3 + TOKEN.length) === TOKEN) return true;
  return cookieToken(req) === TOKEN;
}

// ---------- Cloud DB（★ 阿里云部署适配：凭证路径可配 + 缺凭证降级不崩服务——Reports 不受影响） ----------
let dbInst = null;
let dbFailed = false;

function getDb() {
  if (dbFailed) {
    return null;
  }
  if (dbInst) {
    return dbInst;
  }
  try {
    const credPath = CFG.agcCredentialPath ? path.resolve(ROOT, CFG.agcCredentialPath) : path.join(ROOT, '..', 'agc-credential.json');
    dbInst = cloud.createInstance(credPath, 'dash', Region.REGION_CN).database({ zoneName: 'default' });
  } catch (e) {
    dbFailed = true;
    console.log('[dash] AGC 凭证缺失/不可读（' + (e && e.message ? e.message : String(e)) + '）——events 同步停用，Reports 拉取不受影响');
    return null;
  }
  return dbInst;
}

// ---------- 内存缓存 + 分卷 ----------
// key=`e|t`（与云函数复合主键同构——重拉幂等去重）
const MEM = new Map();
let lastSyncT = 0;
let lastSyncAt = 0;
let lastLedgerT = 0; // ★ 0.302.1.1：SpLedger 增量游标（与 lastSyncT 同 state.json 持久化）

function dayKey(t) { const d = new Date(t); return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); }

function volPath(day) { return path.join(DATA_DIR, 'data-' + day + '.json'); }

function loadVolumes() {
  if (!fs.existsSync(DATA_DIR)) { fs.mkdirSync(DATA_DIR, { recursive: true }); }
  // state
  try { const s = JSON.parse(fs.readFileSync(STATE_FILE, 'utf-8')); lastSyncT = Number(s.lastSyncT) || 0; lastLedgerT = Number(s.lastLedgerT) || 0; } catch (_e) {}  // 明细卷（90 天滚动）
  const cutoff = Date.now() - CFG.detailRetainDays * 864e5;
  let removed = 0;
  for (const f of fs.readdirSync(DATA_DIR)) {
    const m = /^data-(\d{4})-(\d{2})-(\d{2})\.json$/.exec(f);
    if (!m) continue;
    const day = m[1] + '-' + m[2] + '-' + m[3];
    const ts = new Date(day + 'T00:00:00').getTime();
    if (ts < cutoff) { try { fs.unlinkSync(path.join(DATA_DIR, f)); removed++; } catch (_e) {} continue; }
    try {
      const arr = JSON.parse(fs.readFileSync(path.join(DATA_DIR, f), 'utf-8'));
      for (const ev of arr) MEM.set(ev.e + '|' + ev.t, ev);
    } catch (_e) { /* 坏卷跳过 */ }
  }
  console.log('[dash] volumes loaded: ' + MEM.size + ' rows' + (removed ? ' (pruned ' + removed + ' old files)' : ''));
}

function persistDay(day) {
  // 落当日卷（原子写 tmp→rename）
  const rows = [];
  for (const ev of MEM.values()) if (dayKey(ev.t) === day) rows.push(ev);
  const tmp = volPath(day) + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(rows));
  fs.renameSync(tmp, volPath(day));
}

async function syncFromCloud() {
  const db = getDb();
  if (!db) {
    return;
  }
  try {
    // ★ 2001018 教训：Cloud DB 单次 query 上限 1000 条——正序分页翻页（游标=页内最大 t，
    //   >= 边界重拉由 e|t Map 去重吸收；60 轮=6 万条上限）
    let round = 0;
    let added = 0;
    while (round < 60) {
      const coll = db.collection('events');
      const arr = await coll.query().greaterThanOrEqualTo('t', lastSyncT).orderByAsc('t').limit(1000).get();
      let pageMax = lastSyncT;
      const touched = new Set();
      for (const o of arr) {
        const ev = { e: String(o.getFieldValue('e') || ''), p: String(o.getFieldValue('p') || ''), t: Number(o.getFieldValue('t') || 0) };
        if (MEM.has(ev.e + '|' + ev.t)) continue;
        MEM.set(ev.e + '|' + ev.t, ev);
        if (ev.t > pageMax) pageMax = ev.t;
        touched.add(dayKey(ev.t));
        added++;
      }
      for (const day of touched) persistDay(day);
      lastSyncT = Math.max(lastSyncT, pageMax);
      fs.writeFileSync(STATE_FILE, JSON.stringify({ lastSyncT: lastSyncT }));
      if (arr.length < 1000) break;
      round++;
    }
    lastSyncAt = Date.now();
    console.log('[dash] sync +' + added + ' rows, total ' + MEM.size + ', lastT=' + lastSyncT);
    await syncUsers(db); // ★ 0.302.1.1：SpMirror+SpLedger 同节奏拉取（10 分钟）
  } catch (e) {
    console.log('[dash] sync fail: ' + (e && e.message ? e.message : String(e)));
  }
}

// ---------- ★ 0.302.1.1 用户规模数据源（SpMirror + SpLedger → AI 快照） ----------
const MIRROR = new Map(); // accountId -> {availableSp, frozenSp, reportedAt, deviceModel}
const LEDGER = new Map(); // id -> {accountId, ts, event, src, amount}（裁剪保近 180 天）
const LEDGER_RETAIN_MS = 180 * 864e5;

async function syncUsers(db) {
  try {
    // SpMirror 全量（账号量级小；objectId 主键游标翻页）
    let round = 0;
    while (round < 10) {
      const coll = db.collection('SpMirror');
      let q = coll.query().orderByAsc('objectId').limit(1000);
      if (MIRROR.size > 0) {
        const cursor = MIRROR.get('_cursor_') || '';
        if (cursor) q = coll.query().greaterThan('objectId', cursor).orderByAsc('objectId').limit(1000);
      }
      const arr = await q.get();
      let maxId = '';
      for (const o of arr) {
        const id = String(o.getFieldValue('objectId') || '');
        if (!id || id === '_cursor_') continue;
        MIRROR.set(id, {
          availableSp: Number(o.getFieldValue('availableSp')) || 0,
          frozenSp: Number(o.getFieldValue('frozenSp')) || 0,
          reportedAt: Number(o.getFieldValue('reportedAt')) || 0,
          deviceModel: String(o.getFieldValue('deviceModel') || '')
        });
        if (id > maxId) maxId = id;
      }
      if (maxId) MIRROR.set('_cursor_', maxId);
      if (arr.length < 1000) break;
      round++;
    }
    // SpLedger 增量（ts 游标，照抄 events 分页模式）
    let lRound = 0;
    let lAdded = 0;
    while (lRound < 30) {
      const coll = db.collection('SpLedger');
      const arr = await coll.query().greaterThanOrEqualTo('ts', lastLedgerT).orderByAsc('ts').limit(1000).get();
      let pageMax = lastLedgerT;
      for (const o of arr) {
        const id = String(o.getFieldValue('objectId') || '');
        const ts = Number(o.getFieldValue('ts')) || 0;
        if (!id || LEDGER.has(id)) continue;
        LEDGER.set(id, { accountId: String(o.getFieldValue('accountId') || ''), ts: ts, event: String(o.getFieldValue('event') || ''), src: String(o.getFieldValue('src') || ''), amount: Number(o.getFieldValue('amount')) || 0 });
        if (ts > pageMax) pageMax = ts;
        lAdded++;
      }
      lastLedgerT = Math.max(lastLedgerT, pageMax);
      if (arr.length < 1000) break;
      lRound++;
    }
    // 裁剪：只保近 180 天流水（量有界）
    const ledgerCutoff = Date.now() / 1000 - LEDGER_RETAIN_MS / 1000;
    for (const [id, e] of LEDGER) if (e.ts < ledgerCutoff) LEDGER.delete(id);
    fs.writeFileSync(STATE_FILE, JSON.stringify({ lastSyncT: lastSyncT, lastLedgerT: lastLedgerT }));
    console.log('[dash] users sync: mirrors=' + (MIRROR.size - 1) + ' ledger+' + lAdded + ' total=' + LEDGER.size);
  } catch (e) {
    console.log('[dash] users sync fail: ' + (e && e.message ? e.message : String(e)));
  }
}

function weekKeyTs(tsMs) {
  // ISO 周标签（周一为一周起点）：YYYY-Www
  const d = new Date(tsMs);
  const day = (d.getDay() + 6) % 7; // 周一=0
  const monday = new Date(d.getFullYear(), d.getMonth(), d.getDate() - day);
  const y = monday.getFullYear();
  const jan4 = new Date(y, 0, 4);
  const jan4Day = (jan4.getDay() + 6) % 7;
  const week1Mon = new Date(y, 0, 4 - jan4Day);
  const wk = Math.floor((monday - week1Mon) / 6048e5) + 1;
  return y + '-W' + String(wk).padStart(2, '0');
}

function usersAggregate() {
  const totalAccounts = Math.max(0, MIRROR.size - 1); // 减游标伪行
  const rookie = new Set();
  const rookieFinal = new Set();
  const signUsers = new Set();
  const firstSeen = new Map(); // accountId -> min ts
  const weeks = new Map();     // weekKey -> {active:Set, firstSeen:Set, grant, consume}
  for (let i = 5; i >= 0; i--) {
    weeks.set(weekKeyTs(Date.now() - i * 6048e5), { active: new Set(), firstSeen: new Set(), grant: 0, consume: 0 });
  }
  for (const e of LEDGER.values()) {
    if (!e.accountId) continue;
    if (e.src && e.src.indexOf('rookie_') === 0) rookie.add(e.accountId);
    if (e.src === 'rookie_bonus') rookieFinal.add(e.accountId);
    if (e.src === 'sign') signUsers.add(e.accountId);
    const prev = firstSeen.get(e.accountId);
    if (prev === undefined || e.ts < prev) firstSeen.set(e.accountId, e.ts);
    const wk = weekKeyTs(e.ts * 1000);
    const w = weeks.get(wk);
    if (w) {
      w.active.add(e.accountId);
      if (e.event === 'grant') w.grant += Math.abs(e.amount); else if (e.event === 'consume') w.consume += Math.abs(e.amount);
    }
  }
  for (const [acc, ts] of firstSeen) {
    const w = weeks.get(weekKeyTs(ts * 1000));
    if (w) w.firstSeen.add(acc);
  }
  const weekList = [];
  for (const [k, w] of weeks) weekList.push({ week: k, active: w.active.size, firstSeen: w.firstSeen.size, grantSp: w.grant, consumeSp: w.consume });
  return {
    totalAccounts: totalAccounts,
    rookieTouched: rookie.size,
    rookieFinal: rookieFinal.size,
    signUsers: signUsers.size,
    ledgerSince: '2026-10-23',
    weeks: weekList
  };
}

// ---------- SP 聚合（Tab2 数据源，服务端算好前端只渲染） ----------
function parseP(p) { try { return JSON.parse(p || '{}'); } catch (_e) { return {}; } }

function spAggregate() {
  const today = dayKey(Date.now());
  const dayAgg = new Map();   // day -> {consume, grant}
  const modelAgg = new Map(); // model -> consume
  const uidDay = new Map();   // uid|day -> consume（P50/P90 人均日消耗）
  const uidBal = new Map();   // uid -> {bal, t}（取最新）
  const uidSp = new Map();    // uid -> consume 累计（TOP 榜）
  const hitBuckets = [0, 0, 0, 0, 0]; // 0% / 1-20 / 21-50 / 51-80 / 81-100
  const grantSrc = new Map(); // src -> grant
  const sceneAgg = new Map(); // sc -> {sp, cnt}（★ 0.272.0 按场景拆分：chat/regen/word/extract/encourage_r/encourage_s）
  let consumeTotal = 0, grantTotal = 0, consumeToday = 0, grantToday = 0;
  let consumeCnt = 0;

  for (const ev of MEM.values()) {
    if (ev.e !== 'sp_consume' && ev.e !== 'sp_grant') continue;
    const p = parseP(ev.p);
    const day = dayKey(ev.t);
    const d = dayAgg.get(day) || { consume: 0, grant: 0 };
    if (ev.e === 'sp_consume') {
      const sp = Number(p.sp) || 0;
      d.consume += sp; consumeTotal += sp; consumeCnt++;
      if (day === today) consumeToday += sp;
      const m = p.m || '(unknown)';
      modelAgg.set(m, (modelAgg.get(m) || 0) + sp);
      const sc = p.sc || '?';
      const scAgg = sceneAgg.get(sc) || { sp: 0, cnt: 0, free: 0 };
      scAgg.sp += sp; scAgg.cnt++;
      if (p.f === 'y') scAgg.free++; // 免扣照报行（encourage_*/Lv8）单独计数
      sceneAgg.set(sc, scAgg);
      const uid = p.id || '?';
      const uk = uid + '|' + day;
      uidDay.set(uk, (uidDay.get(uk) || 0) + sp);
      uidSp.set(uid, (uidSp.get(uid) || 0) + sp);
      const bal = Number(p.bal);
      if (!isNaN(bal) && (!uidBal.has(uid) || ev.t >= uidBal.get(uid).t)) uidBal.set(uid, { bal: bal, t: ev.t });
      const h = Number(p.h) || 0;
      hitBuckets[h <= 0 ? 0 : h <= 20 ? 1 : h <= 50 ? 2 : h <= 80 ? 3 : 4]++;
    } else {
      const sp = Number(p.sp) || 0;
      d.grant += sp; grantTotal += sp;
      if (day === today) grantToday += sp;
      const src = p.src || '?';
      grantSrc.set(src, (grantSrc.get(src) || 0) + sp);
      // 发放行 bal 同样刷新 uid 最新余额
      const uid = p.id || '?';
      const bal = Number(p.bal);
      if (!isNaN(bal) && (!uidBal.has(uid) || ev.t >= uidBal.get(uid).t)) uidBal.set(uid, { bal: bal, t: ev.t });
    }
    dayAgg.set(day, d);
  }

  // P50/P90 人均日消耗（按 uid×day 分布取分位）
  const perUserDay = [...uidDay.values()].sort((a, b) => a - b);
  function pct(q) {
    if (perUserDay.length === 0) return 0;
    const i = Math.min(perUserDay.length - 1, Math.floor(q * perUserDay.length));
    return perUserDay[i];
  }

  // 余额分层直方图（0 / 1-10万 / 10-50万 / 50万+）
  const balBuckets = [0, 0, 0, 0];
  for (const v of uidBal.values()) {
    balBuckets[v.bal <= 0 ? 0 : v.bal < 100000 ? 1 : v.bal < 500000 ? 2 : 3]++;
  }

  // 日序列（近 90 天，升序）
  const days = [...dayAgg.keys()].sort().slice(-90);
  const series = days.map(d => ({ day: d, consume: dayAgg.get(d).consume, grant: dayAgg.get(d).grant, ratio: dayAgg.get(d).consume > 0 ? +(dayAgg.get(d).grant / dayAgg.get(d).consume).toFixed(2) : null }));

  const uidTop = [...uidSp.entries()].sort((a, b) => b[1] - a[1]).slice(0, 10).map(x => ({ uid: x[0], sp: x[1] }));
  const cny = +(consumeTotal / 10000 * CFG.spCostPer10kCny).toFixed(2);
  const cnyToday = +(consumeToday / 10000 * CFG.spCostPer10kCny).toFixed(2);

  return {
    ok: true,
    summary: { consumeTotal, grantTotal, consumeToday, grantToday, cny, cnyToday, consumeCnt, spCostPer10kCny: CFG.spCostPer10kCny },
    series, uidTop,
    models: [...modelAgg.entries()].sort((a, b) => b[1] - a[1]).map(x => ({ model: x[0], sp: x[1] })),
    scenes: [...sceneAgg.entries()].sort((a, b) => b[1].sp - a[1].sp).map(x => ({ scene: x[0], sp: x[1].sp, cnt: x[1].cnt, free: x[1].free })), // ★ 0.272.0 按场景拆分
    grantSrc: [...grantSrc.entries()].sort((a, b) => b[1] - a[1]).map(x => ({ src: x[0], sp: x[1] })),
    p50: pct(0.5), p90: pct(0.9),
    balBuckets, hitBuckets
  };
}

// ---------- 配额监控（Tab4） ----------
function quotaStatus() {
  const today = dayKey(Date.now());
  let n = 0;
  for (const ev of MEM.values()) if (dayKey(ev.t) === today) n++;
  const pct = CFG.dailyWriteQuota > 0 ? +(n / CFG.dailyWriteQuota * 100).toFixed(1) : 0;
  const level = pct >= CFG.quotaRedPct ? 'red' : pct >= CFG.quotaYellowPct ? 'yellow' : 'green';
  return { todayRows: n, quota: CFG.dailyWriteQuota, pct: pct, level: level, yellowPct: CFG.quotaYellowPct, redPct: CFG.quotaRedPct,
    note: '口径=events 表当日行数（云函数 e+t 复合主键 upsert 幂等，重试不增行）；日活破 500 触发 B 案小时聚合后此口径不变' };
}

// ============================================================
// ★ 0.273.0 毛利财务与运营聚合（Tab3 转正 + AI 助手快照数据源）
// ============================================================
// 等级阈值（ChatModel.siyiLevelTitle 实码抄录——Lv2~Lv8 门槛天数；任务书草稿阈值有误以此为准）
const LEVEL_DAYS = [7, 30, 90, 150, 210, 240, 365];
function levelOf(ld) { for (let i = LEVEL_DAYS.length - 1; i >= 0; i--) if (ld >= LEVEL_DAYS[i]) return i + 2; return 1; }

// 闲时判定（事件时间戳北京时间——服务器本地即北京；offPeakHours=[[时,分],[时,分]] 闭开区间）
function isOffPeak(t) {
  const oh = (CFG.pricing && CFG.pricing.offPeakHours) || [[0, 30], [9, 30]];
  const d = new Date(t);
  const mins = d.getHours() * 60 + d.getMinutes();
  const s = (oh[0] && oh[0][0] || 0) * 60 + (oh[0] && oh[0][1] || 0);
  const e = (oh[1] && oh[1][0] || 9) * 60 + (oh[1] && oh[1][1] || 30);
  return mins >= s && mins < e;
}

// 单事件 token 成本折算（任务书 D3：cost=(it−ct)×输入价 + ct×缓存价 + ot×输出价，元/百万tokens）
function eventCostCny(t, modelName, it, ot, ct) {
  const table = (CFG.pricing && (CFG.pricing[modelName] || CFG.pricing.default)) || { inOffPeak: 1, inPeak: 2, outOffPeak: 4, outPeak: 8, cacheOffPeak: 0.02, cachePeak: 0.04 };
  const off = isOffPeak(t);
  const miss = Math.max(0, it - ct);
  return (miss * (off ? table.inOffPeak : table.inPeak) + ct * (off ? table.cacheOffPeak : table.cachePeak) + ot * (off ? table.outOffPeak : table.outPeak)) / 1e6;
}

// AI 助手自身成本账本（data/ai-cost.jsonl：date/provider/it/ot/cost 每行一笔）
function aiCostPath() { return path.join(DATA_DIR, 'ai-cost.jsonl'); }
function appendAiCost(rec) {
  try { fs.appendFileSync(aiCostPath(), JSON.stringify(rec) + '\n'); } catch (_e) {}
}
function loadAiCosts() {
  const out = [];
  try {
    for (const line of fs.readFileSync(aiCostPath(), 'utf-8').split(/\r?\n/)) {
      if (!line.trim()) continue;
      try { out.push(JSON.parse(line)); } catch (_e) {}
    }
  } catch (_e) {}
  return out;
}

// 区间起点（今日0点 / 近7天 / 近30天——D4 日/周/月，年不做）
function rangeStart(range) {
  const d = new Date(); d.setHours(0, 0, 0, 0);
  if (range === 'day') return d.getTime();
  d.setDate(d.getDate() - (range === 'week' ? 6 : 29));
  return d.getTime();
}

// 财务+运营总聚合（/api/fin 数据源；AI 快照同源——两口径天然一致）
function finAggregate(range) {
  const rs = rangeStart(range);
  const today = dayKey(Date.now());
  let recharge = 0, rechargeCnt = 0;          // 充值流水（sp_grant src=iap amt 求和——现金口径只认真收到的钱）
  let tokenCost = 0, tokenCostRows = 0;       // token 成本（新字段行折算）
  let subsidyCost = 0;                        // 用户补贴成本（encourage_* + Lv8 f:y 行）
  let spConsume = 0, spConsumeFree = 0;
  const sceneAgg = new Map();                 // sc -> {cnt, it, ot, ct, sp, cny, free, freeCny}
  const hourBuckets = new Array(24).fill(0);  // 0-23 使用时段直方（sp_consume 行数）
  let effFrom = '';                           // it/ot/ct 生效日（老行无字段=成本报表累计起点）
  // 运营：日活/留存/等级
  const dailyDay = new Map();                 // day -> Set(uid)（app_daily）
  const firstDay = new Map();                 // uid -> 首现日（app_first 全期）
  const latestLd = new Map();                 // uid -> 最新 ld（app_daily 全期取最新）
  const activeToday = new Set();              // 今日活跃 uid（含 app_daily）
  let wau = new Set();                        // 区间活跃 uid

  for (const ev of MEM.values()) {
    const p = parseP(ev.p);
    const day = dayKey(ev.t);
    if (ev.e === 'sp_consume') {
      const sp = Number(p.sp) || 0;
      const sc = p.sc || '?';
      const hasTok = p.it !== undefined || p.ot !== undefined || p.ct !== undefined;
      let cny = 0;
      if (hasTok) {
        const it = Number(p.it) || 0, ot = Number(p.ot) || 0, ct = Number(p.ct) || 0;
        cny = eventCostCny(ev.t, p.m || '', it, ot, ct);
        tokenCost += cny; tokenCostRows++;
        if (!effFrom || day < effFrom) effFrom = day;
      }
      const isSubsidy = sc === 'encourage_r' || sc === 'encourage_s' || p.f === 'y';
      if (isSubsidy) subsidyCost += cny;
      if (ev.t >= rs) {
        spConsume += sp;
        if (p.f === 'y') spConsumeFree++;
        const sa = sceneAgg.get(sc) || { cnt: 0, it: 0, ot: 0, ct: 0, sp: 0, cny: 0, free: 0 };
        sa.cnt++; sa.sp += sp; sa.cny += cny;
        if (hasTok) { sa.it += Number(p.it) || 0; sa.ot += Number(p.ot) || 0; sa.ct += Number(p.ct) || 0; }
        if (p.f === 'y') sa.free++;
        sceneAgg.set(sc, sa);
        const h = new Date(ev.t).getHours();
        hourBuckets[h]++;
        if (p.id) wau.add(p.id);
      }
    } else if (ev.e === 'sp_grant' && p.src === 'iap' && ev.t >= rs) {
      const amt = parseFloat(p.amt);
      if (!isNaN(amt) && amt > 0) { recharge += amt; rechargeCnt++; }
    } else if (ev.e === 'app_daily') {
      const uid = p.id || '?';
      if (!dailyDay.has(day)) dailyDay.set(day, new Set());
      dailyDay.get(day).add(uid);
      const ld = Number(p.ld) || 0;
      if (!latestLd.has(uid) || ev.t >= (latestLd.get(uid).t || 0)) latestLd.set(uid, { ld: ld, t: ev.t });
      if (day === today) activeToday.add(uid);
      if (ev.t >= rs && p.id) wau.add(p.id);
    } else if (ev.e === 'app_first') {
      const uid = p.id || '?';
      if (!firstDay.has(uid) || day < firstDay.get(uid)) firstDay.set(uid, day);
    }
  }

  // AI 助手成本（区间+全期累计；tencent 档才有金额——D7.4 计价规则）
  const costs = loadAiCosts();
  let aiCostRange = 0, aiItRange = 0, aiOtRange = 0, aiCostTotal = 0, aiItTotal = 0, aiOtTotal = 0, aiCntTotal = 0;
  for (const c of costs) {
    const ct2 = new Date(c.date + 'T00:00:00').getTime() || 0;
    aiCostTotal += Number(c.cost) || 0; aiItTotal += Number(c.it) || 0; aiOtTotal += Number(c.ot) || 0; aiCntTotal++;
    if (ct2 >= rs) { aiCostRange += Number(c.cost) || 0; aiItRange += Number(c.it) || 0; aiOtRange += Number(c.ot) || 0; }
  }

  // 固定成本分摊（月费×1/30 天；周×7/30；月×1）
  const fixed = Number(CFG.fixedMonthlyCostCny) || 0;
  const fixedShare = range === 'day' ? fixed / 30 : range === 'week' ? fixed * 7 / 30 : fixed;

  // 毛利/净利（现金口径：毛利=充值−token成本；净利=毛利−固定成本−AI助手成本）
  const gross = +(recharge - tokenCost).toFixed(2);
  const net = +(gross - fixedShare - aiCostRange).toFixed(2);

  // 日活曲线（升序 90 天）+ 次日/7 日留存（app_first cohort × app_daily——分母=注册日活跃 uid，分子=D+1/D+7 仍活跃）
  const days = [...dailyDay.keys()].sort().slice(-90);
  const dauSeries = days.map(d => ({ day: d, dau: dailyDay.get(d).size }));
  let r1 = null, r7 = null, cohort1 = 0, hit1 = 0, cohort7 = 0, hit7 = 0;
  const dayTs = (d) => new Date(d + 'T00:00:00').getTime();
  for (const [uid, fd] of firstDay.entries()) {
    const activeFd = dailyDay.has(fd) && dailyDay.get(fd).has(uid);
    if (!activeFd) continue; // 分母=app_first 注册日当天有 app_daily 活跃
    cohort1++; cohort7++;
    const d1 = dayKey(dayTs(fd) + 864e5), d7 = dayKey(dayTs(fd) + 7 * 864e5);
    if (dailyDay.has(d1) && dailyDay.get(d1).has(uid)) hit1++;
    if (dailyDay.has(d7) && dailyDay.get(d7).has(uid)) hit7++;
  }
  if (cohort1 > 0) r1 = +(hit1 / cohort1 * 100).toFixed(1);
  if (cohort7 > 0) r7 = +(hit7 / cohort7 * 100).toFixed(1);

  // 等级分布直方（Lv1~Lv8：uid 最新 ld → 阈值表）
  const lvBuckets = new Array(8).fill(0);
  for (const v of latestLd.values()) lvBuckets[levelOf(v.ld) - 1]++;

  return {
    ok: true, range,
    summary: { recharge: +recharge.toFixed(2), rechargeCnt, tokenCost: +tokenCost.toFixed(4), tokenCostRows,
      gross, fixedShare: +fixedShare.toFixed(2), aiCostRange: +aiCostRange.toFixed(4), net,
      spConsume, spConsumeFree, subsidyCost: +subsidyCost.toFixed(4), effFrom,
      wau: wau.size, dau: activeToday.size, retainNext: r1, retain7: r7, cohort1, cohort7 },
    scenes: [...sceneAgg.entries()].sort((a, b) => b[1].cny - a[1].cny).map(x => ({ scene: x[0], ...x[1], cny: +x[1].cny.toFixed(4) })),
    hours: hourBuckets,
    dauSeries, lvBuckets,
    aiCost: { range: { cny: +aiCostRange.toFixed(4), it: aiItRange, ot: aiOtRange }, total: { cny: +aiCostTotal.toFixed(4), it: aiItTotal, ot: aiOtTotal, cnt: aiCntTotal } },
    pricing: CFG.pricing, fixedMonthlyCostCny: fixed
  };
}

// ---------- ★ 0.273.0 看板 AI 问答助手（D7：四提供商照抄 app 0.190.0 结构；默认火山） ----------
const AI_PROVIDERS = {
  volcano: { name: '火山引擎', endpoint: 'https://ark.cn-beijing.volces.com/api/v3/chat/completions', model: 'deepseek-v4-flash-ga-260731', keyUrl: 'https://console.volcengine.com/ark' },
  deepseek: { name: 'DeepSeek 官网', endpoint: 'https://api.deepseek.com/chat/completions', model: 'deepseek-chat', keyUrl: 'https://platform.deepseek.com' },
  tencent: { name: '腾讯云', endpoint: 'https://tokenhub.tencentmaas.com/v1/chat/completions', model: 'deepseek/deepseek-flash', keyUrl: 'https://console.cloud.tencent.com/tencentmaas' },
  custom: { name: '自定义', endpoint: '', model: '', keyUrl: '' }
};

function aiCfgResolved() {
  const a = CFG.aiAssistant || {};
  const provider = AI_PROVIDERS[a.provider] ? a.provider : 'volcano';
  const preset = AI_PROVIDERS[provider];
  const endpoint = provider === 'custom' ? (a.customEndpoint || '') : preset.endpoint;
  const model = provider === 'custom' ? (a.customModel || '') : preset.model;
  return { provider, name: preset.name, endpoint, model, apiKey: a.apiKey || '', keyUrl: preset.keyUrl };
}

// 聚合数据快照 → 紧凑 JSON（AI 只准用快照回答——数字锚定防编造）
function aiSnapshot() {
  const pick = (r) => ({ range: r.range, ...r.summary, scenes: r.scenes.map(s => ({ scene: s.scene, cnt: s.cnt, it: s.it, ot: s.ot, ct: s.ct, sp: s.sp, cny: s.cny, free: s.free })) });
  return {
    generatedAt: new Date().toLocaleString('zh-CN'),
    today: pick(finAggregate('day')),
    week: pick(finAggregate('week')),
    month: pick(finAggregate('month')),
    aiAssistantCost: finAggregate('month').aiCost.total,
    hourPeak: (() => { const f = finAggregate('day'); const max = Math.max(...f.hours); return { hour: f.hours.indexOf(max), count: max }; })(),
    users: usersAggregate() // ★ 0.302.1.1：用户规模块（注册数/新手任务/完赛/签到/近 6 周表）
  };
}

const AI_SYSTEM_PROMPT = '你是 DAG AI Chat 运营看板的数据分析助手。\n' +
  '铁律：\n' +
  '1. 只准使用下方【数据快照】中的数字回答，禁止编造、估算或使用快照外的任何数字；快照没有的维度直接回答「该维度暂无数据」。\n' +
  '2. 对比类问题（如上周 vs 上上周）用 markdown 表格回答：表头=对比维度，一行一个场景或指标。\n' +
  '3. 回答不超过 10 句：第 1 句给结论，其后给数据支撑。\n' +
  '4. 金额单位=人民币元（保留 2 位小数）；token 展示为 tokens；SP 即司忆点。\n' +
  '5. scene 对照：chat=聊天 regen=重生成 word=查词 extract=提炼 encourage_r=复习鼓励 encourage_s=统计鼓励 rerank=AI排序 profile=画像观察 summary=分支摘要 hook=伴读编排。\n' +
  '6. 毛利=充值流水−token成本；净利润=毛利−固定成本−看板AI助手成本。老数据无 token 字段时成本从生效日起算，须注明。\n' +
  '7. 不回答与看板数据无关的问题（代码、隐私、密钥等），礼貌引导回数据话题。\n' +
  '8. 用户规模口径（users 块）：注册账号数=users.totalAccounts（开启云同步的华为账号，SpMirror 上报口径）；完成新手任务（≥1 个）=users.rookieTouched；新手七任务完赛=users.rookieFinal；签到用户=users.signUsers。问「注册多少/完成新手任务多少」直接引用这些数字。\n' +
  '9. 按周统计用 users.weeks（近 6 周，week=ISO 周标签）：active=当周有 SP 流水的账号数、firstSeen=当周首次产生流水的账号数、grantSp/consumeSp=当周发放/消耗 SP。注意：流水 2026-10-23 上线，此前注册账号的首见周都落在上线当周——引用周新增时必须注明该口径。周表用 markdown 表格输出（表头：周/活跃账号/首见账号/发放SP/消耗SP）。';

// OpenAI 兼容非流式调用（60s 超时）
function callAiChat(messages, cb) {
  const cfg = aiCfgResolved();
  if (!cfg.apiKey || !cfg.endpoint || !cfg.model) { cb(new Error('未配置 AI 助手（设置卡选提供商并填 Key）'), null); return; }
  const body = JSON.stringify({ model: cfg.model, messages: messages, stream: false });
  const u = new URL(cfg.endpoint);
  const req = require('https').request({ hostname: u.hostname, path: u.pathname + u.search, method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + cfg.apiKey, 'Content-Length': Buffer.byteLength(body) },
    timeout: 60000 }, (res) => {
    let d = '';
    res.on('data', c => d += c);
    res.on('end', () => {
      try {
        const j = JSON.parse(d);
        if (j.choices && j.choices[0] && j.choices[0].message) {
          cb(null, { reply: j.choices[0].message.content || '', usage: j.usage || {} });
        } else {
          cb(new Error('模型响应异常：' + d.slice(0, 150)), null);
        }
      } catch (_e) { cb(new Error('模型响应非 JSON：' + d.slice(0, 150)), null); }
    });
  });
  req.on('timeout', () => { req.destroy(); cb(new Error('模型请求超时（60s）'), null); });
  req.on('error', (e) => cb(e, null));
  req.end(body);
}

// ---------- HTTP ----------
function sendFile(res, filePath) {
  fs.readFile(filePath, (err, buf) => {
    if (err) { res.writeHead(404); res.end('not found'); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(filePath).toLowerCase()] || 'application/octet-stream' });
    res.end(buf);
  });
}

function sendJson(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(obj));
}

function loginPage() {
  return '<!DOCTYPE html><html lang="zh"><head><meta charset="UTF-8"><title>DAGAI 看板 · 口令</title>' +
    '<style>body{background:#17131f;color:#e8e2f5;font-family:Microsoft YaHei,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}' +
    '.box{background:#201a2e;border:1px solid #342a52;border-radius:10px;padding:28px;width:300px;text-align:center}' +
    'h1{font-size:16px;color:#b9a5ff;margin:0 0 16px}input{width:100%;padding:9px;border-radius:6px;border:1px solid #4a3d75;background:#2c2440;color:#e8e2f5;box-sizing:border-box}' +
    'button{margin-top:12px;width:100%;padding:9px;border:none;border-radius:6px;background:#6c4fe0;color:#fff;cursor:pointer}' +
    '.err{color:#e07a7a;font-size:12px;margin-top:8px;min-height:16px}</style></head><body>' +
    '<div class="box"><h1>DAGAI 后台数据</h1><input id="pw" type="password" placeholder="访问口令" onkeydown="if(event.key===\'Enter\')go()">' +
    '<button onclick="go()">进入</button><div class="err" id="err"></div></div>' +
    // ★ 0.302.1.4 自动登录：本机存过 token（登录一次后的 7 天+有效期=长期）→ 直接带 k 参数进首页，不再重输口令
    '<script>(function(){try{var t=localStorage.getItem(\'dash_token\');if(t){location.replace(\'/?k=\'+t);return}}catch(_e){}' +
    'setTimeout(function(){var p=document.getElementById(\'pw\');if(p)p.focus()},80)})();' +
    'async function go(){const r=await fetch(\'/api/login\',{method:\'POST\',headers:{\'Content-Type\':\'application/json\'},body:JSON.stringify({pass:document.getElementById(\'pw\').value})});' +
    'if(r.ok){const t=await r.json();try{localStorage.setItem(\'dash_token\',t.token||\'\')}catch(_e){}location.replace(\'/?k=\'+(t.token||\'\'))}else{document.getElementById(\'err\').textContent=\'口令不对\'}}</script></body></html>';
}

const server = http.createServer(async (req, res) => {
  const url = req.url.split('?')[0];
  try {
    // 登录端点（不鉴权）
    if (url === '/api/login' && req.method === 'POST') {
      let body = '';
      req.on('data', c => body += c);
      req.on('end', () => {
        try {
          const pass = (JSON.parse(body || '{}') || {}).pass || '';
          if (crypto.createHash('sha256').update(String(pass) + '::dagai-dash').digest('hex') === TOKEN) {
            // ★ 0.302.1.3 响应带 token：登录页跳 /?k=token——前端存 localStorage（iframe 分区存储，
            //   SameSite 拦 Cookie 也能活）；Cookie 保留（顶级窗口直开场景）
            res.writeHead(200, { 'Set-Cookie': 'dag_dash=' + TOKEN + '; HttpOnly; Path=/; Max-Age=' + 7 * 86400, 'Content-Type': 'application/json; charset=utf-8' });
            res.end('{"ok":true,"token":"' + TOKEN + '"}');
          } else sendJson(res, 401, { ok: false });
        } catch (_e) { sendJson(res, 400, { ok: false }); }
      });
      return;
    }
    // 全站口令闸门
    if (!authed(req)) {
      if (url === '/' || url === '/index.html') {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(loginPage());
      } else {
        sendJson(res, 401, { ok: false, error: 'unauthorized' });
      }
      return;
    }
    if (url === '/' || url === '/index.html') {
      sendFile(res, path.join(ROOT, 'index.html'));
    } else if (url === '/api/data') {
      // Tab1 平移：内存全量倒序（最多 2 万条，防超大屏渲染炸）
      const arr = [...MEM.values()].sort((a, b) => b.t - a.t).slice(0, 20000);
      sendJson(res, 200, { ok: true, count: MEM.size, events: arr });
    } else if (url === '/api/sp') {
      sendJson(res, 200, spAggregate());
    } else if (url === '/api/fin') {
      // ★ 0.273.0 Tab3 财务+运营聚合（range=day/week/month——D4 日/周/月，年不做）
      const m = /range=(day|week|month)/.exec(req.url);
      sendJson(res, 200, finAggregate(m ? m[1] : 'week'));
    } else if (url === '/api/sp/query' && req.method === 'GET') {
      // ★ 0.302.1.3 SP 数据台·账号镜像查询（自测试台 0.301.0.2 平移——直连 Cloud DB 同实例）
      const qi2 = req.url.indexOf('?');
      const sp = new URLSearchParams(qi2 >= 0 ? req.url.slice(qi2 + 1) : '');
      let accountId = sp.get('accountId') || '';
      if (!accountId) { sendJson(res, 400, { ok: false, err: 'accountId 必填（或 __recent__ 看最近 50 行）' }); return; }
      // ★ 0.302.4.2：手机号别名解析（华为个人开发者拿不到账号手机号——由运营在数据台绑定一次）
      if (/^1\d{10}$/.test(accountId)) {
        const mapped = loadAliases()[accountId];
        if (!mapped) { sendJson(res, 200, { ok: false, err: '该手机号未绑定账号——先用账号 ID(unionID/openID) 查询，再点账号卡片里的「绑定手机号」', code: 'alias_missing' }); return; }
        accountId = String(mapped);
      }
      try {
        const coll = getDb().collection('SpMirror');
        const q = accountId === '__recent__' ? coll.query().orderByDesc('reportedAt').limit(50) : coll.query().equalTo('objectId', accountId);
        const rows = await q.get();
        const out = [];
        for (const o of rows) out.push(o.getObject ? o.getObject() : o);
        sendJson(res, 200, { ok: true, mirrors: out });
      } catch (e) { sendJson(res, 200, { ok: false, err: '查询失败：' + (e && e.message ? e.message : String(e)) }); }
    } else if (url === '/api/sp/alias' && req.method === 'POST') {
      // ★ 0.302.4.2 绑定手机号→账号 ID（一次绑定，此后手机号可直接查询；仅服务器本地 aliases.json）
      let abody = '';
      req.on('data', c => abody += c);
      req.on('end', () => {
        try {
          const b = JSON.parse(abody || '{}');
          const phone = String(b.phone || '').trim();
          const accountId = String(b.accountId || '').trim();
          if (!/^1\d{10}$/.test(phone)) { sendJson(res, 400, { ok: false, err: '手机号必须为 11 位数字' }); return; }
          if (accountId.length < 10) { sendJson(res, 400, { ok: false, err: '账号 ID 不合法' }); return; }
          const m = loadAliases();
          m[phone] = accountId;
          if (!saveAliases(m)) { sendJson(res, 500, { ok: false, err: '别名保存失败（服务器写盘异常）' }); return; }
          sendJson(res, 200, { ok: true });
        } catch (e) { sendJson(res, 400, { ok: false, err: '绑定失败：' + (e && e.message ? e.message : String(e)) }); }
      });
      return;
    } else if (url === '/api/sp/aliases' && req.method === 'GET') {
      sendJson(res, 200, { ok: true, aliases: loadAliases() });
    } else if (url === '/api/sp/command' && req.method === 'POST') {
      // ★ 0.302.1.3 SP 数据台·下发指令（写 SpCommand pending 行，app 拉取执行）
      let cbody = '';
      req.on('data', c => cbody += c);
      req.on('end', async () => {
        try {
          const b = JSON.parse(cbody || '{}');
          const targets = Array.isArray(b.targets) ? b.targets : [];
          if (targets.length === 0) { sendJson(res, 400, { ok: false, err: 'targets 必填（账号 ID 数组）' }); return; }
          // ★ 0.308.2：手机号别名解析（同查询接口 0.302.4.2 语义——已绑定→映射账号 ID；
          //   未绑定→拦截报错，杜绝「手机号原文落 target=永不被拉取的死单」——2026-10-24 实锤：
          //   target=18115530752 的 deduct 指令 pending 到天荒地老）
          const aliases = loadAliases();
          for (let i = 0; i < targets.length; i++) {
            const raw = String(targets[i]).trim();
            if (/^1\d{10}$/.test(raw)) {
              const mapped = aliases[raw];
              if (!mapped) { sendJson(res, 400, { ok: false, err: `手机号 ${raw} 未绑定账号——先用账号 ID 在「账号查询」查一次，再点账号卡片里的「绑定手机号」` }); return; }
              targets[i] = mapped;
            }
          }
          if (b.type !== 'grant' && b.type !== 'deduct') { sendJson(res, 400, { ok: false, err: 'type 必须 grant/deduct' }); return; }
          // ★ 0.302.3.2：池类型（嘉奖/充能）用 type 后缀承载——零表结构变更（Cloud DB 不新增字段）：
          //   bonus=嘉奖（默认，兼容旧端 grant/deduct）；permanent=充能 → grant_perm / deduct_perm
          const pool = String(b.pool || 'bonus');
          if (pool !== 'bonus' && pool !== 'permanent') { sendJson(res, 400, { ok: false, err: 'pool 必须 bonus/permanent' }); return; }
          if (!(parseInt(b.amount, 10) > 0)) { sendJson(res, 400, { ok: false, err: 'amount 必须为正整数' }); return; }
          const effType = pool === 'permanent' ? b.type + '_perm' : b.type;
          const now = Math.floor(Date.now() / 1000); // 表时间戳秒级（Integer 32 位坑）
          const rows = [];
          for (const t of targets) {
            const o = CloudDBZoneGenericObject.build('SpCommand');
            o.addFieldValue('objectId', 'c' + Date.now() + Math.floor(Math.random() * 100000));
            o.addFieldValue('target', String(t));
            o.addFieldValue('type', effType);
            o.addFieldValue('amount', parseInt(b.amount, 10));
            o.addFieldValue('note', String(b.note || ''));
            o.addFieldValue('status', 'pending');
            o.addFieldValue('claimedBy', '');
            o.addFieldValue('claimedAt', 0);
            o.addFieldValue('confirmedAt', 0);
            o.addFieldValue('resultAmount', 0);
            o.addFieldValue('createdAt', now);
            rows.push(o);
          }
          await getDb().collection('SpCommand').upsert(rows);
          sendJson(res, 200, { ok: true, count: rows.length });
        } catch (e) { sendJson(res, 400, { ok: false, err: '请求体解析/写入失败：' + (e && e.message ? e.message : String(e)) }); }
      });
      return;
    } else if (url === '/api/sp/commands' && req.method === 'GET') {
      // ★ 0.302.1.3 SP 数据台·指令流水（最近 20 条）
      try {
        const rows = await getDb().collection('SpCommand').query().orderByDesc('createdAt').limit(20).get();
        const out = [];
        for (const o of rows) out.push(o.getObject ? o.getObject() : o);
        sendJson(res, 200, { ok: true, commands: out });
      } catch (e) { sendJson(res, 200, { ok: false, err: '查询失败：' + (e && e.message ? e.message : String(e)) }); }
    } else if (url === '/api/sp/command/cancel' && req.method === 'POST') {
      // ★ 0.302.4：撤销未执行指令（pending/claimed → cancelled；已 done 不动）——防测试残留指令事后补账
      let xbody = '';
      req.on('data', c => xbody += c);
      req.on('end', async () => {
        try {
          const b = JSON.parse(xbody || '{}');
          const id = String(b.id || '');
          if (!id) { sendJson(res, 400, { ok: false, err: 'id 必填' }); return; }
          const rows = await getDb().collection('SpCommand').query().equalTo('objectId', id).get();
          if (!rows.length) { sendJson(res, 404, { ok: false, err: '指令不存在' }); return; }
          let n = 0;
          for (const r of rows) {
            const o = r.getObject ? r.getObject() : r;
            if (o.status === 'done' || o.status === 'cancelled') continue;
            const g = CloudDBZoneGenericObject.build('SpCommand');
            g.addFieldValue('objectId', o.objectId);
            g.addFieldValue('target', String(o.target || ''));
            g.addFieldValue('type', String(o.type || ''));
            g.addFieldValue('amount', parseInt(o.amount, 10) || 0);
            g.addFieldValue('note', String(o.note || ''));
            g.addFieldValue('status', 'cancelled');
            g.addFieldValue('claimedBy', String(o.claimedBy || ''));
            g.addFieldValue('claimedAt', parseInt(o.claimedAt, 10) || 0);
            g.addFieldValue('confirmedAt', parseInt(o.confirmedAt, 10) || 0);
            g.addFieldValue('resultAmount', parseInt(o.resultAmount, 10) || 0);
            g.addFieldValue('createdAt', parseInt(o.createdAt, 10) || 0);
            await getDb().collection('SpCommand').upsert([g]);
            n++;
          }
          sendJson(res, 200, { ok: true, cancelled: n });
        } catch (e) { sendJson(res, 400, { ok: false, err: '撤销失败：' + (e && e.message ? e.message : String(e)) }); }
      });
      return;
    } else if (url === '/api/sp/ledger' && req.method === 'GET') {
      // ★ 0.302.1.3 SP 数据台·事件流水（该账号最近 N 条）
      const qi3 = req.url.indexOf('?');
      const sp3 = new URLSearchParams(qi3 >= 0 ? req.url.slice(qi3 + 1) : '');
      const accountId = sp3.get('accountId') || '';
      const limit = Math.min(parseInt(sp3.get('limit') || '50', 10) || 50, 100);
      if (!accountId) { sendJson(res, 400, { ok: false, err: 'accountId 必填' }); return; }
      try {
        const rows = await getDb().collection('SpLedger').query().equalTo('accountId', accountId).orderByDesc('ts').limit(limit).get();
        const out = [];
        for (const o of rows) out.push(o.getObject ? o.getObject() : o);
        sendJson(res, 200, { ok: true, ledger: out });
      } catch (e) { sendJson(res, 200, { ok: false, err: '查询失败：' + (e && e.message ? e.message : String(e)) }); }
    } else if (url === '/api/ai/chat' && req.method === 'POST') {
      // ★ 0.273.0 看板 AI 问答助手（口令鉴权沿用；快照注入+非流式+成本入账 ai-cost.jsonl）
      let body = '';
      req.on('data', c => body += c);
      req.on('end', () => {
        try {
          const q = (JSON.parse(body || '{}') || {}).question || '';
          const history = (JSON.parse(body || '{}') || {}).history || [];
          if (!q.trim()) { sendJson(res, 400, { ok: false, error: '问题不能为空' }); return; }
          const snap = aiSnapshot();
          const msgs = [{ role: 'system', content: AI_SYSTEM_PROMPT + '\n\n【数据快照】\n' + JSON.stringify(snap) }];
          for (const h of history.slice(-10)) { // 近 10 轮历史（D7.2）
            if (h && h.role && h.content) msgs.push({ role: h.role === 'user' ? 'user' : 'assistant', content: String(h.content).slice(0, 4000) });
          }
          msgs.push({ role: 'user', content: q.slice(0, 4000) });
          const cfg = aiCfgResolved();
          callAiChat(msgs, (err, out) => {
            if (err) { sendJson(res, 200, { ok: false, error: String(err.message || err) }); return; }
            // 成本入账：usage prompt/completion tokens；tencent 档按 D3 单价折算 ¥、其余档金额记 0（D7.4 计价规则）
            const it = Number(out.usage.prompt_tokens) || 0;
            const ot = Number(out.usage.completion_tokens) || 0;
            const cost = cfg.provider === 'tencent' ? eventCostCny(Date.now(), '', it, ot, 0) : 0;
            appendAiCost({ date: dayKey(Date.now()), provider: cfg.provider, it: it, ot: ot, cost: +cost.toFixed(6) });
            sendJson(res, 200, { ok: true, reply: out.reply, usage: { it: it, ot: ot, cost: +cost.toFixed(6) } });
          });
        } catch (_e) { sendJson(res, 400, { ok: false, error: '请求格式错误' }); }
      });
      return;
    } else if (url === '/api/ai/config' && req.method === 'GET') {
      // 配置回显（不回 key 全文——只回是否已配）
      const cfg = aiCfgResolved();
      sendJson(res, 200, { ok: true, provider: cfg.provider, name: cfg.name, model: cfg.model,
        endpoint: cfg.endpoint, keyUrl: cfg.keyUrl, hasKey: !!cfg.apiKey,
        providers: Object.keys(AI_PROVIDERS).map(k => ({ id: k, name: AI_PROVIDERS[k].name, keyUrl: AI_PROVIDERS[k].keyUrl })) });
    } else if (url === '/api/ai/config' && req.method === 'POST') {
      // 保存配置（写回 config.json 三段合并；apiKey 空串=不覆盖已存 key）
      let body = '';
      req.on('data', c => body += c);
      req.on('end', () => {
        try {
          const j = JSON.parse(body || '{}');
          const cur = JSON.parse(fs.readFileSync(path.join(ROOT, 'config.json'), 'utf-8'));
          const a = cur.aiAssistant || {};
          if (j.provider && AI_PROVIDERS[j.provider]) a.provider = j.provider;
          if (typeof j.apiKey === 'string' && j.apiKey.trim() !== '') a.apiKey = j.apiKey.trim();
          if (typeof j.clearKey === 'boolean' && j.clearKey) a.apiKey = '';
          if (typeof j.customEndpoint === 'string') a.customEndpoint = j.customEndpoint.trim();
          if (typeof j.customModel === 'string') a.customModel = j.customModel.trim();
          cur.aiAssistant = a;
          fs.writeFileSync(path.join(ROOT, 'config.json'), JSON.stringify(cur, null, 2));
          CFG.aiAssistant = a;
          sendJson(res, 200, { ok: true });
        } catch (e) { sendJson(res, 200, { ok: false, error: '保存失败：' + (e && e.message ? e.message : String(e)) }); }
      });
      return;
    } else if (url === '/api/meta') {
      sendJson(res, 200, { ok: true, rows: MEM.size, lastSyncT: lastSyncT, lastSyncAt: lastSyncAt, quota: quotaStatus(),
        reports: { enabled: rptCfgOk() } });
    } else if (url === '/api/reports/pull') {
      if (!rptCfgOk()) { sendJson(res, 200, { ok: false, error: '未配置凭证（config.json reports 段：enabled/clientId/clientSecret/appId）' }); return; }
      sendJson(res, 200, await pullAllReports());
    } else if (url === '/api/reports') {
      let last = null;
      try { last = JSON.parse(fs.readFileSync(path.join(DATA_DIR, 'reports', 'last.json'), 'utf-8')); } catch (_e) {}
      sendJson(res, 200, { ok: true, enabled: rptCfgOk(), last: last });
    } else if (url === '/api/sync') {
      await syncFromCloud();
      sendJson(res, 200, { ok: true, rows: MEM.size, lastSyncAt: lastSyncAt });
    } else if (url.startsWith('/screenshots/')) {
      sendFile(res, path.join(ROOT, 'screenshots', path.basename(url)));
    } else if (url === '/coords.json') {
      sendFile(res, path.join(ROOT, 'coords.json'));
    } else {
      res.writeHead(404); res.end('not found');
    }
  } catch (e) {
    sendJson(res, 200, { ok: false, error: e && e.message ? e.message : String(e) });
  }
});

// ---------- 启动 ----------
loadVolumes();
server.listen(CFG.port, () => {
  console.log('[dash v2] http://localhost:' + CFG.port + ' （口令见 config.json password）');
});
syncFromCloud().then(() => { /* 首启即同步 */ });
setInterval(syncFromCloud, CFG.syncIntervalMs);
// Reports：启动 60s 后拉一次（若已配置），此后每日一拉（报表 T+1 结算，日拉足够）
setTimeout(() => { if (rptCfgOk()) pullAllReports().then(r => console.log('[dash] reports pull: ' + (r.error ? r.error : 'ok'))); }, 60000);
setInterval(() => { if (rptCfgOk()) pullAllReports().then(() => {}); }, 24 * 3600 * 1000);
