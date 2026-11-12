# TTyStatusBar

## 1. 概述

`TTyStatusBar` 是 TyControls 库中的主题化状态栏控件，继承自 `TTyCustomControl`。它是一条通常停靠在窗体底部的多面板信息条：默认 `Align = alBottom`，横向排布若干 `TTyStatusPanel` 面板（各有自己的文本、宽度、对齐方式），右下角可绘制一个尺寸手柄（SizeGrip）。也可切换到 `SimplePanel` 单一整条文本模式。典型用途：显示"就绪"提示、行列号、点击计数、右侧品牌 / 时间等状态信息。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.StatusBar` |
| `GetStyleTypeKey` 返回值 | `'TyStatusBar'` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸 | 200 × 22（逻辑像素，构造时设置；实际使用中一般由 `alBottom` 停靠拉伸宽度） |

在 `.tycss` 文件中，该控件对应的选择器前缀为 `TyStatusBar`。

```pascal
uses tyControls.StatusBar;
```

> 面板项类型 `TTyStatusPanel`、集合类型 `TTyStatusPanels`（`TOwnedCollection` 子类）也定义在同一单元内。

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Panels` | `TTyStatusPanels` | `[]`（空集合） | 面板集合；写入时对内部集合执行 `Assign`。每个面板是一个 `TTyStatusPanel`（见下表）。任何面板属性变化都会重绘状态栏。 |
| `SimplePanel` | `Boolean` | `False` | 为 `True` 时切换到单一整条文本模式：忽略 `Panels`，改为绘制 `SimpleText`（左对齐、垂直居中）。 |
| `SimpleText` | `TCaption` | `''` | `SimplePanel = True` 时显示的整条文本。写入时仅当当前处于 `SimplePanel` 模式才触发重绘。 |
| `SizeGrip` | `Boolean` | `True` | 为 `True` 时在控件右下角绘制 3 个对角小点组成的尺寸手柄（`default True`），拖它或拖状态栏底边调整窗口大小。只在窗口可调整大小、没有最大化、而且状态栏正好贴着窗口底边（手柄还要贴着角）时才画、才拖得动；`False` 时状态栏上哪里都不调整窗口。 |
| `AutoHint` | `Boolean` | `False` | 为 `True` 时把应用程序当前提示（`Application.Hint`）显示到状态栏：`SimplePanel` 模式写入 `SimpleText`，否则写入 `Panels[0].Text`。这正是"鼠标划过工具按钮 / 高亮菜单项，下面这条读出说明"的经典状态行；主题化菜单已经会把菜单项 `Hint` 发布到 `Application.Hint`，此前库内没有任何控件接收它。与 LCL `TStatusBar.AutoHint` 同名同义，默认同为 `False`（打开会接管 `SimpleText` / 0 号面板）。 |
| `Align` | `TAlign` | `alBottom` | 停靠方式，**默认已重声明为 `alBottom`**（`property Align default alBottom;`），构造函数也显式设为 `alBottom`。 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点。 |

### `TTyStatusPanel`（`Panels` 集合项）的 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Text` | `string` | `''` | 该面板显示的文本。 |
| `Width` | `Integer` | `50` | 面板逻辑宽度（`default 50`）。**`Width <= 0` 的面板为"填充面板"**：占据其余固定宽度面板之外的全部剩余空间；若有多个 `<= 0` 面板，只有**第一个**吃掉剩余空间，其后的 `<= 0` 面板宽度为 0。**最后一个面板的 `Width` 只是下限**：它总是延伸到右侧内边距处（见 §7）。 |
| `Alignment` | `TAlignment` | `taLeftJustify` | 面板内文本的水平对齐（`taLeftJustify` / `taCenter` / `taRightJustify`，`default taLeftJustify`）。垂直方向固定居中。 |
| `Style` | `TTyStatusPanelStyle` | `psText` | `psText` 按主题样式绘制本面板的 `Text`；`psOwnerDraw` 把这一格交给应用：状态栏照常绘制背景与分隔线，但**不画任何文本**，改为触发 `OnDrawPanel`。要在格子里画图标、彩色状态点这类内容就用它。枚举名取自 LCL `TStatusPanelStyle`（`comctrls.pp:45`），从 `TStatusBar` 窗体里搬过来的 `Style := psOwnerDraw` 可原样编译。 |
| `Control` | `TControl` | `nil` | 放在这个面板里的控件：文字旁边的转圈指示器、小按钮、进度条都可以。赋值后它成为状态栏的子控件，状态栏从此把它摆在面板格子里：贴着格子的前导边（从右到左时是右边），垂直居中，保持它自己的尺寸，格子放不下时才缩小。`psText` 面板的文字从控件后面开始（间距由 `--statusbar-control-gap` 决定），`Alignment` 在剩下的空间里照常生效；控件隐藏时不占位置。一个控件只能属于一个面板；控件被释放或被移到别的父控件上，面板的这个属性自动清空。详见 §7。 |

> `TTyStatusPanels` 额外提供 `function Add: TTyStatusPanel;` 与默认索引器 `Items[AIndex]: TTyStatusPanel`（即 `Panels[i]`）以便按类型访问面板项。

### 公开方法

| 方法 | 说明 |
|------|------|
| `function PanelAtPos(X, Y: Integer): Integer` | 客户区坐标落在哪个面板上；不在任何面板上或处于 `SimplePanel` 模式时返回 `-1`。LCL 的同名写法 `GetPanelIndexAt(X, Y)` 是它的别名。 |
| `function PanelRect(AIndex: Integer): TRect` | 第 `AIndex` 个面板的格子，客户区坐标，和绘制、`PanelAtPos` 用的是同一份布局，从右到左时跟着镜像。索引无效或处于 `SimplePanel` 模式时返回空矩形。要在面板上方弹出菜单、给面板对齐别的东西，用它，不必自己照着内边距重算。 |
| `function PanelTextRect(AIndex: Integer): TRect` | 面板文字所在的矩形：格子去掉两侧的文字内缩，再去掉 `Control` 占掉的那一段。自绘面板往这里画，就不会压到面板里的控件。 |
| `function PanelTextStyle: TTyStyleSet` | 状态栏画面板文字用的已解析样式，里面有文字颜色（`TextColor`）、字体名（`FontName`）和字重（`FontWeight`）。`OnDrawPanel` 的处理器用它，画出来的颜色和字体就和其他面板一致，也跟着主题走。 |
| `function PanelFontSize: Integer` | 面板文字的字号，直接传给 `TTyPainter` 的文字方法（`DrawText`、`MeasureText` 的字号参数）。 |
| `function PanelFontHeightPx: Integer` | 同一个字号换算成当前 PPI 下的字体像素高度，用来把图标或图片配成和文字一样大。 |
| `procedure DrawPanelText(APainter: TTyPainter; const ARect: TRect; const AText: string; AAlignment: TAlignment = taLeftJustify)` | 在 `ARect` 里画一段文字，画法和 `psText` 面板画自己的 `Text` 完全一样：同样的颜色和字体，垂直居中，按阅读方向对齐，放不下时加省略号。在 `OnDrawPanel` 里用事件给的 `APainter` 调用；`ARect` 传 `PanelTextRect(APanel.Index)` 就和文字面板逐像素一致。 |

### 继承的通用成员

TTyStatusBar 继承自 `TTyCustomControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分 |
| `Controller` | `TTyCustomStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器 |

> **无独立的交互状态跟踪字段：** `TTyStatusBar` 未声明自己的 `FHover` / `FPressed` 等字段，也**未重写** `CurrentStates`；绘制仅读取 `CurrentStyle`（普通态样式）。状态栏是信息展示控件，不响应悬停 / 焦点等交互态视觉变化。

---

## 4. 事件

| 事件 | 签名 | 说明 |
|------|------|------|
| `OnHint` | `TNotifyEvent` | `AutoHint = True` 时，状态栏收到应用提示后**先**触发本事件。它是**接管**而非通知：一旦赋值，状态栏自己就不再写 `SimpleText` / `Panels[0]`，由处理器决定提示放到哪、怎么排版（例如"就绪 — <hint>"放进 2 号面板）。文本从 `Application.Hint` 读。语义与 LCL `TStatusBar.OnHint`（`statusbar.inc:70-88`）一致。 |
| `OnDrawPanel` | `TTyDrawPanelEvent = procedure(AStatusBar: TTyCustomStatusBar; APanel: TTyStatusPanel; APainter: TTyPainter; const ARect: TRect) of object` | 为每个 `Style = psOwnerDraw` 的面板触发一次，`ARect` 是该格在状态栏绘制坐标系里的设备像素矩形。**必须通过 `APainter` 绘制，不要用状态栏的 `Canvas`**：`TTyPainter` 画进 BGRA 图层，`EndPaint` 才合成到画布上，先画到 `Canvas` 的内容会被整个覆盖。这与 `TTyPaintPanel.OnPaintSurface` 是同一套约定；LCL 的 `TDrawPanelEvent` 只给矩形、要求处理器自己去取 `StatusBar.Canvas`，在自绘管线下不成立。 |

| `OnPanelClick` | `TTyPanelClickEvent = procedure(Sender: TObject; APanel: TTyStatusPanel) of object` | 鼠标左键在同一个面板上按下并松开时触发，`APanel` 是被点的面板，序号是 `APanel.Index`。按下后拖到别的面板再松开不算点击。以下几种情况不触发：按在尺寸手柄或底边调整窗口大小的那一条上；点在面板里的子控件上（那次点击归子控件，要响应就接它自己的 `OnClick`）；`SimplePanel` 模式。`OnClick` 照旧触发，两者互不影响；一次点击里的先后是 `OnClick`、`OnMouseUp`、`OnPanelClick`，所以在处理器里弹菜单或对话框时，这次松开已经处理完了。 |

> 除以上自有事件外，`TTyStatusBar` 暴露**基线事件集**（Tier A 鼠标 / 通用事件 + Tier B 键盘 / 焦点事件，因其为可聚焦的 `TTyCustomControl`）。完整基线清单见 [../events.md](../events.md)。

---

## 5. 状态与主题

### 支持的伪类状态

`TTyStatusBar` 绘制时只解析 `CurrentStyle`（普通态），**不区分** `:hover` / `:focus` / `:active` 的差异化外观；内置主题也未为其定义任何伪类规则。`:disabled`（`Enabled = False`）等仍由基类的通用状态机计算，但状态栏本身无交互态视觉切换。

### light.tycss 内置规则摘要

```css
TyStatusBar {
  background: var(--chrome-bar-bg);   /* 缺省 = var(--surface-chrome);皮肤定这一个令牌即可让三条 bar 齐平 */
  color: var(--on-surface);
  border-color: var(--border);
  border-width: var(--input-border-width);
  font-size: var(--font-size-base);
  font-weight: var(--font-weight-normal);
}
```

内置主题未为 `TyStatusBar` 定义命名变体（`.class`）或伪类规则；可通过 `StyleClass` 添加自定义变体。

### 度量令牌

| 令牌 | 默认值 | 说明 |
|------|--------|------|
| `--statusbar-control-gap` | `4px` | 面板里的控件（`TTyStatusPanel.Control`）和面板文字之间的间距。写在主题的 `:root` 里对所有状态栏生效；只调一个状态栏，写进它的 `StyleOverride`（如 `--statusbar-control-gap: 8px`）。 |

**渲染细节：**

- **背景与顶部边线：** 先铺一层 `FillSharpBackdrop`（让 alpha 背景可透出窗体照片，形成玻璃感；纯色 / 非图片主题无影响），再用 `background` 令牌整条填充，然后在**顶部**画一条 `border-color` 的 1px 细线（`border-width` 缩放，最小 1px）——是"状态栏顶线"外观，**不是完整边框**。
- **多面板模式：** 面板矩形由 `TyStatusPanelRects` 依据各面板 `Width` 计算（左右各留 6 逻辑像素内边距 `CStatusBarPadX`）；**最后一个面板的右边界一律拉到 `总宽 - 内边距`**（见 §7）。算好的格子可以用 `PanelRect(i)` 取到。第一个之后的每个面板左侧画一条 1px 分隔线（仅当主题存在 `border-color` 时；上下各内缩 3 逻辑像素）。面板文字用 `color`（`TextColor`）绘制，水平按各面板 `Alignment`、垂直居中，左右各再内缩 2 逻辑像素；面板里有控件时，文字从控件后面开始（`PanelTextRect(i)`）。
- **SimplePanel 模式：** 忽略面板，直接在 `[padX, W-padX]` 区域绘制 `SimpleText`，左对齐、垂直居中。
- **SizeGrip：** `SizeGrip = True` 时在右下角用 `TextColor` 画 3 个对角排列的 2×2 小点（间距 4 逻辑像素）。

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.StatusBar;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

var
  Bar: TTyStatusBar;
  P: TTyStatusPanel;
begin
  Bar := TTyStatusBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alBottom;      // 默认已是 alBottom
  Bar.Height := 24;
  Bar.SizeGrip := True;       // 右下角尺寸手柄

  // 面板 0：状态（填充面板，Width <= 0 撑满剩余空间）
  P := Bar.Panels.Add;
  P.Text := '就绪';
  P.Width := 0;
  P.Alignment := taLeftJustify;

  // 面板 1：点击计数（居中，固定宽）
  P := Bar.Panels.Add;
  P.Text := '点击：0';
  P.Width := 110;
  P.Alignment := taCenter;

  // 面板 2：右对齐品牌（固定宽）
  P := Bar.Panels.Add;
  P.Text := 'TyControls';
  P.Width := 110;
  P.Alignment := taRightJustify;
end;

// 运行时更新某个面板文本（自动重绘）
Bar.Panels[1].Text := '点击：3';

// 切换到单一整条文本模式
Bar.SimplePanel := True;
Bar.SimpleText := '正在保存…';
```

### 可点击的面板、面板里的控件

```pascal
// 面板 1 的文字前面放一个转圈指示器；状态栏负责摆放，面板变宽变窄它都跟着
Spinner := TTyActivityIndicator.Create(Self);
Spinner.SetBounds(0, 0, 16, 16);
Bar.Panels[1].Control := Spinner;      // 从此是状态栏的子控件
Spinner.Visible := False;              // 隐藏时不占位置，文字回到格子开头

Bar.OnPanelClick := @BarPanelClick;

procedure TForm1.BarPanelClick(Sender: TObject; APanel: TTyStatusPanel);
var
  r: TRect;
begin
  case APanel.Index of
    1: ShowBuildOutput;
    2: begin
         // 在被点的面板正上方弹出菜单：PanelRect 给的就是它的格子
         r := Bar.PanelRect(APanel.Index);
         with Bar.ClientToScreen(Point(r.Left, r.Top)) do
           EncodingMenu.Popup(X, Y);
       end;
  end;
end;
```

### 自绘面板用状态栏自己的颜色和字体

```pascal
// Bar.Panels[2].Style := psOwnerDraw;  Bar.OnDrawPanel := @BarDrawPanel;
procedure TForm1.BarDrawPanel(AStatusBar: TTyCustomStatusBar; APanel: TTyStatusPanel;
  APainter: TTyPainter; const ARect: TRect);
var
  S: TTyStyleSet;
  r: TRect;
  dot: TTyFill;
  d: Integer;
begin
  S := AStatusBar.PanelTextStyle;                 // 其他面板用的颜色、字体
  r := AStatusBar.PanelTextRect(APanel.Index);    // 文字该在的位置
  // 先画一个和文字一样高的状态点，颜色跟着主题
  d := AStatusBar.PanelFontHeightPx div 2;
  dot := Default(TTyFill);
  dot.Kind := tfkSolid;
  dot.Color := S.TextColor;
  APainter.FillBackground(Bounds(r.Left, (r.Top + r.Bottom - d) div 2, d, d), dot, 0);
  // 再让状态栏照文字面板的画法把文字画上
  r.Left := r.Left + d + APainter.Scale(4);
  AStatusBar.DrawPanelText(APainter, r, '3 个问题', APanel.Alignment);
end;
```

---

## 7. 注意事项

- **默认停靠底部：** `Align` 默认值即 `alBottom`（既在 published 声明处 `default alBottom`，构造函数也显式赋值），因此值为 `alBottom` 时不写入 `.lfm`/`.dfm`。放到窗体上默认贴底，无需手动设置。
- **填充面板规则：** `Width <= 0` 的面板吃掉剩余空间，但**只有第一个** `<= 0` 面板生效，其后的 `<= 0` 面板宽度为 0（会退化成零宽面板）。若剩余空间为负则夹紧到 0。
- **最后一个面板顶到右边缘：** 无论给它设了多宽，最后一个面板的右边界都会拉到 `总宽 - 内边距`（与原生状态栏一致，win32 把末个面板的 right 设为 -1）。否则各面板宽度之和凑不满客户区时，末个面板与边框之间会露出一条父窗体底色的空带。
- **SimplePanel 屏蔽面板：** `SimplePanel = True` 时完全忽略 `Panels` 集合，只画 `SimpleText`；此时 `PanelAtPos` 恒返回 `-1`。切回多面板模式时面板内容仍在（未被清空）。
- **面板变更即重绘：** `TTyStatusPanel` 的 `Text`/`Width`/`Alignment` setter 调用 `Changed(False)`，经 `TTyStatusPanels.Update` 触发宿主 `Invalidate`——运行时改面板文本会自动刷新，无需手动 `Invalidate`。
- **面板点击：** 用 `OnPanelClick`。它只认"在同一个面板上按下并松开"的左键点击；面板在按下和松开之间被删掉或换了位置，这次点击作废。尺寸手柄画在最后一个面板上面，但不属于它：点在手柄上不触发。在 Windows 上，状态栏贴着可调整大小的窗口底边时，底边几个像素和手柄归窗口调整大小用，按在那里既不触发 `OnPanelClick` 也不触发 `OnClick`，这是有意的。
- **面板里的控件（`Control`）：**
  - 赋值即改父控件：控件会被设成 `Align = alNone` 并成为状态栏的子控件；它的位置从此归状态栏管，自己设的 `Left`/`Top` 会在下一次布局时被改回去。尺寸还是它自己的：改它的 `Width`/`Height`，状态栏就按新尺寸摆，文字跟着让位。
  - 格子比控件小的时候控件被缩到格子里，格子变大后恢复原来的尺寸。`AutoSize = True` 的控件不缩（它会自己再撑回去）。
  - `SimplePanel` 模式下没有格子，控件在运行时被缩成 0×0，切回多面板模式后恢复。设计器里不缩，免得把 0×0 存进窗体文件。
  - 面板被删除时控件不跟着释放，它留在状态栏上原来的位置，由你处置。控件被释放、或者被改到别的父控件上，面板的 `Control` 自动变回 `nil`。把同一个控件赋给第二个面板（或另一个状态栏的面板），原来那个面板会放手。
  - 状态栏自己、以及状态栏所在的容器不能当面板控件，赋值会抛 `EInvalidOperation`。
  - 子控件的圆角外侧、透明区域取到的是状态栏的主题背景，不用另外处理。
  - 窗体文件里 `Control` 写的是控件名；控件声明在状态栏之前、之后或状态栏里面都能正确载入。设计器保存时会把它写在状态栏里面。
- **状态栏可以放子控件：** 设计器里可以直接把控件拖进状态栏（`csAcceptsControls`）。没有挂到面板 `Control` 上的子控件，状态栏不摆放它，位置由你自己定。`BorderWidth` 的含义不变，仍然是状态栏内容的额外内边距。
- **SizeGrip 仅为视觉提示：** `SizeGrip` 绘制的是 3 个装饰性小点，表示可拖拽调整窗口大小的位置提示；它本身只是绘制，`default True` 故值为 `True` 时不写入序列化。
- **状态栏顶线而非边框：** 主题的 `border-color`/`border-width` 只作用于**顶部一条细线**，不绘制四周完整边框；面板之间的分隔线同样依赖 `border-color` 令牌存在才绘制。
- **视觉全部由主题驱动：** 背景、文字颜色、字号、字重均取自 `.tycss` 令牌（见上表），不在控件代码中写死；控件也不暴露 `Color`/`Font`（族/字号）等与主题冲突的原生属性。
- **右到左镜像（`BiDiMode := bdRightToLeft`）：** 面板从右往左铺，第一个面板顶到右边缘、最后一个顶到左边缘（“末个面板顶边”那条规则跟着换边），面板分隔线画在各面板的**前导**边；面板文本的 `Alignment` 按阅读序解释（`taLeftJustify` 落在格子右侧）。**尺寸手柄移到左下角**，交给操作系统的拖拽边码也从 `HTBOTTOMRIGHT` 换成 `HTBOTTOMLEFT`。
- **手柄的绘制与命中现在共用一处：** 面板矩形一直只有 `TyStatusPanelRects` 一个出处（绘制、`PanelAtPos`、`PanelRect` 和面板控件的摆放现在读的是同一次布局），但手柄从前是两份——绘制里的 `W - Scale(3) - k*Scale(4)` 与 `ResizeHitAt` 里的 `X >= W - grip` 各自声明了一遍“手柄在右下角”。现在两边都从 `TyStatusGripRect` 取那个角，只是要的方框大小不同（抓取区比三个点大一圈）。底边细条两端的 `HTBOTTOMLEFT`/`HTBOTTOMRIGHT` **不镜像**：那两个说的是真实的窗口角，窗口的左下角在哪种阅读方向下都还是左下角。见 [rtl.md](../rtl.md)。
