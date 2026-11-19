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
- **`TabStop = False` 的控件点击时不获得焦点**,键盘焦点留在原来的控件上。文本框、多行文本框和数值、日期时间这类输入字段除外：点进去就是为了输入。
- **`TTyTrackBar` 按 PageUp 增大 `Position`**,与 Qt 一致，与 Win32 相反。`Reversed` 的条上按键和滚轮跟着屏幕走：滑块在屏幕上往哪边走和没翻转时一样，所以 PageUp 减小 `Position`。
- **`TTyTreeView.AutoExpand` 沿用 Delphi 的语义**:焦点移到哪个节点就展开哪个，离开的节点收起。LCL 的含义是"给节点添加子节点时展开它"。
- **`TTyTitleBar` 禁用后外观不变。** 它代表窗口本身，窗口不会变灰;要表示"窗口不可用"请禁用窗口里的内容。
- **窗体自己的 `Font` 不覆盖主题。** 整个窗口的字体来自主题;要换字体，改主题或用 `StyleOverride`。控件自己设置的字体照常生效。
- **`TTyScrollPanel.AutoPan` 需要宿主驱动。** 拖动经过时在 `OnDragOver` 里调用 `AutoPanTo`,拖动结束时调用 `StopAutoPan`。
- **`TTyColorDialog.Color` 是 `TTyColor`(`$AARRGGBB`,带透明度),不是 `TColor`。** 直接把 `clRed` 赋给它，得到的是一个透明的蓝色;要按 `TColor` 读写，用 `LCLColor`。
- **在 `TTyDateTimePicker` 里按 `Delete` 会把整个日期清成 NULL**,和 `N` 键一样(LCL 只认 `N`)。不想让用户清空，设 `NullInputAllowed := False`。

## 与普通 LCL 控件混用

主题化的容器上可以直接放普通的 LCL 控件(`TPanel`、`TFrame`、`TScrollBox` ……)。运行时，能放子控件的 TyControls 容器(面板、分组框、卡片、工具窗口、页面等)会让自己的 LCL `Color` 等于**子控件身后的那个颜色**:

| 容器的主题背景 | 它的 `Color` |
|------|------|
| 纯色 | 这个颜色 |
| 半透明 | 叠在容器身后的颜色上之后的结果 |
| 没有(比如分组框) | 容器身后的颜色 |
| 渐变 | 渐变中点的颜色 |

`ParentColor = True` 的普通控件于是自己就画成这个颜色，再放到它上面的 TyControls 控件，圆角外侧取到的也是它，不再是 `clBtnFace`。换主题、换 `Controller`、改 `StyleClass` / `StyleOverride`、把容器挪到别的父控件上，颜色都跟着变。

- **只在运行时。** 设计器里容器的 `Color` 不动，这个颜色也不会写进 `.lfm`。
- **取静止状态的样式。** 鼠标悬停、获得焦点不会改它。
- **你设过的 `Color` 归你。** 给容器的 `Color` 赋过值之后库不再碰它;赋回 `clDefault`(`TTyFrame` 也可以设 `ParentColor := True`)就重新跟主题。
- **渐变只能给一个平色。** 普通 LCL 控件只会画一种颜色。要在渐变宿主上看不出接缝，把视图做成 [TTyFrame](controls/frame.md),它画的是宿主背景在自己位置上的那一片。
- 自己写的容器不想要这个行为，重写 `ThemesChildBackdrop` 返回 `False`。

窗体(`TTyForm`)一直是这样做的:`ApplyChromeTheme` 把纯色的窗体背景写进窗体的 `Color`。

## `AutoSize` 不起作用的控件

下列控件没有"按内容"的自然尺寸,`AutoSize` 不改变它们的大小:`TTyMemo`、`TTyListView`、`TTyTreeView`、`TTyDrawGrid`、`TTyStringGrid`、`TTyValueListEditor`、仪表类控件、`TTyChart`、`TTySparkline`、`TTyProgressBar`、`TTyShape`、`TTyStarShape`、`TTyArrow`、`TTyBevel`、`TTySplitter`、取色控件、`TTyPreviewBox`、`TTyImageView`、`TTyTransfer`、`TTyRibbonBackstage`、`TTyRibbonGallery`、`TTyTitleBar`、`TTyTerminalView`（要固定行列用 `SizeForGrid`）。

## 不再发布的属性

下面这些属性对所在的控件不可能起作用，4.0 起不再发布(3.0 里只是在对象查看器里隐藏)。3.x 的窗体里给它们设过的值，4.0 载入时直接丢掉，窗体照常打开；再保存一次，`.lfm` 里就没有这几行了。

| 控件 | 属性 | 原因 |
|------|------|------|
| 数值框:`TTyNumericEdit`、`TTyCurrencyEdit`、`TTyCalcEdit`、`TTyCalcCurrencyEdit`、`TTyFloatSpinEdit`、`TTyTrackEdit` 及它们的 DB 版本 | `CharCase` | 只能输入数字、符号和小数点 |
| `TTyAdvancedComboBox`、`TTyCheckComboBox`、`TTyColorBox`、`TTyColorComboBox`、`TTyFilterComboBox`、`TTyOfficeComboBox`、`TTyShellComboBox` | `MaxLength`、`CharCase`、`ReadOnly` | 只能选、不能输入，没有可编辑的文字 |
| `TTyDrawGrid` | `HideSelectionWhenInactive`、`FadeUnfocusedSelection`、`MinEditorWidth` | 没有选区，也没有内置的单元格编辑器;`TTyStringGrid` 照常发布 |
| 网格的 `Header` | `MainColumn` | 网格没有主列;`TTyListView`、`TTyTreeView` 的表头照常发布 |
| `TTyShellListView` | `OwnerData`、`ItemCount`、`Items`、`OnGetItemText`、`OnGetItemImage`、`OnGetItemGroup` | 列表内容由它自己从文件夹读;`TTyListView` 照常发布 |
| `TTyShellTreeView` | `NodeDataSize`、`RootNodeCount`、`Items`、`OnInitChildren` | 节点由它自己从文件系统建;`TTyTreeView` 照常发布 |
| `TTyDBLookupListBox` | `MultiSelect`、`ExtendedSelect` | 查找列表只存一个键(LCL 也不发布);`TTyDBListBox` 照常发布 |
| 文本输入控件:`TTyEdit`、`TTyMaskEdit`、`TTyComboEdit`、`TTyURLEdit`、数值框、`TTyMemo`、`TTySpinEdit`、`TTyDateTimePicker` 及它们的 DB 版本 | `ChildSizing` | 没有要排的子控件 |
| `TTyRangeTrackBar`、`TTyMultiTrackBar`、`TTyGradientTrackBar` | `ChildSizing` | 没有要排的子控件 |
| `TTyTerminalView` | `ChildSizing` | 滚动条由终端自己摆;设了它，滚动条会盖到最后几列上 |
| `TTyToolWindowActions` | `AutoSize`、`ChildSizing`、`BorderSpacing` | 位置和尺寸由所在的工具窗口排，子控件由它自己排成一排 |

上面这些只能选的组合框(`TTyColorBox`、`TTyColorComboBox` 除外)的 `Style` 仍然发布，但对象查看器的下拉列表里只列出只能选的样式;可编辑的样式设上去也会被换成对应的只能选样式。

## `TTyRichEdit` 与 Delphi 的 `TRichEdit`、RichMemo

`TTyRichEdit` 由本库自己绘制，不是 Windows 的富文本控件。Delphi `TRichEdit` 的大部分成员和 RichMemo 的方法都在，名字不变，但有一些能编译、做的事却不一样。下面逐条列出。

### `uses` 里要写什么

Delphi 的 `uses ComCtrls`(或 RichMemo 的 `RichMemo`)换成 `tyControls.RichEdit`,再加上声明它的成员所用类型和取值的那些单元。`tyControls.RichEdit` 不转出它们，就像 `tyControls.Memo` 不转出 `tyControls.ScrollBar` 一样：没写上这些单元之前，移植过来的代码第一次编译就会停在 `TTyRichPos`、`nsBullet` 或 `stMatchCase` 上。IDE 生成的事件处理方法不受影响：它会自己加上参数所需的单元。

```pascal
uses
  tyControls.RichEdit, tyControls.RichEdit.Text, tyControls.RichEdit.Attrs,
  tyControls.RichEdit.Model, tyControls.RichEdit.Layout, tyControls.RichEdit.Find,
  tyControls.ScrollBar;  // 要用 Document.Execute 时再加 tyControls.RichEdit.Commands
```

| 单元 | 提供的名字 |
|------|-----------|
| `tyControls.RichEdit` | `TTyRichEdit`、`ETyRichEdit`、`TTyRichFormat`(`rfAuto`、`rfRtf`、`rfText`)、各个事件类型(`OnFallbackFont` 的 `TTyRichFallbackEvent` 在 `tyControls.RichEdit.Layout` 里)、`TTyRichFindEnd`(`rfeFound` ……)、`TTyRichReplaceEnd`(`rreDone` ……)、`TTyRichReplaceResult`、`TTyRichFindTask`(`rftFind`、`rftReplace`) |
| `tyControls.RichEdit.Text` | `TTyRichPos` |
| `tyControls.RichEdit.Attrs` | `TTyRichTextAttributes`、`TTyRichParaAttributes`、`TNumberingStyle` 及 `nsNone`、`nsBullet`,`TTySearchTypes`(`stWholeWord`、`stMatchCase`)、`TTySearchOptions`(`soMatchCase`、`soWholeWord`、`soBackward`)、`TTyRichConsistentAttributes`(`caBold` ……)、`TTyRichConsistentParaAttributes`(`cpaAlignment` ……)、`TTySubscriptType`(`sstNone` ……);RichMemo 的记录、集合和辅助过程:`TTyFontParams`、`InitFontParams`、`TTyParaMetric`、`TTyParaNumbering`(`pnBullet` ……)、`TTyParaAlignment`(`paLeft` ……)、`TTyTabStopList`、`TTyTextModifyMask`(`tmm_Styles` ……)、`TTyParaModifyMask`、`TTyParaRange` |
| `tyControls.RichEdit.Model` | 各种编号列表(`lkDecimal` …… `lkUpperRoman`)、`ParaAlign` 用的 `TTyParaAlign`(`paraLeft`、`paraCenter`、`paraRight`、`paraJustify`)、`LineSpacingRule` 用的 `TTyLineSpacing`(`lsSingle` ……)、`TTyTextEncoding`(`teAuto`、`teUtf8` ……)、`TTyRichDocument` |
| `tyControls.RichEdit.Layout` | `TTyRichWrapMode`(`rwmWindow`、`rwmPage`、`rwmNone`) |
| `tyControls.RichEdit.Find` | `TTyRichFindOptions`(`rfoMatchCase`、`rfoWholeWord`、`rfoBackward`、`rfoWrap`) |
| `tyControls.RichEdit.Commands` | 给 `Document.Execute` 用的命令(`TTyRichInsertText` ……) |
| `tyControls.ScrollBar` | `TTyScrollBarAutoHide`(`sbahDefault`、`sbahNever`、`sbahAuto`) |

### 位置、行和文字

- **位置按字符(码点)计，不按 UTF-16 单元。** BMP 以外的字符(表情、生僻字)在这里占一个位置，在 Delphi 和 Windows 上的 RichMemo 里占两个;段落结束占一个位置。
- **位置和长度是 `TTyRichPos`(`Int64`)。** `SelStart`、`SelLength`、`FindText` 的结果和 RichMemo 风格的方法都用它。赋给 `Integer` 变量能编译，没有任何警告，超过 `High(Integer)` 的位置会被截断;类型是 64 位的，就是为了这么大的文档，所以要声明为 `TTyRichPos`。
- **`Lines` 的一行是一个段落**,不是 Delphi 那样屏幕上折行后的一行:`Lines.Count` 是段落数,`Lines[i]` 是一个段落的文字。大文档从不整篇排版,`Lines` 必须不排版就能回答。
- **`CaretPos` 和 Delphi 一样是选区末端的 `TPoint`**:`Y` 是段落,`X` 是段内第几个字符。RichMemo 的 `CaretPos`(即 LCL 多行文本框的)读的是选区起点。
- **给 `CaretPos` 赋值时 `X` 限制在段落之内。** Delphi 直接把 `X` 加到行首，超出行尾的列会落到后面的行里。
- **读 `SelText` 得到的是复制到剪贴板的纯文本**:段落结束是平台的换行符(Delphi 是 CR),图片不出现(Delphi 是 U+FFFC)。所以 `Length(SelText)` 不像 Delphi 那样等于 `SelLength`。
- **`Text` 里图片是 U+FFFC**,段落之间用平台的换行符连接;在大文档里读它会把全文复制一份。
- **`Text :=` 和 `Clear` 换掉整个内容**:撤销历史清空，之后 `Modified` 为 `False`,`Clear` 不能撤销，和 Delphi 的 `WM_SETTEXT` 一样。在 `BeginEdit … EndEdit` 之间调用两者都会抛 `ETyRichEdit`。

### 能编译，含义不同

- **每次经控件载入都会设置 `PlainText`**:文本文件设为 `True`,RTF 文件设为 `False`。Delphi 的 `PlainText` 从不自己改变。
- **代码或对象查看器把 `PlainText` 设为 `True` 后，它一直说了算**:此后不指定格式的载入都按文本读，不指定格式的文件保存都写文本，和 Delphi 一样。用 `rfText` 载入不会结束它;`PlainText := False`、`LoadRichText`、`LoadFromStream(S, rfRtf)` 或按文件内容决定格式的载入会结束它。
- **不指定格式的载入看文件开头**(可选的 BOM 和空白之后是 `{\rtf` 就是 RTF,否则是文本)。Delphi 先试 RTF,失败再按文本读，并且不动 `PlainText`。
- **单参数的 `Lines.LoadFromFile`、`LoadFromStream`、`SaveToFile`、`SaveToStream` 就是控件自己的载入和保存**,所以 RTF 文件会按 RTF 读。带 `TEncoding` 的重载是 TStrings 的，把文件当纯文本;要指定编码，设 `TextEncoding` 再用单参数的版本。
- **`Lines.SaveToFile` 会清除 `Modified`**,Delphi 的不动它。否则保存之后关闭窗口时"是否保存修改"还会再问一次。
- **撤销或重做回到上次载入或保存时的内容,`Modified` 会重新变成 `False`**;Delphi 的一直是 `True`。
- **撤销恢复这一步之前的选区，重做后是一个不带选区的光标，停在这一步结束的位置**,和 Windows 的富文本控件一样。连续输入合成一步;一次格式写入、代码的每一次编辑各算一步。
- **写入文字已有的值不算一步撤销**:不触发 `OnChange`,不动 `Modified`。
- **`CanUndo` 和 `CanRedo` 是替用户回答的**:`ReadOnly` 或禁用时为 `False`。代码要问，用 `Document.CanUndo`。
- **`ReadOnly` 只拦用户。** 代码照样能通过 `SelText`、`Lines`、`Text`、格式接口和替换方法修改内容，和 Delphi 的 `SelAttributes` 一样;剪切、粘贴、`ClearSelection`、`Undo`、`Redo` 在只读控件上什么也不做，也和 Delphi 一样。
- **`ClearSelection` 删除选区**,和 Delphi 一样;只想取消选区用 `CollapseSelection`。
- **没选中文字时选好的格式(先点粗体再输入)遇到任何一次设置选区就作废**,哪怕是 `SelStart := SelStart`,和 Windows 一样。
- **在 `Lines.BeginUpdate … EndUpdate`、`Document.BeginUpdate … EndUpdate` 和 `BeginEdit … EndEdit` 之间，每次写入的效果和在外面一样**:光标和选区跟着 `SelText`、`Lines`、`InDelText` 走。`BeginEdit … EndEdit` 把重画和两种通知都压到结尾：最后触发一次 `OnChange` 和一次 `OnSelectionChange`。`Lines.BeginUpdate` 和 `Document.BeginUpdate` 只压住 `OnChange` 和重画;在里面设置选区(`SelStart`、`SelLength`、`CaretPos`、`CaretIndex`)会立即通知，和 Delphi 一样。
- **在这些括号之间用户的操作不起作用**:剪切、粘贴、`ClearSelection`、`Undo`、`Redo` 和按键都被忽略，不报错，也不触发 `OnEditRefused`。
- **在括号之间直接用 `Document.Execute` 做的修改**:同一个括号里还设置过选区或经控件写过文字时，它不移动选区。两样都没有时，选区只在结尾按整个括号合并成的一次修改移动：夹在两处这样的修改之间的光标会落到第一处的开头。
- **`BeginEdit … EndEdit` 算一步撤销**:撤销恢复 `BeginEdit` 时的选区，重做后是一个光标，停在 `EndEdit` 时光标所在的位置。
- **文件还在载入、载入被取消之后、或正在保存时，写格式会抛 `ETyRichEdit`**,Delphi 的控件没有这些状态。含有嵌套表格的表格行会被跳过，保持文件里的样子。
- **写格式之前先结束正在进行的输入法组字。**
- **`SendMessage(Handle, EM_…)` 和 `Perform(EM_…)` 能编译，但什么也不做**:没有系统控件来接收它们。改用对应的成员:`EM_SCROLLCARET` 用 `ScrollCaretIntoView`,`EM_LINEFROMCHAR` 用 `Document.Text.ParaOfPos`,`EM_LINEINDEX` 用 `Document.Text.ParaStart`,`EM_GETFIRSTVISIBLELINE` 用 `TopParagraph`,`EM_POSFROMCHAR` 用 `PositionRect`,`EM_CHARFROMPOS` 用 `PositionAtPoint`,`EM_GETTEXTRANGE` 用 `GetText`,`EM_SETZOOM` 用 `Zoom`,`EM_SETTARGETDEVICE` 用 `WrapMode`。`EM_EXLIMITTEXT` 无需设置：没有长度上限。

### 字符和段落格式

- **`TNumberingStyle` 有七个成员**(`nsNone`、`nsBullet` 和直到 `lkUpperRoman` 的各种编号),所以 `Paragraph.Numbering := TNumberingStyle(Button.Down)` 照常可用，但 `for … in TNumberingStyle`、带 `else` 的 `case`、以它为下标的数组看到的是七个值。
- **`Numbering := nsBullet`(或某种编号)给没有缩进的段落加上写字板的悬挂缩进**(首行 18 磅，其余行 36 磅);`nsNone` 把缩进还原为 0。Delphi 的 `nsBullet` 把 `LeftIndent` 至少提到 10 磅,`nsNone` 把 `LeftIndent` 设为 0。
- **两端对齐的段落在 `Paragraph.Alignment` 里读出 `taLeftJustify`**,因为 `TAlignment` 没有两端对齐;`ParaAlign` 能读出全部四种。
- **从右到左的 `BiDiMode` 下 `Paragraph.Alignment` 不左右互换**:控件没有从右到左的排版。RTF 文件里从右到左的段落原样保留，保存时写回。
- **自动文字颜色读出 `clDefault`(Delphi 是 `clWindowText`),没有突出显示读出 `clNone`(Delphi 是 `clWindow`)**,因为自动颜色跟着主题走。写入 `clWindowText`、`clWindow` 或 `clDefault` 表示自动或无，和 Delphi 一样。
- **`Font.Assign(SelAttributes)` 对自动颜色的文字给出 `clDefault`**,也不设置字距类型(pitch)。
- **`SelAttributes.Assign(DefAttributes)` 去掉文字自己的字体**,此后它跟着 `DefAttributes` 和主题走;Delphi 是把基础字体的值抄进文字。
- **没有自己字体的文字，`Name` 和 `Size` 读出的是它显示用的字体。** 把读到的值原样写回，这样的文字仍然没有自己的字体，所以工具栏读了再写回不会把字体固化进文字。`Height`、RichMemo 风格的方法和 `Assign(TFont)` 也是这样。
- **字体名 `'default'` 在任何写入里都表示"没有名字"**,文件里不会出现一个叫 `default` 的字体。
- **`Height` 是负数时取绝对值。**
- **`DefAttributes` 是叠在主题上的控件 `Font`**:写它就是改 `Font`,不算一步撤销。它的 `BackColor` 和 `Subscript` 不能设置(写入会抛 `ETyRichEdit`)。
- **`ConsistentAttributes` 比较的是文字存的格式，不是显示出来的样子**:没有字体名的文字和写明了基础字体名的文字放在一起,`caFace` 算作不一致。
- **`ConsistentAttributes` 有工作量上限**:选区非常大，或大 RTF 文件里还有没解析的部分时，它把不能证明一致的属性报成不一致，这样工具栏可以在每次选区变化时读它。
- **选区从段落结尾开始时,`SelAttributes` 回答的是下一段第一个字符**,也就是写入时会被设置格式的那个字符。
- **选中多个段落时,`FirstIndent`、`LeftIndent`、`RightIndent` 按每个段落自己的值来改**,和 Delphi 一样。
- **缩进、段前段后间距和制表位读出时四舍五入到整磅**;Delphi 是截断。写入是精确的。
- **`Tab[i] :=` 超出 `TabCount` 时会一直补到 `i`**,于是个数变成 `i + 1`;Delphi 把个数设为 `i`。`TabCount` 最多 32,下标 32 及以上被忽略。

### 查找和替换

- **`FindText` 的选项是 `stWholeWord` 和 `stMatchCase`(类型 `TTySearchTypes`)**;RichMemo 风格的 `Search` 用 `soMatchCase`、`soWholeWord`、`soBackward`(类型 `TTySearchOptions`)。FPC 的 `StrUtils` 也有 `soMatchCase` 和 `soWholeWord`:同时用到两者的单元里要加限定名。
- **`Length`(`Len`)为负数时一直找到末尾。** Delphi 只有 `StartPos + Length` 等于 -1 时才是找到末尾。超出末尾的范围会被截到末尾。
- **RichMemo 风格的反向 `Search` 从 `Start` 往前找 `Len` 个字符**(`Len` 为负数时找到 0),返回离 `Start` 最近的匹配，和 Windows 上的 RichMemo 一样。
- **带 `var` 结果的 `Search` 报告的是匹配在本控件里的字符长度**;RichMemo 报告的是要找的文字的长度。CR LF 匹配一个段落结尾时，这里给 1,RichMemo 给 2。也有 `Integer` 版本的重载，位置超过 `High(Integer)` 的匹配按没找到处理。
- **整词匹配按光标的分词规则**:每个中文、日文、韩文字符两侧都算词的边界。大小写按码点逐个折叠(`ß` 不匹配 `ss`,没有土耳其语规则),不做规范化。
- **要找的文字里 CR LF、LF、CR 各匹配一个段落结尾。** Delphi 会把 CR LF 变成 CR。
- **图片永远不会被匹配**,链接的文字和合并掉的表格单元格里的文字也不会。
- **文件还在载入时,`FindText` 和 `Search` 只找已经载入的部分**,其余部分返回 -1;`FindNextAsync` 先找已经载入的部分，随着载入继续往下找。
- **在很大的 RTF 文件里查找，是边找边读文件里的段落**,所以上百兆的文件上 `FindNext`、`FindText`、`Search` 可能要十秒以上。这种文件优先用 `FindNextAsync`:它在后台查找，可以取消。
- **`ReplaceAll` 有三种形式**:最简单的返回替换的个数;带 `out ASkipped` 的还数出没动的匹配;带范围(`AStart`、`ALength`,长度为负数表示到末尾，和 `FindText` 的取法一样)的填一个 `TTyRichReplaceResult`。`ReplaceAllAsync` 取同样的范围(默认整篇),把同样的记录交给 `OnReplaceDone`。文档不允许用户编辑改动的匹配(在含有嵌套表格的表格行里，或删掉它会把文字跨过表格单元格或行的边界连起来)保持原样，计入 `Skipped`。文档当下不接受改动时，所有匹配也都这样处理：载入被取消之后,`ReplaceAll` 和 `ReplaceAllAsync` 都如此;文件正在载入或正在保存时,`ReplaceAll` 如此(`ReplaceAllAsync` 则等载入结束)。
- **一次替换算一步撤销，这一步有上限**,是 `Document.MaxUndoBytes` 的四倍。`TTyRichReplaceResult.Ending` 说明它怎么结束:`rreDone`(走完了范围)、`rreLimit`(这一步满了)、`rreCancelled`(被 `CancelFind`、进度事件、再次开始、不是它自己做的编辑或撤销(在它下一轮之前又撤回的也算)、`ClearUndo` 或其他让撤销历史放掉它那一步的操作、换了内容或保存停下;只有后台替换会这样)或 `rreFailed`(无法继续);`Replaced` 和 `Skipped` 是它做了多少。已经替换的保留，算一步撤销。撤销历史如果是在别的操作当中放掉这一步的(文档的 `ClearUndo`、敲了一个键让历史超过字节上限、新的一步把重做那一侧丢掉),替换当场就结束(`FindRunning` 为 False),`OnReplaceDone` 随后从应用程序的消息循环里触发，不在那个操作里面。
- **遇到 `rreLimit` 或 `rreCancelled` 后要接着替换，就从它报告的位置再调用一次**:`ReplaceAll(AFind, AReplace, AOptions, R.ResumeAt, R.ResumeLength, R)`,只要 `R.Ending` 是 `rreLimit` 就再重复(`rreCancelled` 或 `rreFailed` 的调用不会自己接下去)。`ResumeAt` 紧跟在它处理的最后一个匹配后面，按报告时的文字计算(后台替换停下以后做的编辑也算进去);不会有地方被替换两次，替换文字里含有要找的文字时也一样。没有剩下的或者内容已经换掉时,`ResumeAt` 是 -1。后台替换被撤销它自己那一步而停下时,`Replaced` 报 0,`ResumeAt` 报范围的起点：它做的已经一点不剩(如果在它察觉之前又重做了，报的就是重做放回去的个数和那之后的位置)。带 `rfoWholeWord` 时，文字没有变动、又恰好从 `ResumeAt` 开始的再次调用，会把紧挨着上一个已替换匹配的那个匹配也替换掉，和一次做完的结果一样;中间有过编辑，或者从别的位置开始，这样的匹配就按当时的文字来判断。停下的那一次已经计入的被拒绝的匹配，再调用时可能又计入一次 `Skipped`。
- **`OnFindDone` 给出 `AEnd`(`rfeFound`、`rfeNotFound`、`rfeCancelled`)和匹配的 `APos`、`ALen`**(没找到时是 -1 和 0);`OnReplaceDone` 给出 `TTyRichReplaceResult`。每次开始的后台查找或替换都恰好触发一次，控件被销毁时除外。`OnFindProgress` 用 `ATask` 说明在跑的是查找(`rftFind`)还是替换(`rftReplace`),并给出所查范围里已经完成的字符数;`ACancel` 让它停下。这些事件的处理方法可以释放控件：触发事件的那个调用照常返回，就像什么都没找到、没替换一样(`FindNext` 返回 False,`ReplaceAll` 返回 0 和 `rreCancelled`),不会有异常传出来;这个调用本身是在这类处理方法里发出的，也一样。只有一个例外：不要在给 `Text` 赋值期间运行的处理方法里释放控件(`Text` 的写方法是 LCL 自己的，控件的代码返回以后它还要读这个控件);等赋值返回以后再释放，比如用 `Application.ReleaseComponent`。

### 表格

- **只有 `WantTabs` 为 `True` 时，Tab 才在单元格之间移动。** 在单元格里按 Tab 到下一个单元格(一行的最后一格之后是下一行的第一格，合并掉的单元格跳过),并选中它的内容;Shift+Tab 到前一个单元格，在第一个单元格里什么也不做。在表格的最后一个单元格里按 Tab,会在下面加一行(一步撤销),光标进入新行的第一格。Ctrl+Tab 插入制表符。`WantTabs` 为 `False` 时，在表格里 Tab 也是移动焦点，和 Delphi 的 `TRichEdit` 一样。`ReadOnly` 时 Tab 和 Shift+Tab 照样在单元格之间移动，只是在最后一格按 Tab 不加行。
- **表格方法**:`InsertTable(ARows, ACols)`、`InsertRow` 和 `InsertColumn`(`AAfter` 默认为 `True`:插在下面、右边)、`DeleteRow` 和 `DeleteColumn`(删除选区碰到的每一行、每一列)、`DeleteTable`、`InTable`,以及给动作的 `Update` 用的 `CanInsertTable` …… `CanDeleteTable`。Delphi 的 `TRichEdit` 和 RichMemo 都没有这些方法。它们是用户的操作:`ReadOnly` 时什么也不做，返回 `False`,和剪切、粘贴一样;纯文本文档(`PlainText`)、文件还在载入或正在保存，以及表格不允许时，返回 `False`,什么也不改，并通过 `OnEditRefused` 说明原因(不抛异常)。`DeleteColumn` 删除选区盖住的每个单元格所在的列，按选中时显示的文字顺序算：盖住了整整一行，就是所有的列。要在只读控件上改表格，代码执行文档的命令:`Document.Execute` 加上 `tyControls.RichEdit.Commands` 里的 `TTyRichInsertTable`、`TTyRichInsertRow` 等。
- **不能修改的**:有合并单元格、或者单元格里套着表格的表格，它的行和列(按文件原样显示和保存，但不能编辑);各行单元格数不一样的表格，它的列;超过 63 列或 32767 行(Word 的上限)。按需读取的大 RTF 文件里，还有太大而不能整个读入的表格(在文件里超过约 1 MB),以及文件里没有写完整的表格。`DeleteTable` 也能删除有合并单元格的表格。
- **表格行不能粘贴进表格**:光标在单元格里时，粘贴的行作为这个单元格的文字放进去;选中整行再粘贴行会被拒绝。
- **两个表格挨在一起时**(删掉了它们中间的段落),显示成一个表格,Tab 也从一个走进另一个;但行和列的方法只改光标所在的那一个，直到文档保存后再打开。
- **`CanInsertRow` 这些函数回答得很省**:什么都没变时再问，直接给出上次的答案。按需读取的大 RTF 文件分段给出的表格，除非已经读到的部分就不允许修改，否则回答 `True`;真正执行时再读整个表格，不能修改就说明原因。

### 图片

- **从代码插入**:`InsertPictureFromFile(AFileName)`、`InsertPictureFromStream(AStream)` 和 `InsertPicture(AGraphic)`,以及给动作的 `Update` 用的 `CanInsertPicture`。Delphi 的 `TRichEdit` 和 RichMemo 都没有这些方法(本控件也没有 RichMemo 的 `InDelInline`)。不弹对话框：文件由应用程序自己问用户。PNG 和 JPEG 文件按文件本身的字节放进去，一个字节不改，照片用这种方式更好;BMP、GIF、TIFF、图标等其他 LCL 能读的图片，解码后存成 PNG。`InsertPicture` 把 `TPortableNetworkGraphic` 存成 PNG,`TJPEGImage` 存成 JPEG(就是它们的 `SaveToStream` 给出的字节),其他的都存成 PNG。图片替换选区，和粘贴一样(一步撤销，名字是"插入图片");大小按图片自己的分辨率(没有就按 96 dpi)算出的像素，比光标处的可用宽度(页面的文字宽度，或者单元格的宽度)宽时，保持比例缩小。
- **它们是用户的操作**:`ReadOnly`、禁用或者在文档的更新块里时，什么也不做，返回 `False`;纯文本文档、正在载入或保存的文档、粘贴也放不进去的地方、读不了的文件(附上系统的说明)、图元文件(`.wmf`、`.emf`)、不是图片的字节，以及超过 128 MB 或约 3355 万像素的图片，都会被拒绝，原因通过 `OnEditRefused` 告诉(不抛异常)。
- **手柄**:用户可以编辑时，选中的图片显示边框和八个手柄(四个角和四条边的中点);只读或禁用的控件，以及不能调整大小的对象(控件按读到的原样保留的 RTF 块),只显示边框。颜色来自主题的 `TyRichEditObject`(`border-color` 是边框和手柄的轮廓,`background` 是手柄的填充;`StyleOverride` 里的 `--accent` 和 `--surface` 也作用于它们);手柄大小跟着屏幕的 DPI 变，不跟着 `Zoom` 变。应用程序自己的对象类通过 `TTyRichObject.CanResize` 和 `Resized` 参与。
- **拖手柄调整大小**:拖动时有一个轮廓跟着指针，松手之前文档什么都不变。拖角上的手柄保持图片显示出来的宽高比(按住 Shift 时不保持),拖边中点的手柄只改那一边，和拖动的手柄相对的那一边留在原处。每条边至少 300 缇，最多 22 英寸(31680 缇，Word 的上限);文字折行时，宽度最多到图片所在处的可用宽度。这些限制只限制拖动：已经比可用宽度宽、或者小于 300 缇的图片，保持原来的大小，直到拖动把它变小(或变大);在手柄上按下又松开、没有移动，什么也不改。松手是一条命令(`TTyRichResizeObject`,一步撤销，名字是"调整对象大小"),图片保持选中。它立刻按新的大小显示(用已经解码的像素),后台按新的大小生成图像后就变清晰。执行前先问 `OnObjectResize`,它可以改大小，也可以不让改。拖动中按 Esc、失去鼠标捕获、在原来的大小松手、滚动或者文档有了改动，都什么也不改。
- **调整大小保留什么**:图片的字节和格式(写字板的 `\wmetafile8` 还是那个图元文件,JPEG 还是那个 JPEG,逐字节一致);撤销调整会放回原来那个图片对象，所以打开文件、调整大小、撤销再保存，得到的还是原文件的字节。**不保留什么**:调整过大小的图片按新的大小从模型写出，所以文件里图片组除图片本身以外的内容——缩放字(`\picscalex`)、裁剪、同一张图片的其他表示(`\nonshppict`)和属性(`\picprop`)——不再保留。
- **控件画不了的图元文件**(EMF,或者不只是一张位图的 WMF)显示成一个框;写字板里只含一张位图的图元文件照常画出来。两种都和其他图片一样可以选中、调整大小，字节按读到的原样保存。

### 拖动选区

- **在控件里拖动**:在选区上(它的文字，或者选中的图片上手柄以外的地方)按下左键，移动超过拖动阈值(LCL 的 `Mouse.DragThreshold`,应用程序不改时是 96 PPI 下的 5 像素，按屏幕的 PPI 等比放大),就开始拖动选区;松手时把它移到那里，按住 Ctrl 时复制过去(拖动中按下或松开 Ctrl 都行，指针形状立刻跟着变)。移动和复制各算一步撤销(名字是"移动""复制");之后内容在新位置保持选中，撤销会把文字、格式、对象、单元格和选区都恢复原样。按下又松开、中间没有拖动，就是普通的单击;按住 Shift 按下是扩展选区，双击选中词，三击选中段落。开始拖动时，后台正在进行的查找或替换会结束(作为取消，触发它的 `OnFindDone` / `OnReplaceDone`),和用户打字时一样;文档正在载入或保存时不会开始拖动。
- **放下是什么**:等于把选区剪切(复制)后粘贴到那个位置，只是合成一步——格式、对象都带着，整行在表格外仍是行，放进单元格里就成为单元格的文字;跨单元格的范围复制时整行带上，和复制到剪贴板一样。不经过剪贴板。移动的图片还是原来那个图片(撤销后保存，得到的还是原文件的字节);复制出的图片和原图共用同一份字节。对应的命令是 `tyControls.RichEdit.Commands` 里的 `TTyRichMove` 和 `TTyRichCopy`,代码也可以直接对文档执行。
- **拖动的时候**:一条虚线标记显示选区会放到哪里，颜色是主题里对象边框的颜色(`TyRichEditObject` 的 `border-color`);指针显示移动(`crDrag`)、复制(`crMultiDrag`)或"不能放这里"(`crNoDrop`);指针在控件里、靠近文字区的边缘时，视图按拖选的速度滚动;拖动中滚动了(包括用滚轮或滚动条)、缩放了或者控件改了大小，标记和指针形状会显示这时指针下面的位置，松手也放到那里。指针在控件外面时，哪里都不是可以放的位置：没有标记，显示"不能放这里",松手什么也不做。在选区里面松手，或者移动时在选区的开头、结尾松手，什么也不做;放不进内容的位置(含嵌套表格的行)、跨单元格的选区的移动、还在载入的文档，会被拒绝，原因通过 `OnEditRefused` 告诉。按 Esc、按右键、失去鼠标捕获、按下修饰键以外的键、选区或内容有了变化，拖动都会结束，什么也不改。
- **`DragDropEditing`**(发布的属性，默认 `True`)可以关掉这个功能：关掉以后，在选区上按下就是普通的单击。`ReadOnly` 时也不能拖。`DragMode = dmAutomatic` 时，按下开始的是 LCL 自己的拖动(`OnStartDrag`、`OnDragOver`、`OnDragDrop` 这些事件),选区不会被拖动。
- **和 Windows 富文本控件的不同**(Delphi 的 `TRichEdit`,Windows 上的 RichMemo):那里拖动选区是 OLE 拖放，别的程序也能接收;这里目前只在控件内部。接收的一方(`DropEnter`、`DropOver`、`DropLeave`、`DropOn`,参数是一个 `TTyRichDropOffer`)是公开的，别的控件或平台的拖放可以把内容交给它;`DropEffectAt` 和 `DropCursor` 是受保护的虚方法，派生类可以自己决定。

### 没有的东西

- **Delphi 的类型名**:属性类是 `TTyRichTextAttributes` 和 `TTyRichParaAttributes`,集合类型是 `TTyRichConsistentAttributes`、`TTyRichConsistentParaAttributes` 和 `TTySubscriptType`。成员名和 Delphi 一样(`caBold`、`cpaAlignment`、`sstSuperscript` ……),所以用到这些值的代码能编译，用 Delphi 类型名声明变量的代码不能。序号也不同。
- **RichMemo 的类型名**:记录、枚举和集合都带本库的前缀(`TTyFontParams`、`TTyParaMetric`、`TTyParaNumbering`、`TTyTabStopList`、`TTyTextModifyMask` ……),`TTabStop` 是 `TTyRichTabStop`。成员保留 RichMemo 的名字(`paLeft`、`tmm_Styles` ……);在同时用了 `RichMemo` 或 `Menus` 的单元里要加限定名。
- **把 `Integer` 变量传给 `GetStyleRange` 或 `GetParaRange`** 编译不过：改声明为 `TTyRichPos`。
- **控件不保存的属性**:`Protected`、`Disabled`、`Hidden`、`Link`、`Offset`、`Pitch`、`RevAuthor`、`UseForAllText` 以及 `ConsistentAttributes` 里对应的成员(`caProtected` ……)。RTF 文件里的这些内容按原字节保留，保存时写回。
- **多行文本框的成员**:控件不是 `TCustomMemo`,所以没有 `WordWrap`(用 `WrapMode`)、`ScrollBars`(需要时自动出现;`ScrollBarAutoHide`)、`Alignment`(按段落设:`Paragraph.Alignment`)、`MaxLength`、`WantReturns`(回车总是新起一段)、`BorderStyle`、`Color` 和 `ParentColor`(颜色来自主题，用 `StyleOverride` 改)、`HideSelection`、`HideScrollBars`、`GetSelTextBuf`、`SetSelTextBuf`;`is TCustomEdit` 判断和 LCL 的标准编辑动作也认不出它。右键菜单是本库的文本菜单。
- **Delphi 的其他成员**:`OnProtectChange`、`OnResizeRequest`、`OnSaveClipboard`、`OnLinkClick`、`EnableURLs`、`ShowURLHint`、`SelectionStreamMode`、`SpellChecking`、`ShowSpellCheckMenu`、`Transparent`、`EditMargins`、`ActiveLineNo`、`ScrollPosition`(用 `ScrollY`,视图顶端的像素位置，可以写入;`ScrollX` 读出水平偏移)、`Print`、`RenderRange`、`PageRect`、`DefaultConverter`、`RegisterConversionFormat` 和 `SetSelTextToFriendlyURL`。
- **RichMemo 的其他成员**:`SetLink`、`isLink`、`OnLinkAction`、`Print`、`OnPrintAction`、`InDelInline`、`InitParaNumber`、`InitParaBullet`、第二个 `InitTabStopList`、`GetFontParams`、`InitPrintParams` 和 `InitTextUIParams`。
- **替换当前匹配**:用 `SelText :=` 或 `InDelText`。
- **窗体文件里的 `Lines`。** 富文本不能脱离格式按行保存，所以 `Lines` 不发布：在运行时设置文字或载入文件。
- **从 Delphi 转换来的窗体**,对下表里 Delphi 的 `TRichEdit` 存过、本控件不发布的每个属性都会报属性不存在。把它们删掉就够了(打开窗体时 IDE 会弹出"Repair LFM file"对话框，选"移除所有无效属性";或者在编辑器里打开这个 .lfm,用"工具 → 在编辑器中检查 LFM 文件")，除非表里写了要改设什么。

| Delphi 的属性 | 改用 |
|--------------|------|
| `Lines.Strings` | 在运行时设置文字或载入文件 |
| `WordWrap` | `WrapMode`(`False` 对应 `rwmNone`) |
| `ScrollBars`、`HideScrollBars` | 不用设：滚动条需要时自动出现;`ScrollBarAutoHide` |
| `HideSelection` | 不用设：没有焦点时选区照样显示，颜色是主题给的 |
| `Alignment` | 在运行时按段落设 `Paragraph.Alignment` 或 `ParaAlign` |
| `MaxLength` | 不用设：没有长度上限 |
| `WantReturns` | 不用设：回车总是新起一段 |
| `Color`、`ParentColor`、`BorderStyle`、`BorderWidth`、`BevelEdges`、`BevelInner`、`BevelOuter`、`BevelKind`、`BevelWidth`、`Ctl3D`、`ParentCtl3D`、`StyleElements`、`StyleName` | 主题;用 `StyleOverride` 或 `StyleClass` |
| `ParentFont` | 不用设:`Font` 是控件自己叠在主题上的基础字体 |
| `BiDiMode`、`ParentBiDiMode` | 不用设：没有从右到左的排版 |
| `ImeMode`、`ImeName` | 不用设：输入法由系统决定 |
| `EditMargins` | 主题的内边距;用 `StyleOverride` |
| `EnableURLs`、`ShowURLHint`、`SelectionStreamMode`、`SpellChecking`、`Transparent`、`Touch` | 没有对应 |
| `OnLinkClick`、`OnProtectChange`、`OnResizeRequest`、`OnSaveClipboard`、`OnGesture`、`OnMouseActivate`、`OnStartDock`、`OnEndDock` | 没有对应;处理方法留在单元里，不再挂上 |
- **RichMemo 的 `TTyParaNumbering` 只保留 `Style` 和 `NumberStart`**:`pnCustomChar` 变成项目符号,`Indent`、`CustomChar`、`SepChar`、`ForceNewNum` 读出 0、`#0` 或 `False`。
- **竖线制表位**:`tabWordBar` 按左对齐制表位写入。

### 行为不同的 RichMemo 方法

- **对没有自己字体的文字,`GetTextAttributes` 给出显示用的字体名和字号**;自动颜色是 `clDefault`。读、改、写回的写法不会把字体固化进文字。
- **`TTyParaMetric.LineSpacing` 用 RichMemo 的刻度**(单倍 1.2、1.5 倍 1.8、双倍 2.4)。写入时取控件支持的四种里最接近的一种;0 或负数不改行距，固定值或最小值行距读出 0。
- **`SetParaMetric` 和 `SetRangeParaParams` 按每个段落自己的值来改**,算一步撤销。
- **`SetRangeParams` 里同一个样式既在添加集合又在移除集合时，结果是去掉**,和 RichMemo 一样。
- **在光标处用长度 0 调用 `SetTextAttributes`,设置的是接下来输入的格式**;在别处长度 0 什么也不做。
- **`GetStyleRange` 不超出位置所在的段落。**
- **`InDelText` 算一步撤销**,插入的文字用被替换的第一个字符的格式，返回插入的字符数。
- **`LoadRichText` 把 `PlainText` 设为 `False`**;它和 `SaveRichText` 出错时返回 `False`(内存不足照常抛出)。
- **`ZoomFactor` 等于 `Zoom / 100`**,写入时取整到百分之一。

### 新增的

- **段落**:`ParaAlign`(含两端对齐)、`NumberingStart`、`SpaceBefore`、`SpaceAfter`、`LineSpacingRule`、`LineSpacing`(单位是磅);每次写入只改每个段落里自己那一项。
- **选区和编辑**:`CaretIndex`(光标所在的那一端)、`CollapseSelection`、`BeginEdit` / `EndEdit`(多次写入合成一步撤销)、`RangeText`。
- **表格**:`InsertTable`、`InsertRow`、`InsertColumn`、`DeleteRow`、`DeleteColumn`、`DeleteTable`、`InTable` 和各个 `Can…` 函数;Tab 在单元格之间移动(见上面的"表格")。
- **图片**:`InsertPictureFromFile`、`InsertPictureFromStream`、`InsertPicture`、`CanInsertPicture`;选中图片的手柄和拖手柄调整大小,`OnObjectResize`(见上面的"图片")。
- **拖动选区**:用鼠标移动，或按住 Ctrl 复制,`DragDropEditing`,接收的一方 `DropEnter` / `DropOver` / `DropLeave` / `DropOn`(见上面的"拖动选区")。
- **查找和替换**:`FindNext`、`FindNextAsync`、`ReplaceAll`(三种形式)、`ReplaceAllAsync`、`CancelFind`、`FindRunning`、`OnFindProgress`、`OnFindDone`、`OnReplaceDone`。一次替换算一步撤销，不受 `ReadOnly` 限制。
- **`Action` 是发布的**,和 `TTyMemo` 一样(Delphi 的 `TRichEdit` 和 LCL 的 `TMemo` 不发布它):关联了动作时，点击编辑区会执行它;它的 `Caption` 不会进入文字。
- **大文件**:RTF 文件在后台读入(`Loading`、`FinishLoading`、`CancelLoad`、`OnLoadProgress`);`OnSaveProgress` 报告保存进度。
- **事件和设置**:`OnModifiedChange`、`OnEditRefused`(用户的编辑被文档拒绝)、`OnZoomChange`、`OnFallbackFont`、`WrapMode`、`TextEncoding`、`TextCodePage`、`ScrollBarAutoHide`。
- **文档本身**:`Document`(命令、撤销历史、格式),给需要的不只是控件成员的代码用。
