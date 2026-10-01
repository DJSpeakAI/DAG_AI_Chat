// 解析 uitest dumpLayout JSON，输出控件树摘要
const fs = require('fs');
const file = process.argv[2];
const j = JSON.parse(fs.readFileSync(file, 'utf8'));

function walk(node, depth) {
  if (!node) return;
  const a = node.attributes || {};
  const parts = [];
  if (a.type) parts.push(`type=${a.type}`);
  if (a.text) parts.push(`text="${a.text}"`);
  if (a.key) parts.push(`key=${a.key}`);
  if (a.id) parts.push(`id=${a.id}`);
  if (a.description) parts.push(`desc="${a.description}"`);
  if (a.clickable === 'true') parts.push('CLICKABLE');
  if (a.bounds) parts.push(`bounds=${a.bounds}`);
  if (parts.length > 0) {
    console.log('  '.repeat(depth) + parts.join(' '));
  }
  if (node.children) {
    for (const c of node.children) walk(c, depth + 1);
  }
}
walk(j, 0);
