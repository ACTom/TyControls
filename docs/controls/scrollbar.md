# TTyScrollBar — API 参考

## 1. 概述

`TTyScrollBar` 是 TyControls 库中的滚动条控件，支持垂直和水平两种方向。控件自绘轨道背景和滑块（thumb），通过 `TyScrollThumbRect` 纯函数计算 thumb 的几何位置，无需外部状态。`OnChange` 仅在 `Position` 真正发生变化时触发，防止冗余通知。

`TyScrollThumbRect` 是该单元导出的独立几何工具函数，可在自绘场景中单独使用。

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ScrollBar` |
| typeKey | `TyScrollBar` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸 | 16 × 160（垂直，逻辑像素） |

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Kind` | `TTyScrollBarKind` | `sbVertical` | 方向。`sbVertical`：竖向；`sbHorizontal`：横向。改变后触发 `Invalidate`。 |
| `Min` | `Integer` | `0` | 最小位置值。赋值时若 `Position < Min` 则自动夹紧 `Position := Min`。 |
| `Max` | `Integer` | `100` | 最大位置值。赋值时若 `Position > Max` 则自动夹紧 `Position := Max`。 |
| `Position` | `Integer` | `0` | 当前位置，范围 `[Min, Max]`。赋值时自动夹紧；仅在值真正变化时触发 `OnChange`。 |
| `PageSize` | `Integer` | `10` | 页面大小（可见内容大小），决定 thumb 在轨道中的比例长度。不可为负（负值被夹为 0）。 |
| `OnChange` | `TNotifyEvent` | `nil` | Position 真实变化时触发（包括 `DragThumbTo` 引起的变化）。 |
| `Align` | `TAlign` | — | 布局对齐方式。 |
| `Anchors` | `TAnchors` | — | 锚点布局。 |
| `StyleClass` | `string` | `''` | CSS 变体类名。 |
| `Controller` | `TTyStyleController` | `nil`（使用全局默认） | 关联的样式控制器。 |

### 类型定义

```pascal
TTyScrollBarKind = (sbHorizontal, sbVertical);
```

注意：枚举定义中 `sbHorizontal` 序数值为 0，`sbVertical` 为 1；但 `Kind` 属性的默认值为 `sbVertical`。

## 4. 方法与事件

### public 方法

#### `procedure BeginThumbDrag(AGrabPosAlongTrack: Integer)`

开始拖动 thumb。`AGrabPosAlongTrack` 是鼠标在轨道方向上的坐标（相对于控件客户区）：

- 计算当前 thumb 的像素起始位置（`ThumbStart`）。
- 记录抓取偏移：`FDragGrabOffset := AGrabPosAlongTrack - ThumbStart`。
- 设置 `FDragging := True`。

通常在 `OnMouseDown` 中调用，`AGrabPosAlongTrack` 传入 `Y`（垂直）或 `X`（水平）。

#### `procedure DragThumbTo(APosAlongTrack: Integer)`

拖动过程中更新位置。若 `FDragging = False` 则立即退出（无操作）。

计算逻辑：

1. 获取当前 thumb 的像素长度（`ThumbLen`）。
2. `FreeSpace := TrackLength - ThumbLen`（最小为 1）。
3. `NewTop := APosAlongTrack - FDragGrabOffset`，夹紧至 `[0, FreeSpace]`。
4. `NewPos := Min + (NewTop * (Max - Min)) div FreeSpace`。
5. 通过 `Position := NewPos` 赋值（自动夹紧并在变化时触发 `OnChange`）。

通常在 `OnMouseMove` 中调用。

#### `procedure EndThumbDrag`

结束拖动，仅将 `FDragging := False`。通常在 `OnMouseUp` 中调用。

#### `function GetStyleTypeKey: string`（override）

返回固定字符串 `'TyScrollBar'`。

### 独立几何函数

#### `function TyScrollThumbRect(...): TRect`

```pascal
function TyScrollThumbRect(const ATrack: TRect; AKind: TTyScrollBarKind;
  AMin, AMax, APosition, APageSize: Integer): TRect;
```

纯函数，无副作用，根据参数计算 thumb 在轨道矩形内的像素位置。

**算法：**

- `Span := (AMax - AMin) + APageSize`
- 退化条件（`Span <= 0` 或 `APageSize <= 0` 或 `AMax <= AMin`）：thumb 填满整个轨道，返回 `ATrack`。
- `ThumbLen := (APageSize * TrackLen) div Span`，夹紧至 `[1, TrackLen]`。
- `FreeSpace := TrackLen - ThumbLen`。
- `Travel := AMax - AMin`。
- `Pos0 := clamp(APosition - AMin, 0, Travel)`。
- `Offset := (Pos0 * FreeSpace) div Travel`（`Travel <= 0` 时 `Offset = 0`）。
- 垂直：`Result := Rect(Left, Top+Offset, Right, Top+Offset+ThumbLen)`。
- 水平：`Result := Rect(Left+Offset, Top, Left+Offset+ThumbLen, Bottom)`。

**Thumb 与轨道的比例关系：**

```
ThumbLen / TrackLen ≈ PageSize / (Max - Min + PageSize)
```

`PageSize` 越大，thumb 越长（代表可见内容比例大）；`Max - Min` 越大，thumb 越短。

### 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TNotifyEvent` | `Position` 属性值真实变化时（包括 `DragThumbTo` 间接触发） |

## 5. 状态与主题

### 状态

TTyScrollBar 继承 `TTyCustomControl` 的状态机制：

| 状态常量 | 触发条件 |
|----------|----------|
| `tysNormal` | 正常 |
| `tysHover` | 鼠标悬停在控件上 |
| `tysActive` | 鼠标左键按下 |
| `tysFocused` | 键盘焦点（TabStop 默认继承，但 ScrollBar 通常不设 TabStop） |
| `tysDisabled` | `Enabled = False` |

### light.tycss 内置规则

```css
TyScrollBar {
  background: darken(--surface, 6%);  /* 轨道背景 */
  color: var(--border);               /* thumb 颜色（通过 TextColor 渲染） */
  border-radius: 4px;
}
TyScrollBar:hover  { color: darken(--border, 15%); }
TyScrollBar:active { color: var(--accent); /* #3B82F6 */ }
```

### 渲染细节

- `DrawFrame` 绘制轨道背景（使用样式的 `background`）。
- Thumb 颜色来自当前样式的 **`TextColor`**（即 CSS `color` 属性）。渲染器构造一个 `tfkSolid` 填充，颜色 = `S.TextColor`，然后以 `S.BorderRadius` 圆角绘制 thumb 矩形。因此在 `.tycss` 中用 `color` 控制滑块颜色是正确的写法：

```css
TyScrollBar         { color: var(--border); }       /* 滑块默认颜色 */
TyScrollBar:hover   { color: darken(--border, 15%); }
TyScrollBar:active  { color: var(--accent); }
```

- 没有内置命名变体（`.class`）。

## 6. 代码示例

### 基本垂直滚动条

```pascal
uses tyControls.ScrollBar;

var
  SB: TTyScrollBar;
begin
  SB := TTyScrollBar.Create(Self);
  SB.Parent := Self;
  SB.Kind := sbVertical;
  SB.Left := 200;
  SB.Top := 10;
  SB.Width := 16;
  SB.Height := 200;
  SB.Min := 0;
  SB.Max := 90;    // 内容总行数 - 可见行数
  SB.PageSize := 10;
  SB.Position := 0;
  SB.OnChange := @OnScrollChange;
end;

procedure TForm1.OnScrollChange(Sender: TObject);
begin
  // 同步滚动内容
  MyListArea.TopRow := TTyScrollBar(Sender).Position;
end;
```

### 集成鼠标拖动

```pascal
procedure TForm1.ScrollBarMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then
    // 垂直时传 Y，水平时传 X
    FScrollBar.BeginThumbDrag(Y);
end;

procedure TForm1.ScrollBarMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
begin
  if ssLeft in Shift then
    FScrollBar.DragThumbTo(Y);
end;

procedure TForm1.ScrollBarMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FScrollBar.EndThumbDrag;
end;
```

### 直接使用 TyScrollThumbRect（自绘场景）

```pascal
uses tyControls.ScrollBar;

var
  Track: TRect;
  Thumb: TRect;
begin
  Track := Rect(0, 0, 16, 200);
  Thumb := TyScrollThumbRect(Track, sbVertical, 0, 90, 30, 10);
  // 在自己的 Canvas 上绘制 Thumb
  Canvas.FillRect(Thumb);
end;
```

## 7. 注意事项

1. **OnChange 防重入：** `SetPosition` 先夹紧值，若夹紧后与原值相同则不调用 `OnChange`，无需在回调中过滤重复值。
2. **SetMin/SetMax 自动夹紧 Position：** 修改 `Min` 或 `Max` 时若导致 `Position` 越界，会静默调整 `Position`（不触发 `OnChange`，仅触发 `Invalidate`）。
3. **BeginThumbDrag 的坐标系：** `AGrabPosAlongTrack` 和 `APosAlongTrack` 均为**控件客户区坐标**，垂直时取鼠标 Y，水平时取鼠标 X，与控件的 `ClientRect` 基准一致。
4. **退化情形：** 当 `Max <= Min` 或 `PageSize <= 0` 时，`TyScrollThumbRect` 返回整个轨道矩形（thumb 填满），此时拖动无意义。
5. **TabStop：** ScrollBar 控件 `TabStop` 不在 `published` 列表中，默认继承 `TCustomControl` 的默认值（`False`），通常不参与焦点循环。
6. **水平时默认尺寸不自动翻转：** `Kind` 改变后，控件的宽/高不会自动对调，需手动交换 `Width` 和 `Height`。
