# IDE 工作台 D 期：设计期支持、示例、文档 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（本期约定，优先于子技能的默认做法）**：整期连续实现，**每个任务单独提交**，每个任务只跑它列出的相关 suite；**不在任务之间安排审查环**。整期做完后（Task 10）跑一次全量、做一次整体规格核对和一次代码质量审查。
>
> **谁来做**：标了 **【主控执行】** 的步骤由主控会话做，实现 agent **不做**——编任何 `.lpk`（`tycontrols.lpk`、`tycontrols_dt.lpk`）、编 example、跑 example、真机。理由：`lazbuild <包>.lpk` 改的是机器级包注册表（`%LOCALAPPDATA%\lazarus\packagefiles.xml`），三棵树三个会话共用，编一次就把注册权抢到本树（[[parallel-agent-worktree-hazards]]、[[three-worktree-31-layout]]）。实现 agent 只写源码、跑 `tests/tytests.lpi`（它不 require tycontrols 包，编的是本树的 `source/`，不碰注册表）。

**Goal:** 让工具窗口工作台在 Lazarus 设计器里用得起来（组件面板、组件编辑器、孤儿窗口和 Placement 冲突的提示），交付一个能完整走一遍工作台的示例，写好控件文档和 README；期末给用户一张真机验收表。

**Architecture:** 设计器那一半拆两层。**判定和模型操作**（这个菜单项可不可用、另一侧栏是哪条、孤儿能回到哪些栏、执行移动）放进运行时包的新单元 `tyControls.ToolWindows.DesignRules`，无头测得到；**IDE 那一半**（起名、`Hook.PersistentAdded`、`AddUndoAction`、`Modified`、选中）留在 `designtime/tyControls.Design.CompEditors.pas`，只调判定、不自己判。孤儿提示和冲突提示都**在内容区让出一行**（当前页是窗口化子控件、盖满内容区，不让出来就看不见），所以「重画」= `Realign` + `Invalidate`。示例用 `.lfm` 搭一个类 IDE 窗体，把只有真机才能验的东西都放在能点到的地方。

**Tech Stack:** FPC / Lazarus LCL、IDEIntf（`ComponentEditors`、`PropEdits`）、BGRABitmap、`TTyPainter`、fpcunit、lazres / genicons。

**设计依据：** `docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md`（下称 spec）。本计划覆盖 spec §16 第 7、8 步（含 A / B / C 期往里补的条目）；内容在 §3.2、§6.1、§10.6、§11、§13、§14、§15。spec 里所有「实现期修正（A / B / C 期）」以修正后为准。

**不在本期**：spec §13 的「不做」清单（边缘弹出、徽标、每窗口尺寸、键盘操作图标条……）；manager 的组件编辑器（spec §11 没有）；IDE「File → New」模板（工作台不是一种工程 / 窗体类型，`tyControls.Design.NewItems` 不动）；CHANGELOG（项目惯例：发版时写，[[changelog-user-facing]]；本期不写，Task 10 在签收记录里留一句给发版时用的草稿）。

---

## 开工前要定的问题

下面是 spec 的 D 期内容没写到、与现有代码对不上、或者有不止一种做法的地方。每条都给了建议，**计划正文按建议写**；用户改了哪条，执行时改对应任务，收尾时（Task 10）写回 spec。

### 一、产品方向 / 用户可见行为（要问用户）

> **状态（2026-09-24）**：六条先按建议执行，已告知用户，用户在真机验收时可改。第二类全部按建议采纳。
>
> **执行方式调整**：实现 agent 连续做 Task 1–9，**跳过所有「主控执行」的检查点**（编包、编示例、核对 pot/po），只写源码、跑 tytests；主控在 Task 9 之后一次性编 `tycontrols.lpk`、dt 包和示例，把报错交回修复，再做 Task 10。

1. **组件编辑器的菜单：不适用的项灰掉，还是不显示？**
   spec §11 写「移到另一侧栏（只有侧栏窗口……）」「移回栏里 ▸（只有孤儿）」，没说「只有」是指可见还是可用。
   **建议**：
   - 栏：`新建工具窗口`、`显示 ▸`，两项固定。
   - 窗口：`添加操作区`、`移到另一侧栏`、`移回栏里 ▸`，**三项固定，不适用就灰掉**。位置固定，用户右键时肌肉记忆不乱；底栏窗口上看到灰掉的「移到另一侧栏」，本身就在说「底栏不能跨」。
   - 双击栏 / 窗口 = 生成默认事件处理器（同 `TTyPageControlEditor` 继承 `TDefaultComponentEditor`），**不是**执行第 0 个动词——否则双击栏就多出一个窗口。

2. **设计期孤儿窗口长什么样？**
   窗口构造里 `Align := alClient`，而 `Align` 和 bounds 都不进 .lfm（spec §3.1）。撤销删除后窗口被建到**窗体**上（spec §11 已知限制），它会铺满整个窗体、盖在 Surface 上面。
   **建议**：保持 `alClient` 铺满父控件，顶上一行 `TyToolWindowNote` 提示。理由：孤儿是一个要马上处理掉的错误状态，铺满反而不可能看漏；右键「移回栏里 ▸」一步就回去。另一种做法（孤儿按固定尺寸放左上角）要给窗口加 bounds 的存储规则，而运行时孤儿本来就藏着，不值得。

3. **提示文案**（英文是 msgid，中文进 zh_CN.po；都要在默认宽度的侧栏里放得下，见 Task 3 的判据）：
   - 孤儿窗口：`Not in a tool window bar: hidden at run time` / `不在工具窗口栏里，运行时隐藏`
   - Placement 冲突：`Same Placement as another bar` / `与另一条栏的 Placement 相同`
   - 组件编辑器：`New Tool Window` / `新建工具窗口`，`Show Window` / `显示窗口`，`Add Actions Area` / `添加操作区`，`Move to Other Side Bar` / `移到另一侧栏`，`Move Back into Bar` / `移回栏里`
   **建议**：照上面。

4. **组件面板放哪一页？**
   **建议**：栏和 manager 都进 `TyControls Containers`（跟 `TTyPageControl` / `TTyTabSheet` 放在一起，用的时候总是一起放）；窗口和操作区 `RegisterNoIcon`（spec §2）。

5. **manager 加一个公开方法 `UsableBar(APlacement)`。**
   组件编辑器要找「另一侧那条栏」，manager 的注册表是 protected（`FBars`），外面够不着；示例里「移到另一侧」的右键菜单也要同一个答案。
   **建议**：基类 `TTyCustomToolWindowManager` 上加 public `function UsableBar(APlacement: TTyToolWindowPlacement): TTyToolWindowBar`——此刻这个 Placement 的可用栏（同 Placement 的都不可用，所以最多一条），没有答 nil；现算。写进控件文档。

6. **示例的内容和行为**（spec §16 第 8 步给了骨架，下面是补的）：
   - 目录 `examples/toolwindows/`，工程 `toolwindows_example.lpi`（照控件名，跟文档 `toolwindows.md` 对上）。
   - 布局串存在 `GetAppConfigDir(False)` 下的 `toolwindows.layout`：**FormCreate 读、FormClose 存**（真实应用就这么用，也是 spec §10.5 推荐的读取时机），菜单里另有「保存 / 读取 / 恢复默认布局」三项，方便不重启就验。
   - 密度放在 View 菜单（Classic / Modern 两个单选项）；换肤照规矩在标题栏（`ThemeCombo` + `DarkSwitch`）。
   - 侧栏图标右键：「移到另一侧」（演示 `ContextWindow` + `UsableBar` + `MoveWindow`）；底栏标签右键：「最大化 / 还原」「收起面板」。
   - 窗口操作区里放两个「在自己窗口里调 API」的按钮：Outline 的「移到另一侧」、Explorer 的「恢复默认布局」——spec §9.9 / §10.5 排队那条路只有真机点得出来。
   - 一个 **Diagnostics 菜单**：「3 秒后弹一个模态框」「3 秒后弹一个菜单」「禁用 / 启用当前底栏页」。spec §15 的「拖动中 ShowModal / 弹菜单抢捕获能否取消」「禁用当前页后标签行点击落到哪里」没有这几个开关就没法在真机上做。这是 example 的第二个用途（测试够不到的，[[example-content-two-purposes]]）。
   **建议**：照上面。Diagnostics 菜单如果用户嫌噪音，可以只留在 D 期验收用、验完删掉。

### 二、实现层面的取舍（主控可按建议直接定）

7. **判定放运行时包的新单元 `source/tyControls.ToolWindows.DesignRules.pas`。**
   设计期包不进测试构建（[[designtime-package-not-in-test-build]]），判定写在 `designtime/` 里就一条都测不到。代价是登记 `tycontrols.lpk`（[[new-unit-missing-from-lpk]]，`TReleaseManifestTest` 守着）。IDE 的 `TComponentEditor.IsInInlined` 就是 `csInline in Component.Owner.ComponentState`（`componenteditors.pas:698-701`），不依赖 IDE，可以在运行时单元里照写；组件编辑器**只调**这里的判定，不自己再判一遍（两处判定会漂开）。

8. **孤儿提示和冲突提示都让出内容区的一行。** spec §3.2 / §10.6 只说「画一行提示」。窗口化的当前页盖满栏的内容区、孤儿窗口的正文控件通常 `alClient`，只画不让，一个像素都露不出来——栏上「漏进来的非窗口子控件」那一行（A 期）就是这么修的。所以：
   - 孤儿窗口：设计期 `AdjustClientRect` 顶上让一行（高 = `--toolwindow-header-height`）。
   - 冲突的栏：设计期内容区底部让一行，叠在漏入子控件那一行**上面**，两行互不重叠。
   - 让出一行会改 `AdjustClientRect` 的答案，所以「重画时机」要 `Realign` + `Invalidate`，不能只 `Invalidate`。

9. **冲突提示的重排由 manager 统一发起**：基类加 private `PlacementsChanged`，在 `AddBar`、`RemoveBar` 末尾调，栏的 `SetPlacement` 改完 `FPlacement` 后经 `FManager.PlacementsChanged` 调；`SetManager` / `DetachManager` 里栏自己也重排一次（离开 manager 的那一条已经不在 `FBars` 里了）。只在设计期、非加载 / 释放中做（加载中的冲突由栏的 `Loaded` → `Relayout` 带上）。可用性照旧现算（C 期问题 17）。

10. **设计期孤儿的显示：摘 `csNoDesignVisible` 之后直接 `Visible := True`。**
    spec §3.2 写「去掉 csNoDesignVisible、显示出来」。只摘标志不够：设计期的显示状态是 `Visible or (csDesigning and not csNoDesignVisible)`，触发重算的是写 `Visible`（`control.inc:4612-4625`），而孤儿的 `Visible` 往往已经是 False，写同值是空操作。`Visible` 是 `stored False`，写 True 不进 .lfm。回到栏里以后由 `SwitchCore` 把非当前页的标志加回去（现有行为）。

11. **`StripHint` 改成 `TTranslateString`。**
    spec §3.1 写的是 `string`。LCL 的窗体翻译只认类型**正好是** `TTranslateString` 的属性（`lcltranslator.pas:313`），声明成 `string`，设计器里填的图标条提示永远翻译不了——`TTyRibbon.FileTabCaption` 踩过同一个坑（`Ribbon.pas:170-181`）。示例要翻译提示，这一条先修。赋值兼容，对象查看器里没有差别。

12. **`.pot` 由实现 agent 照格式手写，主控编包时核对。**
    运行时的 `languages/tyControls.StrConsts.pot` 由 `lazbuild tycontrols.lpk` 生成、设计期的 `languages/tyControls.Design.CompEditors.pot` 由 `lazbuild tycontrols_dt.lpk` 生成（包开了 i18n，[[i18n-program]]），实现 agent 不许编包。但 `TI18NTest.TestEveryStrConstsResourcestringIsInThePot` 和 `TestEveryPotHasAChineseCatalogue` 当场就要 pot 里有这些条目。所以：实现 agent 按字母序手写 pot 条目和 zh_CN 条目；主控编包后 `git diff --exit-code languages/`，有出入以生成的为准另提交一次。

13. **面板图标生成脚本实现 agent 可以跑。** `scripts/gen-icons.ps1` 只编 `tools/genicons/genicons.lpi`（`RequiredPackages` 只有 `BGRABitmapPack` + `LCL`，跟 `tests/tytests.lpi` 同一类，不碰 tycontrols 的注册），再用 `lazres` 打包。图标和注册必须在**同一个提交**里：只注册不出图标，`TPaletteIconTest` 红；只出图标不注册，脚本自己的漂移检查和 `TestNoOrphanIconResources` 红。

14. **示例由实现 agent 手写、不编；主控在 Task 7 末尾编、冒烟，把报错交回实现 agent 在同一个任务里修完。** 实现 agent 能做的静态检查：`scripts/check-lfm-props.py`、`scripts/check-example-po.py`、`TEnglishFitTest`、`TSkinFitTest`（这两个扫全部 example 的 .lfm）。

15. ~~**「移到另一侧栏」不记撤销。** spec §11 没要求；`MoveWindow` 设计期那条路（C 期）也没有撤销。控件文档写明「这一步不能 Ctrl+Z，再点一次移回来」。~~
    **实现期修正（D 期收尾，`3e0d81cf`）**：两个移动菜单项都记一条 Parent 的撤销（照 IDE 组件树换父），撤销后窗口回到原栏末尾、成为当前页；见 spec §11。

16. **从面板放下栏时 `ExpandedSize` 可能被改掉——先写测试，红了再修。**
    IDE 放下控件的顺序是：宽 = `Max(5, 构造出来的 Width)` 按设计器 PPI 缩放 → `AutoAdjustLayout(96 → 设计器 PPI)` → `SetBounds(...)` → `Parent :=`（`ide/customformeditor.pp:1453-1506`）。栏的 `SetBounds` 在设计期会把宽写回 `ExpandedSize`（A 期），150% 下两边各自取整差一个像素，就可能写回 239 或 241，对象查看器里 `ExpandedSize` 加粗。无头照这个顺序模拟一遍就知道（Task 5）。

**共享文件**：本计划**不改** `source/tyControls.Base.pas`、`source/tyControls.Painter.pas`。执行中发现非改不可，**停下来先问用户**。

**主题**：不新增类型键和 token。两种新提示用已有的 `TyToolWindowNote`（A 期就为「孤儿、没有窗口、Placement 冲突、多余操作区、非窗口子控件」五种提示定好了）。不碰 `themes/`、两个主题生成器和 golden。

---

## 接口清单（全计划用这一套名字）

**公开的：**

```pascal
{ tyControls.ToolWindows }
TTyToolWindow
  published
    property StripHint: TTranslateString;             { Task 1:由 string 改 }
  public
    { 设计期孤儿提示的那一行(客户区坐标,按自己字体的 PPI);不是设计期孤儿时为空矩形。 }
    function OrphanNoteRect: TRect;                   { Task 2 }

TTyToolWindowBarLayout
    ConflictNote: TRect;                              { Task 3 }

TTyCustomToolWindowManager
  public
    function UsableBar(APlacement: TTyToolWindowPlacement): TTyToolWindowBar;   { Task 4 }

{ tyControls.ToolWindows.DesignRules(新单元,Task 4) }
type
  TTyToolWindowBarArray = array of TTyToolWindowBar;
function TyToolWindowInInlined(AComponent: TComponent): Boolean;
function TyToolWindowDesignCanAddWindow(ABar: TTyToolWindowBar): Boolean;
function TyToolWindowDesignCanAddActions(AWindow: TTyToolWindow): Boolean;
function TyToolWindowDesignOtherSide(AWindow: TTyToolWindow): TTyToolWindowBar;
function TyToolWindowDesignMoveToOtherSide(AWindow: TTyToolWindow): Boolean;
function TyToolWindowDesignReturnTargets(AWindow: TTyToolWindow): TTyToolWindowBarArray;
function TyToolWindowDesignReturnToBar(AWindow: TTyToolWindow; ABar: TTyToolWindowBar): Boolean;

{ tyControls.StrConsts }
rsTyToolWindowOrphan, rsTyToolWindowBarConflict       { Task 2 / Task 3 }

{ designtime/tyControls.Design.CompEditors(Task 6) }
TTyToolWindowBarEditor, TTyToolWindowEditor
rsDtTwNewWindow, rsDtTwShowWindow, rsDtTwAddActions, rsDtTwMoveOtherSide, rsDtTwMoveBack
```

**单元内部的：**

| 在谁身上 | 名字 | 首次出现 |
|---|---|---|
| 窗口 | `OrphanNoteRectIn(const AClient: TRect; APPI: Integer): TRect` | Task 2 |
| 栏 | `PlacementConflicts: Boolean`、`ConflictMayHaveChanged` | Task 3 |
| manager 基类 | `PlacementsChanged` | Task 3 |

类型和方法**跟着第一个读它的任务一起加**，不提前加。

---

## 文件清单

| 文件 | 本期改什么 |
|---|---|
| `source/tyControls.ToolWindows.pas` | `StripHint` 类型；孤儿的显示、提示行、让位；冲突提示行和重排；`UsableBar` |
| `source/tyControls.ToolWindows.DesignRules.pas` | **新建**。组件编辑器的判定和模型操作（Task 4） |
| `source/tyControls.StrConsts.pas` | 两条提示的 resourcestring |
| `tycontrols.lpk` | 登记新单元 |
| `languages/tyControls.StrConsts.pot`、`languages/tycontrols.strconsts.zh_CN.po` | 两条提示 |
| `designtime/tyControls.Design.pas` | 组件面板注册、`RegisterNoIcon`、uses |
| `designtime/tyControls.Design.PropEditors.pas` | 窗口和操作区的 `Controller` 藏起来 |
| `designtime/tyControls.Design.CompEditors.pas` | 两个组件编辑器、5 条 resourcestring、注册 |
| `languages/tyControls.Design.CompEditors.pot`、`languages/tycontrols.design.compeditors.zh_CN.po` | 5 条菜单项 |
| `tools/genicons/genicons.lpr`、`scripts/gen-icons.ps1` | 两个面板图标的画法和类名 |
| `designtime/icons/TTyToolWindowBar*.png`、`TTyToolWindowManager*.png`、`designtime/tycontrols_icons.lrs` | 生成物，跟注册一起提交 |
| `tests/test.toolwindow.design.pas` | **新建**。`TTyToolWindowDesignTests`（无头） |
| `tests/test.toolwindow.window.pas` | `StripHint` 的类型 |
| `tests/test.version.pas`、`tests/test.designeditors.pas` | uses 和 `RegisterClasses` 块补四个类 |
| `tests/tytests.lpr` | uses 加 `test.toolwindow.design` |
| `examples/toolwindows/*` | **新建**。示例（Task 7） |
| `docs/controls/toolwindows.md` | **新建**。控件文档（Task 8） |
| `docs/controls/README.md`、`README.md`、`README.en.md` | 目录、控件清单、示例表（Task 8 / 9） |
| `docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md` | 只在 Task 10 写回 |

**不碰**：`source/tyControls.Base.pas`、`source/tyControls.Painter.pas`、`themes/`、`source/tyControls.ToolWindows.Layout.pas`、`source/tyControls.ToolWindows.LayoutText.pas`、`designtime/tyControls.Design.NewItems.pas`、`CHANGELOG*.md`。

---

## 实现期的地雷（每个任务开工前看一眼）

A 期 12 条、B 期 14 条、C 期 13 条照样有效（CRLF 上的变异先 `git diff --stat`、变异后 `lazbuild -B`、「谁先读就是谁的」、哨兵底色、`AssertSame` 已释放指针会假绿、`FreeNotification` 双向、fixup 倒序、`Loaded` 顺序 = 读入顺序……）。D 期另加：

1. **设计期包不进测试构建**（[[designtime-package-not-in-test-build]]）。`designtime/` 里的代码测试全绿**一个字都不能证明**它编得过。`TPropertyEditor` 有零参数的 `GetPropInfo` 成员，会遮蔽 `TypInfo.GetPropInfo`——设计期编辑器里的 RTTI 调用一律写全 `TypInfo.`。编 dt 包是**主控**的事（检查点 B）。
2. **设计器守卫是解析文件的**：`test.designregistry` 解析 `designtime/` 下每个 `.pas` 的 `RegisterComponents` / `RegisterNoIcon` / `RegisterPropertyEditor`，`test.paletteicons`、`test.version`、`test.designeditors` 都从它取总体。**面板分组必须留在 `tyControls.Design.pas`**（`gen-icons.ps1` 和 `test.paletteicons` 只认那里）。
3. **`test.version` 要在 `RegisterClasses` 块里认得每一个被注册的类名**：注册了新类而没补，`TestEveryRegisteredNameResolves` 当场红——这是它的本职，不是误报。
4. **`TTranslateString` 在 `Classes` 里**（FPC RTL，`type string`），不用另加 uses。
5. **`csNoDesignVisible` 先改、`Visible` 后写**（`ShowWindowNow` 的注释）；孤儿那一支同样。
6. **设计期提示让出的行改的是 `AdjustClientRect`**：只 `Invalidate` 的话，对齐引擎不重排，当前页照样盖着提示。所有「提示出现 / 消失」的时机都要 `Realign`。
7. **`csLoading` 期间的 `AddBar`（fixup 里 `SetManager`）不许重排**，更不许抛异常（fixup 里抛异常中止整个窗体加载，spec §10.6）。
8. **`OwnerFormDesignerModifiedProc` 是可换的全局钩子**（`LCLProc`）：测试里换成计数器就能数「设计器被通知了几次」（照 `test.tabset.pas:115-140` 的写法，测完还原）。
9. **组件编辑器里的菜单项**：子菜单项的 `OnClick` 是编辑器对象的方法；点击时**重新算一遍**候选（按 `MenuIndex` 取），不在 `PrepareItem` 里存指针——菜单开着的这段时间里窗口可能被删了（照 `TTyPageControlEditor.ShowPageMenuItemClick`）。
10. **example 的 .lfm 只改 .lfm、不改 .pas 时，lazbuild 不重编**（[[examples-must-be-lfm-titlebar-skin]] 里的 Lazarus 坑）：主控编 example 前 `rm -rf examples/toolwindows/lib`；改了 `source/` 之后编 example 一律 `-B`（[[example-stale-lib-on-source-change]]）。
11. **.lfm 里流进来的 `Checked` / `ItemIndex` 会在流式加载时触发 `OnChange`**，而那时兄弟控件可能还没读进来（AV）。初始选中一律放 FormCreate（[[examples-must-be-lfm-titlebar-skin]] 的「gotchas」）。
12. **窗体上的字段名不许叫 `MenuBar` / `Controller`**：跟 `TTyForm` 的 published 属性撞名，编不过（[[i18n-program]]）。
13. **新单元写出来是 LF**：仓库 `core.autocrlf = true`，检出后是 CRLF。变异用的搜索串先确认命中（[[crlf-mutation-phantom-survivor]]）。

---

## 跑测试的固定套路

改了 `source/` 之后**必须** `lazbuild -B`。exe 用唯一名 `tytests-31.exe`（别的会话也在跑 `tytests.exe`，[[parallel-agent-worktree-hazards]]；禁用 `taskkill -im`）。

跑一组 suite（把 `SUITES` 换成任务里列的名字）：

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi > /tmp/build.txt 2>&1 || { tail -30 /tmp/build.txt; false; } && cd tests && cp tytests.exe tytests-31.exe && for s in SUITES; do ./tytests-31.exe --suite=$s --format=plain > /tmp/t-$s.txt 2>&1; printf '%s: ' $s; grep -E "Number of (run tests|errors|failures)" /tmp/t-$s.txt | tr '\n' ' '; echo; done
```

**判据是每个 suite 那一行都有 `Number of run tests`、errors / failures 为 0**，不是 exit code。某一行为空 = 跑丢了（或 suite 名写错），重跑，别读成通过。

全量（只在 Task 0 和 Task 10；输出必须重定向到文件，[[known-rare-suite-flake]]）：

```bash
cd /d/Projects/ty-3.1/tests && ./tytests-31.exe --all --format=plain > /tmp/all.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/all.txt
```

**工具窗口全部 suite**（C 期签收时的 18 个 + 本期的 1 个）：`TTyToolWindowGeometryTests TTyToolWindowThemeTests TTyToolWindowTests TTyToolWindowStreamingTests TTyToolWindowActionsTests TTyToolWindowBarTests TTyToolWindowImagesTests TTyToolWindowFocusTests TTyToolWindowStripTests TTyToolWindowEdgeTests TTyToolWindowReorderTests TTyToolWindowBottomTests TTyToolWindowBottomInputTests TTyToolWindowManagerTests TTyToolWindowManagerLiveTests TTyToolWindowCrossDragTests TTyToolWindowLayoutTextTests TTyToolWindowLayoutApplyTests`，本期起再加 `TTyToolWindowDesignTests`（Task 2 起）。

**设计期与发布守卫**（下文写「守卫 suite」指这一串）：`TPaletteIconTest TVersionTest TDesignEditorsTest TI18NTest TReleaseManifestTest TEnglishFitTest TSkinFitTest`。

## 关于判据和变异

纯查询（`OrphanNoteRect`、`BarLayout.ConflictNote`、`UsableBar`、`DesignRules` 的每个函数）给输入 / 期望表，测试照表写。**涉及重画时机、设计器通知、像素的，只写判据和「在哪个变异下必须红」**，测试代码执行时按判据现写，写完**先做变异确认它真的在守**（[[tests-written-with-the-fix-are-green-and-wrong]]、[[plan-tests-write-the-mutation-not-the-code]]）。

变异三拍：改一行 → `git diff --stat` 确认改到了 → `lazbuild -B` → 跑 → **必须红** → 改回 → 重编重跑 → 绿。一条变异没红：先查是不是改错了地方；确实没红，说明那条测试没守住，**当场补强再继续**，并在该任务的提交信息里写一句。

探针只能是**真实状态的只读视图**。「重画了没有」用栏探针（`TBarAccess`）已有的 `Invalidate` 重写计数；「设计器被通知了没有」用 `OwnerFormDesignerModifiedProc` 计数（地雷 8）。

**设计期夹具**：新 suite 从 `TTyToolWindowManagerFixture`（`tests/test.toolwindow.manager.pas`）派生，设计期的栏和窗口照 C 期 `TestDesignTimeCanMoveIgnoresTheEvent` 那一套（`FDesignOwner`、`NewDesignBar`、`NewWindowIn(bar, FDesignOwner)`）——Owner 带 csDesigning、构造时传下来，走的是设计器放下控件的真实路径。继承窗体里的窗口（csAncestor）和 frame 实例（Owner 带 csInline）用测试里的小子类调 protected 的 `SetAncestor` / `SetInline` 造。

---

### Task 0: 基线

**Files:** 无改动。

- [ ] **Step 1: 确认起点**

```bash
cd /d/Projects/ty-3.1 && git status --short && git branch --show-current && git log --oneline -1
```

Expected：工作区干净，分支 `feat/3.1`，HEAD 是本计划的提交或其后。

- [ ] **Step 2: 编译并跑工具窗口全部 suite + 守卫 suite + 全量，记下条数**

每个 suite 的 `Number of run tests` 和全量总数记进草稿，Task 10 签收时一起写进本计划末尾。C 期签收是 7666 条 0 / 0。**有红就停**：D 期不在红的基线上开工。

- [ ] **Step 3: 【主控执行】两个包的基线**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tycontrols.lpk > /tmp/pkg.txt 2>&1; tail -3 /tmp/pkg.txt; lazbuild -B tycontrols_dt.lpk > /tmp/dt.txt 2>&1; tail -3 /tmp/dt.txt; git status --short languages/
```

Expected：两个包都编过；`languages/` 没有变化（有变化说明 C 期的 pot 就没跟上，先单独提交生成物再开工）。报错路径里出现别的树（`ty-controls`、`ty-advchart`、`.claude/worktrees/…`）= 注册权被抢，重编一次。

- [ ] **Step 4: 先查几件事，结论记进草稿（后面的任务要用）**

1. `designtime/tyControls.Design.PropEditors.pas` 的 `RegisterPropertyEditors` 里藏属性的那一段（`THiddenPropertyEditor`，约 730-835 行）按什么顺序排、uses 里要加哪几个单元。Task 5 用。
2. `tests/test.version.pas` 底部 `RegisterClasses` 块的写法。Task 5 用。
3. `docs/controls/glyphbuttons.md` §3：只显示图标的按钮怎么接 Lucide（`IconFont` = `TTyLucideIconFont`、`GlyphName`、`ShowCaption := False`），以及 `TTyLucideImageList` 在 .lfm 里怎么写 `Names`（`examples/icons/umain.lfm:324-334` 是 `TTyVirtualImageList + IconFont` 的写法，`TTyLucideImageList` 要不要 `IconFont` 查源码）。Task 7 用。
4. 示例要用的 Lucide 名字都在（已查：`files search list-tree arrow-left-right rotate-ccw trash-2 plus x ellipsis panel-bottom terminal circle-alert` 都有）。

---

### Task 1: `StripHint` 能被窗体翻译（开工前问题 11）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.window.pas`

- [ ] **Step 1: 写测试（判据，`TTyToolWindowTests`）**

| 判据 | 在哪个变异下必须红 |
|---|---|
| `GetPropInfo(TTyToolWindow, 'StripHint')^.PropType = TypeInfo(TTranslateString)` | 改回 `string` |
| 设计期流式往返（照 `TTyToolWindowStreamingTests` 的 `WriteComponent` / `ReadComponent`）：`StripHint = '资源管理器'` 读回来一字不差 | —（守住改类型不改行为） |

- [ ] **Step 2: 跑，确认第一条红**

- [ ] **Step 3: 实现**

字段、setter、属性三处的 `string` 换成 `TTranslateString`；属性上方的注释补一句：

```pascal
    { 图标条提示;空的时候用 Caption,**不用 Hint**(见 TTyToolWindowBar.StripHintText)。
      类型是 TTranslateString 不是 string:LCL 的窗体翻译只认类型正好是它的属性
      (lcltranslator.pas:313),设计器里填的提示才进得了 .po(同 TTyRibbon.FileTabCaption)。 }
    property StripHint: TTranslateString read FStripHint write SetStripHint;
```

- [ ] **Step 4: 跑** `TTyToolWindowTests TTyToolWindowStreamingTests TTyToolWindowStripTests`，全绿；变异。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.window.pas && git commit -m "fix(toolwindows): StripHint is a TTranslateString so a form's .po can translate it

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 设计期孤儿窗口（spec §3.2）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `source/tyControls.StrConsts.pas`
- Modify: `languages/tyControls.StrConsts.pot`、`languages/tycontrols.strconsts.zh_CN.po`
- Create: `tests/test.toolwindow.design.pas`
- Modify: `tests/tytests.lpr`

孤儿 = Parent 不是栏。运行时照旧藏着（A 期已做）；设计期要看得见，顶上一行 `TyToolWindowNote` 提示，正文从提示下面开始（开工前问题 2、8、10）。

- [ ] **Step 1: 新测试单元**

`tests/test.toolwindow.design.pas`：`TTyToolWindowDesignTests = class(TTyToolWindowManagerFixture)`，uses 抄 `test.toolwindow.manager` 那一串再加 `test.toolwindow.manager`。挂进 `tests/tytests.lpr` 的 uses（`test.toolwindow.layoutapply,` 后面，用编辑工具改，别用 sed）。

- [ ] **Step 2: 写测试（判据）**

「挪出去」一律用：设计期栏（`NewDesignBar`）里两个窗口，把**当前页**挪到窗体上一个设计期 `TTyPanel`（Owner = `FDesignOwner`）上——当前页原来显示着，非当前页原来藏着，两种都要测。

| 判据 | 在哪个变异下必须红 |
|---|---|
| 设计期，**非当前页**挪出去：`csNoDesignVisible` 不在 `ControlStyle`、`IsControlVisible` 为真 | 删掉 `SetParent` 里设计期那一支 |
| 同上，只摘标志、不写 `Visible`：`IsControlVisible` 照样得为真（这条专门守「Visible 原来是 False」） | 那一支只摘标志不写 `Visible` |
| 设计期孤儿的 `OrphanNoteRect` 非空，高 = `--toolwindow-header-height` 按字体 PPI（默认主题 26），宽 = 客户区宽 | `OrphanNoteRectIn` 不看设计期 / 高取错 token |
| `LayOut` 之后（夹具的对齐帮手）：`BodyRect.Top = OrphanNoteRect.Bottom`；孤儿里的 alClient 正文控件 `Top` 也等于它 | `AdjustClientRect` 不让出这一行 |
| 孤儿里的操作区（`EnsureActions`）排在提示行下面：`Actions.Top >= OrphanNoteRect.Bottom` | `CustomAlignPosition` 的孤儿分支按客户区原点摆（不走 `BodyRect`） |
| 哨兵底色 `RenderTo`（[[headless-render-needs-sentinel-ground]]，照 A 期 Task 3 用控制器 `StyleOverride` 把背景刷成哨兵色）：提示行里有非哨兵的墨迹像素，提示行以下的正文区（不放子控件）一个都没有 | `RenderTo` 不画提示 |
| **运行时**同样挪出去：`Visible = False`、`OrphanNoteRect` 为空、`BodyRect.Top = 0` | 去掉 `csDesigning` 判断（运行时也显示 / 也让位） |
| 设计期孤儿再 `Parent :=` 回原来的栏：它成为当前页、`OrphanNoteRect` 为空、`HeaderMode = twhSide`；栏里其余每个窗口都带 `csNoDesignVisible` | —（守现有 `SwitchCore` 行为；变异：`RegisterWindow` 里设计期不切页） |
| 设计期 `Parent := nil`：不抛异常 | — |
| 设计期孤儿流式往返（Owner = 设计期根，孤儿的 Parent 是根上的面板）：文本里**没有** `Visible = True` | `Visible` 改成 stored |

- [ ] **Step 3: 跑，确认红**

- [ ] **Step 4: 实现**

`SetParent` 末尾那一支（现在是「运行时的孤儿保持隐藏」）换成：

```pascal
  if NewParent is TTyToolWindowBar then
    TTyToolWindowBar(NewParent).RegisterWindow(Self)
  else if not (csDestroying in ComponentState) then
  begin
    if csDesigning in ComponentState then
    begin
      { 设计期的孤儿(spec §3.2):撤销删除、粘贴等途径落到栏外的窗口要看得见,才能右键
        「移回栏里」。先摘 csNoDesignVisible 再写 Visible(同 ShowWindowNow 的顺序)——
        只摘标志不够:设计期的显示状态是 `Visible or (csDesigning and not csNoDesignVisible)`,
        触发重算的是写 Visible,而孤儿的 Visible 往往已经是 False,写同值是空操作。
        Visible 是 stored False,这一句不进 .lfm。回到栏里由栏的切页把标志加回去。 }
      ControlStyle := ControlStyle - [csNoDesignVisible];
      Visible := True;
    end
    else
      { 运行时的孤儿保持隐藏:没有栏替它守「一次只显示一页」。 }
      Visible := False;
  end;
```

（`Visible := True` 在 `Bar = nil` 时经 `SetVisible` 直接放行，见 `TTyToolWindow.SetVisible` 开头。）

窗口加：

```pascal
    { 设计期孤儿的提示行(spec §3.2),AClient 坐标:顶上一行,高 = --toolwindow-header-height
      (跟栏的提示行、标题行是同一个「一行字加上下留白」的尺寸),钳在客户区里。不是设计期、
      在栏里时为空矩形。AdjustClientRect 让位、RenderTo 画提示、OrphanNoteRect 答探针,
      问的都是这一处。 }
    function OrphanNoteRectIn(const AClient: TRect; APPI: Integer): TRect;
  public
    function OrphanNoteRect: TRect;   { = OrphanNoteRectIn(客户区, Font.PixelsPerInch) }
```

`AdjustClientRect`：继承、标题行之后，`n := OrphanNoteRectIn(ARect, Font.PixelsPerInch); if n.Bottom > ARect.Top then ARect.Top := n.Bottom;`。

`RenderTo`：`EndPaint` 之前，提示行非空就按 `TyToolWindowNote` 的静止态样式（`TyStyleClassFor(Self, StyleClass)`）画 `rsTyToolWindowOrphan`：左右各缩一个 `--toolwindow-header-pad`，`taLeftJustify`、`tlCenter`、放不下出省略号——写法照栏画 `rsTyToolWindowBarStray` 那一段（`TTyToolWindowBar.RenderTo` 末尾）。

`SetParent` 里那句「设计期那一半（显示 + 提示）归 D 期」的注释改成现在的事实。

`source/tyControls.StrConsts.pas`，放在 `rsTyToolWindowBarStray` 后面：

```pascal
  { Drawn at design time along the top of a TTyToolWindow whose parent is not a tool window
    bar: undo of a delete re-creates it on the form, a paste can drop it anywhere. It stays
    hidden at run time. Right-click it -> "Move Back into Bar" puts it back. }
  rsTyToolWindowOrphan =
    'Not in a tool window bar: hidden at run time';
```

pot（按 key 字母序，插在 `rstytoolwindowmore` 和 `rstytoolwindowrestore` 之间）和 zh_CN.po（同一位置）：

```
#: tycontrols.strconsts.rstytoolwindoworphan
msgid "Not in a tool window bar: hidden at run time"
msgstr "不在工具窗口栏里，运行时隐藏"
```

（pot 里 `msgstr ""`。）

- [ ] **Step 5: 跑** `TTyToolWindowDesignTests TTyToolWindowTests TTyToolWindowActionsTests TTyToolWindowStreamingTests TI18NTest`，全绿；变异逐条。

- [ ] **Step 6: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas source/tyControls.StrConsts.pas languages/tyControls.StrConsts.pot languages/tycontrols.strconsts.zh_CN.po tests/test.toolwindow.design.pas tests/tytests.lpr && git commit -m "feat(toolwindows): a tool window outside a bar shows itself and a note at design time

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Placement 冲突提示和重画时机（spec §10.6、§16 第 7 步）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `source/tyControls.StrConsts.pas`
- Modify: `languages/tyControls.StrConsts.pot`、`languages/tycontrols.strconsts.zh_CN.po`
- Modify: `tests/test.toolwindow.design.pas`

同一个 manager 下 Placement 相同的每一条栏都不可用（C 期），设计期要在它们身上画一行提示。可用性现算、不缓存——没有缓存可失效，所以要保证**每一处改变 Placement 集合的地方都让这个 manager 下所有栏重排、重画**（开工前问题 8、9）。

- [ ] **Step 1: 写测试（判据，`TTyToolWindowDesignTests`）**

「重画」用 `TBarAccess` 的 `Invalidate` 计数；「重排」的结果用 `BarLayout.Content` 和夹具 `LayOut` 之后当前页的 `BoundsRect` 看。

| 判据 | 在哪个变异下必须红 |
|---|---|
| 设计期，同一 manager 下两条左栏：两条的 `BarLayout.ConflictNote` 都非空，高 = header-height token；`Content.Bottom = ConflictNote.Top` | `LayoutAt` 不看冲突 |
| 同上，`LayOut` 之后当前页的 `BoundsRect.Bottom <= ConflictNote.Top`（当前页不盖提示） | 只画不让（`Content` 不扣） |
| **运行时**同样两条左栏：`ConflictNote` 为空 | 去掉 `csDesigning` 判断 |
| 设计期两条左栏、**没有** manager（或各自一个 manager）：都为空 | 按同父兄弟的 Placement 判，而不是按 manager |
| 冲突 + 漏进来一个非窗口子控件（照 A 期漏入测试的造法）：两行都在、冲突行在上、`ConflictNote.Bottom = StrayNote.Top` | 两行共用一个矩形 / 次序反了 |
| 哨兵底色 `RenderTo`：冲突行里有墨迹像素 | `RenderTo` 不画冲突提示 |
| A、B 两条左栏冲突；`B.Placement := twpRight`：A 的 `Invalidate` 计数至少 +1，A 的 `ConflictNote` 为空 | `SetPlacement` 不调 `PlacementsChanged` |
| A、B 冲突；`B.Manager := nil`：A 重画且提示没了；B 自己也重画且提示没了 | `RemoveBar` 不调 `PlacementsChanged` / `SetManager` 不重排自己 |
| A 左、B 右不冲突；再加一条左栏 C 指向同一 manager：A 的计数 +1、A 有提示 | `AddBar` 不调 `PlacementsChanged` |
| A、B 冲突；释放 B：A 重画、提示没了 | 释放那条路（manager 的 `Notification` → `RemoveBar`）没走到 `PlacementsChanged` |
| A、B 冲突；释放 manager：A、B 都重画、提示没了 | `DetachManager` 不重排 |
| 加载中（`TBarAccess.BeginLoad`，照 C 期 Task 1 的流式判据）把两条同 Placement 的栏指向同一 manager：不抛异常，两条的 `Invalidate` 计数不因 `AddBar` 增加 | 去掉 `ConflictMayHaveChanged` 的 `csLoading` 守卫 |
| 文案放得下：默认主题、96 PPI、`ExpandedSize = 240` 的设计期左栏，`TyMeasureTextBlock` 与 `TyMeasureRenderedTextWidth` 量 `rsTyToolWindowBarConflict` 取大 ≤ `ConflictNote` 宽 − 2 × header-pad | 文案改长（这条守的是开工前问题 3 的文案） |

- [ ] **Step 2: 跑，确认红**

- [ ] **Step 3: 实现**

`TTyToolWindowBarLayout` 加（放在 `StrayNote` 后面）：

```pascal
    { 设计期 Placement 冲突(spec §10.6):同一 manager 下另有一条栏 Placement 相同。内容区底部
      再让出一行,叠在 StrayNote 上面 —— 当前页是窗口化子控件、盖满内容区,不让出来提示一个
      像素都露不出来。 }
    ConflictNote: TRect;
```

栏加 private：

```pascal
    { 同一 manager 下另有一条栏 Placement 相同(manager 现算,C 期)。manager 正在释放时不算。 }
    function PlacementConflicts: Boolean;
    { 冲突提示可能出现 / 消失了:它占内容区的一行,所以要重排再重画。只在设计期、不在加载 /
      释放中做 —— 加载中的由 Loaded → Relayout 带上;运行时没有这行提示。 }
    procedure ConflictMayHaveChanged;
```

`PlacementConflicts` = `(FManager <> nil) and not (csDestroying in FManager.ComponentState) and not FManager.IsBarUsable(Self)`（本栏在 manager 上时 `IsBarUsable` 为假只有冲突一种原因）。

`ConflictMayHaveChanged`：`if [csDesigning, csLoading, csDestroying] * ComponentState <> [csDesigning] then Exit; Realign; Invalidate;`

`LayoutAt`：在 StrayNote 那一段之后、`EmptyNote` 之前：

```pascal
  if (csDesigning in ComponentState) and PlacementConflicts then
  begin
    bandH := TokenPxAt(TyToolWindowHeaderHeightVar, TyToolWindowHeaderHeightDef, APPI);
    if bandH > Result.Content.Bottom - Result.Content.Top then
      bandH := Result.Content.Bottom - Result.Content.Top;
    Result.ConflictNote := Rect(Result.Content.Left, Result.Content.Bottom - bandH,
      Result.Content.Right, Result.Content.Bottom);
    Dec(Result.Content.Bottom, bandH);
  end;
```

`RenderTo`：设计期提示那一段的条件和画法加上 `L.ConflictNote`，文字 `rsTyToolWindowBarConflict`、左对齐、省略号（同 `StrayNote`）。

manager 基类加 private：

```pascal
    { 注册栏的 Placement 集合变了(加进 / 摘掉一条栏、某条栏改了 Placement):每条栏的冲突提示
      都可能出现或消失(spec §10.6)。可用性现算,这里只让它们按新答案重排、重画。 }
    procedure PlacementsChanged;
```

实现：对 `FBars` 里每一条调 `ConflictMayHaveChanged`（它自己过滤设计期 / 加载 / 释放）。调用点：

- `AddBar` 末尾；`RemoveBar` 末尾（manager 的 `Notification` 释放那条路经它）。
- 栏的 `SetPlacement`：`FPlacement := AValue` 之后 `if FManager <> nil then FManager.PlacementsChanged;`（本栏自己在 `FBars` 里，一起重排；原有的 `Realign; Invalidate` 保留）。
- 栏的 `SetManager` 末尾、`DetachManager` 末尾：`ConflictMayHaveChanged`（离开的这一条已经不在任何 manager 的表里）。

`IsBarUsable` 声明处那句「设计期冲突提示的重画归 D 期」改成现在的事实。

`source/tyControls.StrConsts.pas`，放在 `rsTyToolWindowBarStray` 后面：

```pascal
  { Drawn at design time in a line reserved at the bottom of a bar's content area when
    another bar on the same TTyToolWindowManager has the same Placement. Every such bar is
    left out of cross-bar drags, MoveWindow and layout strings; reordering inside it still
    works. Short on purpose: a side bar is 240px wide by default. }
  rsTyToolWindowBarConflict =
    'Same Placement as another bar';
```

pot / zh_CN.po（按字母序插在 `rstytoolwindowbarempty` 前面）：

```
#: tycontrols.strconsts.rstytoolwindowbarconflict
msgid "Same Placement as another bar"
msgstr "与另一条栏的 Placement 相同"
```

- [ ] **Step 4: 跑** `TTyToolWindowDesignTests TTyToolWindowManagerTests TTyToolWindowBarTests TTyToolWindowStreamingTests TI18NTest`，全绿；变异逐条。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas source/tyControls.StrConsts.pas languages/tyControls.StrConsts.pot languages/tycontrols.strconsts.zh_CN.po tests/test.toolwindow.design.pas && git commit -m "feat(toolwindows): bars sharing a placement on one manager say so at design time

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 组件编辑器的判定（新单元 `DesignRules`，`UsableBar`）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Create: `source/tyControls.ToolWindows.DesignRules.pas`
- Modify: `tycontrols.lpk`
- Modify: `tests/test.toolwindow.design.pas`

spec §11 的每个菜单项「可不可用」「目标是谁」「做什么」都在这里一处答，组件编辑器（Task 6）只调它（开工前问题 5、7）。

- [ ] **Step 1: `UsableBar`**

基类 `TTyCustomToolWindowManager` public，放在 `IsBarUsable` 后面：

```pascal
    { 此刻 Placement 为 APlacement 的可用栏(spec §10.6:同 Placement 的都不可用,所以最多一条);
      没有答 nil。现算。组件编辑器的「移到另一侧栏」、应用自己的「移到另一侧」菜单都问它。 }
    function UsableBar(APlacement: TTyToolWindowPlacement): TTyToolWindowBar;
```

实现：扫 `FBars`，Placement 相同且不在 csDestroying 的计数；正好一条就答它，否则 nil。

- [ ] **Step 2: 新单元**

```pascal
unit tyControls.ToolWindows.DesignRules;
{$mode objfpc}{$H+}

{ 设计器里工具窗口的组件编辑器(designtime/tyControls.Design.CompEditors)的判定和模型那一半
  (spec §11)。放在运行时包里:设计期包不进测试构建,判定写在那边就一条都测不到。组件编辑器
  只做 IDE 那一半 —— 起名、Hook.PersistentAdded、AddUndoAction、Modified、选中 —— 不自己再判。 }

interface

uses
  Classes, Controls,
  tyControls.ToolWindows, tyControls.ToolWindows.Manager;

type
  TTyToolWindowBarArray = array of TTyToolWindowBar;

{ AComponent 在 frame 实例里 —— IDE 的 TComponentEditor.IsInInlined 就是这一句
  (componenteditors.pas:698-701)。往 frame 实例里加组件不行(:178-183),继承来的控件也不能换父
  (customformeditor.pp:1667-1669)。 }
function TyToolWindowInInlined(AComponent: TComponent): Boolean;

{ 「新建工具窗口」:栏在、不在 frame 实例里、不在加载 / 释放中。子孙窗体里往继承来的栏加窗口
  可以(spec §11)。 }
function TyToolWindowDesignCanAddWindow(ABar: TTyToolWindowBar): Boolean;

{ 「添加操作区」:窗口还没有操作区(Actions = nil)、不在 frame 实例里。继承来的窗口可以加。 }
function TyToolWindowDesignCanAddActions(AWindow: TTyToolWindow): Boolean;

{ 「移到另一侧栏」的目标:窗口在侧栏里、不是继承来的(csAncestor)、不在 frame 实例里,所在栏
  有 manager,manager 下另一侧(左 ↔ 右)有可用栏(UsableBar),且 CanMoveWindow 答 True
  (它管本栏冲突、同一窗体、加载 / 释放中);否则 nil。 }
function TyToolWindowDesignOtherSide(AWindow: TTyToolWindow): TTyToolWindowBar;

{ 执行「移到另一侧栏」:目标为 nil、manager 不是 TTyToolWindowManager 答 False;否则
  MoveWindow(设计期同步、不问 OnCanMoveWindow、不发事件、自己通知设计器,spec §9.9)。
  Bar.Manager 是基类类型,这里转型(spec §2)。 }
function TyToolWindowDesignMoveToOtherSide(AWindow: TTyToolWindow): Boolean;

{ 「移回栏里 ▸」的候选:只有孤儿(Parent 不是栏)才有;窗口不是继承来的、不在 frame 实例里、
  有 Owner;候选 = AWindow.Owner 拥有的每一条栏(按 Owner.Components 顺序),去掉在 frame
  实例里的、在加载 / 释放中的。侧栏、底栏都算:孤儿没有「原来那一类」。 }
function TyToolWindowDesignReturnTargets(AWindow: TTyToolWindow): TTyToolWindowBarArray;

{ 执行「移回栏里」:ABar 必须在候选里,否则答 False、什么都不改。Parent := ABar —— 设计期
  直接改 Parent 不走 CommitCrossMove(BooksDirectMove 排除设计期),注册即成为当前页。
  设计器由调用方通知(Modified)。 }
function TyToolWindowDesignReturnToBar(AWindow: TTyToolWindow; ABar: TTyToolWindowBar): Boolean;

implementation

end.
```

实现照注释写。`csAncestor` 看 `AWindow.ComponentState`；「另一侧」：`twpLeft` ↔ `twpRight`，底栏窗口直接 nil。

`tycontrols.lpk` 照 `tyControls.ToolWindows.Manager` 那一条加 `<Item>`（`Filename` + `UnitName`），Files 的 `Count` 加一（先看这个 .lpk 用的是 `Count` 属性还是逐项，照现有写法）。

- [ ] **Step 3: 写测试（判据，`TTyToolWindowDesignTests`）**

设计期夹具：`FDesignOwner` 上左栏 L（Explorer、Search，当前页 Search）、右栏 R（Outline）、底栏 B（Output），都指向 manager M。`TAncestorWindow`（调 `SetAncestor(True)`）、`TInlineOwner`（`SetInline(True)`）是测试单元里的小子类。

| 判据 | 在哪个变异下必须红 |
|---|---|
| `M.UsableBar(twpLeft) = L`、`(twpRight) = R`、`(twpBottom) = B` | 恒答 nil |
| 再加一条左栏 L2：`UsableBar(twpLeft) = nil`，`(twpRight)` 仍是 R；释放 L2 后又是 L | 取第一条 / 最后一条 |
| `OtherSide(Explorer) = R`；`OtherSide(Outline) = L` | 左右写反 |
| `OtherSide(Output) = nil`（底栏） | 不查底栏 |
| 加 L2 冲突之后：`OtherSide(Explorer) = nil`（本栏不可用）、`OtherSide(Outline) = nil`（左侧没有可用栏） | 只看目标不看源 / 反过来 |
| 栏 L 没有 manager：`OtherSide(Explorer) = nil` | 没判 `Manager = nil`（AV 也算红） |
| 继承来的窗口（`TAncestorWindow` 放进 L）：`OtherSide = nil`，但 `CanAddActions = True` | 去掉 `csAncestor` 判断 / 把它也加到 `CanAddActions` 上 |
| frame 实例：`TInlineOwner` 拥有的栏 → `CanAddWindow = False`；它拥有的窗口 → `CanAddActions = False`、`OtherSide = nil` | 去掉 `TyToolWindowInInlined` |
| `CanAddActions`：没有操作区时 True，`EnsureActions` 之后 False | 恒 True |
| `MoveToOtherSide(Explorer)`：答 True，`Explorer.Bar = R`、`R.ActiveWindow = Explorer`、`R.Collapsed` 不变（设计期不写 Collapsed）、L 回落到 Search；事件串（夹具的 `FLog`，挂上 `OnWindowMoved` 和三条栏的事件）为空；`OwnerFormDesignerModifiedProc` 计数 ≥ 1（地雷 8，测完还原） | 绕过 `MoveWindow` 直接改 Parent（计数会是 0 或事件串不空，二者之一要红；**如果两条都绿，把这个变异记成等价、写进提交信息**，由真机验收表第 8 条兜底） |
| `MoveToOtherSide(Output)`：答 False，什么都没变 | 不先问 `OtherSide` |
| `ReturnTargets`：在栏里的窗口 → 空；Explorer 挪到一个面板上变孤儿 → `[L, R, B]`（按 `Components` 顺序）；孤儿是继承来的 → 空；另有一条栏由 `TInlineOwner` 拥有 → 不在候选里 | 不判孤儿 / 不判 csAncestor / 不排除 frame 实例 |
| `ReturnToBar(孤儿, R)`：答 True，`Parent = R`、`R.ActiveWindow = 孤儿`、`OrphanNoteRect` 为空 | —（守 Task 2 的回流；变异：答 True 但不设 Parent） |
| `ReturnToBar(孤儿, 不在候选里的栏)`、`ReturnToBar(非孤儿, R)`：答 False、什么都不变 | 不查候选 |

- [ ] **Step 4: 跑** `TTyToolWindowDesignTests TTyToolWindowManagerTests TReleaseManifestTest`，全绿；变异逐条。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas source/tyControls.ToolWindows.DesignRules.pas tycontrols.lpk tests/test.toolwindow.design.pas && git commit -m "feat(toolwindows): design-time verb rules live in the runtime package; manager.UsableBar

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: 【主控执行】检查点 A：运行时包和 pot**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tycontrols.lpk > /tmp/pkg.txt 2>&1; tail -3 /tmp/pkg.txt; git diff --stat languages/
```

Expected：包编过（新单元在包里，[[new-unit-missing-from-lpk]]）；`languages/` 没有差别。有差别 = Task 2 / 3 手写的 pot 跟生成的不一致：以生成的为准，`git add languages/ && git commit -m "chore(i18n): regenerate the runtime .pot"`（带 Co-Authored-By 行）。

---

### Task 5: 设计期包——组件面板、面板图标、藏起 `Controller`

**Files:**
- Modify: `designtime/tyControls.Design.pas`
- Modify: `designtime/tyControls.Design.PropEditors.pas`
- Modify: `tools/genicons/genicons.lpr`、`scripts/gen-icons.ps1`
- Create（生成）: `designtime/icons/TTyToolWindowBar.png`、`_150`、`_200`，`TTyToolWindowManager.png`、`_150`、`_200`
- Modify（生成）: `designtime/tycontrols_icons.lrs`
- Modify: `tests/test.version.pas`、`tests/test.designeditors.pas`、`tests/test.toolwindow.design.pas`

- [ ] **Step 1: 放下栏的尺寸（开工前问题 16）——先测**

`TTyToolWindowDesignTests` 里照 IDE 放下控件的顺序模拟两遍（`ide/customformeditor.pp:1453-1506`）：

1. 96 PPI：`b := TTyToolWindowBar.Create(FDesignOwner)`；`w := Max(5, b.Width); h := Max(5, b.Height)`；`b.SetBounds(10, 10, w, h)`；`b.Parent := <设计期面板>`。
2. 144 PPI：同上，但 `w := MulDiv(Max(5, b.Width), 144, 96)`、`h` 同理，`SetBounds` 之前先 `b.AutoAdjustLayout(lapAutoAdjustForDPI, 96, 144, 0, 0)`。

| 判据 | 在哪个变异下必须红 |
|---|---|
| 两遍之后 `b.ExpandedSize = 240`，`IsStoredProp(b, 'ExpandedSize')` 为 False（对象查看器里不加粗） | 见下 |

跑。**绿了**：这一步只留测试，变异是「`SetBounds` 写回时不扣图标条」（必须红）。**红了**：修 `TTyToolWindowBar.SetBounds`——设计期写回时，换算出来的 `v` 按此刻 PPI 再缩放回去，跟 `FExpandedSize` 缩放的结果只差取整误差（`Abs(MulDiv(v, PPI, 96) - MulDiv(FExpandedSize, PPI, 96)) <= 1`）就不写回；变异是「去掉这个容差」（必须红）。注释写清楚这一条是从 IDE 放下控件的顺序来的。

- [ ] **Step 2: 注册**

`designtime/tyControls.Design.pas`：

- uses 在 `tyControls.AdvanceChart,` 后面加 `tyControls.ToolWindows, tyControls.ToolWindows.Manager,`（manager 的注册要 uses 它的单元，spec §16 第 7 步）。
- `TyControls Containers` 那一组末尾加 `TTyToolWindowBar, TTyToolWindowManager`（开工前问题 4）。
- 在 `RegisterNoIcon([TTyGridCell]);` 后面：

```pascal
  { 工具窗口和它的操作区由栏的组件编辑器建(「新建工具窗口」「添加操作区」),不从面板拖 ——
    注册了才能流式化、选中、撤销删除(撤销走的是粘贴那条路,要按类名找得到),但没有面板按钮。 }
  RegisterNoIcon([TTyToolWindow, TTyToolWindowActions]);
```

`designtime/tyControls.Design.PropEditors.pas`（照 Task 0 Step 4 第 1 条查到的位置和写法）：

```pascal
  { 工具窗口和操作区的 Controller 由栏 / 窗口推送、不进 .lfm(spec §3.1 / §4):对象查看器里
    改了也会被下一次推送盖掉,不给看。 }
  RegisterPropertyEditor(TypeInfo(TTyStyleController), TTyToolWindow, 'Controller', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TTyStyleController), TTyToolWindowActions, 'Controller', THiddenPropertyEditor);
```

uses 加 `tyControls.ToolWindows`。

- [ ] **Step 3: 面板图标**

`tools/genicons/genicons.lpr`：照邻近的 `GSplitter` / `GTabControl` 在 24 单位空间里加两个画法（线条墨色 `#3C3C3C`、强调色 `#3B82F6`，[[palette-icons-and-sizes]]）：

- `GToolWindowBar`：一个窗框，左边一条竖的图标条（里面三个小方块、最上面那个用强调色），条右边是一块内容区。
- `GToolWindowManager`：两条竖栏（左右各一），中间一个双向箭头。

`Glyphs` 数组上界加 2，加 `(Name:'TTyToolWindowBar'; Draw:@GToolWindowBar)`、`(Name:'TTyToolWindowManager'; Draw:@GToolWindowManager)`；`scripts/gen-icons.ps1` 的 `$classes` 在 `# Phase 5 containers & layout` 那一组末尾加 `'TTyToolWindowBar','TTyToolWindowManager'`。然后：

```powershell
powershell -File scripts/gen-icons.ps1
```

Expected：`OK: 168 registered components all have icons`（166 + 2），`Packed … icon resources` 条数 = 类数 × 3。报错路径里出现别的树就停下交主控（开工前问题 13）。打开生成的 `designtime/icons/TTyToolWindowBar_200.png` 看一眼（Read 工具能看图）。

- [ ] **Step 4: 守卫跟上**

- `tests/test.version.pas`：uses 加 `tyControls.ToolWindows, tyControls.ToolWindows.Manager`，底部 `RegisterClasses` 块加四个类（地雷 3）。
- `tests/test.designeditors.pas`：uses 加 `tyControls.ToolWindows`（`GetClass('TTyToolWindow')` 要解析得到）。

- [ ] **Step 5: 跑** `TTyToolWindowDesignTests` + 守卫 suite，全绿。判据：

| 判据 | 在哪个变异下必须红 |
|---|---|
| `TPaletteIconTest` 三条都绿（面板类都有三档图标；`RegisterNoIcon` 的两个类没有图标；没有孤儿图标） | 注释掉 `$classes` 里的一个再重跑脚本 |
| `TVersionTest` 绿：四个类名都解析得到、都报 `TyVersion` | 从 `RegisterClasses` 块里删一个 |
| `TDesignEditorsTest.TestEveryRegistrationTargetsARealProperty` 绿：两条 `Controller` 注册都落在真实的 published 属性上 | 属性名写成 `'Controler'` |

- [ ] **Step 6: 提交**

```bash
cd /d/Projects/ty-3.1 && git add designtime/tyControls.Design.pas designtime/tyControls.Design.PropEditors.pas tools/genicons/genicons.lpr scripts/gen-icons.ps1 designtime/icons/TTyToolWindowBar*.png designtime/icons/TTyToolWindowManager*.png designtime/tycontrols_icons.lrs tests/test.version.pas tests/test.designeditors.pas tests/test.toolwindow.design.pas source/tyControls.ToolWindows.pas && git commit -m "feat(toolwindows): the bar and the manager are on the palette; Controller hidden from the inspector

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

（Step 1 没改源码的话 `source/tyControls.ToolWindows.pas` 不在暂存区，`git add` 一个没变的文件无害。）

---

### Task 6: 组件编辑器（spec §11）

**Files:**
- Modify: `designtime/tyControls.Design.CompEditors.pas`
- Modify: `languages/tyControls.Design.CompEditors.pot`、`languages/tycontrols.design.compeditors.zh_CN.po`

设计期包测不到（地雷 1），判定全在 Task 4 测过；这里只写 IDE 那一半，**不许**在编辑器里另判可用性。

- [ ] **Step 1: resourcestring**

在 `rsDtTreeEditNodes` 后面：

```pascal
  { Tool window bars and tool windows (spec §11). Whether each verb applies is decided in the
    runtime unit tyControls.ToolWindows.DesignRules, where it can be tested. }
  rsDtTwNewWindow     = 'New Tool Window';
  rsDtTwShowWindow    = 'Show Window';
  rsDtTwAddActions    = 'Add Actions Area';
  rsDtTwMoveOtherSide = 'Move to Other Side Bar';
  rsDtTwMoveBack      = 'Move Back into Bar';
```

pot 和 zh_CN.po 各加 5 条（key 形如 `tycontrols.design.compeditors.rsdttwnewwindow`；中文照开工前问题 3）。

- [ ] **Step 2: 两个编辑器**

interface 段（uses 加 `ComponentEditors` 里已有、再加 `tyControls.ToolWindows, tyControls.ToolWindows.DesignRules`）：

```pascal
  { 工具窗口栏的右键菜单(spec §11):「新建工具窗口」「显示 ▸」。双击 = 生成默认事件处理器
    (TDefaultComponentEditor,同 TTyPageControlEditor),不是执行第 0 个动词。
    不提供「删除工具窗口」:Hook.DeletePersistent 跳过继承组件检查、Owner 检查和撤销记录
    (designer.pp:3144-3179),子孙窗体里能删掉继承来的窗口。用 Delete 键删。 }
  TTyToolWindowBarEditor = class(TDefaultComponentEditor)
  private
    function Bar: TTyToolWindowBar;
    procedure ShowWindowItemClick(Sender: TObject);
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
    procedure PrepareItem(Index: Integer; const AnItem: TMenuItem); override;
  end;

  { 工具窗口的右键菜单(spec §11):「添加操作区」「移到另一侧栏」「移回栏里 ▸」,三项固定,
    不适用的灰掉。可用性和目标都问 tyControls.ToolWindows.DesignRules。 }
  TTyToolWindowEditor = class(TDefaultComponentEditor)
  private
    function Win: TTyToolWindow;
    procedure MoveBackItemClick(Sender: TObject);
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
    procedure PrepareItem(Index: Integer; const AnItem: TMenuItem); override;
  end;
```

栏编辑器：

- `GetVerbCount = 2`；0 = `rsDtTwNewWindow`，1 = `rsDtTwShowWindow`。
- `PrepareItem`：0 → `AnItem.Enabled := TyToolWindowDesignCanAddWindow(Bar)`；1 → `Enabled := Bar.WindowCount > 0`，子菜单每个窗口一项（`Name := 'TyTwShow' + IntToStr(i)`，`Caption := W.Name + ' "' + W.Caption + '"'`，`OnClick := @ShowWindowItemClick`），照 `TTyPageControlEditor.PrepareItem`。
- `ShowWindowItemClick`：按 `MenuIndex` 取 `Bar.Windows[i]`（越界就返回），`Bar.ActiveWindow := W`（设计期只激活；切页第 6 步自己通知设计器、刷新对象查看器），`GetDesigner.SelectOnlyThisComponent(W)`。
- `ExecuteVerb(0)`（spec §11 的顺序，照抄不省步）：

```pascal
    0: begin
         if not TyToolWindowDesignCanAddWindow(Bar) then Exit;
         Hook := nil;
         if not GetHook(Hook) then Exit;
         W := TTyToolWindow.Create(Bar.Owner);
         W.Parent := Bar;       { 注册即成为当前页(不在加载中);设计期切页通知设计器 }
         W.Name := GetDesigner.CreateUniqueComponentName(W.ClassName);
         W.Caption := W.Name;
         Hook.PersistentAdded(W, True);
         { 照抄 PageControl 的「添加页」不记撤销,Ctrl+Z 删不掉加出来的窗口;面板拖放记撤销的
           就是这一句(designer.pp:788)。 }
         GetDesigner.AddUndoAction(W, uopAdd, True, 'Name', '', W.Name);
         Modified;
       end;
```

窗口编辑器：

- `GetVerbCount = 3`；0 = `rsDtTwAddActions`，1 = `rsDtTwMoveOtherSide`，2 = `rsDtTwMoveBack`。
- `PrepareItem`：0 → `TyToolWindowDesignCanAddActions(Win)`；1 → `TyToolWindowDesignOtherSide(Win) <> nil`；2 → 候选非空，子菜单每条栏一项（`Caption := B.Name`，`OnClick := @MoveBackItemClick`）。
- `ExecuteVerb(0)`：判定不过就返回；`A := Win.EnsureActions`；`A.Name := GetDesigner.CreateUniqueComponentName(A.ClassName)`；`Hook.PersistentAdded(A, True)`；`GetDesigner.AddUndoAction(A, uopAdd, True, 'Name', '', A.Name)`；`Modified`。
- `ExecuteVerb(1)`：`if TyToolWindowDesignMoveToOtherSide(Win) then GetDesigner.SelectOnlyThisComponent(Win);`——**不再调 `Modified`**（`MoveWindow` 设计期自己通知，spec §11 C 期修正）。
- `MoveBackItemClick`：重新取候选（地雷 9），按 `MenuIndex` 取栏；`if TyToolWindowDesignReturnToBar(Win, B) then begin Modified; GetDesigner.SelectOnlyThisComponent(Win); end;`。

`RegisterComponentEditors` 里：

```pascal
  // Tool window bars: New Tool Window / Show Window; tool windows: Add Actions Area / Move to
  // Other Side Bar / Move Back into Bar (spec §11). Double-click still makes the default event.
  RegisterComponentEditor(TTyToolWindowBar, TTyToolWindowBarEditor);
  RegisterComponentEditor(TTyToolWindow, TTyToolWindowEditor);
```

- [ ] **Step 3: 跑** `TI18NTest TDesignEditorsTest TVersionTest TTyToolWindowDesignTests`，全绿（设计期代码本身编不进测试，这里只守 pot / po 和注册解析）。

- [ ] **Step 4: 提交**

```bash
cd /d/Projects/ty-3.1 && git add designtime/tyControls.Design.CompEditors.pas languages/tyControls.Design.CompEditors.pot languages/tycontrols.design.compeditors.zh_CN.po && git commit -m "feat(toolwindows): component editors for bars and tool windows

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: 【主控执行】检查点 B：设计期包**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tycontrols.lpk > /tmp/pkg.txt 2>&1; tail -3 /tmp/pkg.txt; lazbuild -B tycontrols_dt.lpk > /tmp/dt.txt 2>&1; grep -iE "error|fatal" /tmp/dt.txt | head -20; tail -3 /tmp/dt.txt; git diff --stat languages/
```

Expected：两个包都编过；`languages/` 没有差别。编译错误交回实现 agent 在 Task 5 / 6 里修（修完另起提交，信息写 `fix(toolwindows): design-time package builds`）；pot 有出入以生成的为准另提交。

---

### Task 7: 示例 `examples/toolwindows`（spec §16 第 8 步）

**Files:**
- Create: `examples/toolwindows/toolwindows_example.lpi`、`toolwindows_example.lpr`、`toolwindows_example.ico`
- Create: `examples/toolwindows/umain.pas`、`umain.lfm`
- Create: `examples/toolwindows/languages/toolwindows_example.zh_CN.po`、`languages/tycontrols.zh_CN.po`

**规矩**（[[examples-must-be-lfm-titlebar-skin]]、[[example-content-two-purposes]]、[[demo-edits-lfm-not-code]]、[[no-native-controls-in-ui]]）：

- 窗体和全部控件在 `.lfm` 里，`.pas` 只放事件处理；**设置写进 .lfm**，只有「必须是代码」的（填 `ThemeCombo`、初始选中、读写布局文件、日志）在代码里。
- 真的 `TTyTitleBar`（`TitleBar = Bar`，标题有字），标题栏右侧 `ThemeCombo` + `DarkSwitch`，运行时换肤。
- 自绘 UI 里不用裸 LCL 控件（`TMainMenu` / `TMenuItem` / `TTimer` 是非可视的模型对象，经 `TTyMenuBar` 画出来，有先例 `examples/menu`）。
- 内容只放两类：**教用法**（从 .lfm / 代码里怎么够到它）和**测试够不到的**（真机手势、拖放、布局存取、换肤换密度、各种取消）。不追求成员覆盖率。

- [ ] **Step 1: 工程骨架**

照 `examples/splitter` 抄：`.lpi`（改工程名和单元；保留 `Scaled`、`UseXPManifest` + `DpiAware`、`Icon Value="0"`、`GraphicApplication`、i18n 块、`RequiredPackages` LCL + tycontrols）、`.lpr`（`LangDir`、`SetDefaultLang`、`TranslateUnitResourceStringsEx(... 'tycontrols', 'tyControls.StrConsts')`、`RequireDerivedFormResource := True`）、`.ico`（直接复制 `splitter_example.ico`：`scripts/gen-appicon.ps1` 往每个 example 装的是同一个应用图标）。

- [ ] **Step 2: 窗体（.lfm 的组件树）**

```
MainForm: TMainForm                     Caption 'Tool windows example'; TitleBar = Bar; MenuBar = MainMenuBar
│                                       OnCreate / OnClose; Width 1100, Height 720, poScreenCenter
├─ Surface: TTyFormSurface              alClient
│  ├─ Bar: TTyTitleBar                  alTop, Top 0; Caption 'Tool windows  · TyControls'
│  │   ├─ DarkSwitch: TTyToggleSwitch   akTop+akRight
│  │   └─ ThemeCombo: TTyComboBox       akTop+akRight
│  ├─ MainMenuBar: TTyMenuBar           alTop, Top 34; Menu = MainMenu1
│  ├─ LeftBar: TTyToolWindowBar         Placement twpLeft(默认,不写); Left 0; Manager = ToolMgr; PopupMenu = StripMenu; ShowHint True
│  │   ├─ ExplorerWin: TTyToolWindow    Caption 'Explorer'; ImageName 'files'; StripHint 'Explorer (files)'
│  │   │   ├─ ExplorerActions: TTyToolWindowActions
│  │   │   │   └─ BtnResetLayout        只显示图标 'rotate-ccw';Hint 'Reset layout';OnClick → ToolMgr.ResetLayout
│  │   │   └─ ExplorerTree: TTyTreeView alClient;Items 在 .lfm 里(几个文件夹 / 文件)
│  │   └─ SearchWin: TTyToolWindow      Caption 'Search'; ImageName 'search'
│  │       ├─ SearchEdit: TTyEdit       alTop
│  │       └─ SearchList: TTyListBox    alClient
│  ├─ RightBar: TTyToolWindowBar        Placement twpRight; Align alRight; Manager = ToolMgr; PopupMenu = StripMenu; ShowHint True
│  │   └─ OutlineWin: TTyToolWindow     Caption 'Outline'; ImageName 'list-tree'
│  │       ├─ OutlineActions: TTyToolWindowActions
│  │       │   └─ BtnOutlineMove        只显示图标 'arrow-left-right';Hint 'Move to the other side';OnClick → MoveWindow 到 UsableBar(另一侧)
│  │       └─ OutlineList: TTyListBox   alClient
│  └─ EditorHost: TTyPanel              alClient(编辑区和底栏一起放进来,底栏就只在编辑区下面,spec §2)
│      ├─ BottomBar: TTyToolWindowBar   Placement twpBottom; Align alBottom; ExpandedSize 200; Manager = ToolMgr; PopupMenu = PanelMenu
│      │   ├─ ProblemsWin: TTyToolWindow Caption 'Problems'   ← 没有操作区:切页时看标签行高度不跳
│      │   │   └─ ProblemsList: TTyListBox alClient
│      │   ├─ OutputWin: TTyToolWindow   Caption 'Output'
│      │   │   ├─ OutputActions: TTyToolWindowActions
│      │   │   │   ├─ OutputFilter: TTyEdit     宽 140;TextHint 'Filter'
│      │   │   │   └─ BtnOutputClear            只显示图标 'trash-2';Hint 'Clear'
│      │   │   └─ OutputMemo: TTyMemo   alClient;ReadOnly;事件日志写在这里
│      │   └─ TerminalWin: TTyToolWindow Caption 'Terminal'
│      │       ├─ TerminalActions: TTyToolWindowActions
│      │       │   ├─ BtnTermNew / BtnTermClose / BtnTermMore   'plus' / 'x' / 'ellipsis'
│      │       └─ TerminalMemo: TTyMemo alClient
│      └─ EditorMemo: TTyMemo           alClient;一段示例源码
├─ ToolMgr: TTyToolWindowManager        Images = Icons;OnWindowMoved / OnLayoutApplied
├─ Icons: TTyLucideImageList            Names = files, search, list-tree(写法照 Task 0 Step 4 第 3 条)
├─ LucideFont: TTyLucideIconFont        给操作区里只显示图标的按钮用
├─ MainMenu1: TMainMenu
│   ├─ File:    Exit
│   ├─ View:    Bottom Panel(Ctrl+J,勾选项);-;Density ▸ Classic / Modern(单选)
│   ├─ Layout:  Save Layout / Load Layout / Reset Layout
│   └─ Diagnostics: Show a Dialog in 3 s / Pop Up a Menu in 3 s / Disable Output Page(勾选项)
├─ StripMenu: TTyPopupMenu              Move to Other Side
├─ PanelMenu: TTyPopupMenu              Maximize / Restore;Hide Panel
└─ DiagTimer: TTimer                    Enabled False;Interval 3000
```

要点：

- 同向对齐的兄弟**显式写 Top / Left**（`Bar` Top 0、`MainMenuBar` Top 34；`LeftBar` Left 0；[[lcl-code-created-align-order]]）。
- 窗口的 `Left / Top / Width / Height / Visible / TabOrder` 是 `stored False`，**不写**；栏沿轴那一边（侧栏 `Width`、底栏 `Height`）也不写。`ActiveIndex` 按需写（Explorer 那条写 0 或不写；底栏写 1 让 Output 当前页——日志一启动就看得见）。
- 窗口里没有 Name 的话布局串不认它（spec §10.2）——.lfm 里每个窗口本来就有 Name。
- 操作区里的按钮用 `docs/controls/glyphbuttons.md` 里只显示图标的写法（`IconFont = LucideFont`、`GlyphName`、`ShowCaption = False`），`Hint` 写上、`ShowHint` 打开。
- 初始选中（`ThemeCombo.ItemIndex`、Density 单选、Bottom Panel 勾选）放 FormCreate（地雷 11）。
- 字段名不许叫 `MenuBar` / `Controller`（地雷 12）。

- [ ] **Step 3: 代码（`umain.pas`，只放处理器）**

| 处理器 | 做什么 | 教什么 / 验什么 |
|---|---|---|
| `FormCreate` | 填 `ThemeCombo`（`TyBuiltinThemeNames`，选 `default`）；Density / Bottom Panel 的初始勾选；布局文件存在就 `ToolMgr.LoadLayoutFromString(读出来的文本)`；日志一行 `Ready` | spec §10.5 推荐在 FormCreate 读；启动时当前页收不到 `OnShow`（日志里看得出来） |
| `FormClose` | `ToolMgr.SaveLayoutToString` 写进文件（目录不存在先 `ForceDirectories`） | 真实应用的用法 |
| `ThemeComboChange` / `DarkSwitchChange` | 照 `examples/splitter` | 换肤 |
| Density 两项 | `TyDefaultController.Density := tdClassic / tdModern` | 换密度：图标条宽、标题行高、内容区下限跟着变 |
| View › Bottom Panel | `BottomBar.Collapsed := not BottomBar.Collapsed` | spec §5.3：底栏收起后界面上没有入口，由应用给开关 |
| `BottomBar.OnCollapse / OnExpand` | 同步那一项的勾选；写日志 | 标签行的收起按钮也会改它 |
| Layout 三项 | `SaveLayoutToString` 存文件 / 读文件 `LoadLayoutFromString` / `ResetLayout`；答 False 写日志 | 保存 / 读取 / 恢复 |
| `StripMenu.OnPopup` | `b := StripMenu.PopupComponent as TTyToolWindowBar; w := b.ContextWindow`；目标 = `ToolMgr.UsableBar(另一侧)`；`w = nil` 或 `not ToolMgr.CanMoveWindow(w, 目标)` 时那一项灰掉 | `ContextWindow`、`UsableBar`、`CanMoveWindow` |
| Move to Other Side | `ToolMgr.MoveWindow(w, 目标)` | `MoveWindow`；右键不在图标上时栏不弹菜单（冒泡到窗体） |
| `BtnOutlineMove` | 同上，窗口是 `OutlineWin` 自己；调完马上记一行日志：`MoveWindow` 的返回值和此刻 `OutlineWin.Bar.Name` | spec §9.9：按钮在要移动的窗口里——窗体显示着，移动排队执行。日志先出「返回 True、还在旧栏」，排队的移动执行后才出 `moved` |
| `BtnResetLayout` | `ToolMgr.ResetLayout` | spec §10.5 / §14：「恢复布局」按钮在某个窗口的操作区里 |
| `PanelMenu` 两项 | `BottomBar.Maximized := not BottomBar.Maximized`（`OnPopup` 里按状态改标题）；`BottomBar.Collapsed := True` | 标签右键经 `HeaderContextPopup` 走到栏的 `PopupMenu` |
| `BtnOutputClear` / `OutputFilter.OnChange` | 清日志 / 按关键字筛（日志行存一份 `TStringList`，筛出来重填 `OutputMemo`） | 操作区里是真控件 |
| `BtnTermNew / Close / More` | 往 `TerminalMemo` 写一行说明（不假装真的终端） | 三个按钮只为了占满操作区：底栏各页操作区宽度不同，标签行共用一个行高 |
| `ToolMgr.OnWindowMoved` | 日志 `moved <窗口> from <栏> (#<旧序号>)` | 事件语义：手势、`MoveWindow`、`WindowIndex` 发；读布局不发 |
| `ToolMgr.OnLayoutApplied` | 日志 `layout applied` | |
| 三条栏的 `OnChange` | 日志 `<栏>: active = <窗口>` | 启动时不发（spec §5.1） |
| Diagnostics › Show a Dialog in 3 s / Pop Up a Menu in 3 s | 记下要做哪一件，`DiagTimer.Enabled := True`；到点 `TyMessageDlg(...)` 或 `PanelMenu.PopUp(Mouse.CursorPos)` | spec §15：拖动中 `ShowModal` / 弹菜单抢走捕获能否取消——点完菜单去拖一个图标，别松手 |
| Diagnostics › Disable Output Page | `OutputWin.Enabled := not OutputWin.Enabled` | spec §3.6 / §15：禁用当前页后标签行点击落到哪里（文档写的是「别这么做」，这里专门给真机看后果） |

日志统一走一个 `Log(const S: string)`：加进日志表、按筛选框刷新 `OutputMemo`。所有日志格式是 resourcestring（能翻译，[[i18n-program]]：代码里的字面量永远翻译不了）。

- [ ] **Step 4: i18n**

- `languages/tycontrols.zh_CN.po`：**整份复制** `languages/tycontrols.strconsts.zh_CN.po`（此刻已含 Task 2 / 3 的两条）。
- `languages/toolwindows_example.zh_CN.po`：照 `examples/splitter/languages/splitter_example.zh_CN.po` 的头；.lfm 里每个 `Caption` / `Hint` / `StripHint` / `TextHint`（key = `tmainform.<组件名小写>.<属性小写>`，窗体自己是 `tmainform.caption`）和 `umain.pas` 每条 resourcestring（key = `umain.<名字小写>`）各一条，带 `%` 的加 `#, object-pascal-format`。工具窗口的 `Caption` 翻译了不影响布局——布局串按 `Name` 认窗口。

- [ ] **Step 5: 静态检查（实现 agent 做）**

```bash
cd /d/Projects/ty-3.1 && python scripts/check-lfm-props.py . ; python scripts/check-example-po.py .
```

（两个脚本的参数照各自文件头的 Usage 核一遍。）再跑 `TEnglishFitTest TSkinFitTest TI18NTest`，全绿。`TEnglishFitTest` 红 = 某个英文标题在手写的宽度里放不下：放宽或开 `AutoSize`，别改短文案凑数。

- [ ] **Step 6: 提交**

```bash
cd /d/Projects/ty-3.1 && git add examples/toolwindows && git commit -m "feat(examples): toolwindows — an IDE-style workbench with side bars, a bottom panel and saved layouts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: 【主控执行】检查点 C：编、冒烟、po 核对**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tycontrols.lpk > /tmp/pkg.txt 2>&1; tail -2 /tmp/pkg.txt \
 && rm -rf examples/toolwindows/lib && lazbuild -B examples/toolwindows/toolwindows_example.lpi > /tmp/ex.txt 2>&1; grep -iE "error|fatal" /tmp/ex.txt | head; tail -2 /tmp/ex.txt
```

然后：

1. `powershell -File scripts/smoke-launch-examples.ps1`（至少 toolwindows 这一个要起得来、有可见窗口；超时就是模态错误框挡在 `CreateForm` 里，多半是 .lfm 的属性名或空 po 条目）。
2. `python scripts/example-rsj2po.py examples/toolwindows toolwindows_example <一个只含 {} 的 json>`：它对 .po 里**缺**的 resourcestring 报 ERROR——报了就是 Step 4 漏写，交回实现 agent 补。
3. 编译错误、流式错误都交回实现 agent，**在本任务里**修完（另起提交 `fix(examples): toolwindows builds and streams`）。
4. 主控自己开一次：启动不崩、左右侧栏和底栏都在、日志第一行是 `Ready`、换一个主题不崩。**只到这里**——完整的走查留给用户的真机验收（本计划末尾的表）。

---

### Task 8: 控件文档 `docs/controls/toolwindows.md`

**Files:**
- Create: `docs/controls/toolwindows.md`
- Modify: `docs/controls/README.md`

中文，只有这一份（`docs/controls/` 没有英文版，照惯例）。**原生语感、短句、能列表就不写段落**，不写「为什么这么设计」的小作文（[[doc-writing-native-tone]]）；有意的偏离只一句话讲清楚。结构照 `docs/controls/pagecontrol.md`：

- [ ] **Step 1: 按下面的提纲写**

1. **概述**：四个类一张表（类 / 作用 / 设计器里）；**摆法**两句话 + 一小段 .lfm 骨架：栏是普通的 Align 控件，底栏横跨整个窗口还是只在编辑区下面由布局决定——编辑区和底栏一起放进一个 alClient 容器就只在编辑区下面（spec §2）。
2. **typeKey 与 token**：spec §12 的类型键表（用途一句话）、颜色 token 表、长度 token 列表；皮肤调 token 就行，不用写基础规则。
3. **属性与方法**：四个类各一张表（只列 published 和常用 public；`StripHint` 写明是 `TTranslateString`；manager 的 `UsableBar` 写进去）。
4. **事件**：spec §6.6 的表（发 / 不发），加一句 `MoveWindow` 的发送顺序。
5. **跨侧拖动与 `MoveWindow`**：能拖什么（侧 ↔ 侧，底栏只在栏内）；`OnCanMoveWindow` 否决；排队规则一段。
6. **布局保存**：三个方法一张表；**在 FormCreate 里读**；一段布局串示例；版本漂移四条（缺窗口、新窗口留在设计时那一侧、改名当新窗口、另一类栏下的名字算未放置）；不保存的东西（最大化、窗口里的内容）。
7. **设计器里使用**：从面板放下栏和 manager、改 `Placement`；两个组件编辑器的菜单项（各一句）；设计期点图标 / 标签切页；孤儿窗口和「移回栏里」；Placement 冲突的提示；**粘贴要先选中栏**（侧栏点图标条，底栏点标签行空白处或边缘区）；「移到另一侧栏」不能 Ctrl+Z；在对象查看器组件树里选中一个非当前页的窗口不会自动切过去，用「显示 ▸」或点图标。
8. **流式化**：一段 .lfm 示例；窗口的 bounds、`Visible`、`Controller` 不进流；窗口顺序就是 `Controls` 顺序。
9. **注意事项**（下面每一条一两句，逐条对上 spec 原处）：
   - `Controller` 由栏推给窗口、窗口推给操作区，代码直接赋给窗口会被下一次推送盖掉（§3.1）。
   - 图标条提示跟随栏的 `ShowHint`，标签提示跟随窗口的 `ShowHint`；提示用 `StripHint`，不用 `Hint`（§3.6、§8）。
   - 要禁用页面，禁用正文里的控件，不要禁用 `TTyToolWindow` 本身（§3.6）。
   - 操作区上 `AutoSize` / `ChildSizing` / `BorderSpacing` 无效（§4）。
   - 启动时显示出来的当前页收不到 `OnShow`，首次填充放 FormCreate（§5.1）。
   - `OnExit` 里不要把焦点设回被藏起的窗口里的控件（§5.1）。
   - 底栏收起后界面上没有入口，应用自己给开关（§5.3，示例的 View › Bottom Panel）。
   - 事件处理器里不许释放栏、窗口或 manager，用 `Application.ReleaseComponent`（§6.6）。
   - 只设了 `ImageIndex` 的窗口要跨侧，得用 manager 上的共享列表；只在 manager 上设列表时，对象查看器里 `ImageIndex` 的下拉是空的，请设 `ImageName`（§8）。
   - `Esc` 取消拖动只吃掉 KeyDown，KeyUp 仍会到焦点控件（§9.7）。
   - 排队时 `MoveWindow` 返回之后 `W.Bar` 还是旧栏（§9.9）。
   - 排队的布局会覆盖排着期间的同步改动和已经排着的移动（§10.5）。
   - 跨栏移动（`MoveWindow`、拖放、读布局 / 恢复默认）会重建窗口里所有句柄，IME 组字、光标、原生子窗口的状态不保留（§10.4）。
   - 改了名的窗口当成新窗口（§10.3）；翻译 `Caption` 不影响布局（按 `Name` 认）。
   - `Bar.Manager` 是基类类型，调 `MoveWindow` / 布局方法要转型成 `TTyToolWindowManager`，或者直接引用窗体上的 manager（§2）。
   - 继承窗体上读用户布局要在 FormCreate 里调（§10.5 的限制）。
   - 同一个 manager 下 Placement 相同的栏都不可用：不参与跨栏拖动、`MoveWindow`、布局保存，栏内调顺序照常（§10.6）。
   - 不支持：manager 放在数据模块里、栏分布在多个窗体上（§10.6）。
   - 删掉一个工具窗口或操作区后撤销 / 重做，它会被建到**窗体**上：窗口显示为孤儿，右键「移回栏里 ▸」；操作区用 IDE 的「改变父控件」放回窗口（§11）。
10. **和 VS Code / JetBrains 的差异**（§13，列表，每条一句）。
11. **示例**：指向 `examples/toolwindows`，一句话说里面能试什么。

- [ ] **Step 2: 目录**

`docs/controls/README.md` 的「容器与布局」表里，`TTyTabSet` 那一行后面加：

```markdown
| [TTyToolWindowBar](toolwindows.md) | IDE 式侧栏 / 底栏：图标条或标签切换工具窗口，可拉宽、收起 |
| [TTyToolWindowManager](toolwindows.md) | 工具窗口跨侧拖动、`MoveWindow`、布局保存 |
```

- [ ] **Step 3: 自查**

`grep -c "——" docs/controls/toolwindows.md`（多了就改短句）；文中每个成员名在 `source/` 里 grep 得到（`TTranslateString`、`UsableBar`、`OrphanNoteRect` 之类别写错）；链接都能打开。

- [ ] **Step 4: 提交**

```bash
cd /d/Projects/ty-3.1 && git add docs/controls/toolwindows.md docs/controls/README.md && git commit -m "docs(toolwindows): control reference

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: README（中英）

**Files:**
- Modify: `README.md`、`README.en.md`

- [ ] **Step 1: 先查数字的口径**

README 的控件数现在自己就对不上：正文写「163 个控件」，各分组标题上的数加起来是 164，`designtime/tyControls.Design.pas` 里 `RegisterComponents` 的类是 166 个（本期再加 2 个 = 168）。先用 `test.designregistry` 的同一口径（`RegisterComponents` 里的类，不含 `RegisterNoIcon`）数一遍，再把「特性」那一行、「控件清单」开头那一行、各分组标题的数统一成这个口径；中英两份一起改。数不清楚的地方停下来问主控，别猜。

- [ ] **Step 2: 改**

- 「容器与布局 · `TyControls Containers`」表加两行（中：`TTyToolWindowBar` | IDE 式侧栏 / 底栏，工具窗口可拖到另一侧、布局可保存；`TTyToolWindowManager` | 工具窗口的跨侧拖动和布局保存），标题里的数 +2。
- 「示例」表加一行：`[toolwindows](examples/toolwindows/)` | IDE 式工作台：左右侧栏 + 底栏、跨侧拖动、保存 / 恢复布局。
- 英文版同样两处，**不是逐句翻译**，照英文 README 自己的说法写（[[doc-writing-native-tone]]）。
- 不写已知限制、不写实现机制。

- [ ] **Step 3: 提交**

```bash
cd /d/Projects/ty-3.1 && git add README.md README.en.md && git commit -m "docs(readme): tool window bars, the manager and the toolwindows example

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: 收尾——按 spec 逐条核、grep、全量、抽查变异、审查、写回 spec、真机验收表

**Files:**
- Modify: `docs/superpowers/plans/2026-09-24-toolwindow-phase-d.md`
- Modify: `docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md`

- [x] **Step 1: 按 spec 逐条核代码，不看测试**（[[green-tests-are-not-spec-conformance]]）

逐条对着代码查，每条记「在哪一行实现 / 为什么不需要」：

- §2：四个类的 `RegisterClass` 还在；设计期包里栏和 manager `RegisterComponents`、窗口和操作区 `RegisterNoIcon`；manager 的注册 uses 了 `tyControls.ToolWindows.Manager`。
- §3.1 / §4：窗口和操作区的 `Controller` 藏起来了（两条 `THiddenPropertyEditor`）。
- §3.2：设计期孤儿显示、提示、让位；运行时孤儿隐藏；resourcestring。
- §6.1：面板放下的尺寸（Task 5 Step 1 的结论）。
- §10.6：冲突提示；`SetManager`、`SetPlacement`、`AddBar`、`RemoveBar`、manager 被释放五处都重排、重画。
- §11：栏编辑器两项、窗口编辑器三项；「新建工具窗口」的步骤和顺序（含 `AddUndoAction`）；「添加操作区」同样记撤销；可用性全部问 `DesignRules`；csAncestor、frame 实例灰掉；不提供「删除工具窗口」。
- §16 第 7 步 C 期补的四条、第 8 步的文档要点（Task 8 Step 1 第 9 节逐条对）和 i18n 清单（孤儿提示、「添加工具窗口」、冲突提示、多余操作区提示、非窗口子控件提示、最大化、还原、收起、更多、组件编辑器菜单项——前面的 A / B 期已有，本期补齐后逐个在 pot 和 zh_CN.po 里找到）。

- [x] **Step 2: grep**

```bash
cd /d/Projects/ty-3.1 && grep -n "D 期" source/tyControls.ToolWindows*.pas tests/test.toolwindow.*.pas; for f in TyToolWindowInInlined TyToolWindowDesignCanAddWindow TyToolWindowDesignCanAddActions TyToolWindowDesignOtherSide TyToolWindowDesignMoveToOtherSide TyToolWindowDesignReturnTargets TyToolWindowDesignReturnToBar UsableBar; do printf '%s: src=%s dt=%s tests=%s ex=%s\n' $f $(grep -rlw $f source | wc -l) $(grep -rlw $f designtime | wc -l) $(grep -rlw $f tests | wc -l) $(grep -rlw $f examples | wc -l); done
```

Expected：`D 期` 字样都改成了现在的事实（注释里「设计期那一半归 D 期」之类）；`DesignRules` 的每个函数**在 `designtime/` 里有人调**（dt 列 ≥ 1，[[built-not-wired-is-the-default-failure]]）、在 `tests/` 里有人测；`UsableBar` 在 `designtime/`（经 `DesignRules`）和 `examples/` 里都有人用。

- [x] **Step 3: 跑全量**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --all --format=plain > /tmp/all.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/all.txt
```

Expected：errors / failures 都是 0，总数 = Task 0 的基线 + 本期新增条数。红了先按 [[known-rare-suite-flake]]、[[suite-order-widgetset-init]]、[[canary-then-rebuild]] 排查。

- [x] **Step 4: 【主控执行】三个产物各编一遍**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tycontrols.lpk && lazbuild -B tycontrols_dt.lpk && rm -rf examples/toolwindows/lib && lazbuild -B examples/toolwindows/toolwindows_example.lpi && git status --short languages/
```

Expected：三个都编过，`languages/` 干净。

- [x] **Step 5: 抽查变异（每条三拍，必须红）**

1. Task 2 的「`SetParent` 设计期那一支只摘标志不写 `Visible`」。
2. Task 3 的「`SetPlacement` 不调 `PlacementsChanged`」。
3. Task 3 的「冲突提示只画不让（`Content` 不扣）」。
4. Task 4 的「`OtherSide` 不查 csAncestor」。
5. Task 4 的「`ReturnTargets` 不排除 frame 实例」。

- [x] **Step 6: 整体代码质量审查**

对 `git diff <Task 0 的 HEAD>..HEAD -- source/ designtime/` 做一次：组件编辑器里有没有偷偷自己判可用性（应当全问 `DesignRules`）；三种提示行（漏入子控件、冲突、孤儿）的画法是否该合成一个小函数；注释与代码不符；遗留的「D 期」字样；try/finally 成对。审出来的问题修完回到 Step 3。

- [x] **Step 7: 把实现期的偏差写回 spec 原处**

「开工前要定的问题」里用户拍板的每一条、实现中新发现的每一处 spec 没写准的地方，都在 spec **原处**改并标「实现期修正（D 期）」。至少要落的：

- §3.1（问题 11：`StripHint` 是 `TTranslateString`）；
- §3.2（问题 2、8、10：孤儿铺满父控件、顶上让一行、摘标志后写 `Visible`）；
- §6.1（问题 16：放下栏的尺寸，看 Task 5 Step 1 的结论）；
- §9.9 / §10.6（问题 5：`UsableBar`；问题 8、9：冲突提示让一行、在哪几处重排）；
- §11（问题 1：菜单项固定、灰掉；问题 7：判定在 `DesignRules`；问题 15：~~「移到另一侧栏」不记撤销~~ 收尾改成两个移动菜单项都记撤销）；
- §15 加一条「D 期落地、待真机」指向本计划末尾的验收表；
- §16 第 7、8 步标「已完成（D 期）」。

- [x] **Step 8: 签收记录写进本计划末尾，提交**

签收记录写：全量条数、提交区间、变异抽查结果、spec 写回、遗留；再给发版时用的 CHANGELOG 草稿一行（只写用户可感知的：「新增：IDE 式侧栏 / 底栏 `TTyToolWindowBar` 与 `TTyToolWindowManager`：图标条 / 标签切换、左右侧互拖、底栏最大化、布局保存与恢复，设计器里可直接新建和移动工具窗口」）。

```bash
cd /d/Projects/ty-3.1 && git add docs/ && git commit -m "docs(toolwindows): phase D sign-off and corrections written back into the spec

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## D 期做完能看到什么

- Lazarus 组件面板「TyControls Containers」页上多了栏和 manager 两个按钮。放一条栏到窗体上，右键「新建工具窗口」两次，得到两个窗口、图标条上两个图标，点图标切页；`Ctrl+Z` 能把新建的窗口撤掉。
- 窗口右键「添加操作区」，往操作区里拖按钮；把 `Placement` 改成 `twpBottom`，窗口的标题变成底栏标签，操作区跟到标签行右端。
- 再放一条右栏和一个 manager，三条栏都指向它：左栏窗口右键「移到另一侧栏」就过去了。把右栏的 `Placement` 也改成左，两条左栏上立刻出现「与另一条栏的 Placement 相同」，改回来提示就没了。
- 删掉一个窗口再 `Ctrl+Z`，它出现在窗体上、顶上写着「不在工具窗口栏里，运行时隐藏」；右键「移回栏里 ▸」挑一条栏就回去。
- 对象查看器里窗口和操作区没有 `Controller`。
- `examples/toolwindows` 跑起来是一个类 IDE 窗体：左边 Explorer / Search，右边 Outline，编辑区下面 Problems / Output / Terminal；能跨侧拖、能最大化底栏、能收起再用 `Ctrl+J` 叫回来；关掉再开回到上次的样子；换肤、换密度都跟着变；Output 页里是事件日志。
- `docs/controls/toolwindows.md`、README 都有了。

**还做不到的**（spec §13 的不做清单）：边缘弹出、图标 / 标签徽标、每窗口记尺寸、键盘操作图标条、跨窗体拖动、浮动窗口。

---

## 真机验收表（给用户）

> **已合并（2026-09-28）**：这张表和 E 期的补充项已合成一张、从 1 连续编号（第 38 项换成 E 期的 38′），给用户用的是 `docs/superpowers/plans/2026-09-28-toolwindow-acceptance.md`。这里留作原始记录。

D 期是工作台的里程碑：下面是 spec §15 全部「只能真机验」的项，加上 D 期新出来的。**大部分在 `examples/toolwindows` 里做**；IDE 那一组用 Lazarus 打开 `examples/toolwindows/toolwindows_example.lpi`，在设计器里打开 `umain.lfm` 做。验之前主控已经 `lazbuild -B tycontrols.lpk`、装好 `tycontrols_dt.lpk` 并重启了 Lazarus。

「平台」一列写的是**必须**在哪验；空着的在手头的 Win32 上验一遍就行。

### 一、Lazarus IDE（设计器）

| # | 验什么 | 怎么操作 | 期望 |
|---|---|---|---|
| 1 | 面板图标 | 看「TyControls Containers」页；系统缩放 100% / 150% / 200% 各看一眼 | 栏和 manager 两个按钮有图标、不糊 |
| 2 | 放下栏的尺寸 | 从面板点一下放一条栏到空白窗体上（150% 缩放下再放一次） | 左侧一条带图标条的栏；对象查看器里 `ExpandedSize` 正好 240（不是 239 / 241 / 380）、不加粗。拖一个矩形放下也一样：拖出的宽被忽略，栏按 240 推导（已知，spec §6.1） |
| 3 | 改 `Placement` | 对象查看器里改成 `twpRight` / `twpBottom` | `Align` 跟着变，栏挪到父控件那一侧的最外边 |
| 4 | 新建工具窗口 + 撤销 | 栏右键「新建工具窗口」；再 `Ctrl+Z` | 新窗口成为当前页、名字和标题一样、窗体标题出现「*」；撤销后窗口没了 |
| 5 | 设计期点图标 / 标签切页 | 两个窗口，点另一个图标；底栏点另一个标签 | 松开时切页，对象查看器的 `ActiveIndex` 跟着变 |
| 6 | 标签行让位给栏 | 底栏：点标签行后面的空白处 | 选中的是栏，不是当前页窗口 |
| 7 | 「显示窗口 ▸」（英文 IDE：`Show Window ▸`） | 栏右键 → 显示窗口 ▸ → 挑一个窗口 | 切过去并选中它；子菜单每项是「名字 "标题"」 |
| 8 | 移到另一侧栏 + 撤销 | 左、右两条侧栏 + manager；左栏窗口右键「移到另一侧栏」；再 `Ctrl+Z`；底栏窗口右键看同一项 | 窗口到了右栏、成为当前页、窗体标题出现「*」；撤销后回到左栏，排在**末尾**、成为当前页（原来的序号不还原，已知）；底栏窗口上这一项是灰的 |
| 9 | 添加操作区 | 窗口右键「添加操作区」，往里拖一个按钮；再右键看同一项 | 操作区出现在标题行右端，按钮在里面；第二次这一项是灰的 |
| 10 | Placement 冲突提示 | 把右栏的 `Placement` 改成 `twpLeft`；再改回来 | 两条栏底部立刻出现「与另一条栏的 Placement 相同」，不用点一下才刷新；改回来立刻消失 |
| 11 | 撤销删除 → 孤儿 | 选中一个窗口按 Delete，再 `Ctrl+Z` | 窗口出现在窗体上、顶上一行「不在工具窗口栏里，运行时隐藏」；右键「移回栏里 ▸」挑原来的栏，回去并成为当前页（排在末尾）；再 `Ctrl+Z`，又成孤儿 |
| 12 | 粘贴 | 复制一个窗口；点侧栏图标条（选中栏）再粘贴；再选中当前页窗口的正文粘贴一次 | 第一次进了栏；第二次落在窗口里，显示成孤儿提示 |
| 13 | 继承窗体 | 新建一个继承自 `umain` 的窗体，在继承来的窗口上右键 | 「移到另一侧栏」灰；往继承来的栏里「新建工具窗口」可以 |
| 14 | frame 实例 | 新建一个 frame 放一条栏和两个窗口，再把 frame 放到窗体上，右键 frame 里的栏和窗口 | 新建 / 添加 / 移动三类菜单项都是灰的 |
| 15 | `Controller` 隐藏 | 选中窗口、选中操作区看对象查看器 | 没有 `Controller`；栏上有 |
| 16 | 保存再打开 | 调过顺序、换过当前页、有一个孤儿的窗体保存、关掉、再打开 | 顺序、当前页、孤儿都还在 |
| 17 | 组件树里选中藏着的窗口 | 在对象查看器的组件树里点一个非当前页的窗口 | 不会切过去（LCL 设计器不调 `ShowControl`，文档写了；**据 Lazarus 源码推断，以真机为准**）；记下实际表现 |
| 18 | 中文 IDE | Lazarus 切到中文重启，右键栏和窗口 | 菜单项是中文 |

### 二、运行时（`examples/toolwindows`）

| # | 验什么 | 平台 | 怎么操作 | 期望 |
|---|---|---|---|---|
| 19 | 启动事件 | | 看 Output 页 | 第一行 `Ready`；启动时没有 `active =` 之类的切页日志 |
| 20 | 跨侧拖动 | | 按住 Search 图标拖到右栏图标条、再拖到右栏内容区上、再拖到编辑区上 | 右栏条上出现插入线；在内容区上线停在最后一个图标后面；编辑区上是禁止光标、没有线；在右栏松开就过去了，日志一行 `moved` |
| 21 | 拖动光标 | Win32、GTK3、Qt、Cocoa | 同上，看光标 | 拖动中一直是拖动光标 / 禁止光标，松开后恢复 |
| 22 | Esc 取消 | Win32、GTK3 | 拖到一半按 Esc | 什么都没变；松开不算点击 |
| 23 | 拖出源栏后的坐标 | GTK3（X11 / Wayland） | 从左栏拖到右栏 | 右栏的插入线跟着指针走，位置对 |
| 24 | 从双击起拖 | Qt | 双击一个图标，第二次按下不松、直接拖 | 能拖起来 |
| 25 | Alt+Tab 中途 | 各 widgetset | 拖到一半 Alt+Tab 切走 | 拖动取消，回来后栏状态正常 |
| 26 | 拖动中弹模态框 | 各 widgetset | Diagnostics › Show a Dialog in 3 s，马上去拖一个图标别松手 | 对话框弹出时拖动取消；关掉对话框后没有残留的插入线或光标 |
| 27 | 拖动中弹菜单 | 各 widgetset | Diagnostics › Pop Up a Menu in 3 s，同上 | 同上 |
| 28 | 捕获期间离开 | Win32 | 按住图标（不超过阈值）移出栏再移回来松开 | 按阈值内松开算点击，图标悬停状态不乱 |
| 29 | 窗口里的按钮移动自己 | Win32 优先 | 点 Outline 操作区的双向箭头按钮（提示 `Move to the other side`） | Outline 到了另一侧，程序不崩；日志先是 `MoveWindow returned True; Outline is in RightBar right now`（返回 True、还在旧栏），再是 `moved OutlineWin from RightBar (#0)` |
| 30 | 窗口里的按钮恢复布局 | Win32 优先 | 先把布局弄乱，再点 Explorer 操作区的逆时针箭头按钮（提示 `Reset layout`） | 恢复到启动时的样子，程序不崩 |
| 31 | 布局存取 | | 拖乱、收起一侧、调宽、换当前页 → Layout › Save Layout → 再弄乱 → Layout › Load Layout；再 Layout › Reset Layout；再关掉程序重开 | Load 回到存的样子；Reset 回到 .lfm 的样子；重开回到关之前的样子 |
| 32 | 底栏最大化 / 收起 | | 标签行的最大化按钮、收起按钮；标签右键菜单（Maximize / Restore、Hide Panel）；View › Bottom Panel（Ctrl+J） | 最大化压掉编辑区、还原回原高；收起后界面上没有底栏，Ctrl+J 叫回来 |
| 33 | 拉宽与吸附 | | 拖侧栏和底栏的边；拖到很窄再松手；拖回来 | 实时变宽；拖到内容下限一半以下松手 = 收起；拖回来不收起 |
| 34 | 右键菜单 | | 侧栏图标上右键「Move to Other Side」；图标条空白处右键 | 图标上弹菜单、能移；空白处不弹栏的菜单 |
| 35 | 溢出 | | 把窗体缩矮、缩窄到图标 / 标签放不下 | 出现溢出按钮；左栏菜单往右开、右栏往左开、底栏往下开 |
| 36 | 溢出菜单位置 | GTK3 / Qt Wayland | 同上 | 菜单贴着溢出按钮，不跑到屏幕角上 |
| 37 | 提示 | | 指针停在图标上、标签上、最大化按钮上 | 图标显示 StripHint；中文界面下是中文 |
| 38 | ~~禁用当前页~~ **E 期替换**：用户真机验出被困住，不接受这条限制；新期望见 `2026-09-27-toolwindow-phase-e.md` 末尾「补充真机验收项」的 38′ | 各 widgetset | ~~底栏切到 Output，Diagnostics › Disable Output Page，再点标签 / 按钮~~ | ~~标签行跟着失灵（文档写的「别禁用窗口本身」）；记下各平台点击落到了哪里~~ |
| 39 | 换父后的 IME / 光标 | Win32、Linux | Search 框里用中文输入法打到一半（不上屏），拖 Search 到右栏 | 组字被丢掉（文档写的），程序不崩；再点进去能正常输入 |
| 40 | 换肤 | | 17 个主题逐个切，亮 / 暗都切 | 标题行、标签下划线、图标着色、边缘线都对；拖动时插入线看得见（高对比度皮肤重点看） |
| 41 | 换密度 | | View › Density › Modern / Classic 来回切 | 图标条、标题行、标签跟着变，操作区按钮不被裁 |
| 42 | 字形清晰 | Linux、macOS | 看图标条、溢出、最大化、收起按钮 | 不糊 |
| 43 | 中文界面 | | 系统语言中文（或 `--lang zh_CN`）启动 | 菜单、窗口标题、日志是中文；布局照常存取（按 Name 认窗口） |

发现问题照分支标准修（先证实、写守卫、看着变红、变异、全量）；**先问「这个 example 不存在，这个行为还算不算错」**——是才改 `source/`，只是示例布局想要点别的就改示例（[[example-content-two-purposes]]）。

---

## D 期签收（2026-09-27）

- **全量**：7715 条，errors 0 / failures 0（C 期签收 7666）。
- **提交区间**：Task 0–9 `1baf26e2..40db6c60`；整体审查后的修复 `3f968bbf..a95523dd`。
- **编译**：主控编过运行时包 `tycontrols.lpk`、设计期包 `tycontrols_dt.lpk`、示例 `examples/toolwindows`，均 0 错。
- **i18n**：工具窗口的 11 条 resourcestring 在 `tyControls.StrConsts.pot` 和 `tycontrols.strconsts.zh_CN.po` 里齐全；`tyControls.Design.CompEditors.pot` 和编出来的 rsj 一致。
- **spec 写回**：§2、§3.1、§3.2、§6.1、§9.9、§10.6、§11、§15、§16 原处标「实现期修正 / 补（D 期）」。开工前问题 15（「移到另一侧栏」不记撤销）已被收尾推翻：两个移动菜单项都记撤销。
- **变异抽查（Step 5）**：第 1–4 条在 Task 2–4 实现时逐条做过、都红；第 5 条不适用（`ReturnTargets` 只扫 `Owner.Components`，frame 实例里的栏本来就不在候选里，那句排除是死代码，没写）。收尾修复批次每条修复另做了变异。
- **真机**：待用户按上面的「真机验收表」逐项做。
- **遗留**（不阻塞）：
  - M-5「栏 `Loaded` 不 `Relayout`」在冲突提示那条测试上是等价变异（LCL 自己的 `Loaded → LoadedAll → AdjustSize` 也会重排），那一句守的是推导宽度，由 `TestExpandedSizeStreamsOnBothSidesOfTheDefault` 杀。
  - 中间提交没有逐个单独编译验证，只验了 HEAD。
- **CHANGELOG 草稿**（发版时用）：新增：IDE 式侧栏 / 底栏 `TTyToolWindowBar` 与 `TTyToolWindowManager`：图标条 / 标签切换、左右侧互拖、底栏最大化、布局保存与恢复，设计器里可直接新建和移动工具窗口。
