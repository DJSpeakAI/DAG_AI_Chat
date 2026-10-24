// ============================================================
// sp-admin — SP 数据台云函数（★ 0.301.0 运营旁路服务端件）
// ============================================================
// 双入口：
//   ① app callFunction：report 镜像上报 / fetch 指令拉取（claim+超时回收）/ confirm 执行回报
//   ② HTTP 触发器（X-Admin-Token 鉴权）：query 快照 / command 批量下指令 / commands 指令流水
// ★ 2026-10-23 本地冒烟实锤四枚坑（换任何同族函数直接抄本文件，勿再踩）：
//   1) cloud-server（含 1.0.5）实例 API = 命名导出 { cloud }.createInstance——顶层直调报
//      "cloud.createInstance is not a function"
//   2) 实例方法 = inst.database({ zoneName })（非 cloudDB()）；表 = db.collection('表名')
//   3) 行数据必须 CloudDBZoneGenericObject.build(表名)+addFieldValue 逐字段（裸类报 2047
//      缺五元数据方法；纯对象报 3037003 缺主键）；查询结果取 .getObject() 转纯 JSON
//   4) 表时间戳字段 Integer=32 位——毫秒戳溢出报 3007007，全链一律秒级（Math.floor(ms/1000)）
// ============================================================

const agcModule = require('@hw-agconnect/cloud-server');
const cloud = agcModule.cloud || agcModule;
const inst = cloud.createInstance(__dirname + '/agc-credential.json', 'spAdmin',
  agcModule.Region.REGION_CN);
const db = inst.database({ zoneName: 'default' });
const mirrorCol = db.collection('SpMirror');
const cmdCol = db.collection('SpCommand');
const ledgerCol = db.collection('SpLedger'); // ★ 0.302.0 事件流水（表未建时 upsert 单独兜底不影响镜像）
const GenericObject = agcModule.CloudDBZoneGenericObject;

const ADMIN_TOKEN = process.env.ADMIN_TOKEN || 'dagai-sp-admin-change-me';
const CLAIM_TIMEOUT_SEC = 600; // claimed 超 10 分钟未 confirm → 回 pending 重派

function nowSec() { return Math.floor(Date.now() / 1000); }
function toInt(v) {
  const n = parseInt(String(v === undefined || v === null ? 0 : v), 10);
  return isNaN(n) ? 0 : n;
}

// 通用对象构建（坑③：GenericObject+addFieldValue）
function buildRow(table, plain) {
  const o = GenericObject.build(table);
  for (const k of Object.keys(plain)) {
    o.addFieldValue(k, plain[k]);
  }
  return o;
}

// 查询结果转纯 JSON（坑③：GenericObject 直接 stringify 会丢 fieldMap）
function rowsToPlain(rows) {
  const out = [];
  for (let i = 0; i < rows.length; i++) {
    out.push(rows[i].getObject ? rows[i].getObject() : rows[i]);
  }
  return out;
}

// ── app: report 镜像上报（★ 0.313.0 Phase2：SpMirror 已是权威账本，端侧上报降级为
//    「首次建行种子」——行已存在则绝不改余额（防弱网/旧版端把云端已扣余额上报冲回；
//    余额唯一写入方=sp_init/sp_spend/sp_grant）；流水同样由云函数事务写 SpLedger）──
async function handleReport(event) {
  const accountId = String(event.accountId || '');
  if (!accountId) {
    return { ok: 'n' };
  }
  let existing = null;
  try {
    existing = await readMirror(accountId);
  } catch (_e) {
    existing = null;
  }
  if (existing !== null) {
    return { ok: 'y' }; // 权威行已存在：忽略端侧上报（幂等成功，零写入）
  }
  const frozenSp = toInt(event.frozenSp);
  const m = {
    objectId: accountId,
    permSp: toInt(event.permSp),
    permCons: toInt(event.permCons),
    bonusSp: toInt(event.bonusSp),
    bonusCons: toInt(event.bonusCons),
    giftSp: toInt(event.giftSp),
    giftCons: toInt(event.giftCons),
    frozenSp: frozenSp,
    pkgJson: String(event.pkgJson || '[]'),
    deviceModel: String(event.deviceModel || ''),
    reportedAt: nowSec(),
  };
  m.availableSp = Math.max(0, availableOf(m) - frozenSp);
  await mirrorCol.upsert(buildRow('SpMirror', m));
  return { ok: 'y' };
}

// ══════════════════════════════════════════════════════════════
// ★ 0.312.0 SP 云函数权威记账（B 方案·根除云空间白嫖；全案 docs/0.312.0）
// 病根：SP 账本存在华为云空间行里——系统后台关同步后上行失败但本地照扣=白嫖。
// 解法：SpMirror=权威余额（objectId=accountId），SpLedger=流水+幂等键（objectId=txId），
//   一切消耗/发放必须本云函数成功才在客户端生效；云空间开关开不开都绕不过。
// 幂等：同 txId 重复请求返回首次结果（防重试双扣）；sp_init 云端已有记录绝不覆盖。
// 并发：读-改-写；多端同时扣极小概率丢更新=少扣（对用户有利、无负余额）。字段集=SpMirror 现有 schema 全集（不新增字段，免 AGC 控制台改对象类型）。
// ══════════════════════════════════════════════════════════════
function availableOf(m) {
  return (toInt(m.permSp) + toInt(m.bonusSp) + toInt(m.giftSp))
    - (toInt(m.permCons) + toInt(m.bonusCons) + toInt(m.giftCons));
}

async function readMirror(accountId) {
  const rows = rowsToPlain(await mirrorCol.query().equalTo('objectId', accountId).get());
  return rows.length > 0 ? rows[0] : null;
}

async function readLedgerRow(txId) {
  const rows = rowsToPlain(await ledgerCol.query().equalTo('objectId', txId).get());
  return rows.length > 0 ? rows[0] : null;
}

// 余额快照返回体（客户端镜像的唯一来源）
// ★ 0.313.0：welcomeGranted 不再写 SpMirror 字段（线上对象类型无此字段——0.313.0 本地直调实锤
//   3037004），改由 SpLedger 的 welcome:<accountId> 幂等流水判定；客户端仍按原字段名读取。
function balanceOut(m, welcomeGranted) {
  return {
    ok: true,
    bal: availableOf(m),
    permSp: toInt(m.permSp),
    permCons: toInt(m.permCons),
    bonusSp: toInt(m.bonusSp),
    bonusCons: toInt(m.bonusCons),
    giftSp: toInt(m.giftSp),
    giftCons: toInt(m.giftCons),
    welcomeGranted: welcomeGranted === true,
  };
}

// 礼包已发判定（SpLedger 幂等键 'welcome:<accountId>' 存在即已发；Phase3 礼包走 sp_grant 后天然成立）
async function welcomeGrantedOf(accountId) {
  try {
    const row = await readLedgerRow('welcome:' + accountId);
    return row !== null;
  } catch (_e) {
    return false;
  }
}

// ── sp_balance：查权威余额（客户端门卫/展示）──
async function handleSpBalance(event) {
  const accountId = String(event.accountId || '');
  if (!accountId) {
    return { ok: false, err: 'accountId required' };
  }
  const m = await readMirror(accountId);
  if (m === null) {
    return { ok: false, err: 'no-account' }; // 客户端走 sp_init 初始化
  }
  return balanceOut(m, await welcomeGrantedOf(accountId));
}

// ── sp_init：旧账号/新账号初始化（云端已有记录绝不覆盖——数据安全第一）──
async function handleSpInit(event) {
  const accountId = String(event.accountId || '');
  if (!accountId) {
    return { ok: false, err: 'accountId required' };
  }
  const existing = await readMirror(accountId);
  if (existing !== null) {
    return balanceOut(existing, await welcomeGrantedOf(accountId)); // 已有权威账本：忽略入参（防本地伪造覆盖云端）
  }
  const m = {
    objectId: accountId,
    permSp: Math.max(0, toInt(event.permSp)),
    permCons: Math.max(0, toInt(event.permCons)),
    bonusSp: Math.max(0, toInt(event.bonusSp)),
    bonusCons: Math.max(0, toInt(event.bonusCons)),
    giftSp: Math.max(0, toInt(event.giftSp)),
    giftCons: Math.max(0, toInt(event.giftCons)),
    frozenSp: 0,
    pkgJson: '[]',
    deviceModel: String(event.deviceModel || ''),
    reportedAt: nowSec(),
  };
  m.availableSp = Math.max(0, availableOf(m));
  await mirrorCol.upsert(buildRow('SpMirror', m));
  return balanceOut(m, false);
}

// ── sp_spend：事务扣点（gift→bonus→perm；幂等 txId）──
async function handleSpSpend(event) {
  const accountId = String(event.accountId || '');
  const txId = String(event.txId || '');
  const cost = toInt(event.cost);
  if (!accountId || !txId) {
    return { ok: false, err: 'accountId/txId required' };
  }
  if (cost <= 0) {
    return { ok: false, err: 'cost must > 0' };
  }
  // 幂等：同 txId 已记账 → 返回首次结果，绝不二次扣
  const dup = await readLedgerRow(txId);
  if (dup !== null) {
    return { ok: true, duplicate: true, cost: toInt(dup.amount), bal: toInt(dup.balAfter) };
  }
  const m0 = await readMirror(accountId);
  if (m0 === null) {
    return { ok: false, err: 'no-account' };
  }
  let avail = availableOf(m0);
  if (avail < cost) {
    return { ok: false, err: 'insufficient', bal: avail, need: cost };
  }
  // 扣减顺序与客户端 consumeSiyiSp 一致：gift → bonus → perm
  let remain = cost;
  let g = toInt(m0.giftSp);
  let gc = toInt(m0.giftCons);
  let b = toInt(m0.bonusSp);
  let bc = toInt(m0.bonusCons);
  let p = toInt(m0.permSp);
  let pc = toInt(m0.permCons);
  const gAvail = g - gc;
  if (gAvail > 0) {
    const take = Math.min(gAvail, remain);
    gc += take;
    remain -= take;
  }
  if (remain > 0) {
    const bAvail = b - bc;
    if (bAvail > 0) {
      const take = Math.min(bAvail, remain);
      bc += take;
      remain -= take;
    }
  }
  if (remain > 0) {
    const pAvail = p - pc;
    if (pAvail > 0) {
      const take = Math.min(pAvail, remain);
      pc += take;
      remain -= take;
    }
  }
  const m1 = {
    objectId: accountId,
    permSp: p, permCons: pc,
    bonusSp: b, bonusCons: bc,
    giftSp: g, giftCons: gc,
    frozenSp: toInt(m0.frozenSp),
    pkgJson: String(m0.pkgJson || '[]'),
    deviceModel: String(m0.deviceModel || event.deviceModel || ''),
    reportedAt: nowSec(),
  };
  m1.availableSp = Math.max(0, availableOf(m1) - toInt(m1.frozenSp));
  await mirrorCol.upsert(buildRow('SpMirror', m1));
  await ledgerCol.upsert(buildRow('SpLedger', {
    objectId: txId,
    accountId: accountId,
    ts: nowSec(),
    event: 'spend',
    src: String(event.scene || 'ai'),
    amount: -cost,
    pool: 'auto',
    balAfter: availableOf(m1),
    deviceModel: String(event.deviceModel || ''),
    note: String(event.note || ''),
  }));
  return { ok: true, cost: cost, bal: availableOf(m1) };
}

// ── sp_grant：事务加池（幂等 txId；pool=gift|bonus|perm）──
async function handleSpGrant(event) {
  const accountId = String(event.accountId || '');
  const txId = String(event.txId || '');
  const amount = toInt(event.amount);
  const pool = String(event.pool || 'bonus');
  if (!accountId || !txId) {
    return { ok: false, err: 'accountId/txId required' };
  }
  if (amount <= 0) {
    return { ok: false, err: 'amount must > 0' };
  }
  if (pool !== 'gift' && pool !== 'bonus' && pool !== 'perm') {
    return { ok: false, err: 'pool invalid' };
  }
  const dup = await readLedgerRow(txId);
  if (dup !== null) {
    return { ok: true, duplicate: true, amount: toInt(dup.amount), bal: toInt(dup.balAfter) };
  }
  const m0 = await readMirror(accountId);
  if (m0 === null) {
    return { ok: false, err: 'no-account' };
  }
  const m1 = {
    objectId: accountId,
    permSp: toInt(m0.permSp) + (pool === 'perm' ? amount : 0),
    permCons: toInt(m0.permCons),
    bonusSp: toInt(m0.bonusSp) + (pool === 'bonus' ? amount : 0),
    bonusCons: toInt(m0.bonusCons),
    giftSp: toInt(m0.giftSp) + (pool === 'gift' ? amount : 0),
    giftCons: toInt(m0.giftCons),
    frozenSp: toInt(m0.frozenSp),
    pkgJson: String(m0.pkgJson || '[]'),
    deviceModel: String(m0.deviceModel || ''),
    reportedAt: nowSec(),
  };
  m1.availableSp = Math.max(0, availableOf(m1) - toInt(m1.frozenSp));
  await mirrorCol.upsert(buildRow('SpMirror', m1));
  await ledgerCol.upsert(buildRow('SpLedger', {
    objectId: txId,
    accountId: accountId,
    ts: nowSec(),
    event: 'grant',
    src: String(event.src || 'unknown'),
    amount: amount,
    pool: pool,
    balAfter: availableOf(m1),
    deviceModel: String(event.deviceModel || ''),
    note: String(event.note || ''),
  }));
  return { ok: true, amount: amount, bal: availableOf(m1) };
}

// ── app: fetch 指令拉取（claim 派发+超时回收；竞态窗口毫秒级=一期已知边界）──
async function handleFetch(event) {
  const accountId = String(event.accountId || '');
  if (!accountId) {
    return { commands: '[]' };
  }
  const now = nowSec();
  const out = [];
  try {
    const rows = rowsToPlain(await cmdCol.query().equalTo('target', accountId)
      .in('status', ['pending', 'claimed']).get());
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      if (row.status === 'claimed') {
        const isMine = row.claimedBy === accountId && now - toInt(row.claimedAt) < CLAIM_TIMEOUT_SEC;
        if (!isMine) {
          await cmdCol.upsert(buildRow('SpCommand',
            Object.assign({}, row, { status: 'pending', claimedBy: '', claimedAt: 0 }))); // 过期回收
        } else {
          continue; // 本账号已持有未超时 claim——不重复派
        }
      }
      if (row.status === 'pending') {
        await cmdCol.upsert(buildRow('SpCommand',
          Object.assign({}, row, { status: 'claimed', claimedBy: accountId, claimedAt: now })));
        out.push({ id: row.objectId, type: row.type, amount: toInt(row.amount), note: row.note || '' });
      }
    }
  } catch (_e) {
    return { commands: '[]' };
  }
  return { commands: JSON.stringify(out) };
}

// ── app: probe 云同步真值探针（★ 0.308.0 假开启检测）──
//   端侧 RDB cloudSync 通路在「系统云空间未放行」时静默无操作（华为无检测 API），
//   端侧无法区分「云端空」与「假开启」。本探针走 AGC callFunction 独立通道查 default
//   zone 两表：SpMirror 镜像（同主键 upsert，会被最后上报设备覆盖）+ SpLedger 流水
//   （追加不覆盖）——任一存在**他设备**痕迹 ⇒ 该账号在其他设备有资产史 ⇒ 云端大概率
//   有 cfg:siyi-points 行；此时端侧若拉不到该行 = 假开启实锤（端侧自行判定）。
//   返回 probe='y' 有他设备痕迹 / 'n' 无（或仅本机） / 'e' 查询异常（端侧 fail-open）。
async function handleProbe(event) {
  const accountId = String(event.accountId || '');
  const deviceModel = String(event.deviceModel || '');
  if (!accountId) {
    return { probe: 'n' };
  }
  try {
    const mirrors = rowsToPlain(await mirrorCol.query().equalTo('objectId', accountId).get());
    for (let i = 0; i < mirrors.length; i++) {
      if (String(mirrors[i].deviceModel || '') !== deviceModel) {
        return { probe: 'y' };
      }
    }
    const ledger = rowsToPlain(await ledgerCol.query().equalTo('accountId', accountId).limit(20).get());
    for (let i = 0; i < ledger.length; i++) {
      if (String(ledger[i].deviceModel || '') !== deviceModel) {
        return { probe: 'y' };
      }
    }
    return { probe: 'n' };
  } catch (_e) {
    return { probe: 'e' };
  }
}

// ── app: confirm 执行回报 ──
async function handleConfirm(event) {
  const commandId = String(event.commandId || '');
  const accountId = String(event.accountId || '');
  if (!commandId || !accountId) {
    return { ok: 'n' };
  }
  try {
    const rows = rowsToPlain(await cmdCol.query().equalTo('objectId', commandId).get());
    if (rows.length === 0 || rows[0].status === 'done') {
      return { ok: 'y' }; // 不存在/已完结=幂等成功
    }
    await cmdCol.upsert(buildRow('SpCommand',
      Object.assign({}, rows[0], { status: 'done', confirmedAt: nowSec(),
        resultAmount: toInt(event.resultAmount) })));
    return { ok: 'y' };
  } catch (_e) {
    return { ok: 'n' };
  }
}

// ── HTTP: query 快照查询（单账号 / 最近 50 行）──
async function handleQuery(event) {
  const accountId = String(event.accountId || '');
  try {
    if (accountId === '__recent__') {
      return { ok: true, mirrors: rowsToPlain(await mirrorCol.query()
        .orderByDesc('reportedAt').limit(50).get()) };
    }
    if (!accountId) {
      return { ok: false, err: 'accountId required' };
    }
    return { ok: true, mirrors: rowsToPlain(await mirrorCol.query()
      .equalTo('objectId', accountId).get()) };
  } catch (_e) {
    return { ok: false, err: 'query failed: ' + String(_e && _e.message ? _e.message : _e).slice(0, 120) };
  }
}

// ── HTTP: command 批量下指令 ──
async function handleCommand(event) {
  let targets = [];
  try {
    targets = JSON.parse(String(event.targets || '[]'));
  } catch (_e) {
    targets = [];
  }
  const type = String(event.type || '');
  const amount = toInt(event.amount);
  const note = String(event.note || '');
  if (!Array.isArray(targets) || targets.length === 0) {
    return { ok: false, err: 'targets required' };
  }
  if (type !== 'grant' && type !== 'deduct') {
    return { ok: false, err: 'type must be grant/deduct' };
  }
  if (amount <= 0) {
    return { ok: false, err: 'amount must > 0' };
  }
  const now = nowSec();
  const rows = [];
  for (let i = 0; i < targets.length; i++) {
    rows.push(buildRow('SpCommand', {
      objectId: 'c' + Date.now() + Math.floor(Math.random() * 100000),
      target: String(targets[i]),
      type: type,
      amount: amount,
      note: note,
      status: 'pending',
      claimedBy: '',
      claimedAt: 0,
      confirmedAt: 0,
      resultAmount: 0,
      createdAt: now,
    }));
  }
  await cmdCol.upsert(rows);
  return { ok: true, count: rows.length };
}

// ── HTTP: commands 指令流水（最近 20 条）──
async function handleCommands() {
  try {
    return { ok: true, commands: rowsToPlain(await cmdCol.query()
      .orderByDesc('createdAt').limit(20).get()) };
  } catch (_e) {
    return { ok: false, err: 'query failed' };
  }
}

function authorized(event) {
  const headers = (event && event.headers) || {};
  const token = String(headers['X-Admin-Token'] || headers['x-admin-token'] || event.adminToken || '');
  return token === ADMIN_TOKEN;
}

// ★ 2026-10-23 官方文档实锤（《Node.js》入口方法）：AGC 运行时回调是**单参数** `callback(result)`——
//   写成 Node 习惯的 callback(null, result) 会被平台当成 result=null → 控制台执行结果显示空串 ""
//   （血泪：排了一晚上，用户操作 100% 正确）。异常也用单参数回错误对象 {code, message}。
exports.myHandler = async function (event, context, callback) {
  // HTTP 触发器/控制台测试的事件体兼容（官方示例定式：body 是字符串时先 parse）
  let ev = event;
  try {
    if (event && typeof event.body === 'string') {
      ev = JSON.parse(event.body);
    }
  } catch (_e) {
    ev = event;
  }
  try {
    const action = ev && ev.action ? String(ev.action) : '';
    if (action === 'report') {
      callback(await handleReport(ev));
      return;
    }
    if (action === 'fetch') {
      callback(await handleFetch(ev));
      return;
    }
    if (action === 'confirm') {
      callback(await handleConfirm(ev));
      return;
    }
    if (action === 'probe') {
      callback(await handleProbe(ev));
      return;
    }
    // ★ 0.312.0 SP 权威记账四接口（客户端直调——无需 admin token，账本接口幂等+云端校验防滥用）
    if (action === 'sp_balance') {
      callback(await handleSpBalance(ev));
      return;
    }
    if (action === 'sp_init') {
      callback(await handleSpInit(ev));
      return;
    }
    if (action === 'sp_spend') {
      callback(await handleSpSpend(ev));
      return;
    }
    if (action === 'sp_grant') {
      callback(await handleSpGrant(ev));
      return;
    }
    if (action === 'query' || action === 'command' || action === 'commands') {
      if (!authorized(ev)) {
        callback({ ok: false, err: 'unauthorized' });
        return;
      }
      if (action === 'query') {
        callback(await handleQuery(ev));
        return;
      }
      if (action === 'command') {
        callback(await handleCommand(ev));
        return;
      }
      callback(await handleCommands());
      return;
    }
    callback({ ok: false, err: 'unknown action' });
  } catch (_e) {
    callback({ code: 500, message: 'internal error: ' + String(_e && _e.message ? _e.message : _e).slice(0, 120) });
  }
};
