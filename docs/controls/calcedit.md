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

typeKey 同各自基类(`'TyEdit'`);弹出的计算器用 `'TyPanel'` / `'TyEdit'` / `'TyButton'`。无新增 `.tycss`。

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
