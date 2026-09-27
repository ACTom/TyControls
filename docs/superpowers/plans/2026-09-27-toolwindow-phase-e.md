# IDE 工作台 E 期：禁用窗口不困人、角标、一侧空了就隐藏 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（本期约定，优先于子技能的默认做法）**：整期连续实现，**每个任务单独提交**，每个任务只跑它列出的相关 suite；**不在任务之间安排审查环**，中途不汇报、不问要不要提交。整期做完后（Task 11）跑一次全量、做一次整体规格核对和一次代码质量审查。
>
> **谁来做**：标了 **【主控执行】** 的步骤由主控会话做，实现 agent **不做**——编任何 `.lpk`（`tycontrols.lpk`、`tycontrols_dt.lpk`）、编 example、跑 example、真机。理由同 D 期：`lazbuild <包>.lpk` 改的是机器级包注册表，三棵树三个会话共用（[[parallel-agent-worktree-hazards]]、[[three-worktree-31-layout]]）。实现 agent 只写源码、跑 `tests/tytests.lpi`、跑主题生成器。实现 agent **跳过所有「主控执行」的检查点**，主控在 Task 10 之后一次性编包和示例，把报错交回修复，再做 Task 11。

**Goal:** 真机验收后的第一批：禁用的工具窗口永远不把用户困住；工具窗口可以带角标；一侧没有窗口时整条隐藏，拖动时在那一侧显示放置预览。

**Architecture:** 三件事都在 `source/tyControls.ToolWindows.pas`（栏、窗口、manager 基类）和 `source/tyControls.ToolWindows.Manager.pas`（跨栏命中）里做，不动纯几何单元的函数签名。禁用：标签 / 图标认窗口的 `Enabled`；当前页禁用时底栏把标签行「让出」到栏自己的像素里画、自己收输入（spec §3.7 机制 ②），所有「标签行在谁身上」的问题归到一个查询 `TabRowHost`。角标：窗口上的四个属性照抄 `TTyButton`，尺寸和位置复用 `tyControls.Badge` 的纯函数，底栏把胶囊算进标签宽。隐藏：推导宽度为 0、不写 `Visible`；拖动时 manager 通知隐藏的栏显示一块有句柄的子控件当放置预览，探测矩形就是它。

**Tech Stack:** FPC / Lazarus LCL、BGRABitmap、`TTyPainter`、fpcunit、`.tycss` 主题与两个生成器。

**设计依据：** `docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md`（下称 spec）。本计划覆盖 spec 里所有标「E 期新增 / 修正 / 补（2026-09-27）」的条目：§3.3、§3.6、**§3.7**、§5.4、§6.1、§6.2、§6.5、§6.8、**§6.9**、§7.1、§7.3、§7.4、**§8.1**、§9.1、§9.4、§9.5、§9.8、§10.3、§10.7、§12、§13、§15、§16 第 9 步。

**不在本期**：spec §13 的其余「不做」（不拖动时指针靠近边缘弹出、每窗口尺寸、键盘操作图标条……）；CHANGELOG（发版时写，[[changelog-user-facing]]；Task 11 留草稿）；README（控件数不变）。

---

## 开工前要定的问题

spec 的 E 期条目没写死、或者有不止一种做法的地方。每条都给了建议，**计划正文按建议写**；改了哪条，执行时改对应任务，收尾时（Task 11）写回 spec。用户 2026-09-27 已经拍板的三件事的大方向（禁用窗口 = 内容禁用但不困人；角标属性在窗口上、名字跟 `TTyButton`；侧栏默认空了就隐藏、推导宽 0、预览是有句柄的子控件）不再列。

### 一、产品方向 / 用户可见（问用户）

> **已定（2026-09-27）**：用户回复「都按建议」，第一类 8 条全部按建议；第二类主控按建议采纳。

1. **当前页被禁用时，底栏它的操作区看不见。**
   机制 ②（让出标签行，spec §3.7）的代价：操作区是页的子控件，页让出了那一行，它就没地方显示。标签、溢出、最大化、收起都在，位置不变（操作区那一格留空，标签不重排）。
   **建议**：接受。要看见灰着的操作区只能走机制 ①（栏在标签行上叠两块有句柄的代理），叠放要在 GTK2 / GTK3 / Qt / Cocoa 上逐个真机，叠错了就又困住。

2. **禁用窗口的图标 / 标签能不能拖（调顺序、拖到另一侧）？**
   **建议**：不能。禁用 = 不是把手，看上去灰的东西拖得动会被当成 bug。右键菜单（栏照常设 `ContextWindow`）、`MoveWindow`、`WindowIndex` 照常。

3. **侧栏当前页被禁用时，点它自己的图标还收起 / 展开吗？**
   你说「当前页被禁用时，图标条仍然能收起」，侧栏收起的入口就是点当前页的图标（另一个是把拉宽边拖到很窄吸附收起）。
   **建议**：能。这个图标画灰（`:selected` + `:disabled`），但接悬停和按下、点一下收起 / 展开；不能拖。

4. **角标要不要「圆点」模式？**
   `TTyButton` 的徽标只有数字；库里单独的 `TTyBadge` 有 `Dot`（画一个小圆点，表示「有东西」不说多少）。
   **建议**：要，属性名 `BadgeDot`（按 `TTyButton` 的 `Badge*` 前缀起）。示例里 Output 页「有新日志」就用它。
   （0 显不显示照 `TTyButton`：`ShowBadge` 开着就显示 0；想 0 时藏起来，设 `ShowBadge := n > 0` 或在 `OnBadgeDisplay` 里藏。`TTyBadge` 是 0 默认藏，不照它。）

5. **溢出菜单里的项带不带角标？**
   **建议**：带。数字写成 `Problems (3)`，圆点写成 `Problems •`。收进溢出菜单的窗口在行上看不见，数字也跟着丢的话，用户不知道那里有东西。

6. **提示要不要带数字？**
   **建议**：不带，仍是 `StripHint`（空的时候 `Caption`）。数字就在图标上，提示再说一遍是噪音；想带的应用自己改 `StripHint`。

7. **放置预览上的文字。**
   **建议**：左栏 `Drop here to show the left side bar` / `放到左侧栏`，右栏 `Drop here to show the right side bar` / `放到右侧栏`。默认宽（240）下放得下，Task 8 有判据守着。

8. **示例怎么演示。**
   **建议**：
   - Problems 页数字角标 = 列表条数；Search 页数字角标（侧栏上也看得到一个）。
   - Output 页圆点：Output 不是正在看的那一页时来了新日志就亮，切到 Output 就灭。
   - Diagnostics 菜单加两项：`Add 45 Problems`（点三次就到 `99+`，看标签变宽、挤进溢出）；`Disable Search Window`（侧栏的禁用语义）。原来的 `Disable Output Page` 保留，文案改成验新行为。
   - 右栏只有 Outline：把它拖到左边，右栏就隐藏；再从左栏拖一个图标，就能看到右侧的放置预览。

### 二、实现层面（主控定）

9. **机制选 ②（让出标签行），不选 ①（代理）。** 比较表在 spec §3.7。② 没有新句柄、没有叠放，各平台一样，布局 / 像素 / 真实 `MouseDown` 全能无头测；① 的叠放只能真机，出错就回到被困住。

10. **属性名 `HideWhenEmpty: Boolean`（默认 True）。** 不用枚举（只有两种状态）；不叫 `AutoHide`：库里 `TTyScrollBar.AutoHide` 是跟主题走的三态枚举，JetBrains 的 Auto-hide 又是另一种视图模式（spec §13 不做），同名会误导。

11. **角标事件类型直接复用 `tyControls.Button.TTyBadgeDisplayEvent`。** `tyControls.ToolWindows` 的 interface uses 加 `tyControls.Button`（没有循环：Button 不 uses ToolWindows），implementation 加 `tyControls.Badge`（`TyBadgeText` / `TyBadgeSize` / `TyBadgeCornerPos`）。不另声明同形类型——两个同形的方法类型，对象查看器里不能把同一个处理器挂给按钮和工具窗口。

12. **角标一处量：量标签宽和画胶囊用同一个函数。** `TTyButton.DrawBadge` 用画笔的 `MeasureText` 量，那是画的时候才有画笔；这里标签宽要先于绘制算好、还要进缓存，所以按标签的量法（`TyMeasureTextBlock` 与 `TyMeasureRenderedTextWidth` 取大，`Painter.pas:454-466` 的约定）量文字宽和 `'0'` 的高，再交给 `TyBadgeSize`。量宽和画用两套量法，胶囊会比留的位置宽一个像素、压到下一个标签上，而且不会红。

13. **角标主题只写 `themes/light.tycss`，默认 token 同 `TyBadge` 那套（`--accent` / `--on-accent`），不回落到皮肤自己写的 `TyBadge` 规则。** 代价写进 spec §12：`green.tycss` 的 `TyBadge` 写死了 9px 和 `#FFFFFF`，不会带到工具窗口角标上。

14. **角标和标题的间隔复用 `--toolwindow-header-gap`，不加长度 token。** 不动 `DensityPack`、`GMETRICS`。

15. **放置预览由隐藏的那条栏持有，manager 基类加一个虚方法 `DragSourceChanged` 在「正在拖」变化时通知。** 现在 `FDragSource` 在引擎里两处直接赋值（`BeginDragging` 末尾、`ReleaseResources`），改成都经基类的 `SetDragSource`，值变了才调虚方法。候选条件（可用、`IsEnabled`、同一窗体、看得见、不在释放中、不是源栏、侧栏）从 `TTyToolWindowManager.DropTargetAt` 里抽成一个函数 `IsCrossCandidate`，预览和命中测试问同一个——两处各写一遍会漂开。

16. **预览的宽按「假设显示」推导：栏加标志 `FAssumeShown`，只在 `ShownAxisPx` 里置位。** 置位期间 `SizesAsCollapsed` 和 `HiddenAsEmpty` 都答「有窗口、展开」，别的栏照常按自己的真实状态参加 §6.2 分空间。不另写一份推导公式（两份会漂开）。

17. **两种手势中途变化都取消手势**：手势窗口或捕获者被禁用；标签行换了宿主（当前页禁用 / 启用、切页引起让出或收回）且进行中的是标签行手势（拉宽不算）。

18. **Win32 上点禁用页正文会落到栏**（spec §3.7 根因）：栏吞掉 `Click` / `DblClick`，不挡 `OnMouseDown` / `OnMouseUp`（它们在继承里先发，挡就得不调继承，栏的这两个事件对图标条本来也发）。文档写明。

19. **`TabRowHost` 做成 public 只读查询。** spec 要求「标签行在谁身上」一处答；测试也问它。

20. **共享文件**：本计划**不改** `source/tyControls.Base.pas`、`source/tyControls.Painter.pas`、`source/tyControls.Button.pas`、`source/tyControls.Badge.pas`。执行中发现非改不可，**停下来先问**。

---

## 接口清单（全计划用这一套名字）

**公开的：**

```pascal
{ tyControls.ToolWindows }
type
  { 当前页的标签行此刻在谁身上(spec §3.7)。Host = nil:不是底栏、没有当前页或行高 0。
    Row 是 Host 客户区坐标;Geom 是行内坐标(行左上角为原点)。 }
  TTyToolWindowTabRowHost = record
    Host: TWinControl;
    Row: TRect;
    Geom: TTyToolWindowHeaderGeom;
  end;

  { 隐藏侧栏的放置预览(spec §9.8)。运行时由栏建,Owner = nil、Parent = 栏的父控件。 }
  TTyToolWindowDropPreview = class(TTyCustomControl)          { Task 8 }
  public
    property Hot: Boolean;                                     { 指针在里面、它是此刻的目标 }
  end;

TTyToolWindow
  published
    property ShowBadge: Boolean default False;                 { Task 5 }
    property BadgeValue: Integer default 0;                    { Task 5 }
    property BadgeDot: Boolean default False;                  { Task 5(开工前问题 4) }
    property OnBadgeDisplay: TTyBadgeDisplayEvent;             { Task 5 }
  public
    { 此刻画不画角标、画什么(事件已经应用过)。AText 在圆点模式下是 ''。 }
    function BadgeDisplay(out AText: string; out ADot: Boolean): Boolean;   { Task 5 }

TTyToolWindowBarLayout
    TabRow: TRect;                                             { Task 2 }

TTyToolWindowBar
  published
    property HideWhenEmpty: Boolean default True;              { Task 7 }
  public
    function TabRowHost: TTyToolWindowTabRowHost;              { Task 2 }
    function HostsTabRow: Boolean;                             { Task 2 }
    function HiddenAsEmpty: Boolean;                           { Task 7 }
    { 放置预览此刻该在的矩形,父控件客户区坐标;不是隐藏的侧栏时为空。 }
    function DropPreviewRect: TRect;                           { Task 8 }
    property DropPreview: TTyToolWindowDropPreview;            { Task 8,只读;没建过是 nil }

{ tyControls.StrConsts }
rsTyToolWindowDropLeft, rsTyToolWindowDropRight                { Task 8 }
```

**单元内部的：**

| 在谁身上 | 名字 | 首次出现 |
|---|---|---|
| 窗口 | `CMEnabledChanged`（message `CM_ENABLEDCHANGED`） | Task 1 |
| 栏 | `WindowEnabledChanged(W)`、`WindowClickable(W)` | Task 1 |
| 栏 | `BottomRowHeightAt(APPI)`、`TabRowHostMayHaveChanged`、`FTabRowHosted`、`TabRowHostControl` | Task 2 |
| 栏 | `RowDown` / `RowMove` / `RowUp` / `RowHintAt`（按 `TTyToolWindowTabRowHost` + 宿主坐标） | Task 3 |
| 栏 | `BadgeSizeAt(W, APPI, out AText, out ADot): TSize`、`DrawBadgeIn(P, W, ABox, APPI)` | Task 5 |
| 栏 | `TabWidthsChanged`（只清标签宽缓存的标志）、`FTabCacheBadges` | Task 6 |
| Manager 单元 | `VisibleScreenRectOf(AParent, ARect)` | Task 8 |
| 栏 | `FAssumeShown`、`ShownAxisPx` | Task 8 |
| 栏 | `ShowDropPreview`、`HideDropPreview`、`SetDropPreviewHot` | Task 8 |
| manager 基类 | `SetDragSource`、`DragSourceChanged`（virtual） | Task 8 |
| manager | `IsCrossCandidate(ASource, ABar)` | Task 8 |

类型和方法**跟着第一个读它的任务一起加**，不提前加。

---

## 文件清单

| 文件 | 本期改什么 |
|---|---|
| `source/tyControls.ToolWindows.pas` | 禁用语义、让出标签行、角标、`HideWhenEmpty`、放置预览控件、manager 基类的通知 |
| `source/tyControls.ToolWindows.Manager.pas` | `IsCrossCandidate`；隐藏侧栏的探测矩形；`DragSourceChanged` 的实现 |
| `source/tyControls.StrConsts.pas` | 两条预览文案 |
| `languages/tyControls.StrConsts.pot`、`languages/tycontrols.strconsts.zh_CN.po` | 同上 |
| `themes/light.tycss` | 两个键、四个颜色 token |
| `source/tyControls.DefaultTheme.pas`、`source/tyControls.Css.Catalog.pas` | 生成物 |
| `tests/test.themes.pas`、`tests/golden/*.golden.txt`、`tests/test.defaulttheme.pas`、`tests/test.toolwindow.theme.pas` | 主题守卫 |
| `tests/test.toolwindow.disabled.pas` | **新建**。`TTyToolWindowDisabledTests`（Task 1–3） |
| `tests/test.toolwindow.badge.pas` | **新建**。`TTyToolWindowBadgeTests`（Task 5–6） |
| `tests/test.toolwindow.hide.pas` | **新建**。`TTyToolWindowHideTests`（Task 7–8） |
| `tests/test.toolwindow.bar.pas` | `TBarAccess` 按需加只转发的入口（`CallConstrainedResize`、`CallDoMouseWheel`、`CallHintAt`……） |
| `tests/tytests.lpr` | uses 加三个新单元 |
| `examples/toolwindows/*` | 角标、Diagnostics 两项、`Disable Output Page` 的文案（Task 9） |
| `docs/controls/toolwindows.md` | Task 10 |
| `docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md` | 只在 Task 11 写回 |

**不碰**：`source/tyControls.Base.pas`、`source/tyControls.Painter.pas`、`source/tyControls.Button.pas`、`source/tyControls.Badge.pas`、`source/tyControls.ToolWindows.Layout.pas`、`source/tyControls.ToolWindows.LayoutText.pas`、`source/tyControls.ToolWindows.DesignRules.pas`、`designtime/`、`source/tyControls.DensityPack.pas`、`CHANGELOG*.md`、`README*.md`。

---

## 实现期的地雷（每个任务开工前看一眼）

A–D 期的地雷照样有效（CRLF 上的变异先 `git diff --stat`、变异后 `lazbuild -B`、「谁先读就是谁的」、哨兵底色、`AssertSame` 已释放指针会假绿、无头不跑 LCL 对齐……）。E 期另加：

1. **重写 `CM_ENABLEDCHANGED` 必须先调 `inherited`**：LCL 在 `TWinControl.CMEnabledChanged` 里禁用 / 启用原生句柄、挪走焦点（`wincontrol.inc:6753-6763`）。不调就是 [[swallowed-cm-message-inherited]]：句柄永远停在旧状态。
2. **「窗口禁用」看 `W.Enabled`，不看 `W.IsEnabled`。** `IsEnabled` 顺着父链算，栏一禁用所有窗口都答假——当前页的「仍能收起」例外就会被栏的禁用误触发。栏自己禁用由现有的 `IsEnabled` / `Enabled` 闸管。
3. **让出那一行的高由栏自己算**（`BottomRowHeightAt`：`TokenPxAt(--toolwindow-header-height)` 与 `HeaderActionsHeight` 取大），**不读当前页的 `HeaderTokenPx` 缓存**：那是页在自己的 `Invalidate` 里察觉换主题的唯一一条边（spec §3.4），栏先读了，页就察觉不到了。
4. **让出 / 收回改的是 `AdjustClientRect` 的答案**：只 `Invalidate` 的话当前页停在旧边界里、盖着标签行。所有「让不让变了」的时机都要 `Realign` + 当前页 `RelayoutHeader`。
5. **无头测试跑不到 LCL 对齐**（[[headless-tests-never-run-lcl-align]]）：边界类判据先调夹具的 `Relayout` / `LayOut`；「有没有请重排」用 `AlignCount` / `Invalidates` 计数。
6. **标签行坐标有三套**：宿主客户区（引擎、`Press` / `Move` 用）、行内（`TyToolWindowZoneAt`、几何用）、栏客户区（`PartAt`、`WindowAtPos`、右键用）。当前页当宿主时行在它的客户区原点，前两套恰好相等——**只在「栏当宿主」时才分得开**，变异测试要选点在让出那一行里（行的 `Top` 不是 0：前面有 chrome 和边缘区）。
7. **`Windows[i]` / `IndexOfWindow` 每问一次都数一遍 `Controls`**：绘制和量宽的循环里先取一次 `WindowList(nil)`（`PaintHeader` 的注释）。
8. **`OnBadgeDisplay` 会被频繁调用**（量宽缓存键每次现算、每次画、每次命中）。测试里数调用次数只断言「≥ 1」，别断言准确次数。
9. **宽 0 的栏**：`ConstrainedResize` 的下限也得是 0，否则 LCL 把它钳回图标条宽；`SetBounds` 原样再设是空操作（[[lcl-setbounds-same-rect-noop]]），推导给的一定要是算好的新宽。
10. **放置预览是窗口化控件**：擦除时先铺父控件的 `Color`（[[windowed-ghost-erases-to-parent-color]]），显示前把它的 `Color` 设成解析出的栏底色；它是父控件的子控件，**栏的兄弟监听要跳过它**（spec §6.2 E 期补）；`BringToFront` 改的是父控件的 `Controls` 顺序，栏分空间的循环跟顺序无关，不受影响。
11. **生成器整体覆写**（[[gen-defaulttheme-eats-handwritten-code]]）：动 `light.tycss` 之前先验 FAITHFUL。
12. **跟着修复写的测试绿着错**（[[tests-written-with-the-fix-are-green-and-wrong]]）：每条判据先写、看它红、再实现；变异三拍逐条做。B 期的 `TestTheBarItselfIgnoresClicksOnTheTabRow`（栏自己收到标签行上的按下只吞）**必须保持绿**——它守的是「当前页没禁用」那一半；本期新测试钉的是另一半。
13. **新单元写出来是 LF**：仓库 `core.autocrlf = true`，检出后是 CRLF。变异用的搜索串先确认命中（[[crlf-mutation-phantom-survivor]]）；改 `.pas` 别用 Git Bash 的 `sed -i`（[[git-bash-sed-strips-crlf]]），用编辑工具。

---

## 跑测试的固定套路

改了 `source/` 之后**必须** `lazbuild -B`。exe 用唯一名 `tytests-31.exe`（禁用 `taskkill -im`）。

跑一组 suite（把 `SUITES` 换成任务里列的名字）：

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi > /tmp/build.txt 2>&1 || { tail -30 /tmp/build.txt; false; } && cd tests && cp tytests.exe tytests-31.exe && for s in SUITES; do ./tytests-31.exe --suite=$s --format=plain > /tmp/t-$s.txt 2>&1; printf '%s: ' $s; grep -E "Number of (run tests|errors|failures)" /tmp/t-$s.txt | tr '\n' ' '; echo; done
```

**判据是每个 suite 那一行都有 `Number of run tests`、errors / failures 为 0**，不是 exit code。某一行为空 = 跑丢了（或 suite 名写错），重跑，别读成通过。

全量（只在 Task 0 和 Task 11；输出必须重定向到文件，[[known-rare-suite-flake]]）：

```bash
cd /d/Projects/ty-3.1/tests && ./tytests-31.exe --all --format=plain > /tmp/all.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/all.txt
```

**工具窗口全部 suite**（D 期签收时的 19 个）：`TTyToolWindowGeometryTests TTyToolWindowThemeTests TTyToolWindowTests TTyToolWindowStreamingTests TTyToolWindowActionsTests TTyToolWindowBarTests TTyToolWindowImagesTests TTyToolWindowFocusTests TTyToolWindowStripTests TTyToolWindowEdgeTests TTyToolWindowReorderTests TTyToolWindowBottomTests TTyToolWindowBottomInputTests TTyToolWindowManagerTests TTyToolWindowManagerLiveTests TTyToolWindowCrossDragTests TTyToolWindowLayoutTextTests TTyToolWindowLayoutApplyTests TTyToolWindowDesignTests`，本期起再加 `TTyToolWindowDisabledTests`（Task 1 起）、`TTyToolWindowBadgeTests`（Task 5 起）、`TTyToolWindowHideTests`（Task 7 起）。

**主题守卫**：`TTestThemeGolden TTyThemesTest TDefaultThemeTest TTyToolWindowThemeTests`（suite 名以 `tests/test.themes.pas`、`tests/test.defaulttheme.pas` 里 `RegisterTest` 的为准，Task 0 Step 4 先核一遍）。

**发布守卫**：`TI18NTest TReleaseManifestTest TEnglishFitTest TSkinFitTest`。

## 关于判据和变异

纯查询（`BadgeDisplay`、`HiddenAsEmpty`、`TabRowHost`、`DropPreviewRect`、`BarLayout.TabRow`）给输入 / 期望表，测试照表写。**涉及重排时机、手势、像素的，只写判据和「在哪个变异下必须红」**，测试代码执行时按判据现写，写完**先做变异确认它真的在守**（[[plan-tests-write-the-mutation-not-the-code]]）。

变异三拍：改一行 → `git diff --stat` 确认改到了 → `lazbuild -B` → 跑 → **必须红** → 改回 → 重编重跑 → 绿。一条变异没红：先查是不是改错了地方；确实没红，说明那条测试没守住，**当场补强再继续**，并在该任务的提交信息里写一句。

探针只能是**真实状态的只读视图**。手势一律走真实的 `MouseDown / MouseMove / MouseUp`（`TBarAccess.CallMouse*`、`TProbeWindow.CallMouse*`、夹具的 `ClickIcon` / `ClickAt`）；防抖用 `TBarAccess.FakeClock`。像素一律哨兵底色 + `StyleOverride` 把要数的墨色钉成独一无二的颜色（[[headless-render-needs-sentinel-ground]]；底栏照 `TTyToolWindowBottomFixture` 的 `BottomTheme` / `InkIn`，侧栏照 `TallyStripCell`）。

**夹具**：`TTyToolWindowDisabledTests` 和 `TTyToolWindowBadgeTests` 从 `TTyToolWindowBottomFixture`（`tests/test.toolwindow.bottom.pas`）派生——侧栏的用例在同一个夹具里另建一条侧栏（夹具的 `FBar` 就是 `TBarAccess`，先设 `Placement` 再加窗口）；`TTyToolWindowHideTests` 从 `TTyToolWindowManagerFixture`（`tests/test.toolwindow.manager.pas`）派生，用 `NewBarOn` / `NewLeftRight` / `LayOut`。夹具里 `BottomTheme`、`InkIn`、`RestInk`、`SelInk` 这些 implementation 段的常量和函数，新单元要用就挪到 interface 或在新单元里照抄一份（照抄的注释写清来源）。

---

### Task 0: 基线

**Files:** 无改动。

- [ ] **Step 1: 确认起点**

```bash
cd /d/Projects/ty-3.1 && git status --short && git branch --show-current && git log --oneline -1
```

Expected：工作区干净，分支 `feat/3.1`，HEAD 是本计划的提交或其后。

- [ ] **Step 2: 编译并跑工具窗口全部 suite + 主题守卫 + 发布守卫 + 全量，记下条数**

每个 suite 的 `Number of run tests` 和全量总数记进草稿，Task 11 签收时一起写进本计划末尾。D 期签收是 7715 条 0 / 0。**有红就停**。

- [ ] **Step 3: 【主控执行】两个包和示例的基线**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tycontrols.lpk > /tmp/pkg.txt 2>&1; tail -3 /tmp/pkg.txt; rm -rf examples/toolwindows/lib && lazbuild -B examples/toolwindows/toolwindows_example.lpi > /tmp/ex.txt 2>&1; tail -3 /tmp/ex.txt; git status --short languages/
```

Expected：都编过；`languages/` 没有变化。报错路径里出现别的树 = 注册权被抢，重编一次。

- [ ] **Step 4: 先查几件事，结论记进草稿**

1. 主题守卫的真实 suite 名（上面「主题守卫」那一行）；`tests/test.defaulttheme.pas` 里 `TestBuiltinCoversAllTypeKeys` 的 `AssertBg` 写法。Task 4 用。
2. `SwitchCore`、`SetCollapsed`、`Relayout`、`Loaded` 里哪一处是「切页 / 收起 / 展开完成、对齐已恢复」的最后一句——`TabRowHostMayHaveChanged` 挂在那里（Task 2）。
3. `TTyToolWindowGesture.Press` 的 `ACapturer` 用在哪些地方（阈值原点、捕获轮询、`HeaderPressed`、`HeaderCapturedBy`、`PaintHeader` 的插入线）。Task 3 要让「栏当捕获者」在这几处都成立。
4. `WatchSiblings` 挂兄弟的循环在哪一行、按什么过滤。Task 8 要在那里跳过放置预览。
5. B 期的提示测试（`TTyToolWindowBottomInputTests` 里 `CM_HINTSHOW` 那几条）怎么构造 `THintInfo`、怎么发消息。Task 3 照抄。

---

### Task 1: 禁用窗口的图标 / 标签认 `Enabled`（spec §3.7 语义、根因第 2 条）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Create: `tests/test.toolwindow.disabled.pas`
- Modify: `tests/tytests.lpr`、`tests/test.toolwindow.bar.pas`（按需加只转发的入口）

这一步不管「当前页禁用后底栏标签行怎么活」（Task 2、3），只让禁用窗口在图标条 / 标签行上**看起来是禁用的、点了不切、拖不动**，以及当前页禁用时侧栏图标仍能收起。

- [ ] **Step 1: 新测试单元**

`tests/test.toolwindow.disabled.pas`：`TTyToolWindowDisabledTests = class(TTyToolWindowBottomFixture)`。uses 抄 `test.toolwindow.bottom` 那一串再加 `test.toolwindow.bottom`。挂进 `tests/tytests.lpr` 的 uses（`test.toolwindow.design,` 后面，用编辑工具改）。

- [ ] **Step 2: 写测试（判据）**

侧栏用例：一条运行时左栏，三个窗口 Explorer / Search / Git，当前页 Explorer，图标列表用 `NewHouseList`（三个都用 `house`），`FBar.FakeClock := True`（每次点击前 `Clock` 推 1000，躲开防抖）。底栏用例：`NewBottomBar(['Problems', 'Output', 'Terminal'], 0)`。

| 判据 | 在哪个变异下必须红 |
|---|---|
| 侧栏：`Search.Enabled := False`，`ClickIcon(1)`：`ActiveWindow` 还是 Explorer，`FChanges = 0` | `StripClick` / 按下不看窗口的 `Enabled` |
| 侧栏：同上，在 Search 图标上按下并移过阈值（`CallMouseMove` 走 `Max(|dx|,|dy|)` 超过 `TyToolWindowDragThreshold`）：`IsDraggingForTest` 为假 | 按下照常武装成可拖的（`Press` 的 `ADraggable` 不看 `Enabled`） |
| 侧栏：指针移到 Search 图标上（`CallMouseMove` 不带键）：`FBar.StripHover <> 1` | 悬停不跳过禁用窗口 |
| 侧栏像素：`StyleOverride` 把 `--muted` 钉成 `#00FF00`、`--toolwindow-strip-ink` 钉成 `#FF0000`（图标按墨色着色）：Search 那一格有 `#00FF00` 的墨迹、没有 `#FF0000`；Explorer、Git 两格反过来 | `StripItemStates` 不看窗口的 `Enabled` |
| 侧栏：当前页 Explorer 自己被禁用，`ClickIcon(0)`：`Collapsed = True`；推时钟再点一次：`False` | 一刀切「禁用的图标不接点击」（当前页没有例外） |
| 侧栏：当前页 Explorer 禁用，在它的图标上按下移过阈值：不起拖 | 当前页例外连拖动也放开了 |
| 侧栏：Explorer 禁用后点 Search：切过去（别的图标照常） | 窗口禁用时整条图标条都不收输入 |
| 侧栏：Search 禁用，代码 `FBar.ActiveWindow := Search`：切过去，`Search.Visible` | 把「不切到禁用窗口」写进了 `ActivateWindow`（spec §3.3：代码照常） |
| 侧栏：Search 禁用，在它的图标上右键（`CallDoContextPopup`）：`ContextWindow = Search`、`Handled` 不被栏置真（应用的菜单照弹） | 右键也跳过禁用窗口（spec §3.7：右键照常） |
| 侧栏：拖动 Search 途中（已过阈值）`Search.Enabled := False`：手势取消（`IsDraggingForTest` 假），之后松开不调顺序 | `WindowEnabledChanged` 不取消手势 |
| 底栏：`FWins[1].Enabled := False`，`ClickAt(FWins[0], TabCentre(1))`：当前页还是 Problems | `HeaderMouseDown` 不看标签对应窗口的 `Enabled` |
| 底栏像素（`BottomTheme` + `--muted: #00FF00`）：Output 标签里有 `#00FF00`、没有 `RestInk`；Terminal 标签有 `RestInk` | `HeaderTabStates` 不看窗口的 `Enabled` |
| 底栏：Output 禁用，指针移到 Output 标签上：`HeaderHoverPartForTest <> twbpItem` 或 `HeaderHoverIndexForTest <> 1` | 标签行悬停不跳过禁用窗口 |
| 溢出菜单（侧栏把栏压矮到只放得下一个图标，照 A 期溢出测试的造法）：禁用窗口那一项 `Enabled = False`；直接调它的 `OnClick`：不切 | 菜单项不灰 / `OverflowItemClick` 不看 `Enabled` |
| 重画：`Search.Enabled := False` 之后 `FBar.Invalidates` 至少 +1；底栏 `FWins[1].Enabled := False` 之后当前页的缓存要重渲染（`ArmActive` + `CacheWouldRender`） | 窗口的 `CM_ENABLEDCHANGED` 不通知栏 |

- [ ] **Step 3: 跑，确认红**

- [ ] **Step 4: 实现**

窗口（`TTyToolWindow`，private 的消息段里，`CMBiDiModeChanged` 旁边）：

```pascal
    { 窗口自己的 Enabled 变了(spec §3.7):图标 / 标签的样子、手势、底栏的「让出标签行」都跟着
      变,交给栏。先调继承 —— LCL 在那里禁用 / 启用原生句柄、挪走焦点(wincontrol.inc:6753-6763),
      不调就是 [[swallowed-cm-message-inherited]]。 }
    procedure CMEnabledChanged(var Message: TLMessage); message CM_ENABLEDCHANGED;
```

```pascal
procedure TTyToolWindow.CMEnabledChanged(var Message: TLMessage);
var
  b: TTyToolWindowBar;
begin
  inherited;
  b := Bar;
  if (b <> nil) and not (csDestroying in b.ComponentState) then
    b.WindowEnabledChanged(Self);
end;
```

栏加 private：

```pascal
    { 用户能不能点它切过去、按住它拖(spec §3.7):看窗口**自己的** Enabled —— IsEnabled 顺着
      父链算,栏一禁用全都答假,当前页的例外就被栏的禁用误触发了。栏自己禁用另有一道闸。 }
    function WindowClickable(AWindow: TTyToolWindow): Boolean;
    { 窗口的 Enabled 变了:正武装 / 拖着它、或捕获在它身上的手势取消;它的悬停清掉;重画。
      底栏当前页的「让出标签行」在 Task 2 接到这里。 }
    procedure WindowEnabledChanged(AWindow: TTyToolWindow);
```

`WindowClickable(W)` = `(W <> nil) and W.Enabled`。

`WindowEnabledChanged`：
- 不是本栏的窗口（`IndexOfWindow < 0`）就退出；栏在加载 / 释放中退出。
- `not W.Enabled` 且（`FGesture.Window = W` 或 `FGesture.Capturer = W`）→ `ResetGesture(twgeCancel)`。
- 悬停落在它身上的清掉（图标条 `FStripHover`、标签行 `FHeaderHoverPart = twbpItem` 且序号是它）。
- 底栏 `InvalidateHeader`，侧栏 `Invalidate`。

图标条：
- `StripItemStates(AIndex)`：窗口禁用也加 `tysDisabled`（栏禁用那一支保留）；悬停、按下只在「栏启用，且窗口可点或它就是当前页」时加（当前页例外，spec §3.7）。注释写明例外的理由。
- `UpdateHoverAt`（侧栏那一支）：命中的图标对应窗口不可点、又不是当前页 → 当作没有悬停。
- `MouseDown` 的图标那一支：窗口不可点、又不是当前页 → 只吞（`SwallowClick` 已经为真），不武装、不设 `FStripPressed`；是当前页 → `FGesture.Press(twbpItem, w, w.Enabled, …)`（禁用的当前页可以点、不能拖）。
- `StripClick`：开头 `if not WindowClickable(AWindow) and (AWindow <> FActive) then Exit;`（兜底：按下那一道闸之后窗口才被禁用的情况，`WindowEnabledChanged` 已经取消了手势，这里再挡一次不花钱）。

底栏：
- `HeaderTabStates`：窗口禁用加 `tysDisabled`，不接悬停、按下（它不是当前页也好、是也好——底栏点当前页标签本来什么都不做）。
- `HeaderMouseDown` 的 `twzTab`：`if not WindowClickable(Windows[idx]) then Exit;`（不武装）。
- `HeaderMoveIn` 的悬停、栏自己的 `UpdateHoverAt`（底栏那一支）：命中禁用窗口的标签当作没有悬停。

溢出菜单：`ShowOverflowMenu` 里 `item.Enabled := Windows[hidden[i]].Enabled;`；`OverflowItemClick` 里 `if not w.Enabled then Exit;`。

- [ ] **Step 5: 跑** `TTyToolWindowDisabledTests TTyToolWindowStripTests TTyToolWindowBottomTests TTyToolWindowBottomInputTests TTyToolWindowReorderTests TTyToolWindowCrossDragTests`，全绿；变异逐条。

- [ ] **Step 6: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.disabled.pas tests/tytests.lpr tests/test.toolwindow.bar.pas && git commit -m "fix(toolwindows): a disabled tool window's icon and tab look disabled and do not switch

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 让出标签行——布局与绘制（spec §3.7 机制 ②）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.disabled.pas`

当前页禁用时，栏在内容区顶上留一行自己画标签行，页从这一行下面开始、不再留标题行。这一步只做布局、绘制和「标签行在谁身上」这个查询；输入在 Task 3。

- [ ] **Step 1: 写测试（判据）**

底栏：`NewBottomBar(['Problems', 'Output', 'Terminal'], 1)`，Output 是当前页；Terminal 的操作区放一个 40px 高的子控件（`AddActionsKid`），让统一行高高过 token（地雷 3 的变异才分得开）。记下禁用前的 `h0 := FWins[1].HeaderHeightPx`、正文在栏里的顶 `t0 := FWins[1].Top + FWins[1].BodyRect.Top`。然后 `FWins[1].Enabled := False; Relayout;`。

| 判据 | 在哪个变异下必须红 |
|---|---|
| `FBar.HostsTabRow` 为真；`FBar.BarLayout.TabRow` 高 = `h0`，顶 = 禁用前 `Content.Top`；`Content.Top = TabRow.Bottom` | `LayoutAt` 不让出 |
| 同上，行高 = `h0`（> token 值） | 行高只取 token、不算操作区（地雷 3） |
| `FWins[1].HeaderHeightPx = 0`、`BodyRect.Top = 0`、`FWins[1].Top = TabRow.Bottom` | 页的 `HeaderHeightAt` 不看「让出」 |
| 正文在栏里的顶不变：`FWins[1].Top + FWins[1].BodyRect.Top = t0` | 行高两边算法不一致（任一边变异） |
| 页的操作区是空矩形或在正文之外：`Actions.Height = 0` 或 `Actions.BoundsRect` 不与 `BodyRect` 相交 | 让出期间操作区照旧摆在页顶、压在正文上 |
| `TabRowHost.Host = FBar`、`Row = BarLayout.TabRow`、`Geom` 的每个标签矩形与禁用前 `ActiveGeom` 对应的**逐个相等**（标签不重排）；`Geom.Actions` 宽 = 禁用前的 | 几何按「没有操作区」算（操作区那一格没留） |
| 启用回来（`Enabled := True; Relayout`）：`HostsTabRow` 假、`TabRow` 空、`HeaderHeightPx = h0`、`TabRowHost.Host = FWins[1]` | 收回那一支缺失 |
| 通知：`Enabled := False` 之后（**不**调 `Relayout`）栏被请了一次重排（`FBar.AlignCount` +1 或当前页 `AlignCount` +1，以 Task 0 Step 4 第 2 条查到的为准）且 `FBar.Invalidates` +1 | `WindowEnabledChanged` 不接 `TabRowHostMayHaveChanged` |
| 切页也对一遍：Output 禁用时代码切到 Problems：`HostsTabRow` 假、栏被请了重排；再切回 Output：真 | `SwitchCore` 之后不对 |
| 收起时不让出：Output 禁用、`Collapsed := True`：`HostsTabRow` 假、`TabRow` 空 | 条件漏了收起 |
| 设计期不让出（`NewDesignBar` 的底栏，当前页 `Enabled := False`）：`HostsTabRow` 假 | 条件漏了设计期 |
| 侧栏不让出：左栏当前页禁用：`HostsTabRow` 假、`TabRow` 空 | 条件漏了 Placement |
| 像素（`BottomTheme` + `--muted: #00FF00`，栏 `CallRenderTo` 画到哨兵底上）：`TabRow` 里 Problems、Terminal 的标签有**原色** `RestInk`（没被 opacity 冲淡）；Output 标签有 `#00FF00`；页自己画出来的顶部一行里没有任何标签墨色（`RenderPage(FWins[1], …)`） | 栏的 `RenderTo` 不画 `TabRow` / 页照旧画标签行 |
| 像素：最大化、收起按钮在 `TabRow` 里有 `RestInk`（不是禁用墨色） | 按钮的状态跟着当前页的禁用走了 |
| 重画走栏：让出期间改 Problems 的 `Caption`：`FBar.Invalidates` +1 | `InvalidateHeader` 只丢当前页的缓存 |
| `PartAt`（栏坐标）在 `TabRow` 里 Terminal 标签中心答 `twbpItem`、序号 2；`WindowAtPos` 答 Terminal | `HeaderZoneAt(nil, …)` 仍按当前页的 `Left / Top` 换算 |
| `OverflowWindows` 与禁用前相同（把栏压窄到收进一个标签再比） | `OverflowWindows` 仍问当前页的几何（让出后页里行高 0，一个都放不下） |
| 溢出菜单锚点（`OverflowMenuAnchorIn`）的宿主是栏、锚点在 `TabRow` 的溢出按钮底边 | 锚点仍按当前页算 |

- [ ] **Step 2: 跑，确认红**

- [ ] **Step 3: 实现**

类型（`TTyToolWindowBarLayout` 前面）加 `TTyToolWindowTabRowHost`（见接口清单）。`TTyToolWindowBarLayout` 在 `ConflictNote` 后面加：

```pascal
    { 运行时底栏的当前页被禁用:栏在内容区顶上让出来、自己画的标签行(spec §3.7)。
      禁用的页收不到鼠标(Win32 / GTK / Qt / Cocoa 各有各的原因,spec §3.7 根因),标签行
      只能长在栏自己的像素里。其余时候为空。 }
    TabRow: TRect;
```

栏：

```pascal
  private
    { 上一次按哪种样子排过(让出 / 没让出):TabRowHostMayHaveChanged 比它。 }
    FTabRowHosted: Boolean;
    { 底栏统一行高(spec §3.4),按 APPI。token 自己取(TokenPxAt),不读窗口的 HeaderTokenPx
      缓存 —— 那是窗口在自己的 Invalidate 里察觉换主题的唯一一条边,谁先读就是谁的。 }
    function BottomRowHeightAt(APPI: Integer): Integer;
    { 标签行此刻长在谁身上(只答控件,不算几何):按下态、插入线的「捕获者是不是宿主」用它。 }
    function TabRowHostControl: TWinControl;
    { 让不让出变了:让出 / 收回那一行改的是 AdjustClientRect 的答案,要 Realign(只重画的话
      当前页停在旧边界里、盖着标签行);当前页 RelayoutHeader;栏和当前页都重画;进行中的
      标签行手势取消(拉宽不算)。加载 / 释放中不做。 }
    procedure TabRowHostMayHaveChanged;
  public
    { 运行时、底栏、有当前页、当前页自己 Enabled = False、栏没收起(spec §3.7)。 }
    function HostsTabRow: Boolean;
    function TabRowHost: TTyToolWindowTabRowHost;
```

```pascal
function TTyToolWindowBar.HostsTabRow: Boolean;
begin
  Result := (FPlacement = twpBottom) and (FActive <> nil) and not FActive.Enabled
    and not (csDesigning in ComponentState) and not FCollapsed;
end;

function TTyToolWindowBar.BottomRowHeightAt(APPI: Integer): Integer;
var
  a: Integer;
begin
  Result := TokenPxAt(TyToolWindowHeaderHeightVar, TyToolWindowHeaderHeightDef, APPI);
  a := HeaderActionsHeight(nil, APPI);
  if a > Result then Result := a;
  if Result < 1 then Result := 1;
end;

function TTyToolWindowBar.TabRowHost: TTyToolWindowTabRowHost;
var
  L: TTyToolWindowBarLayout;
begin
  Result := Default(TTyToolWindowTabRowHost);
  if (FPlacement <> twpBottom) or (FActive = nil) then Exit;
  if HostsTabRow then
  begin
    L := BarLayout;
    if L.TabRow.Bottom <= L.TabRow.Top then Exit;
    Result.Host := Self;
    Result.Row := L.TabRow;
    Result.Geom := HeaderGeometry(FActive, L.TabRow.Right - L.TabRow.Left,
      L.TabRow.Bottom - L.TabRow.Top, PPI);
  end
  else
  begin
    Result.Row := FActive.HeaderRowRect;
    if Result.Row.Bottom <= Result.Row.Top then Exit;
    Result.Host := FActive;
    Result.Geom := FActive.HeaderGeomAt(Rect(0, 0, FActive.ClientWidth, FActive.ClientHeight),
      FActive.Font.PixelsPerInch);
  end;
end;
```

（`PPI` 与 `FActive.Font.PixelsPerInch` 在推送之后是同一个数；两支各用各的是照搬现有调用点，别顺手统一——统一了会让 PPI 漂移的测试换一种红法。）

`LayoutAt`：在边缘区那一段之后、设计期提示之前：

```pascal
  { 当前页禁用:内容区顶上让出一行给标签行(spec §3.7),行高同没让出时 —— 标签行不跳。 }
  if HostsTabRow then
  begin
    bandH := BottomRowHeightAt(APPI);
    if bandH > Result.Content.Bottom - Result.Content.Top then
      bandH := Result.Content.Bottom - Result.Content.Top;
    Result.TabRow := Rect(Result.Content.Left, Result.Content.Top,
      Result.Content.Right, Result.Content.Top + bandH);
    Inc(Result.Content.Top, bandH);
  end;
```

窗口 `HeaderHeightAt` 开头（`twhNone` 那一句之后）：

```pascal
  { 栏让出了标签行(当前页被禁用,spec §3.7):页自己不再留标题行,正文从页顶开始、操作区
    摆成空的。行高没变,只是长到了栏里。 }
  if (HeaderMode = twhBottom) and IsActive and Bar.HostsTabRow then Exit(0);
```

栏 `RenderTo`：`DrawFrame` 之后、设计期提示之前，`L.TabRow` 非空就

```pascal
      PaintHeader(FActive, P, L.TabRow,
        HeaderGeometry(FActive, L.TabRow.Right - L.TabRow.Left, L.TabRow.Bottom - L.TabRow.Top, APPI),
        APPI);
```

改用 `TabRowHost` 的调用点（逐个改，每个都是「标签行在谁身上」）：
- `HeaderZoneAt(nil, …)`：`w = nil` 那一支改成取 `TabRowHost`，行在栏坐标里的原点 = 宿主是栏时 `Row.TopLeft`，宿主是当前页时 `(FActive.Left + Row.Left, FActive.Top + Row.Top)`；按 `Geom` 和这个原点换算。`AWindow <> nil` 那一支（页转来的）不变。
- `OverflowWindows`（底栏那一支）：用 `TabRowHost.Geom`。
- `OverflowMenuAnchorIn`（底栏那一支）：宿主 = `TabRowHost.Host`，矩形 = `Geom.Overflow` 平移 `Row.TopLeft`；读写方向仍取当前页的 `IsRightToLeft`（几何按它镜像，B 期收尾的规矩）。
- `InvalidateHeader`：`HostsTabRow` 时 `Invalidate`（栏自己没有绘制缓存），否则照旧丢当前页的缓存。
- `TabRowHostControl` = `HostsTabRow ? Self : FActive`（底栏以外 nil）。

`TabRowHostMayHaveChanged`：

```pascal
procedure TTyToolWindowBar.TabRowHostMayHaveChanged;
var
  now: Boolean;
begin
  if [csLoading, csDestroying] * ComponentState <> [] then Exit;
  now := HostsTabRow;
  if now = FTabRowHosted then Exit;
  FTabRowHosted := now;
  { 标签行换了宿主:进行中的标签行手势跟着失效(捕获者、坐标系都不是原来那个了);拉宽不算。 }
  if (FGesture <> nil) and (FGesture.Part in [twbpItem, twbpOverflow, twbpMaximize, twbpCollapse]) then
    ResetGesture(twgeCancel);
  Realign;
  if FActive <> nil then FActive.RelayoutHeader;
  Invalidate;
  InvalidateHeader;
end;
```

调用点：`WindowEnabledChanged` 末尾（窗口是当前页时）；Task 0 Step 4 第 2 条查到的切页、收起 / 展开完成处；栏的 `Loaded` 末尾（.lfm 里流进来一个 `Enabled = False` 的当前页）。

- [ ] **Step 4: 跑** `TTyToolWindowDisabledTests TTyToolWindowBottomTests TTyToolWindowBottomInputTests TTyToolWindowBarTests TTyToolWindowStreamingTests`，全绿；变异逐条。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.disabled.pas && git commit -m "fix(toolwindows): the bar draws the tab row while the current bottom page is disabled

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 让出标签行——输入（spec §3.7、§6.8 E 期补）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.disabled.pas`、`tests/test.toolwindow.bar.pas`

让出的那一行是栏自己的像素：按下原生就到栏。栏现在的规矩是「落在标签行部件上的按下一律吞掉」（B 期收尾）——当前页禁用时改成走同一套标签行手势，捕获者是栏。

- [ ] **Step 1: 写测试（判据）**

同 Task 2 的底栏，Output（当前页）禁用、`Relayout`。点位一律取 `TabRowHost` 的几何平移 `Row.TopLeft` 之后的**栏坐标**，经 `TBarAccess.CallMouseDown / CallMouseMove / CallMouseUp`（真实入口）。

| 判据 | 在哪个变异下必须红 |
|---|---|
| 点 Terminal 标签（按下、松开同一点）：当前页变成 Terminal，`FChanges = 1` | `MouseDown` 的底栏分支照旧只吞 |
| 同上，但按下落在 Terminal、松开落在 Problems：不切 | 松开不看部件（按下就切） |
| 点收起按钮：`Collapsed = True`；展开后点最大化：`Maximized = True`，再点：`False` | 按钮不走标签行手势 |
| 点溢出按钮（栏压窄到收进一个标签）：`OverflowMenu.Items.Count` = 收进去的个数 | 同上 |
| 拖 Problems 标签（序号 0）过阈值、在 Terminal 标签的后半松开（槽位 3，`FinalIndex = 3 − 1 = 2`）：窗口顺序变成 Output, Terminal, Problems，当前页仍是 Output | 拖动那一支仍走侧栏的 `DragTo`（栏坐标当图标条算） |
| 拖动中 `PaintHeader` 画插入线：栏 `CallRenderTo` 的 `TabRow` 里有插入线色（`--toolwindow-drop-color` 钉成哨兵） | `PaintHeader` 的插入线仍要求「捕获者 = 当前页」 |
| 按下 Terminal 标签不松：栏 `CallRenderTo` 里 Terminal 标签有按下态底色（`--toolwindow-overlay-active` 钉成哨兵） | `HeaderPressed` 仍要求「捕获者 = 当前页」 |
| **坐标**：点在让出行里、行内坐标与栏坐标差一个 `Row.Top`（边缘区 + chrome）的位置——点 Terminal 标签**下半部**（行内 y > 行高 − `Row.Top`）：切到 Terminal | 核心用栏坐标直接查行内几何（没减 `Row.TopLeft`，地雷 6） |
| 悬停：指针移到 Problems 标签（不带键）：`HeaderHoverPartForTest = twbpItem`、序号 0；`CallMouseLeave`：清掉 | 栏的 `MouseLeave` 不清标签行悬停 |
| 提示：`CM_HINTSHOW` 发给栏、点在 Terminal 标签：`HintStr` = Terminal 的 `StripHint` 或 `Caption`；点在最大化按钮：`rsTyToolWindowMaximize`；点在行内空白：`Result = 1`（不显示，也不回落到栏自己的 `Hint`） | 栏的 `CMHintShow` 只认 `twbpItem` |
| 右键：`CallDoContextPopup` 点在 Terminal 标签：`ContextWindow = Terminal`；点在行内空白：`Handled = True`（吞掉，不冒泡）；点在栏的边缘区：`Handled = False` | 行内空白照旧不处理（冒泡到窗体） |
| 滚轮：`CallDoMouseWheel`（新加的只转发入口）点在行内：答 True | 栏在让出行上不吞滚轮 |
| Win32 那一路：点在禁用页的正文（栏坐标，页的边界里）：栏的 `OnClick` 不触发（`FClicks = 0`，夹具的 `HandleClick`）；页启用时同一点经栏直接调：`FClicks` 照旧（这条是对照，证明闸只在禁用时起作用） | 栏不吞禁用页正文上的 Click |
| 回归：Output **没**禁用时，栏自己收到标签上的按下仍然只吞（B 期的 `TestTheBarItselfIgnoresClicksOnTheTabRow` 保持绿） | 把「栏收标签行输入」放开到不管禁不禁用 |
| 松开时当前页被切走：在让出行里点 Problems 切过去之后，`HostsTabRow` 假、`Terminal`/`Problems` 页的标签行照旧能用（`ClickAt(FWins[0], TabCentre(2))` 切到 Terminal） | 收回之后栏还在收标签行输入 |

- [ ] **Step 2: 跑，确认红**

- [ ] **Step 3: 实现**

把标签行手势的核心从「窗口」改成「宿主」：

```pascal
  private
    { 标签行手势的核心(spec §7.4 / §9.2),按宿主做:AHost 是 TabRowHost(当前页或栏),X / Y 是
      宿主客户区坐标。引擎拿宿主坐标(阈值原点、捕获轮询都按宿主),几何命中减掉 Row.TopLeft
      换成行内坐标。当前页当宿主时行在它客户区原点,两套坐标相等 —— 原来那一路行为不变。 }
    procedure RowDown(const AHost: TTyToolWindowTabRowHost; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure RowMove(const AHost: TTyToolWindowTabRowHost; Shift: TShiftState; X, Y: Integer);
    procedure RowUp(const AHost: TTyToolWindowTabRowHost; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    function RowHintAt(const AHost: TTyToolWindowTabRowHost; X, Y: Integer; out AText: string;
      out ARect: TRect): Boolean;
```

- 现在 `HeaderMouseDown` / `HeaderMoveIn` / `HeaderMouseUp` / `HeaderHint` 的函数体搬进 `Row*`，把里面的「`AWindow` 当捕获者」换成 `AHost.Host`、「`HeaderZoneAt(AWindow, X, Y)` / `TyToolWindowZoneAt(AGeom, X, Y)`」换成按 `AHost.Geom` 查 `(X − Row.Left, Y − Row.Top)`，`HeaderDropSlotIn` 也按行内坐标。
- 公开的 `HeaderMouseDown / HeaderMouseMove / HeaderMouseUp / HeaderHint(AWindow, …)` 保留签名：先做原来的闸（`AWindow = FActive`、栏 `IsEnabled`、非设计期……），再造一个 `Host = AWindow`、`Row = AWindow.HeaderRowRect`、`Geom = AWindow.HeaderGeomAt(…)` 的宿主调 `Row*`。页那一边一行不改。
- `HeaderPressed`、`PaintHeader` 的插入线：「`FGesture.Capturer = AWindow`」改成「`FGesture.Capturer = TabRowHostControl`」。`HeaderCapturedBy(AWindow)` 不变（页只在自己当宿主时问它）。
- 栏 `MouseDown` 的底栏分支：

```pascal
  { 底栏:标签、溢出、按钮在标签行里。平时标签行长在当前页上、由它收了转过来,栏自己收到的
    (当前页没有句柄、程序里直接调的)只吞 —— 不许走图标条「点当前页就收起」的语义。当前页
    被禁用时标签行让到了栏里(spec §3.7):那就是栏自己的像素,走同一套标签行手势,捕获者是栏。 }
  if (FPlacement = twpBottom) and (part in [twbpItem, twbpOverflow, twbpMaximize, twbpCollapse]) then
  begin
    if HostsTabRow then RowDown(TabRowHost, Button, Shift, X, Y);
    Exit;
  end;
```

- 栏 `MouseMove`：底栏、`FGesture.Capturer = Self` 且手势部件是标签行部件 → `RowMove(TabRowHost, …)` 后退出（拖动、阈值都在这里）。不带键的悬停照旧走 `UpdateHoverAt`：Task 2 之后 `PartAt` 已经按 `TabRowHost` 换算，Task 1 之后它也跳过禁用窗口，不另开一条。其余照旧。
- 栏 `MouseUp`：底栏、`FGesture.Capturer = Self`、标签行部件 → `RowUp(TabRowHost, …)` 作为最后一句（它可能收起栏），之后不再碰 `Self`。
- 栏 `MouseLeave`：`HostsTabRow` 时清标签行悬停（`SetHeaderHover(twbpNone, -1)`）。
- 栏 `CMHintShow`：`HostsTabRow` 且点在 `TabRow` 里 → `RowHintAt`；有文字就 `Result := 0`，空白 `Result := 1`（不显示、不回落）。
- 栏 `DoContextPopup`：`HostsTabRow` 且点在 `TabRow` 里、不在标签上 → `Handled := True; Exit`（吞掉）；标签上照旧（`WindowAtPos` → `PartAt` 已经按 `TabRowHost` 换算，Task 2）。
- 栏加 `DoMouseWheel` 重写：`HostsTabRow` 且点在 `TabRow` 里 → `Result := True`；否则继承。`TBarAccess` 加只转发的 `CallDoMouseWheel`。
- 栏 `MouseDown` 的 `SwallowClick`：`part <> twbpNone`，**或者**当前页禁用、看得见、点落在它的 `BoundsRect` 里（Win32 上禁用页正文的按下落到栏，spec §3.7；GTK / Cocoa 上收不到）。注释写明 `OnMouseDown` / `OnMouseUp` 挡不住。

- [ ] **Step 4: 跑** `TTyToolWindowDisabledTests TTyToolWindowBottomTests TTyToolWindowBottomInputTests TTyToolWindowReorderTests TTyToolWindowStripTests TTyToolWindowEdgeTests`，全绿；变异逐条。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.disabled.pas tests/test.toolwindow.bar.pas && git commit -m "fix(toolwindows): the tab row the bar draws for a disabled page takes clicks, drags, hints and right-clicks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 主题——两个类型键、四个颜色 token（spec §12 E 期）

**Files:**
- Modify: `themes/light.tycss`
- Regenerate: `source/tyControls.DefaultTheme.pas`、`source/tyControls.Css.Catalog.pas`
- Modify: `tests/test.themes.pas`、`tests/golden/*.golden.txt`、`tests/test.defaulttheme.pas`、`tests/test.toolwindow.theme.pas`

- [ ] **Step 1: 先验生成器忠实度（动 light.tycss 之前）**

```bash
cd /d/Projects/ty-3.1 && git checkout HEAD -- themes/light.tycss && powershell -File scripts/gen-defaulttheme.ps1 && git diff --quiet -- source/tyControls.DefaultTheme.pas && echo FAITHFUL
```

Expected：`FAITHFUL`。不是就停。

- [ ] **Step 2: 写测试（判据，`TTyToolWindowThemeTests`）**

| 判据 | 在哪个变异下必须红 |
|---|---|
| 17 个内置主题 × 亮 / 暗：`TyToolWindowBadge` 有 background 和 color；`TyToolWindowDropZone` 有 background、border-color，`:hover` 的 background 与静止态不同 | 删掉任一条规则 / `:hover` 写成同值 |
| light.tycss：`TyToolWindowBadge` 的 background 等于 `--accent`、color 等于 `--on-accent`（用 `ResolveStyle('TyBadge')` 比对：两者 background、color、字重相等） | token 默认值写错 |
| 皮肤能改：`StyleOverride` 设 `--toolwindow-badge-bg: #123456` 后 `TyToolWindowBadge` 的 background 跟着变 | 规则里写死 `var(--accent)` 而不经 token |

- [ ] **Step 3: 跑，确认红**

- [ ] **Step 4: 写 light.tycss**

颜色 token（`--toolwindow-drop-color` 那一行后面）：

```css
  --toolwindow-badge-bg:            var(--accent);
  --toolwindow-badge-ink:           var(--on-accent);
  --toolwindow-dropzone-bg:         alpha(var(--toolwindow-drop-color), 0.10);
  --toolwindow-dropzone-bg-hover:   alpha(var(--toolwindow-drop-color), 0.22);
```

规则（`TyToolWindowNote` 那一行后面）：

```css
/* 工具窗口的角标(图标右上角、标签标题后面的胶囊)。写法照 TyBadge,默认值也是那套通用 token;
   自己一个键,皮肤调 --toolwindow-badge-* 或直接写这个键。尺寸 token 共用 --badge-*。 */
TyToolWindowBadge { background: var(--toolwindow-badge-bg); color: var(--toolwindow-badge-ink);
                    border-radius: var(--radius-round); font-size: var(--font-size-base);
                    font-weight: var(--font-weight-bold); padding: var(--pad-badge); }
/* 隐藏侧栏的放置预览(拖动时出现)。底色带透明度:预览是不透明的子窗口,代码先铺栏的底色再叠
   这一层。:hover = 指针在里面、它是此刻的目标。 */
TyToolWindowDropZone       { background: var(--toolwindow-dropzone-bg); color: var(--toolwindow-ink);
                             border-color: var(--toolwindow-drop-color);
                             border-width: var(--input-border-width); }
TyToolWindowDropZone:hover { background: var(--toolwindow-dropzone-bg-hover); }
```

代码里的键常量（`source/tyControls.ToolWindows.pas`，`TyToolWindowNoteKey` 旁边）：`TyToolWindowBadgeKey = 'TyToolWindowBadge'`、`TyToolWindowDropZoneKey = 'TyToolWindowDropZone'`。

- [ ] **Step 5: 跑两个生成器**

```bash
cd /d/Projects/ty-3.1 && powershell -File scripts/gen-defaulttheme.ps1 && powershell -File scripts/gen-tycss-catalog.ps1 && git status --short
```

Expected：`DefaultTheme.pas` 和 `Css.Catalog.pas` 都改了。不用跑 `gen-builtinthemes.ps1`（没动 `auto` / `system` / `builtin/*`）。

- [ ] **Step 6: GGRID 登记 + golden 重铺 + 内置主题覆盖**

`tests/test.themes.pas`：GGRID 上界 +2（`array[0..220]` → `array[0..222]`），`'TyToolWindowNote|'` 后面加 `'TyToolWindowBadge|', 'TyToolWindowDropZone|'`。GMETRICS 不动（没有长度 token）。重铺 golden（照 A 期 Task 1 Step 10：跑 `TTestThemeGolden` 得到 `.actual`，**逐个 diff 确认是纯增量**，只多出这两个键的行，再覆盖）。`tests/test.defaulttheme.pas` 的 `TestBuiltinCoversAllTypeKeys` 加 `AssertBg('TyToolWindowBadge', [])`、`AssertBg('TyToolWindowDropZone', [])`。

- [ ] **Step 7: 跑主题守卫 + `TTyToolWindowThemeTests`**，全绿；变异（把 light.tycss 的 `TyToolWindowDropZone:hover` 删掉，重跑生成器、重编）必须红，改回。

- [ ] **Step 8: 提交**

```bash
cd /d/Projects/ty-3.1 && git add themes/light.tycss source/tyControls.DefaultTheme.pas source/tyControls.Css.Catalog.pas source/tyControls.ToolWindows.pas tests/ && git commit -m "feat(toolwindows): theme keys for window badges and the drop zone

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 角标属性 + 侧栏图标上的角标（spec §8.1）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Create: `tests/test.toolwindow.badge.pas`
- Modify: `tests/tytests.lpr`

- [ ] **Step 1: 新测试单元**

`tests/test.toolwindow.badge.pas`：`TTyToolWindowBadgeTests = class(TTyToolWindowBottomFixture)`，挂进 `tytests.lpr`（`test.toolwindow.disabled,` 后面）。

- [ ] **Step 2: 写测试**

`BadgeDisplay` 是纯查询，照表写（窗口不用进栏）：

| 设置 | 期望 `(Result, AText, ADot)` |
|---|---|
| 默认 | `(False, '', False)` |
| `ShowBadge`，`BadgeValue = 0` | `(True, '0', False)`（照 `TTyButton`：开着就显示 0） |
| `ShowBadge`，`5` | `(True, '5', False)` |
| `ShowBadge`，`99` / `100` | `'99'` / `rsBadgeOverflow` |
| `ShowBadge`，`-3` | `(True, '-3', False)` |
| `ShowBadge`，`BadgeDot`，`7` | `(True, '', True)` |
| `ShowBadge`，事件把 `AVisible := False` | `(False, …)` |
| `ShowBadge`，事件把 `AText := ''`（数字模式） | `(False, …)` |
| `ShowBadge`，事件把 `AText := 'new'` | `(True, 'new', False)` |
| `ShowBadge`，`BadgeDot`，事件把 `AText := 'x'` | `(True, '', True)`（圆点模式不用文字） |
| 不开 `ShowBadge`，挂着事件 | `(False, …)`，**事件没被调** |

其余判据：

| 判据 | 在哪个变异下必须红 |
|---|---|
| 流式：三个属性默认值不写进 .lfm；`ShowBadge = True`、`BadgeValue = 150`、`BadgeDot = True` 往返（照 `TTyToolWindowStreamingTests` 的写法） | published 的 default 与构造值不一致（[[tabstop-declared-default-must-match]]） |
| 侧栏像素：Search（序号 1）`ShowBadge := True; BadgeValue := 5`，`StyleOverride` 把 `--toolwindow-badge-bg` 钉成哨兵：Search 格右上四分之一里有哨兵色，左下四分之一里没有；Explorer 格里没有 | 角不对 / 画到别的格 |
| 同上，栏 `BiDiMode := bdRightToLeft`：哨兵在**左上**四分之一 | 没有 `TyBidiFlipBadgePosition` |
| 胶囊尺寸：`BadgeValue := 150` 时哨兵的横向跨度比 `5` 时宽；`BadgeDot` 时横纵跨度都约等于 `--badge-dot-size` 按 PPI（±1） | 圆点仍按数字量 / 99+ 没走 `TyBadgeText` |
| 画在最上面：当前页（有指示条）的格子里，角标区域的像素是角标色，不是指示条色（把 `--toolwindow-strip-indicator-color` 钉成另一种哨兵、`--toolwindow-strip-indicator-size` 调大到压进角标区域） | 角标画在指示条之前 |
| 收起的栏照画：`Collapsed := True` 后 Search 格里仍有哨兵 | 收起时跳过角标 |
| 改了就重画：`BadgeValue := 6` 之后 `FBar.Invalidates` +1；`ShowBadge`、`BadgeDot` 同；设计期栏（`NewDesignBar`）同 | setter 不通知栏 |
| 跟着窗口走：`MoveWindow` 把 Search 挪到另一侧栏后，那条栏的 Search 格里有哨兵 | （守属性在窗口上；变异：把角标存在栏上按序号查） |
| 禁用窗口的角标照常颜色：Search 禁用后格里仍有哨兵原色 | 角标跟着 `:disabled` 解析 |

- [ ] **Step 3: 跑，确认红**

- [ ] **Step 4: 实现**

`tyControls.ToolWindows` 的 interface uses 加 `tyControls.Button`（`TTyBadgeDisplayEvent`、`TyBidiFlipBadgePosition`、`bpTopRight`），implementation uses 加 `tyControls.Badge`（`TyBadgeText`、`TyBadgeSize`、`TyBadgeCornerPos`、`TyBadgeInset` 等常量）。

窗口：

```pascal
  private
    FShowBadge: Boolean;
    FBadgeValue: Integer;
    FBadgeDot: Boolean;
    FOnBadgeDisplay: TTyBadgeDisplayEvent;
    procedure SetShowBadge(AValue: Boolean);
    procedure SetBadgeValue(AValue: Integer);
    procedure SetBadgeDot(AValue: Boolean);
    { 角标变了:侧栏重画;底栏丢标签宽缓存、重画当前页(Task 6 接上)。 }
    procedure BadgeChanged;
  public
    function BadgeDisplay(out AText: string; out ADot: Boolean): Boolean;
  published
    { 角标(spec §8.1),名字和语义照 TTyButton:ShowBadge 是总开关,开着时 0 也显示;> 99 显示
      '99+';OnBadgeDisplay 可以改文字或藏起来(会被频繁调用,不许有副作用)。BadgeDot 画一个
      圆点代替数字。不进布局串。 }
    property ShowBadge: Boolean read FShowBadge write SetShowBadge default False;
    property BadgeValue: Integer read FBadgeValue write SetBadgeValue default 0;
    property BadgeDot: Boolean read FBadgeDot write SetBadgeDot default False;
    property OnBadgeDisplay: TTyBadgeDisplayEvent read FOnBadgeDisplay write FOnBadgeDisplay;
```

```pascal
function TTyToolWindow.BadgeDisplay(out AText: string; out ADot: Boolean): Boolean;
var
  vis: Boolean;
begin
  AText := '';
  ADot := FBadgeDot;
  if not FShowBadge then Exit(False);
  AText := TyBadgeText(FBadgeValue, False);   { 圆点也先给数字,事件看得到;画的时候不用 }
  vis := True;
  if Assigned(FOnBadgeDisplay) then FOnBadgeDisplay(Self, FBadgeValue, AText, vis);
  if ADot then
  begin
    AText := '';
    Result := vis;
  end
  else
    Result := vis and (AText <> '');
end;
```

`BadgeChanged`：`Bar <> nil` 且栏不在释放中时——侧栏 `Bar.Invalidate`；底栏留给 Task 6（这一步先同样 `Bar.Invalidate`，Task 6 改成丢缓存 + `InvalidateHeader`）。

栏加 private（一处量，开工前问题 12）：

```pascal
    { 角标的尺寸(设备像素,按 APPI)和文字;不画时 (0, 0)。文字宽按标签的量法(两种量法取大),
      高按 '0',交给 TyBadgeSize —— 量标签宽和画胶囊都问这里,两边差一个像素胶囊就压到下一个
      标签上。样式取 TyToolWindowBadge 静止态;内边距、--badge-min-size、--badge-dot-size 按 PPI。 }
    function BadgeSizeAt(AWindow: TTyToolWindow; APPI: Integer; out AText: string;
      out ADot: Boolean): TSize;
    { 在 ABox 里按 ACorner 画 AWindow 的角标(画笔坐标);不画就什么都不做。圆点画成圆,数字画
      胶囊(圆角照 TTyButton.DrawBadge:主题没给圆角就半高),文字用 ASmallCrisp。 }
    procedure DrawBadgeIn(APainter: TTyPainter; AWindow: TTyToolWindow; const ABox: TRect;
      APPI: Integer);
```

`DrawBadgeIn` 的画法照 `TTyButton.DrawBadge`（`Button.pas:433-495`）：填底（`TyUniformCorners(半高)`，主题给了更小的圆角就用主题的）、文字框四边各放 1 个像素再 `DrawText(..., taCenter, tlCenter, False, 0, True)`。尺寸从 `BadgeSizeAt` 来，不再现量。

栏 `RenderTo` 的图标循环里，指示条画完之后：

```pascal
        { 角标(spec §8.1):图标格右上角,按画笔的读写方向镜像(同 TTyButton);在最上面。 }
        sz := BadgeSizeAt(Windows[L.Slots[i].ItemIndex], APPI, btxt, bdot);
        if sz.cx > 0 then
        begin
          pt := TyBadgeCornerPos(cell, sz.cx, sz.cy,
            MulDiv(ActiveController.Metric(TyBadgeInsetVar, TyBadgeInset), APPI, 96),
            TyBidiFlipBadgePosition(bpTopRight, P.RightToLeft));
          DrawBadgeIn(P, Windows[L.Slots[i].ItemIndex], Rect(pt.X, pt.Y, pt.X + sz.cx, pt.Y + sz.cy), APPI);
        end;
```

（循环里 `Windows[...]` 按地雷 7 先取一次 `WindowList(nil)`。）

- [ ] **Step 5: 跑** `TTyToolWindowBadgeTests TTyToolWindowStripTests TTyToolWindowStreamingTests TTyToolWindowTests TTyToolWindowManagerTests`，全绿；变异逐条。

- [ ] **Step 6: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.badge.pas tests/tytests.lpr && git commit -m "feat(toolwindows): tool windows carry a badge, drawn on their strip icon

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 底栏标签的角标 + 溢出菜单（spec §7.3 E 期、§8.1）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.badge.pas`

- [ ] **Step 1: 写测试（判据）**

`NewBottomBar(['Problems', 'Output', 'Terminal'], 1)`，`BottomTheme` + `--toolwindow-badge-bg` 钉成哨兵。「标签宽」一律从 `ActiveGeom` 的标签矩形取。

| 判据 | 在哪个变异下必须红 |
|---|---|
| Problems `ShowBadge`、`BadgeValue = 3`：Problems 标签宽 = 原宽 + `header-gap` + `BadgeSizeAt` 的宽（测试用同一套公开函数现算：`TyMeasureTextBlock` / `TyMeasureRenderedTextWidth` 取大、`TyBadgeSize`）；另两个标签宽不变 | 忘了间隔 / 量法跟画法不一致 |
| 缓存键：只改 `BadgeValue` 3 → 150（标题不动），Problems 标签宽跟着变 | 标签宽缓存键不含角标 |
| 事件：`OnBadgeDisplay` 按测试里的一个开关把文字改成 `'many'`，拨开关后 `Problems.Invalidate`：标签宽跟着变 | 缓存键记的是 `BadgeValue` 而不是事件之后的文字 |
| 像素（LTR）：Problems 标签里哨兵在标题墨迹的**右边**（哨兵的最左像素 > 标题墨迹的最右像素） | 胶囊画在标题前面 |
| 像素（当前页 `BiDiMode := bdRightToLeft`）：哨兵在标题墨迹的**左边** | 胶囊的位置没随几何镜像 |
| 当前页标签被截（栏窄到只剩当前页、标题出省略号）：胶囊仍在（哨兵像素 > 0） | 截标题时把胶囊也截了 |
| 改非当前页的角标：当前页缓存要重渲染（`ArmActive` 之后 `Problems.BadgeValue := 4`，`CacheWouldRender` 为真） | setter 只重画栏、不 `InvalidateHeader` |
| 标签宽变了当前页的操作区跟上（B 期收尾的漂移检查）：Output 有操作区，行宽刚好的时候给 Problems 加一个 `99+`、让 Terminal 挤进溢出：`ActiveGeom.Overflow` 非空、Terminal 进了 `OverflowWindows` | 只重画不重排 |
| 溢出菜单（开工前问题 5）：Terminal `BadgeValue = 7` 且被挤进溢出，点溢出按钮后菜单项标题 = `'Terminal (7)'`；圆点模式 `'Terminal •'`；不显示角标时就是 `'Terminal'` | 菜单项不带角标 |
| 提示不带数字（开工前问题 6）：Problems 标签的 `HeaderHint` 文字 = `StripHint` / `Caption`，不含 `'3'` | —（守现状；变异：提示拼上角标文字） |

- [ ] **Step 2: 跑，确认红**

- [ ] **Step 3: 实现**

- `MeasureTabWidths`：每个窗口 `BadgeSizeAt(w, APPI, …)` 宽 > 0 时，标签宽再加 `TokenPxAt(TyToolWindowHeaderGapVar, …)` + 胶囊宽。
- `TabWidthsAt` 的缓存键加一个数组 `FTabCacheBadges: array of string`：每个窗口一项，`BadgeDisplay` 答假记 `''`，圆点记 `#1'dot'`（任何不会是真文字的串都行，注释写明），数字记 `'#' + AText`。逐项比，和标题那一组同一个循环。
- `PaintHeader` 的标签循环：`BadgeSizeAt` 宽 > 0 时，从文字框（`box`）的阅读终点一侧切出 `gap + 胶囊宽`：LTR 切右边、RTL（`AWindow.IsRightToLeft`，几何按它镜像）切左边；切完文字框 ≥ 0 才画胶囊（放不下就只画标题）。胶囊在切出来的那一段里、贴着标题一侧、按行高垂直居中，调 `DrawBadgeIn`。下划线仍横跨切之前的整个文字框（胶囊是标签的一部分）。
- `TTyToolWindow.BadgeChanged`：底栏改成 `FTabCacheValid := False`（栏的一个 private 方法 `TabWidthsChanged`，只清标志）+ `InvalidateHeader`；B 期收尾的漂移检查会在当前页的 `Invalidate` 里把操作区跟上。
- `ShowOverflowMenu`：菜单项标题 = `Caption`，`BadgeDisplay` 答真时数字加 `' (' + AText + ')'`，圆点加 `' •'`（U+2022，`#$E2#$80#$A2`）。

- [ ] **Step 4: 跑** `TTyToolWindowBadgeTests TTyToolWindowBottomTests TTyToolWindowBottomInputTests TTyToolWindowGeometryTests`，全绿；变异逐条。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.badge.pas && git commit -m "feat(toolwindows): badges on bottom tabs and in the overflow menu

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `HideWhenEmpty`——一侧没有窗口时宽 0（spec §6.9、§6.1、§5.4）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Create: `tests/test.toolwindow.hide.pas`
- Modify: `tests/tytests.lpr`、`tests/test.toolwindow.bar.pas`

- [ ] **Step 1: 新测试单元**

`tests/test.toolwindow.hide.pas`：`TTyToolWindowHideTests = class(TTyToolWindowManagerFixture)`，挂进 `tytests.lpr`（`test.toolwindow.badge,` 后面）。`TBarAccess` 加只转发的 `CallConstrainedResize(var MinW, MinH, MaxW, MaxH)`。

- [ ] **Step 2: 写测试**

`HiddenAsEmpty` 纯查询表（每一行一条新栏）：

| 栏 | 期望 |
|---|---|
| 运行时左栏，没有窗口 | True |
| 运行时右栏，没有窗口 | True |
| 运行时左栏，没有窗口，`HideWhenEmpty := False` | False |
| 运行时左栏，一个窗口 | False |
| 运行时左栏，没有窗口，漏进来一个非窗口子控件 | True |
| 设计期左栏（`NewDesignBar`），没有窗口 | False |
| 运行时底栏，没有窗口 | False（底栏不管，高本来就是 0） |
| 运行时左栏，没有窗口，`Collapsed := True` | True |

其余判据：

| 判据 | 在哪个变异下必须红 |
|---|---|
| 隐藏的左栏：`CallDerivedAxisPx = 0`；`BarLayout` 的 `Strip`、`Cells`、`Edge`、`Content` 全空；`Visible` 仍为真 | `FixedAxisPx` 不看隐藏 / 写了 `Visible` |
| `HideWhenEmpty := False` 的空左栏：`CallDerivedAxisPx` = 图标条 + 2 × chrome（A 期的样子） | 把「没有窗口」一律当隐藏 |
| `CallConstrainedResize` 的 `MinWidth` 在隐藏时保持 0 | `ConstrainedResize` 仍给图标条宽（地雷 9） |
| 底栏：`HideWhenEmpty` 真假两种，空底栏的推导高都是 0，有窗口的都一样 | 底栏也被属性影响 |
| 最后一个窗口走：左栏只有 Outline，`MoveWindow(Outline, 右栏)` 之后左栏 `Width = 0`（夹具 `LayOut`）；再挪回来：`Width` = 图标条 + 2 × chrome + 边缘区 + 内容 | 注销之后不重推 |
| `Collapsed` 不被写：隐藏前 `Collapsed = True` 的栏，挪回一个窗口（`MoveWindow` 会展开目标栏，§9.5）后照 §9.5 展开；隐藏期间读 `Collapsed` 不变 | 隐藏时顺手写了 `Collapsed` |
| `ExpandedSize` 不变 | 隐藏时顺手写了 `ExpandedSize` |
| 改属性重推：空右栏 `HideWhenEmpty := False` 之后宽 > 0，改回 True 之后宽 0 | setter 不 `Relayout` |
| 可用性：隐藏的右栏 `ToolMgr.IsBarUsable = True`、`UsableBar(twpRight)` 答它；`MoveWindow(W, 右栏)` 答 True 且右栏出现 | 把隐藏当成不可用 |
| 分空间（§6.2）：父控件很窄、两侧都要空间时，右栏隐藏后左栏拿到的内容宽 = 它不跟右栏分时的值 | 隐藏的栏仍按图标条扣固定部分 |
| 布局读取：存一份右栏有窗口的串 A、一份右栏空的串 B；读 B：右栏宽 0；读 A：右栏宽 > 0 | —（守推导；变异：布局应用绕过 `Relayout`） |
| 流式：`HideWhenEmpty = True` 不写进 .lfm；`False` 写进去并读回 | default 与构造值不一致 |
| 设计期不隐藏：设计期空左栏宽 = 展开宽，`EmptyNote` 非空 | 条件漏了设计期 |

- [ ] **Step 3: 跑，确认红**

- [ ] **Step 4: 实现**

栏：

```pascal
  private
    FHideWhenEmpty: Boolean;
    procedure SetHideWhenEmpty(AValue: Boolean);
  public
    { 运行时、侧栏、HideWhenEmpty、没有窗口(spec §6.9)。推导宽 0,不写 Visible。 }
    function HiddenAsEmpty: Boolean;
  published
    { 一侧没有窗口时整条隐藏(推导宽度为 0),默认开;只对侧栏起作用 —— 底栏没有窗口时本来就
      高 0。设计期永远不隐藏。隐藏的栏照样可用(IsBarUsable / UsableBar / MoveWindow),拖动时
      在它的位置显示放置预览。 }
    property HideWhenEmpty: Boolean read FHideWhenEmpty write SetHideWhenEmpty default True;
```

构造里 `FHideWhenEmpty := True`（和 published 的 default 一致）。

```pascal
function TTyToolWindowBar.HiddenAsEmpty: Boolean;
begin
  Result := FHideWhenEmpty and (FPlacement <> twpBottom)
    and not (csDesigning in ComponentState) and (WindowCount = 0);
end;
```

（Task 8 会在这里加 `and not FAssumeShown`。）

- `FixedAxisPx` 侧栏那一支开头：`if HiddenAsEmpty then Exit(0);`
- `ConstrainedResize` 侧栏那一支：`if HiddenAsEmpty then lo := 0 else ...`（原来的计算放进 else）。
- `LayoutAt`：开头 `if HiddenAsEmpty then Exit(Default(TTyToolWindowBarLayout));`（Content 空、没有图标条、没有边缘区；设计期不会走到这里）。
- `SetHideWhenEmpty`：值变了且不在加载中 → `Relayout; Invalidate;`。
- `UnnarrowedContentPx` 已经在「没有窗口」时答 0（`SizesAsCollapsed`），不用改。

- [ ] **Step 5: 跑** `TTyToolWindowHideTests TTyToolWindowBarTests TTyToolWindowManagerTests TTyToolWindowLayoutApplyTests TTyToolWindowStreamingTests TTyToolWindowCrossDragTests TTyToolWindowDesignTests`，全绿；变异逐条。

**注意**：C 期、D 期可能有测试把「拖空的侧栏保留图标条」当成前提（比如拖空之后再往它的图标条上拖、量它的宽）。这些测试在默认 `HideWhenEmpty = True` 下会红——**先判断它守的是什么**：守的是「空栏仍是放置目标」的，把夹具里那条栏设 `HideWhenEmpty := False` 保留原意，另在 Task 8 用隐藏栏补一条；守的就是「保留图标条」本身的，改成新期望。每一处改动在提交信息里列出来（[[tests-that-pin-the-bug]]）。

- [ ] **Step 6: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/ && git commit -m "feat(toolwindows): a side bar with no windows hides itself (HideWhenEmpty)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 放置预览（spec §9.4、§9.8 E 期）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`、`source/tyControls.ToolWindows.Manager.pas`
- Modify: `source/tyControls.StrConsts.pas`、`languages/tyControls.StrConsts.pot`、`languages/tycontrols.strconsts.zh_CN.po`
- Modify: `tests/test.toolwindow.hide.pas`

- [ ] **Step 1: 写测试（判据）**

`NewLeftRight`（左 Explorer / Search / Git，右 Outline），先 `MoveWindow(Outline, 左栏)` 让右栏空了、隐藏；`LayOut` 两条栏和父控件。拖动一律真实入口：在左栏 Search 图标上 `CallMouseDown`、`CallMouseMove` 过阈值（进入 Dragging），再按屏幕坐标换算到左栏客户区继续 `CallMouseMove`。

| 判据 | 在哪个变异下必须红 |
|---|---|
| 进入 Dragging 之后：`RightBar.DropPreview <> nil`、`Visible`、`Parent = RightBar.Parent`、不在任何栏的 `Controls` 里 | 不显示预览 / 挂错父控件 |
| 位置：`BoundsRect.Right = RightBar.Left`（右栏宽 0）、`Top = RightBar.Top`、`Height = RightBar.Height`；宽 = 右栏「有一个窗口、展开着」时的推导宽（测试临时 `HideWhenEmpty := False` 并放一个窗口量出来的 `CallDerivedAxisPx`，量完还原） | 宽只取 `ExpandedSize`（漏了图标条 / chrome / 边缘区）/ 不按 §6.2 收窄 |
| 父控件窄到放不下时：预览宽 = 收窄后的值，且钳在父控件调整后的客户区里 | 预览不收窄 |
| 按下未过阈值：没有预览 | 按下就显示 |
| 指针移进预览（屏幕坐标取预览中心）：`ToolMgr.DropTargetAt` 答右栏、槽位 0；预览 `Hot`；光标 `crDrag` | 探测矩形用右栏的 `ClientRect`（宽 0，永远点不中） |
| 移出预览回到编辑区：`Hot` 假、光标 `crNoDrop` | `SetForeignDrop(-1)` 不清 `Hot` |
| 在预览里松开：Search 到了右栏、是右栏当前页、右栏宽 > 0、`Collapsed = False`；预览不可见；`OnWindowMoved` 发了一次 | 提交不走 `MoveFromDrop` / 收尾不收预览 |
| `Esc`（`Perform(CN_KEYDOWN, VK_ESCAPE)` 在无关控件上）/ `ToolMgr.CancelDrag`：预览不可见 | 收尾（`ReleaseResources` 清 `FDragSource`）不通知 |
| `OnCanMoveWindow` 否决右栏：指针在预览里 → `DropTargetAt` 答 nil、光标 `crNoDrop`、预览不 `Hot`；预览照样显示（否决要等指针进去才知道） | 否决时仍 `Hot` / 进入拖动时就问了 `CanMoveWindow` |
| `HideWhenEmpty := False` 的空右栏：没有预览（它有图标条，照旧是插入线目标） | 按「没有窗口」而不是按「隐藏」判 |
| 底栏标签拖动（底栏也注册在这个 manager 上）：没有预览 | 预览不看源栏是不是侧栏 |
| 禁用的右栏（`RightBar.Enabled := False`）：没有预览 | 候选条件没和 `DropTargetAt` 共用（`IsCrossCandidate`） |
| 兄弟监听：显示预览之后（再触发一次推导）左栏 `WatchedSiblingCountForTest` 不变 | 没跳过预览（地雷 10） |
| 像素：预览 `RenderTo` 到哨兵底上：整块没有哨兵色（不透明）；文字行有 `--toolwindow-ink`（钉成哨兵）的墨迹；`Hot` 时底色与不 `Hot` 时不同 | 预览透明 / 不画文字 / `:hover` 没接 |
| 文案放得下（开工前问题 7）：96 PPI、默认主题，右栏 `ExpandedSize = 240` 时的预览宽 − 2 × `header-pad` ≥ `rsTyToolWindowDropRight` 的宽（两种量法取大）；左栏同 | 文案改长 |
| 拖动中释放右栏（`RightBar.Free`）：不 AV，之后松开不挪窗口；拖动中释放 manager：不 AV | 预览没随栏释放 / manager 析构时不收预览 |
| 预览显示时栏被改成 `HideWhenEmpty := False` 或来了一个窗口（代码 `MoveWindow` 在处理器外调不了——用 `Parent :=` 直接挂一个新窗口）：预览收掉 | 条件变了不重对 |

- [ ] **Step 2: 跑，确认红**

- [ ] **Step 3: 实现**

**预览控件**（interface，放在栏前面）：

```pascal
  { 隐藏侧栏的放置预览(spec §9.8):拖动时在隐藏的那一侧、按那条栏展开后的宽显示一块。
    有句柄的子控件,不是顶层窗口(Wayland 不让程序定位顶层窗口);不透明、不拿焦点、不参加
    对齐。拖动期间捕获在源栏上,它收不到鼠标,命中全靠 manager 的几何。Owner = nil,由栏持有。 }
  TTyToolWindowDropPreview = class(TTyCustomControl)
  private
    FBar: TTyToolWindowBar;
    FHot: Boolean;
    procedure SetHot(AValue: Boolean);
  protected
    function GetStyleTypeKey: string; override;          { TyToolWindowDropZoneKey }
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  public
    constructor CreateFor(ABar: TTyToolWindowBar);
    procedure Paint; override;
    property Hot: Boolean read FHot write SetHot;
  end;
```

- 构造：`inherited Create(nil)`；`ControlStyle := ControlStyle + [csNoFocus, csNoDesignVisible, csOpaque] - [csAcceptsControls]`；`TabStop := False`；`Align := alNone`；`Visible := False`；`Controller` 跟栏的 `Controller`（`ShowDropPreview` 里每次推一次）。
- `RenderTo`：`BeginPaint` 用栏的 `IsRightToLeft`；先铺 `TyToolWindowBar` 静止态 background（`ResolveStyle(TyToolWindowBarKey, 栏的样式类, [tysNormal])`），再按 `TyToolWindowDropZone`（`[tysHover]` 或 `[tysNormal]`）`DrawFrame`；正中一行 `rsTyToolWindowDropLeft` / `Right`（按栏的 `Placement`），左右各缩一个 `--toolwindow-header-pad`，`taCenter`、`tlCenter`、省略号。不做绘制缓存（只在拖动中存在，重画少）。
- `SetHot`：变了才 `Invalidate`。

**栏**：

```pascal
  private
    FDropPreview: TTyToolWindowDropPreview;
    { 只在 ShownAxisPx 里置位:SizesAsCollapsed / HiddenAsEmpty 按「有一个窗口、展开着」答。 }
    FAssumeShown: Boolean;
    { 这条栏有一个窗口、展开着时推导出来的轴向尺寸(放置预览的宽,spec §9.8)。别的栏照常按
      自己的真实状态参加 §6.2 分空间。 }
    function ShownAxisPx: Integer;
    procedure ShowDropPreview;
    procedure HideDropPreview;
    procedure SetDropPreviewHot(AOn: Boolean);
  public
    function DropPreviewRect: TRect;
    property DropPreview: TTyToolWindowDropPreview read FDropPreview;
```

- `SizesAsCollapsed` 和 `HiddenAsEmpty` 各加 `and not FAssumeShown`。
- `ShownAxisPx`：`FAssumeShown := True; try Result := DerivedAxisPx(Metrics) finally FAssumeShown := False end`。
- `DropPreviewRect`：不是 `HiddenAsEmpty` 或没有父控件 → 空；否则 w = `ShownAxisPx`，左栏 `Rect(Left, Top, Left + w, Top + Height)`、右栏 `Rect(Left + Width - w, Top, Left + Width, Top + Height)`，再和父控件 `ClientRect` 经 `AdjustClientRect` 之后的矩形求交。
- `ShowDropPreview`：`DropPreviewRect` 为空就 `HideDropPreview` 退出；没建过就 `TTyToolWindowDropPreview.CreateFor(Self)`；推 `Controller`；`Color` 设成解析出的栏底色（地雷 10）；`Parent := Parent`（本栏的父控件，每次都设，栏可能换过父控件）；`BoundsRect := 那个矩形`；`Hot := False`；`Visible := True`；`BringToFront`。
- `HideDropPreview`：有就 `Hot := False; Visible := False`（不释放，下次拖动复用；栏析构时 `FreeAndNil`）。
- `SetForeignDrop(ASlot)`：`HiddenAsEmpty` 时不 `Invalidate` 自己（没有像素），改调 `SetDropPreviewHot(ASlot >= 0)`；其余照旧。
- `WatchSiblings`：跳过 `TTyToolWindowDropPreview`（Task 0 Step 4 第 4 条查到的那个循环）。
- 析构：`FreeAndNil(FDropPreview)`（在 `Destroying` 之后、继承之前；预览的 Parent 是别的控件，先摘 Parent 再释放）。
- `Relayout` 末尾：预览正显示着、而 `HiddenAsEmpty` 变假了（来了窗口、属性改了）→ `HideDropPreview`。

**manager 基类**（`TTyCustomToolWindowManager`）：

```pascal
  private
    { FDragSource 只经这里写:值变了就调 DragSourceChanged。 }
    procedure SetDragSource(ABar: TTyToolWindowBar);
  protected
    { 「正在拖」变了(进入拖动 / 手势收尾)。TTyToolWindowManager 在这里显示 / 收掉隐藏侧栏的
      放置预览(spec §9.8)。基类什么都不做。 }
    procedure DragSourceChanged; virtual;
```

引擎里两处直接赋值（`BeginDragging` 末尾、`ReleaseResources`）改成 `FBar.Manager.SetDragSource(FBar)` / `SetDragSource(nil)`（后者照旧只在 `FDragSource = FBar` 时）。

**manager**（`tyControls.ToolWindows.Manager.pas`）：

- 抽出 `function IsCrossCandidate(ASource, ABar: TTyToolWindowBar): Boolean`：`DropTargetAt` 循环里那一串条件原样搬过来（`b <> ASource`、不是底栏、`IsBarUsable`、`VisibleInForm`、`IsEnabled`、不在释放中、同一窗体），`DropTargetAt` 改成调它。
- `DragSourceChanged` 重写：`FDragSource` 非空、是侧栏、`IsBarUsable(FDragSource)` → 对每条注册栏 `b`：`IsCrossCandidate(FDragSource, b) and b.HiddenAsEmpty` 就 `b.ShowDropPreview`，否则 `b.HideDropPreview`；`FDragSource` 为 nil → 每条都 `HideDropPreview`。
- `DropProbeOf(b)`：`b.HiddenAsEmpty` 时 `Visible` = `b.DropPreviewRect` 换屏幕坐标、再和父控件及每一级祖先的屏幕客户区求交（照 `VisibleScreenRect` 的写法另写一个 `VisibleScreenRectOf(AParent, ARect)`）；`Cells` 为空、`Slots` 为空、`Count = 0`、`Holes` 为空。其余照旧。
- 析构 / `opRemove` 摘栏时：被摘的栏 `HideDropPreview`。

**文案**（`source/tyControls.StrConsts.pas`，`rsTyToolWindowCrossBarMove` 后面）：

```pascal
  { Drawn in the drop zone that stands in for a hidden (empty) side bar while a tool window is
    being dragged: releasing inside it moves the window there and the bar appears. Must fit a
    side bar's default width (240 logical px). }
  rsTyToolWindowDropLeft  = 'Drop here to show the left side bar';
  rsTyToolWindowDropRight = 'Drop here to show the right side bar';
```

pot / zh_CN.po 按 key 字母序（`rstytoolwindowcrossbarmove` 后面、`rstytoolwindowmaximize` 前面），中文 `放到左侧栏` / `放到右侧栏`（pot 里 `msgstr ""`）。

- [ ] **Step 4: 跑** `TTyToolWindowHideTests TTyToolWindowCrossDragTests TTyToolWindowManagerTests TTyToolWindowManagerLiveTests TTyToolWindowStripTests TTyToolWindowBarTests TI18NTest`，全绿；变异逐条。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas source/tyControls.ToolWindows.Manager.pas source/tyControls.StrConsts.pas languages/tyControls.StrConsts.pot languages/tycontrols.strconsts.zh_CN.po tests/test.toolwindow.hide.pas && git commit -m "feat(toolwindows): dragging shows a drop zone where a hidden side bar would open

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 示例（开工前问题 8）

**Files:**
- Modify: `examples/toolwindows/umain.pas`、`examples/toolwindows/umain.lfm`
- Modify: `examples/toolwindows/languages/toolwindows_example.zh_CN.po`、`examples/toolwindows/languages/tycontrols.zh_CN.po`

规矩同 D 期 Task 7（[[examples-must-be-lfm-titlebar-skin]]、[[demo-edits-lfm-not-code]]、[[example-content-two-purposes]]）：设置进 .lfm，只有「必须是代码」的在代码里。

- [ ] **Step 1: .lfm**

- `SearchWin`：`ShowBadge = True`、`BadgeValue` = `SearchList` 里的条数。
- `ProblemsWin`：`ShowBadge = True`、`BadgeValue` = `ProblemsList` 里的条数。
- `OutputWin`：`BadgeDot = True`（`ShowBadge` 不写，默认 False；由代码开关）。
- `RightBar`：`HideWhenEmpty` 不写（默认 True）。
- Diagnostics 菜单：`MnuDiagDisable` 保留（标题不变 `Disable &Output Page`）；后面加 `MnuDiagDisableSearch`（`Disable &Search Window`，勾选项）；再加一条分隔线和 `MnuDiagBadge`（`Add 45 &Problems`）。

- [ ] **Step 2: 代码**

| 处理器 | 做什么 | 验什么 |
|---|---|---|
| `Log` | 加一行之后：`OutputWin` 不是正在看的那一页（`not OutputWin.IsActive or BottomBar.Collapsed`）就 `OutputWin.ShowBadge := True` | 圆点角标 |
| `OutputWin.OnShow`（新） | `OutputWin.ShowBadge := False` | 切过去就灭 |
| `MnuDiagDisableClick` | 注释改成新行为：禁用 Output 页之后正文和操作区失效，但标签行还能切、能收起、能最大化；Output 标签灰、点不回去。代码不变 | spec §3.7；真机验收第 38 项 |
| `MnuDiagDisableSearchClick`（新） | `SearchWin.Enabled := not SearchWin.Enabled`，同步勾选，写日志 | 侧栏的禁用语义；真机验收第 44、45 项 |
| `MnuDiagBadgeClick`（新） | `ProblemsWin.BadgeValue := ProblemsWin.BadgeValue + 45`，写日志 | `99+`、标签变宽、挤进溢出 |

新日志格式都是 resourcestring。示例单元头的注释补两句：角标在哪几页、把 Outline 拖到左边右栏就隐藏、再拖一个图标能看到右侧的放置预览。

- [ ] **Step 3: i18n**

- `languages/tycontrols.zh_CN.po`：**整份复制** `languages/tycontrols.strconsts.zh_CN.po`（此刻已含 Task 8 的两条）。
- `languages/toolwindows_example.zh_CN.po`：新菜单项的 `Caption`、新 resourcestring 各一条（key 规则见 D 期 Task 7 Step 4）。

- [ ] **Step 4: 静态检查（实现 agent 做）**

```bash
cd /d/Projects/ty-3.1 && python scripts/check-lfm-props.py . ; python scripts/check-example-po.py .
```

再跑 `TEnglishFitTest TSkinFitTest TI18NTest`，全绿。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add examples/toolwindows && git commit -m "feat(examples): toolwindows shows badges, a right bar that hides, and a disabled page you can leave

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: 【主控执行】编、冒烟、po 核对**（在 Task 10 之后和包一起做，见 Task 11 Step 4）

---

### Task 10: 控件文档 `docs/controls/toolwindows.md`

**Files:**
- Modify: `docs/controls/toolwindows.md`

原生语感、短句、能列表就不写段落（[[doc-writing-native-tone]]）。

- [ ] **Step 1: 改**

1. §2 typeKey 表加 `TyToolWindowBadge`（图标 / 标签上的角标）、`TyToolWindowDropZone`（拖动时隐藏侧栏的放置预览；`:hover`）；token 表加四个颜色 token。说一句：角标默认颜色同 `TyBadge`，但不跟着皮肤的 `TyBadge` 规则走，要改就改 `--toolwindow-badge-*`。
2. §3 栏的表加 `HideWhenEmpty`；窗口的表加 `ShowBadge` / `BadgeValue` / `BadgeDot` / `OnBadgeDisplay`（一行一句，照 `TTyButton` 的说法）。
3. 新加一节「角标」：放在哪（侧栏图标右上角、底栏标题后面）；0 也显示（`ShowBadge := n > 0` 可以藏）；`99+`；圆点；`OnBadgeDisplay` 会被频繁调用、别有副作用，事件的答案变了要自己 `Invalidate`；溢出菜单里带数字；不进布局串。
4. 新加一节「一侧没有窗口时」：默认整条隐藏（宽 0，`Visible` 不动）；拖动时隐藏的那一侧出现放置预览，松手就过去；「移到另一侧」、`MoveWindow` 照常；`HideWhenEmpty := False` 保留图标条；底栏不受影响；设计期不隐藏。
5. 新加一节「禁用工具窗口」（替换 §9 注意事项里「不要禁用 `TTyToolWindow` 本身」那一条）：禁用窗口 = 内容禁用；它的图标 / 标签灰掉、点了不切、不能拖，代码照常能切过去；当前页被禁用时标签行照常能切、收起、最大化，底栏它的操作区在禁用期间看不见（按开工前问题 1 的结论写）；侧栏点当前页的灰图标仍能收起；Win32 上点禁用页的正文，栏的 `OnMouseDown` / `OnMouseUp` 会触发（`OnClick` 不会）。
6. §10 差异：「拖空的侧栏保留图标条」改成新说法；「不做」里去掉「图标 / 标签上的数字徽标」，「边缘靠近弹出」改成「不拖动时指针靠近边缘弹出」。
7. §11 示例：补角标、隐藏、Diagnostics 两项。

- [ ] **Step 2: 自查**

`grep -n "不要禁用" docs/controls/toolwindows.md` 为空；文中每个成员名在 `source/` 里 grep 得到；`grep -c "——" docs/controls/toolwindows.md` 没有比改之前多太多。

- [ ] **Step 3: 提交**

```bash
cd /d/Projects/ty-3.1 && git add docs/controls/toolwindows.md && git commit -m "docs(toolwindows): disabled windows, badges and hiding an empty side

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: 收尾——按 spec 逐条核、grep、全量、编包、抽查变异、审查、写回 spec、签收

**Files:**
- Modify: `docs/superpowers/plans/2026-09-27-toolwindow-phase-e.md`
- Modify: `docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md`

- [ ] **Step 1: 按 spec 逐条核代码，不看测试**（[[green-tests-are-not-spec-conformance]]）

逐条对着代码查，每条记「在哪一行实现 / 为什么不需要」：

- §3.7 语义的每一条（七个圆点 + 当前页被禁用的两条 + 手势取消）；「让出标签行」细则的每一条（条件、行高、`TabRow`、页答 0、几何不重排、画、输入五样、`TabRowHost` 的六个调用点、三个时机、Win32 吞 Click）。
- §6.5 / §7.4 / §9.1 的 E 期补：禁用窗口不接悬停、不武装、不是把手；当前页例外。
- §8.1：四个属性和语义、侧栏角的位置和镜像、画在最上面、收起照画、底栏胶囊的位置 / 截断 / 下划线、不看禁用、溢出菜单、提示、改了之后的通知。
- §7.3：标签宽加间隔 + 胶囊，缓存键含角标显示。
- §6.9：条件、推导宽 0、不写 `Visible`、最小尺寸、`LayoutIn` 全空、和 `Collapsed` / `ExpandedSize` 的关系、时机、可用性不变、布局。
- §6.2 E 期补：隐藏栏分空间为 0；预览按假设显示推导；兄弟监听跳过预览。
- §9.4：隐藏栏是候选、探测矩形 = 预览、slot 0、`TyToolWindowDropAt` 没改、`CanMoveWindow` 只在进入时问。
- §9.8：预览的出现 / 收掉时机、位置、控件性质、画法、`Hot`、松手提交。
- §12：两个键、四个 token、写在 light.tycss。

- [ ] **Step 2: grep**

```bash
cd /d/Projects/ty-3.1 && grep -n "Task [0-9]* 接上\|Task [0-9]* 改成" source/tyControls.ToolWindows*.pas; for f in HostsTabRow TabRowHost HiddenAsEmpty DropPreviewRect BadgeDisplay IsCrossCandidate DragSourceChanged BottomRowHeightAt BadgeSizeAt; do printf '%s: src=%s tests=%s\n' $f $(grep -rlw $f source | wc -l) $(grep -rlw $f tests | wc -l); done; grep -rn "rsTyToolWindowDrop" source examples | wc -l
```

Expected：没有残留的「Task N 接上」之类的临时注释；每个名字在 `source/` 里有人用（src ≥ 1，[[built-not-wired-is-the-default-failure]]）、在 `tests/` 里有人测；两条文案在 `source/` 里被画预览的代码引用。

- [ ] **Step 3: 跑全量**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --all --format=plain > /tmp/all.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/all.txt
```

Expected：errors / failures 都是 0，总数 = Task 0 的基线 + 本期新增条数。红了先按 [[known-rare-suite-flake]]、[[suite-order-widgetset-init]]、[[canary-then-rebuild]] 排查。

- [ ] **Step 4: 【主控执行】编包、编示例、冒烟、po 核对**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tycontrols.lpk > /tmp/pkg.txt 2>&1; tail -2 /tmp/pkg.txt && rm -rf examples/toolwindows/lib && lazbuild -B examples/toolwindows/toolwindows_example.lpi > /tmp/ex.txt 2>&1; grep -iE "error|fatal" /tmp/ex.txt | head; tail -2 /tmp/ex.txt; git status --short languages/
```

然后：`powershell -File scripts/smoke-launch-examples.ps1`（toolwindows 要起得来）；`python scripts/example-rsj2po.py examples/toolwindows toolwindows_example <只含 {} 的 json>` 不报 ERROR；`languages/` 有出入以生成的为准另提交一次。主控自己开一次示例：启动不崩、Search 和 Problems 有角标、把 Outline 拖到左边右栏消失、再拖一个图标看到右侧预览。**只到这里**，完整走查留给用户（本计划末尾的表）。设计期包没改，不用编 `tycontrols_dt.lpk`。

- [ ] **Step 5: 抽查变异（每条三拍，必须红）**

1. Task 1：`WindowClickable` 改成恒真。
2. Task 2：`HeaderHeightAt` 里「让出答 0」那一句删掉。
3. Task 3：`RowDown` 查几何时不减 `Row.TopLeft`（地雷 6）。
4. Task 6：标签宽缓存键不含角标。
5. Task 7：`ConstrainedResize` 不看 `HiddenAsEmpty`。
6. Task 8：`DropProbeOf` 对隐藏栏仍用 `ClientRect`。

- [ ] **Step 6: 整体代码质量审查**

对 `git diff <Task 0 的 HEAD>..HEAD -- source/` 做一次：「标签行在谁身上」是不是全都问 `TabRowHost` / `TabRowHostControl`（grep `FActive.HeaderGeomAt`、`Capturer = AWindow`，剩下的每一处要说得出为什么）；角标是不是只有 `BadgeSizeAt` 一处量；候选条件是不是只有 `IsCrossCandidate` 一处；注释与代码不符；try/finally 成对；`FAssumeShown` 只在 `ShownAxisPx` 里置位。审出来的问题修完回到 Step 3。

- [ ] **Step 7: 把实现期的偏差写回 spec 原处**

开工前问题里用户改了的每一条、实现中新发现的每一处 spec 没写准的地方，都在 spec **原处**改并标「实现期修正（E 期）」。至少要落的：

- §3.7：机制最终用的是 ②（开工前问题 1、9 的结论）；删掉「这一段作废」那句条件；Win32 的 `OnMouseDown` / `OnMouseUp`（问题 18）。
- §3.7 / §9.1：禁用窗口能不能拖（问题 2）；当前页例外（问题 3）。
- §8.1：`BadgeDot` 要不要（问题 4）；溢出菜单（问题 5）；提示（问题 6）；把三处「待用户确认」改成结论。
- §9.8：预览文案（问题 7）。
- §15 E 期那一条指向本计划末尾的表；§16 第 9 步标「已完成（E 期）」。

- [ ] **Step 8: 签收记录写进本计划末尾，提交**

签收记录写：全量条数、提交区间、变异抽查结果、spec 写回、遗留；再给发版时用的 CHANGELOG 草稿（只写用户可感知的，一句话一条，按新增 / 修复归组）：
- 新增：工具窗口可以带角标（数字或圆点），侧栏画在图标右上角、底栏画在标签标题后面。
- 新增：侧栏没有窗口时整条隐藏，拖动工具窗口时在那一侧显示放置区域（`HideWhenEmpty`）。
- 修复：当前页被禁用后，底栏的标签、最大化、收起还能用，不会被困在这一页。

```bash
cd /d/Projects/ty-3.1 && git add docs/ && git commit -m "docs(toolwindows): phase E sign-off and corrections written back into the spec

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## E 期做完能看到什么

- `examples/toolwindows`：Search 图标右上角、Problems 标签后面各有一个数字；Output 不是当前页时来了日志，标签后面亮一个圆点，切过去就灭。Diagnostics › Add 45 Problems 点三次变成 `99+`，标签变宽，后面的标签被挤进溢出菜单，菜单里的项带着数字。
- Diagnostics › Disable Output Page：Output 的正文灰了、筛选框和清除按钮不见了，但标签行照常：点 Problems 切过去、最大化、收起都行；Output 的标签灰着，点不回去；再点一次菜单启用，一切恢复。
- Diagnostics › Disable Search Window：Search 图标灰、点不动也拖不动；切到 Search 之后再禁用，点它的图标照样收起 / 展开。
- 把 Outline 拖到左边，右栏整条消失、编辑区变宽；再从左栏拖一个图标，右侧编辑区边缘出现一块「放到右侧栏」，按右栏展开的宽；拖进去高亮，松手右栏出现，窗口成了当前页。
- 设计器里给窗口设 `ShowBadge` / `BadgeValue`，图标和标签上立刻看得到；删光右栏的窗口，设计器里右栏照旧在、写着「添加工具窗口」。

---

## 补充真机验收项（给用户）

D 期的 43 项照旧有效，**第 38 项被下面的 38′ 替换**；新增 44–56。「平台」一列写的是**必须**在哪验；空着的在手头的 Win32 上验一遍就行。验之前主控已经 `lazbuild -B tycontrols.lpk` 并编好了示例。

### 改动的

| # | 验什么 | 平台 | 怎么操作 | 期望 |
|---|---|---|---|---|
| 38′（替换 38） | 禁用当前页 | 各 widgetset | 底栏切到 Output，Diagnostics › Disable Output Page；点 Problems 标签、最大化、还原、收起（再 Ctrl+J 叫回来）、溢出（窗体缩窄到有标签收进去）；再点 Output 标签；最后再点一次菜单启用 | Output 正文灰、操作区（筛选框、清除）看不见，标签行不变淡；别的标签照常切、按钮照常；Output 标签灰、没有悬停、点了不切；启用后操作区回来、Output 标签能点。**不再**有「点什么都没反应、切不走」 |

### 新增的

| # | 验什么 | 平台 | 怎么操作 | 期望 |
|---|---|---|---|---|
| 44 | 禁用非当前页（侧栏） | | 左栏当前页是 Explorer 时，Diagnostics › Disable Search Window；指针停在 Search 图标上、点它、按住拖它；右键它选 Move to Other Side | 图标灰、没有悬停、点了不切、拖不起来；提示照常；右键菜单能把它移过去 |
| 45 | 禁用当前页（侧栏） | | 先切到 Search，再禁用它；点 Search 图标两次；点 Explorer 图标 | 第一次收起、第二次展开；点 Explorer 切过去 |
| 46 | 禁用当前页（底栏）点正文 | Win32、GTK3、Qt、Cocoa | Output 禁用后在它的正文上点几下 | 没有任何反应，程序不崩（Win32 上栏的 `OnMouseDown` 会触发，示例里看不出来，不算问题） |
| 47 | 侧栏角标 | | 看 Search 图标；收起左栏再看；右键 Search 移到右栏再看 | 图标右上角一个数字胶囊，不压住指示条；收起后还在；移到右栏后跟着过去 |
| 48 | 底栏角标、99+、溢出 | | 看 Problems 标签；Diagnostics › Add 45 Problems 点三次；把窗体缩窄 | 标题后面一个胶囊；到 `99+` 时标签变宽、后面的标签右移或被收进溢出；溢出菜单里的项写成 `Terminal (…)` 这样 |
| 49 | Output 圆点 | | 切到 Problems，再做点会写日志的事（拖一个图标、换个主题）；再切回 Output | Output 标签后面亮一个圆点；切回 Output 圆点灭 |
| 50 | 设计期角标 | Lazarus IDE | 在 `umain.lfm` 里选中 OutlineWin，对象查看器改 `ShowBadge`、`BadgeValue`、`BadgeDot` | 设计器里右栏图标立刻出现 / 变化；保存再打开还在 |
| 51 | 一侧空了隐藏 + 放置预览 | | 把 Outline 拖到左栏；再从左栏按住一个图标往右拖，指针进右侧那块、出来、再进去、松手 | 右栏整条消失、编辑区变宽；拖动一开始右侧编辑区边缘就出现一块「放到右侧栏」，宽同右栏原来展开的宽；指针进去高亮、出来恢复；松手右栏出现、窗口成为当前页并展开 |
| 52 | 预览的平台行为 | GTK3（X11 / Wayland）、Qt、Cocoa | 同 51 | 预览出现在编辑区右边缘、盖在编辑区上（不被编辑区或底栏挡住）；拖动不因预览出现而中断；松手或 Esc 后预览消失、不留残影 |
| 53 | 预览中取消 | 各 widgetset | 同 51，拖到一半按 Esc；再试一次拖到一半 Diagnostics › Show a Dialog in 3 s | 预览消失，右栏仍隐藏，窗口没动 |
| 54 | 隐藏的一侧用菜单移过去 | | 右栏隐藏时，右键左栏的一个图标 › Move to Other Side | 右栏出现，窗口过去了 |
| 55 | 布局存取与隐藏 | | 右栏隐藏时 Layout › Save Layout；Layout › Reset Layout；再 Layout › Load Layout；关掉程序重开 | Reset 后右栏回来（Outline 在右边）；Load 后右栏又隐藏；重开是关之前的样子 |
| 56 | 换肤看角标和预览 | | 17 个主题逐个切，亮 / 暗都切，每个主题看一眼角标、拖一次看预览 | 角标数字看得清（高对比度皮肤重点看）；预览底色和边框看得见、文字看得清 |

发现问题照分支标准修（先证实、写守卫、看着变红、变异、全量）；先问「这个 example 不存在，这个行为还算不算错」——是才改 `source/`，只是示例想要点别的就改示例（[[example-content-two-purposes]]）。
