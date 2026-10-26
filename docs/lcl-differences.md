# 与 LCL 的有意差异

> English: [lcl-differences.en.md](lcl-differences.en.md)

TyControls 的属性名和语义尽量与 LCL 一致，从 Lazarus 移植的代码大多不用改。下面这些地方是**故意**不同的，移植时请留意。

## 默认值

| 属性 | TyControls | LCL | 说明 |
|------|-----------|-----|------|
| `AutoSize`(标签、编辑框、组合框、复选框、单选按钮) | `False` | `True` | 高度跟主题走;需要按内容定尺寸时显式打开 |
| `TTyMemo.WordWrap` | `False` | `True` | 长行横向滚动 |
| `TTyMemo.ScrollBars` | `ssAutoVertical` | `ssNone` | 内容超出时才出现竖向滚动条 |
| `TTyNumericEdit.Alignment`(及其子类) | `taRightJustify` | `taLeftJustify` | 数字右对齐 |
| `TTyRadioButton.TabStop` | `True` | `False` | 每个单选按钮都能用 Tab 到达 |
| `TTySpeedButton.Spacing` | `-1` | `4` | `-1` 表示图标与文字的间距由主题的 `--glyph-button-gap` 决定 |
| `TTyCoolBar.ShowText`、`TTyCoolBand.Break` | `False` | `True` | |
| `TTyStatusBar.SimplePanel` | `False` | `True` | 没有面板的状态栏照样显示 `SimpleText` |
| `TTyTreeView.RightClickSelect` | `True` | `False` | 右键先选中节点，再弹出菜单 |
| `TTyListView.ReadOnly` | `True` | `False` | 需要原地改名时设为 `False` |
| `TTyScrollBar.Kind` | `sbVertical` | `sbHorizontal` | 见 [TTyScrollBar](controls/scrollbar.md) |
| `TTyScrollBar.LargeChange` | `0` | `1` | `0` 表示按 `PageSize` 翻页，见 [TTyScrollBar](controls/scrollbar.md) |

## 行为

- **像素属性都是逻辑像素**(96 PPI 下的像素)。宽度、高度、内边距、`BorderWidth` 等由控件按自己的 PPI 缩放，高 DPI 下不用手工换算。
- **`TTyScrollBar.Position` 可以到达 `Max`。** LCL 的滚动条最大只到 `Max - PageSize + 1`。
- **`TabStop = False` 的控件点击时不获得焦点**,键盘焦点留在原来的控件上。
- **`TTyTrackBar` 按 PageUp 增大 `Position`**,与 Qt 一致，与 Win32 相反。
- **`TTyTreeView.AutoExpand` 沿用 Delphi 的语义**:焦点移到哪个节点就展开哪个，离开的节点收起。LCL 的含义是"给节点添加子节点时展开它"。
- **`TTyTitleBar` 禁用后外观不变。** 它代表窗口本身，窗口不会变灰;要表示"窗口不可用"请禁用窗口里的内容。
- **窗体自己的 `Font` 不覆盖主题。** 整个窗口的字体来自主题;要换字体，改主题或用 `StyleOverride`。控件自己设置的字体照常生效。
- **`TTyScrollPanel.AutoPan` 需要宿主驱动。** 拖动经过时在 `OnDragOver` 里调用 `AutoPanTo`,拖动结束时调用 `StopAutoPan`。

## `AutoSize` 不起作用的控件

下列控件没有"按内容"的自然尺寸,`AutoSize` 不改变它们的大小:`TTyMemo`、`TTyListView`、`TTyTreeView`、`TTyDrawGrid`、`TTyStringGrid`、`TTyValueListEditor`、仪表类控件、`TTyChart`、`TTySparkline`、`TTyProgressBar`、`TTyShape`、`TTyStarShape`、`TTyArrow`、`TTyBevel`、`TTySplitter`、取色控件、`TTyPreviewBox`、`TTyImageView`、`TTyTransfer`、`TTyRibbonBackstage`、`TTyRibbonGallery`、`TTyTitleBar`。

## 不再发布的属性

下面这些属性对所在的控件不可能起作用，4.0 起不再发布(3.0 里只是在对象查看器里隐藏)。3.x 的窗体如果给它们设过值，4.0 载入时会报 `Unknown property`:在 IDE 里打开窗体时选择跳过，或者从 `.lfm` 里删掉那几行。

| 控件 | 属性 | 原因 |
|------|------|------|
| 数值框:`TTyNumericEdit`、`TTyCurrencyEdit`、`TTyCalcEdit`、`TTyCalcCurrencyEdit`、`TTyFloatSpinEdit`、`TTyTrackEdit` 及它们的 DB 版本 | `CharCase` | 只能输入数字、符号和小数点 |
| `TTyAdvancedComboBox`、`TTyCheckComboBox`、`TTyColorBox`、`TTyColorComboBox`、`TTyFilterComboBox`、`TTyOfficeComboBox`、`TTyShellComboBox` | `MaxLength`、`CharCase`、`ReadOnly` | 只能选、不能输入，没有可编辑的文字 |
| `TTyDrawGrid` | `HideSelectionWhenInactive`、`FadeUnfocusedSelection`、`MinEditorWidth` | 没有选区，也没有内置的单元格编辑器;`TTyStringGrid` 照常发布 |
| 网格的 `Header` | `MainColumn` | 网格没有主列;`TTyListView`、`TTyTreeView` 的表头照常发布 |

上面这些只能选的组合框(`TTyColorBox`、`TTyColorComboBox` 除外)的 `Style` 仍然发布，但对象查看器的下拉列表里只列出只能选的样式;可编辑的样式设上去也会被换成对应的只能选样式。
