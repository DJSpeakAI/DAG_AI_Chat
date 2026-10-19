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
// 老能力平移：GET /api/data（内存全量，前端 Tab1 热区+事件分布零改）
// 凭证：../agc-credential.json（track-events 根，绝不入 git）
// ============================================================
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { cloud, Region } = require('@hw-agconnect/cloud-server');

// ---------- 配置 ----------
const ROOT = __dirname;
const DATA_DIR = path.join(ROOT, 'data');
const STATE_FILE = path.join(DATA_DIR, 'state.json');
let CFG = {
  port: 8766,
  password: 'changeme',        // ★ 部署后必改（部署指引第 3 步）
  spCostPer10kCny: 0.05,       // 每 1 万 SP 对应成本 ¥（调参改配置不改码；app 内禁 ¥-SP 换算不受限）
  dailyWriteQuota: 20000,      // Cloud DB 免费配额写 2 万次/天（口径=events 当日行数）
  quotaYellowPct: 60,
  quotaRedPct: 80,
  syncIntervalMs: 10 * 60 * 1000, // 10 分钟增量同步（保护读配额 5 万/天）
  detailRetainDays: 90,
  reports: { enabled: false, clientId: '', clientSecret: '', appId: '' } // Connect API 凭证（开发者级凭证→API客户端创建；appId=应用 APP ID）
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

function rptCfgOk() { return CFG.reports && CFG.reports.enabled && CFG.reports.clientId && CFG.reports.clientSecret && CFG.reports.appId; }

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
function authed(req) { return cookieToken(req) === TOKEN; }

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

function dayKey(t) { const d = new Date(t); return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); }

function volPath(day) { return path.join(DATA_DIR, 'data-' + day + '.json'); }

function loadVolumes() {
  if (!fs.existsSync(DATA_DIR)) { fs.mkdirSync(DATA_DIR, { recursive: true }); }
  // state
  try { const s = JSON.parse(fs.readFileSync(STATE_FILE, 'utf-8')); lastSyncT = Number(s.lastSyncT) || 0; } catch (_e) {}
  // 明细卷（90 天滚动）
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
  } catch (e) {
    console.log('[dash] sync fail: ' + (e && e.message ? e.message : String(e)));
  }
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
    '<div class="box"><h1>DAGAI 埋点看板 v2</h1><input id="pw" type="password" placeholder="访问口令" onkeydown="if(event.key===\'Enter\')go()">' +
    '<button onclick="go()">进入</button><div class="err" id="err"></div></div>' +
    '<script>async function go(){const r=await fetch(\'/api/login\',{method:\'POST\',headers:{\'Content-Type\':\'application/json\'},body:JSON.stringify({pass:document.getElementById(\'pw\').value})});' +
    'if(r.ok){location.reload()}else{document.getElementById(\'err\').textContent=\'口令不对\'}}</script></body></html>';
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
            res.writeHead(200, { 'Set-Cookie': 'dag_dash=' + TOKEN + '; HttpOnly; Path=/; Max-Age=' + 7 * 86400, 'Content-Type': 'application/json; charset=utf-8' });
            res.end('{"ok":true}');
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
