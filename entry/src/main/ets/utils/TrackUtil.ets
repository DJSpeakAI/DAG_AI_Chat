// ============================================================
// TrackUtil.ets — ★ 0.206.0 用户行为埋点（数据驱动决策：播客模式等伪需求验证）
// ============================================================
// 架构（用户拍板方案 C）：track() 统一接口 → 隐私闸门（默认关）→ 攒批队列
//   → AGC 云函数 trackEvents → Cloud DB events 表 → AGC 控制台查看/导出 Excel。
// 双保险：hiAppEvent 同步落系统事件域（本地诊断可查，不依赖网络）。
// 断网不丢：上报失败队列保留，下次 flush 重试。
// 埋��字典：docs/埋点字典.md（事件 ID ↔ 中文按钮对照——AI/用户查询入口，加新埋点必须同步登记）
// ============================================================

import { preferences } from '@kit.ArkData';
import { hiAppEvent, hilog } from '@kit.PerformanceAnalysisKit';
import cloud, { FunctionOptions } from '@hw-agconnect/cloud';

const PREF_TRACK = 'track_settings';
const KEY_ENABLED = 'analytics_enabled'; // 隐私开关（默认 false——用户拍板合规）
const KEY_QUEUE = 'event_queue';         // 攒批队列（JSON 数组）
const QUEUE_FLUSH_SIZE = 20;             // 攒够 20 条自动上报
const CLOUD_FN_NAME = 'track-events'; // AGC 云函数名（★ 命名规则：仅小写/数字/中划线——trackEvents 大写被拒，0.206.1 改）
const TRACK_TAG = 'DAGAI_TE';         // hilog 标签（flush 成败可查——0.206.2 前全静默无法诊断）
const QUEUE_MAX = 200;                // 失败回滚合并后队列上限（防长期断网无限膨胀——超出丢最旧）

/** 队列条目（.ts 风格平铺——云函数参数只认基础类型） */
interface TrackedEvent {
  e: string;                 // event id
  p: string;                 // params JSON 串（可能为空）
  t: number;                 // 发生时间戳 ms
}

function getPref(context: Context): preferences.Preferences {
  return preferences.getPreferencesSync(context, { name: PREF_TRACK });
}

/** 隐私开关状态（默认关） */
export function isTrackingEnabled(context: Context): boolean {
  try {
    return (getPref(context).getSync(KEY_ENABLED, false) as boolean) === true;
  } catch (_e) {
    return false;
  }
}

/**
 * 设置隐私开关。关闭时清空未上报队列（合规：用户撤回同意后，未上传的数据不再上传）。
 */
export function setTrackingEnabled(context: Context, on: boolean): void {
  try {
    const pref = getPref(context);
    pref.putSync(KEY_ENABLED, on);
    if (!on) {
      pref.putSync(KEY_QUEUE, '[]');
    }
    pref.flush();
  } catch (_e) {
    // 静默
  }
}

/**
 * 埋点统一入口（全项目唯一写法：track(ctx, 'podcast_mode', {page:'chat'})）。
 * 未开隐私开关 → 直接返回（零开销）；开启 → hiAppEvent 本地双落 + 入队（满 20 条自动上报）。
 */
export function track(context: Context, eventId: string, params?: Record<string, string>): void {
  if (!isTrackingEnabled(context)) {
    return;
  }
  // 双保险：系统事件域（本地 hiview 可查——诊断兜底，不依赖云端）
  try {
    const emptyParams: Record<string, string> = {};
    const info: hiAppEvent.AppEventInfo = {
      domain: 'dagai',
      name: eventId,
      eventType: hiAppEvent.EventType.BEHAVIOR,
      params: params === undefined ? emptyParams : params
    };
    hiAppEvent.write(info).catch(() => {
      // 本地落失败静默（云端队列为主）
    });
  } catch (_e) {
    // 静默
  }
  // 入队
  try {
    const pref = getPref(context);
    const q = JSON.parse(pref.getSync(KEY_QUEUE, '[]') as string) as TrackedEvent[];
    const ev: TrackedEvent = { e: eventId, p: params === undefined ? '' : JSON.stringify(params), t: Date.now() };
    q.push(ev);
    if (q.length >= QUEUE_FLUSH_SIZE) {
      pref.putSync(KEY_QUEUE, '[]'); // 先清（防上报中重复入队）——失败有 hiAppEvent 兜底
      pref.flush();
      flushToCloud(context, q);
    } else {
      pref.putSync(KEY_QUEUE, JSON.stringify(q));
      pref.flush();
    }
  } catch (_e) {
    // 静默
  }
}

/**
 * 上报队列到 AGC 云函数（成功静默；失败静默保留队列由下次重试——调用方兜底版带返回值）。
 * 触发时机：满 20 条 / 应用退后台（EntryAbility.onBackground）。
 */
export function flushTrackQueue(context: Context): void {
  try {
    const pref = getPref(context);
    const q = JSON.parse(pref.getSync(KEY_QUEUE, '[]') as string) as TrackedEvent[];
    if (q.length === 0) {
      return;
    }
    pref.putSync(KEY_QUEUE, '[]');
    pref.flush();
    flushToCloud(context, q);
  } catch (_e) {
    // 静默
  }
}

function flushToCloud(context: Context, events: TrackedEvent[]): void {
  try {
    // 云函数参数平铺（见 docs/cloud/trackEvents部署指引.md——events: [{e,p,t}...] JSON 串）
    const payload: Record<string, Object> = {};
    payload['events'] = JSON.stringify(events);
    const opt: FunctionOptions = { name: CLOUD_FN_NAME, params: payload };
    cloud.callFunction(opt).then(() => {
      hilog.info(0x0000, TRACK_TAG, 'flush ok n=%{public}d', events.length);
    }).catch(() => {
      // ★ 0.206.2：失败回滚队列（真·断网不丢——0.206.0/1 "先清后发"失败即丢，顶部注释承诺未兑现）。
      //   典型场景：onBackground flush 被鸿蒙后台网络限制掐掉 → 此处回滚 → onForeground/下次满批补发。
      hilog.warn(0x0000, TRACK_TAG, 'flush fail, rollback n=%{public}d', events.length);
      try {
        const pref = getPref(context);
        const q = JSON.parse(pref.getSync(KEY_QUEUE, '[]') as string) as TrackedEvent[];
        for (const ev of events) {
          q.push(ev);
        }
        q.sort((a: TrackedEvent, b: TrackedEvent) => a.t - b.t);
        if (q.length > QUEUE_MAX) {
          q.splice(0, q.length - QUEUE_MAX);
        }
        pref.putSync(KEY_QUEUE, JSON.stringify(q));
        pref.flush();
      } catch (_e2) {
        // 回滚失败（本地存储异常）静默
      }
    });
  } catch (_e) {
    // AGC 未初始化（应用极早期/初始化失败）静默
  }
}
