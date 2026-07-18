# TTyGrid 设计:对标 TMS TAdvStringGrid 的自绘数据网格

> 状态:**设计已定**(2026-07-18)。约束:**功能不能比参照物少**。
>
> ⚠️ **版权边界(务必遵守)**:参照物 TMS TAdvStringGrid(`Advgrid.pas`,66142 行 / 1024 属性)
> 是**受版权保护的第三方商业代码**。本项目仅将其用作**功能清单与大致结构的参照**——
> 下文出现的 `edXxx` / `AddXxx` / `GroupSum` 等标识符,只是为了逐项勾选"这个能力我们有没有"
> 而记录的**功能对照表**,**不是要照搬其命名、类型或实现**。
>
> **本网格是独立实现(clean-room)**:全部建立在我们自己的 `tyControls.Columns.pas`、
> `tyControls.ListView.Layout.pas`、`TTyPainter` 与主题引擎之上,采用我们自己的命名体系
> (`TTyGridEditLink`、`EditorKind`、`TyGridXxx` token 等)。
> **任何时候都不得从那份源码复制代码**;功能盘点阶段已结束,实现阶段不再参考其源码。

---

## 1. 目标与硬约束

做 ty-controls 的旗舰数据网格,功能对标 TAdvStringGrid。同时必须守住库的既有铁律:

- **全自绘**(BGRABitmap),**外观全部走 `.tycss` token**,控件里不写死任何视觉值;
- HiDPI 按 PPI 缩放;跨平台像素一致;
- **零数据库依赖**(不做 DBGrid);
- 走完整的新控件出厂流程(20 份 `.tycss` → 生成器 → 图标 → `Design.pas` 注册 → `.lpk` → 测试 → 文档 → 示例 → i18n → README/CHANGELOG)。

Grid 是路线图里被推迟过三次的最后一块硬骨头,体量远大于此前任何一个控件,**必须分期**——但分期不等于砍功能,见第 6 节。

## 2. 参照物盘点(实测)

| 领域 | AdvStringGrid 的量级 |
|---|---|
| 单元格编辑器类型 | **~40 种**(`edNormal/edNumeric/edFloat/edPositiveFloat/edSpinEdit/edFloatSpinEdit/edDateEdit/edDateSpinEdit/edTimeEdit/edComboEdit/edComboList/edCheckBox/edButton/edEditBtn/edMaskEditBtn/edNumericEditBtn/edUnitEditBtn/edUpperCase/edLowerCase/edCapital/edMixedCase/edPassword/edValidChars/edColorPickerDropDown/edImagePickerDropDown/edMemoDropDown/edCalculatorDropDown/edTrackBarDropDown/edDetailDropDown/edGridDropDown/edControlDropDown/edRichEdit/edUniEdit/edCustom` …) |
| 单元格图形/控件 | **30+ 种** `AddXxx`(Bitmap/Picture/Icon/ImageIdx/MultiImage/DataImage、CheckBox(+Column)、Radio(+Button/Column)、Progress(+Ex/Formatted/Pie)、Comment/ColorComment/Balloon、Node(树列)、Expand、Marker、Button/BitButton、ComboString、InterfacedCell) |
| 排序 | 多列索引排序、`OnCustomCompare`、点击列头排序、分组内排序、未排序原值映射(`UnSortedRowIndex`) |
| 过滤 | 列自动过滤下拉(勾选式/多列/增量)、过滤表达式集合 `TFilter`、`OnCustomFilter`、保存/加载过滤器 |
| 分组聚合 | `Group/SubGroup/UnGroup`、分组计数、聚合 `GroupSum/Avg/Min/Max/Count/StdDev/Distinct`、汇总行、列脚计算 |
| 合并 | 行/列单元格合并、列自动合并、表头合并、分组合并 |
| 选择 | 单元格/行/列/矩形块/**不连续多选**、选区聚合(Sum/Avg/Min/Max)、选区调整手柄、隐藏选中/未选中行 |
| 剪贴板 | 单元格区域复制/剪切/粘贴、**Excel 剪贴板格式**、HTML/RTF 复制、逐单元格粘贴事件 |
| 导入导出 | CSV / 固定宽度 / XLS / HTML / XML / 流 |
| 打印 | `TPrintSettings`(页边距/方向/页眉页脚/缩放/重复固定行)、打印预览、按选区打印 |

## 3. 我们已有的地基(可直接复用)

这是本设计最关键的发现——**网格所需的一半引擎已经存在**:

| 已有资产 | 提供什么 | 复用方式 |
|---|---|---|
| **`tyControls.Columns.pas`** | `TTyColumn`(Width/MinWidth/MaxWidth/Position/Alignment/Text/ImageIndex/Options)、`TTyColumns`(位置↔索引映射、`TotalWidth`、`ColumnFromPosition`、`DetermineSplitterIndex`、`ApplyAutoSize`、`DistributeSpring`)、`TTyHeader` | **整份拿来**。列几何、拖宽、自动适宽、弹性分配全部免费,且已有无头测试 |
| **`tyControls.ListView.Layout.pas`** | 纯几何:行矩形、可视行窗口、行命中、二维键盘导航 | 行几何与虚拟化窗口直接用;单元格矩形 = 行矩形 ∩ 列跨度 |
| **`TTyListView`** | 虚拟数据四读者(`GetItemText(行,**列**)` 签名天然匹配)、**`FOrder`/`FRank` 稳定排序置换**、行选择+框选、双内嵌滚动条(两趟互夺定宽)、表头渲染+排序字形、**网格线渲染**、内联编辑器生命周期("移动单元格前必先提交"的 9 条规则) | 大面积复用;`FOrder/FRank`(选择/编辑按稳定行标识而非显示序)是可排序网格的正确架构,原样继承 |
| **`TTyValueListEditor`** | **单元格编辑器种类目录**:内联文本 / 数值受限 / 下拉选取 / 颜色色板 / 省略号对话框 / 只读,含提交-校验流程 | 这就是 TMS 的 "EditLink kinds" 的现成版本,把**按行**的 EditorKind 推广成**按列/按单元格** |
| **`TTyPopover`**(本周刚合并) | **能承载控件的气泡浮层** | AdvGrid 那一整排 `edXxxDropDown`(颜色/图片/备忘/计算器/滑块/明细/子网格)的统一载体 |
| `TTyTreeView` | 多列单元格绘制、内联编辑、节点展开/折叠 | 树列(`AddNode`)与分组折叠的参照 |
| `TTyHtmlLabel` | 行内 HTML 子集渲染 | HTML 单元格 |

**必须新建的**(现有控件都没有):① 二维单元格光标与选择(现有选择是纯行、无列维度);② 按列/按单元格的编辑器分派与 `SetCellText(行,列)` 回写;③ **冻结行列(固定窗格)+ 行头槽**;④ 按单元格的视觉钩子(`OnGetCellStyle`/`OnDrawCell`);⑤ 可变行高、单元格合并;⑥ 正文的**列**命中(现有只命中行);⑦ 列拖动重排(`TTyColumn.coDraggable`/`AdjustPosition` 已建模但从未接线);⑧ 单元格区域剪贴板。

## 4. 架构

### 4.1 类层次

```
TTyCustomControl
  └─ TTyCustomGrid        几何/窗格/滚动/选择/绘制管线/键鼠/主题(无数据)
       ├─ TTyDrawGrid     纯自绘:内容由 OnDrawCell / OnGetCellText 提供(对齐 LCL TDrawGrid)
       └─ TTyStringGrid   完整体:单元格存储 + 编辑 + 排序/过滤/分组/合并 + 剪贴板/导入导出
                          ← 这一层才是 TAdvStringGrid 的对位
```
沿用 LCL 的 `TDrawGrid`/`TStringGrid` 命名,让从 `TStringGrid`/`TAdvStringGrid` 迁移的用户零学习成本。

### 4.2 数据模型

- **稀疏存储** `TTyCellStore`:以 `(列,行)` 为键的哈希 → `TTyCellData`(文本 + 类型化值 + 关联对象 + 单元格级格式)。100 万 × 100 的空表**不占内存**。
- **类型化访问**:`Cells[c,r]: string`、`Ints`、`Floats`、`Values: Variant`、`Objects`。
- **虚拟模式**:`OnGetCellText(col,row)` / `OnSetCellText`,复用 `TTyListView` 已验证的四读者模式(其 `GetItemText(AIndex, AColumn)` 签名本就是二维的)。
- **行序间接层**:复用 `FOrder`(显示序→行)/`FRank`(行→显示序)。**排序、过滤、分组全部只置换这一层**,选择/焦点/编辑一律按稳定行标识记账,因此重排后不会错位。这是全设计的中心不变量。

### 4.3 行列几何与固定窗格

- 列:整份复用 `tyControls.Columns.pas`。
- 行:新增 `TTyRows`(每行 `Height`,默认统一、可选可变;`Visible` 供过滤/折叠使用)。
- **固定窗格**:`FixedCols`/`FixedRows` 把视口切成 4 个窗格(角/固定行/固定列/正文),绘制与命中都按窗格分派——这是全新的一层。

### 4.4 绘制管线与主题 token

按窗格绘制 → 窗格内按列位置游走(复用 ListView 的 `colLeft/colRight` 推导)→ 单元格矩形 = 行矩形 ∩ 列跨度(再经合并跨度修正)→ 解析单元格样式 → 画背景/边框/内容。

新增 token(**各自独立的 typeKey,绝不借用树/列表的键**,见 `borrowed-typekey-unreachable` 教训):

```
TyGrid                 整体表面/边框/字体
TyGridCell             正文单元格(:hover / :selected / :focused / :disabled)
TyGridFixed            固定行列(表头以外的冻结区)
TyGridHeader           列头带
TyGridHeaderSection    列头分段(含排序字形)
TyGridIndicator        行头/行号槽
TyGridGroupRow         分组行
TyGridSummaryRow       汇总/列脚行
TyGridSelection        选区填充/边框
TyGridLine             网格线
TyGridEditor           内联编辑器外框
```
度量 token:`--grid-row-height`、`--grid-header-height`、`--grid-indicator-width`、`--grid-line-width`、`--grid-cell-padding`。

**按单元格定制**:`OnGetCellStyle(col,row; var AStyle)` 覆盖主题解析结果;`OnDrawCell` 完全接管。二者覆盖 AdvGrid 的 `OnGetCellColor`/`OnGetCellFont`/`OnGetAlignment` 全家。

### 4.5 编辑器注册表(~40 种 → 少数控件 × 修饰符)

AdvGrid 的编辑器枚举看着吓人,其实是**少量控件 × 修饰符**的笛卡尔积:

| 归类 | 承载控件 | 覆盖的 AdvGrid 类型 |
|---|---|---|
| 文本 | `TTyEdit` + 修饰符(大小写变换/合法字符集/密码/掩码) | `edNormal/edUpperCase/edLowerCase/edCapital/edMixedCase/edPassword/edValidChars/edUniEdit` |
| 数值 | `TTyEdit` 数值受限(**`TTyValueEdit.FilterInsert` 已实现**)/ `TTySpinEdit` | `edNumeric/edPositiveNumeric/edFloat/edPositiveFloat/edSpinEdit/edFloatSpinEdit` |
| 日期时间 | `TTyDateTimePicker` | `edDateEdit/edDateSpinEdit/edTimeEdit/edTimeSpinEdit/edDateTime` |
| 下拉 | `TTyComboBox`(可编辑/只选) | `edComboEdit/edComboList/edUniCombo*` |
| 勾选 | `TTyCheckBox` | `edCheckBox` |
| 按钮/省略号 | `TTyEdit` + 尾部按钮(**ValueListEditor 已实现**) | `edButton/edEditBtn/edMaskEditBtn/edNumericEditBtn/edUnitEditBtn` |
| **浮层面板** | **`TTyPopover` 承载任意控件** | `edColorPickerDropDown/edImagePickerDropDown/edMemoDropDown/edCalculatorDropDown/edTrackBarDropDown/edDetailDropDown/edGridDropDown/edControlDropDown` |
| 扩展点 | **`TTyGridEditLink`**(抽象基类) | `edCustom`——用户挂任意控件当编辑器 |

编辑器**按列**指定(`TTyGridColumn.EditorKind`),并可被 `OnGetCellEditor(col,row)` 按单元格覆盖。生命周期直接继承 ListView 那套"任何会移动单元格的动作之前必先提交"的规则集。

### 4.6 选择与导航

二维:当前单元格 `(Col,Row)` + 选区 = **矩形区间列表**(天然支持块选与不连续多选)。模式:`gsmCell / gsmRow / gsmColumn / gsmBlock / gsmDisjoint`。一律按**稳定行标识**记账,排序/过滤后不跑位。键盘:方向键移动单元格光标、Tab/Enter 可配置走向、翻页、Ctrl+Home/End、Shift 扩展选区。

### 4.7 排序 / 过滤 / 分组 / 合并 的挂载点

全部作用在 §4.2 的行序间接层,互不干扰:

- **排序** → 置换 `FOrder`(复用 ListView 的稳定归并排序 + 文本/数值/日期比较器 + `OnCompareCells`);多列索引排序 = 比较器串联。
- **过滤** → 标记行不可见后重建 `FOrder`;列头自动过滤下拉 = `TTyPopover` + 勾选列表。
- **分组** → 向显示序注入合成的分组行/汇总行 + 聚合计算(`Sum/Avg/Min/Max/Count/StdDev/Distinct`)。
- **合并** → 跨度表 `(col,row) → (colspan,rowspan)`,绘制与命中都查它。

## 5. 功能对标矩阵

| AdvGrid 领域 | 计划 | 依托 |
|---|---|---|
| 列模型/拖宽/自动适宽 | **复用** | `tyControls.Columns.pas` |
| 行几何/可视窗口/行命中 | **复用** | `ListView.Layout.pas` |
| 虚拟数据 | **复用** | ListView 四读者(签名已二维) |
| 排序(含自定义比较) | **复用+改造** | ListView 归并排序 + `FOrder/FRank` |
| 行选择/框选 | **复用** | ListView 选择引擎 |
| 滚动条/滚轮 | **复用** | ListView 双内嵌滚动条 |
| 表头/排序字形/网格线 | **复用** | ListView 渲染(换成自己的 token) |
| 内联编辑生命周期 | **复用** | ListView 编辑器规则集 |
| 编辑器种类目录 | **改造** | ValueListEditor 按行 → 按列 |
| 浮层类编辑器 | **改造** | `TTyPopover` 承载 |
| HTML 单元格 | **改造** | `TTyHtmlLabel` |
| 树列/展开折叠 | **改造** | `TTyTreeView` |
| 二维光标与选区 | **新建** | — |
| 冻结行列 + 行头槽 | **新建** | — |
| 按单元格样式/自绘钩子 | **新建** | — |
| 可变行高 / 单元格合并 | **新建** | — |
| 过滤(下拉+表达式) | **新建** | 下拉壳复用 Popover |
| 分组 + 聚合 + 汇总行 | **新建** | — |
| 单元格图形(勾选/进度/评分/图片/批注/按钮) | **新建** | 绘制原语已有 |
| 剪贴板单元格区域(含 Excel 格式) | **新建** | — |
| CSV / TSV / HTML / XML 导入导出 | **新建** | 纯文本序列化,成本低 |
| 列拖动重排 | **接线** | `coDraggable`/`AdjustPosition` 已建模未接线 |
| **XLS/Excel 原生读写** | **建议暂缓** | 需要完整 Excel 文件格式库,属应用层 |
| **PDF 导出 / 打印子系统** | **建议暂缓** | 前置程序已明确排除 print;属应用层 |
| **RichEdit 单元格** | **建议暂缓** | 需要富文本引擎;前置程序已排除 RichEdit |

## 6. 分期路线图(一期一 merge)

| 期 | 内容 | 为什么这个顺序 |
|---|---|---|
| **P0 骨架** | `TTyCustomGrid`:列模型接入、行几何、**固定窗格**、滚动、主题渲染、网格线、单元格命中;`TTyDrawGrid` | 一切的地基;窗格切分必须最先定,否则后面全要返工 |
| **P1 数据与选择** | `TTyStringGrid` 稀疏存储 + 类型化访问 + 虚拟模式;**二维光标/选择**(cell/row/col/block/disjoint)+ 键盘导航 | 没有数据和光标就没法验证任何交互 |
| **P2 编辑** | 编辑器注册表 + 常用编辑器(文本/数值/下拉/勾选/日期/按钮省略号)+ 提交校验事件 + `TTyGridEditLink` 扩展点 | 编辑是网格的核心价值 |
| **P3 排序与过滤** | 排序(复用)+ 列头点击 + 自动过滤下拉 + 过滤表达式 | 都只动行序层,一起做最省 |
| **P4 分组/汇总/合并** | 分组行 + 聚合 + 汇总行 + 单元格合并 | 依赖 P3 的行序层与 P0 的跨度渲染 |
| **P5 单元格图形** | 勾选/单选/进度/评分/图片/批注/按钮/树列 + HTML 单元格 | 纯绘制层,可独立推进 |
| **P6 数据交换** | 单元格区域剪贴板(含 Excel 剪贴板格式)+ CSV/TSV/HTML/XML | 依赖 P1 的存储与 P1 的选区 |
| **P7 打磨** | 列拖动重排、自动适宽、类型搜索、固定汇总行、IME、无障碍 | 收尾 |

## 7. 已决事项(2026-07-18 用户拍板)

1. **命名 —— 三层,对齐 LCL**:`TTyCustomGrid`(基类) → `TTyDrawGrid`(纯自绘) → `TTyStringGrid`(完整体)。
   让从 `TStringGrid` / `TAdvStringGrid` 迁移的用户零学习成本。
2. **新建,不改造 `TTyTreeView`**:新建 `TTyCustomGrid`,复用 `Columns.pas` + `ListView.Layout.pas`
   + ListView 的引擎片段。TreeView 的核心是层级节点模型,把它掰成平表会同时伤害两者。
3. **范围边界 —— 暂缓 3 项**:**XLS 原生读写、PDF 导出 / 打印子系统、RichEdit 单元格**不做。
   它们不是网格控件本身,而是文件格式库与输出子系统;前置程序也已明确排除 print / RichEdit。
   **CSV / TSV / HTML / XML 导入导出照做**(纯文本序列化,成本低),见 P6。
   日后若要补,应作为独立可选单元(如 `tyControls.Grid.Xls.pas`)排在 P7 之后,**不进网格本体**。

> 除此之外,§5 矩阵中的每一项 AdvGrid 能力都有明确归宿(复用 / 改造 / 新建 / 接线),
> 满足「功能不能比参照物少」的约束。
