# TTyFontListBox

## 1. 概述

TTyFontListBox 是**字体族列表框**——[TTyFontComboBox](fontcombobox.md) 的列表版。每一行(字体族名)都**用它自己的字体绘制**。继承自 [TTyCustomListBox](listbox.md),覆写 `PaintItemContent`(与 FontComboBox 共用自由函数 `TyDrawFontRow`)。从 `Screen.Fonts` 填充,`SelectedFont` 是选中族。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.FontListBox` |
| typeKey | `'TyListBox'` / `'TyListItem'`(继承)|

无新增 `.tycss`。

```pascal
uses tyControls.FontListBox;
```

---

## 3. 属性 / 方法

| 成员 | 说明 |
|------|------|
| `SelectedFont: string` | 选中的字体族名(读=当前行;写=选中同名行,若存在)。 |
| `FixedPitchOnly: Boolean` | 只列等宽字体,默认 `False`;判断方法同 [TTyFontComboBox](fontcombobox.md#只列等宽字体)(读系统的等宽标志,不量宽度)。改它会重新填充,原来选中的字体族还在就仍选中它,不在了就什么都不选;原来没选中的仍不选中。选中的字体族没变就不触发 `OnChange` / `OnSelectionChange`,变了只触发一次。 |
| `RefreshFonts` | 重新填充;`FixedPitchOnly` 开着时只填等宽字体。 |

另继承 `TTyCustomListBox` 的 `ItemIndex` / `OnChange` 等。

---

## 4. 注意事项

- **组合 vs 列表:** 收起式选字体用 [TTyFontComboBox](fontcombobox.md);要常驻列表用本控件。
- **所见即所得:** 每行用自己的字体画(BGRA 找不到时回退)。填充来源 `Screen.Fonts`,headless 下可能为空(不崩)。和字体框一样不列 `@` 开头的竖排字体(见 [TTyFontComboBox](fontcombobox.md#6-注意事项));3.0 列出它们,4.0 起不列。
- **字体列表不存进 `.lfm`:** `Items` 是本机装的字体,不写进窗体文件,读窗体时按本机字体重新填充。3.0.0 存过的窗体里带着保存那台机器的字体列表,读完会换成本机的,并按名字选回原来的字体族(本机没有就不选)。新存的窗体只记 `ItemIndex` 序号,换一台字体不同的机器会对到别的字体;要固定某个字体族,运行时设 `SelectedFont`。
