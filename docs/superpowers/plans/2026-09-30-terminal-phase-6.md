# 终端控件 6 期：独立配色方案（Windows Terminal JSON）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（项目约定，优先于子技能的默认做法）**：整期**连续写完**——每个任务只写代码 + 测试并单独提交，任务之间**不编译、不跑测试**；Task 1–9 写完后在 Task 10 **一次编译**、跑本期 suite 和全量、集中修红、集中变异、期末整体审查（规格核对 + 代码质量）。中途不汇报、不问要不要提交。**用户要求 1–6 期一起真机验收**：本期的真机项与截图进验收材料，Task 11 并进 `2026-09-29-terminal-acceptance.md`，不另起一份、不中途找用户。
>
> **谁来做**：标 **【主控执行】** 的步骤实现 agent **不做**、直接跳过：问用户、编 `tycontrols.lpk` / `tycontrols_dt.lpk`、编示例、跑 `scripts/example-rsj2po.py`、截图、启动示例。实现 agent 不编任何 `.lpk`（可以改 `.lpk` 的文件清单）、不编示例。设计期代码（Task 7）不在测试构建里（[[designtime-package-not-in-test-build]]），它的逻辑放进运行时单元测，设计期只留胶水。
>
> **共享文件**：`source/tyControls.Base.pas`、`source/tyControls.Painter.pas`、`source/tyControls.StyleModel.pas`、`source/tyControls.TextMenu.pas` 本期**不改**。另有两个全库共用、但不在这四个里的文件本期要加东西，单独标出：`source/tyControls.StrConsts.pas`（加读写方案的错误消息，照 3 期终端菜单 `rsTerminalMenuClear` 的先例）、`designtime/tyControls.Design.CompEditors.pas`（只在用户同意开工前问题一第 2 条时，加终端的右键菜单）。执行中发现别处非改不可，停下交主控，主控先问用户。

**Goal:** 终端控件可以不跟主题、改用一套独立的配色方案（前景、背景、光标、光标下的字色、聚焦 / 失焦选区、16 色），方案可在设计器里改、进 `.lfm`，可配成明暗各一套随主题换；方案从 Windows Terminal 的 JSON（单个方案对象或 `settings.json` 的 `schemes` 数组按名取）读入、也能写出；示例带几套许可清楚的方案和「导入…」。

**Architecture:** 新的运行时单元 `tyControls.Terminal.ColorScheme`：方案对象 `TTyTerminalColorScheme = class(TPersistent)`（published 的名字 + 22 个颜色，「未设置」= `clNone`），WT JSON 的读（`fpjson`，认注释与尾逗号，自带一份认注释的 `\u` 预解码）和写，错误都是 `ETyTerminalColorSchemeError`。控件只在 `EnsurePalette` 一处接线：按 `ColorSource` 和明暗配对选出生效的方案，逐槽「方案设了用方案、否则用主题」建色表；Core 的 OSC 覆盖表照旧在色表之前，所以明暗查询、2031、禁用预混、最低对比度都不用改。通知 Core 仍只走 `EnsureThemeCurrent` 的「色表逐项比、真变了才通知」，缓存键加上配色来源、配对开关、选中那套方案的修订号。

**Tech Stack:** FPC 3.2.2 / Lazarus LCL、fpcunit；`fcl-json`（`fpjson` / `jsonparser` / `jsonscanner`，库里 AdvChart 已在用）；BGRABitmap（像素测试）。没有 node 基准：Windows Terminal 是 C++，本期的期望值来自 WT 文档与源码逐条写成的输入 / 期望表，外加 WT 自带 `defaults.json` 的原样夹具。

**设计依据：** `docs/superpowers/specs/2026-09-28-terminal-view-design.md`（下称 spec）§11.1（本期新增，含核实记录），以及 §7.3、§9.1、§14、§15、§16、§17、§18 里标「6 期新增（2026-09-30 用户拍板）」的几处。

**不在本期**：别的配色格式（iTerm2 `.itermcolors`、xterm.js `ITheme` JSON、Alacritty / kitty 等——解析留了扩展口）；16–255 色进方案（xterm `extendedAnsi`，WT 没有）；滚动条、外框、链接下划线的方案色；主题 token 改动；CHANGELOG（发版时写，[[changelog-user-facing]]）；合 `main`（验收之后另定，[[pre-merge-checklist]]）。

---

## 总目录

| 部分 | 任务 | 这一批做完能看到什么（执行时不单独验收） |
|---|---|---|
| 基线 | Task 0 | 起点、条数、用户对开工前问题一的答复 |
| 方案单元 | Task 1–4 | 颜色串、转义预解码、方案对象、读 WT、写 WT，全部是纯逻辑、各有输入 / 期望表 |
| 控件 | Task 5–6 | `ColorSource` / `ColorScheme` / 明暗配对进设计器和 `.lfm`；色表按「OSC > 方案 > 主题」取；996 / 2031、最低对比度、禁用、选区在方案下都对；通知时机对 |
| 设计器 | Task 7（有条件） | 终端右键「导入 / 导出 Windows Terminal 配色…」 |
| 示例 | Task 8 | 七套方案 + 三对明暗的下拉、「导入…」 |
| 文档与守卫 | Task 9 | 控件文档、notices、README、发版守卫、i18n、截图工具 `--phase6` |
| 收尾 | Task 10 | 一次编译、全量、按 spec 逐条核、集中变异、主控编包编示例截图、审查、写回 spec、签收 |
| 验收文档 | Task 11 | 1–6 期合在一份验收文档里 |

---

## 核实记录（写计划时读文档 / 源码 / 实跑，2026-09-30）

外部格式与上游语义的核实写在 spec §11.1.2（WT 文档与源码、xterm.js `ThemeService.ts`、FPC `fcl-json`、iTerm2-Color-Schemes 的许可），这里不重复，只补代码侧的事实。行号是本仓库 `ecd03780`。

**控件的取色路径（`source/tyControls.Terminal.pas`）**

1. `EnsurePalette`（`:1246-1324`）建 259 色表 `FPalette` 和 `FCursorInkRgb`、`FSelBg[聚焦]`、`FSelInk` / `FSelHasInk`、`FLinkRgb`。缓存键是 `FPaletteModel`、`FPaletteVersion`（`ThemeVersion`）、`FPaletteClass`、`FPaletteOverride`（`:1257-1259`）。0–15 取 `TyTerminalAnsi<n>`，实例换了底时按 `on()` 重求（`:1287-1305`）；258 与光标下的字色有「实例换了前景 / 底色就跟着换」的规则（`:1310-1317`）。选区没写时是 `($5A shl 24) or instFg`（`:1281`）。
2. `EnsureThemeCurrent`（`:1326-1373`）：`EnsurePalette` 后，若四项键和上次通知时相同就退出；否则逐项比 259 色，**真变了**才 `FCore.NotifyColorSchemeChanged`（在绘制里则 `QueueAsyncCall(@AsyncNotifyScheme)`，`:1346-1359`）；无论变没变都把外框、所有行标脏（`:1369-1372`）。第一次（`FNotifiedValid = False`）不通知。
3. 主题广播只有 `Invalidate`（`:1413-1423`，`TTyStyleController.Changed` 对每个登记的控件 `Invalidate`），它调 `EnsureThemeCurrent`；`UpdateGrid` 也调（`:1632`）。
4. `ColorSignature`（`:1900-1914`）从 `FCore.ResolveColor(0..258)` 抄 `FRawColors`（覆盖色优先）；`PremixFrameColors`（`:1926-1960`）禁用时朝父底色预混；`RenderTo` 在签名变了时清两份对比度缓存（`:2122-2131`）；选区色 `TyTermBlendOver(FPalette[257], FSelBg[FHasFocus])` 再 `Frame`（`:2154-2156`）。
5. `PaintPreedit`（`:2469-2500`）组字串的底色 / 字色 / 下划线取主题 `TyTerminalPreedit`（基础层是 `--terminal-bg` / `-fg` / `accent`），没写才退回 257 / 256。
6. Core 的明暗应答 `ReportColorScheme`（`source/tyControls.Terminal.Core.Services.inc:351-`）比 `ResolveColor(ColorBg)` 与 `ResolveColor(ColorFg)` 的亮度——覆盖优先、其次 `OnQueryBaseColor`（控件答 `FPalette`，`Terminal.pas:958-960`）。所以方案进了 `FPalette`，996 / 2031 自动按生效的底色答；**Core 本期不改**。
7. `TyLuminance`（`source/tyControls.Css.Values.pas:154-160`，Rec.601，`Single`）是 tycss `on()` 用的那一个（`> 0.5` 为浅，`:177-180`），接口里公开。明暗配对的判断直接调它，和 `on()` 同一条规则。
8. `TyTermBlendOver`（`source/tyControls.Terminal.Render.pas:1757-1765`）是选区混色用的那一个。上游 `rgba.blend`（`xterm:src/common/Color.ts:266-283`）写成 `bg + Math.round((fg − bg)·a)`，两者都是同一个实数的四舍五入，差别只在浮点误差上；4 期起就这么用，本期不动。

**流式化、RTTI 与设计器**

9. 对象属性要有 setter 才流式化：`source/tyControls.Columns.pas` 里 `TTyHeader.Columns` 的长注释（FPC 的 `TWriter.WriteProperty` 对没有 setter 的属性直接返回、`TReader.ReadPropValue` 报只读）。
10. 控件的 RTTI 守卫 `TestPublishedDefaultsMatchTheConstructor`（`tests/test.terminal.view.pas:959-988`）只走控件自己的序数属性，不进子对象；`TestStreamedValuesSurviveLoading`（`:1015-1049`）用 `WriteComponent` / `ReadComponent` 往返。本期要把两个方案对象的子属性也守上。
11. 设计期的组件编辑器都在 `designtime/tyControls.Design.CompEditors.pas`（`TComponentEditor` 子类、`GetVerbCount` / `GetVerb` / `ExecuteVerb`，由 `RegisterComponentEditors` 注册）；设计期的文件对话框用 LCL 的 `TOpenDialog`（`designtime/tyControls.Design.PropEditors.pas:590-597`），提示用 `TyMessageDlg`；多选一用 LCL 的 `InputCombo`（`lcl:dialogs.pp:1031`）。终端目前没有组件编辑器。

**JSON 与转义**

12. `fpjson` 在 `fpc:packages/fcl-json/src/`；`TJSONParser.Create(const Source: RawByteString; AOptions: TJSONOptions)`（`jsonreader.pp:65`）。选项：`joComments`（`jsonscanner.pp:498-540`，`//` 与 `/* */`）、`joIgnoreTrailingComma`（`jsonreader.pp:372`、`:400`）、重复键默认抛（`jsonparser.pp:132`）。
13. `TyDecodeUnicodeEscapes`（`source/tyControls.AdvChart.Option.pas:209-310`）在**实现部分**、没导出。它按引号跟踪「在不在串里」但**不认注释**；它把 `\u0022`、`\u005C` 和控制字符也解成裸字符（裸的 `"` 会提前结束字符串）。终端这份（Task 1）要认注释、这几类保留成转义。AdvChart 那份的两处问题不在本期范围，签收时列进「计划外发现」。
14. WT 的 `defaults.json`（`microsoft/terminal` `main`，commit `4e2b8bd9`，`src/cascadia/TerminalSettingsModel/defaults.json`，36805 字节，MIT）：`schemes` 16 套，依次 Dimidium、Ottosson、Campbell、Campbell Powershell、Vintage、One Half Dark、One Half Light、Solarized Dark、Solarized Light、Tango Dark、Tango Light、Dark+、VSCode Dark Modern、VSCode Light Modern、CGA、IBM 5153；CRLF；`//` 注释（第 80 行 `//   - "foreground"`，注释里有引号）；两处尾逗号；第 16 行 `"wordDelimiters": " /\\()\"'-.,:;<>~!@#$%^&*|+=[]{}~?│"`（串里有 `\"`、单引号和一个 `\u` 转义）；第 42 行 `"ms-appx:///ProfileIcons/…"`（串里有 `//`）。正好是预解码三种陷阱的真实样本。Campbell 没有 `selectionBackground`（读入时按 WT 补 `#FFFFFF`）。

**示例与守卫**

15. 示例：`examples/terminal/umain.pas` 用 `TTyOpenDialog`（`:98`）；第四行工具栏 `Tools4`（`umain.lfm:279-`）放着复制即选、网址、OSC 52、最低对比度；`RecordingsDir`（`umain.pas:190-203`）从 exe 往上找 `recordings/`——`colorschemes/` 照这个找法。标题栏里有换肤下拉 `ThemeCombo` 和暗色开关 `DarkSwitch`（`:60-62`、`:292-310`）。
16. 发版守卫（`tests/test.release.pas`）：`TheThirdPartyNoticeCoversTheTerminalPort`、`TheExampleRecordingsMatchTheOracle`（示例资源随包、无 `\u0000`）、`EveryUnitOnDiskIsListedInItsPackage`（新单元漏进 `.lpk` 会红，[[new-unit-missing-from-lpk]]）。
17. 终端的 `resourcestring` 在 `source/tyControls.StrConsts.pas:263-266`，`.po` 在 `languages/tycontrols.strconsts.{en,zh_CN}.po`。

---

## 开工前要定的问题

每条都给了建议，**计划正文按建议写**；改了哪条，执行时改对应任务，收尾时（Task 10）写回 spec §11.1 原处。第一类由主控在 Task 0 问用户；用户没回复前按建议做（和 3–5 期一样，一起验收时仍可改）。用户 2026-09-30 已定的七条（spec §11.1.1）不在这里重问。

### 一、产品方向 / 用户可见（问用户）

> **状态（2026-09-30）**：用户说「继续」，四条先按建议执行（`ColorSource` 两值 + `ColorSchemePaired` + `DarkColorScheme`；做设计器右键导入/导出，可改 `designtime/tyControls.Design.CompEditors.pas`；示例带七套加三对明暗；链接下划线跟主题、组字串底色/字色用方案），已告知用户，最终一次性验收时可改。第二类主控按建议采纳。

> **状态**：（Task 0 填：用户对下面四条的答复；没答复就写「未答复，按建议执行，验收时可改」。）

1. **「明暗各一套」在属性上长什么样？**
   - **A（建议）**：`ColorSource`（跟随主题 / 自定义方案）照你定的两个值；另加开关 `ColorSchemePaired`（默认关）和第二个方案对象 `DarkColorScheme`。开关关着时一直用 `ColorScheme`；开着时浅色主题用 `ColorScheme`、深色主题用 `DarkColorScheme`。对象查看器里一眼看得出现在是不是配对。
   - B：`ColorSource` 做成三个值（跟随主题 / 一套方案 / 明暗两套），不要开关。少一个属性，但和你定的「两个值」不一样。
   - C：不要开关，`DarkColorScheme` 里有颜色就算配对。最省事，但清空一个颜色就可能改变行为，不建议。
2. **设计器里要不要「导入 / 导出 Windows Terminal 配色…」的右键菜单？**
   对象查看器本来就能一格一格改 22 个颜色；没有导入的话，想在设计器里用一套现成的方案得手抄 22 个色值。
   **建议做**（Task 7）：右键终端 →「导入 Windows Terminal 配色…」选文件，一套就直接进、多套先选名字；配对开着时再问写进浅色还是深色那套；「导出…」写成一个 WT 方案文件。要改 `designtime/tyControls.Design.CompEditors.pas`（全库设计期共用的一个文件，只加终端的一个编辑器类和注册一行）。选「不做」则 Task 7 跳过。
3. **示例带哪几套？**
   **建议**：Windows Terminal 自带的七套——Campbell、One Half Dark、One Half Light、Solarized Dark、Solarized Light、Tango Dark、Tango Light——原样取自 WT 的 `defaults.json`（MIT）；下拉里另有三对明暗（One Half、Solarized、Tango）演示随暗色开关自动换。许可：WT 是 MIT（Microsoft）；Solarized 原作 MIT（Ethan Schoonover）；One Half 原作 MIT（Son A. Pham）；Tango 调色板在公有领域。notices 加一节。
   不带 iTerm2-Color-Schemes 里的：那个仓库的 MIT 只管「这个集合」，它自己写明单套方案的版权归各作者——要一套一套查。文档里告诉用户那里的 `windowsterminal/` 目录可以直接「导入…」。
   另外两种做法：WT 自带的 16 套全带（多出来的 Dimidium、Ottosson、Campbell Powershell、Vintage、Dark+、VSCode Dark / Light Modern、CGA、IBM 5153 同样在 WT 的 MIT 文件里）；或者只带我们自己按公开色值配的两三套。
4. **自定义方案下，链接下划线和组字串用什么颜色？**
   方案里没有这两项（WT 也没有）。**建议**：链接下划线照旧取主题的 `TyTerminalLink`（和外框、滚动条一样跟主题）；组字串的底色 / 字色改用方案的背景 / 前景（不然会在方案的底上出现一块主题色），下划线仍取主题。另一种做法：链接下划线也改用方案的前景。

### 二、实现层面（主控定）

1. **新单元** `source/tyControls.Terminal.ColorScheme.pas`，进运行时包 `tycontrols.lpk`。依赖 `SysUtils`、`Classes`、`Graphics`（只为 `TColor` / `clNone` / `clDefault` / `ColorToRGB`）、`fpjson`、`jsonparser`、`jsonscanner`、`tyControls.StrConsts`；不引 `Controls` / `Forms` / 控件单元。自己写的，不进 notices 的 xterm.js 标题；单元头注明语义照 `xterm:src/browser/services/ThemeService.ts:81-131`、格式照 WT `ColorScheme.cpp`。
2. **「未设置」= `clNone`**；`clDefault` 当未设置；系统色（`clWindow` 这类，高位 `$80`）经 `ColorToRGB` 解成 RGB。TColor（`$00BBGGRR`）与色表（`$RRGGBB`）只在两个函数里换（`TyTermSchemeColorRgb` / `TyTermRgbToSchemeColor`）。
3. **`\u` 预解码**：终端自带 `TyTermJsonDecodeEscapes`（接口里公开，给测试）——认 `//` 与 `/* */` 注释（注释原样拷、里面的引号不算）；只在字符串里解；`\u0022` 写回 `\"`、`\u005C` 写回 `\\`、`< U+0020` 的保留原转义；代理对合并，孤立代理出 U+FFFD；`\\u` 是字面的反斜杠加 u。不改 AdvChart 那份（核实记录 13）。
4. **读入缺 `foreground` / `background` / `cursorColor` / `selectionBackground` 时按 WT 的缺省补**（`#FFFFFF` / `#000000` / `#FFFFFF` / `#FFFFFF`，WT `ColorScheme.h` 的默认值）：读进来的方案和它在 WT 里一样完整，写出时 WT 的 `ToJson` 本来也四个都写。另一种做法是留空、跟主题——那样同一个文件在 WT 和这里颜色不同，不取。
5. **重复键报错**：用 `fpjson` 的默认（抛），转成我们的错误。jsoncpp 是后者为准；要照它得自己走一遍语法树，不值得（spec §11.1.10）。
6. **按名取**：`schemes` 里按顺序，`name` 逐字相等、16 色齐的**第一个**（WT 的 `emplace` 不覆盖）；只校验选中的那一套。
7. **明暗判定**：`TyLuminance(本实例跟随主题时的底色) > 0.5` 为浅（核实记录 7）。不读 `--ty-mode`、不看 `Model.Mode`：单模式的深色皮肤、用户调深的 `--terminal-bg` 都该算深。
8. **缓存键与通知**：`EnsurePalette` 的键加 `ColorSource`、`ColorSchemePaired`、**选中那一边**的方案修订号（`Revision`，每次 `OnChange` 加一）；选哪边由主题决定、已含在 `ThemeVersion` / 类 / 覆盖里，所以另一边的方案改了不失效、不重画。通知仍只在 `EnsureThemeCurrent`、逐项比。`EnsureThemeCurrent` 的「和上次通知时同一把键就退出」那一句跟着加这三项（地雷 4）。
9. **选区的 0.3**：方案设了选区色时 `FSelBg := TTyColor(($4D shl 24) or rgb)`（xterm `color.opacity(…, 0.3)` 的 alpha = `Math.round(0.3 × 255)` = 77 = `$4D`），之后照旧 `TyTermBlendOver(FPalette[257], …)`——`FPalette[257]` 这时就是方案的底色。
10. **加载中**：`csLoading` 时方案的 `OnChange` 只记修订号，不 `Invalidate`、不建色表；`Loaded` 里什么都不写回 published 字段（[[loaded-sync-clobbers-streamed-values]]）。
11. **写出格式**：键顺序照 WT `ToJson`；`#RRGGBB` 大写；四空格缩进、`LF`、末尾一个换行；前四个可选项未设置的不写；16 色缺或名字空报错。
12. **同一次消息处理里的几次改动只通知一次**：示例切「一对」要装两套方案、开配对、改来源，宿主代码也常这样连着设。今天的 `Invalidate`（`Terminal.pas:1413-1423`）当场 `EnsureThemeCurrent`，连着设四项就可能通知两三次（每次都清 OSC 覆盖、发一条 2031）。做法：`ColorSource` / `ColorSchemePaired` 的 setter 和方案的 `OnChange` **不调 `Invalidate`**，只排一次 `QueueAsyncCall`（复用 `FNotifyQueued` / `AsyncNotifyScheme`，`:1161-1166`），回调里 `EnsureThemeCurrent` 再 `Invalidate`。读色表的路径不受影响：Core 问颜色时 `CoreQueryColor` 先 `EnsurePalette`（`:958`），所以改完当场 `ResolveColor`、996 都是新方案的——只有「清 OSC 覆盖、发 2031」这一步挪到消息循环里。其他路径（主题广播、绘制）先走到 `EnsureThemeCurrent` 也没关系：它通知一次，回调来时逐项比已经相同、不再通知。
13. **测试单元**：新 `tests/test.terminal.colorscheme.pas`（suite `TTyTerminalColorSchemeTests`，纯逻辑）、`tests/test.terminal.view.scheme.pas`（suite `TTyTerminalViewSchemeTests`，控件）；夹具 `tests/fixtures/terminal-wt-defaults.json`（WT 原文件逐字节，含 CRLF——`.gitattributes` 里给它 `-text`，否则 autocrlf 会动它）。

---

## 需要改共享文件的地方

**结论：四个共享文件不改。** 另有两个全库共用的文件要加东西，列在这里：

| 文件 | 为什么 | 本期怎么做 |
|---|---|---|
| `source/tyControls.StrConsts.pas` | 读写方案的错误消息要 `resourcestring`、进 `.po` | 加一段「TTyTerminalColorScheme」，照 `rsTerminalMenuClear` 的先例（Task 3、4）；同步 `languages/tycontrols.strconsts.{en,zh_CN}.po` 与 `.pot` |
| `designtime/tyControls.Design.CompEditors.pas` | 设计器右键导入 / 导出 | 只在开工前问题一第 2 条用户同意时（Task 7）：加一个 `TTyTerminalViewComponentEditor`、注册一行 |
| `Base.pas` / `Painter.pas` / `StyleModel.pas` / `TextMenu.pas` | — | 不涉及。明暗判定用 `Css.Values` 已公开的 `TyLuminance`，不改 `StyleModel` |

**会改的终端文件**：新 `Terminal.ColorScheme.pas`（Task 1–4）；`Terminal.pas`（Task 5、6）；`tycontrols.lpk` 的文件清单（Task 1）；示例 `umain.pas` / `umain.lfm` / `languages/*` / 新目录 `colorschemes/`（Task 8）。Core、Render、Buffer 等都不改。

---

## 接口清单（全计划用这一套名字）

### `source/tyControls.Terminal.ColorScheme.pas`（新）

```pascal
type
  { 前 16 个的序号就是 ANSI 号 }
  TTyTerminalSchemeSlot = (
    tssBlack, tssRed, tssGreen, tssYellow, tssBlue, tssPurple, tssCyan, tssWhite,
    tssBrightBlack, tssBrightRed, tssBrightGreen, tssBrightYellow,
    tssBrightBlue, tssBrightPurple, tssBrightCyan, tssBrightWhite,
    tssForeground, tssBackground, tssCursor, tssCursorText,
    tssSelection, tssSelectionInactive);

  TTyTerminalColorSchemeFormat = (tcfAuto, tcfWindowsTerminal);

  ETyTerminalColorSchemeError = class(Exception)
  private
    FKey: string;
  public
    constructor CreateKey(const AKey, AMessage: string);
    property Key: string read FKey;     { 出错的 JSON 键；'' = 整段文本或整套 }
  end;

  TTyTerminalColorScheme = class(TPersistent)
  private
    FOwner: TPersistent;
    FName: string;
    FColors: array[TTyTerminalSchemeSlot] of TColor;
    FRevision: Cardinal;
    FUpdateCount: Integer;
    FChangePending: Boolean;
    FOnChange: TNotifyEvent;
    function GetColor(ASlot: TTyTerminalSchemeSlot): TColor;
    procedure SetColor(ASlot: TTyTerminalSchemeSlot; AValue: TColor);
    function GetSlotColor(AIndex: Integer): TColor;           { published 属性的 index 读 }
    procedure SetSlotColor(AIndex: Integer; AValue: TColor);  { published 属性的 index 写 }
    procedure SetName(const AValue: string);
    procedure Changed;
  protected
    function GetOwner: TPersistent; override;
  public
    constructor Create(AOwner: TPersistent = nil);
    procedure Assign(ASource: TPersistent); override;
    function Equals(AObj: TObject): Boolean; override;
    procedure Clear;                                          { 全部 clNone、Name ''；有变化才发 OnChange }
    function IsEmpty: Boolean;                                { 22 色都未设置（Name 不算） }
    procedure BeginUpdate;
    procedure EndUpdate;                                      { 期间有改动则只发一次 OnChange }
    { 这一槽设了没有、设了是什么 RGB（$RRGGBB；系统色经 ColorToRGB） }
    function SlotRgb(ASlot: TTyTerminalSchemeSlot; out ARgb: Cardinal): Boolean;
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
    class function ListSchemeNames(const AText: string;
      AFormat: TTyTerminalColorSchemeFormat = tcfAuto): TStringArray;
    property Colors[ASlot: TTyTerminalSchemeSlot]: TColor read GetColor write SetColor;
    property Revision: Cardinal read FRevision;               { 每次 OnChange 加一（纯查询） }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  published
    property Name: string read FName write SetName;           { '' 不写进 .lfm（string 的默认就是不存空串） }
    property Foreground: TColor index Ord(tssForeground) read GetSlotColor write SetSlotColor default clNone;
    property Background: TColor index Ord(tssBackground) read GetSlotColor write SetSlotColor default clNone;
    property CursorColor: TColor index Ord(tssCursor) read GetSlotColor write SetSlotColor default clNone;
    property CursorText: TColor index Ord(tssCursorText) read GetSlotColor write SetSlotColor default clNone;
    property SelectionBackground: TColor index Ord(tssSelection) read GetSlotColor write SetSlotColor default clNone;
    property SelectionInactiveBackground: TColor index Ord(tssSelectionInactive) read GetSlotColor write SetSlotColor default clNone;
    property Black: TColor index Ord(tssBlack) read GetSlotColor write SetSlotColor default clNone;
    { … Red、Green、Yellow、Blue、Purple、Cyan、White、BrightBlack … BrightWhite 同样写法，共 16 个 }
  end;

{ 纯函数（测试直接调） }
{ '#rgb' 或 '#rrggbb'，大小写不限，前后不许空白；别的一律 False }
function TyTermParseSchemeColor(const AText: string; out ARgb: Cardinal): Boolean;
{ $RRGGBB → '#RRGGBB'（大写） }
function TyTermSchemeColorText(ARgb: Cardinal): string;
{ TColor → $RRGGBB；clNone / clDefault 答 False；系统色经 ColorToRGB }
function TyTermSchemeColorRgb(AColor: TColor; out ARgb: Cardinal): Boolean;
{ $RRGGBB → TColor（$00BBGGRR） }
function TyTermRgbToSchemeColor(ARgb: Cardinal): TColor;
{ fpjson 之前：字符串里的 \u 转义解成 UTF-8（认注释；" \ 与控制字符保留成转义） }
function TyTermJsonDecodeEscapes(const AText: string): string;
{ WT 的键名（16 色与四个可选项；CursorText / SelectionInactive 答 ''） }
function TyTermWtSchemeKey(ASlot: TTyTerminalSchemeSlot): string;
```

`TyTermWtSchemeKey`：`black red green yellow blue purple cyan white brightBlack brightRed brightGreen brightYellow brightBlue brightPurple brightCyan brightWhite foreground background cursorColor ''（CursorText） selectionBackground ''（SelectionInactive）`。

### `source/tyControls.Terminal.pas`（改）

```pascal
type
  TTyTerminalColorSource = (tsrcTheme, tsrcScheme);

  TTyTerminalView = class(...)
  private
    FColorSource: TTyTerminalColorSource;
    FColorScheme, FDarkColorScheme: TTyTerminalColorScheme;
    FColorSchemePaired: Boolean;
    { 色表缓存键新增的三项 + 选了哪一边 }
    FPaletteSource: TTyTerminalColorSource;
    FPalettePaired, FPaletteDarkSide: Boolean;
    FPaletteSchemeRev: Cardinal;
    { EnsureThemeCurrent 的「上次通知」键同样加这四项 }
    FNotifiedSource: TTyTerminalColorSource;
    FNotifiedPaired, FNotifiedDarkSide: Boolean;
    FNotifiedSchemeRev: Cardinal;
    procedure SetColorSource(AValue: TTyTerminalColorSource);
    procedure SetColorScheme(AValue: TTyTerminalColorScheme);        { Assign }
    procedure SetDarkColorScheme(AValue: TTyTerminalColorScheme);    { Assign }
    procedure SetColorSchemePaired(AValue: Boolean);
    procedure SchemeChanged(Sender: TObject);                         { 两个方案的 OnChange }
    procedure RequestSchemeNotify;                                    { 开工前问题二第 12 条 }
  protected
    { FOR THE TESTS（纯查询）：色表这一刻用的是哪套（nil = 跟随主题）、主题算不算深、
      有没有排着的通知、RequestSchemeNotify 真正排队过几次 }
    function ActiveColorScheme: TTyTerminalColorScheme;
    function ThemeGroundIsDark: Boolean;
    function NotifyQueued: Boolean;
    function SchemeNotifyRequests: Integer;
  published
    property ColorSource: TTyTerminalColorSource read FColorSource write SetColorSource default tsrcTheme;
    property ColorScheme: TTyTerminalColorScheme read FColorScheme write SetColorScheme;
    property ColorSchemePaired: Boolean read FColorSchemePaired write SetColorSchemePaired default False;
    property DarkColorScheme: TTyTerminalColorScheme read FDarkColorScheme write SetDarkColorScheme;
  end;
```

（开工前问题一第 1 条选了 B / C 的话，按那个形态改这四个属性，其余不变。）

---

## 文件清单

| 文件 | 本期做什么 |
|---|---|
| `source/tyControls.Terminal.ColorScheme.pas` | **新建**（Task 1–4） |
| `tycontrols.lpk` | 文件清单加新单元（Task 1） |
| `source/tyControls.StrConsts.pas`、`languages/tyControls.StrConsts.pot`、`languages/tycontrols.strconsts.{en,zh_CN}.po` | 加错误消息（Task 3、4） |
| `source/tyControls.Terminal.pas` | 四个属性、`EnsurePalette` / `EnsureThemeCurrent` / `PaintPreedit` 接线（Task 5、6） |
| `tests/test.terminal.colorscheme.pas` | **新建**（Task 1–4：suite `TTyTerminalColorSchemeTests`） |
| `tests/test.terminal.view.scheme.pas` | **新建**（Task 5、6：suite `TTyTerminalViewSchemeTests`） |
| `tests/test.terminal.view.pas` | RTTI 守卫扩到子对象、流式往返加方案（Task 5） |
| `tests/tytests.lpr` | uses 加两个测试单元 |
| `tests/fixtures/terminal-wt-defaults.json`、`.gitattributes` | **新建** / 加一行 `-text`（Task 3） |
| `designtime/tyControls.Design.CompEditors.pas`、`languages/tyControls.Design.CompEditors.pot`、`languages/tycontrols.design.compeditors.zh_CN.po` | 有条件（Task 7） |
| `examples/terminal/colorschemes/windows-terminal.json` | **新建**（Task 8） |
| `examples/terminal/umain.pas`、`umain.lfm`、`languages/terminal_example.zh_CN.json`（`.po` 由主控生成） | 改（Task 8） |
| `tests/test.terminal.example.pas` | 加示例的方案测试（Task 8） |
| `docs/controls/terminal.md`、`README.md`、`README.en.md`、`THIRD-PARTY-NOTICES.md`、`tests/test.release.pas`、`tools/terminal-shots/terminalshots.lpr` | 改（Task 9） |
| `docs/superpowers/plans/2026-09-30-terminal-phase-6-shots/` | **新建**（Task 10 主控） |
| `docs/superpowers/specs/2026-09-28-terminal-view-design.md` | 只在 Task 10 写回 |
| `docs/superpowers/plans/2026-09-29-terminal-acceptance.md` | Task 11 更新 |

**不碰**：四个共享文件、Core / Parser / Buffer / Render / Keyboard / Selection / Links 单元、主题文件、`CHANGELOG*`、`source/tyControls.AdvChart.Option.pas`（它的预解码问题记进签收的「计划外发现」）。

---

## 实现期的地雷（每个任务开工前看一眼）

1. **`clNone` 不是 0**（[[zero-value-must-be-the-safe-answer]]）：构造里 22 色全部设 `clNone`，`FillChar` / `Default()` 出来的是黑色。published `default clNone` 必须等于构造值（[[tabstop-declared-default-must-match]]），RTTI 守卫要走进子对象。
2. **字节序**：TColor 是 `$00BBGGRR`，色表、WT 的 `#RRGGBB`、`TyTermBlendOver` 都是 `$RRGGBB`。换算只在 `TyTermSchemeColorRgb` / `TyTermRgbToSchemeColor`；测试的色值选 R ≠ B 的（`$C50F1F`），对称色（`$808080`）测不出换反。
3. **对象属性要有 setter 才流式化**（核实记录 9）：`ColorScheme` / `DarkColorScheme` 的 setter 是 `Assign`，不是替换指针；`GetOwner` 答控件。
4. **两把键**：`EnsurePalette` 的缓存键和 `EnsureThemeCurrent` 的「上次通知」键是两处（`Terminal.pas:1257-1259`、`:1332-1334`），只加了前一处，方案变了色表会重建、但 `EnsureThemeCurrent` 在第一句就退出——不通知、不重画（[[built-not-wired-is-the-default-failure]]）。
5. **另一边的方案改了不算**：键里只放选中那一边的修订号；放两边的话，配对时改深色那套会让浅色主题下的终端整屏重画（不错，但白画），更糟的是 `ColorSource = tsrcTheme` 时改方案也会重画。
6. **判明暗要用主题的底，不用方案的底**：`ThemeGroundIsDark` 在「跟随主题」的算法里取 `instBg`，不能读 `FPalette[257]`（那是方案的）——否则深色方案会把自己判成深主题、配对永远选深色那边。
7. **`csLoading`**：`.lfm` 里的子属性一项项流进来，每项都发 `OnChange`；加载中建色表会用半套方案、`FNotifiedValid` 变 True，加载完第一次真正建表就会被当成「变了」去清 OSC 覆盖、发 2031（地雷 4 的另一面）。加载中只记修订号。
8. **读入必须原子**：解析进一个临时方案，成功才 `Assign`；失败不发 `OnChange`、不动 `Revision`。
9. **`fpjson` 的两个坑**：两个 `\u` 挨着丢字节（先预解码）；`\u0000` 被吞（名字里出现就认了，记为限制，[[fpjson-drops-u0000]]）。预解码不能碰注释、不能把 `\u0022` 解成裸引号。含 `\u`、`\x1b`、反斜杠的测试数据用 Write 工具落文件，不用 heredoc（[[bash-heredoc-eats-backslashes]]）；改 `.pas` 用编辑工具，不用 Git Bash 的 `sed -i`（[[git-bash-sed-strips-crlf]]）。
10. **夹具字节不能变**：`terminal-wt-defaults.json` 要逐字节等于上游（CRLF 是它的一部分）；`.gitattributes` 给 `-text`，提交后 `git show HEAD:… | wc -c` = 36805。
11. **系统色**：`ColorToRGB(clWindow)` 要 widgetset；测试进程有。系统色变了不会让 `ThemeVersion` 变，色表不会自己刷新——记为限制，不做监听。
12. **示例规矩**（[[examples-must-be-lfm-titlebar-skin]]、[[demo-edits-lfm-not-code]]、[[no-native-controls-in-ui]]、[[skin-variance-breaks-fixed-widths]]、[[lcl-code-created-align-order]]）：新下拉、按钮写进 `.lfm`、`AutoSize`、库控件；英文标题同步 `.po` 的 msgid（[[example-english-caption-fit]]）；`.po` 新条目 msgstr 不能空（[[empty-po-entry-blocks-startup]]）。
13. **单跑绿 / 全量红** 先 `lazbuild -B` 重编（[[canary-then-rebuild]]），再查进程级状态（[[suite-order-widgetset-init]]）；期末变异先 `git diff --stat` 确认改到了（[[crlf-mutation-phantom-survivor]]）。
14. **测试钉死了旧行为**（[[tests-that-pin-the-bug]]）：3–5 期的主题测试钉着「色表只来自主题」。`ColorSource` 默认是跟随主题，它们应当一条不改就绿；有哪条要改，先停下查是不是把默认值改了。

---

## 跑测试的固定套路（只在 Task 10 跑）

改了 `source/` 之后**必须** `lazbuild -B`。exe 用唯一名 `tytests-term.exe`。

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi > /tmp/term-build.txt 2>&1 || { tail -30 /tmp/term-build.txt; false; } && cd tests && cp tytests.exe tytests-term.exe && for s in $SUITES; do ./tytests-term.exe --suite=$s --format=plain > /tmp/term-$s.txt 2>&1; printf '%s: ' $s; grep -E "Number of (run tests|errors|failures)" /tmp/term-$s.txt | tr '\n' ' '; echo; done
```

`SUITES` = `TTyTerminalColorSchemeTests TTyTerminalViewSchemeTests TTyTerminalViewTests TTyTerminalViewThemeTests TTyTerminalViewPaintTests TTyTerminalViewInputTests TTyTerminalExampleTests TReleaseManifestTest TI18NTest`

**判据是每个 suite 那一行都有 `Number of run tests`、errors / failures 为 0**，不是 exit code。某一行为空 = 跑丢了，重跑，别读成通过。

全量（输出必须重定向到文件，[[known-rare-suite-flake]]）：

```bash
cd /d/Projects/ty-3.1/tests && ./tytests-term.exe --all --format=plain > /tmp/term-all.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/term-all.txt
```

---

## 关于判据和变异

- 纯函数给**输入 / 期望表**；控件、像素、事件测试写**判据**（比什么、怎么数、失败打印什么），测试代码执行时现写（[[plan-tests-write-the-mutation-not-the-code]]）。
- 每条判据写明「**在哪个变异下必须红**」；变异期末集中做（Task 10 Step 6）：改一行 → `git diff --stat` 确认改到了 → `lazbuild -B` → 跑相关 suite → **必须红** → 改回 → 重编重跑 → 绿。没红的先查改没改对地方、再查是不是「这条路走不到」；确实没红，当场补测试，签收记录写一句。
- 接线类变异（事件没挂、键没加、通知没调、`Invalidate` 没调）每类至少一条（[[built-not-wired-is-the-default-failure]]）。
- 断言里那个量要真的变过（[[assertion-never-varies-the-thing]]）：方案色和主题色必须不同、浅色主题配深色方案、R ≠ B；「没通知」的断言之前先证明同一个动作在另一种设置下**会**通知。
- 标「等价」的变异不做，理由写在表里。卡住时按进程号结束 `tytests-term.exe`，**禁用 `taskkill -im`**（[[parallel-agent-worktree-hazards]]）。

---

### Task 0: 基线、问用户

**Files:** 无（只记数）

- [ ] **Step 1: 【主控执行】问用户开工前问题一的四条**，把答复写进「开工前要定的问题 · 一」开头的「状态」引用块（格式照 5 期计划）；用户没回复就按建议开工，告诉用户「一起验收时可改」。第 2 条选「不做」则 Task 7 跳过；第 1 条选 B / C 则按接口清单末尾那句改。

- [ ] **Step 2: 确认起点**

```bash
cd /d/Projects/ty-3.1 && git status --short && git branch --show-current && git log --oneline -1 && git log --oneline feat/terminal..main | wc -l
```

Expected：工作区干净，分支 `feat/terminal`，HEAD 是本计划的提交或其后；`main` 没有新提交（有的话停下交主控：要不要先合）。

- [ ] **Step 3: 基线编译并跑全量**（实现 agent 做）：「跑测试的固定套路」的全量命令。条数记进草稿（5 期签收 8360，唯一的红是 `TPainterTest.TestTextIsInkedAsWindowsInksIt`），Task 10 签收时写进本计划末尾。**有别的红就停。**

- [ ] **Step 4: 取夹具**：从 `https://raw.githubusercontent.com/microsoft/terminal/4e2b8bd9264642475d1398c11a5fd2aba06f373e/src/cascadia/TerminalSettingsModel/defaults.json` 取到草稿目录，确认 36805 字节、CRLF、`schemes` 16 套（核实记录 14）。和 WT 许可原文 `…/4e2b8bd9…/LICENSE` 一起留着，Task 3、8、9 用。

---

### Task 1: 单元骨架、颜色串、转义预解码

**Files:**
- Create: `source/tyControls.Terminal.ColorScheme.pas`（本任务只放类型声明、五个纯函数；类的方法体留给 Task 2–4，声明先全写上、方法体暂为 `raise ENotImplemented`——Task 4 结束时不许再有）
- Modify: `tycontrols.lpk`（照 `tyControls.Terminal.Links.pas` 那一项加 `<Item>`）
- Create: `tests/test.terminal.colorscheme.pas`（suite `TTyTerminalColorSchemeTests`，`RegisterTest`）
- Modify: `tests/tytests.lpr`（uses 加 `test.terminal.colorscheme`）

- [ ] **Step 1: 单元头**：一段中文说明（这是什么、未设置 = `clNone`、优先级在控件里、语义出处 `xterm:src/browser/services/ThemeService.ts:81-131`、格式出处 WT `ColorScheme.cpp` / `JsonUtils.h` 与文档 URL、`fpjson` 的两个坑为什么要预解码）。`uses` 照开工前问题二第 1 条。

- [ ] **Step 2: `TyTermParseSchemeColor`**：长度 4 或 7、首字符 `#`、其余全是 `0-9a-fA-F`；4 位时每位重复（`#1a2` → `$11AA22`）。别的一律 False、`ARgb := 0`。

- [ ] **Step 3: `TyTermSchemeColorText`、`TyTermSchemeColorRgb`、`TyTermRgbToSchemeColor`、`TyTermWtSchemeKey`**

```pascal
function TyTermSchemeColorRgb(AColor: TColor; out ARgb: Cardinal): Boolean;
var
  c: TColor;
begin
  ARgb := 0;
  if (AColor = clNone) or (AColor = clDefault) then Exit(False);
  c := ColorToRGB(AColor);            { 系统色（高位 $80）解成 RGB；普通色原样 }
  ARgb := (Cardinal(c) and $FF) shl 16 or (Cardinal(c) and $FF00) or ((Cardinal(c) shr 16) and $FF);
  Result := True;
end;

function TyTermRgbToSchemeColor(ARgb: Cardinal): TColor;
begin
  Result := TColor(((ARgb and $FF) shl 16) or (ARgb and $FF00) or ((ARgb shr 16) and $FF));
end;
```

- [ ] **Step 4: `TyTermJsonDecodeEscapes`**：从 `AdvChart.Option.pas:209-310` 的结构出发重写（不引那个单元），改三处：（a）不在串里时遇到 `//` 拷到行尾、遇到 `/*` 拷到 `*/`（没收尾就拷到末尾，让解析器报错）；（b）解出的码位是 `"` 时写 `\"`、是 `\` 时写 `\\`、小于 `$20` 时原样拷那 6 个字符；（c）单引号串照 AdvChart 也认（`jsonscanner` 非严格模式收单引号），双引号串里的单引号不算、单引号串里的双引号不算。

- [ ] **Step 5: 测试（输入 / 期望表）**

`TyTermParseSchemeColor`：

| 输入 | 结果 | RGB |
|---|---|---|
| `#C50F1F` | True | `$C50F1F` |
| `#c50f1f` | True | `$C50F1F` |
| `#0C0C0C` | True | `$0C0C0C` |
| `#fff` | True | `$FFFFFF` |
| `#1a2` | True | `$11AA22` |
| `#000` | True | `$000000` |
| `#C50F1FFF`（8 位） | False | — |
| `#C50F1`（5 位） | False | — |
| `C50F1F` | False | — |
| `#12345g` | False | —（WT 的 `stoul` 会当 `05`，我们严格） |
| `' #123456'`、`'#123456 '` | False | — |
| `''`、`'#'` | False | — |
| `rgb(1,2,3)`、`red` | False | — |
| `#ＦＦＦ`（全角） | False | — |

`TyTermSchemeColorText`：`$C50F1F` → `#C50F1F`；`0` → `#000000`；`$ABCDEF` → `#ABCDEF`（大写）。

`TyTermSchemeColorRgb` / `TyTermRgbToSchemeColor`：`TColor($1F0FC5)` → True、`$C50F1F`；`$C50F1F` → `TColor($1F0FC5)`；`clNone`、`clDefault` → False；`clBlack` → True、0；`clWindow` → True、等于 `ColorToRGB(clWindow)` 换字节序后的值；往返 `$C50F1F` → TColor → `$C50F1F`。

`TyTermJsonDecodeEscapes`（左边是源文本，JSON 里的反斜杠按字面）：

| 输入 | 输出 |
|---|---|
| `{"n":"\u4e2d\u6587"}` | `{"n":"中文"}`（UTF-8） |
| `{"n":"a\u0022b"}` | `{"n":"a\"b"}` |
| `{"n":"a\u005cb"}` | `{"n":"a\\b"}` |
| `{"n":"a\u0001b"}` | 原样 |
| `{"n":"\\u4e2d"}` | 原样（字面反斜杠加 u） |
| `{"n":"\ud83d\ude00"}` | `{"n":"😀"}` |
| `{"n":"\ud83d"}`、`{"n":"\ude00"}` | `{"n":"�"}`（U+FFFD） |
| `{"n":"\u12"}` | 原样（留给解析器） |
| `// it's "x" \u4e2d` + 换行 + `{"n":"\u4e2d\u6587"}` | 注释原样（里面的 `\u4e2d` 也不动）、串解开 |
| `/* "x */ {"n":"\u00e9\u00e8"}` | 注释原样、串解开 |
| `{"u":"ms-appx:///P","n":"\u4e2d\u6587"}` | 串里的 `//` 不是注释，`n` 照样解开 |
| `{"w":" /\\()\"'-.,:;<>~?\u2502","n":"\u4e2d\u6587"}`（WT `defaults.json` 第 16 行的形状） | `\"` 与单引号不改变「在串里」，两处 `\u` 都解开 |

再加一条集成判据：上表每一行（能解析的）预解码后交 `TJSONParser`（`joUTF8`、`joComments`、`joIgnoreTrailingComma`）得到的 `n` 等于期望的 UTF-8 串。**变异 C1**：预解码去掉注释处理 → 第 9、10 行红。**C2**：`\u0022` 解成裸引号 → 第 2 行的集成判据红（解析失败）。**C3**：4 位颜色不重复位（`#1a2` → `$01A2`）→ 红。**C4**：`TyTermSchemeColorRgb` 不换字节序 → 红。**C5**：长度检查放宽到 9 → `#C50F1FFF` 那行红。

- [ ] **Step 6: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.ColorScheme.pas tycontrols.lpk tests/test.terminal.colorscheme.pas tests/tytests.lpr && git commit -m "feat(terminal): colour strings and escape pre-decoding for colour schemes

A new unit holds the colour scheme types. This first step parses and
writes Windows Terminal colour strings (#rgb and #rrggbb, nothing else),
converts between TColor and the palette's byte order in one place, and
decodes \\u escapes before fpjson sees them, skipping comments and keeping
quotes, backslashes and control characters escaped.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 方案对象

**Files:**
- Modify: `source/tyControls.Terminal.ColorScheme.pas`
- Modify: `tests/test.terminal.colorscheme.pas`

- [ ] **Step 1: 构造与基本方法**：构造设 22 色 `clNone`、`FOwner := AOwner`；`GetOwner` 答 `FOwner`。`SetColor` / `SetSlotColor` / `SetName` 值没变就不动，变了 `Changed`。`Changed`：`FUpdateCount > 0` 时只记 `FChangePending`；否则 `Inc(FRevision)`、发 `OnChange`。`BeginUpdate` / `EndUpdate` 嵌套计数，归零时有待发的就 `Changed` 一次。`Assign`（源是 `TTyTerminalColorScheme`）在 `BeginUpdate` / `EndUpdate` 里逐项拷，一样就不发；别的源 `inherited`。`Equals` 比 `Name` 与 22 色。`Clear` 同样包在一次更新里。`IsEmpty` 只看 22 色。`SlotRgb` 调 `TyTermSchemeColorRgb`。

- [ ] **Step 2: 测试（判据）**
  - 新建的方案 22 色都是 `clNone`、`Name = ''`、`IsEmpty`、`Revision = 0`。**变异 O1**：构造漏设一项（`CursorText` 留 0）→ 红。
  - RTTI：方案类的每个 `tkInteger` published 属性 `Default` = 构造后的值（22 项，断言个数 = 22）。**O2**：一个属性的 `default` 写成 `clBlack` → 红。
  - 改一色：`OnChange` 一次、`Revision` +1；再设同一个值：不发、不加。**O3**：去掉「值没变不动」→ 红。
  - `BeginUpdate` 里改三色、`EndUpdate`：一次；嵌套两层只在最外层发。**O4**：`EndUpdate` 每减一层都发 → 红。（签收注：按原意是「每减一层都直接加修订号、发 `OnChange`，绕过 `Changed`」，审查后照这个写法重做，见签收的变异表。）
  - `Assign`：结果 `Equals` 源、发一次；从相同的方案 `Assign`：不发。`Clear` 一个空方案：不发。
  - `SlotRgb`：设 `Red := TColor($1F0FC5)` → `$C50F1F`；未设置 → False。
  - `Colors[tssPurple]` 与 `Purple` 是同一格（设一个读另一个）。**O5**：`index` 写错一个（`Purple` 指到 `tssBlue`）→ 红。

- [ ] **Step 3: 提交**：`feat(terminal): the colour scheme object` + 两三行说明（未设置是 clNone、一次更新只发一次 OnChange、修订号给控件做缓存键）+ Co-Authored-By。

---

### Task 3: 读 Windows Terminal 的 JSON

**Files:**
- Modify: `source/tyControls.Terminal.ColorScheme.pas`、`source/tyControls.StrConsts.pas`、`languages/tyControls.StrConsts.pot`、`languages/tycontrols.strconsts.en.po`、`languages/tycontrols.strconsts.zh_CN.po`
- Create: `tests/fixtures/terminal-wt-defaults.json`（Task 0 取到的原文件，逐字节）
- Modify: `.gitattributes`（`tests/fixtures/terminal-wt-defaults.json -text`）
- Modify: `tests/test.terminal.colorscheme.pas`

- [ ] **Step 1: 错误消息**（`StrConsts.pas`，接在 `rsTerminalMenuClear` 那一段后，英文照下表，`.po` 的 zh_CN 一并写；msgstr 不许空）

| 名字 | 英文 | 中文 |
|---|---|---|
| `rsTermSchemeUtf16` | `UTF-16 text is not supported; save the file as UTF-8` | `不支持 UTF-16 文本，请把文件存成 UTF-8` |
| `rsTermSchemeBadJson` | `Not valid JSON: %s` | `不是合法的 JSON：%s` |
| `rsTermSchemeNotObject` | `Expected a colour scheme object or a settings file with "schemes"` | `需要一个配色方案对象，或带 "schemes" 的设置文件` |
| `rsTermSchemeSchemesNotArray` | `"schemes" is not an array` | `"schemes" 不是数组` |
| `rsTermSchemeNotFound` | `No colour scheme named "%s". Schemes in the text: %s` | `没有名为「%s」的配色方案。文本里有：%s` |
| `rsTermSchemeNeedName` | `The text has several colour schemes; choose one: %s` | `文本里有多套配色方案，请指定一个：%s` |
| `rsTermSchemeNoneValid` | `The text has no complete colour scheme (a name and all 16 colours)` | `文本里没有完整的配色方案（要有名字和全部 16 色）` |
| `rsTermSchemeMissingKeys` | `Missing colours: %s` | `缺少颜色：%s` |
| `rsTermSchemeBadColor` | `"%s" is not a colour (#rgb or #rrggbb): %s` | `「%s」不是颜色（#rgb 或 #rrggbb）：%s` |
| `rsTermSchemeNoName` | `The colour scheme has no name` | `配色方案没有名字` |

名字列表最多 20 个、用 `, ` 连，多了加 `…`。`rsTermSchemeNoName` 给 Task 4 用。

- [ ] **Step 2: `LoadFromText`**（`TryLoadFromText` 包一层 `try … except on E: Exception do AError := E.Message`）：
  1. 开头是 `EF BB BF` 去掉；是 `FF FE` 或 `FE FF` 报 `rsTermSchemeUtf16`。
  2. `TyTermJsonDecodeEscapes` → `TJSONParser.Create(…, [joUTF8, joComments, joIgnoreTrailingComma])` → `Parse`；异常转 `ETyTerminalColorSchemeError`（`rsTermSchemeBadJson`，带原消息的行列）。
  3. 顶层不是 `TJSONObject` → `rsTermSchemeNotObject`。
  4. 有 `schemes` 键：不是数组 → `rsTermSchemeSchemesNotArray`（`Key = 'schemes'`）。按顺序挑候选：是对象、`name` 是字符串、16 色的键齐（`purple` 缺看 `magenta`，`brightPurple` 缺看 `brightMagenta`；只看键在不在，值是什么类型都算在，格式留到第 6 步报）。`AName <> ''`：第一个 `name = AName` 的候选；没有 → `rsTermSchemeNotFound`（列候选名）。`AName = ''`：候选恰好一个取它；零个 → `rsTermSchemeNoneValid`；多个 → `rsTermSchemeNeedName`。
  5. 没有 `schemes` 键：整个对象就是方案；`AName <> ''` 且对象的 `name`（没有就是 `''`）不等于它 → `rsTermSchemeNotFound`。缺 16 色里的键 → `rsTermSchemeMissingKeys`（`Key` = 第一个缺的，消息列全部）。
  6. 读进临时方案：16 色、`foreground`、`background`、`cursorColor`、`selectionBackground` 逐个——不是字符串或 `TyTermParseSchemeColor` 失败 → `rsTermSchemeBadColor`（`Key` = 键名，消息带原值；非字符串写 JSON 形式）；四个可选项缺了按 WT 补 `$FFFFFF` / `$000000` / `$FFFFFF` / `$FFFFFF`；`purple` 在就用它、不在用 `magenta`；`CursorText`、`SelectionInactiveBackground` 留 `clNone`；`Name` = `name`（没有就 `''`）。
  7. 成功：`Assign(临时)`（一次 `OnChange`）。任何一步失败：本对象不动。
  8. `LoadFromFile` / `TryLoadFromFile`：`TFileStream` 整个读成 `RawByteString` 再走上面；文件异常 `LoadFromFile` 透传、`TryLoadFromFile` 转成 `AError`。`ListSchemeNames`：同第 1–4 步，返回每个是对象且 `name` 是字符串的项（不要求 16 色齐），单个对象返回它的 `name`（可能是 `''`）；解析失败返回空数组。
  9. `AFormat`：`tcfAuto` 与 `tcfWindowsTerminal` 走同一条；`case` 写全，以后加格式加分支。

- [ ] **Step 3: 测试（输入 / 期望表 + 判据）**

| # | 输入 | `AName` | 期望 |
|---|---|---|---|
| 1 | WT 文档里的 Campbell 示例（单个对象，文档原文） | `''` | 成功；`Name = 'Campbell'`；`Red = $C50F1F`、`Purple = $881798`、`BrightYellow = $F9F1A5`、`Background = $0C0C0C`、`Foreground = $CCCCCC`、`CursorColor = $FFFFFF`、`SelectionBackground = $FFFFFF`（RGB，经 `SlotRgb`） |
| 2 | 同上、`AName = 'Campbell'` | | 成功 |
| 3 | 同上、`AName = 'campbell'` | | `rsTermSchemeNotFound`（区分大小写） |
| 4 | 夹具 `terminal-wt-defaults.json` | `ListSchemeNames` | 16 个名字，顺序同核实记录 14 |
| 5 | 夹具 | `'Solarized Light'` | `Background = $FDF6E3`、`CursorColor = $002B36`、`SelectionBackground = $2C4D57`、`Purple = $D33682`、`BrightWhite = $FDF6E3` |
| 6 | 夹具 | `'Campbell'` | `SelectionBackground = $FFFFFF`（缺、按 WT 补） |
| 7 | 夹具 | `''` | `rsTermSchemeNeedName`，消息里有 `Campbell` |
| 8 | 夹具 | `'Nope'` | `rsTermSchemeNotFound` |
| 9 | 单个对象，16 色全、没有 `name` | `''` | 成功、`Name = ''`、前景按 WT 补 `$FFFFFF`、底 `$000000` |
| 10 | 单个对象，用 `magenta` / `brightMagenta` 代替 `purple` / `brightPurple` | `''` | 成功、`Purple` / `BrightPurple` = 那两色 |
| 11 | 单个对象，`purple` 和 `magenta` 都写、值不同 | `''` | 成功、`Purple` = `purple` 的 |
| 12 | 单个对象，缺 `brightCyan` | `''` | `rsTermSchemeMissingKeys`、`Key = 'brightCyan'` |
| 13 | 单个对象，`purple` + `magenta` 都写、缺 `red` | `''` | `rsTermSchemeMissingKeys`、`Key = 'red'`（WT 会数满 16，§11.1.10） |
| 14 | `"red": "#C50F1FFF"` | `''` | `rsTermSchemeBadColor`、`Key = 'red'`、消息含原值 |
| 15 | `"red": 12910623` | `''` | `rsTermSchemeBadColor`、`Key = 'red'` |
| 16 | `"red": null` | `''` | `rsTermSchemeBadColor` |
| 17 | `"cursorColor": "#12345g"` | `''` | `rsTermSchemeBadColor`、`Key = 'cursorColor'` |
| 18 | 多余的键 `"foo": 1`、`"cursorShape": "bar"` | `''` | 成功（不认识的键不管） |
| 19 | 两个 `"red"` | `''` | 报错（重复键） |
| 20 | 前面带 UTF-8 BOM 的 #1 | `''` | 成功 |
| 21 | 前面带 `FF FE` 的任意内容 | `''` | `rsTermSchemeUtf16` |
| 22 | `[` 1, 2 `]` | `''` | `rsTermSchemeNotObject` |
| 23 | `{"schemes": {}}` | `''` | `rsTermSchemeSchemesNotArray`、`Key = 'schemes'` |
| 24 | `{"schemes": [#1 去掉 name, #1]}` | `''` | 成功、取第二个（第一个没名字不算候选） |
| 25 | `{"schemes": [{"name":"A", 缺 red}, {"name":"A", 全}]}` | `'A'` | 成功、取第二个（不全的跳过，同 WT） |
| 26 | `{"schemes": [{"name":"A", red #111111}, {"name":"A", red #222222}]}` | `'A'` | `Red = $111111`（第一个，同 WT 的 `emplace`） |
| 27 | `{"schemes": [{"name":"A", 全}, {"name":"B", "red": "bad"}]}` | `'A'` | 成功（B 的坏颜色不连累，§11.1.10） |
| 28 | `{"schemes": [{"name":"\u4e2d\u6587", 全}]}`（源文本里是转义） | `'中文'` | 成功、`Name = '中文'` |
| 29 | `{"schemes": []}` | `''` | `rsTermSchemeNoneValid` |
| 30 | `{`（没收尾） | `''` | `rsTermSchemeBadJson`，消息有行号 |

判据（每条写进测试的断言消息）：
  - 失败的每一行：`TryLoadFromText` 返回 False、`AError` 非空；事先装好的一套方案（`Equals` 快照）不变、`OnChange` 零次、`Revision` 不变。**变异 L1**：先改自己再校验（失败留半套）→ 红。
  - 成功的每一行：`OnChange` 恰好一次。
  - 夹具字节数 = 36805（防 autocrlf 动它，地雷 10）。
  - 夹具 16 套逐一 `LoadFromText(夹具, 名字)` 都成功（循环里断言次数 = 16）。
  - **L2**：不去 BOM → #20 红。**L3**：不认 `magenta` → #10 红。**L4**：按名取改成「最后一个」→ #26 红。**L5**：不跳过不全的候选 → #25 红。**L6**：缺的可选项不补（留 `clNone`）→ #6、#9 红。**L7**：不预解码 → #28 红（两个 `\u` 挨着丢字节）。**L8**：名字比较改成不区分大小写 → #3 红。

- [ ] **Step 4: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.ColorScheme.pas source/tyControls.StrConsts.pas languages/tyControls.StrConsts.pot languages/tycontrols.strconsts.en.po languages/tycontrols.strconsts.zh_CN.po tests/fixtures/terminal-wt-defaults.json .gitattributes tests/test.terminal.colorscheme.pas && git commit -m "feat(terminal): read Windows Terminal colour schemes

A scheme loads from a single scheme object or from a settings.json by
name, the way Windows Terminal picks it: the first complete scheme with
that exact name wins, and the four optional colours fall back to its
defaults. A load that fails leaves the scheme as it was, with a message
naming the key. Windows Terminal's own defaults.json is kept as a
fixture byte for byte.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 写 Windows Terminal 的 JSON

**Files:**
- Modify: `source/tyControls.Terminal.ColorScheme.pas`、`tests/test.terminal.colorscheme.pas`

- [ ] **Step 1: `SaveToText`**：名字空 → `rsTermSchemeNoName`；16 色有未设置的 → `rsTermSchemeMissingKeys`（列 WT 键名）。不用 `fpjson` 的格式化器（它的缩进和键序不受我们控制），自己拼：

```text
{
    "name": "<JSON 转义后的名字>",
    "foreground": "#RRGGBB",
    "background": "#RRGGBB",
    "selectionBackground": "#RRGGBB",
    "cursorColor": "#RRGGBB",
    "black": "#RRGGBB",
    …（red green yellow blue purple cyan white brightBlack … brightWhite）
    "brightWhite": "#RRGGBB"
}
```

每行 `LF`、末尾一个 `LF`；前四项未设置的整行不写；名字按 JSON 转义（`"`、`\`、控制字符写 `\uXXXX`，其余 UTF-8 原样）。`SaveToFile` 用 `TFileStream` 写 `SaveToText` 的字节（不加 BOM）。所有 `raise ENotImplemented` 此时都不许剩（`grep -n ENotImplemented source/tyControls.Terminal.ColorScheme.pas` 为空）。

- [ ] **Step 2: 测试（判据）**
  - Campbell（Task 3 #1 读进来）写出的文本逐字等于期望串（测试里写死：键序、大写、四空格、`LF`、末尾换行）。**变异 S1**：`selectionBackground` 与 `cursorColor` 顺序对调 → 红。**S2**：小写十六进制 → 红。
  - 读 → 写 → 读：夹具 16 套逐一，第二次读出的方案 `Equals` 第一次（断言次数 = 16）。
  - 只设 16 色、四个可选项未设置：输出里没有这四个键；再读回来四项按 WT 补。
  - 缺一色 → 报错、方案不变；名字空 → 报错。**S3**：缺色时照写 `#000000` → 红。
  - 名字 `a"b\c` 与 `中文` 写出后读回来相等。
  - `CursorText`、`SelectionInactiveBackground` 设了也不写（输出里没有 `cursor`、`Inactive` 字样）。
  - 系统色：`Red := clWindow` 写出的是 `ColorToRGB(clWindow)` 的 `#RRGGBB`。

- [ ] **Step 3: 提交**：`feat(terminal): write colour schemes in Windows Terminal's format` + 说明（键序照 WT 的 ToJson、缺色或无名拒绝写、两项 WT 没有的不写）+ Co-Authored-By。

---

### Task 5: 控件的属性、流式化、RTTI

**Files:**
- Modify: `source/tyControls.Terminal.pas`
- Create: `tests/test.terminal.view.scheme.pas`（suite `TTyTerminalViewSchemeTests`；夹具照 `test.terminal.view.pas` 的 `F.View` / `F.Ctl` / `TyTermFixtureCss` 那一套，能引用就引用、不复制）
- Modify: `tests/test.terminal.view.pas`、`tests/tytests.lpr`

- [ ] **Step 1: 属性**：接口清单里的四个属性、`TTyTerminalColorSource`。构造里 `FColorScheme := TTyTerminalColorScheme.Create(Self)`、`FDarkColorScheme` 同样，`OnChange := @SchemeChanged`；析构里先断开 `OnChange` 再释放。`SetColorScheme` / `SetDarkColorScheme` = `Assign`。`SetColorSource` / `SetColorSchemePaired` 值变了、`SchemeChanged` 被调时，都走一个 `RequestSchemeNotify`：`csLoading` 或 `csDestroying` 时什么都不做；否则 `FNotifyQueued` 没排过就 `Application.QueueAsyncCall(@AsyncNotifyScheme, 0)`（开工前问题二第 12 条；`AsyncNotifyScheme` 里 `EnsureThemeCurrent` 之后补一句 `Invalidate`）。**不当场 `Invalidate`**——它会当场 `EnsureThemeCurrent`、当场通知。色表的键失效是自动的（键里有修订号 / 来源 / 配对，Task 6），不用另设标志。
- [ ] **Step 2: RTTI 守卫扩展**（`test.terminal.view.pas` 的 `TestPublishedDefaultsMatchTheConstructor`）：另走 `ColorScheme`、`DarkColorScheme` 两个子对象的序数属性，逐个 `Default` = 构造值；断言子对象检查的个数 = 44。**变异 P1**：控件构造里给 `ColorScheme.Background` 设了值 → 红。
- [ ] **Step 3: 流式往返**（`TestStreamedValuesSurviveLoading` 加几项，或本 suite 新开一条）：源控件设 `ColorSource := tsrcScheme`、`ColorSchemePaired := True`、`ColorScheme` 从 Campbell 读、`DarkColorScheme.Red := TColor($1F0FC5)`、`DarkColorScheme.Name := 'Mine'`；`WriteComponent` / `ReadComponent` 后目标的四个属性相等（方案用 `Equals`）。另断言：流里只写了设过的子属性——把流转成文本（`ObjectBinaryToText`），`DarkColorScheme.` 开头的行恰好 2 行。**P2**：去掉 `ColorScheme` 的 setter（改只读）→ 红（FPC 不写，核实记录 9）。
- [ ] **Step 4: 加载中不通知**：用 `ObjectTextToBinary` 从一段 `.lfm` 文本（`ColorSource = tsrcScheme`，外加 `ColorScheme.` 开头的 Name 与 22 色）读进一个有父窗体、挂了 `OnData` 的控件。读完先泵消息（`Application.ProcessMessages` 五次），此时 `OnData` 为空、`FNotifyQueued` 为 False（纯查询）；再 `WriteSync(#27'[?2031h')`、清记录、绘制一次、泵消息：`OnData` 仍为空（加载后第一次建色表不算变化）；再改一色、泵消息：恰好一条 `ESC[?997;`。另断言加载后 `SchemeNotifyRequests = 0`（纯查询：`RequestSchemeNotify` 真正排队的次数）。**P3**：`RequestSchemeNotify` 不看 `csLoading` → `SchemeNotifyRequests` 红（2031 那条不一定红：加载时 2031 还没开，排队的通知发不出东西——所以要这个计数）。
- [ ] **Step 5: 提交**：`feat(terminal): a colour source and two colour schemes on the terminal view` + 说明（跟随主题仍是默认；方案对象在设计器里展开、只写改过的项；加载中不重建色表）+ Co-Authored-By。

---

### Task 6: 取色、明暗配对、通知时机

**Files:**
- Modify: `source/tyControls.Terminal.pas`、`tests/test.terminal.view.scheme.pas`

- [ ] **Step 1: `EnsurePalette`**（`Terminal.pas:1246-1324`）：
  1. **缓存判断**（开头那一句）在原来四项之外加：`FPaletteSource = FColorSource`、`FPalettePaired = FColorSchemePaired`、`FPaletteSchemeRev = SideRevision(FPaletteDarkSide)`——`SideRevision(d)` 是「来源是主题 → 0；不配对或 `not d` → `FColorScheme.Revision`；否则 `FDarkColorScheme.Revision`」。明暗那一边只取决于主题，而主题的四项已经在键里，所以用**上次算出的** `FPaletteDarkSide` 挑修订号就够，热路径上不多解析一次样式。
  2. 键不同才往下：先照旧算出 `instFg` / `instBg` / `themeFg` / `themeBg`（这一段不动）。
  3. `darkSide := not (TyLuminance(TyRGB(instBg 的三个通道)) > 0.5)`（`on()` 的规则）；`scheme :=` `nil`（`ColorSource = tsrcTheme`）/ `FColorScheme`（不配对，或配对且浅）/ `FDarkColorScheme`（配对且深）。
  4. 原来的整张表照旧建好（主题值）。然后若 `scheme <> nil`，逐槽覆盖（spec §11.1.4 的表）：0–15、256、257 设了就用；258 = 方案的光标，否则**覆盖后的** 256；光标下的字色 = 方案的，否则覆盖后的 257；选区聚焦 = 方案设了就 `TTyColor(($4D shl 24) or rgb)`（`rgb` 是 `SlotRgb` 给的 `$RRGGBB`，写法同 `:1281` 的 `($5A shl 24) or instFg`），否则主题的；选区失焦 = 方案的失焦色（同样 0.3），否则方案的聚焦色（设了），否则主题的；`FSelInk` / `FSelHasInk` / `FLinkRgb` 不动。
  5. 记下新键：`FPaletteSource`、`FPalettePaired`、`FPaletteDarkSide := darkSide`、`FPaletteSchemeRev := SideRevision(darkSide)`。
- [ ] **Step 2: `EnsureThemeCurrent`**（`:1332-1334` 与 `:1364-1368`）：「和上次通知同一把键」的判断与记录都加那四项（地雷 4）。其余不动：逐项比、真变了才通知、在绘制里就排队。
- [ ] **Step 3: `PaintPreedit`**（`:2479-2485`，开工前问题一第 4 条按建议）：`ActiveColorScheme <> nil` 时不读 `TyTerminalPreedit` 的 `background` / `color`（直接用 `FFrameColors[257]` / `[256]`），`border-color` 照读。
- [ ] **Step 4: `ActiveColorScheme`、`ThemeGroundIsDark`**：给测试的纯查询，读 `EnsurePalette` 算好的结果（先 `EnsurePalette`）。
- [ ] **Step 5: 测试（判据）**。夹具：`TyTermFixtureCss` 的主题底是 `#102030`（深）；另备一个浅底覆盖 `TyTerminal { background: #f4f4f4; color: #202020; }`。方案用 Campbell（深）、Tango Light（浅，读夹具）。颜色一律经 `View.Core.ResolveColor` 和像素（下划线 / 底色块，[[headless-render-needs-sentinel-ground]]）两头看。
  - **跟随主题不变**：`ColorSource = tsrcTheme`、方案里装满 Campbell → 259 色逐项等于没装方案时（先记一份）。**V1**：`EnsurePalette` 不看 `ColorSource` → 红。
  - **逐槽**：`tsrcScheme` + Campbell → `ResolveColor(1) = $C50F1F`、`(5) = $881798`、`(256) = $CCCCCC`、`(257) = $0C0C0C`、`(258) = $FFFFFF`、`(100) = TyTermDefaultPaletteColor(100)`。**V2**：`purple` 的槽错位 → 红。**V3**：字节序反了 → 红（`$C50F1F` vs `$1F0FC5`）。
  - **未设置跟主题**：方案只设 `Red`：`ResolveColor(1)` = 方案色，`(2)`、`(256)`、`(257)` = 主题值；`(258)` = 主题前景（光标未设 → 生效的前景）；把前景也设了：`(258)` 跟着变成方案前景。**V4**：光标未设时取主题的光标色而不是生效前景 → 最后一步红（夹具主题光标是 `#ff8000`）。
  - **光标下的字色**：块光标格的字形像素颜色 = 方案 `CursorText`；未设 → 方案底色。
  - **选区 0.3**：方案 `SelectionBackground := $FFFFFF`、底 `$000000`：选中格底色像素 = `TyTermBlendOver($000000, BGRA(255,255,255,$4D))`（= `$4D4D4D`）；失焦（未设）同聚焦；再设 `SelectionInactiveBackground := $FF0000`，失焦时 = `TyTermBlendOver($000000, BGRA(255,0,0,$4D))`。**V5**：不降 alpha（按不透明替换）→ 红。**V6**：失焦未设时退回主题而不是方案聚焦色 → 红。
  - **OSC 覆盖 > 方案**：方案底 `$0C0C0C`；程序 `OSC 11 ;#f0f0f0` → `ResolveColor(257) = $F0F0F0`、内边距像素是它；`OSC 111` → 回到 `$0C0C0C`（方案，不是主题的 `#102030`）。**V7**：覆盖表之后又被方案盖掉（接线放错层）→ 红。
  - **996 / 2031 按生效底色**：浅主题（覆盖 `#f4f4f4`）+ Campbell：`CSI ? 996 n` 答 `ESC [ ? 997 ; 1 n`（深）；跟随主题时答 `…;2n`（浅）——同一个主题下两种答案都出现过，断言才有意义。再 `OSC 11 ;#ffffff` → 答浅。
  - **通知时机**（开 2031、清记录；每个动作之后先断言 `OnData` 还是空的、`NotifyQueued = True`，再泵消息五次，然后数 `ESC[?997;` 的条数）：`ColorSource` 从主题切到方案 → 1；改方案一色 → 1、且之前 `OSC 4;1;#123456` 设的覆盖被清掉（`ResolveColor(1)` = 方案色）；`BeginUpdate` 改 5 色 `EndUpdate` → 1；`LoadFromText` 换一套 → 1；从「深色主题、已是自定义方案 Campbell、不配对」出发，**同一段代码里连着** `ColorScheme` 装 Tango Light（正在用，色表变）、`DarkColorScheme` 装 Tango Dark、`ColorSchemePaired := True`（深色主题下换到深色那边，色表又变）→ 1（当场通知的话是 2）；改一个**当前没用到**的色（`tsrcTheme` 时改 `ColorScheme.Red`；配对且浅时改 `DarkColorScheme.Red`）→ 0，且 `RowsPaintedLastFrame`（5 期的探针）下一帧为 0（不重画）；把方案改成和主题每一色都相同 → 0（色表没变）。改完不泵消息就 `CSI ? 996 n`：答的已是新方案的明暗（色表当场就是新的）。**V8**：`EnsureThemeCurrent` 的键没加新四项 → 「改一色 → 1」红（地雷 4）。**V9**：键里放两边的修订号 → 「没用到的色 → 不重画」红。**V13**：`RequestSchemeNotify` 当场 `Invalidate`（不排队）→ 「连着设四项 → 1」红（会是 2）、「动作之后 `OnData` 还是空的」红。
  - **明暗配对**：`ColorSchemePaired := True`、`ColorScheme` = Tango Light、`DarkColorScheme` = Campbell；控制器 `Mode := 'light'`（或浅底覆盖）→ `ActiveColorScheme = ColorScheme`、`ResolveColor(257) = $FFFFFF`；切 `'dark'`（或 `TyTermFixtureCss` 的深底）→ `= DarkColorScheme`、`$0C0C0C`、2031 报一次深；再切回 → 报一次浅。关掉配对再切明暗 → 0 条（色表不变）。**V10**：明暗判定读了 `FPalette[257]`（方案的底）→ 红（地雷 6：Campbell 的深底把自己判成深，浅主题下也选深那边）。边界：主题底分别是 `#7f7f7f` 与 `#808080`（Rec.601 在 0.5 两侧最近的两个灰），期望由 `ResolveOverride('color: on(<那个灰>, #000000, #ffffff)')` 取 tycss 自己的答案（黑 = 浅、白 = 深），不手算。**V11**：判定方向反了（`> 0.5` 算深）→ 红。`>` 写成 `>=`（**V11b**）：整数通道里 `299r + 587g + 114b = 127500` 有 114 组解（写计划时枚举过，比如 `#00CC44`、`#01ADE1`、`#04C26D`），但 `TyLuminance` 按 `Single` 算，恰好等于 0.5 的不一定有——执行时对这 114 组逐个算，挑一组恰好 0.5 的加进边界例（期望仍由 `on()` 给），V11b 必须红；一组都没有就标等价、理由写进签收。
  - **单模式的深色皮肤**：主题只写 `TyTerminal { background: #1e1e1e }`、没有 `@mode` → `ThemeGroundIsDark = True`。
  - **最低对比度照样生效**：方案用 Solarized Light（底 `$FDF6E3`），挑其中一色对这个底比值 1 时 < 4.5 的（执行时用 `TyTermContrastRatio` 算出来挑一个，挑中的色号和比值写进测试注释），`MinimumContrastRatio := 4.5` → 下划线像素 = `TyTermEnsureContrastRatio(底, 前景, 4.5)` 的结果；1 时 = 原色。**V12**：方案覆盖漏了 257（底色仍是主题的 `#102030`）→ 红（对比度按错的底推，下划线色不同）。
  - **禁用**：`Enabled := False` → 底色像素 = `PremixRgb(方案底, 父底, a)`（同 3 期的禁用测试的算法）。
  - **组字串**：方案下组字串的底色像素 = 方案底色、不是夹具 `TyTerminalPreedit` 的 `#203040`；下划线仍是 `#00ff00`。
  - **3–5 期的主题测试一条不改就绿**（地雷 14）。
- [ ] **Step 6: 提交**：`feat(terminal): the palette takes a colour scheme between the program's colours and the theme` + 说明（逐槽方案优先、未设跟主题；配对按主题底色深浅选边；色表真变了才通知 Core，没用到的那套改了不重画；OSC、对比度、禁用照旧在后面）+ Co-Authored-By。

---

### Task 7（有条件）: 设计器右键导入 / 导出

只在开工前问题一第 2 条用户同意时做；否则跳过，签收写「用户选不做」。

**Files:**
- Modify: `source/tyControls.Terminal.ColorScheme.pas`（设计器要用的纯逻辑放这里，能测）、`tests/test.terminal.colorscheme.pas`
- Modify: `designtime/tyControls.Design.CompEditors.pas`、`languages/tyControls.Design.CompEditors.pot`、`languages/tycontrols.design.compeditors.zh_CN.po`

- [ ] **Step 1: 纯逻辑**：`function TyTermSchemeImportPlan(const AText: string; out ANames: TStringArray; out AError: string): Boolean`——列出能导入的名字（`ListSchemeNames` 里 16 色齐的）；零个时 False 带 `rsTermSchemeNoneValid`。测试：夹具 → 16 个；只有一套的单个对象 → 1 个；坏 JSON → False。
- [ ] **Step 2: 组件编辑器** `TTyTerminalViewComponentEditor = class(TDefaultComponentEditor)`（保留双击的默认行为），两个动词：「Import Windows Terminal colour scheme...」「Export colour scheme...」。导入：`TOpenDialog`（过滤 `*.json`）→ 读文本 → `TyTermSchemeImportPlan` → 一个名字直接用、多个 `InputCombo` → 配对开着时再 `InputCombo`（浅色 / 深色）→ `TryLoadFromText` 进对应方案 → 失败 `TyMessageDlg` 带 `AError` → 成功 `Designer.Modified`，若 `ColorSource = tsrcTheme` 顺手设成 `tsrcScheme`（问一句：`TyMessageDlg` 是 / 否）。导出：配对时先问哪一套，`TSaveDialog` → `SaveToFile`，异常 `TyMessageDlg`。`RegisterComponentEditor(TTyTerminalView, TTyTerminalViewComponentEditor)` 加进 `RegisterComponentEditors`。菜单字串是 `resourcestring`，进设计期 `.po`（zh_CN：「导入 Windows Terminal 配色…」「导出配色…」「写进哪一套？」「浅色」「深色」「改成使用自定义方案？」）。
- [ ] **Step 3: 【主控执行】** 编 `tycontrols_dt.lpk`（设计期包不在测试构建里）；真机项第 95 项。
- [ ] **Step 4: 提交**：`feat(designer): import and export Windows Terminal colour schemes on the terminal view` + Co-Authored-By。

---

### Task 8: 示例

**Files:**
- Create: `examples/terminal/colorschemes/windows-terminal.json`
- Modify: `examples/terminal/umain.pas`、`examples/terminal/umain.lfm`、`examples/terminal/languages/terminal_example.zh_CN.json`
- Modify: `tests/test.terminal.example.pas`

- [ ] **Step 1: 方案文件**：`{ "schemes": [ … ] }`，七套（开工前问题一第 3 条的答复，默认 Campbell、One Half Dark、One Half Light、Solarized Dark、Solarized Light、Tango Dark、Tango Light）的对象**原样**从夹具抄（键和值、大小写一字不改），`LF`、四空格。第一行写注释说明出处（WT 格式允许 `//`，顺带演示读注释）：`// From Windows Terminal's defaults.json (commit 4e2b8bd9), MIT License. See THIRD-PARTY-NOTICES.md.`
- [ ] **Step 2: 界面**（全在 `.lfm`，[[demo-edits-lfm-not-code]]）：第四行工具栏 `Tools4` 在「Minimum contrast」之后加 `LblColors: TTyLabel`（`Caption = 'Colours:'`）、`CmbColors: TTyComboBox`（`AutoSize`，宽度按最长项）、`BtnImportColors: TTyButton`（`Caption = 'Import...'`、`Hint = 'Load a Windows Terminal colour scheme or settings.json'`）；控件一律设显式 `Left` / `Top`（[[lcl-code-created-align-order]]）。放不下就另起第五行 `Tools5`，别把已有的挤窄。
- [ ] **Step 3: 代码**：
  - 启动时找 `colorschemes/`（照 `RecordingsDir` 的往上找法，抽一个共用的 `ExampleDir(const ASub)`）、读 `windows-terminal.json`，`ListSchemeNames` 进下拉：第 0 项 `rsColorsFollowTheme`（「Follow theme」）、然后七套名字、然后三对 `One Half (light / dark)`、`Solarized (light / dark)`、`Tango (light / dark)`（`rsColorsPairFmt = '%s (light / dark)'`，只在两套都在时出现）。每项的 `Objects[]` 挂一个小记录（文本 + 浅名 + 深名），不在下拉里存原文多份。
  - 选中：「跟随主题」→ `Term.ColorSource := tsrcTheme`；单套 → `Term.ColorScheme.LoadFromText(文本, 名)`、`ColorSchemePaired := False`、`ColorSource := tsrcScheme`；一对 → `ColorScheme` 读浅、`DarkColorScheme` 读深、`ColorSchemePaired := True`、`ColorSource := tsrcScheme`。连着设几项只通知一次靠控件（开工前问题二第 12 条），示例不用管顺序。
  - 「导入…」：`DlgOpen`（已有的 `TTyOpenDialog`，过滤 `JSON (*.json)|*.json|All files|*`）→ 读文件 → `ListSchemeNames` → 能读的每一套（`TryLoadFromText` 到一个临时方案，成功才算）加进下拉末尾、选中导入的第一套；一套都读不进 → 状态栏显示 `rsColorsImportFailedFmt`（「Could not import: %s」）带 `AError`，控件不变。
  - 明暗开关不用额外代码：配对时换主题明暗，控件自己换边。
- [ ] **Step 4: i18n**：`terminal_example.zh_CN.json` 加 `umain.rscolorsfollowtheme`「跟随主题」、`umain.rscolorspairfmt`「%s（浅色 / 深色）」、`umain.rscolorsimportfailedfmt`「无法导入：%s」，以及 `.lfm` 的三个标题 / 提示（「配色：」「导入…」「读入 Windows Terminal 的配色方案或 settings.json」）——键名照已有条目的写法；`.po` 由主控在 Task 10 生成。
- [ ] **Step 5: 测试**（`TTyTerminalExampleTests`，照 `TestTheMainFormBuildsWithARecording` 建主窗体）：下拉有 1 + 7 + 3 = 11 项、顺序对；选 `Solarized Dark` → `Term.ColorSource = tsrcScheme`、`Term.Core.ResolveColor(257) = $002B36`；选 `Tango (light / dark)` → `ColorSchemePaired`、两套名字对，拨 `DarkSwitch` 到暗 → `ResolveColor(257) = $000000`（Tango Dark），拨回 → `$FFFFFF`（Tango Light）；选「跟随主题」→ `tsrcTheme`、`ResolveColor(257)` 回到主题底；从 1 → 单套 → 一对，每次选择 2031 报告恰好 1 条（开 2031 后数）；导入一个坏文件（测试写进临时目录）→ 下拉项数不变、状态栏有 `Could not import`、`ResolveColor(257)` 不变。另一条：exe 旁和上几层都找不到 `colorschemes/` 时（测试把查找起点指到临时目录）建窗体不抛、下拉只有「跟随主题」一项、「导入…」照样可用。**X1**：一对的深色那套读成浅色的名字 → 拨暗那一步红。**X2**：找不到目录时不判空直接读文件 → 最后一条红（抛异常）。
- [ ] **Step 6: 提交**：`feat(examples): colour schemes in the terminal example` + 说明（七套取自 WT 的 defaults.json、三对随暗色开关换、导入任意 WT 文件）+ Co-Authored-By。

---

### Task 9: 文档、notices、README、发版守卫、截图工具

**Files:**
- Modify: `docs/controls/terminal.md`、`README.md`、`README.en.md`、`THIRD-PARTY-NOTICES.md`、`tests/test.release.pas`、`tools/terminal-shots/terminalshots.lpr`

写法照 [[doc-writing-native-tone]]：原生中文、短句、不写小作文。

- [ ] **Step 1: `docs/controls/terminal.md`**
  - §2 单元与 typeKey：加 `tyControls.Terminal.ColorScheme`。
  - §3 published 属性表加 `ColorSource`、`ColorScheme`、`ColorSchemePaired`、`DarkColorScheme`；方案对象的 23 个子属性一张小表（名字、WT 键、未设置时）；方法（读、写、`Try*`、`ListSchemeNames`）。
  - §10 状态与主题：新一小节「独立配色方案」——优先级一句话（程序的颜色 > 方案 > 主题）、未设置的项跟主题、选区按 0.3 混、明暗配对按主题底色的深浅、换方案会清掉程序用 OSC 设的颜色（和换主题一样）、禁用与最低对比度照旧；浅底 16 色看不清时「可以换一套方案，或打开最低对比度」。
  - 新小节「读写 Windows Terminal 配色」：支持的形状（单个对象、`settings.json` 按名）、颜色格式、缺项怎么补、错误怎么报、写出的样子与丢掉的两项；「方案从哪来」：WT 自带的、`iTerm2-Color-Schemes` 的 `windowsterminal/` 目录（许可按单套各自的）。
  - §11 代码示例：从文件读一套、配对两套、`TryLoadFromFile` 报错。
  - §13 本期限制 / 后续：只支持 WT 格式；16–255 不进方案；系统色变了不会自己刷新；`\u0000` 在名字里会丢。
- [ ] **Step 2: README**：两份的终端那一行（或功能列表）补「独立配色方案（可读写 Windows Terminal 格式）」，不改控件数。
- [ ] **Step 3: notices**：`THIRD-PARTY-NOTICES.md` 新一节 `## Windows Terminal color schemes — examples/terminal/colorschemes/`：出处（`microsoft/terminal`，`src/cascadia/TerminalSettingsModel/defaults.json`，commit `4e2b8bd9`）、「只在带上示例这个目录时才要」、Solarized（Copyright (c) 2011 Ethan Schoonover，MIT）、One Half（Copyright (c) 2019 Son A. Pham，MIT）两行、Tango 公有领域一句、WT 的 MIT 全文（`Copyright (c) Microsoft Corporation. All rights reserved.`）。「Test fixtures」一小节加一行：`tests/fixtures/terminal-wt-defaults.json` 是同一个文件的原样一份。
- [ ] **Step 4: 发版守卫**（`tests/test.release.pas`）：新测试 `TheExampleColourSchemesAreCoveredByTheNotice`：`examples/terminal/colorschemes/` 下每个 `.json` 都被 notices 那一节的标题覆盖（标题里有这个目录名）；文件里的每一套名字都在「示例带的七套」里（防以后有人加一套许可没查过的）；文件无 `\u0000`。`TheThirdPartyNoticeCoversTheTerminalPort` 不动（新单元是自己写的）。`EveryUnitOnDiskIsListedInItsPackage` 自然管新单元。**变异 D1**：notices 删掉那一节 → 红。**D2**：示例文件里多加一套 `Dark+` → 红。
- [ ] **Step 5: 截图工具**：`terminalshots.lpr` 加 `--phase6`，出到 `docs/superpowers/plans/2026-09-30-terminal-phase-6-shots/`，`index.md` 列每张看什么（格式照 5 期）：
  1. `scheme-{campbell,onehalf-dark,onehalf-light,solarized-dark,solarized-light,tango-dark,tango-light}.png`：`palette.cast` 在 default 浅色主题下、七套方案各一张。
  2. `scheme-pair-tango-{light,dark}.png`：配对，主题浅 / 深各一张。
  3. `scheme-follow-default-{light,dark}.png`：跟随主题的对照。工具里同一个控件「从没设过方案」和「方案装满 Campbell、但 `ColorSource = tsrcTheme`」各画一次，两张逐像素相同，不同就打印出来（签收记结果）。
  4. `scheme-osc11-solarized-dark.png`：方案下程序 `OSC 11 ;#203040`，内边距跟着变。
  5. `scheme-contrast-{1,45}-solarized-light.png`：最低对比度 1 与 4.5。
  6. `scheme-partial-default-light.png`：方案只设了前景、背景、红，其余跟主题。
  7. `scheme-selection-{focused,unfocused}-campbell.png`：选区的 0.3。
- [ ] **Step 6: 提交**（不编译；截图由主控在 Task 10 跑）：`docs(terminal): colour schemes in the control page, the notices and the shots tool` + Co-Authored-By。

---

### Task 10: 收尾——编译、全量、按 spec 逐条核、集中变异、主控编包编示例截图、审查、写回 spec、签收

**Files:**
- Modify: 本计划（签收记录）、`docs/superpowers/specs/2026-09-28-terminal-view-design.md`（写回）
- 修复时按需改 Task 1–9 的文件

- [x] **Step 1: 一次编译 + 本期 suite + 全量**：「跑测试的固定套路」。Expected：本期 suite 全 0 / 0；全量 errors / failures 只剩基线那一条、总数 = 基线 + 本期新增。红了集中修：WT 格式以 spec §11.1.2 的核实记录为准、取色语义以 xterm `ThemeService.ts` 为准；修复提交 `fix(terminal): ...`，一个问题一个提交。
- [x] **Step 2: 按 spec 逐条核代码，不看测试**（[[green-tests-are-not-spec-conformance]]、[[built-not-wired-is-the-default-failure]]）：§11.1.1 七条、§11.1.3 两张表的每一行、§11.1.4 取色表每一槽、§11.1.5 三条、§11.1.6 六条、§11.1.7 读九条写五条、§11.1.8 错误表每一行、§11.1.9、§11.1.11；逐条记「在哪一行实现 / 为什么不需要 / 挪到以后」。
- [x] **Step 3: 【主控执行】编包、编示例、i18n、截图**（截图已在审查修复后重跑；主控在 922af908 上编完两个包与示例，见签收）

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tycontrols.lpk > /tmp/term-pkg.txt 2>&1; tail -3 /tmp/term-pkg.txt; lazbuild -B tycontrols_dt.lpk > /tmp/term-dt.txt 2>&1; tail -3 /tmp/term-dt.txt; lazbuild -B examples/terminal/terminal_example.lpi > /tmp/term-ex.txt 2>&1; tail -3 /tmp/term-ex.txt; git status --short
```

Expected：三个都编过。然后：
1. `python scripts/example-rsj2po.py examples/terminal terminal_example examples/terminal/languages/terminal_example.zh_CN.json`，重编示例，`python scripts/check-example-po.py` 过；`python scripts/check-lfm-props.py` 过。
2. `powershell -File scripts/smoke-launch-examples.ps1`（终端示例起得来）。
3. 示例里切 Solarized Dark、Tango（明暗）后拨暗色开关、「导入…」选夹具 `terminal-wt-defaults.json`（只看不录，真机验收时用户再看）。
4. Task 7 做了的话：装 `tycontrols_dt.lpk` 重建 IDE，右键终端看得到两项（真机项第 95 项交用户）。
5. `lazbuild -B tools/terminal-shots/terminalshots.lpi` 后跑 `terminalshots --phase6`；PNG 进 git、单张 ≤ 300 KB；抽查每组一张；`scheme-follow-*` 与 3 期截图逐像素相同的比对结果记进签收。
- [x] **Step 4: 集中变异**（每条三拍，必须红）：C1–C5（Task 1）、O1–O5（Task 2）、L1–L8（Task 3）、S1–S3（Task 4）、P1–P3（Task 5）、V1–V13 与 V11b（Task 6）、X1–X2（Task 8）、D1–D2（Task 9）；Task 7 做了的话加 **E1**（`TyTermSchemeImportPlan` 把不全的也列上 → 红）。结果逐条记进签收；没红的当场补强。
- [x] **Step 5: 整体代码质量审查**（`git diff <Task 0 的 HEAD>..HEAD`）：
  - 方案单元：读的每条规则与 spec §11.1.7 对照；错误路径都原子；预解码与 AdvChart 那份的差异写在注释里；没有 `ENotImplemented`；`fpjson` 对象都释放（`try … finally`）。
  - 控件：两把键（地雷 4）；判明暗用的是主题底（地雷 6）；加载中（地雷 7）；析构顺序；`EnsurePalette` 的热路径没变慢（跑一次 `terminalbench --paint`，和 5 期签收的 10.92–11.05 ms 比）。
  - 视觉值没有写死（0.3 是上游的常量，注明出处）；测试里期望值不从被测代码算（[[test-expectation-from-the-environment]]）。
  审出来的问题修完回到 Step 1。
- [x] **Step 6: 写回 spec 原处，标「实现期修正（6 期）」**，原文删除线保留。至少：状态行（6 期签收）；§11.1 各小节里「待定」的三条按用户的答复改成定论；实现中与 §11.1 不同的地方；§14（notices 实际写法）；§15（§11.1.10 若有增减）；§16（本期真机项编号）；§17（6 期开工前问题的结论）；§18（6 期实际做了什么）。
- [x] **Step 7: 签收记录写进本计划末尾，提交**：全量条数（基线 → 签收）、提交区间、本期各 suite 用时、变异结果（每条红 / 补强 / 等价）、spec 写回的节号、计划外发现（至少：AdvChart 的 `TyDecodeUnicodeEscapes` 不认注释、会把 `"` / `\` 解成裸字符）、遗留。

```bash
cd /d/Projects/ty-3.1 && git add docs/ && git commit -m "docs(terminal): phase 6 sign-off; corrections written back into the spec

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: 更新最终验收文档（1–6 期合在一份）

**Files:**
- Modify: `docs/superpowers/plans/2026-09-29-terminal-acceptance.md`

用户在验收 1–5 期，**不另起一份**。写法照 [[doc-writing-native-tone]]；改动只加不删，已有的 1–91 项文字不动（除了下面点名的几处「6 期：…」补句）。

- [ ] **Step 1: 开头**：第一段「五期做完后」改成「六期做完后」、「3–5 期所有要在真机上看的项」改成「3–6 期」；「做了什么」加一条 **6 期**：「终端可以不跟主题、换成独立的配色方案（前景、背景、光标、选区、16 色），可在设计器里改、能配成明暗两套随主题换；方案从 Windows Terminal 的 JSON 读进来、也能写出去；示例带 WT 自带的七套和三对明暗，外加『导入…』。」分支头提交和全量条数换成 6 期签收的。
- [ ] **Step 2: 准备**：示例那条加「配色」下拉和「导入…」在第几行工具栏（按 Task 8 的实际位置）；Task 7 做了的话，设计期那条加「右键终端有导入 / 导出配色」。
- [ ] **Step 3: 验收表**：表头说明里的「5 期审查补」后加一句「第 92 项起是 6 期」。第 92 项起并入下面「6 期新增的真机验收项」（Task 7 没做就删掉第 95 项、后面顺延）。已有几项补一句「6 期：…」，不另起：
  - 第 3 项（16 色与皮肤）：「6 期：看不清的可以在示例里换一套方案对照（第 92 项）。」
  - 第 19 项（OSC 改色后整屏更新）：「6 期：自定义方案下再做一次，`\e]111\a` 回到方案的底色（第 96 项）。」
  - 第 26 项（浅底 3 号色取舍）：「6 期：默认仍跟随主题；看不清的宿主可以换方案（决定 D1）。」
  - 第 76 项（最低对比度）：「6 期：方案下同样生效（第 97 项）。」
  - 第 18 项（设计期）：「6 期：见第 94、95 项。」
- [ ] **Step 4: 按平台的项号**：把 92 项起的项号按平台列补进索引表。
- [ ] **Step 5: 决定清单**：
  - D1 的「选项」后加一行「**6 期后的表述**：默认跟随主题；看不清可换方案。主题的浅底 16 色仍是默认，仍待你在（a）/（b）/（c）中定；嫌看不清的宿主可以把单个终端换成一套方案（示例里的 Tango Light、Solarized Light、One Half Light），或打开最低对比度。」「看哪里」加 6 期截图 `scheme-*-light.png`。
  - D2 同样加「6 期后的表述」一行（7 / 15 调不调仍待定；看不清可换方案）。
  - D17「另一个做法」加「或换一套方案（6 期）」。
  - 新一小节「**6 期开工前的问题**」：四条（明暗配对的属性形态、设计器右键导入导出、示例带哪几套、自定义方案下链接与组字串的颜色），每条写「是什么、选项、现在的做法（按 Task 0 的实际答复）、看哪里、改哪里」，格式照 D8–D13 那张表。
  - 「spec §15 里你可能想改的偏离」加一行「6 期新增」：读 WT 配色时的六处与 WT 不同（严格的十六进制、重复键报错、只校验选中的那一套、别名的怪情况报缺键、单个对象可无名、写出丢两项），和未设置时光标 / 光标下字色取生效的前景 / 底色。
- [ ] **Step 6: 「记现象」表**：加第 98 项（各 widgetset 下系统色解出来的样子，写回 spec §11.1.3）。
- [ ] **Step 7: 截图**：加 `2026-09-30-terminal-phase-6-shots/` 一行（张数、内容一句话、链接 `index.md`）；重新生成加 `terminalshots --phase6`。
- [ ] **Step 8: 自查**：项号连续不重复；1–91 除点名的补句外与改前逐字相同（`git diff` 只在那几行有改动）；每个截图链接指向存在的文件（`ls` 核对）；决定清单每条都有「看哪里」。
- [ ] **Step 9: 提交**

```bash
cd /d/Projects/ty-3.1 && git add docs/superpowers/plans/2026-09-29-terminal-acceptance.md && git commit -m "docs(terminal): phase 6 joins the acceptance sheet

The colour scheme checks follow on from item 91, a few earlier items
gain a line for phase 6, and the light-palette decisions now read
'follows the theme by default; switch to a scheme if it is hard to
read'.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 6 期做完能看到什么

- `tytests` 里本期的两个 suite 全绿：颜色串、预解码、读 WT（30 条输入表、夹具 16 套）、写 WT（键序逐字、往返）与 WT 的规则逐条对上；控件的取色逐槽、OSC 覆盖、996 / 2031、明暗配对、通知次数、加载、禁用、对比度、选区在方案下都对；3–5 期的主题测试一条没改。
- 示例里切到 Solarized Dark，整窗连内边距一起换色，换皮肤不影响它；选「Tango（浅色 / 深色）」再拨暗色开关，终端跟着换；「导入…」一个 WT 的 `settings.json`，里面的方案全出现在下拉里。
- 一份 1–6 期合在一起的验收文档。

---

## 6 期新增的真机验收项（Task 11 并入验收文档，接第 91 项往下编）

截图在 `docs/superpowers/plans/2026-09-30-terminal-phase-6-shots/`。

| # | 项 | 平台 | 怎么验 | 算过 |
|---|---|---|---|---|
| 92 | 示例里切方案 | Win32；GTK2、Qt6、Cocoa 各抽一次 | 「配色」下拉切七套、再切回「跟随主题」；回放 `palette.cast`、`ls-color.cast` | 整窗（连内边距）换成那一套，换皮肤时不跟着变；切回后和以前一样（和 `scheme-*.png` 对照） |
| 93 | 明暗配对 | 各平台 | 选「Tango（浅色 / 深色）」，拨标题栏的暗色开关几次；再换一个深色皮肤 | 浅色主题是 Tango Light、深色是 Tango Dark，拨一次换一次；单模式的深色皮肤也换到深色那套 |
| 94 | 设计器里改方案 | Lazarus IDE（Win32） | 放一个终端，`ColorSource` 改成自定义方案，展开 `ColorScheme` 改几个颜色；存盘、关掉窗体再打开 | 设计期预览跟着变；`.lfm` 里只有改过的几项；重开后颜色还在 |
| 95 | 设计器右键导入导出（Task 7 做了才有） | Lazarus IDE（Win32） | 右键终端「导入 Windows Terminal 配色…」选本机 WT 的 `settings.json`（`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_*\LocalState\settings.json`）挑一套；再「导出配色…」，把导出的文件放进 WT 的 `schemes` 里 | 导入后预览是那一套、窗体标成已修改；导出的方案在 WT 里能选、颜色一样 |
| 96 | 方案下程序改色 | 各平台 | 自定义方案下 Shell 里 `printf '\e]11;#203040\a'`、`printf '\e]4;1;#00ff00\a'`，再 `printf '\e]111\a'`、`printf '\e]104\a'`；开 2031 后切方案（`printf '\e[?2031h'`，看键码面板） | 程序的颜色盖过方案；复位后回到方案的颜色（不是主题的）；切方案时程序设的颜色被清掉、键码面板出一条 `ESC [ ? 997 ; 1 n` / `2 n`，和新方案的底色深浅一致 |
| 97 | 方案下的最低对比度与禁用 | Win32 | Solarized Light 下「最低对比度」切 1 / 4.5；临时把终端 `Enabled := False` | 4.5 下浅色方案里的淡色字变清楚、框线块元素不变；禁用时整块变淡（和 `scheme-contrast-*.png` 对照） |
| 98 | 系统色 | Win32、GTK2、Qt6、Cocoa | 设计器里把方案的背景设成 `clWindow`、前景设成 `clWindowText`，运行 | 颜色是那个平台窗口底色 / 字色；记下各 widgetset 的实际值，写回 spec §11.1.3 |
| 99 | 导入真实的 WT 文件 | Win32 | 示例「导入…」本机 WT 的 `settings.json`（带注释、尾逗号，可能有 BOM）；再导入 `iTerm2-Color-Schemes` 的 `windowsterminal/` 里任意几个文件；再导入一个故意写坏的（删一个颜色） | 能读的都出现在下拉里、颜色和 WT 里一样；坏文件在状态栏报出缺哪个颜色，终端不变 |

---

## 与规格不符之处（核实中发现，Task 10 写回）

1. spec §7.3 的 3 期修正「只有色表真变了（换明暗、换配色）才调」——这里的「换配色」原指主题；6 期起还包括方案（§7.3 的 6 期注已写）。
2. 不是规格错，是一处容易看走眼的地方：spec §11「深底那套用 xterm.js 默认色（Tango）」，而 WT 自带的 Tango Dark 和它**只差 0 号**（WT `#000000`、xterm `#2e3436`，其余 15 色逐个相同，核实时对过）；前景 / 底色两边本来就不同（WT `#D3D7CF` / `#000000`，跟随主题时是皮肤的 surface token）。示例里「Tango Dark」和跟随深色主题时看起来不一样是这个原因，不是 bug——控件文档第 10 节写一句。
3. spec §10.7「块光标下的字用 `TyTerminalCursor` 的 `color` 重画」：方案下改用方案的 `CursorText`、未设时生效的底色（§11.1.4）。

---

## 6 期签收（2026-09-30）

**全量**：集中变异之后 `lazbuild -B` 重编、`--all` 跑一遍：8413 条（审查前 8405，审查修复加 8 条：方案单元 6、控件 1、示例 1），errors 0、failures 1——唯一的红仍是本机 ClearType 环境下的 `TPainterTest.TestTextIsInkedAsWindowsInksIt`（「Segoe UI，96 PPI，浅色：ours 1075 / 0.24，Windows 1203 / 0.37」，和 5 期签收时同一个值，与终端无关）。本期三个 suite：`TTyTerminalColorSchemeTests` 33 条 0.25 s、`TTyTerminalViewSchemeTests` 16 条 6.7 s、`TTyTerminalExampleTests` 11 条 3.5 s。

**提交区间**：`997cb270..HEAD`（Task 1 起）。期末审查的修复在 `4dd29fac..HEAD`：`639a773b` 方案单元（嵌套深度与文件大小的上限、名字去重与两句新消息、导入计划读颜色、`Changed` 公开）、`7e96c022` 控件（没用到的方案改了不整窗失效）、`bdfdd1d8` 设计器（导出先校验、标题去两种省略号）、`899b2ce3` 示例（一对原子、下拉去重、清错误、光标设置）、`afeb61f4` 发版守卫的 `\u0000`、`f2f053ca` 控件文档与截图，以及本签收（spec 写回、验收文档）。

**期末审查的处理**（审查员的编号 → 结果）：
1. **深嵌套 JSON 栈溢出崩进程**：预解码的同一遍扫描里数串外、注释外的方括号与花括号深度，超过 64 层报 `rsTermSchemeBadJson`（内层消息 `rsTermSchemeTooDeep`）；没有 `\u`、原样返回的快路也数（只数不解）；`LoadFromFile` 超过 16 MB 报 `rsTermSchemeTooBig`。公开常量 `TyTermJsonMaxDepth`、`TyTermSchemeMaxFileBytes`。测试：深度 64 能读、65 报错（不带和带 `\u` 各一例，方括号、花括号、混合，串里 / 注释里的不算）；十万层对 `TryLoadFromText`、`ListSchemeNames`、`TyTermSchemeImportPlan` 都答失败、不崩；16 MB + 1 字节的文件。
2. **系统色刷新办法无效**：`TTyTerminalColorScheme.Changed` 改成公开（库里 `TTyStyleController.Changed` 的惯例）：内容没变也加修订号、发 `OnChange`，`BeginUpdate` 里照样攒。控件文档 §3 方法表、系统色一段、§13 改成调它。测试：方案单元一条、控件一条（再设同一个 `clWindow` 不动；`Changed` 加修订号、排通知、整窗失效）。
3. **没用到的方案改了整窗失效**：选了「`SchemeChanged` 只在正在用的那一边时排通知」。另一种（回调里只在键变了才 `Invalidate`）试过又退回：`UpdateGrid` 也会调 `EnsureThemeCurrent` 把新键记下而不失效窗口，回调再比就会漏掉该有的重画。测试：`TestNotificationsComeOncePerChange` 里原来四处「0 条」改用新的 `Quiet`（不排通知、不报、控件的 `Invalidate` 次数不变），加「正在用的一边改了：报一次、失效」「没配对时改 `DarkColorScheme`：什么都不动」。
4. **`Loaded` 清 `FNotifiedValid` 的副作用**：代码不改，写进 spec §11.1.6。
5. **未设光标取「生效前景」不含 OSC 10**：代码不改，spec §11.1.4 表里写清（光标下的字色同理，不含 OSC 11）。
6. **只设底色的方案配浅主题时 16 色仍是浅底那套**：控件文档 §10 提醒一句；验收文档加第 100 项，结论交 D1 或文档。
7. **`ColorScheme := nil` 抛 `EConvertError`**：控件文档属性表注明（同 `Font := nil`），清空用 `Clear`。
8. **报错消息的名字列表**：去重；按名找不到而没有完整方案时换一句（`rsTermSchemeNotFoundNone`），单个对象没名字时另一句（`rsTermSchemeNotFoundUnnamed`）。顺带：`AName = ''` 时按不同的名字数（两套同名、别无其他时取第一套，不再报「要给名字：A, A」）。测试 `TestNameListsNameEachOnce`（7 行）。`.pot` 与 `zh_CN.po` 同步，`en.po` 不需要。
9. **设计器**：导出先 `SaveToText` 校验，不合格当场报错、不弹对话框；对话框标题 `VerbTitle` 同时去掉 `...` 与 `…`；选边的标题跟着是导入还是导出（原来导出也用导入的标题）。设计期单元不在测试构建里：用 fpc 对着已编好的包单独编过这个单元（0 错），包本身待主控编。
10. **示例**：`ColorsChange` 先把一套（一对就两套）读进临时对象，都成功才赋值，失败什么属性都不改；`ImportColorsFrom` 用 `TyTermSchemeImportPlan` 解析一次（导入计划顺带读每一套的颜色，写坏颜色的不列——和原来「逐个试读」的结果一样），下拉按显示名去重（同名那一项改读新文件，再导入同一个文件不增加）；选中或导入成功后清掉之前的错误。测试：一对里深色那套读不进时浅色那套也没设上（新 `TestAPairThatDoesNotLoadChangesNothing`）、再导入 `defaults.json` 条数不变、七套各只一项、成功的选择清掉错误。
11. **`test.release.pas` 的 `'' + 'u0000'`**：改回 `'\' + 'u0000'`。
12. **V11b 静默跳过**：`TestTheDarkSideIsWhatOnCalls` 断言恰好 0.5 的底色存在（本机找到的第一个是 `#00CC44`），不再 `if` 跳过。
13. **示例测试的环境依赖**：新函数 `FoldersOnTheExamplePath` 照示例的找法（exe 旁边再往上 8 层）先查有没有 `colorschemes/`、`recordings/`，有就报出路径（注释说明理由：示例会把路径上任何一个这样的目录当自己的，不查就会在后面的条数上莫名其妙地失败）；只删自己建的目录，删完断言它不在了。
14. **截图**：`terminalshots --phase6` 加 `scheme-selection-inactive-campbell.png`（Campbell 另设失焦选区色 `#00FFFF`，失焦时选区是 `#085555`，前两张是 `#555555`；数像素核过），重跑后另外 17 张逐字节没变，`scheme-follow-*` 仍和从没设过方案的控件、和 3 期 `palette-default-*.png` 都 0 像素差；index 多一行。
15. **O4 重做**：按原意写（`EndUpdate` 每减一层都直接加修订号、发 `OnChange`，绕过 `Changed`）：红，见下表。

另外（用户要求，和本批一起）：示例第五行加光标设置——「Cursor:」下拉（方块 / 下划线 / 竖线 → `CursorStyle`）、「Blink」（`CursorBlink`）、「Unfocused:」下拉（空心框 / 方块 / 竖线 / 下划线 / 不显示 → `CursorInactiveStyle`），写在 `.lfm`，文字走 resourcestring，`FormCreate` 按控件现在的值选中；示例 `.po` / `.json` 同步；「建真主窗体」的测试覆盖到它们。控件文档写清光标默认值由属性定，DECSCUSR（`CSI Ps SP q`，0–6）临时覆盖，`CSI 0 SP q` 与 RIS 回到属性。验收文档第 101 项。

**变异**（脚本：改一处 → 断言命中恰好一次 → `lazbuild` → 跑相关 suite → 还原；全部做完还原后 `-B` 重编跑全量，见上）。审查前 Task 1–9 的变异表不在本仓库的记录里，这里只记审查指定的和本次修正的；O4 按计划的原意（绕过 `Changed` 直接加修订号、发 `OnChange`）重做，以这里为准：

| # | 变异 | 结果 |
|---|---|---|
| 1a | 去掉深度检查 | 红：`TestDeepNestingIsRefused`（第 41 行：深度 65 读成功了）。只跑这一条：带十万层的 `TestVeryDeepNestingDoesNotCrash` 在这个变异下会撑爆栈，不拿进程崩溃当「红」 |
| 1b | 没有 `\u` 的快路不数深度 | 红：`TestDeepNestingIsRefused`（第 41 行，不带转义的那一例） |
| 2 | `Changed` 不加修订号 | 红：`TestChangedIsAChange`、`TestChangedRefreshesASystemColour` 等（方案单元 3 条、控件 6 条） |
| 3 | `SchemeChanged` 不看是不是正在用的一边 | 红：`TestNotificationsComeOncePerChange`（「跟随主题时装方案：不排通知」） |
| 8a | 名字不去重 | 红：`TestNameListsNameEachOnce` |
| 8b | 没有可列的名字时仍用旧句子 | 红：`TestNameListsNameEachOnce`（第 53 行） |
| 8c | 单个对象无名时仍用旧句子 | 红：`TestNameListsNameEachOnce` |
| 8d | 导入计划不读颜色 | 红：`TestTheImportPlanSkipsBadColours` |
| 10a | 示例把浅色那套直接读进终端 | 红：`TestAPairThatDoesNotLoadChangesNothing`（「浅色那套也没设上」） |
| 10b | 示例导入不去重 | 红：`TestTheMainFormBuildsWithARecording`（再导入 17 → 33）、`TestTheColourListOffersSevenAndThreePairs`（20 → 27） |
| 10c | 成功后不清错误 | 红：`TestAPairThatDoesNotLoadChangesNothing`、`TestTheColourListOffersSevenAndThreePairs` |
| 12（V11b） | 明暗判定 `> 0.5` 写成 `>= 0.5` | 红：`TestTheDarkSideIsWhatOnCalls`（`#00CC44`） |
| 15（O4） | `EndUpdate` 每减一层都直接加修订号、发 `OnChange`，绕过 `Changed` | 红：`TestUpdatesAreBatched`（「里层结束不发」期望 1 得 2）、`TestAssignClearAndEquals` |

**写回 spec 的节**（标「实现期修正（6 期）」，推翻的原文删除线保留）：状态行；§7.3（「换配色」含换方案）；§10.7（方案下块光标里的字）；§11（WT 的 Tango Dark 与 xterm.js 默认只差 0 号）；§11.1.1（待定已定）；§11.1.3（属性表的待定 → D20、`Changed`、全空按跟随主题与配对只填深色、`:= nil`）；§11.1.4（258 与光标下字色取色表不含 OSC 10 / 11、D23、只设底色时 16 色跟主题）；§11.1.6（只加选中那一边的修订号、没用到的方案不排通知不失效、`ReadComponent` 的副作用）；§11.1.7（单个 `case` 分支、公开的 `Changed` / 导入计划 / 两个常量、单引号串的 `\u0027`、深度与大小上限、按不同名字数、待定已定）；§11.1.8（两行新错误、名字去重与两句新消息）；§11.1.9（设计器的问改用方案 / 问哪一套 / 导出先校验 / 标题、D21、D22、示例在 `Tools5` 与单独的 `DlgColors`、一对原子、去重、光标设置）；§11.1.10（两条上限、同名算一个名字）；§11.1.11（`en.po` 不改、示例 `.po` 手工补全、rsj2po 复查新增 0）；§11.1.12（WT 文档 Campbell 已逐字核对，2026-09-30；审查加的测试）；§14（notices 的实际标题与 `### Test fixture` 小节）；§15；§16（第 92–101 项、18 张截图）；§17（D20–D23 的结论）；§18（6 期实际做了什么）。

**验收文档**：第 93 项加「开着 2031 拨暗色开关，每拨一次恰好一条 997」；第 95 项加 Ctrl+Z 撤销导入（记现象）、标题没有省略号、没名字或缺色时导出报错不留空文件；第 98 项加改系统配色后调 `Changed`；第 99 项加 `\u` 转义与直接 UTF-8 的中文名、同名只出现一次、再导入不增加、成功后错误消失；新第 100 项（只设底色的方案配浅主题，结论交 D1 或文档）、第 101 项（示例光标设置与 vim 的 DECSCUSR、`CSI 0 SP q`）；平台索引、D1「看哪里」、「记现象」表（95、98、100）、截图 18 张；头提交与全量条数。

**计划外发现**：AdvChart 的 `TyDecodeUnicodeEscapes`（`source/tyControls.AdvChart.Option.pas`）不认注释、会把 `\u0022` / `\u005C` 解成裸字符，也没有嵌套深度上限（AdvChart 的 JSON 同样交给 fpjson 递归解析，很深的嵌套应当同样会撑爆栈；没有实测）。不在本期范围，留给 AdvChart。

**主控已做（922af908 之上）**：`lazbuild -B` 编 `tycontrols.lpk`、`tycontrols_dt.lpk`、终端示例都 0 错；`example-rsj2po.py` 0 新增 0 改动；`check-example-po.py` 101 份 0 问题、`check-lfm-props.py` 通过；启动示例枚举窗口只有主窗体（`TTyTerminalView 示例`）与应用窗口，没有 `#32770`。第五行在中英文下挤不挤是真机项，并入验收第 101 项。原待办：编 `tycontrols.lpk`（运行时单元改了：`Terminal.ColorScheme`、`Terminal`、`StrConsts`）、`tycontrols_dt.lpk`（`designtime/tyControls.Design.CompEditors.pas` 改了），编终端示例（`.lfm` 加了五个控件）；`example-rsj2po.py` 复查示例 `.po`（本次手工补了 5 条 `.lfm` 文字与 5 条 resourcestring，`check-example-po.py` 101 份 0 问题、`check-lfm-props.py` 通过）；启动示例看第五行的光标设置在英文和中文界面下不挤。
