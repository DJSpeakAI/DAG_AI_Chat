// ============================================================
// SpAdminUtil.ets — SP 数据台传输层（★ 0.301.0 运营旁路）
// ============================================================
// 定位：sp-admin 云函数的纯传输封装——report 镜像上报 / fetch 指令拉取 / confirm 执行回报。
// 依赖纪律（0.223.0 防环军令）：本文件**零 import ChatModel**（参数全基础类型/字符串化），
//   业务层（快照构建/指令执行）在 ChatModel 尾部「SP 数据台」区块——ChatModel → 本文件单向。
// 云函数未部署/无网 = 全静默降级（fetch 返 '[]'、report/confirm 返 false，调用方零阻塞零报错）。
// ★ 0.301.1 实锤：AGC SDK 初始化是异步的（EntryAbility.initAgc），冷启时 callFunction 会抢跑
//   报 "agconnect sdk not initialized"——此处带 1.5s×3 次重试兜底。
// 全案：docs/0.165+/0.301.0 SP 数据台.md
// ============================================================

import cloud, { FunctionOptions } from '@hw-agconnect/cloud';

const SP_ADMIN_FN_NAME = 'sp-admin'; // AGC 云函数名（小写中划线命名铁律——track-events 同款）

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}

// "not initialized"=AGC SDK 未就绪（冷启抢跑）→ 重试 3 次；其余错误直接放弃
function isNotInitialized(err: Object): boolean {
  return `${err}`.indexOf('not initialized') >= 0;
}

// 最近一次通道异常原文（★ 0.313.0：权威记账四接口据此区分 network 与 unknown——
//   云函数旧版/对象类型不匹配（3037004）不能误报成网络问题，门卫文案要准确）
let lastCallError: string = '';

// 统一调用入口（未初始化重试 1.5s×3；返回原始响应，异常返 null）
async function callWithRetry(payload: Record<string, Object>): Promise<Object | null> {
  lastCallError = '';
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      return await cloud.callFunction({ name: SP_ADMIN_FN_NAME, params: payload } as FunctionOptions);
    } catch (_e) {
      lastCallError = `${_e}`;
      if (isNotInitialized(_e) && attempt < 2) {
        await sleep(1500);
        continue;
      }
      return null;
    }
  }
  return null;
}

// 响应字段读取（stringify 双路径——getValue() 返 any 被 arkts-no-any-unknown 拍，0.291.0 定式：
// 顶层直读 + responseBody 嵌套读互为兜底；任何异常返空串由调用方兜 '[]'）
function readStringField(resp: Object, field: string): string {
  try {
    const raw = JSON.stringify(resp);
    if (typeof raw !== 'string' || raw.length === 0) {
      return '';
    }
    const obj = JSON.parse(raw) as Record<string, Object>;
    const top = obj[field];
    if (typeof top === 'string') {
      return top;
    }
    const nested = obj['responseBody'];
    if (nested !== undefined && typeof nested === 'object' && nested !== null) {
      const inner = (nested as Record<string, Object>)[field];
      if (typeof inner === 'string') {
        return inner;
      }
    }
  } catch (_e) {
    return '';
  }
  return '';
}

// 指令拉取（返回指令 JSON 串；'[]' 兜底=未部署/无待执行/异常三态同形，调用方零分支）
export async function spAdminFetch(accountId: string): Promise<string> {
  if (accountId.length === 0) {
    return '[]';
  }
  const payload: Record<string, Object> = {};
  payload['action'] = 'fetch';
  payload['accountId'] = accountId;
  const resp = await callWithRetry(payload);
  if (resp === null) {
    return '[]';
  }
  const out = readStringField(resp, 'commands');
  return out.length > 0 ? out : '[]';
}

// 执行回报（resultAmount=实发/实扣额；云函数侧 claimed 超 10 分钟未 confirm 回 pending 兜底重派）
export async function spAdminConfirm(commandId: string, accountId: string, resultAmount: number): Promise<boolean> {
  if (commandId.length === 0 || accountId.length === 0) {
    return false;
  }
  const payload: Record<string, Object> = {};
  payload['action'] = 'confirm';
  payload['commandId'] = commandId;
  payload['accountId'] = accountId;
  payload['resultAmount'] = `${resultAmount}`;
  const resp = await callWithRetry(payload);
  return resp !== null;
}

// ★ 0.308.0 云同步真值探针：查 default zone Mirror+Ledger 双表有无「他设备」资产痕迹。
//   返回 'yes'=有他设备痕迹（云端大概率有 SP 行，本机拉不到=假开启实锤）；
//   'no'=明确无痕迹（云函数确认无——新账号/仅本机）；'err'=通道失败或响应异常
//   （未部署旧版函数返 unknown action、无网、字段缺失——一律 fail-open 放行但语义归 err，
//   防「空串误判 no」掩盖部署未生效——0.308.1 实锤修复）
export async function spAdminProbe(accountId: string, deviceModel: string): Promise<string> {
  if (accountId.length === 0) {
    return 'no';
  }
  const payload: Record<string, Object> = {};
  payload['action'] = 'probe';
  payload['accountId'] = accountId;
  payload['deviceModel'] = deviceModel;
  const resp = await callWithRetry(payload);
  if (resp === null) {
    return 'err';
  }
  const v = readStringField(resp, 'probe');
  if (v === 'y') {
    return 'yes';
  }
  if (v === 'n') {
    return 'no';
  }
  return 'err'; // 'e' 异常 / 空串（旧版函数 unknown action 等）——无法判定按通道失败处理
}

// ============================================================
// ★ 0.312.0 SP 云函数权威记账（B 方案·根除云空间白嫖）——四接口客户端封装
// 语义：余额权威在云端（SpMirror），一切消耗/发放必须本通道成功才在客户端生效。
// 返回统一 SpAuthResult：ok=false 时 err 区分 no-account/insufficient/network/unknown；
//   通道失败（resp=null）= network；旧版函数（unknown action）= unknown（客户端降级策略自定）。
// 全案：docs/0.312.0 SP云函数权威记账.md
// ============================================================
export class SpAuthResult {
  ok: boolean = false;
  err: string = '';           // no-account / insufficient / network / unknown / 空（成功）
  bal: number = 0;            // 云端权威余额（三池可用合计）
  permSp: number = 0;
  permCons: number = 0;
  bonusSp: number = 0;
  bonusCons: number = 0;
  giftSp: number = 0;
  giftCons: number = 0;
  welcomeGranted: boolean = false;
  amount: number = 0;         // spend 实扣 / grant 实发
  duplicate: boolean = false; // 幂等命中（txId 已记账，本次未重复扣/发）
  hasPools: boolean = false;  // 响应是否带四池明细（sp_balance/sp_init 才有；spend/grant 只回 bal——
                              //   无明细时绝不能覆盖本地镜像，否则会把余额清零）
}

// 字段读取（stringify 定式：Record 值转字符串再解析——绕开 Object 直转 Number/布尔的类型限制）
function strOf(obj: Record<string, Object>, key: string): string {
  const v = obj[key];
  if (v === undefined || v === null) {
    return '';
  }
  return `${v}`;
}

function numOf(obj: Record<string, Object>, key: string): number {
  const n = Number(strOf(obj, key));
  return isNaN(n) ? 0 : n;
}

function boolOf(obj: Record<string, Object>, key: string): boolean {
  const s = strOf(obj, key);
  return s === 'true' || s === '1' || s === 'y';
}

// 响应解析（stringify 双路径同 readStringField 定式——避免 any/索引访问违规）
function parseAuthResult(resp: Object | null): SpAuthResult {
  const out = new SpAuthResult();
  if (resp === null) {
    out.err = 'network';
    return out;
  }
  let obj: Record<string, Object> | null = null;
  try {
    const raw = JSON.stringify(resp);
    const parsed = JSON.parse(raw) as Record<string, Object>;
    obj = parsed;
    const nested = parsed['responseBody'];
    if (nested !== undefined && typeof nested === 'object' && nested !== null) {
      obj = nested as Record<string, Object>;
    }
  } catch (_e) {
    out.err = 'unknown';
    return out;
  }
  if (obj === null) {
    out.err = 'unknown';
    return out;
  }
  out.ok = boolOf(obj, 'ok');
  out.err = strOf(obj, 'err');
  out.bal = numOf(obj, 'bal');
  out.permSp = numOf(obj, 'permSp');
  out.permCons = numOf(obj, 'permCons');
  out.bonusSp = numOf(obj, 'bonusSp');
  out.bonusCons = numOf(obj, 'bonusCons');
  out.giftSp = numOf(obj, 'giftSp');
  out.giftCons = numOf(obj, 'giftCons');
  out.welcomeGranted = boolOf(obj, 'welcomeGranted');
  out.amount = numOf(obj, 'amount') > 0 ? numOf(obj, 'amount') : numOf(obj, 'cost');
  out.duplicate = boolOf(obj, 'duplicate');
  // 四池明细存在判定（有任一池字段=balance/init 响应——spend/grant 只回 bal，不能当明细用）
  out.hasPools = obj['permSp'] !== undefined || obj['bonusSp'] !== undefined || obj['giftSp'] !== undefined;
  if (!out.ok && out.err.length === 0) {
    out.err = 'unknown';
  }
  return out;
}

// 通道异常归类（★ 0.313.0）：AGC 未初始化已由 callWithRetry 内部重试；走到这里=网络/服务异常。
//   仅明确的网络类错误归 network（可重试队列），其余（旧版函数/对象类型不匹配/鉴权）归 unknown
//   ——unknown 不本地降级，门卫提示「服务升级中」，防把配置故障误报成没网。
function authFailureResult(): SpAuthResult {
  const out = new SpAuthResult();
  const e = lastCallError.toLowerCase();
  const networkLike = e.indexOf('network') >= 0 || e.indexOf('timeout') >= 0 || e.indexOf('timed out') >= 0
    || e.indexOf('connection') >= 0 || e.indexOf('socket') >= 0 || e.indexOf('econn') >= 0
    || e.indexOf('unreachable') >= 0 || e.indexOf('dns') >= 0 || e.indexOf('host') >= 0;
  out.err = networkLike ? 'network' : 'unknown';
  return out;
}

// 权威记账统一调用（返回结构化结果，绝不抛）
async function callAuth(payload: Record<string, Object>): Promise<SpAuthResult> {
  const resp = await callWithRetry(payload);
  if (resp === null) {
    return authFailureResult();
  }
  return parseAuthResult(resp);
}

// 查权威余额（no-account=云端无账本，调用方走 spAuthInit）
export async function spAuthBalance(accountId: string): Promise<SpAuthResult> {
  const payload: Record<string, Object> = {};
  payload['action'] = 'sp_balance';
  payload['accountId'] = accountId;
  return callAuth(payload);
}

// 初始化云端账本（云端已有记录则忽略入参返回现有余额——绝不覆盖，数据安全第一）
export async function spAuthInit(accountId: string, permSp: number, permCons: number,
  bonusSp: number, bonusCons: number, giftSp: number, giftCons: number,
  welcomeGranted: boolean, deviceModel: string): Promise<SpAuthResult> {
  const payload: Record<string, Object> = {};
  payload['action'] = 'sp_init';
  payload['accountId'] = accountId;
  payload['permSp'] = `${Math.max(0, Math.floor(permSp))}`;
  payload['permCons'] = `${Math.max(0, Math.floor(permCons))}`;
  payload['bonusSp'] = `${Math.max(0, Math.floor(bonusSp))}`;
  payload['bonusCons'] = `${Math.max(0, Math.floor(bonusCons))}`;
  payload['giftSp'] = `${Math.max(0, Math.floor(giftSp))}`;
  payload['giftCons'] = `${Math.max(0, Math.floor(giftCons))}`;
  payload['welcomeGranted'] = welcomeGranted ? '1' : '0';
  payload['deviceModel'] = deviceModel;
  return callAuth(payload);
}

// 事务扣点（txId 幂等——重试不双扣；不足=insufficient 拦截）
export async function spAuthSpend(accountId: string, txId: string, cost: number,
  scene: string, note: string, deviceModel: string): Promise<SpAuthResult> {
  const payload: Record<string, Object> = {};
  payload['action'] = 'sp_spend';
  payload['accountId'] = accountId;
  payload['txId'] = txId;
  payload['cost'] = `${Math.max(1, Math.floor(cost))}`;
  payload['scene'] = scene;
  payload['note'] = note;
  payload['deviceModel'] = deviceModel;
  return callAuth(payload);
}

// 事务加池（txId 幂等；pool=gift|bonus|perm）
export async function spAuthGrant(accountId: string, txId: string, src: string,
  amount: number, pool: string, note: string, deviceModel: string): Promise<SpAuthResult> {
  const payload: Record<string, Object> = {};
  payload['action'] = 'sp_grant';
  payload['accountId'] = accountId;
  payload['txId'] = txId;
  payload['src'] = src;
  payload['amount'] = `${Math.max(1, Math.floor(amount))}`;
  payload['pool'] = pool;
  payload['note'] = note;
  payload['deviceModel'] = deviceModel;
  return callAuth(payload);
}
