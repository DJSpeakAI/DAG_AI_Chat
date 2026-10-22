// ============================================================
// IapUtil.ets — 华为应用内支付（IAP Kit）封装（★ 0.261.0 SP 充能）
// ============================================================
// 外部配置（2026-10-19 已就绪，全案 docs/0.165+/0.261.0）：
//   - 商户号 102499800030（个人开发者）；AGC 应用内购买服务已开启（沙盒）
//   - 商品：dagai_sp200w（200 万 SP ¥9.9）/ dagai_sp400w（400 万 SP ¥19）均为消耗型
//   - 纯客户端方案（无自建服务器）：到账幂等靠本地 token 集合
//     （SubscriptionStore.iapConsumedTokens，与 redeemedCodes 同类纯本地记录）
// API 全部以本机 SDK @hms.core.iap.d.ts 实测为准（函数名与旧网文/旧 JS SDK 不同）：
//   环境检查=queryEnvironmentStatus；查商品=queryProducts；购买=createPurchase；
//   消耗确认=finishPurchase（消耗型发货后必须调用，漏消耗=二次购买报「已拥有」）；
//   未完成单查询=queryPurchases(UNFINISHED)——补单链路数据源
// ★ 0.288.4 数据模型真相（官方 iap-data-model 文档实锤，修复 181 账号「存在未完成订单」死锁）：
//   API11+ 的 createPurchase/queryPurchases 返回 PurchaseData {type, jwsPurchaseOrder,
//   jwsSubscriptionStatus}——productId/purchaseToken/purchaseOrderId 全在 jwsPurchaseOrder
//   （JWS = header.payload.signature，payload 为 base64url 编码的 PurchaseOrderPayload JSON），
//   顶层一个都读不到！0.261~0.288.2 按顶层直读 → 沙盒偶通生产必瞎：主链路凭据缺失/商品不匹配
//   误拦没到账，补单链路整单跳过 → 挂单永远恢复不了 → 「存在未完成订单，请稍后重试」死循环。
//   统一入口 parsePurchaseRecord：JWS payload 解码 + 老格式顶层字段兜底，两条链路共用。
// 依赖方向：IapUtil → ChatModel 单向（grantSiyiSpFromIap 数据层函数在 ChatModel）
// ============================================================

import { iap } from '@kit.IAPKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import cloud, { FunctionOptions } from '@hw-agconnect/cloud';
import { connectSubscription, connectSiyiPoints, grantSiyiSpFromIap, iapSpAmountOf,
  writeOffRefundedPackage, parseIapPackages,
  IAP_PRODUCT_SP_200W, IAP_PRODUCT_SP_400W } from '../common/ChatModel';

// ── 错误码常量（值=d.ts IAPErrorCode 实测，非凭记忆）──
const ERR_USER_CANCELED: number = 1001860000;        // 用户取消
const ERR_PRODUCT_OWNED: number = 1001860051;        // 已拥有未消耗（漏 finish）
const ERR_ACCOUNT_NOT_LOGGED_IN: number = 1001860050; // 未登录华为账号
const ERR_ACCOUNT_NOT_TEST: number = 1001860058;     // 非沙盒测试账号（调试包）

// 结构化购买结果（class 而非 obj literal 类型——ArkTS 无结构类型）
export class IapOutcome {
  state: string = 'failed';  // 'ok'=到账 / 'cancelled'=用户取消 / 'failed'=失败
  message: string = '';      // 失败时的友好中文提示（成功时可空）
  spAmount: number = 0;      // 本次实到账 SP（0=未到账或重复单）
}

// 错误码 → 友好中文提示（铁律：禁原始英文报错；数字码保留=排查利器）
function classifyIapError(code: number): string {
  if (code === ERR_USER_CANCELED) {
    return '已取消支付';
  }
  if (code === ERR_ACCOUNT_NOT_LOGGED_IN) {
    return '请先登录华为账号';
  }
  if (code === ERR_ACCOUNT_NOT_TEST) {
    return '当前华为账号暂无测试权限';
  }
  if (code === 1001860005) {
    return '网络连接失败，请检查网络后重试';
  }
  if (code === 1001860004) {
    return '操作过于频繁，请稍后再试';
  }
  if (code === 1001860002) {
    return '支付服务未授权（应用签名配置缺失）';
  }
  if (code === 1001860003) {
    return '商品信息无效';
  }
  if (code === ERR_PRODUCT_OWNED) {
    return '存在未完成订单，请稍后重试';
  }
  if (code === 1001860054) {
    return '当前账号所在地区暂不支持支付';
  }
  if (code === 1001860056) {
    return '当前账号不允许购买';
  }
  if (code === 1001860001) {
    return '支付系统繁忙，请稍后再试';
  }
  return `支付未完成（${code}）`;
}

// ── 商品价格查询：返回 productId → 展示价（如 '¥9.90'）；失败返回空（UI 用保底价）──
export async function queryIapSpPrices(context: common.UIAbilityContext): Promise<Record<string, string>> {
  const out: Record<string, string> = {};
  try {
    const products = await iap.queryProducts(context, {
      productType: iap.ProductType.CONSUMABLE,
      productIds: [IAP_PRODUCT_SP_200W, IAP_PRODUCT_SP_400W]
    });
    for (let i = 0; i < products.length; i++) {
      const p = products[i];
      const price = p.localPrice ?? p.price; // localPrice 优先（price 已废弃仍兜底）
      if (price.length > 0) {
        out[p.id] = price;
      }
    }
  } catch (_e) {
    // 静默——价格展示非关键路径，UI 走保底价
  }
  return out;
}

// ── IAP 展示价保底表（0.261.0 localPrice 同口径）——★ 0.273.0：purchaseData.price 缺失/非法时
//   的 amt 兜底（sp_grant iap 行充值流水数据源；单位元字符串）──
function iapFallbackAmtCny(productId: string): string {
  return productId === IAP_PRODUCT_SP_400W ? '19.00' : '9.90';
}

// ── 统一购买记录（★ 0.288.4）：新 PurchaseData/JWS 格式与老 InAppPurchaseData 格式归一 ──
export class PurchaseRecord {
  productId: string = '';
  purchaseToken: string = '';
  purchaseOrderId: string = '';
  priceFen: number = NaN;       // 成交价（分）；NaN=缺失（amt 走保底）
  purchaseState: number = 0;    // 默认 0=已购买（新 JWS 格式无此字段——UNFINISHED 查询本身即待发货）
  revocationTime: number = 0;   // ★ 0.289.0：撤销（退款）时间 epoch ms（JWS payload；>0=已退款）
  fromJws: boolean = false;     // 诊断：字段是否取自 JWS payload（生产环境预期 true）
}

// JWS payload 解码：'header.payload.signature' 第 2 段 base64url → utf-8 → JSON
export function decodeJwsPayload(jws: string): Record<string, Object> | null {
  const parts = jws.split('.');
  if (parts.length < 2 || parts[1].length === 0) {
    return null;
  }
  let b = parts[1];
  const pad = b.length % 4; // JWS 段无 '=' 填充，解码前补齐
  if (pad === 2) {
    b += '==';
  } else if (pad === 3) {
    b += '=';
  } else if (pad === 1) {
    return null; // 非法 base64 长度
  }
  try {
    const bytes = new util.Base64Helper().decodeSync(b, util.Type.BASIC_URL_SAFE);
    return JSON.parse(util.TextDecoder.create('utf-8').decodeToString(bytes)) as Record<string, Object>;
  } catch (_e) {
    return null;
  }
}

// 顶层/payload 字符串多键防御读（华为数据模型字段命名文档与实测多次出入——0.288.1/0.288.2 两次实锤）
function readStr(r: Record<string, Object>, keys: string[]): string {
  for (let i = 0; i < keys.length; i++) {
    const v = r[keys[i]];
    if (typeof v === 'string' && v.length > 0) {
      return v;
    }
  }
  return '';
}

// ★ 0.288.4 核心修复：purchaseData/purchaseDataList 每元素统一解析入口。
//   老格式顶层直读兜底 + 新格式 jwsPurchaseOrder payload 解码，字段缺失互为补位
//   （顶层 productId/product_Id/product_id、purchaseToken/purchase_token 等命名全部防御）。
//   返回 null 仅当整串 JSON 解析失败；字段级缺失由调用方按业务语义处理
export function parsePurchaseRecord(purchaseDataStr: string): PurchaseRecord | null {
  let top: Record<string, Object>;
  try {
    top = JSON.parse(purchaseDataStr) as Record<string, Object>;
  } catch (_e) {
    return null;
  }
  const rec = new PurchaseRecord();
  rec.productId = readStr(top, ['productId', 'product_Id', 'product_id']);
  rec.purchaseToken = readStr(top, ['purchaseToken', 'purchase_token']);
  rec.purchaseOrderId = readStr(top, ['purchaseOrderId', 'orderId', 'order_id']);
  const psRaw = top['purchaseState'];
  if (typeof psRaw === 'number') {
    rec.purchaseState = psRaw;
  }
  const priceRaw = top['price'];
  if (typeof priceRaw === 'number') {
    rec.priceFen = priceRaw;
  }
  // 新格式（PurchaseData）：订单字段全在 jwsPurchaseOrder 的 JWS payload 里
  const jwsRaw = top['jwsPurchaseOrder'];
  if (typeof jwsRaw === 'string' && jwsRaw.length > 0) {
    const p = decodeJwsPayload(jwsRaw);
    if (p !== null) {
      if (rec.productId.length === 0) {
        rec.productId = readStr(p, ['productId', 'product_Id', 'product_id']);
      }
      if (rec.purchaseToken.length === 0) {
        rec.purchaseToken = readStr(p, ['purchaseToken', 'purchase_token']);
      }
      if (rec.purchaseOrderId.length === 0) {
        rec.purchaseOrderId = readStr(p, ['purchaseOrderId', 'order_id']);
      }
      if (isNaN(rec.priceFen)) {
        const pr = p['price'];
        if (typeof pr === 'number') {
          rec.priceFen = pr;
        }
      }
      // ★ 0.289.0：退款感知数据源——PurchaseOrderPayload.revocationTime（>0=订单已撤销/退款）
      const rt = p['revocationTime'];
      if (typeof rt === 'number' && rt > 0) {
        rec.revocationTime = rt;
      }
      rec.fromJws = true;
    }
  }
  return rec;
}

// ★ 0.273.0：InAppPurchaseData.price（单位分，d.ts+官方文档实查）→ 元字符串；
//   非法/缺失返回保底价（看板充值流水求和容错——NaN 拒收）；导出供 hypium 断言
export function iapAmtFromPurchaseData(r: Record<string, Object>, productId: string): string {
  const priceFen = Number(r['price'] ?? NaN);
  return iapAmtFromFen(priceFen, productId);
}

// ★ 0.288.4：分 → 元字符串（解析后的统一入口——两条链路共用，保底逻辑与 0.273.0 一致）
export function iapAmtFromFen(priceFen: number, productId: string): string {
  if (isNaN(priceFen) || priceFen <= 0) {
    return iapFallbackAmtCny(productId);
  }
  return `${(priceFen / 100).toFixed(2)}`;
}

// ── 未完成订单补单：查 UNFINISHED 消耗型单，逐单幂等到账+消耗确认 ──
//   场景：支付成功但 finishPurchase 失败（进程被杀等）→ 下次购买报「已拥有」；
//   本函数恢复：grant 幂等挡双入账（token 已记则只补 finish）
//   ★ 0.288.2：返回本次补到账 SP 总额（0=无补单）——BillingPage 据此弹「已补入账」提示框，
//   修复版装机后用户此前被误拦的已付款订单经此链路自动追回到账，无需重新付款
export async function recoverPendingPurchases(context: common.UIAbilityContext): Promise<number> {
  let recoveredTotal = 0;
  try {
    const result = await iap.queryPurchases(context, {
      productType: iap.ProductType.CONSUMABLE,
      queryType: iap.PurchaseQueryType.UNFINISHED
    });
    const subscription = connectSubscription();
    const siyi = connectSiyiPoints();
    for (let i = 0; i < result.purchaseDataList.length; i++) {
      try {
        // ★ 0.288.4：统一解析（JWS payload + 老格式兜底）——此前顶层直读在新数据模型下
        //   productId/purchaseToken 全空 → 整单跳过 → 挂单永不清除（「存在未完成订单」死锁根因）
        const rec = parsePurchaseRecord(result.purchaseDataList[i]);
        if (rec !== null && iapSpAmountOf(rec.productId) > 0
          && rec.purchaseToken.length > 0 && rec.purchaseState === 0) {
          const granted = grantSiyiSpFromIap(subscription, siyi, rec.productId, rec.purchaseToken,
            iapAmtFromFen(rec.priceFen, rec.productId)); // ★ 0.273.0：amt 传参（payload price 分→元）
          if (granted) {
            recoveredTotal += iapSpAmountOf(rec.productId);
          }
          try {
            await iap.finishPurchase(context, {
              productType: iap.ProductType.CONSUMABLE,
              purchaseToken: rec.purchaseToken,
              purchaseOrderId: rec.purchaseOrderId
            });
          } catch (_e2) {
            // 单条 finish 失败继续下一单（下次补单再试）
          }
        }
      } catch (_e1) {
        // 单条解析失败跳过
      }
    }
  } catch (_e) {
    // 静默——未登录/无未完成单/网络异常均为常态
  }
  return recoveredTotal;
}

// ── ★ 0.289.0 退款自动感知 / ★ 0.289.2 按华为官方答复修正 ──
//   真相（2026-10-22 华为 AI 答复实锤）：①queryPurchaseRecords 已废弃，替代=queryPurchases
//   ②退款以 JWS payload 的 revocationTime 表达（非 purchaseState=2，那是废弃老模型字段）
//   ③**已 finishPurchase 发货的消耗型订单不在 queryPurchases 返回范围——纯客户端退款感知
//   本质不可靠**（官方不承诺），本函数只能兜「未发货即退款」极端场景+沙盒验证；
//   可靠方案=AGC 云函数收 REFUND_TRANSACTION 通知+服务端七年 refunded 对账（PENDING 上架前实施）
export async function detectRefundedIapPurchases(context: common.UIAbilityContext): Promise<number> {
  let writtenTotal = 0;
  try {
    const result = await iap.queryPurchases(context, {
      productType: iap.ProductType.CONSUMABLE,
      queryType: iap.PurchaseQueryType.ALL
    });
    const siyi = connectSiyiPoints();
    for (let i = 0; i < result.purchaseDataList.length; i++) {
      const rec = parsePurchaseRecord(result.purchaseDataList[i]);
      if (rec === null || rec.purchaseToken.length === 0) {
        continue;
      }
      if (rec.revocationTime > 0 || rec.purchaseState === 2) {
        writtenTotal += writeOffRefundedPackage(siyi, rec.purchaseToken);
      }
    }
  } catch (_e) {
    // 静默——未登录/网络异常/无记录均为常态
  }
  return writtenTotal;
}

// ── ★ 0.291.0 云端退款标记拉取（可靠退款感知主链路）──
//   架构（用户拍板 2026-10-22）：华为退款完成 → AGC 云函数 refund-events（HTTP 触发器收
//   REFUND_TRANSACTION 通知）→ Cloud DB refunds 表（objectId=purchaseToken 幂等）→
//   **本函数三时机拉取：启动/回前台/进账单页**——用户零操作自动核销（修正初版「用户下拉」傻逼设计）；
//   白嫖闭环论证：用 SP 必开 app → 开 app 即拉取（1~2s 后台完成）→ 核销先于扣费生效。
//   云函数未部署/无网=静默 0（不阻塞；detectRefundedIapPurchases 本地查询并存兜底沙盒/未发货场景）。
//   返回本轮核销作废 SP 总额（>0 时调用方弹「退款已核销」提示）
const REFUND_FN_NAME = 'refund-events'; // AGC 云函数名（小写中划线——track-events 同款命名铁律）

export async function pullRefundMarks(): Promise<number> {
  let writtenTotal = 0;
  try {
    const siyi = connectSiyiPoints();
    const pkgs = parseIapPackages(siyi.iapPackages);
    if (pkgs.length === 0) {
      return 0; // 无包账本=无充能历史，零请求省配额
    }
    const toks: string[] = [];
    for (let i = 0; i < pkgs.length; i++) {
      if (pkgs[i].ref !== 1) {
        toks.push(pkgs[i].tok);
      }
    }
    if (toks.length === 0) {
      return 0; // 全部已核销，零请求
    }
    const payload: Record<string, Object> = {};
    payload['action'] = 'query';
    payload['tokens'] = JSON.stringify(toks); // 基础类型传参（track-events 同款铁律）
    const resp = await cloud.callFunction({ name: REFUND_FN_NAME, params: payload } as FunctionOptions);
    // getValue() 签名返回 any（SDK d.ts 实锤，ESObject 接住仍被 arkts-no-any-unknown 拍）——
    // 绕法=stringify 整个响应（responseBody 是运行时自有属性会被序列化），双路径读 refunded
    // （顶层直读 + responseBody 嵌套读互为兜底；字段防御=0.288 系列多键定式）
    const raw = JSON.stringify(resp);
    let refundedRaw = '';
    if (typeof raw === 'string' && raw.length > 0) {
      try {
        const obj = JSON.parse(raw) as Record<string, Object>;
        const top = obj['refunded'];
        if (typeof top === 'string') {
          refundedRaw = top;
        } else {
          const nested = obj['responseBody'];
          if (nested !== undefined && typeof nested === 'object' && nested !== null) {
            const inner = (nested as Record<string, Object>)['refunded'];
            if (typeof inner === 'string') {
              refundedRaw = inner;
            }
          }
        }
      } catch (_e) {
        return 0;
      }
    }
    if (refundedRaw.length === 0) {
      return 0;
    }
    let refunded: string[] = [];
    try {
      refunded = JSON.parse(refundedRaw) as string[];
    } catch (_e) {
      return 0;
    }
    for (let i = 0; i < refunded.length; i++) {
      writtenTotal += writeOffRefundedPackage(siyi, refunded[i]);
    }
  } catch (_e) {
    // 静默——云函数未部署（-1 资源不存在）/未初始化/无网均为常态，不阻塞业务
  }
  return writtenTotal;
}

// ── 完整购买流（核心）：拉起收银台 → 校验 → 幂等到账 → 消耗确认 ──
// 全捕获不 throw，一律返回结构化 IapOutcome（UI 直接按 state 分支）
export async function purchaseSp(context: common.UIAbilityContext, productId: string): Promise<IapOutcome> {
  const out = new IapOutcome();
  if (iapSpAmountOf(productId) <= 0) {
    out.message = '该商品暂不可用';
    return out;
  }
  // 1. 环境检查（未登录华为账号/地域不支持在此拦截，不拉收银台）
  try {
    await iap.queryEnvironmentStatus(context);
  } catch (e) {
    out.message = classifyIapError((e as BusinessError).code);
    return out;
  }
  // 2. 拉起收银台（系统托管 UI；须主线程调用——onClick 事件内天然满足）
  let purchaseDataStr = '';
  try {
    const result = await iap.createPurchase(context, {
      productId: productId,
      productType: iap.ProductType.CONSUMABLE
    });
    purchaseDataStr = result.purchaseData;
  } catch (e) {
    const err = e as BusinessError;
    if (err.code === ERR_PRODUCT_OWNED) {
      // 已拥有未消耗单——先自动补单恢复；★ 0.288.2：补到账则直接按成功收尾（无需用户重买）
      const recovered = await recoverPendingPurchases(context);
      if (recovered > 0) {
        out.state = 'ok';
        out.spAmount = recovered;
        return out;
      }
      out.message = '存在未完成订单，请稍后重试';
      return out;
    }
    if (err.code === ERR_USER_CANCELED) {
      out.state = 'cancelled';
      out.message = '已取消';
      return out;
    }
    out.message = classifyIapError(err.code);
    return out;
  }
  // 3. 解析+校验 purchaseData（★ 0.288.4：统一走 parsePurchaseRecord——新 PurchaseData 格式
  //    订单字段在 jwsPurchaseOrder 的 JWS payload，老格式顶层兜底；商品匹配+purchaseState=0 已购买）
  let purchaseToken = '';
  let purchaseOrderId = '';
  let amountCny = '';
  let dataProductId = '';
  let state = 0;
  const rec = parsePurchaseRecord(purchaseDataStr);
  if (rec === null) {
    out.message = '支付结果解析失败，未到账（如已扣款请联系列表页客服入口）';
    return out;
  }
  purchaseToken = rec.purchaseToken;
  purchaseOrderId = rec.purchaseOrderId;
  amountCny = iapAmtFromFen(rec.priceFen, productId); // ★ 0.273.0：实际成交价 ¥（sp_grant iap amt）
  dataProductId = rec.productId;
  state = rec.purchaseState;
  if (state !== 0) {
    out.message = '订单状态异常，未到账（如已扣款请联系列表页客服入口）';
    return out;
  }
  // ★ 0.288.2：缺失不拦截（0.261.0 设计回归）——createPurchase resolve 本身=支付成功，
  //   商品归属以我方发起购买的商品为准；仅当读到非空且确实不匹配才拦（防串单）
  if (dataProductId.length > 0 && dataProductId !== productId) {
    out.message = '订单商品不匹配，未到账';
    return out;
  }
  if (purchaseToken.length === 0) {
    out.message = '订单凭据缺失，未到账';
    return out;
  }
  // 4. 幂等到账（到账即记 token——finish 失败不丢防线，补单路径幂等挡双入账）
  const granted = grantSiyiSpFromIap(connectSubscription(), connectSiyiPoints(), productId, purchaseToken, amountCny);
  if (!granted) {
    // token 已在已入账集合=重复回调，按成功处理但不再加额
    out.state = 'ok';
    out.spAmount = 0;
    out.message = '该订单已入账过，请勿重复操作';
    return out;
  }
  // 5. 消耗确认（消耗型必须；失败不回滚到账——补单链路 recoverPendingPurchases 兜底）
  try {
    await iap.finishPurchase(context, {
      productType: iap.ProductType.CONSUMABLE,
      purchaseToken: purchaseToken,
      purchaseOrderId: purchaseOrderId
    });
  } catch (_e) {
    // 静默：SP 已到账；未消耗单下次补单自动恢复
  }
  out.state = 'ok';
  out.spAmount = iapSpAmountOf(productId);
  return out;
}
