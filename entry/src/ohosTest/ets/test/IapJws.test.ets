import { describe, it, expect } from '@ohos/hypium';
import { util } from '@kit.ArkTS';
import { IAP_PRODUCT_SP_200W, IAP_PRODUCT_SP_400W } from '../../../main/ets/common/ChatModel';
import { parsePurchaseRecord, decodeJwsPayload, iapAmtFromFen } from '../../../main/ets/utils/IapUtil';

// ★ 0.288.4：IAP 购买数据统一解析断言（project_rule §12.13 测试覆盖军令——bug 修复必须带回归用例）。
//   根因：API11+ createPurchase/queryPurchases 返回 PurchaseData {type, jwsPurchaseOrder, ...}，
//   订单字段在 JWS payload（base64url 第 2 段），顶层直读全空 → 补单整单跳过（「存在未完成订单」死锁）。
//   真收银台链路涉及华为账号+支付不进单测，此处断言纯解析函数全部分支
export default function iapJwsTest() {
  describe('DAGAI_IapJwsTest', () => {
    // 运行时构造 base64url 段（无 '=' 填充，与真实 JWS 一致；encodeSync 返回 Uint8Array 需转 string）
    const b64url = (s: string): string => {
      const bytes = new util.TextEncoder().encodeInto(s);
      const encoded = new util.Base64Helper().encodeSync(bytes, util.Type.BASIC_URL_SAFE);
      return util.TextDecoder.create('utf-8').decodeToString(encoded).split('=').join('');
    };
    const payloadJson = '{"environment":"NORMAL","purchaseOrderId":"PO-2026-001",'
      + '"purchaseToken":"TOKEN092XXXXXXXX","applicationId":"6917618071300773117",'
      + '"productId":"dagai_sp200w","productType":"0","purchaseTime":1771500000000,'
      + '"price":990,"currency":"CNY","countryCode":"CN","signedTime":1771500001000}';
    const jws = `eyJhbGciOiJSUzI1NiJ9.${b64url(payloadJson)}.fake-signature-segment`;

    // ---- 新格式（生产环境主战场）：订单字段全在 jwsPurchaseOrder payload ----
    it('jws_new_format_full_fields', 0, () => {
      const s = JSON.stringify({ type: 0, jwsPurchaseOrder: jws, jwsSubscriptionStatus: '' });
      const rec = parsePurchaseRecord(s);
      expect(rec !== null).assertTrue();
      expect(rec!.productId).assertEqual('dagai_sp200w');
      expect(rec!.purchaseToken).assertEqual('TOKEN092XXXXXXXX');
      expect(rec!.purchaseOrderId).assertEqual('PO-2026-001');
      expect(rec!.priceFen).assertEqual(990);
      expect(rec!.purchaseState).assertEqual(0); // 新格式无此字段 → 默认 0=通过
      expect(rec!.fromJws).assertTrue();
      // 顶层直读（0.288.2 及之前的读法）必须全空——证明旧代码在生产环境必然漏单
      const top = JSON.parse(s) as Record<string, Object>;
      expect(top['productId'] === undefined).assertTrue();
      expect(top['purchaseToken'] === undefined).assertTrue();
    })
    it('jws_decode_payload_directly', 0, () => {
      const p = decodeJwsPayload(jws);
      expect(p !== null).assertTrue();
      expect(p!['productId']).assertEqual('dagai_sp200w');
      expect(p!['purchaseToken']).assertEqual('TOKEN092XXXXXXXX');
    })

    // ---- 老格式（InAppPurchaseData 顶层字段）兜底仍通 ----
    it('legacy_top_level_fields', 0, () => {
      const rec = parsePurchaseRecord('{"productId":"dagai_sp400w","purchaseToken":"LEGACY-TOK",'
        + '"orderId":"LEGACY-ORDER","purchaseState":0,"price":1900}');
      expect(rec !== null).assertTrue();
      expect(rec!.productId).assertEqual('dagai_sp400w');
      expect(rec!.purchaseToken).assertEqual('LEGACY-TOK');
      expect(rec!.purchaseOrderId).assertEqual('LEGACY-ORDER');
      expect(rec!.priceFen).assertEqual(1900);
      expect(rec!.fromJws).assertFalse();
    })
    // 老格式取消态必须拦（purchaseState=1）
    it('legacy_cancelled_state_kept', 0, () => {
      const rec = parsePurchaseRecord('{"productId":"dagai_sp200w","purchaseToken":"T",'
        + '"purchaseState":1,"price":990}');
      expect(rec !== null).assertTrue();
      expect(rec!.purchaseState).assertEqual(1);
    })

    // ---- 混合/畸形防御：坏 JWS 回退顶层、坏 JSON 返 null、空串安全 ----
    it('bad_jws_falls_back_to_top', 0, () => {
      const rec = parsePurchaseRecord('{"jwsPurchaseOrder":"not-a-jws","productId":"dagai_sp200w"}');
      expect(rec !== null).assertTrue();
      expect(rec!.productId).assertEqual('dagai_sp200w'); // JWS 解不动 → 顶层兜底
      expect(rec!.purchaseToken).assertEqual(''); // 顶层也没有 → 空（调用方按缺失处理）
      expect(rec!.fromJws).assertFalse();
    })
    it('bad_json_returns_null', 0, () => {
      expect(parsePurchaseRecord('not-json') === null).assertTrue();
      expect(parsePurchaseRecord('') === null).assertTrue();
    })
    it('jws_illegal_base64_length_null', 0, () => {
      expect(decodeJwsPayload('a.b.c') === null).assertTrue(); // len%4==1 非法
      expect(decodeJwsPayload('no-segment') === null).assertTrue();
    })

    // ---- 金额换算：分→元 / NaN+非法保底（与 0.273.0 口径一致） ----
    it('amt_from_fen_conversion', 0, () => {
      expect(iapAmtFromFen(990, IAP_PRODUCT_SP_200W)).assertEqual('9.90');
      expect(iapAmtFromFen(1900, IAP_PRODUCT_SP_400W)).assertEqual('19.00');
      expect(iapAmtFromFen(NaN, IAP_PRODUCT_SP_200W)).assertEqual('9.90'); // 缺失→保底
      expect(iapAmtFromFen(0, IAP_PRODUCT_SP_400W)).assertEqual('19.00'); // 非正→保底
    })
  })
}
