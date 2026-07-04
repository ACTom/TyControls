# TTyMenuBar + TTyPopupMenu

## 1. 概述

`TTyMenuBar` 与 `TTyPopupMenu` 是 TyControls 库中一对主题化的菜单控件，二者都在标准 LCL 菜单数据模型（`TMainMenu` / `TPopupMenu` + `TMenuItem`）之上做**主题化重绘**，用 `.tycss` 令牌驱动的下拉/弹出替换原生 OS 菜单外观。

- `TTyMenuBar`（继承自 `TTyCustomControl`）是一条**水平应用程序菜单栏**：把关联的 `TMainMenu` 的可见顶层项渲染成一排横向单元格，单击某个顶层项（或 Alt+助记符）弹出该项子菜单的主题化下拉。
- `TTyPopupMenu`（继承自 `TPopupMenu`）是一个**主题化右键弹出菜单**：它*就是*一个 `TPopupMenu`，可直接挂到任意控件的 `PopupMenu` 属性上；它重写了虚方法 `PopUp(X, Y)`，把右键路径引到主题化渲染器而非原生菜单。

两者共享同一套内部渲染基础设施（`TTyMenuView` 行渲染器 + `TTyMenuPopup` 弹出宿主 + `TyBuildMenuRows` 行模型），因此下拉/子菜单/右键菜单外观完全一致。典型用途：给自绘窗框（`TTyForm`）配套一条与主题一致的菜单栏与右键菜单。

> `TTyMenuView` 与 `TTyMenuPopup` 是内部实现类（弹出行渲染器 / 弹出宿主），**不是** published 组件，本文不作为公开 API 记录，仅在解释机制时提及。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Menu` |
| `TTyMenuBar.GetStyleTypeKey` 返回值 | `'TyMenuBar'` |
| `TTyPopupMenu` 弹出体 typeKey | `'TyMenuView'`（弹出面）+ `'TyMenuPopup'`（弹出窗宿主/圆角半径）+ `'TyMenuItem'`（每一行/每个单元格） |

在 `.tycss` 文件中，菜单栏本身的选择器前缀为 `TyMenuBar`；下拉/右键弹出的面板背景用 `TyMenuView`（弹出窗窗体的圆角半径另由 `TyMenuPopup` 解析），**每一行菜单项与菜单栏的每个顶层单元格**统一用 `TyMenuItem` 选择器（含 `:hover` / `:active` / `:disabled` 状态）。

```pascal
uses tyControls.Menu;
```

---

## 3. 属性表

### 3.1 TTyMenuBar —— 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Menu` | `TMainMenu` | `nil` | 关联的 LCL 数据模型。写入时 `SetMenu` 先关闭已开下拉、对新模型 `FreeNotification`、重算自适应宽度并重绘；渲染的顶层单元格由 `Menu.Items` 中**可见**的顶层项构成。`TTyForm.MenuBar` 读取它做快捷键派发 / mac 全局菜单栏交接。 |
| `AutoSizeWidth` | `Boolean` | `False` | 为 `True` 时把 `Width` 收缩至 `FitWidth`（顶层单元格宽度之和 + 菜单栏左右 padding）。这是一个**独立标志**，不走 LCL 的 `AutoSize`/`CanAutoSize` 机制。仅当 `Align` **不是** `alTop`/`alBottom` 时生效——那两种对齐下 LCL 会把菜单栏强制拉伸到父宽度，内容自适应会被覆盖。在 `Menu` 被（重新）赋值、此标志被置 `True`、以及 resize/relayout 时重算。 |
| `Align` | `TAlign` | — | 停靠对齐方式（继承自 `TControl`）。示例中用 `alTop` 贴在标题栏下方随窗体拉伸。 |
| `Anchors` | `TAnchors` | — | 锚点布局（继承自 `TControl`）。 |

> **构造默认值：** `TTyMenuBar.Create` 中设 `TabStop := True`、`Height := 28`，并调用 `TyAccelRegister(Self)` 注册共享 Alt 状态（Alt 键按下/松开时重绘菜单栏以显示助记符下划线）。

### 3.2 TTyPopupMenu —— 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `About` | `string`（只读） | `TyVersion` | 只读库版本号；设计期编辑器打开 About 对话框。 |
| `Controller` | `TTyStyleController` | `nil` | 主题化弹出解析令牌所用的样式控制器。 |

> `TTyPopupMenu` 的菜单项模型直接用**继承自 `TPopupMenu` 的 `Items`**（标准 `TMenuItem` 树），无需另设属性——把 `TMenuItem` 加到 `Items` 即可。它同时继承 `TPopupMenu` 的全部标准成员（`Items`、`OnPopup` 等）。

### 3.3 继承的通用成员

`TTyMenuBar` 继承自 `TTyCustomControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器 |

### 3.4 状态跟踪字段（protected，不 published）

`TTyMenuBar`：

| 字段 | 类型 | 说明 |
|------|------|------|
| `FHotIndex` | `Integer` | 当前鼠标悬停的顶层单元格索引，无则 `-1`；对应该单元格进入 `:hover` |
| `FOpenIndex` | `Integer` | 当前已打开下拉的顶层单元格索引，无则 `-1`；对应该单元格进入 `:active` |

> 菜单栏本身的 `TyMenuBar` 选择器**不使用**伪类；`:hover` / `:active` 作用在**单元格**（`TyMenuItem` 选择器）上，由上面两个字段驱动（见 §5）。

---

## 4. 事件

`TTyMenuBar` 与 `TTyPopupMenu` 在自身类上**没有声明专有事件**——菜单命令的响应发生在 `TMenuItem` 级别：

| 来源 | 事件 | 说明 |
|------|------|------|
| `TMenuItem.OnClick` | `TNotifyEvent` | 激活某个叶子菜单项（点击 / Enter / 空格 / 助记符）时，触发**该 `TMenuItem` 自己**的 `OnClick`。菜单栏与右键菜单都通过 `TMenuItem.Click` 分发到此事件。 |
| `TPopupMenu.OnPopup` | `TNotifyEvent` | `TTyPopupMenu` 继承自 `TPopupMenu`，其标准弹出事件仍可用。 |

> `TTyMenuBar` 作为 `TTyCustomControl` 子类，仍暴露**基线事件集**（Tier A 鼠标 / 通用事件 + Tier B 键盘 / 焦点事件）。但对菜单而言，命令响应应挂在**各 `TMenuItem` 的 `OnClick`** 上，而不是菜单栏本身的 `OnClick`。完整基线清单见 [../events.md](../events.md)。

---

## 5. 状态与主题

### 5.1 支持的伪类状态

菜单栏面板（`TyMenuBar`）与弹出面板（`TyMenuView` / `TyMenuPopup`）本身**不使用伪类**——它们只提供背景/边框/圆角/padding 的基础样式。伪类作用在 **`TyMenuItem`**（每个顶层单元格 / 每一行）上：

| 伪类 | 触发条件 |
|------|----------|
| `:hover` | **菜单栏单元格**：鼠标悬停在该顶层单元格上（`FHotIndex`）。<br>（下拉/弹出的**行**内部用高亮 `FHighlight` 表达"当前行"，映射为下方的 `:active`，不单独用 `:hover`。） |
| `:active` | **菜单栏单元格**：该单元格的下拉已打开（`FOpenIndex`）。<br>**弹出行**：该行被键盘/鼠标高亮选中（`FHighlight`）。 |
| `:disabled` | 对应 `TMenuItem.Enabled = False` 的行（`TyBuildMenuRows` 中读取 `mi.Enabled`）。 |

### 5.2 light.tycss 内置规则摘要

```css
/* 菜单栏面板：透明背景，仅提供文字色/字体/内边距 */
TyMenuBar {
  background: alpha(#FFFFFF, 0);   /* 完全透明，融入窗体背景 */
  color: var(--on-surface);
  font-size: var(--font-size-base);
  font-weight: var(--font-weight-normal);
  padding: 2px;
}

/* 下拉/右键弹出的面板体（TyMenuView 绘制；TyMenuPopup 供弹出窗圆角半径） */
TyMenuView {
  background: var(--surface);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: var(--input-border-width);
  border-radius: var(--radius);
  padding: 4px;
}
TyMenuPopup {                       /* 与 TyMenuView 镜像；用于弹出窗窗体的圆角遮罩半径 */
  background: var(--surface);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: var(--input-border-width);
  border-radius: var(--radius);
  padding: 4px;
}

/* 单行 / 单个顶层单元格（base 的 border-color 即分隔线墨色） */
TyMenuItem {
  background: alpha(#FFFFFF, 0);
  color: var(--on-surface);
  border-color: var(--border);       /* 分隔线颜色由此取 */
  border-radius: var(--radius-sm);
  padding: 4px;
  font-size: var(--font-size-base);
  font-weight: var(--font-weight-normal);
}
TyMenuItem:hover    { background: var(--surface-hover); }              /* 悬停高亮 */
TyMenuItem:active   { background: var(--accent); color: var(--on-accent); }  /* 打开/高亮：accent 填充 */
TyMenuItem:disabled { color: var(--muted); }                          /* 禁用项灰化 */
```

### 5.3 渲染细节

- **布局度量常量**（逻辑像素，96-PPI 基线，各调用点用 `TTyPainter.Scale` / `MulDiv` 缩放到设备 PPI）：`TyMenuSeparatorHeight = 7`（分隔线槽高）、`TyMenuArrowSlot = 16`（右侧子菜单 ▸ 箭头预留宽）、`TyMenuCheckSlot = 18`（左侧勾选/单选字形预留宽）、`TyMenuShortcutGap = 24`（标题与右对齐快捷键文本间最小间距）、`TyMenuHoverOpenDelay = 350`（子菜单悬停自动展开的毫秒延迟）。这些是**尺寸/间距令牌，不是颜色**——颜色一律来自 `.tycss`。
- **分隔线：** `TMenuItem.Caption = '-'`（`IsLine`）渲染为一条居中于分隔槽的 1px 主题线，颜色取 `TyMenuItem` 的 `border-color`。
- **勾选/单选字形：** `TMenuItem.Checked` 为 `True` 时在左槽绘制字形——`RadioItem` 为 `True` 用圆点（`tgRadioDot`），否则用勾号（`tgCheck`），颜色跟随行的 `TextColor`。
- **子菜单箭头 / 快捷键：** 有子项（`mi.Count > 0`）的行在右槽绘制 `tgArrowRight` 箭头；否则若 `mi.ShortCut <> 0`，在右槽右对齐绘制 `ShortCutToText(mi.ShortCut)`。（`ShortCutToText(0)` 返回 `'Unknown'`，故仅当 `ShortCut <> 0` 才渲染快捷键文本。）
- **默认项加粗：** `TMenuItem.Default = True` 的行以 `font-weight: 700`（粗体）渲染。
- **助记符下划线：** 标题中的 `&` 由 `TyParseMnemonic` 解析（共享设施 `tyControls.Accel`），`&` 从显示文本移除，其后字符在**按住 Alt 时**显示下划线；菜单栏的下划线经 `TyAccelGatePos` 门控（仅 Alt 态显示）。
- **弹出圆角：** 弹出窗体用与 `TyMenuPopup` 的 `border-radius` 匹配的圆角区域做窗口遮罩（`SetWindowRgn`/`CreateRoundRectRgn`，跨 win32/gtk2/qt）；半径为 0 或非 Windows 时留矩形；Wayland 无法遮罩窗口，改为方角绘制（`ForceSquareSurface`）。

---

## 6. 代码示例

以下示例镜像 `examples/menu/umain.pas`：纯代码构建一条绑定 `TMainMenu` 的菜单栏，并挂一个右键菜单到面板上。

```pascal
uses
  Classes, Menus,
  tyControls.Controller, tyControls.Menu, tyControls.Panel;

// 加载主题（须在创建控件前）
TyDefaultController.LoadTheme('themes/light.tycss');

// ---- 1. 构建标准 LCL 数据模型 ----
var
  MainMenu: TMainMenu;
  TopItem, Leaf: TMenuItem;

MainMenu := TMainMenu.Create(Self);

TopItem := TMenuItem.Create(MainMenu);
TopItem.Caption := '文件(&F)';        // & 前缀 → Alt+F 助记符
MainMenu.Items.Add(TopItem);

Leaf := TMenuItem.Create(MainMenu);
Leaf.Caption := '新建(&N)';
Leaf.OnClick := @MenuItemClicked;     // 命令响应挂在 TMenuItem 上
TopItem.Add(Leaf);

Leaf := TMenuItem.Create(MainMenu);
Leaf.Caption := '-';                  // Caption='-' → 分隔线
TopItem.Add(Leaf);

// ---- 2. 主题化菜单栏，绑定数据模型 ----
var MenuBar: TTyMenuBar;
MenuBar := TTyMenuBar.Create(Self);
MenuBar.Parent := Self;
MenuBar.Align := alTop;               // 贴顶随窗体拉伸
MenuBar.Height := 30;
MenuBar.Menu := MainMenu;             // 绑定：点顶层项 / Alt+F 打开下拉

// ---- 3. 主题化右键菜单，挂到面板 ----
var
  Popup: TTyPopupMenu;
  PanelHost: TTyPanel;

Popup := TTyPopupMenu.Create(Self);
Leaf := TMenuItem.Create(Popup);
Leaf.Caption := '刷新(&R)';
Leaf.OnClick := @MenuItemClicked;
Popup.Items.Add(Leaf);

PanelHost := TTyPanel.Create(Self);
PanelHost.Parent := Self;
PanelHost.PopupMenu := Popup;         // 右键面板 → 弹出主题化菜单

// ---- 命令响应 ----
procedure TMainForm.MenuItemClicked(Sender: TObject);
begin
  ShowMessage('已选择：' + StripHotkey((Sender as TMenuItem).Caption));
end;
```

> **与 `TTyForm` 联动（可选）：** 若把菜单栏赋给窗体的 `MenuBar` 属性（`Form.MenuBar := MenuBar`），可启用 `TTyForm.IsShortcut` 的快捷键派发与 mac 全局菜单栏交接（见示例第 151 行）。

---

## 7. 注意事项

- **数据模型是标准 LCL：** 菜单结构完全用原生 `TMainMenu` / `TPopupMenu` + `TMenuItem` 描述——`Caption`、`Enabled`、`Checked`、`RadioItem`、`ShortCut`、`Default`、`Visible`、子项（`Add`）都是标准 LCL 语义。TyControls 只接管**外观**（重绘），不改数据模型。
- **命令挂在 `TMenuItem.OnClick`：** 激活叶子项会调用 `TMenuItem.Click` 触发**该项自己**的 `OnClick`；不要指望菜单栏/弹出菜单类上有汇总的选择事件（它们没有）。
- **`Caption = '-'` 即分隔线：** 遵循 LCL 约定，`IsLine` 的项渲染为分隔线（不可选中、不可高亮）。
- **只渲染可见项：** `TyBuildMenuRows` 跳过 `Visible = False` 的项；菜单栏顶层单元格同样只计可见顶层项（`VisibleTopItem`）。设 `Visible := False` 可动态隐藏项。
- **`AutoSizeWidth` 受 `Align` 制约：** 仅当 `Align` **不是** `alTop`/`alBottom` 时才收缩到内容宽度——那两种对齐下 LCL 强制拉伸到父宽度，自适应会被覆盖。默认 `False`（声明了 `default False`，值为 `False` 时不写入 `.lfm`/`.dfm`）。
- **Alt+助记符打开顶层菜单：** `DialogChar` 仅在**恰好按下 Alt**（无 Ctrl/Shift）时匹配顶层项助记符打开其下拉；纯字母键经窗体级 DialogChar 广播不会误开菜单。助记符下划线仅在按住 Alt 时显示。
- **弹出层键盘导航：** 下拉/子菜单打开后，方向键上下移动高亮（跳过分隔线与禁用项、两端回绕）、`Home`/`End` 跳首末可选项、`Enter`/`Space` 激活、`→` 在子菜单行上展开子菜单（否则在根下拉上切到相邻顶层）、`←` 折叠子菜单回父级（根下拉上则切到上一顶层）、`Esc` 关闭当前层。裸字母/数字键跳转到匹配助记符的行并激活。
- **子菜单悬停自动展开：** 高亮停在子菜单行上超过 `TyMenuHoverOpenDelay`（350ms）自动展开该子菜单；移到非子菜单行会折叠已展开的同级子菜单。
- **`TTyPopupMenu` 是真正的 `TPopupMenu`：** 它重写虚方法 `PopUp(X, Y)`（已核实 `menus.pp` 中该方法为 `virtual`），因此赋给任意控件的 `PopupMenu` 属性、走 LCL 的 `DoContextPopup` 右键路径即可弹出主题化菜单，无需额外接线。
- **主题必须先加载：** 弹出体的背景/边框/圆角/高亮全部来自 `.tycss` 令牌；未加载主题时样式解析没有可用令牌。视觉值一律由主题驱动，代码中不写死颜色。
- **弹出圆角的平台差异：** 圆角窗口遮罩在 win32/gtk2/qt(X11) 上生效；Wayland 无法遮罩窗口，退化为方角绘制以避免"圆角绘制叠在方角窗口"的边缘瑕疵。
