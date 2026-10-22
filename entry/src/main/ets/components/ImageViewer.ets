// ============================================================
// ImageViewer.ets — 全屏图片浏览器（★ 拆分自 ChatPage.ets）
// ============================================================
// ★ 0.246.0 曾升级缩放查看器（捏合/双击/滚轮/放大平移），★ 0.249.3 用户拍板整体回滚
// 回归 Swiper+× 原始形态；保留保存能力（PC 右键菜单 / 手机+Pad 触摸长按菜单）。
// ★ 0.249.3 修「触摸长按菜单跳不出来」：①缩放手势全删（手势竞争消失）
// ②draggable(false)（Image 默认可拖拽，系统拖拽识别器抢触摸长按）。
// 模式：AppStorageV2 共享 store（宿主页写 visible/images/index，组件 connect 渲染）；
// if 挂载制=每次打开新实例，@Local 菜单态天然重置（原 @Monitor 语义）。
import { AppTheme, connectAppTheme } from '../common/AppTheme';
import { RADIUS_CONTROL } from '../common/DesignTokens';
import { FONT_INTER } from '../common/DesignTokens';
import { ImageViewerStore, connectImageViewer } from '../common/ChatPageTypes';
import { buffer } from '@kit.ArkTS';
import { fileIo, picker } from '@kit.CoreFileKit';

@ComponentV2
export struct ImageViewer {
  theme: AppTheme = connectAppTheme();
  imgViewer: ImageViewerStore = connectImageViewer();
  @Local menuVisible: boolean = false; // ★ 0.247.1：触摸长按保存菜单开态（PC 右键走 bindContextMenu 原样）

  // ★ 0.246.0：保存当前查看图片（免权限走 DocumentViewPicker 系统保存对话框 + fileIo 写入；
  //   data URI 解 base64，file:// 沙箱路径直读；三端统一入口——PC 右键 / 触摸长按都进这一条链）
  async saveViewerImage(): Promise<void> {
    const src = this.imgViewer.images[this.imgViewer.index] ?? '';
    if (src.length === 0) {
      return;
    }
    try {
      let data: ArrayBuffer;
      if (src.startsWith('data:image')) {
        const b64 = src.substring(src.indexOf(',') + 1);
        data = buffer.from(b64, 'base64').buffer;
      } else {
        const file = fileIo.openSync(src, fileIo.OpenMode.READ_ONLY);
        const stat = fileIo.statSync(file.fd);
        data = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, data);
        fileIo.closeSync(file);
      }
      const opt = new picker.DocumentSaveOptions();
      opt.newFileNames = [`DAGAI_${Date.now()}.jpg`];
      const res = await new picker.DocumentViewPicker().save(opt);
      if (res.length > 0) {
        const out = fileIo.openSync(res[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
        fileIo.writeSync(out.fd, data);
        fileIo.closeSync(out);
        this.showToastSafe('图片已保存');
      }
    } catch (err) {
      this.showToastSafe('保存取消或失败');
    }
  }

  // toast 轻提示（showToast 可能抛异常，统一包裹消除编译告警，失败不影响主流程）
  showToastSafe(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (e) {
      // toast 失败静默忽略
    }
  }

  // ★ 0.247.1：查看器保存菜单卡（PC 右键 viewerSaveMenu / 触摸长按浮层同款）——深色卡+品牌紫竖条+白字
  //   +阴影，替换 0.246.0 素底紫字丑版（用户拍板「右击保存按钮很难看」）；点击保存并收起
  @Builder
  viewerMenuCard() {
    Row({ space: 8 }) {
      Column() {
        Blank()
      }
      .width(4)
      .height(18)
      .borderRadius(2)
      .backgroundColor(this.theme.brandPrimary)
      Text('保存图片')
        .fontSize(15)
        .fontColor(this.theme.textPrimary)
        .fontFamily(FONT_INTER)
    }
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 20, top: 12, bottom: 12 })
    .backgroundColor(this.theme.surfaceNode)
    .borderRadius(RADIUS_CONTROL)
    .border({ width: 1, color: this.theme.strokeCard })
    .shadow({ radius: 16, color: this.theme.shadowColor, offsetX: 0, offsetY: 4 })
    .onClick(() => {
      this.menuVisible = false;
      this.saveViewerImage();
    })
  }

  // ★ 0.247.1：查看器保存菜单（bindContextMenu RightClick——PC 右键触发；卡样式与触摸长按浮层同款）
  @Builder
  viewerSaveMenu() {
    this.viewerMenuCard()
  }

  build() {
    Stack() {
      Swiper() {
        ForEach(this.imgViewer.images, (url: string) => {
          Image(url)
            .objectFit(ImageFit.Contain)
            .width('100%')
            .height('100%')
            .draggable(false)
            .gesture(
              // ★ 0.247.1：触摸长按 500ms 弹保存菜单（手机/Pad）；★ 0.249.3 缩放回滚后无手势竞争
              LongPressGesture({ duration: 500 })
                .onAction(() => {
                  this.menuVisible = true;
                })
            )
            .gesture(
              // ★ 0.249.3：单击即关（双击缩放已回滚，无需 320ms 延迟判定）；菜单开着=先收菜单
              TapGesture({ count: 1 })
                .onAction(() => {
                  if (this.menuVisible) {
                    this.menuVisible = false; // 菜单开着点图=收菜单，不关查看器
                    return;
                  }
                  this.imgViewer.visible = false;
                })
            )
            .bindContextMenu(this.viewerSaveMenu, ResponseType.RightClick)
        }, (url: string) => url)
      }
      .index(this.imgViewer.index)
      .indicator(true)
      .backgroundColor(Color.Black)

      Button('×')
        .fontSize(24)
        .fontColor(this.theme.textPrimary)
        .backgroundColor(Color.Transparent)
        .position({ x: 20, y: 20 })
        .onClick(() => {
          this.imgViewer.visible = false;
        })

      // ★ 0.247.1：触摸长按菜单浮层（与 PC 右键 viewerSaveMenu 同款卡）——底部居中弹出，点外收起
      if (this.menuVisible) {
        Column() {
          Column() {
            Blank()
          }
          .width('100%')
          .layoutWeight(1)
          this.viewerMenuCard()
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: 140 })
        .onClick(() => {
          this.menuVisible = false;
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .onClick(() => {
      this.imgViewer.visible = false;
    })
    // ★ 新增：右滑手势关闭图片预览（0.120）
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal })
        .onActionEnd((event: PanGestureEvent) => {
          if (event.offsetX > 30) { // 右滑超过30vp关闭预览
            this.imgViewer.visible = false;
          }
        })
    )
  }
}
