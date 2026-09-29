# 终端控件 4 期：鼠标、选区与剪贴板、链接、右键菜单、真 shell 示例 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（项目约定，优先于子技能的默认做法）**：按子批次连续实现，**每个任务只写代码 + 测试并单独提交**；每个子批次写完**编译一次、只跑本段的 suite、只修本段的红**；node 生成脚本例外，生成物要进提交，脚本当场跑。整期写完后（Task 18）一次全量、集中变异、整体审查（规格核对 + 代码质量）。中途不汇报、不问要不要提交。**用户要求终端所有期做完再一次性真机验收**：本期的真机项、截图都进期末验收材料（本文末尾「真机验收项汇总」，接着 3 期的第 31 项往下编），不中途找用户。
>
> **谁来做**：标 **【主控执行】** 的步骤实现 agent **不做**、直接跳过：编 `tycontrols.lpk` / `tycontrols_dt.lpk`、编示例、跑 `scripts/example-rsj2po.py`、截图、启动示例、要联网的步骤。实现 agent 不编任何 `.lpk`、不编示例、不改 `D:/Projects/xterm.js` 里被跟踪的文件，node 依赖不进本仓库。**WSL 里编译运行纯 FPC 控制台程序**（Task 15 的 `tools/terminal-ptytest`）由实现 agent 做——它不碰 LCL、不碰包注册。
>
> **共享文件**：`source/tyControls.Base.pas`、`source/tyControls.Painter.pas`、`source/tyControls.StyleModel.pas` 本期**不改**（见「需要改共享文件的地方」）。`source/tyControls.TextMenu.pas` 也不改（右键菜单自建，开工前问题一第 1 条）。执行中若发现非改不可，停下交主控，主控先问用户。

**Goal:** 把终端的鼠标接全（按键 / 拖动 / 移动 / 横竖滚轮经 `Core.TriggerMouseEvent` 上报，覆盖键下本地选择），做出选区（字符 / 词 / 行 / 列、自动滚动、随输出移动、画出来、复制、`CopyOnSelect`、Linux PRIMARY）、右键菜单、链接（OSC 8 + 网址识别、Ctrl+悬停下划线、Ctrl+单击交宿主）、OSC 52 三种策略；示例加「真 shell」模式（Windows ConPTY、Linux / macOS `posix_openpt`），PTY 读写在后台线程、用 `Write` 回调做背压。

**Architecture:** 两个新的纯逻辑单元：`tyControls.Terminal.Selection`（照 `SelectionModel.ts` / `SelectionService.ts` 的非 DOM 部分移植：取词、取行、拖动、trim 调整、选区文本；外加 OSC 52 编解码）和 `tyControls.Terminal.Links`（照 `WebLinkProvider.ts` 的网址扫描与 `isUrl`、`OscLinkProvider.ts`、`Linkifier.ts` 的去重叠与命中判定），都能在 node 里拿上游当基准逐项比。控件层把 LCL 鼠标事件分给「上报 / 本地选择 / 链接」三条路，行绘制器加选区底色与链接下划线两段。示例的 PTY 部分全在 `examples/terminal/`：共用的会话（读线程、写线程、加锁队列、背压、退出）+ 两个平台后端 + 把会话接到终端的 `ushell.pas`。

**Tech Stack:** FPC 3.2.2 / Lazarus LCL、BGRABitmap、fpcunit；node v22.22.2 + xterm.js 6.0.0 本地 checkout 的 `out/`（1 期已构建，`addons/addon-web-links/out`、`addons/addon-clipboard/out` 也在）；Windows ConPTY（kernel32 按名取）；POSIX `posix_openpt` / `grantpt` / `unlockpt` / `ptsname`（libc，自己声明）；WSL `Ubuntu`（WSL1，FPC 3.2.2）跑 Unix 后端的控制台验证。

**设计依据：** `docs/superpowers/specs/2026-09-28-terminal-view-design.md`（下称 spec）。本计划覆盖 §18 第 4 期（输入法、括号粘贴已在 3 期做完，本期只剩真机验收）、§7.5 / §7.6 的鼠标上报在控件侧的接线、§9.1 / §9.2 / §9.3 的 4 期属性事件方法、§9.5、§9.6、§9.8、§11 的选区与链接 token、§12.1 真 shell、§12.2、§12.3（流控提前到本期，开工前问题二第 17 条）、§12.4、§13.4 的鼠标与网址两行、§14、§15、§16，以及 3 期签收「给 4 期的交接」全部七条。

**不在本期**（spec §18）：重新折行、控件侧性能（整屏上滚缓存平移、字形缓存统计）、最低对比度、盲文 / Powerline / Legacy Computing 自绘（5 期）；win32-input-mode 的键盘编码、Alt+单击移动光标、kitty 键盘协议（后期，§15）；CHANGELOG（发版时写，[[changelog-user-facing]]）。

---

## 总目录

本计划分一个主文件和四个子批次附录。**先读完主文件**（核实记录、开工前问题、接口清单、地雷、判据约定），再按任务号顺序做；附录里的任务引用主文件的节名。

| 部分 | 文件 | 任务 | 这一批做完能看到什么（执行时不单独验收，见执行方式） |
|---|---|---|---|
| 主文件 | 本文件 | Task 0 基线；Task 18 收尾 | 核实记录、开工前问题、接口、地雷、Win32InputMode 与 ConPTY 鼠标的结论、真机验收汇总 |
| 4a 基准与纯逻辑 | [`2026-09-29-terminal-phase-4a-oracle-units.md`](2026-09-29-terminal-phase-4a-oracle-units.md) | Task 1–4 | 取词、取行、拖动、trim、选区文本（普通 / 列）、网址识别（含 `isUrl`）、OSC 8 链接范围、去重叠、OSC 52 编解码、像素→格子 / 选区点、拖动滚速、鼠标事件映射，全部与上游逐项相同；Core 有 `OnUserInput`，Buffer 有 `TrimmedLines` |
| 4b 鼠标与选区 | [`2026-09-29-terminal-phase-4b-mouse-selection.md`](2026-09-29-terminal-phase-4b-mouse-selection.md) | Task 5–9 | 程序接管时按键 / 拖动 / 移动 / 横竖滚轮按协议上报；覆盖键下本地选择；单击拖、双击词、三击行、Alt 列选、拖出上下边自动滚；选区随输出走、该清时清；选区画出来（聚焦 / 失焦两色、选区前景）；复制、全选、`CopyOnSelect`、PRIMARY、中键粘贴；右键菜单四项 |
| 4c 链接与 OSC 52 | [`2026-09-29-terminal-phase-4c-links-osc52.md`](2026-09-29-terminal-phase-4c-links-osc52.md) | Task 10–12 | 按住 Ctrl（macOS Cmd）时指针下的链接画下划线、手形光标；Ctrl+单击发 `OnLinkActivate`（程序接管鼠标时也是）；双击链接选整条；OSC 52 三种策略 |
| 4d 真 shell 示例 | [`2026-09-29-terminal-phase-4d-pty-example.md`](2026-09-29-terminal-phase-4d-pty-example.md) | Task 13–17 | 示例切到「Shell」就起 cmd / pwsh / `$SHELL`；改窗口大小同步 PTY；背压下 `cat` 大文件不卡不涨；进程退出打一行；Windows 把 `{conpty, 构建号}` 交给 Core；控件文档、README、notices、i18n |

---

## 核实记录（写计划时读源码 + 实跑得到，2026-09-29）

执行者不用重做；Task 0 和各任务会在真构建上复核其中几条。行号都是 `xterm:`（`D:/Projects/xterm.js`，`c58ea36`）或本仓库。

**上游选区（`src/browser/services/SelectionService.ts`、`src/browser/selection/SelectionModel.ts`）**

1. **选区用坐标，不用标记**。模型存 `selectionStart` / `selectionEnd`（`[x, 绝对行]`，x 是 0..cols 的**边界**）和 `selectionStartLength`、`isSelectAllActive`（`SelectionModel.ts:16-33`）。输出把行挤出时只靠 `lines.onTrim` 减行号（`SelectionService.ts:144`、`:386-391`；`SelectionModel.ts:123-144`：终点 < 0 清空，起点 < 0 改成 `[0, 0]`）。注释明说 splice 的插删**故意不跟**（`:780-783`）。spec §9.5.5 写的「锚在标记上」和上游不同——标记在插删时也会动（`Buffer.pas` 的 `LinesInsert` / `LinesDelete`）。见开工前问题二第 1 条。
2. **finalSelectionEnd 的三种补正**：反向或没有终点时用「起点 + 长度」按列数折行（`SelectionModel.ts:78-89`，刚好落在右边界时不带下一行）；有起点长度且同一行时取两者较大（`:92-102`）；全选是 `[cols, ybase + rows − 1]`（`:70-72`）。`hasSelection` = 起终点不同（`SelectionService.ts:191-198`）。
3. **选区文本**：非列模式首行 `[start.x, 同行则 end.x)`，中间行整行，末行 `[0, end.x)`；折行的行接到上一段后面、不换行；每段 `translateBufferLineToString(行, true, …)`（去尾空白）；NBSP 换成空格；段之间用 `isWindows ? '\r\n' : '\n'`（`SelectionService.ts:227-259`）。列模式每行 `[min x, max x)`，不看折行；起终 x 相同返回空串（`:213-226`）。
   **所以 spec §9.6.1 / §15 说的「上游用 `\n`、我们用平台换行是偏离」不对**：上游本来就是 Windows 上 `\r\n`，FPC 的 `LineEnding` 与之相同，不是偏离（写回，见「与规格不符之处」第 1 条）。node 里 `Platform.isWindows` 为假（`src/common/Platform.ts:20-22`，平台名是 `'node'`），夹具里是 `\n`，Pascal 侧把分隔符作参数传 `#10` 比。
4. **取词 `_getWordAt`（`:833-981`）按 UTF-16 下标算**：行串是 `translateBufferLineToString(row, false)`，宽字符在串里只占自己、`getChars().length` 是 UTF-16 长度（表情占 2），列 ↔ 下标由 `_convertViewportColToCharacterIndex`（`:793-809`）换；空格处向两边扩到非空格；非空格处向两边扩到分隔符；词在折行处上下递归接（`:952-978`）；长度不超过列数（`:940`）；`allowWhitespaceOnlySelection = False` 且全是空白时不选（`:948-950`，JS `trim()` 的空白）。
5. **分隔符判定 `_isCharWordSeparator`（`:1034-1041`）**：宽度 0 的格（宽字符后半）永远不是；否则 `wordSeparator.indexOf(cell.getChars()) >= 0`——**空串的 `indexOf` 是 0**，所以从没写过的格（`getChars() = ''`）**是**分隔符。移植必须照这个（`Pos` 对空串答 0，要单独判）。
6. **单击 / 双击 / 三击 / Shift+单击**（`handleMouseDown`，`:453-500`）：右键且已有选区 → 直接返回（选区留着给菜单复制）；非左键返回；程序接管鼠标（`_enabled = False`）时只有 `shouldForceSelection` 才继续（`:471-478`）；`_enabled` 且 Shift → 扩展（`:486-487`，只改终点）；否则按 `event.detail` 1 / 2 / 3。单击：清长度、全选标志，列模式 = `shouldColumnSelect`，起点 = 指针，点在右边界上（`line.length === x`）就不再调整，点在宽字符后半就 `x++`（`:542-578`）。双击先看链接（`_selectWordAtCursor` `:344-361`：`linkifier.currentLink` 有就选整条链接），否则取词、允许纯空白。三击取折行段（`_selectLineAt` `:1047-1056`）。
7. **拖动 `_handleMouseMove`（`:619-686`）**：终点 = 指针；行模式终点 x 取 0 或 cols；词模式 `_selectToWordAt`；按滚速把终点 x 推到 cols / 0（非列模式）；终点落在宽字符后半就 `x++`（不超过 cols）；终点没变就不重画。**自动滚** `_dragScroll`（`:692-716`）每 50 ms 一次：滚 `_dragScrollAmount` 行，再把终点放到视口底行（`min(ydisp + rows − 1, lines.length − 1)`，非列模式 x = cols）或视口顶行（x = 0）。滚速 `_getMouseEventScrollAmount`（`:417-430`）：离画布上下边的距离钳到 ±50 再除 50，结果 = 符号 + `Math.round(offset × 14)`。
8. **覆盖键与列选择**：`shouldForceSelection`（`:437-447`）非 macOS 看 Shift，macOS 看 `alt && macOptionClickForcesSelection`；`shouldColumnSelect`（`:607-612`）= `alt && !(isMac && macOptionClickForcesSelection)`。
9. **选区事件**（`onSelectionChange`）：`clearSelection` 每次都发（`:267-272`，没有选区也发）；`selectAll`、`selectLines` 发；单击时若原来有选区发一次（`:557-560`）；松开和 `setSelection` 走 `_fireEventIfSelectionChanged`（`:746-776`，和上一次发的起终点比）。
10. **清选区的时机**：用户输入（`coreService.onUserInput`，`:139-143`）；行数变了（`:158-162`，列数变不清）；换缓冲（`:778-785`）；程序打开鼠标上报（`MouseService.ts:380-393` 的 `_syncMouseModeState` → `disable()`）；`reset`（`CoreBrowserTerminal.ts:1111`）。**`Terminal.clear()` 不清选区**（`CoreBrowserTerminal.ts:1075-1089`）——3 期交接的「`OnScrollbackCleared` 清选区」是我们加的，进 §15。RIS 经 `BufferSet.reset` 发 `onBufferActivate`（`BufferSet.ts:39-54`；本仓库 `Buffer.pas` 的 `TTyTerminalBufferSet.Reset` 同样发），所以换缓冲那一条就清掉了。
11. **选区的格子判定**（画的时候）：`DomRendererRowFactory.ts:534-552`，列模式按起终 x 的大小两种写法；选区底色用「不透明化」的选区色（主题底色上叠选区色，`ThemeService.ts:87-90`），聚焦 / 失焦两色（`:385`），选区前景只在主题给了才用（`:391-395`）。
12. **坐标**：选区用的格子由 `getCoords(…, isSelection = true)` 算（`src/browser/input/Mouse.ts:40-49`）：`x = ceil((px + 半格宽) / 格宽)` 钳到 `[1, cols + 1]`，`y = ceil(py / 格高)` 钳到 `[1, rows]`，再减 1、加 `ydisp`（`SelectionService.ts:397-410`）——点在一格的右半，选区从下一格的边界算。上报用的格子是 `isSelection = false`（x 钳到 `[1, cols]`）。浏览器坐标是小数；我们的设备像素取**像素中心**（`px + 0.5`），3 期 `CellAt` 的「整除再钳」正好等于上游，选区点另写一个函数（`TyTermSelectionPointAt`，Task 2）。

**上游鼠标（`src/browser/services/MouseService.ts`）**

13. **LCL 事件对上游事件**：`_sendEvent`（`:104-192`）——移动时按住的键按 `buttons` 位取，**左优先、再中、再右**（`:124-127`）；按下 / 抬起 `button < 3` 才是左中右，否则 NONE（随后被 `TriggerMouseEvent` 的「无键 + 非移动」丢掉）；按下只在程序接管鼠标且不是 `shouldForceSelection` 时上报（`:224-235`），上报后才在 document 上挂抬起 / 拖动监听（`:237-249`）；不带键的移动只在元素上（`:217-222`）。所以「这次按下是上报还是本地选择」在按下那一刻定，拖动、抬起跟着它，中途松开覆盖键不换路（选区服务的 mousemove 监听 `stopImmediatePropagation`，`SelectionService.ts:623`）。
14. **程序接管时右键**：上游照样上报右键按下 / 抬起；`contextmenu` 事件另外走 `rightClickHandler`（`CoreBrowserTerminal.ts:383-394`，只准备 textarea、macOS 默认先选词 `rightClickSelectsWord: isMac`，`OptionsService.ts:52`；`Clipboard.ts:83-96`）。浏览器原生菜单照弹——我们定的是「程序接管时右键只上报、不弹菜单；覆盖键 + 右键弹菜单」（spec §9.5.2，定稿时新加）。
15. **覆盖键剥修饰位**：上游只在 `mouseEventsRequireAlt` 时剥 Alt，而且**滚轮不剥**（`:175-179`）。我们按着覆盖键时按键事件根本不上报（第 13 条），所以 spec §9.5.2「覆盖键是 Alt 时要剥掉」无处可用：滚轮照上游不剥。写回（开工前问题二第 10 条）。
16. **LCL 捕获**：`TControl.CaptureMouseButtons` 默认只有 `[mbLeft]`（`lcl:controls.pp:1794-1795`；`include/control.inc:2515`、`:2536`、`:2555` 按键判断），中键、右键拖出控件收不到移动——本期设成三键。
17. **横向滚轮**：`DoMouseWheelHorz`（`lcl:include/control.inc:2392-2411`）按 `WheelDelta < 0` 分到 `DoMouseWheelLeft` / `Right`，这两个**拿不到 `WheelDelta`**（`controls.pp:1538-1539`），没法照竖向按 ±120 累计（触控板一次只给几十）。覆盖 `DoMouseWheelHorz` 本身（`virtual`，`:1537`）。
18. **光标形状**：上游 `cursor: text`（`css/xterm.css:39`），程序接管鼠标时 `default`（`:119-120`），链接 `pointer`（`:123-125`），列选择 `crosshair`（`:130`）。LCL 有 `SetTempCursor`（`controls.pp:1726`），换形状不改 `Cursor` 属性（`Cursor` 在 `TTyCustomControl` 上是 published 的，`Base.pas:487`）；但 LCL 在进入控件等时机会用 `Cursor` 复位（`control.inc:1244`、`:2995`），所以每次 `MouseMove` 重设。

**上游链接**

19. **网址识别**（`addons/addon-web-links`）：正则 `strictUrlRegex`（`WebLinksAddon.ts:21`）`/(https?|HTTPS?):[/]{2}[^\s"'!*(){}|\\\^<>`]*[^\s"':,.!?{}|\\\^~\[\]`()<>]/`；`LinkComputer.computeLink`（`WebLinkProvider.ts:59-101`）把折行段（向上看 `isWrapped` 且首字符不是空格、向下看下一行 `isWrapped`，碰到含空格的段或累计 2048 个 UTF-16 单元就停，`:113-153`）拼成一串（每段 `translateToString(true)`）再跑 `g` 正则；**每个匹配还要过 `isUrl`**（`:44-55`、`:72-75`）：`new URL(text)` 成功，且 `text` 小写后以「协议 // [用户[:密码]@] 主机[:非默认端口]」小写开头——spec §9.8 没提这一层。下标回映射 `_mapStrIdx`（`:160-199`）按 `getChars().length || 1` 递减，行尾空格子后面接宽字符的折行要 +1。
    - 实跑确认（`D:/Projects/xterm.js/out` + `addons/addon-web-links/out`，node）：`WebLinksAddon` 的正则可以用一个假终端的 `registerLinkProvider` 取出来（`_regex`），`LinkComputer.computeLink(y, regex, headless 终端, noop)` 在 headless 终端上直接跑，`aaa http://example.com aaa`（20 列）得 `http://example.com`、`start (5,1)`、`end (2,2)`。
    - JS `\s` 含 U+00A0、U+1680、U+2000–200A、U+2028/2029、U+202F、U+205F、U+3000、U+FEFF（中文全角空格 U+3000 会截断网址）；正则没有 `u` 标志，按 UTF-16 单元匹配。FPC `RegExpr` 按字节 / ANSI 处理 `\s`，对不上——手写扫描器（开工前问题二第 4 条）。
    - `isUrl` 的实际效果：主机里有非 ASCII → `new URL` 转成 `xn--…`，前缀必不等 → 不算链接；主机里有 `%` → 解码后前缀不等；IPv4 不是规范点分十进制（`0x7f.1`、`127.1`、`1.2.3.4.`）→ 不等；端口 `:080` 解析成默认端口 80 → 前缀只到主机 → **算**链接；`:08080` → 前缀 `:8080` → 不算；只有密码没有用户名 → 前缀不带用户信息 → 不算；用户信息里的 `; = [ ]`、非 ASCII、多余的 `@` / `:` 会被百分号编码 → 不算。
20. **OSC 8**（`src/browser/OscLinkProvider.ts`）：一行里按链接号连续的格子成段（`:22-104`，扫到 `getTrimmedLength` 为止），段在折行处上下接（`_getRangeWithLineWrap` `:108-172`）；**没有 `linkHandler.allowNonHttpProtocols` 时，URI 不是 http / https 或解析失败的段直接不当链接**（`:64-75`）——不下划线、不能点。spec §9.8 写成「激活时默认拒绝非 http(s)」，位置和含义都不对（开工前问题一第 2 条）。
21. **Linkifier**（`src/browser/Linkifier.ts`）：OSC 8 提供者先注册（`CoreBrowserTerminal.ts:182`），和网址重叠的后注册者被去掉（`_removeIntersectingLinks` `:153-173`，按 `[start.x, end.x]` 闭区间逐列占位）；命中判定 `_linkAtPosition` `:370-375`（行 × 列数 + 列，闭区间，1 起）；**上游悬停不要修饰键就下划线、手形，单击（按下和抬起在同一条链接上）就激活**（`:217-233`、`_handleNewLink` `:246-310`）——我们定的 Ctrl+悬停 / Ctrl+单击是偏离，spec §15 只写了「程序接管时 Ctrl+单击仍开链接」，少了这一条（写回）。
22. 实跑确认 `out/browser/services/SelectionService.js`、`out/browser/OscLinkProvider.js`、`addons/addon-web-links/out/WebLinkProvider.js`、`addons/addon-clipboard/out/ClipboardAddon.js` 都能在 node 里加载；`SelectionService` 用假元素、假 `coreBrowserService.window`（`requestAnimationFrame` / `setInterval` 空实现）和 headless 终端自己的 `_bufferService` / `coreService` / `optionsService` / `mouseStateService` 构造，`_selectWordAt([6, 0], true)` 在 `aaa http://example.com aaa` 上得 `[4, 0]` + 长度 18、`selectionText` = `http://example.com`。所以选区、网址、OSC 8、OSC 52 的期望值全部可以由上游代码本身生成。

**OSC 52（`addons/addon-clipboard/src/ClipboardAddon.ts`）**

23. `data.split(';')`，不足两段直接返回；只看前两段 `Pc`、`Pd`（`:32-39`）；`Pd = '?'` 读：`\x1b]52;<Pc>;<base64(UTF-8 文本)>\x07` 经 `terminal.input(…, false)` 回（`:27-30`、`:40-52`）；否则 base64 解码成文本写剪贴板，解码失败写空串（`:54-66`）。解码：node 22 没有 `Uint8Array.fromBase64`（实测 `typeof` 为 `undefined`），走 `atob`（WHATWG 宽容 base64：去 ASCII 空白、可省 `=`、长度模 4 余 1 或有非法字符就失败）+ `TextDecoder`（UTF-8，坏序列按最大子串换 U+FFFD，**开头的 BOM 去掉**），`:104-124`。浏览器新版走 `fromBase64`，差别只在极端输入；基准取 node 的。

**PTY 与平台**

24. FPC 3.2.2 的 Windows 单元有 `EXTENDED_STARTUPINFO_PRESENT`（`fpc:rtl/win/wininc/defines.inc:702`）、`PeekNamedPipe`、`CancelIoEx`，**没有** `CreatePseudoConsole` / `ResizePseudoConsole` / `ClosePseudoConsole`、`InitializeProcThreadAttributeList` / `UpdateProcThreadAttribute` / `DeleteProcThreadAttributeList`、`STARTUPINFOEXW`、`RtlGetVersion`——全部自己声明，ConPTY 三个和 `RtlGetVersion` 按名动态取。
25. FPC 3.2.2 的 RTL 没有 `forkpty` / `openpty` / `posix_openpt` / `grantpt`（只在废弃的 `packages/libc`）；有 `FpFork`、`FpSetsid`、`FpExecve`（Linux 上是直接系统调用，`rtl/linux/bunxsysc.inc:307`、`:441`）、`FpIoctl`、`TIOCSWINSZ`（`rtl/linux/termios.inc:49`；`rtl/darwin/termios.inc:498`）、`TIOCSCTTY`（`rtl/darwin/termios.inc:504`，Linux 同样在 `termios.inc`）。`posix_openpt` 系列在 glibc 和 macOS libSystem 里都有，不用链 libutil（WSL 里只有 `libutil.so.1` 和 `libutil.a`、没有 `libutil.so`，链 `-lutil` 还得装开发包）。
26. 本机 WSL：`Ubuntu`，WSL1（内核 `4.4.0-19041-Microsoft`），glibc 2.39，有 `fpc` 3.2.2、`gcc`、`tmux`、`lazbuild`。WSL1 支持 `/dev/ptmx`。Unix 后端能在这里编成纯 FPC 控制台程序跑（Task 15）；LCL 示例的 Linux 版仍待真机。
27. **分支**：`main` 没有 `feat/terminal` 之外的新提交（`git log feat/terminal..main` 为空），本期不用合并。3 期签收全量 8168 条。

**本仓库**

28. 控件现状（`source/tyControls.Terminal.pas`，2703 行）：`MouseDown` 只取焦点，`MouseUp` 什么都不做，没有 `MouseMove`；`DoMouseWheel` 三种去向已做（`:2259-2329`）；`KeyDown` 里 `tkrSelectAll` 不算动作（`:2167`）；`CopyToClipboard` 空（`:2401-2405`）；`ReadClipboardText` / `WriteClipboardText` 是虚方法（`:2095-2103`）；构造没设 `Cursor`（Memo 设 `crIBeam`，`Memo.pas:959`）。
29. `TTyTerminalBuffer.LinesTrim`（`Buffer.pas:2502-2524`）只调标记；缓冲的行表 `OnTrim` 被缓冲自己占着（`:2043`），外面挂不上。
30. Core 没有 `onUserInput`：`TriggerDataEvent`（`Core.Services.inc:33-50`）只发 `OnRequestScrollToBottom` 和 `OnData`。上游 `CoreService.triggerDataEvent` 在 `wasUserInput` 时发 `onUserInput`（`CoreService.ts:86-89`），`disableStdin` 时整个早退、不发。
31. 右键菜单现成的 `TTyTextEditMenu`（`TextMenu.pas:67-`）固定六项（撤销、重做、剪切、复制、粘贴、全选，`:188-202`），没有加项的口子；`rsTextMenuCopy` / `rsTextMenuPaste` / `rsTextMenuSelectAll` 在 `StrConsts.pas:259-261`。
32. 多击：库的约定是 `TyMultiClickCount`（`TextMenu.pas`，`ssDouble` 认第二击、时间窗 + 距离认第三击，注释「no widgetset marks the third」），Edit / Memo 都用它（[[edit-memo-text-editing-batch]]）。spec §9.5.5 写的 `ssTriple` / `csTripleClicks` 不用。
33. 测试工程搜索路径已经有 `../examples/terminal`（`tests/tytests.lpi:50`），示例的单元可以直接进测试。
34. 选区 token 与键已在基础层（`themes/light.tycss:96-98`、`:754-755`、`:772`），3 期测试断言解析得出（`test.terminal.view.theme.pas:99-101`、`:211-221`）；`TTyStyleSet.Present` 有 `tpTextColor`（`Types.pas:71-78`），「选区前景写了才用」靠它判断（Task 7 核实基础层没有继承来的 `color`）。

---

## Win32InputMode 与 ConPTY 鼠标：结论

**本期不做 win32-input-mode，列入以后；ConPTY 鼠标控件不需要额外工作，是否真能收到要真机看。**

- `Win32InputMode.ts` 只管键盘（`xterm:src/common/input/Win32InputMode.ts:1-14`：`CSI Vk ; Sc ; Uc ; Kd ; Cs ; Rc _`，要扫描码、按下和抬起都发），和鼠标无关；它靠 DECSET 9001 打开，而且要选项 `vtExtensions.win32InputMode`（`InputHandler.ts:2043-2047`、`:2293-2296`、`:2393`）。控件 3 期起把这个扩展一律屏蔽（`MaskUnencodedExtensions`，spec §15）：ConPTY 若在启动时发 `CSI ? 9001 h`，我们不认、DECRQM 答「不认识」，ConPTY 退回普通 VT 键盘输入。要做它得有扫描码（LCL 的 `KeyDown` 拿不到，各 widgetset 另取），不是本期的量。
- ConPTY 下的鼠标：控制台程序打开 `ENABLE_MOUSE_INPUT` 时，ConPTY 应该向终端发标准的 DECSET 1000 / 1002 / 1003 / 1006 请求鼠标，再把终端报上来的 SGR 序列转成控制台的 `MOUSE_EVENT`——终端侧就是本期做的标准鼠标上报，不需要特殊处理。**这一段来自对微软 ConPTY 行为的了解，本机没有源码或文档可核，构建 19044 上有没有这条通路也不确定**，所以只写成真机项：示例加「记录 PTY 输出」开关，把 ConPTY 启动后发来的前 4 KB 以十六进制列进侧栏，真机上看它发了哪些模式（`?9001h`、`?1004h`、`?1003h` / `?1006h`），结果写回 spec §12.4 / §16（真机验收第 33、34 项）。
- 键盘经 ConPTY：普通 VT 序列，ConPTY 转成 `KEY_EVENT`。Alt+键、方向键、功能键的效果在真机项里看（第 32 项）。

---

## 开工前要定的问题

每条都给了建议，**计划正文按建议写**；改了哪条，执行时改对应任务，收尾时（Task 18）写回 spec。

### 一、产品方向 / 用户可见（问用户）

> **状态（2026-09-29）**：六条先按建议执行（右键菜单四项自建、`AllowNonHttpLinks` 默认 False、macOS 右键先选词、Windows 默认 `%COMSPEC%` 并列出 pwsh/wsl、Win/macOS 中键无动作、双击链接照上游选整条），已告知用户，最终一次性验收时可改。第二类主控按建议采纳。`main` 无新提交，不用合并。

1. **右键菜单放几项？**（核实记录 31）
   spec §9.6.4 说复用 `TTyTextEditMenu`：六项里剪切、撤销、重做灰掉，另加「清屏」——但那个菜单没有加项的口子，要加就得改 Edit / Memo 共用的 `TextMenu.pas`。本期任务说的是四项：复制、粘贴、全选、清屏。
   **建议**：终端自建四项菜单（复制 / 粘贴 / 分隔线 / 全选 / 清屏），用同一个主题化的 `TTyPopupMenu`，复制粘贴全选三个字串沿用库里已有的翻译，只新增「清屏」一条；不实现 `ITyTextEditActions`（它就是为那六项设计的）。设了 `PopupMenu` 就用宿主的。写回 §9、§9.6.4。
2. **OSC 8 里非 http / https 的链接（`file://`、`ssh://`）算不算链接？**（核实记录 20）
   上游默认**不算**：不下划线、不能点（有 `linkHandler.allowNonHttpProtocols` 才算）。spec §9.8 写的是「交宿主」。`ls --hyperlink` 输出的全是 `file://`。
   **建议**：照上游，控件默认只认 http / https；加 published 属性 `AllowNonHttpLinks: Boolean = False`，打开后全部交宿主（`OnLinkActivate` 带原样 URI）。网址识别本来就只认 http(s)，不受影响。另一个做法是按 spec 全认、交宿主判断——代价是 `file://` 也会在 Ctrl+悬停时画下划线，宿主不处理时点了没反应。
3. **macOS 上右键要不要先选中指针下的词？**（核实记录 14）
   上游在 macOS 上默认开（`rightClickSelectsWord: isMac`）：右键点在选区外时先选中那个词（不含纯空白），再弹菜单，于是菜单里「复制」直接可用。
   **建议**：照上游，只在 macOS 上这样做，不加属性。
4. **Windows 上「真 shell」默认起什么？**
   **建议**：默认 `%COMSPEC%`（cmd.exe，一定在、起得最快）；命令下拉里另给 `powershell.exe`、`pwsh.exe`（找得到才列）、`wsl.exe`（找得到才列）；可以手改命令行。Linux / macOS 默认 `$SHELL`（没有就 `/bin/sh`），加 `-l`（登录 shell，macOS 终端的惯例）。
5. **程序没接管鼠标时，Windows / macOS 上中键做什么？**
   Linux 是粘贴 PRIMARY（spec §17.1 第 9 条已定）。Windows Terminal 中键默认什么都不做，PuTTY 是粘贴。
   **建议**：Windows / macOS 上中键不做任何事（程序接管时照常上报）。
6. **双击在链接上选整条链接**（核实记录 6）
   上游双击时指针下有链接就选整条链接（冒号、斜杠、问号都在里面），不看修饰键——上游悬停本来就认出链接了。我们的链接悬停要按 Ctrl，但双击选链接的逻辑可以独立做。
   **建议**：照上游，双击时指针下有链接（OSC 8 或识别出的网址，受 `DetectUrls` 控制）就选整条，不要求按 Ctrl。

### 二、实现层面（主控定）

1. **选区照上游用坐标 + trim，不用标记**（核实记录 1、29）：`TTyTerminalBuffer` 加一个纯查询 `TrimmedLines: Int64`（这个缓冲从头上挤掉的累计行数，`LinesTrim` 里加 `AAmount`）；选区记下建立时的读数，每次用选区之前（绘制、鼠标、取文本、`EndDrive`）按差值调一次 `HandleTrim`——上游的调整是逐次减、判负，按累计量一次减结果相同（`SelectionModel.ts:123-144` 只判「是否已小于 0」，单调）。换缓冲（含 RIS / `Reset`，都发 `OnBufferActivate`）时清选区并重取读数。比在 `Buffer` 上加事件、再由控件订阅两个缓冲（`Reset` 会换对象）简单。写回 §9.5.5。
2. **Core 加 `OnUserInput: TNotifyEvent`**（核实记录 30）：`TriggerDataEvent` 在 `AWasUserInput` 时、`OnData` 之前发（上游顺序：`onRequestScrollToBottom` → `onUserInput` → `onData`）；`ReadOnly` 时整个早退、不发。控件用它清选区。写回 §7.6。
3. **两个新单元**：`tyControls.Terminal.Selection`（选区模型与服务、像素→选区点、拖动滚速、OSC 52 编解码）、`tyControls.Terminal.Links`（网址扫描、`isUrl`、OSC 8 段、去重叠、命中判定、http(s) URL 前缀解析）。都只依赖 `SysUtils`、`Classes`、`Types`、`Terminal.Buffer`、`Unicode.Width`，不引 LCL；进运行时包；notices 标题加这两个文件。写回 §2.1、§14。
4. **网址识别不用 FPC `RegExpr`，手写扫描器**（核实记录 19）：在 `UnicodeString`（UTF-16）上逐单元照正则的语义走——`(https?|HTTPS?)://` 起头（大小写只有这四种），贪婪吃「不在集合 X 里」的一段，再回退找最后一个「不在集合 Y 里」的字符作结尾（紧跟在这一段后面的那个字符也可以当结尾，只要它不在 Y 里——X 与 Y 的差集只有 `*`）；找不到结尾就从下一个下标再试；匹配过后下一次从匹配末尾开始（JS `g` 的 `lastIndex`）。`\s` 用 `Buffer` 里现成的 `TyTermIsJsWhitespace`。写回 §9.8。
5. **`isUrl` 与 OSC 8 协议检查的移植范围**（核实记录 19、20）：写一个「http / https 的 WHATWG URL 前缀解析」：去首尾 C0 与空格、删 Tab / 换行；协议（字母起头、`[A-Za-z0-9+.-]*`、`:`，小写后是 `http` / `https`）；`//` 之后（特殊协议也吃多余的 `/`、`\`）到 `/ ? #` 为权威部分；最后一个 `@` 分用户信息（用户名 / 密码按用户信息编码集编码）；主机：`[` 开头按 IPv6 解析并规范化，否则百分号解码、查禁止字符、「以数字结尾」就按 IPv4 解析并规范化，纯 ASCII 小写；端口：纯数字、≤ 65535、等于默认端口就去掉。输出「成功与否」和上游 `isUrl` 里那个 `parsedBase`。**偏离**：主机含非 ASCII 时不做 IDNA——`isUrl` 直接判否（上游转 punycode 后前缀必不等，结果相同），OSC 8 的协议检查按「成功」算（上游 UTS46 失败的少数字符我们不查）；`xn--` 标签不校验 punycode。两条进 §15。夹具里不放这两类输入，另写手工用例钉住我们的答案。
6. **选区点与格子都按像素中心算**（核实记录 12）：`TyTermSelectionPointAt` = `x = ⌊(2·px + 格宽) / (2·格宽)⌋` 钳 `[0, cols]`，`y = ⌊py / 格高⌋` 钳 `[0, rows − 1]`（px / py 相对网格左上角的整数设备像素；由上游 `ceil((px + 0.5 + 格宽/2) / 格宽) − 1` 对整数化简而来；负数像素结果钳成 0，取整方向不影响）；基准用上游 `getCoords(…, true)` 喂 `clientX = px + 0.5`。例：格宽 7，`px = 3`（第 0 格中心）→ 0，`px = 4`（右半）→ 1。
7. **多击用库的 `TyMultiClickCount`**（核实记录 32），不用 `ssTriple`。写回 §9.5.5。
8. **`CaptureMouseButtons := [mbLeft, mbMiddle, mbRight]`**（核实记录 16），构造里设。
9. **横向滚轮覆盖 `DoMouseWheelHorz`**（核实记录 17），±120 累计同竖向，余数独立；程序没要滚轮时交还父控件（`Result := False`，终端没有横向可滚）。写回 §9.5.3。
10. **覆盖键不剥修饰位**（核实记录 15）：按着覆盖键时按键、拖动、抬起一律本地处理、不上报；滚轮照上游带着修饰位上报。写回 §9.5.2。
11. **列选择让位于覆盖键**：Alt 是覆盖键（macOS 默认 Option，或 `SelectionOverrideKey = tsoAlt`）时不做列选择——上游 macOS 那条规则的推广（核实记录 8）。
12. **拖动自动滚的 50 像素阈值按 PPI 缩放**（逻辑像素，`MulDiv(50, PPI, 96)`）；滚速公式照上游（`Floor(x + 0.5)` 模拟 `Math.round`，负数 `.5` 向正无穷）。
13. **`CopyOnSelect` 与 PRIMARY 在「一次选择结束」时写一次**：松开左键、双击、三击、Shift+单击扩展、键盘全选之后，选区非空才写（xterm 的惯例是松开时设 PRIMARY；上游浏览器层在拖动中每步重写 textarea，那是浏览器机制）。
14. **PRIMARY 只在 X11 惯例的平台**：`TyTerminalUsesPrimary = {$IF DEFINED(UNIX) AND NOT DEFINED(DARWIN)}True{$ELSE}False{$ENDIF}`，受保护标志 `FUsesPrimary` 可在测试里改（同 `FIsMac`）；读写走两个新虚方法 `ReadPrimaryText` / `WritePrimaryText`（默认 `PrimarySelection.AsText`，`lcl:clipbrd.pp:236`、`:268-270`）。Wayland 下行为进真机。
15. **OSC 52 在解析中同步问宿主**：上游读剪贴板是 Promise、解析器会停住等它，应答顺序不乱；我们没有异步处理器，同步发 `OnOsc52` 才能保持顺序。宿主可以在事件里弹模态框（Core 的重入规则保证安全，spec §3.1）。应答走 `Core.Input(…, False)`。控件注册的 OSC 52 处理器在 `to52Off` 时吞掉（不进 `OnOsc`）。
16. **Unix 用 `posix_openpt` 系列，不用 `forkpty`**（核实记录 25）：`posix_openpt(O_RDWR or O_NOCTTY)`、`grantpt`、`unlockpt`、`ptsname` 自己声明 `external 'c'`；`FpFork` 之后子进程**只做系统调用**：`FpSetsid`、`FpOpen(从端)`、`FpIoctl(TIOCSCTTY)`、`FpDup2` 三次、`FpClose`、`FpExecve`（路径、argv、envp 全在 fork 之前备好成 `PChar` 数组）、失败 `FpExit(127)`——LCL 程序是多线程的，fork 之后子进程里分配内存可能死锁。读用 `FpPoll` 同时等主端和一个自唤醒管道，关闭时写唤醒管道。
17. **示例的流量控制从 5 期提前到本期**（本期任务要求）：spec §12.3 的高低水位（1 MB / 256 KB）落在示例的会话里（读线程在未完成字节超过高水位时停读，`Write` 回调把它降到低水位以下时继续）。5 期仍做控件侧的 `Write` 回调顺序测试和性能。写回 §12.3、§18。
18. **PTY 会话的线程**：读线程、写线程各一个（写 PTY 在后台，大段粘贴不卡界面；spec §12.2 写的「写 PTY 在主线程」改掉，写回）；Windows 另有一个退出等待线程（ConPTY 在子进程退出后不会自己关输出管道，要 `ClosePseudoConsole` 才会，而它在 24H2 之前的版本会阻塞到输出排空——所以由等待线程调，不在主线程调）。读线程到主线程照 spec §3.5：加锁队列、从空变非空时唤醒主线程一次。会话单元不引 `Forms`：唤醒是注入的回调，示例里接 `Application.QueueAsyncCall`，WSL 控制台测试里接一个事件。
19. **ConPTY 的 `COORD` 按 `DWORD` 打包传**（`(行 shl 16) or 列`），不按记录传值：两个函数的 `COORD` 参数是按值的 4 字节结构，自己打包不依赖编译器对小记录的传参约定。
20. **Windows 构建号用 `RtlGetVersion`**（ntdll，按名取）：`GetVersionEx` 没有兼容性清单时会谎报。
21. **选区前景「写了才用」**：`TyTerminalSelection` 的无状态 / `:focus` 样式里 `tpTextColor in Present` 才用 `color`。Task 7 先核实基础层与 17 个主题里这个键的 `Present` 没有继承来的 `tpTextColor`；有的话改成判「规则层显式声明」（照 `StyleModel` 已有的查询，不改共享文件），实在查不到就停下交主控。
22. **API 名字照 spec**：链接事件叫 `OnLinkActivate(Sender; const AUri: string; AFromOsc8: Boolean)`（本期任务里写的 `OnLinkClick` 以 spec 为准）。
23. **`OnScrollbackCleared` 清选区**（3 期交接）：上游 `clear()` 不清（核实记录 10），这是我们加的，进 §15。

---

## 需要改共享文件的地方

**结论：本期不需要改 `Base.pas`、`Painter.pas`、`StyleModel.pas`，也不改 `TextMenu.pas`。**

| 看起来要改 | 为什么 | 本期怎么做 |
|---|---|---|
| `TextMenu.pas` 的 `TTyTextEditMenu` 只有固定六项 | 要加「清屏」 | 终端自建菜单（开工前问题一第 1 条），只复用 `StrConsts` 里的三个字串 |
| `Base.pas` 发布了 `Cursor`，控件动态换形状会冲掉宿主设的值 | 光标形状随上报 / 链接 / 列选择变 | 用 LCL 的 `SetTempCursor`（核实记录 18），不写 `Cursor` 属性；宿主设了非 `crDefault` 的 `Cursor` 时，平常的形状用宿主的 |
| `StyleModel.pas` 看不出「这条规则写没写 `color`」 | 选区前景写了才用 | 用 `TTyStyleSet.Present`（开工前问题二第 21 条）；不行再交主控 |

**会改的库内非共享文件**：`source/tyControls.StrConsts.pas` 加一条 `rsTerminalMenuClear`（库的字串都在这里，照常加）；`languages/tycontrols.strconsts.en.po` / `.zh_CN.po` 加对应条目（`.pot` 由主控编包时生成）。

**会改的终端单元**（不是共享文件，但 3 期定过「不顺手改」，这里明列）：`Terminal.Buffer.pas` 加 `TrimmedLines`（Task 4）；`Terminal.Core.pas` / `Core.Services.inc` 加 `OnUserInput`（Task 4）；`Terminal.Render.pas` 的行绘制器加选区与链接下划线两段（Task 7）。

---

## 接口清单（全计划用这一套名字）

和 spec 不同的地方标 ★，收尾写回。

### `source/tyControls.Terminal.Selection.pas`（新 ★，Task 2）

```pascal
type
  { 选区点：Col 是 0..Cols 的边界（不是格子），Row 是缓冲的绝对行（0 = 滚回最早一行） }
  TTyTermSelPoint = record
    Col, Row: Integer;
  end;
  TTyTermSelMode = (tsmNormal, tsmWord, tsmLine, tsmColumn);   { SelectionService.ts:56-61 }

  { SelectionModel.ts:12-145 }
  TTyTermSelectionModel = class
  public
    IsSelectAllActive: Boolean;
    StartLength: Integer;
    HasStart, HasEnd: Boolean;
    Start, Finish: TTyTermSelPoint;             { selectionStart / selectionEnd（end 是保留字） }
    constructor Create(ABuffers: TTyTerminalBufferService);
    procedure Clear;
    function FinalStart(out P: TTyTermSelPoint): Boolean;   { False = undefined }
    function FinalEnd(out P: TTyTermSelPoint): Boolean;
    function AreReversed: Boolean;
    function HandleTrim(AAmount: Integer): Boolean;          { True = 要重画 }
  end;

  { 一条链接的范围（Linkifier 的 IBufferRange：1 起、闭区间），双击选链接用；Links 单元引用它 }
  TTyTermLinkRange = record
    StartX, StartY, EndX, EndY: Integer;
  end;
  PTyTermLinkRange = ^TTyTermLinkRange;

  { SelectionService.ts 的非 DOM 部分。所有「按下 / 拖动 / 松开」的入参都已经是选区点；
    路由（上报还是选择、覆盖键、列选择的判定）在控件里。 }
  TTyTermSelection = class
  public
    constructor Create(ABuffers: TTyTerminalBufferService);
    destructor Destroy; override;
    { 按下：AClicks 1..3；AIncremental = Shift 扩展（只在程序没接管鼠标时）；AColumn = 列选择；
      ALink：双击时指针下的链接（nil = 没有）。handleMouseDown 的左键部分，:483-499 }
    procedure Press(const APoint: TTyTermSelPoint; AClicks: Integer; AIncremental, AColumn: Boolean;
      ALink: PTyTermLinkRange = nil);
    { 拖动：_handleMouseMove :619-686；AScrollAmount 由 TyTermDragScrollAmount 算 }
    procedure DragTo(const APoint: TTyTermSelPoint; AScrollAmount: Integer);
    { 自动滚的一拍：返回要滚的行数（0 = 不滚）；控件滚完调 AfterDragScroll（:692-716） }
    function DragScrollAmount: Integer;
    procedure AfterDragScroll;
    { 松开：_handleMouseUp 的非 Alt+单击部分，:722-744 }
    procedure Release;
    { macOS 右键：rightClickSelect，:820-827 }
    procedure RightClickSelect(const APoint: TTyTermSelPoint; ALink: PTyTermLinkRange = nil);
    procedure SelectAll;                                      { :366-370 }
    procedure SelectLines(AFirst, ALast: Integer);            { :372-380 }
    procedure SetSelection(ACol, ARow, ALength: Integer);     { :811-818 }
    procedure Clear;                                          { clearSelection :267-272 }
    procedure HandleTrim(AAmount: Integer);                   { :386-391 }
    function HasSelection: Boolean;
    function Text(const ALineSep: string): string;            { selectionText :203-262；NBSP → 空格 }
    { 画的时候：这一绝对行里被选中的列 [AFrom, ATo)；False = 这一行没有（DomRendererRowFactory.ts:534-552） }
    function RowSpan(AAbsRow: Integer; out AFrom, ATo: Integer): Boolean;
    function FinalStart(out P: TTyTermSelPoint): Boolean;
    function FinalEnd(out P: TTyTermSelPoint): Boolean;
    property Mode: TTyTermSelMode read FMode;
    property Dragging: Boolean read FDragging;                { 按下到松开之间（上游挂着 mousemove 监听） }
    property WordSeparators: UnicodeString read FSeparators write FSeparators;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;   { = onSelectionChange 的每一次 }
    property OnRedraw: TNotifyEvent read FOnRedraw write FOnRedraw;   { = refresh() 的每一次 }
    property Model: TTyTermSelectionModel read FModel;                 { FOR THE TESTS }
  end;

{ 像素（相对网格左上角的设备像素）→ 选区点的 (列边界, 视口行)；像素中心规则（开工前问题二第 6 条） }
function TyTermSelectionPointAt(APx, APy, ACellW, ACellH, ACols, ARows: Integer): TPoint;
{ 拖动自动滚速：AOffsetY 相对网格顶（设备像素，可为负），AHeight = 网格高，AThreshold = 50 按 PPI；
  0 = 在网格内。_getMouseEventScrollAmount :417-430 }
function TyTermDragScrollAmount(AOffsetY, AHeight, AThreshold: Integer): Integer;
{ OSC 52（ClipboardAddon.ts:27-66）：拆参数；base64（atob 宽容规则）→ UTF-8（TextDecoder 规则：去 BOM、
  坏序列换 U+FFFD）；应答串 }
function TyTermOsc52Split(const AData: string; out APc, APd: string): Boolean;   { False = 不足两段 }
function TyTermOsc52Decode(const APd: string): string;           { 解码失败 = '' }
function TyTermOsc52Reply(const APc, AText: string): RawByteString;  { ESC ] 52 ; Pc ; b64 BEL }
```

### `source/tyControls.Terminal.Links.pas`（新 ★，Task 3）

```pascal
type
  TTyTermLinkSource = (tlsOsc8, tlsUrl);
  TTyTermLink = record
    Range: TTyTermLinkRange;    { 1 起、闭区间，同上游 IBufferRange }
    Text: string;               { UTF-8：OSC 8 是 URI，网址是匹配到的串 }
    Source: TTyTermLinkSource;
    LinkId: Int64;              { OSC 8 的链接号；网址为 0 }
  end;
  TTyTermLinks = array of TTyTermLink;

{ http(s) URL 的前缀解析（开工前问题二第 5 条）：成功时 ABase = 上游 isUrl 里的 parsedBase，
  AIsHttp = 协议是 http / https }
function TyTermParseUrlPrefix(const AText: UnicodeString; out ABase: UnicodeString;
  out AIsHttp: Boolean): Boolean;
{ WebLinkProvider.ts:44-55 }
function TyTermIsUrl(const AText: UnicodeString): Boolean;
{ strictUrlRegex 的一次 exec：从 AFrom（0 起 UTF-16 下标）起找下一个匹配；False = 没有 }
function TyTermNextUrlMatch(const S: UnicodeString; AFrom: Integer; out AStart, ALength: Integer): Boolean;
{ LinkComputer.computeLink（WebLinkProvider.ts:59-101）：AY 是 1 起的绝对行 }
function TyTermComputeUrlLinks(ABuffer: TTyTerminalBuffer; AY: Integer): TTyTermLinks;
{ OscLinkProvider.provideLinks（:22-104）：AAllowNonHttp = linkHandler.allowNonHttpProtocols }
function TyTermComputeOsc8Links(ABuffer: TTyTerminalBuffer; ALinks: TTyTerminalOscLinks; AY: Integer;
  AAllowNonHttp: Boolean): TTyTermLinks;
{ Linkifier._removeIntersectingLinks（:153-173）：按提供者顺序（OSC 8 在前），就地去掉和前面重叠的 }
procedure TyTermRemoveIntersectingLinks(AY, ACols: Integer; var AReplies: array of TTyTermLinks);
{ Linkifier._linkAtPosition（:370-375）：AX / AY 1 起 }
function TyTermLinkAtPosition(const ALink: TTyTermLink; AX, AY, ACols: Integer): Boolean;
{ 控件用：绝对行 AAbsRow（0 起）、列 ACol（0 起）处的链接；两个提供者、去重叠、命中，全在这里 }
function TyTermFindLinkAt(ABuffer: TTyTerminalBuffer; ALinks: TTyTerminalOscLinks; ACol, AAbsRow,
  ACols: Integer; ADetectUrls, AAllowNonHttp: Boolean; out ALink: TTyTermLink): Boolean;
```

### `source/tyControls.Terminal.Buffer.pas` / `Core.pas`（改 ★，Task 4）

```pascal
  TTyTerminalBuffer = class
    { 从头上挤掉的累计行数（LinesTrim 每次加 AAmount）；纯查询，选区按差值调整 }
    property TrimmedLines: Int64 read FTrimmedLines;
  TTyTerminalCore = class
    { CoreService.onUserInput：TriggerDataEvent 在 AWasUserInput 时、OnData 之前；ReadOnly 时不发 }
    property OnUserInput: TNotifyEvent read FOnUserInput write FOnUserInput;
```

### `source/tyControls.Terminal.Render.pas`（改，Task 7）

行绘制器 `TTyTermRowPainter` 加字段（`PaintRow` 签名不变，调用前按行设）：

```pascal
    SelFrom, SelTo: Integer;        { 这一行被选中的列 [SelFrom, SelTo)；SelFrom >= SelTo = 没有 }
    SelColor: TBGRAPixel;           { 可带 alpha：叠在格子底色上（字形之前） }
    SelInk: Cardinal;               { 选区前景 $RRGGBB }
    SelHasInk: Boolean;             { 主题写了选区 color 才 True }
    LinkFrom, LinkTo: Integer;      { 这一行悬停链接的列 [LinkFrom, LinkTo)；没有 = 空 }
    LinkColor: Cardinal;            { 单线下划线的颜色 }
```

以及一处混色函数 `TyTermBlendOver(ABg: Cardinal; const AOver: TBGRAPixel): Cardinal`（每通道 `(bg·(255−a) + over·a + 127) div 255`），像素测试的期望值用同一个公式算。

### `source/tyControls.Terminal.pas`（改，Task 5–12）

```pascal
type
  TTyTerminalSelectionOverrideKey = (tsoDefault, tsoShift, tsoAlt, tsoNone);
  TTyTerminalOsc52Policy = (to52Off, to52Write, to52ReadWrite);
  TTyTerminalLinkEvent = procedure(Sender: TObject; const AUri: string; AFromOsc8: Boolean) of object;
  TTyTerminalOsc52Event = procedure(Sender: TObject; AWrite: Boolean; const ASelection: string;
    var AText: string; var AAllow: Boolean) of object;

  TTyTerminalView = class(TTyCustomControl, ITyImeEditable, ITyScrollBarFrameHost)   { ★ 不加 ITyTextEditActions }
  public
    procedure SelectAll;
    procedure ClearSelection;
    procedure Select(ACol, AAbsRow, ALength: Integer);          { = setSelection }
    procedure SelectLines(AFirst, ALast: Integer);               { 绝对行 }
    procedure CopyToClipboard;                                   { 有选区才写 }
    property SelectionText: string read GetSelectionText;        { 行间 LineEnding }
    property HasSelection: Boolean read GetHasSelection;
  published
    property SelectionOverrideKey: TTyTerminalSelectionOverrideKey default tsoDefault;
    property Osc52: TTyTerminalOsc52Policy default to52Off;
    property WordSeparators: string stored WordSeparatorsStored;  { 构造值 ' ()[]{}'',"`' }
    property CopyOnSelect: Boolean default False;
    property DetectUrls: Boolean default True;
    property AllowNonHttpLinks: Boolean default False;           { ★ 开工前问题一第 2 条 }
    property PopupMenu;                                          { 基类已 published；设了就代替内置菜单 }
    property OnLinkActivate: TTyTerminalLinkEvent;
    property OnOsc52: TTyTerminalOsc52Event;
    property OnSelectionChange: TNotifyEvent;
  protected
    FUsesPrimary: Boolean;                                       { ★ 平台标志，测试可改 }
    function ReadPrimaryText: string; virtual;                   { ★ }
    procedure WritePrimaryText(const S: string); virtual;        { ★ }
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheelHorz(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure DoContextPopup(MousePos: TPoint; var Handled: Boolean); override;
    procedure DragScrollTick;                                    { ★ 自动滚计时器的回调转这里；测试直接调 }
    function OverrideHeld(Shift: TShiftState): Boolean;          { ★ 覆盖键按着没有 }
    function ColumnWanted(Shift: TShiftState): Boolean;          { ★ Alt 且覆盖键不是 Alt }
    function LinkAt(ACol, AViewRow: Integer; out ALink: TTyTermLink): Boolean;   { ★ Task 10 }
    procedure UpdateContextMenu;                                 { ★ 建菜单、按状态设 Enabled }
    procedure ShowContextMenu(const AClientPos: TPoint); virtual;   { ★ 测试的缝：不真弹 }
    function CurrentShiftState: TShiftState; virtual;            { ★ 默认 GetKeyShiftState；菜单先于按下到时用 }
    { FOR THE TESTS：Selection（TTyTermSelection）、Hover、DragTimerActive、ContextMenu、
      Route（这次按下走哪条路） }
  end;
```

**控件新接管的 Core 事件**：`OnUserInput`（清选区）。控件文档的「宿主别改写」清单加上它。

### 示例（新，Task 13–16）

| 单元 | 内容 |
|---|---|
| `examples/terminal/uptysession.pas` | `TPtyBackend`（抽象：`Start` / `Read` / `Write` / `Resize` / `Shutdown` / `ExitCode`）、`TPtySession`（读线程、写线程、加锁队列、背压、唤醒回调、`Pump` 在主线程取数据与退出通知）。只引 `Classes`、`SysUtils`、`SyncObjs` |
| `examples/terminal/uptywin.pas` | `{$IFDEF MSWINDOWS}`：`TConPtyBackend`、`TPipeBackend`（在一对现成管道上读写，给测试和 ConPTY 共用）、`TyWindowsBuildNumber`（`RtlGetVersion`）、`TyConPtyAvailable` |
| `examples/terminal/uptyunix.pas` | `{$IFDEF UNIX}`：`TUnixPtyBackend`（`posix_openpt` 系列、fork、poll + 唤醒管道、`TIOCSWINSZ`、`waitpid`）。只引 `BaseUnix`、`Unix`、`TermIO`、`Classes`、`SysUtils`，不引 LCL——WSL 控制台测试也用它 |
| `examples/terminal/ushell.pas` | `TTerminalShell`：把会话接到 `TTyTerminalView`（`OnData` → 写、`OnGridResize` → 改尺寸、输出按 `Write` 回调记账、退出打一行、设 `Core.WindowsPty`），不引窗体；测试里可以接假后端 |

---

## 文件清单

| 文件 | 本期做什么 |
|---|---|
| `tools/terminal-oracle/selection-cases.js`、`cases/selection.js` | **新建**（Task 1） |
| `tools/terminal-oracle/url-cases.js`、`cases/links.js` | **新建**（Task 1）；spec §13.2 早就列了 `url-cases.js`，OSC 8 与去重叠一并放这里 |
| `tools/terminal-oracle/clipboard-cases.js` | **新建**（Task 1）。OSC 52 |
| `tools/terminal-oracle/mouse-cases.js` | **新建**（Task 1）。`_sendEvent` 的事件映射、`getCoords` 两种、拖动滚速 |
| `tools/terminal-oracle/lib-dump.js`、`regen-all.js` | 改（Task 1）。`PORTED` / `GENERATED` / `SCRIPTS` 追加 |
| `tests/fixtures/terminal-selection.json`、`terminal-links.json`、`terminal-osc52.json`、`terminal-mouse-events.json` | **生成** |
| `source/tyControls.Terminal.Selection.pas`、`source/tyControls.Terminal.Links.pas` | **新建**（Task 2、3） |
| `source/tyControls.Terminal.Buffer.pas`、`Core.pas`、`Core.Services.inc` | 改（Task 4） |
| `source/tyControls.Terminal.Render.pas` | 改（Task 7） |
| `source/tyControls.Terminal.pas` | 改（Task 5–8、10、11） |
| `source/tyControls.StrConsts.pas`、`languages/tycontrols.strconsts.en.po`、`.zh_CN.po` | 改（Task 8） |
| `tycontrols.lpk` | `<Files>` 末尾加两个新单元（Task 2、3） |
| `tests/test.terminal.selection.pas`、`test.terminal.links.pas` | **新建**（Task 4） |
| `tests/test.terminal.view.mouse.pas` | **新建**（Task 9） |
| `tests/test.terminal.view.paint.pas` | 改（Task 9、12：选区与链接的像素） |
| `tests/test.terminal.view.links.pas` | **新建**（Task 12） |
| `tests/test.terminal.view.pas` | 改（Task 9：published 默认值守卫自动覆盖新属性；探针加鼠标与剪贴板的桩） |
| `tests/test.terminal.pty.pas` | **新建**（Task 13、14） |
| `tests/test.terminal.example.pas` | 改（Task 16） |
| `tools/terminal-shots/*` | 改（Task 17：加选区、列选、链接下划线三组；Task 18 主控跑） |
| `tests/tytests.lpr` | uses 加新测试单元 |
| `examples/terminal/uptysession.pas`、`uptywin.pas`、`uptyunix.pas`、`ushell.pas` | **新建**（Task 13–16） |
| `examples/terminal/umain.pas`、`umain.lfm`、`terminal_example.lpi`、`languages/terminal_example.zh_CN.po` | 改（Task 16；`terminal_example.zh_CN.po` 由主控用 `example-rsj2po.py` 生成） |
| `examples/terminal/languages/tycontrols.zh_CN.po` | 改（Task 16：右键菜单四条库字串的译文，示例带的是库译文的子集） |
| `tools/terminal-ptytest/ptytest.lpr`、`.gitignore` | **新建**（Task 15）。WSL 里 `fpc` 直接编，不进包 |
| `docs/controls/terminal.md`、`README.md`、`README.en.md` | 改（Task 17） |
| `THIRD-PARTY-NOTICES.md`、`tests/test.release.pas` | 改（Task 17） |
| `docs/superpowers/specs/2026-09-28-terminal-view-design.md` | 只在 Task 18 写回 |

**不碰**：`Base.pas`、`Painter.pas`、`StyleModel.pas`、`TextMenu.pas`、Parser / Unicode.Width / Keyboard 三个单元（Keyboard 里全选的判定已经有了）、主题文件（token 与键 3 期已就位）、`CHANGELOG*`、`D:/Projects/xterm.js` 下任何受版本控制的文件。发现 Core / Buffer 的别的 bug 另开 `fix(terminal)` 提交并写明，不顺手改。

---

## 实现期的地雷（每个任务开工前看一眼）

1. **只经 `lib-dump.js` 加载上游**，新用到的 `.ts` 进 `PORTED`（过期构建检查）；addon 的产物在 `addons/<名字>/out/`。
2. **CRLF 与反斜杠**：含 `\x1b`、`\u`、正则的 JS 一律用 Write 工具落文件（[[bash-heredoc-eats-backslashes]]）；改 `.pas` 用编辑工具，不用 Git Bash 的 `sed -i`（[[git-bash-sed-strips-crlf]]）；期末变异先 `git diff --stat` 确认改到了（[[crlf-mutation-phantom-survivor]]）。
3. **FPC 的 `{ }` 注释会嵌套**（[[fpc-brace-comments-nest]]）：正则、JSON、`{}` 别写进花括号注释；正则的字符集合在 Pascal 里写成常量串，注释用 `//`。
4. **下标是 UTF-16**：取词（核实记录 4）、网址扫描与回映射（核实记录 19）全按 UTF-16 单元算；`TranslateToString` 出的是 UTF-8，先转 `UnicodeString`；格子的 `GetChars` 长度用 `TyTermJsLength`。用 UTF-8 字节下标会在中文、表情上错位，小测试只写 ASCII 会假绿（[[index-keyed-string-sort-trap]] 同一类）——夹具必须有中文、表情、组合字符、宽字符跨行尾。
5. **空串是分隔符**（核实记录 5）：`Pos('', s)` 答 0，照上游要单独判。
6. **JS 的 `Math.round`**：`Floor(x + 0.5)`；负数的 `.5` 向正无穷（`Math.round(-0.5) = -0`）。滚速公式、像素中心都要对表。
7. **选区点不是格子**：选区列是 0..Cols 的边界；画、取文本按 `[from, to)`；宽字符的 `+1` 补正只在按下和拖动时做（核实记录 6、7）。
8. **按下时定路**（核实记录 13）：`MouseDown` 定下「上报 / 选择 / 链接 / 无」，拖动、抬起一直走同一条，直到所有键松开；中途松开覆盖键、Ctrl 不换路。
9. **右键菜单的时序各 widgetset 不同**：Win32 在抬起后发 `WM_CONTEXTMENU`；GTK 可能在按下时就发。`DoContextPopup` 里先看「这次右键按下是不是上报了」的标志，标志不在（菜单先于按下到）就按当前的协议与修饰键现算（`GetKeyShiftState`）。真机项第 40 项。
10. **`SetTempCursor` 会被 LCL 复位**（核实记录 18）：每次 `MouseMove` 和按键改了 Ctrl / Alt 都重设。
11. **fork 之后只做系统调用**（开工前问题二第 16 条）：子进程里不许有字符串操作、`WriteLn`、异常。`FpExecve` 用 `PChar` 重载，不用 `RawByteString` 重载（后者会转换分配）。
12. **关 PTY 的顺序**（开工前问题二第 18 条）：先让读线程进「丢弃模式」（不再等背压、读到的直接丢），再关伪终端 / 发 SIGHUP、写唤醒管道，再 `WaitFor` 三个线程，最后关句柄。任何一步都不能在主线程上阻塞等一个要主线程配合的线程——读线程等背压、主线程等读线程，就是死锁。测试里每个等待都带超时。
13. **会话的回调在主线程**：`Pump` 只在主线程调；读线程只碰加锁的队列和计数；`OnExit` 在所有输出交给终端之后才发。
14. **无头像素测试三件套**（[[headless-render-needs-sentinel-ground]]）：哨兵底色 + 真父窗体 + 自建 controller；选区颜色断言用 █（整格纯色）和空格子（纯底色）两种格子；链接下划线数 `UnderlineY` 那几行的像素。先打包围盒再写断言。
15. **`SetFocus` 在无头里可能抛**：焦点相关（选区两色）的测试用探针的 `Enter` / `Leave`（3 期的做法），另有一条走真窗体（`test.focus.tabstop.pas` 的惰性初始化）。
16. **单跑绿 / 全量红** 先 `lazbuild -B` 重编（[[canary-then-rebuild]]），再查进程级状态（[[suite-order-widgetset-init]]）。线程测试若偶发，先查等待有没有超时、有没有在析构里等一个还在排队的异步调用。
17. **published default = 构造值**（[[tabstop-declared-default-must-match]]）；字符串属性用 `stored` 函数；3 期的 RTTI 守卫会自动覆盖新属性。
18. **视觉值走主题 token**（[[theme-customizability-principle]]）：选区色、失焦选区色、链接色都从 token 来；禁用时和 3 期的色表一样按 `:disabled` 的 opacity 预混。
19. **新单元进 `.lpk`、新测试单元进 `tytests.lpr`**（[[new-unit-missing-from-lpk]]）；示例的新单元进 `terminal_example.lpi`。
20. **示例规矩**（[[examples-must-be-lfm-titlebar-skin]]、[[demo-edits-lfm-not-code]]、[[no-native-controls-in-ui]]、[[skin-variance-breaks-fixed-widths]]）：新控件写进 `.lfm`、`AutoSize`、全用库控件；英文标题改了同步 `.po` 的 msgid（[[example-english-caption-fit]]）。
21. **空 `.po` 条目会让程序起不来**（[[empty-po-entry-blocks-startup]]）：`.po` 新条目 msgstr 必须有值。
22. **测试钉死错值**（[[tests-that-pin-the-bug]]、[[tests-written-with-the-fix-are-green-and-wrong]]）：期望值只来自夹具或本计划的表，不来自「先跑一遍看看」。

---

## 跑测试的固定套路（每段末只跑本段；Task 18 跑全量）

改了 `source/` 之后**必须** `lazbuild -B`。exe 用唯一名 `tytests-term.exe`。

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi > /tmp/term-build.txt 2>&1 || { tail -30 /tmp/term-build.txt; false; } && cd tests && cp tytests.exe tytests-term.exe && for s in $SUITES; do ./tytests-term.exe --suite=$s --format=plain > /tmp/term-$s.txt 2>&1; printf '%s: ' $s; grep -E "Number of (run tests|errors|failures)" /tmp/term-$s.txt | tr '\n' ' '; echo; done
```

| 段 | 编译时机 | `SUITES` |
|---|---|---|
| 4a | Task 4 之后 | `TTyTerminalSelectionOracleTests TTyTerminalSelectionTests TTyTerminalLinksOracleTests TTyTerminalLinksTests TTyTerminalCoreTests TTyTerminalBufferTests TReleaseManifestTest` |
| 4b | Task 9 之后 | 上一行 + `TTyTerminalViewTests TTyTerminalViewPaintTests TTyTerminalViewInputTests TTyTerminalViewMouseTests TI18NTest` |
| 4c | Task 12 之后 | 上一行 + `TTyTerminalViewLinkTests` |
| 4d | Task 17 之后 | 上一行 + `TTyTerminalPtyTests TTyTerminalExampleTests TTyTerminalViewThemeTests` |

**判据是每个 suite 那一行都有 `Number of run tests`、errors / failures 为 0**，不是 exit code。某一行为空 = 跑丢了，重跑，别读成通过。每段只修本段的红，**不跑全量、不做变异、不汇报**。线程测试（`TTyTerminalPtyTests`）单跑一次后**再跑两次**，三次都绿才算。

全量（Task 18，输出必须重定向到文件，[[known-rare-suite-flake]]）：

```bash
cd /d/Projects/ty-3.1/tests && ./tytests-term.exe --all --format=plain > /tmp/term-all.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/term-all.txt
```

node 侧：`cd /d/Projects/ty-3.1 && node tools/terminal-oracle/regen-all.js --expect-clean`（先把工作区提交干净）。

WSL 侧（Task 15、Task 18）：

```bash
wsl -d Ubuntu -- bash -lc "cd /mnt/d/Projects/ty-3.1/tools/terminal-ptytest && rm -rf lib && mkdir -p lib && fpc -Mobjfpc -Sh -FUlib -Fu../../examples/terminal -optytest ptytest.lpr > lib/build.txt 2>&1 || tail -20 lib/build.txt; ./ptytest"
```

判据：最后一行 `ptytest: N passed, 0 failed`，N 等于用例数。

---

## 关于判据和变异

- 纯函数给**输入 / 期望表**（或由夹具给）；夹具比较和像素、事件、线程测试写**判据**（比什么、怎么数、失败打印什么），测试代码执行时现写。
- 每条判据写明「**在哪个变异下必须红**」；各任务的变异表期末集中做（Task 18 Step 6）：改一行 → `git diff --stat` 确认改到了 → `lazbuild -B` → 跑相关 suite → **必须红** → 改回 → 重编重跑 → 绿。没红的先查改没改对地方、再查是不是「这条路走不到」；确实没红，当场补测试，签收记录写一句。
- 接线类变异（事件没转发、`Invalidate` 没调、计时器没建、唤醒没调、`OnUserInput` 没接）每类至少一条（[[built-not-wired-is-the-default-failure]]）。
- 所有夹具测试结尾断言比较次数 `> 0` 且等于从夹具算出的应比次数（[[assertion-never-varies-the-thing]]）；步骤型夹具每一步都比，不只比最后一步。
- 标「等价」的变异不做，理由写在表里。会死循环、会挂住的变异不做；卡住时按进程号结束 `tytests-term.exe`，**禁用 `taskkill -im`**（[[parallel-agent-worktree-hazards]]）。

---

### Task 0: 基线

**Files:** 无（只记数）

- [ ] **Step 1: 确认起点**

```bash
cd /d/Projects/ty-3.1 && git status --short && git branch --show-current && git log --oneline -1 && git log --oneline feat/terminal..main | wc -l
```

Expected：工作区干净，分支 `feat/terminal`，HEAD 是本计划的提交或其后；`main` 没有新提交（有的话停下交主控：要不要先合）。

- [ ] **Step 2: 基线编译并跑全量**（实现 agent 做）：「跑测试的固定套路」的全量命令。条数记进草稿（3 期签收是 8168，唯一的红是本机 ClearType 环境下的 `TPainterTest.TestTextIsInkedAsWindowsInksIt`，与本期无关），Task 18 签收时写进本计划末尾。**有别的红就停。**

- [ ] **Step 3: 上游产物在不在**

```bash
cd /d/Projects/xterm.js && git status --short | head -3 && ls out/browser/services/SelectionService.js out/browser/OscLinkProvider.js out/browser/Linkifier.js out/browser/input/Mouse.js out/browser/services/MouseService.js addons/addon-web-links/out/WebLinkProvider.js addons/addon-web-links/out/WebLinksAddon.js addons/addon-clipboard/out/ClipboardAddon.js
```

Expected：checkout 干净，八个文件都在（不在就停下交主控重新 `npm run build`）。

- [ ] **Step 4: WSL 可用**

```bash
wsl -d Ubuntu -- bash -lc "fpc -iV && test -e /dev/ptmx && echo ptmx-ok"
```

Expected：`3.2.2` 与 `ptmx-ok`。不可用就把 Task 15 的 WSL 验证记成「待真机」，其余照做。

---

### Task 18: 收尾——编译、全量、按 spec 逐条核、集中变异、主控编包编示例、审查、写回 spec、签收

**Files:**
- Modify: 本计划（签收记录）、`docs/superpowers/specs/2026-09-28-terminal-view-design.md`（写回）
- 修复时按需改 Task 1–17 的文件

- [x] **Step 1: 一次编译 + 本期全部 suite + 全量**：「跑测试的固定套路」4d 行与全量命令。Expected：本期 suite 全 0 / 0；全量 errors / failures 只剩基线那一条、总数 = 基线 + 本期新增。红了集中修：分清是移植错、夹具错还是控件错——选区、链接、OSC 52 **以上游为准**；修复提交 `fix(terminal): ...`，一个问题一个提交。

- [x] **Step 2: 重跑生成，确认可复现**：`node tools/terminal-oracle/regen-all.js --expect-clean` → `clean`；WSL 的 `ptytest` 再跑一次全过。

- [x] **Step 3: 规模记录**：新夹具的字节数与用例数；本期各 suite 用时；`TTyTerminalPtyTests` 三次连跑的用时。

- [x] **Step 4: 按 spec 逐条核代码，不看测试**（[[green-tests-are-not-spec-conformance]]、[[built-not-wired-is-the-default-failure]]）。逐条记「在哪一行实现 / 为什么不需要 / 挪到几期」：
  - §2.1：两个新单元的依赖（不引 LCL）、进运行时包；示例四个单元只在示例里。
  - §3.4 / §3.5：链接、OSC 52 以事件交宿主；读线程 → 加锁队列 → 一次唤醒 → 主线程 `Write`。
  - §7.5 / §7.6：按键、拖动、移动、横竖滚轮全部经 `TriggerMouseEvent`；0 起格子、设备像素、钳在网格。
  - §9.1：五个 4 期属性 + `AllowNonHttpLinks`，默认值、`stored`；§9.2：三个事件；§9.3：选区方法、`CopyToClipboard`、`SelectionText` / `HasSelection`。
  - §9.4：`tkrSelectAll` 接上；复制快捷键有选区才写。
  - §9.5.1–§9.5.5：「谁拿鼠标」表的九格逐格对；覆盖键四个值、macOS 默认 Option；捕获三键；横向滚轮；单击 / 双击 / 三击 / Shift / Alt 列选；自动滚（50 ms、15 行、50 像素按 PPI）；trim 跟随；清选区六个时机。
  - §9.6.1–§9.6.4：复制规则（去尾空白、折行不换行、`LineEnding`、NBSP）；PRIMARY；OSC 52 三种策略与默认值；右键菜单四项与灰掉规则、`PopupMenu` 优先、菜单键。
  - §9.8：两种来源、网址正则与 `isUrl`、Ctrl / Cmd+悬停、手形、Ctrl+单击、程序接管时仍优先、控件不打开任何东西。
  - §11：`TyTerminalSelection` 两态、选区前景「写了才用」、`TyTerminalLink`、禁用预混。
  - §12.1–§12.4：示例真 shell、命令行、重启、退出一行、`WindowsPty`、改尺寸、流控、记录 PTY 输出。
  - §13.4：鼠标、网址两行的夹具；§14：单元头、notices；§15、§16：本期新增的偏离与真机项都进了验收表。
  - 3 期交接七条逐条对上。

- [ ] **Step 5: 【主控执行】编包、编示例、i18n、截图**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tycontrols.lpk > /tmp/term-pkg.txt 2>&1; tail -3 /tmp/term-pkg.txt; lazbuild -B tycontrols_dt.lpk > /tmp/term-dt.txt 2>&1; tail -3 /tmp/term-dt.txt; lazbuild -B examples/terminal/terminal_example.lpi > /tmp/term-ex.txt 2>&1; tail -3 /tmp/term-ex.txt; git status --short
```

Expected：三个都编过；`git status` 只多出 `languages/tyControls.StrConsts.pot` 的新条目（照 i18n 惯例提交）。然后：
1. `python scripts/example-rsj2po.py examples/terminal terminal_example <Task 16 写好的译文 json>`，重编示例，`python scripts/check-example-po.py` 过。
2. `powershell -File scripts/smoke-launch-examples.ps1`（终端示例起得来、有窗口）。
3. 示例切到 Shell 模式、默认命令，起得来、能打 `dir` 看到输出（只看不录，真机验收时用户再看一遍）；Linux 版若 WSL 里的 `lazbuild` 能编 LCL 程序就编一次，不能就记「待真机」。
4. **截图**（给期末一次性验收，跑 Task 17 给 `tools/terminal-shots` 加好的三组，照 3 期的离屏做法）：选区（聚焦 / 失焦）、列选区、Ctrl+悬停的链接下划线，各在默认浅色 / 默认深色 / xp / macos 四种皮肤下；存 `docs/superpowers/plans/2026-09-29-terminal-phase-4-shots/`，PNG 进 git、单张 ≤ 300 KB，`index.md` 列出每张看什么。

- [x] **Step 6: 集中变异**（每条三拍，必须红）：各任务变异表 S*（Task 2）、L*（Task 3）、C*（Task 4）、M*（Task 5）、E*（Task 6）、P*（Task 7）、U*（Task 8）、H*（Task 10）、O*（Task 11）、Y*（Task 13–15）、X*（Task 16）。JS 侧的变异改完跑对应生成脚本、确认失败后改回，`regen-all.js --expect-clean` 仍然 `clean`。WSL 侧的变异在 WSL 里编跑 `ptytest`。结果逐条记进签收记录；没红的当场补强。

- [x] **Step 7: 整体代码质量审查**（`git diff <Task 0 的 HEAD>..HEAD`）：
  - 选区：与 `SelectionService.ts` / `SelectionModel.ts` 逐方法对照（`_getWordAt` 的四个计数、折行递归的两个方向、`finalSelectionEnd` 的三种补正、事件发送的条件）；注释里的行号对得上。
  - 链接：扫描器与正则逐字符集合对照；`_mapStrIdx` 的「行尾空格子 + 下一行宽字符」补正；OSC 8 段的「结束条件 + 行尾」；URL 前缀解析与 WHATWG 对照（userinfo 编码集、禁止主机字符、IPv4 / IPv6 规范形、默认端口）。
  - 控件：按下定路（地雷 8）；每个 Core 事件都接了（`OnUserInput` 新增）；析构顺序（自动滚计时器、菜单、会话）；`Paint` 里没有改选区、没有发宿主事件；视觉值没有写死。
  - PTY：fork 之后只有系统调用；三个线程的退出路径都不依赖主线程；句柄 / fd 都关了；背压的计数在锁里。
  - 夹具读空时每个测试都会红（计数断言）；等价变异的理由站得住。
  审出来的问题修完回到 Step 1。

- [x] **Step 8: 写回 spec 原处，标「实现期修正（4 期）」**。至少：§1.1（新增：选区用坐标不用标记；上游复制本来就是平台换行；OSC 8 非 http 在提供者里就丢；上游悬停与单击不要修饰键；`isUrl` 过滤；`Win32InputMode` 与 ConPTY 鼠标的结论）；§2.1（两个新单元）；§7.6（`OnUserInput`）；§6.3（`TrimmedLines`）；§9（类声明不加 `ITyTextEditActions`；§9.1 `AllowNonHttpLinks`；§9.5.2 不剥修饰位、按下定路；§9.5.3 `DoMouseWheelHorz`；§9.5.5 多击用 `TyMultiClickCount`、选区点、trim 计数、`OnScrollbackCleared`、阈值按 PPI；§9.6.1 删掉「偏离」一句；§9.6.2 写入时机；§9.6.4 四项菜单；§9.8 手写扫描器、`isUrl`、双击选链接）；§12.1 / §12.2 / §12.3（示例实际的样子、写线程与退出线程、`posix_openpt`、流控提前）；§12.4 与 §16（真机观察的结论位置）；§13.2（本期脚本与测试单元）；§14（notices 标题）；§15（新增偏离：Ctrl 才悬停 / 激活、`AllowNonHttpLinks`、`OnScrollbackCleared` 清选区、非 ASCII 主机与 `xn--`、1016 之外的像素规则不变）；§18（流控挪到 4 期、4 / 5 期边界）；开工前问题一的六条结论。

- [x] **Step 9: 签收记录写进本计划末尾，提交**：全量条数（基线 → 签收）、提交区间、各 suite 用时、夹具体积与用例数、WSL `ptytest` 结果、变异结果（每条红 / 补强 / 等价）、spec 写回的节号、遗留、给 5 期的交接；更新「真机验收项汇总」。

```bash
cd /d/Projects/ty-3.1 && git add docs/ && git commit -m "docs(terminal): phase 4 sign-off; corrections written back into the spec

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 4 期做完能看到什么

- `tytests` 里本期的 suite 全绿：取词、取行、拖动、trim、选区文本、网址识别、OSC 8、去重叠、OSC 52、像素几何、鼠标事件映射与上游逐项相同；控件的鼠标路由（九种情况）、选区事件、清选区时机、菜单、剪贴板、PRIMARY、链接悬停与激活、OSC 52 策略；选区与链接下划线的像素；PTY 会话的读写、背压、唤醒、退出、关闭不挂；Windows 上真 ConPTY 起 `cmd /c echo` 拿到输出和退出码。
- WSL 里 `ptytest` 全过：`posix_openpt` 起 `/bin/sh`、`stty size` 跟着改尺寸变、退出码、2 MB 输出不丢且背压生效、关闭时子进程收走。
- 示例切到 Shell 能用 cmd / pwsh；拖窗口改大小，`mode con` 报的列数跟着变；Ctrl+悬停网址出下划线，Ctrl+单击弹确认后用浏览器打开；右键菜单四项；选中文字复制到记事本是 CRLF。
- `docs/controls/terminal.md`、两份 README、notices 更新。

---

## 真机验收项汇总（全部各期做完后一次性验收；1–31 在 3 期计划末尾，本期接着编）

每项写「怎么验 / 看什么算过」。截图在 `docs/superpowers/plans/2026-09-29-terminal-phase-4-shots/`。

| # | 项 | 平台 | 怎么验 | 算过 |
|---|---|---|---|---|
| 32 | ConPTY 基本 | Win32（本机 19044；有条件再在 Windows 11 上） | 示例 Shell 模式起 cmd、pwsh；`dir`、彩色输出、Tab 补全、方向键历史、Ctrl+C 中断 `ping -t`；拖窗口改大小后 `mode con` | 都正常；`mode con` 的列数、行数等于状态栏的网格尺寸 |
| 33 | ConPTY 启动时发了什么 | Win32 | 打开「记录 PTY 输出」再起 cmd，看侧栏前 4 KB | 记下有没有 `?9001h`、`?1004h`、`?25l` 等，写回 spec §12.4 / §16；控件对 `?9001h` 不认（DECRQM 报不认识），键盘照常 |
| 34 | ConPTY 鼠标 | Win32 | cmd 里跑 `wsl.exe` 进 vim `:set mouse=a`、htop；有 Far Manager 的话跑一次 | 能点能拖能滚就记「通」；不通就记构建号与现象（控件侧协议本期已按标准做，见「Win32InputMode 与 ConPTY 鼠标：结论」） |
| 35 | 老 ConPTY 的折行启发 | Win32 19044 | 输出一行 300 字符的长行，窗口改窄再改宽；三击这行、复制 | 显示与 ConPTY 重绘一致；三击选中整段折行、复制成一行 |
| 36 | forkpty 路径 Linux | GTK2、Qt6 | 示例起 `$SHELL -l`；vim、htop 里拖窗口；`exit 3` | 起得来；vim / htop 跟着改尺寸重画；终端里打出「进程已退出（3）」，能重启 |
| 37 | forkpty 路径 macOS | Cocoa | 同上，zsh | 同上 |
| 38 | 鼠标上报 | 各平台 | vim `:set mouse=a` 点、拖选、滚；htop 点列头；tmux `set -g mouse on` 拖分隔线、点窗格；mc | 都按程序的意思动；拖出窗口外仍在报（捕获） |
| 39 | 覆盖键本地选择 | 各平台 | vim 鼠标模式下按住 Shift（macOS Option）拖选，再 Ctrl+Shift+C / Cmd+C | 选中的是本地选区、vim 没收到拖动；剪贴板里是那段文字 |
| 40 | 右键 | Win32、GTK2、Qt6、Cocoa | 程序没接管：右键出四项菜单（没选区时复制灰）；vim 鼠标模式：右键发给 vim、不弹菜单；Shift（macOS Option）+右键弹菜单；菜单键 / Shift+F10 | 都如此；GTK 上菜单不会在右键上报之后又弹出来（地雷 9） |
| 41 | 选词、选行、列选 | 各平台 | 双击单词、路径、网址；三击折行的长行；Alt+拖动 | 词按 `WordSeparators` 断、网址整条；三击整段折行；列选是矩形。Linux 上 Alt+拖动若被窗口管理器拿走，记下来 |
| 42 | 拖选自动滚 | 各平台 | 滚回里拖选到窗口上边外、下边外，远近不同 | 越远越快；松手停 |
| 43 | 选区随输出 | 各平台 | 选中滚回里的一段，同时 `ping`（Win：`ping -t`）持续输出 | 选区跟着文字往上走；文字被挤出滚回后选区消失；打字时选区清掉 |
| 44 | 复制规则 | Win32、Linux | 选中含折行长行和行尾空白的几行，复制到记事本 / gedit | Windows 上是 CRLF、Linux 上是 LF；折行接成一行；行尾空白去掉 |
| 45 | CopyOnSelect | 各平台 | 示例里勾上，拖选 | 松手即进剪贴板 |
| 46 | Linux PRIMARY | GTK2、Qt6（X11；再在 Wayland 会话里看一次） | 在终端里选中，到别的程序中键；在别的程序里选中，到终端中键 | X11 下两个方向都通；Wayland 下记现象 |
| 47 | 链接 | 各平台 | `echo https://example.com`；`printf '\e]8;;https://example.com\e\\link\e]8;;\e\\\n'`；`ls --hyperlink=auto`（file://）；vim 鼠标模式里 Ctrl+单击网址 | Ctrl+悬停出下划线、手形；Ctrl+单击弹示例的确认、再用浏览器开；不按 Ctrl 悬停没有下划线；`file://` 默认不是链接（开工前问题一第 2 条）；vim 里 Ctrl+单击也开 |
| 48 | OSC 52 | 各平台 | 示例三种策略下 `printf '\e]52;c;aGVsbG8=\a'`，再 `printf '\e]52;c;?\a'`；tmux `set -g set-clipboard on` 里复制 | Off：剪贴板不变、读无应答；写：剪贴板变 `hello`；读写：读时示例弹确认，同意后键码面板里有应答 |
| 49 | 横向滚轮 | 各平台（触控板、带横滚的鼠标） | vim 鼠标模式里横滚；bash 里横滚 | vim 收到 66 / 67（键码面板可见）；bash 里什么都不发、窗口不乱滚 |
| 50 | 括号粘贴真机 | 各平台 | bash 5 / zsh 里粘贴多行；vim 插入模式粘贴缩进代码 | 多行不当场执行；vim 不层层缩进 |
| 51 | 输入法进真 shell | Win32、Qt6、GTK2、Cocoa | cmd / bash 里 `echo 中文` | 候选窗在光标格；回车后 shell 回显中文 |
| 52 | 高 DPI 下的鼠标 | Win32 150% | 选区起点（半格规则）、拖动阈值、上报格子 | 点在格子右半从下一格开始选；上报的格子和指针对得上 |
| 53 | macOS 全选与右键选词 | Cocoa | Cmd+A、Cmd+C；在选区外右键 | 全选并可复制；右键先选中词再弹菜单 |
| 54 | 流量控制 | 各平台 | `cat` 一个 50 MB 文本（Win：`type`） | 界面不冻、内存不涨过百 MB；没有「写入溢出」；中途 Ctrl+C 能停 |
| 55 | 关闭与重启不挂 | 各平台 | `ping -t` / `sleep 1000` 运行中点「重启」、再直接关窗 | 立即重启 / 关闭；任务管理器 / `ps` 里没有残留的 shell 或 conhost |
| 56 | 关闭 / 重启的冻结时长（第 55 项的可量标准） | Win32、GTK2、Qt6、Cocoa | 第 55 项的三种程序（`ping -t`、一个在 `CTRL_CLOSE_EVENT` 里不走的程序、`trap '' HUP; sleep 1000`）各点一次「重启」、各关一次窗；看界面停多久 | 点下去到界面能动 ≤ 200 ms（关闭在收尾线程上，自动测试量的是 `Close` < 200 ms）；关窗时窗口可以晚到约 9 秒才消失（程序退出时有上限的总等待），但窗口不「未响应」 |
| 57 | Win11 24H2 无残留 | Windows 11 24H2 | 同第 55 项；再跑 `cmd /k` 后关窗 | 24H2 上 `ClosePseudoConsole` 不再等，程序可能还在：3 秒内按句柄结束，任务管理器按 PID 查不到；这是本机杀不掉的 Y16 变异交给真机的那一半 |
| 58 | 退出与关闭同时发生 | 各平台 | `cmd /c exit 3`（`sh -c 'exit 3'`）反复点「重启」，快过它退出 | 不崩、不挂、没有残留；偶尔看到上一个程序的退出行是正常的，不会出现在新程序的输出中间 |
| 59 | macOS 的 `poll()` 与 PTY | Cocoa | 示例起 zsh，`ls`、`cat` 大文件、改尺寸 | 输出照常；若 `poll()` 对主端答 `POLLNVAL`，后端自动换 `select`（WSL 里强制走过这条路径） |
| 60 | 失去捕获 | Win32、GTK2、Qt6、Cocoa | 在终端里按住左键拖选，拖动中 Alt+Tab 切走再松键再切回；vim 鼠标模式里拖动中弹出一个模态框（宿主可用 `OnBell` 弹） | 切回后选区已经结束、不再跟着指针；vim 收到了抬起（不再以为键还按着）；`GetKeyState` 对鼠标键的答案在各 widgetset 上对 |
| 61 | Shift+F10 | Win32、GTK2、Qt6、Cocoa | bash / vim 里按 Shift+F10 | 程序收到 F10 带 Shift 的编码；之后弹不弹控件菜单记下来（看 widgetset），写回 §9.6.4 |
| 62 | 子进程的信号与描述符 | GTK2、Qt6、Cocoa | 示例起 `bash --norc`，`grep -E 'Sig(Blk|Ign)' /proc/self/status`（macOS 用 `trap -p`、`ulimit`）；`yes | head -1`；`ls /proc/$$/fd` | 屏蔽字和忽略集都是 0（LCL 程序忽略了 SIGPIPE 也不传下去）；`yes` 静悄悄结束；没有宿主的描述符 |
| 63 | 失焦选区看得见 | 各平台，17 个皮肤明暗 | 选中一段后点别处；深色主题、反显文字上（`ls --color` 的目录、vim 的状态行）也选一次 | 失焦的选区在每个皮肤下都看得出（截图 `selection-*.png`）；反显、亮底色格上的选区和空白处同色 |
| 64 | X10 横向滚轮 | 各平台（触控板） | 程序开 `?9h`（`printf '\e[?9h'`）后横滚；再开 `?1000h` 横滚 | X10 下不上报、横滚交给外层（窗口里有可横滚的父控件时它动）；1000 下报 66 / 67 |
| 65 | ConPTY 录制在新版本上的差异 | Windows 11 | 用 `tools/terminal-conpty-record` 按 `recordings/*.cmdline` 重录 cmd / PowerShell，和 19044 的录制比 | 记下 ConPTY 画屏的差别（标题、清屏、行尾补空格）；控件回放两份都和上游一致 |

---

## 与规格不符之处（核实中发现，Task 18 写回）

1. §9.6.1、§15「上游复制用 `\n`，我们用平台换行是偏离」：上游 `SelectionService.ts:259` 就是 `isWindows ? '\r\n' : '\n'`，不是偏离。
2. §9.5.5「选区锚在标记上」：上游用坐标 + `onTrim`，并且故意不跟 splice 的插删（核实记录 1）。
3. §9.5.5「多击用 `ssTriple` / `csTripleClicks`」：库的约定是 `TyMultiClickCount`（核实记录 32）。
4. §9.5.3「覆盖 `DoMouseWheelLeft` / `Right`」：这两个拿不到 `WheelDelta`，要覆盖 `DoMouseWheelHorz`（核实记录 17）。
5. §9.5.2「覆盖键是 Alt 时要剥掉」：按着覆盖键时按键不上报，滚轮上游不剥，这句无处可用（核实记录 15）。
6. §9.5.2「上报期间用 LCL 鼠标捕获」：LCL 默认只捕获左键，要显式设三键（核实记录 16）。
7. §9.8「正则用 FPC `RegExpr` 改写」：JS `\s` 含 Unicode 空白、下标是 UTF-16，`RegExpr` 对不上；另外 spec 漏了上游的 `isUrl`（`new URL` + 前缀比较）这一层（核实记录 19）。
8. §9.8「上游 OSC 8 默认拒绝非 http(s)（`:64`）」：不是激活时拒绝，是提供者直接不返回这种链接（不下划线、不能点）（核实记录 20）。
9. §9.8 / §15：上游悬停不要修饰键就下划线、单击就激活；我们要 Ctrl / Cmd，是偏离，§15 没列（核实记录 21）。
10. §9.6.4「复用 `TTyTextEditMenu`、另加清屏」：那个菜单没有加项的口子；本期任务说四项（开工前问题一第 1 条）。
11. §9.6.3「base64 写」：上游解码走 `atob` 宽容规则 + `TextDecoder`（去 BOM、坏序列换 U+FFFD），spec 没写（核实记录 23）。
12. §12.2「写 PTY 在主线程」「forkpty 自己声明」：本期改成写线程（大段粘贴不卡界面）、`posix_openpt` 系列（不链 libutil）；§12.3 流控从 5 期提前到本期（本期任务要求）。
13. §9.5.5 的清选区时机里没有 `OnScrollbackCleared`，3 期交接有；上游 `clear()` 不清选区，是我们加的（核实记录 10）。
14. 本期任务里的 `OnLinkClick` 与 spec §9.2 的 `OnLinkActivate` 不一致：按 spec。

---

## 4 期签收（2026-09-29）

**全量**：`lazbuild -B` 后 `--all` 8285 条（期末审查前 8260，本批新增 25），errors 0、failures 1——唯一的红仍是本机 ClearType 环境下的 `TPainterTest.TestTextIsInkedAsWindowsInksIt`（main 带来的环境测试，与本期无关）。本期各 suite 用时：Pty 21.1 s（另两次连跑 18.1 / 18.0 s，三次都绿）、ViewMouse 13.8 s、ViewPaint 14.8 s、ViewLink 5.2 s、ViewTheme 7.3 s、Selection 预言 0.3 s、Links 预言 0.8 s、CoreOracle 5.5 s（含两份 ConPTY 录制）。`node tools/terminal-oracle/regen-all.js --expect-clean` → `clean`。WSL `ptytest`：12 passed, 0 failed（T6 关闭 0 ms、子进程 11 ms 后没了；T10 不理 SIGHUP 的子进程 3.2 s 后被 SIGKILL；T11 select 路径；T12 子进程状态）。

**提交区间**：`a5cabea2..`（期末审查前的截图提交之后）——`4d02b78c` 拆 include（纯搬移）、`26940c83` PTY 收尾线程、`f63554bf` 控件的审查修复、`9fe68995` 失焦选区 alpha、`e53c42ff` ConPTY 录制、`a5d18775` 示例 `.po` 的 msgctxt、`88eb8222` 控件文档与截图、`2ecadca2` spec 写回，以及本签收提交。

**期末两轮审查（规格核对 + 代码质量）的处理**：
1. ConPTY 关闭堵主线程：`ClosePseudoConsole` 只由退出等待线程调（等程序退出或关闭事件）；`Close` 只做不阻塞的几件事后立即返回，收尾线程等关（3 s）、超时按句柄 `TerminateProcess`（再 2 s）、中断两个线程（3 s）、关句柄释放；读线程关闭期间一直排空。程序退出时 `PtyWaitForFinishers` 有上限地等一次。Unix 同理（主线程只发 SIGHUP）。`TestConPtyResizesAndCloses` 改断言 `Close` < 200 ms；新加两个「不肯走的程序」（测试程序自己带 `--ty-pty-helper`：卡在 `CTRL_CLOSE_EVENT` 处理里 / `FreeConsole` 后睡），断言立即返回、按句柄结束（退出码 1）、按 PID 查无残留、会话全部释放；`TestCloseDoesNotHang` 后半段用 `PumpsRun`（类变量）与 `PtySessionsAlive` 计数断言；退出与关闭同时发生的竞态假后端 30 轮、真 ConPTY 5 轮。
2. 超时后释放后使用：会话对象改成句柄，核心归收尾线程；停不下来的连同所用资源留着（`PtySessionsLeaked`）。`Stop` 先 `Unhook`（try/finally），关会话后再 `RemoveAsyncCalls`；卡在 `WriteFile` 的写线程由 `CancelSynchronousIo` 取消。测试：卡死的读线程、卡住的写。
3. 鼠标抬起丢失：覆盖 `CaptureChanged`（LCL 抬起消息里那一次除外，`FInButtonUp`）、`DoExit`，键确实松开（`HeldMouseButtons`，默认 `GetKeyState`）就走 `MouseUp` 的收尾；同一个键再按下时也先收尾（抬起报在上次位置）。
4. 选区色：`--terminal-selection-bg-inactive` → `alpha(var(--on-surface), 0.3)`，重跑 `gen-defaulttheme`（catalog、内置主题无变化），golden（light / dark / showcase 三份，只有这一个 alpha）更新；选中格底色**替换**为主题底色上预混的不透明色；宽字符按首列整字；守卫 17 主题 × 明暗：失焦 ≥ 1.70（实测最差 1.80，macos 浅色；0.18 时 1.41）、聚焦 ≥ 1.25（实测最差 1.27，office 深色）；截图工具列选区补 `DoEnter`。
5. 选区取文字两遍法；`FinishSelection` 两样都不要时不取文字；PRIMARY 按需（LCL `PrimarySelection.OnRequest` + `SetSupportedFormats`，核实过 `clipbrd.pp` 有这条路，SynEdit 同法），控件释放时交出所有权；一万行复制 1 秒上限的测试（本机整个测试 0.19 s）。
6. OSC 52：处理器 try/except，宿主事件与剪贴板的异常不出 `Parse`，块里后面的字节照常解析；文档与事件注释写明事件里不能释放控件。
7. 等价变异重判：见下表 Y16、J1、Y9 / Y9a。
8. Unix 子进程：清信号屏蔽字、1–31 恢复 `SIG_DFL`、关 3 到软上限（≤ 65536）的描述符，全在 fork 前备好；ptytest T12（`yes | head -1`、忽略集、描述符）。
9. `POLLNVAL` → 改用 `select`（`ForceSelect` 让 WSL 走这条路，T11）；真机第 59 项。
10. 读线程异常也唤醒宿主打退出行；写线程退出后 `Write` 不再入队。
11. `GetWordAt` 的折行递归改两个循环（折了两万行的词双击测试）。
12. `Select()` 入口钳参数。
13. 菜单「粘贴」用 `TyClipboardHasText`（测试缝 `ClipboardHasText`），不读整段剪贴板。
14. macOS 右键选词挪到 `PopupMenu` 判断之前。
15. 鼠标协议每次换成开着的另一种都清选区；同一协议重复 DECSET 不清（Core 只在真变时发事件），进 §15。
16. X10 下横向滚轮交还父控件：先用 `RestrictMouseEvent` 问协议收不收滚轮，满格的再看 `TriggerMouseEvent` 的返回值。
17. `Links.pas` 单元头的首次悬停差异改归「结果不同」，写明上游第一次悬停可能挑中与别处 OSC 8 重叠的网址；行为不改（上游答案随悬停历史变），进 §15。
18. `docs/controls/terminal.md`：Shift+F10 是有编码的键，先发给程序，弹不弹菜单看 widgetset（真机第 61 项）；另补抬起丢失、PRIMARY 按需、选区替换底色、OSC 52 事件约束、PTY 关闭不在主线程上等。
19. 退出码 `Int64`（`ExitCode`、`Pump`、`TTerminalShell.ExitCode`；不再借写回调的 tag 传）；退出后终端回只读，`TermData` 在 `FRunning` 为假时不入队。
20. 示例 `tycontrols.zh_CN.po` 的 `rsterminalmenuclear` 补 `msgctxt`（库里没有示例 po 同步脚本，手改；`check-example-po.py` 101 份 0 问题）。
21. 像素测试不再整体关预算：`SetUp` 冻结 `Core.Clock`，预算分支照常执行；冷启动计时测试把时钟换回墙上时间。改动小，全绿。
22. ConPTY 录制：做了。`tools/terminal-conpty-record` 经示例会话在 19044 录 `cmd /c` 与 `powershell -NoLogo -NoProfile -NonInteractive -Command` 各一段（命令行在 `recordings/*.cmdline`），`conpty-cast.py` 转 asciicast（首条 OSC 0 的全路径只留文件名；见到用户名、机器名、个人目录就拒绝），进 `recordings.js` 的上游对照（10 份录制），拷进示例。
23. 拆单元：鼠标、链接、OSC 52、右键菜单、选区胶水搬进 `tyControls.Terminal.View.*.inc`，纯搬移单独提交；`.lpk` 不变（`.inc` 不列）；notices 标题不加（控件是自己写的，Terminal.pas 本来就不在标题里），发版守卫 `TheThirdPartyNoticeCoversTheTerminalPort` 加查这五个文件随包发出。

**变异**（每条：改 → `git diff --stat` 确认改到 → 重编 → 跑相关 suite → 还原；脚本化执行，还原后工作区干净）：

| # | 变异 | 结果 |
|---|---|---|
| 1a | 关闭回到主线程（`Close` 里同步做收尾） | 红：`TestConPtyCloseReturnsAtOnce…`、`…LeftItsConsole`、`TestAStuckSessionIsLeftNotFreed` |
| 1b | 超时不 `TerminateProcess` | 红：`TestConPtyCloseReturnsAtOnceAndEndsAProgramThatStays`（`FreeConsole` 那例被 `Shutdown` 的兜底 `TerminateProcess` 救了——两道防线） |
| 1u | Unix：`BeginClose` 里同步等子进程（WSL） | 红：ptytest T10（`Close` 3162 ms） |
| 2a | 收尾超时照样释放 | 红：7 例（泄漏计数、存活计数） |
| 2b | 不取消卡住的写 | 红：`TestABlockedWriteIsCancelled` |
| 2c | 只去掉 `Stop` 里的 `RemoveAsyncCalls` | 存活：`Destroy` 里还有一次（冗余）；两处都去掉 → 红：`TestCloseDoesNotHang`、`TestCloseWhileTheProgramExits` |
| 3a | `CaptureChanged` 不收尾 | 红：`TestALostReleaseIsFinished` |
| 3b | 抬起消息里的捕获变化也当丢了 | 红：`TestACtrlClickSurvivesTheCaptureGoingFirst` |
| 3c | 不问键还按着没有 | 红：`TestALostReleaseIsFinished` |
| 4a | 失焦 alpha 回 0.18 | 红：`TestTheSelectionStandsOutOnEveryTheme`（最差 1.41 < 1.70） |
| 4b | 选区只换默认底色的格子（彩色 / 反显格保持原底色） | 红：`TestTheSelectionReplacesTheCellsBackground` |
| 4c | 列选区半格（宽字符不按首列） | 红：`TestAWideCharacterIsSelectedByItsFirstColumn` |
| 5a | 每次松开都拼文字 | 红：`TestPrimaryIsOfferedNotBuilt` |
| 5b | 选区文字改回逐段 `s := s + t` | 存活：FPC 的 `s := s + t` 在引用计数为 1 时原地扩展，本机不是平方级（整个测试 0.19 s）；两遍法不依赖内存管理器的这个行为，1 秒上限守的是真正的平方级（比如每段复制整串） |
| 6 | OSC 52 异常不吞 | 红：`TestOsc52ExceptionsStayInside` |
| 7 J1 | `TSelRun` 不读 `cellHeight`、写死 10，`lib-dump.js` 的 `CELL_H` 改 11 重生成夹具 | 红：`TestEveryStepMatches`、`TestAfterResetToo`；对照（写死 10、夹具仍是 10）绿——夹具确实依赖假尺寸。夹具与脚本已还原，`regen-all --expect-clean` 仍 `clean` |
| 7 Y16 | `Shutdown` 不等进程、不 `TerminateProcess`（原 4d 表） | 重判：**本机不可杀、交真机**——19044 上 cmd 随控制台关闭就走，没有残留可看；24H2 上 `ClosePseudoConsole` 不再等，才会留下程序（真机第 57 项）。本批的收尾路径另由 1b 覆盖 |
| 7 Y9 / Y9a | 只去掉等背压时的 `FDiscard` 检查 / 只去掉 `BeginClose` 的 `FHeld := False` | 各自存活；两者**同时**去掉 → 红：`TestCloseWhileHeldBack`。三道冗余：等背压的循环看 `FDiscard`；`BeginClose` 置 `FHeld := False` 并 `SetEvent(FResume)`；进等待前的判断 `not FDiscard and (FOutstanding > FHigh)` 不让关闭后的读再被拦住 |
| 8a | 子进程不恢复 `SIG_DFL`（WSL） | 红：T12（`yes` 见到 EPIPE） |
| 8b | 子进程不关继承的描述符（WSL） | 红：T12 |
| 8c | 子进程不清信号屏蔽字（WSL） | 存活：本环境等价——Ubuntu 的 `/bin/sh` 是 dash，启动时自己清屏蔽字；换成不清的 shell 才看得见（真机第 62 项用 bash 看） |
| 9 | select 路径看不到数据（WSL） | 红：T11 |
| 10a | 读线程异常不唤醒 | 红：`TestAReaderThatRaisesEndsTheSession` |
| 10b | 写线程没了仍入队 | 红：`TestNoWritesQueueOnceTheWriterIsGone` |
| 11 | 折行取词只接一行 | 红：`TestAWordWrappedOverManyRows` |
| 12 | `Select` 不钳长度 | 红：`TestSelectIsClamped` |
| 13 | 菜单读整段剪贴板 | 红：`TestTheMenuDoesNotReadTheClipboard` |
| 15 | 只在从无到有时清选区 | 红：`TestEveryProtocolChangeClearsTheSelection` |
| 16 | X10 下横向滚轮照吃 | 红：`TestX10HandsTheSidewaysWheelBack` |
| 19a | 退出码截成 Integer | 红：`TestTheExitCodeIsNotAnInteger` |
| 19b / 19c | 退出后不回只读 / 退出后按键仍入队 | 红：`TestAfterTheExitKeysGoNowhere` |

**主控已办（2026-09-29）**：在 `ca0d63ac` 上 `lazbuild -B` 编过 `tycontrols.lpk`、`tycontrols_dt.lpk` 和终端示例，均 0 错；`example-rsj2po.py` 核对 rsj 26 条、added 0；示例启动能开窗。Shell 模式的重启与关窗需要人工点击（本会话没有界面操作权限），并入真机验收第 55–65 项，由用户在最终一次性验收时做。

**截图**：`tools/terminal-shots --phase4` 重出，覆盖 `docs/superpowers/plans/2026-09-29-terminal-phase-4-shots/`，`index.md` 更新。抽查：深色失焦选区（`selection-default-dark.png`）看得清；列选区（聚焦）里「文」「三」起点落在后半整字不选、「试」整字选中，和上游规则一致。3 期截图里没有选区，不受影响，不重出。

**spec 写回**（标「实现期修正（4 期）」，原文删除线保留）：状态行、§1.1（第 11–14 条）、§2.1、§6.3、§7.6、§9（类声明）、§9.1、§9.2、§9.3、§9.4、§9.5.2（含抬起丢失）、§9.5.3、§9.5.5、§9.6.1、§9.6.2（按需 PRIMARY）、§9.6.3（含异常隔离）、§9.6.4、§9.8、§11（选区绘制改法、alpha 0.3、对比度守卫阈值）、§12.1、§12.2（含工作线程关闭、子进程状态、`POLLNVAL`）、§12.3、§12.4、§13.2、§13.4（ConPTY 录制）、§14、§15、§16、§17.1（六条结论）、§18。

**真机验收汇总续编**：第 56–65 项，接在上面「真机验收项汇总」表的第 55 项之后。

**给 5 期的交接**：
1. 重新折行：接上后 `TyTermComputeUrlLinks` 的 `ACols` 截断不再起作用，删掉参数前先看调用点；折行后选区的坐标怎么跟，照上游核实后再定。
2. 冷启动光栅化慢：根因在共享单元 `Painter.pas` 的 `TTyGdiTextRenderer`，要改须用户拍板；控件侧的预算与分帧已经在。
3. `MinimumContrastRatio`（§10.9），连同 3 期留下的浅底 3 号色与本批聚焦选区在 office 深色上的对比度（1.27）一起看。
4. 流控已在 4 期；5 期做控件侧 `Write` 回调顺序测试与性能数字。
