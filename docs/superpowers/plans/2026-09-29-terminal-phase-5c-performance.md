# 终端控件 5 期 · 5c 性能：行复用、冷启动光栅化、测量与调优（Task 7–9）

> 本文件是 [`2026-09-29-terminal-phase-5.md`](2026-09-29-terminal-phase-5.md) 的附录，执行方式、核实记录、开工前问题、接口清单、地雷都在主文件。先读主文件，尤其是核实记录 22–28，开工前问题一第 1 条、问题二第 9、10、13–15 条，地雷 10–12、15、16。

**这一批做完能看到什么**：输出一行一行往上滚时，每帧只画新露出的行和光标离开的那一行，其余像素原样搬上去（增量画出来的表面与整屏重画逐字节相同）；Win32 上冷启动光栅化走终端自己的 GDI 路径，遮罩与库的文字管线逐位相同、快几倍（或按用户选择改了 `Painter.pas`）；吞吐、最长一片、内存、缓存命中有测试守着，`terminalbench` 的本期数字填进主文件。段末编译一次，只跑 5c 的 suite。

---

### Task 7: 行复用——整屏上滚只画新露出的行

**Files:**
- Modify: `source/tyControls.Terminal.Buffer.pas`（行的 `Serial` / `Revision`）
- Modify: `tools/terminal-oracle/gen-terminal-glyphs.js`；重新生成 `source/tyControls.Terminal.CustomGlyphs.inc`（图案纵向周期）
- Modify: `source/tyControls.Terminal.Render.pas`（`RowUsesYPhase`）、`source/tyControls.Terminal.pas`（行键、搬行、`CoreScroll`）
- Modify: `tests/test.terminal.buffer.pas`、`tests/test.terminal.view.paint.pas`

设计见开工前问题二第 9 条，坑见地雷 10、11。

- [ ] **Step 1: 行的 `Serial` 与 `Revision`**：`TTyTerminalLine` 加类计数器 `GNextSerial: Int64`，两个构造函数都取一个；私有 `Touch`（`Inc(FRevision)`，`inline`）。在**每个改内容的公开方法**里调一次：`SetCell`、`SetCellFromCodepoint`、`AddCodepointToCell`、`InsertCells`、`DeleteCells`、`ReplaceCells`、`Resize`（真的变了才算，和返回值无关——简单起见一律 `Touch`）、`Fill`、`CopyFrom`、`CopyCellsFrom`。`IsWrapped` 的 setter 不 `Touch`。再 grep 同一单元里其他类直接写 `TTyTerminalLine` 私有字段的地方（FPC 允许同单元访问私有字段：`\.FData\[`、`\.FLength`、`\.FCombined`、`\.FExtended`），每一处也要 `Touch` 或改走方法。接口注释写「纯查询；控件据此认出一行的像素没变（5 期）」。
- [ ] **Step 2: 图案纵向周期**：`gen-terminal-glyphs.js` 从数据里取所有 `pattern` 部件的行数，求最小公倍数，写成常量 `TyTermGlyphPatternPeriodY`（和现有常量同一处）；脚本断言它 ≤ 16。重跑脚本，`git diff` 只多这一个常量。
- [ ] **Step 3: 行绘制器报相位**：`PaintRow` 开头清 `FRowUsesYPhase`；画自绘字形时，`TyTermCustomGlyphPhase` 给出的 `APhaseY` 来自图案部件（它只在有图案部件时非零、也可能恰好为 0——所以按「这个码位有图案部件」判断，不按相位值）就置位。
- [ ] **Step 4: 控件的行键**（接口清单的 `TTyTermRowKey`）：
  1. `FRowKeys: array of TTyTermRowKey`，长度随行数；`FAllDirty`、表面重建、帧级参数（色表签名、度量 / 字体规格、`FHasFocus`、选区色、对比度、禁用预混）任何一个变了，全部作废（`Valid := False`）。
  2. 覆盖层 = 这一行的选区列段 `[SelFrom, SelTo)`、悬停链接列段、光标（列、形状；不显示时 −1）、组字串（在这一行时它的 UTF-8 串，否则空）——用记录直接比，不用哈希。
  3. `RenderTo` 里：先为每个视口行算新键（`Serial` / `Revision` 取 `buf.GetLine(YDisp + r)`；`nil` 行用 `Serial = 0`、`Revision = 0`）。然后：
     - 新键 = 这一行上一帧的键 → 不动；
     - 否则在上一帧的键里找 `Serial`、`Revision`、覆盖层都相同的行 `s`；找到、且（这一行上一帧没画相位字形，或 `((r − s) × 格高) mod TyTermGlyphPatternPeriodY = 0`）→ 记为「从 s 搬」；
     - 否则 → 记为「要画」。
     「从 s 搬」的源行先整体拷进一张草稿（按 `ScanLine[y]` 逐像素行拷，地雷 11），再逐个写到目标行；然后画「要画」的行。`PaintRow` 返回 False（光栅预算超了）的行，键作废（地雷 10 c）。
  4. 同步输出（2026）暂存中（`FSyncHolding`）：这一帧**不搬也不画**任何行（保持 3 期「攒着的一起画」的语义），只贴图。
  5. 画了或搬了、却不在这次画布裁剪区里的行，`InvalidateRows` 补一次（多一次贴图，不会漏到屏幕上）。
  6. `CoreScroll` 与 `EndDrive` 里的滚动：不再 `DirtyAll`，改成失效网格区（让下一次 `Paint` 贴整块网格）；`FAllDirty` 只留给帧级变化。
  7. 给测试的 `RowsMovedLastFrame`、`RowsPaintedLastFrame`、`ForgetPaintedRows`（接口清单）。
- [ ] **Step 5: 测试**（判据）

**`TTyTerminalBufferTests`**：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestEveryMutationBumpsTheRevision` | 对一行逐个调 Step 1 列出的每个方法，每次之后 `Revision` 都变了；`IsWrapped := True` 之后不变；`Recycle` 之后 `CopyFrom` 的那一行变了 | W1：去掉 `SetCellFromCodepoint` 里的 `Touch`（逐个方法各做一次，表里只列这一条代表） |
| `TestSerialsAreNeverReused` | 循环 10000 次「建一行、记 `Serial`、释放」：`Serial` 严格递增、全不相同（地址会被复用，[[assertsame-freed-pointer-trap]]） | W9：`Serial` 取对象地址 |

**`TTyTerminalViewPaintTests`**：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestIncrementalEqualsFullRepaint` | 探针控件（真父窗体、哨兵底色、自建 controller），`LineHeightPercent = 113`（让格高是奇数）、144 PPI 各跑一遍。种子化脚本 200 步，每步随机取一种：写文字（ASCII、CJK、表情、`░▒▓` 连片、SGR、反显）、`DECSTBM` + 换行滚动区域、`CSI S` / `CSI T`、`IL` / `DL`、`ED 2`、进出 `?1049h`、大 REP、`ScrollLines(±k)`、`Select` / `ClearSelection`、按 Ctrl 悬停 / 放开、聚焦 / 失焦、闪烁相位翻转、`?2026h` / `?2026l`。每步之后：`RenderTo` 一次（增量），拷下网格区像素 A；`ForgetPaintedRows`；再 `RenderTo`，像素 B。A 与 B 逐字节相等；失败打印种子、步号、行号、第一个不同的像素 | W2：键里不含 `Revision`；W3：键里不含覆盖层；W4：不看相位规则（奇数格高下的阴影行红）；W5：预算超了的行键照样有效（这一条把光栅预算调到 0.01 ms、时钟每读一次加 1 ms）；W6：搬行不经草稿、原地拷（向下搬时覆盖源行） |
| `TestScrollingPaintsOnlyWhatChanged` | 写满一屏后 20 次「`WriteSync('line n' + CRLF)` + `RenderTo`」：每帧 `RowsPaintedLastFrame ≤ 3`（新露出的底行、光标离开的那一行，余量一行）、`RowsMovedLastFrame ≥ Rows − 3` | W8：`CoreScroll` 仍然 `DirtyAll`（每帧画满一屏） |
| `TestAFrameChangeRepaintsEveryRow` | 聚焦 ↔ 失焦、换主题、改 `LetterSpacing` 各一次：下一帧 `RowsPaintedLastFrame = Rows` | W10：帧级参数里漏了 `FHasFocus`（选区两色不重画） |
| `TestSyncOutputStillHoldsRows` | 3 期已有的 `TestSyncOutputHoldsRowsBack` / `…TimesOut` / `…StartsAtTheFirstHeldRow` 原样要绿；另加：暂存期间因别的原因触发 `RenderTo`（比如 `Invalidate`），网格像素不变 | W7：暂存中照样按键画行 |
| `TestRowsChangedOutsideTheClipAreInvalidated` | 探针覆盖 `InvalidateRows` 记下参数；只失效第 0–9 行后调 `RenderTo`（画布裁剪区 = 这 10 行），第 50 行的内容此前被改过：`RenderTo` 之后记录里有第 50 行 | W11：去掉 Step 4 第 5 小点 |

3、4 期里断言「滚动后整屏重画」「`RowsPainted` 增量 = 行数」的旧测试，按地雷 16 改成本期的判据（行数来自上面的规则），提交说明写明。

- [ ] **Step 6: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Buffer.pas tools/terminal-oracle/gen-terminal-glyphs.js source/tyControls.Terminal.CustomGlyphs.inc source/tyControls.Terminal.Render.pas source/tyControls.Terminal.pas tests/test.terminal.buffer.pas tests/test.terminal.view.paint.pas && git commit -m "perf(terminal): rows whose pixels did not change are moved, not repainted

Each line carries a serial that is never reused and a revision bumped by
every change to its cells. The view keys every painted row by the line's
serial and revision and by what lies over it -- selection, hovered link,
cursor, marked text -- and moves a row it finds elsewhere on screen
instead of painting it again; shaded glyphs move only by whole pattern
periods. Scrolling a line now paints the new bottom row and the one the
cursor left. Synchronized output still holds every row back.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 冷启动光栅化——终端自己的 Win32 路径（开工前问题一第 1 条选 B 时）

**Files:**
- Modify: `source/tyControls.Terminal.Render.pas`
- Modify: `tests/test.terminal.render.pas`

做法见开工前问题二第 10 条，坑见地雷 12。只在 `{$IFDEF LCLWin32}` 下；别的 widgetset 编出来和现在一样。

- [ ] **Step 1: `TTyTermGdiGlyphRenderer = class(TLCLFontRenderer)`**（`bgra:bgratext.pas:125`；`uses` 加 `BGRAText`、`LCLIntf`、`LCLType`）：
  1. `UpdateFont` 覆盖：`inherited`（名字、样式、高度、质量照 `TBGRASystemFontRenderer.UpdateFont`，`bgratext.pas:1437-1466`），再 `FFont.Quality := fqCleartypeNatural`（照 `Painter.pas:1263-1269`）。
  2. 一张常驻 `TBitmap`（`pf24bit`，[[opaque-device-cache-pf24bit]]；只长不缩），一个给测试的计数 `BitmapsCreated`。
  3. `RasterizeCoverage`：照 `Painter.pas:1271-1360` 的每一步——同一个量尺寸的调用与样式、`ox` / `oy` 的「加 0.5 取整」、`mx` / `my` 边距、白底、`SetBkMode(TRANSPARENT)`、`SetTextColor(0)`、`DrawText` 的标志（`DT_SINGLELINE or DT_NOCLIP or DT_NOPREFIX`，不从右到左）；然后直接读位图的扫描线，每像素 `cov := 255 − (r + g + b) div 3`。
  4. **复现旧遮罩**：旧路径把 `cov` 当 alpha 在白底 BGRA 草稿上 `FastBlendPixel` 黑色，光栅器再取 `255 − 灰度均值`（`Render.pas:776-786`）。单元初始化时用 `FastBlendPixelInline`（`bgra:bgrablend.pas:50`）对一个白像素、alpha 0..255 各算一次，得到 256 项表 `GLegacyCoverage[cov]`；新路径的遮罩值 = `GLegacyCoverage[cov]`。不自己推公式——用 BGRA 自己的函数算表，舍入必然一致。
  5. 旧路径还把 `ox − mx + px` 的像素按草稿的裁剪区裁掉；新路径按「光栅器取的是草稿里 `[pad, pad + CellH)` 行、`[0, w)` 列」直接算出落在这个窗口里的像素，窗口外的丢掉。
- [ ] **Step 2: 光栅器接上**：`TTyTermGlyphRasterizer` 在 Win32 上持有一个 `TTyTermGdiGlyphRenderer`；`Configure` 在给草稿 `TyConfigureTextFont` 之后，把草稿的 `FontName`、`FontEmHeight`、`FontStyle`（含斜体）、`FontQuality` 原样抄给它（它的 `UpdateFont` 由此算出和草稿同一个 `FFont`）。`Rasterize` 里 `TextSize` 照旧问草稿（`adv`），画字那一步换成 `RasterizeCoverage`。`UseLibraryPath = True` 时走旧的 `tmp.TextOut`（给对照测试）。
- [ ] **Step 3: 度量要不要一起挪**：看主文件「基线数字」里 Task 1 拆出的 `TextSize` 占比。≥ 30% 就在同一个 DC 上用 `DrawText(…, DT_CALCRECT)` 量，并加一条测试：每个对照字形新旧两边的 `adv` 相等；< 30% 不挪，签收记录写一句。
- [ ] **Step 4: 测试**（判据；非 Win32 构建上这几条 `Ignore('Win32 only')`）

**`TTyTerminalRenderTests`**：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestTheOwnRasterPathMatchesTheLibrarys` | 字形集：95 个可打印 ASCII × 常规 / 粗 / 斜 / 粗斜，96 与 144 PPI，另加 40 个 CJK、10 个韩文、5 个表情、5 个组合簇（`e` + U+0301 等）。每个字形 `UseLibraryPath` 真假各光栅化一次：遮罩的宽、高、`OffsetX` / `OffsetY`、每个字节都相等；失败打印字形、PPI、样式、第一个不同的位置 | G1：不查 `GLegacyCoverage`、直接用 `cov`；G2：质量用 `fqCleartype`（不是 Natural）；G3：`DrawText` 不带 `DT_NOPREFIX`（`&` 那个字形红） |
| `TestTheOwnRasterPathKeepsOneBitmap` | 光栅化上面全部字形后 `BitmapsCreated ≤ 2`（首次 + 至多一次长大） | G4：每个字形新建位图 |
| `TestTheOwnRasterPathIsFaster` | 同一次运行里冷光栅化 380 个 ASCII 字形：新路径耗时 ≤ 旧路径的 1/2（相对量，开工前问题二第 14 条；计时前换回墙上时钟） | G4（若 G4 在本条存活——位图创建不是大头——记下，`KeepsOneBitmap` 已经守住它） |

- [ ] **Step 5: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Render.pas tests/test.terminal.render.pas && git commit -m "perf(terminal): glyphs are rasterized on one kept GDI bitmap on Windows

The terminal draws a new glyph with the same font, quality and DrawText
call as the library's Windows text path, but on a bitmap it keeps, and
reads the coverage straight off it instead of converting a fresh bitmap
per glyph. The coverage is folded through a table built from BGRA's own
blend, so every mask is the one the library path produced, byte for byte.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 8A（只在用户选了 A 时做，代替 Task 8）：改 `Painter.pas` 的 `TTyGdiTextRenderer`

**Files:**
- Modify: `source/tyControls.Painter.pas`（共享文件，**用户已同意**才动）
- Modify: `tests/test.painter.pas`（`TPainterTest` 所在单元）

- [ ] **Step 1**：`TTyGdiTextRenderer` 加一个常驻 `TBitmap`（`pf24bit`，只长不缩，析构释放）；`InternalTextOutAngle` 复用它（每次按需 `SetSize` 变大、只清要用的矩形）；不再 `TBGRABitmap.Create(tmp)`，直接读 `TBitmap` 的扫描线算覆盖率，其余（量尺寸、位置取整、`DrawText`、`FastBlendPixel`）一字不改。
- [ ] **Step 2: 测试**：`TPainterTest` 加 `TestTheGdiRendererKeepsOneBitmap`（画 200 段文字后创建的位图数 ≤ 2，计数是给测试的类变量）；全库文字像素测试（全量里的 `TPainterTest`、各控件的 golden）不许有变化——Task 14 的全量就是判据。变异 G5：每次新建位图（`KeepsOneBitmap` 红）；G6：读扫描线时 R、B 通道写反（golden 红）。
- [ ] **Step 3: 提交** `perf(painter): the Windows text renderer keeps one bitmap`（正文说明：全库的首帧文字都受益；像素不变），结尾 Co-Authored-By 行。终端的光栅器不改。

---

### Task 9: 性能测试、缓存统计与调优

**Files:**
- Modify: `source/tyControls.Terminal.Render.pas`（`Evictions`）
- 有条件：`source/tyControls.Terminal.pas`（改尺寸合并，Step 2）
- Create: `tests/test.terminal.perf.pas`（suite `TTyTerminalPerfTests`）
- Modify: `tests/tytests.lpr`、`tools/terminal-bench/terminalbench.lpr`、主文件「基线数字」（本期列）

- [ ] **Step 1: 淘汰计数**：`TTyTermGlyphCache.MakeRoom` 每淘汰一项 `Inc(FEvictions)`；`Clear` 不清计数（计数是累计的统计量），另给 `ResetStats`。
- [ ] **Step 2: 改尺寸合并**（开工前问题二第 13 条）：跑 `terminalbench --reflow`。**每次 > 50 ms** 才做：`UpdateGrid` 算出的新格子数先记在 `FPendingGrid`、`QueueAsyncCall` 一次（已排着就只更新尺寸），异步回调里才 `Core.Resize` + `OnGridResize`；排着的期间 `RenderTo` 仍按 Core 的旧格子画、网格外补底色；查询度量的入口（`CellAt`、`CellRect`、`SizeForGrid`）先把排着的应用掉（它们要的是新格子）。测试 `TestResizesCoalesceToTheLast`：不泵消息连续 10 次 `SetBounds`，`OnGridResize` 0 次；泵一次后恰好 1 次、尺寸是最后那次的；中途调 `CellAt` 会先应用（`Cols` 变成新值）。变异 B4：每次 `SetBounds` 都当场 `Core.Resize`（计数 10 次红）。**≤ 50 ms 不做**，签收记录写数字与结论。
- [ ] **Step 3: 预算调优**：用 `terminalbench --flood` 与 `--slice` 各试 `TyTermWriteTimeoutMs` ∈ {8, 12, 16}、控件 `FrameMs` ∈ {16, 33}、光栅预算 ∈ {5, 10}；只有吞吐提升 ≥ 10% 且「两次绘制的最长间隔」不超过 50 ms 才改默认值（12 ms 是上游的值，改了进 §15）。结论与数字进签收记录；不改就写「维持」。
- [ ] **Step 4: 测试**（判据；计时类照开工前问题二第 14 条，计时前换回墙上时钟）

**`TTyTerminalPerfTests`**（新 suite）：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestAFloodKeepsMemoryFlat` | 控件在真父窗体上，20 MB（`terminalbench` 同一个生成器，CJK 从 6000 个不同码位里取）按 64 KB、4 块在途经 `View.Write` 喂，泵消息直到回调到齐：`TTyTerminalLine.LiveCount ≤ Rows + Scrollback + 4`；`GetFPCHeapStatus.CurrHeapUsed` 增量 ≤ 32 MB；字形缓存 `Count ≤ 4096` 且 `Evictions > 0`；回调恰好 320 次 | B1：环形表不按 `Scrollback` 挤掉（行数涨）；B2：字形缓存不淘汰（`Count` 超） |
| `TestTheCacheHitsOnceWarm` | `vim-edit.cast`、`htop-few-frames.cast` 各回放两遍（每遍后 `RenderTo`）：第二遍 `Misses` 的增量 = 0 | B3：码位键里混进每帧会变的东西（比如光标列） |
| `TestTheLongestSliceStaysNearTheBudget` | Core `Write` 20 MB 一块，`ProcessPending(12)` 循环到完：最长一次的耗时 ≤ 12 ms + 3 × 本次运行里单独量的一段（128 KB）解析耗时 | F1（块内切片退回整块） |
| `TestAFullRepaintIsNotSlower` | 200 × 60 满屏、热缓存，`ForgetPaintedRows` + `RenderTo` 的中位（20 次）≤ 30 ms（3 期 11.8 ms 的约 2.5 倍，宽裕上限；精确数字进 spec） | —（守回归，不做变异） |

- [ ] **Step 5: 基准本期数字**：`terminalbench` 的 `--flood` 加 `Evictions` 一列；跑 `--all`，把本期数字填进主文件「基线数字」表的本期列，对照目标标「过 / 没过」；没过的写原因（进 Task 14 的审查）。
- [ ] **Step 6: 提交**（不编译；`tytests.lpr` 的 uses 加 `test.terminal.perf`）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Render.pas source/tyControls.Terminal.pas tests/test.terminal.perf.pas tests/tytests.lpr tools/terminal-bench docs/superpowers/plans/2026-09-29-terminal-phase-5.md && git commit -m "test(terminal): memory, cache and slice guards; phase 5 numbers

A 20 MB flood through the view keeps the live lines and the heap flat and
the glyph cache bounded; a warm cache misses nothing on a second replay;
the longest slice of one huge write stays within the budget plus one
piece. The glyph cache counts evictions, and the benchmark's numbers
after phase 5 sit next to the baseline in the plan.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: 段 5c 编译并跑本段 suite**（主文件「跑测试的固定套路」5c 行）。`TTyTerminalPerfTests` 单跑后再连跑两次，三次都绿；只修本段的红。
