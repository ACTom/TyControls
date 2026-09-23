# IDE 工作台 C 期：manager、跨侧拖动、布局保存 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（本期约定，优先于子技能的默认做法）**：整期连续实现，**每个任务单独提交**，每个任务只跑它列出的相关 suite；**不在任务之间安排审查环**。整期做完后（Task 14）跑一次全量、做一次整体规格核对和一次代码质量审查。

**Goal:** 把空壳 `TTyToolWindowManager` 做成真的组件：栏经 `Manager` 属性注册到它上面，图片列表回落到 `Manager.Images`；左右侧栏之间能拖动工具窗口（悬停时画插入线、松开时移过去、各种取消），并提供 `MoveWindow` / `CanMoveWindow` / `OnWindowMoved` 等公开接口；最后是布局串的保存、读取、恢复默认。

**Architecture:** manager 是同一单元里的非可视组件，持有注册栏的列表、`Images`、「正在拖」标记、一条自己的异步队列和默认布局。跨侧拖动复用 B 期抽出来的手势引擎，只给它加一个「目标栏」；候选栏的命中写成 `tyControls.ToolWindows.Layout` 里的纯函数，manager 每次移动现建探测矩形交给它。布局串的解析、格式化、版本漂移计划都是新单元 `tyControls.ToolWindows.LayoutText` 里的纯函数，控件只负责把现状装成输入、把计划照做成一个批次。

**Tech Stack:** FPC / Lazarus LCL、BGRABitmap、`TTyPainter`、fpcunit。

**设计依据：** `docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md`（下称 spec）。本计划覆盖 spec §16 第 5 步（含 B 期留下的 6 项）和第 6 步。spec 里所有「实现期修正（A 期 / B 期 / B 期收尾）」以修正后为准。

**不在本期**（D 期）：组件编辑器（「新建工具窗口」「移到另一侧栏」「移回栏里」）、设计期 Placement 冲突提示和孤儿窗口提示、组件面板注册与图标、示例、`docs/controls/toolwindows.md`、README。本期**不新增 resourcestring**（C 期的行为都没有要显示的文字）。

---

## 开工前要定的问题

下面是 spec 的 C 期内容互相矛盾、与 A / B 期实现冲突、或者 spec 没写到的地方。每条都给了建议，**计划正文按建议写**；用户改了哪条，执行时改对应任务，收尾时（Task 14）写回 spec。

### 一、产品方向 / 用户可见行为（要问用户）

1. **禁用的侧栏算不算放置目标？**（spec §9.4 的候选栏条件只列了「可见、不在释放中、同一窗体、没冲突」。）
   源栏禁用时根本拖不起来（LCL 不给禁用控件发鼠标消息，B 期也补了同一道闸）；但另一侧栏 `Enabled = False` 时，按字面照样接住拖过来的窗口——用户把东西放进一个灰掉的栏里。
   **建议**：`IsEnabled` 为假的栏不是跨栏目标（不画线、`crNoDrop`，松开即取消）；`MoveWindow` 这个 API 不管 Enabled，照常可用。

2. **「Showing 之后第一次改动布局之前也记」（spec §10.5），「改动布局」包括哪些？**
   spec 在「算搭建」那一条里列了 `Collapsed` / `ExpandedSize` / `WindowIndex` / `MoveWindow`，没提**切当前页**。代码搭的 manager、没调过 Load / Reset / `CaptureDefaultLayout` 时：用户启动后先点了另一个图标，再点「恢复默认布局」——按字面，切页不触发记录，Reset 会先记下「此刻」（已经切过的样子）再应用，当前页恢复不回去。
   **建议**：凡是布局串里存的东西都算——`Collapsed`、`ExpandedSize`（含拉宽边）、调顺序（手势、`WindowIndex`、`MoveWindow` 同栏）、跨栏（`MoveWindow`、拖放、直接改 `Parent`）、**当前页换了**（点图标 / 标签 / 溢出菜单、代码设 `ActiveWindow` / `ActiveIndex`）。

### 二、实现层面的取舍（主控可按建议直接定）

3. **侧 ↔ 底的判据不能整个复用 `MovesAcrossBarKinds`**（spec §16 第 5 步写「复用它的判据」）。
   `TTyToolWindow.MovesAcrossBarKinds` 把「窗口或任一条栏在加载 / 设计 / 释放中」算成**不跨类**（那是 `Parent :=` 抛异常的豁免）。`MoveWindow` 在设计期是要同步做的（D 期组件编辑器用），照搬的话设计期 `MoveWindow(侧栏窗口, 底栏)` 会过检查、`SetParent` 又不抛，窗口就真的跨到底栏去了。
   **建议**：把「两边都是栏、一侧一底（按 Placement）」拆成实现段的小函数 `BarKindsDiffer(AOld, ANew)`；`MovesAcrossBarKinds` = 它 + 豁免；manager 的结构检查只用它，不带豁免。

4. **spec §9.2 记录里 B 期没加的三个字段（源索引、窗口原来是否当前页、栏原来是否收起）没有读者。**
   按下时什么都不激活、拖动中什么都不挪，这三个量到提交那一刻和按下时一模一样；`OnWindowMoved` 的 `AOldIndex` 在提交前现取 `IndexOfWindow` 就是它。加了就是「建好没接线」（[[built-not-wired-is-the-default-failure]]）。
   **建议**：不加；收尾在 §9.2 原处标注「实现期修正（C 期）：不需要，理由……」。

5. **栏析构里的 `Application.RemoveAsyncCalls(Self)`（A 期留给 C 期的那一句）撤不掉 manager 的队列。**
   `RemoveAsyncCalls(AnObject)` 按**方法所属的对象**匹配（`application.inc:2356`，`TMethod(lItem^.Method).Data = AnObject`）；队列由 manager 持有、排的是 manager 的方法，栏这一句永远匹配不到。A 期注释的前提不成立。另外它在 `Application` 析构的后半段会抛异常（`AppDoNotCallAsyncQueue` 置位之后，`application.inc:161, 2377-2378`）。
   **建议**：栏上删掉这一句和那段注释；manager 析构里撤自己的，带 `not (AppDoNotCallAsyncQueue in Application.Flags)` 守卫；队列里涉及某条栏 / 某个窗口的项由 manager 的 `Notification(opRemove)` 删（spec §9.9 本来就这么写）。

6. **`TryFinishLoading` 只在 manager 和栏的 `Loaded` 里调，会漏。**（spec §10.5：「manager 的 Loaded、每条栏 Loaded 的最后一句都调」，而判据要求「所有参与者（含窗口）都不在 csLoading」。）
   读取器按**读入顺序**逐个调 `Loaded`（`reader.inc:1528-1530`），父控件先于子控件读入：栏的 `Loaded` 跑的时候它的窗口还在 csLoading。窗体里非可视组件写在控件后面（`customform.inc:1049-1060`），manager 通常最后一个 `Loaded`，碰巧能收尾；frame、继承窗体、manager 写在别处时就没人收尾。
   **建议**：`TTyToolWindow` 也重写 `Loaded`，最后一句经 `Bar.Manager` 调 `TryFinishLoading`。谁最后一个离开 csLoading，谁收尾。

7. **普通 Load / Reset 的批次不能用 `BeginSilent`。**
   `BeginSilent` 同时压住栏的 `OnChange` / `OnCollapse` / `OnExpand` **和**窗口的 `OnShow` / `OnHide`；spec §6.6 / §10.4 要求普通布局应用里窗口的 `OnShow` / `OnHide` **照常**，只有加载结束时应用挂起计划才全静默。
   **建议**：栏加一个独立的批次计数 `FLayoutBatch`：只进 `EventsAllowed`（压栏事件）、让切页 / 收起跳过焦点那一步、让注销不回落（见下条）。挂起计划 = `BeginSilent` + 批次一起包。

8. **批次内窗口离开源栏时不回落当前页。**（spec §5.2：「布局应用不走这条，按 §10.3 自己的回落规则」。）
   现在的 `UnregisterWindow` 会立刻 `SwitchCore(下一个)`：那一页先显示再被计划藏掉，普通 Load 里多发一对 `OnShow` / `OnHide`。
   **建议**：`FLayoutBatch > 0` 时当前页离开只置 nil，由计划统一激活。

9. **`MoveWindow` 的事件顺序要延后。**（spec §6.6：源栏 `OnChange` → 目标栏 `OnExpand` → 目标栏 `OnChange` → `OnWindowMoved`，都在 `EnableAlign` 和焦点恢复之后。）
   现在注销 / 注册 / 收起的事件都在 `SetParent` 和 setter 里当场发，顺序和时机都对不上。
   **建议**：栏加「延后事件」：`BeginDeferEvents` 期间 `DoChange` 和 `SetCollapsed` 的事件只记进一个集合，`EndDeferEvents` 交还集合，由调用方按 spec 的顺序发（发之前再过一遍 `EventsAllowed`）。运行时直接改 `Parent`（同类栏，spec §3.2）走同一套、同一顺序。

10. **命中纯函数只管侧栏候选。** spec §9.4 把底栏标签的落点也写在「manager 上的纯函数」一节里；B 期已经在栏上实现了底栏标签行的落点（`HeaderDropSlotIn`），底栏又永远不跨栏。
    **建议**：纯函数 `TyToolWindowDropAt` 只处理「源侧栏 + 其他侧栏」；底栏标签的调顺序保持 B 期的路子，manager 不参与。收尾在 §9.4 标注。

11. **目标栏的插入线要一个「外来落点」模式。** 现在 `DropLineY` 只在**自己的**引擎在拖、且不是空操作时画线；目标栏的引擎是闲着的。
    **建议**：栏加 `FForeignDrop: Boolean`，由源栏的引擎经 `SetForeignDrop(slot)` 写；有外来落点时按槽位画线，不做空操作判断（跨栏没有空操作）。

12. **「参与的栏改了 `Collapsed` / `Placement` / `Manager` 就取消」（spec §9.7）按「源栏或此刻的目标栏」理解。** 其他注册栏的变化，下一次移动重建探测矩形时自然反映。

13. **队列「`GetCaptureControl` 在 W 里时再排一次」只再排一次。** 第二次执行时捕获还在 W 里也照做——那时按钮自己的点击处理早就返回了，再排下去可能永远排。

14. **Load / Reset 从 manager 自己发的事件里重入：返回 False。** spec 只给 `MoveWindow` 定了「从事件处理里重入返回 False」；Load / Reset 同一口径，免得在 `OnWindowMoved` 里读布局、又在布局批次里发出 `OnWindowMoved`。

15. **默认布局存成一份布局串。** 记默认布局 = `SaveLayoutToString`；`ResetLayout` = 按这份串走同一条应用路径。spec「默认布局里没有的窗口，Reset 时留在原处」正是 §10.3「未放置的留在当前栏」，一套规则不写两遍。

16. **保存跳过重名窗口的范围 = 读取时按名字找的范围**：manager 下**可用**栏（没因 Placement 冲突被排除）里的窗口。两边范围一致，「保存写出来的串必须能读回来」才成立。

17. **`IsBarUsable` 现算，不缓存。** 注册栏最多几条，现算比「在 `SetManager` / `SetPlacement` / `opRemove` 三处记得失效」可靠。spec 说的「在这三处重新检查」变成：这三处取消涉及的拖动（问题 12）；设计期冲突提示的重画归 D 期。

18. **布局串解析和版本漂移计划放新单元 `source/tyControls.ToolWindows.LayoutText.pas`**（纯函数，只 uses `SysUtils`）。几何单元已经 558 行，职责是「标题行 / 图标条 / 槽位的几何」，布局串是另一回事。代价是登记 `tycontrols.lpk`（[[new-unit-missing-from-lpk]]，`TReleaseManifestTest` 守着）。

19. **设计期 `MoveWindow`：同步、不发事件、不问 `OnCanMoveWindow`，但通知设计器**（`OwnerFormDesignerModified`，同 `ReorderWindow` 现在的做法），D 期的菜单项不用再各自补。

20. **`SaveLayoutToString` 在 manager 下没有可用栏时返回 `TYTOOLLAYOUT/1|end`**（能读回来、读了什么都不改），不返回空串。

---

## B 期留给本期的 6 项 → 接线任务

spec §16 第 5 步那 6 项，每一项在哪个任务做、谁读它。Task 14 Step 2 逐项核。

| 项 | 接线任务 | 读它的地方 |
|---|---|---|
| 引擎的「目标栏」 | Task 8 | `TTyToolWindowGesture.SetTarget` / `Target`；`ReleaseResources` 清目标栏的反馈；manager 在目标栏被释放 / 改状态时取消 |
| §9.2 记录里的源索引 / 原来是否当前页 / 原来是否收起 | —（问题 4：不加） | 收尾写回 spec |
| manager 的「正在拖」标记 | Task 8 | `IsDragging`、`CancelDrag`、布局应用第 1 步、非源栏看到无按键移动时取消 |
| 调顺序发 `OnWindowMoved` | Task 4 | `ReorderWindow`（图标拖动、标签拖动、`WindowIndex`、同栏 `MoveWindow` 都经过它） |
| `MoveWindow` / `CanMoveWindow` 复用侧 ↔ 底判据 | Task 3 | `BarKindsDiffer`（问题 3） |
| 布局应用第 2 步直接 `Maximized := False` | Task 12 | 应用批次开头 |

---

## 接口清单（全计划用这一套名字）

**公开的（spec §9.9、§10.1）：**

```pascal
type
  TTyCanMoveWindowEvent = procedure(Sender: TObject; AWindow: TTyToolWindow;
    ATargetBar: TTyToolWindowBar; var AAllow: Boolean) of object;
  TTyWindowMovedEvent = procedure(Sender: TObject; AWindow: TTyToolWindow;
    ASourceBar: TTyToolWindowBar; AOldIndex: Integer) of object;

  TTyToolWindowManager = class(TTyComponent)
  public
    function MoveWindow(AWindow: TTyToolWindow; ATargetBar: TTyToolWindowBar;
      AIndex: Integer = -1): Boolean;
    function CanMoveWindow(AWindow: TTyToolWindow; ATargetBar: TTyToolWindowBar): Boolean;
    procedure CancelDrag;
    function IsDragging: Boolean;
    { 这条栏是不是可用:注册在本 manager 上,且没有别的注册栏和它 Placement 相同(spec §10.6)。 }
    function IsBarUsable(ABar: TTyToolWindowBar): Boolean;
    function SaveLayoutToString: string;
    function LoadLayoutFromString(const AText: string): Boolean;
    function ResetLayout: Boolean;
    procedure CaptureDefaultLayout;
  published
    property Images: TCustomImageList read FImages write SetImages;
    property OnCanMoveWindow: TTyCanMoveWindowEvent read FOnCanMoveWindow write FOnCanMoveWindow;
    property OnWindowMoved: TTyWindowMovedEvent read FOnWindowMoved write FOnWindowMoved;
    property OnLayoutApplied: TNotifyEvent read FOnLayoutApplied write FOnLayoutApplied;
  end;

  TTyToolWindowBar
  published
    property Manager: TTyToolWindowManager read FManager write SetManager;
```

**单元内部的（同单元 private 互相可见，不对外）：**

| 在谁身上 | 名字 | 首次出现 |
|---|---|---|
| manager | `FBars`、`AddBar`、`RemoveBar` | Task 1 |
| manager | `NotifyImagesChanged` | Task 2 |
| 实现段函数 | `BarKindsDiffer(AOld, ANew: TWinControl): Boolean` | Task 3 |
| manager | `FEventDepth`、`StructureAllows` | Task 3 |
| manager | `MoveNow`、`WindowMoved` | Task 4 |
| 栏 | `TTyToolWindowBarEvent = (twbeChange, twbeExpand, twbeCollapse)`、`TTyToolWindowBarEvents`、`FDeferEvents`、`FPendingEvents`、`BeginDeferEvents`、`EndDeferEvents`、`FireBarEvent`、`PlaceWindow` | Task 4 |
| 窗口 | `FQuietMove` | Task 5 |
| manager | `TTyToolWindowQueued`、`FQueue`、`FQueuePosted`、`Enqueue`、`HasQueued`、`PurgeQueue`、`RunQueue`、`MustQueue` | Task 6 |
| 几何单元（公开） | `TTyToolWindowDropProbe`、`TTyToolWindowDropProbes`、`TyToolWindowDropAt` | Task 7 |
| 引擎 | `FTarget`、`FAllowed`、`SetTarget`、`Target`、`AllowedFor` | Task 8 |
| manager | `FDragSource`、`DropTargetAt`、`BarChanged` | Task 8 |
| 栏 | `FForeignDrop`、`SetForeignDrop`、探针 `ForeignDropForTest` | Task 8 |
| 新单元（公开） | `TyToolLayoutTag`、`TTyToolLayoutSide`、`TTyToolLayoutGroup`、`TTyToolLayoutDoc`、`TyToolLayoutParse`、`TyToolLayoutFormat` | Task 10 |
| 新单元（公开） | `TTyToolLayoutBarState`、`TTyToolLayoutWorld`、`TTyToolLayoutRef`、`TTyToolLayoutBarPlan`、`TTyToolLayoutPlan`、`TyToolLayoutPlanFor` | Task 11 |
| 栏 | `FLayoutBatch` | Task 12 |
| manager | `FApplying`、`ApplyText`、`BuildWorld` | Task 12 |
| manager | `FDefaultText`、`FDefaultCaptured`、`FPendingText`、`FPendingKind`、`EnsureDefaultCaptured`、`NoteLayoutChanging`、`AnyParticipantLoading`、`TryFinishLoading`、`LayoutAppliedAsync` | Task 13 |
| 窗口 | `Loaded` 重写 | Task 13 |

类型和方法**跟着第一个读它的任务一起加**，不提前加。

---

## 文件清单

| 文件 | 本期改什么 |
|---|---|
| `source/tyControls.ToolWindows.pas` | manager 本体；栏的 `Manager`、`EffectiveImages` 回落、延后事件、外来落点、布局批次；窗口的同类改 Parent 簿记、`Loaded`；引擎的目标栏 |
| `source/tyControls.ToolWindows.Layout.pas` | 跨栏命中纯函数 `TyToolWindowDropAt`（Task 7） |
| `source/tyControls.ToolWindows.LayoutText.pas` | **新建**。布局串解析 / 格式化 / 漂移计划（Task 10、11） |
| `tycontrols.lpk` | 登记新单元（Task 10） |
| `tests/test.toolwindow.manager.pas` | **新建**。`TTyToolWindowManagerTests`（无头：注册、冲突、`CanMoveWindow`、`MoveWindow` 同步、事件、直接改 Parent）与 `TTyToolWindowManagerLiveTests`（真句柄：焦点、队列、Showing 之后的时机） |
| `tests/test.toolwindow.crossdrag.pas` | **新建**。`TTyToolWindowCrossDragTests` |
| `tests/test.toolwindow.layouttext.pas` | **新建**。`TTyToolWindowLayoutTextTests`（纯函数表） |
| `tests/test.toolwindow.layoutapply.pas` | **新建**。`TTyToolWindowLayoutApplyTests` |
| `tests/test.toolwindow.geometry.pas` | `TyToolWindowDropAt` 的表 |
| `tests/test.toolwindow.images.pas` | `Manager.Images` 回落 |
| `tests/test.toolwindow.window.pas` | 流式：`Manager` 属性往返、同 Placement 两种流顺序 |
| `tests/tytests.lpr` | uses 加四个新测试单元 |
| `docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md` | 只在 Task 14 写回 |

**共享文件**：本计划**不改** `source/tyControls.Base.pas`、`source/tyControls.Painter.pas`。执行中发现非改不可，**停下来先问用户**，说明要改什么、为什么不能在本单元里解决。

**主题**：不新增类型键和 token。目标栏的插入线用 A 期已有的 `TyToolWindowDropIndicator`（`--toolwindow-drop-color`）和 `--toolwindow-drop-size`，和源栏同一个写法。所以本期**不碰** `themes/light.tycss`、两个生成器和 golden。执行中如果真要加（比如想给目标栏整条加高亮——spec 没要求），那就是 spec 变更：先问用户，再改 light.tycss、跑 `scripts/gen-defaulttheme.ps1`（先验忠实度）和 `scripts/gen-tycss-catalog.ps1`、在 `test.themes` 的 GGRID / GMETRICS 里补、重铺 golden。

**不碰**：`designtime/`、`examples/`、`docs/controls/`、`languages/`。

---

## 实现期的地雷（每个任务开工前看一眼）

A 期 12 条、B 期 14 条照样有效（CRLF 变异先 `git diff --stat`、变异后 `lazbuild -B`、引擎构造第一句建析构最后一句放、处理器挂在引擎上要引擎自己摘、标签行视觉变化走 `InvalidateHeader`、「谁先读就是谁的」、三套坐标、RTL 只镜像一次、捕获者自己的 MouseUp 里藏起自己、`WndProc` 记按下坐标、无头的边界、夹具别对称、哨兵底色、`SetBounds` 原样再设是空操作、`AssertSame` 已释放指针会假绿）。C 期另加：

1. **`FreeNotification` 是双向的**（`compon.inc:559-577`）：`A.FreeNotification(B)` 同时把 B 挂到 A、A 挂到 B；`RemoveFreeNotification` 一次拆两边。manager 和栏互相挂着，manager 的队列又挂着窗口和栏——拆之前确认没有别的引用还指望这条通知；拿不准就**不拆**（多一次通知无害，少一次是悬垂指针）。另外 `FreeNotification(自己的 Owner)` 直接返回、什么都不挂（`compon.inc:562`）。
2. **通知顺序说不准**：释放一个列表 / 栏时，manager 和栏谁先收到 `opRemove` 取决于挂的先后（表倒序通知）。每一方收到通知时都只处理自己的引用，**不许假设对方已经清过**；「正在释放的不算生效」统一靠 `csDestroying` 过滤（A 期 `EffectiveImages` 的做法）。
3. **`Loaded` 的顺序 = 读入顺序**，父先子后；窗体里 manager 通常最后（问题 6）。**fixup 倒序执行**（[[fpc-streaming-fixup-order-facts]]）：`Manager` 的 setter 在 fixup 里跑，**绝不抛异常**（会中止整个窗体加载），冲突也只是「不可用」。
4. **换父控件重建 W 里所有句柄**：在 W 自己的按钮点击里同步换父 = 在点击处理里销毁按钮的句柄。所以 Showing 之后的跨栏移动和布局应用排队（spec §9.9 / §10.5）。
5. **无头的窗体永远不 `Showing`**：无头下 `MoveWindow` 和 Load 永远走同步那一支。排队、「Showing 之后第一次改动之前记默认布局」都只能在真句柄夹具里测（`TTyToolWindowManagerLiveTests`，自带 widgetset 惰性初始化开关，照 `test.toolwindow.focus` 的写法；[[suite-order-widgetset-init]]）。
6. **抽队列**：`Application.ProcessMessages` 会跑 `ProcessAsyncCallQueue`（`test.controls.combobox` 就这么用）。**先查**无头下它是不是真的抽空了本 manager 排的项；真句柄夹具里一定行。
7. **`RemoveAsyncCalls` 按方法的对象匹配、应用关停后会抛**（问题 5）。
8. **`ClientToScreen` 无头也能用**：没有句柄时 `GetClientOrigin` 是父链 `Left / Top` 的累加（`wincontrol.inc:4007-4026`、`control.inc:1632-1639`），同一窗体上的两条栏互相换算是一致的。`FindControlAtPosition` 只在有句柄时问（spec §9.4）。
9. **事件都在 `EnableAlign` 和焦点恢复之后发**；`DisableAlign` 和 `BeginDeferEvents` 一律 try/finally 成对——中途抛异常卡住的计数没有任何断言会指向它。
10. **批次和延后是两件事**：`FLayoutBatch`（压栏事件、跳过焦点、不回落）、`BeginSilent`（压全部用户事件）、`BeginDeferEvents`（记下来稍后按顺序发）互不替代（问题 7、9）。
11. **布局串顺序只靠列表位置**，不写数字顺序键（[[index-keyed-string-sort-trap]]）。
12. **截断测试先把状态挪离要读的串**（spec §14）：不挪的话，前缀即使被应用了照样绿。
13. **新单元写出来是 LF**：仓库 `core.autocrlf = true`，提交时规范化，检出后是 CRLF。变异用的搜索串照地雷 1（B 期）先确认命中。

---

## 跑测试的固定套路

改了 `source/` 之后**必须** `lazbuild -B`。exe 用唯一名 `tytests-31.exe`（别的会话也在跑 `tytests.exe`，[[parallel-agent-worktree-hazards]]）。

跑一组 suite（把 `SUITES` 换成任务里列的名字）：

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi > /tmp/build.txt 2>&1 || { tail -30 /tmp/build.txt; false; } && cd tests && cp tytests.exe tytests-31.exe && for s in SUITES; do ./tytests-31.exe --suite=$s --format=plain > /tmp/t-$s.txt 2>&1; printf '%s: ' $s; grep -E "Number of (run tests|errors|failures)" /tmp/t-$s.txt | tr '\n' ' '; echo; done
```

**判据是每个 suite 那一行都有 `Number of run tests`、errors / failures 为 0**，不是 exit code。某一行为空 = 跑丢了（或 suite 名写错，`No tests selected.` 也是空），重跑，别读成通过。

全量（只在 Task 0 和 Task 14；输出必须重定向到文件，[[known-rare-suite-flake]]）：

```bash
cd /d/Projects/ty-3.1/tests && ./tytests-31.exe --all --format=plain > /tmp/all.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/all.txt
```

工具窗口的全部 suite（B 期签收时的 13 个）：`TTyToolWindowGeometryTests TTyToolWindowThemeTests TTyToolWindowTests TTyToolWindowStreamingTests TTyToolWindowActionsTests TTyToolWindowBarTests TTyToolWindowImagesTests TTyToolWindowFocusTests TTyToolWindowStripTests TTyToolWindowEdgeTests TTyToolWindowReorderTests TTyToolWindowBottomTests TTyToolWindowBottomInputTests`；本期起依次再加 `TTyToolWindowManagerTests`（Task 1 起）、`TTyToolWindowManagerLiveTests`（Task 5 起）、`TTyToolWindowCrossDragTests`（Task 8 起）、`TTyToolWindowLayoutTextTests`（Task 10 起）、`TTyToolWindowLayoutApplyTests`（Task 12 起）。下文写「工具窗口全部 suite」指这一串。

## 关于判据和变异

纯函数（Task 7、10、11）给输入 / 期望表，测试照表写。**涉及时序、手势、焦点、像素、事件顺序的，只写判据和「在哪个变异下必须红」**，测试代码执行时按判据现写，写完**先做变异确认它真的在守**（[[tests-written-with-the-fix-are-green-and-wrong]]、[[plan-tests-write-the-mutation-not-the-code]]）。

变异三拍：改一行 → `git diff --stat` 确认改到了 → `lazbuild -B` → 跑 → **必须红** → 改回 → 重编重跑 → 绿。一条变异没红：先查是不是改错了地方；确实没红，说明那条测试没守住，**当场补强再继续**，并在该任务的提交信息里写一句。

探针只能是**真实状态的只读视图**，不许另开一条测试专用的计算路径。事件顺序一律用「处理器往一个字符串里追加 `名字;`」记，断言整串相等——只数次数的断言在顺序变异下是绿的。

---

### Task 0: 基线

**Files:** 无改动。

- [ ] **Step 1: 确认起点**

```bash
cd /d/Projects/ty-3.1 && git status --short && git log --oneline -1
```

Expected：工作区干净，分支 `feat/3.1`，HEAD 是本计划的提交或其后。

- [ ] **Step 2: 编译并跑工具窗口全部 suite + 全量，记下条数**

每个 suite 的 `Number of run tests` 和全量总数记进草稿，Task 14 签收时一起写进本计划末尾。B 期签收是 7485 条 0 / 0。

Expected：全部 0 errors / 0 failures。**有红就停**：C 期不在红的基线上开工。

- [ ] **Step 3: 先查三件事，结论记进草稿（后面的任务要用）**

1. 无头下 `Application.ProcessMessages` 能不能抽空 `Application.QueueAsyncCall` 排的项（写一个十行的临时测试：排一个置标志的方法、抽一次、看标志；看完删掉，不提交）。决定 Task 6 / Task 13 里哪些判据能留在无头 suite。
2. 无头下，窗体上三条栏（左、右、底）加一个 alClient 编辑区，调一次窗体的 `AdjustClientRect + AlignControls`（照 `TBarAccess.CallAlignControls`，[[headless-tests-never-run-lcl-align]]）之后，两条侧栏的 `BoundsRect` 是不是分列两边、`ClientToScreen` 换算是否一致。决定 Task 8 夹具怎么摆栏。
3. `TCustomFrame.GetChildren` 的写出顺序（非可视组件在不在控件后面），写进 Task 13 的注释。

---

### Task 1: manager 本体与栏的 `Manager` 属性

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Create: `tests/test.toolwindow.manager.pas`
- Modify: `tests/tytests.lpr`
- Modify: `tests/test.toolwindow.window.pas`

- [ ] **Step 1: 声明**

manager 的空壳换成（事件、队列等后面的任务再加）：

```pascal
  { 工具窗口栏的协调者(spec §2):可以不放。栏经 Manager 属性注册到它上面;跨侧拖动、
    MoveWindow、布局保存都要它。非可视组件,从 TTyComponent 来(带对象查看器里的 Version)。
    不支持放在数据模块里、栏分布在多个窗体上(spec §10.6)。 }
  TTyToolWindowManager = class(TTyComponent)
  private
    { 注册着的栏,注册顺序,无语义(「先注册的赢」不成立:fixup 倒序执行,spec §10.6)。 }
    FBars: array of TTyToolWindowBar;
    procedure AddBar(ABar: TTyToolWindowBar);
    procedure RemoveBar(ABar: TTyToolWindowBar);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    destructor Destroy; override;
    function IsBarUsable(ABar: TTyToolWindowBar): Boolean;
  end;
```

栏：private 加 `FManager: TTyToolWindowManager; procedure SetManager(AValue: TTyToolWindowManager);`，published 加 `property Manager: TTyToolWindowManager read FManager write SetManager;`（放在 `Images` 前面）。

- [ ] **Step 2: 实现**

```pascal
procedure TTyToolWindowManager.AddBar(ABar: TTyToolWindowBar);
var
  i: Integer;
begin
  for i := 0 to High(FBars) do
    if FBars[i] = ABar then Exit;
  SetLength(FBars, Length(FBars) + 1);
  FBars[High(FBars)] := ABar;
  { 双向:栏被释放时本 manager 收到 opRemove,本 manager 被释放时栏收到。 }
  ABar.FreeNotification(Self);
end;

procedure TTyToolWindowManager.RemoveBar(ABar: TTyToolWindowBar);
var
  i: Integer;
begin
  for i := 0 to High(FBars) do
    if FBars[i] = ABar then
    begin
      Delete(FBars, i, 1);
      Break;
    end;
end;

function TTyToolWindowManager.IsBarUsable(ABar: TTyToolWindowBar): Boolean;
var
  i: Integer;
begin
  { 现算不缓存(开工前问题 17)。与别的注册栏 Placement 相同的**每一条**都不可用,
    不按先来后到(spec §10.6)。 }
  Result := (ABar <> nil) and (ABar.Manager = Self);
  if not Result then Exit;
  for i := 0 to High(FBars) do
    if (FBars[i] <> ABar) and (FBars[i].Placement = ABar.Placement) then Exit(False);
end;
```

`Notification`：继承之后，`opRemove` 且是 `TTyToolWindowBar` → `RemoveBar`。`Destroy`：本任务只调继承（Task 6 / 8 再加撤队列、取消拖动）。

栏的 `SetManager`：

```pascal
procedure TTyToolWindowBar.SetManager(AValue: TTyToolWindowManager);
begin
  if FManager = AValue then Exit;
  { 流式 fixup 期间也会走到这里:绝不抛异常(spec §10.6)。 }
  if FManager <> nil then
  begin
    FManager.RemoveBar(Self);
    { 双向挂的通知一起拆 —— 本栏和旧 manager 之间别无其他引用(队列项在 Task 6 由 manager
      自己按 opRemove / 离开清)。旧 manager 正在释放时它自己在清表,不碰。 }
    if not (csDestroying in FManager.ComponentState) then
      FManager.RemoveFreeNotification(Self);
  end;
  FManager := AValue;
  if AValue <> nil then AValue.AddBar(Self);
end;
```

栏的 `Notification`：`opRemove` 且 `AComponent = FManager` → `FManager := nil`（不调 `RemoveBar`：manager 正在走）。

- [ ] **Step 3: 新测试单元与夹具**

`tests/test.toolwindow.manager.pas`：`TTyToolWindowManagerTests = class(TTyToolWindowBarFixture)`，uses 抄 `test.toolwindow.bottom` 那一串。夹具帮手：

- `NewManager: TTyToolWindowManager`（Owner = `FForm`）；
- `NewBarOn(APlacement; const ACaptions: array of string): TBarAccess`：Owner = `FForm`、Parent = `FForm`，**先设 Placement 再加窗口**，窗口标题长短不一、每个窗口都给 `Name`（`'W' + 标题`，布局任务要用），当前页不是第一个（地雷 12，B 期）。

挂进 `tests/tytests.lpr` 的 uses（`test.toolwindow.bottom,` 后面，用编辑工具改，别用 sed）。

- [ ] **Step 4: 写测试（判据）**

无头（`TTyToolWindowManagerTests`）：

| 判据 | 在哪个变异下必须红 |
|---|---|
| 左、右、底三条栏各设 `Manager := m`：三条都 `IsBarUsable` | `IsBarUsable` 恒答 False |
| 再加一条左栏：两条左栏都不可用，右栏、底栏仍可用 | 改成「第一个注册的可用」 |
| 把其中一条左栏改成 `twpRight`：左栏可用、两条右栏都不可用 | 结果缓存在 `SetManager` 那一刻 |
| 冲突的那条 `Manager := nil`：它 `IsBarUsable` 为假（不在 manager 上），另一条恢复可用 | `SetManager(nil)` 不 `RemoveBar` |
| 释放一条冲突栏：另一条恢复可用 | `Notification` 不 `RemoveBar` |
| 释放 manager：每条栏的 `Manager = nil`（比 nil，不比已释放的指针，B 期地雷 14） | 栏的 `Notification` 不清 `FManager` |
| `Manager` 属性 published、类型是 `TTyToolWindowManager`（`GetPropInfo`） | 写成 public |

流式（`TTyToolWindowStreamingTests`，照 `TestRoundTripKeepsWindowsOrderActiveAndSizes` 用 `WriteComponent` / `ReadComponent`）：

| 判据 | 在哪个变异下必须红 |
|---|---|
| 源窗体：manager `Manager1`、两条栏指向它；往返后目标窗体的两条栏 `Manager` 是目标窗体里的那个 manager、都可用；文本里有 `Manager = Manager1` | 属性没 published / setter 在加载中直接返回 |
| 两条同 Placement 的栏：先建 A 后建 B、先建 B 后建 A 各往返一次，两次都是「两条都不可用」 | 改成「先注册的赢」（fixup 倒序会让两种流顺序答案不同） |
| 加载中（`TBarAccess.BeginLoad`）把两条同 Placement 的栏指向同一个 manager 不抛异常 | `SetManager` 里冲突时 raise |

- [ ] **Step 5: 跑** `TTyToolWindowTests TTyToolWindowStreamingTests TTyToolWindowBarTests TTyToolWindowManagerTests`，全绿；变异逐条。

- [ ] **Step 6: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.manager.pas tests/test.toolwindow.window.pas tests/tytests.lpr && git commit -m "feat(toolwindows): bars register on a manager; same-placement bars are unusable

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 图片列表回落到 `Manager.Images`（spec §8）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.images.pas`

照 A 期留在 `EffectiveImages` 上的契约做：**只改这一处**的回落，再在 manager 换了、`Manager.Images` 换了、manager 被移除时调 `ImagesChanged`；订阅和 FreeNotification 本来就跟着 `EffectiveImages` 走。

- [ ] **Step 1: 实现**

```pascal
function TTyToolWindowBar.EffectiveImages: TCustomImageList;
begin
  { Images,为空时**读取时**回落到 Manager.Images(spec §8)。正在释放的 manager 和列表都不算
    (地雷 2:它们的 opRemove 到栏时,对方清没清引用说不准)。 }
  Result := FImages;
  if (Result = nil) and (FManager <> nil)
     and not (csDestroying in FManager.ComponentState) then
    Result := FManager.Images;
  if (Result <> nil) and (csDestroying in Result.ComponentState) then Result := nil;
end;
```

- manager 加 `FImages`、`SetImages`、published `Images`、private `NotifyImagesChanged`（对 `FBars` 里每条不在 csDestroying 的栏调 `ImagesChanged`）。`SetImages`：同值返回；旧列表**不拆** FreeNotification（地雷 1：拿不准就不拆）；写字段；新列表 `FreeNotification(Self)`；`NotifyImagesChanged`。
- manager 的 `Notification`：`opRemove` 且 `AComponent = FImages` → `FImages := nil; NotifyImagesChanged`。
- 栏：`SetManager` 末尾 `ImagesChanged`；`Notification` 里清 `FManager` 之后 `ImagesChanged`。
- 更新 `EffectiveImages` 声明处和 `Notification` 里那两段「C 期……」注释为现在的事实。

- [ ] **Step 2: 写测试（判据，`TTyToolWindowImagesTests`）**

| 判据 | 在哪个变异下必须红 |
|---|---|
| 栏没设 `Images`、manager 设了 `house / folder` 列表：窗口 `ImageName := 'folder'` 的 `ResolvedImageIndex = 1`，图标格里有图标像素（`TallyStripCell` 那一套） | `EffectiveImages` 不回落 |
| 栏自己设了列表时用自己的（同名不同序的两份列表，照 `HouseFolder` / `FolderHouse`） | 回落优先于 `FImages` |
| 只设了 `ImageIndex := 1`、栏和 manager 都没列表的窗口，之后给 **manager** 设列表：名字解析成那一格 | `SetImages` 不 `NotifyImagesChanged` |
| manager 的列表换成另一份：旧列表的变更到不了栏、新列表的到得了（`ChangeReachesBar`） | 同上；或栏的 `ImagesChanged` 不重新订阅 |
| 释放 manager 的列表：栏的 `EffectiveImages` 为 nil，列表析构不死循环（照 `TestAListBeingFreedIsNoLongerEffective`，观察者挂在 manager 的列表上） | 去掉 `csDestroying` 过滤 |
| 释放 manager（列表还活着）：列表之后的变更到不了栏 | 栏收到 manager 的 opRemove 不 `ImagesChanged` |
| 栏 `Manager := nil`：同上 | `SetManager` 末尾不 `ImagesChanged` |
| manager 正在释放、它的 opRemove 还没到栏的那一刻（`TFreeWatcher` 挂在 manager 上、登记在栏之后），栏的 `EffectiveImages` 不是 manager 的列表 | 去掉对 manager 的 `csDestroying` 判断 |

- [ ] **Step 3: 跑** `TTyToolWindowImagesTests TTyToolWindowStripTests TTyToolWindowManagerTests`，全绿；变异逐条。

- [ ] **Step 4: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.images.pas && git commit -m "feat(toolwindows): a bar without its own image list reads the manager's

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 侧 ↔ 底判据拆出来，`CanMoveWindow` / `OnCanMoveWindow`

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.manager.pas`

- [ ] **Step 1: 拆判据（开工前问题 3）**

实现段、`TTyToolWindow.MovesAcrossBarKinds` 之前：

```pascal
{ 两边都是栏、一侧一底(按 Placement,不看 Align)。不带任何豁免:运行时改 Parent 的豁免在
  MovesAcrossBarKinds 里,manager 的结构检查(设计期也要拒)只用这一句。 }
function BarKindsDiffer(AOld, ANew: TWinControl): Boolean;
begin
  Result := (AOld <> ANew) and (AOld is TTyToolWindowBar) and (ANew is TTyToolWindowBar)
    and ((TTyToolWindowBar(AOld).Placement = twpBottom)
         <> (TTyToolWindowBar(ANew).Placement = twpBottom));
end;
```

`MovesAcrossBarKinds` 改成 `BarKindsDiffer(AOld, ANew) and` 三组豁免。行为不变——B 期那组测试原样绿。

- [ ] **Step 2: 结构检查与 `CanMoveWindow`**

manager 加 `FEventDepth: Integer`、`FOnCanMoveWindow`、published `OnCanMoveWindow`，private：

```pascal
    { spec §9.9 的结构检查(不问事件)。ASource 出参是 W 此刻的栏。 }
    function StructureAllows(AWindow: TTyToolWindow; ATarget: TTyToolWindowBar;
      out ASource: TTyToolWindowBar): Boolean;
```

逐条（全部成立才 True）：`AWindow`、`ATarget` 非 nil；`ASource := AWindow.Bar` 非 nil；`ASource.Manager = Self` 且 `ATarget.Manager = Self`；manager、W、源栏、目标栏都不在 csLoading / csDestroying；`GetParentForm(ASource) = GetParentForm(ATarget)`；`not BarKindsDiffer(ASource, ATarget)`；`ASource = ATarget` 或者两条都 `IsBarUsable`。

`CanMoveWindow`：结构不过 → False；同一条栏 → True；manager 在 csDesigning → True（不问事件，spec §6.6）；否则 `allow := True`，`Inc(FEventDepth)` 包着 try/finally 调 `OnCanMoveWindow`，返回 `allow`。**没有副作用**：不取消拖动、不记默认布局、不动任何状态。

- [ ] **Step 3: 写测试（判据）**

| 判据 | 在哪个变异下必须红 |
|---|---|
| 左 → 右（同一 manager、都可用）：True；左 → 底、底 → 右：False | `StructureAllows` 不判 `BarKindsDiffer` |
| **设计期**（`NewDesignBar` 建的三条栏）左 → 底：False | 结构检查改用 `MovesAcrossBarKinds`（带豁免，设计期放行） |
| 同一条栏：True，且 `OnCanMoveWindow` 没被调 | 同栏也问事件 |
| 目标栏在别的 manager 上 / 没 manager：False | 不判目标栏的 manager |
| 窗口的栏不在本 manager 上：False | 不判源栏的 manager |
| 目标栏因 Placement 冲突不可用：False；源栏冲突时去别的栏：False；冲突源栏的同栏：True | 不判 `IsBarUsable`；或同栏也判 |
| 目标栏在另一个窗体上：False | 不比父窗体 |
| 任一在 csLoading（`BeginLoad`）：False | 不判加载中 |
| 事件把 `AAllow` 置 False：答 False；事件里收到的 `AWindow` / `ATargetBar` 正是入参 | 忽略 `AAllow` |
| 调用前后：两条栏的窗口顺序、当前页、`Collapsed`、`ExpandedSize` 全不变 | （无副作用守卫：变异「顺手 `ATarget.Collapsed := False`」要红） |
| B 期那组 `EInvalidOperation` 测试照旧全绿 | — |

- [ ] **Step 4: 跑** `TTyToolWindowBottomTests TTyToolWindowStreamingTests TTyToolWindowManagerTests`，全绿；变异逐条。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.manager.pas && git commit -m "feat(toolwindows): the manager answers whether a window may move to a bar

The side/bottom test is split out of MovesAcrossBarKinds so the manager can
refuse it at design time too; the runtime Parent exemptions stay where they were.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `MoveWindow` 的同步路径、事件延后、`OnWindowMoved`

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.manager.pas`（新加 `TTyToolWindowManagerLiveTests`，真句柄）

本任务只做同步路径：无头的窗体从不 Showing，`MoveWindow` 恒走这一支（地雷 5）。排队在 Task 6。

- [ ] **Step 1: 栏的延后事件（开工前问题 9）**

```pascal
  { MoveWindow / 直接改 Parent 期间先记下、之后按 spec §6.6 的顺序发的栏事件。 }
  TTyToolWindowBarEvent = (twbeChange, twbeExpand, twbeCollapse);
  TTyToolWindowBarEvents = set of TTyToolWindowBarEvent;
```

栏 private：`FDeferEvents: Integer; FPendingEvents: TTyToolWindowBarEvents;`、`procedure BeginDeferEvents;`（计数 +1）、`function EndDeferEvents: TTyToolWindowBarEvents;`（计数 -1，钳在 0；降到 0 时交还并清空集合，否则交还空集）、`procedure FireBarEvent(AEvent: TTyToolWindowBarEvent);`（过一遍 `EventsAllowed` 再调对应处理器）。
- `DoChange`：`FDeferEvents > 0` 时 `Include(FPendingEvents, twbeChange)` 并返回。
- `SetCollapsed` 末尾发事件那段同样处理（`twbeCollapse` / `twbeExpand`）。**同一次延后里先收起后展开**时两者都记着——由调用方按顺序发；本期没有这种路径，不另处理。

- [ ] **Step 2: 调顺序拆成两层**

- `PlaceWindow(AWindow, AIndex)`（private）：现在 `ReorderWindow` 的全部内容，返回原来的窗口序号（没挪返回 -1）。
- `ReorderWindow(AWindow, AIndex)` = `old := PlaceWindow(...)`；`old >= 0` 且 `FManager <> nil` 时 `FManager.WindowMoved(AWindow, Self, old)`。图标拖动、标签拖动、`WindowIndex` 都经过它——B 期留下的「调顺序发 `OnWindowMoved`」由此接上。`SetChildOrder` 不经过它（流式、设计器，不发）。

- [ ] **Step 3: manager 的 `WindowMoved` 与 `MoveWindow`**

manager 加 `FOnWindowMoved` 与 published `OnWindowMoved`，private：

```pascal
    { 发 OnWindowMoved(spec §6.6):运行时才发;流式加载、设计期、布局批次(Task 12 起)不发。
      包在 FEventDepth 里,处理器里再调 MoveWindow 答 False。 }
    procedure WindowMoved(AWindow: TTyToolWindow; ASource: TTyToolWindowBar; AOldIndex: Integer);
    { 真正的一次跨栏移动(spec §9.5 的顺序)。调用方已经过了结构检查和 CanMoveWindow。 }
    procedure MoveNow(AWindow: TTyToolWindow; ATarget: TTyToolWindowBar; AIndex: Integer);
```

`WindowMoved` 的门：manager 和源栏都不在 `[csDesigning, csLoading, csDestroying]` 里。

`MoveWindow`（本任务的版本；Task 6 插入排队、Task 13 插入记默认布局）：

```pascal
function TTyToolWindowManager.MoveWindow(AWindow: TTyToolWindow; ATargetBar: TTyToolWindowBar;
  AIndex: Integer): Boolean;
var
  src: TTyToolWindowBar;
begin
  Result := False;
  if FEventDepth > 0 then Exit;                       { 从事件处理里重入(spec §9.9) }
  if not StructureAllows(AWindow, ATargetBar, src) then Exit;
  if src = ATargetBar then
  begin
    { 同一条栏就是调顺序:同步,不问事件。-1 = 末尾。 }
    if AIndex < 0 then AIndex := MaxInt;
    src.ReorderWindow(AWindow, AIndex);
    Exit(True);
  end;
  if not CanMoveWindow(AWindow, ATargetBar) then Exit;
  MoveNow(AWindow, ATargetBar, AIndex);
  Result := True;
end;
```

`MoveNow` 的顺序（spec §9.5，逐句照写）：

1. `CancelDrag`（Task 8 才有：本任务先不写这一句，Task 8 Step 4 补上并配判据）。
2. 记 `form := GetParentForm(ATarget)`、`focus := form.ActiveControl`（form 可为 nil）、`oldIdx := src.IndexOfWindow(W)`。
3. `src.BeginDeferEvents; ATarget.BeginDeferEvents; src.DisableAlign; ATarget.DisableAlign;` —— 下面整段包在 try/finally 里，finally 里倒序 `EnableAlign` 两条、`EndDeferEvents` 两条（交还的集合存进局部变量）。
4. `W.Parent := ATarget`（`SetParent` 里完成：从源栏注销并回落、注册到目标栏、推 Controller、按目标栏的列表解析图标）。
5. `ATarget.PlaceWindow(W, 钳过的 AIndex)`（-1 或越界 = 末尾）。
6. `ATarget.ActivateWindow(W)`；`ATarget.Collapsed := False`（运行时；设计期 `SetCollapsed` 本来就只写字段）。
7. finally 之后：`focus <> nil` 且 `W.ContainsControl(focus)` 且 `focus.CanFocus` → `form.ActiveControl := focus`。
8. 设计期：`OwnerFormDesignerModified(ATarget)`，不发任何事件（问题 19），结束。
9. 运行时发事件，`Inc(FEventDepth)` 包着 try/finally：源栏的集合里有 `twbeChange` → `src.FireBarEvent(twbeChange)`；目标栏有 `twbeExpand` → 发；目标栏有 `twbeChange` → 发；最后 `OnWindowMoved(Self, W, src, oldIdx)`。源栏从不发 `OnCollapse`（它的 `Collapsed` 根本没动）。

注意第 9 步的 `OnWindowMoved` 直接调处理器，不经 `WindowMoved`（那个自己加一层 `FEventDepth`，这里已经在里面了；两处的门条件一致）。

- [ ] **Step 4: 写测试（判据）**

无头（`TTyToolWindowManagerTests`；左栏 `a b c`、当前页 `b`，右栏 `x`、`Collapsed = True`）：

| 判据 | 在哪个变异下必须红 |
|---|---|
| `MoveWindow(b, 右, 0)` 返回 True；`b.Bar = 右`、`右.Windows[0] = b`、`右.ActiveWindow = b`、`右.Collapsed = False`；左栏当前页回落到 `c`（原位置的下一个）；`左.Collapsed` 不变 | 第 6 步不展开；或不激活 |
| 事件顺序串 = `左.change;右.expand;右.change;moved(b,左,1);` | 去掉延后（事件当场发，串变成 `左.change;右.change;右.expand;…`） |
| `AIndex = -1` 和 `AIndex = 99`：落在末尾；`AIndex = 0`：第一个 | 不钳；或 -1 当 0 |
| 移非当前页 `a`：左栏不发 `OnChange`，当前页仍是 `b` | 源栏无条件发 change |
| 同栏 `MoveWindow(a, 左, 2)`：顺序变了、`OnChange` 没发、`OnWindowMoved` 一次且 `ASourceBar = 左`、`AOldIndex = 0`、`OnCanMoveWindow` 没被问 | 同栏走跨栏那条 |
| `OnWindowMoved` 处理器里再调 `MoveWindow(…)`：返回 False，状态不变 | 去掉 `FEventDepth` 判断 |
| `OnCanMoveWindow` 里调 `MoveWindow`：False | `CanMoveWindow` 不加 `FEventDepth` |
| 被否决：返回 False，什么都没变，没有任何事件 | 否决之后照做 |
| `b.WindowIndex := 0`、图标拖动调顺序、底栏标签拖动调顺序：各发一次 `OnWindowMoved`，`ASourceBar` 是本栏、`AOldIndex` 对；拖回原位（空操作）不发；`SetChildOrder` 不发；设计期栏 `WindowIndex` 不发 | `ReorderWindow` 不调 `WindowMoved`；或 `PlaceWindow` 没挪也报 |
| 设计期（三条设计期栏）`MoveWindow(左的窗口, 右)`：同步挪过去；`OnCanMoveWindow` / `OnWindowMoved` / 栏事件都没发 | 设计期也发事件 |

第 7 步（还焦点）和「事件在 `EnableAlign` 之后」要真句柄、窗体可见才测得出；而 Task 6 之后窗体一可见，公开的 `MoveWindow` 就排队了。所以这两条放到 Task 9，用 `MoveNow` 在 Showing 之后仍然同步的真实入口（拖放提交）测。

- [ ] **Step 5: 跑** `TTyToolWindowReorderTests TTyToolWindowBottomInputTests TTyToolWindowBarTests TTyToolWindowManagerTests`，全绿；变异逐条。

- [ ] **Step 6: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.manager.pas && git commit -m "feat(toolwindows): MoveWindow and OnWindowMoved, with bar events after the move settles

Reordering (drag, WindowIndex) reports through OnWindowMoved too.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 运行时直接改 `Parent` 到同类栏的簿记（spec §3.2）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.manager.pas`

- [ ] **Step 1: 实现**

- 窗口加 private `FQuietMove: Boolean`：`MoveWindow` 和布局应用（Task 12）自己换父时置上，`SetParent` 看见它就跳过本节的簿记。`MoveNow` 第 4 步改成 `W.FQuietMove := True; try W.Parent := ATarget; finally W.FQuietMove := False; end;`。
- `TTyToolWindow.SetParent`：跨类检查之后、继承之前算 `book`：

```pascal
  { spec §3.2:运行时同类栏之间直接改 Parent —— 照 MoveWindow 的簿记(目标栏展开、焦点还回去、
    事件按同一顺序),不问否决。MoveWindow / 布局应用自己换父时(FQuietMove)不走这里。 }
  book := (not FQuietMove) and (old <> NewParent)
    and (old is TTyToolWindowBar) and (NewParent is TTyToolWindowBar)
    and ([csLoading, csDesigning, csDestroying]
         * (ComponentState + old.ComponentState + NewParent.ComponentState) = []);
```

`book` 为真时：记下窗体 `ActiveControl`、`oldIdx`、两条栏 `BeginDeferEvents`；继承和注册（照旧）之后 `TTyToolWindowBar(NewParent).Collapsed := False`；finally 里 `EndDeferEvents` 两条；`RelayoutHeader` 之后还焦点（同 `MoveNow` 第 7 步）；再按 `源 change → 目标 expand → 目标 change` 发；两条栏的 `Manager` 相同且非 nil 时最后调 `Manager.WindowMoved(Self, 源栏, oldIdx)`。注册那一步已经把 W 设成目标栏当前页（`RegisterWindow` 的「注册即激活」，Task 12 之前 MoveWindow 也靠它）。

- [ ] **Step 2: 写测试（判据）**

| 判据 | 在哪个变异下必须红 |
|---|---|
| 没有 manager：`b.Parent := 右`（右栏收起着）→ `右.ActiveWindow = b`、`右.Collapsed = False`；左栏回落；事件串 `左.change;右.expand;右.change;` | 去掉 `Collapsed := False`；或去掉延后 |
| 两条栏同一 manager：多一次 `OnWindowMoved(b, 左, oldIdx)`，而且 `OnCanMoveWindow` 没被问 | 不发；或问了否决 |
| 两条栏在不同 manager：没有 `OnWindowMoved` | 只判一边有 manager |
| 目标栏因冲突不可用：照样挪过去、展开（spec：冲突不冲突都照做） | 簿记里判 `IsBarUsable` |
| `MoveWindow(b, 右)`：`OnWindowMoved` **恰好一次** | `MoveNow` 不置 `FQuietMove`（簿记再发一次） |
| 设计期、加载中：目标栏的 `Collapsed` 不被改 | `book` 不看豁免 |
| 孤儿进栏、出栏到 nil：不走簿记（事件串里没有 expand） | `book` 不要求两边都是栏 |

真句柄：本任务新建 suite `TTyToolWindowManagerLiveTests`（和 `TTyToolWindowManagerTests` 同一个单元；夹具照 `TTyToolWindowFocusTests`：**本单元自带** widgetset 惰性初始化开关、窗体摆在 (-4000, -4000) 再 `Visible := True` + `HandleNeeded`、`Application.OnException` 陷阱）。直接改 `Parent` 永远同步，窗体可见也一样：

| 判据 | 在哪个变异下必须红 |
|---|---|
| 焦点在 `b` 正文里的编辑框，`b.Parent := 右` 之后 `ActiveControl` 还是它 | 去掉还焦点那一步 |
| 右栏的 `OnChange` 处理器里读 `b.BoundsRect`：等于右栏内容区（事件在对齐之后） | 事件挪进 `SetParent` 的继承之前 |

- [ ] **Step 3: 跑** `TTyToolWindowBarTests TTyToolWindowBottomTests TTyToolWindowManagerTests TTyToolWindowManagerLiveTests`，全绿；变异逐条。

- [ ] **Step 4: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.manager.pas && git commit -m "feat(toolwindows): assigning Parent to a same-kind bar books the move like MoveWindow

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `MoveWindow` 的队列（spec §9.9）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.manager.pas`

- [ ] **Step 1: 队列**

```pascal
  { manager 自己的异步队列里的一项(spec §9.9 / §10.5)。 }
  TTyToolWindowQueuedKind = (twqMove, twqIndex);
  TTyToolWindowQueued = record
    Kind: TTyToolWindowQueuedKind;
    Window: TTyToolWindow;
    Target: TTyToolWindowBar;    { twqMove }
    Index: Integer;
    Requeued: Boolean;           { 捕获还在 W 里、已经再排过一次(开工前问题 13) }
  end;
```

manager private：`FQueue: array of TTyToolWindowQueued; FQueuePosted: Boolean;`、`Enqueue(const AItem)`（追加；W 和目标栏各 `FreeNotification(Self)`；没发过就 `Application.QueueAsyncCall(@RunQueue, 0)` 并置 `FQueuePosted`）、`HasQueued(AWindow): Boolean`、`PurgeQueue(AComponent)`（删掉 `Window` 或 `Target` 是它的项）、`RunQueue(Data: PtrInt)`、`MustQueue(AWindow): Boolean`。

- `MustQueue` = 运行时（manager 不在 csDesigning）且 `GetParentForm(W)` 非 nil 且 `Showing`。
- `MoveWindow` 改成：重入、结构检查照旧；**`HasQueued(W)` 为真 → 入队（同栏也入队）、返回 True**；同栏且不 `MustQueue` → 照旧同步；跨栏先问 `CanMoveWindow`（False 就返回 False），然后 `MustQueue` → 入队返回 True，否则 `MoveNow`。同栏但 `MustQueue`：照 spec，同栏**同步**（不重建句柄）——只有 W 已有排队项时才入队。
- 拖放提交（Task 9）走 `MoveNow` 的同步入口，不经 `MustQueue`。
- `TTyToolWindow.SetWindowIndex`：`b.Manager <> nil` 且 `b.Manager.HasQueued(Self)` → 入一项 `twqIndex`；否则照旧。
- `RunQueue`：`FQueuePosted := False`；取走整个队列（`items := FQueue; FQueue := nil`），按序执行：
  - `twqMove`：`GetCaptureControl` 在 W 里（`= W` 或 `W.ContainsControl`）且没再排过 → 置 `Requeued` 后 `Enqueue` 回去、跳过；否则重做 `StructureAllows` 与 `CanMoveWindow`，都过才 `MoveNow`，否则**静默丢弃**（不发事件）。
  - `twqIndex`：`W.Bar <> nil` 时 `W.Bar.ReorderWindow(W, Index)`。
- manager 的 `Notification`：`opRemove` 时 `PurgeQueue(AComponent)`（窗口、栏都可能在队列里）；`RemoveBar` 时同样 `PurgeQueue(ABar)`（离开 manager 的栏不再是目标）。
- manager 析构第一句：`if (Application <> nil) and not (AppDoNotCallAsyncQueue in Application.Flags) then Application.RemoveAsyncCalls(Self);`（问题 5）；`FQueue := nil`。
- **栏析构里删掉** `Application.RemoveAsyncCalls(Self)` 和它上面那两行注释；`Application.RemoveAllHandlersOfObject(Self)` 保留。

- [ ] **Step 2: 写测试（判据）**

真句柄（`TTyToolWindowManagerLiveTests`；窗体 `Visible := True` + `HandleNeeded`，`Showing` 为真）：

| 判据 | 在哪个变异下必须红 |
|---|---|
| `MoveWindow(b, 右)` 返回 True，**返回那一刻** `b.Bar = 左`；抽消息之后 `b.Bar = 右`、事件照 Task 4 的顺序发 | `MustQueue` 恒 False（同步） |
| 窗体不可见时同样的调用：同步生效 | `MustQueue` 不看 `Showing` |
| `b` 操作区里放一个 `TTyButton`，它的 `OnClick` 里调 `MoveWindow(b, 右)`，用真实消息点它（`Perform(LM_LBUTTONDOWN)` / `LM_LBUTTONUP` 或照 `test.focus.tabstop` 的点击帮手）：处理器返回前后按钮的 `Handle` 值不变、没有异常被陷阱接住；抽消息之后 `b` 在右栏 | 同上 |
| `MoveWindow(b, 右, 0)` 排着时 `b.WindowIndex := 1`：抽消息之后 `b` 在右栏、`WindowIndex = 1` | `SetWindowIndex` 不看队列（当场在左栏调、之后被移动覆盖） |
| 排着时同栏 `MoveWindow(b, 左, 0)`：也进队列，按调用顺序执行 | 有排队项时同栏仍同步 |
| 排着时释放右栏：抽消息不 AV，`b` 还在左栏 | 不 `PurgeQueue` |
| 排着时释放 `b`：抽消息不 AV | 同上（窗口那一支） |
| 排着时释放 manager：抽消息不 AV（陷阱里没有异常） | 析构不 `RemoveAsyncCalls` |
| 排队时 `OnCanMoveWindow` 放行、执行时否决：静默丢弃，没有 `OnWindowMoved`、没有栏事件 | 执行时不再问 |
| 执行时捕获在 `b` 里（`SetCaptureControl(b 里的按钮)`）：抽一次消息后还在左栏；放掉捕获再抽：到了右栏 | 不再排 |
| 捕获一直不放：第二轮照做（不无限再排） | 再排不设上限 |

- [ ] **Step 3: 结构验收**（栏析构不再调 `RemoveAsyncCalls`，这一条不写成测试）

```bash
cd /d/Projects/ty-3.1 && grep -n "RemoveAsyncCalls\|QueueAsyncCall" source/tyControls.ToolWindows.pas
```

Expected：`QueueAsyncCall` 只在 `Enqueue`（Task 13 起还有布局那两处）；`RemoveAsyncCalls` 只在 manager 析构。

- [ ] **Step 4: 跑** `TTyToolWindowTests TTyToolWindowBarTests TTyToolWindowManagerTests TTyToolWindowManagerLiveTests`，全绿；变异逐条。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.manager.pas && git commit -m "feat(toolwindows): cross-bar moves after the form shows are queued on the manager

The bar's destructor no longer calls RemoveAsyncCalls: the queue belongs to the
manager, and RemoveAsyncCalls only ever matched the bar's own methods.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 跨栏命中的纯函数（spec §9.4）

**Files:**
- Modify: `source/tyControls.ToolWindows.Layout.pas`
- Modify: `tests/test.toolwindow.geometry.pas`

- [ ] **Step 1: 写失败的测试（照下表）**

声明（interface 段，`TyToolWindowSlotAt` 后面）：

```pascal
  { 跨栏拖动的一个候选(spec §9.4),manager 每次移动现建。坐标一律**屏幕坐标**。 }
  TTyToolWindowDropProbe = record
    { 栏的 ClientRect 与每一级祖先 ClientRect 的交集。 }
    Visible: TRect;
    { 嵌在这条栏里面的别的栏:落在里面的点不算这个候选。 }
    Holes: array of TRect;
    { 图标条去掉界线的那一段。 }
    Cells: TRect;
    { 已排布的图标,ItemIndex 是窗口序号。 }
    Slots: TTyToolWindowSlots;
    Count: Integer;
    IsSource: Boolean;
    { 另一侧栏:CanMoveWindow 的答案。源栏忽略。 }
    Allowed: Boolean;
  end;
  TTyToolWindowDropProbes = array of TTyToolWindowDropProbe;

{ P 落在哪个候选上,-1 = 没有目标。按数组顺序找第一个 Visible 含 P(且不在 Holes 里)的候选:
  在它的 Cells 里 → 按图标中点找空隙;源栏 Cells 之外 → 没有目标(源栏自己的内容区);
  另一侧栏 Cells 之外 → 「最后一个已排布图标之后」那个空隙;另一侧栏被否决 → 没有目标。
  ASlot 是窗口序号的槽位,-1 时无意义。调用方把源栏放在第一个。 }
function TyToolWindowDropAt(const AProbes: array of TTyToolWindowDropProbe; const P: TPoint;
  out ASlot: Integer): Integer;
```

公共输入：源栏 `S`：`Visible (0,0,200,400)`、`Cells (0,0,36,400)`、`Slots [0:(0,0,36,36), 1:(0,36,36,72)]`、`Count 2`、`IsSource`。另一侧栏 `T`：`Visible (600,0,800,400)`、`Cells (764,0,800,400)`、`Slots [0:(764,0,800,36)]`、`Count 1`、`Allowed True`。探测数组 `[S, T]`。

| # | 变化 | P | 期望（候选, 槽位） |
|---|---|---|---|
| D1 | — | (18,10) | (0, 0) |
| D2 | — | (18,60) | (0, 2)（第二个图标中点 54 之后） |
| D3 | — | (18,300) | (0, 2)（条尾空白 = 最后一个之后） |
| D4 | — | (100,100) | (-1)（源栏内容区） |
| D5 | — | (780,10) | (1, 0) |
| D6 | — | (780,300) | (1, 1) |
| D7 | — | (650,200) | (1, 1)（另一侧栏的内容区 = 末尾空隙） |
| D8 | `T.Allowed = False` | (780,10)、(650,200) | 都是 (-1) |
| D9 | — | (400,200) | (-1)（编辑区） |
| D10 | `T.Holes = [(640,100,700,150)]` | (660,120) | (-1)；(660,200) 仍是 (1, 1) |
| D11 | `T.Count = 3`，`T.Slots = [2:(764,0,800,36)]`（前两个被溢出收起，当前页被强制留下） | (780,10) → (1, 2)；(650,200) → (1, 3) | 映射到窗口序号，不是排布序号 |
| D12 | `T.Count = 0`，`T.Slots = []` | (650,200) | (1, 0) |
| D13 | `T.Visible = (600,0,700,400)`（祖先裁掉了图标条） | (780,10) | (-1) |
| D14 | 空数组 | 任意 | (-1) |
| D15 | `S.Holes = [(40,100,200,200)]`，再加第三个候选 `N`（`Visible (40,100,200,200)`、`Cells (40,100,76,200)`、`Slots []`、`Count 0`、`Allowed True`），数组 `[S, T, N]` | (120,150) | (2, 0)（嵌在源栏里的栏能当目标） |

- [ ] **Step 2: 跑，确认编译失败**（`TyToolWindowDropAt` 未声明）。

- [ ] **Step 3: 实现**

```pascal
function TyToolWindowDropAt(const AProbes: array of TTyToolWindowDropProbe; const P: TPoint;
  out ASlot: Integer): Integer;
var
  i, j: Integer;
  inHole: Boolean;
begin
  ASlot := -1;
  for i := 0 to High(AProbes) do
  begin
    if not PtInRect(AProbes[i].Visible, P) then Continue;
    inHole := False;
    for j := 0 to High(AProbes[i].Holes) do
      if PtInRect(AProbes[i].Holes[j], P) then
      begin
        inHole := True;
        Break;
      end;
    if inHole then Continue;
    if PtInRect(AProbes[i].Cells, P) then
      ASlot := TyToolWindowSlotAt(AProbes[i].Slots, P.X, P.Y, True, AProbes[i].Count)
    else if AProbes[i].IsSource then
      Exit(-1)                                 { 源栏自己的内容区:没有目标 }
    else
      { 「最后一个已排布图标之后」:同一个函数,指针放到条尾之外。 }
      ASlot := TyToolWindowSlotAt(AProbes[i].Slots, P.X, High(Integer), True, AProbes[i].Count);
    if not AProbes[i].IsSource and not AProbes[i].Allowed then
    begin
      ASlot := -1;
      Exit(-1);
    end;
    Exit(i);
  end;
  Result := -1;
end;
```

- [ ] **Step 4: 跑 `TTyToolWindowGeometryTests`，全绿**

- [ ] **Step 5: 变异**

| 变异 | 必须红 |
|---|---|
| 不查 `Holes` | D10 或 D15 |
| 源栏 Cells 之外 `Continue`（落到后面的候选） | D4（配合 D15 之外的一组让它有后续候选可落） |
| 否决时仍返回候选 | D8 |
| 末尾空隙写成 `Count` | D11 |
| 不查 `Visible`、只查 `Cells` | D13 |

- [ ] **Step 6: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.Layout.pas tests/test.toolwindow.geometry.pas && git commit -m "feat(toolwindows): pure hit test for dropping a window on another side bar

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 跨侧拖动——目标栏、正在拖、探测与反馈

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Create: `tests/test.toolwindow.crossdrag.pas`
- Modify: `tests/tytests.lpr`

- [ ] **Step 1: 引擎的目标栏和 manager 的「正在拖」**

引擎加：

```pascal
    { 跨栏拖动此刻的目标栏(另一侧栏);nil = 目标是源栏自己或者没有目标。反馈画在它身上。 }
    FTarget: TTyToolWindowBar;
    { 这一次手势里问过的目标栏和答案(spec §9.4:每个目标栏每次手势只问一次)。 }
    FAllowed: array of record Bar: TTyToolWindowBar; Allowed: Boolean; end;
  public
    { 换目标栏:旧的清反馈、新的画 ASlot。 }
    procedure SetTarget(ABar: TTyToolWindowBar; ASlot: Integer);
    function AllowedFor(ABar: TTyToolWindowBar): Boolean;
    property Target: TTyToolWindowBar read FTarget;
```

- `SetTarget`：`FTarget <> ABar` 时旧目标 `SetForeignDrop(-1)`；`FTarget := ABar`；非 nil 时 `ABar.SetForeignDrop(ASlot)`。
- `AllowedFor`：在 `FAllowed` 里找；没有就问 `FBar.Manager.CanMoveWindow(FWindow, ABar)` 并记下。
- `ReleaseResources` 末尾加：`SetTarget(nil, -1)`；`FAllowed := nil`；`FBar.Manager <> nil` 且它的 `FDragSource = FBar` 时清成 nil。
- `BeginDragging` 末尾：`FBar.Manager <> nil` 时 `FBar.Manager.FDragSource := FBar`。
- 析构不碰 manager（它在栏析构之后才放）。

manager 加 `FDragSource: TTyToolWindowBar`；`IsDragging` = `FDragSource <> nil`；`CancelDrag` = `FDragSource <> nil` 时 `FDragSource.ResetGesture(twgeCancel)`；private `BarChanged(ABar)` = `ABar` 是 `FDragSource` 或 `FDragSource.FGesture.Target` 时 `CancelDrag`。

- [ ] **Step 2: 目标栏的外来落点（开工前问题 11）**

栏加 `FForeignDrop: Boolean`、private `SetForeignDrop(ASlot: Integer)`（`ASlot < 0` 时 `FForeignDrop := False`、`FDropSlot := -1`；否则两者都写；变了才 `Invalidate`，csDestroying 时只写字段），探针 `property ForeignDropForTest: Boolean read FForeignDrop;`。`DropLineY` 开头改成：

```pascal
  if FForeignDrop then
  begin
    if FDropSlot < 0 then Exit;
  end
  else if (FGesture.State <> twgsDragging) or (FDropSlot < 0) or IsNoOpSlot(FDropSlot) then Exit;
```

画线那段不动（同一个类型键、同一粗细、画进 BGRA 层）。**空栏**（没有已排布图标）也要有线：`DropLineY` 两个循环都找不到时，外来落点答图标条 `Cells.Top`。

- [ ] **Step 3: 探测与光标**

manager private：

```pascal
    { spec §9.4:源栏 ASource 上拖着 AWindow,屏幕点 AScreen 落在哪条栏的哪个槽位。
      答源栏自己、另一侧栏,或 nil(没有目标)。每次现建探测矩形。 }
    function DropTargetAt(ASource: TTyToolWindowBar; AWindow: TTyToolWindow;
      const AScreen: TPoint; out ASlot: Integer): TTyToolWindowBar;
```

- 源栏的探测：`Visible` = 源栏客户区与每一级祖先客户区的屏幕交集；`Holes` = 源栏里嵌着的其他栏（递归子控件里的 `TTyToolWindowBar`，看得见的）的屏幕矩形；`Cells` / `Slots` = `BarLayout` 换屏幕坐标；`IsSource`。
- 源栏 `IsBarUsable` 时再加候选：`FBars` 里每一条 ≠ 源栏、`Placement <> twpBottom`、`IsBarUsable`、`IsVisible`、`IsEnabled`（开工前问题 1）、不在 csDestroying、`GetParentForm` 与源栏相同的栏，`Allowed := ASource.FGesture.AllowedFor(那条栏)`。
- 源栏有句柄时先问 `FindControlAtPosition(AScreen, True)`：非 nil 且 `GetParentForm(它) <> GetParentForm(ASource)` → 直接没有目标（非模态浮动窗体盖在上面）。
- 调 `TyToolWindowDropAt`，把下标换回栏。

栏的 `DragTo(X, Y)` 改成：

```pascal
  { 有 manager 的侧栏:问 manager(spec §9.4);否则照 A 期只看自己的图标条。 }
  if (FManager <> nil) and (FPlacement <> twpBottom) then
  begin
    tgt := FManager.DropTargetAt(Self, FGesture.Window, ClientToScreen(Point(X, Y)), slot);
    if tgt = Self then
    begin
      FGesture.SetTarget(nil, -1);
      SetDropSlot(slot);
    end
    else
    begin
      SetDropSlot(-1);
      FGesture.SetTarget(tgt, slot);     { tgt 为 nil 时只清旧目标 }
    end;
    if tgt = nil then FGesture.SetCursor(crNoDrop) else FGesture.SetCursor(crDrag);
    Exit;
  end;
```

- [ ] **Step 4: 取消的各条路（spec §9.7）**

- `MoveNow` 第 1 句补上 `CancelDrag`。
- 栏 `SetCollapsed`、`SetPlacement`、`SetManager`（换之前）：`FManager <> nil` 时 `FManager.BarChanged(Self)`（源栏自己的 `ResetGesture` 照旧）。
- manager `Notification` / `RemoveBar`：被移除的栏是源栏或目标栏 → `CancelDrag`（先于 `PurgeQueue`）。manager 析构：`CancelDrag` 在撤队列之后。
- 栏 `Notification` 里 manager 被移除：`ResetGesture(twgeCancel)`（spec §9.7「manager 的 opRemove」）。
- 栏 `MouseMove` 开头：`FManager <> nil`、`FManager.FDragSource <> nil`、`FManager.FDragSource <> Self`、`not (ssLeft in Shift)` → `FManager.CancelDrag`（spec §9.7「任何注册栏看到没有 ssLeft 的移动」）。
- 目标栏被释放：它 csDestroying 时引擎 `SetTarget(nil)` 只写它的字段（`SetForeignDrop` 在 csDestroying 下不重画），不 AV。

- [ ] **Step 5: 夹具**

`tests/test.toolwindow.crossdrag.pas`：`TTyToolWindowCrossDragTests = class(TTyToolWindowBarFixture)`。窗体 800×400：左栏（`FBar`，窗口 `a b c`，当前页 `b`）、右栏（窗口 `x`）、底栏（窗口 `p q`）、一个 alClient 的 `TTyPanel` 当编辑区，都 `Manager := m`。按 Task 0 Step 3 第 2 条查到的办法让对齐引擎摆一遍，**断言摆好了**（左栏在左、右栏在右，不然后面每条都假绿）。帮手：`ScreenOf(ABar, APoint)`、`ToSourceClient(AScreen)`（换回左栏客户区给 `CallMouseMove`）、`StartDrag(AIndex)`（按住左栏第 AIndex 格往下拖过阈值）。挂进 `tests/tytests.lpr`。

- [ ] **Step 6: 写测试（判据）**

| 判据 | 在哪个变异下必须红 |
|---|---|
| 从左栏拖到右栏图标条第一格上半：右栏 `ForeignDropForTest`、`DropSlotForTest = 0`；左栏 `DropSlotForTest = -1`；`m.IsDragging` | `DragTo` 不问 manager |
| 拖到右栏内容区：右栏槽位 = 1（末尾空隙） | 内容区当没有目标 |
| 拖到编辑区、底栏：两条侧栏都没有落点；光标 `crNoDrop`（探针读引擎的光标：`TBarAccess` 已记 `CursorWrites`，另加只读 `DragCursorForTest` 读引擎 `FCursor`） | 编辑区返回右栏 |
| 在右栏上来回移动三次：`OnCanMoveWindow` 只被问一次 | `AllowedFor` 不缓存 |
| `OnCanMoveWindow` 否决：右栏没有落点、光标 `crNoDrop` | 不看 `Allowed` |
| 右栏禁用（`Enabled := False`）：没有落点（问题 1） | 候选不判 `IsEnabled` |
| 右栏 `Visible := False`、或 manager 下再加一条右栏（冲突）：没有落点；左栏内调顺序照常有落点 | 不判可见 / 可用 |
| 左栏自己冲突（再加一条左栏）：拖到右栏没有落点 | 源栏冲突时仍加候选 |
| 右栏在另一个窗体上（同一 manager）：没有落点 | 不比窗体 |
| 从右栏上方移回左栏图标条：右栏 `ForeignDropForTest` 为假、槽位 -1 | `SetTarget` 不清旧目标 |
| 右栏一个窗口里嵌一条（没注册的）侧栏，指针落在它上面：没有落点 | 不建 `Holes` |
| 像素：哨兵底色下 `RenderTo` 右栏，落点那一行有插入线色；左栏图标条里没有；空的右栏（先把 `x` 挪走）也有线 | `DropLineY` 不认外来落点；空栏答 -1 |
| Esc（在无关控件上 `Perform(CN_KEYDOWN, VK_ESCAPE)`）：`m.IsDragging` 为假，右栏的落点清掉 | `ReleaseResources` 不 `SetTarget(nil)` |
| `m.CancelDrag`：同上，引擎记成 Cancelled（之后的松开什么都不做） | `CancelDrag` 不走 `ResetGesture(twgeCancel)` |
| 拖到右栏上时 `右.Collapsed := True`、`右.Placement := twpLeft`、`右.Manager := nil`：各自取消 | `BarChanged` 不认目标栏 |
| 拖到右栏上时释放右栏：不 AV，左栏引擎回到 Cancelled / Idle，`m.IsDragging` 为假 | manager 的 opRemove 不取消 |
| 拖动中释放 manager：左栏引擎取消，之后在右栏位置松开什么都不发生 | 栏收到 manager 的 opRemove 不取消 |
| 右栏收到一次不带 ssLeft 的 `MouseMove`：取消 | 去掉 Step 4 最后一条 |
| 没有 manager 的侧栏：拖到别的栏上照 A 期答没有目标（原 `TTyToolWindowReorderTests` 全绿） | — |

- [ ] **Step 7: 跑** `TTyToolWindowReorderTests TTyToolWindowStripTests TTyToolWindowBottomInputTests TTyToolWindowManagerTests TTyToolWindowCrossDragTests`，全绿；变异逐条。

- [ ] **Step 8: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.crossdrag.pas tests/tytests.lpr && git commit -m "feat(toolwindows): dragging an icon over another side bar shows where it will land

The gesture engine gains a target bar; the manager tracks the drag so any bar,
the manager, or a change to either bar can cancel it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 跨侧拖动——提交

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.crossdrag.pas`、`tests/test.toolwindow.manager.pas`

- [ ] **Step 1: 实现**

- manager private `MoveFromDrop(AWindow, ATarget, ASlot): Boolean`：`StructureAllows` 和 `CanMoveWindow`（spec §6.6：放下时再问一次）都过才 `MoveNow`，**不经 `MustQueue`**（spec §9.9：从拖放提交调用是同步的）；`HasQueued(W)` 为真时也照做——拖动开始后 W 不可能再被排队以外的路挪走，队列里的项执行时会重新检查。
- 栏的 `MouseUp`：`FGesture.State = twgsDragging` 且有 manager 的侧栏时，在 `Release` 之前算 `tgt := FManager.DropTargetAt(...)`；`tgt = Self` 走原来的 `commit` 判断；`tgt` 是另一条栏时记下 `cross := True`、`slot`。`Release` 之后 `twrDrop` 分支：先 `UpdateHoverAt`，然后同栏照旧 `ReorderWindow`，跨栏**最后一句** `FManager.MoveFromDrop(rel.Window, tgt, slot)`，之后不再碰 `Self`（spec §9.2）。
- `FinalIndex`：跨栏 = 槽位本身（spec §9.4）。

- [ ] **Step 2: 写测试（判据）**

无头（`TTyToolWindowCrossDragTests`）：

| 判据 | 在哪个变异下必须红 |
|---|---|
| 把 `b`（左栏当前页）拖到右栏图标条第一格上半松开：`b` 在右栏第 0 个、是右栏当前页、右栏展开；左栏当前页回落到 `c`；事件串 `左.change;右.expand;右.change;moved(b,左,1);` | 跨栏 `twrDrop` 不提交 |
| 拖到右栏内容区松开：`b` 在右栏末尾 | 内容区不提交 |
| 右栏收起着：放下之后展开到它的 `ExpandedSize`（`右.Width` = 推导值） | — （Task 4 已守；跑一遍拖放版确认） |
| 拖到编辑区松开：什么都没变，没有任何事件，也不是点击（`Collapsed`、当前页不变） | 没有目标时当成点击 |
| 悬停时放行、松开时否决（处理器里数次数，第二次起答 False）：不挪 | 放下时不再问 |
| Esc 之后在右栏上松开：不挪 | 取消后照提交 |
| 把左栏最后一个窗口也拖走：左栏 `Collapsed` 仍为 False、`Width` = 图标条 + chrome（只剩图标条）；再从右栏把一个窗口拖回左栏的图标条：成功 | 源栏拖空时写 `Collapsed := True`；或空栏不是目标 |
| 放下之后栏的 `OnClick` 没触发 | 吞点击标志被跨栏分支跳过 |
| 只设了 `ImageIndex`、没设 `ImageName` 的窗口，两条栏都用 `Manager.Images`：拖过去之后右栏那一格的 `ResolvedImageIndex` 不变 | — （守 spec §8 的文档说法成立） |

真句柄（`TTyToolWindowManagerLiveTests`，窗体 Showing）：

| 判据 | 在哪个变异下必须红 |
|---|---|
| Showing 之后拖放：**松开那一刻**窗口已经在右栏（不排队） | `MoveFromDrop` 改调公开的 `MoveWindow`（Showing 时排队） |
| 焦点在 `b` 的编辑框里，拖放到右栏：`ActiveControl` 还是它（Task 4 留过来的） | 去掉 `MoveNow` 第 7 步 |
| 右栏 `OnChange` 处理器里读 `b.BoundsRect`：等于右栏内容区（Task 4 留过来的） | `MoveNow` 的事件挪到 `EnableAlign` 之前 |

- [ ] **Step 3: 跑** `TTyToolWindowReorderTests TTyToolWindowManagerTests TTyToolWindowManagerLiveTests TTyToolWindowCrossDragTests`，全绿；变异逐条。

- [ ] **Step 4: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/ && git commit -m "feat(toolwindows): dropping an icon on the other side bar moves the window there

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: 布局串的解析与格式化（新单元，spec §10.2）

**Files:**
- Create: `source/tyControls.ToolWindows.LayoutText.pas`
- Modify: `tycontrols.lpk`
- Create: `tests/test.toolwindow.layouttext.pas`
- Modify: `tests/tytests.lpr`

- [ ] **Step 1: 新单元骨架（interface）**

```pascal
unit tyControls.ToolWindows.LayoutText;
{$mode objfpc}{$H+}

{ 工具窗口布局串(spec §10.2 / §10.3):解析、格式化、版本漂移计划。纯函数,无控件,可无头测。
  格式照 TTyStringGrid.SaveLayoutToString 的约定(一行、| 分段、key=value),但解析更严:
  普通字符切分(不用 TStringList.DelimitedText,它仍然特殊处理引号)、必须以 end 收尾、
  数字只认 1-5 位纯数字。 }

interface

uses
  SysUtils;

const
  TyToolLayoutTag = 'TYTOOLLAYOUT/1';

type
  TTyToolLayoutSide = (tlsLeft, tlsRight, tlsBottom);

  TTyToolLayoutGroup = record
    Present: Boolean;         { p、pWins、pActive 三个 key 都在 }
    Size: Integer;            { 0..99999 }
    Collapsed: Boolean;
    Names: TStringArray;      { 按顺序 }
    Active: string;           { '' 或 Names 里的一个(拼写取 Names 里的那个) }
  end;

  TTyToolLayoutDoc = array[TTyToolLayoutSide] of TTyToolLayoutGroup;

{ 整串合法才答 True 并填 ADoc;不合法答 False,ADoc 全是零值(Present 都为假)。 }
function TyToolLayoutParse(const AText: string; out ADoc: TTyToolLayoutDoc): Boolean;
{ 按 left、right、bottom 的顺序只写 Present 的组。调用方保证名字合法、不重名。 }
function TyToolLayoutFormat(const ADoc: TTyToolLayoutDoc): string;
```

key 名：`left` / `leftWins` / `leftActive`，`right…`，`bottom…`；key **区分大小写**（`Left=` 是未知 key）。

- [ ] **Step 2: 写失败的测试（照下表）**

好串 `G`：

```
TYTOOLLAYOUT/1|left=240,0|leftWins=Explorer,Search|leftActive=Explorer|right=300,1|rightWins=Outline|rightActive=Outline|bottom=200,0|bottomWins=Problems,Output|bottomActive=Output|end
```

接受（`TyToolLayoutParse` 答 True，`ADoc` 如表）：

| # | 输入 | 期望 |
|---|---|---|
| A1 | `G` | 三组都 Present；left `(240, False, [Explorer, Search], Explorer)`；right `(300, True, [Outline], Outline)`；bottom `(200, False, [Problems, Output], Output)` |
| A2 | `G` 去掉 right 的三段 | right 不 Present，其余同 A1 |
| A3 | `TYTOOLLAYOUT/1|end` | 三组都不 Present |
| A4 | `G` 在 `end` 前插 `future=a,b` | 同 A1（未知 key 忽略） |
| A5 | `TYTOOLLAYOUT/1|left=240,0|leftWins=|leftActive=|end` | left Present、`Names = []`、`Active = ''` |
| A6 | `G` 的 `leftActive=`（空） | left `Active = ''` |
| A7 | `G` 的 `leftWins=Frame1.Explorer,Search`、`leftActive=Search` | 接受（带点的名字留口子，spec §10.2） |
| A8 | `left=0,0`、`left=99999,1`、`left=00240,0` | 尺寸 0 / 99999 / 240 |
| A9 | `G` 的 `leftActive=explorer` | 接受，`Active = 'Explorer'`（取列表里的拼写） |
| A10 | `G` 的三组倒过来写（bottom 在前） | 同 A1 |

拒绝（每条和 `G` 只差一个缺陷，答 False 且 `ADoc` 三组都不 Present）：

| # | 缺陷 |
|---|---|
| R1 | 标签 `TYTOOLLAYOUT/2` |
| R2 | 标签小写 `tytoollayout/1` |
| R3 | 去掉 `|end` |
| R4 | `end` 不在最后：`…|leftActive=Explorer|end|right=300,1|…`（去掉末尾的 `|end`） |
| R5 | `…|end|end` |
| R6 | 缺 `rightActive=Outline`（组不完整） |
| R7 | `left= 240,0` |
| R8 | `left=$F0,0` |
| R9 | `left=240,2` |
| R10 | `left=240,0,1` |
| R11 | `left=100000,0` |
| R12 | `left=,0` |
| R13 | `left=-1,0`、`left=+240,0`（两条） |
| R14 | `leftActive=Outline`（不在自己的列表里） |
| R15 | `rightWins=explorer`、`rightActive=explorer`（和 left 的 Explorer 只差大小写） |
| R16 | 多一段 `left=240,0`（重复 key） |
| R17 | `leftWins=Explorer,,Search` |
| R18 | `leftWins=Explorer,`（末尾空项） |
| R19 | `left=240,0||leftWins=…`（空段） |
| R20 | 多一段 `=5`（空 key） |
| R21 | 多一段 `foo`（没有 `=`） |
| R22 | `leftWins=Explorer,1abc`、`leftWins=Exp lorer`（两条，非法标识符） |
| R23 | `Left=240,0`（key 区分大小写 → left 组不完整） |
| R24 | 空串 |

格式化：

| # | 输入 | 期望输出 |
|---|---|---|
| F1 | A1 的 doc | 逐字等于 `G` |
| F2 | 只有 left Present | `TYTOOLLAYOUT/1|left=240,0|leftWins=Explorer,Search|leftActive=Explorer|end` |
| F3 | A5 的 doc | `TYTOOLLAYOUT/1|left=240,0|leftWins=|leftActive=|end` |
| F4 | 全不 Present | `TYTOOLLAYOUT/1|end` |
| F5 | F1–F4 每一个 | `TyToolLayoutParse(TyToolLayoutFormat(d))` 答 True，解析结果逐字段等于 `d` |

截断（纯函数层先守一遍）：对 `G` 的每个前缀（长度 1..Length-1）`TyToolLayoutParse` 都答 False。

- [ ] **Step 3: 跑，确认编译失败**（单元不存在）。

- [ ] **Step 4: 实现**

解析按下面的顺序，任何一步不过就 `ADoc := Default(TTyToolLayoutDoc)` 并答 False：

1. 按 `|` 手工切（`Pos` / `Copy` 循环，不用 `TStringList`）。段数 ≥ 2；第 0 段 `= TyToolLayoutTag`；最后一段 `= 'end'`；中间任何一段都不是 `'end'`。
2. 中间每段：非空；含 `=`，第一个 `=` 前的 key 非空；key 在已见集合里 → 拒绝（重复）。已知 key 记值，未知的忽略。
3. 每组：三个 key 全有 / 全无，否则拒绝。
4. `p` 的值按 `,` 切成正好两段；尺寸 1-5 个 `'0'..'9'`，`StrToInt`；标志正好是 `'0'` 或 `'1'`。
5. `pWins`：空串 = 空列表；否则按 `,` 切，每项非空且 `IsValidIdent(项, True, True)`（FPC 3.2.2 `sysstrh.inc:114` 有这个签名）。
6. 全部组的名字两两 `CompareText` 不同。
7. `pActive`：空，或者 `CompareText` 等于本组某个名字（记那个名字的拼写）。

格式化用 `Format('%s=%d,%d', [...])` 拼，`Names` 用 `,` 连接。

- [ ] **Step 5: 登记单元**

`tycontrols.lpk` 里 `tyControls.ToolWindows.Layout` 那个 `<Item>` 后面照样加一个（用编辑工具，文件是 CRLF）：

```xml
      <Item>
        <Filename Value="source/tyControls.ToolWindows.LayoutText.pas"/>
        <UnitName Value="tyControls.ToolWindows.LayoutText"/>
      </Item>
```

**先查** `<Files Count="…">` 之类的计数属性有没有（`grep -n "Count=" tycontrols.lpk | head`）；有就加一。新测试单元 `tests/test.toolwindow.layouttext.pas`（`TTyToolWindowLayoutTextTests = class(TTestCase)`）挂进 `tests/tytests.lpr`。

- [ ] **Step 6: 跑** `TTyToolWindowLayoutTextTests TReleaseManifestTest`，全绿；再 `lazbuild -B tycontrols.lpk`（包本身能编）。

- [ ] **Step 7: 变异**

| 变异 | 必须红 |
|---|---|
| 不查最后一段是 `end` | R3、截断 |
| 尺寸用 `TryStrToInt(Trim(…))`（照 Grid） | R7、R8、R13 |
| 名字唯一性用 `=` 比 | R15 |
| 空项不拒 | R17、R18 |
| 组不完整时只丢那一组、不拒整串 | R6 |
| 格式化漏 `|end` | F1、F5 |
| 从 `.lpk` 里删掉这一项 | `TReleaseManifestTest` |

- [ ] **Step 8: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.LayoutText.pas tycontrols.lpk tests/test.toolwindow.layouttext.pas tests/tytests.lpr && git commit -m "feat(toolwindows): strict parser and writer for the tool window layout string

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: 版本漂移计划（纯函数，spec §10.3）

**Files:**
- Modify: `source/tyControls.ToolWindows.LayoutText.pas`
- Modify: `tests/test.toolwindow.layouttext.pas`

- [ ] **Step 1: 声明**

```pascal
type
  { 程序此刻的一条可用栏(manager 装)。Names 按窗口顺序,空名 / 重名照实填 —— 找不到、
    匹配到不止一个都由计划自己判。 }
  TTyToolLayoutBarState = record
    Usable: Boolean;          { 有这个 Placement 的可用栏 }
    Names: TStringArray;
    Active: Integer;          { 当前页的窗口序号,-1 = 没有 }
  end;
  TTyToolLayoutWorld = array[TTyToolLayoutSide] of TTyToolLayoutBarState;

  { 一个窗口的身份 = 它此刻在哪条栏的第几个。 }
  TTyToolLayoutRef = record
    Side: TTyToolLayoutSide;
    Index: Integer;
  end;

  TTyToolLayoutBarPlan = record
    { 串里有这一组、这条栏可用:尺寸和收起才写。 }
    Apply: Boolean;
    Size: Integer;
    Collapsed: Boolean;
    { 应用之后这条栏的窗口顺序(已放置的在前,未放置的留在原栏、保持相对顺序)。 }
    Order: array of TTyToolLayoutRef;
    { Order 里的下标,-1 = 没有当前页。 }
    Active: Integer;
  end;
  TTyToolLayoutPlan = array[TTyToolLayoutSide] of TTyToolLayoutBarPlan;

{ spec §10.3。只对 Usable 的栏出计划(不可用的栏 Order 为空、Apply 为假,调用方不碰它)。 }
function TyToolLayoutPlanFor(const AWorld: TTyToolLayoutWorld;
  const ADoc: TTyToolLayoutDoc): TTyToolLayoutPlan;
```

- [ ] **Step 2: 写失败的测试（照下表）**

公共世界 `W0`：left 可用 `[Explorer, Search]`、当前 0；right 可用 `[Outline]`、当前 0；bottom 可用 `[Problems, Output, Terminal]`、当前 1。引用写成 `L0`、`R0`、`B2` 这样。

| # | 变化 | 期望 |
|---|---|---|
| P1 | doc = A1 | left `Order [L0, L1]`、`Active 0`、`Apply (240, 未收起)`；right `[R0]`、0、`(300, 收起)`；bottom `[B0, B1, B2]`（Terminal 未放置、排在后面）、`Active 1`、`(200, 未收起)` |
| P2 | doc：left `[Search]` / `Search`；right `[Explorer, Outline]` / `Explorer`；bottom 同 A1 | left `[L1]`、0；right `[L0, R0]`、0 |
| P3 | doc left `[Explorer, Ghost, Search]` | left `[L0, L1]`（Ghost 丢掉） |
| P4 | 世界 left 改成 `[Explorer, Search, NewOne]`；doc left `[Search, Explorer]` | left `[L1, L0, L2]` |
| P5 | 世界 left 改成 `[Explorer2, Search]`、当前 0；doc left `[Explorer, Search]` / `Explorer` | left `[L1, L0]`（Search 已放置，Explorer2 未放置）；`Active 1`（保存的 Explorer 不在栏里 → 当前页 Explorer2 还在 → 不变） |
| P6 | 世界 right `Usable = False`；doc left `[Explorer]`，doc right `[Search]` | right 没有计划；left `[L0, L1]`（Search 列在程序里没有的组下 → 未放置 → 留在 left） |
| P7 | doc bottom `[Explorer, Output]` / `Output`；doc left `[Problems, Search]` / `Search` | Explorer 列在底栏组下 → 未放置、留在 left；Problems 列在左栏组下 → 未放置、留在 bottom。left `[L1, L0]`、`Active 0`；bottom `[B1, B0, B2]`、`Active 0` |
| P8 | doc 没有 right 组；doc left `[Explorer, Search, Outline]` | right `Apply = False`、`Order []`、`Active -1`；left `[L0, L1, R0]` |
| P9 | doc left `[Search]` / `''`；doc right `[Explorer, Outline]` / `Outline` | left `[L1]`、`Active 0`（原当前页 Explorer 走了 → 第一个） |
| P10 | 世界 right 改成 `[Explorer, Outline]`（和 left 的 Explorer 重名）；doc left `[Search, Explorer]` | Explorer 匹配到两个 → 丢掉；left `[L1, L0]`；right `[R0, R1]` 不变 |
| P11 | 世界 left 改成 `['', Search]`（无名窗口）；doc left `[Search]` | left `[L1, L0]` |
| P12 | 世界 right 改成 `[]`、当前 -1；doc right `[]` / `''`、`(180, 收起)` | right `Apply`、`(180, 收起)`、`Order []`、`Active -1` |
| P13 | doc left `[Frame1.Explorer, Search]` | 带点的名字找不到、丢掉；left `[L1, L0]` |
| P14 | doc = A3（三组都没有） | 每条可用栏 `Apply = False`、`Order` 原样、`Active` 原样 |

（注意：同一个名字不能同时出现在两个组里——解析那一层就拒了（R15 那类）。漂移表的输入都必须先过得了 `TyToolLayoutParse`，写测试时每个 doc 先 Format 再 Parse 一遍断言 True。）

- [ ] **Step 3: 跑，确认红。**

- [ ] **Step 4: 实现**

1. 建名字索引：对所有 `Usable` 栏的每个窗口，非空名字按 `CompareText` 归类；一个名字对应不止一个窗口 → 记成「重名」。
2. 对每个 Present 且 `Usable` 的组、按组内顺序：名字找不到 / 重名 → 丢；找到的窗口所在栏与这一组**不同类**（一侧一底）→ 丢（未放置）；否则记「窗口 → 这一组」。Present 但不 Usable 的组整组跳过（里面的名字自然是未放置）。
3. 每条可用栏的 `Order` = 本组已放置的（组内顺序）+ 此刻在这条栏里、**没有被任何组放置**的窗口（原相对顺序）。
4. `Active`：保存的名字（非空）已放置到这条栏 → 它；否则此刻的当前页还在 `Order` 里 → 它；否则 `Order` 非空 → 0；否则 -1。缺组的栏同样走这条。
5. `Apply` / `Size` / `Collapsed` 只在组 Present 且栏 Usable 时填。

- [ ] **Step 5: 跑 `TTyToolWindowLayoutTextTests`，全绿；变异**

| 变异 | 必须红 |
|---|---|
| 未放置的排在已放置的前面 | P1、P4 |
| 不判「不同类」 | P7 |
| 重名时取第一个 | P10 |
| 当前页回落直接取第一个（跳过「原当前页还在」） | P5 |
| 缺组的栏不回落当前页 | P8 或 P9 |
| Present 但不 Usable 的组照样放置 | P6 |

- [ ] **Step 6: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.LayoutText.pas tests/test.toolwindow.layouttext.pas && git commit -m "feat(toolwindows): plan how a saved layout lands on the windows a program has now

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: 保存、读取、恢复的同步应用批次（spec §10.1、§10.2 保存、§10.4、§10.7）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`（uses 加 `tyControls.ToolWindows.LayoutText`）
- Create: `tests/test.toolwindow.layoutapply.pas`
- Modify: `tests/tytests.lpr`、`tests/test.toolwindow.manager.pas`（Live suite 加焦点判据）

本任务只做「不在加载中、窗体没 Showing」的同步路径；挂起、排队、默认布局的自动记录在 Task 13。`ResetLayout` 本任务先实现成「还没记过默认布局就先记（`SaveLayoutToString`），再按它应用」，Task 13 补全时机规则。

- [ ] **Step 1: 栏的批次（开工前问题 7、8）**

栏 private `FLayoutBatch: Integer`：
- `EventsAllowed` 加 `and (FLayoutBatch = 0)`。
- `SwitchCore`：`FLayoutBatch > 0` 时把 `AMoveFocus` 当 False。
- `SetCollapsed`：`FLayoutBatch > 0` 时跳过 `SelectNext` 那一步（spec §5.3）。
- `UnregisterWindow`：`FLayoutBatch > 0` 且离开的是当前页时只 `FActive := nil`，不回落（spec §5.2）。
- `RegisterWindow`：`AWindow.FQuietMove` 时不「注册即激活」（spec §5.1）。**`MoveNow` 第 6 步显式 `ActivateWindow` 已经在做**，行为不变。
- `ReorderWindow` 的 `OnWindowMoved` 门：`FLayoutBatch = 0`（批次里用 `PlaceWindow`，本来也不经过它；加这一道防以后有人在批次里调 `WindowIndex`）。

- [ ] **Step 2: manager**

- private `BuildWorld(out AWindows: array[TTyToolLayoutSide] of TTyToolWindowArray): TTyToolLayoutWorld`：对每个 Placement，找 `FBars` 里 Placement 是它且 `IsBarUsable` 的栏（最多一条），填 `Names`（`Controls` 顺序的窗口 `Name`）、`Active`，窗口本身填进 `AWindows`。
- `SaveLayoutToString`：`BuildWorld`；每条可用栏写一组：`Size = ExpandedSize`（最大化期间也是它，spec §10.2）、`Collapsed`；`Names` = 按顺序、跳过 `Name = ''` 或与**可用栏里**另一个窗口 `CompareText` 相同的（问题 16）；`Active` = 当前页的名字，当前页被跳过了就 `''`。返回 `TyToolLayoutFormat`。没有可用栏时是 `TYTOOLLAYOUT/1|end`（问题 20）。
- `LoadLayoutFromString(AText)`：manager 在 csDesigning / csDestroying → False；`FBars` 为空 → False；`TyToolLayoutParse` 失败 → False；`FEventDepth > 0` → False（问题 14）；否则 `ApplyText(doc)`，True。
- `ResetLayout`：前两条同上；本任务：还没记过就先 `CaptureDefaultLayout`；解析 `FDefaultText`、`ApplyText`。
- `CaptureDefaultLayout`：`FDefaultText := SaveLayoutToString; FDefaultCaptured := True;`（问题 15）。
- `FOnLayoutApplied` 与 published `OnLayoutApplied`。
- `ApplyText(const ADoc)`（spec §10.4 的七步，try/finally 逐层成对）：
  1. `CancelDrag`。
  2. 每条注册的底栏 `Maximized := False`（B 期留下的那一项）。
  3. 记窗体 `ActiveControl`（取第一条注册栏的 `GetParentForm`）、以及它原来在哪个窗口里（扫各栏的窗口 `ContainsControl`）。
  4. `plan := TyToolLayoutPlanFor(BuildWorld(wins), ADoc)`；`Inc(FApplying)`；所有注册栏 `Inc(FLayoutBatch)` + `DisableAlign`。
  5. 对每条可用栏 `B`、按 `plan[side].Order`：窗口不在 `B` 里的，`FQuietMove := True; Parent := B; FQuietMove := False`（try/finally）；再逐个 `B.PlaceWindow(w, k)`；`B.ActivateWindow(Order[Active])`（-1 时跳过）；`Apply` 时 `B.ExpandedSize := Size`、`B.Collapsed := Collapsed`。
  6. finally：倒序 `EnableAlign`、`Dec(FLayoutBatch)`；`Dec(FApplying)`。
  7. 焦点：原控件还 `CanFocus` → 还给它；否则原控件在某个窗口 W 里：W 现在的栏收起了、或没有能聚焦的当前页 → `GetParentForm(栏).SelectNext(栏, True, True)`；否则 `栏.ActiveWindow.FocusFirst`。原控件不在任何工具窗口里 → 不动。
  8. `Inc(FEventDepth)` 包着发 `OnLayoutApplied`。
- 批次里不问 `OnCanMoveWindow`、不发 `OnWindowMoved`（`MoveNow` 不经过，`PlaceWindow` 不发）。

- [ ] **Step 3: 新测试单元**

`tests/test.toolwindow.layoutapply.pas`：`TTyToolWindowLayoutApplyTests = class(TTyToolWindowBarFixture)`，夹具同 Task 8（左 `Explorer Search`、右 `Outline`、底 `Problems Output Terminal`，都有 Name）。挂进 `tests/tytests.lpr`。

- [ ] **Step 4: 写测试（判据）**

| 判据 | 在哪个变异下必须红 |
|---|---|
| 往返：先搞成非默认（左栏调过顺序、`Search` 跨到右栏、右栏收起、底栏 `ExpandedSize = 180`、左栏当前页是一个**无名**窗口），`s := Save`；再用 `MoveWindow` / setter 全部改回去；`Load(s)` 返回 True；`Save` 逐字等于 `s`，并逐项断言顺序、所在栏、收起、尺寸（无名当前页：左栏当前页不变） | 任一步没应用 |
| 截断：状态先挪离 `s`（地雷 12）；对 `s` 的每个前缀（长度 1..Length-1）`Load` 答 False，且 `Save` 输出逐字节不变；`s` 的最后一组放**多位数**尺寸 | 解析不查 `end`；或先应用后校验 |
| Task 10 的 R1–R24 各取一条喂 `Load`：False、状态不变 | — （解析已守；控件层确认没有别的入口绕过） |
| 重名窗口（右栏里再建一个也叫 `WExplorer` 的——两个窗口 Owner 不同）和无名窗口：`Save` 跳过它们；`Load(Save)` 答 True | 保存不跳过重名（读回时两个都匹配到，但串本身 R15 被拒） |
| 设计期 manager、正在释放的 manager、没有注册栏的 manager：`Load` / `Reset` 答 False | 去掉对应的门 |
| 批次事件：`Load` 期间 `OnCanMoveWindow`、`OnWindowMoved`、栏的 `OnChange` / `OnCollapse` / `OnExpand` 都没发；`OnLayoutApplied` 恰好一次 | `EventsAllowed` 不看 `FLayoutBatch`；或批次里走了 `MoveWindow` |
| `OnShow` / `OnHide` 照常：`Load` 把左栏当前页从 `Explorer` 换成 `Search`，`Explorer` 恰好一次 hide、`Search` 恰好一次 show；**跨栏挪走当前页**的那条源栏，回落页没有被短暂显示（没有它的 show / hide） | `UnregisterWindow` 批次里照常回落 |
| 挪进来的窗口在目标栏不是当前页：它没有 show 事件 | `RegisterWindow` 不看 `FQuietMove` |
| 最大化的底栏：`Load` 之后 `Maximized = False`，`ExpandedSize` = 串里的值 | 去掉第 2 步 |
| 拖动中 `Load`：拖动被取消（`m.IsDragging` 为假） | 去掉第 1 步 |
| 读进没有底栏的程序（把底栏 `Manager := nil`）的串带 bottom 组：答 True，左右照应用 | 缺可用栏的组让整串失败 |
| `ResetLayout`：改过之后 Reset，回到第一次 Reset 之前记下的样子（本任务：第一次调时现记） | Reset 不经 `ApplyText` |
| DPI：96 → 144（`AutoAdjustLayout` 各栏）→ 96 之后 `Save` 输出不变；144 下 `Load` 之后侧栏设备宽 = `MulDiv(ExpandedSize, 144, 96)` + 固定部分 | 保存写设备像素 |
| 不保存最大化（spec §10.7）：最大化时 `Save` 的底栏尺寸 = `ExpandedSize` | 保存写此刻的 Height |

焦点那一步（第 7 步）要窗体可见才测得出，而 Task 13 之后窗体可见时 `Load` 排队——这几条判据写在 Task 13，用「抽消息」走真实路径。不许为了现在就测而开一个直接调 `ApplyText` 的探针（绕过真实入口）。

- [ ] **Step 5: 跑** `TTyToolWindowBarTests TTyToolWindowBottomTests TTyToolWindowManagerTests TTyToolWindowCrossDragTests TTyToolWindowLayoutTextTests TTyToolWindowLayoutApplyTests`，全绿；变异逐条。

- [ ] **Step 6: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/ && git commit -m "feat(toolwindows): save, load and reset the workbench layout in one batch

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: 时机——加载中挂起、`TryFinishLoading`、默认布局、Showing 之后排队（spec §10.5）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.layoutapply.pas`、`tests/test.toolwindow.manager.pas`

- [ ] **Step 1: 挂起与收尾**

manager 加：

```pascal
  TTyToolLayoutPending = (tlpNone, tlpLoad, tlpReset);
  ...
    FPendingKind: TTyToolLayoutPending;
    FPendingText: string;
    FDefaultText: string;
    FDefaultCaptured: Boolean;
    { manager、任一注册栏、或它们的任一窗口还在 csLoading。 }
    function AnyParticipantLoading: Boolean;
    { spec §10.5:最后一个离开 csLoading 的参与者调它。都不在加载中了:先记默认布局
      (还没记过的话),再静默应用挂起的计划,OnLayoutApplied 推到加载结束之后。 }
    procedure TryFinishLoading;
    procedure EnsureDefaultCaptured;
    procedure LayoutAppliedAsync(Data: PtrInt);
  protected
    procedure Loaded; override;
```

- `Load` / `Reset`：格式检查（Reset 不需要）之后，`AnyParticipantLoading` → 覆盖挂起计划（`FPendingKind` / `FPendingText`），返回 True。
- `TryFinishLoading`：`AnyParticipantLoading` → 返回；`EnsureDefaultCaptured`；有挂起计划 → 取出、清掉、所有注册栏 `BeginSilent`（try/finally）包着 `ApplyText`，并让 `ApplyText` 第 8 步改成 `Application.QueueAsyncCall(@LayoutAppliedAsync, 0)`（加一个参数 `AQueueEvent`）。Reset 的挂起计划用的是**刚记下的**默认布局。
- 调用点：manager `Loaded` 末尾；栏 `Loaded` 最后一句（`FManager <> nil` 时）；**窗口新加 `Loaded` 重写**，继承之后 `Bar <> nil` 且 `Bar.Manager <> nil` 时调（问题 6）。
- manager 析构的 `RemoveAsyncCalls` 同时撤掉 `LayoutAppliedAsync`（同一个对象，不用另写）。

- [ ] **Step 2: 默认布局的自动记录**

- `EnsureDefaultCaptured`：没记过就 `CaptureDefaultLayout`（它会把 `FDefaultCaptured` 置上；`CaptureDefaultLayout` 随时覆盖）。
- private `NoteLayoutChanging(ABar: TTyToolWindowBar)`：没记过、manager 和栏都不在加载 / 设计 / 释放中、`FApplying = 0`、`GetParentForm(ABar)` 非 nil 且 `Showing` → `CaptureDefaultLayout`。
- 调用点（问题 2，都在**改之前**）：栏的 `SetCollapsed`（值真的变时）、`SetExpandedSize`（值真的变时）、`ReorderWindow`、`ActivateWindow`（`AWindow <> FActive` 且不在加载中时）、`MoveNow` 开头（在 `CancelDrag` 之后）、窗口 `SetParent` 的 `book` 分支开头。`FLayoutBatch > 0` 时这些路径由 `FApplying` 挡掉。
- `Load` / `Reset` 非加载期间先 `EnsureDefaultCaptured`（spec：FormCreate 里先搭好再读用户布局，记下的就是搭好的样子）。

- [ ] **Step 3: Showing 之后排队**

- 队列记录 `TTyToolWindowQueuedKind` 加 `twqLayout`，记录加 `Text: string; IsReset: Boolean`（Reset 执行时取那一刻的默认布局）。
- `Load` / `Reset`（非加载期间）：`EnsureDefaultCaptured` 之后，窗体 `Showing` → 清空队列（覆盖之前排队的计划和移动，spec §10.5）、入一项 `twqLayout`、返回 True；否则同步 `ApplyText`。
- `RunQueue` 的 `twqLayout`：先算计划；「要跨栏移动的窗口」里有一个含着捕获控件、且没再排过 → 再排一次；否则重新解析文本（排着期间窗口可能变了）并 `ApplyText`。

- [ ] **Step 4: 写测试（判据）**

无头（`TTyToolWindowLayoutApplyTests`）：

| 判据 | 在哪个变异下必须红 |
|---|---|
| 真实的流：窗体里依次写 `TLoadCaller`（测试里的小组件，它的 `Loaded` 调 `m.LoadLayoutFromString(s)`）、三条栏和窗口、manager；`ReadComponent` 之后布局是 `s` 的样子 | 加载中直接应用（那时窗口还在 csLoading、名字还没全） |
| 同上，`TLoadCaller` 在它的 `Loaded` 里调：返回 True；应用期间没有任何用户事件（栏事件、`OnShow` / `OnHide` 都没有） | 挂起计划不包 `BeginSilent` |
| `OnLayoutApplied` 在 `ReadComponent` 返回时**还没**发；抽消息之后恰好一次（Task 0 Step 3 第 1 条：无头抽不动就挪到 Live suite） | 挂起计划同步发 `OnLayoutApplied` |
| 流里写成「manager 在栏前面」（手工调写入顺序，或用 frame——Task 0 Step 3 第 3 条查到的写法）：照样应用 | 窗口的 `Loaded` 不调 `TryFinishLoading` |
| 加载中调两次（先 Load 后 Reset）：只应用后一次 | 挂起计划不覆盖 |
| 加载中喂坏串：立即 False，加载结束后什么都没应用 | 加载中不查格式 |
| 从 .lfm 加载的默认布局 = 流进来的值：加载后改几处，`ResetLayout` 回到流里的顺序、当前页、尺寸、收起 | 默认布局在第一次 Reset 时才记 |
| 继承窗体（照 `TTyToolWindowStreamingTests` 里 ancestor / descendant 两遍读）上的 Reset：回到子孙窗体流进来的值 | — |
| 代码搭的 manager：FormCreate 里（窗体没 Showing）先改 `Collapsed` / `ExpandedSize` / `WindowIndex` / `MoveWindow`，再 `Load(用户串)`：默认布局 = 改完之后、读用户串之前的样子（`Reset` 回到它） | Load 不先 `EnsureDefaultCaptured` |
| `CaptureDefaultLayout` 之后再改、再 `Load`：Reset 回到 `CaptureDefaultLayout` 那一刻 | Load 覆盖已记的默认布局 |

真句柄（`TTyToolWindowManagerLiveTests`，窗体 Showing）：

| 判据 | 在哪个变异下必须红 |
|---|---|
| 代码搭的 manager、没调过 Load / Reset：窗体显示之后点左栏另一个图标（真实 `MouseDown` / `MouseUp`），再 `ResetLayout`、抽消息：当前页回到点之前那一页（问题 2） | `ActivateWindow` 不调 `NoteLayoutChanging` |
| 同上，改 `ExpandedSize` / `Collapsed` / 拖动调顺序 / 跨栏拖放各一次（各自独立的一条）：Reset 回到改之前 | 对应调用点缺 `NoteLayoutChanging` |
| Showing 之后 `Load`：返回那一刻状态没变，抽消息之后应用 | Showing 时同步应用 |
| 「恢复布局」按钮放在某个窗口的操作区里、它的 `OnClick` 调 `ResetLayout`，而默认布局会把这个窗口挪到另一侧：点它（真实消息）不 AV、按钮 `Handle` 在处理器里不变；抽消息之后生效（spec §14） | 同上 |
| 排着的移动后面来一个 `Load`：移动被覆盖，只剩布局 | `Load` 入队时不清队列 |
| 焦点（spec §10.4 第 7 步 / §14）：焦点在左栏当前页的编辑框里，`Load` 一个只把左栏收起、当前页不变的串，抽消息：`ActiveControl` 不是窗体本身、也不在藏起来的窗口里 | 去掉第 7 步的 `SelectNext` 分支 |
| 焦点在左栏当前页 `Explorer` 里，串把 `Explorer` 挪到右栏（展开）：`ActiveControl` 还是原来那个编辑框 | 第 7 步不先试「原控件还 `CanFocus`」 |
| 焦点在 `Explorer` 里，串把它挪到右栏、但右栏当前页换成别的：焦点落在右栏当前页里（`FocusFirst`），不在窗体本身 | 第 7 步不走 `FocusFirst` 分支 |

- [ ] **Step 5: 跑** `TTyToolWindowStreamingTests TTyToolWindowBarTests TTyToolWindowManagerTests TTyToolWindowManagerLiveTests TTyToolWindowLayoutApplyTests`，全绿；变异逐条。

- [ ] **Step 6: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/ && git commit -m "feat(toolwindows): layout calls during loading wait for the last Loaded; after showing they queue

The default layout is captured from the streamed values, or from the code-built
state just before the first layout change once the form shows.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: 收尾——按 spec 逐条核、grep、跑全量、抽查变异、审查、偏差写回 spec

**Files:**
- Modify: `docs/superpowers/plans/2026-09-24-toolwindow-phase-c.md`
- Modify: `docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md`

- [ ] **Step 1: 按 spec 逐条核代码，不看测试**（[[green-tests-are-not-spec-conformance]]）

逐条对着代码查，每条记「在哪一行实现 / 为什么不需要」：

- §2：manager 继承 `TTyComponent`、`RegisterClass` 还在；栏的 `Manager` published。
- §3.2：同类改 Parent 的簿记（展开、焦点、事件顺序、同一 manager 才发 `OnWindowMoved`、`FQuietMove` 跳过）；跨类仍抛。
- §5.1 / §5.2 / §5.3：注册即激活在 `FQuietMove` 时关掉；批次内不回落、不挪焦点。
- §6.6：表里每一行的「发 / 不发」逐格核——尤其 `OnWindowMoved` 在 `WindowIndex`、手势、`MoveWindow`、同 manager 直接改 Parent 时发，流式 / 设计期 / Load / Reset 不发；`OnLayoutApplied` 挂起时排队。`MoveWindow` 的发送顺序。
- §8：`EffectiveImages` 回落和三处 `ImagesChanged`。
- §9.2：进入拖动时标记 manager；目标栏的反馈只在 `(栏, 槽位)` 变时 invalidate。
- §9.4：候选栏条件逐条（含问题 1 的 `IsEnabled`）；`FindControlAtPosition`；嵌套栏；否决缓存。
- §9.5：`MoveNow` 的顺序逐句；源栏拖空不写 `Collapsed`。
- §9.7：取消的每一条路都有调用点（Esc、无按键移动（源栏和其他注册栏）、`LM_CANCELMODE`、失活、换窗体、计时器、四种 `opRemove`、`MoveWindow` / `Load` / `Reset`、参与栏改三属性、`CancelDrag`、栏和 manager 析构）。
- §9.9：`MoveWindow` 返回 False 的每一条；同步 / 排队的判定；队列规则四条。
- §10.1–§10.7：逐节。
- §13：`OnWindowMoved` 对 API 也发（有意偏离已实现）。

- [ ] **Step 2: grep**

```bash
cd /d/Projects/ty-3.1 && for c in $(grep -hoE "^ +TyToolWindow[A-Za-z]+ += |^ +TyToolLayout[A-Za-z]+ += " source/tyControls.ToolWindows.pas source/tyControls.ToolWindows.Layout.pas source/tyControls.ToolWindows.LayoutText.pas | sed -E 's/^ +//; s/ +=.*//'); do n=$(grep -rwn "$c" source --include=*.pas | grep -vE "^[^:]+:[0-9]+: +$c +=" | wc -l); [ "$n" -eq 0 ] && echo "没人读: $c"; done; echo done
```

Expected：只打印 `done`。再核：

- 「接口清单」表里每个名字在 `source/` 里定义处之外至少出现一次（`grep -c`），`ForeignDropForTest` 这类探针在 `tests/` 里有人读。
- 三个 published 事件都有调用处：`grep -n "FOnCanMoveWindow\|FOnWindowMoved\|FOnLayoutApplied" source/tyControls.ToolWindows.pas`，每个除了声明和属性行之外至少一处调用。
- `grep -n "C 期\|空壳\|TODO" source/tyControls.ToolWindows*.pas tests/test.toolwindow.*.pas`：`C 期` 字样都改成现在的事实（栏析构、`EffectiveImages`、`BeginSilent`、`SwitchCore`、`Notification`、引擎、manager 的注释；测试里「C 期的布局应用」那几处改成指向真实的测试）。
- 「B 期留给本期的 6 项」表逐项在代码里找到。

- [ ] **Step 3: 跑全量**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && lazbuild -B tycontrols.lpk && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --all --format=plain > /tmp/all.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/all.txt
```

Expected：`Number of run tests` 那一行存在，errors / failures 都是 0，总数 = Task 0 的基线 + 本期新增条数。红了先按 [[known-rare-suite-flake]]、[[suite-order-widgetset-init]]、[[canary-then-rebuild]] 排查是不是既有的偶发 / 顺序问题 / 二进制陈旧，再疑本期代码。

- [ ] **Step 4: 抽查变异（每条三拍，必须红）**

1. Task 4 的「去掉延后」（事件顺序串）。
2. Task 6 的「`MustQueue` 恒 False」（按钮句柄那一条）。
3. Task 7 的「不查 `Holes`」。
4. Task 8 的「`SetTarget` 不清旧目标」。
5. Task 12 的「`UnregisterWindow` 批次里照常回落」。
6. Task 13 的「窗口的 `Loaded` 不调 `TryFinishLoading`」。

- [ ] **Step 5: 整体代码质量审查**

按执行方式，本期只在这里做一次：对 `git diff <Task 0 的 HEAD>..HEAD -- source/` 做一次代码质量审查（重复代码——`MoveNow` 和 `SetParent` 的簿记、`ApplyText` 的焦点那一段是否该合成一处；注释与代码不符；遗留的「C 期」字样；死字段 / 死方法；try/finally 成对）。审出来的问题修完再回到 Step 3 跑一次全量。

- [ ] **Step 6: 把实现期的偏差写回 spec 原处**

「开工前要定的问题」里用户拍板的每一条，和实现中新发现的每一处 spec 没写准的地方，都在 spec **原处**改并标「实现期修正（C 期）」——D 期读的是 spec，不是这份计划。至少要落的：

- §9.4（问题 1：禁用的栏不是目标；问题 10：纯函数只管侧栏候选）；
- §10.5（问题 2：「改动布局」的清单；问题 6：窗口的 `Loaded` 也调 `TryFinishLoading`；问题 15：默认布局存成串）；
- §9.2（问题 4：三个字段不加）；
- §9.7 / §9.9（问题 5：队列归 manager、析构撤、关停守卫；问题 12、13）；
- §3.2 / §6.6（问题 9：直接改 Parent 与 `MoveWindow` 同一事件顺序）；
- §10.4（问题 7、8：批次与静默分开、批次内不回落）；
- §10.1（问题 14、20）；§10.2（问题 16）；§10.6（问题 17）；§11（问题 19：设计期 `MoveWindow` 自己通知设计器）；
- §16 第 5、6 步标「已完成」，把本期留给 D 期的事写进第 7 步（设计期冲突提示要在哪几处重画、组件编辑器可以直接用 `IsBarUsable` / `CanMoveWindow`）。

- [ ] **Step 7: 签收记录写进本计划末尾，提交**

```bash
cd /d/Projects/ty-3.1 && git add docs/ && git commit -m "docs(toolwindows): phase C sign-off notes and spec corrections

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## C 期做完能看到什么

在一个窗体里用代码搭左右两条侧栏、一条底栏和一个 manager（D 期才有组件编辑器和示例；下面这段是 C 期的冒烟用法，不进仓库）：

```pascal
procedure TMainForm.FormCreate(Sender: TObject);
var
  host: TTyPanel;
  mgr: TTyToolWindowManager;
  left, right, bottom: TTyToolWindowBar;

  function AddWin(ABar: TTyToolWindowBar; const AName, ACaption, AIcon: string): TTyToolWindow;
  begin
    Result := TTyToolWindow.Create(Self);
    Result.Name := AName;               { 布局串按 Name 认窗口 }
    Result.Caption := ACaption;
    Result.ImageName := AIcon;
    Result.Parent := ABar;
  end;

begin
  mgr := TTyToolWindowManager.Create(Self);
  mgr.Images := LucideImages1;          { 两侧共用一份列表(spec §8) }

  left := TTyToolWindowBar.Create(Self);
  left.Parent := Surface;               { TTyForm 的内容容器 }
  left.Placement := twpLeft;
  left.Manager := mgr;
  AddWin(left, 'Explorer', 'Explorer', 'files');
  AddWin(left, 'Search', 'Search', 'search');

  right := TTyToolWindowBar.Create(Self);
  right.Parent := Surface;
  right.Placement := twpRight;
  right.Manager := mgr;
  AddWin(right, 'Outline', 'Outline', 'list-tree');

  { 编辑区和底栏一起放进一个 alClient 的容器,底栏就只在编辑区下面(spec §2)。 }
  host := TTyPanel.Create(Self);
  host.Parent := Surface;
  host.Align := alClient;
  Memo1.Parent := host;
  Memo1.Align := alClient;

  bottom := TTyToolWindowBar.Create(Self);
  bottom.Parent := host;
  bottom.Placement := twpBottom;
  bottom.Manager := mgr;
  AddWin(bottom, 'Problems', 'Problems', '');
  AddWin(bottom, 'Output', 'Output', '');

  { 读上次存的布局;第一次运行没有就什么都不做(格式错也只是答 False)。 }
  if FileExists(LayoutFile) then
    mgr.LoadLayoutFromString(Trim(ReadFileToString(LayoutFile)));
end;

procedure TMainForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  WriteStringToFile(LayoutFile, mgr.SaveLayoutToString);   { 名字照项目里现成的工具函数改 }
end;
```

（`TTyPanel` / `Surface` / 读写文件的工具函数的确切名字执行时照 `examples/` 里现有的 `.lfm` 和代码核一遍。）

运行起来应当是：

- 左右各一条侧栏、各有图标条，底栏在编辑区下面；两侧的图标都来自 manager 上的那一份列表；
- 按住左栏的「Search」图标拖向右栏：经过右栏图标条时，右栏条上出现插入线，拖到右栏内容区时插入线停在右栏最后一个图标后面；经过编辑区、底栏时变成禁止光标、没有线；
- 在右栏上松开：Search 移到右栏、成为右栏的当前页，右栏收起着的话会展开；左栏回落到剩下的那一页；拖到一半按 Esc、或者在编辑区上松开，什么都不变；
- 把左栏最后一个窗口也拖走，左栏只剩图标条，照样能再拖回来；
- 底栏的标签只能在底栏里调顺序，拖到侧栏上是禁止光标；
- 代码里 `mgr.MoveWindow(Explorer, right)`、`Explorer.WindowIndex := 0` 都生效，`OnWindowMoved` 每次都报；在窗口自己的按钮里调 `MoveWindow` 也不会崩（窗体显示之后是排队执行的）；
- 关掉程序再打开，两侧窗口的归属、顺序、当前页、宽度、收起状态都回到上次的样子；新版本里新加的窗口留在设计时那一侧；
- `mgr.ResetLayout` 回到 FormCreate 搭好的样子；
- 同一个 manager 下放两条左栏：两条都不参与跨栏拖动和布局保存，各自的栏内调顺序照常。

**还做不到的**（D 期）：设计器里「新建工具窗口」「移到另一侧栏」「移回栏里」、设计期的 Placement 冲突提示和孤儿窗口提示、组件面板上的栏和 manager、示例和文档。

**只能真机验的**（spec §15 里和 C 期有关的，本期无头测不到）：

- Win32：拖动光标在别的栏、编辑区上方是否正确；
- GTK3：拖出源栏后移动事件的坐标（跨栏命中全靠它）；`gtk_grab_add` 下 Esc；
- GTK3 / Qt Wayland：同窗体坐标；
- Cocoa：临时光标；拖动事件是否一直发给按下的那个 view；
- 各 widgetset：拖动中 Alt+Tab、`ShowModal`、弹出菜单抢走捕获后能否取消；换父控件后窗口里的原生子控件（IME 组字、光标）是否按文档说的那样丢状态；
- 皮肤：17 个主题下目标栏的插入线看不看得见（尤其高对比度皮肤）。
