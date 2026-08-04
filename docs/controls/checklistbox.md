# TTyCheckListBox

## 1. 概述

TTyCheckListBox 是**每行带勾选框的列表框**。继承自 [TTyListBox](listbox.md),覆写 `PaintItemContent` 在每行左侧画一个勾选框 + 文字。**勾选状态存在 `Items.Objects[i]`(0/1)**,与条目天然对齐(排序 / 删除都跟着走,不会错位)。点击勾选框列、或在选中行按**空格**即可切换;其余选择行为同 `TTyListBox`。勾选框外观取自 `'TyCheckBox'` 主题。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.CheckListBox` |
| typeKey | `'TyListBox'` / `'TyListItem'`(行)+ `'TyCheckBox'`(勾选框)|

无新增 `.tycss`。

```pascal
uses tyControls.CheckListBox;
```

---

## 3. 属性 / 方法 / 事件

| 成员 | 说明 |
|------|------|
| `Checked[AIndex]: Boolean` | 读 / 写第 i 行的勾选状态。**读的时候 `cbGrayed` 算「已勾选」**(即「不是全关」,对齐 LCL `checklst.pas:279-282`);写 True/False 直接落到 `cbChecked` / `cbUnchecked`。 |
| `State[AIndex]: TCheckBoxState` | 完整三态:`cbUnchecked` / `cbChecked` / `cbGrayed`。**「部分选中」的行**(子项不一致的父行)以前根本没法表达。 |
| `ItemEnabled[AIndex]: Boolean` | 单独禁用某一行:按主题的 disabled 行样式渲染,点击和空格都切不动它。选项表里有些选项不可用(授权限制、互斥)时,不必再删行或在事件里跟控件较劲。 |
| `AllowGrayed: Boolean` | **published**,默认 False。用户切换时是否经过 `cbGrayed`。与 `TTyCheckBox` 同名同默认。 |
| `Toggle(AIndex)` | 按状态环推进一格:关→开→关;`AllowGrayed` 打开时 关→灰→开→关(LCL `NextStateMap`)。**禁用行不动**。 |
| `CheckAll(AState, aAllowGrayed=True, aAllowDisabled=True)` | 把所有行置为 `AState`;两个开关分别用于跳过已是 `cbGrayed` 的行、跳过被 `ItemEnabled` 关掉的行。 |
| `CheckedCount: Integer` | 已勾选的行数(`cbGrayed` 计入)。 |
| `OnClickCheck: TNotifyEvent` | 某行勾选状态被切换时触发。 |

另继承 `TTyListBox` 的 `Items` / `ItemIndex` / `OnChange` / 多选 等。

### 3.1 逐行状态存在哪

三样东西打包在同一个 `Items.Objects[i]` 里:

| 位 | 含义 |
|----|------|
| 0-1 | `Ord(State)` |
| 2 | 禁用位(**0 表示启用**) |

这样 `nil`(没碰过的行)天然等于「启用 + 未勾选」,而且历史上只写 0/1 的列表原样读得对。

> **应用自己的对象放进 `Items.Objects[]` 时**:凡是落在上述位以外的值都不认作状态,该行按「启用 + 未勾选」读,
> 下一次写会**整槽覆盖**而不是就地改低位。以前是「非 0 就算勾上」,于是每个挂了应用对象的行一出场就是勾选的。

---

## 4. 交互

- **点击勾选框列**(行左侧约一个行高宽的区域)→ 选中该行 + 切换勾选。
- **空格键**(选中行)→ 切换勾选。禁用行上空格**仍被吃掉**(该行就是当前行,放行会触发窗体的默认按钮)。
- 点击文字区 → 只选择(不切换)。
- 被 `ItemEnabled[i] := False` 关掉的行:点击、空格、`Toggle` 都不动它,并按 disabled 样式渲染。

---

## 5. 代码示例

```pascal
uses tyControls.Controller, tyControls.CheckListBox;

var CL: TTyCheckListBox;
CL := TTyCheckListBox.Create(Self);
CL.Parent := Self;
CL.SetBounds(20, 20, 180, 200);
CL.Items.Add('选项 A');
CL.Items.Add('选项 B');
CL.Checked[0] := True;
// if CL.CheckedCount > 0 then ...
```

---

## 6. 注意事项

- **Objects 被占用:** 勾选状态存在 `Items.Objects[i]`——所以**别再用 `Objects` 存自己的数据**(这是刻意的:并行数组会在排序时错位,见 [colorbox.md](colorbox.md) 的同一教训)。
- **交互是真机验证项:** 纯状态逻辑(`Checked` / `CheckedCount` / 排序不错位)已 headless 单测;鼠标 / 空格切换需真机验证。
