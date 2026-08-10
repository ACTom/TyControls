# RTL 镜像层的定量摸底 —— 哪些控件是三行,哪些是重写

本文只回答一个问题:**如果决定做 RTL 的"镜像"(布局层),各控件族分别要付多少。**

不含 BiDi(文本层)。双向文本分段、视觉序重排、`TTyPainter.DrawText`/`MeasureText` 走
`TBidiTextLayout` —— 那是另一条线正在做的事,本文一律假设它落地。两者的唯一交界写在
§6.1,那一处必须两边一起看。

**本文没有跑过任何构建**,全部结论来自读源码;每一条结构性判断都带 `文件:行`。
拿不准的地方写"拿不准",不四舍五入。

> 记账口径:不估工时,只分三档 ——
> **(a) 几行**:几何已经收口在一个纯函数里,给它加一个 `RightToLeft` 参数就完事。
> **(b) 有边界**:同一个单元里几个函数,机械但真有量。
> **(c) 重写**:布局模型本身假设了从左往右 —— 从左边累加的固定偏移、下标↔位置的算术、
> 钉死在 x=0 的滚动原点。

---

## 0. 三句话结论

1. **最重要的发现:文本对齐这一半有唯一收口点,而且只有一行。**
   全库 146 处 `DrawText` 调用最终都落到 `TTyPainter.DrawTextLine`
   (`source/tyControls.Painter.pas:997`),对齐只在一处生效:
   `style.Alignment := AHAlign`(`:1045`)。
   给 `TTyPainter` 加一个在 `BeginPaint`(`Painter.pas:483`)时写入的 `FRightToLeft`,
   在这一行改成 `BidiFlipAlignment(AHAlign, FRightToLeft)`,**146 个调用点一次全翻**。
   Label / Panel / Button / GroupBox / StatusBar / Tab / 列表行文字全部跟着走,控件代码一行不动。
   这是整份文档里性价比最高的一条,应该第一个做。

2. **几何这一半没有收口点。** 不存在共享的"内容矩形"函数:`.Padding.Left` 在 `source/` 里
   出现 114 处,每个控件在自己的 `RenderTo` 里各内缩一次(`tyControls.CheckBox.pas:275-280`、
   `tyControls.Button.pas:616-619`、`tyControls.CheckBox.pas:577-580` 是同一段的三份拷贝)。
   `AdjustClientRect` 只有 9 个控件覆写,且**全部是对称内缩**(左右各减同一个 padding),
   镜像与否无差别 —— 它不是杠杆点。

3. **桶分布(brief 列的 15 组)**:**(a) 5 组 · (b) 7 组 · (c) 3 组**。
   (c) 是 `TTyCustomGrid`、`TTyTreeView`、`TTyDateTimePicker`,三个都是**同一个病因**:
   绘制与命中各算一遍 x 轴。TreeView 的源码注释自己写着 "KEEP IN SYNC WITH RenderTo"
   (`tyControls.TreeView.pas:5998`),DateTimePicker 的 MouseDown 里写着
   "Recompute text rect exactly as in RenderTo"(`tyControls.DateTimePicker.pas:1352`)。
   **这三个不是"镜像难",是"它们本来就欠一次收口"。** 镜像只是把这笔债催了出来。

---

## 1. LCL 白送了什么,没送什么

三个被点名的函数,读了函数体:

| 位置 | 实际做的事 |
|---|---|
| `controls.pp:1833` / `include/control.inc:6017` `IsRightToLeft` | `Result := UseRightToLeftReading`,而后者(`:6035`)= `BiDiMode <> bdLeftToRight`。**一个一行的谓词。** |
| `controls.pp:2779` / `:2922` `BidiFlipAlignment` | 一张 `array[Boolean, TAlignment]` 查表:左↔右互换,`taCenter` 不动。 |
| `controls.pp:2781` / `:2966` `BidiFlipRect` | `Left := ParentRect.Right - (Left - ParentRect.Left) - W`。**在父矩形内水平镜像一个矩形,五行。** |

### 1.1 真正白送的三样

- **属性管道**:`BiDiMode` / `ParentBiDiMode` 的存储、`stored IsBiDiModeStored`
  (`control.inc:6007`)、父子传播(`CMParentBiDiModeChanged`,`control.inc:5993`)、
  改动时的 `Invalidate` + `AdjustSize`(`wincontrol.inc:6777-6785`)。这一套不用我们写。
  对 `TTyCheckGroup`/`TTyRadioGroup` 尤其值钱:它们是**真子控件**组成的,父控件设一次
  `BiDiMode`,每个子 `TTyCheckBox` 自动收到,各自翻自己的指示器。
- **`BidiFlipRect` 这条算术**:所有"把一个矩形翻到对面"的地方直接调它,不必自己写公式,
  也就不会有人写错一个 `-1`。
- **`BidiFlipAlignment`**:§0.1 那一行就是它。

### 1.2 明确**没有**送的四样(这是决策的关键)

1. **像素层什么都没有。** LCL-Win32 的 `SetBiDiMode`
   (`interfaces/win32/win32wscontrols.pp:355-372`)只设 `WS_EX_RTLREADING` /
   `WS_EX_RIGHT` / `WS_EX_LEFTSCROLLBAR`,**不设 `WS_EX_LAYOUTRTL`**。
   也就是说 GDI 不会替我们镜像 DC。
   - 好消息:不会和我们的 BGRA blit 打架,不存在"翻两次"。
   - 坏消息:一分钱便宜也没占到。`WS_EX_RIGHT`/`WS_EX_RTLREADING` 只对原生控件的
     文本绘制有意义;`WS_EX_LEFTSCROLLBAR` 只挪**非客户区**滚动条,而我们的滚动条
     全是自己画的子控件(`tyControls.ListBox.pas:671`、`tyControls.Grid.pas:3357`、
     `tyControls.ScrollBox.pas` 的 `FVScrollBar`)。**三个标志对我们全部是空操作。**
2. **`Align` 引擎不认 BiDi。** 我在 `include/wincontrol.inc` 里只找到**一处** BiDi 分支,
   在 `TAutoSizeBox.SetTableControls`(`:1551`、`:1562`)—— 那是 `ChildSizing` 的
   **表格布局**路径。`alLeft`/`alRight` 的停靠对齐**完全不看 `BiDiMode`**。
   **含义:LCL 自己的 `TPanel` 在 RTL 下,`alLeft` 的子控件也还在左边。**
   我们没有义务、也不该去替 LCL 镜像 `Align` —— 那会让我们的容器和 LCL 容器行为分叉。
   这一条直接砍掉了"容器要不要镜像子控件布局"这个最大的坑(见 §5 不做清单)。
3. **`BidiFlipAnchors`(`controls.pp:2933`)是个陷阱。** 它名字像纯函数,实际**会写**
   `Control.AnchorSide[akLeft/akRight]`(`:2947-2950`)再返回翻过的 `Anchors`。
   调用一次改控件状态,调两次翻回去。**不要在绘制路径上调它。**
4. **命中测试一行都没有。** LCL 这三个函数没有一个碰命中。**这正是本文的全部工作量所在。**

---

## 2. 有没有唯一的收口点?

有一个,而且只有一个。另外两个候选查证后是假的 —— 写在这里免得下一个人再查一遍。

### 2.1 ✅ 真收口点:`TTyPainter` 的文本对齐

- 全库 `.DrawText(` 调用 **146** 处、`.BeginPaint(` **120** 处、`RenderTo` 声明 **74** 处。
- 多行走 `TTyPainter.DrawText`(`Painter.pas:939`),它逐行转交
  `DrawTextLine`(`:997`);单行直接进 `DrawTextLine`。
- `DrawTextLine` 里对齐只出现在**三处**:`style.Alignment := AHAlign`(`:1045`)、
  助记符下划线的 `case AHAlign of`(`:1058-1062`)、以及非 Windows 的
  `DrawTextSupersampled`(`:1079` 声明,`:1103` 是它自己那份
  `style.Alignment := AHAlign`)。
- 结论:**把 RTL 标志放进 `TTyPainter`,在 `DrawTextLine` 顶部做一次
  `AHAlign := BidiFlipAlignment(AHAlign, FRightToLeft)`,三处同时生效。**

  ⚠️ 一条必须写死的边界:**只有当调用方传的是"整条内容矩形"时这样翻才对。**
  凡是调用方已经把矩形切成了槽位(`TTyCheckBox.RenderTo:302/308` 的 `TextRect`、
  `TTyListBox.PaintItemContent:1033` 的 padding 内缩矩形),矩形本身也得翻,
  否则文字会靠到一条已经算错的边上。所以这一条是**必要不充分** —— 它解决"文字贴错边",
  不解决"槽位在错边"。

  ⚠️ `source/tyControls.Painter.pas` 正在被另一条线改(BiDi)。**上面的行号会漂。**
  接手时按符号名重新定位,别按行号打补丁。

### 2.2 ❌ 假收口点一:`AdjustClientRect` / `GetClientRect`

全库只有 9 个覆写:`Card:89`、`Empty:119`、`ExPanel:77`、`Form:98/314`、`GridPanel:48`、
`GroupBox:21`、`Panel:35`、`Ribbon:97/207`、`TabStrip:136`,加 `ScrollBox:72/92`。
逐个读过:**它们全部是对称内缩**。举两例:

- `TTyGroupBox.AdjustClientRect`(`GroupBox.pas:63-82`):`Inc(Left, Padding.Left)` /
  `Dec(Right, Padding.Right)`,上边多扣一条标题带。左右两侧扣的是各自的 padding —— 镜像时
  唯一要做的是把 `Padding.Left`/`Padding.Right` 对调,**而这只有在主题给了非对称 padding
  时才看得出差别**。
- `TTyPanel.AdjustClientRect`(`Panel.pas:35`):`BorderWidth` 四边同值。

**唯一的例外**是 `TTyScrollBox.GetClientRect`(`ScrollBox.pas:565-574`):
`Dec(Result.Right, FVScrollBar.Width)`(`:569`)—— 这一句把"竖滚动条在右边"写死在了客户区语义里。
它是真的要改(见 §3.13),但它是**一个控件的一句**,不是一类控件的杠杆。

### 2.3 ❌ 假收口点二:`TTyStyleSet.Padding`

`TTyStyleSet.Padding: TRect`(`Types.pas:83`)是四向的,理论上"翻一次 padding 就全库镜像"。
实际不成立:**没有任何共享函数消费它。** 每个控件在自己的 `RenderTo` 里手写内缩,
`Padding.Left` 在 `source/` 出现 114 次。翻 padding 只能在
`TTyStyleModel.ResolveStyle` 出口处做(`Base.pas:607`/`:1489` 两个 `CurrentStyle` 入口),
但那会**连带翻掉主题作者故意写的非对称 padding**,而且对"槽位在哪一侧"毫无作用。
不建议。

### 2.4 ❌ 诱人但错误的捷径:在 `EndPaint` 里水平翻转位图

每个控件都画进 `FBmp` 再在 `TTyPainter.EndPaint` 一次性
`FBmp.Draw(FCanvas, FRect.Left, FRect.Top, ...)`。在 `Draw` 之前对 `FBmp` 做一次
水平翻转,**整个界面的 chrome 一行代码就镜像了**。
不要做。两个致命问题:(1) 文字会跟着翻成镜像字;(2) 命中测试一动不动 ——
这正是本项目反复栽过的"画在右边、点在左边"。写在这里是因为它足够诱人,
值得先否掉。

### 2.5 ✅ 半个收口点:三个纯几何单元

`tyControls.Grid.Layout.pas`、`tyControls.ListView.Layout.pas`、以及
`tyControls.HeaderControl.pas` 的 `TyHeaderSection*` 三件套,是全库**唯一**把
"矩形函数"和"命中函数"机械绑死的地方 —— 命中函数直接调矩形函数取逆
(`ListView.Layout.pas:530-534`、`HeaderControl.pas:298`)。
**在这三处加 `RightToLeft` 参数,绘制与命中不可能分叉。** 这是应该被推广的形状,
不是应该被绕过的形状。

---

## 3. 逐族清单

每条固定四问:**几何在哪 / 命中在哪 / 桶 / 还牵动什么**。

---

### 3.1 `TTyEdit` / `TTyMemo` / `TTyMaskEdit` —— **(b) 有边界**

**几何**:`TTyEdit.TextStartX`(`Edit.pas:875`)= `Padding.Left`;
`TTyEdit.AlignOffset`(`:884`)按 `FAlignment` 把富余量推到右/中;
`TTyEdit.CaretPixelXAt`(`:1196`)= `TextStartX + Widths[i]`。
`TTyMemo` 同构:`RowAlignOffset`(`Memo.pas:1449`)按行算对齐偏移。
`TTyMaskEdit` 是 `class(TTyEdit)`(`MaskEdit.pas:56`),几何全部继承。

**命中**:`TTyEdit.CaretIndexAtX`(`:1148`)。
**和绘制共用同一组三件套** —— `RelX := AX - StartX - AlignOffset(APPI) + FScrollX`
(`:1161`),再在同一份 `MeasureCodepointWidths` 上走码点边界。
`TTyMemo` 有显式的 `CaretToVisual` / `VisualToCaret` 互逆对(`Memo.pas:403`/`:408`)。
**这一族是"一个来源"的正面例子。**

**为什么是 (b) 而不是 (a)**:纯镜像本身确实只要
`FAlignment` 过一次 `BidiFlipAlignment` —— 但右侧还有一段被写死的保留区
`RightReserve(APPI)`,而 `StartX + RightPad` 这段视口算式在
`AlignOffset:895`、`ClampScrollX:1019`、`EnsureCaretVisible:1041` **写了三份**。
那是 SpinEdit/ComboEdit 的按钮列;`TTyDateTimePicker` 的同类按钮由
`TyDateTimeButtonRect`(`DateTimePicker.pas:1009`)钉在
`X0 := ALocal.Right - BtnW`(`:1014`)。这些槽位要一起翻,不然按钮压在文字上。

**还牵动**:`FScrollX` 的原点(`Edit.pas:19` 注释写着 ">= 0",RTL 下溢出文本要
右钉左滚);`Home`/`End` 不变(它们是逻辑首尾,不是视觉首尾);
`VK_LEFT`/`VK_RIGHT` **不该翻** —— 在 BiDi 文本里方向键是**视觉移动**,
应该由 BiDi 层决定,不是镜像层。

⚠️ **与 BiDi 线的唯一硬交界**:`MeasureCodepointWidths`(`Edit.pas:948`)返回的是
**逻辑序前缀和**,`CaretPixelXAt` / `CaretIndexAtX` 全部建在它上面。
BiDi 一旦落地,视觉序 ≠ 逻辑序,**这个前缀和模型就失效了**,和镜像无关。
两条线必须在这一点上碰头,否则会出现"混排文本里点击落到另一个词"的经典 bug。

---

### 3.2 `TTyLabel` / `TTyDivider` —— **(a) 几行**

**几何**:`TTyLabel.RenderTo`(`TyLabel.pas:347`),内容矩形四向内缩(`:374-377`),
文字交给 `P.DrawText(..., FAlignment, ...)`(`:412`)。
`TTyDivider` 更好:`TyDividerLayout`(`Divider.pas:53` 声明 / `:109` 实现)是
**纯函数**,吃 `AAlign` 和 `ALeftIndent`,吐出 `CaptionRect` + 两段横线。

**命中**:两者都没有内部命中 —— `TTyLabel.Click`(`:199`)整块可点,`TTyDivider` 不可交互。
**没有分叉的可能。**

**桶理由**:`TTyLabel` 只要 §2.1 那一行就够(它的 `DrawText` 传的是整条内容矩形)。
`TTyDivider` 要在 `TyDividerLayout` 里翻 `AAlign` 与 `ALeftIndent` 的方向 ——
一个纯函数、一个参数。

**还牵动**:`TTyDivider.LeftIndent`(`Divider.pas:93`)在 RTL 下语义是"从右缩进",
属性名会骗人。**建议保持属性名不变、只翻行为**,并在文档里说一句 —— 改名是破坏性变更,
不值得为这一条付。

---

### 3.3 `TTyCheckBox` / `TTyRadioButton` / `TTyGroupBox` / `TTyCheckGroup` / `TTyRadioGroup` —— **(a) 几行**

**这一族是最便宜的,因为开关已经装好了。**

**几何**:`TTyCheckBox.RenderTo`(`CheckBox.pas:243`)已经有一个完整的左右分支:
`FAlignment = taLeftJustify` → 指示器画在 `ContentRect.Right - BoxSize`(`:288`),
否则画在 `ContentRect.Left`(`:290`);文字矩形与文字对齐同步在 `:300-310` 翻。
`TTyRadioButton` 是同一段的孪生(`:546-620`)。
源码注释自己写着:"only the two X coordinates branch"(`:286`)。
**RTL 要的一切,这个控件已经能做了 —— 缺的只是把 `IsRightToLeft` 接到 `FAlignment` 上。**

**命中**:**没有内部命中**。`TTyCheckBox.Click`(`:218`)整块响应,没有 `PtInRect`。
绘制与命中不可能分叉。

`TTyCheckGroup` / `TTyRadioGroup` 更好:它们由**真的子控件**组成
(`CheckGroup.pas:329 LayoutCheckBoxes`、`RadioGroup.pas:336 LayoutButtons`),
位置由纯函数 `TyCheckGroupCellRect`(`CheckGroup.pas:143`)/
`TyRadioGroupCellRect`(`RadioGroup.pas:134`)给出。
**命中完全不存在** —— 每个子控件自己处理自己的点击。
镜像 = 在纯函数里 `col := cols - 1 - col`(接在 `CheckGroup.pas:161` 与 `:166` 两条
`col :=` 之后,喂给 `:173-177` 的 `l`/`r` 计算),
子控件的指示器则靠 LCL 的 `BiDiMode` 父子传播自动翻(§1.1)。

`TTyGroupBox`:`AdjustClientRect`(`GroupBox.pas:63`)对称,只有标题的 `FAlignment`
(`:32`)要翻 —— §2.1 那一行覆盖。注意 `GroupBox.Alignment` 是 `TAlignment`(标题位置),
`CheckBox.Alignment` 是 `TLeftRight`(指示器边),源码在 `GroupBox.pas:29-31` 已经把
"同名不同义、别去统一"记下来了 —— **镜像时也别去统一**。

**还牵动**:`TTyRadioGroup.MoveSelection(AHorzDiff, AVertDiff)`(`RadioGroup.pas:466`)
—— RTL 下 `AHorzDiff` 要取反,否则左箭头往后走。这是**一行**,也是这一族里唯一的键盘改动。

---

### 3.4 `TTyButton` 及其后代 —— **(a) 几行**

**几何**:`TTyButton.RenderTo`(`Button.pas:581`)算出 `ContentRect`(`:616-619`),
交给 `DrawContent`(`:750`),后者只做一件事:
`APainter.DrawText(AContentRect, disp, ..., FAlignment, tlCenter, ...)`(`:759`)。
徽标 `DrawBadge`(`:407`)按 `FBadgePosition` 定角。

**命中**:**没有内部命中**。整块按钮一个点击面。

**桶理由**:`FAlignment`(`:177`,`default taCenter`)—— 默认居中,`BidiFlipAlignment`
对 `taCenter` 是恒等。**绝大多数按钮 RTL 下零改动。**
只有显式设了左/右对齐的按钮受影响,而那正好被 §2.1 那一行覆盖。

**还牵动**:带图标的后代(`GlyphButtons.pas`、`DropButtons.pas`)有"图标在左、文字在右"
的槽位 —— LCL 自己为此备了 `BidiAdjustButtonLayout`(`buttons.pp:700`),
一张 `TButtonLayout` 查表,**照抄即可**。徽标角位(`TTyBadgePosition`)按定义应该跟着翻。

---

### 3.5 `TTyPanel` —— **(a) 几行**

**几何**:`RenderTo`(`Panel.pas:24` 声明)按 `FAlignment` / `FVerticalAlignment`
画自己的 Caption;`AdjustClientRect`(`:35`)对称内缩 `BorderWidth`。

**命中**:无。

**桶理由**:Caption 对齐被 §2.1 覆盖;容器内的子控件布局**不镜像**(§1.2 第 2 条,
LCL 自己也不镜像)。

**还牵动**:什么都不牵动 —— 这正是它便宜的原因。
`ChildSizing` 的表格路径 LCL 已经替我们做了 BiDi(`wincontrol.inc:1551`),
`TTyPanel` republish 了 `ChildSizing`,**这一份是白捡的**。

---

### 3.6 `TTyListBox` —— **(b) 有边界**

**几何**:`TTyListBox.ItemRect`(`ListBox.pas:1067`)返回
`Rect(0, rowTop, ClientWidth, rowTop + SH)`(`:1078`)—— **整宽行**。
行内文字在 `PaintItemContent`(`:1029`)里按 `Padding.Left/Right` 内缩(`:1033-1036`)、
写死 `taLeftJustify`(`:1041`)。多选勾选框另按 `BoxStyle.Padding.Left` 内缩(`:924`)。

**命中**:`RowAtY`(`:1165`)是 `ItemRect` 的逆(源码注释在 `:1075` 明说)。
**但 `MouseDown`(`:788`)和 `MouseMove`(`:845`)没有调 `RowAtY`,而是把同一个公式
`FTopIndex + ((Y - ContentTopOffset) div SH)` 抄了两遍。**
这是既有的、与 RTL 无关的重复,顺手值得收口 —— y 轴的重复不会被 RTL 触发,
但它证明这个控件里"抄一遍公式"是被允许的习惯,而 x 轴一旦引入分支就会中招。

**桶理由**:三处 x 常量要改(行文字对齐、勾选框边、滚动条边),外加一个真问题 ——
`FScrollBar.Align := alRight`(`:674`)。因为 LCL 的 `Align` 不认 BiDi(§1.2),
这里必须显式改成 `alLeft`;而 `ItemRect` 返回的行宽是 `ClientWidth`(含滚动条位置),
RTL 下行左端要让开滚动条,否则文字画到条底下。**行矩形的定义要跟着动。**

**还牵动**:横向滚动(`ScrollWidth`,审计里记为未实现)如果将来做,原点要跟着定在右侧。

---

### 3.7 `TTyListView` —— **(b) 有边界**

**几何**:`tyControls.ListView.Layout.pas` 是**纯几何单元**。
`TyListItemRect`(`:414`)是唯一的矩形出处:
report 模式 `Left := -AScrollX`(`:425`);图标/列表模式
`col := ADisplayPos mod Tracks`(`:443`)+ `Left := col * PitchX - AScrollX`(`:447`)
—— 典型的**下标↔位置算术**。
`TyListCheckRect`(`:457`)把勾选框钉在 `ACell.Left + APad`(`:471`)。
report 模式的列 x 走共享列模型 `TTyColumns`(见 §3.8)。

**命中**:`TyListItemAt`(`:483`)—— 先用逆算术猜 `col`(`:517`),
**再用 `TyListItemRect` 复核**(`:531-533`)。这是全库最好的形状:
猜错只会答 -1(死区),不会答错格。

**桶理由**:改动集中在一个单元、三个函数:`TyListItemRect` 的 `col` 翻转、
`TyListItemAt` 的逆算术翻转、`TyListCheckRect` 换边。加一个
`TTyListMetrics.RightToLeft` 字段(`ListView.Layout.pas:58` 起的记录)。
分组布局是**同一段算术的第二份拷贝** ——
`TyListGroupItemRect:1102`(`:1121` 的 `-AScrollX`、`:1134` 的 `col * PitchX`)与
`TyListGroupHitTest:1197`(`:1258` 的逆算术),两两对应,必须一起改。
**机械但真有量。**

**还牵动**:
- **键盘方向**:`TyListNavigate`(`:654`)里 `lnLeft: delta := -1`(`:714`),
  RTL 下必须 `+1` —— brief 点名的"Left 应该往前走"就是这一行。
  `ListView.pas:3813-3814` 把 `VK_LEFT/VK_RIGHT` 映射成 `lnLeft/lnRight`,
  翻转做在 `TyListNavigate` 里(纯函数、可无头测)比做在 KeyDown 里好。
- **列拖宽的符号**:`newW := FResizeStartW + UnscaleI(X - FResizeStartX)`
  (`ListView.pas:3672`)—— RTL 下向左拖是变宽,这个减法要取反。
  **这是最容易漏的一处**,因为它不在任何 `*Rect` 函数里。
- **框选**(`TyListMarqueeHits:750`)自动跟着 `TyListItemRect` 走,无需额外改。

> **2026-08-06 更新:report 模式的列轴现在是白送的。**
> 本控件的三个列命中调用(`ListView.pas:2158` 与 `:3469` 的 `DetermineSplitterIndex`、
> `:3488` 的 `ColumnFromPosition`)已改成收**设备像素 + 绘制端原点 + PPI**,
> 与 `RenderHeader`(`:2962`)、报表行(`:2779`)、网格竖线(`:3063`)传给 `Span()` 的
> 是同一组参数。所以 §3.9 说的那个 `TyColumnSpan.ARightToLeft` 一改,
> 本控件的列轴、拖宽命中、表头点击**一起跟上,不需要在本单元里加任何东西**。
> 桶仍是 (b),但 (b) 的内容只剩上面那三个 `TyList*` 函数与下面两条"还牵动"。

---

### 3.8 `TTyCustomGrid` / `TTyStringGrid` —— **(c) 重写(列轴)**

**几何(列轴)**:`TTyCustomGrid.ColumnLeftPx`(`Grid.pas:4969`)是列 x 的**唯一出处**,
`CellRect`(`:5034`)= 行轴(纯几何层 `TyGridRowRect`)× 列轴(`ColumnLeftPx`)。
**行轴部分完全没问题** —— `tyControls.Grid.Layout.pas` 是纯的、可无头测的、
`TyGridRowAt` 明写"必须恒为 `TyGridRowRect` 的逆"(`:163-169`)。

**命中**:`TTyCustomGrid.CellAt`(`Grid.pas:5326`)→ `ColumnAtX`(`:5007`)。
**`ColumnAtX` 是靠逐列调 `ColumnLeftPx`/`ColumnWidthPx` 取逆的**(`:5020-5021`),
源码注释明说"要紧的是它与绘制用的是同一个出处"(`:5012-5013`)。
**列轴的绘制/命中共用一个来源 —— 这一半是干净的。**

**那为什么是 (c)?** 因为**视口原点被钉死在 x=0**,而且冻结带/行头槽是**另外三处**
独立的左侧假设:

1. `ViewportW`(`:3657`)= `ClientWidth - FVScroll.Width` —— 只说宽度不说原点。
   竖滚动条在 `ClientWidth - sb`(`:3860`、`:3882`)。RTL 要把条挪到 x=0,
   于是视口变成 `[sb, ClientWidth)`,**所有 x 都要加一个非零原点** ——
   这正是 (c) 的定义。
2. `FrozenWidthPx`(`:3610`)把"行头槽 + 固定列"的厚度算在**左侧**,
   `ColumnAtX` 里的守卫 `if (i >= FFixedCols) and (AX < FrozenWidthPx) then Continue`
   (`:5024`)直接依赖它在左。
3. 行头槽在绘制端是 `Rect(0, r.Top, AIndicatorW - ..., r.Bottom)`(`:4707`),
   在命中端是 `if FShowIndicator and (AX < ScaleI(FIndicatorWidth))`(`:5361`),
   **另有两处同样的裸判断**(`:4530`、`:5545`)。**四处独立的 "x < indicatorW"。**
4. 纯几何层的 `TyGridPaneRect`(`Grid.Layout.pas:213`)按
   `FrozenLeft`/`FrozenRight` 切九宫格(`:229-233`)—— 镜像时这两个字段要对调,
   而"左带含行头槽"是写进注释的契约(`Grid.Layout.pas:63-68`),要一起改。
5. 右侧冻结列自己有一段"锚在视口右沿"的反向算法
   (`Grid.pas:4978-4988`,`Result := ViewportW` 在 `:4985`),
   镜像后它变成锚左沿,和第 1 条冲突。

**判据:如果只做"列从右往左排",改 `ColumnLeftPx` 一处就够;
但滚动条不挪到左边的 RTL 网格是半成品,而挪滚动条就要动视口原点,
一动原点上面五处全部跟着动。** 这就是它落在 (c) 的原因。

**还牵动**:`VK_LEFT: MoveCursor(FCol - 1, FRow)`(`:8062`)要取反;
`GetLeftCol`/`SetLeftCol`(`:5092`/`:5110`)的语义变成"最右列";
`SetScrollX` 的方向;`TTyStringGrid.CellRect` 覆写(`:11328`)只是转发,无额外成本。

---

### 3.9 `TTyTreeView` —— **(b) 有边界**(2026-08-06 由 (c) 降级)

> **本节已重写。** 原判 **(c)** 的唯一理由是"四到五份手抄的 x 累加链",
> 并建议"先合并成一个纯函数 `TyTreeSlotLayout`,做完之后 RTL 就是 (a)"。
> **那次重构做完了**:`bee3308` 把五份累加收成 `TyTreeCaptionSlots`;
> 随后一轮(本节的来源)又把命中端的**锚点**和**坐标空间**与绘制端对齐 ——
> 那两处不一致各自是一个真 bug(主列不在最左时点箭头不展开;PPI≠96 时列边界差一格),
> 都已修复并有守卫。**债已还清,所以桶变了。**

**几何**:两个纯函数,都是 §3.10 夸的那个形状。
- `TyColumnSpan(ALogicalLeft, ALogicalWidth, AOriginX, APPI)`(`Columns.pas:364`)——
  列的横向跨度,从**原点**向右平铺;`TTyColumn.Span`(`:379`)是薄壳。
- `TyTreeCaptionSlots(ACellLeft, APPI, AIndent, ALevel, ...)`(`TreeView.pas:989`)——
  单元格内 缩进→展开→复选→图标→标题 逐槽向右走,一次算完填进记录;
  `NodeCaptionSlots`(`:3497`)是薄壳,负责补上两个 per-node 答案。

**命中**:`GetNodeAtPoint`(`:4809`)、`GetHeaderHitAt`(`:4923`)、
拖列的 `MouseMove`(`:5331`)**全部调用**上面两个 ——
而且现在传的是与绘制端**逐字相同**的参数:同一个原点、同一个 PPI、同一个锚点
(`MainCellAnchor:3516`,它自己取自绘制端的 `InternalCellRect:3537`)。
**三个消费者、一个来源,机械上不可能分叉** —— §3.10 的判据,树现在也满足。

**桶理由**:分成两条轴看。
- **列轴 = (a) 几行**:给 `TyColumnSpan` 加一个 `ARightToLeft`,
  把"从 `AOriginX` 向右平铺"改成绕客户区宽度反射。**一个纯函数、一个参数**;
  `ColumnFromPosition`(`Columns.pas:802`)、`DetermineSplitterIndex`(`:844`)、
  表头、拖列浮标、`GetCellRect` 自动跟上,因为它们收的就是同一组 `(origin, PPI)`。
  **且这一条与 §3.8 / §3.10 同源,一次改三处。**
  > **先决已经完成**:反射要算 `clientWidth - x`。命中在逻辑像素、绘制在设备像素时,
  > 这个 `clientWidth` 两边不是同一个量,反射没有唯一含义 —— 那时那一格舍入偏差
  > 在镜像后会放大成"整列错位"。现在两边同空间,`ARightToLeft` 才是可写的。
- **槽位轴 = (b) 有边界**:`TyTreeCaptionSlots` 要能从单元格**右**缘向左平铺
  (缩进往左长,展开→复选→图标→标题依次左移)。改动集中在一个纯函数里,
  但记录的 `ButtonSlotX` / `CheckX` / `ImageX` / `CaptionX` 现在语义是"左边",
  五个消费者都按左边读;**要么记录加方向位,要么这四个字段改成"前缘"** —— 这就是那条边界。
  `MainCellAnchor` 与 `absX < mainX → hpLabel` 的分区规则(`:4857`)同向翻转:
  RTL 下非主列正文在主列**右**边。

**还牵动**(都不在任何 `*Rect` 函数里 —— 按经验这才是会漏的部分):
1. **树线是本族最后一份手写 x 累加**:`ancSlotX` / `ancMidX`(`:4154`、`:4162`,
   以及 0 列孪生分支 `:4424`、`:4434`)按**祖先**层级重算缩进,
   而槽位记录只覆盖本节点这一层。要么手工镜像,要么先并进记录。
2. **`VK_RIGHT` 展开 / `VK_LEFT` 收起**(`:5610`、`:5631`):
   按 §6.3 第 4 条的判据 —— 这一下按键移动的是**节点**(槽位之间)而不是光标(字符之间),
   属于**布局方向,要翻**。
3. **拖宽符号**:`newWidth := FResizeStartWidth + MulDiv(X - FResizeStartX, 96, PPI)`(`:5292`),
   与 §3.7 的 `ListView.pas:3682` 同类 —— RTL 下向左拖是变宽。
4. **`TTyColumn.Left` 不能动**(`Columns.pas:104`,public,宿主在读):
   镜像必须做进 `TyColumnSpan`,不能做进 `UpdatePositions`。
5. `FRangeX` / `FOffsetX` 的横向滚动原点移到右缘。

---

### 3.10 `TTyHeaderControl` —— **(a) 几行 · 全库最佳形态**

**几何**:`TyHeaderSectionRects`(`HeaderControl.pas:257`)—— **纯函数**,
从 `AClient.Left` 往右平铺(`:279`),最后一节吸收余量。

**命中**:`TyHeaderSectionAtX`(`:292`)和 `TyHeaderResizeEdgeAtX`(`:309`)
**都以调用 `TyHeaderSectionRects` 开始**(`:298`、`:316`)。
绘制端 `RenderTo`(`:666`)在 `:696` 调的也是它。
**三个消费者,一个来源,机械上不可能分叉。**

**桶理由**:给 `TyHeaderSectionRects` 加一个 `ARightToLeft: Boolean`,
把 `x := AClient.Left` 起的正向平铺改成从 `AClient.Right` 起的反向平铺 ——
**一个纯函数、一个参数,命中和拖宽自动跟上**。
排序三角形 `TyHeaderSortTriangle`(`:249` 声明)当前钉在单元格右侧,换边即可。

**还牵动**:拖宽的位移符号 —— `MouseMove` 里的 `X - FResizeStartX`(`:815`),和 §3.7 同类问题;
各节文字对齐由 §2.1 覆盖。

---

### 3.11 `TTyPageControl` / `TTyTabSheet` / `TTyCustomTabStrip` —— **(b) 有边界**

**几何**:`TTyCustomTabStrip.RebuildLayout`(`TabStrip.pas:468`)是**唯一的布局构建者**,
一次性填满 `FHeaderRects[]` / `FCloseRects[]`(`:504`、`:509`),`X := 0` 起逐个右移(`:491`、`:515`)。
溢出箭头 `FScrollLeftRect := Rect(0,0,ArrowW,TabH)` / `FScrollRightRect`(`:527-528`)。
内容区偏移在 `HeaderShiftPx`(`:625` 声明 / `:629` 实现)一处。

**命中**:`IndexOfTabAt`(`:705`)读的就是 `FHeaderRects[]`,用同一个 `HeaderShiftPx` 平移
(`:726-727`)。**一份缓存数组,两边共用。**

**桶理由**:要改的是 `RebuildLayout` 里的排布方向、关闭槽换边(`:509`)、
两个箭头矩形对调(`:527-528`)、`HeaderShiftPx` 的原点(`:629` 现在是
`FScrollLeftRect.Right - FHeaderScroll + HeaderLeftInset`,RTL 下起点在右)。
几个函数、一个单元。

**还牵动**:
- **拖拽重排的中点规则**:`TyDropIndexAt`(`:768`)"从左往右扫,返回第一个中点在 X 右侧的下标"
  (`:775` 的默认值 + `:781` 的 `Mid` + `:782` 的 `if X < Mid`)—— RTL 下扫描方向和比较符号都要翻。**brief 点名的中点规则就是这里。**
- `VK_LEFT`/`VK_RIGHT` 切页(`:1344`、`:1350`)取反。
- ~~`AdjustClientRect`(`:803`)只扣顶部标签带,**与镜像无关** —— `TabPosition` 目前只有顶边
  (审计已记为缺口),所以没有"标签在左/右边"的分支要一起翻。这一点省了不少事。~~
  **(2026-08-06 作废:`TabPosition` 已落地。)** 现在扣的是**镜像之后**那条边:
  `tpLeft` 在右到左下扣的是右边。规则收在一个 `InsetForBand` 里,`AdjustClientRect` 与
  `DisplayRect` 共用,两者不可能各说各话。理由见 §6.3 第 7 条。
- `TTyPageControl`(`PageControl.pas`)本身不含几何,全部转发给基类;
  `TTyTabSheet` 是普通容器,子控件布局不镜像(§1.2)。**这两个零成本。**

---

### 3.12 `TTyPopupMenu` / `TTyMenuBar` —— **(a)+(b)**

**`TTyMenuBar`:(a) 几行。**
几何:`TopLeft(AIndex, APPI)`(`Menu.pas:2081`)—— **唯一出处**,而且它**已经有一条反向分支**:
右对齐的顶级项从 `Width - Padding.Right` 往左减(`:2087-2095`)。
**RTL 要的公式,这个控件已经写过一遍了。**
命中:`TopAtX`(`:2103`)逐项调 `TopLeft` 取逆(`:2110`)。绘制:`RenderTo`(`:2360`)在
`:2378` 调同一个。**一个来源,三个消费者。** 改 `TopLeft` 一处即可。

**`TTyPopupMenu`(即 `TTyMenuView` + `TTyMenuPopup`):(b) 有边界。**
几何:`TTyMenuView.RenderTo`(`:1206`)—— 左槽 `LeftSlotWidth`(`:846`,勾选/图标)、
右槽 `--menu-arrow-slot`(`:1262`,子菜单箭头 + 快捷键),中间是标题。
命中:`RowAtY`(`:978`)**只做 y 轴** —— 行内 x 没有任何命中判定
(`MouseUp:1100` 只用 y)。**所以行内槽位换边不会造成绘制/命中分叉,这是好消息。**
真正要改的是**弹出方向**:`ComputeBounds`(`:1542`)里
下拉菜单 `L := AAnchor.Left`(`:1566`)在 RTL 下应为 `AAnchor.Right - AWidth`;
子菜单 `L := AAnchor.Right`(`:1559`)应改为向左展开并在越界时翻右。

**还牵动**:`VK_LEFT`/`VK_RIGHT`(`:1144`、`:1155`)是"进入子菜单 / 返回父菜单",
RTL 下必须对调 —— **这是语义级对调,漏了会让 RTL 用户完全无法用键盘打开子菜单。**
装饰性左侧色带 `bannerPx`(`:1246`)要换边。

---

### 3.13 `TTyScrollBar` / `TTyScrollBox` —— **(b) 有边界**

**`TTyScrollBar`**:几何全在三个**纯函数**里 ——
`TyScrollThumbRect`(`ScrollBar.pas:134`)、`TyScrollButtonSize`(`:173`)、
`TyScrollTrackRect`(`:182`)。横向分支里 `Rect(ATrack.Left + Offset, ...)`(`:169`)
是唯一要翻的算术;`TyScrollTrackRect` 的两端按钮(`:197-198`)对调。
命中:`PosAlong(X, Y)`(`:679`)横向答 `X` —— 翻成 `TrackRect.Right - X` 一行。
**横向滚动条在 RTL 下原点在右**(位置增大 = 视觉左移),这是 Windows 的既定行为。
竖条完全不受影响。

**`TTyScrollBox`**:四处钉死"竖条在右":
`GetClientRect` 的 `Dec(Result.Right, FVScrollBar.Width)`(`:569`)、
`MeasureAndDock` 里的 `FVScrollBar.SetBounds(Width - thick - bw, ...)`(`:495`)、
`FContent.SetBounds(bw, bw, viewW, viewH)`(`:536`,RTL 下左边要让开条宽)、
以及 `:707` 的第二处 dock。
`AdjustClientRect` 的 `OffsetRect(ARect, -FScrollX, -FScrollY)`(`:623`)是滚动原点 ——
RTL 下横向偏移方向相反。

**桶理由**:四五处坐标 + 一个纯函数的横向分支 + 一个原点符号。机械,但不是三行。

**还牵动**:`ScrollInView`(`:359`)的边界判断;
**注意 `AdjustClientRect` / `GetLogicalClientRect` / 滚动原点这"三个钩子"的契约**
(`ScrollBox.pas:20-25` 与 `:581-604` 的长注释)—— 记忆里已经有一条
"滚动容器的三个布局钩子",镜像时三处必须同步,只改一处会出现"每滚一次少 12px"那类症状。
**子控件在盒内的布局不镜像**(§1.2)。

---

### 3.14 `TTyStatusBar` / `TTyCoolBar` / `TTyControlBar` —— **(b) 有边界**

**`TTyStatusBar`**:几何 = `TyStatusPanelRects`(`StatusBar.pas:144`)**纯函数**,
`x := APadding` 起往右铺(`:157`),最后一格拉到右缘(`:165-166`)。
命中:`MouseDown`(`:379`)本身不按格分派;`:278` 与 `:322` 两处各自调
`TyStatusPanelRects` 求同一批矩形(一处给提示、一处给绘制)—— **同一个纯函数,不分叉**。
唯一的方向硬编码是 size grip:绘制在右下(`:345-354`,`gx := W - P.Scale(3) - ...` 在 `:350`),
命中在另一个函数 `ResizeHitAt`(`:361`)里:
`if FSizeGrip and (X >= W - grip) and (Y >= H - grip)`(`:369`)——
**这两处是分开写的,镜像时必须同时改**;而且 RTL 下抓手应在左下,
`TyStartNativeResize` 的边码要从 `cHTBOTTOMRIGHT` 换成 `cHTBOTTOMLEFT`(`:52`)。

**`TTyControlBar` / `TTyCoolBar`**:几何 = `TyControlBarPack`(`ControlBar.pas:110`)
**纯函数**,`contentLeft := AGripperW`(`:124`)—— 抓手占左侧、内容从其右开始。
`PaintGrippers`(`:221`)在 `Rect(0, bandTop, AGripperW, ...)`(`:229`)画。
`TTyCoolBar.BandRectFor`(`CoolBar.pas:585`)从 `ACtl.BoundsRect` 反推抓手条
(`Result.Right := Result.Left` / `Dec(Result.Left, gw)`,`:610-611`),命中 `BandAtPoint`(`:785`)直接
`PtInRect(BandRectFor(...))`。**一个来源,链式派生。**

**桶理由**:`TyControlBarPack` 的方向(`:124` 的 `contentLeft`、`:144-148` 的 `Result[I]` 赋值)+ `PaintGrippers` 的抓手边(`:229`)
+ `BandRectFor` 的 `Dec(Result.Left, gw)`→`Inc(Result.Right, gw)`(`CoolBar.pas:610-611`),三处;status bar 另加 grip 的两处 + 一个边码。

**还牵动**:band 的换行规则(`ControlBar.pas:135-141` 的 wrap,判据是 `x + w > contentLeft + usable`)在镜像后是"从右往左填,
溢出换行" —— 换行判断的比较符号要翻。

---

### 3.15 `TTyDateTimePicker` —— ~~(c) 重写(命中面)~~ → **(b) 有边界** → **已做(2026-08-06)**

> **本节的行号在写下时就已经过期一轮,现在整节都是历史了。** 下面第一段保留原始诊断
> (行号按当时的文件,与今天差 ~500 行,`CheckBoxRect` 这个函数已经不存在),
> 因为它记录的是**为什么**这一条曾经贵;之后是收口与镜像的结果。

**当初的诊断**:`RenderTo`(`DateTimePicker.pas:1633`)算文本矩形 → `TextOriginX`(`:1178`)
按 `FAlignment` 定起点 → 逐段用 `MeasureCharX`(`:1202`)量到第 n 个字符的宽度。
按钮列 `TyDateTimeButtonRect`(`:1009`)钉死 `X0 := ALocal.Right - BtnW`(`:1014`);
勾选框 `CheckBoxRect`(`:1443`)在文本矩形左侧。命中面 `MouseDown`(`:1322`)的注释直接写着
"Recompute text rect exactly as in RenderTo (without scale rounding diff)",然后手抄了
一遍文本矩形、又手抄了一遍文字左偏移。**这就是"点年份选到月份"那个 bug 的机制:
同一个矩形算了两遍,一遍带舍入差、一遍不带。** 四组槽位、绘制与命中各一份表达式,
加方向标志等于在八处各插一遍,而且没有任何测试能保证八处一致 —— 它们本来就不一致。

**收口已经发生了**,而且和本文的预测一样,是独立于 RTL 做掉的:
`TyDateTimeRects` 现在是**一个纯函数**,一次返回文本框、勾选框、按钮与上下半区;
`FieldLayout` 把它和显示串、文本原点接在一起;`RenderTo` / `MouseDown` /
`CalculatePreferredSize` 全部只读它。`FieldLayout` / `SegmentSpanX` / `SegmentAtX`
是三个接缝。**桶因此从 (c) 落到 (b)** —— 与 §3.9 的 TreeView 完全同型。

**镜像本身(2026-08-06 完成)**:成品记录在 `TyDateTimeRects` 末尾**做一次
`BidiFlipRect`**,不是每组槽位各加一个方向分支 —— 与 `TyCaptionLayoutFor`、
`TyStatusPanelRects` 同一个杠杆。绘制与命中读同一条记录,所以"镜像了绘制、
没镜像命中"在结构上不可表达。没画出来的部件(`dmNone` 的按钮、没开的勾选框)不参与反射。
`TextOriginX` 走 `BidiFlipAlignment`,溢出钳位也跟着换边(把**阅读起点**留在框内);
`RenderTo` 给 `BeginPaint` 上方向标志;弹出日历经 `TyPopupRect` 新增的
`ARightToLeft` 贴锚点右缘。段间 `VK_LEFT`/`VK_RIGHT` 按 §6.3 第 4 条取反,
`Home`/`End` 不动。

**留下的边界**:段位置是按**前缀宽度**量的,量不出 painter 的双向重排。
所以格式串里出现右到左字面量/月份名时,高亮与命中**彼此一致**(同源)但都不跟随重排后的
字形。这与镜像无关、镜像前后一样,记在 `docs/rtl.md`。

**守卫**:`tests/test.rtl.pas` 的 `TRtlDateTimePickerTest`。其中
`TheGlyphsLandWhereTheOriginSaysTheyWill` 是唯一够到**字形**的一条 ——
文本路径上有两个独立的翻转(`TextOriginX` 管高亮与命中,`TTyPainter.DrawText` 管字形),
只翻一个的话本文件其余断言全绿而字串画在框的一端、选在另一端。

---

## 4. 桶分布汇总

| # | 控件族 | 桶 | 一句话理由 |
|---|---|---|---|
| 1 | Edit / Memo / MaskEdit | **b** | 绘制与命中共用三件套;右侧保留区与滚动原点要一起翻 |
| 2 | Label / Divider | **a** | 纯函数 + 无命中 |
| 3 | CheckBox / RadioButton / GroupBox / CheckGroup / RadioGroup | **a** | 左右分支**已经存在**;组由真子控件组成,无命中 |
| 4 | Button 全族 | **a** | 默认居中,无内部命中;图标布局照抄 LCL 查表 |
| 5 | Panel | **a** | 只有 Caption;子控件布局不镜像 |
| 6 | ListBox | **b** | 三处 x 常量 + 滚动条 `alRight` + 行矩形定义 |
| 7 | ListView | **b** | 纯几何单元里三个函数 + 拖宽符号 + 方向键 |
| 8 | CustomGrid / StringGrid | **c** | 视口原点钉在 x=0;行头槽有四处独立判断 |
| 9 | TreeView | ~~c~~ → **b** | 五份累加已收成一个纯函数(`bee3308`),锚点与坐标空间也已对齐;列轴变 (a),只剩槽位记录的"左边→前缘"和树线那一份手写累加 |
| 10 | HeaderControl | **a** | 一个纯函数,三个消费者全部取逆于它 |
| 11 | PageControl / TabSheet / TabStrip | **b** | 一份缓存布局 + 箭头/关闭槽换边 + 中点规则 |
| 12 | PopupMenu / MenuBar | **b**(Bar 是 **a**) | Bar 已有反向分支;Popup 行内 x 无命中,只需换边 + 弹出方向 |
| 13 | ScrollBar / ScrollBox | **b** | 三个纯函数的横向分支 + 四处 dock 坐标 + 原点符号 |
| 14 | StatusBar / CoolBar / ControlBar | **b** | 纯打包函数 + 抓手边;size grip 绘制与命中分写两处 |
| 15 | DateTimePicker | ~~c~~ → **b** | 四组槽位已收成一个纯函数(`TyDateTimeRects`),绘制/命中/宽度查询全读它;镜像是成品上的一次反射 |

**原合计:(a) 5 · (b) 7 · (c) 3。2026-08-06 起:(a) 5 · (b) 9 · (c) 1** ——
TreeView(§3.9)与 DateTimePicker(§3.15)都因为各自的收口从 (c) 落到了 (b),
只剩 CustomGrid/StringGrid 一个 (c)。

**改变决策形状的一点**:三个 (c) 里,**没有一个是因为"RTL 难"**。
它们贵是因为各自欠一次"绘制/命中收口"的重构 ——
`TyTreeSlotLayout`、`TTyDateTimePicker` 的 x 分区、`TTyCustomGrid` 的视口原点。
**这三次重构即使永远不做 RTL 也该做**(TreeView 与 DateTimePicker 都已经因此出过 bug)。
如果把它们记在各自的账上,**RTL 程序本身就变成 5 个 (a) + 7 个 (b) + 3 个 (b)** ——
量级完全不同。这一条应该直接影响"做不做"的判断。

> **这个预测已经兑现了两次(都在 2026-08-06)。** TreeView 的那次收口(`bee3308`)
> 独立于 RTL 做掉了,顺带**露出**了两个真 bug —— 主列不在最左时点箭头不展开、
> PPI≠96 时列边界差一格 —— 修完之后 TreeView 直接从 (c) 落到 (b)(§3.9)。
> DateTimePicker 走了完全一样的路:`TyDateTimeRects` 那次收口修掉的正是本文点名的
> "点年份选到月份",做完之后它也落到 (b),镜像本身随后只是成品上的一次反射(§3.15)。
> 也就是说:**这三笔重构的收益是先于 RTL 兑现的**,
> 而"是否要做 RTL"的答案不必等它们做完才给。三个 (c) 现在只剩一个。

---

## 5. 半做会静默坏掉什么(按"多难发现"排,最难在前)

1. **命中偏移了半个槽,但没偏出格。**
   最难发现。用户点"月",选中了"月",但点在月和日的交界像素上选错。
   headless 测不出(要逐像素反查),真机上也只是"偶尔手滑"。
   高危点:`TTyDateTimePicker.MouseDown:1352`、`TTyTreeView.GetNodeAtPoint`(现 `:4809`)。
   **防线**:逐像素反查测试(纯几何单元已经有这种测试,`Grid.Layout.pas:163-169` 写了这条不变量)。

   > **这一条已经应验过一次,而且正是"没偏出格"的那个形状(2026-08-06)。**
   > `GetNodeAtPoint` 曾把列命中折算到逻辑像素再比,PPI≠96 时一列的最后一个设备像素
   > 会答成下一列;主列不在最左时展开箭头整整偏一列(那个偏出格了,所以点不动)。
   > 两者都是**先写守卫、看它红、再修**发现的。
   > 守卫在 `tests/test.treeview.columns.pas` 的 `TColumnX1Test` / `TColumnX2Test`
   > 与 `tests/test.listview.pas` 的 `TListViewHeaderDpiTest`,
   > 全部**断言在边界像素上,不在槽位中点** —— 中点断言对本条完全免疫,
   > 变异测试里"锚点 +1 像素"这个突变体只被边界断言杀掉。做镜像时照抄这个形状。

2. **只翻了绘制,没翻拖动的位移符号。**
   静态截图完全正确,一拖列宽就朝反方向变。
   `ListView.pas:3672`、`HeaderControl.pas:815`(`X - FResizeStartX`)、CoolBar 的 band 拉伸。
   **没有任何静态测试会红。**

3. **箭头键方向没翻。**
   界面镜像了、键盘没镜像。RTL 用户按左箭头往后走。
   `TyListNavigate:714`、`Grid.pas:8062`、`TabStrip.pas:1344/1350`、
   `Menu.pas:1144/1155`(子菜单进/出,最严重)、`RadioGroup.pas:466`。
   review 时几乎看不出来,因为每一处都只是一个 `-1`。

4. **滚动原点没跟着翻。**
   初始画面正确,一滚就错位、或滚到头还差一截。
   `ScrollBox.pas:623`、`Grid.pas` 的 `SetScrollX`、`TabStrip.pas:629`。
   症状常被误报成"滚动条坏了"。

5. **size grip / 拖拽抓手画在一边、响应在另一边。**
   `StatusBar.pas:345`(画)与 `:369`(命中)是分开写的两处。
   用户看到抓手在左下、鼠标在左下不变形状,去右下才能拉。**一眼可见,但只有 RTL 用户会碰到。**

6. **弹出菜单在屏幕边缘翻错方向。**
   `Menu.pas:1556-1569`(`ComputeBounds` 的两条 `L :=` 分支)。只在贴边时出现,平时正常。

7. **滚动条还在右边。** 最显眼,也最容易在第一次截图时被发现 —— **反而是最安全的漏项。**

**规律**:**越是纯几何的东西越安全**(有测试、有逆函数守着),
**越是"顺手写在 MouseDown 里的一个减号"越危险**。
这与本项目已有的教训一致 —— 命中面从来不是被"设计错"的,是被"没人看"的。

---

## 6. 建议顺序,以及明确不做的清单

### 6.1 先决:与 BiDi 线碰一次头

**~~必须先定的一件事~~ —— 2026-08-06 已做完,此条留作记录。**
`TTyEdit.MeasureCodepointWidths` 返回逻辑序前缀和,`CaretPixelXAt` 与 `CaretIndexAtX`
全部建在其上;BiDi 落地后视觉序 ≠ 逻辑序,**这个模型失效,与镜像无关**。
`TTyMemo` 的 `CaretToVisual`/`VisualToCaret` 同理(原文的 `Memo.pas:403`/`:408` 行号已过期)。

**结论**:光标 x ↔ 字符下标**由控件自己负责**,不走 painter。
`TTyPainter.TextCaretX`/`TextCharIndexAtX` 从控件里用不了 —— 它们在 `FBmp` 上排版,
而那个只在 `BeginPaint`/`EndPaint` 之间存在,光标却是从鼠标/按键/闪烁定时器里查的。
两个控件各自建 run 表并缓存,再用守卫钉住"答案必须与 painter 一致"(对 painter 能表达的下标)。
`TTyEdit` 在 `7fd44ec`、`TTyMemo` 在这一轮完成 —— memo 是**按视觉行**建表,不是按逻辑行。

### 6.2 顺序(最便宜且最显眼在前)

| 阶段 | 内容 | 为什么排这里 |
|---|---|---|
| **0** | `TTyPainter` 加 RTL 标志,`DrawTextLine` 一行 `BidiFlipAlignment` | **一行换 146 个调用点**。做完立刻能截一张"整个界面文字靠右"的图,是最好的进度证明 |
| **1** | 3.3 复选/单选/组 + 3.2 Label/Divider + 3.4 Button + 3.5 Panel | 五个 (a),开关本来就在。做完覆盖了一个典型表单的绝大部分可见面 |
| **2** | 3.10 HeaderControl | 唯一一个"纯函数加一个参数就结束"的复杂控件。同时它是 Grid/ListView/TreeView 的列头共同祖先形状,先做能验证 `TTyColumns` 的镜像方案 |
| **3** | 3.13 ScrollBar/ScrollBox + 3.6 ListBox | 滚动条挪到左边是 RTL 最强的视觉信号 |
| **4** | 3.11 Tab + 3.12 Menu + 3.14 Bars | 三组 (b),互不依赖,可并行 |
| **5** | 3.7 ListView | 纯几何单元,有逆函数守着,风险低但量大 |
| **6** | **拆项**:TreeView 三链合一、DateTimePicker x 分区抽取、Grid 视口原点 | **作为独立的收口重构立项,不记在 RTL 账上**。做完之后这三个各自降到 (b) |
| **7** | 3.8 / 3.9 / 3.15 的镜像本身 | 只有 6 做完才动 |

### 6.3 明确**不**镜像的清单(以及理由)

1. **容器内子控件的 `Align` / `Anchors` 布局。**
   LCL 自己不镜像(`wincontrol.inc` 里只有 `ChildSizing` 表格路径有 BiDi 分支,`:1551`)。
   我们镜像了就和所有原生容器行为分叉,移植过来的窗体会错位。
   **`ChildSizing` 的表格路径例外 —— 那个 LCL 已经替我们做了,白捡。**
2. **`BidiFlipAnchors`(`controls.pp:2933`)不调用。** 它有副作用(会写 `AnchorSide`),
   不是纯函数,放在绘制或布局路径上会累积状态。
3. **`Home` / `End` / `PageUp` / `PageDown` 不翻。** 它们是逻辑首尾,不是视觉首尾。
   `TyListNavigate:663-667` 的处理已经是对的。
4. **文本编辑里的 `VK_LEFT`/`VK_RIGHT` 不由镜像层翻。** 在 BiDi 文本中方向键是视觉移动,
   归 BiDi 层管;镜像层去翻会和它打架。
   **列表/网格/标签页/菜单里的方向键要翻**(那是布局方向,不是文本方向)—— 两者必须分清。

   **判据不是"这个控件能不能打字",是"这一下按键移动的是什么"。**
   移动**光标**(在字符之间走)= 文本方向,归 BiDi 层,不翻。
   移动**选中项 / 焦点格 / 当前字段**(在一组槽位之间走)= 布局方向,归镜像层,要翻。

   `TTyDateTimePicker` 是唯一一个两边都沾的:它能打字,但 `VK_LEFT`/`VK_RIGHT`
   在**字段之间**跳(年→月→日),不在字符之间跳 —— 所以它按**布局方向**处理,要翻。
   §3.15 结尾说"段间 `VK_LEFT`/`VK_RIGHT` 要取反"与本条**不矛盾**,这里把判据写明,
   免得下一个人读到两处对不上就自己挑一个。
   (2026-08-06 补:收口那一轮的 agent 读出这两节像是打架,报上来而没有自作主张 ——
   这段就是那次调和。)
5. **不在 `EndPaint` 里翻位图**(§2.4)。
6. **不改属性名**(`Divider.LeftIndent`、`Columns[].Left`、`FScrollLeftRect`)。
   语义在 RTL 下会骗人,但改名是破坏性变更,收益不抵成本 —— 在 `docs/` 里写清楚即可。
7. ~~**`TabPosition` 的左/右边标签不做。** 它目前根本不存在(审计已记为缺口),
   现在为一个还没有的功能预留镜像分支是浪费。~~
   **(2026-08-06 作废:`TabPosition` 已经做了。)** 当时的判断("功能不存在,不预留分支")
   是对的 —— 而它现在存在了,所以这一条的结论要换,判据不用换。
   实际落地时**一个镜像分支都没有加**:反射从"作用在内容矩形上、嵌入之前"挪到了
   "作用在屏幕矩形上、嵌入之后"。这一挪在 `tpTop` 下逐字节不变(嵌入是恒等映射),
   而对左/右条带自动变成"**换边**"——反射的是条带的**次轴**,于是 `tpLeft` 整条搬到右边、
   行内的关闭 ×/图标各自换端,而**上下顺序不动**、`↑/↓` 不对调。
   这正是本节第 3 条("`Home`/`End` 是逻辑首尾")的同一条判据:
   **横向反射不可能给一条竖着走的行程重新排序**。
   `AdjustClientRect` 因此也有了要翻的东西(页面体扣的是镜像**之后**那条边),
   §3.11 里"`AdjustClientRect` 与镜像无关、这一点省了不少事"随之作废。

### 6.4 如果决定**不做**

那就必须落实 `plans/2026-08-04-parity-remaining-programs.md:29-31` 里的第二条:
**在 `docs/` 里写明"本库不支持 RTL 镜像"**,并保留
`tests/test.parity.pas:1025 LyingPropertiesStayUnpublished` 这条守卫
(它现在钉着 `TTyPanel`/`TTyUpDown` 的 `BiDiMode` 不许 published)。
**目前"既没做也没写"是最差的状态,这一点没有变。**

不过本文给出了一个中间选项,值得单独考虑:
**只做 §6.2 的阶段 0 + 阶段 1**(一行 painter 改动 + 五组 (a) 控件)。
它不构成完整的 RTL 支持,但它让"表单类界面在 RTL 下文字与指示器都在对的一侧"成立,
且没有引入任何绘制/命中分叉的风险(这一批控件**全部没有内部命中**)。
如果要发一个"部分 RTL"的版本,这是唯一一条不会留下静默 bug 的切法。
