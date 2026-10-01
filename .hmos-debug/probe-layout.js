const t = require(__dirname + '/chat-layout.json');
const texts = [];
const types = {};
(function w(n) {
  if (!n || typeof n !== 'object') return;
  const a = n.attributes || {};
  if (a.text) texts.push(a.text);
  const ty = a.type || 'unknown';
  types[ty] = (types[ty] || 0) + 1;
  (n.children || []).forEach(c => w(c));
})(t);
console.log('文本节点数:', texts.length);
console.log('文本列表:', texts.slice(0, 50).join(' | '));
console.log('控件类型统计:', JSON.stringify(types));
