# TTyTrackBar — API 参考

## 1. 概述

`TTyTrackBar` 是 TyControls 库中的主题化滑块控件，继承自 `TTyCustomControl`。控件显示一条轨道（可水平或垂直，见 `Orientation`），轨道上有一个可拖动的滑块（thumb），并可按 `Frequency` 绘制刻度线。用户可以鼠标拖动滑块、点击轨道任意位置、或使用方向键 / `PageUp`/`PageDown` / `Home`/`End` 来改变 `Position` 值；`OnChange` 在值变化时触发。垂直方向遵循"顶部=Max、值向上增大"的约定。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.TrackBar` |
| typeKey（轨道） | `TyTrackBar` |
| typeKey（滑块） | `TyTrackThumb` |
| typeKey（选区） | `TyTrackSelection` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸 | 160 × 24（逻辑像素） |

```pascal
uses tyControls.TrackBar;
```

---

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Min` | `Integer` | `0` | 最小值。赋值时若 `Position < Min` 则静默夹紧，触发重绘。 |
| `Max` | `Integer` | `100` | 最大值。赋值时若 `Position > Max` 则静默夹紧，触发重绘。 |
| `Position` | `Integer` | `0` | 当前值，范围 `[Min, Max]`，赋值时自动夹紧；若值真正变化则触发 `OnChange` 和重绘。 |
| `Orientation` | `TTyTrackOrientation` | `toHorizontal` | 滑块方向：`toHorizontal`（水平，默认；左=Min、右=Max）/ `toVertical`（垂直）。**垂直约定：顶部为 `Max`，值向上增大**（即向上拖动/方向键增大 `Position`）。赋值时若当前宽高与新方向不符会**自动对调宽高**（与 LCL 一致），随后重绘；流式载入期间（`csLoading`）不动，`.lfm` 里写死的尺寸优先。 |
| `Frequency` | `Integer` | `1` | 刻度线（tick marks）间隔，单位为值（value-units）。默认 `1` = 每个值单位一条刻度（与原生 `TTrackBar` 一致，开箱即可见刻度）；`0` = **不绘制刻度**。负值被夹为 0。 |
| `Reversed` | `Boolean` | `False` | **（API parity 新增）** 在**不改方向**的前提下翻转值轴：水平条从左到右递**减**，或垂直条把 `Min` 放到顶部。早前方向是写死在 `Orientation` 上的（垂直=反向、水平=正向），四种配置里有两种根本取不到。**垂直轴上与 LCL 有意不同**，见第 8 节第 12 条。按键和滚轮跟着屏幕走，翻转后改变 `Position` 的方向相反，见第 5 节。 |
| `TickMarks` | `TTyTrackTickMark` | `ttmBottomRight` | **（API parity 新增）** 刻度画在轨道哪一侧：`ttmBottomRight`（水平在下 / 垂直在右，默认）/ `ttmTopLeft` / `ttmBoth`。与 LCL `TTickMark` 同义同默认（`comctrls.pp:2795`）。 |
| `TickStyle` | `TTyTrackTickStyle` | `ttsAuto` | **（API parity 新增）** 刻度怎么生成：`ttsAuto`（每 `Frequency` 个值单位一条，默认）/ `ttsNone`（不画）/ `ttsManual`（**只**画 `SetTick` 手工放的那几条）。与 LCL `TTickStyle` 同义同默认（`comctrls.pp:2796`）。`Frequency = 0` 仍然能关掉自动刻度，旧写法不变。 |
| `LineSize` | `Integer` | `1` | 方向键单步步进量（每次 ±`LineSize`）。最小为 1（赋值 <1 被夹为 1）。 |
| `PageSize` | `Integer` | `10` | `PageUp`/`PageDown` 翻页步进量（每次 ±`PageSize`）。最小为 1（赋值 <1 被夹为 1）。 |
| `SelStart` / `SelEnd` | `Integer` | `0` / `0` | 选区的两端，单位和 `Position` 相同（照 LCL）。轨道上这两个值之间的一段用 `TyTrackSelection` 的 `background` 填充，画在滑块下面；起止点在滑块中心，`Reversed`、竖排都跟着走。两端超出 `Min..Max` 时落在 `Min` / `Max` 上；两个都是 `0` 表示没有选区（LCL 的约定，新放的控件不显示）；`SelStart > SelEnd` 时不画（和 Windows 原生滑块一样）。只用来显示，用户拖不动——要能拖的区间用 [`TTyRangeTrackBar`](multitrackbar.md)。 |
| `ShowSelRange` | `Boolean` | `True` | 是否显示选区，默认值照 LCL。 |
| `ShowValue` | `Boolean` | `False` | 在滑轨旁显示当前值（横向在右、纵向在下），字体与颜色取轨道样式 `TyTrackBar` 的 `color`。默认关——打开会占掉一条空间，滑轨相应变短（几何与命中都跟着变）。 |
| `TickLabels` | `Boolean` | `False` | 在每条刻度外侧写上它的值，见第 6 节「刻度标签」。默认关——标签要另占一条，已经摆好的窗体不该因此变形。 |
| `OnFormatTickLabel` | `TTyTrackTickLabelEvent` | `nil` | `procedure(Sender: TObject; AValue: Integer; var AText: string)`：画之前改写某条刻度标签的文字（「1 月」「¥100」）；改成空串就不画这一条。 |
| `OnDrawThumb` | `TTyTrackDrawThumbEvent` | `nil` | 自己画滑块（三角形、图片、任意形状），见 [第 6 节](#自己画滑块ondrawthumb)。4.0 起。 |
| `OnChange` | `TNotifyEvent` | `nil` | `Position` 真实变化时触发（含拖动、点击定位、方向键/翻页键步进、直接赋值）。 |
| `TabStop` | `Boolean` | `True` | 是否参与 Tab 键导航（构造时自动置为 `True`）。 |
| `Align` | `TAlign` | — | 父容器内的停靠方式。 |
| `Anchors` | `TAnchors` | — | 锚点布局。 |
| `StyleClass` | `string` | `''` | CSS 变体类名。 |
| `Controller` | `TTyCustomStyleController` | `nil`（全局默认） | 关联的样式控制器。 |
| `OnClick` | `TNotifyEvent` | `nil` | 鼠标点击时触发（在完成定位后触发）。 |

### 继承的通用成员

TTyTrackBar 继承自 `TTyCustomControl`（`tyControls.Base`）的通用状态机制。

---

## 4. 方法与事件

### public 方法

#### `function ThumbRect: TRect`

返回滑块在控件客户区坐标系中的当前像素矩形（以 `Font.PixelsPerInch` 为 DPI 基准），**随 `Orientation` 切换主轴**。这是**命中**矩形：沿主轴和画出来的滑块一样长，垂直于主轴占满整个控件（比画出来的滑块宽容，指针在滑块那一列的任何位置都能抓住它）。

滑轨排在**内容区**里：客户区减去焦点环（或边框）和样式的 `padding`，见 [第 6 节](#内容区焦点环和-padding)。滑块沿主轴的长度默认 12 逻辑像素，可用令牌 `--track-thumb-length` 改。

- **水平：** 主轴为宽度（`MainLen` = 内容区宽度，开了 `ShowValue` 再减去读数那一条），滑块沿左右移动（左=Min、右=Max）。
- **垂直：** 主轴为高度（`MainLen` = 内容区高度，同样减去读数），滑块沿上下移动；坐标系**反转**（`Inverted = True`），使顶部对应 `Max`、底部对应 `Min`。

偏移量由内部纯函数 `TyTrackThumbOffset(MainLen, ThumbW, Min, Max, Position, Inverted)` 计算（四舍五入），按 `Inverted` 标志处理垂直反转。

#### `procedure DragTo(APos: Integer)`

将滑块中心对齐到沿主轴的坐标 `APos` 处（水平传入鼠标 X、垂直传入鼠标 Y），经 `TyTrackPosFromOffset`（同样按 `Inverted` 处理垂直反转）算出新的 `Position` 并赋值（触发夹紧和 `OnChange`）。通常在拖动或点击事件中调用。

---

## 5. 键盘与交互

方向键按 `Orientation` 区分主轴，"增大"方向遵循垂直顶=Max 约定：

| 操作 | 水平（`toHorizontal`） | 垂直（`toVertical`） | 行为 |
|------|------|------|------|
| 减小键 | `←`（Left） | `↓`（Down） | `Position -= LineSize`（到达 `Min` 后停止） |
| 增大键 | `→`（Right） | `↑`（Up） | `Position += LineSize`（到达 `Max` 后停止） |
| 横跨主轴的减小键 | `↓`（Down） | `←`（Left） | 同减小键 |
| 横跨主轴的增大键 | `↑`（Up） | `→`（Right） | 同增大键 |
| `PageUp`（VK_PRIOR） | — | — | `Position += PageSize`（**增大**，两种方向一致） |
| `PageDown`（VK_NEXT） | — | — | `Position -= PageSize`（减小，两种方向一致） |
| `Home`（VK_HOME） | — | — | `Position := Min` |
| `End`（VK_END） | — | — | `Position := Max` |
| 鼠标左键按下 | — | — | 立即定位到点击位置（水平按 X、垂直按 Y 调用 `DragTo`）并开始拖动 |
| 鼠标拖动 | — | — | 持续调用 `DragTo`（水平 X / 垂直 Y） |
| 鼠标左键释放 | — | — | 结束拖动 |
| 鼠标滚轮 | — | — | **（API parity 新增）** 滚轮上滚 `Position += LineSize`、下滚 `-= LineSize`（与原生 LCL `TTrackBar` 一致：上滚增大，与 ScrollBar 相反）；经 `SetPosition` 触发 `OnChange`。`Enabled = False` 时忽略。 |

> **注意：** 垂直方向上 `↑` 增大、`↓` 减小（顶部=Max）；四个方向键在两种方向下都起作用，`↑`/`→` 始终增大、`↓`/`←` 始终减小，按键不会漏给窗体让焦点跑掉；`PageUp` 始终增大、`PageDown` 始终减小，与方向无关。上面说的都是没翻转的条。每个被处理的按键消费后不再传递（`Key := 0`）。

**`Reversed = True` 时按键和滚轮跟着屏幕走。** 每个键、滚轮每一格让滑块在屏幕上往哪边走，和同方向没翻转的条完全一样，所以改变 `Position` 的方向正好相反：

- 横排翻转后按 `→`，滑块往右走，`Position` 减小；按 `←` 往左走，`Position` 增大。
- 竖排翻转后按 `↑`，滑块往上走，`Position` 减小；按 `↓` 往下走，`Position` 增大。
- `PageUp` / `PageDown` 同理：`PageUp` 还是让滑块往右（竖排往上）走，翻转后 `Position` 减小。
- `Home` 把滑块送到没翻转时它去的那一头（横排左端、竖排底端），翻转后那一头是 `Max`；`End` 送到另一头，是 `Min`。
- 滚轮上滚还是让滑块往右（竖排往上）走，翻转后 `Position` 减小。

这和 LCL 的 `TTrackBar` 在 Windows 上一样：Windows 的原生滑块本身不翻转，LCL 只是把位置镜像过去，所以翻不翻转，按键都按屏幕方向走。

> **基线事件集：** 除 `OnChange` 外，TTyTrackBar 还暴露全部**基线事件**（Tier A + Tier B），见 [../events.md](../events.md)。TrackBar **无** `OnScroll` 事件（与 ScrollBar 不同），位置变化统一通过 `OnChange` 通知。

---

## 6. 状态与主题

### 轨道：typeKey `TyTrackBar`

| 状态 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停在控件上 |
| `:focus` | 获得键盘焦点 |
| `:active` | 鼠标左键按下（任意位置） |
| `:disabled` | `Enabled = False` |

### 内容区：焦点环和 padding

滑轨、滑块、刻度和读数都排在**内容区**里，内容区是客户区四边各让出两样东西之后剩下的部分：

- **外框**：焦点环（`TyTrackBar:focus` 的 `outline`，含 `outline-offset`）和边框里宽的那个。不管控件有没有焦点都让出焦点环的位置，所以获得焦点时滑轨不会移动。主题既没有焦点环也没有边框时不让。
- **padding**：样式的 `padding`，内置主题是 0。想让滑轨离边远一点，或者让读数后面多留些空，在控件的 `StyleOverride` 里写，比如 `padding: 0px 8px;`。

拖动和命中用的是同一个内容区，画在哪儿、点了算多少不会对不上。`AutoSize` 的厚度也把这两样算进去。

> 3.0.5 以前各部件排在整个客户区里：滑轨穿过焦点环，滑块和刻度压在环上，读数贴着环，`padding` 不起作用（#236）。升级后，在有焦点环的主题上（内置主题都有 2 像素的环）滑轨四周各向里收 2 像素。

### 滑块的大小和圆角

三个令牌，每个滑动条自己读（先读自己的 `StyleOverride`，再读主题），3.0.5 新增（#237）：

| 令牌 | 默认 | 含义 |
|---|---|---|
| `--track-thumb-length` | `12px` | 滑块沿滑轨方向的大小。 |
| `--track-thumb-thickness` | 占满滑轨所在的带 | 滑块垂直于滑轨方向的大小；超过那条带就按带算。 |
| `--track-thumb-radius` | `TyTrackThumb` 规则的 `border-radius` | 滑块的圆角。 |

```pascal
// 圆形滑块：长和厚相等，圆角用主题默认的胶囊值
Bar.StyleOverride := '--track-thumb-length: 16px; --track-thumb-thickness: 16px;';
// 方形
Bar.StyleOverride := '--track-thumb-length: 14px; --track-thumb-thickness: 14px; --track-thumb-radius: 0px;';
// 窄条
Bar.StyleOverride := '--track-thumb-length: 6px; --track-thumb-radius: 2px;';
// 所有滑动条
TyDefaultController.StyleOverride := ':root { --track-thumb-length: 16px; --track-thumb-thickness: 16px; }';
```

方向换成垂直时，“长”仍然沿着滑轨、“厚”仍然垂直于滑轨。滑块的颜色仍由主题的 `TyTrackThumb` 规则决定。三角形和自绘滑块 3.0 没有。

### 自己画滑块：`OnDrawThumb`

4.0 起（#242）。三个令牌只管得了圆角矩形这一类：圆、胶囊、窄条、方块。三角形、图片，或者应用自己的形状，在这个事件里画：

```pascal
TTyTrackDrawThumbEvent = procedure(Sender: TObject; APainter: TTyPainter; AIndex: Integer;
  const ARect: TRect; const AStyle: TTyStyleSet; AStates: TTyStateSet;
  var ADefaultDraw: Boolean) of object;
```

- `ARect` 是滑块实际画出来的矩形，坐标就是控件的客户区坐标：在滑块所在的带里（有刻度时让出刻度那一条），`--track-thumb-thickness` 已经算进去。
- `AStyle` 是控件本来要用的样式：`TyTrackThumb` 规则在 `AStates` 下解析出来的结果，`--track-thumb-radius` 已经写进 `BorderRadius`。主题色在 `AStyle.Background.Color` 里，悬停、按下时主题换了颜色，这里拿到的就是换过的。
- `AStates`：`tysNormal` / `tysHover` / `tysActive` 三选一，控件有焦点时再加 `tysFocused`。
- `AIndex` 在 `TTyTrackBar` 上总是 `0`；多滑块一族用的是同一个事件，那里是滑块的序号（见 [multitrackbar.md](multitrackbar.md) 第 6 节）。
- 把 `ADefaultDraw` 设成 `False`，控件就不画这个滑块，画什么都由你。保留 `True` 的话，默认的滑块会盖在你画的东西上面。
- 命中测试不变：不管画成什么形状，能抓住滑块的仍然是 `ThumbRect` 那个矩形。

一个指向下方的三角形：

```pascal
procedure TForm1.BarDrawThumb(Sender: TObject; APainter: TTyPainter; AIndex: Integer;
  const ARect: TRect; const AStyle: TTyStyleSet; AStates: TTyStateSet;
  var ADefaultDraw: Boolean);
begin
  ADefaultDraw := False;
  APainter.BeginPath;
  APainter.MoveTo(ARect.Left, ARect.Top);
  APainter.LineTo(ARect.Right, ARect.Top);
  APainter.LineTo((ARect.Left + ARect.Right) / 2, ARect.Bottom);
  APainter.ClosePath;
  APainter.FillPath(AStyle.Background.Color);   // 主题给滑块的颜色，悬停和按下时跟着变
end;
```

想让三角形宽一点，把 `--track-thumb-length` 调大（比如 `16px`）；它同时决定了能抓住滑块的范围。

派生类想换滑块的画法，重写 protected 的 `PaintThumb`（参数和事件一样）。基类的实现就是「先问 `OnDrawThumb`，没被接管就按主题画」，重写后不调 `inherited` 就不再问事件。

### 滑块子部件：typeKey `TyTrackThumb`

滑块使用独立 typeKey `TyTrackThumb` 解析样式，状态如下：

| 状态 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停在滑块矩形内（非拖动时） |
| `:active` | 正在拖动中（`FDragging = True`） |
| `:focus` | 控件有键盘焦点（与上面三种叠加）。默认主题在滑块内侧画一圈 `--on-accent` 色的环；主题没写这条规则时滑块外观不变。 |
| 无伪类 | 正常状态 |

> **注意：** 拖动时滑块状态固定为 `:active`，即使鼠标移出控件边界（`MouseLeave` 不会清除 `FDragging`，仅在 `MouseUp` 时清除）。

### light.tycss 示例规则

```css
TyTrackBar {
  background: darken(--surface, 6%);  /* 轨道背景 */
  border-radius: 4px;
}
TyTrackBar:focus    { outline: 2px var(--focus-ring); }
TyTrackBar:disabled { opacity: 0.5; }   /* 禁用态半透明，与其余控件状态一致 */

TyTrackThumb { background: var(--border); border-radius: 4px; }
TyTrackThumb:hover  { background: darken(--border, 10%); }
TyTrackThumb:active { background: var(--accent); }
TyTrackThumb:focus  { outline: 2px var(--on-accent); outline-offset: 2px; }
```

> **滑块的焦点环：** `TyTrackThumb` 的 `outline` 画在滑块**内侧**，`outline-offset` 往里缩。滑块本身是强调色，用 `--focus-ring`（也是强调色）画会看不出来，所以默认主题用强调色上的文字色 `--on-accent`。整条控件的焦点环仍由 `TyTrackBar:focus` 负责。多滑块控件里，这个状态只给方向键要动的那个滑块，见 [multitrackbar.md](multitrackbar.md)。

> **`:disabled`（Batch ④）：** `TyTrackBar` 现支持 `:disabled` 伪类，与 `TyScrollBar` / `TyTabControl` / `TyProgressBar` 一道补齐状态等价性——`Enabled = False` 时整条轨道（含滑块、刻度）按 `opacity` 统一变淡。滑块子部件 `TyTrackThumb`（tier-a 着色面）的颜色独立于轨道，详见 [tycss-reference.md](../tycss-reference.md) §8.3。

### 刻度线（ticks）

当 `Frequency > 0` 且 `Max > Min` 时，控件从 `Min` 起每隔 `Frequency` 个值单位绘制一条短刻度线，刻度对齐到该值下滑块中心所在的主轴位置（水平绘于轨道底缘、垂直绘于轨道右缘，长约 4 逻辑像素 / 粗 1 逻辑像素）。刻度颜色取轨道样式 `TyTrackBar` 的 `TextColor`（即 CSS `color`，主题驱动），可在 `.tycss` 中为 `TyTrackBar` 声明 `color` 控制刻度颜色——`ShowValue` 的读数用的也是这一条 `color`。默认 `Frequency = 1`（每个值单位一条）；置 `0` 才完全不绘制刻度。

### 刻度标签（TickLabels）

`TickLabels = True` 时，每条刻度外侧（离凹槽较远的那一边）写上它的值；`TickMarks = ttmBoth` 时两侧都写。字体和颜色取 `TyTrackBar`，和刻度、读数是同一条 `color`。

- 标签另占一条：横排时高度是文字高 + 2 逻辑像素，竖排时宽度是最宽那个标签 + 2 逻辑像素，凹槽和滑块相应让开。这条的厚度在绘制时量出并缓存，所以开了 `AutoSize` 的控件在第二次布局时才把它算进去（和 `ShowValue` 一样）。
- 相邻标签挤不下时跳过中间会重叠的那些，首尾两个总是保留（控件短得连这两个都放不下时只留第一个）。
- `OnFormatTickLabel` 可以改写文字：

  ```pascal
  procedure TMainForm.MonthLabel(Sender: TObject; AValue: Integer; var AText: string);
  begin
    AText := IntToStr(AValue) + ' 月';
  end;
  ```

- 关着的时候（默认）布局和绘制与没有这个功能时逐像素相同。`TTyRangeTrackBar` / `TTyMultiTrackBar` 的刻度和标签与这里是同一段代码。

---

## 7. 状态过渡动画（batch⑤+⑥）

`TTyTrackBar` 支持滑块（thumb）在 **程序化** `Position` 改变时平滑过渡到新位置，由 `tyControls.Animation` 单元的 `TTyAnimator` 驱动。

### 开关属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `AnimationsEnabled` | `Boolean` | `True` | 是否启用滑块位置过渡动画。**public 属性，不 published**（不写入 `.lfm`），需在代码中设置。 |

> 这是唯一的动画开关，**没有**单独的时长 / 缓动曲线属性可供配置——时长与缓动在控件内部固定。

### 行为

- **程序化变化才缓动：** 启用（`True`，默认）且有窗口句柄时，由**方向键 / `PageUp`/`PageDown` / `Home`/`End` / 直接赋值**等引起的 `Position` 变化会让滑块从旧位置**缓动**到新位置（约 **120ms**，缓动曲线 `teEaseOutCubic`）。
- **拖动 / 点击定位始终瞬时：** 鼠标拖动或点击轨道定位（`DragTo`）时滑块**实时跟手、不缓动**，避免延迟感。
- **关闭（`False`）：** 所有 `Position` 变化都瞬间反映到滑块位置。
- 控件尚无窗口句柄（headless / 设计器）时，无论开关如何都**瞬间吸附到终态**（**headless-snap**）——因此既有的逐像素 thumb 几何测试不受影响。
- 内部按需创建一个 `TTimer`（约 60fps）推进动画，抵达目标后自动停止；动画逻辑可在测试中以显式毫秒步进确定性驱动。

```pascal
var TB: TTyTrackBar;
TB := TTyTrackBar.Create(Self);
TB.Parent := Self;
// AnimationsEnabled 默认即为 True（程序化变化时滑块缓动）；
// 如需瞬时更新可显式关闭：TB.AnimationsEnabled := False;
TB.Position := 80;   // 滑块平滑滑向 80（约 120ms）
```

---

## 8. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.TrackBar;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

// 创建滑块
var TB: TTyTrackBar;
TB := TTyTrackBar.Create(Self);
TB.Parent := Self;
TB.SetBounds(24, 24, 200, 24);
TB.Min := 0;
TB.Max := 100;
TB.Position := 50;
TB.OnChange := @OnTrackChange;

procedure TMainForm.OnTrackChange(Sender: TObject);
begin
  with Sender as TTyTrackBar do
    Label1.Caption := Format('当前值：%d', [Position]);
end;
```

完整可运行示例参见 `examples/trackbar/umain.pas`。

---

## 9. 注意事项

1. **ThumbRect 坐标系：** `ThumbRect` 返回的是**控件客户区坐标**（左上角为 `(0,0)`），不是屏幕坐标。
2. **拖动跨出边界：** 鼠标移出控件范围时，`MouseLeave` 不会终止拖动（仅清除 hover 状态），这使得"按住不放，拖出后再拖回"的体验连贯。拖动只在 `MouseUp` 时结束。
3. **OnChange 防重入：** `SetPosition` 先夹紧值，若夹紧后与原值相同则不调用 `OnChange`，回调中无需过滤重复值。
4. **Min/Max 修改时 Position 静默校正：** 修改范围后 `Position` 会被自动校正，但不触发 `OnChange`（仅触发 `Invalidate`）。
5. **滑块的大小走令牌：** 滑块沿主轴默认 12 逻辑像素（DPI 缩放后），垂直于主轴默认占满滑轨所在的带；两者和圆角都能用令牌改（`--track-thumb-length` / `--track-thumb-thickness` / `--track-thumb-radius`，见 [第 6 节](#滑块的大小和圆角)），没有对应的属性。
6. **垂直方向约定：** `Orientation = toVertical` 时，**顶部为 `Max`、底部为 `Min`，值向上增大**——向上拖动、`↑`、`PageUp` 都增大 `Position`。切换 `Orientation` 时控件的宽/高会**自动对调**（仅当当前尺寸与新方向不符时）：以前不换，于是一个 200×30 的横条切成垂直后仍是 200 宽 30 高、里面画着一条竖轨道，每个调用方都得自己再改一次尺寸。流式载入期间不动，`.lfm` 里的显式尺寸优先。
7. **刻度由 TickStyle + Frequency + TickMarks 共同决定（API parity 新增）：** `TickStyle` 选**哪些值**有刻度（自动 / 不画 / 只画手工放的），`TickMarks` 选**画在哪一侧**。`ttsManual` 配合 `SetTick` 才能表达不等距刻度（gamma 曲线、一组档位）；`ClearTicks` 清空，`TickCount` 读数量。超出 `[Min,Max]` 的手工刻度不会被接受，也不会在范围改变后被夹到端头凭空造出一条刻度。
8. **刷一遍默认值差异（有意保留）：** `Max` 默认 `100`（LCL 是 `10`）、`PageSize` 默认 `10`（LCL 是 `2`）。两者**不跟随 LCL**：这两个只是量级默认值，不改变任何语义；而 published 默认值一旦改动，**所有现有 `.lfm`（恰恰因为值等于默认而没有存盘）会静默改变含义** —— 正是这条指控本身担心的那种失败，只不过受害者变成了本库的使用者。从 Lazarus 批量移植时请显式写清楚这两个属性。
9. **刻度由 Frequency 驱动：** 默认 `Frequency = 1`（每个值单位一条刻度，与原生 `TTrackBar` 一致）；置 `0` 才不绘制刻度。颜色取自主题 `TyTrackBar` 的 `color`。以前默认是 `0`，于是拖一个滑块到窗体上看到的是一条光秃秃的轨道，刻度看起来像没实现，而不像被关掉了。
10. **滑块过渡动画（batch⑤+⑥）：** `AnimationsEnabled` 默认 `True`，程序化 `Position` 变化（方向键/翻页/Home/End/赋值）时滑块缓动到新位置（约 120ms），**拖动 / 点击定位则始终瞬时跟手**；headless / 设计器下瞬间吸附。详见上文「状态过渡动画」。
11. **`AutoSize` 现在有东西可问（API parity 新增）：** 控件实现了 `CalculatePreferredSize`，**只答跨轴**（水平条答高度、垂直条答宽度，主轴返回 `0` = 该轴无意见）——与 LCL `ShouldAutoAdjust` 的切分一致（`include/trackbar.inc:95-107`）。轨道多长是窗体作者的事，多厚是主题的事：换一个刻度更长、内距更厚或读数字体更大的皮肤时，写死 `Height = 24` 的滑块会把刻度或读数裁掉。（`ShowValue` 的文字高度在绘制时量得并缓存，因此开了读数的控件在**第二次**布局时才稳定，与 `MainLen` 早就带着的首帧局限一样。）
12. **`Reversed` 在垂直轴上与 LCL 不同（有意，有迁移路径）：** 本控件**未翻转**的垂直方向是顶部 = `Max`（音量推块），因为只有这样“向上 = 变大”对键盘、滚轮和拖动才同时成立（见第 6 条）；LCL/Win32 未翻转的垂直条是顶部 = `Min`。所以水平条的值轴与 LCL 一致，垂直条正好相反。迁移：从 Lazarus 移植时，垂直条上的 `Reversed` 去掉，水平条上的原样保留。若改成跟随 LCL，现有每一个垂直 `TTyTrackBar` 都会静默倒过来，而且 `↑` 会变成向下拖滑块。按键和滚轮在翻转的条上跟着屏幕走（第 5 节），这条规则与 LCL 在 Windows 上一致。各个键往哪边走仍有本控件自己的约定：`PageUp` 往 `Max` 那头走，Windows 往左（竖排往上）走，见 [LCL 差异](../lcl-differences.md)；竖排的 `Home` 去底端，Windows 去顶端。
