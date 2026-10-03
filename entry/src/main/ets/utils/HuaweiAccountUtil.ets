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
import { common } from '@kit.AbilityKit';

// ── 登录态持久化：昵称/头像/UnionID/OpenID ──
@ObservedV2
export class HuaweiAccountStore {
  @Trace isLoggedIn: boolean = false; // 是否已登录
  @Trace nickName: string = ''; // 华为账号昵称（未设置昵称时华为返回匿名手机号/邮箱）
  @Trace avatarUri: string = ''; // 头像 URL（用户更新头像后原链接会失效，仅作展示用）
  @Trace openID: string = ''; // 应用维度用户标识
  @Trace unionID: string = ''; // 开发者维度用户标识（云同步用）
}

// 连接持久化单例（key 固定 'huawei-account'，与 PersistData/api-config 同款模式）
export function connectHuaweiAccount(): HuaweiAccountStore {
  return PersistenceV2.connect(HuaweiAccountStore, 'huawei-account',
    () => new HuaweiAccountStore()) as HuaweiAccountStore;
}

// ── 官方错误码 → 用户可读中文提示（Account Kit 文档建议的 UI 交互处理） ──
// ★ 0.164.4 调试增强：提示末尾附上原始 code + 服务端 message，并同步 console 日志，
//    便于装机截图/DevEco Log 窗口定位真实错误（此前 1001502003 文案掩盖了服务端具体原因）
function errorToTip(error: BusinessError): string {
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
  console.error(`[HuaweiLogin] code=${error.code}, msg=${error.message}`); // DevEco Log 窗口可见
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
