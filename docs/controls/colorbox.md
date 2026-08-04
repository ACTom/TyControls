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
| `Selected` | `TColor` | **published**(对齐 `TColorBox`,可在对象查看器里设、可流式保存)。当前选中色;读=当前项的色(无则 `clNone`),写=选中板里的匹配项,**板里没有则 `ItemIndex := -1`,不再往列表里追加行**(除非 `Style` 里有 `cbCustomColor`,见下)。 |
| `Style` | `TTyColorBoxStyle` | **published**,默认 `TyDefaultColorBoxStyle`。**色板由哪些颜色组成**——见下表。写它会重建 `Items`。 |
| `ColorRectWidth` / `ColorRectOffset` | `Integer` | **published**,逻辑 px,默认 0 = 跟随主题(`--color-swatch-width` / `--color-swatch-offset`;主题不说话时就是历来的「按行高取正方形」+ 4px 内缩)。宽度设成正数即得**色条**而非方块。 |
| `DefaultColorColor` / `NoneColorColor` | `TColor` | **published**,默认 `clBlack`。`clDefault` / `clNone` 这两行**实际画出来的**颜色——它们本身是哨兵值,不是颜色。 |
| `OnGetColors` | `TTyGetColorsEvent` | **published**。`Style` 含 `cbCustomColors` 时,每次重建色板的最后一步触发,处理器往传入的 `AItems` 里追加自己的颜色(用 `TyAddColorItem`)。 |
| `Colors[AIndex]` | `TColor` | **读 / 写**第 i 项的色(对齐 `TColorListBox.Colors`;越界写忽略)。 |
| `ColorNames[AIndex]` | `string` | 第 i 项的显示名(越界返回 `''`)。 |
| `AddColor(AName, AColor)` | — | 追加一个(名, 色)项。 |
| `ClearColors` | — | 清空所有项与颜色。 |
| `ColorAt(AIndex)` | `TColor` | 第 i 项的色(越界 `clNone`)。 |

另继承 `TTyComboBox` 的 `ItemIndex` / `OnChange` / `OnSelect` 等。

### 3.1 Style —— 色板由什么组成

对齐 LCL `TColorBox.Style`(`colorbox.pas:35-43`),成员一一对应:

| 成员 | 作用 |
|------|------|
| `cbStandardColors` | 16 个标准 VGA 色(clBlack…clWhite) |
| `cbExtendedColors` | 4 个扩展色(clMoneyGreen / clSkyBlue / clCream / clMedGray) |
| `cbSystemColors` | 系统色(clBtnFace / clWindow / clHighlight…) |
| `cbIncludeNone` | 加一行 `clNone` |
| `cbIncludeDefault` | 加一行 `clDefault` |
| `cbCustomColor` | 第 0 行是**可写槽位**:`Selected := 板外的颜色` 会落进这一行,而不是清空选择 |
| `cbPrettyNames` | 显示 `Button Face` 而不是 `clBtnFace`(用的是 LCL 自己的资源串,所以自带各语言翻译) |
| `cbCustomColors` | 重建的最后一步触发 `OnGetColors` |

> **默认值刻意与 LCL 不同。** LCL 的默认是 `[cbStandardColors, cbExtendedColors, cbSystemColors]`;
> 本库的 `TyDefaultColorBoxStyle = [cbStandardColors, cbPrettyNames]`,**正好重建出本控件历来内置的
> 那 16 个漂亮名字的 VGA 色**——数量、顺序、名字都不变。published 属性的 `default` 决定了「.lfm 里没写这一行」
> 该怎么解释,改它等于悄悄重排每一个已经在用的颜色框。要 LCL 的组合,写一句 `Style := [...]` 即可。

> **这个名字以前是别的意思。** `Style` 原本是从 `TTyComboBox` 继承来的下拉模式,而 `TTyColorBox.SetStyle`
> 会把写进来的值**原样丢掉**(强制 `csDropDownList`)——对象查看器给你这个属性、控件不理它。
> 现在它是色板组合;下拉模式仍然锁死,仍可经 `TTyComboBox(Box).Style` 读到。
> **BREAKING**:`ColorBox1.Style := csDropDown` 不再编译(它本来也没有任何效果)。

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
CB.Selected := clRed;        // 选中红;不在板里的色 -> ItemIndex = -1(不追加)
// 读取:MyColor := CB.Selected;
```

---

## 6. 注意事项

- **地基控件:** 它证明并建立了逐项自绘钩子;`ColorListBox` / `FontComboBox` 等会复用同一套。
- **写 `Selected` 不再撑大色板:** 选色器的语义是"从板里挑",不是"往板里加"——`TColorBox.Selected` 同样是写不匹配的色就置 `ItemIndex := -1`。会追加的 setter 还不幂等:写二十次就多二十行。要把色**加进**板里请显式调 `AddColor`。共用函数 `TySelectColorIndex` 保留了 `AAppendIfMissing` 参数(默认 `True`),供确实需要"当前值必须可显示"的**编辑器**类调用方使用;两个选色控件都传 `False`。
- **颜色存在 `Items.Objects[i]`:** 与名称**天然对齐**——`Sorted:=True` 重排名称、`Items.Delete` 删除、直接改 `Items` 都不会让色块错位(没有并行数组)。
- **锁定只选不编辑:** `Style` 被强制为 `csDropDownList`(覆写 `SetStyle` 忽略 `csDropDown`)——可编辑模式的下拉是**前缀过滤**的,会打乱行索引→色块映射,所以禁掉。
- **色块轮廓:** 用主题的文字色描 1px 边,浅色色块(白等)也可见——不硬编码。
