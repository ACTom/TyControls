# TTyCalculator

## 1. 概述

TTyCalculator 是**表达式计算器**:用户按键构建一条完整表达式(如 `333*222+5`),**顶部小字实时显示整个式子供校对**,底部大字显示当前录入项 / 结果。键盘阵是 5×4 的 [TTyButton](button.md) 子控件(数字 / 工具键为 `ghost` 描边,运算符 / `=` 为实心)。按 `=` 用 `TyEvalExpr` **按运算符优先级求值**(`×÷` 先于 `+−`,`2 + 3 × 4 = 14`),支持一元负号与括号外的四则混合。引擎用 `PressKey(cmd)` 单字符驱动;`Value` / `Display`(大字行)/ `Expression`(式子)读状态。解析 / 格式化固定用 `.` 小数点(与区域设置无关)。可独立用,也作为下拉被 [TTyCalcEdit](calcedit.md) 复用。

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
- 边输入边在顶部看到完整式子(如 `333*222`),按 `=` 才求值;`=` 后再按运算符会从结果继续。
- 求值**按优先级**:`2 + 3 × 4 = 14`。
- 除以 0 / 溢出 显示 `Error`(**粘滞**:需 `C` / `CE` / `←` 才清除)。

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

- **有优先级:** `×÷` 先于 `+−`(`TyEvalExpr` 采用调度场算法),支持一元负号;暂不支持括号。
- **双行显示:** 顶部小字 = 完整表达式(校对输入),底部大字 = 当前录入项 / 结果。
- **区域无关:** 显示 / 解析固定 `.` 小数点;`Value` 是 `Double`,极大 / 极小值按 `ffGeneral` 15 位有效数字显示(结果可能是 `1E308` 科学计数,继续运算能正确解析)。
- **主题自绘:** 计算器画自己的主题面板底(不吃父容器底色,所以在下拉弹层里也不发白);按键跟随 `Controller` 主题。
- **交互是真机验证项:** 表达式引擎(优先级 / 一元负号 / 除零 / 溢出 / 退格 / ± / 清除 / 种子值 / 科学计数续算)已 headless 单测;按钮点击、键盘输入、双行绘制需真机验证。
