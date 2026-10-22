// ============================================================
// refund-events — IAP 退款事件云函数（★ 0.291.0 退款感知主链路服务端件）
// ============================================================
// 双入口：
//   ① HTTP 触发器（AGC 应用内支付服务「通知接收地址」指向本函数 URL）：
//      华为 IAP 服务器 POST {jwsNotification: "JWS串"} → 解码 payload →
//      notificationType=REVOKE（消耗型=订单退款）→ 取 purchaseToken →
//      Cloud DB refunds 表 upsert（objectId=purchaseToken，天然幂等）→
//      立即返 {"resultCode":"000000","resultDesc":"Success."}（防通知重发堆积）
//   ② app callFunction 查询（IapUtil.pullRefundMarks 三时机调用）：
//      {action:'query', tokens:'["tokA","tokB"]'} → 查 refunds 表命中 →
//      callback(null, {refunded: '["tokA"]'})
//
// ⚠️ 上线前必做（部署指引检查项）：
//   1. JWS 验签——当前仅解码不验签（测试期可接受：函数 URL 不公开+伪造无收益）；
//      上线必须按官方文档「对返回结果验签」补华为支付公钥验签
//   2. 服务端对账 API 定期兜底（180 天窗口「应用购买记录相关支付订单查询」）
//
// 部署形态：与 track-events 同项目（复用 cloud-server-deps 依赖层 + agc-credential.json）
// ============================================================

const cloud = require('@hw-agconnect/cloud-server');

const inst = cloud.createInstance(__dirname + '/agc-credential.json', 'refundEvents', cloud.Region.REGION_CN);
const db = inst.cloudDB();

// Cloud DB 对象类型 refunds（控制台建表字段一一对应；objectId=purchaseToken 主键）
class RefundMark {
  constructor() {
    this.objectId = '';    // 主键=purchaseToken（幂等锚点）
    this.orderId = '';     // purchaseOrderId
    this.environment = ''; // NORMAL / SANDBOX
    this.signedTime = 0;   // 通知签名时间（ms）
    this.notifiedAt = 0;   // 本函数入库时间（ms）
    this.raw = '';         // NotificationPayload 原文存档（排查/补验签用）
  }
}

// JWS payload 解码：'header.payload.signature' 第 2 段 base64url → utf-8 JSON
function decodeJwsPayload(jws) {
  try {
    const seg = jws.split('.')[1];
    if (!seg) {
      return null;
    }
    return JSON.parse(Buffer.from(seg, 'base64url').toString('utf-8'));
  } catch (_e) {
    return null;
  }
}

// HTTP 通知入口：立即 200 语义 + 幂等入库；任何内部异常仍返 000000
// （华为侧只认 HTTP 200；入库失败不重试（下次事件/对账 API 兜底），绝不因己方故障引发通知堆积重发风暴）
async function handleNotification(event) {
  let jws = '';
  const body = event && event.body !== undefined ? event.body : event;
  if (typeof body === 'string') {
    try {
      const parsed = JSON.parse(body);
      jws = typeof parsed.jwsNotification === 'string' ? parsed.jwsNotification : '';
    } catch (_e) {
      jws = '';
    }
  } else if (body && typeof body === 'object') {
    jws = typeof body.jwsNotification === 'string' ? body.jwsNotification : '';
  }
  if (!jws) {
    return { resultCode: '000000', resultDesc: 'Success.' };
  }
  const payload = decodeJwsPayload(jws);
  if (payload === null) {
    return { resultCode: '000000', resultDesc: 'Success.' };
  }
  // 只处理退款：主类型 REVOKE（消耗型/非消耗型=订单退款）；subtype REFUND_TRANSACTION=退款成功
  // 其余类型（DID_NEW_TRANSACTION 等）直接 200 忽略——本函数只管退款核销
  if (payload.notificationType !== 'REVOKE') {
    return { resultCode: '000000', resultDesc: 'Success.' };
  }
  const meta = payload.notificationMetaData;
  const token = meta && typeof meta.purchaseToken === 'string' ? meta.purchaseToken : '';
  if (!token) {
    return { resultCode: '000000', resultDesc: 'Success.' };
  }
  const row = new RefundMark();
  row.objectId = token;
  row.orderId = meta.purchaseOrderId !== undefined ? String(meta.purchaseOrderId) : '';
  row.environment = meta.environment !== undefined ? String(meta.environment) : '';
  row.signedTime = typeof payload.signedTime === 'number' ? payload.signedTime : 0;
  row.notifiedAt = Date.now();
  row.raw = JSON.stringify(payload);
  try {
    const zone = db.zone('default');
    await zone.upsert([row], RefundMark); // upsert 幂等：重发通知覆盖同主键行，零副作用
  } catch (_e) {
    // 入库失败也返成功：对账 API 兜底；防重发堆积（顶部注释军令）
  }
  return { resultCode: '000000', resultDesc: 'Success.' };
}

// app 查询入口：tokens JSON 串 → 命中 refunds 主键列表
async function handleQuery(event) {
  let toks = [];
  try {
    toks = JSON.parse(String(event.tokens || '[]'));
  } catch (_e) {
    toks = [];
  }
  if (!Array.isArray(toks) || toks.length === 0) {
    return { refunded: '[]' };
  }
  // 分批 query（单次 in 上限防御：每批 50）
  const hit = [];
  try {
    const zone = db.zone('default');
    for (let i = 0; i < toks.length; i += 50) {
      const batch = toks.slice(i, i + 50);
      const q = db.query(RefundMark).in('objectId', batch);
      const rows = await zone.query(q);
      for (let r = 0; r < rows.length; r++) {
        if (rows[r].objectId) {
          hit.push(rows[r].objectId);
        }
      }
    }
  } catch (_e) {
    return { refunded: '[]' }; // 查询异常=无退款（保守：不核销）
  }
  return { refunded: JSON.stringify(hit) };
}

exports.myHandler = async function (event, context, callback) {
  try {
    if (event && event.action === 'query') {
      callback(null, await handleQuery(event));
      return;
    }
    callback(null, await handleNotification(event));
  } catch (_e) {
    // 全兜底：任何异常都按成功通知响应（防重发堆积）；query 异常已在内部兜
    callback(null, { resultCode: '000000', resultDesc: 'Success.' });
  }
};
