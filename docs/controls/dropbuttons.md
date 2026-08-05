# 下拉按钮 (TTyDropDownButton / TTyMenuButton)

## 1. 概述

这两个控件把一个下拉菜单挂到按钮上，都继承自 [[TTyButton]]，共享同一套框架、悬停背景淡入、状态、焦点环与数字角标——**不新增任何 `.tycss` 规则**：

| 控件 | 布局 | 点击行为 | 典型用途 |
|------|------|----------|----------|
| `TTyDropDownButton` | **分裂式**：左侧标题区 + 右侧箭头区（中间一条细分隔线） | 点**标题区** → 正常 `Click`/`OnClick`；点**箭头区** → 弹出菜单 | 主操作 + 次要选项（如「保存 ▾」，箭头出「另存为…」） |
| `TTyMenuButton` | **整按钮**：标题 + 尾随的向下箭头（无分裂、无分隔线） | **任意点击**都弹出菜单（且 `Click` 本身即是「下拉」） | 纯菜单触发器（如「选项 ▾」「排序 ▾」） |

核心区别：**分裂按钮**把一次点击按落点分流——只有落在右侧箭头区才下拉，标题区仍是普通按钮；**菜单按钮**没有分裂，整个按钮就是下拉触发器。

> **复用 TyButton 主题**：两者的 `GetStyleTypeKey` 都保持返回 `'TyButton'`（继承而来）。因此框架、`:hover`/`:active`/`:focus`/`:disabled`/`:selected` 状态、悬停背景渐变和角标都**免费**获得。箭头三角用解析后样式的 `TextColor` 填充（`Canvas2D` 抗锯齿），分裂线用 `BorderColor`——**全部主题驱动，无硬编码颜色**。

弹出的是 [[菜单|menu]] 单元里的 `TTyPopupMenu`（其虚方法 `PopUp(X, Y)` 渲染主题化菜单，而非系统原生菜单）。菜单树用标准 LCL 的 `Items`（`TMenuItem`）构建。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.DropButtons` |
| `GetStyleTypeKey` 返回值 | `'TyButton'`（**两者均复用**，见 [button.md](button.md)） |

```pascal
uses tyControls.Menu, tyControls.DropButtons;
```

---

## 3. 属性与事件

### 3.1 `TTyDropDownButton`（分裂按钮）自有成员

| 成员 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `DropDownMenu` | `TTyPopupMenu` | `nil` | 点击箭头区时弹出的主题化菜单。用 `FreeNotification`/`Notification` 挂钩：所指菜单被释放时自动置 `nil`，不留悬垂引用。 |
| `ArrowWidth` | `Integer` | `18` | 右侧箭头区宽度（**逻辑像素**，随 PPI 缩放）。命中判定用它把点击落点划入「箭头区 / 标题区」。设为负数钳制为 `0`。 |
| `OnDropDown` | `TNotifyEvent` | `nil` | 菜单弹出**之前**触发，供处理器动态构建/更新菜单项。 |

### 3.2 `TTyMenuButton`（菜单按钮）自有成员

| 成员 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `DropDownMenu` | `TTyPopupMenu` | `nil` | 点击时弹出的菜单（同样 `FreeNotification` 挂钩）。 |
| `OnDropDown` | `TNotifyEvent` | `nil` | 弹出前触发。 |

> 菜单按钮**没有** `ArrowWidth`——它不分裂，尾随箭头只是视觉标识，整按钮都可点。

### 3.3 继承自 [[TTyButton]] 的常用成员

`Caption`、`Down`（`:selected` 常驻选中态）、`Default`、`Cancel`、`ModalResult`、`ShowBadge`/`BadgeValue`/`BadgePosition`/`OnBadgeDisplay`（数字角标）、`AnimationsEnabled`（悬停背景渐变）、`Enabled`、`Font`、`Align`、`Anchors`、`StyleClass`、`Controller`、`OnClick` 等——细节见 [button.md](button.md)。

---

## 4. 点击路由（分裂 vs 整按钮）

### 4.1 分裂按钮 `TTyDropDownButton`

LCL 在鼠标抬起**之后**才合成 `Click`，因此分裂判定分两步：`MouseDown` 记下**按下点的 X**，随后 `Click` 读这个 X 决定去向：

- 按下点落在**箭头区**（右侧 `ArrowWidth` 逻辑像素内） → 调 `DoDropDown`（下拉），并**吞掉**主 `OnClick`。
- 落在**标题区**（或键盘触发的 `Click`，此时无按下点） → 走正常 `TTyButton.Click`（`OnClick` + `ModalResult` 语义）。

命中判定抽成纯函数 **`TyDropArrowHit`**（可无头单测）：

```pascal
function TyDropArrowHit(AClickX, AWidthPx, AArrowWidthPx: Integer): Boolean;
```

- 箭头区是控件最右侧的 `AArrowWidthPx` 像素；点击 X 恰为 `(AWidthPx - AArrowWidthPx)` 即落入第一个箭头像素。
- 退化宽度（箭头 ≥ 控件宽、或非正数）一律返回 `False`，保证极小/零宽按钮不会把每次点击都当成箭头命中。

例（控件宽 100、箭头区 20）：`x=90 → True`、`x=99 → True`、`x=80 → True`（首个箭头像素）、`x=79 → False`、`x=50 → False`。

### 4.2 菜单按钮 `TTyMenuButton`

整按钮即下拉——重写 `Click`：先 `inherited Click`（仍履行基类 `OnClick` + `ModalResult` 约定），再 `DoDropDown`。所以一次点击**既触发 `OnClick` 也弹菜单**。

### 4.3 `DoDropDown`（两者共有的下拉逻辑）

1. 触发 `OnDropDown`（供处理器填充菜单）。
2. 若 `DropDownMenu <> nil` 且控件已有窗口句柄（`HandleAllocated`）→ 在按钮**左下角**（屏幕坐标）弹出：

```pascal
p := ClientToScreen(Point(0, Height));
DropDownMenu.PopUp(p.X, p.Y);
```

> **无头安全**：真正的 `PopUp` 需要 GUI 窗口，因此只在有句柄的真实点击路径里调用。无头（测试）调用只会走到「记录是否**将要**弹出」这一步（`RequestedPopup` 标志），绝不触碰 GUI。`DrawContent` 与命中判定在 `DropDownMenu = nil` / 无句柄时也不会崩溃。

---

## 5. 绘制机制（DrawContent）

两者都**只重写** `DrawContent`（各自重写 `Create`/路由方法），不触碰框架/状态/角标绘制路径：基类 `RenderTo`（继承自 TTyButton）先画框架、算内边距，再把已内缩的内容矩形交给 `DrawContent`。

- **`TTyDropDownButton.DrawContent`**：把内容矩形切成「标题矩形（左）+ 箭头矩形（右 `ArrowWidth`）」；`inherited DrawContent(P, 标题矩形, S)` 居中画标题；箭头矩形里用 `Canvas2D` 画一个居中的**向下三角**（`FillPolyG` 语义，填 `S.TextColor`）；两者之间画一条 1px 竖直**分隔线**（`S.BorderColor`）。箭头区过窄时自动退让，绝不把标题挤没。
- **`TTyMenuButton.DrawContent`**：同样切出标题 + 尾随箭头区，画居中标题 + 向下三角，但**无分隔线**（整按钮一体）。

---

## 6. 状态与主题

伪类状态与 [[TTyButton]] 完全一致：`:hover` / `:focus` / `:active` / `:disabled` / `:selected`（由 `Down` 驱动）。由于复用 `TyButton` 选择器，**默认外观就是一个普通按钮**（加上箭头/分隔线）。要扁平/工具栏观感，给它一个自定义 `StyleClass`（如 `'ghost'`，见 button.md 的 ghost 变体），无需新增 typeKey。

---

## 7. 代码示例

```pascal
uses
  Menus,
  tyControls.Controller,
  tyControls.Menu, tyControls.DropButtons;

TyDefaultController.LoadTheme('themes/light.tycss');

// 1) 一个主题化弹出菜单(标准 LCL Items 构建菜单树)
var Menu: TTyPopupMenu; Mi: TMenuItem;
Menu := TTyPopupMenu.Create(Self);
Menu.Controller := TyDefaultController;   // 用哪套主题渲染菜单
Mi := TMenuItem.Create(Menu); Mi.Caption := '另存为…'; Mi.OnClick := @DoSaveAs;
Menu.Items.Add(Mi);
Mi := TMenuItem.Create(Menu); Mi.Caption := '导出 PDF'; Mi.OnClick := @DoExport;
Menu.Items.Add(Mi);

// 2) 分裂按钮:点「保存」正常保存,点右侧箭头出上面的菜单
var SaveBtn: TTyDropDownButton;
SaveBtn := TTyDropDownButton.Create(Self);
SaveBtn.Parent := Self;
SaveBtn.SetBounds(24, 24, 120, 30);
SaveBtn.Caption := '保存';
SaveBtn.OnClick := @DoSave;          // 点标题区 -> 主操作
SaveBtn.DropDownMenu := Menu;        // 点箭头区 -> 弹菜单
// SaveBtn.ArrowWidth := 22;         // 可选:加宽箭头区
// SaveBtn.OnDropDown := @BuildMenu; // 可选:弹出前动态填充 Menu.Items

// 3) 菜单按钮:整按钮都弹菜单
var SortBtn: TTyMenuButton;
SortBtn := TTyMenuButton.Create(Self);
SortBtn.Parent := Self;
SortBtn.SetBounds(160, 24, 100, 30);
SortBtn.Caption := '排序';
SortBtn.DropDownMenu := Menu;
// 菜单按钮的 Click 即下拉;若也挂 OnClick,它会在弹菜单的同时触发。
```

---

## 8. 注意事项

- **弹菜单需要真机（GUI 窗口）：** `PopUp` 依赖 `ClientToScreen` 与一个真实的 GUI 事件循环，只在控件已分配窗口句柄时执行。**无头/单元测试环境**下 `DoDropDown` 只走到「记录 `RequestedPopup`」并触发 `OnDropDown`，绝不打开窗口——因此命中判定、路由决策、事件触发都可无头测试。
- **无菜单即普通按钮：** `DropDownMenu = nil` 时，分裂按钮点箭头区仅触发 `OnDropDown`（供处理器临时赋菜单）却不弹；菜单按钮的 `Click` 也照常触发 `OnClick`。均不崩溃。
- **`OnDropDown` 在弹出之前触发**：可在此惰性/动态构建 `DropDownMenu.Items`，做到「按需生成菜单」。
- **分裂命中用整控件宽度**：`TyDropArrowHit` 以控件**整宽**为基准把最右 `ArrowWidth` 划为箭头区（可点区域是整个右侧竖条）；而绘制的三角在内边距**之内**——即可视三角略微内缩，但可点箭头区是右侧整条，这正是分裂按钮的自然手感。
- **尺寸随 PPI 缩放**：`ArrowWidth` 是逻辑像素，命中判定与绘制都经同一套 `MulDiv`/`TTyPainter.Scale` 换算到设备像素，两者对齐。
- **不要遮蔽 `TControl`/`TComponent` 成员**：设 `DropDownMenu`、`ArrowWidth` 后 `Invalidate` 重绘。

---

## 相关

- [[TTyButton]] —— 基类，提供框架、状态、悬停渐变、角标、Default/Cancel/ModalResult。
- [[菜单|menu]] —— `TTyPopupMenu` 主题化弹出菜单（`PopUp(X, Y)` 渲染菜单树）。
- **右到左镜像：暂不支持，且是刻意的。** `TTyDropDownButton` 把按钮面切成「标题区 + 箭头区」，并且**要把点击的 x 读回来**判断按的是哪一半（`TyDropArrowHit`，`tyControls.DropButtons.pas:170`）。只镜像绘制而不镜像命中，就会得到「画在左边、点在右边」——本库已经在 `TTyShape`、`TTyTreeView.GetNodeAt`、日期选择器上栽过三次的那个 bug。所以箭头区暂时留在右侧；`tests/test.rtl.pas` 的 `TRtlExclusionTest` 把绘制与命中钉在一起，将来谁要镜像它，必须在同一次提交里把两边一起改，否则测试变红。（`TTyMenuButton` 没有内部命中，整块就是下拉，不受影响。）
