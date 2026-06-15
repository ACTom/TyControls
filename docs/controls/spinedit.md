# TTySpinEdit — API 参考

## 1. 概述

`TTySpinEdit` 是 TyControls 库中的主题化**可内联编辑的整数微调控件**，继承自 `TTyCustomControl`。控件显示一个整数值，右侧有上/下两个小箭头按钮。用户既可以**直接键入数字与前导 `-`**（轻量内联编辑缓冲，无选区/剪贴板），也可以点击箭头按钮、使用上/下方向键、或滚动鼠标滚轮来按 `Increment` 步进改变 `Value`。`Enter` 或失焦时**提交**编辑缓冲（解析 → 夹紧 `[MinValue, MaxValue]` → 写 `Value`）；`Esc` **还原**到当前 `Value`；非法输入（空串或仅 `-`）提交时退回当前 `Value`。值始终被夹紧到 `[MinValue, MaxValue]` 区间，`Value` 真实变化时触发 `OnChange`。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.SpinEdit` |
| typeKey | `TySpinEdit` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸 | 120 × 28（逻辑像素） |

```pascal
uses tyControls.SpinEdit;
```

---

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `MinValue` | `Integer` | `0` | 最小值。赋值时若 `Value < MinValue` 则静默夹紧，触发重绘（不触发 `OnChange`）。 |
| `MaxValue` | `Integer` | `100` | 最大值。赋值时若 `Value > MaxValue` 则静默夹紧，触发重绘（不触发 `OnChange`）。 |
| `Value` | `Integer` | `0` | 当前值，范围 `[MinValue, MaxValue]`，赋值时自动夹紧；若值真正变化则触发 `OnChange` 和重绘。 |
| `Increment` | `Integer` | `1` | 每步步进量。赋值小于 1 时被强制置为 1。 |
| `OnChange` | `TNotifyEvent` | `nil` | `Value` 真实变化时触发（含箭头按钮、方向键、滚轮、直接赋值）。 |
| `TabStop` | `Boolean` | `True` | 是否参与 Tab 键导航（构造时自动置为 `True`）。 |
| `Align` | `TAlign` | — | 父容器内的停靠方式。 |
| `Anchors` | `TAnchors` | — | 锚点布局。 |
| `StyleClass` | `string` | `''` | CSS 变体类名。 |
| `Controller` | `TTyStyleController` | `nil`（全局默认） | 关联的样式控制器。 |
| `OnClick` | `TNotifyEvent` | `nil` | 鼠标点击时触发。 |

### 继承的通用成员

TTySpinEdit 继承自 `TTyCustomControl`（`tyControls.Base`）的通用状态机制。

---

## 4. 几何辅助函数

```pascal
function TySpinUpButtonRect(const ALocal: TRect; APPI: Integer): TRect;
function TySpinDownButtonRect(const ALocal: TRect; APPI: Integer): TRect;
```

返回上/下箭头按钮在给定客户区矩形 `ALocal` 中的像素矩形（以 `APPI` 为 DPI 基准）。按钮宽度为 `MulDiv(18, APPI, 96)`（贴齐控件右缘），上下按钮各占客户区高度的一半。例如在 120 × 28、96 DPI 下：上按钮 `Rect(102, 0, 120, 14)`、下按钮 `Rect(102, 14, 120, 28)`。

这两个函数是纯几何函数（无副作用），既用于渲染也用于命中测试，可在测试中直接断言。

---

## 5. 键盘与交互

| 操作 | 行为 |
|------|------|
| 数字键 `0`–`9` | 在光标处插入数字字符，更新内联编辑缓冲，重绘 |
| `-` | 仅在光标位于位置 0 且缓冲中尚无 `-` 时插入（允许键入负数），其余位置忽略 |
| `←` | 光标左移一码点（到达缓冲开头后停止） |
| `→` | 光标右移一码点（到达缓冲末尾后停止） |
| `Home` | 光标移到缓冲开头 |
| `End` | 光标移到缓冲末尾 |
| `Backspace` | 删除光标前一码点 |
| `Delete` | 删除光标后一码点 |
| `Enter` | **提交**：将缓冲解析为整数（`StrToIntDef`，无法解析时退回当前 `Value`）→ 夹紧 `[MinValue, MaxValue]` → 写入 `Value`（若变化则触发 `OnChange`）→ 回填缓冲 |
| `Esc` | **还原**：丢弃编辑缓冲，重新同步到当前 `Value`（`SyncBufferToValue`），重绘；不触发 `OnChange` |
| `↑`（Up） | `Value += Increment`（到达 `MaxValue` 后停止），同步回填缓冲，消费按键 |
| `↓`（Down） | `Value -= Increment`（到达 `MinValue` 后停止），同步回填缓冲，消费按键 |
| 鼠标左键点击上箭头 | `Value += Increment`，同步回填缓冲 |
| 鼠标左键点击下箭头 | `Value -= Increment`，同步回填缓冲 |
| 鼠标滚轮向上 | `Value += Increment`，同步回填缓冲 |
| 鼠标滚轮向下 | `Value -= Increment`，同步回填缓冲 |
| 失焦（`DoExit`） | 等同 `Enter`：自动提交当前缓冲 |

> **注意：** 当 `Enabled = False` 时，`KeyDown` 不消费按键、`DoMouseWheel` 返回 `False`、`MouseDown` 直接返回——即禁用状态下所有输入都不生效。滚轮处理会先调用 `inherited`（即用户的 `OnMouseWheel`），若用户已消费事件则不再步进。

---

## 6. 状态与主题：typeKey `TySpinEdit`

| 状态 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停在控件上 |
| `:focus` | 获得键盘焦点 |
| `:disabled` | `Enabled = False` |

上/下箭头使用 `TTyPainter.DrawGlyph` 以 `tgArrowUp` / `tgArrowDown` 字形绘制（tier-b 单色字形），颜色取自解析样式的 `TextColor`。获得焦点时在编辑缓冲的光标位置绘制 1px 竖条光标，以约 530 ms 间隔**闪烁**（`TTimer` 懒创建，无头测试与设计器中光标保持静态）。

**数值文字字号由主题 `font-size` 决定（Batch ④）：** 数值文字与光标定位统一经 `ResolveFontSize(S)` 取字号——优先用主题 `TySpinEdit { font-size }`（内置 9px），其次 `Font.Size`，再退到默认 9。绘制（`DrawText`）与光标横坐标测量（`CaretPixelX`）共用同一字号，保证光标始终对齐。早前写死的孤立字号 12 已移除。

### light.tycss 示例规则

```css
TySpinEdit {
  background: var(--surface);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: 1px;
  border-radius: var(--radius);
  padding: 4px;
  font-size: 10px;
}
TySpinEdit:hover    { border-color: darken(--border, 10%); }
TySpinEdit:focus    { border-color: var(--accent); }
TySpinEdit:disabled { opacity: 0.5; }
```

---

## 7. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.SpinEdit;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

// 创建微调控件
var SE: TTySpinEdit;
SE := TTySpinEdit.Create(Self);
SE.Parent := Self;
SE.SetBounds(24, 24, 120, 28);
SE.MinValue := 0;
SE.MaxValue := 100;
SE.Increment := 5;
SE.Value := 10;
SE.OnChange := @OnSpinChange;

procedure TMainForm.OnSpinChange(Sender: TObject);
begin
  with Sender as TTySpinEdit do
    Label1.Caption := Format('当前值：%d', [Value]);
end;
```

完整可运行示例参见 `examples/spinedit/umain.pas`。

---

## 8. 注意事项

1. **值始终夹紧：** 任何修改 `Value` 的路径（属性赋值、按钮、方向键、滚轮、`Enter`/失焦提交）都通过同一 setter，自动夹紧到 `[MinValue, MaxValue]`。
2. **OnChange 防重入：** setter 先夹紧值，若夹紧后与原值相同则不调用 `OnChange`，回调中无需过滤重复值。
3. **Min/Max 修改时 Value 静默校正：** 修改范围后 `Value` 会被自动校正到新区间，但**不**触发 `OnChange`（仅触发 `Invalidate`）。
4. **Increment 下限为 1：** 给 `Increment` 赋小于 1 的值会被强制置为 1。
5. **按钮几何固定：** 上/下箭头按钮宽度固定为 18 逻辑像素（DPI 缩放后）、贴齐右缘，各占高度一半，不可通过属性调整。
6. **内联编辑缓冲轻量：** 编辑缓冲（`FEditText`/`FCaret`）无选区、无剪贴板、无撤销栈；步进操作（方向键/滚轮/按钮）总是立即提交并回填缓冲，不经过缓冲层。
7. **非法输入安全退回：** 提交时若缓冲为空串或仅含 `-`（`StrToIntDef` 返回当前 `FValue` 作为默认值），则 `Value` 不变、`OnChange` 不触发，缓冲回填为当前 `Value` 的字符串表示。
8. **光标闪烁：** 聚焦时以约 530 ms 间隔启动；`TTimer` 懒创建，仅在 `HandleAllocated` 后启动，无头测试与设计器中光标静态。
9. **I-beam 光标（batch⑤+⑥）：** 构造时把 `Cursor` 设为 `crIBeam`，鼠标移到控件上时呈现标准的文本输入「I 形」光标，提示内联数字编辑区可直接键入。
