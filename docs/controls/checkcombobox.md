# TTyCheckComboBox

## 1. 概述

TTyCheckComboBox 是**下拉为勾选列表的组合框**:点开后可勾选任意多项,**弹层不会因点选而关闭**(多选),字段里显示已勾选项的汇总(用 `Separator` 连接;一个都没勾时显示 `EmptyText`)。继承自 [TTyComboBox](combobox.md),下拉列表是一个 [TTyCheckListBox](checklistbox.md)。

每项的勾选状态存在**本组合框自己的** `Items.Objects[i]` 里的一个 `TTyCheckComboItemState` 对象(与 LCL `comboex.pas` 的 `TCheckComboItemState` 同形)——这是持久真值,跟着字符串一起被排序/插入/删除搬动,故开关弹层、排序都不丢(无并行数组)。**这个状态对象里另有一个 `Data` 字段专门放应用自己的数据**,通过控件级的 `Objects[i]` 属性读写(LCL 也是这么分的)。控件锁定为 `csDropDownList`(可编辑前缀过滤对多选无意义)。用 `Items.Add` + `Checked[]` 构建。

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
| `Objects[AIndex]: TObject` | **应用自己的每行数据**(读/写)。对应 LCL `TCustomCheckCombo.Objects[]`,存在状态对象的 `Data` 字段里,与勾选状态互不影响。用 `Items.AddObject(s, Data)` 挂上去的对象会在首次用到时被自动接管进 `Data`,所以两种顺序都行。 |
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
CC.Objects[0] := MyStyleRecord;   // 应用自己的每行数据,与勾选状态互不干扰
CC.EmptyText := '(未选择样式)';
// 字段显示:粗体   ·   CC.CheckedText / CC.CheckedCount 读取结果
```

---

## 6. 注意事项

- **应用数据用 `Objects[i]`,不是 `Items.Objects[i]`(API parity 修正):** `Items.Objects[i]` 是控件的槽位(放状态对象)。早前那里直接存的是 `0`/`1` 勾选标志,于是**应用往里存任何东西都会把勾选状态冲掉,反过来勾一下也会把应用的数据冲掉**——`Items.AddObject(s, Data)` 挂的对象甚至会被读成"已勾选"。现在改用 `CC.Objects[i] := Data` / `Data := CC.Objects[i]`(和 LCL 一样),两者各有各的字段。仍然**不要**在已经勾选过的行上直接写 `Items.Objects[i] := X`:那会把状态对象整个替换掉(不会崩、也不会泄漏,但那一行的勾选状态就没了)——这条限制 LCL 也有,而且 LCL 是直接抛异常。
- **状态对象由控件持有:** 它们挂在 `Items.Objects[]` 上但由控件自己的池负责释放;`Items.Delete` / `Items.Clear` / 重新填表都不会泄漏(池会在长大到一定程度时清扫掉够不着的状态)。
- **只读多选:** 控件锁定 `csDropDownList`,忽略改成 `csDropDown` 的尝试(多选没有单一"选中项",可编辑字段无意义)。
- **弹层常开靠基类钩子:** 基类把弹层点选行为抽成了 `DoPopupPick`,本控件覆写为空以"切换而不关闭";其余组合框仍是"选中即关闭"。
- **交互是真机验证项:** 纯逻辑(勾选状态 / 汇总 / 分隔符 / 排序不丢 / 锁定只读)已 headless 单测;弹层常开与实时同步需真机验证。
