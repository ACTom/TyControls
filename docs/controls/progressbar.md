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
| `Step` | `Integer` | `10` | **（API parity 新增）** `StepIt` 一次前进多少（LCL `comctrls.pp:1853`，同默认）。不夹负值：倒数的进度条是合法用法。 |
| `BarShowText` | `Boolean` | `False` | **（API parity 新增）** 在条内画出进度文字（那个“47%”）。早前只能另外放一个标签自己同步，尽管同库的 `TTyGauge` / `TTyCircularProgress` / `TTyTrackBar` 早就会画自己的值。LCL：`comctrls.pp:1855`。 |
| `BarTextFormat` | `string` | `'%p%%'` | **（API parity 新增）** 读数模板：`%v` = `Position`、`%l` = `Min`、`%u` = `Max`、`%p` = 百分比、`%%` = 一个百分号。LCL 把 `'%v from [%l-%u] (=%p%%)'` 写死在 gtk 接口里（`include/progressbar.inc:48`）且不可改；这里默认就是人们真正想要的百分比，并且可改。 |
| `AnimationsEnabled` | `Boolean` | `True` | **（API parity 新增 published）** 控制 Position 变化时填充段的缓动动画（约 120 ms，EaseOutCubic）；关闭或无头环境瞬时跳变。 |
| `OnChange` | `TNotifyEvent` | `nil` | **（API parity 新增）** `Position` / `Min` / `Max` 实际变化后触发；同值赋值不触发。 |
| `Align` | `TAlign` | — | 父容器内的停靠方式。 |
| `Anchors` | `TAnchors` | — | 锚点布局。 |
| `StyleClass` | `string` | `''` | CSS 变体类名。 |
| `Controller` | `TTyStyleController` | `nil`（全局默认） | 关联的样式控制器。 |

> **注意：** `TTyProgressBar` 本身无键盘 / 鼠标交互（纯展示控件），但**（API parity 新增）** 现提供 `OnChange` 事件，于 `Position` / `Min` / `Max` 实际变化时触发。它继承自 `TTyGraphicControl`，因此仅暴露 **Tier A** 基线事件（鼠标 / 通用），**无** Tier B 键盘 / 焦点事件——见 [../events.md](../events.md)。

### 继承的通用成员

TTyProgressBar 继承自 `TTyGraphicControl`（`tyControls.Base`）的样式解析机制。

---

## 4. 方法与事件

`TTyProgressBar` 没有公开的交互方法。**（API parity 新增）** 它现在提供一个 `OnChange: TNotifyEvent` 事件，在 `Position` / `Min` / `Max` 实际变化（通过属性写入）后触发；同值赋值不触发。除此之外的行为均通过写入属性触发重绘来实现。

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

## 附：API parity 补齐（本轮）

### 四个填充方向

`TTyProgressOrientation` 现在有 LCL `TProgressBarOrientation`（`comctrls.pp:1801`）的全部四个值：

| 值 | 填充方向 | 圆角侧 |
|------|----------|--------|
| `tpoHorizontal`（默认） | 左 → 右 | 左侧两角 |
| `tpoVertical` | 下 → 上 | 底部两角 |
| `tpoRightToLeft` | 右 → 左 | 右侧两角 |
| `tpoTopDown` | 上 → 下 | 顶部两角 |

后两个早前根本取不到，于是 RTL 版面的进度条与“排空/倒计时”表计都画不出来。枚举标识符与 LCL 不同（`tpo*` vs `pb*`），这是全库的命名约定；它是编译期报错的响亮失败，不是静默的错答案。

### StepIt / StepBy

```pascal
procedure StepIt;                  // Position += Step（夹紧到 [Min,Max]）
procedure StepBy(ADelta: Integer); // Position += ADelta（同样夹紧）
function  BarText: string;         // 已填好的读数文字
```

`for i := 1 to n do begin Work; Bar.StepIt; end` 这个惯用循环早前没有对应物。两者都走 `Position` setter，所以夹紧、重绘、缓动与 `OnChange` 与直接赋值完全一致——LCL 的 `StepIt` 绕过了自己的 setter（`progressbar.inc:237`），代价是它不发通知。

`BarText` 是 public 的，宿主可以把同一串字放到状态栏里，不必重新推导一遍。

### 读数的墨色从哪里来

没有任何颜色写在控件里：主题给 `TyProgressBar` 声明了 `color` 就用它，没声明就回退到每个主题都定义的弱化墨色 `TyTextHint`。（目前随库发布的主题都没有给 `TyProgressBar` 写 `color`，而未声明的 `TextColor` 会解析成 `$00000000`——alpha 0——正是 `TTyTrackBar.ShowValue` 曾经“留了位置却什么也没画”的原因。）想自定义，在 `.tycss` 里给 `TyProgressBar` 写 `color` 即可。

### 不做：`Style = pbstMarquee` 与 `Smooth`

- **`Style`（确定/不确定）** 在本库是另一个控件：`TTyActivityBar`（它的头注释就写着“`TTyProgressBar` 的不确定兄弟”）。本轮**未**把它并回来，所以 `ProgressBar1.Style := pbstMarquee` 仍然无法工作，且一个控件不能在运行时两种模式互切（“先不知道总大小、后来知道了”的下载正需要这个）。
- **`Smooth`（连续/分段填充）** 不作为属性提供：LCL 那边它只是转给原生部件的一个请求（Win32 的 `PBS_SMOOTH`），在没有该能力的 widgetset 上什么也不做；对一个自绘控件而言“连续还是分段”是材质决定，属于皮肤引擎，不应该是控件上的一个布尔。
