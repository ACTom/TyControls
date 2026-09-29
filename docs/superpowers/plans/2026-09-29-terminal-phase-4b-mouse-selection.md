# 终端控件 4 期 · 4b 鼠标与选区（Task 5–9）

> 本文件是 [`2026-09-29-terminal-phase-4.md`](2026-09-29-terminal-phase-4.md) 的附录，执行方式、核实记录、开工前问题、接口清单、地雷都在主文件。先读主文件，尤其是核实记录 6–18、开工前问题一第 1、3、5 条与二第 1、2、6–14、21 条，地雷 8–10、14、15。

**这一批做完能看到什么**：程序接管鼠标时，按键、拖动、移动、横竖滚轮按协议上报，拖出控件照报；按住覆盖键（默认 Shift，macOS Option）就是本地选择；单击拖、双击词、三击行、Alt 列选、Shift 扩展、拖出上下边自动滚；选区随输出上移、该清时清；选区画出来（聚焦 / 失焦两色，主题写了选区前景才换字色）；复制、全选（macOS Cmd+A）、`CopyOnSelect`、Linux PRIMARY 与中键粘贴；右键菜单四项，程序接管时右键上报、覆盖键 + 右键弹菜单。段末编译一次，只跑 4a–4b 的 suite。

---

## 「谁拿鼠标」逐格（spec §9.5.2 的表落到代码）

`Reporting` = `Core.Modes.MouseProtocol <> tmpNone`；`Override` = 按着覆盖键（`SelectionOverrideKey`：`tsoDefault` 在 macOS 是 Alt、其余是 Shift；`tsoShift`；`tsoAlt`；`tsoNone` 永远 False）；`LinkKey` = 按着链接键（macOS `ssMeta`，其余 `ssCtrl`）且指针下有链接（Task 10 接上，本批先留一个恒 False 的 `LinkAtPress`）。

| 按下时 | 路（`FRoute`） | 拖动 / 移动 | 抬起 |
|---|---|---|---|
| `LinkKey` | `mrLink` | 只更新悬停 | 同一条链接 → `OnLinkActivate`（Task 10） |
| `Reporting` 且非 `Override`，任何键 | `mrReport` | 按住的键按左、中、右优先（核实记录 13）报 `tmaMove` | 报 `tmaUp` |
| 左键（非上报） | `mrSelect` | `DragTo` + 自动滚 | `Release`、写 PRIMARY / `CopyOnSelect` |
| 右键（非上报） | `mrNone`（macOS 先 `RightClickSelect`） | — | — ；菜单由 `DoContextPopup` 弹 |
| 中键（非上报），`FUsesPrimary` | `mrPrimary` | — | 粘贴 PRIMARY |
| 中键（非上报），其他平台；第 4、5 键 | `mrNone` | — | — |
| 没有按键时的移动 | — | `Reporting` 就报 `tmbNone` + `tmaMove`（只有 1003 放行）；否则只更新悬停与光标形状 | — |

路在按下那一刻定，直到开这条路的那个键抬起（地雷 8）；这期间别的键按下：`mrReport` 照报，其他路忽略。

---

### Task 5: 鼠标上报与路由

**Files:**
- Modify: `source/tyControls.Terminal.pas`

- [ ] **Step 1: 构造与状态**
  - 构造里 `CaptureMouseButtons := [mbLeft, mbMiddle, mbRight]`（核实记录 16）；`FUsesPrimary := TyTerminalUsesPrimary`（新常量，主文件开工前问题二第 14 条，放在单元的 interface 常量区）。
  - 字段：`FRoute: (mrNone, mrReport, mrSelect, mrLink, mrPrimary)`、`FRouteButton: TMouseButton`、`FRightReported: Boolean`、`FHorzAccum: Integer`。
  - 两个小函数（受保护，测试也用）：`OverrideHeld(Shift): Boolean`、`ColumnWanted(Shift): Boolean` = `ssAlt in Shift` 且覆盖键不是 Alt（开工前问题二第 11 条）。

- [ ] **Step 2: 上报事件的构造**：把 3 期 `DoMouseWheel` 里造事件的那段（格子 `CellAt`、像素钳在网格、修饰键）抽成 `MakeMouseEvent(AButton, AAction, X, Y, Shift): TTyTerminalMouseEvent`，滚轮也改用它（行为不变，3 期的滚轮测试守着）。LCL → 上游的键：`mbLeft → tmbLeft`、`mbMiddle → tmbMiddle`、`mbRight → tmbRight`、其余不报。移动时的键：`ssLeft` → 左，否则 `ssMiddle` → 中，否则 `ssRight` → 右，否则 `tmbNone`（`MouseService.ts:124-127`，夹具 `terminal-mouse-events.json` 的 `send` 部分就是这张表）。

- [ ] **Step 3: `MouseDown`**（保留 3 期的取焦点，放在最前面）：没有路时按上表定路；`mrReport` → `FCore.TriggerMouseEvent(MakeMouseEvent(键, tmaDown, …))`，右键记 `FRightReported := True`；`mrSelect` 交 Task 6；右键非上报且 `FIsMac` 交 Task 6 的 `RightClickSelect`。已有 `mrReport` 路时别的键按下也照报。

- [ ] **Step 4: `MouseMove`**（新覆盖）：`inherited`；`mrReport` → 报 `tmaMove`（键按 Step 2）；`mrSelect` → Task 6；没有路且 `Reporting` → 报 `tmbNone` 的移动（`TriggerMouseEvent` 按协议与去重决定发不发）。最后更新光标形状（Step 6）。

- [ ] **Step 5: `MouseUp`**：`mrReport` → 报 `tmaUp`；抬起的是 `FRouteButton` → 路清掉（`mrSelect` / `mrPrimary` / `mrLink` 的收尾在 Task 6 / 10）。

- [ ] **Step 6: 光标形状**：`UpdatePointer(Shift)`：链接悬停（Task 10）→ `crHandPoint`；`Reporting` 且非 `Override` → `crDefault`；`ColumnWanted` 且（非上报或 `Override`）→ `crCross`；否则 `Cursor <> crDefault` 时用宿主的 `Cursor`，不然 `crIBeam`。用 `SetTempCursor`，每次 `MouseMove`、`MouseEnter`、修饰键的 `KeyDown` / `KeyUp` 都调（地雷 10）。

- [ ] **Step 7: 横向滚轮 `DoMouseWheelHorz`**（核实记录 17）：`Result := inherited`（宿主的 `OnMouseWheelHorz` / `Left` / `Right` 先拿）；处理了或禁用就返回。`Reporting`：±120 累计（与竖向同一套：同号留余数、反向清零，余数独立于竖向）；每一格 `TriggerMouseEvent(MakeMouseEvent(tmbWheel, WheelDelta < 0 ? tmaLeft : tmaRight, …))`；返回 True。不上报：`Result := False`（交还父控件）。

- [ ] **Step 8: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.pas && git commit -m "feat(terminal): mouse presses, drags, moves and sideways wheels reach the program

When a program asks for the mouse, every button's press and release,
drags with the button held (left before middle before right, as
xterm.js reads them), plain moves and horizontal wheel notches go
through the core's filter and encoder. The path is chosen when a button
goes down and kept until it comes up; the selection override key keeps
the press local. All three buttons capture the mouse, so a drag out of
the control is still reported, clamped to the grid.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 本地选区接进控件

**Files:**
- Modify: `source/tyControls.Terminal.pas`

- [ ] **Step 1: 持有与同步**
  - 构造：`FSelection := TTyTermSelection.Create(FCore.BufferService)`，`WordSeparators` 同步属性（构造值 `' ()[]{}'',"`'`，`stored` 函数判「不等于构造值」）；`FSelection.OnChange := @SelectionChanged`（发 `OnSelectionChange`）、`OnRedraw := @SelectionRedraw`（Task 7 的失效）。析构：先停自动滚计时器，再释放 `FSelection`（在 Core 之前）。
  - `SyncSelectionTrim`：`d := FCore.Buffer.TrimmedLines − FSelTrimBase`；`d > 0` → `FSelection.HandleTrim(d)`；记新读数。调用点：`EndDrive` 末尾、`RenderTo` 画行之前、每个鼠标入口、`SelectionText` / `HasSelection` / `CopyToClipboard`（开工前问题二第 1 条）。
  - 清选区（上游 `clearSelection`，核实记录 10）：
    - `Core.OnUserInput` → 有选区就 `ClearSelection`（新接的 Core 事件；析构里置 nil）；
    - `CoreBufferActivate` → `FSelection.Clear`、重取读数（含 RIS / `Reset`）；
    - `CoreResize` → 行数和上一次不同才清（记 `FSelRows`）；
    - `CoreModesChange` → 协议从 `tmpNone` 变成别的 → 清（上游 `disable()`；记 `FLastProtocol`）；
    - `CoreScrollbackCleared` → 清（我们加的，开工前问题二第 23 条）。

- [ ] **Step 2: 按下、拖动、松开**（`mrSelect` 路）
  - 点：`p := TyTermSelectionPointAt(X − ins.Left, Y − ins.Top, 格宽, 格高, Cols, Rows)`；选区点 = `(p.X, p.Y + Buffer.YDisp)`。
  - 次数：`TyMultiClickCount(ssDouble in Shift, X, Y, FLastClickX, FLastClickY, FLastClickTick, FClickCount, Font.PixelsPerInch)`（开工前问题二第 7 条）。
  - 按下：`FSelection.Press(点, 次数, not Reporting and (ssShift in Shift), ColumnWanted(Shift), 双击时的链接)`——链接在 Task 10 接，本批传 nil。按下后 `FSelection.Dragging` 为真就开自动滚计时器（懒建 `TTimer`，`Interval = 50`，`OnTimer` → `DragScrollTick`；设计期不建）。
  - 右键（非上报）：已有选区什么都不做；`FIsMac` → `FSelection.RightClickSelect(点, 链接)`（开工前问题一第 3 条）。
  - 拖动（`MouseMove` 的 `mrSelect`）：`FSelection.DragTo(点, TyTermDragScrollAmount(Y − ins.Top, Rows × 格高, MulDiv(50, Font.PixelsPerInch, 96)))`——`DragTo` 里的点钳在网格内（`TyTermSelectionPointAt` 已钳），滚速按真实的越界距离算。
  - `DragScrollTick`（受保护）：`n := FSelection.DragScrollAmount`；`n <> 0` → `FCore.ScrollLines(n)`、`FSelection.AfterDragScroll`。
  - 松开左键：停计时器；`FSelection.Release`；`FinishSelection`。
  - `FinishSelection`（「一次选择结束」，开工前问题二第 13 条）：有选区 → `FUsesPrimary` 时 `WritePrimaryText(SelectionText)`；`CopyOnSelect` 时 `WriteClipboardText(SelectionText)`。
  - 中键（`mrPrimary`）松开：`Paste(ReadPrimaryText)`（走括号粘贴编码；空串不发）。

- [ ] **Step 3: 公开 API 与键盘**
  - `SelectAll`、`ClearSelection`、`Select(ACol, AAbsRow, ALength)`（= `SetSelection`）、`SelectLines(AFirst, ALast)`、`SelectionText`（`FSelection.Text(LineEnding)`）、`HasSelection`；`CopyToClipboard` = 有选区才 `WriteClipboardText(SelectionText)`。
  - `KeyDown`：`tkrSelectAll` 算本地动作（新 `kaSelectAll`，照样先问 `OnShortcutQuery`）→ `SelectAll` + `FinishSelection`；原来的注释「选区在 4 期」删掉。复制快捷键已经调 `CopyToClipboard`，不动。
  - `ReadPrimaryText` / `WritePrimaryText` 虚方法：默认 `PrimarySelection.AsText`。
  - 新 published 属性：`SelectionOverrideKey`（`tsoDefault`）、`WordSeparators`、`CopyOnSelect`（False）；事件 `OnSelectionChange`。

- [ ] **Step 4: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.pas && git commit -m "feat(terminal): select with the mouse, copy, select all

Click and drag selects characters, a double click a word, a third click
the wrapped line, Alt+drag a column, Shift+click extends; dragging past
the top or bottom scrolls, faster the further out. The selection moves
with lines trimmed off by new output and goes away on typing, a new
row count, the other screen, a program taking the mouse or a cleared
scrollback. Cmd+A selects all on macOS; a finished selection also goes
to the X11 primary selection, and to the clipboard with CopyOnSelect.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 选区与链接下划线的绘制

**Files:**
- Modify: `source/tyControls.Terminal.Render.pas`、`source/tyControls.Terminal.pas`

- [ ] **Step 1: 行绘制器**（接口见主文件）：第 1 步铺完底色后，`[SelFrom, SelTo)` 里每格的底色换成 `TyTermBlendOver(格底色, SelColor)` 重铺（按格，宽字符两半都在范围里才整格——范围本来就按格给）；第 2 步字形在选区格里、`SelHasInk` 时用 `SelInk`；第 3 步三类线画完后，`[LinkFrom, LinkTo)` 用 `LinkColor` 画单线下划线（在 `UnderlineY`，线宽 `LineW`，盖在格子自己的下划线上）；光标照旧最后画。字段每行由调用方设，`PaintRow` 结尾**不**清（调用方每行都设）。`TyTermBlendOver` 放在 Render 单元，注释写公式。

- [ ] **Step 2: 颜色来源**（`EnsurePalette` 同一个键，主题变了一起失效）：`TyTerminalSelection` 无状态（失焦）与 `[tysFocused]`（聚焦）两份：`background` 取 RGBA（保留 alpha）、`color` 在 `tpTextColor in Present` 时才用（开工前问题二第 21 条——先写一条临时断言跑 17 个主题确认基础层没有继承来的 `tpTextColor`，结论写进提交说明；有继承就停下交主控）；`TyTerminalLink` 的 `color`。禁用时三者都按 `:disabled` 的 opacity 朝父控件底色预混（照 3 期 `PremixFrameColors`，选区色的 alpha 不变、只混 RGB）。按实例的 `StyleClass` / `StyleOverride` 取（照 3 期色表）。

- [ ] **Step 3: 控件按行设字段**：`RenderTo` 画第 r 行前：`SyncSelectionTrim` 已做；`FSelection.RowSpan(YDisp + r, a, b)` → `SelFrom / SelTo`（没有就 0 / 0）；颜色按 `FHasFocus` 取两份之一；链接范围（Task 10）先设空。

- [ ] **Step 4: 失效**（照上游 `handleSelectionChanged` 只重画涉及的行）：`SelectionRedraw` 把「上次画过的选区视口行段」与「现在的段」的并集标脏（`FSelDrawnFirst / Last` 在 `RenderTo` 里记）；`SetHasFocus` 变化时把当前选区的视口行段标脏（两色不同）；滚动已经整屏脏，不另做。

- [ ] **Step 5: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Render.pas source/tyControls.Terminal.pas && git commit -m "feat(terminal): the selection and a hovered link are drawn

Selected cells get the theme's selection colour laid over their own
background, the focused or the unfocused one, and their text the
selection colour only when the theme gives one. A hovered link is
underlined in the link colour. Only the rows a selection change
touches are redrawn; disabled terminals dim these colours too.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 右键菜单

**Files:**
- Modify: `source/tyControls.Terminal.pas`、`source/tyControls.StrConsts.pas`、`languages/tycontrols.strconsts.en.po`、`languages/tycontrols.strconsts.zh_CN.po`

- [ ] **Step 1: 字串**：`StrConsts.pas` 在 `rsTextMenuSelectAll` 附近加 `rsTerminalMenuClear = 'Clear';`；两份 `.po` 照已有条目的格式加（en 的 msgstr `Clear`，zh_CN 的 msgstr `清屏`；msgstr 不能空，地雷 21）。`.pot` 由主控编包时生成。

- [ ] **Step 2: 菜单**（开工前问题一第 1 条）：懒建 `FMenu: TTyPopupMenu`（无 owner，析构里释放）：复制（`rsTextMenuCopy`）、粘贴（`rsTextMenuPaste`）、分隔线、全选（`rsTextMenuSelectAll`）、清屏（`rsTerminalMenuClear`）。受保护 `UpdateContextMenu`（建 + 按状态设 `Enabled`：复制 = `HasSelection`；粘贴 = `not ReadOnly` 且 `ReadClipboardText <> ''`；全选、清屏一直可用）；受保护虚方法 `ShowContextMenu(AClientPos)`：`UpdateContextMenu`、`Controller := Self.Controller`、`PopupComponent := Self`、`PopUp(ClientToScreen(AClientPos))`。四项的 `OnClick`：`CopyToClipboard`、`PasteFromClipboard`、`SelectAll` + `FinishSelection`、`Clear`。

- [ ] **Step 3: `DoContextPopup`**（地雷 9）：`inherited`（宿主的 `OnContextPopup` 先拿，处理了就返回）；「这次右键是上报的」→ `Handled := True`、清标志、返回。判定：`FRightReported` 为真；或（标志不在、菜单先于按下到）`Reporting` 且非 `OverrideHeld(CurrentShiftState)`——`CurrentShiftState` 是受保护虚方法（默认 `GetKeyShiftState`），测试可以替换。`PopupMenu <> nil` → 返回（LCL 弹宿主的）。否则位置：`(-1, -1)`（菜单键）→ 光标格左下角；`ShowContextMenu(位置)`；`Handled := True`。

- [ ] **Step 4: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.pas source/tyControls.StrConsts.pas languages/tycontrols.strconsts.en.po languages/tycontrols.strconsts.zh_CN.po && git commit -m "feat(terminal): a right-click menu -- copy, paste, select all, clear

The themed popup the text controls use, with the four actions a
terminal has. A right click a program has taken is reported instead;
the selection override key brings the menu back. A PopupMenu set on
the control replaces it, and the menu key opens it at the cursor.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 鼠标、选区、菜单、绘制的测试

**Files:**
- Create: `tests/test.terminal.view.mouse.pas`（suite `TTyTerminalViewMouseTests`）
- Modify: `tests/test.terminal.view.pas`（探针加方法）、`tests/test.terminal.view.paint.pas`（加选区像素）、`tests/tytests.lpr`

**探针加的**（`TTyTerminalViewProbe`）：`Down(Button, Shift, X, Y)`、`MoveTo(Shift, X, Y)`、`Up(Button, Shift, X, Y)`、`WheelHorz(Shift, Delta, Pos): Boolean`、`ContextPopup(Pos): Boolean`（调 `DoContextPopup`，返回 `Handled`）、`MenuShownAt: TPoint` / `MenuShows: Integer`（覆盖 `ShowContextMenu`：记下、调 `UpdateContextMenu`、不 `PopUp`）、`MenuItem(i): TMenuItem`、`PrimaryText` / `PrimaryWrites` / `PrimaryWritten`（覆盖两个 PRIMARY 虚方法）、`FakeShift`（覆盖 `CurrentShiftState`）、`TickDrag`、`DragTimerOn`、`Sel: TTyTermSelection`、`Route`、`LastTempCursor`（覆盖 `SetTempCursor` 记下再 `inherited`）、`SetPrimaryPlatform(B)`。坐标一律用 `View.CellRect(c, r)` 的中心，不写死像素。`OnData` 拼十六进制比（3 期做法）。

`TTyTerminalViewMouseTests`：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestWithoutProtocolADragSelects` | 写 `hello world`；左键在格 (0,0) 按下、移到 (5,0) 的中心右半、抬起 → `SelectionText = 'hello '`（半格规则：右半算到下一格边界），没有 `OnData` | M1：路由不看协议（按下被上报） |
| `TestPressAndReleaseAreReported` | `CSI ? 1000 h CSI ? 1006 h`；左键 (2,1) 按下 → `1B 5B 3C 30 3B 33 3B 32 4D`；抬起 → 同上末字节 `6D`；`HasSelection = False` | M2：抬起不报 |
| `TestDragsFollowTheProtocol` | 1000：按住左键移动 → 无；1002：→ `ESC[<32;…M`；1003 不按键移动 → `ESC[<35;…M`；1002 不按键移动 → 无；按住中键 + 右键（`[ssMiddle, ssRight]`）在 1002 下移动 → `ESC[<33;…M` | M3：移动时键的优先级右先于中 |
| `TestTheRouteIsKeptUntilRelease` | 1002：Shift+左键按下（覆盖键）、移动时 `Shift` 里不再有 `ssShift` → 仍在选择、没有 `OnData`；抬起后再不带 Shift 按下 → 上报 | M4：每次移动重新判路 |
| `TestOverrideKeyValues` | Windows 标志：`tsoDefault` → Shift 本地；macOS 标志：`tsoDefault` → Alt 本地、Shift 上报（带 shift 位 4）；`tsoAlt` → Alt 本地；`tsoNone` → Shift 上报 | M5：macOS 默认仍是 Shift |
| `TestModifiersAreReported` | 1000 + 1006：Ctrl+Alt 左键按下（Windows 标志，默认覆盖键）→ 事件码 24 | — |
| `TestMiddleAndRightAreReported` | 1000 + 1006：中键 → 码 1；右键 → 码 2；`mbExtra1` → 无 | M6：右键不报 |
| `TestAllThreeButtonsCapture` | `CaptureMouseButtons = [mbLeft, mbMiddle, mbRight]` | M7：构造里没设 |
| `TestADragOutsideIsClampedToTheGrid` | 1002 + 1006：左键 (1,1) 按下，移到 `(-50, 10000)` → `ESC[<32;1;<Rows>M` | — |
| `TestTheSidewaysWheel` | 1000 + 1006：`WheelHorz(-120)` → 码 66、返回 True；`+120` → 67；`+60` 两次 → 一次 67；无协议 → 返回 False、无 `OnData` | M8：左右对调；M9：不累计 |
| `TestTakingTheMouseClearsTheSelection` | 选中一段、`OnSelectionChange` 计数清零；`WriteSync(CSI ? 1000 h)` → `HasSelection = False`、计数 1 | E1：协议变化不清 |
| `TestShiftClickExtendsOnlyWithoutAProtocol` | 无协议：单击 (0,0)、Shift+单击 (4,0) → 选 4 格；1000 下 Shift+单击（覆盖键）→ 新选区起点 | — |
| `TestDoubleAndTripleClicks` | `foo bar.baz qux`：第二次按下带 `ssDouble` 在 `bar` 上 → `bar.baz`；紧接着第三次（不带 `ssDouble`、同位置）→ 整行 | E2：`ssDouble` 不看（双击当单击） |
| `TestAltDragIsAColumn` | Windows：Alt+拖 从 (1,0) 到 (3,2) → 三行各两字符、`#13#10` 分隔；macOS 标志 + 默认覆盖键 + 1000：Alt+拖 → 本地但**不是**列（`Mode <> tsmColumn`） | E3：`ColumnWanted` 不看覆盖键 |
| `TestDraggingOffTheTopScrolls` | 5 行、写 100 行、在第 2 行按下、移到网格上方 30 像素 → `DragTimerOn`；`TickDrag` → `YDisp` 减少 `TyTermDragScrollAmount(-30, …)`、选区终点行 = `YDisp`；抬起 → 计时器停 | E4：没开计时器；E5：`TickDrag` 不调 `AfterDragScroll` |
| `TestTheSelectionFollowsOutput` | 5 行、滚回 10：写 12 行，选中滚回里 `line-3` 那行，再写 3 行 → `SelectionText` 仍是 `line-3`；再写 20 行 → 清掉 | E6：`SyncSelectionTrim` 不调 |
| `TestTypingClearsTheSelection` | 选中后 `TypeChar('x')` → 清；`ReadOnly := True` 时选中后打字 → 不清（上游 `disableStdin` 不发 `onUserInput`） | E7：`OnUserInput` 没接 |
| `TestWhenTheSelectionIsCleared` | 改列数不清；改行数清；`CSI ? 1049 h` 清；`Clear` 清；`Reset` 清；每次 `OnSelectionChange` 各一次 | E8：`CoreResize` 列变也清 |
| `TestSelectAllOnTheMac` | macOS 标志：`Meta+A` → 全选、`Key = 0`、没有 `OnData`；Windows：`Ctrl+A` → `01` | E9：`tkrSelectAll` 仍不当动作 |
| `TestCopyWritesTheSelection` | 有选区：`Ctrl+Shift+C` → 剪贴板桩 = 选区文本（两行时中间是 `LineEnding`）；没选区 → 桩没被写 | E10：`CopyToClipboard` 不看 `HasSelection`（写空串） |
| `TestCopyOnSelect` | 打开：拖选松手 → 剪贴板写一次；关（默认）→ 不写；`Meta+A`（macOS 标志）也写一次 | E11：`FinishSelection` 不看 `CopyOnSelect` |
| `TestThePrimarySelection` | `SetPrimaryPlatform(True)`：松手写 PRIMARY；中键（无协议）松开 → 粘贴 PRIMARY（`CSI ? 2004 h` 时带括号）；1000 下中键 → 上报、不粘贴；`SetPrimaryPlatform(False)`：松手不写、中键什么都不做 | E12：中键粘贴不看平台 |
| `TestSelectionEventsCount` | `SelectAll` 1 次；`ClearSelection` 1 次；`Select(0, YBase, 3)` 1 次；同一范围再 `Select` 0 次（没变） | E13：`OnChange` 没转发 |
| `TestTheMenuWithoutAProtocol` | `ContextPopup((10, 10))` → `MenuShows = 1`、`Handled`；四项标题是四个 resourcestring；没选区时复制灰、剪贴板桩空时粘贴灰、`ReadOnly` 时粘贴灰 | U1：`DoContextPopup` 不接 |
| `TestAReportedRightClickHasNoMenu` | 1000：右键按下抬起（上报）后 `ContextPopup` → `Handled`、`MenuShows = 0` | U2：不看 `FRightReported` |
| `TestTheMenuBeforeThePress` | 1000、`FakeShift = []`、没有按下过 → `ContextPopup` 不弹；`FakeShift = [ssShift]` → 弹 | U3：没有「现算」这条 |
| `TestOverrideRightClickShowsTheMenu` | 1000：Shift+右键 → 不上报、`ContextPopup` 弹 | — |
| `TestTheHostsPopupMenuWins` | `PopupMenu := TPopupMenu.Create(Form)` → `ContextPopup` 返回 `Handled = False`、`MenuShows = 0` | — |
| `TestMenuItemsAct` | 有选区时点复制 → 剪贴板；全选 → `HasSelection`；清屏 → `Core.Buffer.YBase = 0`（滚回清掉） | U4：清屏调了 `Reset` |
| `TestTheMenuKeyOpensAtTheCursor` | `CSI 3;5H` 后 `ContextPopup((-1, -1))` → `MenuShownAt` = 格 (4, 2) 的左下角 | — |
| `TestRightClickKeepsTheSelection` | Windows：有选区时右键按下 → 选区不变、`OnSelectionChange` 0 次 | — |
| `TestRightClickSelectsAWordOnTheMac` | macOS 标志：没选区时在 `bar` 上右键 → 选中 `bar`；在空白上右键 → 不选 | E14：`RightClickSelect` 允许纯空白 |
| `TestPointerShapes` | 无协议 → `crIBeam`；1000 → `crDefault`；1000 + Shift 移动 → `crIBeam`；Alt 移动（无协议）→ `crCross`；宿主 `Cursor := crHelp` → 平常用 `crHelp` | M10：接管时仍是 `crIBeam` |

**`TTyTerminalViewPaintTests` 加的**（哨兵底色、`CellRect` 定位、先打包围盒，地雷 14）：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestSelectionIsPainted` | 空行上选 (2..5)：这 4 格每个像素 = `TyTermBlendOver(主题底色, 失焦选区色)`；格 1、格 6 = 主题底色；`Enter` 后重画 → 聚焦选区色 | P1：选区不画；P2：焦点变化不重画选区行（`Enter` 后仍是失焦色） |
| `TestSelectedTextKeepsItsColourUnlessTheThemeSaysSo` | 选中一个 █：格内像素 = 前景色（█ 整格墨）；换一个给 `TyTerminalSelection:focus { color: #ff0000 }` 的夹具主题、聚焦后 → 纯红 | P3：`SelHasInk` 恒真（默认主题下 █ 被换色） |
| `TestAColumnIsARectangle` | Alt 拖出 3 × 2 的列：只有这 6 格是选区色 | — |
| `TestTheSelectionScrollsWithTheText` | 滚回里选中一行后 `ScrollLines(-1)` → 选区色下移一行（在缓冲行上，不在视口行上） | P4：`RowSpan` 用视口行 |
| `TestOnlyTouchedRowsRepaint` | 在第 3 行里改选区 → 失效的行只有第 3 行（`Invalidated` 记录） | P5：`SelectionRedraw` 整屏失效 |
| `TestADisabledSelectionIsDimmed` | `Enabled := False` 后选区格的颜色 = 预混后的底色再叠预混后的选区色（公式同 3 期禁用测试） | P6：选区色不预混 |

- [ ] **Step 1: 写测试单元、改探针、加进 `tytests.lpr`**
- [ ] **Step 2: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add tests/test.terminal.view.mouse.pas tests/test.terminal.view.pas tests/test.terminal.view.paint.pas tests/tytests.lpr && git commit -m "test(terminal): mouse routes, the selection, the menu and their pixels

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 3: 段 4b 编译并跑本段 suite**（主文件「跑测试的固定套路」4b 行）。只修本段的红。
