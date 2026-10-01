// 提取控件树里最长的文本（最新 AI 回复全文）
const fs = require('fs');
const j = JSON.parse(fs.readFileSync('E:/project/DAG_AI_Chat/.hmos-debug/s4.json', 'utf8'));
let texts = [];
function walk(n) {
  if (!n) return;
  const a = n.attributes || {};
  if (a.text && a.text.length > 20) texts.push(a.text);
  if (n.children) n.children.forEach(walk);
}
walk(j);
const last = texts[texts.length - 1];
console.log('=== 最新 AI 回复全文 ===');
console.log(last);
console.log('=== 行数: ' + last.split('\n').length + ' ===');
