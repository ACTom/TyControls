# 应用菜单按钮 (TTyRibbonAppMenu)

## 1. 概述

`TTyRibbonAppMenu` 是 Ribbon 左上角那颗醒目的应用（「文件 / File」）按钮：一颗**强调色按钮**，点击后弹出一份由**顶层命令**加上可选的**最近项目**区段组合而成的菜单。

它继承自 [[TTyMenuButton]]（单元 `tyControls.DropButtons`）——整颗按钮即下拉触发器，天然获得标题 + 尾随箭头的绘制，`Click` 会先触发 `OnDropDown` 再（有窗口句柄时）弹出下拉菜单。

> **复用 TyButton 主题，无新增 `.tycss`**：`GetStyleTypeKey` 保持返回 `'TyButton'`（继承而来）。强调外观**完全**来自 `StyleClass := 'primary'`——不引入任何新 typeKey。构造时默认 `Caption := 'File'`、`StyleClass := 'primary'`、尺寸约 64×26（逻辑像素，随 PPI 缩放）。

核心价值：应用只需分别设置 **`Commands`**（他们的「文件」菜单）和 **`RecentItems`**（一份字符串列表），本控件负责**组合**二者——且**绝不修改用户拥有的任何对象**。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.RibbonAppMenu` |
| 类 | `TTyRibbonAppMenu`（继承 [[TTyMenuButton]]） |
| `GetStyleTypeKey` 返回值 | `'TyButton'`（**继承复用**，见 [button.md](button.md)） |

```pascal
uses tyControls.Menu, tyControls.DropButtons, tyControls.RibbonAppMenu;
```

---

## 3. 属性与事件

| 成员 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Commands` | `TTyPopupMenu` | `nil` | 用户的命令菜单（他们的「文件」项树）。每次下拉时被**复制**进内部菜单，**从不被修改**。`FreeNotification` 挂钩：所指菜单被释放时自动置 `nil`。 |
| `RecentItems` | `TStrings` | 空 | 最近文件标题。非空时会在命令项下方追加一条分隔线 + 每条一行；选择某行触发 `OnRecentItemClick` 并带上其索引。控件自持存储（`Assign` 语义）。 |
| `OnRecentItemClick` | `TTyRecentItemEvent` | `nil` | 选择某个最近项时触发，`AIndex` 为该项在 `RecentItems` 中的 0 基索引。 |

`TTyRecentItemEvent` 定义于本单元：

```pascal
TTyRecentItemEvent = procedure(Sender: TObject; AIndex: Integer) of object;
```

> 继承自 [[TTyButton]] / [[TTyMenuButton]] 的常用成员（`Caption`、`Enabled`、`Font`、`StyleClass`、`Controller`、`OnClick`、`ShowBadge`/`BadgeValue`… 以及 `DropDownMenu`/`OnDropDown`）依旧可用，细节见 [button.md](button.md) 与 [dropbuttons.md](dropbuttons.md)。**注意**：`DropDownMenu` 由本控件在下拉时内部接管（指向内部组合菜单），不要手工设置它。

---

## 4. 组合机制（Commands + RecentItems）

本控件**自持一份内部 `TTyPopupMenu`（`FMenu`）**（`Create` 中创建、`Destroy` 中释放），按钮真正弹出的是它。每次下拉（重写 `DoDropDown`）都会**重建** `FMenu`：

1. 把 `Commands` 的**顶层命令项**逐个复制进 `FMenu`——每个克隆是 `FMenu` 拥有的全新 `TMenuItem`，带 `Caption` + 一个**转发式 `OnClick`**（回调时再触发源命令项自己的 `OnClick`，用户处理器照常运行）。`'-'` 标题的项自动仍是分隔线。
2. 若 `RecentItems` **非空**，追加一条分隔线 + 每条一行；每行的 `OnClick` 路由到 `OnRecentItemClick` 并带上它的索引。
3. 把继承来的 `DropDownMenu` 指向 `FMenu`，再调 `inherited DoDropDown`（触发 `OnDropDown`，并在**有窗口句柄时**弹出 `FMenu`）。

这样一来：**用户设置 `Commands`（他们的文件菜单）+ `RecentItems`（一份字符串列表），本控件把二者组合起来——用户拥有的东西一概不被改动。**

组合后的行数：

| `Commands` 顶层项数 | `RecentItems` 数 | `FMenu.Items.Count` |
|:---:|:---:|:---:|
| N | 0 | N |
| N | M > 0 | N + 1（分隔线）+ M |
| 0（`Commands = nil`） | 0 | 0 |
| 0（`Commands = nil`） | M > 0 | 1（分隔线）+ M |

> **无头安全**：重建 + 连线全程不需要窗口句柄（真正的 GUI `PopUp` 由继承的 `DoDropDown` 用 `HandleAllocated` 把守）。`Commands = nil`、`RecentItems` 空、无句柄——都不会崩溃。因此组合逻辑（受保护的 `RebuildMenu` 缝合点 + `DroppedMenuItemCount`/`DroppedMenuItem` 检视缝合点）可完全无头单测。

---

## 5. 代码示例

```pascal
uses
  Menus,
  tyControls.Controller,
  tyControls.Menu, tyControls.DropButtons, tyControls.RibbonAppMenu;

// 1) 用户自己的「文件」命令菜单（标准 LCL Items 构建，本控件绝不改动它）
var Cmds: TTyPopupMenu; Mi: TMenuItem;
Cmds := TTyPopupMenu.Create(Self);
Mi := TMenuItem.Create(Cmds); Mi.Caption := '新建'; Mi.OnClick := @DoNew;  Cmds.Items.Add(Mi);
Mi := TMenuItem.Create(Cmds); Mi.Caption := '打开…'; Mi.OnClick := @DoOpen; Cmds.Items.Add(Mi);
Mi := TMenuItem.Create(Cmds); Mi.Caption := '保存'; Mi.OnClick := @DoSave;  Cmds.Items.Add(Mi);

// 2) 应用菜单按钮：强调外观 + 组合命令与最近项
var App: TTyRibbonAppMenu;
App := TTyRibbonAppMenu.Create(Self);
App.Parent := Ribbon;                 // 通常停靠在 Ribbon 左上角
App.SetBounds(0, 0, 64, 26);
// Caption 默认 'File'、StyleClass 默认 'primary'，按需改：
App.Caption := '文件';
App.Commands := Cmds;                 // 顶层命令
App.RecentItems.Add('报告.docx');     // 最近项区段
App.RecentItems.Add('预算.xlsx');
App.OnRecentItemClick := @OpenRecent; // procedure(Sender: TObject; AIndex: Integer)
```

```pascal
procedure TForm1.OpenRecent(Sender: TObject; AIndex: Integer);
begin
  // AIndex 是 RecentItems 中的索引
  LoadDocument(TTyRibbonAppMenu(Sender).RecentItems[AIndex]);
end;
```

---

## 6. 注意事项

- **不要手工设 `DropDownMenu`**：本控件在下拉时把它接管为内部组合菜单（`FMenu`）。要改菜单内容，改 `Commands` / `RecentItems`。
- **弹菜单需要真机（GUI 窗口）**：与 [[TTyMenuButton]] 一致，真正的 `PopUp` 只在有窗口句柄时执行；无头环境只走到组合 + 触发 `OnDropDown`。
- **强调外观来自 `StyleClass`**：默认 `'primary'`。换主题类可得不同强调风格，无需新 typeKey。
- **不遮蔽基类成员**：设 `Commands` / `RecentItems` 后 `Invalidate` 重绘。

---

## 相关

- [[TTyMenuButton]] —— 基类，整按钮下拉；提供标题 + 尾随箭头绘制、`DoDropDown`、`DropDownMenu`/`OnDropDown`（见 [dropbuttons.md](dropbuttons.md)）。
- [[菜单|menu]] —— `TTyPopupMenu` 主题化弹出菜单（`PopUp(X, Y)` 渲染菜单树）。
- [[TTyRibbon]] —— 命令带宿主；应用菜单按钮通常停靠在其左上角（见 [ribbon.md](ribbon.md)）。
