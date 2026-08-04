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

### 3.9 `TTyTreeView` —— **(c) 重写**

**这是最贵的一个,而且理由不是"树难",是"这里有三份手抄的 x 累加"。**

**几何**:`RenderTo` 的逐行循环里,
`indentPx := P.Scale((level + Ord(FShowRoot)) * FIndent)`(`TreeView.pas:3923`),
`btnSlotW`/`imgSlotW` 各一个 Indent 宽(`:3882-3883`),
之后靠 `Inc(captionX, ...)` 逐槽往右推。

**命中**:`GetNodeAtPoint`(`:4660`)—— **把同一串累加又写了一遍**
(`:4697-4699` 复制了三个 slot 宽,`:4702-4707` 的注释画出 x 分区表,
`:4732` 起用 `captionX := indentPx` + `Inc(captionX, ...)` 重走一遍)。
函数头的注释自己写着 "X-accumulation mirrors RenderTo EXACTLY"(`:4651`)。
`GetNodeAt`(`:6273`)只是它的转发壳。

**而且不止三份。** `Inc(captionX, imgSlotW)` 这一句在文件里出现**四次**:
`:4167`(多列绘制分支)、`:4452`(单列绘制分支 —— 注释里说的 "the 0-column twin")、
`:4755` 与 `:4779`(命中的两条分支)。
第五份是 `CellTextRect`(`:6007`),内联编辑器的定位,文件注释写着
**"KEEP IN SYNC WITH RenderTo's main-column caption layout ...
and GetNodeAtPoint's x-zones"**(`:5998-6000`),并逐条列出四个槽宽。

**桶理由**:一个方向标志要在**四五份手抄的累加链**里各插一遍,
而"缩进往左长"意味着累加要从 `CR.Right` 开始递减 —— 每条链的每一步都要重写。
**任何漏掉一条分支的补丁都会让树画在右边、答在左边。**

**唯一负责任的做法**:先把三份合并成一个纯函数
(`TyTreeSlotLayout(level, flags, ...) : record Indent, Button, Check, Image, Text: TRect end`),
让三个调用方都吃它 —— **这次重构本身就值得做,与 RTL 无关**;
做完之后 RTL 是 (a)。**建议把这一条从 RTL 程序里拆出去,单独立项。**

**还牵动**:`VK_RIGHT` 展开 / `VK_LEFT` 收起(`:5505`、`:5526`)—— 这两个在 RTL 下必须对调,
而且它是**语义**而非视觉的对调,漏了会让 RTL 用户的方向键完全反过来;
多列模式的列 x 走 `TTyColumns.ColumnFromPosition`(`:4801`、`:4861`、`:5226`),
和 §3.8/§3.10 同源,一起改;拖放插入点、树线(`:3998-4006`、`:4268-4278`)也是同一串累加。

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
- `AdjustClientRect`(`:803`)只扣顶部标签带,**与镜像无关** —— `TabPosition` 目前只有顶边
  (审计已记为缺口),所以没有"标签在左/右边"的分支要一起翻。这一点省了不少事。
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

### 3.15 `TTyDateTimePicker` —— **(c) 重写(命中面)**

**几何**:`RenderTo`(`DateTimePicker.pas:1633`)算文本矩形 → `TextOriginX`(`:1178`)
按 `FAlignment` 定起点 → 逐段用 `MeasureCharX`(`:1202`)量到第 n 个字符的宽度。
按钮列 `TyDateTimeButtonRect`(`:1009`)钉死 `X0 := ALocal.Right - BtnW`(`:1014`);
勾选框 `CheckBoxRect`(`:1443`)在文本矩形左侧。

**命中**:`MouseDown`(`:1322`)—— **注释直接写着 "Recompute text rect exactly as in
RenderTo (without scale rounding diff)"(`:1352`)**,然后在 `:1354-1358` 手抄了一遍
文本矩形,`:1414-1416` 又手抄了一遍文字左偏移。
**这就是 brief 里"点年份选到月份"那个 bug 的机制:同一个矩形算了两遍,
一遍带舍入差、一遍不带。**

**桶理由**:段分割 + 文本原点 + 三种按钮(下拉/上下)+ 勾选框,四组槽位,
每组在**绘制与命中两侧各有一份独立表达式**。加方向标志等于在八处各插一遍,
且没有任何测试能保证八处一致 —— 因为它们本来就不一致。

**唯一负责任的做法**:和 TreeView 一样,**先把 `RenderTo` 与 `MouseDown` 的 x 分区
抽成一个纯函数,让两边都吃它**;做完之后 RTL 是 (b)。
**这次抽取本身会顺手修掉一个既有 bug** —— 值得单独立项,而不是记在 RTL 账上。

**还牵动**:段间 `VK_LEFT`/`VK_RIGHT` 移动(在 `KeyDown:1801` 里)要取反;
弹出日历的对齐边。

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
| 9 | TreeView | **c** | 四到五份手抄的 x 累加链,源码自己写着 KEEP IN SYNC |
| 10 | HeaderControl | **a** | 一个纯函数,三个消费者全部取逆于它 |
| 11 | PageControl / TabSheet / TabStrip | **b** | 一份缓存布局 + 箭头/关闭槽换边 + 中点规则 |
| 12 | PopupMenu / MenuBar | **b**(Bar 是 **a**) | Bar 已有反向分支;Popup 行内 x 无命中,只需换边 + 弹出方向 |
| 13 | ScrollBar / ScrollBox | **b** | 三个纯函数的横向分支 + 四处 dock 坐标 + 原点符号 |
| 14 | StatusBar / CoolBar / ControlBar | **b** | 纯打包函数 + 抓手边;size grip 绘制与命中分写两处 |
| 15 | DateTimePicker | **c** | 命中面把绘制的矩形手抄了一遍(既有 bug 的机制) |

**合计:(a) 5 · (b) 7 · (c) 3。**

**改变决策形状的一点**:三个 (c) 里,**没有一个是因为"RTL 难"**。
它们贵是因为各自欠一次"绘制/命中收口"的重构 ——
`TyTreeSlotLayout`、`TTyDateTimePicker` 的 x 分区、`TTyCustomGrid` 的视口原点。
**这三次重构即使永远不做 RTL 也该做**(TreeView 与 DateTimePicker 都已经因此出过 bug)。
如果把它们记在各自的账上,**RTL 程序本身就变成 5 个 (a) + 7 个 (b) + 3 个 (b)** ——
量级完全不同。这一条应该直接影响"做不做"的判断。

---

## 5. 半做会静默坏掉什么(按"多难发现"排,最难在前)

1. **命中偏移了半个槽,但没偏出格。**
   最难发现。用户点"月",选中了"月",但点在月和日的交界像素上选错。
   headless 测不出(要逐像素反查),真机上也只是"偶尔手滑"。
   高危点:`TTyDateTimePicker.MouseDown:1352`、`TTyTreeView.GetNodeAtPoint:4660`。
   **防线**:逐像素反查测试(纯几何单元已经有这种测试,`Grid.Layout.pas:163-169` 写了这条不变量)。

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

**必须先定的一件事**:`TTyEdit.MeasureCodepointWidths`(`Edit.pas:948`)
返回逻辑序前缀和,`CaretPixelXAt`(`:1196`)与 `CaretIndexAtX`(`:1148`)全部建在其上。
BiDi 落地后视觉序 ≠ 逻辑序,**这个模型失效,与镜像无关**。
两条线要就"光标 x ↔ 字符下标由谁负责"达成一致,否则会出现混排文本里点击落错词。
`TTyMemo` 的 `CaretToVisual`/`VisualToCaret`(`Memo.pas:403`/`:408`)同理。

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
5. **不在 `EndPaint` 里翻位图**(§2.4)。
6. **不改属性名**(`Divider.LeftIndent`、`Columns[].Left`、`FScrollLeftRect`)。
   语义在 RTL 下会骗人,但改名是破坏性变更,收益不抵成本 —— 在 `docs/` 里写清楚即可。
7. **`TabPosition` 的左/右边标签不做。** 它目前根本不存在(审计已记为缺口),
   现在为一个还没有的功能预留镜像分支是浪费。

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
