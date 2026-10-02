// ============================================================
// AnnotationPage.ets — 屏幕圈选标注页（★ 0.152）
// ============================================================
// 本页面是内置屏幕标注能力的涂鸦标注界面，功能包括：
//   - 显示 ChatPage 截取的当前屏幕画面（base64 → PixelMap → Canvas 底图）
//   - 画笔涂鸦圈选（单指拖动画线，圆头粗线红色笔触）
//   - 撤销上一笔 / 清空画布（全量重绘：底图 + 笔画栈）
//   - 标注完成三种操作（需求 0.119 第三章）：
//       ① 当前对话导入 —— 合成图写入结果 store，pop 回 ChatPage 挂到输入区
//       ② 创建子气泡分支 —— 结果 store 标记 branch，ChatPage 调现有 addBubble
//          （继承父节点完整上下文，10+15 规则不变，底层消息链路零改动）
//       ③ 存入知识库 —— 结果 store 标记 knowledge，ChatPage 打开卡片编辑弹窗
//          并发起多模态 AI 提炼（queryKnowledgeFromImage）
//   - 有涂鸦时返回需二次确认（防误触丢弃劳动成果，与 0.150 删除确认同理念）
//   - 深浅色主题适配
//
// 图片策略：截图与导出均为 base64 data URI（与相册图片消息、知识卡片配图
// 同模式）——不写系统相册、不产生临时文件，随消息/卡片生命周期存续。
//
// 技术栈：鸿蒙 ArkUI V2（@ComponentV2 / @Local / @Param）
// 导航模式：NavPathStack（从 ChatPage push 进入，pop 返回）
// ============================================================

import { AppStorageV2 } from '@kit.ArkUI';
import { image } from '@kit.ImageKit'; // 截图 base64 解码 → PixelMap（Canvas drawImage 底图）
import { buffer } from '@kit.ArkTS';   // base64 ↔ ArrayBuffer
import { AnnotationDraftStore, AnnotationResultStore, connectAnnotationDraft, connectAnnotationResult } from '../common/AnnotationModel'; // ★ 0.152：截图草稿 + 结果回传
import { ThemeStore } from '../entryability/EntryAbility'; // 深浅色主题（项目统一模式）

// 一笔涂鸦中的一个采样点（Canvas 本地坐标，单位 vp）
class StrokePoint {
  x: number;
  y: number;

  constructor(x: number, y: number) {
    this.x = x;
    this.y = y;
  }
}

// 画笔参数（红色圆头粗线——浅色/深色截图上都醒目）
const PEN_COLOR = '#F44336';
const PEN_WIDTH = 4;

@ComponentV2
export struct AnnotationPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  draft: AnnotationDraftStore = connectAnnotationDraft();     // ChatPage 写入的截图
  result: AnnotationResultStore = connectAnnotationResult();  // 标注结果回传
  // 画布尺寸（vp，等比 fit 到可用区域后固定；0 = 尚未就绪，Canvas 不渲染）
  @Local canvasW: number = 0;
  @Local canvasH: number = 0;
  // 笔画栈（整体替换触发刷新；length 同时驱动撤销按钮可用性与返回确认判断）
  @Local strokes: StrokePoint[][] = [];
  // 解码失败提示（空草稿/解码异常时显示错误态 + 返回按钮）
  @Local loadError: string = '';
  // 返回二次确认弹窗（有涂鸦时返回需确认，防误触丢弃）
  @Local exitConfirmVisible: boolean = false;

  private ctx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true)); // 抗锯齿
  private pixelMap: image.PixelMap | null = null; // 解码后的截图底图
  private imgW: number = 0; // 截图像素宽（等比计算用）
  private imgH: number = 0;
  private availW: number = 0; // 画布可用区域（vp，onAreaChange 记录）
  private availH: number = 0;
  private fitted: boolean = false; // 画布尺寸只 fit 一次（页面内尺寸不再变化）
  private currentStroke: StrokePoint[] = []; // 正在绘制的一笔（Up 时并入 strokes）

  // ★ 获取 ThemeStore（通过 AppStorageV2 共享，项目统一模式）
  getThemeStore(): ThemeStore {
    return AppStorageV2.connect(ThemeStore, 'theme-store', () => new ThemeStore()) as ThemeStore;
  }

  aboutToAppear() {
    if (this.draft.imageUri.length === 0) {
      // 防御：无截图草稿（异常进入）——显示错误态
      this.loadError = '未获取到屏幕截图，请返回重试';
      return;
    }
    this.decodeDraft();
  }

  // 解码截图草稿：base64 → PixelMap + 记录原始尺寸，就绪后尝试 fit 画布
  async decodeDraft(): Promise<void> {
    try {
      const bytes = buffer.from(this.draft.imageUri.split(',')[1], 'base64');
      const source = image.createImageSource(bytes.buffer);
      const pm = await source.createPixelMap();
      const info = await pm.getImageInfo();
      await source.release(); // 源已解码完，释放（PixelMap 保留供 drawImage）
      this.pixelMap = pm;
      this.imgW = info.size.width;
      this.imgH = info.size.height;
      this.tryFitCanvas();
    } catch (e) {
      console.error(`[0.152] AnnotationPage 解码截图失败: ${JSON.stringify(e)}`);
      this.loadError = '截图解码失败，请返回重试';
    }
  }

  // 画布可用区域就绪（onAreaChange）——记录尺寸并尝试 fit
  onCanvasAreaChange(w: number, h: number): void {
    if (this.availW === 0 && w > 0) {
      this.availW = w;
      this.availH = h;
      this.tryFitCanvas();
    }
  }

  // 双就绪（截图尺寸 + 可用区域）后等比计算画布尺寸——只算一次：
  // 画布 = 截图等比缩放（无 Contain 留白边），导出即所见即所得
  tryFitCanvas(): void {
    if (this.fitted || this.imgW <= 0 || this.imgH <= 0 || this.availW <= 0 || this.availH <= 0) {
      return;
    }
    this.fitted = true;
    const scale = Math.min(this.availW / this.imgW, this.availH / this.imgH);
    this.canvasW = Math.floor(this.imgW * scale);
    this.canvasH = Math.floor(this.imgH * scale);
    // canvasW/H 赋值 → build 重跑 → Canvas 尺寸生效 → onReady 触发 → 绘制底图
  }

  // Canvas 就绪：绘制截图底图（等比铺满画布）
  drawBaseImage(): void {
    if (this.pixelMap === null || this.canvasW <= 0 || this.canvasH <= 0) {
      return;
    }
    this.ctx.clearRect(0, 0, this.canvasW, this.canvasH);
    this.ctx.drawImage(this.pixelMap, 0, 0, this.canvasW, this.canvasH);
  }

  // 全量重绘：底图 + 笔画栈（撤销/清空后调用）
  fullRedraw(): void {
    this.drawBaseImage();
    this.redrawAllStrokes();
  }

  // 重绘全部已提交笔画
  redrawAllStrokes(): void {
    this.ctx.strokeStyle = PEN_COLOR;
    this.ctx.lineWidth = PEN_WIDTH;
    this.ctx.lineCap = 'round'; // CanvasLineCap 字面量（round = 圆头，笔画衔接自然）
    this.ctx.lineJoin = 'round'; // CanvasLineJoin 字面量（round = 圆角拐点）
    for (let i = 0; i < this.strokes.length; i++) {
      this.drawStrokePath(this.strokes[i]);
    }
  }

  // 沿点序列描一条笔画路径
  drawStrokePath(points: StrokePoint[]): void {
    if (points.length === 1) {
      // 单点（轻点一下）：画一个笔宽圆点
      this.ctx.beginPath();
      this.ctx.fillStyle = PEN_COLOR;
      this.ctx.arc(points[0].x, points[0].y, PEN_WIDTH / 2, 0, Math.PI * 2);
      this.ctx.fill();
      return;
    }
    this.ctx.beginPath();
    this.ctx.moveTo(points[0].x, points[0].y);
    for (let i = 1; i < points.length; i++) {
      this.ctx.lineTo(points[i].x, points[i].y);
    }
    this.ctx.stroke();
  }

  // 画布触摸：Down 落笔 → Move 增量描线（只画上一段，不整笔重绘）→ Up 收笔入栈
  onCanvasTouch(event: TouchEvent): void {
    if (this.canvasW <= 0) {
      return; // 画布未就绪不响应
    }
    const pt = event.touches[0];
    if (event.type === TouchType.Down) {
      this.currentStroke = [new StrokePoint(pt.x, pt.y)];
      // 落笔即画一个圆点（单击也能留痕）
      this.ctx.beginPath();
      this.ctx.fillStyle = PEN_COLOR;
      this.ctx.arc(pt.x, pt.y, PEN_WIDTH / 2, 0, Math.PI * 2);
      this.ctx.fill();
    } else if (event.type === TouchType.Move) {
      const prev = this.currentStroke[this.currentStroke.length - 1];
      this.currentStroke.push(new StrokePoint(pt.x, pt.y));
      // 增量描线：只画 prev → cur 这一段（实时跟手）
      this.ctx.strokeStyle = PEN_COLOR;
      this.ctx.lineWidth = PEN_WIDTH;
      this.ctx.lineCap = 'round'; // CanvasLineCap 字面量
      this.ctx.lineJoin = 'round'; // CanvasLineJoin 字面量
      this.ctx.beginPath();
      this.ctx.moveTo(prev.x, prev.y);
      this.ctx.lineTo(pt.x, pt.y);
      this.ctx.stroke();
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.currentStroke.length > 0) {
        // 整体替换触发 @Local 刷新（撤销按钮可用性 / 返回确认判断同步更新）
        this.strokes = [...this.strokes, this.currentStroke];
        this.currentStroke = [];
      }
    }
  }

  // 撤销上一笔：弹出末笔后全量重绘（底图 + 剩余笔画）
  undoStroke(): void {
    if (this.strokes.length === 0) {
      return;
    }
    this.strokes = this.strokes.slice(0, this.strokes.length - 1);
    this.fullRedraw();
  }

  // 清空画布：笔画栈清空后重绘底图
  clearAllStrokes(): void {
    if (this.strokes.length === 0) {
      return;
    }
    this.strokes = [];
    this.fullRedraw();
  }

  // 导出合成图（底图 + 涂鸦，JPEG 90 与相册图片压缩档一致）并携带动作 pop 回 ChatPage
  exportAndReturn(action: string): void {
    if (this.canvasW <= 0) {
      return; // 画布未就绪（解码中）防御
    }
    const dataUri = this.ctx.toDataURL('image/jpeg', 0.9); // data:image/jpeg;base64,...
    this.result.action = action;
    this.result.imageUri = dataUri;
    this.pathStack.pop();
  }

  // 返回入口：有涂鸦时弹二次确认（防误触丢弃），无涂鸦直接返回
  requestExit(): boolean {
    if (this.strokes.length > 0) {
      this.exitConfirmVisible = true;
      return true; // 消费返回事件（弹窗接管）
    }
    this.pathStack.pop();
    return true;
  }

  build() {
    NavDestination() {
      Column() {
        // ── 顶栏：返回 | 标题 | 撤销 / 清空（自绘行，项目统一模式） ──
        Row() {
          Button('←')
            .fontSize(18)
            .backgroundColor(Color.Transparent)
            .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
            .padding({ left: 4, right: 4 })
            .margin({ right: 4 })
            .onClick(() => {
              this.requestExit();
            })
          Text('屏幕标注')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
          Blank()
            .layoutWeight(1)
          // 撤销（无笔画时禁用）
          Text('↩ 撤销')
            .fontSize(13)
            .fontColor(this.strokes.length > 0
              ? (this.getThemeStore().isDark ? '#7AB8FF' : '#1976D2')
              : (this.getThemeStore().isDark ? '#555555' : '#BBBBBB'))
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .onClick(() => {
              this.undoStroke();
            })
          // 清空（无笔画时禁用）
          Text('🗑 清空')
            .fontSize(13)
            .fontColor(this.strokes.length > 0
              ? '#F44336'
              : (this.getThemeStore().isDark ? '#555555' : '#BBBBBB'))
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .margin({ left: 4 })
            .onClick(() => {
              this.clearAllStrokes();
            })
        }
        .width('100%')
        .padding({ left: 8, right: 12, top: 8, bottom: 4 })

        // ── 画布区：截图等比画布（居中），触摸涂鸦 ──
        if (this.loadError.length > 0) {
          Column() {
            Text(this.loadError)
              .fontSize(14)
              .fontColor('#F44336')
              .textAlign(TextAlign.Center)
            Button('返回')
              .fontSize(14)
              .margin({ top: 16 })
              .onClick(() => {
                this.pathStack.pop();
              })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Stack() {
            if (this.canvasW > 0 && this.canvasH > 0) {
              Canvas(this.ctx)
                .width(this.canvasW)
                .height(this.canvasH)
                .borderRadius(8)
                .border({ width: 1, color: this.getThemeStore().isDark ? '#555555' : '#DDDDDD' })
                .onReady(() => {
                  this.drawBaseImage(); // 画布就绪：绘制截图底图
                })
                .onTouch((event: TouchEvent) => {
                  this.onCanvasTouch(event); // 画笔涂鸦
                })
            } else {
              // 截图解码中
              Column() {
                Text('截图处理中...')
                  .fontSize(14)
                  .fontColor(this.getThemeStore().isDark ? '#999999' : '#666666')
              }
              .justifyContent(FlexAlign.Center)
            }
          }
          .width('100%')
          .layoutWeight(1)
          .alignContent(Alignment.Center)
          .onAreaChange((oldArea: Area, newArea: Area) => {
            // Area.width/height 是 Length 联合类型，Number() 归一为 vp 数值
            this.onCanvasAreaChange(Number(newArea.width), Number(newArea.height));
          })
        }

        // ── 底部操作区：三种操作（需求 0.119 第三章原文语义） ──
        Row() {
          Button('当前对话导入')
            .fontSize(13)
            .layoutWeight(1)
            .backgroundColor('#1976D2')
            .fontColor('#FFFFFF')
            .enabled(this.canvasW > 0)
            .onClick(() => {
              this.exportAndReturn('import');
            })
          Button('创建子气泡')
            .fontSize(13)
            .layoutWeight(1)
            .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#F5F5F5')
            .fontColor(this.getThemeStore().isDark ? '#E0E0E0' : '#333333')
            .margin({ left: 8 })
            .enabled(this.canvasW > 0)
            .onClick(() => {
              this.exportAndReturn('branch');
            })
          Button('存入知识库')
            .fontSize(13)
            .layoutWeight(1)
            .backgroundColor(this.getThemeStore().isDark ? '#1E3A5F' : '#E3F2FD')
            .fontColor(this.getThemeStore().isDark ? '#7AB8FF' : '#1976D2')
            .margin({ left: 8 })
            .enabled(this.canvasW > 0)
            .onClick(() => {
              this.exportAndReturn('knowledge');
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getThemeStore().isDark ? '#1A1A1A' : '#FAFAFA')

      // ── 返回二次确认弹窗（有涂鸦时防误触丢弃） ──
      if (this.exitConfirmVisible) {
        Stack() {
          // 遮罩：不关闭弹窗（防误触，与知识编辑弹窗同理念）
          Column() {
            Blank()
          }
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.4)')

          Column() {
            Text('丢弃涂鸦内容？')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getThemeStore().isDark ? '#FFFFFF' : '#333333')
              .margin({ bottom: 8 })
            Text('标注尚未导入使用，退出将丢弃当前涂鸦')
              .fontSize(13)
              .fontColor(this.getThemeStore().isDark ? '#999999' : '#666666')
              .margin({ bottom: 16 })
            Row() {
              Button('继续标注')
                .fontSize(14)
                .layoutWeight(1)
                .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#F5F5F5')
                .fontColor(this.getThemeStore().isDark ? '#E0E0E0' : '#333333')
                .margin({ right: 8 })
                .onClick(() => {
                  this.exitConfirmVisible = false;
                })
              Button('丢弃并退出')
                .fontSize(14)
                .layoutWeight(1)
                .backgroundColor('#F44336')
                .fontColor('#FFFFFF')
                .onClick(() => {
                  this.exitConfirmVisible = false;
                  this.pathStack.pop();
                })
            }
            .width('100%')
          }
          .width('85%')
          .padding(20)
          .borderRadius(12)
          .backgroundColor(this.getThemeStore().isDark ? '#2C2C2C' : '#FFFFFF')
        }
        .width('100%')
        .height('100%')
        .alignContent(Alignment.Center)
      }
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      return this.requestExit(); // 有涂鸦时拦截返回弹确认，无涂鸦直接返回
    })
  }
}
