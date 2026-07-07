# TTyCheckGroup

## 1. 概述

`TTyCheckGroup` 是 TyControls 库中的**复选组**容器控件，继承自 [`TTyGroupBox`](groupbox.md)。它在一个带标题的圆角边框内，为 `Items` 中的每一项**自动生成一个 [`TTyCheckBox`](checkbox.md) 子控件**，并按列网格布局排列。

与单选组（RadioGroup）不同，组内的复选框是**互相独立**的——没有互斥关系，可任意组合勾选。典型用途：多选偏好设置（如“通知方式：邮件 / 短信 / 推送”）、功能开关面板、标签过滤器等。

自动生成的复选框是**内部辅助控件**：它们由本控件拥有（owned）、带 `csNoDesignVisible` 标志，因此**不会泄漏到 IDE 设计器**中作为可选中的独立子控件。`Items` 变化时整组子控件重建，并**按索引保留原有的勾选状态**（仍在范围内的项保持原状态，新增项默认未勾选）。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.CheckGroup` |
| `GetStyleTypeKey` 返回值 | `'TyGroupBox'`（**继承自 `TTyGroupBox`，不新增 `.tycss` 选择器**） |
| 基类 | `TTyGroupBox`（`tyControls.GroupBox`） → `TTyCustomControl`（`tyControls.Base`） |
| 默认尺寸 | 185 × 130（逻辑像素） |
| 子复选框行距 | 24 逻辑像素（每个复选框 22 高，按 DPI 缩放） |

> **复用 `TyGroupBox` 令牌：** 外框与标题带直接使用分组框主题绘制；子复选框各自解析 `TyCheckBox` 令牌。`.tycss` 中**不存在** `TyCheckGroup` 选择器。

```pascal
uses tyControls.CheckGroup;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Items` | `TStrings` | `[]`（空列表） | 各复选项的标题列表。内部由 `TStringList` 支撑（以获得 `OnChange`），声明类型为 `TStrings`。写入时调用 `Assign` 复制内容；列表变化（增删改）自动**重建全部子复选框**、重新布局并重绘。标题支持 `&` 助记符显示（下划线）。 |
| `Columns` | `Integer` | `1` | 子复选框排布的列数。各列等分客户区宽度，**最后一列吸收宽度余数**；每列自上而下填满后再填下一列（column-major）。写入 `< 1` 的值会被夹紧为 `1`。声明 `default 1`。 |
| `OnItemChange` | `TCheckGroupItemEvent` | `nil` | 某个复选框被切换时触发，携带该项索引。见 [§4 事件](#4-事件)。 |

### 自有 public 成员

| 成员 | 签名 | 说明 |
|------|------|------|
| `Checked[AIndex]` | `property Checked[AIndex: Integer]: Boolean`（**索引属性，可读写**） | 读/写第 `AIndex` 个复选框的勾选状态。**越界读**返回 `False`；**越界写**为安全空操作（不崩溃）。写入会触发对应子控件的 `OnChange`，进而触发 `OnItemChange`。 |
| `Count` | `function Count: Integer` | 子复选框数量（`= Items.Count`）。 |
| `CheckedCount` | `function CheckedCount: Integer` | 当前处于勾选状态的项数。 |

### 继承的通用成员

`TTyCheckGroup` 从 [`TTyGroupBox`](groupbox.md) 继承：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Caption` | `string` | `''` | 顶部嵌入边框线的标题文字。 |
| `Alignment` | `TAlignment` | `taLeftJustify` | 标题在顶部边框带内的水平对齐。 |
| `Align` / `Anchors` | — | — | 停靠 / 锚点布局。 |
| `StyleClass` | `string` | `''` | CSS 变体类名（作用于外框；子复选框各自解析 `TyCheckBox`）。 |
| `Controller` | `TTyStyleController` | `nil`（全局默认） | 关联的样式控制器。**赋值会同步传播给所有内部子复选框**，保证整组主题一致。 |

---

## 4. 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnItemChange` | `TCheckGroupItemEvent = procedure(Sender: TObject; AIndex: Integer) of object` | 某个复选框的勾选状态**实际改变**时触发，`AIndex` 为该项索引。用户点击、键盘空格、或通过 `Checked[i] :=` 编程改变均会触发；设为相同值不触发（子复选框内部有 early-out 守卫）。 |

> **重建期不误触发：** `Items` 变化引发重建时，代码在恢复各项勾选状态**之后**才挂接子控件的 `OnChange`，因此“重建恢复状态”这一步**不会**误触发 `OnItemChange`——只有真正的用户/编程切换才会。

> 除 `OnItemChange` 外，`TTyCheckGroup` 还暴露继承自 `TTyCustomControl` 的**基线事件集**（Tier A 鼠标 / 通用事件 + Tier B 键盘 / 焦点事件）。完整清单见 [../events.md](../events.md)。

---

## 5. 布局与渲染

### 列网格布局（column-major）

- 子复选框在**分组框客户区**内排列——`TTyGroupBox.AdjustClientRect` 已把客户区顶边下移到标题带之下，因此子复选框不会遮盖标题。
- `Columns` 列**等分客户区宽度**，最后一列吸收整数除法余数（无缝拼贴）。
- 每列**自上而下**填满后再填下一列（先纵后横）。项数不能整除列数时，靠前的列多一行。
- 每个复选框行高固定为 24 逻辑像素（按 `Font.PixelsPerInch` 缩放），复选框本体 22 高。
- 布局在 `Items` 变化、`Columns` 变化、控件 `Resize` 与 `SetParent` 时自动重算。

### 子控件生命周期

- 每个子复选框由本控件 `Create(Self)` 拥有，标记 `csNoDesignVisible`（IDE 设计器中不可见、不可选中）。
- `Items` 变化时：先快照当前勾选状态 → `FreeAndNil` 释放旧子控件 → 按新 `Items` 创建新子控件 → 按索引恢复勾选状态 → 重新布局。整个过程有**重入守卫**（`FRebuilding`），子控件状态变动不会递归重建。
- 本控件销毁时，子控件随 owner 一并释放（析构中先清空内部数组，避免悬垂引用）。

---

## 6. 纯布局辅助函数（可单元测试）

单元级导出一个**纯函数**（无控件状态），是列布局的几何内核，被测试直接覆盖：

| 函数 | 签名 | 说明 |
|------|------|------|
| `TyCheckGroupCellRect` | `function TyCheckGroupCellRect(const AClientRect: TRect; ACount, AColumns, AIndex, ARowH: Integer): TRect` | 第 `AIndex` 项在客户区 `AClientRect` 内的设备像素单元矩形，共 `ACount` 项、`AColumns` 列、行高 `ARowH`。列等分宽度（末列吸收余数），列内自上而下（column-major）。`AIndex` 越界、`ACount <= 0`、`AColumns <= 0` 或 `ARowH <= 0` 返回空矩形。 |

```pascal
// 200px 宽、4 项、2 列、行高 20：两列各 100px、各 2 行，先填左列。
TyCheckGroupCellRect(Rect(0,0,200,400), 4, 2, 0, 20);  // -> (0,0,100,20)     左列第 1 行
TyCheckGroupCellRect(Rect(0,0,200,400), 4, 2, 1, 20);  // -> (0,20,100,40)    左列第 2 行
TyCheckGroupCellRect(Rect(0,0,200,400), 4, 2, 2, 20);  // -> (100,0,200,20)   右列第 1 行
TyCheckGroupCellRect(Rect(0,0,201,400), 4, 2, 2, 20).Right;  // -> 201（末列吸收余数）
```

---

## 7. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.CheckGroup;

// 加载主题（通常在窗体 Create 顶部执行一次）
TyDefaultController.LoadTheme('themes/light.tycss');

var Notify: TTyCheckGroup;
Notify := TTyCheckGroup.Create(Self);
Notify.Parent := Self;
Notify.SetBounds(20, 20, 220, 130);
Notify.Caption := '通知方式';
Notify.Columns := 1;
Notify.Items.Add('电子邮件');
Notify.Items.Add('短信');
Notify.Items.Add('应用推送');
Notify.Checked[0] := True;                 // 默认勾选“电子邮件”
Notify.OnItemChange := @NotifyItemChanged;

procedure TMainForm.NotifyItemChanged(Sender: TObject; AIndex: Integer);
var G: TTyCheckGroup;
begin
  G := Sender as TTyCheckGroup;
  // AIndex 为刚切换的项；也可读取整组状态：
  ShowMessage(Format('第 %d 项 = %s；共勾选 %d 项',
    [AIndex, BoolToStr(G.Checked[AIndex], True), G.CheckedCount]));
end;

// —— 两列布局 ——
var Feats: TTyCheckGroup;
Feats := TTyCheckGroup.Create(Self);
Feats.Parent := Self;
Feats.SetBounds(260, 20, 260, 130);
Feats.Caption := '启用功能';
Feats.Columns := 2;                        // 6 项将排成 2 列 × 3 行
Feats.Items.CommaText := '自动保存,拼写检查,深色模式,行号,自动缩进,代码折叠';
```

---

## 8. 注意事项

1. **子复选框独立无互斥：** 与单选组不同，勾选一项不会取消其它项——各项完全独立。若需要互斥，请改用单选组（RadioGroup）。
2. **`Items` 变化会重建整组子控件：** 增删改任一项都会释放并重建全部子复选框；勾选状态**按索引**保留（仍在范围内的项保持原状态，新增项默认未勾选，被删项状态丢弃）。若需精确的“按内容”迁移，请在赋值前后自行记录/恢复。
3. **子控件不进设计器：** 内部复选框带 `csNoDesignVisible`，不会作为可选中的子控件出现在 IDE 设计器里。请通过 `Items` 编辑标题，通过 `Checked[]` 读写状态。
4. **越界访问安全：** `Checked[]` 越界读返回 `False`、越界写为空操作，不崩溃。
5. **`Controller` 传播：** 给本控件设 `Controller` 会同步应用到所有内部子复选框，整组主题保持一致。
6. **复用 `TyGroupBox` 主题：** 外框走 `TyGroupBox` 令牌，子复选框走 `TyCheckBox` 令牌；`.tycss` 中不新增 `TyCheckGroup` 规则。请确保主题为 `TyGroupBox` 声明了 `background`（用于遮盖标题处边框线，见 [TTyGroupBox 注意事项](groupbox.md#7-注意事项)）。

---

参见 [[TTyGroupBox]] —— 提供带标题的外框与客户区内缩；[[TTyCheckBox]] —— 每个组内项的子控件类型。
