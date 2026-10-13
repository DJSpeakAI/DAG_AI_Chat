// ============================================================
// testing/console/auditRules.js — ★ 0.229.26 UI 规范审计引擎
// 组织模式（0.229.26 评审定稿，DeepSeek 建议）：组件族=断言函数（纯逻辑），页面=执行单元（巡检），
//   一次 dump 多次断言；跨页一致性=全局断言（巡检完成后比对）。
// 能力边界（0.229.26 spike 实测定案，Pad 真机 26 属性键实证）：
//   ✅ backgroundColor（#AARRGGBB 归一化）/bounds(px)/text/type/enabled/visible/clickable/hint/opacity
//   ✗ fontSize/fontWeight/fontFamily/文字前景色（dump -a 也不输出——文字样式断言留三期 hypium 通道）
// 断言宽容度三层（评审定稿）：①色值归一化精确匹配 ②尺寸 ±2px 几何容差 ③显式豁免清单（非静默放行）
// ============================================================
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PROJECT = path.resolve(__dirname, '..', '..');
const TOKENS_FILE = path.join(PROJECT, 'entry', 'src', 'main', 'ets', 'common', 'DesignTokens.ets');

// ---------- DesignTokens 期望值表（跟读源码自动生成 + ★版本锚定：新增常量报警不静默扩展） ----------
// ★ 0.229.26 评审补充建议 1：期望表跟读需版本锚定——DesignTokens 新增常量时审计报告必须报警
//   （"发现未纳入审计的新 token"），防止新增非法色被静默洗白
let _tokensCache = null;
function parseDesignTokens() {
  if (_tokensCache) return _tokensCache;
  const src = fs.readFileSync(TOKENS_FILE, 'utf8');
  const colors = new Map(); // 归一化hex -> 常量名
  const raw = [];
  const re = /export\s+const\s+([A-Z_0-9]+):\s*string\s*=\s*'([^']+)'/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    const norm = normalizeColor(m[2]);
    if (norm) { colors.set(norm, m[1]); raw.push({ name: m[1], value: m[2], norm }); }
  }
  _tokensCache = { colors, raw, count: raw.length, hash: crypto.createHash('md5').update(raw.map((r) => r.name).join(',')).digest('hex').slice(0, 8) };
  return _tokensCache;
}
// 色值归一化：'#RRGGBB' / '#AARRGGBB' / 'rgba(r,g,b,a)' → 统一 '#aarrggbb' 小写（评审建议：hex 大小写不敏感）
function normalizeColor(s) {
  const str = String(s || '').trim().toLowerCase();
  if (/^#[0-9a-f]{6}$/.test(str)) return '#ff' + str.slice(1);
  if (/^#[0-9a-f]{8}$/.test(str)) return str;
  const m = str.match(/^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)$/);
  if (m) {
    const a = Math.round((m[4] === undefined ? 1 : parseFloat(m[4])) * 255);
    const hex = (n) => n.toString(16).padStart(2, '0');
    return '#' + hex(a) + hex(+m[1]) + hex(+m[2]) + hex(+m[3]);
  }
  return null;
}

// ---------- dump 解析：app 窗口子树节点收集（窗口过滤——全屏 dump 含多窗口，裸搜误中） ----------
// ★ 0.229.25 教训：定位必须限定 bundleName 子树
function parseBoundsStr(s) {
  const m = String(s || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
  return m ? { x: +m[1], y: +m[2], w: +m[3] - +m[1], h: +m[4] - +m[2], x2: +m[3], y2: +m[4] } : null;
}
function collectAppNodes(jsonText, bundle) {
  const nodes = [];
  const walk = (n, inApp) => {
    if (!n || typeof n !== 'object') return;
    const a = n.attributes || {};
    const nowIn = inApp || a.bundleName === bundle;
    if (nowIn) {
      const b = parseBoundsStr(a.bounds);
      if (b && a.visible !== 'false') nodes.push({ ...a, ...b, xc: b.x + b.w / 2, yc: b.y + b.h / 2 });
    }
    for (const k of Object.keys(n)) if (n[k] && typeof n[k] === 'object') walk(n[k], nowIn);
  };
  try { walk(JSON.parse(jsonText), false); } catch (_) { /* dump 非 JSON */ }
  return nodes;
}

// ---------- 标尺标定：以边栏内容区（BG_NAV 底色、贴左、窄长）实测宽 ↔ 208vp 锚定 density ----------
// ★ 0.230.0 修正：UI_GUIDELINES"侧边栏 240×800，**内容区宽 208**"——dump 抓到的 BG_NAV 容器实为 208vp
//   内容区（0.229.26 曾误锚 240 致 density=2.1667，多源交叉实为 2.5：520→1300px、48→120px 全吻合）
// 自动适应三端（PC/Pad/手机各自标定）；标定失败=后续尺寸断言全部 skip（防瞎报）
function calibrateDensity(nodes) {
  const tk = parseDesignTokens();
  const navColor = normalizeColor('#1A1030');
  const cands = nodes.filter((n) => n.backgroundColor && normalizeColor(n.backgroundColor) === navColor && n.x === 0 && n.w > 60 && n.w < 900 && n.h > 400);
  if (!cands.length) return { ok: false, reason: '未找到边栏容器（BG_NAV/贴左/窄长特征全不中）——尺寸断言将全部跳过' };
  const sb = cands.sort((a, b) => a.x - b.x)[0];
  const density = sb.w / 208;
  return { ok: density > 0.8 && density < 5, density, sidebarPx: sb.w, reason: density > 0.8 && density < 5 ? '' : 'density 越界（' + density.toFixed(3) + '）' };
}

// ---------- 断言函数集（组件族=纯函数；输入 nodes+ctx；输出 violations[]） ----------
// violation: { rule, where, expect, actual, level }  level: 'fail' | 'warn'
const V = (rule, where, expect, actual, level) => ({ rule, where, expect, actual, level: level || 'fail' });

// 豁免清单（评审三层宽容度第③层：显式 allowlist，非静默放行；格式 {text匹配, color} ）
const COLOR_EXEMPT = [
  { match: /^#(00|01|02)[0-9a-f]{6}$/, reason: '近透明装饰层（alpha<2%，无视觉意义不构成规范违规）' },
  { match: /^#ff333333$/, reason: '系统窗口底（宿主容器，非 app 控件色）' },
  { match: /^#ff000000$/, reason: '纯黑透明度载体（遮罩/阴影合成基色）' },
];

// A11 全局色值白名单：app 窗口内所有 backgroundColor ∈ DesignTokens 43 常量（归一化精确匹配）
function auditColorWhitelist(nodes, ctx, page) {
  const tk = parseDesignTokens();
  const out = [];
  const seen = new Map();
  for (const n of nodes) {
    const c = n.backgroundColor && normalizeColor(n.backgroundColor);
    if (!c || c === '#00000000') continue;
    if (tk.colors.has(c)) continue;
    if (COLOR_EXEMPT.some((e) => e.match.test(c))) continue;
    // 渐变端点/高亮合成等一次性色：聚合报告（同色只报一次，避免 50 个节点同色刷屏）
    if (!seen.has(c)) seen.set(c, []);
    seen.get(c).push(n);
  }
  for (const [c, list] of seen) {
    out.push(V('A11 色值白名单', `${page}/${list[0].type}「${(list[0].text || '').slice(0, 12)}」${list.length > 1 ? ` 等${list.length}处` : ''}`,
      'DesignTokens 43 常量（hex 归一化）', c + '（非 token 色——人工裁决：补 token 或改代码；已知合成色可入豁免清单）', 'warn'));
  }
  return out;
}

// A1 页面背景：根容器底色 = BG_CANVAS(#160D26)（四主页面）/ BG_APP(#120B1F)（首页）
function auditPageBackground(nodes, ctx, page, expectColor) {
  const want = normalizeColor(expectColor);
  const root = nodes.filter((n) => n.backgroundColor && normalizeColor(n.backgroundColor) === want)
    .sort((a, b) => b.w * b.h - a.w * a.h)[0];
  if (!root) return [V('A1 页面背景', page, expectColor + '（BG_CANVAS/BG_APP）', '未找到该底色容器（页面根底色可能被改）', 'warn')];
  return [];
}

// A3+A15 图标两档制+热区：clickable 可点控件 bounds ≥ 40vp（不达=可用性缺陷，warn 人工裁决豁免）
// ★ 0.230.0.1 豁免裁决入档（0.229.26 审计 warn 池人工复核结论）：
//   「桌面卡片」「⇄」「最新 ↓」等紧凑入口=设计如此的小控件（紧凑列表操作区），非违规——显式豁免
const HOTZONE_EXEMPT = ['桌面卡片', '⇄', '最新 ↓', '需复习 ↑', '字母 ↑'];
function auditHotzone(nodes, ctx, page) {
  if (!ctx.density) return [];
  const min = 40 * ctx.density - 2;
  const out = [];
  for (const n of nodes) {
    if (n.clickable !== 'true' || !n.text) continue;
    if (HOTZONE_EXEMPT.some((e) => (n.text || '').includes(e))) continue; // 显式豁免（评审三层宽容度第③层）
    if (n.h < min) out.push(V('A15 可点热区', `${page}/「${n.text.slice(0, 12)}」`, `高 ≥40vp(${Math.round(min)}px)`, `${n.w}×${n.h}px`, 'warn'));
  }
  return out;
}

// 尺寸期望表（vp，源自 UI_GUIDELINES 组件规格；px=vp×density，容差 ±2px）
const SIZE_SPEC = {
  bubbleCard: { w: 150, h: 68, name: '气泡节点卡片' },
  navItemH: { h: 44, name: '边栏导航项' },
  dialogConfirmW: { w: 400, name: '确认类弹窗宽' },
  dialogEditorW: { w: 520, name: '编辑器弹窗宽' },
  dialogBtnH: { h: 48, name: '弹窗主按钮高' },
};

// B4 弹窗双按钮等宽等高：两按钮 w 差 ≤1px、h=48vp±2px
function auditDialogButtons(nodes, ctx, dialogName, btnTexts) {
  const out = [];
  const btns = [];
  for (const t of btnTexts) {
    const hits = nodes.filter((n) => n.text === t && n.type === 'Button');
    if (hits.length) btns.push(hits[hits.length - 1]);
  }
  if (btns.length < 2) return [V('B4 弹窗按钮定位', dialogName, `双按钮「${btnTexts.join('/')}」`, `仅定位到 ${btns.length} 个`, 'warn')];
  const [a, b] = btns;
  if (Math.abs(a.w - b.w) > 1) out.push(V('B4 双按钮等宽', `${dialogName}「${a.text}」vs「${b.text}」`, '|宽差| ≤1px', `${a.w}px vs ${b.w}px（差${Math.abs(a.w - b.w)}px）`, 'fail'));
  const h48 = ctx.density ? 48 * ctx.density : 48;
  for (const x of btns) if (Math.abs(x.h - h48) > 2 * (ctx.density || 1)) out.push(V('B4 按钮高 48vp', `${dialogName}「${x.text}」`, `≈${Math.round(h48)}px`, `${x.h}px`, 'warn'));
  return out;
}

// B1/B2 弹窗宽度断点制：平板/PC 固定 vp 值 / 手机 86%（pad 端断言固定值）
function auditDialogWidth(nodes, ctx, dialogName, dialogTitleText, expectVp) {
  if (!ctx.density) return [];
  const out = [];
  const title = nodes.filter((n) => n.text && n.text.includes(dialogTitleText)).sort((a, b) => a.w * a.h - b.w * b.h)[0];
  if (!title) return [V('B1 弹窗宽度', dialogName, '标题定位', `未找到标题「${dialogTitleText}」`, 'warn')];
  // ★0.229.26 二轮修正：容器选择=包含标题中心点的 SURFACE_NODE 容器中**宽度最接近目标值**者
  //   （首版"最小面积"会抓到 86% 外层遮罩/Stack 层——编辑器外层 .width('86%') 与内层面板 520 并存时定位漂移）
  const panelColor = normalizeColor('#241640');
  const panels = nodes.filter((n) => n.backgroundColor && normalizeColor(n.backgroundColor) === panelColor &&
    n.x <= title.xc && n.x2 >= title.xc && n.y <= title.yc && n.y2 >= title.yc);
  const targetPx = expectVp * ctx.density;
  const panel = panels.sort((a, b) => Math.abs(a.w - targetPx) - Math.abs(b.w - targetPx))[0];
  const widthPx = panel ? panel.w : null;
  if (widthPx === null) return [V('B1 弹窗宽度', dialogName, `${expectVp}vp(≈${Math.round(targetPx)}px)`, 'SURFACE_NODE 面板容器未定位（弹窗底色可能变化）', 'warn')];
  if (Math.abs(widthPx - targetPx) > targetPx * 0.06) out.push(V('B1/B2 弹窗宽度断点', dialogName, `${expectVp}vp≈${Math.round(targetPx)}px`, `${widthPx}px（${(widthPx / ctx.density).toFixed(1)}vp）——断点制 400/520 硬规范（0.225.2 历史回归位）`, 'fail'));
  return out;
}

// B5 按钮层级色：主操作=BRAND_PRIMARY 底 / 危险=DANGER 红系 / 取消=非彩底
function auditDialogButtonColor(nodes, ctx, dialogName, btnText, expectTokenName) {
  const tk = parseDesignTokens();
  const btn = nodes.filter((n) => n.text === btnText && n.type === 'Button').sort((a, b) => b.w * b.h - a.w * a.h)[0];
  if (!btn) return [V('B5 按钮层级色', `${dialogName}「${btnText}」`, expectTokenName, '按钮未定位', 'warn')];
  const want = [...tk.colors.entries()].filter(([hex, name]) => name === expectTokenName).map(([hex]) => hex)[0];
  const got = normalizeColor(btn.backgroundColor);
  if (want && got !== want) return [V('B5 按钮层级色', `${dialogName}「${btnText}」`, `${expectTokenName}=${want}`, `${got}（${tk.colors.get(got) || '非token色'}）`, 'fail')];
  return [];
}

// A5 边栏导航项：存在性+选中态（★0.229.26 首跑修正：紫底在容器节点（无 text）——不限带 text；
//   44vp 高断言砍除——透明容器 dump 不可达，文字节点高≠容器高（首跑 41px 实证=Text 高））
function auditSidebar(nodes, ctx, page) {
  const out = [];
  // 导航项存在性（折叠态由 navTo 展开保障；这里只验展开后有六项）
  const navTexts = ['气泡树', '单词库', '知识库', '卡片复习', '统计', '账单', '设置'];
  const found = navTexts.filter((t) => nodes.some((n) => n.text === t && n.x < (ctx.sidebarPx || 560) + 60));
  if (found.length < 6) out.push(V('A5 边栏导航项', page, `≥6 项（${navTexts.join('/')}）`, `仅 ${found.length} 项：${found.join('/') || '无'}——边栏可能折叠或导航缺失`, 'warn'));
  // 选中态：边栏区域内存在高亮填充节点——★0.229.26 二轮实锤：代码实际=SURFACE_HOVER（AppSideBar.ets:633），
  //   UI_GUIDELINES 六-2 写=BRAND_PRIMARY 整块填充（0.220.0 重构后文档未跟上）——两版兼容断言+文档冲突报告（人工裁决改哪边）
  const hover = normalizeColor('#2C1B4D'); const brand = normalizeColor('#7C4DFF');
  const norm = (c) => (c ? normalizeColor(c) : null);
  const selNode = nodes.find((n) => n.x < (ctx.sidebarPx || 560) + 60 && (norm(n.backgroundColor) === hover || norm(n.backgroundColor) === brand) && n.w > 40 && n.h > 30);
  if (!selNode) out.push(V('A5 选中态高亮', page, '边栏区域存在 SURFACE_HOVER/BRAND_PRIMARY 填充节点', '未发现高亮节点（选中态缺失或路由高亮 bug——0.195.0 回归位）', 'fail'));
  else if (norm(selNode.backgroundColor) === hover) out.push(V('A5 文档一致性', page, 'UI_GUIDELINES 六-2：选中态=BRAND_PRIMARY 整块填充', `代码实际=SURFACE_HOVER（AppSideBar.ets:633 isItemActive 三元）——文档与代码不一致，人工裁决：改文档跟代码 / 改代码跟文档`, 'warn'));
  return out;
}

// B9 返回键关闭弹窗（执行层做 dump 前后对比，规则层只判结果）
function verdictBackKey(dialogGone, appAlive) {
  if (!dialogGone) return [V('B9 返回键关弹窗', '', '返回键=关弹窗', '弹窗仍在（返回键未关闭弹窗——项目基线功能）', 'fail')];
  if (!appAlive) return [V('B9 返回键关弹窗', '', '弹窗关、app 存活', 'app 退出/崩溃（返回键误退 app）', 'fail')];
  return [];
}

// ---------- ★ 0.233.0 新增断言（用户四条 UI 反馈落规范——UI_GUIDELINES 11.1/11.2/11.3/11.6） ----------

// 面板定位 helper：含标题中心点的 SURFACE_NODE 容器中最小面积者（=最内层弹窗面板本体）
function findDialogPanel(nodes, titleText) {
  const title = nodes.filter((n) => n.text && n.text.includes(titleText)).sort((a, b) => a.w * a.h - b.w * b.h)[0];
  if (!title) return null;
  const panelColor = normalizeColor('#241640');
  const panels = nodes.filter((n) => n.backgroundColor && normalizeColor(n.backgroundColor) === panelColor &&
    n.x <= title.xc && n.x2 >= title.xc && n.y <= title.yc && n.y2 >= title.yc);
  return panels.sort((a, b) => (a.w * a.h) - (b.w * b.h))[0] || null;
}

// A16 弹窗左右留白（★0.233.0 用户定稿「左边留空地右边也预留空地，不能贴边，贴边就很丑」）：
// 弹窗面板两侧距屏幕边缘各 ≥2% 屏宽（手机 92% 断点=每侧 4%；宽屏固定值居中天然更大）
function auditDialogSideMargins(nodes, ctx, dialogName, titleText, screenW) {
  const panel = findDialogPanel(nodes, titleText);
  if (!panel) return [V('A16 弹窗左右留白', dialogName, '面板定位', `未找到含「${titleText}」的 SURFACE_NODE 面板`, 'warn')];
  if (!screenW) return [V('A16 弹窗左右留白', dialogName, '屏宽基准', 'dump 根节点 bounds 缺失——跳过', 'warn')];
  const minPad = Math.round(screenW * 0.02);
  const leftPad = panel.x, rightPad = screenW - panel.x2;
  const out = [];
  if (leftPad < minPad) out.push(V('A16 弹窗左留白', dialogName, `≥${minPad}px(2%屏宽)`, `${leftPad}px——左边贴边`, 'fail'));
  if (rightPad < minPad) out.push(V('A16 弹窗右留白', dialogName, `≥${minPad}px(2%屏宽)`, `${rightPad}px——右边贴边（0.233.0 用户实锤项）`, 'fail'));
  return out;
}

// A17 折叠三角规格（★0.233.0 用户拍板「小三角太小，用大三角」）：行首三角容器宽 22vp（0.222.14 大三角统一值）
function auditCollapseTriangle(nodes, ctx, rowTitleText) {
  const row = nodes.find((n) => (n.text || '').includes(rowTitleText));
  if (!row) return [V('A17 折叠三角规格', rowTitleText, '折叠行存在', '未找到折叠行', 'warn')];
  const tri = nodes.filter((n) => ['▸', '▾', '▲', '▼'].includes(n.text) &&
    Math.abs(n.yc - row.yc) < Math.max(row.h, 24)).sort((a, b) => a.x - b.x)[0];
  if (!tri) return [V('A17 折叠三角规格', rowTitleText, '行首三角存在', '同高度行内未见三角字符（三角被删或换图标）', 'warn')];
  if (!ctx.density) return [];
  const want = 22 * ctx.density;
  if (Math.abs(tri.w - want) > 2 * ctx.density) {
    return [V('A17 折叠三角宽 22vp', rowTitleText, `≈${Math.round(want)}px（22vp·0.222.14 大三角）`, `${tri.w}px——小三角违规（用户拍板放大）`, 'fail')];
  }
  return [];
}

// A18 Tab 轨道两端留白（★0.232.2 两轮拍板定 12；UI_GUIDELINES 11.2）：SEGMENTED_TRACK 轨道与弹窗面板内缘间距 ≥12vp
function auditTabTrackPadding(nodes, ctx, dialogName, titleText) {
  if (!ctx.density) return [];
  const tk = parseDesignTokens();
  const trackColor = [...tk.colors.entries()].filter(([hex, name]) => name === 'SEGMENTED_TRACK').map(([hex]) => hex)[0];
  const panel = findDialogPanel(nodes, titleText);
  if (!trackColor || !panel) return [V('A18 Tab轨道端留白', dialogName, '轨道/面板定位', `track=${trackColor ? '✓' : '缺'} panel=${panel ? '✓' : '缺'}`, 'warn')];
  const track = nodes.filter((n) => normalizeColor(n.backgroundColor) === trackColor && n.w > 200 && n.h > 30)
    .sort((a, b) => b.w - a.w)[0];
  if (!track) return [V('A18 Tab轨道端留白', dialogName, 'SEGMENTED_TRACK 轨道容器', '未定位（轨道底色/结构变化）', 'warn')];
  const want = 12 * ctx.density;
  const leftPad = track.x - panel.x, rightPad = panel.x2 - track.x2;
  const out = [];
  if (leftPad < want - 2 * ctx.density) out.push(V('A18 Tab轨道左留白', dialogName, `≥${Math.round(want)}px(12vp)`, `${leftPad}px`, 'fail'));
  if (rightPad < want - 2 * ctx.density) out.push(V('A18 Tab轨道右留白', dialogName, `≥${Math.round(want)}px(12vp)`, `${rightPad}px——首尾 Tab 贴轨道边缘（0.232.1 用户拍板违规）`, 'fail'));
  return out;
}

module.exports = { parseDesignTokens, normalizeColor, collectAppNodes, calibrateDensity, auditColorWhitelist, auditPageBackground, auditHotzone, auditDialogButtons, auditDialogWidth, auditDialogButtonColor, auditSidebar, verdictBackKey, auditDialogSideMargins, auditCollapseTriangle, auditTabTrackPadding, findDialogPanel, SIZE_SPEC };
