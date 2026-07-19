# TTyGrid 架构审计(2026-07-20)

**背景**:57 个提交的功能补齐之后,维护者怀疑积累了绕行与特殊处理,要求先审计再重构。
用 5 个独立视角并行审计 + 对高危项逐条**对抗复核**(refute-by-default)。

**结论先说**:值得重构,但**首先要修的是审计挖出来的真 bug** —— 其中多个是
2026-07-19/20 这轮刚交付的功能,已经在 main 或 feat/grid-p3 上。
重构必须建立在"当前行为是对的"之上,否则是在错误行为上做结构调整。

---

## A. 已确认的 bug(复核未被推翻)—— 先修这些

### A1【高】`CellPane` 用**显示序**的判据去判**数据行**参数
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

**修法**:把空间写进签名而不是靠约定 —— `CellPane(ACol, APos)` 收显示位置,
`CellVisibleRect` 做唯一一次转换;加 `RowHeightOfDisplay(APos)` 给冻结带厚度用。
只有 2 个调用点(3567、9833)。
**守卫**:`FixedRows=2` + 降序排,断言每个数据行的 `CellVisibleRect` 落在正确窗格。
现有测试测不到 —— 它们**分别**测固定行和排序,从不叠加。

**关于类型级修法的判断**:不值得。FPC 的 `type TDataRow = type Integer` 仍能自由赋给
Integer 而不报错;记录 + 运算符重载要穿透上万行的行下标算术(`ARow + i`、
`pos - FMaxRowSpan + 1`、跨度计数),换不来编译期保证。
**命名纪律(`ARow`=数据 / `APos`=显示,文件里已有约八成遵守)+ 少数几个转换收口点
才是这里的天花板。**

### A2【高】多级分组只按**第一个**分组列排序 —— 我昨天刚交付的 P6 是坏的
`source/tyControls.Grid.pas:9044-9049` `EffectiveSortKeys` 只 prepend `GetGroupCol`
(= `FGroupCols[0]`),而 `BuildGroups:5534` 按**每一级**切段,且完全依赖相邻性
(它自己的注释 5455 就写着"必须在排序之后 —— 否则同组的行不相邻,切不出段")。

**代价**:两级以上分组时,第二级的键不连续 → 同一个子组标题在列表里**反复出现**,
每个还带着错的计数与小计。真实数据上必然发生。
**我的测试没抓到,是因为 fixture 恰好本来就是聚簇的** —— 又一次假绿。

**修法**:`EffectiveSortKeys` 把 `FGroupCols` 全部按序 prepend;去重改成"是否属于
FGroupCols"而不是"是否等于 FGroupCols[0]"。把 `GetGroupCol` 改名 `OutermostGroupCol`
(它读起来像"那个分组列",实际是"最外层那个",正是这次迁移漏掉的原因)。

### A3【高】`ApplyOrderToData` 根本没搬**格属性**,而注释说搬了
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

### A4【高】`gekTime` 编辑提交的是 `DateToStr` → 写进单元格的是 "1899-12-30"
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

### A5【中】`CellPane` 的顶部带只做**两路**分割,底部带做了**三路**
`3536-3540` vs `3541-3547`。`gpTopRight` 在整个仓库**没有任何生产者**。
**代价**:同时开启 `FixedRows` 与 `FixedColsRight` 时,右上角那块被判成 gpTop,
与顶部带(不含右冻结列)求交 → 右上角的格子被裁没。

### A6【中】`ActiveSelectionRect` 在锚点行被筛掉时退化
`9161-9167`:`DataToDisplay` 对被筛掉/隐藏的行返回 -1,而这里直接参与 Min/Max。
**代价**:选中若干行后再筛掉其中一行,活动选区矩形从 -1 起算,选中范围突然扩到表头。

### A7【中】`SwapRows` 搬了三种状态,只有一种进了撤销栈
`7142-7187`:文字走 `Cells[]`(被记录),`FAttrs.MoveEntry` 与 `RowHeights` 交换**没被记录**。
`TTyCustomGrid.SetRowHeights:3052` 完全不记账。
**代价**:拖行/上移下移之后 Ctrl+Z,文字回来了、底色和行高没回来。
**注意**:复核指出"补一条 gukRowSwap"的修法是**错的** —— 同一条记录里已经有逐格的
gukCell 条目,会**双重施加**。要么在 SwapRows 期间抑制 SetCells 记录,要么给属性
单独的记录点。

---

## B. 结构性问题(重构的正题)

### B1 规则被逐处重述,而不是收口
已确认的实例:
- **裁到所属窗格**:单元格文字 / 行号 / 横格线 / 选区外框 —— 四处,每处都是漏了才发现。
- **移动光标要重锚选区**:曾写在 4 个调用点,已收口进 `MoveCursor`(这次做对了)。
- **逐行循环必须走槽位**:10 处,已收口进 `TyGridRowAtSlot`(这次做对了)。
- **十来个编辑器分支**各自 `SetBounds/Visible/SetFocus/Exit`;加一个事件只能靠外面
  包一层 `DoBeginEdit`(A4 就是这个结构的直接后果)。

**方向**:凡是"必须在 N 处都做对"的规则,都要有一个**过不去的收口点**。
绘制侧建议引入 `DrawInPane(APane; ...)` 之类的包装,让"裁剪"不可能被跳过。

### B2 行下标为键的旁挂表没有登记处
`FRowHeights`、`FHiddenRows` 是纯行下标键;`FCells`/`FAttrs` 是二维格键。
三条置换路径(`ShiftCells` 增删行 / `SwapRows` / `ApplyOrderToData`)**各覆盖了不同的子集**
—— A3、A7 都是这个的具体表现。
**方向**:一个"所有按行记账的存储"的登记表 + 一个统一的 `PermuteRows(const AMap)`,
三条路径都走它。新增一张旁挂表时只需登记,不必再去改三个地方。

### B3 十亿行的说法在写入侧偏薄
- 页脚汇总**每帧**遍历全部显示行(`RenderFooter:7761 → AggregateValue:7690`)。
  百万行时每帧 O(n) —— 需要按"过滤/数据变更"失效的缓存。
- `DistinctColumnValues/Counts` 每次开筛选下拉扫全表(设计如此,但百万行会卡)。
- `FOrder`/`FRank` 是两个 RowCount 长的 Integer 数组(百万行 8MB,可接受)。

### B4 单文件 ~9950 行
`TTyCustomGrid` ~2500 / `TTyDrawGrid` 小 / `TTyStringGrid` ~6000,外加列类、属性存储、
撤销、筛选、分组、导出、剪贴板、编辑器、渲染。
**可以外移**(耦合弱):导出/剪贴板、撤销栈、筛选与分组的**模型**部分。
**不该外移**:渲染与几何(与内部状态强耦合,`Grid.Layout.pas` 已经把纯几何拆干净了)。

---

## C. 建议的执行顺序

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
