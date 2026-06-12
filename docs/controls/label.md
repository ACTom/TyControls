# TTyLabel

## 1. 概述

TTyLabel 是 TyControls 库中的主题化静态文本控件，继承自 `TTyGraphicControl`（非 `TCustomControl`，因此**不可获得键盘焦点**）。典型用途：显示标题、提示文字、状态信息等只读标签，背景透明、无边框，文字颜色来自主题。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.TyLabel`（注意：单元名是 `TyLabel`，不是 `Label`） |
| `GetStyleTypeKey` 返回值 | `'TyLabel'` |

在 `.tycss` 文件中，该控件对应的选择器前缀为 `TyLabel`。

```pascal
uses tyControls.TyLabel;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Caption` | `string` | `''` | 标签显示文字，左对齐、垂直居中渲染 |
| `Enabled` | `Boolean` | `True` | 为 `False` 时触发 `:disabled` 主题状态（通常降低不透明度） |
| `Font` | `TFont` | 系统默认 | 传递 PPI 给渲染器；字体族与大小优先由主题控制 |
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点 |

### 继承的通用成员

TTyLabel 继承自 `TTyGraphicControl`（`tyControls.Base`），与其他 TyControls 控件共享以下 published 属性：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器 |

**状态跟踪字段（protected，不 published）：**

| 字段/状态 | 类型 | 说明 |
|-----------|------|------|
| `FHover` | `Boolean` | 鼠标悬停时为 `True`，触发 `:hover` 主题状态 |
| `FPressed` | `Boolean` | 鼠标左键按下时为 `True`，触发 `:active` 主题状态 |
| `Enabled = False` | — | 触发 `:disabled` 主题状态 |

> **注意：** TTyLabel 继承自 `TTyGraphicControl`（`TGraphicControl` 的子类），而非 `TTyCustomControl`（`TCustomControl` 的子类）。`TGraphicControl` **没有窗口句柄**，因此**不支持键盘焦点**，也就**没有** `:focus` 伪类状态。`CurrentStates` 方法中亦无 `tysFocused` 的处理逻辑。

---

## 4. 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnClick` | `TNotifyEvent` | 鼠标点击时（`TGraphicControl` 内置支持） |

---

## 5. 状态与主题

### 支持的伪类状态

| 伪类 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停 |
| `:active` | 鼠标左键按下 |
| `:disabled` | `Enabled = False` |

> `:focus` **不支持**（`TTyGraphicControl` 无窗口句柄，不可聚焦）。

### light.tycss 内置规则摘要

```css
TyLabel {
  background: alpha(#FFFFFF, 0);   /* 完全透明背景 */
  color: var(--on-surface);        /* #1F2937 */
  font-size: 10px;
  font-weight: 400;
}
TyLabel:disabled { opacity: 0.5; }
```

light.tycss 为 TyLabel 定义了极简规则：透明背景、无边框、无 `padding`，只有基础文字颜色和禁用态的半透明效果。

**Opacity 特性说明：** `opacity` 属性在渲染管线中通过 `TTyPainter` 的 `Opacity` 字段实现，`DrawFrame` 会在绘制前先设置透明度。`:disabled` 时 `opacity: 0.5` 使整个控件（含文字）渲染为半透明。

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.TyLabel;

// 加载主题（通常在窗体 Create 最顶部执行一次）
TyDefaultController.LoadTheme('themes/light.tycss');

// 基础标签
var Lbl: TTyLabel;
Lbl := TTyLabel.Create(Self);
Lbl.Parent := Self;
Lbl.SetBounds(24, 24, 280, 24);
Lbl.Caption := '这是一段说明文字';

// 禁用态（显示半透明）
var LblDisabled: TTyLabel;
LblDisabled := TTyLabel.Create(Self);
LblDisabled.Parent := Self;
LblDisabled.SetBounds(24, 60, 280, 24);
LblDisabled.Caption := '此功能暂不可用';
LblDisabled.Enabled := False;

// 动态更新 Caption
Lbl.Caption := Format('已处理 %d 条记录', [RecordCount]);
```

完整可运行示例参见 `examples/label/umain.pas`。

---

## 7. 注意事项

- **无边框、纯文本：** 默认背景完全透明（`alpha(#FFFFFF, 0)`），不绘制边框，视觉上等同于原生 `TLabel`，但外观完全由 `.tycss` 主题驱动。
- **不可聚焦：** 基类是 `TGraphicControl`，没有 HWND，无法接收键盘焦点，`:focus` 伪类永远不会生效。如果需要可聚焦的文字控件，应换用其他控件类型。
- **Opacity：** `:disabled` 状态下 `opacity: 0.5` 会使文字和背景一起半透明。若主题未设置 `opacity`，渲染时默认 `Opacity = 1.0`（见 `EmptyStyleSet`）。
- **文字对齐：** 渲染时固定为左对齐（`taLeftJustify`）、垂直居中（`tlCenter`），不可通过属性修改；如需其他对齐方式，需自行继承并重写 `RenderTo`。
- **单元名陷阱：** 单元名是 `tyControls.TyLabel`（含 `Ty` 前缀），与其他控件单元（如 `tyControls.Button`）的命名规律不同，容易拼错。
