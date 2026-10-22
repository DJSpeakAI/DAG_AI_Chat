// ============================================================
// SketchPage.ets — ★ 0.297.0 数学证明画板（无限画布）
// ============================================================
// 场景：数学证明手写（抽象代数等）→ 画完导出一张图 → 走现有图片附件流发 AI。
// 架构（用户拍板自绘，弃 Pen Kit——其只支持纵向长画布/私有格式/工具栏不可定制）：
//   - 无限画布 = 视口 Canvas + 世界坐标（Canvas ≤10000px 限制天然规避，华为 FAQ 实锤）；
//     笔迹按世界坐标矢量存储，缩放平移矢量重放永不模糊（BBTreeCanvas 骨架复刻）
//   - 屏幕坐标 = 世界坐标 × viewScale + view 偏移；PinchGesture 捏合中心锚点公式
//   - 手势分工：单指=书写（增量描线）；双指 Pan+Pinch=平移缩放（navActive+触点数双保险防误画）
//   - 防手掌误触：手写笔活跃后 800ms 内的手指触摸忽略（Pad 书写场景）
//   - 双色笔 token 复用：浅色=黑(textPrimary)+红(danger)；深色=白(textPrimary)+黄(reviewGood)
//   - 导出：全部笔迹包围盒 → OffscreenCanvas 矢量重放（短边≥1080px，上限 8000px）
//     → JPEG 0.92 dataUri → SketchResultStore 回传 → ChatPage @Monitor 挂 pendingImages
// 导航：NavPathStack（Index.pageMap 'SketchPage' 分发，AnnotationPage 同模式）。
// ============================================================

import { AppTheme, connectAppTheme } from '../common/AppTheme';
import { connectSketchResult } from '../common/SketchModel';
import { RADIUS_CONTROL, RADIUS_NAV, FONT_SIZE_SCREEN_TITLE, FONT_SIZE_BODY, FONT_SIZE_CARD_TITLE_SM, FONT_SIZE_CAPTION } from '../common/DesignTokens';

// 一笔：颜色 + 世界坐标点序列（x0,y0,x1,y1,... 扁平存储，页面会话级不持久化）
class SketchStroke {
  color: string;
  pts: number[];

  constructor(color: string, pts: number[]) {
    this.color = color;
    this.pts = pts;
  }
}

const PEN_WIDTH = 3;          // 笔宽（世界单位，缩放导出等比）
const VIEW_SCALE_MIN = 0.15;  // 缩小下限（缩小看全局）
const VIEW_SCALE_MAX = 5;     // 放大上限
const EXPORT_MIN_SIDE = 1080; // 导出短边目标像素（高清档）
const EXPORT_MAX_SIDE = 8000; // 导出单边像素上限（防超 Canvas 限制/内存）
const EXPORT_PADDING = 24;    // 导出包围盒外留白（世界单位）
const PALM_REJECT_MS = 800;   // 手写笔活跃后手掌（手指）拒触窗口

@ComponentV2
export struct SketchPage {
  theme: AppTheme = connectAppTheme();
  @Param pathStack: NavPathStack = new NavPathStack();
  result = connectSketchResult();

  // 视图变换（世界→屏幕：sx = wx*scale + vx）
  @Local viewScale: number = 1;
  @Local viewX: number = 0;
  @Local viewY: number = 0;
  // 笔画栈（整体替换触发刷新：撤销按钮态/空态提示/返回确认）
  @Local strokes: SketchStroke[] = [];
  @Local penIndex: number = 0; // 0=主色笔 1=强调笔
  @Local exitConfirmVisible: boolean = false;

  private ctx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private canvasW: number = 0; // 视口尺寸（vp，onReady 记录）
  private canvasH: number = 0;
  private currentStroke: SketchStroke | null = null; // 正在绘制的一笔
  private navActive: boolean = false;    // 双指手势（缩放/平移）进行中——书写忽略
  private pinchStartScale: number = 1;
  private panStartX: number = 0;
  private panStartY: number = 0;
  private lastPenAt: number = 0;         // 最近一次手写笔事件时间（防手掌误触）
  private palmRejectedId: number = -1;   // 被手掌判定拒绝的触点 id（Down→Up 全程忽略）
  private hasInk: boolean = false;       // 画布是否有笔迹（strokes 与绘制中合并判断，空态提示用）

  // ── 笔色（token 复用零散色）：浅色=黑+红 / 深色=白+黄 ──
  penColor(i: number): string {
    return i === 0 ? this.theme.textPrimary : (this.theme.isDark ? this.theme.reviewGood : this.theme.danger);
  }

  // ── 坐标换算 ──
  toWorld(sx: number, sy: number): number[] {
    return [(sx - this.viewX) / this.viewScale, (sy - this.viewY) / this.viewScale];
  }

  // ── 触摸书写（单指；双指手势期间忽略并丢弃当前笔画） ──
  onCanvasTouch(event: TouchEvent): void {
    if (this.canvasW <= 0) {
      return;
    }
    const pt = event.touches[0];
    if (pt === undefined) {
      return;
    }
    const isFinger = event.sourceTool === SourceTool.Finger; // 输入源（TouchEvent 级属性，非 TouchObject）
    // 手写笔事件刷新活跃时间；手指在笔活跃窗口内=手掌误触（Pad 书写场景），Down→Up 全程拒绝
    if (!isFinger) {
      this.lastPenAt = Date.now();
    }
    if (event.type === TouchType.Down) {
      if (isFinger && Date.now() - this.lastPenAt < PALM_REJECT_MS) {
        this.palmRejectedId = pt.id;
        return;
      }
      if (this.navActive || event.touches.length >= 2) {
        return; // 手势中落指不画
      }
      const w = this.toWorld(pt.x, pt.y);
      this.currentStroke = new SketchStroke(this.penColor(this.penIndex), [w[0], w[1]]);
      // 落笔即画圆点（轻点留痕）
      this.ctx.beginPath();
      this.ctx.fillStyle = this.currentStroke.color;
      this.ctx.arc(pt.x, pt.y, PEN_WIDTH * this.viewScale / 2, 0, Math.PI * 2);
      this.ctx.fill();
      this.hasInk = true;
      return;
    }
    if (event.type === TouchType.Move) {
      if (pt.id === this.palmRejectedId) {
        return;
      }
      // 双指/手势接管：丢弃正在进行的笔画并清痕重绘
      if (this.navActive || event.touches.length >= 2) {
        this.dropCurrentStroke();
        return;
      }
      const s = this.currentStroke;
      if (s === null) {
        return;
      }
      const n = s.pts.length;
      if (n < 2) {
        return;
      }
      const prevSx = s.pts[n - 2] * this.viewScale + this.viewX;
      const prevSy = s.pts[n - 1] * this.viewScale + this.viewY;
      const w = this.toWorld(pt.x, pt.y);
      s.pts.push(w[0], w[1]);
      // 增量描线：只画上一世界点→当前段（实时跟手）
      this.ctx.strokeStyle = s.color;
      this.ctx.lineWidth = PEN_WIDTH * this.viewScale;
      this.ctx.lineCap = 'round';
      this.ctx.lineJoin = 'round';
      this.ctx.beginPath();
      this.ctx.moveTo(prevSx, prevSy);
      this.ctx.lineTo(pt.x, pt.y);
      this.ctx.stroke();
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (pt.id === this.palmRejectedId) {
        this.palmRejectedId = -1;
        return;
      }
      this.commitCurrentStroke();
    }
  }

  // 丢弃正在进行的笔画并清痕（双指接管/单指变双指）
  dropCurrentStroke(): void {
    if (this.currentStroke !== null) {
      this.currentStroke = null;
      this.fullRedraw();
    }
  }

  // 收笔入栈（整体替换触发 @Local 刷新）
  commitCurrentStroke(): void {
    const s = this.currentStroke;
    if (s !== null && s.pts.length >= 2) {
      this.strokes = [...this.strokes, s];
    }
    this.currentStroke = null;
  }

  // ── 全量重绘：清屏 + 逐笔矢量重放（世界→屏幕） ──
  fullRedraw(): void {
    if (this.canvasW <= 0) {
      return;
    }
    this.ctx.clearRect(0, 0, this.canvasW, this.canvasH);
    this.ctx.lineCap = 'round';
    this.ctx.lineJoin = 'round';
    for (let i = 0; i < this.strokes.length; i++) {
      this.drawStrokeScreen(this.strokes[i]);
    }
    if (this.currentStroke !== null) {
      this.drawStrokeScreen(this.currentStroke);
    }
    this.hasInk = this.strokes.length > 0 || this.currentStroke !== null;
  }

  // 世界系笔画 → 屏幕坐标绘制
  drawStrokeScreen(s: SketchStroke): void {
    const n = s.pts.length;
    if (n < 2) {
      return;
    }
    this.ctx.strokeStyle = s.color;
    this.ctx.lineWidth = PEN_WIDTH * this.viewScale;
    this.ctx.beginPath();
    this.ctx.moveTo(s.pts[0] * this.viewScale + this.viewX, s.pts[1] * this.viewScale + this.viewY);
    for (let i = 2; i < n; i += 2) {
      this.ctx.lineTo(s.pts[i] * this.viewScale + this.viewX, s.pts[i + 1] * this.viewScale + this.viewY);
    }
    this.ctx.stroke();
  }

  // 撤销上一笔
  undoStroke(): void {
    if (this.strokes.length === 0) {
      return;
    }
    this.strokes = this.strokes.slice(0, this.strokes.length - 1);
    this.fullRedraw();
  }

  // ── 导出：包围盒 + OffscreenCanvas 矢量重放 → JPEG dataUri → store 回传 ──
  exportAndReturn(): void {
    const total = this.strokes.length;
    if (total === 0) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '还没画任何内容' });
      } catch (_e) {
        // toast 失败静默（不影响主流程）
      }
      return;
    }
    // 世界系包围盒
    let minX = Infinity;
    let minY = Infinity;
    let maxX = -Infinity;
    let maxY = -Infinity;
    for (let i = 0; i < total; i++) {
      const pts = this.strokes[i].pts;
      for (let j = 0; j + 1 < pts.length; j += 2) {
        if (pts[j] < minX) {
          minX = pts[j];
        }
        if (pts[j] > maxX) {
          maxX = pts[j];
        }
        if (pts[j + 1] < minY) {
          minY = pts[j + 1];
        }
        if (pts[j + 1] > maxY) {
          maxY = pts[j + 1];
        }
      }
    }
    minX -= EXPORT_PADDING;
    minY -= EXPORT_PADDING;
    maxX += EXPORT_PADDING;
    maxY += EXPORT_PADDING;
    const wWorld = Math.max(maxX - minX, 1);
    const hWorld = Math.max(maxY - minY, 1);
    // 导出倍率：短边 ≥1080px 高清，单边 ≤8000px 防超限
    let s = Math.min(3, Math.max(1, EXPORT_MIN_SIDE / Math.min(wWorld, hWorld)));
    if (Math.max(wWorld, hWorld) * s > EXPORT_MAX_SIDE) {
      s = EXPORT_MAX_SIDE / Math.max(wWorld, hWorld);
    }
    const wPx = Math.max(2, Math.floor(wWorld * s));
    const hPx = Math.max(2, Math.floor(hWorld * s));
    const off = new OffscreenCanvas(wPx, hPx);
    const octx = off.getContext('2d', new RenderingContextSettings(true));
    // 底色跟随主题（用户拍板所见即所得）
    octx.fillStyle = this.theme.bgCanvas;
    octx.fillRect(0, 0, wPx, hPx);
    octx.lineCap = 'round';
    octx.lineJoin = 'round';
    octx.lineWidth = PEN_WIDTH * s;
    for (let i = 0; i < total; i++) {
      const stroke = this.strokes[i];
      const pts = stroke.pts;
      if (pts.length < 2) {
        continue;
      }
      octx.strokeStyle = stroke.color;
      octx.beginPath();
      octx.moveTo((pts[0] - minX) * s, (pts[1] - minY) * s);
      for (let j = 2; j + 1 < pts.length; j += 2) {
        octx.lineTo((pts[j] - minX) * s, (pts[j + 1] - minY) * s);
      }
      octx.stroke();
    }
    this.result.imageUri = octx.toDataURL('image/jpeg', 0.92);
    this.pathStack.pop();
  }

  // 返回入口：有笔迹时二次确认（防误触丢弃证明草稿）
  requestExit(): boolean {
    if (this.strokes.length > 0 || this.currentStroke !== null) {
      this.exitConfirmVisible = true;
      return true;
    }
    this.pathStack.pop();
    return true;
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          // ── 顶栏：✕ | 标题 | 撤销 | 完成 ──
          Row() {
            Button('✕')
              .fontSize(16)
              .backgroundColor(Color.Transparent)
              .fontColor(this.theme.textSecondary)
              .padding({ left: 4, right: 4 })
              .margin({ right: 4 })
              .onClick(() => {
                this.requestExit();
              })
            Text('画板')
              .fontSize(FONT_SIZE_SCREEN_TITLE)
              .fontWeight(600)
              .fontColor(this.theme.textPrimary)
            Blank()
              .layoutWeight(1)
            Row() {
              Image($r('app.media.undo'))
                .width(16)
                .height(16)
                .objectFit(ImageFit.Contain)
            }
            .opacity(this.strokes.length > 0 ? 1 : 0.4)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .onClick(() => {
              this.undoStroke();
            })
            Button('完成')
              .fontSize(FONT_SIZE_CARD_TITLE_SM)
              .backgroundColor(this.theme.brandPrimary)
              .fontColor(Color.White)
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .borderRadius(RADIUS_CONTROL)
              .margin({ left: 8 })
              .onClick(() => {
                this.exportAndReturn();
              })
          }
          .width('100%')
          .padding({ left: 8, right: 12, top: 8, bottom: 4 })

          // ── 无限画布区 ──
          Stack() {
            Canvas(this.ctx)
              .width('100%')
              .height('100%')
              .onReady(() => {
                // 画布就绪/尺寸变化（清屏）→ 全量重放（faqs-arkui-1049）
                this.canvasW = px2vp(this.ctx.width);
                this.canvasH = px2vp(this.ctx.height);
                this.fullRedraw();
              })
              .onTouch((event: TouchEvent) => {
                this.onCanvasTouch(event);
              })
              // 双指平移（单指是画笔不绑 Pan）
              .gesture(
                PanGesture({ fingers: 2, distance: 3 })
                  .onActionStart(() => {
                    this.navActive = true;
                    this.dropCurrentStroke();
                    this.panStartX = this.viewX;
                    this.panStartY = this.viewY;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    this.viewX = this.panStartX + event.offsetX;
                    this.viewY = this.panStartY + event.offsetY;
                    this.fullRedraw();
                  })
                  .onActionEnd(() => {
                    this.navActive = false;
                  })
              )
              // 双指捏合缩放（捏合中心锚点，BBTreeCanvas 同公式）
              .gesture(
                PinchGesture({ fingers: 2 })
                  .onActionStart(() => {
                    this.navActive = true;
                    this.dropCurrentStroke();
                    this.pinchStartScale = this.viewScale;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    const newScale = Math.min(VIEW_SCALE_MAX,
                      Math.max(VIEW_SCALE_MIN, this.pinchStartScale * event.scale));
                    const ratio = newScale / this.viewScale;
                    this.viewX = event.pinchCenterX - (event.pinchCenterX - this.viewX) * ratio;
                    this.viewY = event.pinchCenterY - (event.pinchCenterY - this.viewY) * ratio;
                    this.viewScale = newScale;
                    this.fullRedraw();
                  })
                  .onActionEnd(() => {
                    this.navActive = false;
                  })
              )
            // 空态提示（无笔迹时显示操作引导）
            if (!this.hasInk) {
              Column({ space: 6 }) {
                Text('单指书写 · 双指缩放平移')
                  .fontSize(FONT_SIZE_BODY)
                  .fontColor(this.theme.textTertiary)
                Text('无限画布，随便写随便推')
                  .fontSize(FONT_SIZE_CAPTION)
                  .fontColor(this.theme.textTertiary)
              }
              .justifyContent(FlexAlign.Center)
              .hitTestBehavior(HitTestMode.None)
            }
          }
          .width('100%')
          .layoutWeight(1)

          // ── 底栏：双色笔切换 ──
          Row({ space: 24 }) {
            Row() {
              Column()
                .width(22)
                .height(22)
                .borderRadius(11)
                .backgroundColor(this.penColor(0))
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .borderRadius(18)
            .border({
              width: this.penIndex === 0 ? 1.5 : 1,
              color: this.penIndex === 0 ? this.theme.strokeBrand : Color.Transparent
            })
            .backgroundColor(this.penIndex === 0 ? this.theme.surfaceSoft : Color.Transparent)
            .onClick(() => {
              this.penIndex = 0;
            })

            Row() {
              Column()
                .width(22)
                .height(22)
                .borderRadius(11)
                .backgroundColor(this.penColor(1))
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .borderRadius(18)
            .border({
              width: this.penIndex === 1 ? 1.5 : 1,
              color: this.penIndex === 1 ? this.theme.strokeBrand : Color.Transparent
            })
            .backgroundColor(this.penIndex === 1 ? this.theme.surfaceSoft : Color.Transparent)
            .onClick(() => {
              this.penIndex = 1;
            })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 8, bottom: 10 })
        }
        .width('100%')
        .height('100%')
        .background(this.theme.bgApp)

        // ── 返回二次确认弹窗（有笔迹时防误触丢弃） ──
        if (this.exitConfirmVisible) {
          Stack() {
            Column() {
              Blank()
            }
            .width('100%')
            .height('100%')
            .backgroundColor(this.theme.overlay)

            Column() {
              Text('丢弃画板内容？')
                .fontSize(16)
                .fontWeight(600)
                .fontColor(this.theme.textPrimary)
                .margin({ bottom: 8 })
              Text('画板尚未完成导出，退出将丢弃当前笔迹')
                .fontSize(FONT_SIZE_BODY)
                .fontColor(this.theme.textSecondary)
                .margin({ bottom: 16 })
              Row() {
                Button('继续画')
                  .fontSize(14)
                  .layoutWeight(1)
                  .backgroundColor(this.theme.surfaceHover)
                  .fontColor(this.theme.textPrimary)
                  .margin({ right: 8 })
                  .onClick(() => {
                    this.exitConfirmVisible = false;
                  })
                Button('丢弃并退出')
                  .fontSize(14)
                  .layoutWeight(1)
                  .backgroundColor(this.theme.danger)
                  .fontColor(this.theme.textPrimary)
                  .onClick(() => {
                    this.exitConfirmVisible = false;
                    this.pathStack.pop();
                  })
              }
              .width('100%')
            }
            .width('85%')
            .padding(20)
            .borderRadius(RADIUS_NAV)
            .backgroundColor(this.theme.surfaceNode)
          }
          .width('100%')
          .height('100%')
          .alignContent(Alignment.Center)
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.bgApp)
    .onBackPressed(() => {
      return this.requestExit();
    })
  }
}
