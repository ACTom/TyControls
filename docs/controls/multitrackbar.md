# TTyRangeTrackBar / TTyMultiTrackBar / TTyGradientTrackBar — API 参考

## 1. 概述

一条轨道上放多个滑块。三个控件共用同一套模型、画法和交互，区别只在滑块怎么组织：

- **`TTyRangeTrackBar`**：一个或多个区间。每个区间两个滑块（`Low`、`High`），区间之间不重叠，`Low..High` 一段用选区色填充。适合价格区间、时间段、允许值范围。
- **`TTyMultiTrackBar`**：多个独立的值。每个滑块可以单独设颜色、提示、是否可用和样式类；相邻两个滑块之间的一段可以按样式类着色。适合阈值刻度（正常 / 警告 / 危险）、多个标记点。
- **`TTyGradientTrackBar`**：渐变编辑器。滑块就是色标，轨道画成色标组成的渐变；点轨道加色标、拖出轨道删色标、双击改颜色，开箱即用。

属性名和默认值尽量与 `TTyTrackBar` 相同（`Min`、`Max`、`Orientation`、`Reversed`、`TickMarks`、`TickStyle`、`Frequency`、`LineSize`、`PageSize`、`ShowValue`、`TickLabels`……），换过来时不用重新记一套。

让用户加、删、越过、推动滑块、整段拖动区间，这些行为都由控件内置，各有一个开关（第 5 节）。区间控件和多值控件上默认全关，打开哪个由你决定；渐变控件默认就打开了编辑器该有的那几个。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.MultiTrackBar` |
| typeKey（控件） | `TyRangeTrackBar` / `TyMultiTrackBar` / `TyGradientTrackBar`，父键都是 `TyTrackBar`——现有主题不用改就能用，想单独调再写自己的规则 |
| typeKey（凹槽） | `TyTrackGroove`（与 `TTyTrackBar` 共用） |
| typeKey（滑块） | `TyTrackThumb`（与 `TTyTrackBar` 共用），每个滑块可带自己的样式类；控件另外会加上 `removing`、`stop` 两个类（第 10 节） |
| typeKey（区间高亮） | `TyTrackSelection`（`TTyRangeTrackBar`，与 `TTyTrackBar` 的选区同一个键） |
| typeKey（分段） | `TyTrackSegment.<类>`（`TTyMultiTrackBar`） |
| 类层次 | `TTyCustomControl` → `TTyMultiTrackBarBase` → `TTyCustomRangeTrackBar` → `TTyRangeTrackBar`；`TTyMultiTrackBarBase` → `TTyCustomMultiTrackBar` → `TTyMultiTrackBar`；`TTyCustomMultiTrackBar` → `TTyCustomGradientTrackBar` → `TTyGradientTrackBar` |
| 默认尺寸 | 160 × 24（逻辑像素，高度随密度缩放） |
| 面板 | `TyControls Bars`，紧跟在 `TTyTrackBar` 后面，依次是区间、多值、渐变 |

```pascal
uses tyControls.MultiTrackBar;
```

---

## 3. 共用属性

三个控件都 published 下面这些（`TTyMultiTrackBarBase` 里实现）。

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Min` / `Max` | `Integer` | `0` / `100` | 取值范围。改了以后所有滑块重新排好（见第 8 节），有滑块因此移动时照常触发事件。 |
| `MinGap` | `Integer` | `0` | 相邻两个滑块至少隔多远（值单位）。`0` 表示可以重合。区间内部、区间之间都受它约束。范围放不下时的处理见第 8 节。打开 `AllowCrossing` 时用户的操作不受它约束（第 5 节）。 |
| `Orientation` | `TTyTrackOrientation` | `toHorizontal` | 与 `TTyTrackBar` 相同：竖排时顶部是 `Max`，改方向时宽高自动对调（读窗体时不动）。 |
| `Reversed` | `Boolean` | `False` | 不改方向，翻转值轴。 |
| `TickMarks` / `TickStyle` / `Frequency` | — | `ttmBottomRight` / `ttsAuto` / `1` | 刻度画在哪一侧、画哪些值，与 `TTyTrackBar` 完全相同，连画法都是同一段代码。`SetTick` / `ClearTicks` / `TickCount` 用于 `ttsManual`。 |
| `TickLabels` | `Boolean` | `False` | 在每条刻度外侧写上它的值。说明见 [trackbar.md](trackbar.md) 的「刻度标签」。 |
| `OnFormatTickLabel` | `TTyTrackTickLabelEvent` | `nil` | 改写刻度标签的文字（「1 月」「¥100」），写成空串就不画那一条。 |
| `LineSize` / `PageSize` | `Integer` | `1` / `10` | 方向键和滚轮每次走 `LineSize`，`PageUp` / `PageDown` 走 `PageSize`。最小为 1。 |
| `ShowValue` | `Boolean` | `False` | 在轨道旁显示数值（横排在右、竖排在下）：显示**选中滑块**的值，没有选中时显示第一个滑块的值。读数那一条按 `Min`、`Max` 里较宽的那个量，拖动时轨道长度不会跟着位数变。 |
| `TabStop` | `Boolean` | `True` | 可以用 Tab 进入。 |
| `OnChange` | `TNotifyEvent` | `nil` | 任何一个滑块的值变了就触发（一次操作只触发一次）。用户加、删滑块或区间，渐变控件里改色标颜色，也触发。 |
| `OnThumbChange` | `TTyTrackThumbEvent` | `nil` | 某个滑块的值变了，`AIndex` 是它的序号。先于 `OnChange`。 |
| `OnThumbChanging` | `TTyTrackThumbChangingEvent` | `nil` | 用户正要移动某个滑块，值还没变。可以不让动，也可以改成别的值。只管用户操作，代码赋值不触发。见第 7 节。 |
| `OnThumbSelect` | `TTyTrackThumbEvent` | `nil` | 选中的滑块变了，`AIndex` 是新序号（`-1` = 没有选中）。 |
| `OnDrawTrack` | `TTyTrackDrawEvent` | `nil` | 自绘轨道，见第 6 节。 |
| `OnDrawThumb` | `TTyTrackDrawThumbEvent` | `nil` | 自绘滑块，见第 6 节。 |
| `OnDrawSegment` | `TTyTrackDrawSegmentEvent` | `nil` | 自绘分段（两个滑块之间的那段凹槽），见第 6 节。 |
| `OnTrackClick` | `TTyTrackClickEvent` | `nil` | 左键按在轨道上、没按中滑块时触发，先于控件自己的处理（加滑块 / 区间，或最近的滑块跳过来）。见第 7 节。 |

### public 成员

| 成员 | 说明 |
|------|------|
| `ThumbCount: Integer` | 滑块个数。`TTyRangeTrackBar` 是区间数 × 2。 |
| `ThumbValues[i]: Integer` | 第 i 个滑块的值，只读。滑块永远按值升序排列。 |
| `SetThumbValue(AIndex, AValue)` | 从代码移动一个滑块。值会被夹在 `Min..Max` 以及左右邻居 ± `MinGap` 之间；真变了才触发 `OnThumbChange` 和 `OnChange`，不问 `OnThumbChanging`。给集合项赋值走的也是它。拖动、键盘、滚轮按同样的规则夹值，只是先问 `OnThumbChanging`。序号越界抛 `EListError`。 |
| `SelectedThumb: Integer` | 键盘操作的那个滑块，`-1` = 没有。赋值越界当作 `-1`。 |
| `RemovingThumb: Integer` | 正被拖出轨道、松手就会删掉的那个滑块，`-1` = 没有（第 5 节）。拖动期间和绘制期间都有效：拖回轨道或者松手后又是 `-1`。自绘滑块时用它画自己的「将被删除」样子。 |
| `ThumbRect(AIndex): TRect` | 滑块的**命中**矩形（客户区坐标）：沿轨道 12 逻辑像素，横向占满整个控件——和 `TTyTrackBar.ThumbRect` 在同一个值时完全一样。 |
| `ThumbAtPoint(X, Y): Integer` | 客户区里一个点下面是哪个滑块，没有就是 `-1`。判断规则和左键按下时完全一样（控件自己按下、悬停、按滑块显示提示都调它）：几个滑块的命中矩形叠在一起时取中心最近的，一样近取值小的。**不可用的滑块也算**——它照样画在那里，应用可能还要对它做点什么（比如右键删除）；按下时不理它的是控件自己。 |
| `SegmentSpan(AIndex, APPI, out ALow, AHigh): Boolean` | 第 AIndex 段沿主轴的像素范围（见下文「分段」）。只给位置，不管这一段画不画。 |
| `ValueAtPoint(X, Y): Integer` | 客户区里一个点对应的值：拖到那里的滑块、按在那里时跳过来的滑块，取的就是这个值。跟着 `Orientation` / `Reversed` 走，只看主轴，超出两端时是 `Min` / `Max`。 |

---

## 4. 各控件自己的属性

### TTyRangeTrackBar

| 属性 | 类型 | 说明 |
|------|------|------|
| `Ranges` | `TTyTrackRanges` | 区间集合，项是 `TTyTrackRange`（`Low`、`High`）。滑块顺序是 `[Low0, High0, Low1, High1, …]`。新放的控件带一个 25..75 的区间。 |
| `LowValue` / `HighValue` | `Integer` | 第一个区间的两端（public）。没有区间时读出 0，赋值时先建一个。 |
| `AllowCrossing` / `Pushable` | `Boolean` | 见第 5 节，默认 `False`。 |
| `AllowUserRanges` | `Boolean` | 用户点轨道加区间、把一端拖出轨道删区间、按 `Delete` 删选中端点所在的区间。默认 `False`，见第 5 节。 |
| `NewRangeWidth` | `Integer` | 用户新加的区间有多宽（值单位），默认 `10`。放不下时会收窄。 |
| `DraggableRanges` | `Boolean` | 按住区间的高亮段拖，整个区间平移。默认 `False`，见第 5 节。 |
| `OnThumbRemoving` | `TTyTrackThumbRemovingEvent` | 用户要删一个区间之前问你，`AIndex` 是被拖出去的那一端（或选中的那一端）。 |

- 给 `Low` / `High` 赋值和拖动走同一条路：碰到邻居停在 `MinGap` 处，并触发事件。
- 新加在末尾的区间从上一个区间的 `High`（第一个区间从 `Min`）铺到 `Max`，两端再按需要设。
- 区间里 `Low..High` 一段用 `TyTrackSelection` 填充（从滑块中心到滑块中心，和 `TTyTrackBar` 的选区画法一样），区间与区间之间露出凹槽。
- 窗体文件里区间乱序、重叠或 `Low > High` 都没关系：读完后所有值放在一起排序，再两两配对。

### TTyMultiTrackBar

| 属性 | 类型 | 说明 |
|------|------|------|
| `Thumbs` | `TTyTrackThumbs` | 滑块集合，`Thumbs[i]` 就是第 i 个滑块。新放的控件带三个：25、50、75。 |
| `Segments` | `TTyTrackSegments` | 分段样式集合，项只有 `StyleClass`。 |
| `AllowCrossing` / `Pushable` | `Boolean` | 见第 5 节，默认 `False`。 |
| `AllowUserThumbs` | `Boolean` | 用户点轨道加滑块、拖出轨道或按 `Delete` 删滑块。默认 `False`，见第 5 节。 |
| `MinThumbs` / `MaxThumbs` | `Integer` | 用户最少删到几个、最多加到几个，`0` = 不限。默认都是 `0`。只限制用户，代码增删不受它管。 |
| `OnThumbRemoving` | `TTyTrackThumbRemovingEvent` | 用户要删一个滑块之前问你。 |

滑块项 `TTyTrackThumbItem`：

| 属性 | 默认值 | 说明 |
|------|--------|------|
| `Value` | 新加在末尾时为 `Max` | 滑块的值，赋值与 `SetThumbValue` 相同。 |
| `Color` | `clDefault` | `clDefault` 跟主题走；其他颜色在所有状态下替换主题给的背景色。颜色在这里是**数据**（就像取色器选出来的那个颜色），不是界面样式。用户加的滑块是 `clDefault`。 |
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

### TTyGradientTrackBar

建在多值控件上：`Thumbs` 就是色标，`Thumbs[i].Value` 是色标的位置，`Thumbs[i].Color` 是它的颜色。新放的控件带两个色标：`Min` 处黑、`Max` 处白。

| 属性 / 成员 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Thumbs` | `TTyTrackThumbs` | 黑 → 白两个 | 色标。项的属性同上表。 |
| `AllowCrossing` | `Boolean` | `True` | 色标可以互相越过，也可以叠在同一个值上。 |
| `AllowUserThumbs` | `Boolean` | `True` | 点轨道加色标，拖出轨道或按 `Delete` 删色标。 |
| `MinThumbs` / `MaxThumbs` | `Integer` | `2` / `0` | 用户最少删到两个色标，加多少不限。 |
| `OnThumbRemoving` | `TTyTrackThumbRemovingEvent` | `nil` | 用户要删一个色标之前问你。 |
| `OnEditStopColor` | `TTyEditStopColorEvent` | `nil` | 用户双击色标要改颜色，见下文。 |
| `Gradient: TTyGradStops` | 函数 | — | 按值排好的色标：每项是颜色和位置，位置 = `(Value − Min) / (Max − Min)`，在 `0..1` 之间。几个色标在同一个值上时按它们在 `Thumbs` 里的顺序。 |
| `GradientFill(AAngleDeg = 0): TTyFill` | 函数 | — | 轨道画的就是这个填充。交给 `TTyPainter.FillBackground` 就能在别处画出同一条渐变：没有色标是 `tfkNone`，一个是 `tfkSolid`，更多是 `AAngleDeg` 方向的线性渐变（`0` = `Min` 在左，`90` = `Min` 在上）。 |
| `ExecuteColorDialog(var AColor): Boolean` | protected virtual | — | 弹颜色对话框（`TTyColorDialog`），确定返回 `True` 并带回颜色。子类可以换成自己的对话框。 |

不发布 `Segments`（轨道已经是渐变了）和 `Pushable`。`OnDrawTrack` / `OnDrawSegment` 照常可以接管轨道。

**轨道。** 凹槽从 `Min` 端滑块的中心到 `Max` 端滑块的中心画成 `GradientFill`，两端外侧分别用第一个、最后一个颜色补齐，最后按主题画凹槽的边框。没有任何色标带颜色时画普通凹槽。

**加色标。** 新色标取渐变在那个位置已有的颜色，所以加上之后轨道看不出变化，要拖开或者改颜色才看得到。

**改颜色。** 双击一个可用的色标：先触发 `OnEditStopColor`。

```pascal
TTyEditStopColorEvent = procedure(Sender: TObject; AIndex: Integer; var AColor: TColor;
  var AHandled: Boolean) of object;
```

- `AColor` 进来时是色标现在的颜色（`clDefault` 的色标给的是渐变在那里的颜色）。
- `AHandled := True`：控件不弹对话框，色标取你留下的 `AColor`；不改就什么都不变。用自己的取色器时这样写。
- 不处理：控件以 `AColor` 打开 `TTyColorDialog`——处理函数可以只改 `AColor`、不置 `AHandled`，给对话框预设一个颜色。对话框没有 `Controller` 属性，按全局主题显示。
- 颜色真变了才触发 `OnChange`。
- 在空白处双击：第一下加一个色标，第二下编辑它的颜色。

**`clDefault` 的色标**没有自己的颜色：不进 `Gradient`，滑块按主题画。

**混色。** 渐变逐个色标线性混合，按 sRGB 各通道直接插值，不做 gamma 校正；新色标的颜色也按同样的方法算。画家在恰好两个色标、位置正好 0 和 1 时会走另一条带 gamma 校正的快路径，中间会亮一截（黑到白的中点约 `#AAAAAA`），再加一个色标整条渐变就变了样。为了让两个色标和三个色标画得一致，`GradientFill` 在这种情况下把第一个色标重复一次，避开那条路。

```pascal
// 预览条：画的就是轨道上那条渐变
procedure TMainForm.PreviewPaint(Sender: TObject; APainter: TTyPainter; const AContent: TRect);
begin
  APainter.FillBackground(AContent, Stops.GradientFill(0), 0);
end;
```

---

## 5. 用户编辑：开关

| 开关 | `TTyRangeTrackBar` | `TTyMultiTrackBar` | `TTyGradientTrackBar` |
|------|:-:|:-:|:-:|
| `AllowCrossing` | 有，默认关 | 有，默认关 | 有，默认**开** |
| `Pushable` | 有，默认关 | 有，默认关 | — |
| `AllowUserThumbs` | 叫 `AllowUserRanges`，默认关 | 有，默认关 | 有，默认**开** |
| `MinThumbs` / `MaxThumbs` | — | 有，`0` / `0` | 有，`2` / `0` |
| `NewRangeWidth` | 有，`10` | — | — |
| `DraggableRanges` | 有，默认关 | — | — |
| `OnThumbRemoving` | 有 | 有 | 有 |

### 你的事件先于控件

内置行为都挂在第一步就有的那几个事件**后面**，你的处理函数永远先跑，也永远拦得住：

- **加**：按在空白轨道上，先问 `OnTrackClick`。你置了 `AHandled := True`，控件就什么都不加。
- **移动**：越过、推动、整段拖动里，每个要动的滑块都先经 `OnThumbChanging`。拒绝了就不动，改了值就按你的值走。
- **删**：拖出轨道松手、按 `Delete`，先问 `OnThumbRemoving`。置 `AAllow := False` 就不删。

```pascal
TTyTrackThumbRemovingEvent = procedure(Sender: TObject; AIndex: Integer;
  var AAllow: Boolean) of object;
```

和 `OnThumbChanging` 一样，这些事件只管用户：代码里增删滑块、区间，直接改 `Value`，都不问。

### AllowCrossing：越过邻居

- 用户拖动的滑块不再被邻居挡住，越过去以后所有滑块按值重新排序。被拖的滑块带着它的项一起走——颜色、提示、样式类，选中也跟着它。方向键、`PageUp` / `PageDown`、`Home` / `End`、滚轮同样能越过。
- 开着时 `MinGap` 对用户操作不生效，两个滑块可以叠在同一个值上。
- 越过以后的事件顺序：`OnThumbSelect`（新序号）→ `OnThumbChange`（新序号）→ `OnChange`。
- **只管用户。** 代码写值（`SetThumbValue`、`Thumbs[i].Value`）照旧夹在两个邻居之间（间距按 0 算），不改变项的顺序。要整体重排，用 `BeginUpdate` / `EndUpdate`（第 8 节）。
- 关掉时滑块按 `MinGap` 重新排开，和改 `MinGap` 一样会触发事件。
- 与 `Pushable` 同时打开时，`AllowCrossing` 说了算。

### Pushable：推着邻居走

- 拖到离邻居 `MinGap` 的地方，邻居被推着一起走，邻居再推下一个，一直推到这一串顶住 `Min` / `Max` 为止。
- 每个被推的滑块都先经 `OnThumbChanging`。被拒绝的滑块就是一堵墙，不可用（`Enabled = False`）的滑块也是：整串停在离墙 `MinGap` 的地方。已经问过的滑块不会再问一次，退回的值总在它们被允许的方向上。被推的滑块，处理函数给回来的值还会再夹在「前一个 + `MinGap`」和这一串剩下的余地之间。
- 事件：`OnThumbChange` 按推动的顺序触发（被拖的先，然后依次是被推的），最后一次 `OnChange`。
- 只管用户的移动，代码写值不推。

### AllowUserThumbs / AllowUserRanges：加和删

**加。** 左键按在空白轨道上，`OnTrackClick` 没处理时：

- 多值控件、渐变控件：在按点加一个滑块并选中，这一下接着就是在拖它。离邻居不到 `MinGap` 时夹进两个邻居之间的空档；空档放不下，或者已经到了 `MaxThumbs`，这一下什么都不做——不会退回去让最近的滑块跳过来。多值控件新加的滑块 `Color = clDefault`，渐变控件见第 4 节。
- 区间控件：以按点为中心加一个宽 `NewRangeWidth` 的区间，`[v − w div 2, v − w div 2 + w]`，宽度是奇数时多出的那一格在上方。放不下时收窄到两侧区间（各让出 `MinGap`）和 `Min..Max` 之间的空档；剩下的比 `MinGap` 还窄就不加。按在某个区间里面不加，也不让端点跳过来（`DraggableRanges` 关着时按在高亮段上也是这样）。加上之后选中新区间的下端；`DraggableRanges` 开着时这一下接着整段拖新区间，关着时不拖。
- 只在第一下按下时加，双击的第二下不加。

**删。** 三种情况：

- 把滑块垂直于轨道拖出去，离控件边缘超过主题度量 `--track-remove-distance`（默认 24 逻辑像素；横排看 Y，竖排看 X）：滑块按「将被删除」的样子画（第 10 节），这时松手就删。拖回来就恢复。拖出去的时候滑块的值不跟指针走。
- 选中一个滑块按 `Delete`。
- 区间控件：拖出去的是哪一端都删**整个区间**，两端滑块和高亮段一起淡出；`Delete` 删选中端点所在的区间。

删之前先问 `OnThumbRemoving`（区间控件收到的是那一端的序号）。滑块数已经到 `MinThumbs` 时，拖出去也不显示「将被删除」，松手不删，也不问 `OnThumbRemoving`。删掉以后选中变成 `-1`。整段拖动（`DraggableRanges`）把区间拖出轨道不会删——只有拖一端才删。

### DraggableRanges：整段拖动区间

- 按在区间的高亮段上（不在端点上）拖，整个区间平移，宽度不变，碰到相邻区间（`MinGap`）或 `Min` / `Max` 就停。
- 按下时先问 `OnTrackClick`，处理了就不拖。按下选中这个区间的下端，指针位置按下端的抓取点换算，和拖单个滑块一样不会跳。
- 每一步先问下端、再问上端的 `OnThumbChanging`，各带这一步要把它放到的值。任何一端拒绝，这一步整段不动。处理函数改了值，整段按那一端的答案平移（后问的说了算），再夹回邻居和 `Min` / `Max` 之间。
- 事件：两端各一次 `OnThumbChange`（下端先），最后一次 `OnChange`。

---

## 6. 自绘

```pascal
TTyTrackDrawEvent = procedure(Sender: TObject; APainter: TTyPainter; const ARect: TRect;
  var ADefaultDraw: Boolean) of object;
TTyTrackDrawThumbEvent = procedure(Sender: TObject; APainter: TTyPainter; AIndex: Integer;
  const ARect: TRect; AStates: TTyStateSet; var ADefaultDraw: Boolean) of object;
TTyTrackDrawSegmentEvent = procedure(Sender: TObject; APainter: TTyPainter; AIndex: Integer;
  const ARect: TRect; var ADefaultDraw: Boolean) of object;
```

- `OnDrawTrack` 在画凹槽**之前**调用，`ARect` 是凹槽矩形。把 `ADefaultDraw` 设成 `False`，控件就不画凹槽，也不画区间高亮、分段和渐变——整条轨道交给你。保留 `True` 的话，默认画法会盖在你画的东西上面。
- `OnDrawSegment` 在凹槽画完之后、每一段的默认填充**之前**调用，`AIndex` 从 `0` 到 `ThumbCount`，**每一段都调**——不管它有没有默认填充（`TTyRangeTrackBar` 的区间、`TTyMultiTrackBar` 设了 `StyleClass` 的分段才有）。`ARect` 就是默认填充用的那个矩形：沿轨道从滑块中心到滑块中心（同 `SegmentSpan`），横向是凹槽的厚度；两个滑块叠在一起时可能是空矩形。`ADefaultDraw := False` 只跳过这一段的默认填充。如果 `OnDrawTrack` 已经把 `ADefaultDraw` 设成了 `False`，整条轨道归你，分段不画，`OnDrawSegment` 也不会被调用。
- `OnDrawThumb` 在画每个滑块**之前**调用，`ARect` 是滑块实际画出来的矩形（在滑块带里，横向比 `ThumbRect` 的命中矩形窄，有刻度时让出刻度那一条），`AStates` 是解析样式用的状态：`tysNormal` / `tysHover` / `tysActive` 三选一，控件有焦点时选中的那个滑块再加 `tysFocused`。`ADefaultDraw := False` 只跳过这一个滑块。接管了滑块，「将被删除」的样子也要自己画：看 `RemovingThumb` 是不是这个序号。区间控件里 `RemovingThumb` 是被拖出去的那一端，同一区间的另一端（序号 `RemovingThumb xor 1`）也该画成要删的样子（见第 10 节）。
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

## 7. 在控件外面扩展

通用的编辑行为控件已经内置（第 5 节）。内置的规则不合用时——只许在某一段里加、按别的规则取颜色、用右键菜单删——就用事件和公开的几何（`ValueAtPoint`、`ThumbAtPoint`、`SegmentSpan`、`ThumbRect`、`ThumbValues`）在应用里写，不用改控件。你的事件总是先于内置行为，处理了内置的就不再做。

### OnTrackClick

```pascal
TTyTrackClickEvent = procedure(Sender: TObject; AValue: Integer;
  var AHandled: Boolean) of object;
```

- 左键按在轨道上、但没有按中任何滑块时触发（不可用的滑块也算滑块，按上去什么都不发生）。`AValue` 是按点的值，即 `ValueAtPoint(X, Y)`。
- 在控件自己的处理**之前**调用。控件自己的处理是：开了 `AllowUserThumbs` / `AllowUserRanges` 时在那里加滑块或区间；没开时离按点最近的可用滑块跳过来、被选中、接着可以拖。`AHandled := True` 就到此为止：不加、没有滑块移动，选中也不变。
- 处理函数里可以增删区间或滑块。控件在事件返回后重新看一遍按点下面是什么：不处理（`AHandled` 保持 `False`）而刚好在按点放了一个滑块，这一下就按在了新滑块上——抓住它，不移动，可以接着拖。
- 双击只算一次点击：只有第一次按下会问。第一次被处理了，双击的第二次按下什么也不做；没被处理，第二次按下照常，不再问。

**示例：只许在 20..80 之间加区间**（`TTyRangeTrackBar`，`AllowUserRanges = True`）

```pascal
procedure TMainForm.PriceTrackClick(Sender: TObject; AValue: Integer; var AHandled: Boolean);
begin
  // 范围外的点击吞掉：不加区间，也不让端点跳过来
  if (AValue < 20) or (AValue > 80) then
    AHandled := True;
end;
```

自己加区间时，`BeginUpdate` 不能省：新区间先加在集合末尾，这时直接给 `Low` / `High` 赋值会被它左边的邻居挡住（见第 8 节）；在 `BeginUpdate` 里赋值原样保存，到 `EndUpdate` 时一起排好。

```pascal
Price.Ranges.BeginUpdate;
try
  r := Price.Ranges.Add;
  r.Low := lo;
  r.High := hi;
finally
  Price.Ranges.EndUpdate;
end;
```

**渐变不用自己画。** 以前用 `TTyMultiTrackBar` + `OnDrawSegment` + `OnTrackClick` 拼出来的渐变编辑器，现在直接用 `TTyGradientTrackBar`（第 4 节）。如果分段的颜色是事先定好的（比如温度条从绿到红），在主题里加一个分段的样式类，再把那一段的 `StyleClass` 设成它：

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

- 用户要移动第 `AIndex` 个滑块时、值**还没变**之前触发。用户操作指：拖动（每挪一步问一次）、方向键 / `PageUp` / `PageDown` / `Home` / `End`、滚轮，按在轨道空白处时最近的滑块跳过来，以及 `Pushable` 推动的每个邻居、`DraggableRanges` 拖动的区间两端。
- `AValue` 是滑块将要去的值，已经夹在左右邻居 ± `MinGap` 和 `Min..Max` 之间（`AllowCrossing` 开着时只夹 `Min..Max`）。这一下根本动不了（比如已经顶着邻居还往那边拖）就不问。
- `AAllow := False`：滑块不动，也不触发 `OnThumbChange` / `OnChange`。
- 改 `AValue`：滑块去你给的值。这个值会再按邻居 ± `MinGap` 和 `Min..Max` 夹一遍，所以给得再离谱也破坏不了第 8 节的不变式。改完正好等于当前值，就什么都不发生。
- **只管用户，不管代码。** `SetThumbValue`、给 `Thumbs[i].Value` / `Ranges[i].Low` / `High` / `LowValue` / `HighValue` 赋值、改 `Min` / `Max` / `MinGap` 引起的重排、读窗体，都不触发——和 LCL 的惯例一样，这类事件拦的是用户，不是程序自己。
- 拖动被拒时，滑块留在原地，抓取点也不变：之后某一步放行了，滑块落在「指针减去当初按下时的偏移」处，不会突然跳到指针正下方。

**和 `Thumbs[i].Enabled := False` 的区别。** 不可用的滑块完全不参与交互：按不中、选不中、Tab 跳过它、没有悬停效果。被 `OnThumbChanging` 拒绝的滑块只是不动——照样能按、能选中（`OnThumbSelect` 照常触发）、能双击、Tab 能停在它上面、有焦点环。需要「看得到、点得到，但位置固定」时用 `OnThumbChanging`。

**示例一：渐变编辑器固定首尾两个色标**

两端的色标定义了渐变从哪里开始、到哪里结束，位置不该被拖走，也不该被删掉；但用户还要选中它们、双击改颜色，所以不能设成不可用。

```pascal
procedure TMainForm.StopsThumbChanging(Sender: TObject; AIndex: Integer;
  var AValue: Integer; var AAllow: Boolean);
begin
  // 第一个和最后一个色标钉在原地，中间的随便拖
  if (AIndex = 0) or (AIndex = Stops.ThumbCount - 1) then
    AAllow := False;
end;

procedure TMainForm.StopsThumbRemoving(Sender: TObject; AIndex: Integer; var AAllow: Boolean);
begin
  // 也不许拖出去或按 Delete 删掉
  if (AIndex = 0) or (AIndex = Stops.ThumbCount - 1) then
    AAllow := False;
end;
```

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

内置的删除是拖出轨道和 `Delete` 键。想要右键菜单，`ThumbAtPoint` 告诉你右键按在了哪个滑块上。下面用库里的 `TTyPopupMenu`（不是系统原生菜单）：把它设为控件的 `PopupMenu`，在 `OnContextPopup` 里决定弹不弹、菜单项能不能用。

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
- 代码删除不问 `OnThumbRemoving`，也不受 `MinThumbs` 限制，这些条件要自己判断。
- 删掉选中的滑块后，`SelectedThumb` 变成 `-1`（见第 8 节）。

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

## 8. 值的规则

**不变式**：滑块按值升序排列，相邻两个至少隔 `MinGap`，全部在 `Min..Max` 内。`AllowCrossing` 开着时间距不算（按 0）。

- **单个滑块移动**（拖动、键盘、滚轮、`SetThumbValue`、给集合项赋值）：夹在左右邻居 ± `MinGap` 和 `Min..Max` 之间，碰到邻居就停，不会越过去——除非用户操作时开着 `AllowCrossing`（越过后重新排序）或 `Pushable`（推着邻居走），见第 5 节。用户操作先问 `OnThumbChanging`，它给回来的值同样再夹一遍。
- **整体重排**发生在改 `Min`、`Max`、`MinGap` 时，关掉 `AllowCrossing` 时，以及读完窗体时：先排序，从左往右推开到满足间距，超出 `Max` 的再从右往左推回来。读窗体时的重排不触发事件。
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

  `TTyMultiTrackBar`（以及渐变控件）在 `EndUpdate` 时按值把集合项排序，每一项带着自己的颜色、提示、可用状态和样式类一起挪；选中的滑块也跟着它的项走到新位置（序号变了会触发一次 `OnThumbSelect`），被删掉的话就变成没有选中。`TTyRangeTrackBar` 也一样：加区间、删区间或在 `EndUpdate` 时，区间项按值排序，每一项留着自己的 `Low` / `High`；选中的还是原来那个区间的同一端，序号变了触发一次 `OnThumbSelect`，那个区间被删了就变成没有选中。读窗体时不触发。
- **清空集合**：把区间或滑块全删了，窗体文件里会写 `NoRanges = True` / `NoThumbs = True`。读窗体时空集合不会被清掉，没有这个标记就会把构造时的默认项读回来。

---

## 9. 键盘与鼠标

只有可用的滑块参与。

| 操作 | 行为 |
|------|------|
| 左键按在滑块上 | 选中它，从按下的位置开始拖（只按不动不会挪动滑块）。几个滑块叠在一起时取中心最近的那个，一样近取值小的。 |
| 左键按在轨道空白处 | 先问 `OnTrackClick`（见第 7 节）；没被处理时，开了 `AllowUserThumbs` / `AllowUserRanges` 就在那里加滑块或区间（第 5 节），没开就是离按点最近的滑块跳过去并选中，接着可以拖。一样近时取值小的那个。 |
| 左键按在区间高亮段上 | `DraggableRanges` 开着时先问 `OnTrackClick`，没被处理就整段拖这个区间；关着时同按在空白处。 |
| 拖动 | 每一步先问 `OnThumbChanging`，碰到邻居停在 `MinGap` 处（`AllowCrossing` 时越过、`Pushable` 时推着走）。`MinGap = 0` 时几个滑块叠在同一个值上，往哪边拖就由能往那边走的那个接手，叠在两端的滑块也拉得开。拖出控件不中断，松开左键才结束。 |
| 拖出轨道 | 开了 `AllowUserThumbs` / `AllowUserRanges` 时，离控件边缘超过 `--track-remove-distance` 就显示「将被删除」，松手删除（第 5 节）。 |
| 双击色标 | 渐变控件：改颜色（第 4 节）。 |
| `←` / `↓` | 键盘滑块减 `LineSize`（竖排时 `↑` 增大，同 `TTyTrackBar`） |
| `→` / `↑` | 加 `LineSize` |
| `PageUp` / `PageDown` | 加 / 减 `PageSize` |
| `Home` / `End` | 到它能去的最小 / 最大值（邻居 ± `MinGap`，或 `Min` / `Max`） |
| `Delete` | 开了 `AllowUserThumbs` / `AllowUserRanges` 时删除选中的滑块（区间控件删它所在的区间），先问 `OnThumbRemoving`。 |
| `Tab` / `Shift+Tab` | 在可用滑块之间前后切换；到了最后一个（往回时是第一个）再按，焦点才离开控件。 |
| 用 Tab 进入控件 | 选中第一个可用滑块；用 `Shift+Tab` 进入时选中最后一个。点击进入时由点击决定。 |
| 滚轮 | 键盘滑块上滚加 `LineSize`、下滚减，同 `TTyTrackBar`；`OnMouseWheel` 里置 `Handled` 可以拦下。 |

「键盘滑块」是选中的那个；没有选中（或选中的不可用）时是第一个可用滑块，按键后它变成选中的。

---

## 10. 状态与主题

| typeKey | 画什么 | 状态 |
|---------|--------|------|
| `TyRangeTrackBar` / `TyMultiTrackBar` / `TyGradientTrackBar` | 控件本体（父键 `TyTrackBar`）：外框、刻度和标签的 `color`、读数字体 | `:focus` `:disabled` |
| `TyTrackGroove` | 凹槽（渐变控件只用它的边框和圆角，填充是渐变） | 无 |
| `TyTrackThumb` | 每个滑块，可带样式类 | `:hover`（指针下）`:active`（正在拖）`:focus`（控件有焦点时的选中滑块） |
| `TyTrackThumb.removing` | 拖出轨道、松手就会删掉的滑块 | 同上 |
| `TyTrackThumb.stop` | 渐变控件的色标 | 同上 |
| `TyTrackSelection` | `TTyRangeTrackBar` 的区间 | 无 |
| `TyTrackSegment.<类>` | `TTyMultiTrackBar` 的分段，只读 `background`、`border-radius` | 无 |

| 度量 | 默认 | 说明 |
|------|------|------|
| `--track-remove-distance` | `24px` | 滑块垂直于轨道拖出控件边缘多远算「拖出去了」。 |

默认主题里的相关规则：

```css
TyTrackSelection { background: var(--accent); border-radius: var(--radius-round); }
TyTrackSegment   { border-radius: var(--radius-round); }   /* 没有类：不画 */
TyTrackSegment.success { background: var(--success); }
TyTrackSegment.warning { background: var(--warning); }
TyTrackSegment.danger  { background: var(--danger); }
TyTrackThumb:focus { outline: 2px var(--on-accent); outline-offset: 2px; }
TyTrackThumb.removing { opacity: var(--disabled-opacity); }
TyTrackThumb.stop { border-width: 1px; border-color: var(--on-surface); }
```

`TyTrackThumb:focus` 在滑块内侧画一圈 `--on-accent` 色的环：滑块本身是强调色，用 `--focus-ring`（也是强调色）画环会看不出来。按 Tab 在滑块之间切换时，有环的那个就是方向键要动的。`TTyTrackBar` 的单个滑块在控件有焦点时也带这个状态。

**`removing` 和 `stop` 是类，不是状态。** 控件把它们加在滑块自己的样式类后面一起解析（滑块的类是 `big` 时解析 `big removing`），所以主题可以分别给 `.big` 和 `.removing` 写规则。

- `.removing` 的 `opacity` 由控件乘到滑块的颜色上（背景、边框、轮廓，`Thumbs[i].Color` 给的底色也算），只淡化这一个滑块。区间控件拖出一端时，两端滑块都按 `.removing` 画，高亮段按 `TyTrackThumb.removing` 解析出的 `opacity` 一起淡出——没有单独的 `TyTrackSelection.removing`。
- `.stop`：色标用自己的颜色填充，白色色标放在浅色表面上（或黑色色标放在深色表面上）会和周围融成一片。默认主题给色标加一圈表面文字色的边，任何颜色的色标都看得见。

**自己写主题时注意。** 一个主题只要写了任何一条 `TyTrackThumb` 规则，默认主题里这个键的整套规则就不再生效——变体类也在内。所以写了自己的 `TyTrackThumb` 的主题，要连 `.removing` 和 `.stop` 一起写，不然拖出去的滑块看起来和平常一样、浅色色标没有边。内置的 17 套主题都已经带上了；`classic` 的滑块是立体凸起，凸起的亮暗两边从色标自己的颜色算出来，总有一边看得清，所以它不写 `.stop`。

---

## 11. 与 TTyTrackBar 的区别

1. **没有 `Position`**：值在 `ThumbValues` / 集合项里。读数（`ShowValue`）显示选中滑块的值。
2. **没有 `SelStart` / `SelEnd`**：要高亮一段就用 `TTyRangeTrackBar` 的区间（同一个主题键），而且用户拖得动。
3. **没有位置动画**：键盘和滚轮改值时滑块直接跳到新位置。
4. **右到左（RTL）不镜像**，与 `TTyTrackBar` 一致：值轴只看 `Orientation` 和 `Reversed`。整个滑块家族的 RTL 以后一起做。
5. 刻度、刻度标签、凹槽、滑块的尺寸和位置都与 `TTyTrackBar` 共用同一套函数：一个值为 V 的滑块，画出来和 `Position = V` 的 `TTyTrackBar` 一模一样。

---

## 12. 与最初设计的出入

下面几处和 #36 最初的设计不同，按实现为准：

1. **「将被删除」是变体类 `TyTrackThumb.removing`，不是状态 `:removing`。** 样式系统的状态是固定的几个，新加的状态不会被应用。
2. **淡出由控件自己做。** 画家的 `opacity` 只作用于整次绘制，所以控件把 `.removing` 解析出的 `opacity` 乘到这个滑块的颜色上。自绘滑块（`OnDrawThumb` 接管）时要自己画，判断用 `RemovingThumb`。
3. **区间控件的「加删」开关叫 `AllowUserRanges`**，和多值控件的 `AllowUserThumbs` 是同一套机制；区间控件不发布 `MinThumbs` / `MaxThumbs`。区间被拖出时高亮段沿用 `.removing` 的 `opacity`，没有单独的主题键。
4. **`AllowCrossing` 只管用户。** 代码写值仍然夹在邻居之间，不改变项的顺序。
5. **渐变的混色不做 gamma 校正**，按 sRGB 各通道线性插值，`GradientFill` 在只有首尾两个色标时会重复第一个色标（第 4 节）。
6. **新增 `RemovingThumb`**（public，只读），给自绘用；**新增 `TyTrackThumb.stop`**，让色标在任何颜色下都有边。

---

## 13. 代码示例

```pascal
uses
  tyControls.MultiTrackBar;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  // 两个价格区间，至少隔 5；用户可以加区间、整段拖动、拖出一端删掉
  Price := TTyRangeTrackBar.Create(Self);
  Price.Parent := Self;
  Price.SetBounds(16, 16, 300, 24);
  Price.MinGap := 5;
  Price.AllowUserRanges := True;
  Price.DraggableRanges := True;
  Price.Ranges.BeginUpdate;
  try
    Price.Ranges.Clear;
    with Price.Ranges.Add do begin Low := 10; High := 30; end;
    with Price.Ranges.Add do begin Low := 60; High := 85; end;
  finally
    Price.Ranges.EndUpdate;
  end;
  Price.OnChange := @PriceChange;

  // 渐变编辑器：默认黑到白，加一个红色色标
  Stops := TTyGradientTrackBar.Create(Self);
  Stops.Parent := Self;
  Stops.SetBounds(16, 56, 300, 24);
  Stops.Thumbs.BeginUpdate;
  try
    with Stops.Thumbs.Add do begin Value := 50; Color := clRed; end;
  finally
    Stops.Thumbs.EndUpdate;
  end;
end;

procedure TMainForm.PriceChange(Sender: TObject);
var
  i: Integer;
  s: string;
begin
  s := '';
  for i := 0 to Price.Ranges.Count - 1 do
    s := s + Format('%d..%d ', [Price.Ranges[i].Low, Price.Ranges[i].High]);
  Caption := s;
end;
```

完整可运行示例见 `examples/trackbar/`。
