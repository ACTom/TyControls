# 多滑块 TrackBar 第一步 实现计划（#36）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or subagent-driven-development) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（项目约定）**：测试先行；每个任务改代码 + 写测试并单独提交；任务之间只编 `tests/tytests.lpi` 跑本任务的 suite，最后一个任务一次全量、集中变异、签收。中途不汇报、不问要不要提交。测试写「判据 + 必须变红的变异」，测试代码由实现者按判据写。
>
> **谁来做**：标 **【主控执行】** 的步骤实现 agent 不做：编 `.lpk`、编 `examples/`、生成面板图标、Lazarus 3.0 构建、GUI 冒烟、推送。实现 agent 只编 `tests/tytests.lpi`。
>
> **不改的文件**：`Painter.pas`、`StyleModel.pas`、`TextMenu.pas`、`Base.pas`、`Component.pas`、`AdvanceChart.pas` 及 `AdvChart.*`、`CHANGELOG*`。

**Goal:** GitHub #36 第一步——`TTyCustomMultiTrackBar` 加两个最终类 `TTyRangeTrackBar`（一个或多个区间）与 `TTyMultiTrackBar`（多个值，每个滑块可单独设颜色 / 提示 / 样式），共用 TrackBar 的属性名；三个控件（含 `TTyTrackBar`）加刻度标签。

**Architecture:** 新单元 `tyControls.MultiTrackBar`。`TTyCustomMultiTrackBar = class(TTyCustomControl)`，与 `TTyCustomTrackBar` 并列而不是派生（后者的核心是单个 `Position`）。（执行时改名，Task 5：共用基类叫 `TTyMultiTrackBarBase`，是中间类，同 `TTyGlyphButtonBase`；按拆分规则每个最终类要有自己的 Custom 类，`TTyCustomMultiTrackBar` 让给 `TTyMultiTrackBar` 的 Custom 类，`TTyRangeTrackBar` 的是 `TTyCustomRangeTrackBar`。下文的 `TTyCustomMultiTrackBar` 指共用基类时都读作 `TTyMultiTrackBarBase`。）模型是一个有序整数数组 `FValues`（滑块位置，升序、相邻至少 `MinGap`），两个最终类各自把 `Ranges` / `Thumbs` 集合映射到这个数组。几何复用 `tyControls.TrackBar` 的单元级函数 `TyTrackThumbOffset` / `TyTrackPosFromOffset`；刻度与刻度标签抽成 `tyControls.TrackBar` 里的单元级过程，TrackBar 与多滑块共用一份。

**Tech Stack:** FPC 3.2.2 / Lazarus 4.4 LCL（最低 Lazarus 3.0）、BGRABitmap、fpcunit。

**工作树：** `D:/Projects/ty-multitrack`，分支 `feat/multi-trackbar`，起点 `feat/trackbar-selrange` @ `c82ab367`（#37，`TyTrackSelection` 主题键已在）。

---

## 范围（用户 2026-10-06 定，issue #36 第一步）

做：Custom 基类、`TTyRangeTrackBar`、`TTyMultiTrackBar`、每个滑块的颜色 / 提示 / 可用 / 样式类、选中滑块、三个控件的刻度标签、`MinGap`、`OnThumbChange`、`OnDrawTrack` / `OnDrawThumb`、键盘与鼠标。
不做（第二步）：`TTyGradientTrackBar`、`AllowCrossing`、`AllowUserThumbs` / `AllowUserRanges`、`Pushable`、拖动整段平移。以后再说：DB 版、小数值。

## 核实记录

| # | 事实 | 出处 | 影响 |
|---|---|---|---|
| V1 | `TTyCustomTrackBar.Inverted = (Orientation = toVertical) xor Reversed`，不看 BiDi；TrackBar 目前不做 RTL 镜像，`docs/rtl.md` 也没列它 | TrackBar.pas:391-397 | D8：多滑块先与 TrackBar 一致，不镜像（需主控确认） |
| V2 | `TyTrackThumbOffset(MainLen, ThumbLen, Min, Max, Pos, Invert)` 自己把 `Pos` 钳到 `Min..Max`；`TyTrackPosFromOffset` 是它的反函数 | TrackBar.pas:247 起 | 多滑块直接用，不另写换算 |
| V3 | TrackBar 的子部件主题键：`TyTrackGroove`（凹槽）、`TyTrackThumb`（滑块，`:hover` / `:active`）、`TyTrackSelection`（#37，选区）；刻度颜色取 `TyTrackBar` 的 `color` | light.tycss:650-675 | 多滑块全部沿用，区间高亮就是 `TyTrackSelection`；新加 `TyTrackSegment`（多值控件的分段，默认不画） |
| V4 | TrackBar 的刻度带：`TickLen = 4`、带宽 `TickLen + 2`（逻辑像素），按 `TickMarks` 放在一侧或两侧，`ttsAuto` 每 `Frequency` 一条、`ttsManual` 只画 `SetTick` 的值 | TrackBar.pas RenderTo | 抽成共用过程，刻度标签放在刻度带外侧 |
| V5 | 本库测试里控件拿不到真实焦点（测试窗体不显示）；Tab 的分发走窗体的 `SelectNext`，控件要截 Tab 需响应 `CM_WANTSPECIALKEY` | LCL wincontrol.inc | 「Tab 在滑块之间切换」用 `CM_WANTSPECIALKEY`：还有下一个滑块时要 Tab，否则放行；测试直接送消息 |

## 设计

**D1 模型（Custom 类）**：`FValues: array of Integer`，不变式「升序、`FValues[i+1] - FValues[i] >= MinGap`、全部在 `Min..Max`」。唯一写入口 `SetThumbValue(AIndex, AValue)`：钳到 `[左邻 + MinGap, 右邻 − MinGap]` 与 `Min..Max`，变了才触发 `OnThumbChange(Self, AIndex)` 和 `OnChange`。`Min` / `Max` / `MinGap` 改变或读窗体结束（`Loaded`）时 `Normalize`：排序、从左到右推开到满足间距，放不下（`(n−1)·MinGap > Max − Min`）时把 `MinGap` 当作 `(Max − Min) div (n−1)` 用（不改属性值，只影响摆放），文档写明。公开：`ThumbCount`、`ThumbValues[i]`（只读，读写走最终类的集合或 `SetThumbValue`）、`SelectedThumb`（−1 = 无）、`MinGap`（默认 0）。

**D2 `TTyRangeTrackBar`**：发布 `Ranges: TTyTrackRanges`（`TCollection`，项 `TTyTrackRange` 有 `Low`、`High`），默认一项 25..75（新放的控件看得见）；`LowValue` / `HighValue` 读写 `Ranges[0]`（没有项时读 0、写时先建一项）。滑块 = 每个区间两个，位置 `[Low0, High0, Low1, High1, …]`，区间之间与区间内都受 `MinGap`；`Low > High` 或区间重叠的输入在 `Normalize` 时排好。高亮：`High` 与下一个 `Low` 之间不画，`Low..High` 之间用 `TyTrackSelection` 填（同 #37 的画法：从滑块中心到滑块中心）。集合项改值走 `SetThumbValue`，所以拖动与代码设值同一条路。

**D3 `TTyMultiTrackBar`**：发布 `Thumbs: TTyTrackThumbs`（`TCollection`，项 `TTyTrackThumbItem`：`Value`、`Color`（`clDefault` = 跟主题）、`Hint`、`Enabled`（默认 True；False = 照画、不能拖、不能选）、`StyleClass`），默认三项 25 / 50 / 75；`Segments: TTyTrackSegments`（项 `TTyTrackSegmentItem`：`StyleClass`），第 i 段是滑块 i−1 与 i 之间（第 0 段在第一个滑块之前），有对应项且该项的 `StyleClass` 非空时用 `TyTrackSegment.<类>` 解析出的 `background` 填凹槽那一段，否则不画（露出凹槽）。滑块的 `Color` 是数据不是界面样式（像颜色选择器选出的值），不违反主题令牌原则；非默认时替换解析出的 `background` 颜色，状态（hover / active）仍由主题决定其余属性。

**D4 共用属性**（名字、默认值同 `TTyTrackBar`）：`Min`、`Max`、`Orientation`、`Reversed`、`TickMarks`、`TickStyle`、`Frequency`、`SetTick` / `ClearTicks` / `TickCount`、`LineSize`、`PageSize`、`ShowValue`（读数显示**选中滑块**的值，没有选中时显示第一个滑块的值；读数带的宽度按 `Min` / `Max` 较宽者量，同 TrackBar）、`TabStop default True`、`OnChange`。新增：`MinGap`、`TickLabels`、`OnFormatTickLabel`、`SelectedThumb`、`OnThumbSelect`、`OnThumbChange`、`OnDrawTrack`、`OnDrawThumb`。

**D5 刻度标签（三个控件）**：`TickLabels: Boolean default False`；为 True 时在每条刻度外侧写它的值，文字经 `OnFormatTickLabel(Sender; AValue: Integer; var AText: string)` 可改（「1 月」「¥100」）；字体与颜色取控件 `TyTrackBar` 的样式（和刻度同一条 `color`）。标签带的厚度 = 量出的文字高度（横排）/ 最宽标签宽度（竖排）+ 2 逻辑像素，在刻度带外侧再让出一条，`CalculatePreferredSize` 的跨轴尺寸把它算进去。相邻标签放不下时跳过会重叠的那些（保留首尾）。`TickLabels = False` 时 TrackBar 的布局与绘制**逐像素不变**（测试钉住）。抽成 `tyControls.TrackBar` 的单元级过程 `TyDrawTrackTicks(...)`，TrackBar 与多滑块各自调用。

**D6 交互**：
- 鼠标：左键按在某个可用滑块上 → 选中它并开始拖；按在凹槽空白处 → 离按点最近的可用滑块跳过去并选中（距离相等取值较小的那个）；拖动经 `SetThumbValue`，碰到邻居停在 `MinGap` 处。不可用的滑块不响应。
- 键盘（选中的滑块；没有选中时第一个可用滑块）：←/↓ 减 `LineSize`、→/↑ 加（竖排「上增大」，同 TrackBar）、PageUp / PageDown 按 `PageSize`、Home / End 到它能去的最小 / 最大（邻居 ± `MinGap`）。Tab / Shift+Tab 在可用滑块之间切换，到头才离开控件（D5 的 `CM_WANTSPECIALKEY`）。
- 选中变化触发 `OnThumbSelect(Sender; AIndex)`；滑块的 `Hint` 在指针悬停时作为控件提示（`CM_HINTSHOW` 里按指针下的滑块取，没有则用控件自己的 `Hint`）。

**D7 自绘钩子**：`OnDrawTrack(Sender; APainter: TTyPainter; const ARect: TRect; var ADefaultDraw: Boolean)` 在画凹槽之前、`OnDrawThumb(Sender; APainter: TTyPainter; AIndex: Integer; const ARect: TRect; AStates: TTyStateSet; var ADefaultDraw: Boolean)` 在画每个滑块之前；`ADefaultDraw := False` 则跳过默认画法。

**D8 RTL（需主控确认）**：`TTyTrackBar` 目前不镜像（V1）。建议多滑块先与它一致、不镜像；整个 TrackBar 家族的 RTL 另开一项（三个一起改，镜像时刻度标签、键盘方向一并处理）。issue #36 里「right-to-left mirroring」一句改为指向那一项。

**D9 主题与类型键**：`GetStyleTypeKey`：`TyRangeTrackBar`、`TyMultiTrackBar`，初始化时 `TyTryRegisterTypeKeyParent` 挂到 `TyTrackBar`（现有主题直接能用）。新子键 `TyTrackSegment`，`themes/light.tycss` 给一个不画的基础规则加三个变体示例（`.success` / `.warning` / `.danger` 用 `--success` / `--warning` / `--danger` 一类现有令牌——实现者查 light.tycss 里实际有哪些语义色令牌，没有就用现有的 accent / 状态色）；重跑 `gen-defaulttheme.ps1`、`gen-builtinthemes.ps1`、`gen-tycss-catalog.ps1` 并核对 diff。

**D10 拆分与注册**：两个类进 `CSplit`、`gen-mimic.py`、G10 夹具；`Design.pas` 的 `'TyControls Bars'` 页在 `TTyTrackBar` 后面加两个；`genicons.lpr` 与 `gen-icons.ps1` 各加两项【主控执行】；`test.version` `Reg()`；`test.focus.tabstop` 归「可聚焦」。

**D11 需主控确认汇总**：① D8 不做 RTL 镜像（与 TrackBar 一致）；② D1 里 `MinGap` 放不下时临时缩小而不是报错；③ `TTyRangeTrackBar` 默认一个 25..75 的区间、`TTyMultiTrackBar` 默认 25 / 50 / 75 三个滑块。没回复就按建议做。

## 文件

- 新建 `source/tyControls.MultiTrackBar.pas`（加进 `tycontrols.lpk`）。
- 改 `source/tyControls.TrackBar.pas`（`TyDrawTrackTicks`、`TickLabels`、`OnFormatTickLabel`）。
- 改 `themes/light.tycss`；生成 `source/tyControls.DefaultTheme.pas`、`source/tyControls.Css.Catalog.pas`（如有 `BuiltinThemeData` 变化一并）。
- 测试：新建 `tests/test.multitrackbar.pas`（模型、几何、交互、两个最终类）、`tests/test.trackbar.ticklabels.pas`；改 `tests/tytests.lpr`、`tests/test.customclasses.pas`、生成 `tests/test.customclasses.mimic.pas`、`tests/fixtures/customclasses/fresh-streams.txt`、`tests/test.version.pas`、`tests/test.focus.tabstop.pas`。
- 设计期：`designtime/tyControls.Design.pas`、`tools/genicons/genicons.lpr`、`scripts/gen-icons.ps1`、生成图标与 `.lrs`【主控执行】。
- 示例：改 `examples/trackbar/umain.lfm`（加一个 `TTyRangeTrackBar`、一个带分段样式的 `TTyMultiTrackBar`、一个开了刻度标签的 `TTyTrackBar`；只改 `.lfm`，事件处理放 `.pas`）。
- 文档：新建 `docs/controls/multitrackbar.md`；改 `docs/controls/trackbar.md`（刻度标签）、`docs/controls/README.md`、`docs/tycss-reference*.md`（`TyTrackSegment`）、`README.md` / `.en.md`（控件表与总数）。

---

### Task 1: 刻度过程抽出 + TrackBar 的刻度标签

- [ ] 测试（`test.trackbar.ticklabels`）：`TickLabels` 默认 False；**关时**对一组配置（横 / 竖、三种 `TickMarks`、三种 `TickStyle`、开关 `ShowValue`、`Reversed`）渲染结果与改动前逐像素相同——做法：先在改动前的提交上把这些配置的渲染结果存成夹具（`tests/fixtures/trackbar/*.png` 或像素哈希），再在改动后比较；开时每条刻度旁有文字墨迹、文字落在刻度带外侧；`OnFormatTickLabel` 改文字后墨迹变化（「1 月」比「1」宽）；放不下时首尾标签都在、中间有跳过且无重叠；`CalculatePreferredSize` 的跨轴尺寸开时比关时大，大的量等于标签带厚度。
- [ ] 实现 D5。
- [ ] 提交 `feat(trackbar): tick labels`，`Refs #36`。
- 变异：抽出后的过程漏掉 `ttsManual` 分支 → 夹具比较红；标签画在刻度内侧 → 红；不跳过重叠 → 红；`CalculatePreferredSize` 不算标签带 → 红。

### Task 2: 模型（Custom 类，无绘制）

- [ ] 测试：`SetThumbValue` 钳到邻居 ± `MinGap` 与 `Min..Max`；只在值变时触发 `OnThumbChange`（带序号）与 `OnChange`；`Normalize` 排序乱序输入、推开太近的值；`MinGap` 放不下时按 D1 摆放且不改属性值；改 `Min` / `Max` 后重新满足不变式；读窗体（模拟 `csLoading` 下乱序赋值再 `Loaded`）后满足不变式且读窗体期间不触发事件。
- [ ] 实现 D1。提交 `feat(multitrackbar): the ordered thumb model`。
- 变异：钳制只看左邻 → 红；`Loaded` 不 `Normalize` → 红；值没变也触发事件 → 红。

### Task 3: 几何与绘制

- [ ] 测试（哨兵底色）：每个滑块的矩形中心等于 `TyTrackThumbOffset` 对该值的位置（与同尺寸 `TTyTrackBar` 在 `Position = 该值` 时的 `ThumbRect` 比较，而不是自己再算一遍）；`Reversed` / 竖排跟着走；区间高亮恰好在每个 `Low..High` 的滑块中心之间、区间之间无高亮；分段按 `StyleClass` 着色、无类的段不画；`Color` 非默认的滑块墨迹是该颜色；不可用滑块照画；刻度与标签同 TrackBar（共用过程）。
- [ ] 实现。提交 `feat(multitrackbar): geometry and painting`。

### Task 4: 交互

- [ ] 测试（真实路径：`MouseDown` + `MouseMove` + `MouseUp`、`KeyDown`、`CM_WANTSPECIALKEY` 消息、`CM_HINTSHOW`）：按在滑块上拖动只动它、碰邻居停在 `MinGap`；按在空白处最近的可用滑块跳过去（等距取值小的）；不可用滑块不响应、点它时也不会选中别的；键盘各键按 D6；Tab 在滑块间切换、最后一个之后 `CM_WANTSPECIALKEY` 返回 0（放行），Shift+Tab 反向同理；悬停在带 `Hint` 的滑块上提示是它的 `Hint`。
- [ ] 实现 D6。提交 `feat(multitrackbar): mouse and keyboard`。
- 变异：等距不取小值 → 红；Tab 到最后一个仍截住 → 红；不可用滑块能拖 → 红。

### Task 5: `TTyRangeTrackBar`

- [ ] 测试：默认一个 25..75；`LowValue` / `HighValue` 读写第一个区间，空集合时写入会建项；多区间（1..3、4..6、8..12）的滑块顺序与高亮；集合里乱序 / 重叠的区间读入后被排好；拖动区间端点经集合项读得到新值；`.lfm` 往返（`Ranges` 集合写出读回相同）。
- [ ] 实现 D2，拆分登记（`CSplit`、mimic、`test.version`）。提交 `feat(multitrackbar): TTyRangeTrackBar`。

### Task 6: `TTyMultiTrackBar`

- [ ] 测试：默认三项；每项 `Value` / `Color` / `Hint` / `Enabled` / `StyleClass` 生效（各配一条渲染或交互断言）；`Segments` 项数少于段数时多出的段不画；`.lfm` 往返。
- [ ] 实现 D3，拆分登记。提交 `feat(multitrackbar): TTyMultiTrackBar`。

### Task 7: 自绘钩子与读数

- [ ] 测试：`OnDrawTrack` / `OnDrawThumb` 被调用、参数正确（序号、矩形、状态）、`ADefaultDraw := False` 时默认墨迹消失；`ShowValue` 显示选中滑块的值，选中变化后读数跟着变。
- [ ] 实现 D4 / D7。提交 `feat(multitrackbar): owner-draw hooks and the readout`。

### Task 8: 主题、注册、示例、文档

- [ ] 主题（D9）、类型键测试（两个键的链、17 个内置主题下与 `TyTrackBar` 一致）。
- [ ] 注册（D10，图标【主控执行】）、G10 夹具、`test.focus.tabstop`。
- [ ] 示例 `.lfm`、文档、README。提交（主题 / 注册 / 示例 / 文档各一个）。

### Task 9: 编译、全量、变异、Lazarus 3.0、冒烟、签收【主控执行为主】

- [ ] 实现 agent：全量；集中变异（各任务列出的 + 每个判据至少一个），每次还原后核对哈希。
- [ ] 主控：私有 `--pcp` 编三个包与全部示例（4.4、3.0）、3.0 全量、逐个启动示例、看 trackbar 示例截图。
- [ ] 签收写进本文件。

## 签收（执行时填）
