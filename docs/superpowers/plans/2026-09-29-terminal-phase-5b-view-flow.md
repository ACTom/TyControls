# 终端控件 5 期 · 5b 控件接上折行、流量控制余项（Task 5–6）

> 本文件是 [`2026-09-29-terminal-phase-5.md`](2026-09-29-terminal-phase-5.md) 的附录，执行方式、核实记录、开工前问题、接口清单、地雷都在主文件。先读主文件，尤其是核实记录 11–13、28，开工前问题一第 2 条、问题二第 6–8 条，地雷 13、16。

**这一批做完能看到什么**：控件里拖窗口宽度，长行折回、缩回来复原；选区按开工前问题一第 2 条的结论处理；悬停的链接随改尺寸清掉；滚动条随折行后的行数；网址回映射和上游一致（不再按网格宽度截）。写入队列把一次很大的 `Write` 按 128 KB 的段切进多片，回调顺序、异常、改尺寸、丢弃在切片下都对；控件侧有走真消息循环的回调顺序测试。段末编译一次，只跑 5b 的 suite。

---

### Task 5: 控件接上折行：选区、悬停、滚动条、网址回映射

**Files:**
- Modify: `source/tyControls.Terminal.Links.pas`（删 `ACols`）、`source/tyControls.Terminal.View.Links.inc`、`source/tyControls.Terminal.pas`（`CoreResize`）、`source/tyControls.Terminal.View.Selection.inc`
- Modify: `tests/test.terminal.links.pas`、`tests/test.terminal.view.pas`、`tests/test.terminal.view.links.pas`、`tests/test.terminal.view.paint.pas`

- [ ] **Step 1: 删 `ACols`**（开工前问题二第 6 条）：`TyTermComputeUrlLinks(ABuffer, AY)`；`MapStrIdx` 去掉 `ACols` 参数与那两行截断，按 `line.Length` 走（`WebLinkProvider.ts:171`）；`TyTermFindLinkAt` 调它时不再传列数（`TyTermFindLinkAt` 自己的 `ACols` 留着——去重叠与命中判定按网格列数算，上游同样，`Linkifier.ts:153-173`、`:370-375`）。单元头与接口注释里「phase 5」那段删掉，换成一句：行比网格长时（不折行的缓冲）按行的全长映射，同上游。测试里的调用点跟着改。
- [ ] **Step 2: 改尺寸清悬停**（开工前问题二第 7 条）：`CoreResize` 里悬停有效就先 `DirtyLinkRows(FHoverLink)`、再 `FHoverValid := False`（照 `Linkifier.ts:47-50` 的 `_clearCurrentLink`）；指针下次移动时 `UpdateHover` 重新找。
- [ ] **Step 3: 改列数后的选区**（开工前问题一第 2 条；下面按建议写，用户选了「照上游」就只做第 3 小点）：
  1. 控件记 `FSelCols`（同 `FSelRows` 的做法，构造和 `CoreResize` 里维护）。
  2. `CoreResize`：列数变了、且 `FCore.Buffer.IsReflowEnabled`（当前缓冲这次会折行）→ `ClearSelection`（它发 `OnSelectionChange`）；行数变了照旧清。注释写明：上游改列数不清（`SelectionService.ts:158-162`），字挪了以后选区会框着别的字；我们在真的重新折行时清掉（spec §15）。
  3. 不清的路径（老 ConPTY、备用屏、「照上游」）：`TrimmedLines` 已经包含折行挤出的行，`SyncSelectionTrim` 照常把选区上移，不用另写。
- [ ] **Step 4: 滚动条与视口**：`CoreResize` 已经 `SyncScrollBar`；核对折行改了 `YDisp` / `YBase` 之后，拇指位置和 `Max = 行数 − 视口行数`（[[scrollbar-max-is-position-not-content]]）都跟着对——不对就在 `CoreResize` 里补，不在别处补。
- [ ] **Step 5: 找出钉着「不折行」的旧控件测试**：跑一次 `TTyTerminalViewTests TTyTerminalViewPaintTests TTyTerminalViewMouseTests TTyTerminalViewLinkTests TTyTerminalViewInputTests TTyTerminalExampleTests`（本任务写完先编一次，5b 段末还会整段再跑），红了的逐个判断：如果它断言的是改列数后的缓冲内容 / 行数 / 网址范围，新答案要能从一个同样喂字节、同样改尺寸的裸 Core 得到（裸 Core 已由 Task 4 对上游证明）；按新答案改测试，提交说明写「pinned the no-reflow answer」（地雷 16）。和折行无关的红停下查。
- [ ] **Step 6: 测试**（判据）

**`TTyTerminalLinksOracleTests`**：Task 2 加的老 ConPTY 那例（5a 段末留着的红）现在必须绿。

**`TTyTerminalViewTests`**：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestTheViewRewrapsLikeTheCore` | 控件（探针窗体、默认 `WindowsPty`）写入一段含 170 字长行、CJK、表情的文本；用 `SizeForGrid` 把客户区改到 40 列、再改回 80 列、再到 23 列。每一步控件的 `Core` 与一个裸 Core（同样字节、同样依次 `Resize`）逐行比 `TranslateToString(False)`、`IsWrapped`、光标、`YBase` / `YDisp` | V6：控件在 `UpdateGrid` 里把 `WindowsPty` 当成 `{conpty, 19044}`（任何让控件不折行的接线错误） |
| `TestAReflowingResizeClearsTheSelection` | 选中长行的一段；改列数 → `HasSelection = False`、`OnSelectionChange` 恰好一次；同样操作在 `Core.WindowsPty := (twpConPty, 19044)` 下 → 选区还在、坐标不变；只改行数 → 清（已有规则） | V2：列数一变就清、不看折行开关（老 ConPTY 那半红）；V3：不清（默认那半红） |
| `TestTheSelectionFollowsATrimByReflow` | 老 ConPTY 以外、选区没被清的路径没有；这一条走「照上游」时才有意义——**用户选了「照上游」才写**：滚回满、选中滚回里一段，变窄挤出 2 行 → 选区上移 2 行（与 `terminal-selection` 夹具 `reflow-trim-shifts` 相同） | —（按答复二选一） |
| `TestTheScrollBarFollowsReflow` | 滚回里有 30 行 200 字的长行（80 列）；改到 40 列 → 滚动条 `Max = Core.Buffer.Lines.Length − Rows`、`Position = YDisp`；再改回 80 列同样成立 | V4：`CoreResize` 不同步滚动条 |

**`TTyTerminalViewLinkTests`**：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestAResizeDropsTheHover` | 按着 Ctrl 悬停一条折了行的网址（`HoverValid`）；改列数 → `HoverValid = False`，旧链接占的视口行被标脏（探针读脏行）；指针再动一下 → 按新位置重新悬停，范围与 `TyTermFindLinkAt` 在新缓冲上的答案相同 | V1：`CoreResize` 不清悬停 |
| `TestALongLineUnderAnOldConPtyMapsAsUpstream` | `WindowsPty = {conpty, 19044}`，80 列写一条 120 字的网址后改到 40 列（行比网格长）；`LinkAt` 的范围 = 夹具里上游那一例的答案 | V5：恢复按网格宽度截（`MapStrIdx` 里 `n := Min(n, cols)`） |

**`TTyTerminalViewPaintTests`**：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestAReflowRepaintsEveryRow` | 改列数后下一帧 `RowsPainted` 增量 = 行数（全部重画），且网格区每一行的有墨列范围与新缓冲的内容一致（有字的格有墨、空格子无墨，按 3 期「只数有没有墨」的做法） | V7：`CoreResize` 不置 `FAllDirty` |

- [ ] **Step 7: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Links.pas source/tyControls.Terminal.View.Links.inc source/tyControls.Terminal.pas source/tyControls.Terminal.View.Selection.inc tests/test.terminal.links.pas tests/test.terminal.view.pas tests/test.terminal.view.links.pas tests/test.terminal.view.paint.pas && git commit -m "feat(terminal): the view follows a rewrapped buffer

A resize drops the hovered link as xterm.js's linkifier does, and clears
the selection when the buffer actually rewraps, since its cells then hold
other text. Web addresses on a line longer than the grid map back over
the whole line again, as upstream does; the cut to the grid width was a
stand-in for reflow.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 流量控制余项：块内切片与控件侧的回调顺序

**Files:**
- Modify: `source/tyControls.Terminal.Core.pas`（`FChunkPos`、`HeadChunkParsed`）、`source/tyControls.Terminal.Core.WriteQueue.inc`、`source/tyControls.Terminal.Core.InputHandler.inc`（按范围解析）
- Modify: `tests/test.terminal.core.pas`（`TTyTerminalWriteQueueTests`、`TTyTerminalReentryTests`）、`tests/test.terminal.view.pas`

**还没做的流量控制**（spec §3、§12.3，4 期签收交接第 4 条）：示例的高低水位 4 期已做；本期剩下（1）一个块在一片里整块解析完才让出（2 期修正「块内切片是 5 期的事」）；（2）控件侧的 `Write` 回调顺序测试（Core 侧已有 `TestCallbacksRunInOrder` 等）；（3）文档写清宿主怎么做流控、释放控件时没处理的块不回调（Task 13）。

- [ ] **Step 1: 按范围解析**：`Parse(const AData: RawByteString)` 拆出 `ParseRange(const AData: RawByteString; AStart, ACount: Integer)`（`Parse` = 整串的一次 `ParseRange`）。一次 `ParseRange` = 上游的一次 `parse` 调用：开头记光标、`ClearRange`，结尾 `OnCursorMove` / `OnRefreshRows` 照旧。解码器的半截序列跨调用保留（本来就跨块保留）。
- [ ] **Step 2: 块内位置**（开工前问题二第 8 条）：`FChunkPos` = 队首块已解析的字节数。`ProcessOneChunk` 改成「处理队首块的下一段或到底」：
  1. 这一段 `n := Min(TyTermMaxParseBuffer, 块长 − FChunkPos)`；**先**推进 `FChunkPos` 与 `Dec(FPendingData, n)`，再 `ParseRange`（和现在「先推进再解析」同一个道理：异常或嵌套的清空都不会把同一段解析两遍）。
  2. `FChunkPos` 到了块尾：块出队（`Inc(FBufferOffset)`、`FChunkPos := 0`、放掉数据），调回调，`RunDeferred`——和现在的结尾一样。
  3. 某段里处理器抛异常：这一块剩下的算已处理（`Dec(FPendingData, 剩余)`、出队），回调照调（`finally`），异常照旧往外抛。
  4. `InnerWrite` 在**段与段之间**查预算（`NowMs − start >= ABudgetMs` 就停），块没完也停；`AMore` = 队里还有没处理完的块（含半块）。
  5. `FlushSync` 从 `FChunkPos` 接着把队列清完；`WriteSync`、`Resize` 前的清空都经它。
  6. `ClearQueue` / `DiscardPending` / 析构：`FChunkPos := 0`，半块连同后面的一起丢，不调回调。
  7. 处理器里延后的 `Resize` / `Reset` / `WriteSync`（spec §3.1 的重入规则）仍在**整块**的回调之后执行，不在段与段之间执行（地雷 13）；`ProcessPending` 在半块时返回 True，控件照常排下一片。
  8. 单元头「splitting inside a chunk is phase 5」改掉；§15 的偏离写进单元头的 WHAT DIFFERS 一节：上游整块一次解析（`WriteBuffer.ts:224-297`）。
- [ ] **Step 3: 测试**（判据）

**`TTyTerminalWriteQueueTests`**（`TestOneBigChunkIsNotSplit` 钉着旧行为，删掉，换成下面第一条；提交说明写明）：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestABigChunkIsSlicedBetweenPieces` | 注入时钟：每读一次加 5 ms。`Write` 1 MB（8 段）带回调；`ProcessPending(12)` → 返回 True、`HeadChunkParsed = 3 × 131072`（起点读一次、每段后读一次：5、10、15 ≥ 12 停）、回调没调、`PendingBytes = 1 MB − 3 × 131072`、`OnRefreshRows` 3 次；再调到返回 False：回调恰好一次、在最后一段之后 | F1：只在块与块之间查预算（一片就整块）；F2：每段都调回调；F3：`PendingBytes` 在块开头一次减完 |
| `TestSlicedEqualsWhole` | `terminal-core-recording.json` 里每份录制的全部字节当一块写入，用「每读一次加 20 ms」的时钟逐片处理完；与另一个 Core 整块 `WriteSync` 的结果按 `TyTermCompareState` 比（除 `renders` / `cursorMoves` 计数，理由同 2 期的切块变体）——全等 | F8：段与段之间重置解码器（半截 UTF-8 丢了） |
| `TestResizeMidChunkParsesTheRestFirst` | 1 MB 块处理了 3 段后 `Core.Resize(40, 10)`：剩下的 5 段先按旧尺寸解析、回调一次、然后改尺寸；结果与「整块 `WriteSync` 再 `Resize`」的 Core 全等 | F4：清空时从块头重来（前 3 段解析两遍，状态不同） |
| `TestWriteSyncMidChunk` | 同上，把 `Resize` 换成 `WriteSync('x')` | F4 |
| `TestDiscardMidChunk` | 3 段之后 `DiscardPending`：回调不调、`PendingBytes = 0`、`HeadChunkParsed = 0`；再 `Write('abc')` 从头正常解析 | F5：`DiscardPending` 不清 `FChunkPos`（下一块从中间开始解析） |
| `TestAHandlerRaisingMidChunk` | 注册一个 CSI 处理器，在第 2 段里遇到时抛异常：异常冒出 `ProcessPending`；这一块回调恰好一次；第 3 段之后的字节不解析；队里的下一块下一片正常解析 | F7：异常后剩下的段下一片接着解析（与「这一块算已处理」相反） |

**`TTyTerminalReentryTests`**：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestAResizeFromAnEventWaitsForTheWholeChunk` | 第 1 段里有 OSC 0，`OnTitleChange` 里调 `Core.Resize(30, 8)`；第 1 片结束（半块）时 `Cols` 仍是旧值；整块处理完、回调之后 `Cols = 30`；回调里看到的 `Cols` 是旧值 | F6：段与段之间 `RunDeferred` |

**`TTyTerminalViewTests`**（控件侧，走真 `QueueAsyncCall` + `Application.ProcessMessages`，[[built-not-wired-is-the-default-failure]]）：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestWriteCallbacksComeInOrderThroughTheView` | 50 次 `View.Write`，大小 1 B 到 300 KB 不等，每块末尾一个 OSC 0 把标题设成自己的序号，`ATag` = 序号；泵消息直到 50 个回调都到。回调序号严格递增、各一次；每个回调里 `View.Title` = 它自己的序号（它的数据已全部解析、下一块还没开始） | F2；F9：控件的 `AsyncSlice` 里每片之后不再排下一片（回调到不齐，测试带 10 秒上限） |
| `TestAResizeInsideAViewCallback` | 第 3 个回调里改控件尺寸（`SetBounds` 到 `SizeForGrid(40, 10)`）；其余回调仍各一次、按序；最终 `Cols = 40` | —（守回归：回调里改尺寸会同步清空队列，顺序不能乱） |
| `TestAHugeWriteYieldsToTheMessageLoop` | `View.Write` 一次 20 MB（带回调），紧接着 `Application.QueueAsyncCall` 自己的一个标记调用；泵消息：标记调用执行时 `Core.PendingBytes > 0`（数据还没解析完，队列让出过）；最终回调恰好一次 | F1 |

- [ ] **Step 4: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Core.pas source/tyControls.Terminal.Core.WriteQueue.inc source/tyControls.Terminal.Core.InputHandler.inc tests/test.terminal.core.pas tests/test.terminal.view.pas && git commit -m "feat(terminal): one large write is parsed over several slices

The write queue now checks its time budget between the 128 KB pieces a
chunk is parsed in, not only between chunks, so a host that writes tens of
megabytes at once no longer freezes the window. A chunk's callback still
comes once, after its last piece; a flush, a resize or WriteSync goes on
from where the slice stopped, a discard drops the half-parsed chunk
without its callback, and calls made from events still wait for the whole
chunk. xterm.js parses a chunk in one go; this is a deliberate difference.
The view's callbacks are tested in order through the real message loop.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: 段 5b 编译并跑本段 suite**（主文件「跑测试的固定套路」5b 行）。只修本段的红；Task 5 Step 5 那类「钉着不折行」的旧测试按地雷 16 处理。
