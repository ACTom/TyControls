# TTyCheckComboBox

## 1. 概述

TTyCheckComboBox 是**下拉为勾选列表的组合框**:点开后可勾选任意多项,**弹层不会因点选而关闭**(多选),字段里显示已勾选项的汇总(用 `Separator` 连接;一个都没勾时显示 `EmptyText`)。继承自 [TTyComboBox](combobox.md),下拉列表是一个 [TTyCheckListBox](checklistbox.md)。

每项的勾选状态存在**本组合框自己的** `Items.Objects[i]`(`0`/`1`)——这是持久真值,开弹层时经 `Items.Assign` 拷进弹层的勾选列表,每次勾选再同步回来,故开关弹层、排序都不丢(无并行数组)。控件锁定为 `csDropDownList`(可编辑前缀过滤对多选无意义)。用 `Items.Add` + `Checked[]` 构建。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.CheckComboBox` |
| typeKey | `'TyComboBox'`(字段)/ `'TyListBox'` + `'TyCheckBox'`(弹层每行的复选框)|

无新增 `.tycss`。

```pascal
uses tyControls.CheckComboBox;
```

---

## 3. 属性 / 方法 / 事件

| 成员 | 说明 |
|------|------|
| `Checked[AIndex]: Boolean` | 第 i 项是否勾选(读/写;写会同步已打开的弹层)。 |
| `CheckedCount: Integer` | 已勾选项数。 |
| `CheckedText: string` | 字段汇总(勾选项文本用 `Separator` 连接;为空时是 `EmptyText`)。 |
| `Separator: string` | 汇总分隔符(默认 `', '`)。 |
| `EmptyText: string` | 一个都没勾时字段显示的文字(默认 `''`)。 |
| `OnChange` | 勾选发生变化时触发(继承自 `TTyComboBox`)。 |

另继承 `TTyComboBox` 的 `Items` / `Sorted` / `DropDownCount` 等。

---

## 4. 交互

- 点开下拉 → 每行一个复选框。**点复选框列 / 按空格** 切换该项;弹层**保持打开**,字段汇总实时更新。
- 点弹层外部 / 按 `Esc` → 关闭弹层(不影响已勾选状态)。
- 代码里 `Checked[i] := True/False` 编程勾选;若弹层正开着也会同步。

---

## 5. 代码示例

```pascal
uses tyControls.Controller, tyControls.CheckComboBox;

var CC: TTyCheckComboBox;
CC := TTyCheckComboBox.Create(Self);
CC.Parent := Self;
CC.SetBounds(20, 20, 220, 28);
CC.Items.Add('粗体');
CC.Items.Add('斜体');
CC.Items.Add('下划线');
CC.Checked[0] := True;
CC.EmptyText := '(未选择样式)';
// 字段显示:粗体   ·   CC.CheckedText / CC.CheckedCount 读取结果
```

---

## 6. 注意事项

- **Objects 被占用:** 勾选状态存在 `Items.Objects[i]`——**别再用 `Objects` 存自己的数据**(并行数组会在排序时错位)。
- **只读多选:** 控件锁定 `csDropDownList`,忽略改成 `csDropDown` 的尝试(多选没有单一"选中项",可编辑字段无意义)。
- **弹层常开靠基类钩子:** 基类把弹层点选行为抽成了 `DoPopupPick`,本控件覆写为空以"切换而不关闭";其余组合框仍是"选中即关闭"。
- **交互是真机验证项:** 纯逻辑(勾选状态 / 汇总 / 分隔符 / 排序不丢 / 锁定只读)已 headless 单测;弹层常开与实时同步需真机验证。
