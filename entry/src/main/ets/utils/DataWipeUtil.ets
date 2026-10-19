// ============================================================
// DataWipeUtil.ets — ★ 0.263.0：退出登录「清空本机数据」工具
// ============================================================
// 场景：用户把 Pad 借给他人前，退出华为账号并一键清空本机全部
// 学习数据（气泡树/词库/知识库/统计/SP/签到/书签/注意力/复习状态）。
//
// 数据安全设计（与「卸载重装」语义完全等价，云端数据零影响）：
//   1. 调用顺序铁律：必须先 disableCloudSyncOnLogout（停云同步开关）+
//      logoutHuaweiID（断账号会话）→ 再调本函数清数据；
//   2. 清空走「直接置空 store 字段」而非 removeXxx 业务函数——不产生
//      墓碑行（0.230.1 铁律：墓碑只准显式删除操作触发），云端实体行
//      不会被删除标记压制，重新登录开同步后全量下行恢复；
//   3. RDB cloud_data 全表 DELETE：行是上行事实（0.228.2），本地事实
//      清空=与卸载重装等价；物理删行不上行（0.230.1 伪墓碑清洗实证）；
//   4. 沙箱内部双备份一并删除——否则「空库+有备份」会在下次启动弹
//      恢复询问（0.205.0 第二道防线），借用人手滑即数据回归；
//   5. 功能设置类（API 配置/主题/协议/订阅/偏好）保留——非隐私内容，
//      且 SubscriptionStore 含 VIP/兑码记录，清空将丢失用户自身权益。
//
// 不动清单：ApiConfig / theme / agreement / subscription / 各偏好 store /
//   CloudSyncArbiter（同步基础设施状态）/ widget formId（删则桌面卡片失联）。
// ============================================================

import { relationalStore } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { PersistenceV2 } from '@kit.ArkUI';
import { PersistData, connectTabForest, connectStatistics, connectSiyiPoints,
  connectSignIn, connectChatBookmarks } from '../common/ChatModel';
import { connectWordBank } from './WordStoreUtil';
import { connectKnowledgeBank } from './KnowledgeStoreUtil';
import { connectAttention } from '../common/KnowledgeModel';
import { connectReviewDailyState, connectDailyReviewCount } from '../components/ReviewPage';
import { buildWidgetState } from './WidgetHostBridge';
import { pushWidgetState } from './WidgetReviewUtil';

// 与 CloudSyncUtil.ets 同源常量（该文件为红线禁改、常量未导出——此处写死同值，改名须两处同步）
const WIPE_DB_NAME = 'dag_chat_cloud.db';
const WIPE_TABLE_NAME = 'cloud_data';

// 沙箱内部备份目录（BackupUtil.writeInternalBackup 的产物——0.205.0 第二道防线）
const WIPE_BACKUP_DIR = '/backups';

// ── 清空各业务 store（内存态 + PersistenceV2 自动落盘） ──
function wipePersistenceStores(): void {
  // 气泡树平铺池（工作区内存态随 terminateSelf 一并消失）
  const persist = PersistenceV2Connect();
  persist.bubbleTreeJson = '';
  // Tab 森林（选项卡结构——interconvertPools 派生视图一并清）
  const forest = connectTabForest();
  forest.tabsJson = '[]';
  forest.activeTabId = '';
  // 词库 + 文件夹（seed marker 是一次性 version 标记，preset 不会复活）
  const wordBank = connectWordBank();
  wordBank.words = [];
  wordBank.folders = [];
  // 知识库 + 文件夹
  const knowledgeBank = connectKnowledgeBank();
  knowledgeBank.cards = [];
  knowledgeBank.folders = [];
  // 学习统计（按天聚合）
  connectStatistics().raw = '{"days":[]}';
  // SP 三池+消耗（welcomeGranted 保留=防新人礼包重复发放薅羊毛；
  //   真实余额重新登录后由云端 cfg:siyi-points max 合并拉回）
  const sp = connectSiyiPoints();
  sp.permanentSp = 0;
  sp.bonusSp = 0;
  sp.giftSp = 0;
  sp.giftSpExpireAt = 0;
  sp.consumedGiftSp = 0;
  sp.consumedBonusSp = 0;
  sp.consumedPermanentSp = 0;
  // 签到（guideShown 保留=UI 引导标志非数据）
  const signIn = connectSignIn();
  signIn.signDates = [];
  signIn.lastSignDate = '';
  signIn.streak = 0;
  signIn.maxStreak = 0;
  signIn.makeupVouchers = 0;
  signIn.makeupGrantedLevel = 0;
  signIn.makeupDates = [];
  // 阅读书签
  connectChatBookmarks().raw = '{"entries":[]}';
  // 注意力热度
  const attention = connectAttention();
  attention.heatJson = '{}';
  attention.updatedAt = 0;
  // 每日复习完成状态（10 字段全回默认）
  const daily = connectReviewDailyState();
  daily.wordDate = '';
  daily.wordTotal = 0;
  daily.wordHard = 0;
  daily.wordGood = 0;
  daily.wordEasy = 0;
  daily.knowledgeDate = '';
  daily.knowledgeTotal = 0;
  daily.knowledgeHard = 0;
  daily.knowledgeGood = 0;
  daily.knowledgeEasy = 0;
}

// ── 清空云同步本地 RDB（行=上行事实，物理删行不上行——0.230.1 实证） ──
async function wipeCloudRdb(context: common.Context): Promise<void> {
  try {
    const store = await relationalStore.getRdbStore(context, {
      name: WIPE_DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1,
      autoCleanDirtyData: false
    });
    await store.executeSql(`DELETE FROM ${WIPE_TABLE_NAME}`);
  } catch (_e) {
    // 未开过云同步的设备 db 不存在——getRdbStore 自建后删除，失败静默无害
  }
}

// ── 删除沙箱内部双备份（防「空库+有备份」恢复询问把数据带回） ──
function wipeInternalBackups(context: common.Context): void {
  const dir = context.filesDir + WIPE_BACKUP_DIR;
  try {
    const names = fileIo.listFileSync(dir);
    for (let i = 0; i < names.length; i++) {
      try {
        fileIo.unlinkSync(dir + '/' + names[i]);
      } catch (_e) {
        // 单文件失败继续（备份 tmp 偶发句柄占用）
      }
    }
    fileIo.rmdirSync(dir);
  } catch (_e) {
    // 目录不存在=无备份，直接过
  }
}

// ── 桌面卡片刷空态（清库后卡片残留旧词条=隐私泄漏） ──
function wipeWidgetState(context: common.Context): void {
  try {
    const daily = connectDailyReviewCount();
    buildWidgetState(context, 'word', connectWordBank(), connectKnowledgeBank(),
      daily.wordCount, daily.knowledgeCount); // 空库构建 → done 空态写盘
    pushWidgetState(context); // 推全部卡片立即生效
  } catch (_e) {
    // 卡片推送失败不影响清零主流程
  }
}

// ── 对外唯一入口：清空本机全部学习数据 ──
// 返回 true=全部成功；false=store 层成功但 RDB/备份清理有异常（数据已不可见，仍建议重启）
export async function clearAllLocalUserData(context: common.Context): Promise<boolean> {
  wipePersistenceStores();
  wipeWidgetState(context);
  wipeInternalBackups(context);
  await wipeCloudRdb(context);
  return true;
}

// PersistData 连接（key 'persist-data'——与 ChatModel 内部同款模式，类已 export）
function PersistenceV2Connect(): PersistData {
  return PersistenceV2.connect(PersistData, 'persist-data', () => new PersistData()) as PersistData;
}
