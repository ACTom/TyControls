# 终端控件 3 期 · 3c 输入与滚回（Task 11–14）

> 本文件是 [`2026-09-29-terminal-phase-3.md`](2026-09-29-terminal-phase-3.md) 的附录，执行方式、核实记录、开工前问题、接口清单、地雷都在主文件。先读主文件，尤其是核实记录 10（`KeyDown` 清零与 `WM_CHAR`）、开工前问题二第 10 条（3 / 4 期边界）。

**这一批做完能看到什么**：键盘经真实的 `KeyDown` / `UTF8KeyPress` 发出正确字节——吞键、`OnShortcutQuery` 放行、复制粘贴快捷键、本地翻页、第三层 Shift、Alt 前缀、macOS Option、Ctrl+C 永远发给程序；内嵌滚动条跟着缓冲走、拖动能滚、备用屏禁用、列数不变；竖向滚轮三种去向；点击取焦点；输入法提交、候选窗在光标格、macOS 组字串画在光标处。段末编译一次，只跑 3a–3c 的 suite。

---

### Task 11: 键盘接进控件

**Files:**
- Modify: `source/tyControls.Terminal.pas`

- [ ] **Step 1: `KeyDown(var Key: Word; Shift: TShiftState)`**（spec §9.4；上游 `_keyDown`，`CoreBrowserTerminal.ts:860-940`）

1. `inherited KeyDown(Key, Shift)`（宿主的 `OnKeyDown` 先拿到；它把 `Key` 清零了就直接返回）；`FKeyDownHandled := False`；`FLastKeyShift := Shift`。
2. `Key = VK_PROCESSKEY`（229，输入法处理中）→ 返回，不动 `Key`（`CompositionHelper.ts:117-131` 的同一个意思）。
3. `ev := TyTerminalKeyEventFromLCL(Key, Shift)`。
4. **本地动作**先认（按平台标志 `FIsMac`）：
   - 复制：Win / Linux `Ctrl+Shift+C`、`Ctrl+Insert`；macOS `Meta+C`。
   - 粘贴：Win / Linux `Ctrl+Shift+V`、`Shift+Insert`；macOS `Meta+V`。
   - `Shift+Home` / `Shift+End` → 到顶 / 到底（定稿时新加）。
   - 其余交 `r := TyTerminalEvaluateKey(ev, Modes.ApplicationCursorKeys, FIsMac, MacOptionIsMeta)`：`tkrPageUp` / `tkrPageDown` → `ScrollLines(∓(Rows − 1))`（上游 `rows - 1`，`CoreBrowserTerminal.ts:873-878`）；`tkrSelectAll` → 本期**不算**动作（选区 4 期）、不吞；`tkrSendKey` 且 `r.Key <> ''` → 发送动作。
5. `TyTerminalIsThirdLevelShift(ev, FIsMac, FIsWindows, MacOptionIsMeta, False)` 为真 → 返回，不动 `Key`（字符留给 `UTF8KeyPress`；上游 `return true`）。
6. **可出字符的键**：`r` 来自默认分支的「无修饰单字符」那一支（`not Ctrl and not Alt and not Meta and (KeyCode >= 48) and (Key 是一个 UTF-16 单元)`），以及空格（上游 keydown 不发空格）→ 返回，**不清零**（核实记录 10：清零会让 Win32 吞掉随后的字符）。判断写成一个小函数 `KeyWaitsForItsCharacter(ev)`，注释引 `Keyboard.ts:361-364` 与 `CoreBrowserTerminal.ts:898-903`。
7. 没有动作 → 返回（`Key` 原样往下走：窗体快捷键、Tab 导航照常）。
8. 有动作 → 先问 `OnShortcutQuery(Self, Key, Shift, pass)`（`pass` 初值 False）；`pass` → 返回、不动 `Key`。否则执行动作：发送 = `FCore.Input(r.Key, True)` + 记一次活动（闪烁）；复制 = `CopyToClipboard`（本期空实现：没有选区，什么都不做）；粘贴 = `PasteFromClipboard`；翻页 / 到顶到底 = 对应 `Scroll*`。然后 `Key := 0`、`FKeyDownHandled := True`。
9. `ReadOnly` 不在这里判断：发送照走，Core 把 `OnData` 挡掉（上游 `disableStdin` 同样在 `triggerDataEvent` 里挡）；本地动作照常。

- [ ] **Step 2: `UTF8KeyPress(var UTF8Key: TUTF8Char)`**（上游 `_keyPress`，`:958-1000`）

1. `full := TyImeTakeCommit(UTF8Key)`（地雷 4；GTK3 的截断绕行）；非空 → `HandleImeCommit(full)`、`UTF8Key := ''`、返回。
2. `inherited UTF8KeyPress(UTF8Key)`；`UTF8Key = ''` → 返回。
3. `FKeyDownHandled` → 清掉它、`UTF8Key := ''`、返回（上游 `_keyDownHandled`）。
4. 上一次 `KeyDown` 的修饰键（`FLastKeyShift`）含 Ctrl / Alt / Meta，且不是第三层 Shift（`TyTerminalIsThirdLevelShift(…, AKeyPress = True)`）→ 丢掉（上游 `:980-985`）。
5. 控制字符（`< #32`、`#127`）丢掉——它们只可能是 `KeyDown` 已经处理过、widgetset 又送来的那一份。
6. 其余：`FCore.Input(UTF8Key, True)`、记一次活动、`UTF8Key := ''`。

- [ ] **Step 3: 粘贴与输入**：`Paste(AText)` = `FCore.Input(TyTerminalPrepareTextForPaste(AText, Modes.BracketedPaste), True)`；`PasteFromClipboard` = `Paste(ReadClipboardText)`（空串不发）；`Input(AText)` = `FCore.Input(AText, True)`；`ReadClipboardText` / `WriteClipboardText` 虚方法照 `Edit.pas:1839-1847`（`Clipboard.AsText`）。粘贴、输入同样由 `ScrollOnUserInput` 经 Core 的 `OnRequestScrollToBottom` 滚到底（Task 7 已接）。

- [ ] **Step 4: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.pas && git commit -m "feat(terminal): keys go to the program, and only the host can take one back

Every key with an encoding is sent and swallowed, Tab and Ctrl+letters
included, unless OnShortcutQuery lets it through to the form. Keys that
type a character are left for the character event so any keyboard layout
works; a key already sent drops the character the widgetset may still
deliver. Ctrl+Shift+C/V and Ctrl/Shift+Insert (Cmd+C/V on macOS) are
copy and paste, Ctrl+C always goes to the program, Shift+PgUp/PgDn and
Shift+Home/End page the scrollback.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: 滚动条、滚轮、点击取焦点

**Files:**
- Modify: `source/tyControls.Terminal.pas`

- [ ] **Step 1: 内嵌滚动条**（spec §9.7；照 `Memo.pas:2372-2506` 的竖条部分）

- `UpdateScrollBar`：设计期直接返回；第一次调用时懒建（`Memo.pas:2408-2424` 逐项照抄：`Parent := Self`、`Kind := sbVertical`、`Align := alRight`、`TabStop := False`、`OnChange := @ScrollBarChange`、`AnimationsEnabled := False`、`AutoHide := FScrollBarAutoHide`、`ControlStyle + [csNoDesignVisible]`、`Width := barW`、`Controller := Self.Controller`）。`UpdateGrid` 里调它；`Controller` 换了要推给条（同 Memo）。
- `SyncScrollBar`（`OnScroll`、`OnBufferActivate`、`OnScrollbackCleared`、`OnResize` 之后调）：在 `FSyncingScroll` 守卫里设 `Min := 0`、`Max := Buffer.YBase`（**最大位置**，= 行数 − 视口行数，[[scrollbar-max-is-position-not-content]]）、`PageSize := Rows`、`Position := Buffer.YDisp`、`Enabled := Buffer.HasScrollback`（备用屏、`Scrollback = 0` 都是 False）。**不改** `Visible`（开工前问题一第 2 条、地雷 6）。
- `ScrollBarChange`：`FSyncingScroll` 时返回；否则 `FCore.ScrollLines(FScrollBar.Position − Buffer.YDisp)`。
- `ITyScrollBarFrameHost`：`ScrollBarFrameStyle := CurrentStyle`；`EmbedsScrollBar(ABar) := ABar = FScrollBar`（`Memo.pas:2362-2370`）。
- `MouseEnter` / `MouseLeave` 在 `inherited` 之后 `NoteHostHover(True / False)`（`Memo.pas:1308-1320`，自动隐藏的条靠它醒来）。
- `SetScrollBarAutoHide` 推给已建的条。

- [ ] **Step 2: 竖向滚轮 `DoMouseWheel(Shift, WheelDelta, MousePos): Boolean`**（spec §9.5.3 / §9.5.4；核实记录 14）

1. `Result := inherited`（宿主 `OnMouseWheel` 先拿；它处理了就返回 True）；已处理或 `not Enabled` → 返回。
2. `FWheelAccum += WheelDelta`；每满 ±120 出一格（同号的余数留着，反向时清零）；本次一格都不满也 `Result := True`（吃掉这点位移，不让父控件滚）。
3. 每一格：
   - `Modes.MouseProtocol <> tmpNone`：造 `TTyTerminalMouseEvent`（`CellAt(MousePos)` 的列行、`MousePos` 的设备像素、`Button := tmbWheel`、`Action := 上 ? tmaUp : tmaDown`、`Shift` / `Alt` / `Ctrl` 取自 `Shift`）→ `FCore.TriggerMouseEvent(ev)` 返回 True → 这一格结束。
   - 否则 `Buffer.HasScrollback` → `FCore.ScrollLines(上 ? −3 : 3)`（每格 3 行，同 Memo）。
   - 否则 `AlternateScroll` → `FCore.Input(ESC + (应用光标 ? 'O' : '[') + (上 ? 'A' : 'B'), True)`。
4. `Result := True`。横向滚轮（`DoMouseWheelLeft` / `Right`）、按键上报、覆盖键都在 4 期（开工前问题二第 10 条）。

- [ ] **Step 3: 点击取焦点**：`MouseDown` 在 `inherited` 之后 `if CanFocus and not Focused then SetFocus`。本期不做任何上报和选择。

- [ ] **Step 4: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.pas && git commit -m "feat(terminal): the scroll bar follows the scrollback, the wheel goes three ways

The embedded bar's maximum is the top line's furthest position, it is
disabled where there is no scrollback (the alternate screen, or none
configured) and its width is always reserved. A wheel notch is reported
to a program that asked for wheel events, otherwise scrolls three lines
back, otherwise -- no scrollback, AlternateScroll on -- sends an arrow
key, as xterm.js does. A click gives the terminal focus.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: 输入法

**Files:**
- Modify: `source/tyControls.Terminal.pas`

spec §9.9；库内先例 `Edit.pas:2201-2274`、`Memo.pas:4464`、`:4565-4572`；接口 `TextMenu.pas:52-61`；Cocoa 驱动 `CocoaWS.pas:60-95`。

- [ ] **Step 1: 钩子的装卸**：`InitializeWnd` 里 `TyImeUninstall(FImeHook); FImeHook := TyImeInstall(Self, @HandleImeCommit, @GetImeCaretRect)`；`DestroyWnd` 和析构里 `TyImeUninstall`；`DoEnter` / `DoExit` 里 `TyImeSetFocus(FImeHook, True / False)`（照 `Edit.pas:598-627`）。设计期不装。

- [ ] **Step 2: 提交与光标矩形**

- `HandleImeCommit(const ACommitUtf8: string)`：非空 → `FCore.Input(ACommitUtf8, True)`、记一次活动。
- `ImeCaretCell: TRect`（受保护，FOR THE TESTS 也用）：`CellRect(Buffer.X, Buffer.Y)`，宽字符不扩（候选窗只要一个锚点）；视口不在底部时仍按光标所在屏幕行算（候选窗跟着光标，不跟视口）。
- `GetImeCaretRect`：没句柄或没焦点 → 空矩形；否则 `FImeCaretRect`（缓存）。
- 光标矩形更新（`RenderTo` 末尾，照 `Edit.pas:2706-2710` 与 `Memo.pas:4464`）：`ImeCaretCell` 和 `FImeCaretRect` 不同 → 存下、`TyImeUpdateCaret`（Qt 要主动戳）；聚焦时 `TySetImeCaretPos(Self, r.Left, r.Top)`（Win32 IMM32）。`OnCursorMove` 标脏的光标行会触发一次重画，所以光标一动矩形就跟上。

- [ ] **Step 3: macOS 的 `ITyImeEditable`**（本地组字串，不碰缓冲）

- `ImeTargetControl` = `Self`；`ImeIsReadOnly` = `ReadOnly`（Cocoa 驱动见只读直接不组字）；`ImeCaretBoundClient` = 有焦点时 `ImeCaretCell`，否则空矩形；`ImeCaretIndex` = 0（组字串从本地串开头算）。
- `ImeSessionBegin`：`FPreedit := ''`、`FInPreedit := True`。
- `ImeReplace(AStart, ALen, AText)`：在 `FPreedit` 上按**码位**下标删 `[AStart, AStart + ALen)`、在 `AStart` 插 `AText`（越界钳住）；光标行标脏。
- `ImeSessionEnd`：`FPreedit <> ''` → `FCore.Input(FPreedit, True)`；清空、`FInPreedit := False`、光标行标脏。取消时驱动先把串换成空再结束，自然不发（spec §9.9）。
- 组字串的画法（`RenderTo` 第 4 步画完光标行之后、只在 `FPreedit <> ''` 时）：从光标格起，宽度按 `TyUnicodeStringCellWidth(FPreedit, UnicodeVersion, AmbiguousWide)` 格，超出行尾截断；底色 = `TyTerminalPreedit` 的 `background`、字 = 其 `color`、底部一条 `LineW` 高的线 = 其 `border-color`；字形走同一个光栅器与缓存。组字串不进缓冲、不影响光标位置。

- [ ] **Step 4: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.pas && git commit -m "feat(terminal): input methods commit to the program and follow the cursor

The library's per-widgetset hooks deliver committed text, which goes out
as typed input; the candidate window is anchored on the cursor's cell
and moved whenever the cursor moves. On macOS the marked text is kept in
the control, drawn over the cursor line, and sent once when the session
ends -- a cancelled composition sends nothing.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: 输入与滚回测试

**Files:**
- Create: `tests/test.terminal.view.input.pas`（suite `TTyTerminalViewInputTests`，用 Task 9 的探针与夹具）
- Modify: `tests/tytests.lpr`

探针的平台标志默认等于 `TyTerminalIsMac` / `TyTerminalIsWindows`（测试在 Windows 上跑），macOS 的几条把 `FIsMac := True; FIsWindows := False`。按键一律经探针的 `KeyDown` / `UTF8KeyPress`（控件自己的覆盖方法，不是直接调 `TyTerminalEvaluateKey`）。`OnData` 拼成十六进制串比。

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestPlatformFlagsDefaultToThePlatform` | 新控件的两个标志等于两个常量 | I1：构造里把 `FIsMac` 写死 |
| `TestAnArrowIsSentAndSwallowed` | `KeyDown(VK_UP, [])` → `OnData = 1B 5B 41`、`Key = 0` | I2：发了但没清零 |
| `TestApplicationCursorFollowsTheProgram` | `WriteSync(CSI ? 1 h)` 后 `VK_UP` → `1B 4F 41` | I3：应用光标参数传常量 False |
| `TestPrintableKeysWaitForTheirCharacter` | `KeyDown(Ord('A'), [])` → 没有 `OnData`、`Key` 仍是 `Ord('A')`；随后 `UTF8KeyPress('a')` → `61` | I4：在 `KeyDown` 里就发（两次 `61` 或 `Key` 被清零） |
| `TestSpaceWaitsToo` | `KeyDown(VK_SPACE, [])` 不发、不清零；`UTF8KeyPress(' ')` → `20` | — |
| `TestAKeySentInKeyDownDropsItsCharacter` | `KeyDown(VK_RETURN)` → `0D`；随后 `UTF8KeyPress(#13)` → 不再发；`Ctrl+A` → `01`，随后 `UTF8KeyPress(#1)` 不再发 | I5：不看 `FKeyDownHandled` |
| `TestCharactersTypedWithCtrlAreDropped` | `KeyDown(Ord('B'), [ssCtrl, ssShift])`（上游不编码）后 `UTF8KeyPress('B')` → 不发 | I6：`UTF8KeyPress` 不看上一次的修饰键 |
| `TestAltGrLeavesTheCharacter` | Windows 标志：`KeyDown(Ord('Q'), [ssCtrl, ssAlt])` → 不发、不清零；`UTF8KeyPress('@')` → `40` | I7：第三层 Shift 没判断（会发 `1B 11`） |
| `TestAltPrefixesEscape` | Windows：`Alt+F` → `1B 66`，`Key = 0`；macOS 标志、`MacOptionIsMeta = False`：`Alt+F` → 不发（第三层）；`True` → `1B 66` | I8：`MacOptionIsMeta` 没传进去 |
| `TestTabStaysInTheTerminal` | `KeyDown(VK_TAB, [])` → `09`、`Key = 0` | — |
| `TestShortcutQueryLetsAKeyThrough` | 宿主对 `VK_TAB` 放行：`KeyDown(VK_TAB)` → 没有 `OnData`、`Key = VK_TAB`；同一个宿主对 `VK_UP` 不放行 → 照发；查询收到的 `Key` / `Shift` 就是这次的键 | I9：没问；I10：问了不看结果 |
| `TestShortcutQueryIsAskedForLocalActionsToo` | 放行 `Ctrl+Shift+V` → 剪贴板桩没被读、没有 `OnData`、`Key` 不变 | I11：本地动作跳过查询 |
| `TestPasteShortcuts` | 剪贴板桩 `'a'#10'b'`：`Ctrl+Shift+V` 与 `Shift+Insert` 各得 `61 0D 62`；`CSI ? 2004 h` 后 → `1B 5B 32 30 30 7E 61 0D 62 1B 5B 32 30 31 7E`；macOS 标志下 `Meta+V` 同样粘贴，`Ctrl+Shift+V` 不粘贴 | I12：`Shift+Insert` 没认；I13：粘贴没走括号编码 |
| `TestCtrlCAlwaysGoesToTheProgram` | Windows 与 macOS 标志下 `Ctrl+C` 都是 `03` | I14：Ctrl+C 当复制 |
| `TestTheCopyShortcutIsSwallowed` | `Ctrl+Shift+C` → 没有 `OnData`、`Key = 0`、剪贴板桩没被写（没有选区） | — |
| `TestLocalPaging` | 5 行终端写 100 行：`Shift+PgUp` → `YDisp = YBase − 4`；`Shift+PgDn` 回到 `YBase`；`Shift+Home` → 0；`Shift+End` → `YBase`；四次都没有 `OnData` | I15：翻页用 `Rows` 不是 `Rows − 1` |
| `TestTypingScrollsToTheBottom` | 上翻后 `UTF8KeyPress('x')` → `YDisp = YBase`；`ScrollOnUserInput := False` 时不动 | I16：`OnRequestScrollToBottom` 没接 |
| `TestReadOnlySendsNothingButStillPages` | `ReadOnly := True`：`VK_UP`、`UTF8KeyPress('x')`、粘贴都没有 `OnData`；`Shift+PgUp` 照滚 | — |
| `TestTheImeKeyIsLeftAlone` | `KeyDown(VK_PROCESSKEY)` → 不发、`Key` 不变、`OnShortcutQuery` 没被问 | I17 等价、不做：去掉 229 的早退后，上游对 229 本来就没有编码、也不是本地动作，照样不发不问；早退只是省一次求值 |
| `TestTheBarTracksTheBuffer` | 5 行、`Scrollback = 1000`，写 100 行：条 `Max = Buffer.YBase`、`PageSize = 5`、`Position = YDisp`；`ScrollLines(-10)` → `Position = YBase − 10` | I18：`Max` 设成总行数 |
| `TestDraggingTheBarScrolls` | `FScrollBar.Position := 3`（经它的 `OnChange`）→ `YDisp = 3` | I19：`OnChange` 没接 |
| `TestTheAltScreenDisablesTheBar` | `CSI ? 1049 h` → `Enabled = False`；`CSI ? 1049 l` → True；`Scrollback := 0` → False | I20 |
| `TestColumnsSurviveTheAltScreen` | 进出备用屏，`Cols` 不变、`OnGridResize` 一次都没发、条的 `Visible` 始终 True | I21：备用屏时把条藏起并不扣条宽 |
| `TestTheBarSitsOnTheRightEdge` | 探针里 `AlignControls(nil, ClientRect)`（传**没扣过**的矩形，[[headless-tests-never-run-lcl-align]]）→ 条 `Left = ClientWidth − barW`、`Width = barW`（`--scrollbar-size` 按 PPI） | — |
| `TestTheBarIsAFrameHost` | `EmbedsScrollBar(条) = True`、别的条 False；`ScrollBarFrameStyle` 的底色 = `CurrentStyle` 的底色 | — |
| `TestNoBarAtDesignTime` | 设计期排版后没有 `TTyScrollBar` 子控件（接 Task 9 的 V23b） | V23b |
| `TestTheWheelScrollsTheScrollback` | 100 行：`+120` → `YDisp` 少 3；`−120` → 多 3；两次 `+60` → 合起来一格 | I22：不累计（`+60` 就滚）；I23：每格 1 行 |
| `TestTheWheelSendsArrowsWithoutScrollback` | 备用屏：`+120` → `1B 5B 41`；`CSI ? 1 h` 后 → `1B 4F 41`；`AlternateScroll := False` → 什么都不发 | I24：不看 `AlternateScroll` |
| `TestTheWheelIsReportedWhenAsked` | `CSI ? 1000 h CSI ? 1006 h`，在格 (2, 1) 的中心滚上一格 → `1B 5B 3C 36 34 3B 33 3B 32 4D`（`ESC[<64;3;2M`） | I25：不调 `TriggerMouseEvent` |
| `TestX10DoesNotTakeTheWheel` | 备用屏 + `CSI ? 9 h`（X10 不报滚轮）→ 方向键 | I26：协议非 NONE 就当已上报 |
| `TestTheHostsWheelHandlerComesFirst` | 宿主 `OnMouseWheel` 置 `Handled` → 没滚、没发 | — |
| `TestAClickTakesFocus` | 真窗体（照 `test.focus.tabstop.pas` 的 `TTyClickFocusTest` 写法，惰性初始化 widgetset、`Show`）：左键按下 → `Focused` | I27：`MouseDown` 不 `SetFocus` |
| `TestImeCommitsAreSent` | `HandleImeCommit('中文')` → `OnData` = 那六个字节；`ReadOnly` 时不发 | I28：提交没接到 Core |
| `TestTheImeAnchorIsTheCursorCell` | `CSI 3;5H` 后 `ImeCaretCell = CellRect(4, 2)` | I29：行列对调 |
| `TestMarkedTextIsKeptUntilTheSessionEnds` | `ImeSessionBegin`；`ImeReplace(0, 0, 'zh')` → 没有 `OnData`，重画后光标格有 `TyTerminalPreedit` 的下划线色像素；`ImeReplace(0, 2, '中')`；`ImeSessionEnd` → `OnData = E4 B8 AD`；再画，光标格没有组字串的颜色 | I30：`ImeSessionEnd` 不清空（下一次会重发） |
| `TestACancelledCompositionSendsNothing` | 开始、`ImeReplace(0, 0, 'x')`、`ImeReplace(0, 1, '')`、结束 → 没有 `OnData` | — |

- [ ] **Step 1: 写测试单元、加进 `tytests.lpr`**
- [ ] **Step 2: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add tests/test.terminal.view.input.pas tests/tytests.lpr && git commit -m "test(terminal): keys, shortcuts, the scroll bar, the wheel and input methods

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 3: 段 3c 编译并跑本段 suite**（主文件「跑测试的固定套路」3c 行）。只修本段的红。
