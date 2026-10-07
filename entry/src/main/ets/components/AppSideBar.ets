// AppSideBar.ets — ★ 0.195.0：应用边栏共享组件（从 BBTreeCanvas.SideBarPanel 抽取）
// 宿主两种形态（用户定稿「大屏边栏常驻，页面平移，体验非常棒」）：
//   ① Index 大屏常驻——平板/PC 边栏一直存在，页面在右侧 Navigation 区域平移不遮边栏
//   ② BBTreeCanvas 手机抽屉——translate 滑入滑出由宿主包裹层承担
// 导航逻辑全部经 onNavClick(kind) 注入宿主（本组件零导航）：
//   canvas/wordbank/knowledge/statistics/billing/settings/account；kind='' = 点边栏空白（手机收抽屉）

import { HuaweiAccountStore, connectHuaweiAccount, loginWithHuaweiID } from '../utils/HuaweiAccountUtil'; // ★ 0.196.9：logoutHuaweiID 删——退出确认弹窗移 Index 根挂载，确认后走 doLogout
import { SubscriptionStore, connectSubscription, isVip } from '../common/ChatModel'; // ★ 0.196.8：登录后云同步弹窗 VIP 判定
import { shouldPromptCloudSyncAfterLogin } from '../utils/CloudSyncUtil'; // ★ 0.196.8：云同步↔账号耦合；★ 0.196.9：弹窗 UI 移 AppConfirmDialog（暗紫）
import { connectConfirmDialog } from './AppConfirmDialog'; // ★ 0.196.9：确认弹窗触发桥（退出账号/云同步询问——Index 根挂载消费）
import { common } from '@kit.AbilityKit'; // ★ 0.196.2：头像登录（getHostContext 转 common.Context 调 loginWithHuaweiID）
import { requestPublishReviewWidget } from '../utils/WidgetReviewUtil'; // ★ 0.203.0：桌面卡片入口（请求发布复习卡片到桌面）
import { track } from '../utils/TrackUtil'; // 0.206.0 埋点
import { BG_NAV, RADIUS_LOGO, RADIUS_NAV, BRAND_PRIMARY, BRAND_SECONDARY, SURFACE_SOFT, SURFACE_HOVER, STROKE_CARD, TEXT_PRIMARY, TEXT_SECONDARY, TEXT_TERTIARY, FONT_SIZE_NAV_LABEL, FONT_SIZE_CARD_TITLE, FONT_SIZE_CARD_TITLE_SM, FONT_SIZE_CAPTION, FONT_INTER, FONT_INTER_SEMIBOLD } from '../common/DesignTokens';

@ComponentV2
export struct AppSideBar {
  @Event onNavClick: (kind: string) => void = (kind: string) => {};
  // ★ 0.195.0 bugfix：选中态动态跟踪（用户实测报 bug：停在统计页边栏仍高亮气泡树「对不上」——
  //   原画布项硬编码永久高亮已废）。宿主注入当前路由名，本组件按映射判定高亮；
  //   BBTreeCanvas 手机抽屉形态固定传 'BBTreeCanvas'（抽屉只能从画布唤出，人就在画布上）
  @Param currentRoute: string = '';
  @Param settingsOpen: boolean = false; // 设置是弹窗非页面：弹窗开着时高亮设置项
  account: HuaweiAccountStore = connectHuaweiAccount();
  subscription: SubscriptionStore = connectSubscription(); // ★ 0.196.8：登录后云同步弹窗 VIP 判定

  /** ★ 0.195.0：导航项高亮判定——当前路由映射（ChatPage/AnnotationPage 是气泡树子页，归气泡树） */
  isItemActive(kind: string): boolean {
    if (kind === 'canvas') {
      return this.currentRoute === 'BBTreeCanvas' || this.currentRoute === 'ChatPage' || this.currentRoute === 'AnnotationPage';
    }
    if (kind === 'wordbank') {
      return this.currentRoute === 'WordBankPage';
    }
    if (kind === 'knowledge') {
      return this.currentRoute === 'KnowledgeBankPage';
    }
    if (kind === 'review') {
      return this.currentRoute === 'ReviewPage'; // ★ 0.196.1：知识复习页
    }
    if (kind === 'statistics') {
      return this.currentRoute === 'StatisticsPage';
    }
    if (kind === 'billing') {
      return this.currentRoute === 'BillingPage';
    }
    if (kind === 'settings') {
      return this.settingsOpen;
    }
    return false;
  }

  /** 边栏导航项图标（canvas 走 bubbles.svg，其余同原 navIcon 映射） */
  navIcon(kind: string): Resource {
    if (kind === 'wordbank') {
      return $r('app.media.bookopen');
    }
    if (kind === 'knowledge') {
      return $r('app.media.library');
    }
    if (kind === 'review') {
      return $r('app.media.refresh'); // ★ 0.196.1：复习（循环箭头=重复记忆语义；后续可换专属图标）
    }
    if (kind === 'statistics') {
      return $r('app.media.chart');
    }
    if (kind === 'billing') {
      return $r('app.media.receipt');
    }
    return $r('app.media.settings');
  }

  /** 边栏导航项文字 */
  navLabel(kind: string): string {
    if (kind === 'wordbank') {
      return '单词库';
    }
    if (kind === 'knowledge') {
      return '知识库';
    }
    if (kind === 'review') {
      return '卡片复习'; // ★ 0.201.0：用户拍板「知识复习」→「卡片复习」（页面同改，复习页覆盖单词+知识卡两类）
    }
    if (kind === 'statistics') {
      return '统计';
    }
    if (kind === 'billing') {
      return '账单';
    }
    if (kind === 'settings') {
      return '设置';
    }
    return '气泡树'; // ★ 0.195.0：边栏「画布」→「气泡树」（用户定稿——命名与页面主体统一）
  }

  /** 账号显示名（未登录显示「未登录」） */
  getAccountDisplayName(): string {
    if (!this.account.isLoggedIn) {
      return '未登录';
    }
    if (this.account.nickName !== '') {
      return this.account.nickName;
    }
    if (this.account.openID !== '') {
      return `ID: ${this.account.openID.substring(0, 10)}…`;
    }
    return '已登录';
  }

  // 边栏 Logo（36×36 容器 225° 主紫渐变 + gitbranch，同节点图标容器视觉语言）
  @Builder
  SideBarLogo(size: number) {
    Column() {
      Image($r('app.media.gitbranch'))
        .width(size * 0.55)
        .height(size * 0.55)
        .objectFit(ImageFit.Contain)
    }
    .width(size)
    .height(size)
    .borderRadius(RADIUS_LOGO)
    .linearGradient({ angle: 225, colors: [[BRAND_PRIMARY, 0], [BRAND_SECONDARY, 1]] })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 边栏头像（登录态 avatarUri 圆形裁切；无头像/未登录柔面圆占位）
  @Builder
  SideBarAvatar(size: number) {
    if (this.account.avatarUri !== '') {
      Image(this.account.avatarUri)
        .width(size)
        .height(size)
        .borderRadius(size / 2)
        .clip(true)
        .objectFit(ImageFit.Cover)
    } else {
      Column() {
        Image($r('app.media.gitbranch'))
          .width(size * 0.5)
          .height(size * 0.5)
          .objectFit(ImageFit.Contain)
      }
      .width(size)
      .height(size)
      .borderRadius(size / 2)
      .backgroundColor(SURFACE_SOFT)
      .border({ width: 1, color: STROKE_CARD })
      .justifyContent(FlexAlign.Center)
    }
  }

  // 边栏导航项（气泡树=主选中态样式；点击经 onNavClick 交宿主裁决）
  @Builder
  SideBarNavItem(kind: string) {
    Row({ space: 10 }) {
      if (kind === 'canvas') {
        // ★ 0.195.0：DagIcon 自绘 → bubbles.svg（三气泡+连线，与画布实际视觉同构）
        Image($r('app.media.bubbles'))
          .width(18)
          .height(18)
          .objectFit(ImageFit.Contain)
      } else {
        Image(this.navIcon(kind))
          .width(18)
          .height(18)
          .objectFit(ImageFit.Contain)
      }
      Text(this.navLabel(kind))
        .fontSize(FONT_SIZE_NAV_LABEL)
        .fontFamily(this.isItemActive(kind) ? FONT_INTER_SEMIBOLD : FONT_INTER) // ★ 0.195.0 bugfix：硬编码 canvas 永久高亮 → 动态跟踪
        .fontColor(this.isItemActive(kind) ? TEXT_PRIMARY : TEXT_SECONDARY)
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .borderRadius(RADIUS_NAV)
    .backgroundColor(this.isItemActive(kind) ? SURFACE_HOVER : Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
 const _tp1: Record<string, string> = {}; _tp1['item'] = kind;
      track(this.getUIContext().getHostContext() as common.Context, 'sidebar_nav', _tp1); // 0.206.0 埋点：边栏导航
      this.onNavClick(kind);
    })
  }

  build() {
    Column() {
      // ── 顶部 Logo 区（Logo + 应用名 + 副标题）──
      Row({ space: 10 }) {
        this.SideBarLogo(36)
        Column({ space: 2 }) {
          Text('DAG AI Chat')
            .fontSize(FONT_SIZE_CARD_TITLE)
            .fontWeight(600)
            .fontFamily(FONT_INTER_SEMIBOLD)
            .fontColor(TEXT_PRIMARY)
            .maxLines(1)
          Text('你的AI学习伴侣')
            .fontSize(FONT_SIZE_CAPTION)
            .fontFamily(FONT_INTER)
            .fontColor(TEXT_TERTIARY)
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 20, bottom: 24 })

      // ── 导航项：气泡树（主）/ 单词库 / 知识库 / 复习 / 统计 / 账单 ──
      this.SideBarNavItem('canvas')
      this.SideBarNavItem('wordbank')
      this.SideBarNavItem('knowledge')
      this.SideBarNavItem('review') // ★ 0.196.1：知识复习（用户定稿：知识库下方）
      this.SideBarNavItem('statistics')
      this.SideBarNavItem('billing')

      // ── 弹性空隙（底部设置 + 账号沉底）──
      Blank()

      // ── 底部：设置 + 账号 ──
      this.SideBarNavItem('settings')
      Divider()
        .color(STROKE_CARD)
        .width('100%')
        .margin({ top: 6, bottom: 6 })
      Row({ space: 10 }) {
        this.SideBarAvatar(36)
        Text(this.getAccountDisplayName())
          .fontSize(FONT_SIZE_CARD_TITLE_SM)
          .fontFamily(FONT_INTER)
          .fontColor(TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        // ★ 0.203.0：桌面卡片小字入口（用户拍板：账户行右边小字「桌面卡片」，点击打开卡片管理器选规格添加）
        //   子组件 onClick 消费不冒泡——不会误触账户行的登录/退出逻辑
        Text('桌面卡片')
          .fontSize(10)
          .fontFamily(FONT_INTER_SEMIBOLD)
          .fontColor(BRAND_PRIMARY)
          .padding({ left: 6, right: 6, top: 3, bottom: 3 })
          .border({ width: 0.5, color: BRAND_SECONDARY })
          .borderRadius(8)
          .onClick(() => {
            requestPublishReviewWidget();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        // ★ 0.196.2 用户拍板：点头像=华为账号退出确认弹窗（原跳统计页废弃——统计已有边栏独立入口）
        // ★ 0.196.3 bugfix（用户实测「退出后再点没反应」）：未登录点头像=直接拉起登录
        if (!this.account.isLoggedIn) {
          track(this.getUIContext().getHostContext() as common.Context, 'login_huawei'); // 0.206.0 埋点：登录入口点击
          const loginContext = this.getUIContext().getHostContext() as common.Context;
          // ★ 0.196.8：登录成功 → 弹「是否开启云同步」（云同步与账号绑定，用户拍板流程）
          // ★ 0.196.9：弹窗 UI 换 AppConfirmDialog 暗紫（Index 根挂载，store 触发）
          loginWithHuaweiID(loginContext).then((tip: string) => {
            if (tip === '' && shouldPromptCloudSyncAfterLogin(isVip(this.subscription))) {
              connectConfirmDialog().cloudSyncPromptVisible = true;
            }
          });
          return;
        }
        // ★ 0.196.9：退出确认换 AppConfirmDialog 暗紫（原系统 AlertDialog 灰底，用户实测反馈
        //   与暗紫风格不符）——弹窗 Index 根挂载；确认后走 doLogout（退出 + 云同步强制关一条龙）
        connectConfirmDialog().logoutConfirmVisible = true;
      })
    }
    .width(208)
    .height('100%')
    .padding({ left: 12, right: 12, bottom: 16 })
    .backgroundColor(BG_NAV)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onNavClick(''); // 点边栏空白（手机抽屉收起；按钮 onClick 已消费不冒泡至此）
    })
  }
}

