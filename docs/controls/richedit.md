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

完整的例子在 `examples/richedit`：一个小写字板，菜单和工具栏都是下面 §4 的动作，带标尺、状态栏、换皮肤，"示例文档"菜单打开几份样本(中文和各种格式、表格、图片、Word 的带链接的目录)。

## 2. 两层 API

### 2.1 Delphi 的样子(和 RichMemo 的方法)

从 Delphi 的 `TRichEdit` 或 Lazarus 的 RichMemo 搬过来的代码，大多能照原样编译：

- 文字和选区：`Lines`、`Text`、`SelStart`、`SelLength`、`SelText`、`CaretPos`、`SelectAll`、`Clear`。位置按字符(Unicode 码点)数，段落结束符算一个字符，类型是 `TTyRichPos`(`Int64`)。
- 格式：`SelAttributes`(选区的字符格式)、`DefAttributes`(没有自己格式的文字用什么显示)、`Paragraph`(选区碰到的段落的格式)，还有 RichMemo 的 `SetTextAttributes`、`GetTextAttributes`、`SetRangeParams`、`SetParaAlignment`、`SetParaMetric`、`SetParaNumbering`、`GetParaRange`、`SetParaTabs`。读的时候 `ConsistentAttributes` 说哪些属性整个选区都一样。
- 查找和替换：`FindText`、RichMemo 的 `Search`，还有自己的 `FindNext`、`ReplaceAll` 和它们在后台跑的版本 `FindNextAsync`、`ReplaceAllAsync`。
- 文件：`LoadFromFile`、`LoadFromStream`、`SaveToFile`、`SaveToStream`、`PlainText`。
- 其他：`Zoom`、`ReadOnly`、`Modified`、`Undo`、`Redo`、`CanUndo`、`CanPaste`、剪贴板的几个方法。

这一层的每一次写都是文档的一个命令，也就是一步撤销。它是给程序用的：`ReadOnly` 只挡用户，不挡这些调用。文档正在载入或保存的时候写会抛 `ETyRichEdit`。

能编译、做的事却和 Delphi 或 RichMemo 不一样的地方，逐条列在 [LCL 差异](../lcl-differences.md)的最后一节里。最常碰到的几条：

- 位置是字符，不是 UTF-16 单元，换行也只算一个；
- `Lines` 没有 published，窗体文件里不存内容；
- `Text :=`、`Clear` 和载入都清空撤销记录；
- 字号用磅，缩进用磅，和 Delphi 一样；内部存的是缇(1/20 磅)。

### 2.2 文档和命令

底下是文档模型 `Document`(`TTyRichDocument`，单元 `tyControls.RichEdit.Model`)。对它的每一次修改都是一个命令对象，交给 `Document.Execute`：插入文字 `TTyRichInsertText`、删除 `TTyRichDelete`、字符格式 `TTyRichSetCharFormat`、段落格式 `TTyRichSetParaFormat`、对象 `TTyRichInsertObject`、表格的 `TTyRichInsertTable`、`TTyRichInsertRow` 等等(单元 `tyControls.RichEdit.Commands`)。命令只记下改动(片段的引用、旧值)，从不复制整篇文档。`Document.BeginUpdate` / `EndUpdate` 中间的命令合成一步撤销；控件的 `BeginEdit` / `EndEdit` 也是这样，还把选区放回去。

用户的操作是另一组方法：`InsertTable`、`InsertRow`、`DeleteColumn`、`InsertPictureFromFile`、`ApplyParagraphFormat`(标尺用的那个)、`FindNext`。它们像按键一样：只读或禁用时什么都不做，被拒绝时通过 `OnEditRefused` 告诉，不抛异常。每个都有对应的 `Can…`(`CanInsertTable`、`CanInsertPicture`、`CanUndo` ……)，工具栏可以拿它来变灰。

## 3. 标尺 `TTyRichEditRuler`

放在富文本上面，`RichEdit` 指向它。标尺显示插入点所在段落的首行缩进、其他行的缩进(悬挂缩进)、右缩进和制表位，刻度是厘米或英寸(`MeasureUnit`，默认跟系统)，跟着缩放、屏幕 PPI 和水平滚动走。插入点在表格里时，零点是单元格文字的左边。

拖动标记时富文本里出现一条竖线，表示文字会到哪里；按四分之一个单位吸附，按住 Alt 不吸附；Esc 取消。松手是一个命令、一步撤销(通过 `ApplyParagraphFormat`)。在标尺空白处双击加一个左对齐的制表位，把制表位拖出标尺就删掉它。选了几个段落时，标尺显示插入点所在段落的标记，拖动把那一个值给所有选中的段落。只读、禁用、载入中、没连富文本时，标记变灰，拖不动。标尺从不拿焦点。

## 4. 动作 `tyControls.RichEdit.Actions`

一套现成的动作，放进 `TActionList`(IDE 的动作列表编辑器里在"TyControls Rich Edit"分类下)，菜单项、`TTySpeedButton` 或别的控件连上就能用：

| 动作 | 标题 | 快捷键 | Enabled 问的是 | Checked 问的是 |
|---|---|---|---|---|
| `TTyRichEditBold` / `Italic` / `Underline` | 粗体 / 斜体 / 下划线 | Ctrl+B / I / U | 用户这里能不能改格式 | 整个选区都有这个样式 |
| `TTyRichEditStrikeOut` | 删除线 | — | 同上 | 同上 |
| `TTyRichEditSuperscript` / `Subscript` | 上标 / 下标 | — | 同上 | 整个选区都是上标 / 下标 |
| `TTyRichEditAlignLeft` / `Center` / `Right` / `Justify` | 左对齐 / 居中 / 右对齐 / 两端对齐 | Ctrl+L / E / R / J | 同上 | 选区碰到的段落都是这种对齐 |
| `TTyRichEditBullets` / `Numbering` | 项目符号 / 编号 | Ctrl+Shift+L / — | 同上 | 这些段落都是这种列表 |
| `TTyRichEditIndentIncrease` / `Decrease` | 增加 / 减少缩进 | — | 同上 | — |
| `TTyRichEditInsertPicture` | 图片... | — | `CanInsertPicture` | — |
| `TTyRichEditInsertTable` | 表格 | — | `CanInsertTable` | — |
| `TTyRichEditFind` | 查找... | Ctrl+F | 控件可用 | — |
| `TTyRichEditReplace` | 替换... | Ctrl+H | 用户这里能不能改 | — |
| `TTyRichEditUndo` / `Redo` | 撤销 / 重做 | Ctrl+Z / Y | `CanUndo` / `CanRedo` | — |
| `TTyRichEditZoomIn` / `ZoomOut` / `ZoomReset` | 放大 / 缩小 / 100% | Ctrl+加号 / 减号 / 0 | 还没到缩放的上限 / 下限 | 100%：缩放是 100 |

"用户这里能不能改格式"是控件自己的回答(`CaretParagraphView` 的 `Editable`：不是只读、可用、文档不在载入或保存、不在更新中)。动作不加自己的规则：显示什么由控件回答，做什么也走控件给用户的那扇门，所以每个动作就是一步撤销，名字和格式 API 的一样，被拒绝时控件通过 `OnEditRefused` 告诉，和按键被拒一样。

- **作用于哪个富文本**：设了 `RichEdit` 就是它(别的窗体上的也行)；没设就是有焦点的那个 `TTyCustomRichEdit`；都没有就变灰。
- **字符样式**通过 `SelAttributes` 写：没选东西时，它决定接下来打的字是什么格式，不算一步撤销。`SelAttributes` 是程序用的那一层，不挡只读，所以动作只在用户能改格式的地方写；域的结果里被拒绝的，控件会告诉，不会抛出来。
- **缩进**把插入点所在段落的首行移到下一个(上一个)半英寸处，不越过左边距；选了几个段落时都移到那个位置，各自保留自己的悬挂距离(和标尺的规则一样)。
- **插入表格**插入 `Rows` × `Columns`(默认 3 × 3)。插入前触发 `OnChooseSize`，程序可以在这里问用户，改大小，或者取消。
- **插入图片**用本库自己的打开对话框(`Dialog`，一个 `TTyOpenPictureDialog`)，过滤器是控件能读的格式(`TyRichPictureFilter`：LCL 能读的图片都行，PNG 和 JPEG 原样保存字节，其他转成 PNG；不收 WMF、EMF)。
- **查找、替换**显示本库自己的查找、替换对话框(`Dialog`)。"查找下一个"就是控件的 `FindNext`(区分大小写、全字匹配、向上向下，到头了从另一头接着找)；"替换"替换选中的那个匹配再找下一个；"全部替换"是 `ReplaceAll`，一步撤销，`OnReplaced` 告诉替换了几处。没找到时触发 `OnNotFound`，没有处理程序就弹本库的消息框。替换的方法属于程序那一层，不挡只读，所以动作只在用户能改的地方替换。
- **快捷键**是动作的默认值，可以改。同一个键不会两边都处理：LCL 先把键交给有焦点的控件，富文本自己处理 Ctrl+Z、Ctrl+Y(撤销、重做)，动作的 Ctrl+Z、Ctrl+Y 只在焦点不在富文本上、又设了 `RichEdit` 的时候起作用；Ctrl+B 这类富文本不处理的键归动作。

**更新的代价。** 程序空闲时 LCL 会更新每个动作，一个动作连着菜单项和按钮时还不止一次。动作不每次都去问控件：每个富文本有一份记录(`TTyRichEditActionState`)，它在选区、内容、格式、视图、只读或可用状态变了以后问控件一次——听的是标尺也在听的通知(`AddHandlerOnParagraphView`)，不是程序的事件——所有动作都读这份记录。所以不管选区多长、文档多大，一轮空闲更新都不问控件。变了以后那一次要问格式 API 整个选区是不是一致：控件给这一步设了上限(约 30 毫秒的遍历，超出部分按"不一致"算)，还按选区和内容记住答案。100 MB 全选时的实测见 §6。

## 5. 文件

- **RTF**：读，写。没改过的文档保存出来和原文件逐字节一样；改过的，没改的部分原样写回。控件不认识的内容挂在它所在的段落、文字或一个对象上保留，保存时原样写回。中文：读的时候按字体的 `\fcharset` 解码，没有就按 `\ansicpgN`；双字节的 `\'xx\'xx` 拼成一个字；`\uN` 和 `\ucN` 都认。写的时候每个非 ASCII 字符写成 `\uN` 加后备字节，中文字体写 `\fcharset134`。大的 RTF 文件是按需解析的：先建索引，用到哪段才解析哪段。
- **纯文本**：编码先看 BOM，再看是不是合法的 UTF-8，最后用系统的 ANSI 代码页(`TextEncoding`、`TextCodePage` 可以指定)。保存时保持原来的编码、BOM 和换行符。
- **怎么选格式**：`LoadFromFile` 看文件本身；`SaveToFile` 不给格式时看扩展名，再看 `PlainText`。`PlainText = True` 的文档按纯文本存，格式不进文件。
- **图片**按原来的字节保存(PNG、JPEG)；写字板存的图片(一个只装着一张位图的 WMF)也能画出来，画不了的图元文件显示成一个框，字节照样保留。表格、合并单元格、表格里的表格都能读、显示、原样存回；合并单元格的表格、含嵌套表格的行不能增删行列。

## 6. 大文件

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
| 全选 100 MB 的 txt / RTF 后，23 个动作的第一轮更新(问控件的那一次) | 55 / 64 毫秒 |
| 之后的一轮空闲更新 | 0.0 毫秒 |
| 移动 50 M 个字符的选区(拖放) | 314 毫秒 |
| 粘贴 10 MB 的 RTF | 3.6 秒 |

(Windows 10，测时机器的负载 3% 到 5%。)

慢的地方，也就是跟改动范围成正比的事：

- 对整篇文档的格式写(全选后设粗体)：命令要碰每一段，按需解析的 RTF 会被全部解析一遍；范围大时显示等待光标。
- 全选后复制、剪切，或者粘贴一大段：跟内容大小成正比。
- 同步的 `FindText`、`FindNext`、`ReplaceAll` 一直找到底；长文档用 `FindNextAsync`、`ReplaceAllAsync`，它们在后台分片跑。
- 保存一个改过的大文件要把整篇写出去。

## 7. 和 Delphi 的 TRichEdit、RichMemo 不一样的地方

完整的列表在 [LCL 差异](../lcl-differences.md)的最后一节。概括一下：

- 不是 Windows 的 RichEdit：没有 `EM_` 消息，`Perform(EM_…)` 不起作用，那一页列了每个消息该用什么代替；
- 位置是码点，不是 UTF-16 单元；
- `ReadOnly` 只挡用户，程序的写照样能改；用户的操作(`CutToClipboard`、`Undo` ……)在只读时什么都不做，和 Delphi 一样；
- `PlainText` 是文档的状态，载入文本文件会把它设成 `True`；
- 没有 `OnProtectChange`、`OnResizeRequest`、`OnSaveClipboard`；多了 `OnEditRefused`、`OnObjectResize`、`OnDropFiles`、`OnFallbackFont`、后台查找的事件；
- RichMemo 的 `Search` 向后找的规则照 RichMemo 的后端来；`ZoomFactor` 是 `Zoom / 100`。

## 8. 扩展点

- **事件**：`OnEditRefused`(用户的操作被拒绝，原因是一句可以给用户看的话)、`OnObjectResize`(用手柄改图片大小之前，可以改或取消)、`OnDropFiles`(拖进来的文件，自己处理还是交给控件)、`OnFallbackFont`(某个字符换了字体)、`OnLoadProgress`、`OnSaveProgress`、`OnFindProgress`、`OnFindDone`、`OnReplaceDone`。
- **`TTyCustomRichEdit` 的虚方法**：`CreateDocument`、`CreateDevice`、`CreateLayouter`(换文档、测量绘制的设备、排版器)；`RunUserEdit`(看到用户的每一次修改)；`CommandRefusal`、`EditRefused`(怎么说拒绝)；`PlainTextDocument`；`ShowTextMenu`(右键菜单)；`DoChange`、`DoSelectionChange`、`DoZoomChange`；剪贴板读写的几个方法。
- **命令**：自己写一个 `TTyRichCommand` 的子类，交给 `Document.Execute`，它就是一步撤销。
- **标尺**：`DrawMarker`、`DrawTickLabel`、`Snap` 是虚方法；`OnMarkerChanging`(可以不让改)、`OnMarkerChanged`。
- **动作**：子类覆盖 `UpdateOn`、`ExecuteOn`；插入图片的 `AskFileName`、查找替换的 `ShowDialog` 和 `ShowNotFound` 是虚方法，可以换成程序自己的界面。
- **自己的工具栏**：不用这套动作也行，`CaretParagraphView`、`AddHandlerOnParagraphView`、`ApplyParagraphFormat` 和各个 `Can…` 都是公开的，标尺和动作只用这些公开的调用。
