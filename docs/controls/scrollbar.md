# TTyScrollBar — API 参考

## 1. 概述

`TTyScrollBar` 是 TyControls 库中的滚动条控件，支持垂直和水平两种方向。控件自绘轨道背景和滑块（thumb），通过 `TyScrollThumbRect` 纯函数计算 thumb 的几何位置，无需外部状态。`OnChange` 仅在 `Position` 真正发生变化时触发，防止冗余通知。

`TyScrollThumbRect` 是该单元导出的独立几何工具函数，可在自绘场景中单独使用。

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ScrollBar` |
| typeKey（轨道 / 端部箭头） | `TyScrollBar` |
| typeKey（滑块子部件） | `TyScrollThumb` |
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
| `PageSize` | `Integer` | `10` | 页面大小（可见内容大小），决定 thumb 在轨道中的比例长度。不可为负（负值被夹为 0）。同时也是点击轨道空白处和 `PageUp`/`PageDown` 的步进量。 |
| `SmallChange` | `Integer` | `1` | 单步步进量：点击端部箭头按钮、按方向键各步进 ±`SmallChange`。最小为 1（赋值 <1 被夹为 1）。 |
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

### 端部箭头按钮与交互

控件在轨道两端各渲染一个箭头按钮（垂直：顶/底；水平：左/右）。为给按钮腾出空间，**轨道（track）从客户区两端各内缩一个按钮尺寸**：

- 按钮尺寸 = 轨道横向厚度（`TyScrollButtonSize`：垂直取宽度，水平取高度）。
- 轨道矩形由 `TyScrollTrackRect(Client, Kind, ButtonSize)` 计算；thumb 与点击命中均基于内缩后的轨道。
- **退化：** 当控件主轴长度 `<= 2 × 按钮尺寸`（太短放不下两个按钮）时，不保留箭头带，整个客户区都是轨道。

鼠标交互（`MouseDown`，仅左键）：

| 命中位置 | 行为 |
|----------|------|
| 端部箭头按钮（Lo / Hi） | `Position ∓= SmallChange`（Lo 减、Hi 加），并尝试 `SetFocus` |
| thumb 本体 | 开始拖动（`BeginThumbDrag` + `MouseCapture`） |
| 轨道空白处（thumb 之外） | 朝点击方向翻一页 `Position ∓= PageSize` |

### 键盘操作

控件需获得焦点才响应（`TabStop` 默认 `False`，参见注意事项）。每个被处理的按键消费后不再传递（`Key := 0`）。

| 按键 | 行为 |
|------|------|
| `↑` / `↓`（垂直） | `Position ∓= SmallChange`（↑ 减、↓ 加） |
| `←` / `→`（水平） | `Position ∓= SmallChange`（← 减、→ 加） |
| `PageUp`（VK_PRIOR） | `Position -= PageSize` |
| `PageDown`（VK_NEXT） | `Position += PageSize` |
| `Home`（VK_HOME） | `Position := Min` |
| `End`（VK_END） | `Position := Max` |

> 方向键按 `Kind` 区分主轴：垂直用 `↑`/`↓`，水平用 `←`/`→`。所有步进结果都经 `SetPosition` 钳制到 `[Min, Max]`。

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

#### `function TyScrollButtonSize(...): Integer` / `function TyScrollTrackRect(...): TRect`

```pascal
function TyScrollButtonSize(const AClient: TRect; AKind: TTyScrollBarKind): Integer;
function TyScrollTrackRect(const AClient: TRect; AKind: TTyScrollBarKind;
  AButtonSize: Integer): TRect;
```

两个导出的纯几何函数，配合端部箭头按钮使用：`TyScrollButtonSize` 返回箭头按钮的尺寸（= 轨道横向厚度）；`TyScrollTrackRect` 返回从客户区两端各内缩一个按钮尺寸后的轨道矩形（主轴太短放不下两个按钮时返回整个客户区）。控件内部用它们定位 thumb 与命中检测，也可在自绘场景中单独调用。

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

### 支持的伪类状态（TyScrollBar 轨道）

| 伪类 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停在控件上 |
| `:focus` | 控件获得键盘焦点（绘制焦点环；ScrollBar 通常不参与 Tab，需显式获焦才出现） |
| `:active` | 鼠标左键按下 |
| `:disabled` | `Enabled = False`（统一施加 `opacity` 半透明，与其余控件状态一致） |

### light.tycss 内置规则

```css
TyScrollBar {
  background: darken(--surface, 6%);  /* 轨道背景 */
  color: var(--border);               /* 端部箭头墨色（tier-b 字形） */
  border-radius: 4px;
}
TyScrollBar:hover  { color: darken(--border, 15%); }
TyScrollBar:active { color: var(--accent); /* #3B82F6 */ }
TyScrollBar:focus    { outline: 2px var(--focus-ring); }   /* 焦点环 */
TyScrollBar:disabled { opacity: 0.5; }

/* 滑块由独立子部件 typeKey 着色（tier-a 着色面） */
TyScrollThumb        { background: var(--border); border-radius: 4px; }
TyScrollThumb:hover  { background: darken(--border, 15%); }
TyScrollThumb:active { background: var(--accent); }
```

### 渲染细节

- `DrawFrame` 绘制轨道背景（使用 `TyScrollBar` 的 `background`），并施加 `:focus` 焦点环、`:disabled` 的 `opacity`。
- **滑块（thumb）是独立子部件 typeKey `TyScrollThumb`**（tier-a 着色面）：渲染器解析 `TyScrollThumb` 的样式，用其 `background.Color` 构造 `tfkSolid` 填充、以其 `border-radius` 为圆角绘制 thumb 矩形——不再借用 `TyScrollBar` 的 `color`。`TyScrollThumb` 支持 `:hover` / `:active`，其内置默认（`var(--border)` / hover `darken(--border,15%)` / active `var(--accent)`、`border-radius:4px`）与旧版借用 `color` 时的渲染结果**逐字一致**，老主题升级后外观不变。
- **端部箭头**仍是 tier-b 单色字形，墨色取 `TyScrollBar` 的 `color`（`TextColor`）。要单独改箭头颜色，改 `TyScrollBar { color: … }`；要改滑块颜色，改 `TyScrollThumb { background: … }`。详见 [tycss-reference.md](../tycss-reference.md) §8.3。
- 没有内置命名变体（`.class`）。

## 6. 状态过渡动画（batch⑤+⑥）

`TTyScrollBar` 支持滑块（thumb）在 **程序化** `Position` 改变时平滑过渡到新位置，由 `tyControls.Animation` 单元的 `TTyAnimator` 驱动。

### 开关属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `AnimationsEnabled` | `Boolean` | `True` | 是否启用滑块位置过渡动画。**public 属性，不 published**（不写入 `.lfm`），需在代码中设置。 |

> 这是唯一的动画开关，**没有**单独的时长 / 缓动曲线属性可供配置——时长与缓动在控件内部固定。

### 行为

- **程序化变化才缓动：** 启用（`True`，默认）且有窗口句柄时，由**键盘 / 滚轮 / 点击轨道空白翻页 / 端部箭头**等引起的 `Position` 变化会让绘制的滑块从旧位置**缓动**到新位置（约 **120ms**，缓动曲线 `teEaseOutCubic`）。
- **拖动始终瞬时：** 用户**拖动滑块**（`DragThumbTo`）时滑块**实时跟手、不缓动**——拖拽期间绘制即贴当前位置，避免延迟感。
- **关闭（`False`）：** 所有 `Position` 变化都瞬间反映到滑块位置。
- 控件尚无窗口句柄（headless / 设计器）时，无论开关如何都**瞬间吸附到终态**（**headless-snap**）——因此既有的逐像素 thumb 几何测试不受影响。
- 内部按需创建一个 `TTimer`（约 60fps）推进动画，抵达目标后自动停止；动画逻辑可在测试中以显式毫秒步进确定性驱动。

> **NOTE — 内嵌滚动条按设计为静态：** `TTyListBox` 与 `TTyMemo` 内部惰性创建的滚动条在创建时被显式设为 `AnimationsEnabled := False`。这是**有意为之**：列表 / 多行编辑器的内容跟随滚动需要即时反馈，滑块缓动反而会与内容产生位置错位，因此内嵌滚动条始终瞬时跟随，不参与缓动。独立使用 `TTyScrollBar` 时默认启用缓动，不受此影响。

## 7. 代码示例

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

## 8. 注意事项

1. **OnChange 防重入：** `SetPosition` 先夹紧值，若夹紧后与原值相同则不调用 `OnChange`，无需在回调中过滤重复值。
2. **SetMin/SetMax 自动夹紧 Position：** 修改 `Min` 或 `Max` 时若导致 `Position` 越界，会静默调整 `Position`（不触发 `OnChange`，仅触发 `Invalidate`）。
3. **BeginThumbDrag 的坐标系：** `AGrabPosAlongTrack` 和 `APosAlongTrack` 均为**控件客户区坐标**，垂直时取鼠标 Y，水平时取鼠标 X，与控件的 `ClientRect` 基准一致。
4. **退化情形：** 当 `Max <= Min` 或 `PageSize <= 0` 时，`TyScrollThumbRect` 返回整个轨道矩形（thumb 填满），此时拖动无意义。
5. **TabStop：** ScrollBar 控件 `TabStop` 不在 `published` 列表中，默认继承 `TCustomControl` 的默认值（`False`），通常不参与焦点循环。
6. **水平时默认尺寸不自动翻转：** `Kind` 改变后，控件的宽/高不会自动对调，需手动交换 `Width` 和 `Height`。
7. **滑块过渡动画（batch⑤+⑥）：** `AnimationsEnabled` 默认 `True`，程序化 `Position` 变化（键盘/滚轮/翻页/箭头）时滑块缓动到新位置（约 120ms），**拖动则始终瞬时跟手**；headless / 设计器下瞬间吸附。`TTyListBox` / `TTyMemo` 的**内嵌滚动条按设计置为静态**（`AnimationsEnabled := False`）。详见上文「状态过渡动画」。
