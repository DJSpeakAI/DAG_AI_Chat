// ============================================================
// ZstdUtil.ets — ★ 0.227.0 Zstandard 解码器（纯 ArkTS，零原生依赖）
// ============================================================
// 移植自 fzstd 0.1.1（作者 101arrowz，MIT License）解压部分，
// 供新版 Anki apkg（24.11+）的 collection.anki21b / media / 媒体文件解码。
// 移植纪律（ArkTS 严格模式）：无解构、无逗号表达式、无表达式内赋值、
//   全部显式类型；fzstd 的元组返回改为结果类、鸭子对象改为具名类。
// 用法：zstdDecompress(new Uint8Array(zstdBytes)) → 解码后 Uint8Array
// ============================================================

/** FSE 解码表（zstd 序列/字面量熵编码状态机） */
class FseTable {
  b: number = 0;                      // accuracy log（状态位数）
  s: Uint8Array = new Uint8Array(0);  // 每状态符号
  n: Uint8Array = new Uint8Array(0);  // 每状态消耗位数
  t: Uint16Array = new Uint16Array(0); // 下一状态基值
}

/** Huffman 解码表（字面量段） */
class HufTable {
  n: Uint8Array = new Uint8Array(0); // 每状态消耗位数
  b: number = 0;                     // 最大位数
  s: Uint8Array = new Uint8Array(0); // 每状态符号
}

/** rfse/rhu 的返回（原 fzstd 元组 [bt, table]） */
class FseReadResult {
  bt: number = 0;
  table: FseTable = new FseTable();
}

class HufReadResult {
  bt: number = 0;
  table: HufTable = new HufTable();
}

/** zstd 帧状态（原 fzstd 匿名对象） */
class ZFrameState {
  b: number = 0;                       // 当前字节位
  y: number = 0;                       // 输出写入位
  l: number = 0;                       // 当前块是否最后一块
  d: number = 0;                       // 字典 id
  w: Uint8Array = new Uint8Array(0);   // 滑动窗口
  e: number = 0;                       // 窗口有效长度
  o: Int32Array = new Int32Array(3);   // repeat offsets（初值 1/4/8）
  u: number = 0;                       // 帧内容长度（0=未知）
  c: number = 0;                       // 是否带校验和
  m: number = 0;                       // 单块最大字节数
  h: HufTable | undefined = undefined; // 块间复用的 Huffman 表
  t: FseTable[] | undefined = undefined; // 块间复用的 FSE 表
}

const EC: string[] = [
  'invalid zstd data',
  'window size too large',
  'invalid block type',
  'FSE accuracy too high',
  'match distance too far back',
  'unexpected EOF'
];

function zerr(ind: number): Error {
  return new Error(EC[ind]);
}

/** Uint8Array 切片（手动实现，规避原型链调用） */
function slc(v: Uint8Array, s: number, e: number): Uint8Array {
  const st = s < 0 ? 0 : s;
  const en = e > v.length ? v.length : e;
  const n = new Uint8Array(en - st);
  n.set(v.subarray(st, en));
  return n;
}

/** 区间填充 */
function fill(v: Uint8Array, n: number, s: number, e: number): void {
  let i = s < 0 ? 0 : s;
  const en = e > v.length ? v.length : e;
  for (; i < en; ++i) {
    v[i] = n;
  }
}

/** 区间左移拷贝（窗口滑动） */
function cpw(v: Uint8Array, t: number, s: number, e: number): void {
  let i = s < 0 ? 0 : s;
  const en = e > v.length ? v.length : e;
  while (i < en) {
    v[t] = v[i];
    ++t;
    ++i;
  }
}

/** 小端读 n 字节 */
function rb(d: Uint8Array, b: number, n: number): number {
  let i = 0;
  let o = 0;
  for (; i < n; ++i) {
    o |= d[b] << (i << 3);
    ++b;
  }
  return o;
}

function b4(d: Uint8Array, b: number): number {
  return (d[b] | (d[b + 1] << 8) | (d[b + 2] << 16) | (d[b + 3] << 24)) >>> 0;
}

/**
 * 读 zstd 帧头。返回 ZFrameState（正常帧）或 number（可跳帧的字节数）。
 * 始终按「精确分配」模式（fzstd w=1）：帧长已知时输出缓冲=帧长。
 */
function rzfh(dat: Uint8Array): ZFrameState | number {
  const n3 = dat[0] | (dat[1] << 8) | (dat[2] << 16);
  if (n3 === 0x2FB528 && dat[3] === 253) {
    // Zstandard 帧
    const flg = dat[4];
    const ss = (flg >> 5) & 1;      // single segment
    const cc = (flg >> 2) & 1;      // checksum
    const df = flg & 3;             // dict flag
    const fcf = flg >> 6;           // frame content size 位数档
    if ((flg & 8) !== 0) {
      throw zerr(0);
    }
    let bt = 6 - ss;
    const db = df === 3 ? 4 : df;
    const di = rb(dat, bt, db);
    bt += db;
    const fsb = fcf !== 0 ? (1 << fcf) : ss;
    const fss = rb(dat, bt, fsb) + (fcf === 1 ? 256 : 0);
    let ws = fss;
    if (ss === 0) {
      const wb = 1 << (10 + (dat[5] >> 3));
      ws = wb + (wb >> 3) * (dat[5] & 7);
    }
    if (ws > 2145386496) {
      throw zerr(1);
    }
    const buf = new Uint8Array((fss !== 0 ? fss : ws) + 12);
    buf[0] = 1;
    buf[4] = 4;
    buf[8] = 8;
    const st = new ZFrameState();
    st.b = bt + fsb;
    st.y = 0;
    st.l = 0;
    st.d = di;
    st.w = buf.subarray(12, buf.length);
    st.e = ws;
    st.o = new Int32Array(buf.buffer, 0, 3); // 初值即 [1,4,8]（buf 前 12 字节复用）
    st.u = fss;
    st.c = cc;
    st.m = Math.min(131072, ws);
    return st;
  } else if (((n3 >> 4) | (dat[3] << 20)) === 0x184D2A5) {
    // 可跳帧：返回应跳过的字节数
    return b4(dat, 4) + 8;
  }
  throw zerr(0);
}

/** 非零数的最高有效位 */
function msb(val: number): number {
  let bits = 0;
  while ((1 << bits) <= val) {
    ++bits;
  }
  return bits - 1;
}

/** 读 FSE 表（有限状态熵） */
function rfse(dat: Uint8Array, bt: number, mal: number): FseReadResult {
  let tpos = (bt << 3) + 4;
  const al = (dat[bt] & 15) + 5;
  if (al > mal) {
    throw zerr(3);
  }
  const sz = 1 << al;
  let probs = sz;
  let sym = -1;
  let re = -1;
  let i = -1;
  let ht = sz;
  const buf = new ArrayBuffer(512 + (sz << 2));
  const freq = new Int16Array(buf, 0, 256);
  const dstate = new Uint16Array(buf, 0, 256);
  const nstate = new Uint16Array(buf, 512, sz);
  const bb1 = 512 + (sz << 1);
  const syms = new Uint8Array(buf, bb1, sz);
  const nbits = new Uint8Array(buf, bb1 + sz);
  while (sym < 255 && probs > 0) {
    const bits = msb(probs + 1);
    const cbt = tpos >> 3;
    const msk = (1 << (bits + 1)) - 1;
    let val = ((dat[cbt] | (dat[cbt + 1] << 8) | (dat[cbt + 2] << 16)) >> (tpos & 7)) & msk;
    const msk1fb = (1 << bits) - 1;
    const msv = msk - probs - 1;
    const sval = val & msk1fb;
    if (sval < msv) {
      tpos += bits;
      val = sval;
    } else {
      tpos += bits + 1;
      if (val > msk1fb) {
        val -= msv;
      }
    }
    ++sym;
    --val;
    freq[sym] = val;
    if (val === -1) {
      probs += val;
      --ht;
      syms[ht] = sym;
    } else {
      probs -= val;
    }
    if (val === 0) {
      do {
        const rbt = tpos >> 3;
        re = ((dat[rbt] | (dat[rbt + 1] << 8)) >> (tpos & 7)) & 3;
        tpos += 2;
        sym += re;
      } while (re === 3);
    }
  }
  if (sym > 255 || probs !== 0) {
    throw zerr(0);
  }
  let sympos = 0;
  const sstep = (sz >> 1) + (sz >> 3) + 3;
  const smask = sz - 1;
  let s = 0;
  for (; s <= sym; ++s) {
    const sf = freq[s];
    if (sf < 1) {
      dstate[s] = -sf;
      continue;
    }
    for (i = 0; i < sf; ++i) {
      syms[sympos] = s;
      do {
        sympos = (sympos + sstep) & smask;
      } while (sympos >= ht);
    }
  }
  if (sympos !== 0) {
    throw zerr(0);
  }
  for (i = 0; i < sz; ++i) {
    const ns = dstate[syms[i]];
    dstate[syms[i]] = ns + 1;
    const nb = al - msb(ns);
    nbits[i] = nb;
    nstate[i] = (ns << nb) - sz;
  }
  const res = new FseReadResult();
  res.bt = (tpos + 7) >> 3;
  const tbl = new FseTable();
  tbl.b = al;
  tbl.s = syms;
  tbl.n = nbits;
  tbl.t = nstate;
  res.table = tbl;
  return res;
}

/** 读 Huffman 权重表 */
function rhu(dat: Uint8Array, bt: number): HufReadResult {
  let i = 0;
  let wc = -1;
  const buf = new Uint8Array(292);
  const hb = dat[bt];
  const hw = buf.subarray(0, 256);
  const rc = buf.subarray(256, 268);
  const ri = new Uint16Array(buf.buffer, 268);
  if (hb < 128) {
    // FSE 编码的权重流
    const fr = rfse(dat, bt + 1, 6);
    const ebt = fr.bt;
    const fdt = fr.table;
    bt += hb;
    const epos = ebt << 3;
    const lb = dat[bt];
    if (lb === 0) {
      throw zerr(0);
    }
    let st1 = 0;
    let st2 = 0;
    let btr1 = fdt.b;
    let btr2 = btr1;
    ++bt;
    let fpos = (bt << 3) - 8 + msb(lb);
    while (true) {
      fpos -= btr1;
      if (fpos < epos) {
        break;
      }
      let cbt = fpos >> 3;
      st1 += ((dat[cbt] | (dat[cbt + 1] << 8)) >> (fpos & 7)) & ((1 << btr1) - 1);
      ++wc;
      hw[wc] = fdt.s[st1];
      fpos -= btr2;
      if (fpos < epos) {
        break;
      }
      cbt = fpos >> 3;
      st2 += ((dat[cbt] | (dat[cbt + 1] << 8)) >> (fpos & 7)) & ((1 << btr2) - 1);
      ++wc;
      hw[wc] = fdt.s[st2];
      btr1 = fdt.n[st1];
      st1 = fdt.t[st1];
      btr2 = fdt.n[st2];
      st2 = fdt.t[st2];
    }
    ++wc;
    if (wc > 255) {
      throw zerr(0);
    }
  } else {
    // 直接 4bit 权重
    wc = hb - 127;
    for (; i < wc; i += 2) {
      ++bt;
      const byte = dat[bt];
      hw[i] = byte >> 4;
      hw[i + 1] = byte & 15;
    }
    ++bt;
  }
  let wes = 0;
  for (i = 0; i < wc; ++i) {
    const wt = hw[i];
    if (wt > 11) {
      throw zerr(0);
    }
    if (wt !== 0) {
      wes += 1 << (wt - 1);
    }
  }
  const mb = msb(wes) + 1;
  const ts = 1 << mb;
  const rem = ts - wes;
  if ((rem & (rem - 1)) !== 0) {
    throw zerr(0);
  }
  hw[wc] = msb(rem) + 1;
  ++wc;
  for (i = 0; i < wc; ++i) {
    const wt = hw[i];
    const nwt = wt !== 0 ? mb + 1 - wt : 0;
    hw[i] = nwt;
    rc[nwt] = rc[nwt] + 1;
  }
  const hbuf = new Uint8Array(ts << 1);
  const hsyms = hbuf.subarray(0, ts);
  const nb = hbuf.subarray(ts, hbuf.length);
  ri[mb] = 0;
  for (i = mb; i > 0; --i) {
    const pv = ri[i];
    const nv = pv + rc[i] * (1 << (mb - i));
    fill(nb, i, pv, nv);
    ri[i - 1] = nv;
  }
  if (ri[0] !== ts) {
    throw zerr(0);
  }
  for (i = 0; i < wc; ++i) {
    const bits = hw[i];
    if (bits !== 0) {
      const code = ri[bits];
      const ncode = code + (1 << (mb - bits));
      fill(hsyms, i, code, ncode);
      ri[bits] = ncode;
    }
  }
  const res = new HufReadResult();
  res.bt = bt;
  const tbl = new HufTable();
  tbl.n = nb;
  tbl.b = mb;
  tbl.s = hsyms;
  res.table = tbl;
  return res;
}

function u8a(vals: number[]): Uint8Array {
  const u = new Uint8Array(vals.length);
  for (let k = 0; k < vals.length; ++k) {
    u[k] = vals[k];
  }
  return u;
}

// zstd 预定义序列表（fzstd 内置常量，原文照抄）
const dllt: FseTable = rfse(u8a([81, 16, 99, 140, 49, 198, 24, 99, 12, 33, 196, 24, 99, 102, 102, 134, 70, 146, 4]), 0, 6).table;
const dmlt: FseTable = rfse(u8a([33, 20, 196, 24, 99, 140, 33, 132, 16, 66, 8, 33, 132, 16, 66, 8, 33, 68, 68, 68, 68, 68, 68, 68, 68, 36, 9]), 0, 6).table;
const doct: FseTable = rfse(u8a([32, 132, 16, 66, 102, 70, 68, 68, 68, 68, 36, 73, 2]), 0, 5).table;

function b2bl(b: Uint8Array, s: number): Int32Array {
  const len = b.length;
  const bl = new Int32Array(len);
  let sv = s;
  for (let i = 0; i < len; ++i) {
    bl[i] = sv;
    sv += 1 << b[i];
  }
  return bl;
}

// 预定义额外位数表（字面量长度/匹配长度）
const llb: Uint8Array = new Uint8Array(new Int32Array([0, 0, 0, 0, 16843009, 50528770, 134678020, 202050057, 269422093]).buffer, 0, 36);
const llbl: Int32Array = b2bl(llb, 0);
const mlb: Uint8Array = new Uint8Array(new Int32Array([0, 0, 0, 0, 0, 0, 0, 0, 16843009, 50528770, 117769220, 185207048, 252579084, 16]).buffer, 0, 53);
const mlbl: Int32Array = b2bl(mlb, 3);

/** 解码 Huffman 字面量流（单流） */
function dhu(dat: Uint8Array, out: Uint8Array, hu: HufTable): void {
  const len = dat.length;
  const ss = out.length;
  const lb = dat[len - 1];
  const msk = (1 << hu.b) - 1;
  const eb = -hu.b;
  if (lb === 0) {
    throw zerr(0);
  }
  let st = 0;
  let btr = hu.b;
  let pos = (len << 3) - 8 + msb(lb) - btr;
  let i = -1;
  while (pos > eb && i < ss) {
    const cbt = pos >> 3;
    const val = (dat[cbt] | (dat[cbt + 1] << 8) | (dat[cbt + 2] << 16)) >> (pos & 7);
    st = ((st << btr) | val) & msk;
    ++i;
    out[i] = hu.s[st];
    btr = hu.n[st];
    pos -= btr;
  }
  if (pos !== eb || i + 1 !== ss) {
    throw zerr(0);
  }
}

/** 解码 Huffman 字面量流（4 流交错） */
function dhu4(dat: Uint8Array, out: Uint8Array, hu: HufTable): void {
  let bt = 6;
  const ss = out.length;
  const sz1 = (ss + 3) >> 2;
  const sz2 = sz1 << 1;
  const sz3 = sz1 + sz2;
  const l1 = dat[0] | (dat[1] << 8);
  dhu(dat.subarray(bt, bt + l1), out.subarray(0, sz1), hu);
  bt += l1;
  const l2 = dat[2] | (dat[3] << 8);
  dhu(dat.subarray(bt, bt + l2), out.subarray(sz1, sz2), hu);
  bt += l2;
  const l3 = dat[4] | (dat[5] << 8);
  dhu(dat.subarray(bt, bt + l3), out.subarray(sz2, sz3), hu);
  bt += l3;
  dhu(dat.subarray(bt, dat.length), out.subarray(sz3, out.length), hu);
}

/**
 * 解码一个 zstd 块。
 * out 提供=写入输出缓冲（帧精确模式）；否则返回本块新缓冲。
 * 数据不足返回 undefined（上层转 EOF 错误）。
 */
function rzb(dat: Uint8Array, st: ZFrameState, out: Uint8Array | undefined): Uint8Array | undefined {
  let bt = st.b;
  const b0 = dat[bt];
  const btype = (b0 >> 1) & 3;
  st.l = b0 & 1;
  const sz = (b0 >> 3) | (dat[bt + 1] << 5) | (dat[bt + 2] << 13);
  bt += 3;
  const ebt = bt + sz;
  if (btype === 1) {
    // RLE 块
    if (bt >= dat.length) {
      return undefined;
    }
    st.b = bt + 1;
    if (out !== undefined) {
      fill(out, dat[bt], st.y, st.y + sz);
      st.y += sz;
      return out;
    }
    const rle = new Uint8Array(sz);
    fill(rle, dat[bt], 0, sz);
    return rle;
  }
  if (ebt > dat.length) {
    return undefined;
  }
  if (btype === 0) {
    // 原始块
    st.b = ebt;
    if (out !== undefined) {
      out.set(dat.subarray(bt, ebt), st.y);
      st.y += sz;
      return out;
    }
    return slc(dat, bt, ebt);
  }
  if (btype === 2) {
    // 压缩块
    const b3 = dat[bt];
    const lbt = b3 & 3;
    const sf = (b3 >> 2) & 3;
    let lss = b3 >> 4;
    let lcs = 0;
    let s4 = 0;
    if (lbt < 2) {
      if ((sf & 1) !== 0) {
        ++bt;
        lss |= dat[bt] << 4;
        if ((sf & 2) !== 0) {
          ++bt;
          lss |= dat[bt] << 12;
        }
      } else {
        lss = b3 >> 3;
      }
    } else {
      s4 = sf;
      if (sf < 2) {
        ++bt;
        lss |= (dat[bt] & 63) << 4;
        const hi = dat[bt] >> 6;
        ++bt;
        lcs = hi | (dat[bt] << 2);
      } else if (sf === 2) {
        ++bt;
        lss |= dat[bt] << 4;
        ++bt;
        lss |= (dat[bt] & 3) << 12;
        const mid = dat[bt] >> 2;
        ++bt;
        lcs = mid | (dat[bt] << 6);
      } else {
        ++bt;
        lss |= dat[bt] << 4;
        ++bt;
        lss |= (dat[bt] & 63) << 12;
        const h1 = dat[bt] >> 6;
        ++bt;
        const h2 = dat[bt] << 2;
        ++bt;
        lcs = h1 | h2 | (dat[bt] << 10);
      }
    }
    ++bt;
    // 字面量暂存区（挂在输出尾部，绝不与后向引用重叠）
    let buf: Uint8Array = out !== undefined ? out.subarray(st.y, st.y + st.m) : new Uint8Array(st.m);
    let spl = buf.length - lss;
    if (lbt === 0) {
      buf.set(dat.subarray(bt, bt + lss), spl);
      bt += lss;
    } else if (lbt === 1) {
      fill(buf, dat[bt], spl, buf.length);
      ++bt;
    } else {
      let hu = st.h;
      if (lbt === 2) {
        const hud = rhu(dat, bt);
        lcs += bt - hud.bt;
        bt = hud.bt;
        hu = hud.table;
        st.h = hu;
      } else if (hu === undefined) {
        throw zerr(0);
      }
      const dst = dat.subarray(bt, bt + lcs);
      const obuf = buf.subarray(spl, buf.length);
      if (s4 !== 0) {
        dhu4(dst, obuf, hu);
      } else {
        dhu(dst, obuf, hu);
      }
      bt += lcs;
    }
    // 序列段
    let ns = dat[bt];
    ++bt;
    if (ns !== 0) {
      if (ns === 255) {
        const lo = dat[bt];
        ++bt;
        const hi2 = dat[bt];
        ++bt;
        ns = (lo | (hi2 << 8)) + 0x7F00;
      } else if (ns > 127) {
        const lo = dat[bt];
        ++bt;
        ns = ((ns - 128) << 8) | lo;
      }
      const scm = dat[bt];
      ++bt;
      if ((scm & 3) !== 0) {
        throw zerr(0);
      }
      const dts: FseTable[] = [dmlt, doct, dllt];
      let ii = 2;
      for (; ii > -1; --ii) {
        const md = (scm >> ((ii << 1) + 2)) & 3;
        if (md === 1) {
          // RLE 模式：单符号表
          const rbuf = new Uint8Array(3);
          rbuf[2] = dat[bt];
          ++bt;
          const rt = new FseTable();
          rt.s = rbuf.subarray(2, 3);
          rt.n = rbuf.subarray(0, 1);
          rt.t = new Uint16Array(rbuf.buffer, 0, 1);
          rt.b = 0;
          dts[ii] = rt;
        } else if (md === 2) {
          const fr = rfse(dat, bt, 9 - (ii & 1));
          bt = fr.bt;
          dts[ii] = fr.table;
        } else if (md === 3) {
          if (st.t === undefined) {
            throw zerr(0);
          }
          dts[ii] = st.t[ii];
        }
      }
      st.t = dts;
      const mlt = dts[0];
      const oct = dts[1];
      const llt = dts[2];
      const lb = dat[ebt - 1];
      if (lb === 0) {
        throw zerr(0);
      }
      let spos = (ebt << 3) - 8 + msb(lb) - llt.b;
      let cbt = spos >> 3;
      let oubt = 0;
      let lst = ((dat[cbt] | (dat[cbt + 1] << 8)) >> (spos & 7)) & ((1 << llt.b) - 1);
      spos -= oct.b;
      cbt = spos >> 3;
      let ost = ((dat[cbt] | (dat[cbt + 1] << 8)) >> (spos & 7)) & ((1 << oct.b) - 1);
      spos -= mlt.b;
      cbt = spos >> 3;
      let mst = ((dat[cbt] | (dat[cbt + 1] << 8)) >> (spos & 7)) & ((1 << mlt.b) - 1);
      ++ns;
      while (--ns !== 0) {
        const llc = llt.s[lst];
        const lbtr = llt.n[lst];
        const mlc = mlt.s[mst];
        const mbtr = mlt.n[mst];
        const ofc = oct.s[ost];
        const obtr = oct.n[ost];
        spos -= ofc;
        cbt = spos >> 3;
        const ofp = 1 << ofc;
        const off = ofp + (((dat[cbt] | (dat[cbt + 1] << 8) | (dat[cbt + 2] << 16) | (dat[cbt + 3] << 24)) >>> (spos & 7)) & (ofp - 1));
        spos -= mlb[mlc];
        cbt = spos >> 3;
        let ml = mlbl[mlc] + (((dat[cbt] | (dat[cbt + 1] << 8) | (dat[cbt + 2] << 16)) >> (spos & 7)) & ((1 << mlb[mlc]) - 1));
        spos -= llb[llc];
        cbt = spos >> 3;
        const ll = llbl[llc] + (((dat[cbt] | (dat[cbt + 1] << 8) | (dat[cbt + 2] << 16)) >> (spos & 7)) & ((1 << llb[llc]) - 1));
        spos -= lbtr;
        cbt = spos >> 3;
        lst = llt.t[lst] + (((dat[cbt] | (dat[cbt + 1] << 8)) >> (spos & 7)) & ((1 << lbtr) - 1));
        spos -= mbtr;
        cbt = spos >> 3;
        mst = mlt.t[mst] + (((dat[cbt] | (dat[cbt + 1] << 8)) >> (spos & 7)) & ((1 << mbtr) - 1));
        spos -= obtr;
        cbt = spos >> 3;
        ost = oct.t[ost] + (((dat[cbt] | (dat[cbt + 1] << 8)) >> (spos & 7)) & ((1 << obtr) - 1));
        // repeat offset 状态更新
        let roff: number;
        if (off > 3) {
          st.o[2] = st.o[1];
          st.o[1] = st.o[0];
          roff = off - 3;
          st.o[0] = roff;
        } else {
          const idx = off - (ll !== 0 ? 1 : 0);
          if (idx !== 0) {
            roff = idx === 3 ? st.o[0] - 1 : st.o[idx];
            if (idx > 1) {
              st.o[2] = st.o[1];
            }
            st.o[1] = st.o[0];
            st.o[0] = roff;
          } else {
            roff = st.o[0];
          }
        }
        // 拷贝字面量
        let ci = 0;
        for (; ci < ll; ++ci) {
          buf[oubt + ci] = buf[spl + ci];
        }
        oubt += ll;
        spl += ll;
        let stin = oubt - roff;
        if (stin < 0) {
          // 引用越过块起点 → 从窗口补
          let len = -stin;
          const bs = st.e + stin;
          if (len > ml) {
            len = ml;
          }
          let wi = 0;
          for (; wi < len; ++wi) {
            buf[oubt + wi] = st.w[bs + wi];
          }
          oubt += len;
          ml -= len;
          stin = 0;
        }
        let mi = 0;
        for (; mi < ml; ++mi) {
          buf[oubt + mi] = buf[stin + mi];
        }
        oubt += ml;
      }
      if (oubt !== spl) {
        // 剩余未引用字面量全量搬出
        while (spl < buf.length) {
          buf[oubt] = buf[spl];
          ++oubt;
          ++spl;
        }
      } else {
        oubt = buf.length;
      }
      if (out !== undefined) {
        st.y += oubt;
      } else {
        buf = slc(buf, 0, oubt);
      }
    } else {
      // 无序列：纯字面量块
      if (out !== undefined) {
        st.y += lss;
        if (spl !== 0) {
          let li = 0;
          for (; li < lss; ++li) {
            buf[li] = buf[spl + li];
          }
        }
      } else if (spl !== 0) {
        buf = slc(buf, spl, buf.length);
      }
    }
    st.b = ebt;
    return buf;
  }
  throw zerr(2);
}

/** 多缓冲拼接 */
function cct(bufs: Uint8Array[], ol: number): Uint8Array {
  if (bufs.length === 1) {
    return bufs[0];
  }
  const buf = new Uint8Array(ol);
  let b = 0;
  for (let i = 0; i < bufs.length; ++i) {
    buf.set(bufs[i], b);
    b += bufs[i].length;
  }
  return buf;
}

/**
 * Zstandard 解压（主入口）。支持多帧/可跳帧/带校验和（校验和不验证）。
 * 输出可能为窗口 subarray（byteOffset=12），需要干净缓冲时用 u8Copy。
 */
export function zstdDecompress(dat: Uint8Array): Uint8Array {
  const bufs: Uint8Array[] = [];
  let buf: Uint8Array | undefined = undefined;
  let bt = 0;
  let ol = 0;
  let d: Uint8Array = dat;
  while (d.length > 0) {
    const fr = rzfh(d);
    if (fr instanceof ZFrameState) {
      const st = fr;
      buf = undefined;
      if (st.w.length === st.u) {
        // 帧长已知：直接用窗口作输出缓冲（精确分配）
        buf = st.w;
        bufs.push(buf);
        ol += st.u;
      }
      while (st.l === 0) {
        const blk = rzb(d, st, buf);
        if (blk === undefined) {
          throw zerr(5);
        }
        if (buf !== undefined) {
          st.e = st.y;
        } else {
          bufs.push(blk);
          ol += blk.length;
          cpw(st.w, 0, blk.length, st.w.length);
          st.w.set(blk, st.w.length - blk.length);
        }
      }
      bt = st.b + (st.c !== 0 ? 4 : 0);
    } else {
      bt = fr;
    }
    d = d.subarray(bt, d.length);
  }
  return cct(bufs, ol);
}

/** 拷贝为独立缓冲的 Uint8Array（byteOffset=0、buffer 长度=元素数） */
export function u8Copy(u: Uint8Array): Uint8Array {
  const n = new Uint8Array(u.length);
  n.set(u);
  return n;
}

/** zstd 魔数检测（28 b5 2f fd） */
export function isZstd(u: Uint8Array): boolean {
  return u.length >= 4 && u[0] === 0x28 && u[1] === 0xb5 && u[2] === 0x2f && u[3] === 0xfd;
}
