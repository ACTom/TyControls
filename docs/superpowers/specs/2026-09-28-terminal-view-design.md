# 终端控件 TTyTerminalView —— 设计规格

> 状态：已定稿（用户 2026-09-28 审过，§17.1 全部按建议），分支 feat/terminal · 上游：xterm.js 6.0.0（`D:/Projects/xterm.js`，commit `c58ea36`）· 需求来源：用户口头（2026-09-23 立项，2026-09-28 逐段确认）

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

### 3.2 脏行与重画

- 核心每改一行就把行号并进脏区间（上游 `_dirtyRowTracker.markDirty`，`InputHandler.ts:534`），解析完一片后发一次 `OnRefreshRows(First, Last)`。
- 控件只 `Invalidate` 这几行的矩形；操作系统合并无效区，一帧最多画一次。上游同样只记 `[start, end]` 区间、一帧画一次（`xterm:src/browser/RenderDebouncer.ts:34-51`）。
- **同步输出（DECSET 2026）**：模式开着时只攒脏行不画，关掉时一起画；1 秒没关就强制关掉再画（`xterm:src/browser/services/RenderService.ts:22`、`:162-167`、`:359-363`）。

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

### 4.2 决定：从上游 dump 生成，不从 Unicode 官方数据生成

脚本 `tools/terminal-oracle/gen-unicode-tables.js` 在 node 里加载上游的四个 provider，对 0..0x10FFFF 每个码位取 `wcwidth` 和 15 表的原始 `getInfo`，压成区间表，写出 `source/tyControls.Unicode.Width.Data.inc`。

理由：
1. 目标是和 xterm.js **逐位一致**，不是和某个 Unicode 版本一致。6 带手工修补、11 没有出处，从 UCD 重新生成**一定**和上游对不上，也说不清差在哪。
2. 15 的表本来就是从 UCD 生成的，dump 出来就是那份数据，还省掉移植第三方解压器（它们没有许可头，`third-party/*.ts` 里 grep 不到 License / Copyright）。
3. 一份脚本、一种做法覆盖四个版本；以后要加 Unicode 16，再写一个从 UCD 生成的脚本，用同一套测试对照。

「和 shell 的 wcwidth 对上」靠**选对版本**：宿主按目标系统选 6 / 11 / 15（§9.1 `UnicodeVersion`），控件不猜。

生成的 `.inc` 进库、进 git；脚本头部写明上游路径、commit、生成时间。表有改动时重跑脚本，`git diff` 必须只动 `.inc`。

### 4.3 ambiguous 宽度

- 15 / 15-graphemes：照上游，`AmbiguousWide = True` 等于把 provider 的 `ambiguousCharsAreWide` 设为 true（`UnicodeGraphemeProvider.ts:13`、`:37`、`:67`）。node 脚本可以直接改这个字段，所以两种设置都有期望值。
- 6 / 11：上游没有这类数据。**建议**：这两个版本下 `AmbiguousWide` 不起作用，文档写明（待拍板，§17 用户问题 2）。另一种做法是借 15 表的 ambiguous 类，但那就没有上游基准了。

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

### 5.2 有界

| 上限 | 值 | 出处 | 超出时 |
|---|---|---|---|
| 参数个数 | 32 | `Params.ts:78` | 后面的丢弃（`:160`） |
| 子参数总数 | 32（硬上限 256） | `Params.ts:78`、`:13-15` | 丢弃（`:183`） |
| 参数值 | 0x7FFFFFFF | `Params.ts:11` | 截到上限（`:168`、`:246`） |
| 中间字节 | 2 个 | `EscapeSequenceParser.ts:255-256` | 照上游 |
| OSC / DCS / APC 载荷 | 10,000,000 | `parser/Constants.ts:65-67`；`OscParser.ts:196-237` | 标记超限，结束时处理器收到失败、不执行 |

坏序列、超长序列的测试断言的就是这几条：喂完之后内存和状态都在上限以内，后续正常序列照常工作（§13.4）。

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

### 7.3 颜色请求

OSC 4 / 10 / 11 / 12 设置和查询、OSC 104 / 110 / 111 / 112 复位（`InputHandler.ts:293-325`）。上游核心只发事件，由浏览器层拿主题色应答或改色（`CoreBrowserTerminal.ts:211-258`）。
我们把**覆盖表**放在 Core：程序设置的颜色存成「第 n 色 → RGB」，复位就删掉；查询时 Core 问控件要基准色（事件 `OnQueryBaseColor`），有覆盖用覆盖。渲染取色也走同一处：覆盖表优先，其次主题。
颜色主题查询（`CSI ? 996 n`）照上游用前景 / 背景亮度比较决定报深 / 浅（`CoreBrowserTerminal.ts:261-`）。主题切换时控件调 `Core.NotifyColorSchemeChanged`，开了 2031 就发通知。

### 7.4 未处理的 OSC

核心注册的 OSC 只有 0 / 1 / 2 / 4 / 8 / 10 / 11 / 12 / 104 / 110 / 111 / 112（`InputHandler.ts:286-325`）。52 由控件注册（§9.6.3）。其余一律进 `OnOsc(Ident, Data, var Handled)`——7（当前目录）、133 / 633（shell 集成）、1337 等由宿主处理。宿主也可以直接 `Core.Parser.RegisterOscHandler`。

### 7.5 鼠标协议状态

照 `MouseStateService`（`xterm:src/common/services/MouseStateService.ts`）：五种协议及其过滤（`:13-82`）、事件码（`:92-113`）、三种编码（`:121-151`；默认编码超过 223 就不报，`:133-135`）。
上报前的过滤照浏览器层 `_triggerMouseEvent`（`MouseService.ts:497-545`）：去掉无意义组合、坐标转 1 起、移动事件按格（像素编码按像素）去重、协议限制、编码。控件把 LCL 鼠标事件换成 `TTyTerminalMouseEvent` 交给 `Core.TriggerMouseEvent`，Core 决定发不发、发什么。

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

---

## 9. 控件 `TTyTerminalView`

`TTyTerminalView = class(TTyCustomControl, ITyTextEditActions, ITyImeEditable, ITyScrollBarFrameHost)`
（基类 `source/tyControls.Base.pas:330`；三个接口见 §9.6、§9.9、§9.7。）

构造：`ControlStyle + [csOpaque, csDoubleClicks, csTripleClicks]`，`TabStop := True`，建 `FCore`。**构造里不建滚动条**，第一次排布时再建（照 `TTyMemo.UpdateScrollBar`，`source/tyControls.Memo.pas:2372-2504`）。

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

### 9.3 公开方法

`Write`（两个重载，转 `Core.Write` 并负责排片）、`WriteSync`、`Paste(const AText)`（走粘贴编码）、`Input(const AText)`（当作键入）、`Clear`（清滚回）、`Reset`、`ScrollLines` / `ScrollPages` / `ScrollToTop` / `ScrollToBottom`、`SelectAll` / `ClearSelection` / `Select(ACol, AAbsRow, ALength)` / `SelectLines`、`CopyToClipboard` / `PasteFromClipboard`、`CellAt(X, Y): TPoint`、`CellRect(ACol, ARow): TRect`。

### 9.4 键盘

- **顺序**：LCL 先调控件的 `KeyDown`（`KeyDownBeforeInterface` → `KeyDown`，`lcl:include/wincontrol.inc:5750-5753`、调用点 `:5883`），**之后**才查窗体和菜单快捷键（`:5888`）、再走 Tab 导航（`DoRemainingKeyDown`，`:5922-`）。所以控件在 `KeyDown` 里把 `Key` 清零，就压过了窗体上的 Ctrl+C、Tab 切焦点。
- **终端吞哪些键**：`TyTerminalEvaluateKey` 有结果的键都吞，包括 Tab、Shift+Tab、Esc、方向键、F1–F12、Ctrl+字母。
- **放行**：吞之前发 `OnShortcutQuery`，宿主把 `APassToApplication` 设成 True 的键保持原样往下走（窗体快捷键、Tab 导航照常）。默认什么都不放行（§17 问题 6）。
- **复制粘贴快捷键**：Windows / Linux 上 Ctrl+Shift+C / Ctrl+Shift+V、Ctrl+Insert / Shift+Insert；macOS 上 Cmd+C / Cmd+V。Ctrl+C 不劫持（它是中断）（§17 问题 5）。
- **本地翻页**：Shift+PgUp / PgDn 翻滚回（`Keyboard.ts:207-225`），Shift+Home / End 到顶 / 到底（定稿时新加）。
- 用户键入时，若视口不在底部且 `ScrollOnUserInput`，滚回底部（`CoreService.ts:80-84`）；有选区就清掉（上游挂在「用户输入」事件上，`xterm:src/browser/services/SelectionService.ts:139-143`）。

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
- 备用屏没有滚回，滚动条禁用（AutoHide 时藏起）；切回主屏恢复。
- 新输出到来：视口在底部就跟着走；不在底部就不动（上游同，`YDisp` 只在 `YDisp = YBase` 时跟随）。

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

### 9.10 焦点、光标闪烁、设计期

- `DoEnter` / `DoExit`：`Core.ReportFocus`；重画光标（聚焦时实心，失焦按 `CursorInactiveStyle`）。
- 闪烁：懒建 `TTimer`（照 `Edit.pas:574-590`），周期 600ms（上游 WebGL 渲染器的值，`addons/addon-webgl/src/CursorBlinkStateManager.ts:13`）；5 分钟没有输入输出就停在「显示」（上游 `CURSOR_BLINK_IDLE_TIMEOUT`，`src/browser/renderer/shared/Constants.ts:12`）。每次只标光标所在行脏。
- 设计期（`csDesigning`）：不建计时器、不建滚动条；画几行示例文字，覆盖 16 色和粗体 / 下划线，方便在设计器里看主题效果。

---

## 10. 渲染

### 10.1 管线

- 控件持有一张**视口大小的行缓存位图**（`TBGRABitmap`，不透明）。
- 脏行（§3.2）重画进缓存：先铺每格底色（含选区、反显），再画字形，再画下划线 / 删除线 / 上划线，最后画光标。
- `Paint` 只把缓存的无效区贴到画布（`Draw(..., Opaque = True)`）。不用 `TTyPainter` 每帧新建整张位图（`source/tyControls.Painter.pas:1301`）——外框、滚动条角落这些仍走 `TTyPainter`。
- 缓存不经 `TBitmap` 中转；万一要中转，用 pf24bit（[[opaque-device-cache-pf24bit]]：pf32bit 在 GTK2 上整块黑）。
- 5 期：整屏上滚时先把缓存内容整体上移，只画新露出的行。

### 10.2 单元格度量

- 字号 → 像素：`TyFontHeightPx(Size, PPI)`（`Painter.pas:1174` 同一换算）。
- 格宽：量 32 个 `W` 的总宽除以 32（上游量 `W`，`xterm:src/browser/services/CharSizeService.ts:86`、`:115`），向上取整到整数设备像素，再加 `LetterSpacing`（按 DPI 缩放）。整数格宽保证网格对齐。
- 格高：BGRA 字体度量的 `Lineheight`（`bgra:bgrabitmaptypes.pas:412-425`）× `LineHeightPercent`，向上取整；基线取同一记录的 `Baseline`。
- 格子数 = (客户区 − 内边距 − 滚动条) / 格尺寸，向下取整；变了就 `Core.Resize` + `OnGridResize`。

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

### 10.4 字形缓存

- 键：簇的 UTF-8 串 + 粗体 + 斜体 + 占格数（1 / 2）+ 用哪个字体（主 / 宽）。颜色不进键（按 E2 的（a））。
- 值：alpha 遮罩（8 位）和它相对格子左上角的偏移。字形比格子宽时水平压缩进格子（上游 `rescaleOverlappingGlyphs` 的思路，`typings/xterm.d.ts:234-249`）；比格子高时不压、按格子裁。
- 容量：4096 项，满了按最近最少使用淘汰（定稿时新加）。字体、字号、DPI、`AmbiguousWide` 变了整个清空。
- 空格和空格子不进缓存。

### 10.5 自绘字形

制表符（U+2500–257F）和块元素（U+2580–259F）不用字体画，按单元格几何自己画，保证相邻格连成线（上游 WebGL 渲染器默认这么做，`addons/addon-webgl/typings/addon-webgl.d.ts:54-75`；定义表 `addons/addon-webgl/src/customGlyphs/CustomGlyphDefinitions.ts`，MIT，可移植数据）。3 期做这两段；盲文、Powerline、Legacy Computing 5 期再定。

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

---

## 12. 示例 `examples/terminal`

### 12.1 形态

照库内示例规矩（[[examples-must-be-lfm-titlebar-skin]]）：`TTyForm` + `.lfm` + 真 `TTyTitleBar` + 运行时换肤、明暗切换（模板 `examples/memo/umain.pas`：`:28-29`、`:98-130`）。

- **回放**：打开录制文件，按原节奏 / 加速 / 一次喂完播放；`ReadOnly = True`。录制格式建议 asciicast v2（每行一个 JSON：头部含宽高，事件 `[时间, "o", 数据]`；本机没有 asciinema 源码可核，格式以其官方文档为准，§17 问题 11）。示例自带几段录制（`examples/terminal/recordings/`）。3 期另加一个「键码面板」：把 `OnData` 的字节以十六进制列出来，回放模式下验键盘编码。
- **真 shell**（4 期）：Windows 起 `cmd` / `powershell`，Linux / macOS 起 `$SHELL`；菜单里可以改命令行。
- 菜单：打开录制、回放速度、新建 shell、复制 / 粘贴、字号、Unicode 版本、ambiguous 宽度、OSC 52 策略、换肤、明暗。

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

### 13.2 目录

| 路径 | 内容 |
|---|---|
| `tools/terminal-oracle/*.js` | 生成脚本，一类一个：`gen-unicode-tables.js`（§4.2）、`unicode-cases.js`、`url-cases.js`（4 期）、`parser-cases.js`、`core-cases.js`、`escape-files.js`、`recordings.js`、`fuzz.js`、`keyboard-cases.js`、`mouse-cases.js`、`reflow-cases.js`（5 期）；共用的导出代码放 `lib-dump.js` |
| `tools/terminal-oracle/cases/*.js` | 手写用例的输入（序列 + 尺寸 + 步骤），不含期望值 |
| `tools/terminal-oracle/recordings/*.cast` | 真实程序录制（每份 ≤ 256KB，§17 实现问题 8） |
| `tests/fixtures/terminal-<name>.json` | 生成的夹具（输入 + 期望值），照 AdvChart 的平铺命名（`tests/fixtures/advchart-*.json`） |
| `tests/test.unicode.width.pas`、`tests/test.terminal.parser.pas`、`…buffer.pas`、`…core.pas`、`…keyboard.pas`、`…mouse.pas` | 基准比对 |
| `tests/test.terminal.view.*.pas` | 3–5 期控件测试 |

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

### 13.5 夹具纪律（AdvChart 的教训照搬）

出处：`D:/Projects/ty-advchart/docs/superpowers/specs/2026-09-01-advancechart-tier0.md:4785-4792`、[[advchart-upstream-oracle]]。

1. **精确比较**。缓冲的三个字、光标、模式、`OnData` 字节逐位相等；没有容差。
2. **照上游的结果做，不照它注释的意图做**。例：1049 注释说要清备用屏但实际不清（表里 `:1926` 写「不清」，`:1930` 的 FIXME 说应该清）；照结果。
3. **有意的偏离只在一处归一化**：XTVERSION 字符串（§7.2）、合成的颜色应答（§13.4）。脚本和 Pascal 测试各有一个 `Normalize` 函数，只处理这几条，每条带理由。
4. **输入分类**：夹具里每个用例标明来源（`escape-file` / `hand` / `recording` / `fuzz` / `synthesized`），失败时先看类别。
5. **复用路径也要比**：每个用例在 Pascal 侧跑两遍——一次 `Reset` 后重跑、一次新建 Core——结果都要对（照 AdvChart「先 Invalidate 再画一次」那条）。
6. **上游自己崩的输入**没有答案：删掉用例并在脚本里记一行。
7. **生成可复现**：脚本不读时间、不用未种子化的随机数；重跑脚本 `git diff` 应为空。

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
- **测试夹具**：`escape_sequence_files` 的输入来自 xterm.js 仓库（MIT），其中部分期望文本注明取自另一个项目（`NOTES` 的「text used from … vt100-parser」一行）；我们只取 `.in` 输入、期望值由上游生成，但输入字节进了夹具，在 notices 里加「测试夹具」一小节（§17 实现问题 9）。

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

---

## 17. 开工前要定的问题

### 17.1 要问用户的

> **已定（2026-09-28）**：用户回复「按你说的做」，以下 11 条全部按建议。另：用户明确不想引入第三方库——Unicode 表编译进库（§4.2），运行时不依赖 ICU 或任何外部库。

1. **默认 Unicode 版本**。建议 `tuv11`：6 太老，表情和很多 CJK 扩展区都算错；15-graphemes 上游自称实验性（`addons/addon-unicode-graphemes/README.md:3`）。
2. **6 / 11 版本下 `AmbiguousWide` 怎么办**。建议不起作用、文档写明，这样每种组合都有上游基准（§4.3）。
3. **字体从哪来**。建议：主题键 `TyTerminal` 的 font-family / font-size（token 默认 `monospace` + 基础字号），实例覆盖按「字体覆盖通道」需求的规则就地实现（`ParentFont = False` 且字段非出厂值才生效），那个需求落地后并入公共 helper（§10.3）。
4. **16 色默认值**。深底用 xterm.js 的 Tango（已核实，`xterm:src/browser/Types.ts:183-203`）。浅底那套建议：同色相、逐色调暗到对白底对比度 ≥ 4.5:1（0 黑、7 白、8 亮黑、15 亮白除外），3 期用脚本算出后写死进 light.tycss，出 17 主题截图给你拍板。
5. **复制粘贴快捷键**。建议 Win / Linux：Ctrl+Shift+C / V 和 Ctrl+Insert / Shift+Insert；macOS：Cmd+C / V；Ctrl+C 永远发给程序。
6. **Tab 和窗体快捷键**。终端默认吞掉 Tab 和所有有编码的键，焦点只能靠鼠标或宿主放行的键离开；`OnShortcutQuery` 让宿主逐键放行（§9.4）。要不要给一个默认放行的键（比如 Ctrl+Tab）？建议不给，交宿主。
7. **1007**。建议只做属性 `AlternateScroll`、不认 DECSET 1007，保持和上游逐位一致（§9.5.4）。
8. **程序接管鼠标时怎么弹菜单**。建议覆盖键 + 右键弹控件菜单（§9.5.2）。
9. **Linux PRIMARY 和 `CopyOnSelect`**。建议 Linux 上选完总是写 PRIMARY、中键粘贴 PRIMARY；`CopyOnSelect`（写系统剪贴板）默认关。
10. **列选择**。建议 4 期照上游做 Alt+拖动（macOS 上 Option 是覆盖键时不做）。
11. **回放格式**。建议 asciicast v2，示例和基准脚本共用同一批录制。

### 17.2 实现层面的（计划里定，不必问）

1. `TTyTerminalCore` 用 `TObject`（§7.1）。
2. 非主线程 `Write` 抛 `EInvalidOperation`（§3.5）。
3. 字形遮罩做法由 E2 定，默认（a）（§10.3）。
4. 字体回退由 E1 定，缺 CJK 时加 `--terminal-font-family-wide`（§10.3）。
5. Unicode 表的存放：15 表 dump 成区间数组 + 二分；6 / 11 的 BMP 部分建 64K 字节查表（同上游，`UnicodeV11.ts:197-211`），在 `initialization` 里建。
6. 解析器转移表在 `initialization` 里照上游代码生成（§5.1），不写成常量数组。
7. 组合内容的稀疏存储：每行一个按列号排序的小数组（行里组合格很少），不上字典。
8. 录制文件每份 ≤ 256KB，夹具 JSON 单个 ≤ 2MB；超了就拆用例。
9. `escape_sequence_files` 进夹具前核对那份外部来源的许可（§14）。
10. Unicode 许可原文 1 期从 unicode.org 取（§14）。
11. XTVERSION 的字符串格式：`TyControls(3.1.0)`，版本取 `TyVersion` 常量（`source/tyControls.Types.pas:111`）。

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
