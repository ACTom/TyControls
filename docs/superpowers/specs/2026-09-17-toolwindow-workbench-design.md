# IDE 工作台侧栏与底栏 —— 设计定稿

> 状态：已定稿（用户 2026-09-17 逐段拍板）· 分支：`feat/3.1` · 需求来源：用户口头（3.1）

现代 IDE 那种左右侧栏加底栏：侧栏一侧只显示一个工具窗口，靠图标条切换；底栏是一排文字标签，
标签右边是当前页自己的操作区（筛选框、清除、新建终端……）。左右侧栏之间可以互相拖动工具窗口，但不能拖到底栏。

本文锁范围与契约，实现步骤另拆到 `docs/superpowers/plans/`。
所有关于 LCL / Lazarus 设计器 / FPC 流式的结论都是**读源码核实**的（行号见各节），**没有真机验过**的列在 §15。
文中标了「定稿时新加」的规则，是讨论时没有、写文档时补上的默认做法，依据写在原处。

---

## 1. 已定的前提（不再讨论）

| # | 决定 | 直接后果 |
|---|------|----------|
| 1 | **拆成四个类**，不做一个大控件 | 只要一个左侧栏、侧栏放进别的容器、底栏横跨还是只在编辑区下面，都是普通 Align 问题 |
| 2 | **两侧都有图标条**（JetBrains 形状），一侧同时只显示一个窗口（VS Code 行为） | 不做"右侧栏用标题行标签"的模式；VS Code 右侧栏其实没有图标条，这里是有意偏离 |
| 3 | 窗口里的**分段叠放**（VS Code 资源管理器里的"打开的编辑器 / 文件夹 / 大纲"）属于**页面内容** | 框架不管，页面里自己放 `TTyExPanel` |
| 4 | **操作区是工具窗口的子控件**，不挂在栏上 | Lazarus 设计器的删除 / 复制都顺着 Parent 走，挂在栏上会漏掉（§11） |
| 5 | 底栏标签那一行由**当前页代画**，鼠标转交给栏 | 同一行里放标签和当前页的操作区；和滚动条替宿主画边框同一个路子 |
| 6 | **底栏标签和侧栏图标都在鼠标松开时切换** | 按下就切会藏起正持有鼠标捕获的窗口；图标按下就切还会和拖动打架（§9.3） |
| 7 | **侧栏 ↔ 侧栏可以拖，侧栏 ↔ 底栏双向都不行** | 有意偏离 VS Code（它三处都能互拖） |
| 8 | 拖动由 **manager 自己做**，不走 LCL 的 DragManager | 用户自己写了 `OnDragOver` 的控件会截走工具窗口（§9.6） |
| 9 | **栏宽每侧记一个**（VS Code 做法），不按窗口各记 | 同一侧切换窗口编辑区宽度不跳；格式留了加"每窗口宽度"的口子，不用改版本号 |
| 10 | 布局存成**一行字符串**，照 `TTyStringGrid.SaveLayoutToString` 的约定 | 不引入 ini / XML / JSON |

---

## 2. 组成

一个单元 `source/tyControls.ToolWindows.pas`：

| 类 | 作用 | 设计器里 |
|---|---|---|
| `TTyToolWindow` | 一页工具窗口：上面标题行，下面正文 | 容器，Owner=窗体，Parent=栏；照 `TTyTabSheet` |
| `TTyToolWindowActions` | 这一页的操作区，放在标题行右端 | 窗口的子容器，可选 |
| `TTyToolWindowBar` | 贴一条边的栏：图标条（侧栏）、切页、收起、拉宽、调顺序 | 组件面板上有；`Placement` 选左 / 右 / 底 |
| `TTyToolWindowManager` | 不可见组件，可以不放：跨侧拖动、布局保存 | 组件面板上有；栏的 `Manager` 属性指向它 |

- `initialization` 里对四个类 `RegisterClass`；设计期包里栏和 manager `RegisterComponents`，窗口和操作区 `RegisterNoIcon`。
- 单元加进 `tycontrols.lpk`（搜索路径能编过不代表进了包，见 [[new-unit-missing-from-lpk]]）；组件编辑器和属性编辑器在 `tycontrols_dt.lpk`，要单独编。
- 名字已查过不重名。`TTyActivityBar`（不定进度条）和 `ToolGroup`（`TTyToolGroupPanel`）已被占用，避开。

**摆法（写进文档和示例）**：栏就是普通的 Align 控件。底栏横跨整个窗口还是只在编辑区下面，由布局决定——
把编辑区和底栏一起放进一个 alClient 的 TTy 容器，底栏就只在编辑区下面（VS Code 默认的样子）。

**索引约定（全文通用）**：`ActiveIndex`、`WindowIndex`、拖放槽位、`FinalIndex`、`MoveWindow` 的 `AIndex`、布局串里的顺序，
一律是**窗口之间**的序号；调 `SetControlIndex` 前换算成 `Controls` 下标（第 k 个窗口当前在 `Controls` 里的位置）。

---

## 3. 工具窗口 `TTyToolWindow`

### 3.1 类与属性

`TTyToolWindow = class(TTyCustomControl)`

- 构造：`ControlStyle + [csAcceptsControls, csDesignFixedBounds, csNoDesignVisible, csNoFocus, csTripleClicks, csQuadClicks]`；`Align := alClient`；`Visible := False`。**构造里什么都不自动建**（csLoading 翻倍坑，见 GridPanel）。
  多击两个标志的理由：底栏标题行的按下落在窗口的句柄上，LCL 数点击次数看的是收到消息的那个窗口化控件（`controls.pp:3280-3290`）；不加的话第三次按下被还原成普通按下，又生效一次。
- published：`Caption`、`ImageName: string`、`ImageIndex: TImageIndex`（`stored (ImageName = '') and (ImageIndex >= 0)`，default -1）、`StripHint: string`、`StyleClass`、`OnShow`、`OnHide`。
- `Left / Top / Width / Height / TabOrder / Visible` 重新声明为 `stored False`。
- **`Controller` 由栏推送，不写进 .lfm**。它在基类 `TTyCustomControl` 上已经 published（`Base.pas:452`），子类撤不掉。
  做法：在 published 段重新声明 `property Controller stored False;`；设计期包里用 `THiddenPropertyEditor` 把窗口和操作区的 `Controller` 从对象查看器里藏起来（先例 `Design.PropEditors.pas:730-738`）。
  栏在注册、栏换 Controller、移动时推给窗口，窗口再推给操作区；代码里直接赋给窗口的值会被下一次推送盖掉，文档写明。
  不存的理由：.lfm 里的值在 `RegisterPage` 之后才读进来，两边会漂开（`PageControl.pas:280`，`reader.inc:984` 先于 `:1004`）。
- public：`Bar`、`IsActive`、`Actions`（扫 `Controls[]` 找第一个 `TTyToolWindowActions`，不缓存）、`EnsureActions`、`FocusFirst`（包一层 protected 的 `SelectFirst`）、`WindowIndex`（读写，`stored False`）、`RelayoutHeader`、`HeaderRowRect`。

### 3.2 父控件

- `ChildClassAllowed` 拒绝 `TTyToolWindow` 和 `TTyToolWindowBar`（防止窗口套窗口）。
- `SetParent` 照 `TTyTabSheet.SetParent`：从旧栏注销（任一方 csDestroying 时跳过）、注册到新栏、推 Controller、`RelayoutHeader`。
- **孤儿模式**（Parent 不是栏）：设计期去掉 csNoDesignVisible、显示出来，并用 `TyToolWindowNote` 画一行提示（resourcestring）。运行时保持隐藏。
  HeaderMode = none：标题行高 0，`CustomAlignPosition` 不调 `Bar`，操作区按 raw 首选尺寸放在左上角。
  **不在 `CheckNewParent` 里 raise**：源码上读取器会经过它，但 `designtime/tyControls.Design.pas:211-216` 记着真机结果——设计器粘贴不经过能挂守卫的 SetParent；在读取器里抛异常还会中止整个撤销。
- **运行时直接改 Parent**：
  - 改到**另一类**栏（侧 ↔ 底）抛 `EInvalidOperation`（csLoading / csDesigning 时除外）。
  - 改到**同类**栏：有没有 manager、目标冲不冲突都照做（用户显式要求，这里又不能抛异常）；执行 §9.5 的源栏 / 目标栏簿记（源栏回落当前页，W 成为目标栏当前页并展开），不问否决。`SetParent` 在继承之前记下窗体的 `ActiveControl`，簿记完成后它还在 W 里且 `CanFocus` 就还给它（同 `MoveWindow`）。两条栏在同一个 manager 下时发 `OnWindowMoved`；栏的事件照 §6.6。`MoveWindow` 和布局应用（§10.4）内部自己改 Parent 时置标志，跳过这段。

### 3.3 可见性

每条栏同时只显示一页，这个不变量由栏守：

- 重写 `SetVisible`。栏自己切换时置 `FBarSwitching`，直接放行。
- 运行时，外部对非当前页设 `True` → 通过栏激活这一页并展开栏；对当前页设 `True`、栏收起着 → 展开；对当前页设 `False` → 栏 `Collapsed := True`。
- 设计期：外部设 `True` 只激活，不写 `Collapsed`；对当前页设 `False` 忽略。否则对象查看器里一勾，`Collapsed` 就被写进 .lfm，设计期又永远按展开显示，用户看不到，运行时却是收起的。
- csLoading 期间的赋值忽略。

### 3.4 标题行

- **HeaderMode 只看所在栏的 Placement**：side / bottom / none（孤儿）。**不看哪页是当前页**——否则不活动页按侧栏模式排、切换后又按底栏模式排，正文会跳。
- **标题行高**：
  - 侧栏模式：`max(token 项, 本窗口操作区的 raw 首选高度)`。
  - 底栏模式：由栏统一算 `max(token 项, 栏内所有窗口操作区的 raw 首选高度)`，所有窗口共用，**标签行高度不随切页变化**；窗口列表或任一操作区的首选高度变了，栏对所有窗口 `RelayoutHeader`。
  - token 项 = `--toolwindow-header-height` 按 PPI 缩放，按键 `(PPI, model identity, ThemeVersion, UseRightToLeftAlignment, HeaderMode)` 缓存；在 `Invalidate` 重写里、继承的 `AutoAdjustLayout` 之后、`CMBiDiModeChanged` 里各查一次键，变了就带重入保护 `Realign`。理由：主题切换只会带来一次裸 `Invalidate`（`Controller.pas:665-687`），没人调 Realign（`ScrollBar.pas:992-1000` 同一处注释）。
  - 操作区那一项**不缓存**，`AdjustClientRect` 每次现取。侧栏模式和底栏当前页：操作区子控件增删、显隐、改尺寸会触发整窗体 `DoAllAutoSize` 自顶向下 `AlignControl`（`control.inc:3092-3099`），现取就能跟上。
  - **底栏另加一个通知**：只靠整窗体 `DoAllAutoSize` 不够——`AdjustSize` 往上传到隐藏的窗口就停（`control.inc:383-388`），当前页察觉不到非当前页操作区的变化。所以操作区重写 `AdjustSize`（虚方法，`controls.pp:1640`；子控件增删 `wincontrol.inc:6416, 6459`、改尺寸 `control.inc:731-732`、隐藏 `control.inc:4639-4640` 都会调到它，所在窗口隐藏时也调得到），继承之后先 `InvalidatePreferredSize`（子控件只改 `Constraints` 时缓存不会失效，`control.inc:1520-1522`），再比较自己的 raw 首选宽高和上次记下的值，变了就通知所在栏；栏重算统一行高，变了就带重入保护对当前页 `RelayoutHeader`（csLoading 期间跳过）。非当前页在激活第 4 步 `RelayoutHeader` 时现取。
  - 换了内边距大的皮肤，按钮不会被裁。
- `AdjustClientRect`：继承后 `Top += 标题行高`。
- `CustomAlignPosition`：
  - 侧栏 / 底栏模式：`Actions`（第一个操作区）的四个边界全部取 `Bar.HeaderGeometry(Self).Actions`。
  - 多出来的操作区（§4）放在正文区左上角（`AdjustClientRect` 之后的客户区原点），按 raw 首选尺寸。
  - HeaderMode = none：不调 `Bar`（§3.2）。
  - 其他子控件走继承。

**侧栏标题行**：`[header-pad][标题][header-gap][操作区]`；操作区自带内边距，宽为 0 时尾端补一个 `header-pad`。
操作区优先保宽；标题先省略号、窄到放不下一个字形就不画。侧栏标题行**没有固定按钮**。

**底栏标题行**（从尾端往前排）：`[收起][最大化/还原][分隔线][操作区][溢出][标签…]`，规则见 §7.3。

### 3.5 绘制

- 用 `TTyTabSheet` 的缓存模式（`TabSheet.pas:330-355`）。**所有标题行的视觉变化都走 `Invalidate`（会丢缓存）**，不许裸 InvalidateRect——否则运行时 blit 旧缓存，悬停永远不变；而设计期不走缓存，在设计器里看是好的（假绿）。
- 侧栏模式：`TyToolWindowHeader` 底色，再在 `Geom.Caption` 里画标题。标题宽度量法 `Max(TyMeasureTextBlock, TyMeasureRenderedTextWidth)`（`Painter.pas:454-466` 的约定）。
- 底栏模式：标题行底色，再 `Bar.PaintHeader(Self, P, Geom)`，只在 `IsActive` 时画。
- **窗口从不画栏的边框**（§6.1）。

### 3.6 底栏模式下的输入

**标签行区域** = 标题行矩形减去操作区矩形（窗口坐标，包括标签之间和标签后面的空白）。下面的武装、吞输入、转发、提示、右键都按这个区域判断；区域内 `HeaderZoneAt` 返回 none 的点只吞掉，不转发。

- 在标签行区域里按下 → 武装 `FHeaderGesture`；武装期间 Down / Move / Up / Leave 全部转给栏。
- 区域内的输入**吞掉**继承的 `MouseDown / MouseUp / Click / DblClick`、`DoContextPopup`（Handled）、`DoMouseWheel`（True）。否则用户挂在窗口上的 `OnClick`、`PopupMenu`、滚轮处理会对标签行的点击起反应（`control.inc:2515-2523, 2827-2846`）。区域内从不 `SetFocus`。
- 重写 `BeginAutoDrag`：用户设了 `DragMode = dmAutomatic`，在标签行区域按下也不会起一个 LCL 拖动（`control.inc:2284`）。
- **设计期**：窗口在整个标签行区域回答 `CM_MASKHITTEST > 0`（坐标先 `ParentToClient(pt, GetDesignerForm(Self))`），设计器的命中搜索跳过窗口、落到栏上，而栏永远不会被隐藏（`designer.pp:497-502`）。栏的 `CM_DESIGNHITTEST` 仍然只在标签上和武装期间回答 1（§7.4），点空白就是选中栏。
- `CM_HINTSHOW`：区域内从 `Bar.HeaderHint` 取 `HintStr` 和 `CursorRect`，区域外走继承。**不强行把窗口的 `ShowHint` 设成 True**——它会经 `ParentShowHint` 传给用户的所有子控件（`control.inc:1295-1304`）。标签提示跟随窗口自己的 `ShowHint`，文档写明。
- 右键：标签行区域内窗口的 `DoContextPopup` 一律置 Handled。只有落在**标签上**才调栏的 `HeaderContextPopup(W, X, Y)`（§7.2）：栏设好 `ContextWindow`，用栏坐标触发自己的 `OnContextPopup`；没被处理、有 `PopupMenu` 且 `AutoPopup` 为 True 时，以栏为 `PopupComponent` 在鼠标位置弹出。落在溢出、分隔线、最大化、收起和空白处：只吞掉，不转给栏，也不弹菜单。
- **当前页 `Enabled = False` 时，标签行、溢出、最大化、收起都跟着失灵**：输入由这个窗口接收，Cocoa 直接丢弃（`cocoawscommon.pas:920-923`）。文档写明：要禁用页面，禁用正文里的控件，不要禁用 `TTyToolWindow` 本身。

---

## 4. 操作区 `TTyToolWindowActions`

`TTyToolWindowActions = class(TTyCustomControl)`

- 构造：`ControlStyle + [csAcceptsControls, csDesignFixedBounds, csNoFocus, csAutoSizeKeepChildLeft, csAutoSizeKeepChildTop]`；`inherited SetAlign(alCustom)`，重写 `SetAlign` 钉死 alCustom；**Align 和 Anchors 不 published**。
  不加那两个 KeepChild 标志，用户在对象查看器里开 AutoSize，`TWinControl.DoAutoSize` 会把子控件往左上挪、和自定义排列互相覆盖（`wincontrol.inc:3441-3476`）。文档写明 AutoSize / ChildSizing / BorderSpacing 在这个类上无效。
- `Controller` 同 §3.1：`stored False`，对象查看器里隐藏，由窗口推送。
- `Left / Top / Width / Height` 只在 Parent 不是 `TTyToolWindow` 时存。
- `ChildClassAllowed` 拒绝 `TTyToolWindow`、`TTyToolWindowBar`、`TTyToolWindowActions`。
- **只由组件编辑器的"添加操作区"或 `EnsureActions` 创建**（`TabOrder := 0`）；不在窗口构造里自动建。
- **一个窗口只认第一个操作区**（`Actions`）。粘贴等途径多出来的不参与标题行排布：设计期显示在正文左上角，并画 `TyToolWindowNote` 提示；运行时隐藏。
- **孤儿**（Parent 不是 `TTyToolWindow`）：设计期画 `TyToolWindowNote` 提示（构造里没有 csNoDesignVisible，本来就看得见），运行时隐藏。

**排列**（重写 `AlignControls`，不调继承，带保护）：

- 可见子控件按 `Controls[]` 顺序从左往右排，RTL 下视觉上反过来。
- 每个子控件之间隔 `--toolwindow-header-gap`；每个子控件垂直居中，高度不低于它的 `Constraints.MinHeight`。
- 宽度不够时，整排**贴尾端对齐**，被裁掉的是开头的控件。

**首选尺寸**（窗口一律读 `GetPreferredSize(w, h, True)`，raw）：

- 宽 = 2×`--toolwindow-header-pad` + 可见子控件宽之和 + (可见子控件数 − 1)×`--toolwindow-header-gap`；运行时一个可见子控件都没有 → **0**。
  非 raw 的 `GetPreferredSize` 会把 0 宽换成 75px 默认宽（`control.inc:5609-5643`），空操作区会平白占掉一截。
- 高 = 最高子控件的 max(MinHeight, Height) + 2×`--toolwindow-header-pad`。
- 设计期没有子控件时：给一个边长为 `--toolwindow-header-height`（按 PPI 缩放，**不取标题行高**，否则定义绕回自己）的方形槽位，用 `--border` 描边，方便往里拖控件。

**外观**：类型键 `TyToolWindowActions`，无状态，`background: var(--toolwindow-header-bg)`（和标题行、标签行共用一个 token）。
放在"标题行减去底部分隔线那条带"的矩形里，不盖标题行的装饰。
"透明"做不到：ghost 子控件是按父控件解析出的**样式**填底，不是按已画的像素（`Base.pas:1170-1201`）。

---

## 5. 当前页与收起（栏的状态模型）

### 5.1 当前页

- published 且 stored `ActiveIndex: Integer`（选中索引流式存取的模式照 `TTyPageControl.ActivePageIndex`）；public `ActiveWindow`，setter 忽略 Parent 不是本栏的窗口。
- **`ActiveIndex` 跟随窗口身份**：调顺序后当前页还是那个窗口，索引跟着变。**不照抄** PageControl / TabSet "选中位置不变"的规则。
- `Loaded`：应用 `ActiveIndex`（-1 或越界、栏里又有窗口时取第一个，同 `PageControl.pas:392-395`），按生效的图片列表解析挂起的 `ImageIndex`，对每个窗口 `RelayoutHeader`，最后调 `TryFinishLoading`（§10.5）。
  `Loaded` 里应用 `ActiveIndex` 引起的激活**视同流式加载**：不发栏的 `OnChange`，也不发窗口的 `OnShow` / `OnHide`。这时 csLoading 已清，但窗体的 `OnCreate` 还没跑，理由同 §10.4。文档写明：启动时显示出来的当前页收不到 `OnShow`，首次填充内容要放在 FormCreate 里。

`ActivateWindow(W)` 的顺序（固定）：

1. `FActive := W`。栏收起着就到此为止，不显示窗口（§5.3）。
2. W：先 Exclude csNoDesignVisible，再 `Visible := True`（在 `FBarSwitching` 下）。
3. 旧页：先 Include csNoDesignVisible，再 `Visible := False`（在 `FBarSwitching` 下）。
4. `RelayoutHeader(W)`；运行时按 `Mouse.CursorPos` 重查悬停。
5. **只有焦点原来在旧页里**、且 `W.CanFocus` 时，调 `W.FocusFirst`；焦点不在旧页就不动。
   先藏旧页再聚焦新页会被 LCL 聚焦到窗体本身；新页还没显示就聚焦会抛 "cannot focus"（`customform.inc:1856-1880`）。
   布局应用的批次里跳过这一步（§10.4）。
6. 设计期：`OwnerFormDesignerModified` + `TyDesignerRefreshValuesProc`。

其他：

- 栏**不在加载中**时注册进来的窗口（组件编辑器新建、粘贴、运行时代码添加）成为当前页；布局应用（§10.4）和 `MoveWindow`（§9.5）自己管激活，关掉这条副作用。
- `ShowControl(本栏的某个窗口)`：运行时激活并展开；设计期只激活，不写 `Collapsed`。其他走继承。
- 代码设 `ActiveWindow` / `ActiveIndex` 只换当前页，**不改 `Collapsed`**（§10.4 靠这一点分开设两者）。
- 文档写明：`OnExit` 里不要把焦点设回被藏起的窗口里的控件。

### 5.2 当前页离开本栏

窗口被释放、设计期删除、代码改 Parent、`MoveWindow` 共用一条。不论走哪条路径（`Notification(opRemove)`，或 `SetParent` 的注销分支——`MoveWindow` 和直接改 Parent 都经过它）：

- 先记下它原来的位置、把 `FActive` 置 nil，再激活原位置上的下一个窗口，没有下一个就上一个，都没有就保持 nil（同 `TTyPageControl.UnregisterPage`，`PageControl.pas:303-308`）。先置 nil，回落用的 `ActivateWindow` 就不会去藏已经离开的窗口，也不会因为"焦点在旧页里"去挪焦点。
- `Notification(opRemove)` 同时清属于被移除窗口的悬停、按下部件和手势记录（§9.7）。
- 布局应用不走这条，按 §10.3 自己的回落规则。

### 5.3 收起 / 展开

published `Collapsed: Boolean`（default False）：流式存取，**只在运行时生效**，设计期永远按展开显示。**栏被拖空时不写它。**

侧栏和底栏相同，只在运行时：

- **收起**：先记下窗体的 `ActiveControl` 在不在当前页里；当前页在 `FBarSwitching` 下 `Visible := False`（发 `OnHide`），`FActive` 保留；焦点原来在里面的话，调 `GetParentForm(Bar).SelectNext(Bar, True, True)`。否则焦点掉到窗体本身，快捷键全部失灵（`customform.inc:901-910, 452-473`）。
  侧栏剩下图标条；底栏高度推成 0（**栏自己的 `Visible` 不动**，那是用户的属性）。收起时当前图标不画 `:selected`。
  布局应用批次内跳过焦点这一步，由 §10.4 第 7 步统一处理。
- **展开**：在 `FBarSwitching` 下把 `FActive` 显示出来（发 `OnShow`）。
- 栏收起时 `ActivateWindow` 只换 `FActive`。点击、`ShowControl`、对窗口设 `Visible := True`（包括当前页）引起的激活会同时展开栏。
- **底栏收起后界面上不留入口**（侧栏至少还有图标条），由应用提供开关（菜单项或快捷键设 `Collapsed := False`），文档写明；示例里有这个菜单项（§16）。

### 5.4 没有窗口的栏

- 栏用同一套几何自己画（window = nil，栏坐标）。
- 设计期：不收起，没有窗口也按展开算尺寸，显示一行"添加工具窗口"提示（resourcestring）。零高度的栏在设计器里点不中（`designer.pp:506-510` 要求点落在控件矩形内）。
- 运行时：侧栏只剩图标条（展开尺寸还记着），底栏高度为 0。拉宽边不起作用。

---

## 6. 栏 `TTyToolWindowBar`

### 6.1 类、摆放、尺寸

- 构造：`ControlStyle + [csAcceptsControls, csTripleClicks, csQuadClicks]`；`ChildClassAllowed` 只接受 `TTyToolWindow`。
  粘贴、运行时代码等途径漏进来的非窗口子控件不计入索引、不参与排布和布局保存；设计期画 `TyToolWindowNote` 提示，运行时隐藏。
- 栏重写 `SetChildOrder` 调 `SetControlIndex`（按 §2 的索引换算）并重建列表。**窗口顺序永远就是 `Controls` 顺序**：`TWinControl` 不重写 `SetChildOrder`（继承的是空实现），继承窗体里写的 `ffChildPos` 会被静默丢掉（`compon.inc:389-393`）。
- published `Placement: (tpLeft, tpRight, tpBottom)`，`default tpLeft`（等于构造值）。
  - 图标条贴哪边、边缘区在哪边、侧 / 底的判断**一律按 `Placement`，不看 `Align`**。
  - 设计期或运行时改 Placement（非 csLoading）时顺手把 `Align` 设成对应值，同时把 `Left`（左右）或 `Top`（底）设到父控件同侧的最外边，让它排在同向对齐兄弟的最外侧（[[lcl-code-created-align-order]]）。`Align` 仍然 published，复杂布局可以自己改，但几何不跟着 `Align` 变。
  - 侧 ↔ 底的 Placement 变化，运行时栏里有窗口就忽略（会破坏"不能跨到底栏"的规则和布局字符串的键）。
  - 定稿时新加（改 Placement 顺带设 Align）。
- published `ExpandedSize: Integer`（**逻辑 96-DPI 像素**）：沿栏的轴向的内容尺寸。侧栏不含图标条和边缘区；底栏含当前页的标签行、不含边缘区。
  - 构造值 240，声明 `default 240`，侧栏和底栏共用一个默认值（Pascal 的 default 只能是常量，不能按 Placement 分；见 [[tabstop-declared-default-must-match]]）。
  - setter 钳到 0..99999（和布局串的 1-5 位纯数字对齐）；拉宽、设计器改大小、代码、读取布局都经过它。
- **尺寸推导**（`chrome` = 单边 `TyChromeInsetLogical`，见下）：
  - 侧栏 `Width` = 图标条 + 2×chrome +（运行时收起或没有窗口 ? 0 : 边缘区 + 有效内容）。
  - 底栏 `Height` =（运行时收起或没有窗口 ? 0 : 2×chrome + 边缘区 + 有效内容）。
  - 设计期不算收起，没有窗口也按展开算。
  - 侧栏 `Width` / 底栏 `Height` 重新声明为 stored False（用 stored 函数按 Placement 判断）。
  - 有效内容 = `MulDiv(ExpandedSize, PPI, 96)`，排布时按 §6.2 收窄。**收窄只影响这一次排布，不写回 `ExpandedSize`**——否则在 FormCreate 里（DPI 缩放和窗体尺寸都还不是最终值）一收，用户的宽度就永久变小了。
  - `AutoAdjustLayout` 在继承之后按新 PPI 重新推。
- **最小尺寸**由重写 `ConstrainedResize` 给，和推导走同一个分支。下面的"收起或没有窗口"只指运行时，设计期不算收起，没有窗口也按展开算。侧栏：收起或没有窗口 = 图标条 + 2×chrome，否则 = 图标条 + 2×chrome + 边缘区 + content-min；底栏：收起或没有窗口 = 0，否则 = 2×chrome + 边缘区 + content-min。**不去写用户的 `Constraints`**。
- **设计器里拖栏的边改大小**：只有 csDesigning、非 csLoading，并且不在栏自己推导尺寸（`FDeriving`）或 `AutoAdjustLayout`（`FDpiAdjusting`）期间的 `SetBounds`，才去掉图标条、边缘区、chrome，再 `UnscaleI` 写回 `ExpandedSize`。其他来源的 `SetBounds`（推导、收窄、DPI、Align）一律不写回，否则收窄值会写回、DPI 会二次缩放。
- **栏自己的主题钩子**：栏按 `(PPI, model identity, ThemeVersion, RTL, Placement)` 缓存图标条宽、边缘区宽和 chrome；在 `Invalidate` 重写里、继承的 `AutoAdjustLayout` 之后各查一次，变了就带重入保护重推尺寸并 `Realign`（理由同 §3.4）。
- **边框**：窗口从不画栏的边框。栏的类型键在基础主题里没有边框和圆角；皮肤给栏加了边框时，栏的 `AdjustClientRect` 按**静止态**样式内缩：`TyChromeInsetLogical(ResolveStyle(类型键, TyStyleClassFor(Self, StyleClass), [tysNormal]) 叠上 StyleOverride)`。不用 `CurrentStyle`：它带 hover / active，内缩量会随状态变（`Base.pas:574-576`），而悬停只 Invalidate、不 Realign。分隔线画在栏自己的边缘区里，窗口盖不到。

### 6.2 空间不够时的收窄

定稿时新加。

- 只看**同轴**的非栏对齐兄弟（侧栏看 alLeft / alRight，底栏看 alTop / alBottom，alClient 不算）：可用 = 父控件调整后客户区沿轴尺寸 − 这些兄弟的尺寸 − 同轴所有栏的固定部分（图标条、边缘区、chrome）。
- 同轴的两条侧栏一起算，用各自**未收窄**的有效内容，不读对方当前宽度：两者之和放得下就各用各的；放不下按 `ExpandedSize` 比例分，各自不低于 content-min。
- 编辑区可以被压到 0（和 §6.4 最大化一致）。

### 6.3 拉宽边

- 边缘区在栏内部、内容区靠编辑区的一侧（底栏在顶边），宽度 `--toolwindow-edge-size`。
  不用外部 `TTySplitter`：它按几何找目标（`Splitter.pas:283-307`），吸附到 0 会把图标条一起吞掉（`:108-111`），上限只按父控件客户区减自身宽算、不管其他对齐兄弟，还可能把另一条栏挤出去（`:322`）。
  也不直接复用 `TySplitterNewSize`：它默认吸附到 0，关掉吸附又钳在最小值上，两种都和下面的规则冲突。
- 拖动时**实时**写 `ExpandedSize := 起点 + UnscaleI(位移)`，位移按增长方向取符号：左栏向右、右栏向左、底栏向上为正（同 `TySplitterNewSize` 对 alRight / alBottom 取反，`Splitter.pas:103-106`）；和 Grid 拖列宽一致（`Grid.pas:6756-6767`）。写入不低于 content-min。
- **吸附收起**（定稿时新加，依据：VS Code 的分隔条总能吸附关闭，`paneCompositePart.ts:112-117`）：未钳的原始尺寸小于 content-min 的一半时，**实时**按收起排布（侧栏只剩图标条宽，底栏高度 0），`ExpandedSize` 保持拖动开始时的值；拖回阈值以内恢复展开、继续实时写。松手时处在收起排布，才写 `Collapsed := True`。
- 拉宽过程中收到 `LM_CANCELMODE`、Application 失活，或栏的 `Collapsed` / `Placement` / 最大化状态被改，就结束拉宽，`ExpandedSize` 恢复成起点。
- 栏里没有窗口、底栏最大化期间、设计期：边缘区不起作用。

### 6.4 最大化（底栏）

- 只在运行时有，不存进 .lfm，也不存进布局字符串。
- 最大化：高度取父控件扣掉其他对齐兄弟后的全部可用高度（同一父控件里的 alClient 兄弟被压到 0）。还原高度就是 `ExpandedSize`，最大化期间它不变。
- 最大化期间订阅 `Parent.AddHandlerOnResize`；还原、`SetParent`、销毁时退订。切换时 `RelayoutHeader`。
- 收起、栏变空、`SetParent` 之前先还原（并 `RelayoutHeader`），再展开时用还原高度。

### 6.5 图标条（侧栏）

- 图标条贴在栏的外侧边（左栏在最左、右栏在最右），宽 `--toolwindow-strip-size`，图标项 `--toolwindow-strip-item-size`，字形 `--toolwindow-glyph-size`。
- 图标从上往下按窗口顺序排。**放不下时**（定稿时新加，和底栏标签同一规则，含预留溢出按钮后重排，§7.3）：按顺序放，遇到第一个放不下的就停，它和后面的全部进溢出菜单；当前页的图标如果不在已放的里面，追加到末尾，再从它前面一个开始往前挤掉，直到放得下。末尾显示溢出按钮。
- 溢出按钮：同一部件内松手才弹出；设计期回答 0；菜单项的动作是激活该窗口，栏收起时一并展开，不受 §9.3 的防抖限制。菜单里的窗口不能拖，跨侧用 `MoveWindow`。
- 条上的部件在栏自己的像素里，栏直接处理输入，不需要代画。
- 设计期点图标切换当前页。应答规则照 `TabStrip`（`TabStrip.pas:2232-2248`）：按下和拖动回答 1，松开回答 0 交还（[[designer-hittest-gesture-consistency]]）。
  **切换时机不照 TabStrip**（它按下就切，`:2307`）：切换写在 `CM_DESIGNHITTEST` 的松开分支里，先切换再回答 0——回答 0 之后设计器不会再调 `MouseUp`（`designer.pp:2486-2494`）。和 §7.4 底栏同一写法。
- 重写 `BeginAutoDrag`，图标条区域不起 LCL 拖动。

### 6.6 事件

| 事件 | 什么时候发 | 不发 |
|---|---|---|
| 栏 `OnChange` | 运行时当前页**换了窗口**（点击、代码设 `ActiveWindow` / `ActiveIndex`、`MoveWindow`、直接改 Parent、当前页离开本栏） | 设计期；csLoading；栏 `Loaded` 里应用 `ActiveIndex`；布局应用批次内；调顺序引起的 `ActiveIndex` 数值变化 |
| 栏 `OnCollapse` / `OnExpand` | 运行时 `Collapsed` 真正变了（点击、代码、吸附收起、对当前页设 `Visible := False`、`MoveWindow` 展开目标栏） | 设计期；csLoading；布局应用批次内 |
| 窗口 `OnShow` / `OnHide` | 运行时窗口显示 / 隐藏（激活、收起、展开）；普通布局应用批次内照常 | 设计期；栏 `Loaded` 里应用 `ActiveIndex`；加载结束时应用挂起计划的批次内（§10.4） |
| manager `OnCanMoveWindow` | 跨栏：拖动悬停、放下、调用 `MoveWindow` 时，排队的移动执行前再问一次 | 同栏调顺序；直接改 Parent；布局应用；设计期 |
| manager `OnWindowMoved` | 运行时窗口的栏或索引真正变化之后：手势、`MoveWindow`、`WindowIndex`、同一 manager 下直接改 Parent | 流式加载；设计期；`LoadLayoutFromString` / `ResetLayout` |
| manager `OnLayoutApplied` | Load / Reset 的批次结束后一次；挂起计划应用后用 `QueueAsyncCall` 推到加载结束之后 | — |

- `MoveWindow` 的发送顺序：源栏 `OnChange`（W 原来是当前页时）→ 目标栏 `OnExpand`（原来收起时）→ 目标栏 `OnChange` → `OnWindowMoved`，都在 `EnableAlign` 和焦点恢复之后。源栏从不发 `OnCollapse`（拖空不写 `Collapsed`）。
- 名字照库里已有的：`OnChange` 同 `TTyPageControl`，`OnCollapse` / `OnExpand` 同 `TTyExPanel`。v1 不做 `OnChanging`。
- 事件处理里不许释放栏、窗口或 manager（用 `Application.ReleaseComponent`）。

### 6.7 键盘

- 图标条不是 Tab 停靠点（`TabStop` published default False），不拿焦点。
- 不提供键盘拖动。所有动作都有公开 API（`ActiveWindow`、`Collapsed`、`MoveWindow`、`WindowIndex`）。

### 6.8 右键菜单

- **不内置菜单**。库里只有文字编辑控件在 `PopupMenu` 为空时兜底一个（`Edit.pas:2042-2052`）；内置还要加 .po 字符串。应用用 `MoveWindow` 自己做"移到另一侧"。
- 右键从不武装拖动、从不切换。
- public `WindowAtPos(X, Y)`（不在图标 / 标签上返回 nil，同 `IndexOfTabAt`）；只读 `ContextWindow`。
- 图标或标签上的点：`DoContextPopup` 先设 `ContextWindow`，再调继承。
- **不在图标或标签上的点**（包括键盘菜单键的 (-1,-1)：栏不拿焦点，这种请求一定来自子控件）：重写的 `DoContextPopup` **不调继承**（不触发 `OnContextPopup`，Handled 保持 False），`ContextWindow` 置 nil，并记一个标志；`GetPopupMenu` 看到标志就返回 nil。两步都要做：LCL 先调 `DoContextPopup` 再调 `GetPopupMenu`（`control.inc:2484-2492`），只改后者挡不住 `OnContextPopup`。这样子控件的右键请求继续冒泡到窗体。
- 底栏标签上的右键经 `HeaderContextPopup` 进来；标签行里不在标签上的右键由当前页吞掉，不冒泡到窗体（§3.6）。

---

## 7. 底栏标题行共用

### 7.1 为什么由当前页代画

标签行的像素属于当前页（窗口化子控件自己拥有那块像素），操作区又必须是窗口的子控件（§1 #4），
所以当前页替栏画标签、溢出按钮、分隔线、固定按钮，输入转给栏；悬停、按下、溢出集合、最大化状态都存在栏上。

- 栏**忽略非当前页窗口转来的 `HeaderMouseMove` / `HeaderMouseLeave`**：切换后旧页迟到的 leave 不许清掉 §5.1 第 4 步重算的悬停。

比较过的另外两种（核实结论）：

- **内部标签控件每次切换挂到当前页上**：给窗口化控件换父控件会销毁重建句柄（`control.inc:4421-4437` → `wincontrol.inc:6427-6441`），手势中途丢捕获。否决。
- **栏在窗口上面叠一层标签 / 按钮控件**（`TTyScrollBox` 的滚动条就这么叠，`ScrollBox.pas:615-622`）：可以做到按下就切、支持双击，但每次加页、加载、切换都要重新提到最上面，要替别人画标题行背景，GTK2 / GTK3 / Qt / Cocoa 上叠放是否正确只能逐个真机验。作为备选记录，不做。

### 7.2 接口

栏实现 `ITyToolWindowHeaderHost`，窗口用 `Supports(Parent, ...)` 找：

```pascal
HeaderMode(W): TTyToolWindowHeaderMode;
HeaderGeometry(W): TTyToolWindowHeaderGeom;
PaintHeader(W; P: TTyPainter; const Geom);
HeaderZoneAt(W; X, Y; out R: TRect): TTyToolWindowHeaderZone;   // none | tab(i) | overflow | separator | maximize | collapse
HeaderMouseDown / HeaderMouseMove / HeaderMouseUp / HeaderMouseLeave(W; ...);
HeaderHint(W; X, Y; out S: string; out R: TRect): Boolean;
HeaderContextPopup(W; X, Y);
```

全部接受 `W = nil`，表示栏坐标（没有窗口时栏自己画自己）。

- 几何照 `TTyBreadcrumb` 的拆法写成纯函数：可见计划、排布、`IndexAt` 三个函数（`Breadcrumb.pas:140-159`），`IndexAt` 扫描排布自己产出的矩形，是排布的精确逆运算；输入是一个 record。侧栏和底栏两种模式一起定。
- 栏按 `(W, 行宽, PPI, model identity, ThemeVersion, RTL, 窗口列表戳, 标题戳, 本窗口操作区的 raw 首选宽, 生效的标题行高, 是否最大化)` 缓存（底栏模式的标题行高取栏统一算出的值，§3.4）。
- 五个使用者读同一份结果：窗口绘制、运行时命中、`CM_MASKHITTEST`、`CM_DESIGNHITTEST`、栏自绘。
- `HeaderHint` 的文字：标签用 `StripHint`，空的时候用 `Caption`；最大化、还原、收起、溢出用 resourcestring。

### 7.3 排布规则

- 从尾端往前：`[收起][最大化/还原][分隔线][操作区][溢出][标签…]`。
- 固定部件（收起、最大化、分隔线）永远不缩。
- 操作区保持 raw 宽，直到标签区缩到 `--toolwindow-tab-area-min`；再往下才压缩操作区（贴尾端，裁掉开头的控件）。
- 标签按顺序放，**遇到第一个放不下的就停**，它和后面的全部进溢出菜单，后面短的也不往前补；当前页的标签如果不在已放的里面，追加到末尾，再从它前面一个开始往前挤掉已放的标签，直到放得下（`compositeBar.ts:532-580` 同形）。放不下的**整个**收进溢出菜单，标题文字不截断——只有当前页的标签连单独放都放不下时才加省略号。只在确实有标签被收起时才预留溢出按钮：先从可用宽度里扣掉溢出按钮的宽度，再按上面的规则重排一次（仍然保证当前页留在行上，挤掉的是它前面的非当前页项）。
  （依据：VS Code 面板把放不下的标签收到 "Additional Views" 按钮后面、当前标签始终可见、工具栏先拿宽度，`paneCompositePart.ts:689-721`。VS Code 是否也截断标题文字没查过，没照抄。）
- RTL：整套几何算一次，再用 `BidiFlipRect` 按行宽镜像。Placement、图标条、边缘区保持物理方向（项目的 RTL 范围规则：不镜像 Align）。
- 标签只显示文字（VS Code 面板默认），不显示图标。

### 7.4 手势

- 运行时：按下标签只武装；**在同一个标签上松开才切换**（LCL 在 Click / MouseUp 之前已经放掉捕获，`control.inc:2827-2846`）。溢出、最大化、收起在同一部件内松开才生效。点当前页的标签什么都不做。
- 带多击标记的按下（§9.2）在溢出、最大化、收起上不生效。
- 拖过阈值就是调顺序（§9），不切换。
- 设计期：`CM_DESIGNHITTEST` 只在标签上和武装期间回答 1；松开分支里先切换，再回答 0。溢出、最大化、收起在设计期回答 0（它们改模型且没有撤销）。设计期不做悬停（设计期控件收不到 enter / leave，`application.inc:604-605`）。
- 标签上不提供双击手势：切换后第二次按下落在新窗口上，多击计数会重置（`controls.pp:3187-3240`）。
- 溢出菜单是 `TTyPopupMenu`（Owner = 栏，和图标条共用），只在 `HandleAllocated` 时弹出；菜单项的动作是激活该窗口。

---

## 8. 图标、提示

- `ImageName` 是持久键，`ImageIndex` 是它的视图（照 `TabSheet.pas:90-100, 159-212` 的约定）。`ImageIndex` 声明为 `ImgList.TImageIndex`，LCL 的 `TImageIndexPropertyEditor` 就会顺着 `Parent = 栏 → Images` 自动挂上。
- 图片列表：`Bar.Images`（`TCustomImageList`），为空时读取时回落到 `Manager.Images`。不做"借出"。
  - 文档写明：只设了 `ImageIndex`、没设 `ImageName` 的窗口，要在两侧之间移动就得用 manager 上的共享列表。
  - 文档写明：属性编辑器只看栏自己的 `Images`（`graphpropedits.pas:713-728`），看不到 `Manager.Images` 回落；只在 manager 上设列表时，对象查看器里 `ImageIndex` 的下拉是空的，这种用法应该设 `ImageName`。
- 挂起的 `ImageIndex` 在**栏的 `Loaded`** 里解析，不在 csLoading 期间解析（否则解析到先 fixup 的那个列表）。
- 订阅列表变化：栏记住 `FSubscribedList`。生效列表变了（`Bar.Images`、`Manager`、`Manager.Images`、manager 被移除），**先对旧列表 `UnRegisterChanges` 再注册新的**，并 `FreeNotification`。只有被移除的正是 `FSubscribedList` 时才跳过注销——同一个 link 不注销就重复注册，旧列表析构时死循环（`imglist.inc:1692-1698, 2706-2711`）。
- 着色：照 glyph 按钮（`GlyphButtons.pas:645-658`），把图标着成图标项自己类型键各状态的 `TextColor`。本库的列表（`TTyVirtualImageList` 及其子类）一律用 `RenderIndex(i, px)`（或 `TyRenderImage`）取一张调用方持有的位图——字体字形出来是列表自己的 `GlyphColor`，**不是墨色**（`ImageCollection.pas:1477-1490`）；再 `TyTintBitmapAlpha(bmp, 墨色)` + `TyFadeBitmapAlpha(bmp, TyAlphaOf(墨色))`，用完释放。不给列表加新接口。**外来列表默认不着色**（部分 widgetset 上物化出的位图可能丢了 alpha，`ImageDraw.pas:275-279`）。
- 缓存：先不做，照现有调用方每次绘制都渲染。要做就先测，键 `(名字, px, ARGB)`，按 `(列表身份, IconFont.Version, Collection.ChangeStamp, model identity, ThemeVersion, PPI)` 清，**LRU 上限**（同 `TyImageCacheDefaultCapacity = 64`），不接受动画插值出来的颜色。
- **图标条提示**用 `StripHint`，空的时候用 `Caption`，由栏处理 `CM_HINTSHOW`。**不用 `Hint`**：LCL 顺着父链找第一个非空 Hint（`application.inc:33-41`），窗口里所有没设 Hint 的控件都会冒出"资源管理器"。

---

## 9. 拖放

### 9.1 能拖什么

- **侧栏图标**：在本侧调顺序，或拖到**同一个 manager、同一个窗体**上的另一侧栏。
- **底栏标签**：只能在底栏里调顺序。
- 不能当拖动把手的：标题行、正文、操作区、拉宽边、溢出 / 最大化 / 收起按钮、溢出菜单里的项。
- 只在运行时（设计期跨侧用组件编辑器的菜单项，§11）。

### 9.2 手势状态机

每条栏一个引擎，状态：Idle、Armed、Dragging、Cancelled。底栏的输入经当前页的 `HeaderMouse*` 转进来。

**按下**（左键，落在图标或标签上）：

- 每次按下都新建一条记录，清掉 Cancelled、吞点击标志和目标——上一次手势丢了松开，也不影响这次。
- 记录：窗口（引用，不是索引）、源栏、屏幕原点（捕获者的 `ClientToScreen`）、源索引、窗口原来是否当前页、栏原来是否收起、是否多击。
- 带 `ssDouble / ssTriple / ssQuad` 的按下：照常新建记录，**可以武装拖动**，但记录打上多击标记，阈值以内松开**永远不算点击**。
  （修正批准稿"多击按下什么都不做"：LCL 把双击时间内、3px 以内、同一控件同一按键的第二次按下一律标成多击，`controls.pp:3205-3233`；那样点一下图标、马上按住同一个图标拖，就拖不起来。）
- 右键、中键从不武装。**按下时什么都不激活**（§9.3）。

**移动**（Armed）：

- 没有 `ssLeft` → Idle。
- 阈值 `TyToolWindowDragThreshold(Font.PixelsPerInch) = Max(1, MulDiv(6, PPI, 96))`，屏幕像素，**侧栏和底栏都用 `Max(|dx|, |dy|)`**。
  `TabStrip` 只算沿条方向的位移（`TabStrip.pas:2350-2354`），照抄到竖着的图标条上，往右横拖永远拖不起来。底栏标签竖着拖出标签行也进入 Dragging，显示 `crNoDrop`，松开即取消。
- 过阈值 → Dragging。

**进入 Dragging**：

- 置吞点击标志；`Application.CancelHint`。
- `Screen.BeginTempCursor(拖动光标)`。控件自己的 `Cursor` 在捕获期间管不到别的窗口（`control.inc:4509-4520`；Win32 的 `SetCursor` 只在自己句柄里找子窗口）。
- 装上 `Application.AddOnKeyDownBeforeHandler`、`AddOnDeactivateHandler`、`Screen.AddHandlerActiveFormChanged`，并新建一个**只在拖动期间存在**的 `TTimer`（约 100 ms，先例 `tyControls.Accel`）。
  **不用 `AddOnIdleHandler`**：`Application.OnIdle` 或处理器链上任一个把 Done 置 False，后面的就不跑（`application.inc:471-477, 743-751`）；`TPopupMenu.PopUp` 直接 `ReleaseCapture` 抢走捕获的情况只有轮询抓得到。
- `CaptureConfirmed := HandleAllocated and (GetCaptureControl = 捕获者)`。
- 标记 manager 正在拖；源图标用图标项的 `:active` 状态画到手势结束。

**移动**（Dragging）：

- 没有 `ssLeft` → 取消。
- 否则命中测试（§9.4）。`(栏, 槽位)` 变了才调 `旧栏.ClearDropFeedback` / `新栏.SetDropFeedback(slot)`，两者都只 invalidate。
- 光标要换时：先 `BeginTempCursor(新)`，再 `EndTempCursor(旧)`。

**松开**（在继承的 `MouseUp` 之后）：

- Armed，落在同一个图标 / 标签上、没有多击标记 → 点击（§9.3）。
- Armed，其他情况 → 什么都不做。
- Dragging → 在松开点重算命中、拷到局部变量、调 `EndGesture`，**提交（§9.5）作为最后一句**，提交之后不再碰 Self。
- Cancelled → 什么都不做，也不算点击。

**重写**：

- 按下落在图标 / 标签区域时吞掉 `Click` 和 `DblClick`（栏 published 了 OnClick，LCL 在 MouseUp 之前调 Click）。
- `MouseLeave` 和转发来的 `HeaderMouseLeave` **从不解除武装**：捕获期间 LCL 本身不发 leave，但 Win32 的 `WM_MOUSELEAVE` 可能在捕获者身上触发一次（`win32callback.inc:2337-2345`）。

### 9.3 点击（运行时，阈值以内、在同一项上松开）

侧栏图标：

- 不是当前页 → 激活；栏收起着就展开。
- 是当前页 → 切换 `Collapsed`。
- 防抖：距离**这个窗口上一次真正执行的点击动作**不到 300 ms 的点击忽略（VS Code 同形状的保护，`paneCompositeBar.ts:810`）。时钟走一个可重写的函数，无头测试好控制。
  GTK3 上第二次按下先来普通按下、再来带 ssDouble 的双击消息，双击有多击标记保护；但 GTK3 不下发三击消息（`GDK_3BUTTON_PRESS` 直接丢弃，`gtk3widgets.pas:1181` 附近），三击靠这个防抖。

**为什么松开才切**（用户 2026-09-17 拍板）：按下就切的话，按住一个没显示的图标准备拖走，这一页先闪出来（收起的栏还先展开、焦点可能跳进去）；拖走后原侧剩下一个用户没选过的页；Esc 取消后切换也撤不回。

底栏标签：不是当前页 → 激活；是当前页 → 什么都不做（只有 VS Code 活动栏会切换收起）。

### 9.4 命中测试（manager 上的纯函数，每次移动重建探测矩形）

**候选栏**：

- 源栏自己永远是候选，只算它的图标条 / 标签行（冲突不冲突都一样，用来栏内调顺序）；源栏自己冲突时，不再找其他候选。
- 其他栏：注册在源栏的 manager 上、没因 Placement 冲突被排除（§10.6）、`IsVisible`、不在 csDestroying、`GetParentForm` 和源栏相同。
- 没有 manager 时只有源栏自己。

对每个候选：

- `LP := Bar.ScreenToClient(P)`；可用矩形 = 栏的 ClientRect 与每一级祖先 ClientRect 的交集。
- 落在嵌套于候选栏内部的另一条 `TTyToolWindowBar` 里的点，不算这个候选。
- 运行时有句柄时：`FindControlAtPosition(P, True)` 落在别的窗体上 → 没有目标（非模态浮动窗体盖在上面的情况）；返回 nil → 信几何。
- 不做跨窗体（Wayland 下没有全局坐标）。

**侧栏图标的落点**：

- **图标条**（源栏或另一侧栏）：`TyToolWindowSlotAt(已排布的图标矩形, P)` 按已排布图标的中点找空隙，交叉轴钳住。已排布图标 k 之前的空隙映射到它对应窗口的索引；最后一个已排布图标之后（含溢出按钮所在位置）映射到它的窗口索引 + 1。空操作判断和 `FinalIndex` 都用映射后的窗口索引算——当前页被强制留在条上、前面有窗口被溢出收起时，已排布图标不是窗口列表的前缀，不能直接拿空隙序号当索引。
  `TyDropIndexAtPoint` 不能用：它返回 0..Count-1、默认最后一个，"最后一个之后"和"最后一个之前"是同一个答案（`TabStrip.pas:1753, 1779-1781`）。
- **另一侧栏的其他任何地方**（内容、标题行、边缘区，包括收起的和空的栏）：slot = 该栏图标条上"最后一个已排布图标之后"那个空隙的值（没有溢出时就是窗口数），插入线画在同一个位置。内容区被当前页（窗口化子控件）盖着，反馈只能画在图标条上。
- 另一侧栏且 `CanMoveWindow` 为 False（每个目标栏每次手势只问一次、缓存）：没有目标。
- 其他所有地方（源栏自己的内容、底栏、编辑区、别的窗体、窗体外）：没有目标，`crNoDrop`；在这里松开就是取消。

**底栏标签的落点**：只算源底栏的**标签行区域**（§3.6 定义），按阅读顺序在**可见标签**之间找空隙；RTL 下先把指针镜像一次再扫。可见标签 k 之前的空隙映射到那个窗口的索引，最后一个可见标签之后映射到它的索引 + 1。底栏的正文、边缘区和底栏外都没有目标，显示 `crNoDrop`，在这里松开就是取消。

**空操作与最终索引**：同一条栏且映射后的 slot 为 src 或 src+1 → 空操作（`crDrag`，不画线）。`FinalIndex := slot - Ord(同栏 and (slot > src))`。

### 9.5 提交

**同一条栏**：窗口之间 `SetControlIndex`（按 §2 换算）。不激活、不展开、不换父。即使是从当前页自己的处理里发起也安全（不重建句柄）。

**另一侧栏**：同步调 `Manager.MoveWindow(W, Target, FinalIndex)`——源栏不在 W 里面，LCL 在 MouseUp 之前已放掉捕获。

- W 成为目标栏的当前页，目标栏 `Collapsed := False`，展开到它的 `ExpandedSize`。
- 源栏按 §5.2 回落当前页。**源栏的 `Collapsed` 不改。**
- 源栏拖空了：因为没有窗口，内容不显示；**不写 `Collapsed`**，图标条保持 token 宽度，拉宽边不起作用，仍然是放置目标。
  （如果写成收起：用户存了布局，新版本给这一侧加了窗口，读回来是收起的，看不到新窗口。）
- `MoveWindow` 内部：记下焦点控件 → `DisableAlign` 两条栏 → `W.Parent := Target`（`SetParent` 里依次完成：从源栏注销并按 §5.2 回落当前页、注册到目标栏、推 Controller、按目标栏的列表重新解析图标；**W 里所有句柄重建**，LCL 换父控件的固有行为）→ 目标栏激活并展开 W → `EnableAlign` → 原焦点控件在 W 里且 `CanFocus` 时还给它 → 事件（§6.6）。

### 9.6 为什么不用 LCL 的 DragManager

- `FindControlAtPosition` 递归到最深的子控件（`controls.pp:3449-3450`），拿到的是窗口内容或操作区，不是栏；`DragOver` 只发给最深控件、不冒泡，拖到内容区上根本收不到。
- 用户自己写了 `OnDragOver` / `OnDragDrop` 的控件会被询问，可能直接接住一个工具窗口拖动对象。
- 栏 published 的 `OnStartDrag` / `OnEndDrag` 会为内部手势触发，用户挂的处理器会误响应（`Base.pas:410-416`）。
- `DragMode = dmAutomatic` 在控件任何位置左键按下都起拖（`control.inc:2284`），包括操作区和拉宽边。

### 9.7 取消

`EndGesture` 幂等：弹出**唯一一次** `BeginTempCursor`（不配对的 `EndTempCursor` 会抛）、移除所有处理器、释放计时器、清目标的反馈、清 manager 的拖动状态。

调用它的地方：

- **Esc**：`KeyDownBefore` 处理器里（`Key := 0`）。图标条不拿焦点，按键到不了栏的 `KeyDown`。只吃掉 KeyDown，Esc 的 KeyUp 仍会到达焦点控件，文档写明。
- 源捕获者或任何注册栏看到没有 `ssLeft` 的移动。
- 捕获者（栏，或转发的当前页）收到 `LM_CANCELMODE`（`ShowModal`、`Application.HandleException` 会发）。
- Application 失活；`ActiveFormChanged` 到别的窗体。
- 计时器检查：`CaptureConfirmed` 且 `GetCaptureControl <> 捕获者`。
- 源栏、窗口、目标栏、manager 的 `opRemove`：不论 Armed 还是 Dragging，都清掉手势记录（Dragging 再走 `EndGesture`），同时清掉属于被移除窗口的悬停和按下部件。
- `MoveWindow`、`LoadLayoutFromString`、`ResetLayout`，或参与的栏改了 `Collapsed / Placement / Manager`。
- `Manager.CancelDrag`。
- 栏和 manager 的析构（同时 `RemoveAllHandlersOfObject`、`Application.RemoveAsyncCalls`）。

**`CaptureChanged` 从不取消**：LCL 在 `WMLButtonUp` 里先放捕获、再 Click、再 MouseUp，Win32 上捕获变更通知在**每一次正常松开**、提交之前就到——在里面取消会让所有放下都失败。GTK / Qt 发给新的捕获者，Cocoa 根本不发。

### 9.8 反馈外观

- 新类型键 `TyToolWindowDropIndicator`，`background: var(--toolwindow-drop-color)`；粗细 `--toolwindow-drop-size`（密度块），按 PPI 缩放。
- 侧栏：**目标栏**在自己的 `RenderTo` 里、`EndPaint` 之前画进 BGRA 层（[[painter-bgra-overwrites-canvas-gdi]]）。只在 `(栏, 槽位)` 变化时 invalidate。
- 底栏：`Bar.PaintHeader` 在当前页的 `RenderTo` 里画，栏 invalidate 那个窗口。
- 不画拖影，不加浮层。拖动过程中不实时挪位置（底栏标签也是松开才 `SetControlIndex`）。
- 不照抄 TreeView 的拖放标记：它借了 `TyTreeNode:selected` 的颜色、写死 alpha、插入符号没按 DPI 缩放。

### 9.9 接口

```pascal
TTyToolWindowManager
  function MoveWindow(AWindow: TTyToolWindow; ATargetBar: TTyToolWindowBar;
    AIndex: Integer = -1): Boolean;
  function CanMoveWindow(AWindow: TTyToolWindow; ATargetBar: TTyToolWindowBar): Boolean;
  procedure CancelDrag;
  function IsDragging: Boolean;
  property OnCanMoveWindow: TTyCanMoveWindowEvent;
    // (Sender: TObject; AWindow: TTyToolWindow; ATargetBar: TTyToolWindowBar; var AAllow: Boolean)
  property OnWindowMoved: TTyWindowMovedEvent;
    // (Sender: TObject; AWindow: TTyToolWindow; ASourceBar: TTyToolWindowBar; AOldIndex: Integer)

TTyToolWindow
  property WindowIndex: Integer;   // public，stored False；没有 manager 也能调栏内顺序
```

**`MoveWindow`**：

- `AIndex` 是在目标栏窗口里的最终位置，钳住；-1 表示末尾。目标是同一条栏就是调顺序。
- 返回 False、什么都不改：W 或目标栏没注册在这个 manager 上；源栏或目标栏因 Placement 冲突被排除（同一条栏调顺序除外）；两者父窗体不同；侧 ↔ 底；任一参与者 csLoading；从事件处理里重入；跨栏且 `CanMoveWindow` 为 False。
- **同一条栏**：同步（不重建句柄）——除非这个窗口还有排队的移动，见下。
- **跨栏**，以下情况同步：从拖放提交调用；csDesigning（组件编辑器菜单项：不发事件）；`GetParentForm(W)` 还没 `Showing`（FormCreate 里）。
- **跨栏的其他情况排队**（`Application.QueueAsyncCall`），`GetCaptureControl` 在 W 里时再排一次；返回 True 表示"已接受"。
  理由：按钮就在要移动的窗口里时（比如操作区里放一个"移到左边"），同步换父会在按钮自己的点击处理里销毁它的句柄；而这种情况检测不出来——Click 之前捕获已释放，工具按钮也不拿焦点。
- **队列规则**：
  - 排队的移动执行时重新做全部结构检查、再问一次 `CanMoveWindow`，不通过就静默丢弃（不发事件）。
  - 窗口、栏、manager 的 `opRemove` 从队列里删掉涉及它的项。
  - 某个窗口还有排队的移动时，对它的 `MoveWindow`（包括同栏）和 `WindowIndex` 也进同一个队列，保证按调用顺序执行。
  - 文档写明：排队时调用返回后 `W.Bar` 还是旧栏。

**`CanMoveWindow` / `OnCanMoveWindow`**：结构检查 + 事件；同一条栏永远 True。只管跨栏，**必须没有副作用**。被否决的目标在悬停时就不画插入线、显示禁止光标，而不是松开后默默不动。

没有 manager 时：只有栏内 / 行内调顺序。

---

## 10. 布局保存

### 10.1 接口（manager）

```pascal
function SaveLayoutToString: string;
function LoadLayoutFromString(const AText: string): Boolean;
function ResetLayout: Boolean;
procedure CaptureDefaultLayout;
property OnLayoutApplied: TNotifyEvent;
```

- 没有 manager 的栏不能保存。
- `Load` / `Reset` 返回 False 且什么都不改：文本格式错；manager 在 csDesigning 或 csDestroying；没有注册任何栏。（Reset 不会遇到"还没有默认布局"：非加载期间调用会先记，加载期间调用会挂起，§10.5。）
- True 表示已经应用，或者已接受、挂起 / 排队（§10.5）。
- 格式错不抛异常（布局是偏好，会过期，和 Grid 布局字符串同一策略）。

### 10.2 格式

```
TYTOOLLAYOUT/1|left=240,0|leftWins=Explorer,Search|leftActive=Explorer|right=300,1|rightWins=Outline|rightActive=Outline|bottom=200,0|bottomWins=Problems,Output|bottomActive=Output|end
```

**解析**：

- 按 `|` 切，再按 `,` 切，用**普通字符切分**，不用 `TStringList.DelimitedText`（它仍然特殊处理引号）。
- 第一段必须正好是标签 `TYTOOLLAYOUT/1`。
- **最后一段必须正好是 `end`**，且只出现一次——没有结束标记，截断在最后一个值中间（`bottomActive=Outp`）的字符串照样通过校验。
- 其他每段都是 `key=value`，key 非空。空段、重复 key → 拒绝。未知 key 忽略；以后加的 key 放在 `end` 之前。

**分组**（p = left / right / bottom）：

- `p`、`pWins`、`pActive` 要么都有要么都没有；不完整 → 拒绝。
- **没有哪一组是必需的**。缺的组，那条栏保持现状。只有左栏和底栏的程序也能存能读；带底栏的程序存的串，读进没底栏的程序也行。

**值**：

- `p = 尺寸,标志`：尺寸 1-5 位纯数字，标志 `0` 或 `1`，正好两个字段。`' 240'`、`'$F0'` 都拒（Grid 的 `Trim + TryStrToInt` 会接受，这里不照抄）。
- `pWins` = 空，或逗号分隔的名字，每个都要过 `IsValidIdent(name, True, True)`；空项 → 拒绝。
  允许带点是给以后按 Owner 路径区分 frame 里的窗口留口子：这一版保存永远只写 Name；读到带点的名字按 §10.3 找不到、丢掉，不拒绝整个串。
- 名字在所有 `pWins` 里唯一，用 `CompareText` 比（组件名本来就不区分大小写，`compon.inc:553`）；`pActive` 引用的是自己组 `pWins` 里的名字，不算重复。
- `pActive` = 空，或 `pWins` 里的一个名字。不在自己列表里 → 拒绝；空加非空列表 → 合法。

**保存**：

- 按 left、right、bottom 的顺序写，只写有可用栏的 Placement（§10.6）。
- 窗口按 `Controls` 顺序列（只列窗口）。
- 跳过 Name 为空、或与 manager 下另一个窗口 Name 相同（`CompareText`）的窗口。
- `pActive` 是当前页的 Name（如果它被写了），否则空。
- 尺寸写 `ExpandedSize`（最大化期间也是还原高度）。
- **保存写出来的串必须能读回来**——否则重名或无名窗口会让程序每次启动都读不进自己的布局。

**顺序只靠列表位置**，不写数字顺序键（[[index-keyed-string-sort-trap]]：`"9" > "10"`）。
**不往 `pWins` 的项里加字段**：旧解析器会拒绝整个串。以后加东西一律用新的可选 key。

### 10.3 版本漂移（格式对，但窗口变了）

校验全部通过后才建计划：

- 在 manager 可用栏的窗口里按名字找。找不到、或匹配到不止一个 → 丢掉这个名字。
- 这个程序没有对应可用栏的组 → 整组忽略，里面的名字算"未放置"。
- 名字列在**另一类**栏下（按窗口当前所在的栏判断侧 / 底）→ 算未放置。
- 未放置的窗口留在当前栏，排在已放置的后面，保持它们现在的相对顺序（新版本新加的窗口就留在设计时那一侧）。
- 当前页：保存的名字如果最终在这条栏里就用它；否则当前页还在就不变；否则第一个窗口；否则没有。缺组的栏也照这条回落（它的当前页可能被别的组挪走）。
- `ExpandedSize := 保存的尺寸`（只经过 setter 的 0..99999 范围钳，不按父控件钳）；`Collapsed := 保存的标志`。没有窗口的侧栏保留图标条。
- **改了名的窗口当成新窗口**（丢掉原来的位置），文档写明。

### 10.4 应用（一个批次）

1. 取消拖动。
2. 最大化的底栏先还原。
3. 记下窗体的 `ActiveControl`。
4. 所有栏 `DisableAlign`。
5. 把窗口挪到各自的栏、`SetControlIndex`、激活、设尺寸和收起标志；激活和收起都跳过焦点那一步（§5.1 第 5 步、§5.3），并关掉"注册即激活""移动即展开"的副作用（§5.1、§3.2）。
6. `EnableAlign`。
7. 焦点：原控件还 `CanFocus` 就还给它。否则看它原来所在的窗口现在在哪条栏：那条栏收起了，或者没有能聚焦的当前页，就 `GetParentForm(栏).SelectNext(栏, True, True)`；展开着就 `FocusFirst` 这条栏的当前页。原控件不在任何工具窗口里就不动。

事件：

- 不问 `OnCanMoveWindow`，不发 `OnWindowMoved`，栏的 `OnChange` / `OnCollapse` / `OnExpand` 批次内也不发（Grid 的布局读取同样不问否决：`Grid.pas:13347-13386` 直接写列宽和排序键，`OnCanSort` 只在 `SortByColumn` 里问，`:14523-14528`）。
- 窗口的 `OnShow` / `OnHide` 照常；批次结束发一次 `OnLayoutApplied`。
- **挂起计划**在 `TryFinishLoading` 里应用时，窗体的 `OnCreate` 还没跑：批次内不发任何用户事件（连 `OnShow` / `OnHide` 也不发），视同流式加载；`OnLayoutApplied` 用 `QueueAsyncCall` 推到加载结束之后。否则用户处理器引用 FormCreate 里才建的对象就会 AV。（修正批准稿：批准稿写的是应用布局时窗口 `OnShow` / `OnHide` 照常发；这里只对加载结束时在 `TryFinishLoading` 里应用的挂起计划收窄，普通 Load / Reset 仍照常发。）
- 文档写明：`MoveWindow`、`LoadLayoutFromString`、`ResetLayout` 把窗口挪到另一侧栏时，都会重建窗口里所有句柄（IME 组字、光标、原生子窗口状态不保留）。

### 10.5 时机

**加载过程中调用**（manager、某条注册栏或它的某个窗口还在 csLoading）：

- 立即检查格式，格式错返回 False。
- 否则把这次调用（Load 的文本，或一次 Reset）存成**唯一**的挂起计划（后来的 Load / Reset 覆盖它），返回 True。
- manager 的 `Loaded`、每条栏 `Loaded` 的最后一句都调 `TryFinishLoading`；等所有参与者都不在 csLoading 了：先记默认布局（还没记过的话），再应用挂起计划。
- 这是给 frame 用的：**TFrame 没有 OnCreate**，内嵌到窗体上的 frame 构造函数返回时，它的子控件还在 csLoading，而它自己的 Loaded 又先于子控件（`reader.inc:1521-1525`）。继承窗体同理。

**其他时候调用**：

- 窗体还没 `Showing`（FormCreate 里，文档推荐的位置）→ 同步。
- 否则整个计划排队（`QueueAsyncCall`，覆盖之前排队的计划和移动；销毁时 `RemoveAsyncCalls`），捕获在某个要跨栏移动的窗口里时再排一次。理由同 §9.9：比如"恢复默认布局"按钮放在某个窗口的操作区里，同步应用会在按钮自己的点击里销毁它的句柄。

**默认布局（`ResetLayout` 恢复的对象）**：

- **从 .lfm 加载的**：加载结束时自动记。拍的是**流进来的值**（存储的 `ActiveIndex`、`Controls` 顺序、`ExpandedSize`、`Collapsed`），不依赖各 `Loaded` 的执行顺序——LCL 先读完所有流、解析完所有引用，才开始第一个 `Loaded`（`lresources.pp:3178-3180`）。
- **代码搭的**（manager 从没收到 `Loaded`，代码建的组件永远收不到）：
  - 窗体第一次 `Showing` 之前改 `Collapsed` / `ExpandedSize` / `WindowIndex`、调 `MoveWindow`，算搭建，不触发记录。
  - `LoadLayoutFromString` / `ResetLayout` 在非加载期间调用时先记（还没记过的话）——FormCreate 里先搭好再读用户布局，记下的就是搭好的样子。加载期间调用的，由 `TryFinishLoading` 先记流进来的值再应用。
  - `Showing` 之后第一次改动布局之前也记。
- `CaptureDefaultLayout` 随时覆盖；调过之后不再自动记。
- 默认布局里没有的窗口，Reset 时留在原处。

### 10.6 键

- 窗口按组件 Name，不区分大小写。
- 栏按 Placement。**一个 manager 下，与其他栏 Placement 相同的每一条栏都不可用**：不参与保存、读取、跨栏命中测试、跨栏移动；栏内调顺序照常。
  - 不按"先注册的赢"：引用 fixup 按 .lfm 里的**倒序**执行（`sllist.inc:91-96`，`reader.inc:750`），先注册的其实是流里最后一个。
  - 在 `SetManager`、`SetPlacement`、`opRemove` 时重新检查。
  - **不抛异常**：这些 setter 在 fixup 期间执行，在里面抛异常会中止整个窗体加载（`reader.inc:734-786`，没有恢复）。
  - 设计期冲突的栏用 `TyToolWindowNote` 画一行提示。
- 不支持：manager 放在数据模块里、栏分布在多个窗体上（文档写明）。

### 10.7 不保存

- 底栏最大化状态。
- 窗口里的内容：筛选框文字、终端会话、滚动位置（Grid 布局同样不存筛选）。

---

## 11. 设计器

**栏的组件编辑器**：

- "新建工具窗口"：`Create(Bar.Owner)`；`Parent := Bar`；`CreateUniqueComponentName`；`Caption := Name`；激活；`Hook.PersistentAdded`；`GetDesigner.AddUndoAction(NewComp, uopAdd, True, 'Name', '', NewComp.Name)`；`Modified`。
  照抄 PageControl 的"添加页"不记撤销，Ctrl+Z 删不掉加出来的东西（`designer.pp:788` 是面板拖放记撤销的地方）。
- "显示 ▸" 子菜单列出所有窗口（设计期只激活）。
- **不提供"删除工具窗口"**：`Hook.DeletePersistent` 跳过继承组件检查、Owner 检查和撤销记录（`designer.pp:3144-3179`），在子孙窗体里能删掉继承来的窗口、把子孙窗体弄坏。用 Delete 键删。

**窗口的组件编辑器**：

- "添加操作区"（已有时灰掉）：同样 `PersistentAdded` + `AddUndoAction`。
- "移到另一侧栏"（只有侧栏窗口；本栏不冲突、`Bar.Manager` 下另一侧有不冲突的栏才可用；csAncestor 的窗口灰掉）：调 `MoveWindow`。
- "移回栏里 ▸"（只有孤儿）。

**规则**：

- frame 实例里（`IsInInlined`）所有添加和移动菜单项都灰掉——不能往 frame 实例里加组件（`componenteditors.pas:178-183`）；继承来的控件不能换父（`customformeditor.pp:1667-1669`）。子孙窗体里往继承来的栏加窗口、往继承来的窗口加操作区仍然可以。
- 窗口顺序 = `Controls` 顺序，栏重写 `SetChildOrder`（§6.1）。
  （顺带发现 `TTyPageControl.MovePage` 也没同步子控件顺序，已单独开修复任务给 3.0 会话。）
- 粘贴：粘贴目标是第一个带 `csAcceptsControls` 的选中控件，选中栏的正文时会粘进当前页里。`ChildClassAllowed` 拦住面板拖放和"改变父控件"；漏过去的由孤儿模式 / 提示显示出来。文档写明：先选中栏再粘贴——侧栏点图标条，底栏点标签行的空白处或边缘区。

**已知限制**（文档写明）：删掉一个工具窗口或操作区后撤销 / 重做，它会被建到**窗体**上而不是回到原来的栏或窗口里。
Lazarus 撤销时只存父控件名字，用 `FForm.FindChildControl` 找——只扫窗体的直接子控件，不能重写（`designer.pp:1540-1545`，`wincontrol.inc:4547-4558`）。
补救：窗口靠孤儿模式可见，右键"移回栏里 ▸"；操作区用 IDE 的"改变父控件"放回窗口。

---

## 12. 主题

**类型键**（每个都是自己的，基础规则写在 `themes/light.tycss`，不借 `TyTab` / `TyBadge` / `TyTreeNode`）：

| 键 | 用途 |
|---|---|
| `TyToolWindowBar` | 栏底色 |
| `TyToolWindowStrip` | 图标条底色与边框（**实现期补**：边框不能省——antdesign / bootstrap / material3 / ubuntu 四个皮肤的 `--chrome-bar-bg` 就等于 `--surface`，没有边框时整条图标条看不见） |
| `TyToolWindowStripItem` | 图标项；`:hover` `:selected` `:active` |
| `TyToolWindowStripIndicator` | 当前图标的指示条（定稿时新加） |
| `TyToolWindowEdge` | 栏的边缘区（拉宽边，以及贴着编辑区的那条分隔线）；`:hover` `:active` |
| `TyToolWindow` | 窗口正文底色 |
| `TyToolWindowHeader` | 侧栏标题行底色、标题墨色和字体、可选底线 |
| `TyToolWindowActions` | 操作区 |
| `TyToolWindowTabRow` | 底栏标签行 |
| `TyToolWindowTab` | 标签；`:hover` `:selected`（当前页只用 `[tysSelected]` 解析） |
| `TyToolWindowTabIndicator` | 当前标签下划线 |
| `TyToolWindowOverflow` | 溢出按钮（图标条和标签行共用）；`:hover` `:active` |
| `TyToolWindowButton` | 最大化 / 收起；`:hover` `:active` |
| `TyToolWindowSeparator` | 底栏标题行里固定按钮前面的分隔线 |
| `TyToolWindowDropIndicator` | 拖放插入线 |
| `TyToolWindowNote` | 设计期提示（孤儿、没有窗口、Placement 冲突、多余操作区、非窗口子控件） |

**颜色 token**（皮肤调 token，不用写基础规则；见 [[variant-dies-under-skin-base-rule]]）。light.tycss 里的默认值：

| token | 默认 |
|---|---|
| `--toolwindow-bg` | `var(--surface)` |
| `--toolwindow-ink` | `var(--on-surface)` |
| `--toolwindow-header-bg`（标题行 / 操作区 / 标签行共用） | `var(--toolwindow-bg)` |
| `--toolwindow-caption-ink` | `var(--on-surface)` |
| `--toolwindow-tab-ink` | `var(--muted)` |
| `--toolwindow-tab-ink-selected` | `var(--on-surface)` |
| `--toolwindow-indicator-color`（标签下划线） | `var(--accent)` |
| `--toolwindow-strip-bg` | `var(--chrome-bar-bg)` |
| `--toolwindow-strip-ink` | `var(--muted)` |
| `--toolwindow-strip-ink-selected` | `var(--on-surface)` |
| `--toolwindow-strip-indicator-color` | `var(--accent)` |
| `--toolwindow-edge-color` | `var(--border)` |
| `--toolwindow-edge-color-hover` | `var(--accent)` |
| `--toolwindow-overlay-hover` | `var(--overlay-hover)` |
| `--toolwindow-overlay-active` | `alpha(var(--on-surface), 0.20)` |
| `--toolwindow-drop-color` | `var(--accent)` |

（**实现期修正 2026-09-20**：原表把选中态的两个墨色写成 `-active` 结尾。本库 `-active` 专指「按下」那一族——`--surface-active` / `--accent-active` / `--danger-active`——所以改成 `-selected`。同时补上实现期发现缺的四个：容器墨色、边缘区悬停色、以及悬停 / 按下两个叠加色，后者原来直接写死 `var(--overlay-hover)` 和 `var(--accent)`，皮肤压不住。）

底色**只引用皮肤已经定义的 surface / chrome token**，不在新 token 里自己写 `darken(--surface, …)`——那会绕过白底皮肤已经定义好的 chrome token（[[skin-must-define-derived-tokens]]）。

**长度 token**（密度块，modern 值写进 DensityPack）：
`--toolwindow-header-height`、`-header-pad`、`-header-gap`、`-tab-pad`、`-tab-area-min`、`-indicator-size`（标签下划线）、`-strip-indicator-size`（0 = 不画）、`-button-size`、`-glyph-size`、`-content-min`、`-strip-size`、`-strip-item-size`、`-edge-size`、`-drop-size`。

改完：跑 `gen-defaulttheme.ps1`（先验忠实度）、`gen-tycss-catalog.ps1`；键和 token 加进 `test.themes` 的 GGRID / GMETRICS；加一条跨 17 个主题的 resolve 测试。

---

## 13. 有意的偏离与不做清单

**和 VS Code 不同**：

- 两侧都有图标条（VS Code 右侧栏的切换是标题行里的标签）。
- 侧栏和底栏之间不能互拖（VS Code 三处互通，`compositeBar.ts:118-121`）。
- 标签和图标都在松开时切换。
- 被拖空的侧栏保留图标条（VS Code 整块隐藏，靠拖到编辑区边缘弹出来；我们不做边缘弹出）。

**和 JetBrains 不同**：一侧只显示一个窗口，不做上下 / 左右分屏；底部窗口不放进侧栏图标条的下半段；不做浮动 / 独立窗口 / 自动隐藏等视图模式。

**和库内惯例不同**：

- 图标和标签**松开才切**，而库里纯切换控件（`TTySegmented`、`TabStrip`、`Pagination`）按下就切（`Pagination.pas:912-914`）。理由见 §9.3，和 TreeView / Grid 表头点击改成松开（c73e1c07、60b4f069）同向。
- `OnWindowMoved` 对 `MoveWindow` / `WindowIndex` 也发，而 Grid `OnRowMove`、TreeView `OnNodeMoved`、TabStrip `OnReorder` 只为手势发。这里是为了给应用一个"布局变了"的信号（比如自动保存）。

**不做**（以后要再单独立项）：

- 边缘靠近弹出隐藏的栏。
- 底栏对齐方式（居中 / 两端）选项——用布局本身表达（§2）。
- 图标 / 标签上的数字徽标。
- 每窗口记忆尺寸（格式已留口子：`TTyToolWindow.PreferredSize` + 可选 key `sizes=Name:n,...` + manager 开关，不改版本号）。
- 键盘操作图标条、`&` 助记符、无障碍角色。
- 跨窗体拖动、manager 放在数据模块里、栏分布在多个窗体上。
- 内置右键菜单、从标题行拖动窗口。
- 标题行操作自动收进"…"菜单（操作区里是真控件，没法通用地搬进菜单）。

---

## 14. 测试

涉及手势的测试走真实的 `MouseDown / MouseMove / MouseUp`；**每条都要把它守护的规则删掉一次，确认会红**（[[tests-written-with-the-fix-are-green-and-wrong]]）。
需要句柄的测试自带 widgetset 惰性初始化（[[headless-tests-never-run-lcl-align]]）。

**流式**：

- 窗口 + 操作区 + 正文往返；调顺序后往返；继承窗体里的子控件顺序。
- 两条同 Placement 的栏，两种流顺序结果一致。
- `ExpandedSize` = 240 和 ≠ 240 各往返一次，侧栏和底栏都测。
- 窗口的 `Controller` 不写进 .lfm。

**排布**（无头调 `AdjustClientRect + AlignControls`）：

- 正文在标题行下面，操作区矩形等于几何结果。
- 改操作区的 Align 不起作用；空操作区宽 0；MinHeight 撑高标题行；开 AutoSize 子控件不动。
- 运行时往操作区加一个比 token 高的控件，或藏掉最高的那个，正文 Top 跟着变。
- 底栏两页操作区高度不同，切页时标签行高度不变。
- 底栏：运行时往非当前页的操作区加一个比共用行高更高的控件，当前页的标签行立刻变高，之后来回切页高度不变；再把它藏掉，当前页的标签行立刻变回原高。
- 主题 token 变化后正文重新排布（把窗口的 Invalidate 钩子变异掉要红）。
- 改 `--toolwindow-strip-size` / `--toolwindow-edge-size` 后栏宽和内缩跟着变（把栏的 Invalidate 钩子变异掉要红）。
- 对非当前页 `Visible := True` 后，恰好一个可见窗口。
- 几何经五个入口一致，含 RTL 的绘制 / 命中配对。
- 设计期手势松开回答 0，且在松开时切换。

**栏**：

- 收起时焦点在当前页里，收起后 `ActiveControl` 不是窗体本身（侧栏、底栏各测一次）。
- 焦点在某侧当前页里，读一个只把这一侧收起、当前页不变的布局串，之后 `ActiveControl` 不是窗体本身，也不在隐藏的窗口里。
- 启动时 `Loaded` 应用 `ActiveIndex` 不发 `OnChange` / `OnShow`。
- 底栏收起后当前页不可见。
- 拉宽拖到 content-min 一半以下：实时按收起排布，松开后 `Collapsed = True`、`ExpandedSize` 等于起点；拖回来再松开不收起。
- 拉宽中途 `LM_CANCELMODE`：`ExpandedSize` 回到起点。
- 窗体缩窄后 `ExpandedSize` 不变；左右两栏都放不下时按比例分、结果不依赖 Align 顺序。
- 最大化后父控件变高，栏跟着变高；最大化时收起再展开，回到还原高度。
- 当前页被释放后，回落到下一个 / 上一个。
- 运行时 `Parent` 改到另一类栏抛 `EInvalidOperation`。
- 冲突栏上的图标条不是跨栏目标，但栏内调顺序照常。

**拖放**：

- 槽位函数：含末尾空隙、空操作对、当前页被强制留在条上且前面有窗口被收起（拖当前页原地放下是空操作，放到它前后空隙位置正确）；`FinalIndex`。
- 侧栏横向拖能起拖；底栏标签竖拖出行显示 `crNoDrop`、松开不切换。
- 单击后跟 `ssDouble` / `ssTriple` 按下不会执行两次；点击图标后立即在同一位置按下并拖动，能起拖。
- 在无关控件上 `Perform(CN_KEYDOWN, VK_ESCAPE)` 取消；`Perform(LM_CANCELMODE)` 取消。
- 取消后的松开不是点击；丢了松开之后的下一次按下照常点击。
- 调顺序后栏的 `OnClick` 不触发。
- 插入线像素：哨兵底色 `RenderTo`，在目标栏和当前页里数（[[headless-render-needs-sentinel-ground]]）。
- 被否决的栏不画线。
- 排队的移动执行前目标栏被释放：静默丢弃，不 AV。

**布局**：

- 往返起点是非默认状态：调过顺序、一个窗口跨了侧、一侧收起、尺寸改过、当前页无名。
- 拒绝的串，每条和好串只差一个缺陷：标签、缺 `end`、组不完整、`' 240'` / `'$F0'`、标志 2、三个字段、当前页不在列表里、只差大小写的重名、重复 key、空列表项。
- 截断：**先把状态挪离要读的串**，再对长度 1..Length-1 的每个前缀断言返回 False 且 `SaveLayoutToString` 输出逐字节不变；最后一组里放多位数尺寸。
  （Grid 的截断测试先读了好串、再断言列宽还是串里那个值——前缀如果被应用了照样通过，别照抄。）
- 漂移：缺窗口、新窗口、改名窗口；程序里没有的栏的组；名字在另一类栏下；带底栏的串读进没底栏的程序。
- 时机：内嵌 frame 的构造函数里调用，加载结束后应用、批次内不发用户事件；代码搭的 manager 和子孙窗体上的 Reset。
- DPI：96 → 144 → 96 后 `Save` 输出不变；FormCreate 里 Load 之后 `AutoAdjustLayout`，设备宽度正确。
- 窗口操作区里的"恢复布局"按钮：应用被排队，不同步销毁按钮句柄。

---

## 15. 只能真机验的

- **Lazarus IDE**：设计期点标签 / 图标切换、`CM_MASKHITTEST` 让位到栏、组件编辑器菜单项、撤销删除后的孤儿模式、粘贴、继承窗体和 frame 实例里菜单项灰掉、`Controller` 在对象查看器里隐藏。
- **Win32**：捕获期间是否还会收到 `WM_MOUSELEAVE`；拖动光标。
- **GTK3**：拖出源控件后移动事件的坐标；`gtk_grab_add` 下 Esc 能否收到。
- **GTK3 / Qt Wayland**：溢出菜单的弹出位置（`TTyPopupMenu.PopUp` 不设 Wayland 锚点）；同窗体坐标。
- **Qt**：从双击按下起拖（双击事件里按下不抓捕获）。
- **Cocoa**：临时光标；拖动事件发给按下的那个 view。
- **各 widgetset**：Alt+Tab 中途取消；拖动中 `ShowModal` 能否取消；拖动中弹出菜单抢走捕获后能否取消；禁用当前页后标签行点击落到哪里。
- **Linux / macOS**：图标条和固定按钮字形是否清晰。
- **皮肤**：17 个主题下的标题行、标签下划线、图标着色；高对比度皮肤下插入线是否看得见。

---

## 16. 交付顺序（给计划用）

1. **主题**：§12 的类型键和 token，跑两个生成器，加进 GGRID / GMETRICS。
2. **标题行几何**：纯函数和 `ITyToolWindowHeaderHost`（§7.2，侧栏、底栏两种模式一起定）。
3. **窗口 + 操作区 + 侧栏**：图标条、手势引擎的武装和点击（§9.2 按下 / 松开，§9.3）、当前页与收起（§5）、拉宽、`ExpandedSize` / `Collapsed`、栏内拖动调顺序；没有 manager，`TryFinishLoading` 先留空。
4. **底栏**：标签、溢出、最大化、标签行输入转发。
5. **manager**：`Images` 回落、跨侧拖动、`MoveWindow`（含队列和直接改 Parent 的簿记）、事件。
6. **布局保存**（补上 `TryFinishLoading`）。
7. **设计期**：组件编辑器、属性编辑器（隐藏 `Controller`）、孤儿提示、面板图标。
8. **示例 + 文档**：示例用 `.lfm` + `TTyTitleBar` + 换肤；类 IDE：左侧资源管理器 / 搜索，右侧大纲，底栏问题 / 输出（操作区放筛选框和清除）/ 终端（新建、关闭、更多），中间 `TTyMemo`；菜单里保存 / 读取 / 恢复布局、显示 / 隐藏底栏。
   `docs/controls/toolwindows.md`、README（.md + .en.md）。
   i18n 的 resourcestring：孤儿提示、"添加工具窗口"、Placement 冲突提示、多余操作区提示、非窗口子控件提示、最大化、还原、收起、更多、组件编辑器菜单项。
