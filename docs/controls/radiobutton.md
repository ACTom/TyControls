# TTyRadioButton

## 1. 概述

TTyRadioButton 是 TyControls 库中的主题化单选按钮控件，继承自 `TTyCustomControl`。典型用途：在一组互斥选项中选择其一（如性别、颜色、方案），同一父容器（`Parent`）下的所有 `TTyRadioButton` 自动互斥——选中一个会取消同组其他选项。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.CheckBox`（与 `TTyCheckBox` 同一单元） |
| `GetStyleTypeKey` 返回值 | `'TyRadioButton'` |

在 `.tycss` 文件中，该控件对应的选择器前缀为 `TyRadioButton`。

```pascal
uses tyControls.CheckBox;   // TTyRadioButton 与 TTyCheckBox 共用此单元
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Checked` | `Boolean` | `False` | 单选按钮当前选中状态；设为 `True` 时自动取消同一父容器下其他 `TTyRadioButton` 的选中状态（已定义 `default False`） |
| `Caption` | `string` | `''` | 单选按钮右侧显示的文字标签 |
| `Enabled` | `Boolean` | `True` | 为 `False` 时触发 `:disabled`，控件不响应交互 |
| `Font` | `TFont` | 系统默认 | 传递 PPI 给渲染器；字体族与大小优先由主题控制 |
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点 |

### 继承的通用成员

TTyRadioButton 继承自 `TTyCustomControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器 |

**状态跟踪字段（protected，不 published）：**

| 字段/状态 | 类型 | 说明 |
|-----------|------|------|
| `FHover` | `Boolean` | 鼠标悬停时为 `True`，触发 `:hover` 主题状态 |
| `FPressed` | `Boolean` | 鼠标左键按下时为 `True`，触发 `:active` 主题状态 |
| `Focused` | `Boolean` | 获得键盘焦点时触发 `:focus` 主题状态 |
| `Enabled = False` | — | 触发 `:disabled` 主题状态 |

**构造时自动设置 `TabStop := True`**，支持 Tab 键导航。

---

## 4. 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnClick` | `TNotifyEvent` | 用户点击控件时（`Checked` 已在此时设为 `True`，同组其他按钮已取消选中） |

---

## 5. 状态与主题

### 支持的伪类状态

| 伪类 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停 |
| `:focus` | 获得键盘焦点 |
| `:active` | 鼠标左键按下 |
| `:disabled` | `Enabled = False` |

### light.tycss 内置规则摘要

```css
TyRadioButton {
  background: var(--surface);      /* #FFFFFF，圆形底色 */
  color: var(--on-surface);        /* #1F2937，文字和圆点颜色 */
  border-color: var(--border);     /* #D1D5DB */
  border-width: 1px;
  border-radius: 8px;              /* 等于 BoxSize/2，呈现完整圆形 */
}
TyRadioButton:hover    { border-color: var(--accent); }   /* 悬停时边框变蓝 */
TyRadioButton:active   { background: var(--accent); }     /* 按下时圆圈变蓝 */
TyRadioButton:disabled { opacity: 0.5; }
```

**渲染细节：** 圆形指示器（`DotRect`）尺寸固定为 16×16 逻辑像素，圆角半径为 `BoxSize div 2`，视觉上为完整圆圈。选中时，内部圆点用 `tgRadioDot` 字形、`TextColor` 颜色绘制。圆圈与文字之间间距为 6 逻辑像素。

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.CheckBox, tyControls.Panel;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

// 使用 TTyPanel 作为分组容器
var PanelFruit: TTyPanel;
PanelFruit := TTyPanel.Create(Self);
PanelFruit.Parent := Self;
PanelFruit.Caption := '水果';
PanelFruit.SetBounds(16, 16, 176, 140);

// 在同一 Panel 内添加三个单选按钮（互斥）
var R1, R2, R3: TTyRadioButton;

R1 := TTyRadioButton.Create(PanelFruit);
R1.Parent := PanelFruit;
R1.SetBounds(8, 28, 160, 28);
R1.Caption := '苹果';
R1.Checked := True;   // 默认选中第一项
R1.OnClick := @RadioClicked;

R2 := TTyRadioButton.Create(PanelFruit);
R2.Parent := PanelFruit;
R2.SetBounds(8, 64, 160, 28);
R2.Caption := '香蕉';
R2.OnClick := @RadioClicked;

R3 := TTyRadioButton.Create(PanelFruit);
R3.Parent := PanelFruit;
R3.SetBounds(8, 100, 160, 28);
R3.Caption := '芒果';
R3.OnClick := @RadioClicked;

// 事件处理：Checked 已为 True，可直接读取
procedure TMainForm.RadioClicked(Sender: TObject);
begin
  ShowMessage('选中：' + (Sender as TTyRadioButton).Caption);
end;
```

完整可运行示例（含两组独立单选组）参见 `examples/radiobutton/umain.pas`。

---

## 7. 注意事项

- **按 Parent 分组互斥：** `UncheckSiblings` 方法遍历 `Parent.Controls`，将所有 `TTyRadioButton` 兄弟控件的 `Checked` 设为 `False`。**分组边界由 `Parent` 决定**，而非任何额外的 `GroupName` 属性。若要实现两个独立单选组，只需将它们分别放在两个不同的容器（如两个 `TTyPanel`）内。
- **点击只能选中，不能取消：** `Click` 方法始终调用 `SetChecked(True)`，点击已选中项不会取消选中。若需要"可取消"的单选行为，需自行扩展。
- **`SetChecked(False)` 不触发互斥：** 直接通过代码将 `Checked` 设为 `False` 时，不会触发 `UncheckSiblings`，因为互斥逻辑只在 `SetChecked` 中 `FChecked = True` 时执行。
- **OnClick 事件时序：** `Click` 先调用 `SetChecked(True)`（同步完成互斥），再调用 `inherited Click`（触发 `OnClick`），因此在 `OnClick` 处理器中读取 `Checked` 已为最终值，同组其他按钮也已完成取消。
- **同单元注意：** `TTyCheckBox` 和 `TTyRadioButton` 定义在同一单元 `tyControls.CheckBox` 中，`uses` 一次即可同时使用两者。
- **DFM 序列化：** `Checked` 声明了 `default False`，值为 `False` 时不写入 `.lfm`/`.dfm`；值为 `True` 时写入。
