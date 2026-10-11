# 多滑块 TrackBar 第二步 实现计划（#36）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or subagent-driven-development) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（项目约定）**：测试先行；每个任务改代码 + 写测试并单独提交；任务之间只编 `tests/tytests.lpi` 跑本任务的 suite，最后一个任务一次全量、集中变异、签收。中途不汇报、不问要不要提交。测试写「判据 + 必须变红的变异」。
>
> **谁来做**：标 **【主控执行】** 的步骤实现 agent 不做：编 `.lpk`、编 `examples/`、生成面板图标、Lazarus 3.0 构建、GUI 冒烟、推送。
>
> **不改的文件**：`Painter.pas`、`StyleModel.pas`、`TextMenu.pas`、`Base.pas`、`Component.pas`、`AdvanceChart.pas` 及 `AdvChart.*`、`CHANGELOG*`。

**Goal:** #36 第二步——渐变色标控件 `TTyGradientTrackBar`，以及第一步各控件上默认关闭的几个开关：`AllowCrossing`、`AllowUserThumbs` / `AllowUserRanges`、`Pushable`、`DraggableRanges`。

**Architecture:** 开关都放在 `TTyMultiTrackBarBase`（中间类，protected），各最终类按需发布。内置行为一律建在第一步的扩展点上：加滑块 / 区间走 `OnTrackClick` 之后（用户处理了就不再内置添加），移动走 `OnThumbChanging`，删除新增一个 `OnThumbRemoving`——用户的事件处理永远先于内置行为、也能拦住它。`TTyGradientTrackBar` 建在多值控件上：`TTyCustomGradientTrackBar = class(TTyCustomMultiTrackBar)`，色标就是 `Thumbs`（`Value`、`Color`），轨道默认按色标颜色画渐变。

**工作树：** `D:/Projects/ty-gradient`，分支 `feat/gradient-trackbar`，起点 main（含第一步合并）。

---

## 核实记录（执行前补）

| # | 待核的事实 | 影响 | 核实结果（2026-10-12，d280bfa9） |
|---|---|---|---|
| V1 | 第一步的 `UserMoveThumb`、`OnTrackClick` 的触发点与「处理后重新命中」逻辑、双击合并规则 | 新开关都插在这些点之后 | 成立。`UserMoveThumb` 在 MultiTrackBar.pas:913（先 `ClampThumbValue`、不动不问、`DoThumbChanging`、处理后索引失效即退、再夹一次后 `ApplyThumbValue`）；拖动 / 键 / 滚轮 / 跳到按点都经它（:1641、:1709、:1561、:1612）。`OnTrackClick` 在 `MouseDown` :1580–1597：只在空白处、首击（无 ssDouble/Triple/Quad）问；处理了置 `FTrackClickTaken` 退出；没处理则 `ThumbAtPoint` 重新命中（:1595）。双击规则 :1573–1575。内置添加插在 :1603 的「空白处」分支、最近滑块跳过来之前。 |
| V2 | `TTyMultiTrackBar` 在 `EndUpdate` 时排序、颜色与选中跟着项走（6537619c）；区间控件同样（1c9de42d） | `AllowCrossing` 的「越过后重排」直接复用 | 成立，但**不能直接复用**：`ThumbsChanged`（:2307）排序后整组 `SetThumbValues` 重建，选中按项 ID（`FSelectedID`）找回、发一次 `OnThumbSelect`；它不知道哪个是被拖的滑块，也会把 `FDragThumb` 留在旧索引。越过改为基类就地交换 `FValues` 并经新的 protected virtual `ThumbIndexMoved(AFrom, ATo)` 让最终类挪项（多值：`FSyncing` 下 `Item.Index := ATo`；区间：值按位置写回，不用挪），`FDragThumb` / `FHoverThumb` / `FSelectedThumb` 一并重映射。选中跟项的机制（ID / `RememberSelection`）照旧在 `DoThumbSelect` 里生效。 |
| V3 | `TyGradientNeedsStops`（#49，tyControls.Types）与 `TTyFill` 的多色标渐变（`GradStops`） | 渐变控件的轨道与 `Gradient` 输出用它 | 存在：`TyGradientNeedsStops` Types.pas:177/256；`TTyFill.GradStops: array of TTyGradStop`（Color: TTyColor; Pos: Single）Types.pas:59。（Task 4 用，本次未动。） |
| V4 | `TTyColorDialog`（tyControls.Dialogs.Color）的用法；双击经 protected virtual 调用，测试可替换 | D3 | 存在：Dialogs.Color.pas:156，`Execute: Boolean`（:173，非 virtual），`Color` 是 **TTyColor**（ARGB，默认 $FF000000，:180），`LCLColor: TColor` 可读写（:174）。（Task 4 用，本次未动。） |

**核实中发现与设计不符之处（已在下文原处标注）**：
- D7 的 `:removing` 状态做不出来而不改 StyleModel：状态的层叠顺序是 StyleModel.pas:1852 / :1910 的固定 5 元数组（`cStateOrder` / `cTierStates`），新加的 `TTyState` 成员永远不会被应用；伪类名在 Css.Parser.pas:176 `PseudoToState` 里写死。改用**变体类** `TyTrackThumb.removing`：`ResolveLayer` 把 StyleClass 按空格拆成多个变体（StyleModel.pas:1861–1863），所以解析时传 `'<滑块自己的类> removing'`，滑块原有的类照样生效。
- `opacity` 画不到单个滑块上：`TTyPainter.Opacity` 是整次绘制在 `EndPaint` 统一乘的（Base.pas:1393），`TyDrawTrackThumb` / `TyFillSubElement` 不读 `tpOpacity`。改为 MultiTrackBar 自己把「将被删除」滑块解析出的颜色（背景、边框、轮廓，含 `Color` 覆盖的底色）的 alpha 乘上 `Opacity`。

## 设计

**D1 `AllowCrossing`**（默认 False；渐变控件默认 True）：拖动时不受邻居阻挡，越过即按值重新排序，被拖的滑块（以及它的颜色、提示、选中）跟着项走；`MinGap` 在开着时不生效（色标可以重合）。键盘方向键同样可越过。与 `Pushable` 同开时 `AllowCrossing` 优先。
  > 【执行时补，Task 1】只管用户的移动（拖动、键、滚轮、跳到按点）：代码写值（`SetThumbValue`、`Thumbs[i].Value`）开着时仍夹在两邻居之间（间距 0），不改项的顺序——程序要整体重排用 `BeginUpdate` / `EndUpdate`。越过后的事件顺序：`OnThumbSelect`（新索引）→ `OnThumbChange`（新索引）→ `OnChange`。关掉 `AllowCrossing` 时按 `MinGap` 重新排开（同改 `MinGap`，会发事件）。

**D2 `Pushable`**（默认 False）：拖到邻居 `MinGap` 处时推着邻居一起走，连锁推动，直到被推的一串碰到 `Min` / `Max` 为止；每个被推动的滑块都经 `OnThumbChanging`（被拒则推动在那里停住）、触发各自的 `OnThumbChange`，最后一次 `OnChange`。
  > 【执行时补，Task 1】禁用的滑块（`Enabled = False`）推不动，当作墙：同被 `OnThumbChanging` 拒绝。被拒时整串退到离墙 `MinGap` 处（已问过的滑块不再重问，退回的值总在它们被允许的方向上）。被推者的处理器答案再夹在「前一个 + MinGap」与链条余地之间。`OnThumbChange` 按推动顺序（被拖的先，再依次被推的），最后一次 `OnChange`。只管用户的移动，代码写值不推。

**D3 `AllowUserThumbs`**（多值、渐变控件；默认 False，渐变控件默认 True）：
- 加：在空白轨道左键按下，`OnTrackClick` 之后（没被处理时），在该值加一个滑块并选中；多值控件的新滑块 `Color = clDefault`，渐变控件取两侧色标在该位置的插值色。超过 `MaxThumbs`（默认 0 = 不限）不加。
  > 【执行时补，Task 2】只在首击（不是双击的后续按下）。按点离邻居不足 `MinGap` 时夹进两邻居之间的空档，空档放不下不加（同 D4）。新滑块成为这次按下拖动的滑块（按在哪就抓在哪）。到了 `MaxThumbs` 或放不下时这次按下什么也不做——不退回「最近滑块跳过来」。
- 删：把滑块垂直于轨道拖出超过一段距离（主题度量 `--track-remove-distance`，默认 24 逻辑像素）时，滑块按「将被删除」画（`TyTrackThumb:removing` 状态，主题给淡出样式），此时松开即删；拖回轨道内恢复。删除前触发新事件 `OnThumbRemoving(Sender; AIndex: Integer; var AAllow: Boolean)`；少于 `MinThumbs`（默认 0；渐变控件默认 2）不删。
  > 【执行时改，Task 2】`:removing` 状态改为变体类 `TyTrackThumb.removing`（理由见核实记录）；淡出用 `opacity`，由控件乘到滑块颜色的 alpha 上。距离从控件边缘沿交叉轴量起（水平条看 Y、竖直条看 X），超过（>）才算拖出；拖出期间滑块的值不跟指针走。滑块数已到 `MinThumbs` 时不显示「将被删除」，松开也不问 `OnThumbRemoving`。删除后选中跟着消失（-1）。
- 键盘：选中滑块时 Delete 键删除（同样经 `OnThumbRemoving` 与 `MinThumbs`）。

**D4 `AllowUserRanges`**（区间控件；默认 False）：空白处左键按下（未被 `OnTrackClick` 处理）时，以按点为中心加一个区间，宽度为 `NewRangeWidth`（默认 10，单位同值），放不下（与相邻区间冲突）时在可用空档内收缩，空档小于 `MinGap` 时不加。删除：把区间的任一端拖出轨道，整个区间按「将被删除」显示，松开删除（`OnThumbRemoving` 收到该端点的序号；拒绝则不删）；Delete 键删除选中端点所在的区间。

**D5 `DraggableRanges`**（区间控件；默认 False）：按在区间的高亮段上（不在端点上）拖动，整段平移，宽度不变，碰到相邻区间（`MinGap`）或 `Min` / `Max` 停住；两个端点都经 `OnThumbChanging`（任一被拒则这一步整段不动）。

**D6 `TTyGradientTrackBar`**：
- 发布：`Thumbs`（色标）、`Min` / `Max`（默认 0 / 100）及第一步的共用属性，外加 `AllowCrossing`（默认 True）、`AllowUserThumbs`（默认 True）、`MinThumbs`（默认 2）、`MaxThumbs`、`OnThumbRemoving`、`OnEditStopColor`。
- 默认两个色标：`Min` 处黑、`Max` 处白（`clBlack` / `clWhite` 是数据，不是界面样式）。
- 轨道：凹槽画成色标渐变（首个色标之前延续首色、末个之后延续末色），用 `TTyFill` 的多色标渐变；`OnDrawTrack` / `OnDrawSegment` 照常可以接管。
- 双击色标：触发 `OnEditStopColor(Sender; AIndex: Integer; var AColor: TColor; var AHandled: Boolean)`，没处理时弹 `TTyColorDialog`（经 protected virtual `ExecuteColorDialog(var AColor): Boolean`，测试替换），确定后改该色标的 `Color`。
- 输出：`function Gradient: TTyGradStops`（按值排序的颜色与 0..1 位置）、`function GradientFill(AAngleDeg: Single = 0): TTyFill`（直接交给 `FillBackground` 画同一条渐变）。

**D7 主题**：`TyGradientTrackBar` → `TyTrackBar`；新增状态 `:removing`（`TyTrackThumb:removing { opacity: … }`，各内置主题能 resolve 到可见的区别，跨 17 主题 × 亮 / 暗测）、度量 `--track-remove-distance`（light.tycss 定义，其余主题回退）。
  > 【执行时改，Task 2】`:removing` → `TyTrackThumb.removing`（变体类，见核实记录）。Task 2 已在 light.tycss 加 `--track-remove-distance: 24px` 与 `TyTrackThumb.removing { opacity: var(--disabled-opacity); }`；其余内置皮肤的跨 17 主题测仍归 Task 5（自带 `TyTrackThumb` 规则的皮肤拿不到基础层的 `.removing`，要各自补）。

**D8 需主控确认**（不回复按建议）：① `AllowCrossing` 时 `MinGap` 不生效；② 拖出轨道删除的距离用主题度量；③ 渐变控件默认黑→白两个色标、默认可加减可越过；④ 新增状态名 `:removing`。

## 任务

### Task 1：`AllowCrossing` 与 `Pushable`
- 测试：越过后顺序、被拖项（颜色 / 提示 / 选中）跟着走；`MinGap` 不生效；`Pushable` 连锁推动到边界停住、每个被推者经 `OnThumbChanging`（拒绝时整串停在那里）；两个同开时越过优先；默认关时行为与第一步逐项相同（第一步全部测试保持绿）。
- 变异：越过后选中不跟项 → 红；推动不经 `OnThumbChanging` → 红；推过 `Max` → 红。

### Task 2：`AllowUserThumbs`、`OnThumbRemoving`、`MinThumbs` / `MaxThumbs`
- 测试（真实路径）：空白处加（被 `OnTrackClick` 处理时不加）；拖出超过距离出现 `:removing`、松开删除、拖回恢复；`OnThumbRemoving` 拒绝 / `MinThumbs` 时不删；Delete 键删除；`MaxThumbs` 时不加。
- 变异：`OnTrackClick` 处理后仍内置添加 → 红；忽略 `MinThumbs` → 红；距离判据用错轴 → 红。

### Task 3：`AllowUserRanges`、`DraggableRanges`
- 测试：按点加区间、空档不足时收缩 / 不加；拖出一端整区删除；拖高亮段整体平移、碰邻停住、任一端被 `OnThumbChanging` 拒绝则不动。
- 变异：平移时宽度变化 → 红；平移越过邻居 → 红。

### Task 4：`TTyGradientTrackBar`
- 测试：默认两色标；轨道像素与 `GradientFill` 画出的同一条渐变逐像素相同（同一个 `TTyFill`）；首色之前 / 末色之后延续；新加色标颜色是两侧插值；双击经 `ExecuteColorDialog` 改色、`OnEditStopColor` 处理时不弹；`Gradient` 输出按值排序、位置 0..1；`.lfm` 往返；拆分登记（中间链：`TTyCustomGradientTrackBar = class(TTyCustomMultiTrackBar)`）。
- 变异：插值取了单侧颜色 → 红；`Gradient` 位置未归一化 → 红。

### Task 5：主题、注册、示例、文档
- `:removing` 状态与度量（17 主题测）；面板注册（`'TyControls Bars'`，`TTyMultiTrackBar` 之后）、图标【主控执行】、守卫（version、focus.tabstop、customclasses、G10、tbcoverage）。
- 示例：右栏的手写渐变演示换成 `TTyGradientTrackBar`（双击改色、拖出删除），预览条用 `GradientFill`；区间演示打开 `DraggableRanges` 与 `AllowUserRanges`（去掉手写的 `OnTrackClick` 加区间代码，改在提示文字里说明）；多值阈值演示打开 `Pushable`。`.lfm` 与 `.po` 照规矩。
- 文档：`docs/controls/multitrackbar.md` 加各开关与渐变控件，说明内置行为都在用户事件之后；README 控件表与总数。

### Task 6：编译、全量、变异、Lazarus 3.0、冒烟、签收【主控执行为主】

## 签收（执行时填）
