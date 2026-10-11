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
| `Min` / `Max` | `Integer` | `0` / `100` | 取值范围。改了以后所有滑块重新排好（见第 6 节），有滑块因此移动时照常触发事件。 |
| `MinGap` | `Integer` | `0` | 相邻两个滑块至少隔多远（值单位）。`0` 表示可以重合。区间内部、区间之间都受它约束。范围放不下时的处理见第 6 节。 |
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
| `OnThumbSelect` | `TTyTrackThumbEvent` | `nil` | 选中的滑块变了，`AIndex` 是新序号（`-1` = 没有选中）。 |
| `OnDrawTrack` | `TTyTrackDrawEvent` | `nil` | 自绘轨道，见第 5 节。 |
| `OnDrawThumb` | `TTyTrackDrawThumbEvent` | `nil` | 自绘滑块，见第 5 节。 |

### public 成员

| 成员 | 说明 |
|------|------|
| `ThumbCount: Integer` | 滑块个数。`TTyRangeTrackBar` 是区间数 × 2。 |
| `ThumbValues[i]: Integer` | 第 i 个滑块的值，只读。滑块永远按值升序排列。 |
| `SetThumbValue(AIndex, AValue)` | 移动一个滑块。值会被夹在 `Min..Max` 以及左右邻居 ± `MinGap` 之间；真变了才触发 `OnThumbChange` 和 `OnChange`。拖动、键盘、集合项赋值走的都是它。序号越界抛 `EListError`。 |
| `SelectedThumb: Integer` | 键盘操作的那个滑块，`-1` = 没有。赋值越界当作 `-1`。 |
| `ThumbRect(AIndex): TRect` | 滑块的**命中**矩形（客户区坐标）：沿轨道 12 逻辑像素，横向占满整个控件——和 `TTyTrackBar.ThumbRect` 在同一个值时完全一样。 |
| `SegmentSpan(AIndex, APPI, out ALow, AHigh): Boolean` | 第 AIndex 段沿主轴的像素范围（见下文「分段」）。只给位置，不管这一段画不画。 |

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
```

- `OnDrawTrack` 在画凹槽**之前**调用，`ARect` 是凹槽矩形。把 `ADefaultDraw` 设成 `False`，控件就不画凹槽，也不画区间高亮和分段——整条轨道交给你。保留 `True` 的话，默认画法会盖在你画的东西上面。
- `OnDrawThumb` 在画每个滑块**之前**调用，`ARect` 是滑块实际画出来的矩形（在滑块带里，横向比 `ThumbRect` 的命中矩形窄，有刻度时让出刻度那一条），`AStates` 是解析样式用的状态：`tysNormal` / `tysHover` / `tysActive` 三选一，控件有焦点时选中的那个滑块再加 `tysFocused`。`ADefaultDraw := False` 只跳过这一个滑块。
- 调用顺序就是绘制顺序：先轨道，再按序号画滑块，正在拖的（没有就是选中的）放到最后，压在上面。刻度、标签和读数总是由控件画。
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

## 6. 值的规则

**不变式**：滑块按值升序排列，相邻两个至少隔 `MinGap`，全部在 `Min..Max` 内。

- **单个滑块移动**（拖动、键盘、`SetThumbValue`、给集合项赋值）：夹在左右邻居 ± `MinGap` 和 `Min..Max` 之间，碰到邻居就停，不会越过去。
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

  `TTyMultiTrackBar` 在 `EndUpdate` 时按值把集合项排序，每一项带着自己的颜色、提示、可用状态和样式类一起挪；选中的滑块也跟着它的项走到新位置（序号变了会触发一次 `OnThumbSelect`），被删掉的话就变成没有选中。
- **清空集合**：把区间或滑块全删了，窗体文件里会写 `NoRanges = True` / `NoThumbs = True`。读窗体时空集合不会被清掉，没有这个标记就会把构造时的默认项读回来。

---

## 7. 键盘与鼠标

只有可用的滑块参与。

| 操作 | 行为 |
|------|------|
| 左键按在滑块上 | 选中它，从按下的位置开始拖（只按不动不会挪动滑块）。几个滑块叠在一起时取中心最近的那个，一样近取值小的。 |
| 左键按在轨道空白处 | 离按点最近的滑块跳过去并选中，接着可以拖。一样近时取值小的那个。 |
| 拖动 | 经 `SetThumbValue`，碰到邻居停在 `MinGap` 处。`MinGap = 0` 时几个滑块叠在同一个值上，往哪边拖就由能往那边走的那个接手，叠在两端的滑块也拉得开。拖出控件不中断，松开左键才结束。 |
| `←` / `↓` | 键盘滑块减 `LineSize`（竖排时 `↑` 增大，同 `TTyTrackBar`） |
| `→` / `↑` | 加 `LineSize` |
| `PageUp` / `PageDown` | 加 / 减 `PageSize` |
| `Home` / `End` | 到它能去的最小 / 最大值（邻居 ± `MinGap`，或 `Min` / `Max`） |
| `Tab` / `Shift+Tab` | 在可用滑块之间前后切换；到了最后一个（往回时是第一个）再按，焦点才离开控件。 |
| 用 Tab 进入控件 | 选中第一个可用滑块；用 `Shift+Tab` 进入时选中最后一个。点击进入时由点击决定。 |
| 滚轮 | 键盘滑块上滚加 `LineSize`、下滚减，同 `TTyTrackBar`；`OnMouseWheel` 里置 `Handled` 可以拦下。 |

「键盘滑块」是选中的那个；没有选中（或选中的不可用）时是第一个可用滑块，按键后它变成选中的。

---

## 8. 状态与主题

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

## 9. 与 TTyTrackBar 的区别

1. **没有 `Position`**：值在 `ThumbValues` / 集合项里。读数（`ShowValue`）显示选中滑块的值。
2. **没有 `SelStart` / `SelEnd`**：要高亮一段就用 `TTyRangeTrackBar` 的区间（同一个主题键），而且用户拖得动。
3. **没有位置动画**：键盘和滚轮改值时滑块直接跳到新位置。
4. **右到左（RTL）不镜像**，与 `TTyTrackBar` 一致：值轴只看 `Orientation` 和 `Reversed`。整个滑块家族的 RTL 以后一起做。
5. 刻度、刻度标签、凹槽、滑块的尺寸和位置都与 `TTyTrackBar` 共用同一套函数：一个值为 V 的滑块，画出来和 `Position = V` 的 `TTyTrackBar` 一模一样。

---

## 10. 代码示例

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
