// ============================================================
// CloudSyncUtil.ets — 端云数据同步工具（★ 0.165 云同步）
// ============================================================
// 技术路线：ArkData 端云数据同步（RDB + cloudSync，数据存华为云空间）
//   - 本地 RDB 库 dag_chat_cloud.db（★ AGC 容器名必须 = dag_chat_cloud，无后缀）
//   - 表 cloud_data（★ AGC 新界面双字段映射：数据类型名称 cloudData 驼峰——该输入框不允许
//     下划线；「高级设置→本地表名称」填 cloud_data 承接映射，端侧表名不变）：
//       key TEXT 主键 / value TEXT / updated_at INTEGER
//   - setDistributedTables(DISTRIBUTED_CLOUD, autoSync: true)：本地变更自动上云
// 快照行模式（docs/0.165.md 方案）：
//   - flat_pool ← PersistData.bubbleTreeJson（平铺池全部树）
//   - tabs_pool ← TabForestStore.tabsJson（Tab 池全部 Tab 元数据+树）
// 官方约束（端云同步文档实证）：
//   - 主键须唯一禁自增；表列只能新增不能修改删除；字段禁 NOT NULL
//   - 云侧须在 AGC 配置：容器 dag_chat_cloud + 数据类型 cloudData（本地表名称 cloud_data）
//     + 字段一一对应 + 主键勾「端侧去重主键」（实测新界面，详见 docs/0.165.md 第三章）
//   - debug 证书连开发环境 / release 证书连生产环境（当前 debug 签名 → 开发环境调测）
//   - 云侧未配置时：本地写入正常，上云失败仅打日志（不崩溃不阻塞持久化路径）
// ============================================================

import { relationalStore } from '@kit.ArkData';
import { abilityAccessCtrl, bundleManager, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PersistenceV2, UIContext } from '@kit.ArkUI'; // ★ 0.196.8：应用级开关持久化 + 登录后弹窗（UIContext）

const DB_NAME = 'dag_chat_cloud.db'; // 库名（AGC 容器名 = dag_chat_cloud）
const TABLE_NAME = 'cloud_data';     // 表名 = 云侧「本地表名称」字段值（数据类型名为驼峰 cloudData）
const TAG = 'CloudSyncUtil';
const DOMAIN = 0x0165;

// 模块级 RDB 实例 + 初始化 Promise（EntryAbility 启动时 init 一次，全应用共享）
let rdbStore: relationalStore.RdbStore | null = null;
let initPromise: Promise<boolean> | null = null;
let cloudSyncActive: boolean = false; // ★ 0.165.1：云同步是否已激活（权限授予 + setDistributedTables 成功）
let downlinkCallback: ((storeUri: Array<string>) => void) | null = null; // ★ 0.196.8：下行订阅回调引用（deactivateCloudSync off 用）

// ★ 0.196.8：云同步应用级开关——与华为账号登录态绑定（用户拍板：两状态同时开/同时关）
//   背景：系统权限 DISTRIBUTED_DATASYNC 授予后应用无法主动撤销，退出华为账号后权限仍在
//   （UI 显示「已开启」）但云侧已无账号会话实际同步不了——故加应用层开关作为「用户意图」
//   真相源：激活条件 = 权限授予 && 开关开；退出账号 → 开关强制关（UI 显示未开启，与账号一致）
@ObservedV2
export class CloudSyncStore {
  @Trace enabled: boolean = false; // 登录弹窗「开启」/设置页按钮 → true；退出账号 → false
}

// 连接持久化单例（key 'cloud-sync-switch'，与 PersistData/api-config 同款模式）
export function connectCloudSync(): CloudSyncStore {
  return PersistenceV2.connect(CloudSyncStore, 'cloud-sync-switch',
    () => new CloudSyncStore()) as CloudSyncStore;
}

// ★ 0.165.2：云端下行处理器（回调注入——ChatModel 已 import 本文件，本文件反向
// import ChatModel 会循环依赖，故业务写回逻辑由 ChatModel 侧注册进来）
type CloudDataHandler = (key: string, value: string) => void;
let downlinkHandler: CloudDataHandler | null = null;

// ★ 0.165.1：初始化云同步 RDB（EntryAbility.onWindowStageCreate 调用，幂等）
// 建库 → 建表 → 设置端云同步表（autoSync 开启后本地变更自动上云，无需手动 cloudSync）
export function initCloudDb(context: common.UIAbilityContext): void {
  if (initPromise !== null) {
    return; // 已初始化（或初始化进行中），幂等
  }
  initPromise = (async (): Promise<boolean> => {
    try {
      const store = await relationalStore.getRdbStore(context, {
        name: DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1, // S1 即可上云（S4 不能同步）
        autoCleanDirtyData: false // 保留脏数据供 cursor 增量查询（0.165.2 下行合并用）
      });
      // 建表：主键唯一禁自增（端云同步硬约束）；字段一律不设 NOT NULL（云端字段默认允许为空）
      await store.executeSql(`CREATE TABLE IF NOT EXISTS ${TABLE_NAME} (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at INTEGER
      )`);
      rdbStore = store;
      hilog.info(DOMAIN, TAG, 'cloud db init ok');
      // ★ 0.165.1：DISTRIBUTED_DATASYNC（normal + user_grant）须用户弹窗授权后才能开云同步；
      // 未授权时本地 RDB 正常读写（upsertCloudData 照常落库），云同步待命——授权后 activateCloudSync 激活
      const granted = await hasSyncPermission();
      // ★ 0.196.8：应用级开关也须开——退出账号时开关已强制关，权限仍在也不激活（UI/行为与账号一致）
      if (granted && connectCloudSync().enabled) {
        activateCloudSync();
      } else {
        hilog.info(DOMAIN, TAG, 'sync permission not granted yet, cloud sync standby');
      }
      return true;
    } catch (err) {
      // 初始化失败（如系统 RDB 异常）：云同步整体静默降级，本地 PersistenceV2 路径不受影响
      hilog.error(DOMAIN, TAG, `cloud db init failed: ${JSON.stringify(err)}`);
      return false;
    }
  })();
}

// ★ 0.165.1：激活端云同步（权限已授予时调用；幂等）——设置分布式表 + autoSync，
// 此后本表任何写入由框架自动推云（云侧 AGC 配置就绪后生效）
function activateCloudSync(): void {
  if (rdbStore === null || cloudSyncActive) {
    return;
  }
  try {
    rdbStore.setDistributedTables([TABLE_NAME], relationalStore.DistributedType.DISTRIBUTED_CLOUD,
      { autoSync: true });
    cloudSyncActive = true;
    subscribeCloudDownlink(); // ★ 0.165.2：激活即订阅云端下行（无论启动时已有权限还是用户刚授权，都挂上）
    hilog.info(DOMAIN, TAG, 'cloud sync activated (autoSync on)');
  } catch (err) {
    hilog.warn(DOMAIN, TAG, `activate cloud sync failed: ${JSON.stringify(err)}`);
  }
}

// ★ 0.196.8：停用端云同步（退出华为账号时调用；幂等）——退订下行 + 清激活标记。
//   系统权限无法由应用撤销（留在系统层无妨：下次登录开关重开即秒激活，无需再弹权限窗）
function deactivateCloudSync(): void {
  if (!cloudSyncActive) {
    return;
  }
  cloudSyncActive = false;
  if (rdbStore !== null && downlinkCallback !== null) {
    try {
      rdbStore.off('dataChange', relationalStore.SubscribeType.SUBSCRIBE_TYPE_CLOUD, downlinkCallback);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `off dataChange failed: ${JSON.stringify(err)}`);
    }
  }
  hilog.info(DOMAIN, TAG, 'cloud sync deactivated (logout)');
}

// ★ 0.196.8：设置应用级开关（登录弹窗「开启」/设置页按钮/退出账号三条路径统一走这里）
//   开=true：权限已授予则立即激活；未授予则待 requestSyncPermission 授权后激活
//   开=false：立即停用（退出账号路径）
export function setCloudSyncEnabled(enabled: boolean): void {
  connectCloudSync().enabled = enabled;
  if (enabled) {
    hasSyncPermission().then((granted: boolean) => {
      if (granted && connectCloudSync().enabled) {
        activateCloudSync();
      }
    });
  } else {
    deactivateCloudSync();
  }
}

// ★ 0.165.1：查询分布式数据同步权限是否已授予（checkAccessToken）
async function hasSyncPermission(): Promise<boolean> {
  try {
    const bundleInfo = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    const atm = abilityAccessCtrl.createAtManager();
    const result = await atm.checkAccessToken(bundleInfo.appInfo.accessTokenId,
      'ohos.permission.DISTRIBUTED_DATASYNC');
    return result === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, `check permission failed: ${JSON.stringify(err)}`);
    return false;
  }
}

// ★ 0.165.1：向用户弹窗申请分布式数据同步权限（user_grant 权限须运行时弹窗）——
// 授权成功立即激活云同步。★ 0.165.2：返回授权结果（设置页「云同步」Tab 按钮据此刷新状态）；
// 用户拒绝后可再次调用重试
export async function requestSyncPermission(context: common.UIAbilityContext): Promise<boolean> {
  try {
    const atm = abilityAccessCtrl.createAtManager();
    // ★ 0.165.1：不写显式返回类型名（新 SDK 已移除 PermissionRequestResult 导出），靠类型推断
    const result = await atm.requestPermissionsFromUser(context,
      ['ohos.permission.DISTRIBUTED_DATASYNC']);
    if (result.authResults.length > 0 &&
      result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      hilog.info(DOMAIN, TAG, 'sync permission granted by user');
      connectCloudSync().enabled = true; // ★ 0.196.8：授权即用户意图开——开关落 true（激活由下方 activate）
      activateCloudSync();
      return true;
    }
    hilog.info(DOMAIN, TAG, 'sync permission denied by user');
    return false;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, `request permission failed: ${JSON.stringify(err)}`);
    return false;
  }
}

// 内部：等待初始化完成（EntryAbility 先跑，此处仅为调用早于 init 的兜底）
function ensureReady(): Promise<boolean> {
  if (initPromise === null) {
    return Promise.resolve(false);
  }
  return initPromise;
}

// ★ 0.165.1：写入/更新一行快照（fire-and-forget：失败仅日志，绝不阻塞本地持久化路径）
// ON_CONFLICT_REPLACE = INSERT OR REPLACE 语义：主键冲突删旧插新（表无外键引用，无副作用）
export function upsertCloudData(key: string, value: string): void {
  ensureReady().then((ok: boolean) => {
    if (!ok || rdbStore === null) {
      return;
    }
    const bucket: relationalStore.ValuesBucket = {
      'key': key,
      'value': value,
      'updated_at': Date.now()
    };
    rdbStore.insert(TABLE_NAME, bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE)
      .catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, `upsert ${key} failed: code=${err.code} msg=${err.message}`);
      });
  });
}

// 查询一行快照（0.165.2 下行链路内部使用：pullAndNotify 拉快照通知业务层）
async function queryCloudData(key: string): Promise<string | null> {
  if (!await ensureReady() || rdbStore === null) {
    return null;
  }
  try {
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('key', key);
    const resultSet = await rdbStore.query(predicates, ['value']);
    let result: string | null = null;
    if (resultSet.goToNextRow()) {
      result = resultSet.getString(resultSet.getColumnIndex('value'));
    }
    resultSet.close();
    return result;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, `query ${key} failed: ${JSON.stringify(err)}`);
    return null;
  }
}

// ============================================================
// ★ 0.165.2：云端下行链路（dataChange 订阅 → 拉快照 → 通知业务层写回）
// ============================================================

// 注册下行处理器（ChatModel.setupCloudDownlink 调用；幂等，后注册覆盖先注册）
export function registerCloudDataHandler(handler: CloudDataHandler): void {
  downlinkHandler = handler;
}

// 查询分布式同步权限是否已授予（设置页「云同步」Tab 状态显示用）
export async function isCloudSyncGranted(): Promise<boolean> {
  return hasSyncPermission();
}

// 订阅云端数据变化（SUBSCRIBE_TYPE_CLOUD：云端数据下行到本地 RDB 后触发）——
// 事件里拉取两个快照 key 通知业务层；值比较与写回池由 ChatModel 侧 handler 负责。
// 本机 upsert 上云的「回声」由 handler 侧「值 != 池」比较天然挡住（相等不写回）
function subscribeCloudDownlink(): void {
  if (rdbStore === null) {
    return;
  }
  try {
    downlinkCallback = (storeUri: Array<string>) => { // ★ 0.196.8：回调存模块变量（deactivateCloudSync off 用）
      hilog.info(DOMAIN, TAG, `cloud dataChange: ${JSON.stringify(storeUri)}`);
      pullAndNotify('flat_pool');
      pullAndNotify('tabs_pool');
    };
    rdbStore.on('dataChange', relationalStore.SubscribeType.SUBSCRIBE_TYPE_CLOUD, downlinkCallback);
    hilog.info(DOMAIN, TAG, 'cloud dataChange subscribed');
  } catch (err) {
    hilog.warn(DOMAIN, TAG, `subscribe dataChange failed: ${JSON.stringify(err)}`);
  }
}

// 拉一行快照并通知业务层（值为 null = 表空/查询失败，不通知）
async function pullAndNotify(key: string): Promise<void> {
  if (downlinkHandler === null) {
    return;
  }
  const value = await queryCloudData(key);
  if (value !== null) {
    downlinkHandler(key, value);
  }
}

// ============================================================
// ★ 0.196.8：云同步 ↔ 华为账号登录态耦合（用户拍板：两状态同时开/同时关）
// ============================================================

// toast 静默包裹（同 GlobalSettingsDialog.showToastSafe——showToast 可能抛异常）
function toastSafe(uiContext: UIContext, msg: string): void {
  try {
    uiContext.getPromptAction().showToast({ message: msg, duration: 1500 });
  } catch (_e) {
    // 静默失败（toast 非关键路径）
  }
}

// ★ 0.196.9：登录后是否需要弹「是否开启云同步」询问（弹窗 UI 由 Index 根挂载的
//   AppConfirmDialog 承担——系统 AlertDialog 灰底与暗紫风格不符，用户实测反馈）
// isVipNow 由调用方传入（本文件不 import ChatModel——ChatModel 已 import 本文件，反向会循环依赖）；
// 非 VIP 不弹（云同步是会员功能，设置页显示「订阅后开启」，弹了也是死路）
export function shouldPromptCloudSyncAfterLogin(isVipNow: boolean): boolean {
  return !connectCloudSync().enabled && isVipNow;
}

// ★ 0.196.9：用户在「是否开启云同步」弹窗点「开启」——开关开；权限未授予则续弹系统授权窗
// （授权窗是系统级 UI 无法自定义；应用内弹窗已全部暗紫化）
export function enableCloudSyncNow(uiContext: UIContext): void {
  const context = uiContext.getHostContext() as common.UIAbilityContext;
  hasSyncPermission().then((granted: boolean) => {
    if (granted) {
      // 权限已在（如退出账号前授过）——开关一开即激活，无需再弹系统窗
      setCloudSyncEnabled(true);
      toastSafe(uiContext, '云同步已开启');
    } else if (context !== undefined && context !== null) {
      // 首次开启：弹系统授权窗（授权成功 requestSyncPermission 内部落开关+激活）
      requestSyncPermission(context).then((ok: boolean) => {
        toastSafe(uiContext, ok ? '云同步已开启' : '未授权，云同步保持关闭');
      });
    }
  });
}

// 退出账号成功后调用：开关强制关 + toast（仅在原本开着时提示——没开过就不打扰）
export function disableCloudSyncOnLogout(uiContext: UIContext): void {
  if (!connectCloudSync().enabled) {
    return;
  }
  setCloudSyncEnabled(false);
  toastSafe(uiContext, '云同步已随账号退出关闭');
}
