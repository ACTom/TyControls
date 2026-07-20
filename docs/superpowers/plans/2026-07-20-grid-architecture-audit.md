# TTyGrid 架构审计(2026-07-20)

**背景**:57 个提交的功能补齐之后,维护者怀疑积累了绕行与特殊处理,要求先审计再重构。
用 5 个独立视角并行审计 + 对高危项逐条**对抗复核**(refute-by-default)。

**结论先说**:值得重构,但**首先要修的是审计挖出来的真 bug** —— 其中多个是
2026-07-19/20 这轮刚交付的功能,已经在 main 或 feat/grid-p3 上。
重构必须建立在"当前行为是对的"之上,否则是在错误行为上做结构调整。

---

## A. 已确认的 bug(复核未被推翻)—— 先修这些

> **进度**:A 组**全部修完**(2026-07-20)。A2 · A4 · A3 · A5 先修;
> A1 · A6 · A7 在本轮修完,每条都先红后绿 + 变异验证 + 单独提交。
> 修 A5 时**顺带挖出第 8 个 bug**:右冻结列锚在 `ClientWidth` 而窗格锚在 `ViewportW`,
> 整条右冻结带右移一个滚动条宽、最右一列被裁 —— 已一并修掉。
> 修 B2 时**又挖出第 9 个**:`SwapRows` 不搬隐藏标记 —— 藏着的行换个位置就冒出来。

### A1【高】✅ 已修 · `CellPane` 用**显示序**的判据去判**数据行**参数
`source/tyControls.Grid.pas:3531-3552`
```pascal
if ARow < FFixedRows then ...
if (FFixedRowsBottom > 0) and (ARow >= DisplayRowCount - FFixedRowsBottom) then ...
```
两个判据都是显示序语义,但唯一的绘制调用方 `CellVisibleRect:3566-3567` 传的是**数据行**
(同一行的 `CellRect(ACol, ARow)` 内部还要 `DataToDisplay(ARow)`)。

**代价**:`FixedRows > 0` 且有排序/筛选/分组时,**数据下标 < FixedRows 的格子一律被判成
gpTop**,与冻结带求交后变成空矩形 —— 它们滚到哪儿都不画,行**静默变空白**。
反过来,真正显示在冻结带里的行被判成 gpBody 而被裁掉。

同族:`FrozenHeightPx:2351` 与 `FrozenBottomPx:2249` 把显示位置喂给 `RowHeightOf`
(数据行查表),可变行高时冻结带厚度取的是**另外几行**的高度。
对照 `RowTops:5962` 是对的(先 `DisplayToData` 再 `RowHeightOf`)。

**已修**(`c5ed5e4`):空间写进了签名 —— `CellPane(ACol, APos)` 收显示位置,
`CellVisibleRect` 做唯一一次转换;`RowHeightOfDisplay(APos)` 供冻结带厚度用。
守卫:`TestFixedRowsAndSortTogetherKeepCellsInTheirPane`(FixedRows=2 + 降序,
逐个数据行断言可见矩形非空且等于几何矩形)、
`TestFrozenBandThicknessFollowsDisplayedRows`(可变行高 + 排序,上下两条带各一条)。
三处修改点逐一变异,均变红。

**关于类型级修法的判断**:不值得。FPC 的 `type TDataRow = type Integer` 仍能自由赋给
Integer 而不报错;记录 + 运算符重载要穿透上万行的行下标算术(`ARow + i`、
`pos - FMaxRowSpan + 1`、跨度计数),换不来编译期保证。
**命名纪律(`ARow`=数据 / `APos`=显示,文件里已有约八成遵守)+ 少数几个转换收口点
才是这里的天花板。**

### A2【高】✅ 已修 · 多级分组只按**第一个**分组列排序 —— 我昨天刚交付的 P6 是坏的
`source/tyControls.Grid.pas:9044-9049` `EffectiveSortKeys` 只 prepend `GetGroupCol`
(= `FGroupCols[0]`),而 `BuildGroups:5534` 按**每一级**切段,且完全依赖相邻性
(它自己的注释 5455 就写着"必须在排序之后 —— 否则同组的行不相邻,切不出段")。

**代价**:两级以上分组时,第二级的键不连续 → 同一个子组标题在列表里**反复出现**,
每个还带着错的计数与小计。真实数据上必然发生。
**我的测试没抓到,是因为 fixture 恰好本来就是聚簇的** —— 又一次假绿。

**修法**:`EffectiveSortKeys` 把 `FGroupCols` 全部按序 prepend;去重改成"是否属于
FGroupCols"而不是"是否等于 FGroupCols[0]"。把 `GetGroupCol` 改名 `OutermostGroupCol`
(它读起来像"那个分组列",实际是"最外层那个",正是这次迁移漏掉的原因)。

### A3【高】✅ 已修 · `ApplyOrderToData` 根本没搬**格属性**,而注释说搬了
`source/tyControls.Grid.pas:8914` 声明了 `attrSnap`,**全文件仅此一处** —— 从未填充、
从未写回。注释 8908-8910 却明确承诺"底色/合并跨度/只读…都跟着走"。

**代价**:`gsmData` 物理排序后,文字换了位置而底色/文字色/只读/合并跨度**留在原地**,
装饰到不相干的数据上;陈旧的 rowspan 会让 `CellRect` 声称占有它已经不拥有的行,**画到邻行上**。
更糟:写回走 `Cells[]` 所以**文字可撤销、属性不可撤销** ——
Ctrl+Z 之后得到一个从未存在过的状态。

**修法**:照 `ShiftCells` 已有的做法(`FAttrs.SnapshotKeys/MoveEntry/Ensure/Remove`)。
注意属性对象是引用类型,直接 move-then-move 会 alias —— 用 `SwapRows:7172` 那个
"经哨兵键三步换"的写法,或先按值快照。
**守卫**:给某行设一个显眼的 CellColor,gsmData 排序,断言颜色跟着文字走。

### A4【高】✅ 已修 · `gekTime` 编辑提交的是 `DateToStr` → 写进单元格的是 "1899-12-30"
`source/tyControls.Grid.pas:9745`。开编辑按**种类**分派(9601-9612 设 `Kind := dtkTime`),
关编辑按**控件可见性**分派(9722-9726 只看 `FDateEditor.Visible`)——
而 `FDateEditor` **一个控件服务两种种类**,可见性无法区分它们。
复核实测:`GetDate = Trunc(FDateTime)`(DateTimePicker.pas:1541),时间只有小数部分
→ `DateToStr(0)` = "1899-12-30"。

附带:`dtkDate` **全文件从未被赋值过** → 编辑过一次时间格之后,共享的日期选择器
**永久停在时间模式**,此后日期列弹出的是时间选择器。
(9642 的 PasswordChar 注释"每次都要显式设回去,否则上一格的遮罩会留下来" ——
这条教训在 `FEditor` 上学过一次,没有推广到 `FDateEditor`。)

**代价**:数据损坏(用户输入的时间被丢弃、写入一个错误日期)。
**修法**:开编辑时把**实际打开的种类**记进 `FEditKind`,`EndEdit` 按它分派,
不再从可见性反推。每个分支还必须把它没设的共享属性显式设回默认(Kind / PasswordChar /
Alignment / CharCase)。
**低风险的临时修法**:9744 处按 `FDateEditor.Kind` 分支,9527 处补 `Kind := dtkDate`。

### A5【中】✅ 已修 · `CellPane` 的顶部带只做**两路**分割,底部带做了**三路**
`3536-3540` vs `3541-3547`。`gpTopRight` 在整个仓库**没有任何生产者**。
**代价**:同时开启 `FixedRows` 与 `FixedColsRight` 时,右上角那块被判成 gpTop,
与顶部带(不含右冻结列)求交 → 右上角的格子被裁没。

### A6【中】✅ 已修 · `ActiveSelectionRect` 在锚点行被筛掉时退化
`DataToDisplay` 对被筛掉/隐藏的行返回 -1,而这里直接参与 Min/Max。
**代价**:选中若干行后再筛掉其中一行,活动选区矩形从 -1 起算,选中范围突然扩到表头。
**已修**(`598efc5`):锚点没有显示位置时退化成"只有光标那一行"。
守卫:`TestFilteringOutTheAnchorDoesNotGrowTheSelection`。

### A7【中】✅ 已修 · `SwapRows` 搬了三种状态,只有一种进了撤销栈
文字走 `Cells[]`(被记录),`FAttrs.MoveEntry` 与 `RowHeights` 交换**没被记录**。
**代价**:拖行/上移下移之后 Ctrl+Z,文字回来了、底色和行高没回来。
**没有**按"补一条 gukRowSwap"来修(复核指出那会与逐格 gukCell 条目双重施加)。
**已修**(`5d714db`):给两个存储各自一个记录点,与 SetCells/SetRowCount 同一种做法 ——
`TTyGridCellAttrStore.OnChanging`(建/改/删任一条之前发通知,按值快照)
+ `SetRowHeights` 改 virtual 并记录钳制后的旧值。
`Find` 从此是只读视图,要改字段得走新的 `Mutate`。
**顺带**:合并/取消合并也可撤销了 —— P3 当初明确留下的偏离一并补上,
`RestoreAttr` 会对账 `FMergeCount` 与跨度提示。
守卫:`TestUndoRestoresCellAttributesAndRowHeights`(交换 → Undo → Redo,
行高用几何断言)、`TestUndoRestoresCellColorAndMerge`(新建路径与**清除**路径各一条)。
三个记录点逐一变异,均变红。

---

## B. 结构性问题(重构的正题)

> **进度**:B1 · B2 · B3 已做完(2026-07-20)。B4 待评估 —— 见文末。

### B1 ✅ 已做 · 规则被逐处重述,而不是收口
已确认的实例:
- **裁到所属窗格**:单元格文字 / 行号 / 横格线 / 选区外框 —— 四处,每处都是漏了才发现。
- **移动光标要重锚选区**:曾写在 4 个调用点,已收口进 `MoveCursor`(这次做对了)。
- **逐行循环必须走槽位**:10 处,已收口进 `TyGridRowAtSlot`(这次做对了)。
- **十来个编辑器分支**各自 `SetBounds/Visible/SetFocus/Exit`;加一个事件只能靠外面
  包一层 `DoBeginEdit`(A4 就是这个结构的直接后果)。

**方向**:凡是"必须在 N 处都做对"的规则,都要有一个**过不去的收口点**。
绘制侧建议引入 `DrawInPane(APane; ...)` 之类的包装,让"裁剪"不可能被跳过。

**已做**(`d663277`):带的几何只剩一处出处 `TyGridRowBandRect`(几何层);
绘制走 `DrawInRowBand`(跨列的 chrome)/ `DrawInPane`(有列归属的 chrome),
两者都收**嵌套过程**当绘制动作 —— 不交给它们就根本画不出来,"忘了裁剪"在结构上不再可能。
行为零变化(3859/0/12);把任一个包装里的求交去掉,逐像素一致性测试立刻变红。
(为此给单元加了 `{$modeswitch nestedprocvars}`。)

### B2 ✅ 已做 · 行下标为键的旁挂表没有登记处
`FRowHeights`、`FHiddenRows` 是纯行下标键;`FCells`/`FAttrs` 是二维格键。
三条置换路径(`ShiftCells` 增删行 / `SwapRows` / `ApplyOrderToData`)**各覆盖了不同的子集**
—— A3、A7 都是这个的具体表现。
**方向**:一个"所有按行记账的存储"的登记表 + 一个统一的 `PermuteRows(const AMap)`,
三条路径都走它。新增一张旁挂表时只需登记,不必再去改三个地方。

**已做**(`604521b`),但**没做成登记表**:两条**纯置换**路径(`SwapRows` /
`ApplyOrderToData`)收口进 `PermuteRowState(AMap)`;增删行是另一类(行数会变),
仍收口在 `ShiftRowKeyedTable`。这类存储只有两张,而它们的写回路径本就不同
(行高必须走 `SetRowHeights` —— 撤销的记录点在那儿),为两张表建注册框架
读起来比它替掉的重复更难。新增第三张表时改这两处。
**顺带挖出并修掉第 9 个 bug**:`SwapRows` 不搬隐藏标记 ——
标记留在旧下标上,换过去的那一行凭空消失、藏着的那一行冒出来。
守卫:`TestSwappingRowsCarriesTheHiddenFlag`(走一遍显示序看**谁被显示出来**,
不看标记本身)。

### B3 ✅ 已做 · 十亿行的说法在写入侧偏薄
- 页脚汇总**每帧**遍历全部显示行(`RenderFooter → AggregateValue`)。
  百万行时每帧 O(n) —— 需要按"过滤/数据变更"失效的缓存。
  **已做**(`a4eb201`):逐列缓存,失效挂在三个**既有**收口点上 ——
  `SetCells`(数据)/ `InvalidateOrder`(筛选、隐藏、分组、行数增删都汇到这儿)/
  `SetColumnAggregate`(口径)。挂了 `OnGetCellText` 的表**不缓存**:
  宿主随时改值而控件收不到通知,缓存住就是把一个陈旧的合计钉在页脚上 ——
  慢比错好。`AccumulateCell` 改 virtual,测试靠它数"一帧扫了多少格"
  (只断言结果对不对,分辨不出"每帧重算"和"用了缓存")。
  三个失效点逐一变异,均变红。
- `DistinctColumnValues/Counts` 每次开筛选下拉扫全表(设计如此,但百万行会卡)。
- `FOrder`/`FRank` 是两个 RowCount 长的 Integer 数组(百万行 8MB,可接受)。

### B4 ✅ 已评估并收尾 · 单文件 ~9950 行
`TTyCustomGrid` ~2500 / `TTyDrawGrid` 小 / `TTyStringGrid` ~6000,外加列类、属性存储、
撤销、筛选、分组、导出、剪贴板、编辑器、渲染。
**不该外移**:渲染与几何(与内部状态强耦合,`Grid.Layout.pas` 已经把纯几何拆干净了)。

**四个候选逐个查过真实代码之后,只有一块是干净的**(`afda96f`):

| 候选 | 规模 | 结论 |
|---|---|---|
| 纯文本编解码器 `TyCsvQuote`/`TyCsvParse`/`TyHtmlEscape` | 97 行 | ✅ **已外移**到 `tyControls.Grid.Csv.pas` —— 本来就是自由函数,不碰任何网格状态,搬家不需要给网格开新口子 |
| `TyCsvSplit` | 41 行 | ✅ **已删** —— 死代码,被字符级解析器取代后全仓库无人调用 |
| 撤销栈 | 净 ~110 行 | ❌ **不做** —— 要一个约十成员的回调接口 + 放开私有字段 |
| 筛选 / 分组的模型 | 55 / 152 行 | ❌ **不做** —— 纯算法核很小,而搬出去要让签名暴露内部状态 |
| 导出/剪贴板的其余部分 | 285 行 | ❌ **不做** —— `SelectionAsText` 直接读 `FSelAnchorCol/Row`(全无访问器),`PasteFromText` 会改 `RowCount` 和列模型;"导出是只读所以耦合弱"这个前提**不成立** |

净效果 10409 → 10308 行。**小,而这正是这一项真实价值的诚实度量。**
后三项别再重开:代价是"用多一个接口换掉少一处重复",而这个文件的每一次机械重构
历史上都出过事。

**这次评估顺带挖出第 10、11 个 bug**(与拆分本身无关,见下)。

---

## D. 评估 B4 时挖出来的(与拆分无关,已修)

### D1【高】✅ 已修 · 批量操作**没有**算一条撤销记录,尽管头文件里一直这么写
`PasteFromText` / `InsertRows` / `RemoveRows` 开的是 `BeginUpdateOrder`(压重排),
而撤销事务在 `BeginUpdate → OpenUndoGroup`;`CutToClipboard` 一点批量都没有。
实测:2×2 粘贴压 4 条、2×2 剪切 4 条、`InsertRows(0,3)` **25 条**、`RemoveRows(0,2)` 9 条。
点一下要按二十五次 Ctrl+Z。
**单数**的 `InsertRow`/`DeleteRow` 一直是对的 —— 规则又一次被逐处重述而不是收口,
与本轮 B1 那个裁剪缺陷同一个形状。
**已修**(`1dcb013`)。守卫:`TestPasteAndCutAreOneUndoStepEach` ——
断言站在用户那一侧(**按一次撤销,整块都得回来**),不是只数栈深。

### D2【高】✅ 已修 · `ClearCells` 绕过收口点 → 清空与"导入 CSV"都撤不回来
它直接 `FCells.Clear`,不经过 `SetCells`。**收口点保证的只是经过它的改动。**
连带两个后果:清空不可撤销;导入 CSV 整件事也不可撤销(导入第一步就是清空)。
同一个绕行还让 B3 那个挂在 `SetCells` 上的汇总失效够不着 ——
**清空一张表之后页脚还挂着旧的合计**。
**已修**(`5ccdad1`):先逐条记原值再整表清掉(记的东西一样,省掉逐格拆字典的开销),
`LoadFromCSVText` 把"清空 + 改行数 + 重填"包成一条事务。
守卫:`TestClearAndCsvImportAreUndoable`。

---

## C. 执行顺序(已全部走完 2026-07-20)

1. **A2、A4** —— 最便宜、且都是**数据/功能级**错误,各自一处改动。
2. **A3、A7** —— 属性与行高的置换/记录,和 B2 的收口一起做更划算。
3. **A1、A5** —— `CellPane` 的空间与三路分割,一起改,带上"固定行 + 排序"的叠加测试。
4. **A6** —— 选区矩形对 -1 的处理。
5. **B1** 绘制侧收口 → **B2** 行置换收口 → **B3** 汇总缓存 → **B4** 拆文件。

**每一项的收工条件同 grid-remaining 计划**:先红后绿、变异验证、全量、示例重建。

**特别提醒(本轮审计给出的最重要一条)**:
A2 和 A3 都是"功能刚交付、测试全绿、但真实数据上是坏的"。
两次的原因相同 —— **fixture 太温和**:A2 的分组数据本来就聚簇,A3 从没在排序后检查属性。
新增功能的测试必须问一句:**这份数据能把这条规则改坏的实现区分出来吗?**

---

## E. 收尾时的账(2026-07-20)

**11 个 bug**:审计原本认定 7 个(A1-A7),修的过程中又冒出 4 个 ——
第 8 个在修 A5 时(右冻结带锚错基准)、第 9 个在做 B2 时(交换不搬隐藏标记)、
第 10、11 个在**评估 B4** 时(D1 批量撤销、D2 清空绕过收口点)。
**后两个是读代码找拆分边界时发现的,没有任何测试指向它们** ——
"为了搬家而通读一遍"本身就找出了两个数据级缺陷,这是这一项唯一算得上大的收益。

**贯穿全程的同一个形状**:一条规则被要求"在 N 处都做对"。
裁剪(4 处)、行置换(3 处)、批量撤销事务(单数对、复数错)、
收口点被绕过(`ClearCells`)—— 四次都是同一种失败。
**判据**:凡是写下"记得也要 X"的注释,那里就该有一个过不去的入口,而不是一条注释。

测试:3863 通过 / 0 失败 / 12 已知错误(win32 控件创建,基线如此)。
每条修复都先红后绿 + 逐个修改点变异验证 + 单独提交。
