# 更新日志

本文件记录 **ty-controls** 的所有重要变更。项目采用 3 段式语义化版本号(`主版本.次版本.修订号`)。
所有控件均由 BGRABitmap 全自绘、由轻量 `.tycss` 文本主题统一着色 —— 在 Windows、Linux、macOS 上
像素级一致。

> English: [CHANGELOG.en.md](CHANGELOG.en.md).

## [未发布]

### 修复 —— 这一轮的目视问题

- **可编辑下拉框画了两层边框**,倒三角掉进两层之间。量下来箭头根本没动:只读态和可编辑态,
  箭头到外边框都是 3px。差别是可编辑态那个内嵌的编辑框把自己那圈字段边框也画了出来,
  于是箭头被夹在内框和外框中间(左 10px、右 3px),看着就是"贴边"。
- **微调按钮、滚动条端头、标签条左右滚动键**现在画**实心三角**,不再是带杆的箭头。
  Windows 自己就是这么分的:**步进/滚动**用三角(spin 部件是 5×3 实心三角,原生标签条滚动用的
  就是同一个部件),**展开/下拉**用 V 形。同时把图标挤在边框上的问题一并修了 ——
  这一族按钮的图标内距原本吃掉每边 9px,在 18×14 的按钮半格里只剩 9×5 的墨水区。
  **对主题作者是不兼容变更**:微调按钮的覆盖令牌现在是 `--glyph-triangle-up/down`,
  不再是 `--glyph-arrow-up/down`(现有主题没有一个设过这两个,所以实际影响为零)。
- **菜单按钮的下拉标记**改用与下拉按钮、工具条、下拉框同一个 V 形,不再是自己手搓的三角。
- **日期框的下拉标记**此前是被**拉伸**填满按钮区的 V 形,所以又宽又扁,跟库里任何一个下拉框都不一样;
  现在和下拉框逐像素相同。
- **滑块条根本没有"槽"** —— 整个控件就是槽。它把整块客户区填成 `--surface-track`,
  所以在任何主题下都是一块更深的板;aero 那种蓝色表面上还是**中性灰**;而刻度画在同一个矩形里,
  于是**压在轨道上**。现在:控件本身不画背景、继承所在表面;槽是居中的一条细带(新的
  `TyTrackGroove` 键);刻度按 `TickMarks` 指定的一侧单独占一条带。aero 顺带把
  `--surface-track` 接到它本来就有、却只给进度条用的 `--track`。
- **字段右端小部件的位置统一了**。下拉框把按钮区贴在边框上,而所有基于编辑框那条
  "尾部部件"接缝的控件是从**内缩后的内容框**量起 —— 于是同一个 9px 箭头,下拉框离边框 3px、
  ComboEdit 7px、SpinEdit 6px、CalcEdit 和 FloatSpinEdit 10px、MenuButton 12px。
  现在只有一个定义,画和点也共用它(此前是两份各自写死的算式)。
- **`window-shadow: false` 时窗口失焦会闪出 Windows 经典标题栏**(论坛反馈)。
  关阴影走的是 `DWMWA_NCRENDERING_POLICY=DISABLED`,DWM 退出后 Windows 回退到旧版非客户区绘制,
  而旧版路径不走已有的那道抑制。

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
- **每格挂一个对象**:`Objects[列, 行]` —— "这一行是哪条记录"终于有地方放了。
  它跟着格子一起搬家:排序(含真的换数据的物理排序)、插行删行、换行拖行,
  对象都停在它那一行上。从前宿主得自己维护一张按行下标记账的平行表,
  并在每一次结构变动之后重新对齐 —— 而对不齐的症状是排完序读到别人的记录,
  一声不响。**网格不拥有这些对象**(不释放、不复制、不存盘),
  它们也**不进撤销栈**(那会让 Ctrl+Z 交还一个你可能已经释放掉的指针)。
- **整行整列当 `TStrings` 用**:`Grid.Rows[3] := MyList`、
  `Memo.Lines := Grid.Cols[2]`、`Grid.Rows[r].CommaText` —— 几乎每个从 LCL
  移植过来的程序都有这两三行,从前只能改写成逐格循环。交出来的是**活视图**:
  读写直接落到格子上。**赋值不改网格的结构**(源短了尾部原样留着、源长了多的丢掉),
  与 LCL 逐字一致。

### 修复 —— 用户与论坛反馈的这一轮

- **单选组点一下不跟焦点**:点"Small",圆点过去了、**焦点框还留在上一项**,再点一下才跟上。
  机制是两条正确的规则撞在一起 —— 单选组只让**选中项**有 TabStop(LCL 自己也这么做),
  而基类又拿 TabStop 当"这次点击要不要取焦点"的闸门,于是**唯一点得出焦点的恰好是已经选中的那项**。
  LCL 不中招是因为它的子控件是原生 radio,Windows 不管 TabStop 一律给焦点;自绘控件没这待遇。
- **单选组 / 复选组每一行都压着上一行**:行距用 `--row-height`(22),而托管子控件自己的最小高度是 25,
  LCL 把每次 SetBounds 上钳到 25 —— 于是相邻两行**重叠 3 像素**,下面那行 z 序更高,
  正好盖掉上一行焦点框的整条下边。最后一行没人盖,所以只有它是好的。
- **CoolBar / ToolBarEx / ControlBar 的子控件擦掉了容器的下边框**:布局用的是没扣掉边框的客户区。
- **CoolBar 抓柄拖动改错了对象**:真 rebar 拖抓柄是移动**它与左邻之间的分界**(左边那条被挤窄),
  我们却在缩放被拖的那条自己。现已对齐;行首那条没有左邻,手势按 LCL 的做法变成"移动"。
- **CoolBar 现在能换序了**:拖过邻居即交换,拖到最后一行下面即独占一行。
  代码里"做不到"的注释是错的——`TWinControl.SetControlIndex` 能把子控件放到列表任意位置,
  而打包器就是按子控件顺序读的,**移动子控件本身就是换序**。
- **滚动框:拖滑块闪烁、内容不跟手**。滚动条的位置**由两处算式各算一遍**,差一个边框宽,
  于是每滚一步两条滚动条被搬开又搬回(那就是闪烁),每次 SetBounds 又重入对齐流程 ——
  12 步拖动触发 120 轮重排,现在是 24 轮。另外有视口时内容住在视口里,
  而"布局原点跟偏移走"这两个钩子挂在外框上,对它完全没生效:视口里对齐的子控件**一格都不滚**。
- **`goHeaderPushedLook`(列头按下观感)与 `goThumbTracking`(拖滑块时是否实时滚)现已可用**。
  后者也可以只关一条轴:`Grid.VScrollBar.LiveTracking := False`。
- **网格 Ctrl+X** 补上(此前只有公开方法,没有手势)。
- **布局网格的格子在渐变主题下露出系统底色**:`TTyGridCell.Paint` 是个空方法,而且它借用数据格的
  主题键(那个键按设计就是透明的)。现在有自己的键,并继承父控件已经画好的背景 —— 不是填一层纯色,
  那会把渐变压平。
- **Bevel 的高光在暗色主题下发白**:混合比例不分明暗,一律往白里推 55%。
- **工具条的分裂下拉按钮在默认扁平样式下看不出分界**:那条竖线用边框色画,而扁平工具条给每个工具挂
  `ghost` 类,ghost 的边框色是全透明。于是 `tbsDropDown` 和 `tbsButtonDrop` 长得一样、行为却不同。
- **下拉箭头画在一处、点在另一处**:两者差一个内边距,默认设置下**画出来的分隔线和大约 6 像素的箭头
  跑的是主操作**。现在两处读同一个纯函数。
- **`TyForm { window-shadow: false; }` 从来没关掉过阴影**,详见上一节。
- **跨屏 DPI(PerMonitorV2):拖到高分屏再拖回来,布局回不去了**。六个控件把尺寸下限写成设备像素,
  而 LCL 又对同一份 `Constraints` 缩放了一次,于是**一次跨屏应用两遍**:按钮 29 → 175 → **70**。
  现在 DPI 变化期间下限不再重算,等 PPI 稳定后一次性重新推导 —— 来回拖动可精确还原。
  顺带把同步阶段的耗时降了 42%(重复的标题测量本来就是白做的)。
- **42 个示例其实一直没有清单文件**:`.lpi` 里都写着 `UseXPManifest`,但只有 4 个 `.lpr` 真的把
  项目资源链进去了 —— 其余的既没有 common-controls v6,也没有任何 DPI 声明。

### 新增

- **`TTyToolBar.HotImages` / `DisabledImages`**:悬停 / 禁用时换**图形**(换颜色一直是主题的活)。
  按名字取图,只在工具已经在用条自己那份图、且备用集合里有同名图时才生效。
- **`TTyScrollBar.LiveTracking`**:关掉后拖滑块只移动拇指,松手才提交位置。
- **`TTyForm.StyleOverride`**:窗体也能像别的控件那样,运行时用一小段 CSS 覆盖自己的外观。

### 新增 — 新控件 `TTyFloatSpinEdit`

- **小数微调框**:`Value: Double`、`Decimals`、`Increment`(**允许小于 1** —— 0.25 一步正是它存在的意义;
  步长比 `Decimals` 细会看起来没反应,文档写明)。与整数版 `TTySpinEdit` 是**兄弟不是父子**:
  它继承自 `TTyNumericEdit`,所以选区 / 剪贴板 / 撤销 / IME 一应俱全,千分位分组默认**关**(LCL 同)。
  组件面板 `TyControls Edits` 分页,共 162 个可拖放控件。

### 新增 — 第二、三波继续补齐

- **网格 `Options`**:LCL 那套 ~32 个行为旗标,一个属性面板入口翻全部开关。21 个进集合
  (其中 9 个是既有具名属性的**视图**,读写同一份状态,设计器与代码永不打架)、11 个不做且逐条
  写了理由 —— 取舍全表在 [docs/controls/grid.md](docs/controls/grid.md)。
- **工具条终于有了按钮类型系统**:`TTyToolButton` 六种样式(按钮 / 勾选 / 下拉 / 分组 / 分隔 / 分割线),
  `Grouped` 相邻成组、`ImageIndex` 落到 `ImageName` 上(重排图片集不会悄悄换图)。条上同批补齐
  `ButtonWidth`(**下限**语义,调低会还原设计宽)、`DropDownWidth`、`List`(图标在旁;本库默认与 LCL
  相反,叠放会把标题压成零高,文档写明)、`OnPaintButton` 整体自绘钩子。
- **列表框横向滚动**:`ScrollWidth` + 底部滚动条,比框宽的项终于看得全;顺带开出**逐行高度**的缝 ——
  下拉框由此补上 `csOwnerDrawVariable` / `csOwnerDrawEditableVariable` + `OnMeasureItem`,
  以及 **`csSimple` 常驻列表**(字段下永远可见,无弹层无箭头,Win32 语义逐条实测)。
- **标签条多行**:`MultiLine` / `RaggedRight` / `RowCount` —— 页签放不下折成多行,不再只有滚动箭头;
  左右侧边条带自动变多列。`ScrollOpposite` 明确不做(它与拖拽重排语义相撞,计划里有全文)。
- **四个容器的停靠面**:`TTyPanel` / `TTyGroupBox` / `TTyPageControl` / `TTyControlBar` 全部
  published `DockSite` 与九个停靠成员 —— 用**真实鼠标拖放**逐站验证过,不是只跑了 `ManualDock`。
- **图像集合进得了 `.lfm` 了**:`TTyImageCollection.Images` 是 published 集合,每项名字 + PNG
  (base64,可 diff 可审;**不用** LCL 那种 IDE 打不开的二进制伪属性)。同名多项 = **多分辨率母版**,
  HiDPI 按"最小够用"取,不再只能拉伸一张。
- **日历与日期框的月份、星期名跟随应用语言**:`--lang=en` 下不再是"八月 2026 / 周日 周一"。
  优先级 = 应用显式指定 > 已加载翻译 > OS 区域,**不加载语言目录的程序保持原有 OS 行为,零回归**。
  注意:英文部署要带上几乎为空的 `tycontrols.en.po`(里面的语言哨兵就是开关),README 有说明。
- **值列表编辑器**:`KeyOptions`(键可改 / Insert 加行 / Ctrl+Delete 删行 / `keyUnique` 按**同级**判重)
  + `Keys[]` 可写(LCL 形状:程序写入不查重)。
- **面板标题的纵轴**:`TTyPanel.VerticalAlignment`(LCL 的类型与默认值)—— 标题能靠上靠下,
  不再永远钉在中央和子控件撞字。

### 修复

- **`TyForm { window-shadow: false; }` 从来没关掉过阴影** —— 属性一直读得对、合得对、时机也对,
  死在最后一步:可缩放的 TTyForm 是真实 DWM 窗框,它的阴影是**窗框阴影**,与
  `DwmExtendFrameIntoClientArea` 的 margins 毫无关系,而旧代码正是靠"把 margins 清零"去关它。
  真正的开关是 `DWMWA_NCRENDERING_POLICY`。顺带两件:关掉后左右下会露出一圈 GDI 的经典残框(已一并吞掉,
  边缘缩放不受影响);以及**固定尺寸窗口从来就没有过阴影**(玻璃扩展对它是死的),现在默认也有了。
- **`TTyForm.StyleOverride`**:窗体也能像其他控件那样,运行时塞一小段 CSS 覆盖自己的 chrome ——
  `Form.StyleOverride := 'window-shadow: false; border-radius: 0;'` **当场生效**,不必为了一个窗口做一套主题。
  用的是控件那一套解析与合并器(同一份代码,不是另起炉灶),窗体里原先七处各自解析样式的地方也都改走它。


- **aero 切暗色是半黑半白的混窗**(你截图那个):aero 只定义了 19 个 typeKey,其余控件回落基础层;
  而它的 `@mode dark` 是浅色的逐字复制、又没钉住基础层的模式种子,于是自家控件保持浅色、
  回落的全变黑。现在 **aero 有一套真正的暗色玻璃**(Win7 深色 colorization 那种深蓝黑),
  **classic 则钉死"无暗色"**(Win95 没有这回事,切暗色=整窗保持原样)。
  新守卫按 17 主题 × 两模式全扫:窗体背景与回落表面的明暗必须同类、正文墨对比 ≥60 luma,
  这一类"半黑半白"从此进不了库。
- **aero 主题下所有窗口化控件四角出现纯黑硬角块** —— 根因不是画家:渐变背景的窗体从不设 `Color`,
  停在 `clDefault`,而它按 RGB 读出来就是**纯黑**,子控件重建父背景时拿到的就是这个黑。
  现在渐变会按控件所在的那一段真实切片。
- **只读网格不再能被改出三个口子**:`ReadOnly` 之前拦得住七条编辑路径,拦不住**粘贴、剪切、填充柄**。
  现在粘贴整体被拒、剪切退化为复制、填充柄直接消失;**逐格 / 逐列锁定也从此对填充生效**
  (等差填充跨过锁定格按位置续,不会错位)。网格的 **Ctrl+C/V** 之外补上 **Ctrl+X**。
- **勾选框的本地化真值词('是')在真实程序里从来没生效过** —— 它在单元初始化时拷贝翻译,
  而语言目录是之后才加载的。现在实时读取,中文表里键入 是 真的会打勾。
- **工具条按钮英文下截成 "Ne…"、中文反而完整** —— `AutoSize` 用一套文字引擎量宽、画家用另一套画,
  两套对同一串英文给出不同答案。现在量与画同源。
- **Ribbon 的 File 页签终于可翻译**(此前类型不对,翻译器够不着;默认值同时从硬编码中文改为英文 ——
  属性默认值跟随语言会让 `.lfm` 依赖保存时的区域,故默认值永远是英文字面量,翻译走目录)。
- **43 个示例的代码拼接文案全部可翻译**(约 740 条),`--lang=en` 与中文下整窗一致;
  维护工具 `scripts/example-rsj2po.py` / `check-example-po.py` 一并入库。

### 新增 — 从 LCL 移植时最常撞的几堵墙

- **树的节点对象模型**:`Tree.Items.AddChild(nil, '根')` 能编译能跑了,`Add` / `AddFirst` /
  `AddChildFirst` / `Insert` / `DeleteItem` / `TopLvlItems[]` 一并到位,节点标题用
  `Tree.NodeText[Node]` 读。设计期在属性面板点 `Items` 的省略号(或双击控件)就能编树,
  形状直接看得见。**虚拟模式一点没变**:`Items` 是空的就还是从前那棵百万节点的树,
  一个字节都不多占。两边同时给内容(比如既填了 `Items` 又挂了 `OnGetText`)会**当场报错并
  同时点名两边** —— 静默偏向任何一边,都会变成"我的事件不触发了"或者"我在设计器里填的
  节点运行时不见了"。
- **标签条能换边、能带图标**:`TabPosition` 支持上/下/左/右,`Images` + 每页 `ImageIndex`。
  左右两边的标签**不旋转文字** —— 一条 28 像素宽的竖条放不下一行字;它变成一列整宽的行,
  按最宽的那条标题定宽,这也是现在的界面惯常的做法。
- **下拉框的 owner-draw**:`Style` 补到 `csOwnerDrawFixed` / `csOwnerDrawEditableFixed`,
  配 `OnDrawItem` 自己画每一行(以及收起来时的那一格)。**不挂处理器就照旧走主题绘制**,
  所以单改 `Style` 不会把控件画成一片空白。
- **掩码框说的是 LCL 的掩码语言了**,而且**光标能落进任意一个槽**就地覆写 —— 从前只能从左
  往右追加、只能删最后一个。
- **日期框能表达"没填"**:`NullInputAllowed` 允许用户按 Del/Ctrl+N 清空,`NullDate`
  就是 LCL 的那个值(和 LCL 控件、和数据库列都能对上),`TextForNullDate` 决定空的时候
  显示什么。
- **`TTyUpDown.Associate`**:上下按钮绑到一个编辑框上。**它是双向的** —— 用户在框里改了数字,
  下一次点箭头从**框里那个数**接着走,而不是从按钮自己记的那个。
- **工具条能指定在哪儿换行**:`TyToolbarLayout` 新增一个"这一项另起一行"的入参,不再只能
  等它挤不下了自己折。

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
- **`TTyValueListEditor.VisibleRowCount` 改成"视口里装得下几行"。** 从前它答的是"展开着几行",
  那个含义现在叫 **`DisplayRowCount`**。两者都是 `Integer`、都是 public,所以从 Lazarus 移植来的
  翻页算式编译得过、算出来的却是垃圾:500 行展开着就一次翻 500 行。这与数据网格上那个同名撞车
  是同一处伤,当时没落到这个类上,因为这个控件是列表框不是网格。
- **掩码框空着的时候现在显示 `__/__/____`。** 从前空的掩码框就是一个**什么都没有的空盒子**,
  打了一半显示 `12` —— 屏幕上没有任何东西告诉用户这个字段要八位数字、分隔符在哪、还差多少。
  占位符由新的 `SpaceChar` 决定(默认 `'_'`,与 Delphi/Lazarus 相同),光标落在下一个待填槽上。
  **注意 `Text` 是显示串**,所以没动过的字段读出来是 `'__/__/____'` 而不是 `''` —— 要值请读新的
  `MaskedValue`。写 `SpaceChar := #0` 可退回旧显示。
- **掩码框离开焦点时会检查有没有填完。** 半截的 `'12/__/____'` 从前**悄无声息地**进到业务代码,
  除非每个调用点都记得轮询 `IsComplete`。现在失焦时自动校验一次,没填满抛 `ETyMaskError`;
  也可以在 OK 按钮里主动调新增的 `ValidateEdit`。只在**用户本次真的改过**这个字段时才查,
  且 `OnExit` 先跑 —— 让处理器有机会先补齐。允许半截值的表单请把该字段的 `Mask` 设为 `''`,
  或重写 `ValidateEdit`。
- **`TTyValueListEditor.InsertRow` 换成 LCL 的签名**,返回新行下标、带 `Append` 参数
  (默认 `True`,已有的两参数写法照旧可用)。同时补上"插到某个位置"——这个类从前**根本没有**,
  想按顺序建表只能整体重建。`RowCount` 也从只读函数变成可读写属性,`RowCount := 0` 能编译了。
- **失焦的 `TTyEdit` 不再画选区高亮**(`HideSelection`,默认 `True`,与 `TEdit` 一致)。
  从前一张窗体上三个输入框会同时显示三段"像是活动的"选区。选区本身保留,只是不画。
- **Tab 进 `TTyEdit` 会全选内容了**(`AutoSelect`,默认 `True`,与 `TEdit` 一致),于是"Tab 进去
  直接打新值"这套录入流程不用再在每个输入框的 `OnEnter` 里手写 `SelectAll`。鼠标点击定位光标不受影响。
- **`TTyEdit.PasswordChar := #0` 现在是"关掉掩码"。** 从前它得到一个装着 NUL 的字符串 ——
  于是该显示明文的时候仍在打码,打的还是一个谁也看不见的字形。
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
- **`TTyImage.Center` 与 `Transparent` 的默认值改为 `False`(与 `TImage` 一致)。**
  这两个属性用的是 LCL 的**名字**,默认值却一直是相反的。LCL 不把等于默认值的属性写进 `.lfm`,
  所以一份从 `TImage` 转过来的窗体里**根本没有 `Center=` 这一行** —— 落到旧版控件上,
  每一张未拉伸的图都会悄悄跑到控件正中,而 `.lfm` 里没有任何东西能解释它。
  **迁移**:原先依赖默认值的窗体显式写上 `Center = True` / `Transparent = True`。
- **`TTyVirtualImageList.Draw` 与 `TTyGlyphImageList.Draw` 改用 LCL 的参数顺序。**
  以前是 `Draw(画布, 序号, X, Y, 尺寸)` —— 顶着 LCL 的**方法名**却把序号和坐标**对调**。
  所有参数都是 `Integer`,于是把 `Images.Draw(C, X, Y, Idx)` 移植过来最自然的改法就是补上尺寸,
  写成 `Draw(C, X, Y, Idx, 16)`:**编译通过**,然后把第 X 号图画到了 `(Y, Idx)`。
  现在 `Draw` 就是 LCL 那个签名(末位是 **`AEnabled`**,不是 `Ghosted` —— 两者互为反义
  且都是 `Boolean`,写反了照样编译,结果是每个图标都画成禁用态)。带尺寸的那版改名
  **`DrawIndex`**,四个 `Integer` 的 `Draw` 已不存在,所以旧调用点会**编译失败**而不是悄悄对调。
  **迁移**:`Draw(C, i, x, y, sz)` → `DrawIndex(C, i, x, y, sz)`。
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
  - **新增的 `Objects` / `Cols` / `Rows` 会与同名的后代成员撞车。** 自己从
    `TTyStringGrid` 派生、并在派生类里声明过这三个名字之一(属性、字段或方法)的代码
    编译不过,报"重复标识符"。这是**编译期**的错、指得很准,改名即可 ——
    但升级前值得先搜一遍。
- **掩码框换了掩码语言(不兼容)。** 从前是本库自己那三个码(`#` 数字、`L` 字母、`C` 任意),
  现在就是 **LCL / Delphi 的那一套**:`0` 必填数字、`9` 可选数字、`L`/`l` 字母、`A`/`a` 字母数字、
  `C`/`c` 任意、`H` 十六进制、`B` 二进制,加上 `>` `<` `<>` 大小写区、`\` 转义、`!`,
  以及结尾的 `;存字面量;占位符` 两段。**旧写法里的 `#` 现在会直接抛异常**,不会静默。
  这一条本身就是在修一个更坏的毛病:从前把一条 Lazarus 的 `EditMask` 贴进来是**收下的**,
  但意思完全不同 —— `'000-0000'` 在旧语言里一个可编辑槽都没有,那个框永远吃不进一个键,
  一声不响。

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
- **`TTyDateTimePicker.DateTime` 的代码写入不再触发 `OnChange`。** 以前无条件触发,于是
  "把一条记录读进窗体"这行普通代码会回调应用自己的处理器 —— 没人碰过的窗体亮起脏标记,
  回写模型的处理器还会自激循环,而且**没有开关可以关掉**。现在 `OnChange` 只代表用户改的;
  需要旧行为把 `dtpoDoChangeOnSetDateTime` 放进新的 `Options`(这也是 LCL 的做法与默认值)。
- **`TTyCalendar.FirstDayOfWeek` 默认改为跟随系统。** 以前写死周日开头,于是周一开头的区域
  (欧洲、亚洲大部分)开箱即得一个美式周布局,而且**没有任何取值能表达"跟随系统"** ——
  只能硬写 `wdMonday`,应用换语言后又错了。依赖周日开头的窗体请显式写 `FirstDayOfWeek := wdSunday`。
- **点日历里相邻月的灰格,现在会选中它并翻到那个月。** 以前这一击被直接丢掉:灰格是死的,
  也没有任何提示。这是 LCL 的默认行为;要恢复旧的拒绝,把 `dsNoMonthChange` 放进新的
  `DisplaySettings`。
- **`Esc` 现在撤销整次编辑,而不只是丢掉半截数字。** 用方向键把月份调过头的用户按下 `Esc`、
  以为取消了,改动却留着 —— 这是所有人都会做的手势里最不该失灵的一个。控件在获得焦点时
  记下当时的值,`Esc` 恢复它。
- **`TTyDateTimePicker` 里键入的两位年份会展开。** 在 `yyyy` 格式里敲 `26` 再离开,以前存下的是
  公元 26 年 —— 一个看不见的错误数据。现在按新的 `CenturyFrom`(默认 1941)展开成 2026。
  三位 / 四位输入不动。同理,12 小时格式里键入的小时留在当前半天(下午 3 点敲 `04` 得 16:00,
  以前得 4:00,显示还写着 "04 PM")。
- **格式串不再被悄悄改写。** 以前控件把单字母字段翻倍(`'d/m/yyyy'` → `'dd/mm/yyyy'`),
  于是显式写的格式看起来像被忽略了;而且这条改写对月份名本来就不成立,`'dd mmmm yyyy'` 里
  点年份会选中月份。现在按写的那样渲染,新的 `LeadingZeros := False` 给出 `9/7/2026` 这种紧凑样式。
- **`Space` 切换复选框现在会触发 `OnChecked`。** 以前只有鼠标点复选框那条路径通知,键盘改了
  状态却不告诉任何人。通知点移进了属性 setter,所以鼠标、`Space`、自动勾选、程序化赋值
  走的都是同一条路(LCL 也是这样)。
- **`TTySpinEdit.MaxValue` 默认从 100 改为 0(= 不限)。** 这是 LCL 的默认值,而"上限恰好 100"
  是个**会毁数据的**默认:往一个没配过范围的控件里输入 5000,提交时被静默钳成 100,
  没有任何提示。示例里的每个 spin edit 都显式写了范围,所以显示不受影响;
  你自己的窗体若依赖那个隐含的 100,请显式写出来。
- **`TTyUpDown.OnArrowClick` 改到值变完之后触发。** 以前它先触发,于是处理器里读 `Position`
  读到的是**自己这次点击之前**的值 —— 每一个"点了上箭头就去同步别处"的处理器都慢一拍。
- **`TTyShellTreeView` 的目录展开默认改为每次重新读盘**(LCL 的 `ecmRefreshedExpanding`)。
  以前一个目录在控件生命周期里只枚举一次,所以**之后新建的文件永远不出现**。
  要旧行为把 `ExpandCollapseMode` 设成 `ecmKeepChildren`。
- **`TTyShellListView.UpdateView` 按路径而不是按行号恢复选中。** 以前钉的是行**下标**,
  于是在选中项上方新建一个文件,高亮就跑到了另一个文件上 —— 文件对话框会返回一个
  用户根本没点过的名字。
- **`TTyImage.Center` / `Transparent` 默认由 `True` 改为 `False`(与 LCL 一致)。**
  从 `TImage` 转过来的 `.lfm` 里没有 `Center=` 这一行,于是每一张不拉伸的图都被悄悄居中了。
  需要居中请显式写 `Center = True`。
- **树控件三个成员把名字还给了 LCL 的含义,升级前逐条替换。**
  - **`GetNodeAt`**。以前是 `GetNodeAt(Y; out ANodeTop)` —— 与 LCL 的
    `GetNodeAt(X, Y)` **同名、同参数个数、都是 Integer**,于是移植过来的调用**直接绑上了它**:
    把调用方的 X 当成滚动偏移读、返回错误的节点、还顺手改写了调用方的 Y。
    这不是假想:改完名,本库自己的测试**一次构建红了 12 条断言**。
    现在 `GetNodeAt(X, Y)` 是 LCL 的含义,我们原来那个叫 `GetNodeAtOffset`。
  - **`Selected`**。以前是按下标的 Boolean;LCL 的是**当前节点**,所以
    `if Tree.Selected <> nil` 根本编译不过。现在 `Selected` 是节点,按下标的那个叫 `NodeSelected[]`。
  - **`OnDragOver`**。以前被树内节点拖动的否决事件占着,而它压在基类本来就提供的
    LCL 拖放钩子上 —— 于是树是唯一一个**不能当 LCL 放置目标**的 TTy 控件。
    树内那个改叫 `OnNodeDragOver`;`OnDragOver`/`OnDragDrop`/`OnStartDrag`/`OnEndDrag`/
    `DragMode`/`DragCursor` 回来了。
- **`TTyVirtualImageList.Draw` / `TTyGlyphImageList.Draw` 改用 LCL 的参数顺序**
  `(Canvas, X, Y, Index, Enabled)` —— 注意最后一个是 **Enabled**,不是 Ghosted,含义相反。
  带尺寸的那个形式改叫 `DrawIndex`。**刻意不保留 4 个 Integer 参数的重载**:
  让旧调用点编译失败,好过让它编译通过而把坐标和下标对调。
- **`TTyScrollBox.ScrollBy` 现在滚动的是视图。** `TScrollingWinControl` **重写**了它做这件事,
  我们没有 —— 于是移植过来的 `Box.ScrollBy(0,-50)` 落到了 `TWinControl` 的**搬子控件**版本上:
  同名、同参数个数、同类型,零编译错误。它把所有子控件(**连两个滚动条一起**)整体位移,
  而滚动偏移字段纹丝不动;下一次量程刷新把移位后的子控件量成更小的范围,滚动条和滑块一起坏掉。
  搬子控件那个语义仍在,走 `inherited ScrollBy`。
- **`TTyToolBar.Indent` 只管横向了,纵向内距是新的 `ContentPadY`。** LCL 的 `Indent` 是第一个
  工具前面的横向间隙;我们的**同时**是顶部内距,而且工具条高度算成 `Indent*2 + 行高`。
  于是 `Indent := 24` —— 一个再普通不过的 LCL 值,用来让开一个 logo —— 会让工具条**凭空高 48px**、
  所有工具往下挪 24px。`ContentPadY` 默认 4(= 原来的默认值),所以**没设过 `Indent` 的工具条
  一个像素都不变**;设过的会拿回 4px 的纵向内距。
- **`TTyCheckGroup` / `TTyRadioGroup` 的多列排布默认改为行优先**(新属性 `ColumnLayout`,
  默认 `clHorizontalThenVertical` = LCL 的默认)。以前硬写成列优先,于是一个 6 项 2 列的分组
  在 Lazarus 里读作 `1 2 / 3 4 / 5 6`,在这里读作 **`1 4 / 2 5 / 3 6`** —— 用户的选项列表被静默重排。
  要旧排布写 `ColumnLayout := clVerticalThenHorizontal`。**单列分组(默认 `Columns = 1`)不受影响。**
- **`TTyListBox.Items` 的类型由 `TStringList` 改为 `TStrings`**,于是 `LB.Items := Memo.Lines` 编译得过。
- **`TTyColorBox.Style` 现在真的组合调色板了。** 属性面板给了它、`.lfm` 存了它,而 setter
  **把每一个取值都扔掉**。八个集合成员现在全部生效(标准色/扩展色/系统色/自定义槽/无色/默认色/
  精选名字/包含 `clNone`);颜色名读 LCL 自己的资源串,所以是**翻译过的**。
  默认值刻意**不照抄 LCL** —— 它逐字节复现现有那 16 个精选颜色,否则每一份省略该行的 `.lfm`
  都会被重新组合成另一套调色板。下拉形态仍锁定,要改走 `TTyComboBox(Box).Style`。
- **`TTyCheckComboItemState.Checked` 改为 `State: TCheckBoxState`**(并新增 `Enabled`),
  与 LCL 的 `TCheckComboItemState` 一致。直接操作状态对象的代码要改;走 `Checked[]` 属性的不受影响。
- **`TTyPaintPanel` 的设计期落点尺寸由 185×41 改为 105×105。** 一个绘图面以信箱条的形状落下来,
  画什么都被裁掉。已有 `.lfm` 带着显式尺寸,不受影响。
- **`TTyColorButton.Caption` 现在解析 `&` 助记符**,和同一张窗体上其它按钮一致(以前它把 `&` 原样画出)。
- **`TTyGlyphLayout` 新增 `glRight` / `glBottom`**(追加在末尾,已有序号不变);
  `HasGlyphSource`(protected)改名为 `CanShowGlyph`(public)。

### 新增 — 文本输入控件补上 LCL 的成员

- **`TTyMemo.Alignment`**:每一条可见行的水平对齐。居中的多行文字块从前**用任何办法都做不出来**,
  主题也不行。绘制与**点击命中**共用同一个偏移,不会点在一处、落在另一处。
- **`TTyMemo.CharCase`**:打字与赋值都强制大小写,复用输入框那套折叠规则。
- **`Modified`(`TTyEdit` / `TTyMemo`)**:用户改过为 `True`,程序化赋值之后回到 `False` ——
  这个区分是应用层用 `OnChange` **搭不出来**的(两种情况它都触发)。用来驱动"保存"是否可用、
  关闭前要不要提示。
- **`TTyEdit.EchoMode`**:`emNormal` / `emPassword` / `emNone`(什么都不显示),与 `PasswordChar`
  双向联动。`emNone` 从前没有任何等价写法。
- **多播 `OnChange`**(`AddHandlerOnChange` / `RemoveHandlerOnChange`,两个控件都有):库内或框架层
  想观察一个输入框,不必再把应用唯一的那个 `OnChange` 抢走,两个观察者也能共存。
- **`TTyMemo.CaretLine` / `CaretCol` / `SetCaret` 变成公开的**:光标在第几行第几列 ——
  状态栏那句"Ln 12, Col 4"、跳转到行、错误高亮,从前都得先派生一个子类才够得着。
- **无障碍角色**:`TTyEdit` / `TTyMaskEdit` / `TTyMemo` / `TTyLabel` 构造时声明自己是什么。
  自绘控件没有可供读屏软件回退的原生对等物,不声明的话整个文本输入族对辅助技术都是不透明的。

### 修复 — 渐变容器上的控件像挖了个洞

面板或容器的背景是**渐变**时,坐在它上面的窗口化控件(速度按钮、勾选框、开关、滑杆、
各种仪表……)会自己重建父级背景 —— 而重建出来的是**一整块纯色**。于是控件占的那块矩形
在渐变里格格不入,离渐变另一端越远越刺眼。现在控件取的是渐变落在**它自己那一段**上的
切片,按位置对齐,接缝看不出来;三个以上色标的多段渐变同样正确。

只能给一个颜色的地方(窗口擦除色、圆角外的补角、禁用变暗的基准色)现在取控件**中心**
处的颜色 —— 从前一律取渐变的最后一个色标,哪怕控件坐在渐变的起点上。

### 修复 — 掩码框的两个删除入口绕过掩码

`InjectBackspace` / `InjectDelete` 会从掩码框的显示串里挖掉一个**原始字符**,掩码字面量一并挖走 ——
于是内容不再符合它自称在强制的掩码。键盘上的退格/删除一直是对的,这两个方法不是。
(与 `Ctrl+V` 从前那个洞同一个形状。)

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
- **文件重命名(F2)之后列表会重新读盘。** 上一版把 `Refresh` 改名成 `UpdateView` 之后,
  提交编辑那一句 `Refresh` **静默落到了 `TControl.Refresh` 上** —— 磁盘上改了,行里还是旧名字。
- **滑块的刻度终于画出来了**:`TickMarks`(上/下、左/右、两侧)、`TickStyle`
  (无 / 自动 / 手动)、`SetTick`/`ClearTicks`/`TickCount`,以及 `Reversed`(反向刻度)。
- **进度条**:`Step`/`StepIt`/`StepBy` 步进、`BarShowText` 在条上显示百分比
  (模板可配,`BarTextFormat`)、`Orientation` 支持四个方向(含从右往左、从上往下)。
- **`TTyScrollBar.LargeChange` 现在有人读了** —— 以前点滚动槽永远翻一整页,
  宿主设的翻页量到不了任何地方。
- **微调框补齐了一批编辑期成员**:`Text`(读到的是**还没提交的**输入缓冲)、`CaretPos`、
  `Modified`(程序赋值会清零 —— 它回答的是"用户动过没有")、`EditorEnabled`
  (锁住键入但保留箭头)、`ValueEmpty`(空白态)、`TextHint`,以及可覆写的
  `GetLimitedValue`/`ValueToStr`/`StrToValue`。
- **`TTyUpDown` 新增 `OnChanging` / `OnChangingEx`**:可以否决一次步进,
  `OnChangingEx` 还能看到**将要变成的值和方向**。另有 `MinRepeatInterval`(长按重复的下限)。
- **文件树补齐**:`Root`(把树限定在一个目录下)、`ObjectTypes`、`Path`、`FileSortType`
  与 `OnSortCompare`(自定义排序)、`OnAddItem`(逐项否决)、`UseBuiltinIcons`;
  文件列表同上,外加 `AutoSizeColumns`、`MaskCaseSensitivity`。
  树 / 列表 / 过滤下拉之间可以互相关联(`Tree.ShellListView`、`List.ShellTreeView`、
  `Combo.ShellListView`),点一边另一边跟着走。
- 名称对齐:`TTyCalendar.DateTime`、`TTyMaskEdit.EditMask`、`TTyMemo.Append`、`TTyEdit.Clear`、
  `TTyListBox` 与 `TTyComboBox` 的 `Clear`/`AddItem`/`Count`/`ItemRect` 等一整套列表方法。

- **`TTyShape` 只认它真正盖住的像素了。** 以前圆形/椭圆/菱形/直线都按**整个外框**吃点击,
  于是圆形四角后面的控件永远点不到。现在按形状本身判定(边框宽度也算在内),
  另外公开了 `PtInShape` 供宿主自己查。
- **`TTyStarShape` 同上,而星形是这件事最严重的地方。** 五个尖角之间有五道很深的凹口,
  外框里一大片是**根本没画过的画布** —— 以前控件对这些位置一律回答"是我的",
  于是**任何压在星角背后的控件都点不到**。现在按形状判定,并公开 `PtInShape` / `StarGeometry`。
- **`TTyArrow` 新增三角形箭头**(`Shape := tasTriangle`),角度由 `ArrowPointerAngle` 控制
  (与 LCL 的 `TArrow` 同名同默认值 60°)。以前本库只画得出块状箭头,
  移植过来的窗体想要的那个方向三角形**根本画不出来**。默认仍是块状箭头 ——
  改默认值会让所有现有窗体上的箭头静默转向。
- **`TTyPanel.BorderWidth` 现在真的留出内距了。** 基类 republish 了它,但 `TWinControl`
  **根本不读**这个值 —— LCL 里那圈内缩全靠 `TCustomPanel` 自己做。于是属性面板给了你
  一个 8px 的内边距,容器把它当空气。
- **面板可以当停靠站点了**:`DockSite`、`UseDockManager` 与整套 `OnDockDrop`/`OnDockOver`/
  `OnStartDock`/`OnEndDock`/`OnUnDock`/`OnGetSiteInfo`/`OnGetDockCaption`。
  后四个在上游是 protected,**以前根本没有任何途径能用到**。
- **拖动重排标签页不再让页头和页体错位**(选中钉在位置上,而只有页头听话);
  **把一页移到另一个 `TTyPageControl`,旧的那个不再继续把它算在自己名下**
  (反注册挂在"被释放"上,而不是"换了父控件")。
- **状态栏能自动显示提示了**:`AutoHint` 把 `Application.Hint` 写进 `SimpleText` 或第 0 格,
  `OnHint` 可整段接管。这也让**上一版做的菜单项 `Hint`** 终于看得见 —— 菜单一直在发布,
  只是库里没人接。另有 `GetPanelIndexAt`、以及 `Style := psOwnerDraw` + `OnDrawPanel`
  (状态格从前只能是纯文字)。
- **列头段落有了约束与隐藏**:`MinWidth`/`MaxWidth`/`Visible`/`InsertSection`。
  四条改宽路径(setter、整条写入、插入、**实时拖动**)走同一个钳制 ——
  setter 认、拖动不认的限制不叫限制。
- **菜单项的 `ShowAlwaysCheckable` 有人读了** —— 以前只看 `AutoCheck`,而那个标志**同时**
  让菜单项自己翻转,很多应用并不想要。
- **按钮补上 `Alignment`(标题对齐)与 `ShowAccelChar`。** `'AT&T'` 从前会画成 `'ATT'`
  **并且**莫名其妙多出一个 Alt+T 快捷键,唯一的躲法是在每个赋值点把 `&` 写两遍。
  另有 `GlyphLayout` 新增右侧/下方(`more ▾` 那种尾随图标从前任何设置都做不出来)、
  逐按钮的 `Spacing`、public 的 `CanShowGlyph`、以及 `TTySpeedButton.FindDownButton`
  (分组代码一直只会遍历兄弟去**弹起**它们,想读回哪个被按下得自己写一遍类型扫描)。
- **勾选框/单选钮的 `Alignment`** —— 注意这是 LCL 的含义:**指示器在哪一侧**,不是标题对齐
  (`TTyGroupBox.Alignment` 才是标题对齐)。同一个词两个主语。
- **分组控件补上逐项控制**:`Buttons[]`(逐项的 `Hint`/`PopupMenu`/`Font`/`Enabled` 从前够不着)、
  `CheckEnabled[]`(灰掉某一行 —— "这个选项你的版本没有")、`OnItemClick`、`OnItemEnter`/`OnItemExit`。
  **方向键现在能在单选组里移动了** —— 以前箭头**什么也不做**,键盘用户只能一路 Tab,
  而 Tab 配空格会**沿途改掉每一个经过的选项**。方向键跳过禁用项、到头停住。
  分组自己的 `OnKeyDown`/`OnKeyUp`/`OnKeyPress` 也终于会触发(分组从不持有焦点,
  这几个槽以前装了也白装)。
- **`TTyColorButton.ButtonColor`**(LCL 的名字**和类型**)—— 从前把一个 `TColor` 赋给
  `SelectedColor` 会被当成 ARGB 读,颜色静默变成另一个;另有 `OnColorChanged`(与我们的
  `OnColorChange` 只差一个字母,读起来像"这个事件不存在")。
- **`TTyGroupBox` 的 `ClientWidth`/`ClientHeight`** —— 移植过来的 `.lfm` 里钉客户区尺寸的那两行
  以前直接丢失。
- **列表框**:`OnSelectionChange(Sender; User)` 能区分用户点选与代码赋值(配 `Lock`/`Unlock`)、
  `ExtendedSelect`(触屏上唯一可用的多选方式)。
- **勾选列表框**:三态 `State[]` + `AllowGrayed`、`ItemEnabled[]`(禁用行**看上去也是禁用的**)、
  `Toggle`、`CheckAll`。顺带修掉:`Objects[]` 里放了别的对象会被读成"已勾选"(非零即真)。
- **取色框 / 取色列表**:`Colors[]` 可读**可写**、`ColorNames[]`、`OnGetColors`、
  `DefaultColorColor`/`NoneColorColor`(`clNone`/`clDefault` 从前按哨兵值原样画出来)。
  色块尺寸也从写死的 4px 改走 `--color-swatch-width` / `--color-swatch-offset`。
- **`TTyListView` 的 `Columns` / `Column[]` / `ColumnCount`** 不必再绕 `Header` 拿;
  另有 `OnInsert` / `OnDeletion`(后者是逐项 `Data` 唯一还够得着的时刻,清空和销毁时逐行触发)。
- **下拉框**:`ItemHeight`/`ItemWidth`、`TextHint`(占位提示,两种形态都画)、`ReadOnly`、
  **可写的 `DroppedDown`**、`SelStart`/`SelLength`/`SelText`/`SelectAll`、`AddHistoryItem`、
  以及 `OnGetItems` —— 懒加载下拉的**第一次点击从前什么也不会发生**,因为空列表的早退发生在
  任何钩子之前。
- **`TTyComboBoxEx.ItemsEx`**:published 的集合,**设计器可编辑、进 `.lfm`** ——
  这个控件存在的理由本身。它是唯一真相来源,`Items` 是它的投影。
- **勾选下拉框**:三态、`ItemEnabled[]`、`OnItemChange`、`CheckAll`/`Toggle`/`AddItem`/
  `AssignItems`/`DeleteItem`。
- **标签页与滚动容器补齐**:`TabRect`/`DisplayRect`/`IndexOfTabAt`/`AddTabSheet`/`ScrollTabs`/
  `PageIndex`/`PageControl`/`OnShow`/`OnHide`、`ScrollInView`/`UpdateScrollbars`、
  以及标签文字的 `WordWrap`/`VerticalAlignment`/`ShowAccelChar`。
- **无障碍**:文本控件、面板、分隔条现在会声明 `AccessibleRole` —— 自绘控件没有原生对等物
  可供辅助技术回落,在此之前整个文本族对读屏软件都是"未识别的自定义控件"。

### 新增 — 形状与图像控件补齐

- **`TTyShape` 补齐 LCL 的 15 种形状,并多了一个逃生口。** 新增圆角正方形、正菱形、
  左 / 右 / 下三角形(流程方向标、播放 / 后退图标)、朝上与朝下的五角星 ——
  这些以前**任何属性组合都画不出来**,`.lfm` 里带这些值的窗体直接打不开。
  另加 `tskPolygon` + **`OnShapePoints`**:顶点由应用给,于是六边形、标注框、V 形箭头
  这些枚举没覆盖的形状**在设计期就能用**,不必再派生一个 `TTyGraphicControl`。
  新枚举值一律**追加在末尾**,现有窗体的形状不会变。
- **`TTyShape` / `TTyStarShape` 新增 `OnShapeClick`** —— 点在墨迹上才触发。
- **`TTyStarShape` 新增 `PointDown`**,尖角朝下(LCL 的 `stStarDown`)。以前控件没有任何
  旋转手段,这个形状画不出来。
- **`TTyImage` 可以直接用共享图标集了**(`Images` / `ImageIndex` / `ImageWidth`)。
  以前一张窗体上的主题图标只能把位图复制进控件自己的 `Picture`,于是"图标集改一处、
  处处生效"和集合已经做好的按 DPI 出图全都用不上。
- **`TTyImage` 新增 `StretchInEnabled` / `StretchOutEnabled`** —— 分别管缩小与放大。
  "大图缩小、小图绝不放大"这条 LCL 的经典配方以前**无法表达**(关掉 `Stretch`/`Proportional`
  是两个方向一起关)。
- **`TTyImage` 新增 `KeepOriginXWhenClipped` / `KeepOriginYWhenClipped`**:居中时若图比控件大,
  把该轴钉在原点而不是两边对称裁掉 —— 地图、截图、扫描件的左上角终于能看见。
- **`TTyImage` 新增 `AntialiasingMode`**:`amOn` 要求插值平滑(以前**无法要求**),
  `amOff` 要求硬边,`amDontCare`(默认)行为不变。
- **`TTyImage` 新增 `OnPictureChanged` 与 `HasGraphic`**:换图时刷新尺寸标签 / 置脏标志 /
  重建缩略图,不必再轮询;判断"有没有东西可画"也不用自己去 `Picture.Graphic` 上做 nil 判断。

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
