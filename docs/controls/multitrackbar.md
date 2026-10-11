# TTyRangeTrackBar / TTyMultiTrackBar — API 参考

## 1. 概述

一条轨道上放多个滑块。两个控件共用同一套模型、画法和交互，区别只在滑块怎么组织：

- **`TTyRangeTrackBar`**：一个或多个区间。每个区间两个滑块（`Low`、`High`），区间之间不重叠，`Low..High` 一段用选区色填充。适合价格区间、时间段、允许值范围。
- **`TTyMultiTrackBar`**：多个独立的值。每个滑块可以单独设颜色、提示、是否可用和样式类；相邻两个滑块之间的一段可以按样式类着色。适合阈值刻度（正常 / 警告 / 危险）、多个标记点、渐变色标。

属性名和默认值尽量与 `TTyTrackBar` 相同（`Min`、`Max`、`Orientation`、`Reversed`、`TickMarks`、`TickStyle`、`Frequency`、`LineSize`、`PageSize`、`ShowValue`、`TickLabels`……），换过来时不用重新记一套。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.MultiTrackBar` |
| typeKey（控件） | `TyRangeTrackBar` / `TyMultiTrackBar`，父键都是 `TyTrackBar`——现有主题不用改就能用，想单独调再写自己的规则 |
| typeKey（凹槽） | `TyTrackGroove`（与 `TTyTrackBar` 共用） |
| typeKey（滑块） | `TyTrackThumb`（与 `TTyTrackBar` 共用），每个滑块可带自己的样式类 |
| typeKey（区间高亮） | `TyTrackSelection`（`TTyRangeTrackBar`，与 `TTyTrackBar` 的选区同一个键） |
| typeKey（分段） | `TyTrackSegment.<类>`（`TTyMultiTrackBar`） |
| 类层次 | `TTyCustomControl` → `TTyMultiTrackBarBase` → `TTyCustomRangeTrackBar` → `TTyRangeTrackBar`；`TTyMultiTrackBarBase` → `TTyCustomMultiTrackBar` → `TTyMultiTrackBar` |
| 默认尺寸 | 160 × 24（逻辑像素，高度随密度缩放） |
| 面板 | `TyControls Bars`，紧跟在 `TTyTrackBar` 后面 |

```pascal
uses tyControls.MultiTrackBar;
```

---

## 3. 共用属性

两个控件都 published 下面这些（`TTyMultiTrackBarBase` 里实现）。

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Min` / `Max` | `Integer` | `0` / `100` | 取值范围。改了以后所有滑块重新排好（见第 7 节），有滑块因此移动时照常触发事件。 |
| `MinGap` | `Integer` | `0` | 相邻两个滑块至少隔多远（值单位）。`0` 表示可以重合。区间内部、区间之间都受它约束。范围放不下时的处理见第 7 节。 |
| `Orientation` | `TTyTrackOrientation` | `toHorizontal` | 与 `TTyTrackBar` 相同：竖排时顶部是 `Max`，改方向时宽高自动对调（读窗体时不动）。 |
| `Reversed` | `Boolean` | `False` | 不改方向，翻转值轴。 |
| `TickMarks` / `TickStyle` / `Frequency` | — | `ttmBottomRight` / `ttsAuto` / `1` | 刻度画在哪一侧、画哪些值，与 `TTyTrackBar` 完全相同，连画法都是同一段代码。`SetTick` / `ClearTicks` / `TickCount` 用于 `ttsManual`。 |
| `TickLabels` | `Boolean` | `False` | 在每条刻度外侧写上它的值。说明见 [trackbar.md](trackbar.md) 的「刻度标签」。 |
| `OnFormatTickLabel` | `TTyTrackTickLabelEvent` | `nil` | 改写刻度标签的文字（「1 月」「¥100」），写成空串就不画那一条。 |
| `LineSize` / `PageSize` | `Integer` | `1` / `10` | 方向键和滚轮每次走 `LineSize`，`PageUp` / `PageDown` 走 `PageSize`。最小为 1。 |
| `ShowValue` | `Boolean` | `False` | 在轨道旁显示数值（横排在右、竖排在下）：显示**选中滑块**的值，没有选中时显示第一个滑块的值。读数那一条按 `Min`、`Max` 里较宽的那个量，拖动时轨道长度不会跟着位数变。 |
| `TabStop` | `Boolean` | `True` | 可以用 Tab 进入。 |
| `OnChange` | `TNotifyEvent` | `nil` | 任何一个滑块的值变了就触发（一次操作只触发一次）。 |
| `OnThumbChange` | `TTyTrackThumbEvent` | `nil` | 某个滑块的值变了，`AIndex` 是它的序号。先于 `OnChange`。 |
| `OnThumbChanging` | `TTyTrackThumbChangingEvent` | `nil` | 用户正要移动某个滑块，值还没变。可以不让动，也可以改成别的值。只管用户操作，代码赋值不触发。见第 6 节。 |
| `OnThumbSelect` | `TTyTrackThumbEvent` | `nil` | 选中的滑块变了，`AIndex` 是新序号（`-1` = 没有选中）。 |
| `OnDrawTrack` | `TTyTrackDrawEvent` | `nil` | 自绘轨道，见第 5 节。 |
| `OnDrawThumb` | `TTyTrackDrawThumbEvent` | `nil` | 自绘滑块，见第 5 节。 |
| `OnDrawSegment` | `TTyTrackDrawSegmentEvent` | `nil` | 自绘分段（两个滑块之间的那段凹槽），见第 5 节。 |
| `OnTrackClick` | `TTyTrackClickEvent` | `nil` | 左键按在轨道上、没按中滑块时触发，先于默认的「最近的滑块跳过来」。见第 6 节。 |

### public 成员

| 成员 | 说明 |
|------|------|
| `ThumbCount: Integer` | 滑块个数。`TTyRangeTrackBar` 是区间数 × 2。 |
| `ThumbValues[i]: Integer` | 第 i 个滑块的值，只读。滑块永远按值升序排列。 |
| `SetThumbValue(AIndex, AValue)` | 从代码移动一个滑块。值会被夹在 `Min..Max` 以及左右邻居 ± `MinGap` 之间；真变了才触发 `OnThumbChange` 和 `OnChange`，不问 `OnThumbChanging`。给集合项赋值走的也是它。拖动、键盘、滚轮按同样的规则夹值，只是先问 `OnThumbChanging`。序号越界抛 `EListError`。 |
| `SelectedThumb: Integer` | 键盘操作的那个滑块，`-1` = 没有。赋值越界当作 `-1`。 |
| `ThumbRect(AIndex): TRect` | 滑块的**命中**矩形（客户区坐标）：沿轨道 12 逻辑像素，横向占满整个控件——和 `TTyTrackBar.ThumbRect` 在同一个值时完全一样。 |
| `ThumbAtPoint(X, Y): Integer` | 客户区里一个点下面是哪个滑块，没有就是 `-1`。判断规则和左键按下时完全一样（控件自己按下、悬停、按滑块显示提示都调它）：几个滑块的命中矩形叠在一起时取中心最近的，一样近取值小的。**不可用的滑块也算**——它照样画在那里，应用可能还要对它做点什么（比如右键删除）；按下时不理它的是控件自己。 |
| `SegmentSpan(AIndex, APPI, out ALow, AHigh): Boolean` | 第 AIndex 段沿主轴的像素范围（见下文「分段」）。只给位置，不管这一段画不画。 |
| `ValueAtPoint(X, Y): Integer` | 客户区里一个点对应的值：拖到那里的滑块、按在那里时跳过来的滑块，取的就是这个值。跟着 `Orientation` / `Reversed` 走，只看主轴，超出两端时是 `Min` / `Max`。 |

---

## 4. 两个控件各自的属性

### TTyRangeTrackBar

| 属性 | 类型 | 说明 |
|------|------|------|
| `Ranges` | `TTyTrackRanges` | 区间集合，项是 `TTyTrackRange`（`Low`、`High`）。滑块顺序是 `[Low0, High0, Low1, High1, …]`。新放的控件带一个 25..75 的区间。 |
| `LowValue` / `HighValue` | `Integer` | 第一个区间的两端（public）。没有区间时读出 0，赋值时先建一个。 |

- 给 `Low` / `High` 赋值和拖动走同一条路：碰到邻居停在 `MinGap` 处，并触发事件。
- 新加在末尾的区间从上一个区间的 `High`（第一个区间从 `Min`）铺到 `Max`，两端再按需要设。
- 区间里 `Low..High` 一段用 `TyTrackSelection` 填充（从滑块中心到滑块中心，和 `TTyTrackBar` 的选区画法一样），区间与区间之间露出凹槽。
- 窗体文件里区间乱序、重叠或 `Low > High` 都没关系：读完后所有值放在一起排序，再两两配对。

### TTyMultiTrackBar

| 属性 | 类型 | 说明 |
|------|------|------|
| `Thumbs` | `TTyTrackThumbs` | 滑块集合，`Thumbs[i]` 就是第 i 个滑块。新放的控件带三个：25、50、75。 |
| `Segments` | `TTyTrackSegments` | 分段样式集合，项只有 `StyleClass`。 |

滑块项 `TTyTrackThumbItem`：

| 属性 | 默认值 | 说明 |
|------|--------|------|
| `Value` | 新加在末尾时为 `Max` | 滑块的值，赋值与 `SetThumbValue` 相同。 |
| `Color` | `clDefault` | `clDefault` 跟主题走；其他颜色在所有状态下替换主题给的背景色。颜色在这里是**数据**（就像取色器选出来的那个颜色），不是界面样式。 |
| `Hint` | `''` | 指针停在这个滑块上时控件显示的提示（需要 `ShowHint`）；空串时用控件自己的 `Hint`。 |
| `Enabled` | `True` | `False`：照常画出来，但不能按、不能拖、不能选，键盘和 Tab 都跳过它。 |
| `StyleClass` | `''` | 按 `TyTrackThumb.<类>` 解析这个滑块的样式。 |

分段：第 0 段从轨道 `Min` 端到第一个滑块，第 i 段在滑块 i−1 和滑块 i 之间，最后一段从最后一个滑块到 `Max` 端。`Segments[i]` 的 `StyleClass` 不为空时，这一段用 `TyTrackSegment.<类>` 解析出的 `background` 填充；类为空或者 `Segments` 项数不够，这一段就不画，露出凹槽。默认主题带 `success`、`warning`、`danger` 三个类：

```pascal
// 0..60 正常，60..85 警告，85 以上危险
Bar.Thumbs.Clear;
Bar.Thumbs.Add.Value := 60;
Bar.Thumbs.Add.Value := 85;
Bar.Segments.Add.StyleClass := 'success';
Bar.Segments.Add.StyleClass := 'warning';
Bar.Segments.Add.StyleClass := 'danger';
```

---

## 5. 自绘

```pascal
TTyTrackDrawEvent = procedure(Sender: TObject; APainter: TTyPainter; const ARect: TRect;
  var ADefaultDraw: Boolean) of object;
TTyTrackDrawThumbEvent = procedure(Sender: TObject; APainter: TTyPainter; AIndex: Integer;
  const ARect: TRect; AStates: TTyStateSet; var ADefaultDraw: Boolean) of object;
TTyTrackDrawSegmentEvent = procedure(Sender: TObject; APainter: TTyPainter; AIndex: Integer;
  const ARect: TRect; var ADefaultDraw: Boolean) of object;
```

- `OnDrawTrack` 在画凹槽**之前**调用，`ARect` 是凹槽矩形。把 `ADefaultDraw` 设成 `False`，控件就不画凹槽，也不画区间高亮和分段——整条轨道交给你。保留 `True` 的话，默认画法会盖在你画的东西上面。
- `OnDrawSegment` 在凹槽画完之后、每一段的默认填充**之前**调用，`AIndex` 从 `0` 到 `ThumbCount`，**每一段都调**——不管它有没有默认填充（`TTyRangeTrackBar` 的区间、`TTyMultiTrackBar` 设了 `StyleClass` 的分段才有）。`ARect` 就是默认填充用的那个矩形：沿轨道从滑块中心到滑块中心（同 `SegmentSpan`），横向是凹槽的厚度；两个滑块叠在一起时可能是空矩形。`ADefaultDraw := False` 只跳过这一段的默认填充。如果 `OnDrawTrack` 已经把 `ADefaultDraw` 设成了 `False`，整条轨道归你，分段不画，`OnDrawSegment` 也不会被调用。
- `OnDrawThumb` 在画每个滑块**之前**调用，`ARect` 是滑块实际画出来的矩形（在滑块带里，横向比 `ThumbRect` 的命中矩形窄，有刻度时让出刻度那一条），`AStates` 是解析样式用的状态：`tysNormal` / `tysHover` / `tysActive` 三选一，控件有焦点时选中的那个滑块再加 `tysFocused`。`ADefaultDraw := False` 只跳过这一个滑块。
- 调用顺序就是绘制顺序：先轨道，再按序号画分段，再按序号画滑块，正在拖的（没有就是选中的）放到最后，压在上面。刻度、标签和读数总是由控件画。
- `APainter` 的坐标就是控件的客户区坐标。需要区间或分段的位置可以用 `SegmentSpan`。

```pascal
procedure TMainForm.BarDrawThumb(Sender: TObject; APainter: TTyPainter; AIndex: Integer;
  const ARect: TRect; AStates: TTyStateSet; var ADefaultDraw: Boolean);
var
  f: TTyFill;
begin
  if AIndex <> 0 then Exit;            // 只接管第一个滑块
  f := Default(TTyFill);
  f.Kind := tfkSolid;
  f.Color := TyRGB($F5, $9E, $0B);
  APainter.FillBackground(ARect, f, 2);
  ADefaultDraw := False;
end;
```

---

## 6. 在控件外面扩展

控件只内置通用的行为。点空白处加区间、按滑块颜色画渐变、固定某个滑块、右键删除这类需求，用事件和公开的几何（`ValueAtPoint`、`ThumbAtPoint`、`SegmentSpan`、`ThumbRect`、`ThumbValues`）在应用里写，不用改控件。

### OnTrackClick

```pascal
TTyTrackClickEvent = procedure(Sender: TObject; AValue: Integer;
  var AHandled: Boolean) of object;
```

- 左键按在轨道上、但没有按中任何滑块时触发（不可用的滑块也算滑块，按上去什么都不发生）。`AValue` 是按点的值，即 `ValueAtPoint(X, Y)`。
- 在默认行为**之前**调用。默认行为是离按点最近的可用滑块跳过来、被选中、接着可以拖。`AHandled := True` 就到此为止：没有滑块移动，选中也不变。
- 处理函数里可以增删区间或滑块。控件在事件返回后重新看一遍按点下面是什么：不处理（`AHandled` 保持 `False`）而刚好在按点放了一个滑块，这一下就按在了新滑块上——抓住它，不移动，可以接着拖。
- 双击只算一次点击：只有第一次按下会问。第一次被处理了，双击的第二次按下什么也不做；没被处理，第二次按下照常，不再问。

**示例一：点轨道空白处加一个区间**（`TTyRangeTrackBar`，遵守 `MinGap`）

```pascal
uses Math;

// 点在两个区间之间：在那里加一个宽 10 的区间；点在某个区间里：照常（最近的端点跳过来）
procedure TMainForm.PriceTrackClick(Sender: TObject; AValue: Integer; var AHandled: Boolean);
var
  i, lo, hi, gap: Integer;
  r: TTyTrackRange;
begin
  gap := Price.MinGap;
  lo := Price.Min;
  hi := Price.Max;
  // 区间总是按值排好的：找出按点左右两边的区间，新区间离它们都至少隔 MinGap
  for i := 0 to Price.Ranges.Count - 1 do
  begin
    r := Price.Ranges[i];
    if (AValue >= r.Low) and (AValue <= r.High) then Exit;   // 在区间里，交给默认行为
    if r.High < AValue then lo := Math.Max(lo, r.High + gap)
    else hi := Math.Min(hi, r.Low - gap);
  end;
  AHandled := True;                       // 不管加没加，都不让端点跳过来
  lo := Math.Max(lo, AValue - 5);
  hi := Math.Min(hi, AValue + 5);
  if (hi <= lo) or (hi - lo < gap) then Exit;   // 太挤，放不下
  Price.Ranges.BeginUpdate;
  try
    r := Price.Ranges.Add;
    r.Low := lo;
    r.High := hi;
  finally
    Price.Ranges.EndUpdate;
  end;
end;
```

`BeginUpdate` 不能省：新区间先加在集合末尾，这时直接给 `Low` / `High` 赋值会被它左边的邻居挡住（见第 7 节）；在 `BeginUpdate` 里赋值原样保存，到 `EndUpdate` 时一起排好。

### 示例二：渐变色标

一个 `TTyMultiTrackBar` 当渐变编辑器用：每个滑块是一个色标（颜色放在 `Thumbs[i].Color`，可以直接写在 .lfm 里），相邻两个滑块之间那一段用 `OnDrawSegment` 画成从左边颜色到右边颜色的渐变；点轨道空白处加一个色标，颜色按位置在左右两个色标之间插值。

```pascal
uses Math, Graphics, tyControls.Types, tyControls.Painter, tyControls.MultiTrackBar;

function MixColor(A, B: TColor; T: Double): TColor;
begin
  A := ColorToRGB(A);
  B := ColorToRGB(B);
  Result := RGBToColor(Round(Red(A) + (Red(B) - Red(A)) * T),
    Round(Green(A) + (Green(B) - Green(A)) * T), Round(Blue(A) + (Blue(B) - Blue(A)) * T));
end;

// 第 i 段（滑块 i-1 到滑块 i）画成两个滑块颜色之间的渐变；首尾两段照默认（露出凹槽）
procedure TMainForm.StopsDrawSegment(Sender: TObject; APainter: TTyPainter; AIndex: Integer;
  const ARect: TRect; var ADefaultDraw: Boolean);
var
  f: TTyFill;
  a, b: TColor;
begin
  if (AIndex = 0) or (AIndex >= Stops.ThumbCount) then Exit;
  a := ColorToRGB(Stops.Thumbs[AIndex - 1].Color);
  b := ColorToRGB(Stops.Thumbs[AIndex].Color);
  f := Default(TTyFill);
  f.Kind := tfkLinearGradient;
  f.GradFrom := TyRGB(Red(a), Green(a), Blue(a));
  f.GradTo := TyRGB(Red(b), Green(b), Blue(b));
  f.GradAngleDeg := 0;       // 0 = 从左到右（Min 在左）；竖排是 270（从下到上）
  APainter.FillBackground(ARect, f, 0);
  ADefaultDraw := False;
end;

// 点空白处：在那里加一个色标，颜色取左右两个色标按位置插值
procedure TMainForm.StopsTrackClick(Sender: TObject; AValue: Integer; var AHandled: Boolean);
var
  i: Integer;
  c: TColor;
  t: TTyTrackThumbItem;
begin
  i := 0;
  while (i < Stops.ThumbCount) and (Stops.ThumbValues[i] < AValue) do Inc(i);
  if Stops.ThumbCount = 0 then c := clGray
  else if i = 0 then c := Stops.Thumbs[0].Color
  else if i = Stops.ThumbCount then c := Stops.Thumbs[i - 1].Color
  else c := MixColor(Stops.Thumbs[i - 1].Color, Stops.Thumbs[i].Color,
    (AValue - Stops.ThumbValues[i - 1]) / (Stops.ThumbValues[i] - Stops.ThumbValues[i - 1]));
  Stops.Thumbs.BeginUpdate;
  try
    t := Stops.Thumbs.Add;
    t.Value := AValue;
    t.Color := c;
  finally
    Stops.Thumbs.EndUpdate;
  end;
  Stops.SelectedThumb := t.Index;   // EndUpdate 已经按值排好，项的序号就是滑块的序号
  AHandled := True;
end;
```

几点说明：

- `TTyFill` 只给两个颜色时填 `GradFrom` / `GradTo` 就够了，`GradStops` 留空。`GradAngleDeg` 与 tycss 的 `linear-gradient` 一致：`0` 从左到右，`90` 从上到下。
- 例子假定每个色标都设了 `Color`。`clDefault` 表示「跟主题走」，`ColorToRGB` 拿不到滑块实际画出来的颜色，渐变编辑器里别留默认色。
- 例子里的色标 `MinGap` 是 0。`MinGap` 大于 0 时，点在离已有色标太近的地方，`EndUpdate` 会把相邻的色标推开；不想这样就先在处理函数里检查，太近时不加。
- 渐变由画家按线性光混合，中间的颜色会比按 sRGB 直接平均的亮一些。

**固定的渐变不用写代码。** 如果分段的颜色是事先定好的（比如温度条从绿到红），在主题里加一个分段的样式类，再把那一段的 `StyleClass` 设成它：

```pascal
TyDefaultController.StyleOverride :=
  'TyTrackSegment.heat { background: linear-gradient(0deg, #22C55E, #EAB308, #EF4444); }';
Bar.Segments[1].StyleClass := 'heat';
```

### OnThumbChanging：固定滑块、吸附到整数步

```pascal
TTyTrackThumbChangingEvent = procedure(Sender: TObject; AIndex: Integer; var AValue: Integer;
  var AAllow: Boolean) of object;
```

- 用户要移动第 `AIndex` 个滑块时、值**还没变**之前触发。用户操作指：拖动（每挪一步问一次）、方向键 / `PageUp` / `PageDown` / `Home` / `End`、滚轮，以及按在轨道空白处时最近的滑块跳过来。
- `AValue` 是滑块将要去的值，已经夹在左右邻居 ± `MinGap` 和 `Min..Max` 之间。这一下根本动不了（比如已经顶着邻居还往那边拖）就不问。
- `AAllow := False`：滑块不动，也不触发 `OnThumbChange` / `OnChange`。
- 改 `AValue`：滑块去你给的值。这个值会再按邻居 ± `MinGap` 和 `Min..Max` 夹一遍，所以给得再离谱也破坏不了第 7 节的不变式。改完正好等于当前值，就什么都不发生。
- **只管用户，不管代码。** `SetThumbValue`、给 `Thumbs[i].Value` / `Ranges[i].Low` / `High` / `LowValue` / `HighValue` 赋值、改 `Min` / `Max` / `MinGap` 引起的重排、读窗体，都不触发——和 LCL 的惯例一样，这类事件拦的是用户，不是程序自己。
- 拖动被拒时，滑块留在原地，抓取点也不变：之后某一步放行了，滑块落在「指针减去当初按下时的偏移」处，不会突然跳到指针正下方。

**和 `Thumbs[i].Enabled := False` 的区别。** 不可用的滑块完全不参与交互：按不中、选不中、Tab 跳过它、没有悬停效果。被 `OnThumbChanging` 拒绝的滑块只是不动——照样能按、能选中（`OnThumbSelect` 照常触发）、能双击、Tab 能停在它上面、有焦点环。需要「看得到、点得到，但位置固定」时用 `OnThumbChanging`。

**示例一：渐变编辑器固定首尾两个色标**

两端的色标定义了渐变从哪里开始、到哪里结束，位置不该被拖走；但用户还要选中它们来改颜色，所以不能设成不可用。

```pascal
procedure TMainForm.StopsThumbChanging(Sender: TObject; AIndex: Integer;
  var AValue: Integer; var AAllow: Boolean);
begin
  // 第一个和最后一个色标钉在原地，中间的随便拖
  if (AIndex = 0) or (AIndex = Stops.ThumbCount - 1) then
    AAllow := False;
end;
```

按在轨道空白处时，如果离按点最近的是首尾色标，它会被选中但不会过来。想让空白处的点击干脆什么都不做，配合 `OnTrackClick` 置 `AHandled := True`。

**示例二：吸附到 5 的倍数**

```pascal
procedure TMainForm.BarThumbChanging(Sender: TObject; AIndex: Integer;
  var AValue: Integer; var AAllow: Boolean);
begin
  AValue := Round(AValue / 5) * 5;
end;
```

- 同时把 `LineSize` 设成 5。否则按一下方向键提议的是当前值 ± 1，吸附回去还是原值，看起来就是按键没反应。
- 吸附后的值还要再夹一遍。邻居在 20、`MinGap = 2` 时，往左拖到头提议的是 22，吸附成 20，再夹回 22——所以贴着邻居时可能停在不是 5 的倍数的位置。想严格只停在 5 的倍数上，让 `MinGap`、`Min`、`Max` 和所有滑块的初始值也都是 5 的倍数。

### 右键删除滑块

`ThumbAtPoint` 告诉你右键按在了哪个滑块上。下面用库里的 `TTyPopupMenu`（不是系统原生菜单）：把它设为控件的 `PopupMenu`，在 `OnContextPopup` 里决定弹不弹、菜单项能不能用。

```pascal
// Stops.PopupMenu := StopsMenu;  StopsMenu 里有一项 StopsMenuDelete
procedure TMainForm.StopsContextPopup(Sender: TObject; MousePos: TPoint;
  var Handled: Boolean);
begin
  if (MousePos.X = -1) and (MousePos.Y = -1) then
    FMenuStop := Stops.SelectedThumb       // 用菜单键或 Shift+F10 弹出：对选中的滑块
  else
    FMenuStop := Stops.ThumbAtPoint(MousePos.X, MousePos.Y);
  if FMenuStop < 0 then
  begin
    Handled := True;                       // 不在滑块上：不弹菜单
    Exit;
  end;
  // 首尾色标是固定的，不能删；只剩两个时也不能再删
  StopsMenuDelete.Enabled := (FMenuStop > 0) and (FMenuStop < Stops.ThumbCount - 1)
    and (Stops.ThumbCount > 2);
end;

procedure TMainForm.StopsMenuDeleteClick(Sender: TObject);
begin
  if (FMenuStop >= 0) and (FMenuStop < Stops.ThumbCount) then
    Stops.Thumbs.Delete(FMenuStop);
end;
```

- 序号要在弹出时记下来（`FMenuStop`），点菜单项时指针早就不在原处了，不能再按位置算一次。
- `OnContextPopup` 收到的 `MousePos` 是客户区坐标，正好交给 `ThumbAtPoint`；`(-1, -1)` 表示是键盘弹出的。
- `ThumbAtPoint` 会返回不可用的滑块。不想让人删不可用的滑块，自己再判断一下 `Thumbs[i].Enabled`。
- 删掉选中的滑块后，`SelectedThumb` 变成 `-1`（见第 7 节）。

`TTyRangeTrackBar` 删的是**整个区间**：滑块 `2k` 和 `2k + 1` 是第 `k` 个区间的 `Low` 和 `High`，区间条上的滑块永远成对，不能只删一端。

```pascal
procedure TMainForm.PriceContextPopup(Sender: TObject; MousePos: TPoint;
  var Handled: Boolean);
var
  i: Integer;
begin
  i := Price.ThumbAtPoint(MousePos.X, MousePos.Y);
  if i < 0 then
    FMenuRange := -1
  else
    FMenuRange := i div 2;                 // 按在哪一端都是这个区间
  Handled := FMenuRange < 0;
end;

procedure TMainForm.PriceMenuDeleteClick(Sender: TObject);
begin
  if (FMenuRange >= 0) and (FMenuRange < Price.Ranges.Count) then
    Price.Ranges.Delete(FMenuRange);
end;
```

---

## 7. 值的规则

**不变式**：滑块按值升序排列，相邻两个至少隔 `MinGap`，全部在 `Min..Max` 内。

- **单个滑块移动**（拖动、键盘、滚轮、`SetThumbValue`、给集合项赋值）：夹在左右邻居 ± `MinGap` 和 `Min..Max` 之间，碰到邻居就停，不会越过去。用户操作先问 `OnThumbChanging`，它给回来的值同样再夹一遍。
- **整体重排**发生在改 `Min`、`Max`、`MinGap` 时，以及读完窗体时：先排序，从左往右推开到满足间距，超出 `Max` 的再从右往左推回来。读窗体时的重排不触发事件。
- **`MinGap` 放不下时**——`(滑块数 − 1) × MinGap > Max − Min`——不报错，也不改属性值：滑块按 `(Max − Min) div (滑块数 − 1)` 的间距摆放。之后把范围放宽，原来的间距自动恢复。
- **`BeginUpdate` / `EndUpdate`**：在 `Ranges.BeginUpdate` 或 `Thumbs.BeginUpdate` 之后，给项赋值**原样保存**、不夹不排，滑块也先不动；到 `EndUpdate` 时一次排好。一次改好几个值、而且中间状态会互相挡路时（比如把两个区间整体右移），先 `BeginUpdate`：

  ```pascal
  Bar.Ranges.BeginUpdate;
  try
    Bar.Ranges[0].Low := 40;  Bar.Ranges[0].High := 50;
    Bar.Ranges[1].Low := 70;  Bar.Ranges[1].High := 90;
  finally
    Bar.Ranges.EndUpdate;
  end;
  ```

  `TTyMultiTrackBar` 在 `EndUpdate` 时按值把集合项排序，每一项带着自己的颜色、提示、可用状态和样式类一起挪；选中的滑块也跟着它的项走到新位置（序号变了会触发一次 `OnThumbSelect`），被删掉的话就变成没有选中。`TTyRangeTrackBar` 也一样：加区间、删区间或在 `EndUpdate` 时，区间项按值排序，每一项留着自己的 `Low` / `High`；选中的还是原来那个区间的同一端，序号变了触发一次 `OnThumbSelect`，那个区间被删了就变成没有选中。读窗体时不触发。
- **清空集合**：把区间或滑块全删了，窗体文件里会写 `NoRanges = True` / `NoThumbs = True`。读窗体时空集合不会被清掉，没有这个标记就会把构造时的默认项读回来。

---

## 8. 键盘与鼠标

只有可用的滑块参与。

| 操作 | 行为 |
|------|------|
| 左键按在滑块上 | 选中它，从按下的位置开始拖（只按不动不会挪动滑块）。几个滑块叠在一起时取中心最近的那个，一样近取值小的。 |
| 左键按在轨道空白处 | 先问 `OnTrackClick`（见第 6 节）；没被处理时，离按点最近的滑块跳过去并选中，接着可以拖。一样近时取值小的那个。 |
| 拖动 | 每一步先问 `OnThumbChanging`，碰到邻居停在 `MinGap` 处。`MinGap = 0` 时几个滑块叠在同一个值上，往哪边拖就由能往那边走的那个接手，叠在两端的滑块也拉得开。拖出控件不中断，松开左键才结束。 |
| `←` / `↓` | 键盘滑块减 `LineSize`（竖排时 `↑` 增大，同 `TTyTrackBar`） |
| `→` / `↑` | 加 `LineSize` |
| `PageUp` / `PageDown` | 加 / 减 `PageSize` |
| `Home` / `End` | 到它能去的最小 / 最大值（邻居 ± `MinGap`，或 `Min` / `Max`） |
| `Tab` / `Shift+Tab` | 在可用滑块之间前后切换；到了最后一个（往回时是第一个）再按，焦点才离开控件。 |
| 用 Tab 进入控件 | 选中第一个可用滑块；用 `Shift+Tab` 进入时选中最后一个。点击进入时由点击决定。 |
| 滚轮 | 键盘滑块上滚加 `LineSize`、下滚减，同 `TTyTrackBar`；`OnMouseWheel` 里置 `Handled` 可以拦下。 |

「键盘滑块」是选中的那个；没有选中（或选中的不可用）时是第一个可用滑块，按键后它变成选中的。

---

## 9. 状态与主题

| typeKey | 画什么 | 状态 |
|---------|--------|------|
| `TyRangeTrackBar` / `TyMultiTrackBar` | 控件本体（父键 `TyTrackBar`）：外框、刻度和标签的 `color`、读数字体 | `:focus` `:disabled` |
| `TyTrackGroove` | 凹槽 | 无 |
| `TyTrackThumb` | 每个滑块，可带样式类 | `:hover`（指针下）`:active`（正在拖）`:focus`（控件有焦点时的选中滑块） |
| `TyTrackSelection` | `TTyRangeTrackBar` 的区间 | 无 |
| `TyTrackSegment.<类>` | `TTyMultiTrackBar` 的分段，只读 `background`、`border-radius` | 无 |

默认主题里的相关规则：

```css
TyTrackSelection { background: var(--accent); border-radius: var(--radius-round); }
TyTrackSegment   { border-radius: var(--radius-round); }   /* 没有类：不画 */
TyTrackSegment.success { background: var(--success); }
TyTrackSegment.warning { background: var(--warning); }
TyTrackSegment.danger  { background: var(--danger); }
TyTrackThumb:focus { outline: 2px var(--on-accent); outline-offset: 2px; }
```

`TyTrackThumb:focus` 在滑块内侧画一圈 `--on-accent` 色的环：滑块本身是强调色，用 `--focus-ring`（也是强调色）画环会看不出来。按 Tab 在滑块之间切换时，有环的那个就是方向键要动的。`TTyTrackBar` 的单个滑块在控件有焦点时也带这个状态。

---

## 10. 与 TTyTrackBar 的区别

1. **没有 `Position`**：值在 `ThumbValues` / 集合项里。读数（`ShowValue`）显示选中滑块的值。
2. **没有 `SelStart` / `SelEnd`**：要高亮一段就用 `TTyRangeTrackBar` 的区间（同一个主题键），而且用户拖得动。
3. **没有位置动画**：键盘和滚轮改值时滑块直接跳到新位置。
4. **右到左（RTL）不镜像**，与 `TTyTrackBar` 一致：值轴只看 `Orientation` 和 `Reversed`。整个滑块家族的 RTL 以后一起做。
5. 刻度、刻度标签、凹槽、滑块的尺寸和位置都与 `TTyTrackBar` 共用同一套函数：一个值为 V 的滑块，画出来和 `Position = V` 的 `TTyTrackBar` 一模一样。

---

## 11. 代码示例

```pascal
uses
  tyControls.MultiTrackBar;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  // 两个价格区间，至少隔 5
  Price := TTyRangeTrackBar.Create(Self);
  Price.Parent := Self;
  Price.SetBounds(16, 16, 300, 24);
  Price.MinGap := 5;
  Price.Ranges.BeginUpdate;
  try
    Price.Ranges.Clear;
    with Price.Ranges.Add do begin Low := 10; High := 30; end;
    with Price.Ranges.Add do begin Low := 60; High := 85; end;
  finally
    Price.Ranges.EndUpdate;
  end;
  Price.OnChange := @PriceChange;
end;

procedure TMainForm.PriceChange(Sender: TObject);
begin
  Caption := Format('%d..%d, %d..%d', [Price.Ranges[0].Low, Price.Ranges[0].High,
    Price.Ranges[1].Low, Price.Ranges[1].High]);
end;
```

完整可运行示例见 `examples/trackbar/`。
