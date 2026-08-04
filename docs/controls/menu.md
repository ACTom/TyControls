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
| `Version` | `string`（只读） | `TyVersion` | 只读库版本号；设计期编辑器打开 About 对话框。 |
| `Controller` | `TTyStyleController` | `nil` | 主题化弹出解析令牌所用的样式控制器。 |

> `TTyPopupMenu` 的菜单项模型直接用**继承自 `TPopupMenu` 的 `Items`**（标准 `TMenuItem` 树），无需另设属性——把 `TMenuItem` 加到 `Items` 即可。它同时继承 `TPopupMenu` 的全部标准成员（`Items`、`Alignment`、`PopupPoint`、`Close`、`OnPopup`、`OnClose` 等），并且这些成员**真的在跑**：
>
> | 继承成员 | 行为 |
> |------|------|
> | `Alignment` | `paLeft`（默认）/ `paRight` / `paCenter`：弹出体相对 `PopUp(X, Y)` 那个点左对齐 / 右对齐 / 居中。右对齐是"从右侧工具条唤起的上下文菜单"的正常选择（左对齐会滑出屏幕）。渲染器是按锚点**左边缘**挂下拉的，所以对齐靠平移锚点表达——弹出体自己的宽度要测过才知道，故 `paRight`/`paCenter` 按渲染器报出的实测宽度偏移 |
> | `PopupPoint` | 每次 `PopUp(X, Y)` 都会写入，因此读到的是本次唤起的位置而不是历史值 |
> | `Close` / `OnClose` | 弹出体以任何方式消失（选中项、`Esc`、点到外面）都会走到 `TPopupMenu.Close` → `DoClose` → `OnClose`，并清掉全局 `ActivePopupMenu` |

#### 3.2.1 继承自 LCL 且**由主题化渲染器实现**的成员

下面这些成员声明在 `TPopupMenu` / `TMenu` / `TMenuItem` 上，对象查看器一直提供、也一直可以赋值——它们现在由主题化渲染器真正读取并生效（此前是「可设置但被忽略」）。

| 成员 | 声明于 | 默认值 | 主题化渲染器中的语义 |
|------|--------|--------|----------------------|
| `TrackButton` | `TPopupMenu` | `tbRightButton` | 弹出后哪个鼠标键可以激活菜单行。`tbRightButton`（默认）= **左右键都能选中**（与 Win32 `TPM_RIGHTBUTTON`、Qt 的 `trackButton` 过滤一致），因此「按住右键 → 拖到某行 → 松开」这一常规右键菜单手势可用；`tbLeftButton` = **仅左键**。 |
| `OwnerDraw` | `TMenu` | `False` | 自绘开关。为 `True` 时，每一行的**尺寸**来自 `OnMeasureItem`、**像素**来自 `OnDrawItem`（先取该 `TMenuItem` 自己的处理器，没有则回落到所属菜单的处理器——即 `TMenuItem.DoMeasureItem` / `DoDrawItem` 的 LCL 规则）。 |
| `OnDrawItem` | `TMenu` / `TMenuItem` | `nil` | `procedure(Sender; ACanvas: TCanvas; ARect: TRect; AState: TOwnerDrawState)`。仅在 `OwnerDraw = True` 时触发；触发的行**不再绘制**默认内容（勾选/图标槽、标题、快捷键、子菜单箭头）。 |
| `OnMeasureItem` | `TMenu` / `TMenuItem` | `nil` | `procedure(Sender; ACanvas: TCanvas; var AWidth, AHeight: Integer)`。仅在 `OwnerDraw = True` 时触发；入参已按主题默认值预填，处理器可只改一个轴。行高、行顶偏移、命中测试与弹出体测量**全部**采用其结果，所以变高行的绘制位置与点击位置一致。 |
| `GlyphShowMode` | `TMenuItem` | `gsmApplication` | 该项是否参与左侧图标列：`gsmAlways` 始终画、`gsmNever` 从不画、`gsmApplication` 跟随 `Application.ShowMenuGlyphs`、`gsmSystem` 跟随系统主题（`toShowMenuImages`）。设计期一律显示。逐项生效，一项退出不影响同级其他项。 |
| `SubMenuImages` / `SubMenuImagesWidth` | `TMenuItem` | `nil` / `0` | 子菜单专属图标源。按 LCL 的 `TMenuItem.GetImageList` 规则**逐项**解析：沿父链找**最近**一个设了 `SubMenuImages` 的祖先，都没有才回落到所属菜单的 `Images`。`SubMenuImagesWidth` 是 96-PPI 下的图像宽度（`0` = 用图像列表自身尺寸）。 |

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
| `TMenuItem.OnClick` | `TNotifyEvent` | 激活某个叶子菜单项（点击 / Enter / 空格 / 助记符）时，触发**该 `TMenuItem` 自己**的 `OnClick`。菜单栏与右键菜单都通过 `TMenuItem.Click` 分发到此事件。**菜单栏上没有子项的顶层项也算叶子**：点它直接触发它的 `OnClick`（见 §7）。 |
| `TPopupMenu.OnPopup` | `TNotifyEvent` | 每次 `PopUp(X, Y)` 弹出**之前**触发，且**早于行快照**——所以在这个 handler 里增删菜单项是有效的，这正是"按光标下的东西现拼上下文菜单"的做法。触发后若 `Items.Count = 0` 则什么也不弹（与 LCL 同）。 |
| `TPopupMenu.OnClose` | `TNotifyEvent` | 弹出体关闭后触发（选中项 / `Esc` / 点到外面都算），同时清掉全局 `ActivePopupMenu`。 |
| `TMenuItem.OnDrawItem` / `TMenu.OnDrawItem` | `TMenuDrawItemEvent` | 自绘一行的内容；仅当 `OwnerDraw = True` 时触发。见 §3.2.1 与 §7。 |
| `TMenuItem.OnMeasureItem` / `TMenu.OnMeasureItem` | `TMenuMeasureItemEvent` | 决定一行的宽/高；仅当 `OwnerDraw = True` 时触发。见 §3.2.1。 |

> 上面四个事件对 `TTyMenuBar` 关联的 `TMainMenu` 同样有效：菜单栏下拉与右键菜单用的是同一个渲染器，`TMainMenu.OwnerDraw` 会被转发给下拉。（菜单栏**自身的顶层单元格**不参与自绘，它们不是弹出行。）

> `TTyMenuBar` 作为 `TTyCustomControl` 子类，仍暴露**基线事件集**（Tier A 鼠标 / 通用事件 + Tier B 键盘 / 焦点事件）。但对菜单而言，命令响应应挂在**各 `TMenuItem` 的 `OnClick`** 上，而不是菜单栏本身的 `OnClick`。完整基线清单见 [../events.md](../events.md)。

---

## 5. 状态与主题

### 5.1 支持的伪类状态

菜单栏面板（`TyMenuBar`）与弹出面板（`TyMenuView` / `TyMenuPopup`）本身**不使用伪类**——它们只提供背景/边框/圆角/padding 的基础样式。伪类作用在 **`TyMenuItem`**（每个顶层单元格 / 每一行）上：

| 伪类 | 触发条件 |
|------|----------|
| `:hover` | **菜单栏单元格**：鼠标悬停在该顶层单元格上（`FHotIndex`）。<br>（下拉/弹出的**行**内部用高亮 `FHighlight` 表达"当前行"，映射为下方的 `:active`，不单独用 `:hover`。） |
| `:active` | **菜单栏单元格**：该单元格的下拉已打开（`FOpenIndex`）。<br>**弹出行**：该行被键盘/鼠标高亮选中（`FHighlight`）。 |
| `:disabled` | 对应 `TMenuItem.Enabled = False` 的**行**（`TyBuildMenuRows` 中读取 `mi.Enabled`），以及 `Enabled = False` 的**顶层单元格**。禁用**压过** `:hover` / `:active`：禁用的顶层不给悬停高亮，免得那层高亮反过来邀请用户去点一个点不开的东西。 |

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
- **可切换项的空勾选框：** `TMenuItem.ShowAlwaysCheckable = True` **或** `AutoCheck = True`、而当前 `Checked = False` 的行，在左槽画一个**空方框**（`StrokeBorder`），让用户在点之前就看出这是个开关——否则"视图 &gt; 工具栏"和"文件 &gt; 打开"长得一模一样，非要点过一次才知道。两个标志都读，因为 LCL 自己两个都读（`TMenuItem.IsCheckItem` = `Checked or RadioItem or AutoCheck or ShowAlwaysCheckable`，`menuitem.inc:1247`）。`ShowAlwaysCheckable` 是**显式**的那一个——"这是个开关，把框画出来"——而它恰恰是此前被忽略的：属性已 published、对象查看器里就有，绘制却只看 `AutoCheck`（那个还会让菜单项点一下自己就切换，很多程序并不想要），于是设了专为此事而生的那个属性反而什么都不画。空框只在没有勾选字形时画，且**优先于图标列**（`ImageIndex`）。
- **子菜单箭头 / 快捷键：** 有子项（`mi.Count > 0`）的行在右槽绘制 `tgArrowRight` 箭头；否则若 `mi.ShortCut <> 0`，在右槽右对齐绘制 `ShortCutToText(mi.ShortCut)`。（`ShortCutToText(0)` 返回 `'Unknown'`，故仅当 `ShortCut <> 0` 才渲染快捷键文本。）
- **默认项加粗：** `TMenuItem.Default = True` 的行以 `font-weight: 700`（粗体）渲染。
- **高亮行的 Hint 发布到 `Application.Hint`：** 高亮移到某行时把该 `TMenuItem.Hint` 写进 `Application.Hint`（状态栏 / 长提示面板据此描述光标下的命令）；高亮移开（索引 `-1`）时**清空**——留着一条已经不在指针下的命令的描述，比什么都不显示更糟。
- **图标列的两个来源与优先级：** 左槽的图标可以来自两处——库自己的 `TTyVirtualImageList`（`TTyImagesMenu.Images`，BGRA 名称键），或按 `GetImageList` 解析出的 **LCL `TCustomImageList`**（`SubMenuImages` 链 → 菜单的 `Images`）。**解析出的 LCL 列表优先**：`SubMenuImages` 是「这一层子菜单就要用这套图标」的明确声明，理应压过菜单级来源；二者在设计器里也不会撞车，因为 `TTyImagesMenu.Images` 遮蔽了 `TMenu.Images`。两条路径都先经 `GlyphShowMode` 门控，`Checked` 的勾选字形仍然优先于图标。
- **图标尺寸决定槽宽与行高下限：** 主题的 `--menu-check-slot`（18px）与文本行高是**下限**而非上限——LCL 图像列表自带像素尺寸，`SubMenuImagesWidth` 还能要求更大的，所以左槽与行高会被撑到刚好容纳图标（否则 32px 图标会盖住标题、上下被裁）。撑开量来自应用自己的图像列表，不是写死的视觉值。
- **禁用行的图标变灰：** LCL 图像列表按 `Enabled` 绘制，禁用行传 `False` 得到灰化图标（`TScaledImageListResolution.Draw` 的第 5 参是 `AEnabled` 而**不是** "greyed"，且它还有一个 `TGraphicsDrawEffect` 重载，传反了照样能编译）。
- **GDI 两趟后置绘制：** LCL 图像列表的图标与 `OnDrawItem` 都是 GDI 绘制，必须在 `TTyPainter.EndPaint` **之后**画到 `ACanvas` 上——在此之前直接画到 `ACanvas` 的内容会被 BGRA 图层的合成覆盖掉。两趟都按各自行矩形裁剪，互不越界。
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

- **数据模型是标准 LCL：** 菜单结构完全用原生 `TMainMenu` / `TPopupMenu` + `TMenuItem` 描述——`Caption`、`Enabled`、`Checked`、`RadioItem`、`AutoCheck`、`ShortCut`、`Default`、`Hint`、`RightJustify`、`ShowAlwaysCheckable`、`Visible`、子项（`Add`）都是标准 LCL 语义，且都**真的被读**。TyControls 只接管**外观**（重绘），不改数据模型。
- **命令挂在 `TMenuItem.OnClick`：** 激活叶子项会调用 `TMenuItem.Click` 触发**该项自己**的 `OnClick`；不要指望菜单栏/弹出菜单类上有汇总的选择事件（它们没有）。
- **禁用的顶层项打不开：** `Enabled = False` 的顶层项，点击、悬停切换、Alt+助记符三条路都打不开它的下拉（三者都汇到同一个 `OpenTop`，所以判定就写在那里）；它同时按 `:disabled` 绘制，用户看得出来点不动。
- **没有子项的顶层项是一个命令按钮：** 与原生菜单栏一致，点一个没有子项的顶层项直接触发它的 `OnClick`（先收起已打开的下拉）。这就是"帮助"这类单条命令能直接摆在菜单栏上的做法。
- **`RightJustify` 让顶层项贴右：** 某个顶层项的 `TMenuItem.RightJustify = True` 时，它贴着菜单栏右边缘排布（经典的右对齐"帮助"/"窗口"菜单）。位置是**从右往左**量出来的——右边缘减去「它自己及其之后所有顶层项」的宽度之和——所以菜单栏拉伸时这一组始终咬着右边缘。**惯例是从要右对齐的那一项起，后面每一项都设 `RightJustify`**：没设的那些仍按左侧打包排布，而右侧会替它们留出空位。
- **`TTyPopupMenu.PopUp` 走完整的 LCL 弹出协议：** 顺序是——先 `Close` 掉别的 `ActivePopupMenu` → 写 `PopupPoint` → 触发 `OnPopup` → `Items.Count = 0` 则直接返回 → 认领 `ActivePopupMenu`（`Close`/`OnClose` 靠它才够得着）→ `InitiateActions`（action 关联项刷新 `Enabled`/`Caption`/`Checked`）→ **最后**才做行快照并弹出。顺序是重点：快照如果先做，即使 `OnPopup` 触发了，在里面增删的项也进不了这一次弹出。
- **`Caption = '-'` 即分隔线：** 遵循 LCL 约定，`IsLine` 的项渲染为分隔线（不可选中、不可高亮）。
- **只渲染可见项：** `TyBuildMenuRows` 跳过 `Visible = False` 的项；菜单栏顶层单元格同样只计可见顶层项（`VisibleTopItem`）。设 `Visible := False` 可动态隐藏项。
- **`AutoSizeWidth` 受 `Align` 制约：** 仅当 `Align` **不是** `alTop`/`alBottom` 时才收缩到内容宽度——那两种对齐下 LCL 强制拉伸到父宽度，自适应会被覆盖。默认 `False`（声明了 `default False`，值为 `False` 时不写入 `.lfm`/`.dfm`）。
- **Alt+助记符打开顶层菜单：** `DialogChar` 仅在**恰好按下 Alt**（无 Ctrl/Shift）时匹配顶层项助记符打开其下拉；纯字母键经窗体级 DialogChar 广播不会误开菜单。助记符下划线仅在按住 Alt 时显示。
- **弹出层键盘导航：** 下拉/子菜单打开后，方向键上下移动高亮（跳过分隔线与禁用项、两端回绕）、`Home`/`End` 跳首末可选项、`Enter`/`Space` 激活、`→` 在子菜单行上展开子菜单（否则在根下拉上切到相邻顶层）、`←` 折叠子菜单回父级（根下拉上则切到上一顶层）、`Esc` 关闭当前层。裸字母/数字键跳转到匹配助记符的行并激活。
- **子菜单悬停自动展开：** 高亮停在子菜单行上超过 `TyMenuHoverOpenDelay`（350ms）自动展开该子菜单；移到非子菜单行会折叠已展开的同级子菜单。
- **自绘（`OwnerDraw`）的边界：**
  - 它是**开关**：`OwnerDraw = False`（默认）时，即使某项挂了 `OnDrawItem` / `OnMeasureItem` 也**不会**触发，行仍按主题绘制。
  - 触发自绘的行：**先**铺该行的主题背景（含 `:active` 高亮），**再**调处理器，并在 `AState` 中带上 `odBackgroundPainted` 告知这一点——只画文字的处理器因此仍能落在正确的高亮上。其余状态按行如实映射：`odSelected`（当前高亮行）、`odDisabled` + `odGrayed`、`odChecked`、`odDefault`。
  - **不覆盖 TyControls 专有的「章节标题」行**（`TTyMenuEx` 的 `-Text`）：它在 LCL 里没有对应的项类型，自绘协议管不到它，仍按主题绘制。普通项与分隔线都参与自绘。
  - 自绘只改**内容**，不改弹出体的背景/边框/圆角——那仍由 `TyMenuView` / `TyMenuPopup` 令牌决定。
- **`TrackButton` 的含义：** `tbRightButton`（默认）不是「只能右键」，而是「左右键都能选中」，与 Win32 `TPM_RIGHTBUTTON` 一致；左键路径（`TControl.Click`）在两种取值下都可用，`tbLeftButton` 只是把右键关掉。
- **`TTyPopupMenu` 是真正的 `TPopupMenu`：** 它重写虚方法 `PopUp(X, Y)`（已核实 `menus.pp` 中该方法为 `virtual`），因此赋给任意控件的 `PopupMenu` 属性、走 LCL 的 `DoContextPopup` 右键路径即可弹出主题化菜单，无需额外接线。
- **主题必须先加载：** 弹出体的背景/边框/圆角/高亮全部来自 `.tycss` 令牌；未加载主题时样式解析没有可用令牌。视觉值一律由主题驱动，代码中不写死颜色。
- **弹出圆角的平台差异：** 圆角窗口遮罩在 win32/gtk2/qt(X11) 上生效；Wayland 无法遮罩窗口，退化为方角绘制以避免"圆角绘制叠在方角窗口"的边缘瑕疵。
