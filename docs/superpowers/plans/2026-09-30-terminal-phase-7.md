# 终端控件 7 期：数据流钩子与解析器钩子（示例里实现 ZModem）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（项目约定，优先于子技能的默认做法）**：整期**连续写完**——每个任务只写代码 + 测试并单独提交，任务之间**不编译、不跑 Pascal 测试**（例外写在各任务里：Task 0 的基线与实验工具、Task 4 跑 node 生成夹具、Task 7 在 WSL 里跑录制脚本——这几样产出要进 git）；Task 1–12 写完后在 Task 13 **一次编译**、跑本期 suite 和全量、集中修红、集中变异、期末整体审查（规格核对 + 代码质量）。中途不汇报、不问要不要提交。**用户要求 1–7 期一起真机验收**：本期的真机项与截图进验收材料，Task 14 并进 `2026-09-29-terminal-acceptance.md`，不另起一份、不中途找用户。
>
> **谁来做**：标 **【主控执行】** 的步骤实现 agent **不做**、直接跳过：问用户、编 `tycontrols.lpk` / `tycontrols_dt.lpk`、编示例、跑 `scripts/example-rsj2po.py`、截图、启动示例。实现 agent 不编任何 `.lpk`（可以改 `.lpk` 的文件清单）、不编示例（示例单元经测试工程的搜索路径编进 `tytests`，照 4 期先例）。
>
> **共享文件**：`source/tyControls.Base.pas`、`source/tyControls.Painter.pas`、`source/tyControls.StyleModel.pas`、`source/tyControls.TextMenu.pas` 本期**不改**，别的全库共用文件（`StrConsts.pas`、设计期单元）也不改。执行中发现非改不可，停下交主控，主控先问用户。

**Goal:** 控件不内置任何带内协议，但宿主不改控件就能实现 ZModem 这类「程序在输出里嵌一段二进制协议」的东西：Core 在解析器之前开一个数据流钩子（检测、接管、交还），解析器钩子照 xterm.js 的 `IParser` 公开；示例用这两样实现 ZModem 收发，与真实 lrzsz 互通。

**Architecture:** 钩子全在 Core（不依赖 LCL）：写入队列每取一段、交给解码器之前，先问挂着的处理器 `Detect`；有人接管就把后续原始字节交给它的 `Feed`，解析器与屏幕不动，块的回调照常；处理器经 Core 持有的会话对象 `SendRaw` / `Release(剩余字节)` / `ShowText`。接管期间 Core 把「用户输入」改发 `OnClaimedInput`、把自己发起的报告丢掉；控件只转发、并在接管期间按「程序没要鼠标」处理。解析器钩子是 Core 上照 `ParserApi.ts` 的一层包装，底下就是 2 期已对上游比过的注册链。ZModem 在示例里分三层：纯编解码、收发状态机、终端胶水（后两层不引 LCL，测试与 WSL 控制台工具直接用）；Windows 上 ConPTY 会改坏二进制，示例加一个不经 ConPTY 的管道后端。

**Tech Stack:** FPC 3.2.2 / Lazarus LCL、fpcunit；node + xterm.js 6.0.0 headless（解析器钩子的基准，`tools/terminal-oracle/`）；WSL `Ubuntu` 里的 lrzsz 0.12.21rc 与 `fpc`（互通与 Unix PTY 路径）；Windows ConPTY（`examples/terminal/uptywin.pas`）。

**设计依据:** `docs/superpowers/specs/2026-09-28-terminal-view-design.md`（下称 spec）§19（本期新增，含核实记录与写计划时的预实验），以及 §2.1、§3、§7.4、§7.6、§9.2、§9.3、§12、§13.2、§14、§15、§16、§17、§18 里标「7 期新增（2026-09-30 用户拍板）」的几处。

**不在本期**：控件内置任何协议（ZModem、XMODEM、Kermit、iTerm2 / kitty 的文件传输 OSC）；续传（ZCRESUM 当从头传）；ZModem 的加密、压缩、ZCOMMAND；异步解析器处理器；win32-input-mode；CHANGELOG（发版时写，[[changelog-user-facing]]）；合 `main`（验收之后另定，[[pre-merge-checklist]]）。

---

## 总目录

| 部分 | 任务 | 这一批做完能看到什么（执行时不单独验收） |
|---|---|---|
| 基线与实验 | Task 0 | 起点、条数、用户对开工前问题一的答复；ConPTY / 管道两个方向的二进制实验结论 |
| 数据流钩子 | Task 1–3 | 假协议处理器能在任意切块下检测、接管、交还，流控不断，输入改道，与切片 / 延后 / `Reset` / `DiscardPending` 的每条交互都有判据 |
| 解析器钩子 | Task 4 | Core 上五个 `Register*Handler` 与上游逐位对上 |
| 控件 | Task 5 | `OnClaimedInput`、接管期间鼠标不上报 |
| ZModem | Task 6–8 | 编解码、收发状态机（环回 + 故障注入 + lrzsz 录制回放）、终端胶水 |
| 管道后端与互通 | Task 9–10 | Windows 经管道、WSL 经 Unix PTY 与真 lrzsz 收发一致 |
| 示例 | Task 11 | 「ZModem」「Pipe」开关、传输条、选目录 / 选文件 |
| 文档与守卫 | Task 12 | 控件文档、发版守卫、截图工具 `--phase7` |
| 收尾 | Task 13 | 一次编译、全量、按 spec 逐条核、集中变异、主控编包编示例截图、审查、写回 spec、签收 |
| 验收文档 | Task 14 | 1–7 期合在一份验收文档里 |

---

## 核实记录（写计划时读源码 / 实跑，2026-09-30）

上游语义、ZModem 出处与许可、写计划时的预实验写在 spec §19.2，这里不重复，只补代码侧的事实。行号是本仓库 `4dd29fac` 加 6 期修复 agent 当时的工作区（Core、Parser 两个单元修复没碰）。

**写入队列（`source/tyControls.Terminal.Core.WriteQueue.inc`）**

1. `ProcessOneChunk`（`:111-162`）：取队首块的下一段（切片时 `TyTermSlicePieceBytes` = 32 KB，清空时 `TyTermMaxParseBuffer` = 128 KB），**先**推进 `FChunkPos`、减 `FPendingData`，最后一段先 `TakeHead`，再 `ParseRange(data, start + 1, n)`；`finally` 里处理「前一段抛异常、这一块剩下的算已处理」，最后一段调回调、`RunDeferred`。**拦截点就放在 `ParseRange` 这一句**：没挂处理器、没人接管、交还缓冲为空时原样调 `ParseRange`（快路径），否则走新的 `StreamPiece(data, start + 1, n)`。
2. `InnerWrite`（`:164-208`）的循环条件是 `FQueueCount > FBufferOffset`、`FlushSync`（`:256-280`）是 `FBufferOffset < FQueueCount`、`ClearQueue`（`:44-56`）清队列；交还缓冲要并进这三处的「还有没有东西」判断，`DiscardPending`（`:226-231`）经 `ClearQueue` 连它一起丢。
3. 延后与重入：`FBusy`（`Core.pas:247`）在 `ParseRange`（`Core.InputHandler.inc:20-60`）里加减；`Resize`（`Core.Services.inc:588-612`）、`Reset`（`:615-632`）、`WriteSync`（`WriteQueue.inc:238-254`）见到 `FBusy > 0` 就 `Defer`；`ProcessPending`（`:210-224`）在忙时返回 False 并记 `FRerequest`。`Detect` / `Claimed` / `Feed` 不在 `ParseRange` 里，**必须自己包一层 `Inc(FBusy)` / `Dec(FBusy)`**，否则处理器引出的 `Resize` 会在 `Feed` 里当场 `FlushSync`，把后面的块递归喂进来（地雷 1）。
4. `RunDeferred`（`:311-333`）在 `FChunkPos > 0`（半块）时不跑，块的最后一段之后才跑——接管不改这条。

**输入与报告（`source/tyControls.Terminal.Core.Services.inc`）**

5. `TriggerDataEvent`（`:33-53`）：`DisableStdin` 早退 → 用户输入且不在底部就滚到底 → `OnUserInput` → `FDidUserInput := True` → `OnData`。改道放在早退之后、滚到底之前。`TriggerBinaryEvent`（`:56-`）是默认编码的鼠标报告。`ReportFocusNow`（`:376-383`）发 `CSI I` / `CSI O`，`NotifyColorSchemeChanged`（`:364-374`）发 2031；OSC 颜色应答（`:320`）、DA / DSR 等只可能从解析器里来——接管期间解析器不跑，它们自然没有。
6. `TriggerMouseEvent`（`:250-`）：接管期间直接返回 False。控件的 `Reporting`（`source/tyControls.Terminal.View.Mouse.inc:122-125`）只看 `FCore.Modes.MouseProtocol`，要加「且没被接管」；滚轮翻方向键在同一文件 `:49-62`，走 `FCore.Input(…, True)`，接管时自然进 `OnClaimedInput`。

**解析器（`source/tyControls.Terminal.Parser.pas`）**

7. `Register*` / `Unregister` / `Clear*` / `Set*Fallback`（`:353-378`）；句柄从 1 起递增（`NewHandle`，`:1780-1784`）；标识校验 `IdentOf`（`:1814-1846`）抛 `EArgumentException`，消息照上游。`DispatchCsi`（`:2017-2035`）每轮重读 `list.Items[j]`，派发中 `Add` 引起的 `SetLength` 不会读到旧数组。OSC 的 `Finish`（`:1469-1508`）只在 `ActiveCount = 0` 时调回退——即「链非空不进 `OnOsc`」，和上游同。
8. 字符串处理器 `TTyTerminalOscStringHandler` / `TTyTerminalDcsStringHandler` / `TTyTerminalApcStringHandler`（`:165-238`）收的回调类型是 `TTyTerminalOscDataEvent`（`function(const AData: string): Boolean of object`）与 `TTyTerminalDcsDataEvent`；CSI / ESC 的 `TTyTerminalCsiEvent` / `TTyTerminalEscEvent`（`:130-132`）本来就是方法指针。`TTyTerminalParams.ToJson`（`:84`）= `JSON.stringify(toArray())`，基准直接比串。
9. Core 在构造时注册全部内置处理器（`Core.pas:926-`，`RegisterHandlers`），`Core.Parser` 公开（`:548`）。上游的 `ParserApi`（`xterm:src/common/public/ParserApi.ts`）只是包装，headless 的 `terminal.parser` 可以直接在 node 里用（`xterm:src/headless/public/Terminal.ts:77-80`）——基准脚本就用它。

**控件与示例**

10. 控件的 `Write` / `WriteSync` / `Paste` / `Input` / `Reset`（`source/tyControls.Terminal.pas:2905-2963`）都转 Core；`CoreData`（`:938-941`）转宿主的 `OnData`。接管期间的按键、粘贴不用改控件：它们都经 `FCore.Input(…, True)`（`:2942`、`:2949`、`:3137`、`:3204`、`:3256`）。
11. 示例的会话（`examples/terminal/uptysession.pas`）有 `PendingWrite`（「FOR THE TESTS」，排着还没交给写线程的字节，`:180` 附近）——上传节流要用它，本期把注释改成正式用途。后端基类 `TPtyBackend`（`:62-95`）；`TPipeBackend`（`uptywin.pas:47-66`）读写一对现成句柄，`TConPtyBackend` 建伪控制台再起进程（`:369-`，`STARTF_USESTDHANDLES`、`CreateProcessW`）。新后端 `TProcessPipeBackend` 照 `TConPtyBackend` 的起进程与收尾写法，只是不建伪控制台。
12. `TTerminalShell`（`examples/terminal/ushell.pas`）把会话接到控件，`Stop`（`:150-173`）先摘钩子再 `DiscardPending`；示例「重启」（`umain.pas:706-711`）先 `DiscardPending` 再 `Reset` 再起新会话。
13. 库里现成的：`TTySelectPathDialog`（`source/tyControls.Dialogs.SelectPath.pas:75-89`，`Execute` / `Directory`）、`TTyOpenDialog`（`Dialogs.FileDialog.pas:212`）、`TTyProgressBar`。fpcunit 的 `Ignore(...)` 在测试里已有先例（`tests/test.painter.pas:345`）。
14. 发版守卫 `TheThirdPartyNoticeCoversTheTerminalPort`（`tests/test.release.pas:572-624`）：移植的文件进 notices 标题；自己写的 include（`ViewIncludes`）只查随包发出。`TestTheExampleProjectListsItsUnits`（`tests/test.terminal.example.pas:319-`）查示例 `.lpi` 列了哪些单元。
15. 工具先例：`tools/terminal-conpty-record/conptyrecord.lpr`（Windows 控制台，直接 `fpc` 编，用示例的会话录 ConPTY 输出）、`tools/terminal-ptytest/ptytest.lpr`（WSL 里 `fpc` 编，跑 Unix 后端）。

---

## 开工前要定的问题

每条都给了建议，**计划正文按建议写**；改了哪条，执行时改对应任务，收尾时（Task 13）写回 spec §19 原处。第一类由主控在 Task 0 问用户；用户没回复前按建议做（和 3–6 期一样，一起验收时仍可改）。用户 2026-09-30 已定的四条（spec §19.1）不在这里重问。

### 一、产品方向 / 用户可见（问用户）

> **状态（2026-09-30）**：六条先按建议执行（Windows 加 Pipe 模式、ConPTY 下提示并中止；每次选下载目录、重名自动改名、清理远端文件名；取消/失败删掉半截文件；检测到后先问；进度在终端一行 + 底部传输条；「ZModem」勾选默认开），已告知用户，最终一次性验收时可改。第二类主控按建议采纳（含：处理器用抽象类而非接口；§7.4 改为经 Core 新方法注册）。

> **状态**：未单独答复，按建议执行（用户 2026-09-30 同意 7 期整体方案、要求在示例里实现 ZModem），一起验收时可改。

1. **Windows 上 ZModem 走哪条路？**
   写计划时的预实验（spec §19.2 第 12 条）：经 ConPTY，`0x80` 以上的字节和 NUL 直接丢了，输出还被重新渲染（多出清屏、光标定位）；经普通管道原样。ZModem 的数据几乎一定含这些字节，所以经 ConPTY 传不了（Task 0 用正式实验再确认一次，含输入方向）。
   - **A（建议）**：示例 Shell 那排加一个「Pipe」勾选：命令不经 ConPTY、用两条管道直接起（`wsl.exe -d Ubuntu -- sz 文件`、`ssh -T 主机` 这类用；没有终端，程序不回显，要看自己打的字就开「本地回显」）。默认的 ConPTY 下检测到 ZModem 时，终端里提示一行「ConPTY 会改坏二进制数据，ZModem 请改用管道模式」，并发中止序列让远端停下。
   - B：ConPTY 下也照样试（会校验错、重传到放弃，卡十几秒）。
   - C：不做管道模式，Windows 上不支持 ZModem，只在 Linux / macOS 上能用。
2. **下载存到哪、重名怎么办？**
   **建议**：每次传输开始时弹一次选目录（默认是上次用的，第一次是用户的「下载」文件夹），这一步本身就是确认；一次传多个文件都放那里。远端给的名字只取文件名部分、去掉 Windows 不许的字符。重名**不覆盖**，自动改名 `名字 (1).扩展名`。
   另外的做法：不问、固定存到「下载」；重名时逐个问覆盖 / 改名 / 跳过。
3. **取消或失败时，没收完的文件怎么办？** **建议删掉**。另一做法：留着、改名 `.part`。
4. **检测到 ZModem 后先不先问？** **建议问**：下载时就是第 2 条的选目录，上传时就是选文件；点「取消」等于拒绝，向远端发中止序列。另一做法：下载不问、直接存到默认目录。
5. **进度显示在哪？** **建议两处**：终端里一行（像 Xshell / SecureCRT 那样原地刷新，传完留一行摘要：文件数、大小、用时、速度），示例底部一排传输条（名字、进度条、「取消」按钮，平时隐藏）。另一做法：只用传输条，终端里什么都不写。
6. **自动识别能不能关？** **建议** Shell 那排加一个「ZModem」勾选，默认开；关掉后 `sz` 的字节照原样显示成乱码（和没有这个功能的终端一样）。

### 二、实现层面（主控定）

1. **处理器用抽象类、不用 COM 接口**（spec §19.3 末段写了理由）：`TTyTerminalStreamHandler` 由宿主继承，Core 不拥有；会话 `TTyTerminalStreamSession` 由 Core 持有、只有一个、和 Core 同寿命。主控原先提议的 `ITyTerminalStreamHandler` / `ITyTerminalStreamSession` 名字不用。
2. **拦截点**在 `ProcessOneChunk` 的 `ParseRange` 那一句（核实记录 1），解码之前，按段（32 KB / 128 KB）问。**不扣留段尾**：标记跨段时前半截先显示，处理器自己记着（spec §19.4）。
3. **多个处理器**：每段问全部，`AClaimAt` 最小的胜出，同一位置后挂的优先；没胜出的不通知。
4. **交还的字节再走 `Detect`**；一次接管一个字节都没吃就交还全部时，第一个字节直接解析（防死循环）。在 `Feed` 外 `Release`：字节进交还缓冲、`RequestProcess`，下一片处理。
5. **`ShowText`**：独立的 `TTyUtf8Decoder`，当场解析；解析器正在跑时（只可能是它自己引出的事件里又调）攒着，外层解析返回后接着解析。
6. **`Reset` 结束接管**（先 `ClaimEnded(tceReset)`）；**`DiscardPending` 不结束接管**，交还缓冲一起丢；`Resize` 不影响；`RemoveStreamHandler` 正在接管的那个先 `ClaimEnded(tceRemoved)`；Core 析构不回调。
7. **接管期间**：`AWasUserInput` 的输入改发 `OnClaimedInput`（不滚到底、不发 `OnUserInput`、不设 `FDidUserInput`）；Core 自发的（焦点、2031、默认编码鼠标、`AWasUserInput = False` 的 `Input`）丢掉；`TriggerMouseEvent` 返回 False；`ReadOnly` 时两样都不发、`SendRaw` 返回 False。
8. **解析器钩子**：Core 上五个 `Register*Handler` + `UnregisterHandler`，Core 记下自己发出的句柄，`UnregisterHandler` 只认这些（防宿主误删 Core 的内置处理器）；`AHandler = nil` 抛 `EArgumentNilException`；OSC 编号 < 0 抛 `EArgumentOutOfRangeException`；参数借用。
9. **ZModem 在示例里三个单元**（spec §19.7 表）：`uzmodem.pas`、`uzmodemsession.pas` 只引 `SysUtils` / `Classes`；`uzmodemterm.pas` 再引 `tyControls.Terminal.Core`，不引 LCL。自己写，单元头写规范出处（Forsberg，Rev Oct-14-88）与「不含 lrzsz 的代码（GPL）」。
10. **ZModem 裁剪**：照 spec §19.7「范围」；收子包上限 8192、发 1024；CRC32 优先（我们的 ZRINIT 带 CANFC32）；我们的 ZRINIT 的 ZF0 = `CANFDX | CANOVIO | CANFC32`（`$23`，和 lrzsz 的 `rz` 一样——录制回放因此可比）、缓冲大小 0（全流式）。
11. **超时**：10 秒、同一处重试 10 次；时钟由宿主经 `Tick(ANowMs)` 驱动（示例 100 ms 的 `TTimer`，测试注入）。
12. **上传节流**：胶水问宿主 `CanSend`（还能再交多少字节），示例答 `256 KB − Session.PendingWrite`；每次 `Tick` 与每次收到对方数据时补发。
13. **管道后端**：`TProcessPipeBackend(AMergeStderr: Boolean = True)` 放 `uptywin.pas`；stderr 默认并进同一管道（交互式 `bash -i` 的提示符在 stderr 上），测试用 `False`（stderr 进 `NUL`）。`Resize` 什么都不做；`IsConPty` 答 False。
14. **测试单元**：`tests/test.terminal.stream.pas`（`TTyTerminalStreamTests`）、`tests/test.terminal.hooks.pas`（`TTyTerminalHookOracleTests`、`TTyTerminalHookTests`）、`tests/test.terminal.view.stream.pas`（`TTyTerminalViewStreamTests`）、`tests/test.terminal.zmodem.pas`（`TTyTerminalZmodemTests`）、`tests/test.terminal.zmodem.wsl.pas`（`TTyTerminalZmodemWslTests`）；夹具 `tests/fixtures/terminal-core-hooks.json`、`tests/fixtures/terminal-zmodem/`（`.gitattributes` 给 `-text`）。
15. **录制夹具的来源**：WSL 里让 `sz` 与 `rz` 直接对传（两个 FIFO + `tee`），录下双方各自发的字节——不经过我们的代码，所以能当收发状态机的半个基准（spec §19.9）。

---

## 需要改共享文件的地方

**结论：不改。** 四个共享文件、`StrConsts.pas`、设计期单元都不涉及：库里没有新的用户可见文字（异常消息是英文，照 Core 的先例不进 `resourcestring`），`OnClaimedInput` 是控件自己的 published 事件。

**会改的终端文件**：`Terminal.Core.pas`（声明）、新 `Terminal.Core.Stream.inc`（实现）、`Terminal.Core.WriteQueue.inc`（拦截点与交还缓冲）、`Terminal.Core.Services.inc`（输入改道、报告丢弃、鼠标）、`Terminal.pas` 与 `Terminal.View.Mouse.inc`（转发、鼠标）。Parser、Buffer、Render 等不改。

---

## 接口清单（全计划用这一套名字）

### `source/tyControls.Terminal.Core.pas`（改；实现在新 `tyControls.Terminal.Core.Stream.inc`）

```pascal
type
  TTyTerminalCore = class;
  TTyTerminalStreamSession = class;

  { spec 19.3: a claim that the handler did not end itself }
  TTyTerminalClaimEnd = (tceReset, tceRemoved);

  { In-band protocol hook (spec 19.3). The host derives from it and hands it to
    AddStreamHandler; the core does not own it (remove it before freeing it). Main
    thread only. }
  TTyTerminalStreamHandler = class
  public
    { The program's raw bytes (not decoded) are about to reach the parser. True with
      AClaimAt in 0..ACount: claim from there; the bytes before it are parsed first.
      Asked only while nobody claims. A marker cut between two pieces is the handler's
      to remember -- the earlier piece is already on screen. }
    function Detect(AData: PByte; ACount: Integer; out AClaimAt: Integer): Boolean; virtual; abstract;
    { the claim starts; everything before AClaimAt has been parsed. ASession stays
      Active until the claim ends. Default: nothing. }
    procedure Claimed(ASession: TTyTerminalStreamSession); virtual;
    { the program's output while claimed, in order; the first call is the rest of the
      piece Detect saw (none when AClaimAt = ACount) }
    procedure Feed(AData: PByte; ACount: Integer); virtual; abstract;
    { the host ended the claim (Reset, RemoveStreamHandler), not Release. Default:
      nothing. }
    procedure ClaimEnded(AHow: TTyTerminalClaimEnd); virtual;
  end;

  { One per core, for the core's life; Active only during a claim. Every method is a
    no-op (SendRaw answers False) when not Active. }
  TTyTerminalStreamSession = class
  private
    FCore: TTyTerminalCore;
    FHandler: TTyTerminalStreamHandler;
    FActive: Boolean;
  public
    { straight to OnData: no key encoding, no scroll to the bottom, no OnUserInput, not
      "the user just typed". False under ReadOnly, without OnData, or not Active. }
    function SendRaw(const AData: RawByteString): Boolean;
    { ends the claim; ALeftover (bytes the handler took but that are not its own) goes
      back in front of everything not parsed yet: through Detect again, then the parser }
    procedure Release(const ALeftover: RawByteString = '');
    { UTF-8 text (control sequences allowed) on the screen, not sent: parsed now with a
      decoder of its own; while the parser runs (an event of its own parse) it waits
      for that parse to return }
    procedure ShowText(const AText: string);
    property Active: Boolean read FActive;
    property Core: TTyTerminalCore read FCore;
    property Handler: TTyTerminalStreamHandler read FHandler;
  end;

  { in TTyTerminalCore, public: }
    procedure AddStreamHandler(AHandler: TTyTerminalStreamHandler);     { again: ignored }
    procedure RemoveStreamHandler(AHandler: TTyTerminalStreamHandler);  { unknown: ignored }
    property StreamHandlerCount: Integer read GetStreamHandlerCount;
    property StreamClaimed: Boolean read GetStreamClaimed;
    property ClaimingHandler: TTyTerminalStreamHandler read GetClaimingHandler;
    property StreamSession: TTyTerminalStreamSession read FStreamSession;
    property OnClaimedInput: TTyTerminalDataEvent read FOnClaimedInput write FOnClaimedInput;
    { spec 19.6, after xterm.js's ParserApi: the newest is tried first, True stops,
      False tries the one before, the core's own last. OSC / DCS / APC: once, on a
      successful end, payload up to 10 MB. The params are borrowed (Clone to keep). }
    function RegisterCsiHandler(const AId: TTyTerminalFunctionId; AHandler: TTyTerminalCsiEvent): Integer;
    function RegisterEscHandler(const AId: TTyTerminalFunctionId; AHandler: TTyTerminalEscEvent): Integer;
    function RegisterOscHandler(AIdent: Integer; AHandler: TTyTerminalOscDataEvent): Integer;
    function RegisterDcsHandler(const AId: TTyTerminalFunctionId; AHandler: TTyTerminalDcsDataEvent): Integer;
    function RegisterApcHandler(const AId: TTyTerminalFunctionId; AHandler: TTyTerminalOscDataEvent): Integer;
    { only handles these five gave out; anything else (the core's own) is ignored }
    procedure UnregisterHandler(AHandle: Integer);
    { FOR THE TESTS (pure queries) }
    property StreamPiecesOffered: Int64 read FStreamPiecesOffered;   { pieces that took the slow path }
    property StreamDetectCalls: Int64 read FStreamDetectCalls;
```

私有字段（写进 `Core.pas` 的类声明，名字固定，测试的判据里要用到其中几个的效果）：`FStreamHandlers: array of TTyTerminalStreamHandler`、`FStreamCount: Integer`、`FClaim: TTyTerminalStreamHandler`、`FStreamSession: TTyTerminalStreamSession`、`FFront: RawByteString`（交还缓冲）、`FFrontPos: Integer`、`FClaimFed: Int64`（这次接管收到的字节数，防死循环用）、`FShowDecoder: TTyUtf8Decoder`、`FShowPending: RawByteString`、`FParsing: Integer`（`ParseRange` 与 `ShowText` 的解析深度）、`FUserHandles: array of Integer`（`Register*Handler` 发出的句柄）、`FOnClaimedInput`。

### `source/tyControls.Terminal.pas`（改）

```pascal
  { TTyTerminalView, public }
    procedure AddStreamHandler(AHandler: TTyTerminalStreamHandler);
    procedure RemoveStreamHandler(AHandler: TTyTerminalStreamHandler);
    property StreamClaimed: Boolean read GetStreamClaimed;
  published
    property OnClaimedInput: TTyTerminalDataEvent read FOnClaimedInput write FOnClaimedInput;
```

### `examples/terminal/uzmodem.pas`（新：编解码）

```pascal
const
  ZPAD = $2A; ZDLE = $18; ZDLEE = $58; ZBIN = $41; ZHEX = $42; ZBIN32 = $43;
  ZRQINIT = 0; ZRINIT = 1; ZSINIT = 2; ZACK = 3; ZFILE = 4; ZSKIP = 5; ZNAK = 6;
  ZABORT = 7; ZFIN = 8; ZRPOS = 9; ZDATA = 10; ZEOF = 11; ZFERR = 12; ZCRC = 13;
  ZCHALLENGE = 14; ZCOMPL = 15; ZCAN = 16; ZFREECNT = 17; ZCOMMAND = 18; ZSTDERR = 19;
  ZCRCE = $68; ZCRCG = $69; ZCRCQ = $6A; ZCRCW = $6B; ZRUB0 = $6C; ZRUB1 = $6D;
  { ZRINIT ZF0 }
  CANFDX = $01; CANOVIO = $02; CANBRK = $04; CANCRY = $08; CANLZW = $10; CANFC32 = $20;
  ESCCTL = $40; ESC8 = $80;
  ZmMaxRecvSubpacket = 8192;
  ZmSendSubpacket = 1024;
  { what lrzsz sends to abort, as seen on the wire (spec 19.2 item 11) }
  ZmAbortSequence = #24#24#24#24#24#24#24#24#24#24#8#8#8#8#8#8#8#8#8#8;

type
  TZmHeaderKind = (zhkHex, zhkBin16, zhkBin32);
  { P[0..3] = ZP0..ZP3 = ZF3..ZF0: a position little-endian, flags ZF0 in P[3] }
  TZmHeader = record
    FrameType: Byte;
    P: array[0..3] of Byte;
  end;

  { an advanced record: the unit switches advancedrecords on, as Core does }
  TZmEscaper = record
    EscCtl: Boolean;          { the peer asked for ESCCTL: every control character }
    LastSent: Byte;           { CR after '@' is escaped (telnet), so this carries }
    procedure Init(AEscCtl: Boolean);
    function Escape(AData: PByte; ACount: Integer): RawByteString;
  end;

function ZmCrc16(ACrc: Word; AData: PByte; ACount: Integer): Word;          { XMODEM, $1021, MSB first }
function ZmCrc32(ACrc: Cardinal; AData: PByte; ACount: Integer): Cardinal;  { reflected $EDB88320; caller starts at $FFFFFFFF and inverts }
function ZmPosHeader(AType: Byte; APos: Cardinal): TZmHeader;
function ZmFlagsHeader(AType, AF0, AF1, AF2, AF3: Byte): TZmHeader;
function ZmHeaderPos(const AHeader: TZmHeader): Cardinal;
function ZmEncodeHexHeader(const AHeader: TZmHeader): RawByteString;
function ZmEncodeBinHeader(const AHeader: TZmHeader; ACrc32: Boolean; var AEsc: TZmEscaper): RawByteString;
function ZmEncodeSubpacket(AData: PByte; ACount: Integer; AEnd: Byte; ACrc32: Boolean;
  var AEsc: TZmEscaper): RawByteString;
{ 'name'#0'size mtime mode serial filesleft bytesleft'#0 -- size decimal, mtime / mode octal }
function ZmBuildFileInfo(const AName: string; ASize, AMTime: Int64; AFilesLeft: Integer; ABytesLeft: Int64): RawByteString;
function ZmParseFileInfo(const AData: RawByteString; out AName: string; out ASize, AMTime: Int64;
  out AMode: Cardinal): Boolean;

type
  TZmReaderHeaderEvent = procedure(const AHeader: TZmHeader; AKind: TZmHeaderKind) of object;
  TZmReaderDataEvent = procedure(const AData: RawByteString; AEnd: Byte; ACrcOk: Boolean) of object;

  { byte-at-a-time frame reader: headers anywhere in garbage; after a binary ZDATA /
    ZFILE / ZSINIT / ZCOMMAND header, data subpackets in that header's CRC until one
    ends ZCRCE or ZCRCW. Unescaped XON / XOFF (with or without the high bit) are
    dropped; five ZDLE (CAN) in a row is the peer aborting. }
  TZmReader = class
  public
    { consumes AData[0..ACount-1] until Stop is called from an event; answers how many
      bytes were consumed }
    function Push(AData: PByte; ACount: Integer): Integer;
    procedure Stop;                 { from an event: Push returns right after this byte }
    procedure ExpectData(ACrc32: Boolean);   { e.g. after a ZDATA the receiver accepts }
    procedure DropData;             { back to looking for headers (after sending ZRPOS) }
    property OnHeader: TZmReaderHeaderEvent;
    property OnData: TZmReaderDataEvent;
    property OnCancel: TNotifyEvent;
    property GarbageCount: Integer;  { bytes skipped looking for a header since the last one }
  end;
```

### `examples/terminal/uzmodemsession.pas`（新：收发状态机）

```pascal
type
  TZmResult = (zrOk, zrCancelledHere, zrCancelledThere, zrTimeout, zrError);
  TZmSendEvent = procedure(Sender: TObject; const AData: RawByteString) of object;
  TZmProgressEvent = procedure(Sender: TObject; const AName: string; AFileDone, AFileSize,
    ATotalDone: Int64) of object;
  { ALeftover: bytes after the session's end (after "OO", after the peer's ZFIN) }
  TZmDoneEvent = procedure(Sender: TObject; AResult: TZmResult; const AMessage: string;
    const ALeftover: RawByteString) of object;

  TZmFileSink = class          { the receiver writes through it }
  public
    { False = skip this file (ZSKIP); AName is the peer's, untouched }
    function Open(const AName: string; ASize, AMTime: Int64): Boolean; virtual; abstract;
    function Write(AData: PByte; ACount: Integer): Boolean; virtual; abstract;
    { AComplete False: cancelled or failed half way }
    procedure Finish(AComplete: Boolean); virtual; abstract;
  end;

  TZmFileSource = class        { the sender reads through it }
  public
    { the next file; False = none left. AStream belongs to the source. }
    function Next(out AName: string; out ASize, AMTime: Int64; out AStream: TStream): Boolean; virtual; abstract;
    function FilesLeft: Integer; virtual; abstract;
    function BytesLeft: Int64; virtual; abstract;
  end;

  TZmReceiver = class
  public
    constructor Create(ASink: TZmFileSink);
    procedure Start(ANowMs: Double);                 { sends ZRINIT }
    { consumed until the session ends; the rest reaches OnDone's ALeftover }
    procedure Input(AData: PByte; ACount: Integer; ANowMs: Double);
    procedure Tick(ANowMs: Double);                  { timeouts and retries }
    procedure Cancel;                                { ZmAbortSequence, then OnDone(zrCancelledHere) }
    property Done: Boolean;
    property OnSend: TZmSendEvent;
    property OnProgress: TZmProgressEvent;
    property OnDone: TZmDoneEvent;
    { options, before Start }
    property EscapeControl: Boolean;                 { advertise ESCCTL (tests); default False }
    property TimeoutMs: Integer;                     { default 10000 }
    property MaxRetries: Integer;                    { default 10 }
    property MaxSubpacket: Integer;                  { default ZmMaxRecvSubpacket }
  end;

  TZmCanSendFunc = function: Integer of object;       { bytes the host takes now }

  TZmSender = class
  public
    constructor Create(ASource: TZmFileSource);
    { AInit: the ZRINIT that started it (flags, buffer size) }
    procedure Start(const AInit: TZmHeader; ANowMs: Double);
    procedure Input(AData: PByte; ACount: Integer; ANowMs: Double);
    procedure Tick(ANowMs: Double);                  { timeouts; and more data if CanSend allows }
    procedure Cancel;
    property Done: Boolean;
    property CanSend: TZmCanSendFunc;                { nil = unlimited (tests) }
    property OnSend: TZmSendEvent;
    property OnProgress: TZmProgressEvent;
    property OnDone: TZmDoneEvent;
    property UseCrc32: Boolean;                      { default: when the ZRINIT has CANFC32 }
    property TimeoutMs: Integer;
    property MaxRetries: Integer;
  end;
```

### `examples/terminal/uzmodemterm.pas`（新：终端胶水，不引 LCL）

```pascal
type
  TZmodemState = (zsIdle, zsAskDownload, zsAskUpload, zsReceiving, zsSending, zsRefusing);
  TZmodemFinishedEvent = procedure(Sender: TObject; AResult: TZmResult; const AMessage: string) of object;

  TZmodemStreamHandler = class(TTyTerminalStreamHandler)
  public
    constructor Create(ACore: TTyTerminalCore);    { AddStreamHandler here, Remove in Destroy }
    destructor Destroy; override;
    function Detect(AData: PByte; ACount: Integer; out AClaimAt: Integer): Boolean; override;
    procedure Claimed(ASession: TTyTerminalStreamSession); override;
    procedure Feed(AData: PByte; ACount: Integer); override;
    procedure ClaimEnded(AHow: TTyTerminalClaimEnd); override;
    { the host's answers (any time after the request event, from a queued call) }
    procedure AcceptDownload(const ADirectory: string);
    procedure StartUpload(AFiles: TStrings);
    procedure Decline;                             { abort sequence, release }
    procedure Cancel;                              { same, mid-transfer too }
    { wire Core.OnClaimedInput here: five Ctrl+X (#24) in a row cancel }
    procedure UserInput(const AData: RawByteString);
    procedure Tick(ANowMs: Double);                { the host's timer (100 ms in the example) }
    property State: TZmodemState;
    property Enabled: Boolean;                     { False: Detect always answers False }
    { behind ConPTY (Core.WindowsPty.Backend = twpConPty): say so, abort, release }
    property RefuseBehindConPty: Boolean;          { default True -- Task 0 decides }
    property CanSend: TZmCanSendFunc;
    property Clock: TTyTerminalClock;              { nil = TyTermDefaultClock }
    property OnDownloadRequest: TNotifyEvent;      { ask for a directory, answer later }
    property OnUploadRequest: TNotifyEvent;        { ask for files, answer later }
    property OnProgress: TZmProgressEvent;
    property OnFinished: TZmodemFinishedEvent;
  end;

{ the last path element, Windows-forbidden characters and control characters as '_',
  trailing dots and spaces off, a reserved device name prefixed with '_', '' -> 'file' }
function ZmSafeFileName(const AName: string): string;
{ ADir + AName when free, else 'name (1).ext', 'name (2).ext' ... }
function ZmUniqueFileName(const ADir, AName: string): string;
{ finds a ZRQINIT / ZRINIT hex header with a good CRC; ACarry holds up to 20 bytes of a
  header cut at the end of the previous piece. Answers the header's type (-1 = none)
  and where its first '*' is (0 when it began in the carry). }
function ZmDetectHexStart(AData: PByte; ACount: Integer; var ACarry: RawByteString;
  out AAt: Integer): Integer;
```

### `examples/terminal/uptywin.pas`（改）

```pascal
  { a command on two anonymous pipes, no pseudo console (spec 19.7): binary safe }
  TProcessPipeBackend = class(TPipeBackend)
  public
    constructor Create(AMergeStderr: Boolean = True);
    function Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean; override;
    procedure Resize(ACols, ARows: Integer); override;       { nothing }
    procedure BeginClose; override;                          { closes the input pipe }
    function FinishClose(AWaitMs: Integer): TPtyCloseResult; override;
    function ExitCode(AWaitMs: Integer): Int64; override;
    procedure Shutdown; override;
    { FOR THE TESTS }
    property ProcessId: DWORD;
  end;
```

---

## 文件清单

| 文件 | 本期做什么 |
|---|---|
| `source/tyControls.Terminal.Core.pas` | 声明（Task 1、2、4） |
| `source/tyControls.Terminal.Core.Stream.inc` | **新建**（Task 1–4） |
| `source/tyControls.Terminal.Core.WriteQueue.inc` | 拦截点、交还缓冲（Task 1、2） |
| `source/tyControls.Terminal.Core.Services.inc` | 输入改道、报告丢弃、鼠标（Task 3） |
| `source/tyControls.Terminal.pas`、`source/tyControls.Terminal.View.Mouse.inc` | 转发、`OnClaimedInput`、鼠标（Task 5） |
| `tools/terminal-zmodem-probe/zmprobe.lpr` | **新建**（Task 0） |
| `tools/terminal-oracle/hook-cases.js`、`cases/hooks.js`、`lib-dump.js`、`regen-all.js` | 新建 / 登记（Task 4） |
| `tests/fixtures/terminal-core-hooks.json` | **生成**（Task 4） |
| `tools/terminal-oracle/zmodem-record.sh`、`zmodem-record.py` | **新建**（Task 7，WSL 里跑） |
| `tests/fixtures/terminal-zmodem/`、`.gitattributes` | **生成** / 加 `-text`（Task 7） |
| `examples/terminal/uzmodem.pas`、`uzmodemsession.pas`、`uzmodemterm.pas` | **新建**（Task 6–8） |
| `examples/terminal/uptywin.pas`、`uptysession.pas`（注释） | 改（Task 9） |
| `tools/terminal-zmodem-wsl/zmwsl.lpr` | **新建**（Task 10） |
| `examples/terminal/umain.pas`、`umain.lfm`、`ushell.pas`、`terminal_example.lpi`、`languages/terminal_example.zh_CN.json`（`.po` 由主控生成） | 改（Task 11） |
| `tests/test.terminal.stream.pas` | **新建**（Task 1–3） |
| `tests/test.terminal.hooks.pas` | **新建**（Task 4） |
| `tests/test.terminal.view.stream.pas` | **新建**（Task 5） |
| `tests/test.terminal.zmodem.pas` | **新建**（Task 6–8） |
| `tests/test.terminal.zmodem.wsl.pas` | **新建**（Task 10） |
| `tests/test.terminal.example.pas`、`tests/test.release.pas`、`tests/tytests.lpr` | 改（Task 11、12；uses 随各任务加） |
| `docs/controls/terminal.md`、`README.md`、`README.en.md`、`tools/terminal-shots/terminalshots.lpr` | 改（Task 12） |
| `docs/superpowers/plans/2026-09-30-terminal-phase-7-shots/` | **新建**（Task 13 主控） |
| `docs/superpowers/specs/2026-09-28-terminal-view-design.md` | 只在 Task 13 写回 |
| `docs/superpowers/plans/2026-09-29-terminal-acceptance.md` | Task 14 更新 |

**不碰**：四个共享文件、Parser / Buffer / Render / Keyboard / Selection / Links / ColorScheme 单元、主题文件、`THIRD-PARTY-NOTICES.md`（没有新的第三方代码；Task 12 核一遍不需要加）、`CHANGELOG*`。

---

## 实现期的地雷（每个任务开工前看一眼）

1. **`Detect` / `Claimed` / `Feed` 必须在「忙」里**（核实记录 3）：它们不在 `ParseRange` 里，自己 `Inc(FBusy)`。漏了的症状：处理器的 `SendRaw` → 宿主的 `OnData` → 宿主 `Resize` → `FlushSync` 在 `Feed` 里递归处理后面的块，字节乱序。变异 H18 专门杀它。
2. **拦截点只有一处**：`ProcessOneChunk` 调 `ParseRange` 的那一句。`Parse`（`Core.InputHandler.inc:13-16`，测试和 2 期夹具在用）**不走钩子**——它是「直接喂解析器」，不是写入。别在 `ParseRange` 里面拦：`ShowText` 与交还的字节也要经它解析。
3. **快路径要真的快**：条件是 `(FStreamCount = 0) and (FClaim = nil) and (FFront = '')`，三个整数 / 指针比较；别在快路径上建子串、别调虚方法。`StreamPiecesOffered` 只在慢路径加一。
4. **`AClaimAt` 之前的字节要在 `Claimed` 之前解析完**，而且用的是程序那一路的解码器（`FDecoder`）；`ShowText` 用 `FShowDecoder`。两个解码器搞混的症状：程序输出里半个汉字之后接管，`ShowText` 的第一个字乱码，或交还后程序那个汉字丢了。
5. **交还缓冲不计入 `PendingBytes`**：那些字节进来时已经减过了；再加一次，宿主的高低水位就永远降不下来（示例的会话会停读、卡死）。
6. **防死循环**：只看「这次接管收到的字节数 = 交还的长度」（`FClaimFed`），不看内容；`Release` 在 `Claimed` 里（一个字节没收）调、交还空串，不算「一个没吃全交还」。
7. **会话对象只有一个**：`Release` / `ClaimEnded` 之后 `FActive := False`、`FHandler := nil`，别释放它；宿主留着指针事后误调是空操作。
8. **`RemoveStreamHandler` 可能在 `Detect` 循环里、在它自己的 `Feed` 里被调**：循环按快照遍历、把被摘的槽置 `nil`，循环外再压缩；`Feed` 返回后先看 `FClaim` 还是不是它。
9. **`Reset` 在忙时是延后的**（核实记录 3）：`ClaimEnded(tceReset)` 也跟着延后到块处理完之后，不在 `Reset` 被调的那一刻。
10. **`UnregisterHandler` 只认自己发的句柄**：句柄是解析器的全局序号，Core 自己的内置处理器也有句柄（1、2、3…），宿主传错一个数就能拆掉 SGR。
11. **ZModem 的字节序**：头的 P0..P3 是位置的**小端**，而标志在 P3（ZF0）；十六进制头的 CRC16 **高字节在前**；binary32 的 CRC32 **低字节在前**、发的是取反后的值；十六进制用**小写**（lrzsz 发小写，收时两种都认）；ZACK 与 ZFIN 的十六进制头后面**没有** XON。测试向量见 Task 6，全部实测或用标准校验值核过。
12. **帧读取器在数据模式里遇到 `ZPAD` 不是头**：子包里的 `*` 是普通字节；只有 ZDLE 转义的结束符才结束子包。反过来，头的搜索模式里要跳过任何垃圾（`sz` 前面的 `rz\r`、`rz` 的 `rz waiting to receive.`）。
13. **示例规矩**（[[examples-must-be-lfm-titlebar-skin]]、[[demo-edits-lfm-not-code]]、[[no-native-controls-in-ui]]、[[skin-variance-breaks-fixed-widths]]、[[lcl-code-created-align-order]]）：新勾选、传输条写进 `.lfm`、`AutoSize`、库控件；英文标题同步 `.po` 的 msgid（[[example-english-caption-fit]]）；`.po` 新条目 msgstr 不能空（[[empty-po-entry-blocks-startup]]）；聚焦用 `CanSetFocus`。
14. **不在 `Feed` 里弹模态框**：请求事件里只 `QueueAsyncCall`，对话框在消息循环里弹；`sz` 在等的时候会重发 ZRQINIT，`Feed` 照收、忽略。
15. **含 `\x18`、`\x8a`、反斜杠的测试数据用 Write 工具落文件**，不用 heredoc（[[bash-heredoc-eats-backslashes]]）；改 `.pas` 用编辑工具，不用 Git Bash 的 `sed -i`（[[git-bash-sed-strips-crlf]]）。录制夹具是二进制，`.gitattributes` 给 `-text`，提交后 `git show HEAD:<file> | cmp - <file>` 验一遍。
16. **单跑绿 / 全量红** 先 `lazbuild -B` 重编（[[canary-then-rebuild]]），再查进程级状态（[[suite-order-widgetset-init]]）；期末变异先 `git diff --stat` 确认改到了（[[crlf-mutation-phantom-survivor]]）。卡住的测试进程按进程号结束，**禁用 `taskkill -im`**（[[parallel-agent-worktree-hazards]]）；WSL 里残留的 `sz` / `rz` 用 `wsl.exe -d Ubuntu -- pkill -x sz`（只杀 WSL 里的）。
17. **测试钉死了旧行为**（[[tests-that-pin-the-bug]]）：没挂处理器时 1–6 期的全部测试应当一条不改就绿；有哪条要改，先停下查是不是快路径的条件写错了。

---

## 跑测试的固定套路（只在 Task 13 跑）

改了 `source/` 之后**必须** `lazbuild -B`。exe 用唯一名 `tytests-term.exe`。

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi > /tmp/term-build.txt 2>&1 || { tail -30 /tmp/term-build.txt; false; } && cd tests && cp tytests.exe tytests-term.exe && for s in $SUITES; do ./tytests-term.exe --suite=$s --format=plain > /tmp/term-$s.txt 2>&1; printf '%s: ' $s; grep -E "Number of (run tests|errors|failures|ignored)" /tmp/term-$s.txt | tr '\n' ' '; echo; done
```

`SUITES` = `TTyTerminalStreamTests TTyTerminalHookOracleTests TTyTerminalHookTests TTyTerminalViewStreamTests TTyTerminalZmodemTests TTyTerminalZmodemWslTests TTyTerminalWriteQueueTests TTyTerminalReentryTests TTyTerminalCoreTests TTyTerminalCoreOracleTests TTyTerminalParserTests TTyTerminalViewTests TTyTerminalViewInputTests TTyTerminalViewMouseTests TTyTerminalPtyTests TTyTerminalExampleTests TTyTerminalPerfTests TReleaseManifestTest TI18NTest`

**判据是每个 suite 那一行都有 `Number of run tests`、errors / failures 为 0**，不是 exit code。某一行为空 = 跑丢了，重跑，别读成通过。`TTyTerminalZmodemWslTests` 的 ignored 数要等于 0（本机有 WSL 与 lrzsz）；不为 0 就读 `Ignore` 的原因。

全量（输出必须重定向到文件，[[known-rare-suite-flake]]）：

```bash
cd /d/Projects/ty-3.1/tests && ./tytests-term.exe --all --format=plain > /tmp/term-all.txt 2>&1; grep -E "Number of (run tests|errors|failures|ignored)" /tmp/term-all.txt
```

---

## 关于判据和变异

- 纯函数给**输入 / 期望表**；钩子、控件、状态机、互通测试写**判据**（比什么、怎么数、失败打印什么），测试代码执行时现写（[[plan-tests-write-the-mutation-not-the-code]]）。
- 每条判据写明「**在哪个变异下必须红**」；变异期末集中做（Task 13 Step 5）：改一行 → `git diff --stat` 确认改到了 → `lazbuild -B` → 跑相关 suite → **必须红** → 改回 → 重编重跑 → 绿。没红的先查改没改对地方、再查是不是「这条路走不到」；确实没红，当场补测试，签收记录写一句。
- 接线类变异（事件没挂、改道没做、`Inc(FBusy)` 没包、转发没接）每类至少一条（[[built-not-wired-is-the-default-failure]]）。
- 断言里那个量要真的变过（[[assertion-never-varies-the-thing]]）：「接管期间没发 `OnData`」之前先证明同一个动作在不接管时**会**发；「焦点报告被丢掉」之前先证明 1004 开着、同一个 `ReportFocus` 不接管时会发；ZModem 的数据要含每个需要转义的字节。
- 「假协议」处理器 `TFakeProtocol`（测试单元里）：`Detect` 找 `<<GO>>`（跨段时自己记着前缀，`AClaimAt` 指在 `<` 上或 0）；`Feed` 把收到的字节全追加进 `Fed`，见到 `<<END>>` 就 `Release(结束标记之后的部分)`；可配置「在 `Claimed` 里立刻 `Release(全部)`」「`Feed` 里调某个回调」「抛异常」；记一个调用日志（`Detect@段长`、`Claimed`、`Feed:<字节>`、`ClaimEnded:<how>`）。
- 标「等价」的变异不做，理由写在表里。

---

### Task 0: 基线、问用户、ConPTY / 管道实验

**Files:**
- Create: `tools/terminal-zmodem-probe/zmprobe.lpr`

- [ ] **Step 1: 【主控执行】问用户开工前问题一的六条**，把答复写进「开工前要定的问题 · 一」开头的「状态」引用块（格式照 6 期计划）；用户没回复就按建议开工，告诉用户「一起验收时可改」。第 1 条选 B：`RefuseBehindConPty` 默认改 False、Task 11 的提示句不要；选 C：Task 9 跳过、Task 10 只留 WSL 里的 Unix PTY 部分、Task 11 不加「Pipe」。

- [ ] **Step 2: 确认起点**

```bash
cd /d/Projects/ty-3.1 && git status --short && git branch --show-current && git log --oneline -1 && git log --oneline feat/terminal..main | wc -l
```

Expected：工作区干净（6 期的修复都已提交），分支 `feat/terminal`，HEAD 是本计划的提交或其后；`main` 没有新提交（有的话停下交主控：要不要先合）。工作区不干净就停下交主控——6 期修复 agent 可能还在改 `Terminal.pas` 与示例。

- [ ] **Step 3: 基线编译并跑全量**（实现 agent 做）：「跑测试的固定套路」的全量命令。条数记进草稿（6 期签收时 8405 条，唯一的红是 `TPainterTest.TestTextIsInkedAsWindowsInksIt`），Task 13 签收时写进本计划末尾。**有别的红就停。**

- [ ] **Step 4: 确认 WSL 环境**

```bash
wsl.exe -d Ubuntu -- sh -c 'sz --version; rz --version; which fpc python3 mkfifo tee; fpc -iV'
```

Expected：`sz (lrzsz) 0.12.21rc`、`rz (lrzsz) 0.12.21rc`、四个命令都在、FPC 3.2.2。缺什么就停下交主控（Task 7、10 要用）。

- [ ] **Step 5: 写实验工具 `tools/terminal-zmodem-probe/zmprobe.lpr`**：Windows 控制台程序，照 `tools/terminal-conpty-record/conptyrecord.lpr` 的写法用示例的 `uptysession` + `uptywin`（`TConPtyBackend`），手编：`cd tools/terminal-zmodem-probe && mkdir -p lib && fpc -Mobjfpc -Sh -FUlib -Fu../../examples/terminal zmprobe.lpr`。四种模式，每种打印一张表并以退出码表示「原样 / 不原样」：
  1. `--conpty-out`：经 ConPTY 跑 `wsl.exe -d Ubuntu -- python3 -c "import sys; sys.stdout.buffer.write(bytes(range(256))*4); sys.stdout.flush()"`，收 5 秒，从收到的字节里找 `00 01 02 … ff` 这段：对每个字节值打印「原样 / 丢了 / 变成了什么」（在找不到完整一段时按顺序对齐，打印第一处对不上的上下文十六进制）。
  2. `--conpty-in`：经 ConPTY 跑 `wsl.exe -d Ubuntu -- sh -c 'stty raw -echo; head -c 1024 | od -An -tx1 -v'`，等 2 秒后用会话的 `Write` 灌 `bytes(range(256))*4`，收 5 秒，把 `od` 的十六进制读回来逐字节比。
  3. `--conpty-sz`：本机临时目录写一个 4 KB 文件（字节 0..255 循环），经 ConPTY 跑 `wsl.exe -d Ubuntu -- sz <wslpath>`，收 3 秒、不回应，打印收到的原始十六进制，并判断 ZRQINIT 十六进制头（`2a 2a 18 42 30 30 …` 直到 `0d 8a 11`）是否完整。
  4. `--pipe-out` / `--pipe-in`：同 1、2，但不经 ConPTY：工具自己 `CreateProcessW` 带两条匿名管道起 `wsl.exe`（这是 Task 9 后端的最小前身，只在工具里，结束即关）。
  写实验工具可以当场编译运行（本任务的例外）。

- [ ] **Step 6: 跑实验、记结果**：五种模式各跑一次，把每张表（字节值 → 结局，只列不原样的）和结论写进本计划 Task 0 下面新加的「实验结果」小节，并用一句话写结论：ConPTY 输出方向 / 输入方向是否原样、管道两个方向是否原样、`sz` 的头经 ConPTY 是否完整。预期（写计划时的预实验，spec §19.2 第 12 条）：ConPTY 输出丢 `0x80`–`0xFF` 中的若干、丢 `0x00`，管道原样。**结论与预期不同就停下交主控**（开工前问题一第 1 条要重问用户）。

- [ ] **Step 7: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-zmodem-probe/zmprobe.lpr docs/superpowers/plans/2026-09-30-terminal-phase-7.md && git commit -m "test(terminal): a probe for binary bytes through ConPTY and through pipes

Four ways a byte can travel between the example and a WSL program:
out of and into a pseudo console, out of and into two plain pipes, and
the head of an sz session through ConPTY. The results are written into
the phase 7 plan.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

`lib/` 与 `.exe` 不提交（`.gitignore` 已有 `lib/`；exe 照 `terminal-conpty-record` 的先例看 `git status`，出现就加进 `.gitignore`）。

#### 实验结果（2026-09-30，本机 Windows 10 19044，WSL `Ubuntu`）

**结论：ConPTY 两个方向都不原样，管道两个方向都原样，`sz` 的头经 ConPTY 不完整——与预期一致，开工前问题一第 1 条按建议（A）走。**

| 模式 | 结局 | 不原样的字节 |
|---|---|---|
| `--pipe-out` | 原样（1024 字节，`00..ff` 整段按序） | 无 |
| `--pipe-in` | 原样（`od` 读回 1024 字节逐字节相同） | 无 |
| `--conpty-out` | **不原样**：收到 492 字节，是重新渲染过的 VT（开头 `CSI 2J`、`CSI m`、`CSI H`、标题 `OSC 0`、`?25h`，行尾 `CSI K`、`CR LF`） | `00` 丢；`08 09 0B 0C` 丢（被当作光标移动执行掉）；`80`–`FF` 全丢；`07 0A 0D 1B` 与若干 ASCII 变多（渲染加的）；第二、三遍的 `20`–`2F` 也没了（被重绘覆盖） |
| `--conpty-in` | **不原样**：`od` 读回 508 字节 | `16`（Ctrl+V）丢；`80`–`FF` 全丢（不是合法 UTF-8，被控制台吞掉）；其余 `00`–`7F` 原样到达（`stty raw` 下 Ctrl+C 也到了） |
| `--conpty-in-printable`（只发 `20`–`FF`，排除控制字符的干扰） | **不原样**：读回 384 字节 | `80`–`FF` 全丢 |
| `--conpty-sz`（4 KB 文件） | **不完整**：ZRQINIT 头成了 `11 2A 18 42 30…30 CSI 1;2H`——`0D 8A` 没了、`XON` 被挪到 `*` 前面，`rz\r` 被渲染成 `rz CSI H` | 头的 `0D 8A` |

实验工具与写计划时的设想有两处不同：输入方向的命令改成 `stty raw -echo; timeout --foreground 5 dd bs=1 count=1024 > 临时文件; stty sane; od -w32 临时文件; sleep 1`——`timeout` 不带 `--foreground` 时子进程不在终端前台组、读终端就被 `SIGTTIN` 停住；`head -c` 被 `timeout` 结束时缓冲里的字节没写出来；`raw` 关了 `LF → CR LF`，ConPTY 会把阶梯状输出渲染成光标移动；程序一退出 ConPTY 就不再渲染，最后要 `sleep 1`。另加了 `--conpty-in-printable` 一种（上表）。

---

### Task 1: Core 的数据流钩子——类型、挂载、快路径、检测与接管

**Files:**
- Modify: `source/tyControls.Terminal.Core.pas`（接口清单里的声明；`uses` 不变；类头注释加一段「stream hooks: spec 19」，单元头的 include 列表加新文件）
- Create: `source/tyControls.Terminal.Core.Stream.inc`（`{$I}` 在 `WriteQueue.inc` 之后；文件头写「自己写的，不是移植；spec §19」）
- Modify: `source/tyControls.Terminal.Core.WriteQueue.inc`（`ProcessOneChunk` 的拦截点；`InnerWrite` / `FlushSync` / `ClearQueue` 认交还缓冲）
- Create: `tests/test.terminal.stream.pas`（suite `TTyTerminalStreamTests`；`TFakeProtocol` 放这里，`interface` 里导出给 Task 5 用）
- Modify: `tests/tytests.lpr`（uses 加 `test.terminal.stream`）

- [ ] **Step 1: 声明**：接口清单的类型与 Core 成员全部写上；`TTyTerminalStreamHandler.Claimed` / `ClaimEnded` 空实现；Core 构造里建 `FStreamSession`、`FShowDecoder`，析构里释放（**不**调任何处理器，地雷 7、spec §19.5）。

- [ ] **Step 2: `AddStreamHandler` / `RemoveStreamHandler`**：`CheckThread`；加：已在就忽略、`nil` 抛 `EArgumentNilException`；摘：是正在接管的就先 `EndClaim(tceRemoved)`（调 `ClaimEnded`，会话失效），再从数组里摘（在 `Detect` 循环里就置 `nil`，地雷 8）。

- [ ] **Step 3: 拦截点**（`ProcessOneChunk`，核实记录 1）：

```pascal
    if (FStreamCount = 0) and (FClaim = nil) and (FFront = '') then
      ParseRange(data, start + 1, n)
    else
      StreamPiece(data, start + 1, n);
```

`StreamPiece(const AData: RawByteString; AFrom, ACount: Integer)` 在 `Core.Stream.inc`：`Inc(FStreamPiecesOffered)`；先处理交还缓冲（Task 2 写，本任务留 `DrainFront` 空壳）；再：有人接管 → `DoFeed`；否则 → `OfferPiece`。`OfferPiece`：`Inc(FBusy)`，对快照里每个非 `nil` 的处理器调 `Detect`（`Inc(FStreamDetectCalls)`），`AClaimAt` 不在 `0..ACount` 抛 `EArgumentOutOfRangeException`，取最小位置、同一位置取后挂的；`Dec(FBusy)`（`try … finally`）。有胜者：`ParseRange(AData, AFrom, at)`（`at > 0` 时）→ `BeginClaim(winner)`（会话 `FActive := True`、`FHandler`、`FClaimFed := 0`，`Inc(FBusy)` 里调 `Claimed`）→ `at < ACount` 时 `DoFeed(AData, AFrom + at, ACount - at)`。没有：`ParseRange` 整段。`DoFeed`：`Inc(FClaimFed, n)`，`Inc(FBusy)` 里调 `FClaim.Feed(@AData[AFrom], n)`；`Feed` 返回后若 `FClaim` 已变（被摘、被 `Release`）就不再碰原处理器。

- [ ] **Step 4: 判据测试**（`tests/test.terminal.stream.pas`，本任务写 H1–H6、H23–H28；用 `TTyTerminalCore.Create(40, 5)`，多数用 `WriteSync`，涉及切片的用 `Write` + `ProcessPending`（注入冻结时钟，照 2 期 `TTyTerminalWriteQueueTests` 的做法））：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| H1 | 没挂处理器：`WriteSync` 1 MB 后 `StreamPiecesOffered = 0`；挂上再摘掉，再写 1 MB，仍为 0 且 `StreamHandlerCount = 0` | 快路径条件去掉 `FStreamCount = 0`（总走慢路径） |
| H2 | `Detect` 收到的是原始字节：写 `'a'#$E4#$B8'b'#$FF` → 日志里 `Detect` 那段逐字节相同（不是解码后的） | `StreamPiece` 改成传解码后的码位转回的 UTF-8 |
| H3 | 标记在段中间：`'abc<<GO>>xyz'` → `Claimed` 时第 0 行文字是 `abc`（在 `Claimed` 里读缓冲）；`Feed` 收到 `<<GO>>xyz`；屏幕上始终没有 `xyz` | ① `Claimed` 挪到解析前缀之前；② 前缀改成整段解析 |
| H4 | 每一段都问：一次 `Write` 100 KB（`'.'` 填充、第 70000 字节起是 `<<GO>>`），逐片 `ProcessPending` → 接管从 70000 开始，`Fed` 的第一个字节就是 `<`，`Detect` 调了 3 次（32 KB 一段） | `StreamPiece` 只在块的第一段问 `Detect` |
| H5 | 跨段标记：两次 `Write`：`'ab<<G'`、`'O>>zz'` → 屏幕 `ab<<G`，第二段 `AClaimAt = 0`，`Fed = 'O>>zz'` | 第二段不问 `Detect`（「上一段没检测到」就跳过） |
| H6 | `AClaimAt = ACount`：处理器在段尾接管 → 这一段全部解析、`Feed` 没被调；下一次 `Write('xyz')` 全部进 `Fed` | `at < ACount` 的判断写成 `<=`（空 `Feed`，日志多一条） |
| H23 | 摘正在接管的：`RemoveStreamHandler` → 日志 `ClaimEnded:removed` 恰一次、`StreamClaimed = False`；之后 `WriteSync('q')` 显示 `q`；在它自己的 `Feed` 里摘（配置回调）同样，且 `Feed` 返回后没有别的调用 | 摘时不调 `EndClaim` |
| H24 | 多个处理器：A 先挂、在 10 处接管；B 后挂、在 5 处接管 → B 胜；两个都在 5 → 后挂的胜；A 没收到任何 `Claimed` | 改成「第一个返回 True 的胜」 |
| H25 | 异常：`Detect` 抛 → `WriteSync` 抛出、那一块的回调照调、没有接管、后面的块照常；`AClaimAt = ACount + 1` → 同上，异常是 `EArgumentOutOfRangeException`；`Feed` 抛 → 接管还在、下一块照常进 `Feed` | 区间检查去掉 |
| H26 | 线程：从 `TThread` 里 `AddStreamHandler` → `EInvalidOperation` | 去掉 `CheckThread` |
| H27 | 析构：接管中 `Core.Free` → 处理器日志没有 `ClaimEnded`，不崩 | 析构里调 `EndClaim` |
| H28 | 会话对象复用：两次接管拿到的 `ASession` 是同一个对象；第一次结束后 `Active = False`，此时 `SendRaw('x')` 返回 False、不发 `OnData` | `EndClaim` 不清 `FActive` |

- [ ] **Step 5: 提交**：`feat(terminal): stream handlers can claim the program's output before the parser` + Co-Authored-By。

---

### Task 2: 会话——SendRaw、Release（交还顺序、再检测、防死循环）、ShowText

**Files:**
- Modify: `source/tyControls.Terminal.Core.Stream.inc`、`source/tyControls.Terminal.Core.WriteQueue.inc`、`source/tyControls.Terminal.Core.InputHandler.inc`（`ParseRange` 进出时 `Inc` / `Dec(FParsing)`，出来时若 `FParsing = 0` 且 `FShowPending <> ''` 就解析它）
- Modify: `tests/test.terminal.stream.pas`

- [ ] **Step 1: `SendRaw`**：`CheckThread`；不 `Active`、`DisableStdin`（`ReadOnly`）、没挂 `OnData` → False；否则 `FOnData(Self, AData)`、True。不经 `TriggerDataEvent`（不滚到底、不发 `OnUserInput`、不设 `FDidUserInput`）。

- [ ] **Step 2: `Release`**：`CheckThread`；不 `Active` 就返回。`zeroProgress := (FClaimFed > 0) and (Length(ALeftover) = FClaimFed)`；`EndClaim`（不调 `ClaimEnded`）；`ALeftover <> ''` 时**插到交还缓冲最前面**（`FFront := ALeftover + Copy(FFront, FFrontPos + 1, MaxInt)`、`FFrontPos := 0`），记 `FFrontBypass := zeroProgress`；不在 `Feed` 里（`FBusy = 0`）时 `RequestProcess`。
- `DrainFront`（`StreamPiece` 开头，也在 `InnerWrite` / `FlushSync` 的循环里当作「还有东西」）：每次最多取 `TyTermSlicePieceBytes` 一段；`FFrontBypass` 时第一个字节直接 `ParseRange`、清标志；其余走 `OfferPiece` / `DoFeed`，和队列里的段一样。`InnerWrite` 的循环条件改成 `(FFront <> '') or (FQueueCount > FBufferOffset)`，交还缓冲先于队首；`ProcessOneChunk` 被调时若 `FFront <> ''` 先处理它、这一轮不动队列。`ClearQueue` 清 `FFront` / `FFrontPos` / `FFrontBypass`。**不改 `FPendingData`**（地雷 5）。

- [ ] **Step 3: `ShowText`**：`CheckThread`；不 `Active` 就返回（接管外宿主直接 `Write` 就行）；`FParsing > 0` → `FShowPending := FShowPending + AText`，返回；否则 `ParseLocal(AText)`：`Inc(FParsing)`、`Inc(FBusy)`，`FShowDecoder.Decode` 成码位、`FParser.Parse`，照 `ParseRange` 的结尾发 `OnCursorMove` / `OnRefreshRows`；出来时 `FShowPending` 非空就循环解析（先取出、再清空、再解析）。

- [ ] **Step 4: 判据测试**（H7–H14）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| H7 | 交还顺序：处理器见 `<<END>>` 时 `Release('tail')`；这时队里还有一块 `'more'` → 屏幕 `tailmore` | 交还的字节追加到队尾 |
| H8 | 交还再检测：`Release` 的字节里又有 `<<GO>>` → 第二次接管，日志两条 `Claimed`；`sz a; sz b` 的形状 | 交还缓冲直接 `ParseRange`、不问 `Detect` |
| H9 | 防死循环：处理器配置成「`Claimed` 之后第一次 `Feed` 就 `Release(收到的全部)`」且每次都在 0 处接管 → `WriteSync('<<GO>>x')` 在 1 秒内返回，`StreamDetectCalls < 20`，屏幕显示 `<<GO>>x`（测试里 `Detect` 调到 1000 次就抛，免得挂死） | 去掉 `FFrontBypass` |
| H10 | 在 `Feed` 外 `Release('xyz')`（接管中、没有输出）：返回时屏幕上还没有 `xyz`、`OnProcessRequest` 恰发一次；`ProcessPending` 后出现 | 在 `Feed` 外也当场解析 |
| H11 | 两个解码器：程序输出 `#$E4#$B8` 后紧跟 `<<GO>>`；`Feed` 里 `ShowText('é')` → 屏幕有 `é`；`<<END>>` 后交还 `#$AD` → 屏幕接着出现 `中`（程序那一路的半截序列没被打乱） | `ShowText` 用 `FDecoder` |
| H12 | `ShowText` 重入：挂 `OnRefreshRows`，第一次触发时再 `ShowText('2')`；`Feed` 里 `ShowText('1')` → 屏幕 `12`，不抛异常 | 去掉 `FParsing > 0` 时的攒着（解析器重入，`Parse` 里状态被打乱：断言屏幕文字顺序和解析器状态回到 ground） |
| H13 | 流控不断：接管后五次 `Write`（带回调、各 10 KB）→ 五个回调按顺序都到，`PendingBytes = 0`，`Fed` 长度 50 KB | 接管的块跳过回调 |
| H14 | `SendRaw`：`#0#$FF#$18` 原样到 `OnData`；先上翻 3 行，`SendRaw` 后 `YDisp` 不变；`OnUserInput` 没发；紧接着 `Write('a')` 不当场解析（`ProcessPending` 前屏幕没有 `a`）；`ReadOnly := True` 时返回 False、不发 | ① `SendRaw` 改走 `TriggerDataEvent(…, True)`；② 去掉 `ReadOnly` 判断 |

- [ ] **Step 5: 提交**：`feat(terminal): a claimed stream answers, hands back what is not its own, and shows local text` + Co-Authored-By。

---

### Task 3: 与既有机制的交互、输入改道、Core 自发的输出

**Files:**
- Modify: `source/tyControls.Terminal.Core.Services.inc`（`TriggerDataEvent`、`TriggerBinaryEvent`、`TriggerMouseEvent`、`Reset`）
- Modify: `source/tyControls.Terminal.Core.Stream.inc`
- Modify: `tests/test.terminal.stream.pas`

- [ ] **Step 1: 改道**：`TriggerDataEvent` 在 `DisableStdin` 早退之后加：

```pascal
  if FClaim <> nil then
  begin
    { spec 19.5: the user's input goes to OnClaimedInput; the core's own reports would
      land inside the protocol's bytes and are dropped }
    if AWasUserInput and Assigned(FOnClaimedInput) then
      FOnClaimedInput(Self, AData);
    Exit;
  end;
```

`TriggerBinaryEvent` 接管时直接返回；`TriggerMouseEvent` 在 `CheckThread` 之后接管时 `Exit(False)`。

- [ ] **Step 2: `Reset`**：不忙时，`DoReset` 之前若 `FClaim <> nil` 就 `EndClaim(tceReset)`（调 `ClaimEnded`）。忙时照旧延后（地雷 9）。`DiscardPending` 不动接管（Task 2 已让它清交还缓冲）。

- [ ] **Step 3: 判据测试**（H15–H22）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| H15 | 改道：不接管时 `Input('x', True)` 发 `OnData('x')` 与 `OnUserInput`（先证明）；接管时只发 `OnClaimedInput('x')`，`OnData` / `OnUserInput` 都没发、上翻的视口不动；交还后又回到 `OnData`；`ReadOnly := True` 时接管中 `OnClaimedInput` 也不发 | ① 改道去掉；② 改道挪到滚到底之后（视口被拉到底） |
| H16 | 自发的丢掉：程序先开 1004、2031（`WriteSync(#27'[?1004h'#27'[?2031h')`）、挂 `OnQueryBaseColor`；不接管时 `ReportFocus(False)` 与 `NotifyColorSchemeChanged` 各发一条 `OnData`（先证明）；接管时两者都不发 `OnData`、也不发 `OnClaimedInput`；`Input('r', False)` 同样不发 | `FClaim <> nil` 分支里对 `AWasUserInput = False` 也发 `OnClaimedInput` / 不 `Exit` |
| H17 | 鼠标：程序开 1000；不接管时 `TriggerMouseEvent`（左键按下）返回 True 并发 `OnData`（先证明）；接管时返回 False、不发；默认编码下 `TriggerBinaryEvent` 同样 | 去掉 `TriggerMouseEvent` 的接管判断 |
| H18 | 延后：`Feed` 里经 `SendRaw` → 测试的 `OnData` 调 `Core.Resize(30, 5)`、`Core.WriteSync('w')`、`Core.Reset`；日志顺序：`Feed` 结束 → 块回调 → `Resize` 生效 → `w` 被检测 / 解析 → `ClaimEnded:reset`；`Feed` 没有被递归调用（日志里 `Feed` 不嵌套） | `OfferPiece` / `DoFeed` 去掉 `Inc(FBusy)`（地雷 1） |
| H19 | `WriteSync` 接管中：`WriteSync('abc')` 全部进 `Fed`、屏幕不变 | 拦截点只放在切片路径（`FlushSync` 用另一段代码） |
| H20 | `DiscardPending` 接管中：排着的三块被丢、它们的回调不调、没进 `Fed`；接管仍在；之前 `Release` 在 `Feed` 外交还、还没处理的字节也被丢 | `ClearQueue` 不清交还缓冲 |
| H21 | `Reset`：接管中 `Reset` → `ClaimEnded:reset` 恰一次、`StreamClaimed = False`；之后 `WriteSync('<<GO>>')` 能再被检测；不接管时 `Reset` 不调任何处理器 | `Reset` 不结束接管 |
| H22 | `Resize` 接管中：接管仍在、`Cols` 变了、`OnResize` 发了 | `Resize` 里误加 `EndClaim` |

- [ ] **Step 4: 提交**：`feat(terminal): while a stream is claimed, keys go to OnClaimedInput and the core's own reports are held back` + Co-Authored-By。

---

### Task 4: 解析器钩子公开（Core 上五个 Register*Handler）与上游基准

**Files:**
- Modify: `source/tyControls.Terminal.Core.pas`（声明；`Parser` 属性的注释改成「底层接口，宿主用 Register*Handler」）、`source/tyControls.Terminal.Core.Stream.inc`（实现）
- Create: `tools/terminal-oracle/hook-cases.js`、`tools/terminal-oracle/cases/hooks.js`
- Modify: `tools/terminal-oracle/lib-dump.js`（`PORTED` 加 `src/common/public/ParserApi.ts`）、`tools/terminal-oracle/regen-all.js`（加 `hook-cases.js`）
- Generate: `tests/fixtures/terminal-core-hooks.json`
- Create: `tests/test.terminal.hooks.pas`（suites `TTyTerminalHookOracleTests`、`TTyTerminalHookTests`）；`tests/tytests.lpr` 加 uses

- [ ] **Step 1: 实现**：五个方法都先 `CheckThread`、`AHandler` 为 `nil` 抛 `EArgumentNilException`；OSC 编号 < 0 抛 `EArgumentOutOfRangeException`；CSI / ESC 直接 `FParser.RegisterCsiHandler` / `RegisterEscHandler`；OSC / DCS / APC 包 `TTyTerminalOscStringHandler.Create(AHandler)` / `TTyTerminalDcsStringHandler` / `TTyTerminalApcStringHandler`；返回的句柄记进 `FUserHandles`。`UnregisterHandler`：`CheckThread`；不在 `FUserHandles` 里就忽略（地雷 10）；在就摘掉并 `FParser.Unregister`。标识不合法的异常由 `IdentOf` 抛，照上游消息。

- [ ] **Step 2: 基准脚本**（照 `core-cases.js` 的结构，用 `lib-term.js` 建 headless、用 `term.parser.register*`）：每个用例 `{ id, cols, rows, steps }`，步骤有 `{ register: { tag, kind: 'csi'|'esc'|'osc'|'dcs'|'apc', id: {prefix?, intermediates?, final} | ident, returns: [true, false, …] } }`（第 n 次调用返回 `returns[min(n, len-1)]`）、`{ dispose: tag }`、`{ write: base64 }`、`{ reset: true }`、`{ inside: { tag, onCall: n, register: {…} | dispose: tag } }`（第 n 次被调时在处理器里注册 / 注销）。导出 lib-term 的整份状态，外加 `calls`：`[{ tag, kind, params: JSON.stringify(params) | null, data: base64(utf8(data)) | null, returned }]`（按调用顺序）。手写用例 `cases/hooks.js`，至少：

  1. CSI `m` 返回 true → SGR 不生效（格子是默认属性），日志一条、参数 `[31]`；返回 false → SGR 生效。
  2. 同一 CSI 两个处理器：后挂的先调；它返回 false、前一个返回 true → 内置不跑；再注销后挂的 → 只剩前一个。
  3. 子参数：`CSI 38:2::10:20:30 m` 与 `CSI 4:3 m` 的 `params` 串逐字。
  4. ESC `#8`（DECALN）返回 true → 屏幕没被 `E` 填满；返回 false → 填满。
  5. OSC 1337（没有内置）→ 日志收到载荷（含中文与 `;`）；OSC 0 返回 false → 标题照设；返回 true → 标题不变；OSC 分三次 `write` 切开 → 只调一次、载荷完整。
  6. DCS `$q`（DECRQSS）返回 true → `data` 里没有应答；返回 false → 有；DCS 的 `params` 串。
  7. APC `G` → 日志收到载荷；注销后不再调。
  8. 在处理器里注册同一标识的新处理器、注销链里别的处理器（`inside`）——结果以上游为准。
  9. `reset()` 之后注册的处理器仍在被调。
  10. 标识不合法（前缀 `!`、三个中间字节、CSI 终止字节 `0x30`）：上游抛的消息记进夹具，Pascal 比 `EArgumentException` 的消息。

  跑：`node tools/terminal-oracle/hook-cases.js`，生成 `tests/fixtures/terminal-core-hooks.json`；`node tools/terminal-oracle/regen-all.js --expect-clean` 通过（本任务的例外：node 可以跑）。

- [ ] **Step 3: Pascal 基准测试** `TTyTerminalHookOracleTests.TestTheFixtures`：读夹具，照 `test.terminal.core.pas` 的比较辅助单元（`test.terminal.oracle.pas`）比整份状态；按步骤调 `Core.Register*Handler` / `UnregisterHandler` / `Reset`，脚本化的返回值与日志由一个测试对象提供（CSI 的参数用 `AParams.ToJson`，OSC / DCS / APC 的载荷转 base64）；`calls` 逐项比。每个用例跑两遍（新建 Core；同一 Core `Reset` 后重跑——夹具有 `afterReset` 时比它，照 2 期的规矩）。

- [ ] **Step 4: 判据测试**（`TTyTerminalHookTests`，上游没有的部分）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| P1 | 只认自己的句柄：对 1..500 逐个 `UnregisterHandler`，之后 `WriteSync(#27'[31mX')` 的 `X` 仍是红色；自己注册的那个句柄注销后不再被调 | `UnregisterHandler` 不查 `FUserHandles`、直接转解析器 |
| P2 | `OnOsc` 与链：挂 `OnOsc`；OSC 7 先到 `OnOsc`（先证明）；注册 OSC 7 处理器返回 False → `OnOsc` 不再收到 OSC 7；注销后又收到 | 等价于上游、解析器没改：这一条守的是文档写的行为；变异「`RegisterOscHandler` 包装里处理器返回 False 时手动调 `OnOsc`」 |
| P3 | 参数校验：`nil` → `EArgumentNilException`；OSC `-1` → `EArgumentOutOfRangeException`；CSI 前缀 `'!'` → `EArgumentException` | 去掉 `nil` 判断 |
| P4 | 线程：从线程里 `RegisterCsiHandler` → `EInvalidOperation` | 去掉 `CheckThread` |
| P5 | 处理器抛异常：CSI 处理器抛 → `WriteSync` 抛出；后面的块照常（§3.1 的规则），处理器仍注册着 | —（等价：规则在写入队列里，2 期已守；这一条只防包装吞掉异常） |
| P6 | 参数借用：CSI 处理器里 `AParams.Clone` 存起来，返回后读克隆的值正确 | — |

- [ ] **Step 5: 提交**（两个提交）：夹具与脚本 `test(terminal): parser hook fixtures from xterm.js`；Core 与测试 `feat(terminal): parser hooks on the core, after xterm.js's IParser`，各带 Co-Authored-By。

---

### Task 5: 控件——转发、OnClaimedInput、接管期间鼠标

**Files:**
- Modify: `source/tyControls.Terminal.pas`（`AddStreamHandler` / `RemoveStreamHandler` / `StreamClaimed`；`FCore.OnClaimedInput := @CoreClaimedInput`，析构里清；published `OnClaimedInput`）
- Modify: `source/tyControls.Terminal.View.Mouse.inc`（`Reporting` 加 `and not FCore.StreamClaimed`）
- Create: `tests/test.terminal.view.stream.pas`（suite `TTyTerminalViewStreamTests`，用 `test.terminal.view.pas` 导出的控件夹具与 Task 1 的 `TFakeProtocol`）；`tests/tytests.lpr` 加 uses

- [ ] **Step 1: 实现**：`CoreClaimedInput` 转宿主的 `OnClaimedInput`，并 `NoteActivity`（与 `Input` 一致）。接管开始 / 结束控件不做别的（屏幕本来就没动）。

- [ ] **Step 2: 判据测试**：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| V1 | 真按键：不接管时 `KeyDown` 发 Ctrl+X → `OnData(#24)`（先证明）；接管时 → `OnClaimedInput(#24)`、`OnData` 没发 | 控件不接 `FCore.OnClaimedInput` |
| V2 | 粘贴：括号粘贴开着，接管中 `Paste('a'#10'b')` → `OnClaimedInput` 收到括号包好、换行成 CR 的字节 | — |
| V3 | 鼠标：程序开 1000；不接管时按下发报告（先证明）；接管时按下拖动 → 没有 `OnData`、`HasSelection = True` | `Reporting` 不看接管 |
| V4 | 滚轮：程序开 1000 且有滚回；接管时滚轮向上 → 视口上移、没有 `OnData` | 同上 |
| V5 | 流式化：`OnClaimedInput` 挂到窗体方法上，`WriteComponent` / `ReadComponent` 往返后还在（照 `TestStreamedValuesSurviveLoading`） | — |
| V6 | 转发：`Term.AddStreamHandler(h)` 后 `Term.Core.StreamHandlerCount = 1`，`Term.StreamClaimed` 与 Core 一致 | `StreamClaimed` 读错字段 |

- [ ] **Step 3: 提交**：`feat(terminal): the view forwards stream handlers and pauses mouse reports while a stream is claimed` + Co-Authored-By。

---

### Task 6: ZModem 编解码（`examples/terminal/uzmodem.pas`）

**Files:**
- Create: `examples/terminal/uzmodem.pas`（单元头：「自己写的；协议按 Chuck Forsberg, The ZMODEM Inter Application File Transfer Protocol, Rev Oct-14-88（公有领域）；不含 lrzsz（GPL）的代码，lrzsz 只当互通对象」；`uses SysUtils, Classes`）
- Create: `tests/test.terminal.zmodem.pas`（suite `TTyTerminalZmodemTests`）；`tests/tytests.lpr` 加 uses

- [ ] **Step 1: CRC**

```pascal
function ZmCrc16(ACrc: Word; AData: PByte; ACount: Integer): Word;
var
  i, b: Integer;
begin
  Result := ACrc;
  for i := 0 to ACount - 1 do
  begin
    Result := Result xor (Word(AData[i]) shl 8);
    for b := 1 to 8 do
      if (Result and $8000) <> 0 then
        Result := Word((Result shl 1) xor $1021)
      else
        Result := Word(Result shl 1);
  end;
end;

function ZmCrc32(ACrc: Cardinal; AData: PByte; ACount: Integer): Cardinal;
var
  i, b: Integer;
begin
  Result := ACrc;
  for i := 0 to ACount - 1 do
  begin
    Result := Result xor AData[i];
    for b := 1 to 8 do
      if (Result and 1) <> 0 then
        Result := (Result shr 1) xor $EDB88320
      else
        Result := Result shr 1;
  end;
end;
```

（逐位写法够快：1 MB 约几毫秒；Task 13 的审查若嫌慢再换查表，测试不变。）

- [ ] **Step 2: 头的编码**：十六进制头 = `**` + ZDLE + `B` + 类型与 P0..P3 各两位**小写**十六进制 + CRC16（对 5 个字节，高字节在前）四位 + `#13#$8A`，类型不是 ZACK / ZFIN 时再加 `#$11`。二进制头 = ZPAD + ZDLE + (`A` 或 `C`) + 转义后的（类型、P0..P3、CRC：16 位高字节在前；32 位是 `not ZmCrc32($FFFFFFFF, …)` 低字节在前）。子包 = 转义后的数据 + ZDLE + 结束符 + 转义后的 CRC（CRC 包含结束符那个字节）。`TZmEscaper.Escape`：`$18 $10 $11 $13 $90 $91 $93` 一律转义；`EscCtl` 时再加 `(c and $60) = 0` 的全部；`LastSent` 是 `@`（`$40` 或 `$C0`）时的 `$0D` / `$8D`；转义 = ZDLE + `c xor $40`。

- [ ] **Step 3: `TZmReader`**：两种模式。找头：`ZPAD` 起，跳过更多 `ZPAD`，必须 ZDLE，然后 `A` / `B` / `C`；十六进制头读 14 位十六进制（大小写都认）+ 4 位 CRC、之后吃掉 `CR` / `LF|$80` / `XON` 里出现的；二进制头按转义读 5 字节 + CRC。CRC 错的头丢弃、`GarbageCount` 累加。数据模式：反转义（ZDLE 后：结束符 `h`–`k` 结束子包，`l` → `$7F`，`m` → `$FF`，`(c and $60) = $40` → `c xor $40`，别的算错），读 CRC 后发 `OnData(数据, 结束符, CRC 对不对)`；ZCRCE / ZCRCW 后回到找头；超过 `ZmMaxRecvSubpacket` 算 CRC 错、回到找头。任何模式里未转义的 `$11 $13 $91 $93` 丢掉。连续 5 个 ZDLE → `OnCancel`。`Push` 在事件里 `Stop` 时返回已吃的字节数（会话结束时要知道剩下的是交还的）。二进制的 ZDATA / ZFILE / ZSINIT / ZCOMMAND 头之后自动进数据模式（CRC 种类随头）；`ExpectData` / `DropData` 给状态机用。

- [ ] **Step 4: 文件信息**：`ZmBuildFileInfo`：`名字 #0 十进制大小 空格 八进制修改时间 空格 八进制 100644 空格 0 空格 剩余文件数 空格 剩余字节数 #0`。`ZmParseFileInfo`：名字到第一个 `#0`；其后按空格拆，缺的字段为 -1 / 0；大小不是数字就失败。

- [ ] **Step 5: 输入 / 期望表**（`TTyTerminalZmodemTests`，纯函数）：

| # | 输入 | 期望 | 必须红的变异 |
|---|---|---|---|
| Z1 | `ZmCrc16(0, '123456789')` | `$31C3`；分三段累加与整段相同 | 多项式改 `$8408` |
| Z2 | `not ZmCrc32($FFFFFFFF, '123456789')` | `$CBF43926` | 初值改 0 |
| Z3 | `ZmEncodeHexHeader(ZmFlagsHeader(ZRINIT, $23, 0, 0, 0))`（P3 = ZF0） | `'**'#$18'B0100000023be50'#13#$8A#$11`（`rz` 线上实测，spec §19.2 第 11 条） | 十六进制改大写；ZF0 放到 P0 |
| Z4 | ZRQINIT 位置 0 | `'**'#$18'B00000000000000'#13#$8A#$11`（`sz` 实测） | — |
| Z5 | ZFIN 位置 0；ZACK 位置 0 | `'**'#$18'B0800000000022d'#13#$8A`；`'**'#$18'B0300000000eed2'#13#$8A`（都没有 XON；CRC 用 Python 核过） | XON 总加 |
| Z6 | 0..255 逐个过默认转义 | 恰好 `$10 $11 $13 $18 $90 $91 $93` 七个变成两字节（第二字节 = `c xor $40`），其余原样 | 漏 `$18` |
| Z7 | `EscCtl` 下 0..255 | 恰好 `(c and $60) = 0` 的 64 个（`$00–$1F`、`$80–$9F`）变成两字节；`$7F`、`$FF` 不转义 | 把 `$7F` 也算进去 |
| Z8 | 默认转义 `'@'#13'@'#$8D'A'#13` | `@` 后的两个 CR 转义、`A` 后的不转义 | 去掉 `LastSent` |
| Z9 | 读取器：Z3–Z5 的串，前面加 `'rz'#13` 与 100 个随机垃圾，**逐字节喂** | 三个 `OnHeader`，类型与 P 对；`GarbageCount` = 103 | — |
| Z10 | 二进制 32 位 ZDATA 头 + 三个子包（ZCRCG 1024 字节全部 0..255 循环、ZCRCQ 1 字节、ZCRCE 0 字节），整段喂与逐字节喂 | 三个 `OnData`，数据与结束符对、CRC 全对；改一个数据字节 → 那一个 CRC 错 | 反转义漏 `ZRUB1` |
| Z11 | 数据模式里夹着未转义的 `$11 $93` | 被丢掉，数据不含它们 | 不丢 |
| Z12 | 5 个 `$18` | `OnCancel` 一次；4 个不触发 | 阈值改 4 |
| Z13 | 子包 9000 字节 | 算 CRC 错、回到找头，之后的十六进制头照常认 | 上限去掉 |
| Z14 | `ZmParseFileInfo('a b.bin'#0'1234 14530722433 100644 0 1 1234'#0)` | 名字 `a b.bin`、大小 1234、时间 `&14530722433`、模式 `&100644`；只有名字和大小也成功 | 时间按十进制读 |

- [ ] **Step 6: 提交**：`feat(examples): ZModem frames, CRCs and escaping for the terminal example` + Co-Authored-By。

---

### Task 7: ZModem 收发状态机（`uzmodemsession.pas`）与 lrzsz 录制

**Files:**
- Create: `examples/terminal/uzmodemsession.pas`（单元头同 Task 6）
- Create: `tools/terminal-oracle/zmodem-record.sh`、`tools/terminal-oracle/zmodem-record.py`
- Generate: `tests/fixtures/terminal-zmodem/`（`cases.json` + 每例 `<id>.sz.bin`、`<id>.rz.bin`、源文件 `<id>.<n>.src`）
- Modify: `.gitattributes`（`tests/fixtures/terminal-zmodem/** -text`）、`tests/test.terminal.zmodem.pas`

- [ ] **Step 1: 收方**（`TZmReceiver`，状态：等头 / 收文件信息 / 收数据 / 等 OO）：`Start` 发 ZRINIT（十六进制，ZF0 = `CANFDX or CANOVIO or CANFC32`，`EscapeControl` 时再或 `ESCCTL`，P0 / P1 缓冲大小 0）。收到：ZRQINIT → 再发 ZRINIT；ZSINIT → 收它的子包、回 ZACK；ZFILE → 收文件信息子包，`Sink.Open` 为 False 回 ZSKIP，否则回 ZRPOS(0)；ZDATA(位置) → 位置对上就进数据模式，对不上回 ZRPOS(已收)；子包 CRC 对 → 写、前进，ZCRCQ / ZCRCW 回 ZACK(位置)；CRC 错 / 超长 → 回 ZRPOS(已收)、`DropData`，直到位置对上的 ZDATA；ZEOF(位置) → 等于已收就 `Sink.Finish(True)`、回 ZRINIT，不等就忽略；ZFIN → 回 ZFIN、进「等 OO」（至多吃两个 `O`、1 秒没来就结束），之后同一次 `Input` 里剩下的字节进 `OnDone` 的 `ALeftover`；ZCOMMAND → 发中止序列、`zrError('the sender asked to run a command; refused')`；ZCAN / 5 个 CAN → `zrCancelledThere`，关文件（未完成）。`Tick`：等应答超过 `TimeoutMs` 就重发上一次的应答（ZRINIT 或 ZRPOS），同一处 `MaxRetries` 次后发中止序列、`zrTimeout`。`Cancel`：发中止序列、未完成的 `Finish(False)`、`zrCancelledHere`。

- [ ] **Step 2: 发方**（`TZmSender`）：`Start(ZRINIT)`：记对方标志（CANFC32 → 32 位 CRC，ESCCTL → 转义控制字符）与缓冲大小（P0 + P1 × 256，0 = 全流式）；取第一个文件，发 ZFILE（二进制头，ZF0 = `ZCBIN`）+ 文件信息子包（ZCRCW）。等：ZRPOS(n) → 定位到 n，发 ZDATA(n) 头，然后在 `CanSend` 允许的量里一包一包发 1024 字节的 ZCRCG；缓冲大小非 0 时每满一窗发 ZCRCW、等 ZACK；到文件尾发 ZCRCE、ZEOF(大小)；ZSKIP → 下一个文件；ZRINIT（ZEOF 之后）→ 下一个文件，没有了发 ZFIN；中途 ZRPOS → 回退到那个位置重发（丢掉手里还没发的，重发 ZDATA）；ZFIN → 发 `OO`、`ALeftover` 是这之后的字节、`zrOk`；ZNAK → 重发上一个头；ZCAN / 5 个 CAN → `zrCancelledThere`。`Tick`：超时重发上一个头，`MaxRetries` 后中止；并在 `CanSend` 放行时继续产数据。

- [ ] **Step 3: 录制脚本**（WSL 里跑，只用 `sz` / `rz` 自己，不经我们的代码，开工前问题二第 15 条）：`zmodem-record.py` 在临时目录按种子（Python `random.Random(种子)`）生成源文件、`os.utime` 设修改时间为 1700000000；`zmodem-record.sh` 对每个用例建两个 FIFO，`sz <选项> 文件… < fifo_b | tee <id>.sz.bin > fifo_a`、`rz <选项> < fifo_a | tee <id>.rz.bin > fifo_b`（`rz` 在另一个临时目录里收），等两边退出、比较收到的文件与源文件（不同就报错退出），把两个 `.bin`、源文件、`cases.json`（每例的选项、文件名、大小、MD5、`sz --version` 与 `rz --version`、生成命令）拷进 `tests/fixtures/terminal-zmodem/`。用例（总量控制在 300 KB 以内）：
  - `one-small`：一个 1500 字节文件（0..255 循环，含全部要转义的字节）；
  - `empty`：一个 0 字节文件；
  - `batch`：三个文件（1 字节、1024 字节、5000 字节随机）；
  - `esc`：`sz -e` / `rz -e`，一个 3000 字节随机；
  - `big-block`：`sz -8`，一个 20000 字节随机；
  - `window`：`sz -w 2048`，一个 20000 字节随机；
  - `names`：名字 `a b 中文.bin`、`x.y.z`，各 100 字节。
  跑：`wsl.exe -d Ubuntu --cd /mnt/d/Projects/ty-3.1 -- sh tools/terminal-oracle/zmodem-record.sh`（本任务的例外：WSL 里的脚本可以跑）。**可复现性只要求到文件**：两个进程同时起，谁的第一个头先到有时序（`rz` 可能多发一次 ZRINIT，`sz` 可能因此多发一次 ZFILE），所以再跑一遍时收到的文件、`cases.json` 必须相同，两个 `.bin` 可以不同——提交第一次跑的，脚本头部写明这一点（和 §13.5 第 7 条「`git diff` 为空」不同，签收时写进计划外发现）。

- [ ] **Step 4: 判据测试**（`TTyTerminalZmodemTests`，加在 Task 6 的后面；时钟都是注入的数）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| S1 | 回放 `sz`：每个录制用例，把 `<id>.sz.bin` 整段喂给 `TZmReceiver`（一个把文件写进内存的 sink）→ 收到的文件名、内容（MD5）与 `cases.json` 相同；**我们回的头的序列**（解析 `OnSend` 的字节）与 `<id>.rz.bin` 里 `rz` 回的头，去掉相邻重复的 ZRINIT / ZRPOS 后，类型与位置逐个相同（录制里 `sz` 若因时序重发了 ZFILE，我们对同一个文件的第二个 ZFILE 照样回 ZRPOS、不重开文件）；再按 1 字节、按 7 字节切着喂一遍，结果一样 | 收方收 ZFILE 后回 ZRINIT（而不是 ZRPOS） |
| S2 | 回放 `rz`：每个录制用例，把源文件交给 `TZmSender`、把 `<id>.rz.bin` 里 `rz` 的各个头按顺序在我们发完上一段之后喂进去 → 我们发的字节用 `TZmReader` 解出来：文件名、大小、内容与源文件相同，最后是 `OO` | 发方 ZEOF 的位置发成已发字节数减一 |
| S3 | 环回：自家发方 ↔ 自家收方直接对接，文件大小 0、1、1023、1024、1025、70000、0..255 循环 5000；选项组合：CRC16 / CRC32、`EscapeControl`、对方缓冲 0 / 4096、收方子包上限 1024（发方照发 1024）→ 内容逐字节相同、双方 `zrOk`、会话结束后多喂的 `'TAIL'` 出现在 `ALeftover` | 收方 CRC 错时不回 ZRPOS |
| S4 | 故障注入环回：种子随机数在两个方向各以 1/5000 的概率翻转一个字节、1/20000 的概率丢一个字节，70000 字节的文件、种子 1..20 → 全部 `zrOk`、内容相同；记录重传次数 > 0（证明真的注入了） | 发方收到中途的 ZRPOS 不回退 |
| S5 | 超时：收方 `Start` 后不喂任何东西，时钟每次加 10001 → 每次重发 ZRINIT，第 11 次时发出 `ZmAbortSequence`、`zrTimeout`；中间喂一个 ZRQINIT 重置计数 | 重试计数不重置 |
| S6 | 取消：`Cancel` 发的字节恰好是 `ZmAbortSequence`（10 CAN + 10 BS）；没收完的 sink `Finish(False)`；对方 5 个 CAN → `zrCancelledThere` | —（字节值比较） |
| S7 | ZFIN 之后：收方回 ZFIN 后喂 `'OOprompt$ '` → `ALeftover = 'prompt$ '`；喂 `'Xprompt'` → `'Xprompt'`；喂 `'O'` 再喂 `'Orest'` → `'rest'`；只喂 `'O'` 然后时钟过 1 秒 → 结束、`ALeftover = ''` | 把 `OO` 也算进剩余 |
| S8 | ZCOMMAND 被拒：喂一个二进制 ZCOMMAND 头 + 子包 `'rm -rf ~'` → 发中止序列、`zrError`，没有调任何执行 | — |
| S9 | ZEOF 位置不对被忽略：收到 1000 字节后 ZEOF(1500) → 不 `Finish`、不回 ZRINIT | 不查位置 |

- [ ] **Step 5: 提交**（两个提交）：录制 `test(examples): lrzsz talking to itself, recorded for the ZModem tests`（附 `cases.json` 里的 lrzsz 版本）；状态机与测试 `feat(examples): ZModem receiver and sender state machines`，各带 Co-Authored-By。提交后 `git show HEAD~1:tests/fixtures/terminal-zmodem/one-small.sz.bin | cmp - tests/fixtures/terminal-zmodem/one-small.sz.bin`（地雷 15）。

---

### Task 8: 终端胶水（`uzmodemterm.pas`）

**Files:**
- Create: `examples/terminal/uzmodemterm.pas`（单元头同 Task 6；`uses SysUtils, Classes, tyControls.Terminal.Core, uzmodem, uzmodemsession`，不引 LCL）
- Modify: `tests/test.terminal.zmodem.pas`

- [ ] **Step 1: 检测**（`ZmDetectHexStart` + `Detect`）：`Enabled = False` 或 `State <> zsIdle` 就 False。在 `ACarry + 这一段` 里找 `**` ZDLE `B`，其后 14 位十六进制 + 4 位 CRC 且 CRC 对、类型是 0 或 1；找到：`AClaimAt` = 第一个 `*` 在这一段里的位置（在 carry 里就 0），记下类型；没找到：把这一段最后至多 20 个字节存进 carry（只在它们可能是头的开头时：从最后一个 `*` 起）。

- [ ] **Step 2: 接管后**：`Claimed` 记会话。`RefuseBehindConPty` 且 `Core.WindowsPty.Backend = twpConPty` → `ShowText(拒绝那句 + #13#10)`、`SendRaw(ZmAbortSequence)`、`Release('')`、`OnFinished(zrError, …)`。否则类型 0 → `zsAskDownload`、发 `OnDownloadRequest`；类型 1 → `zsAskUpload`、发 `OnUploadRequest`（事件里宿主只排异步调用，地雷 14）。等答复期间 `Feed` 的字节暂存（`sz` 重发的 ZRQINIT、`rz` 的 ZRINIT；上传时要把最后一个 ZRINIT 头交给发方的 `Start`）。`AcceptDownload(目录)`：建 `TZmReceiver`（sink 写进目录，名字 `ZmUniqueFileName(目录, ZmSafeFileName(远端名))`、按修改时间设文件时间、`Finish(False)` 时删掉），`Start`，再把暂存的字节交给它。`StartUpload(文件)`：建 `TZmSender`（source 按列表开文件），`Start(暂存里最后一个 ZRINIT)`。`Decline` / `Cancel`：发中止序列（有状态机就 `Cancel` 它），`ShowText` 一行「已取消」，`Release('')`。

- [ ] **Step 3: 进度与结束**：状态机的 `OnProgress` → 至多每 200 ms（按 `Clock`）一次 `ShowText(#13#27'[K' + '↓ 名字  已收 / 总大小  百分比  速度')`（上传用 `↑`），同时转发 `OnProgress`；`OnDone` → `ShowText(#13#27'[K' + 摘要 + #13#10)`（文件数、总字节、用时、平均速度；失败时是原因），`Release(ALeftover)`，`OnFinished`。数字格式用 `FormatFloat` 与 `KB` / `MB`，不依赖区域设置（[[test-expectation-from-the-environment]]）。文字全放 `resourcestring`（示例的 `.po` 由主控生成）。

- [ ] **Step 4: 取消键与节拍**：`UserInput(AData)`：逐字节数连续的 `#24`，到 5 个就 `Cancel`；中间夹别的字节就归零。`Tick(ANowMs)` 转给状态机；`CanSend` 转给发方。`ClaimEnded(tceReset / tceRemoved)`：状态机 `Cancel`（远端还在就停下它），没收完的文件删掉，回 `zsIdle`。`Destroy`：`RemoveStreamHandler`（会先 `ClaimEnded(tceRemoved)`）。

- [ ] **Step 5: 文件名**（`ZmSafeFileName` / `ZmUniqueFileName`）输入 / 期望表：

| 输入 | 期望 |
|---|---|
| `../../etc/passwd` | `passwd` |
| `a\b\c.txt` | `c.txt` |
| `C:\x\y.bin` | `y.bin` |
| `a:b*c?"<>\|.txt`（`\|` 指竖线） | `a_b_c_____.txt`（冒号、星号、问号、引号、尖括号、竖线各一个 `_`） |
| `name. . ` | `name` |
| `CON`、`con.txt`、`LPT1.log` | `_CON`、`_con.txt`、`_LPT1.log` |
| `''`、`'..'`、`'.'` | `file` |
| `报告 2026.pdf` | 原样 |
| 名字里有 `#1`、`#31`、`#127` | 各换成 `_` |
| `ZmUniqueFileName(d, 'x.txt')`，`d` 里已有 `x.txt`、`x (1).txt` | `d\x (2).txt` |
| `ZmUniqueFileName(d, 'x')`，已有 `x` | `d\x (1)` |

- [ ] **Step 6: 判据测试**（接真的 `TTyTerminalCore`，时钟注入）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| T1 | 检测：`sz` 录制的开头（`rz\r` + ZRQINIT）整段写入 → 屏幕有 `rz`、`AClaimAt` 在 `*`；头在 1..20 每个位置被切成两次 `Write` → 都检测到、第二段 `AClaimAt = 0`；CRC 改一位 → 不检测；10 MB 种子随机字节 → 没有误检；`rz` 的 ZRINIT → 上传请求 | CRC 不校验就算检测到（随机字节里出现 `**`#24`B` 就误检——测试用种子构造一段 `**`#24`B00` + 错 CRC 保证有这个输入） |
| T2 | 先问后答：检测到 ZRQINIT 后，答复之前 `OnData` 一个字节都没发；`AcceptDownload` 后发出的第一个头是 ZRINIT | 接管就立刻 `Start` 收方 |
| T3 | 整个下载：把 `one-small.sz.bin` 分块写进 Core，`AcceptDownload(临时目录)` → 文件内容对、屏幕最后一行是摘要、会话结束后写入的 `'$ '` 显示在摘要下一行、`StreamClaimed = False` | 结束时不 `Release` |
| T4 | 进度节流：时钟每喂一块加 50 ms、共 40 块 → `ShowText` 的进度行不超过 11 次 | 去掉 200 ms 判断 |
| T5 | Ctrl+X：`UserInput` 五个 `#24` → 取消（中止序列发出、`zrCancelledHere`、临时文件删掉）；`#24#24'a'#24#24#24` 不取消；四个不取消 | 计数不归零 |
| T6 | ConPTY：`Core.WindowsPty` 设成 ConPTY → 检测到后屏幕出现拒绝那句、`OnData` 是中止序列、没弹请求事件；`RefuseBehindConPty := False` 时照常问 | 不看 `WindowsPty` |
| T7 | `Reset` 中途：下载一半 `Core.Reset` → 中止序列发出、没收完的文件被删、`State = zsIdle` | `ClaimEnded` 里不 `Cancel` |
| T8 | 上传节流：`CanSend` 答 0 → `Tick` 不产数据；改答 4096 → 下一次 `Tick` 产出 ≤ 4096 + 一个包的开销 | 不看 `CanSend` |

- [ ] **Step 7: 提交**：`feat(examples): a ZModem stream handler for the terminal` + Co-Authored-By。

---

### Task 9: 管道后端 `TProcessPipeBackend`

**Files:**
- Modify: `examples/terminal/uptywin.pas`（新类；单元头注释加一段「TProcessPipeBackend: no pseudo console, binary safe; for ZModem (spec 19.7)」）
- Modify: `examples/terminal/uptysession.pas`（`PendingWrite` 的注释从「FOR THE TESTS」改成正式用途：上传节流）
- Modify: `tests/test.terminal.pty.pas`（加三条）

- [ ] **Step 1: 实现**：`Start`：两条匿名管道（`bInheritHandle` 只给子进程那一端，另一端 `SetHandleInformation` 去掉继承）；`STARTUPINFOW` 带 `STARTF_USESTDHANDLES`：`hStdInput` = 输入管道的读端、`hStdOutput` = 输出管道的写端、`hStdError` = 合并时同写端，否则 `CreateFileW('NUL', …)`；`CreateProcessW(nil, cmd, …, True, CREATE_NO_WINDOW or CREATE_UNICODE_ENVIRONMENT, …)`；起完关掉子进程那几端；`FIn` / `FOut` 交给 `TPipeBackend`。退出等待照 `TConPtyBackend` 的 `TConPtyExitWaiter` 那套（等进程句柄或关闭事件），`BeginClose` 关输入管道的写端（程序读到 EOF）并置关闭事件；`FinishClose` 等进程（上限 `AWaitMs`），不走就按句柄 `TerminateProcess`、再等 2 秒；`ExitCode` 用 `GetExitCodeProcess`；`Resize` 空；`IsConPty` 继承（False）。主线程不等（spec §12.2 的规矩）。

- [ ] **Step 2: 判据测试**（`TTyTerminalPtyTests`，Windows 才跑）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| B1 | 二进制原样：`cmd.exe /c type <含 0..255 的文件>`（本机，不要 WSL）→ 会话读出的字节与文件相同；再用测试程序自己带的 `--ty-pty-helper cat`（4 期先例）回显 0..255 → 相同 | `hStdOutput` 误用 ConPTY 的伪控制台（换成 `TConPtyBackend` 做对照：对照组必须不同，证明这条测得出） |
| B2 | 关闭：起一个不退出的 helper，`Close` 立即返回（< 100 ms），`PtyWaitForFinishers(9000)` 为 True，进程已不在 | `BeginClose` 里同步等进程 |
| B3 | stderr：合并时 helper 往 stderr 写的字节出现在输出里；不合并时不出现 | 合并开关不起作用 |

- [ ] **Step 3: 提交**：`feat(examples): a pipe backend that runs a command without ConPTY` + Co-Authored-By。

---

### Task 10: 与真实 lrzsz 互通

**Files:**
- Create: `tests/test.terminal.zmodem.wsl.pas`（suite `TTyTerminalZmodemWslTests`）；`tests/tytests.lpr` 加 uses
- Create: `tools/terminal-zmodem-wsl/zmwsl.lpr`

- [ ] **Step 1: 环境检查**（每个测试开头，结果缓存）：非 Windows、`wsl.exe` 不在、`wsl.exe -d Ubuntu -- sh -c 'command -v sz && command -v rz'` 失败或超时 15 秒 → `Ignore('WSL Ubuntu with lrzsz is not available: <原因>')`。

- [ ] **Step 2: 测试骨架**：`TTyTerminalCore.Create(80, 24)` + `TZmodemStreamHandler`（`OnDownloadRequest` 里测试直接 `AcceptDownload(临时目录)`——测试里没有消息循环，同步答是允许的；`OnUploadRequest` 里 `StartUpload(文件)`）+ `TPtySession(TProcessPipeBackend.Create(False))`；会话 `OnWake` 置事件，主循环等事件（上限 60 秒）→ `Pump` → `Core.Write(数据, 回调 → Delivered)` → `ProcessPending` 直到返回 False；`Core.OnData` → `session.Write`；`CanSend` 答 `256 KB − session.PendingWrite`；每 100 ms `Tick`。源文件在 Windows 临时目录，WSL 那边的路径用 `wsl.exe -d Ubuntu -- wslpath -u '<路径>'` 取；命令 `wsl.exe -d Ubuntu --cd <目录> -- sz <选项> <文件>` / `-- rz <选项>`。结束判据：`OnFinished` 到了且进程退出。每例结束后 `wsl.exe -d Ubuntu -- pkill -x sz; pkill -x rz`（只杀 WSL 里的，地雷 16）。

- [ ] **Step 3: 用例**（每例比较内容逐字节、`OnFinished` 的结果是 `zrOk`、`sz` / `rz` 退出码 0）：

| # | 用例 | 在哪个变异下必须红（期末挑三条做） |
|---|---|---|
| I1 | 下载 0 字节、1 字节、1024、1025 | — |
| I2 | 下载 0..255 循环 64 KB（全部要转义的字节）；`sz -e` 再一次 | 转义漏 `$90` |
| I3 | 下载 1.5 MB 种子随机；记下用时与吞吐（进签收） | — |
| I4 | 一次下载三个文件（`sz a b c`） | 收方 ZEOF 后不回 ZRINIT |
| I5 | `sz -8`、`sz -w 2048` | 收方子包上限 1024 |
| I6 | 注入：测试在会话与 Core 之间把第 20000 个字节翻转一次 → 仍 `zrOk`、内容相同（记重传次数 ≥ 1） | 收方 CRC 错不回 ZRPOS |
| I7 | 结束后的输出：`sh -c 'sz f; printf TAIL-$?'` → 文件对，屏幕上摘要之后是 `TAIL-0` | 结束时交还的字节被丢 |
| I8 | 中途取消：下载 1.5 MB，收到 200 KB 时 `Cancel` → `sh -c 'sz f; printf "EXIT-$?"'` 的屏幕上出现 `EXIT-` 且不是 `EXIT-0`；临时文件不在 | — |
| I9 | 上传 0 字节、0..255 循环 64 KB、1.5 MB、两个文件；`rz -e` 再一次；上传文件名 `a b 中文.bin` 在 WSL 那边名字相同 | 发方忽略 ESCCTL |
| I10 | 上传注入：测试在我们发出的字节里翻转第 30000 个字节 → `rz` 回 ZRPOS、我们重发，内容相同 | 发方收到中途 ZRPOS 不回退 |
| I11 | 上传中途取消 → `rz` 退出码非 0 | — |

- [ ] **Step 4: WSL 里经 Unix PTY 的工具** `tools/terminal-zmodem-wsl/zmwsl.lpr`（照 `tools/terminal-ptytest/ptytest.lpr`：`cthreads`、`uptysession`、`uptyunix`，加 `-Fu../../source`（Core 不依赖 LCL）；手编 `cd tools/terminal-zmodem-wsl && mkdir -p lib && fpc -Mobjfpc -Sh -FUlib -Fu../../examples/terminal -Fu../../source zmwsl.lpr`）：同样的 Core + 胶水 + `TUnixPtyBackend`，命令 `/bin/sh -c 'sz …'`（`sz` 在 PTY 里自己设原始模式），跑 I1、I2、I3、I4、I7、I9 的对应例；打印 `PASS` / `FAIL` 与 `zmwsl: N passed, M failed`，退出码 M。本任务只写，Task 13 跑。

- [ ] **Step 5: 提交**：`test(examples): ZModem against lrzsz through pipes and a Unix PTY` + Co-Authored-By。

---

### Task 11: 示例

**Files:**
- Modify: `examples/terminal/umain.lfm`、`umain.pas`、`ushell.pas`、`terminal_example.lpi`（加三个单元）、`languages/terminal_example.zh_CN.json`
- Modify: `tests/test.terminal.example.pas`

- [ ] **Step 1: `.lfm`**（[[demo-edits-lfm-not-code]]）：`Tools3` 加 `ChkZmodem`（Caption `ZModem`，`Checked = True`）、`ChkPipe`（Caption `Pipe`，`Visible` 在 `FormCreate` 里按 `{$IFDEF MSWINDOWS}` 设——平台差异只能在代码里；默认 `Checked = False`）；新 `Tools6: TTyPanel`（`Align = alBottom`，显式 `Top` 放在状态栏上面，[[lcl-code-created-align-order]]；`Visible = False`）：`LblTransfer: TTyLabel`（`AutoSize`）、`BarTransfer: TTyProgressBar`（`Align = alClient`，`AnimationsEnabled = False`）、`BtnCancelTransfer: TTyButton`（Caption `Cancel`，`AutoSize`）；非可视：`DlgUpload: TTyOpenDialog`（多选、标题 `Files to send`）、`DlgDownloadDir: TTySelectPathDialog`（标题 `Save received files in`）、`ZmTimer: TTimer`（`Interval = 100`，`Enabled = False`）。

- [ ] **Step 2: `ushell.pas`**：`TTerminalShell.Create` 多一个可选参数 `AZmodem: Boolean`；为 True 时建 `TZmodemStreamHandler(FTerm.Core)`，`CanSend` 答 `256 KB − FSession.PendingWrite`（会话已关就 0）；`Stop` 里先 `Cancel`、再释放它（在 `Unhook` 之后、`DiscardPending` 之前）。暴露 `property Zmodem: TZmodemStreamHandler`。控件的 `OnClaimedInput` 由主窗体接到 `FShell.Zmodem.UserInput` 与键码面板。

- [ ] **Step 3: `umain.pas`**：
  - `StartShell`：`ChkPipe.Checked`（仅 Windows）时建 `TProcessPipeBackend.Create(True)`，否则照旧；`TTerminalShell.Create(Term, backend, …, ChkZmodem.Checked)`；接 `OnDownloadRequest` / `OnUploadRequest` / `OnProgress` / `OnFinished`；`ZmTimer.Enabled := True`。
  - `OnDownloadRequest`：`Application.QueueAsyncCall(@AskDownloadDir, 0)`；`AskDownloadDir`：`DlgDownloadDir.Directory` 默认上次的（没有就 `GetUserDir + 'Downloads'`，不存在退到 `GetUserDir`）；`Execute` 成功 → `AcceptDownload`，否则 `Decline`；之后 `FocusTerm`（`CanSetFocus`）。上传同理（`DlgUpload.Files`）。开工前问题一第 2 条的「上次的目录」存在窗体字段里，不写文件。
  - `OnProgress`：显示 `Tools6`，`LblTransfer.Caption := 名字`，`BarTransfer` 按千分比；`OnFinished`：隐藏 `Tools6`，状态栏 `Status.Panels[0]` 写摘要或原因。
  - `BtnCancelTransfer.OnClick` → `Zmodem.Cancel`；`ChkZmodem.OnClick` → `Zmodem.Enabled`（运行中也能切）；`ChkPipe.OnClick` 只影响下次启动（状态栏提示一句「下次启动生效」）。
  - `ZmTimer.OnTimer` → `Zmodem.Tick(TyTermDefaultClock)`。
  - 键码面板：`OnClaimedInput` 的字节以「(claimed)」前缀列出。
  - 测试缝：`class var ZmodemAnswerForTest: string`（非空时 `AskDownloadDir` 不弹框、直接用它），注释标「FOR THE TESTS」。

- [ ] **Step 4: i18n**：新 Caption 与 `resourcestring` 进 `languages/terminal_example.zh_CN.json`（「ZModem」不译；「Pipe」→「管道」；「Cancel」→「取消」；对话框标题；胶水里的进度与摘要句；ConPTY 拒绝那句：「ConPTY 会改坏二进制数据，ZModem 请改用管道模式（勾选“管道”后重启）」）。`.po` 由主控在 Task 13 生成。

- [ ] **Step 5: 判据测试**（`TTyTerminalExampleTests`，照「建真主窗体」的先例 `TMainForm.Create(nil)`）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| X1 | 建窗体：`Tools6` 不可见、`ChkZmodem.Checked`、`ChkPipe.Visible` 在 Windows 上为 True；`ZmTimer` 未启用 | `.lfm` 里 `Tools6.Visible = True` |
| X2 | 回放下载：假后端（4 期测试里那个）把 `one-small.sz.bin` 作为程序输出喂进来，`ZmodemAnswerForTest := 临时目录` → 消息循环跑到 `OnFinished`（上限 10 秒）后临时目录里的文件内容对、`Tools6` 又隐藏、状态栏有摘要 | 主窗体没接 `OnDownloadRequest` |
| X3 | 关掉 ZModem：`ChkZmodem.Checked := False` 再喂同样的字节 → 没有请求、屏幕上出现 `rz` 与乱码、`Term.StreamClaimed = False` | `ChkZmodem.OnClick` 没接 |
| X4 | `.lpi` 列了 `uzmodem.pas`、`uzmodemsession.pas`、`uzmodemterm.pas`（`TestTheExampleProjectListsItsUnits` 的数组加三项） | — |

- [ ] **Step 6: 提交**：`feat(examples): ZModem downloads and uploads in the terminal example` + Co-Authored-By。

---

### Task 12: 文档、README、发版守卫、截图工具

**Files:**
- Modify: `docs/controls/terminal.md`、`README.md`、`README.en.md`、`tests/test.release.pas`、`tools/terminal-shots/terminalshots.lpr`

- [ ] **Step 1: 控件文档**（[[doc-writing-native-tone]]）：
  - 事件表加 `OnClaimedInput`；方法表加 `AddStreamHandler` / `RemoveStreamHandler`，只读属性加 `StreamClaimed`。
  - 新一节「带内协议：数据流钩子」：什么时候用（ZModem、自定义的二进制协议）；一段最小的处理器代码（检测一个标记、`Feed` 里找结束标记、`Release` 交还）；时序要点（前面的先显示、跨段自己记、交还的字节再检测、回调照常）；接管期间的键盘、鼠标、焦点报告；`Reset` 结束接管、`DiscardPending` 不结束；不内置 ZModem，示例里有一份可以抄。
  - 新一节「解析器钩子」：五个方法、返回值的意思、借用的参数、OSC 注册后不再进 `OnOsc`、`Core.Parser` 是底层接口；例子：OSC 1337 的处理器、覆盖 CSI `m`。
  - 平台一节：Windows 上 ConPTY 会改坏二进制，带内协议要不经 ConPTY 的管道（示例的「Pipe」）；Linux / macOS 的 PTY 没这个问题。
  - 限制：只有同步处理器；标记跨段时前半截会显示；接管期间焦点报告不补发。
- [ ] **Step 2: README**：两份的终端那一条补「带内协议钩子与解析器钩子（示例里有 ZModem 收发）」，不改控件数。
- [ ] **Step 3: 发版守卫**（`tests/test.release.pas`）：`ViewIncludes` 旁边加一个 `CoreOwnIncludes`（`source/tyControls.Terminal.Core.Stream.inc`：随包发出、在磁盘上、**不在** xterm.js 一节的标题里——它是自己写的）；新测试 `TheExampleZmodemUnitsAreOurOwn`：三个 `uzmodem*.pas` 随示例发出、文件里没有 `GNU General Public License` / `GPL` 字样、单元头有 `Forsberg`。**变异 D1**：在 `uzmodem.pas` 的注释里加一句 `GPL` → 红。**D2**：打包脚本（`scripts/*.ps1` / `.sh` 的示例规则）排除 `uzmodem*.pas` → 红。
- [ ] **Step 4: 截图工具**：`terminalshots.lpr` 加 `--phase7`，出到 `docs/superpowers/plans/2026-09-30-terminal-phase-7-shots/`，`index.md` 列每张看什么（格式照 6 期）：
  1. `zmodem-progress-{light,dark}.png`：离屏控件，`$ sz report.pdf` + `rz` 一行后接管，`ShowText` 一行进度（固定数字）。
  2. `zmodem-done-{light,dark}.png`：交还之后：摘要一行，下一行是交还的提示符。
  3. `zmodem-conpty-refused.png`：ConPTY 拒绝那句。
  4. `claimed-selection.png`：程序开着 1000 时接管、鼠标拖出本地选区。
  画法都走真的 Core + 胶水（用 Task 7 的录制喂，时钟注入），不手画文字。
- [ ] **Step 5: 提交**（不编译；截图由主控在 Task 13 跑）：`docs(terminal): stream and parser hooks in the control page, guards and phase 7 shots` + Co-Authored-By。

---

### Task 13: 收尾——编译、全量、按 spec 逐条核、集中变异、主控编包编示例截图、审查、写回 spec、签收

**Files:**
- Modify: 本计划（签收记录）、`docs/superpowers/specs/2026-09-28-terminal-view-design.md`（写回）
- 修复时按需改 Task 1–12 的文件

- [ ] **Step 1: 一次编译 + 本期 suite + 全量**：「跑测试的固定套路」。Expected：本期 suite 全 0 / 0，`TTyTerminalZmodemWslTests` 没有 ignored；全量 errors / failures 只剩基线那一条、总数 = 基线 + 本期新增。红了集中修：钩子以 spec §19.3–19.5 为准，解析器钩子以上游为准，ZModem 以 lrzsz 的线上行为为准；修复提交 `fix(terminal): ...` / `fix(examples): ...`，一个问题一个提交。
- [ ] **Step 2: WSL 里跑 Unix PTY 工具**：`wsl.exe -d Ubuntu --cd /mnt/d/Projects/ty-3.1/tools/terminal-zmodem-wsl -- sh -c 'mkdir -p lib && fpc -Mobjfpc -Sh -FUlib -Fu../../examples/terminal -Fu../../source zmwsl.lpr && ./zmwsl'`。Expected：`zmwsl: 6 passed, 0 failed`（编不过先看是不是 Core 间接引了 LCL——那是 bug，Core 不该依赖 LCL）。结果进签收。
- [ ] **Step 3: 按 spec 逐条核代码，不看测试**（[[green-tests-are-not-spec-conformance]]、[[built-not-wired-is-the-default-failure]]）：§19.3 接口每个成员、§19.4 每一条、§19.5 表的每一行、§19.6 每一条、§19.7「范围」的每个帧类型与每条规则、示例的每一项；逐条记「在哪一行实现 / 为什么不需要 / 挪到以后」。
- [ ] **Step 4: 【主控执行】编包、编示例、i18n、截图、看一眼**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tycontrols.lpk > /tmp/term-pkg.txt 2>&1; tail -3 /tmp/term-pkg.txt; lazbuild -B tycontrols_dt.lpk > /tmp/term-dt.txt 2>&1; tail -3 /tmp/term-dt.txt; lazbuild -B examples/terminal/terminal_example.lpi > /tmp/term-ex.txt 2>&1; tail -3 /tmp/term-ex.txt; git status --short
```

Expected：三个都编过。然后：
1. `python scripts/example-rsj2po.py examples/terminal terminal_example examples/terminal/languages/terminal_example.zh_CN.json`，重编示例，`python scripts/check-example-po.py` 过；`python scripts/check-lfm-props.py` 过。
2. `powershell -File scripts/smoke-launch-examples.ps1`（终端示例起得来）。
3. 示例里勾「Pipe」、命令 `wsl.exe -d Ubuntu -- sz /etc/os-release`、启动：弹选目录、下载完、终端里一行摘要（只看不录，真机验收时用户再看）；不勾「Pipe」再跑一次：出现 ConPTY 那句。
4. `lazbuild -B tools/terminal-shots/terminalshots.lpi` 后跑 `terminalshots --phase7`；PNG 进 git、单张 ≤ 300 KB；抽查每组一张。
5. 吞吐与零开销：`terminalbench` 的 Core 吞吐与 5 期签收的 19.2 MB/s 比（没挂处理器时差 ≤ 2%）；I3 的下载吞吐进签收。
- [ ] **Step 5: 集中变异**（每条三拍，必须红）：H1–H28（Task 1–3 的表，除标「—」的）、P1–P4、V1、V3、V4、V6、Z1–Z3、Z5–Z8、Z10–Z14、S1–S5、S7、S9、T1、T2、T3、T4、T5、T6、T7、T8、B1–B3、I2、I6、I10（这三条要 WSL）、X1–X3、D1–D2。结果逐条记进签收；没红的当场补强。
- [ ] **Step 6: 整体代码质量审查**（`git diff <Task 0 的 HEAD>..HEAD`）：
  - Core：快路径只有三个比较（地雷 3）；每个进处理器的地方都在「忙」里（地雷 1）；交还缓冲不计入 `PendingBytes`（地雷 5）；`RemoveStreamHandler` 在循环里、在 `Feed` 里都安全（地雷 8）；`UnregisterHandler` 只认自己的句柄（地雷 10）；新代码的注释照 Core 的英文惯例。
  - ZModem：字节序（地雷 11）；状态机的每个分支都有超时出口；文件句柄在每条失败路径上都关、没收完的都删；没有模态框在 `Feed` 里（地雷 14）；单元头的出处与「不含 lrzsz 代码」。
  - 示例：规矩（地雷 13）；关窗口、切模式、重启时传输都被取消、没有悬挂的异步调用（`Application.RemoveAsyncCalls`）。
  审出来的问题修完回到 Step 1。
- [ ] **Step 7: 写回 spec 原处，标「实现期修正（7 期）」**，原文删除线保留。至少：状态行（7 期签收）；§19.2 第 12 条（Task 0 正式实验的结论）；§19 各节实现中与规格不同的地方；开工前问题一的答复写进 §19 原处；§14、§15、§16（本期真机项的实际编号）、§17（7 期开工前问题的结论）、§18（7 期实际做了什么）。
- [ ] **Step 8: 签收记录写进本计划末尾，提交**：全量条数（基线 → 签收）、提交区间、本期各 suite 用时、WSL 工具结果、下载 / 上传吞吐、变异结果（每条红 / 补强 / 等价）、spec 写回的节号、计划外发现、遗留。

```bash
cd /d/Projects/ty-3.1 && git add docs/ && git commit -m "docs(terminal): phase 7 sign-off; corrections written back into the spec

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: 更新最终验收文档（1–7 期合在一份）

**Files:**
- Modify: `docs/superpowers/plans/2026-09-29-terminal-acceptance.md`

用户在验收 1–6 期，**不另起一份**。写法照 [[doc-writing-native-tone]]；改动只加不删，已有的项文字不动（除了下面点名的几处「7 期：…」补句）。

- [ ] **Step 1: 开头**：「六期做完后」改成「七期做完后」、「3–6 期所有要在真机上看的项」改成「3–7 期」；「做了什么」加一条 **7 期**：「控件不内置 ZModem，但宿主可以自己实现这类带内协议：Core 在解析器前面开了一个数据流钩子（检测、接管、交还剩下的字节），解析器钩子照 xterm.js 公开。示例用它们实现了 ZModem 的下载和上传，和 lrzsz 互通；Windows 上 ConPTY 会改坏二进制数据，示例加了不经 ConPTY 的『管道』模式。」分支头提交和全量条数换成 7 期签收的。
- [ ] **Step 2: 准备**：示例那条加「Shell 那排的『ZModem』『Pipe』勾选（Pipe 只在 Windows 有）、传输时底部多出的一排」；新一条「ZModem 的项要 WSL 里装 lrzsz（`sudo apt install lrzsz`）；Linux / macOS 本机装 lrzsz；远端的项要一台能 ssh 的机器」。
- [ ] **Step 3: 验收表**：表头说明里加一句「第 N 项起是 7 期」（N = 当时最后一项 + 1）。下面「7 期新增的真机验收项」的 Z1–Z12 换成实际项号并入。已有几项补一句「7 期：…」，不另起：
  - 第 33 项（ConPTY 启动时发了哪些模式）：「7 期：ConPTY 也会改坏二进制，见第 N+4 项。」
  - 第 40 项（右键菜单）：「7 期：传输中右键菜单照常（接管期间本地操作不受影响）。」
- [ ] **Step 4: 按平台的项号**：新项号按平台补进索引表。
- [ ] **Step 5: 决定清单**：新一小节「**7 期开工前的问题**」，六条（Windows 上走哪条路、下载存哪与重名、没收完的文件、先不先问、进度显示在哪、自动识别的开关），每条写「是什么、选项、现在的做法（按 Task 0 的实际答复）、看哪里、改哪里」，格式照 D20–D23 那张表，编号接 D23 往下。「spec §15 里你可能想改的偏离」加一行「7 期新增」：接管期间焦点、2031、默认编码鼠标报告丢掉且不补发；标记跨段时前半截会显示；解析器钩子的参数借用、只有同步。
- [ ] **Step 6: 「记现象」表**：加三行——ConPTY 下 ZModem 的实际表现（写回 spec §19.2 第 12 条、§12.4）；`ssh -T` 管道模式能不能用（§19.7）；各平台的下载 / 上传速度（§19.9）。
- [ ] **Step 7: 截图**：加 `2026-09-30-terminal-phase-7-shots/` 一行（张数、内容一句话、链接 `index.md`）；重新生成加 `terminalshots --phase7`。
- [ ] **Step 8: 自查**：项号连续不重复；已有各项除点名的补句外与改前逐字相同（`git diff` 只在那几行有改动）；每个截图链接指向存在的文件（`ls` 核对）；决定清单每条都有「看哪里」。
- [ ] **Step 9: 提交**

```bash
cd /d/Projects/ty-3.1 && git add docs/superpowers/plans/2026-09-29-terminal-acceptance.md && git commit -m "docs(terminal): phase 7 joins the acceptance sheet

The in-band protocol checks follow on from the last item, two earlier
items gain a line for phase 7, and the six questions asked before
phase 7 join the decision list.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 7 期做完能看到什么

- `tytests` 里本期的六个 suite 全绿：假协议处理器在任意切块下检测、接管、交还，流控回调一个不少，输入改道、Core 自发的报告丢弃、鼠标暂停，与切片、延后、`WriteSync`、`DiscardPending`、`Reset`、`Resize` 的每条交互都对；解析器钩子与 xterm.js 逐位相同；ZModem 的编解码对上 lrzsz 线上实测的字节与标准校验值，收发状态机回放 lrzsz 的录制、环回加故障注入都对；经管道与真实的 `sz` / `rz` 收发一致；1–6 期的测试一条没改。
- WSL 里经 Unix PTY 的工具 6 例全过。
- 示例里勾「Pipe」跑 `wsl.exe -d Ubuntu -- sz 文件`：弹选目录、下载完，终端里留一行摘要；远端 `rz` 弹选文件、上传完；传输中点「取消」或连按五次 Ctrl+X 能停下；不勾「Pipe」时终端里说明 ConPTY 不行。
- 一份 1–7 期合在一起的验收文档。

---

## 7 期新增的真机验收项（Task 14 并入验收文档，接当时的最后一项往下编）

写计划时验收文档的最后一项是第 101 项（6 期修复期间可能还会加），这里先记 Z1–Z12，并入时换成实际项号。截图在 `docs/superpowers/plans/2026-09-30-terminal-phase-7-shots/`。

| # | 项 | 平台 | 怎么验 | 算过 |
|---|---|---|---|---|
| Z1 | 下载 | Win32（管道模式、WSL） | 勾「Pipe」，命令 `wsl.exe -d Ubuntu --cd ~ -- sz 文件`；分别下一个小文本、一个 0 字节文件、一次三个文件（`sz a b c`）、一个中文名的文件 | 弹选目录；文件都在、内容和 WSL 里 `md5sum` 一致；中文名正确；终端里一行摘要，之后的输出正常 |
| Z2 | 上传 | Win32（管道模式） | 命令 `wsl.exe -d Ubuntu --cd /tmp -- rz`；选一个文件、再选三个 | 弹选文件；WSL 里 `md5sum` 一致；多个文件都到 |
| Z3 | 管道模式下的交互 shell | Win32 | 勾「Pipe」，命令 `wsl.exe -d Ubuntu -- bash -i`，开「本地回显」；在里面 `sz`、`rz` 各一次 | 能用；记下提示符、回显的样子（写回 spec §19.7） |
| Z4 | 大文件 | Win32（管道模式） | `dd if=/dev/urandom of=/tmp/big bs=1M count=200` 后 `sz /tmp/big`；再把它上传回去 | 内容一致；记下速度（写回 spec §19.9）；传输中窗口能拖、能滚回、界面不卡 |
| Z5 | 取消 | Win32 | 大文件传到一半：点「取消」；另一次连按五次 Ctrl+X；另一次点「Restart」；另一次直接关窗口 | 都能停下，WSL 里的 `sz` / `rz` 退出（`ps` 看不到）；没收完的文件被删；之后终端能正常用；关窗口不卡 |
| Z6 | ConPTY 下 | Win32（默认模式） | 不勾「Pipe」，命令 `wsl.exe`，在里面 `sz 文件` | 终端里一行说明 ConPTY 不行、`sz` 被中止、终端能继续用（开工前问题一第 1 条选 B 时：记下实际表现） |
| Z7 | Linux 真 PTY | GTK2、Qt6 | 示例 Shell（`$SHELL -l`）里 `sz`、`rz`，各传一个大文件和三个小文件；再 `ssh` 到另一台机器上做一次 | 都能传、内容一致；速度记下 |
| Z8 | macOS 真 PTY | Cocoa | 装 lrzsz（`brew install lrzsz`）后同 Z7 | 同 Z7 |
| Z9 | `ssh -T` 管道模式 | Win32（Windows 自带 OpenSSH） | 勾「Pipe」，命令 `ssh -T 用户@主机`，在里面 `sz`、`rz` | 能传；记下现象（写回 spec §19.7） |
| Z10 | 误检 | Win32、GTK2 | Shell 里 `printf 'rz\r**\030B00000000000000\r\212\021'`（一个没有 `sz` 在等的假头） | 弹选目录；点取消后终端里多一行「已取消」，shell 收到中止序列后照常能用（记下 shell 显示了什么） |
| Z11 | 接管期间的鼠标、选区、滚回 | Win32 | 在 vim 里（开了鼠标）`:!sz 文件`，传输中用鼠标拖选、滚轮滚回、切到别的窗口再切回 | 能本地选中复制；滚轮滚滚回；vim 恢复后鼠标照常给 vim |
| Z12 | 文件名 | Win32 | WSL 里建 `a:b.txt`、`CON`、`x.txt`（本地目录里已有 `x.txt`）后 `sz` 它们 | 分别存成 `a_b.txt`、`_CON`、`x (1).txt`，没覆盖任何东西 |

---

## 与规格不符之处（核实中发现，Task 13 写回）

1. spec §7.4 原文「宿主也可以直接 `Core.Parser.RegisterOscHandler`」：能，但 `Core.Parser` 同时开放了 `Clear*` / `Set*Fallback`，会拆掉 Core 自己的处理；7 期起建议改用 Core 的 `Register*Handler`（§7.4 的 7 期注已写）。
2. 主控提议的 `ITyTerminalStreamHandler` / `ITyTerminalStreamSession` 改成抽象类 `TTyTerminalStreamHandler` 与 Core 持有的 `TTyTerminalStreamSession`（理由在 spec §19.3 末段与开工前问题二第 1 条）；处理器的方法多了可选的 `Claimed` / `ClaimEnded`，`Detect` 的参数是指针 + 长度（避免每段复制一份）。
3. xterm.js 类型注释里 `IFunctionIdentifier` 那段还写着「APC … currently not supported」（`typings/xterm.d.ts` 约 `:1913`），而同一文件的 `IParser` 已有 `registerApcHandler`、`ParserApi.ts` 也实现了——是上游注释过时，照实现做。
