# TTyRichEdit — 富文本编辑

[English](richedit.en.md)

## 1. 它是什么，不是什么

`TTyRichEdit` 是一个自己绘制的富文本编辑器，也能只用来看。它读写 RTF 和纯文本，带格式的文字、段落、列表、表格、图片都能编辑，跟着主题和皮肤走。它不用任何平台自带的富文本控件，所以在 Windows、macOS、Linux(GTK2、GTK3、Qt5、Qt6)上画出来和用起来都一样。

它不做的事：

- **没有页面。** 没有分页视图、页眉页脚、打印预览。文字可以按窗口宽度折行、按文档的纸张宽度和页边距折行(`WrapMode = rwmPage`，像写字板的"按标尺换行")，或者不折行。
- **没有拼写检查。**
- **域是只读的。** 链接、目录、页码、交叉引用这些域，读出来的是文件里存的结果，显示成普通的文字和段落；控件不重新计算它们，结果里的文字也不能改(要删就选中整个域)。改了会被拒绝，原因通过 `OnEditRefused` 告诉。
- **从右往左的文字不排版。** 段落的从右往左标记会读进来、原样写回去，但段落还是从左往右排。
- 文件里控件不认识的东西(批注、脚注、修订、公式、形状、嵌入对象……)不会丢：它们作为看不见的内容或一个对象保留下来，保存时原样写回。

单元 `tyControls.RichEdit`；组件面板 `TyControls Edits` 页上是 `TTyRichEdit` 和它的标尺 `TTyRichEditRuler`。主题的类型键是 `TyRichEdit`(没写的规则从 `TyMemo` 继承)。

```pascal
uses tyControls.RichEdit, tyControls.RichEdit.Ruler, tyControls.RichEdit.Actions;
```

最小的用法：

```pascal
RichEdit1.LoadFromFile('说明.rtf');      // RTF 还是文本，看文件本身
RichEdit1.SelStart := 0;
RichEdit1.SelLength := 5;
RichEdit1.SelAttributes.Bold := True;   // 一步撤销
RichEdit1.SaveToFile('说明.rtf');
```

完整的例子在 `examples/richedit`：一个小写字板，菜单、两行工具栏和编辑框的右键菜单都是下面 §4 的动作——有字体框、字号框(可以填半磅)、文字颜色和突出显示按钮(打开本库的颜色对话框)——带标尺、状态栏、换皮肤，窗口窄了工具栏那一行就折到下一行，"示例文档"菜单打开几份样本(中文和各种格式、表格、图片、Word 的带链接的目录)，还有一个用代码搭的页面(§5)，分别当帮助页和首页显示(§6);"插入"菜单里有链接窗体和书签窗体，双击图片按原大小看图(§7)。

## 2. 两层 API

### 2.1 Delphi 的样子(和 RichMemo 的方法)

从 Delphi 的 `TRichEdit` 或 Lazarus 的 RichMemo 搬过来的代码，大多能照原样编译：

- 文字和选区：`Lines`、`Text`、`SelStart`、`SelLength`、`SelText`、`CaretPos`、`SelectAll`、`Clear`。位置按字符(Unicode 码点)数，段落结束符算一个字符，类型是 `TTyRichPos`(`Int64`)。
- 格式：`SelAttributes`(选区的字符格式)、`DefAttributes`(没有自己格式的文字用什么显示)、`Paragraph`(选区碰到的段落的格式)，还有 RichMemo 的 `SetTextAttributes`、`GetTextAttributes`、`SetRangeParams`、`SetParaAlignment`、`SetParaMetric`、`SetParaNumbering`、`GetParaRange`、`SetParaTabs`。读的时候 `ConsistentAttributes` 说哪些属性整个选区都一样。Delphi 之外还有：`SelAttributes.SizeF`(半磅)、`Paragraph.ListLevel`、`ListStart`、`BulletText`(列表的级别、起始编号、项目符号)、带对齐方式和前导符的 `SetTab`(目录行用点状前导符)、`LineSpacingMultiple`(任意倍数：1.08、3)、`SpaceBefore` / `SpaceAfter`、`Shading`(段落底色)；控件上还有 `ApplyParagraphSpacing`(用户的段前段后间距)、`SetPageSetup`(纸宽和页边距)、`SetDefaultFormats` 和 `DocumentColor`(文档自己的底色)。编号的起始号:给 `Paragraph.NumberingStart`(`ListStart`)写一个数，选区里第一个列表项就从这个数开始一个新列表，其余的项接着往下编;写 0 让它们重新接着编，读到 0 表示这一项接着前一项编。
- 查找和替换：`FindText`、RichMemo 的 `Search`，还有自己的 `FindNext`、`ReplaceAll` 和它们在后台跑的版本 `FindNextAsync`、`ReplaceAllAsync`。
- 文件：`LoadFromFile`、`LoadFromStream`、`SaveToFile`、`SaveToStream`、`PlainText`。
- 其他：`Zoom`、`ReadOnly`、`Modified`、`Undo`、`Redo`、`CanUndo`、`CanPaste`、剪贴板的几个方法。

单位：字符和段落的成员(字号、缩进、间距、制表位)用磅，和 Delphi 一样；页面和表格的尺寸(`SetPageSetup`、构建器的 `PageSetup` 和 `Table` 列宽、`Document.Settings`)用缇，1 英寸 1440 缇，和文件里一样。

这一层的每一次写都是文档的一个命令，也就是一步撤销。它是给程序用的：`ReadOnly` 只挡用户，不挡这些调用。文档正在载入或保存的时候写会抛 `ETyRichEdit`。

能编译、做的事却和 Delphi 或 RichMemo 不一样的地方，逐条列在 [LCL 差异](../lcl-differences.md)的最后一节里。最常碰到的几条：

- 位置是字符，不是 UTF-16 单元，换行也只算一个；
- `Lines` 没有 published，窗体文件里不存内容；
- `Text :=`、`Clear` 和载入都清空撤销记录；
- 字号用磅，缩进用磅，和 Delphi 一样；内部存的是缇(1/20 磅)。

### 2.2 文档和命令

底下是文档模型 `Document`(`TTyRichDocument`，单元 `tyControls.RichEdit.Model`)。对它的每一次修改都是一个命令对象，交给 `Document.Execute`：插入文字 `TTyRichInsertText`、删除 `TTyRichDelete`、字符格式 `TTyRichSetCharFormat`、段落格式 `TTyRichSetParaFormat`、对象 `TTyRichInsertObject`、表格的 `TTyRichInsertTable`、`TTyRichInsertRow` 等等(单元 `tyControls.RichEdit.Commands`)。命令只记下改动(片段的引用、旧值)，从不复制整篇文档。`Document.BeginUpdate` / `EndUpdate` 中间的命令合成一步撤销；控件的 `BeginEdit` / `EndEdit` 也是这样，还把选区放回去。

用户的操作是另一组方法：`ApplyCharacterFormat`(工具栏的粗体、字体框)、`ApplyParagraphFormat`(对齐、缩进，标尺用的也是它)、`InsertTable`、`InsertRow`、`DeleteColumn`、`InsertPictureFromFile`。它们像按键一样：只读或禁用时什么都不做，被拒绝时通过 `OnEditRefused` 告诉一次，不抛异常。`FindNext`(用户的查找下一个)也是这一组的，但它不改文档，只读时照样能用。和格式 API 的区别就在这里：`SelAttributes` 是程序的写，不管只读，被拒绝时抛 `ETyRichEdit`。每个操作都有对应的 `Can…`(`CanFormatCharacters`、`CanFormatParagraphs`、`CanInsertTable`、`CanInsertPicture`、`CanUndo` ……)，回答这个操作现在会不会被接受，工具栏拿它来变灰。它们不需要排版，读的东西有上限：选区里从第一段起最多 `CRichFormatQueryParas` 段，每段查一下域的深度和所在的单元格。

## 3. 标尺 `TTyRichEditRuler`

放在富文本上面，`RichEdit` 指向它。标尺显示插入点所在段落的首行缩进、其他行的缩进(悬挂缩进)、右缩进和制表位，刻度是厘米或英寸(`MeasureUnit`，默认跟系统)，跟着缩放、屏幕 PPI 和水平滚动走。插入点在表格里时，零点是单元格文字的左边。

拖动标记时富文本里出现一条竖线，表示文字会到哪里；按四分之一个单位吸附，按住 Alt 不吸附；Esc 取消。松手是一个命令、一步撤销(通过 `ApplyParagraphFormat`)。在标尺空白处双击加一个左对齐的制表位，把制表位拖出标尺就删掉它。标尺显示段落格式要从哪一段改起的那一段(和 `Paragraph` 读的、拖动改的是同一段)：没选东西时是插入点所在的段落，选了几个段落时是第一个，拖动把那一个值给所有选中的段落。只读、禁用、载入中、没连富文本时，或者在域的结果里、含嵌套表格的行里(`CanFormatParagraphs` 说不行的地方)，标记变灰，拖不动。标尺从不拿焦点。

## 4. 动作 `tyControls.RichEdit.Actions`

一套现成的动作，放进 `TActionList`(IDE 的动作列表编辑器里在"TyControls Rich Edit"分类下)，菜单项、`TTySpeedButton` 或别的控件连上就能用：

| 动作 | 标题 | 快捷键 | Enabled 问的是 | Checked 问的是 |
|---|---|---|---|---|
| `TTyRichEditCut` / `Copy` / `Paste` | 剪切 / 复制 / 粘贴 | Ctrl+X / C / V | 有选区且不是只读 / 有选区 / 剪贴板里有能粘贴的东西 | — |
| `TTyRichEditSelectAll` / `Delete` | 全选 / 删除 | Ctrl+A / — | 文档里有文字 / 有选区且不是只读 | — |
| `TTyRichEditBold` / `Italic` / `Underline` | 粗体 / 斜体 / 下划线 | Ctrl+B / I / U | 用户这里能不能改格式 | 整个选区都有这个样式 |
| `TTyRichEditStrikeOut` | 删除线 | — | 同上 | 同上 |
| `TTyRichEditSuperscript` / `Subscript` | 上标 / 下标 | — | 同上 | 整个选区都是上标 / 下标 |
| `TTyRichEditFontName` | 字体 | — | 同上 | 整个选区都是 `FontName` 这个字体 |
| `TTyRichEditFontSize` | 字号 | — | 同上，且 `Size` 大于 0 | 整个选区都是 `Size` 磅 |
| `TTyRichEditFontGrow` / `FontShrink` | 增大字号 / 减小字号 | Ctrl+Shift+. / , | 同上，且还有下一档 | — |
| `TTyRichEditTextColor` / `HighlightColor` | 文字颜色 / 突出显示 | — | 同上 | — |
| `TTyRichEditClearFormat` | 清除格式 | Ctrl+空格 | 同上 | — |
| `TTyRichEditAlignLeft` / `Center` / `Right` / `Justify` | 左对齐 / 居中 / 右对齐 / 两端对齐 | Ctrl+L / E / R / J | 同上 | 选区碰到的段落都是这种对齐 |
| `TTyRichEditBullets` / `Numbering` | 项目符号 / 编号 | Ctrl+Shift+L / — | 同上 | 这些段落都是这种列表 |
| `TTyRichEditIndentIncrease` / `Decrease` | 增加 / 减少缩进 | — | 同上 | — |
| `TTyRichEditLineSpacing` | 行距 | — | 同上 | 这些段落都是 `Spacing` 这种行距，设了 `Multiple` 时是那个倍数 |
| `TTyRichEditParagraphSpacing` | 段落间距 | — | 同上，且设了 `Before` 或 `After` | 这些段落的段前 / 段后就是给的值 |
| `TTyRichEditInsertPicture` | 图片... | — | `CanInsertPicture` | — |
| `TTyRichEditInsertTable` | 表格 | — | `CanInsertTable` | — |
| `TTyRichEditInsertLink` / `RemoveLink` | 链接... / 取消链接 | — | `CanInsertLink` 或 `CanEditLink` / `CanEditLink` | — |
| `TTyRichEditInsertRowAbove` / `RowBelow` | 在上方 / 下方插入行 | — | `CanInsertRow` | — |
| `TTyRichEditInsertColumnLeft` / `ColumnRight` | 在左侧 / 右侧插入列 | — | `CanInsertColumn` | — |
| `TTyRichEditDeleteRow` / `DeleteColumn` / `DeleteTable` | 删除行 / 列 / 表格 | — | `CanDeleteRow` / `CanDeleteColumn` / `CanDeleteTable` | — |
| `TTyRichEditFind` | 查找... | Ctrl+F | 控件可用 | — |
| `TTyRichEditReplace` | 替换... | Ctrl+H | 用户这里能不能改 | — |
| `TTyRichEditUndo` / `Redo` | 撤销 / 重做 | Ctrl+Z / Y | `CanUndo` / `CanRedo` | — |
| `TTyRichEditZoomIn` / `ZoomOut` / `ZoomReset` | 放大 / 缩小 / 100% | Ctrl+加号 / 减号 / 0 | 还没到缩放的上限 / 下限 | 100%：缩放是 100 |

"用户这里能不能改格式"是控件自己的回答(`CanFormatCharacters`、`CanFormatParagraphs`：不是只读、可用、文档不在载入或保存、不在更新中，而且选区不全在域的结果里、不全在含嵌套表格的行里)。动作不加自己的规则：显示什么由控件回答，做什么也走控件给用户的那扇门，所以每个动作就是一步撤销，名字和格式 API 的一样，被拒绝时控件通过 `OnEditRefused` 告诉，和按键被拒一样。

- **标尺**只在 `CanFormatParagraphs` 说可以的地方能拖：域的结果里、含嵌套表格的行里，标记是灰的，按下去也不开始拖动。
- **作用于哪个富文本**：设了 `RichEdit` 就是它(别的窗体上的也行)；没设就是有焦点的那个 `TTyCustomRichEdit`；都没有就变灰。
- **字符样式**通过 `ApplyCharacterFormat` 写：没选东西时，它决定接下来打的字是什么格式，不算一步撤销。在域的结果里、含嵌套表格的行里，格式动作是灰的；插入图片也一样。
- **剪贴板动作**就是文字菜单的那几个(`CutToClipboard`、`CopyToClipboard`、`PasteFromClipboard`、`SelectAll`、`ClearSelection`)，能不能用的回答和编辑框自己的右键菜单一样。
- **字体和字号**:`TTyRichEditFontName` 设 `FontName`,`TTyRichEditFontSize` 按整磅设 `Size`(字号框要给半磅，可以通过 `ApplyCharacterFormat` 写 `SizeHalfPt`)。增大、减小字号从选区的字号走到常用字号表(8、9、10、11、12、14 …… 72)的下一档。
- **颜色**:`TTyRichEditTextColor`、`TTyRichEditHighlightColor` 套用自己的 `Color`(默认红色、黄色;`clDefault` 是主题的文字颜色,`clNone` 是不突出显示)。先触发 `OnChooseColor`：程序可以在这里问用户(用本库的 `TySelectColor`)、改颜色或者取消；选中的颜色记下来，下次接着用。
- **清除格式**把选区里字符的格式恢复成默认：字体、字号、样式、上下标和颜色；段落格式不动。
- **行距**给选区碰到的段落设 `Spacing`(单倍、1.15、1.5、双倍)，`Multiple` 大于 0 时设成那个倍数(任意倍数，比如 1.08、3);和对齐一样，一种行距一个动作。**段落间距**设段前 `Before`、段后 `After`(磅，精确到缇，7.5 也行；默认 -1，表示那一边不动)，可以只设一边，也可以两边都设——Word 菜单里的 0、6、12 磅就是这样；段落正好是这些磅数时打勾。行高和 Word 的排法一致：单倍是字体自己的行高(西文字体是字高加上字体要求的行间空隙，空隙在文字上方；宋体、微软雅黑这类东亚字体是字高的 1.3 倍，多出的部分上下各一半),1.15、1.5、双倍是它的倍数，多出的高度在文字下方；小于 1 的倍数把整行按比例压低，上下一起少，字照原样画全、会压到上一行上(最小 0.1 倍)；“最小值”不足时补在文字上方；固定行距就是那个值，基线在行高的五分之四处。段前、段后间距在行的外面。每一行的高度取整到设备像素，所以长文本可能比 Word 里短百分之一左右。
- **链接**:`TTyRichEditInsertLink` 通过 `OnGetLink` 询问地址和文字(没有处理程序就什么都不做：由程序去问用户)；插入点在链接里时改这个链接(`SetLink`)，否则新建一个(`InsertLink`)。`TTyRichEditRemoveLink` 就是 `RemoveLink`。见 §7。
- **表格操作**在插入点所在行的上方或下方插入一行，在所在列的左侧或右侧插入一列，或者删除这一行、这一列、整个表格；插入点进到新的行或列。控件说不行的地方就是灰的(不在表格里、有合并单元格的表格、含嵌套表格的行、各行单元格数不同时的列)。
- **缩进**把插入点所在段落的首行移到下一个(上一个)半英寸处，不越过左边距；选了几个段落时都移到那个位置，各自保留自己的悬挂距离(和标尺的规则一样)。
- **插入表格**插入 `Rows` × `Columns`(默认 3 × 3)。插入前触发 `OnChooseSize`，程序可以在这里问用户，改大小，或者取消。
- **插入图片**用本库自己的打开对话框(`Dialog`，一个 `TTyOpenPictureDialog`)，过滤器是控件能读的格式(`TyRichPictureFilter`：LCL 能读的图片都行，PNG 和 JPEG 原样保存字节，其他转成 PNG；不收 WMF、EMF)。
- **查找、替换**显示本库自己的查找、替换对话框(`Dialog`)。"查找下一个"就是控件的 `FindNext`(区分大小写、全字匹配、向上向下，到头了从另一头接着找)；"替换"替换选中的那个匹配再找下一个；"全部替换"是 `ReplaceAll`，一步撤销，`OnReplaced` 告诉替换了几处。没找到时触发 `OnNotFound`，没有处理程序就弹本库的消息框。替换的方法属于程序那一层，不挡只读，所以动作只在用户能改的地方替换。
- **快捷键**是动作的默认值，可以改。同一个键不会两边都处理：LCL 先把键交给有焦点的控件，富文本自己处理 Ctrl+Z、Ctrl+Y(撤销、重做)，动作的 Ctrl+Z、Ctrl+Y 只在焦点不在富文本上、又设了 `RichEdit` 的时候起作用；Ctrl+B 这类富文本不处理的键归动作。

**更新的代价。** 程序空闲时 LCL 会更新每个动作，一个动作连着菜单项和按钮时还不止一次。动作不每次都去问控件：每个富文本有一份记录(`TTyRichEditActionState`)，它在选区、内容、格式、视图、只读或可用状态变了以后问控件一次——听的是标尺也在听的通知(`AddHandlerOnParagraphView`)，不是程序的事件——所有动作都读这份记录。所以不管选区多长、文档多大，一轮空闲更新都不问控件——剪贴板的五个动作除外：它们每次更新都问控件的文字回答(`TeHasSelection`、`TeHasText`、`TeIsReadOnly`)，和 LCL 自己的编辑动作一样；粘贴问 `CanPaste`，它要看系统剪贴板上有哪些格式。变了以后那一次要问格式 API 整个选区是不是一致：控件给这一步设了上限(约 30 毫秒的遍历，超出部分按"不一致"算)，还按选区和内容记住答案。100 MB 全选时的实测见 §9。

## 5. 用代码搭内容

不是文件的页面——首页、帮助页、一段"新功能"说明——用构建器 `TTyRichBuilder`(单元 `tyControls.RichEdit.Builder`)来写。调用的顺序就是页面的顺序，每个调用都返回构建器本身，可以连着写：

```pascal
uses tyControls.RichEdit, tyControls.RichEdit.Builder, Graphics;

procedure ShowWelcome(Rich: TTyRichEdit);
var
  B: TTyRichBuilder;
begin
  B := Rich.NewBuilder;              // the document's own defaults; yours to free
  try
    B.Font('', 20).Bold.Text('Welcome');
    B.Paragraph.Reset.Text('Read the ').Link('guide', '#guide')
      .Text(' or visit ').Link('the Lazarus site', 'https://www.lazarus-ide.org/').Text('.');
    B.Paragraph.Bullet.Text('A point');
    B.Paragraph.Bullet(1).Text('a point under it');
    B.Paragraph.Shading(TColor($00D7F4FF)).Text('A note on a light yellow ground.');
    B.Table([2160, 5040]);
    B.Cell.Bold.Text('Name').Cell.Text('What it is').Reset;
    B.Row.Cell.Text('Builder').Cell.Text('Content made from code');
    B.EndTable;
    B.Paragraph.SpaceBefore(12).Bookmark('guide').Bold.Text('The guide').Reset;
    B.Paragraph.Text('A "#guide" link jumps here by itself.');
    Rich.SetContent(B);              // a new content; AppendContent, InsertContent add to it
  finally
    B.Free;
  end;
end;
```

这个过程原样放在 `examples/richedit/upagesample.pas` 里，跟着示例一起编译。那个单元的其余部分搭了一个更长的页面——一张图片、一个链接组成的目录、带第二级的列表、带点状前导符的制表位、一段带底色的提示、一个表格——示例的"示例文档 > 用代码搭的页面"打开的就是它。

**构建器怎么记格式。** 它记着当前的字符格式和正在搭的这一段的段落格式。字符方面的调用(`Font`、`Bold`、`Italic`、`Underline`、`StrikeOut`、`Superscript`、`Subscript`、`Color`、`Highlight`)改的是之后加进来的内容的格式；`Reset` 回到文档的默认格式。段落方面的调用(`Align`、`Indent`、`Spacing`、`SpaceBefore`、`SpaceAfter`、`LineSpacing`、`LineSpacingExact`、`Tab`、`Bullet`、`Numbered`、`Shading`)改的是正在搭的这一段。第一段一开始就有；`Paragraph` 结束这一段、开始下一段，下一段用默认的段落格式，字符格式保持不变。字号、缩进、间距用磅；表格的列宽用缇(1 英寸 1440 缇)。

- **文字**:`Text`(`#9` 是制表符,`#10` 是段内换行)。
- **列表**:`Bullet(级别, 符号)`、`Numbered(级别, 起始编号)`;0 级是最外层(最深 8 级),每一级有自己的悬挂缩进。给了起始编号的项从这个号开始一个新列表，不给(0)就接着同一级的前一项编：`Numbered(0, 5)`、`Numbered`、`Numbered` 是 5、6、7,后面再来一个 `Numbered(0, 1)` 又是 1;内层的项跟在外层的项后面从 1 开始。
- **制表位**:`Tab(位置, 对齐, 前导符)`，比如目录行用 `Tab(300, rtaRight, rtlDot)`。
- **链接和书签**:`Link(文字, 地址)`——文字在前，按页面的阅读顺序，和 `Text` 一样；控件的 `InsertLink(地址, 文字)` 地址在前，因为文字可以不给——`Bookmark(名字)`(一个点)、`BookmarkStart` / `BookmarkEnd`(一段范围)。指向 `'#名字'` 的链接点了就跳到那个书签，不用写代码(见 §7)。
- **图片**:`Picture` 可以来自 `TGraphic`、文件、流、图像列表加下标,`PictureResource` 来自程序的资源；大小用磅，给 0 就是它自己的大小(按 96 dpi 算像素)。PNG 和 JPEG 原样保存字节，其他格式转成 PNG。
- **表格**:`Table(列宽)`(空数组就是平分正文宽度)，每个单元格的内容前面先 `Cell`,`Row` 开始下一行,`EndTable` 结束。每一行的单元格数必须和列数相同。紧跟在 `EndTable` 后面的 `Paragraph` 就是表格后面的那一段，不会多出一段。
- **样式**:`DefineStyle(名字)` 把当前的字符格式和段落格式记在一个名字下,`Style(名字)` 两样一起套用。它们只是搭页面时的方便，不会进文档。
- **文档自己的设置**:`PageSetup(纸宽, 左边距, 右边距)` 和 `DocumentColor(颜色)` 只有 `SetContent` 会用。

调用的地方不对——表格外面调 `Cell`、单元格里再建表格、Word 不接受的地址或书签名、读不了的图片——会抛 `ETyRichEdit`，消息里写着是哪个调用("TTyRichBuilder.Cell: …")。

**放进控件的三种方式。** 三个都是代码对文档的修改，不看 `ReadOnly`，所以只读的页面也能用。构建器还是你的，内容不变，可以再放一次。文档还在载入时，`SetContent` 结束载入、换掉文档；正在保存时抛 `ETyRichEdit`。`AppendContent`、`InsertContent` 遇到正在载入或保存的文档时抛 `ETyRichEdit`。

| 调用 | 做什么 |
|---|---|
| `SetContent(B)` | 换成新内容，和载入文件一样：撤销历史清空,`Modified` 为 False，插入点在开头,`PageSetup` / `DocumentColor` 生效。 |
| `AppendContent(B)` | 内容接在最后一段后面，一步撤销。最后一段有内容就保持不变；是空段的话，内容的第一段占它的位置。 |
| `InsertContent(Pos, B)` | 内容插在 `Pos`，一步撤销。在段首就把各段整段插在这一段前面；在段中按粘贴的规则插入；在表格单元格里，各段都成为这个单元格的段落(构建器里的表格变成文字)。 |

**代价。** 构建器只做记录：每种格式在池里只存一份，搭的时候什么都不测量、不排版。放进控件时也不排版；下一次绘制时排一次版、画一次。在开发机上，一万段带格式的内容(加粗的词，每十段一个链接)搭好并用 `SetContent` 放进去，大约 100 毫秒。

**现在还做不到的。** 单元格的底色、边框和行高会接受下来(单元格里的 `Shading`、`Row(行高)`)并记住，但要等表格属性做好以后才显示；列宽已经生效。没有合并单元格；单元格里建表格会被拒绝。

## 6. 当展示页用

富文本控件可以用来展示页面，而不是编辑：首页、导航页、帮助页，不用再加载一个 HTML 浏览控件。下面这些属性让它变成展示页：

| 属性 | 作用 |
|---|---|
| `ReadOnly` | True：用户不能输入、不能修改；代码照样能写。 |
| `CaretWhenReadOnly` | False:`ReadOnly` 时不显示插入点。选区照常画。 |
| `AllowSelection` | False：用户选不了任何东西——不能拖选、双击，不能 Shift+方向键，Ctrl+A 和复制不起作用；指针在文字上是箭头，在链接上是手形。同时是 `ReadOnly` 时，右键不弹控件自己的菜单(里面每一项都会是灰的)；`PopupMenu` 和 `OnContextPopup` 和别的控件一样能用。 |
| `FocusOnClick` | False：点击不拿焦点(滚轮和链接照常)；再把 `TabStop` 设成 False，就永远不会拿到焦点。 |
| `ScrollBars` | `ssNone`：从不显示自己的滚动条；按键照样能滚，滚轮交给父控件。其他值只在内容放不下时才显示滚动条。滚轮只在控件能滚的方向上归控件(那个方向可以有滚动条，内容又放不下)——滚到头了也还是它的；否则交给父控件，所以放在滚动框里的页面跟着滚动框滚。Ctrl+滚轮总是缩放。 |
| `AutoHeight` | True：内容、宽度、缩放、PPI 或主题变了，`Height` 就跟着 `ContentHeight` 变(受 `Constraints` 限制)。`Align`(`alClient`、`alLeft`、`alRight`)或上下两个锚点决定高度时，它不起作用；内容尺寸还是估计值时(`ContentSizeIsEstimate`：文件还在载入，或者段落多于整篇测量的数目)也不起作用——控件保持现在的高度。它设的高度不超过 `CRichAutoHeightLimit`(32,000 像素)：远超这个值窗口就出错。它是给页面用的，不是给文件用的：控件保留一块和自己一样大的绘制表面，一个页面占宽 × 高 × 4 字节；比这个上限还长的文档，应该放在自己滚动的控件里。 |

`ContentHeight`、`ContentWidth` 是在当前宽度、缩放和主题下内容需要的客户区像素；`ContentSizeIsEstimate` 说明它们是不是估计值(没有整篇排版的大文档)。每次变化触发一次 `OnContentSizeChange`。

两种常用组合，和示例的页面窗体(`examples/richedit/upageform.lfm`)一样：

- **帮助页**——能阅读、选中、复制，自己滚动：`ReadOnly := True; CaretWhenReadOnly := False;`,`Align := alClient`。`AllowSelection` 和 `ScrollBars` 保持默认值(True、`ssBoth`)。
- **首页**——高度跟着内容，放在 `TTyScrollBox` 里，和别的控件一起作为一整页滚动：`ReadOnly := True; CaretWhenReadOnly := False; AllowSelection := False; FocusOnClick := False; TabStop := False; ScrollBars := ssNone; AutoHeight := True;`，在滚动框里 `Align := alTop`。`FocusOnClick` 为 False 让点击不拿焦点；`TabStop` 为 False 让 Tab 不停在它上面——首页两个都要。鼠标在页面上滚滚轮，滚动的是滚动框；右键不弹页面自己的菜单。`AcceptDrops` 仍是 True：拖到页面上的文件归控件(它是只读的，什么都不发生)，到不了窗体——窗体要接收拖进来的文件时，把它设成 False。

**页面上的链接。** 只读的页面，或者 `AllowSelection` 为 False 的页面，左键单击(或中键单击)链接就触发 `OnLinkClick`；可编辑的页面要 Ctrl+单击，和 Word 一样。控件自己从不打开地址：网址在 `OnLinkClick` 里打开(`OpenURL`)。指向 `'#名字'` 的链接由控件自己跟过去(`FollowBookmarkLinks`，默认 True)：书签所在的那一行来到视图顶部，已经在视图上面三分之一里的就不动。首页上的富文本高度就是内容的高度，它自己没有可滚的；要动的是外面的滚动框，可以在 `OnFollowLink` 里做：

```pascal
procedure TPageForm.HomeFollowLink(Sender: TObject; const AName: string; var AAllow: Boolean);
var
  s, e: TTyRichPos;
  r: TRect;
begin
  AAllow := False;
  if not HomeRich.FindBookmark(AName, s, e) then Exit;
  r := HomeRich.PositionRect(s);
  HomeBox.ScrollTo(0, HomeBox.ScrollY + HomeRich.Top + r.Top);
end;
```

**主题。** "自动"颜色的文字用主题的文字颜色画，没有自己颜色的链接用主题的链接颜色画，所以用构建器搭的页面会跟着皮肤和深色模式变。页面自己指定的颜色(一个红字、一段底色、`DocumentColor`)不变；落在这些颜色上的"自动"颜色文字，从主题文字颜色和它的反色里取更醒目的那个。

## 7. 链接和书签

链接就是 Word 的 HYPERLINK 域，地址是 `'目标'`、`'#名字'`(本文档的书签)或 `'目标#名字'` 之一。用户这一层的方法：

- `InsertLink(地址, 文字)`：有选区时选区原样成为链接的文字；给了文字就用它替换；都没有就用地址本身作文字。地址在前，因为文字可以不给；构建器的 `Link(文字, 地址)` 按阅读顺序文字在前——在两者之间搬代码时留意参数顺序。
- `SetLink(地址, 文字)`：插入点或选区所在的链接换成新地址；给了文字，链接的文字也换掉。
- `RemoveLink`：链接不再是链接，文字留下，去掉链接的外观。
- `CanInsertLink`、`CanEditLink` 回答现在做不做得了；`LinkAtSelection` 给出链接的位置和地址。

它们是用户的操作：`ReadOnly` 时被拒绝，每个都是一步撤销，被拒绝时通过 `OnEditRefused` 告诉。链接的文字是域的结果，不能直接在里面打字，要用 `SetLink` 改。动作 `TTyRichEditInsertLink`(它的 `OnGetLink` 询问地址和文字；插入点在链接里时改的就是那个链接)和 `TTyRichEditRemoveLink` 从菜单做同样的事(见 §4)。

**两种外观。** `InsertLink` 给新链接 Word 的外观：下划线，文字没有自己的颜色时用 Word 的链接蓝，和 Word 新建的链接一样。构建器的 `Link` 做出来的是下划线加"自动"颜色，按主题的链接颜色画，会跟着皮肤变。两种情况下，文字有自己的颜色就保持那个颜色。

**书签。** `BookmarkCount`、`BookmarkName(下标)` 按书签位置的先后列出书签；隐藏书签(以"_"开头的名字，Word 给目录标题建的那种)要传 `AIncludeHidden` 才列出。`FindBookmark` 给出书签的起点和终点；`GoToBookmark` 把插入点放过去，并把那一行放到视图顶部(这是移动，不是修改，只读的页面也能用)。`AddBookmark(名字)` 标记选区或插入点所在的位置,`DeleteBookmark`、`RenameBookmark` 删除和改名；这三个和 `InsertLink` 一样是用户的操作，`CanEditBookmarks` 回答现在做不做得了。名字遵守 Word 的规则(`TyRichBookmarkNameValid`：字母开头，后面是字母、数字或"_"，最多 40 个)，比较时不分大小写。按需读入的大 RTF 文件里，找一个书签只读它两端所在的那几段。

**在书签处输入和粘贴。** 和 Word 一样，紧挨书签起点输入的文字进到书签里，紧挨书签终点输入的文字在书签后面；书签只是一个点时，文字在这个点后面。粘贴和输入法上屏的文字也是这样。粘贴、拖放或用 `InsertContent`、`AppendContent` 放进来的书签，如果文档里已经有同名的书签，就不放进来：文字照样进来，原来的书签不动。只带进来一端的书签也不放进来。剪切再粘贴，或者拖动移动文字，书签会跟着一起移过去。

**跟随链接。** 点击链接触发 `OnLinkClick(Sender, URL, Button)`，和 Delphi 一样。`'#名字'` 的链接接着会被跟过去：先触发 `OnFollowLink(Sender, Name, var Allow)`,`Allow := False` 就不跳；然后 `GoToBookmark`。书签不存在就什么都不做。`'目标#名字'` 和其他地址，控件从不自己跟过去。

**对象。** 点击或双击图片、或者显示图片的块(公式、嵌入对象)时，触发 `OnObjectClick`、`OnObjectDblClick`:`procedure(Sender: TObject; const AClick: TTyRichObjectClick; var AHandled: Boolean)`。这个记录里有对象(`RichObject`)、它的位置(`Pos`)、鼠标键、按键(`Shift`)、客户区像素的点(`Point`)和对象在客户区里的框(`Bounds`)；`PointInPicture(宽, 高)` 把这个点换算到那个大小的图片里——首页上的图片热区就这样做。用记录是为了以后加成员不会让已有的处理程序编译不过。`AHandled := True` 就不再做点击原本接着要做的事。`ObjectAtPoint(X, Y, Pos)` 找出某个点下面的对象。图片可以按它自己的大小交给 `TPicture` 或 `TBitmap`(`Picture.Assign(TheObject)`),`TTyRichPicture.SaveImageToStream` 写出它的文件字节。示例里看大图的窗体(`uviewerform.pas`)就是这样处理双击的。

## 8. 文件

- **RTF**：读，写。没改过的文档保存出来和原文件逐字节一样；改过的，没改的部分原样写回。控件不认识的内容挂在它所在的段落、文字或一个对象上保留，保存时原样写回。中文：读的时候按字体的 `\fcharset` 解码，没有就按 `\ansicpgN`；双字节的 `\'xx\'xx` 拼成一个字；`\uN` 和 `\ucN` 都认。写的时候每个非 ASCII 字符写成 `\uN` 加后备字节，中文字体写 `\fcharset134`。大的 RTF 文件是按需解析的：先建索引，用到哪段才解析哪段。
- **列表**:写成 Word 的列表表(`\listtable`、`\listoverridetable`,段落上 `\lsN\ilvlM`),旁边留一份 `{\*\pn …}` 给系统的 RichEdit 这类不认列表表的程序;Word 里显示的编号和控件画的一样。规则只有一条：给了起始号的项从这个号开始一个新列表(构建器的 `Numbered(0, 5)`),没给的(`Numbered`,起始号 0)接着同一级的前一项编;遇到更外层的项、不是列表项的段落或同一级换了种类，列表就断开，下一项从 1 开始。所以 `Numbered(0, 5)`、`Numbered`、`Numbered` 是 5、6、7,紧接着的 `Numbered(0, 1)` 又是 1;内层的项跟在外层的项后面总是从 1 开始。级别是 0 到 8(RTF 和 Word 只有九级)。
- **纯文本**：编码先看 BOM，再看是不是合法的 UTF-8，最后用系统的 ANSI 代码页(`TextEncoding`、`TextCodePage` 可以指定)。保存时保持原来的编码、BOM 和换行符。
- **怎么选格式**：`LoadFromFile` 看文件本身；`SaveToFile` 不给格式时看扩展名，再看 `PlainText`。`PlainText = True` 的文档按纯文本存，格式不进文件。
- **图片**按原来的字节保存(PNG、JPEG)；写字板存的图片(一个只装着一张位图的 WMF)也能画出来，画不了的图元文件显示成一个框，字节照样保留。表格、合并单元格、表格里的表格都能读、显示、原样存回；合并单元格的表格、含嵌套表格的行不能增删行列。

## 9. 大文件

承诺的：100 MB 的 txt 和 100 MB 的 RTF 能打开、能编辑而不卡——第一屏 1 秒内出来，滚到任意位置 100 毫秒内，敲一个键 30 毫秒内，内存不超过文件大小的 3 倍。界面线程上唯一跟文档大小成正比的事是载入时的那一遍扫描；其他的事只碰看得见的部分，或者在后台分片做，可以取消(`OnLoadProgress`、`CancelLoad`、`FindNextAsync`、`ReplaceAllAsync`、`CancelFind`)。

本机性能测试(`TTyRichEditPerfTest`)的数字：

| 测的是什么 | 时间 |
|---|---|
| 100 MB 的 txt：载入并画出第一屏(文件刚写过，在系统缓存里) | 338 毫秒 |
| 100 MB 的 txt：跳到中间并画出来 | 52 毫秒 |
| 100 MB 的 txt：在中间敲一个字，到画完 | 2.1 毫秒 |
| 100 MB 的 RTF：载入第一片并画出第一屏 | 330 毫秒 |
| 100 MB 的 RTF：其余部分在后台建完索引(不卡界面) | 1.5 秒 |
| 100 MB 的 RTF：在中间敲一个字，到画完 | 1.6 毫秒 |
| 载入 100 MB 后进程的峰值内存 | 约 180 MB |
| 10,000 行的表格里按 Tab | 1.1 毫秒 |
| 全选 100 MB 的 txt / RTF 后，23 个动作的第一轮更新(问控件的那一次) | 50 / 70 毫秒 |
| 之后的一轮空闲更新 | 0.0 毫秒 |
| 移动 50 M 个字符的选区(拖放) | 314 毫秒 |
| 粘贴 10 MB 的 RTF | 3.6 秒 |

(Windows 10，测时机器的负载 3% 到 5%。)

慢的地方，也就是跟改动范围成正比的事：

- 对整篇文档的格式写(全选后设粗体)：命令要碰每一段，按需解析的 RTF 会被全部解析一遍；范围大时显示等待光标。
- 全选后复制、剪切，或者粘贴一大段：跟内容大小成正比。
- 同步的 `FindText`、`FindNext`、`ReplaceAll` 一直找到底；长文档用 `FindNextAsync`、`ReplaceAllAsync`，它们在后台分片跑。
- 保存一个改过的大文件要把整篇写出去。

## 10. 和 Delphi 的 TRichEdit、RichMemo 不一样的地方

完整的列表在 [LCL 差异](../lcl-differences.md)的最后一节。概括一下：

- 不是 Windows 的 RichEdit：没有 `EM_` 消息，`Perform(EM_…)` 不起作用，那一页列了每个消息该用什么代替；
- 位置是码点，不是 UTF-16 单元；
- `ReadOnly` 只挡用户，程序的写照样能改；用户的操作(`CutToClipboard`、`Undo` ……)在只读时什么都不做，和 Delphi 一样；
- `PlainText` 是文档的状态，载入文本文件会把它设成 `True`；
- 没有 `OnProtectChange`、`OnSaveClipboard`,`OnResizeRequest` 换成 `OnContentSizeChange` 加 `ContentHeight`(§6)；多了 `OnEditRefused`、`OnObjectResize`、`OnDropFiles`、`OnFallbackFont`、后台查找的事件；
- RichMemo 的 `Search` 向后找的规则照 RichMemo 的后端来；`ZoomFactor` 是 `Zoom / 100`。

## 11. 扩展点

- **事件**：`OnEditRefused`(用户的操作被拒绝，原因是一句可以给用户看的话)、`OnObjectResize`(用手柄改图片大小之前，可以改或取消)、`OnDropFiles`(拖进来的文件，自己处理还是交给控件)、`OnFallbackFont`(某个字符换了字体)、`OnLinkClick` 和 `OnFollowLink`(点了链接、要跟到书签之前)、`OnObjectClick` 和 `OnObjectDblClick`(点了图片)、`OnContentSizeChange`(内容尺寸变了)、`OnLoadProgress`、`OnSaveProgress`、`OnFindProgress`、`OnFindDone`、`OnReplaceDone`。
- **`TTyCustomRichEdit` 的虚方法**：`CreateDocument`、`CreateDevice`、`CreateLayouter`(换文档、测量绘制的设备、排版器)；`RunUserEdit`(看到用户的每一次修改)；`CommandRefusal`、`EditRefused`(怎么说拒绝)；`PlainTextDocument`；`ShowTextMenu`(右键菜单)；`DoChange`、`DoSelectionChange`、`DoZoomChange`；剪贴板读写的几个方法。
- **命令**：自己写一个 `TTyRichCommand` 的子类，交给 `Document.Execute`，它就是一步撤销。
- **标尺**：`DrawMarker`、`DrawTickLabel`、`Snap` 是虚方法；`OnMarkerChanging`(可以不让改)、`OnMarkerChanged`。
- **动作**：子类覆盖 `UpdateOn`、`ExecuteOn`；插入图片的 `AskFileName`、查找替换的 `ShowDialog` 和 `ShowNotFound` 是虚方法，可以换成程序自己的界面。
- **自己的工具栏**：不用这套动作也行，`ApplyCharacterFormat`、`ApplyParagraphFormat`、各个 `Can…`、`AddHandlerOnParagraphView`(什么时候该再问一次)、`ParagraphView` 都是公开的，标尺和动作只用这些公开的调用。
