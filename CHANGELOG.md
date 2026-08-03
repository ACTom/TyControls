# 更新日志

本文件记录 **ty-controls** 的所有重要变更。项目采用 3 段式语义化版本号(`主版本.次版本.修订号`)。
所有控件均由 BGRABitmap 全自绘、由轻量 `.tycss` 文本主题统一着色 —— 在 Windows、Linux、macOS 上
像素级一致。

> English: [CHANGELOG.en.md](CHANGELOG.en.md).

## [未发布]

### 新增 — 数据网格 `TTyStringGrid`

- **三层结构**:`TTyCustomGrid`(几何/绘制/主题)→ `TTyDrawGrid`(内容由宿主给,天然虚拟)
  → `TTyStringGrid`(自带稀疏存储 + 编辑 + 组织)。从 `TStringGrid` 迁移基本零学习成本。
- **看得见的能力**:冻结行列、百万行不卡(只画可视窗口)、二维光标与区域多选、
  可变行高、点列头排序、列头按值筛选、分组折叠、单元格合并、底部汇总带
  (**只统计筛选后可见的行**)、`Ctrl+C/V` 与 Excel 互粘、CSV 导入导出、
  拖列头改宽与换位。
- **单元格能放东西**:勾选框、下拉、日期、取色、进度条、评分、图片 ——
  显示方式与编辑方式是**正交**的(一列可以显示成进度条,双击仍按数值编辑)。
- 示例:[examples/grid](examples/grid/)。

- **表格该有的手感**:直接敲字就进编辑(这一笔就是新内容的第一个字符,与 Excel 一致)、
  Enter 向下推进、Tab 按格推进并在行尾折行 —— 从前必须先按 F2 或双击才能输入,
  Tab 还会把焦点整个弹出网格。
- **多列排序**:Shift+点列头追加次级列,表头显示顺位徽标;排序方式**跟着列走**
  (文本 / 数值 / 日期),空值排前排后可选且**翻方向时位置不变**。
- **过滤能条件化**:包含 / 等于 / 开头是 / 结尾是 / 大于 / 小于……
  —— 从前只有"包含"一种,数值列想筛 >1000 完全做不到。正在过滤的列漏斗会点亮。
- **分组表头**:横跨若干列的上层标题(两级)。排序与筛选按钮只出现在叶子级,
  点分组标题不会把下面某一列排序掉。
- **离散多选**(Ctrl+点)与拖选;选区聚合 `SelectionSum/Avg/Min/Max`,
  用来写状态栏那句"已选 12 项,合计 3400"。
- **逐格外观**:一个 `OnGetCellStyle` 钩子覆盖底色/文字色/字体/两轴对齐;
  另有**落盘**的 `CellColors[c,r]`(用户手工涂的颜色,存下来还在)、
  逐格边框(四支笔,用来画报表的分区块粗线)、斑马纹、焦点格与选区的区分。
- **换行与行高**:单元格文字换行、拖行分隔线改行高、`AutoFitRow` 按内容自适应,
  外加全局上下限当护栏。
- **列级声明**:这一列用什么编辑器、是否只读、下拉候选、只允许输入哪些字符、
  最多几个字 —— **设计期配好即可,不用接任何事件**。逐格只读也支持。
- **宿主可以接自己的编辑器**(`OnCreateEditLink`),网格答不上来的编辑需求有逃生口。
- **行的显式隐藏**:与过滤是两回事 —— 过滤是条件、隐藏是事实,清过滤不会把手工
  隐藏的行放出来。
- 批量行列操作(一次插/删多行、移动、交换)与丰富的事件族(单元格级鼠标、
  列宽行高的拖动过程与结束、列换位、勾选框、剪贴板)。
- **撤销 / 重做**(Ctrl+Z / Ctrl+Y):退回来的不只是文字 —— 底色、文字色、只读、
  合并跨度、行高、整表清空、导入 CSV 都一起退回原状。
  **一次批量操作按一次就全退回**:粘贴一片、剪切一片、一次插/删多行、
  给选区涂色、全表自适应行高、清掉所有合并,都是一步。
  `UndoLimit` 默认 100 条(0 = 关掉)。单条记录过大时整条作废并清空栈 ——
  半条撤销记录还原出来是一张四不像的表,比"这一步撤销不了"危险得多。
- **排序可以真的搬数据**:`SortMode := gsmData` 时点列头会像 Excel 一样
  **物理置换**(文字 + 逐格属性 + 行高 + 隐藏标记 + 合并跨度一起走),
  排完显示序就等于数据序 —— 于是"排过序就不许合并 / 不许拖行"那几条限制
  自动解除。一挂上筛选、分组或虚拟数据源就自动退回原来的行为
  (被筛掉的行一起搬 = 数据损坏)。物理排序**是可撤销的**。
- **多级分组**:`GroupByColumns([省, 市])` 按层级缩进;小计按层级各算各的
  (一行算进它所有祖先组);折叠状态按**层级路径**记,所以"北京"在不同省份下
  互不影响。单列分组是它的退化情形,只有一条实现。
- **鼠标拖行**:在行号槽里按下并拖过阈值就能重排行(与拖列头对称)。
  `OnRowMove` 可否决;行高分隔线优先;排过序/分过组/藏过行时拒绝拖动 ——
  显示序不是数据序时,把行拖到某个屏幕位置没有意义,松手排序就放回去了。
- **版式持久化**:`SaveLayoutToString` / `LoadLayoutFromString` 存取列宽、列序、
  可见性、排序键与冻结数;存哪儿由宿主决定(注册表 / ini / 数据库都行)。
  读回来是**全有或全无** —— 先整串校验通过才动控件,半套版式比完全不还原更难排查。
- **编辑器细节**:窄列编辑时编辑器自动加宽(`MinEditorWidth`,不改列宽也不越右缘)、
  下拉宽度可单独配(`TTyGridColumn.DropDownWidth`)、`OnGetEditorProp` 让宿主拿到
  真正那个编辑器控件微调字体/限长 —— 不必为了一点调整去写整个 `OnCreateEditLink`。
- **给选区上色**:`SetSelectionColor` / `SetSelectionTextColor` 直接对整个选区生效
  并算作一次操作(此前只能宿主自己遍历,而那样撤销是一格一格退的)。
- **内嵌筛选行**:列头下面一条带,每列一个输入位,打进去就按那一列筛。
  支持 `>1000`、`<=5`、`<>华东`、`300..600` 这样的写法,`;` 分隔的多个条件
  之间是**或**。输入即筛(停手才真的去筛),回车立刻生效,Esc 放弃这次修改。
  它是自己一条带、不是数据行 —— 行数、寻址、导出都不受影响。
- **树形单元格**:某一列可以显示层级(缩进 + 展开三角),折叠就把子行收起来。
  **父子关系由宿主给**(`OnGetNodeLevel` / `OnGetHasChildren`),控件不持有树,
  所以百万行的树也不必先在控件里建起来。
- **增删列、换列位置现在也能撤销**,连那一列的全部身份一起回来:
  宽度、标题、对齐、编辑器种类、只读、候选项、那一列上的筛选……
  从前列的结构进不了撤销栈,只能靠"一改列就清空撤销栈"兜底。

### 变更 — 与 Delphi/Lazarus 对齐(**含不兼容变更**)

逐个控件把本库与 LCL/Delphi 同名控件并排比对后的一批修正。**下面这些会改变现有代码的行为,
升级前请读完。**

- **`TTyMemo.SelStart` / `SelLength` 现在按完整的换行符计数。** 以前一个换行只算 1 个码点,
  而 `Text` 在 Windows 上吐出的是 CRLF 两个字符 —— 于是这两个偏移**指的根本是另一个字符串**:
  `Memo.SelStart := Pos(needle, Memo.Text) - 1` 每多一条前置行就多错一位,**而在第 1 行上永远是对的,
  也就是大家试它的地方**。现在 `SelText` 恒等于 `UTF8Copy(Text, SelStart + 1, SelLength)`;
  落在 CRLF 中间的偏移会被钳到该行行尾。**如果你以前为这个偏差做过补偿,请把补偿去掉。**
- **`TTyValueListEditor.Values` 改为按键取用,`ValueOf` 取消。** 行号形式叫 `ValueFromIndex`。
  `Values['Name'] := 'Bob'` —— 几乎每个移植过来的程序都有这一行 —— 以前编译不过,报的还是一句
  指不到症结的"参数 1 类型不兼容";而 `Values[0]` 在两个库上都能编译、含义却不同。
  两者**刻意不做成同名重载**:整数/字符串重载正是让移植代码打错成员还照样编译的路子。
  另外两条行为也一并对齐了 LCL:查找**不分大小写**,写一个不存在的键会**追加一行**。
- **`TTyListView` 的 `OnChange` / `OnChanging` / `OnSelectItem` 签名变了。** 从 Delphi/Lazarus
  移植的代码**不用改**(这三个就是 LCL 的形状);写给**本库旧签名**的代码要改。
  `OnChange` 从只有 `Sender` 变成带上是哪一项、变的是什么(`ctText` / `ctImage` / `ctState`);
  新增的 `OnChanging` 让你能**否决**一次选择变化;`OnSelectItem` 多了 `ASelected`,于是"第 3 行被选中"
  和"第 3 行被放开"终于分得清 —— 后者以前根本收不到任何事件。
  随之而来:`OnSelectItem` 现在是状态**增量**,重复选中一个已选中的行不再触发它(这是 LCL 的行为)。
- **`TTyToolBar.Images` 的类型由 `TImageList` 改为 `TTyImageCollection`。** 本库所有图标都出自
  按名字取用的 BGRA 集合,没有任何一处从按下标取用的 `TImageList` 渲染 —— 所以那个类型的属性
  无论宿主怎么赋值都到不了工具按钮。这正是它从前"存下来什么也不做"的原因。
- **`TTyEdit.ClearSelection` / `TTyMemo.ClearSelection` 现在会删除选中的文本。**
  以前它们只是收起选区、保留文字,而 LCL 和 Delphi 的同名方法一直是删除。同一个名字两个相反
  语义,而且**静默的那个方向更危险**:从 Lazarus 移植来的代码调它删除用户选中的内容,文字留着,
  什么提示都没有。旧行为保留为 **`CollapseSelection`**。
- **`TTyShellListView.Refresh` 改名为 `UpdateView`。** `Refresh` 在整个 LCL 和本库都是"立刻重画",
  这里却被改成了重新读盘 —— 于是它是唯一一个"顺手重画一下"会打到文件系统的控件,而真想重画的人
  没有办法要。
- **shell 控件不再占用 7 个 published 事件槽。** `TTyShellTreeView` 的 `OnGetText`/`OnInitNode`/
  `OnExpanding`/`OnGetImageIndex`/`OnChange` 与 `TTyShellListView` 的 `OnCompare`/`OnItemActivate`
  以前被构造函数占用,应用装上任何一个都会**静默替换掉 shell 行为**(树不再显示文件名、双击不再
  进目录)。现在这些行为改用覆写实现,事件槽归应用 —— 覆写跑完再调基类,所以应用的处理器看得到
  shell 给出的答案、也能改掉它。
  **一个例外:`TTyShellListView.OnCompare` 目前仍收不到调用**(排序覆写没有回调基类),文件列表的
  排序还不能由应用接管。
- **`TTyPanel` / `TTyTabSheet` / `TTyDivider` 的 `Caption` 与 `Text` 合一。** 以前它们各自有一个
  影子 `Caption`,写 `Caption` 不会写到 `TControl.Text`,于是读 `Text` 的东西(action link、
  无障碍、遍历 `TControl` 的通用代码)看到的是空串。`.lfm` 不受影响。
- **`TTyScrollPanel.AutoScroll` 改名为 `AutoPan`。** LCL 里所有滚动容器的 `AutoScroll` 都是
  "自动管理滚动条";我们的是"指针靠近边缘时自动平移"。新名字与该控件自己的
  `AutoPanTo`/`AutoPanActive`/`StopAutoPan` 一致。
- **`TTyGauge` 不再 published `Caption`** —— 它从来不画。
- **`TTyRadioGroup` 现在会通知选择变化。** 用代码写 `ItemIndex` 以前是静默的,于是跟着选择联动的
  处理器在用户点击时正常、在应用恢复保存值时失效。同时 `OnClick` 现在会在选择变化时触发
  (对齐 `TCustomRadioGroup`),并且**整个组只占一个 Tab 停靠点**(以前每个选项各占一个)。
- **`TTyColorButton.OnColorChange` 现在任何改色都触发**(以前只有对话框改色才触发);
  `OnClick` 现在在打开取色对话框**之前**触发,处理器因此能看到改动前的值。
- **`TTyImage.Proportional` 不再放大图片。** 以前 16×16 图标放进 200×200 会被吹大;现在只缩不放,
  要放大请同时开 `Stretch`(与 LCL 一致)。
- **`TTySplitter` 新增 `AutoSnap`(默认开)**:拖过 `MinSize` 即收起面板。以前 `MinSize` 是一道
  拖不过去的地板,等于没有任何手势能关掉一个面板。
- **`TTySpinEdit`**:`MinValue = MaxValue` 表示"不限",不再把值钳死在最小值。
- **`TTyTrackBar.Frequency` 默认改为 1**(刻度开箱即见),`Orientation` 现在会交换宽高。
- **`TTyHeaderControl.OnSectionResize` 只在松手时触发一次**;拖动过程改由新的 `OnSectionTrack` 报告。
- **数据网格:六个名字换了含义,升级前逐条对照。**
  - **`VisibleRowCount` 回到 LCL 的含义 —— 视口能放下几行**。以前它返回的是过滤后的数据行数,
    移植过来的翻页算式照样编译、算出来的却是另一个数;我们那个含义本来就有
    `DisplayRowCount` / `FilteredRowCount` 两个名字。
  - **`ClearRows` / `ClearCols` 现在是删除行列**(LCL 的含义)。以前它们清空一段区域的**内容**,
    同名反义 —— 清内容改叫 `ClearRowContents` / `ClearColContents`。刻意**不做成参数个数不同的
    重载**:"删掉所有行"和"清空两行"不能只差一个参数。
  - **`SaveToStream` / `LoadFromStream` 不再写 CSV**,改为带版本的完整容器(列宽、属性、位置一起存)。
    以前 CSV 藏在一个默认参数后面,移植代码写一个参数就能编译,存出来的东西悄悄丢列。
    CSV 请用 `SaveToCSVStream` / `LoadFromCSVStream`(标题行现在可选)。
  - **`Selection` 可写了** —— 存下来的选区终于能原样还原,不用自己拆成四个坐标重放。
  - `GridLineStyle` 保留本库含义(枚举类型不同,移植代码一定编译报错,不会静默走错)。
- **越界赋值现在会抛异常,不再静默。** `TTyCalendar.Date`(超出 `MinDate`/`MaxDate`)、
  `TTyCheckGroup.Checked[i]`、`TTyRadioGroup.ItemIndex` 三处从前分别是**悄悄钳住**、
  **读回 False 写了个寂寞**、**悄悄变成 -1**。这些结果都是**看起来合理**的状态,
  于是索引算错了没人会去查。`.lfm` 流式化豁免(否则属性次序不对会让整个窗体打不开);
  日历想要"尽量靠近"请改用 `SetDateClamped`。
- **`TTyMaskEdit.Text := 'hello world'` 现在走掩码**,不再整串塞进 `'###-###'` 里 ——
  从前 `IsComplete` 会对着那串垃圾说"填完了"。赋值与 Ctrl+V 现在判定一致(截断但不补齐)。
  另外两种**必然是移植错误**的掩码会直接报错:一个可编辑槽都没有的掩码(`'000-0000'`),
  以及含 `;` 的 LCL 三段式掩码(会悄悄丢掉后半段)。
- **`TTyShellTreeView.SelectPath` 改为函数**,写非法 `Directory` 会抛异常。
  以前非法路径**什么也不做** —— "路径写错了"和"路径没错但里面是空的"看起来一模一样。
  `SelectPath` 返回 `Boolean` 并附 `LastPathError`(四种可区分的原因),不抛异常;
  而 `Directory` 是属性写入、没有返回值可用,所以那一头抛。
- **`TTyTabStrip.TabHeight`**:`0` 保留"不显示标签条"(示例在运行时用它),**自动**改到负数上,
  与移植过来的 `TabHeight := -1` 一致。顺带修掉:现代密度下 `TabHeight := 28` 会命中"没变化"的
  提前返回,于是取值缩了、标签条没动。
- **`TTyHeader.Images` 的类型改为 `TTyVirtualImageList`。** 以前声明成 LCL 的 `TCustomImageList`,
  而本库的图像集合并非它的后代 —— 也就是说,**能赋进去的列表恰好都是画不出来的**,
  这个属性从声明上就不可用,网格只好自带第二份列表绕开它。
- **`TTyHeaderControl` 三个 section 事件的第一个参数由 `TObject` 改为 `TTyHeaderControl`**,
  `OnSectionTrack` 另多一个 `AState`(按下 / 拖动中 / 松手),于是"这个宽度是拖到一半还是最终值"
  终于分得清。
- **`TTySpinEdit.OnChange` 现在每敲一个字符就触发。** 以前只有提交后的值变化才触发,于是
  做即时校验、点亮"确定"按钮、更新预览的处理器在用户输入过程中**完全听不到动静** ——
  而半截数字可能根本走不到提交。提交值的变化改由新的 `OnValueChange` 报告(它最后触发,
  处理器看到的是稳定状态)。新触发点是旧的**超集**,不会有处理器丢事件。
- **`TTyCheckComboBox.Objects[]` 归应用所有了。** 以前勾选状态就占着这个槽,应用往里放自己的
  对象,读回来是"已勾选";文档还把这条当规则写着。现在勾选状态与应用数据同住一个对象里
  (LCL 的做法),排序、删除、清空都不会错位或泄漏。

### 修复 — 属性面板给了旋钮,控件却不看

这一批的共同点:成员都在那儿,**执行了、返回了、什么也没发生**。不报错、不打日志、截图上也看不见。

- **`TTySplitter` 的 `ResizeStyle` 四个取值现在全部生效。** 从前只有 `rsUpdate` 真的会改尺寸:
  选 `rsPattern` 或 `rsNone` 的分隔条**可以拖到天荒地老,什么都不会动**;`rsLine` 会动,但不画任何反馈。
  换句话说,选中默认值以外的任何一项就等于把这个控件关掉了。现在三种延迟样式都在松手时提交,
  `rsLine` / `rsPattern` 还会在拖动过程中画一条实时预览带(实心 / 虚线)。
  预览带的颜色取握把点用的同一个 `color` 令牌,`TySplitter { color: ... }` 一改改两处。
- **工具条的 `ShowCaptions` 现在真的能只显示图标了。** 它连同 `Images` 一起下发到每个能画图标的
  工具项(新增的 `TTyGlyphButtonBase.ShowCaption` 也可以逐个按钮设)。**解析不出图标的工具项保留标题**,
  所以这个与 LCL 对齐的 `False` 默认值不会把现有应用里的纯文字工具条抹白。
  工具条把自己的图标集合**借**给没有 `Images` 的工具项,自带集合的工具项不受影响。
- **`TTyMemo.ScrollBy` 现在滚动的是文本。** 从前调这个"备忘录滚动 API"拿到的是 `TWinControl` 的
  搬子控件版本:它把备忘录自己内嵌的滚动条从停靠边上拖走,而文字纹丝不动。
- **`TTyTreeView` 的 `Ghosted` 终于有了用处。** `OnGetImageIndex` 一直递给应用一个
  `var Ghosted: Boolean`,拿到手就丢了 —— 它想表达的"这个节点的图标画淡一点"(剪切 / 不可用的观感)
  在库里没有任何地方能实现。现在 `TTyVirtualImageList.Draw` 支持淡显:只降透明度、不改颜色,
  因为"改颜色"说的是**另一个东西**,而不是**不可用**。
- **右键菜单的 `OnPopup` 现在会触发**,`PopupPoint` 会更新,`Close`/`OnClose` 不再是空操作。
  菜单项快照改到 `OnPopup` **之后**才取,所以在里面动态加的菜单项真的会出现。
- **`TTyColorButton.Caption` 现在画出来了** —— 它一直是 published、设计器能填,但从来一个像素都不画。
- **所有控件都能在设计器/`.lfm` 里隐藏、拖放、接横向滚轮了** —— `Visible`、整套
  `DragMode`/`OnDragOver`/`OnDragDrop`…、`OnMouseWheelHorz|Left|Right`、`OnShowHint`
  以前在两个基类上都没 published,只能从代码里设。`AutoSize`、`BorderWidth`、`ChildSizing` 同理。
- **掩码输入框不再接受粘贴进来的任意文本**(以前 Ctrl+V 绕过掩码,电话号码栏里能躺 "hello world"),
  Delete 键也不再删掉掩码分隔符本身。
- **菜单栏**:禁用的顶级菜单画成灰且点不开;**无子项的顶级项现在会触发 `OnClick`**(以前完全没反应,
  和"菜单加载失败"看起来一模一样);支持 `RightJustify`(右对齐的 Help/Window 菜单)。
- **菜单项的 `Hint` 现在会发布到 `Application.Hint`**(状态栏可以描述光标下的命令);
  `AutoCheck` 的项在未勾选时也画出空勾选框,不必先点一次才知道它是开关。
- **日期时间选择器**:A/P 键设 AM/PM、分隔符键跳下一段、空格切换勾选框
  (以前勾选框只能鼠标点,而未勾选时控件拒绝一切按键 —— 键盘用户根本无法启用它)。
- **`ActivePage`、`ColorBox.Selected`、`ColorListBox.Selected` 现在是 published 的** ——
  这些控件存在的那个理由本身,以前没法在设计器里设、也不进 `.lfm`。
- **列头最后一段的宽度不再说谎**:新增 `EffectiveSectionWidth` 报告真正画出来的宽度。
- **`TTyScrollBox` 的视图滚动可以调用了**(`ScrollByDelta` / `ScrollTo`,以前是 protected)。
- **禁用的分隔条不再显示拖动光标**;列头/树控件不再吃掉调用方设的 `Cursor`。
- **速度按钮 `Down := True` 会松开同组其他按钮**;`AllowAllUp` 关掉时会恢复"必须有一个按下"的约束。
- **单选列表框的 `ClearSelection` / `Selected[i] := False` 真的会取消选中**。
- **`TTyCheckGroup.Checked[i] := x` 不再触发 `OnItemChange`**(程序赋值不该被当成用户操作)。
- **`TTyToolBar` 不再覆盖子按钮的 `StyleClass`**(宿主设的 `'primary'` 等变体会保留;
  `TTyToolBarEx` 上暂时仍会被覆盖);**状态栏最后一格铺到右边缘**。
- **取色下拉框写入调色板外的颜色不再往列表里追加一行**。
- **`TTyUpDown.Wrap` 现在进位而不是丢弃溢出**(Increment > 1 时不再变成"归零器");
  新增带方向的 `OnArrowClick`。
- **`TTyShellListView` 大小列的单位可翻译了**(以前写死英文)。
- **右键菜单的四个属性终于有人读了**:`TrackButton`(以前按住右键拖到菜单项上松手,什么也不会发生)、
  `GlyphShowMode`(逐项控制图标画不画)、`SubMenuImages`(每级子菜单可以用自己的图标集,
  以前一律继承上一级)、以及整套 `OwnerDraw` / `OnDrawItem` / `OnMeasureItem` 自绘协议。
  另外,**禁用菜单项的图标现在画成灰的**。
- **列头可以带图标了**:`TTyColumn.ImageIndex` 现在真的画出来,标题会给它让位;
  列头没有自己的图标集时,用控件的 `SmallImages`(这也是 Delphi/LCL 解析列图标的地方)。
- **文件树的 `ShowHidden` 立刻生效**,不再等到下一次刷新才露面。
- **`TTyDivider` 新增 `LeftIndent`**(`TDividerBevel` 的属性):按像素指定横线从左边缩进多少。
  与本库的 `Alignment` 并存,`LeftIndent >= 0` 时它说了算;默认关闭,现有分隔线渲染不变。
- **`TTyToolBarEx` 不再覆盖子按钮的 `StyleClass`** —— 上一版只修好了基类,`Ex` 子类
  重写了布局,那一行还留着,于是同样一句 `StyleClass := 'primary'` 在两个几乎一样的工具条上
  一个保得住、一个每次重排都被抹掉。
- **`TTyShellListView.OnCompare` 现在真的会被调用**(上一版把事件槽还给了应用,却没人去触发它)。
- 名称对齐:`TTyCalendar.DateTime`、`TTyMaskEdit.EditMask`、`TTyMemo.Append`、`TTyEdit.Clear`、
  `TTyListBox` 与 `TTyComboBox` 的 `Clear`/`AddItem`/`Count`/`ItemRect` 等一整套列表方法。

### 新增 — `OnPaint`

- **所有 TTy 控件都有 `OnPaint` 了。** 控件画完自己之后触发,交给你的是控件自己的 `Canvas` ——
  想加一个角标、一层浮层、一个调试框,不必再派生一个类。它**不是**自绘替换:
  处理器接手时控件已经画好了,你是画在它上面。
  文档从前把"没有 `OnPaint`"写成一条设计取舍,其实不是:本库每个控件都是先画进 BGRA 图层、
  再整块合成到画布上,从 `Paint` 里触发的钩子画的东西会被那次合成盖掉 —— 所以钩子挪到了
  合成完成之后。在带缓存的容器上,浮层也不会被烤进缓存里反复重放。

### 修复 — 数据网格

- **粘贴不再静默丢数据**:往 10 行的网格里粘 100 行,从前会悄悄丢掉 90 行;
  现在按剪贴板块的大小自动扩行扩列。
- **CSV 里含换行的字段不再串数据**:Excel 导出的 CSV 常有这种字段,
  从前会被拦腰截断、行数凭空变多。
- **排序小三角其实从来没显示过**:排序状态没有同步给表头。
- **一分组就丢排序列**:分组会把用户选的排序列静默抹掉。
- **增删行时合并区不跟着走**:内容跟着搬了,合并框留在原地。
- **`hoAutoResize` / 列头图标从来不生效**:属性暴露了,但运行期没有任何代码读它们。
- 排序时空值的位置会随升降序翻转(一翻向,空行就整块冒到最上面)。

### 性能 — 数据网格

- 单元格文字的绘制曾占整帧渲染时间的 **94%**;加了跨帧的文本缓存后降到约 1/20。
  滚动大表明显更跟手。


### 新增 — 14 个现代 UI 控件(对标 Ant Design 的缺口)

- **卡片与标记**:`TTyCard`(标题 + 内容 + 操作三段式卡片;`hoverable` 只需一条 `TyCard:hover` 规则)、`TTyTag`(标签胶囊,可关闭,颜色变体走 `StyleClass`)、`TTyBadge`(**独立**数字/圆点角标 —— 把 `Target` 指向任意控件即可吸附到它的角上,并随其移动缩放;`TTyButton` 自带的角标照旧可用)。
- **反馈**:`TTyAlert`(**内联**警告条 —— 此前所有提示都是模态弹窗,页面里常驻一条提示的语义完全没有;info / success / warning / error 四型,可关闭)、`TTyNotification`(角落浮出、自动消失的 toast;悬停暂停倒计时)、`TTyPopover`(**能放控件**的气泡浮层 —— `TTyHint` / `TTyBalloonHint` 只能显示文本)。
- **导航与流程**:`TTySegmented`(分段控制器,可聚焦 + 左右键切换)、`TTyPagination`(分页器,`1 2 3 … 195`;不依赖表格,配任意列表)、`TTySteps`(向导步骤条,横竖两向)、`TTyBreadcrumb`(面包屑)。
- **录入**:`TTyTransfer`(双列表穿梭框)、`TTyTreeSelect`(树形下拉)、`TTyCascader`(级联选择:省/市/区)。
- **空状态**:`TTyEmpty`(插画 + 文案 + 可选操作 —— 列表/树/表格的标配,此前只能手拼 Label)。

以上全部进组件面板(带 HiDPI 图标),**20 个主题下都能正常显示**,并各有一份 API 文档。

### 新增 — 主题

- **调色板多了两个语义色 `--success` / `--warning`**(各带 `on()` 配对),供警告条与 toast 的 success/warning 型使用。既有主题无需改动即可继承。
- **角标的角内缩与最小尺寸现在可调**(`--badge-inset` / `--badge-min-size`)。默认值不变,所以现有界面**一个像素都不会动**。

### 新增 — 示例

- **[examples/antdesign](examples/antdesign/) —— "TyControls Pro"**:仿 Ant Design Pro 的后台系统(侧边导航 + 6 个页面),默认 antdesign 皮肤,可运行时换肤与切换明暗。


### 变更 — 窗体结构(现有窗体需迁移)

- **`TTyForm` 的控件现在承载在内容容器 `TTyFormSurface` 上** —— 每个窗体一个,名为 `Surface`,铺满窗体,**所有控件都放在它里面**。File > New 的 *TyControls Form / Application* 模板已自带,新建窗体无需额外操作;设计器里拖控件本来就落进它。
  **现有窗体需要迁移**:把原本直接放在窗体上的控件移进 `Surface`(样式控制器、定时器、对话框组件等非可视组件不动)。
  **图形控件(`TTyLabel`、`TTyShape` 等)必须放在 `Surface` 里** —— 它们画在父控件身上,直接放在窗体上会被遮挡而不可见;你这么放时设计器会提示。
  对话框(`TTyDialog`)不受影响:它不可缩放、没有 `Surface`,控件照常直接放在对话框上。

### 修复

- **内置主题的"危险按钮"现在真的是危险色** —— 15 个内置主题里此前只有 `showcase` 定义了 `TyButton.danger`,其余 14 个会让 `StyleClass='danger'` 的按钮**静默回退**成普通按钮。现在每个主题都按自己模仿的设计体系取危险色(Bootstrap danger、Ant Design error、Material 3 error、Apple systemRed、GNOME/Yaru、KDE Breeze negative、各代微软红等),明暗模式分别配色。

- **无边框可缩放窗口右/下边缘那条没画上的白/透明细边消失了** —— 这类窗口画不到自己最外圈的像素,现由内容容器画到真正的边缘。这正是上面那项结构变更的原因。
- **File > New 的 *TyControls Dialog* 不再生成两条标题栏**;由它创建的对话框也不再在启动时报 `EClassNotFound: Class "TTyPanel" not found`。

## [2.2.0] — 2026-07-04

一个大型功能版本。主角是**对话框子系统**:为 **TTyForm** 补齐完整的窗口镶边(caption 按钮),
新增 **11 个全自绘对话框组件**及配套全局函数、IDE 集成与独立示例;同时新增**三个小控件**
(三态 CheckBox、可编辑 ComboBox、TTyTabSet),为全部控件补齐 API 文档,并修复大量在真机上
(尤其 Windows 10)才暴露的显示问题。

### 新增 — 对话框

- **TTyForm 窗口镶边** —— 标题栏的最小化 / 最大化 / 关闭按钮现由 `BorderIcons` 统一控制
  (`BorderIcons:=[]` 去掉全部按钮),窗口可否缩放由 `Resizable` 决定;旧的 `ShowMinimize` /
  `ShowMaximize` 属性已移除。
- **11 个全自绘对话框组件** —— 与 LCL 对齐,既可作为组件拖放,也提供全局函数直接调用:
  - **消息框**(`TyShowMessage` / `TyMessageDlg`)—— 完整的按钮组合、结果与类型图标。
  - **输入 / 密码 / 多行文本**(`TyInputQuery` / `TyPasswordQuery` / `TyTextQuery`)。
  - **列表取值**、**文件夹选择**(带新建文件夹、可展开目录树)。
  - **取色器**(HSV + 色相条 + RGB / CMYK / Alpha / Hex)、**字体选择器**(字族 / 字号 / 样式 / 颜色 / 预览)。
  - **查找 / 替换**(无模态,`OnFind` / `OnReplace`)、**进度对话框**(可取消)。
  - 全部对话框都支持 `OnShow` / `OnClose` / `OnCanClose` 事件。
- **IDE 集成** —— 新增 **TyControls Dialogs** 组件面板分组、11 个对话框的调色板图标、File > New 的
  **TyControls Dialog** 模板;设计器中双击任一对话框组件即可预览。
- **示例** —— 新增独立的 **dialogs 示例**演示全部 11 个对话框;主 demo 也加入了对话框网格。

### 新增 — 三个小控件

- **三态 CheckBox** —— `State` / `AllowGrayed`,带灰显(不确定态)。
- **可编辑 ComboBox** —— `csDropDown` 自由输入 + 前缀自动补全。
- **TTyTabSet** —— 纯标签条控件(非页容器)。

### 新增 — 文档

- 为**全部控件补齐逐控件 API 文档**(属性 / 事件 / 状态 / 主题变体 / 代码示例),覆盖此前缺文档的
  TreeView、Calendar、DateTimePicker、Splitter、StatusBar、ToolBar、TabSet、菜单、NativeStyler 等,
  并新增控件文档索引 `docs/controls/`。

### 新增 — 示例整体翻新

- 所有单控件示例统一采用 **TTyForm + TTyTitleBar** 自绘窗框,并更充分地演示各控件特性。
- 新增 7 个专属示例:tabset、calendar、datetimepicker、splitter、statusbar、toolbar、menu;
  `tabcontrol` 示例改用 TTyPageControl + TTyTabSheet。

### 修复

- **Windows 10 窗口发白 / 透明** —— 窗口及容器(对话框、分组框、页签、禁用控件)在 Windows 10 上
  不再透出玻璃或白色,窗口失去焦点时也不再整片变白。
- **禁用控件发虚** —— 禁用状态的控件文字不再发虚、背景不再透白。
- **可缩放窗口侧边竖条** —— 可缩放窗口左右两侧不再出现主题色 / 白色竖条。
- **可编辑 ComboBox 输入** —— 输入时不再丢失焦点或字符,自动补全弹层不再闪烁,点选补全项会填入正确的值。
- **标签滚动箭头** —— 标签过多时,左右滚动箭头不再遮住首 / 尾标签。
- **日期选择器下拉崩溃** —— 使用全局默认主题时,打开日历下拉不再崩溃。
- **进度对话框闪烁** —— 进度对话框的文字与进度条不再闪烁。
- **双击最大化崩溃** —— 多显示器 / 特殊配置下双击标题栏最大化不再崩溃。
- **中文界面** —— 中文系统下消息框按钮显示"确定 / 取消"等,dialogs 与 demo 示例界面跟随系统语言显示中文。
- **示例修复** —— 修复若干示例的启动崩溃与显示问题(radiobutton 启动崩溃、GroupBox 标题遮挡、
  splitter 拖动方向等)。

## [2.1.1] — 2026-06-30

一个修复版本,集中处理 green 图片主题的真机观感,以及 IDE 设计期的若干小问题。

### 修复

- **green 主题** —— 所有容器(toolbar、titlebar、statusbar、panel、groupbox、tab、分隔符、滚动条)
  改为 **100% 透明**,照片背景干净透出,不再有磨砂或纯色填充。
- **TTyForm 玻璃/照片背景** —— 应用主题时即时重建:用 Custom… 选图片主题后背景图**立刻出现**
  (不再需要先最小化/最大化触发);工具栏、状态栏也会采样照片透出。
- **最小化** —— 主窗口最小化到任务栏(而不是缩到屏幕角落的小方块);最小化弹出子窗口不再连累整个应用。
- **TTyToolBar 分隔符** —— 实心主题下与工具栏背景无缝(去掉怪异的填充色块),图片主题下透出照片。
- **IDE 设计器**
  - 切换 **TTyPageControl** 页面后旧页控件不再残留(先置 `csNoDesignVisible` 再改 `Visible`,使可见性即时重算)。
  - **TTyTreeView / TTyListBox / TTyMemo** 的内部子控件(滚动条、TTyTreeView 的内联编辑器)不再在设计器中露出。

## [2.1.0] — 2026-06-30

一个大型功能版本。主角是 **TTyTreeView**(一个 VirtualTreeView 级别的虚拟树),同时新增另外五个控件、
为 **TTyForm** 加入原生窗口缩放与窗口特效,并为整个库加上键盘助记符。

### 新增 — 新控件

- **TTyTreeView** —— 虚拟、数据按需加载的树,可承载百万级节点:
  - 三阶段惰性初始化;增量高度/位置缓存 + 快速命中测试。
  - 多列 + 可拖拽表头 —— 列**调宽**、**重排**、**自动列宽 / 弹性列**。
  - **排序** —— `OnCompareNodes`、点击表头切换升降序(带方向箭头)、惰性感知的归并排序。
  - **复选框** + 三态 + 自动三态传播,以及**单选(radio)**节点。
  - **多选**(Ctrl / Shift / Ctrl+A)与**整行选择**。
  - **逐节点可变行高**(`OnMeasureItem`)。
  - **增量输入查找**(type-to-find)。
  - **逐单元格自绘**(`OnDrawNode` / `OnAfterCellPaint`)。
  - **内联单元格编辑**(F2 / 双击;Enter 提交、Esc 取消;`OnEditing` / `OnNewText`)。
  - **树内节点拖放** —— 重排或改变父子关系,带 accent 落点标记与循环重父化守卫。
- **TTySplitter** —— 拖动以调整相邻控件大小。
- **TTyStatusBar** —— 分栏状态栏。
- **TTyToolBar** —— 带分隔符的工具栏。
- **TTyDateTimePicker** —— 分段式日期/时间编辑 + 下拉日历 + 时间微调。
- **TTyCalendar** —— 支持 日 → 月 → 年 逐级钻取的日历。

### 新增 — TTyForm

- 原生窗口**缩放**(Windows 自绘边框:`WS_THICKFRAME` + `WM_NCCALCSIZE` / `WM_NCHITTEST`),
  新增 **`Resizable`** 属性;最大化铺满显示器工作区;标题栏拖动 + 顶边缩放。
- 系统**圆角 + 原生投影**(Windows 11 DWM / macOS),默认开启,可通过 CSS 关闭。

### 新增 — 交互、主题、国际化

- **助记符(Mnemonics)** —— `&` 加速键,Alt 下划线显示 + Alt+字母激活,覆盖菜单、按钮、复选框、
  单选钮、分组框、标签、标签页。
- **TTyNativeStyler** —— 让原生 / 第三方 LCL 控件与当前主题协调一致。
- **TTyComboBox** —— 共享的主题化下拉浮层。
- **国际化** —— `resourcestring` + 英文与简体中文 `.po` 词条(主题诊断、设计期字符串、演示程序),
  演示程序支持运行时切换语言。

### 修复

- **TreeView** —— 节点图标不显示(ImageList 绘制被 BGRA 合成覆盖,改为合成之后再画;真正的根因是
  在加列之前就设了 `MainColumn`);HiDPI 垂直轴(滚动 / 命中测试 / 滚动到可见);超大范围的内嵌
  滚动条(最小滑块尺寸、64 位位置映射、构造期创建);展开箭头尺寸;水平滚动;销毁时托管节点数据
  泄漏;删除 / 清空时多选计数完整性。
- **TTyForm** —— 最大化底边钻到任务栏下方;双击最大化"原地变大";顶边缩放;顶部边框过宽。
- **主题** —— 双模式主题以无模式方式加载时崩溃;`TTyNativeStyler` 在深色主题下的文字颜色。
- **TTyEdit** —— 光标高度改为跟随字体行高(原先绑定盒子高度,在树的内联编辑器等紧凑宿主里只有半高)。
- **TTyMemo** —— 文本测量性能(逐行宽度缓存)。

### 平台

- **macOS** —— 编译 + 运行修复(系统主题检测用 process 单元、`CGFloat`、多显示器启动定位)。
- 自绘编辑控件的**输入法(IME)**支持(Qt6 / GTK2)。

### 说明

- 原生窗口缩放本版本**仅 Windows**;GTK / Qt / Cocoa 回退到手动缩放边距(原生交接计划中)。

## [2.0.0] — 2026-06-20

2.x 初始基线:基于 `.tycss` v2 主题引擎(先合并后解析、分层 token、双 `@mode`、跟随系统亮/暗 + 强调色、
热重载 + lint)的全自绘控件集,12 套内置主题,逐控件 `About` 元数据,以及发布工具链。
