// ============================================================
// server.js — 埋点可视化看板本地服务（方案 A，2026-10-08）
// 入口：双击桌面「埋点看板.bat」或 node server.js → http://localhost:8765
// 路由：GET /            → index.html
//       GET /api/data    → Cloud DB events 全量（倒序，最多 1 万条）
//       GET /coords.json → 坐标配置（热区标注）
//       GET /screenshots/* → App 截图静态资源
// 凭证：../agc-credential.json（E:\track-events 根，绝不入 git）
// ============================================================
const http = require('http');
const fs = require('fs');
const path = require('path');
const { cloud, Region } = require('@hw-agconnect/cloud-server');

const PORT = 8765;
const ROOT = __dirname;
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8', '.png': 'image/png', '.jpg': 'image/jpeg' };

const inst = cloud.createInstance(path.join(ROOT, '..', 'agc-credential.json'), 'dash', Region.REGION_CN);
const db = inst.database({ zoneName: 'default' });

async function fetchAllEvents() {
  const coll = db.collection('events');
  // 个人应用数据量小：t>0 全量倒序拉取，聚合放前端
  const arr = await coll.query().greaterThan('t', 0).orderByDesc('t').limit(10000).get();
  // get() 返回 CloudDBZoneGenericObject（fieldMap 是 Map，JSON 序列化成 {}）——逐字段取值转平铺
  return arr.map(function (o) {
    return {
      e: String(o.getFieldValue('e') || ''),
      p: String(o.getFieldValue('p') || ''),
      t: Number(o.getFieldValue('t') || 0)
    };
  });
}

function sendFile(res, filePath) {
  fs.readFile(filePath, (err, buf) => {
    if (err) {
      res.writeHead(404); res.end('not found'); return;
    }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(filePath).toLowerCase()] || 'application/octet-stream' });
    res.end(buf);
  });
}

const server = http.createServer(async (req, res) => {
  const url = req.url.split('?')[0];
  try {
    if (url === '/' || url === '/index.html') {
      sendFile(res, path.join(ROOT, 'index.html'));
    } else if (url === '/api/data') {
      const events = await fetchAllEvents();
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ ok: true, count: events.length, events: events }));
    } else if (url.startsWith('/screenshots/')) {
      // 防目录穿越：只取文件名段
      const name = path.basename(url);
      sendFile(res, path.join(ROOT, 'screenshots', name));
    } else if (url === '/coords.json') {
      sendFile(res, path.join(ROOT, 'coords.json'));
    } else {
      res.writeHead(404); res.end('not found');
    }
  } catch (e) {
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ ok: false, error: e && e.message ? e.message : String(e) }));
  }
});

server.listen(PORT, () => {
  console.log('[dashboard] http://localhost:' + PORT);
});
// 保活引用（SDK 内部有定时器，无需额外处理）
