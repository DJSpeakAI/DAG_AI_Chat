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
// ★ 0.264.0：1→2 协议合规修订定稿（门禁拆分+SP 条款重写+三方 SDK 清单+链接核实）——存量已同意用户重新弹首启门禁
export const AGREEMENT_VERSION: number = 2;

// 勾选前缀文案
export const AGREEMENT_CHECK_PREFIX: string = '我已阅读并同意';

// 三项协议名
export const AGREEMENT_USER_NAME: string = '用户协议';
export const AGREEMENT_PRIVACY_NAME: string = '隐私政策';
export const AGREEMENT_HUAWEI_NAME: string = '华为账号用户认证协议';

// 华为账号用户认证协议官方链接
// ★ 0.264.0 已核实（curl 200 + 官方 FAQ faqs-account-17 确认「华为统一提供的隐私政策页面」）：
//   华为账号一键登录须提供本协议链接，跳转华为官方页面
export const HUAWEI_ACCOUNT_AGREEMENT_URL: string = 'https://privacy.consumer.huawei.com/legal/id/authentication-terms.htm?code=CN&language=zh-CN';

// 用户协议正文（分段渲染）
// ★ 0.264.0 协议合规修订定稿（桌面任务书照单施工）：服务说明修正矛盾+AI 标识+SP 虚拟服务规则+
//   行为规范补安全审核+开发者名称与回复时限+头部版本信息
export const USER_AGREEMENT_SECTIONS: string[] = [
  '版本号：v2.0；生效日期：2026年10月19日（上架前统一更新日期）',
  '本协议是您与 DAG AI Chat 开发者之间，就使用本应用服务所订立的协议。请您仔细阅读并充分理解本协议；您勾选同意或实际使用本应用，即视为已阅读并同意本协议全部内容。',
  '1. 服务说明：本应用是一款本地优先的 AI 对话与知识管理工具，提供对话、词库、知识库、云同步等功能。AI 对话能力由开发者统一接入的第三方 AI 服务（腾讯云 TokenHub 平台的 DeepSeek 模型）提供；您也可自行配置其他第三方 AI 服务商接口，相关服务由对应服务商提供，需遵守其协议。',
  '2. 账号与登录：您可使用华为账号登录本应用，首次登录前将单独征求您对《华为账号用户认证协议》的同意。登录仅用于云同步等需身份识别的功能；不登录可使用新建单词库、新建知识库、卡片复习等本地功能，AI 对话、云同步等需登录华为账号后使用。您应对账号安全负责。',
  '3. 用户行为规范：您承诺不利用本应用从事违法违规活动，不输入、上传、传播违法、色情、暴力、恐怖等有害内容，不得故意规避应用的内容安全审核机制；如有违规，我们有权限制或停止向您提供相关服务。因您使用本应用产生的内容由您自行负责。',
  '4. AI 生成内容：AI 生成内容仅供参考，可能存在错误或不准确，不构成任何专业建议，请勿直接将其作为医疗、法律、金融等专业决策依据。本应用所有 AI 生成内容均会添加「AI 生成」标识，请注意识别。请自行甄别并对使用后果负责。',
  '5. 司忆点（SP）与数据：司忆点（SP）是本应用内的虚拟服务点数，用于兑换 AI 对话等应用内服务。SP 分为充能 SP 与奖励 SP（兑换码、任务奖励等）：充能 SP 到账后、在未消耗任何点数前，您可在账单页申请退款；一旦产生任何消耗，即不可退款、退款入口将关闭；奖励 SP 不适用退款。SP 不具有现金价值，不可兑换、提现、转让或继承。SP 余额与消耗记录属于应用业务运营数据，不属于个人信息；我们如何处理您的信息，详见《隐私政策》，建议您一并阅读。',
  '6. 云同步服务：开启云同步后，您的数据将在您登录的华为账号设备间同步。您可随时关闭。',
  '7. 知识产权：本应用的软件、界面、商标等知识产权归开发者所有；您在本应用中创建的内容归您所有。',
  '8. 服务变更与终止：我们可能对服务进行升级、调整或终止；重大变更将提前告知。',
  '9. 免责声明：在法律允许范围内，本应用按"现状"提供，不对因使用或无法使用本应用造成的损失承担超出法律规定范围的责任。',
  '10. 第三方服务：您使用第三方 AI 服务、华为账号服务时，需同时遵守对应服务商的用户协议与隐私政策。',
  '11. 协议更新：本协议可能更新，重大更新后我们将重新征求您的同意。',
  '12. 联系方式：开发者：孙加腾；联系方式：1725912449@qq.com；我们将在 5 个工作日内回复。',
];

// 隐私政策正文（分段渲染）
// ★ 0.264.0 协议合规修订定稿：信息主体+第三方 SDK 清单（三方链接全部官方核实 200）+AI 服务精确化+
//   保存期限+权利处理时限+未成年人监护人提示
export const PRIVACY_SECTIONS: string[] = [
  'DAG AI Chat（开发者：孙加腾）深知个人信息对您的重要性，承诺严格遵守相关法律法规，遵循最小必要原则保护您的隐私安全。本政策说明我们如何收集、使用和保护您的信息。',
  '1. 本地存储：对话、单词库、知识库及 AI 配置（含 API Key）默认全部存储在设备本地，卸载即清除。本地功能不收集、不上传您的个人信息。您自行配置的 AI 服务商 API 密钥仅存储在设备本地，我们不收集、不上传或用于其他用途。',
  '2. AI 服务与安全审计：您的对话内容仅在您主动发起 AI 请求时，传输至腾讯云 TokenHub 平台（由腾讯云计算（北京）有限责任公司运营），由其调用 DeepSeek 模型生成回复；您可选择不发送任何内容。为履行内容安全与合规审计义务，服务商平台会对对话内容进行安全过滤，并留存审计日志不少于 6 个月（含输入与输出内容），仅用于安全审核与监管追溯，不另作他用。本应用自身不收集、不另行存储您的对话正文。为优化复习卡片的展示顺序，在您使用 AI 对话时，我们会将您当前的提问文本及相关复习卡片的标题与标签传输至 AI 服务商进行语义匹配计算。该数据仅用于排序处理，不涉及个人身份信息，不产生额外费用，不会存储或用于其他用途。',
  '3. 云同步：仅在您登录华为账号并主动开启后生效，数据经华为云空间加密，仅同步于您登录的华为账号设备之间。',
  '4. 华为账号信息：登录华为账号后，我们仅获取您的昵称、头像用于界面展示，仅存储在本地，不上传至第三方。',
  '5. 第三方 SDK 清单：为向您提供服务，本应用接入以下第三方 SDK，其信息处理受对应提供方隐私政策约束（链接可复制到浏览器查看）：',
  '（1）华为账号服务（Account Kit）｜提供方：华为软件技术有限公司｜收集的个人信息：昵称、头像、OpenID｜使用目的：登录、云同步身份识别｜隐私政策：https://consumer.huawei.com/cn/privacy/privacy-policy/',
  '（2）华为云空间（应用数据同步）｜提供方：华为软件技术有限公司｜收集的个人信息：用户主动同步的业务数据｜使用目的：跨设备数据同步｜隐私政策：https://consumer.huawei.com/cn/privacy/privacy-policy/',
  '（3）腾讯云 TokenHub（DeepSeek 模型）｜提供方：腾讯云计算（北京）有限责任公司｜收集的个人信息：用户主动发送的对话输入与输出内容｜使用目的：生成 AI 回复、内容安全审计｜隐私政策：https://cloud.tencent.com/document/product/301/11470',
  '6. 体验改进计划（可选，默认关闭）：在您单独同意后，我们会收集匿名的功能使用频次统计，并使用随机生成的匿名设备标识区分设备与统计活跃情况，该标识不包含任何个人信息、无法关联到您的真实身份。仅收集匿名功能点击次数与匿名设备标识，不含任何其他个人标识信息，不包含任何对话内容、学习内容，不用于其他任何目的。您可随时在「设置 → 关于」关闭。（体验改进统计为开发者自建服务，非第三方 SDK）',
  '7. 权限：仅在您主动选择图片时访问相册，无其他敏感权限。',
  '8. 保存期限：除法律法规另有规定外，您的个人信息保存期限为实现本政策所述目的所必需的最短时间：本地数据保存至您卸载应用；第三方审计日志按其平台政策留存不少于 6 个月。',
  '9. 您的权利：您可随时在「设置 → 云同步」关闭云同步、在「设置 → 关于」关闭体验改进计划，也可在「设置 → 关于 → 法律条款」点击「撤回同意」一键撤回全部协议同意（撤回后云同步将立即关闭，需重新同意后方可继续使用本应用；本机与云端数据不会删除），或卸载应用撤回全部同意并清除本地数据；撤回同意不影响此前基于同意开展的信息处理活动的效力。您可通过下方邮箱联系我们行使查询、更正、删除等权利，我们将在 15 个工作日内处理并回复您的请求。',
  '10. 第三方服务：您使用第三方 AI 服务、华为账号服务时，其信息处理受对应服务商隐私政策约束，请另行阅读。',
  '11. 未成年人：若您是未满 14 周岁的未成年人，请在监护人陪同下阅读本政策，并在监护人同意后使用本应用。监护人应关注未成年人使用 AI 对话功能时的对话内容，避免输入或接收不适宜的信息。',
  '12. 卸载提示：卸载应用将永久清除所有本地数据（对话、卡片、配置等），无法恢复，请谨慎操作。',
  '13. 政策更新：本政策可能更新，重大变更将以适当方式告知并重新征求您的同意。',
  '14. 联系我们：开发者：孙加腾；联系方式：1725912449@qq.com。',
  '版本号：v2.0；生效日期：2026年10月19日（上架前统一更新日期）',
];

// ★ 0.264.0：隐私政策敏感条款判定（华为审核独立项——「本地存储」「AI 服务与安全审计」突出展示）
//   展示层（GlobalSettingsDialog 法律条款弹窗 / AgreementDialog 正文）据此加粗，纯前缀匹配不依赖数组索引
export function isPrivacySensitiveSection(sec: string): boolean {
  return sec.startsWith('1. 本地存储') || sec.startsWith('2. AI 服务与安全审计');
}

// 同意状态（持久化——每台设备单独确认，不随云同步）
@ObservedV2
export class AgreementStore {
  @Trace agreed: boolean = false;           // 是否已同意全部协议
  @Trace agreedVersion: number = 0;         // 已同意的协议版本（落后则重新弹）
  @Trace improvePromptShown: boolean = false; // 体验改进计划引导是否已弹过（仅弹一次）
  @Trace hwAgreed: boolean = false;         // ★ 0.264.0：华为账号用户认证协议同意态（登录门禁，与基础协议分开征求；Schema 铁律尾部追加+默认值）
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
  @Trace hwPromptVisible: boolean = false; // ★ 0.264.0：华为协议登录门禁弹窗可见性（Index 根挂载）
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

// ★ 0.264.0：华为协议是否需要同意（登录门禁——首启基础门禁拆分后单独征求；同意一次即可，不随协议版本重置）
export function needsHwAgreement(): boolean {
  return !connectAgreement().hwAgreed;
}

// ★ 0.264.0：记录华为协议同意
export function markHwAgreed(): void {
  connectAgreement().hwAgreed = true;
}

// 撤回同意（关于页入口）——回到未同意态，重新 gate 登录/云同步
export function revokeAgreement(): void {
  const ag = connectAgreement();
  ag.agreed = false;
  ag.agreedVersion = 0;
  ag.hwAgreed = false; // ★ 0.264.0：一并重置华为协议同意（最简实现——重新走两段门禁）
}