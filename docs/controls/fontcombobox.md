# TTyFontComboBox

## 1. 概述

TTyFontComboBox 是**字体族组合框**:字段和下拉列表的每一项都**用它自己的字体绘制**(所见即所得的字体选择器)。继承自 [TTyCustomComboBox](combobox.md),覆写 `CreatePopupList`(注入一个按行字体绘制的下拉列表)和 `PaintFieldContent`(字段用选中字体绘制)。列表从 `Screen.Fonts`(已安装字体族)填充。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.FontComboBox` |
| typeKey | `'TyComboBox'` / `'TyListItem'`(继承)|

无新增 `.tycss`。

```pascal
uses tyControls.FontComboBox;
```

---

## 3. 属性 / 方法

| 成员 | 说明 |
|------|------|
| `SelectedFont: string` | 选中的字体族名(== `Text`);写入会选中同名项(若存在)。 |
| `FixedPitchOnly: Boolean` | 只列等宽字体,默认 `False`。改它会重新填充列表,原来选中的字体族还在就仍选中它,不在了就选第一项。见下文「只列等宽字体」。 |
| `RefreshFonts` | 重新填充(装了新字体后调用);`FixedPitchOnly` 开着时只填等宽字体。 |

另继承 `TTyCustomComboBox` 的 `Items` / `ItemIndex` / `OnChange` / `OnSelect` 等。

---

## 4. 机制

`PaintItemContent` 把每行文字的**字体名设成该行文字本身**,于是每个字体族名用它自己的字体渲染;`PaintFieldContent` 对选中项做同样处理。都建立在 [colorbox.md](colorbox.md) 引入的逐项自绘钩子之上。

---

## 5. 代码示例

```pascal
uses tyControls.Controller, tyControls.FontComboBox;

var FC: TTyFontComboBox;
FC := TTyFontComboBox.Create(Self);
FC.Parent := Self;
FC.SetBounds(20, 20, 220, 28);
FC.SelectedFont := 'Segoe UI';
// 使用:SomeLabel.Font.Name := FC.SelectedFont;
```

---

## 6. 注意事项

- **所见即所得:** 每项用自己的字体画——直观但依赖系统字体渲染(BGRA 找不到时回退)。
- **填充来源:** `Screen.Fonts`;真机上是系统已安装字体,headless 下可能为空(不崩)。
- **字体列表不存进 `.lfm`:** `Items` 是本机装的字体,不写进窗体文件。读窗体时按本机字体重新填充,按名字(`Text`)选回原来的字体族;本机没有这个字体时不选中任何项。3.0.0 存过的窗体里带着保存那台机器的字体列表,照样能读,读完换成本机的。
- **只读式选择:** 继承 `csDropDownList` 语义即可(如需自由输入字体名可设 `Style`,但通常不必)。

### 只列等宽字体

`FixedPitchOnly = True` 时,哪些字体算等宽由系统说了算,经 LCL 的 `EnumFontFamiliesEx` 读出来:Windows 是字体的间距标志,GTK2/GTK3 是 `pango_font_family_is_monospace`,Qt 是 `QFontDatabase::isFixedPitch`,Cocoa 是字体的 `NSFontMonoSpaceTrait`。不量字形宽度。系统对某个字体的标志不准时,以系统为准,和本机其它程序里看到的一样。

只在这个选项开着时才多做一次枚举(构造、`Loaded`、`RefreshFonts`、改这个属性时),开销和列出全部字体名差不多。顺序和写法跟 `Screen.Fonts` 一致,只是少了非等宽的行。

同一个判断也用在 [`TTyFontListBox`](fontlistbox.md) 和字体对话框的 `fdFixedPitchOnly` 上;代码里要这份列表,调 `tyControls.FontFamilies` 单元的 `TyGetFontFamilies(List, True)`。
