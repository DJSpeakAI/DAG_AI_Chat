// ============================================================
// CodeBlockView.ets — 代码块组件（自动换行/横向滚动切换 + 语法高亮 + 划词五件套）
// ============================================================
// ★ 0.122 原生组件；★ 拆分自 ChatPage.ets（原文件内 struct）。
// - 语法高亮：Text 内 ForEach Span 按着色 token 渲染；token 顺序拼接与 content
//   完全一致，划词/全选/复制偏移不错位（keyGenerator 纳入内容长度防流式撞缓存）
// - 划词桥接：复用宿主页的选择工具栏状态链路（@Event 回调，this 归位正确）
//   ★ 0.157 崩溃修复教训：禁用 @BuilderParam 传父组件工具栏——@Builder 经
//   @BuilderParam 传入后在子组件上下文执行，this 不再指向宿主页 → 长按代码块
//   TypeError 崩溃（真机实证）。本组件自带工具栏 UI，按钮动作走 @Event。
// - 划词级书签：书签区间与语法 token 求交集拆分，marked 段紫色下划线（保留语法色）
import deviceInfo from '@ohos.deviceInfo';
import { AppTheme, connectAppTheme } from '../common/AppTheme';
import { RADIUS_CONTROL } from '../common/DesignTokens';
import { CodeToken, tokenizeCode } from '../utils/SyntaxHighlight';

// ★ 0.191.0：带书签标志的代码 token 渲染单元——书签区间与语法 token 求交集拆分，
// marked 段保留语法色 + 紫色下划线（划词级标记在代码块内的等效实现）
class MarkedToken {
  text: string;
  kind: number;
  marked: boolean;
  constructor(text: string, kind: number, marked: boolean) {
    this.text = text;
    this.kind = kind;
    this.marked = marked;
  }
}

@ComponentV2
export struct CodeBlockView {
  theme: AppTheme = connectAppTheme();
  @Param content: string = '';   // 代码内容
  @Param lang: string = '';      // ★ 0.149：语言标识（parseMarkdown 已提取；空 = plaintext 不高亮）
  @Param fontScale: number = 1.0; // ★ 0.214.0：字号缩放透传（父组件捏合；工具栏/标签等辅助元素不缩）
  @Local wrap: boolean = true;    // 默认开启自动换行
  @Event onZoom: (content: string, lang: string) => void =
    (content: string, lang: string) => {}; // ★ 0.153：放大回调（父组件打开全屏代码弹窗）；★ 0.149 加传 lang
  // ★ 0.156：划词桥接——代码块 Text 复用宿主页的选择工具栏（翻译/入知识库/复制/全选）与状态链路
  @Param textKey: string = '';                                    // 划词 key（父组件生成，如 `${msgId}|c${segIdx}`）
  @Param selController: TextController | undefined = undefined;   // 父组件注册的 TextController（关闭选择菜单用）
  @Param selectAllKey: string = '';                               // 全选受控态（`${key}|${nonce}`，命中时本块全选）
  // ★ 0.157：按钮动作经 @Event 回调父组件（this 归位正确）
  @Event onTranslate: () => void = () => {};       // 翻译按钮（父组件 onToolbarTranslate）
  @Event onAddKnowledge: () => void = () => {};    // 入知识库按钮（父组件 onToolbarAddKnowledge）
  @Event onCopy: () => void = () => {};            // 复制按钮（父组件 onToolbarCopy）
  @Event onSelectAll: () => void = () => {};       // 全选按钮（父组件 onToolbarSelectAll）
  @Event onMenuAppear: (key: string) => void = (key: string) => {}; // 菜单弹出（父组件记录 selKey）
  @Event onMenuDisappear: () => void = () => {};                    // 菜单关闭（父组件清理选中状态）
  @Event onSelChange: (key: string, content: string, start: number, end: number) => void =
    (key: string, content: string, start: number, end: number) => {}; // 选中变化（父组件按偏移截取选中文本）
  // ★ 0.191.0：划词级书签——父组件传入本块书签偏移（-1=无）与工具栏标记按钮状态
  @Param bmStart: number = -1;
  @Param bmEnd: number = -1;
  @Param bookmarkBtnLabel: string = '标记'; // 按钮文案（标记/取消标记，父组件按划选首字符判定）
  @Event onBookmark: () => void = () => {}; // 标记/取消标记按钮（父组件 onToolbarBookmark）

  /** ★ 0.281.0：设备三档判定（与 ChatPage.isPcDevice 同口径）——代码块划词菜单 PC 档走右键触发 */
  isPcDevice(): boolean {
    const t = deviceInfo.deviceType;
    return t !== 'phone' && t !== 'tablet' && t !== 'tv' && t !== 'car' && t !== 'wearable';
  }

  // ★ 0.149：着色 token 序列（@Computed 依赖 content/lang 自动重算；流式增量输出实时刷新高亮）
  // tokenizeCode 返回 null（语言不支持/超长兜底）时降级为单段全文本——渲染层只有一条 Span 拼接路径
  @Computed
  get renderTokens(): CodeToken[] {
    const tokens = tokenizeCode(this.content, this.lang);
    if (tokens === null) {
      return [new CodeToken(this.content, 0)];
    }
    return tokens;
  }

  // ★ 0.191.0：书签区间与语法 token 求交集拆分——marked 段渲染时加紫色下划线（保留语法色）
  // 偏移越界（书签过期/内容变化）时交集为空，自然降级为无标记渲染
  @Computed
  get markedTokens(): MarkedToken[] {
    const tokens = this.renderTokens;
    if (this.bmStart < 0 || this.bmEnd <= this.bmStart) {
      const plain: MarkedToken[] = [];
      for (const t of tokens) {
        plain.push(new MarkedToken(t.text, t.kind, false));
      }
      return plain;
    }
    const out: MarkedToken[] = [];
    let pos = 0;
    for (const t of tokens) {
      const tStart = pos;
      const tEnd = pos + t.text.length;
      pos = tEnd;
      if (tEnd <= this.bmStart || tStart >= this.bmEnd) {
        out.push(new MarkedToken(t.text, t.kind, false));
        continue;
      }
      if (tStart < this.bmStart) {
        out.push(new MarkedToken(t.text.substring(0, this.bmStart - tStart), t.kind, false));
      }
      const mStart = tStart > this.bmStart ? tStart : this.bmStart;
      const mEnd = tEnd < this.bmEnd ? tEnd : this.bmEnd;
      out.push(new MarkedToken(t.text.substring(mStart - tStart, mEnd - tStart), t.kind, true));
      if (tEnd > this.bmEnd) {
        out.push(new MarkedToken(t.text.substring(this.bmEnd - tStart), t.kind, false));
      }
    }
    return out;
  }

  // ★ 0.149：token 配色；★ 0.181.0 收敛 DesignTokens 语义常量（关键字蓝/字符串绿/注释灰/数字橙）
  tokenColor(kind: number): string {
    if (kind === 1) {
      return this.theme.codeKeyword; // 关键字：蓝
    }
    if (kind === 2) {
      return this.theme.codeString; // 字符串：绿
    }
    if (kind === 3) {
      return this.theme.codeComment; // 注释：灰
    }
    if (kind === 4) {
      return this.theme.codeNumber; // 数字：橙
    }
    return this.theme.codeText;   // 普通代码文本：底色对应文字色
  }

  // ★ 0.157：代码块专用选择工具栏——UI 与 ChatPage.SelectionToolbar 保持一致（样式改动两处同步），
  // 主题色用 DesignTokens 常量、按钮动作走 @Event，规避 @BuilderParam 的 this 上下文丢失
  @Builder
  codeToolbar() {
    Row() {
      Text('翻译')
        .fontSize(Math.round(14 * this.fontScale * 10) / 10)
        .fontColor(this.theme.brandSecondary)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.onTranslate();
        })
      Divider()
        .vertical(true)
        .height(16)
        .color(this.theme.strokeCard)
      Text('入知识库')
        .fontSize(Math.round(14 * this.fontScale * 10) / 10)
        .fontColor(this.theme.brandSecondary)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.onAddKnowledge();
        })
      Divider()
        .vertical(true)
        .height(16)
        .color(this.theme.strokeCard)
      // ★ 0.191.0：标记/取消标记（与主工具栏同位——复制左边；文案由父组件按划选首字符判定）
      Text(this.bookmarkBtnLabel)
        .fontSize(Math.round(14 * this.fontScale * 10) / 10)
        .fontColor(this.theme.textPrimary)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.onBookmark();
        })
      Divider()
        .vertical(true)
        .height(16)
        .color(this.theme.strokeCard)
      Text('复制')
        .fontSize(Math.round(14 * this.fontScale * 10) / 10)
        .fontColor(this.theme.textPrimary)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.onCopy();
        })
      Divider()
        .vertical(true)
        .height(16)
        .color(this.theme.strokeCard)
      Text('全选')
        .fontSize(Math.round(14 * this.fontScale * 10) / 10)
        .fontColor(this.theme.textPrimary)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.onSelectAll();
        })
    }
    .backgroundColor(this.theme.surfaceNode)
    .borderRadius(RADIUS_CONTROL)
    .border({ width: 0.5, color: this.theme.strokeCard })
    .shadow({ radius: 12, color: this.theme.shadowColorSoft, offsetX: 0, offsetY: 4 })
  }

  build() {
    Column() {
      // ★ 按钮栏：左对齐 + 小字体 + 醒目样式（0.122 优化；0.153 拆分为两个独立按钮：换行切换 + 放大）
      // ★ 0.191.0 定稿：换行/放大全换 svg 矢量图标（wrap/nowrap/zoom.svg 紫色 18×18）；
      //   Row({ space: 8 }) 间距统一（用户指示：图2 顶栏间距不统一重新排列）
      Row({ space: 8 }) {
        // ★ 0.149：语言标签（无语言标识的代码块标记为 plaintext，不高亮）
        Text(this.lang.length > 0 ? this.lang : 'plaintext')
          .fontSize(11)
          .fontColor(this.theme.textTertiary)

        // 换行切换按钮：换行模式 wrap.svg（下弯左箭头），滚动模式 nowrap.svg（双向箭头）
        // ★ 0.191.0 定稿：按钮样式=深紫底+方框+圆角；★ 缩小 20×18/图标14（用户指示大了不美观）
        Row() {
          Image(this.wrap ? $r('app.media.wrap') : $r('app.media.nowrap'))
            .width(14)
            .height(14)
        }
        .width(20)
        .height(18)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .borderRadius(4)
        .backgroundColor(this.theme.surfaceHover)
        .border({ width: 0.5, color: this.theme.strokeBrand })
        .onClick(() => {
          this.wrap = !this.wrap;
        })

        // ★ 0.153：放大按钮——打开全屏代码查看弹窗（父组件渲染）；zoom.svg=⤢ 对角双箭头矢量版；同款框样式
        Row() {
          Image($r('app.media.zoom'))
            .width(14)
            .height(14)
        }
        .width(20)
        .height(18)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .borderRadius(4)
        .backgroundColor(this.theme.surfaceHover)
        .border({ width: 0.5, color: this.theme.strokeBrand })
        .onClick(() => {
          this.onZoom(this.content, this.lang); // ★ 0.149：加传 lang（放大弹窗同步高亮）
        })
      }
      .margin({ top: 4, bottom: 2 })

      // 代码内容：根据 wrap 状态切换渲染模式
      if (this.wrap) {
        // ★ 0.154：去掉 width('100%')——气泡链多层自适应父容器下百分比宽度解析异常，
        // 导致代码块比气泡内容区宽、右侧显示被挡；改为无 width + 父约束折行
        //（与气泡内普通文本段同模式：长代码自动折行且始终在气泡内，短代码背景随内容自适应）
        // ★ 0.156：划词五件套——与普通文本段同模式（copyOption + 自研菜单 + 选中回调 + 全选受控）
        // ★ 0.149：语法高亮——Text 内 ForEach Span 按着色 token 渲染；token 顺序拼接与 content
        // 完全一致，划词/全选/复制偏移不错位；keyGenerator 纳入内容长度，流式更新触发 Span 重建
        Text('', { controller: this.selController }) {
          ForEach(this.markedTokens, (t: MarkedToken, i: number) => {
            Span(t.text)
              .fontColor(this.tokenColor(t.kind))
              // ★ 0.191.0：书签 marked 段紫色下划线（保留语法色）
              .decoration(t.marked ? { type: TextDecorationType.Underline, color: this.theme.brandSecondary } : { type: TextDecorationType.None })
          }, (t: MarkedToken, i: number) => `${i}|${t.kind}|${t.text.length}|${t.marked}`)
        }
          .fontSize(14)
          .fontFamily('monospace')
          .fontColor(this.theme.codeText)
          .padding(10)
          .backgroundColor(this.theme.bgCanvas)
          .borderRadius(RADIUS_CONTROL)
          .copyOption(CopyOptions.LocalDevice)
          .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE) // ★ 0.285.3：可获焦模式（华为二轮正解）——Text 默认 UNFOCUSABLE 划选后不获焦、系统 Ctrl+C 派发给错误组件；本模式点击/划选即入获焦链，系统默认复制直接生效
          .focusOnTouch(true) // ★ 0.285.4：拖选起手 press 即申请焦点——textSelectable 只给获焦能力、拖选本身不改焦点归属（华为 Q2），获焦后系统 Ctrl+C 才作用于其选区
          .bindSelectionMenu(TextSpanType.TEXT, this.codeToolbar, this.isPcDevice() ? TextResponseType.RIGHT_CLICK : TextResponseType.SELECT, {
            onAppear: () => {
              this.onMenuAppear(this.textKey);
            },
            onDisappear: () => {
              this.onMenuDisappear();
            }
          })
          .bindSelectionMenu(TextSpanType.TEXT, this.codeToolbar, TextResponseType.LONG_PRESS, {
            onAppear: () => {
              this.onMenuAppear(this.textKey);
            },
            onDisappear: () => {
              this.onMenuDisappear();
            }
          })
          .onTextSelectionChange((start: number, end: number) => {
            this.onSelChange(this.textKey, this.content, start, end);
          })
          .selection(
            this.selectAllKey.startsWith(`${this.textKey}|`) ? 0 : 1,
            this.selectAllKey.startsWith(`${this.textKey}|`) ? this.content.length : 0
          )
      } else {
        // 滚动模式：横向滚动查看长代码
        Scroll() {
          // ★ 0.156：划词五件套——同 wrap 模式（长按进入选择，拖动与横向滚动手势互不冲突）
          // ★ 0.149：语法高亮——同 wrap 模式 ForEach Span 着色渲染
          Text('', { controller: this.selController }) {
            ForEach(this.markedTokens, (t: MarkedToken, i: number) => {
              Span(t.text)
                .fontColor(this.tokenColor(t.kind))
                // ★ 0.191.0：书签 marked 段紫色下划线（保留语法色）
                .decoration(t.marked ? { type: TextDecorationType.Underline, color: this.theme.brandSecondary } : { type: TextDecorationType.None })
            }, (t: MarkedToken, i: number) => `${i}|${t.kind}|${t.text.length}|${t.marked}`)
          }
            .fontSize(14)
            .fontFamily('monospace')
            .fontColor(this.theme.codeText)
            .padding(10)
            .backgroundColor(this.theme.bgCanvas)
            .borderRadius(RADIUS_CONTROL)
            .copyOption(CopyOptions.LocalDevice)
            .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE) // ★ 0.285.3：可获焦模式（华为二轮正解）——Text 默认 UNFOCUSABLE 划选后不获焦、系统 Ctrl+C 派发给错误组件；本模式点击/划选即入获焦链，系统默认复制直接生效
            .focusOnTouch(true) // ★ 0.285.4：拖选起手 press 即申请焦点——textSelectable 只给获焦能力、拖选本身不改焦点归属（华为 Q2），获焦后系统 Ctrl+C 才作用于其选区
            .bindSelectionMenu(TextSpanType.TEXT, this.codeToolbar, this.isPcDevice() ? TextResponseType.RIGHT_CLICK : TextResponseType.SELECT, {
              onAppear: () => {
                this.onMenuAppear(this.textKey);
              },
              onDisappear: () => {
                this.onMenuDisappear();
              }
            })
            .bindSelectionMenu(TextSpanType.TEXT, this.codeToolbar, TextResponseType.LONG_PRESS, {
              onAppear: () => {
                this.onMenuAppear(this.textKey);
              },
              onDisappear: () => {
                this.onMenuDisappear();
              }
            })
            .onTextSelectionChange((start: number, end: number) => {
              this.onSelChange(this.textKey, this.content, start, end);
            })
            .selection(
              this.selectAllKey.startsWith(`${this.textKey}|`) ? 0 : 1,
              this.selectAllKey.startsWith(`${this.textKey}|`) ? this.content.length : 0
            )
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Auto)
        // ★ 0.154：width('100%') 改为约束 maxWidth——视口被钳制在气泡内容区内，
        // 长代码横向滚动正常、不再向右溢出气泡
        .constraintSize({ maxWidth: '100%' })
      }
    }
    .margin({ top: 6, bottom: 6 })
    .alignItems(HorizontalAlign.Start) // ★ 按钮左对齐（0.122 优化）
  }
}
