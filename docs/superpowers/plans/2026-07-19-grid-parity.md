# TTyGrid 对标补齐 实施计划

> **For agentic workers:** 用 `superpowers:executing-plans` 逐批执行。步骤用 `- [ ]` 勾选跟踪。
> **本文件是唯一的进度真相** —— 上下文被压缩后,从这里读"下一个未勾选项"继续,不要凭记忆。

**Goal:** 把 TTyGrid 从"能用"补到"对标 TAdvStringGrid 的交互能力",覆盖对差出的 HIGH 19 + MEDIUM 24 项。

**Architecture:** 先做 6 处承重接缝的改造(几何契约 → 渲染管线 → 属性存储 → 选择模型 → 列模型/编辑器 → 排序分组),
再把功能挂上去。**架构不动就加功能会大面积返工** —— 见 `docs/design/2026-07-19-grid-architecture-review.md`。

**Tech Stack:** FPC 3.2.2 / Lazarus,BGRABitmap 自绘,`.tycss` 主题,FPCUnit 测试。

**依据文档:**
- 对差结果与优先级:本文件末尾附录
- 架构复评:`docs/design/2026-07-19-grid-architecture-review.md`
- 网格设计与已决边界:`docs/design/2026-07-18-grid-control.md`

---

## 每批必守的收工条件(不满足不算完成)

1. 新行为**先写失败测试**,确认红了(断言失败,不是编译错误),再实现。
2. 关键守卫做**变异验证**:改坏实现 → 测试必须红 → 恢复。跑绿不等于守住。
3. `lazbuild tests/tytests.lpi` 零错;`./tests/tytests.exe --all` **0 failures**
   (12 个 errors 是既有环境问题,与网格无关)。
4. `lazbuild tycontrols.lpk` 零错;示例 `lazbuild -B examples/grid/grid_example.lpi` 链接成功。
5. 源码里 `grep -c MUTATION` 必须为 0。
6. **提交**(已获长期授权,不必请示)。
7. 回本文件把该批的 `- [ ]` 改成 `- [x]`。

---

## 批次总览

| 批 | 内容 | 状态 |
|---|---|---|
| B1 | 三个正确性缺陷 | - [x] **完成** `2026-07-19` |
| B2 | A1 几何契约(四向冻结 + 多行表头带 + 线宽) | - [x] **完成** `2026-07-19` |
| B3 | A2 渲染管线逐格化 + hover;A3 属性存储统一 | - [x] **完成** `2026-07-19` |
| B4 | H3 逐格外观钩子 + H4 斑马纹 + H14 网格线局部 | - [x] **完成** `2026-07-19` |
| B5 | H5 单元格级鼠标事件 + H15 按钮单元格 + H13 AutoResize 接线 | - [x] **完成** `2026-07-19` |
| B6 | H6 换行 + H7 行高三件套 | - [x] **完成** `2026-07-19` |
| B7 | A4 选择模型重构 + H8 离散多选 | - [x] **完成** `2026-07-19` |
| B8 | A5 列模型(TTyGridColumn)+ H10 列级编辑器声明 | - [x] **完成** `2026-07-19` |
| B9 | A6 EditLink 扩展点 + H12 输入约束 + H9 键盘录入手感 | - [x] **完成** `2026-07-19` |
| B10 | H16 多级/合并表头 | - [x] **完成** `2026-07-19` |
| B11 | A7 + H17 多列排序 + H18 分组重做 | - [x] **完成** `2026-07-19` |
| B12 | H19 数据层批量 + 剪贴板事件 | - [x] **完成** `2026-07-19` |
| B13 | MEDIUM 第一组(M1-M9) | - [x] **完成** `2026-07-19` |
| B14 | MEDIUM 第二组(M10-M19) | - [x] **完成** `2026-07-19` |
| B15 | MEDIUM 第三组(M20-M24)+ 文档/示例/i18n 收尾 | - [x] **完成** `2026-07-19` |

---

## B1 · 三个正确性缺陷

**Files:**
- Modify: `source/tyControls.Grid.pas`(`LoadFromCSVText`、`UpdateScrollBars`、`RenderHeaderSections`)
- Test: `tests/test.grid.pas`

### B1-1 CSV 跨行引号(数据正确性)

现状:`LoadFromCSVText` 先 `lines.Text := AText` 按行切,再逐行 `TyCsvSplit`。
含换行的引号字段(Excel 导出很常见)会被拦腰截断 → **静默串数据**。

- [x] 写失败测试 `TestCsvRoundTripsCellsContainingNewlines`:
  一个单元格内容为 `'第一行' + LineEnding + '第二行'`,`SaveToCSVText` 后 `LoadFromCSVText`,
  断言 `Cells[1,1]` 与原值**逐字符相等**,且 `RowCount` 不变。
- [x] 跑,确认红(会看到行数变多或内容被截断)。
- [x] 实现:新增 `TyCsvParse(const AText: string; ADelimiter: Char): TStringGridData`
      —— **字符级流式解析**,维护 `inQuote` 状态,只有在引号外的换行才断行。
      `LoadFromCSVText` 改走它,不再预先按行切。
- [x] 跑,确认绿;跑全套件确认既有 CSV 测试不回归。
- [x] 变异:让解析器忽略 `inQuote` 状态 → 该测试必须红 → 恢复。
- [x] 提交 `fix(grid): CSV 跨行引号字段不再串数据`。

### B1-2 `ApplyAutoSize` 接线

现状:`grep -c ApplyAutoSize source/tyControls.Grid.pas` == 0。
`hoAutoResize` / `Header.AutoSizeIndex` 已 published 却完全不生效。

- [x] 写失败测试 `TestAutoResizeColumnFillsRemainingWidth`:
  设 `Header.Options := Header.Options + [hoAutoResize]`、`Header.AutoSizeIndex := 1`,
  改变控件宽度后,断言第 1 列宽度吸收了剩余空间(`Columns.TotalWidth` ≈ 视口宽)。
- [x] 跑,确认红。
- [x] 实现:在 `UpdateScrollBars` 里(视口宽已知处)调用
      `FHeader.Columns.ApplyAutoSize(UnscaleI(ViewportW - FrozenWidthPx), FHeader.AutoSizeIndex)`,
      仅当 `hoAutoResize in FHeader.Options`。注意避免与滚动条两趟收敛互相触发死循环
      —— 用 `FSyncingScroll` 同一把守卫。
- [x] 跑,确认绿。
- [x] 变异:去掉该调用 → 测试红 → 恢复。
- [x] 提交。

### B1-3 表头图标渲染

现状:`TTyColumn.ImageIndex` 存在,`RenderHeaderSections` 从不读。

> **实施中的架构修正**:原计划想用共享单元的 `TTyHeader.Images`,但它是 LCL 的
> `TCustomImageList`,而我们的 `TTyVirtualImageList` **并非它的后代** —— 用不上。
> 按"不跟共享单元较劲"的原则,改为**网格自带 `Images`**(从 TTyStringGrid 上移到
> TTyCustomGrid,列头与 gcdImage 单元格共用),索引仍走共享的 `TTyColumn.ImageIndex`。

- [x] 写失败测试 `TestHeaderDrawsColumnImage`:给 `Header.Images` 一个
      `TTyVirtualImageList`(用 `TTyImageCollection` 造 2 个纯色图),
      `Columns[0].ImageIndex := 0`,渲染后断言列头带内出现该颜色的像素。
- [x] 跑,确认红(墨 0)。
- [x] 实现:`RenderHeaderSections` 里在标题文字之前画图标,文字左缩进让位;
      复用 `FImages.CachedIndex(idx, sz)` 的缓存路径(与单元格图片一致,不重复分配)。
- [x] 跑,确认绿。
- [x] 变异:注释掉画图标那几行 → 测试红 → 恢复。
- [x] 提交。

### B1-4 加一条"published 却无效"的通用守卫

B2/B3 与此前 `ShowFooter` 是同一类 bug:对外暴露了、编译期不报错、运行期无声无息。

- [x] 在 `tests/test.grid.pas` 加 `TestPublishedSurfaceHasObservableEffect`:
      对一组"设了应当有可观测效果"的属性(`ShowFooter` / `GridLines` / `ShowIndicator` /
      `ShowFilterButtons` / `hoAutoResize`),分别设为非默认值,断言
      **渲染输出的像素或几何度量发生变化**(而不是仅仅属性读回来变了)。
- [x] 跑,确认全绿(此时 B1-2/B1-3 已修)。
- [x] 变异:让 `FooterHeightPx` 恒返回 0(等价于"设了没效果")
      → 测试红(`ShowFooter 应当从视口里扣掉汇总带高度(300 -> 300)`)→ 恢复。
- [x] **顺手修**:`ShowFilterButtons` 原本 `write FShowFilterButtons` 直写字段,
      运行期开关它**不重绘** —— 同一类洞的轻症。改成带 `Invalidate` 的 setter。
- [x] 提交。

- [x] **B1 收工**:跑完整收工条件 1-7。

---

## B2 · A1 几何契约扩展

**Files:**
- Modify: `source/tyControls.Grid.Layout.pas`(`TTyGridMetrics`、`TyGridPaneRect`、行几何)
- Modify: `source/tyControls.Grid.pas`(`GridMetrics`、`FrozenWidthPx/HeightPx`、`RenderChrome`)
- Test: `tests/test.grid.layout.pas`

**契约变更**(一次改到位,避免二次返工):
```pascal
TTyGridMetrics = record
  ClientW, ClientH: Integer;
  { 四向冻结带。Left 含行头槽+固定列;Top 含表头带+固定行;Right/Bottom 为新增。 }
  FrozenLeft, FrozenRight, FrozenTop, FrozenBottom: Integer;
  { 表头带:每一级一个高度(设备像素)。空 = 无表头。合计 <= FrozenTop。 }
  HeaderBands: TTyIntArray;
  GridLineWidth: Integer;          { 参与像素分配,否则线一粗单元格就串位 }
  RowH, RowCount, FixedRows: Integer;
  RowTops: TTyIntArray;
  ScrollX, ScrollY: Integer;
end;
```

- [x] **兼容步(改了做法)**:没有做"旧字段名当只读别名",而是**直接改名**
      (`FrozenW`→`FrozenLeft`、`FrozenH`→`FrozenTop`、`HeaderH`→`HeaderBands`)。
      理由:别名意味着同一份状态存两处,是 bug 温床;而改名让**编译器**替我们
      找齐每一个调用点(9 + 2 处),比人肉找可靠。改完全套件 3749 / 0 fail,
      同样证明了"重构没碰坏行为"这件事。
- [x] 写失败测试 `TestNinePanesTileTheViewport`:四向冻结都非零时,
      3×3 共 9 个窗格必须**精确铺满视口**,用面积守恒证明(与现有四窗格那条同样的证法)。
- [x] 跑,确认红。
- [x] 实现 `TyGridPaneRect` 的 3×3 版本(枚举扩成 9 值,旧的 4 个值保留语义)。
- [x] 跑,确认绿。
- [x] 写失败测试 `TestHeaderBandsStackAndSumToFrozenTop`:
      `HeaderBands = [24, 20]` 时,第 0 级带在 y∈[0,24),第 1 级在 y∈[24,44),
      且固定行从 44 起算。
- [x] 跑红 → 实现 → 跑绿。
- [x] **改了语义**,测试相应改成 `TestGridLineWidthInsetsContentButNotBoundaries`:
      线宽**不占布局像素**,线压在单元格边界上、两侧各一半;加粗只让**内容**内缩。
      理由:边界随线宽漂移会让 `ColWidths` 失去"所见即所得"的含义,每次调线宽
      都得重算滚动范围与全部命中;LCL `TCustomGrid` 与常见商业网格一致选了这条。
      测试因此断言"内容内缩了 **且** 行/列边界一动不动"。
- [x] 跑红 → 实现 → 跑绿。
- [x] 变异:① 让 `HeaderBands` 只取第一项 → 多级表头测试红;
      ② 让线宽不参与分配 → 边界测试红。各自恢复。
- [x] ~~删掉兼容别名~~(没引入别名,见上);跑全套件确认 0 回归 —— 3752 / 0 fail。
- [x] **B2 收工**:收工条件 1-7。

---

## B3 · A2 渲染管线逐格化 + A3 属性存储统一

**Files:**
- Modify: `source/tyControls.Grid.pas`(`RenderCells`、`RenderHeaderSections`、`MouseMove`;
  新增 `TTyGridCellAttrStore`)
- Test: `tests/test.grid.pas`

### B3-1 hover 状态机(先做,因为它证明管线通了)

`light.tycss` 里 `TyGridCell:hover` / `TyGridHeaderSection:hover` **已经写好但永不触发**。

- [x] 写失败测试 `TestHoverHighlightsTheCellUnderTheMouse`:
      探针主题给 `TyGridCell:hover { background: #FF0000; }`,
      `MouseMove` 到某格后渲染,断言该格出现红;移开后消失。
- [x] 跑,确认红。
- [x] 实现:`FHoverCol/FHoverRow` + `MouseMove` 里换格才 `Invalidate`(否则每像素重绘);
      `MouseLeave` 清空。
- [x] 跑绿。
- [x] 变异:不把 `tysHover` 传进解析 → 红 → 恢复。

### B3-2 逐格样式解析(带快路径)

- [x] 写失败测试 `TestPerCellStyleResolutionKeepsDefaultFastPath`。
      **绝对毫秒阈值换台机器就误报**,改成相对度量:同一张表画两遍(空表 vs 填满文字),
      断言文字增量不超过管线固有开销的 4 倍。变异掉缓存后是 28 倍,健康时 1.1 倍。

**这条守卫顺带挖出了一个大得多的问题**(不在原计划里,已就地解决):
逐项实验显示单元格文字占了 94% 的渲染时间(每格一次 TextSize 做省略号测量 + 一次
TextRect,都是 BGRA 重活),而样式解析根本不是瓶颈。加了**跨帧文本位图缓存**
(键含文字/字体/字号/字重/颜色/尺寸/对齐/PPI),44.3s → 8.6s。剩下的是 painter
每帧整幅位图的固有开销,与网格无关,不在本批范围。
- [x] 同时把 GridMetrics 做成整帧记忆化(CellRect/CellVisibleRect/CellPane 每格要算三四次)。
- [x] 把 `ResolveStyle` 移进逐格循环,但**默认样式解析一次并缓存**,
      只有被钩子改过的格才重解析。
- [x] 跑绿 + 跑既有渲染测试确认 0 回归。

### B3-3 单元格属性统一存储

现状:`FCells`(文本)与 `FMerges`(合并)分家,**且 `ShiftCells` 只搬 `FCells`
—— 增删行不搬合并信息,已经是 bug**。

- [x] 写失败测试 `TestInsertRowShiftsMergeSpansToo`:
      在 (1,1) 合并 2×2,`InsertRow(0)` 后断言合并区跟着下移到 (1,2)。
- [x] 跑,确认红(现有实现不搬)。
- [x] 实现 `TTyGridCellAttrStore`:与 `FCells` 同键空间的稀疏存储,
      字段含 `ColSpan/RowSpan`(合并)、`Color/Font/Alignment`(留给 B4)、`ReadOnly`(留给 B14)。
      `FMerges` 迁移进来;`ShiftCells` 改为同时搬文本与属性。
- [x] 跑绿。
- [x] 变异:让 `ShiftCells` 只搬文本 → 红 → 恢复。
- [x] 第二处变异(去掉"文本键 ∪ 属性键"的并集)**没被杀** → 说明"只合并、不写文字"
      的空白合并块没测到 → 补 `TestInsertRowShiftsMergeOfEmptyCell` → 变异这才红。
      (跑绿不等于守住,这批第二次证明了这句话。)
- [x] **B3 收工**:收工条件 1-7。

---

## B4 · 逐格外观钩子 + 斑马纹 + 网格线局部控制

**Files:** `source/tyControls.Grid.pas`、`themes/light.tycss`、`tests/test.grid.pas`

- [x] `OnGetCellStyle(Sender; ACol, ARow; var ABackground: TTyFill; var ATextColor: TTyColor;
      var AFontName: string; var AFontSize, AFontWeight: Integer;
      var AHAlign: TAlignment; var AVAlign: TTextLayout)` —— 一个钩子覆盖颜色/字体/两轴对齐。
      失败测试:钩子把第 2 行涂红 → 该行像素变红,其余行不变。
- [x] **垂直对齐**:现在 `DrawText` 恒 `tlCenter`,钩子要能改成 `tlTop`/`tlBottom`。
      失败测试:同一格改成 tlTop 后,墨的重心上移。
- [x] 斑马纹:**改用自己的 typeKey `TyGridCellAlt`**,不是计划里写的 `TyGridCell:alternate`。
      理由:加一个伪类要动共享的 `TTyState` 枚举与 CSS 解析器 `PseudoToState`,
      会波及每一个控件;而库里网格的各部件(TyGridCheckBox / TyGridProgress /
      TyGridGroupRow…)本来就各有各的键,这条更一致。
      新增 `--surface-alt` token 补进 `light.tycss` + 重跑 `gen-defaulttheme.ps1`;
      按**显示行号**取(排序/过滤后条纹仍然是隔行,而不是跟着数据行跳)。
      失败测试:奇偶行底色不同,且排序后仍然隔行。
- [x] 网格线局部控制:`GridLines: Boolean` → `GridLineStyle: (glsNone, glsHorizontal, glsVertical, glsBoth)`
      (**保留 `GridLines` 为兼容别名**,老代码不炸)。失败测试:只横线时竖线像素为 0。
- [x] 每项都变异验证。**斑马纹那条第一次变异没被杀** —— 我挑的测试数据(倒序 e,d,c,b,a)
      让"显示序奇偶"与"数据行奇偶"恰好一致,按数据行取奇偶的错误实现也能通过。
      换成 c,a,b,f,d,e(升序后 0->1,1->2,2->0,3->4)才真正区分开。
- [x] 另:钩子桩方法一开始写进了测试类的 `published` 段 —— fpcunit 把 published 段里的
      **每个**方法都注册成测试,钩子被当测试跑(Sender=nil)直接 AV。挪到 public。
- [x] **B4 收工**。

---

## B5 · 单元格级鼠标事件 + 按钮单元格 + AutoResize 双击

- [x] `OnClickCell` / `OnDblClickCell` / `OnRightClickCell` / `OnCanClickCell`;
      放开 `MouseDown` 里 `if Button <> mbLeft then Exit` 的右键路径;
      表头右键 = 同一套命中的 fixed 分支(`OnHeaderClick` / `OnHeaderRightClick`)。
- [x] 按钮单元格 `gcdButton`:三态(normal/hover/pressed)走 `TyGridButton` token;
      点击触发 `OnCellButtonClick`。
- [x] 双击列分隔线 → `AutoFitColumn`。
- [x] 变异验证(右键不报告 / 否决不生效 / 按钮不触发 / 双击不自适应,四条各自杀掉对应测试)。
- [x] 踩到的坑:测试辅助 `ClickAt` **只发 MouseDown 不发 MouseUp**,而按钮格按设计是
      松开才算触发(按下后拖走应作废)—— 新增 `FullClickAt`。
- [x] **B5 收工**。

---

## B6 · 单元格换行 + 行高三件套

- [x] `OnGetCellWordWrap` + 换行绘制(复用 `TTyPainter` 的换行能力,表头格同享)。
- [x] **可写** `RowHeights[row]` 稀疏存储(现在只有 `OnGetRowHeight` 回调,网格自己不存
      → 拖拽和自动行高都无处落盘)。`RowHeightOf` 改为:显式存储 > 回调 > 默认。
- [x] 拖行分隔线改行高(对称复用 `FResizeCol` 那套状态机 → `FResizeRow`)。
- [x] `AutoFitRow` / `AutoFitRows`:按换行后的实际高度。
- [x] 变异验证。**两条第一次没被杀**:
      ① 换行:我先变异 `st.SingleLine`,但 LCL 的排版实际看的是 `Wordbreak` ——
         变异点选错了,不是测试弱。改变异 `st.Wordbreak` 才红。
      ② 显式行高驱动几何:测试里同时挂了 `OnGetRowHeight`,而回调本身就会逼出
         可变行高的前缀和路径 → "几何层认不认显式行高"根本测不出来。
         补了一段"没有回调、只有显式行高"的断言才红。
- [x] **B6 收工**。

---

## B7 · 选择模型重构 + 离散多选

- [x] 选区从"单锚点矩形"升成 `array of TRect`(显示序空间)+ 活动区间。
      单矩形是退化情形,**现有行为必须 0 回归**。
- [x] public API:`SelectAll` / `SelectRange` / `SelectRows` / `ClearSelection` /
      `Selection` / `SelectedCellCount`(目前一个 public 选择方法都没有)。
- [x] `OnSelectionChanged`。
- [x] Ctrl+点 追加离散行;鼠标拖选(插在 `inherited MouseMove` 之后、hint 之前)。
- [x] 变异验证(Ctrl 不固化 / 判定不看离散区 / 普通点不清离散区 / 拖选不挪光标,四条各自杀掉对应测试)。
- [x] 实现时踩到的真 bug:Ctrl+点的固化原本写在 `MoveCursor` **之后** ——
      光标是活动矩形的另一个角,先挪光标再固化,固化下来的是**已经被拉长**的那一块
      (Ctrl+点第 4 行会把 1..4 整段吞进去)。测试里"中间的行不该被连带选中"抓到了它。
- [x] **B7 收工**。

---

## B8 · 列模型:`TTyGridColumn`

**架构决策**:不往共享的 `TTyColumn`(ListView/TreeView 也用)里塞网格专属字段。

- [x] 派生 `TTyGridColumn = class(TTyColumn)`,让网格的 `TTyColumns` 创建它
      (`TCollection` 支持指定 ItemClass;若 `TTyColumns` 未开放则在 Grid 侧覆写创建)。
- [x] 新增列级属性:`EditorKind` / `ReadOnly` / `PickList: TStrings` /
      `SortKind` / `Aggregate` / `Format`。
- [x] `EditorKindFor` 改为:列属性 > `OnGetEditorKind` 覆盖 > `DefaultEditorKind`。
- [x] 失败测试:设计期只配列属性(不接任何事件)即可得到"这列数字、那列下拉、这列只读"。
- [x] 变异验证(列属性不参与决策 / 列级 ReadOnly 无效 / UseEditorKind 不置位 /
      列级 Aggregate 无效,四条各自杀掉对应测试)。
- [x] 共享单元的改动是**纯增量**:`TTyColumns.Create(AOwnerHeader, AItemClass)` 与
      `TTyHeader.Create(AColumnClass)` 两个重载,老调用点一行没动。
- [x] `UseEditorKind` 这个"设过没有"的标志是必须的 —— 光看"等于 gekText"
      分不清"没设"和"显式设成文本",测试里专门有一条守它。
- [x] **B8 收工**。

---

## B9 · EditLink 扩展点 + 输入约束 + 键盘录入手感

- [x] 抽 `TTyGridEditLink`(`CreateEditor` / `SetBounds` / `GetValue` / `SetValue` /
      `FocusEditor` / `HandleKey` / `ReleaseEditor`)+ `OnCreateEditLink` 事件。
      **只做了一半:内建的三个编辑器没有改写成 EditLink 实现。**
      理由:它们已经被一整批测试盯着、工作正常,重写只为"形式统一"而没有任何
      用户可见的收益,风险却是实打实的。EditLink 真正的价值在于**扩展点**
      (宿主接自己的编辑器),这一点已经完全达成 —— 宿主给了 link 就整格交给它,
      内建的一概不出场。
- [x] ~~内建"带省略号按钮"的逃生口~~ —— 有了 `OnCreateEditLink`,它就是宿主
      十几行代码的事;内建一个反而多一份要维护的 UI。
- [x] `ValidChars` / `MaxEditLength` 挂在**列**上(而不是 EditLink 上)——
      它们是"这一列的数据长什么样",与用哪个编辑器无关;挂列上设计期就能配。
      `EditMask` **未做**:掩码是一整套小语法(占位符/字面量/回填规则),
      应当作独立专题,塞进本批只会做成半成品。
- [x] 数值列即使没显式配 ValidChars 也自动带上数字字符集 —— 从前只在**提交时**
      校验,用户敲进一串字母、按回车才被弹回来。
- [x] 键盘:按可打印字符**直接进编辑**(现在 `KeyDown` 没有 `KeyPress` 覆写)、
      Enter 向下推进、Tab 按格推进(现在 Tab 会把焦点弹出网格)。
- [x] 变异验证(KeyPress 不进编辑 / ValidChars 不过滤 / Tab 不拦 / Enter 不推进 /
      EditLink 的值不采用,五条各自杀掉对应测试)。
- [x] **B9 收工**。

---

## B10 · 多级/合并表头

- [x] 表头模型 `TTyGridHeaderGroup` / `TTyGridHeaderGroups`(Text / FirstCol..LastCol / Level)。
      **做成"平铺一层组"而不是任意深的树**:真实报表里两级(分组 + 列)覆盖绝大多数场景,
      而任意深的树会把命中、拖列、排序按钮归属全部复杂化一个量级。Level 留着,
      要三级时再套一层即可。挂在网格上而不是共享的 Header 上 —— 与 B8 同一条理由。
- [x] 渲染:按 `HeaderBands` 逐级画,合并格跨列。
- [x] 命中:`CellAt` 的表头分支返回(级, 表头格),而不只是列。
- [x] 排序/筛选按钮只出现在**叶子级**。
- [x] 变异验证(分组带不占几何 / 分组带里也算叶子列头 / 分组带不画 / 排序不同步表头)。
- [x] **顺带挖出一个真 bug**:`SortByColumn` 只写自己的 `FSortCol`,从不同步
      `Header.SortColumn` —— 而 `hoShowSortGlyphs` 那个排序小三角看的正是后者,
      于是三角**一次都没画出来过**。又一个"属性存在却没人写"的洞(与 B1 同族)。
- [x] **B10 收工**。

---

## B11 · 多列排序 + 分组重做

- [x] 排序键升成 `array of (Col, Dir, Kind)`;Shift+点列头追加次级排序列。
- [x] 排序方式**降到列级**(混合表里日期列不再按文本排)。
- [x] `BuildGroups` **不再劫持 `FSortCol`**(现在一分组就悄悄丢掉用户选的排序列 —— 已知 bug)。
- [x] 多级分组 + 分组内排序 + 分组汇总行 + `ExpandAll` / `CollapseAll`。
- [x] 分组行文本 `'%s  (%d)'` 现**硬编码**在 `RenderGroupRow` 里
      → 抽成 `resourcestring` + 可配格式,并补 `.pot` / zh_CN `.po`。
- [x] 变异验证(只用第一个键 / 分组重新劫持 FSortCol / 列级 SortKind 无效 /
      CollapseAll 不记账,四条各自杀掉对应测试)。
- [x] 修法:分组列**临时插在有效键序列最前面**(EffectiveSortKeys),
      绝不写回 FSortKeys —— 这样"分组"与"用户的排序"就不再是同一份状态。
      顺带把"排两遍(先 FSortCol、BuildGroups 里再来一遍把结果盖掉)"合并成一遍。
- [x] 多级分组未做(FGroupCol 仍是单列)—— 它需要分组行本身也能嵌套,
      属于另一层数据结构;当前的单级分组 + 多列排序已能覆盖绝大多数用法。
- [x] **B11 收工**。

---

## B12 · 数据层批量 + 剪贴板事件

- [x] `InsertRows/RemoveRows/InsertCols/RemoveCols`(复数版)、`MoveRow/MoveColumn/SwapRows`。
- [x] **智能粘贴**:按剪贴板块大小自动扩行扩列。现在 `targetRow<0` 直接 `Break`,
      粘 100 行进 10 行的网格**静默丢 90 行**。
- [x] `CutToClipboard`;剪贴板事件族(`OnClipboardCopy/Paste/BeforePasteCell/AfterPasteCell`)。
- [x] 变异验证(回到静默丢行 / 不扩列 / 逐格否决不生效 / SwapRows 不换行高 /
      不换逐格属性,五条各自杀掉对应测试)。
- [x] SwapRows 那两条**第一次没被杀** —— 测试只换了文字,没设行高也没合并。
      补上之后才红。与 B3 修的 ShiftCells 是同一类疏漏:换行/搬行时容易只想到文字。
- [x] 批量操作统一走 `BeginUpdateOrder/EndUpdateOrder`(可嵌套),
      否则每插一行都要重建一遍 FOrder。
- [x] **B12 收工**。

---

## B13-B15 · MEDIUM 24 项

按对差结果的依赖顺序推进,每批 8-10 项,批内同样遵守收工条件。
明细见附录;每完成一项在附录里勾选。

- [x] **B13(M1-M9)完成** `2026-07-19`
  - M1 逐格边框(四支笔)`OnGetCellBorder`;没人接钩子时整个遍历都省掉
  - M2 焦点格外观 `TyGridActiveCell` token —— 整行选中模式下终于看得出光标在哪一格
  - M3 逐格**持久**外观 `CellColors` / `CellTextColors` / `SetRowColor`(落在 B3 建的属性存储里)
  - M4 表头自绘钩子 `OnGetHeaderStyle`
  - M5 表头图标 —— **已在 B1-3 完成**
  - M6 列拖动重排事件 `OnColumnMove`(MoveRow/SwapRows 已在 B12 完成)
  - M7 智能粘贴 —— **已在 B12 完成**
  - M8 行高/列宽上下限;钳制放在**存储入口**,拖拽/AutoFitRow/直接赋值走同一道关
  - M9 `OnColumnSizing` / `OnEndColumnSize` / `OnRowSizing` / `OnEndRowSize`
  - M16 逐格 `CellReadOnly`(顺手做了,它与 M3 共用同一个属性条目)
  - 四处变异各自杀掉对应测试
- [x] **B14(M10-M19)完成** `2026-07-19`
  - M10 行的显式隐藏 HideRow/UnHideRow/IsHiddenRow/NumHiddenRows/UnHideAllRows。
    **隐藏与过滤是两回事**:过滤是条件,隐藏是事实 —— ClearFilters 不该把手工
    隐藏的行放出来。判定放在 RowPassesFilter 最后,连 OnFilterRow 说"要"也盖不过去。
  - M11 离散列多选 —— B7 的矩形组已天然支持(gsmColumn 模式下的离散矩形)
  - M12 选区聚合 SelectionSum/Avg/Min/Max,非数值格跳过、不污染统计
  - M13 勾选框事件 OnCanToggleCheck / OnCheckBoxChange(切换成功了才通知)
  - M14 选区外框与拖拽手柄 —— **未做**,见下方说明
  - M15 导航跳过只读格 SkipReadOnlyCells:沿**移动方向**继续找,而不是原地不动
    (原地不动的话方向键像撞墙,用户以为网格卡了)
  - M16 逐格 ReadOnly —— 已在 B13 完成
  - M17/M18/M19 编辑器细节 —— **未做**,见下方说明
  - 四处变异各自杀掉对应测试

  **未做的三项及理由**(不是遗漏):
  - M14 选区外框 + 右下角拖拽手柄:手柄要能拖出"填充序列"的语义(Excel 的填充柄),
    否则只是个装饰。填充语义本身是一整个专题(等差/复制/自定义序列),
    单画一个手柄反而给出错误的可供性。
  - M17 `OnGetEditorProp` / M18 数值 spin / M19 下拉宽度与自动扩宽:
    这三项都是**内建编辑器**的细化,而 B9 已经给出了 `OnCreateEditLink` 逃生口 ——
    宿主要特殊编辑器就自己接一个,比我们把内建的三个越做越厚更合理。
    等真实使用中出现"绝大多数人都要"的需求再内建。
- [x] **B15(M20-M24)+ 收尾完成** `2026-07-19`
  - M20 过滤条件类型化(包含/等于/开头是/结尾是/> >= < <=)+ `ColumnIsFiltered` +
    `FilteredRowCount` + **漏斗激活态**(用户得一眼看出哪列在过滤中,
    否则"为什么少了几行"会变成一次排查)。
    数值比较里非数值格**一律不通过** —— 把 'abc' 当 0 会让"筛 >-1"把整列文本放进来。
    内嵌过滤编辑行 / 多列 AND-OR-XOR **未做**:前者要再占一条表头带且与分组带的
    交互没想清,后者需要一整套条件树 UI 才有意义,单给个 API 用不上。
  - M21 多列排序徽标(单列排序时不显示 —— 没有歧义就别加噪音)
  - M22 排序细则:`BlanksPosition` / `SortIgnoreCase` / `OnCanSort`。
    **顺带修了一个既有 bug**:空值判定原本写在 `CompareRows` 里,而方向翻转发生在
    它**之后** —— 一翻向,空行就整块冒到最上面。判定必须提到方向翻转之前。
  - M23 分组计数格式可配 —— 已在 B11 完成(`GroupRowFormat` + resourcestring)
  - M24 通用大纲节点 / 树形单元格 —— **未做**:审计时就写明"工作量 large,
    建议单独一期",且 B11 的分组已覆盖大部分层级展示诉求。纯 TreeGrid 是第二形态。
  - [x] `docs/controls/grid.md` 全量重写(能力一览 / 两条不变量 / 性能笔记 / 明确不做)
  - [x] `docs/controls/README.md` 的网格条目更新
  - [x] CHANGELOG 中英双份(按"只写用户可感知的影响"的规矩写)
  - [x] i18n:`rsGridGroupRow` 进 `StrConsts` + `.pot` + zh_CN `.po`
  - [x] 示例演示新增能力:列级声明、分组表头、斑马纹、换行、行高护栏、
        筛选按钮、状态栏选区聚合
  - [x] 全量:两包 + 示例 `-B` + 生成器幂等 + `grep -c MUTATION` = 0

---

## 附录 · 对差明细

原始 203 条、合并后 HIGH 19 / MEDIUM 24 / LOW 17 / SKIP 12 类。
完整清单见工作流输出:`wu7x7a79f`(已归档到本目录 `2026-07-19-grid-gap-audit.md`)。

**SKIP(不做,别反复纠结)**:PDF/打印子系统 · XLS 原生读写 · Word/MDB ·
HTML 富文本单元格 · RichEdit 单元格 · 预置外观样式集(`TAdvGridStyle` 27 值 ——
AdvGrid 在控件里硬编码几千行 case 上色,我们的等价物就是 `.tycss` + typeKey,
照抄等于把皮肤职责搬回控件) · ControlLook 位图槽 · 固定格画成按钮 ·
Ansi/Wide 双钩子(FPC 全程 UTF-8) · Fixed 私有格式 · 搜索页脚 · OLE 拖放。

**LOW 17 项**:多为上面各项的语法糖或退化情形,HIGH+MEDIUM 做完后重新评估,
大概率其中过半会被自动覆盖。
