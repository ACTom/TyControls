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
| `Caption` | `TCaption` | `''` | 面板标题文字，显示在内容区顶部（按 `Alignment` 水平对齐、垂直居中）；为空字符串时不绘制文字。**它就是 `TControl.Caption`**：`Caption` 与 `Text` 是同一个字符串（早先本控件另有一个自己的 `FCaption` 影子字段，写 `Caption` 时 `Text` 仍是空的），重绘经重写 `TextChanged` 触发 |
| `Alignment` | `TAlignment` | `taCenter` | 标题文字在内容区内的水平对齐方式：`taLeftJustify`（左对齐）/ `taCenter`（居中，默认）/ `taRightJustify`（右对齐）；赋值时触发 `Invalidate` |
| `VerticalAlignment` | `TTextLayout` | `tlCenter` | 标题文字的**垂直**位置：`tlTop` / `tlCenter`（默认）/ `tlBottom`。此前这一轴是写死的居中，因此"标题贴顶、子控件在下"的分区标题栏用面板自己的 `Caption` 根本表达不出来 |
| `WordWrap` | `Boolean` | `False` | 标题过长时折行显示，而不是省略号截断。折行走库内统一的 `TyWrapTextCJK`（既按空格断，也按 CJK 码点断，所以中文标题会正常折行）。默认 `False` = 现有窗体行为不变 |
| `ShowAccelChar` | `Boolean` | `False` | 把 `&` 解释为助记符标记：`&` 被吃掉，其后字符在按住 Alt 时显示下划线。关闭时 `&` 就是普通字符、照常绘制。与 `TCustomPanel.ShowAccelChar` 同义、同默认值；**仅影响显示**（面板不接受焦点，没有可供 Alt+字母 激活的目标）。折行与助记符下划线不能同时生效——画笔的多行分支没有逐行助记符偏移，但 `&` 仍会被吃掉，标题文字本身是对的 |
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点 |
| `DockSite` / `UseDockManager` / `OnDockDrop` / `OnDockOver` / `OnUnDock` / `OnGetSiteInfo` / `OnGetDockCaption` / `OnStartDock` / `OnEndDock` | — | — | 停靠族，照 `TPanel` 原样 republish。全部是 `TWinControl` / `TControl` 自己的成员，驱动它们的 dock manager 是 LCL 的代码；`tests/test.parity.container.pas` 里的探针真的把一个控件停靠进 `TTyPanel` 并断言了重新 parent、dock client 列表与通知，所以这是 republish 而非重新实现。前五个在 `TWinControl` 上是 public（代码里一直能写），`OnGetSiteInfo` / `OnGetDockCaption` / `OnStartDock` / `OnEndDock` 是 protected——**它们此前没有任何途径可达**，对象检视器和代码都够不着 |

> **注意：** 上表只列 TTyPanel **自己**声明（或 republish）的属性。`Enabled` / `Visible` / `Font` / `Hint` / `AutoSize` / `BorderWidth` / `ChildSizing` / 拖放族等由基类 `TTyCustomControl` 统一 published，在对象检视器里同样可见（完整清单见 [../events.md](../events.md)）。

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

TTyPanel 自身没有声明专有事件，但作为 `TTyCustomControl` 子类，它暴露**基线事件集**（Tier A 鼠标 / 通用事件 + Tier B 键盘 / 焦点事件，含 `OnClick` 与 `OnDragOver` / `OnDragDrop` 拖放族，完整清单见 [../events.md](../events.md)）。作为容器，通常不需要直接处理面板的点击事件；子控件各自处理自己的事件。

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
- **子控件不受 padding 约束，但受 `BorderWidth` 约束：** 面板的**主题 `padding`** 只影响 `Caption` 文字的绘制位置，不约束子控件布局。要给某一个面板留出内边距，用 `BorderWidth`——`TTyPanel.AdjustClientRect` 现在是它**唯一**的消费者。`BorderWidth` 是 `TWinControl` 的成员、由基类 published，但 `TWinControl` 自己从不读它（`TWinControl.AdjustClientRect` 是空实现，`SetBorderWidth` 只发一条 `CM_BORDERCHANGED`）；在 LCL 里内缩是 `TCustomPanel.AdjustClientRect` 做的，别处都没有。所以在补上这个重写之前，对象检视器里明摆着一个面板根本不理会的属性：设计器写下 `BorderWidth = 8`，子控件依旧贴着边框，也没有任何东西说明为什么。
  > 这条同样适用于 `TTyTabSheet` / `TTyPageControl`：它们的 `BorderWidth` 仍然是惰性的——**因为 LCL 的 `TTabSheet` / `TPageControl` 也一样**（`TCustomPage` 和 `TCustomTabControl` 都没有重写 `AdjustClientRect`）。这不是缺口，是对齐。
- **单选分组的关键：** `TTyRadioButton` 的互斥范围由 `Parent` 决定，将不同组的单选按钮放在不同 `TTyPanel` 内，是实现多个独立单选组的标准做法。
- **Caption vs 子控件重叠：** 若同时使用 `Caption` 和子控件，需注意标题文字绘制在内容区域（经 `padding` 内缩后）顶部、按 `Alignment` 水平对齐、垂直居中的位置（默认 `taCenter` 居中），子控件的 `Top` 值应给标题文字留出足够空间。
- **默认尺寸较小：** 构造时 `Width=185, Height=41`，通常需要在创建后通过 `SetBounds` 调整为实际所需大小。
- **`Caption` 就是 `Text`：** 二者是同一个 `TControl` 字符串，写哪个另一个都跟着变；不存在"设了 `Caption` 而 `Text` 仍为空"的旧行为（那会让 action link、无障碍查询等一切读 `Text` 的通用代码看到空串）。
- **无障碍身份：** 构造时设 `AccessibleRole := larGroup`（与 `TCustomPanel.Create` 一致）。此前库内每个控件都停在 `TControl` 的 `larUnknown`，屏幕阅读器把每个 ty 容器都念成"未知控件"，标准 LCL 窗体白送的结构地标在这里是缺的。`AccessibleDescription` 有意不设：LCL 那份是 resourcestring，为同一个意思再造一个可译字符串要在两个包里各跑一轮 `.po`，而角色已经把话说清楚了。
- **`ShowAccelChar` 只在开启时才注册 Alt 监听：** 下划线只在按住 Alt 期间出现，而唯一会在 Alt 边沿重绘的是 accel 监听注册表——但那个注册表会装一个 Application 级输入钩子、每次 Alt 都遍历重绘所有成员。为一个默认关闭的特性把全应用的面板都注册进去，是白付永久成本，所以注册跟着 `ShowAccelChar` 走。
- **右到左镜像：只翻 Caption，不翻子控件。** `BiDiMode := bdRightToLeft` 时 `Alignment` 按阅读序解释（默认 `taCenter`，居中是不动点，所以默认情况下什么都不变）。**子控件的 `Align`/`Anchors` 排布不镜像**：LCL 的对齐引擎在 `wincontrol.inc` 里只有 `ChildSizing` 的**表格**路径带 BiDi 分支（`:1551`，而 `TTyPanel` republish 了 `ChildSizing`，这一份是白捡的），`alLeft` 的子控件在原生 `TPanel` 上也还在左边。我们跟着不镜像，否则移植过来的窗体会与原生容器排得相反。见 [rtl.md](../rtl.md)。
