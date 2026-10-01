// 提取会话列表项坐标
const t = require(__dirname + '/tts-layout.json');
const targets = ['白月夜工作室—DJ', '昆山市花桥镇阿明文化艺术交流中心'];
const results = [];

function walk(node) {
  if (!node || typeof node !== 'object') return;
  const a = node.attributes || {};
  if (targets.includes(a.text)) {
    results.push({ text: a.text, bounds: a.bounds, type: a.type });
  }
  (node.children || []).forEach(walk);
}
walk(t);

function center(b) {
  const m = (b || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
  if (!m) return null;
  return { x: Math.round((Number(m[1]) + Number(m[3])) / 2), y: Math.round((Number(m[2]) + Number(m[4])) / 2) };
}
for (const r of results) {
  const c = center(r.bounds);
  console.log(`${r.text} [${r.type}] bounds=${r.bounds} -> 点击坐标 (${c ? c.x + ',' + c.y : '?'})`);
}
if (!results.length) console.log('未找到会话项');
