// ============================================================
// extract-marks.js — 从 uitest dumpLayout 的 layout.json 提取控件中心相对坐标
// 用法：node extract-marks.js <layout.json> [screenW screenH] [关键词1 关键词2 ...]
// 无关键词 = 列出全部带文本的控件（找标注参考）
// 输出：文本/id → bounds 中心 → x,y 相对比例（coords.json marks 直接可填）
// ============================================================
const fs = require('fs');
const file = process.argv[2];
const W = Number(process.argv[3] || 2800), H = Number(process.argv[4] || 1840);
const kws = process.argv.slice(5);
const tree = JSON.parse(fs.readFileSync(file, 'utf8'));
const out = [];
function center(b) {
  const m = /\[(\d+),(\d+)\]\[(\d+),(\d+)\]/.exec(b || '');
  if (!m) return null;
  const x1 = +m[1], y1 = +m[2], x2 = +m[3], y2 = +m[4];
  if (x2 - x1 > W * 0.9 && y2 - y1 > H * 0.9) return null; // 全屏容器跳过
  return { x: +(((x1 + x2) / 2) / W).toFixed(4), y: +(((y1 + y2) / 2) / H).toFixed(4), w: x2 - x1, h: y2 - y1 };
}
function walk(n) {
  if (!n || !n.attributes) return;
  const a = n.attributes;
  const label = a.text || a.id || a.description || '';
  if (label && a.bounds) {
    const c = center(a.bounds);
    if (c && (kws.length === 0 || kws.some(k => label.indexOf(k) >= 0))) {
      out.push({ label: label.slice(0, 40), x: c.x, y: c.y, w: c.w, h: c.h, clickable: a.clickable === 'true' });
    }
  }
  (n.children || []).forEach(walk);
}
walk(tree);
out.forEach(o => console.log(JSON.stringify(o)));
console.error('total: ' + out.length);
