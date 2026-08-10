# TTyGrid 架构复评 —— 承接 AdvStringGrid 全量对差之后

> 2026-07-19。触发:对 TAdvStringGrid 做了**系统性**功能对差(10 领域 / 约 150 条),
> 结果 HIGH 19 · MEDIUM 24 · LOW 17 · SKIP 12。
> 此前的"高/中优先级"是凭印象列的,**不作数**;本文以对差结果为准重排。
>
> 本文回答一个问题:**现有地基能不能直接承接这些功能?不能的话先改哪里?**

## 结论先说

现有架构有 **6 处承重接缝撑不住**,必须先改;另有 **3 个正确性缺陷**零依赖、应最先修。
在这 9 项落地之前动上层功能,会大面积返工。

---

## 一、正确性缺陷(零依赖,最先修)

| # | 问题 | 性质 |
|---|---|---|
| **B1** | `LoadFromCSVText` 先按 `TStringList.Text` 切行、再逐行拆字段 —— **含换行的引号字段会被拦腰截断**,Excel 导出的 CSV 静默串数据 | 数据正确性,不是功能缺失 |
| **B2** | `TTyColumns.ApplyAutoSize` 在 Grid.pas **零调用** —— `hoAutoResize` / `AutoSizeIndex` 已 published 却不生效 | published 却无效,比缺失更误导 |
| **B3** | `TTyColumn.ImageIndex` / `TTyHeader.Images` 字段存在,`RenderHeaderSections` **从不读取** | 同 B2 |

> B2/B3 与此前 `ShowFooter` 那次是同一类:**对外暴露了、编译期不报错、运行期无声无息**。
> 值得加一条守卫:遍历 published 属性,凡"设了没有任何可观测效果"的要能被测出来。

---

## 二、撑不住的 6 处承重接缝

### A1 · 几何契约:标量冻结带 → 四向 + 多行表头带

**现状**:`TTyGridMetrics` 用 `FrozenW` / `FrozenH` 两个标量,`HeaderH` 也是标量;
窗格固定为 4 个(corner / top / left / body)。

**撑不住什么**:多级表头(H16)要表头带有 N 行、每行高度不同、表头格可跨列;
右侧/底部冻结(对差里的 low,但同属几何)要窗格从 4 个变 9 个;
网格线线宽(H14)要参与像素分配,否则线一粗单元格就串位。

**怎么改**:`FrozenLeft/Right/Top/Bottom` 四向 + `HeaderBands: array of Integer` +
`GridLineWidth`。`TyGridPaneRect` 从 4 分支扩成 3×3 网格,**铺满不变量照旧用面积守恒证明**。

**被谁依赖**:H2 / H5 / H9 / H16 / M4 / M9。**这是全部改造的最底层,必须第一个做。**

### A2 · 渲染管线:循环外解析一次 → 逐格解析(带快路径)

**现状**:`RenderCells` 在 `for` 之前 `ResolveStyle('TyGridCell')` **一次**,
整表共用一个 `cellS` / `ink` / `padL/padR`。`RenderHeaderSections` 同理。

**撑不住什么**:逐格颜色/字体/对齐(H3)、行交替色(H4)、hover 高亮(H2)、
逐格边框(M1)、焦点格与选区区分(M2)—— **全部挂在这条管线上**。

**顺带暴露一个洞**:`light.tycss` 里已经写了 `TyGridCell:hover` / `TyGridHeaderSection:hover`,
但控件从不记录 hover 行列、也从不把 `tysHover` 传进解析 —— **皮肤写了,代码没接,永远不触发**。

**怎么改**:样式解析移进逐格循环,但保留"默认样式解析一次并缓存"的快路径
(绝大多数格用默认,只有被钩子改过的才重解析),否则百万行滚动会退化。
同时加 hover 状态机(`FHoverCol/FHoverRow`,只在换格时失效重绘)。

**被谁依赖**:H3 / H4 / H6 / H7 / M1 / M2 / M3。

### A3 · 逐格属性:各存各的哈希 → 统一的单元格属性存储

**现状**:逐格数据分散在 `FCells`(文本)+ `FMerges`(合并跨度),
另有 `FAggregates` / `FColFilters` / `FValFilters` / `FCollapsed` 各自一份。

**撑不住什么**:再加逐格颜色(M3)、逐格字体(M3)、逐格只读(M16)、逐格提示,
就会长出 4 个平行哈希 —— 键空间相同、生命周期相同、增删行时**每一个都要单独搬移**
(`ShiftCells` 现在只搬 `FCells`,`FMerges` 已经是漏的)。

**怎么改**:收敛成一个 `TTyGridCellAttrStore`(与 `FCells` 同键空间的稀疏存储),
合并跨度/颜色/字体/只读都是它的字段。`ShiftCells` 只需搬一处。

> 这条现在就已经有 bug:**增删行不会搬移合并信息**。改架构顺手把它修掉。

### A4 · 选择模型:单锚点矩形 → 区间列表

**现状**:`FSelAnchorCol/Row` + 光标,选区恒为一个矩形。

**撑不住什么**:离散多选(H8)—— 用户按 Ctrl 勾第 2 行和第 7 行,
**现有结构在物理上无法表达**。选区聚合(M12)、离散列选(M11)、选区手柄(M14)全部卡在这。

**怎么改**:选区 = `array of TRect`(显示序空间)+ 一个"当前活动区间"。
单矩形是它的退化情形,现有行为不变。公开 `SelectAll/SelectRange/ClearSelection/Selection`
(目前一个 public 选择方法都没有)+ `OnSelectionChanged`。

### A5 · 列模型:共享的 `TTyColumn` 塞不下网格专属配置

**现状**:`TTyColumn`(`tyControls.Columns.pas`)只有 Width/Alignment/Text/ImageIndex/Options。
**它是共享单元** —— ListView 与 TreeView 也在用。

**撑不住什么**:列级编辑器/只读/候选列表/排序方式(H10、H17)。
每张表都得写 `OnGetEditorKind` 回调,**设计期完全配不出来**。

**架构决策**:不往共享的 `TTyColumn` 里塞网格专属字段(会污染 ListView/TreeView,
且违反本项目"借来的键够不着"的同类教训)。
→ **派生 `TTyGridColumn = class(TTyColumn)`**,让网格的 `TTyColumns` 创建这个子类。
共享单元零改动,网格侧拿到强类型的列配置,设计期可编辑。

### A6 · 编辑器:三个写死的私有字段 → `TTyGridEditLink` 扩展点

**现状**:`FEditor`(TTyEdit)、`FPickEditor`(TTyComboBox)、`FDateEditor` 三个私有字段,
`BeginEdit` 里 `if EditorKindFor(...) = gekXxx then` 一路 if 下来。

**撑不住什么**:第三方无法挂自己的编辑器;下拉全家桶(备忘/计算器/滑块/颜色/子表格)
每加一种就要改 `BeginEdit` 和 `EndEdit` 两处;`OnGetEditorProp`(M17)、
按键级输入约束(H12)也没有承载点。

**怎么改**:抽 `TTyGridEditLink`(创建/定位/取值/写值/焦点/键路由),
现有三个编辑器改造成它的内建实现。**越晚做越贵** —— 现在是 3 个分支,再拖就是 10 个。

### A7 · 排序与分组:单列 → 多列(顺带修一个已知劫持)

**现状**:`FSortCol` 是单个整数,`FSortKind` 是**控件级**;
`FGroupCol` 单个;`BuildGroups` 里**直接把 `FSortCol` 强设成 `FGroupCol`**。

**撑不住什么**:多列排序(H17)、按列排序方式(混合表里日期列会按文本排 → 01/12 排在 02/01 前)、
多级分组 + 分组内排序(H18)。

**已知 bug**:一分组就把用户选的排序列**悄悄丢掉**了。

**怎么改**:排序键升成 `array of (Col, Dir, Kind)`;分组列升成数组;
`BuildGroups` 改为"按分组键排序 → 再按用户排序键在组内排",不再劫持。

---

## 三、落地顺序(依赖决定)

```
B1 B2 B3          正确性,零依赖,随时可插
  ↓
A1 几何契约 ──┬─→ A2 渲染管线 ─→ H3 逐格外观钩子 → H4 斑马纹 → M1/M2/M3
              ├─→ H16 多级表头 ─→ M4/M5
              └─→ H5 单元格级鼠标事件 ─→ H15 按钮格 / M13
A3 属性存储 ──────→ M3/M16 + 顺手修"增删行不搬合并信息"
A4 选择模型 ──────→ H8 → M11/M12/M14
A5 列模型 ────────→ H10 → A6 编辑器扩展点 → H12/M17/M18/M19
A7 排序分组 ──────→ H17 → H18 → M21/M23
H7 行高三件套(可写存储 → 拖拽 → 自动行高)依赖 H6 换行
H19 数据层批量(含 B1)零依赖
```

**第一批(架构)**:B1 B2 B3 → A1 → A2 → A3。
做完这四步,上层的逐格外观、多级表头、斑马纹、hover 才有地方挂。

**第二批**:A4 → A5 → A6 → A7,各自解锁一大片。

---

## 四、明确不做(SKIP,12 类)

XLS 原生读写 · PDF 导出与打印子系统 · RichEdit 单元格(此三项此前已决)
· Office 2003/2007 外观样式集(与本库主题体系冲突)· 数据库绑定
· 其余见对差原始结果。
