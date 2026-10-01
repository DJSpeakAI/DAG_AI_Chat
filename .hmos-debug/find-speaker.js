// 从 dumpLayout JSON 中提取喇叭按钮（🔈/⏳/🔊）坐标
const fs = require('fs');
const raw = fs.readFileSync('.hmos-debug/tts-layout.json', 'utf8');
const tree = JSON.parse(raw);

const targets = ['🔈', '⏳', '🔊', '×'];
const results = [];

function walk(node, path) {
  if (!node || typeof node !== 'object') return;
  const attrs = node.attributes || {};
  const text = attrs.text || '';
  if (targets.includes(text)) {
    results.push({
      text,
      bounds: attrs.bounds,
      id: attrs.id || '',
      type: attrs.type || '',
      path: path.slice(-3).join(' > ')
    });
  }
  const kids = node.children || [];
  for (let i = 0; i < kids.length; i++) {
    walk(kids[i], path.concat(`${(kids[i].attributes || {}).type || '?'}`));
  }
}

walk(tree, []);
console.log('找到目标控件数:', results.length);
for (const r of results) {
  console.log(JSON.stringify(r));
}

// 解析 bounds 计算中心点
function center(b) {
  const m = b.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
  if (!m) return null;
  return { x: (Number(m[1]) + Number(m[3])) / 2, y: (Number(m[2]) + Number(m[4])) / 2 };
}
console.log('\n--- 中心点坐标 ---');
for (const r of results) {
  const c = center(r.bounds || '');
  if (c) console.log(`${r.text} -> click (${c.x}, ${c.y})`);
}
