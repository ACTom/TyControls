# 终端控件 TTyTerminalView —— 设计规格

> 状态：已定稿（用户 2026-09-28 审过，§17.1 全部按建议）；1 期已签收（2026-09-28，记录在 1 期计划末尾）；2 期已签收（2026-09-29，记录在 2 期计划末尾）；3 期已签收（2026-09-29，记录在 3 期计划末尾，真机与截图验收随各期一次做完）；4 期已签收（2026-09-29，记录在 4 期计划末尾）；5 期已签收（2026-09-30，记录在 5 期计划末尾，3–5 期真机项合成一份验收文档 `docs/superpowers/plans/2026-09-29-terminal-acceptance.md`）；五期的实现期修正都已写回各节原处；**6 期（独立配色方案）2026-09-30 用户拍板、规格补在 §11.1**，计划 `docs/superpowers/plans/2026-09-30-terminal-phase-6.md`，做完和 1–5 期一起验收，分支 feat/terminal · 上游：xterm.js 6.0.0（`D:/Projects/xterm.js`，commit `c58ea36`）· 需求来源：用户口头（2026-09-23 立项，2026-09-28 逐段确认）

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

**实现期修正（4 期）**：
11. **上游选区记坐标，不记标记**：`selectionStart` / `selectionEnd` 是 `[列边界, 绝对行]`，输出把行挤出头部时只靠 `onTrim` 减行号（`SelectionModel.ts:123-144`），插删行故意不跟（`SelectionService.ts:780-783`）。§9.5.5 照此改。
12. **上游复制本来就用平台换行**：`SelectionService.ts:259` 是 `isWindows ? '\r\n' : '\n'`，和 FPC 的 `LineEnding` 一样，不是偏离（§9.6.1、§15 照此改）。
13. **上游的链接比原先写的多一层过滤**：网址正则的每个匹配还要过 `isUrl`——`new URL` 解得出、且原文以规范化后的「协议//用户@主机:端口」开头（`WebLinkProvider.ts:44-55`）；OSC 8 在没有 `allowNonHttpProtocols` 时，非 http(s) 的链接在提供者里就不返回（`OscLinkProvider.ts:64-75`：不下划线、不能点），不是激活时才拒绝。§9.8 照此改。
14. **上游悬停不要修饰键**：指针移到链接上就下划线、变手形，单击（按下和抬起在同一条链接上）就激活（`Linkifier.ts:217-233`、`:246-310`）。我们要按着 Ctrl（macOS Cmd），是偏离，进 §15。

**实现期修正（5 期）**：
15. **折行开关看的是字段 `_hasScrollback`**（`Buffer.ts:310-316`），不是 getter：`Scrollback = 0` 的主屏也折；给了构建号时只有 ConPTY 且 ≥ 21376 才折，`{winpty, 构建号}`、`{无后端, 构建号}` 也不折；没给构建号一律折（§6.2）。
16. **`reflowCursorLine` 默认 false**（`OptionsService.ts:50`）：光标所在的那段折行两个方向都不动，提示符后正在打的长命令拖宽后仍是两行（§6.2、§7.6）。
17. **上游改列数不清选区**：`SelectionService.ts:158-162` 只看行数；折行插删不跟，只随 `onTrim` 上移（§9.5.5）。
18. **上游改尺寸清掉悬停的链接**（`Linkifier.ts:47-50`），指针形状跟着复位（`:355-357`）（§9.8）。
19. **两个渲染器在对比度上有三处不同**：反显加默认前景时，DOM 拿前景比前景，WebGL 比画出来的两个颜色（`TextureAtlas.ts:399-417`）；暗淡的格调过对比度后两者都不再变淡（WebGL 在叠透明度之前返回，`TextureAtlas.ts:352-356`；DOM 的内联色盖过 `.xterm-dim`，`DomRenderer.ts:201-203`）；选区字色落在暗淡的格上，WebGL 变淡、DOM 不变淡。我们取 WebGL 的比法、DOM 的选区字色（§10.9）。
20. **上游 `_reflowSmaller` 会写负下标**（`Buffer.ts:504-510`，`lines.set(i--, …)`）：环形表起点大于 0 时（滚回满了）变窄，负下标取模后落在最后几行，提示符那一行变成顶上被挤掉的那行。我们不照搬（§6.2、§15）。
21. **Win32 上排队的异步调用会饿住绘制和输入**：LCL 的 `QueueAsyncCall` 投一个 `WM_NULL`，应用窗口在 `PeekMessage` 循环里派发它时就跑异步队列（`lcl:interfaces/win32/win32callback.inc:2062-2068`）。一片接一片地排，线程队列里总有一条投递的消息；`WM_PAINT` 只在队列空时给，键盘鼠标也排在投递消息之后。原稿 §3.1「已经提交的 `WM_PAINT` 会先被处理」在 Win32 上不成立：5 期实测 50 MB 灌入的前 3.4 秒窗口一次也没画（§3.1）。

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

**实现期修正（4 期）**：
- 新增两个纯逻辑单元，都进运行时包、不引 LCL：`tyControls.Terminal.Selection`（`SelectionService.ts` / `SelectionModel.ts` 的非 DOM 部分——取词、取行、拖动、trim、选区文本；像素到选区点、拖动滚速；OSC 52 编解码）、`tyControls.Terminal.Links`（网址扫描与 `isUrl`、OSC 8 段、去重叠、命中判定）。依赖只有 `SysUtils`、`Classes`、`Types`、`Terminal.Buffer`、`Unicode.Width`，Links 另引 Selection（链接范围的类型）。
- 控件单元长到约 3700 行，鼠标路由、选区胶水、链接、OSC 52、右键菜单五段原样搬进 include（`tyControls.Terminal.View.Mouse / Selection / Links / Osc52 / Menu.inc`），照 Core 的做法不进 `.lpk`。控件是自己写的，这五个也不进 notices 标题；发版守卫查它们随包发出。
- PTY 单元仍只在示例里，四个：`uptysession`、`uptywin`、`uptyunix`、`ushell`（§12.2）。

**实现期修正（5 期）**：
- 新 include `tyControls.Terminal.Buffer.Reflow.inc`（`BufferReflow.ts` 的五个函数、`Buffer.ts` 的 `_reflow*`，由 `Buffer.pas` 引入）；新生成物 `tyControls.Terminal.Luminance.inc`（`contrast-cases.js` 算出的 256 项线性化表，按 IEEE 位模式写）。两个都不进 `.lpk`，notices 标题和发版守卫逐个列名。
- 亮度函数留在 Core：Core 回答明暗配色查询本来就用它，而且 Core 不依赖 LCL；`Terminal.Render` 的对比度函数引用 Core 的这一份。

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
~~LCL 的异步调用在 `Application.ProcessMessages` 里排在 `AppProcessMessages` 之后（`lcl:include/application.inc:449-453`），空闲时在 `Idle` 里跑（`:469-471`）——已经提交的 `WM_PAINT` 会先被处理，渲染有机会追上，和上游「setTimeout 0 让渲染追上」同一个意思。~~（5 期实测不成立，见下面 5 期修正与 §1.1 第 21 条。）

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

**实现期修正（5 期）**：
- **块内切片**：一片（`ProcessPending`）把一块按 `TyTermSlicePieceBytes`（32 KB）一段交给解析器，段与段之间看预算，一块没解析完就记下块内位置（`HeadChunkParsed`）、让出。~~按 131072 字节（`MAX_PARSEBUFFER`）分段~~ 审查后和 `MAX_PARSEBUFFER` 脱钩：128 KB 一段时预算只能在一段解析完才看，一片常超出 6–8 ms；32 KB 一段超出 1–2 ms。`WriteSync` 和改尺寸前的清空仍按 128 KB 一段。上游整块一次解析（`WriteBuffer.ts:224-297`），是偏离（§15），结果状态和整块相同（夹具证明）。
- 细则：块的回调在最后一段之后才调；事件里延后的调用等整块处理完、回调之后才执行，不在段与段之间；`PendingBytes` 按段减；`OnRefreshRows` 每段一次；某段里处理器抛异常时这一块剩下的算已处理、回调照调；`WriteSync`、`Resize` 前的清空从块内位置接着解析；`DiscardPending` 连同半块一起丢、不调回调。
- **一片多长、什么时候画**（控件，审查后改）：~~距上次绘制不到 16 ms 就接着跑下一片~~ 输出一直排着时，解析加绘制一轮约 50 ms（`FloodCycleMs`）：留给解析的时间 = 50 ms 减上一帧 `RenderTo` 花的时间，至少 3 ms；每次 `ProcessPending` 的预算是离这一刻还剩多少（好久没画过——隐藏、无头——就按上游的 12 ms）。按 16 ms 一帧算时，整屏新行一帧 15–20 ms、贴上屏后 DWM 还占十几毫秒，解析只剩 3 ms，50 MB 灌入掉到 1.4 MB/s；50 ms 一轮时约 5 MB/s、两次绘制隔 50–85 ms（§16）。到点还有没解析的，**当场画这一帧**（`Update`，Win32 上是 `UpdateWindow`），再排下一片：只靠排队，Win32 上窗口在整个灌入期间一次也画不上（§1.1 第 21 条）。Win32 上键盘、鼠标按键在排队时，下一片改走 1 ms 的计时器（`WM_TIMER` 排在输入和绘制之后），先让输入进来。还有输出排着时，一帧光栅化新字形的预算从 10 ms 降到 4 ms（这时的行很快滚走，新字形多半白画）。
- 预算调优（Task 9）：一次改一个（写超时 8 / 12 / 16、帧 16 / 33、光栅 5 / 10），没有一组吞吐高出 10%，写超时维持 12 ms。灌入时两次绘制的间隔见 §10.1 与 §16。

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

**实现期修正（5 期）**，行复用（整屏上滚只画新露出的行）：
- 每个视口行记一个键：行对象的 `Serial`（出生时从类计数器取、永不重复，不怕地址复用）、`Revision`（每个改内容的方法加一，`IsWrapped` 不算）、压在这一行上的东西——选区列段、悬停链接列段、光标（列、形状，不显示时 −1）、组字串和它画在哪一列（光标闪灭、DECTCEM 时组字串照样画，横移光标只有这一列在变，审查后补进键里）。
- 每帧：键和上一帧同一行相同就不动；和上一帧另一行相同就把那一行的像素搬过来（画过阴影 ░▒▓ 的行只在位移 × 格高是图案纵向周期的倍数时搬）；都不是才画。光栅预算超了的行键作废，下一帧重画。底边被表面截掉的行（排着的网格比客户区大）键也作废，不当搬运的源（审查后补的）。
- 帧级参数（色表、度量与字体、PPI、列数、聚焦、粗体变亮、网格位置、最低对比度）一变，全部键作废、整屏重画。
- 滚动不再整屏标脏，只失效网格区让 `Paint` 贴一次；同步输出攒着时不搬也不画，只贴图。
- 行绘制和搬运都裁到外框里面（审查后补的：排着的网格比客户区大时不压右边、下边框）。
- ~~帧率上限：距上次绘制不到 16 ms 就接着跑下一片~~ 输出排着时一轮约 50 ms、到点当场画（§3.1）；光栅化预算输出排着时 4 ms。

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

**实现期修正（5 期）**：
- ~~Windows ConPTY 版本号低于 21376 时上游关掉折行~~ 实际规则（§1.1 第 15 条）：给了构建号（本仓库 `BuildNumber <> 0`）时，只有 ConPTY 且 ≥ 21376 才折；没给一律折，包括 `{conpty}`；看的是主缓冲的字段 `FHasScrollback`，`Scrollback = 0` 的主屏也折；备用屏不折。上游的 `{conpty, 0}` 会同时开启发、开折行，本仓库 0 = 没给，表达不了这个组合（没有意义的输入，§15）。
- ~~2–4 期折行恒关~~ 5 期接上：`Buffer.Reflow.inc` 逐行照上游移植，事件次序和下标照抄，重排前把要搬的行全部钉住（环形表按原始下标清槽，起点不为 0 时清掉的可能是还要搬的行）。2 期绕开折行的改列数用例补了默认配置的镜像。
- 光标所在的那段默认不动（`reflowCursorLine`，§7.6）。
- 一列：`TyTermReflowSmallerGetNewLineLengths` 只在上游真会死循环的地方（宽字符落在切口、一列放不下）抛 `EArgumentOutOfRangeException`；另两处对应上游抛 TypeError 的地方（越过折行段、段里的行不够）也抛。入口不查列数：上游自己的用例会改到 1 列。Core 的最小列数是 2，碰不到。
- **上游的负下标 bug 不照搬**（§1.1 第 20 条）：`_reflowSmaller` 重排时下标小于 0 的新行不写。node 基准脚本对上游同一处打运行时补丁（`lib-dump.js` 读 `out/common/buffer/Buffer.js` 的文本、把那一句加上判断后在内存里编译，被跟踪的文件不动，补丁点找不到或不止一处就拒绝；`XTERM_UNPATCHED=1` 跑原样的上游），新增用例 `full-scrollback-narrow-keeps-the-prompt`；原有夹具重生成后一个字节没变（这个 bug 没有别的用例碰到）。
- **改尺寸合并**（控件）：`Scrollback` 10000、200 列两行一折时一次改尺寸 125 / 61 / 65 ms（200 → 120 → 200 → 80 列；审查后加了 `CopyCellsFrom` 的快路径，降到 48 / 33 / 32 ms），超过 50 ms，做了合并——有窗口时客户区一变，新网格先记下、排一次异步调用，消息循环里才 `Core.Resize`，只按最后的尺寸折一次；排着时照旧按 Core 的旧网格画。没有窗口（隐藏、测试、设计器）当场改。~~要新网格的入口（`Cols`、`Rows`、`Core`、`CellAt`、`CellRect`、`SizeForGrid`、`Write`、`WriteSync`、`Paste`、`Input`）先应用~~ 审查后只剩问几何的入口（`Cols`、`Rows`、`CellAt`、`CellRect`、`SizeForGrid`）和 `WriteSync`：程序收到改尺寸几乎一定输出，`Write` 每次都应用就退化成每一步折一次；排着时 `Core` 仍是旧网格（§9.3）。释放中不应用。Win32 的模态拖动循环会派发排着的异步调用，合并在真拖动时到底有没有效，进真机验收（用户已定：保留合并，真机再看）。
- **行内存回收**（审查后补的）：~~内存回收调度本身没有可观察行为，不移植~~（§6.3 的 2 期修正）先变宽再变窄后，每行都留着宽的分配（10 万行 × 400 列约 480 MB）。照上游：`Resize` 数出分配超过两倍用量的行，超过总行数的十分之一就逐行 `CleanupMemory`（上游在空闲时每批 100 行，这里当场做完，只差在时机，§15）。1 万行 80 → 400 → 80 列，堆回到原处（测试守着）。

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

**实现期修正（4 期）**：`TTyTerminalBuffer` 加纯查询 `TrimmedLines: Int64`——环形表每次 `OnTrim` 把行数累加上去，选区按差值追（§9.5.5），不在缓冲上挂事件。Core 的 REP 快进跳过的那段滚动不发环形表事件，所以不计；快进要先真滚过两倍环形表长度才起作用，选区活不过那么久。

**实现期修正（5 期）**：
- `TTyTerminalLine` 加两个纯查询：`Serial: Int64`、`Revision: QWord`（§3.2 的行复用用；~~`Revision: Cardinal`~~ 审查后改 `QWord`：长会话里底部那一行改上 2^32 次，带溢出检查构建会抛异常）。
- 行表加公开的事件触发口 `NotifyInsert` / `NotifyDelete` / `NotifyTrim`（上游的 emitter 本来公开，折行直接触发）；`TrimmedLines` 照旧只在缓冲的 `LinesTrim` 里加，折行的 `onTrim` 也算进去。
- 新增 `CleanupMemory`（`BufferLine.ts:439-446`，§6.2）。
- `CopyCellsFrom` 的快路径（审查后补的）：整段都在两行界内、源的格子都没有组合文本和扩展属性的标志、同一行里的拷贝方向和逐格的顺序一致时，一次 `Move`，结果和逐格相同（测试逐项对照）。1 万行滚回的折行 （200 → 120 → 200 → 80 列）从 125 / 61 / 65 ms 降到 48 / 33 / 32 ms；10 万行 120 → 70 → 120 列约 0.64–0.72 s，和 1 万行成线性。

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

**6 期新增（2026-09-30 用户拍板）**：色表多了一个来源——控件的独立配色方案（§11.1）。取色顺序变成「程序的 OSC 覆盖 > 自定义方案 > 主题 token」：Core 的覆盖表照旧在最前，`OnQueryBaseColor` 答的色表由控件按 `ColorSource` 从方案或主题建。Core 不改：明暗查询（`CSI ? 996 n`）和 2031 通知本来就按 `ResolveColor(256 / 257)`（覆盖优先、其次色表）比亮度，方案进了色表，答的就是实际生效的背景色。换方案、改方案里的颜色、明暗配对随主题换边，都算「色表真变了」，走上面 3 期修正的同一条通知路径（清 OSC 覆盖色、2031 开着就报一次）。

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

**实现期修正（4 期）**：Core 加 `OnUserInput: TNotifyEvent`（上游 `CoreService.onUserInput`，`CoreService.ts:86-89`）：`TriggerDataEvent` 在 `AWasUserInput` 时发，顺序照上游——先滚到底，再 `OnUserInput`，再 `OnData`；`ReadOnly` 时整个早退、不发。控件接管它（清选区），宿主别改写。

**实现期修正（5 期）**：Core 加 `ReflowCursorLine: Boolean`（上游 `reflowCursorLine`，默认 False，只是 Core 属性、不上控件的 published）；`ParseRange`（写入队列一段一段交给解析器）；给测试的纯查询 `HeadChunkParsed`（队首那一块已经解析了多少字节）；常量 `TyTermSlicePieceBytes`（§3.1）。

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

**实现期修正（4 期）**：~~`ITyTextEditActions`（右键菜单）和选区一起在 4 期加~~ 4 期也不实现 `ITyTextEditActions`：那个接口是给编辑框的六项菜单（撤销、重做、剪切……）设计的，`TTyTextEditMenu` 没有加项的口子；终端自建四项菜单（§9.6.4）。~~`csTripleClicks`~~ 多击不靠它（§9.5.5）。构造里设 `CaptureMouseButtons := [mbLeft, mbMiddle, mbRight]`（§9.5.2）。

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
| `MinimumContrastRatio` | ~~Single~~ Double（stored 函数） | 1 | 5 期；1 = 不调（`:43`；`typings/xterm.d.ts:197-207`） |

`WordSeparators` 的构造值写成 Pascal 是 ``' ()[]{}'',"`'``，和上游 `OptionsService.ts:55` 的字符集合逐字相同。

另有 `TTyCustomControl` 惯常的：`Align`、`Anchors`、`BorderSpacing`、`Constraints`、`Enabled`、`Visible`、`TabStop`、`TabOrder`、`PopupMenu`（设了就代替内置菜单）、`Hint`、`ShowHint`、`StyleClass`、`StyleOverride`、`Controller`、`Font` / `ParentFont`（§10.3）。

运行时只读：`Core`、`Cols`、`Rows`、`Title`、`SelectionText`、`HasSelection`。

**实现期修正（3 期）**：
- 本期 published 的是：`Scrollback`（负数按 0，上限 100000 由 Core 钳）、`CursorStyle`、`CursorInactiveStyle`、`CursorBlink`、`AmbiguousWide`、`UnicodeVersion`、`MacOptionIsMeta`、`AlternateScroll`、`DrawBoldTextInBrightColors`、`ReadOnly`、`ConvertEol`、`TabStopWidth`（小于 1 按 1）、`ScrollOnUserInput`、`ScrollBarAutoHide`、`LineHeightPercent`（钳到 100–300；上游小于 1 抛异常）、`LetterSpacing`（钳到 −10–50），外加 `TabStop` 默认 True、`Align`、`Anchors`、`ParentFont`。
- 4 期再加：`SelectionOverrideKey`、`Osc52`、`WordSeparators`、`CopyOnSelect`、`DetectUrls`；5 期：`MinimumContrastRatio`。后加 published 属性不破坏已有的 `.lfm`。
- 运行时只读本期只有 `Core`、`Cols`、`Rows`、`Title`；`SelectionText`、`HasSelection` 在 4 期。
- published 默认值 = 构造值由本控件自己的 RTTI 测试逐个守（全局守卫只查 `TabStop`）。

**实现期修正（4 期）**：4 期 published 的是 `SelectionOverrideKey`、`Osc52`、`WordSeparators`（`stored` 函数，构造值不写进 `.lfm`）、`CopyOnSelect`、`DetectUrls`，外加 `AllowNonHttpLinks: Boolean = False`（非 http(s) 的 OSC 8 算不算链接，§9.8）。运行时只读的 `SelectionText`、`HasSelection` 也在本期。

**6 期新增（2026-09-30 用户拍板）**：配色来源 `ColorSource`（默认跟随主题）、方案对象 `ColorScheme`、明暗配对 `ColorSchemePaired` + `DarkColorScheme`，属性表与默认值见 §11.1.3。

**实现期修正（5 期）**：`MinimumContrastRatio` 用 `Double`：上游是 JS 双精度、钳成一位小数，`Single` 存不住 1.3，比值恰在边界时和上游不同。写入时照上游钳到 1–21、保留一位小数（`OptionsService.ts:188-190`），NaN 和无穷按 1（上游会存 NaN，§15）；`stored` 函数，构造值 1 不写进 `.lfm`，RTTI 守卫另加一条管它。改了清两份对比度缓存、整屏重画。

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

**实现期修正（4 期）**：这三个本期加上（4 期任务里写的 `OnLinkClick` 以本节的 `OnLinkActivate` 为准）。`OnOsc52` 在解析中间同步发：宿主可以弹模态框，**不能在里面释放控件**；事件抛出的异常控件吞掉（§9.6.3）。

### 9.3 公开方法

`Write`（两个重载，转 `Core.Write` 并负责排片）、`WriteSync`、`Paste(const AText)`（走粘贴编码）、`Input(const AText)`（当作键入）、`Clear`（清滚回）、`Reset`、`ScrollLines` / `ScrollPages` / `ScrollToTop` / `ScrollToBottom`、`SelectAll` / `ClearSelection` / `Select(ACol, AAbsRow, ALength)` / `SelectLines`、`CopyToClipboard` / `PasteFromClipboard`、`CellAt(X, Y): TPoint`、`CellRect(ACol, ARow): TRect`。

**实现期修正（3 期）**：
- 新增 `SizeForGrid(ACols, ARows): TSize`：给定网格要多大的客户区（内边距、条宽都算进去）；示例「按录制尺寸」和想固定 80 × 24 的宿主用它。
- `CopyToClipboard` 本期是空操作（没有选区）；`SelectAll` / `ClearSelection` / `Select` / `SelectLines` 和选区一起在 4 期。
- Core 加了 `DiscardPending`：丢掉还没解析的块、不调它们的回调（宿主自己要丢的，流控计数跟着重来；上游 `WriteBuffer` 没有）。回放示例换录制时用。

**实现期修正（4 期）**：`SelectAll` / `ClearSelection` / `Select` / `SelectLines`、`CopyToClipboard`（有选区才写）本期接上。`Select(ACol, AAbsRow, ALength)` 在入口把参数钳进缓冲——列 0..`Cols`、行 0..最后一行、长度 0..到缓冲末尾（上游不查；长度太大时「起点 + 长度」会溢出）。

**实现期修正（5 期）**：改尺寸合并（§6.2）之后，`Cols`、`Rows`、`CellAt`、`CellRect`、`SizeForGrid` 和 `WriteSync` 先把排着的网格应用掉——读这些属性可能当场发出 `OnGridResize`。`CellRect` 的参数若是现算的（右键菜单的光标格、输入法的锚），先应用再算。~~`Core`、`Write`、`Paste`、`Input` 也先应用~~ 审查后不应用：排着的时候 `Core` 仍是旧网格，`Write` 进来的数据按旧网格解析，应用时一起折。

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

**实现期修正（4 期）**：~~`tkrSelectAll` 本期不算动作、不吞~~ 接上了：macOS Cmd+A 全选、吞键，算一次选择结束（PRIMARY、`CopyOnSelect` 照 §9.6.2）。复制快捷键照吞，有选区才写剪贴板，没有选区什么都不写（不把剪贴板清空）。

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

**实现期修正（4 期）**：
- ~~上报时覆盖键本身不算进修饰位——只有它是 Alt 时要剥掉~~ 按着覆盖键时按键、拖动、抬起一律本地处理、根本不上报，剥修饰位无处可用；滚轮照上游带着修饰位上报（上游只在 `mouseEventsRequireAlt` 时剥，滚轮也不剥，`MouseService.ts:175-179`）。
- 路在按下那一刻定（上报 / 本地选择 / 链接 / 中键 PRIMARY / 无），拖动、抬起一直走它，直到所有键松开；中途松开覆盖键、Ctrl 不换路（`MouseService.ts:224-249`；选区服务的 mousemove 监听 `stopImmediatePropagation`）。上报路上别的键按下也照报。
- ~~上报期间用 LCL 鼠标捕获~~ 捕获要显式开三键：LCL 默认只捕获左键（`CaptureMouseButtons = [mbLeft]`，`lcl:controls.pp:1794-1795`），中键、右键拖出控件收不到移动。
- **抬起丢了**（期末审查后新定）：上游在 document 上等抬起，总能等到；LCL 里捕获会被拿走（Alt+Tab、模态框、别的控件 `SetCapture`），抬起也可能落在别的窗口上。控件覆盖 `CaptureChanged` 与 `DoExit`：这次按下要的键确实已经松开（`GetKeyState`）就照 `MouseUp` 收尾——停自动滚、选区松开（PRIMARY、`CopyOnSelect` 照常）、上报路替程序补发抬起（报在最后知道的位置）、路复位；链接不激活、中键不粘贴。键还按着就先不动，抬起也许还会落回来。LCL 的抬起消息自己先放捕获，`CaptureChanged` 先于 `MouseUp` 到（`lcl:include/control.inc:2824-2848`），那一次不算丢。同一个键又按下时它上次的抬起还没来过，也先收尾。各 widgetset 的 `GetKeyState` 对鼠标键答得对不对要真机（第 60 项）。

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

**实现期修正（4 期）**（§9.5.3）：~~控件覆盖 `DoMouseWheelLeft` / `DoMouseWheelRight`~~ 这两个拿不到 `WheelDelta`（`controls.pp:1538-1539`），照竖向按 ±120 累计要覆盖 `DoMouseWheelHorz` 本身，余数和竖向各记各的。程序不收就交还父控件（终端没有横向可滚）：没开上报；或者协议不收滚轮——X10 只报按下，开着上报也不收（`RestrictMouseEvent` 答否，期末审查后补的）；或者满格的那一下没报出去（`TriggerMouseEvent` 答否，比如指针在内边距里）。

#### 9.5.5 本地选择

- 单击拖动：按字符选；双击选词（`WordSeparators`，`SelectionService.ts:1034-1041`）；三击选整行，含折行的连续行（`getWrappedRangeForLine`，`:1047-1057`）。多击用 LCL 的 `ssDouble` / `ssTriple`（`csTripleClicks`，`lcl:controls.pp:306`）。
- Shift+单击扩展选区（程序没接管时；接管时 Shift 已经是覆盖键，按下即新选区——同上游）。
- Alt+拖动列选择（`SelectionService.ts:607-612`）；macOS 上 Option 是覆盖键时不做列选择（上游同一规则，`:611`）。
- 拖到控件上下边外面时自动滚动：离边越远越快，每 50ms 一次、每次最多 15 行、50 像素到顶速（`SelectionService.ts:26-34`、`:654-665`）。
- 选区锚在缓冲行上（标记，§6.2），新输出把行顶上去时选区跟着走（上游 `_handleTrim`，`:386-391`）；行被挤出滚回就清掉选区。
- 清选区的时机照上游：用户输入（上一节）、行数变化（`:157-162`）、程序打开鼠标上报（上游此时停用选择并清空，`:173-176`、`CoreBrowserTerminal.ts:621-624`；覆盖键仍可新选，`SelectionService.ts:471-478`）、切换主备屏。

**实现期修正（4 期）**：
- ~~选区锚在缓冲行上（标记，§6.2）~~ 照上游记坐标（§1.1 第 11 条）：列是 0..`Cols` 的**边界**、行是缓冲的绝对行。缓冲的 `TrimmedLines`（§6.3）在选区建立时记下读数，每次用之前（解析返回后、绘制前、每个鼠标入口）按差值整体上移，终点减成负的就清、起点减成负的改成 `[0, 0]`（`SelectionModel.ts:123-144`）。插删行不跟（上游故意的）。
- ~~多击用 LCL 的 `ssDouble` / `ssTriple`（`csTripleClicks`）~~ 用库的 `TyMultiClickCount`（`ssDouble` 认第二击，时间窗 + 距离认第三击；没有 widgetset 标第三击），和 Edit / Memo 一致。
- 选区点按**像素中心**算：`x = ⌊(2·px + 格宽) / (2·格宽)⌋` 钳到 0..`Cols`，点在一格的右半就从下一格的边界算（上游 `getCoords(…, isSelection = true)`，`Mouse.ts:40-49`，喂 `px + 0.5`）；上报用的格子仍是整除再钳。
- 自动滚的 50 像素按 PPI 缩放（`MulDiv(50, PPI, 96)`）；滚速公式照上游，`Math.round` 写成 `Floor(x + 0.5)`。
- 双击时指针下有链接（OSC 8，或 `DetectUrls` 开时识别出的网址）就选整条（上游 `_selectWordAtCursor`），不要求按 Ctrl。
- 取词沿折行上下接：上游每接一行递归一层（`:952-978`），折了几万行的一个词会把栈用完；这里写成两个循环，结果相同（期末审查后改的）。
- 清选区的时机：用户输入（Core 的 `OnUserInput`，§7.6）；行数变了（列数变不清）；换缓冲（含 RIS、`Reset`，它们都发 `OnBufferActivate`）；程序的鼠标上报协议**每次换成开着的一种**都清（上游每次协议变化都走 `disable()`，`MouseService.ts:380-393`——1000 换 1002 也清，关掉不清；期末审查前只在从无到有时清）；清滚回——最后这条是我们加的（上游 `clear()` 不清，`CoreBrowserTerminal.ts:1075-1089`），进 §15。

**实现期修正（5 期）**：~~列数变不清~~ 列数变了、并且当前缓冲这次真的重新折行时也清（字挪了，选区还框着原来的格子，复制出来是别的字）；不折行时（老 ConPTY、备用屏）照上游保留。是偏离（§15，用户可在验收时改）。折行挤出头部的行照常经 `TrimmedLines` 上移。

### 9.6 选区与剪贴板

#### 9.6.1 复制

`SelectionText`：逐行 `TranslateToString(True, …)`；折行的行之间不加换行，其他行之间加 `LineEnding`（定稿时新加：上游浏览器层用 `\n`，Windows 上贴进记事本要 CRLF）。
剪贴板直接用 LCL `Clipbrd`（库里 `TTyEdit` / `TTyMemo` 也是，`Edit.pas:1841`、`:1846`），读写走两个 virtual 方法，测试可以替换（照 `Edit.pas:260-261`）。

**实现期修正（4 期）**：~~（定稿时新加：上游浏览器层用 `\n`，Windows 上贴进记事本要 CRLF）~~ 上游本来就是平台换行（§1.1 第 12 条），不是偏离。另：NBSP 换成空格；列选区每行取 `[左, 右)`、不看折行，起终列相同是空串。选区文字分两遍拼——先算总长，再一次填好（期末审查后改的：原来逐行把字符串加长，一万行的选区是平方级）；测试守着一万行（一半是一个折了五千行的长行）1 秒内。

#### 9.6.2 Linux PRIMARY

X11 惯例：选完写 `PrimarySelection`（`lcl:clipbrd.pp:236`），中键粘贴 PRIMARY（程序没接管鼠标时）。Wayland 下是否可用要真机（§16）。建议做（§17 问题 9）。

**实现期修正（4 期）**：写入时机是「一次选择结束」：松开左键、双击、三击、Shift+单击扩展、全选之后，选区非空才算（xterm 的惯例；上游浏览器层拖动中每步重写 textarea，那是浏览器的机制）。~~选完写 `PrimarySelection`~~ 期末审查后改成**按需提供**：只登记「有、是文字」（`SetSupportedFormats` + `OnRequest`，SynEdit 的做法），别的程序来要时才取此刻的选区文字；PRIMARY 和 `CopyOnSelect` 都不要时根本不拼文字。控件释放时交出所有权。平台按平台判定（Unix 且非 macOS），不按 widgetset；Wayland 待真机。

#### 9.6.3 OSC 52

控件注册 OSC 52 处理器，解析照 `ClipboardAddon._setOrReportClipboard`（`xterm:addons/addon-clipboard/src/ClipboardAddon.ts:32-`）：`Pc;Pd`，`Pd = ?` 是读，否则 base64 写。
- `Osc52 = to52Off`（默认）：丢弃，不问宿主。
- `to52Write`：写请求先发 `OnOsc52`（宿主可改文本、可拒绝），`AAllow` 默认 True；读请求丢弃。
- `to52ReadWrite`：读请求也发 `OnOsc52`，`AAllow` 默认 **False**（读剪贴板是隐私问题，宿主要显式同意）。

**实现期修正（4 期）**：
- ~~base64 写~~ 解码照上游在 node 下实际走的路：`atob`（WHATWG 的宽容 base64：去掉 ASCII 空白、`=` 可省，长度模 4 余 1 或有非法字符就失败）+ `TextDecoder`（UTF-8，坏序列按最长前缀换 U+FFFD，开头的 BOM 去掉）；解不出来写空串（`ClipboardAddon.ts:54-66`、`:104-124`）。
- 在解析中间同步问宿主：上游读剪贴板是 Promise、解析器停住等它，同步发才能让应答不乱序。应答走 `Core.Input(…, False)`，不算用户输入：不清选区、不滚到底。控件注册的处理器在 `to52Off` 时也吞掉，不进 `OnOsc`。
- 异常隔离（期末审查后新定）：宿主的事件、读写剪贴板（别的程序占着时 LCL 会抛）抛出的异常在处理器里吞掉，这一条作罢——冒出 `Parse` 会丢掉这一块剩下的字节。宿主不能在事件里释放控件。

#### 9.6.4 右键菜单

实现 `ITyTextEditActions`（`source/tyControls.TextMenu.pas:25-45`），复用 `TTyTextEditMenu`（`:67`）：复制、粘贴、全选可用；剪切、撤销、重做灰掉（`TeIsReadOnly` 答 True，`TeCanUndo` / `TeCanRedo` 答 False）。另加「清屏」一项（定稿时新加；resourcestring）。设了 `PopupMenu` 就用它。

**实现期修正（4 期）**：~~实现 `ITyTextEditActions`，复用 `TTyTextEditMenu`~~ 那个菜单固定六项、没有加项的口子。终端自建四项（复制、粘贴、分隔线、全选、清屏），用同一个主题化的 `TTyPopupMenu`；复制、粘贴、全选沿用库里已有的三个字串，只新增「清屏」。没有选区时复制灰；`ReadOnly` 或剪贴板里没有文字时粘贴灰——只问有没有文字（`TyClipboardHasText`），不把剪贴板整段读出来（期末审查后改的）。设了 `PopupMenu` 就由 LCL 弹宿主的。这次右键报给了程序就不弹；各 widgetset 的菜单消息先后不同，菜单先于按下到时按当前的协议和修饰键现算。菜单键弹在光标格左下角；Shift+F10 是有编码的键，照常先发给程序，之后弹不弹看 widgetset（真机第 61 项）。macOS 右键在选区外先选中指针下的词（上游 `rightClickSelectsWord: isMac`），宿主设了 `PopupMenu` 也一样（期末审查后改的）。

### 9.7 滚回与滚动条

- 自己建一根 `TTyScrollBar`，照 `TTyMemo`：`Parent := Self`、`Align := alRight`、`TabStop := False`、`csNoDesignVisible`、宽度取 `--scrollbar-size`、`AutoHide := ScrollBarAutoHide`（`Memo.pas:2384`、`:2410-2420`）。
- 实现 `ITyScrollBarFrameHost`（`source/tyControls.ScrollBar.pas:61-73`），滚动条替控件画外框那一段。
- `Max` 是**最大位置**不是内容高度：`Max = 缓冲行数 − 视口行数`（[[scrollbar-max-is-position-not-content]]）。
- 备用屏没有滚回，滚动条禁用~~（AutoHide 时藏起）~~；切回主屏恢复。
- 新输出到来：视口在底部就跟着走；不在底部就不动（上游同，`YDisp` 只在 `YDisp = YBase` 时跟随）。

**实现期修正（3 期）**：条宽**一直扣**——网格宽 = 客户区 − 内边距 − 条宽，备用屏里、`Scrollback = 0` 时条只是禁用、不拿掉（自动隐藏的主题下淡掉，留一条空白），列数不随主屏 / 备用屏变化，进出 vim 不会给程序多发一次改尺寸（开工前问题一第 2 条）。滚动条的同步在一次解析里只做一次（§3.2）。

**实现期修正（5 期）**：重新折行改了行数，滚动条的范围和拇指跟着新的行数走（改尺寸事件里同步一次）。

### 9.8 链接

- 两种来源：OSC 8（缓冲里的链接号，§6.2）；`DetectUrls` 开时按行文本正则识别，正则照 `addon-web-links` 的 `strictUrlRegex`（`xterm:addons/addon-web-links/src/WebLinksAddon.ts:21`），用 FPC `RegExpr` 改写。期望值由 node 直接跑上游正则生成，输入取上游用例（`addons/addon-web-links/test/WebLinksAddon.test.ts:33-188`：各种顶级域名、全角字符前后、带用户名密码、组合字符）再加自己的。
- 悬停：按住 Ctrl（macOS Cmd）时，指针下的链接画下划线（`TyTerminalLink`），光标变手形。
- 激活：Ctrl+单击（macOS Cmd+单击）发 `OnLinkActivate`；控件自己不打开任何东西。上游 OSC 8 默认处理还会弹确认框（`OscLinkProvider.ts:183`），并默认拒绝非 http(s) 协议（`:64`）——这些是宿主的事，示例里演示。
- 程序接管鼠标时，Ctrl+单击仍然优先当链接（定稿时新加：不然全屏程序里的链接点不开）。

**实现期修正（4 期）**：
- ~~用 FPC `RegExpr` 改写~~ JS 的 `\s` 含 Unicode 空白（中文全角空格会截断网址）、正则没有 `u` 标志、按 UTF-16 单元走，`RegExpr` 两样都对不上：改成在 UTF-16 串上手写的扫描器，照正则的回溯走（`TyTermNextUrlMatch`）。每个匹配再过 `isUrl`（§1.1 第 13 条）：`TyTermParseUrlPrefix` 是 WHATWG URL 解析器里 http / https 用得到的那部分，另有一个带 `ANonAsciiHost` 的重载（主机含非 ASCII 时告诉调用方，§15）；`TyTermIsUrl` 对非 http(s) 一律答否。
- ~~上游 OSC 8 默认拒绝非 http(s) 协议（`:64`）~~ 在提供者里就不返回（§1.1 第 13 条）。加 published `AllowNonHttpLinks`（默认 False，照上游）；打开后全交宿主，`OnLinkActivate` 带原样 URI。
- 悬停与激活要按 Ctrl（macOS Cmd），是偏离（§1.1 第 14 条，§15）。按下和抬起在同一条链接上才发 `OnLinkActivate`（`Linkifier.ts:220-233`）。
- 缓冲还不重新折行（5 期），一行可能比网格长：网址的下标回映射按 `ACols` 截断——上游重新折行后行本来就是这个长度；5 期接上折行，这个参数就不再起作用。**实现期修正（5 期）**：~~这个参数就不再起作用~~ 不折行的地方（老 ConPTY、备用屏）行照样比网格长，上游按行的全长映射（`WebLinkProvider.ts:171`），截断反而是偏离：`TyTermComputeUrlLinks` 的 `ACols` 参数删掉。链接下划线仍按网格裁。
- 同一行第一次悬停的结果和上游不同，进 §15。

**实现期修正（5 期）**：改尺寸清掉悬停的链接（`Linkifier.ts:47-50`），重画它占的行，指针形状当场复位（审查后补的，`:355-357`）；指针再动时按新缓冲重新找。

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

**实现期修正（5 期）**：
- ~~整屏上滚时先把缓存内容整体上移~~ 按「视口挪了几行」推算在滚动区域、环形表回收、REP 快进下都会错，改成按行内容认行（§3.2 的行复用）：一行一行上滚时每帧只画新露出的行和光标离开的那一行，其余的行从表面上搬。
- 搬运：所有要搬的行位移相同（一次滚动）时，按先读后写的方向逐像素行一次 `Move`，不经草稿（审查后补的）；位移不一的仍先拷进草稿再写回。
- 数字（`terminalbench --scroll`，200 × 60、96 PPI，2000 行）：每帧画 2.00 行；离屏每帧（整张表面贴一次）4.78 ms（基线 6.94 ms、审查前 5.32 ms）；走 `Paint` 的测法（显示出来的窗口、只画失效区）6.9 ms（审查前 9.2 ms）。原定「耗时 ≤ 基线的 1/4」没达到（要 1.74 ms）；按主控的决定改写为「每帧 ≤ 3 行，耗时不劣于基线」，两种测法都过（§18）。
- 没做、列为以后：环形表面（滚动只改一个行原点偏移，贴图分两次）、屏幕路径用 `ScrollWindowEx` 平移、只失效新行——后者要保证屏幕上的像素和表面一致（失效区没画完就滚、被遮挡的部分），本期不冒这个险。

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

**实现期修正（5 期）**，冷启动光栅化：
- 用户选了 A：改共享的 `Painter.pas`（`TTyGdiTextRenderer` 留一张常驻 GDI 位图、直接读 DIB 的像素，不再每次新建 `TBitmap` 再整张转成 BGRA）；终端的光栅器不动。全库的首帧文字都受益。
- 数字（`terminalbench --raster`）：376 个 ASCII 冷填充 918 → 约 466 ms（每个 2.43 → 1.22 ms），200 个 CJK 461 → 约 276 ms（每个 2.28 → 1.34 ms）；`TextSize` 现在占约一半。原定「每个 ≤ 基线的 1/3」只对 B 路线（终端自己的光栅路径、度量也挪进同一个 DC）成立，改写为「走 A：每个 ≤ 基线的 1/2」（§18），实测 ASCII 0.50、CJK 0.59（五次的中位；这台机器此时负载起伏大，单次 0.48–0.70，Task 9 时量的是 0.47 / 0.53）。
- 常驻位图（审查后改的）：只放大不够的那一维（原来一维不够两维都 ×1.5，一条长行之后几次大字号就是几十 MB）；超过 4 M 像素或宽超过 8192 的一段走一次性位图、画完就放；另一线程的一段照旧自己建一张（`SetSize` 在 `try` 里）；行距取 GDI 报的 `bmWidthBytes`；行序仍取 LCL 对这张 DIB 的描述——`GetObject` 对 LCL 建的自上而下 DIB 在 `dsBmih.biHeight` 里也答正数（本机实测），看符号分不出（审查建议按符号判断，改了全库文字就上下颠倒）；不是 DIB 时只转换用到的 w × h。
- 像素：全库文字路径逐像素不变——`tools/painter-regress` 在同一次会话里对比改动前（`cf92b36d^` 的 `Painter.pas`）与当前，366 个画面 0 像素差（结果文件 `tests/fixtures/painter-regress/ab-2026-09-30.md`）。

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

**实现期修正（5 期）**：缓存加淘汰计数 `Evictions`（累计，`Clear` 不清，另有 `ResetStats`），和 `Hits` / `Misses` 一起给基准；自绘字形的键加字号（矢量形状的线宽跟着字号，控件换字体本来也清缓存，这一项是冗余但守着——审查后补了测试）。

### 10.5 自绘字形

制表符（U+2500–257F）和块元素（U+2580–259F）不用字体画，按单元格几何自己画，保证相邻格连成线（上游 WebGL 渲染器默认这么做，`addons/addon-webgl/typings/addon-webgl.d.ts:54-75`；定义表 `addons/addon-webgl/src/customGlyphs/CustomGlyphDefinitions.ts`，MIT，可移植数据）。3 期做这两段；盲文、Powerline、Legacy Computing 5 期再定。

**实现期修正（3 期）**：
- 路径坐标取整后**只裁不钳**：上游对这些字形传 `clampToCell = false`（`CustomGlyphRasterizer.ts:734`），画出格的部分按格子裁掉。
- 本批：每个自绘字形只画一次——白色画在比格子大一圈的透明小位图上、Canvas2D 裁到格子，alpha 就是覆盖率遮罩，进字形缓存（§10.4）；着色时用 Canvas2D 画形状的同一个伽马混合（全覆盖直接是那个颜色）。原来直接在表面上画、每格两张整面大小的剪裁遮罩。和直接画比：全部 160 个字形 × 两种格子 × 两种 PPI × 两种底色里，0.03% 的像素差 1（一个字形两段笔画重叠的半覆盖像素，原来混两次、现在合成一次再混），其余逐像素相同。

**实现期修正（5 期）**：~~盲文、Powerline、Legacy Computing 5 期再定~~ 做了 Powerline（E0A0–E0D4 里上游定义的 38 个）和盲文（2800–28FF，256 个）；部件加 `VECTOR_SHAPE`（含 Q / T / Z 命令和弧，按上游的 `scaleType` 缩放，非零环绕填充）与 `BRAILLE`。Legacy Computing、进度条（EE00–EE0B）、git 分支（F5D0–F60D）没做（§15「不做」）。遮罩和直接画的对照扩到三段全部 454 个字形：96 / 144 PPI × 两种格子 × 两种底色共 3632 次绘制，0.011% 的像素差 1，其余逐像素相同。

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

**实现期修正（5 期）**：
- 函数逐位照上游：亮度查表（`Luminance.inc`，V8 的 `Math.pow` 结果按位写进去，常量一律 `Double`），`contrastRatio`、`reduceLuminance` / `increaseLuminance`、`ensureContrastRatio` 与 node 跑出的夹具逐位相同。
- 两份缓存：暗淡的格比值减半、用另一份；键是（底色，前景）。改比值、换主题两份都清（上游改比值只清常规那份，是上游的 bug）。缓存最多 16384 对，满了清空重来（上游无界，§15）。
- 不调的：比值 1；框线、块元素 2500–259F 与 Powerline E0A4–E0D6（`treatGlyphAsBackgroundColor`）；块光标下的字；链接下划线；显式的下划线色；没有字形也没有线的空格子（审查后补的，省一次查缓存）；隐藏（SGR 8）的格。组合字符的格一律调（同 DOM，WebGL 排除）。
- 比的是**画出来的**两个颜色（照 WebGL，§1.1 第 19 条）：选中的格对选区底色比，主题给了选区字色就调那个字色；反显的默认色是主题底色画在主题前景上。
- 暗淡：~~先调前景再做暗淡混合~~ 调过的颜色直接画、**不再变淡**（审查发现照计划写成了「调完再混暗淡」：`$AAAAAA` 在 `$BBBBBB` 上、4.5 时画成 1.56:1，连要求的 2.25 都不到；上游两个渲染器都不再变淡）。没调的照比值 1 时的样子画（变淡）。
- 选区字色（主题给了才有）：比值 1 和大于 1 一致——字、删除线、上划线、默认下划线都用选区字色，暗淡的格上也不变淡（同 DOM：内联色盖过暗淡类、线条取 `currentColor`；审查前比值 1 时线条用格子自己的前景，是 4 期遗留的偏离，已改）。
- 默认下划线跟着调整后的前景（DOM 的 `currentColor`）。

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

**实现期修正（4 期）**：
- ~~`TyTerminalSelection` 的 `background` 叠在格子底色上~~ 期末审查后改成照上游：选区色带着它的透明度先在**主题底色**上混成不透明（上游 `selectionBackgroundOpaque` / `selectionInactiveBackgroundOpaque`，`ThemeService.ts:87-90`），再**替换**选中格的底色（`DomRendererRowFactory.ts:380-386`）——叠在格子自己的底色上时，反显格、亮底色格上的选区几乎看不见。宽字符按它的第一列算，整字选中或整字不选（`:112`、`:160`；列选区起点落在宽字符后半时那个字不选）。禁用时混好的不透明色再按 `:disabled` 的 opacity 预混。
- 选区前景「写了才用」按 `tpTextColor in Present` 判断；基础层和 17 个主题都没给 `TyTerminalSelection` 写 `color`，选中的字保持原色。
- ~~`--terminal-selection-bg-inactive: alpha(var(--on-surface), 0.18)`~~ 改成 `0.3`（上游默认选区的透明度）：0.18 在浅底上只比底色深一点，失焦的选区几乎看不出来。守卫 `TestTheSelectionStandsOutOnEveryTheme`：17 个主题 × 明暗，混好的选区色对底色的 WCAG 对比度——失焦 ≥ 1.70（改后实测最差 1.80，macos 浅色；0.18 时最差 1.41，同是 macos 浅色，守卫会红）、聚焦 ≥ 1.25（实测最差 1.27，office 深色：强调色和深底亮度相近，靠色相区分，亮度比看不出来；聚焦色本期不动，这条只防皮肤再改坏）。选区是叠在字后面的色块，不照 WCAG 非文字的 3:1——那会要一个把字盖住的选区。

**实现期修正（5 期）**：浅底兜底的数据：比值 1 时对皮肤实际浅底低于 4.5:1 的不止 3 号——xp 8 个（最差 3 号 3.70、14 号 3.72、10 号 3.74）、macos 8 个、breeze 7 个；比值 4.5 时全部 ≥ 4.5（最低 macos 3 号 4.58；每步推 10%，xp 会过冲到 5.25–5.30）。`MinimumContrastRatio` 默认 1，也就是默认不兜底，要宿主设。截图 `docs/superpowers/plans/2026-09-29-terminal-phase-5-shots/contrast-{1,45}-{xp,macos,breeze}-light.png`；（a）/（b）/（c）仍待用户在最终验收时定（验收文档决定 D1）。

**6 期新增（2026-09-30 用户拍板）**：主题仍是默认的配色来源；单个实例可以改用独立的配色方案，见 §11.1。浅底 16 色的取舍（D1 / D2）表述改成「默认跟随主题；看不清可换方案」，仍待用户定（§17.1 第 4 条的 6 期注）。

### 11.1 独立配色方案（6 期新增（2026-09-30 用户拍板））

现在终端的颜色全部来自主题 token，单个实例只能靠 `StyleClass` / `StyleOverride` 改。6 期给控件一套独立于主题的配色：宿主（或设计器里的用户）选「跟随主题」或「自定义方案」，方案可以从 Windows Terminal 的 JSON 读进来、写出去。方案清单由外部维护，控件只管读入和应用。实现步骤见 `docs/superpowers/plans/2026-09-30-terminal-phase-6.md`。

#### 11.1.1 用户定的（2026-09-30）

| # | 决定 |
|---|---|
| 1 | 控件加 `ColorSource`：跟随主题（默认，维持现状）/ 自定义方案 |
| 2 | 独立的方案对象 `ColorScheme`，published，可在设计器里改、进 `.lfm`：前景、背景、光标、光标下的字色、选区（聚焦 / 失焦）、16 色；16 色的名字照 Windows Terminal：black / red / green / yellow / blue / purple / cyan / white 及 bright* |
| 3 | 可选「明暗各一套」：浅色、深色各配一个方案，主题换明暗时自动换 |
| 4 | 优先级：程序的 OSC 4 / 10 / 11（/ 12）覆盖 > 自定义方案 > 主题 token；`MinimumContrastRatio` 对最终颜色生效；2031 与明暗查询按实际生效的背景色回答；`NotifyColorSchemeChanged` 的时机要对 |
| 5 | 先只支持 Windows Terminal 的 JSON 配色格式，解析留扩展口；读入：单个 scheme 对象、WT `settings.json` 里的 `schemes` 数组（按名取）；也能写出 |
| 6 | 示例带几套许可清楚的方案做演示，外加「从文件导入」 |
| 7 | 做成第 6 期，做完和 1–5 期一起验收（更新 `2026-09-29-terminal-acceptance.md`，不另起一份） |

标「待定」的是计划开工前问题一里等用户答的，本节按建议写。

#### 11.1.2 核实记录（2026-09-30，读文档与源码）

**Windows Terminal 的配色格式**（文档 https://learn.microsoft.com/en-us/windows/terminal/customize-settings/color-schemes ，`ms.date` 2021-04-14、页面更新 2025-08-21；源码 github.com/microsoft/terminal `main`，commit `4e2b8bd9`，下称 `wt:`）：

| 键 | 必选 | 缺了 WT 怎么办 | 出处 |
|---|---|---|---|
| `name` | 是 | 整套无效、跳过 | `wt:src/cascadia/TerminalSettingsModel/ColorScheme.cpp` 的 `_layerJson`（「Required fields」）；schema `minLength: 1` |
| `foreground` | 否 | `#FFFFFF`（`DEFAULT_FOREGROUND`） | `ColorScheme.h` 的 `WINRT_PROPERTY` 默认值；`wt:src/inc/DefaultSettings.h` |
| `background` | 否 | `#000000`（`DEFAULT_BACKGROUND`） | 同上 |
| `cursorColor` | 否 | `#FFFFFF`（`DEFAULT_CURSOR_COLOR`） | 同上；schema 标 `default: "#FFFFFF"` |
| `selectionBackground` | 否 | `#FFFFFF`（取 `DEFAULT_FOREGROUND`，不是这套的前景） | 同上 |
| `black` `red` `green` `yellow` `blue` `purple` `cyan` `white` `brightBlack` `brightRed` `brightGreen` `brightYellow` `brightBlue` `brightPurple` `brightCyan` `brightWhite` | 是，16 个都要 | 不满 16 个整套无效、跳过 | `ColorScheme.cpp` 的 `TableColorsMapping` 与 `isValid &= (colorCount == 16)` |
| `magenta` / `brightMagenta` | 别名 | 分别等于 5 / 13 号（GH#11456） | `TableColorsMapping` 末两项 |

- **颜色格式**：文档原话是 `"#rgb"` 或 `"#rrggbb"`；schema 的 `Color` 模式 `^#[A-Fa-f0-9]{3}(?:[A-Fa-f0-9]{3})?$`。读入时 `CanConvert` 只收**字符串、长度 4 或 7、以 `#` 开头**（`wt:src/cascadia/TerminalSettingsModel/JsonUtils.h` 的 `ConversionTrait<til::color>`），所以 `#rrggbbaa` 在配色里**不收**（底层 `Utils::ColorFromHexString` 认 9 位，但走不到）；不是字符串、长度不对都抛 `DeserializationError`。十六进制位用 `std::stoul(…, 16)` 解，`#12345g` 这种会被解成 `05`，WT 不报错——我们严格报错（§11.1.10）。
- **缺字段**：`name` 或 16 色不全 → `FromJson` 返回空、这一套被**静默跳过**；颜色写坏 → 异常。两者不一样。
- **按名取**：`settings.colorSchemes.emplace(scheme->Name(), …)`（`wt:…/CascadiaSettingsSerialization.cpp` 的 `_parse`）——`emplace` 不覆盖已有的键，同名的**第一个有效**的算数。名字按原样比较（区分大小写）。
- **`purple` 与 `magenta` 都写了**：WT 按表的顺序读，读满 16 个就停（`if (colorCount == ColorSchemeExpectedSize) break;`）——16 个主名都在时别名不读；主名缺一个时别名补上。怪情况（`purple` 和 `magenta` 都写了、另缺一个主名）WT 会数到 16、把缺的那一色留成未初始化值；我们报「缺某键」（§11.1.10）。
- **文件格式**：`settings.json` 是带注释、允许尾逗号的 JSON（WT 自带的 `defaults.json` 里就有 `//` 注释和尾逗号；读用 jsoncpp 的 `CharReaderBuilder` 默认设置）。方案在顶层的 `schemes` 数组里。
- **明暗配对 WT 也有**：profile 的 `colorScheme` 可以是字符串，也可以是 `{"light": 名, "dark": 名}`（schema `SchemePair`：「depending on the theme of the application」）。我们的「明暗各一套」同一个意思，但看的是主题（§11.1.5），不读 profile。
- **WT 写出**（`ColorScheme::ToJson`）：`name`、`foreground`、`background`、`selectionBackground`、`cursorColor`，再按表顺序 16 色；颜色是 `#RRGGBB`（`til::color::ToHexString(true)`）。

**xterm.js 的 `ITheme`**（`xterm:typings/xterm.d.ts:372-445`，`xterm:src/browser/services/ThemeService.ts`）——控件内部的取色语义以它为准：
- 字段：`foreground`、`background`、`cursor`、`cursorAccent`（块光标下的字色）、`selectionBackground`、`selectionForeground`、`selectionInactiveBackground`，16 色用 `magenta` / `brightMagenta`（WT 叫 `purple`），另有 `extendedAnsi`（16–255，WT 没有）、滚动条三色、`overviewRulerBorder`。
- 缺省（`ThemeService.ts:23-31`、`:81-131`）：前景 `#ffffff`、底 `#000000`、光标 `#ffffff`、`cursorAccent` 取常量 `#000000`（`DEFAULT_CURSOR_ACCENT = DEFAULT_BACKGROUND`，`:26`——是默认底色常量，不是这套主题的底色）、选区 `rgba(255,255,255,0.3)`；**失焦选区缺了就等于聚焦选区**（`:89`）。
- **不透明的选区色一律降到 0.3 透明度**（`:97-106`，Issue #2737；`color.opacity` 的 alpha = `Math.round(0.3 × 255)` = `0x4D`），再在底色上混成不透明（`:88`、`:90`）。WT 的 `selectionBackground` 没有 alpha，按这一条就是「这一色、0.3」。
- 光标与 `cursorAccent` 也在底色上混（`:85-86`），不透明时等于原色。
- 换主题清两份对比度缓存（`:135-136`）；覆盖色随整张表重建丢掉（§7.3 的 2 期修正）。

**FPC 3.2.2 的 JSON**：`fpjson` / `jsonparser` / `jsonscanner` 在 `fpc:packages/fcl-json/src/`，库里 AdvChart 已在用（`source/tyControls.AdvChart.Option.pas:332`），运行时包不多一个依赖。选项 `joComments`（`//` 与 `/* */`，`jsonscanner.pp:498-540`）、`joIgnoreTrailingComma`（`jsonreader.pp:372`、`:400`）够读 WT 的 `settings.json`；**重复键默认抛异常**（`jsonparser.pp:132`，开了 `joIgnoreDuplicates` 是**前者**为准，jsoncpp 是后者为准）；BOM 只在流构造时查（`joBOMCheck`，`jsonscanner.pp:162`），从字符串读要自己去掉。已知两个坑：**`\u0000` 被吞掉**（[[fpjson-drops-u0000]]），**两个 `\u` 转义挨着时丢字节**（`AdvChart.Option.pas:197-208` 的注释；那里的对策是解析前先把 `\u` 转义解成 UTF-8，`TyDecodeUnicodeEscapes`，在实现部分、没导出）。那个预解码不认注释（注释里的引号会让它把串内串外弄反），也会把 `\u0022` / `\u005C` 解成裸的引号、反斜杠——终端这边要自己的一份，认注释、这两个字符和控制字符保留成转义（计划开工前问题二）。

**外部方案集**：`mbadolato/iTerm2-Color-Schemes` 有 `windowsterminal/` 目录（每套一个 WT 格式的 JSON）；仓库 `LICENSE` 是 MIT（Copyright (c) 2011 to Present Mark Badolato），但末尾写明「This license covers the iTerm-Color-Schemes repository collection of themes. The copyright/license for each individual theme belongs to the author of that theme.」——**单套方案的许可要逐个查，不能按仓库的 MIT 打包**。示例因此不从那里带（§11.1.9）。

#### 11.1.3 数据模型与属性

**方案对象** `TTyTerminalColorScheme = class(TPersistent)`（新单元 `tyControls.Terminal.ColorScheme`，进运行时包；依赖 `SysUtils`、`Classes`、`Graphics`（只为 `TColor` / `clNone` / `ColorToRGB`）、`fpjson` / `jsonparser` / `jsonscanner`、`tyControls.StrConsts`；不引 `Controls` / `Forms`）：

| published 属性 | 类型 | 默认（= 构造值） | WT 键 | xterm `ITheme` | 未设置时 |
|---|---|---|---|---|---|
| `Name` | string | `''`（不写进 `.lfm`） | `name` | — | 只用于显示和写出 |
| `Foreground` | TColor | `clNone` | `foreground` | `foreground` | 主题的前景 |
| `Background` | TColor | `clNone` | `background` | `background` | 主题的底色 |
| `CursorColor` | TColor | `clNone` | `cursorColor` | `cursor` | 生效的前景 |
| `CursorText` | TColor | `clNone` | —（WT 没有） | `cursorAccent` | 生效的底色 |
| `SelectionBackground` | TColor | `clNone` | `selectionBackground` | `selectionBackground` | 主题的聚焦选区色（带它自己的 alpha） |
| `SelectionInactiveBackground` | TColor | `clNone` | —（WT 没有） | `selectionInactiveBackground` | 设了 `SelectionBackground` 就用它（照 xterm `:89`），否则主题的失焦选区色 |
| `Black` … `White`、`BrightBlack` … `BrightWhite`（16 个，顺序 = ANSI 0–15，5 / 13 叫 `Purple` / `BrightPurple`） | TColor | `clNone` | 同名小驼峰（读时也认 `magenta` / `brightMagenta`） | `black` … `brightWhite`（5 / 13 叫 `magenta`） | 主题的那一色 |

- **「未设置」是 `clNone`**，不是 0：TColor 的零值是合法的黑色（[[zero-value-must-be-the-safe-answer]]）。`clDefault` 当未设置；系统色（`clWindow` 这类，设计器的颜色下拉里有）用时经 `ColorToRGB` 解成 RGB。TColor 是 `$00BBGGRR`，色表是 `$RRGGBB`，换算只在一处（地雷见计划）。
- 另有：`Colors[ASlot]` 下标属性（`TTyTerminalSchemeSlot`，前 16 个的序号就是 ANSI 号）、`Assign`、`Clear`、`IsEmpty`、`Equals`、`BeginUpdate` / `EndUpdate`、`OnChange`（控件挂上，宿主别改写）、读写方法（§11.1.7）。`GetOwner` 答控件，设计器的属性路径与「已修改」标记靠它。
- 选区字色（xterm `selectionForeground`）不进方案：WT 没有；主题「写了才用」的那一条照旧（§11）。

**控件的新属性**（`TTyTerminalView`，published；default 一律等于构造值）：

| 属性 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `ColorSource` | `TTyTerminalColorSource = (tsrcTheme, tsrcScheme)` | `tsrcTheme` | 跟随主题 = 5 期的样子，方案对象里有什么都不看 |
| `ColorScheme` | `TTyTerminalColorScheme` | 空方案 | 自定义方案；配对时是浅色那套。有 setter（`Assign`）：FPC 没有 setter 的对象属性不流式化（`source/tyControls.Columns.pas` 里 `TTyHeader.Columns` 的注释） |
| `ColorSchemePaired` | Boolean | False | 明暗各一套（待定：属性形态，计划开工前问题一第 1 条） |
| `DarkColorScheme` | `TTyTerminalColorScheme` | 空方案 | 配对时深色主题用 |

- 设计器里四个都能改；`ColorScheme` / `DarkColorScheme` 在对象查看器里展开成 23 个子属性，只有改过的写进 `.lfm`。
- `ColorSource = tsrcScheme` 而方案全空时，画出来和跟随主题一样（每一色都退回主题）。

#### 11.1.4 取色与优先级

一句话：**程序的 OSC 覆盖 > 方案里设了的 > 主题**。控件的色表（`FPalette`，就是 `OnQueryBaseColor` 答的那一份）按下表建；Core 的覆盖表照旧在它前面（§7.3）。

| 槽 | 方案设了 | 方案没设 |
|---|---|---|
| 0–15 | 方案的色 | 跟随主题时本实例的那一色（含 3 期「实例换了底就按 `on()` 重求」那一条） |
| 16–255 | 公式（`TyTermDefaultPaletteColor`，同上游；方案不管，WT 没有、xterm 的 `extendedAnsi` 不做） | 同左 |
| 256 前景 | 方案的色 | 主题的 |
| 257 底色（也是内边距、网格外余量的底色） | 方案的色 | 主题的 |
| 258 光标 | 方案的色 | 生效的前景（256） |
| 光标下的字色 | 方案的色 | 生效的底色（257） |
| 选区（聚焦） | 方案的色按 xterm 降到 0.3（alpha `$4D`），再在生效的底色上混成不透明 | 主题 `TyTerminalSelection:focus`，带它自己的 alpha 混 |
| 选区（失焦） | 同上 | 方案设了聚焦选区就用它（xterm）；否则主题的无状态 `TyTerminalSelection` |
| 选区字色、链接下划线、外框与边框 | —（不进方案） | 主题 |
| 组字串（macOS） | — | 自定义方案时底色 / 字色取生效的 257 / 256，下划线仍取主题（`TyTerminalPreedit` 的底色 / 字色本来就是 `--terminal-bg` / `-fg`，方案下不能再用主题的） |

- 深底实例的 3 期规则（光标色、光标下的字色跟着实例的前景 / 底色换）只在「跟随主题」下用；自定义方案下由上表决定。
- **其后照旧**：禁用时整张表按 `:disabled` 的 opacity 预混（`PremixFrameColors`）；程序问颜色答原色；`MinimumContrastRatio` 对画出来的两个颜色调（§10.9），所以方案里对比度不够的色一样被推；换方案清两份对比度缓存（色表签名变了）。
- 16–255 不进方案；OSC 4 改它们照旧。

#### 11.1.5 明暗配对

- `ColorSchemePaired = False`：一直用 `ColorScheme`。
- `ColorSchemePaired = True`：主题是浅的用 `ColorScheme`，深的用 `DarkColorScheme`。
- **「主题是深是浅」看主题，不看方案**：取本实例「跟随主题」时会用的底色（`TyTerminal` 的 `background`，带本实例的 `StyleClass` / `StyleOverride`），按 tycss 三参数 `on()` 同一条规则判断——Rec.601 亮度 > 0.5 为浅，恰好 0.5 算深（`Css.Values.pas`，§11 的 3 期修正）。不看 `TTyStyleModel.Mode` 的名字：单模式的深色皮肤没有 `dark` 这个模式名，用户把 `--terminal-bg` 调深也该换边。
- 主题换明暗 → 选中的那一边变了 → 色表变了 → 通知 Core（§11.1.6）。没配对时换明暗色表不变，不通知（和 3 期「主题变了但颜色没变不报」同一条）。

#### 11.1.6 什么时候通知 Core

- 色表的缓存键（今天是 模型、`ThemeVersion`、类、`StyleOverride`）加上：`ColorSource`、`ColorSchemePaired`、两个方案各自的修订号（每次 `OnChange` 加一）。明暗配对选哪边由主题决定，已经在 `ThemeVersion` 里。
- 通知仍只走 `EnsureThemeCurrent` 那一处：**色表逐项比，真变了才** `NotifyColorSchemeChanged`（清 OSC 覆盖色——和上游换主题一样，程序设的颜色随之丢掉；2031 开着就报一次明暗）。改一个方案里没被用到的色（`ColorSource = tsrcTheme` 时，或配对时另一边的方案）不通知、也不重画。
- 在绘制里发现的变化照旧经消息循环再通知（3 期修正），不在绘制里发 `OnData`。
- `.lfm` 加载中（`csLoading`）不建色表、不通知；`Loaded` 之后第一次建色表不算「变了」（和 3 期「第一次建色表不算变化」同一条）——加载本身不会清掉什么、不会发 2031。
- 一次改多个色用 `BeginUpdate` / `EndUpdate`，只算一次；`LoadFrom*` / `Assign` / `Clear` 内部就是一次。
- 改 `ColorSource`、`ColorSchemePaired`、方案里的色，**当场**只让色表的键失效（之后 Core 问颜色、996 都已是新的一套），「清 OSC 覆盖、报 2031、重画」经消息循环做一次（`QueueAsyncCall`，和绘制里发现的主题变化同一个开关）——宿主在一个事件处理里连着设几项（装两套、开配对、改来源），程序只收到一条 2031（计划开工前问题二第 12 条）。
- 通知后整窗重画（色表签名变了，§3.2 的 3 期修正）。

#### 11.1.7 读写 API（先只有 Windows Terminal 格式，留扩展口）

```pascal
type
  TTyTerminalColorSchemeFormat = (tcfAuto, tcfWindowsTerminal);   { 以后加格式就加一个值和一对读写函数 }
  ETyTerminalColorSchemeError = class(Exception)
  public
    property Key: string;          { 出错的键（'' = 整段文本或整套） }
  end;

  TTyTerminalColorScheme = class(TPersistent)
  public
    procedure LoadFromText(const AText: string; const AName: string = '';
      AFormat: TTyTerminalColorSchemeFormat = tcfAuto);
    procedure LoadFromFile(const AFileName: string; const AName: string = '';
      AFormat: TTyTerminalColorSchemeFormat = tcfAuto);
    function TryLoadFromText(const AText, AName: string; out AError: string;
      AFormat: TTyTerminalColorSchemeFormat = tcfAuto): Boolean;
    function TryLoadFromFile(const AFileName, AName: string; out AError: string;
      AFormat: TTyTerminalColorSchemeFormat = tcfAuto): Boolean;
    function SaveToText(AFormat: TTyTerminalColorSchemeFormat = tcfWindowsTerminal): string;
    procedure SaveToFile(const AFileName: string;
      AFormat: TTyTerminalColorSchemeFormat = tcfWindowsTerminal);
    { 文本里有哪几套（按出现顺序；只列有字符串 name 的；单个对象就是它自己的名字，可能是 ''） }
    class function ListSchemeNames(const AText: string;
      AFormat: TTyTerminalColorSchemeFormat = tcfAuto): TStringArray;
  end;
```

**读**：
- 先去掉 UTF-8 BOM；开头是 UTF-16 的 BOM 报「不支持 UTF-16」。`\u` 转义先解成 UTF-8（认注释；引号、反斜杠、控制字符保留成转义），再交 `fpjson`，选项 `joUTF8`、`joComments`、`joIgnoreTrailingComma`。
- 顶层对象有 `schemes` 键 → 当 `settings.json`：`schemes` 必须是数组；按出现顺序找 `name` 与 `AName` **逐字相等**（区分大小写）且 16 色齐全的第一个对象（同 WT 的 `emplace`）；`AName = ''` 时数组里恰好一套有效就取它，多于一套报「要给名字」并列出名字。其余的对象不看——别的方案里的坏颜色不连累这一套（WT 会整个文件读不进，这是有意放宽）。
- 顶层对象没有 `schemes` 键 → 当单个方案对象；`name` 可以没有（单个文件里名字不是必需的，读进来 `Name = ''`）；`AName <> ''` 且和它的名字不同时报「找不到」。
- 16 色必须齐（`purple` 缺了用 `magenta`，`brightPurple` 同理，两者都写了以主名为准）；`foreground` / `background` / `cursorColor` / `selectionBackground` 缺了**按 WT 的缺省补上**（`#FFFFFF` / `#000000` / `#FFFFFF` / `#FFFFFF`），读进来的方案因此和它在 WT 里一样完整（待定：计划开工前问题二第 4 条）；`CursorText`、`SelectionInactiveBackground` 读后是未设置（WT 没有这两项）。
- 颜色必须是字符串，`#rgb` 或 `#rrggbb`，十六进制位大小写都行，前后不许有空白；别的一律报错（含 `#rrggbbaa`、`rgb(…)`、颜色名）。
- 不认识的键不管（WT 的 schema 不许多余键，但加载器不查）。
- **原子**：成功才整体替换（`Assign` 一个临时对象），发一次 `OnChange`；失败什么都不动、不发 `OnChange`。

**写**：
- 键的顺序照 WT 的 `ToJson`：`name`、`foreground`、`background`、`selectionBackground`、`cursorColor`，然后 16 色（`black` … `brightWhite`，5 / 13 写 `purple` / `brightPurple`）；颜色写 `#RRGGBB` 大写；四个空格缩进、`LF` 换行、末尾一个换行。
- 前四个里未设置的不写（WT 读时按它的缺省补）；16 色有未设置的、或 `Name` 为空，报错（WT 会把这一套当无效跳过，写出去没用）。
- `CursorText`、`SelectionInactiveBackground` 不写（WT 格式没有这两项），文档写明；系统色经 `ColorToRGB` 写成 RGB。
- 读 → 写 → 读，方案逐项相等（除了上面丢掉的两项）。

#### 11.1.8 错误处理

| 情况 | 结果 |
|---|---|
| 不是合法 JSON（含没收尾的注释、UTF-16） | `ETyTerminalColorSchemeError`，消息带 `fpjson` 给的行列 |
| 顶层不是对象；`schemes` 不是数组 | 报错，`Key` = `''` / `schemes` |
| 找不到 `AName`；`AName = ''` 而有效的多于一套；一套有效的都没有 | 报错，消息列出文本里有效的名字（最多 20 个） |
| 缺 16 色里的键 | 报错，`Key` = 第一个缺的键，消息列出全部缺的 |
| 颜色不是字符串 / 格式不对 | 报错，`Key` = 那个键，消息带原值 |
| 重复键 | 报错（`fpjson` 默认；jsoncpp 后者为准，§15） |
| 文件打不开 | `LoadFromFile` 透传 RTL 的异常；`TryLoadFromFile` 返回 False 和它的消息 |
| 写出时名字空、16 色不全 | 报错，方案不变 |

- `Try*` 变体不抛（`ETyTerminalColorSchemeError` 和读文件的异常都转成 `AError`），示例和设计器用它。
- 消息是 `resourcestring`（放 `tyControls.StrConsts`，和 3 期终端菜单同一处），进 `.po`（en + zh_CN）。

#### 11.1.9 设计器、`.lfm`、示例

- 对象查看器里改 `ColorSource` / `ColorSchemePaired`、展开两个方案改颜色；设计期预览照这一套画（设计期本来就画色表）。
- `.lfm` 里只写改过的：`ColorSource = tsrcScheme`、`ColorScheme.Name = 'Campbell'`、`ColorScheme.Red = 2035653` 之类。改颜色不改别的属性，`Loaded` 里不往 published 字段写派生值（[[loaded-sync-clobbers-streamed-values]]）。
- 设计器右键菜单「导入 Windows Terminal 配色…」「导出…」（待定：计划开工前问题一第 2 条；建议做，否则设计器里只能一格一格填 22 个颜色）：选文件 → 一套就直接导入、多套先选名字（`InputCombo`）→ 写进 `ColorScheme`（配对时再问写哪一边）→ 标记窗体已修改。
- **示例**：带 Windows Terminal 自带的七套（Campbell、One Half Dark / Light、Solarized Dark / Light、Tango Dark / Light），原样取自 `wt:src/cascadia/TerminalSettingsModel/defaults.json`（MIT，Microsoft；Solarized 原作 Ethan Schoonover，MIT，已核 `altercation/solarized` 的 `LICENSE`；One Half 原作 Son A. Pham，MIT，已核 `sonph/onehalf` 的 `LICENSE.txt`；Tango 调色板由 Tango Desktop Project 放进公有领域），放 `examples/terminal/colorschemes/windows-terminal.json`（`settings.json` 的形状，只有 `schemes`），notices 加一节（待定：计划开工前问题一第 3 条）。下拉：跟随主题 / 七套单套 / 三对明暗（One Half、Solarized、Tango）；「导入…」读任意 WT 文件，一套或多套都加进下拉。不从 iTerm2-Color-Schemes 带（§11.1.2）；文档里告诉用户那里的 `windowsterminal/` 目录可以直接导入。

#### 11.1.10 与 WT、xterm.js 不同的地方（进 §15）

- 颜色的十六进制位严格检查（WT 用 `stoul` 解，`#12345g` 算 `05`）。
- 重复键报错（jsoncpp 后者为准）。
- 按名取时只校验选中的那一套，别的方案的坏颜色不连累（WT 整个文件读不进）。
- `purple` + `magenta` 都写了又缺一个主名：报缺键（WT 会数满 16 个、留一色未初始化）。
- 单个方案对象可以没有 `name`（WT 的 `schemes` 里没名字的无效）。
- 未设置的光标下字色取生效的底色（xterm 缺省是常量黑，§11.1.2）；未设置的光标取生效的前景（xterm / WT 缺省白）——只在方案没设这两项时有区别，从 WT 读进来的方案光标一定有值。
- 写出时丢掉 `CursorText`、`SelectionInactiveBackground`（WT 格式没有）。

#### 11.1.11 i18n

- 库：读写错误消息（§11.1.8）进 `tyControls.StrConsts` 的 `resourcestring`，`languages/tycontrols.strconsts.{en,zh_CN}.po` 同步；设计器菜单项（若做）进 `designtime` 的 `.po`。
- 示例：新下拉的标签、「跟随主题」「导入…」、三对的显示名、导入失败的提示，进 `languages/terminal_example.zh_CN.json` / `.po`。方案名（Campbell、Solarized Dark…）是专名，不翻。

#### 11.1.12 测试（6 期）

- 纯函数（颜色串、转义预解码、读、写）给输入 / 期望表：WT 文档与源码给出的每一条规则一例以上；`defaults.json`（`4e2b8bd9` 的原样一份作夹具，带 `//` 注释、尾逗号、CRLF、一个 `\u` 转义）里 16 套全部读得进、名字与顺序对，示例带的七套逐色对（期望值由测试里手写的 `$RRGGBB` 表给，不经 `fpjson`）；读 → 写 → 读逐项相等；失败原子。
- 控件：取色优先级逐槽（方案设 / 没设 × 主题明 / 暗）；OSC 覆盖在方案之上；996 / 2031 按实际底色答；换方案、改一色、`BeginUpdate` 批量、配对随主题换边各只通知一次，没配对时换明暗不通知；`.lfm` 往返、加载中不发任何 `OnData`；RTTI 守卫扩到方案对象的子属性；最低对比度、禁用预混、选区 0.3 在方案下的像素。
- 示例：下拉里有七套和三对，选中后控件的色表等于那一套；导入坏文件时状态栏提示、控件不变。
- 每条判据写「在哪个变异下必须红」，期末集中变异（计划）。

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

**实现期修正（4 期）**，示例实际的样子：
- 工具条最前面加模式下拉（`CmbMode`：回放 / Shell）。切到 Shell 多出一排（`Tools3`）：命令下拉、启动 / 重启、「记录 PTY 输出」（把 PTY 发来的前 4 KB 以十六进制列进键码面板，看 ConPTY 启动时要了什么）。另一排（`Tools4`）两种模式共用：`CopyOnSelect`、`DetectUrls`、OSC 52 策略。
- 命令列表：Windows 上 `%COMSPEC%`（默认：一定在、起得最快）、`powershell.exe`，PATH 里找得到才列 `pwsh.exe`、`wsl.exe`；Linux / macOS 上 `$SHELL -l`（没有就 `/bin/sh -l`）。可以手改。
- 程序退出：它写的全部显示完，再打一行暗色的「进程已退出，退出码 n」；终端回到只读，按键不再入队（期末审查后补的）。Windows 的退出码是 DWORD，按 `Int64` 存，4294967295 不和「不知道」（−1）混。
- Ctrl+单击链接：示例先问再开，只开 http / https；OSC 52 读剪贴板要用户点头。

### 12.2 PTY 单元（只在示例里）

| 单元 | 平台 | 要点 |
|---|---|---|
| `uptywin.pas` | Windows | ConPTY：`CreatePseudoConsole` / `ResizePseudoConsole` / `ClosePseudoConsole` 从 kernel32 **按名动态加载**——FPC 3.2.2 的 Windows 单元没有声明（`fpc:` 下 grep 不到 `CreatePseudoConsole`）；取不到就提示「本机不支持 ConPTY」。两条匿名管道 + `STARTUPINFOEX` 的伪控制台属性起进程 |
| `uptyunix.pas` | Linux / macOS | `forkpty` 自己声明 `external`（Linux 在 libutil，macOS 在 libc）——FPC 3.2.2 只有已废弃的 `libc` 包声明过（`fpc:packages/libc/src/ptyh.inc:3`），且那个包只支持 linux/i386（`fpc:packages/libc/fpmake.pp:30-31`）。改尺寸用 `ioctl(TIOCSWINSZ)` |
| `uptythread.pas` | 共用 | 读线程 + 加锁队列 + 一次 `QueueAsyncCall`（§3.5）；写 PTY 在主线程 |

`OnGridResize` → 改 PTY 尺寸；`OnData` → 写 PTY；进程退出 → 在终端里打一行提示。

**实现期修正（4 期）**：

| 单元 | 要点 |
|---|---|
| `uptysession.pas` | ~~`uptythread.pas`~~ 会话：读线程、写线程、加锁队列、背压、一批一次唤醒、收尾线程。只引 `Classes`、`SysUtils`、`SyncObjs`，WSL 的控制台测试直接用 |
| `uptywin.pas` | ConPTY + 退出等待线程；`STARTF_USESTDHANDLES` 带空句柄（不带时，宿主被重定向的标准句柄会传给子进程，子进程写到那里、不进伪控制台）；`COORD` 按 `DWORD` 打包传；构建号用 `RtlGetVersion` |
| `uptyunix.pas` | ~~`forkpty`~~ `posix_openpt` / `grantpt` / `unlockpt` / `ptsname`（libc 里都有，自己声明；不链 libutil——Linux 上要装开发包才链得上）|
| `ushell.pas` | 把会话接到 `TTyTerminalView`：`OnData` → 写、`OnGridResize` → 改尺寸、输出按 `Write` 回调记账、退出一行、设 `Core.WindowsPty` |

- ~~写 PTY 在主线程~~ 在写线程上写：大段粘贴不卡界面。
- 命令一律 `/bin/sh -c "<命令行>"`，前面不加 `exec`（列表、管道、`exit 7` 这类内建命令都要 shell 来解析）；环境变量用示例自己的，`TERM=xterm-256color`、`COLORTERM=truecolor`，去掉 `LINES` / `COLUMNS`（尺寸从 PTY 来）。
- `fork` 之后子进程只做异步信号安全的系统调用。期末审查后补了三件：信号屏蔽字清空；1–31 号信号恢复 `SIG_DFL`（被忽略的信号会跨 `execve` 传下去，宿主忽略 SIGPIPE 的话 `yes | head -1` 里的 `yes` 就死不掉）；3 到软上限（最多 65536）的描述符全关。
- 等读写用 `poll`；macOS 的 `poll()` 不支持字符设备，对主端可能答 `POLLNVAL`，第一次见到就改用 `select`（WSL 里强制走过一遍 select 路径；macOS 待真机，第 59 项）。
- **关闭不在主线程上等**（期末审查后改的）：19044 上 `ClosePseudoConsole` 会在调用它的线程上阻塞——24H2 之前它要等输出读完、程序退出，程序在 `CTRL_CLOSE_EVENT` 处理里可以耗 5 秒——原来有一条路在主线程上调它。照 node-pty 的做法，`ClosePseudoConsole` 只由退出等待线程调，它等「程序退出」或「关闭事件」两者之一。宿主关闭（`Close` / `Free`）只做不阻塞的几件事：读线程改为丢弃、写线程停、取消卡住的写、不再唤醒宿主、置关闭事件，然后立即返回；剩下的交给会话自己的收尾线程——等伪控制台关掉、程序退出（上限 3 秒），超时按**句柄** `TerminateProcess`（这也让卡住的 `ClosePseudoConsole` 返回，再等 2 秒），再中断两个线程直到都退出（上限 3 秒），最后关句柄、释放。读线程关闭期间一直在读（丢弃）：伪控制台要等输出读完才关。Unix 同理：宿主关闭只发 SIGHUP，收尾线程等子进程（上限 3 秒）、不走就 SIGKILL。停不下来的（线程卡死，或杀了进程 `ClosePseudoConsole` 也不返回）连同它用的东西一起留着——是泄漏，不是挂死，也不是释放后再用。会话对象本身只是句柄，释放它就是关闭、立即返回。程序退出时对还在收尾的会话有上限地等一次（`PtyWaitForFinishers`，约 9 秒封顶）。
- 读线程抛异常也算结束：照样唤醒宿主、打退出行（退出码不知道）。写线程退出（管道断了）之后 `Write` 不再往队列里加。

### 12.3 流量控制（5 期）

读线程在待写字节超过高水位（建议 1MB）时停读，等 `Write` 回调把积压降到低水位（建议 256KB）以下再读。这是上游文档推荐的做法（`WriteBuffer.ts:12-19` 的注释要求宿主做流控）。

**实现期修正（4 期）**：~~5 期~~ 流控提前到本期（4 期任务要求），落在示例的会话里：读线程在「读了、终端还没解析完」的字节超过高水位 1 MB 时停读，`Write` 回调把它降到 256 KB 以下再读；一次读 64 KB。关闭时读线程改为丢弃、不再等背压。5 期仍做控件侧的 `Write` 回调顺序测试和性能。**实现期修正（5 期）**：控件侧的回调顺序测试已做（块内切片后回调仍在整块之后、按写入顺序到；事件里延后的调用在回调之后），灌入的内存与窗口重画见 §3.1、§16。

### 12.4 ConPTY 的两件事

- **版本号**：示例用 `RtlGetVersion` 取 Windows 构建号，设 `Core.WindowsPty := (twpConPty, 构建号)`。低于 21376 时核心关折行、开折行启发（§6.2）。
- **win32-input-mode**：ConPTY 启动时会不会发 `CSI ? 9001 h`、发了之后要求终端怎么报键，出处是上游注释里链接的微软规格（`InputHandler.ts:2043`），本机没有源码可核；控件默认不开这个扩展（§7.2），键盘按普通 VT 发。列入后期（§15），真机上先观察 ConPTY 实际发了什么（§16）。

**实现期修正（4 期）**：ConPTY 下的鼠标控件不用另做：控制台程序打开鼠标输入时，ConPTY 应该向终端要标准的 1000 / 1002 / 1003 / 1006，再把终端报上来的 SGR 序列转成控制台的鼠标事件，终端这边就是本期的标准上报。这段出自对 ConPTY 行为的了解，本机没有源码可核，列为真机项（示例的「记录 PTY 输出」看它实际发了什么）。win32-input-mode 本期不做（§15）。

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

**实现期修正（4 期）**：
- 新脚本：`selection-cases.js`（+ `cases/selection.js`）、`url-cases.js`（网址、`isUrl`、OSC 8、去重叠，+ `cases/links.js`）、`clipboard-cases.js`（OSC 52）、`mouse-cases.js`（`_sendEvent` 的事件映射、`getCoords` 两种、拖动滚速）；`conpty-cast.py`（ConPTY 录制转 asciicast，§13.4）。`regen-all.js` 与 `lib-dump.js` 的 `PORTED` / `GENERATED` 跟着加。
- 新夹具：`terminal-selection.json`、`terminal-links.json`、`terminal-osc52.json`、`terminal-mouse-events.json`；`terminal-core-recording.json` 多了两份 ConPTY 录制。
- 新测试单元：`test.terminal.selection.pas`、`test.terminal.links.pas`（对上游）、`test.terminal.view.mouse.pas`、`test.terminal.view.links.pas`、`test.terminal.pty.pas`（会话、背压、关闭与收尾、ConPTY；「不肯跟着控制台走的程序」由测试程序自己带 `--ty-pty-helper` 起来当）。
- 工具：`tools/terminal-ptytest`（WSL 里用 `fpc` 直接编的控制台程序，跑 Unix 后端，12 例）、`tools/terminal-conpty-record`（经示例的会话录 ConPTY）、`tools/terminal-shots --phase4`（选区、列选区、链接悬停的验收截图，存 `docs/superpowers/plans/2026-09-29-terminal-phase-4-shots/`）。
- 像素测试：~~整体关掉光栅预算（`RasterBudgetMs := 0`）~~ 期末审查后改成冻结时钟——预算照常开着、每个字形都走那个判断，只是读到的时间不动，永远不超；要墙上时间的计时测试自己把时钟换回来。

**实现期修正（5 期）**：
- 新脚本：`reflow-cases.js`（+ `cases/reflow.js`）、`contrast-cases.js`（→ `Luminance.inc`、`terminal-contrast.json`）；`lib-dump.js` 加 `marker` 步骤、`reflowCursorLine` 选项、`PORTED` 加 `BufferReflow`、`RendererUtils`、`ColorContrastCache`、`OptionsService`，并对上游 `_reflowSmaller` 的负下标打运行时补丁（§6.2）；`gen-terminal-glyphs.js` 加 Powerline、盲文与图案纵向周期。
- 新夹具：`terminal-core-reflow-*.json`（245 例：手写 110、4 份录制切出 16、种子随机 120）、`terminal-reflow-units.json`（五个纯函数：27 / 7 / 8 例）、`terminal-contrast.json`；`terminal-buffer-ops.json`、`terminal-selection*.json`、`terminal-links*.json` 加了改列数的用例。
- 新测试单元：`test.terminal.reflow.pas`（`TTyTerminalReflowOracleTests`、`TTyTerminalReflowTests`）、`test.terminal.perf.pas`（`TTyTerminalPerfTests`：灌入的内存与缓存、热缓存零未中、最长一片、整屏重画、对比度成本、显示出来的窗口在灌入时照样画）。
- 工具：`tools/terminal-bench`（基准，直接引 `source/`，不进包）；`tools/painter-regress`（全库文字路径的离屏出图与哈希、计时；`ab.sh` 在临时 worktree 里对改动前的文件做同一次会话的 A/B，哈希文件头写机器指纹、指纹不符拒绝比较）；`tools/terminal-shots --phase5`。

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

**实现期修正（4 期）**：
- 鼠标、网址两行本期完成（`mouse-cases.js`、`url-cases.js`）。
- ConPTY 的录制本期补上：经示例的会话（`TConPtyBackend`）在本机（19044）录了 `cmd /c` 与 `powershell -NoProfile -Command` 各一段（`recordings/conpty-cmd.cast`、`conpty-powershell.cast`；命令行在同名 `.cmdline` 里，可以重录）。ConPTY 发的第一条 OSC 0 带程序的全路径，转换时只留文件名；转换脚本见到用户名、机器名、个人目录就拒绝。它们和 WSL 录的一样喂上游、逐步比，也拷进了示例。

**实现期修正（5 期）**：「重新折行」一行完成：core-reflow 245 例（各种宽度来回、宽字符跨切口、组合字符、标记、OSC 8、光标、滚回满、四种视口情形、备用屏、四种 `WindowsPty`、`reflowCursorLine` 两种），另有缓冲层、选区、网址各几例改列数。

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
- **实现期修正（4 期）**：notices 的 xterm.js 一节标题加两个单元——`tyControls.Terminal.Selection.pas`（`SelectionService.ts`、`SelectionModel.ts`，外加 `addon-clipboard` 的 OSC 52 规则）、`tyControls.Terminal.Links.pas`（`addon-web-links` 的 `WebLinkProvider.ts` / `WebLinksAddon.ts`，`OscLinkProvider.ts`、`Linkifier.ts`）；两个 addon 自己的版权行（addon-web-links 2017、addon-clipboard 2023）并进那一节，发版守卫逐个查标题。控件拆出来的五个 include 是自己写的，不进标题。i18n：终端菜单的「Clear」和图片集合对话框的「Clear」同一个 msgid，库和示例的 `.po` 里各带 `msgctxt`，各有各的译文。
- **实现期修正（5 期）**：notices 的 xterm.js 一节标题加 `tyControls.Terminal.Buffer.Reflow.inc`（`BufferReflow.ts`、`Buffer.ts` 的 `_reflow*`）与 `tyControls.Terminal.Luminance.inc`（`Color.ts` 的公式在 node 里算出的表）；自绘字形那句的区段改成实际范围。发版守卫逐个查。
- **6 期新增（2026-09-30 用户拍板）**：新单元 `tyControls.Terminal.ColorScheme.pas` 是自己写的（读写 WT 格式、取色语义照 xterm `ThemeService.ts`，单元头注明出处行号），不进 xterm.js 一节的标题。示例带的七套方案取自 Windows Terminal 的 `defaults.json`（MIT，Microsoft），notices 加一节「Windows Terminal color schemes — `examples/terminal/colorschemes/`」：WT 的 MIT 全文与版权行，外加 Solarized（Ethan Schoonover，MIT）、One Half（Son A. Pham，MIT）两行版权与「Tango 调色板在公有领域」一句；「只在带上示例的这个目录时才要」。发版守卫查这一节与文件随示例发出。`iTerm2-Color-Schemes` 不打包（单套许可归各作者，§11.1.2）。

---

## 15. 有意的偏离与不做清单

**和 xterm.js 不同**：

- macOS 默认选区覆盖键是 Option（上游默认没有，§1.1 第 5 条）。
- 横向滚轮上报（上游不产生，§1.1 第 3 条）。
- `AlternateScroll` 属性可关（上游无条件，§1.1 第 2 条）；仍不认 DECSET 1007。
- XTVERSION 报库名（§7.2）。
- 1016 报设备像素（§9.5.1）。
- ~~复制时行尾用平台换行（§9.6.1）~~（4 期核实不是偏离，§1.1 第 12 条）。
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

**实现期修正（4 期）**，4 期新增的偏离：
- 链接悬停、激活要按 Ctrl（macOS Cmd）；上游悬停就下划线、单击就激活（§1.1 第 14 条）。
- 非 http(s) 的 OSC 8 链接默认不算（照上游）；`AllowNonHttpLinks` 这个属性是我们加的，打开后全交宿主。
- 不做 IDNA：主机含非 ASCII 的网址不算链接（上游转 punycode 后前缀比不上，结果相同）；OSC 8 的协议检查对这种主机按「解得出」算（上游 UTS 46 会拒掉少数字符，我们不查）；`xn--` 标签不校验 punycode。
- 同一行第一次悬停：上游在去掉重叠之前就挑链接（`Linkifier.ts:133-146`、`:175-215`），第一次悬停可能挑中一个和别处 OSC 8 链接重叠的网址，指针移开再回来就挑不中了；我们总在去掉重叠之后挑，结果不随悬停的先后变。
- 清滚回（`OnScrollbackCleared`）也清选区：上游 `clear()` 不清（`CoreBrowserTerminal.ts:1075-1089`），选区会指着别的行。
- 同一个鼠标协议重复 DECSET（比如连发两次 `?1000h`）上游也清选区（`activeProtocol` 的 setter 每次都发事件）；我们只在协议真变了时清（Core 只在模式真变时发 `OnModesChange`）。
- 抬起丢了时照松开收尾、替程序补发抬起（§9.5.2）；上游挂在 document 上的监听总能等到抬起，没有这种情况。
- 中键：Windows / macOS 上程序没接管鼠标时什么都不做（Linux X11 上粘贴 PRIMARY）。
- 选区：期末审查前是「叠在格子底色上」，是偏离；已改回上游的「替换成不透明的选区色」（§11），不再是偏离。

**实现期修正（5 期）**，5 期新增的偏离：
- 块内切片：一片把一块按 32 KB 一段解析、段间看预算（上游整块一次，§3.1）；灌入时到点当场画一帧、Win32 上有输入排队时下一片让一下（上游的浏览器没有这回事）。
- 改列数且真的重新折行时清选区（上游不清，§9.5.5）。
- 对比度：反显默认色取 WebGL 的比法（DOM 拿前景比前景）；选区字色在暗淡格上不变淡、线条跟着选区字色（取 DOM 的做法，WebGL 变淡）；组合字符的格照调（同 DOM，WebGL 不调）；隐藏且带下划线的格不调；两份缓存在改比值时都清；缓存最多 16384 对（上游无界）。
- `MinimumContrastRatio` 是 NaN 或无穷时按 1（上游会存 NaN）。
- `WindowsPty = {conpty, 0}` 表达不了（0 = 没给）。
- Buffer 层在上游会死循环或抛 TypeError 的三处抛 `EArgumentOutOfRangeException`（§6.2）。
- 上游 `_reflowSmaller` 的负下标 bug 不照搬：满滚回时变窄不冲掉底部几行（§1.1 第 20 条）。
- 行内存回收当场做完，上游在空闲时分批（§6.2）。

**6 期新增（2026-09-30 用户拍板）**：独立配色方案（§11.1）和 Windows Terminal、xterm.js 不同的七处，逐条见 §11.1.10（严格的十六进制、重复键报错、只校验选中的那一套、别名的怪情况报缺键、单个对象可无名、未设置的光标与光标下字色取生效的前景 / 底色、写出丢两项）。

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
- **实现期修正（5 期）**：Legacy Computing（1FB00–）、进度条（EE00–EE0B）、git 分支图（F5D0–F60D）的自绘（§10.5）。

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

**实现期修正（4 期）**：4 期的真机验收项接着 3 期编号，汇总在 4 期计划末尾（第 32–55 项，期末审查后加了第 56–65 项：关闭 / 重启的冻结时长、Win11 24H2 无残留、退出与关闭同时发生、macOS 的 `POLLNVAL`、失去捕获、Shift+F10、子进程的信号与描述符、失焦选区看不看得见、X10 横向滚轮、ConPTY 录制在新版本上的差异）；截图在 `docs/superpowers/plans/2026-09-29-terminal-phase-4-shots/`。

**实现期修正（5 期）**：
- 本机数字（Win32，Xeon Silver 4216，Windows 10 19044，`terminalbench`）：Core 吞吐 19.2 MB/s（基线 18.9）；一次 `Write` 20 MB 最长的一片 13.1–13.7 ms（基线整块一片 1025.6 ms；审查前 128 KB 一段时 18.0 ms）；热缓存整屏重画 96 PPI 10.9–11.1 ms、144 PPI 19.2–19.7 ms、对比度 4.5 时 11.6–12.0 ms；一行一行滚见 §10.1；冷填充见 §10.3；50 MB 灌入 5.1–5.2 MB/s，两次绘制的间隔中位 52.6 ms、最长 79–110 ms，开始后 33–39 ms 画上第一帧，堆 +3.1 MB，存活 1061 行（审查前记的 69 ms、12.5 MB/s 是在窗口前 3.4 秒一次也没画的情况下量的，§1.1 第 21 条）；折行（1 万行滚回）125 / 61 / 65 ms（200 → 120 → 200 → 80 列；审查后加了 `CopyCellsFrom` 的快路径，降到 48 / 33 / 32 ms），10 万行 120 → 70 → 120 列约 0.64–0.72 s（1 万行 49–54 ms，线性）。四个 widgetset 的数字留给真机（验收第 71、75 项）。
- 对比度夹具只在 Win64（`Extended` = `Double`）上证明逐位相同；x86_64-linux 上未标类型的实常量是 80 位 Extended、i386 上 x87 全程扩展精度，那两处要真机跑 `TTyTerminalRenderTests`（有类型的常量已保留；i386 只能要求 SSE2 编译）。
- 3–5 期的真机项合成一份：`docs/superpowers/plans/2026-09-29-terminal-acceptance.md`（91 项，含两轮审查补的第 80–91 项）。

**6 期新增（2026-09-30 用户拍板）**：配色方案的真机项接着验收文档编号（第 92 项起，6 期计划末尾列出、收尾时并进验收文档）：示例里切方案与明暗配对、设计器里改方案并存盘重开、导入真实的 WT `settings.json`（带注释、尾逗号、BOM、中文名）、方案下的 OSC 改色与 2031、最低对比度、禁用态、各 widgetset 下系统色（`clWindow` 等）解出来的样子。

---

## 17. 开工前要定的问题

### 17.1 要问用户的

> **已定（2026-09-28）**：用户回复「按你说的做」，以下 11 条全部按建议。另：用户明确不想引入第三方库——Unicode 表编译进库（§4.2），运行时不依赖 ICU 或任何外部库。

1. **默认 Unicode 版本**。建议 `tuv11`：6 太老，表情和很多 CJK 扩展区都算错；15-graphemes 上游自称实验性（`addons/addon-unicode-graphemes/README.md:3`）。
2. **6 / 11 版本下 `AmbiguousWide` 怎么办**。建议不起作用、文档写明，这样每种组合都有上游基准（§4.3）。
3. **字体从哪来**。建议：主题键 `TyTerminal` 的 font-family / font-size（token 默认 `monospace` + 基础字号），实例覆盖按「字体覆盖通道」需求的规则就地实现（`ParentFont = False` 且字段非出厂值才生效），那个需求落地后并入公共 helper（§10.3）。
4. **16 色默认值**。深底用 xterm.js 的 Tango（已核实，`xterm:src/browser/Types.ts:183-203`）。浅底那套建议：同色相、逐色调暗到对白底对比度 ≥ 4.5:1（0 黑、7 白、8 亮黑、15 亮白除外），3 期用脚本算出后写死进 light.tycss，出 17 主题截图给你拍板。
   **实现期修正（3 期）**：按公式做了，字面「对白底 ≥ 4.5:1」达标（最差 3 号 4.52:1）；但各皮肤的浅底不是纯白，3 号色落到实际 `--surface` 上最差 xp 3.70:1、macos 3.82、breeze 3.96（其余 ≥ 4.04）。主控决定暂按（c）维持，5 期 `MinimumContrastRatio` 兜底；最终验收时看截图（`docs/superpowers/plans/2026-09-29-terminal-phase-3-shots/`，含 xp / macos / breeze 的 3 号色放大样例和 7 / 15 号色放大样例）请用户在（a）以最暗浅底重算、（b）终端底色改用更白的 token、（c）维持 三者中定；7 / 15 在浅底上几乎看不见，同一次定要不要调。
   **6 期注（2026-09-30）**：有了独立配色方案（§11.1），验收文档的 D1（3 号色）、D2（7 / 15 号色）表述改成「**默认跟随主题；看不清可换方案**」——主题的浅底 16 色仍是默认、仍待用户在（a）/（b）/（c）与调不调 7 / 15 之间定；嫌主题的浅底色看不清的宿主，可以把单个终端换成一套自定义方案（比如 Tango Light、Solarized Light），或打开 `MinimumContrastRatio`。决定本身没变，只是多了一条出路。
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

**实现期修正（4 期）**，4 期开工前问题一的六条结论（按建议执行、已告知用户，最终验收时可改）：
1. 右键菜单终端自建四项（复制、粘贴、全选、清屏），不实现 `ITyTextEditActions`、不改 `TextMenu.pas`；设了 `PopupMenu` 用宿主的（§9.6.4）。
2. 非 http(s) 的 OSC 8 默认不算链接，照上游；`AllowNonHttpLinks` 打开后全交宿主（§9.8）。
3. macOS 右键在选区外先选中那个词，照上游，不加属性。
4. Windows 默认 `%COMSPEC%`，另列 `powershell.exe`，找得到才列 `pwsh.exe`、`wsl.exe`；Linux / macOS 用 `$SHELL -l`（§12.1）。
5. 程序没接管鼠标时，Windows / macOS 上中键什么都不做；Linux 粘贴 PRIMARY。
6. 双击在链接上选整条链接，照上游，不要求按 Ctrl（§9.5.5）。

**实现期修正（5 期）**，5 期开工前问题一的五条结论：
1. 冷启动光栅化：用户选 A（改 `Painter.pas`），并要求全库文字的像素与性能回归（§10.3）。
2. 改列数重新折行时清选区（按建议，最终验收时可改，§9.5.5）。
3. `MinimumContrastRatio` 默认 1、只做控件属性、示例加下拉（1 / 3 / 4.5 / 7）（按建议）。
4. 自绘字形扩到 Powerline 与盲文（按建议，§10.5）。
5. 光标所在的那段默认不折，`Core.ReflowCursorLine` 可开（按建议，§6.2）。
另外期末审查后主控定了三条（用户验收时可改）：上游 `_reflowSmaller` 的负下标 bug 修掉（§6.2）；两条没达标的性能目标按实测改写（§18）；改尺寸合并保留，Win32 真拖动的效果进真机验收。

**6 期新增（2026-09-30 用户拍板）**：用户定了独立配色方案的七条（§11.1.1），不再讨论。计划开工前问题一里另有三条等用户答（明暗配对的属性形态、设计器右键导入导出、示例带哪几套），用户没回复前按建议做，验收时可改；结论写回 §11.1 原处。验收文档的决定清单 D1 / D2 按上面第 4 条的 6 期注改表述，D17（最低对比度的默认值）的「另一个做法」里加一句「或换一套方案」。

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

**实现期修正（4 期）**，4 / 5 期边界：
- 流控从 5 期挪进 4 期（示例会话的高低水位，§12.3）；5 期仍有控件侧的 `Write` 回调顺序测试和性能。
- ConPTY 的录制在 4 期补上了（§13.4）。
- 留给 5 期：重新折行（接上后网址回映射的 `ACols` 截断不再起作用，§9.8）；冷启动时光栅化新字形慢（根因在共享单元 `Painter.pas` 的 `TTyGdiTextRenderer`，要改须用户拍板）；`MinimumContrastRatio`。

### 5 期：重新折行、流量控制、性能、最低对比度

- 重新折行（`BufferReflow` 移植 + `reflow-cases.js`，含 `windowsPty` 两种）。
- 流量控制：示例的高低水位（§12.3），`Write` 回调顺序测试。
- 性能：整屏上滚的缓存平移、字形缓存命中统计、切片预算调优；四个 widgetset 的实测数字写回本规格。
- `MinimumContrastRatio`（§10.9）；盲文、Powerline、Legacy Computing 自绘字形要不要做在这期定。
- **做完能看到**：拖窗口宽度时长行重新折回、缩回来复原；`cat` 几十 MB 的日志界面不卡死、内存不涨；打开最低对比度后浅色皮肤上的暗色文字变清楚。

**实现期修正（5 期）**，实际做了什么：
- 重新折行（`Buffer.Reflow.inc`，与上游逐位相同，负下标 bug 除外）；控件接线：选区、悬停链接、滚动条；网址回映射删掉 `ACols`；改尺寸合并。
- 写入队列块内切片；灌入时窗口照样重画、输入不卡（§3.1）。
- 性能：行复用（整屏上滚只画新露出的行）、`Painter.pas` 常驻位图（A 路线）、缓存统计、`CopyCellsFrom` 快路径、行内存回收；基准工具与性能测试。
- `MinimumContrastRatio`；Powerline 与盲文自绘。
- 性能目标的改写（主控在期末审查后按实测定，用户验收时可改）：
  - 一行一行滚：~~每帧耗时 ≤ 基线的 1/4~~ 每帧画的行数 ≤ 3，且耗时不劣于基线（6.94 ms）。实测每帧 2.00 行，离屏 4.78 ms、走 `Paint` 6.9 ms：过。原目标（≤ 1.74 ms）要在屏幕上直接滚（环形表面、`ScrollWindowEx`），列为以后。
  - 50 MB 灌入：~~两次绘制的最长间隔 ≤ 50 ms~~ 两次绘制的间隔 ≤ 约 90 ms（一轮 50 ms 的解析、一帧整屏新行 15–20 ms、贴上屏后 DWM 占的十几毫秒），且不劣于基线。实测中位 52.6 ms、最长 79–110 ms（两次），基线实际是前 3.4 秒不画：中位过，最长偶有尖峰超过 90 ms；吞吐 5 MB/s，低于不画时的 10–12 MB/s——这是灌入时窗口不再被饿住的代价。要再快得让整屏新行更便宜（很快滚走的行不画），列为以后。
  - 冷填充：~~每个字形 ≤ 基线的 1/3~~ 走 A 路线：每个 ≤ 基线的 1/2（实测 ASCII 0.50、CJK 0.59（五次的中位；这台机器此时负载起伏大，单次 0.48–0.70，Task 9 时量的是 0.47 / 0.53））。在 A 之上再做 B（终端自己的光栅路径、度量挪进同一个 DC）列为以后。

### 6 期：独立配色方案（6 期新增（2026-09-30 用户拍板））

- 新单元 `tyControls.Terminal.ColorScheme`：方案对象、Windows Terminal JSON 的读写（单个对象、`settings.json` 的 `schemes` 按名取）、错误处理；控件的 `ColorSource`、`ColorScheme`、明暗配对；色表插在 OSC 覆盖之下、主题之上（§11.1）。
- 设计器：对象查看器里改，`.lfm` 往返；（用户同意时）右键导入 / 导出。
- 示例：Windows Terminal 自带的七套 + 三对明暗、「导入…」；notices 一节。
- **做完能看到**：示例里把终端换成 Solarized Dark，整窗连内边距一起换色，换皮肤不影响它；选「Tango（明暗）」再拨暗色开关，终端跟着换成 Tango Dark；导入一个 WT 的 `settings.json` 按名选出一套；程序 `printf '\e]11;#203040\a'` 仍盖过方案、`\e]111\a` 回到方案的底色；和 1–5 期一起真机验收。

