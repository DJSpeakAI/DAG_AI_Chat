// ============================================================
// RookieTask.ets — ★ 0.294.0：好奇宝宝新手任务体系（数据层+状态机）
// ============================================================
// 用户拍板（2026-10-22 三轮）：引导新用户逐步体验七大核心功能，每完成一条发 SP 奖励；
//   名字呼应 Lv1 头衔「好奇宝宝」（等级体系不挂钩）。
// 任务制：不按顺序、做完哪条打勾哪条；7 条全完+奖励结清 → 画布右上角入口整体消失。
// 奖励（乙档递进）：探索类 1 万×3 + 核心类 2 万×3 + 性格测试 1 万 + 完赛奖 2 万
//   （性格测试另有每 5 题 5000×3 节点奖励走 PersonalityQuiz 既有链路，二者叠加）。
// SP 云服务铁律（project_rule §SP）：发放走 grantBonusSp 收口（内含 0.293.0 SiyiGate 守卫）——
//   未开通云服务=任务照常打勾记信号（挂账），开通后 settleRookieTasks 自动对账差集补发；
//   done/granted 两集合随 cfg:siyi-points 云行并集合并多端收敛、永不重复发。
// 检测挂点（7 处既有链路零新业务）：addBubble（ChatPage）/司枢发送（ChatPage）/
//   圈注回传（ChatPage）/划词翻译 onDone（ChatPage）/划词入库保存（ChatPage）/
//   首次评分（ReviewPage+ChatPage 司忆区）/性格测试答完（PersonalityQuiz.writeQuizProfile）。
// ============================================================

import { AppStorageV2 } from '@kit.ArkUI';
import { SiyiPointStore, connectSiyiPoints, grantBonusSp } from './ChatModel';
import { siyiGateReady } from '../utils/SiyiGate';
import { trackAuto } from '../utils/TrackUtil';

// ── 任务定义（常量表驱动：后续加任务=尾部追加行，架构不动）──
export class RookieTaskDef {
  id: string = '';
  name: string = '';
  desc: string = '';
  sp: number = 0;
  constructor(id: string, name: string, desc: string, sp: number) {
    this.id = id;
    this.name = name;
    this.desc = desc;
    this.sp = sp;
  }
}

export const ROOKIE_TASKS: RookieTaskDef[] = [
  new RookieTaskDef('new_bubble', '新建一个气泡', '种下你的第一颗想法', 10000),
  new RookieTaskDef('word_translate', '划词翻译一次', '长按文字即可翻译', 10000),
  new RookieTaskDef('word_to_knowledge', '划词入知识库', '随手收藏成知识卡片', 10000),
  new RookieTaskDef('use_sishu', '使用一次司枢模式', '让 AI 深度思考给你看', 20000),
  new RookieTaskDef('screen_annotate', '屏幕圈注一次', '圈住屏幕上任何疑问', 20000),
  new RookieTaskDef('first_review', '完成第一次复习', '知识卡或单词都算', 20000),
  new RookieTaskDef('personality_quiz', '完成性格测试', '15 题，让 AI 更懂你', 10000)
];

export const ROOKIE_BONUS_SP: number = 20000;  // 完赛奖（7 条全亮一次性）
const ROOKIE_BONUS_ID = '__bonus__';            // 完赛奖在 granted 集合中的哨兵 id

// ── 弹窗桥（AppStorageV2 应用级共享；挂载点唯一=BBTreeCanvas——SignInDialogBridge 同款纪律）──
@ObservedV2
export class RookieTaskBridge {
  @Trace panelVisible: boolean = false;   // 任务面板
  @Trace rewardVisible: boolean = false;  // 单任务/汇总奖励弹窗
  @Trace rewardTitle: string = '';        // 弹窗标题（任务名 / 「新手任务奖励已到账」）
  @Trace rewardAmount: number = 0;        // 本次到账 SP
  @Trace rewardDone: number = 0;          // 完成进度 x（汇总弹窗用，单任务弹窗=7 之一忽略）
}

export function connectRookieBridge(): RookieTaskBridge {
  return AppStorageV2.connect(RookieTaskBridge, 'rookie-task-bridge',
    () => new RookieTaskBridge()) as RookieTaskBridge;
}

// ── 集合工具（done/granted 均存 siyi-points 两 JSON 字段——云行并集即唯一真相源，无独立本地 key）──
export function rookieDoneIds(siyi: SiyiPointStore): string[] {
  try {
    const arr = JSON.parse(siyi.rookieDoneJson) as string[];
    return Array.isArray(arr) ? arr : [];
  } catch (_e) {
    return [];
  }
}

export function rookieGrantedIds(siyi: SiyiPointStore): string[] {
  try {
    const arr = JSON.parse(siyi.rookieGrantedJson) as string[];
    return Array.isArray(arr) ? arr : [];
  } catch (_e) {
    return [];
  }
}

function writeDoneIds(siyi: SiyiPointStore, ids: string[]): void {
  siyi.rookieDoneJson = JSON.stringify(ids); // PersistenceV2 即时落盘；云上行由 grantBonusSp/结算的 scheduleRowFlush 带
}

function writeGrantedIds(siyi: SiyiPointStore, ids: string[]): void {
  siyi.rookieGrantedJson = JSON.stringify(ids);
}

function pushUnique(ids: string[], id: string): boolean {
  if (ids.indexOf(id) >= 0) {
    return false;
  }
  ids.push(id);
  return true;
}

// ── 状态查询（面板/角标消费）──
export function rookieDoneCount(siyi: SiyiPointStore): number {
  const done = rookieDoneIds(siyi);
  let n = 0;
  for (let i = 0; i < ROOKIE_TASKS.length; i++) {
    if (done.indexOf(ROOKIE_TASKS[i].id) >= 0) {
      n++;
    }
  }
  return n;
}

export function rookieUndoneCount(siyi: SiyiPointStore): number {
  return ROOKIE_TASKS.length - rookieDoneCount(siyi);
}

export function rookieTaskDone(siyi: SiyiPointStore, id: string): boolean {
  return rookieDoneIds(siyi).indexOf(id) >= 0;
}

export function rookieTaskGranted(siyi: SiyiPointStore, id: string): boolean {
  return rookieGrantedIds(siyi).indexOf(id) >= 0;
}

/** 入口整体消失条件：7 条全 done 且全部奖励（含完赛奖哨兵）已发放结清 */
export function rookieAllSettled(siyi: SiyiPointStore): boolean {
  return rookieDoneCount(siyi) >= ROOKIE_TASKS.length
    && rookieGrantedIds(siyi).indexOf(ROOKIE_BONUS_ID) >= 0;
}

// ── 发放（gate ready 前提下；幂等=granted 集合）──
function grantOne(siyi: SiyiPointStore, id: string, amount: number): boolean {
  const granted = rookieGrantedIds(siyi);
  if (granted.indexOf(id) >= 0) {
    return false; // 已发过（幂等）
  }
  if (!grantBonusSp(siyi, amount, `rookie_${id === ROOKIE_BONUS_ID ? 'bonus' : id}`)) {
    return false; // gate 未就绪——保留挂账，结算时机再试
  }
  granted.push(id);
  writeGrantedIds(siyi, granted);
  return true;
}

/**
 * 完成信号入口（7 处业务挂点调用；幂等；未开云服务也照记——「后台给一个信号就自动解锁这一条」）。
 * gate 就绪：即时发放+弹「+N SP」奖励窗；gate 未就绪：静默打勾挂账（结算时机补发）。
 */
export function completeRookieTask(id: string): void {
  const siyi = connectSiyiPoints();
  const done = rookieDoneIds(siyi);
  if (!pushUnique(done, id)) {
    return; // 已完成过（幂等）
  }
  writeDoneIds(siyi, done);
  const p: Record<string, string> = {};
  p['task'] = id;
  trackAuto('rookie_task_done', p);
  if (!siyiGateReady()) {
    return; // 挂账：云服务开通后 settleRookieTasks 自动补发
  }
  settleRookieTasks(); // 即时路径（内部含本条发放+完赛判定）
}

/**
 * 结算（挂账补发+完赛奖）：gate ready 才动作；三时机调用——app 启动/回前台/任务面板打开。
 * 返回本次补发总额（0=无差集）；有补发时调用方弹汇总窗（bridge.rewardVisible）。
 */
export function settleRookieTasks(): number {
  const siyi = connectSiyiPoints();
  if (!siyiGateReady()) {
    return 0;
  }
  const done = rookieDoneIds(siyi);
  const granted = rookieGrantedIds(siyi);
  let total = 0;
  let grantedAny = false;
  for (let i = 0; i < ROOKIE_TASKS.length; i++) {
    const t = ROOKIE_TASKS[i];
    if (done.indexOf(t.id) >= 0 && granted.indexOf(t.id) < 0) {
      if (grantOne(siyi, t.id, t.sp)) {
        total += t.sp;
        grantedAny = true;
      }
    }
  }
  // 完赛奖：7 条全 done 且哨兵未发 → 一笔发
  if (rookieDoneCount(siyi) >= ROOKIE_TASKS.length
    && rookieGrantedIds(siyi).indexOf(ROOKIE_BONUS_ID) < 0) {
    if (grantOne(siyi, ROOKIE_BONUS_ID, ROOKIE_BONUS_SP)) {
      total += ROOKIE_BONUS_SP;
      grantedAny = true;
    }
  }
  if (grantedAny) {
    const bridge = connectRookieBridge();
    bridge.rewardTitle = total >= ROOKIE_BONUS_SP
      ? '恭喜！新手任务全部完成' : '新手任务奖励已到账';
    bridge.rewardAmount = total;
    bridge.rewardVisible = true;
  }
  return total;
}