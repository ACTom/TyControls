# TTyNumericEdit

## 1. 概述

TTyNumericEdit 是**数值编辑框**,继承自 [TTyEdit](edit.md),复用它的整套文本引擎(选区 / 撤销 / IME / 光标)与 `'TyEdit'` 主题。输入被过滤到数字 / 负号 / 小数点;**聚焦时编辑"原始值"(无千分位),失焦后重新按分组格式化显示**——从而避免"边打边格式化"带来的光标错乱。`Value` 是强类型访问器;`MinValue`/`MaxValue` 在失焦时夹紧。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.NumericEdit` |
| `GetStyleTypeKey` | `'TyEdit'`(**继承**,不覆盖)|

复用 `TTyEdit` 主题规则,无新增 `.tycss`。

```pascal
uses tyControls.NumericEdit;
```

---

## 3. 属性表

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Value` | `Double` | `0` | 强类型数值(读:解析当前文本并夹紧;写:格式化写入)。 |
| `Decimals` | `Integer` | `2` | 小数位数(0 = 整数)。 |
| `UseThousands` | `Boolean` | `True` | 是否用千分位分组显示。 |
| `MinValue` | `Double` | `0` | 下限(仅当 `MaxValue > MinValue` 时启用夹紧)。 |
| `MaxValue` | `Double` | `0` | 上限。 |

另继承 [TTyEdit](edit.md) 的全部已发布属性(`Text` / `Alignment` / `ReadOnly` / `MaxLength` / `OnChange` …)与 `Modified` 脏标记。构造时默认 `Alignment = taRightJustify`(数字右对齐)。

---

## 4. 事件

复用 `TTyEdit` 事件(`OnChange` 等)。见 [../events.md](../events.md)。

---

## 5. 行为与主题

- **输入过滤**(`UTF8KeyPress`):只放行 `0-9` / `-` / 小数分隔符(且仅当 `Decimals>0`);其余可打印字符与多字节输入一律吞掉。
- **聚焦**(`DoEnter`):去掉千分位,显示原始数字,方便编辑。
- **失焦**(`DoExit`):解析当前文本 → 夹紧到 `[MinValue,MaxValue]` → 重新分组格式化。
- **重新格式化不清 `Modified`:** 上面这三种重排(失焦分组、聚焦去分组、改 `Decimals`/`UseThousands`/`MinValue`/`MaxValue` 触发的重排)都只是控件按**同一个值**重新推导显示,不是程序覆盖用户的输入,因此 `Modified` 原样保留(原来是 `True` 就还是 `True`,原来是 `False` 也不会被凭空置脏)。只有程序写 `Value` / `Text` 才把它清成 `False`。跟 [TTySpinEdit](spinedit.md) 提交时的处理一致——同一个库里两个"数值输入框"必须对"用户碰过没有"给同一个答案。
- 视觉全部来自 `'TyEdit'`。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.NumericEdit;

TyDefaultController.LoadTheme('themes/light.tycss');

var Price: TTyNumericEdit;
Price := TTyNumericEdit.Create(Self);
Price.Parent := Self;
Price.SetBounds(20, 20, 160, 28);
Price.Decimals := 2;            // 1,234.50 样式
Price.Value := 1234.5;
// Price.Value 读回 1234.5
```

---

## 7. 注意事项

- **不边打边格式化:** 分组只在失焦时应用,编辑时是原始数字——这是刻意的(避免光标在动态插入的千分位里跳)。
- **纯逻辑可测:** `TyFormatNumber`(定点 + 分组,本地化安全)与 `TyParseNumber`(去分组 + 归一化小数点)都是纯函数,已单元测试(`test.numericedit`)。
- **粘贴:** 粘贴的非数字文本不走输入过滤,但会在失焦解析时被清理 / 归零。
- **`Modified` 用于"启用保存":** Tab 离开一个刚填好的数值框**不会**把它重新标成"未改动";要重置脏标记请显式写 `Modified := False`(保存成功之后)。
- **货币 / 掩码:** 需要货币符号用后续 `TTyCurrencyEdit`;需要输入掩码(日期 / 电话)用 `TTyMaskEdit`。
- **要步进按钮:** 用派生的 [`TTyFloatSpinEdit`](floatspinedit.md)(LCL `TFloatSpinEdit` 对标)。它只加一对上下按钮和一个 `Double` 的 `Increment`,其余全部继承本控件——**但把 `UseThousands` 的默认值翻成 `False`**,因为 LCL 的小数微调框不做千分位分组。
