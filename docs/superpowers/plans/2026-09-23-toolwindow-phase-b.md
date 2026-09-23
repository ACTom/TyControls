# IDE 工作台 B 期：手势引擎抽离 + 底栏 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（本期约定，优先于子技能的默认做法）**：整期连续实现，**每个任务单独提交**，每个任务只跑它列出的相关 suite；**不在任务之间安排审查环**。整期做完后（Task 12）跑一次全量、做一次整体规格核对和一次代码质量审查。

**Goal:** 先把栏上的手势状态机抽成独立的引擎类（纯重构），再在它上面做出能用的底栏：文字标签行由当前页代画、松开切换、溢出菜单、最大化 / 还原、收起、标签调顺序、设计期点标签切换，以及运行时跨类改 Parent 抛异常。

**Architecture:** 手势引擎 `TTyToolWindowGesture` 是栏持有的一个普通类，管状态机（Idle / Armed / Dragging / Cancelled、拉宽）、手势记录、临时光标 / 处理器 / 捕获计时器这些资源和唯一的收尾入口；命中、落点、提交、悬停留在栏上。底栏标题行的几何写成纯函数（`tyControls.ToolWindows.Layout` 里 `twhBottom` 那一支 + 逆运算 `TyToolWindowZoneAt`）；栏实现 `ITyToolWindowHeaderHost`，给当前页装配输入、代画、接收转发来的输入；当前页只负责把标签行区域的输入转给栏、并吞掉不该给用户处理器的那一份。

**Tech Stack:** FPC / Lazarus LCL、BGRABitmap、`TTyPainter`、`TTyStyleController.Metric`、fpcunit。

**设计依据：** `docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md`（下称 spec）。本计划覆盖 spec §16 第 4 步，以及 A 期计划末尾「留给 B 期开工时做」的手势引擎抽离。spec 里所有「实现期修正（A 期）」以修正后为准。

**不在本期**：manager（`Images` 回落、跨侧拖动、`MoveWindow`、直接改 Parent 的同类簿记、`OnWindowMoved`）归 C 期；布局保存归 C 期；设计器组件编辑器、属性编辑器、孤儿窗口的设计期显示、示例、`docs/controls/toolwindows.md`、README 归 D 期。

---

## 开工前要定的问题

下面这些是 spec 的 B 期内容互相矛盾、与 A 期实现冲突、或者 spec 明说「B 期再定」的地方。每条给了建议；**计划正文按建议写**，用户改了哪条，执行时按用户的决定改对应任务，收尾时写回 spec。

> **已定（2026-09-23）**：十条都是实现层面的取舍，不涉及产品方向，主控按建议全部采纳，照计划正文执行；收尾时照 Task 12 写回 spec。

1. **`W = nil` 和「没有窗口的栏用同一套几何自己画」（spec §5.4、§7.2）。** A 期的实现里，运行时空底栏高度是 0，设计期空栏在内容区画「Add a tool window」提示（`LayoutAt` 的 `EmptyNote`），根本没有「栏自己画一行标签」的场合；而底栏有窗口时标签行总是由当前页画。
   **建议**：`W = nil` 只表示「栏坐标、当前页的标题行」，给栏自己的查询用（设计期 `CM_DESIGNHITTEST`、栏坐标的 `PartAt`）；没有当前页时几何为空、部件为 none。栏**不**自画标题行，`PaintHeader(nil, …)` 本期不调用。收尾时在 §5.4 / §7.2 原处标注。

2. **分隔线的宽度没有 token（spec §7.2 的输入 `SeparatorWidth` 对 §12）。** §12 的长度 token 里没有分隔线，`TyToolWindowSeparator` 在 light.tycss 里只有 `background: var(--border)`。写死 1px 违反「视觉值走主题 token」。
   **建议**：照 A 期收尾对边缘区的修正，把分隔线改成「线」的写法：light.tycss 里 `TyToolWindowSeparator { border-color: var(--border); border-width: 1px; }`（去掉 background），线宽 = border-width 按 PPI 缩放、至少 1（解析不出可见边框时 0）；槽宽 `SeparatorWidth = 2 × header-gap + 线宽`。代价：改 light.tycss、跑两个生成器、GGRID golden 里 `TyToolWindowSeparator` 那几行要重铺（Task 3 Step 1）。
   **备选**：不动主题，线宽 = `MulDiv(1, PPI, 96)`、颜色取 background——省掉重铺，但线宽写死。

3. **标题行几何缓存键里的「窗口列表戳 / 标题戳」（spec §7.2）和 A 期「窗口顺序每次现取、不缓存」冲突。** 设计器「移到最前 / 最后」直接调非虚的 `SetControlIndex`（`wincontrol.inc:5346` → `SetChildZPosition`，不调任何虚方法、不通知谁），戳记不到这种变化，缓存会端出旧顺序。
   **建议**：不缓存整份几何（排布本身是几十次整数运算），只缓存**标签宽**（量字才是贵的）。缓存键 = 此刻「(窗口引用, Caption) 按 Controls 顺序」的快照数组逐项比 + (PPI, model 身份, ThemeVersion, 样式类, StyleOverride)。快照每次现取，直接调 `SetControlIndex` 也躲不过。收尾时在 §7.2 原处标注。

4. **最大化的 OnResize 订阅（spec §6.4）和 A 期重复；多条同轴底栏时的份额没写。** A 期为了收窄（§6.2 实现期修正）已经让栏**始终**订阅父控件 OnResize（`TTyToolWindowBar.SetParent` → `AddHandlerOnResize(@ParentResized)`），§6.4 的「最大化期间订阅、还原时退订」没有必要。
   **建议**：直接复用已有订阅，最大化只改推导那一项；收尾时在 §6.4 标注。份额：最大化那条的内容项 = 父控件调整后客户区高度 − 同轴非栏对齐兄弟 − 所有参与分空间的同轴栏的固定部分 − **其余**参与者的未收窄内容，不低于 content-min；其余栏照 §6.2 用各自的未收窄值（看最大化那条仍是它的 `ExpandedSize`），不让位。同一父控件里两条底栏本来就少见，这条只保证不出负数、不循环。

5. **`ITyToolWindowHeaderHost` 的签名要补（spec §7.2）。**
   - A 期收尾把渲染统一成「一套尺度」（7339bf50：`RenderTo(APPI)` 的几何和 token 一律按 `APPI`），而 spec 的 `HeaderGeometry(W)` / `PaintHeader(W; P; Geom)` 没有 PPI、行尺寸参数。
   - 底栏统一行高（§3.4）要栏回答「全栏操作区最高多少」。
   - §9.7 要求「捕获者（栏，或转发的当前页）收到 `LM_CANCELMODE`」就取消，接口里没有这一路。
   - `HeaderZoneAt` 注释写的是「tab(i)」，要一个 out 的窗口序号。
   **建议**：接口按 Task 3 Step 2 的声明（加 PPI / 行宽行高参数、`HeaderActionsHeight`、`HeaderCancelMode`、`HeaderZoneAt` 带 `out AIndex`）。窗口找宿主**经 `Bar`**（`GetBar` 是「在不在栏里」唯一的回答处，A 期 Task 3 的审查结论），不另写一处 `Supports(Parent, …)`——只有栏实现这个接口，两者等价。收尾时在 §7.2 标注。

6. **底栏几个固定按钮的字形。** spec 没定。库里现成的矢量字形（`TTyGlyphKind`，`Base.pas:1441-1466`，都有 `--glyph-*` 覆写 token）。
   **建议**：溢出 = `tgChevronDown`（和图标条溢出同一个，下拉用空心 V，见 [[windows-splits-arrow-idioms-by-role]]）；最大化 / 还原 = `tgMaximize` / `tgRestore`；收起 = `tgMinimize`（JetBrains「隐藏」同形；`tgClose` 会被读成「关掉这个窗口」，而收起只是藏起整条底栏）。

7. **底栏溢出按钮的位置和菜单方向（spec §7.3 只定了顺序，§7.4 写「底栏的 B 期接线时再定」）。**
   **建议**：溢出按钮紧跟在最后一个已排标签后面（和 A 期图标条的修正一致，VS Code 面板同形），不贴到操作区左边；菜单从溢出按钮底边、按阅读起点对齐往下开（LTR 左沿、RTL 右沿），锚点和对齐仍由 `TyToolWindowOverflowMenuAnchor` 一处算，加 `twpBottom` 分支。

8. **「区域内的输入吞掉继承的 MouseUp / Click」（spec §3.6）按什么判区域。** 按字面，按下在正文、松开在标签行的那一次，`MouseUp` 会被吞掉——用户看到了 `OnMouseDown` 却收不到配对的 `OnMouseUp`。
   **建议**：**按下落在哪决定这整次点击归谁**：按下在标签行区域 → 这一次的 MouseUp / Click / DblClick 都吞（不管松开在哪）；按下在正文 → 照常走继承。`MouseDown`、`DoContextPopup`、`DoMouseWheel`、提示仍按各自那一刻的位置判断。收尾时在 §3.6 标注。

9. **标签按哪种状态量宽（spec §7.3 / §12 没写）。** 皮肤给 `TyToolWindowTab:selected` 加粗时，只按静止态量，当前标签会被截；按各自状态量，切页时整行重排、后面的标签跟着跳。
   **建议**：每个标签取「静止态样式量的宽」和「选中态样式量的宽」的较大者，再加 2 × tab-pad。

10. **不能最大化的时候设 `Maximized := True`（spec §6.4 没写）。**
    **建议**：侧栏、设计期、加载中、栏收起着、栏里没有窗口时一律忽略（读回 False）；底栏收起着时标签行本来就看不见，没有按钮能点到这一步，代码里设它也不顺带展开。

---

## 空位接线表（spec §16 第 4 步）

A 期给底栏留的空位，每一项在哪个任务里**第一次被源码读到**。Task 12 Step 2 用 grep 核：`source/` 里除定义行之外至少出现一次。

| 空位 | 种类 | 接线任务 | 读它的地方 |
|---|---|---|---|
| `TyToolWindowTabPadVar` | 长度 token 常量 | Task 3 | 标签宽 = 字宽 + 2×tab-pad（`TabWidthsAt`）；Task 5 画字时内缩 |
| `TyToolWindowTabAreaMinVar` | 长度 token 常量 | Task 3 | 纯函数输入 `TabAreaMin` |
| `TyToolWindowButtonSizeVar` | 长度 token 常量 | Task 3 | 纯函数输入 `ButtonSize`、`OverflowWidth` |
| `TyToolWindowIndicatorSizeVar` | 长度 token 常量 | Task 5 | 当前标签下划线粗细 |
| `TyToolWindowTabKey` | 类型键 | Task 3 | 量标签宽的字体；Task 5 标签底色 / 墨色 |
| `TyToolWindowSeparatorKey` | 类型键 | Task 3 | 分隔线线宽（问题 2 的建议）；Task 5 画线 |
| `TyToolWindowTabRowKey` | 类型键 | Task 5 | 标签行底色 |
| `TyToolWindowTabIndicatorKey` | 类型键 | Task 5 | 下划线颜色 |
| `TyToolWindowButtonKey` | 类型键 | Task 5 | 最大化 / 收起按钮底色与字形墨色 |
| 输入 `TabWidths` / `ActiveIndex` / `TabAreaMin` / `ButtonSize` / `SeparatorWidth` / `OverflowWidth` | 纯函数输入字段 | 纯函数在 Task 2 消费；控件在 Task 3 装配 | `TyToolWindowHeaderLayout` 的 `twhBottom` 支；`TTyToolWindowBar.HeaderInputFor` |

类型键常量**跟着第一个读它的任务一起加**，不提前加——没人读的常量就是「建好没接线」（[[built-not-wired-is-the-default-failure]]）。

---

## 文件清单

| 文件 | 职责 / 本期改什么 |
|---|---|
| `source/tyControls.ToolWindows.Layout.pas` | `twhBottom` 那一支排布、`TyToolWindowZoneAt`（Task 2） |
| `source/tyControls.ToolWindows.pas` | 手势引擎类（Task 1）；`ITyToolWindowHeaderHost` 与栏的实现；窗口的底栏输入转发、`CM_MASKHITTEST`、`EInvalidOperation`；最大化；底栏常量与类型键 |
| `source/tyControls.StrConsts.pas`、`languages/tyControls.StrConsts.pot`、`languages/tycontrols.strconsts.zh_CN.po` | 四条提示文字（Task 8） |
| `themes/light.tycss`、生成物 `source/tyControls.DefaultTheme.pas`、`source/tyControls.Css.Catalog.pas`、`tests/golden/*.golden.txt` | 仅在采纳问题 2 的建议时：分隔线改成线写法（Task 3） |
| `tests/test.toolwindow.geometry.pas` | 底栏排布、命中逆运算的输入 / 期望表 |
| `tests/test.toolwindow.window.pas` | `TProbeWindow` 加输入探针（`CallMouseDown` 等，Task 6） |
| `tests/test.toolwindow.bar.pas` | `TBarAccess` 加 `CallAlignControls`（Task 3） |
| `tests/test.toolwindow.bottom.pas` | **新建**。`TTyToolWindowBottomTests`（装配、行高、绘制、最大化、跨类改 Parent、设计期）与 `TTyToolWindowBottomInputTests`（转发、点击、溢出、提示、右键、调顺序） |
| `tests/test.toolwindow.focus.pas` | 需要真句柄的几条：底栏收起焦点、捕获在当前页上的计时器、最大化跟随父控件 |
| `tests/tytests.lpr` | uses 加 `test.toolwindow.bottom` |

**共享文件**：本计划**不改** `source/tyControls.Base.pas`、`source/tyControls.Painter.pas`。要用的都是现成的：`TyDrawGlyph`、`TyMeasureTextBlock`、`TyMeasureRenderedTextWidth`、`TTyPainter.DrawText / FillBackground`、`TyBorderVisible`。执行中如果发现非改不可，**停下来先问用户**，说明要改什么、为什么不能在本单元里解决。

**不碰**：`designtime/`、`examples/`、`docs/controls/`、`tycontrols.lpk`（本期不新建源码单元）。

---

## 实现期的地雷（每个任务开工前看一眼）

A 期计划的 12 条地雷照样有效（`ClientRect` 不含内缩、改内缩要 `Realign; Invalidate;`、`RenderTo` 用 (0,0)-local、缓存位图 pf24bit、`Result := nil` 再 `SetLength`、csNoDesignVisible 先于 Visible、published default、token 常量化、`Metric` 返回逻辑像素、别用 `sed -i` 改 CRLF 文件、换主题只有裸 `Invalidate`）。B 期另加：

1. **源码是 CRLF。** `source/*.pas`、`tests/tytests.lpr`、`tycontrols.lpk` 都是 CRLF。变异时用 LF 搜索串替换会静默 no-op（[[crlf-mutation-phantom-survivor]]）：**每次变异先 `git diff --stat` 确认真改到了**，再编。计划文件本身是 LF。
2. **变异之后必须 `lazbuild -B` 重编**再跑；收割不还原 exe（[[canary-then-rebuild]]）。「全量红 + 单跑绿」先疑二进制陈旧。
3. **引擎的生命期。** 栏构造里 `DeriveSize` 会走到 `SizesAsCollapsed`（读吸附标志）；析构的继承部分会经 `UnregisterWindow` 调 `ResetGesture`。所以引擎在构造**第一句**（`inherited Create` 之后、任何推导之前）建，在析构**最后一句**（`inherited Destroy` 之后）放；栏上读引擎的几个小函数一律 nil 安全。
4. **处理器挂在引擎对象上。** `Application.RemoveAllHandlersOfObject(Self)` 在栏的析构里摘不掉引擎的处理器——引擎自己的析构要对 Application 和 Screen 各调一次 `RemoveAllHandlersOfObject(Self)`。
5. **标签行的一切视觉变化都要让当前页 `Invalidate`。** 像素属于当前页，而当前页有绘制缓存（spec §3.5）：只 `Bar.Invalidate`，运行时 blit 旧帧，设计期不走缓存看着一切正常（假绿）。栏上统一走一个 `InvalidateHeader` 小函数。
6. **「谁先读就是谁的」**（A 期 Task 4 审查结论）：栏算统一行高时**不许**读窗口的 `HeaderTokenPx` 缓存——那是窗口在自己 `Invalidate` 里察觉换主题的唯一一条边。栏只取各窗口操作区的首选高（不缓存的那一项）。
7. **三套坐标。** 窗口客户区（标题行、`HeaderMouse*` 的 X/Y）、栏客户区（`PartAt`、`CM_DESIGNHITTEST`）、屏幕（手势原点、阈值）。窗口是栏的直接子控件：栏坐标 = 窗口坐标 + `W.Left/W.Top`（先查一遍窗口的 `BoundsRect` 确实是栏客户区坐标，不是 `AdjustClientRect` 之后的相对坐标）。`CM_MASKHITTEST` 的坐标是**设计器窗体**坐标（照 `TTyShape.CMMaskHitTest`，`Shape.pas:709-725`）。
8. **RTL 只镜像一次。** 纯函数排完就镜像（`TyToolWindowFlipAll`），绘制、命中都吃镜像后的几何；只有「按阅读顺序找空隙」要先拿一份再翻回 LTR 的拷贝、指针 `X' := RowWidth - 1 - X`。
9. **在捕获者自己的 MouseUp 里藏起它自己。** 点标签切页、点收起，都会在当前页（捕获者）的 `MouseUp` 里把它藏掉。动作一律放在最后一句，之后不再碰 `Self`（spec §9.2）。LCL 在 `Click` / `MouseUp` 之前已经放了捕获（`control.inc:2827-2846`）。
10. **LCL 的调用顺序。** `WMLButtonUp`：先 `Click` 再 `MouseUp`；`WMLButtonDBLCLK`：先 `DoMouseDown(ssDouble)` 再 `DblClick`（`control.inc:2602-2604`）。所以「这一次按在哪」要在 `WndProc` 收到 `LM_LBUTTONDOWN / LM_LBUTTONDBLCLK` 时就记下（同栏的 `FAutoDragPos`），`Click` / `DblClick` / `BeginAutoDrag` 都问它。
11. **无头的边界。** 无头没有捕获（`CaptureConfirmed` 恒假，计时器不建）、窗体 OnResize 排队发且无头不走（最大化跟随父控件）、对齐引擎不跑（要自己调 `AdjustClientRect + AlignControls`，[[headless-tests-never-run-lcl-align]]）。这几类断言放 `test.toolwindow.focus` 的真句柄夹具。
12. **夹具别对称。** 镜像、对齐、「当前页被强制留下」这类断言，标签标题要**长短不一**、当前页不要是第一个——等宽标签镜像前后一模一样，断言从来没变过（[[assertion-never-varies-the-thing]]）。
13. **像素断言用哨兵底色**（[[headless-render-needs-sentinel-ground]]）：把栏的主题背景经控制器 `StyleOverride` 刷成品红，被测的颜色挑红绿蓝不等的值。
14. **`SetBounds` 原样再设是空操作**（[[lcl-setbounds-same-rect-noop]]）；**`AssertSame` 对已释放指针会假绿**（[[assertsame-freed-pointer-trap]]）——窗口在手势中被释放的测试，断言走「当前页没变 / 手势状态」，不比已释放的指针。

---

## 跑测试的固定套路

改了 `source/` 之后**必须** `lazbuild -B`。exe 用唯一名 `tytests-31.exe`（别的会话也在跑 `tytests.exe`，[[parallel-agent-worktree-hazards]]）。

跑一组 suite（把 `SUITES` 换成任务里列的名字）：

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi > /tmp/build.txt 2>&1 || { tail -30 /tmp/build.txt; false; } && cd tests && cp tytests.exe tytests-31.exe && for s in SUITES; do ./tytests-31.exe --suite=$s --format=plain > /tmp/t-$s.txt 2>&1; printf '%s: ' $s; grep -E "Number of (run tests|errors|failures)" /tmp/t-$s.txt | tr '\n' ' '; echo; done
```

**判据是每个 suite 那一行都有 `Number of run tests`、errors / failures 为 0**，不是 exit code。某一行为空 = 跑丢了（或 suite 名写错，`No tests selected.` 也是空），重跑，别读成通过。

全量（只在 Task 0 和 Task 12；输出必须重定向到文件，[[known-rare-suite-flake]]）：

```bash
cd /d/Projects/ty-3.1/tests && ./tytests-31.exe --all --format=plain > /tmp/all.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/all.txt
```

工具窗口的全部 suite：`TTyToolWindowGeometryTests TTyToolWindowThemeTests TTyToolWindowTests TTyToolWindowStreamingTests TTyToolWindowActionsTests TTyToolWindowBarTests TTyToolWindowImagesTests TTyToolWindowFocusTests TTyToolWindowStripTests TTyToolWindowEdgeTests TTyToolWindowReorderTests`，Task 2 起再加 `TTyToolWindowBottomTests TTyToolWindowBottomInputTests`（后者 Task 6 起才有）。下文写「工具窗口全部 suite」指这一串。

## 关于判据和变异

纯函数（Task 2）给输入 / 期望表，测试照表写。**涉及时序、手势、焦点、像素的，计划只写判据和「在哪个变异下必须红」**，测试代码执行时按判据现写，写完**先做变异确认它真的在守**（A 期经验：隔空写的时序测试近一半是假守卫，[[tests-written-with-the-fix-are-green-and-wrong]]、[[plan-tests-write-the-mutation-not-the-code]]）。

变异三拍：改一行 → `git diff --stat` 确认改到了 → `lazbuild -B` → 跑 → **必须红** → 改回 → 重编重跑 → 绿。一条变异没红：先查是不是改错了地方；确实没红，说明那条测试没守住，**当场补强再继续**，并在该任务的提交信息里写一句。

探针只能是**真实状态的只读视图**，不许另开一条测试专用的计算路径（A 期计划「探针属性」一节）。

---

### Task 0: 基线

**Files:** 无改动。

- [ ] **Step 1: 确认起点**

```bash
cd /d/Projects/ty-3.1 && git status --short && git log --oneline -1
```

Expected：工作区干净，分支 `feat/3.1`，HEAD 是本计划的提交或其后。

- [ ] **Step 2: 编译并跑工具窗口全部 suite + 全量，记下条数**

先跑「工具窗口全部 suite」，再跑全量。把每个 suite 的 `Number of run tests` 和全量总数记进本计划 Task 12 的签收区（先写在草稿里，Task 12 一起提交）。A 期签收是 7364 条 0 / 0。

Expected：全部 0 errors / 0 failures。**有红就停**：B 期不在红的基线上开工。

---

### Task 1: 把手势状态机抽成 `TTyToolWindowGesture`（纯重构）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- （只在 Step 6 发现测试没守住时）Modify: `tests/test.toolwindow.*.pas`

**目标**：栏上现在散着 18 个手势字段（`FGState / FGPart / FGWindow / FGOrigin / FGMulti / FGSwallowClick / FDesignGesture / FDesignWindow / FEdgeDragging / FEdgeSnapped / FEdgeStartSize / FEdgeStartPos / FDeactivateHooked / FDragCursor / FTempCursorPushed / FGestureHooked / FCaptureConfirmed / FCaptureTimer`），状态转移写在 `MouseMove` / `MouseUp` 的分支里，唯一清理入口是 `ResetGesture`。抽成一个引擎类，让 B 期标签行（捕获者是当前页而不是栏）、C 期跨栏拖动（目标栏不是源栏）能直接复用。**行为一点不变，不加任何新行为、不加没人用的字段**（spec §9.2 列的「源索引、窗口原来是否当前页、栏原来是否收起」A 期没有用处，本任务也不加，等用它的任务再加）。

**拆分边界：**

| 归引擎（`TTyToolWindowGesture`） | 留在栏上 |
|---|---|
| 状态 Idle / Armed / Dragging / Cancelled 与全部转移 | 命中：`PartAt`、`DropSlotAt`、`IsNoOpSlot`、`DropLineY` |
| 手势记录：部件、窗口引用、**捕获者**（`TControl`，本任务恒为栏）、屏幕原点、多击标记、可否拖动、吞点击标志 | 落点反馈：`FDropSlot`、`SetDropSlot`（spec §9.2：反馈属于目标栏） |
| 拉宽记录：进行中、吸附中、起点尺寸、起点屏幕坐标 | 提交与点击语义：`ReorderWindow`、`StripClick`、`ShowOverflowMenu`、`EdgeDragTo`（按位移写尺寸） |
| 设计期武装：武装中、被按下的窗口 | 悬停与按下的**视觉**状态：`FStripHover`、`FStripPressed`、`FOverflowHover`、`FOverflowPressed`、`FEdgeHover`、借来的光标 |
| 资源：临时光标（唯一一次压 / 弹）、KeyDownBefore / ActiveFormChanged / Deactivate 三个处理器、捕获计时器与 `CaptureConfirmed` | 输入管道：`FAutoDragPos`、`BeginAutoDrag`、`WndProc`、`DoContextPopup`、`GetPopupMenu`、溢出菜单 |
| 唯一收尾入口 `Reset(原因)`（幂等） | `ResetGesture(原因)` 保留为**一行转发**，所有现有调用点不动 |

引擎在收尾时回调栏的三处（同单元，直接调 private）：`ResizeEnded`（拉宽回起点或保留，现 `ResetGesture` 前半段原样搬过去）、`SetDropSlot(-1)`（清反馈）、`GestureCleared`（清按下的视觉状态并重画，现 `ResetGesture` 末尾那段）。

**为什么不另开单元**：引擎要回调栏的 private 方法、记 `TTyToolWindow` 引用，C 期的 manager 也在本单元；拆出去就得为它另立一个回调接口、把窗口引用降成 `TControl`，还要登记 .lpk、改测试的 uses。本任务只在同一单元里把它从栏上拿开。

- [ ] **Step 1: 在 interface 段声明引擎（`TTyToolWindowGestureEnd` 之后、`TTyToolWindowBar` 之前）**

```pascal
  { 手势引擎一次移动之后告诉栏该做什么(见 TTyToolWindowGesture.Move 的状态表)。 }
  TTyToolWindowGestureMove = (
    twgmNone,       { 什么都不做:武装着没过阈值、Cancelled 还按着、丢了松开刚被取消 }
    twgmHover,      { 不在手势里(或取消后按键已松):追踪悬停 }
    twgmDragStart,  { 这一下刚过阈值进入拖动:先清悬停,再按拖动处理 }
    twgmDrag,       { 拖动中:重算落点 }
    twgmResize);    { 拉宽中:按位移写尺寸 }

  { 松开时这次手势算什么。零值 twrNone 就是安全的那一侧:什么都不做。 }
  TTyToolWindowReleaseKind = (twrNone, twrClick, twrDrop, twrResize);
  TTyToolWindowGestureRelease = record
    Kind: TTyToolWindowReleaseKind;
    Part: TTyToolWindowBarPart;   { twrClick:按下的那个部件 }
    Window: TTyToolWindow;        { twrClick / twrDrop:手势的窗口 }
    Snapped: Boolean;             { twrResize:松手时处在吸附排布 }
  end;

  { 栏的手势引擎(spec §9.2 / §9.7)。每条栏一个,栏构造时建、析构最后放。
    只管状态机、手势记录、资源和唯一的收尾入口;命中、落点、提交、悬停都在栏上。
    内部类型:只给本单元的栏(C 期还有 manager)用,不是公开 API。 }
  TTyToolWindowGesture = class
  private
    FBar: TTyToolWindowBar;
    FState: TTyToolWindowGestureState;
    FPart: TTyToolWindowBarPart;
    FWindow: TTyToolWindow;
    { 收到按下、持有捕获的控件:图标条是栏,B 期标签行是当前页。阈值原点、捕获轮询都按它。 }
    FCapturer: TControl;
    FOrigin: TPoint;            { 屏幕坐标 }
    FMulti: Boolean;
    FDraggable: Boolean;
    FSwallowClick: Boolean;
    FResizing: Boolean;
    FSnapped: Boolean;
    FStartSize: Integer;
    FStartPos: TPoint;          { 屏幕坐标 }
    FDesignArmed: Boolean;
    FDesignWindow: TTyToolWindow;
    FCursor: TCursor;
    FCursorPushed: Boolean;
    FHooked: Boolean;
    FDeactivateHooked: Boolean;
    FCaptureConfirmed: Boolean;
    FCaptureTimer: TComponent;  { ExtCtrls.TTimer;ExtCtrls 只在 implementation 里 uses }
    procedure ReleaseResources;
    procedure SyncDeactivateHook;
    procedure BeginDragging;
    function PastThreshold(X, Y: Integer): Boolean;
    procedure KeyDownBefore(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ActiveFormChanged(Sender: TObject; Form: TCustomForm);
    procedure AppDeactivated(Sender: TObject);
    procedure CaptureTimerTick(Sender: TObject);
  public
    constructor Create(ABar: TTyToolWindowBar);
    destructor Destroy; override;
    { 新的一次按下(调用方已经 Reset(twgeDiscard) 过)。X, Y 是捕获者客户区坐标。 }
    procedure Press(APart: TTyToolWindowBarPart; AWindow: TTyToolWindow; ADraggable: Boolean;
      ACapturer: TControl; X, Y: Integer; AShift: TShiftState);
    procedure BeginResize(AStartSize: Integer; const AScreenPos: TPoint);
    function Move(AShift: TShiftState; X, Y: Integer): TTyToolWindowGestureMove;
    { APart / AWindow:松开点上的部件和窗口(调用方命中);引擎判完就收尾,再把答案交回。
      拖动的落点由调用方在调它**之前**算好 —— 落点要看手势窗口,收尾之后就没了。 }
    function Release(APart: TTyToolWindowBarPart; AWindow: TTyToolWindow): TTyToolWindowGestureRelease;
    procedure Reset(AReason: TTyToolWindowGestureEnd);
    procedure SetCursor(ACursor: TCursor);
    procedure ArmDesign(AWindow: TTyToolWindow);
    procedure DisarmDesign;
    property State: TTyToolWindowGestureState read FState;
    property Part: TTyToolWindowBarPart read FPart;
    property Window: TTyToolWindow read FWindow;
    property Capturer: TControl read FCapturer;
    property Resizing: Boolean read FResizing;
    property Snapped: Boolean read FSnapped write FSnapped;
    property StartSize: Integer read FStartSize;
    property StartPos: TPoint read FStartPos;
    property SwallowClick: Boolean read FSwallowClick write FSwallowClick;
    property DesignArmed: Boolean read FDesignArmed;
    property DesignWindow: TTyToolWindow read FDesignWindow;
    function HasCaptureTimer: Boolean;
  end;
```

`TTyToolWindowBarPart` 目前声明在 `TTyToolWindowGestureState` 前面，顺序已经对；`TCustomForm` 已经从 `Forms` 来。

- [ ] **Step 2: 实现引擎——把栏上现有的函数体搬过来，一行语义不改**

对照表（左边是现在栏上的，右边是去处）：

| 现在（栏） | 搬到 |
|---|---|
| `ReleaseGestureResources` | `TTyToolWindowGesture.ReleaseResources`（里面 `SetDropSlot(-1)` 改成 `FBar.SetDropSlot(-1)`） |
| `SyncDeactivateHook` / `HookDeactivate` / `AppDeactivated` | 引擎同名（`HookDeactivate` 并进 `SyncDeactivateHook`）；条件 = `FResizing or FHooked`；`BeginResize`、`BeginDragging`、`ReleaseResources` 末尾各调一次（现在 `BeginEdgeDrag`、`BeginDragging`、`ReleaseGestureResources` 就是这三处） |
| `BeginDragging` 的资源部分 | `TTyToolWindowGesture.BeginDragging`；`CaptureConfirmed := (FCapturer is TWinControl) and TWinControl(FCapturer).HandleAllocated and (GetCaptureControl = FCapturer)` |
| `SetDragCursor` | `SetCursor` |
| `KeyDownBefore` / `ActiveFormChanged` / `CaptureTimerTick` | 引擎同名；`ActiveFormChanged` 比的是 `GetParentForm(FBar)`；计时器比的是 `FCapturer` |
| `ResetGesture` 的主体 | `Reset`：① 拉宽中 → 记下吸附、清两个标志，栏不在析构中就 `FBar.ResizeEnded(AReason, wasSnapped)`；② `ReleaseResources`；③ 状态转移（照现有：`twgeCancel` 且原来 Dragging / Cancelled → Cancelled，其余 Idle）；④ 清记录（部件、窗口、捕获者、多击、可拖）；⑤ `FBar.GestureCleared` |
| `MouseMove` 里的状态分支 | `Move`，按下表 |
| `MouseUp` 里「拷到局部、判点击、收尾」 | `Release`，按下表 |
| `FDesignGesture := …` 的四处 | `ArmDesign` / `DisarmDesign` |

`Move` 的状态表（**必须和现在的 `MouseMove` 逐格一致**，执行时逐行对照旧代码核）：

| 进入时 | Shift 带 ssLeft | 引擎做的事 | 返回 |
|---|---|---|---|
| 拉宽中 | 是 | — | `twgmResize` |
| 拉宽中 | 否 | `Reset(twgeCancel)` | `twgmNone` |
| Dragging | 是 | — | `twgmDrag` |
| Dragging | 否 | `Reset(twgeCancel)` → Cancelled | `twgmNone` |
| Armed | 否 | `Reset(twgeCancel)` → Idle | `twgmNone` |
| Armed，可拖，过阈值 | 是 | `BeginDragging` | `twgmDragStart` |
| Armed，其他 | 是 | — | `twgmNone` |
| Cancelled | 否 | `Reset(twgeDiscard)` | `twgmHover` |
| Cancelled | 是 | — | `twgmNone` |
| Idle | 任意 | — | `twgmHover` |

阈值：`PastThreshold` = 捕获者 `ClientToScreen(Point(X, Y))` 与 `FOrigin` 的 `Max(|dx|, |dy|) >= TyToolWindowDragThreshold(FBar.PPI)`（现有写法原样）。

`Release` 的判定表（调用方先处理设计期分支，再调它）：

| 进入时 | 条件 | 引擎 | 返回 `Kind` |
|---|---|---|---|
| 拉宽中 | — | 记下 `FSnapped`，`Reset(twgeRelease)` | `twrResize`（`Snapped`） |
| Dragging | — | 记下窗口，`Reset(twgeRelease)` | `twrDrop`（`Window`） |
| Armed | 没有多击；`APart = FPart`；部件是 `twbpItem` 时还要 `AWindow = FWindow` | 记下部件和窗口，`Reset(twgeRelease)` | `twrClick` |
| 其他 | — | `Reset(twgeRelease)` | `twrNone` |

析构：`ReleaseResources`，然后 `Application.RemoveAllHandlersOfObject(Self)`、`Screen.RemoveAllHandlersOfObject(Self)`（各自判 nil）。**析构不回调栏**（它是在栏的 `inherited Destroy` 之后才放的）。

- [ ] **Step 3: 栏改成用引擎**

- 删掉上面那 18 个字段和搬走的 8 个方法；加 `FGesture: TTyToolWindowGesture;`。
- 构造：`inherited Create` 之后**第一句** `FGesture := TTyToolWindowGesture.Create(Self);`（在 `DeriveSize` 之前）。
- 析构：保留原来的 `ResetGesture(twgeDiscard)` 位置；`inherited Destroy;` **之后**加 `FreeAndNil(FGesture);`。
- 加 private 的 nil 安全小函数 `EdgeResizing` / `EdgeSnapped`（`(FGesture <> nil) and FGesture.Resizing` 之类），`SizesAsCollapsed`、`RenderTo`、`RecheckHover`、`MouseLeave`、`UnregisterWindow` 里原来读 `FEdgeDragging` / `FEdgeSnapped` 的地方改读它们。
- 新加 private `ResizeEnded(AReason: TTyToolWindowGestureEnd; AWasSnapped: Boolean)`（现 `ResetGesture` 里 `if FEdgeDragging then … end` 那段的「不在析构中」分支，起点从 `FGesture.StartSize` 取）和 `GestureCleared`（现 `ResetGesture` 末尾清 `FStripPressed` / `FOverflowPressed` 那段）。
- `ResetGesture(AReason)` 变成 `FGesture.Reset(AReason);` 一行；所有调用点不动。
- `MouseDown`：`FGSwallowClick := …` → `FGesture.SwallowClick := …`；武装 → `FGesture.Press(part, 窗口或 nil, part = twbpItem, Self, X, Y, Shift)`，按下视觉（`FStripPressed` / `FOverflowPressed` + `Invalidate`）留在栏上照旧；设计期 → `FGesture.ArmDesign(…)`；边缘区 → `BeginEdgeDrag` 里调 `FGesture.BeginResize(FExpandedSize, ClientToScreen(Point(X, Y)))`（守卫和 `Invalidate` 留在栏上）。
- `MouseMove`：`case FGesture.Move(Shift, X, Y) of twgmResize: EdgeDragTo; twgmDragStart: SetStripHover(-1, False) 后 DragTo; twgmDrag: DragTo; twgmHover: UpdateHoverAt; twgmNone: ; end`。注意现在 `BeginDragging` 里 `SetStripHover(-1, False)` 在压光标之前；搬完之后在 `twgmDragStart` 分支里做，只是先后换了，两者互不读对方的状态。
- `MouseUp`：设计期分支照旧（改调 `DisarmDesign`）；然后 `if FGesture.State = twgsDragging then` 先按现在的写法算好 `idx` 与「是否提交」；`part := PartAt(X, Y, idx2)`；`rel := FGesture.Release(part, 那一格的窗口或 nil)`；再按 `rel.Kind` 分派。**每一支里「重查悬停」和「动作」的先后照现在的代码，不许统一**：
  - `twrResize`：先 `if rel.Snapped then Collapsed := True`，再 `UpdateHoverAt(X, Y)`（现在就是「收尾 → 写 Collapsed → 重查悬停」）；
  - `twrDrop`：先 `UpdateHoverAt`，再提交（`ReorderWindow`）；
  - `twrClick` / `twrNone`：先 `UpdateHoverAt`，再 `StripClick` / `ShowOverflowMenu`（`twrNone` 没有动作）。
- `DragTo` 里的 `SetDragCursor` → `FGesture.SetCursor`。
- `EdgeDragTo`：`FEdgeStartPos` / `FEdgeStartSize` / `FEdgeSnapped` → 引擎的 `StartPos` / `StartSize` / `Snapped`。
- `CMDesignHitTest`、`CaptureChanged`、`MouseLeave`、`LMCancelMode`、`UnregisterWindow`：`FDesignGesture` / `FDesignWindow` → `FGesture.DesignArmed` / `DesignWindow` / `DisarmDesign`；`FGWindow` / `FGPart` → `FGesture.Window` / `Part`。
- `IsNoOpSlot`：`FGWindow` → `FGesture.Window`。
- 探针名字都不改：`GestureStateForTest` → `FGesture.State`；`IsDraggingForTest`；`HasCaptureTimerForTest` → `FGesture.HasCaptureTimer`；`IsEdgeDraggingForTest` 从 `property … read FEdgeDragging` 改成读 `EdgeResizing` 的函数（测试里的用法不变）。
- 注释：把原来挂在这些字段上的中文注释跟着搬到引擎的字段上，别丢。

- [ ] **Step 4: 编译、跑工具窗口全部 suite**

Expected：条数与 Task 0 记下的**完全相同**，全部 0 / 0。测试文件一行没改就能编过（探针名字没变）。

- [ ] **Step 5: 结构验收**

```bash
cd /d/Projects/ty-3.1 && grep -nE "\bF(G(State|Part|Window|Origin|Multi|SwallowClick)|Design(Gesture|Window)|Edge(Dragging|Snapped|StartSize|StartPos)|DeactivateHooked|DragCursor|TempCursorPushed|GestureHooked|CaptureConfirmed|CaptureTimer)\b" source/tyControls.ToolWindows.pas
```

Expected：没有输出（旧字段名一个不剩；引擎里的字段是新名字）。再确认 `ResetGesture` 的函数体只有一行、`ReleaseGestureResources` 这个名字已不存在。

- [ ] **Step 6: 变异——重构之后这些仍必须红**

每条改在**引擎**里（或栏的新接缝上），三拍做完：

| # | 变异 | 必须红的测试 |
|---|---|---|
| 1 | `ReleaseResources` 里弹临时光标那段整个删掉 | `TestFreeingTheBarMidDragUnwindsTheCursorStack`、`TestASecondPressWhileDraggingUnwindsEverything` |
| 2 | `Reset` 里 `twgeCancel` 记成 Cancelled 那句删掉 | `TestEscCancelsAndTheReleaseIsNotAClick` |
| 3 | `BeginDragging` 不挂 `KeyDownBefore` | `TestEscCancelsAndTheReleaseIsNotAClick` |
| 4 | `SyncDeactivateHook` 恒按 False 处理 | `TestApplicationDeactivationCancelsTheDrag` |
| 5 | `ActiveFormChanged` 不比窗体、直接返回 | `TestAnotherFormBecomingActiveCancelsTheDrag` |
| 6 | `CaptureTimerTick` 拖动中不取消 | `TestTheCaptureTimerCancelsWhenCaptureIsLost`（focus） |
| 7 | `ResizeEnded` 在取消时不回起点 | `TestEdgeDragCancelRestoresTheStartValue`、`TestAPressAfterALostReleaseRestoresTheStartSize` |
| 8 | `Press` 不记多击标记 | `TestDoubleClickPressNeverCounts` |
| 9 | `PastThreshold` 只算 `dy` | `TestSidewaysDragStarts` |
| 10 | `Release` 判点击时不比窗口（只比部件） | `TestAReleaseOffTheIconIsNotAClick` 或 `TestAWindowLeavingKeepsThePressedIconOnItsWindow`（至少一条红） |
| 11 | 栏的 `CaptureChanged` 不调 `DisarmDesign` | `TestACancelledDesignGestureIgnoresTheNextBareHitTest` |
| 12 | `UnregisterWindow` 里「手势窗口走了就 `ResetGesture(twgeDiscard)`」删掉 | `TestAWindowFreedWhileArmedIsNotAClick`、`TestFreeingTheDraggedWindowEndsTheGesture` |
| 13 | 引擎析构不 `RemoveAllHandlersOfObject`，**并且** `Reset` 不摘失活处理器 | `TestFreeingTheBarMidDragUnwindsTheCursorStack`（释放后 `IntfAppDeactivate` 调进已释放对象） |
| 14 | 把 `FreeAndNil(FGesture)` 挪到 `inherited Destroy` 之前 | 释放窗口 / 释放栏的任一条 AV（`TestFreeingTheBarMidResizeIsQuiet` 等） |

跑 1–5、7–12 用对应 suite；6 在 `TTyToolWindowFocusTests`。任何一条没红：先 `git diff` 看是不是没改到（CRLF），确实没红就说明原测试没守住——补强那条测试，让它在这个变异下红，另起一个提交 `test(toolwindows): …`。

- [ ] **Step 7: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas && git commit -m "refactor(toolwindows): the bar's gesture state machine becomes its own engine

The press record, the resize record, the design-time arm, the temp cursor,
the three application/screen handlers and the capture timer move off the bar
into TTyToolWindowGesture, with Reset as the single exit. Hit testing, drop
feedback, commits and hover stay on the bar. No behaviour change; the capturer
is a field so the bottom bar's tab row can drive the same engine.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 底栏标题行的纯几何（`twhBottom` 排布 + `TyToolWindowZoneAt`）

**Files:**
- Modify: `source/tyControls.ToolWindows.Layout.pas`
- Modify: `tests/test.toolwindow.geometry.pas`

纯函数不认 DPI、主题、控件；尺寸都是调用方缩放好的设备像素。

**排布规则**（spec §7.3，按问题 7 的建议定溢出按钮位置）：

- 从尾端往前：尾端留一个 `Pad` → `[收起][Gap][最大化][分隔线槽][操作区][溢出][标签…]` → 行首留一个 `Pad`。
- 固定部件（收起、最大化、分隔线槽）永远不缩；按钮是 `ButtonSize` 见方（高钳进行高、垂直居中），分隔线槽占整行高、宽 `SeparatorWidth`。排不下的那一截钳在 `[0, RowWidth]` 里，矩形不反转。
- 操作区保持 `ActionsWidth`，直到标签区（行首 `Pad` 到操作区左沿）缩到 `TabAreaMin`；再往下才压缩操作区，最小到 0（0 = 全零哨兵，同「没有操作区」）。压缩只缩宽，里面的子控件贴尾端、裁开头，由操作区自己的排布做。
- 标签：`TyToolWindowVisiblePlan(标签区宽, TabWidths, ActiveIndex, OverflowWidth)` 给出可见计划；从标签区左沿依次排，每个标签右沿不越过「标签区右沿，有东西被收起时再减 `OverflowWidth`」——于是只有当前页的标签连单独都放不下时才会被截（画的时候出省略号）。
- 溢出按钮：有窗口被收起时紧跟在最后一个已排标签后面，宽 `OverflowWidth`，按钮带那样垂直居中，右沿钳在标签区右沿。
- `Hidden` = 不在可见计划里的窗口序号，按窗口顺序。
- RTL：排完调 `TyToolWindowFlipAll`（函数末尾那一句本来就在）。

- [ ] **Step 1: 写失败的测试（照下表）**

公共输入：`Mode = twhBottom`、`RowHeight = 26`、`Pad = 6`、`Gap = 4`、`ButtonSize = 22`、`SeparatorWidth = 9`、`OverflowWidth = 22`、`TabAreaMin = 50`、`ActionsWidth = 60`、`TabWidths = [80, 70, 90]`。矩形写成 `(Left, Top, Right, Bottom)`。

| # | 变化的输入 | 期望 |
|---|---|---|
| B1 | `RowWidth = 400`、`ActiveIndex = 0` | 收起 `(372,2,394,24)`；最大化 `(346,2,368,24)`；分隔线 `(337,0,346,26)`；操作区 `(277,0,337,26)`；标签区 `(6,0,277,26)`；标签 `[0:(6..86), 1:(86..156), 2:(156..246)]`（纵向 0..26）；溢出为空；`Hidden = []` |
| B2 | `RowWidth = 300`、`ActiveIndex = 0` | 操作区 `(177,0,237,26)`；标签区 `(6,0,177,26)`；标签只有 `[0:(6..86)]`；溢出 `(86,2,108,24)`；`Hidden = [1, 2]` |
| B3 | `RowWidth = 300`、`ActiveIndex = 2` | 标签只有 `[2:(6..96)]`（**窗口序号 2 排在第一格**）；溢出 `(96,2,118,24)`；`Hidden = [0, 1]` |
| B4 | `RowWidth = 160`、`ActiveIndex = 0` | 分隔线 `(97,0,106,26)`；操作区被压到 41：`(56,0,97,26)`；标签区 `(6,0,56,26)`；标签 `[0:(6..34)]`（被截，省略号的情形）；溢出 `(34,2,56,24)`；`Hidden = [1, 2]` |
| B5 | `RowWidth = 60`、`ActiveIndex = 1` | 收起 `(32,2,54,24)`；最大化 `(6,2,28,24)`；分隔线钳成 `(0,0,6,26)`；操作区全零；标签区宽 0；标签 `[1:宽 0]`；`Hidden = [0, 2]`；**所有矩形都在 `[0, 60]` 里、`Right >= Left`** |
| B6 | B1 再加 `ActionsWidth = 0` | 操作区全零；标签区 `(6,0,337,26)` |
| B7 | B1 再加 `TabWidths = []`、`ActiveIndex = -1` | 标签、溢出、`Hidden` 都空；三个固定部件同 B1 |
| B8 | B1 再加 `RightToLeft = True` | 收起 `(6,2,28,24)`；标签 0 `(314..394)`；操作区 `(63,0,123,26)`；和 B1 对照每个矩形都是 `BidiFlipRect` 的结果 |
| B9 | B2 再加 `RowHeight = 16` | 按钮高钳成 16：收起 `(272,0,294,16)`；溢出同样 16 高 |
| B10 | B1 再加 `TabWidths = [80, -5, 90]`、`ButtonSize = -3` | 不抛异常；负宽按 0；按钮宽按 0；矩形不反转 |

命中逆运算 `TyToolWindowZoneAt(const AGeom; X, Y: Integer; out AIndex: Integer): TTyToolWindowZone`：

| # | 判据 |
|---|---|
| Z1 | 对 B1–B4、B8 的每一个**非空**部件，它的中心点 → 那个部件；标签中心 → `twzTab`，`AIndex` 是**窗口序号**（B3 的第一格答 2，不答 0） |
| Z2 | 操作区中心、标签区里最后一个标签之后的空白 → `twzNone`，`AIndex = -1` |
| Z3 | 侧栏几何（`Mode = twhSide`，任取一组 A 期的输入）上任何一点 → `twzNone` |
| Z4 | B5 里宽 0 的标签、钳成零宽的部件永远命不中 |

- [ ] **Step 2: 跑，确认编译失败**（`TyToolWindowZoneAt` 未声明）或表里的行红（`twhBottom` 那一支现在什么都不排）。

- [ ] **Step 3: 实现**

`TyToolWindowHeaderLayout` 里 `if AInput.Mode = twhSide then … end;` 后面接 `else if AInput.Mode = twhBottom then LayoutBottomRow(AInput, pad, gap, aw, Result);`（`pad / gap / aw` 用函数开头已经钳过的值），删掉那句「twhBottom 那一支在 B 期实现」的注释。`LayoutBottomRow` 写在 implementation 段、`TyToolWindowHeaderLayout` 之前：

```pascal
{ 底栏标题行(spec §7.3)。从尾端往前 [收起][最大化][分隔线][操作区][溢出][标签…];
  固定部件不缩,放不下的那一截钳在 [0, 行宽];操作区保宽直到标签区缩到 TabAreaMin;
  标签按可见计划排(当前页强制留下),溢出按钮紧跟最后一个已排标签。镜像由调用方末尾统一做。 }
procedure LayoutBottomRow(const AInput: TTyToolWindowHeaderInput; APad, AGap, AActionsW: Integer;
  var AGeom: TTyToolWindowHeaderGeom);
var
  rowW, rowH, btn, bh, bt, sep, ovf, amin, x, fixedLeft, room, right, limit, n, i, k, w: Integer;
  plan: TTyToolWindowPlan;
  shown: array of Boolean;

  function ClampX(AValue: Integer): Integer;
  begin
    if AValue < 0 then Result := 0
    else if AValue > rowW then Result := rowW
    else Result := AValue;
  end;

  function Span(ALeft, ARight, ATop, ABottom: Integer): TRect;
  begin
    Result := Rect(ClampX(ALeft), ATop, ClampX(ARight), ABottom);
    if Result.Right < Result.Left then Result.Right := Result.Left;
  end;

begin
  rowW := AInput.RowWidth;
  rowH := AInput.RowHeight;
  { 负数入参一次钳干净(同 TyToolWindowVisiblePlan 的规矩)。 }
  btn := AInput.ButtonSize;      if btn < 0 then btn := 0;
  sep := AInput.SeparatorWidth;  if sep < 0 then sep := 0;
  ovf := AInput.OverflowWidth;   if ovf < 0 then ovf := 0;
  amin := AInput.TabAreaMin;     if amin < 0 then amin := 0;
  bh := btn;
  if bh > rowH then bh := rowH;
  bt := (rowH - bh) div 2;

  x := rowW - APad;
  AGeom.Collapse := Span(x - btn, x, bt, bt + bh);
  Dec(x, btn + AGap);
  AGeom.Maximize := Span(x - btn, x, bt, bt + bh);
  Dec(x, btn);
  AGeom.Separator := Span(x - sep, x, 0, rowH);
  Dec(x, sep);
  fixedLeft := x;

  room := fixedLeft - APad;
  if AActionsW > room - amin then AActionsW := room - amin;
  if AActionsW < 0 then AActionsW := 0;
  if AActionsW > 0 then
    AGeom.Actions := Span(fixedLeft - AActionsW, fixedLeft, 0, rowH);
  right := fixedLeft - AActionsW;
  if right < APad then right := APad;
  AGeom.TabArea := Span(APad, right, 0, rowH);

  n := Length(AInput.TabWidths);
  plan := TyToolWindowVisiblePlan(AGeom.TabArea.Right - AGeom.TabArea.Left,
    AInput.TabWidths, AInput.ActiveIndex, ovf);
  limit := AGeom.TabArea.Right;
  if Length(plan) < n then Dec(limit, ovf);
  if limit < AGeom.TabArea.Left then limit := AGeom.TabArea.Left;
  AGeom.Tabs := nil;
  SetLength(AGeom.Tabs, Length(plan));
  x := AGeom.TabArea.Left;
  for i := 0 to High(plan) do
  begin
    k := plan[i];
    w := AInput.TabWidths[k];
    if w < 0 then w := 0;
    if x + w > limit then w := limit - x;
    if w < 0 then w := 0;
    AGeom.Tabs[i].ItemIndex := k;
    AGeom.Tabs[i].ItemRect := Span(x, x + w, 0, rowH);
    Inc(x, w);
  end;

  AGeom.Hidden := nil;
  if Length(plan) < n then
  begin
    AGeom.Overflow := Span(x, x + ovf, bt, bt + bh);
    if AGeom.Overflow.Right > AGeom.TabArea.Right then
      AGeom.Overflow.Right := AGeom.TabArea.Right;
    if AGeom.Overflow.Right < AGeom.Overflow.Left then
      AGeom.Overflow.Right := AGeom.Overflow.Left;
    shown := nil;
    SetLength(shown, n);
    for i := 0 to High(plan) do shown[plan[i]] := True;
    for i := 0 to n - 1 do
      if not shown[i] then
      begin
        SetLength(AGeom.Hidden, Length(AGeom.Hidden) + 1);
        AGeom.Hidden[High(AGeom.Hidden)] := i;
      end;
  end;
end;
```

执行时核一遍表 B1–B10 的每个数都从这段代码算得出来（表是按这段代码算的；两边对不上，以「spec §7.3 + 问题 7 的建议」为准改代码，再改表）。

`TyToolWindowZoneAt` 声明在 interface 段 `TyToolWindowHeaderLayout` 下面，注释写明「是排布的精确逆运算，只扫排布产出的矩形；空矩形命不中」：

```pascal
function TyToolWindowZoneAt(const AGeom: TTyToolWindowHeaderGeom; X, Y: Integer;
  out AIndex: Integer): TTyToolWindowZone;
var
  pt: TPoint;
  i: Integer;
begin
  AIndex := -1;
  pt := Point(X, Y);
  for i := 0 to High(AGeom.Tabs) do
    if PtInRect(AGeom.Tabs[i].ItemRect, pt) then
    begin
      AIndex := AGeom.Tabs[i].ItemIndex;
      Exit(twzTab);
    end;
  if PtInRect(AGeom.Overflow, pt) then Exit(twzOverflow);
  if PtInRect(AGeom.Separator, pt) then Exit(twzSeparator);
  if PtInRect(AGeom.Maximize, pt) then Exit(twzMaximize);
  if PtInRect(AGeom.Collapse, pt) then Exit(twzCollapse);
  Result := twzNone;
end;
```

同时把 `TTyToolWindowZone` 上面那句「返回它的命中测跟底栏一起在 B 期落地」改成指向 `TyToolWindowZoneAt`。

- [ ] **Step 4: 跑 `TTyToolWindowGeometryTests`，全绿**

- [ ] **Step 5: 变异**

| 变异 | 必须红 |
|---|---|
| `limit` 不减 `ovf`（有东西收起时标签照旧排到标签区右沿） | B2 或 B4 |
| 操作区不压缩（删掉 `room - amin` 那句） | B4 |
| `ItemIndex := k` 改成 `ItemIndex := i` | B3、Z1 |
| `TyToolWindowZoneAt` 删掉分隔线那句 | Z1 |
| `LayoutBottomRow` 里 `Span` 不钳（直接 `Rect(...)`） | B5 |

- [ ] **Step 6: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.Layout.pas tests/test.toolwindow.geometry.pas && git commit -m "feat(toolwindows): bottom header row geometry and its hit-test inverse

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `ITyToolWindowHeaderHost` 与标题行输入的装配

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- （采纳问题 2 的建议时）Modify: `themes/light.tycss`；Regenerate: `source/tyControls.DefaultTheme.pas`、`source/tyControls.Css.Catalog.pas`；Modify: `tests/golden/*.golden.txt`
- Modify: `tests/test.toolwindow.bar.pas`（`TBarAccess.CallAlignControls`）
- Create: `tests/test.toolwindow.bottom.pas`
- Modify: `tests/tytests.lpr`

- [ ] **Step 1（采纳问题 2 时）: 分隔线改成线的写法**

先验生成器忠实度（[[gen-defaulttheme-eats-handwritten-code]]）：

```bash
cd /d/Projects/ty-3.1 && powershell -File scripts/gen-defaulttheme.ps1 && git diff --quiet -- source/tyControls.DefaultTheme.pas && echo FAITHFUL
```

不是 `FAITHFUL` 就停。然后把 light.tycss 里 `TyToolWindowSeparator { background: var(--border); }` 改成 `TyToolWindowSeparator { border-color: var(--border); border-width: 1px; }`，跑 `scripts/gen-defaulttheme.ps1`、`scripts/gen-tycss-catalog.ps1`，再跑 `TTestThemeGolden`：三张 `.actual` 逐个 diff，**只允许 `TyToolWindowSeparator` 那几行变**，确认后 `mv` 覆盖（命令同 A 期 Task 1 Step 10），再跑一次 `TTestThemeGolden` 必须全绿。

- [ ] **Step 2: 声明接口和底栏常量**

type 段开头（`TTyToolWindowBar = class;` 那组前向声明里）补 `TTyToolWindow = class;`，接口紧跟前向声明之后：

```pascal
  { 底栏标题行的宿主(spec §7.1 / §7.2)。标签行的像素属于当前页(窗口化子控件自己拥有那块像素),
    所以当前页替栏画、把输入转给栏;悬停、按下、溢出集合、最大化状态都在栏上。
    只有 TTyToolWindowBar 实现它。AWindow = nil 表示「栏坐标、当前页的标题行」(开工前问题 1);
    没有当前页时几何为空、部件为 none。尺寸一律按入参 APPI(同 RenderTo 的一套尺度)。 }
  ITyToolWindowHeaderHost = interface
    ['{DCDF22CA-27B6-47C8-87CC-7157244C477C}']
    function HeaderMode(AWindow: TTyToolWindow): TTyToolWindowHeaderMode;
    { 底栏统一行高里操作区那一项:栏里所有窗口操作区 raw 首选高的最大值(spec §3.4)。 }
    function HeaderActionsHeight(AWindow: TTyToolWindow; APPI: Integer): Integer;
    function HeaderGeometry(AWindow: TTyToolWindow; ARowWidth, ARowHeight,
      APPI: Integer): TTyToolWindowHeaderGeom;
    procedure PaintHeader(AWindow: TTyToolWindow; APainter: TTyPainter; const ARow: TRect;
      const AGeom: TTyToolWindowHeaderGeom; APPI: Integer);
    function HeaderZoneAt(AWindow: TTyToolWindow; X, Y: Integer; out AIndex: Integer;
      out ARect: TRect): TTyToolWindowZone;
    procedure HeaderMouseDown(AWindow: TTyToolWindow; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure HeaderMouseMove(AWindow: TTyToolWindow; Shift: TShiftState; X, Y: Integer);
    procedure HeaderMouseUp(AWindow: TTyToolWindow; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure HeaderMouseLeave(AWindow: TTyToolWindow);
    { 捕获者是当前页、它收到了 LM_CANCELMODE(spec §9.7)。 }
    procedure HeaderCancelMode(AWindow: TTyToolWindow);
    function HeaderHint(AWindow: TTyToolWindow; X, Y: Integer; out AText: string;
      out ARect: TRect): Boolean;
    procedure HeaderContextPopup(AWindow: TTyToolWindow; X, Y: Integer);
  end;
```

栏声明改成 `TTyToolWindowBar = class(TTyCustomControl, ITyToolWindowHeaderHost)`。接口方法一律放在栏的 **public** 段（接口调用本来就绕过可见性，放 private 反而让测试够不着）。本任务给出 `HeaderMode`、`HeaderActionsHeight`、`HeaderGeometry`、`HeaderZoneAt` 的真实实现。其余方法接口要求现在就得有实现体、否则编不过，所以**先留空体**，并在每个空体里写一行注释指明由哪个任务填：`PaintHeader` → Task 5；`HeaderMouseDown / Move / Up / Leave`、`HeaderCancelMode` → Task 6；`HeaderHint`、`HeaderContextPopup` → Task 8。这是本计划仅有的空体，Task 12 Step 1 逐个核它们都已填上。

常量段加：

```pascal
  TyToolWindowTabKey             = 'TyToolWindowTab';
  TyToolWindowSeparatorKey       = 'TyToolWindowSeparator';
```

并删掉「底栏那几个 … B 期接线时再加」那句注释里已经加了的两个名字（剩下的三个 Task 5 加）。

- [ ] **Step 3: 栏装配底栏输入**

- `TabWidthsAt(APPI): TTyToolWindowWidths`（private）：按窗口顺序，每个窗口 `Max(TyMeasureTextBlock 宽, TyMeasureRenderedTextWidth)`（Painter 的「两种量法取大」约定），字体取 `TyToolWindowTab` 在 `[tysNormal]` 与 `[tysSelected]` 下两份样式各量一次取大（问题 9），再加 `2 × TokenPxAt(TyToolWindowTabPadVar, TyToolWindowTabPadDef, APPI)`。空标题也有 2×tab-pad 宽。
- 标签宽缓存（问题 3）：只在 `APPI = PPI` 时走缓存；键 = (窗口引用, Caption) 按 Controls 顺序的快照数组 + PPI + model 身份 + ThemeVersion + `TyStyleClassFor(Self, StyleClass)` + `StyleOverride`，逐项比，任何一项不同就重量。别的 PPI 现量。
- `SeparatorLinePx(APPI)`（private）：`TyToolWindowSeparator` 按 `[tysNormal]` 解析，`TyBorderVisible` 为真时 `Max(1, MulDiv(BorderWidth, APPI, 96))`，否则 0（问题 2 备选方案下改成 `Max(1, MulDiv(1, APPI, 96))`）。
- `HeaderInputFor(AWindow; ARowWidth, ARowHeight, APPI): TTyToolWindowHeaderInput`（private）：`Result := AWindow.HeaderInput(APPI, ARowWidth)`（公共字段：模式、行宽、Pad、Gap、操作区宽、RTL）；`RowHeight := ARowHeight`；底栏再补 `TabWidths := TabWidthsAt(APPI)`、`ActiveIndex := IndexOfWindow(FActive)`、`TabAreaMin := TokenPxAt(TyToolWindowTabAreaMinVar, …)`、`ButtonSize := TokenPxAt(TyToolWindowButtonSizeVar, …)`、`OverflowWidth := ButtonSize`、`SeparatorWidth := 2 × Gap + SeparatorLinePx(APPI)`。
- `HeaderGeometry(AWindow, …)`：`AWindow = nil` 时取 `FActive`，还是 nil 就返回 `Default(TTyToolWindowHeaderGeom)`；否则 `TyToolWindowHeaderLayout(HeaderInputFor(…))`。
- `HeaderMode(AWindow)`：侧 / 底按 `FPlacement`。窗口原来的 `TTyToolWindow.HeaderMode` 改成「`Bar` 为 nil → `twhNone`，否则问 `Bar.HeaderMode(Self)`」——「在不在栏里」仍然只由 `GetBar` 回答（问题 5）。
- `HeaderZoneAt(AWindow, X, Y, AIndex, ARect)`：几何取当前页此刻的客户区（`HeaderGeomAt(Rect(0, 0, W.ClientWidth, W.ClientHeight), W.Font.PixelsPerInch)`），`TyToolWindowZoneAt` 之后把命中部件的矩形放进 `ARect`（窗口坐标）；`AWindow = nil` 时入参是栏坐标，先减当前页 `Left / Top`，出参再加回去。
- `HeaderActionsHeight(AWindow, APPI)`：栏里每个窗口 `ActionsPreferredSize(APPI).cy` 的最大值（`ActionsPreferredSize` 是窗口的 private，同单元可调）。**本任务就实现它**，但窗口要到 Task 4 才用它。

- [ ] **Step 4: 窗口的底栏模式改问栏**

- `TTyToolWindow.HeaderGeomAt`：`HeaderMode = twhBottom` 时 `Result := Bar.HeaderGeometry(Self, row 宽, row 高, APPI)`（行仍由 `HeaderRowIn` 钳），否则照旧。`CustomAlignPosition` 已经经 `HeaderGeomAt` 摆操作区，不用改；`AlignControls` 比较的 `TyToolWindowSameGeom` 已经覆盖全部字段，也不用改。
- 注释里「底栏模式由栏统一算(B 期)」「twhBottom 那一支标题行排布在 B 期」这类话，改成现在的事实。

- [ ] **Step 5: 新测试单元与夹具**

`tests/test.toolwindow.bottom.pas`：`TTyToolWindowBottomTests = class(TTyToolWindowBarFixture)`，uses 抄 `test.toolwindow.strip` 那一串。夹具帮手 `NewBottomBar(const ACaptions: array of string; AActive: Integer)`：先把 `FBar.Placement := twpBottom`（**先设 Placement 再加窗口**——运行时有窗口时侧 ↔ 底被忽略）、`FBar.Width := 600`、按标题建窗口（标题长短不一，地雷 12）、设当前页，再 `FBar.CallAlignControls`（`TBarAccess` 新加，照 `TProbeWindow.CallAlignControls`：`GetClientRect → AdjustClientRect → AlignControls`），窗口才有真实边界。挂进 `tests/tytests.lpr` 的 uses（`test.toolwindow.reorder,` 后面，用编辑工具改，别用 sed）。

- [ ] **Step 6: 写测试（判据）**

| 判据 | 在哪个变异下必须红 |
|---|---|
| 底栏当前页的操作区（`EnsureActions` + 一个定宽子控件）经 `CallAlignControls` 之后，`BoundsRect` 等于 `HeaderGeomAt(...).Actions`；并且它在**底栏**的位置（左边是标签区、右边是分隔线），不是侧栏那个贴右端的位置 | `HeaderGeomAt` 的底栏分支删掉（退回侧栏排布） |
| 把一个非当前页的 `Caption` 改长，当前页几何里那个标签变宽、它后面的标签右移 | 标签宽缓存的键里去掉 Caption |
| `StyleOverride` 把 `--toolwindow-tab-pad` 从 10 改 14：每个标签宽 +8 | `TabWidthsAt` 不读 tab-pad（写死 Def） |
| `--toolwindow-button-size` 从 22 改 30：收起按钮左沿左移 8，最大化再左移 8 | 装配时 `ButtonSize` 写死 Def |
| `--toolwindow-tab-area-min` 调大到逼操作区压缩：操作区宽变小、标签区宽等于新 token | 装配时 `TabAreaMin` 写死 Def |
| 换 model 或换主题（`ThemeVersion` 变）之后标签宽跟着字体变（用一个把 `TyToolWindowTab` 字号改大的 `StyleOverride`） | 缓存键去掉 ThemeVersion |
| 直接 `SetControlIndex` 调换两个窗口（不经 `ReorderWindow`），当前页几何里标签顺序跟着换 | 缓存键改成只比长度、不比窗口引用 |
| 皮肤只让选中态加粗（`TyToolWindowTab:selected { font-weight: 700 }`）：切页前后每个标签宽一样 | `TabWidthsAt` 只按 `[tysNormal]` 量 |
| （采纳问题 2 时）`TyToolWindowSeparator` 的 border-width 改 3：分隔线槽宽 = 2×gap + 3 | `SeparatorLinePx` 写死 1 |
| `HeaderZoneAt(nil, …)`（栏坐标）在当前页某个标签中心（窗口坐标 + `Left/Top`）答 `twzTab` 和那个窗口序号，`ARect` 是栏坐标 | 忘了减 / 加 `Left/Top` |

- [ ] **Step 7: 跑** `TTyToolWindowGeometryTests TTyToolWindowTests TTyToolWindowActionsTests TTyToolWindowBarTests TTyToolWindowBottomTests`（采纳问题 2 时再加 `TTestThemeGolden TTyToolWindowThemeTests`），全绿；上表变异逐条做。

- [ ] **Step 8: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.bar.pas tests/test.toolwindow.bottom.pas tests/tytests.lpr && git commit -m "feat(toolwindows): the bar hosts the bottom header row and feeds its geometry

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

（采纳问题 2 时把 `themes/light.tycss source/tyControls.DefaultTheme.pas source/tyControls.Css.Catalog.pas tests/golden` 一起 add，提交信息正文加一句 `The tab-row separator is a themed rule (border-color/border-width) like the edge line.`）

---

### Task 4: 底栏统一行高与操作区的变化通知（spec §3.4）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.bottom.pas`

- [ ] **Step 1: 行高改问栏**

`TTyToolWindow.HeaderHeightAt`：token 那一项照旧（自己的缓存，地雷 6）；操作区那一项在 `HeaderMode = twhBottom` 时取 `Bar.HeaderActionsHeight(Self, APPI)`，侧栏照旧取自己的（加底线）。底栏没有底线（`HeaderRuleUncached` 已经只在侧栏答非 0）。

- [ ] **Step 2: 通知链**

- `TTyToolWindowActions` 重写 `AdjustSize`（`controls.pp:1640` 的虚方法）：`inherited`；`InvalidatePreferredSize`（子控件只改 `Constraints` 时缓存不失效，`control.inc:1520-1522`）；算 `PreferredSizeAt(Font.PixelsPerInch)`，和上次记下的比，变了就记下并通知所在窗口的栏（`Parent is TTyToolWindow` 且它的 `Bar <> nil`）：`Bar.ActionsSizeChanged`。
- `TTyToolWindowBar.ActionsSizeChanged`（private）：csLoading / csDestroying 时跳过；只在底栏做；算 `HeaderActionsHeight(nil, PPI)`，和上次**用过的**值（新字段 `FBottomActionsPx`）比，变了就记下并带重入保护对**当前页** `RelayoutHeader`（非当前页在激活第 4 步 `RelayoutHeader` 时现取，spec §3.4）。
- 窗口列表变了也要重算：`RegisterWindow` / `UnregisterWindow` 末尾（底栏）调同一个 `ActionsSizeChanged`。
- 先查：`AdjustSize` 在无头下对**隐藏窗口里**的操作区是否调得到（spec §3.4 引的 `wincontrol.inc:6416, 6459`、`control.inc:731-732, 4639-4640`）。无头调不到就把第二条测试挪进 `test.toolwindow.focus` 的真句柄夹具，并在代码注释里写明查到的行号。

- [ ] **Step 3: 写测试（判据）**

| 判据 | 在哪个变异下必须红 |
|---|---|
| 两页操作区首选高不同（一个 20、一个 40 的子控件），两页的 `HeaderRowRect` 高相同且等于 40（> token），来回切页不变 | 底栏也只按本窗口操作区算行高 |
| 运行时往**非当前页**的操作区加一个比共用行高更高的子控件：**不切页**，当前页的 `HeaderRowRect` 立刻变高、正文 `BodyRect.Top` 跟着下移；把它藏掉，立刻变回原高 | `TTyToolWindowActions.AdjustSize` 不通知栏 |
| 往底栏加一个操作区很高的新窗口（它不是当前页时）：当前页行高立刻跟上 | `RegisterWindow` 末尾不重算 |
| 操作区子控件只改 `Constraints.MinHeight`（不改 `Height`）也跟上 | 删掉 `InvalidatePreferredSize` |
| 换主题之后，窗口仍然察觉 token 变化并重排（A 期那条 `TestThemeChangeRelayoutsTheBody` 的底栏版：底栏窗口、改 `--toolwindow-header-height`、断言重排次数 > 0 且行高变了） | 栏在自己的 `Invalidate` 里替窗口读 `HeaderTokenPx`（地雷 6 的反例，做一次看它红） |

- [ ] **Step 4: 跑** `TTyToolWindowTests TTyToolWindowActionsTests TTyToolWindowBarTests TTyToolWindowBottomTests`，全绿；变异逐条。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/ && git commit -m "feat(toolwindows): the bottom tab row shares one height across pages

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 标签行绘制（`PaintHeader`）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.bottom.pas`

- [ ] **Step 1: 常量**

```pascal
  TyToolWindowTabRowKey          = 'TyToolWindowTabRow';
  TyToolWindowTabIndicatorKey    = 'TyToolWindowTabIndicator';
  TyToolWindowButtonKey          = 'TyToolWindowButton';
```

删掉「底栏那几个 … B 期接线时再加」那整句注释。

- [ ] **Step 2: 窗口的 `RenderTo` 接上**

`HeaderMode = twhBottom`、行非空、**`IsActive`** 时：`g := HeaderGeomAt(R, APPI)`，`Bar.PaintHeader(Self, P, hdr, g, APPI)`。非当前页不画（它是藏着的；设计期也是 csNoDesignVisible）。

- [ ] **Step 3: 栏的 `PaintHeader`**（`ARow` 是窗口 (0,0)-local 坐标；一切在 `P.EndPaint` 之前画进 BGRA 层，[[painter-bgra-overwrites-canvas-gdi]]）

1. 标签行底色：`TyToolWindowTabRow` 的 background 铺满 `ARow`。
2. 每个 `AGeom.Tabs[i]`：状态——是当前页只用 `[tysSelected]`（spec §12）；否则悬停中 `[tysHover]`，否则 `[tysNormal]`；栏禁用时 `[tysDisabled]`（当前页仍 `[tysSelected]`，同图标条）。有 background 就铺；文字画在标签矩形左右各内缩 tab-pad 的框里，`taCenter` / `tlCenter`，**省略号开**（只有被截的当前页标签会真的出省略号）。
3. 下划线：当前页那个标签，`TyToolWindowTabIndicator` 的 background，粗细 `TokenPxAt(TyToolWindowIndicatorSizeVar, …, APPI)`（0 = 不画），贴标签矩形底边，横向跨文字框（标签矩形左右各内缩 tab-pad）。
4. 溢出按钮（非空时）：`TyToolWindowOverflow` 按 `[hover / active / normal / disabled]` 解析，底色 + 字形（问题 6：`tgChevronDown`），字形边长 `--toolwindow-glyph-size`，墨色取这个键自己的 color（spec §12：这里的 color 就是给标签行用的）。
5. 分隔线：`TyToolWindowSeparator`，`SeparatorLinePx(APPI)` 宽的一条竖线，居中在分隔线槽里，纵向跟按钮带同高。
6. 最大化、收起：`TyToolWindowButton` 按状态解析，底色 + 字形（最大化 `tgMaximize`，Task 7 起最大化时换 `tgRestore`；收起 `tgMinimize`）。
7. 插入线（Task 9 接上，本任务不画）。

按下态：部件的 `tysActive` 从引擎读（`FGesture.State = twgsArmed` 且 `FGesture.Capturer` 是这个窗口、`FGesture.Part` 是这个部件），不另记字段。悬停态在栏上新加 `FHeaderHoverPart: TTyToolWindowBarPart; FHeaderHoverIndex: Integer`（Task 6 写它；本任务只读）。

- [ ] **Step 4: 当前页跟着变——`InvalidateHeader`**

栏上加 private `InvalidateHeader`：底栏且 `FActive <> nil` 时 `FActive.Invalidate`（丢窗口缓存）。以下每一处都调它（每一处一条判据，见 Step 5）：任一窗口 `Caption` 变（`TTyToolWindow.TextChanged` 里，底栏时通知栏）；`ReorderWindow`、`SetChildOrder`；`RegisterWindow` / `UnregisterWindow`；`SetEnabled` 引起的 `CMEnabledChanged`；以及 Task 6–9 的悬停、按下、最大化、插入线变化。

- [ ] **Step 5: 写测试（判据，像素一律哨兵底色，地雷 13）**

主题钉法：控制器 `StyleOverride` 里把 `--toolwindow-header-bg` 刷成品红、`--toolwindow-tab-ink` 蓝、`--toolwindow-tab-ink-selected` 黄、`--toolwindow-indicator-color` 黑，分隔线颜色另挑一个。三个标题长短不一，当前页是第二个。

| 判据 | 在哪个变异下必须红 |
|---|---|
| 下划线色的像素只出现在当前页标签的底边那几行里；其他标签底边一个都没有 | 对每个标签都画下划线 |
| 下划线贴在底边，不在顶边 | 下划线画在标签顶边 |
| `--toolwindow-indicator-size` 改 4：下划线行数随之变 | 下划线粗细写死 Def |
| 黄墨（选中）只在当前页标签框里；蓝墨（静止）只在其他标签框里 | 当前页按 `[tysHover]` 或 `[tysNormal]` 解析 |
| 非当前页窗口 `CallRenderTo` 画出来的标题行里没有任何标签墨色 | 去掉 `IsActive` 门 |
| 有标签收起时溢出按钮框里有字形墨色；全放得下时那一块是底色 | 溢出不看 `AGeom.Overflow` 是否为空、总是画 |
| 分隔线槽中间那一列有分隔线色；槽两侧 gap 是底色 | 线画满整个槽宽 |
| RTL（`BiDiMode := bdRightToLeft`）下，下划线落在**镜像后**的当前页标签框里 | `PaintHeader` 用未镜像的矩形（执行时临时把窗口 RTL 位关掉只给几何，看它红） |
| 按 144 PPI `CallRenderTo`，标签宽和按钮尺寸都按 144 缩放（同 `TestRenderingAtAnotherPpiScalesTheWholeGeometry`） | `TabWidthsAt` 用 `PPI` 而不是入参 `APPI` |
| 改一个**非当前页**的 `Caption` 之后，当前页 `CacheWouldRender` 为真 | `TextChanged` 不通知栏 |
| `WindowIndex` 调顺序之后，当前页 `CacheWouldRender` 为真 | `ReorderWindow` 不调 `InvalidateHeader` |

- [ ] **Step 6: 跑** `TTyToolWindowTests TTyToolWindowBarTests TTyToolWindowStripTests TTyToolWindowBottomTests`，全绿；变异逐条。

- [ ] **Step 7: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.bottom.pas && git commit -m "feat(toolwindows): the active page paints the bottom tab row for its bar

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 标签行输入转发与标签点击（spec §3.6 运行时、§7.4、§9.3 底栏）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.window.pas`（`TProbeWindow` 加输入探针）
- Modify: `tests/test.toolwindow.bottom.pas`（新 suite `TTyToolWindowBottomInputTests`）

**标签行区域** = 标题行矩形减去操作区矩形（窗口坐标，含标签之间和后面的空白）。窗口上加 private `InTabRowRegion(X, Y): Boolean`（底栏模式且在栏里才可能为真），一处答，下面所有判断都问它。

- [ ] **Step 1: 部件枚举与悬停**

- `TTyToolWindowBarPart` 加 `twbpMaximize, twbpCollapse, twbpSeparator`；加 private `PartOfZone(TTyToolWindowZone): TTyToolWindowBarPart`（`twzTab → twbpItem`、`twzOverflow → twbpOverflow`、其余一一对应、`twzNone → twbpNone`）。**图标和标签共用 `twbpItem`、两种溢出共用 `twbpOverflow`**：一条栏只会有其中一种，手势引擎和点击分派因此不用分两套。
- 栏坐标的 `PartAt(X, Y, AIndex)`：底栏且有当前页时，在原有判断之前先问 `HeaderZoneAt(nil, X, Y, idx, r)`，映射成 `PartOfZone`（标签时 `AIndex = idx`）；侧栏不变。于是 `WindowAtPos` 在栏坐标的标签上答那个窗口（spec §6.8「不在图标 / 标签上返回 nil」），Task 8 的右键和 Task 10 的设计期都靠它。运行时栏自己收不到标签行上的按下（当前页盖着），这一段只服务栏坐标的查询。
- 栏上 `SetHeaderHover(APart, AIndex)`：变了才写，并 `InvalidateHeader`。`UnregisterWindow` 里清掉（同 `FStripHover` 的处理）。切页后（`SwitchCore` 末尾的 `RecheckHover`）底栏也要重查：指针在当前页客户区里就按 `HeaderZoneAt` 重算，不在就清。
- 引擎回调的 `GestureCleared`（Task 1）在底栏时也调 `InvalidateHeader`：按下态是从引擎读的，收尾之后当前页得重画掉它。

- [ ] **Step 2: 栏的 `HeaderMouse*`（坐标一律是窗口客户区）**

- `HeaderMouseDown(W, Button, Shift, X, Y)`：`W <> FActive` 或栏 `not IsEnabled` → 什么都不做（本计划的决定：禁用的栏不武装，和图标条一致——LCL 不给禁用控件发鼠标消息；Task 12 写回 spec §3.6）。左键：先 `ResetGesture(twgeDiscard)`；`zone := HeaderZoneAt(W, X, Y, idx, r)`；`twzTab` → `FGesture.Press(twbpItem, Windows[idx], True, W, X, Y, Shift)`；溢出 / 最大化 / 收起 → `FGesture.Press(对应部件, nil, False, W, X, Y, Shift)`；分隔线、none → 不武装。按下后 `InvalidateHeader`。**按下什么都不激活**。
- `HeaderMouseMove(W, Shift, X, Y)`：`W <> FActive` → 忽略（spec §7.1：旧页迟到的消息不许清新页的悬停）。`case FGesture.Move(Shift, X, Y) of twgmHover: 按 HeaderZoneAt 设悬停; twgmDragStart: 清悬停 + HeaderDragTo（Task 9，本任务先只清悬停）; twgmDrag: HeaderDragTo（Task 9）; else ; end`。
- `HeaderMouseUp(W, Button, Shift, X, Y)`：左键才处理；拖动中的落点 Task 9 加；`zone := HeaderZoneAt(...)`；`rel := FGesture.Release(PartOfZone(zone), 标签时 Windows[idx] 否则 nil)`；重设悬停；然后**最后一句**分派：`twrClick` 且部件 `twbpItem` 且窗口不是当前页 → `ActivateWindow(rel.Window)`；是当前页 → 什么都不做（spec §9.3 底栏标签）。溢出 / 收起 / 最大化的分派在 Task 7、8 加到这个 `case` 里。
- `HeaderMouseLeave(W)`：`W = FActive` 时清悬停；**从不解除武装**（spec §9.2）。
- `HeaderCancelMode(W)`：`FGesture.Capturer = W` 时 `ResetGesture(twgeCancel)`。

- [ ] **Step 3: 窗口这一侧**

- `WndProc`：`LM_LBUTTONDOWN` / `LM_LBUTTONDBLCLK` 到来时先记 `FPressInRow := InTabRowRegion(消息坐标)` 和坐标（照栏的 `FAutoDragPos`），再走继承（地雷 10）。
- `MouseDown`：`InTabRowRegion` 为假 → 继承。为真 → **不调继承**；`HeaderZoneAt` 不是 none 才转发 `Bar.HeaderMouseDown`，左键时置 `FHeaderGesture := True`；none 只吞。区域内从不 `SetFocus`（窗口本来就 csNoFocus，别另加）。
- `MouseMove`：`FHeaderGesture` → 一律转发 `HeaderMouseMove`（不论位置）；否则在区域里且部件不是 none → 转发 `HeaderMouseMove`；在区域里但 none、或出了区域 → 转发 `HeaderMouseLeave`（清悬停，不违反「none 只吞不转」）。**然后照常调继承**（spec 只要求吞 Down / Up / Click / DblClick / 右键 / 滚轮）。
- `MouseUp`：按问题 8 的建议——`FPressInRow` 为真 → 不调继承；`FHeaderGesture` 为真时清掉它并转发 `HeaderMouseUp`；否则继承。转发放在**最后一句**（它可能把本窗口藏起来，地雷 9）。
- `Click` / `DblClick`：`FPressInRow` 为真 → 吞。
- `MouseLeave`：继承，然后 `HeaderMouseLeave`。
- `DoMouseWheel`：区域内返回 True、不调继承。先查 `MousePos` 的坐标系：`TControl.WMMouseWheel` 里是 `GetMousePosFromMessage`（`control.inc:1931-1940`，控件宽高 ≤ 32767 时直接用消息坐标）——再查 `win32callback.inc` 的 `WM_MOUSEWHEEL` 分支确认消息坐标已经换成客户区；查不实就改用 `ScreenToClient(Mouse.CursorPos)`，注释里写明查到的行号。
- `DoContextPopup`：`MousePos` 在区域内 → `Handled := True`，**不调继承**；落在标签上时再调 `Bar.HeaderContextPopup`（Task 8 填它的实现）。键盘菜单键的 `(-1, -1)` 不在区域里，走继承。
- `BeginAutoDrag`：按 `WndProc` 记下的按下坐标（没有就问指针）判区域，区域内直接返回；否则调新加的 protected virtual `StartLclAutoDrag`（照栏，测试重写它数次数）。
- `LM_CANCELMODE`：继承；`FHeaderGesture` 为真时清掉并 `Bar.HeaderCancelMode(Self)`。

- [ ] **Step 4: 探针**

`TProbeWindow` 加：`CallMouseDown(X, Y; AShift = [ssLeft])`、`CallMouseMove`、`CallMouseUp`、`CallMouseLeave`、`CallClick`、`CallDblClick`、`CallDoContextPopup`、`CallDoMouseWheel`、`CallBeginAutoDrag`、`AutoDragStarts`（重写 `StartLclAutoDrag` 计数）、`SimulatePress(X, Y)`（`Perform(LM_LBUTTONDOWN, MK_LBUTTON, 坐标)`：走 `WndProc` → LCL 的 `WMLButtonDown` → `MouseDown` 整条真实路径，`FPressInRow` 由真实代码记下；需要它的测试用它**代替** `CallMouseDown`，别两个都调）。都是转发到 protected 方法，不另算。先试 `SimulatePress` 无头走不走得通（`Perform` 不要句柄，但 `WMLButtonDown` 里抓捕获那一步要看）；走不通，用它的几条挪进 `test.toolwindow.focus` 的真句柄夹具。

- [ ] **Step 5: 写测试（判据，`TTyToolWindowBottomInputTests`）**

| 判据 | 在哪个变异下必须红 |
|---|---|
| 在非当前页标签上按下：当前页不变；在同一标签上松开：切过去 | 把 `ActivateWindow` 挪到 `HeaderMouseDown` |
| 按在标签 A、松开在标签 B：不切 | `Release` 判点击不比窗口 |
| 点当前页的标签：`ActiveWindow`、`Collapsed` 都不变，`OnChange` 不发 | 分派改成 `StripClick`（会切换收起） |
| `[ssLeft, ssDouble]` 的按下再松开：不切 | `Press` 不记多击 |
| 用户挂在窗口上的 `OnMouseDown` / `OnMouseUp` / `OnClick` 在标签行按下松开时一个都不触发；在正文里照常触发 | `MouseDown` 区域内也调继承；`Click` 不看 `FPressInRow` |
| 按在正文、松开在标签行：`OnMouseUp` 照常触发（问题 8） | `MouseUp` 按松开位置判区域 |
| 标签行里的滚轮：`DoMouseWheel` 返回 True，用户 `OnMouseWheel` 不触发；正文里照常 | 删掉 `DoMouseWheel` 重写 |
| `DragMode := dmAutomatic`：`SimulatePress` 在标签行 + `CallBeginAutoDrag` → `AutoDragStarts = 0`；正文里 → 1 | `BeginAutoDrag` 不看按下坐标、只问指针（测试里指针放在正文） |
| 切页之后，旧页（已藏）迟到的 `HeaderMouseLeave` 不清掉新页此刻的悬停 | `HeaderMouseLeave` 不判 `W = FActive` |
| 标签上按下、当前页收到 `LM_CANCELMODE`、再在同一标签上松开：不切 | 窗口不转发 `HeaderCancelMode` |
| 在标签上武装、那个标签的窗口被释放、在原位置松开：不切，当前页不变，不 AV（地雷 14） | `UnregisterWindow` 不因手势窗口离开而收尾 |
| 栏 `Enabled := False` 后标签上按下松开：不切 | `HeaderMouseDown` 不判 `IsEnabled` |
| 悬停：移到标签 k 上，`FHeaderHoverIndex = k`（探针读栏的真实字段），当前页 `CacheWouldRender` 为真 | 悬停变化只 `Bar.Invalidate`、不 `InvalidateHeader` |
| 栏坐标（标签中心 + 当前页 `Left/Top`）的 `WindowAtPos` 答那个标签的窗口；标签行空白处答 nil | `PartAt` 不认底栏标签 |
| 标签上按下再松开（点击完成）之后，当前页 `CacheWouldRender` 为真（按下态要被重画掉） | `GestureCleared` 底栏时不 `InvalidateHeader` |
| 切页之后悬停按指针重查（`FakePointer` 放在另一个标签上） | 底栏不走 `RecheckHover` |

- [ ] **Step 6: 跑** `TTyToolWindowTests TTyToolWindowBarTests TTyToolWindowStripTests TTyToolWindowReorderTests TTyToolWindowBottomTests TTyToolWindowBottomInputTests`，全绿；变异逐条。图标条的 suite 要一起跑：`TTyToolWindowBarPart` 加了成员，`PartAt` 和 `Click` 吞点击的判断不许被连带改坏。

- [ ] **Step 7: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/ && git commit -m "feat(toolwindows): the tab row forwards its input to the bar and switches on release

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 最大化 / 还原（spec §6.4）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.bottom.pas`、`tests/test.toolwindow.focus.pas`

- [ ] **Step 1: 状态与推导**

- 栏加 `FMaximized` 和 public `property Maximized: Boolean read FMaximized write SetMaximized;`（**不 published**：只在运行时有、不进 .lfm，spec §6.4）。
- `SetMaximized(AValue)`：值没变 → 返回；要设 True 而（非底栏、csDesigning / csLoading / csDestroying、`FCollapsed`、`WindowCount = 0`）任一成立 → 返回（问题 10）。否则 `ResetGesture(twgeCancel)`（拉宽中被改 = 结束拉宽回起点，spec §6.3）→ 写字段 → `Relayout` → 当前页 `RelayoutHeader` → `InvalidateHeader`（字形换了）。
- 推导：`DerivedAxisPx(AM)` 里，底栏、`FMaximized` 且不按收起算尺寸时，内容项换成新的 `MaximizedContentPx(AM)`（问题 4 的规则），否则照旧 `NarrowedContentPx`。**`ExpandedSize` 从头到尾不写**。父控件 OnResize 已经订阅着（`ParentResized` → `DeriveSize`），不另订阅（问题 4）。
- 先还原的地方（spec §6.4）：`SetCollapsed(True)` 开头；`UnregisterWindow` 里窗口数降到 0；栏的 `SetParent` 在继承之前；`SetPlacement` 开头。都是 `Maximized := False`（它自己 `RelayoutHeader`）。
- 边缘区：最大化期间 `PartAt` 不答 `twbpEdge`、`BeginEdgeDrag` 的守卫加 `FMaximized`、悬停不借调整光标；`LayoutAt` 里 `Edge` 照旧（那条贴编辑区的线照画）。
- 点击分派：`HeaderMouseUp` 的 `case` 加 `twbpMaximize: Maximized := not FMaximized;`。
- `PaintHeader`：最大化时最大化按钮画 `tgRestore`。

- [ ] **Step 2: 写测试（判据）**

无头（`TTyToolWindowBottomTests`）：

| 判据 | 在哪个变异下必须红 |
|---|---|
| 父控件客户区高 400、另有一个 30 高的 alTop 非栏兄弟和一个 alClient 兄弟：`Maximized := True` 后栏 `Height = 370`；`ExpandedSize` 不变 | `MaximizedContentPx` 不扣非栏兄弟；或推导仍走 `NarrowedContentPx` |
| 还原后 `Height` 回到按 `ExpandedSize` 推的值 | 还原不 `Relayout` |
| 最大化时 `Collapsed := True`：`Maximized` 读回 False；再展开，高度是还原高度 | `SetCollapsed` 不先还原 |
| 侧栏、设计期、空底栏、收起着：`Maximized := True` 读回 False | 去掉对应守卫（逐个） |
| `Maximized` 不在 published 属性里（`GetPropInfo` 为 nil），流式往返不出现 | 误写成 published |
| 最大化期间在边缘区按下拖动：`ExpandedSize` 不变，`IsEdgeDraggingForTest` 为假 | `BeginEdgeDrag` 不判 `FMaximized` |
| 拉宽中途设 `Maximized := True`：`ExpandedSize` 回到起点 | `SetMaximized` 不 `ResetGesture` |
| 在最大化按钮上按下、同一按钮上松开：`Maximized` 翻转；按在按钮、松开在别处：不变；`[ssDouble]` 的按下：不变（spec §7.4） | 分派不看 `rel.Kind = twrClick` |
| 最大化后最大化按钮框里的字形像素和最大化前不同（`tgRestore` 对 `tgMaximize`） | `PaintHeader` 不看 `FMaximized` |
| 最大化之后当前页 `CacheWouldRender` 为真 | `SetMaximized` 不 `InvalidateHeader` |

真句柄（`test.toolwindow.focus`，窗体 OnResize 排队发，地雷 11）：

| 判据 | 在哪个变异下必须红 |
|---|---|
| 最大化后把窗体拉高 100，抽消息之后栏高度也多 100，`ExpandedSize` 不变 | `MaximizedContentPx` 用最大化那一刻记下的值、不按此刻父控件算 |

- [ ] **Step 3: 跑** `TTyToolWindowBarTests TTyToolWindowEdgeTests TTyToolWindowFocusTests TTyToolWindowStreamingTests TTyToolWindowBottomTests TTyToolWindowBottomInputTests`，全绿；变异逐条。

- [ ] **Step 4: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/ && git commit -m "feat(toolwindows): the bottom bar maximizes over its siblings at run time

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 溢出菜单、收起按钮、提示、右键

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `source/tyControls.StrConsts.pas`、`languages/tyControls.StrConsts.pot`、`languages/tycontrols.strconsts.zh_CN.po`
- Modify: `tests/test.toolwindow.bottom.pas`、`tests/test.toolwindow.strip.pas`（溢出锚点表）、`tests/test.toolwindow.focus.pas`

- [ ] **Step 1: 四条 resourcestring**

`StrConsts.pas` 里 `rsTyToolWindowBarStray` 后面加（注释照上面几条的写法说明用在哪）：

```pascal
  { Hints on the bottom bar's tab row (TTyToolWindowBar.HeaderHint). }
  rsTyToolWindowMaximize = 'Maximize';
  rsTyToolWindowRestore  = 'Restore';
  rsTyToolWindowCollapse = 'Hide';
  rsTyToolWindowMore     = 'More';
```

`.pot` 和 `zh_CN.po` 照 A 期那四条的格式各加四条（`#: tycontrols.strconsts.rstytoolwindowmaximize` …），中文：最大化 / 还原 / 收起 / 更多。**每条 msgstr 都要非空**（[[empty-po-entry-blocks-startup]]）。用编辑工具改，别 sed。

- [ ] **Step 2: 溢出菜单**

- `OverflowWindows`：底栏时返回当前页此刻几何的 `Hidden`（没有当前页时空）；侧栏照旧。`ShowOverflowMenu` 其余不变。
- `TyToolWindowOverflowMenuAnchor` 加 `twpBottom` 分支（问题 7）：锚点 = 溢出按钮的 `(阅读起点那一侧, Bottom)`（LTR 左沿、RTL 右沿），对齐 `paLeft`。
- 底栏弹出时溢出按钮矩形在**当前页**坐标里，`ClientToScreen` 用当前页的；`PopupComponent` 仍是栏；只在当前页 `HandleAllocated` 时弹。
- 分派：`HeaderMouseUp` 的 `case` 加 `twbpOverflow: ShowOverflowMenu;`。菜单项的动作照旧（激活、展开），不受防抖限制。

- [ ] **Step 3: 收起按钮**

分派加 `twbpCollapse: Collapsed := True;`（最后一句：它会藏掉捕获者自己，地雷 9）。

- [ ] **Step 4: 提示**

- 栏 `HeaderHint(W, X, Y, AText, ARect)`：`HeaderZoneAt` 命中标签 → `StripHintText(那个窗口)`（`StripHint`，空则 `Caption`，**不用 `Hint`**）；溢出 → `rsTyToolWindowMore`；最大化 → 按 `FMaximized` 选 `rsTyToolWindowRestore` / `rsTyToolWindowMaximize`；收起 → `rsTyToolWindowCollapse`；分隔线、none → False。`ARect` 是那个部件的矩形（窗口坐标）。
- 窗口 `CM_HINTSHOW`：`CursorPos` 在标签行区域里 → 问 `Bar.HeaderHint`；答 True → 填 `HintStr`、`CursorRect`、`Result := 0`；答 False → `Result := 1`（不显示），`CursorRect := Rect(X, Y, X + 1, Y + 1)`（挪一下就重新问）。区域外走继承。**不改窗口的 `ShowHint`**（spec §3.6）。

- [ ] **Step 5: 右键**

栏 `HeaderContextPopup(W, X, Y)`：命中标签才做——把点换成栏坐标（`X + W.Left, Y + W.Top`），调栏**自己重写的** `DoContextPopup(栏坐标点, handled)`：Task 6 起 `PartAt` / `WindowAtPos` 在栏坐标里认得标签，所以它会把 `FContextWindow` 设成那个窗口、不挡菜单、按栏坐标触发 `OnContextPopup`（spec §6.8 的同一条路，不另写一份）。`DoContextPopup` 只发事件、不弹菜单（弹菜单是 LCL 的 `WM_CONTEXTMENU` 处理在它之后做的，这里没有那一层），所以之后自己补：`handled` 仍为 False、`GetPopupMenu` 非 nil 且 `AutoPopup` → `PopupComponent := Self; PopUp(屏幕坐标)`；只在当前页 `HandleAllocated` 时弹。溢出、分隔线、按钮、空白上的右键：窗口那边已经吞了，栏什么都不做。

- [ ] **Step 6: 写测试（判据）**

| 判据 | 在哪个变异下必须红 |
|---|---|
| 溢出按钮上按下、同处松开：`OverflowMenu` 的项恰好是收起的那几个窗口的标题（按窗口顺序），不含当前页 | `OverflowWindows` 底栏仍按图标条 `BarLayout` 算（空） |
| 点溢出菜单的项：那个窗口成为当前页 | — （A 期已守，跑一遍底栏版确认） |
| `[ssDouble]` 按在溢出 / 收起上再松开：不弹菜单、不收起 | 分派不看 `rel.Kind` |
| 收起按钮上按下：不收起；同处松开：`Collapsed = True`，当前页 `Visible = False`，栏 `Height = 0`（spec §14「底栏收起后当前页不可见」） | 收起挪到按下 |
| 锚点表：底栏 LTR → `(Overflow.Left, Overflow.Bottom)`、`paLeft`；底栏 RTL → `(Overflow.Right, Overflow.Bottom)`、`paLeft`；侧栏两条照 A 期不变 | `twpBottom` 走了侧栏的分支 |
| 提示：标签上给 `StripHint`（设了时）/ `Caption`（没设时），窗口的 `Hint` 设了也不用；`CursorRect` 是那个标签的矩形 | 用 `Hint`；或 `CursorRect` 给了栏坐标 |
| 最大化按钮的提示最大化前后分别是 `Maximize` / `Restore` | 不看 `FMaximized` |
| 标签行空白处：`CM_HINTSHOW` 返回 1 | 空白处也填窗口自己的提示 |
| 右键在非当前页标签上：栏的 `OnContextPopup` 触发，`ContextWindow` 是那个窗口，`MousePos` 是栏坐标；用户挂在**窗口**上的 `OnContextPopup` 不触发 | `HeaderContextPopup` 把窗口坐标原样传给栏（`WindowAtPos` 答 nil、`ContextWindow` 为 nil、事件被挡） |
| 右键在标签行空白处：`Handled = True`，栏和窗口的 `OnContextPopup` 都不触发 | 窗口 `DoContextPopup` 区域内调继承 |
| `TI18NTest` 全绿（四条都在 .pot / zh_CN.po 里、非空） | 删掉 zh_CN.po 里的一条 |

真句柄（`test.toolwindow.focus`）：

| 判据 | 在哪个变异下必须红 |
|---|---|
| 焦点在底栏当前页的编辑框里，点收起按钮（或 `Collapsed := True`）：`ActiveControl` 不是窗体本身、也不在当前页里（spec §14「侧栏、底栏各测一次」） | 收起时不 `SelectNext`（A 期那条变异的底栏版） |

- [ ] **Step 7: 跑** `TTyToolWindowStripTests TTyToolWindowFocusTests TTyToolWindowBottomTests TTyToolWindowBottomInputTests TI18NTest`，全绿；变异逐条。

- [ ] **Step 8: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas source/tyControls.StrConsts.pas languages/ tests/ && git commit -m "feat(toolwindows): tab-row overflow menu, hide button, hints and context menu

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 底栏标签拖动调顺序（spec §9.1、§9.2、§9.4 底栏、§9.8 底栏）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.bottom.pas`、`tests/test.toolwindow.focus.pas`

- [ ] **Step 1: 落点与反馈**

- `HeaderDropSlotAt(W, X, Y): Integer`（private）：只算**标签行区域**（窗口的 `InTabRowRegion`）；区域外 → -1。区域内：取当前几何的拷贝，RTL 时对拷贝调一次 `TyToolWindowFlipAll`（翻回 LTR）、指针 `X := RowWidth - 1 - X`（地雷 8）；`TyToolWindowSlotAt(拷贝.Tabs, X, Y, False, WindowCount)`（它已经按窗口序号映射空隙，含「当前页被强制留下、已排标签不是前缀」的情形）。
- `HeaderDragTo(X, Y)`：`slot := HeaderDropSlotAt(FActive, X, Y)`；`SetDropSlot(slot)`；光标：-1 → `crNoDrop`，空操作 → `crDrag`（不画线），否则 `crDrag`（spec §9.4 / §9.2）。`SetDropSlot` 在底栏时改调 `InvalidateHeader`（反馈画在当前页里，spec §9.8）。
- `HeaderMouseMove` 里接上 `twgmDragStart` / `twgmDrag` → `HeaderDragTo`。
- `HeaderMouseUp`：拖动中先按松开点算 `slot` 和「是否提交」（同图标条的写法：`slot >= 0`、手势窗口还在、不是空操作），再 `Release`，最后一句提交 `ReorderWindow(w, slot - Ord(slot > src))`。区域外松开 = 取消：不调顺序，**也不切页**。
- 插入线：`PaintHeader` 第 7 步——拖动中、槽位有效且不是空操作时，在「空隙 k」画一条竖线：LTR 下是窗口 k 那个标签的左沿，最后一个之后是最后一个标签的右沿（找法同图标条的 `DropLineY`，横过来），RTL 时对这个 x 镜像；颜色 `TyToolWindowDropIndicator` 的 background，粗细 `--toolwindow-drop-size` 按 APPI，纵向占整个标题行，钳在标签区里。
- 捕获者是当前页：引擎的计时器和阈值原点都已经按 `Capturer` 走（Task 1），这里不用再改。

- [ ] **Step 2: 写测试（判据）**

无头（`TTyToolWindowBottomInputTests`；三个长短不一的标签，当前页不是第一个）：

| 判据 | 在哪个变异下必须红 |
|---|---|
| 按住标签 0、**竖着**移出标签行超过阈值：进入拖动，光标 `crNoDrop`；松开：顺序不变、当前页不变（spec §14） | 阈值只算横向；或区域外松开被当成点击 |
| 把标签 0 拖到最后一个标签之后松开：它变成最后一个，`ActiveWindow` 不变，`OnChange` 不发；拖动过程中顺序不实时变 | 在 `HeaderMouseMove` 里提交 |
| 拖回自己前后两个空隙：空操作，顺序不变、不画线 | 去掉空操作判断 |
| 当前页被强制留在行上、前面有窗口被收起时：把当前页拖到它右边的空隙 = 空操作；拖到第一格左边 → 正确的窗口序号（spec §14 槽位那条的底栏版） | 空隙按排布序号、不按 `ItemIndex` 映射 |
| RTL 下：指针落在物理上最右那个标签的右半（阅读顺序上它是第一个的「前半」）→ 槽位 0 | `HeaderDropSlotAt` 不镜像指针 |
| 插入线像素：哨兵底色下，拖动中那一列有插入线色，没拖动时没有；RTL 下出现在镜像后的位置 | 插入线画在栏上（`Bar.RenderTo`）而不是当前页里 |
| 拖动中 `Esc`（在无关控件上 `Perform(CN_KEYDOWN, VK_ESCAPE)`）：取消，之后松开不是点击 | — （引擎已守；底栏版确认捕获者换了也照样挂上） |
| 拖动中当前页收到 `LM_CANCELMODE`：取消，顺序不变 | 窗口不转发 `HeaderCancelMode` |
| 拖动中插入槽变化时当前页 `CacheWouldRender` 为真 | `SetDropSlot` 底栏时只 `Bar.Invalidate` |

真句柄（`test.toolwindow.focus`）：

| 判据 | 在哪个变异下必须红 |
|---|---|
| 在当前页的标签上真按下（捕获落在**当前页**上）拖过阈值：计时器建起来了；用 `SetCaptureControl(别的控件)` 抢走捕获，计时器那一拍取消（spec §9.7） | 引擎的 `CaptureConfirmed` / 计时器比的是栏而不是 `Capturer` |

- [ ] **Step 3: 跑** `TTyToolWindowReorderTests TTyToolWindowFocusTests TTyToolWindowBottomTests TTyToolWindowBottomInputTests`，全绿；变异逐条。

- [ ] **Step 4: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/ && git commit -m "feat(toolwindows): tabs reorder within the bottom bar on release

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: 设计期点标签（spec §3.6 设计期、§7.4 设计期）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.bottom.pas`

- [ ] **Step 1: 窗口让位**

窗口加 `CMMaskHitTest(var Message: TCMHitTest); message CM_MASKHITTEST;`，写法照 `TTyShape.CMMaskHitTest`（`Shape.pas:709-725`）：先置 0（「在我身上」，也是翻不了坐标时的回落）；`GetDesignerForm(TControl(Self))` 为 nil 就返回；坐标 `ScreenToClient(Frm.ClientToScreen(Point(XPos, YPos)))`；`InTabRowRegion` 为真 → 1（设计器跳过窗口，落到栏上）。**不改** `CM_DESIGNHITTEST`（窗口本身在设计期不接收标签行的手势）。

- [ ] **Step 2: 栏在栏坐标里认标签**

- `PartAt` 在栏坐标里认底栏标签，Task 6 Step 1 已经做了；本任务不再改它。
- `MouseDown` 设计期分支已经是「`part = twbpItem` → `ArmDesign(Windows[idx])`」：底栏的标签也是 `twbpItem`，自然接上。
- `CMDesignHitTest`：没武装时「`PartAt = twbpItem` 答 1」，底栏的标签自然接上；**溢出、最大化、收起、分隔线答 0**（它们改模型且没有撤销，spec §7.4）——现有写法本来就只对 `twbpItem` 答 1，执行时确认 Task 6 加的三个部件没有被谁改成「非 none 就答 1」。松开分支「先切再答 0」照旧。设计期 `MouseDown` 只在 `twbpItem` 上 `ArmDesign`，按在最大化等部件上不武装、也不做任何事（运行时那条 `FGesture.Press` 在设计期分支之后，走不到）。
- 设计期不做悬停（`UpdateHoverAt` 已经在 csDesigning 下返回；底栏的悬停也照这条）。

- [ ] **Step 3: 写测试（判据；`NewDesignBar` 建设计期底栏）**

| 判据 | 在哪个变异下必须红 |
|---|---|
| 栏坐标里非当前页标签的中心：`DesignHitTest(位置, 0)` 答 1；按下（`CallMouseDown`）后带 `MK_LBUTTONDOWN` 问答 1；松开那一拍（`AKeys = 0`）答 0，**并且**当前页在这一拍切过去 | 松开分支答 1；或切换挪到按下 |
| 溢出、最大化、收起、分隔线上：答 0，按下松开之后 `Maximized`、`Collapsed`、当前页都不变 | `PartAt` 答这些部件时也答 1 |
| 标签行空白处：答 0（点空白就是选中栏） | 空白答 1 |
| 窗口 `InTabRowRegion`：标签行里（含标签之间、操作区左边的空白）为真，操作区里、正文里为假 | 区域不扣操作区 |
| 窗口的 `CM_MASKHITTEST` 在没有设计器窗体时答 0（照 `TestMaskHitTestFallsBackToSelectable`） | 回落答 1 |

`CM_MASKHITTEST` 让位到栏、设计器里点标签切页，只能真机验（spec §15），写进 Task 12 的真机清单。

- [ ] **Step 4: 跑** `TTyToolWindowStripTests TTyToolWindowBottomTests`，全绿；变异逐条。图标条的设计期测试要一起跑。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.bottom.pas && git commit -m "feat(toolwindows): design-time tab clicks reach the bottom bar through the page

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: 运行时改到另一类栏抛 `EInvalidOperation`（spec §3.2）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.bottom.pas`

- [ ] **Step 1: 实现**

`TTyToolWindow.SetParent` 开头、**`inherited SetParent` 之前**：旧父控件和新父控件都是 `TTyToolWindowBar`、两者一侧一底（按 `Placement` 判，不看 `Align`），并且窗口和两条栏都不在 csLoading / csDesigning / csDestroying → `raise EInvalidOperation.Create('A tool window cannot move between a side bar and a bottom bar');`（消息英文字面量，同 `AdvChart.Coord.pas:288` 的写法）。孤儿（旧父控件不是栏）进底栏、底栏窗口改成 `Parent := nil` 都不抛。**不在 `CheckNewParent` 里做**（spec §3.2：读取器和设计器粘贴会经过它）。

- [ ] **Step 2: 写测试（判据）**

| 判据 | 在哪个变异下必须红 |
|---|---|
| 运行时侧栏窗口 `Parent := 底栏`：抛 `EInvalidOperation`；之后它仍在侧栏、仍是侧栏的当前页、侧栏 `WindowCount` 不变、底栏 `WindowCount` 不变 | 检查挪到 `inherited SetParent` 之后（窗口已经换了父控件） |
| 反方向（底 → 侧）同样抛 | 只判了一个方向 |
| 设计期（`NewDesignBar` 两条）照做，不抛 | 去掉 csDesigning 豁免 |
| 模拟加载（`BeginLoad`）期间照做，不抛 | 去掉 csLoading 豁免 |
| 同类栏之间（侧 → 侧）、孤儿 → 底栏、底栏 → nil：不抛 | 条件写成「新父控件是底栏就抛」 |

- [ ] **Step 3: 跑** `TTyToolWindowBarTests TTyToolWindowStreamingTests TTyToolWindowBottomTests`，全绿；变异逐条。

- [ ] **Step 4: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.bottom.pas && git commit -m "feat(toolwindows): moving a window between a side and a bottom bar raises at run time

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: 收尾——按 spec 逐条核、跑全量、抽查变异、偏差写回 spec

**Files:**
- Modify: `docs/superpowers/plans/2026-09-23-toolwindow-phase-b.md`
- Modify: `docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md`

- [x] **Step 1: 按 spec 逐条核代码，不看测试**（[[green-tests-are-not-spec-conformance]]）

逐条对着代码查，每条记「在哪一行实现 / 为什么不需要」：

- §3.4：底栏统一行高（`HeaderActionsHeight`、通知链、窗口列表变化）；底栏没有底线。
- §3.5：标签行的每一种视觉变化都经 `InvalidateHeader` 丢当前页缓存（逐项列：悬停、按下、标题、调顺序、注册 / 注销、禁用、最大化、插入线）；没有裸 `InvalidateRect`。
- §3.6 每一条：区域定义、武装、吞 Down / Up / Click / DblClick / 右键 / 滚轮、`BeginAutoDrag`、`CM_MASKHITTEST`、`CM_HINTSHOW`（不改 `ShowHint`）、右键只在标签上转给栏、区域内从不 `SetFocus`。
- §5.3：底栏收起后高度 0、当前页藏起、焦点搬出。
- §6.3 / §6.4：最大化期间边缘区不起作用；收起、栏变空、`SetParent`、改 Placement 之前先还原；`ExpandedSize` 不变；不进 .lfm。
- §6.8：标签右键设 `ContextWindow`、以栏为 `PopupComponent`。
- §7.1：栏忽略非当前页转来的 Move / Leave。
- §7.2：接口每个方法都有真实实现（**grep 确认没有空体**：`HeaderMouseDown` 等在 Task 3 留的空体都已填上）；`HeaderHint` 的文字来源。
- §7.3：排布规则逐句对 `LayoutBottomRow`。
- §7.4：松开切换、同一部件内松开才生效、多击在溢出 / 最大化 / 收起上不生效、点当前页标签什么都不做、设计期应答、溢出菜单 Owner = nil。
- §9.1 / §9.4 / §9.8：底栏标签只在本栏内调顺序；标签行外 `crNoDrop`、松开即取消；插入线画在当前页里。
- §9.7：捕获者是当前页时 `LM_CANCELMODE`、计时器都按它。
- §3.2：`EInvalidOperation`。
- §12：底栏五个类型键、四个长度 token 都有人读。

- [x] **Step 2: grep——没有只在定义处 / tests 里出现的常量**

```bash
cd /d/Projects/ty-3.1 && for c in $(grep -hoE "^ +TyToolWindow[A-Za-z]+ += " source/tyControls.ToolWindows.pas source/tyControls.ToolWindows.Layout.pas | sed -E 's/^ +//; s/ +=.*//'); do n=$(grep -rwn "$c" source --include=*.pas | grep -vE "^[^:]+:[0-9]+: +$c +=" | wc -l); [ "$n" -eq 0 ] && echo "没人读: $c"; done; echo done
```

Expected：只打印 `done`。再确认空位接线表里的每一项都真的被读：`grep -n "TyToolWindowTabPadVar\|TyToolWindowTabAreaMinVar\|TyToolWindowIndicatorSizeVar\|TyToolWindowButtonSizeVar\|TyToolWindowTabRowKey\|TyToolWindowTabKey\|TyToolWindowTabIndicatorKey\|TyToolWindowButtonKey\|TyToolWindowSeparatorKey" source/tyControls.ToolWindows.pas`，每个名字至少一处在定义行之外。

- [x] **Step 3: 跑全量**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --all --format=plain > /tmp/all.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/all.txt
```

Expected：`Number of run tests` 那一行存在，errors / failures 都是 0，总数 = Task 0 的基线 + 本期新增条数。红了先按 [[known-rare-suite-flake]]、[[suite-order-widgetset-init]] 排查是不是既有的偶发 / 顺序问题，再疑本期代码。

- [x] **Step 4: 抽查变异（每条三拍，必须红）**

1. Task 1 Step 6 的第 2 条（Cancelled 不记）与第 13 条（处理器不摘）。
2. Task 2 Step 5 的第 3 条（`ItemIndex := i`）。
3. Task 4 Step 3 的第 2 条（操作区不通知栏）。
4. Task 6 Step 5 的第 1 条（按下就切）。
5. Task 9 Step 2 的 RTL 那一条（指针不镜像）。

- [x] **Step 5: 整体代码质量审查**

按执行方式，本期只在这里做一次：对 `git diff <Task 0 的 HEAD>..HEAD -- source/` 做一次代码质量审查（重复代码、注释与代码不符、遗留的「B 期」字样、死字段 / 死方法）。审出来的问题修完再回到 Step 3 跑一次全量。

- [x] **Step 6: 把实现期的偏差写回 spec 原处**

「开工前要定的问题」里用户拍板的每一条，和实现中新发现的每一处 spec 没写准的地方，都在 spec **原处**改并标「实现期修正（B 期）」——C / D 期读的是 spec，不是这份计划。至少要落的：§5.4 / §7.2（`W = nil`）、§7.2（接口签名、缓存键）、§6.4（订阅复用、份额）、§3.6（按下决定归属）、§7.4（底栏溢出菜单方向）、§12（分隔线写法，若采纳）。§16 第 4 步标「已完成」，并把 B 期留给 C 期的事（引擎的「目标栏」、spec §9.2 记录里 B 期没加的字段）写进第 5 步。

- [x] **Step 7: 签收记录写进本计划末尾，提交**

```bash
cd /d/Projects/ty-3.1 && git add docs/ && git commit -m "docs(toolwindows): phase B sign-off notes and spec corrections

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

**B 期签收**：已填，见本计划末尾「B 期签收（2026-09-24）」。

---

## B 期做完能看到什么

在一个窗体里用代码搭一条底栏（D 期才有组件编辑器和示例；下面这段就是 B 期的冒烟用法）：

```pascal
procedure TMainForm.FormCreate(Sender: TObject);
var
  host: TTyPanel;
  bottom: TTyToolWindowBar;
  problems, output, terminal: TTyToolWindow;
  clearBtn: TTyButton;
begin
  { 编辑区和底栏一起放进一个 alClient 的容器,底栏就只在编辑区下面(spec §2)。 }
  host := TTyPanel.Create(Self);
  host.Parent := Surface;             { TTyForm 的内容容器 }
  host.Align := alClient;
  Memo1.Parent := host;
  Memo1.Align := alClient;

  bottom := TTyToolWindowBar.Create(Self);
  bottom.Parent := host;
  bottom.Placement := twpBottom;      { 先设 Placement,再加窗口 }
  bottom.ExpandedSize := 200;

  problems := TTyToolWindow.Create(Self);
  problems.Caption := 'Problems';
  problems.Parent := bottom;
  output := TTyToolWindow.Create(Self);
  output.Caption := 'Output';
  output.Parent := bottom;
  terminal := TTyToolWindow.Create(Self);
  terminal.Caption := 'Terminal';
  terminal.Parent := bottom;

  clearBtn := TTyButton.Create(Self);
  clearBtn.Caption := 'Clear';
  clearBtn.Parent := output.EnsureActions;

  bottom.ActiveWindow := problems;
end;
```

（`TTyPanel` / `Surface` 的确切名字执行时照 `examples/` 里现有的 `.lfm` 核一遍；这段只是冒烟用，不进仓库。）

运行起来应当是：

- 编辑区下面一条底栏，顶边一条贴编辑区的分隔线，能上下拖着调高、拖过头吸附收起；
- 栏的第一行左边是 `Problems  Output  Terminal` 三个文字标签，当前那个墨色更深、下面一条强调色下划线；右端依次是（切到 Output 时）`Clear` 按钮、一条竖分隔线、最大化、收起两个按钮；
- 按住标签不放不会切页，在同一个标签上松开才切；在标签上右键触发栏的右键菜单；标签可以左右拖着调顺序，拖动时有竖插入线，拖出标签行变禁止光标、松开取消，Esc 也取消；
- 窗口缩窄到放不下所有标签时，放不下的收进紧跟在最后一个标签后面的溢出按钮，当前页的标签永远留在行上；
- 最大化按钮把底栏撑满编辑区的高度（编辑区被压到 0），再点还原回原来的高度；窗体改高时最大化的底栏跟着变；
- 收起按钮把整条底栏收掉（高度 0，焦点从里面搬出来）；之后要靠代码 `bottom.Collapsed := False` 拿回来（spec §5.3：底栏收起后界面上不留入口，D 期示例里放菜单项）；
- 切到不同的页，操作区高度不同也不影响标签行的高度；
- 换主题、换密度、换 DPI、切 RTL，标签行跟着变；
- 运行时把侧栏里的窗口 `Parent :=` 到底栏会抛 `EInvalidOperation`。

**还做不到的**（C / D 期）：manager、跨侧拖动、`MoveWindow`、布局保存 / 恢复、设计器里「新建工具窗口」「添加操作区」、孤儿窗口的设计期显示、示例和文档。

**只能真机验的**（spec §15 里和 B 期有关的，本期无头测不到）：

- Lazarus IDE：设计期点底栏标签切页、`CM_MASKHITTEST` 让位到栏、点标签行空白选中栏。
- 各 widgetset：当前页禁用后标签行点击落到哪里；底栏溢出菜单的弹出位置（GTK3 / Qt Wayland）；标签拖动中弹出菜单 / `ShowModal` 抢走捕获后能否取消；Win32 捕获期间的 `WM_MOUSELEAVE`。
- Linux / macOS：标签行按钮字形是否清晰。
- 皮肤：17 个主题下的标签下划线、分隔线、按钮；高对比度皮肤下标签插入线是否看得见。

---

## B 期签收（2026-09-24）

- 全量 7485 条，errors / failures 0 / 0。
- 提交区间：Task 0–11 `67779154..1d9b55da`；整体审查（规格核对 + 代码质量）的修复 `16686303..1a93b9e0`。
- spec 写回：`16686303`（开工前拍板的各条、实现中的偏差）和本次提交（修复批次的偏差，标「实现期修正 / 补（B 期收尾）」）。
- 遗留，不阻塞：
  - (a) 父控件 `Enabled` 变化不通知栏，当前页的缓存帧要等下一次失效才变灰。
  - (b) 新来的非栏兄弟要等下一次推导才被监听（spec §6.2 的限制）。
  - (c) 收起按钮的横线落在半像素上；像素测试只覆盖了最大化按钮。
  - (d) 只能真机验的项见 spec §15。

**C 期开工前**：先读 spec §16 第 5 步——B 期留给 C 期的 6 项（引擎的「目标栏」、§9.2 记录里没加的三个字段、manager 的「正在拖」标记、调顺序发 `OnWindowMoved`、`MoveWindow` / `CanMoveWindow` 复用 `MovesAcrossBarKinds`、布局应用第 2 步直接 `Maximized := False`）。
