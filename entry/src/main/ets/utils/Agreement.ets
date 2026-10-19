// ============================================================
// Agreement.ets — 用户协议 / 隐私政策 文案 + 同意状态（★ 0.226.0）
// ============================================================
// 「阅读并同意」机制的统一数据层：
//   - 持久化：AgreementStore（PersistenceV2 key 'agreement-v1'）
//       agreed / agreedVersion / improvePromptShown
//   - 运行时桥：AgreementBridge（AppStorageV2 key 'agreement-bridge'）
//       promptVisible / pendingAction / improveVisible（不持久化，重启即清）
//   - 三入口统一：首页勾选框 / 边栏登录 / 设置云同步 共用本状态
//   - 合规边界：同意只 gate「登录 / 云同步」，不禁用本地功能
// ============================================================

import { PersistenceV2, AppStorageV2 } from '@kit.ArkUI';
import { trackFirstAuto } from './TrackUtil'; // ★ 0.260.0：app_first 激活埋点（markAgreed 单一收口——两同意路径全覆盖）

// 协议版本：协议重大更新时 +1 → 下次启动/登录重新弹同意
export const AGREEMENT_VERSION: number = 1;

// 勾选前缀文案
export const AGREEMENT_CHECK_PREFIX: string = '我已阅读并同意';

// 三项协议名
export const AGREEMENT_USER_NAME: string = '用户协议';
export const AGREEMENT_PRIVACY_NAME: string = '隐私政策';
export const AGREEMENT_HUAWEI_NAME: string = '华为账号用户认证协议';

// 华为账号用户认证协议官方链接
// ⚠️ 待从华为 Account Kit 官方文档核实替换（不杜撰 URL）
export const HUAWEI_ACCOUNT_AGREEMENT_URL: string = 'https://developer.huawei.com/consumer/cn/';

// 用户协议正文（分段渲染）
export const USER_AGREEMENT_SECTIONS: string[] = [
  '本协议是您与 DAG AI Chat 开发者之间，就使用本应用服务所订立的协议。请您仔细阅读并充分理解本协议；您勾选同意或实际使用本应用，即视为已阅读并同意本协议全部内容。',
  '1. 服务说明：本应用是一款本地优先的 AI 对话与知识管理工具，提供对话、词库、知识库、云同步等功能。部分 AI 能力依赖您自行配置的第三方 AI 服务商接口。',
  '2. 账号与登录：您可使用华为账号登录本应用。登录仅用于云同步等需身份识别的功能，不登录亦可使用本地功能。您应对账号安全负责。',
  '3. 用户行为规范：您承诺不利用本应用从事违法违规活动，不输入、上传、传播违法、色情、暴力、恐怖等有害内容；如有违规，我们有权限制或停止向您提供相关服务。因您使用本应用产生的内容由您自行负责。',
  '4. AI 生成内容：AI 生成内容仅供参考，可能存在错误或不准确，不构成任何专业建议，请勿直接将其作为医疗、法律、金融等专业决策依据。请自行甄别并对使用后果负责。',
  '5. 数据与隐私：我们如何处理您的信息，详见《隐私政策》，建议您一并阅读。司忆点（SP）余额与消耗记录属于应用业务运营数据，不属于个人信息。',
  '6. 云同步服务：开启云同步后，您的数据将在您登录的华为账号设备间同步。您可随时关闭。',
  '7. 知识产权：本应用的软件、界面、商标等知识产权归开发者所有；您在本应用中创建的内容归您所有。',
  '8. 服务变更与终止：我们可能对服务进行升级、调整或终止；重大变更将提前告知。',
  '9. 免责声明：在法律允许范围内，本应用按"现状"提供，不对因使用或无法使用本应用造成的损失承担超出法律规定范围的责任。',
  '10. 第三方服务：您使用第三方 AI 服务、华为账号服务时，需同时遵守对应服务商的用户协议与隐私政策。',
  '11. 协议更新：本协议可能更新，重大更新后我们将重新征求您的同意。',
  '12. 联系方式：1725912449@qq.com',
];

// 隐私政策正文（分段渲染）
export const PRIVACY_SECTIONS: string[] = [
  'DAGAI 深知个人信息对您的重要性，承诺严格遵守相关法律法规，遵循最小必要原则保护您的隐私安全。本政策说明我们如何收集、使用和保护您的信息。',
  '1. 本地存储：对话、单词库、知识库及 AI 配置（含 API Key）默认全部存储在设备本地，卸载即清除。本地功能不收集、不上传您的个人信息。您自行配置的 AI 服务商 API 密钥仅存储在设备本地，我们不收集、不上传或用于其他用途。',
  '2. AI 服务与安全审计：对话内容仅在您主动发送时，传输至 AI 服务商（腾讯云 TokenHub 平台的 DeepSeek 模型）接口用于生成回复。为履行内容安全与合规审计义务，服务商平台会对对话内容进行安全过滤，并留存审计日志不少于 6 个月（含输入与输出内容），仅用于安全审核与监管追溯，不另作他用。本应用自身不收集、不另行存储您的对话正文。',
  '3. 云同步：仅在您登录华为账号并主动开启后生效，数据经华为云空间加密，仅同步于您登录的华为账号设备之间。',
  '4. 华为账号信息：登录华为账号后，我们仅获取您的昵称、头像用于界面展示，仅存储在本地，不上传至第三方。',
  '5. 体验改进计划（可选，默认关闭）：在您单独同意后，我们会收集匿名的功能使用频次统计，并使用随机生成的匿名设备标识区分设备与统计活跃情况，该标识不包含任何个人信息、无法关联到您的真实身份。仅收集匿名功能点击次数与匿名设备标识，不含任何其他个人标识信息，不包含任何对话内容、学习内容，不用于其他任何目的。您可随时在「设置 → 关于」关闭。',
  '6. 权限：仅在您主动选择图片时访问相册，无其他敏感权限。',
  '7. 您的权利：您可随时关闭云同步、关闭体验改进计划以撤回对应功能的同意，或卸载应用撤回全部同意并清除本地数据；撤回同意不影响此前基于同意开展的信息处理活动的效力。您可通过下方邮箱联系我们行使查询、更正、删除等权利。',
  '8. 第三方服务：您使用第三方 AI 服务、华为账号服务时，其信息处理受对应服务商隐私政策约束，请另行阅读。',
  '9. 未成年人：若您是未满 14 周岁的未成年人，请在监护人陪同下阅读本政策，并在监护人同意后使用本应用。',
  '10. 卸载提示：卸载应用将永久清除所有本地数据（对话、卡片、配置等），无法恢复，请谨慎操作。',
  '11. 政策更新：本政策可能更新，重大变更将以适当方式告知并重新征求您的同意。',
  '12. 联系我们：1725912449@qq.com',
  '生效日期：2026年10月12日',
];

// 同意状态（持久化——每台设备单独确认，不随云同步）
@ObservedV2
export class AgreementStore {
  @Trace agreed: boolean = false;           // 是否已同意全部协议
  @Trace agreedVersion: number = 0;         // 已同意的协议版本（落后则重新弹）
  @Trace improvePromptShown: boolean = false; // 体验改进计划引导是否已弹过（仅弹一次）
}

export function connectAgreement(): AgreementStore {
  return PersistenceV2.connect(AgreementStore, 'agreement-v1',
    () => new AgreementStore()) as AgreementStore;
}

// 运行时桥（不持久化——弹窗可见性与待执行动作，重启即清）
@ObservedV2
export class AgreementBridge {
  @Trace promptVisible: boolean = false;   // 同意弹窗可见性（Index 根唯一挂载）
  @Trace pendingAction: string = '';       // 同意后待执行：'' | 'login' | 'sync'
  @Trace improveVisible: boolean = false;  // 体验改进计划引导弹窗可见性
}

export function connectAgreementBridge(): AgreementBridge {
  return AppStorageV2.connect(AgreementBridge, 'agreement-bridge',
    () => new AgreementBridge()) as AgreementBridge;
}

// 是否需要（重新）同意：未同意 或 协议版本落后
export function needsAgreement(): boolean {
  const ag = connectAgreement();
  return !ag.agreed || ag.agreedVersion < AGREEMENT_VERSION;
}

// 记录同意
export function markAgreed(): void {
  const ag = connectAgreement();
  ag.agreed = true;
  ag.agreedVersion = AGREEMENT_VERSION;
  trackFirstAuto(); // ★ 0.260.0：app_first 一次性激活上报（内部幂等+隐私闸门：开关未开零动作、加入计划后恰 1 行）
}

// 撤回同意（关于页入口）——回到未同意态，重新 gate 登录/云同步
export function revokeAgreement(): void {
  const ag = connectAgreement();
  ag.agreed = false;
  ag.agreedVersion = 0;
}