# TTyStringGrid / TTyDrawGrid / TTyCustomGrid — 自绘数据网格

单元:`tyControls.Grid`(几何层在 `tyControls.Grid.Layout`)
示例:[examples/grid](../../examples/grid/)
设计:[2026-07-18-grid-control.md](../design/2026-07-18-grid-control.md)

三层结构,按需取用:

| 类 | 定位 |
|---|---|
| `TTyCustomGrid` | 基类:几何 / 窗格 / 滚动 / 绘制 / 主题。**不规定数据从哪来** |
| `TTyDrawGrid` | 纯自绘:内容由 `OnGetCellText` 现问宿主要 —— 天然虚拟,百万行不占内存 |
| `TTyStringGrid` | 完整体:自带**稀疏**单元格存储 + 二维光标 + 键鼠导航 + 单元格编辑 |

## 快速开始

```pascal
uses tyControls.Columns, tyControls.Grid;

var c: TTyColumn;
begin
  c := Grid.Header.Columns.Add as TTyColumn;
  c.Text := '产品';  c.Width := 120;
  c := Grid.Header.Columns.Add as TTyColumn;
  c.Text := '金额';  c.Width := 100;  c.Alignment := taRightJustify;

  Grid.RowCount := 200;
  Grid.Cells[0, 0] := '云主机';
  Grid.Cells[1, 0] := '1285.00';
  Grid.FixedCols := 1;        // 冻结首列:横向滚动时它钉住不动
end;
```

## 主要属性

| 属性 | 说明 |
|---|---|
| `Header` | 列模型(`TTyHeader`),含 `Columns` 集合、列头高度、排序列、自动适宽列 |
| `RowCount` | 数据行数。拉到一百万也没关系 —— 只绘制可视窗口内的几十行 |
| `DefaultRowHeight` | 统一行高(逻辑像素) |
| `FixedCols` | 冻结在左侧、**不随横向滚动**的列数 |
| `FixedRows` | 冻结在顶部的数据行数(列头带另计) |
| `ShowIndicator` / `IndicatorWidth` | 最左侧的行号/行头槽 |
| `GridLines` | 单元格格线。颜色取 `TyGridLine`,主题没定义则退回本体 `border-color` |
| `Cells[列, 行]` | **稀疏**存储:只有写过的格才占内存;写空串即删除该条目 |
| `Objects[列, 行]` | 挂在这一格上的任意对象("这一行是哪条记录")。网格**不拥有**它:不释放、不复制、不流式化;设 `nil` 即取下。排序 / 插删行 / 换行 / 拖行都带着它走。**不进撤销栈** —— 见下面《对象槽与撤销》 |
| `Cols[列]` / `Rows[行]` | 整列 / 整行的 `TStrings` **活视图**(可读可写、可赋值)。`Memo.Lines := Grid.Cols[2]`、`Grid.Rows[3] := MyList`、`Rows[r].CommaText` 都能用。赋值**不改网格结构**,见下面《整行整列赋值》 |
| `Col` / `Row` | 当前单元格(二维光标) |
| `Options` | 行为开关的集合(`TTyGridOptions`),对标 LCL 的 `TCustomGrid.Options`。设计器里一次看全所有交互开关 —— 见下面《`Options` 与 LCL 标志对照》 |
| `ReadOnly` | 整表只读:**用户手势写不进数据**——编辑器开不出来,粘贴被拒,剪切退化为复制,填充柄消失(等价于 `Options` 里去掉 `goEditing`)。程序化写入(`Cells[..] :=` 等)不受管 —— 边界详见下文《`ReadOnly` / `goEditing` 的边界》 |
| `SortColumn` / `SortDirection` | 当前排序列与方向(只读;用 `SortByColumn` / `ToggleSortColumn` 改) |
| `ShowFooter` / `FooterHeight` | 底部汇总带 |
| `FixedRowsBottom` | 冻结在**底部**的显示行数(与 `FixedRows` 对称)。常见用途是把合计行钉在视口下沿 |
| `FixedColsRight` | 冻结在**右侧**的列数(与 `FixedCols` 对称) |
| `ShowRowNumbers` | 在行头槽里画行号(按**显示序**,排序后屏幕第一行仍是 1)。需要 `ShowIndicator` 也打开 |
| `ShowGroupSubtotals` | 分组行上按列显示小计(默认开)。哪些列有小计由 `SetColumnAggregate` 决定 —— 与汇总带同一份配置 |
| `ShowFilterButtons` | 列头上显示筛选漏斗,点开是带搜索框与逐值计数的下拉 |
| `MinEditorWidth` | 编辑器的最小宽度(逻辑像素)。0 = 完全跟着格走。设大于 0 后,窄列上的编辑器会向右加宽到这个宽度 —— 加宽的是**编辑器**,列宽一点没动,也不会越过网格右缘 |
| `SelectionMode` | `gsmCell`(默认)/ `gsmRow` / `gsmColumn` |
| `Images` | `gcdImage` 用的图像集(`TTyVirtualImageList`) |
| `OnGetRowHeight` | 逐行行高。**接了它才启用可变行高**;不接则全表等高,几何层走整除快路径(百万行时省下一个百万项的前缀和数组) |
| `SortKind` | `gskText` 还是 `gskNumber`。数值列用文本排会得到 `'10' < '9'` |
| `DefaultEditorKind` | 默认编辑器种类,见下表 |
| `DefaultColWidth` | 新建列的宽度(`InsertColumn` / `InsertCols` 用它起宽)。不设时跟着主题的 `--column-width` 走,与 `DefaultRowHeight` 同一套规则。**不追溯改已有列** |
| `ColWidths[列]` | 列宽(逻辑像素),`RowHeights[行]` 的列轴对偶。写入的钳制与拖动改宽完全一样 |
| `GridWidth` / `GridHeight` | 全部列 / 全部行加起来有多大(设备像素)。用来判断内容有没有溢出,或者把面板收到刚好包住表格 |
| `LeftCol` / `TopRow` | 视口左上角那一格(列下标 / **显示位置**)。可读可写;写它只挪视野,**不动光标**——这正是它相对 `ScrollIntoView` 的价值 |
| `VisibleColCount` | 视口里现在装得下几列,`VisibleRowCount` 的列轴对偶 |
| `AutoFillColumns` | 让**每一列**分掉多余的宽度,按各自的 `SizePriority` 加权。与 `hoAutoResize` + `AutoSizeIndex` 的区别:那一对只让**指定的一列**吸收剩余宽度 |
| `ScrollBars` | `ssNone` / `ssHorizontal` / `ssVertical` / `ssBoth` / `ssAuto*`。存储仍是 `VertScrollBarMode` / `HorzScrollBarMode` 那一对(现已 published),这个是 LCL 同名同类型的视图 |
| `ShowFocusCell` / `FocusRectVisible` | 焦点格要不要铺一层区分底色(`TyGridActiveCell`;同一个存储,后者是 LCL 的名字)。**默认 True** —— 两个属性一直都写着 `default True`,但构造函数从来没设过它,所以在此之前出厂的网格里这层底色是熄的;`Options` 的出厂值断言把它照了出来。`Options` 里的对应位是 `goDrawFocusSelected` |
| `HideSelectionWhenInactive` / `FadeUnfocusedSelection` | 失去焦点时选区变淡(同上)。**现已 published** |
| `Modified` | 自建表 / 上次装载以来有没有被改过。收口在 `Cells[]` 与结构性增删行,所以粘贴、填充柄、撤销、勾选框、CSV 装载都算数。存过盘之后宿主自己写 `False` 复位 |
| `EditorMode` | 开/关编辑器的**一个布尔**(读 = `Editing`;写 `False` 是**提交**,不是丢弃)。工具栏按钮要绑的就是它 |
| `InplaceEditor` | 此刻真正在用的编辑器(没在编辑时 nil)。注意 `Editor` 恒指内建的那个 `TTyEdit`,哪怕当前编辑的是下拉列表格 |
| `SelectedColumn` | 光标所在那一列的列对象 |
| `RangeSelectMode` | `rsmMulti`(默认,= 从前的行为)/ `rsmSingle`。**默认与 LCL 不同**是有意的:本库一直无条件支持离散多选,改默认会从每个既有窗体上悄悄拿掉一个功能 |

### 编辑器种类

| 种类 | 行为 |
|---|---|
| `gekNone` | 该格只读,开不了编辑 |
| `gekText` | 普通文本框 |
| `gekNumeric` | 右对齐;提交时校验,非法值不写回 |
| `gekCheckBox` | **不弹编辑器** —— 点方块 / 空格 / F2 直接切换。读值宽松(`1`/`true`/`yes`/`是` 都算勾上),写回统一成 `1`/空串 |
| `gekPickList` | 下拉选取,候选来自 `OnGetPickList`;**选中即提交** |
| `gekDate` | 弹日期选择器 |
| `gekColor` | 弹取色对话框,值存 `#RRGGBB` |
| `gekSpin` | 数值微调(带上下按钮),范围取列的 `MinValue` / `MaxValue` |
| `gekSlider` | 滑动条,范围同上。编辑时自带数值读数,拖到哪儿一眼看得见 |
| `gekRating` | **不弹编辑器** —— 点第几颗星就是几分(与勾选框同一种手感) |
| `gekMemo` | 多行文本,编辑器向下撑开 |
| `gekMask` | 掩码输入,掩码取列的 `EditMask` —— 交给 [`TTyMaskEdit`](maskedit.md) 解释,**写法就是 LCL / Delphi 的掩码语言**(`0` 必填数字、`9` 可选数字、`L` 字母……);`#` 会被拒,详见 [maskedit.md 3.3](maskedit.md#33-与-lcl-的两处故意不同) |
| `gekTime` | 只选时间 |
| `gekPassword` | 输入时打点 |
| `gekCalculator` | 带计算器的数值输入 |
| `gekEllipsis` | 文本 + 右缘一个 `…` 按钮;点它走 `OnEllipsisClick`,宿主爱弹什么对话框弹什么。这是"自定义编辑"的一等公民入口 |

### 单元格显示方式

与编辑方式**正交**——一个格可以显示成进度条,双击仍按数值编辑。经 `OnGetCellDisplay` 逐格指定:

| 显示 | 说明 |
|---|---|
| `gcdText` | 默认:文字 |
| `gcdProgress` | 进度条,值取 0..100(借 `TyProgressBar` 的 token) |
| `gcdRating` | 评分标记,值取 0..5 |
| `gcdImage` | 图片,值是 `Images` 里的索引 |
| `gcdButton` | 画成按钮,点击走 `OnCellButtonClick` |
| `gcdColor` | 画成色块(值是 `#RRGGBB`)。不这么做的话那一列看起来就是一堆脏数据 |

## 主要事件

| 事件 | 用途 |
|---|---|
| `OnGetCellText` | (`TTyDrawGrid`)虚拟模式下现取单元格文本 |
| `OnSelectCell` | 光标即将移动;`ACanSelect := False` 可否决 |
| `OnGetEditorKind` | **逐格**指定编辑器种类(比如金额列用 `gekNumeric`、主键列用 `gekNone`) |
| `OnCellEdited` | 编辑提交前;`AAccept := False` 可否决写回 |
| `OnCompareCells` | 自定义排序比较;置 `AResult` 即接管该列 |
| `OnGetPickList` | `gekPickList` 的候选项 |
| `OnFilterRow` | 逐行过滤;在列过滤的结果上再否决 |
| `OnDrawCell` | **完全接管**某格绘制(置 `AHandled`);背景与选中底色已由控件铺好 |
| `OnGetCellHint` | 逐格提示文本(悬停显示);只在换格时回调 |

## 交互

- **鼠标**:点选单元格;拖列头分隔条改列宽;滚轮纵向滚动(一格三行)
- **键盘**:方向键 / `Home` / `End` / `PageUp` / `PageDown` 移动光标;`F2` 开始编辑
- **区域多选**:`Shift+方向键` 或 `Shift+点击` 拉出矩形选区;普通方向键/点击收回一格
- **排序**:列头选项加上 `hoHeaderClickAutoSort` 后,点列头即 升序 → 降序 → 取消
- **过滤**:`SetColumnFilter(列, 文本)` 做包含匹配(不区分大小写);`OnFilterRow` 可逐行否决
- **剪贴板**:`Ctrl+C` / `Ctrl+X` / `Ctrl+V` / `Ctrl+A`。制表符分隔 = Excel 剪贴板格式,可直接互粘。`ReadOnly` 下 `Ctrl+V` 被拒、`Ctrl+C` 照常、`Ctrl+X` 退化为复制(剪贴板照拿选区,表里一格不清);剪切一片 = 一条撤销记录
- **汇总**:`SetColumnAggregate(列, gagSum/gagAvg/gagMin/gagMax/gagCount)`;**只统计筛选后可见的行**,非数值格跳过
- **列头筛选**:`ShowFilterButtons := True` 后列头出现 ▾,点开是 Excel 式的下拉:
  搜索框 + 逐值行数 + `(全选)` + `(空白)` + 确定/取消。候选与计数都取自**全部数据行**
  (不受本列自身筛选影响,否则勾掉一个值它的计数变 0、就再也判断不出该不该勾回来)。
  勾选状态按**值**记而不是按列表下标 —— 搜索框会 narrow 列表,按下标记账会把勾打到别的值上。
  取数用 `DistinctColumnValueCounts`
- **填充柄**:选区右下角的小方块,往下拖把选区的值铺开 ——
  单格复制、整数等差外推、其余按源区循环重复;`OnFillCells` 可接管做自定义序列。
  只做纵向:横向拖柄少见得多,而半成品的可供性比没有更糟。
  `ReadOnly` 下柄不出现;逐格/逐列只读的目标格被跳过(位置阶梯不乱)
- **列宽/列序**:拖列头右边缘改宽;拖列头本体换位(需 `hoDrag` + `coDraggable`,位移超阈值才生效)
- **分组**:`GroupByColumn(列)` 在显示序里插入**合成分组行**(带成员计数),点分组行折叠/展开。折叠状态按**分组值**记账,重排后不会张冠李戴。
  多级请用 `GroupByColumns([地区列, 城市列])`(从外到内),分组行按层级缩进;
  折叠状态按**层级路径**记账 —— 按单个值记的话,不同地区下的同名城市会一起折叠。
  分组行上还按列显示**小计**(`ShowGroupSubtotals`,默认开;`GroupAggregateValue` / `GroupFooterText` 取值)——
  统计按组的**成员数据行**走而不是显示序,所以折叠着也算得出来
- **版式持久化**:`SaveLayoutToString` / `LoadLayoutFromString` 把列宽、列序、
  可见性、排序键、四向冻结数存成一个字符串;存到哪由宿主决定。
  读回来是**全有或全无**:版本认不出、字段不是数字、列数对不上,一律返回 False
  且**一点不改**现状 —— 半套版式比完全不还原更难排查。
  **不含行高与筛选**:行高可以有 RowCount 那么多条(那是数据不是版式);
  筛选是"此刻想看什么",不该被版式一并复活
- **排序模式**:`SortMode` 默认 `gsmDisplay`(只换显示序,数据不动)。
  设成 `gsmData` 后,排序会像 Excel 那样**真的把数据换位置**(文字、逐格属性、
  行高一起搬),排完显示序 == 数据序 —— 于是"排过序就不让合并/不让拖行"那几条
  限制自动解除。有筛选/分组/虚拟数据源时自动退回 `gsmDisplay` 的行为
  (被筛掉的行一起搬 = 数据损坏;虚拟源下控件根本不持有数据)。
  物理排序**是可撤销的**,一次 Ctrl+Z 退回排序前 —— 这也是它必须建立在撤销之上的原因
- **撤销 / 重做**:`Undo` / `Redo` / `CanUndo` / `CanRedo` / `ClearUndo` / `UndoLimit`
  (默认 100 条,0 = 关掉)。Ctrl+Z / Ctrl+Y 已接在键盘上。
  **退回来的不只是文字**:底色、文字色、只读、合并跨度、行高、整表清空
  都一起退回原状 —— 否则撤销之后会得到一个**从未存在过的状态**
  (文字回来了、涂的颜色留在别处)。
  做法是每种存储各有一个记录点,而不是给每个功能各写一段:
  改数据走 `SetCells`,行数走 `SetRowCount`,行高走 `SetRowHeights`,
  逐格属性走属性存储的"即将改动"通知。**所有**改这些东西的路径都得经过它们。
  **一次批量操作 = 一条记录**:事务边界直接用 `BeginUpdate`/`EndUpdate` ——
  凡是值得"一次重画"的批量操作,也正是值得"一次撤销"的操作。
  粘贴一片、剪切一片、一次插/删多行、导入一份 CSV,都是**按一次** Ctrl+Z 全退回。
  单条记录过大(往十万行灌数据那种)时**整条作废并清空栈**:
  半条撤销记录还原出来是一张四不像的表,比"这一步撤销不了"危险得多。
  唯一不进撤销栈的是排序键与筛选条件 —— 那是"我此刻想怎么看",不是数据
- **编辑器微调**:列上的 `DropDownWidth` 单独放宽 `gekPickList` 的下拉(0 = 跟列宽);
  `OnGetEditorProp` 在编辑器建好之后、交回调用方之前触发,拿到的是真正那个控件 ——
  想改字体/限长/宽度都来得及,不必为了一点微调去写整个 `OnCreateEditLink`
- **行拖动**:在**行头槽**里按下并拖过阈值即可重排行(与列头拖列对称;
  单元格上是框选,不抢那个手势;行高分隔线优先)。`OnRowMove` 可否决。
  排过序/分过组/藏过行时**拖不动** —— 显示序不是数据序时,把行拖到某个屏幕位置
  没有意义,松手排序就会把它放回去
- **合并**:`MergeSelection` 由网格自己从选区算跨度。宿主**别**自己算 ——
  选区矩形活在显示序空间,而 `Selection` 给的是数据行坐标,两者之差不是"几行"
  (排过序的表上这么算会吞掉几十行,真实发生过)。
  合并块记的是一段**数据行**,只在这段行连续升序显示时成立;排序打散它时它自动失效,排回来又恢复
- **合并**:`MergeCells(列, 行, 跨列, 跨行)`;基准格跨满整区,被覆盖格无矩形,点区内任意处都归基准格
- **行列增删**:`InsertRow` / `DeleteRow` / `InsertColumn` / `DeleteColumn`,内容随之整体搬移
- **清空**:分**结构**与**内容**两类,名字必须分得开 ——
  `ClearRows` / `ClearCols`(无参,返回是否真清了什么)删掉全部行/列,与 LCL 同义;
  `ClearRowContents(起, 几行)` / `ClearColContents(起, 几列)` 只把一片格子写空,行列还在
  (它们从前叫 `ClearRows` / `ClearCols` —— 同名反义)
- **自动适宽**:`AutoFitColumn(列)` 取表头与**已写入**单元格里最宽的;只量写过的格,百万行空表也不扫全表
- **查找/替换**:`FindNext` / `ReplaceCells`,按**显示序**从光标之后**环绕**查找;替换跳过只读列
- **HTML 导出**:`SaveToHTMLText/File`,特殊字符转义,同样走显示序
- **CSV**:`SaveToCSVText/File/Stream`、`LoadFromCSVText/File/Stream`。含分隔符/引号/换行的字段自动加引号。
  表头行**两边都可关**(`AWriteTitles` / `AUseTitles`,默认开)—— 对应 LCL 的
  `WriteTitles` / `UseTitles`,无表头的分片文件不会再被吃掉第一条记录
- **全状态流**:`SaveToStream` / `LoadFromStream` 存的是**整张表** —— 结构(行数、
  列宽/可见性/列序、冻结数)+ 内容(按数据行序,被筛掉的行也在里面)+ 位置
  (光标、滚动、选区)。**不含**逐格颜色/批注/只读/合并(与 LCL 默认的
  `SaveOptions` 一致)。喂进来的流认不出格式会**抛异常**而不是回退去当 CSV 读
- **编辑**:`F2` 或双击进入;`Enter` 提交、`Esc` 丢弃;**光标一动就先自动提交**
- 光标走出视口时视口自动跟随(最小移动量)

## 主题 token

`GetStyleTypeKey` 返回 **`'TyGrid'`**。网格自成一套键,**不借用树/列表的键** —— 借来的键在外观主题层
够不着,而且改它会波及那些控件。

`TTyDrawGrid` 与 `TTyStringGrid` **都不重写** `GetStyleTypeKey`,三个类一律解析 `TyGrid` 及下面这套
子部件键。这个"借用"是对的:它们是同一个网格的三层能力切片,画的是同一批部件,拆成三个键只会逼着
皮肤把同一套规则抄三遍。

下面每个键都是绘制路径**真的会解析**的(解析时**带上本控件的 `StyleClass`**,所以 `TyGridCell.compact`
这类变体在子部件上一样管用):

```
TyGrid                      整体表面 / 边框 / 字体
TyGridCell                  正文单元格(:hover / :selected)
TyGridCellAlt               斑马纹的隔行底色(AlternateRows)
TyGridCellSelectedInactive  失焦时的选区底色(HideSelectionWhenInactive)—— 独立的键,
                            不写成 TyGridCell:selected:disabled,因为一个选择器只认一个 :state
TyGridActiveCell            焦点格(光标所在)—— 整行选中模式下靠它看出光标在哪一格
TyGridCellMarked            选区盖在"用户显式指定了底色"的格上时用的半透明层
TyGridFixed                 冻结区(固定行列)
TyGridIndicator             行头 / 行号槽
TyGridHeader                列头带
TyGridHeaderSection         列头分段(:hover / :selected / :active)
                            :active = 被按住的那一段,只在 goHeaderPushedLook 开着时解析。
                            **它不吃控件级的按下态**:CurrentStates 是整个表格的状态,
                            鼠标在表里任何地方按下都会带上 tysActive,若不剔掉,随便点一下
                            正文就会让整条列头换底(RenderHeaderSections 里显式减掉了它)。
TyGridHeaderGroup           分组表头带(横跨若干列的上层标题)
TyGridFilterRow             内嵌筛选行的底色与文字色
TyGridLine                  格线(读 background)
TyGridSelectionFrame        选区外框 + 填充柄(color: 是柄的描边色)
TyGridGroupRow              分组行的底色与文字色(折叠三角也用这个文字色)
TyGridSummaryRow            汇总带的文字色与字体(带底走 FillRegion 的同一个键)
TyGridCheckBox              勾选框单元格(:selected = 已勾选)
TyGridProgress / TyGridProgressFill   进度条单元格的槽与填充
TyGridRating                评分单元格里**已评**的星(读 color)
TyGridRatingEmpty           评分单元格里**未评**的空星(读 color)—— 配成淡色,
                            用户才看得出"第 5 颗还能点"
TyGridHyperlink             gcdHyperlink 单元格的链接文字色
TyGridCommentMark           批注格右上角那个小三角的颜色
TyGridButton                按钮单元格(:hover / :active)
```

度量:`--grid-row-height` / `--grid-header-height` / `--grid-indicator-width` /
`--grid-line-width` / `--grid-cell-padding`。

基层(`themes/light.tycss`)已给全套键,所以**新皮肤一条网格规则都不写也能正常显示**。

> **`TyGridGroupRow` / `TyGridSummaryRow` 现在真的被定义了。** 这两个键网格从支持分组那天起就在解析,
> 但**没有任何主题定义过它们**,于是解析出一个空样式:分组带/汇总带根本不铺底,文字色也只能回落去借
> 网格外框的颜色。现在 `themes/light.tycss` 把这件事**写出来**了,而不是留给一次静默回落。
> 两条规则目前都写成 `background: none` —— 这是**刻意保持现状**(给它们上惯例的 chrome 色调是外观变更,
> 而那一轮是纯粹的可主题化重构);皮肤想要那层底色,自己写 `background: var(--surface-chrome)` 即可。
> 字体一律不声明(与 `TyGridCell` 一致),两条带因此跟着网格自身的字体走;但**只要皮肤声明了**
> `font-name` / `font-size` / `font-weight`,两个键都会读。
> `TyGridSummaryRow` **有意不给 `border-color`**:`RenderFooter` 压根不读它,写了也是死规则 ——
> 汇总带要一条分隔发丝线,得先改代码。

## 能力一览

### 外观
- 逐格外观钩子 `OnGetCellStyle`(底色 / 文字色 / 字体 / 两轴对齐,一个钩子全包)
- 逐格**持久**外观 `CellColors[c,r]` / `CellTextColors[c,r]` / `SetRowColor`
  —— 与钩子的区别是它落盘:用户手工涂黄的格,存下来还得是黄的
- 逐格边框 `OnGetCellBorder`(四支笔各自可开可关)—— 报表的分区块粗线、小计行双线
- 斑马纹 `AlternateRows`(按**显示行号**取奇偶,排序筛选后条纹仍然隔行)
- 行号 `ShowRowNumbers`(画在行头槽里,按**显示序** —— 排序后屏幕第一行仍是 1)
- 焦点格与选区区分(`TyGridActiveCell`)
- 格线 `GridLineStyle`(none / 只横 / 只竖 / 全)+ `GridLineWidth`
  —— 线**不占布局像素**,压在边界上,列宽不因线变粗而挪位
  —— ⚠ **与 LCL 同名不同义**:LCL 的 `TCustomGrid.GridLineStyle` 是 `TPenStyle`
  (`psSolid` / `psDash` / `psDot`,即线**怎么画**);这里是线**画哪几轴**。
  故意保留这处分歧:两边枚举类型不同,移植过来的 `:= psDash` 一律**编译不过**,
  不会像别的同名冲突那样悄悄跑错;而这个属性已经流进了 .lfm,改名要拿"零安全收益"
  去换掉所有现存窗体。虚线格线是**功能请求**,不是改名 —— 格线现在是 BGRA 上的
  `FillRect`,根本没有笔。
- 表头自绘钩子 `OnGetHeaderStyle`;列头图标走 `TTyGridColumn.ImageIndex` + `Images`,
  `Header.Images` 有货时**它优先**(覆盖关系,与 `TTyListView` 同一套规则)
- 逐列的外观:`TTyGridColumn.Color`(整列底色)、`Layout`(整列**垂直**对齐;
  `Alignment` 管水平)。这两个都能在设计器里设 —— 从前只能写 `OnGetCellStyle` 事件代码

### 表头
- 分组表头 `HeaderGroups`(横跨若干相邻列的上层标题)+ `GroupHeaderHeight`
- 排序/筛选按钮**只在叶子级** —— 点分组标题不会把下面某一列排序掉
- 拖列宽 / 拖动重排 / 双击分隔线自适应列宽
- `hoHotTrack` 会让鼠标底下那一段列头点亮(主题键 `TyGridHeaderSection:hover`)。
  这个标志一直是 published 的,而网格从前**根本没读过它**
- 正在过滤的列漏斗**点亮**;多列排序时表头显示顺位徽标

### 数据与交互
- **行为开关总入口** `Options`(`TTyGridOptions`,对标 LCL `TCustomGrid.Options`):
  改行高 / 拖行 / 拖选 / Tab 走格 / 双击适宽 / 冻结列改宽 / 逐格提示 /
  截断提示 / 省略号 / 整行高亮 / 滚动带光标 / 点半露格不滚,一处全在。
  其中一半的位是 `GridLineStyle`、`Header.Options`、`ReadOnly`、`SelectionMode`、
  `ShowRowNumbers` 的**视图**(两边同步,不是第二份存储)——
  见下面《`Options` 与 LCL 标志对照》
- 多列排序:`SortByColumn` 单列、`AddSortColumn` 追加次级列(Shift+点列头)
- 排序方式**跟着列走**(`TTyGridColumn.SortKind`:文本 / 数值 / 日期)
- 排序细则:`BlanksPosition`(空值排前/后,**翻方向时位置不变**)、
  `SortIgnoreCase`、`OnCanSort`(接服务端排序)
- 过滤:条件类型化(包含 / 等于 / 开头是 / 结尾是 / > >= < <=)
  `SetColumnFilterEx`;`ColumnIsFiltered` / `FilteredRowCount`
- 分组:`GroupByColumn` + `ExpandAllGroups` / `CollapseAllGroups`,
  分组行文本走可配的 `GroupRowFormat`
- **列**的显式隐藏 `HideColumn` / `ShowColumn` / `IsHiddenColumn`
  —— 隐藏列不占宽度、不被绘制、光标也不会停上去
- 行的显式隐藏 `HideRow` / `UnHideRow` / `NumHiddenRows`
  —— 与过滤是**两回事**:过滤是条件,隐藏是事实,`ClearFilters` 不会把它放出来
- 批量:`InsertRows` / `RemoveRows` / `InsertCols` / `RemoveCols` /
  `MoveRow` / `SwapRows` / `MoveColumn`
- 每格一个对象槽 `Objects[c, r]`,以及整列/整行的 `TStrings` 活视图
  `Cols[c]` / `Rows[r]`(可赋值)—— 见下面《对象槽与整行整列赋值》
- 剪贴板:复制 / 剪切 / **智能粘贴**(按剪贴板块大小自动扩行扩列),
  事件族 `OnClipboardCopy/Paste` / `OnBeforePasteCell` / `OnAfterPasteCell`
- CSV 往返(引号内的换行不会串数据)。可选项对标 LCL:
  `AWriteTitles` / `AUseTitles`(表头行可有可无)、
  `AVisibleColumnsOnly`(**跳过隐藏列** —— 用户藏起来的列不该被导出去)、
  `ASkipEmptyLines`(空行不再变成幻影空行)。后两个默认关,保持既有行为
- 整表持久化:`SaveToStream` / `LoadFromStream` 与 `SaveToFile` / `LoadFromFile`
  存的是**整张表**(结构 + 内容 + 光标/选区/滚动位置);只要 CSV 请用
  `SaveToCSVStream` / `LoadFromCSVStream`
- `Clear` = 行、列、内容一起没(LCL 语义)。只清内容请用 `ClearCells`;
  只清一段用 `ClearRowContents` / `ClearColContents`
- `HideSortArrow` 只熄掉表头的排序指示器,**一行都不重排** ——
  接服务端排序时用它;`ClearSortColumns` 与 `SortByColumn(-1)` 会把顺序退回去
- 逐列勾选词汇 `TTyGridColumn.ValueChecked` / `ValueUnchecked`:
  一张 `'Y'`/`'N'` 的表被点一下勾选框,从前会被写进一个 `'1'` ——
  宿主的数据词汇被控件换掉了。两个都留空时行为与从前逐字节相同
- 本地化真值词 `TyGridCheckedWord`(单元级全局):出厂是哨兵
  `TyGridCheckedWordFollowRs` = 判定时**实时**读 `rsGridCheckedWord`(zh_CN 目录给
  `是`,**目录晚于单元初始化装载也生效** —— 从前 initialization 里的一份拷贝把这条
  契约废掉了,拷到的永远是英文);赋值即 override,空串 = 明确禁用。
  通用真值 `1`/`true`/`yes`/`y` 永远认

### 选择
- `SelectAll` / `SelectRange` / `SelectRows` / `ClearSelection` /
  `Selection`(**可读可写**:存下来的矩形直接赋回去即可恢复;全负矩形 = 取消选区,
  与 LCL 一致)/ `SelectedCellCount` + `OnSelectionChanged`
- 离散多选(Ctrl+点)、拖选、`SelectionMode`(格 / 行 / 列)
- 离散多选**能枚举**了:`SelectedRangeCount` / `SelectedRange[i]` / `HasMultiSelection`
  (索引 0 恒为活动矩形)。从前对外只有 `Selection`,而它只给最后那一块 ——
  宿主遍历"选区"会静默丢掉前面几片
- `ClearSelections` 是 `ClearSelection` 的 LCL 拼法(复数),同义
- 选区聚合 `SelectionSum` / `Avg` / `Min` / `Max`(非数值格跳过)
- 给整个选区上色:`SetSelectionColor` / `SetSelectionTextColor`(传 0 = 清除,
  返回改了几格)。**别自己写循环** —— 遍历选区要走显示序、跳过分组行、按数据行
  寻址(排序筛选之后颜色才跟着数据走),而且整批必须算**一次**操作,
  否则撤销是一格一格退的。这两个函数把这些都包好了

### 内嵌筛选行
- `ShowFilterRow` 打开列头下面那条带,每列一个输入位;`FilterRowHeight`(0 = 跟列头同高)
- 表达式:`>100` `>=100` `<5` `<=5` `<>x` `=x` · `a..b` 闭区间 · 其余是包含(不区分大小写)
  · `;` 分隔的多个条件之间是 **OR**(列与列之间仍是 AND)
- 半截输入(`>`、`..`、`10..`)一律**不过滤** —— 用户正打到一半时不该把整列筛没
- 输入即筛(防抖),回车立刻生效,Esc 放弃这次修改;`SetFilterText` / `FilterText` 供代码使用
- 它是**自己一条带,不是数据行** —— 行数、寻址、导出都不把它算进去
- 筛选位用的是**独立于单元格编辑器**的那个控件:两者的提交去向完全不同,
  让一个控件服务两种语义正是本控件出过事的地方

### 树形单元格
- `TreeColumn` 指定哪一列画成树(-1 = 不画),`TreeIndent` 定每级缩进
- **控件不持有树**:层级与"有没有孩子"由 `OnGetNodeLevel` / `OnGetHasChildren` 回答
  —— 与虚拟数据源同一条道理,百万行的树不必先在控件里建起来
- 折叠 = 把子行从**显示序**里去掉(复用行序间接层,不另建一套)
- `ToggleNode` / `NodeCollapsed` / `ExpandAllNodes` / `CollapseAllNodes`
- 几何是公开的(`TreeContentLeft` / `TreeToggleRect`)—— 宿主要自绘或自己做命中时,
  拿到的必须是控件正在用的那一份;命中与绘制共用同一个矩形

### 编辑
- 列级声明:`EditorKind` / `ReadOnly` / `PickList` / `Aggregate` / `Format` /
  `ValidChars` / `MaxEditLength` / `MinValue` / `MaxValue` / `EditMask`
  —— **设计期配好列,不用接任何事件**
- 内建编辑器(`TTyGridEditorKind`):文本 / 数值 / **微调** / **滑动条** / 下拉 /
  日历 / **时间** / 取色 / 勾选框 / **星级**(点第几颗就是几分,不弹编辑器)/
  **多行** / **掩码** / **密码** / **带计算器的数值**
  —— 全是把库里**现成的控件**接进来(`TTySpinEdit` / `TTyTrackBar` / `TTyMemo` /
  `TTyMaskEdit` / `TTyCalcEdit` / `TTyDateTimePicker`),不另造一套。
  另有列级 `CharCase`(输入强制大小写)。
- 走 `OnCreateEditLink` 的:省略号按钮弹任意对话框、子表格、图片选择器 ——
  这些的"编辑器"本体是宿主的业务 UI,内建反而限制人
- 逐格 `CellReadOnly[c,r]`
- 键盘手感:直接敲字进编辑(这一笔即第一个字符)、Enter 向下、Tab 按格推进折行
- 输入约束按键级过滤(非法字符**连编辑都不进**)
- 宿主自带编辑器:`OnCreateEditLink` + `TTyGridEditLink`
- 单元格类型:文本 / 数值 / 下拉 / 日期 / 颜色 / 勾选框 / 进度条 / 评分 / 图片 / 按钮
  —— **显示**方式(`TTyGridCellDisplay`)与**编辑**方式(`TTyGridEditorKind`)正交:
  一列可以显示成进度条、双击仍按数值编辑;`gcdColor` 把 `#RRGGBB` 画成色块
  (从前只有 `gekColor` 编辑器、没有显示侧,那一列看起来就是一串没格式化的脏数据)
- 换行 `WordWrap` + `OnGetCellWordWrap`;行高三件套(可写 `RowHeights[]`、
  拖行分隔线、`AutoFitRow` / `AutoFitRows`)+ 全局上下限

### 视口
- `OnTopLeftChanged` —— 视口左上角换格时触发。在此之前网格**没有任何**滚动通知,
  两个表格同步滚动 / 按可视窗口取数 / 记住滚到哪儿都只能轮询
- 按**格**触发而不按像素:我们是平滑的像素滚动,滚三个像素并不换行

### 事件
单元格级鼠标(`OnClickCell` / `OnDblClickCell` / `OnRightClickCell` / `OnCanClickCell`)、
表头(`OnHeaderClick` / `OnHeaderRightClick` / `OnColumnMove`)、
尺寸(`OnColumnSizing` / `OnEndColumnSize` / `OnRowSizing` / `OnEndRowSize`)、
内建控件(`OnCanToggleCheck` / `OnCheckBoxChange` / `OnCellButtonClick`)。

## 对象槽与整行整列赋值

### `Objects[列, 行]` —— 每格挂一个对象

```pascal
Grid.Cells[0, r]   := Rec.Name;
Grid.Objects[0, r] := Rec;          // "这一行是哪条记录"
...
Rec := TMyRecord(Grid.Objects[0, Grid.Row]);
```

**网格不拥有它。** 不释放、不复制、不写进 `.lfm`,也不写进 `SaveToStream`
(那是一个指针,存不下来)。设 `nil` 即取下。

它与这一格的底色 / 合并跨度 / 批注住在**同一条稀疏记录**里,所以
物理排序(`SortMode := gsmData`)、`InsertRow` / `DeleteRow`、`MoveRow` /
`SwapRows`、拖行**都带着它一起搬** —— 宿主不必再维护一张按行下标记账的平行表
并在每次结构变动后重新对齐。那张表正是这个属性要消灭的东西。

**代价**:那条属性记录从 64 字节变成 72 字节(x86_64 实测,净增正好一个指针,
没有伴随的"有没有设过"标志 —— `nil` 本身就是没有)。付这笔钱的只有**已经有属性的格**;
稀疏存储里没有条目的格一分钱不花,`Objects[c,r] := nil` 还会把只剩空壳的条目还回去。
一百万行、每行挂一个对象 = 一百万条记录 ≈ 72 MB + 键的开销 —— 这与
"一百万行的表本身几乎不占内存"是两码事,按行挂对象的表请自己掂量。
(为它单开一张稀疏表能省下那 64 字节的共用部分,但要把排序 / 插删行 / 换行 /
拖行四条搬家路径**逐条重写一遍**,而漏搬一条的症状是"排完序拿到别人的记录"
且一声不响 —— 合并区当年就是这么漏的。共用一条记录是拿内存换正确性。)

#### 对象槽与撤销:**不进撤销栈**

这是一条明确的取舍。撤销栈是**值语义**的(它连 `TTyGridCellAttr` 的引用都不敢存,
因为那个对象会被后来的搬家就地改写),而对象槽装的是**宿主的指针**、网格不拥有它。
把它记进撤销栈,就等于允许一次 Ctrl+Z 交还一个宿主在删掉那一行时已经释放掉的地址
—— 撤销变成 use-after-free,而且是网格无从察觉的那一种。

于是:

- 挂 / 取对象**本身不是一次可撤销的操作**,不会在栈上压记录,也不会作废重做链;
- 撤销**绝不销毁**对象槽 —— 哪怕它要还原的是"当时这一格根本没有属性记录",
  也只把可撤销的字段清回默认值,把对象留着;
- 但撤销**也不把对象槽搬回原位**。撤销一次结构性编辑(插行 / 删行)之后,
  文字与属性都回到原位,而对象槽停在正向操作把它放下的地方。
  需要精确还原的宿主,请在撤销后照自己的数据重挂一遍。

### `Cols[列]` / `Rows[行]` —— 整列 / 整行当 `TStrings`

```pascal
Memo.Lines   := Grid.Cols[2];        // 读:一列变成多行文本
Grid.Rows[3] := MyList;              // 写:一次填一行
Grid.Rows[3].CommaText := 'a,b,c';
Rec := TMyRecord(Grid.Rows[3].Objects[0]);   // 对象也通过它可达
```

交出来的是**活视图**(`TTyGridStrings`),不是副本:读写都直接落到格子上,
长度跟着网格走(列视图 = `RowCount`,行视图 = 列数)。
视图对象**归网格所有**,按下标缓存 —— 同一个下标每次给同一个实例,随网格一起释放。
代价是"碰过多少个不同下标就留下多少个空壳视图",所以**别拿它遍历百万行的表**;
那条路是 CSV / 剪贴板。缓存按下标记账(与 LCL 同),删列 / 移列之后旧视图指的是
那个**位置**,不是原来那一列。

#### 长度不匹配时会发生什么

**网格的尺寸说了算,赋值绝不改网格的结构。** 与 LCL 逐字一致:

| 情形 | 结果 |
|---|---|
| 源列表比视图**短** | 前 N 格被覆盖,**后面那几格原样留着**(不清空) |
| 源列表比视图**长** | 多出来的项**丢掉**,不加行、不加列 |
| 想真的"整行换掉" | 先 `Rows[r].Clear` 再赋值 |

"赋一个短列表"在 LCL 那边从来就不是"整行换掉",移植过来的代码依赖的正是这个行为。
不在赋值里偷偷改行数/列数还有第二个理由:结构变更在撤销栈里是另一种记录,
让一次数据赋值顺手做结构变更,两者混在一起就撤不干净。

整次赋值算**一条**撤销记录(内部包了 `BeginUpdate` / `EndUpdate`)。

#### 其余约定

- `Clear` 清的是**内容**(整行/整列的文字与对象),长度不变 —— 那是网格的结构;
- `Insert` / `Delete` 抛 `EListError`(LCL 同样)。改结构请走
  `InsertRow` / `DeleteRow` / `Header.Columns`;
- `Add` 是例外,而且是必须的:`CommaText` / `DelimitedText` 的赋值走的是
  `Clear` + `Add`,所以 `Add` 往"下一个还没被 `Add` 写过的槽"里写,写满返回 `-1`
  而不抛异常(`Clear` 把这个游标归零);
- 越界**读**给空串 / `nil`,越界**写**抛 `EListError` ——
  静静丢掉一次写入是最难查的那种 bug。

## 两条不变量(改这个控件前先读)

### 1. 命中 = 矩形的逆

命中测试必须由矩形函数取逆得到(`CellAt` = `CellVisibleRect` + `PtInRect`),
这样绘制几何与命中几何在机械上就不可能漂移。

注意是 **`CellVisibleRect` 而不是 `CellRect`** —— 被冻结带盖住的那部分不该点得到。

### 2. 行序间接层

排序/过滤/分组**只置换显示序**;`Cells[列,行]`、`Col`/`Row`、编辑、选择
都按**稳定的数据行**记账。所以排序之后光标仍然盯着同一条数据(只是显示位置变了),
内容也绝不会串位。

- `OnCompareCells` 拿到的 `ARow1/ARow2` 是**数据行**
- **导出/复制一律走显示序**(所见即所得):被过滤掉的行不出现,排序后的次序被保留
- 离散选区用显示序坐标(屏幕上那几条),但 `Selection` 对外一律翻回数据行坐标

### 3. 横轴只有一个变换

RTL 之后又多了一条:**从"阅读坐标"到"屏幕坐标"的变换只有一个**
(`ToScreenRect`),它的逆是同一次反射(`ToReadingRect` / `ToReadingX`)。
凡是判据里带方向性比较符(`>` / `<`)、或者要把一个槽位钉在"某一侧"的地方,
一律先反射回阅读空间、用原来那个式子比,再反射回来 —— 式子一个字不用改,
LTR 因此逐字节不变。**不要在控件里写第二组 `if RtlLayout then ... else ...` 的坐标分支**:
每多一组就多一个"绘制翻了、命中没翻"的机会,而那正是本库反复栽过的那个跟头。

文字对齐有**两条**路径,加新的绘制点时要认清走的是哪一条:
`P.DrawText` 由画笔在 `BeginPaint` 收到的 RTL 标志统一翻(表头、分组带、分组行、页脚),
而 `DrawCellText` **不经过画笔** —— 它把文字排进自己的缓存位图,所以在函数开头
自己翻一次(单元格、行号、筛选位、换行表头)。两条都恰好翻一次,别再加第三次。

## 从右往左(RTL)

`BiDiMode := bdRightToLeft`(从窗体继承;`BiDiMode` **不 published**)之后,
整条横轴镜像:

- 第 0 列贴**右**边缘,列往左排;行头槽 / 行号也在右
- 冻结列(`FixedCols`)钉右边缘;`FixedColsRight` 那一带跑到左边
- 横向滚动条的 `Position = Min` 在**右**端(阅读起点)。
  **`ScrollX` 的语义一个字没变** —— 它恒是"正文列离开阅读起点多远",
  所以存下来的 `ScrollX` 换个方向重新加载仍然指着同一列
- 拖宽抓的是列的**左**缘,往左拖是变宽
- 表头文字、单元格文字、排序三角、筛选漏斗、树形三角与缩进、评分星、省略号按钮、
  批注角标、下拉箭头、进度条填充方向、填充柄 —— 全部换边
- `←`/`→` 跟着眼睛走(布局方向,不是文字方向);`Home`/`End` 仍是**逻辑**首尾;
  选区的锚点与对角存的是**列下标**,不镜像
- **每一处命中都与绘制出自同一个函数**,所以点到的就是画在指针底下的那一格

**这些不镜像**(是决定,不是遗漏,都有测试钉着 —— `TRtlExclusionTest`):

- **纵向滚动条仍在右边。** 网格的所有几何都画在一条原点为 x=0、宽 `ViewportW`
  的视口里,镜像就是把这条带反射到它自己身上(LTR 因此逐字节不变)。
  把条挪到左边就等于给视口一个非零原点,而现在有十来处整幅带写的是
  `Rect(0, .., M.ClientW, ..)`(行带、表头底、筛选行、格线、页脚、滚动快路径),
  每一处都要加同一个常量 —— 十来个"翻九个"的机会。
  镜像摸底文档把"条还在右边"列为**最显眼、因而最安全**的漏项(§5 第 7 条)。
- **列筛选下拉的行不镜像。** 它把每个值的计数钉在行的右端,而继承来的勾选框在行的
  阅读起点 —— 镜像会把两者叠到同一边。
> **折叠三角已经会转向了**(曾经是本节里的第三条)。字形集补上了
> `tgChevronRight` 的镜像伙伴 `tgChevronLeft`(`tyControls.Painter.pas`),
> 树形列与分组行的两处三角改走同一个 `DrawToggleGlyph`:折叠态朝**阅读前进的
> 方向**(LTR 朝右、RTL 朝左),展开态一律朝下 —— 向下是"已经展开在下面"这条
> 竖轴上的事实,与从哪一头读无关。皮肤要换这一向的字形,用 `--glyph-chevron-left`
> (与 `--glyph-chevron-right` / `--glyph-chevron-down` 同一套 v3/C5 令牌)。

## 性能笔记

- 虚拟化:只遍历可视窗口,百万行的表每帧也只画几十行
- **跨帧文本位图缓存**:单元格文字曾占渲染时间的 94%
  (每格一次 `TextSize` 做省略号测量 + 一次 `TextRect`,都是 BGRA 的重活)。
  按外观整体缓存后降到约 1/20。键含文字/字体/字号/字重/颜色/尺寸/对齐/PPI ——
  任何一项变了都是新条目,所以换主题、改列宽、切深色都不需要显式失效
- 逐格样式解析按**状态组合**记忆化:绝大多数格状态相同,整帧只解析一两次
- `GridMetrics` 整帧只算一次(`CellRect`/`CellVisibleRect`/`CellPane` 每格要问三四次)
- 排序是**稳定归并排序**;单元格用哈希表寻址(早先线性查找 + 插入排序,1000 行就卡死)
- **滚动走脏区重绘**:正文像素整体平移复用,只重画滚进来的那一条带(37ms/帧 → 5.7ms/帧)。
  正确性靠**默认作废**:`Invalidate` 一律熄灭表面新鲜度,纯滚动是唯一例外
- **批量写数据一定要用 `BeginUpdate` / `EndUpdate`**(可嵌套)。
  `Cells[c,r] := ...` 每写一格就往 LCL 送一次失效;灌 10 万行 x 9 列 = 90 万次,界面看起来就是死的。
  加锁后整批只重画一次。这是本控件**最容易踩、也最容易漏掉**的性能点

## `Options` 与 LCL 标志对照

`Options: TTyGridOptions` 是从 LCL `TCustomGrid.Options`(`grids.pas:86`)移过来的
行为开关集合。在它之前,这些开关散在四个不同的对象上 —— 格线在 `GridLineStyle`,
改列宽/拖列/列头点亮埋在 `Header.Options` 里(设计器要展开子对象才看得到),
只读在 `ReadOnly`,整行选择在 `SelectionMode`,行号在 `ShowRowNumbers` ——
而**改行高、拖行、双击适宽、"…" 截断这几条根本没有开关**。

### 三条纪律

1. **只收我们真的照办的标志。** LCL 有 32 个,这里 22 个。少掉的 10 个不是漏了:
   一个勾得动却没人理的开关比根本没有它更坏,因为用户会以为自己已经关掉了
   某个行为。`test.grid.options` 里的 `NoInertOptionMembers` 逐个成员去源码里
   找强制点,找不到就红。
2. **一半的位是视图,不是第二份存储。** `goColSizing` 就是
   `Header.Options` 里的 `hoColumnResize`,`goEditing` 就是 `ReadOnly` 取反。
   这些位**不另存一份**:`Options` 读它们时现算,写它们时推回原主。所以
   `GridLineStyle := glsNone` 之后 `goVertLine in Options` 立刻是 `False`,
   反之亦然。
3. **只增不改序。** 集合成员在 `.lfm` 里按**名字**写(`Options = [goVertLine, …]`),
   所以插入成员不会让老窗体读错;但**改名或删名**会让老窗体加载时抛
   `Invalid property value`。新成员一律追加在末尾。

### 出厂值

```pascal
TyDefaultGridOptions =
  [goVertLine, goHorzLine, goRangeSelect, goDrawFocusSelected, goRowSizing,
   goColSizing, goRowMoving, goColMoving, goEditing, goTabs,
   goDblClickAutoSize, goFixedColSizing, goCellHints, goCellEllipsis,
   goThumbTracking];
```

出厂值**逐位复刻加这个属性之前的行为**,不是复刻 LCL 的 `DefaultGridOptions`。
三处刻意与 LCL 不同(见下表 ⚠ 标记):`goDblClickAutoSize`、`goFixedColSizing`、
`goCellEllipsis` 在 LCL 里默认关,而我们一直是开的。改成 LCL 的默认值等于
给每一张现有窗体换行为 —— 这个属性是来**描述**现状的,不是来偷偷改现状的。

### 对照表

`归属` 一列的含义:

- **视图** —— 这一位在别处已经有名字了,`Options` 只是它的另一个入口,两边同步;
- **自有** —— `Options` 是这个行为唯一的开关,以前没有;
- **不收** —— 不在 `TTyGridOption` 里,理由在备注。

| LCL 标志 | 归属 | 我们的 | 出厂 | 备注 |
|---|---|---|---|---|
| `goVertLine` | 视图 | `GridLineStyle` 含 `glsVertical` | 开 | 两位 ↔ 四态,双射不丢信息 |
| `goHorzLine` | 视图 | `GridLineStyle` 含 `glsHorizontal` | 开 | 同上 |
| `goFixedVertLine` | 不收 | — | — | 我们的列头/冻结带是**主题绘制的 chrome**,分隔线取自 `TyGridHeaderSection` 的 `border-color`,不是"固定单元格的格线"。真要拆开:`RenderGridLines` 的纵向循环已经以 `M.FrozenTop` 为界,那就是现成的 seam;列头带那一段还要在 `RenderHeaderSections` 再开一处 |
| `goFixedHorzLine` | 不收 | — | — | 同上。今天顶部固定行走正文那条横线路径,而列头带的横线是无条件画的 |
| `goRangeSelect` | 自有 | `goRangeSelect` | 开 | 关掉后拖动/Shift 仍移动光标,但选区收在当前格。只管**手势**,`SelectRange` 等 API 不受影响 |
| `goDrawFocusSelected` | 视图 | `ShowFocusCell` / `FocusRectVisible` | 开 | 我们的选区**恒含光标格**(`ClearSelection` 收缩到光标),所以"焦点格总是画在选中格上",这个映射是精确的而非近似 |
| `goRowSizing` | 自有 | `goRowSizing` | 开 | 仍需 `ShowIndicator` —— 行分隔线只在行头槽里认(放在单元格上会和框选抢手势) |
| `goColSizing` | 视图 | `Header.Options` 含 `hoColumnResize` | 开 | |
| `goRowMoving` | 自有 | `goRowMoving` | 开 | 仍需 `ShowIndicator`,且排序/过滤生效时不可拖(显示序 ≠ 数据序) |
| `goColMoving` | 视图 | `Header.Options` 含 `hoDrag` | 开 | 单列还要 `coDraggable` |
| `goEditing` | 视图 | `ReadOnly` 取反 | 开 | 关掉 = 用户手势写不进数据:编辑器七条路 + 粘贴 + 剪切的清空半边 + 填充柄,全部认它。程序化写入不受管 —— 边界见《`ReadOnly` / `goEditing` 的边界》 |
| `goAutoAddRows` | 不收 | — | — | **可以做,但语义要先定。** 我们有排序/过滤/分组的显示序,在最后一行编辑完自动追加的那一行该出现在**显示序**的哪儿并不显然;而且要不要进撤销栈也得定。seam 在 `TTyStringGrid.EndEdit` |
| `goAutoAddRowsSkipContentCheck` | 不收 | — | — | 上一条的修饰位,一起等 |
| `goTabs` | 自有 | `goTabs` | 开 | 关掉后 Tab 交给对话框换焦点(不置 `Key := 0`) |
| `goRowSelect` | 视图 | `SelectionMode = gsmRow` | 关 | 三态压两态:`Options` 只在这一位**真的翻了**时才写回,所以 `gsmColumn` 不会被一次无变化的写压成 `gsmCell` |
| `goAlwaysShowEditor` | 不收 | — | — | 我们的编辑器是一个**共享的隐藏子控件**,`MoveCursor` 每次都无条件 `EndEdit`。常驻编辑器要么每格一个实例,要么重做光标移动那条路 —— 是一个独立的改动 |
| `goThumbTracking` | 视图 | 两条内嵌滚动条的 `LiveTracking` | 开 | **曾经不收**,理由是"我们的 `TTyScrollBar` 恒为实时拖动,seam 在 ScrollBar 不在本控件" —— 发布一个控件办不到的标志就是"说谎的属性"。缝已补上(`af73f18`):`TTyScrollBar.LiveTracking`(published,default `True` = 一直以来的行为)加只读 `TrackPosition`。关掉后滑块照样跟手、`OnScroll(scTrack)` 仍带着提议值发出,但 `Position` / `OnChange` / `scPosition` 推迟到松手,两种模式落在同一个终值上;方向键、翻页、滚轮**不受影响**(它们是离散步,原生滚动条也不推迟)。出厂**开**,因为滚动条出厂 `LiveTracking=True`。写的时候**两条一起写**——只写纵向那条的话横向拖动照样实时提交,属性只生效一半。且只在这一位**真的翻了**时才写:`GetOptions` 只问纵向那条,所以"纵开横关"在 `Options` 里读出来是开,无条件写回会把宿主直接设的 `HScrollBar.LiveTracking := False` 悄悄扳回去(与 `goRowSelect` 三态压两态同一个坑,`NoOpWriteKeepsAOneSidedLiveTracking` 钉着)。宿主要单独控制一条,仍可直接设 `Grid.VScrollBar.LiveTracking` |
| `goColSpanning` | 不收 | — | — | 合并格是**按需自动**的:`HasMergedCells` 看 `FMergeCount > 0`,没有合并就不走那条路径。一个开关只能用来"禁用用户显式请求的合并",没有意义 |
| `goRelaxedRowSelect` | 不收 | — | — | 我们**恒为 relaxed**:`FCol` 始终被跟踪,`SelectionMode` 的 setter 不动光标,`gsmRow` 下焦点格照样有自己的底色 |
| `goDblClickAutoSize` | 自有 | `goDblClickAutoSize` | ⚠ 开 | LCL 默认关。关掉后双击**落到普通拖拽改宽**上,不是被吞掉 |
| `goSmoothScroll` | 不收 | — | — | 我们**恒为像素级平滑滚动**(`ScrollX`/`ScrollY` 是设备像素,不按格吸附)。逐格滚动是功能倒退,不提供 |
| `goFixedRowNumbering` | 视图 | `ShowRowNumbers` | 关 | 还需 `ShowIndicator` 才有槽可画;行号按**显示序**、1 起 |
| `goScrollKeepVisible` | 自有 | `goScrollKeepVisible` | 关 | 默认视口与光标解耦(滚走了光标留在原地)。打开后滚动落定时把光标拖进新视口,横纵都管 |
| `goHeaderHotTracking` | 视图 | `Header.Options` 含 `hoHotTrack` | 关 | |
| `goHeaderPushedLook` | 自有 | `goHeaderPushedLook` | 关 | 按住的列头段画成"按下去"。**曾经不收**,理由是缺主题 token(列头段只有 `:hover` / `:selected`,按下态会退回 base 而毫无变化 —— 与其发布一个不照办的标志,不如先补缝)。缝已补上:`themes/light.tycss` 的 `TyGridHeaderSection:active` 走 `--surface-active`,只写在**基层**一份,各模式 seed 自己换。出厂**关**:这个观感以前根本不存在,默认开等于改掉每一张现有窗体 |
| `goSelectionActive` | 不收 | — | — | 我们**恒为 active**:`SetSelection` → `SelectRange` 直接写 `FCol`/`FRow` |
| `goFixedColSizing` | 自有 | `goFixedColSizing` | ⚠ 开 | LCL 默认关。关掉后冻结列(前 `FixedCols` + 后 `FixedColsRight`)的分隔线不再命中,可滚动列不受影响 |
| `goDontScrollPartCell` | 自有 | `goDontScrollPartCell` | 关 | 只管**点击**;键盘导航仍然把光标滚进视口 |
| `goCellHints` | 自有 | `goCellHints` | 开 | 总闸。关掉时连**已经挂上**的提示也摘掉 |
| `goTruncCellHints` | 自有 | `goTruncCellHints` | 关 | 放不下的文字用全文当提示。**现量不记账**:量的口径与绘制是同一个函数(`TyGridEllipsisFit`),所以"提示说放不下"与"屏幕上真加了…"不可能对不上。优先级:截断全文 < 批注 < `OnGetCellHint` |
| `goCellEllipsis` | 自有 | `goCellEllipsis` | ⚠ 开 | LCL 默认关。关掉后单行文字硬裁(末字被切一半) |
| `goRowHighlight` | 自有 | `goRowHighlight` | 关 | 高亮光标所在**整行**。底色复用 `TyGridActiveCell`(本控件自己的键)—— 代价是主题分不开"焦点格"与"高亮行",要分开得加一个 `TyGridRowHighlight` 键 |

### `ReadOnly` / `goEditing` 的边界:用户手势 vs 程序化写入

规则一句话:**用户手势写不进只读表,程序化写入不受管。** 与本库每个编辑控件的
`ReadOnly` 同义(`TTyEdit` / `TTyMemo`),也与 LCL 网格一致(它的粘贴/剪切由
`EditingAllowed` 把门,`grids.pas:11753/11768`)。

用户侧,`ReadOnly := True`(= `Options - [goEditing]`)之后:

- **编辑器七条路**开不出来(双击 / F2 / 直接打字 / 勾选框 / 评分 / 颜色 / "…")。
- **粘贴整体被拒**(`PasteFromText`,Ctrl+V 与宿主接的"粘贴"菜单同一入口),
  `OnClipboardPaste` 不触发(不请宿主否决一个不会发生的操作),不留撤销记录。
- **剪切退化为复制**(`CutToClipboard`):剪贴板照拿选区,表里一格不清 ——
  与 `TTyEdit.CutToClipboard` 同规;LCL 的网格是整个不做,我们跟自己库里的
  编辑控件对齐,不跟它。Ctrl+C 复制**始终可用**。
- **填充柄消失**(`FillHandleRect` 返回空矩形,绘制与命中同源,所以不画也点不中
  —— 画一个拖了没反应的柄是"published 却不照办"的像素版);`FillFromSelectionTo`
  的 API 直调同样被拒。

宿主侧,`Cells[..] :=`、`LoadFromCSVText`、`Undo`/`Redo` 等程序化路径**照旧可写**
—— "宿主主动调 `PasteFromClipboard` 要不要也挡"当年悬着的那个决定,答案是**挡**:
它们就是粘贴/剪切/填充这三个**操作本身**,宿主把自己的菜单项接上去,接出来的必须
还是只读表;宿主想绕开语义,走的路是 `Cells[..] :=`。

逐格 / 逐列的只读(`CellReadOnly[c,r]` / 列的 `ReadOnly`)三条路径同样认:粘贴与
剪切一直走 `EditorKindFor` 这道门逐格跳过,填充柄从前**不走**、现在同门 —— 且跳过
的只是**写入**,位置计数照走,等差外推隔着锁定格仍按位置续(10,20 铺过锁定的
第 3 行得到 30,\_,50,不是 30,\_,40)。守卫在 `tests/test.grid.pas` 的四条
`TestReadOnly*` / `TestFillSkips*`。

`TGridOptions2`(`goScrollToLastCol` / `goScrollToLastRow` / `goEditorParentColor` /
`goEditorParentFont` / `goCopyWithoutTrailingLinebreak`)整套不收:前两个是 LCL 逐格
滚动模型下的边界修补,后三个是它那套编辑器父属性继承的产物 —— 我们的编辑器走
主题,没有 `ParentColor` 这一层。

## 明确不做

XLS 原生读写、PDF 导出与打印子系统、RichEdit / HTML 富文本单元格 ——
它们是文件格式库与输出子系统,不属于网格控件本体。

预置外观样式集(对标品在控件里硬编码几千行 case 上色)也不做:
我们的等价物就是 `.tycss` + typeKey,照抄等于把皮肤职责搬回控件。
