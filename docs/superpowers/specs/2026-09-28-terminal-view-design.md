# 终端控件 TTyTerminalView —— 设计规格

> 状态：已定稿（用户 2026-09-28 审过，§17.1 全部按建议）；1 期已签收（2026-09-28，记录在 1 期计划末尾）；2 期已签收（2026-09-29，记录在 2 期计划末尾）；3 期已签收（2026-09-29，记录在 3 期计划末尾，真机与截图验收随各期一次做完）；三期的实现期修正都已写回各节原处，分支 feat/terminal · 上游：xterm.js 6.0.0（`D:/Projects/xterm.js`，commit `c58ea36`）· 需求来源：用户口头（2026-09-23 立项，2026-09-28 逐段确认）

在库里加一个终端控件：宿主把程序输出的字节流喂进来，控件解析、存进屏幕缓冲、画出来；键盘、鼠标、粘贴编码成字节，经事件交还宿主。
会话、PTY、shell 集成都归宿主，控件不碰进程。解析、缓冲、核心、键盘编码照 xterm.js 移植，渲染自己写。

本文锁范围与契约，实现步骤另拆到 `docs/superpowers/plans/`（一期一份）。

**引用约定**：
- `xterm:` = `D:/Projects/xterm.js/`（6.0.0，`package.json:4`；HEAD `c58ea3637f39`）
- `lcl:` = `C:/lazarus/lcl/`
- `fpc:` = `C:/lazarus/fpc/3.2.2/source/`
- `bgra:` = `C:/Users/Tom/AppData/Local/lazarus/onlinepackagemanager/packages/BGRABitmap/bgrabitmap/`
- 不带前缀的路径是本仓库（`D:/Projects/ty-3.1`）

所有关于 xterm.js、LCL、BGRABitmap、库内已有能力的结论都是**读源码核实**的，行号见各处。**没有真机验过**的列在 §16。
标了「定稿时新加」的，是讨论时没有、写文档时补上的默认做法，依据写在原处。
和讨论时说法不一样的事实，集中在 §1.1，原处也有标注。

---

## 1. 已定的前提（不再讨论）

| # | 决定 | 直接后果 |
|---|------|----------|
| 1 | **分工照 xterm.js**：控件只做解析、缓冲、渲染（含输入编码）；会话、PTY、shell 集成归宿主 | 控件吃字节（`Write`），输入经 `OnData` 交还；控件里没有进程、没有管道、没有线程 |
| 2 | 解析 / 缓冲 / 核心 / 键盘**照 xterm.js 移植**成 Pascal，保留 MIT 署名；渲染自己写 | 1、2 期能拿上游当基准逐位比（§13）；署名见 §14 |
| 3 | **七个部分**：`tyControls.Unicode.Width`、`.Terminal.Parser`、`.Terminal.Buffer`、`.Terminal.Core`、`.Terminal.Keyboard`、`.Terminal`（可见控件）、示例 `examples/terminal` | PTY 接入单元只在示例里（Windows ConPTY，Linux / macOS forkpty），不进包 |
| 4 | **数据流**：`Write` → 写入队列（按帧切片）→ 解析 → 核心 → 缓冲；只标脏行，控件每帧最多重画一次；`Write` 可带「处理完了」回调；标题、响铃、OSC 52（默认关）、打开链接全部以事件交宿主 | §3 |
| 5 | **鼠标**：上报模式 9 / 1000 / 1002 / 1003 / 1004，编码默认 `CSI M`、1006 SGR、1016 SGR 像素；1005、1015 不做；三键、滚轮、Shift / Alt / Ctrl；程序接管鼠标时按住覆盖键（默认 Shift，macOS 默认 Option，可配）拖动仍是本地选择；备用屏滚轮翻成方向键；双击 / 三击选词 / 选行；Ctrl+单击链接交宿主；右键程序接管时发给程序、否则弹控件菜单；括号粘贴 2004 | §9.5；滚轮左右和 1007 的事实修正见 §1.1 |
| 6 | **五期**：1 Unicode 表 + 基准环境；2 解析器 / 缓冲 / 核心；3 控件绘制、键盘、滚回、主题、回放示例；4 PTY 示例、鼠标、选区剪贴板、输入法、链接、括号粘贴；5 重新折行、流量控制、性能、最低对比度 | §18 |
| 7 | **测试**：1、2 期拿 node 跑上游生成期望值、Pascal 侧精确比较；3–5 期用无头像素测试、事件测试、变异验证；真机项期末汇总成验收表。节奏：每期写完编一次跑全量，期末集中变异，期末整体审查（规格核对 + 代码质量） | §13 |
| 8 | **不做**（以后单独立项）：屏幕阅读器、连字、图片协议（sixel / kitty 图形 / iTerm）、kitty 键盘协议 | §15 |
| 9 | **Unicode 宽度确定、各平台一致**，不依赖 ICU；ambiguous 宽度可配（默认窄）；Unicode 版本可配，范围 = xterm.js 支持的版本 | §4 |

### 1.1 核实中修正的前提

讨论时的说法和源码对不上的，以源码为准，原处照此写：

1. **屏幕阅读器**：Qt5 / Qt6 的桥接代码在，但**默认编译掉了**——`lcl:interfaces/qt5/qtdefines.inc:12`、`qt6/qtdefines.inc:12` 都是 `{.$DEFINE QTACCESSIBILITY}`（点号注释），`qtwsfactory.pas:136-141` 只在这个开关打开时注册。GTK3 也是桩（`gtk3/gtk3wsfactory.pas:161-165`），不止 Win32（`win32/win32wsfactory.pas:135-140`）/ GTK2（`gtk2/gtk2wsfactory.pas:143-148`）/ Cocoa（`cocoa/cocoawsfactory.pas:133-138`）。结论不变：不做。
2. **1007（备用屏滚动）xterm.js 没有这个模式**：`setModePrivate`（`xterm:src/common/InputHandler.ts:1932-2071`）和 `resetModePrivate`（`:2198-`）里都没有 `case 1007`。它的行为是**无条件**的：程序没要滚轮事件、且当前缓冲**没有滚回**时，一次滚轮发**一个**上 / 下方向键（`xterm:src/browser/services/MouseService.ts:252-290`，判据 `!buffer.hasScrollback` 在 `:262`，序列在 `:288`）。「没有滚回」= 备用屏（`BufferSet.ts:47` 建备用缓冲时传 `false`），也包括滚回行数为 0 的主屏（`Buffer.ts:103-105`）。我们的做法见 §9.5.4。
3. **滚轮左右**：编码器支持（`CoreMouseAction.LEFT/RIGHT` 仅用于滚轮，`xterm:src/common/Types.ts:170-171`；`eventCode` 对滚轮直接或上 action，`MouseStateService.ts:94-96`），但浏览器层**从不产生**——`_sendEvent` 只看 `deltaY`（`MouseService.ts:142-153`）。横向滚轮上报是我们加的，期望值只能对编码器本身比（§13.4）。
4. **「Alt 当 Meta」只在 macOS 上是选项**：Win / Linux 上 xterm.js 一律给 Alt+键加 ESC 前缀；只有 macOS 看 `macOptionIsMeta`（`xterm:src/common/input/Keyboard.ts:333`，条件 `(!isMac || macOptionIsMeta) && ev.altKey && !ev.metaKey`）。属性因此叫 `MacOptionIsMeta`（§9.1）。
5. **选区覆盖键在 macOS 上的上游默认**：xterm.js 在 macOS 上默认**没有**覆盖键（`macOptionClickForcesSelection` 默认 false，`OptionsService.ts:42`；`SelectionService.ts:442-444`），其他平台是 Shift（`:446`）。用户定的「macOS 默认 Option」是有意偏离，记进 §15。
6. **`Win32InputMode.ts` 只管键盘**：格式 `CSI Vk ; Sc ; Uc ; Kd ; Cs ; Rc _`（`xterm:src/common/input/Win32InputMode.ts:1-14`），按下、抬起都发（`KeyboardService.ts:35-55`），靠 DECSET 9001 打开、且要选项 `vtExtensions.win32InputMode`（默认 false，`xterm:typings/xterm.d.ts:484-492`；`InputHandler.ts:2043-2047`）。和鼠标无关。它和 ConPTY 的关系见 §12.4。
7. **ambiguous 宽度只有 Unicode 15 那张表有数据**：6、11 两张表只有「组合 / 宽」两类（`UnicodeV6.ts`、`addons/addon-unicode11/src/UnicodeV11.ts`）；15 的表带 `CHARWIDTH_EA_AMBIGUOUS` 一类（`addons/addon-unicode-graphemes/src/third-party/UnicodeProperties.ts:38-41`），开关是 provider 上的公开字段 `ambiguousCharsAreWide`（`UnicodeGraphemeProvider.ts:13`），但**不在 addon 的公开类型里**（`addons/addon-unicode-graphemes/typings/addon-unicode-graphemes.d.ts` 只有构造、activate、dispose）。见 §4.3。
8. **OSC 52 不在核心里**，在 `addon-clipboard`（`xterm:addons/addon-clipboard/src/ClipboardAddon.ts:20`）；**OSC 4/10/11/12 的查询应答、颜色主题查询应答在浏览器层**（`xterm:src/browser/CoreBrowserTerminal.ts:211-258`、`:261-`），headless 不应答。这几类的期望值要在 node 脚本里补一层（§13.4）。

**实现期修正（3 期）**：
9. **上游按键不看应用小键盘模式**（DECKPAM / `CSI ? 66 h`）：`evaluateKeyboardEvent`（`Keyboard.ts:38-380`）只收应用光标模式，`applicationKeypad` 只在 InputHandler 里记下、DECRQM 照报，浏览器层没有按键读它。小键盘数字和运算符一律按 `ev.key` 发字符。我们照上游（开工前问题一第 1 条的结论）。
10. **第三层 Shift 有三项**（`CoreBrowserTerminal.ts:937-948`）：macOS 上 Option 且不当 Meta；Windows 上 Ctrl+Alt；Windows 上 `getModifierState('AltGraph')`（LCL 的 `ssAltGr`）。按下事件里另要 `keyCode` 为 0 或 > 47（方向键、退格不算），字符事件里不看 keyCode——所以判定分按下 / 字符两种（§8.4 的 `AKeyPress`）。

---

## 2. 组成

### 2.1 单元

| 单元 | 内容 | 移植自（xterm:） | 依赖 |
|---|---|---|---|
| `tyControls.Unicode.Width` | 字符宽度、组合判定、字形簇连接状态；纯函数 | `src/common/input/UnicodeV6.ts`、`addons/addon-unicode11/src/UnicodeV11.ts`、`addons/addon-unicode-graphemes/src/UnicodeGraphemeProvider.ts`、`…/third-party/UnicodeProperties.ts`（规则部分）、`src/common/services/UnicodeService.ts` | 只 `SysUtils` |
| `tyControls.Unicode.Width.Data.inc` | 生成的数据表（§4.2），include 文件 | 由脚本从上游 dump | — |
| `tyControls.Terminal.Parser` | UTF-8 解码、VT500 状态机、参数、OSC / DCS / APC 子解析器 | `src/common/parser/*.ts`（EscapeSequenceParser、Params、OscParser、DcsParser、ApcParser、Constants、Types）、`src/common/input/TextDecoder.ts` | `Unicode.Width` |
| `tyControls.Terminal.Buffer` | 单元格、行、环形行表、缓冲、主 / 备缓冲组、标记、OSC 8 链接表、重新折行 | `src/common/buffer/*.ts`、`src/common/CircularList.ts`、`src/common/services/OscLinkService.ts` | `Unicode.Width` |
| `tyControls.Terminal.Core` | 不可见的 `TTyTerminalCore`：写入队列、控制序列处理、模式、字符集、鼠标协议状态、颜色请求 | `src/common/InputHandler.ts`、`CoreTerminal.ts`（非 UI 部分）、`services/{Buffer,Core,Charset,MouseState}Service.ts`、`input/WriteBuffer.ts`、`WindowsMode.ts`、`data/Charsets.ts`、`data/EscapeSequences.ts`、`input/XParseColor.ts`；鼠标上报的过滤段取自 `src/browser/services/MouseService.ts:497-545` | 上面三个 |
| `tyControls.Terminal.Keyboard` | 按键 → 字节、粘贴编码、焦点报告；纯函数 | `src/common/input/Keyboard.ts`、`src/browser/Clipboard.ts:13-29`（粘贴两个函数）、`CoreBrowserTerminal.ts:937-948`（第三层 Shift 判定） | `SysUtils`、`Classes`（`TShiftState`）、`LCLType` |
| `tyControls.Terminal` | 可见控件 `TTyTerminalView`：渲染、输入、选区、滚动条、主题 | 自己写；逻辑参照 `src/browser/` 下 SelectionService / SelectionModel / MouseService / RenderDebouncer / ThemeService（引用处标行号） | 上面全部 + 库 |
| `examples/terminal` | 示例：回放 + 真 shell；PTY 单元只在这里 | 自己写 | 控件 |

- 纯函数和不可见类都进运行时包 `tycontrols.lpk`（不进包就在安装包里消失，[[new-unit-missing-from-lpk]]）；`.inc` 不列进 `.lpk`（先例 `Icons.Lucide.License.inc`，见 `docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md` §2）。
- 名字已查：`source/` 下没有 `tyControls.Unicode*`、`tyControls.Terminal*`，也没有任何 wcwidth / EastAsian / grapheme 代码。
- 组件面板只注册 `TTyTerminalView`，放 `TyControls Edits` 分页、挨着 `TTyMemo`（`designtime/tyControls.Design.pas:143-146`）；`TTyTerminalCore` 不是组件（§7.1）。

**实现期修正（2 期）**：
- ~~`services/{Buffer,…}Service.ts` 在 Core~~ `BufferService` 放在 Buffer 单元：它只管滚动、视口、改尺寸，放在下层 2b 才能单独对上游比；Core 持有一个。
- 新增生成物 `source/tyControls.Terminal.Charsets.inc`（`gen-terminal-charsets.js` 从上游 `CHARSETS` dump，别名保留），和 `Unicode.Width.Data.inc` 一样不进 `.lpk`。
- 测试辅助单元 `tests/test.terminal.oracle.pas`：读夹具、驱动 Core、逐项比较，自身不注册测试。
- `Unicode.Width` 多了三个纯函数 `TyUnicodeUtf8Size` / `TyUnicodeUtf8Encode` / `TyUnicodeCodepointToUtf8`：终端几个单元只有这一份 UTF-8 编码器（码位越界或落在代理区编成 U+FFFD）。JavaScript 空白判断只在 Buffer 一份（`TyTermIsJsWhitespace`）。
- Core 的实现拆成三个 include：`tyControls.Terminal.Core.Services.inc`（CoreService / 字符集 / 鼠标 / 颜色焦点 / 选项）、`…Core.InputHandler.inc`（全部控制序列处理器）、`…Core.WriteQueue.inc`（写入队列与重入）；照 `ToolWindows.*.inc` 的先例不进 `.lpk`，notices 标题和发版守卫逐个列名。

**实现期修正（3 期）**：
- 新增单元 `tyControls.Terminal.Render`：不依赖控件的渲染部件——单元格度量、256 色表、格子颜色解析、字形遮罩与缓存、自绘字形、一行的绘制器，可单独测。依赖 `Terminal.Buffer`、`Painter`（字体配置）、BGRABitmap；不引 `Controls` / `Forms`。
- 新增生成物 `tyControls.Terminal.CustomGlyphs.inc`（`gen-terminal-glyphs.js` 从上游 `CustomGlyphDefinitions.ts` dump，U+2500–259F），由 `Terminal.Render` include，不进 `.lpk`。
- 依赖方向：`Terminal.Keyboard` 只有 `SysUtils` / `Classes` / `LCLType`；`Terminal.Render` 不引控件；控件单元 `tyControls.Terminal` 引全部。三个新单元都进运行时包。
- `ITyTextEditActions`、选区、链接都在 4 期，控件本期只实现两个接口（§9）。

### 2.2 不移植的上游部分

DOM 渲染器与 WebGL 渲染器、`Viewport`（浏览器滚动）、`AccessibilityManager`、`CompositionHelper`（浏览器输入法）、`Linkifier` 的 DOM 部分、所有 addon 的 UI 部分。
`WriteBuffer` 和解析器的**异步处理器**（处理器返回 Promise，`xterm:src/common/input/WriteBuffer.ts:219-285`）不移植：FPC 3.2.2 没有闭包，所有处理器一律同步。

---

## 3. 数据流、调度与线程

```
宿主 ──Write(bytes, OnDone)──▶ 写入队列 ──(每片 ≤12ms，片间让出消息循环)──▶ UTF-8 解码 ─▶ 解析器 ─▶ 核心处理器 ─▶ 缓冲
                                                                                          │
                                                                        脏行区间 [first,last] ─▶ 控件 Invalidate 对应行 ─▶ Paint
键盘 / 鼠标 / 粘贴 / 焦点 / 核心应答(DA、DSR、颜色报告…) ──▶ OnData(bytes) ──▶ 宿主写进 PTY
标题 / 响铃 / OSC 52 / 未处理的 OSC / 链接点击 / 网格尺寸变化 ──▶ 各自的事件 ──▶ 宿主决定
```

### 3.1 写入队列

照 `WriteBuffer`（`xterm:src/common/input/WriteBuffer.ts`）：

- `Write` 只入队，不当场解析；队列空时安排一次处理（`:152-183`）。
- **例外**：用户刚输入过（键盘 / 粘贴发过 `OnData`）后的第一次 `Write` 当场解析，压低回显延迟（`:167-176`）。
- 一片最多跑 12ms（`WRITE_TIMEOUT_MS`，`:27`），超时就停、让出，下一片再排（`:295-310`）。
- 积压超过 50MB（`DISCARD_WATERMARK`，`:20`）时 `Write` 抛异常——上游同样抛（`:156-158`），意思是宿主没做流量控制（§12.3、5 期）。
- 每个块处理完调它的回调（`:289-290`）。

**让出怎么做**：Core 不依赖 LCL，它只提供「处理一片」的方法；排下一片由控件用 `Application.QueueAsyncCall`。
LCL 的异步调用在 `Application.ProcessMessages` 里排在 `AppProcessMessages` 之后（`lcl:include/application.inc:449-453`），空闲时在 `Idle` 里跑（`:469-471`）——已经提交的 `WM_PAINT` 会先被处理，渲染有机会追上，和上游「setTimeout 0 让渲染追上」同一个意思。

测试和无头使用走 `Core.WriteSync`（照 `WriteBuffer.writeSync`，`:106`），当场解析完。

**实现期修正（2 期）**：
- ~~一片最多跑 12ms~~ 12ms 在**块与块之间**检查，一个大块整块解析完才让出（上游同样，`WriteBuffer.ts:224-297`）；块内切片是 5 期的事。
- 排片：Core 加 `OnProcessRequest`——队列从空变非空时发，同一时间最多一个待处理请求（照上游 `cancelAndSet` 只留一个定时器）；控件在里面 `Application.QueueAsyncCall`，回调里调 `ProcessPending`，返回 True 再排下一片。
- 时钟 `Clock` 可注入（毫秒，带小数）。默认：Windows 用 `QueryPerformanceCounter`（频率只取一次）；macOS 用 `mach_absolute_time`（FPC 3.2.2 在 Darwin 上的 `GetTickCount64` 是 `gettimeofday`，会跟着墙钟跳；RTL 没声明 mach 计时器，单元里自己声明）；Linux / FreeBSD 用 `GetTickCount64`（`CLOCK_MONOTONIC`）；其余 Unix 同样走 `GetTickCount64`，FPC 那里是 `gettimeofday`。
- 线程检查：`Write` 两个重载、`WriteSync`、`ProcessPending`、`Resize`、`Reset`、`Input`、四个 `Scroll*`、`ClearScrollback`、`TriggerMouseEvent`、`ReportFocus`、`NotifyColorSchemeChanged`、`EndSynchronizedOutput`，非主线程一律 `EInvalidOperation`。
- 积压判定照上游用 `>`：超过 50,000,000 **字节**（队列按字节计）抛 `ETyTerminalWriteOverflow`（新类，宿主可单独捕获；上游抛普通 `Error`）。另加一条：没处理的块超过 100,000 个也抛同一个异常。`Write('')` 不带回调直接忽略，带回调照常入队（回调的意义是「前面的都处理完了」）。
- 取块时**先推进偏移、再解析、再回调**，块的数据当场释放；处理器抛异常时这一块算已处理（不会重解析），它的回调照样调（宿主按回调做流量控制，不能少一次），剩下的块留在队里并重新 `OnProcessRequest`。上游的 `writeSync` 这时会永远停在「同步写中」。
- `WriteSync` 和 `Resize` 前的清空都从第一个没处理的块开始（修上游让出后改尺寸重复解析，§15）。
- **重入**：所有事件都在解析中同步发（`OnScroll`、`OnData`、`OnBell`、`OnTitleChange`、`OnOsc`、`OnRefreshRows`……），`Resize` / `Reset` 执行中也会发事件。事件里调 `Resize`、`Reset`、`WriteSync` 不报错，而是记下来，等这一块解析完、它的回调跑完再按调用顺序执行，`Resize` 只保留最后一次；`ProcessPending` 这时直接返回 False，Core 忙完后若还有东西会重新请求。结果和「事件返回后再调用」相同，不会重复解析，也不会有缓冲在处理器底下被换掉。3 期控件的常见路径（滚动条出现 → 改尺寸、模态框里跑消息循环）靠这一条不出事。

### 3.2 脏行与重画

- 核心每改一行就把行号并进脏区间（上游 `_dirtyRowTracker.markDirty`，`InputHandler.ts:534`），解析完一片后发一次 `OnRefreshRows(First, Last)`。
- 控件只 `Invalidate` 这几行的矩形；操作系统合并无效区，一帧最多画一次。上游同样只记 `[start, end]` 区间、一帧画一次（`xterm:src/browser/RenderDebouncer.ts:34-51`）。
- **同步输出（DECSET 2026）**：模式开着时只攒脏行不画，关掉时一起画；1 秒没关就强制关掉再画（`xterm:src/browser/services/RenderService.ts:22`、`:162-167`、`:359-363`）。

**实现期修正（2 期）**：
- `OnRefreshRows` 每解析完一块发一次（区间算法照 `InputHandler.ts:474-484`）；处理器抛异常时也照发，这一块改过的行不会漏画。
- 2026 的「攒着不画」是控件的事，Core 只维护模式。1 秒超时的入口是 `Core.EndSynchronizedOutput`：清掉 2026、整屏 `OnRefreshRows`、发 `OnModesChange`（照上游超时回调）；3 期控件的 1 秒计时器调它。

**实现期修正（3 期）**，控件侧：
- `OnRefreshRows` 报的已经是**视口行**（Core 在解析结尾换算，同上游 `InputHandler.parse`），控件直接用。
- 同步输出开着时，要重画的一切都进暂存：Core 报的脏行、光标行、闪烁翻转、滚动带来的整屏（上游这些都经 `refreshRows` 进 `bufferRows`）。1 秒计时器从**第一次**暂存起算，模式打开本身不起表；只暂存视口里的行——用户上翻超过一屏时，光标行不在视口，打开 2026 也不起表，回到底部或键入把视口拉回底部才起。
- 一次解析（`AsyncSlice`、`WriteSync`、`Write` 当场解析那次）里 Core 可能滚几千次：`OnScroll` 只记「整屏脏、滚动条待同步」，解析返回后统一失效、同步一次。
- 颜色变了整窗重画：解析前后比 259 色的签名，变了（OSC 4 / 10 / 11 / 12 / 104 / 110 …）就整窗失效——257 号色也是内边距的底色（照上游 `onChangeColors → _fullRefresh`，`RenderService.ts:120`）。
- 帧率上限：距上次绘制不到 16 ms 就接着跑下一片，不让出给 `WM_PAINT`；一帧里光栅化新字形有时间预算（10 ms），超出的字形不画、那一行留脏，下一帧整行重画（每帧至少画一个新字形）。

### 3.3 输出：`OnData` 交字节

上游分 `onData`（字符串，宿主按 UTF-8 发）和 `onBinary`（只用于默认 `CSI M` 鼠标编码，码值 > 127 按单字节发，`MouseService.ts:535-539`、`CoreService.ts:97-104`）。
我们直接交字节，两者合成一个 `OnData(Sender; const AData: RawByteString)`：文本部分是 UTF-8，`CSI M` 的三个码值原样单字节。
`ReadOnly = True` 时一律不发（上游 `disableStdin`，`CoreService.ts:76-78`）。

### 3.4 交给宿主的事件

标题（OSC 0 / 2，`InputHandler.ts:286-290`）、响铃（BEL，`:267`）、OSC 52（§9.6.3）、链接（§9.8）、**核心不处理的 OSC**（7 当前目录、133 / 633 shell 集成等，全部原样交出，§7.4）、网格尺寸变化（宿主据此改 PTY 大小）。
窗口操作类请求（XTWINOPS）照上游默认全关（`windowOptions: {}`，`OptionsService.ts:53`）。

### 3.5 线程约定

- `Write`、所有方法、所有属性**只允许主线程调用**。`Write` 入口检查 `GetCurrentThreadId = MainThreadID`，不是就抛 `EInvalidOperation`（定稿时新加：静默出错比报错难查得多）。
- 所有事件都在主线程发。
- 宿主在后台线程读 PTY 时，把数据交给主线程再 `Write`。示例的做法（§12.2）：读线程把数据追加进加锁的队列，队列从空变非空时 `Application.QueueAsyncCall` 一次，主线程一次取光再 `Write`。FPC 3.2.2 的 `TThread.Queue` 只收方法指针、没有闭包，每块数据要带一个对象，不如队列 + 一次异步调用省事。

---

## 4. `tyControls.Unicode.Width`

### 4.1 上游有什么

| 版本名 | 出处 | 表是怎么来的 |
|---|---|---|
| `6` | 核心自带，默认注册（`xterm:src/common/CoreTerminal.ts:134`） | 手写区间表 + 手工修补：先填宽字符再用组合字符覆盖、`0x303F` 手动改回 1（`UnicodeV6.ts:85-120`，「wrongly in last line」在 `:103`） |
| `11` | `addon-unicode11` | 区间常量表 `BMP_COMBINING` / `HIGH_COMBINING` / `BMP_WIDE` / `HIGH_WIDE`（`UnicodeV11.ts:10-169`），**仓库里没有生成脚本**，出处没写 |
| `15`、`15-graphemes` | `addon-unicode-graphemes`（两个 provider，后者多做字形簇连接，`UnicodeGraphemeProvider.ts:16-19`） | 一个 base64 + 压缩的 trie（`third-party/UnicodeProperties.ts:2-13`），由外部项目 unicode-properties 从 Unicode 数据生成（addon `README.md:7`）；解码器 `tiny-inflate.ts` / `unicode-trie.ts` 是第三方代码 |

- 15 那个 addon 自称实验性、未发布到 npm（`README.md:3`、`:11`）。
- 宽度打包格式：`state << 3 | width << 1 | shouldJoin`（`UnicodeService.ts:19-30`）；15-graphemes 的 state 是字形簇断点类别（GB 规则 6–13 的简化版，`UnicodeProperties.ts:112-143`；没有 GB9c，GB11 只看前一个是不是 ZWJ）。
- 15 的 provider 把 U+FE0F（VS16）强制算宽（`UnicodeGraphemeProvider.ts:37`）。

**实现期修正（1 期）**：实跑上游又看到两条不直观的行为，照搬（§13.5 第 2 条）：
- **`15`（不带 graphemes）不连接组合符**：provider 把小于 2 的 `w` 一律改成 1（`UnicodeGraphemeProvider.ts:35-40`），非 graphemes 分支 `charInfo = w === 0 ? 1 : 0` 于是恒为 0（`:46`）。组合符在 `15` 下自占一格、宽 1，而同一码位的 `wcwidth` 是 0；`"é"` 在 `15` 下串宽 2，`6` / `11` / `15-graphemes` 下是 1。
- **`15` / `15-graphemes` 下控制字符和 U+200D 的 `wcwidth` 是 1**（trie 把 Control 归 `Other`、宽度类 normal），`6` / `11` 下是 0。打印路径不会把 C0 送进来，查表函数照上游答。
- 用户结论：照搬上游，3 期控件文档写明「要字形簇就选 `15-graphemes`，`15` 不连接组合符」。

### 4.2 决定：从上游 dump 生成，不从 Unicode 官方数据生成

脚本 `tools/terminal-oracle/gen-unicode-tables.js` 在 node 里加载上游的四个 provider，对 0..0x10FFFF 每个码位取 `wcwidth` 和 15 表的原始 `getInfo`，压成区间表，写出 `source/tyControls.Unicode.Width.Data.inc`。

理由：
1. 目标是和 xterm.js **逐位一致**，不是和某个 Unicode 版本一致。6 带手工修补、11 没有出处，从 UCD 重新生成**一定**和上游对不上，也说不清差在哪。
2. 15 的表本来就是从 UCD 生成的，dump 出来就是那份数据，还省掉移植第三方解压器（它们没有许可头，`third-party/*.ts` 里 grep 不到 License / Copyright）。
3. 一份脚本、一种做法覆盖四个版本；以后要加 Unicode 16，再写一个从 UCD 生成的脚本，用同一套测试对照。

「和 shell 的 wcwidth 对上」靠**选对版本**：宿主按目标系统选 6 / 11 / 15（§9.1 `UnicodeVersion`），控件不猜。

生成的 `.inc` 进库、进 git；~~脚本头部写明上游路径、commit、生成时间~~。表有改动时重跑脚本，`git diff` 必须只动 `.inc`。

**实现期修正（1 期）**：
- 「写生成时间」和 §13.5 第 7 条「重跑 `git diff` 为空」冲突。生成物头部改写上游版本、完整 commit 和**上游提交日期**（`git log -1 --format=%cs`，现为 2026-08-30），不写墙钟时间，也不写本机路径（换台机器生成物不该变）；上游路径只出现在 `lib-dump.js` 的注释和默认值里。
- 实际区间数：`6` 309 段、`11` 888 段、`15` 原始 `getInfo` 2269 段（取值 20 种、最大 `0x3b`，放进 `Byte`）。
- `core.autocrlf = true` 下检出的是 CRLF，脚本写的是 LF：内容没变也会被 `git status` 报成改动。`writeGenerated` 先按 LF 比较，**内容不变就不重写**。
- `.inc` 头部另注明 `15` 表数据经 addon 取自 unicode-properties（§14）。

### 4.3 ambiguous 宽度

- 15 / 15-graphemes：照上游，`AmbiguousWide = True` 等于把 provider 的 `ambiguousCharsAreWide` 设为 true（`UnicodeGraphemeProvider.ts:13`、`:37`、`:67`）。node 脚本可以直接改这个字段，所以两种设置都有期望值。
- 6 / 11：上游没有这类数据。**建议**：这两个版本下 `AmbiguousWide` 不起作用，文档写明（~~待拍板~~ 已定，§17.1 第 2 条）。另一种做法是借 15 表的 ambiguous 类，但那就没有上游基准了。

**实现期修正（1 期）**：U+0301 这类组合符在 15 表里本身是 ambiguous。打开 `AmbiguousWide` 后，`e` + U+0301 在 `15` 下宽 3（组合符不连接、自占两格，§4.1），在 `15-graphemes` 下宽 2（连接后宽取 2，减去前一个的 1）。用户结论：照搬上游，3 期控件文档写明。

### 4.4 接口草案

```pascal
type
  TTyUnicodeVersion = (tuv6, tuv11, tuv15, tuv15Graphemes);
  TTyUnicodeCharProps = type Cardinal;   // state shl 3 or width shl 1 or Ord(shouldJoin)

function TyUnicodeWcWidth(ACodepoint: Cardinal; AVersion: TTyUnicodeVersion;
  AAmbiguousWide: Boolean): Integer;                         // 0..2
function TyUnicodeCharProperties(ACodepoint: Cardinal; APreceding: TTyUnicodeCharProps;
  AVersion: TTyUnicodeVersion; AAmbiguousWide: Boolean): TTyUnicodeCharProps;
function TyUnicodePropsWidth(AProps: TTyUnicodeCharProps): Integer;       // extractWidth
function TyUnicodePropsShouldJoin(AProps: TTyUnicodeCharProps): Boolean;  // extractShouldJoin
function TyUnicodePropsKind(AProps: TTyUnicodeCharProps): Cardinal;       // extractCharKind
{ UTF-8 串占几格，照 UnicodeService.getStringCellWidth（:67-95），含孤立代理的 UCS-2 回退 }
function TyUnicodeStringCellWidth(const AUtf8: string; AVersion: TTyUnicodeVersion;
  AAmbiguousWide: Boolean): Integer;
function TyUnicodeVersionName(AVersion: TTyUnicodeVersion): string;      // '6' '11' '15' '15-graphemes'
```

纯函数、无全局状态（查表数据是常量）。`TTyUnicodeVersion` 的名字和上游 `activeVersion` 字符串一一对应，夹具里写字符串。

**实现期修正（1 期）**：
- 签名照上面原样实现。「无全局状态」的准确说法：`6` / `11` 的 BMP 在单元 `initialization` 里展开成两张 64K 字节表（§17.2 第 5 条），之后只读；多线程读是安全的。
- `getStringCellWidth` 的行号是 `UnicodeService.ts:67-101`（不是 `:67-95`）。
- **输入按 WTF-8 读**：上游循环的是 UTF-16 单元，标准 UTF-8 装不下孤立代理。三字节编码的 U+D800..U+DFFF 解成那个孤立单元，UCS-2 回退因此够得着；两个这样的三字节序列（CESU-8 写法的代理对）在上游循环里照样合成一对，和单元序列一致。
- **其他非法字节**：每个出错的首字节出一个 U+FFFD、只吃这一个字节（截断、超长编码含三 / 四字节的超长形式、后续字节不是续字节、超过 U+10FFFF 都算）。上游没有这类输入，判据是相对的：和同样多的 U+FFFD 一样宽。
- **越界码位**（> U+10FFFF）：`6` / `11` 的 `wcwidth` 答 1，`15` / `15-graphemes` 也是 1（trie 答 `errorValue` 0，归 `Other`、宽度类 normal）。三个越界常量由脚本从上游问出、写进 `.inc`。

### 4.5 测试（1 期）

- 全码位：四个版本 × 两种 ambiguous（6 / 11 只一种）的 `wcwidth`，和 dump 逐个比。数据表本身就是 dump，这一条验的是查表代码和生成链路，不是循环论证——数据正确性来自「dump 即上游」。
- 连接：`charProperties(cp, preceding)` 的序列用例（组合符、韩文 L/V/T、区旗对、ZWJ 表情序列、VS15/VS16、Prepend），node 端调 `_core.unicodeService.charProperties` 逐步记录，比打包值。
- 串宽：`getStringCellWidth` 用例，含孤立代理。
- 变异：区间二分的边界、`oldWidth > width` 的比较方向、区旗对强制宽 2（`UnicodeGraphemeProvider.ts:52-54`）都要能被杀。

---

## 5. `tyControls.Terminal.Parser`

### 5.1 范围

- **UTF-8 解码**：照 `Utf8ToUtf32`（`xterm:src/common/input/TextDecoder.ts:121-`），跨块保留半截序列。非法字节**直接丢弃**，不换成 U+FFFD（`:174-176` 丢弃中间字节，`:341` 跳过非法字节）——要逐位对上就得照这个做。
- **状态机**：Paul Williams 的 DEC 解析器 + 子参数（`EscapeSequenceParser.ts:232-258` 的说明），转移表在单元初始化时照上游代码生成一次（上游在模块加载时生成，`:97-230`）。
- **处理器注册**：打印、执行（C0 / C1）、CSI、ESC、OSC、DCS、APC 各一张表；键 = 前缀 + 中间字节 + 终止字节，同上游 `_collect << 8 | final`（`:717`）。处理器返回 `Boolean`，false 继续找下一个（上游的回退链）。
- **每次最多喂 131072 个码位**（`MAX_PARSEBUFFER_LENGTH`，`InputHandler.ts:45`），超出的分段喂。

**实现期修正（2 期）**：
- ~~131072 个码位~~ 131072 **字节**：上游按输入单元切，字节输入的单元就是字节（`InputHandler.ts:458-468`）；解码器的半截序列和 `PrecedingJoinState` 跨切口保留。
- U+FEFF（BOM）不论出现在哪，照上游解码器丢弃（`TextDecoder.ts:195`、`:293`）。

### 5.2 有界

| 上限 | 值 | 出处 | 超出时 |
|---|---|---|---|
| 参数个数 | 32 | `Params.ts:78` | 后面的丢弃（`:160`） |
| 子参数总数 | 32（硬上限 256） | `Params.ts:78`、`:13-15` | 丢弃（`:183`） |
| 参数值 | 0x7FFFFFFF | `Params.ts:11` | 截到上限（`:168`、`:246`） |
| 中间字节 | 2 个 | `EscapeSequenceParser.ts:255-256` | 照上游 |
| OSC / DCS / APC 载荷 | 10,000,000 | `parser/Constants.ts:65-67`；`OscParser.ts:196-237` | 标记超限，结束时处理器收到失败、不执行 |

坏序列、超长序列的测试断言的就是这几条：喂完之后内存和状态都在上限以内，后续正常序列照常工作（§13.4）。

**实现期修正（2 期）**：
- 载荷上限按 **UTF-16 单元**计（码位 > U+FFFF 记 2），判定用 `>`（`StringBuilder.ts:55-61`）：10,000,000 单元还收，多一个就不收。Pascal 存 UTF-8，计数照 UTF-16。
- OSC 编号在 Int64 里饱和累加，不回绕（上游是 JS 浮点）；超过 `High(Integer)` 的编号不命中任何处理器，也不交 `OnOsc`。
- 解析器以外也有界：REP 快进（§7.2、§15）、IL / DL / SU / SD / CHT / CBT 的循环钳到还可能改变状态的遍数、链接表上限、`Scrollback` 上限（§6.2）、写入队列的块数上限（§3.1）；没挂 `OnOsc` 时未处理 OSC 的载荷根本不收集（§7.4）。

### 5.3 接口草案

```pascal
type
  TTyTerminalParams = class      // 照 Params.ts：Params / SubParams / Length / AddParam / AddDigit …
  TTyTerminalPrintEvent   = procedure(const AData: array of Cardinal; AStart, AEnd: Integer) of object;
  TTyTerminalExecuteEvent = function: Boolean of object;
  TTyTerminalCsiEvent     = function(AParams: TTyTerminalParams): Boolean of object;
  TTyTerminalEscEvent     = function: Boolean of object;
  TTyTerminalOscHandler   = class   // Start / Put / End(ASuccess): Boolean，照 IOscHandler
  TTyTerminalDcsHandler   = class   // Hook(AParams) / Put / Unhook(ASuccess)
  TTyTerminalApcHandler   = class

  TTyTerminalFunctionId = record Prefix, Intermediates: string; Final: Char; end;

  TTyTerminalParser = class
  public
    procedure SetPrintHandler(AHandler: TTyTerminalPrintEvent);
    procedure SetExecuteHandler(ACode: Byte; AHandler: TTyTerminalExecuteEvent);
    procedure RegisterCsiHandler(const AId: TTyTerminalFunctionId; AHandler: TTyTerminalCsiEvent);
    procedure RegisterEscHandler(const AId: TTyTerminalFunctionId; AHandler: TTyTerminalEscEvent);
    procedure RegisterOscHandler(AIdent: Integer; AHandler: TTyTerminalOscHandler);
    procedure RegisterDcsHandler(const AId: TTyTerminalFunctionId; AHandler: TTyTerminalDcsHandler);
    procedure RegisterApcHandler(const AId: TTyTerminalFunctionId; AHandler: TTyTerminalApcHandler);
    procedure SetOscFallback(...); procedure SetCsiFallback(...); // 未注册的序列交给这里
    procedure Parse(const AData: array of Cardinal; ALength: Integer);
    procedure Reset;
    property PrecedingJoinState: TTyUnicodeCharProps;  // 跨块的字形簇连接状态（EscapeSequenceParser.ts:266）
  end;

  TTyUtf8Decoder = class   // Decode(const ABytes; ACount; var AOut: array of Cardinal): Integer; Clear
```

注销：上游返回 `IDisposable`；Pascal 版 `Register*` 返回一个整数句柄，`Unregister(AHandle)` 撤销。

**实现期修正（2 期）**：
- 回退处理器全套：执行、CSI、ESC、OSC、DCS、APC 各一个 `Set*HandlerFallback`，打印处理器可设可清（`SetPrintHandler` / `ClearPrintHandler`），外加错误处理器 `SetErrorHandler` / `ClearErrorHandler`；`Clear*Handler` 对应上游的删除。
- `IOscHandler.end` / `IApcHandler.end` 在 Pascal 是保留字，叫 `Finish`；`IDcsHandler.unhook` 叫 `Unhook`。
- 注册进来的处理器对象归解析器所有：`Unregister`、`Clear*` 或解析器析构时释放；正在用的（解析中注销自己、清掉正在进行的 OSC 那条链）延后到解析返回或解析器析构，那条链照上游继续服务眼下这个序列。不存在或已注销的句柄是空操作。
- `OscPayloadLength`、`TyTermTransition` 是给测试的纯查询，注释标明。

---

## 6. `tyControls.Terminal.Buffer`

### 6.1 单元格和行

照 `BufferLine`：每格三个 `Cardinal`——content、fg、bg（`xterm:src/common/buffer/BufferLine.ts:29-33`，数组 `:70`）。
- content：低 21 位码位、第 22 位「组合内容」标志、23–24 位宽度（`buffer/Constants.ts:36-74`）。组合内容（一格里多个码位）另存在按列号索引的稀疏表里（上游 `_combined`，`BufferLine.ts:72`）。
- fg / bg：颜色模式（默认 / 16 / 256 / RGB）+ 颜色 + 属性位。fg 上是反显、粗体、下划线、闪烁、隐藏、删除线（`Constants.ts:116-121`），bg 上是斜体、暗淡、有扩展属性、受保护、上划线（`:128-132`）。
- 扩展属性（下划线样式 / 颜色 / 变体偏移、OSC 8 链接号）另存（`AttributeData.ts:141-180`，`BufferLine.ts:74`）。
- 宽字符占两格，第二格宽度 0；「空格」和「从没写过」是两回事（`NULL_CELL_*` vs `WHITESPACE_CELL_*`，`Constants.ts:15-30`）。

逐位照搬这套位布局——期望值直接比这三个字（§13.3），布局一变就对不上。

### 6.2 缓冲

- 行存在环形表里（`CircularList.ts`），容量 = 行数 + 滚回；满了从头上挤掉。
- 主缓冲有滚回，备用缓冲没有（`BufferSet.ts:41`、`:47`）。切回主缓冲时清空备用缓冲（`:82-101`），切到备用时用当前擦除属性填满（`:103-121`）。
- 每行一个 `IsWrapped` 标志：这一行是上一行自动折过来的。选行、复制、重新折行都靠它。
- 光标、滚动区域（`ScrollTop` / `ScrollBottom`）、保存的光标、制表位、`YBase`（最底屏的起点）、`YDisp`（视口起点）都在缓冲上，跟缓冲一起切换。
- 标记（`Marker.ts`）：挂在某一行上、随滚动移动、行被挤掉时作废。控件用它记住选区的锚点；宿主可用来做 shell 集成的命令边界。
- 链接表：OSC 8 的 `id` + URI → 链接号，格子上存链接号（`OscLinkService.ts`）。
- **重新折行**（5 期）：宽度变化时按 `IsWrapped` 重排主缓冲（`BufferReflow.ts`、`Buffer.ts:258-259`）；备用缓冲不折。Windows ConPTY 版本号低于 21376 时上游**关掉折行**（`Buffer.ts:310-316`）并打开「行尾不是空白就当折行」的启发（`CoreTerminal.ts:279-289`、`WindowsMode.ts:9-26`）——本机 Windows 10 LTSC 2021 是 19044，正好落在这条线下面。控件照移植，由宿主告诉 Core 后端和版本号（`WindowsPty`，§7.2、§7.6）。

**实现期修正（2 期）**：
- 行和标记都带非原子引用计数（`AddRef` / `Release`，归零释放；Core 只在主线程）。环形表每个槽位、`BufferService` 的缓存空行各持一份；跨一次表修改还要用的行显式钉住（打印的当前行和折行前的旧行）。槽位写入先加新引用再减旧引用，所以把一行挪到同一表的另一个槽位不必钉。`Pop` 和缩短长度后，越界槽位的引用保留到被覆盖，和上游数组一样。标记由缓冲持一份、链接表每列一次持一份。
- 行表起点照上游只在 `push` / `recycle` 取模，`splice` / `trimStart` / `shift` 不取模，用 Int64 存——`Get(-1)` 因此和上游答得一样。
- `Clear` 换新行表时缓冲的代号加一，旧代号的标记从此不再随行移动（上游它们还订阅着旧表）。
- 2–4 期折行恒关：`IsReflowEnabled` 恒 False，但 `Resize` 已经在上游的位置读它、调 `Reflow`（空实现）并在变窄时截短行——5 期只填 `Reflow`、把开关换成上游规则。改列数的基准用例都在 `windowsPty = {conpty, 19044}` 下（上游这时同样不折）。
- `Scrollback` 上限 100000（`TyTermMaxScrollback`）：环形表按容量一次分配指针数组，上游的 JS 数组是稀疏的，给 10^9 会直接分配 8GB。选上限而不是按需增长：多一行判断、不碰环形表的下标算法。更大的值按上限取，负数照上游抛异常。
- OSC 8 链接表最多 10000 条、`id` + URI 合计 16MB（`TyTermMaxLinks`、`TyTermMaxLinkBytes`），再多就丢最老的（格子上留着的号从此查不到，按无链接画）；链接号改 Int64，注册超过 2^31 次仍然递增有序。上游两样都无界（§15）。

### 6.3 接口草案

```pascal
type
  TTyTerminalCellData = record
    Content, Fg, Bg: Cardinal;
    Ext: TTyTerminalExtAttrs;       // UnderlineStyle, UnderlineColor, UnderlineVariantOffset, UrlId
    Combined: string;               // UTF-8；组合内容时有值
  end;

  TTyTerminalLine = class
  public
    procedure LoadCell(ACol: Integer; var ACell: TTyTerminalCellData);
    function  GetWidth(ACol: Integer): Integer;
    function  GetChars(ACol: Integer): string;        // UTF-8
    function  TranslateToString(ATrimRight: Boolean; AStartCol: Integer = 0; AEndCol: Integer = -1): string;
    property  IsWrapped: Boolean;
    property  Length: Integer;
  end;

  TTyTerminalBuffer = class
  public
    function  GetLine(AAbsRow: Integer): TTyTerminalLine;   // 0 = 滚回最早一行
    function  GetWrappedRangeForLine(AAbsRow: Integer; out AFirst, ALast: Integer): Boolean;
    function  AddMarker(AAbsRow: Integer): TTyTerminalMarker;
    property  YBase, YDisp, X, Y, ScrollTop, ScrollBottom: Integer;
    property  HasScrollback: Boolean;   // Buffer.ts:103-105 的同一判据
    property  Length: Integer;          // 当前总行数
  end;

  TTyTerminalBufferSet = class  // Normal, Alt, Active, IsAlt, OnActivate
```

**实现期修正（2 期）**（§6.1、§6.3）：
- `TranslateToString` 连缓存一起移植，缓存的答案可观察：先要不去尾的、再要去尾的，上游对缓存做 JS `trimEnd()`，会连写进去的空格和别的 JS 空白一起去掉，和按「去尾长度」算的结果不同，照上游。实现用两遍扫描、一次分配。
- 行的 `Resize` 返回值照上游「`cleanupMemory` 能不能省内存」，按分配容量算（缩短不释放、变长够用就复用）；内存回收调度本身没有可观察行为，不移植。
- 制表位表保留列数以外的旧键（上游不删），导出时按数值排序。
- 字符集替换只取映射串的第一个 UTF-16 单元（上游 `charCodeAt(0)`），表由脚本 dump。
- 组合文本、扩展属性的稀疏表只在格子标志位说有时才读：`CombinedEntry` / `ExtendedEntry` 先看标志位，残留的旧条目永远不是答案（上游也只在标志位后面查表）。
- `TTyTerminalExtAttrs.UrlId` 是 Int64（链接号，§6.2）。
- `LiveCount`（行、标记、链接条目各一个）、`SlotLine`、`SeedNextIdForTest` 是给测试的，注释标明。

---

## 7. `tyControls.Terminal.Core`

### 7.1 类的形态

`TTyTerminalCore = class(TObject)`，不是 `TComponent`、不上组件面板。控件自己建一个、`Core` 属性只读公开；测试和无头场景直接 `Create`。（定稿时新加：放成组件会引出「设计器里改它的属性要不要流式化」一整套问题，而这些属性控件上都有。）

### 7.2 处理范围

**控制序列**：照 `InputHandler` 全部移植——它的 `@vt` 注释表就是支持清单（`npm run vtfeatures` 从这些注释抽表，`xterm:package.json:71`）。私有模式按 `setModePrivate` / `resetModePrivate` 的表（`InputHandler.ts:1899-1928`）：

| 模式 | 作用 | 我们 |
|---|---|---|
| 1 / 66 | 应用光标键 / 应用小键盘 | 照上游 |
| 3 | 132 列（上游只在 `windowOptions.setWinLines` 开时生效，`:1945-1955`） | 照上游，默认不生效 |
| 6 / 7 / 45 | 原点、自动折行、反向折行 | 照上游 |
| 12 | 光标闪烁（上游要 `quirks.allowSetCursorBlink`，`:1963-1967`） | 照上游，默认不生效 |
| 25 | 显示光标 | 照上游 |
| 9 / 1000 / 1002 / 1003 | 鼠标协议 X10 / VT200 / DRAG / ANY（`:1976-1991`） | 照上游 |
| 1004 | 焦点报告 `CSI I` / `CSI O`（`:1992-1997`） | 照上游 |
| 1006 / 1016 | SGR / SGR 像素编码（`:2001-2009`） | 照上游 |
| 1005 / 1015 | 上游只记日志（`:1998-2006`，#2507 移除） | 同上游，不做 |
| 47 / 1047 / 1048 / 1049 | 备用屏、存取光标 | 照上游（1049 不清备用屏也照上游，`:1926` 的 `#P` 说明） |
| 2004 | 括号粘贴 | 照上游 |
| 2026 | 同步输出 | 照上游，渲染侧 §3.2 |
| 2031 | 颜色主题变化通知（`vtExtensions.colorSchemeQuery` 默认 true，`typings/xterm.d.ts:494-504`） | 照上游 |
| 9001 | win32-input-mode | Core 照上游记下模式（选项默认关，所以不生效）；键盘侧后期（§15） |

**应答**（经 `OnData`）：DA1 / DA2（`InputHandler.ts:1711-1758`）、DSR / CPR（`:2743-`、`:2760-`）、DECRQM（`:2336-`）、DECRQSS（DCS `$q`，`:375`）、XTVERSION（`:1775`）。
**有意不同**：XTVERSION 上游报 `xterm.js(6.0.0)`（`:1775`，版本来自 `Version.ts:9`），我们报 `TyControls(<库版本>)`；夹具比较时把这一段替换掉（§13.5）。

**选项**：照 `DEFAULT_OPTIONS`（`OptionsService.ts:12-61`）里和核心有关的那部分——`Scrollback`（1000）、`TabStopWidth`（8）、`ConvertEol`（false）、`ScrollOnUserInput`（true）、`ReadOnly`（= `disableStdin`，false）、`WindowOptions`（全关）、`VtExtensions`（kitty 键盘 false、win32-input-mode false、SGR 221/222 true、颜色主题查询 true，`typings/xterm.d.ts:465-505`）、`WindowsPty`（空）、`UnicodeVersion`、`AmbiguousWide`。

**实现期修正（2 期）**：
- 选项补四个（核心代码读它们）：`CursorStyle` / `CursorBlink`（DECRQSS `" q"` 的应答、DECRQM 12 读选项值）、`ScrollOnEraseInDisplay`（ED 2 的分支，默认 false）、`AllowSetCursorBlink`（上游 `quirks.allowSetCursorBlink`，默认 false）。`termName` 固定 `'xterm'`，不开放。`Scrollback` 有上限 100000（§6.2）。
- 1004：打开的那一刻按 Core 记住的焦点立即报一次（浏览器层的行为，`CoreBrowserTerminal.ts:1124-1130`）。`Focused` 初值 **True**（和上游浏览器层起步时的假设一致）：3 期控件建好后必须按实际焦点调一次 `ReportFocus`，否则一个没焦点的终端在程序打开 1004 时会报「有焦点」。
- XTWINOPS 14t / 16t 要像素，Core 只发 `OnWindowOptionsReport(Sender, AKind)`，由控件应答；默认 `WindowOptions = []` 走不到。18t / 22t / 23t Core 自己处理。
- DECCOLM（`CSI ? 3 h/l`，要 `twoSetWinLines`）改到 132 / 80 列后发 `OnResize`，和 `Resize` 同一个事件（上游 `BufferService.onResize` → `onResize`）。
- `OnIconNameChange`（上游只存不发）和 `OnModesChange`（上游没有，每条改了模式的序列发一次）是新增事件。
- REP 按次数精确打印，靠快进保证耗时有界（§15）。

### 7.3 颜色请求

OSC 4 / 10 / 11 / 12 设置和查询、OSC 104 / 110 / 111 / 112 复位（`InputHandler.ts:293-325`）。上游核心只发事件，由浏览器层拿主题色应答或改色（`CoreBrowserTerminal.ts:211-258`）。
我们把**覆盖表**放在 Core：程序设置的颜色存成「第 n 色 → RGB」，复位就删掉；查询时 Core 问控件要基准色（事件 `OnQueryBaseColor`），有覆盖用覆盖。渲染取色也走同一处：覆盖表优先，其次主题。
颜色主题查询（`CSI ? 996 n`）照上游用前景 / 背景亮度比较决定报深 / 浅（`CoreBrowserTerminal.ts:261-`）。主题切换时控件调 `Core.NotifyColorSchemeChanged`，开了 2031 就发通知。

**实现期修正（2 期）**：
- 2031 开着时，**每一次** OSC 设色、复位色都报一次明暗（上游 `modifyColors` / `restoreColor` 都发 `onChangeColors`，`CoreBrowserTerminal.ts:526-531`）。
- `NotifyColorSchemeChanged` 先清空覆盖表（上游换主题重建整张色表，OSC 覆盖色随之丢掉，`ThemeService.ts:80-139`），再按 2031 报明暗。RIS 不清覆盖表（上游 `reset` 不碰 ThemeService）。
- 没挂 `OnQueryBaseColor` 就没有主题可答：OSC 4 / 10 / 11 / 12 的查询、`CSI ? 996 n`、2031 的通知一律不应答，和上游 headless 一致；设色、复位照常记进覆盖表。焦点报告不受影响。

**实现期修正（3 期）**，控件侧：
- 色表（`OnQueryBaseColor` 答的那一份）：0–15 取主题的 `TyTerminalAnsi<n>`，16–255 按上游公式算，256 / 257 取 `TyTerminal` 的前景 / 底色，258 取 `TyTerminalCursor` 的底色；颜色一律取 RGB、丢 alpha；缺了退到 Tango / 黑白，不抛。
- 色表按**本实例的无状态样式**取：类型键 + 实例的 `StyleClass`，`TyTerminal` 再叠 `StyleOverride`；不跟悬停、聚焦、禁用走（禁用在绘制时预混，§11）。实例换了底（类或覆盖改了 `background`），16 色的 token（`on(var(--terminal-bg), …)`）拿这个实例的底色重新求一次，深底就换成深底那套——只在这一色确实来自 token 时（类没有另写它）；光标色、光标下的字色默认就是前景、底色，也跟着实例的前景、底色换。
- ~~换主题时控件调 `NotifyColorSchemeChanged`~~ 只有色表真变了（换明暗、换配色）才调；改内边距、字体的主题变化不调（它会清掉程序设的覆盖色）。第一次建色表不算变化。在绘制里才发现的主题变化不当场调（它会发 `OnData`），记下来经消息循环再调。
- 程序改了颜色时整窗重画，见 §3.2 的控件侧修正。

### 7.4 未处理的 OSC

核心注册的 OSC 只有 0 / 1 / 2 / 4 / 8 / 10 / 11 / 12 / 104 / 110 / 111 / 112（`InputHandler.ts:286-325`）。52 由控件注册（§9.6.3）。其余一律进 `OnOsc(Ident, Data, var Handled)`——7（当前目录）、133 / 633（shell 集成）、1337 等由宿主处理。宿主也可以直接 `Core.Parser.RegisterOscHandler`。

**实现期修正（2 期）**：
- ~~`OnOsc(Ident, Data, var Handled)`~~ `OnOsc(Sender, AIdent, AData)`：Core 对未处理的 OSC 本来就没有默认动作，`Handled` 无处可用，删掉。
- 只交 0..`High(Integer)` 的编号（没有编号的 OSC 是 -1，也不交）。载荷和字符串处理器同一个上限，成功结束才交。
- OSC 开始时没挂 `OnOsc` 就不收集载荷（中途才挂上的那一个也不交），没人听不花内存。

### 7.5 鼠标协议状态

照 `MouseStateService`（`xterm:src/common/services/MouseStateService.ts`）：五种协议及其过滤（`:13-82`）、事件码（`:92-113`）、三种编码（`:121-151`；默认编码超过 223 就不报，`:133-135`）。
上报前的过滤照浏览器层 `_triggerMouseEvent`（`MouseService.ts:497-545`）：去掉无意义组合、坐标转 1 起、移动事件按格（像素编码按像素）去重、协议限制、编码。控件把 LCL 鼠标事件换成 `TTyTerminalMouseEvent` 交给 `Core.TriggerMouseEvent`，Core 决定发不发、发什么。

**实现期修正（2 期）**：
- `RestrictMouseEvent` / `EncodeMouseEvent` 是上游 `MouseStateService` 的两个纯函数，收 **1 起**坐标（和上游一样），直接对上游比（`core-cases.js` 的鼠标夹具）。
- `TriggerMouseEvent` 本批提前到 2 期（原计划 4 期），3 期起控件不必自己路由：收 0 起的格子和设备像素；出界、滚轮 + 移动、无键 + 非移动、非滚轮 + 左右，一律 False；转 1 起；移动与上一个事件相同（按格，SGR-像素按像素，连同键、动作、修饰键）就丢；协议限制；编码；默认编码走二进制（不滚到底、不算用户输入，上游 `triggerBinaryEvent`），其余走 `triggerDataEvent(报告, true)`（滚到底、下一次 `Write` 当场解析）。编码放不下（默认编码超过 223）时照上游仍返回 True、记为上一个事件。`Reset` 清掉上一个事件（上游 `mouseService.reset`）。上游这一段是浏览器代码，没有基准，逐条写判据测试。

### 7.6 接口草案

```pascal
type
  TTyTerminalDataEvent  = procedure(Sender: TObject; const AData: RawByteString) of object;
  TTyTerminalTextEvent  = procedure(Sender: TObject; const AText: string) of object;
  TTyTerminalRowsEvent  = procedure(Sender: TObject; AFirst, ALast: Integer) of object;
  TTyTerminalOscEvent   = procedure(Sender: TObject; AIdent: Integer; const AData: string;
                                    var AHandled: Boolean) of object;
  TTyTerminalWriteDone  = procedure(Sender: TObject; ATag: PtrInt) of object;
  TTyTerminalColorQuery = procedure(Sender: TObject; AIndex: Integer; out ARgb: Cardinal) of object;
                          // AIndex: 0..255 调色板；256 前景；257 背景；258 光标（上游 SpecialColorIndex）

  TTyTerminalMouseButton = (tmbLeft, tmbMiddle, tmbRight, tmbNone, tmbWheel);
  TTyTerminalMouseAction = (tmaUp, tmaDown, tmaLeft, tmaRight, tmaMove);  // Left/Right 只用于滚轮
  TTyTerminalMouseEvent = record
    Col, Row, X, Y: Integer;   // 0 起的格子；X/Y 设备像素（§9.5.1）
    Button: TTyTerminalMouseButton; Action: TTyTerminalMouseAction;
    Shift, Alt, Ctrl: Boolean;
  end;
  TTyTerminalMouseProtocol = (tmpNone, tmpX10, tmpVT200, tmpDrag, tmpAny);
  TTyTerminalMouseEncoding = (tmeDefault, tmeSgr, tmeSgrPixels);

  TTyTerminalModes = record   // 只读快照，字段对应 xterm headless 的 IModes（typings/xterm-headless.d.ts:1424-1484）
    ApplicationCursorKeys, ApplicationKeypad, BracketedPaste, Insert, Origin,
    ReverseWraparound, SendFocus, ShowCursor, SynchronizedOutput, Win32Input, Wraparound,
    ColorSchemeUpdates: Boolean;
    MouseProtocol: TTyTerminalMouseProtocol; MouseEncoding: TTyTerminalMouseEncoding;
    CursorRequest: (tcrDefault, tcrBlock, tcrUnderline, tcrBar);   // DECSCUSR；Default = 用控件属性
    BlinkRequest: (tbrDefault, tbrOn, tbrOff);
  end;

  TTyTerminalCore = class
  public
    constructor Create(ACols, ARows: Integer);
    { 写入 }
    procedure Write(const AData: RawByteString; AOnDone: TTyTerminalWriteDone = nil; ATag: PtrInt = 0);
    procedure Write(const ABuf; ACount: Integer; AOnDone: TTyTerminalWriteDone = nil; ATag: PtrInt = 0);
    procedure WriteSync(const AData: RawByteString);
    function  ProcessPending(ABudgetMs: Integer = 12): Boolean;   // 还有剩返回 True；控件据此再排一片
    property  PendingBytes: Int64;
    { 输入（控件调） }
    procedure Input(const AData: RawByteString; AWasUserInput: Boolean = True);  // 照 triggerDataEvent
    function  TriggerMouseEvent(const AEvent: TTyTerminalMouseEvent): Boolean;
    procedure ReportFocus(AFocused: Boolean);                 // 1004 开着才发
    procedure NotifyColorSchemeChanged;
    { 尺寸与状态 }
    procedure Resize(ACols, ARows: Integer);                  // 最小 2×1（BufferService.ts:13-14）
    procedure Reset;
    procedure ScrollLines(ADelta: Integer); procedure ScrollToBottom; procedure ScrollToTop;
    procedure ClearScrollback;
    property  Cols, Rows: Integer;
    property  Buffers: TTyTerminalBufferSet;
    property  Buffer: TTyTerminalBuffer;          // 当前缓冲
    property  Modes: TTyTerminalModes;
    property  Title: string;
    property  Parser: TTyTerminalParser;          // 宿主可注册自己的处理器
    function  ResolveColor(AIndex: Integer): Cardinal;   // 覆盖表 → OnQueryBaseColor
    { 选项（§7.2） }
    property  Scrollback, TabStopWidth: Integer;
    property  ConvertEol, ScrollOnUserInput, ReadOnly, AmbiguousWide: Boolean;
    property  UnicodeVersion: TTyUnicodeVersion;
    property  WindowsPty: TTyTerminalWindowsPty;  // Backend: (twpNone, twpConPty, twpWinPty); BuildNumber
    property  WindowOptions: TTyTerminalWindowOptions;   // set of，默认 []
    property  VtExtensions: TTyTerminalVtExtensions;     // set of，默认同上游
    { 事件 }
    property  OnData: TTyTerminalDataEvent;
    property  OnRefreshRows: TTyTerminalRowsEvent;
    property  OnTitleChange, OnIconNameChange: TTyTerminalTextEvent;
    property  OnBell, OnCursorMove, OnLineFeed, OnScroll, OnBufferActivate, OnModesChange: TNotifyEvent;
    property  OnOsc: TTyTerminalOscEvent;
    property  OnQueryBaseColor: TTyTerminalColorQuery;
    property  OnRequestScrollToBottom: TNotifyEvent;
  end;
```

**实现期修正（2 期）**：实际接口（`source/tyControls.Terminal.Core.pas`）比上面多出、改动的：
- 写入：`ProcessPending(ABudgetMs = 12)`、`PendingBytes`、`Clock`、`OnProcessRequest`（§3.1）；`ETyTerminalWriteOverflow`。
- ~~`OnScroll: TNotifyEvent`~~ `OnScroll(Sender, AYDisp)`：带视口位置，和上游 `onScroll` 一致。
- 新增：`ScrollPages`（页数 × 行数在 Int64 里算、钳进 Integer）、`IconName`、`Links`（OSC 8 链接表）、`HasColorOverride`（纯查询）、`Focused`（只读，初值 True，§7.2）、`EndSynchronizedOutput`（§3.2）、`TriggerMouseEvent`（§7.5）、`OnResize(Sender, ACols, ARows)`（`Resize` 与 DECCOLM）、`OnScrollbackCleared`（ED 3 真清掉了滚回时、`ClearScrollback` 每次）、`OnWindowOptionsReport`（§7.2）、`OnIconNameChange`、`OnModesChange`、`CursorStyle` / `CursorBlink` / `ScrollOnEraseInDisplay` / `AllowSetCursorBlink`（§7.2）。
- `OnOsc` 去掉 `var AHandled`（§7.4）。
- 给测试的只读查询（`CharsetOfG`、`CharsetKey`、`WindowTitleStack`、`IconNameStack`、`KittyStacks`、`KittyFlags` 等、`IsCursorInitialized`、`GLevel`、`CurrentAttr`、`EraseAttr`、`BufferService`）集中在一处，注释标明「FOR THE TESTS」。
- 事件全部同步发，大多在解析中；事件里调 `Resize` / `Reset` / `WriteSync` 会被延后到这一块处理完，`ProcessPending` 直接返回 False（§3.1）。接口注释写明。

---

## 8. `tyControls.Terminal.Keyboard`

### 8.1 移植什么

`evaluateKeyboardEvent`（`xterm:src/common/input/Keyboard.ts:38-380`）整个函数，纯函数：输入按键事件、应用光标模式、是否 macOS、`macOptionIsMeta`，输出三类结果之一——发送字节、全选、上翻页 / 下翻页（`Types.ts:71-76`；Shift+PgUp/PgDn 是本地翻页，`Keyboard.ts:207-225`）。
上游按键事件有四个修饰键 + `keyCode` + `key`（产生的字符）+ `code`（物理键名）（`Types.ts:55-65`）。

### 8.2 LCL 事件怎么换成上游的按键事件

- **`keyCode`**：LCL 的 `VK_*` 就是 Windows 虚拟键码（`lcl:lcltype.pp:436`、`:440`、`:495`、`:511`、`:591`、`:597` 等），和浏览器 `keyCode` 同源，直接用。
- **`code`**：由 VK 查一张美式布局表得到（`KeyA`、`Digit2`、`Minus`……）。上游只在 Ctrl+Shift 的三个组合（`Keyboard.ts:369-375`）和死键判定（`:348-359`）里用它。
- **`key`**：LCL 的 `KeyDown` 拿不到产生的字符，按 VK + Shift 查美式布局表填（和上游 `KEYCODE_KEY_MAPPINGS` 同一张表，`Keyboard.ts:11-`）。能产生字符的普通键在 `KeyDown` 里**不发**，留给 `UTF8KeyPress`——和上游「A–Z 放到 keypress 里处理」同一个分工（`CoreBrowserTerminal.ts:898-903`、`:979-1017`）。
- **AltGr / 第三层 Shift**：照 `_isThirdLevelShift`（`CoreBrowserTerminal.ts:937-948`）：Windows 上 Ctrl+Alt 同按、或 macOS 上 Option 且不当 Meta 时，交给 `UTF8KeyPress` 出字符。
- **死键 / 输入法**：交给 LCL 和库内输入法（§9.9），`KeyDown` 里见到输入法处理中的键（Win32 的 `VK_PROCESSKEY`，上游 keyCode 229，`CompositionHelper.ts:117-131`）直接放过。

### 8.3 粘贴与焦点

- 粘贴：换行统一成 `CR`（`Clipboard.ts:13-15`）；括号粘贴模式开着时，把 ESC 换成 `␛`（U+241B）再包上 `ESC[200~ … ESC[201~`（`:21-29`）——防止粘贴内容自己提前结束括号。
- 焦点：1004 开着时 `CSI I` / `CSI O`（Core 发）。

### 8.4 接口草案

```pascal
type
  TTyTerminalKeyEvent = record
    KeyCode: Word; Key, Code: string;
    Shift, Ctrl, Alt, Meta: Boolean;
  end;
  TTyTerminalKeyResultKind = (tkrSendKey, tkrSelectAll, tkrPageUp, tkrPageDown);
  TTyTerminalKeyResult = record
    Kind: TTyTerminalKeyResultKind; Cancel: Boolean; Key: RawByteString;  // Key='' = 不发
  end;

function TyTerminalKeyEventFromLCL(AKey: Word; AShift: TShiftState): TTyTerminalKeyEvent;
function TyTerminalEvaluateKey(const AEvent: TTyTerminalKeyEvent; AApplicationCursor, AIsMac,
  AMacOptionIsMeta: Boolean): TTyTerminalKeyResult;
function TyTerminalIsThirdLevelShift(const AEvent: TTyTerminalKeyEvent; AIsMac, AIsWindows,
  AMacOptionIsMeta: Boolean): Boolean;
function TyTerminalPrepareTextForPaste(const AText: string; ABracketed: Boolean): RawByteString;
```

**实现期修正（3 期）**：
- `TTyTerminalKeyEvent` 加 `AltGraph: Boolean`（`getModifierState('AltGraph')`，LCL 的 `ssAltGr`）；`TyTerminalIsThirdLevelShift` 加最后一个参数 `AKeyPress: Boolean`——按下事件（False）另要 keyCode 为 0 或 > 47，字符事件（True）不看（§1.1 第 10 条）。
- 输入法处理中的键在 `KeyDown` 里直接放过、不问宿主：LCL 的 `VK_PROCESSKEY`（$E7）和库里的 `TyVkImeProcess = $E5`（Win32 输入法实际送来的 229）两个都认。
- 平台常量 `TyTerminalIsMac` / `TyTerminalIsWindows` 按平台（不是 widgetset）取。

---

## 9. 控件 `TTyTerminalView`

`TTyTerminalView = class(TTyCustomControl, ITyTextEditActions, ITyImeEditable, ITyScrollBarFrameHost)`
（基类 `source/tyControls.Base.pas:330`；三个接口见 §9.6、§9.9、§9.7。）

构造：`ControlStyle + [csOpaque, csDoubleClicks, csTripleClicks]`，`TabStop := True`，建 `FCore`。**构造里不建滚动条**，第一次排布时再建（照 `TTyMemo.UpdateScrollBar`，`source/tyControls.Memo.pas:2372-2504`）。

**实现期修正（3 期）**：~~`class(TTyCustomControl, ITyTextEditActions, ITyImeEditable, ITyScrollBarFrameHost)`~~ 本期只实现 `ITyImeEditable`、`ITyScrollBarFrameHost` 两个接口；`ITyTextEditActions`（右键菜单）和选区一起在 4 期加。构造里另设 `DoubleBuffered := False`（整面由表面位图贴，§10.1）。

### 9.1 published 属性

default 一律等于构造值（[[tabstop-declared-default-must-match]]）。浮点属性没法写 `default`，用 `stored` 函数。

| 属性 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `Scrollback` | Integer | 1000 | 滚回行数（`OptionsService.ts:34`）；0 = 没有滚回（此时主屏滚轮也翻成方向键，§9.5.4） |
| `CursorStyle` | `TTyTerminalCursorStyle` = (tcsBlock, tcsUnderline, tcsBar) | tcsBlock | `OptionsService.ts:18`；程序用 DECSCUSR 改的优先 |
| `CursorInactiveStyle` | (tcisOutline, tcisBlock, tcisBar, tcisUnderline, tcisNone) | tcisOutline | 失焦时的光标（`:20`） |
| `CursorBlink` | Boolean | False | `:16` |
| `SelectionOverrideKey` | (tsoDefault, tsoShift, tsoAlt, tsoNone) | tsoDefault | 程序接管鼠标时强制本地选择的修饰键；Default = Shift，macOS 上 = Option（§1.1 第 5 条）；Alt 在 macOS 上就是 Option |
| `AmbiguousWide` | Boolean | False | §4.3 |
| `UnicodeVersion` | `TTyUnicodeVersion` | tuv11（建议值，§17 问题 1 拍板） | §4 |
| `Osc52` | (to52Off, to52Write, to52ReadWrite) | to52Off | §9.6.3 |
| `MacOptionIsMeta` | Boolean | False | 只影响 macOS（§1.1 第 4 条） |
| `AlternateScroll` | Boolean | True | 程序没要滚轮、且缓冲没有滚回时，滚轮翻成方向键（§9.5.4） |
| `WordSeparators` | string | 空格 `( ) [ ] { } ' , "` 和反引号（见表下） | 双击选词的分隔字符（`OptionsService.ts:55`） |
| `DrawBoldTextInBrightColors` | Boolean | True | 粗体且前景是 0–7 色时改用 8–15 色（`:21`；`DomRendererRowFactory.ts:318`） |
| `CopyOnSelect` | Boolean | False | 选完就进剪贴板（定稿时新加，§17 问题 9） |
| `DetectUrls` | Boolean | True | 除 OSC 8 外，也按正则认出普通网址（§9.8） |
| `ReadOnly` | Boolean | False | 不发 `OnData`（`disableStdin`）；回放示例用 |
| `ConvertEol` | Boolean | False | LF 当 CR LF；回放只有 LF 的日志时用（`:57`） |
| `TabStopWidth` | Integer | 8 | `:48` |
| `ScrollOnUserInput` | Boolean | True | 用户输入时滚回底部（`:37`；`CoreService.ts:80-84`） |
| `ScrollBarAutoHide` | `TTyScrollBarAutoHide` | sbahDefault | 同 `TTyMemo`（`Memo.pas:880`；`ScrollBar.pas:355`） |
| `LineHeightPercent` | Integer | 100 | 行高倍数（上游 `lineHeight` 1.0，`:29`） |
| `LetterSpacing` | Integer | 0 | 字间距，逻辑像素（上游 `letterSpacing`，`:30`） |
| `MinimumContrastRatio` | Single（stored 函数） | 1 | 5 期；1 = 不调（`:43`；`typings/xterm.d.ts:197-207`） |

`WordSeparators` 的构造值写成 Pascal 是 ``' ()[]{}'',"`'``，和上游 `OptionsService.ts:55` 的字符集合逐字相同。

另有 `TTyCustomControl` 惯常的：`Align`、`Anchors`、`BorderSpacing`、`Constraints`、`Enabled`、`Visible`、`TabStop`、`TabOrder`、`PopupMenu`（设了就代替内置菜单）、`Hint`、`ShowHint`、`StyleClass`、`StyleOverride`、`Controller`、`Font` / `ParentFont`（§10.3）。

运行时只读：`Core`、`Cols`、`Rows`、`Title`、`SelectionText`、`HasSelection`。

**实现期修正（3 期）**：
- 本期 published 的是：`Scrollback`（负数按 0，上限 100000 由 Core 钳）、`CursorStyle`、`CursorInactiveStyle`、`CursorBlink`、`AmbiguousWide`、`UnicodeVersion`、`MacOptionIsMeta`、`AlternateScroll`、`DrawBoldTextInBrightColors`、`ReadOnly`、`ConvertEol`、`TabStopWidth`（小于 1 按 1）、`ScrollOnUserInput`、`ScrollBarAutoHide`、`LineHeightPercent`（钳到 100–300；上游小于 1 抛异常）、`LetterSpacing`（钳到 −10–50），外加 `TabStop` 默认 True、`Align`、`Anchors`、`ParentFont`。
- 4 期再加：`SelectionOverrideKey`、`Osc52`、`WordSeparators`、`CopyOnSelect`、`DetectUrls`；5 期：`MinimumContrastRatio`。后加 published 属性不破坏已有的 `.lfm`。
- 运行时只读本期只有 `Core`、`Cols`、`Rows`、`Title`；`SelectionText`、`HasSelection` 在 4 期。
- published 默认值 = 构造值由本控件自己的 RTTI 测试逐个守（全局守卫只查 `TabStop`）。

### 9.2 事件

| 事件 | 签名 | 何时 |
|---|---|---|
| `OnData` | `(Sender; const AData: RawByteString)` | 键盘 / 鼠标 / 粘贴 / 焦点 / 核心应答要发给程序 |
| `OnGridResize` | `(Sender; ACols, ARows: Integer)` | 格子数变了（宿主改 PTY 大小）；加载完成后的第一次也发 |
| `OnTitleChange` | `(Sender; const ATitle: string)` | OSC 0 / 2 |
| `OnBell` | `(Sender)` | BEL；控件自己不响不闪 |
| `OnLinkActivate` | `(Sender; const AUri: string; AFromOsc8: Boolean)` | Ctrl+单击链接（macOS 是 Cmd+单击） |
| `OnOsc52` | `(Sender; AWrite: Boolean; const ASelection: string; var AText: string; var AAllow: Boolean)` | OSC 52，按 `Osc52` 策略过滤后再问宿主 |
| `OnOsc` | `(Sender; AIdent: Integer; const AData: string; var AHandled: Boolean)` | 核心不处理的 OSC（§7.4） |
| `OnSelectionChange` | `(Sender)` | 选区变了 |
| `OnShortcutQuery` | `(Sender; Key: Word; Shift: TShiftState; var APassToApplication: Boolean)` | 终端要吞这个键之前问一次（§9.4） |

**实现期修正（3 期）**：~~`OnOsc` 带 `var AHandled`~~ `OnOsc(Sender, AIdent, AData)`，和 Core 同签名（§7.4：Core 对未处理的 OSC 没有默认动作）。本期有 `OnData`、`OnGridResize`、`OnTitleChange`、`OnBell`、`OnOsc`、`OnShortcutQuery` 六个；`OnLinkActivate`、`OnOsc52`、`OnSelectionChange` 在 4 期。

### 9.3 公开方法

`Write`（两个重载，转 `Core.Write` 并负责排片）、`WriteSync`、`Paste(const AText)`（走粘贴编码）、`Input(const AText)`（当作键入）、`Clear`（清滚回）、`Reset`、`ScrollLines` / `ScrollPages` / `ScrollToTop` / `ScrollToBottom`、`SelectAll` / `ClearSelection` / `Select(ACol, AAbsRow, ALength)` / `SelectLines`、`CopyToClipboard` / `PasteFromClipboard`、`CellAt(X, Y): TPoint`、`CellRect(ACol, ARow): TRect`。

**实现期修正（3 期）**：
- 新增 `SizeForGrid(ACols, ARows): TSize`：给定网格要多大的客户区（内边距、条宽都算进去）；示例「按录制尺寸」和想固定 80 × 24 的宿主用它。
- `CopyToClipboard` 本期是空操作（没有选区）；`SelectAll` / `ClearSelection` / `Select` / `SelectLines` 和选区一起在 4 期。
- Core 加了 `DiscardPending`：丢掉还没解析的块、不调它们的回调（宿主自己要丢的，流控计数跟着重来；上游 `WriteBuffer` 没有）。回放示例换录制时用。

### 9.4 键盘

- **顺序**：LCL 先调控件的 `KeyDown`（`KeyDownBeforeInterface` → `KeyDown`，`lcl:include/wincontrol.inc:5750-5753`、调用点 `:5883`），**之后**才查窗体和菜单快捷键（`:5888`）、再走 Tab 导航（`DoRemainingKeyDown`，`:5922-`）。所以控件在 `KeyDown` 里把 `Key` 清零，就压过了窗体上的 Ctrl+C、Tab 切焦点。
- **终端吞哪些键**：`TyTerminalEvaluateKey` 有结果的键都吞，包括 Tab、Shift+Tab、Esc、方向键、F1–F12、Ctrl+字母。
- **放行**：吞之前发 `OnShortcutQuery`，宿主把 `APassToApplication` 设成 True 的键保持原样往下走（窗体快捷键、Tab 导航照常）。默认什么都不放行（§17 问题 6）。
- **复制粘贴快捷键**：Windows / Linux 上 Ctrl+Shift+C / Ctrl+Shift+V、Ctrl+Insert / Shift+Insert；macOS 上 Cmd+C / Cmd+V。Ctrl+C 不劫持（它是中断）（§17 问题 5）。
- **本地翻页**：Shift+PgUp / PgDn 翻滚回（`Keyboard.ts:207-225`），Shift+Home / End 到顶 / 到底（定稿时新加）。
- 用户键入时，若视口不在底部且 `ScrollOnUserInput`，滚回底部（`CoreService.ts:80-84`）；有选区就清掉（上游挂在「用户输入」事件上，`xterm:src/browser/services/SelectionService.ts:139-143`）。

**实现期修正（3 期）**：
- ~~`TyTerminalEvaluateKey` 有结果的键都吞~~ 能出字符的键（无修饰、keyCode ≥ 48 且 `key` 恰一个 UTF-16 单元，外加空格）在 `KeyDown` 里**不发、不清零**，等字符事件：键盘布局只有 widgetset 知道，而 Win32 上 `KeyDown` 清零会吞掉随后的 `WM_CHAR`（`lcl:interfaces/win32/win32callback.inc`）。上游同样把这些键留给 keypress（`Keyboard.ts:365-368`、`CoreBrowserTerminal.ts:898-903`）。
- `KeyDown` 已经发了字节的键，控件自己记 `FKeyDownHandled`，`UTF8KeyPress` 见到就丢（上游 `_keyDownHandled`），不靠 widgetset 的行为；`KeyUp` 也清零——字符没来（widgetset 不送），不能让它吞掉下一个键的字符。
- `tkrSelectAll`（macOS Cmd+A）本期不算动作、不吞：选区在 4 期。
- Shift+Home / Shift+End 保留「到顶 / 到底」，是和上游不同的本地动作（上游这两个键照常发给程序），进 §15，真机验收看 PSReadLine / nano 里的取舍。
- 带 Ctrl / Alt / Meta 打出来的字符，除非是第三层 Shift，都不发（`CoreBrowserTerminal.ts:980-985`）；控制字符只可能是 `KeyDown` 处理过、widgetset 又送来的那一份，丢掉。

### 9.5 鼠标

#### 9.5.1 坐标

格子 = (像素 − 内边距) 整除单元格尺寸，钳在网格内（上游先把坐标钳到画布内再除，`xterm:src/browser/services/MouseCoordsService.ts:38-44`）。
1016 的像素坐标报**设备像素**；上游报 CSS 像素（同处 `:43-44`）。100% 缩放下两者一样，高 DPI 下不同——记进 §15。

#### 9.5.2 谁拿鼠标

| 情况 | 按下 / 拖动 / 抬起 | 滚轮 | 右键 |
|---|---|---|---|
| 程序没接管（协议 NONE） | 本地选择 | §9.5.4 | 弹控件菜单 |
| 程序接管，没按覆盖键 | 上报给程序（按协议过滤，§7.5） | 协议含滚轮就上报，否则 §9.5.4 | 上报给程序 |
| 程序接管，按着覆盖键 | 本地选择，不上报（上游同，`MouseService.ts:224-235`、`SelectionService.ts:437-447`） | 同上一行 | 弹控件菜单（定稿时新加，§17 问题 8） |

- 覆盖键 = `SelectionOverrideKey`（§9.1）。上报时覆盖键本身不算进修饰位——只有它是 Alt 时要剥掉；上游的 `mouseEventsRequireAlt` 有同样的剥法（`MouseService.ts:166-190`）。
- 上报期间用 LCL 鼠标捕获，拖出控件照样上报（上游在按下后挂 document 级监听，`MouseService.ts:240-249`）。
- 按键：左 / 中 / 右三键；第 4、5 键不报（上游 `but > WHEEL` 直接丢，`:162-164`）。
- 修饰键：Shift / Alt / Ctrl 照事件码（`MouseStateService.ts:85-89`、`:92`）。

#### 9.5.3 滚轮上报

- 竖向：LCL `DoMouseWheel`，累计 `WheelDelta` 到 ±120 为一格，每格上报一次（上游按像素累计行数，`MouseService.ts:454-490`；我们按 LCL 的「格」换算，定稿时新加）。
- 横向：LCL `DoMouseWheelHorz`（`lcl:controls.pp:1537`）按 `WheelDelta < 0` 分到 `DoMouseWheelLeft`、否则 `DoMouseWheelRight`（`lcl:include/control.inc:2407-2409`；两个虚方法 `controls.pp:1538-1539`），控件覆盖这两个，报 `WHEEL` + `LEFT` / `RIGHT`（事件码 66 / 67）——我们加的（§1.1 第 3 条）。

#### 9.5.4 滚轮不上报时

- 缓冲**有滚回**：滚视口，每格 3 行（同 `TTyMemo`，`Memo.pas:2769-2789`）。
- 缓冲**没有滚回**（备用屏，或 `Scrollback = 0`）且 `AlternateScroll`：每格发一个上 / 下方向键，按应用光标模式选 `ESC O A` / `ESC [ A`（`MouseService.ts:262-290`）。
- 这就是「1007」的行为，但做成属性、**不认** DECSET 1007——上游不认（§1.1 第 2 条），认了的话 DECRQM 1007 的应答就和上游不一致（§17 问题 7）。

**实现期修正（3 期）**（§9.5.3、§9.5.4）：
- 本期只做竖向滚轮；横向（`DoMouseWheelLeft/Right`）在 4 期。
- 每满 ±120 出一格，同号的余数留着，方向反过来时余数清零；一格都不满也算处理了（吃掉这点位移）。宿主的 `OnMouseWheel` 先拿，它处理了就到此为止。
- Shift+滚轮照上游：不上报、不发方向键（`MouseService.ts:459` 的 `_consumeWheelEvent` 对 shiftKey 答 0 行）；滚回在 Windows / Linux 上是横滚（`scrollableElement.ts:394`，终端没有横向可滚，事件交还父控件），macOS 上照常竖滚。
- 上报的像素坐标钳在网格里（0 到 列数 × 格宽 − 1，行同理；上游钳到画布宽高 − 1，`MouseCoordsService.ts:38-39`），格子由 `CellAt` 钳。

#### 9.5.5 本地选择

- 单击拖动：按字符选；双击选词（`WordSeparators`，`SelectionService.ts:1034-1041`）；三击选整行，含折行的连续行（`getWrappedRangeForLine`，`:1047-1057`）。多击用 LCL 的 `ssDouble` / `ssTriple`（`csTripleClicks`，`lcl:controls.pp:306`）。
- Shift+单击扩展选区（程序没接管时；接管时 Shift 已经是覆盖键，按下即新选区——同上游）。
- Alt+拖动列选择（`SelectionService.ts:607-612`）；macOS 上 Option 是覆盖键时不做列选择（上游同一规则，`:611`）。
- 拖到控件上下边外面时自动滚动：离边越远越快，每 50ms 一次、每次最多 15 行、50 像素到顶速（`SelectionService.ts:26-34`、`:654-665`）。
- 选区锚在缓冲行上（标记，§6.2），新输出把行顶上去时选区跟着走（上游 `_handleTrim`，`:386-391`）；行被挤出滚回就清掉选区。
- 清选区的时机照上游：用户输入（上一节）、行数变化（`:157-162`）、程序打开鼠标上报（上游此时停用选择并清空，`:173-176`、`CoreBrowserTerminal.ts:621-624`；覆盖键仍可新选，`SelectionService.ts:471-478`）、切换主备屏。

### 9.6 选区与剪贴板

#### 9.6.1 复制

`SelectionText`：逐行 `TranslateToString(True, …)`；折行的行之间不加换行，其他行之间加 `LineEnding`（定稿时新加：上游浏览器层用 `\n`，Windows 上贴进记事本要 CRLF）。
剪贴板直接用 LCL `Clipbrd`（库里 `TTyEdit` / `TTyMemo` 也是，`Edit.pas:1841`、`:1846`），读写走两个 virtual 方法，测试可以替换（照 `Edit.pas:260-261`）。

#### 9.6.2 Linux PRIMARY

X11 惯例：选完写 `PrimarySelection`（`lcl:clipbrd.pp:236`），中键粘贴 PRIMARY（程序没接管鼠标时）。Wayland 下是否可用要真机（§16）。建议做（§17 问题 9）。

#### 9.6.3 OSC 52

控件注册 OSC 52 处理器，解析照 `ClipboardAddon._setOrReportClipboard`（`xterm:addons/addon-clipboard/src/ClipboardAddon.ts:32-`）：`Pc;Pd`，`Pd = ?` 是读，否则 base64 写。
- `Osc52 = to52Off`（默认）：丢弃，不问宿主。
- `to52Write`：写请求先发 `OnOsc52`（宿主可改文本、可拒绝），`AAllow` 默认 True；读请求丢弃。
- `to52ReadWrite`：读请求也发 `OnOsc52`，`AAllow` 默认 **False**（读剪贴板是隐私问题，宿主要显式同意）。

#### 9.6.4 右键菜单

实现 `ITyTextEditActions`（`source/tyControls.TextMenu.pas:25-45`），复用 `TTyTextEditMenu`（`:67`）：复制、粘贴、全选可用；剪切、撤销、重做灰掉（`TeIsReadOnly` 答 True，`TeCanUndo` / `TeCanRedo` 答 False）。另加「清屏」一项（定稿时新加；resourcestring）。设了 `PopupMenu` 就用它。

### 9.7 滚回与滚动条

- 自己建一根 `TTyScrollBar`，照 `TTyMemo`：`Parent := Self`、`Align := alRight`、`TabStop := False`、`csNoDesignVisible`、宽度取 `--scrollbar-size`、`AutoHide := ScrollBarAutoHide`（`Memo.pas:2384`、`:2410-2420`）。
- 实现 `ITyScrollBarFrameHost`（`source/tyControls.ScrollBar.pas:61-73`），滚动条替控件画外框那一段。
- `Max` 是**最大位置**不是内容高度：`Max = 缓冲行数 − 视口行数`（[[scrollbar-max-is-position-not-content]]）。
- 备用屏没有滚回，滚动条禁用~~（AutoHide 时藏起）~~；切回主屏恢复。
- 新输出到来：视口在底部就跟着走；不在底部就不动（上游同，`YDisp` 只在 `YDisp = YBase` 时跟随）。

**实现期修正（3 期）**：条宽**一直扣**——网格宽 = 客户区 − 内边距 − 条宽，备用屏里、`Scrollback = 0` 时条只是禁用、不拿掉（自动隐藏的主题下淡掉，留一条空白），列数不随主屏 / 备用屏变化，进出 vim 不会给程序多发一次改尺寸（开工前问题一第 2 条）。滚动条的同步在一次解析里只做一次（§3.2）。

### 9.8 链接

- 两种来源：OSC 8（缓冲里的链接号，§6.2）；`DetectUrls` 开时按行文本正则识别，正则照 `addon-web-links` 的 `strictUrlRegex`（`xterm:addons/addon-web-links/src/WebLinksAddon.ts:21`），用 FPC `RegExpr` 改写。期望值由 node 直接跑上游正则生成，输入取上游用例（`addons/addon-web-links/test/WebLinksAddon.test.ts:33-188`：各种顶级域名、全角字符前后、带用户名密码、组合字符）再加自己的。
- 悬停：按住 Ctrl（macOS Cmd）时，指针下的链接画下划线（`TyTerminalLink`），光标变手形。
- 激活：Ctrl+单击（macOS Cmd+单击）发 `OnLinkActivate`；控件自己不打开任何东西。上游 OSC 8 默认处理还会弹确认框（`OscLinkProvider.ts:183`），并默认拒绝非 http(s) 协议（`:64`）——这些是宿主的事，示例里演示。
- 程序接管鼠标时，Ctrl+单击仍然优先当链接（定稿时新加：不然全屏程序里的链接点不开）。

### 9.9 输入法

复用库内各 widgetset 的实现：
- 回调式（`TyImeInstall(Self, @HandleImeCommit, @GetImeCaretRect)`，`source/tyControls.PlatformWS.pas:115-133`；回调类型 `source/tyControls.Types.pas:18-19`），在 `InitializeWnd` 里装（照 `Edit.pas:2267`）。
- Win32 候选窗跟随用 `TySetImeCaretPos`（`PlatformWS.pas:132-133`）。
- macOS 实现 `ITyImeEditable`（`TextMenu.pas:52-61`），由 `TTyCocoaImeHandler`（`source/tyControls.CocoaWS.pas:35-47`）驱动。这个接口是给文本框设计的（`ImeReplace` 改文本、`ImeSessionBegin/End` 包撤销）；终端的实现把它们落在一个**本地组字串**上，不碰缓冲。
  handler 的两条路都以 `ImeReplace` 收尾、再跟 `IMESessionEnd`：组字中途换成新的标记文本、取消时换成空串（`CocoaWS.pas:74-81`），确认时换成提交文本（`:83-89`）。所以终端在 `ImeSessionEnd` 时把本地串整串经 `OnData` 发出、清空——取消时本地串已经是空的，自然不发。
- 候选窗位置 = **光标所在单元格**的矩形（设备像素，客户区坐标），光标行列变化时更新（Qt 要主动戳，照 `Edit.pas:2706-2710` 的做法）。
- 组字串画在光标处，用 `TyTerminalPreedit` 的颜色和下划线；占几格按 Unicode 宽度算，超出行尾就截断显示（不写进缓冲）。
- GTK3 没有候选窗定位（库内现状，`source/tyControls.Gtk3WS.pas:96-111` 只取回完整提交串），终端同样没有。
- 已知限制：LCL `TUTF8Char = String[7]`（`lcl:lcltype.pp:63`）会截断输入法提交串，库内各 widgetset 的钩子就是为绕开它；`UTF8KeyPress` 里仍要调 `TyImeTakeCommit`（照 `Edit.pas:2210`）。

**实现期修正（3 期）**：
- 输入法从 4 期挪到 3 期（开工前问题二第 2 条）：提交通路、候选窗定位、macOS 组字串都在本期，真机验收期末一次。
- 候选窗锚在**光标所在的屏幕行**的格子上（宽字符不扩）；视口不在底部时仍按光标行算——候选窗跟光标，不跟视口。锚是上一帧画出来的那个格子（用这一帧的度量）；没聚焦、没句柄、还没画过一帧时答空矩形。
- Win32：系统候选窗的位置按线程记，在别的控件里打过字就被挪走——所以照 `Memo.pas:4464` **每帧**都设 `TySetImeCaretPos`（聚焦时），聚焦的那一刻作废缓存的锚并先按上一次的格子设一次。
- macOS：照 `Edit.pas` 接 `TTyCocoaImeHandler`——构造时建（LCL-Cocoa 在建句柄时发 `LM_IM_COMPOSITION` 问），消息里答它；`ImeCaretBoundClient` 答和候选窗同一个矩形。不在组字会话里时 `ImeReplace` 就是一次提交（LCL-Cocoa 对死键不开会话直接调 `IMEInsertFinalText`，后面不跟 `IMESessionEnd`），当场发出、不留在组字串里，会话结束也不会再发一遍。未在真机上跑过。
- 组字时不滚到底（上游输入法按键时会滚，`CoreBrowserTerminal.ts:857-861`；组字串画在光标行上，视口在别处就看不见；进 §15，真机验收看要不要补）。

### 9.10 焦点、光标闪烁、设计期

- `DoEnter` / `DoExit`：`Core.ReportFocus`；重画光标（聚焦时实心，失焦按 `CursorInactiveStyle`）。
- 闪烁：懒建 `TTimer`（照 `Edit.pas:574-590`），周期 600ms（上游 WebGL 渲染器的值，`addons/addon-webgl/src/CursorBlinkStateManager.ts:13`）；5 分钟没有输入输出就停在「显示」（上游 `CURSOR_BLINK_IDLE_TIMEOUT`，`src/browser/renderer/shared/Constants.ts:12`）。每次只标光标所在行脏。
- 设计期（`csDesigning`）：不建计时器、不建滚动条；画几行示例文字，覆盖 16 色和粗体 / 下划线，方便在设计器里看主题效果。

**实现期修正（3 期）**：
- Core 出生时 `Focused = True`，控件构造里马上 `ReportFocus(False)`，一个没焦点的终端在程序打开 1004 时报「没有焦点」。
- ~~`DoEnter` / `DoExit`：`Core.ReportFocus`~~ 焦点跟**系统焦点**：`LM_SETFOCUS` / `LM_KILLFOCUS`（切到别的程序也算失焦）和 `DoEnter` / `DoExit` 都进同一个入口，重复的一路什么都不做；驱动 1004 报告、光标形状（失焦样式）和闪烁计时器。上游看的是 textarea 的 focus / blur，也就是系统焦点。
- 点击取焦点：哪个键点下去都取（中键、右键也是在跟终端打交道；基类只认左键），同基类守着 `TabStop`、`SetFocus` 包 `try … except`。
- 悬停、按下、聚焦时基类整控件失效：外框样式（含状态）没变就不重贴整张表面，变了才重画外框（连同各行）。

---

## 10. 渲染

### 10.1 管线

- 控件持有一张**视口大小的行缓存位图**（`TBGRABitmap`，不透明）。
- 脏行（§3.2）重画进缓存：先铺每格底色（含选区、反显），再画字形，再画下划线 / 删除线 / 上划线，最后画光标。
- `Paint` 只把缓存的无效区贴到画布（`Draw(..., Opaque = True)`）。不用 `TTyPainter` 每帧新建整张位图（`source/tyControls.Painter.pas:1301`）——外框、滚动条角落这些仍走 `TTyPainter`。
- 缓存不经 `TBitmap` 中转；万一要中转，用 pf24bit（[[opaque-device-cache-pf24bit]]：pf32bit 在 GTK2 上整块黑）。
- 5 期：整屏上滚时先把缓存内容整体上移，只画新露出的行。

**实现期修正（3 期）**：
- ~~视口大小的行缓存位图~~ 一张**客户区大小**的表面位图（外框 + 内边距 + 网格）：外框和内边距只在主题、尺寸、颜色、外框状态变化时经 `TTyPainter.BeginPaintOn` 画一次，脏行直接画进网格区，`Paint` 只贴画布的裁剪区。位图按 64 像素的块向上取整、只长不缩：拖着改尺寸不每次重建。
- 贴图（本批）：Win32 从位图的 DIB 带源偏移直接 `StretchDIBits`，不经 `GetPart` 复制一份；别的 widgetset 仍走 BGRA 的 `DrawPart`（零拷贝的路子要各平台真机核实）。构造里 `DoubleBuffered := False`：整面都是贴上去的，LCL 的双缓冲再垫一张整窗位图只是多拷一遍。悬停、按下、聚焦的整控件失效只在外框样式变了时才放行（§9.10）。
- 禁用时整块按 `TyTerminal:disabled` 的 opacity 朝父控件底色预混（色表、外框、内边距，§11）。

### 10.2 单元格度量

- 字号 → 像素：`TyFontHeightPx(Size, PPI)`（`Painter.pas:1174` 同一换算）。
- 格宽：量 32 个 `W` 的总宽除以 32（上游量 `W`，`xterm:src/browser/services/CharSizeService.ts:86`、`:115`），向上取整到整数设备像素，再加 `LetterSpacing`（按 DPI 缩放）。整数格宽保证网格对齐。
- 格高：BGRA 字体度量的 `Lineheight`（`bgra:bgrabitmaptypes.pas:412-425`）× `LineHeightPercent`，向上取整；基线取同一记录的 `Baseline`。
- 格子数 = (客户区 − 内边距 − 滚动条) / 格尺寸，向下取整；变了就 `Core.Resize` + `OnGridResize`。

**实现期修正（3 期）**：
- Win32 实测（E1，Consolas 9 / 12 pt × 96 / 144 PPI）：`Lineheight` = `TextSize('Ag').cy` = CJK 字的 `TextSize` 高，格高 14 / 22 / 19 / 28 像素，CJK 的墨迹都在格内；度量没定义时退到 `TextSize('Ag').cy`。
- 字号、字体、DPI、主题任一变了都立即重排：`Font` 改了（`FontChanged` / `CM_PARENTFONTCHANGED`）马上排；谁问出来的度量变了（`CellRect`、`CellAt`、`SizeForGrid`、14t 应答）也排——查询不吞掉「格子变了」这个信号；在绘制里只记下，经 `QueueAsyncCall` 延后。

### 10.3 字体

**来源**（§17 问题 3）：主题键 `TyTerminal` 的 `font-family` / `font-size`；实例覆盖按「字体覆盖通道」需求（`docs/superpowers/specs/2026-09-20-font-override-channel-requirements.md`）的规则在本控件就地实现：`ParentFont = False` 时，`Font.Name` / `Font.Size` 不等于出厂值的字段生效。那个需求落地后并进公共 helper。

**`monospace` 关键字**：`--terminal-font-family` 默认写 `monospace`，控件把它换成平台等宽字体（Windows `Consolas`、Linux `Monospace`、macOS `Menlo`，定稿时新加）。GDI 不认 `monospace` 这个名字，不换就落到非等宽的默认字体。

**库内现状（已核实）**：
- `TyConfigureTextFont` 只设粗体，不设斜体（`Painter.pas:1189`）；主题引擎也没有 font-style。终端的斜体由渲染器自己设 BGRA `FontStyle`。
- **没有逐字形的字体回退**。空字体名才回退到 `TyFallbackFontName`（`Painter.pas:704-710`）。Qt / GTK / Cocoa 上用 `fqSystemClearType`，走系统自己的字体替换；Win32 用 `fqFineAntialiasing`（BGRA 自己的 3× 超采样，`Painter.pas:1184-1188`），GDI 会不会替 CJK 找字形没有证据。
- macOS 上系统替换进来的高字形会被 BGRA 的遮罩切掉下半截，库里靠把 `TyFallbackFontName` 设成 PingFang SC 解决（`source/tyControls.Controller.pas:228`；[[bgra-small-text-blur-linux]] 的 UPDATE-2）。

所以**开工前（3 期第一步）要做两个小实验**：

- **E1 字体回退**：在 Win32 / Qt6 / GTK2 / Cocoa 上，用平台等宽字体各画一行 ASCII + 中日韩 + 韩文 + 表情 + 制表符 + Powerline 字符，看有没有字形、宽度多少、有没有被截。
  - 都有：直接用系统替换。
  - 缺 CJK：加一个 token `--terminal-font-family-wide`，**宽度为 2 的簇**一律用它画（规则简单、跨平台一致）。
  - 缺表情：记成已知限制（BGRA 大概率画不出彩色表情，E1 顺带确认）。
- **E2 字形遮罩**：比较两种做法的画质和耗时——（a）`fqSystem` 灰度、3× 超采样后缩小，存成 alpha 遮罩，着色时贴；（b）`fqSystemClearType` 直接画在已知底色上，缓存键带前景 + 底色。量「填满 95 个 ASCII × 4 种样式」的时间和「200×60 全屏重画」的时间。
  - 默认选（a）：缓存键不带颜色，命中率高；Linux / macOS 小字发虚（[[bgra-small-text-blur-linux]]）正好由超采样治。
  - 超采样的代价（每个字形 9 倍面积光栅化 + 重采样，`Painter.pas:2102-2143`）只在**第一次**画某个字形时付，之后命中缓存。终端的字形集合小、重复率高，这是缓存让超采样付得起的原因。

**实现期修正（3 期）**，E1（Win32 已跑，`tools/terminal-fontprobe --e1`）：
- Consolas 经系统字体链接把中文、日文假名画在格子里：前进宽度正好 2.00 格，墨迹不出格、不被截；韩文 1.3–1.5 格、U+20000 1.7–2.1 格（照样按 2 格画，比格子窄的居中不动）。所以 Windows 上 `monospace-wide` 换成**空串**（交给系统替换）。候选宽字体 Microsoft YaHei 反而在 9 pt 下让 U+20000、表情的墨迹出格，不用。
- 表情：有字形，但只有单色轮廓（GDI 文字管线不画彩色字形）——已知限制，§15 保持「彩色表情不做」。
- Powerline（U+E0A0、U+E0B0）：Consolas 缺字（无墨），5 期定是否自绘。
- 框线、块元素：字体的字形上下都出格（本来就自绘，§10.5）。
- macOS / Linux 没在真机上跑：`monospace-wide` 先按证据给 `PingFang SC` / `Noto Sans CJK SC`，进真机验收。

E2（Win32 已跑，`--e2`；数字是本批修复后重跑的）：
- ~~默认选（a）~~ 选**做法（c）**：库自己的文字管线在 1× 下黑字白底画一遍，覆盖率 = 255 − 灰度（通道平均），缓存不带颜色，着色时用和 `TTyGdiTextRenderer` 同一个非伽马混合。（a）在 Win32 上把用户否掉的「虚」带回来（实心占比 0.3% / 8.5%，参照 12.4% / 21.0%），不选。
- 画质：（c）对参照（`TTyPainter.DrawText` 同底色同前景）的有墨像素平均差 0.19–0.43（每通道 0–255，三组颜色、96 / 144 PPI）；同一遮罩换成 BGRA `FillMask` 的伽马混合（`dmDrawWithTransparency`）差 15.8–27.0。自写混合循环和 `FillMask` 线性混合结果相同、快约 2.5 倍（200 × 60 整屏 7.6 对 20.0 ms、144 PPI 13.9 对 32.3 ms）。
- 耗时（控件自己的光栅器和行绘制器）：冷填充 95 个 ASCII × 4 种样式 380 次约 710 ms（每个 1.87 ms，96 / 144 PPI 相同；花在库的 Win32 文字渲染器每次新建位图再转换上，`Painter.pas`）；热缓存 200 × 60 整屏重画（只画行，不贴）96 PPI 10.1 ms、144 PPI 16.4 ms，满屏 tmux 框线同样 10.0 / 16.4 ms。控件里连贴图的整屏重画 11.8 ms（ASCII、tmux 框线、mc 双线框都在 12 ms 左右；修复前框线靠每格两张整面剪裁遮罩，tmux 2.5 s、mc 5.3 s）。冷填充在控件里按帧摊开（§3.2 的光栅化预算），380 个字形约 900 ms、68 帧，每帧不超过预算。

### 10.4 字形缓存

- 键：簇的 UTF-8 串 + 粗体 + 斜体 + 占格数（1 / 2）+ 用哪个字体（主 / 宽）。颜色不进键（按 E2 的（a））。
- 值：alpha 遮罩（8 位）和它相对格子左上角的偏移。字形比格子宽时水平压缩进格子（上游 `rescaleOverlappingGlyphs` 的思路，`typings/xterm.d.ts:234-249`）；比格子高时不压、按格子裁。
- 容量：4096 项，满了按最近最少使用淘汰（定稿时新加）。字体、字号、DPI、`AmbiguousWide` 变了整个清空。
- 空格和空格子不进缓存。

**实现期修正（3 期）**：
- 键里不含颜色（E2 选了（c））。一格的可打印 ASCII 走快速路径：按码位、粗体、斜体直接查一张 380 项的表，不拼键串。
- 光栅化出来没有墨的字形（零宽空格之类）照样缓存（遮罩为空），~~不进缓存~~ 只有空格和空格子不进。
- 本批：单个码位（非 ASCII、非组合）用 64 位整数键（码位、粗体、斜体、占格数、字体），不每格每帧拼字符串；只有多码位的簇和输入法的组字串用字符串键，格数单独占两个字节编码（原来和标志挤在一个半字节里，1 格和 17 格撞键）。
- 本批：自绘字形（§10.5）也进同一个缓存，键 = 码位、占格数、格宽、格高、PPI，阴影图案 ░▒▓ 另加相位（格子左上角对图案周期取模，图案从表面原点铺）。

### 10.5 自绘字形

制表符（U+2500–257F）和块元素（U+2580–259F）不用字体画，按单元格几何自己画，保证相邻格连成线（上游 WebGL 渲染器默认这么做，`addons/addon-webgl/typings/addon-webgl.d.ts:54-75`；定义表 `addons/addon-webgl/src/customGlyphs/CustomGlyphDefinitions.ts`，MIT，可移植数据）。3 期做这两段；盲文、Powerline、Legacy Computing 5 期再定。

**实现期修正（3 期）**：
- 路径坐标取整后**只裁不钳**：上游对这些字形传 `clampToCell = false`（`CustomGlyphRasterizer.ts:734`），画出格的部分按格子裁掉。
- 本批：每个自绘字形只画一次——白色画在比格子大一圈的透明小位图上、Canvas2D 裁到格子，alpha 就是覆盖率遮罩，进字形缓存（§10.4）；着色时用 Canvas2D 画形状的同一个伽马混合（全覆盖直接是那个颜色）。原来直接在表面上画、每格两张整面大小的剪裁遮罩。和直接画比：全部 160 个字形 × 两种格子 × 两种 PPI × 两种底色里，0.03% 的像素差 1（一个字形两段笔画重叠的半覆盖像素，原来混两次、现在合成一次再混），其余逐像素相同。

### 10.6 属性

| 属性 | 画法 |
|---|---|
| 颜色 | 默认色 / 16 色 / 256 色 / RGB。0–15 取主题（§11），16–255 按上游公式算（6×6×6 立方 + 24 级灰，`xterm:src/browser/Types.ts:205-227`），覆盖表优先（§7.3） |
| 粗体 | 粗体字形；`DrawBoldTextInBrightColors` 时 0–7 色换 8–15 |
| 暗淡 | 前景和底色按 50% 混合（定稿时新加；上游 DOM 渲染器用透明度，效果同） |
| 斜体 | 斜体字形 |
| 下划线 | 单线、双线、波浪、点线、虚线；下划线颜色有就用（SGR 58） |
| 删除线 / 上划线 | 线 |
| 反显 | 前景底色互换 |
| 隐藏 | 不画字形 |
| 闪烁（SGR 5） | 不闪，照常画（上游默认 `blinkIntervalDuration: 0` 也不闪，`OptionsService.ts:17`） |
| 线宽 | 按 DPI 缩放，至少 1 设备像素 |

**实现期修正（3 期）**：
- 下划线的默认颜色是**暗淡处理之后**的前景（`DomRendererRowFactory.ts:313-320`）；调色板下划线色在粗体且小于 8 时同样加 8。
- 下划线（点、虚、波浪）按整段画，图样按**绝对 x** 定相位，跨格连续；阴影 ░▒▓ 同样按表面原点铺。
- 隐藏（SGR 8）的格子在块光标下也不露字（上游把隐藏的格子当空格画，`DomRendererRowFactory.ts:302-306`）。

### 10.7 光标

块 / 下划线 / 竖线（竖线宽取 `--terminal-cursor-width`）；失焦时按 `CursorInactiveStyle`，轮廓 = 1 像素框。块光标下的字用 `TyTerminalCursor` 的 `color` 重画。光标隐藏（DECTCEM）或视口不在底部时不画。

### 10.8 DPI

PPI 取 `Font.PixelsPerInch`（全库约定）。PPI 变化：重算度量、清字形缓存、重算格子数（会触发 `OnGridResize`）。

### 10.9 最低对比度（5 期）

`MinimumContrastRatio > 1` 时，前景对底色对比度不够就把前景往亮或暗推，照 `ensureContrastRatio`（`xterm:src/common/Color.ts:296-`），结果按（前景，底色）缓存（上游 `ColorContrastCache.ts`）。

---

## 11. 主题

**类型键**（都写在 `themes/light.tycss` 基础层，皮肤经基础层继承；不借别的键，[[borrowed-typekey-unreachable]]）：

| 键 | 用途 |
|---|---|
| `TyTerminal` | `background` = 默认底色；`color` = 默认前景；`font-family`、`font-size`；`padding` = 内边距；`border-*` = 外框（默认无）；`:focused` `:disabled` |
| `TyTerminalCursor` | `background` = 光标色；`color` = 块光标下的字色 |
| `TyTerminalSelection` | `background` = 选区底色（可带透明度，叠在格子底色上）；`color` = 选区前景，**写了才用**（上游 `selectionForeground` 可选，`ThemeService.ts:91-95`）；`:focused` = 聚焦时，无状态 = 失焦时 |
| `TyTerminalAnsi0` … `TyTerminalAnsi15` | `color` = 调色板第 n 色（照 `TyChartSeries1..8` 一色一键的先例，`themes/light.tycss:1155-1167`） |
| `TyTerminalLink` | `color` = 链接下划线色 |
| `TyTerminalPreedit` | 输入法组字串：`background`、`color`、`border-color`（下划线） |

**颜色 token**（light.tycss 默认值；皮肤调 token 不写规则，[[variant-dies-under-skin-base-rule]]）：

| token | 默认 |
|---|---|
| `--terminal-bg` | `var(--surface)` |
| `--terminal-fg` | `var(--on-surface)` |
| `--terminal-cursor` | `var(--on-surface)` |
| `--terminal-cursor-ink` | `var(--terminal-bg)` |
| `--terminal-selection-bg` | `alpha(var(--accent), 0.35)` |
| `--terminal-selection-bg-inactive` | `alpha(var(--on-surface), 0.18)` |
| `--terminal-link` | `var(--accent)` |
| `--terminal-ansi-0` … `--terminal-ansi-15` | `on(var(--terminal-bg), <浅底色>, <深底色>)` |

- 16 色用 tycss 的三参数 `on(底, 浅底用, 深底用)`：底色亮度 > 0.5 取第二个参数，否则第三个（`source/tyControls.Css.Values.pas:177-180`）。所以**只写基础层一处**，17 个主题的明暗两种模式、以及用户把 `--terminal-bg` 改深改浅，都自动选对那一套。
- 深底那套用 xterm.js 默认色（Tango，`xterm:src/browser/Types.ts:183-203`）。浅底那套要另配（§17 问题 4）。
- `TyTerminalLink` 取 `--terminal-link`；`TyTerminalPreedit` 背景 / 前景取 `--terminal-bg` / `--terminal-fg`、下划线取 `var(--accent)`，不另设 token。
- 底色只引用皮肤已经定义的 surface token，不自己写 `darken(--surface, …)`（[[skin-must-define-derived-tokens]]）。

**长度 token**（密度块，modern 值写进 DensityPack）：`--terminal-pad`（内边距）、`--terminal-cursor-width`（竖线光标宽，默认 1px，上游 `cursorWidth: 1`，`OptionsService.ts:19`）、`--terminal-underline-width`。

**字体 token**：`--terminal-font-family`（默认 `monospace`，§10.3）、`--terminal-font-size`（默认 `var(--font-size-base)`）；E1 需要时加 `--terminal-font-family-wide`。

改完：跑 `scripts/gen-defaulttheme.ps1`（先验忠实度，[[gen-defaulttheme-eats-handwritten-code]]）、`scripts/gen-tycss-catalog.ps1`；键和 token 加进 `tests/test.themes.pas` 的 GGRID（`:591`）/ GMETRICS（`:681`），重铺 golden；加一条跨 17 个主题 × 明暗的 resolve 测试，断言 16 色都解析得出；浅底那套（我们配的）断言对白底对比度达到 §17 问题 4 的标准，深底那套照搬上游、只记录不断言（Tango 的 0 号 `#2e3436` 在纯黑底上只有约 1.7:1，这是上游的设计，不是我们的错）。

**实现期修正（3 期）**：
- ~~`:focused`~~ 主题的聚焦伪类叫 `:focus`（`Css.Parser.pas`），`TyTerminalSelection:focus` 是聚焦时的选区。
- ~~`font-family`、`font-size` 写在 `TyTerminal` 规则里~~ `font-family` 不经 `var()` 求值（`StyleModel.pas` 直接存原文），所以基础层规则**不写** `font-family`，控件自己 `RawVar('--terminal-font-family')` 读 token；`TyTerminal` 规则里写了 `font-family` 的皮肤照样生效（顺序见 §10.3）。~~`--terminal-font-size`~~ 删掉：字号走 `font-size: var(--font-size-base)`，跟着密度，皮肤要单调就写 `TyTerminal` 的 `font-size`。
- 三参数 `on()` 看的是 **Rec.601 亮度**（> 0.5 取第二个参数，恰好 0.5 算深，`Css.Values.pas`），不是 WCAG 相对亮度。
- 浅底 16 色实际值（`tools/terminal-oracle/light-palette.js` 用上游 `ensureContrastRatio` 对白底 4.5:1 算出，`--check` 守着 `light.tycss`）：1 `#cc0000`、2 `#3f7c04`、3 `#8e7400`、4 `#3465a4`、5 `#75507b`、6 `#047a7c`、9 `#d72424`、10 `#50831c`、11 `#756d24`、12 `#517396`、13 `#8b6687`、14 `#1c8383`；0 / 7 / 8 / 15 照 Tango。
- `:disabled` 用 opacity：本批实现——禁用时色表（259 色）、光标下的字色、外框底色和边框色都按 `TyTerminal:disabled` 的 opacity 朝父控件底色预混，缓存键里有 `Enabled`；程序问颜色（OSC 10 / 11）答的仍是原色。注意皮肤若改写了 `TyTerminal` 规则，基础层的 `:disabled` 不再继承（皮肤层按键整条覆盖），要连 `:disabled` 一起写。
- 浅底对比度：公式对**白底**达标（最差 3 号 4.52:1）；落到各皮肤实际的 `--surface` 上，3 号色最差 xp 3.70、macos 3.82、breeze 3.96、office 4.04、win10 4.07、showcase 4.12、material3 / ubuntu 4.33。主控决定暂按（c）维持现状，交 5 期 `MinimumContrastRatio` 兜底；最终验收时用截图请用户在（a）以最暗浅底重算、（b）终端底色改用更白的 token、（c）维持 三者中定（§17.1 第 4 条）。

---

## 12. 示例 `examples/terminal`

### 12.1 形态

照库内示例规矩（[[examples-must-be-lfm-titlebar-skin]]）：`TTyForm` + `.lfm` + 真 `TTyTitleBar` + 运行时换肤、明暗切换（模板 `examples/memo/umain.pas`：`:28-29`、`:98-130`）。

- **回放**：打开录制文件，按原节奏 / 加速 / 一次喂完播放；`ReadOnly = True`。录制格式建议 asciicast v2（每行一个 JSON：头部含宽高，事件 `[时间, "o", 数据]`；本机没有 asciinema 源码可核，格式以其官方文档为准，§17 问题 11）。示例自带几段录制（`examples/terminal/recordings/`）。3 期另加一个「键码面板」：把 `OnData` 的字节以十六进制列出来，回放模式下验键盘编码。
- **真 shell**（4 期）：Windows 起 `cmd` / `powershell`，Linux / macOS 起 `$SHELL`；菜单里可以改命令行。
- 菜单：打开录制、回放速度、新建 shell、复制 / 粘贴、字号、Unicode 版本、ambiguous 宽度、OSC 52 策略、换肤、明暗。

**实现期修正（3 期）**，示例实际的样子（`examples/terminal`，本期只有回放）：
- ~~菜单~~ 两排工具条代替菜单：录制下拉（`recordings/` 里的文件）、打开…、播放 / 暂停、单步、速度（0.5× / 1× / 2× / 4× / 一次喂完）、按录制尺寸；只读、本地回显、Unicode 版本、歧义字符算宽、字号、粘贴。标题栏里换肤下拉和暗色开关。右侧键码面板（`TTyMemo`，按键的十六进制和可读写法，只留最近 1000 行），中间分隔条，底部状态栏（进度、网格尺寸、标题）。新建 shell、复制、OSC 52 策略在 4 期。
- 录制拷进示例自己的 `recordings/`（2 期的 8 份 + 16 色样例 `palette.cast`），发布包自成一体；发版守卫查两处同名文件字节相同。
- 回放带流控：一次只让一块在终端队列里，写回调到了再写下一块，「一次喂完」按 64 KB 一块喂，不会撑爆队列；写入失败就停播放、只提示一次。换录制时先 `Core.DiscardPending` 丢掉旧录制还没解析的数据，不先同步解析完。读录制先解析到局部、成功才替换，失败保留原来的；头部宽高钳到 2–500 × 1–300；照 `idle_time_limit` 缩短长停顿。
- 「按录制尺寸」经 `SizeForGrid` 算出客户区，窗口按差值放大缩小（原样再设同一矩形是空操作）。

### 12.2 PTY 单元（只在示例里）

| 单元 | 平台 | 要点 |
|---|---|---|
| `uptywin.pas` | Windows | ConPTY：`CreatePseudoConsole` / `ResizePseudoConsole` / `ClosePseudoConsole` 从 kernel32 **按名动态加载**——FPC 3.2.2 的 Windows 单元没有声明（`fpc:` 下 grep 不到 `CreatePseudoConsole`）；取不到就提示「本机不支持 ConPTY」。两条匿名管道 + `STARTUPINFOEX` 的伪控制台属性起进程 |
| `uptyunix.pas` | Linux / macOS | `forkpty` 自己声明 `external`（Linux 在 libutil，macOS 在 libc）——FPC 3.2.2 只有已废弃的 `libc` 包声明过（`fpc:packages/libc/src/ptyh.inc:3`），且那个包只支持 linux/i386（`fpc:packages/libc/fpmake.pp:30-31`）。改尺寸用 `ioctl(TIOCSWINSZ)` |
| `uptythread.pas` | 共用 | 读线程 + 加锁队列 + 一次 `QueueAsyncCall`（§3.5）；写 PTY 在主线程 |

`OnGridResize` → 改 PTY 尺寸；`OnData` → 写 PTY；进程退出 → 在终端里打一行提示。

### 12.3 流量控制（5 期）

读线程在待写字节超过高水位（建议 1MB）时停读，等 `Write` 回调把积压降到低水位（建议 256KB）以下再读。这是上游文档推荐的做法（`WriteBuffer.ts:12-19` 的注释要求宿主做流控）。

### 12.4 ConPTY 的两件事

- **版本号**：示例用 `RtlGetVersion` 取 Windows 构建号，设 `Core.WindowsPty := (twpConPty, 构建号)`。低于 21376 时核心关折行、开折行启发（§6.2）。
- **win32-input-mode**：ConPTY 启动时会不会发 `CSI ? 9001 h`、发了之后要求终端怎么报键，出处是上游注释里链接的微软规格（`InputHandler.ts:2043`），本机没有源码可核；控件默认不开这个扩展（§7.2），键盘按普通 VT 发。列入后期（§15），真机上先观察 ConPTY 实际发了什么（§16）。

---

## 13. 测试

### 13.1 上游基准环境

- 上游**按路径钉版本**，照 AdvChart 的做法（`D:/Projects/ty-advchart/tools/advchart-oracle/bar-geometry.js:68`：`process.env.ECHARTS_DIST || '<固定路径>'`）：脚本里写 `const XTERM = process.env.XTERM_ROOT || 'D:/Projects/xterm.js'`，启动时读 `package.json` 的版本和 `git rev-parse HEAD`，写进每个夹具。
- 用本地 checkout 构建，不装 npm 包：15-graphemes 那个 addon 没发布（`addons/addon-unicode-graphemes/README.md:11`），而且移植源和基准必须是同一份代码。
  一次性准备：在 `D:/Projects/xterm.js` 跑 `npm ci`、`npm run build`（`tsgo -b ./tsconfig.all.json`，`package.json:39-41`），产物在 `out/` 和 `addons/*/out/`。
- 加载：`NODE_PATH=<XTERM>/out node tools/terminal-oracle/<x>.js`——addon 源码用 `common/...` 路径别名（`addons/addon-unicode-graphemes/src/tsconfig.json` 的 `paths`），上游自己的 benchmark 脚本就这么设（`package.json:67`）。入口 `out/headless/public/Terminal.js`（headless 包名 `@xterm/headless`，`headless/package.json:2`）。
- `terminal.unicode` 要 `allowProposedApi: true`（`src/headless/public/Terminal.ts:81-83`）。
- 读内部状态（`_core`、`BufferLine.loadCell`）是可以的：打包时没有混淆私有名（`bin/esbuild.mjs:43` 的 `mangleProps` 注释掉了），用 `out/` 更是原样。
- `write` 是异步的（§3.1），脚本每步都等回调。
- 本机 node v22.22.2（`node --version`），xterm.js checkout 目前没有 `node_modules`，1 期第一步就是装好、跑通。

**实现期修正（1 期）**：
- **node 下 15 表解码是坏的**。`third-party/UnicodeProperties.ts` 的 `_dec` 有 `Buffer` 时用 `Buffer.from(s, 'base64')`，node 的小 Buffer 从 8KB 共享池里切，`byteOffset` 不是 0；`unicode-trie.ts` 用 `new DataView(data.buffer)` 读头，**忽略了 `byteOffset`**，读到池里的垃圾：补充平面的 `getInfo` 全是 0（表情不宽、区旗不连），还会分配约 1.8GB，结果随池里内容变、不可复现。浏览器走 `atob` 分支，是对的。修法：`lib-dump.js` **第一行** `Buffer.poolSize = 0`（加载任何上游模块之前），Buffer 不再走池；再由 `checkTrieDecode` 从同一段 base64 的干净副本独立解码一遍，逐码位和 addon 的 `getInfo` 对照，不一致就中止。基准因此取的是浏览器里的行为。
- 用 `out/`（`tsgo` 产物）。上游自己的单元测试已改用 `npm run esbuild` 的 `out-esbuild/`，`out/` 仍可加载，`XTERM_OUT` 留作备选。
- ~~加载：`NODE_PATH=<XTERM>/out node tools/terminal-oracle/<x>.js`~~ `NODE_PATH` 在 `lib-dump.js` 里设（`process.env.NODE_PATH` + `Module._initPaths()`），命令行不带环境变量前缀——前缀是 POSIX 写法，PowerShell 不认。上游路径仍可用 `XTERM_ROOT` 覆盖。
- 依赖只装在 xterm.js checkout 里：`npm ci --ignore-scripts`（`node-pty` 是原生模块、我们用不到）、`npm run build`。`tools/terminal-oracle/` 不是 npm 包，没有 `package.json` / `node_modules`，脚本只用 node 内置模块。
- 钉版本：`package.json` 版本、HEAD 前缀对不上，或 checkout 有已跟踪文件的改动，就拒绝。期末审查补了一条：钉的是源码 commit，跑的却是构建产物，所以移植涉及的五个源文件任何一个比它的产物新（构建后又切过 commit），也拒绝，提示重新 `npm run build`。

### 13.2 目录

| 路径 | 内容 |
|---|---|
| `tools/terminal-oracle/*.js` | 生成脚本，一类一个：`gen-unicode-tables.js`（§4.2）、`unicode-cases.js`、`url-cases.js`（4 期）、`parser-cases.js`、`core-cases.js`、`escape-files.js`、`recordings.js`、`fuzz.js`、`keyboard-cases.js`、`mouse-cases.js`、`reflow-cases.js`（5 期）；共用的导出代码放 `lib-dump.js` |
| `tools/terminal-oracle/cases/*.js` | 手写用例的输入（序列 + 尺寸 + 步骤），不含期望值 |
| `tools/terminal-oracle/recordings/*.cast` | 真实程序录制（每份 ≤ 256KB，§17 实现问题 8） |
| `tests/fixtures/terminal-<name>.json` | 生成的夹具（输入 + 期望值），照 AdvChart 的平铺命名（`tests/fixtures/advchart-*.json`） |
| `tests/test.unicode.width.pas`、`tests/test.terminal.parser.pas`、`…buffer.pas`、`…core.pas`、`…keyboard.pas`、`…mouse.pas` | 基准比对 |
| `tests/test.terminal.view.*.pas` | 3–5 期控件测试 |

**实现期修正（1 期）**：
- 1 期实际的文件：`lib-dump.js`（上游加载、钉版本、Buffer 池修法、变体切换、区间编码、写文件与 2MB 上限、生成物登记 `GENERATED`）、`gen-unicode-tables.js`、`unicode-cases.js`、`cases/unicode.js`（手写序列与串，只有输入）、`regen-all.js`（重跑全部生成脚本；只许 `GENERATED` 里的文件变，带 `--expect-clean` 时一个字节都不许变；期末审查加了一条：运行前工作区必须干净，否则手改和生成改分不开）、`unicode-license.txt`（Unicode License v3 原文，从 unicode.org 取）。
- 三份夹具：`terminal-unicode-width.json`（六个变体全码位 `wcwidth` 的区间表 + 越界探针）、`terminal-unicode-join.json`（六个变体 × 九个前驱的全码位 `charProperties` 区间表）、`terminal-unicode-cases.json`（手写序列、代表码位两两 / 三连、串宽）。格式写在 `unicode-cases.js` 头部，不用 §13.3（那是 2 期缓冲夹具的格式）。实际体积约 42KB / 642KB / 699KB。

**实现期修正（2 期）**：
- 2 期多出的脚本：`lib-term.js`（建终端、跑步骤、导出整份状态、合成应答器、种子随机数、REP 快进标记）、`buffer-cases.js`（缓冲层操作脚本）、`gen-terminal-charsets.js`（§2.1）、`wsl-record.sh` + `wsl-record-pipe.py`（WSL 里用 tmux 录制，§13.4）；手写输入 `cases/parser.js`、`cases/buffer.js`、`cases/core-hand.js`。鼠标限制 / 编码的直接比较并进 `core-cases.js`；`mouse-cases.js` 留给 4 期的控件侧事件转换。
- `lib-dump.js` 的过期构建检查 `PORTED` 覆盖 2 期移植的全部源文件（含 `data/EscapeSequences.ts`、`headless/public/Terminal.ts`）；`regen-all.js` 缺任何一个生成脚本就报错，不再跳过。
- Pascal 测试：`test.terminal.oracle.pas`（辅助单元）、`test.terminal.parser.pas`、`test.terminal.buffer.pas`、`test.terminal.core.pas`；探针 `tools/terminal-probe`（参数写错给出明确的错误）。

**实现期修正（3 期）**：
- 新脚本：`keyboard-cases.js`（+ 手写输入 `cases/keyboard.js`；美式布局表只有这一份真源）、`gen-terminal-glyphs.js`（→ `CustomGlyphs.inc`）、`view-cases.js`（上游 256 色表）、`light-palette.js`（浅底 16 色，`--check` 核 `light.tycss`）；`regen-all.js` 与 `lib-dump.js` 的 `PORTED` / `GENERATED` 跟着加。
- 新夹具：`terminal-keyboard.json`、`terminal-paste.json`、`terminal-view-palette.json`。
- 新测试单元：`test.terminal.keyboard.pas`（对上游逐位）、`test.terminal.render.pas`（渲染部件）、`test.terminal.view.pas`（属性、事件接线、调度、焦点、主题、网格；另导出探针类和夹具）、`test.terminal.view.paint.pas`（像素与性能）、`test.terminal.view.input.pas`（键盘、滚轮、滚动条、输入法）、`test.terminal.view.theme.pas`（17 个主题 × 明暗）、`test.terminal.example.pas`（示例的录制读取与流控回放；测试工程的搜索路径加了 `examples/terminal`）。
- 工具：`tools/terminal-fontprobe`（E1 / E2，`--e1` / `--e2`），`tools/terminal-shots`（验收截图：离屏建控件、`RenderTo` 画进位图存 PNG，17 个主题 × 明暗的彩色 ls 与 16 色样例、几段录制、放大的色样，连同 `index.md` 写进 `docs/superpowers/plans/2026-09-29-terminal-phase-3-shots/`）。两个都直接引用 `source/`、不经 `.lpk`，不进包。

Pascal 侧读夹具照 AdvChart：`ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + 'terminal-<name>.json'`，`fpjson` 解析（`D:/Projects/ty-advchart/tests/test.advchart.bargeometry.pas:62-66`、`:131-134`）。
夹具里有 NUL 字节时解析前要处理（[[fpjson-drops-u0000]]）——所以字节一律 base64 存，不用 JSON 字符串。

### 13.3 期望值 JSON 格式

```json
{
  "upstream": { "name": "xterm.js", "version": "6.0.0", "commit": "c58ea3637f39" },
  "generator": "tools/terminal-oracle/core-cases.js",
  "cases": [
    {
      "id": "sgr-256-and-wrap",
      "cols": 20, "rows": 5,
      "options": { "scrollback": 10, "unicodeVersion": "6", "ambiguousWide": false,
                   "convertEol": false, "windowsPty": null },
      "steps": [
        { "write": "<base64>" },
        { "resize": [12, 5] },
        { "write": "<base64>" }
      ],
      "expect": {
        "active": "normal",
        "cursor": { "x": 3, "y": 1 },
        "ybase": 0, "ydisp": 0,
        "scroll": { "top": 0, "bottom": 4 },
        "modes": { "applicationCursorKeys": false, "bracketedPaste": false, "insert": false,
                   "origin": false, "reverseWraparound": false, "sendFocus": false,
                   "showCursor": true, "wraparound": true, "synchronizedOutput": false,
                   "mouseProtocol": "NONE", "mouseEncoding": "DEFAULT",
                   "cursorStyle": null, "cursorBlink": null },
        "title": "",
        "bells": 0,
        "data": "<base64，这个用例期间 OnData 发出的全部字节>",
        "buffers": {
          "normal": [
            { "y": 0, "wrapped": false, "text": "hello",
              "cells": [ [104, 1, 0, 0], [101, 1, 0, 0] ],
              "combined": { },
              "ext": { "3": [1, 0, 0, 0] } }
          ],
          "alt": [ ]
        },
        "links": { "1": { "id": "", "uri": "https://example.com" } }
      }
    }
  ]
}
```

- `cells` 每格 `[content, fg, bg, 占位]`，前三个是 `BufferLine.loadCell` 读出的原始 32 位字（`xterm:src/common/buffer/BufferLine.ts:201`；`CellData.ts:23-27`），**逐位比较**。`combined` 按列号存组合内容，`ext` 按列号存 `[ext, urlId, underlineColor, underlineVariantOffset]`（`AttributeData.ts:141-180`），只列有扩展属性的格。
- `text` 是 `translateToString(true)`，只给人看，失败时打印；不参与判定。
- 行只导出到最后一个非空行为止，再加上光标所在行；缺的行 Pascal 侧断言为空行。
- `modes` 的字段名和 headless `IModes` 对齐，多出的（鼠标编码、DECSCUSR 状态）从 `_core` 读。
- 数字都在 32 位以内，不用 AdvChart 的 IEEE 位模式写法。

**实现期修正（2 期）**（细则在 2 期计划「夹具格式」）：
- `cells` 的第 4 个槽位是**游程**（连续相同的格数）；`combined` 存码位数组；「长度等于列数、不折行、全是默认空格、无组合无扩展」的行省略，其余全导出；制表位导出为真的键、按数值排序；单个文件超 1.8MB 自动分片 `terminal-<kind>-<n>.json`，Pascal 侧查分片连号。
- 导出比原稿多：`isUserScrolling`、kitty 键盘状态、`cursorInitialized`、两个可被序列改的选项终值、字符集 G0–G3 与 GL、保存的光标（含字符集）、标记行号、标题栈、链接表、解析器状态与连接状态、各事件的计数与列表，以及本批加的 **`curAttr` / `eraseAttr`**（`{fg, bg, ext: [ext, urlId, 下划线色, 变体偏移]}`，接下来要写的字符和要擦的格子用的属性）。
- 用例可带 `ignore`：顶层字段名的列表，Pascal 比较时跳过。只用于有文档的偏离——REP 快进不发被跳过那段的 `OnScroll`（§15），`lib-term.js` 看到 REP 次数大到可能快进（`> 2 × 环形表容量 + 行数 + 2`）就自动标 `["scrolls"]`。
- **合成应答器每个核心用例都挂**（不只 `synthesized` 类）：Pascal Core 总会答颜色、明暗、1004 焦点，随机字节和录制里一旦出现这些查询，两边才对得上；调色板 259 项随夹具走。

### 13.4 夹具来源与覆盖

| 来源 | 内容 | 期 |
|---|---|---|
| Unicode | §4.5 | 1 |
| 上游自带序列文件 | `xterm:test/fixtures/escape_sequence_files/` 的 76 个 `.in`（80×25，`NOTES` 第 1 行；上游自己的对照测试跳过的几个照跳并记原因，`src/browser/Terminal2.test.ts:21-36`） | 2 |
| vttest 风格手写 | 光标移动、擦除（ED / EL / ECH）、插删（ICH / DCH / IL / DL）、滚动区域 + 原点模式、制表位、字符集（DEC 特殊图形）、SGR 全集（含 `:` 子参数、58 / 59）、宽字符跨行尾、组合字符在行首 / 跨折行、主备屏切换与存取光标、DECSTR / RIS、DSR / DA / DECRQM 应答、OSC 0/2/8、2026 | 2 |
| 真实程序录制 | vim、less、htop、git log --color、ls --color、python REPL、tmux 分屏、`cat` 含中文和表情的文件；Windows 下 cmd / pwsh 经 ConPTY 的输出 | 2（先用 Linux 上录的；ConPTY 的录制 4 期补） |
| 切块 | 同一段输入按 1 字节、随机位置切块喂，结果必须和整块一样（UTF-8 半截、转义半截跨块） | 2 |
| 坏序列 | 截断的 CSI / OSC、非法 UTF-8、C1 字节、ESC 打断序列、CAN / SUB、未知终止字节 | 2 |
| 超长 | 1000 个参数、20 位数字参数、64KB 中间字节、11MB OSC 载荷、1MB 不换行文本；断言 §5.2 的上限和后续序列照常 | 2 |
| 随机 | 种子化随机字节（偏向 ESC、`[`、`;`、数字、终止字节），固定种子写进夹具 | 2 |
| 颜色请求 | OSC 4/10/11/12 查询应答：headless 不应答（§1.1 第 8 条），脚本里挂一个照 `CoreBrowserTerminal.ts:211-258` 抄的应答器、用固定调色板；夹具标 `synthesized: true` | 2 |
| 键盘 | `evaluateKeyboardEvent` 直接调（`out/common/input/Keyboard.js`）：VK × 修饰键组合 × 应用光标 × isMac × macOptionIsMeta，`key` / `code` 用和 Pascal 侧同一张美式布局表生成 | 3 |
| 鼠标 | `MouseStateService` 的过滤和编码直接调（含横向滚轮 LEFT/RIGHT）；`_triggerMouseEvent` 的前处理是浏览器代码，移植后对照 `MouseService.ts:497-545` 逐条写断言 | 4 |
| 网址识别 | 上游 `strictUrlRegex` 在 node 里直接跑（§9.8） | 4 |
| 重新折行 | `resize` 步骤前后的缓冲，含 `windowsPty` 两种设置 | 5 |

**实现期修正（2 期）**：
- 序列文件~~上游跳过的几个照跳~~**全比、不跳**：76 个 `.in` 加 3 个停用的 `.in_`，共 79 个；上游跳过的 5 个理由是「和真 xterm 的输出对不上」，我们比的是上游本身，理由不成立。从 git 对象读（工作区在 `autocrlf` 下是 CRLF），80×25、`convertEol: true`（代替真 PTY 的 ONLCR）。
- 录制：本机 WSL `Ubuntu` 里用 tmux 脚本化驱动 8 个程序（vim、less、htop、`git log --color`、`ls --color`、python REPL、tmux 分屏、`cat` 中英文表情文件），`env -i` 清空环境、不带用户名和主机名。本批把 tmux 的 `default-terminal` 设成 `xterm-256color`（原来是 tmux 默认的 `screen`，程序只发 8 色）后全部重录，vim 用 `habamax` 配色，录到了 `38;5` 序列。ConPTY 的录制 4 期补。
- 超长：IL / DL / SU / SD 的 2^31 次上游跑不完，改由 Pascal 的耗时守卫证明（参数 2^31−1 与 1000 结果相同、很快返回）；夹具里用 1000 证明钳制等价。REP 用几倍环形表容量的次数（十几种形态：宽字符、字形簇、区旗、上下边距、光标在边距外、不折行、插入模式、用户上翻、备用屏、链接、属性、ConPTY 无滚回）由上游逐个打印出期望值，证明快进与逐个打印相同。

### 13.5 夹具纪律（AdvChart 的教训照搬）

出处：`D:/Projects/ty-advchart/docs/superpowers/specs/2026-09-01-advancechart-tier0.md:4785-4792`、[[advchart-upstream-oracle]]。

1. **精确比较**。缓冲的三个字、光标、模式、`OnData` 字节逐位相等；没有容差。
2. **照上游的结果做，不照它注释的意图做**。例：1049 注释说要清备用屏但实际不清（表里 `:1926` 写「不清」，`:1930` 的 FIXME 说应该清）；照结果。
3. **有意的偏离只在一处归一化**：XTVERSION 字符串（§7.2）、合成的颜色应答（§13.4）。脚本和 Pascal 测试各有一个 `Normalize` 函数，只处理这几条，每条带理由。
4. **输入分类**：夹具里每个用例标明来源（`escape-file` / `hand` / `recording` / `fuzz` / `synthesized`），失败时先看类别。
5. **复用路径也要比**：每个用例在 Pascal 侧跑两遍——一次 `Reset` 后重跑、一次新建 Core——结果都要对（照 AdvChart「先 Invalidate 再画一次」那条）。
6. **上游自己崩的输入**没有答案：删掉用例并在脚本里记一行。
7. **生成可复现**：脚本不读时间、不用未种子化的随机数；重跑脚本 `git diff` 应为空。

**实现期修正（2 期）**：
- 第 5 条的「复用路径」期望值**由 node 实际 `reset()` 后在同一实例上重跑生成**：headless 的 `reset()` 不是全复位（标题、链接号、隐藏的光标都留着），不能假设和新建一样；相同就记 `"afterReset": "same"`。
- 第 3 条的归一化只有 XTVERSION 一处；合成应答挂在 node 侧，不算归一化。
- 8. **每个判据单独一个用例**（本期期末审查的教训）：同一个用例里后面的步骤会把前面的结果盖掉（IL 之后又 DL、一个 ECH 之后又一个、DECSTBM 之后又一个），钳制「减 1」这类变异就测不出来。钳制类用例在内容不全是空白的屏幕上做，做完立刻结束，结果留在导出的状态里。
- 9. 每个用例的核心全部释放后，行、标记、链接条目的存活数必须回到用例开始前（泄漏守卫，每用例一次）。

### 13.6 3–5 期

- **像素**：`RenderTo` + 哨兵底色（[[headless-render-needs-sentinel-ground]]），数光标、选区、下划线、宽字符两格、块元素连线、16 色取自主题。字体相关的断言只数「有没有墨」和格子边界，不比字形像素（本机字体不稳定）。
- **事件**：键盘经真实的 `KeyDown` / `UTF8KeyPress`、鼠标经真实的 `MouseDown` / `MouseMove` / `MouseUp` / `DoMouseWheel`，断言 `OnData` 字节；覆盖键、右键分流、滚轮三种去向、链接 Ctrl+单击、OSC 52 三种策略、`OnShortcutQuery` 放行。
- **调度**：`Write` 回调顺序、切片后状态和 `WriteSync` 一致、非主线程 `Write` 抛异常。
- **变异**：每条测试守护的规则删一次确认会红（[[tests-written-with-the-fix-are-green-and-wrong]]）；接线类变异（事件没发、Invalidate 没调）要有测试能杀（[[built-not-wired-is-the-default-failure]]）。

### 13.7 节奏

每期：写完编一次、跑一次全量（输出重定向到文件，[[known-rare-suite-flake]]）→ 期末集中变异 → 整体审查（逐条对本规格 + 代码质量）→ 把实现期修正写回本规格原处。真机项期末汇总成验收表（放 `docs/superpowers/plans/`）。

---

## 14. 许可与署名

- 库是 Modified LGPL（`THIRD-PARTY-NOTICES.md:3`）；xterm.js 是 MIT（`xterm:LICENSE:1-3`：The xterm.js authors、SourceLair Private Company、Christopher Jeffrey）。MIT 允许并入，条件是保留版权和许可声明。
- **移植单元头部**写：移植自 xterm.js 6.0.0（commit、源文件路径），版权行照抄 `LICENSE:1-3`，「MIT，全文见 THIRD-PARTY-NOTICES.md」。addon 移植的部分另写 addon 自己的版权行（`addons/addon-unicode11/LICENSE:1`：2019；`addons/addon-unicode-graphemes/LICENSE:1`：2023）。自定义字形表（§10.5）同理。
- **`THIRD-PARTY-NOTICES.md` 加一节**，格式照 Lucide 那节（`:12-`）：`## xterm.js — <单元列表>`、上游地址和钉住的 commit、「用了 `tyControls.Terminal*` / `tyControls.Unicode.Width` 才要带」、MIT 全文。
- **Unicode 数据**：15 的表源自 Unicode 字符数据库，另加 Unicode 许可（Unicode License v3）声明；原文 1 期从 unicode.org 取（§17 实现问题 10）。
- **实现期修正（1 期）**：`addon-unicode-graphemes` 的 `UnicodeProperties.ts`（字形簇规则 `shouldJoin` / `_shouldJoin` 和 15 表数据）由外部项目 PerBothner/unicode-properties 生成（addon `README.md:7`）。该项目许可已核实为 **MIT**（仓库 `LICENSE` 首行 `Copyright 2018`，正文与 xterm.js 的 MIT 逐字相同、只是折行不同；GitHub 标 `MIT`），兼容，规则照移植、不必按 UAX #29 自写。单元头、`.inc` 头、`THIRD-PARTY-NOTICES.md` 的 xterm.js 一节都写了出处；notices 把它的版权行和 xterm.js 的几行并列、共用同一段 MIT 正文，发版守卫 `TheThirdPartyNoticeCoversTheUnicodeWidthPort` 查这一行。§4.2 理由 2 说的「没有许可头」仍然成立，只是文件本身没写，来源项目有许可。
- **测试夹具**：`escape_sequence_files` 的输入来自 xterm.js 仓库（MIT），其中部分期望文本注明取自另一个项目（`NOTES` 的「text used from … vt100-parser」一行）；我们只取 `.in` 输入、期望值由上游生成，但输入字节进了夹具，在 notices 里加「测试夹具」一小节（§17 实现问题 9）。
- **实现期修正（2 期）**：`MarkLodato/vt100-parser` 许可已核实为 MIT（`Copyright (c) 2010 Mark Lodato`），它的 `test/` 与 xterm.js 的 76 个 `.in` 有 48 个同名，notices 的「Test fixtures」一小节写明部分输入最初出自那里并附其版权行。xterm.js 一节的版权行照上游 `LICENSE` 补了「`Copyright (c) 2014-2026, The xterm.js authors`」一行；Fabrice Bellard（jslinux）的版权只在 Core 单元头说明来历（上游 `LICENSE` 不列它）。notices 标题逐个列出移植的文件（含 `Charsets.inc` 和 Core 的三个 include），发版守卫逐个查。
- **实现期修正（3 期）**：notices 的 xterm.js 一节标题加了三个文件——`tyControls.Terminal.Keyboard.pas`（`Keyboard.ts`、`Clipboard.ts` 的粘贴两函数、第三层 Shift 判定）、`tyControls.Terminal.Render.pas`（颜色解析、256 色表、自绘字形的光栅化逻辑）、`tyControls.Terminal.CustomGlyphs.inc`（自绘字形数据，出自 `addon-webgl`，另列 addon 的版权行 2018 / 2021）。控件单元 `tyControls.Terminal.pas` 是自己写的，只照上游的逻辑、单元头注明出处行号。

---

## 15. 有意的偏离与不做清单

**和 xterm.js 不同**：

- macOS 默认选区覆盖键是 Option（上游默认没有，§1.1 第 5 条）。
- 横向滚轮上报（上游不产生，§1.1 第 3 条）。
- `AlternateScroll` 属性可关（上游无条件，§1.1 第 2 条）；仍不认 DECSET 1007。
- XTVERSION 报库名（§7.2）。
- 1016 报设备像素（§9.5.1）。
- 复制时行尾用平台换行（§9.6.1）。
- `OnData` 合并了 `onData` / `onBinary`（§3.3）。
- 解析处理器全同步（§2.2）。
- 程序接管鼠标时 Ctrl+单击仍开链接、覆盖键+右键弹菜单（§9.5.2、§9.8）。
- 闪烁文字不闪（上游默认也不闪，只是没有开关）。

**实现期修正（2 期）**，2 期新增的偏离：
- **REP**：上游先分配「次数 × 文本」再打印，次数一大就不返回、没有答案。~~Pascal 钳到 2^20 次~~ 我们按次数精确打印，靠快进保证耗时有界：输出把整个环形表（行数 + 滚回）翻过一遍以上后，状态随重复的周期循环，整周期跳过；行、光标、`ybase` / `ydisp`、环形表起点都和逐个打印相同，只是被跳过那段滚动**不发 `OnScroll`**。几倍环形表容量的次数由上游逐个打印出期望值证明等价。唯一跳不过去的是每次重复都把码位堆进同一格（孤立的组合符反复重复）：同一行上、既不滚动也不换行地打了 2^20 个码位后停止。耗时与次数无关，约为「环形表容量 × 被重复文本的长度」。
- 修上游「一片因时间预算停下后改尺寸，已处理的块再解析一遍」的 bug：`WriteSync` 和改尺寸前的清空都从第一个没处理的块开始（§3.1）。
- 写入队列的异常安全、块数上限、事件里调用的延后（§3.1）是我们加的；上游在处理器抛异常后会停在「同步写中」。
- 颜色、明暗、焦点的应答在 Core 里（上游在浏览器层，headless 不应答）；没挂 `OnQueryBaseColor` 时颜色与明暗不应答，和 headless 一致（§7.3）。
- 新增事件：`OnIconNameChange`、`OnModesChange`、`OnProcessRequest`、`OnWindowOptionsReport`、`OnScrollbackCleared`、`OnResize`（上游有 `onResize`，这里照发）；`TriggerMouseEvent` 和 `EndSynchronizedOutput` 把浏览器层的两段逻辑搬进 Core。
- 码位编 UTF-8 时，越界或代理区的码位写成 U+FFFD（上游会生成孤立代理或乱码；解码器本来不会产出这种码位）。
- `Scrollback` 上限 100000（§6.2）。
- 2–4 期不重新折行：改列数时走上游「老 ConPTY」那条路径（§6.2），5 期接上。
- OSC 8 链接表最多 10000 条、16MB，再多丢最老的；链接号 Int64（§6.2）。

**实现期修正（3 期）**，3 期新增的偏离：
- Shift+Home / Shift+End 是本地的「到顶 / 到底」（上游照常发给程序）：PSReadLine、nano 里用它们选到行首 / 行尾的，在这个终端里做不到；真机验收时定去留（§9.4）。
- 14t / 16t 的窗口、格子尺寸应答报**设备像素**（上游 CSS 像素，同 1016）。
- 比格子宽的字形横向压缩进格子（上游 `rescaleOverlappingGlyphs` 默认关）。
- 输入法组字时不滚到底：输入法处理中的键在 `KeyDown` 里直接放过；上游这时若 `scrollOnUserInput` 就先滚到底（`CoreBrowserTerminal.ts:857-861`）。
- Kitty 键盘协议、win32-input-mode 控件不编码，所以两个扩展一律屏蔽：程序查询时不报支持，宿主改了 `Core.VtExtensions` 也在下一次解析前关掉（上游选项打开就报）。
- Shift+滚轮在 Windows / Linux 上不滚滚回、事件交还父控件（上游是横滚，终端没有横向可滚），效果相同。
- `Core.DiscardPending`（丢掉未解析的块、不调回调）是新增的（§9.3）。

**不做**（以后要再单独立项）：

- 屏幕阅读器（§1.1 第 1 条：LCL 默认构建里没有任何 widgetset 桥接）。
- 连字（上游 `addon-ligatures`）。
- 图片协议：sixel、iTerm IIP、kitty 图形（上游 `addons/addon-image/src/SixelHandler.ts`、`IIPHandler.ts`、`kitty/KittyGraphicsHandler.ts`）。
- kitty 键盘协议：上游有 `src/common/input/KittyKeyboard.ts`（526 行），CSI `= ? > <` u 四个处理器注册了但选项默认关（`InputHandler.ts:259-262`、`:3552-3553`）；Core 照移植「关着」的行为（查询不应答），键盘编码后期再说。
- win32-input-mode 的键盘编码（`Win32InputMode.ts`，§12.4）：后期，先真机观察 ConPTY。
- Alt+单击移动光标（上游 `altClickMovesCursor` 默认开，`OptionsService.ts:56`；`MoveToCell.ts`）：后期。
- 搜索（`addon-search`）、序列化（`addon-serialize`）、进度条 OSC 9;4（`addon-progress`）、网页字体（`addon-web-fonts`）。
- 彩色表情（取决于 E1；大概率 BGRA 画不出）。
- 文字闪烁（SGR 5）。

---

## 16. 只能真机验的

- **ConPTY**（Windows 10 19044 / Windows 11）：原生控制台程序（`cmd` 里的 `edit` 类程序、`far`、PowerShell 的 `PSReadLine`）经 ConPTY 能否收到鼠标；ConPTY 启动时实际发了哪些模式（是否有 `?9001h`、`?1004h`）；构建号 < 21376 时折行启发的效果；`ResizePseudoConsole` 后的重绘。
- **forkpty**（Linux、macOS）：`$SHELL` 起得来、`TIOCSWINSZ` 后 vim / htop 跟着变、进程退出的收尾。
- **键盘**：Win32 上 Alt+字母会不会先被窗体菜单拿走（`WM_SYSKEYDOWN`、F10）；AltGr 布局（德语、法语）出字符；macOS Option 两种设置；死键；Ctrl+Space、Ctrl+/、Ctrl+Shift+2/6/-。
- **输入法**：Win32 / Qt6 / GTK2 / Cocoa 上中文输入、候选窗在光标格；Cocoa 的组字串显示与提交时机（§9.9）；GTK3 候选窗位置（已知不跟随）。
- **字体**：E1、E2 两个实验本身就在各平台上跑；Linux / macOS 小字清晰度；macOS CJK 下半截。
- **剪贴板**：Linux PRIMARY（X11、Wayland）、中键粘贴；OSC 52 写入后的系统剪贴板。
- **鼠标**：各 widgetset 横向滚轮（触控板）上报的符号是否符合 LCL 的约定（§9.5.3）；拖出窗口后的上报坐标；多击判定间隔。
- **DPI**：125% / 150% / 每显示器 DPI 切换时格子数、字形缓存重建。
- **性能**（5 期）：`cat` 大文件、`yes`、全屏 htop 刷新时的 CPU 和帧率，四个 widgetset 各一次。
- **皮肤**：17 个主题 × 明暗下 16 色、选区、光标、链接下划线看不看得清。

**实现期修正（3 期）**：E1、E2 在 Win32 上已经跑过（结论与数字见 §10.3），Qt6 / GTK2 / Cocoa 仍待真机；3 期的真机验收项汇总在 3 期计划末尾（截图在 `docs/superpowers/plans/2026-09-29-terminal-phase-3-shots/`）。

---

## 17. 开工前要定的问题

### 17.1 要问用户的

> **已定（2026-09-28）**：用户回复「按你说的做」，以下 11 条全部按建议。另：用户明确不想引入第三方库——Unicode 表编译进库（§4.2），运行时不依赖 ICU 或任何外部库。

1. **默认 Unicode 版本**。建议 `tuv11`：6 太老，表情和很多 CJK 扩展区都算错；15-graphemes 上游自称实验性（`addons/addon-unicode-graphemes/README.md:3`）。
2. **6 / 11 版本下 `AmbiguousWide` 怎么办**。建议不起作用、文档写明，这样每种组合都有上游基准（§4.3）。
3. **字体从哪来**。建议：主题键 `TyTerminal` 的 font-family / font-size（token 默认 `monospace` + 基础字号），实例覆盖按「字体覆盖通道」需求的规则就地实现（`ParentFont = False` 且字段非出厂值才生效），那个需求落地后并入公共 helper（§10.3）。
4. **16 色默认值**。深底用 xterm.js 的 Tango（已核实，`xterm:src/browser/Types.ts:183-203`）。浅底那套建议：同色相、逐色调暗到对白底对比度 ≥ 4.5:1（0 黑、7 白、8 亮黑、15 亮白除外），3 期用脚本算出后写死进 light.tycss，出 17 主题截图给你拍板。
   **实现期修正（3 期）**：按公式做了，字面「对白底 ≥ 4.5:1」达标（最差 3 号 4.52:1）；但各皮肤的浅底不是纯白，3 号色落到实际 `--surface` 上最差 xp 3.70:1、macos 3.82、breeze 3.96（其余 ≥ 4.04）。主控决定暂按（c）维持，5 期 `MinimumContrastRatio` 兜底；最终验收时看截图（`docs/superpowers/plans/2026-09-29-terminal-phase-3-shots/`，含 xp / macos / breeze 的 3 号色放大样例和 7 / 15 号色放大样例）请用户在（a）以最暗浅底重算、（b）终端底色改用更白的 token、（c）维持 三者中定；7 / 15 在浅底上几乎看不见，同一次定要不要调。
5. **复制粘贴快捷键**。建议 Win / Linux：Ctrl+Shift+C / V 和 Ctrl+Insert / Shift+Insert；macOS：Cmd+C / V；Ctrl+C 永远发给程序。
6. **Tab 和窗体快捷键**。终端默认吞掉 Tab 和所有有编码的键，焦点只能靠鼠标或宿主放行的键离开；`OnShortcutQuery` 让宿主逐键放行（§9.4）。要不要给一个默认放行的键（比如 Ctrl+Tab）？建议不给，交宿主。
7. **1007**。建议只做属性 `AlternateScroll`、不认 DECSET 1007，保持和上游逐位一致（§9.5.4）。
8. **程序接管鼠标时怎么弹菜单**。建议覆盖键 + 右键弹控件菜单（§9.5.2）。
9. **Linux PRIMARY 和 `CopyOnSelect`**。建议 Linux 上选完总是写 PRIMARY、中键粘贴 PRIMARY；`CopyOnSelect`（写系统剪贴板）默认关。
10. **列选择**。建议 4 期照上游做 Alt+拖动（macOS 上 Option 是覆盖键时不做）。
11. **回放格式**。建议 asciicast v2，示例和基准脚本共用同一批录制。

**实现期修正（3 期）**，3 期开工前问题一的三条结论（按建议执行、已告知用户，最终验收时可改）：
1. 应用小键盘模式（DECKPAM）不影响小键盘，照上游（§1.1 第 9 条）。
2. 滚动条的宽度一直留着，列数不随主屏 / 备用屏变（§9.7）。
3. 浅底 16 色里 7 / 15 照已定的不调，截图里放大一张给用户定（第 4 条的修正，连同 3 号色在各皮肤浅底上的取舍）。

### 17.2 实现层面的（计划里定，不必问）

1. `TTyTerminalCore` 用 `TObject`（§7.1）。**已完成（2 期）**。
2. 非主线程 `Write` 抛 `EInvalidOperation`（§3.5）。**已完成（2 期）**：扩到全部公开入口（§3.1）。
3. 字形遮罩做法由 E2 定，默认（a）（§10.3）。
4. 字体回退由 E1 定，缺 CJK 时加 `--terminal-font-family-wide`（§10.3）。
5. Unicode 表的存放：15 表 dump 成区间数组 + 二分；6 / 11 的 BMP 部分建 64K 字节查表（同上游，`UnicodeV11.ts:197-211`），在 `initialization` 里建。**已完成（1 期）**：15 表存原始 `getInfo`，`wcwidth` / `charProperties` 由移植逻辑现算；6 / 11 的 BMP 外也走区间二分。
6. 解析器转移表在 `initialization` 里照上游代码生成（§5.1），不写成常量数组。**已完成（2 期）**：4257 项与上游逐项相同。
7. 组合内容的稀疏存储：每行一个按列号排序的小数组（行里组合格很少），不上字典。**已完成（2 期）**：组合文本和扩展属性各一个，只在标志位说有时才读。
8. 录制文件每份 ≤ 256KB，夹具 JSON 单个 ≤ 2MB；超了就拆用例。**夹具部分已完成（1 期）**：`writeFixture` 超 2MB 就报错；录制 2 期起。**已完成（2 期）**：超 1.8MB 自动分片；8 份录制最大约 13KB，`recordings.js` 超 256KB 报错。
9. `escape_sequence_files` 进夹具前核对那份外部来源的许可（§14）。**已完成（2 期）**：vt100-parser 为 MIT，notices 已写（§14）。
10. Unicode 许可原文 1 期从 unicode.org 取（§14）。**已完成（1 期）**：`tools/terminal-oracle/unicode-license.txt`，已抄进 `THIRD-PARTY-NOTICES.md`。
11. XTVERSION 的字符串格式：`TyControls(3.1.0)`，版本取 `TyVersion` 常量（`source/tyControls.Types.pas:111`）。**已完成（2 期）**：Core 不能用 LCL 单元，常量 `TyTermLibraryVersion` 另存一份，测试守着两者相等。

---

## 18. 交付顺序（给计划用）

每期一份计划 `docs/superpowers/plans/2026-MM-DD-terminal-phase-<n>.md`；每期末：全量、变异、审查、真机验收表。

### 1 期：Unicode 宽度与基准环境

- 装好 xterm.js checkout 的构建（§13.1），`tools/terminal-oracle/` 骨架和 `lib-dump.js`。
- `gen-unicode-tables.js` → `tyControls.Unicode.Width.Data.inc`；`tyControls.Unicode.Width`；`unicode-cases.js`。
- `THIRD-PARTY-NOTICES.md` 的 xterm.js 一节和 Unicode 许可。
- **做完能看到**：`tytests` 里 Unicode 一组全绿——四个版本全码位宽度、连接序列、串宽与上游逐位相同；重跑生成脚本 `git diff` 为空。没有界面。

### 2 期：解析器、缓冲、核心

- `Terminal.Parser`、`Terminal.Buffer`、`Terminal.Core`（含写入队列、颜色覆盖表、鼠标协议状态但不含上报前处理）。
- 夹具：`escape-files`、手写、切块、坏序列、超长、随机、颜色请求；录制先用 Linux 录的几段。
- **做完能看到**：几百个用例的缓冲、光标、模式、应答字节与上游逐位相同；超长 / 坏序列后状态有界。一个控制台探针（`tools/terminal-probe`，不进包）能把录制喂进 Core、打印屏幕文本，肉眼对照。

### 3 期：控件、键盘、滚回、主题、回放示例

- 开工先做 E1、E2（§10.3），结论写回本规格。
- `Terminal.Keyboard`（+ `keyboard-cases.js`）；`TTyTerminalView`：度量、行缓存、字形缓存、属性、光标与闪烁、自绘制表符和块元素、DPI、滚回与滚动条、焦点、`OnShortcutQuery`、复制粘贴快捷键（剪贴板读写先接上，选区 4 期）、设计期预览、组件注册与面板图标。
- 主题：§11 的键和 token、两个生成器、GGRID / GMETRICS、跨主题 resolve 和对比度测试；浅底 16 色按 §17 问题 4 拍板。
- `examples/terminal` 回放模式 + 键码面板；`docs/controls/terminal.md`；README 控件数。
- i18n：右键菜单的「清屏」、示例菜单项。
- **做完能看到**：示例里播放 vim / htop / 彩色 `ls` 的录制，画面和真终端一致，换 17 个皮肤和明暗 16 色都看得清；按键在键码面板里显示正确的字节；滚回和滚动条可用。

**实现期修正（3 期）**，3 / 4 期边界：
- 挪进 3 期：输入法（提交通路、候选窗定位、macOS 组字串）；粘贴编码（含括号粘贴，纯函数随键盘单元对上游比；4 期只剩真机验收）。
- 挪到 4 期：右键菜单（`ITyTextEditActions`）连同「清屏」和它的 resourcestring、i18n——和选区一起做；复制快捷键 3 期照吞、`CopyToClipboard` 空操作。
- 4 期接上：选区（字符 / 词 / 行 / 列、自动滚动、锚点跟随）、链接、`WriteClipboardText`（本期只有读剪贴板在用）、主题键 `TyTerminalSelection`、`TyTerminalLink` 与对应 token（本期已写进基础层、测试断言解析得出，但还没有东西用它们）、鼠标全套经 `Core.TriggerMouseEvent`、PTY 示例。

### 4 期：真 shell、鼠标、选区、输入法、链接、括号粘贴

- 示例 PTY 单元（§12.2）、`WindowsPty` 接线、`OnGridResize` → 改 PTY 尺寸。
- 鼠标全套（§9.5；`mouse-cases.js`）、选区（字符 / 词 / 行 / 列、自动滚动、锚点跟随）、PRIMARY、`CopyOnSelect`、右键菜单、OSC 52 三种策略。
- 输入法（§9.9）、链接（OSC 8 + 网址识别、悬停、Ctrl+单击）、括号粘贴。
- **做完能看到**：示例里跑 cmd / pwsh / bash / zsh；vim 和 htop 里鼠标可点可拖、Shift（macOS Option）拖动仍能本地选中复制；中文输入候选窗在光标处；Ctrl+单击链接弹出宿主的确认。真机验收表覆盖 §16 的 ConPTY、键盘、输入法、剪贴板、鼠标各项。

### 5 期：重新折行、流量控制、性能、最低对比度

- 重新折行（`BufferReflow` 移植 + `reflow-cases.js`，含 `windowsPty` 两种）。
- 流量控制：示例的高低水位（§12.3），`Write` 回调顺序测试。
- 性能：整屏上滚的缓存平移、字形缓存命中统计、切片预算调优；四个 widgetset 的实测数字写回本规格。
- `MinimumContrastRatio`（§10.9）；盲文、Powerline、Legacy Computing 自绘字形要不要做在这期定。
- **做完能看到**：拖窗口宽度时长行重新折回、缩回来复原；`cat` 几十 MB 的日志界面不卡死、内存不涨；打开最低对比度后浅色皮肤上的暗色文字变清楚。
