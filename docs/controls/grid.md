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

### 单元格显示方式

与编辑方式**正交**——一个格可以显示成进度条,双击仍按数值编辑。经 `OnGetCellDisplay` 逐格指定:

| 显示 | 说明 |
|---|---|
| `gcdText` | 默认:文字 |
| `gcdProgress` | 进度条,值取 0..100(借 `TyProgressBar` 的 token) |
| `gcdRating` | 评分标记,值取 0..5(借 `TyRating` 的 token) |

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
- **CSV**:`SaveToCSVText/File`、`LoadFromCSVText/File`。含分隔符/引号/换行的字段自动加引号
- **编辑**:`F2` 或双击进入;`Enter` 提交、`Esc` 丢弃;**光标一动就先自动提交**
- 光标走出视口时视口自动跟随(最小移动量)

## 主题 token

网格自成一套键,**不借用树/列表的键**:

```
TyGrid                 整体表面 / 边框 / 字体
TyGridCell             正文单元格(:hover / :selected)
TyGridFixed            冻结区(固定行列)
TyGridIndicator        行头 / 行号槽
TyGridHeader           列头带
TyGridHeaderSection    列头分段
TyGridLine             格线
TyGridSelection        选区
```

度量:`--grid-row-height` / `--grid-header-height` / `--grid-indicator-width` /
`--grid-line-width` / `--grid-cell-padding`。

基层(`themes/light.tycss`)已给全套键,所以**新皮肤一条网格规则都不写也能正常显示**。

## 当前边界

已实现:四窗格几何(含冻结行列)、虚拟化渲染、二维光标与键鼠导航、内嵌滚动条、
单元格编辑(文本 / 数值)。

### 行序间接层(重要)

排序**只置换显示序**;`Cells[列,行]`、`Col`/`Row`、编辑都按**稳定的数据行**记账。
所以排序之后光标仍然盯着同一条数据(只是显示位置变了),内容也绝不会串位。
自定义排序时请记住:`OnCompareCells` 拿到的 `ARow1/ARow2` 是**数据行**。

**导出/复制一律走显示序**(所见即所得):被过滤掉的行不出现,排序后的次序被保留;
而寻址仍是数据行 —— 两者由行序间接层桥接。

尚未实现:图片单元格、颜色选择编辑器、可变行高。**明确不做**见下。
(下拉 / 日期 / 颜色等浮层类,将由 `TTyPopover` 承载)。

**明确不做**:XLS 原生读写、PDF 导出与打印子系统、RichEdit 单元格 —— 它们是文件格式库
与输出子系统,不属于网格控件本体。
