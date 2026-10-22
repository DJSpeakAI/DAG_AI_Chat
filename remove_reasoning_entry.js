const fs = require('fs');
const p = '/storage/Users/currentUser/project/DAG_AI_Chat/entry/src/main/ets/components/ChatPage.ets';
const raw = fs.readFileSync(p, 'utf8');
const NL = raw.includes('\r\n') ? '\r\n' : '\n';
let lines = raw.split(/\r?\n/);
const fail = (m) => { console.error('ABORT: ' + m); process.exit(1); };

// 1) 删思维链弹窗整块（注释2行+if块，花括号配平）
let ci = lines.findIndex(l => l.includes('思维链查看弹窗（任务书'));
if (ci < 0) fail('弹窗注释未找到');
if (!lines[ci + 1].includes('不嵌入气泡正文')) fail('弹窗注释第二行不匹配');
if (!lines[ci + 2].includes('if (this.reasoningViewerMsgId.length > 0) {')) fail('弹窗if行不匹配');
let depth = 0, end = -1;
for (let i = ci + 2; i < lines.length; i++) {
  for (const ch of lines[i]) {
    if (ch === '{') depth++;
    else if (ch === '}') { depth--; if (depth === 0) { end = i; break; } }
  }
  if (end >= 0) break;
}
if (end < 0) fail('弹窗块闭合未找到');
lines.splice(ci, end - ci + 1);

// 2) 入口块：onClick 三行删除 + 文案替换 + 注释更新
const oi = lines.findIndex(l => l.includes('this.reasoningViewerMsgId = msg.messageId;'));
if (oi < 0) fail('入口onClick未找到');
if (lines[oi - 1].trim() !== '.onClick(() => {' || lines[oi + 1].trim() !== '})') fail('入口onClick三行结构不匹配');
lines.splice(oi - 1, 3);
const ti = lines.findIndex(l => l.includes('s · 查看思维链`'));
if (ti < 0) fail('入口文案行未找到');
lines[ti] = lines[ti].replace(' · 查看思维链', '');
const cm = lines.findIndex(l => l.includes('点击「查看思维链」底部半屏弹窗展示全文'));
if (cm < 0) fail('入口注释行未找到');
lines[cm] = lines[cm].replace('点击「查看思维链」底部半屏弹窗展示全文；', '★0.291.4 已删「查看思维链」入口（用户拍板：司忆区已覆盖其价值）；');

// 3) 返回键拦截分支（此时应只剩一处 if）
const rest = lines.map((l, i) => l.includes('reasoningViewerMsgId') ? i : -1).filter(i => i >= 0);
const bi = lines.findIndex(l => l.includes('if (this.reasoningViewerMsgId.length > 0) {'));
if (bi < 0) fail('返回键if未找到');
if (!lines[bi + 1].includes("this.reasoningViewerMsgId = '';") || lines[bi + 2].trim() !== 'return true;') fail('返回键三行结构不匹配');
lines.splice(bi, 3);

// 4) 切分支复位行
const ri = lines.findIndex(l => l.includes("this.reasoningViewerMsgId = '';"));
if (ri < 0) fail('复位行未找到');
lines.splice(ri, 1);

// 5) 声明行
const di = lines.findIndex(l => l.includes("@Local reasoningViewerMsgId: string = '';"));
if (di < 0) fail('声明行未找到');
lines.splice(di, 1);

// 6) 全局断言清零
const left = lines.filter(l => l.includes('reasoningViewerMsgId')).length;
if (left !== 0) fail('reasoningViewerMsgId 残留 ' + left + ' 处');

fs.writeFileSync(p, lines.join(NL));
console.log('OK 已写入；剩余 reasoningViewerMsgId=' + lines.filter(l => l.includes('reasoningViewerMsgId')).length +
  '；弹窗块删除行数=' + (end - ci + 1) + '；总行数=' + lines.length);