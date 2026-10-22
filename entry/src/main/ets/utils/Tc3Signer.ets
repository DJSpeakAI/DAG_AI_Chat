// ============================================================
// Tc3Signer.ets — ★ 0.291.2 腾讯云 API 3.0 TC3-HMAC-SHA256 签名（纯函数）
// ============================================================
// 服务对象：OCR 产品线·多模态文档解析（ocr.tencentcloudapi.com，
//   SubmitMultimodalDocParseJob / DescribeMultimodalDocParseJob）。
// 密码学原语来自 TcCrypto（纯 TS，变长 HMAC key 系统 API 不支持见该文件头注释）。
// 签名算法：腾讯云 API 3.0 官方规范（TC3-HMAC-SHA256）——
//   CanonicalRequest(POST JSON) → StringToSign → 三层 HMAC 派生 → Authorization 头。
// 同一套签名两用（Submit/Describe 复用，客服确认口径）。
// ============================================================

import { hmacSha256Hex, sha256HexOfStr } from './TcCrypto';

const TC_HOST: string = 'ocr.tencentcloudapi.com';
const TC_SERVICE: string = 'ocr';
const TC_VERSION: string = '2018-11-19'; // 腾讯云 OCR 产品线主版本（Submit/Describe 同版本）

function utcDateStr(tsSeconds: number): string {
  const d = new Date(tsSeconds * 1000);
  const y = d.getUTCFullYear();
  const m = `${d.getUTCMonth() + 1}`;
  const day = `${d.getUTCDate()}`;
  return `${y}-${m.length < 2 ? '0' : ''}${m}-${day.length < 2 ? '0' : ''}${day}`;
}

export interface Tc3Headers {
  authorization: string;
  contentType: string;
  host: string;
  action: string;
  timestamp: string;
  version: string;
}

// 组装 TC3 签名全套请求头（payload 为完整 JSON 请求体字符串；tsSeconds 秒级时间戳）
export function buildTc3Headers(action: string, payload: string, secretId: string, secretKey: string,
  tsSeconds: number): Tc3Headers {
  const date = utcDateStr(tsSeconds);
  // 1. Canonical Request（POST / 无 query；signed headers 固定 content-type;host）
  const hashedPayload = sha256HexOfStr(payload);
  const canonicalRequest = `POST\n/\n\ncontent-type:application/json\nhost:${TC_HOST}\n\ncontent-type;host\n${hashedPayload}`;
  // 2. String to Sign
  const credentialScope = `${date}/${TC_SERVICE}/tc3_request`;
  const stringToSign = `TC3-HMAC-SHA256\n${tsSeconds}\n${credentialScope}\n${sha256HexOfStr(canonicalRequest)}`;
  // 3. 三层 HMAC 派生签名（第一层 key 变长 "TC3"+SecretKey——TcCrypto 存在的根因）
  const secretDate = hmacSha256Hex(`TC3${secretKey}`, date);
  const secretService = hmacSha256Hex(secretDate, TC_SERVICE);
  const secretSigning = hmacSha256Hex(secretService, 'tc3_request');
  const signature = hmacSha256Hex(secretSigning, stringToSign);
  return {
    authorization: `TC3-HMAC-SHA256 Credential=${secretId}/${credentialScope}, SignedHeaders=content-type;host, Signature=${signature}`,
    contentType: 'application/json',
    host: TC_HOST,
    action,
    timestamp: `${tsSeconds}`,
    version: TC_VERSION
  };
}

// 导出常量供请求层使用（ohos http 头键小写）
export const TC_OCR_HOST: string = TC_HOST;
