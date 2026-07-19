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
| `Col` / `Row` | 当前单元格(二维光标) |
| `ReadOnly` | 整表只读,任何编辑都开不起来 |
| `SortColumn` / `SortDirection` | 当前排序列与方向(只读;用 `SortByColumn` / `ToggleSortColumn` 改) |
| `ShowFooter` / `FooterHeight` | 底部汇总带 |
| `FixedRows` 现已真正实现 | 前 N 个显示行钉在列头之下、不随滚动、可点击 |
| `SelectionMode` | `gsmCell`(默认)/ `gsmRow` / `gsmColumn` |
| `Images` | `gcdImage` 用的图像集(`TTyVirtualImageList`) |
| `OnGetRowHeight` | 逐行行高。**接了它才启用可变行高**;不接则全表等高,几何层走整除快路径(百万行时省下一个百万项的前缀和数组) |
| `SortKind` | `gskText` 还是 `gskNumber`。数值列用文本排会得到 `'10' < '9'` |
| `DefaultEditorKind` | 默认编辑器种类,见下表 |

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

### 单元格显示方式

与编辑方式**正交**——一个格可以显示成进度条,双击仍按数值编辑。经 `OnGetCellDisplay` 逐格指定:

| 显示 | 说明 |
|---|---|
| `gcdText` | 默认:文字 |
| `gcdProgress` | 进度条,值取 0..100(借 `TyProgressBar` 的 token) |
| `gcdRating` | 评分标记,值取 0..5 |
| `gcdImage` | 图片,值是 `Images` 里的索引 |

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
- **剪贴板**:`Ctrl+C` / `Ctrl+V` / `Ctrl+A`。制表符分隔 = Excel 剪贴板格式,可直接互粘
- **汇总**:`SetColumnAggregate(列, gagSum/gagAvg/gagMin/gagMax/gagCount)`;**只统计筛选后可见的行**,非数值格跳过
- **列头筛选**:`ShowFilterButtons := True` 后列头出现 ▾,点开是该列**去重值的勾选列表**;候选取自全部数据行(不受本列自身筛选影响,否则选不回来)
- **列宽/列序**:拖列头右边缘改宽;拖列头本体换位(需 `hoDrag` + `coDraggable`,位移超阈值才生效)
- **分组**:`GroupByColumn(列)` 在显示序里插入**合成分组行**(带成员计数),点分组行折叠/展开。折叠状态按**分组值**记账,重排后不会张冠李戴
- **合并**:`MergeCells(列, 行, 跨列, 跨行)`;基准格跨满整区,被覆盖格无矩形,点区内任意处都归基准格
- **行列增删**:`InsertRow` / `DeleteRow` / `InsertColumn` / `DeleteColumn`,内容随之整体搬移
- **自动适宽**:`AutoFitColumn(列)` 取表头与**已写入**单元格里最宽的;只量写过的格,百万行空表也不扫全表
- **查找/替换**:`FindNext` / `ReplaceCells`,按**显示序**从光标之后**环绕**查找;替换跳过只读列
- **HTML 导出**:`SaveToHTMLText/File`,特殊字符转义,同样走显示序
- **CSV**:`SaveToCSVText/File`、`LoadFromCSVText/File`。含分隔符/引号/换行的字段自动加引号
- **编辑**:`F2` 或双击进入;`Enter` 提交、`Esc` 丢弃;**光标一动就先自动提交**
- 光标走出视口时视口自动跟随(最小移动量)

## 主题 token

网格自成一套键,**不借用树/列表的键**:

```
TyGrid                 整体表面 / 边框 / 字体
TyGridCell             正文单元格(:hover / :selected)
TyGridCellAlt          斑马纹的隔行底色(AlternateRows)
TyGridActiveCell       焦点格(光标所在)—— 整行选中模式下靠它看出光标在哪一格
TyGridFixed            冻结区(固定行列)
TyGridIndicator        行头 / 行号槽
TyGridHeader           列头带
TyGridHeaderSection    列头分段
TyGridHeaderGroup      分组表头带(横跨若干列的上层标题)
TyGridLine             格线
TyGridSelection        选区
TyGridCheckBox         勾选框单元格
TyGridProgress / TyGridProgressFill   进度条单元格
TyGridRating           评分单元格
TyGridButton           按钮单元格(:hover / :active)
TyGridGroupRow         分组行
TyGridSummaryRow       汇总带
```

度量:`--grid-row-height` / `--grid-header-height` / `--grid-indicator-width` /
`--grid-line-width` / `--grid-cell-padding`。

基层(`themes/light.tycss`)已给全套键,所以**新皮肤一条网格规则都不写也能正常显示**。

## 能力一览

### 外观
- 逐格外观钩子 `OnGetCellStyle`(底色 / 文字色 / 字体 / 两轴对齐,一个钩子全包)
- 逐格**持久**外观 `CellColors[c,r]` / `CellTextColors[c,r]` / `SetRowColor`
  —— 与钩子的区别是它落盘:用户手工涂黄的格,存下来还得是黄的
- 逐格边框 `OnGetCellBorder`(四支笔各自可开可关)—— 报表的分区块粗线、小计行双线
- 斑马纹 `AlternateRows`(按**显示行号**取奇偶,排序筛选后条纹仍然隔行)
- 焦点格与选区区分(`TyGridActiveCell`)
- 格线 `GridLineStyle`(none / 只横 / 只竖 / 全)+ `GridLineWidth`
  —— 线**不占布局像素**,压在边界上,列宽不因线变粗而挪位
- 表头自绘钩子 `OnGetHeaderStyle`;列头图标走 `TTyGridColumn.ImageIndex` + `Images`

### 表头
- 分组表头 `HeaderGroups`(横跨若干相邻列的上层标题)+ `GroupHeaderHeight`
- 排序/筛选按钮**只在叶子级** —— 点分组标题不会把下面某一列排序掉
- 拖列宽 / 拖动重排 / 双击分隔线自适应列宽
- 正在过滤的列漏斗**点亮**;多列排序时表头显示顺位徽标

### 数据与交互
- 多列排序:`SortByColumn` 单列、`AddSortColumn` 追加次级列(Shift+点列头)
- 排序方式**跟着列走**(`TTyGridColumn.SortKind`:文本 / 数值 / 日期)
- 排序细则:`BlanksPosition`(空值排前/后,**翻方向时位置不变**)、
  `SortIgnoreCase`、`OnCanSort`(接服务端排序)
- 过滤:条件类型化(包含 / 等于 / 开头是 / 结尾是 / > >= < <=)
  `SetColumnFilterEx`;`ColumnIsFiltered` / `FilteredRowCount`
- 分组:`GroupByColumn` + `ExpandAllGroups` / `CollapseAllGroups`,
  分组行文本走可配的 `GroupRowFormat`
- 行的显式隐藏 `HideRow` / `UnHideRow` / `NumHiddenRows`
  —— 与过滤是**两回事**:过滤是条件,隐藏是事实,`ClearFilters` 不会把它放出来
- 批量:`InsertRows` / `RemoveRows` / `InsertCols` / `RemoveCols` /
  `MoveRow` / `SwapRows` / `MoveColumn`
- 剪贴板:复制 / 剪切 / **智能粘贴**(按剪贴板块大小自动扩行扩列),
  事件族 `OnClipboardCopy/Paste` / `OnBeforePasteCell` / `OnAfterPasteCell`
- CSV 往返(引号内的换行不会串数据)

### 选择
- `SelectAll` / `SelectRange` / `SelectRows` / `ClearSelection` / `Selection` /
  `SelectedCellCount` + `OnSelectionChanged`
- 离散多选(Ctrl+点)、拖选、`SelectionMode`(格 / 行 / 列)
- 选区聚合 `SelectionSum` / `Avg` / `Min` / `Max`(非数值格跳过)

### 编辑
- 列级声明:`EditorKind` / `ReadOnly` / `PickList` / `Aggregate` / `Format` /
  `ValidChars` / `MaxEditLength` —— **设计期配好列,不用接任何事件**
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

### 事件
单元格级鼠标(`OnClickCell` / `OnDblClickCell` / `OnRightClickCell` / `OnCanClickCell`)、
表头(`OnHeaderClick` / `OnHeaderRightClick` / `OnColumnMove`)、
尺寸(`OnColumnSizing` / `OnEndColumnSize` / `OnRowSizing` / `OnEndRowSize`)、
内建控件(`OnCanToggleCheck` / `OnCheckBoxChange` / `OnCellButtonClick`)。

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

## 性能笔记

- 虚拟化:只遍历可视窗口,百万行的表每帧也只画几十行
- **跨帧文本位图缓存**:单元格文字曾占渲染时间的 94%
  (每格一次 `TextSize` 做省略号测量 + 一次 `TextRect`,都是 BGRA 的重活)。
  按外观整体缓存后降到约 1/20。键含文字/字体/字号/字重/颜色/尺寸/对齐/PPI ——
  任何一项变了都是新条目,所以换主题、改列宽、切深色都不需要显式失效
- 逐格样式解析按**状态组合**记忆化:绝大多数格状态相同,整帧只解析一两次
- `GridMetrics` 整帧只算一次(`CellRect`/`CellVisibleRect`/`CellPane` 每格要问三四次)
- 排序是**稳定归并排序**;单元格用哈希表寻址(早先线性查找 + 插入排序,1000 行就卡死)

## 明确不做

XLS 原生读写、PDF 导出与打印子系统、RichEdit / HTML 富文本单元格 ——
它们是文件格式库与输出子系统,不属于网格控件本体。

预置外观样式集(对标品在控件里硬编码几千行 case 上色)也不做:
我们的等价物就是 `.tycss` + typeKey,照抄等于把皮肤职责搬回控件。
