# TTyCheckBox

## 1. 概述

TTyCheckBox 是 TyControls 库中的主题化复选框控件，继承自 `TTyCustomControl`。典型用途：单个开关选项（如"记住密码"、"接受条款"），独立切换勾选状态，每次点击在选中/未选中之间切换，互不干扰。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.CheckBox` |
| `GetStyleTypeKey` 返回值 | `'TyCheckBox'` |

在 `.tycss` 文件中，该控件对应的选择器前缀为 `TyCheckBox`。

> **注意：** `TTyRadioButton` 也定义在同一个单元 `tyControls.CheckBox` 中，参见 [radiobutton.md](radiobutton.md)。

```pascal
uses tyControls.CheckBox;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Checked` | `Boolean` | `False` | 复选框当前勾选状态；赋值会触发重绘（已定义 `default False`，可参与 DFM 差量存储） |
| `Caption` | `string` | `''` | 复选框右侧显示的文字标签 |
| `Enabled` | `Boolean` | `True` | 为 `False` 时触发 `:disabled`，控件不响应交互 |
| `Font` | `TFont` | 系统默认 | 传递 PPI 给渲染器；字体族与大小优先由主题控制 |
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点 |

### 继承的通用成员

TTyCheckBox 继承自 `TTyCustomControl`（`tyControls.Base`）：

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
| `OnClick` | `TNotifyEvent` | 用户点击控件时（`Checked` 已在此时完成切换） |

---

## 5. 状态与主题

### 支持的伪类状态

| 伪类 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停 |
| `:focus` | 获得键盘焦点 |
| `:active` | 鼠标左键按下，**或** `Checked = True`（已勾选，Batch ④）|
| `:disabled` | `Enabled = False` |

> **`:active` 的双重含义（Batch ④）：** `TTyCheckBox` 重写了 `CurrentStates`——**`Checked = True` 且 `Enabled` 时额外加入 `tysActive`**（与 `TTyToggleSwitch` 的 ON↔`:active` 映射同源）。因此 `:active` 规则同时覆盖"鼠标按下"与"已勾选"两种情形，使主题能用 `:active` 表达勾选态的强调外观。

### light.tycss 内置规则摘要

```css
TyCheckBox {
  background: var(--surface);      /* #FFFFFF，勾选框填充色 */
  color: var(--on-surface);        /* #1F2937，文字和勾号颜色 */
  border-color: var(--border);     /* #D1D5DB */
  border-width: 1px;
  border-radius: 3px;              /* 轻微圆角 */
  padding: 4px;                    /* Batch ④：内缩留白 */
}
TyCheckBox:hover    { border-color: var(--accent); }            /* 悬停时边框变蓝 */
TyCheckBox:active   { background: var(--accent); color: #FFFFFF; }  /* 勾选/按下：accent 方框 + 白勾 */
TyCheckBox:disabled { opacity: 0.5; }
```

**渲染细节：** 勾选框尺寸固定为 16×16 逻辑像素（DPI 缩放），勾号（`tgCheck`）用 `TextColor` 绘制。勾选框与文字之间间距为 6 逻辑像素。主题的 `background`、`border-color`、`border-width` 样式作用于**小方块本身**，控件整体背景透明（无整体背景框）。`opacity` 和 `shadow` 属性经由 `DrawFrame` 路径生效（v1.1 已修复），可用于 `:disabled` 态等场景。

**勾选 `:active` 复活（Batch ④）：** 勾选后控件进入 `:active`，主题规则把小方块填成 `var(--accent)`、并把 `color` 置为 `#FFFFFF` 使勾号（tier-b 字形）变白——**accent 方框 + 白勾**。这是"框内"效果：渲染时 **Caption 文字用一份去掉了 `tysActive` 的样式解析**，因此 `:active` 的 `color: #FFFFFF` 不会把标签文字也染白，标签保持常规前景色。规则同时加了 `padding: 4px` 使方块与文字相对控件边缘内缩留白。

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.CheckBox;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

// 基础复选框
var ChkRemember: TTyCheckBox;
ChkRemember := TTyCheckBox.Create(Self);
ChkRemember.Parent := Self;
ChkRemember.SetBounds(24, 24, 200, 28);
ChkRemember.Caption := '记住密码';
ChkRemember.Checked := False;
ChkRemember.OnClick := @ChkChanged;

// 读取状态
procedure TMainForm.ChkChanged(Sender: TObject);
begin
  if (Sender as TTyCheckBox).Checked then
    ShowMessage('已勾选')
  else
    ShowMessage('已取消');
end;

// 禁用态
ChkRemember.Enabled := False;
```

---

## 7. 注意事项

- **点击即切换：** `Click` 方法中调用 `SetChecked(not FChecked)`，`OnClick` 触发时 `Checked` 已经是新值，可直接在事件处理器中读取。
- **独立状态：** 每个 `TTyCheckBox` 独立维护自己的 `Checked`，不与其他复选框联动。如需单选互斥行为，应使用 `TTyRadioButton`。
- **无 OnChange 事件：** 状态变化只通过 `OnClick` 通知，`SetChecked` 直接赋值不触发任何事件。
- **:active 视觉效果（Batch ④）：** `:active` 现同时由"鼠标按下"与"已勾选（`Checked = True`）"触发（`CurrentStates` 重写）。主题规则把方框填成 accent 蓝（`var(--accent)`）、勾号变白（`color: #FFFFFF`），形成 accent 方框 + 白勾；**Caption 标签不受影响**——其文字色由一份剔除了 `tysActive` 的样式解析提供，故标签保持常规前景色。
- **opacity / shadow 现已生效（v1.1）：** `DrawFrame` 路径现在同样应用于 `TTyCheckBox` 的外层绘制；`opacity` 和 `shadow` 属性可在主题中正常使用（例如 `TyCheckBox:disabled { opacity: 0.5; }`）。
- **控件整体无背景：** 主题中的 `background` 和 `border` 只作用于小方块本身，控件整体（Caption 文字区域）保持透明，不绘制整体背景框。
- **DFM 序列化：** `Checked` 声明了 `default False`，因此值为 `False` 时不写入 `.lfm`/`.dfm` 文件；值为 `True` 时才写入。
