# 终端控件 4 期 · 4c 链接与 OSC 52（Task 10–12）

> 本文件是 [`2026-09-29-terminal-phase-4.md`](2026-09-29-terminal-phase-4.md) 的附录，执行方式、核实记录、开工前问题、接口清单、地雷都在主文件。先读主文件，尤其是核实记录 19–23、开工前问题一第 2、6 条与二第 15、22 条，以及 4b 附录开头的「谁拿鼠标」表（`mrLink` 那一行由本批接上）。

**这一批做完能看到什么**：按住 Ctrl（macOS Cmd）时，指针下的链接（OSC 8，或 `DetectUrls` 开着时认出的网址）画下划线、光标变手形，不按就是普通文字；Ctrl+单击（按下和抬起在同一条链接上）发 `OnLinkActivate`，程序接管鼠标时也是链接优先；双击链接选整条；输出改掉链接所在行时悬停跟着更新。OSC 52 三种策略：关（默认，全丢）、只写（问宿主，默认允许）、读写（读要宿主显式同意）。段末编译一次，只跑 4a–4c 的 suite。

---

### Task 10: 链接悬停与激活

**Files:**
- Modify: `source/tyControls.Terminal.pas`

- [ ] **Step 1: 属性与查找**：published `DetectUrls`（True）、`AllowNonHttpLinks`（False，开工前问题一第 2 条）、事件 `OnLinkActivate`。受保护 `LinkAt(ACol, AViewRow, out ALink): Boolean` = `TyTermFindLinkAt(FCore.Buffer, FCore.Links, ACol, YDisp + AViewRow, Cols, DetectUrls, AllowNonHttpLinks, ALink)`。链接键：`LinkKeyHeld(Shift)` = macOS 标志时 `ssMeta`，否则 `ssCtrl`。

- [ ] **Step 2: 悬停**：字段 `FHover: TTyTermLink`、`FHoverValid`、`FLastMousePos`、`FMouseInside`。`UpdateHover(X, Y, Shift)`：指针在网格内、`LinkKeyHeld`、不在 `mrSelect` 路上 → `LinkAt(CellAt(X, Y))`；和原来的不同（`linkEquals`：文本与范围）→ 旧的和新的范围所在视口行标脏、换掉；否则清掉（同样标脏）。调用点：`MouseMove`（在路由之后）、`MouseEnter` / `MouseLeave`（离开清掉）、`KeyDown` / `KeyUp` 里 `Key` 是 `VK_CONTROL`（macOS 标志下 `VK_LWIN` / `VK_RWIN`，LCL-Cocoa 把 Cmd 报成它们）时用 `FLastMousePos` 和这次的 `Shift` 重算——在 3 期的 `KeyDown` 逻辑之前做，不改变按键的去向（这些键本来就没有编码、不吞）。`EndDrive` 末尾：有悬停且这次解析动过它的行（脏行和悬停范围相交）或滚过 → 在 `FLastMousePos` 重算（上游 `onRenderedViewportChange` 那段，`Linkifier.ts:282-298`）。光标形状在 4b 的 `UpdatePointer` 里读 `FHoverValid`。

- [ ] **Step 3: 画**：`RenderTo` 按行设 `LinkFrom / LinkTo`：悬停范围（1 起、闭区间、绝对行）落在这一视口行上的那一段 → `[起列 − 1, 止列)`（首行从 `StartX − 1`，末行到 `EndX`，中间行整行）；`LinkColor` = `TyTerminalLink` 的 `color`（4b Task 7 已取好）。

- [ ] **Step 4: 激活**（`mrLink` 路）：`MouseDown` 时 `LinkKeyHeld` 且 `LinkAt` 命中 → 路是 `mrLink`、记下 `FDownLink`，**不上报、不选择**（程序接管鼠标时也一样，spec §9.8）；`MouseUp`（同一个键）时在抬起位置再 `LinkAt`，与 `FDownLink` `linkEquals` → `OnLinkActivate(Self, 链接.Text, 链接.Source = tlsOsc8)`（上游 `Linkifier.ts:220-233`）。控件自己不打开任何东西。没按链接键、或指针下没有链接 → 照 4b 的表走。

- [ ] **Step 5: 双击选整条**（开工前问题一第 6 条）：4b Task 6 的 `Press` 在双击时传 `LinkAt` 的范围（不看链接键，受 `DetectUrls` / `AllowNonHttpLinks` 控制），macOS 右键选词同样传。

- [ ] **Step 6: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.pas && git commit -m "feat(terminal): Ctrl+click a link, and the host decides what to open

With Ctrl held (Cmd on macOS) the link under the pointer -- an OSC 8
hyperlink, or a web address the terminal recognises -- is underlined
and the pointer becomes a hand; pressing and releasing on the same link
raises OnLinkActivate, even when a program has the mouse. Nothing is
opened by the control. A double click on a link selects all of it, as
xterm.js does, and the underline follows output that rewrites the line.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: OSC 52

**Files:**
- Modify: `source/tyControls.Terminal.pas`

- [ ] **Step 1: 注册**：构造里 `FCore.Parser.RegisterOscHandler(52, TTyTerminalOscStringHandler.Create(@HandleOsc52))`——所有权与 Core 注册自己的处理器相同（先核对 Core 构造里那几行与 `Parser.pas` 的 `RegisterOscHandler`，照同样的方式交给解析器；不重复释放）。核对 `Core.Reset` 之后处理器还在（Task 12 有测试）；若 `Reset` 会清掉解析器的处理器，就在 `CoreBufferActivate` 之外另找 `Reset` 的收尾点重新注册，并在提交说明里写明。

- [ ] **Step 2: `HandleOsc52(const AData: string): Boolean`**：一律答 True（处理了，不进 `OnOsc`）。
  - `Osc52 = to52Off` → 什么都不做。
  - `TyTermOsc52Split` 为假 → 什么都不做（上游 `args.length < 2`）。
  - `Pd = '?'`：只在 `to52ReadWrite` 时：`text := ReadClipboardText`、`allow := False`、`OnOsc52(Self, False, Pc, text, allow)`（没挂事件就是不允许）；`allow` → `FCore.Input(TyTermOsc52Reply(Pc, text), False)`（不是用户输入，不清选区、不滚到底）。
  - 否则（写）：`to52Write` 或 `to52ReadWrite`：`text := TyTermOsc52Decode(Pd)`、`allow := True`、`OnOsc52(Self, True, Pc, text, allow)`；`allow` → `WriteClipboardText(text)`。
  - 事件是同步的、在解析中间（开工前问题二第 15 条）；接口注释写明「宿主可以在这里弹模态框」。`Pc` 原样交宿主，控件不按它选剪贴板（上游同样不看）。

- [ ] **Step 3: published `Osc52`（`to52Off`）、事件 `OnOsc52`；提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.pas && git commit -m "feat(terminal): OSC 52 clipboard access, off unless the host allows it

Off by default: requests are dropped. With Osc52 = to52Write a program
may set the clipboard, after OnOsc52 lets the host see, change or
refuse the text; with to52ReadWrite it may also read it, but only when
the host says yes. Arguments and base64 are handled as xterm.js's
clipboard addon handles them; the answer is not user input.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: 链接与 OSC 52 的测试

**Files:**
- Create: `tests/test.terminal.view.links.pas`（suite `TTyTerminalViewLinkTests`）
- Modify: `tests/test.terminal.view.pas`（探针加 `Hover: TTyTermLink` / `HoverOn`、`KeyUpNow`）、`tests/test.terminal.view.paint.pas`（链接下划线像素）、`tests/tytests.lpr`

OSC 8 的写法同 4a Task 1：`#27']8;;<uri>'#27'\<文本>'#27']8;;'#27'\'`。链接事件记 `(Uri, FromOsc8)` 列表。

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestCtrlHoverFindsAWebAddress` | 写 `see https://example.com now`；不按 Ctrl 移到 `example` 上 → 没有悬停；`[ssCtrl]` 移到同一处 → 悬停，文本 `https://example.com`，范围 `(5,1)-(23,1)` 映射到控件的绝对行 | H1：悬停不看链接键 |
| `TestTheModifierKeyAloneTogglesTheHover` | 指针停在网址上，不动：`KeyDown(VK_CONTROL, [ssCtrl])` → 悬停；`KeyUp(VK_CONTROL, [])` → 没有；`OnData` 始终为空 | H2：按键时不重算 |
| `TestCmdOnTheMac` | macOS 标志：`[ssCtrl]` 不悬停，`[ssMeta]` 悬停 | H3：macOS 仍用 Ctrl |
| `TestAHandPointer` | 悬停时 `LastTempCursor = crHandPoint`；离开网址 → `crIBeam` | H4：悬停不改光标 |
| `TestCtrlClickActivates` | Ctrl 在网址上按下、抬起 → 一次 `('https://example.com', False)`；OSC 8 的 `https://example.org` → `(…, True)`；按下后移出链接再抬起 → 没有事件 | H5：按下时就发（移出后仍有事件）；H6：`FromOsc8` 反了 |
| `TestALinkWinsOverTheProgram` | `CSI ? 1000 h CSI ? 1006 h`：Ctrl+单击网址 → 链接事件、没有 `OnData`；Ctrl+单击空白处 → 上报（码 16） | H7：上报优先于链接 |
| `TestDetectUrlsOff` | `DetectUrls := False`：网址 Ctrl+悬停 → 没有；OSC 8 仍有 | H8：`DetectUrls` 没传给查找 |
| `TestNonHttpOsc8Links` | OSC 8 `file:///tmp/a` → 默认不是链接；`AllowNonHttpLinks := True` → 是，激活拿到 `file:///tmp/a` 原样 | H9：`AllowNonHttpLinks` 没传 |
| `TestADoubleClickSelectsTheWholeLink` | `(see http://a.com/x?y=1)`：在 `x` 上双击（不按 Ctrl）→ `SelectionText = 'http://a.com/x?y=1'` | H10：双击不传链接（只选出 `x?y=1` 之类） |
| `TestTheHoverFollowsNewOutput` | 悬停在网址上，程序 `CR` + `plain text` + `CSI K` 盖掉这一行 → 悬停清掉（解析后按上次的指针位置重算） | H11：`EndDrive` 不重算 |
| `TestLinksAreNotOpenedByTheControl` | 没挂 `OnLinkActivate` 时 Ctrl+单击 → 不抛、没有 `OnData`、没有选区 | — |
| `TestOsc52OffDropsEverything` | 默认策略：`ESC]52;c;aGVsbG8=BEL`、`ESC]52;c;?BEL` → 剪贴板桩没被读写、没有 `OnData`、`OnOsc52` 没被调、`OnOsc` 也没收到 52 | O4：关着时交给 `OnOsc` |
| `TestOsc52WriteAsksTheHost` | `to52Write`：写 → 事件 `(True, 'c', 'hello', allow = True)`、剪贴板 `hello`；宿主把 `AAllow` 设 False → 不写；宿主改 `AText := 'x'` → 写 `x`；读请求 → 不调事件、没有应答 | O5：写的 `AAllow` 默认 False |
| `TestOsc52ReadNeedsConsent` | `to52ReadWrite`、剪贴板桩 `hi`：读 → 事件 `(False, 'c', 'hi', allow = False)`、没有应答；宿主允许 → `OnData = ESC ]52;c;aGk= BEL`；没挂事件 → 没有应答；有选区时应答不清选区 | O6：读的 `AAllow` 默认 True；O7：应答当用户输入发（选区被清） |
| `TestOsc52SurvivesAReset` | `Reset` 后 `to52Write` 写 → 剪贴板照写 | O8：`Reset` 后处理器丢了 |

**`TTyTerminalViewPaintTests` 加的**：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestAHoveredLinkIsUnderlined` | 网址悬停后渲染：网址的每一格在 `UnderlineY` 那 `LineW` 行上是 `TyTerminalLink` 的颜色，网址前后的格子那一行是底色；松开 Ctrl 再渲染 → 那一行回到底色 | H12：链接段没设给行绘制器 |
| `TestAWrappedLinkIsUnderlinedOnBothRows` | 20 列里一个折两行的网址：两行各自的那一段都有下划线 | H13：只画悬停行 |

- [ ] **Step 1: 写测试单元、改探针、加进 `tytests.lpr`**
- [ ] **Step 2: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add tests/test.terminal.view.links.pas tests/test.terminal.view.pas tests/test.terminal.view.paint.pas tests/tytests.lpr && git commit -m "test(terminal): link hover and activation, OSC 52 policies

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 3: 段 4c 编译并跑本段 suite**（主文件「跑测试的固定套路」4c 行）。只修本段的红。
