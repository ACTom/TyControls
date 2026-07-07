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
| `Checked[AIndex]: Boolean` | 读 / 写第 i 行的勾选状态。 |
| `CheckedCount: Integer` | 已勾选的行数。 |
| `OnClickCheck: TNotifyEvent` | 某行勾选状态被切换时触发。 |

另继承 `TTyListBox` 的 `Items` / `ItemIndex` / `OnChange` / 多选 等。

---

## 4. 交互

- **点击勾选框列**(行左侧约一个行高宽的区域)→ 选中该行 + 切换勾选。
- **空格键**(选中行)→ 切换勾选。
- 点击文字区 → 只选择(不切换)。

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
