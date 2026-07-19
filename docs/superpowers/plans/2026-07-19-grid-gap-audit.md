# TTyGrid 对标 TAdvStringGrid — 功能对差全文

> 2026-07-19,由 10 个 agent 系统盘点 `D:\Projects\Packages\Advgrid.pas`(66142 行)
> 并与当时的 `source/tyControls.Grid.pas` 逐项对差得出。原始 203 条,合并去重后
> **HIGH 19 / MEDIUM 24 / LOW 17 / SKIP 12 类**。
>
> ⚠️ **版权边界**:本文只记录"参照物有哪些功能"用于对差,不含其任何代码。
> TTyGrid 是独立实现,见 `2026-07-18-grid-control.md` 开头的版权说明。
>
> 实施计划见 `2026-07-19-grid-parity.md`;架构复评见
> `../design/2026-07-19-grid-architecture-review.md`。

---

# TTyGrid 开发计划(TAdvStringGrid 对差合并版)

来源:10 个领域盘点共约 150 条,合并去重后 = **HIGH 19 项 / MEDIUM 24 项 / LOW 17 项 / SKIP 12 类**。
合并原则:同一件事在不同领域被报为"缺渲染"和"缺事件"的,一律并成一条;凡是"能力已有、只差接线"的与"要改契约"的分开排。

---

## 先消解三处矛盾(动手前必须 15 分钟核查)

| # | 矛盾 | 处理 |
|---|---|---|
| C1 | 「行列结构」说 *Grid.pas 里没有任何拖动列的实现代码*;「事件面」说 *我们已实现列拖动重排(MouseMove 里有拖列逻辑)*;「表头 have」说 *hoDrag + Columns.AdjustPosition(1343) 已有* | 以后两条为准的可能性大(AdjustPosition 有明确行号)。**核查结论决定 M6 是"实现"还是"只补事件"**,是本计划里唯一优先级可能整档移动的条目 |
| C2 | 「选择导航」说 `MouseMove` 第一句就是 `if not Assigned(FOnGetCellHint) then Exit;`,与 C1 的"MouseMove 里有拖列逻辑"直接冲突 | 大概率 resize/drag 分支在那句 **之前**,而 hint 之后再无逻辑 → 拖选(H8)要插在那句之前。核查后确认插入点 |
| C3 | 「表头」报的 `OnGetCellIndent` 在 AdvGrid 全文 grep 不到 | 已确认不存在,不立条目(见 L 区说明) |

---

## HIGH(19)

### P0 — 契约层,必须最先定(改了它后面全部返工)

**H1. 几何契约一次性扩展:四向冻结 + 网格线线宽 + 表头带多行**
合并自:右侧冻结列(表头 low / 行列结构 medium)、底部冻结行、`GridLineWidth`(视觉 high)、多级表头的表头带高度(表头 high)。
把 `TTyGridMetrics` 的 `FrozenW/FrozenH` 两个标量升成 `FrozenLeft/Right/Top/Bottom` 四向 + `HeaderBands[]` 行数组 + `GridLineWidth` 参与像素分配。**只改几何与命中,不做上层交互**。
依赖:无。**被 H2/H5/H9/H16/M4/M9 依赖。**
用户可见:暂时看不到新功能,但网格线可以变粗,右侧/底部冻结区已能滚动裁剪正确。

**H2. 渲染管线逐格化(逐格 ResolveStyle + hover 状态机)**
合并自:hover 高亮(视觉 high + 单元格外观 medium)、`RenderHeaderSections` 循环外只 ResolveStyle 一次(1391-1392)、`tysHover` 零命中。
`light.tycss:499/507` 已经写好 `TyGridCell:hover` / `TyGridHeaderSection:hover` **但永远不触发** —— 这是"皮肤已写、代码没接"的洞。要把 ResolveStyle 移进逐格/逐段循环,并在 MouseMove 里记录 hover 行/列。
依赖:H1(线宽影响格矩形)。**被 H3/H4/H6/H7/M1/M2 依赖 —— 所有逐格外观都挂在这条管线上。**
用户可见:鼠标划过表格,行/表头会亮起来;表格从"死的"变成"活的"。

**H3. 逐格外观钩子族:`OnGetCellColor` / `OnGetAlignment` / `OnGetWordWrap` / `OnGetFormat`**
合并自:单元格外观 high×2、事件面 high(逐格外观回调)、编辑器区的对齐诉求。
一套 `var ABrush/AFont/HAlign/VAlign` 式钩子,取代"要改个底色就得 OnDrawCell 重画整格"。同时补 **垂直对齐**(现在 DrawText 恒 `tlCenter`)。
依赖:H2。**被 M3(逐格持久外观数组)、L 区所有语法糖(正负数着色/修改标记)依赖。**
用户可见:三行宿主代码即可"超期行标红""合计行右对齐",文字排版仍由控件负责。

**H4. 行交替色(斑马纹)**
合并自:视觉 high + 单元格外观 high(同一件事)。
只需 `RenderCells` 铺底时按显示行号取 `TyGridCell:alternate` token(light.tycss 需补键)。
依赖:H2。
用户可见:装上就"像个正经表格"了。

**H5. 单元格级鼠标事件 + 公开 hit-test:`OnClickCell` / `OnDblClickCell` / `OnRightClickCell` / `OnCanClickCell`,含表头段命中**
合并自:事件面 high、表头右键菜单 high(`OnHeaderClick`/`OnHeaderRightClick`)。
当前 `MouseDown` 里 `if Button <> mbLeft then Exit` 要放开右键路径。表头右键 = 同一套命中的 fixed 分支。
依赖:H1。**被 H15(按钮单元格)、M13(勾选/按钮交互事件)、M20(列菜单)、L(超链接)依赖。**
用户可见:"双击行打开明细""右键列头弹菜单"当天就能写出来,不用自己算 MouseToCell。

### P1 — 基本盘缺口

**H6. 单元格文字换行 + 文本测量服务**
合并自:单元格外观 high、内容类型 high、表头 medium(表头换行)。一次实现覆盖数据格与表头格。
依赖:H2、H3(`OnGetWordWrap`)。**被 H7 依赖(不做换行,自动行高价值减半)。**
用户可见:备注/地址列不再被裁成一行省略号。

**H7. 行高三件套:可写 `RowHeights[]` 稀疏存储 → 拖行分隔线 → 按内容自动行高**
合并自:行列结构 high×3(可写存储 / `AllRowSize` 拖拽 / `AutoSizeRow(s)`)。**必须按此顺序**:没有可写存储,拖拽和自动行高都无处落盘。
依赖:H6(自动行高要量折行后的高度);拖拽复用现有 `FResizeCol` 状态机的对称写法。**被 M8(全局行高上下限)、L(SizeWhileTyping)依赖。**
用户可见:能像列一样拖行高;长文本行自己撑开。

**H8. 选择模型重构:离散行多选 + 程序化选择 API + `OnSelectionChanged` + 鼠标拖选**
合并自:选择导航 high×4、事件面 high(选择变化事件)。
现在只有一个锚点矩形,**物理上无法表达"第 2 行和第 7 行被选中"**,得先加数据结构;`SelectAll/SelectRange/ClearSelection/Selection` 至今没有任何 public 方法;拖选被 C2 那句 early-Exit 挡死。
依赖:C2 核查。**被 M11(离散列选)、M12(选区聚合)、M14(选区外框+手柄)、L(Hotmail 勾选列)、L(右键是否移选区)依赖。**
用户可见:Ctrl 勾一批行去批量删/导出;拖鼠标能拉选区;选行即刷新下方明细面板。

**H9. 键盘录入手感:按键直接进编辑 + Enter 推进 + Tab 按格推进**
合并自:编辑器 high(DirectEdit)、选择导航 high×2(AdvanceOnEnter / TabAdvance)。
Grid.pas **没有 KeyPress/UTF8KeyPress override**,`KeyDown` 里**没有 VK_RETURN / VK_TAB 分支**(唯一的 VK_RETURN 在编辑器里只管提交)。
依赖:无硬依赖;与 H10 同批做最省事。**被 M15(跳过只读格)、L(AlwaysEdit)依赖。**
用户可见:在格上直接打字就开始编辑;回车往下走;Tab 在网格内走格而不是把焦点弹出去。

**H10. 列级编辑器声明:`TTyColumn.EditorKind / ReadOnly / PickList / EditMask`**
合并自:编辑器 high。
`TTyColumn`(Columns.pas:52)目前只有 Width/Alignment,没有任何编辑相关属性 → 每张表都得写 `OnGetEditorKind`,**设计期完全配不出来**。
依赖:无。**被 H11(EditLink 的列级承载)、M16(逐格 ReadOnly)依赖。**
用户可见:设计期在列编辑器里点几下就能配出"这列数字、那列下拉、这列只读"。

**H11. 编辑器扩展点 `TTyGridEditLink`(创建/定位/取值/写值/焦点/键路由,inplace 与 popup 两种承载)**
合并自:编辑器 high(架构级)、编辑器 high(带按钮编辑器 `edEditBtn` 作为首个内建实现)。
现在编辑器是**三个写死的私有字段**,第三方无法扩展。**越晚补越难改**,但工作量 large,故排在 H10 之后、与 H12 之前。首发内建两个:带省略号按钮的编辑器(通用逃生口)+ 现有三个编辑器改造成 EditLink 实现。
依赖:H10。**被 M17(`OnGetEditorProp`)、M18(spin)、M19(下拉宽度/自动扩宽)、L(下拉全家桶:备忘/计算器/滑块/颜色/子表格)依赖 —— 这条不做,下面 8 条全部只能硬编码。**
用户可见:操作列点省略号弹自己的选择器;第三方能挂任意控件当编辑器。

**H12. 按键级输入约束:`ValidChars` / `MaxEditLength` / `EditMask`**
合并自:编辑器 high。代码注释里我们自己写了"等 TTyValueEdit 泛化出来后再接"。
依赖:H11(挂在 EditLink 上最自然)。
用户可见:非法字符敲不进去,而不是敲完一堆再被静默驳回。

**H13. `hoAutoResize` / `AutoSizeIndex` 接线 + 批量自动列宽 + 双击分隔线自动列宽**
合并自:行列结构 high×2。`TTyColumns.ApplyAutoSize` 在 Grid.pas 中**零调用** —— 属性已 published 却不生效。
依赖:无(小,可穿插)。
用户可见:表格右侧那条永远填不满的空白带消失;双击列分隔线自动贴合内容。

**H14. 网格线局部控制:只横线 / 只竖线 / 全无,固定区与数据区分开**
合并自:视觉 high。现在只有一个 Boolean。
依赖:H1(线宽已进几何)。
用户可见:能做出 Ant Design / Material 那种"只留横线"的现代表格。

**H15. 按钮单元格(操作列)**
合并自:内容类型 high。
依赖:H5(命中)、H2(hover/pressed 三态)。
用户可见:每行末尾一列"编辑 / 删除"按钮,不用自绘 + 自己算命中区。

**H16. 多级(分层)表头 + 表头单元格合并**
合并自:表头 high×2。两条同源,**合并表头是多级表头的退化情形,同批实现**。
依赖:H1(表头带多行的几何已就位)。**被 M4(表头自绘钩子)、M5(表头高度自适应)、M20(列菜单)依赖 —— 先做它,否则表头相关项都要重做。**
用户可见:能做出"2026年 → 一季度/二季度"这种一级/二级表头。

**H17. 排序模型多列化 + 按列排序格式**
合并自:排序 high×3(多列排序 / `TSortStyle` 按列格式 / `SortKind` 从控件级降到列级)。
`FSortCol` 是单个整数、`FSortKind` 是控件级 → 混合列(文本+金额+日期)直接排错,日期列会把 01/12 排在 02/01 前。
依赖:无。**被 H18(分组内排序)、M21(排序徽标)、M22(空值位置/大小写)依赖。**
用户可见:Shift 追加第二排序列;日期列按日期排而不是按文本排。

**H18. 分组重做:分组内排序 + 多级分组 + 分组汇总行 + 一键展开/折叠**
合并自:排序分组 high×4 + medium(按行范围列计算 `ColumnSum(ACol,From,To)` —— 分组小计的前置)。
现在 `BuildGroups` 直接把 `FSortCol` 强设成 `FGroupCol`(一分组就丢掉用户选的排序列),`FGroupCol` 只有一个,分组行只显示计数。
依赖:H17。实现顺序:按行范围聚合 → 分组内排序 → 分组汇总行 → 多级分组 → ExpandAll/CollapseAll。**被 M23(分组头合并/汇总线)、M24(通用大纲节点)、内容类型的树节点依赖。**
用户可见:地区→城市两级分组,每组底部有小计,一键全展开。

**H19. 数据层批量与正确性:CSV 跨行引号解析修复 + `InsertRows/RemoveRows/InsertCols/RemoveCols` + `MoveRow/MoveColumn/SwapRows` + `CutToClipboard` + 剪贴板事件族**
合并自:数据交换 high×5、事件面 high(剪贴板事件族 / 行列结构变更事件)。
**CSV 那条是正确性缺陷不是功能缺失**:`LoadFromCSVText` 先按 `TStringList.Text` 切行再逐行 split,任何 Excel 导出的含换行单元格都会**静默错数据**,应最先修。剪贴板 14 个钩子我们目前 0 个。
依赖:无(CSV 修复零依赖,应插到最前当作 quick win)。**被 M6(行/列拖动重排要有 Move 原语)、M7(智能粘贴扩行)、M25(插删行否决事件)依赖。**
用户可见:Excel 存的 CSV 导进来不再串行;Ctrl+X 有反应;粘贴进来的数据能被宿主校验/清洗/记 undo。

---

## MEDIUM(24)

**M1. 逐格边框控制**(`OnGetCellBorder` + 四支笔的 `OnGetCellBorderProp`)— 依赖 H2/H3。→ 报表式表格能画分区块粗线、小计行双线。
**M2. 焦点格与选区外观区分**(ActiveCell 独立底色/字体 + `SelectionTextColor`)— 合并自单元格外观 medium + 视觉 medium×2;依赖 H2。→ gsmRow 模式下终于看得出光标在哪一格;深色选中底上的文字不再糊。
**M3. 逐格持久外观数组**(`Colors[i,j]` / `Fonts[i,j]` / `RowColor[i]`)— 依赖 H3(先钩子后数组,复用稀疏 FCells 套路)。→ 用户手工把某几格涂黄能落盘。
**M4. 表头自绘钩子**(逐表头格改色/字体/边框)— 依赖 H16。→ 必填列表头标红、当前排序列表头高亮。
**M5. 表头图标接线 + 表头高度自适应** — `TTyColumn.ImageIndex` / `TTyHeader.Images` 字段**已存在但 RenderHeaderSections 完全没读**(属性存在却无效,比缺失更误导);依赖 H16、H6。→ 列标题旁能放图标,长列名折行后表头自己变高。
**M6. 行拖动重排 + 列拖动重排事件** — 取决于 **C1 核查结论**:若列拖动已实现则本条只补 `OnColumnMove(ing)` 事件(small);行拖动无论如何要新做,且要想清与 `FOrder` 排序置换的交互。依赖 H19(Move 原语)。→ 拖行头调优先级;新列序能被宿主持久化。
**M7. 智能粘贴**(按剪贴板块大小自动扩行扩列)— 现在 `targetRow<0` 直接 Break,粘 100 行进 10 行的网格**静默丢 90 行**;依赖 H19。
**M8. 全局行高/列宽上下限** — 自动行高上线后的护栏,否则一条超长文本撑爆;依赖 H7。
**M9. 列宽/行高交互事件**(`OnColumnSizing/OnEndColumnSize/OnRowSizing/OnEndRowSize`)— 依赖 H7。→ 列宽偏好能保存恢复,不用轮询。
**M10. 行的显式隐藏 API**(HideRow/UnHideRow/IsHiddenRow/NumHiddenRows)— 显示序置换是天然承载点,加一个 hidden 位集;现在只能借过滤间接隐藏,**语义不对(ClearFilters 会抹掉)**。
**M11. 离散列多选** — 依赖 H8 的数据结构。
**M12. 选区聚合**(SelectionSum/Avg/Min/Max)— 依赖 H8。→ 状态栏"已选 12 项,合计 3400"。
**M13. 内置控件单元格的交互事件**(`OnCheckBoxClick/Change/CanToggle`、`OnButtonClick`、`OnRatingChange`、`OnComboDropDown/CloseUp`)— 依赖 H5、H15。→ 勾选框一勾就能触发宿主逻辑。
**M14. 选区外框 + 右下角拖拽手柄** — 依赖 H8;颜色走主题 token。→ Excel 式选区观感。
**M15. 导航跳过只读/禁用/固定格** — 依赖 H9、H10(列级 ReadOnly 才知道该跳谁)。
**M16. 逐格 ReadOnly[col,row] 可写存储** — 依赖 H10。→ "已审核行不可改"不用宿主自己维护集合。
**M17. `OnGetEditorProp`(开编辑前改编辑器属性)** — 依赖 H11,是 EditLink 的配套必需品。
**M18. 数值 spin 编辑器** — 依赖 H11。
**M19. 下拉宽度控制 + 编辑器随内容自动扩宽 + 下拉箭头常驻显示** — 合并自编辑器 medium×3;依赖 H11(扩宽还要处理冻结窗格裁剪)。→ 窄列编辑长文本看得见自己在打什么;一眼看出哪列可选。
**M20. 过滤能力升级:条件类型化(>/</开头是/包含…)+ 内嵌过滤编辑行 + 多列 AND/OR/XOR + 过滤下拉钩子 + 漏斗图标激活态 + `FilteredRows`** — 合并自排序过滤 high×2 + medium×4 + 事件面 medium。现在只有"包含"一种,**数值列筛 >1000 完全做不到**;`GlyphActive` 最要紧(用户得看出哪列在过滤中)。依赖 H16(过滤编辑行占一条表头带)。
**M21. 多列排序徽标(表头显示 1/2/3 + 各自方向)** — 依赖 H17,做完多列排序必须配套否则用户看不出按啥排。
**M22. 排序细则:空值位置(blFirst/blLast)+ `IgnoreCase` 开关 + `OnCanSort`/`OnClickSort`** — 现在写死 `CompareText`(恒不区分大小写);后两个钩子是接服务端排序的必需品。依赖 H17。
**M23. 分组呈现:计数格式可配 + 分组头横跨整行 + 汇总行分隔线** — `'%s  (%d)'` **硬编码在 RenderGroupRow 里**,连"不显示计数"都做不到,违反主题可定制硬规则。颜色一律走 token,不照抄 AdvGrid 的 4 个颜色属性。依赖 H18。
**M24. 通用大纲节点 / 树形单元格**(AddNode/ExpandNode/GetNodeLevel + 层级缩进连线)— 合并自内容类型 high(large) + 排序分组 medium + 事件面 low(节点事件)。**降到 medium 的理由**:H18 的多级分组已覆盖大部分层级展示诉求,纯 TreeGrid 是第二形态而非基本盘;但工作量 large,建议单独一期。依赖 H18。

*(medium 尾部一并纳入、不再单列的小项:批注单元格角标 + 悬停批注、超链接单元格、三态勾选框、整列一次性配置单元格类型、逐格持久化设置内容类型、JSON 导出、流式 Load/SaveToStream、限定区域导出、追加式 CSV 导入 + MaxRows/IgnoreRows、HTML 导出可配置化(至少特殊字符转义)、分区域清空 ClearRows/ClearCols、插删行否决事件、滚动条策略开关 ScrollBarAlways、背景位图与作用范围、选区显示细则开关、键盘扩展事件 OnReturn/OnCtrlReturn、提示扩展 OnScrollHint、`OnEditChange` 逐击键回调、`OnCanEditCell` 独立钩子、列脚 `CalcFooter(ACol)` 显式重算与自定义聚合值事件 `OnColumnCalc` —— 这些都是 small,建议作为"顺手批次"塞进各自 HIGH 条目的同一个 PR,不单独排期。)*

---

## LOW(17,建议全部延后到 HIGH+MEDIUM 收尾)

按"有替代路径"排序,越靠前越可能被提前捞起来:

1. **列的显式隐藏方法糖**(HideColumn/IsHiddenColumn)— 能力已具备(改 Options),纯便利。
2. **自动编号列 `AutoNumberCol`** — ShowIndicator 已覆盖"看得见行号"。
3. **批量设置列标题的 StringList 属性** — 设计期一次贴一列名会舒服些。
4. **单元格背景渐变逐格覆盖** — FillBackground 接 TTyBackground,主题里本来就能配渐变,只缺"逐格覆盖"这一层;且渐变格在扁平审美里基本不用。
5. **内建条件着色语法糖**(正负数自动着色 / 修改过的格标色)— 有了 H3 钩子后宿主几行搞定。
6. **`OnIsFixedCell`(把普通格伪装成表头格)** — 分组行/汇总行样式键已覆盖。
7. **表头下拉按钮槽泛化** — 筛选按钮已占这个交互位,真做列菜单时再泛化。
8. **`FixedRowAlways/FixedColAlways`** — 我们的固定行本来就恒定可见,是 AdvGrid 的兼容旧行为开关,不构成缺口。
9. **固定行/列独立尺寸命名对齐** — Header.Height + IndicatorWidth 已语义等价,只是不叫这个名字。
10. **离散单元格多选** — AdvGrid 有整套,但业务表格里行级多选就够了(large)。
11. **Hotmail 式勾选列行选** — 是 H8 + 勾选框列的组合表现层,依赖落地后作为一个开关做。
12. **编辑器长尾**:大小写转换 / 密码列 / 带单位编辑器 / 常驻编辑模式 AlwaysEdit / 编辑期方向键跨格 / 下拉全家桶(备忘/计算器/滑块/颜色/图片/子表格)— **一律等 H11 之后作为增量,绝不逐个硬编码**。
13. **进度条/评分的精细化**(任意值域 + 文本模板 + 分级配色、饼状进度、区间指示条、形状单元格)— OnDrawCell 已能自绘。
14. **任意图片对象/文件图片/拉伸模式** — gcdImage 已覆盖图标列这个 90% 场景。
15. **气球提示单元格 / 旋转文本 / ICellGraphic 接口 / 内嵌滚动条** — 前者 TTyPopover 将来接起来很便宜,后三者 OnDrawCell 等价。
16. **持久化类**:列宽存注册表(**应改做"导出/导入布局字符串"由宿主自己存,注册表方案跨平台不成立**)、排序状态 Save/LoadToString、过滤条件存盘、定宽文本导入导出、原生二进制格式、纯文本 ASCII 导出、导出格式化选项(FloatFormat/QuoteEmptyCells)。
17. **其余**:整表缩放 ZoomFactor(ScaleI 的 HiDPI 已覆盖主诉求)、滚轮行为可配、部分可见行滚动策略、隐藏行原始数据访问与"聚合含隐藏行"开关、排序后自动合并同值单元格、排序表头专用配色(**要做也必须走 `TyGridHeader:sorted` token**)、`ColumnDistinct/StdDev`、导入导出进度通知、SizeWhileTyping、VirtualEdit(等虚拟模式那一期)、表头就地改标题、通用 undo/redo(**对标对象自己也没有,真要做是独立命令栈专题**)、OLE 拖放(Windows COM 专属,应走 LCL DragDrop 模型)。

---

## SKIP(12 类,理由归档,别反复纠结)

| 类别 | 涉及条目 | 理由 |
|---|---|---|
| PDF / 打印子系统 | PrintSettings 全族、跨页重复固定行、打印逐格颜色/边框钩子、打印选区、分组汇总打印、打印事件族(13 个)、打印侧视觉参数 | 路线图已明确不做 |
| XLS 原生读写 | SaveToXLS/LoadFromXLS、过滤结果导出 XLS、`OnLoadCell/OnSaveCell` | 文件格式库范畴,用户走 CSV 中转 |
| Word / MDB | SaveToDOC、LoadFromMDB* | 靠 COM 自动化实现,跨平台不成立 |
| HTML 富文本单元格引擎 | THTMLSettings、EnableHTML/XHTML、HTML 提示窗、过滤下拉里的 HTML、fcStripHTML | 等同 RichEdit 一档;是个完整 HTML 子集解析+排版引擎,收益不抵成本 |
| RichEdit 单元格 | edRichEdit、OnRichEditSelectionChange、SelectionRTFKeep | 路线图已明确不做 |
| 预制外观样式集 | TAdvGridStyle(27 值)、SetStyle、Look、UIStyle、AutoThemeAdapt | AdvGrid 没有主题引擎才在控件里硬编码几千行 case 配色(31460-32525)。**我们的等价物就是 .tycss + typeKey**,照抄等于把主题职责搬回控件,违背"视觉值必须 token 驱动"的硬规则 |
| ControlLook 位图字形 | CheckedGlyph/RadioOnGlyph/ExpandGlyph 等 TBitmap 槽 | Win32 时代做法,HiDPI 会糊;对应能力应由 TTyIconFont + token 提供,不在 Grid 上开一套位图槽 |
| 固定单元格画成按钮 | FixedAsButtons、FixedGradientDown*/Hover* | 状态外观应由 tycss 表达,不加属性 |
| Ansi/Wide 双轨钩子 | OnSetEditWideText / OnGetEditWideText / OnCellValidateWide | Delphi 历史包袱;FPC/Lazarus 全程 UTF-8,不存在这个问题 |
| Fixed 文件格式存取 | SaveToFixed/LoadFromFixed(布局版) | AdvGrid 私有格式,与我们 CSV/HTML 的定位不同 |
| 搜索页脚子系统 | OnSearchFooter* 5 个事件 | 我们没有该组件;真要做应是独立控件,不塞进 Grid |
| 锚点/超链接事件族 | OnAnchorClick/Enter/Exit/Hint | 依赖 HTML 引擎(注:**纯文本正则识别的超链接单元格已作为 medium 尾部保留**,只是不做 HTML 版) |

---

## 关键依赖链(一图流)

```
H1 几何契约(四向冻结/线宽/表头带)
 ├─> H2 逐格渲染管线+hover ──> H3 逐格钩子 ──> H4 斑马纹 / M1 边框 / M2 焦点格 / M3 持久外观数组 / L 条件着色语法糖
 │                              └─> H6 换行 ──> H7 行高三件套 ──> M8 上下限 / M9 尺寸事件 / L SizeWhileTyping
 ├─> H5 单元格级鼠标事件 ──> H15 按钮单元格 / M13 控件格事件 / M20 列菜单 / L 超链接
 ├─> H14 网格线局部控制
 └─> H16 多级表头+合并 ──> M4 表头自绘 / M5 表头图标+高度自适应 / M20 内嵌过滤行

H8 选择模型重构 ──> M11 离散列选 / M12 选区聚合 / M14 选区外框手柄 / L Hotmail 勾选列
H9 键盘录入 ─┬─> M15 跳过只读格
H10 列级编辑器声明 ─┴─> H11 EditLink 扩展点 ──> H12 输入约束 / M17 EditorProp / M18 spin / M19 下拉宽度 / L 下拉全家桶
                     └─> M16 逐格 ReadOnly
H17 多列排序+按列格式 ──> H18 分组重做 ──> M21 排序徽标 / M23 分组呈现 / M24 树形节点
H19 数据层批量+CSV修复+剪贴板 ──> M6 行列拖动重排 / M7 智能粘贴 / M25 插删否决事件
H13 AutoResize 接线(无依赖,随时可插)
```

**建议的批次切分(1 批 = 1 次 merge)**:
B1 = C1/C2 核查 + H19 的 CSV 修复(纯 bugfix,最快见效) ·
B2 = H1 契约(P0,必须最先合) ·
B3 = H2+H3+H4+H14(渲染管线,收益最密) ·
B4 = H5+H15+H13 ·
B5 = H6+H7 ·
B6 = H8 ·
B7 = H9+H10+H11+H12 ·
B8 = H16 ·
B9 = H17+H18 ·
B10 = H19 余下(批量 API + 剪贴板事件) ·
之后 MEDIUM 按依赖顺序滚动。