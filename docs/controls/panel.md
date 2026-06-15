# TTyPanel

## 1. 概述

TTyPanel 是 TyControls 库中的主题化容器控件，继承自 `TTyCustomControl`。典型用途：将相关控件归组（如单选按钮分组、表单分区），提供带圆角和边框的视觉分组框，并可选显示标题文字；作为真正的 LCL 容器，子控件直接以其为 `Parent`。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Panel` |
| `GetStyleTypeKey` 返回值 | `'TyPanel'` |

在 `.tycss` 文件中，该控件对应的选择器前缀为 `TyPanel`。

```pascal
uses tyControls.Panel;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Caption` | `string` | `''` | 面板标题文字，显示在内容区顶部（按 `Alignment` 水平对齐、垂直居中）；为空字符串时不绘制文字 |
| `Alignment` | `TAlignment` | `taCenter` | 标题文字在内容区内的水平对齐方式：`taLeftJustify`（左对齐）/ `taCenter`（居中，默认）/ `taRightJustify`（右对齐）；赋值时触发 `Invalidate` |
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点 |

> **注意：** TTyPanel 没有 published `Enabled`、`Font` 属性（未在 `published` 节显式重声明），但作为 `TCustomControl` 子类，这些属性在对象层面仍然存在，只是不在对象检视器中显示。

### 继承的通用成员

TTyPanel 继承自 `TTyCustomControl`（`tyControls.Base`）：

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

**构造时默认尺寸：** `Width = 185`，`Height = 41`（在 `Create` 中硬编码，可在创建后自由调整）。

---

## 4. 事件

TTyPanel 当前版本没有在 `published` 节声明任何事件（包括 `OnClick`）。作为容器，通常不需要直接处理面板的点击事件；子控件各自处理自己的事件。

---

## 5. 状态与主题

### 支持的伪类状态

| 伪类 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停在面板自身上（不含子控件区域） |
| `:focus` | 面板自身获得键盘焦点 |
| `:active` | 鼠标左键在面板上按下 |
| `:disabled` | `Enabled = False`（内部状态，通过继承支持） |

### light.tycss 内置规则摘要

```css
TyPanel {
  background: var(--surface);      /* #FFFFFF */
  color: var(--on-surface);        /* #1F2937，标题文字颜色 */
  border-color: var(--border);     /* #D1D5DB */
  border-width: 1px;
  border-radius: var(--radius);    /* 6px */
  padding: 8px;
}
```

light.tycss 为 `TyPanel` 只定义了基础规则，没有 `:hover`、`:active`、`:disabled` 等伪类变体。`padding: 8px` 决定了标题文字到面板边缘的内边距，但**不影响子控件的布局**——子控件坐标相对于面板左上角（0,0）独立计算，不受 `padding` 约束。

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.Panel, tyControls.CheckBox, tyControls.Button;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

// 创建面板作为容器
var Panel: TTyPanel;
Panel := TTyPanel.Create(Self);
Panel.Parent := Self;
Panel.Caption := '选项设置';
Panel.SetBounds(16, 16, 240, 120);

// 将子控件的 Parent 设为 Panel，实现分组
var ChkOpt1: TTyCheckBox;
ChkOpt1 := TTyCheckBox.Create(Panel);
ChkOpt1.Parent := Panel;
ChkOpt1.SetBounds(8, 28, 200, 28);
ChkOpt1.Caption := '启用通知';

var ChkOpt2: TTyCheckBox;
ChkOpt2 := TTyCheckBox.Create(Panel);
ChkOpt2.Parent := Panel;
ChkOpt2.SetBounds(8, 64, 200, 28);
ChkOpt2.Caption := '自动更新';

// 使用面板分组单选按钮（互斥范围限定在该 Panel 内）
var PanelColor: TTyPanel;
PanelColor := TTyPanel.Create(Self);
PanelColor.Parent := Self;
PanelColor.Caption := '颜色';
PanelColor.SetBounds(270, 16, 176, 120);

var R1: TTyRadioButton;
R1 := TTyRadioButton.Create(PanelColor);
R1.Parent := PanelColor;
R1.SetBounds(8, 28, 160, 28);
R1.Caption := '红色';
R1.Checked := True;
```

完整可运行示例（含两个独立单选组）参见 `examples/radiobutton/umain.pas`。

---

## 7. 注意事项

- **真容器，可承载子控件：** `TTyPanel` 继承自 `TCustomControl`（有窗口句柄），子控件可以将其设为 `Parent`，坐标系以面板左上角为原点。这与 `TGraphicControl` 类控件（如 `TTyLabel`）不同，后者无法作为父容器。
- **子控件不受 padding 约束：** 面板的 `padding` 只影响 `Caption` 文字的绘制位置，不自动约束子控件布局。子控件坐标需手动设置，避免与边框/标题重叠。
- **单选分组的关键：** `TTyRadioButton` 的互斥范围由 `Parent` 决定，将不同组的单选按钮放在不同 `TTyPanel` 内，是实现多个独立单选组的标准做法。
- **Caption vs 子控件重叠：** 若同时使用 `Caption` 和子控件，需注意标题文字绘制在内容区域（经 `padding` 内缩后）顶部、按 `Alignment` 水平对齐、垂直居中的位置（默认 `taCenter` 居中），子控件的 `Top` 值应给标题文字留出足够空间。
- **默认尺寸较小：** 构造时 `Width=185, Height=41`，通常需要在创建后通过 `SetBounds` 调整为实际所需大小。
- **无 Enabled/Font published：** `Enabled` 和 `Font` 未在 TTyPanel 的 `published` 节重声明，不会出现在 IDE 对象检视器中，但可在代码中通过继承的属性访问。
