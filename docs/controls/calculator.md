# TTyCalculator

## 1. 概述

TTyCalculator 是**四则运算计算器**:一条右对齐的显示条 + 一个 5×4 的键盘阵(数字键为 `ghost` 描边按钮,运算符 / `=` 为实心)。键盘阵由 [TTyButton](button.md) 子控件组成。引擎是一个普通状态机,用 `PressKey(cmd)` 单字符驱动;`Value` / `Display` 读结果。**无运算符优先级**(从左到右求值:`2 + 3 × 4 = 20`)。解析 / 格式化固定用 `.` 小数点(与区域设置无关)。可独立使用,也作为下拉被 [TTyCalcEdit](calcedit.md) 复用。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Calculator` |
| typeKey | `'TyPanel'`(背板)+ `'TyEdit'`(显示条)+ `'TyButton'`(按键)|

无新增 `.tycss`。

```pascal
uses tyControls.Calculator;
```

---

## 3. 属性 / 方法 / 事件

| 成员 | 说明 |
|------|------|
| `Value: Double` | 当前数值(错误态读为 0);写入会作为显示种子。 |
| `Display: string` | 当前显示文本(如 `3.14`,除零时为 `Error`)。 |
| `PressKey(ACmd: Char)` | 喂一个键:`0`..`9` / `.` / `+ - * /` / `=` / `C`(全清)/ `E`(清当前项)/ `B`(退格)/ `N`(±)。 |
| `Clear` | 清零、复位全部状态。 |
| `OnChange` | 任意按键后触发。 |
| `OnResult` | 按 `=` 后触发。 |

---

## 4. 交互

- **点按键** 或 **键盘输入**:`0`..`9` / `.` / `+ - * /` / `=`(或 `Enter`)/ `Backspace`(退格)/ `Esc`(全清)。
- 运算符链式从左到右;`=` 后再按运算符会从结果继续。
- 除以 0 显示 `Error`;下一个数字键自动恢复。

---

## 5. 代码示例

```pascal
uses tyControls.Controller, tyControls.Calculator;

var Calc: TTyCalculator;
Calc := TTyCalculator.Create(Self);
Calc.Parent := Self;
Calc.SetBounds(20, 20, 220, 300);
Calc.OnResult := @HandleResult;   // 读 Calc.Value
// 或者纯逻辑:Calc.PressKey('1'); Calc.PressKey('2'); Calc.PressKey('+'); ... Calc.Value
```

---

## 6. 注意事项

- **无优先级:** 有意从左到右求值(与系统计算器"标准"模式一致),不做 `×÷` 先算。
- **区域无关:** 显示 / 解析固定 `.` 小数点;`Value` 是 `Double`,极大 / 极小值按 `ffGeneral` 15 位有效数字显示。
- **按键是真按钮:** 键盘阵是 `TTyButton` 子控件,跟随本控件的 `Controller` 主题;数字用 `ghost` 变体。
- **交互是真机验证项:** 引擎(加减乘除 / 链式 / 除零 / 退格 / ± / 清除 / 种子值)已 headless 单测;按钮点击、键盘输入、绘制需真机验证。
