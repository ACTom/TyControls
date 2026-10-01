# 主题编辑器 2 期：种子与联动 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（项目约定，优先于子技能的默认做法）**：整期**连续写完**——每个任务只写代码 + 测试并单独提交，任务之间**不编译、不跑测试**（例外只有 Task 0：基线编译与全量，产出记进草稿）；Task 1–10 写完后在 Task 11 **一次编译**、跑本期 suite 和全量、集中修红、按 spec 逐条核代码、集中变异、期末审查、写回 spec、签收；Task 12 把本期的真机项追加进三期共用的验收文档。中途不汇报、不问要不要提交。**三期做完用户一次性真机验收**。
>
> **谁来做**：标 **【主控执行】** 的步骤实现 agent **不做**、直接跳过：问用户、编 `tycontrols.lpk` / `tycontrols_dt.lpk`、截图、启动 GUI 冒烟。实现 agent 不编任何 `.lpk`。**`tools/themebuilder/themebuilder.lpi` 实现 agent 可以编**（Task 11，编法见「跑测试的固定套路」）。
>
> **共享文件**：本期**不改任何库文件**——`source/` 与 `designtime/` 一个字节都不动（`Base.pas`、`Painter.pas`、`StyleModel.pas`、`TextMenu.pas`、`StrConsts.pas` 更不用说）。本期需要的库能力全部是现成的公开 API（核实记录 3、5、6、7、8）。执行中发现非改库不可，停下交主控，主控先问用户。

**Goal:** 在 1 期的编辑器上接通「种子与联动」：侧栏第一页的种子面板（明暗两列、双向同步、拆成两套、表达式确认、缺种子插入、继承值灰显），预览里 Ctrl+点击跳到或插入规则，覆盖检查两张单子，导出主题包（文件夹 / zip，读回验证、失败不留坏包），「在程序里怎么用」代码片段小窗（从文件、从主题包、注册成命名主题，片段真的编进测试工程）。

**Architecture:** 全部在 `tools/themebuilder/` 里做。一个容错的文本扫描（`tbcssscan`，复用库的 `TTyCssLexer`，把行列换成字节偏移）给出每个 `:root` / `@mode` / 规则块与每条声明的值区间；种子（`tbseeds`）和规则定位（`tbrules`）都在它上面算出「文本改动」（`TTbTextEdits`，只替换值或插入整行，其余字节不动），主窗体把一组改动在 SynEdit 里包成一步撤销。种子的实际颜色由一个**不带密度包**的独立样式模型按列（模式）求值。Ctrl+点击挂在预览每个控件的 `WindowProc` 上，按住 Ctrl 的左键在控件处理之前被截走。覆盖检查用「预览控件自己的 typeKey + 工具里一张『单元 → 子部件 typeKey』表（守卫测试对着源码核）」对「文档规则的 typeKey」与「底层 `TyBuiltinThemeCss` 的规则 typeKey」。导出先写到目标旁边的临时位置，用库的读取端（`TTyThemeDirSource` / `TTyThemeZipSource`）读回、加载进新模型并逐模式试解析，全过才挪到目标，失败全部删掉。

**Tech Stack:** FPC 3.2.2 / Lazarus 4.4 LCL、SynEdit、BGRABitmap、FPC `zipper`（`TZipper`）、`fpjson`、fpcunit（`tests/tytests.lpi`）；Python 3（`scripts/example-rsj2po.py`）。

**设计依据:** `docs/superpowers/specs/2026-10-01-theme-builder-design.md`（下称 spec）§9 第 2 条，细节在 §5.2、§5.3（Ctrl+点击、覆盖检查）、§6（导出、代码片段）、§8（种子扫描、规则定位、覆盖检查、导出）。1 期计划 `docs/superpowers/plans/2026-10-01-themebuilder-phase-1.md`（下称 1 期计划）的格式、约定、硬规则本期照用。

**不在本期**：AI 的一切（3 期，侧栏「AI」页也是 3 期再加）；工具的使用文档与 README（3 期末）；CHANGELOG（发版时写）；合 `main`；库里 zip 主题源对 `@import` / 图片的支持（见开工前问题一第 1 条的另一做法 c）。

---

## 总目录

| 部分 | 任务 | 这一批做完能看到什么（执行时不单独验收） |
|---|---|---|
| 基线 | Task 0 | 起点、全量条数、主控定开工前问题 |
| 文本底子 | Task 1 | 容错扫描：块、声明的值区间、选择器；偏移 ↔ 行列；文本改动 |
| 种子 | Task 2–3 | 种子定位与改写（纯函数）；按列求值；种子面板 frame |
| 规则与 Ctrl+点击 | Task 4–5 | 规则查找 / 插入（纯函数）；预览里按住 Ctrl 点控件得到 typeKey 与变体 |
| 覆盖检查 | Task 6 | 两张单子的算法、子部件表与守卫、对话框 |
| 导出 | Task 7 | 收集引用文件、写文件夹 / zip、读回验证、失败不留痕、导出对话框 |
| 代码片段 | Task 8 | 三种写法（四段）的片段、CSS 转 Pascal 函数、片段编进测试工程的守卫、片段小窗 |
| 主窗体接线 | Task 9 | 侧栏「种子」页、一步撤销、Ctrl+点击跳转与插入、菜单 |
| 双语 | Task 10 | 新增 `.lfm` 与 resourcestring 的中文 |
| 收尾 | Task 11 | 一次编译、全量、按 spec 逐条核、集中变异、主控编包冒烟、审查、写回 spec、签收 |
| 验收文档 | Task 12 | 往三期共用的验收文档追加 2 期各项与决定 |

---

## 核实记录（写计划时读源码，2026-10-01，`feat/theme-builder` @ `ffe4861d`）

**1. 种子在主题文件里的各种写法**

1. `themes/auto.tycss` 的 SEED 段在两个 `@mode` 块里：亮色 `:507-511`，**一行写三个**（`:510` `--accent: #3B82F6; --surface: #FFFFFF; --on-surface: #1F2937;`、`:511` 另外三个）；暗色 `:562-570` 一行一个、冒号后**用空格对齐**（`--accent:     #60A5FA;`）。注释行 `/* ── SEED ── 5 colors + 1 metric */` 在块里（`:509`、`:564`）。所以「替换那一行」必须是「只替换值那一段」，不能整行重写（spec §5.2 的「只替换值」）。
2. 单模式（只有顶层 `:root`）：`themes/light.tycss:4-5`（同一行多个）、`themes/dark.tycss:2-9`、`themes/builtin/showcase.tycss:2-5`。
3. 双模式里种子写在**顶层 `:root`、两种模式共用**：`breeze.tycss:11`（`:root { --accent: #3DAEE9;   --on-titlebar: var(--ink);   /* … */` 与下一行的 `}`，亮 / 暗块里都没有 `--accent`）；`win11.tycss:97`、`:119`（顶层 `:root` 写在两个 `@mode` 块**之后**，含 `--radius: 5px`）；`xp.tycss:10-11`、`fluent.tycss:11-12`（`--radius`）。
4. 只在某一模式里写：`classic.tycss` 亮色块 `:32-48` 没有 `--surface`，暗色块 `:49-68` 有（`:67` 钉成底层亮色值）。
5. 表达式：`aero.tycss:242-243`（`--surface: var(--field-bg);`、`--on-surface: var(--ink);`）；`system.tycss:464`、`:518`（`--accent: system-accent;`，运行时由钩子换成系统强调色）。
6. 一行一个块：`themes/palettes/*.tycss:4-5`（`@mode light { :root { --accent: …; … } }`，暗色那行是 `@mode dark  {` 两个空格）。
7. 同一块里重复声明、注释里的假种子：仓库主题里没有现成例子，按引擎语义处理——同一块（及同一作用域的多个块）里**后写的赢**（`Css.Parser.pas:302-331` `ParseRootInto` 用 `Values[]` 覆盖；`StyleModel.pas` `AddSheetInto` 新值覆盖旧值），注释由词法器跳过（`Css.Lexer.pas` `SkipWhitespaceAndComments`）。
8. 生效顺序（`StyleModel.pas:1199-1238` `RebuildMergedVars`）：底层 `:root` → 底层 `@mode`（**只在用户主题本身是双模式时**叠）→ 用户顶层 `:root` → 当前模式的用户 `@mode` → 系统令牌 → 运行时覆盖。所以某一列（模式）的种子：该模式块里有就用它（最后一条），否则用顶层 `:root` 的（最后一条），否则继承底层。底层的分模式种子只有 `--on-surface`、`--surface`、`--border`（`DefaultTheme.pas:20-31` `TyBuiltinBaseModeCss`），其余三个种子两种模式同值（`TyBuiltinThemeCss` 的 `:root`）。

**2. 有没有可复用的容错扫描、怎么求值**

9. `ThemeLint.pas` 的二次词法走查 `BuildPositions`（`:216` 起）与 `TLintPositions`（`:121`）都在 implementation 里、私有，只记属性名的行列、不记值区间——不能复用，也不改库去公开它。
10. 库的词法器可以直接用：`TTyCssLexer`（`Css.Lexer.pas:11-28`，公开 `Next` / `Peek`）从不抛异常（未闭合字符串读到文末，未知字符出 `ctkDelim`），跳过注释；记号只有 `Line` / `Col`（`Css.Tokens.pas:10-14`），**没有字节偏移**。换算：按词法器同样的断行规则（`Advance`，`:62-85`：LF 断行；单独的 CR 断行；CR 后跟 LF 时 CR 不断）建「每行起点」表，偏移 = 行起点 + `Col` − 1（`Col` 本来就是字节列）。值的结束位置 = 终止它的 `;` / `}` 记号的偏移往回跳过空白与尾随注释（解析器的 `ReadRawValue` 在 `;` 就停、不看括号深度，`Css.Parser.pas:224-300`）。
11. 求值用公开 API：`TTyStyleModel.LoadFromSource`（`StyleModel.pas:1611-1629`）+ `SetMode`（`:1084-1093`）+ `ResolveOverride('color: var(--x);')`（`:1787`，坏值容忍，取 `TextColor`，1 期 `tbeditorlook.pas` 就这样取令牌）+ `ResolveMetric('--radius', 默认)`（`:1156-1191`）。
12. **不用预览控制器求值**（spec §5.2 写的是「经预览控制器求值」）：预览模型一次只在一个模式里，要两列就得来回 `SetMode`；而且「现代」密度包是叠加加载进用户 `:root` 的，里面有 `--radius: 8px`（`DensityPack.pas:27-35`），预览在现代密度下 `--radius` 是 8 而文档写的是 6。所以种子面板自己持有一个 `TTyStyleModel`（构造时装好底层，`StyleModel.pas:937-983`），用和预览一样的主题源（`TTbTextThemeSource`，`url()` / `@import` 按文档目录）加载、**不加**密度包，按列 `SetMode` 求值。写回 spec。

**3. 种子面板放哪、用什么控件**

13. 侧栏现在只有「问题」一页（`tbmain.lfm:50-69`，`SideBar: TTyToolWindowBar` 里一个 `ProblemsWin: TTyToolWindow`）；窗口顺序 = `.lfm` 里的子控件顺序（`ToolWindows.pas:689` 注释），`ActiveIndex` 在 `Loaded` 里应用（`:251`）。「种子」页在 `ProblemsWin` 之前加（spec 的顺序：种子 / 问题 / AI）。图标用 Lucide `palette`（`assets/lucide/codepoints.json` 有）。
14. 预览是运行时建的 frame、放进 `PreviewHost`（`tbmain.pas:191-194`）；种子面板照这个办法：`SeedsWin` 里放 `SeedsHost: TTyPanel`，`FormCreate` 里建 `TTbSeedsFrame` 放进去。
15. 颜色：`TTyColorButton`（`ColorButton.pas:26`）——`ShowText = True` 时画色块加 `#RRGGBB`（`:98`）；点它时**先** `inherited Click`、**再**开 `TySelectColor`（`:326-345`），选定后设 `SelectedColor`；`SelectedColor` 的 setter **任何改动都触发** `OnColorChange`（`:152-169`，流式加载除外）——代码里同步色块时要自己挡住回调。取色对话框是 `TySelectColor`（`Dialogs.Color.pas:109-110`），另有组件 `TTyColorDialog`（`:113`）。颜色转文字有 `TyColorHex`（`ColorButton.pas:20`，`#RRGGBB` 大写、忽略 alpha）；`TTyColor` 是 `$AARRGGBB`（`Types.pas:11`）；主题里 8 位十六进制是合法的（`breeze.tycss` 的 `#0000000F`）。
16. 圆角：`TTySpinEdit`（`SpinEdit.pas:121-156`：`MinValue`、`MaxValue`、`Value`、`OnChange`）。（实现期修正（开工核对）：挂 `OnValueChange`——`OnChange` 对每一次缓冲改动都触发。）

**4. Ctrl+点击**

17. 控件的 typeKey：`ITyStyleable.GetStyleTypeKey`（`Base.pas:14-17`，两个 Ty 基类都实现它，`_AddRef` 返回 −1，`:772-775`），测试里已有 `(B as ITyStyleable).GetStyleTypeKey` 的写法（`tests/test.button.pas:165`）。变体：published 的 `StyleClass`（`Base.pas:322`、`:504`），可以含多个空格分隔的类（`docs/tycss-reference.md` §4.4 第 2 条）；标题栏上的控件运行时会再追加 `on-titlebar`（`TyStyleClassFor`，`Base.pas:680-686`），Ctrl+点击只看 `StyleClass`。
18. 拦截：LCL 每条鼠标消息最后都走控件的 `WindowProc`（`controls.pp:1818`，可写）：窗口化控件由 widgetset 投递；图形控件由父控件 `IsControlMouseMsg`（`wincontrol.inc:4765-4830`）用 `Control.Perform` 转发，`Perform` 调的就是 `WindowProc`（`control.inc:1617-1627`）。所以给预览里每个控件换一个 `WindowProc`：`LM_LBUTTONDOWN` / `LM_LBUTTONDBLCLK` 且按着 Ctrl 时自己处理、不交给原来的，随后那一条 `LM_LBUTTONUP` 也吞掉；其余原样转交。测试里用 `Control.Perform(LM_LBUTTONDOWN, MK_LBUTTON or MK_CONTROL, …)` 就能走真实路径。
19. Ctrl 的判断：`TLMMouse.Keys`（`lmessages.pp:401-413`）里的 `MK_CONTROL`（`lcltype.pp:2856`）。Cocoa 下 Ctrl → `MK_CONTROL`，Cmd → `ssMeta`（`cocoawscommon.pas:238`、`:252-254`、`:311-312`），而 macOS 上 Ctrl+点击是右键的习惯，所以 Darwin 上另认 `ssMeta in GetKeyShiftState`（`controls.pp:2770`）。
20. 点到哪一个：`ControlAtPos` 的标志 `capfAllowDisabled`、`capfAllowWinControls`、`capfRecursive`（`controls.pp:2037-2044`）——禁用的图形控件父控件不会转发（`IsControlMouseMsg` 用的是 `[]`），所以收到消息的控件先用这组标志往下找最深的那个，再往上找最近的实现了 `ITyStyleable` 的祖先。Win32 上禁用的**窗口化**控件根本收不到鼠标消息，「全部禁用」时点它们没反应——真机验收记一条。
21. 嵌套：预览的组合控件里有内部子控件（`TbApplyController` 已经逐层走过它们，`tbpreview.pas:279-312`），挂钩同样逐层走；内部子控件点中后往上找到的最近 Ty 控件就是答案（可能是内部的 Ty 子控件本身，也是对的：它有自己的 typeKey）。子部件 typeKey（页签 `TyTab`、滚动条滑块 `TyScrollThumb` 等）画在控件里面、不是控件，Ctrl+点击拿到的是整个控件的 typeKey（spec「取被点控件的 typeKey」）。样例窗口（`tbpreview.pas:806-814`）建好时一起挂；消息 / 输入对话框是模态、编辑器被挡住，弹出菜单、菜单栏下拉、通知一闪而过，都不挂（开工前问题一第 7 条）。预览顶上的开关条（`Tools`）属于工具，不挂。
22. 选择器写法（`docs/tycss-reference.md` §4.1，`:206-226`）：`类型名 [. 变体] [: 状态]`，逗号列表；解析器 `ParseSelector`（`Css.Parser.pas:195-222`）；`:checked` 是 `:selected` 的别名（`:172-193`）。规则只能在顶层（`@mode` 里只允许 `:root`，1 期金样本 `'@mode dark { TyButton { } }'` 是解析错误）。同名多条是「正序全部应用、后写的逐属性覆盖」（§4.4 `:291-305`、`StyleModel.pas:1270-1288`）。类型名与变体比较不分大小写（`SameText`，同上）。

**5. 覆盖检查**

23. 「底层有没有专门规则」：底层 = `TyBuiltinThemeCss + TyBuiltinBaseModeCss`（`StyleModel.pas:965`），后者只有变量。`TyBuiltinThemeCss` 是公开函数（`DefaultTheme.pas:12`），工具直接用 `TTyCssParser` 解析它、收集每条规则的选择器类型名。**不用** `TyCatalogTypeKeys`：目录是从 `light.tycss` 生成的文档真相（`Css.Catalog.pas:4-5`），而且不含代码解析、底层刻意不定义的 8 个键（`docs/tycss-reference.md` §8.4 `:1126-1141`，如 `TyFormSurface`、`TyListViewLine`）。`TTyStyleModel.UserHasTypeKey`（`:1300`）只看用户层、只认「无变体无状态」的规则，也不合用。
24. 「预览里摆了哪些」：控件自己的 typeKey 只是一部分，子部件 typeKey 是控件在绘制时用字面量解析的（`TabStrip.pas` 的 `'TyTab'`、`ScrollBar.pas` 的 `'TyScrollThumb'`……），还有少数是拼出来的（`ActivityIndicator.pas:167`、`CircularProgress.pas:208` 的 `GetStyleTypeKey + 'Fill'`，`Rating.pas:235` 的 `+ 'Star'`）。模型没有「解析过哪些键」的钩子（`ResolveStyle` 不是虚方法，控件直接调 `ActiveController.Model.ResolveStyle`），不改库就只能在工具里放一张「单元 → 子部件 typeKey」表：运行时对预览里每个控件的类**及其祖先类**取 `ClassType.UnitName`（FPC `TObject.UnitName`，`objpash.inc:252`）查表。表由守卫测试对着源码核：那个单元去掉注释后的字符串字面量里形如 `Ty[A-Z]…` 的（去掉 `'TyControls'`）必须都在表里；表里多出来的必须是 `TyCatalogTypeKeys` 里的键（容许手工补上拼出来的那三个）。写计划时按这个规则扫了一遍，结果就是 Task 6 的表。同一单元里别的控件的键也会被算作「摆了」——只会让第一张单子漏报，不会误报。
25. 「文档写了哪些」：容错扫描的顶层规则块的选择器类型名（`@import` 进来的文件不算，开工前问题二第 5 条）。

**6. 导出主题包**

26. 读取端（`ThemeBundle.pas`）：入口样式表默认 `theme.tycss`（`cTyDefaultThemeEntry`，`:33`）；清单 `theme.json`，字段 `name`、`author`、`version`、`extends`、`entry`、`dualMode`（`:36-45`、`:131-160`；解析失败回落默认、不抛）。目录源 `TTyThemeDirSource`（`AssetBaseDir` = 目录，模型按文件解析 `url()` 与 `@import`，与 `LoadFromFile` 逐字节一致）；zip 源 `TTyThemeZipSource`（`:262-285` 全部解到内存；条目名统一成 `/`、不分大小写、去掉开头的 `/`，`:318-326`；`AssetBaseDir = ''`，`:408-411`）。
27. **zip 源的限制比 spec 以为的大**：单元头（`:15-21`）写明 zip 里的**图片**画不出来（painter 要文件路径）；而 `@import` 也解析不了——模型展开 `@import` 走的是磁盘（`StyleModel.pas:1372-1438` `ExpandSheet`：`FileExists(原路径)` 或 `基准目录 + 路径`），从不调主题源的 `ReadText`，zip 源的基准目录又是空的（`LoadFromSource` `:1617-1621` 的注释也写了）。所以 spec §6「tycss + `url()` / `@import` 引用的文件 + 清单」打成 zip、再用 `TTyThemeZipSource` 读回加载：带 `@import` 的会加载失败，带图片的加载通过但程序里看不到图。开工前问题一第 1 条。
28. 引用文件的解析规则（导出要照运行时的规则收）：`@import` 相对于**导入它的那个文件**所在目录（`ExpandSheet` 每层用自己的目录）；`url()` **一律相对于入口文件的目录**——解析时用的是 `FThemeBaseDir`，即入口文件目录（`StyleModel.pas:490-498` `ResolveAssetPath`、`:1741-1756`），导入文件里的 `url()` 也一样。（`ThemeLint.pas:917` 对导入文件用它自己的目录查缺图——和运行时不一致，是库里的一个小问题，不在本期改，签收记为计划外发现。）`url()` 可以出现在任何值里，包括 `:root` 变量。
29. FPC `zipper`：`TZipper`（`zipper.pp:413`）的 `FileName`、`Entries.AddFileEntry(ADiskFileName, AArchiveFileName)` 与 `AddFileEntry(AStream, AArchiveFileName)`（`:404-407`）、`ZipAllFiles`；测试里已有用法（`tests/test.themebundle.pas:62-84`，归档名用 `/`）。
30. 读回后的加载：`TTyStyleModel.Create` + `LoadFromSource(源)`，再按 `ModeNames`（没有就只试 `''`）逐个 `SetMode` + 1 期的 ~~`TbProbeResolve`（`tbpreview.pas:314-352`）~~ `TbProbeDocument`（实现期修正（开工核对）：1 期期末的快探测 + 引擎定案）——和预览的「加载后试解析」是同一个标准。

**7. 代码片段用到的 API（逐个核过签名）**

31. 从文件：`TTyStyleController.ThemeFile`（published，`Controller.pas:132`；setter `:249-263`，文件存在就 `LoadTheme`）；`LoadTheme(AFileName)`（`:79`、`:583-595`）。文档与示例两种写法都有（`docs/themes.md:113`、`examples/theming/umain.pas:246`、`docs/getting-started.md:142`）。用 `ThemeFile`：换密度时 `ReloadThemeLayer` 按 `ThemeFile` / `ThemeName` 重装（`:359-401`），不会丢。
32. 注册成命名主题：`TyRegisterThemeCss(const AName, ACss: string)`（`ThemeRegistry.pas:43`、`:164-176`）+ `Controller.ThemeName := AName`（`Controller.pas:139`、`:305-319`，`TryApplyThemeName` 先查 CSS 注册表，`:265-293`）。
33. 从主题包：库里**没有**控制器级的「加载主题包」API。文件夹包：`TyRegisterThemeFolder(const AName, ADir: string)`（`ThemeRegistry.pas:30`、`:199-210`）——入口**固定**是 `<ADir>/theme.tycss`，不看清单的 `entry`（所以导出一律用 `theme.tycss` 当入口）——再 `ThemeName := AName`；走文件加载，`url()` 与 `@import` 都按包目录解析。zip 包：`TTyThemeZipSource.Create(zip路径)` 读出 `RootCss`，`TyRegisterThemeCss` 注册、`ThemeName` 切换；不用 `Controller.Model.LoadFromSource` + `Changed`：它不加密度包、不加 `StyleOverride`，而且之后一换密度 `ReloadThemeLayer` 就把它冲掉（`ThemeFile` / `ThemeName` 都空时装空文本）。
34. 片段在窗体的 `OnCreate` 里，末尾 `ApplyChromeTheme(TyDefaultController)`（`TTyForm` 的方法，示例惯例：`examples/toolwindows/umain.pas:204-215`）。卸载注册有 `TyUnregisterTheme`（`ThemeRegistry.pas:52`），测试还原用。

**8. 与 1 期代码的衔接**

35. 文本进出编辑器：1 期新建 / 打开走 `LoadEditor`（`tbmain.pas:321-331`，整篇替换并 `ClearUndo`）；刷新走 `EditorChange` → 300 ms 计时器 → `RefreshNow`（`:458-483`）。无句柄的 SynEdit 在测试里可能不触发 `OnChange`（1 期 F2 的写法，`tests/test.themebuilder.main.pas:169-179`）。
36. 一步撤销：`TCustomSynEdit.BeginUndoBlock` / `EndUndoBlock`（`synedit.pp:930-932`，public）；`SetTextBetweenPoints(起, 止, 文本, [], scamAdjust)`（`:976-983`，逻辑坐标即字节列，内部本身也包一层 undo 块，`:6368-`）；`Undo`（`:1000`）。整篇 `Lines.Text :=` 会让撤销变成「全文替换」——不能用来做局部改动。
37. 编辑器默认开着 `eoTrimTrailingSpaces`（`SYNEDIT_DEFAULT_OPTIONS`，`synedit` 包 `:59-67`；工具的 `.lfm` 与 kit 都没去掉它，kit 只去了 `eoScrollPastEol`，`CssEditKit.pas:87`）——插入空规则时中间那行的两个缩进空格可能被修掉、光标又因为没有 `eoScrollPastEol` 夹到行首。Task 9 的 F24 守这一点，红了的处理写在那里。（实现期修正（开工核对）：1 期 L8 已在工具里关掉它，`ebef1b2d`。）
38. 询问统一走主窗体的 `Ask`（`tbmain.pas:261-270`，测试由 `PromptAnswerForTest` 回答）；frame 要问就通过事件借主窗体的 `Ask`。（实现期修正（开工核对）：`Ask` 1 期期末多了 `AType` 参数，借的是适配 `AskFor`。）
39. 1 期测试里要跟着改的：F1 断言侧栏只有一页（`tests/test.themebuilder.main.pas:155-167`）；F11 的单元清单是写死的十项（`:301-335`）；I1 的 `.lfm` 清单是写死的三个文件（`:535-570` 附近，`LfmKeys(ToolDir + 'tbmain.lfm', …)` 三行）。

**9. 编译与测试工程**

40. 测试工程的搜索路径已含 `../tools/themebuilder`（`tests/tytests.lpi:53`），`SynEdit` 包 1 期已加；新工具单元编进测试只要在 `tests/tytests.lpr` 的 uses 里加测试单元。工具工程 `themebuilder.lpi` 的 `<Units>` 要逐个列（F11 从磁盘问清单）。
41. 起点：`feat/theme-builder` 比 `main` 多 24 个提交、`main` 没有新提交；1 期正在期末审查，之后有少量修复提交——Task 0 以届时的 HEAD 为起点。

---

> **实现期修正（开工核对）**：计划按 `ffe4861d` 核实，1 期期末修复（`77e9d0e0..c0cebbe1`）后来改了 `tbmain`、`tbpreview`、`tbdocument`、`Css.Values`、`ThemeLint`。开工时对着 `f87c46c6` 逐条核对，调整如下（各任务原处另有标注）：
> 1. 主窗体测试编号：1 期期末修复已用到 F28（F19–F28 是期末新增的），本期主窗体判据 F19–F29 顺延为 **F29–F39**（F19→F29 …… F29→F39），集中变异清单同。
> 2. 核实记录 37 / F24：`eoTrimTrailingSpaces` 1 期已关（L8，`ebef1b2d`），F24（现 F34）不再有「红了怎么办」那一支。
> 3. 核实记录 30 / Task 7 Step 4d：1 期期末把试解析改成「快探测 + 引擎定案」（`TbProbeDocument`），读回验证照预览用它，不再单用 `TbProbeResolve`。
> 4. 核实记录 38：1 期期末 `Ask` 多了消息类型参数（`AType`，L6），方法指针对不上 `TTbAskEvent`，主窗体加一个适配 `AskFor(AMsg, AButtons)` 挂给种子页与导出对话框。
> 5. 核实记录 16 / Task 3：圆角微调框挂 `OnValueChange`（值真的变了才触发）而不是 `OnChange`（库里注释写明它对每一次缓冲改动都触发，打一个两位数会先写进一位数）。
> 6. 核实记录 12 / SF7：密度包是叠进用户**顶层** `:root` 的，极简模板把 `--radius` 写在 `@mode` 块里、合并时盖过密度包，所以预览在现代密度下仍是 6px——计划里「先证明是 8」对极简模板不成立。SF7 改用 `TyBuiltinThemeCss`（`--radius` 写在 `:root`）：预览现代下 8、面板 6。
> 7. Task 9 Step 3：`RefreshNow` 调 `UpdateFrom` 时 `FProblems` 还没建（1 期期末拆出了 `BuildProblems`），传的是 `FParseFailed`（即 `TbHasParseError(FLint)`）。
> 8. Task 6：`TbCoverage` 与单元 `tbcoverage` 同名，在用了这个单元的地方被当成单元名，改名 `TbCoverageLists`；子部件表按 CV4 的规则多两行（`HeaderControl`、`Popup`），共 51 行。

## 开工前要定的问题

每条都给了建议，**计划正文按建议写**；改了哪条，执行时改对应任务，Task 11 写回 spec 原处。第一类由主控在 Task 0 决定问不问用户；用户没回复前按建议做（三期一起验收时仍可改，Task 12 把它们写进验收文档的「等你定的决定」）。

> **状态**：未单独询问用户，按建议执行（用户 2026-10-01 以 /goal 指示按计划、开发、验证、修复顺序完成 spec 全部内容），一起验收时可改。

### 一、产品方向 / 用户可见（问用户）

1. **主题包做成什么样。** 库的 zip 读取端解析不了 `@import`、画不出 zip 里的图片（核实记录 27）。**建议**（a）：两种都导——**文件夹包**（`theme.tycss` + `theme.json` + 它引用的文件，保持相对路径）完整可用；**zip 包**只在文档不引用任何文件时可选，否则对话框里灰掉并说明原因。读回验证：文件夹用 `TTyThemeDirSource`，zip 用 `TTyThemeZipSource`（spec 原文）。另两种做法：（b）照 spec 只出 zip——带图片的主题程序里缺图、带 `@import` 的导出即失败；（c）先改库让 zip 源真正支持（解到临时目录、改写路径），库改动，另立项。
2. **引用了文档目录以外的文件怎么办。** **建议**拒绝导出，对话框列出这些引用（绝对路径、路径里有 `..` 段的）请用户挪进主题所在目录。另一做法：复制进包里的 `assets/` 并改写导出副本里的引用（编辑器里的文本不动）。
3. **导出目标已存在。** **建议**：文件夹目标必须不存在或是空目录，否则拒绝（工具不删用户的目录）；zip 目标已存在时问一次是否覆盖。
4. **种子写在顶层 `:root`、两种模式共用时改某一列**（breeze 的 `--accent`，win11 / xp / fluent 的 `--radius`，核实记录 3）。**建议**问一句：「`--radius` 写在 `:root` 里，亮暗共用。选『是』改 `:root`（两种模式都变），选『否』只给亮色加一行。」另一做法：不问，一律只加到这一列的模式块里。
5. **「拆成明暗两套」要不要删掉 `:root` 里原来的种子。** **建议**只插入两个 `@mode` 块（六个种子齐全，暗色先用亮色的值），`:root` 原样不动（spec §5.2「不动别的文本」）；从此 `:root` 里那几行被 `@mode` 盖住。另一做法：顺手删掉 `:root` 里的种子行。
6. **表达式确认的时机。** 库的取色按钮一点就先开取色对话框（核实记录 15）。**建议**：选好颜色、写进文本**之前**确认一次（「`--surface` 现在是表达式 `var(--field-bg)`，改成 `#EEEEEE` 吗？」），选「否」色块退回原色、文本不动。另一做法：工具里派生一个「先问再开对话框」的按钮（要重写 `Click`，绕开库的实现）。
7. **Ctrl+点击的范围。** **建议**：预览八页里的控件 + 样例窗口；消息 / 输入对话框（模态，编辑器被挡住）、弹出菜单、菜单栏下拉、通知不支持；macOS 上 Cmd+点击也算（核实记录 19、21）。子部件（页签、滑块）点到的是整个控件。
8. **Ctrl+点击时同名多条、没有完全对应的规则。** **建议**：只认「类型与变体完全一致、不带状态」的选择器；第一次跳到第一条，再点同一个控件依次跳下一条、循环；一条都没有才在文末插入空规则（带状态的规则不算，`TyButton.primary:hover` 存在也会插入 `TyButton.primary`）。控件的 `StyleClass` 有多个类时依次找，都没有就用第一个类插入。
9. **覆盖检查放哪。** **建议**「视图 → 覆盖检查…」弹一个对话框，两张单子，双击一项跳到（或插入）它的规则。另一做法：侧栏第三页，跟着编辑实时刷新（与 spec §2 第 5 条「种子 / 问题 / AI」三页不符）。
10. **代码片段里「从主题包加载」的写法**（核实记录 33）。**建议**文件夹包、zip 包各给一段：文件夹 `TyRegisterThemeFolder` + `ThemeName`；zip 读出 `RootCss` 再 `TyRegisterThemeCss` + `ThemeName`。都不用 `Model.LoadFromSource`（换密度会被冲掉）。片段小窗仍是三页（从文件 / 从主题包 / 注册成命名主题），「从主题包」一页上下两段。
11. **侧栏默认显示哪页。** **建议**「种子」（第一页）；问题数照旧显示在「问题」图标的角标上。

### 二、实现层面（主控定）

1. **新单元（`tb` 前缀）**：`tbcssscan`（容错扫描、偏移与行列、文本改动）、`tbseeds`（种子定位、改写、按列求值）、`tbseedsframe`（种子面板，frame）、`tbrules`（规则查找与插入）、`tbpick`（Ctrl+点击挂钩）、`tbcoverage`（覆盖检查算法与子部件表）、`tbcoverageform`（对话框）、`tbexport`（收集、写、读回、提交）、`tbexportform`（对话框）、`tbsnippets`（片段文本、CSS 转 Pascal 函数）、`tbsnippetsform`（小窗）。spec §4 的 `useeds` / `urules` / `uexport` 写回为这些名字。
2. **所有改文本的地方都算出 `TTbTextEdits`**（按偏移升序、不重叠），主窗体一个入口 `ApplyEdits` 在 `BeginUndoBlock` / `EndUndoBlock` 里从后往前 `SetTextBetweenPoints`；入口先比对「算改动时扫的文本」与编辑器当前文本，不一样就不改（陈旧保护）；frame 在算改动之前先让主窗体把待刷新的刷新掉（`OnSync`）。
3. **种子求值用独立模型**（核实记录 12），和预览同一个主题源、不带密度包。
4. **文档解析不了时种子面板整页禁用**，顶上一行说「先修好问题列表里的错误」（不显示上一版的值：值区间可能已经对不上）。
5. **覆盖检查只看入口文档**：`@import` 进来的文件里的规则不算「文档写了」（第二张单子可能因此多报）；写进验收文档的「与规格不符」。
6. **子部件表 + 守卫**（核实记录 24）。
7. **片段的编译守卫**：测试单元里放四段片段的真代码（一个 `TTyForm` 子类的方法）与极简模板生成的 Pascal 函数，前后用 `// >>> 名字` / `// <<< 名字` 标出；测试读自己的源文件，逐行（去行尾空白）与 `TbSnippetBody` / `TbPascalCssFunction` 的输出比；「注册」那一段真的执行一次（事后还原）。片段改了而测试单元没跟着改 = 红；测试单元编不过 = tytests 编不过。
8. **测试缝**：询问照旧走 `PromptAnswerForTest`；种子面板在测试里直接设色块的 `SelectedColor` / 调 `ApplyValue`；三个对话框只 `Create` + 准备、从不 `ShowModal`，导出目标直接写进对话框的编辑框；Ctrl+点击用 `Perform` 发消息。
9. **导出包里的 `theme.tycss`** = 「现在保存会写出的字节」：`TbJoinLines(Editor.Lines, 文档换行符, 文末换行)`，不带 BOM。

---

## 需要改共享文件的地方

**库：无。** `source/`、`designtime/`、`tycontrols.lpk`、`tycontrols_dt.lpk`、`languages/` 本期都不碰。

**非库的共用文件：** `tests/tytests.lpr`（uses 随各任务加）、`tests/test.themebuilder.main.pas`（1 期的 F1、F11、I1 跟着改，Task 9；新增 F19–F29）、`tools/themebuilder/themebuilder.lpi`（`<Units>` 随各任务加）、`tools/themebuilder/tbmain.pas` / `.lfm`（Task 9）、`tools/themebuilder/tbpreview.pas`（Task 5、6）。

---

## 接口清单（全计划用这一套名字）

```pascal
{ tbcssscan.pas }
type
  TTbBlockKind = (tbkRoot, tbkModeRoot, tbkRule);

  TTbDecl = record
    Name: string;                 { as written: '--accent', 'background' }
    NameStart: Integer;           { 1-based byte offset of the name }
    ValueStart, ValueEnd: Integer;{ the value is Text[ValueStart .. ValueEnd-1]; blanks and
                                    comments before the ';' are not part of it }
    StopAt: Integer;              { the ';' that ends it; 0 when a '}' or the end did }
  end;

  TTbSelectorRef = record
    TypeName, Variant, State: string;   { State lower case, '' = none }
    Start: Integer;                     { offset of the type name }
  end;

  TTbBlock = class
  public
    Kind: TTbBlockKind;
    Mode: string;          { tbkModeRoot: the @mode name, lower case }
    ModeStart: Integer;    { tbkModeRoot: the '@' of its @mode; 0 otherwise }
    OuterClose: Integer;   { tbkModeRoot: the @mode block's own '}'; 0 when missing }
    HeadStart: Integer;    { ':' of :root, or the first selector's first byte }
    OpenBrace: Integer;
    CloseBrace: Integer;   { 0: the text ends first }
    Selectors: array of TTbSelectorRef;  { tbkRule }
    Decls: array of TTbDecl;
  end;

  TTbCssScan = class
  public
    Text: string;
    ImportEnd: Integer;    { one past the last top-level @import's ';' (0: none) }
    constructor Create;
    destructor Destroy; override;
    function Count: Integer;
    function Block(AIndex: Integer): TTbBlock;
    function HasModes: Boolean;                        { some tbkModeRoot block }
    function DeclValue(ABlock, ADecl: Integer): string;
  end;

  TTbTextEdit = record
    Start, Stop: Integer;  { replace Text[Start .. Stop-1]; Start = Stop inserts }
    Text: string;
  end;
  TTbTextEdits = array of TTbTextEdit;   { ascending, never overlapping }
  TTbOffsets = array of Integer;

{ a forgiving walk: never raises, whatever the text }
function TbScanCss(const AText: string): TTbCssScan;
{ AOffset (1-based, may be Length+1) -> Point(byte column, line), lines broken as the tycss
  lexer breaks them (LF, CRLF, a lone CR) -- SynEdit's logical caret }
function TbOffsetToPoint(const AText: string; AOffset: Integer): TPoint;
function TbLineStart(const AText: string; AOffset: Integer): Integer;
function TbLineIndent(const AText: string; AOffset: Integer): string;
{ where "append at the end" goes: before a final line break, else Length+1 }
function TbEndInsertPos(const AText: string): Integer;
function TbDetectEol(const AText: string): string;    { the first break as written; LineEnding when none }
function TbEdit(AStart, AStop: Integer; const AText: string): TTbTextEdit;
function TbApplyEdits(const AText: string; const AEdits: TTbTextEdits): string;

{ tbseeds.pas }
const
  TbSeedCount = 6;
  TbSeedNames: array[0..TbSeedCount - 1] of string =
    ('accent', 'surface', 'on-surface', 'border', 'danger', 'radius');
  TbRadiusSeed = 5;
type
  TTbSeedSource = (tssOwn, tssShared, tssInherited);
  TTbSeedCell = record
    Seed: Integer;
    Column: string;          { '' = a one-mode document; 'light' / 'dark' }
    Source: TTbSeedSource;   { tssShared: only in the top-level :root of a two-mode document }
    Block, Decl: Integer;    { the declaration that counts; -1 when inherited }
    Raw: string;             { as written; '' when inherited }
    IsExpression: Boolean;
  end;
function TbSeedColumns(AScan: TTbCssScan): TStringArray;       { [''] or ['light', 'dark'] }
function TbSeedCell(AScan: TTbCssScan; ASeed: Integer; const AColumn: string): TTbSeedCell;
function TbIsLiteralSeedValue(ASeed: Integer; const ARaw: string): Boolean;
function TbColorText(AColor: TTyColor): string;                { '#RRGGBB'; '#RRGGBBAA' when not opaque }
function TbRadiusText(APx: Integer): string;                    { '6px' }
{ AShared: for a tssShared cell, True = change the :root value, False = add to the column's block.
  nil when there is nowhere to put it (a block that never closes). }
function TbSeedSetEdits(AScan: TTbCssScan; const AEol: string; ASeed: Integer;
  const AColumn, AValue: string; AShared: Boolean): TTbTextEdits;
{ a one-mode document -> two @mode blocks with the six seeds (AValues[seed]); nil for a two-mode one }
function TbSplitModesEdits(AScan: TTbCssScan; const AEol: string;
  const AValues: array of string): TTbTextEdits;
type
  TTbSeedEval = class
  public
    constructor Create;
    destructor Destroy; override;
    { the text over the base, as the preview loads it but without a density pack; False: it does not load }
    function Load(const AText, ABaseDir: string): Boolean;
    function Color(ASeed: Integer; const AColumn: string; out AColor: TTyColor): Boolean;
    function Radius(const AColumn: string; out APx: Integer): Boolean;
  end;

{ tbseedsframe.pas }
type
  TTbAskEvent = function(const AMsg: string; AButtons: TMsgDlgButtons): TModalResult of object;
  TTbEditsEvent = procedure(Sender: TObject; const AText: string;
    const AEdits: TTbTextEdits) of object;
  TTbSeedsFrame = class(TFrame)
    { .lfm: Task 3 }
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure UpdateFrom(const AText, ABaseDir: string; ABroken: Boolean);
    { the one way a value gets into the text: sync, confirm, compute, hand over. False: nothing changed }
    function ApplyValue(ASeed, AColumnIndex: Integer; const AValue: string): Boolean;
    function SplitModes: Boolean;
    function Cell(ASeed, AColumnIndex: Integer): TTbSeedCell;
    function ResolvedText(ASeed, AColumnIndex: Integer): string;  { '#RRGGBB' / '6px' / '' }
    function Swatch(ASeed, AColumnIndex: Integer): TTyColorButton;   { FOR THE TESTS }
    function Note(ASeed, AColumnIndex: Integer): TTyLabel;           { FOR THE TESTS }
    function RadiusSpin(AColumnIndex: Integer): TTySpinEdit;         { FOR THE TESTS }
    property Columns: TStringArray read FColumns;
    property Broken: Boolean read FBroken;
    property ScannedText: string read FText;
    property OnEdits: TTbEditsEvent read FOnEdits write FOnEdits;
    property OnAsk: TTbAskEvent read FOnAsk write FOnAsk;
    property OnSync: TNotifyEvent read FOnSync write FOnSync;
  end;

{ tbrules.pas }
function TbSelectorText(const ATypeKey, AVariant: string): string;   { 'TyButton.primary' }
{ offsets of the selectors that are exactly ATypeKey[.AVariant] with no state, text order }
function TbFindRuleSelectors(AScan: TTbCssScan; const ATypeKey, AVariant: string): TTbOffsets;
{ an empty rule at the end; ACaret: where the caret goes in TbApplyEdits(AScan.Text, Result) }
function TbNewRuleEdits(AScan: TTbCssScan; const AEol, ATypeKey, AVariant: string;
  out ACaret: Integer): TTbTextEdits;

{ tbpick.pas }
type
  TTbPickEvent = procedure(Sender: TObject; const ATypeKey, AStyleClass: string) of object;
  TTbPicker = class(TComponent)
  public
    procedure HookTree(ARoot: TWinControl);   { ARoot and every control under it, once each }
    procedure UnhookAll;
    function HookCount: Integer;              { FOR THE TESTS }
    property OnPick: TTbPickEvent read FOnPick write FOnPick;
  end;
function TbIsPickMessage(const AMsg: TLMessage): Boolean;
{ the deepest control at APos (AControl's client coordinates), disabled ones too, then up to
  the nearest one with a typeKey; nil when none }
function TbPickTarget(AControl: TControl; const APos: TPoint): TControl;

{ tbpreview.pas（加） }
    procedure CollectTypeKeys(ADest: TStrings);      { what the preview shows, sub-parts included }
    property Picker: TTbPicker read FPicker;         { FOR THE TESTS }
    property OnPick: TTbPickEvent read FOnPick write FOnPick;

{ tbcoverage.pas }
procedure TbDocTypeKeys(AScan: TTbCssScan; ADest: TStrings);
procedure TbBaseTypeKeys(ADest: TStrings);
function TbPartKeysOfUnit(const AUnit: string): string;       { comma list, '' when no row }
procedure TbPartKeysOfClass(AClass: TClass; ADest: TStrings); { its unit's row and every ancestor's }
function TbPartKeyUnits: TStringArray;                          { FOR THE TESTS }
procedure TbCoverage(ADoc, APreview, ABase, ANotShown, ADefaultLook: TStrings);

{ tbcoverageform.pas }
type
  TTbCoverageForm = class(TTyForm)
  public
    procedure Fill(ANotShown, ADefaultLook: TStrings);
    property Chosen: string read FChosen;    { the typeKey double-clicked; '' = none }
  end;

{ tbexport.pas }
type
  TTbBundleFormat = (tbfFolder, tbfZip);
  TTbBundleFile = record
    Source: string;     { on disk, expanded }
    Archive: string;    { in the bundle, '/' separated, as the text refers to it }
  end;
  TTbBundleFiles = array of TTbBundleFile;
  TTbBundleInfo = record
    Name, Author, Version: string;
    DualMode: Boolean;
  end;
function TbCollectBundleFiles(const AText, ABaseDir: string; out AFiles: TTbBundleFiles;
  out AError: string): Boolean;
function TbManifestJson(const AInfo: TTbBundleInfo): string;
function TbExportBundle(const AEntry: string; const AFiles: TTbBundleFiles;
  const AInfo: TTbBundleInfo; AFormat: TTbBundleFormat; const ATarget: string;
  out AError: string): Boolean;

{ tbexportform.pas }
type
  TTbExportForm = class(TTyForm)
  public
    procedure Prepare(const AEntry, ABaseDir, AName: string; ADualMode: Boolean);
    function DoExport(out AError: string): Boolean;
    property Files: TTbBundleFiles read FFiles;
    property CollectError: string read FCollectError;
    property OnAsk: TTbAskEvent read FOnAsk write FOnAsk;   { "replace the zip?" }
  end;

{ tbsnippets.pas }
type
  TTbSnippetKind = (tsnFile, tsnFolder, tsnZip, tsnRegister);
function TbSnippetThemeName(const AFileName, ABasedOn: string): string;
function TbSnippetUses(AKind: TTbSnippetKind): string;          { 'tyControls.Controller, ...' }
function TbSnippetBody(AKind: TTbSnippetKind; const AName, AFileName: string): string;
function TbPascalCssFunction(const AFuncName, ACss: string): string;
{ what the window shows: the uses line, where it goes, (the function,) the body }
function TbSnippet(AKind: TTbSnippetKind; const AName, AFileName, ACss: string): string;

{ tbsnippetsform.pas }
type
  TTbSnippetsForm = class(TTyForm)
  public
    procedure Prepare(const AName, AFileName, ACss: string);
  end;

{ tbmain.pas（加） }
    function ApplyEdits(const AText: string; const AEdits: TTbTextEdits): Boolean;
    procedure JumpToRule(const ATypeKey, AStyleClass: string);
    function BuildCoverageForm: TTbCoverageForm;     { filled, not shown }
    function BuildExportForm: TTbExportForm;         { prepared, not shown }
    function BuildSnippetsForm: TTbSnippetsForm;     { prepared, not shown }
    function EntryBytes: string;                     { what Save would write, without a BOM }
    function SnippetName: string;
    property Seeds: TTbSeedsFrame read FSeeds;
```

---

## 文件清单

| 文件 | 本期做什么 |
|---|---|
| `tools/themebuilder/tbcssscan.pas`、`tests/test.themebuilder.scan.pas`（`TTbCssScanTests`，Task 4 再加 `TTbRulesTests`） | **新建**（Task 1） |
| `tools/themebuilder/tbseeds.pas`、`tests/test.themebuilder.seeds.pas`（`TTbSeedEditTests`，Task 3 再加 `TTbSeedsFrameTests`） | **新建**（Task 2） |
| `tools/themebuilder/tbseedsframe.pas`、`tbseedsframe.lfm` | **新建**（Task 3） |
| `tools/themebuilder/tbrules.pas` | **新建**（Task 4） |
| `tools/themebuilder/tbpick.pas`、`tests/test.themebuilder.pick.pas`（`TTbPickTests`，Task 6 再加 `TTbCoverageTests`） | **新建**（Task 5） |
| `tools/themebuilder/tbpreview.pas` | 改（Task 5、6） |
| `tools/themebuilder/tbcoverage.pas`、`tbcoverageform.pas`、`tbcoverageform.lfm` | **新建**（Task 6） |
| `tools/themebuilder/tbexport.pas`、`tbexportform.pas`、`tbexportform.lfm`、`tests/test.themebuilder.export.pas`（`TTbExportTests`） | **新建**（Task 7） |
| `tools/themebuilder/tbsnippets.pas`、`tbsnippetsform.pas`、`tbsnippetsform.lfm`、`tests/test.themebuilder.snippets.pas`（`TTbSnippetsTests`） | **新建**（Task 8） |
| `tools/themebuilder/tbmain.pas`、`tbmain.lfm`、`tests/test.themebuilder.main.pas` | 改（Task 9、10） |
| `tools/themebuilder/themebuilder.lpi` | `<Units>` 随 Task 1–8 加 |
| `tools/themebuilder/languages/themebuilder.zh_CN.po`、`themebuilder.zh_CN.json` | 改（Task 10；代码条目 Task 11 跑脚本补） |
| `tests/tytests.lpr` | uses 随各任务加 |
| `docs/superpowers/specs/2026-10-01-theme-builder-design.md` | 只在 Task 11 写回 |
| `docs/superpowers/plans/2026-10-01-themebuilder-acceptance.md` | 改（Task 12） |

**不碰**：`source/`、`designtime/`、两个 `.lpk`、库的 `languages/`、`themes/`、`README*`、`CHANGELOG*`、`scripts/`。

---

## 实现期的地雷（每个任务开工前看一眼）

1 期计划「实现期的地雷」1–19 条全部照旧（不 amend / rebase / reset / stash；不用 `sed -i`；只按 PID 结束进程；FPC `{ }` 注释会嵌套——注释里的 CSS 花括号写成 `( )` 或用 `//`；`.lfm` 规矩；自绘 UI 里不用裸 LCL 控件；视觉值走主题令牌；聚焦用 `CanSetFocus`；默认控制器的监听要摘；测试不弹任何窗；新单元进清单；工具单元英文注释、用户可见文字全部 resourcestring 或 `.lfm`；SynEdit 的列是字节列；单跑绿全量红先 `lazbuild -B`；手编带 `-FU`）。本期另加：

20. **文本改动只替换值、只插入整行或整块**：任何路径都不重写整行、不重排、不动注释；测试里「其余字节不变」用「改动前后去掉改动区间后逐字节相等」来断言，不用肉眼。
21. **偏移是字节、从 1 开始、针对「算改动时扫的那份文本」**：编辑器的 `Lines.Text` 用平台换行符（Windows 上 CRLF），扫描、算改动、换成行列都用同一份字符串；改动一律从后往前应用。
22. **色块、微调框在代码里同步时挡住回调**（`FUpdating`）：`TTyColorButton.SelectedColor` 的 setter 任何改动都触发 `OnColorChange`（核实记录 15），`TTySpinEdit.Value` 同理——漏挡的症状是一刷新就往文本里写一遍。
23. **挂钩要能摘干净**：`UnhookAll` 只在控件的 `WindowProc` 还是我们的时候才还原；控件先于挂钩被释放时（样例窗口）靠 `FreeNotification` 丢掉记录、不碰它。frame 析构第一件事 `FPicker.UnhookAll`。
24. **拦下的点击不能再交给控件**：按住 Ctrl 的按下与随后那次抬起都不调原来的 `WindowProc`；没按 Ctrl 的一律原样转交（别的消息更是）。
25. **导出不许留下半个包**：任何失败路径都删掉临时目录 / 文件；目标只在读回验证通过之后才出现；原来就有的 zip 目标失败后逐字节不变。测试里所有目标都在测试自己的临时目录。
26. **片段里的每个名字都要编得过**：改 `TbSnippetBody` 就要同步改 `tests/test.themebuilder.snippets.pas` 里的真代码（守卫会红）。
27. **不往 `tests/` 目录写文件**（测试 exe 所在目录）：片段测试不执行「从文件 / 从主题包」那三段（它们读 exe 旁边的文件）。

---

## 跑测试的固定套路（只在 Task 0 与 Task 11 跑）

exe 用唯一名 `tytests-tb2.exe`。

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi > /tmp/tb2-build.txt 2>&1 || { tail -30 /tmp/tb2-build.txt; false; } && cd tests && cp tytests.exe tytests-tb2.exe && for s in $SUITES; do ./tytests-tb2.exe --suite=$s --format=plain > /tmp/tb2-$s.txt 2>&1; printf '%s: ' $s; grep -E "Number of (run tests|errors|failures|ignored)" /tmp/tb2-$s.txt | tr '\n' ' '; echo; done
```

`SUITES` = `TTbCssScanTests TTbRulesTests TTbSeedEditTests TTbSeedsFrameTests TTbPickTests TTbCoverageTests TTbExportTests TTbSnippetsTests TTbMainFormTests TTbPreviewTests TTbProblemsTests TTbDocumentTests TTbSettingsTests TTbTemplatesTests TTbCssEditKitTests TTbLintExTests TTbParserPosTests TThemeLintGoldenTests TThemeBundleTest TControllerTest TCssCatalogTest TI18NTest TReleaseManifestTest`

**判据是每个 suite 那一行都有 `Number of run tests`、errors / failures 为 0**，不是 exit code。某一行为空 = 跑丢了，重跑。

全量（输出必须重定向到文件）：

```bash
cd /d/Projects/ty-3.1/tests && ./tytests-tb2.exe --all --format=plain > /tmp/tb2-all.txt 2>&1; grep -E "Number of (run tests|errors|failures|ignored)" /tmp/tb2-all.txt
```

**编工具**（实现 agent 可以做，只在 Task 11）：

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tools/themebuilder/themebuilder.lpi > /tmp/tb2-tool.txt 2>&1; tail -3 /tmp/tb2-tool.txt; grep -ci "components.synedit.*Compiling\|Compiling.*synedit" /tmp/tb2-tool.txt
```

Expected：0 错；最后一个数是 0（没有去重编 Lazarus 目录里的 SynEdit）。

---

## 关于判据和变异

同 1 期计划同名一节：纯函数给**输入 / 期望表**，frame、窗体、对话框写**判据**；每条写明「**在哪个变异下必须红**」，期末集中做（改一行 → `git diff --stat` 确认改到 → `lazbuild -B` → 跑相关 suite → 必须红 → 改回 → 重编重跑 → 绿）；接线类变异每类至少一条（事件没挂、挂钩没装、刷新没接、撤销块没包）；断言里那个量要真的变过（「面板跟着文本变」之前先证明两份文本的值不同；「预览在现代密度下是 8」之前先证明经典下是 6）；标「—」的不做变异，理由写在表里。

---

### Task 0: 起点、基线、开工前问题

**Files:** 无（只读、只跑）

- [ ] **Step 1: 【主控执行】开工前问题一的十一条**：主控决定问不问用户；问了就把答复写进「开工前要定的问题」开头的「状态」引用块；没问或没回复就写「按建议执行」。答复与建议不同的：第 1 条选（b）→ Task 7 去掉文件夹格式、对话框只有 zip；选（c）→ 停下，库改动另立项。第 2 条选「复制并改写」→ Task 7 的 `TbCollectBundleFiles` 改成返回「重写表」、导出副本按表改写。第 4 条选「不问」→ Task 3 的 `ApplyValue` 对 `tssShared` 一律 `AShared := False`。第 5 条选「删掉」→ Task 2 的 `TbSplitModesEdits` 多出删除改动（逐条声明从 `NameStart` 删到 `StopAt` 之后的同行空白；整行只剩空白时连行尾换行一起删）。第 8 条改了→ Task 4 / Task 9 的查找规则照改。第 9 条选「侧栏」→ Task 6 的对话框改成 frame、放进侧栏第二页。

- [ ] **Step 2: 确认起点**

```bash
cd /d/Projects/ty-3.1 && git status --short && git branch --show-current && git log --oneline -1 && git log --oneline feat/theme-builder..main | wc -l && grep -n "^## 签收" -A5 docs/superpowers/plans/2026-10-01-themebuilder-phase-1.md | head -8
```

Expected：工作区干净，分支 `feat/theme-builder`；`main` 没有新提交（有的话停下交主控）；1 期计划末尾的签收已填（没填 = 1 期还没收尾，停下交主控）。

- [ ] **Step 3: 基线编译与全量**（本任务的例外，实现 agent 做）：「跑测试的固定套路」的编译 + 全量。条数与红名单记进草稿，Task 11 签收时写进本计划末尾。**除 1 期签收里记的已知项外有别的红就停。**

---

### Task 1: 容错扫描、偏移与行列、文本改动

**Files:**
- Create: `tools/themebuilder/tbcssscan.pas`、`tests/test.themebuilder.scan.pas`（suite `TTbCssScanTests`）
- Modify: `tools/themebuilder/themebuilder.lpi`（`<Units>` 加一项）、`tests/tytests.lpr`（uses 加 `test.themebuilder.scan`）

- [ ] **Step 1: 单元头注释**（英文）：为什么有它——种子面板与 Ctrl+点击要在文本里找到「某条声明的值」「某条规则的选择器」并只改那一段，而解析器不保留位置、lint 的位置走查是私有的；做法——用库的 `TTyCssLexer`（注释、字符串与解析器认得一模一样），把记号的行列换成字节偏移；**永不抛异常**：写坏的文本照样扫，扫到哪算哪。

- [ ] **Step 2: 类型与声明**：照接口清单 `tbcssscan.pas` 一节。`TTbCssScan` 拥有它的块（`TFPList`，析构时逐个释放）。

- [ ] **Step 3: 行起点与偏移**：

```pascal
{ where each line starts, broken exactly as TTyCssLexer.Advance breaks them: LF; a lone CR;
  CR+LF once. Index = line number (1-based); starts[1] = 1. }
function LineStarts(const AText: string): TTbOffsets;
var
  i, n: Integer;
begin
  SetLength(Result, 64);
  Result[0] := 0;
  Result[1] := 1;
  n := 1;
  for i := 1 to Length(AText) do
    if (AText[i] = #10) or ((AText[i] = #13) and ((i = Length(AText)) or (AText[i + 1] <> #10))) then
    begin
      Inc(n);
      if n >= Length(Result) then
        SetLength(Result, Length(Result) * 2);
      Result[n] := i + 1;
    end;
  SetLength(Result, n + 1);
end;

function TbOffsetToPoint(const AText: string; AOffset: Integer): TPoint;
var
  starts: TTbOffsets;
  y: Integer;
begin
  starts := LineStarts(AText);
  if AOffset < 1 then AOffset := 1;
  if AOffset > Length(AText) + 1 then AOffset := Length(AText) + 1;
  y := High(starts);
  while (y > 1) and (starts[y] > AOffset) do
    Dec(y);
  Result := Point(AOffset - starts[y] + 1, y);
end;
```

  `TbLineStart` 用同一张表；`TbLineIndent` = 该行起点起连续的空格与制表符；`TbEndInsertPos`：以 `#13#10` 结尾 → `Length − 1`，以 `#10` 或 `#13` 结尾 → `Length`，否则 `Length + 1`；`TbDetectEol` = 第一个换行的原样（`#13#10` / `#10` / `#13`），没有换行时 `LineEnding`。`TbEdit` 只是填记录。`TbApplyEdits` 从最后一个往前 `Copy` 拼接（先断言升序不重叠，违反时原文返回——测试会抓）。

- [ ] **Step 4: 扫描**。记号偏移 = `starts[tok.Line] + tok.Col − 1`（行号越界给 `Length + 1`，`ctkEOF` 正好落在这里）。值的结束：

```pascal
{ one past the value's last byte, walking back from the token that ended it over blanks and
  trailing comments -- never before AStart }
function ValueEndBefore(const AText: string; AStart, AStop: Integer): Integer;
var
  p, q: Integer;
begin
  p := AStop;
  while True do
  begin
    while (p > AStart) and (AText[p - 1] in [' ', #9, #10, #13]) do
      Dec(p);
    if (p - 2 >= AStart) and (AText[p - 1] = '/') and (AText[p - 2] = '*') then
    begin
      q := p - 3;
      while (q >= AStart) and not ((AText[q] = '/') and (AText[q + 1] = '*')) do
        Dec(q);
      if q < AStart then Break;
      p := q;
    end
    else
      Break;
  end;
  Result := p;
end;
```

  走法（一个 `TTyCssLexer`，一个顶层循环，`try … except` 包住整个函数：出任何异常就返回已经扫到的部分）：
  - `ctkEOF` → 结束。
  - `ctkAtKeyword`：`import` → 取到 `ctkSemicolon`（或 EOF），是分号就 `ImportEnd := 偏移 + 1`；`mode` → `ReadMode`；其他 → `SkipStatementOrBlock`（取到深度 0 的 `;`，或把遇到的第一个 `{ … }` 按深度整块跳过）。
  - `ctkColon` 且下一个是 `ctkIdent` `root`（不分大小写）且再下一个是 `ctkLBrace` → 新块 `tbkRoot`，`HeadStart` = 冒号偏移，`ReadDecls`。
  - `ctkIdent` → `ReadRule`：选择器 = 类型名 [`ctkDot` + 标识符 → `Variant`] [`ctkColon` + 标识符 → `State`（小写）]，`ctkComma` 后接下一个；遇 `ctkLBrace` → `ReadDecls`、块入表；遇别的（`;`、`}`、EOF）→ 丢掉这个块，按 `SkipStatementOrBlock` 继续。
  - 其他（游离的 `}` 等）→ 忽略。
  - `ReadMode(at)`：取模式名（标识符，小写；不是标识符就当未知 at 规则跳过），取 `{`；内层循环：`}` → 记 `outer`、结束；EOF → `outer := 0`、结束；`:` + `root` + `{` → 新块 `tbkModeRoot`（`Mode`、`ModeStart` = `@` 的偏移、`HeadStart` = 冒号偏移），`ReadDecls`；`{` → 按深度整块跳过；其余忽略。结束后把 `outer` 写进这次建的每个块的 `OuterClose`。
  - `ReadDecls(B)`：`OpenBrace` = `{` 的偏移；循环看 `Peek`：`}` → `CloseBrace`、取走、返回；EOF → `CloseBrace := 0`、返回；`ctkIdent` → 取走当名字，下一个不是 `:` 就继续循环（不记）；是 `:` → 取走，`ValueStart` = `Peek` 的偏移，一直取到 `Peek` 是 `;` / `}` / EOF，`ValueEnd := Max(ValueStart, ValueEndBefore(text, ValueStart, 终止记号偏移))`，是 `;` 就 `StopAt` = 它的偏移并取走；记进 `B.Decls`；其他记号 → 取走。
  - `DeclValue` = `Copy(Text, ValueStart, ValueEnd − ValueStart)`；`HasModes` = 有 `tbkModeRoot` 块。

- [ ] **Step 5: 判据测试**（`TTbCssScanTests`；多行输入用 `#10` 等显式写出；「值」指 `DeclValue`）：

| # | 输入 | 期望 | 在哪个变异下必须红 |
|---|---|---|---|
| C1 | `':root { --a: #111; --b: 2px; }'` | 1 块 `tbkRoot`，`HeadStart = 1`、`OpenBrace = 7`、`CloseBrace = 30`；声明 `--a`（`NameStart 9`、`ValueStart 14`、`ValueEnd 18`、`StopAt 18`）、`--b`（`20`、`25`、`28`、`28`） | 偏移少算 1（`+ Col` 不减 1） |
| C2 | `'@mode light {'#10'  :root {'#10'  /* ── SEED ── */'#10'  --accent: #3B82F6; --surface: #FFFFFF;'#10'  }'#10'}'` | 1 块 `tbkModeRoot`，`Mode = 'light'`、`ModeStart = 1`、`OuterClose` = 最后一个 `}` 的偏移；两条声明，值 `#3B82F6`、`#FFFFFF` | `ReadMode` 不记 `OuterClose` |
| C3 | `':root { /* --accent: red; */ --accent: #222; }'` | 一条声明，值 `#222` | — （词法器跳注释） |
| C4 | `':root { --accent: #333 /* c */ ; }'` | 值 `#333` | `ValueEndBefore` 不跳尾随注释（得到 `#333 /* c */`） |
| C5 | `':root { --surface: darken(var(--x), 4%); }'` | 值 `darken(var(--x), 4%)` | — |
| C6 | `'TyLabel { font-family: "A;B"; }'` | 值 `"A;B"`（字符串里的分号不终止） | — |
| C7 | `'TyButton.primary:hover, TyEdit { color: red; }'` | 1 块 `tbkRule`；选择器 `('TyButton','primary','hover')` Start 1、`('TyEdit','','')` Start 25 | 逗号后不继续读（只剩一个） |
| C8 | `'@import "a.tycss";'#10':root { --a: 1px; }'` | `ImportEnd = 19`；1 块 | — |
| C9 | `':root { --a: #111;'` 与 `'TyButton { color: red'` | 前者 `CloseBrace = 0`、一条声明 `#111`；后者一条声明 `red`、`StopAt = 0`、`CloseBrace = 0`；都不抛 | `ReadDecls` 遇 EOF 不停（死循环——以超时算红） |
| C10 | `'@media x { TyButton { color: red; } }'#10':root { --a: 1px; }'` | 只有 1 块（`:root`） | 未知 at 规则不整块跳过（多出一个 `TyButton` 规则） |
| C11 | `':root { --a: #111; --a: #222; }'` | 两条声明，按出现顺序 | — |
| C12 | `TbOffsetToPoint('ab'#13#10'c'#$E4#$B8#$AD'd'#13'e'#10'f', o)`：o = 5 / 9 / 11 / 13 / 14 | (1,2) / (5,2) / (1,3) / (1,4) / (2,4) | 单独的 CR 不断行（e 落在第 2 行） |
| C13 | 真文件对拍：`themes/` 下每个 `*.tycss`（递归）：`TTyCssParser` 解析得到的顶层 `RootVars` 每个名字，扫描里 `tbkRoot` 块中**最后一条**同名声明的值，与解析器的值去掉全部空白、把 `'` 换成 `"` 后相等；每个 `@mode` 块同理（按模式名对 `tbkModeRoot`）；规则条数相等，每条规则第一个选择器的类型名相等 | — （对拍，失败信息打印文件、名字与两边的值） |
| C14 | `TbApplyEdits('abcdef', [TbEdit(2,4,'XY'), TbEdit(6,6,'!')])` → `'aXYde!f'`；`TbEndInsertPos`：`'a'#13#10` → 2，`'a'#10` → 2，`'a'` → 2，`''` → 1 | — | `TbApplyEdits` 从前往后应用（第二个改动落错位置） |

- [ ] **Step 6: 注册与提交**：`.lpi` 加 `tbcssscan.pas`（`<UnitName Value="tbcssscan"/>`、`<IsPartOfProject Value="True"/>`）；`tytests.lpr` uses 加 `test.themebuilder.scan`。`feat(themebuilder): a forgiving scan of tycss that knows where every value and selector is` + Co-Authored-By。

---

### Task 2: 种子的定位与改写（纯函数）

**Files:**
- Create: `tools/themebuilder/tbseeds.pas`（本任务写纯函数部分；`TTbSeedEval` 在 Task 3）、`tests/test.themebuilder.seeds.pas`（suite `TTbSeedEditTests`）
- Modify: `tools/themebuilder/themebuilder.lpi`、`tests/tytests.lpr`

- [ ] **Step 1: 单元头注释**：六个种子（spec §5.2，`themes/auto.tycss` 的 SEED 段）；一列就是一个模式，这一列的值按引擎的生效顺序找（核实记录 8）；改值只替换值区间，缺的插入一整行，块不存在就建块；表达式的判断。

- [ ] **Step 2: 查找与格子**：

```pascal
{ the last declaration of AName in the blocks of this kind (and mode): later wins, as in the engine }
function FindLast(AScan: TTbCssScan; AKind: TTbBlockKind; const AMode, AName: string;
  out ABlock, ADecl: Integer): Boolean;
var
  b, d: Integer;
  blk: TTbBlock;
begin
  ABlock := -1;
  ADecl := -1;
  for b := 0 to AScan.Count - 1 do
  begin
    blk := AScan.Block(b);
    if blk.Kind <> AKind then Continue;
    if (AKind = tbkModeRoot) and (blk.Mode <> AMode) then Continue;
    for d := 0 to High(blk.Decls) do
      if SameText(blk.Decls[d].Name, AName) then
      begin
        ABlock := b;
        ADecl := d;
      end;
  end;
  Result := ABlock >= 0;
end;

function TbSeedCell(AScan: TTbCssScan; ASeed: Integer; const AColumn: string): TTbSeedCell;
var
  name: string;
  b, d: Integer;
begin
  Result := Default(TTbSeedCell);
  Result.Seed := ASeed;
  Result.Column := AColumn;
  Result.Block := -1;
  Result.Decl := -1;
  name := '--' + TbSeedNames[ASeed];
  if (AColumn <> '') and FindLast(AScan, tbkModeRoot, AColumn, name, b, d) then
    Result.Source := tssOwn
  else if FindLast(AScan, tbkRoot, '', name, b, d) then
  begin
    if AColumn = '' then Result.Source := tssOwn else Result.Source := tssShared;
  end
  else
  begin
    Result.Source := tssInherited;
    Exit;
  end;
  Result.Block := b;
  Result.Decl := d;
  Result.Raw := AScan.DeclValue(b, d);
  Result.IsExpression := not TbIsLiteralSeedValue(ASeed, Result.Raw);
end;
```

  `TbSeedColumns`：`AScan.HasModes` → `['light', 'dark']`，否则 `['']`。`TbIsLiteralSeedValue`：颜色种子 = `#` 后 3、4、6、8 位十六进制（不分大小写）；`radius` = 一串数字、可带 `px`（不分大小写）；其余（`var()`、函数、`system-accent`、颜色名、`em`……）都算表达式。`TbColorText`：alpha = 255 → `TyColorHex(c)`，否则再接两位大写十六进制 alpha。`TbRadiusText` = `IntToStr(n) + 'px'`。

- [ ] **Step 3: 改写**：

```pascal
function TbSeedSetEdits(AScan: TTbCssScan; const AEol: string; ASeed: Integer;
  const AColumn, AValue: string; AShared: Boolean): TTbTextEdits;
var
  cell: TTbSeedCell;
  decl: TTbDecl;
  target: Integer;
  line: string;
begin
  Result := nil;
  cell := TbSeedCell(AScan, ASeed, AColumn);
  line := '--' + TbSeedNames[ASeed] + ': ' + AValue + ';';
  if (cell.Source = tssOwn) or ((cell.Source = tssShared) and AShared) then
  begin
    decl := AScan.Block(cell.Block).Decls[cell.Decl];
    SetLength(Result, 1);
    Result[0] := TbEdit(decl.ValueStart, decl.ValueEnd, AValue);
    Exit;
  end;
  if AColumn = '' then
    target := LastBlock(AScan, tbkRoot, '')
  else
    target := LastBlock(AScan, tbkModeRoot, AColumn);
  if target >= 0 then
    Result := InsertIntoBlock(AScan, target, line, AEol)
  else if AColumn = '' then
    Result := NewRootBlock(AScan, line, AEol)
  else
    Result := NewModeBlock(AScan, AColumn, [line], AEol);
end;
```

  - `LastBlock`：这一类（这一模式）里文档顺序最后一个块的下标，没有为 −1。
  - `InsertIntoBlock`：`CloseBrace = 0` → nil。`ls := TbLineStart(Text, CloseBrace)`；`}` 前面这一段全是空白（多行块）→ 缩进 = 块里最后一条声明所在行的缩进（`TbLineIndent(Text, 最后一条的 NameStart)`），块里没有声明时 = `}` 那行的缩进 + 两个空格；在 `ls` 插入 `缩进 + line + AEol`。否则（一行的块）→ 在 `}` 处插入：前一个字符是空白 → `line + ' '`，否则 `' ' + line + ' '`。
  - `ModeBlockText(AMode, ALines, AEol)` = `'@mode ' + AMode + ' {' + AEol + '  :root {' + AEol` + 每行 `'    ' + 行 + AEol` + `'  }' + AEol + '}'`（缩进同 1 期的极简模板）。
  - `NewModeBlock`：有 `tbkModeRoot` 块时：`AMode = 'light'` → 在第一个模式块的 `ModeStart` 插入 `块 + AEol + AEol`；其他模式 → 在最后一个模式块的 `OuterClose + 1` 插入 `AEol + AEol + 块`（`OuterClose = 0` → nil）。没有任何模式块时（只有拆分会走到）→ 在 `TbEndInsertPos` 插入 `AEol + AEol + 块`；全文只有空白时改为用 `块 + AEol` 替换全文。
  - `NewRootBlock`：有任何块 → 在文档顺序第一个块的起点（`tbkModeRoot` 用 `ModeStart`，其余用 `HeadStart`）插入 `':root {' + AEol + '  ' + line + AEol + '}' + AEol + AEol`；没有块 → 全文只有空白时用 `':root {' + AEol + '  ' + line + AEol + '}' + AEol` 替换全文，否则在 `TbEndInsertPos` 插入 `AEol + AEol + ':root {…}'`（同上，末尾不带 `AEol`）。
  - `TbSplitModesEdits`：`AScan.HasModes` → nil；六行 = `'--' + 名 + ': ' + AValues[i] + ';'`；位置 = 最后一个 `CloseBrace > 0` 的 `tbkRoot` 块的 `CloseBrace + 1`，没有就 `TbEndInsertPos`；文本 = `AEol + AEol + ModeBlockText('light') + AEol + AEol + ModeBlockText('dark')`；全文只有空白时改为 `light + AEol + AEol + dark + AEol` 替换全文。

- [ ] **Step 4: 判据测试**（`TTbSeedEditTests`；「改后」= `TbApplyEdits(T, edits)` 的结果与期望逐字节比；每条另断言「改后」去掉改动区间后与原文相同——用 `TbApplyEdits` 的逆算不方便时，直接断言整串期望即可，因为期望本身就只差那一段）：

| # | T（Pascal 字面量） | 操作 | 期望 | 在哪个变异下必须红 |
|---|---|---|---|---|
| E1 | `'@mode light {'#10'  :root {'#10'  --accent: #3B82F6; --surface: #FFFFFF;'#10'  }'#10'}'#10'@mode dark {'#10'  :root {'#10'  --accent:     #60A5FA;'#10'  }'#10'}'#10` | `surface`、`'light'`、`#EEEEEE`；再单独 `accent`、`'dark'`、`#123456` | `StringReplace(T, '#FFFFFF', '#EEEEEE', [])`；`StringReplace(T, '#60A5FA', '#123456', [])`（对齐空格保留） | 改写整行（同一行的 `--accent` 丢失 / 对齐空格丢失） |
| E2 | `':root {'#10'  /* --accent: #000000; */'#10'  --accent: #111111;'#10'}'#10` | `accent`、`''`、`#222222` | `StringReplace(T, '#111111', '#222222', [])`，注释原样 | — |
| E3 | `':root { --accent: #111111; --accent: #222222; }'` | `accent`、`''`、`#333333` | `':root { --accent: #111111; --accent: #333333; }'` | `FindLast` 取第一条 |
| E4 | `':root {'#10'  --accent: #111111;'#10'}'#10` | `surface`、`''`、`#FFFFFF` | `':root {'#10'  --accent: #111111;'#10'  --surface: #FFFFFF;'#10'}'#10` | 插入不看缩进（得到 `--surface` 顶格） |
| E5 | `'@mode light { :root { --accent: #1E66F5; } }'#10'@mode dark  { :root { --accent: #89B4FA; } }'#10` | `radius`、`'light'`、`8px` | `'@mode light { :root { --accent: #1E66F5; --radius: 8px; } }'#10'@mode dark  { :root { --accent: #89B4FA; } }'#10` | 一行块也按多行插（在行首插入，破坏 `@mode light` 那行） |
| E6 | `':root { --accent: #3DAEE9; }'#10'@mode light {'#10'  :root {'#10'    --surface: #EFF0F1;'#10'  }'#10'}'#10'@mode dark {'#10'  :root {'#10'    --surface: #232629;'#10'  }'#10'}'#10` | 格子 `accent`/`light`；设 `#000000`，`AShared = True`；再 `AShared = False` | 格子 `Source = tssShared`、`Raw = '#3DAEE9'`；前者 `StringReplace(T, '#3DAEE9', '#000000', [])`；后者在亮色块 `    --surface: #EFF0F1;` 之后插入 `'    --accent: #000000;'#10`，其余不变 | ① 双模式文档把 `:root` 里的算成 `tssOwn`；② 忽略 `AShared`（两种都改 `:root`） |
| E7 | `'@mode light {'#10'  :root {'#10'    --accent: #111111;'#10'  }'#10'}'#10`；另一份 T2 = `'@mode dark {'#10'  :root {'#10'    --accent: #222222;'#10'  }'#10'}'#10` | T：`accent`、`'dark'`、`#222222`；T2：`accent`、`'light'`、`#111111` | T → T 的前 `Length−1` 字节 + `#10#10'@mode dark {'#10'  :root {'#10'    --accent: #222222;'#10'  }'#10'}'#10`；T2 → `'@mode light {'#10'  :root {'#10'    --accent: #111111;'#10'  }'#10'}'#10#10` + T2 | 亮色块也建在后面 |
| E8 | `'TyButton { color: red; }'#10`；另一份 `''` | `accent`、`''`、`#111111` | `':root {'#10'  --accent: #111111;'#10'}'#10#10'TyButton { color: red; }'#10`；`''` → `':root {'#10'  --accent: #111111;'#10'}'#10` | — |
| E9 | E4 的 T 全换成 `#13#10`，`AEol = #13#10` | 同 E4 | E4 的期望全换成 `#13#10` | 插入固定用 `LineEnding` 或 `#10` |
| E10 | `':root { --accent: #111111;'`（没闭合） | `accent` 设 `#222222`；`surface` 设 `#FFFFFF` | 前者 `':root { --accent: #222222;'`；后者 **nil** | `InsertIntoBlock` 不查 `CloseBrace = 0`（插到偏移 0 处） |
| E11 | `TbIsLiteralSeedValue`：颜色种子 `#abc`、`#AABBCCDD` → True；`darken(--x, 4%)`、`system-accent`、`var(--a)`、`red` → False；`radius` 的 `6px`、`6`、`12PX` → True，`var(--r)`、`6em` → False | — | — | 颜色只认 6 位（`#abc` 判成表达式） |
| E12 | `':root {'#10'  --accent: #111111; --radius: 4px;'#10'  --muted: #999999;'#10'}'#10'TyButton { color: red; }'#10`，值 `#111111`、`#FFFFFF`、`#1F2937`、`#D1D5DB`、`#EF4444`、`4px` | `TbSplitModesEdits` | 原文到第 4 行的 `}` 为止，接着插入 `#10#10'@mode light {'#10'  :root {'#10'    --accent: #111111;'#10'    --surface: #FFFFFF;'#10'    --on-surface: #1F2937;'#10'    --border: #D1D5DB;'#10'    --danger: #EF4444;'#10'    --radius: 4px;'#10'  }'#10'}'#10#10'@mode dark {'#10`（六行同上）`'  }'#10'}'`，然后是原文的 `#10'TyButton { color: red; }'#10`；再扫一遍：`TbSeedColumns = light, dark`，12 个格子都是 `tssOwn`；对双模式文档调用 → nil | 暗色块写成另一组值；插在 `:root` 之前 |
| E13 | 真文件（从 `TbThemesDir` 读）：`auto.tycss` 12 格全 `tssOwn`；`builtin/classic.tycss` `surface`/`light` = `tssInherited`、`surface`/`dark` = `tssOwn`；`builtin/win11.tycss` `radius` 两列都 `tssShared`、`Raw = '5px'`；`builtin/breeze.tycss` `accent` 两列 `tssShared`；`builtin/aero.tycss` `surface`/`dark` `tssOwn` 且 `IsExpression`；`system.tycss` `accent`/`light` `IsExpression`、`Raw = 'system-accent'`；`light.tycss` 列 = `['']`，6 格全 `tssOwn`；`palettes/catppuccin.tycss` `radius` 两列 `tssInherited` | — | — | `tssShared` 与 `tssOwn` 判反（win11 失败） |

- [ ] **Step 5: 注册与提交**：`.lpi` 加 `tbseeds.pas`；uses 加 `test.themebuilder.seeds`。`feat(themebuilder): find and rewrite the six seeds, one value at a time` + Co-Authored-By。

---

### Task 3: 种子按列求值、种子面板

**Files:**
- Modify: `tools/themebuilder/tbseeds.pas`（加 `TTbSeedEval`）、`tests/test.themebuilder.seeds.pas`（suite `TTbSeedsFrameTests`）
- Create: `tools/themebuilder/tbseedsframe.pas`、`tbseedsframe.lfm`
- Modify: `tools/themebuilder/themebuilder.lpi`

- [ ] **Step 1: `TTbSeedEval`**（`tbseeds.pas`；注释写明为什么不用预览控制器：核实记录 12）：

```pascal
constructor TTbSeedEval.Create;
begin
  inherited Create;
  FModel := TTyStyleModel.Create;   { the base layer, as every model starts }
end;

function TTbSeedEval.Load(const AText, ABaseDir: string): Boolean;
begin
  try
    FModel.LoadFromSource(TTbTextThemeSource.Create(AText, ABaseDir));
    FLoaded := True;
  except
    FLoaded := False;
  end;
  Result := FLoaded;
end;

function TTbSeedEval.Color(ASeed: Integer; const AColumn: string; out AColor: TTyColor): Boolean;
var
  s: TTyStyleSet;
begin
  AColor := 0;
  Result := False;
  if not FLoaded then Exit;
  FModel.SetMode(AColumn);
  s := FModel.ResolveOverride('color: var(--' + TbSeedNames[ASeed] + ');');
  if tpTextColor in s.Present then
  begin
    AColor := s.TextColor;
    Result := True;
  end;
end;
```

  `Radius`：`SetMode(AColumn)`，`APx := FModel.ResolveMetric('--radius', -1)`，`Result := APx >= 0`。析构释放模型。

- [ ] **Step 2: `.lfm`**（`object SeedsFrame: TTbSeedsFrame`，工具皮肤（不设 `Controller`），宽按侧栏 280 设计、用 `AutoSize` 与锚点留余量——换肤会撑宽，仓库记忆「换肤会撑破写死的宽度」）：
  - `ModeNote: TTyLabel`（`alTop`，`WordWrap`，初始空）、`SplitButton: TTyButton`（`alTop`，`Caption = 'Split into light and dark'`，`OnClick = SplitButtonClick`）。
  - `Scroll: TTyScrollBox`（`alClient`），里面 `Header: TTyPanel`（`alTop`：`HdrName: TTyLabel` `'Seed'`、`HdrLeft: TTyLabel` `'Light'`、`HdrRight: TTyLabel` `'Dark'`），然后六行 `RowAccent`、`RowSurface`、`RowOnSurface`、`RowBorder`、`RowDanger`、`RowRadius: TTyPanel`（`alTop`、`AutoSize`），每行：名字 `LblAccent: TTyLabel`（`'--accent'` 等，**不译**，`.po` 里原样）；左右两格：颜色行是 `SwAccentL` / `SwAccentR: TTyColorButton`（`ShowText = True`，`OnColorChange = SwatchColorChange`），`NoteAccentL` / `NoteAccentR: TTyLabel`（初始空）；圆角行是 `SpnRadiusL` / `SpnRadiusR: TTySpinEdit`（`MinValue = 0`、`MaxValue = 64`，`OnChange = RadiusChange`）与 `NoteRadiusL` / `NoteRadiusR`。
  - 所有初值（`Value`、`SelectedColor`、`Visible`）在代码里设（地雷 5：`.lfm` 里的初值会在流式加载时触发事件）。

- [ ] **Step 3: 构造**：`inherited`；`FEval := TTbSeedEval.Create`；把色块、说明、微调框按 `[种子, 列]` 装进 `FSwatch`、`FNote`、`FSpin` 数组，色块的 `Tag := 种子 * 2 + 列`、微调框 `Tag := 列`；`FColumns := ['']`；`FBroken := True`（还没有文本）；`UpdateView`。析构释放 `FScan`、`FEval`。

- [ ] **Step 4: 刷新**（`UpdateFrom`）：

```pascal
procedure TTbSeedsFrame.UpdateFrom(const AText, ABaseDir: string; ABroken: Boolean);
begin
  FText := AText;
  FreeAndNil(FScan);
  FScan := TbScanCss(AText);
  FEol := TbDetectEol(AText);
  FColumns := TbSeedColumns(FScan);
  { a text that does not parse: its value spans may no longer be what they look like }
  FBroken := ABroken or not FEval.Load(AText, ABaseDir);
  UpdateView;
end;
```

  `UpdateView`（整段在 `FUpdating := True … finally False` 里）：`ModeNote.Caption` = `FBroken` → `rsTbSeedsBroken`（'Fix the errors in the problem list first.'）；单模式 → `rsTbSeedsSingleMode`（'One mode: the seeds of both light and dark.'）；否则空。`SplitButton.Visible := (not FBroken) and (Length(FColumns) = 1)`。右列（色块、说明、微调框、`HdrRight`）`Visible := Length(FColumns) = 2`；`HdrLeft.Caption` = 单模式 `rsTbSeedValue`（'Value'）/ 否则 `rsTbSeedLight`；`HdrRight.Caption := rsTbSeedDark`。`Scroll.Enabled := not FBroken`。每个可见格子：`c := Cell(种子, 列)`；色块 `SelectedColor` = 求值结果（求不到就不改）、`DialogCaption := '--' + 名 + ' (' + 列显示名 + ')'`、`Hint := c.Raw`、`ShowHint := c.Raw <> ''`；微调框 `Value` 同理；说明：`tssInherited` → `rsTbSeedInherited`（'inherited'）且 `Enabled := False`（灰）；`tssShared` → `rsTbSeedShared`（'from :root'）；`IsExpression` → `rsTbSeedExpression`（'expression'）；否则空；不是继承的 `Enabled := True`。`Cell` = `TbSeedCell(FScan, 种子, FColumns[列])`（`FScan = nil` 时返回 `Default` 且 `Source = tssInherited`）。`ResolvedText` = 颜色种子 `TbColorText`、圆角 `TbRadiusText`、求不到为 `''`。

- [ ] **Step 5: 改值**：

```pascal
function TTbSeedsFrame.ApplyValue(ASeed, AColumnIndex: Integer; const AValue: string): Boolean;
var
  c: TTbSeedCell;
  shared: Boolean;
  replaced: TTbSeedCell;
  edits: TTbTextEdits;
begin
  Result := False;
  if Assigned(FOnSync) then
    FOnSync(Self);                        { the editor may be ahead of our scan }
  if FBroken or (AColumnIndex > High(FColumns)) then Exit;
  c := Cell(ASeed, AColumnIndex);
  shared := False;
  if c.Source = tssShared then
    case Ask(Format(rsTbSeedSharedAsk, ['--' + TbSeedNames[ASeed], ColumnName(AColumnIndex)]),
      [mbYes, mbNo, mbCancel]) of
      mrYes: shared := True;
      mrNo: shared := False;
    else
      Exit;
    end;
  { only a value that is REPLACED can be an expression lost; an added line loses nothing }
  if (c.Source = tssOwn) or shared then
    if c.IsExpression and (Ask(Format(rsTbSeedExprAsk,
      ['--' + TbSeedNames[ASeed], c.Raw, AValue]), [mbYes, mbNo]) <> mrYes) then
      Exit;
  edits := TbSeedSetEdits(FScan, FEol, ASeed, FColumns[AColumnIndex], AValue, shared);
  if (Length(edits) = 0) or not Assigned(FOnEdits) then Exit;
  FOnEdits(Self, FText, edits);
  Result := True;
end;
```

  `Ask`：`FOnAsk` 没挂时返回 `mrCancel`（不改）。`rsTbSeedSharedAsk = '%s is set in :root and shared by light and dark. Yes: change it there (both modes). No: add it to %s only.'`；`rsTbSeedExprAsk = '%s is the expression %s. Replace it with %s?'`；列显示名用 1 期的 `rsTbModeLight` / `rsTbModeDark`（`tbpreview`），单模式不会走到 `tssShared`。
  - `SwatchColorChange(Sender)`：`FUpdating` 时返回；由 `Tag` 得种子与列；`if not ApplyValue(种子, 列, TbColorText(SelectedColor)) then UpdateView`（没改成就把色块退回文本里的值）。
  - `RadiusChange(Sender)`：同上，值 `TbRadiusText(Value)`。
  - `SplitModes`：`OnSync`；`FBroken` 或已双模式 → False；六个值：格子 `tssOwn` 用 `Raw`，否则用 `ResolvedText(种子, 0)`（为空就 False）；`edits := TbSplitModesEdits(FScan, FEol, 值)`；交给 `FOnEdits`。`SplitButtonClick` 调它。

- [ ] **Step 6: resourcestring**（`tbseedsframe.pas`）：`rsTbSeedsBroken`、`rsTbSeedsSingleMode`、`rsTbSeedValue`、`rsTbSeedLight = 'Light'`、`rsTbSeedDark = 'Dark'`、`rsTbSeedInherited`、`rsTbSeedShared`、`rsTbSeedExpression`、`rsTbSeedSharedAsk`、`rsTbSeedExprAsk`。

- [ ] **Step 7: 判据测试**（`TTbSeedsFrameTests`；frame `TTbSeedsFrame.Create(nil)` 不设 Parent；`OnAsk` 挂一个按脚本回答、计数的桩；`OnEdits` 挂一个记下 `(text, edits)`、计数的桩；`OnSync` 不挂，除非判据说要）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| SF1 | 极简模板（`TbMinimalTemplate`）：`Columns = light, dark`；右列色块 `Visible`；`SplitButton.Visible = False`；`ResolvedText(accent,0) = '#3B82F6'`、`(accent,1) = '#60A5FA'`、`(radius,0) = (radius,1) = '6px'`；12 个说明都是空串；`Swatch(accent,1).SelectedColor` 的十六进制 = `#60A5FA` | `UpdateView` 不按列设色块（右列显示左列的值） |
| SF2 | `TyBuiltinThemeCss`（单模式）：`Columns = ['']`；右列不可见；`SplitButton.Visible`；`ModeNote.Caption = rsTbSeedsSingleMode` | — |
| SF3 | `'@mode light { :root { --accent: #111111; } }'#10'@mode dark { :root { --accent: #222222; } }'`：`surface` 两格 `Source = tssInherited`，`Note(surface,0).Caption = rsTbSeedInherited` 且 `Enabled = False`；`ResolvedText(surface,0) = '#FFFFFF'`、`(surface,1) = '#1E1E1E'`（底层分模式种子） | 求值不按列 `SetMode`（两列都是 `#FFFFFF`） |
| SF4 | `'@mode light { :root { --surface: darken(#FFFFFF, 10%); } }'#10'@mode dark { :root { --surface: #222222; } }'`：`ApplyValue(surface, 0, '#EEEEEE')`，桩答 `mrNo` → False、`OnEdits` 未被调、问了 1 次；答 `mrYes` → True、一次 `OnEdits`，`TbApplyEdits` 后文本里 `darken(#FFFFFF, 10%)` 变成 `#EEEEEE`、其余不变；对 `(surface,1)`（字面值）调用不问 | ① 不问表达式；② 字面值也问 |
| SF5 | E6 的文本：`ApplyValue(accent, 0, '#000000')` 桩答 `mrYes` → 改 `:root`；`mrNo` → 亮色块多一行；`mrCancel` → False、无 `OnEdits` | 共用格子不问（直接写进亮色块） |
| SF6 | 坏文本 `'TyButton {'`（`ABroken = True` 传入）：`Broken`；`ApplyValue` → False、没问、没 `OnEdits`；`ModeNote.Caption = rsTbSeedsBroken`；`Scroll.Enabled = False`；`ABroken = False` 但加载会失败的文本（`'TyButton { border-radius: 1px 2px 3px; }'`）同样 `Broken` | 不看 `FEval.Load` 的结果 |
| SF7 | 密度无关：建一个 `TTbPreviewFrame`，加载 ~~极简模板~~ `TyBuiltinThemeCss`（实现期修正（开工核对）：极简模板的 `--radius` 在 `@mode` 块里，盖过密度包，预览仍是 6）、`SetModern(True)`，**先证明** `Preview.Controller.Model.ResolveMetric('--radius', -1) = 8`；同一文本 `UpdateFrom` 后 `ResolvedText(radius,0) = '6px'` | 求值改用预览控制器的模型（得到 8px） |
| SF8 | 刷新不回写：`UpdateFrom` 极简模板再 `UpdateFrom` 一份不同的双模式文本（先证明两份的 `accent` 亮色值不同）→ `OnEdits` 计数 0；随后 `Swatch(accent,0).SelectedColor := TyRGBA($12,$34,$56,$FF)` → `OnEdits` 计数 1、改动的值是 `'#123456'` | `UpdateView` 不设 `FUpdating`（刷新时计数 > 0） |
| SF9 | 拆分：`TyBuiltinThemeCss` 之上 `SplitModes` → 一次 `OnEdits`；应用后再 `UpdateFrom`：`Columns = light, dark`；12 格 `tssOwn`；`ResolvedText(surface,1) = ResolvedText(surface,0)`（暗色先用亮色值） | 暗色一组取的是求值出的暗色值 |
| SF10 | 圆角：极简模板，`RadiusSpin(1).Value := 9` → `OnEdits` 的改动值 `'9px'`、落在暗色块 | `RadiusChange` 取错列（落到亮色块） |
| SF11 | `OnSync` 先于计算：挂一个桩，桩里调 `UpdateFrom(另一份文本)`；`ApplyValue` 之后 `OnEdits` 收到的 `AText` 是那份新文本 | `ApplyValue` 不调 `OnSync` |

- [ ] **Step 8: 注册与提交**：`.lpi` 加 `tbseedsframe.pas`（`<ComponentName Value="SeedsFrame"/>`、`<HasResources Value="True"/>`、`<ResourceBaseClass Value="Frame"/>`）。`feat(themebuilder): the seeds panel -- light and dark, what is inherited, expressions asked about` + Co-Authored-By。

---

### Task 4: 规则的查找与插入（纯函数）

**Files:**
- Create: `tools/themebuilder/tbrules.pas`
- Modify: `tests/test.themebuilder.scan.pas`（suite `TTbRulesTests`）、`tools/themebuilder/themebuilder.lpi`

- [ ] **Step 1: 单元**：

```pascal
function TbSelectorText(const ATypeKey, AVariant: string): string;
begin
  Result := ATypeKey;
  if AVariant <> '' then
    Result := Result + '.' + AVariant;
end;

function TbFindRuleSelectors(AScan: TTbCssScan; const ATypeKey, AVariant: string): TTbOffsets;
var
  b, s: Integer;
  blk: TTbBlock;
begin
  Result := nil;
  for b := 0 to AScan.Count - 1 do
  begin
    blk := AScan.Block(b);
    if blk.Kind <> tbkRule then Continue;
    for s := 0 to High(blk.Selectors) do
      if SameText(blk.Selectors[s].TypeName, ATypeKey)
         and SameText(blk.Selectors[s].Variant, AVariant)
         and (blk.Selectors[s].State = '') then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := blk.Selectors[s].Start;
      end;
  end;
end;
```

  `TbNewRuleEdits`：`sel := TbSelectorText(…)`；全文只有空白 → 一个改动替换全文为 `sel + ' {' + AEol + '  ' + AEol + '}' + AEol`，`ACaret := 1 + Length(sel + ' {' + AEol + '  ')`；否则在 `p := TbEndInsertPos(Text)` 插入 `AEol + AEol + sel + ' {' + AEol + '  ' + AEol + '}'`，`ACaret := p + Length(AEol + AEol + sel + ' {' + AEol + '  ')`。

- [ ] **Step 2: 判据测试**（`TTbRulesTests`）：

| # | 输入 | 期望 | 在哪个变异下必须红 |
|---|---|---|---|
| R1 | T = `'TyButton { }'#10'TyButton.primary { }'#10'TyButton.primary:hover { }'#10'TyEdit, TyButton.primary { }'`，找 `('TyButton','primary')` | 两个偏移，`TbOffsetToPoint` = (1,2)、(9,4) | 不看 `State`（多出第 3 行） |
| R2 | 同 T，找 `('TyButton','')` → 一个 (1,1)；找 `('tybutton','PRIMARY')` → 同 R1 | — | 比较区分大小写 |
| R3 | `'/* TyButton.primary { } */'#10'TyButton.primary { }'` | 一个 (1,2) | — |
| R4 | `'@mode dark { :root { --a: #111; } }'#10'TyEdit { }'`，找 `('TyEdit','')` → (1,2)；找 `('TyButton','')` → 空 | — | — |
| R5 | `TbNewRuleEdits` 于 `'TyEdit { }'#10`，`AEol = #10`，`('TyButton','primary')` | 应用后 `'TyEdit { }'#10#10'TyButton.primary {'#10'  '#10'}'#10`；`TbOffsetToPoint(新文本, ACaret) = (3,4)` | 插在文末换行之后（多出一个空行在末尾、光标错行） |
| R6 | 同上但原文 `'TyEdit { }'`（无文末换行） | `'TyEdit { }'#10#10'TyButton.primary {'#10'  '#10'}'`，光标 (3,4) | — |
| R7 | 原文 `''`，`('TyButton','')` | `'TyButton {'#10'  '#10'}'#10`，光标 (3,2) | — |

- [ ] **Step 3: 提交**：`.lpi` 加 `tbrules.pas`。`feat(themebuilder): find the rule for a typeKey and variant, or add an empty one` + Co-Authored-By。

---

### Task 5: 预览里的 Ctrl+点击

**Files:**
- Create: `tools/themebuilder/tbpick.pas`、`tests/test.themebuilder.pick.pas`（suite `TTbPickTests`）
- Modify: `tools/themebuilder/tbpreview.pas`、`tools/themebuilder/themebuilder.lpi`、`tests/tytests.lpr`

- [ ] **Step 1: 单元头注释**：为什么挂 `WindowProc`（核实记录 18：窗口化与图形控件的鼠标消息最后都经它，挂一处就够，不必每个控件挂事件、也不改库）；拦的是什么（按住 Ctrl——Darwin 上 Cmd 也算——的左键按下 / 双击，以及紧随其后的那一次抬起）；点中的是谁（核实记录 20）；摘钩的规矩（地雷 23）。

- [ ] **Step 2: 挂钩对象**（implementation 私有）：

```pascal
type
  TTbPickHook = class(TComponent)
  private
    FControl: TControl;
    FOld: TWndMethod;
    FPicker: TTbPicker;
    procedure WndProc(var AMsg: TLMessage);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

procedure TTbPickHook.WndProc(var AMsg: TLMessage);
begin
  if ((AMsg.Msg = LM_LBUTTONDOWN) or (AMsg.Msg = LM_LBUTTONDBLCLK)) and TbIsPickMessage(AMsg) then
  begin
    FPicker.FSwallowUp := True;
    FPicker.Pick(FControl, SmallPointToPoint(TLMMouse(AMsg).Pos));
    AMsg.Result := 0;
    Exit;                        { the control never sees it: no press, no focus, no click }
  end;
  if (AMsg.Msg = LM_LBUTTONUP) and FPicker.FSwallowUp then
  begin
    FPicker.FSwallowUp := False;
    AMsg.Result := 0;
    Exit;
  end;
  FOld(AMsg);
end;

function TbIsPickMessage(const AMsg: TLMessage): Boolean;
begin
  Result := (TLMMouse(AMsg).Keys and MK_CONTROL) <> 0;
  {$IFDEF DARWIN}
  { Ctrl+click is the context-menu gesture on a Mac; Command+click is what reads as "go to" }
  if not Result then
    Result := ssMeta in GetKeyShiftState;
  {$ENDIF}
end;
```

  `Notification(opRemove)` 收到被挂控件释放 → `FControl := nil`，并让 `FPicker` 把自己从表里摘掉（不碰控件）。

- [ ] **Step 3: `TTbPicker`**：私有 `FHooks: TFPList`、`FSwallowUp: Boolean`、`FOnPick`。
  - `HookTree(ARoot)`：`HookOne(ARoot)` 再逐层走 `Controls[]`（`TWinControl` 递归）。`HookOne(C)`：已经挂过（表里有 `FControl = C`）就跳过；否则建一个 `TTbPickHook`（Owner = picker）、`FOld := C.WindowProc`、`FMine := @hook.WndProc`（挂钩里多一个 `FMine: TWndMethod` 字段）、`C.WindowProc := FMine`、`C.FreeNotification(hook)`。
  - `UnhookAll`：从后往前，每个挂钩：`FControl <> nil` 且 `TMethod(FControl.WindowProc).Code = TMethod(FMine).Code` 且 `.Data` 也相等时还原 `FOld`（别人在我们之后又换过就不动）；`RemoveFreeNotification`；释放挂钩。析构调它。
  - `Pick(AControl, APos)`：`t := TbPickTarget(AControl, APos)`；`t = nil` 或 `FOnPick` 没挂 → 返回；`key := (t as ITyStyleable).GetStyleTypeKey`；`cls` = `t` 是 `TTyCustomControl` 就取它的 `StyleClass`，是 `TTyGraphicControl` 同理，否则空；`FOnPick(Self, key, cls)`。
  - `TbPickTarget`：

```pascal
function TbPickTarget(AControl: TControl; const APos: TPoint): TControl;
var
  sub: TControl;
begin
  Result := AControl;
  if AControl is TWinControl then
  begin
    { a disabled graphic child gets no mouse message of its own: its parent does }
    sub := TWinControl(AControl).ControlAtPos(APos,
      [capfAllowDisabled, capfAllowWinControls, capfRecursive]);
    if sub <> nil then
      Result := sub;
  end;
  while (Result <> nil) and not Supports(Result, ITyStyleable) do
    Result := Result.Parent;
end;
```

- [ ] **Step 4: 接进预览 frame**（`tbpreview.pas`）：字段 `FPicker: TTbPicker`、`FOnPick: TTbPickEvent`；构造里在 `TbApplyController(Root, …)` 之后 `FPicker := TTbPicker.Create(Self); FPicker.OnPick := @PickerPick; FPicker.HookTree(Root);`（**只挂 `Root`**，`Tools` 不挂）；`PickerPick` 转给 `FOnPick`；`BuildSampleWindow` 在 `UseController` 之后 `FPicker.HookTree(FSampleWin)`；析构第一句 `if FPicker <> nil then FPicker.UnhookAll;`（在释放样例窗口之前）。接口清单里的 `Picker`、`OnPick` 两个属性。单元头注释补一段 Ctrl+点击。

- [ ] **Step 5: 判据测试**（`TTbPickTests`；`frame := TTbPreviewFrame.Create(nil)`，`frame.OnPick` 挂一个记录 `(key, cls)`、计数的桩；「Ctrl 按下」= `Perform(LM_LBUTTONDOWN, MK_LBUTTON or MK_CONTROL, 0)`，「抬起」= `Perform(LM_LBUTTONUP, 0, 0)`；看控件有没有收到按下，用访问类读 `FPressed`（`TTyCustomControlAccess = class(TTyCustomControl)`，同 1 期 `test.themebuilder.main`））：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| P1 | 对 `BtnPrimary` Ctrl 按下 → 桩 1 次，`('TyButton','primary')`；`FPressed = False`；再抬起：给 `BtnPrimary.OnClick` 挂计数，计数 0 | 拦下后仍调 `FOld`（`FPressed = True`） |
| P2 | 不按 Ctrl：按下 → 桩 0 次、`FPressed = True`（消息转交了）；抬起后复位 | `WndProc` 一律吞（`FPressed = False`） |
| P3 | Ctrl 按下后**不带** Ctrl 的抬起仍被吞（`OnClick` 计数 0），再下一次普通按下照常转交 | 抬起只在带 Ctrl 时吞 |
| P4 | 禁用的图形控件：`LblDisabled` 所在页（它的 `Parent`）对着 `LblDisabled` 中心点 Ctrl 按下 → 桩得到 `('TyLabel', '')` | `TbPickTarget` 去掉 `capfAllowDisabled`（得到 `TyTabSheet` 或页的 typeKey） |
| P5 | 非 Ty 子控件：测试往 `PnlSample` 里加一个 `TShape`（`ExtCtrls`，只在测试里用），`frame.Picker.HookTree(frame.PnlSample)`，对它 Ctrl 按下 → `('TyPanel', '')` | 不往上找（`Supports` 失败返回 nil、桩 0 次） |
| P6 | 样例窗口：`BuildSampleWindow` 之后对它的 `BtnOk` Ctrl 按下 → `('TyButton','primary')` | `BuildSampleWindow` 不 `HookTree` |
| P7 | 开关条不挂：对 `DarkSwitch` Ctrl 按下 → 桩 0 次 | 构造里挂的是整个 frame 而不是 `Root` |
| P8 | 摘钩：单独 `b := TTyButton.Create(nil)`，记下 `TMethod(b.WindowProc)`；一个 `TTbPicker` `HookTree` 之后它变了，`UnhookAll` 之后与记下的相等；`HookCount` 从 1 到 0；再 `b.Free`、picker `Free` 不 AV；另一组先 `b.Free` 再 picker `Free` 也不 AV | ① `UnhookAll` 不还原；② 挂钩不 `FreeNotification`（后一组 AV） |
| P9 | frame 析构不 AV：建 frame、`BuildSampleWindow`、Ctrl 按下一次、`Free` | 析构不先 `UnhookAll`（若确实不 AV，这一变异「等价」，签收写明） |

- [ ] **Step 6: 注册与提交**：`.lpi` 加 `tbpick.pas`；uses 加 `test.themebuilder.pick`。`feat(themebuilder): Ctrl+click in the preview names the control's typeKey and variant` + Co-Authored-By。

---

### Task 6: 覆盖检查

**Files:**
- Create: `tools/themebuilder/tbcoverage.pas`、`tbcoverageform.pas`、`tbcoverageform.lfm`
- Modify: `tools/themebuilder/tbpreview.pas`（`CollectTypeKeys`）、`tests/test.themebuilder.pick.pas`（suite `TTbCoverageTests`）、`tools/themebuilder/themebuilder.lpi`

- [ ] **Step 1: 子部件表**（`tbcoverage.pas` implementation；单元头注释写明表是什么、为什么不能运行时得到、守卫怎么核，核实记录 24）：

```pascal
type
  TTbPartRow = record
    U: string;   { the unit, as TClass.UnitName gives it }
    K: string;   { the typeKeys its code resolves, comma separated }
  end;

const
  { Checked against the sources by TTbCoverageTests.TestThePartTableMatchesTheSources: every
    typeKey a unit names in a string literal is in its row; what a row adds by hand (keys
    built by concatenation) must be a catalogue typeKey. }
  cTbPartRows: array[0..48] of TTbPartRow = (
    (U: 'tyControls.ActivityIndicator'; K: 'TyActivityIndicator,TyActivityIndicatorFill'),
    (U: 'tyControls.Alert'; K: 'TyAlert,TyAlertClose'),
    (U: 'tyControls.Badge'; K: 'TyBadge'),
    (U: 'tyControls.Base'; K: 'TyForm'),
    (U: 'tyControls.Breadcrumb'; K: 'TyBreadcrumb,TyBreadcrumbItem'),
    (U: 'tyControls.Button'; K: 'TyBadge,TyButton'),
    (U: 'tyControls.Calendar'; K: 'TyCalendar,TyCalendarCell,TyCalendarTitle,TyCalendarWeekday'),
    (U: 'tyControls.Card'; K: 'TyCard,TyCardActions,TyCardHeader'),
    (U: 'tyControls.CheckBox'; K: 'TyCheckBox,TyRadioButton'),
    (U: 'tyControls.CheckListBox'; K: 'TyCheckBox'),
    (U: 'tyControls.CircularProgress'; K: 'TyCircularProgress,TyCircularProgressFill'),
    (U: 'tyControls.ComboBox'; K: 'TyComboBox,TyListBox,TyTextHint'),
    (U: 'tyControls.DateTimePicker'; K: 'TyCalendar,TyCheckBox,TyDateTimePicker,TyTextSelection'),
    (U: 'tyControls.Divider'; K: 'TyDivider'),
    (U: 'tyControls.Edit'; K: 'TyEdit,TyTextHint,TyTextSelection'),
    (U: 'tyControls.Empty'; K: 'TyEmpty,TyEmptyImage'),
    (U: 'tyControls.ExPanel'; K: 'TyExPanel,TyExPanelHeader'),
    (U: 'tyControls.Form'; K: 'TyCaptionButton,TyForm,TyTitleBar'),
    (U: 'tyControls.FormSurface'; K: 'TyFormSurface'),
    (U: 'tyControls.GlyphButtons'; K: 'TyGlyphContainerButton,TySpeedButton'),
    (U: 'tyControls.Grid'; K: 'TyGrid,TyGridActiveCell,TyGridButton,TyGridCell,TyGridCellAlt,' +
      'TyGridCellMarked,TyGridCellSelectedInactive,TyGridCheckBox,TyGridCommentMark,' +
      'TyGridFilterRow,TyGridFixed,TyGridGroupRow,TyGridHeader,TyGridHeaderGroup,' +
      'TyGridHeaderSection,TyGridHyperlink,TyGridIndicator,TyGridLine,TyGridProgress,' +
      'TyGridProgressFill,TyGridRating,TyGridRatingEmpty,TyGridSelectionFrame,TyGridSummaryRow'),
    (U: 'tyControls.GroupBox'; K: 'TyGroupBox'),
    (U: 'tyControls.LinkLabel'; K: 'TyLinkLabel,TyLinkLabelLink'),
    (U: 'tyControls.ListBox'; K: 'TyListBox,TyListItem'),
    (U: 'tyControls.ListView'; K: 'TyListView,TyListViewCheckBox,TyListViewGroupHeader,' +
      'TyListViewHeader,TyListViewHeaderSection,TyListViewItem,TyListViewLine,TyListViewMarquee'),
    (U: 'tyControls.Memo'; K: 'TyMemo,TyTextSelection'),
    (U: 'tyControls.Menu'; K: 'TyMenuBar,TyMenuItem,TyMenuPopup,TyMenuView'),
    (U: 'tyControls.Notification'; K: 'TyNotification,TyNotificationClose'),
    (U: 'tyControls.PageControl'; K: 'TyPageControl'),
    (U: 'tyControls.Panel'; K: 'TyPanel'),
    (U: 'tyControls.ProgressBar'; K: 'TyProgressBar,TyProgressFill,TyTextHint'),
    (U: 'tyControls.Rating'; K: 'TyRating,TyRatingStar'),
    (U: 'tyControls.ScrollBar'; K: 'TyScrollBar,TyScrollThumb'),
    (U: 'tyControls.ScrollBox'; K: 'TyScrollBox'),
    (U: 'tyControls.ScrollContent'; K: 'TyScrollContent'),
    (U: 'tyControls.SpinEdit'; K: 'TySpinEdit,TyTextHint'),
    (U: 'tyControls.Splitter'; K: 'TySplitter'),
    (U: 'tyControls.StatusBar'; K: 'TyStatusBar'),
    (U: 'tyControls.TabSet'; K: 'TyTabSet'),
    (U: 'tyControls.TabSheet'; K: 'TyTabSheet'),
    (U: 'tyControls.TabStrip'; K: 'TyTab,TyTabClose'),
    (U: 'tyControls.Tag'; K: 'TyTag,TyTagClose'),
    (U: 'tyControls.ToggleSwitch'; K: 'TyToggleKnob,TyToggleSwitch'),
    (U: 'tyControls.ToolBar'; K: 'TyToolBar,TyToolSeparator'),
    (U: 'tyControls.TrackBar'; K: 'TyTrackBar,TyTrackGroove,TyTrackThumb'),
    (U: 'tyControls.TreeView'; K: 'TyTreeCheckBox,TyTreeHeader,TyTreeHeaderSection,TyTreeNode,TyTreeView'),
    (U: 'tyControls.TyLabel'; K: 'TyLabel'),
    (U: 'tyControls.UpDown'; K: 'TyButton,TyUpDown'),
    (U: 'tyControls.ValueListEditor'; K: 'TyListBox,TyValueListEditor,TyValueListEditorDivider,' +
      'TyValueListEditorExpander,TyValueListEditorKey,TyValueListEditorRow,TyValueListEditorValue'));
```

  （49 行，是写计划时按 CV4 的规则扫源码得到的；扫出来为空的单元（`Dialogs`、`DropButtons`、`Columns`、`Component`、`IconFont`、`Icons.Lucide`、`ImageCollection`）不列行。`TyActivityIndicatorFill`、`TyCircularProgressFill`、`TyRatingStar` 是手工补的拼接键。执行时 CV4 若报出缺行——运行时遇到了写计划时没走到的单元——照它打印的键补一行。）`TbPartKeysOfUnit`：`SameText` 查行。`TbPartKeysOfClass(AClass, ADest)`：`c := AClass`，循环到 `nil`：按 `c.UnitName` 查行、逗号拆开加进 `ADest`；`c := c.ClassParent`。`TbPartKeyUnits` 返回全部 `U`。

- [ ] **Step 2: 三份集合与两张单子**：
  - `TbDocTypeKeys`：扫描里每个 `tbkRule` 块的每个选择器类型名，加进 `ADest`（调用方传入 `Sorted`、`dupIgnore`、`CaseSensitive = False` 的列表）。
  - `TbBaseTypeKeys`：`TTyCssParser.Create(TyBuiltinThemeCss).Parse`，每条规则每个选择器的 `TypeName`；结果缓存在一个单元级的 `TStringList` 里（`finalization` 释放）。
  - `TbCoverage(ADoc, APreview, ABase, ANotShown, ADefaultLook)`：`ANotShown` = `ADoc` 里不在 `APreview` 的；`ADefaultLook` = `APreview` 里既不在 `ADoc` 也不在 `ABase` 的；两者都清空后按字母序填。

- [ ] **Step 3: 预览摆了哪些**（`tbpreview.pas` 的 `CollectTypeKeys`）：`ADest` 应为已排序去重不分大小写的列表。

```pascal
procedure TTbPreviewFrame.CollectTypeKeys(ADest: TStrings);

  procedure AddControl(AControl: TControl);
  var
    i: Integer;
  begin
    if Supports(AControl, ITyStyleable) then
      ADest.Add((AControl as ITyStyleable).GetStyleTypeKey);
    TbPartKeysOfClass(AControl.ClassType, ADest);
    if AControl is TWinControl then
      for i := 0 to TWinControl(AControl).ControlCount - 1 do
        AddControl(TWinControl(AControl).Controls[i]);
  end;

var
  d: TTyDialog;
begin
  AddControl(Root);
  AddControl(BuildSampleWindow);
  d := BuildSampleDialog;
  try AddControl(d); finally d.Free; end;
  d := BuildSampleInput;
  try AddControl(d); finally d.Free; end;
  TbPartKeysOfClass(SamplePopup.ClassType, ADest);
  ADest.Add(TTyNotification.StyleTypeKey);
  ADest.Add(TTyNotification.CloseStyleTypeKey);
end;
```

- [ ] **Step 4: 对话框**（`tbcoverageform.lfm`：`object TbCoverageForm: TTbCoverageForm`，`TitleBar = Bar`，`Caption = 'Coverage check'`，宽 520 高 460，`Position = poOwnerFormCenter`，`OnCreate = FormCreate`；`Surface: TTyFormSurface` 里 `Bar: TTyTitleBar`（`'Coverage check'`）、`LblNotShown: TTyLabel`（'Styled in this theme but not in the preview:'）、`LstNotShown: TTyListBox`、`LblDefault: TTyLabel`（'In the preview, but neither this theme nor the base styles them (they keep their built-in look):'，`WordWrap`）、`LstDefault: TTyListBox`、`LblHint: TTyLabel`（'Double-click an entry to go to its rule, or add one.'）、`BtnClose: TTyButton`（'Close'，`ModalResult = 2`））。`FormCreate`：`ApplyChromeTheme(TyDefaultController)`。`Fill`：两个列表各填一行一项，`TyCatalogTypeKeys` 里没有的在后面加 `'  ' + rsTbCovUnknownKey`（'(not a known typeKey)'），原键另存一份（`FNotShownKeys`、`FDefaultKeys`）；两个列表的 `OnDblClick` → `FChosen := 对应键; ModalResult := mrOk`。

- [ ] **Step 5: 判据测试**（`TTbCoverageTests`）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| CV1 | `TbBaseTypeKeys`：含 `TyButton`、`TyTab`、`TyScrollThumb`、`TyUpDown`（它在 `light.tycss:342` 的并列选择器里、从不打头）；不含 `TyFormSurface`、`TyListViewLine`（§8.4）；条数 ≥ 150 | 只收每条规则的第一个选择器（`TyUpDown` 缺）。（改用 `TyCatalogTypeKeys` 这一变异目前等价：目录与底层规则的选择器头是同一个集合，签收写明） |
| CV2 | `TbCoverage`：doc = {TyButton, TyRibbon, TyButon}、preview = {TyButton, TyTab, TyFormSurface}、base = {TyButton, TyTab} → 不在预览 = [TyButon, TyRibbon]；默认样子 = [TyFormSurface] | 第二张单子不减 `ADoc`（文档写了的也列进去） |
| CV3 | 预览：`CollectTypeKeys` 含 `TyButton`、`TyTab`、`TyScrollThumb`、`TyMenuItem`、`TyNotificationClose`、`TyCaptionButton`、`TyTitleBar`、`TyToggleKnob`；不含 `TyRibbon`、`TyTerminal`、`TyAdvChart` | ① 只取控件自己的 typeKey（`TyTab` 缺）；② 不走祖先类（`TyTab` 在 `TabStrip`，`TTyPageControl` 的父类的单元） |
| CV4 | 表的守卫：建预览 frame + 样例窗口 + 两个对话框，收集遇到的每个类及其祖先类的 `UnitName`（以 `tyControls.` 开头的）；对每个单元读 `source/<单元>.pas`，按下面的规则取字面量键：(a) 源码里去掉 `{ }`（嵌套计数）、`(* *)`、`//` 注释后，所有单引号字符串里**整串**匹配 `^Ty[A-Z][A-Za-z0-9]*$` 且不是 `TyControls` 的；断言 (a) ⊆ 该单元的行；另对表里**每一行**断言：行里每个键 ∈ (a) ∪ `TyCatalogTypeKeys`。失败信息打印单元与缺 / 多的键 | 从 `TabStrip` 行删掉 `TyTab` |
| CV5 | 端到端：极简模板 → 不在预览为空、默认样子含 `TyFormSurface`、`TyListViewLine`、**不含** `TyButton`；`'TyRibbon { }'` → 不在预览 = [TyRibbon] | 第二张单子不减底层（`TyButton` 出现在默认样子里） |
| CV6 | 文档键：`'TyButton.primary:hover, TyEdit { }'#10'@mode dark { :root { --a: #111; } }'` → [TyButton, TyEdit] | — |
| CV7 | 对话框：`Fill` 之后 `LstNotShown.Items` 里 `TyButon` 那一项带 `rsTbCovUnknownKey`、`TyRibbon` 那一项不带；模拟双击第一项（设 `ItemIndex`、调 `OnDblClick`）→ `Chosen = 'TyButon'`、`ModalResult = mrOk` | 双击存的是显示文本（`Chosen` 带注释） |

- [ ] **Step 6: 提交**：`.lpi` 加 `tbcoverage.pas`、`tbcoverageform.pas`（窗体项）。`feat(themebuilder): the coverage check -- styled but not shown, shown but not styled` + Co-Authored-By。

---

### Task 7: 导出主题包

**Files:**
- Create: `tools/themebuilder/tbexport.pas`、`tbexportform.pas`、`tbexportform.lfm`、`tests/test.themebuilder.export.pas`（suite `TTbExportTests`）
- Modify: `tools/themebuilder/themebuilder.lpi`、`tests/tytests.lpr`

- [ ] **Step 1: 单元头注释**：包的格式以读取端为准（核实记录 26：入口 `theme.tycss`、清单 `theme.json` 的字段）；两种格式与 zip 的限制（核实记录 27，开工前问题一第 1 条）；引用文件怎么收（核实记录 28）；「读回并加载」的标准（核实记录 30）；失败不留痕。

- [ ] **Step 2: 收集**（`TbCollectBundleFiles`）：
  - 入口文本与每个导入的文件都用 `TbScanCss` 扫。`@import`：从扫描拿不到路径（导入不是块），另写一个小走查：`TTyCssLexer` 顶层遇 `ctkAtKeyword` `import` → 下一个记号是 `ctkString`（取 `Text`）或 `ctkFunction` `url` 后接的记号串（到 `)`）→ 原始路径。`url()`：每个块每条声明的值里找 `url(`（不分大小写），取到 `)`，去引号、去空白；`data:` 开头的跳过。
  - 路径检查（每一条都查，问题逐行累加进 `AError`，格式 `rsTbExportBadRef = '%s: %s'`（路径、原因））：绝对路径（`FilenameIsAbsolute`，或以 `/`、`\` 开头）→ `rsTbExportAbsolute`（'an absolute path; move the file next to the theme'）；任何一段是 `..` → `rsTbExportOutside`（'outside the theme''s folder'）；`ABaseDir = ''`（未保存）→ `rsTbExportUnsaved`（'save the theme first: paths are read from its folder'）；文件不在 → `rsTbExportMissing`（'not found'）。
  - 解析：`@import` 相对于导入它的文件所在目录（入口就是 `ABaseDir`），递归；`url()` **一律**相对于 `ABaseDir`。归档名 = 相对于 `ABaseDir` 的路径，分隔符换成 `/`。按展开后的全路径（Windows 上小写比较）去重；同一个 `@import` 文件只展开一次（钻石）。导入循环不报错（第二次遇到直接跳过——预览加载会报循环，这里只收文件）。
  - 返回：`AError = ''` 时 True。没有任何引用时 `AFiles = nil`、True（未保存的文档也可以导出）。

- [ ] **Step 3: 清单**：`TbManifestJson` 用 `fpjson` 的 `TJSONObject`：`name`、`author`、`version`、`entry` = `cTyDefaultThemeEntry`、`dualMode`；`FormatJSON` 输出（字符串转义交给 fpjson）。

- [ ] **Step 4: 写、读回、提交**：

```pascal
function TbExportBundle(const AEntry: string; const AFiles: TTbBundleFiles;
  const AInfo: TTbBundleInfo; AFormat: TTbBundleFormat; const ATarget: string;
  out AError: string): Boolean;
var
  temp: string;
begin
  AError := '';
  Result := False;
  if not CheckTarget(AFormat, ATarget, AError) then Exit;       { step 4a }
  if (AFormat = tbfZip) and (Length(AFiles) > 0) then
  begin
    AError := rsTbExportZipRefs;                                   { step 4b }
    Exit;
  end;
  temp := ATarget + '.tbtmp' + IntToStr(GetProcessID);
  try
    WriteBundle(AFormat, temp, AEntry, AFiles, AInfo);             { step 4c }
    if not VerifyBundle(AFormat, temp, AEntry, AFiles, AInfo, AError) then   { step 4d }
      Exit;
    Result := CommitBundle(AFormat, temp, ATarget, AError);        { step 4e }
  except
    on E: Exception do
      AError := E.Message;
  end;
  if not Result then
    RemoveTemp(AFormat, temp);
end;
```

  - 4a `CheckTarget`：目标为空 → `rsTbExportNoTarget`；文件夹格式：目标存在且不是空目录 → `rsTbExportFolderNotEmpty`（'%s is not an empty folder.'）；目标是一个文件 → 同一句；目标的父目录不存在 → `rsTbExportNoParent`。zip：目标是目录 → `rsTbExportNotAFile`。（zip 已存在时的「覆盖吗」由对话框在调用前问。）
  - 4b `rsTbExportZipRefs = 'A zip bundle cannot carry the files this theme refers to (the library reads neither @import nor images from a zip). Export a folder.'`
  - 4c `WriteBundle`：文件夹 → `ForceDirectories(temp)`，写 `theme.tycss`（`AEntry` 原样字节）、`theme.json`，每个引用文件 `ForceDirectories` 后按字节复制到 `temp + 归档名`（分隔符换回 `PathDelim`）；zip → `TZipper`，`FileName := temp`，`Entries.AddFileEntry(TStringStream.Create(AEntry), 'theme.tycss')`、同法加 `theme.json`，`ZipAllFiles`，流在 `finally` 里释放。
  - 4d `VerifyBundle`：`src` = 文件夹 → `TTyThemeDirSource.Create(temp)`，zip → `TTyThemeZipSource.Create(temp)`；`src.Manifest.Entry = 'theme.tycss'`、`Name` / `Author` / `Version` / `DualMode` 与 `AInfo` 相同；`src.RootCss` 非空；每个引用文件 `src.OpenAsset(归档名, stm)` 为 True（流随即释放）；新建 `TTyStyleModel`，`LoadFromSource(src)`（异常 → 失败，消息进 `AError`）；模式 = `ModeNames`，空就 `['']`；逐个 `SetMode` + `TbProbeResolve`（`tbpreview`），失败的消息前加 `Format(rsTbModeFailed, [模式, …])`；模型在 `finally` 里释放。任何一步不对 → `AError := rsTbExportVerifyFailed + ': ' + 原因`，False。
  - 4e `CommitBundle`：文件夹 → 目标是空目录就先 `RemoveDir`；`RenameFile(temp, ATarget)`。zip → 目标存在：先 `RenameFile(ATarget, ATarget + '.tbbak')`；`RenameFile(temp, ATarget)` 失败就把 `.tbbak` 改回来、报错；成功删 `.tbbak`。
  - `RemoveTemp`：文件夹 `DeleteDirectory(temp, False)`（`FileUtil`），zip `DeleteFile(temp)`；都在 `try … except end` 里（清理失败不再抛）。

- [ ] **Step 5: 对话框**（`tbexportform.lfm`：`object TbExportForm: TTbExportForm`，`TitleBar = Bar`，`Caption = 'Export a theme bundle'`，宽 560 高 480，`OnCreate = FormCreate`；`Surface` 里：`Bar`、`LblName` / `EdtName`、`LblAuthor` / `EdtAuthor`、`LblVersion` / `EdtVersion`、`RadFolder: TTyRadioButton`（'A folder'）、`RadZip: TTyRadioButton`（'A zip file'）、`LblTarget` / `EdtTarget` / `BtnBrowse`（'Browse...'）、`LblFiles`（'Files that go in with theme.tycss and theme.json:'）、`LstFiles: TTyListBox`、`LblNote: TTyLabel`（`WordWrap`）、`BtnExport: TTyButton`（'Export'，`StyleClass = primary`）、`BtnCancel`（'Cancel'，`ModalResult = 2`）；非可视 `DlgFolder: TTySelectPathDialog`、`DlgZip: TTySaveDialog`）。
  - `FormCreate`：`ApplyChromeTheme(TyDefaultController)`；单选的初值在 `Prepare` 里设。
  - `Prepare(AEntry, ABaseDir, AName, ADualMode)`：存下；`EdtName.Text := AName`、`EdtVersion.Text := '1.0'`；`FOk := TbCollectBundleFiles(文本, ABaseDir, FFiles, FCollectError)`——文本 = `AEntry`；`LstFiles` 列出归档名（没有时一行 `rsTbExportOnlyTheme`（'(none)'））；`FOk` 为 False → `LblNote.Caption := FCollectError`、`BtnExport.Enabled := False`；有引用文件 → `RadZip.Enabled := False`、`LblNote` 说 zip 为什么不可用（`rsTbExportZipRefs`）；`RadFolder.Checked := True`；默认目标 = `ABaseDir` 非空时 `ABaseDir + AName`（文件夹）/ `+ '.zip'`（zip），切换单选时跟着换扩展名。
  - `DoExport(out AError)`：`info` 取三个编辑框与 `ADualMode`；zip 且目标文件已存在 → 经 `OnAsk`（`TTbAskEvent`，`tbseedsframe` 里声明的那个类型；主窗体挂它的 `Ask`，测试由 `PromptAnswerForTest` 回答；没挂时当作 `mrNo`）问 `Format(rsTbExportOverwrite, [目标])`，不是 `mrYes` 就 False；`Result := TbExportBundle(FEntry, FFiles, info, 格式, 目标, AError)`；成功 `ModalResult := mrOk`，失败 `LblNote.Caption := AError`。`BtnExportClick` 调它。`BtnBrowseClick`：文件夹 `DlgFolder.Execute` → `EdtTarget.Text := DlgFolder.Directory + PathDelim + EdtName.Text`；zip `DlgZip.Execute` → `EdtTarget.Text := DlgZip.FileName`（测试不点它）。

- [ ] **Step 6: resourcestring**（`tbexport.pas` / `tbexportform.pas`）：`rsTbExportBadRef`、`rsTbExportAbsolute`、`rsTbExportOutside`、`rsTbExportUnsaved`、`rsTbExportMissing`、`rsTbExportNoTarget = 'Choose where to export to.'`、`rsTbExportFolderNotEmpty`、`rsTbExportNoParent = 'The folder %s does not exist.'`、`rsTbExportNotAFile = '%s is a folder.'`、`rsTbExportZipRefs`、`rsTbExportVerifyFailed = 'The bundle did not load back'`、`rsTbExportOnlyTheme`、`rsTbExportOverwrite = '%s exists. Replace it?'`。

- [ ] **Step 7: 判据测试**（`TTbExportTests`；每条测试一个临时目录（`GetTempDir` + 进程号 + 序号），`TearDown` 删掉；一个 1×1 PNG 的字节放在测试单元的常量里、按需写文件；「没有残留」= 目标的父目录里用 `FindAllFiles(父目录, '*.tbtmp*;*.tbbak', False)` 为空、且 `FindAllDirectories` 里没有 `.tbtmp`）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| X1 | 把仓库的 `themes/green.tycss` 与 `themes/assets/background.jpg` 复制进临时目录（保持 `assets/`），收集 → True，一个文件，归档名 `assets/background.jpg` | — |
| X2 | 导入链：入口 `'@import "parts/a.tycss";'#10'TyButton { color: #111111; }'`；`parts/a.tycss` = `'@import "b.tycss";'`；`parts/b.tycss` = `'TyPanel { background-image: url(img/x.png) slice(0 0 0 0); }'`；`img/x.png`（在**入口**目录下）→ 文件 = `parts/a.tycss`、`parts/b.tycss`、`img/x.png`（三个，去重） | ① 嵌套的 `@import` 相对入口目录解析（找不到 `parts/b.tycss` 报缺）；② `url()` 相对导入文件的目录（找 `parts/img/x.png` 报缺） |
| X3 | 拒绝：`url(C:\x.png)`（Windows）/ `url(/x.png)` → 含 `rsTbExportAbsolute`；`@import "../x.tycss"` → 含 `rsTbExportOutside`；`url(nope.png)` → 含 `rsTbExportMissing`；`ABaseDir = ''` 且有 `url(a.png)` → 含 `rsTbExportUnsaved`；`ABaseDir = ''` 且无引用 → True、无文件；`url(data:image/png;base64,AAAA)` → 不收 | 不查 `..` |
| X4 | 文件夹导出 X1 → True；目标目录里恰好 `theme.tycss`（字节 = `AEntry`）、`theme.json`、`assets/background.jpg`（字节相同）；`TTyThemeDirSource.Create(目标).Manifest` 的 `Name` / `Author` / `Version` / `DualMode` 与传入的相同、`Entry = 'theme.tycss'`；没有残留 | — |
| X5 | zip 导出（极简模板，无引用）→ True；`TUnZipper.Examine` 后条目恰好两个 `theme.tycss`、`theme.json`；`TTyThemeZipSource.Create(目标).RootCss` 与 `AEntry` 在两边都换成 LF 后相等；`Manifest.DualMode = True`；没有残留 | `WriteBundle` 的 zip 分支漏写 `theme.json`（清单名回落成 zip 文件名） |
| X6 | zip 带引用（X1）→ False、`AError = rsTbExportZipRefs`、目标不存在、没有残留 | 去掉 4b 那一检查（读回后图片不在磁盘上，但加载仍过——所以必须靠这条检查挡） |
| X7 | 失败不留痕：入口 `'@mode light { :root { --z: #ffffff; } }'#10'@mode dark { :root { --y: #000000; } }'#10'TyButton { background: var(--z); }'`（加载过、暗色试解析失败）→ 文件夹导出 False、`AError` 以 `rsTbExportVerifyFailed` 开头、目标不存在、没有残留；zip 同样；**另**先在目标写一个任意内容的 `old.zip`，对它做同样失败的 zip 导出 → `old.zip` 逐字节不变 | ① 读回只试默认模式（导出成功——必须红）；② 失败后不删临时目录（残留） |
| X8 | 目标是非空目录（里面放一个 `keep.txt`）→ False、`AError` 含 `rsTbExportFolderNotEmpty` 的前半句、`keep.txt` 还在、没有残留；目标是空目录 → 成功 | 不查非空（`keep.txt` 被连目录删掉） |
| X9 | 覆盖已有 zip：先导出一次，再用不同的 `AInfo.Version` 导出到同一目标 → True；读回的 `Version` 是新的；没有 `.tbbak` | 成功后不删 `.tbbak` |
| X10 | `TbManifestJson` 经 `TyParseThemeManifest` 读回：名字含 `"`、`\`、汉字时各字段相同、`Loaded = True` | 手拼 JSON 不转义（`"` 那一条解析失败、回落默认） |
| X11 | 对话框：`TTbExportForm.Create(nil)`，`Prepare`（X1 的入口与目录）→ `LstFiles.Items` 含 `assets/background.jpg`；`RadZip.Enabled = False`；`EdtTarget.Text` 以 `.zip` 以外结尾（文件夹）；`EdtTarget.Text := 临时目标; DoExport` → True、`ModalResult = mrOk`；未保存且有 `url(a.png)` 的 `Prepare` → `BtnExport.Enabled = False`、`LblNote.Caption` 含 `rsTbExportUnsaved` | `Prepare` 不按引用禁用 zip |

- [ ] **Step 8: 注册与提交**：`.lpi` 加两个单元（窗体项）；uses 加 `test.themebuilder.export`。`feat(themebuilder): export a theme bundle, read it back through the library, leave nothing behind on failure` + Co-Authored-By。

---

### Task 8: 代码片段

**Files:**
- Create: `tools/themebuilder/tbsnippets.pas`、`tbsnippetsform.pas`、`tbsnippetsform.lfm`、`tests/test.themebuilder.snippets.pas`（suite `TTbSnippetsTests`）
- Modify: `tools/themebuilder/themebuilder.lpi`、`tests/tytests.lpr`

- [ ] **Step 1: 片段正文**（`tbsnippets.pas`；`%NAME%` = 主题名，`%FILE%` = 文件名，都先经 `TbPascalQuote`（单引号加倍）再代入；每行两格缩进，行与行之间用 `LineEnding`）：

  `tsnFile`（uses `tyControls.Controller`）：

```pascal
begin
  TyDefaultController.ThemeFile := ExtractFilePath(ParamStr(0)) + '%FILE%';
  ApplyChromeTheme(TyDefaultController);
end;
```

  `tsnFolder`（uses `tyControls.Controller, tyControls.ThemeRegistry`）：

```pascal
begin
  TyRegisterThemeFolder('%NAME%', ExtractFilePath(ParamStr(0)) + '%NAME%');
  TyDefaultController.ThemeName := '%NAME%';
  ApplyChromeTheme(TyDefaultController);
end;
```

  `tsnZip`（uses `tyControls.Controller, tyControls.ThemeRegistry, tyControls.ThemeBundle`）：

```pascal
var
  bundle: ITyThemeSource;
begin
  bundle := TTyThemeZipSource.Create(ExtractFilePath(ParamStr(0)) + '%NAME%.zip');
  TyRegisterThemeCss('%NAME%', bundle.RootCss);
  TyDefaultController.ThemeName := '%NAME%';
  ApplyChromeTheme(TyDefaultController);
end;
```

  `tsnRegister`（uses `tyControls.Controller, tyControls.ThemeRegistry`）：

```pascal
begin
  TyRegisterThemeCss('%NAME%', ThemeCss);
  TyDefaultController.ThemeName := '%NAME%';
  ApplyChromeTheme(TyDefaultController);
end;
```

  `TbSnippet(AKind, AName, AFileName, ACss)` = `'// uses ' + TbSnippetUses(AKind) + ';'` + 换行 + `'// ' + rsTbSnippetWhere`（'in your main form (a TTyForm):'）+ 换行 + （`tsnRegister` 时再加 `TbPascalCssFunction('ThemeCss', ACss)` + 空行）+ `'procedure TMainForm.FormCreate(Sender: TObject);'` + 换行 + `TbSnippetBody(…)`。（注释行里的 `rsTbSnippetWhere` 译；代码不译。）

- [ ] **Step 2: CSS 转 Pascal 函数**（`TbPascalCssFunction(AFuncName, ACss)`）：按任意换行（LF / CRLF / CR）把 `ACss` 拆行（文末有换行时不产生最后那个空行）；每行按 200 字节切段，切点不落在 UTF-8 续字节（`$80..$BF`）上（往前退到首字节）；每段单引号加倍后成 `'段'`，同一行的段用 ` + ` 连；输出：

```
function <AFuncName>: string;
begin
  Result :=
    '<行1>' + LineEnding +
    …
    '<末行>'<若 ACss 以换行结尾则为 " + LineEnding"，否则无>;
end;
```

  空文本 → `function X: string;` / `begin` / `  Result := '';` / `end;`。

- [ ] **Step 3: 主题名**（`TbSnippetThemeName(AFileName, ABasedOn)`）：有文件名 → 去扩展名的文件名；否则 `ABasedOn`；都空 → `'mytheme'`；然后转小写，`[a-z0-9_-]` 以外的连续字符换成一个 `-`，去掉首尾 `-`，结果为空时 `'mytheme'`。

- [ ] **Step 4: 小窗**（`tbsnippetsform.lfm`：`object TbSnippetsForm: TTbSnippetsForm`，`TitleBar = Bar`，`Caption = 'Use it in a program'`，宽 680 高 520，`OnCreate = FormCreate`；`Surface` 里 `Bar`、`Pages: TTyPageControl`（`alClient`）三页：`TabFile 'From a file'`（`LblFile: TTyLabel` 说明 'Put the .tycss file next to your program.'、`MemoFile: TTyMemo`（`ReadOnly = True`、`ScrollBars = ssBoth`）、`BtnCopyFile: TTyButton` 'Copy'）、`TabBundle 'From a theme bundle'`（`LblFolder`（'A folder bundle, exported next to your program:'）、`MemoFolder`、`BtnCopyFolder`、`LblZip`（'A zip bundle (a theme that refers to no other file):'）、`MemoZip`、`BtnCopyZip`）、`TabRegister 'Registered by name'`（`LblRegister`（'The theme compiled into your program, no file needed:'）、`MemoRegister`、`BtnCopyRegister`）；`BtnClose`（'Close'，`ModalResult = 2`））。`FormCreate`：`ApplyChromeTheme(TyDefaultController)`；四个 Memo 的字体取 1 期 `tbeditorlook` 的 `TbEditorColors(TyDefaultController).FontName`（等宽）。`Prepare`：四个 Memo 的 `Lines.Text` = 对应的 `TbSnippet`。复制按钮：`Clipboard.AsText := 对应 Memo.Lines.Text`（`Clipbrd`）。

- [ ] **Step 5: 编进测试工程的真代码**（`tests/test.themebuilder.snippets.pas`；单元头注释说明这个单元的用途：片段真的能编；守卫把下面标出的几段与 `tbsnippets` 的输出逐行比）。interface 的 uses 必须含 `tyControls.Controller, tyControls.ThemeRegistry, tyControls.ThemeBundle, tyControls.Form`。结构：

```pascal
type
  { the snippets, compiled: each method body is exactly what the window shows }
  TSnippetHost = class(TTyForm)
  public
    procedure FromFile;
    procedure FromFolder;
    procedure FromZip;
    procedure Registered;
  end;

// >>> function
function ThemeCss: string;
begin
  Result :=
    '/* A minimal theme: the six seeds, light and dark. Everything else comes from the base theme. */' + LineEnding +
    '' + LineEnding +
    '@mode light {' + LineEnding +
    '  :root {' + LineEnding +
    '    --accent: #3B82F6;' + LineEnding +
    '    --surface: #FFFFFF;' + LineEnding +
    '    --on-surface: #1F2937;' + LineEnding +
    '    --border: #D1D5DB;' + LineEnding +
    '    --danger: #EF4444;' + LineEnding +
    '    --radius: 6px;' + LineEnding +
    '  }' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '@mode dark {' + LineEnding +
    '  :root {' + LineEnding +
    '    --accent: #60A5FA;' + LineEnding +
    '    --surface: #1E1E1E;' + LineEnding +
    '    --on-surface: #E5E7EB;' + LineEnding +
    '    --border: #3F3F46;' + LineEnding +
    '    --danger: #F87171;' + LineEnding +
    '    --radius: 6px;' + LineEnding +
    '  }' + LineEnding +
    '}' + LineEnding;
end;
// <<< function

procedure TSnippetHost.FromFile;
// >>> file
begin
  TyDefaultController.ThemeFile := ExtractFilePath(ParamStr(0)) + 'mytheme.tycss';
  ApplyChromeTheme(TyDefaultController);
end;
// <<< file
```

  `FromFolder`（`// >>> folder`）、`FromZip`（`// >>> zip`）、`Registered`（`// >>> register`）同理，名字一律 `mytheme`、文件 `mytheme.tycss`。（`ThemeCss` 的第一行是 1 期 `rsTbMinimalHeader` 的英文原文；若 1 期收尾改过那句，照改。）

- [ ] **Step 6: 判据测试**（`TTbSnippetsTests`；读自己的源文件 = `TbRepoDir + 'tests' + PathDelim + 'test.themebuilder.snippets.pas'`；取 `// >>> 名` 与 `// <<< 名` 之间的行、各自去行尾空白）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| S1 | 四段正文：`TbSnippetBody(种类, 'mytheme', 'mytheme.tycss')` 拆行去行尾空白后与对应标记段逐行相等 | 改 `TbSnippetBody` 的一处名字（如 `TyRegisterThemeFolder` 写成 `TyRegisterThemeDir`）——片段对不上真代码 |
| S2 | 函数：`TbPascalCssFunction('ThemeCss', TbMinimalTemplate)` 与 `function` 段逐行相等；且 `ThemeCss = TbMinimalTemplate`（编出来的函数真的还原了文本） | 末行不按「文末有换行」加 `+ LineEnding` |
| S3 | uses：四种 `TbSnippetUses` 里的每个单元名都出现在本测试单元的 uses 里（按文本查） | 片段声称的 uses 少了 `tyControls.ThemeBundle`（zip 那段在真实程序里编不过——本测试单元仍编得过，所以靠这条） |
| S4 | 真跑一次「注册」：`h := TSnippetHost.CreateNew(nil)`（记下 `TyDefaultController.ThemeName` / `Mode`）；`h.Registered` → `TyThemeRegistered('mytheme')`、`TyDefaultController.ThemeName = 'mytheme'`、`Model.RawVar('--accent') = '#3B82F6'`（亮色）；`finally` 还原主题名与模式、`TyUnregisterTheme('mytheme')`、`h.Free` | — （API 路径的冒烟） |
| S5 | `TbPascalCssFunction` 的表：`'a''b'` → 段 `'a''''b'`；一行 450 个 `x` → 三段 `200 + 200 + 50`；199 个 `x` 接 `中`（3 字节）→ 第一段 199 字节、`中` 整个在第二段；`''` → `Result := '';`；`'a'#13#10'b'`（无文末换行）→ 末行 `'b';` | 按 200 字节硬切（`中` 被切开） |
| S6 | `TbSnippetThemeName`：`('C:\t\My Theme!.tycss', '')` → `'my-theme'`；`('', 'win11')` → `'win11'`；`('', '')` → `'mytheme'`；`('///.tycss','')` → `'mytheme'` | — |
| S7 | 小窗：`TTbSnippetsForm.Create(nil)`，`Prepare('green', 'green.tycss', 'TyButton { }')` → `MemoFile` 含 `'green.tycss'`，`MemoFolder` 含 `TyRegisterThemeFolder('green'`，`MemoZip` 含 `'green.zip'`，`MemoRegister` 含 `function ThemeCss` 与 `'TyButton { }'`；`Pages.PageCount = 3` | `Prepare` 漏填一个 Memo |

- [ ] **Step 7: resourcestring**：`rsTbSnippetWhere`。

- [ ] **Step 8: 注册与提交**：`.lpi` 加两个单元；uses 加 `test.themebuilder.snippets`。`feat(themebuilder): how to use the theme in a program, in snippets the test project compiles` + Co-Authored-By。

---

### Task 9: 主窗体接线

**Files:**
- Modify: `tools/themebuilder/tbmain.pas`、`tbmain.lfm`、`tests/test.themebuilder.main.pas`

- [ ] **Step 1: `.lfm`**：
  - `SideBar` 里在 `ProblemsWin` **之前**加 `SeedsWin: TTyToolWindow`（`Caption = 'Seeds'`、`ImageName = 'palette'`、`StripHint = 'Seeds'`），里面 `SeedsHost: TTyPanel`（`alClient`）；`SideBar.ActiveIndex = 0`；`Icons.Names` 加 `palette`。
  - 菜单：`MnuFile` 里 `MnuSaveAs` 之后加 `MnuExportSep`（`-`）、`MnuExport '&Export theme bundle...'`、`MnuSnippets '&Use it in a program...'`；`MnuView` 里 `MnuProblems` 之前加 `MnuSeeds '&Seeds'`，之后加 `MnuViewSep2`（`-`）、`MnuCoverage '&Coverage check...'`。
- [ ] **Step 2: `FormCreate`**（在 `FPreview` 建好之后、`NewMinimal` 之前）：

```pascal
  FSeeds := TTbSeedsFrame.Create(Self);
  FSeeds.Parent := SeedsHost;
  FSeeds.Align := alClient;
  FSeeds.OnEdits := @SeedsEdits;
  FSeeds.OnAsk := @Ask;
  FSeeds.OnSync := @SeedsSync;
  FPreview.OnPick := @PreviewPick;
```

  `FormDestroy` 开头：`if FSeeds <> nil then begin FSeeds.OnEdits := nil; FSeeds.OnAsk := nil; FSeeds.OnSync := nil; end; if FPreview <> nil then FPreview.OnPick := nil;`。
- [ ] **Step 3: 刷新**：`RefreshNow` 在收集问题之后、`ShowProblems` 之前加 `if FSeeds <> nil then FSeeds.UpdateFrom(css, FDoc.BaseDir, TbHasParseError(FProblems));`（实现期修正（开工核对）：1 期期末拆出 `BuildProblems`，这时 `FProblems` 还没建，传 `FParseFailed`）。`SeedsSync`：`if RefreshTimer.Enabled or ((FSeeds <> nil) and (Editor.Lines.Text <> FSeeds.ScannedText)) then RefreshNow;`。
- [ ] **Step 4: 一步撤销**：

```pascal
function TTbMainForm.ApplyEdits(const AText: string; const AEdits: TTbTextEdits): Boolean;
var
  i: Integer;
begin
  Result := False;
  { the edits were worked out on AText; on any other text their offsets mean nothing }
  if (Length(AEdits) = 0) or (Editor.Lines.Text <> AText) then Exit;
  Editor.BeginUndoBlock;
  try
    for i := High(AEdits) downto 0 do   { back to front: the earlier offsets stay good }
      Editor.SetTextBetweenPoints(TbOffsetToPoint(AText, AEdits[i].Start),
        TbOffsetToPoint(AText, AEdits[i].Stop), AEdits[i].Text, [], scamAdjust);
  finally
    Editor.EndUndoBlock;
  end;
  UpdateTitle;
  RefreshNow;
  Result := True;
end;
```

  `SeedsEdits(Sender, AText, AEdits)` = `ApplyEdits(AText, AEdits)`。
- [ ] **Step 5: Ctrl+点击**：

```pascal
procedure TTbMainForm.JumpToRule(const ATypeKey, AStyleClass: string);
var
  scan: TTbCssScan;
  classes: TStringArray;
  hits: TTbOffsets;
  i, caret: Integer;
  variant, key, text: string;
  edits: TTbTextEdits;
begin
  text := Editor.Lines.Text;
  scan := TbScanCss(text);
  try
    classes := SplitClasses(AStyleClass);
    hits := nil;
    variant := '';
    for i := 0 to High(classes) do
    begin
      hits := TbFindRuleSelectors(scan, ATypeKey, classes[i]);
      if Length(hits) > 0 then
      begin
        variant := classes[i];
        Break;
      end;
    end;
    if (Length(hits) = 0) and (Length(classes) = 0) then
      hits := TbFindRuleSelectors(scan, ATypeKey, '');
    if (Length(hits) = 0) and (Length(classes) > 0) then
      variant := classes[0];
    if Length(hits) > 0 then
    begin
      { the same control again: the next rule of that name, round and round }
      key := LowerCase(TbSelectorText(ATypeKey, variant));
      if key = FJumpKey then
        FJumpIndex := (FJumpIndex + 1) mod Length(hits)
      else
        FJumpIndex := 0;
      FJumpKey := key;
      Editor.LogicalCaretXY := TbOffsetToPoint(text, hits[FJumpIndex]);
    end
    else
    begin
      FJumpKey := '';
      edits := TbNewRuleEdits(scan, LineEnding, ATypeKey, variant, caret);
      if ApplyEdits(text, edits) then
        Editor.LogicalCaretXY := TbOffsetToPoint(TbApplyEdits(text, edits), caret);
    end;
  finally
    scan.Free;
  end;
  Editor.EnsureCursorPosVisible;
  if Showing and not Active then
    BringToFront;
  if Editor.CanSetFocus then
    Editor.SetFocus;
end;
```

  `SplitClasses`（implementation 私有；不用 `string.Split`：`{$mode objfpc}` 下用基本类型的 helper 要另开 modeswitch）：`n := WordCount(S, [' ', #9])`，`Result[i-1] := ExtractWord(i, S, [' ', #9])`（`StrUtils`）。`PreviewPick(Sender, ATypeKey, AStyleClass)` = `JumpToRule(…)`。字段 `FJumpKey: string`、`FJumpIndex: Integer`。
- [ ] **Step 6: 菜单与对话框**：
  - `BuildCoverageForm`：`doc`、`prev`、`base` 三个排序去重不分大小写的 `TStringList`；`scan := TbScanCss(Editor.Lines.Text)`；`TbDocTypeKeys(scan, doc)`、`FPreview.CollectTypeKeys(prev)`、`TbBaseTypeKeys(base)`、`TbCoverage(…, notShown, def)`；`Result := TTbCoverageForm.Create(nil); Result.Fill(notShown, def);`；全部临时对象释放。`MnuCoverageClick`：`f := BuildCoverageForm; try if (f.ShowModal = mrOk) and (f.Chosen <> '') then JumpToRule(f.Chosen, ''); finally f.Free; end;`。
  - `EntryBytes` = `TbJoinLines(Editor.Lines, FDoc.LineEnding, FDoc.TrailingEol)`。`SnippetName` = `TbSnippetThemeName(FDoc.FileName, FDoc.BasedOn)`。
  - `BuildExportForm`：`Result := TTbExportForm.Create(nil); Result.OnAsk := @Ask; Result.Prepare(EntryBytes, FDoc.BaseDir, SnippetName, TbScanCss 的 HasModes);`（扫描对象用完释放）。`MnuExportClick`：`ShowModal` 为 `mrOk` → `SetStatus(Format(rsTbExported, [f.EdtTarget.Text]))`（'Exported to %s.'）。
  - `BuildSnippetsForm`：`Prepare(SnippetName, 文件名（未保存为 SnippetName + '.tycss'）, Editor.Lines.Text)`。`MnuSnippetsClick`：`ShowModal`。
  - `MnuSeedsClick` / `MnuProblemsClick` → `ShowSidePage(SeedsWin / ProblemsWin)`：`if SideBar.Collapsed or (SideBar.ActiveWindow <> AWin) then begin SideBar.Collapsed := False; SideBar.ActivateWindow(AWin); end else SideBar.Collapsed := True;`（1 期的「问题」菜单只是切折叠）。
- [ ] **Step 7: resourcestring**：`rsTbExported`。
- [ ] **Step 8: 1 期测试跟着改**（`tests/test.themebuilder.main.pas`）：F1 改为 `WindowCount = 2`、`Windows[0] = SeedsWin`、`Windows[1] = ProblemsWin`；F11 的 `cUnits` 加本期十一个单元（数组上界跟着改）；I1 的 `.lfm` 清单改为 `FindAllFiles(ToolDir, '*.lfm', False)` 逐个 `LfmKeys`（本期新增的四个 `.lfm` 自动纳入）。
- [ ] **Step 9: 判据测试**（接着写 `TTbMainFormTests`；`SetUp` / `TearDown` 照 1 期；实现期修正（开工核对）：编号顺延为 F29–F39，见「开工前要定的问题」前的核对第 1 条）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| F29 | 建好：`Seeds.Parent = SeedsHost`；`SideBar.ActiveWindow = SeedsWin`；启动的极简模板下 `Seeds.Columns = light, dark`、`Seeds.Broken = False` | `FormCreate` 不建 frame / 建了不放进 `SeedsHost` |
| F30 | 一步撤销：极简模板上**先打一个字**（光标移到第 1 行末，`Editor.CommandProcessor(ecChar, 'x', nil)`），再 `Seeds.ApplyValue(accent, 0, '#123456')` → 编辑器文本里亮色块 `--accent: #123456;`、暗色不变；预览按钮 `primary` 的背景 = `$123456`（比法同 1 期 `PreviewButtonBg`）；`Editor.Undo` **一次** → 文本 = 极简模板加那个 `x`（`x` 还在） | `ApplyEdits` 改用 `Editor.Lines.Text := TbApplyEdits(…)`（撤销一次回不到「只差 x」的样子） |
| F31 | 陈旧保护：`Seeds.UpdateFrom` 扫的是 T；编辑器文本另设为 U（不刷新）→ `ApplyEdits(T, 一个改动)` = False、文本仍是 U；**而** `Seeds.ApplyValue(…)` 能成功（`OnSync` 先刷新）、改动落在 U 上 | ① 去掉 `Editor.Lines.Text <> AText` 检查（改动落错位置）；② `FSeeds.OnSync` 不挂（`ApplyValue` 返回 False） |
| F32 | 面板跟着文本：编辑器设为亮色 `--accent: #ABCDEF` 的文档、`RefreshNow` → `Seeds.ResolvedText(accent,0) = '#ABCDEF'`（先证明刷新前不是） | `RefreshNow` 不调 `UpdateFrom` |
| F33 | Ctrl+点击跳转：编辑器文本 = R1 的 T；对 `Preview.BtnPrimary` 发 Ctrl 按下（同 P1）→ `Editor.LogicalCaretXY = (1,2)`；再一次 → (9,4)；再一次 → (1,2) | ① `FPreview.OnPick` 不挂（光标不动）；② 不循环（第二次仍 (1,2)） |
| F34 | Ctrl+点击插入：极简模板，对 `Preview.TagDanger` 发 Ctrl 按下 → 文本（每行去行尾空白、换行统一成 LF）以 `'TyTag.danger {'#10#10'}'#10` 结尾；光标在倒数第二行、`X = 3`；`Editor.Undo` 一次 → 回到极简模板 | 插入不走 `ApplyEdits`（撤销一次回不去）。**若 X = 1 而原因是 SynEdit 修掉了中间行的两个空格（核实记录 37）**：在 `FormCreate` 里 `Editor.Options := Editor.Options - [eoTrimTrailingSpaces]`（注释写明：修尾空格会让「只改那一处」之外的字节变，和保存不改字节的承诺冲突），签收写一句 |
| F35 | 覆盖检查接线：文本 `'TyRibbon { }'` → `BuildCoverageForm.LstNotShown.Items` 含 `TyRibbon` | `BuildCoverageForm` 用的是空的文档键 |
| F36 | 导出接线：把 green 主题与图片复制进临时目录并 `OpenFile`；`f := BuildExportForm` → `f.Files` 有 `assets/background.jpg`；`f.EdtTarget.Text := 临时目标; f.DoExport` → True，目标里的 `theme.tycss` 字节 = `EntryBytes` = 打开的文件的字节 | `EntryBytes` 用 `Editor.Lines.Text`（CRLF / LF 与文件不同时红——用一个 LF 文件、在 Windows 上跑） |
| F37 | 片段接线：打开 `green.tycss` 的副本 → `BuildSnippetsForm.MemoFile` 含 `'green.tycss'`、`MemoFolder` 含 `'green'` | `SnippetName` 不看文件名（得到 `mytheme`） |
| F38 | 侧栏菜单：`MnuSeedsClick` 两次 → 第一次（已在种子页）折叠，第二次展开且仍是种子页；`MnuProblemsClick` → 展开并切到问题页 | — |
| F39 | 窗体销毁后预览的挂钩不回调主窗体：建窗体、`Free`；之后无 AV（`TearDown` 之前显式建一个再释放） | `FormDestroy` 不清 `OnPick`（若确实不 AV，「等价」，签收写明） |

- [ ] **Step 10: 提交**：`feat(themebuilder): the seeds page, Ctrl+click to a rule, the coverage check, export and snippets in the main window` + Co-Authored-By。

---

### Task 10: 中英 `.po`

**Files:**
- Modify: `tools/themebuilder/languages/themebuilder.zh_CN.po`、`themebuilder.zh_CN.json`

- [ ] **Step 1: `.lfm` 条目**：照 1 期 Task 11 Step 2 的写法，在 `.po` 前半段加本期四个新 `.lfm`（根类名 `ttbseedsframe`、`ttbcoverageform`、`ttbexportform`、`ttbsnippetsform`）与 `tbmain.lfm` 新增组件（`ttbmainform.seedswin.caption` / `.striphint`、`mnuexport`、`mnusnippets`、`mnuseeds`、`mnucoverage`）的每个 `Caption`、`Hint`、`TextHint`、`StripHint`、`Text`。**译文**：Seeds 种子、Split into light and dark 拆成明暗两套、Seed 种子、Light 亮色、Dark 暗色、Coverage check 覆盖检查、Styled in this theme but not in the preview: 主题写了、预览里没有的：、In the preview, but neither this theme nor the base styles them (they keep their built-in look): 预览里有、主题和底层都没写的（它们保持内置的样子）：、Double-click an entry to go to its rule, or add one. 双击一项跳到它的规则，没有就添加一条。、Export a theme bundle 导出主题包、A folder 文件夹、A zip file zip 文件、Browse... 浏览…、Files that go in with theme.tycss and theme.json: 随 theme.tycss 和 theme.json 一起打包的文件：、Export 导出、Use it in a program 在程序里怎么用、From a file 从文件、From a theme bundle 从主题包、Registered by name 注册成命名主题、Copy 复制、Close 关闭……（照原生语感，仓库记忆「文档要原生语感」）。`--accent` 等六个种子名的 `Caption` 条目 `msgstr` 与 `msgid` 相同（不译，但不能空）。
- [ ] **Step 2: 代码条目的译文**（`.json`，键 `<小写单元名>.<小写 rs 名>`）：Task 3、6、7、8、9 的全部 resourcestring，例：`tbseedsframe.rstbseedsbroken`: `"先修好问题列表里的错误。"`、`tbseedsframe.rstbseedssinglemode`: `"单模式：明暗共用这一组种子。"`、`tbseedsframe.rstbseedinherited`: `"继承"`、`tbseedsframe.rstbseedshared`: `"来自 :root"`、`tbseedsframe.rstbseedexpression`: `"表达式"`、`tbseedsframe.rstbseedsharedask`: `"%s 写在 :root 里，亮暗共用。选「是」改 :root（两种模式都变），选「否」只给%s加一行。"`、`tbseedsframe.rstbseedexprask`: `"%s 现在是表达式 %s，改成 %s 吗？"`、`tbexport.rstbexportziprefs`: `"zip 包带不了这个主题引用的文件（库读 zip 时既不解析 @import，也不读里面的图片）。请导出成文件夹。"`、`tbexport.rstbexportverifyfailed`: `"导出的包读回来加载不了"`、`tbmain.rstbexported`: `"已导出到 %s。"`、`tbsnippets.rstbsnippetwhere`: `"放在主窗体（TTyForm）里："`……占位符个数与顺序与英文一致。代码条目由 Task 11 编译后跑脚本并进 `.po`。
- [ ] **Step 3: 提交**：`i18n(themebuilder): Chinese for the seeds page, the coverage check, export and snippets` + Co-Authored-By。

---

### Task 11: 收尾——编译、全量、按 spec 逐条核、集中变异、主控编包冒烟、审查、写回 spec、签收

**Files:**
- Modify: 本计划（签收记录）、`docs/superpowers/specs/2026-10-01-theme-builder-design.md`（写回）、`tools/themebuilder/languages/themebuilder.zh_CN.po`（脚本补代码条目）
- 修复时按需改 Task 1–10 的文件

- [ ] **Step 1: 一次编译 + 本期 suite + 全量**：「跑测试的固定套路」。Expected：列出的 suite 全 0 / 0；全量 errors / failures 与 Task 0 的基线相同、总数 = 基线 + 本期新增。红了集中修，一个问题一个 `fix(themebuilder): ...` 提交；以 spec 与本计划的判据为准，不改判据迁就代码（判据本身错了的，改判据并在签收里写原因）。
- [ ] **Step 2: 编工具、补 `.po`**：编工具命令（0 错、没有重编 SynEdit）；然后

```bash
cd /d/Projects/ty-3.1 && python scripts/example-rsj2po.py tools/themebuilder themebuilder tools/themebuilder/languages/themebuilder.zh_CN.json && python scripts/check-example-po.py . && python scripts/check-lfm-props.py && git status --short tools/themebuilder
```

Expected：`added=` 等于本期新增的 resourcestring 个数、没有 `FATAL`；两个检查通过；`git status` 只有 `.po` 变了。重编 tytests 再跑 `TTbMainFormTests`（I1–I3 这时才看得到新条目）。
- [ ] **Step 3: 刷新耗时**：在 `TTbMainFormTests` 里临时加（或写进去留着）一条：打开 `themes/auto.tycss` 的副本，`RefreshNow` 五次取中位数，打印；与 1 期签收记的同一数字比较（1 期没记就只记本期的）。超过 1 期的 2 倍、或超过 150 ms，写进签收（不因此失败）。
- [ ] **Step 4: 按 spec 逐条核代码，不看测试**：§5.1 第 2、4 条（面板改值 → 替换 → 刷新；各算一步撤销）；§5.2 每一句；§5.3 的 Ctrl+点击与覆盖检查；§6 的导出与代码片段两条；§8 的种子扫描、规则定位、覆盖检查、导出四行；逐条记「在哪一行实现 / 为什么不需要 / 与规格不符（写回）」。重点查接线（仓库记忆「建好没接线」）：frame 的三个事件、预览的 `OnPick`、`RefreshNow` 里的 `UpdateFrom`、四个菜单项的 `OnClick`、`BuildSampleWindow` 里的 `HookTree`、导出对话框的 `OnAsk`。
- [ ] **Step 5: 【主控执行】编包、冒烟、看一眼**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tools/themebuilder/themebuilder.lpi > /tmp/tb2-tool.txt 2>&1; tail -3 /tmp/tb2-tool.txt; git status --short
```

Expected：编过；`source/`、`designtime/` 下没有任何改动。然后：
1. `powershell -File scripts/smoke-launch-examples.ps1 -Dirs tools\themebuilder`：起得来、只有主窗体与应用窗口、没有 `#32770`。
2. 打开工具看一眼（不录）：种子页（极简模板两列）→ 改一个颜色 → Ctrl+Z → 打开 `themes/builtin/win11.tycss` 改 `--radius` 看询问 → Ctrl+点击预览的主按钮 → 覆盖检查 → 导出 `themes/green.tycss` 到一个临时文件夹 → 片段小窗。
3. 截两张图放 `docs/superpowers/plans/2026-10-01-themebuilder-acceptance-shots/`：`p2-seeds-win32.png`（种子页，win11 主题）、`p2-export-win32.png`（导出对话框）——Task 12 引用。
- [ ] **Step 6: 集中变异**（每条三拍，必须红）：C1、C2、C4、C7、C9、C10、C12、C14、E1、E3–E7、E9–E13、SF1、SF3–SF11、R1、R2、R5、P1–P9、CV2–CV5、CV7、X2、X3、X5–X11、S1–S3、S5、S7、F29–F39（实现期修正（开工核对）：原 F19–F29）。结果逐条记进签收（红 / 补强 / 等价 + 理由）；没红的先查改没改对地方、再查是不是「这条路走不到」，确实没红就当场补测试。
- [ ] **Step 7: 期末审查（主控派两个审查 agent）**：规格核对（Step 4 的记录对着 spec 再过一遍）+ 代码质量（`git diff <Task 0 的 HEAD>..HEAD`），重点：
  - 文本改动：只替换值区间、只插入整行 / 整块；偏移全部基于同一份文本、从后往前应用；陈旧保护；一步撤销（地雷 20、21）。
  - 种子面板：刷新不回写（地雷 22）；表达式与共用两种询问的时机；坏文本整页禁用。
  - Ctrl+点击：拦下的不交给控件、没拦的原样转交；挂钩能摘干净；`Tools` 不挂（地雷 23、24）。
  - 导出：任何失败都不留痕、原有 zip 不变；zip 的限制说得清（地雷 25）。
  - 片段：守卫真的比对了；`tests/` 目录没被写（地雷 26、27）。
  - 审出来的问题修完回到 Step 1。
- [ ] **Step 8: 写回 spec 原处，标「实现期修正（2 期）」**，原文删除线保留。至少：状态行（2 期签收）；§4 的单元名（`tbcssscan` / `tbseeds` / `tbseedsframe` / `tbrules` / `tbpick` / `tbcoverage` / `tbcoverageform` / `tbexport` / `tbexportform` / `tbsnippets` / `tbsnippetsform`）；§5.2 求值不经预览控制器（核实记录 12）、共用 `:root` 的询问、拆成两套只插入、表达式确认的时机；§5.3 Ctrl+点击的范围与同名多条的规则、覆盖检查的放法与「预览里摆了」的来源；§6 主题包的两种格式与 zip 的限制、导出的路径规则与目标规则、片段的三页四段；开工前问题一的答复；「与规格不符之处」每一条。
- [ ] **Step 9: 签收记录写进本计划末尾，提交**：全量条数（基线 → 签收）、提交区间、本期各 suite 条数与用时、刷新耗时、变异结果、spec 写回的节号、计划外发现（至少：`ThemeLint` 对导入文件的 `url()` 用它自己的目录查缺图，与运行时不一致，核实记录 28）、遗留。

```bash
cd /d/Projects/ty-3.1 && git add docs/ tools/themebuilder/languages && git commit -m "docs(themebuilder): phase 2 sign-off; corrections written back into the spec

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: 把 2 期的真机项追加进验收文档

**Files:**
- Modify: `docs/superpowers/plans/2026-10-01-themebuilder-acceptance.md`

照文档现有的形式与语气（仓库记忆「文档要原生语感」）：

- [ ] **Step 1: 「这是什么，做了什么」**：「2 期」那一行的「（待做）」换成一段：种子面板（明暗两列、改了就写回文本那一个值、表达式和共用 `:root` 的会先问、没写的灰着显示继承值、单模式可以一键拆成两套）；预览里 Ctrl+点击（macOS 上 Cmd+点击）跳到或添加规则；覆盖检查；导出主题包（文件夹或 zip，导出后用库读回、加载不了就不留下）；「在程序里怎么用」的代码片段。写明库本期一处没改。2 期签收的头提交与全量条数。
- [ ] **Step 2: 「验收表」**：本计划末尾「2 期的真机验收项」B1–B18 接着 1 期往下编成 23–40，「期（原编号）」列写「2 期（B1）」……
- [ ] **Step 3: 「按平台的项号」**：各平台一行里补上 23–40 中对应的项。
- [ ] **Step 4: 「等你定的决定」**：加一小节「2 期开工前的问题」，E9 起（E9–E19，对应开工前问题一的 11 条）：是什么、选项、现在的做法（按 Task 0 的实际答复）、看哪一项、改哪里。「与规格不符、你可能想改的」补上本计划「与规格不符之处」里用户看得见的几条。
- [ ] **Step 5: 「截图」**：「1 期不截图；2 期起按需加」改为列出 Task 11 Step 5 的两张图及它们对应的项号。
- [ ] **Step 6: 自查与提交**：项号连续（1–40）；每一项都有「怎么操作」与「期望」；决定清单每条都有「看哪一项」。

```bash
cd /d/Projects/ty-3.1 && git add docs/superpowers/plans/2026-10-01-themebuilder-acceptance.md docs/superpowers/plans/2026-10-01-themebuilder-acceptance-shots && git commit -m "docs(themebuilder): phase 2's checks and decisions on the acceptance sheet

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 2 期做完能看到什么

- `tytests` 里本期八个 suite 全绿，1 期的 suite 照旧全绿：扫描在所有仓库主题上与解析器对得上；种子只改那一个值、缺的插入整行、块不存在就建块、拆成两套；面板按列求值、不受预览密度影响、刷新不回写；Ctrl+点击拿到对的 typeKey 与变体、控件本身什么都没收到；覆盖检查的子部件表与源码对得上；导出的包能被库读回加载、失败不留痕；四段代码片段真的编进了测试工程。
- 工具里：侧栏第一页是种子；改色块文本跟着变、Ctrl+Z 一次回去；按住 Ctrl 点预览控件，编辑器跳到它的规则。
- 库一个字节没动。

---

## 2 期的真机验收项（Task 12 写进验收文档，编号 23–40）

| # | 项 | 平台 | 怎么验 | 算过 |
|---|---|---|---|---|
| B1 | 种子面板的样子 | Win32、GTK2、Cocoa | 依次打开 `themes/auto.tycss`、`themes/builtin/win11.tycss`、`breeze.tycss`、`classic.tycss`、`aero.tycss`、`themes/light.tycss` | 双模式两列、单模式一列加「拆成明暗两套」；win11 的圆角两列写「来自 :root」；classic 亮色的 `--surface` 灰着写「继承」；aero 暗色的 `--surface` 写「表达式」；色块颜色与预览一致；中英文下都不挤、不被裁 |
| B2 | 改一个种子 | Win32、GTK2 | 在 `auto.tycss`（副本）里改亮色 `--surface`、暗色 `--accent` | 文本里只有那个值变了（同一行的另外两个、暗色块的对齐空格、注释都不动）；预览跟着变；Ctrl+Z 一次回到原样 |
| B3 | 表达式先问 | 任一 | `aero.tycss`（副本）暗色 `--surface` 选一个新颜色，先选「否」再选「是」 | 「否」色块退回、文本不动；「是」表达式被换成色值 |
| B4 | 共用 `:root` | 任一 | `win11.tycss`（副本）亮色列改圆角，分别答 是 / 否 / 取消 | 是：`:root` 里的 `--radius` 变、两列都变；否：亮色块多一行、暗色列不变；取消：什么都不变 |
| B5 | 缺种子插入 | 任一 | `classic.tycss`（副本）亮色 `--surface` 选色 | 亮色块里多一行 `--surface: #……;`，缩进与上一行对齐；「继承」字样消失 |
| B6 | 拆成明暗两套 | 任一 | 打开 `themes/light.tycss` 的副本，点「拆成明暗两套」，再切预览的「暗色」 | 文本多出 `@mode light` / `@mode dark` 两块，六个种子齐全、两块的值相同；`:root` 原样；面板变两列；预览的暗色开关能用、切过去样子不变；Ctrl+Z 一次撤回 |
| B7 | 圆角 | 任一 | 用微调框的箭头与键盘改圆角 | 文本跟着变成 `Npx`；预览按钮圆角跟着变 |
| B8 | 文本 → 面板 | 任一 | 在编辑器里直接改 `--accent` 的值 | 停手约 0.3 秒后面板色块变；写坏一个 `}` 时面板整页变灰、顶上提示先修错误 |
| B9 | Ctrl+点击跳转 | Win32、GTK2、Qt6 | 在预览八页里各按住 Ctrl 点几个控件（含主按钮、标签页、列表视图、组合框的下拉按钮处、表格） | 编辑器跳到对应规则的选择器；被点的控件没有被按下、复选框没有变、页签没有切换、没有获得焦点 |
| B10 | 同名多条与插入 | 任一 | 文档里写两条 `TyButton.primary`，连续 Ctrl+点主按钮三次；再 Ctrl+点一个文档里没写的控件 | 依次跳第一、第二、第一条；没写的在文末插入空规则、光标停在花括号里；Ctrl+Z 一次撤回 |
| B11 | 样例窗口与 macOS | Win32、Cocoa | 打开样例窗口，Ctrl+点（Mac 上 Cmd+点）里面的按钮 | 主窗口回到前面、编辑器跳到规则；Mac 上 Ctrl+点仍是右键习惯、不跳 |
| B12 | 全部禁用时 | Win32、GTK2 | 勾「全部禁用」后 Ctrl+点标签和按钮 | 标签能跳；Win32 上禁用的按钮点了没反应（已知，核实记录 20），记下各平台的表现 |
| B13 | 覆盖检查 | 任一 | 极简模板打开覆盖检查；加一条 `TyRibbon { }` 和一条拼错的 `TyButon { }` 再打开；双击各一项 | 第一张单子列出 `TyRibbon` 与 `TyButon`（后者标「不是已知的 typeKey」）；第二张单子列出 `TyFormSurface` 等底层刻意不定义的键；双击跳到或添加规则 |
| B14 | 导出文件夹包 | Win32、GTK2 | 打开 `themes/green.tycss`（副本，带 `assets/`），导出成文件夹；用工具「打开」导出的 `theme.tycss`；再把片段小窗「从主题包」的第一段粘进任一示例的 `FormCreate`、把包放到示例 exe 旁边跑一次 | 包里有 `theme.tycss`、`theme.json`、`assets/background.jpg`；工具里预览与原主题一样（有照片背景）；示例程序换上了这套主题 |
| B15 | 导出 zip 与拒绝 | 任一 | 极简模板导出 zip；green 主题看 zip 选项；导出到一个非空文件夹；导出一份暗色下缺变量的文档 | 极简的 zip 能导出；green 的 zip 选项灰掉并说明原因；非空文件夹被拒、里面的东西不动；缺变量的导出失败、目标位置什么都没留下 |
| B16 | 代码片段 | Win32 | 打开片段小窗看三页，点「复制」粘到别处；把「注册成命名主题」那段（含函数）粘进一个示例编译运行 | 名字、文件名跟着当前文档；复制的内容完整；示例编过、换上了主题 |
| B17 | 中英 | Win32、GTK2 | 中英文系统各看一遍种子页、三个对话框、新菜单项 | 跟随系统语言；中文下没有英文漏网（`--accent` 等种子名本来就不译） |
| B18 | HiDPI | Win32 150%、Cocoa Retina | 看种子页与三个对话框 | 不糊、不挤、色块与文字不被裁 |

---

## 与规格不符之处（核实中发现，Task 11 写回）

1. spec §4 的 `useeds.pas` / `urules.pas` / `uexport.pas` 改为 `tb` 前缀并拆开：`tbcssscan`、`tbseeds`、`tbseedsframe`、`tbrules`、`tbpick`、`tbcoverage`、`tbcoverageform`、`tbexport`、`tbexportform`、`tbsnippets`、`tbsnippetsform`。
2. spec §5.2「色块显示经预览控制器求值的颜色」：改为经一个与预览同样加载、但不带密度包的独立模型按列求值（核实记录 12）。
3. spec §5.2「改之前确认一次」：确认在选好颜色之后、写进文本之前（开工前问题一第 6 条）。另加：种子写在共用 `:root` 时问改哪里（第 4 条）；「拆成明暗两套」只插入、不删 `:root` 里原有的种子（第 5 条）；文档解析不了时整页禁用。
4. spec §5.3 Ctrl+点击：范围是预览八页与样例窗口，对话框、菜单、通知不支持，Mac 上 Cmd+点击也算；只认类型与变体完全一致、不带状态的规则，同名多条循环跳（第 7、8 条）。
5. spec §5.3 覆盖检查：放在「视图 → 覆盖检查…」对话框里（第 9 条）；「预览里摆了」= 控件自己的 typeKey + 工具里的子部件表（同单元别的控件的键也算）；「文档写了」只看入口文档，`@import` 进来的不算。
6. spec §6 导出主题包：库的 zip 读取端解析不了 `@import`、画不出 zip 里的图片（核实记录 27），所以出两种格式：文件夹包完整可用；zip 只在文档不引用其它文件时可选（第 1 条）。引用了文档目录以外的文件拒绝导出（第 2 条）；文件夹目标必须不存在或为空（第 3 条）。
7. spec §6 代码片段：「从主题包加载」一页有文件夹、zip 两段；都用注册 + `ThemeName` 的写法，不用 `Model.LoadFromSource`（第 10 条）。
8. spec §2 第 5 条的侧栏：本期两页（种子、问题），默认显示种子（第 11 条）；AI 页 3 期加。

---

## 签收

签收日期 2026-10-01。起点 `f87c46c6`（1 期签收、主控冒烟之后）；本期提交 `6e4d1254`..`eab654f5`（中间的 `ba0df847` 是 3 期计划 agent 的提交，不属本期）。实现 agent 做了 Task 0–10、Task 11 能做的部分（一次编译含工具工程、本期 suite、全量、集中修红、`.po` 脚本、按 spec 逐条核代码、集中变异、写回 spec）与 Task 12；标【主控执行】的（编两个 `.lpk`、截图、GUI 冒烟、派期末审查）没做，见「主控要做的」。库（`source/`、`designtime/`）一个字节没改。

### 提交表

| 任务 | 提交 | 内容 |
|---|---|---|
| Task 0 | —（`9e71f6f1` 记开工核对） | 基线编译与全量；对照 1 期期末修复核对计划，调整写在「开工前要定的问题」之前 |
| Task 1 | `6e4d1254` | `tbcssscan`：容错扫描、偏移与行列、文本改动 |
| Task 2 | `7393721e` | `tbseeds`：种子的定位、改写、拆成两套 |
| Task 3 | `51bb6070` | `TTbSeedEval`、种子页 frame |
| Task 4 | `073cee64` | `tbrules` |
| Task 5 | `2c040679` | `tbpick`，预览挂钩 |
| Task 6 | `607e6682` | 覆盖检查（算法、子部件表、对话框） |
| Task 7 | `e72ec61f` | 导出主题包与对话框 |
| Task 8 | `8ba0753c` | 代码片段与小窗，片段编进测试工程 |
| Task 9 | `e51f9519` | 主窗体接线，1 期 F1 / F11 / I1 跟着改，F29–F39 |
| Task 10 | `d798aa0d` | 中文 `.lfm` 条目与代码条目译文 |
| Task 11 修红 | `6cf9daa8` | FPC 注释里引号中的 `}` 提前结束注释（`tbcssscan`、`tbseeds`） |
| | `17da53b8` | 局部变量与继承属性同名（`Show`、`Color`、`Note`、`Font`、`Text`、`Doc`）；`TbCoverage` 与单元同名、改名 `TbCoverageLists`；测试单元缺 `Forms`（`TModalResult`） |
| | `80d5e7e0` | 只有扩展名的文件名（`.tycss`）得到默认主题名（S6） |
| | `50b71ad7` | 测试：交给控件的按下会抓鼠标、要窗口句柄——P2、P3、P7 把 frame 放到一个不显示的窗体上 |
| | `1a29b1e3` | `example-rsj2po.py` 补进 26 条代码条目 |
| | `4f900970` | 测试：S3 加「片段正文调用的名字，其单元在片段的 uses 行里」 |
| | `f453159d` | 测试：刷新耗时（打印，> 1.5 s 才红） |
| 变异补强 | `d3f5809d` | C14 换成改变长度的改动；P3 加 `OnMouseUp` 计数 |
| | `eab654f5` | CV2 夹具加一个文档写了、底层没有的键 |
| Task 11 / 12 | 本提交、下一提交 | 签收、spec 写回；验收文档 |

### 测试结果

- 基线（`f87c46c6`，`tests/tytests-tb2base.exe`）全量：8679 / 0 errors / 3 failures（12 分 29 秒）。三条里两条是我在跑基线时写进工作区的新文件造成的（F11「磁盘上的单元都在工程里」看到了还没登记的 `tbexport.pas`；I3 看到了还没译的 `rsTbCovUnknownKey`）；第三条 `TTyStringGridTest.TestBulkFillStaysLinear`（「第 1 批 110 ms，第 9 批 406 ms」）是计时类，单跑两次都绿，另一棵树同时在跑全量。
- 首次编译后：本期八个 suite 与 1 期、相关库 suite 全绿（列表见「跑测试的固定套路」）；TTbCssScanTests 14、TTbRulesTests 7、TTbSeedEditTests 13、TTbSeedsFrameTests 11、TTbPickTests 9、TTbCoverageTests 7、TTbExportTests 11、TTbSnippetsTests 7、TTbMainFormTests 44（1 期 33 + 本期 11）。
- 修红后全量（`1a29b1e3` 之后的构建）：8769 / 0 / 0（12 分 17 秒），= 基线 8679 + 本期 90。
- 签收（`eab654f5` 重编，`tests/tytests-tb2.exe`）全量：**8770 / 0 errors / 0 failures**（12 分 03 秒）= 基线 8679 + 本期 91（90 条判据 + 刷新耗时那一条）；跑时另一棵树（`ty-advchart`）的全量同时在跑，没有计时类红。
- 本期 suite 用时（全量里）：TTbMainFormTests 54.5 s（44 条，每条真建主窗体），TTbSeedsFrameTests 4.1 s，TTbPickTests 3.3 s，TTbExportTests 2.5 s，TTbCoverageTests 1.1 s，其余 < 0.2 s。
- 刷新耗时（Step 3）：打开 `themes/auto.tycss` 的副本、丢掉解析缓存后 `RefreshNow` 五次的中位数 **328 ms**（五次 297–359 ms，全量里、另一棵树同时在跑）——超过计划定的 150 ms 提示线，记在这里、不因此失败；没有拆开量各段（lint、预览加载与试解析、种子页的扫描与独立模型加载）各占多少，留给真机第 27、37 项看打字后是否有可感觉的停顿（含 lint、预览加载与试解析、种子页的扫描与独立模型加载）。1 期签收没记同一数字，只记了试解析 15–31 ms。
- 工具：`lazbuild -B tools/themebuilder/themebuilder.lpi` 0 错，没有重编 SynEdit；`example-rsj2po.py` added=26（本期 26 条 resourcestring），无 FATAL；`check-example-po.py` 103 个文件 0 问题；`check-lfm-props.py` OK。

### 按 spec 逐条核（不看测试）

| spec | 实现 | 结论 |
|---|---|---|
| §5.1 第 2 条：种子改值 → 替换 → 刷新 | `TTbSeedsFrame.ApplyValue` → `OnEdits` → `TTbMainForm.SeedsEdits` → `ApplyEdits`（末尾 `RefreshNow`） | 实现；只替换值区间，不是「那一行」（§5.2 的说法为准） |
| §5.1 第 4 条：各算一步撤销 | `ApplyEdits` 的 `BeginUndoBlock` / `EndUndoBlock`；Ctrl+点击插入也走它 | 实现（F30、F34） |
| §5.2 六个种子 | `TbSeedNames` | 实现 |
| §5.2 两列 / 一列 + 拆成两套（暗色先用亮色值） | `TbSeedColumns`、`TTbSeedsFrame.UpdateView`、`SplitModes` + `TbSplitModesEdits` | 实现；只插入、`:root` 不动（写回） |
| §5.2 色块显示求值后的颜色（经预览控制器） | `TTbSeedEval`（独立模型、不带密度包） | 与规格不符，写回 §5.2 |
| §5.2 表达式标注、改前确认、改后写色值 | `UpdateView` 的说明标签；`ApplyValue` 的 `rsTbSeedExprAsk` | 实现；确认在选好颜色之后（写回）；另加共用 `:root` 的询问（写回） |
| §5.2 没写的灰着显示继承值，一改补一行 | `tssInherited` 说明标签 `Enabled := False`、色块显示底层值；`TbSeedSetEdits` 的 `InsertIntoBlock` / `NewModeBlock` / `NewRootBlock` | 实现；「灰」的是说明文字，色块保持可点（要能改） |
| §5.2 只替换值，容错扫描认得注释、字符串、嵌套块 | `tbcssscan`（库的词法器）、`TbSeedSetEdits` | 实现；未知 at 规则整块跳过 |
| §5.3 Ctrl+点击：typeKey 与变体、跳规则、没有就文末插入空规则、光标在花括号里 | `tbpick`、`TTbPreviewFrame.PickerPick` → `TTbMainForm.JumpToRule`、`tbrules` | 实现；范围、同名多条、状态规则不算等写回 §5.3 |
| §5.3 覆盖检查两张单子 | `tbcoverage`、`TTbPreviewFrame.CollectTypeKeys`、`TTbCoverageForm`、`MnuCoverageClick` | 实现；放在对话框、「预览摆了」的来源、只看入口文档写回 §5.3 |
| §6 导出：tycss + 引用文件 + 清单，读回加载，失败不留坏包 | `tbexport`、`TTbExportForm` | 实现；两种格式、zip 限制、路径与目标规则写回 §6 |
| §6 代码片段：三种写法、可复制 | `tbsnippets`、`TTbSnippetsForm` | 实现；三页四段写回 §6 |
| §8 种子扫描 / 规则定位 / 覆盖检查 / 导出 | E1–E13、SF1–SF11；R1–R7、F33、F34；CV1–CV7；X1–X11、F36 | 实现；导出读回文件夹用目录源（写回 §8） |
| 接线：frame 三个事件、`OnPick`、`RefreshNow` 里的 `UpdateFrom`、四个菜单项、`BuildSampleWindow` 里的 `HookTree`、导出对话框的 `OnAsk` | `TTbMainForm.FormCreate`、`.lfm` 的 `OnClick`、`TTbPreviewFrame.BuildSampleWindow`、`BuildExportForm` | 全部接上；`FormDestroy` 先摘 frame 的事件和 `OnPick` |

### 集中变异（每条改字符串 → `lazbuild` → 跑指定测试 → 写回原字节）

增量构建每条约 10 s。变异文件都是 LF，替换前断言命中恰好一处。全部还原后 `git diff --quiet -- source tools tests designtime` 为真，再 `lazbuild -B` 跑全量（上面「签收」那一行）。

| # | 变异 | 结果 |
|---|---|---|
| C1 | 偏移不减 1 | 红 |
| C2 | `ReadMode` 不写 `OuterClose` | 红 |
| C4 | 值的结尾不跳尾随注释 | 红 |
| C7 | 逗号后不读下一个选择器 | 红 |
| C9 | `ReadDecls` 遇 EOF 不停 | 红（超时，180 s 杀掉——按 PID） |
| C10 | 未知 at 规则不整块跳过 | 红 |
| C12 | 单独的 CR 不断行 | 红 |
| C14 | `TbApplyEdits` 从前往后 | **先存活**：夹具的第一个改动长度不变（2 字节换 2 字节），前后顺序结果一样；改用改变长度的改动（`d3f5809d`）后红 |
| E1 | 改写整段「名字: 值」 | 红（对齐空格丢失） |
| E3 | `FindLast` 取第一条 | 红 |
| E4 | 插入不看缩进 | 红 |
| E5 | 一行的块也按多行插 | 红 |
| E6a | 双模式下 `:root` 里的算 `tssOwn` | 红（E6、E13 win11） |
| E6b | 忽略 `AShared` | 红 |
| E7 | 亮色块也建在后面 | 红 |
| E9 | 插入固定用 `#10` | 红 |
| E10 | 不查 `CloseBrace = 0` | 红 |
| E11 | 颜色只认 6、8 位 | 红 |
| E12 | 两个模式块插在 `:root` 之前 | 红 |
| SF1 | 右列用左列的值 | 红 |
| SF3 | 求值不按列 `SetMode` | 红 |
| SF4a / b | 不问表达式 / 字面值也问 | 红 / 红 |
| SF5 | 共用格子不问 | 红 |
| SF6 | 不看 `FEval.Load` 的结果 | 红 |
| SF7 | 独立模型也加密度包（等价于「改用预览控制器的模型」：多出来的正是密度包） | 红 |
| SF8 | `UpdateView` 不设 `FUpdating` | 红（刷新写回 14 次） |
| SF9 | 暗色块写成另一组值 | 红 |
| SF10 | 圆角取错列 | 红 |
| SF11 | `ApplyValue` 不调 `OnSync` | 红 |
| R1 / R2 / R5 | 不看状态 / 区分大小写 / 插在文末换行之后 | 红 / 红 / 红 |
| P1 | 拦下后仍交给控件 | 红（控件处理按下时抓鼠标要句柄，抛） |
| P2 | 不按 Ctrl 也当拾取 | 红 |
| P3 | 抬起只在带 Ctrl 时吞 | **先存活**：没被按下的按钮收到抬起什么也不做，`OnClick` 与 `FPressed` 看不出；加 `OnMouseUp` 计数（`d3f5809d`）后红 |
| P4 | 去掉 `capfAllowDisabled` | 红（得到 `TyTabSheet`） |
| P5 | 不往上找 | 红 |
| P6 | `BuildSampleWindow` 不 `HookTree` | 红（按下到了按钮，按钮抓鼠标要句柄、抛 1407——没被拦下） |
| P7 | 挂整个 frame | 红 |
| P8a / b | `UnhookAll` 不还原 / 不 `FreeNotification` | 红 / 红 |
| P9 | 析构不先 `UnhookAll` | **等价**：picker 是 frame 拥有的组件，随后在继承的析构里释放时自己 `UnhookAll`；先释放的控件靠 `FreeNotification` 从挂钩里摘掉，不会 AV |
| CV1 | 只收每条规则的第一个选择器 | 红（`TyUpDown`） |
| CV2 | 第二张单子不减文档 | **先存活**：夹具里文档写了的键底层都有，减不减一样；夹具加 `TyCard`（`eab654f5`）后红 |
| CV3a / b | 只取控件自己的 typeKey / 不走祖先类 | 红 / 红 |
| CV4 | 从 `TabStrip` 行删掉 `TyTab` | 红 |
| CV5 | 第二张单子不减底层 | 红 |
| CV7 | 双击存的是显示文本 | 红 |
| X2a / b | 嵌套 `@import` 相对入口 / `url()` 相对导入它的文件 | 红 / 红 |
| X3 | 不查 `..` | 红 |
| X5 | zip 漏写 `theme.json` | 红 |
| X6 | 去掉「zip 不带文件」的检查 | 红 |
| X7a / b | 读回只试第一个模式 / 失败不删临时目录 | 红 / 红 |
| X8 | 不查非空目录 | 红 |
| X9 | 成功后不删 `.tbbak` | 红 |
| X10 | 手拼 JSON 不转义 | 红 |
| X11 | `Prepare` 不按引用禁用 zip | 红 |
| S1 / S2 / S3 / S5 / S7 | 片段名字改错 / 末行不按文末换行 / zip 的 uses 少 `ThemeBundle` / 按 200 字节硬切 / 漏填一个 Memo | 全红（S3 靠 `4f900970` 补的那一半：计划原来的 S3 只查「片段的 uses ⊆ 测试单元的 uses」，少写一个单元查不出来） |
| F29 | frame 不放进 `SeedsHost` | 红 |
| F30 | `ApplyEdits` 改用 `Lines.Text :=` | 红 |
| F31a / b | 去掉陈旧保护 / `OnSync` 不挂 | 红 / 红 |
| F32 | `RefreshNow` 不调 `UpdateFrom` | 红 |
| F33a / b | `OnPick` 不挂 / 不循环 | 红 / 红 |
| F34 | 插入不走 `ApplyEdits` | 红 |
| F35 | `BuildCoverageForm` 用空的文档键 | 红 |
| F36 | `EntryBytes` 用 `Lines.Text` | 红 |
| F37 | `SnippetName` 不看文件名 | 红 |
| F39 | `FormDestroy` 不清 `OnPick` | **等价**：预览 frame 的析构第一件事自己清 `FOnPick` 并摘钩，窗体释放之后不会再有拾取 |

计划列的变异里不做的：C3、C5、C6、C8、C11、C13、E2、E8、SF2、R3、R4、R6、R7、CV6、X1、X4、S4、S6、F38（计划标「—」）。

### 与规格不符之处（已写回 spec，标「实现期修正（2 期）」）

状态行；§2 第 5 条（侧栏两页、默认种子）；§4（十一个单元）；§5.2（求值不经预览控制器、询问的时机与共用 `:root`、拆分只插入、坏文本整页禁用、生效顺序）；§5.3（Ctrl+点击的范围与规则、覆盖检查的放法与来源）；§6（两种格式与 zip 的限制、路径与目标规则、读回标准；片段三页四段）；§8（导出读回文件夹用目录源）。即本计划「与规格不符之处」1–8 条全部写回。开工前问题一的十一条未单独询问，按建议执行，列进验收文档 E11–E21。

### 计划外发现

- `ThemeLint.pas:917` 对导入文件里的 `url()` 用导入文件自己的目录查缺图，运行时是一律相对入口文件目录（核实记录 28）——两边不一致，库里的小问题，本期没改。
- FPC 的 `{ }` 注释里写 `'}'` 会把注释提前结束（注释不认引号），编译报的是后面某处「String exceeds line」；本期四处，已改成文字。
- 过程名与单元名只差大小写（`TbCoverage` / `tbcoverage`）时，在用了这个单元的地方 `TbCoverage(` 被当成单元限定，报「"." expected」。
- `ChangeFileExt('.tycss', '')` 原样返回（以点开头的名字不算有扩展名）。
- 交给控件的鼠标按下会让它抓鼠标，无头、没有父窗口时抛「has no parent window」——测试里要么只发会被拦下的按下，要么把 frame 放到窗体上并初始化 widgetset。
- 1 期期末的主窗体测试已用到 F28，本期计划的 F19–F29 撞号，顺延为 F29–F39。
- 1 期期末之后验收文档已用到第 29 项、E10，本期的真机项与决定顺延为 30–47、E11–E21（计划原写 23–40、E9–E19）。

### 遗留

- 真机验收第 30–47 项（种子页的样子与各平台表现、Ctrl+点击在 Win32 / GTK2 / Qt6 / Cocoa 上是否真的拦得住、导出的包在示例程序里能用）。
- 种子页的布局（两列色块各 104 px、侧栏 280 px）在宽皮肤、中文下是否挤，要真机看（第 30、46、47 项）。
- `TTbSeedsFrame` 的独立模型与预览各加载一次文档，`auto.tycss` 这类大主题刷新多一次加载（见上面的刷新耗时）。

### 主控要做的

1. 在签收头提交上 `lazbuild -B` 编 `tycontrols.lpk`、`tycontrols_dt.lpk`（本期库没改，按惯例确认）与 `tools/themebuilder/themebuilder.lpi`；`powershell -File scripts/smoke-launch-examples.ps1 -Dirs tools\themebuilder` 冒烟（只有主窗体与应用窗口、没有 `#32770`）。
2. Task 11 Step 5 的看一眼（种子页、改色、Ctrl+Z、win11 改圆角看询问、Ctrl+点击、覆盖检查、导出 green 到临时文件夹、片段小窗），并截两张图 `p2-seeds-win32.png`、`p2-export-win32.png` 放 `docs/superpowers/plans/2026-10-01-themebuilder-acceptance-shots/`（验收文档已引用）。
3. Task 11 Step 7 的期末审查（规格核对 + 代码质量，`git diff f87c46c6..HEAD`）。

---

## 期末修复批签收

签收日期 2026-10-01。起点 `bc0db145`（2 期签收与验收文档之后；`ba0df847` 是 3 期计划，不属本批）；本批提交 `b17730db`..`3ffe6d8a` 加本签收提交。两份期末审查列出的 12 个问题与同批小项全部处理，每个 bug 先写一条去掉修复就会红的测试，修后按「改字符串 → 编译 → 跑指定测试 → 写回原字节」逐条变异确认红（不用 git 还原）。库（`source/`、`designtime/`）一个字节没改。

### 主控已做（修复批开始之前）

在 `bc0db145` 上 `lazbuild -B` 编过 `tycontrols.lpk`、`tycontrols_dt.lpk`、`themebuilder.lpi`（0 错）；`check-example-po` 103 份 0 问题、`check-lfm-props` 通过；冒烟启动只有主窗体与应用窗口。两张截图（`p2-seeds-win32.png`、`p2-export-win32.png`）暂缓，三期做完统一出。

### 修复提交表

| 问题 | 提交 | 处理 |
|---|---|---|
| 1 严重：Ctrl+点击插空基规则，控件失去全部样式 | `b17ac0e1`、`3ffe6d8a`（核实） | 引擎让位的是**整个**底层（普通、状态、变体规则全部），只预填不带状态的那条不够（按钮的悬停、主按钮仍会变样）。不带变体时插入底层为该 typeKey 写的全部规则的副本（普通规则合并在前，变体 / 状态规则只留该 typeKey 的选择器），放在文档里该 typeKey 第一条规则之前（没有则文末）；导入的文件里已有普通规则时插空规则；带变体的照旧插空规则（钉住：不让位）；底层没有规则的 typeKey 插空规则，核实无变化（`TyFormSurface`）。H1：极简模板上 Ctrl+点 TyEdit / TyButton / TyCheckBox / TyListBox，每个变体 × 十组状态 × 明暗逐项相同。顺带 `tbcssscan` 记下 `@import` 路径、`TbScanImports` 照 `ExpandSheet` 跟导入链 |
| 2 中：拾取吞抬起标志残留 | `e96227d4` | 选「控件自己的按下先清标志」而不是 `SetCapture`：无需窗口句柄（图形控件、无头测试都成立），也不改 LCL 的捕获。Ctrl+双击的第二下只吞不跳（第一下是普通点击时仍跳一次）。「无残留捕获」无头测不了（`Perform` 的按下在任何情况下都留着捕获，需真机的抬起释放），测的是按钮自己的 `FPressed` / `OnMouseUp` / `OnClick`；真机项 49 |
| 3 中：覆盖检查把真键标成未知 | `66cdb20f` | 已知 = 目录 ∪ 底层规则键 ∪ 子部件表全部键（新增 `tyControls.GridPanel` 一行）∪ 预览键；守卫：库里每个单元在字符串里写的 typeKey 都已知（拼接用前缀除外） |
| 4 中：模式来自 `@import` 时种子面板与预览不符 | `d9f03124` | 列按求值模型的模式；来源判定把导入文件算进去（导入的 `@mode` 盖过文档 `:root` → 标「被导入文件的 @mode 盖过」，悬停说明）。改动入口两者都没选：**不禁用、不问，写进文档自己这一列的模式块**——它在导入之后，盖得过导入（引擎「importer wins」），测试里改完求值确实变了。E13 改为 palettes 的 `--radius` 是「来自导入的文件」 |
| 5 中：种子面板刷新开销 | `cf816c5e` | 见下面计时表。文本 + 目录不变不重算；一列一次切模式；种子页看不见时只收文本、切回（工具窗口 `OnShow`）或被读时再算——改值前 `OnSync` → `RefreshNow` → 收文本，`SetValue` 随后 `CatchUp`，核实安全（F31、SF11 守着）；微调框 250 ms 防抖，连着的半径写入（同一列、中间没别的改动）合成一步撤销（`ApplyEdits` 的合并键：撤销上一步、从第一步之前一次写到最终文本，撤销落点不对就重做、单算一步）；等待中的一步在保存、导出、片段、跳规则、关窗前写入。计时测试拆三段打印，判据：种子段 ≤ 预览段、同一文本再来 ≈ 0 |
| 6 中低：覆盖检查双击插重复规则 | `1e47b736` | `JumpToTypeKey`：先找任意同 typeKey 的选择器（循环），没有才插入；Ctrl+点击保持严格 |
| 7 低：坏文档时种子页仍显示上一版的值 | `beca3de7` | 行全部藏起来（`Scroll.Visible := False`），只留「先修好…」 |
| 8 低：拆分 / 补 `--radius` 后现代密度圆角失效 | `1603fdee` | 拆分只写五个颜色种子；两列文档中某列没有自己的 `--radius`（共用或继承）时先问：是 → `:root`（密度仍盖过它），否 → 该列模式块（也盖过密度，问题里说明），取消。`TbSeedSetEdits` 的 `AShared` 对继承格 = 写进顶层 `:root`。J1：拆分后现代密度下圆角为 8 |
| 9 低：导出读回只试经典密度 | `6efd8319` | 读回模型叠现代密度包、逐模式再试；失败说明是哪种密度 |
| 10 低：代码片段不区分有无引用 | `35bb84c9` | 库没有带基准目录的注册 API（`TyRegisterThemeCss` 只收文本）→ 有相对引用时 zip 与注册两段灰掉（复制按钮也灰）、上方一行说明并点名第一个文件 |
| 11 低：种子页布局 | `6ff7eaa4` | 行 `AutoSize`、说明标签折行并锚在色块下（与色块等宽）、右列锚在左列右边、顶上说明 `AutoSize`；「来自 :root，是表达式」一整条 resourcestring。无头不跑 LCL 自动尺寸（窗口不显示就推迟），测的是布局的构成与标签的首选高度；真机看第 30、46、47 项 |
| 12 轻：空编辑器整段替换多一个空行 | `b17730db` | 不止去掉结尾换行：SynEdit 往零行的编辑器插入时自己还会在后面多出一个空行，同一撤销块里删掉 |
| 小项：`DoExport` 不看收集错误 | `3688fbd1` | 入口返回收集错误、不写任何东西 |
| 小项：`CheckTarget` 递归扫整棵树 | `2179057b` | 看到第一项就停；行为等价（「只看第一项」本身没有可观测的红，变异 X8b 钉住「只含子文件夹也不算空」） |
| 小项：文件夹提交失败删了用户空目录、报错不实 | `3247a669` | 先挪开、失败挪回；提示带系统原因（测试用 `TbExportRenameForTest` 缝模拟挪动失败） |
| 小项：zip 提交静默删已有 `.tbbak` | `9eaca60d` | 旧 zip 挪到没人用的名字（`.tbbak` → `.1.tbbak` …），已有的不动 |
| 小项：引用路径大小写两种写法 | `e6cf1d0a` | 选「拒绝导出并说明」：Windows 上是同一个文件、两份存不下（文件夹不分大小写），包里只能一种路径 |
| 小项：入口改名 `theme.tycss` 与被导入的同名文件冲突 | `afea0951` | 选「报错」（`theme.tycss`、`theme.json`，不分大小写；子目录里的同名文件不冲突）：改名要改导出文本里的引用 |
| 小项：圆角微调框 `MaxValue` | `552370a7` | 64 → 256 |
| 小项：`#rgba` 当成纯颜色 | `10578389` | 只认 3、6、8 位（`TyParseColor`） |
| 小项：`ValueEndBefore` 遇嵌套样子的 `/*` | `566b9cd3` | 改为照词法器向前读（注释到第一个 `*/`、字符串到收尾引号） |
| 小项：`OnEdits` 改函数 | `99ba1ec7` | 拒绝时色块回到原值 |
| 小项：F39 的 `AssertTrue(True)` | `ff04cb73` | 断言样例窗口也挂上、拾取生效（加了规则）、释放不抛；被计时测试隔开的注释已回到 F39 上方（`cf816c5e` 里拆计时测试时一并挪回） |
| 中文 | `d2950fa4` | 本批新增的 10 条代码字符串进 `.json` 与 `.po` |
| spec / 计划 / 验收 | 本提交 | 见下 |

### 计时（`themes/auto.tycss`，毫秒，各项五到七次的中位数；修前用审查的探针 `probe2` 在 `bc0db145` 上跑两次，修后用同样测法的 `probe3` 跑两次；另一棵树可能同时在跑全量）

| 量 | 修前 | 修后 |
|---|---|---|
| 一次 `RefreshNow`（修前：种子页总是算） | 250、266 | 种子页藏着：203、187；种子页看得见、换了文本：281、313 |
| 其中 lint | 46、32 | 47、32 |
| 其中预览加载 + 试解析 | 125、125 | 172、156 |
| 其中种子页，同一文本再刷新 | 94、109 | **0、0** |
| 其中种子页，换了文本 | （同上，修前每次都全算） | 94、93 |
| 改一个种子，端到端 | 281、250 | 297、266 |
| 圆角连改五下（逐下写入的老路径） | 1375、1391，五步撤销 | 1485、1297（逐下 `ApplyValue`，每下一次刷新——这不是微调框的路径） |
| 圆角微调框连按五下（250 ms 等待不计） | 同上一行 | **312、265，一次写入、一步撤销** |
| 全量里的 K1（五次中位数） | — | lint 47、预览 141、种子页 94（同一文本 0）、藏着时整次刷新 187 |

看得见时换了文本的那一次刷新仍多一次整份加载（约 80–95 ms）：第二个模型是 2 期定的设计（不带密度包、按列切模式），本批没动它；能省的是看不见时、文本没变时和圆角连按。

### 测试结果

- `lazbuild -B tests/tytests.lpi` 0 错，exe 复制为 `tests/tytests-tb2fix.exe`。
- 本期 suite：TTbCssScanTests 15、TTbRulesTests 7、TTbSeedEditTests 15、TTbSeedsFrameTests 18、TTbPickTests 11、TTbCoverageTests 9、TTbExportTests 16、TTbSnippetsTests 8、TTbMainFormTests 56，全绿（155 条；2 期签收时 124 条，本批 +31）。
- 全量（`tests/tytests-tb2fix.exe --all`，输出重定向到文件）：**8801 / 0 errors / 0 failures**（20 分 06 秒）= 2 期签收 8770 + 本批 31；无红，没有计时类偶发红。其中 K1 打印：lint 47 ms、预览 141 ms、种子页 94 ms（同一文本再来 0 ms）、种子页藏着时一次完整刷新 187 ms。
- `lazbuild -B tools/themebuilder/themebuilder.lpi` 0 错；`check-example-po.py` 103 个文件 0 问题；`check-lfm-props.py` OK。

### 变异（每条改字符串 → `lazbuild` → 跑指定测试 → 写回原字节；`.lfm` 的变异同时碰一下单元的 `.pas` 让它重编）

| # | 变异 | 结果 |
|---|---|---|
| G1a / G1b | 空编辑器不去结尾换行 / 不删 SynEdit 多出的空行 | 红 / 红 |
| H1a / H1b | 普通规则也插空 / 不抄底层的变体与状态规则 | 红 / 红（各状态的样子变了） |
| H2 | 变体规则也抄底层 | 红 |
| H3 | 抄来的规则放文末 | 红 |
| H4 | 不看导入文件里的普通规则 | 红 |
| C15 | 导入链里子文件用父目录解析 | 红 |
| I1 | 覆盖检查双击走严格查找 | 红 |
| P10 | 普通按下不清吞抬起标志 | 红 |
| P11a / P11b | Ctrl+双击第二下也跳 / 普通按下不清「上一下是拾取」 | 红 / 红 |
| CV8a / CV8b | 不看预览键 / 不看子部件表 | 红 / 红 |
| CV9 | 子部件表没有 GridPanel 的键 | 红 |
| S12a / S12b | 列按文本 / 来源不看导入文件 | 红 / 红 |
| E14a / E14b | 导入的 `@mode` 不算 / 导入的 `:root` 不算 | 红 / 红 |
| J1a | 拆分仍写 `--radius` | 红（J1、SF9、E12） |
| J1b | 圆角不问 | 红 |
| E15 | 继承格「共用」不写 `:root` | 红 |
| SF14 | 忽略 `OnEdits` 的回答 | 红 |
| K2 / K2b | 看不见也全算 / 不挂 `OnShow` | 红 / 红（AV） |
| SF16 | 同一文本也重算 | 红（SF16、K1） |
| SF15a / SF15b / SF15c | 微调框不等 / 刷新时把等待中的值冲掉 / 不带合并键 | 红 / **先存活**（夹具刷新用的是同一文本、被缓存挡住、根本没刷到微调框——「断言里那个量从没变过」；改为一段新文本后红）/ 红 |
| K3 | 不合并 | 红 |
| K3b | 合并不先看文本是不是上一步留下的 | **等价**：撤销后再核对「回到了第一步之前」，对不上就重做、单算一步——这层兜底让它与原判据结果相同 |
| K4 | 保存前不写等待中的一步 | 红 |
| SF6b | 坏文档只禁用不藏 | 红 |
| L1 | 行不 `AutoSize` | **先存活**（`.lfm` 改了但单元没重编，资源仍是旧的——工具问题，不是测试问题）；harness 改为同时碰 `.pas` 后红 |
| SF17 | 两条字符串拼接 | 红 |
| SF18 | 微调框上限 64 | 红 |
| E11b | `#rgba` 当纯颜色 | 红 |
| C16 | 值的结尾用旧的向后找 | 红 |
| X12 | 读回不试现代密度 | 红 |
| X13 | `DoExport` 不看收集错误 | 红 |
| X14a / X14b | 失败不挪回 / 报旧的错 | 红 / 红 |
| X15 | 删掉已有的 `.tbbak` | 红 |
| X16 | 不查两种写法 | 红 |
| X17 | 不查与入口同名 | 红 |
| X8b | 只把文件当「有东西」 | 红 |
| S8 | 有引用也不灰 | 红 |
| F39 | 样例窗口不挂钩 | 红 |

全部还原后 `git diff --quiet -- source tools tests designtime` 为真，再 `lazbuild -B` 跑全量（上面「测试结果」）。

### 写回 spec（标「实现期修正（2 期）：期末修复」）

状态行；§5.1（圆角连改合成一步撤销、250 ms 防抖）；§5.2（列看模型、来源算导入文件及照实说明的边角、拆分不写 `--radius` 与圆角提问、`#rgba`、刷新开销、坏文档藏行、微调框 0–256、行自适应）；§5.3（Ctrl+点击插入底层规则副本及让位机制、拦截的抬起与双击、覆盖检查的已知键与双击）；§6（读回两种密度、`theme.tycss` / `theme.json` 同名拒绝、大小写两写拒绝、目标目录看第一项、挪开不删、`.tbbak` 不删、`DoExport` 自查；片段对有引用的主题灰掉两段）；§8。审查原文不在本 agent 手里，「审查列的 8 条偏差」按修复清单对应到上面这些节逐条写回。

### 计划外发现

- SynEdit 往零行的编辑器插入文本时自己会在后面多一个空行（问题 12 不止是结尾换行）。
- 引擎解析 `@import` 先按**当前工作目录**找、找不到才用导入方目录（`ExpandSheet`）；`TbScanImports` 照抄了这个顺序。
- 无头时 LCL 的自动尺寸对不显示的窗口一律推迟，`AdjustSize` 也不动——布局只能测构成，尺寸要真机看。
- `.lfm` 的改动不会让单元重编，`lazbuild` 的增量构建里资源仍是旧的（变异 L1 第一次「存活」的原因）；改 `.lfm` 后要碰一下 `.pas` 或 `-B`。
- 本 agent 在草稿目录里自己的 Python 辅助脚本上用过一次 `sed -i`（只改了 exe 路径一行，仓库文件全部用 Edit / Write / 落盘脚本）。

### 遗留

- 种子页看得见时，换了文本的刷新仍多一次整份加载（设计如此，见计时表）。
- 抄进来的底层规则与文档原有变体规则交叉改同一属性时，外观可能有出入（spec §5.3 照实写了）。
- 「无残留捕获」与布局尺寸只能真机看（验收第 30、47、49 项）。

### 主控待做

1. 在本签收头提交上 `lazbuild -B` 重编 `tycontrols.lpk`、`tycontrols_dt.lpk`（本批库没改，按惯例确认）与 `tools/themebuilder/themebuilder.lpi`，`powershell -File scripts/smoke-launch-examples.ps1 -Dirs tools\themebuilder` 冒烟。
2. 两张截图 `p2-seeds-win32.png`、`p2-export-win32.png` 暂缓，三期做完统一出。
