# TTyTrackBar — API 参考

## 1. 概述

`TTyTrackBar` 是 TyControls 库中的主题化滑块控件，继承自 `TTyCustomControl`。控件显示一条水平轨道，轨道上有一个可拖动的滑块（thumb）。用户可以鼠标拖动滑块、点击轨道任意位置、或使用左右方向键来改变 `Position` 值；`OnChange` 在值变化时触发。

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
| `OnChange` | `TNotifyEvent` | `nil` | `Position` 真实变化时触发（含拖动、点击定位、方向键步进、直接赋值）。 |
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

返回滑块在控件客户区坐标系中的当前像素矩形（以 `Font.PixelsPerInch` 为 DPI 基准）。滑块宽度固定为 12 逻辑像素（DPI 缩放后）；高度等于控件高度。

算法：

- `TW := MulDiv(12, PPI, 96)`（滑块宽度）
- `Tr := ClientWidth - TW`（滑动行程）
- `ThumbLeft := (Tr × (Position - Min) + (Max - Min) div 2) div (Max - Min)`（四舍五入）
- 返回 `Rect(ThumbLeft, 0, ThumbLeft + TW, ClientHeight)`

#### `procedure DragTo(AXAlongTrack: Integer)`

将滑块中心对齐到 `AXAlongTrack` 处，计算新的 `Position` 并赋值（触发夹紧和 `OnChange`）。通常在拖动或点击事件中调用。

---

## 5. 键盘与交互

| 操作 | 行为 |
|------|------|
| `←`（Left） | `Position -= 1`（到达 `Min` 后停止） |
| `→`（Right） | `Position += 1`（到达 `Max` 后停止） |
| 鼠标左键按下 | 立即调用 `DragTo(X)`，定位到点击位置并开始拖动 |
| 鼠标拖动 | 持续调用 `DragTo(X)` |
| 鼠标左键释放 | 结束拖动 |

> **注意：** 修饰键（Ctrl/Alt/Meta）与左右键组合时，`KeyDown` 不消费该按键（允许通过），以免干扰系统级快捷键。

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
TyTrackBar:focus { border-color: var(--accent); border-width: 1px; }

TyTrackThumb { background: var(--border); border-radius: 4px; }
TyTrackThumb:hover  { background: darken(--border, 10%); }
TyTrackThumb:active { background: var(--accent); }
```

---

## 7. 代码示例

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

## 8. 注意事项

1. **ThumbRect 坐标系：** `ThumbRect` 返回的是**控件客户区坐标**（左上角为 `(0,0)`），不是屏幕坐标。
2. **拖动跨出边界：** 鼠标移出控件范围时，`MouseLeave` 不会终止拖动（仅清除 hover 状态），这使得"按住不放，拖出后再拖回"的体验连贯。拖动只在 `MouseUp` 时结束。
3. **OnChange 防重入：** `SetPosition` 先夹紧值，若夹紧后与原值相同则不调用 `OnChange`，回调中无需过滤重复值。
4. **Min/Max 修改时 Position 静默校正：** 修改范围后 `Position` 会被自动校正，但不触发 `OnChange`（仅触发 `Invalidate`）。
5. **滑块宽度固定：** 滑块宽度固定为 12 逻辑像素（DPI 缩放后），不可通过属性调整。如需更宽的滑块，需继承并重写渲染逻辑。
