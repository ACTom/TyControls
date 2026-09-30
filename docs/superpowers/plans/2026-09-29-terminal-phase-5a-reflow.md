# 终端控件 5 期 · 5a 基准工具与重新折行（Task 1–4）

> 本文件是 [`2026-09-29-terminal-phase-5.md`](2026-09-29-terminal-phase-5.md) 的附录，执行方式、核实记录、开工前问题、接口清单、地雷都在主文件。先读主文件，尤其是核实记录 1–15，开工前问题一第 5 条、问题二第 1–5、15 条，地雷 1–6、16。

**这一批做完能看到什么**：`terminalbench` 量出改代码之前的数字；折行的两份新夹具与三处补充用例由上游代码生成；缓冲按上游规则开关折行，所有改列数的用例（含 2 期绕开折行那几个的默认配置镜像）与上游逐位相同，标记、链接、选区的 trim 计数跟着对。段末编译一次，只跑 5a 的 suite。

---

### Task 1: 基准工具 `tools/terminal-bench` 与基线数字

**Files:**
- Create: `tools/terminal-bench/terminalbench.lpi`、`tools/terminal-bench/terminalbench.lpr`、`tools/terminal-bench/.gitignore`（忽略 `lib/`、`*.exe`，照 `tools/terminal-fontprobe`）
- Modify: 主文件「基线数字」表（填基线列）

**一定在改任何 `source/` 之前做完**：基线量的是 4 期签收时的代码。

- [ ] **Step 1: 工程**：照 `tools/terminal-fontprobe/fontprobe.lpi` 建（LCL 程序、`Interfaces`、搜索路径直接指 `../../source`、不引 `.lpk`；BGRABitmap 的包依赖同 fontprobe）。程序头注释写：它做什么、每个开关量什么、怎么跑、数字写到哪（主文件「基线数字」、spec §16）。
- [ ] **Step 2: 输入数据**：一个种子化的生成器（`xorshift32`，种子写死 `20260929`，不读时间）造「混合终端输出」：每行 60–200 个字符，70% ASCII 单词、10% CJK、1% 表情（U+1F600 段）、1% 组合字符（e + U+0301）；每 5–12 个词换一次颜色（轮换 `ESC[3Nm`、`ESC[38;5;Nm`、`ESC[38;2;r;g;bm`、`ESC[0m`）；行尾 `CRLF`。同一个生成器给所有开关用；数据在内存里现造，不落盘。
- [ ] **Step 3: 开关**（每个开关一段，打印一张 Markdown 表；`--all` 按下面顺序全跑；计时一律 `TyTermDefaultClock`，每项跑 N 次取中位、最大）：
  1. `--core`：`TTyTerminalCore.Create(200, 60)`、`Scrollback = 1000`，32 MB 按 64 KB 切块 `WriteSync`；报 MB/s、每块解析耗时的中位与最大、结束时 `TTyTerminalLine.LiveCount`。
  2. `--slice`：同样的 Core，一次 `Write` 20 MB，然后循环 `ProcessPending(12)` 直到返回 False；报片数、最长一片的耗时（基线应当是「一片、整块」）。
  3. `--paint`：离屏建控件（照 `tools/terminal-shots` 的做法：真父窗体、自建 controller、`RenderTo`），200 × 60，写满一屏混合内容；先 `RenderTo` 一次热身（冷填充不计），再「整屏标脏 + `RenderTo`」50 次；96、144 PPI 各一组。Task 11 之后加一列 `MinimumContrastRatio = 4.5`（基线时这一列写「—」）。
  4. `--scroll`：同一个控件，写满一屏后逐行 `WriteSync('line n' + CRLF)`，每行之后 `RenderTo` 一次，共 2000 行；报每帧平均画了几行（`RowsPainted` 的差值 / 帧数）和每帧耗时中位。
  5. `--raster`：新建控件、清空字形缓存，`RenderTo` 一屏「95 个可打印 ASCII × 常规 / 粗 / 斜 / 粗斜」共 380 个字形（关掉光栅预算：把时钟冻住，照 4 期像素测试的做法）；再另起一屏 200 个不同的 CJK 字。报总耗时和每个字形的耗时。**另外拆开量**光栅器里 `TextSize` 与 `TextOut` 各占多少（在 bench 里直接对 `TTyTermGlyphRasterizer` 用的同一张草稿位图各调 380 次计时），Task 8 据此决定度量要不要一起挪。
  6. `--flood`：控件在真父窗体上，50 MB 按 64 KB 经 `View.Write(…, @Done)` 喂，一次只让 4 块在途（`Done` 回调里再写下一块，照示例的回放流控）；主循环 `Application.ProcessMessages` 直到全部回调到齐。报墙钟、MB/s、`RenderTo` 相邻两次的最长间隔（给控件挂一个 bench 自己的 `OnPaint` 计时不行——用 `RowsPainted` 采样也不行，改成在 bench 的子类里覆盖 `Paint` 记时间戳）、`GetFPCHeapStatus.CurrHeapUsed` 前后差、结束时 `TTyTerminalLine.LiveCount`、字形缓存 `Hits` / `Misses`（Task 9 之后加 `Evictions`）。
  7. `--reflow`：Core `Scrollback = 10000`、200 列 × 60 行，写满（每条逻辑行 400 个字 = 两行一折）；依次 `Resize(120, 60)`、`Resize(200, 60)`、`Resize(80, 60)`，报每次的耗时。基线时折行没接，数字只有「截行」的开销，照记。
  8. `--window --flood <MB>`：开一个真窗口（`TTyForm` 就够，这是工具不是示例），窗口出来后一次 `View.Write` 指定 MB 数的数据，给真机验收第 72 项用；不计时。
- [ ] **Step 4: 编译并跑**：主文件「基准工具」那条命令（`--all`）。Expected：每段都有数字；`--slice` 显示 1 片。
- [ ] **Step 5: 填表**：把数字填进主文件「基线数字」的基线列（写明本机 CPU 型号——从 `wmic cpu get name` 取——与跑的次数）。
- [ ] **Step 6: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-bench docs/superpowers/plans/2026-09-29-terminal-phase-5.md && git commit -m "tools(terminal): a benchmark for the core, the view and the glyph cache

Throughput, slicing of one big write, a full repaint, line-by-line
scrolling, cold glyph rasterization, a 50 MB flood through the view with
its heap and live-line counts, and resize cost with a deep scrollback --
seeded input, median of repeated runs, a Markdown table out. The numbers
before phase 5 are recorded in the plan.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

**变异**：无（工具不进测试；它的数字在 Task 9 由测试的判据守）。

---

### Task 2: 折行的基准脚本与夹具

**Files:**
- Create: `tools/terminal-oracle/reflow-cases.js`、`tools/terminal-oracle/cases/reflow.js`
- Modify: `tools/terminal-oracle/lib-dump.js`、`lib-term.js`、`buffer-cases.js`、`regen-all.js`、`cases/buffer.js`、`cases/selection.js`、`cases/links.js`、`url-cases.js`（`lines` 支持改尺寸）
- Generate: `tests/fixtures/terminal-core-reflow*.json`、`terminal-reflow-units.json`；重新生成 `terminal-buffer-ops*.json`、`terminal-selection*.json`、`terminal-links*.json`

含 `\x1b`、`\u` 的 JS 一律用 Write 工具落文件（地雷 5）。脚本只用 node 内置模块，只经 `lib-dump.js` 加载上游。

- [ ] **Step 1: `lib-dump.js`**：`PORTED` 追加 `common/buffer/BufferReflow`（源 → 产物，照已有写法）；`GENERATED` 追加 `terminal-core-reflow`（可分片，写正则）与 `terminal-reflow-units.json`。头注释补一行：5 期的折行夹具。
- [ ] **Step 2: `lib-term.js`**：
  1. `DEFAULT_OPTIONS` 加 `reflowCursorLine: false`；`makeCaseTerminal` 把它传给 `Terminal`；`normalizeOptions` 自动只写不同于默认的键（现有夹具不变——Step 7 用 `--expect-clean` 以外的方式核对：重跑后除了新增的夹具，已有夹具**逐字节不变**）。
  2. `runSteps` 加步骤 `{ marker: n }` → `term.registerMarker(n)`（上游 `ybase + y + n`，`headless/Terminal.ts:72-74`）；引用不用留，导出的 `markers` 读缓冲的活标记。
  3. 头注释的步骤表补这一种。
- [ ] **Step 3: `buffer-cases.js` 与 `cases/buffer.js`**：选项读 `reflowCursorLine`（传给 `optionsService`）；`cases/buffer.js` 加一组 `reflow`：
  1. **镜像**（核实记录 15）：`cols-change-windowspty`、`resize-cursor-clamp`、`tabs-after-resize` 各复制一份去掉 `windowsPty` 的，id 加后缀 `-reflow`；原来的留着（它们现在守「老 ConPTY 不折」）。
  2. 照 `Buffer.test.ts:260-1140` 的场景逐个写成缓冲层操作（文字用 `text` 步骤直接放格子、光标用 `setXY`）：不折空行；缩列截行；折开与合回（5 列写满后 1 列再回 5 列——注意 1 列只能用于**没有宽字符**的内容，核实记录 6）；`reflowCursorLine` 两种；滚回装不下的部分被丢掉；变宽时删对行数；组合字符跟着搬；标记随折行移动、被挤掉的标记作废；行尾是 0 宽（Tab 留下的）的折行；宽字符变宽 / 变窄；`reflowLarger` 的「视口未满 / 滚回有余 ybase=0 / ybase≠0 且 ydisp=ybase / ydisp≠ybase / 滚回已满」五类；`reflowSmaller` 同五类。每个判据单独一个用例（spec §13.5 第 8 条）。
- [ ] **Step 4: `reflow-cases.js` + `cases/reflow.js`**：用 `lib-term.js` 的 `runCase` / `writeCoreFixture`，出 `terminal-core-reflow.json`（`kind: "core-reflow"`、`source: "reflow"`），格式同其余 Core 夹具（含 `afterReset`）。`cases/reflow.js` 只放输入，分组如下，每组若干用例、每个判据一个用例：
  1. **来回改宽**：一条 170 字的 ASCII 长行，80 → 40 → 13 → 80；80 → 79 → 81 → 2 → 80；只改行数（`_reflow` 早退）。
  2. **宽字符跨行**：CJK 恰好压在旧列尾 / 新列尾；奇数列宽让宽字符落在切口（变窄时挪到下一行、行尾补空格子）；宽字符提前折行留下的空格子（核实记录 7）再变宽；列数 2 与宽字符。
  3. **组合字符**：`e` + U+0301 落在切口两侧；`unicodeVersion: '15-graphemes'` 下的 ZWJ 表情序列跨切口；组合符在折行后的行首。
  4. **标记**：`marker` 步骤放在折行段的各行、段后、滚回里；变宽删行（标记作废 / 上移）、变窄插行（标记下移）、挤出滚回（作废）。
  5. **OSC 8 链接**：一条跨三行的链接变宽、变窄；同 id 两段；链接行被挤出滚回（导出的 `links` 表与格子上的 `urlId`）。
  6. **光标**：光标在折行段里（默认不动 / `reflowCursorLine: true`）；光标在段后；视口未满时光标行上移；`ESC 7` 存了光标之后改宽度再 `ESC 8`（`savedY`）。
  7. **滚回满**：`scrollback` 5 与 10 写满后变窄（`onTrim`，导出的 `scrolls` 与 `ybase` / `ydisp`）；先 `scrollLines: -3`（视口不在底部）再变窄 / 变宽。
  8. **备用屏**：主屏有折行、进 `?1049h`、备用屏也写折行、改列数（备用屏不折、主屏折）、退出看主屏。
  9. **`WindowsPty` 七种**：`null`、`{conpty, 21375}`、`{conpty, 21376}`、`{conpty}`（无构建号）、`{winpty, 30000}`、`{无后端, 30000}`（写成 `{ buildNumber: 30000 }`）、`scrollback: 0`；每种一个「变窄再变宽」；再加一个中途 `setOption: { windowsPty: … }` 从老 ConPTY 切成没有的用例（行比网格长的时候打开折行）。
  10. **2 期 Core 用例的镜像**：`decset-3-winlines`（DECCOLM 132 / 80 列也走折行）、`resize-min`、`resize-cols-winpty`、`resize-saved-cursor` 去掉 `windowsPty`，id 加 `-reflow`。
  11. **录制**：`ls-color`、`cat-cjk-emoji`、`git-log-color`、`vim-edit`（备用屏）各一例：按录制尺寸写完整份，再改到 `宽 − 7`、`宽 − 23`、`宽 + 13`、原宽；录制从 `tools/terminal-oracle/recordings/` 读（和 `recordings.js` 同一个读法，抄它的函数或抽进 `lib-term.js`）。
  12. **种子化随机**：120 个用例，种子 `k + 1`；每例 6–12 步，在「随机写」（ASCII、CJK、表情、组合符、SGR、CR / LF、Tab、`?7l` / `?7h`，200–2000 字节）与「随机改尺寸」（列 2–60、行 1–12）间交替，`scrollback` 取 0–20；夹具里写种子。任何一例上游抛异常或超过 5 秒没结束，就删掉并在脚本里记一行（spec §13.5 第 6 条；超时用 `worker_threads` 跑随机组，主线程等结果带超时——随机组单独放一个 worker，确定性不受影响）。
- [ ] **Step 5: 单元夹具 `terminal-reflow-units.json`**（同一个脚本）：在 node 里直接造 `BufferLine`（`out/common/buffer/BufferLine.js`，`new BufferLine(cols, nullCell, isWrapped)` + `setCellFromCodepoint`），调 `BufferReflow.js` 的四个函数：
  1. `reflowSmallerGetNewLineLengths(lines, oldCols, newCols)`：`BufferReflow.test.ts` 的五例原样，另加：宽字符连续跨多个切口；最后一行有尾部空白；`newCols = 2` 的宽字符（不能用 1，核实记录 6）。
  2. `getWrappedLineTrimmedLength(lines, i, cols)`：最后一行、非最后一行、「行尾空格子 + 下一行首宽字符」、行尾有内容 + 下一行首宽字符、行尾空格子 + 下一行首窄字符。
  3. `reflowLargerGetLinesToRemove(list, oldCols, newCols, absY, nullCell, rcl)`：`BufferReflow.test.ts` 的两例，另加光标在段内 / 段外、两个相邻折行段、段尾整行空。
  4. `reflowLargerCreateNewLayout(list, toRemove)`：上一项的输出直接喂，导出 `layout`、`countRemoved` 与它发的删除事件列表（订阅 `list.onDelete`）。
  行的写法（Pascal 侧照着重建）：`{ cols, wrapped, cells: [[码位, 宽度], …] }`，码位 0 = 空格子（`NULL_CELL`）；只写有内容的格子，其余是空格子。
- [ ] **Step 6: 选区与网址补用例**：
  1. `cases/selection.js`：`reflow-narrow-keeps-coords`（长行上选一段，列数变窄，上游坐标不变、选中的字变了）；`reflow-trim-shifts`（滚回满、变窄挤出行，`trimmed` 与选区上移）；`reflow-wider`；`reflow-rows-too`（行列一起变，清空）。
  2. `url-cases.js` 的 `lines` 支持可选 `resize: [c, r]`（写完、改尺寸、再查询）；`cases/links.js` 加：40 列折三行的网址改到 80 列（一条）、再改到 23 列；同一内容在 `windowsPty: {conpty, 19044}` 下改到 23 列（行比网格长，上游按全长映射——Task 5 删 `ACols` 的依据）。
- [ ] **Step 7: `regen-all.js`** 的 `SCRIPTS` 在 `recordings.js` 之后加 `reflow-cases.js`。跑：

```bash
cd /d/Projects/ty-3.1 && node tools/terminal-oracle/buffer-cases.js && node tools/terminal-oracle/reflow-cases.js && node tools/terminal-oracle/selection-cases.js && node tools/terminal-oracle/url-cases.js && git status --short tests/fixtures && ls -l tests/fixtures/terminal-core-reflow*.json tests/fixtures/terminal-reflow-units.json
```

Expected：新夹具生成（超 1.8 MB 自动分片）；`git status` 里**已有**夹具只有 `terminal-buffer-ops`、`terminal-selection`、`terminal-links` 变了，且 `git diff` 显示只是**追加**了用例（已有用例一个字节不变——`lib-term.js` 加选项不能改动旧夹具）；每个脚本打印用例数；随机组打印被删掉的用例（应当没有）。**抽查**：`{conpty, 19044}` 那例变宽后仍是两行；默认那例合成一行；光标在段内的默认用例仍是两行。

- [ ] **Step 8: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-oracle tests/fixtures && git commit -m "test(terminal): oracle for reflow on resize

Buffer operations and whole-terminal byte streams resized back and forth:
wide characters across the cut, combining marks, markers and OSC 8 links,
the cursor inside and outside a wrapped run, a full scrollback, the
alternate screen, every Windows PTY setting upstream distinguishes, the
recordings, and seeded random mixes. The resize cases phase 2 ran under
an old ConPTY to avoid reflow now also run in the default setup, and the
selection and web-link fixtures gain resized cases.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

**变异（JS 侧，期末做）**：J1：`makeCaseTerminal` 不传 `reflowCursorLine`（`true` 的用例期望值变 → Pascal 侧 `TestReflowCases` 里 `reflowCursorLine: true` 的用例红，说明夹具真的区分了这个选项）；J2：`touch` 上游的 `src/common/buffer/BufferReflow.ts`（内容不变、mtime 比产物新）→ 脚本拒绝跑；之后 `touch` 产物恢复次序，`regen-all.js --expect-clean` 仍 `clean`。

---

### Task 3: `tyControls.Terminal.Buffer.Reflow.inc`——移植 `BufferReflow.ts` 与 `_reflow*`

**Files:**
- Create: `source/tyControls.Terminal.Buffer.Reflow.inc`
- Modify: `source/tyControls.Terminal.Buffer.pas`

include 头：「tyControls.Terminal.Buffer 的一部分（被 include，不是单元）：改列数时的重新折行。移植自 xterm.js 6.0.0（commit、`src/common/buffer/BufferReflow.ts`、`src/common/buffer/Buffer.ts:310-537`），版权与许可见单元头。」单元头的「ported from」清单加这两个文件；「Reflow is phase 5 …」一段改成现在的规则；「Buffer.Resize only touches lines between ring changes」改写：折行在环形表上整体重排，重排前钉住所有原行（开工前问题二第 3 条）。

- [ ] **Step 1: 行表的触发口**：`TTyTerminalLineList` 加 `NotifyInsert` / `NotifyDelete` / `NotifyTrim`（照 `DoTrim` 的写法：有挂才调）。只是触发，不改表。
- [ ] **Step 2: 五个纯函数**（`BufferReflow.ts` 逐行，函数上方注释标行号）：
  - `TyTermReflowLargerGetLinesToRemove`（`:25-110`）：内层 `while (i < lines.length && nextLine.isWrapped)` 先判下标再读——本仓库 `Get` 越界答 `nil`，照样先判下标；「光标在段内就跳过」只在 `not AReflowCursorLine` 时。
  - `TyTermReflowLargerCreateNewLayout`（`:116-145`）：删除事件经 `ALines.NotifyDelete(i − 已删, 个数)`，**正向**。
  - `TyTermReflowLargerApplyNewLayout`（`:151-163`）：先把 `layout` 指向的行收进一个数组并 `AddRef`，再逐个 `SetItem`，再 `Length := Length(layout)`，最后逐个 `Release`（地雷 1）。
  - `TyTermReflowSmallerGetNewLineLengths`（`:179-213`）：~~入口 `ANewCols < 2` 抛 `EArgumentOutOfRangeException`~~（上游会死循环，核实记录 6）。**实现期修正（5 期）**：入口不查列数——上游自己的用例会改到 1 列（没有宽字符落在切口时照常算完），照原文做那几例会红；只在上游真会死循环的地方（宽字符落在切口、一列放不下）抛，另两处对应上游抛 TypeError 的地方也抛（`Buffer.pas` 单元头）。
  - `TyTermGetWrappedLineTrimmedLength`（`:215-229`）。
- [ ] **Step 3: 缓冲里的四个方法**（`Buffer.ts` 逐行）：
  - `GetIsReflowEnabled`（`:310-316`，开工前问题二第 4 条）：用字段 `FHasScrollback`。
  - `Reflow`（`:318-329`）：`FCols = ANewCols` 早退；否则分派。
  - `ReflowLarger` / `ReflowLargerAdjustViewport`（`:331-362`）：空行用 `TTyTerminalLine.Create(ANewCols, nullCell, False)` 经 `PushOwned`；`SavedY` 照上游 `Math.max(savedY − countRemoved, 0)`。
  - `ReflowSmaller`（`:364-537`）：
    1. 往前找段、跳过光标段、算 `destLineLengths`、`linesToAdd`、`trimmedLines`（两个分支照抄 `:392-398`）。
    2. 新行 `GetBlankLine(TyTermDefaultAttr, True)`（引用计数 1，放进本段的 `wrapped` 数组，记下它们是「本段新建的」）；`toInsert` 记起始下标与新行。
    3. 倒着搬（`CopyCellsFrom(…, True)`）；`wrapped[destLineIndex] = nil` 时 `Break`（上游的防御，`:448-452`）。
    4. 行尾补空格子（`:466-471`）；视口调整（`:473-492`，含 `lines.pop()`——**在循环里做**，地雷 3）；`SavedY`。
    5. 循环后若 `toInsert` 非空：先把所有原行收进数组并 `AddRef`；`Length := Min(MaxLength, Length + countToInsert)`；从上往下放（`:506-524`，新行用 `SetItem`）；插入事件**倒序**经 `NotifyInsert`、下标累加（`:525-531`）；`amountToTrim > 0` 时 `NotifyTrim(amountToTrim)`（`:532-535`）；最后 `Release` 全部原行、再 `Release` 全部新行（放进表的新行由表持有，没放进去的随之释放）。
  - 缓冲自己挂在行表上的 `LinesTrim` / `LinesInsert` / `LinesDelete` 不用改：`NotifyTrim` 进 `LinesTrim`，`TrimmedLines` 自动累加，标记自动调整。
- [ ] **Step 4: `Resize`** 里不用改调用点（`:2245-2253` 已在上游的位置）；只把那两行「never taken before phase 5」的注释改成现在的说法。
- [ ] **Step 5: 自查**：逐个方法对照上游（行号注释齐）；所有 `AddRef` 都有配对的 `Release`，异常路径用 `try … finally`（折行中间抛异常的话表可能已半重排，上游同样；至少不泄漏、不释放后使用）。
- [ ] **Step 6: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Buffer.Reflow.inc source/tyControls.Terminal.Buffer.pas && git commit -m "feat(terminal): the main buffer rewraps its lines when the columns change

Ported from xterm.js's BufferReflow and Buffer._reflow*: wrapped runs are
joined when the terminal widens and split when it narrows, wide characters
moved rather than cut, the viewport, cursor and saved cursor kept in step,
and markers told about every line deleted, inserted or trimmed. Reflow is
on as upstream decides: always for the normal buffer, except behind a
Windows PTY whose build is given and is not a ConPTY of 21376 or later;
never for the alternate buffer, and not for the run holding the cursor
unless asked. The lines being rearranged are pinned while the ring is.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Core 的 `ReflowCursorLine`、预言测试的接线与 5a 的测试

**Files:**
- Modify: `source/tyControls.Terminal.Core.pas`、`source/tyControls.Terminal.Core.Services.inc`（属性）
- Modify: `tests/test.terminal.oracle.pas`（选项 `reflowCursorLine`、步骤 `marker`）、`tests/test.terminal.core.pas`（`TestReflowCases`）、`tests/test.terminal.buffer.pas`（缓冲层选项）
- Create: `tests/test.terminal.reflow.pas`（suite `TTyTerminalReflowOracleTests`、`TTyTerminalReflowTests`）
- Modify: `tests/tytests.lpr`

- [ ] **Step 1: Core 属性** `ReflowCursorLine`：读写 `FOptions.ReflowCursorLine`；接口注释「reflowCursorLine（OptionsService.ts:50），默认 False：光标所在的折行段不重排；宿主可设」。
- [ ] **Step 2: 预言测试接线**：`test.terminal.oracle.pas` 的选项映射加 `reflowCursorLine`；步骤加 `marker` → `Core.Buffer.AddMarker(Core.Buffer.YBase + Core.Buffer.Y + n)`（标记是借来的，缓冲持有；导出比的是活标记）。缓冲层预言（`test.terminal.buffer.pas`）的选项同样加。
- [ ] **Step 3: 测试**（判据；夹具读法照已有的 `RunKind`）

**`TTyTerminalCoreOracleTests`**（已有 suite，加一个方法）：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestReflowCases` | `RunKind('core-reflow', 应比用例数)`：全部用例、全部导出字段、`afterReset`；应比数从夹具算出 | R1：开关用 `HasScrollback` getter（`scrollback: 0` 例红）；R2：`>= 21376` 写成 `>`（`{conpty, 21376}` 例红）；R3：构建号给了就只看数字、不看后端（`{winpty, 30000}` 例红）；R4：变宽时行尾宽字符不挪到下一行（宽字符组红）；R5：`GetWrappedLineTrimmedLength` 不认「空格子 + 下一行宽字符」（提前折行例红）；R6：变窄时不补行尾空格子；R7：插入事件正序发（标记组红）；R8：`ReflowSmaller` 不发 `NotifyTrim`（滚回满组的 `markers` 红）；R9：忽略 `reflowCursorLine`、光标段也折（光标组红）；R10：去掉视口调整里的 `lines.pop()` 分支（视口未满组红）；R11：`SavedY` 不调（`ESC 7` 例红）；R13：删除事件的下标不减已删（标记组红） |

**`TTyTerminalBufferOracleTests`**：已有的 `terminal-buffer-ops` 测试原样跑重新生成的夹具——新组（含 `-reflow` 镜像）自动覆盖；它的应比用例数常量跟着改。

**`TTyTerminalReflowOracleTests`**（`terminal-reflow-units.json`）：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestNewLineLengths` | 按夹具重建行（`SetCellFromCodepoint`，码位 0 = 空格子），`TyTermReflowSmallerGetNewLineLengths` 的数组逐项相等 | R14：宽字符落在切口时不少放一格 |
| `TestWrappedLineTrimmedLength` | 每例相等 | R5 |
| `TestLinesToRemove` | `TyTermReflowLargerGetLinesToRemove` 的数组相等 | R9 |
| `TestNewLayoutAndItsEvents` | `layout`、`countRemoved` 相等；挂在行表 `OnDelete` 上记下的事件序列与夹具相等 | R13 |

**`TTyTerminalReflowTests`**（手写）：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestOneColumnIsRefused` | 缓冲层 `TyTermReflowSmallerGetNewLineLengths(…, 1)` 抛 `EArgumentOutOfRangeException`；经 Core `Resize(1, …)` 不抛（`BufferService` 钳到 `TyTermMinimumCols = 2`，`Buffer.pas:2675`）、有宽字符的内容照样折 | R15：去掉入口检查（测试**带超时**：另开线程跑、2 秒没回来算红，不挂住整个测试进程） |
| `TestNoLineOrMarkerLeaks` | 对 `core-reflow` 夹具每个用例：跑完释放 Core 后 `TTyTerminalLine.LiveCount`、`TTyTerminalMarker.LiveCount` 回到用例前（spec §13.5 第 9 条已有的守卫在 `RunKind` 里，这条再对折行单独点名） | R12：`ReflowSmaller` 不钉原行（可能直接崩；崩也算红，记下） |
| `TestTrimmedLinesFollowsReflow` | 5 行、滚回 3、写满后从 40 列改到 10 列：`Buffer.TrimmedLines` 的增量 = 上游这一步的 `onTrim` 总量（从 `terminal-selection` 夹具 `reflow-trim-shifts` 那一步的 `trimmed` 读） | R8 |
| `TestReflowCursorLineProperty` | `Core.ReflowCursorLine := True` 后光标段也折回（`$ abcdefghijKLM`，10 → 20 列：一行）；默认两行 | K2：setter 不写 `FOptions` |
| `TestDeepScrollbackReflowIsQuick` | `Scrollback = 10000`、200 列两行一折写满，200 → 120 → 200 各一次；每次 < 1 s（宽裕上限；精确数字进 spec，开工前问题二第 14 条；计时前把时钟换回墙上时间） | R16：`ReflowLarger` 每删一段就 `Splice` 一次（平方级，Scrollback 10000 下超时） |

**`TTyTerminalSelectionOracleTests` / `TTyTerminalLinksOracleTests`**：已有测试原样跑重新生成的夹具（新加的改尺寸用例自动覆盖），应比数常量跟着改。`TTyTerminalLinksOracleTests` 里老 ConPTY 那例在 Task 5 删 `ACols` 之前是红的——**这是预期的**，5a 段末记下这一条红、留给 5b（不要为了 5a 绿去改夹具）。

- [ ] **Step 4: `tytests.lpr`** 的 uses 加 `test.terminal.reflow`；提交（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Core.pas source/tyControls.Terminal.Core.Services.inc tests/test.terminal.oracle.pas tests/test.terminal.core.pas tests/test.terminal.buffer.pas tests/test.terminal.reflow.pas tests/tytests.lpr && git commit -m "test(terminal): reflow held to upstream, case by case and function by function

The core exposes reflowCursorLine. The oracle runner learns the option and
the marker step; every reflow case, the default-setup mirrors of the old
ConPTY resizes and the pure BufferReflow functions are compared with
upstream's answers, with leak, one-column and deep-scrollback guards.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: 段 5a 编译并跑本段 suite**（主文件「跑测试的固定套路」5a 行）。只修本段的红（上面说的那一条链接用例除外）。夹具和移植对不上时**以上游为准**，先查：事件次序（地雷 2）、`pop` 的位置（地雷 3）、旧列数（地雷 4）、钉住（地雷 1）。3、4 期的 Core / Buffer 测试若因「开始折行」而红，按地雷 16 处理：新答案必须能在上游夹具里找到出处，改测试的提交写明「pinned the no-reflow answer」。
