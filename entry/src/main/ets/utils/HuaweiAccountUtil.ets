// ============================================================
// HuaweiAccountUtil.ets — 华为账号登录封装（★ 0.164）
// ============================================================
// 基于 Account Kit（@kit.AccountKit → authentication 模块）实现：
//   - loginWithHuaweiID()：拉起华为账号登录/授权页，获取昵称/头像/UnionID/OpenID
//   - logoutHuaweiID()：取消授权（退出账号）并清空本地登录态
//   - HuaweiAccountStore：登录态持久化（PersistenceV2，跨启动保存）
//
// 前置配置（AGC，详见 docs/0.164.md）：
//   - module.json5 metadata 配置 client_id（AGC 应用的 Client ID）
//   - 本项目 compatibleSdkVersion 6.1.1(24) ≥ 20，无需配置公钥指纹
//
// 云同步（后续版本）将以 unionID 作为用户唯一标识。
// ============================================================

import { authentication } from '@kit.AccountKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { PersistenceV2 } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { connectConfirmDialog } from '../components/AppConfirmDialog'; // ★ 0.248.3：登录引导弹窗桥（Index 根 Stack 消费；AppConfirmDialog 无反向依赖不成环）

// ── ★ 0.299.2 登录态影子持久化（bug5 根治）──
// 病灶（0.299.1 Pad 三时点诊断实锤）：P2 'huawei-account' 水合**永久失败**——盘值 isLoggedIn=true
// 完好、同文件其他 key（siyi-points/arbiter 等）3 秒内水合成功、唯此 key 运行时恒 factory（false），
// 华为 P2 引擎单 key 黑盒故障。修复=登录态双写 preferences 影子通道（agreement_store 同款实测可靠），
// 启动最早同步点恢复回写 P2 实例（@Trace 赋值 UI 即时刷新；赋值触发 P2 写盘=盘值本 true 无害）。
// ★ 老用户一次性迁移：影子空而 P2 盘值有登录态（水合读不出）→ 直接读 persistent_storage 文件原文
//   抽 huawei-account 条目回填影子（app 自有 filesDir 可读；此后冷启全走影子快路）。
let accountShadow: preferences.Preferences | null = null;

// onCreate 最早同步点调用（initAgreementPrefs 同款纪律——此后任意时刻读到的即磁盘真值）
export function initAccountShadow(context: common.Context): void {
  if (accountShadow === null) {
    accountShadow = preferences.getPreferencesSync(context, { name: 'account_shadow' });
    migrateShadowFromP2File(context); // 影子空→从 P2 盘值文件一次性迁移（老用户救活）
  }
}

function writeAccountShadow(store: HuaweiAccountStore): void {
  if (accountShadow === null) {
    return;
  }
  try {
    const data: Record<string, Object> = {
      'isLoggedIn': store.isLoggedIn,
      'nickName': store.nickName,
      'avatarUri': store.avatarUri,
      'openID': store.openID,
      'unionID': store.unionID,
      'lastAccountMark': store.lastAccountMark
    };
    accountShadow.putSync('account', JSON.stringify(data));
    accountShadow.flushSync();
  } catch (_e) {
    // 影子写失败静默（P2 主通道仍在；下次登录/退出再写）
  }
}

// 启动恢复：影子有登录态而 P2 实例仍 factory（水合失败态）→ 全字段回写救活。
// shadow 无值/未登录态不动作（新装/退出后正常走 factory）。UI 消费全部经 P2 实例（零改动）。
export function restoreAccountFromShadow(): void {
  if (accountShadow === null) {
    return;
  }
  try {
    const raw = accountShadow.getSync('account', '') as string;
    if (raw === '') {
      return;
    }
    const d = JSON.parse(raw) as Record<string, Object>;
    const shadowLoggedIn = d['isLoggedIn'] === true;
    const store = connectHuaweiAccount();
    if (shadowLoggedIn && !store.isLoggedIn) {
      store.isLoggedIn = true;
      store.nickName = `${d['nickName'] ?? ''}`;
      store.avatarUri = `${d['avatarUri'] ?? ''}`;
      store.openID = `${d['openID'] ?? ''}`;
      store.unionID = `${d['unionID'] ?? ''}`;
      // ★ bug6-b：影子里的 lastAccountMark 可能是「登录时先写影子、后落标记」的空值——
      //   空串回写会伪造「换号」导致资产重置（SP 清零事故）。空值一律不覆盖 P2 盘值。
      const shadowMark = `${d['lastAccountMark'] ?? ''}`;
      if (shadowMark !== '') {
        store.lastAccountMark = shadowMark;
      }
    }
  } catch (_e) {
    // 影子损坏静默（走正常未登录态，用户重新登录即重建影子）
  }
}

// ★ 一次性迁移：影子空→读 P2 盘值文件（persistent_storage，XML 转义格式）抽 huawei-account 条目。
//   P2 水合黑盒读不出但文件本身完好（4MB 文本，一次读可接受；只在影子空时跑一次）。
function migrateShadowFromP2File(context: common.Context): void {
  try {
    const raw = accountShadow!.getSync('account', '') as string;
    if (raw !== '') {
      return; // 影子已有数据（新登录/迁移过）——无需迁移
    }
    const path = `${context.filesDir}/persistent_storage`;
    const text = fileIo.readTextSync(path); // 不存在直接抛→外层 catch（accessSync 新 API 返 void 不可作布尔判断）
    const tag = '"huawei-account">&quot;';
    const i = text.indexOf(tag);
    if (i < 0) {
      return; // 盘上无登录记录
    }
    const start = i + tag.length;
    const end = text.indexOf('&quot;</string>', start);
    if (end <= start) {
      return; // 条目截断异常
    }
    const seg = text.substring(start, end);
    // 双重转义还原：XML 层 &quot;/&amp; → 第一层 JSON.parse（unescaped 本就是合法字符串体，\" 转义完好）
    // → 第二层 JSON.parse（对象）
    const unescaped = seg.replace(/&quot;/g, '"').replace(/&amp;/g, '&');
    const objStr = JSON.parse(`"${unescaped}"`) as string;
    const d = JSON.parse(objStr) as Record<string, Object>;
    if (d['isLoggedIn'] !== true) {
      return; // 盘值本就是登出态
    }
    const store = connectHuaweiAccount();
    if (!store.isLoggedIn) {
      store.isLoggedIn = true;
      store.nickName = `${d['nickName'] ?? ''}`;
      store.avatarUri = `${d['avatarUri'] ?? ''}`;
      store.openID = `${d['openID'] ?? ''}`;
      store.unionID = `${d['unionID'] ?? ''}`;
      store.lastAccountMark = `${d['lastAccountMark'] ?? ''}`;
      writeAccountShadow(store); // 回填影子——此后冷启走影子快路，不再读 4MB 文件
    }
  } catch (_e) {
    // 迁移失败静默（用户重新登录即重建影子）
  }
}

// ── 登录态持久化：昵称/头像/UnionID/OpenID ──
@ObservedV2
export class HuaweiAccountStore {
  @Trace isLoggedIn: boolean = false; // 是否已登录
  @Trace nickName: string = ''; // 华为账号昵称（未设置昵称时华为返回匿名手机号/邮箱）
  @Trace avatarUri: string = ''; // 头像 URL（用户更新头像后原链接会失效，仅作展示用）
  @Trace openID: string = ''; // 应用维度用户标识
  @Trace unionID: string = ''; // 开发者维度用户标识（云同步用）
  // ★ 0.293.0：上次登录账号标识（unionID||openID，Schema 尾部追加默认空串）——账号切换检测
  //   （同设备换登华为账号时触发 SP/等级/签到等账号级资产隔离重置，见 ChatModel.resetAccountAssetsOnAccountSwitch）
  @Trace lastAccountMark: string = '';
}

// 连接持久化单例（key 固定 'huawei-account'，与 PersistData/api-config 同款模式）
export function connectHuaweiAccount(): HuaweiAccountStore {
  return PersistenceV2.connect(HuaweiAccountStore, 'huawei-account',
    () => new HuaweiAccountStore()) as HuaweiAccountStore;
}

// ── 官方错误码 → 用户可读中文提示（Account Kit 文档建议的 UI 交互处理） ──
// ★ 0.164.4 调试增强：提示末尾附上原始 code + 服务端 message，并同步 console 日志，
//    便于装机截图/DevEco Log 窗口定位真实错误（此前 1001502003 文案掩盖了服务端具体原因）
// ★ 0.196.9：用户主动取消授权（1001502012）是正常行为非错误——固定短提示、不附 code
//    调试后缀、不打错误日志；调用方据 AUTH_CANCELLED_TIP 静默处理（首页红字 bug 用户实测报）
export const AUTH_CANCELLED_TIP: string = '已取消授权';

function errorToTip(error: BusinessError): string {
  if (error.code === 1001502012) {
    return AUTH_CANCELLED_TIP; // 用户主动取消——正常行为，静默素材（调用方判断后不显示）
  }
  let tip: string;
  if (error.code === 1001502001) {
    tip = '未登录华为账号，请先在系统设置中登录华为账号';
  } else if (error.code === 1001502005) {
    tip = '网络错误，请检查网络后重试';
  } else if (error.code === 1001502012) {
    tip = '已取消授权';
  } else if (error.code === 1001500002) {
    tip = '请求处理中，请勿重复点击';
  } else if (error.code === 1001500001) {
    tip = '应用指纹校验失败，需在 AGC 配置证书指纹';
  } else if (error.code === 1001502002) {
    tip = '应用未获得授权，请重新授权';
  } else if (error.code === 1001502003) {
    tip = '登录参数异常，请更新应用后重试';
  } else if (error.code === 1001502009) {
    tip = '华为账号服务内部错误，请稍后重试';
  } else if (error.code === 12300001) {
    tip = '系统服务异常，请稍后重试';
  } else {
    tip = '操作失败';
  }
  // ★ 0.164.4：附原始错误码 + 服务端 message（截断 200 字符防 UI 溢出）
  const rawMsg = (error.message || '').substring(0, 200);
  return `${tip}【code=${error.code}${rawMsg ? ` | ${rawMsg}` : ''}】`;
}

// ── 华为账号登录：拉起授权页，成功后保存昵称/ID ──
// 返回空字符串 = 成功；非空 = 给用户的错误提示
export function loginWithHuaweiID(context: common.Context): Promise<string> {
  return new Promise<string>((resolve) => {
    const store = connectHuaweiAccount();
    // 创建授权请求：scopes 传 profile 拿昵称头像（个人开发者可用，无需申请权限）
    // ★ 0.164.2 修复 1001502003：'openid' 是默认 scope 无需显式传（官方注释原文：'openid'为默认值可不传），
    //    显式传 ['openid','profile'] 组合会触发服务端参数校验失败；官方「获取头像昵称」示例只传 ['profile']，
    //    openID/unionID 由 AuthorizationWithHuaweiIDCredential 默认返回
    const authRequest = new authentication.HuaweiIDProvider().createAuthorizationWithHuaweiIDRequest();
    authRequest.scopes = ['profile'];
    authRequest.forceAuthorization = true; // 未登录拉起登录页、未授权拉起授权页
    authRequest.state = util.generateRandomUUID(); // 防跨站攻击（官方要求一致性比对）
    try {
      const controller = new authentication.AuthenticationController(context);
      controller.executeRequest(authRequest).then((data) => {
        const response = data as authentication.AuthorizationWithHuaweiIDResponse;
        // state 一致性校验（官方要求）
        const normalizedRequestState = authRequest.state || '';
        const normalizedState = response.state || '';
        if (normalizedRequestState !== normalizedState) {
          resolve('登录异常（state 不一致），请重试');
          return;
        }
        const credential = response.data;
        if (!credential) {
          resolve('登录失败：未返回用户凭据');
          return;
        }
        // 保存登录态（昵称优先；华为账号未设置昵称时返回匿名手机号/邮箱）
        store.isLoggedIn = true;
        store.nickName = credential.nickName || '';
        store.avatarUri = credential.avatarUri || '';
        store.openID = credential.openID || '';
        store.unionID = credential.unionID || '';
        writeAccountShadow(store); // ★ 0.299.2：影子通道双写（P2 水合黑盒防断粮）
        resolve('');
      }).catch((error: BusinessError) => {
        resolve(errorToTip(error));
      });
    } catch (error) {
      resolve(errorToTip(error as BusinessError));
    }
  });
}

// ── 退出账号：取消授权 + 清空本地登录态 ──
// 返回空字符串 = 成功；非空 = 错误提示（本地登录态仍会清空，下次登录重新授权）
export function logoutHuaweiID(context: common.Context): Promise<string> {
  return new Promise<string>((resolve) => {
    const store = connectHuaweiAccount();
    const cancelRequest = new authentication.HuaweiIDProvider().createCancelAuthorizationRequest();
    cancelRequest.state = util.generateRandomUUID();
    // 清空本地登录态（无论取消授权成败都清，保证退出后回到未登录态）
    const clearLocal = (): void => {
      store.isLoggedIn = false;
      store.nickName = '';
      store.avatarUri = '';
      store.openID = '';
      store.unionID = '';
      writeAccountShadow(store); // ★ 0.299.2：影子同步清（防旧影子把退出态救活）
    };
    try {
      const controller = new authentication.AuthenticationController(context);
      controller.executeRequest(cancelRequest).then(() => {
        clearLocal();
        resolve('');
      }).catch((error: BusinessError) => {
        clearLocal();
        resolve(errorToTip(error));
      });
    } catch (error) {
      clearLocal();
      resolve(errorToTip(error as BusinessError));
    }
  });
}

// ★ 0.248.3：云能力统一守卫（上架合规——用户拍板边界：未登录仅可用单词库/知识库新建浏览+卡片复习；
//   AI 对话/导入/导出/圈注/划词翻译/划词入知识库/AI 查词全部拦截）
// 返回 true=已登录放行；false=未登录且已拉起「需要登录」引导弹窗（Index 根 Stack 消费，调用方直接 return）
export function requireLoginForCloud(): boolean {
  if (connectHuaweiAccount().isLoggedIn) {
    return true;
  }
  connectConfirmDialog().aiLoginPromptVisible = true;
  return false;
}
