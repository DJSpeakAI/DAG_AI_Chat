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

// 统一调用入口（未初始化重试 1.5s×3；返回原始响应，异常返 null）
async function callWithRetry(payload: Record<string, Object>): Promise<Object | null> {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      return await cloud.callFunction({ name: SP_ADMIN_FN_NAME, params: payload } as FunctionOptions);
    } catch (_e) {
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

// 镜像上报（SpMirror 同主键 upsert 幂等；payload 全字符串值——track-events 埋点同款铁律）
export async function spAdminReport(payload: Record<string, Object>): Promise<boolean> {
  const resp = await callWithRetry(payload);
  return resp !== null;
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
