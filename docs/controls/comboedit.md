# TTyComboEdit

## 1. 概述

TTyComboEdit 是**带下拉按钮的编辑框**,继承自 [TTyEdit](edit.md)。右侧保留一小块区域画下拉箭头;点击按钮(或调用 `DropDown`)触发 `OnDropDown`,由调用方在事件里弹出**任意 popup**(颜色格 / 计算器 / 日期选择器 …)并把选择写回 `Text`。它是各种"组合式编辑框"的**基座**。复用 TTyEdit 文本引擎 + `'TyEdit'` 主题,靠 `RightReserve` / `PaintTrailing` 钩子预留 + 绘制按钮。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ComboEdit` |
| `GetStyleTypeKey` | `'TyEdit'`(继承)|

无新增 `.tycss`。

```pascal
uses tyControls.ComboEdit;
```

---

## 3. 属性 / 方法 / 事件

继承 [TTyEdit](edit.md) 的全部已发布属性。

| 成员 | 类型 | 说明 |
|------|------|------|
| `OnDropDown` | `TNotifyEvent` | 点击下拉按钮 / 调 `DropDown` 时触发;在这里弹你的 popup。 |
| `DropDown` | `procedure` | 手动触发 `OnDropDown`。 |

---

## 4. 行为

右侧按钮区点击 → `DropDown` → `OnDropDown`。控件自身**不带任何 popup**,弹什么、怎么写回 `Text` 完全由 `OnDropDown` 决定。

---

## 5. 代码示例

```pascal
uses tyControls.Controller, tyControls.ComboEdit;

var C: TTyComboEdit;
C := TTyComboEdit.Create(Self);
C.Parent := Self;
C.SetBounds(20, 20, 200, 28);
C.OnDropDown := @MyDrop;   // 在 MyDrop 里弹颜色格 / 计算器,选完 C.Text := 结果;
```

---

## 6. 注意事项

- **基座控件:** `TTyColorComboBox` / `TTyCalcEdit` 等会在此之上内置具体 popup;直接用它时自己接 `OnDropDown`。
- **尾部钩子:** 与 [TTyURLEdit](urledit.md) 共用 `TTyEdit` 的 `RightReserve` / `PaintTrailing`(默认 0/空 → 普通编辑框字节一致)。
