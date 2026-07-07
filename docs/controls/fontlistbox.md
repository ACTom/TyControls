# TTyFontListBox

## 1. 概述

TTyFontListBox 是**字体族列表框**——[TTyFontComboBox](fontcombobox.md) 的列表版。每一行(字体族名)都**用它自己的字体绘制**。继承自 [TTyListBox](listbox.md),覆写 `PaintItemContent`(与 FontComboBox 共用自由函数 `TyDrawFontRow`)。从 `Screen.Fonts` 填充,`SelectedFont` 是选中族。

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
| `RefreshFonts` | 重新从 `Screen.Fonts` 填充。 |

另继承 `TTyListBox` 的 `ItemIndex` / `OnChange` 等。

---

## 4. 注意事项

- **组合 vs 列表:** 收起式选字体用 [TTyFontComboBox](fontcombobox.md);要常驻列表用本控件。
- **所见即所得:** 每行用自己的字体画(BGRA 找不到时回退)。填充来源 `Screen.Fonts`,headless 下可能为空(不崩)。
