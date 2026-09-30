# 终端控件 3 期：可见控件（绘制、键盘、滚回、主题、回放示例）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（项目约定，优先于子技能的默认做法）**：按子批次连续实现，**每个任务只写代码 + 测试并单独提交**；每个子批次写完**编译一次、只跑本段的 suite、只修本段的红**（照 2 期的分段编译）；node 生成脚本例外，生成物要进提交，脚本当场跑。整期写完后（Task 20）一次全量、集中变异、整体审查（规格核对 + 代码质量）。中途不汇报、不问要不要提交。**用户要求全部各期做完再一次性真机验收**：本期的截图、真机项都进期末验收材料（本文末尾「真机验收项汇总」），不中途找用户。
>
> **谁来做**：标 **【主控执行】** 的步骤实现 agent **不做**、直接跳过：合并分支、编 `tycontrols.lpk` / `tycontrols_dt.lpk`、编示例、跑 `scripts/gen-icons.ps1`、跑 `scripts/example-rsj2po.py`、截图、在 Qt6 等非 Win32 widgetset 上构建探针、要联网的步骤。实现 agent 不编任何 `.lpk`、不编示例、不改 `D:/Projects/xterm.js` 里被跟踪的文件，node 依赖不进本仓库。
>
> **共享文件**：`source/tyControls.Base.pas`、`source/tyControls.Painter.pas` 本期**不改**（见「需要改共享文件的地方」：结论是不需要）。执行中若发现非改不可，停下交主控，主控先问用户。

**Goal:** 新增可见控件 `TTyTerminalView`：把 2 期的 `TTyTerminalCore` 画出来（行缓存、字形缓存、属性、光标、自绘制表符和块元素、DPI）、接上键盘（移植 `Keyboard.ts`）、滚回与内嵌滚动条、主题配色，外加回放示例 `examples/terminal` 和控件文档。

**Architecture:** 三个新单元。`tyControls.Terminal.Keyboard`（纯函数，照 `Keyboard.ts` / `Clipboard.ts` 移植，node 跑上游生成期望值逐位比）；`tyControls.Terminal.Render`（不依赖控件的渲染部件：单元格度量、颜色解析、256 色表、字形遮罩缓存、自绘字形、行绘制器，可单独测）；`tyControls.Terminal`（控件：持有 Core、调度写入、把 Core 的事件接到重画 / 滚动条 / 宿主事件，键盘与滚轮分流，主题取色）。渲染路线由开工前实验 E1 / E2 定：字形画成**不带颜色的覆盖率遮罩**缓存起来，着色时贴；宽度 2 的簇可走单独的宽字体。无头测试用哨兵底色数像素，事件测试经真实的 `KeyDown` / `UTF8KeyPress` / `DoMouseWheel`。

**Tech Stack:** FPC 3.2.2 / Lazarus LCL、BGRABitmap（`TGrayscaleMask` + `FillMask`）、`TTyPainter`（只画外框）、`.tycss` 主题与三个生成器、fpcunit；node v22.22.2 + xterm.js 6.0.0 本地 checkout 的 `out/`（1 期已构建）。

**设计依据：** `docs/superpowers/specs/2026-09-28-terminal-view-design.md`（下称 spec）。本计划覆盖 §18 第 3 期、§8、§9（鼠标只到本期边界，见开工前问题二第 10 条）、§10（最低对比度除外，5 期）、§11、§12.1（回放）、§13.6（3 期部分）、§14、§16（汇总进验收表），以及 2 期签收的「给 3 期的交接」全部九条、1 期签收遗留的两条文档项。

**不在本期**（spec §18）：真 shell / PTY（4 期）；鼠标按键上报、本地选择、右键菜单、横向滚轮、中键、Linux PRIMARY、`CopyOnSelect`、OSC 52、链接（4 期）；重新折行、流量控制、整屏上滚的缓存平移、最低对比度、盲文 / Powerline / Legacy Computing 自绘（5 期）；CHANGELOG（发版时写，[[changelog-user-facing]]）。

---

## 总目录

本计划分一个主文件和四个子批次附录。**先读完主文件**（核实记录、开工前问题、接口清单、地雷、判据约定），再按任务号顺序做；附录里的任务引用主文件的节名。

| 部分 | 文件 | 任务 | 这一批做完能看到什么（执行时不单独验收，见执行方式） |
|---|---|---|---|
| 主文件 | 本文件 | Task 0 基线、合并、开工前实验 E1 / E2；Task 20 收尾 | E1 / E2 的测量表写进本文件「实验记录」，渲染路线定下来 |
| 3a 键盘 | [`2026-09-29-terminal-phase-3a-keyboard.md`](2026-09-29-terminal-phase-3a-keyboard.md) | Task 1–3 | `evaluateKeyboardEvent` 全组合（VK × 修饰键 × 应用光标 × 平台）、第三层 Shift、粘贴编码与上游逐位相同 |
| 3b 渲染与控件骨架 | [`2026-09-29-terminal-phase-3b-render.md`](2026-09-29-terminal-phase-3b-render.md) | Task 4–10 | 控件能把 Core 画出来：16 / 256 / RGB 色、粗体亮色、暗淡、反显、隐藏、五种下划线、删除线、上划线、宽字符两格、制表符与块元素连成线、光标三种形状与失焦样式、闪烁、同步输出、DPI；只重画脏行；字形缓存命中 |
| 3c 输入与滚回 | [`2026-09-29-terminal-phase-3c-input.md`](2026-09-29-terminal-phase-3c-input.md) | Task 11–14 | 键盘经真实 `KeyDown` / `UTF8KeyPress` 发出正确字节、吞键与 `OnShortcutQuery` 放行、复制粘贴快捷键；滚动条与滚轮三种去向；点击取焦点；输入法提交与候选窗定位 |
| 3d 主题、注册、示例、文档 | [`2026-09-29-terminal-phase-3d-theme-example.md`](2026-09-29-terminal-phase-3d-theme-example.md) | Task 15–19 | §11 的键与 token 进基础层，17 个主题 × 明暗 16 色都解析得出、浅底那套对白底 ≥ 4.5:1；面板注册与图标；回放示例；控件文档与 README |

---

## 核实记录（写计划时读源码 + 实跑得到，2026-09-29）

执行者不用重做；Task 0 会在真构建上复核其中几条。

1. **分支落后 main 两个提交**，其中 `b23893ba fix(text): on Windows, text is drawn in ClearType's shapes` 改了 Win32 的文字管线：`TyConfigureTextFont` 在 Win32 上不再用 `fqFineAntialiasing`（6× 超采样、用户说「整体发虚」），改装 `TTyGdiTextRenderer`（ClearType 黑字白底画一遍、三通道平均成覆盖率、按墨色混合）。`feat/terminal` 上的 `Painter.pas:1184-1188` 还是旧的。E1 / E2 在 Windows 上量的必须是将来发布的那条管线（开工前问题二第 1 条）。
2. **spec §10.3 的 E2 默认做法（a）在 Windows 上会把用户否掉的「虚」带回来**：（a）是「3× 超采样后缩小」，和旧的 `fqFineAntialiasing` 同类；用户 2026-09-28 否掉的正是它（[[bgra-small-text-blur-linux]] UPDATE-3）。所以 E2 加第三种做法（c）：用库自己的文字管线在 1× 下黑字白底画一遍，`255 − 灰度` 就是覆盖率遮罩——不带颜色、可缓存，字形和库里其余文字逐像素一致（`TTyGdiTextRenderer` 本来就是「覆盖率 × 墨色」线性混合，所以黑底白底取出的覆盖率再着色，数学上等于直接画）。
3. **`font-family` 不求值**：`StyleModel.pas:875-879` 直接 `AStyle.FontName := raw`，写 `font-family: var(--terminal-font-family)` 会得到字体名 `var(--terminal-font-family)`。`font-size` 走 `TyEvalLength`（`:880-884`），`var()` 可用。所以字体族由控件读 token：`ActiveController.Model.RawVar('--terminal-font-family')`（`StyleModel.pas:1193`），基础层规则里**不写** `font-family`（开工前问题二第 6 条）。库里所有主题都没有 `font-family`，`monospace` 也没出现过（只在 AdvChart 目录字符串里）。
4. **主题的聚焦伪类叫 `:focus`**（`Css.Parser.pas:90`、`:164-172`；`TyMemo` 规则 `light.tycss:695-706`），spec §11 写的 `:focused` 不存在。
5. **三参数 `on()` 看的是 Rec.601 亮度**（`Css.Values.pas:154-160`、`:177-180`；> 0.5 取第二个参数、否则第三个，恰好 0.5 算深），不是 WCAG 相对亮度。WCAG 相对亮度库里只有 Core 的 `TyTermRelativeLuminance`（`Terminal.Core.pas:575`），对比度测试用它。
6. **没有「主题变了」的钩子**：`TTyStyleController.Changed`（`Controller.pas:665-687`）只对每个登记的控件 `Invalidate`；换主题、换明暗都会让 `Model.ThemeVersion` 加一（`StyleModel.pas:1084`）。`TTyScrollBar.Invalidate`（`ScrollBar.pas:992-1015`）就是靠覆盖 `Invalidate` 比 `ThemeVersion` 听见换主题的，并写明为什么不用 `AddChangeListener`（控件的 Controller 可中途换、可回落到全局，挂方法指针容易野）。
7. **StyleOverride 能单独解析**：`Base.pas` 的 `FOvrCache` 是私有的，但它来自公开的 `model.ResolveOverride(StyleOverride)`（`Base.pas:2098`），控件自己调一次就知道覆盖里有没有 `font-size` / `font-family`——实现「StyleOverride > 显式 Font > 主题」（字体覆盖通道需求第 4 条）不用改 `Base.pas`。现成的 `TyResolveFontSize`（`Base.pas:2107-2125`）是「主题 > 显式 Font」，顺序相反，终端不用它。
8. **上游 `Keyboard.ts` 不看应用小键盘模式**：`evaluateKeyboardEvent`（`xterm:src/common/input/Keyboard.ts:38-380`）只收 `applicationCursorMode`；`applicationKeypad` 只在 `InputHandler` 里设、在 DECRQM 里报（`InputHandler.ts:1973`、`:2232`、`:2379`），浏览器层没有任何按键读它。小键盘数字（keyCode 96–105）走默认分支、按 `ev.key` 发字符（`:361-364`）。见开工前问题一第 1 条。
9. **第三层 Shift 有三项**（`CoreBrowserTerminal.ts:937-948`）：macOS Option 且不当 Meta、Windows Ctrl+Alt、Windows `getModifierState('AltGraph')`；keydown 时还要求 `!keyCode || keyCode > 47`（方向键、退格等不算）。spec §8.4 的 `TyTerminalIsThirdLevelShift` 少了第三项和 keydown / keypress 之分。LCL 的对应物是 `ssAltGr`（接口清单加 `AltGraph` 字段和 `AKeyPress` 参数）。
10. **上游 keydown 处理过的键，keypress 就不再发**（`_keyDownHandled`，`CoreBrowserTerminal.ts:976-980`）；A–Z 无修饰键时故意留给 keypress（`:898-903`）。LCL 各 widgetset 在 `KeyDown` 把 `Key` 清零后还会不会送字符不一致：Win32 在 `WM_KEYDOWN` 被 LCL 处理时（`Result <> 0`）吞掉随后的 `WM_CHAR`（`lcl:interfaces/win32/win32callback.inc:2033-2041`、`:2294-2298`、`:2736-2739`），反过来**没清零的键不会被吞**。所以（a）能出字符的键在 `KeyDown` 里**不能清零**，否则 Win32 上字符丢了；（b）控件自己记一个 `FKeyDownHandled`，`UTF8KeyPress` 见到就丢，不依赖 widgetset（地雷 4）。
11. **上游 14t / 16t 的应答**（`CoreBrowserTerminal.ts:1133-1150`）：`ESC[4;<高>;<宽>t` 取画布（网格区）尺寸，`ESC[6;<格高>;<格宽>t` 取格子尺寸，都是 CSS 像素、经 `triggerDataEvent`（非用户输入）。我们报设备像素（同 §15 里 1016 的偏离）。
12. **同步输出的超时从「第一次攒行」起算**，不是从模式打开起算（`RenderService.ts:337-380` 的 `SynchronizedOutputHandler.bufferRows`，`_timeout ??=`）；关掉 2026 时 Core 已经 `RefreshAll`（`Terminal.Core.InputHandler.inc:1306-1310`），超时入口 `EndSynchronizedOutput` 也整屏刷新（`Services.inc:392-403`）。
13. **颜色的上游语义**（`DomRendererRowFactory.ts:342-460`）：先反显（前景底色连同颜色模式一起换），默认色反显时底色取前景色、前景取底色；粗体亮色对 P16 **和 P256** 的 `fg < 8` 都加 8（在反显之后）；暗淡是前景 50% 透明叠在底色上；下划线色若是调色板色且粗体、`< 8` 也加 8（`:313-320`）；隐藏的格子按空格画（`:302-306`）。
14. **滚轮不上报时的方向键**经 `triggerDataEvent(seq, true)`（算用户输入，`MouseService.ts:287-288`）；程序要了滚轮事件时这条路直接不走（`:254-256`）。Core 的 `TriggerMouseEvent` 对不含滚轮的协议（X10）返回 False，正好落到这条路。
15. **自绘字形的上游数据**：`addons/addon-webgl/src/customGlyphs/CustomGlyphDefinitions.ts`（1019 行，MIT，2021 xterm.js authors），`out/` 里可直接 `require`，导出 `customGlyphDefinitions`（**以字符为键**）和 `blockPatternCodepoints`。实跑：U+2500–257F 全是 `PATH_FUNCTION`（178 段，其中 U+2550–2570 的双线和圆角 33 个是**函数**、其余是路径串），U+2580–259F 是 29 个 `SOLID_OCTANT_BLOCK_VECTOR` + 3 个 `BLOCK_PATTERN`（U+2591–2593 阴影）。光栅化在 `CustomGlyphRasterizer.ts`（768 行）：`drawBlockVectorChar` `:129-168`、`drawPatternChar` `:462-530`、`drawPathFunctionCharacter` `:531-589`、`translateArgs` `:734-768`。
16. **`DEFAULT_ANSI_COLORS` 在 node 里可直接加载**（`out/browser/Types.js`，只依赖 `common/Color`）；`Clipboard.js` 的 `prepareTextForTerminal` / `bracketTextForPaste` 只有类型导入，也可直接调；`out/common/input/Keyboard.js` 在。
17. **注册一个控件要过的守卫**：`test.version.pas` 的 `Reg()` 块（`TestEveryRegisteredNameResolves`，`:200-225`）、`test.focus.tabstop.pas` 的 TabStop 表（`:215-240`，终端归「自己处理按键」那一组）、`test.paletteicons.pas`（`:60`、`:100` 起）、`test.dpi.measurefont.pas`（`:115-121`，按注册表取全体）、`test.designregistry.pas`（解析 `Design.pas`）。全局的「published default = 构造值」守卫只查 `TabStop`（`test.focus.tabstop.pas:473-497`），其余属性要本控件自己的测试守。
18. **滚动条的做法照 `TTyMemo`，不是 `TTyScrollBox` 的三个布局钩子**：Memo 的竖条是 `alRight` 的子控件（`Memo.pas:2408-2424`），宽度取 `--scrollbar-size`，只用 `OnChange` 回写（`:2331-2340`），`ITyScrollBarFrameHost` 两个方法（`:2362-2370`）；三个钩子在 `TTyScrollBox`（`ScrollBox.pas:116-153`），是给「有子控件要排」的容器用的。终端没有要排的子控件。
19. **无头测试的前提**：控件要有父窗体、自建 controller、哨兵底色（[[headless-render-needs-sentinel-ground]]）；`alRight` 条的位置要自己调 `AlignControls(nil, ClientRect)`（传没扣过的矩形，[[headless-tests-never-run-lcl-align]]）；`QueueAsyncCall` 在无头里能用，`Forms.Application.ProcessMessages` 排空（`test.controls.combobox.pas:271-275`），真句柄要先 `Forms.Application.Initialize`（`test.focus.tabstop.pas:595` 的惰性开关）。
20. **i18n**：库的字符串在 `source/tyControls.StrConsts.pas`，`.pot` 在编包时生成（`tycontrols.lpk:920-923`）；示例各有 `examples/<x>/languages/<工程>.zh_CN.po`，由 `scripts/example-rsj2po.py` 从编好的 `.rsj` 生成（要先编示例）。本期控件**没有**用户可见字符串（右键菜单连同「清屏」在 4 期，见开工前问题二第 10 条），i18n 只有示例。
21. **README**：`README.md`（中文）、`README.en.md`，「168 个控件」在第 3、36、80 行，`### … TyControls Edits(14)` 在 :114，示例表 :363-385；控件文档索引 `docs/controls/README.md:73` 一带（`TheControlDocsIndexLinksEveryPageAndOnlyRealOnes` 双向守着，`test.release.pas:712`）。

---

## 开工前要定的问题

每条都给了建议，**计划正文按建议写**；改了哪条，执行时改对应任务，收尾时（Task 20）写回 spec。

### 一、产品方向 / 用户可见（问用户）

> **状态（2026-09-29）**：三条先按建议执行（小键盘照上游不受应用小键盘模式影响；滚动条宽度一直留着；浅底 16 色的 7、15 按已定方案不调、期末截图单独给用户定），已告知用户，用户在最终一次性验收时可改。第二类主控按建议采纳。
>
> **Task 0 主控部分**：main（含 `b23893ba` Win32 ClearType 文字管线）已合入 `feat/terminal`（`3c86b8c7`，无冲突）。基线全量由实现 agent 在 Task 0 跑。

1. **应用小键盘模式（DECKPAM / `CSI ? 66 h`）要不要影响小键盘？**（核实记录 8）
   xterm.js 不管这个模式：小键盘数字、`+ - * / .` 一律发字符，模式只记下、DECRQM 照报。真 xterm 在这个模式下发 `ESC O p` … `ESC O y` 之类。
   **建议**：照上游，不影响——键盘一整块才能逐位对上游比；vim、less、htop 都不靠它。另一个做法是按 xterm 发 `ESC O` 系列，但那是没有基准的偏离，还要进 §15。
2. **滚动条的宽度要不要一直留着？**
   备用屏（vim、htop）没有滚回，spec §9.7 说「滚动条禁用（AutoHide 时藏起）」。如果「藏起」是真把条拿掉，列数就变了：进 vim 那一刻终端会多出一列、给程序发一次改尺寸，退出又变回来。
   **建议**：一直留着条的宽度，列数不随主屏 / 备用屏变化；备用屏里条禁用（自动隐藏的主题下淡掉，留一条空白）。代价是全屏程序右边有一条空白。
3. **浅底 16 色里 7（白）和 15（亮白）在白底上几乎看不见，要不要也调？**
   §17.1 第 4 条定的是「0、7、8、15 除外」。照这个做，7 / 15 在浅底上仍是 Tango 的 `#d3d7cf` / `#eeeeec`（对白底约 1.4:1 / 1.2:1）。一些浅色终端配色会把它们调成中灰。
   **建议**：照已定的做（不调），期末截图里专门放一张 7 / 15 的样例，你看了再定。选「调」的话，7 调到对白底 ≥ 3:1、15 保持最浅，写进 Task 15。

### 二、实现层面（主控定）

1. **先把 main 合进 `feat/terminal` 再开工**（核实记录 1）。main 多出的两个提交里有 Win32 文字管线的 ClearType 修复；不合的话 E1 / E2 在 Windows 上量的是要被替换掉的 `fqFineAntialiasing`。**建议**：Task 0 Step 2 主控 `git merge main`（不 rebase），合完跑一次全量当基线。
2. **输入法放 3 期**：spec §18 把输入法放 4 期，本期任务要求做。**建议**：3 期做提交通路（Win32 / Qt / GTK2 / GTK3 / Cocoa 的库内钩子）、候选窗按光标格定位、macOS 组字串画在光标处（Task 13）；真机验收照旧期末一次。写回 §18。
3. **新增单元 `tyControls.Terminal.Render` 和生成物 `tyControls.Terminal.CustomGlyphs.inc`**：spec §2.1 只有一个控件单元。渲染部件（度量、颜色解析、字形缓存、自绘字形、行绘制器）不依赖控件，拆出来可以单独测，控件单元也不至于上万行。`.inc` 由 node 从上游 dump（同 `Charsets.inc` 的先例），不进 `.lpk`。写回 §2.1、§14。
4. **宽字体路径总是实现**，E1 只决定各平台的默认值：token `--terminal-font-family-wide`，关键字 `monospace-wide` 由控件换成平台 CJK 字体，空串表示「不另用字体、交给系统替换」。这样 E1 在其他平台的真机结论只改一个默认值，不改结构。
5. **E2 加做法（c）并作为首选候选**（核实记录 2）。判据见 Task 0。
6. **字体族不走 `var()`**（核实记录 3）：控件按「StyleOverride 的 `font-family` > `ParentFont = False` 且 `Font.Name` 不是 `'default'` > `TyTerminal` 规则里写了 `font-family` > token `--terminal-font-family` > `monospace`」取，再把 `monospace` 换成平台等宽字体。字号同理：「StyleOverride 的 `font-size` > `ParentFont = False` 且 `Font.Size <> 0` > `TyTerminal` 的 `font-size`（基础层写 `var(--terminal-font-size)`）」。
7. **`:focus` 不是 `:focused`**（核实记录 4），写回 §11。
8. **控件的 `OnOsc` 跟 Core 同签名**（`TTyTerminalOscEvent`，没有 `var AHandled`）：spec §9.2 还写着 `AHandled`，但 §7.4 已经删掉了（Core 对未处理 OSC 没有默认动作）。写回 §9.2。
9. **`TTyTerminalKeyEvent` 加 `AltGraph` 字段、`TyTerminalIsThirdLevelShift` 加 `AKeyPress` 参数**（核实记录 9），写回 §8.4。
10. **3 / 4 期的边界**：
    - 鼠标：3 期只做**点击取焦点**和**竖向滚轮**（程序要滚轮就经 `Core.TriggerMouseEvent` 上报；否则有滚回滚 3 行；没有滚回且 `AlternateScroll` 就发方向键）。按键上报、本地选择、覆盖键、右键、中键、横向滚轮、鼠标捕获都在 4 期。
    - 剪贴板：3 期有 `PasteFromClipboard`、`Paste`、粘贴快捷键（Ctrl+Shift+V / Shift+Insert / Cmd+V），粘贴编码含括号粘贴（纯函数随键盘单元移植、对上游比；spec §18 把「括号粘贴」列在 4 期，指的是真机验收）。复制快捷键 3 期**照吞**（交给 `CopyToClipboard`，没有选区时什么都不做），`CopyToClipboard` 与选区一起在 4 期实现。
    - 右键菜单（`ITyTextEditActions`、「清屏」resourcestring）在 4 期，和选区一起；spec §18 第 3 期「i18n：右键菜单的『清屏』」挪到 4 期。
    - `SelectionOverrideKey`、`Osc52`、`WordSeparators`、`CopyOnSelect`、`DetectUrls`、`OnLinkActivate`、`OnOsc52`、`OnSelectionChange`、选区方法在 4 期才加进接口（后加 published 属性不破坏 `.lfm`）；`MinimumContrastRatio` 在 5 期。
11. **录制文件拷进示例**：`examples/terminal/recordings/` 放 2 期的 8 份 `.cast`（合计约 48KB），发布包里示例自成一体；`test.release.pas` 加一条守卫：两处同名文件字节相同（防以后只重录了一边）。
12. **新增公开方法 `SizeForGrid(ACols, ARows): TSize`**（给定网格要多大的客户区）：示例「按录制尺寸」要用，宿主想固定 80×24 也要用。写回 §9.3。
13. **主题变化的检测**：覆盖 `Invalidate`，比 `ActiveController.Model.ThemeVersion`（照 `ScrollBar.pas:992-1015` 的先例，理由同那里的注释）；`RenderTo` 开头再比一次兜底（无头测试直接调 `RenderTo`）。变了就：重建色表、清覆盖（`Core.NotifyColorSchemeChanged`）、度量键失效；**网格尺寸若因此变了，改尺寸经 `QueueAsyncCall` 延后，不在 `Paint` 里 `Core.Resize`**（改尺寸会发事件、宿主会改 PTY、会再次失效重画，在绘制中做这些就是重画风暴——`Base.pas` 里 `FInEraseRefresh` 那段注释记过同一类事故）。
14. **表面位图**：控件持有一张**客户区大小**的不透明 `TBGRABitmap`（外框 + 内边距 + 网格），外框和内边距只在主题 / 尺寸变化时经 `TTyPainter.BeginPaintOn`（`Painter.pas:1306`）画一次；脏行直接画进网格区；`Paint` 只 `DrawPart` 画布的裁剪区。这就是 spec §10.1 的「行缓存位图」，外框仍走 `TTyPainter`，但不每帧新建整张位图。
15. **脏行按视口映射**：Core 报的行号相对 `YBase`，控件换成视口行 `y + YBase − YDisp`，落在视口外就不画；`OnScroll` 整屏重画。上游在用户上翻时会重画错的行（它直接把 `y` 当视口行），渲染是我们自己写的，不算偏离。
16. **调度的测试缝**：受保护的虚方法 `ScheduleSlice`（默认 `Application.QueueAsyncCall`）让测试能数「排了几次」；另外必须有一条走**真** `QueueAsyncCall` + `Forms.Application.ProcessMessages` 的用例（[[built-not-wired-is-the-default-failure]]：只测缝的话，接线变异照样绿）。
17. **闪烁计时用 Core 的时钟**：`BlinkTick(ANowMs)` 受保护，计时器回调传 `Core.Clock` 或 `TyTermDefaultClock`；测试直接喂时间。
18. **键盘夹具的美式布局表只有一份真源**：在 `keyboard-cases.js` 里；Pascal 的 `TyTerminalKeyEventFromLCL` 查的表由测试逐项对夹具比，不是循环论证（比的是两边的表一致 + 移植的函数一致）。
19. **`_isThirdLevelShift` 的基准**：先试在 node 里用 `CoreBrowserTerminal.prototype._isThirdLevelShift.call({options:{macOptionIsMeta}}, browser, ev)` 调上游；`out/browser/CoreBrowserTerminal.js` 在 node 里加载不了（顶层碰 DOM）就改成照 `:937-948` 逐条写的输入 / 期望表，注明「没有基准」。
20. **浅底 16 色的算法**：用上游 `rgba.ensureContrastRatio(白, Tango[i], 4.5)`（`xterm:src/common/Color.ts:296-321`，前景比底暗时按 0.9 倍逐步缩放 RGB，色相不变），1–6、9–14 算，0 / 7 / 8 / 15 照 Tango。脚本 `tools/terminal-oracle/light-palette.js`，带 `--check` 核对 `light.tycss` 里的值。它就是 5 期 `MinimumContrastRatio` 要移植的同一个函数，先在这里用上。
21. **设计期预览**：每次网格变了就 `WriteSync(RIS + 预览字节)`，预览字节是单元里的常量（16 色前景 / 背景各一行、粗体、斜体、下划线五种、删除线、反显、中文、制表符框线），不进流式化。
22. **published 默认值守卫**：本控件自己的测试用 RTTI 遍历全部 published 序数属性，逐个比 `Default` 和新建实例的值（全局守卫只查 `TabStop`，核实记录 17）。

---

## 需要改共享文件的地方

**结论：本期不需要改 `Base.pas`、`Painter.pas`，也不需要改 `StyleModel.pas`。** 列出三处「看起来要改」的地方和绕开的办法，执行时照做；若绕不开，停下交主控，主控先问用户。

| 看起来要改 | 为什么 | 本期怎么做 |
|---|---|---|
| `Painter.pas` 的 `TyConfigureTextFont` 不设斜体（`:1189` 只设粗体） | 终端要斜体字形 | 字形光栅器调完 `TyConfigureTextFont` 后自己 `ABmp.FontStyle := ABmp.FontStyle + [fsItalic]`（spec §10.3 原文就是这个做法） |
| `Painter.pas` 没有逐字形字体回退 | CJK / 表情可能缺字或被截 | 控件层的宽字体（开工前问题二第 4 条），不动绘制层 |
| `StyleModel.pas` 的 `font-family` 不求值 `var()` | token 化的字体族 | 控件读 `RawVar`（开工前问题二第 6 条） |
| `Base.pas` 的 `FOvrCache` 私有 | 要知道 StyleOverride 里写没写字体 | 控件自己调 `model.ResolveOverride`（核实记录 7） |

---

## 接口清单（全计划用这一套名字）

和 spec 不同的地方标 ★，收尾写回。

### `source/tyControls.Terminal.Keyboard.pas`（新，Task 2）

```pascal
type
  { KeyboardEvent 的四个修饰键 + keyCode + key + code（Types.ts:55-65）；Key / Code 是浏览器语义，UTF-8 }
  TTyTerminalKeyEvent = record
    KeyCode: Word;
    Key, Code: string;
    Shift, Ctrl, Alt, Meta: Boolean;
    AltGraph: Boolean;                    { ★ getModifierState('AltGraph')；LCL ssAltGr }
  end;
  { 序号 = 上游 KeyboardResultType（Types.ts:71-76）：SEND_KEY 0、SELECT_ALL 1、PAGE_UP 2、PAGE_DOWN 3 }
  TTyTerminalKeyResultKind = (tkrSendKey, tkrSelectAll, tkrPageUp, tkrPageDown);
  TTyTerminalKeyResult = record
    Kind: TTyTerminalKeyResultKind;
    Cancel: Boolean;
    Key: RawByteString;                   { '' = 上游 undefined，不发 }
  end;

{ VK + Shift 查美式布局表填 Key / Code（表见 Task 1 的词表，与 keyboard-cases.js 同一份） }
function TyTerminalKeyEventFromLCL(AKey: Word; AShift: TShiftState): TTyTerminalKeyEvent;
{ evaluateKeyboardEvent，Keyboard.ts:38-380，逐分支移植 }
function TyTerminalEvaluateKey(const AEvent: TTyTerminalKeyEvent; AApplicationCursor, AIsMac,
  AMacOptionIsMeta: Boolean): TTyTerminalKeyResult;
{ _isThirdLevelShift，CoreBrowserTerminal.ts:937-948 ★ 三项全有；AKeyPress = False 时另要 KeyCode = 0 或 > 47 }
function TyTerminalIsThirdLevelShift(const AEvent: TTyTerminalKeyEvent; AIsMac, AIsWindows,
  AMacOptionIsMeta, AKeyPress: Boolean): Boolean;
{ prepareTextForTerminal + bracketTextForPaste，Clipboard.ts:13-29；结果 UTF-8 }
function TyTerminalPrepareTextForPaste(const AText: string; ABracketed: Boolean): RawByteString;

const
  TyTerminalIsMac = {$IFDEF DARWIN}True{$ELSE}False{$ENDIF};         { 平台，不是 widgetset }
  TyTerminalIsWindows = {$IFDEF MSWINDOWS}True{$ELSE}False{$ENDIF};
```

依赖只有 `SysUtils`、`Classes`（`TShiftState`）、`LCLType`（`VK_*`）——不引 `Forms` / `Controls`。

### `source/tyControls.Terminal.Render.pas`（新 ★，Task 5–6）

```pascal
type
  TTyTermFontKind = (tfkMain, tfkWide);
  { 设备像素；所有长度都已按 PPI 缩放 }
  TTyTermCellMetrics = record
    CellW, CellH: Integer;          { 格子（含字间距、行高倍数） }
    CharW, CharH: Integer;          { 字形区（不含字间距 / 多出来的行高） }
    TextTop: Integer;               { 字形框相对格子顶的偏移（行高多出来的一半） }
    Baseline: Integer;              { 相对格子顶 }
    LineW: Integer;                 { 下划线 / 删除线 / 光标轮廓线宽，≥ 1 }
    UnderlineY, StrikeY, OverlineY: Integer;   { 相对格子顶 }
  end;
  TTyTermFontSpec = record          { 度量与字形缓存的键 }
    MainName, WideName: string;     { WideName = '' → 宽簇也用 MainName }
    SizeLogical, PPI, LetterSpacingLogical, LineHeightPercent: Integer;
  end;
  TTyTermColorResolver = function(AIndex: Integer): Cardinal of object;   { 0..258 → $RRGGBB；= Core.ResolveColor }
  TTyTermCellColors = record Fg, Bg, Underline: Cardinal; Dim, Invisible: Boolean; end;

function TyTermMeasureCell(const ASpec: TTyTermFontSpec): TTyTermCellMetrics;
{ 16..255 = Types.ts:205-227 的立方 + 灰阶；0..15 = Tango（只给测试和没有主题时用） }
function TyTermDefaultPaletteColor(AIndex: Integer): Cardinal;
{ DomRendererRowFactory.ts:342-460 的颜色部分（核实记录 13）；纯函数 }
function TyTermResolveCellColors(AFg, ABg: Cardinal; const AExt: TTyTerminalExtAttrs;
  AResolve: TTyTermColorResolver; ADrawBoldBright: Boolean): TTyTermCellColors;
function TyTermIsCustomGlyph(ACodepoint: Cardinal): Boolean;    { 3 期：U+2500–259F }

type
  TTyTermGlyphKey = record Text: string; Bold, Italic: Boolean; Cells: Integer; Font: TTyTermFontKind; end;
  TTyTermGlyph = class               { 8 位覆盖率遮罩 + 相对格子左上角的偏移 }
    Mask: TGrayscaleMask; OffsetX, OffsetY: Integer;
  end;
  TTyTermGlyphCache = class          { 容量 4096，最近最少使用淘汰（spec §10.4）}
    constructor Create(ACapacity: Integer = 4096);
    function Find(const AKey: TTyTermGlyphKey): TTyTermGlyph;   { nil = 没有；命中计数 }
    procedure Add(const AKey: TTyTermGlyphKey; AGlyph: TTyTermGlyph);   { 拿走所有权 }
    procedure Clear;
    property Count, Hits, Misses: Integer;        { FOR THE TESTS 也给探针用 }
  end;
  TTyTermGlyphRasterizer = class     { 按 E2 定下的做法把一个簇画成遮罩 }
    function Rasterize(const AKey: TTyTermGlyphKey; const ASpec: TTyTermFontSpec;
      const AMetrics: TTyTermCellMetrics): TTyTermGlyph;
  end;
  { 自绘：CustomGlyphRasterizer.ts 的三种类型；数据在 CustomGlyphs.inc }
procedure TyTermDrawCustomGlyph(ABmp: TBGRABitmap; const ACellRect: TRect; ACodepoint: Cardinal;
  AColor: TBGRAPixel; const AMetrics: TTyTermCellMetrics; APPI: Integer);

type
  TTyTermCursorShape = (tcpNone, tcpBlock, tcpOutline, tcpUnderline, tcpBar);   { tcp：别和控件的 tcs* 撞名 }
  TTyTermRowPainter = class          { 一行：底色 → 字形 → 线 → 光标（spec §10.1 的顺序） }
    { 属性：Metrics、Spec、Resolver、GlyphCache、Rasterizer、DrawBoldBright、CursorColor、
      CursorInk、CursorWidthPx（竖线宽） }
    procedure PaintRow(ABmp: TBGRABitmap; AX, AY: Integer; ALine: TTyTerminalLine; ACols: Integer;
      ACursorCol: Integer; ACursorShape: TTyTermCursorShape);     { ACursorCol = -1 没有光标 }
  end;
```

### `source/tyControls.Terminal.pas`（新，Task 7–14）

```pascal
type
  TTyTerminalCursorStyle = (tcsBlock, tcsUnderline, tcsBar);        { → Core.CursorStyle 的 tco* }
  TTyTerminalCursorInactiveStyle = (tcisOutline, tcisBlock, tcisBar, tcisUnderline, tcisNone);
  TTyTerminalGridResizeEvent = procedure(Sender: TObject; ACols, ARows: Integer) of object;
  TTyTerminalShortcutQueryEvent = procedure(Sender: TObject; Key: Word; Shift: TShiftState;
    var APassToApplication: Boolean) of object;

  TTyTerminalView = class(TTyCustomControl, ITyImeEditable, ITyScrollBarFrameHost)
  { ITyTextEditActions 4 期 }
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Write(const AData: RawByteString; AOnDone: TTyTerminalWriteDone = nil; ATag: PtrInt = 0); overload;
    procedure Write(const ABuf; ACount: Integer; AOnDone: TTyTerminalWriteDone = nil; ATag: PtrInt = 0); overload;
    procedure WriteSync(const AData: RawByteString);
    procedure Paste(const AText: string);          { 粘贴编码 → Core.Input(…, True) }
    procedure Input(const AText: string);          { 当作键入 }
    procedure Clear;                               { Core.ClearScrollback }
    procedure Reset;                               { Core.Reset + 整屏重画 }
    procedure ScrollLines(ADelta: Integer); procedure ScrollPages(APages: Integer);
    procedure ScrollToTop; procedure ScrollToBottom;
    procedure PasteFromClipboard;
    function CellAt(X, Y: Integer): TPoint;        { 客户区设备像素 → 0 起的格子，钳在网格内 }
    function CellRect(ACol, ARow: Integer): TRect; { 视口行 }
    function SizeForGrid(ACols, ARows: Integer): TSize;   { ★ 客户区要多大 }
    property Core: TTyTerminalCore read FCore;
    property Cols: Integer; property Rows: Integer; property Title: string;
  published
    property Scrollback: Integer default 1000;
    property CursorStyle: TTyTerminalCursorStyle default tcsBlock;
    property CursorInactiveStyle: TTyTerminalCursorInactiveStyle default tcisOutline;
    property CursorBlink: Boolean default False;
    property AmbiguousWide: Boolean default False;
    property UnicodeVersion: TTyUnicodeVersion default tuv11;
    property MacOptionIsMeta: Boolean default False;
    property AlternateScroll: Boolean default True;
    property DrawBoldTextInBrightColors: Boolean default True;
    property ReadOnly: Boolean default False;
    property ConvertEol: Boolean default False;
    property TabStopWidth: Integer default 8;
    property ScrollOnUserInput: Boolean default True;
    property ScrollBarAutoHide: TTyScrollBarAutoHide default sbahDefault;
    property LineHeightPercent: Integer default 100;
    property LetterSpacing: Integer default 0;
    property TabStop default True;
    { Align, Anchors, BorderSpacing, Constraints, Enabled, TabOrder, PopupMenu, Hint, ShowHint,
      StyleClass, StyleOverride, Controller, Font, ParentFont；OnEnter / OnExit / OnKeyDown /
      OnKeyUp / OnUTF8KeyPress / OnClick / OnMouse* 照 TTyMemo 的 published 列表 }
    property OnData: TTyTerminalDataEvent;
    property OnGridResize: TTyTerminalGridResizeEvent;
    property OnTitleChange: TTyTerminalTextEvent;
    property OnBell: TNotifyEvent;
    property OnOsc: TTyTerminalOscEvent;          { ★ 无 AHandled }
    property OnShortcutQuery: TTyTerminalShortcutQueryEvent;
  protected
    function ReadClipboardText: string; virtual;       { 照 Edit.pas:260-261 }
    procedure WriteClipboardText(const S: string); virtual;
    procedure ScheduleSlice; virtual;                  { ★ 默认 Application.QueueAsyncCall }
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure BlinkTick(ANowMs: Double);               { ★ 计时器回调转这里 }
    { FOR THE TESTS：RowsPainted（累计画过的行数）、GlyphCache、SurfaceBitmap、
      Metrics、PendingSyncRows }
  end;
```

**控件接管的 Core 事件**（宿主**不要**改写这些，控件文档写明）：`OnData`、`OnRefreshRows`、`OnTitleChange`、`OnBell`、`OnCursorMove`、`OnScroll`、`OnBufferActivate`、`OnModesChange`、`OnOsc`、`OnQueryBaseColor`、`OnRequestScrollToBottom`、`OnProcessRequest`、`OnWindowOptionsReport`、`OnResize`、`OnScrollbackCleared`。宿主可以自己挂的：`OnIconNameChange`、`OnLineFeed`；也可以 `Core.Parser.Register*Handler`。

---

## 文件清单

| 文件 | 本期做什么 |
|---|---|
| `tools/terminal-fontprobe/fontprobe.lpr`、`fontprobe.lpi`、`.gitignore` | **新建**（Task 0）。E1 / E2 探针，不进包；照 `tools/terminal-probe/terminalprobe.lpi` 用 `OtherUnitFiles = ../../source` |
| `tools/terminal-oracle/lib-dump.js` | 改（Task 1、4）。`PORTED` 加 `common/input/Keyboard`、`browser/Clipboard`、`browser/Types`、`addons/addon-webgl/src/customGlyphs/CustomGlyphDefinitions`（+ `CoreBrowserTerminal`，若 Task 1 能加载）；`GENERATED` 加新生成物 |
| `tools/terminal-oracle/keyboard-cases.js`、`cases/keyboard.js` | **新建**（Task 1） |
| `tools/terminal-oracle/gen-terminal-glyphs.js` | **新建**（Task 4） |
| `tools/terminal-oracle/view-cases.js` | **新建**（Task 4）。dump 上游 256 色表 |
| `tools/terminal-oracle/light-palette.js` | **新建**（Task 15） |
| `tools/terminal-oracle/regen-all.js` | 改（Task 1、4）。`SCRIPTS` 追加 |
| `tests/fixtures/terminal-keyboard*.json`、`terminal-paste.json`、`terminal-view-palette.json` | **生成** |
| `source/tyControls.Terminal.Keyboard.pas` | **新建**（Task 2） |
| `source/tyControls.Terminal.CustomGlyphs.inc` | **生成**（Task 4），不进 `.lpk` |
| `source/tyControls.Terminal.Render.pas` | **新建**（Task 5） |
| `source/tyControls.Terminal.pas` | **新建**（Task 7–8、11–13） |
| `tycontrols.lpk` | `<Files>` 末尾依次加三个单元（Task 2、5、7） |
| `tests/test.terminal.keyboard.pas` | **新建**（Task 3） |
| `tests/test.terminal.render.pas` | **新建**（Task 6） |
| `tests/test.terminal.view.pas`、`test.terminal.view.paint.pas` | **新建**（Task 9、10） |
| `tests/test.terminal.view.input.pas` | **新建**（Task 14） |
| `tests/test.terminal.view.theme.pas` | **新建**（Task 15） |
| `tests/tytests.lpr` | uses 加上面六个测试单元 |
| `themes/light.tycss`、`source/tyControls.DefaultTheme.pas`、`source/tyControls.Css.Catalog.pas`、`source/tyControls.DensityPack.pas` | 改 / 重新生成（Task 15） |
| `tests/test.themes.pas`、`tests/golden/*.golden.txt`、`tests/test.defaulttheme.pas` | 改（Task 15） |
| `designtime/tyControls.Design.pas`、`tools/genicons/genicons.lpr`、`scripts/gen-icons.ps1`、`designtime/icons/TTyTerminalView*.png`、`designtime/tycontrols_icons.lrs` | 改 / 生成（Task 16；生成【主控执行】） |
| `tests/test.version.pas`、`tests/test.focus.tabstop.pas` | 改（Task 16） |
| `examples/terminal/*` | **新建**（Task 17） |
| `docs/controls/terminal.md`、`docs/controls/README.md`、`README.md`、`README.en.md` | 新建 / 改（Task 18） |
| `THIRD-PARTY-NOTICES.md`、`tests/test.release.pas` | 改（Task 18） |
| `docs/superpowers/specs/2026-09-28-terminal-view-design.md` | 只在 Task 20 写回 |

**不碰**：`source/tyControls.Base.pas`、`source/tyControls.Painter.pas`、`source/tyControls.StyleModel.pas`、Core / Buffer / Parser / Unicode.Width 四个单元（发现 Core 的 bug 另开 `fix(terminal)` 提交并写明，不顺手改）、`source/tyControls.StrConsts.pas`、`languages/`（本期控件没有用户可见字符串）、`CHANGELOG*`、`D:/Projects/xterm.js` 下任何受版本控制的文件。

---

## 实现期的地雷（每个任务开工前看一眼）

1. **只经 `lib-dump.js` 加载上游**，新移植的 `.ts` 进 `PORTED`（过期构建检查），否则切过 commit 没重编的 `out/` 会静默给旧答案。
2. **CRLF 与反斜杠**：含 `\x1b`、`\u` 的 JS 一律用 Write 工具落文件（[[bash-heredoc-eats-backslashes]]）；改 `.pas` 用编辑工具，不用 Git Bash 的 `sed -i`（[[git-bash-sed-strips-crlf]]）；期末变异先 `git diff --stat` 确认改到了（[[crlf-mutation-phantom-survivor]]）。
3. **FPC 的 `{ }` 注释会嵌套**（[[fpc-brace-comments-nest]]）：注释里别写 JSON、别写 `{}`；生成的 `.inc` 由脚本断言没有花括号。
4. **键盘的两个坑**（核实记录 10）：能出字符的键在 `KeyDown` 里不清零（否则 Win32 丢字符）；`FKeyDownHandled` 由控件自己记，`UTF8KeyPress` 见到就丢、清掉。`UTF8KeyPress` 开头先调 `TyImeTakeCommit`（GTK3 的截断绕行，`Edit.pas:2210`）。
5. **不在 `Paint` 里改网格**（开工前问题二第 13 条）：`RenderTo` 只读状态、画；需要改尺寸时记下来、`QueueAsyncCall` 一次。
6. **列数不随滚动条显隐变**（开工前问题一第 2 条）：网格宽 = 客户区 − 内边距 − **条宽（恒扣）**。
7. **事件是同步的、在解析中间发**（2 期签收交接）：Core 事件处理里调 `Core.Resize` / `Reset` / `WriteSync` 会被延后；控件别假设调用返回时已经生效——改尺寸后以 `Core.OnResize` 为准刷新自己的状态，不以「刚才传进去的数」为准。
8. **异步调用和计时器的生命周期**：析构第一步 `Application.RemoveAsyncCalls(Self)`，停掉并释放闪烁 / 同步输出两个计时器，再把 Core 的事件全部置 nil、释放 Core。设计期（`csDesigning`）不建计时器、不建滚动条、不排片（设计期用 `WriteSync`）。
9. **无头像素测试三件套**（[[headless-render-needs-sentinel-ground]]）：哨兵底色（品红 `BGRA(255,0,255,255)`）+ 真父窗体 + 自建 `TTyStyleController`（钉 `ThemeName` / `Mode`，`TearDown` 释放）。字体相关只数「有没有墨」和格子边界，不比字形像素；颜色断言用自绘的 U+2588 █（整格纯色，不受抗锯齿影响）。先打包围盒再写断言（同一条记忆的「探针量的那个量」一节）。
10. **单跑绿 / 全量红** 先 `lazbuild -B` 重编（[[canary-then-rebuild]]），再查是否读了进程级状态（`TyDefaultController`、`TyFallbackFontName`、`Forms.Application` 是否初始化，[[suite-order-widgetset-init]]）。
11. **JS 的数不是 Pascal 的**：`Math.round` 是「.5 向正无穷」（用 `Floor(x + 0.5)`）；上游 `>>` 有符号；颜色一律 `Cardinal` `$RRGGBB`，和 `TBGRAPixel` / `TTyColor` 之间只在一处换算（`Render` 单元的 `TyTermRgbToPixel`）。
12. **新单元进 `.lpk`、新测试单元进 `tytests.lpr` 的 uses**（[[new-unit-missing-from-lpk]]；`EveryUnitOnDiskIsListedInItsPackage`、`EveryTestUnitThatRegistersTestsIsLinked` 守着）；`.inc` 不进 `.lpk`。
13. **published default = 构造值**（[[tabstop-declared-default-must-match]]）；构造里设的值和 `default` 子句逐个对（开工前问题二第 22 条的守卫）。
14. **不往 published 字段写派生状态**（[[loaded-sync-clobbers-streamed-values]]）：属性 setter 转给 Core 的，`Loaded` 里不要从 Core 读回来覆盖。
15. **视觉值走主题 token**（[[theme-customizability-principle]]）：颜色、内边距、光标竖线宽、下划线宽都来自 token；代码里只有「token 缺失时的兜底」。
16. **窗口化的内嵌滚动条贴宿主边**（[[windowed-child-at-host-edge-repaints-frame]]）：照 Memo 实现 `ITyScrollBarFrameHost`，别把条缩进去躲边框。
17. **`SetBounds` 原样再设是空操作**（[[lcl-setbounds-same-rect-noop]]）：示例「按录制尺寸」要传算好的新尺寸。
18. **示例规矩**（[[examples-must-be-lfm-titlebar-skin]]、[[demo-edits-lfm-not-code]]）：`.lfm` + 真 `TTyTitleBar` + 运行时换肤 / 明暗；能写进 `.lfm` 的设置不写进代码；自绘 UI 里不用裸 LCL 控件（[[no-native-controls-in-ui]]）；按钮 `AutoSize`（[[skin-variance-breaks-fixed-widths]]）。

---

## 跑测试的固定套路（每段末只跑本段；Task 20 跑全量）

改了 `source/` 之后**必须** `lazbuild -B`（[[example-stale-lib-on-source-change]]、[[canary-then-rebuild]]）。exe 用唯一名 `tytests-term.exe`。

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi > /tmp/term-build.txt 2>&1 || { tail -30 /tmp/term-build.txt; false; } && cd tests && cp tytests.exe tytests-term.exe && for s in $SUITES; do ./tytests-term.exe --suite=$s --format=plain > /tmp/term-$s.txt 2>&1; printf '%s: ' $s; grep -E "Number of (run tests|errors|failures)" /tmp/term-$s.txt | tr '\n' ' '; echo; done
```

各段的 `SUITES`：

| 段 | 编译时机 | `SUITES` |
|---|---|---|
| 3a | Task 3 之后 | `TTyTerminalKeyboardOracleTests TTyTerminalKeyboardTests TReleaseManifestTest` |
| 3b | Task 10 之后 | 上一行 + `TTyTerminalRenderTests TTyTerminalViewTests TTyTerminalViewPaintTests` |
| 3c | Task 14 之后 | 上一行 + `TTyTerminalViewInputTests` |
| 3d | Task 19 之后 | 上一行 + `TTyTerminalViewThemeTests TTestThemes TTestThemeGolden TBuiltinThemeTest TCssCatalogTest TPaletteIconTest TTyFocusTabStopTest TVersionTest TTyMeasureFontDpiTest TI18NTest` |

**判据是每个 suite 那一行都有 `Number of run tests`、errors / failures 为 0**，不是 exit code。某一行为空 = 跑丢了（或 suite 名写错），重跑，别读成通过。每段只修本段的红，**不跑全量、不做变异、不汇报**。

全量（Task 20，输出必须重定向到文件，[[known-rare-suite-flake]]）：

```bash
cd /d/Projects/ty-3.1/tests && ./tytests-term.exe --all --format=plain > /tmp/term-all.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/term-all.txt
```

node 侧：`cd /d/Projects/ty-3.1 && node tools/terminal-oracle/regen-all.js --expect-clean`（先把工作区提交干净）。

## 关于判据和变异

- 纯函数给**输入 / 期望表**；夹具比较和像素、事件测试写**判据**（比什么、怎么数、失败打印什么），测试代码执行时现写。
- 每条判据写明「**在哪个变异下必须红**」；各任务的变异表期末集中做（Task 20 Step 6）：改一行 → `git diff --stat` 确认改到了 → `lazbuild -B` → 跑相关 suite → **必须红** → 改回 → 重编重跑 → 绿。没红的先查改没改对地方、再查是不是「这条路走不到」（[[headless-render-needs-sentinel-ground]] 第 3 条）；确实没红，当场补测试，签收记录写一句。
- 接线类变异（事件没转发、`Invalidate` 没调、计时器没建、`ScheduleSlice` 没调）每类至少一条（[[built-not-wired-is-the-default-failure]]）。
- 所有夹具测试结尾断言比较次数 `> 0` 且等于从夹具算出的应比次数（[[assertion-never-varies-the-thing]]）。
- 标「等价」的变异不做，理由写在表里。会死循环的变异不做；卡住时按进程号结束 `tytests-term.exe`，**禁用 `taskkill -im`**（[[parallel-agent-worktree-hazards]]）。

---

### Task 0: 基线、合并、开工前实验 E1 / E2

**Files:**
- Create: `tools/terminal-fontprobe/fontprobe.lpr`、`tools/terminal-fontprobe/fontprobe.lpi`
- Modify: 本计划的「实验记录」一节

- [ ] **Step 1: 确认起点**

```bash
cd /d/Projects/ty-3.1 && git status --short && git branch --show-current && git log --oneline -1
```

Expected：工作区干净，分支 `feat/terminal`，HEAD 是本计划的提交或其后。

- [ ] **Step 2: 【主控执行，看开工前问题二第 1 条】合并 main**

```bash
cd /d/Projects/ty-3.1 && git merge --no-edit main && git log --oneline -3 && grep -n "TTyGdiTextRenderer" source/tyControls.Painter.pas | head -2
```

Expected：合并成功（冲突就停下处理，不 rebase、不 reset）；`Painter.pas` 里有 `TTyGdiTextRenderer`。

- [ ] **Step 3: 基线编译并跑全量**（实现 agent 做）

用「跑测试的固定套路」的全量命令（先 `lazbuild -B tests/tytests.lpi`、拷成 `tytests-term.exe`）。条数记进草稿，Task 20 签收时写进本计划末尾。**有红就停**。

- [ ] **Step 4: 写探针 `tools/terminal-fontprobe`**

LCL 程序（`.lpi` 照 `tools/terminal-probe/terminalprobe.lpi`：`OtherUnitFiles = ../../source`，依赖 `LCL`、`BGRABitmapPack`，关掉「Win32 GUI 程序」让它能往 stdout 打），不建窗口，只建位图。参数：`--e1`、`--e2`、`--out <目录>`（PNG 输出目录，默认当前目录下 `fontprobe-out`，**不进 git**；探针目录的 `.gitignore` 忽略它和 `lib/`、`*.exe`）。开头 `TyFallbackFontName := 'Segoe UI'`（Win）/ 平台等价物，避免 [[empty-fontname-gotcha]]。

**E1**（字体回退）：主字体取平台等宽字体（Windows `Consolas`、Linux `Monospace`、macOS `Menlo`），四种配置：9pt / 12pt × 96 / 144 PPI。每种配置：
1. 度量：`TyConfigureTextFont` 后读 `FontPixelMetric`（`Baseline`、`DescentLine`、`Lineheight`，`bgra:bgrabitmaptypes.pas:412-425`）、`TextSize('Ag').cy`、`TextSize('中').cy`、32 个 `W` 的宽度 / 32（格宽，spec §10.2）。
2. 样例簇：`W`、`g`、`|`；`中`、`文`、`あ`、`한`、U+20000；😀、👍🏽（U+1F44D U+1F3FD）、🇨🇳（区旗对）；`─`、`│`、`┼`、`█`（只记录，本期自绘）；U+E0B0、U+E0A0（Powerline）；`e` + U+0301；**缺字参照**：U+10FFFD（16 平面私用区）、U+0378（未分配）。
3. 每个簇画在一张四周各留 1 个格高余量的白底位图上（黑字），量：前进宽度（`TextSize.cx`）；墨迹包围盒（非白像素）；**缺字** = 与缺字参照的位图逐像素相同，或没有墨；**彩色** = 有像素 `max(R,G,B) − min(R,G,B) > 40`；**被截** = 墨迹底边落在「文字框顶 + `TextSize.cy`」那一行上或其下一行（BGRA 按 `TextExtent + 1` 定遮罩高，[[bgra-small-text-blur-linux]] UPDATE-2），或同一个字形用专门的 CJK 字体画时墨迹底边低 ≥ 15% 格高。
4. 同一批 CJK / 表情用候选宽字体（Windows `Microsoft YaHei`、Linux `Noto Sans CJK SC`、macOS `PingFang SC`）再量一遍。
5. 打印表格：每行一个「配置 × 簇 × 字体」，列 = 前进宽度（以格宽为单位，两位小数）、墨迹框（相对格子）、缺字、彩色、被截；PNG 每配置一张拼图。

**E2**（字形遮罩），只在 9pt Consolas、96 与 144 PPI 下量：
- 三种做法：
  - （a）`TyConfigureTextFont(…, PPI × 3)`、3× 画、`Resample` 到 1×（照 `Painter.pas` 的 `DrawTextSupersampled`），灰度当覆盖率；
  - （b）库管线直接在已知底色上画前景色（缓存键带前景 + 底色）；
  - （c）库管线 1× 黑字白底，覆盖率 = `255 − 灰度`（通道平均），着色时 `FillMask`（`bgra:bgradefaultbitmap.pas:556`，遮罩类 `TGrayscaleMask`，`bgra:bgragrayscalemask.pas:55`）。
- **画质**：参照 = `TTyPainter.DrawText` 在同一底色、同一前景下画同一个字（库里其余文字的样子）。每种做法对参照算「逐通道平均绝对差」和「实心占比」（有墨像素里覆盖率 ≥ 0.9 的比例），前景 / 底色取三组：黑 / 白、白 / `#1e1e1e`、`#cc0000` / `#ffffff`。
- **耗时**（各取 5 次的中位数）：冷填充 95 个 ASCII × 4 种样式（常规、粗、斜、粗斜）= 380 次光栅化；热缓存全屏重画 200 × 60 = 12000 格（只做贴遮罩 + 铺底色，字形都已在缓存）。

- [ ] **Step 5: 在 Win32 上跑 E1、E2**（实现 agent：`lazbuild -B tools/terminal-fontprobe/fontprobe.lpi`，再跑 `fontprobe --e1` 与 `--e2`）

- [ ] **Step 6: 【主控执行，可选】在 Windows 的 Qt6 上跑 E1**（`lazbuild -B --ws=qt6 …`，本机 Qt6 运行库齐了才做；不齐就记「待真机」）。GTK2、Linux Qt6、Cocoa 一律进「真机验收项汇总」第 1 项。

- [ ] **Step 7: 按判据定路线，写进下面「实验记录」**

**E1 判据与后续：**

| 结果（每个 widgetset 分别判） | 后续 |
|---|---|
| CJK 有字形、前进宽度在 1.5–2.5 格、不被截 | 该平台 `--terminal-font-family-wide` 的默认关键字 `monospace-wide` 换成**空串**（交给系统替换） |
| CJK 缺字，或被截 | `monospace-wide` 换成该平台候选宽字体（Step 4 第 4 条；候选字体本身也得过这三条） |
| 表情缺字或只有单色 | 已知限制：控件文档「注意事项」写明，spec §15 保持「彩色表情不做」 |
| `Lineheight` 与 `TextSize('Ag').cy` 不同、或 CJK 墨迹超出 `Lineheight` | 格高仍取 `Lineheight`（spec §10.2），CJK 超出部分按格子裁；把数字记下，Task 5 的度量函数注释里引用 |
| Powerline 缺字 | 只记录，5 期定是否自绘 |

没在真机上跑的平台先按证据定默认：macOS `PingFang SC`（[[bgra-small-text-blur-linux]] UPDATE-2：等宽主字体量出来的遮罩切掉 CJK 下半截，这正是终端显式给了 `Menlo` 后会遇到的）；Linux `Noto Sans CJK SC`（`fqSystemClearType` 同一段遮罩代码，`bgratext.pas:1192-1216`）。两条都进真机验收表。

**E2 判据与后续：**

| 结果 | 后续 |
|---|---|
| （c）对参照的平均绝对差 ≤ 2（每通道 0–255），三组颜色都满足；热缓存全屏 ≤ 16 ms；冷填充 ≤ 380 ms（≤ 1 ms / 个） | **用（c）**，所有平台同一套：遮罩按库管线 1× 取，Linux / macOS 不另做超采样（和库里正文一致；库的 `DrawTextSupersampled` 只给小号粗体角标） |
| （c）画质达标、热缓存超时 | 路线不变，瓶颈在贴遮罩：Task 5 把 `FillMask` 换成自己的逐行混合循环，再量 |
| （c）画质达标、冷填充超时 | 路线不变（只在第一次付），记数字；超过 5 ms / 个再议 |
| （c）和参照差得多（> 2） | 先查原因（覆盖率提取、伽马、`TTyGdiTextRenderer` 是否按「覆盖率 × 墨色」混合）；查不清就用（b），缓存键加前景 + 底色，容量仍 4096 |
| （a）只作记录 | （a）在 Win32 上的实心占比预期远低于参照（UPDATE-3 的「两个灰像素」），不选 |

- [ ] **Step 8: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-fontprobe/fontprobe.lpr tools/terminal-fontprobe/fontprobe.lpi tools/terminal-fontprobe/.gitignore docs/superpowers/plans/2026-09-29-terminal-phase-3.md && git commit -m "test(terminal): font probe for the fallback and glyph-mask experiments

Measures, per font setting, the cell metrics and whether CJK, emoji and
Powerline glyphs render, how wide, and whether they are cut; then three
ways of caching a glyph as a mask against the library's own text. The
results and the rendering route they chose are in the phase 3 plan.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### 实验记录（Task 0 Step 7 填）

- 合并：主控把 main 合进 `feat/terminal`（`3c86b8c7`，含 `b23893ba` Win32 ClearType 文字管线），无冲突。期末审查修复前全量 8133 条（2 条与本期无关的红：本机环境下的 ClearType 墨量测试、当时还没生成图标的 `TPaletteIconTest`）。
- E1（Win32，`fontprobe --e1`，期末审查修复后重跑，数字不变）：主字体 Consolas，候选宽字体 Microsoft YaHei。

  | 配置 | 度量（基线 / 行高 / `TextSize('Ag').cy` / 中文 `cy`） | 格宽 × 格高 | Consolas 画 CJK（中 文 あ） | 한 / U+20000 | 表情（😀、👍🏽、🇨🇳） | 框线 / █ | Powerline E0A0 / E0B0 | YaHei 画同一批 |
  |---|---|---|---|---|---|---|---|---|
  | 9pt@96 | 11 / 14 / 14 / 14 | 7 × 14 | 2.00 格，墨迹在格内 | 1.29 / 1.71 格 | 1.3–1.7 格，单色 | 上下出格 | 缺字 | 1.71 格；U+20000、表情墨迹出格（第 15 行，格高 14） |
  | 9pt@144 | 17 / 22 / 22 / 22 | 10 × 22 | 2.00 格，在格内 | 1.50 / 2.10 | 1.5–1.9，单色 | 上下出格 | 缺字 | 表情出格 |
  | 12pt@96 | 15 / 19 / 19 / 19 | 9 × 19 | 2.00 格，在格内 | 1.33 / 2.00 | 1.4–1.9，单色 | 上下出格 | 缺字 | 表情出格、被截 |
  | 12pt@144 | 23 / 28 / 28 / 28 | 13 × 28 | 2.00 格，在格内 | 1.46 / 2.00 | 1.5–2.0，单色 | 上下出格 | 缺字 | 中文墨迹到最后一行 |

- E1（Qt6 on Windows）：没跑（本机没有 Qt6 运行库），进真机验收第 1 项。
- E1 结论：Windows 上 `monospace-wide` = 空串（Consolas 经系统字体链接把 CJK 画成两格、在格内；YaHei 反而出格）；macOS `PingFang SC`、Linux `Noto Sans CJK SC`（按证据，待真机）。表情单色、Powerline 缺字，都是已知限制。格高 = `Lineheight`，与 `TextSize('Ag').cy`、中文字高相同。
- E2（Win32，`fontprobe --e2`，期末审查修复后重跑）：有墨像素对参照的平均差（每通道 0–255），三组颜色依次是黑 / 白、白 / `#1e1e1e`、`#cc0000` / 白：

  | 做法 | 96 PPI | 144 PPI | 实心占比（黑 / 白；参照 12.4% / 21.0%） |
  |---|---|---|---|
  | （a）3× 超采样 | 39.5 / 34.6 / 28.3 | 44.0 / 38.6 / 31.8 | 0.3% / 8.5% |
  | （b）直接画 | 0.07 / 0.06 / 0.05 | 0.02 / 0.02 / 0.02 | 17.2% / 30.6% |
  | （c）遮罩 + 伽马混合（`FillMask` dmDrawWithTransparency） | 27.0 / 19.3 / 18.1 | 23.8 / 15.8 / 15.9 | 12.0% / 23.6% |
  | （c）遮罩 + 线性混合（`FillMask` dmLinearBlend 或自写循环，结果相同） | 0.43 / 0.28 / 0.32 | 0.36 / 0.19 / 0.27 | 17.2% / 30.6% |

  用时（5 次中位数）：探针自己的（c）冷填充 380 次 575 / 597 ms（每个 1.5 / 1.6 ms）；控件的光栅器冷填充 709 / 712 ms（每个 1.87 ms——多量一次前进宽度；时间花在库的 Win32 文字渲染器每次新建 `TBitmap` 再转换）；热缓存 200 × 60 整屏：`FillMask` 20.0 / 32.3 ms，自写循环 7.6 / 13.9 ms，控件的行绘制器（真行、底色、查缓存、着色，不贴）10.1 / 16.4 ms，满屏 tmux 框线同样 10.0 / 16.4 ms。控件里连贴图（常驻 DIB 上只计 `RenderTo`，96 PPI）：ASCII 11.8 ms、tmux 框线 11.8 ms、mc 双线框 + 阴影 12.0 ms（修复前 10.4 / 2550 / 5348 ms）；冷填充 380 个字形在控件里按帧摊开，约 900 ms、68 帧。
- E2 结论：遮罩做法选（c），着色用和 `TTyGdiTextRenderer` 同一个非伽马混合（自写循环）；所有平台同一套，不另做超采样。热缓存整屏在 96 PPI 下 ≤ 16 ms 达标；冷填充每个 1.87 ms 超过 1 ms 的判据但低于 5 ms，记数字，靠每帧光栅化预算不卡帧；要再快得改库的 Win32 文字渲染器（`Painter.pas`，共享文件），交主控。

---

### Task 20: 收尾——编译、全量、按 spec 逐条核、集中变异、主控编包与截图、审查、写回 spec、签收

**Files:**
- Modify: 本计划（签收记录）、`docs/superpowers/specs/2026-09-28-terminal-view-design.md`（写回）
- 修复时按需改 Task 1–19 的文件

- [x] **Step 1: 一次编译 + 本期全部 suite + 全量**

「跑测试的固定套路」3d 行的 `SUITES` 和全量命令。Expected：本期 suite 全 0 / 0；全量 errors / failures 为 0、总数 = Task 0 基线 + 本期新增。红了集中修：分清是移植错、夹具错还是控件错——键盘**以上游为准**；修复提交 `fix(terminal): ...`，一个问题一个提交。全量红而单跑绿，按地雷 10 排查。

- [x] **Step 2: 重跑生成，确认可复现**

```bash
cd /d/Projects/ty-3.1 && node tools/terminal-oracle/regen-all.js --expect-clean && node tools/terminal-oracle/light-palette.js --check
```

Expected：`clean`；`light.tycss` 的浅底 16 色与脚本算出的相同。

- [x] **Step 3: 规模与用时记录**：新夹具的字节数与用例数；本期各 suite 用时；E2 的数字在真控件上再量一次（探针 `--e2` 之外，用 `TTyTerminalViewPaintTests` 里的热缓存用例打印用时，只打印不断言）。

- [x] **Step 4: 按 spec 逐条核代码，不看测试**（[[green-tests-are-not-spec-conformance]]、[[built-not-wired-is-the-default-failure]]）

逐条记「在哪一行实现 / 为什么不需要 / 挪到几期」：
- §2.1：三个新单元的依赖方向（Keyboard 不引 Forms；Render 不引控件；控件引全部）、进运行时包、两个 `.inc` 不进清单。
- §3.1 / §3.2：`OnProcessRequest` → `ScheduleSlice` → `ProcessPending` 返回 True 再排；同步输出攒行、1 秒超时从第一次攒行起、调 `EndSynchronizedOutput`；只 `Invalidate` 脏行矩形。
- §7.2 / §7.3（控件那一半）：建好就 `ReportFocus(False)`，`DoEnter` / `DoExit` 照报；`OnQueryBaseColor` 答 0..258；换主题调 `NotifyColorSchemeChanged`；14t / 16t 应答；`OnScrollbackCleared`、`OnResize` → `OnGridResize`。
- §8：接口清单每一项；美式布局表与夹具同一份；第三层 Shift 三项；粘贴编码。
- §9.1–§9.4、§9.7、§9.9、§9.10（本期部分）：published 表逐项（名字、类型、默认值、转给 Core 的那几个）；§9.2 本期六个事件；§9.3 本期方法；键盘顺序与吞键、放行、复制粘贴快捷键、本地翻页、`ScrollOnUserInput`；滚动条（`Max` = 最大位置、备用屏禁用、宽度恒扣）；输入法；焦点、闪烁 600ms 与 5 分钟停闪、设计期。
- §9.5.3 / §9.5.4（本期部分）：竖向滚轮三种去向。
- §10.1–§10.8：表面位图与 `DrawPart`、度量、字体来源与 `monospace` / `monospace-wide`、字形缓存键 / 容量 / 清空时机、自绘两段、属性表逐行、光标、DPI。
- §11：键、token、`:focus`、`on()` 一处写、生成器、GGRID / GMETRICS、跨主题测试。
- §12.1：回放、速度、单步、暂停、键码面板、本地回显、换肤明暗、菜单项（本期那几项）。
- §13.6：像素、事件、调度三类都有。
- §14：新单元头、`CustomGlyphs.inc` 头、notices。
- 2 期交接九条、1 期遗留两条文档项逐条对上。

- [x] **Step 5: 【主控执行】编包、编示例、截图**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tycontrols.lpk > /tmp/term-pkg.txt 2>&1; tail -3 /tmp/term-pkg.txt; lazbuild -B tycontrols_dt.lpk > /tmp/term-dt.txt 2>&1; tail -3 /tmp/term-dt.txt; lazbuild -B examples/terminal/terminal_example.lpi > /tmp/term-ex.txt 2>&1; tail -3 /tmp/term-ex.txt; git status --short
```

Expected：三个都编过；`git status` 只多出预期的生成物（`.pot` 若有变化照 i18n 惯例处理）。报错路径里出现别的树 = 注册权被抢，重编一次（[[parallel-agent-worktree-hazards]]）。然后：
1. `python scripts/example-rsj2po.py examples/terminal terminal_example <译文 json>`（Task 17 写好的译文），重编示例，`scripts/check-example-po.py` 过。
2. `powershell -File scripts/smoke-launch-examples.ps1`（至少终端示例起得来、有窗口）。
3. **截图（给期末一次性验收）**：示例播放 `ls-color.cast`、`vim-edit.cast`、`htop-few-frames.cast`、`cat-cjk-emoji.cast` 各停在最后一帧；17 个主题 × 明暗 = 34 张 `ls-color` + 一张专门的 16 色样例（`printf` 出 0–15 前景、背景各一行，写成 `examples/terminal/recordings/palette.cast`，Task 17 里做）× 34；7 / 15 的样例单独放大一张（开工前问题一第 3 条）。存 `docs/superpowers/plans/2026-09-29-terminal-phase-3-shots/`（PNG 进 git，单张 ≤ 300KB）。

- [x] **Step 6: 集中变异**（每条三拍，必须红）

各任务变异表：K*（Task 1–3）、R*（Task 4–6）、V*（Task 7–10）、I*（Task 11–14）、T*（Task 15–19）。JS 侧的变异改完跑对应生成脚本、确认失败后改回，`regen-all.js --expect-clean` 仍然 `clean`。结果逐条记进签收记录；没红的当场补强。

- [x] **Step 7: 整体代码质量审查**

对 `git diff <Task 0 合并后的 HEAD>..HEAD`：
- `TyTerminalEvaluateKey` 与 `Keyboard.ts:38-380` 逐分支对照（重点：`modifiers` 位的算法、`metaKey` 早退的三个方向键、PgUp / PgDn 只看 Ctrl 的那两句、默认分支四个 `else if` 的顺序）；注释里的行号都要对得上。
- 渲染：颜色解析与 `DomRendererRowFactory.ts:342-460` 对照；自绘字形与 `CustomGlyphRasterizer.ts` 对照；字形缓存的键里没有颜色（E2 选了（b）就反过来核）。
- 控件：每个 Core 事件都接了；析构顺序（地雷 8）；`Paint` 里没有改尺寸、没有发宿主事件（地雷 5）；没有往 published 字段写派生状态；视觉值没有写死。
- 夹具读空时每个测试都会红（计数断言）；等价变异的理由站得住。

审出来的问题修完回到 Step 1。

- [x] **Step 8: 写回 spec 原处，标「实现期修正（3 期）」**

至少：§1.1（新增：上游不看应用小键盘模式；第三层 Shift 三项）；§2.1（`Terminal.Render` 单元、`CustomGlyphs.inc`）；§8.4（`AltGraph`、`AKeyPress`）；§9（类声明本期只有两个接口；§9.1 本期属性、4 期才加的几个；§9.2 `OnOsc` 无 `AHandled`；§9.3 `SizeForGrid`；§9.4 可出字符的键不清零、`FKeyDownHandled`；§9.7 条宽恒扣、备用屏禁用不拿掉；§9.9 放 3 期）；§10.1（表面位图、`DrawPart`）；§10.2（格高实测）；§10.3（E1 / E2 结论、`monospace-wide`、做法（c））；§10.4（缓存键按 E2）；§11（`:focus`、`font-family` 由控件读 token、`on()` 是 Rec.601 亮度）；§12.1（示例实际菜单、录制拷进示例）；§13.2（本期脚本与测试单元）；§14（notices 标题）；§16（E1 / E2 已在 Win32 跑过的部分）；§18（3 / 4 期边界的挪动）；开工前问题一的三条结论。

- [x] **Step 9: 签收记录写进本计划末尾，提交**

写：全量条数（基线 → 签收）、提交区间、各 suite 用时、夹具体积与用例数、E1 / E2 结论、变异结果（每条红 / 补强 / 等价）、spec 写回的节号、遗留、给 4 期的交接（鼠标按键上报接 `TriggerMouseEvent`、选区与 `CopyToClipboard`、右键菜单与「清屏」、`OnScrollbackCleared` 清选区、覆盖键、横向滚轮、PRIMARY、OSC 52、链接）；更新「真机验收项汇总」。

```bash
cd /d/Projects/ty-3.1 && git add docs/ && git commit -m "docs(terminal): phase 3 sign-off; corrections written back into the spec

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 3 期做完能看到什么

- `tytests` 里本期七个 suite 全绿：键盘编码全组合与上游逐位相同；渲染部件的颜色、256 色表、字形缓存、自绘字形；控件的事件、调度、焦点、主题、像素（颜色、属性、宽字符、连线、光标、脏行、同步输出、DPI）、输入（吞键、放行、快捷键、滚轮、滚动条、输入法）；17 个主题 × 明暗 16 色都解析得出。
- 示例 `examples/terminal` 能打开 `.cast`、按原速 / 加速 / 一次喂完 / 单步播放，画面和真终端一致；换 17 个皮肤、切明暗，16 色都在；关掉只读后按键在键码面板里显示字节，打开本地回显能在终端里看到输入。
- 组件面板 `TyControls Edits` 里有 `TTyTerminalView`、带图标；设计器里放一个，看得到 16 色预览。
- `docs/controls/terminal.md` 与两份 README 更新。

---

## 真机验收项汇总（全部各期做完后一次性验收；本期新增的在这里，4、5 期接着往下加）

每项写「怎么验 / 看什么算过」。截图在 `docs/superpowers/plans/2026-09-29-terminal-phase-3-shots/`。

| # | 项 | 平台 | 怎么验 | 算过 |
|---|---|---|---|---|
| 1 | E1 字体回退 | GTK2、Linux Qt6、Cocoa（Win32 已在 Task 0 跑过） | 各平台编 `tools/terminal-fontprobe`，跑 `--e1` | CJK 有字形、宽 1.5–2.5 格、不被截；按结果确认 / 改 `monospace-wide` 的平台默认值 |
| 2 | E2 画质与耗时 | 同上 | 跑 `--e2` | （c）对参照差 ≤ 2、热缓存全屏 ≤ 16 ms |
| 3 | 16 色与皮肤 | Win32 | 看 34 张 16 色样例截图 + 34 张 `ls-color` 截图 | 每种皮肤明暗下 1–6、9–14 都看得清；7 / 15 的取舍（开工前问题一第 3 条） |
| 4 | 回放与真终端一致 | 任一 | 示例播放 vim / htop / less / tmux / git log / 彩色 ls / 中英表情 | 与 WSL 里真终端同一录制的画面一致（框线连续、宽字符两格、颜色对） |
| 5 | Linux / macOS 小字清晰度、macOS CJK 下半截 | Qt6、GTK2、Cocoa | 示例 9pt 下看中文与粗体 | 不虚、CJK 不缺下半截 |
| 6 | 键盘：Alt+字母 与窗体菜单 | Win32 | 示例关只读，按 Alt+F、F10 | 终端收到 `ESC f`；F10 发 `ESC[21~`、不激活菜单 |
| 7 | 键盘：AltGr 布局 | Win32（德语、法语布局） | AltGr+Q、AltGr+E、AltGr+7 | 出 `@`、`€`、`{`，不发 ESC 前缀 |
| 8 | 键盘：macOS Option | Cocoa | `MacOptionIsMeta` 两种设置下 Option+字母 | False 出第三层字符；True 发 `ESC` + 字母 |
| 9 | 键盘：死键 | Win32、GTK2、Cocoa | 国际布局下 `´` + `e` | 出 `é` 一个字符 |
| 10 | 键盘：Ctrl+Space、Ctrl+/、Ctrl+Shift+2 / 6 / - | 各平台 | 键码面板 | `00`、`1F`、`00` / `1E` / `1F` |
| 11 | Tab 与焦点 | GTK2、Qt6、Cocoa | 终端获焦后按 Tab、Shift+Tab | 发 `09` / `ESC[Z`，焦点不离开终端；`OnShortcutQuery` 放行 Tab 后焦点才走 |
| 12 | 复制粘贴快捷键 | 各平台 | Ctrl+Shift+V、Shift+Insert、Cmd+V；Ctrl+C | 前三个粘贴；Ctrl+C 发 `03` |
| 13 | 输入法 | Win32、Qt6、GTK2、Cocoa；GTK3 | 中文输入法打字 | 提交的字经 `OnData` 发出；候选窗在光标格（GTK3 已知不跟随）；Cocoa 组字串画在光标处、取消时不发 |
| 14 | 滚轮 | 各平台 | 主屏滚回、备用屏（less）、htop（要鼠标） | 主屏滚 3 行 / 格；less 里翻行（方向键）；htop 里滚轮上报 |
| 15 | 滚动条自动隐藏 | 各平台 | `ScrollBarAutoHide` 三个值；进出 vim | 列数不变；备用屏条禁用 / 淡掉 |
| 16 | DPI | Win32 125% / 150%、每显示器切换 | 拖窗口跨屏 | 格子数、字形重建，不糊不错位 |
| 17 | 光标闪烁 | 各平台 | `CursorBlink = True`，放着不动 5 分钟 | 600ms 闪烁；5 分钟后停在显示 |
| 18 | 设计期 | Lazarus IDE（Win32） | 面板图标、放一个到窗体、换主题 | 图标对；预览 16 色随主题变；没有滚动条和计时器 |
| 19 | OSC 改色后整屏更新 | 各平台 | 在真 shell（4 期）或录制里 `printf '\e]11;#203040\a'`、再 `printf '\e]111\a'` | 整个终端连内边距一起变色、变回，没有残留的旧底色条 |
| 20 | 候选窗位置在切焦点之后 | Win32 | 在示例旁放的 Memo / Edit 里打中文，再点回终端打中文 | 候选窗在终端的光标格，不留在 Memo / Edit 的位置 |
| 21 | AltGr | Linux GTK2、Qt6（德语、法语布局） | 同第 7 项 | 出布局上的字符，不发 ESC 前缀 |
| 22 | 切应用时的焦点报告 | 各平台 | 程序打开 1004（`printf '\e[?1004h'`）后 Alt+Tab 切走再切回 | 键码面板依次出 `1B 5B 4F`、`1B 5B 49`；光标变空心框、停闪，回来恢复 |
| 23 | 同步输出（2026） | 各平台 | neovim、tmux 里快速滚动 / 重绘；再用一个只开 2026 不关的脚本 | 画面不撕裂；只开不关的 1 秒后恢复刷新 |
| 24 | 表面位图不整块黑 | GTK2、Qt6、Cocoa | 示例正常播放、拖动改尺寸、局部重画（光标闪烁） | 没有整块黑（pf24bit 的坑，[[opaque-device-cache-pf24bit]]）；非 Win32 的贴图走 `DrawPart`，顺带看局部重画的耗时 |
| 25 | 滚轮手感 | 各平台（触控板、高精度滚轮） | 主屏滚回、less 里、Shift+滚轮 | 触控板不过灵、不丢格；Shift+滚轮在 Win / Linux 上不动、在 macOS 上滚滚回 |
| 26 | 浅底 3 号色取舍 | —（看截图） | `…-shots/ansi-3-{xp,macos,breeze}-light-15x.png`、`palette-*-light.png`、`ansi-7-15-default-light-2x.png` | 用户在（a）以最暗浅底重算、（b）终端底色改用更白 token、（c）维持 三者中定；7 / 15 调不调 |
| 27 | Shift+Home / End | Win32 PSReadLine、nano | 按 Shift+Home / Shift+End | 现在是本地到顶 / 到底；用户定去留（spec §15） |
| 28 | 禁用态外观 | 各平台 | 示例里临时把终端 `Enabled := False` | 整块按 `:disabled` 的 opacity 变淡，字、底色、内边距、外框一致 |
| 29 | 高 DPI 下「按录制尺寸」 | Win32 125% / 150% | 点「按录制尺寸」 | 网格正好是录制的行列数（状态栏显示），不多不少 |
| 30 | 满屏框线的流畅度 | 各平台 | 播放 `tmux-split.cast`；真 mc / tmux（4 期） | 不卡；框线连续 |
| 31 | macOS 输入法 | Cocoa | 拼音输入、取消、死键（´ + e） | 组字串画在光标处，提交发一次、取消不发；死键的 é 只发一次 |

---

## 3 期签收（2026-09-29）

- **全量**：期末审查修复前 8133 条（2 红与本期无关）→ 签收 8168 条（+35：渲染 5、控件 14、像素 5、输入 5、示例 6），唯一的红是 main 合进来的 `TPainterTest.TestTextIsInkedAsWindowsInksIt`（本机 ClearType 环境，不属本期）；`TPaletteIconTest` 在主控生成图标（`00c285cb`）后转绿。最后一次是集中变异之后 `lazbuild -B` 重编再跑的全量。
- **提交区间**：`79787801..HEAD`（开工的问题记录到本签收）。期末两轮审查（规格核对 + 代码质量）的修复在 `82a2855d..668c24bb` 与本签收：渲染（自绘字形进缓存、64 位键、格数编码、行缓冲复用、块光标下隐藏字、光栅化预算）、括号粘贴一次分配、`Core.DiscardPending`、控件（解析中滚动只做一次、改色整窗重画、帧率上限、Win32 直接贴 DIB、关双缓冲、表面按块、状态失效只在外框变化时、禁用预混、实例样式的色表、只在色表变化时通知且不在绘制里通知、系统焦点、改字体 / 查询度量都重排、候选窗每帧设与聚焦刷新、macOS 输入法、任意键点击取焦点、`KeyUp` 清标志、Shift+滚轮、上报坐标钳制、Kitty / win32-input 屏蔽、去掉多余的滚到底处理器）、示例（流控回放、换录制丢弃排队数据、读失败保留原录制、宽高钳制、`idle_time_limit`、键码面板上限、「一次喂完」翻译、`ActiveControl` 进 `.lfm`、粘贴按钮）、控件文档、探针、截图工具与截图、spec 写回。
- **生成物**：`regen-all.js --expect-clean` clean，`light-palette.js --check` 一致。
- **E1 / E2**：见上面「实验记录」（本批修复后重跑）。性能前后（常驻 DIB 上只计 `RenderTo`，200 × 60，96 PPI）：ASCII 10.4 → 11.8 ms、tmux 框线 2550 → 11.8 ms、mc 双线框 5348 → 12.0 ms；冷填充 380 个字形 872 ms 一帧卡住 → 约 900 ms 摊在 68 帧（每帧不超过 10 ms 的预算）。
- **变异**（每条：改一行 → 确认命中一次 → 编译 → 跑相关 suite → 必须红 → 改回）：

  | # | 变异 | 结果（红的测试） |
  |---|---|---|
  | 1a | 自绘字形缓存键去掉阴影相位 | 红：`TestDrawnGlyphsAreCachedPerCellAndPhase` |
  | 1b | 自绘字形缓存键去掉格宽、格高 | 红：同上 |
  | 2 | 解析后不比颜色签名（不整窗重画） | 红：`TestColourChangesRepaintTheWholeWindow` |
  | 4 | `LM_KILLFOCUS` 不报失焦 | 红：`TestSystemFocusDrivesTheReports` |
  | 5 | 每次滚动当场失效、同步滚动条 | 红：`TestScrollingIsFlushedOncePerParse` |
  | 6 | 一次异步调用只跑一片（没有帧率上限） | 红：`TestSlicesRunOnWithinAFrame` |
  | 8a | 禁用时不预混 | 红：`TestDisabledDimsTowardTheParent` |
  | 8b | 预混的键不含 `Enabled` | 红：同上 |
  | 9a | 查询度量变了不重排 | 红：`TestAQueryRelaysOutTheGrid` |
  | 9b | 改字体不重排 | 红：`TestAFontChangeRelaysOutTheGrid` |
  | 11 | 候选窗锚的行列写反 | 红：`TestTheImeAnchorIsTheCursorCell`（走真路径：有句柄、聚焦、画一帧后问 `GetImeCaretRect` / `ImeCaretBoundClient`） |
  | 12a | 色表不看实例的类和覆盖 | 红：`TestAnInstanceGroundPicksItsSixteenColours` |
  | 12b | 16 色不按实例底色重求 | 红：同上 |
  | 13a | V22：模式一打开就开计时器 | 红：`TestTheSyncTimerWaitsForARowOnScreen`（新）、`TestTheSyncTimerStartsAtTheFirstHeldRow` |
  | 13b | I27：删掉 `MouseDown` 的取焦点 | 红：`TestAnyButtonTakesFocus`（中键、右键） |
  | 14 | 码位键不含粗体 | 红：`TestSingleCodePointsAreCachedByCode` |
  | 16 | 格数塞回半字节 | 红：`TestGlyphKeysKeepCellCountsApart` |
  | 25 | 块光标下照画隐藏字 | 红：`TestHiddenTextStaysHiddenUnderTheCursor` |
  | 26a | Shift+滚轮当普通滚轮 | 红：`TestShiftWheelIsLeftAlone` |
  | 26b | 上报像素不钳 | 红：`TestReportedWheelPixelsStayInTheGrid` |
  | 28a | 读录制先清掉旧的再解析 | 红：`TestAFailedLoadKeepsTheRecordingBefore` |
  | 28b | 头部宽度不钳 | 红：`TestTheGridIsClamped` |
  | 29 | 回放不等在途的块就写下一块 | 红：`TestOneChunkInFlight`、`TestAllAtOnceIntoARealTerminal`（60 MB 一次喂完溢出） |

  审查确认的真等价：I5（`UTF8KeyPress` 不看 `FKeyDownHandled`——那几个键的字符本来就被控制字符过滤丢掉）、I16（不接 `OnRequestScrollToBottom`——Core 自己滚到底；本批把这个多余的处理器删了）、I17（输入法键不早退——上游对 229 本来没有编码、不算本地动作）；不适用：R9（`translateArgs` 的钳制上界——自绘路径只裁不钳）、V40（映射忽略 `YDisp`——Core 报的已是视口行）。翻案补测：V22、I27 见上表。
- **编包 / 编示例**：本批没动 `.lpk`、没动设计期包；示例改了 `umain.pas` / `.lfm` / `uasciicast.pas` / `.po`，主控已在 `da8d0551` 上 `lazbuild -B` 编过运行时包、dt 包和示例，均 0 错；`example-rsj2po.py` 核对 `.po`：rsj 10 条、added 0；示例启动能开窗（2026-09-29）。macOS 输入法（`TTyCocoaImeHandler`、`LM_IM_COMPOSITION`）只在 `{$IFDEF LCLCocoa}` 下编，Win32 上编不到，待 Cocoa 构建。
- **截图**：`docs/superpowers/plans/2026-09-29-terminal-phase-3-shots/`（79 张 + `index.md`，由 `tools/terminal-shots` 离屏生成，单张 ≤ 16 KB）：17 主题 × 明暗的彩色 ls 与 16 色样例、vim / htop（程序退出前的最后一屏）/ 中英表情各明暗一张、7 / 15 号色放大、xp / macos / breeze 浅底的 3 号色放大。抽查了默认浅色 16 色、xp 暗色 ls、htop 暗色、vim 浅色、CJK 表情、两张放大色样：画面正常，没有整块黑、白、空白或哨兵色。
- **浅底对比度**：按主控决定暂维持（c），数字与三个选项写进 spec §11、§17.1 第 4 条，最终验收看截图定（真机验收第 26 项）。

### 给 4 期的交接

- 选区（字符 / 词 / 行 / 列、自动滚动、锚点随行走、`OnScrollbackCleared` 清选区）与 `CopyToClipboard`、`WriteClipboardText`；主题键 `TyTerminalSelection` / `TyTerminalLink` 与 token 已在基础层、解析得出，还没有使用者。
- 右键菜单（`ITyTextEditActions`）与「清屏」的 resourcestring / i18n。
- 链接（OSC 8 + 网址识别、悬停、Ctrl+单击）。
- 鼠标全套经 `Core.TriggerMouseEvent`：按键上报、覆盖键、横向滚轮、中键、PRIMARY、OSC 52 三种策略；上报坐标沿用本期的钳制。
- PTY 示例（ConPTY / forkpty），`OnGridResize` → 改 PTY 尺寸，写入走本期示例的流控写法。
- `Win32InputMode` 与 ConPTY 鼠标：先真机观察 ConPTY 实际发什么；控件不编码 win32-input 时继续屏蔽该扩展。
- 冷启动光栅化（Win32 每个字形约 1.9 ms）的根在库的 `TTyGdiTextRenderer`（每次新建 `TBitmap` 再转换，`Painter.pas`），要提速得改共享文件，交主控定。
