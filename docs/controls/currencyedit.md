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
- **曾经点一下就卡死的那个 bug,根子不在本控件。** 现象是:在真窗口上给 `TTyCurrencyEdit` 发一个 `LM_LBUTTONDOWN`,进程再也不回来(CPU 为 0,单线程)。点击本身是无辜的——真正卡住的是**释放一个正持有焦点的编辑框**:`TWinControl.Destroy` → `RemoveFocus` → `WM_KILLFOCUS` → `DoExit` → `Reformat` 写回 `Text`,而 `tyControls.Edit.pas` 的析构函数当时已经先把撤销栈释放掉了(释放后使用 → `EAccessViolation` → LCL 弹模态错误框 → 控制台进程永远等在那儿)。本控件只是**唯一一个默认值就会踩中**的:货币符号让"失焦显示态"(`$0.00`)和"聚焦编辑态"(`0.00`)不一样,于是失焦重排**真的**改了字符串;而 `TTyNumericEdit` 默认值下两者都是 `0.00`,`SetTextInternal` 的 `FText = AValue` 短路直接跨了过去。同族的 `TTyCalcCurrencyEdit` 同理默认踩中,`TTyNumericEdit`/`TTyCalcEdit` 则要持有一个带千分位的值才会踩中。**修复在 `tyControls.Edit.pas` 的析构顺序**,详见 [edit.md](edit.md) 注意事项。
- **取值干净:** `Value` 解析丢弃符号,无论符号在前在后。
- **小数位:** 继承 `TTyNumericEdit` 的 `Decimals`,默认 2(货币惯例)。
