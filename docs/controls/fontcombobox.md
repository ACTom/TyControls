# TTyFontComboBox

## 1. 概述

TTyFontComboBox 是**字体族组合框**:字段和下拉列表的每一项都**用它自己的字体绘制**(所见即所得的字体选择器)。继承自 [TTyComboBox](combobox.md),覆写 `CreatePopupList`(注入一个按行字体绘制的下拉列表)和 `PaintFieldContent`(字段用选中字体绘制)。列表从 `Screen.Fonts`(已安装字体族)填充。

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
| `RefreshFonts` | 重新从 `Screen.Fonts` 填充(装了新字体后调用)。 |

另继承 `TTyComboBox` 的 `Items` / `ItemIndex` / `OnChange` / `OnSelect` 等。

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
- **只读式选择:** 继承 `csDropDownList` 语义即可(如需自由输入字体名可设 `Style`,但通常不必)。
