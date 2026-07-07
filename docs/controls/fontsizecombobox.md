# TTyFontSizeComboBox

## 1. 概述

TTyFontSizeComboBox 是**可编辑的字号组合框**:内置常用字号(6…72),可从下拉里选,也可以**直接键入**一个自定义字号。继承自 [TTyComboBox](combobox.md)(`csDropDown` 可编辑模式),`FontSize` 是数值。字号只是普通文本,**无需逐项自绘**——是 Phase-4 里最轻的一个。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.FontSizeComboBox` |
| typeKey | `'TyComboBox'`(继承)|

无新增 `.tycss`。

```pascal
uses tyControls.FontSizeComboBox;
```

---

## 3. 属性

| 成员 | 类型 | 说明 |
|------|------|------|
| `FontSize` | `Integer` | 数值字号(从文本解析,非数字则 0);写入选中同值预设,否则填入自定义文本。 |

另继承 `TTyComboBox` 的 `Items` / `Text` / `ItemIndex` / `OnChange` 等。默认预设:6,7,8,9,10,11,12,14,16,18,20,24,28,32,36,48,60,72。

---

## 4. 代码示例

```pascal
uses tyControls.Controller, tyControls.FontSizeComboBox;

var FS: TTyFontSizeComboBox;
FS := TTyFontSizeComboBox.Create(Self);
FS.Parent := Self;
FS.SetBounds(20, 20, 64, 28);
FS.FontSize := 14;              // 选中 14 磅
// 用户也可以在框里直接敲 15、13 之类的自定义值
// 使用:SomeLabel.Font.Size := FS.FontSize;
```

---

## 5. 注意事项

- **可编辑:** `Style` 保持 `csDropDown`,所以能输入预设之外的字号;`FontSize` 会如实解析。
- **与字体框搭配:** 常和 [TTyFontComboBox](fontcombobox.md) 并排用(选族 + 选号)。
