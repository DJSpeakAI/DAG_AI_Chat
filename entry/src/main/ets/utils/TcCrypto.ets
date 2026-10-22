// ============================================================
// TcCrypto.ets — ★ 0.291.2 纯 TS SHA-256 + HMAC-SHA256（腾讯云 TC3 签名前置）
// ============================================================
// 为什么不用 @kit.CryptoArchitectureKit：其 Mac 算法的 SymKey 生成器只接受
// AES128/192/256 固定长度密钥，而 TC3 签名第一层 HMAC 的 key 是变长字符串
// "TC3"+SecretKey（SecretKey 长度由用户 CAM 密钥决定），系统 API 无法承载
// 变长 HMAC key——照 ZstdUtil 纯 TS 移植先例自实现（FIPS 180-4 / RFC 2104
// 标准算法，公开域实现改写；零依赖零状态纯函数）。
// 注意：项目兑换码 SHA256（ChatModel）用的 cryptoFramework Md 是定长摘要
// （无 key），与本件 HMAC 场景不同，勿合并。
// ============================================================

const K256: number[] = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];

function utf8Bytes(s: string): Uint8Array {
  const out: number[] = [];
  for (let i = 0; i < s.length; i++) {
    let c = s.charCodeAt(i);
    if (c < 0x80) {
      out.push(c);
    } else if (c < 0x800) {
      out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    } else if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
      // 代理对 → UTF-8 四字节
      const lo = s.charCodeAt(i + 1);
      const cp = 0x10000 + ((c - 0xd800) << 10) + (lo - 0xdc00);
      out.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3f), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
      i++;
    } else {
      out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    }
  }
  return new Uint8Array(out);
}

function rotr(x: number, n: number): number {
  return ((x >>> n) | (x << (32 - n))) >>> 0;
}

// SHA-256 摘要（输入字节串，输出 32 字节）
export function sha256(data: Uint8Array): Uint8Array {
  const h: number[] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  const bitLen = data.length * 8;
  // 填充：0x80 + 0…0 + 8 字节大端长度（按 64 字节块对齐）
  const padLen = ((data.length + 9 + 63) >> 6) << 6;
  const buf = new Uint8Array(padLen);
  buf.set(data);
  buf[data.length] = 0x80;
  // 长度大端写入末 8 字节（JS number 精度内：消息 < 2^53 bit 安全）
  let bl = bitLen;
  const le: number[] = [];
  for (let i = 0; i < 8; i++) {
    le.push(bl % 256); // 从低位逐字节取
    bl = Math.floor(bl / 256);
  }
  for (let i = 0; i < 8; i++) {
    buf[padLen - 8 + i] = le[7 - i]; // 大端：最高字节在最前
  }
  const w = new Array<number>(64);
  for (let off = 0; off < padLen; off += 64) {
    for (let i = 0; i < 16; i++) {
      w[i] = (buf[off + i * 4] << 24) | (buf[off + i * 4 + 1] << 16) | (buf[off + i * 4 + 2] << 8) | buf[off + i * 4 + 3];
    }
    for (let i = 16; i < 64; i++) {
      const s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      const s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }
    let a = h[0];
    let b = h[1];
    let c = h[2];
    let d = h[3];
    let e = h[4];
    let f = h[5];
    let g = h[6];
    let hh = h[7];
    for (let i = 0; i < 64; i++) {
      const S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const ch = (e & f) ^ (~e & g);
      const t1 = (hh + S1 + ch + K256[i] + w[i]) >>> 0;
      const S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const t2 = (S0 + maj) >>> 0;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) >>> 0;
    }
    h[0] = (h[0] + a) >>> 0;
    h[1] = (h[1] + b) >>> 0;
    h[2] = (h[2] + c) >>> 0;
    h[3] = (h[3] + d) >>> 0;
    h[4] = (h[4] + e) >>> 0;
    h[5] = (h[5] + f) >>> 0;
    h[6] = (h[6] + g) >>> 0;
    h[7] = (h[7] + hh) >>> 0;
  }
  const out = new Uint8Array(32);
  for (let i = 0; i < 8; i++) {
    out[i * 4] = (h[i] >>> 24) & 0xff;
    out[i * 4 + 1] = (h[i] >>> 16) & 0xff;
    out[i * 4 + 2] = (h[i] >>> 8) & 0xff;
    out[i * 4 + 3] = h[i] & 0xff;
  }
  return out;
}

// HMAC-SHA256（RFC 2104；key 任意长度——TC3 第一层 "TC3"+SecretKey 是变长的根因）
export function hmacSha256(key: Uint8Array, msg: Uint8Array): Uint8Array {
  const block = 64;
  let k = key;
  if (k.length > block) {
    k = sha256(k);
  }
  const ki = new Uint8Array(block);
  const ko = new Uint8Array(block);
  ki.set(k);
  ko.set(k);
  for (let i = 0; i < block; i++) {
    ki[i] ^= 0x36;
    ko[i] ^= 0x5c;
  }
  const inner = new Uint8Array(block + msg.length);
  inner.set(ki);
  inner.set(msg, block);
  const innerHash = sha256(inner);
  const outer = new Uint8Array(block + 32);
  outer.set(ko);
  outer.set(innerHash, block);
  return sha256(outer);
}

export function bytesToHex(b: Uint8Array): string {
  let s = '';
  for (let i = 0; i < b.length; i++) {
    s += (b[i] >>> 4).toString(16);
    s += (b[i] & 0xf).toString(16);
  }
  return s;
}

// 便捷封装：字符串消息 → hex（TC3 各层签名用）
export function hmacSha256Hex(keyStr: string, msgStr: string): string {
  return bytesToHex(hmacSha256(utf8Bytes(keyStr), utf8Bytes(msgStr)));
}

export function sha256HexOfBytes(data: Uint8Array): string {
  return bytesToHex(sha256(data));
}

export function sha256HexOfStr(s: string): string {
  return bytesToHex(sha256(utf8Bytes(s)));
}
