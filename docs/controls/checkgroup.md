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
| `Columns` | `Integer` | `1` | 子复选框排布的列数。各列等分客户区宽度，**最后一列吸收宽度余数**。填充**顺序**由 `ColumnLayout` 决定。写入 `< 1` 的值会被夹紧为 `1`。声明 `default 1`。 |
| `ColumnLayout` | `TColumnLayout`（`ExtCtrls`） | `clHorizontalThenVertical` | 网格的**填充顺序**。`clHorizontalThenVertical`（默认，也是 LCL 的默认）先横着填满第 0 行再填第 1 行，6 项 2 列读作 `1 2 / 3 4 / 5 6`；`clVerticalThenHorizontal` 先竖着填满第 0 列，读作 `1 4 / 2 5 / 3 6`。见 [§7 注意事项](#7-注意事项) 的破坏性变更说明。 |
| `OnItemChange` | `TCheckGroupItemEvent` | `nil` | 某个复选框被切换时触发，携带该项索引。见 [§4 事件](#4-事件)。 |
| `OnItemClick` | `TCheckGroupClicked` | `nil` | **与 `OnItemChange` 同一个通知**，用的是 LCL 的名字（`extctrls.pp:907`，`TCheckGroup` 在 `:955` 转发）。两个都会触发，`OnItemChange` 在前。各有独立字段，因此各按自己的名字流式化；移植过来的处理器不必改名，已有的也不必动。`TCheckGroupClicked` 是 `TCheckGroupItemEvent` 的类型别名（参数表本来就一致），所以移植的处理器**声明**也能原样编译。 |

### 自有 public 成员

| 成员 | 签名 | 说明 |
|------|------|------|
| `Checked[AIndex]` | `property Checked[AIndex: Integer]: Boolean`（**索引属性，可读写**） | 读/写第 `AIndex` 个复选框的勾选状态。**越界读写一律抛 `EListError`**，消息形如 `TTyCheckGroup Index 7 out of bounds 0 .. 2`（类名 + 越界下标 + 最大合法下标，与 LCL 同形）。编程写入**不**触发 `OnItemChange`（该事件只报告用户操作）。 |
| `Buttons[AIndex]` | `property Buttons[AIndex: Integer]: TTyCheckBox`（**索引属性，只读**） | 交出第 `AIndex` 个**托管复选框本身**，用来触及本控件没有再暴露的逐项属性——单项的 `Hint`、`PopupMenu`、`Font`、`Enabled`，或额外挂一个事件。越界抛 `EListError`，与 `Checked[]` 同形。对应 LCL `TCustomCheckGroup.Buttons[]`（`extctrls.pp:901`，public；`include/customcheckgroup.inc:321-326` 同样越界抛异常）。**分组仍然拥有子控件的生命周期与布局**：不要通过这个句柄给它换父容器或释放它。 |
| `CheckEnabled[AIndex]` | `property CheckEnabled[AIndex: Integer]: Boolean`（**索引属性，可读写**） | 单独禁用/启用某一项，其余保持可用——就是"这个选项你当前的版本没有"那种置灰。越界读写都抛 `EListError`。对应 LCL（`extctrls.pp:904`、`include/customcheckgroup.inc:288-301`）。**能扛过 `Items` 编辑**：重建时按**标题**（而不是槽位下标）恢复，和 `Checked[]` 用的是同一条身份规则——否则这就是个"demo 里能用、app 里活不过下一次列表改动"的旋钮。 |
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
| `OnItemChange` | `TCheckGroupItemEvent = procedure(Sender: TObject; AIndex: Integer) of object` | 某个复选框的勾选状态**实际改变**时触发，`AIndex` 为该项索引。只有用户点击 / 键盘空格会触发；通过 `Checked[i] :=` 编程写入**不**触发（否则"取消其它项"这类回写型处理器会自我重入），设为相同值也不触发（子复选框内部有 early-out 守卫）。 |

> **`Checked[i] :=` 不触发：** `OnItemChange` 报告的是"用户做了什么"。程序化赋值也发这个事件的话，两者就无从区分，于是"勾了这个就取消其余"这种最常见的写法会在处理器里递归回自己。写入时代码把子控件的 `OnChange` 临时置 `nil`、赋值、再还原（与 LCL `TCustomCheckGroup` 同样的抑制手法）。

> **重建期不误触发：** `Items` 变化引发重建时，代码在恢复各项勾选状态**之后**才挂接子控件的 `OnChange`，因此“重建恢复状态”这一步同样**不会**误触发 `OnItemChange`。

> 除 `OnItemChange` / `OnItemClick` 外，`TTyCheckGroup` 还暴露继承自 `TTyCustomControl` 的**基线事件集**（Tier A 鼠标 / 通用事件 + Tier B 键盘 / 焦点事件）。完整清单见 [../events.md](../events.md)。

> **键盘事件现在真的会触发（3.0 起）：** 分组框自己**永不持有焦点**——它整个表面都被子控件铺满——所以它继承来的 `OnKeyDown` / `OnKeyUp` / `OnKeyPress` / `OnUTF8KeyPress` 以前是可以赋值却永远不响的死钩子。现在每个子复选框的四个键盘事件都转接回分组框（LCL 走的是同一条路：`include/customcheckgroup.inc:238-241`、处理器 `:147-171`），焦点在任意一项上时敲的键都会到达分组框的处理器。`Key` 全程是 `var`，因此处理器吞掉一个键就真的吞掉了。

---

## 5. 布局与渲染

### 列网格布局

- 子复选框在**分组框客户区**内排列——`TTyGroupBox.AdjustClientRect` 已把客户区顶边下移到标题带之下，因此子复选框不会遮盖标题。
- `Columns` 列**等分客户区宽度**，最后一列吸收整数除法余数（无缝拼贴）。
- 填充**顺序**由 `ColumnLayout` 决定：默认 `clHorizontalThenVertical` 先横着填满一行再换行；`clVerticalThenHorizontal` 先竖着填满一列再换列。两种顺序的行数都是 `ceil(项数 / 列数)`——它们是同一张网格的两种走法，不是两张网格。
- 行距（**行高**）取 `--row-height` 与**托管复选框自身 `Constraints.MinHeight`** 中的较大者，都换算到设备像素后比较——见 `TyGroupRowPitch`（`tyControls.GroupBox`），与 `TTyRadioGroup` 共用同一条规则。
  之前这里写死 `rowH := 24`：既是硬编码视觉值，又比默认浅色主题 96ppi 下托管复选框自己要的 25 少 1px，而 LCL 会把每一次 `SetBounds` 上钳到 `MinHeight`——于是**相邻两行重叠 1px**，下面那一行（更晚创建的兄弟窗口、z 序更高）就把上一行底部刮掉，正好是 2px 焦点环下边所在的位置。与 `TTyRadioGroup` 的 3px 是同一个缺陷，只是浅一些。
- 布局在 `Items` 变化、`Columns` 变化、控件 `Resize` 与 `SetParent` 时自动重算。

### 子控件生命周期

- 每个子复选框由本控件 `Create(Self)` 拥有，标记 `csNoDesignVisible`（IDE 设计器中不可见、不可选中）。
- `Items` 变化时：先快照当前勾选状态 → `FreeAndNil` 释放旧子控件 → 按新 `Items` 创建新子控件 → 按索引恢复勾选状态 → 重新布局。整个过程有**重入守卫**（`FRebuilding`），子控件状态变动不会递归重建。
- 本控件销毁时，子控件随 owner 一并释放（析构中先清空内部数组，避免悬垂引用）。

---

## 6. 纯布局辅助函数（可单元测试）

单元级导出**纯函数**（无控件状态），是列布局的几何内核，被测试直接覆盖：

| 函数 | 签名 | 说明 |
|------|------|------|
| `TyGroupRowPitch`（在 `tyControls.GroupBox`） | `function TyGroupRowPitch(AThemeRowH, AItemMinH: Integer): Integer` | 行距规则：取两者较大值（并保证 ≥ 1），单位都是**设备像素**。`TTyCheckGroup` 与 `TTyRadioGroup` 共用。抽成纯函数是因为这条规则**在无头测试进程里不可断言**：控制台进程量出的标题字高是 9px、GUI 进程是 17px，托管复选框在测试里只要 17（< 24，不重叠）、在真机上要 25（> 24，重叠 1px），照实控件写的断言永远是假绿。真机那一半在开发期于真机上验证过。 |
| `TyCheckGroupCellRect` | `function TyCheckGroupCellRect(const AClientRect: TRect; ACount, AColumns, AIndex, ARowH: Integer; ALayout: TColumnLayout = clHorizontalThenVertical): TRect` | 第 `AIndex` 项在客户区 `AClientRect` 内的设备像素单元矩形，共 `ACount` 项、`AColumns` 列、行高 `ARowH`，按 `ALayout` 指定的顺序填充。列等分宽度（末列吸收余数）。`AIndex` 越界、`ACount <= 0`、`AColumns <= 0` 或 `ARowH <= 0` 返回空矩形。 |

```pascal
// 200px 宽、4 项、2 列、行高 20：两列各 100px、各 2 行。
// 默认（行优先）：先填满第 0 行 —— 0 1 / 2 3
TyCheckGroupCellRect(Rect(0,0,200,400), 4, 2, 0, 20);  // -> (0,0,100,20)     第 1 行左
TyCheckGroupCellRect(Rect(0,0,200,400), 4, 2, 1, 20);  // -> (100,0,200,20)   第 1 行右
TyCheckGroupCellRect(Rect(0,0,200,400), 4, 2, 2, 20);  // -> (0,20,100,40)    第 2 行左
TyCheckGroupCellRect(Rect(0,0,201,400), 4, 2, 1, 20).Right;  // -> 201（末列吸收余数）

// 列优先（旧行为，现在要显式要求）：先填满第 0 列 —— 0 2 / 1 3
TyCheckGroupCellRect(Rect(0,0,200,400), 4, 2, 1, 20, clVerticalThenHorizontal);
  // -> (0,20,100,40)  左列第 2 行
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
3. **子控件不进设计器：** 内部复选框带 `csNoDesignVisible`，不会作为可选中的子控件出现在 IDE 设计器里。请通过 `Items` 编辑标题，通过 `Checked[]` 读写状态；要触及单项的其它属性（`Hint` / `PopupMenu` / `Enabled` / `Font`），用 `Buttons[i]`。
4. **网格填充顺序改了（3.0 起的破坏性变更）：** 本控件原先**硬编码列优先**（先竖着填满第 0 列），且没有任何开关。LCL 的 `TCustomCheckGroup` 默认是行优先（`ColumnLayout = clHorizontalThenVertical`，`extctrls.pp:906`），于是同一份 .lfm 在 Lazarus 里和在这里排出来的**选项顺序不一样**——6 项 2 列，那边读作 `1 2 / 3 4 / 5 6`，这边读作 `1 4 / 2 5 / 3 6`，而且既不报错也没有别的迹象。现在默认与 LCL 一致，旧顺序仍可通过 `ColumnLayout := clVerticalThenHorizontal` 取回。**迁移**：单列分组（也就是默认的 `Columns = 1`）完全不受影响；只有多列分组需要看一眼，想保持原样就加这一行。
5. **越界访问抛异常（3.0 起的行为变更）：** `Checked[]`、`Buttons[]`、`CheckEnabled[]` 无论读写，下标越界都抛 `EListError` 并写明类名、越界下标与最大合法下标——与 LCL 的 `TCustomCheckGroup` 一致（`include/customcheckgroup.inc:173-177`、`:313-338`）。以前是越界读返回 `False`、越界写静默丢弃，而"不存在的项"和"用户没勾的项"读起来一模一样，填充顺序错了或差一都会被这层静默盖住。用 `Count` / `CheckedCount` 先问范围。
6. **`CheckEnabled[]` 按标题存活：** 逐项禁用的状态在 `Items` 重建时**按标题**恢复，与 `Checked[]` 同一条身份规则；否则改一次列表就会把置灰全部丢掉。
7. **`Controller` 传播：** 给本控件设 `Controller` 会同步应用到所有内部子复选框，整组主题保持一致。
8. **一次点击就会同时勾选并聚焦：** 本控件**不**在子控件之间轮换 `TabStop`——每个子复选框都保持 `TabStop = True`，所以 `TTyCustomControl.MouseDown` 里那道 `TabStop` 焦点闸门总是放行。`TTyRadioGroup` 需要额外修一处"点一下只挪圆点、焦点环不动"，正是因为它按平台惯例只让选中项当 Tab 位（见 [TTyRadioGroup 注意事项 §8](radiogroup.md#8-注意事项)）；这里不存在那个前提，因此也不存在那个缺陷——实测确认过，不是推断。代价是一个 N 项的复选组在 Tab 序里占 N 站，这与 LCL 的 `TCheckGroup` 一致（各项彼此独立，本来就没有"当前项"可言）。
8. **复用 `TyGroupBox` 主题：** 外框走 `TyGroupBox` 令牌，子复选框走 `TyCheckBox` 令牌；`.tycss` 中不新增 `TyCheckGroup` 规则。请确保主题为 `TyGroupBox` 声明了 `background`（用于遮盖标题处边框线，见 [TTyGroupBox 注意事项](groupbox.md#7-注意事项)）。

---

参见 [[TTyGroupBox]] —— 提供带标题的外框与客户区内缩；[[TTyCheckBox]] —— 每个组内项的子控件类型。
- **右到左镜像：** `BiDiMode := bdRightToLeft` 时列序反转（第 0 项落在最右列，往左排），每个内部复选框的指示框各自翻到右侧（靠 LCL 的 `ParentBiDiMode` 父子传播，不需要本控件伸手）。行序不动。
