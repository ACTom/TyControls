# TTyColorListBox

## 1. 概述

TTyColorListBox 是**命名颜色列表框**——[TTyColorBox](colorbox.md) 的列表版。每一行显示一个颜色色块 + 名称。继承自 [TTyListBox](listbox.md),覆写 `PaintItemContent` 钩子画色块;颜色存在 `Items.Objects[i]`,与名称天然对齐(排序 / 删除都跟着走)。与 ColorBox 共用同一套自由函数(`TyAddDefaultColorPalette` / `TyAddColorItem` / `TySelectColorIndex` / `TyDrawColorRow`),选色/追加逻辑只有一份。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ColorListBox` |
| typeKey | `'TyListBox'` / `'TyListItem'`(继承)|

无新增 `.tycss`。

```pascal
uses tyControls.ColorListBox;
```

---

## 3. 属性 / 方法

| 成员 | 说明 |
|------|------|
| `Selected: TColor` | **published**(对齐 `TColorListBox`,可在对象查看器里设、可流式保存)。当前选中色:读=当前行色,写 `clNone` 清空选择;写其他色=选板里的匹配行,**没有则 `ItemIndex := -1`,不再追加行**(与 [TTyColorBox](colorbox.md) 同一套逻辑,要加色请显式调 `AddColor`)。 |
| `Style: TTyColorBoxStyle` | **published**,默认 `TyDefaultColorBoxStyle`。**色板由哪些颜色组成**;成员表与语义见 [TTyColorBox](colorbox.md#31-style--色板由什么组成),两个控件带的是同一套。写它会重建 `Items`。 |
| `ColorRectWidth` / `ColorRectOffset` | **published**,逻辑 px,0 = 跟随主题(`--color-swatch-width` / `--color-swatch-offset`)。 |
| `DefaultColorColor` / `NoneColorColor` | **published**,默认 `clBlack`。`clDefault` / `clNone` 两行实际画出来的颜色。 |
| `OnGetColors: TTyGetColorsEvent` | **published**。`Style` 含 `cbCustomColors` 时,重建色板的最后一步触发。 |
| `Colors[AIndex]: TColor` | **读 / 写**第 i 行的色(对齐 `TColorListBox.Colors`,它在 LCL 里也是有 setter 的那一个;越界写忽略)。 |
| `ColorNames[AIndex]: string` | 第 i 行的显示名(越界返回 `''`)。 |
| `AddColor(AName, AColor)` | 追加一项。 |
| `ClearColors` | 清空。 |
| `ColorAt(AIndex): TColor` | 第 i 行的色(越界 `clNone`)。 |

默认色板 = 16 色 VGA(由 `Style` 的默认值组合出来,不再写死在构造函数里);另继承 `TTyListBox` 的 `ItemIndex` / `OnChange` / 多选等。

> 若 `Style` 里含 `cbIncludeNone`,`Selected := clNone` 会**选中那一行**而不是清空选择——毕竟你专门要了这一行。
> 没有这一行时,`clNone` 仍是「清空」。

---

## 4. 代码示例

```pascal
uses tyControls.Controller, tyControls.ColorListBox, Graphics;

var CL: TTyColorListBox;
CL := TTyColorListBox.Create(Self);
CL.Parent := Self;
CL.SetBounds(20, 20, 160, 220);
CL.Selected := clNavy;
```

---

## 5. 注意事项

- **组合 vs 列表:** 收起式选色用 [TTyColorBox](colorbox.md);要常驻列表用本控件。
- **颜色随名同步:** 颜色在 `Items.Objects[i]`,`Sorted` / `Delete` 不会错位(见 [colorbox.md](colorbox.md) 的同一机制)。
