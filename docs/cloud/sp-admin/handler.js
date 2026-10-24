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

// ── app: report 镜像上报（同主键 upsert 覆盖=幂等）──
async function handleReport(event) {
  const accountId = String(event.accountId || '');
  if (!accountId) {
    return { ok: 'n' };
  }
  await mirrorCol.upsert(buildRow('SpMirror', {
    objectId: accountId,
    availableSp: toInt(event.availableSp),
    frozenSp: toInt(event.frozenSp),
    permSp: toInt(event.permSp),
    permCons: toInt(event.permCons),
    bonusSp: toInt(event.bonusSp),
    bonusCons: toInt(event.bonusCons),
    giftSp: toInt(event.giftSp),
    giftCons: toInt(event.giftCons),
    pkgJson: String(event.pkgJson || '[]'),
    deviceModel: String(event.deviceModel || ''),
    reportedAt: nowSec(),
  }));
  // ★ 0.302.0：事件流水批量入库（搭镜像便车；表未建/失败不影响镜像主链）
  try {
    let ledger = [];
    try {
      ledger = JSON.parse(String(event.ledger || '[]'));
    } catch (_e) {
      ledger = [];
    }
    if (Array.isArray(ledger) && ledger.length > 0) {
      const rows = [];
      for (let i = 0; i < ledger.length && i < 20; i++) {
        const e = ledger[i];
        rows.push(buildRow('SpLedger', {
          objectId: String(e.id || ('L' + Date.now() + i)),
          accountId: accountId,
          ts: toInt(e.ts) || nowSec(),
          event: String(e.event || ''),
          src: String(e.src || ''),
          amount: toInt(e.amount),
          pool: String(e.pool || ''),
          balAfter: toInt(e.bal),
          deviceModel: String(event.deviceModel || ''),
          note: String(e.note || ''),
        }));
      }
      await ledgerCol.upsert(rows);
    }
  } catch (_e) {
    // 流水失败静默——下次上报随镜像重带（端侧成功即清，此处失败=丢本批，可接受：镜像余额仍准）
  }
  return { ok: 'y' };
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
