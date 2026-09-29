# 终端控件 5 期（最后一期）：重新折行、流量控制余项、性能、最低对比度 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（项目约定，优先于子技能的默认做法）**：按子批次连续实现，**每个任务只写代码 + 测试并单独提交**；每个子批次写完**编译一次、只跑本段的 suite、只修本段的红**；node 生成脚本例外，生成物要进提交，脚本当场跑。整期写完后（Task 14）一次全量、集中变异、整体审查（规格核对 + 代码质量）。中途不汇报、不问要不要提交。**用户要求终端所有期做完再一次性真机验收**：本期的真机项、截图进期末验收材料，Task 15 把 3、4、5 期的验收项合成一份独立文档，不中途找用户。
>
> **谁来做**：标 **【主控执行】** 的步骤实现 agent **不做**、直接跳过：编 `tycontrols.lpk` / `tycontrols_dt.lpk`、编示例、跑 `scripts/example-rsj2po.py`、截图、启动示例、问用户。实现 agent 不编任何 `.lpk`、不编示例、不改 `D:/Projects/xterm.js` 里被跟踪的文件，node 依赖不进本仓库。`tools/terminal-bench`（本期新建，Task 1）由实现 agent 编和跑——它和 `tools/terminal-fontprobe` 一样直接引用 `source/`、不经 `.lpk`。
>
> **共享文件**：`source/tyControls.Base.pas`、`source/tyControls.Painter.pas`、`source/tyControls.StyleModel.pas`、`source/tyControls.TextMenu.pas` 本期**不改**。唯一可能要改的是 `Painter.pas`（冷启动光栅化，开工前问题一第 1 条），**只在用户选了 A 时**走 Task 8A；默认走 Task 8（终端自己的光栅路径，不碰共享文件）。执行中发现别处非改不可，停下交主控，主控先问用户。

**Goal:** 主缓冲在改列数时照 xterm.js 重新折行（老 ConPTY 照上游关掉、走启发）；写入队列把一次很大的 `Write` 切进多片；整屏上滚只画新露出的行、冷启动光栅化提速、吞吐和内存有可复现的测量；加 `MinimumContrastRatio`（上游 `ensureContrastRatio`）；按用户的选择扩展自绘字形；最后把 3–5 期的真机验收合成一张表。

**Architecture:** 折行是 Buffer 层的纯移植——`BufferReflow.ts` 的五个函数和 `Buffer.ts` 的 `_reflow*` 进一个新 include `tyControls.Terminal.Buffer.Reflow.inc`，开关换成上游规则，期望值全部由 node 跑上游生成（Buffer 层操作脚本、Core 层字节流、选区与网址两类浏览器层用例）。控件侧只接线：改尺寸后的选区、链接悬停、滚动条。性能三件：写入队列在 131072 字节的解析段之间查预算；控件按「行对象的序号 + 修订号 + 这一行的覆盖层」判断一行像素能不能原样搬过来；Win32 上终端自己持有一张 GDI 位图光栅化字形，逐位复现库文字管线的遮罩。对比度照上游移植纯函数（亮度用 V8 的 `pow` 结果表，逐位对上），在行绘制器里、暗淡之前调整前景。

**Tech Stack:** FPC 3.2.2 / Lazarus LCL、BGRABitmap、fpcunit；node v22.22.2 + xterm.js 6.0.0 本地 checkout 的 `out/`（1 期已构建；`out/common/buffer/BufferReflow.js`、`out/common/Color.js`、`out/browser/renderer/shared/RendererUtils.js`、`addons/addon-webgl/out/customGlyphs/*` 都在，写计划时实跑过）；Win32 GDI（`LCLIntf.DrawText`、`TBitmap` pf24bit）。

**设计依据：** `docs/superpowers/specs/2026-09-28-terminal-view-design.md`（下称 spec）。本计划覆盖 §18 第 5 期全部、§6.2 折行、§3 流量控制余项、§10.1 整屏上滚、§10.3 / §10.4 冷启动与缓存统计、§10.5 自绘字形范围、§10.9 与 §9.1 的 `MinimumContrastRatio`、§11 浅底 16 色的兜底、§13.4 重新折行一行、§15、§16 的性能项，以及 4 期签收「给 5 期的交接」四条、3 期签收留给最终验收的一条。

**不在本期**（以后单独立项，spec §15）：屏幕阅读器、连字、图片协议、kitty 键盘协议、win32-input-mode 键盘编码、Alt+单击移动光标、搜索 / 序列化等 addon；CHANGELOG（发版时写，[[changelog-user-facing]]）；合并 `feat/terminal` 到 `main`（用户验收之后另行决定，届时按 [[pre-merge-checklist]]）。

---

## 总目录

先读完主文件（核实记录、开工前问题、接口清单、地雷、判据约定），再按任务号顺序做；附录里的任务引用主文件的节名。

| 部分 | 文件 | 任务 | 这一批做完能看到什么（执行时不单独验收，见执行方式） |
|---|---|---|---|
| 主文件 | 本文件 | Task 0 基线；Task 13 文档；Task 14 收尾；Task 15 最终验收文档 | 核实记录、开工前问题、接口、地雷、5 期真机项草稿、与规格不符之处 |
| 5a 折行 | [`2026-09-29-terminal-phase-5a-reflow.md`](2026-09-29-terminal-phase-5a-reflow.md) | Task 1–4 | 基准工具量出改动前的数字；缓冲在各种宽度来回改、宽字符跨行、组合字符、标记、光标、滚回满、备用屏、四种 `WindowsPty` 下与上游逐位相同；2 期绕开折行的改列数用例补上默认配置的镜像 |
| 5b 控件接线与流控 | [`2026-09-29-terminal-phase-5b-view-flow.md`](2026-09-29-terminal-phase-5b-view-flow.md) | Task 5–6 | 拖窗口宽度长行折回、缩回来复原；选区、悬停链接、滚动条跟着对；网址不再按网格宽度截；一次 `Write` 20 MB 也按片让出；控件侧回调顺序有测试守着 |
| 5c 性能 | [`2026-09-29-terminal-phase-5c-performance.md`](2026-09-29-terminal-phase-5c-performance.md) | Task 7–9 | 一行一行往上滚时每帧只画新露出的行；Win32 冷启动光栅化快若干倍、像素不变；吞吐、帧、内存、缓存命中有测试守、有数字 |
| 5d 对比度与自绘字形 | [`2026-09-29-terminal-phase-5d-contrast-glyphs.md`](2026-09-29-terminal-phase-5d-contrast-glyphs.md) | Task 10–12 | `MinimumContrastRatio` 与上游逐位相同；打开后浅色皮肤上的暗色字变清楚、框线块元素不变；（用户同意时）Powerline 与盲文自绘 |

---

## 核实记录（写计划时读源码 + 实跑得到，2026-09-29）

执行者不用重做；Task 0 和各任务会在真构建上复核其中几条。行号是 `xterm:`（`D:/Projects/xterm.js`，`c58ea36`）或本仓库。

**上游折行（`src/common/buffer/Buffer.ts`、`BufferReflow.ts`）**

1. **开关 `_isReflowEnabled`（`Buffer.ts:310-316`）**：`windowsPty.buildNumber` 为真值（非 0、非 undefined）时答 `this._hasScrollback && backend === 'conpty' && buildNumber >= 21376`，否则答 `this._hasScrollback`。用的是**字段** `_hasScrollback`（主缓冲为真），不是 getter `hasScrollback`（`:103-105`，还要求 `maxLength > rows`）。实跑（headless，10 列写 15 个字再改 20 列）：默认、`{conpty}`（无构建号）、`scrollback: 0` 都折回一行；`{conpty, 19044}`、`{winpty, 30000}`、`{无后端, 30000}` 都不折。本仓库 `BuildNumber = 0` 表示「没给」，和 JS 的假值对得上。
2. **启发（`CoreTerminal.ts:279-289`、`WindowsMode.ts:9-26`）**：后端和构建号都 `!== undefined`、`conpty` 且 `< 21376` 才开。2 期已移植（`Core.Services.inc:453-458`）。上游的 `{conpty, buildNumber: 0}` 会同时开启发、开折行；本仓库 0 = 没给，表达不了这个组合——没有意义的输入，不进夹具，§15 记一句。
3. **`resize` 的顺序（`Buffer.ts:160-286`）**：先把行加宽（只在变宽时）、再调行数、再缩环形表、再钳光标；然后 `if (_isReflowEnabled) { _reflow(); 变窄就把每行截到新列数 }`；最后保证 `ybase + y` 在行内。`Buffer.pas:2181-2270` 已按这个顺序写好，`IsReflowEnabled` 恒 False、`Reflow` 是空的（`:2130-2139`）。
4. **`_reflowLarger`（`:331-362` + `BufferReflow.ts:25-176`）**：`reflowLargerGetLinesToRemove` 逐个折行段把后面的行往前搬（`copyCellsFrom(..., false)`），行尾是宽字符放不下时挪到下一行（`:81-87`），段尾清空，数出段尾能删掉的空行，给出 `[下标, 个数]` 对；`reflowLargerCreateNewLayout` 按对**正向**发 `onDelete`（下标减去已删的）；`reflowLargerApplyNewLayout` 用 `set` 把留下的行排到前面、再 `lines.length = 新长度`；`_reflowLargerAdjustViewport` 逐个删掉的行调视口：`ybase = 0` 时 `y--`、行不够 `newRows` 就 `push` 空行，否则 `ybase--`、视口在底部时 `ydisp` 跟着；最后 `savedY` 减。
5. **`_reflowSmaller`（`:364-537`）**：从最后一行**往前**找折行段；段长用 `reflowSmallerGetNewLineLengths`（`BufferReflow.ts:179-213`：宽字符落在切口就少放一格）；新行 `getBlankLine(DEFAULT_ATTR_DATA, true)`；数据**倒着**搬（`copyCellsFrom(..., true)`）；切口前是宽字符的行尾补空格子（`:466-471`）；视口调整在循环里逐段做，其中 `ybase = 0` 分支会 `lines.pop()`（`:476-479`）；`savedY` 加。循环结束后一次重排：`lines.length = min(maxLength, length + countToInsert)`（`:502`），从上往下重新放一遍每个下标，插入事件**倒序**发、下标累加修正（`:525-531`），最后 `onTrim(amountToTrim)`（`:532-535`）。
6. **`reflowSmallerGetNewLineLengths` 的死循环**：`newCols = 1` 且有宽字符时会一直算出长度 0（上游注释 `BufferReflow.ts:175-177`「Calling this with a newCols value of 1 will lock up」）。Core 的最小列数是 2（`BufferService.ts:13`，本仓库 `TyTermMinimumCols`），走 Core 碰不到；Buffer 层的公开 `Resize` 能被直接调到。
7. **`getWrappedLineTrimmedLength`（`:215-229`）** 用**旧列数**判断「本行最后一格没内容、宽度 1，且下一行第一格是宽字符」——那一格是宽字符提前折行留下的空格子，不算进长度。
8. **`reflowCursorLine` 默认 false（`OptionsService.ts:50`）**：光标所在的折行段两个方向都不动。实跑：光标停在 `$ abcdefghijKLM`（10 列折成两行）的第二行，改 20 列后仍是两行；设成 true 才合成一行（且光标 x 不重算，上游如此）。**「拖宽后长行复原」对光标所在那一段不成立**——提示符后面正在打的长命令就是这一段（开工前问题一第 5 条）。本仓库 `TTyTerminalOptions.ReflowCursorLine` 字段在（`Buffer.pas:368`），Core 没有属性，`lib-term.js` 没有这个选项。
9. **标记**：缓冲对 `onTrim` / `onInsert` / `onDelete` 的处理在 `Buffer.ts:640-662`（本仓库 `LinesTrim` / `LinesInsert` / `LinesDelete`，`Buffer.pas:2509-2580`）；OSC 8 链接表按标记记行，标记作废时那一行从链接里去掉。本仓库的行表事件只在表内部触发（`DoTrim` 是私有的，`:1718-1722`），缓冲自己占着这三个事件（`:2043`）——上游在折行里**直接触发** emitter，本仓库要一个公开的触发口。
10. **`CircularList.length` 的 setter 按原始下标清槽**（`CircularList.ts:91-98`）；本仓库照搬（`Buffer.pas:1767-1776`，`Store(i, nil)` 会 `Release`）。起点不为 0 时，原始下标 `[旧长度, 新长度)` 上可能正放着**还在用的行**：上游的 JS 数组 `originalLines` 抓着它们，本仓库不先 `AddRef` 就是释放后使用（地雷 1）。
11. **选区与改尺寸**：`SelectionService.ts:158-162` 只在**行数**变了时清选区；折行插删不跟（选区只订阅 `onTrim`，`:144`）。所以改列数重新折行后，选区照旧指着同样的坐标——字已经挪了，选中的是别的字；`_reflowSmaller` 的 `onTrim` 会把它整体上移。
12. **链接悬停**：`Linkifier.ts:47-50` 改尺寸时清掉当前链接。本仓库控件的 `CoreResize`（`Terminal.pas:894-909`）没清悬停——折行以后下划线会画在旧范围上（Task 5 补）。
13. **网址回映射的 `ACols`**（`Links.pas:86-89`、`:854-855`，调用点 `View.Links.inc:16`）：4 期为了模仿「会折行的缓冲」把比网格长的行按网格宽度截。上游 `_mapStrIdx` 按行自己的长度走（`WebLinkProvider.ts:171`）。接上折行后，会折行的缓冲里行长恒等于列数，截断不起作用；**不折行的地方行照样比网格长**（老 ConPTY——本机 19044 的 Shell 模式正是这样、备用屏），上游这时按全长映射，本仓库的截断反而成了偏离（开工前问题二第 6 条）。
14. **上游自己的折行用例**：`Buffer.test.ts:260-1140`（改列数、宽字符、组合字符、标记、滚回满、四种视口情形、ConPTY 构建号门限、`reflowCursorLine`）、`BufferReflow.test.ts`（`reflowSmallerGetNewLineLengths` 五例、`reflowLargerGetLinesToRemove` 两例）——输入照抄，期望值由上游代码生成。
15. **2 期绕开折行的用例**（spec §6.2 的 2 期修正）：`cases/buffer.js` 的 `scroll-cached-blank`、`rows-grow-windowspty`、`cols-change-windowspty`、`resize-cursor-clamp`、`tabs-after-resize`（`:142-163`），`cases/core-hand.js` 的 `decset-3-winlines`、`resize-min`、`resize-cols-winpty`、`resize-saved-cursor`（`:224`、`:311-315`），都带 `windowsPty = {conpty, 19044}`。改列数的那几个本期加一份**不带** `windowsPty` 的镜像。`cases/selection.js:136` 的 `keep-on-a-new-column-count` 不带 WPTY 改列数，但内容没有折行，折不折结果一样——它不证明折行。

**上游对比度（`src/common/Color.ts`、渲染层）**

16. **`rgba.ensureContrastRatio`（`Color.ts:296-321`）**：已达标答 `undefined`；前景比底暗先 `reduceLuminance`（每步 RGB 各减 `ceil(x·0.1)`），不够再试 `increaseLuminance`（每步各加 `ceil((255−x)·0.1)`），取对比度大的那个；前景亮反过来。`relativeLuminance2`（`:240-248`）用 `Math.pow((s + 0.055) / 1.055, 2.4)`；`contrastRatio`（`:377-382`）`(亮 + 0.05) / (暗 + 0.05)`。node 实跑 `ensureContrastRatio(0xffffffff, 0xc4a000ff, 4.5)` = `8e7400ff`，正是 `light.tycss` 的 3 号浅底色。
17. **选项**：默认 1（`OptionsService.ts:43`）；写入时 `Math.max(1, Math.min(21, Math.round(v × 10) / 10))`（`:188-190`）。改了清缓存（`ThemeService.ts:72`），换主题也清（`:136`）。
18. **在哪里用（DOM 渲染器 `DomRendererRowFactory.ts:494-521`）**：比值为 1、或这个码位「当底色画」（`treatGlyphAsBackgroundColor`，`RendererUtils.ts:63-65`：Powerline `E0A4–E0D6` 和框线 / 块元素 `2500–259F`）就不调；暗淡的格比值减半、用另一份缓存；选中的格对**选区底色**调（`bgOverride`，`:380-386`），主题给了选区前景就调那个前景（`fgOverride`）；缓存键是（底色，前景）。WebGL 渲染器同一套（`addons/addon-webgl/src/TextureAtlas.ts:354-466`），先算对比度、再把暗淡按透明度叠上去。
19. **两个渲染器不一致的一处**：反显且前景是默认色时，DOM 把 `colors.foreground` 当前景去比（`:456`），而底色也是 `colors.foreground`（反显，`:419`）——比的是同一个颜色，必然「不达标」，结果是把前景往反方向推；WebGL 的 `_resolveForegroundRgba`（`TextureAtlas.ts:399-417`）在反显时取 `colors.background`，比的是画出来的那两个颜色。开工前问题二第 11 条。
20. **块光标下的字不调**：DOM 的光标块用 `color: cursorAccent !important`（`DomRenderer.ts:265-269`）盖掉任何内联色。
21. 本仓库的暗淡在 `TyTermResolveCellColors` 里就混好了（`Render.pas:431-438`），下划线默认色取混好的前景——对比度必须插在暗淡之前（地雷 7）。

**性能与光栅化**

22. **库的 Win32 文字路径**（`Painter.pas:1271-1360`，`b23893ba` 起，已随 `3c86b8c7` 合进本分支）：每调一次 `TextOut` 就 `TBitmap.Create` → `pf24bit` → `SetSize` → 白底 → 设字体 → `DrawText` → `TBGRABitmap.Create(tmp)`（整张转换）→ 逐像素 `FastBlendPixel`。`TTyGdiTextRenderer` 声明在 `Painter.pas` 的实现部分，外面引用不到、也不能继承；它的字体设置是 `TBGRASystemFontRenderer.UpdateFont`（`bgra:bgratext.pas:1437-1466`：名字经 `PatchSystemFontName`、样式、`Height`、质量）再改成 `fqCleartypeNatural`（`Painter.pas:1263-1269`）。
23. **终端的光栅器**（`Render.pas:740-800`）：草稿 `TBGRABitmap` 常驻，每个字形 `TextSize` 一次、`TextOut` 一次（进上面那条路），覆盖率 = 255 − 灰度均值。spec §10.3 的数字：380 个字形冷填充约 710–900 ms，每个约 1.9 ms。
24. **滚动时控件整屏重画**：`CoreScroll` → `DirtyAll`（`Terminal.pas:828-839`）；一次解析里滚过就在 `EndDrive` 整屏失效（`:968-978`）；`RenderTo` 把脏行全画一遍（`:1955-2010`）。热缓存整屏 11.8 ms（spec §10.3，200 × 60，96 PPI）。
25. **行对象会被复用**：环形表满时 `BufferService.Scroll` 取最上面那一行 `Recycle` 再 `CopyFrom` 空行（`Buffer.pas:2749-2750`）——同一个对象换了内容；行释放后地址会立刻被新行拿到（[[assertsame-freed-pointer-trap]]）。只凭对象地址判断「这一行没变」两头都会错。
26. **阴影 ░▒▓ 按表面原点铺图案**（spec §10.4 / §10.6 的 3 期修正）：一行像素竖着搬 k 行，图案相位变了，除非 `k × 格高` 是图案周期的倍数。
27. **字形缓存已有 `Hits` / `Misses`**（`Render.pas:150-151`），没有淘汰计数。
28. **写入队列**：预算只在块与块之间查（`WriteQueue.inc:125-170`），`TestOneBigChunkIsNotSplit`（`test.terminal.core.pas:1907`，suite `TTyTerminalWriteQueueTests`）钉着这个行为；`Parse` 本来就按 131072 字节一段喂解析器（`InputHandler.inc:13-53`），段与段之间状态连续。

**自绘字形**

29. 上游 `CustomGlyphDefinitions.ts` 的区段：框线 2500–257F、块元素 2580–259F（本仓库已做）、Powerline E0A0–E0D4、进度条 EE00–EE0B、git 分支 F5D0–F60D、Legacy Computing 1FB00–、盲文 2800–28FF。部件种类：已做的是 `SOLID_OCTANT_BLOCK_VECTOR` / `BLOCK_PATTERN` / `PATH_FUNCTION`（M / L / C）；Powerline 要 `VECTOR_SHAPE`（还有 Q / T / Z，和 `drawSvgArc` 的弧，`CustomGlyphRasterizer.ts:318-404`）与 `scaleType`，盲文要 `BRAILLE`（`:169-194`）。E1：Consolas 没有 U+E0A0、U+E0B0 的字形（无墨）。

**本仓库状态**

30. `feat/terminal` 已含 `main` 的最新提交（`git log feat/terminal..main` 为空）；4 期签收全量 8285 条，唯一的红是本机 ClearType 环境下的 `TPainterTest.TestTextIsInkedAsWindowsInksIt`。

---

## 开工前要定的问题

每条都给了建议，**计划正文按建议写**；改了哪条，执行时改对应任务，收尾时（Task 14）写回 spec。第一类由主控在 Task 0 问用户；用户没回复前按建议做（和 3、4 期一样，最终一次性验收时仍可改）。

### 一、产品方向 / 用户可见（问用户）

> **状态（2026-09-29）**：用户对第 1 条**选 A（改 `Painter.pas`）**，并要求「得做好测试，尤其是对其他控件的影响，尤其是 Memo、Grid 等」——Task 8 换成 Task 8A，并按附录 5c 里 Task 8A 下方「用户追加的测试要求」执行。第 2–5 条用户未另作答复，按建议执行，最终一次性验收时可改。第二类主控按建议采纳。

1. **冷启动光栅化慢，要不要改共享文件 `Painter.pas`？**（核实记录 22、23）
   第一次画一屏新字形时每个字形约 1.9 ms，根因是库的 Win32 文字渲染器每次都新建一张 `TBitmap`、再整张转成 BGRA。
   - **A. 改 `Painter.pas`**：`TTyGdiTextRenderer` 留一张常驻的 GDI 位图、按需长大，直接读它的像素，不再整张转换。全库所有自绘文字都受益（编辑框、表格、图表的首帧）。要你同意，并且要跑全库的文字像素测试（`TPainterTest` 等）。
   - **B. 终端自己的 Win32 光栅路径**（**建议**）：在终端的渲染单元里继承 BGRA 的 LCL 字体渲染器，同样的字体设置、同样的 `DrawText`，常驻位图、直接出覆盖率遮罩，**逐位复现**现在的遮罩（有测试守着）。不碰共享文件；其他平台不变。
   - C. 不改：已有的每帧 10 ms 预算把冷填充摊到几十帧（约 0.9 秒补齐一屏）。
   建议 B；A 适合以后作为库的独立改进（本期若选 A，走 Task 8A，B 不做）。
2. **改列数重新折行之后，选区怎么办？**（核实记录 11）
   上游保留坐标：字挪了，选区还框着原来的格子，复制出来是别的字。
   **建议**：当前缓冲这次**会**重新折行（列数变了且折行开关为真）时清掉选区；不折行时（老 ConPTY、备用屏）照上游保留。这是偏离，进 §15——4 期已有同类先例（清滚回也清选区）。另一个做法是完全照上游。
3. **`MinimumContrastRatio` 的默认值和来源**（核实记录 16–18）
   **建议**：默认 1（不调，照上游）；只做控件属性，不加主题 token（上游是每个终端的选项，主题要它的话以后再加一个 `--terminal-min-contrast`）；示例加一个下拉（1 / 3 / 4.5 / 7，默认 1）。浅底 16 色的（a）/（b）/（c）仍在最终验收时定：本期截图给 xp / macos / breeze 浅色在 1 和 4.5 下的对照，你看了再选。
4. **自绘字形这期扩到哪？**（核实记录 29；spec §10.5「5 期再定」）
   **建议**：做 Powerline（E0A0–E0D4：oh-my-posh、starship、agnoster 这类提示符的箭头和圆角，Consolas 没有这些字形，现在是空白）和盲文（2800–28FF：btop 等的图形）；Legacy Computing、进度条、git 分支以后再说。选「都不做」，Task 12 跳过。
5. **光标所在的那段折行拖宽时不复原**（核实记录 8）
   上游默认不动光标所在的折行段（`reflowCursorLine = false`），理由是程序会自己重画那一行；提示符后正在打的长命令拖宽后仍是两行。
   **建议**：照上游，默认不动；`Core.ReflowCursorLine` 做成 Core 属性（宿主想要可以打开），不上控件的 published。

### 二、实现层面（主控定）

1. **折行放新 include** `source/tyControls.Terminal.Buffer.Reflow.inc`（`BufferReflow.ts` 的五个函数 + `Buffer.ts` 的 `_reflow` / `_reflowLarger` / `_reflowLargerAdjustViewport` / `_reflowSmaller`），由 `Buffer.pas` 在实现部分 `{$I}`；五个纯函数在单元接口里公开（测试直接对上游比）。照 Core 三个 include 的先例：不进 `.lpk`，notices 标题和发版守卫逐个列名。`Buffer.pas` 已经 3100 行。
2. **行表加公开的事件触发口**：`TTyTerminalLineList.NotifyInsert(AIndex, AAmount)` / `NotifyDelete` / `NotifyTrim`（上游的 emitter 本来是公开的，`CircularList.ts:49-54`）。缓冲的 `LinesTrim` 仍是唯一加 `TrimmedLines` 的地方，所以折行里的 `onTrim` 自动进计数，选区跟得上。
3. **引用计数**：重排之前把要搬的行全部 `AddRef`（上游是 JS 数组抓着，核实记录 10），重排后统一 `Release`；新行照 `*Owned` 规则；没被放回表的新行随 `Release` 释放。每个用例之后的泄漏守卫（spec §13.5 第 9 条）照常。
4. **开关逐字照上游**（核实记录 1）：`BuildNumber <> 0` 时 `FHasScrollback and (Backend = twpConPty) and (BuildNumber >= 21376)`，否则 `FHasScrollback`——**字段**，不是 `HasScrollback`。
5. **基准**：新脚本 `reflow-cases.js`（spec §13.2 早列了这个名字）+ 手写输入 `cases/reflow.js`，出两份夹具：`terminal-core-reflow.json`（Core 格式，Core 预言测试原样跑）、`terminal-reflow-units.json`（五个纯函数的输入 / 输出）。`cases/buffer.js` 加折行组（含核实记录 15 的镜像）；`cases/selection.js`、`cases/links.js` 各加几例改列数。`lib-term.js` 与 `buffer-cases.js` 加选项 `reflowCursorLine`，`lib-term.js` 加步骤 `marker`（`term.registerMarker(偏移)`）。`lib-dump.js` 的 `PORTED` 加 `common/buffer/BufferReflow`、`browser/renderer/shared/RendererUtils`、`browser/ColorContrastCache`。
6. **删掉 `TyTermComputeUrlLinks` 的 `ACols` 参数**（核实记录 13）：回到上游「按行自己的长度」。会折行的缓冲里没有区别；老 ConPTY、备用屏里和上游一致了。夹具补「老 ConPTY 下窗口改窄后的长行里的网址」一例（上游答案）。链接下划线本来就按网格裁（`PaintRow` 的 `Min(LinkTo, ACols)`）。
7. **`CoreResize` 清悬停**（核实记录 12）：照 `Linkifier` 清掉当前链接、重画它占的行；指针再动时重新找。
8. **块内切片**（spec §3.1 的 2 期修正：「块内切片是 5 期的事」）：写入队列在 131072 字节的解析段之间查预算，一块没解析完就记下块内位置、让出。细则：块的回调在最后一段之后才调；`PendingBytes` 按段减；`OnRefreshRows` 每段一次（每段一次 `Parse`）；某段里处理器抛异常时这一块剩下的算已处理、回调照调（和现在「这一块算已处理」同义）；`WriteSync`、`Resize` 前的清空从块内位置接着解析；`DiscardPending` 连同半块一起丢、不调回调。上游整块一次解析（`WriteBuffer.ts:224-297`），这是偏离，进 §15；结果状态与整块相同（夹具证明）。
9. **行复用（整屏上滚只画新露出的行）**：不靠「视口挪了几行」推算（滚动区域、环形表满时的回收、REP 快进都会让推算出错，核实记录 25），改成**按内容认行**：`TTyTerminalLine` 加两个纯查询——`Serial: Int64`（对象出生时从类计数器取、永不重复，不怕地址复用）和 `Revision: Cardinal`（每个改内容的方法加一，`IsWrapped` 不算：它不影响像素）。控件为每个已画的视口行记 `(Serial, Revision, 覆盖层签名)`；覆盖层 = 这一行的选区列段、悬停链接列段、光标（列、形状、是否显示）、组字串。每帧：键和上一帧同一行相同 → 不画；和上一帧另一行相同 → 从那一行搬像素；都不是 → 画。帧级参数（色表签名、度量、聚焦、选区色、对比度）变了照旧整屏重画。**阴影图案例外**：画过相位相关字形的行只在 `(新行 − 旧行) × 格高` 是图案纵向周期的倍数时才搬（核实记录 26；周期由 `gen-terminal-glyphs.js` 从数据算出、写进 `CustomGlyphs.inc`）。判据是「增量画 = 整屏重画，逐字节」。
10. **Task 8（冷启动 B）的做法**：`Render.pas` 里 `{$IFDEF LCLWin32}` 声明 `TTyTermGdiGlyphRenderer = class(TLCLFontRenderer)`：`UpdateFont` 先 `inherited` 再设 `fqCleartypeNatural`（照 `Painter.pas:1263-1269`）；一张常驻 `pf24bit` 位图（按需长大）、`DrawText` 的标志与 `TTyGdiTextRenderer` 相同（`DT_SINGLELINE or DT_NOCLIP or DT_NOPREFIX`）；读扫描线得到每像素的 ClearType 覆盖率（三通道平均），再**按旧路径的算术**折成遮罩——旧路径是「在白底上 `FastBlendPixel` 黑色、alpha = 覆盖率」，再取 255 − 灰度均值，舍入要一样。度量（`TextSize`）先照旧走 BGRA 草稿；Task 1 的拆分数字说它也贵，再挪到同一个 DC 上用 `DT_CALCRECT`（同样要逐位对上）。别的 widgetset 不变。
11. **对比度的颜色取法照 WebGL**（核实记录 19）：比的是**画出来的**底色和前景（反显时前景默认色 = 主题底色）。DOM 那种「反显默认色拿前景比前景」不照搬，进 §15。其余照上游：暗淡的格比值减半、另一份缓存，先调前景再做暗淡混合；排除 `2500–259F` 与 `E0A4–E0D6`；选中的格对选区底色调，主题给了选区前景就调选区前景；块光标下的字、链接下划线、显式下划线色都不调；默认下划线跟着调整后的前景（DOM 的 `currentColor`）。
12. **亮度用表**：`relativeLuminance` 里的 `Math.pow` 在 V8 上不保证正确舍入，FPC 的 `Power` 也不一样（[[fpc-power-and-str-traps]]），比较 `cr < ratio` 恰在边界时一个 ulp 就会让循环多走一步。`contrast-cases.js` 把 256 个通道值的线性化结果按 IEEE 位模式写成生成物 `source/tyControls.Terminal.Luminance.inc`；Pascal 的亮度 = 表[r]·0.2126 + 表[g]·0.7152 + 表[b]·0.0722，按 JS 的顺序左结合，常量一律 `Double`（[[fpc-real-constant-is-single]]）。
13. **改尺寸要不要合并**：先量（Task 1 与 Task 9）。`Scrollback = 10000`、200 列满屏、两行一折时一次改尺寸若超过 50 ms，就把 `UpdateGrid` 里的 `Core.Resize` 合并成「消息循环里最后一次」（`QueueAsyncCall`，只留最后的尺寸）；没超就不做。结论与数字写回 spec。
14. **性能测试的判据**：能数的一律数（每帧画了几行、分配了几张位图、缓存新增了几个字形），不用计时；非计时不可的给宽裕上限（相对同一次运行里的旧路径，或 Task 1 基线的倍数），精确数字写进 spec，不进断言。计时测试照 4 期的做法把冷冻的时钟换回墙上时间。
15. **基准工具 `tools/terminal-bench`**（新，Task 1）：LCL 程序、无窗体模式跑、直接引 `source/`、不进包，输出一张 Markdown 表。改代码之前先量一次（基线），Task 9 再量一次。
16. **`MinimumContrastRatio` 用 `Double`，不用 spec §9.1 写的 `Single`**：上游的值是 JS 双精度，钳制后是「一位小数」（1.3、4.5）；存成 `Single` 再转回来，1.3 变成 1.2999999523，`cr < ratio` 恰在边界时和上游不同。`Double` 的 published 属性照常进 `.lfm`；`stored` 函数照旧。写回 §9.1。

---

## 需要改共享文件的地方

**结论：默认不需要。只有用户在开工前问题一第 1 条选了 A，才改 `Painter.pas`（Task 8A）。**

| 看起来要改 | 为什么 | 本期怎么做 |
|---|---|---|
| `Painter.pas` 的 `TTyGdiTextRenderer` 每次新建 `TBitmap`（核实记录 22） | 冷启动光栅化慢 | **问用户**（开工前问题一第 1 条）。默认 B：终端在自己的 `Render.pas` 里继承 `TLCLFontRenderer`、常驻位图，逐位复现遮罩（Task 8） |
| `Painter.pas` 的 `TTyGdiTextRenderer` 在实现部分，没法继承或复用 | B 想用同一个字体对象 | 不复用：照 `TBGRASystemFontRenderer.UpdateFont` + `fqCleartypeNatural` 自己配，靠「遮罩逐位相等」的测试证明配得一样 |
| `Base.pas` / `StyleModel.pas` | — | 本期没有涉及 |

**会改的终端单元**（不是共享文件，明列）：`Terminal.Buffer.pas`（行的 `Serial` / `Revision`、行表的触发口、折行开关、`{$I}`，Task 3、7）、新 `Terminal.Buffer.Reflow.inc`（Task 3）、`Terminal.Core.pas` / `Core.Services.inc`（`ReflowCursorLine`，Task 4）、`Core.WriteQueue.inc` / `Core.InputHandler.inc`（块内切片，Task 6）、`Terminal.Links.pas`（删 `ACols`，Task 5）、`Terminal.Render.pas`（光栅路径、行绘制器的对比度、缓存统计，Task 8、9、11）、新生成物 `Terminal.Luminance.inc`（Task 10）、`Terminal.CustomGlyphs.inc`（重新生成：图案周期，Task 7；有条件的新区段，Task 12）、`Terminal.pas` 与 `View.*.inc`（Task 5、7、11）。

---

## 接口清单（全计划用这一套名字）

和 spec 不同或新增的地方标 ★，收尾写回。

### `source/tyControls.Terminal.Buffer.pas` + `…Buffer.Reflow.inc`（★ Task 3、7）

```pascal
type
  TTyTermLineArray = array of TTyTerminalLine;
  TTyTermReflowLayout = record
    Layout: TIntegerDynArray;                  { INewLayoutResult.layout }
    CountRemoved: Integer;
  end;

  TTyTerminalLine = class
  public
    { ★ Task 7：纯查询。Serial 出生时从类计数器取、永不重复；Revision 每个改内容的方法
      （SetCell、SetCellFromCodepoint、AddCodepointToCell、InsertCells、DeleteCells、
      ReplaceCells、Resize、Fill、CopyFrom、CopyCellsFrom 与内部写组合 / 扩展表的路径）加一，
      IsWrapped 不算。控件据此认出「这一行的像素没变」 }
    property Serial: Int64 read FSerial;
    property Revision: Cardinal read FRevision;
  end;

  TTyTerminalLineList = class
  public
    { ★ 上游 onInsertEmitter / onDeleteEmitter / onTrimEmitter.fire（折行直接触发） }
    procedure NotifyInsert(AIndex, AAmount: Integer);
    procedure NotifyDelete(AIndex, AAmount: Integer);
    procedure NotifyTrim(AAmount: Integer);
  end;

{ BufferReflow.ts（★ 公开给测试；缓冲自己也用） }
function TyTermReflowLargerGetLinesToRemove(ALines: TTyTerminalLineList; AOldCols, ANewCols,
  ABufferAbsoluteY: Integer; const ANullCell: TTyTerminalCellData; AReflowCursorLine: Boolean): TIntegerDynArray;
function TyTermReflowLargerCreateNewLayout(ALines: TTyTerminalLineList;
  const AToRemove: TIntegerDynArray): TTyTermReflowLayout;           { 发 NotifyDelete }
procedure TyTermReflowLargerApplyNewLayout(ALines: TTyTerminalLineList; const ALayout: TIntegerDynArray);
{ ANewCols >= 2（Core 保证；1 在上游会死循环，这里抛 EArgumentOutOfRangeException，§15） }
function TyTermReflowSmallerGetNewLineLengths(const AWrapped: TTyTermLineArray;
  AOldCols, ANewCols: Integer): TIntegerDynArray;
function TyTermGetWrappedLineTrimmedLength(const ALines: TTyTermLineArray; AIndex, ACols: Integer): Integer;
```

`TTyTerminalBuffer` 的私有部分加 `ReflowLarger`、`ReflowLargerAdjustViewport`、`ReflowSmaller`；`Reflow` 与 `GetIsReflowEnabled` 填上（开工前问题二第 4 条）。单元头「Reflow is phase 5」那段与「Buffer.Resize only touches lines between ring changes」一句改写。

### `source/tyControls.Terminal.Core.pas`（★ Task 4、6）

```pascal
  TTyTerminalCore = class
  public
    { reflowCursorLine（OptionsService.ts:50），默认 False：光标所在的折行段不重排 }
    property ReflowCursorLine: Boolean read GetReflowCursorLine write SetReflowCursorLine;
    { FOR THE TESTS（纯查询）：队首那一块已经解析了多少字节（块内切片） }
    property HeadChunkParsed: Integer read FChunkPos;
```

### `source/tyControls.Terminal.Links.pas`（改，Task 5）

```pascal
function TyTermComputeUrlLinks(ABuffer: TTyTerminalBuffer; AY: Integer): TTyTermLinks;   { ★ 去掉 ACols }
```

### `source/tyControls.Terminal.Render.pas`（改，Task 8–11）

```pascal
type
  TTyTermCellColors = record
    Fg, Bg, Underline: Cardinal;
    FgRaw: Cardinal;          { ★ 暗淡之前的前景（对比度从它算） }
    UnderlineIsDefault: Boolean;  { ★ 下划线色没显式给（跟着最终字色） }
    Dim, Invisible: Boolean;
  end;

  { ★ ColorContrastCache.ts：（底色，前景）→ 调整后的前景或「不用调」 }
  TTyTermContrastCache = class
  public
    function Find(ABg, AFg: Cardinal; out AResult: Cardinal; out AAdjusted: Boolean): Boolean;
    procedure Put(ABg, AFg, AResult: Cardinal; AAdjusted: Boolean);
    procedure Clear;
    property Count: Integer read GetCount;
  end;

  TTyTermGlyphCache = class
    property Evictions: Integer read FEvictions;   { ★ Task 9：LRU 淘汰计数，和 Hits / Misses 一起给基准 }
  end;

  TTyTermRowPainter = class
  public
    MinContrast: Double;                           { ★ 1 = 不调 }
    ContrastCache, HalfContrastCache: TTyTermContrastCache;
    { ★ Task 7：这一行画了相位相关的字形（阴影图案）；PaintRow 设 }
    property RowUsesYPhase: Boolean read FRowUsesYPhase;
  end;

{ ★ Color.ts：rgb.relativeLuminance / contrastRatio / rgba.ensureContrastRatio }
function TyTermRelativeLuminance(ARgb: Cardinal): Double;               { 查 Luminance.inc 的表 }
function TyTermContrastRatio(AL1, AL2: Double): Double;
{ False = 已经达标（上游 undefined）；ABg / AFg / AResult 是 $RRGGBB }
function TyTermEnsureContrastRatio(ABg, AFg: Cardinal; ARatio: Double; out AResult: Cardinal): Boolean;
function TyTermReduceLuminance(ABg, AFg: Cardinal; ARatio: Double): Cardinal;
function TyTermIncreaseLuminance(ABg, AFg: Cardinal; ARatio: Double): Cardinal;
{ OptionsService.ts:188-190；NaN 与无穷按 1（上游会存 NaN，§15） }
function TyTermClampContrastRatio(AValue: Double): Double;
{ RendererUtils.ts:63-65 treatGlyphAsBackgroundColor }
function TyTermExcludedFromContrast(ACodepoint: Cardinal): Boolean;

{$IFDEF LCLWin32}
  { ★ Task 8：终端自己的字形光栅路径（开工前问题二第 10 条） }
  TTyTermGdiGlyphRenderer = class(TLCLFontRenderer)
  public
    { AText 按草稿位图同一位置画，出和旧路径逐位相同的覆盖率遮罩 }
    function RasterizeCoverage(const AText: string; AOriginX, AOriginY, AWidth, AHeight: Integer): TGrayscaleMask;
  end;
{$ENDIF}
```

`TTyTermGlyphRasterizer` 加一个给测试的开关 `UseLibraryPath: Boolean`（默认 False；True = 走旧路径），`Task 8` 的逐位对照测试靠它两边各跑一次。

### `source/tyControls.Terminal.pas`（改，Task 5、7、11）

```pascal
  published
    { ★ Task 11：1 = 不调（OptionsService.ts:43）；写入时按上游钳到 1..21、保留一位小数 }
    property MinimumContrastRatio: Double read FMinContrast write SetMinContrast
      stored MinimumContrastRatioStored;                        { ★ Double，不是 spec 写的 Single }
  protected
    { FOR THE TESTS（Task 7）：上一帧每个视口行画的键、这一帧搬了几行 / 画了几行 }
    function RowKeyOf(AViewRow: Integer): TTyTermRowKey;
    property RowsMovedLastFrame: Integer read FRowsMoved;
    property RowsPaintedLastFrame: Integer read FRowsPaintedFrame;
    { FOR THE TESTS（Task 7）：下一帧当作整屏都脏（对照「增量 = 整屏」） }
    procedure ForgetPaintedRows;
```

`TTyTermRowOverlay = record SelFrom, SelTo, LinkFrom, LinkTo, CursorCol: Integer; CursorShape: TTyTermCursorShape; Preedit: string; end;`、`TTyTermRowKey = record Serial: Int64; Revision: Cardinal; Overlay: TTyTermRowOverlay; YPhase, Valid: Boolean; end;`（★，控件单元的类型，测试经探针读；覆盖层按字段比，不用哈希）。

### 生成物与脚本（★）

| 文件 | 由谁生成 | 进 `.lpk` |
|---|---|---|
| `source/tyControls.Terminal.Buffer.Reflow.inc` | 手写（移植） | 否（include） |
| `source/tyControls.Terminal.Luminance.inc` | `tools/terminal-oracle/contrast-cases.js` | 否 |
| `tests/fixtures/terminal-core-reflow.json`、`terminal-reflow-units.json` | `reflow-cases.js` | — |
| `tests/fixtures/terminal-contrast.json` | `contrast-cases.js` | — |

---

## 文件清单

| 文件 | 本期做什么 |
|---|---|
| `tools/terminal-bench/terminalbench.lpi`、`.lpr`、`.gitignore` | **新建**（Task 1；Task 9 扩充） |
| `tools/terminal-oracle/reflow-cases.js`、`cases/reflow.js`、`contrast-cases.js` | **新建**（Task 2、10） |
| `tools/terminal-oracle/lib-dump.js`、`lib-term.js`、`buffer-cases.js`、`regen-all.js`、`cases/buffer.js`、`cases/selection.js`、`cases/links.js`、`url-cases.js`、`selection-cases.js`、`gen-terminal-glyphs.js` | 改（Task 2、7、10、12） |
| `tests/fixtures/terminal-core-reflow*.json`、`terminal-reflow-units.json`、`terminal-contrast.json`、`terminal-buffer-ops*.json`、`terminal-selection*.json`、`terminal-links*.json` | **生成 / 重新生成** |
| `source/tyControls.Terminal.Buffer.pas`、`source/tyControls.Terminal.Buffer.Reflow.inc` | 改 / **新建**（Task 3、7） |
| `source/tyControls.Terminal.Core.pas`、`Core.Services.inc`、`Core.WriteQueue.inc`、`Core.InputHandler.inc` | 改（Task 4、6） |
| `source/tyControls.Terminal.Links.pas` | 改（Task 5） |
| `source/tyControls.Terminal.Render.pas`、`source/tyControls.Terminal.Luminance.inc`、`source/tyControls.Terminal.CustomGlyphs.inc` | 改 / **生成**（Task 7–12） |
| `source/tyControls.Terminal.pas`、`source/tyControls.Terminal.View.Links.inc`、`View.Selection.inc` | 改（Task 5、7、11） |
| `tests/test.terminal.buffer.pas`、`test.terminal.core.pas`、`test.terminal.oracle.pas`、`test.terminal.selection.pas`、`test.terminal.links.pas`、`test.terminal.render.pas`、`test.terminal.view.pas`、`test.terminal.view.paint.pas`、`test.terminal.view.links.pas`、`test.terminal.view.theme.pas` | 改 |
| `tests/test.terminal.perf.pas` | **新建**（Task 9：suite `TTyTerminalPerfTests`） |
| `tests/test.terminal.reflow.pas` | **新建**（Task 4：suite `TTyTerminalReflowTests`、`TTyTerminalReflowOracleTests`） |
| `tests/tytests.lpr` | uses 加新测试单元 |
| `tests/test.release.pas` | 改（Task 13：notices 标题守卫加两个 include） |
| `examples/terminal/umain.pas`、`umain.lfm`、`languages/terminal_example.zh_CN.json`、`languages/terminal_example.zh_CN.po` | 改（Task 11；`.po` 由主控在 Task 14 用 json 生成） |
| `tools/terminal-shots/terminalshots.lpr` | 改（Task 13：`--phase5`） |
| `docs/controls/terminal.md`、`README.md`、`README.en.md`、`THIRD-PARTY-NOTICES.md` | 改（Task 13） |
| `docs/superpowers/plans/2026-09-29-terminal-phase-5-shots/` | **新建**（Task 14 主控） |
| `docs/superpowers/plans/2026-09-29-terminal-acceptance.md` | **新建**（Task 15） |
| `docs/superpowers/specs/2026-09-28-terminal-view-design.md` | 只在 Task 14 写回 |

**不碰**：`Base.pas`、`Painter.pas`（除非 Task 8A）、`StyleModel.pas`、`TextMenu.pas`、Parser / Unicode.Width / Keyboard / Selection 四个单元（选区只在控件里接线）、主题文件、`CHANGELOG*`、`D:/Projects/xterm.js` 下任何受版本控制的文件。发现 Core / Buffer 的别的 bug 另开 `fix(terminal)` 提交并写明，不顺手改。

---

## 实现期的地雷（每个任务开工前看一眼）

1. **折行前先钉住行**（核实记录 10）：`lines.length := …` 变长时按**原始下标**清槽，起点不为 0 时清掉的可能是还要搬的行。重排前 `AddRef` 全部原行、重排后 `Release`；新行放进表后放掉自己的引用。泄漏守卫和「释放后使用」都靠 Task 4 的夹具（跑两遍：新建 + `Reset` 后）抓——测试构建开着 `-gh`（heaptrc）就更好，没开就靠 `LiveCount`。
2. **事件的次序和下标照抄**：`_reflowLarger` 正向发删除事件、下标减去已删；`_reflowSmaller` 插入事件**倒序**发、下标累加修正，然后才 `onTrim`。标记与 OSC 8 链接表都挂在这三个事件上；次序错了，夹具里的 `markers` 与 `links` 会红。
3. **`_reflowSmaller` 里视口调整和 `lines.pop()` 在循环中间做**（核实记录 5）：它会改变后面「原行」的个数；不要挪到循环后面。
4. **下标是旧列数**：`getWrappedLineTrimmedLength` 用 `FCols`（此刻还是旧值），`Resize` 最后才更新 `FCols`；别在 `Reflow` 之前改它。
5. **只经 `lib-dump.js` 加载上游**，新用到的 `.ts` 进 `PORTED`；含 `\x1b`、`\u`、正则的 JS 一律用 Write 工具落文件（[[bash-heredoc-eats-backslashes]]）；改 `.pas` 用编辑工具，不用 Git Bash 的 `sed -i`（[[git-bash-sed-strips-crlf]]）；期末变异先 `git diff --stat` 确认改到了（[[crlf-mutation-phantom-survivor]]）。
6. **FPC 的 `{ }` 注释会嵌套**（[[fpc-brace-comments-nest]]）：生成的 `.inc` 不许有花括号（脚本检查，同 `CustomGlyphs.inc`）。
7. **对比度插在暗淡之前**（核实记录 21）：`TyTermResolveCellColors` 先出 `FgRaw`；行绘制器在选区替换底色之后、按 `(底色, 前景)` 调，再做暗淡混合；默认下划线色取最终前景。`MinContrast = 1` 时像素必须和现在**逐字节相同**（3、4 期的像素测试全绿就是证据）。
8. **FPC 的两个 Single 陷阱**（[[fpc-real-constant-is-single]]、[[fpc-max-integer-literal-single]]）：`Ceil(x * 0.1)`、`0.2126` 这类常量要写成 `const K: Double = …`；`Max(1, d)` 这种整数字面量 + Double 的调用会走 Single 重载。判据：对比度夹具逐位相等。
9. **JS 的 `Math.round`**：`TyTermClampContrastRatio` 的 `round(v × 10) / 10` 用 `Floor(v × 10 + 0.5) / 10`；`4.45 × 10` 在双精度下是 44.5 还是 44.49999…，夹具说了算（[[js-round-has-no-domain]]）。
10. **行复用的三个坑**：（a）行对象会被回收复用、地址会被新行拿到——键只用 `Serial` + `Revision`（核实记录 25）；（b）阴影图案按表面原点铺，竖着搬会换相位（核实记录 26）；（c）光栅预算超了的行（`PaintRow` 返回 False）这一帧键作废，下一帧必须重画。
11. **像素搬家的方向**：Win32 上 BGRA 位图是自下而上存的（`LineOrder = riloBottomToTop`，`BlitSurface` 已处理过一次）；搬行按 `ScanLine[y]` 逐像素行拷，先把要搬的源行拷进一张草稿再写回，不在原地重叠拷。
12. **冷启动光栅化的「逐位相同」**（开工前问题二第 10 条）：旧路径在白底上 `FastBlendPixel` 黑色再取 255 − 灰度均值，舍入不是恒等；新路径要复现这一步的整数算术，不是直接用 ClearType 覆盖率。对照测试覆盖 95 个 ASCII × 常规 / 粗 / 斜 / 粗斜 × 96 / 144 PPI + 一组 CJK、韩文、表情。
13. **块内切片与重入**：处理器里调 `Resize` / `WriteSync` 被延后到「这一块处理完」（spec §3.1）；切片后「这一块」要等最后一段——延后的调用在最后一段、回调之后执行，不在段与段之间执行。
14. **无头像素测试三件套**（[[headless-render-needs-sentinel-ground]]）：哨兵底色 + 真父窗体 + 自建 controller；对比度用**下划线**的像素验前景（下划线是整条纯色，字形像素受字体影响）。
15. **单跑绿 / 全量红** 先 `lazbuild -B` 重编（[[canary-then-rebuild]]），再查进程级状态（[[suite-order-widgetset-init]]）。计时测试偶发先查时钟有没有换回墙上时间。
16. **测试钉死了旧行为**（[[tests-that-pin-the-bug]]）：打开折行后，3、4 期里改列数的控件测试可能钉着「不折行」的答案；`TestOneBigChunkIsNotSplit` 钉着「不切块」。改这些测试前先确认新答案来自上游夹具或本计划的判据，不是「先跑一遍看看」（[[tests-written-with-the-fix-are-green-and-wrong]]）。
17. **published default = 构造值**（[[tabstop-declared-default-must-match]]）：`MinimumContrastRatio` 是浮点，用 `stored` 函数；3 期的 RTTI 守卫只管序数属性，本期加一条管它。
18. **示例规矩**（[[examples-must-be-lfm-titlebar-skin]]、[[demo-edits-lfm-not-code]]、[[no-native-controls-in-ui]]、[[skin-variance-breaks-fixed-widths]]）：新下拉写进 `.lfm`、`AutoSize`、库控件；英文标题同步 `.po` 的 msgid（[[example-english-caption-fit]]）；`.po` 新条目 msgstr 不能空（[[empty-po-entry-blocks-startup]]）。
19. **新测试单元进 `tytests.lpr`；新 include 不进 `.lpk` 但发版守卫要查它随包发出**（[[new-unit-missing-from-lpk]]）。

---

## 跑测试的固定套路（每段末只跑本段；Task 14 跑全量）

改了 `source/` 之后**必须** `lazbuild -B`。exe 用唯一名 `tytests-term.exe`。

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi > /tmp/term-build.txt 2>&1 || { tail -30 /tmp/term-build.txt; false; } && cd tests && cp tytests.exe tytests-term.exe && for s in $SUITES; do ./tytests-term.exe --suite=$s --format=plain > /tmp/term-$s.txt 2>&1; printf '%s: ' $s; grep -E "Number of (run tests|errors|failures)" /tmp/term-$s.txt | tr '\n' ' '; echo; done
```

| 段 | 编译时机 | `SUITES` |
|---|---|---|
| 5a | Task 4 之后 | `TTyTerminalReflowOracleTests TTyTerminalReflowTests TTyTerminalBufferOracleTests TTyTerminalBufferTests TTyTerminalCoreOracleTests TTyTerminalCoreTests TTyTerminalWriteQueueTests TTyTerminalReentryTests TTyTerminalSelectionOracleTests TTyTerminalLinksOracleTests TReleaseManifestTest` |
| 5b | Task 6 之后 | 上一行 + `TTyTerminalLinksTests TTyTerminalViewTests TTyTerminalViewPaintTests TTyTerminalViewMouseTests TTyTerminalViewLinkTests TTyTerminalViewInputTests TTyTerminalExampleTests` |
| 5c | Task 9 之后 | 上一行 + `TTyTerminalRenderTests TTyTerminalPerfTests` |
| 5d | Task 12 之后（没有 Task 12 就 Task 11 之后） | 上一行 + `TTyTerminalViewThemeTests TI18NTest` |

**判据是每个 suite 那一行都有 `Number of run tests`、errors / failures 为 0**，不是 exit code。某一行为空 = 跑丢了，重跑，别读成通过。每段只修本段的红，**不跑全量、不做变异、不汇报**。计时类（`TTyTerminalPerfTests`）单跑一次后再跑两次，三次都绿才算。

全量（Task 14，输出必须重定向到文件，[[known-rare-suite-flake]]）：

```bash
cd /d/Projects/ty-3.1/tests && ./tytests-term.exe --all --format=plain > /tmp/term-all.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/term-all.txt
```

node 侧：`cd /d/Projects/ty-3.1 && node tools/terminal-oracle/regen-all.js --expect-clean`（先把工作区提交干净）。

基准工具（Task 1、Task 9、Task 14）：

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tools/terminal-bench/terminalbench.lpi > /tmp/term-bench-build.txt 2>&1 || tail -20 /tmp/term-bench-build.txt; tools/terminal-bench/terminalbench.exe --all > /tmp/term-bench.md 2>&1; cat /tmp/term-bench.md
```

---

## 关于判据和变异

- 纯函数给**输入 / 期望表**（或由夹具给）；夹具比较、像素、事件、计时测试写**判据**（比什么、怎么数、失败打印什么），测试代码执行时现写。
- 每条判据写明「**在哪个变异下必须红**」；各任务的变异表期末集中做（Task 14 Step 6）：改一行 → `git diff --stat` 确认改到了 → `lazbuild -B` → 跑相关 suite → **必须红** → 改回 → 重编重跑 → 绿。没红的先查改没改对地方、再查是不是「这条路走不到」；确实没红，当场补测试，签收记录写一句。
- 接线类变异（事件没转发、开关没接、`Invalidate` 没调、缓存没清）每类至少一条（[[built-not-wired-is-the-default-failure]]）。
- 所有夹具测试结尾断言比较次数 `> 0` 且等于从夹具算出的应比次数（[[assertion-never-varies-the-thing]]）；步骤型夹具每一步都比。
- 标「等价」的变异不做，理由写在表里。会死循环、会挂住的变异不做；卡住时按进程号结束 `tytests-term.exe`，**禁用 `taskkill -im`**（[[parallel-agent-worktree-hazards]]）。

---

### Task 0: 基线、问用户

**Files:** 无（只记数）

- [ ] **Step 1: 【主控执行】问用户开工前问题一的五条**，把答复写进「开工前要定的问题 · 一」开头的「状态」引用块（格式照 4 期计划）；用户没回复就按建议开工，告诉用户「最终验收时可改」。选了 A 的话，Task 8 换成 Task 8A。

- [ ] **Step 2: 确认起点**

```bash
cd /d/Projects/ty-3.1 && git status --short && git branch --show-current && git log --oneline -1 && git log --oneline feat/terminal..main | wc -l
```

Expected：工作区干净，分支 `feat/terminal`，HEAD 是本计划的提交或其后；`main` 没有新提交（有的话停下交主控：要不要先合）。

- [ ] **Step 3: 基线编译并跑全量**（实现 agent 做）：「跑测试的固定套路」的全量命令。条数记进草稿（4 期签收 8285，唯一的红是 `TPainterTest.TestTextIsInkedAsWindowsInksIt`），Task 14 签收时写进本计划末尾。**有别的红就停。**

- [ ] **Step 4: 上游产物在不在**

```bash
cd /d/Projects/xterm.js && git status --short | head -3 && ls out/common/buffer/BufferReflow.js out/common/Color.js out/browser/renderer/shared/RendererUtils.js out/browser/ColorContrastCache.js addons/addon-webgl/out/customGlyphs/CustomGlyphDefinitions.js addons/addon-webgl/out/customGlyphs/CustomGlyphRasterizer.js
```

Expected：checkout 干净，六个文件都在（不在就停下交主控重新 `npm run build`）。

---

### Task 13: 文档、README、notices、发版守卫、i18n、截图工具

**Files:**
- Modify: `docs/controls/terminal.md`、`README.md`、`README.en.md`、`THIRD-PARTY-NOTICES.md`、`tests/test.release.pas`、`tools/terminal-shots/terminalshots.lpr`

写法照 [[doc-writing-native-tone]]：原生中文、短句、不写小作文。

- [ ] **Step 1: `docs/controls/terminal.md`**
  - §3 published 属性表加 `MinimumContrastRatio`（默认 1、范围、保留一位小数、只调前景、哪些字不调、暗淡减半）；public 属性里 `Core.ReflowCursorLine` 一句。
  - §4 数据流与线程：一次很大的 `Write` 按 128 KB 的段切片让出；回调在整块处理完之后；`PendingBytes` 按段减少；宿主做流控的推荐写法（高低水位，示例的 `uptysession.pas`）；释放控件时队列里没处理的块不再回调。
  - §6 滚回与滚动条：改列数时主缓冲重新折行（开关规则：`WindowsPty` 没给或新版 ConPTY 才折；备用屏不折；光标所在那段默认不动、`Core.ReflowCursorLine`；选区按开工前问题一第 2 条的结论）；老 ConPTY 下窗口改窄留下的长行照旧。
  - §10 状态与主题：最低对比度与浅底 16 色的关系（皮肤的浅底不是纯白时 3 号色对比度不足，打开 4.5 兜底）。
  - §12 注意事项：删掉「窗口改窄后网址按网格宽度折回」一句；「第一次画一屏新字形」那条换成本期的数字；加一条「块内切片」对重入的影响（延后的 `Resize` 在整块之后执行）。
  - §13 本期限制 / 后续：删掉 5 期的两条；按 Task 12 的结果写自绘字形已覆盖 / 未覆盖的区段；列出以后的项（spec §15「不做」）。
- [ ] **Step 2: README**：两份的终端那一行不改控件数；功能列表若列了终端能力（查 `README.md` 里 `TTyTerminalView` 所在的段），补「改宽度重新折行、最低对比度」。
- [ ] **Step 3: notices**：`THIRD-PARTY-NOTICES.md` 的 xterm.js 一节标题加 `source/tyControls.Terminal.Buffer.Reflow.inc`、`source/tyControls.Terminal.Luminance.inc`；正文补一句：折行移植自 `src/common/buffer/BufferReflow.ts` 与 `Buffer.ts` 的 `_reflow*`；对比度移植自 `src/common/Color.ts`，亮度表由 `tools/terminal-oracle/contrast-cases.js` 从上游的公式在 node 里算出。Task 12 做了的话，自绘字形那句的区段改成实际范围。
- [ ] **Step 4: 发版守卫**：`tests/test.release.pas` 的 `TheThirdPartyNoticeCoversTheTerminalPort` 的 `Units` 数组加两个 include（数组长度跟着改）；`EveryUnitOnDiskIsListedInItsPackage` 不用动（include 不列）。**变异 D1**：notices 标题删掉 `Buffer.Reflow.inc` → `TReleaseManifestTest` 红。
- [ ] **Step 5: 截图工具**：`tools/terminal-shots/terminalshots.lpr` 加 `--phase5`，出到 `docs/superpowers/plans/2026-09-29-terminal-phase-5-shots/`，`index.md` 列每张看什么（格式照 4 期）。内容：
  1. `reflow-{wide,narrow,back}-default-{light,dark}.png`：80 列写入一段含长行（中英混排、表情、彩色、一条 OSC 8 链接、行尾宽字符正好压线）的文本，依次 80 → 47 → 80 列各截一张。
  2. `reflow-oldconpty-narrow-default-light.png`：同样内容、`WindowsPty = {conpty, 19044}` 下改到 47 列（不折行的对照）。
  3. `contrast-{1,45}-{xp,macos,breeze}-light.png`：`palette.cast` 在 `MinimumContrastRatio` = 1 与 4.5 下各一张（最终验收定浅底（a）/（b）/（c）用）。
  4. `contrast-{1,45}-default-dark.png`：Tango 0 号（`#2e3436`）在纯黑底、暗淡文字、选区里的字、`ls --color` 的反显目录。
  5. `contrast-excluded-default-light.png`：4.5 下 `mc` 风格双线框、块元素、Powerline（Task 12 做了的话）——颜色不变。
  6. Task 12 做了的话：`glyphs-powerline-{light,dark}.png`、`glyphs-braille-{light,dark}.png`（放大 3 倍一张）。
- [ ] **Step 6: 提交**（不编译；截图由主控在 Task 14 跑）

```bash
cd /d/Projects/ty-3.1 && git add docs/controls/terminal.md README.md README.en.md THIRD-PARTY-NOTICES.md tests/test.release.pas tools/terminal-shots/terminalshots.lpr && git commit -m "docs(terminal): reflow, flow control, performance and contrast in the control page

The page says when the main buffer rewraps and when it does not, how a
large write is sliced, what the minimum contrast ratio touches, and the
numbers behind the first-frame glyph cost. The notices name the two new
include files, and the shots tool gains the phase 5 set.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: 收尾——编译、全量、按 spec 逐条核、集中变异、主控编包编示例截图、审查、写回 spec、签收

**Files:**
- Modify: 本计划（签收记录）、`docs/superpowers/specs/2026-09-28-terminal-view-design.md`（写回）
- 修复时按需改 Task 1–13 的文件

- [ ] **Step 1: 一次编译 + 本期全部 suite + 全量**：「跑测试的固定套路」5d 行与全量命令。Expected：本期 suite 全 0 / 0；全量 errors / failures 只剩基线那一条、总数 = 基线 + 本期新增。红了集中修：折行、对比度**以上游为准**；修复提交 `fix(terminal): ...`，一个问题一个提交。

- [ ] **Step 2: 重跑生成，确认可复现**：`node tools/terminal-oracle/regen-all.js --expect-clean` → `clean`；`node tools/terminal-oracle/light-palette.js --check` 一致。

- [ ] **Step 3: 基准数字**：跑 `terminalbench --all`，和 Task 1 的基线并排记进签收（每项：基线 → 本期、目标、过没过）。新夹具的字节数与用例数；本期各 suite 用时；`TTyTerminalPerfTests` 三次连跑的用时。

- [ ] **Step 4: 按 spec 逐条核代码，不看测试**（[[green-tests-are-not-spec-conformance]]、[[built-not-wired-is-the-default-failure]]）。逐条记「在哪一行实现 / 为什么不需要 / 挪到以后」：
  - §6.2：折行开关（四种 `WindowsPty` 与 `Scrollback = 0`）、备用屏不折、光标段、启发仍在老 ConPTY 下开；`Resize` 的顺序。
  - §3.1 / §3.2：块内切片的六条细则（开工前问题二第 8 条）；回调顺序；`OnRefreshRows` 每段；帧率上限与光栅预算仍生效。
  - §9.5.5：改列数后的选区（开工前问题一第 2 条）、`TrimmedLines` 跟上折行的挤出；§9.7 滚动条随折行后的行数；§9.8 `ACols` 已删、悬停随改尺寸清。
  - §10.1：整屏上滚只画新露出的行（行复用的三个坑）；§10.3 / §10.4：冷启动路径、缓存统计；§10.5：自绘字形范围与 Task 12 一致。
  - §10.9 / §9.1：`MinimumContrastRatio` 默认、钳制、`stored`、缓存两份、排除的码位、暗淡减半、选区、反显取法、光标与下划线。
  - §11：浅底 16 色的（c）+ 兜底，截图就位。
  - §13.2 / §13.4：新脚本、夹具、测试单元；§14：notices；§15、§16：本期新增的偏离与真机项都进了验收表。
  - 4 期交接四条、3 期留给最终验收的一条逐条对上。

- [ ] **Step 5: 【主控执行】编包、编示例、i18n、截图**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tycontrols.lpk > /tmp/term-pkg.txt 2>&1; tail -3 /tmp/term-pkg.txt; lazbuild -B tycontrols_dt.lpk > /tmp/term-dt.txt 2>&1; tail -3 /tmp/term-dt.txt; lazbuild -B examples/terminal/terminal_example.lpi > /tmp/term-ex.txt 2>&1; tail -3 /tmp/term-ex.txt; git status --short
```

Expected：三个都编过。然后：
1. `python scripts/example-rsj2po.py examples/terminal terminal_example <Task 11 写好的译文 json>`，重编示例，`python scripts/check-example-po.py` 过。
2. `powershell -File scripts/smoke-launch-examples.ps1`（终端示例起得来、有窗口）。
3. 示例回放模式放 `ls-color.cast`，拖窗口宽度看长行折回、复原；「最低对比度」下拉切到 4.5 看浅色皮肤上的 3 号色（只看不录，真机验收时用户再看）。
4. `lazbuild -B tools/terminal-shots/terminalshots.lpi` 后跑 `terminalshots --phase5`；PNG 进 git、单张 ≤ 300 KB；抽查每组一张：画面正常、没有整块黑 / 白 / 哨兵色、折行三张的文字对得上。

- [ ] **Step 6: 集中变异**（每条三拍，必须红）：各任务变异表 B*（Task 1、9）、J*（Task 2、10 的 JS 侧）、R*（Task 3）、K*（Task 4）、V*（Task 5）、F*（Task 6）、W*（Task 7）、G*（Task 8）、T*（Task 10）、N*（Task 11）、Y*（Task 12）、D*（Task 13）。JS 侧的变异改完跑对应生成脚本、确认失败后改回，`regen-all.js --expect-clean` 仍然 `clean`。结果逐条记进签收记录；没红的当场补强。

- [ ] **Step 7: 整体代码质量审查**（`git diff <Task 0 的 HEAD>..HEAD`）：
  - 折行：与 `BufferReflow.ts` / `Buffer.ts:318-537` 逐行对照（两个方向的循环边界、宽字符挪行、`destLineLengths` 补空格子、视口调整的四个分支、`savedY`、事件次序与下标）；引用计数（钉住 / 放开成对、异常路径）；注释行号对得上。
  - 写入队列：块内位置在所有入口（`ProcessPending`、`WriteSync`、`Resize` 前清空、`DiscardPending`、`Reset`、析构）都处理了；异常路径不重复解析、不漏回调。
  - 行复用：键的每个组成部分都在；帧级参数变化全部走整屏；`Revision` 在所有改内容的方法里都加了（逐个方法对单元的写字段处 grep）。
  - 光栅：新旧两条路只在 Win32 分流；字体配置与 BGRA 的 `UpdateFont` 逐项对照。
  - 对比度：与 `Color.ts`、`DomRendererRowFactory.ts:494-521`、`TextureAtlas.ts:354-466` 对照；常量类型；两份缓存何时清。
  - 视觉值没有写死；夹具读空时每个测试都会红（计数断言）；等价变异的理由站得住。
  审出来的问题修完回到 Step 1。

- [ ] **Step 8: 写回 spec 原处，标「实现期修正（5 期）」**，原文删除线保留。至少：状态行（5 期签收）；§1.1（新增：开关用字段、`{winpty/无后端, 构建号}` 也不折、`reflowCursorLine`、选区与改尺寸、`Linkifier` 清悬停、对比度两个渲染器的差异）；§2.1（`Buffer.Reflow.inc`、`Luminance.inc`）；§3.1（块内切片落地）；§3.2（行复用）；§6.2（折行的实际规则、2 期镜像用例已补）；§6.3（`Serial` / `Revision`、行表触发口）；§7.6（`ReflowCursorLine`）；§9.1（`MinimumContrastRatio` 的钳制与 `stored`）；§9.5.5（改列数后的选区）；§9.8（`ACols` 已删、悬停清）；§10.1（整屏上滚的实际做法）；§10.3（冷启动路径与数字）；§10.4（淘汰计数）；§10.5（自绘字形范围）；§10.9（对比度细则）；§11（浅底兜底的截图位置）；§13.2（新脚本、夹具、测试单元、`tools/terminal-bench`）；§13.4（重新折行一行完成）；§14（notices 标题）；§15（新增偏离：块内切片、改列数清选区（若选）、反显默认色的对比度取法、NaN 比值按 1、`{conpty, 0}` 表达不了、Buffer 层 `newCols < 2` 抛异常）；§16（性能项的本机数字，四个 widgetset 的留给真机）；§17（5 期开工前问题的结论）；§18（5 期实际做了什么）。

- [ ] **Step 9: 签收记录写进本计划末尾，提交**：全量条数（基线 → 签收）、提交区间、各 suite 用时、夹具体积与用例数、基准数字对照、变异结果（每条红 / 补强 / 等价）、spec 写回的节号、遗留。

```bash
cd /d/Projects/ty-3.1 && git add docs/ && git commit -m "docs(terminal): phase 5 sign-off; corrections written back into the spec

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15: 最终验收文档（3–5 期合并）

**Files:**
- Create: `docs/superpowers/plans/2026-09-29-terminal-acceptance.md`

用户要求所有期做完后**一次性**真机验收。这份文档是他拿着逐项验的唯一入口，写法照 [[doc-writing-native-tone]]，不引用计划里的内部编号以外的东西就能看懂。

- [ ] **Step 1: 开头（短）**：一句话说这是什么；怎么准备（`lazbuild -B examples/terminal/terminal_example.lpi`，Linux / macOS 各自怎么编；WSL 里 `tools/terminal-ptytest` 已跑过的不用再跑）；建议的顺序（先 Win32 本机，再 Windows 11，再 Linux GTK2 / Qt6，最后 macOS）；每项看完在「结果」列写 过 / 不过 / 现象。

- [ ] **Step 2: 合并的验收表**：一张表，列为 `# | 期 | 项 | 平台 | 怎么验 | 算过 | 截图 | 结果`。
  - 第 1–31 项：**原样**取自 `2026-09-29-terminal-phase-3.md` 末尾「真机验收项汇总」（文字不改，只加「期 = 3」和截图列）。
  - 第 32–65 项：原样取自 `2026-09-29-terminal-phase-4.md` 末尾（期 = 4）。
  - 第 66 项起：本计划下面「5 期新增的真机验收项」（期 = 5），按 Task 12 的结果删掉不适用的一项后连续编号。
  - 某一项在后面的期里已经被改写（比如第 35 项老 ConPTY 的折行启发在 5 期仍然成立、第 54 项流控在 5 期多了块内切片），在「怎么验」里补一句「5 期：…」，不另起一项。
  - 表后按平台给一个索引（Win32 本机 / Windows 11 / GTK2 / Qt6 / Cocoa 各自要做的项号），方便用户在一台机器上一次做完。

- [ ] **Step 3: 截图目录**：列三个目录（`2026-09-29-terminal-phase-3-shots/`、`…-4-shots/`、`…-5-shots/`），各一句话说里面是什么、链接到各自的 `index.md`；截图怎么重新生成（`terminalshots`、`--phase4`、`--phase5`）。

- [ ] **Step 4: 待用户定的决定清单**：每条写「是什么、选项、现在的做法、建议、看哪张截图 / 哪一项、定了之后改哪里（spec 节号、文件）」。至少：
  1. 浅底 16 色 3 号色：（a）以最暗浅底重算 /（b）终端底色改用更白的 token /（c）维持、靠 `MinimumContrastRatio` 兜底（spec §11、§17.1 第 4 条；截图 `…-3-shots/ansi-3-*-light-15x.png`、`…-5-shots/contrast-*-light.png`；第 26、76 项）。
  2. 浅底 7 / 15 号色调不调（3 期开工前问题一第 3 条；`ansi-7-15-default-light-2x.png`）。
  3. Shift+Home / Shift+End 保留「本地到顶 / 到底」还是照上游发给程序（第 27 项；spec §15）。
  4. 框线字符两段笔画重叠处，本仓库合成一次再混色，比 3 期初版的画法有 0.03% 的像素差 1 级（spec §10.5 的 3 期修正）——保持现状还是回到逐段混色（3 期签收留给最终验收）。
  5. 聚焦选区在 office 深色上的对比度只有 1.27（靠色相区分）：调不调 `--terminal-selection-bg`（4 期签收交接第 3 条；第 63 项）。
  6. 3 期开工前问题一的另两条：小键盘不受应用小键盘模式影响（照上游）；滚动条宽度一直留着。
  7. 4 期开工前问题一的六条：右键菜单四项自建；`AllowNonHttpLinks` 默认 False；macOS 右键先选词；Windows 默认 `%COMSPEC%`；Windows / macOS 中键无动作；双击链接选整条。
  8. 5 期开工前问题一的五条（按 Task 0 的实际答复写现状）。
  9. spec §15 里用户可能想改的偏离（链接要按 Ctrl / Cmd 悬停与单击、输入法组字时不滚到底、macOS 默认覆盖键是 Option、1016 / 14t 报设备像素）——列出来，默认不改。
  10. 验收中「记现象」的项（第 33、34、46、61、65 项等）得出的结论写回 spec 哪里。

- [ ] **Step 5: 验收之后**：一小节说用户验完后要做的事——结论写回 spec §16 / §17；不过的项开 `fix(terminal)`；合 `main` 前按 [[pre-merge-checklist]] 查 i18n 与 README；CHANGELOG 发版时写（[[changelog-user-facing]]）。

- [ ] **Step 6: 自查**：表里的项号连续、没有重复；1–65 的文字与 3、4 期计划逐字相同（`diff` 抽取出来的两段）；每个截图链接指向存在的文件（`ls` 核对）；决定清单每条都有「看哪里」。

- [ ] **Step 7: 提交**

```bash
cd /d/Projects/ty-3.1 && git add docs/superpowers/plans/2026-09-29-terminal-acceptance.md && git commit -m "docs(terminal): the acceptance sheet for all five phases

One table for the real-machine checks of phases 3 to 5, the screenshot
folders, and every decision left to the user, so the terminal can be
signed off in a single pass.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 基线数字（Task 1 填，Task 9 / Task 14 并排补本期的）

本机 Win32、Consolas 9 pt、200 × 60、Release 以外的测试构建选项同 `tytests`。每项取中位数，注明次数。

基线（Task 1，代码为 `1c419367`）：Intel Xeon Silver 4216 @ 2.10 GHz，Windows 10 LTSC 2021（19044），`terminalbench --all` 一次，各项内部的次数见各格。

| 项 | `terminalbench` 开关 | 基线（Task 1） | 本期（Task 9） | 目标 |
|---|---|---|---|---|
| Core 吞吐（WriteSync，64 KB 块，混合内容 32 MB） | `--core` | 18.9 MB/s（3 次中位） | 19.1 MB/s（过） | 不低于基线的 95%（块内切片不许拖慢） |
| 64 KB 块的解析耗时（最大 / 中位） | `--core` | 7.39 ms / 3.13 ms | 4.34 ms / 3.21 ms | 记录 |
| 一次 `Write` 20 MB，最长的一片 | `--slice` | 1 片，1025.6 ms（3 次中位；最大 1088.8） | 81 片，17.96 ms（3 次中位；最大 18.85）；同机一段 128 KB 解析 6.4–8.1 ms（过） | ≤ 12 ms + 一段（128 KB）的解析耗时 |
| 热缓存整屏重画（96 / 144 PPI） | `--paint` | 10.99 ms / 19.81 ms（50 帧中位） | 10.44 ms / 19.17 ms（过）；对比度 4.5（Task 11 后，96 PPI）12.12 ms，同一次运行里比值 1 是 11.56 ms（过：≤ 12.64） | ≤ 基线 × 1.05；对比度 4.5 下 ≤ 基线 × 1.15 |
| 一行一行滚 2000 行：每帧画的行数 / 每帧耗时 | `--scroll` | 60 行 / 6.94 ms（中位） | 2.00 行（过）/ 5.32 ms（没过：只画两行，但整块表面照旧整张贴到画布、其余 58 行经暂存区挪一遍，这两步占了大头；进 Task 14 审查） | 每帧 ≤ 3 行；耗时 ≤ 基线的 1/4 |
| 冷填充 380 个 ASCII 字形（总 / 每个；`TextSize` 与 `TextOut` 各占多少） | `--raster` | 376 个（空格不画）918 ms / 2.43 ms；`TextSize` 0.53 ms、`TextOut`（含白底）1.41 ms，`TextSize` 占 27%（3 次中位） | 376 个 431 ms / 1.13 ms；`TextSize` 0.47 ms、`TextOut` 0.54 ms，占 47%（Task 8 走了 A：终端光栅器没改，快了一倍多来自 Painter 的 GDI 渲染器留住位图；1/3 的目标只对 B 成立） | 每个 ≤ 基线的 1/3（Task 8 走 B 时） |
| 冷填充 200 个 CJK 字形 | `--raster` | 461 ms / 2.28 ms | 246 ms / 1.20 ms（同上） | 同上 |
| 50 MB 经控件：墙钟、MB/s、两次绘制的最长间隔、堆增量、存活行数、缓存命中 / 未中 / 淘汰 | `--flood` | 4803 ms、10.4 MB/s、76.8 ms、+2.9 MB、1061 行、160284 / 25483 / — | 4010 ms、12.5 MB/s、69.2 ms（没过：一次让出里是一片解析 + 一帧整屏新行 + 10 ms 光栅预算，间隔落在 60–85 ms；调预算没有一组更好，见下）、+2.9 MB、1061 行、82116 / 11842 / 0（过：堆、行数） | 堆增量 ≤ 32 MB；存活行数 ≤ 行数 + 滚回 + 4；最长间隔 ≤ 50 ms |
| 折行：`Scrollback` 10000、200 列两行一折，200 → 120 → 200 → 80 每次 | `--reflow` | —（基线不折行，只截行：0.01 / 1.29 / 0.01 ms） | 125.05 / 60.89 / 65.30 ms（10060 / 5031 / 10060 行；> 50 ms，已做改尺寸合并） | 记录；> 50 ms 触发开工前问题二第 13 条 |

预算调优（Task 9 Step 3，一次改一个，`--slice` / `--flood`）：写超时 12 / 帧 16 / 光栅 10（默认）11.3 MB/s、间隔 85.0 ms；写超时 8：7.2 MB/s、196.0 ms；写超时 16：8.6 MB/s、82.6 ms（最长一片 52.4 ms）；帧 33：9.1 MB/s、67.7 ms；光栅 5：9.3 MB/s、71.0 ms。没有一组吞吐高出 10%，**维持**默认值。

---

## 5 期做完能看到什么

- `tytests` 里本期的 suite 全绿：缓冲在各种宽度来回改、宽字符跨行、组合字符、标记、OSC 8 链接、选区、光标、滚回满、备用屏、四种 `WindowsPty`、`reflowCursorLine` 两种设置下与上游逐位相同；对比度函数与上游逐位相同；控件的选区、悬停、滚动条随折行正确；块内切片的状态与整块相同、回调顺序对；增量绘制与整屏重画逐字节相同；Win32 新光栅路径的遮罩与库的文字管线逐位相同。
- 示例里拖窗口宽度，长行折回、缩回来复原（光标所在那段除外）；最低对比度下拉切到 4.5，xp / macos / breeze 浅色上的暗黄字变清楚，框线块元素颜色不变。
- `terminalbench` 的数字：一行一行滚时每帧只画一两行；冷启动光栅化每个字形的耗时降到基线的几分之一；`cat` 大量输出时内存不涨、最长的一片不超过预算加一段。
- 一份 3–5 期合并的验收文档。

---

## 5 期新增的真机验收项（Task 15 并入合并表，接第 65 项往下编）

每项写「怎么验 / 看什么算过」。截图在 `docs/superpowers/plans/2026-09-29-terminal-phase-5-shots/`。

| # | 项 | 平台 | 怎么验 | 算过 |
|---|---|---|---|---|
| 66 | 回放模式折行 | Win32、GTK2、Qt6、Cocoa | 示例回放 `ls-color.cast`、`cat-cjk-emoji.cast`，拖窗口宽度窄、宽来回几次 | 长行按新宽度折回，缩回来复原；宽字符不劈开；颜色、链接跟着字走（截图 `reflow-*.png`） |
| 67 | 真 shell 里的折行 | GTK2、Qt6（bash、zsh）；Cocoa（zsh）；Windows 11（≥ 21376，pwsh） | 输出几行长行后拖窗口；再在提示符后打一条超长命令、拖宽 | 输出的长行折回；提示符那一段按程序的重画走（shell 收到改尺寸后自己重画，可能留一行旧提示符——上游同样，记现象） |
| 68 | 老 ConPTY 不折行 | Win32 19044 | Shell 模式（cmd）输出长行、拖窄再拖宽 | 不重新折行（启发照旧，同第 35 项）；截图 `reflow-oldconpty-*.png` 的样子 |
| 69 | 折行与选区、链接、滚动条 | 各平台 | 选中滚回里一段后拖宽度；按住 Ctrl 悬停一条折了行的网址后拖宽度；拖宽度前后看滚动条 | 选区按开工前问题一第 2 条的结论（清掉或保留）；悬停下划线消失、再移动指针在新位置出现；滚动条的范围和拇指跟着新行数 |
| 70 | 大滚回拖窗口 | Win32、GTK2、Qt6、Cocoa | `Scrollback = 10000`（示例里临时改），`seq 1 200000 \| paste -sd' '` 之类的长行填满后拖窗口宽度 | 拖动不卡（每次改尺寸的耗时见 spec §6.2 写回的数字；合并了改尺寸的话，拖动中只在停下时折一次） |
| 71 | 吞吐与帧率 | Win32、GTK2、Qt6、Cocoa | `cat` 50 MB 文本（Win：`type`）、`yes`（Win：`cmd /c "for /l %i in (0,0,1) do @echo y"`）、htop 全屏刷新；看任务管理器 / `top` | 界面不冻、能拖窗口；内存不涨过百 MB；CPU、帧率记下来写回 spec §16（四个 widgetset 各一组） |
| 72 | 一次很大的 Write | Win32（再抽一个 Linux widgetset） | `terminalbench --window --flood 20`（一个窗口、一次 `Write` 20 MB） | 灌入期间窗口能拖、能重画，不「未响应」 |
| 73 | 滚动只画新行不留残影 | Win32、GTK2、Qt6、Cocoa | less / vim 里快速翻页；tmux 分屏里一边滚；输出含 ░▒▓ 的文本并滚动；光标闪烁时滚；有选区时滚 | 画面和整屏重画一样：没有错位、没有残影、阴影图案不「跳」 |
| 74 | 冷启动首屏 | Win32 | 新开示例，回放 `cat-cjk-emoji.cast` 一次喂完 | 首屏几乎立刻画全；字形和库里别的控件的文字观感一致（和 3 期截图对照） |
| 75 | 非 Win32 的冷启动耗时 | GTK2、Qt6、Cocoa | 各平台编 `tools/terminal-bench`，跑 `--raster` | 每个字形的耗时记下来写回 spec §10.3；比 Win32 基线慢很多的平台，记成以后优化的依据 |
| 76 | 最低对比度 | Win32；17 个皮肤明暗抽看 | 示例「最低对比度」切 1 / 4.5；看 `palette.cast`、`ls --color`、暗淡文字（`printf '\e[2mdim\e[0m'`）、选区里的字 | 4.5 下 xp / macos / breeze 浅色的 3 号色清楚了；暗淡的字仍比正常的淡；决定清单第 1 条就此定（截图 `contrast-*.png`） |
| 77 | 对比度不动框线与块 | 各平台 | 4.5 下跑 mc、tmux 分屏、`printf '\u2588\u2593'` | 边框、块元素的颜色与 1 时相同 |
| 78 | Powerline 与盲文自绘（Task 12 做了才有） | 各平台 | oh-my-posh / starship 的 powerline 主题；btop | 箭头、圆角和相邻格的底色严丝合缝；盲文点阵清楚（截图 `glyphs-*.png`） |
| 79 | 高 DPI 下的折行与滚动 | Win32 150%、每显示器 DPI 切换 | 第 66、73 项在 150% 下各做一次，再把窗口拖到另一块 DPI 不同的屏 | 没有错位；切屏后格子数、字形重建，折行照新列数 |

---

## 与规格不符之处（核实中发现，Task 14 写回）

1. §6.2「Windows ConPTY 版本号低于 21376 时上游关掉折行」不完整：规则是「给了构建号时，只有 ConPTY 且 ≥ 21376 才折」——`{winpty, 任意构建号}`、`{没有后端, 构建号}` 也不折；没给构建号时一律折，包括 `{conpty}`。开关看的是主缓冲的 `_hasScrollback` 字段，所以 `Scrollback = 0` 的主屏也折（核实记录 1，实跑）。
2. §6.2 / §18「拖窗口宽度时长行重新折回、缩回来复原」：上游默认不动光标所在的折行段（`reflowCursorLine = false`），提示符后正在打的长命令不复原（核实记录 8）。
3. 4 期交接「`ACols` 截断随折行消失」：只在会折行的缓冲里消失；老 ConPTY（本机 Shell 模式）、备用屏里行照样比网格长，而上游在那里按行的全长映射——截断本身是偏离，本期删掉（核实记录 13）。
4. 4 期交接「折行后选区的坐标怎么跟，照上游核实后再定」：上游不跟——改列数不清、只随 `onTrim` 上移（核实记录 11）；结论按开工前问题一第 2 条。
5. §9.8 / 控件：上游改尺寸清掉当前悬停的链接（`Linkifier.ts:47-50`），控件没有，本期补（核实记录 12）。
6. §10.9「照 `ensureContrastRatio`，结果按（前景，底色）缓存」不完整：上游两份缓存（暗淡的格比值减半）、写入时钳到 1–21 并保留一位小数、框线 / 块元素 / Powerline 不调、选中的格对选区底色调；两个渲染器在「反显 + 默认前景」上取色不同（核实记录 16–20）。
7. §3.1 的 2 期修正「块内切片是 5 期的事」：上游不切块（`WriteBuffer.ts:224-297` 整块解析），做了就是偏离，§15 要加一条（开工前问题二第 8 条）。
8. §10.1「整屏上滚时先把缓存内容整体上移」：按「视口挪了几行」推算在滚动区域、环形表回收、REP 快进下都会错（核实记录 25），改成按行内容认行（开工前问题二第 9 条）。
9. §10.3 E2 的冷启动数字量的是 `b23893ba` 之后的库文字管线（每次新建 `TBitmap` 再整张转 BGRA）；spec 把根因写成「每次新建位图再转换」是对的，但没写它在共享文件的实现部分、终端无法继承或复用（核实记录 22）。
10. `Buffer.pas` 单元头「Buffer.Resize only touches lines between ring changes」在接上折行后不再成立（折行在环形表上整体重排），要改写。
11. §9.1 `MinimumContrastRatio` 的类型写成 `Single`：上游是双精度、钳成一位小数，`Single` 存不住 1.3 这类值，边界上会和上游不同；本期用 `Double`（开工前问题二第 16 条）。
12. §10.5「盲文、Powerline、Legacy Computing」：上游的自绘区段还有进度条（EE00–EE0B）与 git 分支（F5D0–F60D），Powerline 的实际范围是 E0A0–E0D4（区段注释写 E0BF，定义到 E0D4），要画它们还得支持 `VECTOR_SHAPE`（含 Q / T / Z 命令）与 `BRAILLE` 两种部件（核实记录 29）。
