# TTyCheckComboBox

## 1. 概述

TTyCheckComboBox 是**下拉为勾选列表的组合框**:点开后可勾选任意多项,**弹层不会因点选而关闭**(多选),字段里显示已勾选项的汇总(用 `Separator` 连接;一个都没勾时显示 `EmptyText`)。继承自 [TTyComboBox](combobox.md),下拉列表是一个 [TTyCheckListBox](checklistbox.md)。

每项的状态存在**本组合框自己的** `Items.Objects[i]` 里的一个 `TTyCheckComboItemState` 对象(与 LCL `comboex.pas:263` 的 `TCheckComboItemState` 同形:`State` + `Enabled` + `Data`)——这是持久真值,跟着字符串一起被排序/插入/删除搬动,故开关弹层、排序都不丢(无并行数组)。**状态是三态的**(`State[]` / `AllowGrayed`),另有**每行的启用标志**(`ItemEnabled[]`);`Checked[]` 是同一个槽位的两态视图。**状态对象里还有一个 `Data` 字段专门放应用自己的数据**,通过控件级的 `Objects[i]` 属性读写(LCL 也是这么分的)。控件锁定为 `csDropDownList`(可编辑前缀过滤对多选无意义)。用 `AddItem(文本, 状态)` 构建,或者照旧 `Items.Add` + `Checked[]`。

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
| `Checked[AIndex]: Boolean` | 第 i 项是否勾选(读/写;写会同步已打开的弹层)。等价于 `State[i] = cbChecked`——**`cbGrayed` 读作"未勾选"**,不进汇总也不计入 `CheckedCount`。 |
| `State[AIndex]: TCheckBoxState` | **（API parity 新增）** 完整三态:`cbUnchecked` / `cbChecked` / `cbGrayed`。写入会触发 `OnItemChange`。`cbGrayed` 就是"部分选中 / 继承"那一行。 |
| `ItemEnabled[AIndex]: Boolean` | **（API parity 新增）** 每行的启用标志(默认 `True`)。禁用的行**照常显示**(画成 `:disabled` 的样子)、**代码照常可写**,但用户在弹层里的点击 / 空格会被**拒绝**——就是"本许可证不可用,置灰但别删掉"那个模式。 |
| `AllowGrayed: Boolean`(published,默认 `False`) | **（API parity 新增）** 让用户的切换能经过 `cbGrayed`。 |
| `Objects[AIndex]: TObject` | **应用自己的每行数据**(读/写)。对应 LCL `TCustomCheckCombo.Objects[]`,存在状态对象的 `Data` 字段里,与勾选状态互不影响。用 `Items.AddObject(s, Data)` 挂上去的对象会在首次用到时被自动接管进 `Data`,所以两种顺序都行。 |
| `CheckedCount: Integer` | 已勾选项数(`cbChecked` 才算)。 |
| `CheckedText: string` | 字段汇总(勾选项文本用 `Separator` 连接;为空时是 `EmptyText`)。 |
| `Separator: string` | 汇总分隔符(默认 `', '`)。 |
| `EmptyText: string` | 一个都没勾时字段显示的文字(默认 `''`)。`EmptyText` 也为空时回落到继承来的 `TextHint` 占位文字。 |
| `AddItem(AItem; AState; AEnabled = True)` | **（API parity 新增）** 一次调用追加一行连同它的状态。从前要 `Items.Add` 再 `Checked[Items.Count-1]`——那个索引写错就勾到上一行去了。**重载**继承来的 `AddItem(text, TObject)`,不遮蔽它。 |
| `AssignItems(AItems: TStrings)` | **（API parity 新增）** 批量装载,旧状态全部丢弃。 |
| `DeleteItem(AIndex)` | **（API parity 新增）** 删一行(它的状态由池回收)。 |
| `CheckAll(AState; AAllowGrayed = True; AAllowDisabled = True)` | **（API parity 新增）** 批量置位。`AAllowGrayed = False` 跳过当前是 `cbGrayed` 的行,`AAllowDisabled = False` 跳过禁用行——"把用户真正能改的都勾上"是一次调用,不是一个要自己写对排除条件的循环。 |
| `Toggle(AIndex)` | **（API parity 新增）** 按点击会走的顺序推进一行。 |
| `OnChange` | 勾选发生变化时触发(继承自 `TTyComboBox`,**不带索引**)。 |
| `OnItemChange: TTyCheckItemChangeEvent` | **（API parity 新增）** `procedure(Sender: TObject; AIndex: Integer)`。告诉你**是哪一行**变了,用户切换和**程序化写入**都会触发。从前程序化 `Checked[i] := True` **什么都不发**,绑在组合框上的视图会静默变旧。 |

另继承 `TTyComboBox` 的 `Items` / `Sorted` / `DropDownCount` / `TextHint` 等。

---

## 4. 交互

- 点开下拉 → 每行一个复选框(**三态 + 禁用态都画得出来**:弹层用的是本单元自己的 `TTyCheckComboPopupList`,从宿主组合框读三态,基类 `TTyCheckListBox` 只有两态)。
- **点复选框列 / 按空格** 切换该项;弹层**保持打开**,字段汇总实时更新。
- **切换顺序**(与 LCL `comboex.inc:842` 一致,注意与 `TTyCheckBox` 不同):
  - `AllowGrayed = False`:未勾 → 勾上 → 未勾。
  - `AllowGrayed = True`:未勾 → **半选** → 勾上 → 未勾。
- **`ItemEnabled[i] = False` 的行拒绝用户的切换**(弹层的勾会被弹回原值);`Checked[]` / `State[]` / `CheckAll` 走属性写入,**不受**否决——代码想改就能改。
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
CC.AllowGrayed := True;
CC.AddItem('粗体',   cbChecked);            // 一次调用:文本 + 状态
CC.AddItem('斜体',   cbGrayed);             // 半选 = "部分选中 / 继承"
CC.AddItem('下划线', cbUnchecked, False);   // 显示但禁用:用户点不动,代码改得了
CC.Objects[0] := MyStyleRecord;   // 应用自己的每行数据,与勾选状态互不干扰
CC.EmptyText := '(未选择样式)';
CC.OnItemChange := @StyleItemChanged;       // 告诉你是哪一行变了
// 字段显示:粗体   ·   CC.CheckedText / CC.CheckedCount 读取结果
// CC.CheckAll(cbChecked, False, False);    // 只勾"用户真能改"的行
```

---

## 6. 注意事项

- **应用数据用 `Objects[i]`,不是 `Items.Objects[i]`(API parity 修正):** `Items.Objects[i]` 是控件的槽位(放状态对象)。早前那里直接存的是 `0`/`1` 勾选标志,于是**应用往里存任何东西都会把勾选状态冲掉,反过来勾一下也会把应用的数据冲掉**——`Items.AddObject(s, Data)` 挂的对象甚至会被读成"已勾选"。现在改用 `CC.Objects[i] := Data` / `Data := CC.Objects[i]`(和 LCL 一样),两者各有各的字段。仍然**不要**在已经勾选过的行上直接写 `Items.Objects[i] := X`:那会把状态对象整个替换掉(不会崩、也不会泄漏,但那一行的勾选状态就没了)——这条限制 LCL 也有,而且 LCL 是直接抛异常。
- **状态对象由控件持有:** 它们挂在 `Items.Objects[]` 上但由控件自己的池负责释放;`Items.Delete` / `Items.Clear` / 重新填表都不会泄漏(池会在长大到一定程度时清扫掉够不着的状态)。
- **只读多选:** 控件锁定为**不可编辑**(多选没有单一"选中项",可编辑字段无意义):写进来的 `Style` 只被摘掉编辑框那一位——`csDropDown` → `csDropDownList`,`csOwnerDrawEditableFixed` → `csOwnerDrawFixed`——而不是整个换成 `csDropDownList`。这正是 LCL 的 `TComboBoxStyleHelper.SetEditBox(False)`,也是自绘能设进来的原因:自绘与可编辑是两件正交的事。
- **自绘行支持:** `Style := csOwnerDrawFixed` + `OnDrawItem` 时下拉行整行交给应用画——**包括那一行的勾选框**,因为你要的就是整行自己画。点击切换不受影响(命中测试不在绘制路径上)。协议与限制见 [combobox.md §8.2](combobox.md#82-自绘csownerdrawfixed--csownerdraweditablefixed--ondrawitem)。
- **弹层常开靠基类钩子:** 基类把弹层点选行为抽成了 `DoPopupPick`,本控件覆写为空以"切换而不关闭";其余组合框仍是"选中即关闭"。
- **`TTyCheckComboItemState.Checked` 改名为 `State`(BREAKING):** 状态对象的字段从 `Checked: Boolean` 变成 `State: TCheckBoxState`(并新增 `Enabled: Boolean`),与 LCL 同名同型。直接摸这个对象的代码要改;走 `Checked[]` 属性的代码**不受影响**。
- **切换顺序与 `TTyCheckBox` 不同:** 这里是 LCL `TCustomCheckCombo` 的顺序(未勾 → **半选** → 勾上),`TTyCheckBox` 是(未勾 → 勾上 → 半选)。两边各自对齐各自的 LCL 对应物。
- **未做(与 LCL `TCheckComboBox` 的差异):** 没有 `Count` 属性(用继承来的 `Count` 方法);`TextHint` 只在 `EmptyText` 为空时才顶上。
- **交互是真机验证项:** 纯逻辑(三态 / 启用标志 / `CheckAll` 排除 / `Toggle` 顺序 / `OnItemChange` 带索引 / 增删装载 / 汇总 / 分隔符 / 排序不丢 / 锁定只读 / `Objects[]` 不被勾选冲掉)已 headless 单测;弹层常开、三态与禁用行的**绘制**、以及禁用行拒绝点击的**真实鼠标路径**需真机验证。
