# TTyColorBox

## 1. 概述

TTyColorBox 是**命名颜色组合框**:字段(收起态)和下拉列表的每一项都显示一个**颜色色块 + 名称**。继承自 [TTyComboBox](combobox.md),靠给列表/组合框新增的**逐项自绘钩子**实现——`CreatePopupList` 注入一个会画色块的下拉列表、`PaintFieldContent` 画字段里的色块。通过 `AddColor` / `ClearColors` 管理色板,`Selected` 是当前选中的 `TColor`。这是整个颜色/字体选择器子族的**地基控件**。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ColorBox` |
| typeKey | `'TyComboBox'`(字段)/ `'TyListItem'`(下拉项),均继承 |

无新增 `.tycss`。

```pascal
uses tyControls.ColorBox;
```

---

## 3. 属性 / 方法

| 成员 | 类型 | 说明 |
|------|------|------|
| `Selected` | `TColor` | 当前选中色;读=当前项的色(无则 `clNone`),写=选中匹配项,板里没有则追加一个 `#RRGGBB` 项并选中。 |
| `AddColor(AName, AColor)` | — | 追加一个(名, 色)项。 |
| `ClearColors` | — | 清空所有项与颜色。 |
| `ColorAt(AIndex)` | `TColor` | 第 i 项的色(越界 `clNone`)。 |

内置 16 色经典 VGA 调色板(Black…White);另继承 `TTyComboBox` 的 `ItemIndex` / `OnChange` / `OnSelect` 等。

---

## 4. 机制(地基)

复用三个新加的**逐项自绘钩子**(默认全部字节一致,普通 ListBox/ComboBox 不受影响):

- `TTyListBox.PaintItemContent(P, rowRect, i, style)` —— 每行内容绘制(默认=文字);内部 `TTyColorPopupList` 覆写它画色块+名。
- `TTyComboBox.CreatePopupList: TTyListBox` —— 下拉列表工厂(默认 `TTyListBox`);ColorBox 返回 `TTyColorPopupList`。
- `TTyComboBox.PaintFieldContent(P, textRect, style)` —— 字段选中项绘制(默认=文字);ColorBox 覆写它画色块+名。

后续 `TTyColorListBox` / `TTyFontComboBox` / `TTyCheckListBox` 等都建立在这三个钩子上。纯函数 `TyTColorToTy`(TColor→TTyColor)已单测。

---

## 5. 代码示例

```pascal
uses tyControls.Controller, tyControls.ColorBox;

TyDefaultController.LoadTheme('themes/light.tycss');

var CB: TTyColorBox;
CB := TTyColorBox.Create(Self);
CB.Parent := Self;
CB.SetBounds(20, 20, 180, 28);
CB.Selected := clRed;        // 选中红;不在板里的色会自动追加
// 读取:MyColor := CB.Selected;
```

---

## 6. 注意事项

- **地基控件:** 它证明并建立了逐项自绘钩子;`ColorListBox` / `FontComboBox` 等会复用同一套。
- **颜色存在 `Items.Objects[i]`:** 与名称**天然对齐**——`Sorted:=True` 重排名称、`Items.Delete` 删除、直接改 `Items` 都不会让色块错位(没有并行数组)。
- **锁定只选不编辑:** `Style` 被强制为 `csDropDownList`(覆写 `SetStyle` 忽略 `csDropDown`)——可编辑模式的下拉是**前缀过滤**的,会打乱行索引→色块映射,所以禁掉。
- **色块轮廓:** 用主题的文字色描 1px 边,浅色色块(白等)也可见——不硬编码。
