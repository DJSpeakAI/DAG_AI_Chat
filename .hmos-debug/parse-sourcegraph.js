// 解析 Sourcegraph SSE 搜索结果，提取 doubao-tts 代码匹配
const fs = require('fs');
const F = 'C:/Users/Administrator/.local/share/.codeartsdoer/tool-output/tool_0f8edfef7001K8QDi35gShm1W0';
const s = fs.readFileSync(F, 'utf8');

// SSE 格式：data: [...] 行
const dataLines = s.split('\n').filter(l => l.startsWith('data: ') && !l.includes('"done"'));
let entries = [];
for (const l of dataLines) {
  try {
    const arr = JSON.parse(l.slice(6));
    if (Array.isArray(arr)) entries = entries.concat(arr);
  } catch (e) { /* 忽略非 JSON 行 */ }
}
console.log('匹配条目总数:', entries.length);

// 去重统计 repo/path
const seen = new Set();
const items = [];
for (const e of entries) {
  const key = (e.repository || '?') + ' :: ' + (e.path || '?');
  if (seen.has(key)) continue;
  seen.add(key);
  const content = (e.lineMatches || []).map(m => (m.line || '').trim()).join('\n');
  items.push({ key, content });
}
console.log('去重后 repo::path:', items.length, '\n');

// 全部文件清单
items.forEach(it => console.log('  ' + it.key));
console.log('\n=== 含关键协议信息的匹配 ===');
// 找含 ark 端点 / audio/speech / voice 参数 / 模型ID 的内容
const kw = /ark\.cn-beijing|audio\/speech|"voice"|voice\s*[:=]|doubao-tts-[a-z0-9-]+|seed-tts/i;
items.forEach(it => {
  if (kw.test(it.content)) {
    console.log('\n--- ' + it.key + ' ---');
    console.log(it.content.split('\n').slice(0, 12).join('\n'));
  }
});
