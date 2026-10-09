// ============================================================
// WidgetReviewUtil.ets — ★ 0.204.0 桌面卡片数据引擎（卡片上直接复习）
// ============================================================
// 架构（0.204.0 用户拍板：去掉跳 APP，卡片自闭环复习）：
//   快照升级为「双队列状态」——卡片进程可独立跑评分（applyRating 纯函数复用），
//   评分结果记 pending，主应用下次进复习页时回放合并到 PersistenceV2 真数据。
//
// 数据流：
//   主应用 WidgetHostBridge.buildWidgetState → 写 preferences（word+knowledge 双队列）
//   卡片 EntryFormAbility.onFormEvent(message) → processWidgetCommand：
//     rate   → applyRating（快照内记忆字段）→ idx 前进 → pending 追加 → updateForm
//     switch → 切 word/knowledge 队列 → updateForm
//   主应用 ReviewPage.aboutToAppear → mergeWidgetPending 回放 → 重建快照
//
// 本文件被卡片进程 import——禁止 connect 任何 PersistenceV2 store（防跨进程写冲突）；
//   只 import 纯类定义（WordItem/KnowledgeCard）与纯函数（applyRating）。
// ============================================================

import { preferences } from '@kit.ArkData';
import { formProvider, formBindingData, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

// ★ 0.204.0 bugfix（bug3 根因）：本文件曾被卡片进程 import 了 WordItem/KnowledgeCard/
//   MemoryAlgorithm——@ObservedV2 装饰器类在 FormExtensionAbility 进程（无 ArkUI 运行时）
//   加载即崩 → onFormEvent 根本不执行 → 按钮点了没反应。
//   修复：评分逻辑改「纯字段版」widgetApplyRating（逻辑与 MemoryAlgorithm.applyRating
//   逐行一致——首评绝对间隔/复评系数/钳制/0.202.0 两层提前背惩罚），零装饰器零类依赖。
//   主应用真数据侧仍走原 applyRating（WidgetHostBridge）——两处同步改。

const PREF_NAME = 'widget_review';
const KEY_STATE = 'state';          // WidgetState JSON（双队列+进度）
const KEY_PENDING = 'pending';      // 卡片上产生的评分（主应用回放后清空）
const KEY_LAST_RATE = 'last_rate';  // 防连点时间戳
// ★ 0.204.4：KEY_FORM_IDS/KEY_DIMENSION 已挪 filesDir JSON 文件（preferences 跨进程缓存不可见——见 meta 区注释）

/** 卡片单卡（含记忆字段——卡片进程可直接跑 applyRating） */
export interface WidgetCardItem {
  id: string;
  title: string;
  definition: string;
  strength: number;
  reviewCount: number;
  lastReviewAt: number;
  nextReviewAt: number;
}

/** 一条复习队列（进度+三档计数） */
export interface WidgetQueue {
  items: WidgetCardItem[];
  idx: number;      // 当前第几张（0 基）
  done: boolean;    // 本队完成？
  hard: number;
  good: number;
  easy: number;
}

/** 全局状态：双队列 + 当前展示模式 */
export interface WidgetState {
  mode: string;     // 'word' | 'knowledge'
  word: WidgetQueue;
  knowledge: WidgetQueue;
  noMore?: string;  // 0.204.2：'y'=全部学完（含未来）——完成态隐藏继续按钮显示「全部学完」文案；主应用重建快照时重置
}

/** 待回放评分（卡片上产生；主应用按 happenedAt 顺序 applyRating 到真数据） */
export interface WidgetPendingRating {
  id: string;
  mode: string;
  rating: string; // 'hard' | 'good' | 'easy'
  happenedAt: number;
}

// ---- 纯字段版评分算法（与 MemoryAlgorithm.applyRating 逐行同步；常量同源复制）----

const W_DAY_MS = 24 * 60 * 60 * 1000;
const W_S_MIN_DAYS = 10 / (24 * 60); // S 下限 10 分钟
const W_S_MAX_DAYS = 365;            // S 上限一年
const W_FIRST_HARD = 10 / (24 * 60); // 首评：生疏 10 分钟 / 尚可 12 小时 / 熟知 2 天
const W_FIRST_GOOD = 0.5;
const W_FIRST_EASY = 2;
const W_MULT_HARD = 0.5;             // 复评系数：×0.5 / ×1.6 / ×2.4
const W_MULT_GOOD = 1.6;
const W_MULT_EASY = 2.4;
const W_EARLY_GROWTH_FLOOR = 0.15;   // 0.202.0 层1：增长打折下限 15%
const W_EARLY_MIN_PUSH_DAYS = 1;     // 0.202.0 层2：提前背排期保底 原排期+1 天

/** 纯字段版评分（卡片进程安全——直接改 WidgetCardItem，零类依赖） */
function widgetApplyRating(it: WidgetCardItem, rating: string, now: number): void {
  if (it.strength <= 0) {
    it.strength = rating === 'hard' ? W_FIRST_HARD : (rating === 'good' ? W_FIRST_GOOD : W_FIRST_EASY);
  } else {
    const mult = rating === 'hard' ? W_MULT_HARD : (rating === 'good' ? W_MULT_GOOD : W_MULT_EASY);
    if (rating === 'hard') {
      it.strength = Math.min(Math.max(it.strength * mult, W_S_MIN_DAYS), W_S_MAX_DAYS);
    } else {
      // 层1：增长打折——记忆经过多少比例的考验，强度就涨多少
      const elapsedDays = (now - it.lastReviewAt) / W_DAY_MS;
      const factor = Math.min(Math.max(elapsedDays / it.strength, W_EARLY_GROWTH_FLOOR), 1);
      it.strength = Math.min(Math.max(it.strength * (1 + (mult - 1) * factor), W_S_MIN_DAYS), W_S_MAX_DAYS);
    }
  }
  it.lastReviewAt = now;
  let next = now + it.strength * W_DAY_MS;
  // 层2：提前背的排期散开保底（仅 now < 原排期时生效——到期背零影响）
  if (rating !== 'hard' && now < it.nextReviewAt &&
    next < it.nextReviewAt + W_EARLY_MIN_PUSH_DAYS * W_DAY_MS) {
    next = it.nextReviewAt + W_EARLY_MIN_PUSH_DAYS * W_DAY_MS;
  }
  it.nextReviewAt = next;
}

// ---------------- preferences 基础读写 ----------------

function getPref(context: Context): preferences.Preferences {
  return preferences.getPreferencesSync(context, { name: PREF_NAME });
}

export function emptyWidgetQueue(): WidgetQueue {
  return { items: [], idx: 0, done: true, hard: 0, good: 0, easy: 0 };
}

export function readWidgetState(context: Context): WidgetState {
  try {
    const raw = getPref(context).getSync(KEY_STATE, '') as string;
    if (raw.length > 0) {
      return JSON.parse(raw) as WidgetState;
    }
  } catch (_e) {
    // 损坏按空处理
  }
  return { mode: 'knowledge', word: emptyWidgetQueue(), knowledge: emptyWidgetQueue() };
}

function writeWidgetState(context: Context, s: WidgetState): void {
  try {
    const pref = getPref(context);
    pref.putSync(KEY_STATE, JSON.stringify(s));
    pref.flush();
  } catch (_e) {
    // 静默
  }
}

/** 主应用侧写快照 + 推送全部卡片（HostBridge 构建后调用） */
export function writeWidgetStateForHost(context: Context, s: WidgetState): void {
  writeWidgetState(context, s);
  pushWidgetState(context);
}

function readPending(context: Context): WidgetPendingRating[] {
  try {
    const raw = getPref(context).getSync(KEY_PENDING, '[]') as string;
    return JSON.parse(raw) as WidgetPendingRating[];
  } catch (_e) {
    return [];
  }
}

/** 主应用读 pending（HostBridge 回放用） */
export function readWidgetPending(context: Context): WidgetPendingRating[] {
  return readPending(context);
}

/** 回放完成清空 pending */
export function clearWidgetPending(context: Context): void {
  try {
    const pref = getPref(context);
    pref.putSync(KEY_PENDING, '[]');
    pref.flush();
  } catch (_e) {
    // 静默
  }
}

// ---------------- formId / dimension 管理（★ 0.204.4：改文件直存） ----------------
// ★ 0.204.4 多卡片 bug 根因：preferences 有进程内存缓存——卡片进程 onAddForm 写盘的新 formId，
//   主进程（已启动）的 preferences 缓存看不到 → updateForm 只推旧卡片（用户实测：点新卡旧卡动）。
//   修复：formId/dimension 挪到 filesDir 纯 JSON 文件（fs 直读直写，无缓存，跨进程永远最新）。
//   写者=卡片进程（onAddForm/onSizeChanged 等回调）+ 主进程 ensureWidgetFormIds；读者=两进程推送时。
//   preferences 只留 state/pending（主进程单写者 + 卡片进程冷读，无并发问题）。

interface WidgetMeta {
  formIds: string[];
  dimension: number; // 1=1×2 2=2×2 3=2×4 4=4×4
}

function metaPath(context: Context): string {
  return context.filesDir + '/widget_meta.json';
}

function readWidgetMeta(context: Context): WidgetMeta {
  try {
    const f = fileIo.openSync(metaPath(context), fileIo.OpenMode.READ_ONLY);
    const buf = new ArrayBuffer(8192);
    const len = fileIo.readSync(f.fd, buf);
    fileIo.closeSync(f);
    const decoder = util.TextDecoder.create('utf-8');
    const raw = decoder.decodeToString(new Uint8Array(buf.slice(0, len))).trim();
    const m = JSON.parse(raw) as WidgetMeta;
    if (m !== null && m !== undefined && Array.isArray(m.formIds)) {
      return m;
    }
  } catch (_e) {
    // 文件不存在/损坏按默认
  }
  return { formIds: [], dimension: 3 };
}

function writeWidgetMeta(context: Context, meta: WidgetMeta): void {
  try {
    const f = fileIo.openSync(metaPath(context), fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
    fileIo.writeSync(f.fd, JSON.stringify(meta));
    fileIo.closeSync(f);
  } catch (_e) {
    // 写失败静默
  }
}

/** 记录新添加卡片（onAddForm） */
export function addWidgetFormId(context: Context, formId: string): void {
  const meta = readWidgetMeta(context);
  if (!meta.formIds.includes(formId)) {
    meta.formIds.push(formId);
    writeWidgetMeta(context, meta);
  }
}

/** 卡片删除（onRemoveForm） */
export function removeWidgetFormId(context: Context, formId: string): void {
  const meta = readWidgetMeta(context);
  const next = meta.formIds.filter((x: string): boolean => x !== formId);
  if (next.length !== meta.formIds.length) {
    meta.formIds = next;
    writeWidgetMeta(context, meta);
  }
}

/**
 * ★ 0.204.3：formId 自愈——卸载重装后 preferences 全清（form_ids 空列表），桌面残留卡片
 * 收不到任何推送（用户实测「点了没反应」根因）。getPublishedFormInfos 查询本应用已发布
 * 卡片 → 回写 form_ids → 补推一次快照。call 三入口与主应用启动构建后都调（幂等：非空直接返回）。
 */
export function ensureWidgetFormIds(context: Context): void {
  const meta = readWidgetMeta(context);
  if (meta.formIds.length > 0) {
    return; // 已有记录，无需自愈
  }
  formProvider.getPublishedRunningFormInfos().then((infos: formInfo.RunningFormInfo[]) => {
    const healed: string[] = [];
    infos.forEach((f: formInfo.RunningFormInfo) => {
      if (f.bundleName === 'com.example.dag_ai_chat' && !healed.includes(f.formId)) {
        healed.push(f.formId);
      }
    });
    if (healed.length === 0) {
      return;
    }
    const m = readWidgetMeta(context); // 重读防并发覆盖
    healed.forEach((id: string) => {
      if (!m.formIds.includes(id)) {
        m.formIds.push(id);
      }
    });
    writeWidgetMeta(context, m);
    pushWidgetState(context); // 补推——残留卡片立即恢复显示
  }).catch((_e: BusinessError) => {
    // 查询失败静默（systemapi 受限场景，下次再试）
  });
}

/** 规格变化（onSizeChanged；1=1×2 2=2×2 3=2×4 4=4×4）→ 写盘 + 立即推送刷新排版 */
export function setWidgetDimension(context: Context, dimension: number): void {
  const meta = readWidgetMeta(context);
  meta.dimension = dimension;
  writeWidgetMeta(context, meta);
  pushWidgetState(context);
}

// ---------------- 推送（updateForm 全部已添加卡片） ----------------

/** 快照 → 卡片绑定数据（ArkTS 卡片只认平铺基础类型；dimension 驱动三规格排版分支） */
export function formBindingDataOf(context: Context): formBindingData.FormBindingData {
  const s = readWidgetState(context);
  const q = s.mode === 'word' ? s.word : s.knowledge;
  const dim = getDimension(context);
  const item = q.idx < q.items.length ? q.items[q.idx] : undefined;
  return formBindingData.createFormBindingData({
    mode: s.mode,
    title: item === undefined ? '' : item.title,
    definition: item === undefined ? '' : item.definition,
    progress: q.items.length > 0 ? `${q.idx + 1} / ${q.items.length}` : '',
    remain: q.items.length > 0 ? `${q.items.length - q.idx}` : '0',
    done: q.done || item === undefined ? 'y' : 'n',
    dimension: `${dim}`,
    hard: `${q.hard}`,
    good: `${q.good}`,
    easy: `${q.easy}`,
    noMore: s.noMore === 'y' ? 'y' : 'n'
  });
}

function getDimension(context: Context): number {
  const v = readWidgetMeta(context).dimension;
  if (v >= 1 && v <= 4) {
    return v;
  }
  return 3;
}

export function pushWidgetState(context: Context): void {
  try {
    const ids = readWidgetMeta(context).formIds; // 文件直读——主进程永远看到卡片进程新写的 id（0.204.4 多卡片修复核心）
    const binding = formBindingDataOf(context);
    ids.forEach((id: string) => {
      formProvider.updateForm(id, binding).catch((_e: BusinessError) => {
        // 过期 formId 忽略（卡片已被删除）
      });
    });
  } catch (_e) {
    // 静默
  }
}

// ---------------- 卡片侧命令处理（onFormEvent → 此处分发） ----------------

/**
 * 处理卡片交互命令（EntryFormAbility.onFormEvent 转发）。
 * message 为 postCardAction msg 的 JSON 串：
 *   {"cmd":"rate","rating":"good"}   —— 评分当前卡，快照内推进+记 pending
 *   {"cmd":"switch","mode":"word"}   — 切换单词/知识队列
 */
export function processWidgetCommand(context: Context, message: string): void {
  let cmd = '';
  let rating = 'good';
  let mode = '';
  try {
    const m = JSON.parse(message) as Record<string, string>;
    cmd = m['cmd'] ?? '';
    rating = m['rating'] ?? 'good';
    mode = m['mode'] ?? '';
  } catch (_e) {
    return; // 非法消息忽略
  }

  if (cmd === 'rate') {
    // 防连点：500ms 内重复评分忽略（updateForm 刷新有延迟，防双击跳卡）
    try {
      const pref = getPref(context);
      const last = pref.getSync(KEY_LAST_RATE, 0) as number;
      const now = Date.now();
      if (now - last < 500) {
        return;
      }
      pref.putSync(KEY_LAST_RATE, now);
      pref.flush();
    } catch (_e) {
      // 静默
    }
    handleRate(context, rating);
  } else if (cmd === 'switch' && (mode === 'word' || mode === 'knowledge')) {
    const s = readWidgetState(context);
    s.mode = mode;
    writeWidgetState(context, s);
    pushWidgetState(context);
  }
}

/**
 * 解析 call/message 双形态事件（备用入口——当前主链路为 call→EntryAbility Callee）。
 * call 形态：{'method':'widgetRate','params':{...}}（params 可能是 JSON 串）
 * message 形态：{'cmd':'rate','rating':...}（若 msg 通道恢复）
 */
export function processCallOrMessage(context: Context, message: string): void {
  try {
    const m = JSON.parse(message) as Record<string, string>;
    const method = m['method'] ?? '';
    const params = m['params'] ?? '';
    if (method === 'widgetRate') {
      const p = (typeof params === 'string' && params.length > 0 ? JSON.parse(params) : m) as Record<string, string>;
      processWidgetCommand(context, JSON.stringify({ cmd: 'rate', rating: p['rating'] ?? 'good' }));
    } else if (method === 'widgetSwitch') {
      const p = (typeof params === 'string' && params.length > 0 ? JSON.parse(params) : m) as Record<string, string>;
      processWidgetCommand(context, JSON.stringify({ cmd: 'switch', mode: p['mode'] ?? 'knowledge' }));
    } else {
      processWidgetCommand(context, message); // message 语义直落
    }
  } catch (_e) {
    processWidgetCommand(context, message);
  }
}

function handleRate(context: Context, rating: string): void {
  const s = readWidgetState(context);
  const q = s.mode === 'word' ? s.word : s.knowledge;
  if (q.done || q.idx >= q.items.length) {
    pushWidgetState(context); // 已完成态重推一次（刷新）
    return;
  }
  const it = q.items[q.idx];
  const now = Date.now();
  // 纯字段版评分（与主应用 applyRating 同算法——快照内直接推进记忆字段）
  widgetApplyRating(it, rating, now);
  if (rating === 'hard') {
    q.hard += 1;
  } else if (rating === 'good') {
    q.good += 1;
  } else {
    q.easy += 1;
  }
  q.idx += 1;
  if (q.idx >= q.items.length) {
    q.done = true;
  }
  writeWidgetState(context, s);

  // 记 pending（主应用下次进复习页时回放到 PersistenceV2 真数据）
  try {
    const pref = getPref(context);
    const pending = readPending(context);
    pending.push({ id: it.id, mode: s.mode, rating: rating, happenedAt: now });
    pref.putSync(KEY_PENDING, JSON.stringify(pending));
    pref.flush();
  } catch (_e) {
    // 静默（丢一条评分不致命——快照内进度仍在）
  }
  pushWidgetState(context);
}

// ---------------- 边栏入口：打开卡片管理器 ----------------

/** ★ 0.204.0：打开本应用卡片管理器（账户行入口；用户选规格后添加——2×2/2×4/4×4） */
export function requestPublishReviewWidget(): void {
  const want: Want = {
    bundleName: 'com.example.dag_ai_chat',
    abilityName: 'EntryFormAbility',
    parameters: {
      'ohos.extra.param.key.form_dimension': 3, // Dimension_2_4（默认定位主力规格）
      'ohos.extra.param.key.form_name': 'ReviewWidget',
      'ohos.extra.param.key.module_name': 'entry'
    }
  };
  try {
    formProvider.openFormManager(want);
  } catch (_e) {
    // IPC 异常静默（用户可改走长按图标→服务卡片）
  }
}
