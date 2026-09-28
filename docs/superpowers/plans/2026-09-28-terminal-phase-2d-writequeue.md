# 终端控件 2 期 · 2d 写入调度与探针（Task 19–21）

> 本文件是 [`2026-09-28-terminal-phase-2.md`](2026-09-28-terminal-phase-2.md) 的附录，执行方式、核实记录、开工前问题、接口清单、地雷都在主文件。先读主文件。

**这一批做完能看到什么**：写入队列的每条规则（只入队、队列空时请求排片、用户输入后当场解析、按块检查 12ms、回调顺序、50MB 上限、`WriteSync` 当场解析、改尺寸前先处理完、非主线程调用抛异常）都有注入时钟下的判据测试；切片喂和一次喂的结果相同（拿 2c 的夹具证明）；`tools/terminal-probe` 把录制或序列文件喂进 Core、打印屏幕文本。

写入调度**没有上游基准**：上游的时序靠浏览器事件循环，headless 里 `write` 的切片不可观察。这一批的判据来自 `WriteBuffer.ts` 源码逐条读出的规则，和 spec §3.1。

---

### Task 19: 写入队列、线程检查、时钟与排片

**Files:**
- Modify: `source/tyControls.Terminal.Core.pas`

- [ ] **Step 1: 队列与四个入口**（逐条对 `src/common/input/WriteBuffer.ts`，去掉 Promise / `lastTime` / `promiseResult` 分支）

状态：`FQueue: array of record Data: RawByteString; OnDone: TTyTerminalWriteDone; Tag: PtrInt end`、`FQueueCount`、`FBufferOffset`、`FPendingData: Int64`、`FIsSyncWriting`、`FDidUserInput`、`FProcessRequested`。

- **线程检查**：`Write` 两个重载、`WriteSync`、`ProcessPending` 入口 `if GetCurrentThreadId <> MainThreadID then raise EInvalidOperation.Create('TTyTerminalCore.<Method> must be called from the main thread')`（开工前问题二第 22 条）。检查在做任何事之前，失败时队列不变。
- **`Write(AData, AOnDone, ATag)`**（`:152-182`）：`FPendingData > 50000000` → `raise ETyTerminalWriteOverflow.Create('write data discarded, use flow control to avoid losing data')`（上游原句）。队列为空（`FQueueCount = 0`）时：`FBufferOffset := 0`；若 `FDidUserInput`：清掉它、入队、**当场** `InnerWrite`（同 `ProcessPending(12)` 的一片）、返回；否则请求排片（`RequestProcess`）。然后入队、`FPendingData += Length(AData)`。空串照样入队（上游不特判，回调照样按序调）。
- **`Write(const ABuf; ACount; ...)`**：拷成 `RawByteString` 转上一个重载。
- **`RequestProcess`**：`FProcessRequested` 为 False 时置 True 并发 `OnProcessRequest`（上游 `cancelAndSet` 保证最多一个待执行的定时器）。
- **`ProcessPending(ABudgetMs)`**（`_innerWrite`，`:219-315`）：`FProcessRequested := False`；`start := Now`；`while FQueueCount > FBufferOffset`：取块 → `Parse(块)` → 调回调 → `Inc(FBufferOffset)` → `FPendingData -= 长度` → `if Now - start >= ABudgetMs then Break`。之后：还有剩 → 已处理的块数 > 50 时把队列前移（`WRITE_BUFFER_LENGTH_THRESHOLD`）→ 返回 True（**调用者**据此再排一片；本方法不发 `OnProcessRequest`，免得重复排）；没剩 → 清空队列、`FPendingData := 0`、`FBufferOffset := 0` → 返回 False。
- **`WriteSync(AData)`**（`writeSync`，`:106-150`；不移植 `maxSubsequentCalls`）：入队（无回调）、`FPendingData += 长度`；若 `FIsSyncWriting`（回调里又调 `WriteSync`）就返回；否则置位，**从 `FBufferOffset` 起**逐块处理到队尾（见开工前问题一第 4 条：上游从下标 0 起，会把已处理的块再处理一遍），调回调；清空队列、`FPendingData := 0`、`FBufferOffset := 0`；复位标志。
- **`FlushSync`**（私有，`flushSync`，`:71-101`）：同 `WriteSync` 的处理循环（同样从 `FBufferOffset` 起），`Resize` 调它。
- **`Now`**：`Clock` 非 nil 就调它，否则调内置的高精度时钟 `TyTermDefaultClock`（开工前问题二第 9 条；在 interface 段公开，是纯函数，测试直接调）：

  ```pascal
  function TyTermDefaultClock: Double;
  {$IFDEF MSWINDOWS}
  var c, f: Int64;
  begin
    QueryPerformanceCounter(c); QueryPerformanceFrequency(f);
    Result := c * 1000.0 / f;
  end;
  {$ELSE}
  begin
    Result := GetTickCount64;   { unix SysUtils: clock_gettime(CLOCK_MONOTONIC) where available, 1 ms }
  end;
  {$ENDIF}
  ```

  Windows 上 `GetTickCount64` 粒度约 15.6ms，比 12ms 预算还粗，所以用 `QueryPerformanceCounter`（`Windows` 单元只在 `{$IFDEF MSWINDOWS}` 的 implementation uses 里）；Unix 上 FPC 3.2.2 的 `GetTickCount64` 已经是 `clock_gettime(CLOCK_MONOTONIC)`、毫秒精度，没有就退到 `fpgettimeofday`（`fpc:rtl/unix/sysutils.pp:345-362`），够用，不再引平台单元。这是平台 API，不是 widgetset，用 `MSWINDOWS` 而不是 `LCLWin32` 判断（[[widgetset-not-platform-gating]]）。
- **用户输入**：Task 15 的 `TriggerDataEvent` 在用户输入时置 `FDidUserInput := True`（`CoreTerminal.ts:151` → `handleUserInput`）。
- **析构**：队列里没处理的块直接丢弃，回调不调（上游 `dispose` 同样清空，`:51-56`）。

- [ ] **Step 2: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Core.pas && git commit -m "feat(terminal): the write queue, sliced by time on the main thread only

Write only queues and asks the host once for a processing slice; the
first write after user input is parsed at once to keep echo latency low;
a slice stops between chunks after 12 ms; callbacks run in order; more
than 50 MB pending raises; WriteSync and the flush before a resize parse
everything left. Unlike xterm.js the flush starts at the first
unprocessed chunk, so a resize in the middle of output does not parse a
chunk twice. Calls from other threads raise EInvalidOperation.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

（若开工前问题一第 4 条的结论是「照上游」，提交信息删掉 Unlike 那一句，`WriteSync` / `FlushSync` 改成从下标 0 起，Task 20 的 `TestResizeFlushDoesNotReparse` 改成断言上游行为（`"AABC"`、回调两次）。）

**变异表（期末做）：**

| # | 变异 | 必须红 |
|---|---|---|
| W1 | `Write`：队列空时也不请求排片 | `TestWriteQueuesAndAsksOnce` |
| W2 | `RequestProcess`：不看 `FProcessRequested`（每次 `Write` 都发） | `TestWriteQueuesAndAsksOnce` |
| W3 | `Write`：忽略 `FDidUserInput` | `TestFirstWriteAfterInputParsesAtOnce` |
| W4 | `ProcessPending`：`>=` → `>` | `TestSliceStopsBetweenChunksAtTheBudget` |
| W5 | `ProcessPending`：先 `Break` 判断再调回调 | `TestCallbacksRunInOrder`（最后一块的回调推迟一片） |
| W6 | `Write`：上限判断 `>` → `>=` | `TestFiftyMegabytesRaises`（恰好 50,000,000 时不该抛） |
| W7 | `WriteSync` / `FlushSync`：从下标 0 起 | `TestResizeFlushDoesNotReparse` |
| W8 | `Resize`：不先 `FlushSync` | `TestResizeFlushesFirst` |
| W9 | 线程检查只放在 `Write(RawByteString)` 一个入口 | `TestOtherThreadsAreRefused` |
| W10 | `ProcessPending` 还有剩时也发 `OnProcessRequest` | `TestSliceStopsBetweenChunksAtTheBudget`（请求次数） |

---

### Task 20: 写入队列测试 `TTyTerminalWriteQueueTests`

**Files:**
- Modify: `tests/test.terminal.core.pas`（加类、`initialization` 里 `RegisterTest(TTyTerminalWriteQueueTests)`）

测试里的时钟是一个小对象：`Clock` 指向它的方法，每次被调用返回脚本里的下一个值（脚本用完就重复最后一个）；另记被调用次数。`OnProcessRequest` 只计数，不自动调 `ProcessPending`——由测试决定何时「下一片」。每个判据给出「做什么」与「断言什么」。

| 测试 | 做什么 | 断言 |
|---|---|---|
| `TestWriteQueuesAndAsksOnce` | 新 Core；`Write('a')`；`Write('b')` | 两次之后 `OnProcessRequest` 恰好 1 次；缓冲第 0 行仍为空（只入队）；`PendingBytes = 2` |
| `TestProcessDrainsAndReports` | 接上；时钟脚本 `[0, 1, 2]`；`ProcessPending` | 返回 False；第 0 行 `"ab"`；`PendingBytes = 0`；再 `Write('c')` → `OnProcessRequest` 第 2 次 |
| `TestSliceStopsBetweenChunksAtTheBudget` | 五块各 `'x'`；时钟脚本 `[0, 5, 11, 12, 13]`（开始、每块之后） | 第一次 `ProcessPending` 处理 3 块（第 3 块后 `12 - 0 >= 12`）返回 True，`OnProcessRequest` 次数不变；第二次处理剩下 2 块返回 False；`PendingBytes` 先 2 后 0 |
| `TestOneBigChunkIsNotSplit` | 一块 1MB 的 `'x'`；时钟每次调用加 100 | 一次 `ProcessPending` 处理完整块（按块检查，核实记录 14）返回 False |
| `TestCallbacksRunInOrder` | 三块，各带回调（`ATag` 1、2、3）；时钟让第一片只处理 2 块 | 回调顺序 `1, 2`，下一片 `3`；每个回调被调时，它那一块已经在缓冲里、下一块还没有 |
| `TestCallbackMayWriteAgain` | 第一块的回调里 `Write('z')` | 同一片里处理完（队列在处理中不为空，不再请求排片），最终文本 `…z` 在最后 |
| `TestFirstWriteAfterInputParsesAtOnce` | `Input('k', True)`；`Write('ab', 回调)` | `Write` 返回时第 0 行已是 `"ab"`、回调已调、`OnProcessRequest` 0 次；再 `Write('c')` → 只入队、请求 1 次；`Input('k', False)` 不触发当场解析 |
| `TestFiftyMegabytesRaises` | 入队 50 块、每块 1,000,000 字节（不处理） | 第 51 次 `Write`（调用前 `PendingBytes = 50,000,000`，上游判的是 `>`）**不抛**，之后 `PendingBytes = 51,000,000`；第 52 次抛 `ETyTerminalWriteOverflow`，`PendingBytes` 与队列长度不变 |
| `TestWriteSyncParsesQueuedFirst` | `Write('a')`（不处理）；`WriteSync('b')` | 返回时第 0 行 `"ab"`；`'a'` 的回调已调；`PendingBytes = 0` |
| `TestResizeFlushesFirst` | 20 列；`Write` 25 个 `'x'`（不处理）；`Resize(10, 6)`（`WindowsPty` 设 `{conpty, 19044}`，免得碰折行） | 25 个字符按 20 列折行（第 0 行 20 个、第 1 行 5 个），然后才改列数 |
| `TestResizeFlushDoesNotReparse` | 三块 `'A' 'B' 'C'`；时钟让第一片只处理 `'A'`；然后 `Resize` | 第 0 行 `"ABC"`（上游是 `"AABC"`，核实记录 17）；`'A'` 的回调只调了 1 次 |
| `TestSlicedEqualsWhole` | 取 `terminal-core-escape` 夹具里的 `t0504-vim.in` 用例：一个 Core 用 `Write` 按 97 字节一块喂、时钟让每片只处理一块、循环 `ProcessPending` 直到 False；另一个 Core `WriteSync` 整段 | 两个 Core 都用 `TyTermCompareState` 比夹具的 `expect`，都通过（切片后状态和 `WriteSync` 一致，spec §13.6「调度」） |
| `TestOtherThreadsAreRefused` | 一个 `TThread` 子类在 `Execute` 里依次调 `Write('a')`、`Write(buf, 1)`、`WriteSync('a')`、`ProcessPending`，每次捕获异常类名 | 四次都是 `EInvalidOperation`；主线程上 `PendingBytes = 0`、缓冲为空 |
| `TestDestroyDropsPending` | 入队三块带回调，不处理，`Free` | 回调一次都没调；`TTyTerminalLine.LiveCount` 回到原值 |
| `TestDefaultClockMoves` | 连调两次 `TyTermDefaultClock`，中间 `Sleep(20)`；再用 `Clock := nil` 的 Core 走一遍 `Write` + `ProcessPending` | 第二次读数比第一次大、差值在 10–1000 之间（只证明单位是毫秒、在走，不做精确断言）；`ProcessPending` 不抛、返回 False |

- [ ] **Step 1: 写测试类**
- [ ] **Step 2: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add tests/test.terminal.core.pas && git commit -m "test(terminal): write queue rules under an injected clock

Queue-only writes asking once, slices stopping between chunks at the
budget, one big chunk never split, callbacks in order and re-entrant
writes, the parse-at-once after user input, the 50 MB limit at its exact
edge, WriteSync and the flush before a resize, no reparse after a
mid-slice resize, sliced output equal to one whole write on a real
fixture, and the main-thread rule on all four entry points.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 21: `tools/terminal-probe`

**Files:**
- Create: `tools/terminal-probe/terminalprobe.lpr`
- Create: `tools/terminal-probe/terminalprobe.lpi`

spec §18：「一个控制台探针（`tools/terminal-probe`，不进包）能把录制喂进 Core、打印屏幕文本，肉眼对照」。

- [ ] **Step 1: 写程序**

控制台程序（`{$APPTYPE CONSOLE}`），只 uses `SysUtils`、`Classes`、`fpjson`、`jsonparser` 和三个终端单元（不 uses LCL，也不依赖 `tycontrols.lpk`：`.lpi` 的 `OtherUnitFiles` 指向 `../../source`，和 `tests/tytests.lpi` 同样做法）。

用法：

```
terminalprobe <file> [--cols N] [--rows N] [--scrollback N] [--unicode 6|11|15|15-graphemes]
              [--convert-eol] [--scrollback-too] [--chunk N]
```

- `<file>` 是 `.cast`（asciicast v2：头部取宽高、拼接所有 `"o"` 事件）或任意文件（原样字节）。
- 默认 80 × 24（`.cast` 用头部的尺寸），`--chunk N` 按 N 字节一块 `Write` 并循环 `ProcessPending` 到 False（顺便演示调度），否则 `WriteSync` 整段。
- 输出：先一行 `cols x rows, ybase, cursor (x, y), active normal|alt, title "…"`；然后视口每一行 `NN|<TranslateToString(True)>`；`--scrollback-too` 时先打印滚回部分；最后一行 `OnData: <十六进制，最多 64 字节>`。
- 退出码 0；文件读不了退出码 1 并打印原因。

`.lpi` 照 `tests/tytests.lpi` 的最小写法（一个构建模式、`OtherUnitFiles = ../../source`、`Target = terminalprobe`、`UseAnsiStrings`），不加任何包依赖。

- [ ] **Step 2: 提交**（不编译；Task 23 Step 1 编译并跑）

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-probe && git commit -m "feat(terminal): a console probe that replays a recording through the core

terminalprobe feeds an asciicast recording or any byte file to
TTyTerminalCore, whole or in slices, and prints the screen, the cursor
and the replies, for eyeballing against a real terminal. It builds from
source/ without the package and uses no LCL unit.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 3: 判据（Task 23 Step 1 跑）**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tools/terminal-probe/terminalprobe.lpi > /tmp/term-probe-build.txt 2>&1 || tail -20 /tmp/term-probe-build.txt; git -C /d/Projects/xterm.js show HEAD:test/fixtures/escape_sequence_files/t0504-vim.in > /tmp/t0504.in && tools/terminal-probe/terminalprobe.exe /tmp/t0504.in --cols 80 --rows 25 --convert-eol | head -30
```

Expected：编过；输出的视口文本与 `tests/fixtures/terminal-core-escape*.json` 里 `t0504-vim.in` 用例各行的 `t` 字段逐行相同（肉眼抽 5 行对照即可，精确比较已由 Task 18 做）；`--chunk 97` 的输出与整段喂相同。
