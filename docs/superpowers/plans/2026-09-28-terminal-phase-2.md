# 终端控件 2 期：解析器、缓冲、核心（不可见部分）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（用户要求，优先于子技能的默认做法）**：整期连续实现，**每个任务只写代码 + 测试并单独提交**，**任务之间不编译、不跑 Pascal 测试**（node 生成脚本例外：生成物要进提交，脚本必须当场跑）。整期写完后（Task 23）一次编译、跑全量、集中修；全绿后集中做一轮变异；最后整体规格核对 + 代码质量审查。中途不汇报、不问要不要提交。开工前问题一第 1 条若用户选了「分段编译」，按那一条改节奏，其余不变。
>
> **谁来做**：标 **【主控执行】** 的步骤实现 agent **不做**、直接跳过：要联网的（核对外部许可）、动 `D:/Projects/xterm.js` 或 WSL 环境的（装包、录制）、编 `tycontrols.lpk`。实现 agent 不编任何 `.lpk`，不改 xterm.js checkout 里被跟踪的文件，node 依赖不进本仓库。

**Goal:** 新增三个不可见单元 `tyControls.Terminal.Parser`、`tyControls.Terminal.Buffer`、`tyControls.Terminal.Core`（照 xterm.js 6.0.0 移植），外加写入调度与一个控制台探针；每一层都拿 node 真跑上游生成期望值，Pascal 侧逐位比较。

**Architecture:** 解析器（UTF-8 解码 + VT500 状态机 + OSC/DCS/APC 子解析器）→ 核心（`InputHandler` 与各服务的移植，外加写入队列）→ 缓冲（单元格三字、行、环形行表、主备缓冲、标记、OSC 8 链接表）。基准分三层：解析器层直接跑上游 `EscapeSequenceParser` / `Utf8ToUtf32` 记录回调轨迹；缓冲层直接调上游 `BufferLine` / `CircularList` / `BufferService`；核心层跑 headless `Terminal` 写字节、导出整份状态（spec §13.3）。headless 不应答的几类（颜色查询、明暗查询、焦点）在 node 脚本里照浏览器层源码补一个应答器，夹具标 `synthesized`。

**Tech Stack:** FPC 3.2.2 / Lazarus（`fpcunit`、`fpjson`）；node v22.22.2（只用内置模块）；xterm.js 6.0.0 本地 checkout 的 `out/`（1 期已 `npm ci --ignore-scripts` + `npm run build`）；WSL Ubuntu（只在录制那一步，主控执行、看用户答复）。

**设计依据：** `docs/superpowers/specs/2026-09-28-terminal-view-design.md`（下称 spec）。本计划覆盖 §18 第 2 期、§2（Parser / Buffer / Core 三行）、§3、§5、§6（重新折行除外，5 期）、§7（鼠标上报前处理除外，4 期）、§13（2 期部分）、§14、§17.2 第 1、2、6、7、8、9、11 条。键盘编码按 spec §18 归 3 期，本期不做。

**不在本期**：`tyControls.Terminal.Keyboard`（3 期）；鼠标上报前处理 `TriggerMouseEvent`（4 期，spec §7.5、§13.4「鼠标」行）；重新折行（5 期，开工前问题一第 3 条）；流量控制与性能（5 期）；控件、主题、示例、README、控件文档（3 期起）；CHANGELOG（发版时写，[[changelog-user-facing]]）。

---

## 总目录

本计划分一个主文件和四个子批次附录。**先读完主文件**（核实记录、开工前问题、接口清单、夹具格式、地雷），再按任务号顺序做；附录里的任务引用主文件的节名。

| 部分 | 文件 | 任务 | 这一批做完能看到什么（执行时不单独验收，见执行方式） |
|---|---|---|---|
| 主文件 | 本文件 | Task 0 基线与主控准备；Task 1 基准脚本公共部分；Task 22 许可；Task 23 收尾 | — |
| 2a 解析器与 UTF-8 解码 | [`2026-09-28-terminal-phase-2a-parser.md`](2026-09-28-terminal-phase-2a-parser.md) | Task 2–5 | 转移表 4257 项与上游逐项相同；UTF-8 解码逐块相同；几百条序列的回调轨迹（打印区间、执行、CSI 参数含子参数、ESC、OSC/DCS/APC 起止与载荷、错误）逐项相同；超长载荷、超长参数后状态有界、后续序列照常 |
| 2b 缓冲 | [`2026-09-28-terminal-phase-2b-buffer.md`](2026-09-28-terminal-phase-2b-buffer.md) | Task 6–9 | 行操作（插删替换、宽字符边界、组合、改宽）、环形行表（含三种事件）、缓冲（滚动、改行数、主备切换、制表位、标记、折行区间）、OSC 8 链接表的操作脚本与上游逐步相同；比较器就位 |
| 2c 核心 | [`2026-09-28-terminal-phase-2c-core.md`](2026-09-28-terminal-phase-2c-core.md) | Task 10–18 | 手写 vttest 风格、上游 79 个序列文件、切块、坏序列、超长、随机、颜色与焦点应答、鼠标编码、真实程序录制：缓冲三字、光标、模式、应答字节、事件与上游逐位相同 |
| 2d 写入调度与探针 | [`2026-09-28-terminal-phase-2d-writequeue.md`](2026-09-28-terminal-phase-2d-writequeue.md) | Task 19–21 | 切片、回调顺序、用户输入后当场解析、50MB 上限、非主线程抛异常都有判据测试；`tools/terminal-probe` 把录制喂进 Core 打印屏幕文本 |

---

## 核实记录（写计划时读源码 + 实跑上游得到，2026-09-28）

执行者不用重做；Task 0 会在真构建上复核其中几条。「实跑」= 用 1 期的 `lib-dump.js` 加载 `out/`，在临时目录跑小脚本（没动 checkout）。

1. **移植源的规模与行号**（`xterm:` = `D:/Projects/xterm.js/`，HEAD `c58ea3637f39`）：`src/common/InputHandler.ts` 3699 行；`parser/` 七个文件 2159 行（`EscapeSequenceParser.ts` 934、`Params.ts` 248、`OscParser.ts` 237、`DcsParser.ts` 191、`ApcParser.ts` 196、`Constants.ts` 68、`Types.ts` 285）；`buffer/` 中本期要的 `Buffer.ts` 672（其中 `_reflow*` 约 210 行 5 期做）、`BufferLine.ts` 618、`AttributeData.ts` 213、`CellData.ts` 151、`Constants.ts` 157、`BufferSet.ts` 138、`Marker.ts` 43；`CircularList.ts` 262；`input/TextDecoder.ts` 346、`input/WriteBuffer.ts` 316、`input/XParseColor.ts` 80；`services/` 中 `BufferService.ts` 158、`CoreService.ts` 105、`CharsetService.ts` 38、`MouseStateService.ts` 254、`OscLinkService.ts` 116；`data/Charsets.ts` 253；`WindowsMode.ts` 27；`CoreTerminal.ts` 307；`StringBuilder.ts` 67（`LimitedStringBuilder`，载荷上限在这里算）。
2. **载荷上限按 UTF-16 单元数、`>` 判定**（`StringBuilder.ts:55-61`，OSC / DCS / APC 的字符串处理器共用）。实跑：OSC 2 载荷 10,000,000 个 `a` → 标题设上；10,000,001 个 → 不设；5,000,001 个 😀（10,000,002 单元）→ 不设。Pascal 按 UTF-8 存载荷，但**计数必须按 UTF-16 单元**（码位 > U+FFFF 记 2）。
3. **OSC 编号没有上限**（`OscParser.ts:115-118`，JS 浮点累加）。实跑：`OSC 4294967300;1;? BEL` 不触发任何颜色事件（JS 不回绕）。32 位整数累加会回绕成 4、命中 OSC 4——Pascal 必须饱和，不能回绕（地雷 3）。
4. **参数最大 0x7FFFFFFF，JS 里 `x + 参数` 不溢出**。实跑：`CSI 1;3H` 后 `CSI 99999999999999999999 X`（ECH）擦到行尾（`"ab        "`）。Pascal 用 `Integer` 算 `x + $7FFFFFFF` 会变负、一个都不擦（地雷 3）。
5. **有几条 `while (param--)` 循环按参数次数跑**：IL / DL / SU / SD / CHT / CBT（`InputHandler.ts:1350`、`:1383`、`:1468`、`:1484`、`:1125`、`:1141`）。实跑：各 99999 次合计约 1.1 秒；2^31 次上游等于卡死。把次数钳到区域高度 / 列数，结果和上游完全等价（多出的每一轮都是空操作，开工前问题二第 12 条）。
6. **REP 的超大次数上游崩**：`repeatPrecedingCharacter`（`:1654`）先 `new Uint32Array(text.length * length)`，`CSI 2147483647 b` 实跑 120 秒不返回。这类输入没有上游答案（spec §13.5 第 6 条），Pascal 需要自定上限（开工前问题二第 11 条）。
7. **SGR 59（下划线色复位）把颜色写成 `0x3FFFFFF`，不是「默认」**：setter 掩码 `-1 & 0x3FFFFFF`（`AttributeData.ts:169-172`）。实跑：`CSI 4:3;58:5:9 m A CSI 59 m B CSI 4 m C` 三格的扩展字分别是 `0x0E000009`、`0x0FFFFFFF`、`0x07FFFFFF`。照结果移植（spec §13.5 第 2 条）。
8. **headless 的 `reset()` 不是全复位**（`src/headless/Terminal.ts:122-132`、`CoreTerminal.ts:270-276`）。实跑：复位后 OSC 8 链接号从 2 起（`_oscLinkService._nextId` 不清）、`isCursorHidden` 仍为 true、LNM 改过的 `convertEol` 仍为 true、标题不清。RIS（`ESC c`）同样不恢复隐藏的光标。所以 spec §13.5 第 5 条「`Reset` 后重跑结果要对」的**期望值必须由 node 实际复位后重跑生成**，不能假设和新建一样（开工前问题二第 14 条）。
9. **headless 不应答的几类**，实跑确认：`CSI ?1004h` 后没有 `CSI I`/`CSI O`（浏览器层在打开 1004 时立即报当前焦点，`src/browser/CoreBrowserTerminal.ts:187`、`:1124-1130`）；`CSI ?996n`、`OSC 11;? BEL` 都没有应答（`:211-258`、`:261-268`、`:524-531`）；`CSI 5n` 有（`ESC[0n`）。另外 **2031 打开时，每一次 OSC 设色 / 复位色都会触发一次明暗报告**（`ThemeService.modifyColors` / `restoreColor` 都发 `onChangeColors`，`CoreBrowserTerminal.ts:526-531`）；**换主题会丢掉所有 OSC 覆盖色**（`ThemeService._setTheme` 重建整张色表，`src/browser/services/ThemeService.ts:80-139`）；**RIS 不动主题色**（`CoreBrowserTerminal.reset` 不碰 ThemeService，`:1099-1119`）。
10. **`escape_sequence_files` 工作区里是 CRLF**：xterm.js 仓库 `.gitattributes` 是 `* text=auto`，本机 `core.autocrlf = true`，`git ls-files --eol` 显示 `i/lf w/crlf`（`t0504-vim.in` 是 `-text`）。实跑：`git show HEAD:test/fixtures/escape_sequence_files/t0003-line_wrap.in` 是 LF、3569 字节，工作区文件是 CRLF。生成脚本必须读 git 对象，否则夹具随机器的 git 设置变（地雷 9）。共 76 个 `.in` 和 3 个停用的 `.in_`（`t0031-HPB`、`t0200-SGR`、`t0220-SGR_inverse`）。
11. **上游自己的序列文件测试跳过 5 个**（`src/browser/Terminal2.test.ts:21-27`：`t0055-EL`、`t0084-CBT`、`t0101-NLM`、`t0103-reverse_wrap`、`t0504-vim`），理由都是「和真 xterm 的 `.text` 对不上」。我们比的是 Pascal 对上游、不是对 xterm，这个理由不成立（[[decision-rationale-expires-first]]）；那个测试还是经真 PTY（ONLCR 把 LF 变 CRLF）喂的。见开工前问题二第 13 条。
12. **`NOTES` 说 `t0050-ICH.text` 取自 MarkLodato/vt100-parser**，文件命名（`t0001-all_printable`、`run_tests.py`）也像那个项目的测试目录；`.in` 本身是否也出自那里、那个项目的许可，本机无法核（没有网络），Task 0 Step 3 主控核。
13. **重新折行和改尺寸绑在一起**：`Buffer.resize` 在 `_isReflowEnabled` 时先 `_reflow` 再截短行（`Buffer.ts:258-268`）；默认选项下主缓冲（有滚回）总是开折行（`:310-316`）。所以默认选项下「改列数」的上游结果**包含折行**，2 期没有它的基准；`windowsPty = {conpty, <21376}` 时折行关、行不截短，这条路径 2 期能比（开工前问题一第 3 条）。
14. **写入调度的粒度是「块」**：`_innerWrite` 在两个块之间才看 12ms（`WriteBuffer.ts:224-297`），一个大块整块解析完才让出；`InputHandler.parse` 把输入按 131072 **个输入单元**切（字节输入就是字节，`InputHandler.ts:44-45`、`:458-468`），切片之间不让出。spec §5.1 写的「131072 个码位」应为「131072 字节」。
15. **解析器单跑可行**：`out/common/parser/EscapeSequenceParser.js` 可直接 `new`，六种回退处理器 + 错误处理器能记完整轨迹。实跑：`ESC[1;2:3:4;5::6m` 的参数是 `[1,2,[3,4],5,[-1,6]]`；地面状态下的 `0x7F` 走 ERROR 动作（`["error",127,0]`）；`ESC \` 被构造函数里注册的 ESC 处理器吞掉（`EscapeSequenceParser.ts:334-335`），不进回退。
16. **1 期交接**（1 期计划末尾）：`lib-dump.js` 的 `PORTED`（过期构建检查）只列了 1 期的五个源文件；`GENERATED` 是写死的列表；`regen-all.js` 的 `SCRIPTS` 只有两个脚本；夹具读法照 `tests/test.unicode.width.pas` 的 `FixturePath` / `LoadFixture` / `Miss`。
17. **改尺寸时上游会把已处理的块再解析一遍**：`flushSync` / `writeSync` 用 `_writeBuffer.shift()` 从下标 0 取块（`WriteBuffer.ts:84`、`:137`），而一片因 12ms 预算中断后，已处理的块（`_bufferOffset` 之前）还留在数组头上（`:299-307`，超过 50 块才裁）。实跑：写 `A`、`B`、`C` 三块，让第一片只处理 `A`，再 `resize` → 第 0 行是 `"AABC"`，`A` 的回调调了两次。`CoreTerminal.resize` 每次都先 `flushSync`（`:195-197`），所以「输出正在进行时改窗口大小」就可能重复一段输出。见开工前问题一第 4 条。
18. **仓库现状**：`source/` 下没有 `tyControls.Terminal*`；`tests/tytests.lpi` 的 `OtherUnitFiles` 是 `../source;.`（测试直接编源码）；编程错误类异常用英文字面量（`source/tyControls.Form.pas:1995` 的 `EInvalidOperation.Create('...')`），不走 resourcestring；本机有 WSL（`Ubuntu`、`Ubuntu-26.04`）。

---

## 开工前要定的问题

每条都给了建议，**计划正文按建议写**；改了哪条，执行时改对应任务，收尾时（Task 23）写回 spec。

### 一、产品方向 / 用户可见（问用户）

> **已定（2026-09-29）**：用户回复「可以」——四条全部按建议：分段编译（2a、2b、2c+2d 各编一次、只跑本段 suite；全量/变异/审查期末一次）；在本机 WSL Ubuntu 用 tmux 脚本化录制；重新折行留 5 期；修上游「让出后改尺寸重复解析」的 bug 并记入 §15 偏离。用户另说明：**终端全部各期开发完成后再一次性真机验收**。第二类主控按建议采纳。
>
> **Task 0 主控部分已完成（2026-09-29）**：上游 `c58ea36` 构建完好、8 个产物在、checkout 干净；`MarkLodato/vt100-parser` 许可为 **MIT**（`Copyright (c) 2010 Mark Lodato`），其 `test/` 与 xterm.js 的 76 个 `.in` 有 48 个同名 → 按表第一行：全收，Task 22 写明部分输入最初出自 vt100-parser（MIT + 版权行）；WSL `Ubuntu` 已有 tmux 3.4、git、python3、vim、less，htop 3.3.0 已装（`wsl -u root apt-get`）。

1. **执行节奏：整期一次编译，还是按子批次分段编译？**
   本期约 9000 行 Pascal（`InputHandler` 一个就三千多行）横跨三个单元。整期写完才第一次编译，编译错误和语义错误会跨层叠在一起；好在 2a、2b 各有自己的直接基准（解析器轨迹、缓冲操作脚本），能分层定位。
   **建议**：分段编译——2a 写完编一次、只跑 2a 的 suite；2b 同理；2c + 2d 一起。每段只修本段的红，**不跑全量、不做变异、不汇报**；全量、变异、审查仍在期末一次做。你明确要求过整期批量，所以这条要你拍板；不改的话按执行方式原文做。
2. **真实程序录制从哪来？**（spec §13.4「真实程序录制」、§18「录制先用 Linux 录的几段」）
   本机有 WSL Ubuntu。主控可以用 tmux 脚本化驱动 vim / less / htop / `git log --color` / python REPL / tmux 分屏 / `cat` 中英文表情文件，`pipe-pane` 收原始输出、写成 asciicast v2（Task 14）。要在你的 WSL 里 `apt install tmux htop`（若没有），录制时清空环境（`env -i`、固定 `PS1='$ '`、固定 `HOME`），不带你的用户名、主机名、路径。
   **建议**：同意主控在 WSL 里装包并录制。不同意的话，本期「录制」类只用上游序列文件里的 5 份真实程序输出（`t0500`–`t0504`：bash 长行、ls、彩色 ls、zsh、vim），自录推到 3 期（回放示例本来就要）。
3. **重新折行仍放 5 期，接受 3、4 期拖窗口时长行不重排吗？**（核实记录 13）
   上游默认选项下改列数就会折行。2 期不移植折行，`Buffer.resize` 的折行开关恒为 false（等于上游「老 ConPTY」那条路径）：列变窄时行不截短、不重排，变宽时不合并。3、4 期的控件拖窗口时会看到这个效果，直到 5 期接上。
   **建议**：仍放 5 期（spec §18 原样）。另一个做法是把 `BufferReflow.ts`（229 行）和 `Buffer._reflow*`（约 210 行）挪进 2b，一起比基准；代价是本期再大一截。
4. **上游「改尺寸时重复解析」的 bug 修不修？**（核实记录 17）
   这是 xterm.js 的真 bug：输出正在刷、一片刚因时间预算停下，这时改窗口大小，已经显示过的那几块会再解析一遍——屏幕上重复一段输出，对应的写入回调也调两次。写入调度本来就没有上游基准（headless 看不到切片），修掉不影响任何夹具比较。
   **建议**：修——`WriteSync` 和改尺寸前的清空都从第一个没处理的块开始（Task 19），写进 spec §15 的偏离清单。照搬的话，3、4 期拖窗口时偶尔会看到重复输出。

### 二、实现层面（主控定）

5. **行的生命周期**。上游的行是 GC 对象，引用被随手复制：`shiftElements` 让两个槽位暂时指向同一行、`recycle()` 把挤掉的行拿回来重用、`print` 在 `scroll()` 前后都拿着 `oldRow`（`InputHandler.ts:579-607`）、`BufferService` 缓存一行空行（`_cachedBlankLine`）、headless `clear()` 把光标行放进 0 号槽再改长度。Pascal 手动 `Free` 很容易悬垂。**做法**：`TTyTerminalLine` 自带非原子引用计数（`AddRef` / `Release`），环形行表的每个槽位、`_cachedBlankLine` 各持一份；上游「跨一次修改还拿着行」的地方显式钉住（清单在 Task 8）。备选是 COM 接口自动计数，但每次 `lines.get` 都是原子加减，热路径太贵。守卫：`TTyTerminalLine.LiveCount`（类变量，纯查询）——Core 释放后归零、长时间滚动后等于两块缓冲的行数 + 缓存行（Task 9、Task 18）。
6. **`BufferService` 放进 Buffer 单元**（spec §2.1 把它列在 Core）。它只管滚动、视口、改尺寸，放在 Buffer 单元里 2b 就能单独对上游比（Task 6 的操作脚本要调 `scroll` / `scrollLines` / `resize`）。Core 持有一个。收尾写回 §2.1。
7. **处理器对象归解析器所有**：`RegisterOscHandler` / `RegisterDcsHandler` / `RegisterApcHandler` 传进来的对象，由解析器在 `Unregister` 或析构时释放；方法指针型（CSI / ESC / 执行 / 打印）没有所有权问题。`Register*` 返回整数句柄（spec §5.3），`Unregister` 不存在的句柄是空操作（上游 `dispose` 找不到就不动，`EscapeSequenceParser.ts:397-402`）。
8. **命名映射**：上游 `IOscHandler.end` / `IApcHandler.end` 在 Pascal 是保留字，改叫 `Finish`；`IDcsHandler.unhook` 叫 `Unhook`。其余名字照接口清单。
9. **写入调度的接口**：Core 需要告诉宿主「队列从空变非空，请排一片」，spec §7.6 没有这个事件。**做法**：加 `OnProcessRequest: TNotifyEvent`；加可注入的时钟 `Clock: TTyTerminalClock`（`function: Double of object`，毫秒带小数，默认实现：Windows 用 `QueryPerformanceCounter`——那里的 `GetTickCount64` 粒度约 15.6ms，比 12ms 预算还粗；Unix 上 FPC 的 `GetTickCount64` 已是单调毫秒钟，直接用）。写回 §7.6。
10. **12ms 预算照上游按块检查**（核实记录 14），2 期不在块内切片让出；块内切片是 5 期性能调优的事。
11. **REP 次数上限**：上游对超大次数崩（核实记录 6）。**做法**：Pascal 把重复次数钳到 1,048,576（2^20），并且分块打印、不先分配整段数组；2^20 次以内和上游逐位相同（夹具里有恰好 2^20 的用例），更大的次数是有意偏离，写回 spec §15 并在签收里告诉用户。其余 `while (param--)` 循环按核实记录 5 钳，等价，不算偏离。
12. **等价钳制**：IL / DL 钳到 `scrollBottom - y + 1`，SU / SD 钳到 `scrollBottom - scrollTop + 1`，CHT / CBT 钳到 `cols`。钳制前后的状态由夹具（参数 1000，大于任何区域）证明一致。
13. **序列文件全比、不跳**：76 个 `.in` + 3 个 `.in_` 全部进夹具，上游跳过的 5 个也比（核实记录 11），脚本注释里记上游跳过的原因；从 git 对象读（核实记录 10）；80×25、`convertEol: true`（代替真 PTY 的 ONLCR，文件本意是经终端显示）。spec §13.4 写的「照跳」写回为「不跳」。
14. **复用路径的期望值由 node 生成**（核实记录 8）：每个用例 node 跑两遍——新建跑一遍、`reset()` 后在同一个实例上再跑一遍；第二遍结果和第一遍相同就记 `"afterReset": "same"`，否则存第二份期望。Pascal 侧照样跑两遍、各比各的。
15. **夹具格式的几处细化**（写回 §13.3）：`cells` 第 4 个槽位用作「连续相同格数」（原文是占位）；`combined` 存码位数组而不是字符串；省略「整行都是默认空格、不折行、长度等于列数」的行，其余全导出；制表位导出全部为真的键、**按数值排序**（[[index-keyed-string-sort-trap]]）；超 1.8MB 自动分片 `terminal-<kind>-<n>.json`。详见「夹具格式」。
16. **鼠标**：2 期只做协议 / 编码状态和上游 `MouseStateService` 的两个纯函数（`restrictMouseEvent` / `encodeMouseEvent`，直接调上游比）；`TriggerMouseEvent`（浏览器层的上报前处理）4 期做。spec §7.6 的 `TriggerMouseEvent` 本期先不出现在接口里。
17. **焦点**：Core 记住当前焦点（`ReportFocus(AFocused)` 更新它）；DECSET 1004 打开的那一刻照浏览器层立即报一次当前焦点（核实记录 9）。spec §7.2 / §7.6 只写了「1004 开着才发」，写回。
18. **颜色**：覆盖表在 Core（spec §7.3）；照上游，每次设色 / 复位后若 2031 开着就报明暗；RIS 不清覆盖表；**宿主换主题时调 `NotifyColorSchemeChanged`，Core 清空覆盖表**（上游换主题丢掉 OSC 覆盖色，核实记录 9），然后若 2031 开着就报明暗。写回 §7.3。
19. **选项补四个**（spec §7.2 漏了，但核心代码读它们）：`CursorStyle` / `CursorBlink`（DECRQSS `" q"` 的应答和 DECRQM 12 读选项值，`InputHandler.ts:3535`、`:2376`）、`ScrollOnEraseInDisplay`（ED 2 的分支，`:1260`，默认 false）、`AllowSetCursorBlink`（`quirks.allowSetCursorBlink`，默认 false）。`termName` 固定 `'xterm'`（DA1 / DA2 的分支，不开放）。写回 §7.2。
20. **XTWINOPS 14t / 16t**：要像素尺寸，Core 只发 `OnWindowOptionsReport(Sender; AKind)`，由 3 期控件应答；默认 `WindowOptions = []`，不会走到。18t、22t、23t Core 自己处理。
21. **字符集表从上游 dump**：`gen-terminal-charsets.js` 把 `CHARSETS` 写成 `source/tyControls.Terminal.Charsets.inc`（别名 `C`/`5`、`E`/`6`、`H`/`7` 指向同一张表，dump 时保留），不手抄 253 行。
22. **异常类**：非主线程调用抛 `EInvalidOperation`（spec §3.5）；积压超过 50MB 抛新类 `ETyTerminalWriteOverflow = class(Exception)`，宿主可以单独捕获（上游抛普通 `Error`）。线程检查放在 `Write` 两个重载、`WriteSync`、`ProcessPending` 四个入口。消息是英文字面量（核实记录 18 的惯例）。
23. **`OnOsc` 的编号**：大于 `High(Integer)` 的 OSC 编号不交给宿主（上游这类编号只进日志）。
24. **折行开关**：2 期 `Buffer` 的 `IsReflowEnabled` 恒 false，代码处写明「5 期接 `BufferReflow`」；改列数的基准用例只放在 `windowsPty = {conpty, 19044}` 下（核实记录 13，按问题一第 3 条的结论可能改）。

---

## 接口清单（全计划用这一套名字）

写法照 spec §5.3、§6.3、§7.6；和 spec 不同的地方标 ★，收尾写回。上游名字写在注释里，方便对照。

### `source/tyControls.Unicode.Width.pas`（1 期已有，不改）

`TTyUnicodeVersion`、`TTyUnicodeCharProps`、`TyUnicodeCharProperties`、`TyUnicodePropsWidth`、`TyUnicodePropsShouldJoin`、`TyUnicodeWcWidth`、`TyUnicodeVersionName`。

### `source/tyControls.Terminal.Parser.pas`

```pascal
uses SysUtils, Classes, tyControls.Unicode.Width;

const
  TyTermParserPayloadLimit = 10000000;      { parser/Constants.ts:66 PAYLOAD_LIMIT, UTF-16 units }
  TyTermMaxParseBuffer = 131072;            { InputHandler.ts:45 MAX_PARSEBUFFER_LENGTH, input bytes }
  TyTermParamsMaxValue = $7FFFFFFF;         { Params.ts:11 }
  TyTermParamsMaxSubParams = 256;           { Params.ts:15 }

type
  { ParserState / ParserAction, parser/Constants.ts:9-53 -- ordinals equal upstream's numbers }
  TTyTermParserState = (tpsGround, tpsEscape, tpsEscapeIntermediate, tpsCsiEntry, tpsCsiParam,
    tpsCsiIntermediate, tpsCsiIgnore, tpsSosPmString, tpsOscString, tpsDcsEntry, tpsDcsParam,
    tpsDcsIgnore, tpsDcsIntermediate, tpsDcsPassthrough, tpsApcEntry, tpsApcIntermediate,
    tpsApcPassthrough);
  TTyTermParserAction = (tpaIgnore, tpaError, tpaPrint, tpaExecute, tpaOscStart, tpaOscPut,
    tpaOscEnd, tpaCsiDispatch, tpaParam, tpaCollect, tpaEscDispatch, tpaClear, tpaDcsHook,
    tpaDcsPut, tpaDcsUnhook, tpaApcStart, tpaApcPut, tpaApcEnd);

  TTyTerminalParams = class                   { Params.ts }
  public
    constructor Create(AMaxLength: Integer = 32; AMaxSubParamsLength: Integer = 32);  { raises EArgumentException > 256 }
    function Clone: TTyTerminalParams;
    procedure Reset; procedure ResetZdm;
    procedure AddParam(AValue: Integer); procedure AddSubParam(AValue: Integer);    { EArgumentException < -1 }
    procedure AddDigit(AValue: Integer);
    function HasSubParams(AIdx: Integer): Boolean;
    function SubParamCount(AIdx: Integer): Integer;          { getSubParams(idx).length, 0 = null }
    function SubParam(AIdx, ASub: Integer): Integer;
    function ToJson: string;                                 { JSON.stringify(toArray()), for tests and logs }
    property Params[AIdx: Integer]: Integer read GetParam; default;
    property Length: Integer read FLength;
    property MaxLength: Integer read FMaxLength;
    property MaxSubParamsLength: Integer read FMaxSubParamsLength;
  end;

  TTyTerminalPrintEvent    = procedure(const AData: array of Cardinal; AStart, AEnd: Integer) of object;
  TTyTerminalExecuteEvent  = function: Boolean of object;                 { return value ignored, as upstream }
  TTyTerminalCsiEvent      = function(AParams: TTyTerminalParams): Boolean of object;
  TTyTerminalEscEvent      = function: Boolean of object;
  TTyTerminalExecuteFallback = procedure(ACode: Cardinal) of object;      { ★ spec 只写了 OSC / CSI 回退 }
  TTyTerminalCsiFallback   = procedure(AIdent: Cardinal; AParams: TTyTerminalParams) of object;
  TTyTerminalEscFallback   = procedure(AIdent: Cardinal) of object;
  TTyTermSubAction = (tsaStart, tsaPut, tsaEnd);                          { OSC / APC: START PUT END; DCS: HOOK PUT UNHOOK }
  TTyTerminalOscFallback   = procedure(AIdent: Int64; AAction: TTyTermSubAction;
                               const APayload: string; ASuccess: Boolean) of object;   { UTF-8 payload }
  TTyTerminalDcsFallback   = procedure(AIdent: Cardinal; AAction: TTyTermSubAction;
                               AParams: TTyTerminalParams; const APayload: string; ASuccess: Boolean) of object;
  TTyTerminalApcFallback   = procedure(AIdent: Cardinal; AAction: TTyTermSubAction;
                               const APayload: string; ASuccess: Boolean) of object;
  TTyTermParsingState = record Position: Integer; Code: Cardinal; CurrentState: TTyTermParserState;
                          Collect: Cardinal; Abort: Boolean; end;         { IParsingState, minus params }
  TTyTerminalErrorEvent    = procedure(var AState: TTyTermParsingState) of object;

  TTyTerminalOscHandler = class                                          { IOscHandler }
  public
    procedure Start; virtual; abstract;
    procedure Put(const AData: array of Cardinal; AStart, AEnd: Integer); virtual; abstract;
    function Finish(ASuccess: Boolean): Boolean; virtual; abstract;     { end }
  end;
  TTyTerminalOscDataEvent = function(const AData: string): Boolean of object;      { UTF-8 }
  TTyTerminalOscStringHandler = class(TTyTerminalOscHandler)             { OscHandler, OscParser.ts:195-237 }
    constructor Create(AOnData: TTyTerminalOscDataEvent);
  end;
  TTyTerminalDcsHandler = class                                          { IDcsHandler }
  public
    procedure Hook(AParams: TTyTerminalParams); virtual; abstract;
    procedure Put(const AData: array of Cardinal; AStart, AEnd: Integer); virtual; abstract;
    function Unhook(ASuccess: Boolean): Boolean; virtual; abstract;
  end;
  TTyTerminalDcsDataEvent = function(const AData: string; AParams: TTyTerminalParams): Boolean of object;
  TTyTerminalDcsStringHandler = class(TTyTerminalDcsHandler)             { DcsHandler, DcsParser.ts:141-191 }
    constructor Create(AOnData: TTyTerminalDcsDataEvent);
  end;
  TTyTerminalApcHandler = class                                          { IApcHandler }
  public
    procedure Start; virtual; abstract;
    procedure Put(const AData: array of Cardinal; AStart, AEnd: Integer); virtual; abstract;
    function Finish(ASuccess: Boolean): Boolean; virtual; abstract;
  end;
  TTyTerminalApcStringHandler = class(TTyTerminalApcHandler)             { ApcHandler, ApcParser.ts:154-196 }
    constructor Create(AOnData: TTyTerminalOscDataEvent);
  end;

  TTyTerminalFunctionId = record Prefix, Intermediates: string; Final: Char; end;   { IFunctionIdentifier }

  TTyTerminalParser = class                                              { EscapeSequenceParser }
  public
    constructor Create;
    destructor Destroy; override;                                         { frees registered OSC/DCS/APC handler objects }
    function IdentToString(AIdent: Cardinal): string;
    procedure SetPrintHandler(AHandler: TTyTerminalPrintEvent); procedure ClearPrintHandler;
    procedure SetExecuteHandler(ACode: Byte; AHandler: TTyTerminalExecuteEvent); procedure ClearExecuteHandler(ACode: Byte);
    procedure SetExecuteHandlerFallback(AHandler: TTyTerminalExecuteFallback);
    function RegisterCsiHandler(const AId: TTyTerminalFunctionId; AHandler: TTyTerminalCsiEvent): Integer;
    procedure ClearCsiHandler(const AId: TTyTerminalFunctionId);
    procedure SetCsiHandlerFallback(AHandler: TTyTerminalCsiFallback);
    function RegisterEscHandler(const AId: TTyTerminalFunctionId; AHandler: TTyTerminalEscEvent): Integer;
    procedure ClearEscHandler(const AId: TTyTerminalFunctionId);
    procedure SetEscHandlerFallback(AHandler: TTyTerminalEscFallback);
    function RegisterOscHandler(AIdent: Integer; AHandler: TTyTerminalOscHandler): Integer;
    procedure ClearOscHandler(AIdent: Integer);
    procedure SetOscHandlerFallback(AHandler: TTyTerminalOscFallback);
    function RegisterDcsHandler(const AId: TTyTerminalFunctionId; AHandler: TTyTerminalDcsHandler): Integer;
    procedure ClearDcsHandler(const AId: TTyTerminalFunctionId);
    procedure SetDcsHandlerFallback(AHandler: TTyTerminalDcsFallback);
    function RegisterApcHandler(const AId: TTyTerminalFunctionId; AHandler: TTyTerminalApcHandler): Integer;
    procedure ClearApcHandler(const AId: TTyTerminalFunctionId);
    procedure SetApcHandlerFallback(AHandler: TTyTerminalApcFallback);
    procedure SetErrorHandler(AHandler: TTyTerminalErrorEvent); procedure ClearErrorHandler;
    procedure Unregister(AHandle: Integer);                               { IDisposable.dispose }
    procedure Parse(const AData: array of Cardinal; ALength: Integer);
    procedure Reset;
    property CurrentState: TTyTermParserState read FCurrentState;
    property PrecedingJoinState: TTyUnicodeCharProps read FPrecedingJoinState write FPrecedingJoinState;
    property OscPayloadLength ...  { ★ 纯查询：当前 OSC 字符串处理器已攒的 UTF-16 单元数；有界断言用，见 Task 5 }
  end;

  TTyUtf8Decoder = class                                                  { Utf8ToUtf32, TextDecoder.ts:121-346 }
  public
    procedure Clear;
    function Decode(const ABytes; ACount: Integer; var AOut: array of Cardinal): Integer;   { AOut >= ACount }
  end;

function TyTerminalFunctionId(const APrefix, AIntermediates: string; AFinal: Char): TTyTerminalFunctionId;
function TyTerminalCodepointsToUtf8(const AData: array of Cardinal; AStart, AEnd: Integer): string;   { utf32ToString, output UTF-8 }
function TyTerminalUtf16Length(const AData: array of Cardinal; AStart, AEnd: Integer): Integer;
```

### `source/tyControls.Terminal.Buffer.pas`

```pascal
uses SysUtils, Classes, tyControls.Unicode.Width;

const  { buffer/Constants.ts:36-157, names upper-camel with TyTerm prefix, values identical }
  TyTermContentCodepointMask = $1FFFFF; TyTermContentIsCombinedMask = $200000;
  TyTermContentHasContentMask = $3FFFFF; TyTermContentWidthMask = $C00000; TyTermContentWidthShift = 22;
  TyTermAttrCmMask = $3000000; TyTermAttrCmDefault = 0; TyTermAttrCmP16 = $1000000;
  TyTermAttrCmP256 = $2000000; TyTermAttrCmRgb = $3000000; TyTermAttrRgbMask = $FFFFFF;
  TyTermFgInverse = $4000000; TyTermFgBold = $8000000; TyTermFgUnderline = $10000000;
  TyTermFgBlink = $20000000; TyTermFgInvisible = $40000000; TyTermFgStrikethrough = $80000000;
  TyTermBgItalic = $4000000; TyTermBgDim = $8000000; TyTermBgHasExtended = $10000000;
  TyTermBgProtected = $20000000; TyTermBgOverline = $40000000;
  TyTermExtUnderlineStyle = $1C000000; TyTermExtVariantOffset = $E0000000;
  TyTermNullCellCode = 0; TyTermNullCellWidth = 1; TyTermWhitespaceCellCode = 32;

type
  TTyTermUnderlineStyle = (tusNone, tusSingle, tusDouble, tusCurly, tusDotted, tusDashed);
  TTyTerminalExtAttrs = record                     { ExtendedAttrs, AttributeData.ts:140-213 -- value type, see 地雷 6 }
    RawExt: Cardinal; UrlId: Integer;
    function Ext: Cardinal;                        { getter: DASHED forced when UrlId <> 0 }
    function UnderlineStyle: Integer; procedure SetUnderlineStyle(AValue: Integer);
    function UnderlineColor: Cardinal; procedure SetUnderlineColor(AValue: Integer);   { -1 -> $3FFFFFF, 核实记录 7 }
    function UnderlineVariantOffset: Integer; procedure SetUnderlineVariantOffset(AValue: Integer);
    function IsEmpty: Boolean;
  end;
  TTyTerminalAttrData = record                     { AttributeData }
    Fg, Bg: Cardinal; Extended: TTyTerminalExtAttrs;
    function IsProtected: Boolean; function HasExtendedAttrs: Boolean;
    procedure UpdateExtended;
    { + the colour / flag getters of AttributeData.ts:37-132, same names without "is/get" prefixes dropped }
  end;
  TTyTerminalCellData = record                     { CellData; spec 6.3 }
    Content, Fg, Bg: Cardinal; Ext: TTyTerminalExtAttrs; Combined: string;   { UTF-8 }
    function Width: Integer; function IsCombined: Boolean; function Chars: string;
  end;

  TTyTerminalLine = class                          { BufferLine; reference counted, 开工前问题二第 5 条 }
  public
    constructor Create(ACols: Integer; const AFill: TTyTerminalCellData; AIsWrapped: Boolean = False);
    procedure AddRef; procedure Release;           { Release frees at zero }
    class function LiveCount: Integer;             { pure query, leak guard }
    function GetWidth(ACol: Integer): Integer; function HasWidth(ACol: Integer): Boolean;
    function GetFg(ACol: Integer): Cardinal; function GetBg(ACol: Integer): Cardinal;
    function HasContent(ACol: Integer): Boolean; function GetCodePoint(ACol: Integer): Cardinal;
    function IsCombined(ACol: Integer): Boolean; function GetChars(ACol: Integer): string;    { getString }
    function IsProtected(ACol: Integer): Boolean;
    procedure LoadCell(ACol: Integer; var ACell: TTyTerminalCellData);
    function GetExtended(ACol: Integer): TTyTerminalExtAttrs;
    procedure SetCell(ACol: Integer; const ACell: TTyTerminalCellData);
    procedure SetCellFromCodepoint(ACol: Integer; ACodepoint: Cardinal; AWidth: Integer; const AAttrs: TTyTerminalAttrData);
    procedure AddCodepointToCell(ACol: Integer; ACodepoint: Cardinal; AWidth: Integer);
    procedure InsertCells(APos: Integer; ACount: Int64; const AFill: TTyTerminalCellData);
    procedure DeleteCells(APos: Integer; ACount: Int64; const AFill: TTyTerminalCellData);
    procedure ReplaceCells(AStart: Integer; AEnd: Int64; const AFill: TTyTerminalCellData; ARespectProtect: Boolean = False);
    function Resize(ACols: Integer; const AFill: TTyTerminalCellData): Boolean;
    procedure Fill(const AFill: TTyTerminalCellData; ARespectProtect: Boolean = False);
    procedure CopyFrom(ALine: TTyTerminalLine; ABlank: Boolean = False);
    function Clone(ABlank: Boolean = False): TTyTerminalLine;     { refcount 1, owned by caller }
    function GetTrimmedLength: Integer; function GetNoBgTrimmedLength: Integer;
    procedure CopyCellsFrom(ASrc: TTyTerminalLine; ASrcCol, ADestCol, ALength: Integer; AApplyInReverse: Boolean);
    function TranslateToString(ATrimRight: Boolean = False; AStartCol: Integer = 0; AEndCol: Integer = -1): string;
    property IsWrapped: Boolean; property Length: Integer;
  end;

  TTyTermListEvent = procedure(AIndex, AAmount: Integer) of object;
  TTyTerminalLineList = class                      { CircularList<IBufferLine>; slots own a reference }
  public
    constructor Create(AMaxLength: Integer);
    function Get(AIndex: Integer): TTyTerminalLine;               { borrowed }
    procedure SetItem(AIndex: Integer; ALine: TTyTerminalLine);   { set; takes a reference }
    procedure Push(ALine: TTyTerminalLine); function Recycle: TTyTerminalLine; function Pop: TTyTerminalLine;
    procedure Splice(AStart, ADeleteCount: Integer; const AItems: array of TTyTerminalLine);
    procedure TrimStart(ACount: Integer);
    procedure ShiftElements(AStart, ACount, AOffset: Integer);    { raises EArgumentOutOfRangeException as upstream throws }
    property Length: Integer; property MaxLength: Integer; property IsFull: Boolean;
    property OnInsert, OnDelete: TTyTermListEvent; property OnTrim: TTyTermTrimEvent;
  end;

  TTyTerminalMarker = class                        { Marker.ts }
    property Id: Integer; property Line: Integer; property IsDisposed: Boolean;
    procedure Dispose; procedure AddDisposeListener(AHandler: TNotifyEvent); procedure RemoveDisposeListener(...);
  end;

  TTyTermWindowsPtyBackend = (twpNone, twpConPty, twpWinPty);
  TTyTerminalWindowsPty = record Backend: TTyTermWindowsPtyBackend; BuildNumber: Integer; end;  { 0 = not given }
  TTyTermCharsetId = type Byte;                    { 0 = none (upstream undefined); ids index Core's charset table }
  TTyTermCursorStyleOption = (tcoBlock, tcoUnderline, tcoBar);   { options.cursorStyle }
  TTyTermTrimEvent = procedure(AAmount: Integer) of object;
  TTyTermYDispEvent = procedure(AYDisp: Integer) of object;
  TTyTermResizeEvent = procedure(ACols, ARows: Integer; AColsChanged, ARowsChanged: Boolean) of object;

  TTyTerminalOptions = class                       { the OptionsService subset of spec 7.2 + 开工前问题二第 19 条 }
    Scrollback, TabStopWidth: Integer; ConvertEol, ScrollOnUserInput, DisableStdin,
    ScrollOnEraseInDisplay, ReflowCursorLine, CursorBlink, AllowSetCursorBlink: Boolean;
    CursorStyle: TTyTermCursorStyleOption; WindowsPty: TTyTerminalWindowsPty;
    { WindowOptions / VtExtensions / Unicode live in Core (types there) }
  end;

  TTyTerminalBuffer = class                        { Buffer.ts; spec 6.3 }
  public
    function GetLine(AAbsRow: Integer): TTyTerminalLine;
    function GetWrappedRangeForLine(AAbsRow: Integer; out AFirst, ALast: Integer): Boolean;
    function AddMarker(AAbsRow: Integer): TTyTerminalMarker;
    procedure ClearMarkers(AAbsRow: Integer); procedure ClearAllMarkers;
    function GetNullCell(const AAttr: TTyTerminalAttrData): TTyTerminalCellData;   { + overload without attr }
    function GetWhitespaceCell(const AAttr: TTyTerminalAttrData): TTyTerminalCellData;
    function GetBlankLine(const AAttr: TTyTerminalAttrData; AIsWrapped: Boolean = False): TTyTerminalLine;
    procedure FillViewportRows; procedure FillViewportRows(const AAttr: TTyTerminalAttrData);
    procedure Clear; procedure Resize(ANewCols, ANewRows: Integer);
    procedure SetupTabStops(AFrom: Integer = -1);  { -1 = upstream's undefined }
    function PrevStop(AX: Integer = MaxInt): Integer; function NextStop(AX: Integer = MaxInt): Integer;  { MaxInt = this.x }
    function HasTab(ACol: Integer): Boolean; procedure SetTab(ACol: Integer; AOn: Boolean); procedure ClearAllTabs;
    function TabStops: TIntegerDynArray;           { all set keys ascending, stale ones beyond cols included }
    function TranslateBufferLineToString(AAbsRow: Integer; ATrimRight: Boolean; AStartCol: Integer = 0; AEndCol: Integer = -1): string;
    property Lines: TTyTerminalLineList; property Markers[...]: TTyTerminalMarker; property MarkerCount: Integer;
    property YBase, YDisp, X, Y, ScrollTop, ScrollBottom: Integer;
    property SavedX, SavedY: Integer; property SavedAttr: TTyTerminalAttrData;
    property SavedCharset: TTyTermCharsetId; property SavedCharsets: array of TTyTermCharsetId (+ count);
    property SavedGLevel: Integer; property SavedOriginMode, SavedWraparoundMode: Boolean;
    property HasScrollback: Boolean; property IsCursorInViewport: Boolean;
    property Length: Integer;                      { Lines.Length, spec 6.3 }
    property IsReflowEnabled: Boolean;             { phase 2: always False, 开工前问题二第 24 条 }
  end;

  TTyTermBufferActivateEvent = procedure(AActive, AInactive: TTyTerminalBuffer) of object;
  TTyTerminalBufferSet = class                     { BufferSet.ts; spec 6.3 }
    procedure Reset; procedure ActivateNormalBuffer; procedure ActivateAltBuffer; procedure ActivateAltBuffer(const AFill: TTyTerminalAttrData);
    procedure Resize(ANewCols, ANewRows: Integer); procedure SetupTabStops(AFrom: Integer = -1);
    property Normal, Alt, Active: TTyTerminalBuffer; property IsAlt: Boolean;
    property OnBufferActivate: TTyTermBufferActivateEvent;
  end;

  TTyTerminalBufferService = class                 { ★ services/BufferService.ts, moved here (开工前问题二第 6 条) }
    constructor Create(AOptions: TTyTerminalOptions; ACols, ARows: Integer);  { min 2 x 1 }
    procedure Resize(ACols, ARows: Integer); procedure Reset;
    procedure Scroll(const AEraseAttr: TTyTerminalAttrData; AIsWrapped: Boolean = False);
    procedure ScrollLines(ADisp: Integer; ASuppressScrollEvent: Boolean = False);
    property Cols, Rows: Integer; property Buffers: TTyTerminalBufferSet; property Buffer: TTyTerminalBuffer;
    property IsUserScrolling: Boolean; property OnScroll: TTyTermYDispEvent; property OnResize: TTyTermResizeEvent;
    procedure ScrollbackChanged; procedure TabStopWidthChanged;   { option-change reactions, BufferSet.ts:36-37 }
  end;

  TTyTerminalLinkData = record Id: string; HasId: Boolean; Uri: string; end;      { IOscLinkData }
  TTyTerminalOscLinks = class                      { services/OscLinkService.ts }
    constructor Create(ABufferService: TTyTerminalBufferService);
    function RegisterLink(const AData: TTyTerminalLinkData): Integer;
    procedure AddLineToLink(ALinkId, AAbsRow: Integer);
    function GetLinkData(ALinkId: Integer; out AData: TTyTerminalLinkData): Boolean;
    function LinkIds: TIntegerDynArray;            { ascending, for the oracle export }
    function LinkLines(ALinkId: Integer): TIntegerDynArray;                         { marker lines, in entry order }
  end;
```

### `source/tyControls.Terminal.Core.pas`

```pascal
uses SysUtils, Classes, Math, tyControls.Unicode.Width, tyControls.Terminal.Parser, tyControls.Terminal.Buffer;
{ 不 uses 任何 LCL 单元（spec 3.1），Task 18 有守卫 }

type
  ETyTerminalWriteOverflow = class(Exception);                         { ★ 开工前问题二第 22 条 }
  TTyTerminalDataEvent  = procedure(Sender: TObject; const AData: RawByteString) of object;
  TTyTerminalTextEvent  = procedure(Sender: TObject; const AText: string) of object;
  TTyTerminalRowsEvent  = procedure(Sender: TObject; AFirst, ALast: Integer) of object;
  TTyTerminalOscEvent   = procedure(Sender: TObject; AIdent: Integer; const AData: string; var AHandled: Boolean) of object;
  TTyTerminalWriteDone  = procedure(Sender: TObject; ATag: PtrInt) of object;
  TTyTerminalColorQuery = procedure(Sender: TObject; AIndex: Integer; out ARgb: Cardinal) of object;  { 0..255, 256 fg, 257 bg, 258 cursor }
  TTyTerminalScrollEvent = procedure(Sender: TObject; AYDisp: Integer) of object;  { ★ spec 写 TNotifyEvent；带位置和上游 onScroll 一致 }
  TTyTerminalClock = function: Double of object;                        { ★ ms }
  TTyTermWindowReport = (twrWinSizePixels, twrCellSizePixels);
  TTyTerminalWindowReportEvent = procedure(Sender: TObject; AKind: TTyTermWindowReport) of object;   { ★ }

  TTyTerminalMouseButton = (tmbLeft, tmbMiddle, tmbRight, tmbNone, tmbWheel);   { ordinals = CoreMouseButton 0..4 }
  TTyTerminalMouseAction = (tmaUp, tmaDown, tmaLeft, tmaRight, tmaMove);        { MOVE = 32 upstream: map, 地雷 12 }
  TTyTerminalMouseEvent = record Col, Row, X, Y: Integer; Button: TTyTerminalMouseButton;
    Action: TTyTerminalMouseAction; Shift, Alt, Ctrl: Boolean; end;
  TTyTerminalMouseProtocol = (tmpNone, tmpX10, tmpVT200, tmpDrag, tmpAny);
  TTyTerminalMouseEncoding = (tmeDefault, tmeSgr, tmeSgrPixels);
  TTyTermCursorRequest = (tcrDefault, tcrBlock, tcrUnderline, tcrBar);
  TTyTermBlinkRequest = (tbrDefault, tbrOn, tbrOff);
  TTyTerminalModes = record                                            { spec 7.6 }
    ApplicationCursorKeys, ApplicationKeypad, BracketedPaste, Insert, Origin, ReverseWraparound,
    SendFocus, ShowCursor, SynchronizedOutput, Win32Input, Wraparound, ColorSchemeUpdates: Boolean;
    MouseProtocol: TTyTerminalMouseProtocol; MouseEncoding: TTyTerminalMouseEncoding;
    CursorRequest: TTyTermCursorRequest; BlinkRequest: TTyTermBlinkRequest;
  end;
  TTyTermWindowOption = (twoRestoreWin, twoMinimizeWin, twoSetWinPosition, twoSetWinSizePixels,
    twoRaiseWin, twoLowerWin, twoRefreshWin, twoSetWinSizeChars, twoMaximizeWin, twoFullscreenWin,
    twoGetWinState, twoGetWinPosition, twoGetWinSizePixels, twoGetScreenSizePixels,
    twoGetCellSizePixels, twoGetWinSizeChars, twoGetScreenSizeChars, twoGetIconTitle,
    twoGetWinTitle, twoPushTitle, twoPopTitle, twoSetWinLines);      { IWindowOptions, Types.ts:248-271 }
  TTyTerminalWindowOptions = set of TTyTermWindowOption;
  TTyTermVtExtension = (tveKittyKeyboard, tveWin32InputMode, tveKittySgrBoldFaint, tveColorSchemeQuery);
  TTyTerminalVtExtensions = set of TTyTermVtExtension;                 { default [tveKittySgrBoldFaint, tveColorSchemeQuery] }

  TTyTerminalCore = class                                              { spec 7.6 }
  public
    constructor Create(ACols, ARows: Integer);
    destructor Destroy; override;
    { 写入 -- 2d }
    procedure Write(const AData: RawByteString; AOnDone: TTyTerminalWriteDone = nil; ATag: PtrInt = 0);
    procedure Write(const ABuf; ACount: Integer; AOnDone: TTyTerminalWriteDone = nil; ATag: PtrInt = 0);
    procedure WriteSync(const AData: RawByteString);
    function  ProcessPending(ABudgetMs: Integer = 12): Boolean;
    property  PendingBytes: Int64;
    property  Clock: TTyTerminalClock;                                  { ★ nil = built-in high-resolution clock }
    { 输入 }
    procedure Input(const AData: RawByteString; AWasUserInput: Boolean = True);
    function  RestrictMouseEvent(var AEvent: TTyTerminalMouseEvent): Boolean;          { ★ MouseStateService.restrictMouseEvent }
    function  EncodeMouseEvent(const AEvent: TTyTerminalMouseEvent): RawByteString;    { ★ encodeMouseEvent; '' = suppressed }
    procedure ReportFocus(AFocused: Boolean);                          { also remembered for DECSET 1004, 问题二第 17 条 }
    property  Focused: Boolean;                                         { ★ }
    procedure NotifyColorSchemeChanged;                                 { clears the overlay, then reports if 2031 }
    { 尺寸与状态 }
    procedure Resize(ACols, ARows: Integer);                            { min 2 x 1; flushes pending first }
    procedure Reset;                                                    { headless Terminal.reset }
    procedure ScrollLines(ADelta: Integer); procedure ScrollPages(APages: Integer);
    procedure ScrollToBottom; procedure ScrollToTop;
    procedure ClearScrollback;                                          { headless Terminal.clear }
    property  Cols, Rows: Integer; property Buffers: TTyTerminalBufferSet; property Buffer: TTyTerminalBuffer;
    property  Modes: TTyTerminalModes; property Title: string; property IconName: string;
    property  Parser: TTyTerminalParser; property Links: TTyTerminalOscLinks;
    function  ResolveColor(AIndex: Integer): Cardinal;
    function  HasColorOverride(AIndex: Integer): Boolean;              { ★ pure query for tests / renderer }
    { 选项 }
    property  Scrollback, TabStopWidth: Integer;
    property  ConvertEol, ScrollOnUserInput, ReadOnly, AmbiguousWide: Boolean;
    property  UnicodeVersion: TTyUnicodeVersion;                        { default tuv11 }
    property  WindowsPty: TTyTerminalWindowsPty;
    property  WindowOptions: TTyTerminalWindowOptions; property VtExtensions: TTyTerminalVtExtensions;
    property  CursorStyle: TTyTermCursorStyleOption; property CursorBlink: Boolean;   { ★ }
    property  ScrollOnEraseInDisplay, AllowSetCursorBlink: Boolean;     { ★ }
    { 事件 }
    property  OnData: TTyTerminalDataEvent; property OnRefreshRows: TTyTerminalRowsEvent;
    property  OnTitleChange, OnIconNameChange: TTyTerminalTextEvent;
    property  OnBell, OnCursorMove, OnLineFeed, OnBufferActivate, OnModesChange: TNotifyEvent;
    property  OnScroll: TTyTerminalScrollEvent;
    property  OnOsc: TTyTerminalOscEvent; property OnQueryBaseColor: TTyTerminalColorQuery;
    property  OnRequestScrollToBottom: TNotifyEvent;
    property  OnProcessRequest: TNotifyEvent;                           { ★ }
    property  OnWindowOptionsReport: TTyTerminalWindowReportEvent;     { ★ }
  end;

function TyTermDefaultClock: Double;   { ★ built-in monotonic clock, ms; Task 19 }
const TyTermLibraryVersion = '3.1.0';     { ★ = TyVersion; tyControls.Types uses LCL, Task 17 }
```

`OnIconNameChange`：上游 `setIconName` 只存不发事件（`InputHandler.ts:3052-3055`），我们照 spec 发；夹具比 `IconName` 的终值。`OnModesChange`：上游没有这个事件，Core 在任何模式字段变化后发一次（每条 CSI 最多一次）；本期只写判据测试（Task 18），不比基准。

---

## 文件清单

| 文件 | 本期做什么 |
|---|---|
| `tools/terminal-oracle/lib-dump.js` | 改（Task 1）。`PORTED` 补本期移植的源文件；`GENERATED` 支持分片模式；`gitBlob()` |
| `tools/terminal-oracle/lib-term.js` | **新建**（Task 1）。建终端、跑步骤、导出状态、合成应答器、PRNG、base64 |
| `tools/terminal-oracle/regen-all.js` | 改（Task 1、各生成任务）。`SCRIPTS` 追加本期脚本；分片的旧文件清理 |
| `tools/terminal-oracle/cases/parser.js`、`parser-cases.js` | **新建**（Task 2） |
| `tools/terminal-oracle/cases/buffer.js`、`buffer-cases.js` | **新建**（Task 6） |
| `tools/terminal-oracle/gen-terminal-charsets.js` | **新建**（Task 10） |
| `tools/terminal-oracle/cases/core-hand.js`、`core-cases.js` | **新建**（Task 11） |
| `tools/terminal-oracle/escape-files.js` | **新建**（Task 12） |
| `tools/terminal-oracle/fuzz.js` | **新建**（Task 13） |
| `tools/terminal-oracle/recordings.js`、`recordings/*.cast`、`wsl-record.sh`、`wsl-record-pipe.py` | **新建**（Task 14；录制主控执行，看问题一第 2 条） |
| `source/tyControls.Terminal.Parser.pas` | **新建**（Task 3、4） |
| `source/tyControls.Terminal.Buffer.pas` | **新建**（Task 7、8） |
| `source/tyControls.Terminal.Charsets.inc` | **生成**（Task 10），不进 `.lpk` |
| `source/tyControls.Terminal.Core.pas` | **新建**（Task 15–17、19） |
| `tycontrols.lpk` | `<Files>` 末尾依次加三个单元（Task 3、7、15） |
| `tests/fixtures/terminal-*.json` | **生成**（Task 2、6、11–14） |
| `tests/test.terminal.oracle.pas` | **新建**（Task 5），Task 9、18 扩展。夹具读取、步骤执行、比较器；不注册测试 |
| `tests/test.terminal.parser.pas` | **新建**（Task 5） |
| `tests/test.terminal.buffer.pas` | **新建**（Task 9） |
| `tests/test.terminal.core.pas` | **新建**（Task 18、20） |
| `tests/tytests.lpr` | uses 加五个测试单元（Task 5：`test.terminal.oracle`、`test.terminal.parser`；Task 9：`test.terminal.buffer`；Task 18：`test.terminal.core`） |
| `tools/terminal-probe/terminalprobe.lpr`、`terminalprobe.lpi` | **新建**（Task 21） |
| `THIRD-PARTY-NOTICES.md`、`tests/test.release.pas` | 改（Task 22） |
| `docs/superpowers/specs/2026-09-28-terminal-view-design.md` | 只在 Task 23 写回 |

**不碰**：`source/` 下其他单元（包括 `tyControls.Unicode.Width*`）、`designtime/`、`themes/`、`examples/`、`languages/`、`README*`、`CHANGELOG*`、`D:/Projects/xterm.js` 下任何受版本控制的文件。

---

## 实现期的地雷（每个任务开工前看一眼）

1. **只经 `lib-dump.js` 加载上游**（1 期地雷 1）：新脚本都 `require('./lib-term.js')`，它再 `require('./lib-dump.js')`。上游模块路径用 `L.XTERM + '/' + L.OUT_DIR + '/common/...'`，不写死 `out`。
2. **过期构建检查要跟上**：每移植一个新的 `.ts`，把「源文件 → 产物」对加进 `lib-dump.js` 的 `PORTED`（Task 1 一次加齐，后面任务发现漏了就补），否则切过 commit 没重编的 `out/` 会静默给出旧代码的答案。
3. **JS 的数不是 Pascal 的 `Integer`**（核实记录 3、4，[[js-round-has-no-domain]]）：
   - CSI 参数最大 `$7FFFFFFF`，凡是「坐标 + 参数」「参数 × 长度」一律在 `Int64` 里算，钳完再落回 `Integer`（`_moveCursor`、`_setCursor`、ECH 的 `x + n`、REP 的 `length * text.length`、DECSTBM）。
   - OSC 编号在 `Int64` 里饱和累加（上限取 `High(Int64) div 10` 以下就停止乘 10），**不回绕**。
   - `Params.AddDigit` 的 `cur * 10 + value` 在 `Int64` 里算再钳。
   - `CircularList._startIndex` 上游只增不减（`splice` / `trimStart` 不取模）；Pascal 每次加完取 `mod MaxLength`，下标运算等价（`_getCyclicIndex` 本来就取模）。
   - 位运算：上游 `>>` 是有符号右移（`underlineVariantOffset` 的 `>> 29` 得负数、再 `^ 0xFFFFFFF8`），Pascal 用 `SarLongint`；`fg` / `bg` 的第 31 位（删除线、上游 JS 里是负数）在 Pascal 用 `Cardinal`，导出比较前 node 侧一律 `>>> 0`。
   - `Math.round` 是「.5 向正无穷」，Pascal `Round` 是银行家舍入：`XParseColor` 用 `Floor(x + 0.5)`，且按上游顺序先除后乘（`v / base * 255`）。
   - 参数串转数（OSC 4 / 104 的颜色号）不用 `StrToInt`（超长数字会抛），手写饱和解析。
4. **REP 与循环的钳制**只在开工前问题二第 11、12 条列出的地方做，别「顺手」钳别处。
5. **CRLF 与反斜杠**：含 `\x1b`、`\u` 的 JS 一律用 Write 工具落文件，不用 Bash heredoc（[[bash-heredoc-eats-backslashes]]）；改 `.pas` 用编辑工具，不用 Git Bash 的 `sed -i`（[[git-bash-sed-strips-crlf]]）；期末变异先 `git diff --stat` 确认改到了（[[crlf-mutation-phantom-survivor]]）。
6. **扩展属性按值存**：上游 `ExtendedAttrs` 是对象、被多个格子共享引用，但每次修改前都先 `clone()`（`InputHandler.ts:2469`、`:2488`、`:2509`、`:2708`、`:3138`、`:3145`），所以按值存等价。**不要**移植任何「就地改共享扩展属性」的写法；审查时逐处核「改之前有没有 clone」。
7. **行的引用计数**（开工前问题二第 5 条）：槽位赋值一律经 `SetItem` / `Push` / `Splice`；`Get` 返回借用；跨一次列表修改还要用的行必须 `AddRef` / `Release`（清单在 Task 8）。
8. **FPC 的 `{ }` 注释会嵌套**（[[fpc-brace-comments-nest]]）：单元注释里别写 JSON、别写 `{}` 示例；生成的 `.inc` 头部由脚本断言没有花括号。
9. **序列文件从 git 对象读**（核实记录 10）：`L.gitBlob('test/fixtures/escape_sequence_files/<name>')` = `git -C XTERM show <commit>:<path>`，拿 `Buffer`，不经 `fs.readFileSync`。
10. **生成可复现**（spec §13.5 第 7 条）：不读时间；随机数只用 `lib-term.js` 的 `prng(seed)`，种子写进夹具；对象键固定顺序；`JSON.stringify` 不缩进；`regen-all.js --expect-clean` 必须 `clean`。
11. **fpcunit 断言别放进大循环**（1 期地雷 11）：比较器只计数、记前 30 条，循环外断言一次；NaN 不会出现（全是整数）。
12. **枚举序号 ≠ 上游数值**：`TTyTerminalMouseAction` 的 `tmaMove` 序号是 4，上游 `MOVE = 32`；`TTyTermParserState` / `TTyTermParserAction` 的序号必须等于上游（夹具里存的是数）。凡是和上游数值比的枚举，单元里写一个显式映射函数，别用 `Ord`。
13. **headless 的 `reset()` 不是全复位**（核实记录 8）：Pascal `TTyTerminalCore.Reset` 照 headless 移植——不清标题、不恢复光标可见、不清链接号计数、不复位解析器；`fullReset`（RIS）只多一个 `parser.reset()`。别把它「修」成全复位。
14. **新单元要进 `.lpk`**（[[new-unit-missing-from-lpk]]），`.inc` 不进；新测试单元要进 `tests/tytests.lpr` 的 uses（`TReleaseManifestTest.EveryTestUnitThatRegistersTestsIsLinked` 守着；`test.terminal.oracle` 不注册测试，也要进 uses，被其他单元引用即可）。
15. **Core 不依赖 LCL**（spec §3.1）：三个单元的 uses 只能有 `SysUtils`、`Classes`、`Math`、`Types`、`Windows`（只在 `{$IFDEF MSWINDOWS}` 里、给时钟用）、1 期的 `tyControls.Unicode.Width` 和彼此。`Application.QueueAsyncCall` 是 3 期控件的事。
16. **跑测试时别被全量的偶发失败骗**（[[known-rare-suite-flake]]、[[suite-order-widgetset-init]]）：全量输出重定向到文件；全量红单跑绿先查 exe 是否陈旧（[[canary-then-rebuild]]）。

---

## 夹具格式

所有夹具在 `tests/fixtures/`，平铺命名 `terminal-<kind>[-<n>].json`，单个文件 ≤ 2MB（`writeFixture` 超 1.8MB 自动分片，见 Task 1）。所有文件共用外壳：

```
{ "upstream": { "name", "version", "commit", "commitDate" },   // lib-dump upstreamInfo()
  "generator": "tools/terminal-oracle/<script>.js",
  "kind": "<kind>", "part": 1, "parts": 1,
  "cases": [ { "id", "source", "note"?, ... } ] }
```

`source` 取 `hand` / `escape-file` / `recording` / `fuzz` / `synthesized` / `long`（spec §13.5 第 4 条）；切块变体不单列来源，挂在原用例的 `variants` 里。字节一律 base64（[[fpjson-drops-u0000]]）。

**长串摘要**：任何要存的字符串或码位数组（打印事件的码位、OSC / DCS / APC 载荷、标题）超过 256 个码位时，改存 `{ "n": 码位数, "h": 摘要 }`，摘要是按码位算的 32 位 FNV-1a 变体——`h = 0x811C9DC5; for (cp of 码位) { h = Math.imul(h ^ cp, 0x01000193) >>> 0; }`。Pascal 侧同一公式（`Cardinal` 乘法自然回绕，关掉溢出检查的局部 `{$Q-}`），UTF-8 串先解成码位再算。两侧都在 `test.terminal.oracle` / `lib-term.js` 里只写一份。

### 解析器层（Task 2 写，Task 5 读）

- `terminal-parser-table.json`：`{ "table": [start0, value0, start1, value1, ...] }`，上游 `VT500_TRANSITION_TABLE.table`（4257 项）压成区间。
- `terminal-parser-utf8.json`：每个用例 `{ id, source, chunks: [b64...], out: [[cp...] ...] }`——`out[k]` 是第 k 次 `decode` 返回的码位（同一个解码器实例连续调用）。
- `terminal-parser-trace.json`：每个用例

  ```
  { id, source, register: [ <handler setup> ... ],
    feed: [ { "cp": [..] } | { "repeat": { "cp": [..], "times": n } } | { "reset": 1 }
          | { "unregister": k } ... ],
    trace: [ <event> ... ], finalState: <int>, finalJoinState: <int> }
  ```

  `<event>` 是数组：`["print", [cp...]]`、`["exec", code]`、`["csi", ident, paramsJson]`、`["esc", ident]`、`["osc", ident, "START"|"PUT"|"END", payload|null, success|null]`、`["dcs", ident, "HOOK"|"PUT"|"UNHOOK", paramsJson|payload|null, success|null]`、`["apc", ident, "START"|"PUT"|"END", payload|null, success|null]`、`["error", code, state]`，以及注册处理器的事件 `["h", k, <kind>, ...]`（k = `register` 里的序号）。`paramsJson` 是 `JSON.stringify(params.toArray())` 的字符串。`<handler setup>` 的词表在 Task 2。

### 缓冲层（Task 6 写，Task 9 读）

`terminal-buffer-ops.json`：每个用例 `{ id, target: "line"|"list"|"buffers", init, ops: [[name, ...args] ...], after: [<snapshot per op>] }`。`name` 与参数的词表、快照格式在 Task 6。

### 核心层（Task 11–14 写，Task 18 读）——spec §13.3 的细化

```
{ id, source, cols, rows,
  options: { scrollback, tabStopWidth, convertEol, scrollOnUserInput, disableStdin,
             scrollOnEraseInDisplay, cursorStyle, cursorBlink, allowSetCursorBlink,
             unicodeVersion: "6"|"11"|"15"|"15-graphemes", ambiguousWide,
             windowsPty: null | { backend: "conpty"|"winpty", buildNumber },
             windowOptions: [names], vtExtensions: { kittyKeyboard, win32InputMode,
             kittySgrBoldFaintControl, colorSchemeQuery } },       // 缺省 = 下表默认
  synth?: { palette?: [259 × 0xRRGGBB], focused?: bool },        // 覆盖文件级缺省；应答器总是挂着
  steps: [ { "write": b64 } | { "writeRepeat": { "b64", "times" } } | { "resize": [c, r] }
         | { "input": b64, "user": bool } | { "reset": 1 } | { "clear": 1 }
         | { "scrollLines": n } | { "scrollToTop": 1 } | { "scrollToBottom": 1 }
         | { "setOption": { name: value } } | { "focus": bool } | { "theme": [259 ints] } ],
  variants?: [ { "cuts": "each" | [byteOffsets...] } ],          // 只对单个 write 的用例：切块喂，期望相同
  expect: <state>, afterReset: "same" | <state> }
```

**合成应答器总是挂着**：Pascal 的 Core 总会应答颜色查询、明暗查询、打开 1004 时的焦点，所以 node 侧每个核心用例都挂应答器（不只 `synthesized` 类）——否则随机字节、录制、序列文件里一旦出现 `CSI ?1004h`（vim、tmux 都会发）或 `CSI ?996n`，两边就对不上。核心夹具的外壳多一个 `palette`（259 项，`lib-term.js` 的 `DEFAULT_PALETTE`：0–15 抄 xterm.js 的 Tango 默认 `src/browser/Types.ts:183-203`，16–231 是 6 × 6 × 6 立方 `0, 95, 135, 175, 215, 255`，232–255 灰阶 `8 + 10 × i`，256 前景 `0xFFFFFF`、257 背景 `0x000000`、258 光标 `0xFFFFFF`；Pascal 从夹具读，不写死），用例的 `synth` 只在要换色表或 `focused: false` 时出现。

缺省选项：`scrollback 1000, tabStopWidth 8, convertEol false, scrollOnUserInput true, disableStdin false, scrollOnEraseInDisplay false, cursorStyle "block", cursorBlink false, allowSetCursorBlink false, unicodeVersion "11", ambiguousWide false, windowsPty null, windowOptions [], vtExtensions { kittyKeyboard false, win32InputMode false, kittySgrBoldFaintControl true, colorSchemeQuery true }`。

`<state>`：

```
{ active: "normal"|"alt",
  buffers: { normal: <buf>, alt: <buf> },
  modes: { applicationCursorKeys, applicationKeypad, bracketedPaste, insert, origin,
           reverseWraparound, sendFocus, showCursor, synchronizedOutput, win32Input,
           wraparound, colorSchemeUpdates, mouseProtocol: "NONE"|"X10"|"VT200"|"DRAG"|"ANY",
           mouseEncoding: "DEFAULT"|"SGR"|"SGR_PIXELS", cursorStyle: null|"block"|..., cursorBlink: null|bool,
           kittyFlags },
  options: { convertEol, cursorBlink },                            // 序列能改的两个选项的终值
  charset: { glevel, g: [key|null × 4] },                          // key = CHARSETS 的键，别名取第一个
  title, iconName, bells, lineFeeds, cursorMoves,
  titles: [..], renders: [[start, end]..], scrolls: [ydisp..],
  data: b64,                                                       // onData 字符串按 UTF-8 编码后拼接
  links: [ { linkId, id|null, uri, lines: [..] } ],                // linkId 升序
  parserState, joinState }

<buf> = { x, y, ybase, ydisp, length, maxLength, hasScrollback, scrollTop, scrollBottom,
          tabs: [..],                                              // 数值升序
          saved: { x, y, fg, bg, glevel, origin, wrap },
          markers: [line..],                                       // 该缓冲上未作废的标记行号，按创建顺序
          lines: [ { i, w?: 1, len?: n, t: text, c: [[content, fg, bg, run] ..],
                     comb?: { col: [cp..] }, ext?: { col: [ext, urlId, ulColor, ulVariant] } } ] }
```

- `lines` 里 `i` 是绝对行号（`lines.get(i)`）；**省略**「长度 = cols、不折行、每格都是 `[1<<22, 0, 0]`、没有组合 / 扩展」的行，其余全部导出。Pascal 侧：没导出的行必须恰好是这种默认行。
- `c` 是按列展开前的**游程**：连续相同的 `[content, fg, bg]` 合成一项，`run` 是个数（spec §13.3 的第 4 个槽位）；展开后长度必须等于 `len ?? cols`。
- `comb` 的键是列号，值是码位数组；`ext` 只列 `bg` 带 `HAS_EXTENDED` 的格。
- `t` 是 `translateToString(true)`，只给人看，失败时打印，不参与判定（spec §13.3）。
- XTVERSION 的归一化：应答在 `data` 里，node 侧把 `xterm.js(6.0.0)` 换成占位 `\u0000VERSION\u0000`，Pascal 侧把 `TyControls(3.1.0)` 换成同一占位后再比（spec §13.5 第 3 条；两边各有一个 `Normalize`，只处理这一条和合成应答两件事）。

### 鼠标编码（Task 11 写，Task 18 读）

`terminal-core-mouse.json`：每个用例 `{ id, protocol, encoding, event: {col,row,x,y,button,action,ctrl,alt,shift}, restrict: bool, eventAfter: {...}, encoded: b64|null }`——直接调上游 `mouseStateService.restrictMouseEvent` / `encodeMouseEvent`，`restrict` 会改事件里的修饰位，所以记下改后的事件。

---

## 比较器判据（Task 5 建单元，Task 9、18 扩展）

`tests/test.terminal.oracle.pas` 提供（Task 5 写收集器、夹具读取、摘要；Task 9 写行 / 缓冲比较；Task 18 写 Core 的驱动与整体比较）：

| 名字 | 做什么 | 判据 |
|---|---|---|
| `TTyTermMisses` | 失败收集器 | `Add(ACaseId, APath, AWant, AGot)`：计数、只存前 30 条；`Compared`（比较次数）单独计数；`Text` 给断言消息 |
| `TyTermLoadFixtures(AKind)` | 读 `terminal-<kind>.json` 和 `terminal-<kind>-<n>.json` 全部分片 | 分片的 `parts` 必须一致、`part` 连号，否则当作一次 miss（旧分片残留会被抓到） |
| `TyTermCompareLine` | 一行对 JSON 行 | 逐格比 `content` / `fg` / `bg`、组合码位、扩展四元组、`IsWrapped`、`Length`；失败路径写成 `case <id> [variant <v>] / <normal|alt> / abs row <i> (viewport row <i-ybase>) / col <c> / <field>: want $XXXXXXXX got $YYYYYYYY`，再附两边的行文本 |
| `TyTermCompareState` | Core 对 `<state>` | 上面每个字段；缺省行按「默认行」比；`Compared` 至少加上 `两块缓冲的总行数 × 列数` |
| `TTyTermHarness` | 给 Core 挂记录器、按 `steps` 驱动 | `OnData` 拼字节、`OnBell` 计数、`OnTitleChange` 列表、`OnRefreshRows` 列表、`OnScroll` 列表、`OnLineFeed` / `OnCursorMove` 计数；`OnQueryBaseColor` 答色表（用例的 `synth.palette`，否则文件级 `palette`），建好后先 `ReportFocus(focused)`（缺省 true；此时 1004 未开，不发字节） |

- 每个核心用例跑两遍（spec §13.5 第 5 条）：一个新建的 Core 跑完比 `expect`；同一个 Core 调 `Reset` 后再跑一遍比 `afterReset`（`"same"` 就再比 `expect`）。
- 每个用例、每个 `variants` 项都各跑一遍比同一份 `expect`（切块喂：`cuts` 是切点字节偏移，`"each"` = 每字节一次 `WriteSync`）。
- 所有测试结尾断言 `Compared > 0` 且等于从夹具算出来的应比次数（[[assertion-never-varies-the-thing]]：夹具读空、循环提前退出会零次比较全绿）。

---

## 跑测试的固定套路（只在 Task 23 用；若问题一第 1 条选了分段编译，也在每段末用）

改了 `source/` 之后**必须** `lazbuild -B`（[[example-stale-lib-on-source-change]]、[[canary-then-rebuild]]）。exe 用唯一名 `tytests-term.exe`。

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi > /tmp/term-build.txt 2>&1 || { tail -30 /tmp/term-build.txt; false; } && cd tests && cp tytests.exe tytests-term.exe && for s in TTyTerminalParserOracleTests TTyTerminalParserTests TTyTerminalBufferOracleTests TTyTerminalBufferTests TTyTerminalCoreOracleTests TTyTerminalCoreTests TTyTerminalWriteQueueTests TReleaseManifestTest; do ./tytests-term.exe --suite=$s --format=plain > /tmp/term-$s.txt 2>&1; printf '%s: ' $s; grep -E "Number of (run tests|errors|failures)" /tmp/term-$s.txt | tr '\n' ' '; echo; done
```

**判据是每个 suite 那一行都有 `Number of run tests`、errors / failures 为 0**，不是 exit code。某一行为空 = 跑丢了（或 suite 名写错），重跑，别读成通过。分段编译时只跑本段的 suite。

全量（输出必须重定向到文件，[[known-rare-suite-flake]]）：

```bash
cd /d/Projects/ty-3.1/tests && ./tytests-term.exe --all --format=plain > /tmp/term-all.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/term-all.txt
```

node 侧：

```bash
cd /d/Projects/ty-3.1 && node tools/terminal-oracle/regen-all.js --expect-clean
```

## 关于判据和变异

- 纯函数给**输入 / 期望表**；夹具比较写**判据**（比什么、怎么数、失败打印什么），测试代码执行时现写。
- 每个任务的「变异表」列的是**期末集中做**的变异（Task 23 Step 5）：改一行 → `git diff --stat` 确认改到了 → `lazbuild -B` → 跑相关 suite → **必须红** → 改回 → 重编重跑 → 绿。没红的先查改没改对地方；确实没红，当场补测试，签收记录写一句。
- 标「等价」的变异不做，理由写在表里（审查时核）。会死循环的变异（循环变量不前进）不做；卡住时按进程号结束 `tytests-term.exe`，**禁用 `taskkill -im`**（[[parallel-agent-worktree-hazards]]）。

---

### Task 0: 基线与主控准备

**Files:** 无（Step 3、4 的结论记草稿，Task 12、14、22 用）

- [ ] **Step 1: 确认起点**

```bash
cd /d/Projects/ty-3.1 && git status --short && git branch --show-current && git log --oneline -1
```

Expected：工作区干净，分支 `feat/terminal`，HEAD 是本计划的提交或其后。

- [ ] **Step 2: 【主控执行】复核上游构建**

```bash
cd /d/Projects/xterm.js && git status --short && git rev-parse HEAD && ls out/common/InputHandler.js out/common/parser/EscapeSequenceParser.js out/common/buffer/BufferLine.js out/common/CircularList.js out/common/input/TextDecoder.js out/common/input/WriteBuffer.js out/common/services/MouseStateService.js out/common/data/Charsets.js
```

Expected：`git status --short` 为空；HEAD 以 `c58ea36` 开头；八个产物都在。缺任何一个：`npm run build`（1 期已装好依赖），再查一遍 `git status --short` 仍为空。

- [ ] **Step 3: 【主控执行】核对 `escape_sequence_files` 的外部来源**（核实记录 12，spec §17.2 第 9 条）

看 `https://github.com/MarkLodato/vt100-parser`：(a) 许可（仓库 `LICENSE` / `COPYING` / README）；(b) 它的测试目录里有没有和 `D:/Projects/xterm.js/test/fixtures/escape_sequence_files/*.in` 同名的输入文件。结论记草稿，按下表定 Task 12 的范围：

| 情况 | Task 12 怎么做 | Task 22 怎么写 |
|---|---|---|
| vt100-parser 是 MIT / BSD / Apache 等宽松许可 | 79 个输入全收 | 「测试夹具」小节写：输入来自 xterm.js（MIT），部分最初出自 vt100-parser（许可名 + 版权行） |
| 许可不宽松或查不到，但 `.in` 不在那个项目里 | 全收 | 只写 xterm.js |
| 许可不宽松或查不到，且部分 `.in` 出自那里 | 只收不重名的；重名的在 `escape-files.js` 的 `EXCLUDED` 里列出并注明原因 | 只写 xterm.js；小节注明排除了哪些 |

- [ ] **Step 4: 【主控执行，看问题一第 2 条】准备 WSL 录制环境**

用户同意后：

```bash
wsl.exe -d Ubuntu -- bash -lc "command -v tmux htop git python3 vim less; tmux -V"
```

缺哪个就 `wsl.exe -d Ubuntu -- sudo apt-get install -y tmux htop`（需要用户在场输密码时，交给用户）。用户不同意：记下「本期录制类只用 t0500–t0504」，Task 14 跳过录制部分。

- [ ] **Step 5: 编译并跑全量，记下基线条数**（实现 agent 做）

用「跑测试的固定套路」的全量命令（先 `lazbuild -B tests/tytests.lpi`、拷成 `tytests-term.exe`）。条数记进草稿，Task 23 签收时写进本计划末尾。**有红就停**。

本任务没有提交。

---

### Task 1: 基准脚本公共部分

**Files:**
- Modify: `tools/terminal-oracle/lib-dump.js`
- Create: `tools/terminal-oracle/lib-term.js`
- Modify: `tools/terminal-oracle/regen-all.js`

- [ ] **Step 1: 改 `lib-dump.js`**（编辑工具）

1. `PORTED` 追加（源文件 → `${OUT_DIR}` 下的产物，路径照已有的五对写法）：`src/common/parser/{EscapeSequenceParser,Params,OscParser,DcsParser,ApcParser,Constants}.ts`、`src/common/StringBuilder.ts`、`src/common/input/{TextDecoder,WriteBuffer,XParseColor}.ts`、`src/common/buffer/{Buffer,BufferLine,AttributeData,CellData,Constants,BufferSet,Marker}.ts`、`src/common/CircularList.ts`、`src/common/InputHandler.ts`、`src/common/CoreTerminal.ts`、`src/common/WindowsMode.ts`、`src/common/data/Charsets.ts`、`src/common/services/{BufferService,CoreService,CharsetService,MouseStateService,OscLinkService}.ts`、`src/headless/Terminal.ts`。
2. 导出 `OUT_DIR`。
3. `GENERATED` 改成「精确路径或正则」两种项：保留原四项，追加 `'source/tyControls.Terminal.Charsets.inc'` 和 `/^tests\/fixtures\/terminal-(parser|buffer|core)-[a-z0-9-]+\.json$/`；`writeGenerated` 的登记检查改为「命中任一项」；导出 `isGenerated(rel)`。
4. 新函数 `gitBlob(rel)`：`cp.execFileSync('git', ['-C', XTERM, 'show', 'HEAD:' + rel])`，返回 `Buffer`（地雷 9）；`upstreamInfo()` 已保证 HEAD 是钉住的 commit、工作区干净。
5. `writeFixture(name, obj)` 签名不变（`name` 是文件名，1 期的三个调用照旧）。`obj` 带 `cases` 数组时增加分片：序列化后超过 1,800,000 字节就按用例顺序切成若干片，文件名在 `.json` 前插 `-<n>`（`terminal-core-hand.json` → `terminal-core-hand-1.json` …），每片外壳相同、`part` / `parts` 填好；不超就写单个 `name`（`part: 1, parts: 1`）。没有 `cases` 的（1 期夹具）只做原来的 2MB 检查。写之前删掉同一名字的其他形态（单文件 ↔ 分片切换、分片数变少时的残留），删除也只许动 `isGenerated` 命中的文件。单个用例本身超 1.8MB 就报错（用例要拆）。

- [ ] **Step 2: 写 `lib-term.js`**（Write 工具，地雷 5）

要求（代码结构执行者定，关键函数的语义照这里）：

1. 头部注释：这个文件做什么、只经 `lib-dump.js` 加载上游、夹具格式在本计划「夹具格式」一节、合成应答器抄自哪几处源码（行号）。
2. 导出 `b64(bytes)`、`unb64(s)`、`utf8(s)`、`cps(str)`（串 → 码位数组，按 `for...of`）、`digestable(x)`（「夹具格式」的长串摘要规则：≤ 256 码位原样返回，否则 `{n, h}`）、`prng(seed)`——mulberry32：

   ```js
   function prng(seed) {
     let a = seed >>> 0;
     return () => {
       a = (a + 0x6D2B79F5) >>> 0;
       let t = a;
       t = Math.imul(t ^ (t >>> 15), t | 1);
       t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
       return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
     };
   }
   ```

3. `DEFAULT_OPTIONS`（「夹具格式」的缺省表）、`DEFAULT_PALETTE`（「夹具格式」的缺省色表）、`writeCoreFixture(name, kind, cases)`（外壳带 `palette: DEFAULT_PALETTE`，再调 `L.writeFixture`；所有核心生成脚本都用它）、`normalizeOptions(c)`：把用例的 `options` 补齐缺省，**只输出和缺省不同的键**写回夹具（体积）。
4. `makeCaseTerminal(up, c)`：`new up.Terminal({ allowProposedApi: true, cols, rows, scrollback, tabStopWidth, convertEol, scrollOnUserInput, disableStdin, scrollOnEraseInDisplay, cursorStyle, cursorBlink, windowsPty: windowsPty ?? {}, windowOptions: {<name>: true...}, vtExtensions, quirks: { allowSetCursorBlink } })`，再 `loadAddon` 两个 Unicode addon、`L.useVariant(term, {version, ambiguousWide})`。
5. `attachRecorders(term)` → `rec`：`onData` 收字符串、`onBell` 计数、`onTitleChange` 列表、`onRender` 列表（`[start, end]`）、`onScroll` 列表、`onLineFeed` 计数、`onCursorMove` 计数。
6. `attachSynth(term, palette, focused)`：每个核心用例都挂（「夹具格式」），照 `src/browser/CoreBrowserTerminal.ts:204-268`、`:523-531`、`:1124-1130` 和 `src/browser/services/ThemeService.ts:80-183` 抄：
   - 色表 `base`（259 项，0–255、256 前景、257 背景、258 光标）和 `cur`；`term._core._inputHandler.onColor(ev => ...)`：对每个请求，REPORT → `triggerDataEvent('\x1b]' + ident + ';' + rgbString(cur[idx]) + '\x1b\\')`（`ident` = `10` / `11` / `12` / `4;<idx>`；`rgbString` 照 `XParseColor.ts:58-80` 的 16 位写法）；SET → `cur[idx] = rgb`、再「若 2031 开着就报明暗」；RESTORE 无索引 → 0–255 全部恢复成 `base`，有索引 → 该项恢复，再「若 2031 开着就报明暗」。
   - 报明暗 = `relativeLuminance(cur[257]) < relativeLuminance(cur[256]) ? 1 : 2`，发 `\x1b[?997;<n>n`；`relativeLuminance` 逐字抄 `src/common/Color.ts:236-259`。
   - `onRequestColorSchemeQuery` → 报明暗；`onRequestSendFocus` → 按 `synth.focused` 发 `\x1b[I` / `\x1b[O`。
   - 返回 `{ focus(f), theme(palette) }`：`focus` 更新 `synth.focused`，若 `sendFocus` 开着就发对应字节（`CoreBrowserTerminal.ts:305-331`）；`theme` 把 `base` 和 `cur` 都换成新表（换主题丢覆盖，核实记录 9），再「若 2031 开着就报明暗」。
7. `runSteps(up, term, rec, synthApi, steps)`（async）：`write` → `await new Promise(r => term.write(unb64(b), r))`；`writeRepeat` → 同一块写 `times` 次；`resize` → `term.resize(c, r)`；`input` → `term.input(new TextDecoder().decode(unb64(b)), user)`（输入限 UTF-8 文本）；`reset` → `term.reset()`；`clear` → `term.clear()`；`scrollLines` / `scrollToTop` / `scrollToBottom` → 同名方法；`setOption` → `term.options[name] = value`（`windowsPty` 同样）；`focus` / `theme` → `synthApi`。
8. `dumpState(up, term, rec)` → 「夹具格式」的 `<state>`：`<buf>` 按规则省略默认行、游程压缩、`>>> 0`；`tabs` 取 `Object.keys(buf.tabs).filter(k => buf.tabs[k]).map(Number).sort((a, b) => a - b)`；`markers` 取 `buf.markers.filter(m => !m.isDisposed).map(m => m.line)`；`saved` 取 `savedX / savedY / savedCurAttrData.fg >>> 0 / bg >>> 0 / savedGlevel / savedOriginMode / savedWraparoundMode`；`charset` 把 `_charsetService.charsets[g]` 反查 `CHARSETS` 的第一个键；`links` 从 `term._core._oscLinkService._dataByLinkId` 取，`lines` 是各标记的 `line`；`parserState` = `_inputHandler._parser.currentState`，`joinState` = `_inputHandler._parser.precedingJoinState`；`title`（`_inputHandler._windowTitle`）/ `titles` 的每一项 / `iconName`（`_inputHandler._iconName`）经 `digestable`；`data` 把 `rec.data` 拼起来按 UTF-8 编码、再把 `xterm.js(6.0.0)` 换成 `\u0000VERSION\u0000`（归一化，见「夹具格式」）后 base64。
9. `runCase(up, c, palette = DEFAULT_PALETTE)`（async）→ `{ expect, afterReset }`：新建终端 + 记录器 + 合成器（色表取 `c.synth?.palette ?? palette`，焦点取 `c.synth?.focused ?? true`），`runSteps`，`dumpState`；然后在**同一个**终端上 `term.reset()`、清空记录器（记录器对象换新、事件继续挂着）、再 `runSteps`、`dumpState`；两份 `JSON.stringify` 相同就 `afterReset = "same"`。
10. `checkVariants(up, c, expect)`：只对「步骤恰好一个 `write`」的用例；对每个 `variants` 项，新建终端，按切点分块 `await write` 每一块，`dumpState` 必须和 `expect` 完全相同；不同就抛错并打印用例 id 和第一处差异（这说明上游自己对切块敏感，spec §13.4「切块」要求结果一样；真遇到了，把该变体删掉、在脚本里记一行，照 spec §13.5 第 6 条的精神处理）。
11. `dumpLineOnly(line, cols)`：给 Task 6 的缓冲层快照复用的单行导出（和 `<buf>.lines` 的行格式相同）。

- [ ] **Step 3: 改 `regen-all.js`**（编辑工具）

`SCRIPTS` 改成 `['gen-unicode-tables.js', 'unicode-cases.js', 'parser-cases.js', 'buffer-cases.js', 'gen-terminal-charsets.js', 'core-cases.js', 'escape-files.js', 'fuzz.js', 'recordings.js']`；脚本文件还不存在时跳过并打印 `skip <name> (not written yet)`（整期中途也能跑）；「改了但不是生成物」的判断改用 `L.isGenerated`；被删除的生成物（`git status` 的 ` D`）也算生成物改动。

- [ ] **Step 4: 冒烟**（需要 Task 0 Step 2）

```bash
cd /d/Projects/ty-3.1 && node -e "const T=require('./tools/terminal-oracle/lib-term.js'); const L=require('./tools/terminal-oracle/lib-dump.js'); const up=L.loadUpstream(); T.runCase(up,{id:'smoke',source:'hand',cols:10,rows:3,steps:[{write:T.b64(T.utf8('ab\x1b[31mc\r\n\x1b]2;T\x07\x1b]8;;http://a\x07L\x1b]8;;\x07'))}]}).then(r=>{console.log(JSON.stringify(r.expect).slice(0,600)); console.log(r.afterReset==='same'?'same':'differs'); process.exit(0)})"
```

Expected：打印的 `<state>` 里 `title` 是 `"T"`、`buffers.normal.lines` 有 `i: 0` 那一行（`c` 至少三项）、`y` 为 1、`links` 有一项 `linkId: 1`；第二行是 `differs`——复位后同一实例上再写，链接号从 2 起（核实记录 8），`L` 那一格的扩展四元组里 `urlId` 变成 2。打印 `same` 说明 `runCase` 没在同一个实例上复位重跑，修掉再提交。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-oracle/lib-dump.js tools/terminal-oracle/lib-term.js tools/terminal-oracle/regen-all.js && git commit -m "feat(terminal): oracle plumbing for whole-terminal fixtures

lib-term.js builds a headless terminal from a case, runs its steps, and
exports every buffer cell, the modes, the replies and the events; a small
responder copied from the browser layer answers the colour, colour-scheme
and focus queries headless leaves unanswered. lib-dump.js now checks the
build against every source the phase ports, reads escape files from git
objects so autocrlf cannot change them, and splits large fixtures.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

**判据 / 变异（期末做，JS 侧）：**

| # | 变异 | 必须 |
|---|---|---|
| J3 | `PORTED` 删掉 `InputHandler.ts` 那一对，再把 `out/common/InputHandler.js` 的 mtime 调到源文件之前 | 删之前：`loadUpstream` 抛「the build is stale」；删之后静默加载（证明是这一对在拦）。mtime 改回 |
| J4 | `writeFixture` 的分片阈值改成 100 字节 | 任一生成脚本报「单个用例超限」，或产出多片且 Task 5 / 9 / 18 的分片检查照样绿（分片读法正确） |
| J5 | `dumpState` 去掉 tabs 的数值排序 | Task 18 的制表位用例红（`t0080-HT` / `tabs-beyond-cols`），期望是按字符串序的顺序 |

---

（Task 2–21 见四个附录文件，按任务号顺序做。）

---

### Task 22: 许可与署名

**Files:**
- Modify: `THIRD-PARTY-NOTICES.md`
- Modify: `tests/test.release.pas`
- 单元头部在 Task 3、7、15 写，本任务只核对

- [ ] **Step 1: `THIRD-PARTY-NOTICES.md` 的 xterm.js 一节**（编辑工具，语气照已有的节，[[doc-writing-native-tone]]）

1. 标题改成 `## xterm.js — source/tyControls.Unicode.Width.pas, source/tyControls.Unicode.Width.Data.inc, source/tyControls.Terminal.Parser.pas, source/tyControls.Terminal.Buffer.pas, source/tyControls.Terminal.Core.pas, source/tyControls.Terminal.Charsets.inc`（每个名字仍用反引号，和现有写法一致）。
2. 第二段「You only ship this if you `uses tyControls.Unicode.Width`（and, later, the `tyControls.Terminal*` units…）」改成现在时：用了 `tyControls.Unicode.Width` 或任何 `tyControls.Terminal*` 单元就要带；`Charsets.inc` 是从上游 dump 的数据（同 width 表的说法）。
3. 版权行：核对三个新单元移植的源文件头部，xterm.js 仓库根 `LICENSE:1-3` 三行已在；`InputHandler.ts` / `CoreTerminal.ts` 头部的「Copyright (c) 2012-2013, Christopher Jeffrey」已被第三行覆盖；`CoreTerminal.ts` 提到的「forked from Fabrice Bellard's jslinux (with the author's permission)」是来历说明、不是许可条件，单元头照抄那句来历，notices 不加版权行。结论：版权行不用新增（执行时逐文件核一遍头部，有新的版权人就加一行）。
4. 新子标题 `### Test fixtures`：`tests/fixtures/terminal-core-escape*.json` 里的输入字节来自 xterm.js 仓库的 `test/fixtures/escape_sequence_files/`（MIT，上面的条款）；再按 Task 0 Step 3 的结论加一句 vt100-parser 的出处与许可（或写明排除了哪些文件）。说明这些夹具**不随库发布**（只在 `tests/`），写这一节是为了仓库本身的署名完整（spec §14 最后一条）。
5. 录制（Task 14）是自己录的，不需要 notices；若用户选了不录，这一条不存在。

- [ ] **Step 2: `tests/test.release.pas` 加守卫**

新增 published 方法 `TheThirdPartyNoticeCoversTheTerminalPort`，照 `TheThirdPartyNoticeCoversTheUnicodeWidthPort` 的写法（写一段注释说明为什么是写死的字面量）。判据：

| 断言 | 变异（期末做） |
|---|---|
| 三个 `tyControls.Terminal.*.pas` 都被两个发布脚本发出（`IsShipped(FPs1/FSh, …)`）；`Charsets.inc` 也发出 | — |
| notices 的 `## xterm.js` 标题行里含 `tyControls.Terminal.Core.pas`、`tyControls.Terminal.Parser.pas`、`tyControls.Terminal.Buffer.pas` | R4：标题行删掉 `Parser` → 红 |
| notices 含 `### Test fixtures` | R5：删掉这一小节标题 → 红 |

（两个发布脚本整树发出 `source/`（`scripts/make-release.ps1:70-75` 的注释），新单元和 `.inc` 自动在内，脚本不用改；这条守卫防的是以后有人把 `source/` 改回按扩展名过滤。）

- [ ] **Step 3: 核对三个单元头部**（Task 3、7、15 写的）：移植自 xterm.js 6.0.0（commit 前 12 位）、逐个列出源文件路径、版权行照抄 `LICENSE:1-3`、「MIT，全文见 THIRD-PARTY-NOTICES.md」；Core 单元另写一句 jslinux 来历（同上游 `CoreTerminal.ts:6-12`）。缺的补上。

- [ ] **Step 4: 提交**

```bash
cd /d/Projects/ty-3.1 && git add THIRD-PARTY-NOTICES.md tests/test.release.pas && git commit -m "docs(terminal): notices cover the parser, buffer and core ports

The xterm.js section now names the three terminal units and the dumped
charset table, and a short test-fixtures note credits the escape sequence
files the oracle feeds. The release manifest test fails if either goes
missing while the units ship.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

（若 Step 2 改了发布脚本，一起 add。）

---

### Task 23: 收尾——编译、全量、集中修、按 spec 逐条核、集中变异、审查、写回 spec、签收

**Files:**
- Modify: 本计划（签收记录）、`docs/superpowers/specs/2026-09-28-terminal-view-design.md`（写回）
- 修复时按需改 Task 1–22 的文件

- [ ] **Step 1: 一次编译 + 本期 suite + 全量**

「跑测试的固定套路」的两条命令（本期八个 suite）。另编一次探针：`lazbuild -B tools/terminal-probe/terminalprobe.lpi`，再跑 Task 21 Step 3 的命令。Expected：八个 suite 都 0 / 0；全量 errors / failures 为 0、总数 = Task 0 基线 + 本期新增；探针输出和 Task 21 的判据一致。

编译错、红了就集中修：每一处先分清是移植错还是夹具错——**以上游为准**，对照上游源码行号；修完回到本步从头跑。全量红而单跑绿，按 [[suite-order-widgetset-init]]、[[canary-then-rebuild]] 排查。修复提交信息写 `fix(terminal): ...`，一个问题一个提交。

- [ ] **Step 2: 重跑生成，确认可复现**

```bash
cd /d/Projects/ty-3.1 && node tools/terminal-oracle/regen-all.js --expect-clean
```

Expected：`clean`。

- [ ] **Step 3: 规模与用时记录**

记下：各夹具文件字节数（都 ≤ 2MB）、各类用例条数、`TTyTerminalCoreOracleTests` 的总用时（每个测试结尾 `WriteLn` 用时，只打印不断言）。任何一个 suite 超过 60 秒，先看是不是比较器里做了多余的字符串拼接，别靠删用例省时间。

- [ ] **Step 4: 按 spec 逐条核代码，不看测试**（[[green-tests-are-not-spec-conformance]]、[[built-not-wired-is-the-default-failure]]）

逐条记「在哪一行实现 / 为什么不需要」：

- §2.1：三个单元名、依赖方向（Parser → Width；Buffer → Width；Core → 三者）、进运行时包、`.inc` 不进清单；Core 不用 LCL（守卫测试之外再读一遍 uses）。
- §2.2：处理器全同步；没有移植 `WriteBuffer` 的 Promise 分支和解析器的 `_parseStack` 续跑。
- §3.1：`Write` 只入队、队列空时发 `OnProcessRequest`；用户输入后第一次 `Write` 当场解析；12ms 按块；50MB 抛 `ETyTerminalWriteOverflow`；回调顺序；`WriteSync` 当场解析完。
- §3.2：`OnRefreshRows` 的区间算法照 `InputHandler.ts:474-484`，同步输出模式的「攒着不画」是渲染侧（3 期），Core 只维护模式。
- §3.3：`OnData` 是字节；`ReadOnly` 一律不发。
- §3.4：标题、响铃、未处理 OSC 进 `OnOsc`、XTWINOPS 默认全关。
- §3.5：四个入口的线程检查（开工前问题二第 22 条）；事件都在调用线程（即主线程）发。
- §5.1–§5.3：UTF-8 丢弃非法字节与 BOM；转移表在 `initialization` 生成；处理器表的键；131072 字节分段；§5.2 表里每一行（外加 OSC 编号饱和）；接口名对照「接口清单」。
- §6.1–§6.3：三字位布局；组合与扩展的稀疏存储（§17.2 第 7 条：按列号排序的小数组）；空格 ≠ 从没写过；环形表；主备缓冲；`IsWrapped`；标记；链接表；折行开关恒 false 并有注释。
- §7.1–§7.6：`TObject`；私有模式表逐行（spec 的表 + 2026 / 2031 / 9001）；应答清单；XTVERSION 字符串；选项（含开工前问题二第 19 条的四个）；颜色覆盖表与查询、明暗、换主题清表；`OnOsc` 与核心注册的 OSC 编号清单一致（0 / 1 / 2 / 4 / 8 / 10 / 11 / 12 / 104 / 110 / 111 / 112）；鼠标协议状态、`RestrictMouseEvent` / `EncodeMouseEvent`；接口清单每一项都在。
- §13：目录与命名；§13.3 格式（按本计划的细化）；§13.4 的 2 期各行都有用例；§13.5 七条。
- §14：单元头、notices 的标题与小节。
- §17.2：第 1、2、6、7、8、9、11 条。

- [ ] **Step 5: 集中变异**（每条三拍，必须红）

各任务变异表：J3–J5（Task 1）、P*（Task 2–5）、B*（Task 6–9）、C*（Task 10–18）、W*（Task 19–20）、R4–R5（Task 22）。JS 侧的变异改完跑对应的生成脚本或冒烟命令、确认失败后改回，并且 `regen-all.js --expect-clean` 仍然 `clean`。结果逐条记进签收记录；没红的当场补强。

- [ ] **Step 6: 【主控执行】编一次运行时包**（`.lpk` 清单改了）

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tycontrols.lpk > /tmp/term-pkg.txt 2>&1; tail -3 /tmp/term-pkg.txt; git status --short
```

Expected：编过；`git status` 没有变化（本期没有 resourcestring，`languages/` 不动）。报错路径里出现别的树 = 注册权被抢，重编一次（[[parallel-agent-worktree-hazards]]）。

- [ ] **Step 7: 整体代码质量审查**

对 `git diff <Task 0 的 HEAD>..HEAD`：
- 移植函数与上游逐行对照，重点：`EscapeSequenceParser.parse` 的两个快路径（`:687-746`）与四个内循环（PRINT / PARAM / OSC_PUT / DCS_PUT / APC_PUT）；`Utf8ToUtf32.decode` 的跨块续接（`TextDecoder.ts:155-209`）；`InputHandler.print`（`:517-661`）；`_extractColor`（`:2416-2475`）；`Buffer.resize`（`:160-286`）；`BufferService.scroll`（`:68-126`）；`CircularList.splice` / `shiftElements`。注释里的行号都要对得上。
- 地雷 3 的每一处是否都用了 `Int64` / 饱和；地雷 6 的每一处修改前是否 clone；地雷 7 的钉住清单是否齐（再 grep 一遍 `Get(` 的调用点，看有没有跨修改持有）。
- 只有 `lib-dump.js` 加载上游；`PORTED` 覆盖本期所有移植源；`GENERATED` 与实际写出的文件一致。
- 夹具读空时每个测试都会红（计数断言）；等价变异的理由站得住。
- `TTyTerminalLine.LiveCount` 守卫在 Core 释放后为 0。

审出来的问题修完回到 Step 1。

- [ ] **Step 8: 写回 spec 原处，标「实现期修正（2 期）」**

至少：§2.1（`BufferService` 放进 Buffer 单元；`Charsets.inc`；测试辅助单元 `test.terminal.oracle`）；§3.1（按块检查 12ms、131072 字节、`OnProcessRequest` 与时钟、线程检查的四个入口、溢出异常类）；§5.1（131072 是字节、BOM 丢弃）；§5.2（载荷按 UTF-16 单元、`>` 判定；OSC 编号饱和一行）；§5.3（回退处理器全集、错误处理器、`Finish` 命名、所有权）；§6.2 / §6.3（行的引用计数、折行开关、制表位含越界的旧键）；§7.2（选项补四个、1004 立即报焦点、XTWINOPS 14t/16t 的事件）；§7.3（明暗报告的时机、换主题清覆盖、RIS 不清）；§7.5 / §7.6（2 期只有 `RestrictMouseEvent` / `EncodeMouseEvent`，`TriggerMouseEvent` 4 期；接口清单里标 ★ 的项）；§13.2（脚本清单多了 `lib-term.js`、`buffer-cases.js`、`gen-terminal-charsets.js`、`wsl-record*`；鼠标限制 / 编码的直接比较并进 `core-cases.js`，`mouse-cases.js` 留给 4 期的上报前处理）；§13.3（格式细化、合成应答器总是挂着）；§13.4（序列文件不跳、从 git 对象读、`convertEol`；录制的实际来源）；§13.5（复用路径的期望由 node 生成）；§15（REP 上限；按问题一第 4 条的结论，改尺寸前清空队列从未处理的块开始）；§17.2 第 1、2、6、7、8、9、11 条标「已完成（2 期）」；开工前问题一的四条结论。

- [ ] **Step 9: 签收记录写进本计划末尾，提交**

写：全量条数（基线 → 签收）、提交区间、各 suite 用时、夹具体积与用例数、变异结果（每条红 / 补强 / 等价）、spec 写回的节号、遗留、给 3 期的交接（控件要做的：`OnProcessRequest` → `QueueAsyncCall`、`OnWindowOptionsReport` 应答、`NotifyColorSchemeChanged`、`OnQueryBaseColor`；探针用法）。本期没有真机项，不出验收表。

```bash
cd /d/Projects/ty-3.1 && git add docs/ && git commit -m "docs(terminal): phase 2 sign-off and corrections written back into the spec

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 2 期做完能看到什么

- `tytests` 里七个终端 suite 全绿：解析器的转移表、UTF-8 解码、几百条回调轨迹；缓冲的操作脚本；核心的手写用例、上游 79 个序列文件（整块与逐字节 / 随机切块）、坏序列与超长输入、种子化随机字节、颜色 / 明暗 / 焦点应答、鼠标编码、真实程序录制——缓冲三字、光标、模式、应答字节、事件都和 xterm.js 6.0.0 逐位相同；超长 / 坏序列之后状态有界、后续序列照常。
- 写入队列：切片、回调顺序、用户输入后当场解析、50MB 上限、非主线程调用抛异常，都有判据测试。
- `node tools/terminal-oracle/regen-all.js --expect-clean` 打印 `clean`。
- `tools/terminal-probe` 能把一份录制喂进 Core、打印屏幕文本，肉眼对照。
- 没有界面，没有真机项。
