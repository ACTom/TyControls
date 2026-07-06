# TTyCurrencyEdit

## 1. 概述

TTyCurrencyEdit 是**货币编辑框**,继承自 [TTyNumericEdit](numericedit.md),只在**分组显示形态(失焦)**上额外加一个货币符号。输入过滤、编辑原始值 / 失焦分组格式化、夹紧、`'TyEdit'` 主题全部继承。符号只出现在显示态,**聚焦编辑态是干净可编辑的数字**;解析会丢弃非数字字符,所以取值不受符号影响。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.CurrencyEdit` |
| `GetStyleTypeKey` | `'TyEdit'`(经 `TTyNumericEdit` 继承)|

无新增 `.tycss`。

```pascal
uses tyControls.CurrencyEdit;
```

---

## 3. 属性表

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `CurrencySymbol` | `string` | `'$'` | 货币符号(支持多字节如 `¥` / `€`)。 |
| `SymbolBefore` | `Boolean` | `True` | 符号在数字前(`$1,234.50`)还是后(`1,234.50$`)。 |

另继承 [TTyNumericEdit](numericedit.md) 的 `Value` / `Decimals`(默认 2)/ `UseThousands` / `MinValue` / `MaxValue`,以及 `TTyEdit` 的全部已发布属性。

---

## 4. 事件

复用 `TTyEdit` 事件(`OnChange` 等)。

---

## 5. 行为与主题

覆写 `TTyNumericEdit.Formatted`(protected virtual):仅当 `AGroup=True`(失焦显示态)时把符号包到数字上;`AGroup=False`(聚焦编辑态)保持纯数字,便于编辑。其余全部继承。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.CurrencyEdit;

TyDefaultController.LoadTheme('themes/light.tycss');

var Price: TTyCurrencyEdit;
Price := TTyCurrencyEdit.Create(Self);
Price.Parent := Self;
Price.SetBounds(20, 20, 180, 28);
Price.CurrencySymbol := '¥';
Price.Value := 1234.5;      // 显示 ¥1,234.50;Price.Value 读回 1234.5
```

---

## 7. 注意事项

- **符号不入编辑态:** 聚焦时看不到符号(纯数字好编辑),失焦重新包裹。
- **取值干净:** `Value` 解析丢弃符号,无论符号在前在后。
- **小数位:** 继承 `TTyNumericEdit` 的 `Decimals`,默认 2(货币惯例)。
