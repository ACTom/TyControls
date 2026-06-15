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
| `Orientation` | `TTyTrackOrientation` | `toHorizontal` | 滑块方向：`toHorizontal`（水平，默认；左=Min、右=Max）/ `toVertical`（垂直）。**垂直约定：顶部为 `Max`，值向上增大**（即向上拖动/方向键增大 `Position`）。赋值时触发重绘。 |
| `Frequency` | `Integer` | `0` | 刻度线（tick marks）间隔，单位为值（value-units）。`0`（默认）= **不绘制刻度**；`>0` 时每隔 `Frequency` 个值单位绘制一条刻度线。负值被夹为 0。 |
| `LineSize` | `Integer` | `1` | 方向键单步步进量（每次 ±`LineSize`）。最小为 1（赋值 <1 被夹为 1）。 |
| `PageSize` | `Integer` | `10` | `PageUp`/`PageDown` 翻页步进量（每次 ±`PageSize`）。最小为 1（赋值 <1 被夹为 1）。 |
| `OnChange` | `TNotifyEvent` | `nil` | `Position` 真实变化时触发（含拖动、点击定位、方向键/翻页键步进、直接赋值）。 |
| `TabStop` | `Boolean` | `True` | 是否参与 Tab 键导航（构造时自动置为 `True`）。 |
| `Align` | `TAlign` | — | 父容器内的停靠方式。 |
| `Anchors` | `TAnchors` | — | 锚点布局。 |
| `StyleClass` | `string` | `''` | CSS 变体类名。 |
| `Controller` | `TTyStyleController` | `nil`（全局默认） | 关联的样式控制器。 |
| `OnClick` | `TNotifyEvent` | `nil` | 鼠标点击时触发（在完成定位后触发）。 |

### 继承的通用成员

TTyTrackBar 继承自 `TTyCustomControl`（`tyControls.Base`）的通用状态机制。

---

## 4. 方法与事件

### public 方法

#### `function ThumbRect: TRect`

返回滑块在控件客户区坐标系中的当前像素矩形（以 `Font.PixelsPerInch` 为 DPI 基准），**随 `Orientation` 切换主轴**。滑块沿主轴的厚度固定为 12 逻辑像素（DPI 缩放后）：

- **水平：** 主轴为宽度（`MainLen = ClientWidth`），滑块宽 12 逻辑像素、高 = `ClientHeight`，沿左右移动（左=Min、右=Max）。
- **垂直：** 主轴为高度（`MainLen = ClientHeight`），滑块高 12 逻辑像素、宽 = `ClientWidth`，沿上下移动；坐标系**反转**（`Inverted = True`），使顶部对应 `Max`、底部对应 `Min`。

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
| `PageUp`（VK_PRIOR） | — | — | `Position += PageSize`（**增大**，两种方向一致） |
| `PageDown`（VK_NEXT） | — | — | `Position -= PageSize`（减小，两种方向一致） |
| `Home`（VK_HOME） | — | — | `Position := Min` |
| `End`（VK_END） | — | — | `Position := Max` |
| 鼠标左键按下 | — | — | 立即定位到点击位置（水平按 X、垂直按 Y 调用 `DragTo`）并开始拖动 |
| 鼠标拖动 | — | — | 持续调用 `DragTo`（水平 X / 垂直 Y） |
| 鼠标左键释放 | — | — | 结束拖动 |

> **注意：** 垂直方向上 `↑` 增大、`↓` 减小（顶部=Max）；`PageUp` 始终增大、`PageDown` 始终减小，与方向无关。每个被处理的按键消费后不再传递（`Key := 0`）。

---

## 6. 状态与主题

### 轨道：typeKey `TyTrackBar`

| 状态 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停在控件上 |
| `:focus` | 获得键盘焦点 |
| `:active` | 鼠标左键按下（任意位置） |
| `:disabled` | `Enabled = False` |

### 滑块子部件：typeKey `TyTrackThumb`

滑块使用独立 typeKey `TyTrackThumb` 解析样式，状态如下：

| 状态 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停在滑块矩形内（非拖动时） |
| `:active` | 正在拖动中（`FDragging = True`） |
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
```

> **`:disabled`（Batch ④）：** `TyTrackBar` 现支持 `:disabled` 伪类，与 `TyScrollBar` / `TyTabControl` / `TyProgressBar` 一道补齐状态等价性——`Enabled = False` 时整条轨道（含滑块、刻度）按 `opacity` 统一变淡。滑块子部件 `TyTrackThumb`（tier-a 着色面）的颜色独立于轨道，详见 [tycss-reference.md](../tycss-reference.md) §8.3。

### 刻度线（ticks）

当 `Frequency > 0` 且 `Max > Min` 时，控件从 `Min` 起每隔 `Frequency` 个值单位绘制一条短刻度线，刻度对齐到该值下滑块中心所在的主轴位置（水平绘于轨道底缘、垂直绘于轨道右缘，长约 4 逻辑像素 / 粗 1 逻辑像素）。刻度颜色取轨道样式 `TyTrackBar` 的 `TextColor`（即 CSS `color`，主题驱动），可在 `.tycss` 中为 `TyTrackBar` 声明 `color` 控制刻度颜色。`Frequency = 0`（默认）时完全不绘制刻度。

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
5. **滑块沿主轴厚度固定：** 滑块沿主轴的厚度固定为 12 逻辑像素（DPI 缩放后），不可通过属性调整；横向尺寸跟随控件另一边（水平=控件高、垂直=控件宽）。如需更宽的滑块，需继承并重写渲染逻辑。
6. **垂直方向约定：** `Orientation = toVertical` 时，**顶部为 `Max`、底部为 `Min`，值向上增大**——向上拖动、`↑`、`PageUp` 都增大 `Position`。切换 `Orientation` 后控件宽/高不会自动对调，需手动交换尺寸（垂直通常应高大于宽）。
7. **刻度由 Frequency 驱动：** `Frequency = 0`（默认）不绘制刻度；`>0` 时每隔该值单位画一条刻度线，颜色取自主题 `TyTrackBar` 的 `color`。
8. **滑块过渡动画（batch⑤+⑥）：** `AnimationsEnabled` 默认 `True`，程序化 `Position` 变化（方向键/翻页/Home/End/赋值）时滑块缓动到新位置（约 120ms），**拖动 / 点击定位则始终瞬时跟手**；headless / 设计器下瞬间吸附。详见上文「状态过渡动画」。
