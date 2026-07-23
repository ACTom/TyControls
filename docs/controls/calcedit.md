# TTyCalcEdit / TTyCalcCurrencyEdit

## 1. 概述

两个**带计算器下拉的编辑框**:尾部一个小按钮(2×2 键盘图标),点它弹出一个 [TTyCalculator](calculator.md);计算结果写回编辑框。

- **TTyCalcEdit** 继承自 [TTyNumericEdit](numericedit.md):数值输入 + 失焦分组格式化 + 限幅,再加计算器下拉。
- **TTyCalcCurrencyEdit** 继承自 [TTyCurrencyEdit](currencyedit.md):货币符号 + 分组,再加同一个计算器下拉。

两者复用同一个 `TTyCalcDropdown` 助手(管理弹层 + 计算器生命周期)和同一个尾部按钮绘制,用的正是 [TTyEdit](edit.md) 的尾部小部件钩子(`RightReserve` / `PaintTrailing` / `TrailingZone`)。

---

## 2. 单元与 typeKey

| 控件 | 单元 |
|------|------|
| TTyCalcEdit | `tyControls.CalcEdit` |
| TTyCalcCurrencyEdit | `tyControls.CalcCurrencyEdit` |

**两者的 typeKey 都是 `'TyEdit'`,这是刻意保留的借用。** `TTyCalcEdit` / `TTyCalcCurrencyEdit` 都没有覆写 `GetStyleTypeKey`,沿着 `TTyNumericEdit` → `TTyEdit` 继承下来。理由:一个带计算器下拉的数值框**就是一个编辑框**——框体、边框、内边距、文字、`:hover` / `:focus` / `:disabled` 全部与 `TTyEdit` 逐像素相同,差别只在输入过滤与尾部那颗按钮的行为。它们与普通编辑框同排出现在表单里,共用一个键才不会串色;`TyEdit.small` 之类的变体也自动同时作用于两者。

尾部按钮(2×2 键盘图标)走的是 `TTyEdit` 的尾部小部件钩子,用同一份 `TyEdit` 样式绘制,**没有**自己的键。

弹出的计算器是一个真正的 [TTyCalculator](calculator.md) 实例,它有**自己的** `'TyCalculator'` 键(背板);其显示条仍解析 `'TyEdit'`,键盘阵是真正的 `TTyButton` 子控件,走 `'TyButton'`。

| 部件 | typeKey | 自有 / 借用 |
|------|---------|------------|
| 编辑框本体 + 尾部按钮 | `'TyEdit'` | 借用(刻意:它就是一个编辑框) |
| 下拉里的计算器背板 | `'TyCalculator'` | 计算器自有 |
| 下拉里的显示条 | `'TyEdit'` | 计算器借用(遗留,见 [calculator.md](calculator.md)) |
| 下拉里的按键 | `'TyButton'` | 真实按钮子控件自有 |

```pascal
uses tyControls.CalcEdit, tyControls.CalcCurrencyEdit;
```

---

## 3. 属性 / 方法 / 事件

除各自基类(`Value` / `Decimals` / `MinValue` / `MaxValue` / `CurrencySymbol` 等)外,无新增公开成员——计算器下拉是内部行为。

---

## 4. 交互

- **点尾部按钮** → 弹出计算器,种子值 = 当前 `Value`。
- 计算器里按 **`=`** → 结果写回 `Value` 并关闭弹层;点弹层外关闭 → 也把当前值写回。
- 编辑框本身仍可正常键入(数值 / 货币行为不变)。

---

## 5. 代码示例

```pascal
uses tyControls.Controller, tyControls.CalcEdit, tyControls.CalcCurrencyEdit;

var CE: TTyCalcEdit; CC: TTyCalcCurrencyEdit;
CE := TTyCalcEdit.Create(Self);
CE.Parent := Self; CE.SetBounds(20, 20, 180, 28);
CE.Value := 1000;

CC := TTyCalcCurrencyEdit.Create(Self);
CC.Parent := Self; CC.SetBounds(20, 60, 180, 28);
CC.CurrencySymbol := '¥';
CC.Value := 1234.5;
```

---

## 6. 注意事项

- **结果写回:** 计算器按 `=` 或关闭弹层都会把当前值写回编辑框;编辑框按数值/货币规则重新格式化。
- **计算器主题跟随:** 弹出的计算器用编辑框的 `Controller` 解析主题。
- **复用共享:** 两个控件共用 `TTyCalcDropdown` + `TyDrawCalcButton`(在 `tyControls.CalcEdit` 单元),避免重复。
- **交互是真机验证项:** 编辑框数值/货币逻辑已 headless 单测(含尾部预留);计算器弹层的显示、种子、写回需真机验证。
