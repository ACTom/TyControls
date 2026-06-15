# TTyProgressBar — API 参考

## 1. 概述

`TTyProgressBar` 是 TyControls 库中的主题化进度条控件，继承自 `TTyGraphicControl`（因此是非可交互的纯展示控件，无焦点、无鼠标交互）。控件根据 `Min`、`Max`、`Position` 三个属性计算填充段的宽度比例，然后绘制轨道背景和进度填充段。`Position` 赋值时自动夹取到 `[Min, Max]` 范围内。

该单元同时导出纯函数 `TyProgressFillRect`，可在自绘场景中单独使用。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ProgressBar` |
| typeKey（轨道） | `TyProgressBar` |
| typeKey（填充段） | `TyProgressFill` |
| 基类 | `TTyGraphicControl`（继承自 `TGraphicControl`，非可交互） |
| 默认尺寸 | 200 × 20（逻辑像素） |

```pascal
uses tyControls.ProgressBar;
```

---

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Min` | `Integer` | `0` | 进度最小值。赋值时若 `Position < Min` 则自动夹紧 `Position := Min`，然后触发重绘。 |
| `Max` | `Integer` | `100` | 进度最大值。赋值时若 `Position > Max` 则自动夹紧 `Position := Max`，然后触发重绘。 |
| `Position` | `Integer` | `0` | 当前进度值，范围 `[Min, Max]`。赋值时自动夹紧；若夹紧后值未变化则不触发重绘。 |
| `Align` | `TAlign` | — | 父容器内的停靠方式。 |
| `Anchors` | `TAnchors` | — | 锚点布局。 |
| `StyleClass` | `string` | `''` | CSS 变体类名。 |
| `Controller` | `TTyStyleController` | `nil`（全局默认） | 关联的样式控制器。 |

> **注意：** `TTyProgressBar` 无 `OnChange` 事件，也无任何键盘或鼠标交互；它是纯展示控件。

### 继承的通用成员

TTyProgressBar 继承自 `TTyGraphicControl`（`tyControls.Base`）的样式解析机制。

---

## 4. 方法与事件

`TTyProgressBar` 没有公开的交互方法或事件。所有行为通过写入属性触发重绘来实现。

### 独立几何函数

#### `function TyProgressFillRect(const ATrack: TRect; AMin, AMax, APosition: Integer): TRect`

纯函数，无副作用，根据参数计算填充段在轨道矩形内的像素范围。

**算法：**

- `Travel := AMax - AMin`；若 `Travel <= 0`（退化情形），返回宽度为 0 的矩形（`Right = Left`）。
- `Pos0 := APosition - AMin`：
  - `Pos0 <= 0`：返回宽度为 0 的矩形（空填充）。
  - `Pos0 >= Travel`：返回整个轨道矩形（满填充）。
  - 正常情形：`FillW := (TrackW * Pos0) div Travel`，`Result.Right := ATrack.Left + FillW`。

```pascal
// 直接使用示例（自绘场景）
uses tyControls.ProgressBar;

var
  Track: TRect;
  Fill: TRect;
begin
  Track := Rect(0, 0, 200, 20);
  Fill := TyProgressFillRect(Track, 0, 100, 35);
  // Fill.Right - Fill.Left = 70（35% 进度，200px 轨道）
  Canvas.FillRect(Fill);
end;
```

---

## 5. 状态与主题

### 轨道：typeKey `TyProgressBar`

`TTyProgressBar` 是 `TTyGraphicControl`，没有焦点和鼠标交互状态，始终处于 `tysNormal`（正常）状态。

| 状态 | 适用性 |
|------|--------|
| `:disabled` | `Enabled = False` 时（仍可设置，但此控件无交互，通常不用） |

### 填充段：typeKey `TyProgressFill`

填充段始终以无状态（`[]`）解析样式，使用 `TyProgressFill { }` 基础规则。

### light.tycss 示例规则

```css
TyProgressBar {
  background: darken(--surface, 8%);
  border-color: var(--border);
  border-width: 1px;
  border-radius: var(--radius);
}
TyProgressBar:disabled { opacity: 0.5; }   /* 禁用半透明（Batch ④，状态等价性） */

TyProgressFill {
  background: var(--accent);
  border-radius: var(--radius);
}
```

> **`:disabled`（Batch ④）：** `TyProgressBar` 现支持 `:disabled` 伪类，与 `TyScrollBar` / `TyTrackBar` / `TyTabControl` 一道补齐状态等价性。虽然进度条无交互，但仍可在父级随表单禁用时让进度条随之变淡，外观与其余控件一致。

### 部分填充只圆起始角（Batch ④）

填充段的圆角按填充比例分两种绘制：

- **满填充**（`Position >= Max`）：填充块与轨道首尾齐平，四角都用 `TyProgressFill` 的 `border-radius` 圆角。
- **部分填充**（`Position < Max`）：填充块**左对齐**，其前缘（右边）落在轨道中段。此时只圆**起始(左)的两角**（左上、左下），保留**前缘(右边)直角**——否则未到尾的填充会看起来像一颗悬浮的胶囊。换言之只有起点跟随轨道圆角，进度的"当前位置"边是平的。

---

## 6. 状态过渡动画（batch⑤+⑥）

`TTyProgressBar` 支持填充段在 `Position` 改变时**平滑过渡**到新比例，由 `tyControls.Animation` 单元的 `TTyAnimator` 驱动。

### 开关属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `AnimationsEnabled` | `Boolean` | `True` | 是否启用填充段位置过渡动画。**public 属性，不 published**（不写入 `.lfm`），需在代码中设置。 |

> 这是唯一的动画开关，**没有**单独的时长 / 缓动曲线属性可供配置——时长与缓动在控件内部固定。

### 行为

- **启用（`True`，默认）且控件已分配窗口句柄（`HandleAllocated`）时：** 改变 `Position` 时填充段从旧值**缓动**（ease）到新值，而非瞬间跳变；一次过渡约 **120ms**，缓动曲线 `teEaseOutCubic`（`1 - (1 - t)³`，先快后慢）。
- **关闭（`False`）：** 改变 `Position` 时填充段**瞬间**跳到新宽度。
- 控件尚无窗口句柄（headless / 设计器）时，无论开关如何都**瞬间吸附到终态**（**headless-snap**）——因此既有的逐像素填充测试不受影响。
- 内部按需创建一个 `TTimer`（约 60fps）推进动画，抵达目标后自动停止；`TTyAnimator` 不持有时钟，只接受显式毫秒步进，故动画逻辑可在测试中确定性驱动。

```pascal
var PB: TTyProgressBar;
PB := TTyProgressBar.Create(Self);
PB.Parent := Self;
// AnimationsEnabled 默认即为 True（填充缓动到新 Position）；
// 如需瞬时更新可显式关闭：PB.AnimationsEnabled := False;
PB.Position := 60;   // 填充平滑增长到 60%（约 120ms）
```

---

## 7. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.ProgressBar;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

// 创建进度条
var PB: TTyProgressBar;
PB := TTyProgressBar.Create(Self);
PB.Parent := Self;
PB.SetBounds(24, 24, 300, 20);
PB.Min := 0;
PB.Max := 100;
PB.Position := 0;

// 模拟进度更新（例如在 OnTimer 中）
procedure TMainForm.TimerTick(Sender: TObject);
begin
  if PB.Position < PB.Max then
    PB.Position := PB.Position + 5
  else
    Timer1.Enabled := False;
end;
```

完整可运行示例参见 `examples/progressbar/umain.pas`。

---

## 8. 注意事项

1. **纯展示控件：** `TTyProgressBar` 继承自 `TTyGraphicControl`（而非 `TTyCustomControl`），无 `TabStop`，不参与焦点循环，不处理任何键盘或鼠标事件。
2. **Position 自动夹紧：** `SetPosition` 在内部将值夹取到 `[Min, Max]`，赋值超界不报错也不触发异常，夹紧后若值未变化则不触发重绘。
3. **Min/Max 改变时 Position 自动校正：** 修改 `Min` 或 `Max` 会无声地校正 `Position`（不触发 `OnChange`，因为此控件没有 `OnChange`），然后触发 `Invalidate`。
4. **退化情形：** 当 `Max <= Min` 时，`TyProgressFillRect` 返回宽度为 0 的矩形，即进度条始终显示空。
5. **填充段圆角：** `TyProgressFill` 的 `border-radius` 只影响填充块本身的圆角，不受 `TyProgressBar` 的圆角约束；若两者不一致，填充块可能超出轨道圆角范围，需在主题中手动对齐。**部分填充**时只圆起始(左)两角、保留前缘(右)直角（见上文“部分填充只圆起始角”）；**满填充**时四角都圆。
6. **填充过渡动画（batch⑤+⑥）：** `AnimationsEnabled` 默认 `True`，有窗口句柄时改变 `Position` 会让填充缓动到新比例（约 120ms，`teEaseOutCubic`）；headless / 设计器下瞬间吸附到终态，逐像素测试不受影响。详见上文「状态过渡动画」。
