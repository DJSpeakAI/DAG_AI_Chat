// FoldChevron.ets — ★ 0.237.0 全项目唯一折叠指示器（用户军令「全项目只许一套折叠三角」）
// ============================================================
// 病灶：折叠三角曾散落 3 套字符字形（▸/▾、▼/▲、▼/▶），系统字体下字面宽高/粗细天然不一致
//   且随字体更新漂移（0.235.2 换字形治标不治本）。
// 根治：同一颗华为风格细线 chevron SVG（chevron_fold.svg，this.theme.brandSecondary #A78BFA 内嵌），
//   收起态 0°（指右）、展开态 90°（指下）——同一颗图标转出来的两个状态，物理上不可能
//   再出现「另一个型号」；220ms EaseInOut 旋转（与章节折叠 220ms 动画同曲线）。
// 落点（军令清单）：章节折叠行 FoldRow / 边栏导航条+文件夹树 / 移动复制·加词·入库弹窗树 /
//   复习区·编辑器生词与知识卡词行 / TTS 折叠行——凡折叠三角必须用本组件（UI_GUIDELINES §13）。
// 禁止字符三角（▼▶▸▾▲）；发送按钮 ▾ 与下拉菜单 ▲/▼=「打开菜单」语义，不属折叠指示器。
// ============================================================
import { AppTheme, connectAppTheme } from '../common/AppTheme';

@ComponentV2
export struct FoldChevron {
  theme: AppTheme = connectAppTheme();
  @Param expanded: boolean = false; // 展开=90°指下 / 收起=0°指右
  @Param chevSize: number = 12;    // 默认 12vp（军令统一尺寸；命名避让内建 .size() 属性方法）
  @Param animate: boolean = true;  // 原无动画处可关（静态角度仍全项目统一）

  build() {
    Image($r('app.media.chevron_fold'))
      .width(this.chevSize)
      .height(this.chevSize)
      .fillColor(this.theme.brandSecondary)
      .rotate({ angle: this.expanded ? 90 : 0, centerX: '50%', centerY: '50%' })
      .animation({ duration: this.animate ? 220 : 0, curve: Curve.EaseInOut })
  }
}
