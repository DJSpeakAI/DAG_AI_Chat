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
  reports: { enabled: false, clientId: '', clientKey: '' } // Reports API 凭证位（一期占位）
};
try {
  const c = JSON.parse(fs.readFileSync(path.join(ROOT, 'config.json'), 'utf-8'));
  CFG = Object.assign(CFG, c);
} catch (_e) { /* 无 config.json 用默认 */ }

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

// ---------- Cloud DB ----------
const inst = cloud.createInstance(path.join(ROOT, '..', 'agc-credential.json'), 'dash', Region.REGION_CN);
const db = inst.database({ zoneName: 'default' });

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
  try {
    let rounds = 0;
    let added = 0;
    while (rounds < 50) { // 增量循环：单次上限 1 万，满批续拉（>= 防同 t 漏拉，Map 去重保幂等）
      const coll = db.collection('events');
      const arr = await coll.query().greaterThanOrEqualTo('t', lastSyncT).orderByDesc('t').limit(10000).get();
      let maxT = lastSyncT;
      const touched = new Set();
      for (const o of arr) {
        const ev = { e: String(o.getFieldValue('e') || ''), p: String(o.getFieldValue('p') || ''), t: Number(o.getFieldValue('t') || 0) };
        if (ev.t < lastSyncT || MEM.has(ev.e + '|' + ev.t)) continue;
        MEM.set(ev.e + '|' + ev.t, ev);
        if (ev.t > maxT) maxT = ev.t;
        touched.add(dayKey(ev.t));
        added++;
      }
      for (const day of touched) persistDay(day);
      lastSyncT = Math.max(lastSyncT, maxT);
      fs.writeFileSync(STATE_FILE, JSON.stringify({ lastSyncT: lastSyncT }));
      if (arr.length < 10000) break;
      rounds++;
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
        reports: { enabled: !!(CFG.reports && CFG.reports.enabled) } });
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
