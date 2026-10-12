// ============================================================
// CloudSyncUtil.ets — 端云数据同步传输层（★ 0.228.0 细粒度行模式重构）
// ============================================================
// 技术路线：ArkData 端云数据同步（RDB + cloudSync，数据存华为云空间）
//   - 本地 RDB 库 dag_chat_cloud.db（★ AGC 容器名必须 = dag_chat_cloud）
//   - 表 cloud_data：key TEXT 主键 / value TEXT / updated_at INTEGER
//   - setDistributedTables(DISTRIBUTED_CLOUD, autoSync: true)
// ★ 0.228.0 行模式（探针实证版 docs/0.165+/0.228.0 §四）：
//   - 一行一条：node:<id> / tab:<id> / word:<id> / card:<id> / wfolder:<id> /
//     kfolder:<id> / cfg:<name> / del:<id>（删除标记行——物理删行不传播，墓碑行化）
//   - 冲突裁决：TIME_FIRST 行级 LWW（探针 S3 实证）+ 桥接层 cache 语义仲裁
//   - 大值分块：value ≥ 512KB 拆 <key>~<n> chunk 行（探针实证 3MB 行毒化整批同步）
//   - 语义层（reconcile/flush）在 ChatModel.rowBridge——本文件只管传输与行原语
// 官方约束：主键唯一禁自增；表列只能新增；字段禁 NOT NULL；云侧 AGC 容器+数据类型配置
// ============================================================

import { relationalStore } from '@kit.ArkData';
import { abilityAccessCtrl, bundleManager, common } from '@kit.AbilityKit';
import { PersistenceV2, UIContext } from '@kit.ArkUI';

const DB_NAME = 'dag_chat_cloud.db';
const TABLE_NAME = 'cloud_data';
const CHUNK_THRESHOLD = 512 * 1024; // ★ 0.228.0：单行 value 分块阈值（探针实证 1MB 过/3MB 毒化批次，取 512KB 安全线）

// 模块级 RDB 实例 + 初始化 Promise（EntryAbility 启动时 init 一次，全应用共享）
let rdbStore: relationalStore.RdbStore | null = null;
let initPromise: Promise<boolean> | null = null;
let cloudSyncActive: boolean = false;
let downlinkCallback: ((storeUri: Array<string>) => void) | null = null;
// ★ 0.228.0：行就绪回调（ChatModel.rowBridge 注册——dataChange/forceSync 后触发 reconcile）
let rowsReadyHandler: (() => void) | null = null;
// ★ 0.228.0：脏域标记 → 防抖 flush（ChatModel 注册；upsertCloudData shim 触发）
let flushHandler: (() => void) | null = null;

// ★ 0.196.8：云同步应用级开关——与华为账号登录态绑定（同开同关）
@ObservedV2
export class CloudSyncStore {
  @Trace enabled: boolean = false;
}

export function connectCloudSync(): CloudSyncStore {
  return PersistenceV2.connect(CloudSyncStore, 'cloud-sync-switch',
    () => new CloudSyncStore()) as CloudSyncStore;
}

// ★ 0.228.0：仲裁器 v2（全新 key——0.224.1 教训：旧 key 尾追字段不持久化；v1 整体废弃）
//   只留行模式必需的两个标志：首拉闸门 + 旧池迁移标记
@ObservedV2
export class CloudSyncArbiter {
  @Trace rowInitDone: boolean = false;   // 首轮「拉全表+reconcile」完成前禁一切行上行（0.223.1 种子事故时序防线）
  @Trace legacyMigrated: boolean = false; // 旧四池行已吸收成条目行（迁移幂等标记）
}

export function connectCloudSyncArbiter(): CloudSyncArbiter {
  return PersistenceV2.connect(CloudSyncArbiter, 'cloud-sync-arbiter-v2',
    () => new CloudSyncArbiter()) as CloudSyncArbiter;
}

// ★ 0.228.0：行就绪回调注册（ChatModel.rowBridge——下行 reconcile 入口）
export function registerCloudRowsReady(handler: () => void): void {
  rowsReadyHandler = handler;
}

// ★ 0.228.0：flush 回调注册（ChatModel.rowBridge——上行防抖 flush 入口）
export function registerRowFlush(handler: () => void): void {
  flushHandler = handler;
}

// ★ 0.165.1：初始化云同步 RDB（幂等）
export function initCloudDb(context: common.UIAbilityContext): void {
  if (initPromise !== null) {
    return;
  }
  initPromise = (async (): Promise<boolean> => {
    try {
      const store = await relationalStore.getRdbStore(context, {
        name: DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1,
        autoCleanDirtyData: false
      });
      await store.executeSql(`CREATE TABLE IF NOT EXISTS ${TABLE_NAME} (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at INTEGER
      )`);
      rdbStore = store;
      const granted = await hasSyncPermission();
      if (granted && connectCloudSync().enabled) {
        activateCloudSync();
      }
      return true;
    } catch (_e) {
      return false;
    }
  })();
}

// ★ 0.165.1：激活端云同步（幂等）——设分布式表 + autoSync + 订阅下行 + 立即追赶
function activateCloudSync(): void {
  if (rdbStore === null || cloudSyncActive) {
    return;
  }
  try {
    rdbStore.setDistributedTables([TABLE_NAME], relationalStore.DistributedType.DISTRIBUTED_CLOUD,
      { autoSync: true });
    cloudSyncActive = true;
    subscribeCloudDownlink();
    forceCloudSyncNow();
  } catch (_e) {
    // 静默
  }
}

// ★ 0.223.0/0.228.0：强制立即端云同步（激活时/回前台追赶点）——完成后触发行 reconcile
export function forceCloudSyncNow(): void {
  if (!cloudSyncActive || rdbStore === null) {
    return;
  }
  try {
    rdbStore.cloudSync(relationalStore.SyncMode.SYNC_MODE_TIME_FIRST, [TABLE_NAME],
      (_progress: relationalStore.ProgressDetails): void => {
      }).then(() => {
      if (rowsReadyHandler !== null) {
        rowsReadyHandler(); // 拉全表 reconcile（容忍最终一致：dataChange 事件还会再触发）
      }
    }).catch(() => {
      // 静默（下次前台再试）
    });
  } catch (_e) {
    // 静默
  }
}

// ★ 0.196.8：停用端云同步（退出华为账号；幂等）
function deactivateCloudSync(): void {
  if (!cloudSyncActive) {
    return;
  }
  cloudSyncActive = false;
  if (rdbStore !== null && downlinkCallback !== null) {
    try {
      rdbStore.off('dataChange', relationalStore.SubscribeType.SUBSCRIBE_TYPE_CLOUD, downlinkCallback);
    } catch (_e) {
      // 静默
    }
  }
}

// ★ 0.196.8：设置应用级开关（三路径统一）
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

async function hasSyncPermission(): Promise<boolean> {
  try {
    const bundleInfo = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    const atm = abilityAccessCtrl.createAtManager();
    const result = await atm.checkAccessToken(bundleInfo.appInfo.accessTokenId,
      'ohos.permission.DISTRIBUTED_DATASYNC');
    return result === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  } catch (_e) {
    return false;
  }
}

export async function requestSyncPermission(context: common.UIAbilityContext): Promise<boolean> {
  try {
    const atm = abilityAccessCtrl.createAtManager();
    const result = await atm.requestPermissionsFromUser(context,
      ['ohos.permission.DISTRIBUTED_DATASYNC']);
    if (result.authResults.length > 0 &&
      result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      connectCloudSync().enabled = true;
      activateCloudSync();
      return true;
    }
    return false;
  } catch (_e) {
    return false;
  }
}

function ensureReady(): Promise<boolean> {
  if (initPromise === null) {
    return Promise.resolve(false);
  }
  return initPromise;
}

// ============================================================
// ★ 0.228.0 行原语（桥接层 ChatModel.rowBridge 专用）
// ============================================================

// 全表行（reconcile 用——含 chunk 行，桥接层自行重组）
export class CloudRow {
  key: string = '';
  value: string = '';
  updatedAt: number = 0;
}

export async function queryAllRows(): Promise<CloudRow[]> {
  const out: CloudRow[] = [];
  if (!await ensureReady() || rdbStore === null) {
    return out;
  }
  try {
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    const rs = await rdbStore.query(predicates, ['key', 'value', 'updated_at']);
    while (rs.goToNextRow()) {
      const r = new CloudRow();
      r.key = rs.getString(rs.getColumnIndex('key'));
      r.value = rs.getString(rs.getColumnIndex('value'));
      r.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'));
      out.push(r);
    }
    rs.close();
  } catch (_e) {
    // 静默（空表=无下行）
  }
  return out;
}

// 写一行（≥512KB 自动分块；闸门拦截——首拉 reconcile 完成前禁一切行写入，被闸变更由
//   闸门打开后的全量 flush 补写，本地数据零丢失）。回声/回环由桥接层 cache 语义挡。
export function upsertRow(key: string, value: string): void {
  if (!connectCloudSyncArbiter().rowInitDone) {
    return; // 首拉闸门（0.223.1 种子顶掉云端事故防线——行模式同源风险）
  }
  ensureReady().then((ok: boolean) => {
    if (!ok || rdbStore === null) {
      return;
    }
    const now = Date.now();
    const writes: Promise<void>[] = [];
    if (value.length > CHUNK_THRESHOLD) {
      // 主行存分块元信息，chunk 行 <key>~<n> 存原文片段
      const n = Math.ceil(value.length / CHUNK_THRESHOLD);
      writes.push(writeRow(key, JSON.stringify({ '__chunks': n }), now));
      for (let i = 0; i < n; i++) {
        writes.push(writeRow(`${key}~${i}`, value.substring(i * CHUNK_THRESHOLD, (i + 1) * CHUNK_THRESHOLD), now));
      }
    } else {
      // 非分块主行：清掉可能残留的旧 chunk 行（收缩为小块时防悬挂）
      writes.push(writeRow(key, value, now));
      writes.push(deleteRowLocal(`${key}~0`));
    }
    Promise.all(writes).catch(() => {
      // 静默（下次 flush 重试）
    });
  });
}

function writeRow(key: string, value: string, now: number): Promise<void> {
  const bucket: relationalStore.ValuesBucket = {
    'key': key,
    'value': value,
    'updated_at': now
  };
  return rdbStore!.insert(TABLE_NAME, bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE)
    .then(() => {
      return;
    });
}

// 本地删行（仅本地清理——物理删行不传播云端，删除语义走 del 标记行）
export function deleteRowLocal(key: string): Promise<void> {
  return new Promise<void>((resolve) => {
    ensureReady().then((ok: boolean) => {
      if (!ok || rdbStore === null) {
        resolve();
        return;
      }
      try {
        const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
        predicates.equalTo('key', key);
        rdbStore.delete(predicates).then(() => {
          resolve();
        }).catch(() => {
          resolve();
        });
      } catch (_e) {
        resolve();
      }
    });
  });
}

// ★ 0.228.4 临时清洗钩子（用户拍板零数据开测；验证后与 EntryAbility 挂点一并删）：
//   对全部实体行写 del 标记行+本地删行——del 行经正规 API 写入=框架认账会上传，
//   全端 reconcile 后语义清空（物理行残留云端无害被 del 压制）
export function wipeCloudRows(): void {
  ensureReady().then((ok: boolean) => {
    if (!ok) {
      return;
    }
    queryAllRows().then((rows: CloudRow[]) => {
      const now = Date.now();
      for (const r of rows) {
        const p = ['node:', 'tab:', 'word:', 'card:', 'wfolder:', 'kfolder:', 'layout:'];
        let hit = false;
        for (const pre of p) {
          if (r.key.startsWith(pre)) {
            hit = true;
            break;
          }
        }
        if (!hit) {
          continue;
        }
        const id = r.key.substring(r.key.indexOf(':') + 1);
        const o: Record<string, Object> = {};
        o['t'] = now;
        rdbStore!.insert(TABLE_NAME, {
          'key': 'del:' + id, 'value': JSON.stringify(o), 'updated_at': now
        } as relationalStore.ValuesBucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE).catch(() => {
        });
        deleteRowLocal(r.key);
      }
    }).catch(() => {
    });
  });
}
export function upsertCloudData(_key: string, _value: string): void {
  if (flushHandler !== null) {
    flushHandler(); // 桥接层内部 3 秒防抖合并
  }
}

// ============================================================
// 下行订阅（SUBSCRIBE_TYPE_CLOUD——云端数据下行到本地 RDB 后触发 reconcile）
// ============================================================
function subscribeCloudDownlink(): void {
  if (rdbStore === null) {
    return;
  }
  try {
    downlinkCallback = (storeUri: Array<string>) => {
      if (rowsReadyHandler !== null) {
        rowsReadyHandler();
      }
    };
    rdbStore.on('dataChange', relationalStore.SubscribeType.SUBSCRIBE_TYPE_CLOUD, downlinkCallback);
  } catch (_e) {
    // 静默
  }
}

export async function isCloudSyncGranted(): Promise<boolean> {
  return hasSyncPermission();
}

// ============================================================
// ★ 0.196.8：云同步 ↔ 华为账号登录态耦合（同开同关）
// ============================================================

function toastSafe(uiContext: UIContext, msg: string): void {
  try {
    uiContext.getPromptAction().showToast({ message: msg, duration: 1500 });
  } catch (_e) {
    // 静默
  }
}

export function shouldPromptCloudSyncAfterLogin(isVipNow: boolean): boolean {
  return !connectCloudSync().enabled && isVipNow;
}

export function enableCloudSyncNow(uiContext: UIContext): void {
  const context = uiContext.getHostContext() as common.UIAbilityContext;
  hasSyncPermission().then((granted: boolean) => {
    if (granted) {
      setCloudSyncEnabled(true);
      toastSafe(uiContext, '云同步已开启');
    } else if (context !== undefined && context !== null) {
      requestSyncPermission(context).then((ok: boolean) => {
        toastSafe(uiContext, ok ? '云同步已开启' : '未授权，云同步保持关闭');
      });
    }
  });
}

export function disableCloudSyncOnLogout(uiContext: UIContext): void {
  if (!connectCloudSync().enabled) {
    return;
  }
  setCloudSyncEnabled(false);
  toastSafe(uiContext, '云同步已随账号退出关闭');
}
