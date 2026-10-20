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
// 依赖方向：IapUtil → ChatModel 单向（grantSiyiSpFromIap 数据层函数在 ChatModel）
// ============================================================

import { iap } from '@kit.IAPKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { connectSubscription, connectSiyiPoints, grantSiyiSpFromIap, iapSpAmountOf,
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

// ★ 0.273.0：InAppPurchaseData.price（单位分，d.ts+官方文档实查）→ 元字符串；
//   非法/缺失返回保底价（看板充值流水求和容错——NaN 拒收）；导出供 hypium 断言
export function iapAmtFromPurchaseData(r: Record<string, Object>, productId: string): string {
  const priceFen = Number(r['price'] ?? NaN);
  if (isNaN(priceFen) || priceFen <= 0) {
    return iapFallbackAmtCny(productId);
  }
  return `${(priceFen / 100).toFixed(2)}`;
}

// ── 未完成订单补单：查 UNFINISHED 消耗型单，逐单幂等到账+消耗确认 ──
//   场景：支付成功但 finishPurchase 失败（进程被杀等）→ 下次购买报「已拥有」；
//   本函数恢复：grant 幂等挡双入账（token 已记则只补 finish）
export async function recoverPendingPurchases(context: common.UIAbilityContext): Promise<void> {
  try {
    const result = await iap.queryPurchases(context, {
      productType: iap.ProductType.CONSUMABLE,
      queryType: iap.PurchaseQueryType.UNFINISHED
    });
    const subscription = connectSubscription();
    const siyi = connectSiyiPoints();
    for (let i = 0; i < result.purchaseDataList.length; i++) {
      try {
        const r = JSON.parse(result.purchaseDataList[i]) as Record<string, Object>;
        const pid = String(r['productId'] ?? '');
        const token = String(r['purchaseToken'] ?? '');
        const orderId = String(r['purchaseOrderId'] ?? '');
        const state = Number(r['purchaseState'] ?? 0);
        if (iapSpAmountOf(pid) > 0 && token.length > 0 && state === 0) {
          grantSiyiSpFromIap(subscription, siyi, pid, token, iapAmtFromPurchaseData(r, pid)); // ★ 0.273.0：amt 传参
          try {
            await iap.finishPurchase(context, {
              productType: iap.ProductType.CONSUMABLE,
              purchaseToken: token,
              purchaseOrderId: orderId
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
      // 已拥有未消耗单——先自动补单恢复，再引导重试
      await recoverPendingPurchases(context);
      out.message = '检测到未完成订单，已自动恢复，请重新购买';
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
  // 3. 解析+校验 purchaseData（PurchaseData JSON 串：productID 匹配+purchaseState=0 已购买）
  let purchaseToken = '';
  let purchaseOrderId = '';
  let amountCny = '';
  try {
    const r = JSON.parse(purchaseDataStr) as Record<string, Object>;
    const dataProductId = String(r['productId'] ?? '');
    purchaseToken = String(r['purchaseToken'] ?? '');
    purchaseOrderId = String(r['purchaseOrderId'] ?? '');
    amountCny = iapAmtFromPurchaseData(r, productId); // ★ 0.273.0：实际成交价 ¥（sp_grant iap amt）
    const state = Number(r['purchaseState'] ?? 0);
    if (state !== 0) {
      out.message = '订单状态异常，未到账（如已扣款请联系列表页客服入口）';
      return out;
    }
    if (dataProductId !== productId) {
      out.message = '订单商品不匹配，未到账';
      return out;
    }
  } catch (_e) {
    out.message = '支付结果解析失败，未到账（如已扣款请联系列表页客服入口）';
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
