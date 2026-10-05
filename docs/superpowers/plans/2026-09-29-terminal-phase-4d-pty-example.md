# 终端控件 4 期 · 4d 真 shell 示例、文档、notices（Task 13–17）

> 本文件是 [`2026-09-29-terminal-phase-4.md`](2026-09-29-terminal-phase-4.md) 的附录，执行方式、核实记录、开工前问题、接口清单、地雷都在主文件。先读主文件，尤其是核实记录 24–26、「Win32InputMode 与 ConPTY 鼠标：结论」、开工前问题一第 4 条与二第 16–20 条，地雷 11–13、19–21。

**这一批做完能看到什么**：示例多一个「Shell」模式：Windows 起 cmd / pwsh（ConPTY），Linux / macOS 起 `$SHELL -l`；键入经写线程进 PTY，输出经读线程、加锁队列、一次唤醒回到主线程写进终端，`Write` 回调记账做背压；改窗口大小同步 PTY；进程退出在终端里打一行；Windows 把 `{conpty, 构建号}` 交给 Core。会话逻辑用假后端在 Windows 测试里跑，ConPTY 真起一次 `cmd /c`，Unix 后端在 WSL 里编成控制台程序跑。控件文档、README、notices、示例 i18n。段末编译一次，只跑 4a–4d 的 suite；WSL 跑 `ptytest`。

---

### Task 13: PTY 会话 `uptysession.pas` 与接到终端的 `ushell.pas`

**Files:**
- Create: `examples/terminal/uptysession.pas`、`examples/terminal/ushell.pas`
- Create: `tests/test.terminal.pty.pas`（suite `TTyTerminalPtyTests`，本任务写会话与接线部分）
- Modify: `tests/tytests.lpr`

- [ ] **Step 1: `uptysession.pas`**（只引 `Classes`、`SysUtils`、`SyncObjs`；单元头说明线程约定，spec §3.5）

```pascal
type
  { 一个平台的 PTY。Read / Write 在后台线程里调、会阻塞；其余在主线程。 }
  TPtyBackend = class
  public
    function Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean; virtual; abstract;
    { > 0 读到的字节数；<= 0 结束（子进程那头关了，或者被 Interrupt） }
    function Read(var ABuf; ACount: Integer): Integer; virtual; abstract;
    { 全部写完才返回 True；False = 管道断了 }
    function Write(const ABuf; ACount: Integer): Boolean; virtual; abstract;
    procedure Resize(ACols, ARows: Integer); virtual; abstract;
    { 让阻塞中的 Read / Write 返回（任意线程可调、可重复调） }
    procedure Interrupt; virtual; abstract;
    { 读到结束之后：子进程的退出码（等它退出，最多 AWaitMs） }
    function ExitCode(AWaitMs: Integer): Integer; virtual; abstract;
    { 所有线程都停了之后，在主线程：收子进程、关句柄 }
    procedure Shutdown; virtual; abstract;
    { Windows 后端答 (twpConPty, 构建号) 用；其余答 False }
    function IsConPty(out ABuild: Integer): Boolean; virtual;
    { 会话起了读线程后告诉后端（Windows 用它 CancelSynchronousIo）；默认什么都不做 }
    procedure BindReader(AThread: TThread); virtual;
  end;

  TPtySession = class
  public
    constructor Create(ABackend: TPtyBackend; AHigh: Integer = 1048576; ALow: Integer = 262144;
      AChunk: Integer = 65536);   { 拿走 ABackend 的所有权 }
    destructor Destroy; override; { = Close }
    function Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean;
    procedure Write(const AData: RawByteString);      { 主线程：进写队列 }
    procedure Resize(ACols, ARows: Integer);          { 主线程：直接转给后端 }
    { 主线程：取走队列里的全部输出；结束了（且之前的输出都已取走）时 AExited 为真 }
    function Pump(out AData: RawByteString; out AExited: Boolean; out AExitCode: Integer): Boolean;
    { 主线程：终端处理完了 ACount 字节（Write 的回调）；降到低水位以下就放读线程 }
    procedure Delivered(ACount: Integer);
    procedure Close;                                  { 幂等；地雷 12 的顺序 }
    { 读线程上调：队列从空变非空，或者读到了结束。宿主在里面安排主线程 Pump }
    property OnWake: TNotifyEvent;
    { FOR THE TESTS }
    property Outstanding: Int64;       { 读到、还没 Delivered 的字节 }
    property MaxOutstanding: Int64;
    property WakeCount: Integer;
    property Backend: TPtyBackend;
  end;
```

  - 读线程：循环 { 没在丢弃模式且 `Outstanding > High` → 等放行事件（每 100 ms 醒一次看是否该退出）；`n := Backend.Read(buf, Chunk)`；`n <= 0` → 结束：`code := Backend.ExitCode(2000)`，锁里标「已结束 + 退出码」，唤醒，退出；丢弃模式 → 丢掉、继续；否则锁里追加、`Outstanding += n`、更新 `MaxOutstanding`，原来是空的 → 唤醒 }。
  - 写线程：等写队列非空（或该退出）；逐块 `Backend.Write`；失败 → 停写（读线程会读到结束）。
  - `Pump`：锁里取走全部数据（拼成一串）；「已结束」只在数据取空之后报一次。
  - `Close`：丢弃模式 → 放行事件置位 → `Backend.Interrupt` → 写线程的事件置位 → 等两个线程结束（地雷 12）：循环「等 50 ms、没结束就再 `Backend.Interrupt`」，总共 5 s，超时就 `raise`——测试会看到，而不是挂住 → `Backend.Shutdown`。
  - 唤醒不在锁里调（宿主的回调可能也要锁）。

- [ ] **Step 2: `ushell.pas`**（引 `Forms`、控件单元、`uptysession`；平台后端由调用方传入）

```pascal
type
  TTerminalShell = class
  public
    constructor Create(ATerm: TTyTerminalView; ABackend: TPtyBackend);
    destructor Destroy; override;                    { Stop；RemoveAsyncCalls(Self) }
    function Start(const ACommand: string; out AError: string): Boolean;
    procedure Stop;
    property Running: Boolean;
    property OnData: TTyTerminalDataEvent;           { 键码面板照样要看到按键的字节 }
    property OnOutput: TTyTerminalDataEvent;         { 「记录 PTY 输出」用：每次 Pump 到的原始字节 }
    property OnExit: TNotifyEvent;                   { 退出那一行打完之后 }
    property ExitCode: Integer;
  end;
```

  - `Start`：`Backend.IsConPty(build)` → `Term.Core.WindowsPty := (twpConPty, build)`，否则 `(twpNone, 0)`（在第一个字节到来之前设，spec §12.4）；`Term.ReadOnly := False`；接管 `Term.OnData`（→ `Session.Write`，再转宿主的 `OnData`）与 `Term.OnGridResize`（→ `Session.Resize`）；`Session.OnWake` → `Application.QueueAsyncCall(@AsyncPump, 0)`；按 `Term.Cols / Rows` 起。
  - `AsyncPump`：`Session.Pump`；有数据 → `OnOutput`，`Term.Write(data, @WriteDone, Length(data))`；结束了 → `Term.Write('', @ExitDone, code)`（空串带回调：排在前面所有输出之后，spec §3.1）。
  - `WriteDone(tag)` → `Session.Delivered(tag)`；`ExitDone(code)` → `Term.WriteSync(#13#10 + 暗色 + Format(rsShellExited, [code]) + 复位 + #13#10)`、`Running := False`、`OnExit`。
  - `Stop`：`Session.Close`；还原 `Term.OnData` / `OnGridResize`；`Term.Core.DiscardPending`（丢掉还没解析的输出，宿主要换会话了）。
  - resourcestring `rsShellExited = 'Process exited with code %d'`。

- [ ] **Step 3: 测试**（`TTyTerminalPtyTests` 的第一部分：假后端）。假后端 `TFakePty`：`Read` 等一个事件、从「待读」队列取（`Feed(s)` 追加、`FeedEof(code)` 结束）；`Write` 记下；`Resize` 记下；`Interrupt` 让 `Read` 立即返回 0；可选「无尽模式」每次 `Read` 都给满一块。等待一律 `Forms.Application.ProcessMessages` + 睡 5 ms 循环，最长 5 s，超时断言失败（不挂住）。终端用 3 期的 `TTyTermViewFixture`（真 `QueueAsyncCall`，不走 `ScheduleSlice` 的缝）。

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestOutputReachesTheTerminal` | `Feed('hello')` → 等到终端第 0 行是 `hello` | Y1：`OnWake` 没接 `QueueAsyncCall` |
| `TestOneWakePerBatch` | 不 `Pump`：连续 `Feed` 100 块 → `WakeCount = 1`；`Pump` 一次后再 `Feed` 一块 → 2 | Y2：每块都唤醒 |
| `TestBackpressureStopsTheReader` | 高水位 64 KB、低 16 KB、块 8 KB，无尽模式，从不 `Delivered` → 1 s 后 `MaxOutstanding ≤ 64 KB + 8 KB`；`Delivered(全部)` 之后 200 ms 内读的次数继续增加 | Y3：读线程不看水位 |
| `TestTheExitLineComesLast` | `Feed('a'#13#10'b')`、`FeedEof(3)` → 终端依次是 `a`、`b`、然后退出那一行（含 `3`）；`OnExit` 一次、`ExitCode = 3` | Y4：`Pump` 先报结束再给数据 |
| `TestKeysGoToThePty` | `TypeChar('x')`（探针）→ 假后端 2 s 内收到 `x`；键码面板的转发（`OnData`）也收到 | Y5：写线程没起（`Write` 只进队列） |
| `TestResizeFollowsTheGrid` | 夹具 `SizeTo(100, 30)` → 假后端最后一次 `Resize = (100, 30)`，等于 `Term.Cols / Rows` | Y6：`OnGridResize` 没接 |
| `TestTheWindowsPtyIsTold` | 假后端 `IsConPty` 答 `(True, 19044)` → `Start` 之后、第一个字节之前 `Term.Core.WindowsPty = (twpConPty, 19044)`；答 False → `(twpNone, 0)` | Y7：`WindowsPty` 没设 |
| `TestCloseDoesNotHang` | `Read` 阻塞中 `Close` → 1 s 内返回、两个线程都结束；再 `Close` 一次无事；释放 `TTerminalShell` 时有排着的 `AsyncPump` → 不 AV（`RemoveAsyncCalls`） | Y8：`Close` 不调 `Interrupt`（超时失败） |
| `TestCloseWhileHeldBack` | 背压停住读线程时 `Close` → 1 s 内返回 | Y9：等放行时不看「该退出」 |
| `TestBackpressureThroughTheTerminal` | 无尽模式限量 5 MB、高水位 256 KB：接真终端跑到结束，`MaxOutstanding ≤ 256 KB + 64 KB`，终端最终收到的字节数 = 5 MB（`Write` 回调的 `tag` 累加），没有 `ETyTerminalWriteOverflow` | Y10：`WriteDone` 不调 `Delivered`（卡住 → 超时失败） |

- [ ] **Step 4: `tytests.lpr` 的 uses 加 `test.terminal.pty`；提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add examples/terminal/uptysession.pas examples/terminal/ushell.pas tests/test.terminal.pty.pas tests/tytests.lpr && git commit -m "feat(terminal-example): a PTY session with a reader, a writer and back-pressure

Output is read on a background thread into a locked queue and handed
to the main thread with one wake-up per batch; the terminal's write
callbacks count it back down, and the reader stops above a high-water
mark until they do. Keys are written on a second thread, so a large
paste does not stall the window. When the program exits, its last
output is shown before a line saying so.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Windows ConPTY 后端 `uptywin.pas`

**Files:**
- Create: `examples/terminal/uptywin.pas`
- Modify: `tests/test.terminal.pty.pas`（第二部分，`{$IFDEF MSWINDOWS}`）

- [ ] **Step 1: 声明**（核实记录 24；全部在单元里，注释写「FPC 3.2.2 没有」）：`HPCON = THandle`；`STARTUPINFOEXW = record StartupInfo: TStartupInfoW; lpAttributeList: Pointer; end`；`PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = $00020016`；函数指针类型：`CreatePseudoConsole(size: DWORD; hInput, hOutput: THandle; dwFlags: DWORD; out phPC: HPCON): HRESULT; stdcall`、`ResizePseudoConsole(hPC: HPCON; size: DWORD): HRESULT; stdcall`、`ClosePseudoConsole(hPC: HPCON); stdcall`（`size` 按 `DWORD` 打包，开工前问题二第 19 条）、`InitializeProcThreadAttributeList` / `UpdateProcThreadAttribute` / `DeleteProcThreadAttributeList`、`CancelSynchronousIo(hThread): BOOL`、`RtlGetVersion(var OSVERSIONINFOEXW): LONG`（ntdll）。一个 `LoadConPty: Boolean` 按名取 kernel32 的全部（取不到任何一个就 False）；受保护的类变量钩子 `ConPtyLoader` 让测试模拟「本机没有」。

- [ ] **Step 2: `TPipeBackend`**：在一对现成的句柄上读写（`Read` = `ReadFile`，`ERROR_BROKEN_PIPE` / 失败答 0；`Write` = 循环 `WriteFile`），`Interrupt` = 先置「该退出」标志（`Read` 每次进 `ReadFile` 前查），再 `CancelSynchronousIo(读线程句柄)`（句柄来自 `BindReader`，Task 13 的接口）——取消只对正阻塞在 I/O 里的线程有效，落在两次 `ReadFile` 之间就丢了，所以会话的 `Close` 等读线程时每 50 ms 再调一次 `Interrupt`（Task 13 的 `Close` 照此写：`WaitFor` 用带超时的循环）；`Start` / `Resize` / `ExitCode` / `Shutdown` 留给子类。测试直接用它做管道收发。

- [ ] **Step 3: `TConPtyBackend = class(TPipeBackend)`**：
  1. `Start`：`LoadConPty` 失败 → `AError := rsConPtyUnavailable`，False。两对匿名管道；`CreatePseudoConsole((ARows shl 16) or ACols, inRead, outWrite, 0, FPC)`；随后关掉 `inRead`、`outWrite`（伪控制台已复制它们）。属性表两次调用取大小、分配、`InitializeProcThreadAttributeList`、`UpdateProcThreadAttribute(list, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, Pointer(FPC), SizeOf(HPCON), nil, nil)`——**值就是句柄本身，不是指向句柄的指针**（常见的错）。`CreateProcessW(nil, 可写的命令行副本, nil, nil, False, EXTENDED_STARTUPINFO_PRESENT, nil, nil, si.StartupInfo, pi)`，`si.StartupInfo.cb := SizeOf(STARTUPINFOEXW)`，不设 `STARTF_USESTDHANDLES`。失败 → `SysErrorMessage` 进 `AError`、清理、False。成功后删属性表、关线程句柄、留进程句柄。
  2. 退出等待线程（后端自己的）：`WaitForSingleObject(进程, INFINITE)` → `GetExitCodeProcess` 记下 → 锁里 `ClosePseudoConsole(FPC)`、`FPC := 0`（让输出管道断、读线程读到结束；24H2 之前它会阻塞到输出排空，所以在这个线程里调，开工前问题二第 18 条）。
  3. `Resize` = `ResizePseudoConsole`（记下最后一次的 `HRESULT`，FOR THE TESTS）；`ExitCode(AWaitMs)` = 等进程句柄最多 `AWaitMs` 后读退出码；`Interrupt` = 锁里还有 `FPC` 就 `ClosePseudoConsole`（用户关闭时），再 `inherited Interrupt`；`Shutdown` = 等进程 2 s，还在就 `TerminateProcess`，等退出等待线程结束，关全部句柄。`IsConPty` 答 `(True, TyWindowsBuildNumber)`。
  4. `TyWindowsBuildNumber`：`RtlGetVersion` 的 `dwBuildNumber`（开工前问题二第 20 条），取不到答 0。`TyConPtyAvailable` = `LoadConPty`。
  5. resourcestring：`rsConPtyUnavailable = 'This version of Windows has no pseudo console (ConPTY); Windows 10 1809 or later is needed.'`。

- [ ] **Step 4: 测试**（`TTyTerminalPtyTests` 第二部分）

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestPipesRoundTrip` | `TPipeBackend` 接两对 `CreatePipe`：测试往「输出管道」写 `abc` → 会话 `Pump` 到 `abc`；`Session.Write('xyz')` → 测试从「输入管道」读到 `xyz`；测试关掉输出管道的写端 → 会话报结束 | Y11：`Read` 把 `ERROR_BROKEN_PIPE` 当错误重试（不结束，超时失败） |
| `TestInterruptUnblocksARead` | 没有数据时 `Close` → 1 s 内返回（`CancelSynchronousIo` 让 `ReadFile` 返回） | Y12：`Interrupt` 空实现 |
| `TestTheBuildNumberIsTheRealOne` | `TyWindowsBuildNumber` = 注册表 `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion` 的 `CurrentBuildNumber`，且 ≥ 10240 | Y13：用 `GetVersionEx`（测试程序没有兼容性清单时报 9200） |
| `TestNoConPtyIsReported` | `ConPtyLoader` 换成答 False → `Start` 返回 False、`AError = rsConPtyUnavailable`、没有线程起来 | — |
| `TestConPtyRunsACommand` | （`TyConPtyAvailable` 为假就 `Ignore` 并注明）`cmd.exe /d /c echo tyterm-ok& exit 7`：10 s 内会话输出（去掉转义序列后）含 `tyterm-ok`、结束、`ExitCode = 7` | Y14：属性值传成 `@FPC`（子进程没挂上伪控制台，拿不到输出）；Y15：没有退出等待线程（等不到结束） |
| `TestConPtyResizesAndCloses` | `cmd.exe /d /k`：`Resize(100, 40)` 的 `HRESULT = S_OK`；`Close` 5 s 内返回；之后进程句柄已 signaled | Y16：`Shutdown` 不等进程、不 `TerminateProcess`（残留） |

- [ ] **Step 5: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add examples/terminal/uptywin.pas tests/test.terminal.pty.pas && git commit -m "feat(terminal-example): Windows shells through ConPTY

The pseudo-console calls and the attribute-list calls FPC 3.2.2 does
not declare are looked up by name; without them the example says so.
A thread waits for the program to exit and closes the pseudo console
there, since that call blocks until the output is drained. The real
build number comes from RtlGetVersion and goes to the core, which on
builds before 21376 keeps xterm.js's old-ConPTY wrapping rules.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15: Unix 后端 `uptyunix.pas` 与 WSL 验证程序

**Files:**
- Create: `examples/terminal/uptyunix.pas`
- Create: `tools/terminal-ptytest/ptytest.lpr`、`tools/terminal-ptytest/.gitignore`（忽略 `lib/`、`ptytest`）

- [ ] **Step 1: `uptyunix.pas`**（`{$IFDEF UNIX}`；引 `BaseUnix`、`Unix`、`TermIO`、`Classes`、`SysUtils`、`uptysession`；**不引 LCL**；单元头写 fork 的规矩，地雷 11）
  - 声明（核实记录 25）：`posix_openpt(flags: cint): cint`、`grantpt(fd: cint): cint`、`unlockpt(fd: cint): cint`、`ptsname(fd: cint): PChar`，都 `cdecl; external 'c'`。
  - `Start`：
    1. 主端 `posix_openpt(O_RDWR or O_NOCTTY)`、`grantpt`、`unlockpt`、`ptsname` 抄进一个预先分配好的缓冲；主端设 `FD_CLOEXEC` 与 `O_NONBLOCK`；`TIOCSWINSZ` 设初始尺寸（`ws_row`、`ws_col`，像素两项 0）。
    2. 自唤醒管道 `FpPipe`，两端 `FD_CLOEXEC`，读端 `O_NONBLOCK`。
    3. fork 之前备好：`argv = ['/bin/sh', '-c', 'exec ' + 命令行]`（让 shell 自己解析命令行、再被命令替换掉）；`envp` = 当前环境去掉 `TERM` / `COLORTERM` / `LINES` / `COLUMNS`，加 `TERM=xterm-256color`、`COLORTERM=truecolor`；全部转成以 nil 结尾的 `PPChar`，字符串在父进程里留到子进程 exec 之后才释放。
    4. `FpFork`：子进程（只系统调用）：`FpSetsid`；`FpOpen(从端名, O_RDWR)`；`FpIoctl(从端, TIOCSCTTY, nil)`；`FpDup2` 到 0 / 1 / 2；从端 > 2 就关；关主端；`FpExecve('/bin/sh', argv, envp)`（`PChar` 重载）；失败 `FpExit(127)`。父进程：记下 pid；失败 → `AError`、清理。
  - `Read`：`FpPoll([主端 POLLIN, 唤醒读端 POLLIN], -1)`；唤醒 → 答 0；主端可读 → `FpRead`：> 0 答字节数；`EAGAIN` / `EINTR` → 再 poll；0 或 `EIO`（Linux 上从端全关）→ 答 0；主端 `POLLHUP` 且读不出 → 答 0。
  - `Write`：循环 `FpPoll([主端 POLLOUT, 唤醒读端 POLLIN])` + `FpWrite`，处理部分写与 `EAGAIN`；唤醒 → False。
  - `Resize`：`FpIoctl(主端, TIOCSWINSZ, @ws)`（内核给前台进程组发 `SIGWINCH`）。
  - `Interrupt`：往唤醒管道写一个字节（可重复）；用户关闭时另发 `FpKill(-pid, SIGHUP)`（整个会话）。
  - `ExitCode(AWaitMs)`：`FpWaitPid(pid, @st, WNOHANG)` 轮询到 `AWaitMs`；正常退出 → `WEXITSTATUS`；被信号杀 → `128 + WTERMSIG`；还没退出 → -1。已经收过就直接答记下的值。
  - `Shutdown`：还没收子进程 → `SIGHUP`、等 1 s、`SIGKILL`、`FpWaitPid`；关主端、唤醒管道两端。

- [ ] **Step 2: `tools/terminal-ptytest/ptytest.lpr`**（纯 FPC 控制台程序；`uses cthreads, Classes, SysUtils, SyncObjs, BaseUnix, uptysession, uptyunix;` 第一个必须是 `cthreads`）。每个用例：建后端 + 会话，`OnWake` 置一个 `TEvent`；主循环等事件（100 ms 超时）→ `Pump` → 累加输出 → 立即 `Delivered`（背压用例除外）→ 直到结束或 10 s 超时。打印 `PASS <名字>` / `FAIL <名字>: <原因>`，最后一行 `ptytest: N passed, M failed`，退出码 = M。

| 用例 | 命令 | 判据 | 在哪个变异下必须红 |
|---|---|---|---|
| T1 输出 | `echo tyterm-ok` | 输出含 `tyterm-ok`、退出码 0 | — |
| T2 退出码 | `exit 7` | 7 | Y20：答原始 status（1792） |
| T3 初始尺寸 | `stty size`（80 × 24 起） | 输出含 `24 80` | Y21：初始尺寸没设 |
| T4 改尺寸 | `sleep 0.5; stty size`，起来后立刻 `Resize(100, 30)` | 含 `30 100` | Y22：`Resize` 的 ioctl 打在唤醒管道上 |
| T5 大输出与背压 | `head -c 2000000 /dev/zero \| tr '\0' x`；高水位 256 KB，主循环每 `Pump` 后睡 20 ms 再 `Delivered` | 收到的 `x` 恰好 2000000 个（输出里没有换行，不受 ONLCR 影响）；`MaxOutstanding ≤ 256 KB + 64 KB` | Y23：读线程不看水位 |
| T6 关闭不挂 | `sleep 100`，起来 300 ms 后 `Close` | `Close` 2 s 内返回；之后 `FpKill(pid, 0)` 失败（`ESRCH`，已收走） | Y24：`Read` 只 poll 主端（关闭时挂住，超时 FAIL） |
| T7 环境 | `echo $TERM` | `xterm-256color` | Y25：`envp` 没加 `TERM` |
| T8 控制终端 | `cut -d' ' -f7 /proc/$$/stat` | 输出的 `tty_nr` 不是 0 | Y26：子进程没 `setsid` / `TIOCSCTTY` |
| T9 找不到命令 | `no-such-command-tyterm` | 退出码 127，不挂 | — |

- [ ] **Step 3: 在 WSL 里编跑**（实现 agent 做，主文件「WSL 侧」命令）。全过才提交；某条在 WSL1 上确实跑不了（不是代码的错），`ptytest` 里标 `SKIP <名字>: WSL1 …`、写进提交说明、记进真机项第 36 项。Y20–Y26 的变异期末在 WSL 里做（Task 18 Step 6）。

- [ ] **Step 4: 提交**

```bash
cd /d/Projects/ty-3.1 && git add examples/terminal/uptyunix.pas tools/terminal-ptytest && git commit -m "feat(terminal-example): Linux and macOS shells through posix_openpt

posix_openpt, grantpt, unlockpt and ptsname come from the C library on
both systems, so nothing links libutil. Everything the child needs is
prepared before fork, and the child makes system calls only: a new
session, the terminal as its controlling tty, exec. Reads and writes
poll a wake-up pipe too, so closing never waits on a blocked call.
tools/terminal-ptytest runs the backend in WSL without the LCL.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 16: 示例的「Shell」模式

**Files:**
- Modify: `examples/terminal/umain.pas`、`examples/terminal/umain.lfm`、`examples/terminal/terminal_example.lpi`（加四个单元）
- Create: 示例译文 json（Task 18 主控跑 `example-rsj2po.py` 用；放 `examples/terminal/languages/terminal_example.zh_CN.json`，照 3 期的做法，若 3 期没留 json 就写在提交说明里）

- [ ] **Step 1: `.lfm`**（[[demo-edits-lfm-not-code]]；全用库控件、`AutoSize`，地雷 20）：`Tools1` 行最前面加模式下拉 `CmbMode`（回放 / Shell）；新增一行 `Tools3`（只在 Shell 模式显示）：命令下拉 `CmbCommand`（可编辑）、`BtnStart`（启动 / 重启）、`ChkLogPty`（记录 PTY 输出）；`Tools2` 行加 `ChkCopyOnSelect`、`ChkDetectUrls`（默认勾）、OSC 52 下拉 `CmbOsc52`（关 / 只写 / 读写）。`Term` 上把 `DetectUrls`、`Osc52`、`CopyOnSelect` 的初值写在 `.lfm` 里。

- [ ] **Step 2: `umain.pas`**：
  - 单元头注释补「Shell 模式」一段：宿主做的三件事在这里怎么落（`ushell`），PTY 单元只在示例里（spec §12.2）。
  - 命令下拉的候选（开工前问题一第 4 条）：Windows `%COMSPEC%`（默认）、`powershell.exe`、`pwsh.exe`、`wsl.exe`（后两个 `FileSearch` 在 `PATH` 里找得到才列）；Unix `$SHELL -l`（默认；`$SHELL` 为空用 `/bin/sh`）。
  - 模式切换：到 Shell → 停播放器、`Core.DiscardPending`、`Term.Reset`、建 `TTerminalShell`（Windows `TConPtyBackend`，Unix `TUnixPtyBackend`）并启动；启动失败 → 状态栏提示、留在回放模式。到回放 → `Shell.Stop`、`ReadOnly := True`、`Core.WindowsPty := (twpNone, 0)`。`BtnStart` = 停了再起（重启）。
  - `Shell.OnData` → 键码面板（沿用 `TermData` 的格式）；`ChkLogPty` 勾着时 `Shell.OnOutput` 把每次到的字节按十六进制、`<` 开头加进面板，**一次会话最多记 4096 字节**，满了加一行「（已停止记录）」（「Win32InputMode 与 ConPTY 鼠标：结论」的观察用）。
  - `Term.OnLinkActivate`：http / https → `TyMessageDlg(Format(rsOpenLinkFmt, [uri]), mtConfirmation, [mbYes, mbNo])`，是 → `OpenURL(uri)`；其他协议 → 状态栏 `Format(rsLinkNotOpenedFmt, [uri])`（照上游 OSC 8 的默认：确认框、非 http(s) 不开）。
  - `Term.OnOsc52`：写 → 允许，状态栏 `Format(rsClipboardSetFmt, [UTF8Length(AText)])`；读 → `TyMessageDlg(rsAllowClipboardRead, mtConfirmation, [mbYes, mbNo]) = mrYes`。
  - `Shell.OnExit` → 状态栏 `Format(rsShellExitedStatusFmt, [code])`、`BtnStart` 标题换成「重启」。
  - 关窗：`FormDestroy` 先 `Shell.Free`（`Stop` 在里面）再别的。
  - 新 resourcestring（英文原文；译文进 json）：模式两项、命令、启动、重启、记录 PTY 输出、已停止记录、复制即选中、识别网址、OSC 52 三项、`rsOpenLinkFmt = 'Open %s?'`、`rsLinkNotOpenedFmt = 'Not opened (only http and https): %s'`、`rsClipboardSetFmt = 'The program set the clipboard (%d characters)'`、`rsAllowClipboardRead = 'The program asks to read the clipboard. Allow it?'`、`rsShellExitedStatusFmt = 'Shell exited (%d)'`、`rsShellFailedFmt = 'Could not start: %s'`。
- [ ] **Step 2b: 示例带的库译文**：`examples/terminal/languages/tycontrols.zh_CN.po` 是库译文的一份子集（3 期从 `examples/memo/languages/` 拷来，里面没有右键菜单的字串）。把 `rstextmenucopy`、`rstextmenupaste`、`rstextmenuselectall`、`rsterminalmenuclear` 四条照 `languages/tycontrols.strconsts.zh_CN.po` 的写法（`#: tycontrols.strconsts.<名字>`、msgid、msgstr）追加进去，msgstr 不能空（地雷 21）——否则示例里的右键菜单是英文。

- [ ] **Step 3: 示例测试**（`TTyTerminalExampleTests` 加两条，示例单元已在测试搜索路径里）：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestTheShellUnitsCompileInTheTests` | `TTerminalShell`、`TPtySession` 的类能建（假后端），`ushell` 的 `rsShellExited` 里有 `%d` | — |
| `TestTheExampleProjectListsItsUnits` | `terminal_example.lpi` 的 `<Units>` 里有 `ushell.pas`、`uptysession.pas`、`uptywin.pas`、`uptyunix.pas`（读文件查） | X1：`.lpi` 漏一个单元 |

- [ ] **Step 4: 提交**（不编译；示例由主控编）

```bash
cd /d/Projects/ty-3.1 && git add examples/terminal && git commit -m "feat(terminal-example): a Shell mode next to the replay

Pick Shell and the example starts cmd (or PowerShell, pwsh, wsl where
found) through ConPTY on Windows, or the login shell elsewhere; the
window size follows to the PTY, links ask before opening a browser,
the program may set the clipboard and must ask to read it. A switch
logs the first bytes the PTY sends, for checking what ConPTY asks for.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 17: 控件文档、README、notices、截图工具

**Files:**
- Modify: `docs/controls/terminal.md`、`README.md`、`README.en.md`、`THIRD-PARTY-NOTICES.md`、`tests/test.release.pas`
- Modify: `tools/terminal-shots/*`（加三组截图，由主控在 Task 18 跑）

- [ ] **Step 1: `docs/controls/terminal.md`**（照现有十节的结构，[[doc-writing-native-tone]]）：
  - §3：published 加 `SelectionOverrideKey`、`Osc52`、`WordSeparators`、`CopyOnSelect`、`DetectUrls`、`AllowNonHttpLinks`、`PopupMenu`；public 加 `SelectionText`、`HasSelection`；方法加 `SelectAll`、`ClearSelection`、`Select`、`SelectLines`，`CopyToClipboard` 改说明；事件加 `OnLinkActivate`、`OnOsc52`、`OnSelectionChange`。
  - §4：「控件接管的 Core 事件」加 `OnUserInput`；读线程到主线程的做法指向示例的 `uptysession`。
  - 新增三节（放在「滚回与滚动条」之后）：**鼠标与选区**（「谁拿鼠标」表的读者版；覆盖键；多击；列选；自动滚；何时清选区；复制规则；PRIMARY）、**链接**（两种来源、Ctrl / Cmd、控件不打开任何东西、`AllowNonHttpLinks`、宿主该做的确认）、**剪贴板与 OSC 52**（三种策略、默认关的理由、事件在解析中同步发）。
  - §8 代码示例加「接一个 PTY」的骨架（指向 `examples/terminal/ushell.pas`，写清三件事：`OnData` → PTY、输出 → `Write` 带回调、`OnGridResize` → 改尺寸；Windows 设 `Core.WindowsPty`）。
  - §9 注意事项：OSC 52 读剪贴板是隐私问题；fork 之后只能系统调用；Wayland 下 PRIMARY 看合成器。
  - §10：4 期做完的从「限制」里删掉，5 期的留着。
- [ ] **Step 2: README**：两份的示例表 `terminal` 那一行改成「终端：asciicast 回放、真 shell（ConPTY / PTY）、换肤、键码面板」/「Terminal: asciicast replay, a real shell (ConPTY / PTY), skins, a key-code panel」。控件数不变。
- [ ] **Step 3: notices 与守卫**：`THIRD-PARTY-NOTICES.md` 的 xterm.js 一节标题加 `source/tyControls.Terminal.Selection.pas`、`source/tyControls.Terminal.Links.pas`；版权行加 addon-web-links（`Copyright (c) 2017, The xterm.js authors`，`addons/addon-web-links/LICENSE:1`）与 addon-clipboard（`Copyright (c) 2023, The xterm.js authors`，`addons/addon-clipboard/LICENSE:1`），共用同一段 MIT 正文。`test.release.pas` 的 `TheThirdPartyNoticeCoversTheTerminalPort` 的 `Units` 数组加这两个文件（长度 10 → 12），注释补一句 4 期。示例的 PTY 单元是自己写的，不进 notices。
- [ ] **Step 4: 截图工具**：`tools/terminal-shots` 加三组（照 3 期的离屏 `RenderTo` 做法，不建窗口）：一段带中英文与网址的输出上，（a）普通选区聚焦 / 失焦各一张，（b）列选区，（c）Ctrl+悬停网址的下划线；皮肤取默认浅色、默认深色、xp、macos；`index.md` 每张一句「看什么」。本任务只改工具、编过（`lazbuild -B tools/terminal-shots/*.lpi`，工具直接引 `source/`、不经 `.lpk`，照 3 期），**不跑、不提交截图**（Task 18 主控跑）。
- [ ] **Step 5: 提交**（不编译测试）

```bash
cd /d/Projects/ty-3.1 && git add docs/controls/terminal.md README.md README.en.md THIRD-PARTY-NOTICES.md tests/test.release.pas tools/terminal-shots && git commit -m "docs(terminal): mouse, selection, links, OSC 52 and hosting a shell

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: 段 4d 编译并跑本段 suite**（主文件「跑测试的固定套路」4d 行；`TTyTerminalPtyTests` 连跑三次）。只修本段的红。
