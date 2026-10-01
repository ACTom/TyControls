# 控件拆出 TTyCustomXxx 父类 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（项目约定，优先于子技能的默认做法）**：分三期，每期**连续写完**——每个任务只改代码 + 写测试并单独提交，任务之间**不编译、不跑测试**（例外只有 Task 0：基线编译、生成快照夹具、跑全量，这些产出要进 git）；每期最后一个任务（Task 10 / 18 / 26）**一次编译**、跑本期 suite 和全量、集中修红、集中变异、【主控执行】编包 / 编全部示例 / 冒烟、期末审查、签收。中途不汇报、不问要不要提交。**三期做完用户一次性验收**（验收项在本计划末尾）。
>
> **谁来做**：标 **【主控执行】** 的步骤实现 agent **不做**、直接跳过：问用户、编 `tycontrols.lpk` / `tycontrols_dt.lpk`、编 `examples/`、启动 GUI 冒烟、通知别的会话。实现 agent 只编 `tests/tytests.lpi`。
>
> **共享文件**：`source/tyControls.Base.pas`、`Painter.pas`、`StyleModel.pas`、`TextMenu.pas` **不改**。`DefaultTheme.pas`、`Css.Catalog.pas`、`StrConsts.pas` 也不改（AdvChart 分支在改它们；本计划没有新的用户可见文字，也不动主题）。执行中发现非改不可，停下交主控，主控先问用户。

**Goal:** 每个可视控件 `TTyXxx` 拆成「`TTyCustomXxx` 放全部实现、原 published 属性降到 protected」+「`TTyXxx` 只有一段 published」，让第三方（GitHub issue #8，PascalSCADA）能从 `TTyCustomXxx` 派生、只发布自己想露的属性；现有程序、`.lfm`、示例一个字不用改。

**Architecture:** 纯机械的「插一层」：`TTyXxx = class(P)` 改名为 `TTyCustomXxx = class(P)`，原 published 段改 protected，再在后面接一个只含 `property X;` 的 `TTyXxx = class(TTyCustomXxx)`。重新发布的顺序、default、stored 由 Task 0 拍下的 RTTI 快照逐项钉死；`TTyCustomXxx` 不多发布任何东西、`TTyXxx` 不多一个字段，由常驻结构守卫钉死；库里「这一类控件」语义的类型判断放宽到 Custom 类，属性编辑器注册到 Custom 类。**本计划默认按「只加类、不改任何既有类的 published 集合和祖先」做（开工前问题 D1 的建议 B1）**，因为 3.x 的兼容承诺不允许改 `is` 的答案——这推翻了 brief 第 4 条的继承链写法，理由与证据见 D1 和注意事项 N14。

**Tech Stack:** FPC 3.2.2 / Lazarus 4.4 LCL（最低仍是 Lazarus 3.0）、fpcunit（`tests/tytests.lpi`）、Python 3（辅助脚本，只放 scratchpad 不进仓库）。

**设计依据：** GitHub issue #8；主控 brief（2026-10-02）；用户已定：在 `main`（3.1）上做、3.0 功能冻结不做、AdvChart 不拆、在别的分支上改着的控件单元先排除、顺序按给 issue 的回复（先输入与显示，再容器 / 列表 / 表格，最后其余）。

**工作树：** `D:/Projects/ty-split`，分支 `feat/custom-classes`，起点 `main` @ `a0606352`。

**不在本计划**：`TTyAdvanceChart`、`TTyCalendar`、`TTyDateTimePicker`（排除，见附录 B）；非可视组件（D5）；`TTyCustomControl` / `TTyGraphicControl` 自己发布的 52 / 41 个通用属性（藏不掉，见 N13，要改 `Base.pas`，不在 3.x）；改继承链、改既有中间类、改公开签名里的类型（都是 4.0 的事，见附录 D）；CHANGELOG（发版时写）；合 `main`。

---

## 总目录

| 期 | 任务 | 内容 | 类数 |
|---|---|---|---|
| 0 | Task 0 | 起点核实、RTTI 快照夹具、常驻结构守卫、辅助脚本、基线全量 | — |
| 1 输入与显示 | Task 1 | 按钮：Button、GlyphButtons（3）、DropButtons（2）、ColorButton、ButtonGroup | 8 |
| | Task 2 | 标签：TyLabel、HtmlLabel、LinkLabel、ShadowLabel、GlowLabel、Tag、Badge | 7 |
| | Task 3 | 编辑框 I：Edit、NumericEdit、CurrencyEdit、MaskEdit、URLEdit、ComboEdit、TrackEdit、CalcEdit、CalcCurrencyEdit | 9 |
| | Task 4 | 编辑框 II：Calculator、Memo、SpinEdit、FloatSpinEdit、UpDown | 5 |
| | Task 5 | 选择：CheckBox（含 RadioButton）、ToggleSwitch、Segmented | 4 |
| | Task 6 | 组合框 I：ComboBox、MRUComboBox、ComboBoxEx、OfficeComboBox、AdvancedComboBox、CheckComboBox | 6 |
| | Task 7 | 组合框 II：ColorBox、ColorComboBox、FontComboBox、FontSizeComboBox、FilterComboBox、ShellComboBox；**第一次把属性编辑器挪到 Custom 类，改 test.designeditors** | 6 |
| | Task 8 | 进度与指示：ProgressBar、Gauge、Meter、LevelMeter、CircularProgress、ActivityIndicator、ActivityBar、GearActivityIndicator、Sparkline | 9 |
| | Task 9 | 旋钮与滑块：Rating、Dial、GearDial、AnalogClock、TrackBar | 5 |
| | Task 10 | 1 期收尾 | — |
| 2 容器 / 列表 / 表格 | Task 11 | 面板：Panel、PaintPanel、ExPanel、GridPanel、RelativePanel、ScrollBox、ScrollPanel、ControlBar、CoolBar | 9 |
| | Task 12 | 分组与装饰：GroupBox、RadioGroup、CheckGroup、ToolGroupPanel、Card、Empty、Bevel、Divider、Splitter、SizeBox | 10 |
| | Task 13 | 页签：PageControl、TabSheet、TabSet、ListGroupPanel | 4 |
| | Task 14 | 列表框：ListBox、CheckListBox、OfficeListBox、AdvancedListBox、ValueListEditor、ColorListBox、FontListBox | 7 |
| | Task 15 | 复合选择：Transfer、TreeSelect、Cascader | 3 |
| | Task 16 | 树与列表视图：TreeView、ShellTreeView、ListView、ShellListView、HeaderControl | 5 |
| | Task 17 | 表格：DrawGrid、StringGrid | 2 |
| | Task 18 | 2 期收尾 | — |
| 3 其余 | Task 19 | 条：StatusBar、ToolBar（含 ToolButton、ToolSeparator）、ToolBarEx、Alert、Pagination、Steps、Breadcrumb、ScrollBar | 10 |
| | Task 20 | Ribbon：Ribbon、RibbonPage、RibbonGroup、RibbonAppMenu、RibbonQuickAccess、RibbonGallery、RibbonBackstage | 7 |
| | Task 21 | 窗体镶边与菜单栏：TitleBar、MenuBar | 2 |
| | Task 22 | 图像与图形：CharImage、Image、PreviewBox、ImageView、Shape、StarShape、Arrow、Chart | 8 |
| | Task 23 | 取色器与终端：ColorGrid、LColorPicker、HSColorPicker、TerminalView | 4 |
| | Task 24 | （可选，D6）工具窗口：ToolWindowBar、ToolWindow、ToolWindowActions | 3 |
| | Task 25 | 文档：「从 Ty 控件派生」一节（位置 D8） | — |
| | Task 26 | 3 期收尾、撤掉迁移期快照守卫、用户验收清单 | — |

规模：注册在组件面板（含 `RegisterNoIcon`）的类共 **173** 个：**拆 130**（+ Task 24 可选 3）、**不拆 37**（非可视 35 + `TTyFormSurface` + `TTyGridCell`；Task 24 不做时再加工具窗口 3 个）、**排除 3**（附录 B）。逐类清单见附录 A。

---

## 开工前要定的问题（Task 0 Step 1【主控执行】）

每条给出建议；主控决定问不问用户，问了把答复写进本节开头（加一个「状态」引用块），没回复就按建议做。**D1 必须问用户**——它推翻了 brief。

**D1. 继承链怎么挂（推翻 brief 第 4 条，必须问用户）**
- **A（brief 原定，LCL 的 `TCustomMaskEdit = class(TCustomEdit)` 那种）**：`TTyCustomNumericEdit = class(TTyCustomEdit)`，`TTyNumericEdit` 把 TTyEdit 的 published 全部重新发布。效果最彻底：派生控件的 Custom 类也能藏掉父控件的属性。代价：**`TTyNumericEdit is TTyEdit` 从 True 变 False**，`TTyGlyphButton is TTyButton`、`TTyColorBox is TTyComboBox`、`TTyScrollBox is TTyPanel` 等约 55 个派生控件同理。用户代码里的 `is` / `as` 会**静默改道或运行期抛 EInvalidCast**。仓库里就有现成的例子：`examples/toolbar/umain.pas:162` 的 `(Sender as TTyButton).Caption` 挂在 9 个 `TTyGlyphButton` 的 OnClick 上（`umain.lfm:63` 起）——按 A 做，点一下就抛异常；`tests/test.calcedit.pas:40` 断言 `e is TTyNumericEdit`、`tests/test.scrollbar.autohide.pas:1415` 断言 `TTyValueListEditor.InheritsFrom(TTyListBox)`、`examples/grid/umain.pas:1332` 用 `AEditor is TTyEdit` 认格编辑器、`tools/gallery/tyGalleryCapture.pas:157` 用 `c is TTyButton` 找按钮。CONTRIBUTING.md 的兼容承诺（「同一主版本内……公开 API 不删、不改签名」「`.lfm` 里的属性不删」）和 A 冲突。另外 A 还要求把四个既有中间类（`TTyGlyphButtonBase`、`TTyCustomTabStrip`、`TTyCustomGrid`、`TTyShellTreeLink`）的 published 降级，直接继承它们的第三方 `.lfm` 会在读入时报「Unknown property」。
- **B1（建议，本计划按它写）**：**只加类、不改任何既有类的 published 集合和祖先**。每个要拆的 `TTyXxx`：`TTyCustomXxx = class(<TTyXxx 现在的父类>)`、`TTyXxx = class(TTyCustomXxx)`。家族根（父类是 `TTyCustomControl` / `TTyGraphicControl` 的，约 75 个）得到真正干净的 Custom 类；派生控件（约 55 个）的 Custom 类挂在已发布的父控件下面，只能藏掉**本层新加的**属性。所有现存的 `is` 答案不变，示例与测试不用改。4.0 再按 A 改挂（届时每个派生类改一行父类 + 重新生成发布段，附录 D 记着）。
- **B2**：同 B1，但派生控件 3.x 不建 Custom 类，只拆家族根和独立控件（约 75 个），4.0 一次按 A 做全。工作量少一半，但给 issue 的回复（「每个控件」）要改口。

建议 B1：兑现「每个控件都有 TTyCustomXxx」，又守住 3.x 承诺；派生控件 Custom 类的局限写进文档。选 A 时本计划要改的地方见「拆分规则」末尾的「按 A 做的差异」。

**D2. 属性编辑器 / 组件编辑器注册到哪**
- 属性编辑器（`RegisterPropertyEditor(..., TTyXxx, 'Prop', ...)`）**改注册到 `TTyCustomXxx`**（建议）。LCL 按 `Obj.InheritsFrom(PersistentClass)` 匹配、取最派生的那条（`components/ideintf/propedits.pp:2824-2870`），对象查看器只显示 published 的属性，所以第三方子类发布了 `Directory` 就自动用上目录编辑器，没发布就看不见——不会出错。涉及 6 条：FilterComboBox.Filter、ShellComboBox / ShellListView / ShellTreeView.Directory、RibbonPage.Context、CharImage.GlyphName。`TTyGlyphButtonBase.GlyphName` 照旧（类没变）。
- 组件编辑器（`RegisterComponentEditor`）**留在最终类**（建议）。理由：组件编辑器的动词会改属性（树的节点、页签的页、级联的节点、列表组……），第三方子类要是没发布那个属性、又不靠 `DefineProperties` 存，编辑完存盘就**静默丢了**。编辑器类都在 `tyControls.Design.CompEditors` 的 interface 里（行 42-219），第三方想要可以自己 `RegisterComponentEditor(TMyTree, TTyTreeViewComponentEditor)`，文档里写一句。另一选项：注册到 Custom 类，编辑器里先 `IsPublishedProp(Component, 'Items')` 判断再给动词——要改 12 个编辑器，不建议。

**D3. 原 published 属性在 Custom 类里放 protected 还是 public**
- 用户已定 protected（照 issue 原话）。核实发现 **LCL 的 `TCustomEdit` 其实大多是 public**（`lcl/stdctrls.pp:856` 起：Alignment、CaretPos、MaxLength、ReadOnly、Text、OnChange……都在 public，只有 AutoSelect 等少数在 protected）。两种都能挡住对象查看器和 `.lfm`（那只看 published）；差别在代码：protected 时，第三方或库里另一个单元拿着 `TTyCustomXxx` 类型的引用就不能读写这些属性，要用单元内的 access 类（`TTyCustomXxxAccess = class(TTyCustomXxx)` 再强转）。建议**维持 protected**（用户已定，第三方子类自己决定哪些提成 public），库里放宽类型判断的地方若要读写原 published 属性，一律用 access 类（N17）。若主控 / 用户改选 public，规则 R2 里「protected」换成「public」即可，其余不变。

**D4. 不拆的非可视组件（35 个，建议全部不拆）**：控制器（`TTyStyleController`、`TTyNativeStyler`）是基础设施；菜单（`TTyPopupMenu` / `TTyImagesMenu` / `TTyMenuEx`）的父类 LCL `TPopupMenu` 自己就发布了一批，藏不掉；图标字体与图像列表（`TTyIconFont`、`TTyLucideIconFont`、`TTyLucideImageList`、`TTyGlyphImageList`、`TTyImageCollection`、`TTyVirtualImageList`）、提示（`TTyHint`、`TTyBalloonHint`、`TTyPopover`、`TTyNotification`）、对话框（19 个）——published 属性就是它们的全部用法，拆了没人受益；`TTyToolWindowManager` 已经有 `TTyCustomToolWindowManager`（架构上的拆分，见核实记录 V6）。值得一提的是 `TTyLucideImageList` 正是 issue 说的那种痛（它用 `THiddenPropertyEditor` 藏父类的 Collection / IconFont，`PropEditors.pas:737-738`），但按 B1 它仍从 `TTyVirtualImageList` 派生，拆了也帮不上，留到 4.0。

**D5. 不拆的可视类**：`TTyFormSurface`（窗体的内容宿主，设计器把它的属性全藏了，`PropEditors.pas:801-847`，没有派生它的正当用法）、`TTyGridCell`（由 GridPanel 自己创建、按类判断归属，`GridPanel.pas:566`，第三方无法让 GridPanel 建它的子类）。建议不拆。`TTyForm` / `TTyDialog` 是设计器基类、本来就是 `TForm`，不在范围。

**D6. 工具窗口三件（`TTyToolWindowBar` / `TTyToolWindow` / `TTyToolWindowActions`）拆不拆**：`ToolWindows.pas` 7841 行，库内类型判断 43 处，`ToolWindows.Manager` / `DesignRules` 的公开签名全写死最终类（附录 D），第三方的 Custom 子类拆出来也进不了 manager 的 API。建议 **3.x 不拆**（Task 24 跳过，三个类挪进 `CNotSplit`），4.0 连签名一起做。选拆就照 Task 24 做。

**D7. 给 issue 回复要说清的限制**（主控写回复时用）：① Custom 类仍带着基类发布的通用属性（N13）；② B1 下派生控件的 Custom 类挂在父控件下面；③ 宿主 API 写死最终子项类型的地方（`TTyForm.TitleBar: TTyTitleBar`、`TTyPageControl.ActivePage: TTyTabSheet`、事件的 `Sender: TTyTreeView` 等，附录 D）第三方子类要靠强转，4.0 改。

**D8. 文档放哪**：建议新建 `docs/subclassing.md` + `docs/subclassing.en.md`（「从 Ty 控件派生」：什么时候用 TTyCustomXxx、怎么发布、默认值与顺序的规矩、组件编辑器怎么注册、上面 D7 的限制），`README.md` / `README.en.md` 的文档索引各加一行，`docs/controls/README.md` 顶部加一句指过去。逐控件的 `docs/controls/*.md` 不改。

**D9. 迁移期快照守卫的去留**：Task 0 的 RTTI 快照只在迁移期有意义；它会让「以后给已拆控件加属性」都得重生成夹具。建议 Task 26 删掉快照测试和夹具，常驻结构守卫 G1–G5 留下（它们管的是「拆的形状」，新控件也逃不掉，见 N25）。附录 B 的补拆期自己再拍一份只含那 3 个类的快照。

---

## 核实记录（写计划时读源码与实验，2026-10-02，`main` @ `a0606352`）

**V1. 组件面板清单**：`designtime/tyControls.Design.pas:132-224` 的 `RegisterComponents` 共 15 组 + `RegisterNoIcon` 2 处（`TTyGridCell`；`TTyToolWindow`、`TTyToolWindowActions`；`TTyFormSurface`），合计 173 个类名（`TTyOpenDialog` 是 `TTyCustomFileDialog` 的空子类，单行声明 `Dialogs.FileDialog.pas:212`）。`RegisterDesignerBaseClass` 另有 `TTyForm`、`TTyDialog`。`tests/test.designregistry.pas` 的 `CollectRegisteredClassNames` 在运行时解析同一文件，`tests/test.version.pas:473-499` 把这些名字全部 `RegisterClasses`，所以测试里 `GetClass(name)` 能拿到类引用。

**V2. 现有「Custom」类都不是「Custom + 只 publish」形态**：
| 类 | 位置 | 自己发布 | 子类 | 结论 |
|---|---|---|---|---|
| `TTyCustomControl` | `Base.pas:335` | 52（`Base.pas:418-515`） | 所有窗口化控件 | 基类，发布了通用属性，不改（N13） |
| `TTyGraphicControl` | `Base.pas:79` | 41（`Base.pas:254-333`） | 所有图形控件 | 同上 |
| `TTyCustomGrid` | `Grid.pas:777` | 约 68（`Grid.pas:1644-1877`） | `TTyDrawGrid`（再派生 `TTyStringGrid`） | 已发布一大批；B1 下不动 |
| `TTyCustomTabStrip` | `TabStrip.pas:62` | 约 16（`TabStrip.pas:524-572`） | `TTyPageControl`、`TTyTabSet`、`TTyRibbon` | 同上 |
| `TTyCustomFileDialog` | `Dialogs.FileDialog.pas:170` | 12 | 打开 / 保存 / 图片 / 预览对话框 | 非可视，不动 |
| `TTyCustomToolWindowManager` | `ToolWindows.pas:1403` | 0 | `TTyToolWindowManager`（`ToolWindows.Manager.pas`，有自己的私有实现） | 架构拆分（为了单元依赖），不是这个形态；不动 |
另有两个「Base」中间类：`TTyGlyphButtonBase = class(TTyButton)`（`GlyphButtons.pas:100`，发布 11 个）、`TTyShellTreeLink = class(TTyTreeView)`（`ShellListView.pas:62`，0 个，只为两个 shell 控件互指）、`TTyIconPackFont = class(TTyIconFont)`（非可视）。B1 下全都不动。

**V3. LCL 祖先已经 published 的**（`lcl/controls.pp`）：`TComponent`：Name、Tag。`TControl` 的 published 段：AnchorSideLeft / Top / Right / Bottom、Cursor、Left、Height、Hint、Top、Width、HelpType、HelpKeyword、HelpContext（13 个）。`TWinControl`、`TCustomControl`、`TGraphicControl` **没有** published 段。所以窗口化控件的 Custom 类不可避免地带着 2 + 13 + 52 = 67 个、图形控件 2 + 13 + 41 = 56 个 published 属性（N13）。

**V4. LCL 里常被 Ty 控件重新发布的属性原本的可见性**（`lcl/controls.pp`，决定 R2 里带说明符的重声明放哪一段）：public——Action、Align、Anchors、AutoSize、BorderSpacing、Caption、Color、Constraints、Enabled、Font、OnChangeBounds、OnClick、OnResize、OnShowHint、PopupMenu、ShowHint、Visible、ClientWidth / ClientHeight（TControl）；BorderWidth、ChildSizing、DockSite、TabOrder、TabStop、UseDockManager、OnEnter / OnExit / OnKeyDown / OnKeyPress / OnKeyUp / OnUTF8KeyPress、OnDockDrop / OnDockOver / OnUnDock（TWinControl）；OnPaint（TCustomControl public、TGraphicControl protected）。protected——DragCursor、DragKind、DragMode、ParentFont、ParentShowHint、Text、OnDblClick、OnMouse*（全部）、OnContextPopup、OnDragDrop / OnDragOver、OnStartDrag / OnEndDrag、OnEditingDone、OnConstrainedResize、OnStartDock / OnEndDock、OnGetDockCaption / OnGetSiteInfo。

**V5. FPC 3.2.2 的 RTTI 与重声明（实验，scratchpad `rtti/probe.lpr`、`rtti2/p2.lpr`、`rtti2/p3.lpr`，结果如下）**：
1. `TWriter.WriteProperties`（`rtl/objpas/classes/writer.inc:841`）用 `GetPropList(Instance, PropList)`，后者调 `GetPropInfos`（`rtl/objpas/typinfo.pp:1443`），**不排序**：数组下标就是每个属性的 `NameIndex`，从派生类往祖先走、同下标先到先得。`.lfm` 的写出顺序 = `NameIndex` 顺序；读入（`TReader`）按文件顺序调 setter。
2. `NameIndex` 的分配：编译器从最老的祖先往下数，**一个名字第一次在 published 段出现时**拿下一个号——所以祖先（`TComponent` 的 Name、Tag，`TControl` 的 13 个，`TTyCustomControl` 的 52 个……）发布的属性总排在前面；派生类里再声明（重新发布、改 default、甚至换类型）**沿用祖先那个号**。实验：`TOrig` 里 `property BaseB default 7;` 写在自己 published 段的中间，RTTI 里仍排在祖先的位置（第 3）；`TSplit`（protected → 自己 published）按自己声明的先后拿号；第三方 `TThird` 先写 `Position` 后写 `Max`，RTTI 里就是 Position 在前。
3. **不带说明符的 `property X;` 重声明会继承 default、nodefault、stored（常量 / 字段 / 方法）、index、读写方法**：`TSplit` 的 13 个属性与原 `TOrig` 逐项相同（default=100、`nodefault` 记作 `-2147483648`、`stored IsStrStored` 记作 method、`index 1` 保留、`stored False` 保留）。**跨单元**也一样：`TThirdZ`（另一个单元）发布 `TCustomZ` 里 private 字段 / 私有 setter / 私有 stored 方法支撑的属性，编过、default=100、stored=method、流式写读往返正确。
4. **在派生类里把已 published 的属性重声明到 protected，藏不掉**：`THide` 里 `protected property BaseA;` 之后 `IsPublishedProp(THide, 'BaseA') = True`——RTTI 从祖先那里照样拿得到。这就是 issue 的根：Pascal 不能取消 publish。
5. **把 public 属性在派生类重声明到 protected，不影响外部访问**：`TCustomB` 里 `protected property PubProp;`（祖先 `TA` 里是 public），别的单元照样能写 `c.PubProp := 3`（编译器找不到可见的就继续往祖先找）。所以误降级不会编不过，但读代码的人会被误导，规则 R2 不让这么写。
6. 嵌套类型、`class var`、`class function` 放在 Custom 类里，经最终类访问照常：`TB.TNested`、`TB.Counter`、`TB.Hello` 都编过且结果正确。
7. 结论写进规则：重新发布的**顺序**只对「第一次在 `TTyXxx` 发布的名字」有意义；已在 Custom 父类发布的名字（如 `TabStop`）位置固定在祖先，写在哪段都不影响顺序，但**它的 default / stored 必须写在 Custom 类里**，否则第三方子类拿到的是祖先的 default（N2）。

**V6. 设计期注册的匹配方式**：属性编辑器见 D2；组件编辑器 `GetComponentEditor`（`components/ideintf/componenteditors.pas:608-631`）用 `Component is P^.ComponentClass` 并取最派生的一条。注册清单：`designtime/tyControls.Design.PropEditors.pas:678-848`（`RegisterPropertyEditors`）、`designtime/tyControls.Design.CompEditors.pas:1143-1181`（`RegisterComponentEditors`）。基类上的 `StyleClass` / `StyleOverride` / `Version` 编辑器注册在 `TTyGraphicControl` / `TTyCustomControl`，不受影响。

**V7. `tests/test.designeditors.pas:157` `TestEveryRegistrationTargetsARealProperty`** 要求「注册里写的类本身 publish 了这个属性」（`GetPropInfo(cls, prop)`），并要求类名能 `GetClass`（`RegisterClasses` 块在 `:386`）。属性编辑器挪到 Custom 类后这条会红——Task 7 按 R8 改它。`tests/test.version.pas` 的 `InheritsFromAnEditorBase` 只看 `Version` 编辑器的基类（`TTyGraphicControl` / `TTyCustomControl` / `TTyComponent`），不受影响。

**V8. 类名查表**：样式 typeKey 全是字面量（`TTyEdit.GetStyleTypeKey` 返回 `'TyEdit'`，`Edit.pas:629-632`；全库 `GetStyleTypeKey` 实现里没有 `is` / `ClassType` / `ClassName` 分支）。`ClassName` 的用法只有错误消息（`CheckGroup.pas:438`、`RadioGroup.pas:379/567`、`TreeView.pas:3493`、`Form.pas:2115`）和设计期起名（`CompEditors.pas:634/736/850`，`CreateUniqueComponentName(X.ClassName)`）——实例的类名不变，行为不变。`RegisterClass` 写在最终类上：`Chart.pas:1720`、`ControlBar.pas:516`、`CoolBar.pas:1786`、`FilterComboBox.pas:259`、`Form.pas:2904/2907`（TitleBar、MenuBar）、`Dialogs.FileDialog.pas:1121-1126`——保持（流式按类名找的是最终类）。没有 `FindClass` / `GetClass` / `ClassNameIs` 查控件类、没有 `class of TTyXxx` 类型、没有 class helper。i18n：`.po` 里没有控件类名做键（`.lfm` 翻译键是窗体类名 + 组件名）。组件面板图标按类名找（`scripts/gen-icons.ps1`、`tycontrols_icons.lrs`），注册的仍是最终类，不变。

**V9. 命名冲突**：全仓库（`source`、`designtime`、`tests`、`examples`、`tools`，以及 `ty-advchart`、`ty-3.1` 两棵树）现有的 `TTyCustom*` 只有 `TTyCustomControl`、`TTyCustomGrid`、`TTyCustomTabStrip`、`TTyCustomToolWindowManager`、`TTyCustomFileDialog`。要新建的 130 个名字（`TTyCustom` + 去掉 `TTy` 的类名）与它们都不撞：没有叫 `TTyControl`、`TTyGrid`、`TTyTabStrip` 的控件。

**V10. 排除清单的核实**（`git cherry main <分支>` 取 `+`，再 `git show --name-only`；工作树 `git status --short`）：
| 来源 | 未进 main 的提交 | 碰到的控件单元 | 结论 |
|---|---|---|---|
| `feat/advancechart`（ty-advchart，HEAD `dba5e4f9`） | 107 | `AdvanceChart.pas`（83 次）、`Calendar.pas` 与 `DateTimePicker.pas`（各 1 次：`ab4487d8` 把 `TyDateTimeNames` 挪到 `StrConsts`）；另有 `Base.pas`、`Painter.pas`、`FontUnits.pas`、`DefaultTheme.pas`、`Css.Catalog.pas`、`StrConsts.pas`（本计划都不碰）；测试 `test.calendar.pas`、`test.datetimepicker.pas`、`tests/tytests.lpr`（81 次） | 排除 3 个类 |
| `tmp/an1`（ty-an1，HEAD `ffa2d549`） | 108 | 同上（多一次 AnimAxis 等 AdvChart 内部单元） | 同上 |
| ty-advchart 未提交 | — | `AdvanceChart.pas`、`AdvChart.*`、`DefaultTheme.pas`、`Css.Catalog.pas`、`StrConsts.pas`、`tests/tytests.lpr` | 同上 |
| ty-an1 未提交 | — | `AdvanceChart.pas`、`AdvChart.*` | 同上 |
| `3.0-fixes` | 6 | `HtmlLabel.pas`、`Types.pas`、`Painter.pas`、`designtime/…NewItems.pas` | **用户补充：3.0-fixes 会先合进 main 再开工，不排除任何单元**；Task 0 复核为 0 |
| `3.0-fixes` 工作树（`.claude/worktrees/3.0-fixes`） | — | 干净 | — |
| `feat/theme-builder`（ty-3.1） | 163 | `ThemeLint.pas`、`Css.Values.pas`、`Css.Parser.pas`、`designtime/…CssEditKit.pas`、`designtime/…Css.Editor.pas`；未提交只有 `tools/themebuilder/` 两个文件 | 不碰控件单元；会和本计划在 `tests/tytests.lpr`、`tests/tytests.lpi` 上冲突（预期，手工合） |
| `feat/terminal`、`feat/3.1` | 0 | — | — |
`CheckBox.pas` 的修复已以 `a0606352` 进了 main，不排除。

**V11. 文件格式**：`source/`、`designtime/`、`tests/` 的 `.pas` 全部 CRLF、无混合换行；只有 `tests/test.treeview.pas` 带 UTF-8 BOM。补丁工具 `pt.py` 不在仓库里，只在各会话的 scratchpad（本计划把它并进 `split.py`，见下文）。

**V12. 内部辅助子类**（未注册，库里自己建）：`TTyComboPopupList(TTyListBox)` 及其 7 个子类、`TTyCheckComboPopupList(TTyCheckListBox)`、`TTyGridFilterList(TTyCheckListBox)`、`TTyTransferArrowButton(TTyButton)`、`TTyTreeSelectTree(TTyTreeView)`、`TTyValueEdit(TTyEdit)`。B1 下它们照旧从最终类派生，不动（N23）。

**V13. 没有控件在 published 段里放方法或字段**；没有控件在第一个可见性关键字之前写属性（`{$M+}` 下那会默认 published）。

**V14. `scripts/check-lfm-props.py` 只按属性名查**（`declared_properties()` 收集全 `source/` 的 `property` 名），抓不到「漏了重新发布」——那个名字还在 Custom 类的 protected 段里（N21）。能抓到的是快照守卫和【主控】的示例冒烟（`scripts/smoke-launch-examples.ps1`，`.lfm` 读不进来会弹 `#32770` 错误框）。

---

## 拆分规则（每期每个类都照做）

下面「父类」一律指 **`TTyXxx` 拆分前的父类**（B1）。

- **R0 形状**：
  ```pascal
    TTyCustomXxx = class(<原父类>, <原接口列表>)
    private ... protected ... public ...      // 原样搬，见 R1–R4
    published
      { 只有 R3 的那几行（可能为空，为空就不写 published 段） }
    end;

    TTyXxx = class(TTyCustomXxx)
    published
      property A;   // R5：顺序照快照
      property B;
    end;
  ```
  `TTyXxx` 紧跟在 `TTyCustomXxx` 的 `end;` 后面，同一个 `type` 段。**`TTyXxx` 里不许有任何字段、方法、override、构造 / 析构、接口、`class var`**——有一个，第三方的 `TTyCustomXxx` 子类就少一块行为（G4 守 InstanceSize，审查守其余）。
- **R1 搬进 Custom 的**：全部字段、方法（含构造 / 析构、`Loaded`、`DefineProperties`、`Notification`、`GetStyleTypeKey` 等返回字面量的虚方法——第三方子类照样吃主题）、接口列表（`ITyTextEditActions`、`ITyImeEditable`……写在 Custom 的类头上）、类常量（类里的 `const` 段）/ `class var` / `class function` / 嵌套类型（V5-6：经 `TTyXxx.` 访问照常）、原 private / protected / public 段一个字不改。
- **R2 原 published 段里、名字不在父类 published 集合里的属性**：
  - 本类带类型声明的（`property MaxLength: Integer read ... write ... default 0;`）→ 原样放 Custom 的 **protected**（D3 选 public 就放 public），**read / write / index / default / nodefault / stored 一个都不许动**；
  - 不带类型、但带说明符的重声明（`property ParentColor default False;`）→ 放 Custom，可见性**照被重声明属性原来的可见性**（V4：LCL 的 public 就放 public，protected 就放 protected；Ty 父类里的照父类）；
  - 不带类型也不带说明符的纯重新发布（`property Align;`、`property OnDblClick;`）→ **不进 Custom**（只出现在 R5 的发布段）。
- **R3 原 published 段里、名字已在父类 published 集合里的**（不管是纯重声明 `property Font;`、改说明符 `property TabStop default True;`、改写方法 `property Text write SetMaskedText;`，还是同名换类型 `property Style: TTyColorBoxStyle read ...`）→ **原样留在 Custom 的 published 段**。它们不新增 published 名字，只修正 default / stored / 访问器 / 类型，第三方子类也必须拿到修正后的版本（N2）。附录 A 的「已在父类发布、带说明符的重声明」一列就是这一类里带说明符的。
- **R4 Custom 类之外的同单元代码**：方法实现头 `procedure TTyXxx.Foo` → `procedure TTyCustomXxx.Foo`（`split.py impl`）；`{ TTyXxx }` 分隔注释改成 `{ TTyCustomXxx }`；单元里别处的 `TTyXxx` 引用按 R6 / R7 逐处判断，不批量替换。
- **R5 `TTyXxx` 的发布段**：由 `split.py block TTyXxx <父类>` 从快照生成——快照里 `TTyXxx` 的属性按 RTTI 顺序、去掉父类快照里已有的名字，每个写成 `property X;`。**不手写、不调整顺序**（N1）。
- **R6 类型判断**（`is` / `as` / 强转 / `InheritsFrom` / `ClassType`）：语义是「这一类控件」（父子关系、所有者、同组互斥、宿主处理子控件）→ 改成 `TTyCustomXxx`；语义是「库自己建的那个具体对象」或设计期编辑器（D2）→ 保持。附录 C 是逐处的判断，执行时以它为准，新发现的照同一原则补进附录 C。放宽后若要读写原 published 属性，用单元内 access 类（N17）。
- **R7 公开签名里的类型不改**（兼容承诺）：interface 段里的属性类型、函数返回类型、`var` / `out` 参数、事件类型（`TTyTreeNodeEvent = procedure(Sender: TTyTreeView; ...)`）、虚方法的参数——**一律不改**。Custom 类代码里需要把 `Self` 交给这种签名时，在 Custom 类加一个私有内联助手 `function AsPublished: TTyXxx; inline;`（实现 `Result := TTyXxx(Self)`，注释写明「第三方 Custom 子类在这里被当成 TTyXxx 传出，类型是假的，4.0 改签名」），调用处写 `FOnGetText(AsPublished, ...)`。implementation 段里的私有函数、非虚方法的值 / const 参数可以放宽到 Custom（调用方传最终类照样编得过）。每个用到 `AsPublished` 的签名记进附录 D。
- **R8 设计期**：属性编辑器的注册类改成 Custom 类（D2）；组件编辑器、`RegisterComponents`、`RegisterNoIcon`、`RegisterClass`、新建项模板保持最终类。`tests/test.designeditors.pas` 的检查在 Task 7 改成：「注册类 publish 了该属性，**或**注册类名以 `TTyCustom` 开头、且对应最终类（`'TTy' + Copy(名, 10, MaxInt)`）publish 了它」；最终类和 Custom 类都加进 `RegisterClasses` 块。
- **R9 前向声明**：单元里若有 `TTyXxx = class;` 前向声明，保留（它解析到后面的最终类）；若 Custom 类的声明里要用到最终类型（R7 的 `AsPublished` 返回值），而单元里还没有前向声明，就在 Custom 类之前加 `TTyXxx = class;`。别的类声明需要 Custom 类型时加 `TTyCustomXxx = class;`。
- **R10 守卫清单**：每拆一个类，在 `tests/test.customclasses.pas` 里把它从 `CPending` 挪进 `CSplit`（G1–G5 立刻对它生效）。

**按 A 做的差异**（只有 D1 选 A 才看）：R0 的 `<原父类>` 换成「原父类的 Custom 类」（原父类是 `TTyCustomControl` / `TTyGraphicControl` 的不变）；R5 的 `<父类>` 参数相应换成那个 Custom 类的家族根（发布段因此包含整条链上的名字）；四个中间类（`TTyGlyphButtonBase`、`TTyCustomTabStrip`、`TTyCustomGrid`、`TTyShellTreeLink`）的 published 段整体按 R2 / R3 降级，**并在同一个任务里给它们全部已注册后代补发布段**（否则快照跨任务红）；家族内的拆分必须父先子后（期的划分已满足）；附录 C 里标「A 下必改」的点都要改；`examples/toolbar/umain.pas` 的 `Sender as TTyButton` 要改且 `Down` 属性要能访问（逼出 D3=public）；`tests/test.calcedit.pas:40`、`test.scrollbar.autohide.pas:1415` 的祖先断言改写；CHANGELOG 记为「变更（不兼容）」。

---

## 注意事项（每条：为什么 / 怎么防）

**N1 published 属性的顺序就是 `.lfm` 的写出顺序**
- 为什么：`TWriter` 按 RTTI 的 `NameIndex` 顺序写（V5-1），`TReader` 按文件顺序调 setter。重新发布时顺序一变，新存的 `.lfm` 里 `Position` 可能跑到 `Max` 前面，读回来被默认的 `Max = 100` 钳住，值悄悄变了；老 `.lfm` 读得进来，所以示例冒烟和单测都可能是绿的。
- 规则（V5-2）：第一次在 `TTyXxx` 发布的名字按 `TTyXxx` 发布段里写的先后拿号；已在父类发布的名字（`TabStop`、`Font`……）号码固定在祖先，写在哪都不影响顺序。原来写在发布段中间的 `property TabStop default True;` 搬进 Custom 不会挪动别人的位置。
- 怎么防：R5 发布段只从快照生成，不手写；G6 快照逐行比对（含位置列）；变异 M-G6a（对调两行）必须红。

**N2 default 必须等于构造值；重新发布时 default / stored 不能丢、不能变**
- 为什么：`.lfm` 只写「不等于 default」的值（仓库记忆「default 必须等于构造值」「Loaded 同步冲掉设计器流进来的值」）。default 丢了，每个值都写进 `.lfm`，文件变大但不错；default 变了，用户设的值等于新 default 时不写、读回来却是构造值——**静默丢值**。stored 丢了，`stored False` 的位置 / 尺寸（TabSheet、ToolWindow 的 Left / Top / Width / Height）开始写进 `.lfm`，和宿主的布局打架。
- 两个容易漏的地方：① 改了基类 published 属性 default 的重声明（附录 A 那一列，最常见的是 `TabStop default True`，40 处）必须在 **Custom** 类里（R3），只写在 `TTyXxx` 里时，`TTyXxx` 的快照照样绿，但第三方 `TTyCustomEdit` 子类的 `TabStop` default 是 False 而构造值是 True——用户在设计器里把它关掉，存盘不写，读回来又是 True；② 重新发布写成 `property MaxLength: Integer;`（带了类型）就是一个新属性，default 全丢——R5 只写 `property X;`。
- 怎么防：G3（Custom 类与最终类对每个 Custom 已发布的名字 default / stored / index / 类型一致）、G6（快照里的 default、stored、`s=` / `d=` 列）；变异 M-G3（把一处 `TabStop default True` 从 Custom 挪到最终类）、M-G6b（删一个 `default`）、M-G6c（删一个 `stored`）必须红。

**N3 守卫先行**
- 为什么：拆完再拍快照，拍下来的就是拆坏了的样子。
- 怎么防：Task 0 在任何控件改动之前拍快照并提交；后面每个任务都不许重生成快照（`TY_WRITE_GOLDEN=1` 只在 Task 0 用；期末若发现快照本身错了，停下交主控）。快照覆盖面：全部注册类（排除附录 B 的 3 个）+ 7 个基类 / 中间类（`TTyCustomControl`、`TTyGraphicControl`、`TTyComponent`、`TTyGlyphButtonBase`、`TTyCustomTabStrip`、`TTyCustomGrid`、`TTyShellTreeLink`——B1 下它们一个字都不该变，A 下是 R5 生成发布段的输入）。

**N4 库里的类型判断**
- 为什么：B1 下现有的 `is` 答案都不变，所以不改也不会坏；但第三方 `TTyCustomPageControl` 子类里的 `TTyTabSheet` 会因为 `Parent is TTyPageControl` 为假而不认宿主——拆了等于没拆。反过来，把「库自己建的那个对象」的判断放宽，没有收益只有风险。
- 全库实有的判断（去掉注释误报后）：可视控件约 110 处（其中工具窗口三件 43 处），非可视 / 排除 / 不拆的类另计；逐处结论见附录 C。`tests/`、`examples/`、`tools/` 里的 `is` / `as` 判断的都是最终类实例，B1 下不改（A 下必改的见 D1）。
- 怎么防：每处放宽配一条用第三方 Custom 子类走那条路径的测试（附录 C 的「测试」列），变异 = 把那一处改回最终类，必须红。实在无头驱动不到的写「—」并给理由（一般是与另一处同一个判断、已被那条测试覆盖）。

**N5 设计期注册**
- 为什么 / 怎么做：见 D2、R8、V6、V7。另外三件不动：组件面板图标（按最终类名，`scripts/gen-icons.ps1` 与 `tests/test.paletteicons.pas` 都从 `Design.pas` 的 `RegisterComponents` 解析，清单不变）、默认尺寸（在构造里，随 R1 进 Custom，第三方子类拿到同样的尺寸——这是对的）、新建项模板（`designtime/tyControls.Design.NewItems.pas` 只涉及 `TTyForm` / `TTyDialog` / `TTyTitleBar` / `TTyStyleController`，不改）。
- 怎么防：Task 7 改 test.designeditors 时保住它原来的抓错能力——变异 M-D1：把 Custom 类上的注册属性名改错（`'Directory'` → `'Directry'`）必须红；M-D2：把某条挪到 Custom 的注册改回一个不发布该属性的错误类必须红。

**N6 按类名推导东西的地方**
- 核实结果见 V8：typeKey 是字面量，`ClassName` 只用在消息与起名，`RegisterClass` 在最终类上。
- 怎么防：新加的 Custom 类**不要** `RegisterClass`（不在面板、不该被流式按名创建）；测试里需要 `GetClass` 的 Custom 类在测试单元自己注册（R8）。审查时 grep 一遍 `ClassName`、`ClassType`、`ClassParent`、`FindClass`、`GetClass` 有没有新增。

**N7 命名冲突**：见 V9，130 个新名字都不撞。仍要防的是**同一单元里多个类同时拆**（CheckBox.pas 的 CheckBox + RadioButton、ToolBar.pas 的三件、Ribbon.pas 的三件、GlyphButtons.pas 的三件）：`split.py impl` 每次只改一个类的实现头，按类分次跑；`TTyCustomToolButton` 之类的名字先 grep 一遍确认不存在再建。

**N8 改文件的工具坑**（仓库记忆「Git Bash sed -i 吃 CRLF」「Bash heredoc 吃反斜杠」「CRLF 上的变异替换 = 假存活」）
- **绝不用 `sed -i`**（把 CRLF 整份改成 LF，git 的 autocrlf 还会在 diff 里把它盖过去）。
- 含反斜杠的脚本、正则、测试数据用 Write 工具落文件，不用 heredoc（写本计划时实际踩了一次：heredoc 把 `'\\'` 吃成 `'\'`）。
- 改 `.pas` 用 Edit 工具或 `split.py pt`（读入时换行规整成 LF、写回恢复原风格与 BOM，每块先断言命中数）；`split.py check <file>` 对比 `git show HEAD:<file>` 确认换行风格和 BOM 没变。
- FPC 的 `{ }` 注释会嵌套：在注释里写 `{ TTyXxx }` 这类分隔不会出事，但注释里引用代码片段时别带 `{`；线索是第一条 `Comment level 2` 警告。
- 变异：替换后**读回来和原文比**，确认真的改了；`finally` 里还原后**重编一次**（「收割机不还原 exe」）。

**N9 测试里的 cracker 类照常可用**
- 为什么：测试里大量 `TXxxAccess = class(TTyXxx)` 访问 protected 成员（如 `test.focus.tabstop.pas:151` 的 `TGridAccess = class(TTyCustomGrid)`）。拆完 protected 成员在 `TTyCustomXxx` 里，`TTyXxx` 继承它们，cracker 声明在测试单元里，FPC 允许经 cracker 访问继承来的 protected 成员——不用改。private 成员测试本来就碰不到（不同单元）。
- 要注意的一种：测试 cracker 若**重声明**了某个属性来提升可见性（`public property Foo;`），而 Foo 现在是 Custom 的 protected 属性，照样能提；若测试 cracker 写成 `class(TTyCustomXxx)`，就测不到 `TTyXxx` 的发布段了——新写的测试按「测什么就继承什么」选。
- 怎么防：全量里 cracker 相关的编译错误 = 有人往 `TTyXxx` 里留了代码，回去按 R0 挪进 Custom，别改测试。

**N10 合并与后续**
- 3.0 的修复是 cherry-pick 进 main 的。拆过的单元里方法实现头都改成了 `TTyCustomXxx.Foo`，以后从 `3.0-fixes` 摘修复到 main **必冲突**，要手工移植（把补丁里的 `TTyXxx.` 换成 `TTyCustomXxx.`、published 段的改动换到 Custom 的 protected / R5 发布段）。**【主控执行】每期签收后告诉「3.0 问题修复」会话：哪些单元已拆、移植的规矩**（这一条写进签收）。
- `feat/advancechart` 合进 main 之后，按附录 B 补拆 `TTyAdvanceChart`、`TTyCalendar`、`TTyDateTimePicker`。
- `feat/theme-builder` 合进 main 时，`tests/tytests.lpr`、`tests/tytests.lpi` 会冲突（两边都加单元 / 改搜索路径），手工合；合完在 ty-3.1 的 `tools/themebuilder/` 里 grep 一遍 `is TTy` / `as TTy`，B1 下应当不用改。
- 本分支开工前先 `git merge main`（3.0-fixes 会先合进 main，见 Task 0）。

**N11 示例与文档**
- B1 下全部 49 个示例的 `.pas` / `.lfm` 都不该改。【主控执行】每期末编全部示例 + `scripts/smoke-launch-examples.ps1`（它能抓到 `.lfm` 读不进来的弹框）+ `python scripts/check-lfm-props.py`。
- 文档见 D8 / Task 25；CHANGELOG 发版时写（B1 记在「新增」，一句话：「每个控件都有了 TTyCustomXxx 父类，派生时可以只发布需要的属性」）。合 main 前按仓库记忆「合 main 前查 i18n 与 README」查一遍——本计划不加用户可见文字，README 加文档索引一行。

**N12 性能与二进制**：多一层类只多一个 VMT 和一份类型信息（每类几百字节，130 个合计在几十 KB 量级）；published 属性的 RTTI 条目总数不变（Custom 不发布、最终类发布，只是声明位置变了）。虚方法分派、属性访问的生成代码不变，运行时没有差别。`.lpk` 不加单元，安装包大小的变化可以忽略。

**N13 基类发布的通用属性藏不掉**
- 为什么：`TTyCustomControl` 自己发布了 52 个（Enabled、Visible、Font、Hint、TabOrder、TabStop、Constraints、BorderSpacing、Cursor、PopupMenu、Action、StyleClass、StyleOverride、Controller、Version、AutoSize、BorderWidth、ChildSizing、Drag* 和 30 个事件……），`TTyGraphicControl` 41 个，再加 LCL 祖先的 15 个（V3）。V5-4 证明派生类无法取消。所以第三方的 `TTyCustomEdit` 子类在对象查看器里至少有 67 个属性。
- 怎么办：3.x 不改（`Base.pas` 不许动；要藏就得在 `TTyCustomControl` 之下再插一个不发布的基类，并让所有控件改挂——等于改了所有控件的祖先，4.0 的事）。给 issue 的回复要说清（D7），文档写进限制。

**N14 改继承链会改 `is` 的答案**：见 D1。本计划默认 B1，就是为了这一条。审查时专门核：**没有任何既有类的父类变了**（除了被拆的 `TTyXxx` 自己变成 `class(TTyCustomXxx)`——插层不改变任何 `is` 的答案），没有任何既有类的 published 集合变了（G6 快照对 7 个基类 / 中间类也逐行比）。

**N15 既有的「Custom」类不是这个形态**：见 V2。B1 下它们不动：`TTyCustomDrawGrid = class(TTyCustomGrid)` 仍然带着约 68 个 published 属性，`TTyCustomPageControl = class(TTyCustomTabStrip)` 带着约 16 个；文档里如实写（这两个家族的第三方子类能藏的只有本层的属性）。

**N16 原 published 段在 Custom 里放哪**：见 R2 / R3 / V4 / V5-5。最容易犯的错是图省事把整个 `published` 关键字改成 `protected`：编得过（V5-5），快照也绿，但 ① R3 那些改 default 的重声明跑进了 protected，第三方子类的 default 回到祖先的（N2 的坑 ①，G3 抓）；② `property Align;` 之类变成「把 public 降成 protected」的重声明，读代码的人会以为 `TTyCustomXxx.Align` 不能从外面访问。所以按 R2 / R3 分拣，不整段改关键字。

**N17 跨单元读写 Custom 类的 protected 属性**
- 为什么：放宽类型判断后（R6），另一个单元拿 `TTyCustomPageControl(Parent)` 去读写原 published 的属性（现在是 protected）会编不过。
- 怎么做：在**用的那个单元**的 implementation 段声明 `type TTyCustomXxxAccess = class(TTyCustomXxx);`，强转后访问，注释写「protected since the custom-class split; the access class reaches it for any TTyCustomXxx」。不许为此把属性提成 public（D3 定的是 protected），也不许退回强转成最终类（那是类型假话）。基类发布的属性（StyleClass、OnClick……）和原来就是 public 的成员不受影响，直接用。

**N18 test.designeditors 的规则要改**：见 V7 / R8；改法要保住它原来抓「注册到了不存在的属性」的能力（N5 的 M-D1 / M-D2）。

**N19 组件编辑器为什么不跟着挪**：见 D2——动词改的属性在第三方子类里可能没发布，改完存盘丢失。

**N20 `DefineProperties` 照写**
- 为什么：`DefineProperties` 随 R1 进 Custom，第三方子类哪怕不发布 `Items`，`DefineProperties` 写的隐藏数据（GridPanel 的格、ListView 的项、TreeView 的节点等走自定义流的那些）照样进 `.lfm`。这是对的（状态不丢），但第三方可能意外。
- 怎么防：文档写一句；第三方模拟子类的流式测试对「流里出现了哪些名字」的断言把 `DefineProperties` 写的名字单列出来，不当成泄漏。

**N21 check-lfm-props.py 抓不到漏发布**：见 V14。漏了一个 `property X;`，脚本绿、编译绿，只有快照 G6 和【主控】冒烟能发现。所以 G6 必须逐行比、发布段必须脚本生成。

**N22 同单元的引用、实现头、类方法**
- 实现头必须全改（R4）：漏改一个，编译器报「方法未在类里声明」（`TTyXxx` 里没有这个方法）——好事，编译器会抓到。
- 外部按 `TTyShellTreeView.GetFilesInDir(...)`、`TTyFilterComboBox.ConvertFilterToStrings(...)` 调类方法照常（V5-6），不改调用方。
- 字段、局部变量、helper 类里类型写成 `TTyXxx` 的，按 R6 / R7 判断；编译器报「Incompatible type: got TTyCustomXxx expected TTyXxx」时，先看是不是公开签名（R7 → `AsPublished`），不是就放宽。

**N23 内部辅助子类不动**（V12）：它们从最终类派生、被库自己创建，第三方碰不到；改挂 Custom 没有收益。审查时确认没被顺手改了。

**N24 快照守卫是迁移期的**：别的分支给已拆控件加 / 改 published 属性，合进来就会让 G6 红——这时只重生成**那一个类**的快照段（Task 0 的写模式支持按类过滤，见 G6），在提交说明里写清；Task 26 删除（D9）。

**N25 以后的新控件**：G5 常驻——以后谁往面板加一个可视控件，不拆、也不写进 `CNotSplit` 说明理由，全量就红。这正是要的约束；Task 25 的文档和 CONTRIBUTING 的「几条硬规矩」各加一句（CONTRIBUTING 那句需主控确认）。

**N26 无头测试**：第三方模拟子类不建窗口句柄；渲染比较走各控件现成的 `RenderTo`（仓库记忆「验窗口化控件用 RenderTo」），没有 `RenderTo` 的只比 typeKey；对齐靠手调 `AdjustClientRect` + `AlignControls`（仓库记忆「跑不到 LCL 对齐引擎」）。快照里给每个注册类建一个新实例读 `IsStoredProp` / 序数值，个别 getter 无父窗口会抛——记成 `x`，同样是确定的。

**N27 `{ TTyXxx }` 之外的文字**：类头上方的大段说明注释留在 Custom 类上（说明的是实现）；最终类上方只写一行 `{ TTyXxx publishes ...; everything lives in TTyCustomXxx. }`。不要把旧注释里的 `TTyXxx` 全换成 `TTyCustomXxx`——注释讲的是用户看到的控件。

**N28 一个属性两段声明时的顺序陷阱**：极少数类有多个 published 段（中间夹 public），快照顺序以 RTTI 为准，`split.py block` 已经处理；手工检查时别以「源码里第一个 published 段」为准。

---

## 实现期的地雷（每个任务开工前看一眼）

1. **不 amend、不 rebase、不 reset、不 stash、不 checkout 丢改动**；一个任务一个提交，修复另起提交。
2. **绝不用 `sed -i`**；含反斜杠的内容用 Write 落文件；`.pas` 用 Edit 或 `split.py pt`（N8）。
3. **只按 PID 结束进程，绝不 `taskkill -im`**（全机器按镜像名杀，会杀掉别的会话的测试）。
4. **不编 `.lpk`、不编 `examples/`**（【主控执行】）；只编 `tests/tytests.lpi`（它不依赖 tycontrols 包，`OtherUnitFiles` 直接指 `../source`，不碰机器级包注册）。
5. **不改** `Base.pas`、`Painter.pas`、`StyleModel.pas`、`TextMenu.pas`、`DefaultTheme.pas`、`Css.Catalog.pas`、`StrConsts.pas`；排除的 `AdvanceChart.pas`、`Calendar.pas`、`DateTimePicker.pas` 一行都不碰。某个控件的拆分非改不可，标「需主控 / 用户确认」停下。
6. **不改任何既有类的父类与 published 集合**（B1）；`TTyXxx` 里不留任何代码（R0）。
7. **发布段只用 `split.py block` 生成**，不手写、不调顺序（N1）；不重生成快照（N3）。
8. **公开签名不改类型**（R7）；放宽类型判断只在附录 C 列的地方，新发现的照原则补进附录 C 并写测试。
9. **编译探针别把 `.ppu` 写进 `source/`**：任何手编都带 `-FU`；每期编译前 `ls source/*.ppu source/*.o 2>/dev/null` 必须为空，有就删（仓库记忆「并行 agent 的三个坑」第四条）。
10. **跑 tytests 用复制出来的独有名字 `tytests-split.exe`，输出重定向到文件**；判据是每个 suite 那一行有 `Number of run tests`、errors / failures 为 0，不是 exit code（被杀的那次输出是空的）。
11. **单跑绿 / 全量红**：先 `lazbuild -B` 重编，再查进程级状态（仓库记忆「变异后必须重编再全量」「全量红单跑绿：前置 suite 初始化了 widgetset」「偶发失败」）。
12. **注释与代码风格**：库里新加的注释用英文、照所在单元的惯例；提交说明英文。

---

## 跑测试的固定套路（只在 Task 0 与每期收尾跑）

改了 `source/` 或 `designtime/` 之后必须 `lazbuild -B`。新工作树第一次编会把 `source/` 全编一遍，耗时正常。

```bash
cd /d/Projects/ty-split && ls source/*.ppu source/*.o 2>/dev/null | wc -l && lazbuild -B tests/tytests.lpi > /tmp/split-build.txt 2>&1 || { tail -30 /tmp/split-build.txt; false; } && grep -c "Error:" /tmp/split-build.txt; cd tests && cp tytests.exe tytests-split.exe && for s in $SUITES; do ./tytests-split.exe --suite=$s --format=plain > /tmp/split-$s.txt 2>&1; printf '%s: ' $s; grep -E "Number of (run tests|errors|failures|ignored)" /tmp/split-$s.txt | tr '\n' ' '; echo; done
```

第一个数必须是 0（没有游离的 `.ppu`）。`SUITES` 至少包含：`TTyCustomClassesGuardTest TVersionTest TDesignEditorsTest TPaletteIconTest TTyFocusTabStopTest TTyClickFocusTest`，加上当期的 `TTyCustomClassesP1Test` / `P2` / `P3`，再加当期动过的控件自己的 suite（`grep -l "TTyXxx" tests/test.*.pas` 找出单元，再取其中 `RegisterTest(...)` 的类名）。

全量（输出必须重定向到文件）：

```bash
cd /d/Projects/ty-split/tests && ./tytests-split.exe --all --format=plain > /tmp/split-all.txt 2>&1; grep -E "Number of (run tests|errors|failures|ignored)" /tmp/split-all.txt; grep -E "^\s+(Failed|Error):" /tmp/split-all.txt | head -40
```

---

## 辅助脚本 `split.py`（scratchpad，不进仓库）

每期开工时若 scratchpad 里没有，用 **Write 工具**（不是 heredoc）原样写到 `<scratchpad>/split.py`。在 `D:/Projects/ty-split` 下运行。

```python
#!/usr/bin/env python
"""Custom-class split helper. Run from the repo root (D:/Projects/ty-split).

  python split.py block <TTyXxx> <ParentClass>
      Print the TTyXxx published section from the Task 0 snapshot: the names
      TTyXxx has and <ParentClass> does not, in RTTI order. To stderr: every name
      both have whose attributes differ (those are R3 lines -- they must sit in
      TTyCustomXxx's own published section, verbatim).
  python split.py impl <unit.pas> <TTyXxx>
      Rename the implementation headers `procedure TTyXxx.` (and function /
      constructor / destructor / class procedure / class function / operator)
      to TTyCustomXxx. Prints the count; refuses 0.
  python split.py pt <file> <patchfile>
      pt.py format: blocks of '@@@@ OLD [n]' / '@@@@ NEW' / '@@@@ END'. Each OLD
      must occur exactly n times (default 1). Newline style and BOM preserved.
  python split.py check <file>
      Newline style and BOM of <file> must equal `git show HEAD:<file>`.
"""
import re, subprocess, sys

SNAP = 'tests/fixtures/customclasses/published-snapshot.txt'


def die(msg):
    sys.stderr.write(msg + '\n')
    sys.exit(1)


def read(path):
    b = open(path, 'rb').read()
    bom = b.startswith(b'\xef\xbb\xbf')
    if bom:
        b = b[3:]
    t = b.decode('utf-8')
    crlf = '\r\n' in t
    if crlf:
        if '\n' in t.replace('\r\n', ''):
            die('mixed newlines in ' + path)
        t = t.replace('\r\n', '\n')
    return t, crlf, bom


def write(path, t, crlf, bom):
    if crlf:
        t = t.replace('\n', '\r\n')
    b = t.encode('utf-8')
    if bom:
        b = b'\xef\xbb\xbf' + b
    open(path, 'wb').write(b)


def load_snapshot():
    t, _, _ = read(SNAP)
    out, cur = {}, None
    for line in t.split('\n'):
        if line.startswith('# '):
            cur = line[2:].split()[0]
            out[cur] = []
        elif line and cur:
            f = line.split('\t')
            if len(f) != 10:
                die('bad snapshot line: ' + line)
            out[cur].append(f)
    return out


def block(final, parent):
    s = load_snapshot()
    for c in (final, parent):
        if c not in s:
            die(c + ' is not in the snapshot')
    pmap = {f[2].lower(): f for f in s[parent]}
    own = [f for f in s[final] if f[2].lower() not in pmap]
    print('  %s = class(TTyCustom%s)' % (final, final[3:]))
    print('  published')
    for f in own:
        print('    property %s;' % f[2])
    print('  end;')
    for f in s[final]:
        p = pmap.get(f[2].lower())
        # columns 3..8 = type, kind, default, stored, index, access
        if p is not None and p[3:9] != f[3:9]:
            sys.stderr.write('R3 %s: %s=%s  %s=%s\n' % (
                f[2], parent, '|'.join(p[3:9]), final, '|'.join(f[3:9])))


def impl(path, final):
    t, crlf, bom = read(path)
    custom = 'TTyCustom' + final[3:]
    pat = re.compile(r'^((?:class\s+)?(?:procedure|function|constructor|destructor|operator)\s+)'
                     + re.escape(final) + r'\.', re.M | re.I)
    n = len(pat.findall(t))
    if n == 0:
        die('no implementation headers of %s in %s' % (final, path))
    t = pat.sub(lambda m: m.group(1) + custom + '.', t)
    write(path, t, crlf, bom)
    print('%s: %d headers -> %s' % (path, n, custom))


def pt(path, patch):
    t, crlf, bom = read(path)
    p = open(patch, encoding='utf-8', newline='').read().replace('\r\n', '\n')
    n = 0
    for b in re.split(r'^@@@@ END\n?', p, flags=re.M):
        if '@@@@ OLD' not in b:
            continue
        m = re.match(r'.*?^@@@@ OLD( \d+)?\n(.*?)^@@@@ NEW\n(.*)$', b, flags=re.S | re.M)
        if not m:
            die('bad block: ' + b[:80])
        cnt = int(m.group(1)) if m.group(1) else 1
        old, new = m.group(2), m.group(3)
        c = t.count(old)
        if c != cnt:
            die('expected %d got %d: %r' % (cnt, c, old[:120]))
        t = t.replace(old, new)
        n += 1
    write(path, t, crlf, bom)
    print('%s: %d blocks applied' % (path, n))


def check(path):
    head = subprocess.run(['git', 'show', 'HEAD:' + path.replace('\\', '/')],
                          capture_output=True).stdout
    now = open(path, 'rb').read()
    def style(b):
        return (b.startswith(b'\xef\xbb\xbf'), b'\r\n' in b, b.replace(b'\r\n', b'').count(b'\n'))
    h, w = style(head), style(now)
    if h[0] != w[0] or h[1] != w[1] or (w[1] and w[2] != 0):
        die('%s: BOM/newline changed: HEAD bom=%s crlf=%s, now bom=%s crlf=%s stray-LF=%d'
            % (path, h[0], h[1], w[0], w[1], w[2]))
    print(path + ': ok')


if __name__ == '__main__':
    a = sys.argv[1:]
    if a[:1] == ['block'] and len(a) == 3:
        block(a[1], a[2])
    elif a[:1] == ['impl'] and len(a) == 3:
        impl(a[1], a[2])
    elif a[:1] == ['pt'] and len(a) == 3:
        pt(a[1], a[2])
    elif a[:1] == ['check'] and len(a) == 2:
        check(a[1])
    else:
        die(__doc__)
```

**每个类的标准步骤**（Task 1–24 的「拆」都指这一串，任务里不再重复）：
1. `python split.py block TTyXxx <父类>`，把输出和 stderr 的 R3 清单存进 scratchpad 草稿。
2. 在单元里把类头 `TTyXxx = class(` 改成 `TTyCustomXxx = class(`（Edit 工具）。
3. 按 R2 / R3 分拣原 published 段（附录 A 的「带说明符的重声明」列 + 第 1 步的 R3 清单是检查表）。
4. 在 Custom 类 `end;` 后贴第 1 步打印的最终类声明，前面加一行注释（N27）。
5. `python split.py impl source/tyControls.Xxx.pas TTyXxx`；改 `{ TTyXxx }` 分隔注释。
6. 同单元内其余 `TTyXxx` 引用按 R6 / R7 / 附录 C 处理；需要 `AsPublished` 的加上（R7）。
7. `tests/test.customclasses.pas`：`CPending` → `CSplit`（R10）。
8. `python split.py check source/tyControls.Xxx.pas`（以及本任务动过的每个文件）。

---

## 关于判据和变异

- 守卫与模拟子类写**判据**（比什么、怎么数、失败打印什么），测试代码执行时现写（仓库记忆「plan 里写判据别写测试代码」）。快照格式这种「数据契约」写死在 Task 0。
- 每条判据写明「**在哪个变异下必须红**」；变异在每期收尾集中做：改一行 → **读回来与原文比，确认真改了** → `lazbuild -B` → 跑相关 suite → **必须红** → 改回 → 重编 → 重跑 → 绿。没红先查改没改对地方（CRLF 假存活）、再查是不是「这条路走不到」；确实没红，当场补测试，签收写一句。
- 断言里那个量要真的变过（仓库记忆「断言里那个量从没变过」）：「第三方子类的 `TabStop` default 与构造值一致」之前先证明这个类的构造值确实不是 LCL 的默认；「放宽后第三方子项被宿主认出」之前先证明**改回最终类时**它不被认出（变异就是这个）；「流里没有未发布的名字」之前先证明那个属性在实例上不是默认值。
- 「—」= 不做变异，理由写在表里（结构性检查、纯文档、与另一条同一个判断）。

---

## 第 0 期

### Task 0: 起点、RTTI 快照、常驻结构守卫、基线

**Files:**
- Create: `tests/test.customclasses.pas`（suite `TTyCustomClassesGuardTest`）
- Create: `tests/fixtures/customclasses/published-snapshot.txt`
- Modify: `tests/tytests.lpr`（uses 末尾加 `test.customclasses`）
- 不进仓库：`<scratchpad>/split.py`

- [ ] **Step 1: 【主控执行】开工前问题 D1–D9**：D1 必须问用户；其余主控定。答复写进「开工前要定的问题」开头的「状态」块。D1 选 A，就按「拆分规则 · 按 A 做的差异」改本计划后再开工；D6 选「不拆」，把工具窗口三件写进 `CNotSplit`（理由「3.x public signatures of the manager pin the final classes; 4.0」）、跳过 Task 24。

- [ ] **Step 2: 起点**

```bash
cd /d/Projects/ty-split && git status --short && git branch --show-current && git merge --no-edit main && git log --oneline -1 && git cherry main 3.0-fixes | grep -c '^+'
```

Expected：工作区干净；分支 `feat/custom-classes`；合并成功（3.0-fixes 应已合进 main，所以这里会快进或产生一个合并提交）；**最后一个数是 0**。不为 0 = 3.0-fixes 还有修复没进 main，**停下交主控**。

- [ ] **Step 3: 复核排除清单**

```bash
cd /d/Projects/ty-split && for b in feat/advancechart tmp/an1; do for c in $(git cherry main $b | grep '^+' | awk '{print $2}'); do git show --name-only --format= $c; done; done | grep -E '^(source|designtime)/' | grep -vE 'AdvChart\.|AdvanceChart|Base\.pas|Painter\.pas|FontUnits|DefaultTheme|Css\.Catalog|StrConsts' | sort -u; for t in /d/Projects/ty-advchart /d/Projects/ty-an1 /d/Projects/ty-3.1; do git -C $t status --short | grep -E '(source|designtime)/'; done; for c in $(git cherry main feat/theme-builder | grep '^+' | awk '{print $2}'); do git show --name-only --format= $c; done | grep -E '^source/tyControls\.' | grep -vE 'ThemeLint|Css\.' | sort -u
```

Expected：第一段只有 `source/tyControls.Calendar.pas`、`source/tyControls.DateTimePicker.pas`；第二段只有 AdvChart 相关与上面那几个共享单元；第三段为空。**多出任何控件单元**：把它的类移进 `CNotSplit`（理由「touched by <branch>, split after it merges」），从本计划对应任务里划掉，附录 B 加一行，签收里写明。

- [ ] **Step 4: 辅助脚本**：照「辅助脚本 `split.py`」一节用 Write 工具写进 scratchpad；`python split.py` 不带参数应打印用法并以 1 退出。

- [ ] **Step 5: 守卫单元 `tests/test.customclasses.pas`**（单元头注释：为什么有它——issue #8 的拆分要保证「`.lfm` 一个字不变、第三方子类拿到同样的默认值」，快照在拆分前由当时的代码生成；G6 是迁移期的，Task 26 删除，G1–G5 常驻）。uses `test.designregistry`（`CollectRegisteredClassNames`、`RepoRoot`）、`test.version`（它的 initialization 把所有注册类 `RegisterClasses`，`GetClass` 才拿得到）和 7 个基类所在单元。

  **清单常量**（R10）：
  - `CSplit`：已拆的最终类，Task 0 为空（用 initialization 里填的动态数组，FPC 不允许空的常量数组）。
  - `CPending`：Task 0 填入附录 A「处置」列为 T1–T24 的 133 个名字（D6 选不拆时 130 个），每个任务挪走自己那几个；Task 26 删掉这个清单。
  - `CNotSplit`：名字 + 一句英文理由：`TTyForm`、`TTyDialog`（designer base classes, already TForm）、`TTyFormSurface`、`TTyGridCell`（D5）、`TTyAdvanceChart`、`TTyCalendar`、`TTyDateTimePicker`（split after feat/advancechart merges, appendix B），D6 选不拆时加工具窗口三件。
  - `CSnapshotExempt`：`TTyAdvanceChart`、`TTyCalendar`、`TTyDateTimePicker`。
  - `CSnapshotBases`：`TTyCustomControl`、`TTyGraphicControl`、`TTyComponent`、`TTyGlyphButtonBase`、`TTyCustomTabStrip`、`TTyCustomGrid`、`TTyShellTreeLink`（类引用，直接写）。

  **G6 `TestPublishedSnapshotUnchanged`（迁移期）**：
  - 总体 = `CollectRegisteredClassNames` 经 `GetClass` 解析的类 − `CSnapshotExempt` + `CSnapshotBases`，按类名排序。
  - 每个类先一行头 `# <ClassName> n=<published 属性个数>`，再按 `GetPropList(cls, L)` 的顺序每个属性一行，10 列以 **Tab** 分隔：
    `Class  Pos  Name  TypeName  Kind  Default  Stored  Index  Access  Fresh`
    - `Pos`：在 `GetPropList` 结果里的下标（0 起）；`TypeName` = `PropType^.Name`；`Kind` = `GetEnumName(TypeInfo(TTypeKind), Ord(Kind))`；`Default` = `PropInfo^.Default` 的十进制（不管类型，原样）；`Stored`：`(PropProcs shr 4) and 3 = ptConst` 时 `StoredProc <> nil` 记 `T`、否则 `F`，其余（字段 / 方法）记 `D`；`Index` = `PropInfo^.Index`；`Access` = `R` / `W` / `RW`（`GetProc` / `SetProc` 是否非 nil）。
    - `Fresh`：只对注册类算（基类记 `-`）：用 `Create(nil)`（`TCustomForm` 后代用 `CreateNew(nil)`，同 `test.version.pas` 的 `InstantiateForCheck`）建一个新实例，记 `s=<1|0>`（`IsStoredProp`）加 `,d=<eq|ne|->`（Kind 属于 tkInteger / tkChar / tkWChar / tkEnumeration / tkBool / tkSet / tkInt64 / tkQWord 且 `Default <> Low(LongInt)` 时比较 `GetOrdProp(实例, PI) = Default`，否则 `-`）；任一步抛异常记 `x`。实例用完释放。
  - 写模式：环境变量 `TY_WRITE_GOLDEN=1` 时把输出写进夹具（LF、UTF-8、无 BOM）后通过；另支持 `TY_WRITE_GOLDEN_CLASS=<类名>` 只替换夹具里那一个类的段（N24 用）。否则读夹具，**两边 CRLF 都换成 LF 再比**；不同则失败信息打印：不同的行数、第一处不同的行号、两边那一行、以及所在的类名。
  - 判据：Task 0 写出的夹具里 `TTyEdit` 段的第一行是 `Name`、包含 `Text`、`TabStop` 行的 `Default` 为 1；全文件类头个数预计 179（`CollectRegisteredClassNames` 的 175 个名字——面板与 NoIcon 173 + 设计器基类 2——减豁免 3，加基类 7），以实际为准，签收记下。
  - 变异：M-G6a 对调 `TTyEdit` 发布段相邻两行；M-G6b 删掉 `TTyCustomEdit` 里 `MaxLength` 的 `default 0`；M-G6c 删掉 `TTyCustomTabSheet` 里 `Left` 的 `stored False`（2 期才有，2 期收尾做）——都必须红。

  **G1 `TestSplitClassesSitOnTheirCustomClass`**：对 `CSplit` 每个类 `C`：`C.ClassParent.ClassName = 'TTyCustom' + Copy(C.ClassName, 4, MaxInt)`。失败列出全部不符的类。变异 M-G1：把一个已拆的最终类改回直接继承原父类（同时保留 Custom 类）→ 红。

  **G2 `TestCustomClassesPublishNothingNew`**：对 `CSplit` 每个类：`Custom := C.ClassParent`；Custom 的 published 名字集合（不区分大小写）= `Custom.ClassParent` 的 published 名字集合。失败列出「类：多出的名字」。变异 M-G2：在 `TTyCustomEdit` 的 published 段留一行 `property MaxLength ...` → 红。

  **G3 `TestCustomAndFinalAgreeOnEveryInheritedProperty`**：对 `CSplit` 每个类，Custom 的每个 published 属性与最终类同名属性的 `TypeName`、`Default`、`Stored`、`Index`、`Access` 五项一致。失败列出「类.属性：Custom=… Final=…」。变异 M-G3：把 `TTyCustomEdit` 的 `property TabStop default True;` 挪到 `TTyEdit` 的发布段 → 红。

  **G4 `TestFinalClassesAddNoFields`**：对 `CSplit` 每个类：`C.InstanceSize = C.ClassParent.InstanceSize`。变异 M-G4：给 `TTyEdit` 加一个 `FDummy: Integer` 字段 → 红。

  **G5 `TestEveryRegisteredControlIsAccountedFor`**：总体 = 注册类中 `InheritsFrom(TControl)` 的。① 每个都恰好在 `CSplit`、`CPending`、`CNotSplit` 之一；② 三者两两不相交；③ `CNotSplit` 和 `CPending` 里的类**没有**被拆（`ClassParent.ClassName` 不是 `'TTyCustom' + …`）；④ `CSplit` 的每个都在总体里。失败分四类列名字。变异 M-G5：拆完一个类却忘了把它挪出 `CPending` → ③ 红。

- [ ] **Step 6: 注册**：`tests/tytests.lpr` uses 末尾加 `test.customclasses`。

- [ ] **Step 7: 基线编译、生成夹具、跑全量**（本任务的例外，实现 agent 做）：

```bash
cd /d/Projects/ty-split && ls source/*.ppu source/*.o 2>/dev/null | wc -l && lazbuild -B tests/tytests.lpi > /tmp/split-build.txt 2>&1 || { tail -30 /tmp/split-build.txt; false; }; cd tests && cp tytests.exe tytests-split.exe && mkdir -p fixtures/customclasses && TY_WRITE_GOLDEN=1 ./tytests-split.exe --suite=TTyCustomClassesGuardTest --format=plain > /tmp/split-gold-w.txt 2>&1; ./tytests-split.exe --suite=TTyCustomClassesGuardTest --format=plain > /tmp/split-gold.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/split-gold.txt; grep -c "^# " fixtures/customclasses/published-snapshot.txt; wc -l fixtures/customclasses/published-snapshot.txt; grep -c "	x$" fixtures/customclasses/published-snapshot.txt
```

Expected：编译 0 错；第二次跑 5 条全过；类头个数记下（预计 179）；总行数几千行；`x` 的个数记下（应很少，每个都是无父窗口的 getter——列进签收，执行中不许变）。然后跑全量（「跑测试的固定套路」），**条数与红名单记进草稿**，期末签收写进本计划。**除已知偶发失败外有别的红就停。**

- [ ] **Step 8: 提交**

```bash
cd /d/Projects/ty-split && git add tests/test.customclasses.pas tests/fixtures/customclasses tests/tytests.lpr && git commit -m "test(controls): snapshot every published property before the custom-class split

Issue #8 asks for a TTyCustomXxx parent behind every control, with the
properties protected and TTyXxx only republishing them. A republished
property inherits its default and stored clause, but its position in
RTTI -- and so its place in a saved .lfm -- is wherever it is first
published. This fixture holds the name, type, default, stored clause,
index, access and position of every published property of every
registered class as it is today, so the split can prove nothing moved.

Five structural guards go in with it and stay after the migration:
every split class sits directly on its custom class, the custom class
publishes nothing new, both agree on every inherited property, the
final class adds no field, and every registered control is either
split or listed with a reason.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 第 1 期：输入与显示

**本期新建** `tests/test.customclasses.p1.pas`（suite `TTyCustomClassesP1Test`，Task 1 建、之后每个任务往里加；`tests/tytests.lpr` uses 加 `test.customclasses.p1`）。单元头注释说明它装的是「第三方模拟子类」和「放宽了的类型判断」的测试。

**第三方模拟子类的统一判据**（每个任务列出它的模拟类；名字 `TThirdXxx = class(TTyCustomXxx)`，published 段写任务里点名的 2 个属性；测试单元的 initialization 里 `RegisterClass` 它们）：
- T-a 能建：`TThirdXxx.Create(Form)` 不抛；放到一个 `TForm.CreateNew(nil)` 上。
- T-b 只发布了点名的：`GetPropList(TThirdXxx)` 的名字集合 = `GetPropList(TTyCustomXxx)` 的名字集合 ∪ 点名的 2 个。
- T-c 流式往返：把点名的 2 个属性设成非默认值，再把任务里点名的「隐藏属性」经 access 类（`TThirdXxxAccess = class(TThirdXxx)`，public 重声明那一个）设成非默认值；`WriteComponent` → `ObjectBinaryToText`：文本里有那 2 个名字、**没有**隐藏属性的名字（`DefineProperties` 写的名字按 N20 单列允许）；`ReadComponent` 回来 2 个值相等。
- T-d 主题相同：经 `TTyCustomControl` / `TTyGraphicControl` 的 access 类调 `GetStyleTypeKey`，与同设置的 `TTyXxx` 实例相等；该控件有现成 `RenderTo` 的，同尺寸、同 Caption / 值渲染到白底位图，逐像素相等。
- T-e 默认值站得住：对点名的 2 个属性，新实例的值 = 该属性的 `Default`（有 default 的）或 `IsStoredProp = False`。
- 变异：M-T（每期一条代表）：把某个家族的 `GetStyleTypeKey` 从 Custom 挪到最终类 → 该家族模拟子类 T-d 红（抽象方法错误或 typeKey 不同）。

### Task 1: 按钮

**Files:** Modify `source/tyControls.Button.pas`、`GlyphButtons.pas`、`DropButtons.pas`、`ColorButton.pas`、`ButtonGroup.pas`、`ToolBar.pas`（只改附录 C 的 C1-2 那一处）、`ToolBarEx.pas`（C1-3）、`tests/test.customclasses.pas`；Create `tests/test.customclasses.p1.pas`；Modify `tests/tytests.lpr`。

| 类 | Custom 父类（=原父类） | R3 要留在 Custom published 的 |
|---|---|---|
| TTyButton | TTyCustomControl | `TabStop default True` |
| TTyGlyphButton | TTyGlyphButtonBase | — |
| TTyGlyphContainerButton | TTyGlyphButtonBase | `GlyphLayout default glTop` |
| TTySpeedButton | TTyGlyphButtonBase | `TabStop default False` |
| TTyDropDownButton | TTyButton | — |
| TTyMenuButton | TTyButton | — |
| TTyColorButton | TTyButton | `Alignment default taLeftJustify` |
| TTyButtonGroup | TTyCustomControl | `TabStop default True` |

- [ ] **Step 1: 拆**：按「每个类的标准步骤」逐个拆。GlyphButtons.pas 三个类分三次 `impl`；`TTyGlyphButtonBase` 不动。`TTyDropDownButton` / `TTyMenuButton` 在 DropButtons.pas，分两次。`TTyRibbonAppMenu`（`class(TTyMenuButton)`，3 期）不受影响。
- [ ] **Step 2: 类型判断**：附录 C 的 C1-1（GlyphButtons 同组互斥、`FindDownButton`——返回类型 `TTySpeedButton` 不改，按 R7 用 `AsPublished` 之类的强转，记附录 D）、C1-2（ToolBar 扁平样式）、C1-3（ToolBarEx 扁平样式与溢出弹层点击包装）。
- [ ] **Step 3: 测试**（`test.customclasses.p1.pas`）：
  - 模拟类：`TThirdButton`（发布 `Caption`、`Down`；隐藏 `ModalResult`）；`TThirdSpeedButton`（发布 `GroupIndex`、`Down`；隐藏 `AllowAllUp`）；T-a…T-e。
  - S1-1：同一父控件上一个 `TTySpeedButton` 和一个 `TThirdSpeedButton`，`GroupIndex = 1`、`AllowAllUp = False`（经 access）：按下一个，另一个弹起；两个方向各测一次。变异：C1-1 第一处改回 `TTySpeedButton` → 红。
  - S1-2：`Flat = True` 的 `TTyToolBar` 上放一个 `TThirdButton`，手调一次布局（`AdjustClientRect` + `AlignControls`，N26），它的 `StyleClass = 'ghost'`；先证明不放宽时它是 `''`（变异就是这个）。变异：C1-2 改回 → 红。
  - S1-3：同 S1-2，换成 `TTyToolBarEx`；若溢出弹层在无头下驱动不到，写「—：与 S1-2 是同一判断，审查覆盖」。
- [ ] **Step 4: `CPending` → `CSplit`**：上表 8 个类。
- [ ] **Step 5: 提交**：`refactor(controls): split the button family into TTyCustomXxx and a published TTyXxx`（正文：B1 规则一句、放宽的判断、R7 记下的签名；结尾 Co-Authored-By）。

### Task 2: 标签

**Files:** `source/tyControls.TyLabel.pas`、`HtmlLabel.pas`、`LinkLabel.pas`、`ShadowLabel.pas`、`GlowLabel.pas`、`Tag.pas`、`Badge.pas`、两个测试单元。

全部 `Custom 父类 = 原父类`（`TTyHtmlLabel` 是 `TTyCustomControl`，其余 `TTyGraphicControl`）；附录 A 无 R3 带说明符的行（`split.py block` 的 stderr 为准）。无附录 C 条目。`TTyLabel` 是主题锁定的（仓库记忆「TTyLabel theme-locked」），`RenderTo` 等画法全在 Custom 里，第三方子类同样锁定——文档写一句。

- [ ] **Step 1: 拆** 7 个类。
- [ ] **Step 2: 测试**：`TThirdLabel`（发布 `Caption`、`WordWrap`；隐藏 `Layout`）、`TThirdTag`（发布 `Caption`、`Closable`；隐藏属性执行时从附录 A 里该类新发布的属性中挑一个非事件的）；T-a…T-e，`TTyLabel` 走 `RenderTo` 逐像素。
- [ ] **Step 3: `CPending` → `CSplit`**、提交 `refactor(controls): split the label family ...`。

### Task 3: 编辑框 I

**Files:** `source/tyControls.Edit.pas`（2729 行）、`NumericEdit.pas`、`CurrencyEdit.pas`、`MaskEdit.pas`、`URLEdit.pas`、`ComboEdit.pas`、`TrackEdit.pas`、`CalcEdit.pas`、`CalcCurrencyEdit.pas`、测试单元。

| 类 | Custom 父类 | R3 |
|---|---|---|
| TTyEdit | TTyCustomControl | `TabStop default True` |
| TTyNumericEdit | TTyEdit | — |
| TTyCurrencyEdit | TTyNumericEdit | — |
| TTyMaskEdit | TTyEdit | `Text write SetMaskedText`（改写方法的重声明；它上面那段「静态绑定」注释跟着走） |
| TTyURLEdit | TTyEdit | — |
| TTyComboEdit | TTyEdit | — |
| TTyTrackEdit | TTyNumericEdit | — |
| TTyCalcEdit | TTyNumericEdit | — |
| TTyCalcCurrencyEdit | TTyCurrencyEdit | — |

- [ ] **Step 1: 拆**：先 Edit.pas，再按父先子后。`TTyEdit` 的接口列表 `ITyTextEditActions, ITyImeEditable` 写在 `TTyCustomEdit` 类头上（R1）。`TTyValueEdit`（ValueListEditor.pas，内部）不动（N23）。
- [ ] **Step 2: 测试**：`TThirdEdit`（发布 `Text`、`ReadOnly`；隐藏 `MaxLength`）；T-a…T-e，另加 T-f：`Supports(TThirdEdit 实例, ITyImeEditable)` 与 `Supports(..., ITyTextEditActions)` 都为 True（变异：把接口列表挪到 `TTyEdit` 类头 → 红）。`TThirdMaskEdit`（发布 `EditMask`、`Text`；隐藏 `SpaceChar`）：给 `EditMask` 后经 `Text` 赋值走的是带掩码的 setter（结果与 `TTyMaskEdit` 同输入同输出）。
- [ ] **Step 3: `CPending` → `CSplit`**、提交。

### Task 4: 编辑框 II

**Files:** `source/tyControls.Calculator.pas`、`Memo.pas`（5023 行）、`SpinEdit.pas`、`FloatSpinEdit.pas`、`UpDown.pas`、测试单元。

| 类 | Custom 父类 | R3 |
|---|---|---|
| TTyCalculator | TTyCustomControl | `TabStop default True` |
| TTyMemo | TTyCustomControl | `TabStop default True` |
| TTySpinEdit | TTyCustomControl | `TabStop default True` |
| TTyFloatSpinEdit | TTyNumericEdit | `UseThousands default False` |
| TTyUpDown | TTyGraphicControl | — |

- [ ] **Step 1: 拆**；Memo 若实现 `ITyTextEditActions` 等接口，照 R1 放 Custom。
- [ ] **Step 2: 类型判断**：附录 C 的 C4-1（UpDown 关联互斥）。
- [ ] **Step 3: 测试**：`TThirdMemo`（发布 `Lines`、`ReadOnly`；隐藏 `WantTabs`）、`TThirdUpDown`（发布 `Associate`、`Position`；隐藏 `Increment`）；T-a…T-e。S4-1：同一父控件上 `TTyUpDown` 已关联某个编辑框，`TThirdUpDown` 再关联同一个 → 抛异常；反过来也一样。变异：C4-1 改回 → 红。
- [ ] **Step 4: `CPending` → `CSplit`**、提交。

### Task 5: 选择

**Files:** `source/tyControls.CheckBox.pas`（CheckBox + RadioButton）、`ToggleSwitch.pas`、`Segmented.pas`、测试单元。四个类 Custom 父类 = `TTyCustomControl`，R3 都是 `TabStop default True`。

- [ ] **Step 1: 拆**：CheckBox.pas 两个类分两次 `impl`；`a0606352` 刚改过这里（AutoSize 量全标题），确认改动随 R1 进了 Custom。
- [ ] **Step 2: 类型判断**：C5-1 放宽（单选同组互斥）；C5-2 保持（RadioGroup 的 Sender 只会是它自己建的 `TTyRadioButton`）。
- [ ] **Step 3: 测试**：`TThirdCheckBox`（发布 `Checked`、`Caption`；隐藏 `AllowGrayed`）、`TThirdRadioButton`（发布 `Checked`、`GroupIndex`）；T-a…T-e（CheckBox 有 `RenderTo` 就逐像素）。S5-1：同一父控件、同 `GroupIndex` 的 `TTyRadioButton` 与 `TThirdRadioButton`，勾一个另一个取消，两个方向。变异：C5-1 改回 → 红。
- [ ] **Step 4: `CPending` → `CSplit`**、提交。

### Task 6: 组合框 I

**Files:** `source/tyControls.ComboBox.pas`（2126 行）、`MRUComboBox.pas`、`ComboBoxEx.pas`、`OfficeComboBox.pas`、`AdvancedComboBox.pas`、`CheckComboBox.pas`、测试单元。

| 类 | Custom 父类 | R3 |
|---|---|---|
| TTyComboBox | TTyCustomControl | `TabStop default True` |
| TTyMRUComboBox / TTyComboBoxEx / TTyOfficeComboBox / TTyAdvancedComboBox / TTyCheckComboBox | TTyComboBox | — |

- [ ] **Step 1: 拆**：`TTyComboPopupList` 及其子类（内部）不动。
- [ ] **Step 2: 类型判断**：C6-1（`TyComboOwnerOf`，implementation 私有函数，返回类型可以放宽到 `TTyCustomComboBox`，调用处 4 个随之改）、C6-2（ComboBoxEx 的 ItemsEx 所有者 ×3）、C6-3（AdvancedComboBox 弹层取 Images）、C6-4（CheckComboBox 弹层所有者）放宽；C6-5（CheckComboBox 的 `is TTyCheckListBox` ×3，弹层是它自己建的）保持。
- [ ] **Step 3: 测试**：`TThirdComboBox`（发布 `Items`、`ItemIndex`；隐藏 `DropDownCount`）；T-a…T-e。S6-1：`TThirdComboBox` 设 owner-draw 风格 + 行绘制事件（经 access），建它的弹层列表画一行，事件被调用（经 `TyComboOwnerOf` 认出宿主）。变异：C6-1 改回 → 红。S6-2：`TThirdComboBoxEx = class(TTyCustomComboBoxEx)` 发布 `ItemsEx`、`Images`，往 `ItemsEx` 加一项，`Items.Count` 跟着变（`ItemsExChanged` 被调）。变异：C6-2 的 `Update` 那一处改回 → 红。C6-3、C6-4：能观察就写（弹层行用了宿主的 Images / 勾选状态回写宿主），驱动不到写「—」与理由。
- [ ] **Step 4: `CPending` → `CSplit`**、提交。

### Task 7: 组合框 II，属性编辑器第一次挪到 Custom 类

**Files:** `source/tyControls.ColorBox.pas`、`ColorComboBox.pas`、`FontComboBox.pas`、`FontSizeComboBox.pas`、`FilterComboBox.pas`、`ShellComboBox.pas`、`designtime/tyControls.Design.PropEditors.pas`（:765、:770）、`tests/test.designeditors.pas`、测试单元。

| 类 | Custom 父类 | R3 |
|---|---|---|
| TTyColorBox | TTyComboBox | `Style: TTyColorBoxStyle read FPaletteStyle write SetPaletteStyle ...`（同名换类型，整条原样） |
| TTyColorComboBox | TTyColorBox | — |
| TTyFontComboBox / TTyFontSizeComboBox / TTyFilterComboBox / TTyShellComboBox | TTyComboBox | — |

- [ ] **Step 1: 拆**：`FilterComboBox.pas:259` 的 `RegisterClass(TTyFilterComboBox)` 保持（V8）。`TTyFilterComboBox.ConvertFilterToStrings` 是 `class procedure`，随 R1 进 Custom，外部 `TTyFilterComboBox.ConvertFilterToStrings(...)` 照常（V5-6）。`ShellListView: TTyShellListView` 这类 interface 属性类型不改（R7，记附录 D）。
- [ ] **Step 2: 类型判断**：C7-1（ColorBox 弹层取宿主色块几何）、C7-2（ShellComboBox 弹层所有者）放宽；ColorBox.pas 里 `TTyComboBox(Box).Style` 那两处是**注释**，不动。
- [ ] **Step 3: 设计期**（R8）：`PropEditors.pas:765` `TTyFilterComboBox` → `TTyCustomFilterComboBox`；`:770` `TTyShellComboBox` → `TTyCustomShellComboBox`（注释照旧）。`tests/test.designeditors.pas`：`TestEveryRegistrationTargetsARealProperty` 改成 R8 的规则（失败消息里说明两种合法情形）；`RegisterClasses` 块加 `TTyCustomFilterComboBox`、`TTyCustomShellComboBox`。
- [ ] **Step 4: 测试**：`TThirdColorBox`（发布 `Selected`、`Style`；隐藏 `ColorRectWidth`）、`TThirdShellComboBox`（发布 `Directory`、`Items`）；T-a…T-e。S7-1：`TThirdColorBox` 设一个非默认 `ColorRectWidth`（经 access），弹层画一行，色块宽度用的是它的值（像素数宽度）。变异：C7-1 改回 → 红。S7-2：ShellComboBox 弹层能观察就写，否则「—」。
- [ ] **Step 5: `CPending` → `CSplit`**、提交（正文提一句 test.designeditors 的新规则）。

### Task 8: 进度与指示

**Files:** `source/tyControls.ProgressBar.pas`、`Gauge.pas`、`Meter.pas`、`LevelMeter.pas`、`CircularProgress.pas`、`ActivityIndicator.pas`、`ActivityBar.pas`、`GearActivityIndicator.pas`、`Sparkline.pas`、测试单元。9 个类 Custom 父类 = `TTyGraphicControl`，无 R3 带说明符行，无附录 C 条目。

- [ ] **Step 1: 拆** 9 个类。
- [ ] **Step 2: 测试**：`TThirdProgressBar`（发布 `Position`、`Max`；隐藏 `Step`）——T-c 额外断言：`Max = 50, Position = 40` 写出的文本里 `Max` 在 `Position` 前面（第三方自己的发布顺序决定，这条证明文档里「顺序你说了算」的说法）；`TThirdGauge`（发布 `Value`、`Max`）；T-a…T-e。
- [ ] **Step 3: `CPending` → `CSplit`**、提交。

### Task 9: 旋钮与滑块

**Files:** `source/tyControls.Rating.pas`、`Dial.pas`、`GearDial.pas`、`AnalogClock.pas`、`TrackBar.pas`、测试单元。`TTyRating`、`TTyDial`、`TTyGearDial`、`TTyTrackBar` 父类 `TTyCustomControl`、R3 `TabStop default True`；`TTyAnalogClock` 父类 `TTyGraphicControl`。

- [ ] **Step 1: 拆** 5 个类。
- [ ] **Step 2: 测试**：`TThirdTrackBar`（发布 `Position`、`Max`；隐藏 `TickMarks`）；T-a…T-e；T-e 特别验 `TabStop`：`TThirdTrackBar` 新实例 `TabStop = True` 且 `GetPropInfo(TThirdTrackBar,'TabStop')^.Default = 1`（先证明 LCL 祖先的 default 是 0）。变异：M-G3 的同类——把 `TTyCustomTrackBar` 的 `TabStop default True` 挪进 `TTyTrackBar` → 这条红（G3 也红）。
- [ ] **Step 3: `CPending` → `CSplit`**、提交。

### Task 10: 1 期收尾——编译、全量、集中变异、主控编包冒烟、审查、签收

- [ ] **Step 1: 一次编译 + 本期 suite + 全量**（「跑测试的固定套路」）。Expected：守卫与 P1 suite 全 0 / 0；全量 errors / failures 与 Task 0 基线相同、总数 = 基线 + 本期新增。红了集中修：拆错的以快照与 G1–G5 为准；修复提交 `fix(controls): ...`，一个问题一个提交。
- [ ] **Step 2: 结构核对（不看测试）**：对本期 59 个类逐个看源码：最终类只有 published 段（R0）；Custom 类头带着原接口列表；R3 的行在 Custom 的 published 段；没有任何既有类的父类变了（`git diff <Task 0 HEAD>..HEAD -- source | grep -E "^[-+]\s+T\w+ = class\("` 只出现「旧 `TTyXxx = class(P` 被删、新 `TTyCustomXxx = class(P` 与 `TTyXxx = class(TTyCustomXxx)` 被加」这种成对的行）；没有新增的 `RegisterClass`；`python split.py check` 对本期每个改过的文件都 ok。
- [ ] **Step 3: 集中变异**：M-G1、M-G2、M-G3、M-G4、M-G5、M-G6a、M-G6b、M-T（选 Button 家族）、M-D1、M-D2，以及本期 S 条目的变异（S1-1、S1-2、S4-1、S5-1、S6-1、S6-2、S7-1，加上实际写了的其它 S）。逐条记「红 / 补强 / 等价」。
- [ ] **Step 4: 【主控执行】编包、编全部示例、冒烟**

```bash
cd /d/Projects/ty-split && lazbuild -B tycontrols.lpk > /tmp/split-pkg.txt 2>&1; tail -3 /tmp/split-pkg.txt; lazbuild -B tycontrols_dt.lpk > /tmp/split-dt.txt 2>&1; tail -3 /tmp/split-dt.txt; for p in examples/*/*.lpi; do lazbuild -B "$p" > /tmp/split-ex.txt 2>&1 || echo "FAIL $p"; done; python scripts/check-lfm-props.py; powershell -File scripts/smoke-launch-examples.ps1; git status --short
```

Expected：两个包编过；没有 `FAIL`；两个脚本都过（冒烟没有 `#32770`）；`git status` 干净。编包会改机器级包注册（仓库记忆「并行 agent 的三个坑」第三条、「不抢全局注册编 example：私有 --pcp」），主控按当时几棵树的情况决定用不用私有 `--pcp`。
- [ ] **Step 5: 期末审查（主控派两个审查 agent）**：规格核对（本计划拆分规则 R0–R10 + 附录 C 对本期的每一行）与代码质量（`git diff <Task 0 的 HEAD>..HEAD`）。重点：R2 / R3 分拣（N16）、R7 的 `AsPublished` 只用在公开签名处、附录 C 每处都有测试或理由、没有改动任何共享文件与排除单元。审出来的问题修完回到 Step 1。
- [ ] **Step 6: 签收写进本计划末尾，提交**：全量条数（基线 → 签收）、提交区间、本期 suite 条数、变异结果、R7 新增的签名（补进附录 D）、计划外发现。【主控执行】通知「3.0 问题修复」会话：本期已拆的单元清单与移植规矩（N10）。

```bash
cd /d/Projects/ty-split && git add docs/superpowers/plans/2026-10-02-custom-classes.md && git commit -m "docs(controls): custom-class split phase 1 sign-off

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 第 2 期：容器、列表与表格

**本期新建** `tests/test.customclasses.p2.pas`（suite `TTyCustomClassesP2Test`，Task 11 建；`tytests.lpr` 加进去）。模拟子类判据同 1 期（T-a…T-e）。

### Task 11: 面板

**Files:** `source/tyControls.Panel.pas`、`PaintPanel.pas`、`ExPanel.pas`、`GridPanel.pas`、`RelativePanel.pas`、`ScrollBox.pas`、`ScrollPanel.pas`、`ControlBar.pas`、`CoolBar.pas`、测试单元。

| 类 | Custom 父类 |
|---|---|
| TTyPanel | TTyCustomControl |
| TTyPaintPanel / TTyExPanel / TTyGridPanel / TTyRelativePanel / TTyScrollBox / TTyControlBar | TTyPanel |
| TTyScrollPanel | TTyScrollBox |
| TTyCoolBar | TTyControlBar |

无 R3 带说明符行（以 stderr 为准）。`TTyGridCell` 不拆（D5），GridPanel.pas 里只拆 `TTyGridPanel`。`RegisterClass(TTyControlBar)`、`RegisterClass(TTyCoolBar)` 保持。

- [ ] **Step 1: 拆** 9 个类（父先子后）。Panel 的 `VerticalAlignment default taVerticalCenter` 等是本类带类型的声明，走 R2。
- [ ] **Step 2: 类型判断**：C11-1（GridPanel 的格认父 `AParent is TTyGridPanel`）、C11-2（CoolBar 的 bands 集合取所有者）放宽。
- [ ] **Step 3: 测试**：`TThirdPanel`（发布 `Caption`、`Alignment`；隐藏 `WordWrap`）、`TThirdGridPanel = class(TTyCustomGridPanel)`（发布 `ColumnCount`、`RowCount`）；T-a…T-e。S11-1：把一个 `TTyGridCell` 的 Parent 设成 `TThirdGridPanel`，格子被它接管（GridPanel 的布局把它放进对应行列——手调对齐，N26）；变异：C11-1 改回 → 红。S11-2：`TThirdCoolBar` 的 `Bands.Add` 之后宿主重排（能观察就写，否则「—」）。
- [ ] **Step 4: `CPending` → `CSplit`**、提交。

### Task 12: 分组与装饰

**Files:** `source/tyControls.GroupBox.pas`、`RadioGroup.pas`、`CheckGroup.pas`、`ToolGroupPanel.pas`、`Card.pas`、`Empty.pas`、`Bevel.pas`、`Divider.pas`、`Splitter.pas`、`SizeBox.pas`、测试单元。

Custom 父类：`TTyGroupBox`、`TTyCard`、`TTyEmpty`、`TTySplitter` → `TTyCustomControl`；`TTyRadioGroup`、`TTyCheckGroup`、`TTyToolGroupPanel` → `TTyGroupBox`；`TTyBevel`、`TTyDivider`、`TTySizeBox` → `TTyGraphicControl`。无附录 C 放宽条目（C5-2 保持）。RadioGroup / CheckGroup 的错误消息用 `ClassName`（V8），实例类名不变。

- [ ] **Step 1: 拆** 10 个类。
- [ ] **Step 2: 测试**：`TThirdGroupBox`（发布 `Caption`、`Alignment`）、`TThirdRadioGroup = class(TTyCustomRadioGroup)`（发布 `Items`、`ItemIndex`；隐藏 `Columns`）——它自己建的子按钮仍是 `TTyRadioButton`，点第二个后 `ItemIndex = 1`；T-a…T-e。
- [ ] **Step 3: `CPending` → `CSplit`**、提交。

### Task 13: 页签

**Files:** `source/tyControls.PageControl.pas`、`TabSheet.pas`、`TabSet.pas`、`ListGroupPanel.pas`、测试单元。

| 类 | Custom 父类 | R3 |
|---|---|---|
| TTyPageControl | TTyCustomTabStrip（不动） | — |
| TTyTabSheet | TTyCustomControl | `Left / Top / Width / Height / TabOrder / Visible stored False`（6 行） |
| TTyTabSet | TTyCustomTabStrip | — |
| TTyListGroupPanel | TTyCustomControl | `TabStop default True` |

- [ ] **Step 1: 拆**。`TTyPageControl` 的 `ActivePage: TTyTabSheet`、`Pages[]` 等 interface 类型不改（R7，附录 D）。`TTyCustomTabStrip` 的 published 段一个字不动（B1）。
- [ ] **Step 2: 类型判断**：C13-1（TabSheet 认宿主 ×4 处，含强转）、C13-2（PageControl 的移除通知认页）放宽。TabSheet.pas 里放宽后要读写宿主原 published 的属性时用 access 类（N17）。设计期：`TTyPageControlEditor`（`CompEditors.pas:569`）、ListGroupPanel 编辑器（`:405/:512`）、`Dialogs.ListGroupsEditor.pas:67` 保持（D2）。
- [ ] **Step 3: 测试**：`TThirdPageControl = class(TTyCustomPageControl)`（发布 `ActivePageIndex`、`TabPosition`）；T-a…T-e。S13-1：`TTyTabSheet` 的 Parent 设成 `TThirdPageControl`，`Sheet.PageControl` 返回它、它的页数 +1、激活该页后可见。变异：C13-1 第一处改回 → 红。S13-2：`TThirdTabSheet = class(TTyCustomTabSheet)` 放进 `TTyPageControl` 当活动页后释放，`ActivePage` 变 nil（不悬垂）。变异：C13-2 改回 → 红（若释放后读到悬垂指针会 AV，测试判据写成「释放后 `ActivePage = nil`」而不是比较地址，见仓库记忆「AssertSame on a freed pointer」）。另：`TThirdTabSheet` 的 `Left` 设非零后流式写出的文本里**没有** `Left`（R3 的 `stored False` 到了 Custom；变异 M-G6c 同类：把这一行挪到最终类 → 红）。
- [ ] **Step 4: `CPending` → `CSplit`**、提交。

### Task 14: 列表框

**Files:** `source/tyControls.ListBox.pas`、`CheckListBox.pas`、`OfficeListBox.pas`、`AdvancedListBox.pas`、`ValueListEditor.pas`、`ColorListBox.pas`、`FontListBox.pas`、测试单元。`TTyListBox` → `TTyCustomControl`（R3 `TabStop default True`）；其余 6 个 → `TTyListBox`。内部 `TTyComboPopupList`、`TTyCheckComboPopupList`、`TTyGridFilterList`、`TTyValueEdit` 不动（N23）。无附录 C 放宽条目。

- [ ] **Step 1: 拆** 7 个类；`TTyColorListBox` 若有同名换类型的 `Style`，走 R3。
- [ ] **Step 2: 测试**：`TThirdListBox`（发布 `Items`、`ItemIndex`；隐藏 `Sorted`）、`TThirdCheckListBox = class(TTyCustomCheckListBox)`（发布 `Items`、`AllowGrayed`）；T-a…T-e。
- [ ] **Step 3: `CPending` → `CSplit`**、提交。

### Task 15: 复合选择

**Files:** `source/tyControls.Transfer.pas`、`TreeSelect.pas`、`Cascader.pas`、测试单元。三个类 Custom 父类 = `TTyCustomControl`；`TTyTreeSelect`、`TTyCascader` 的 R3 是 `TabStop default True`。内部 `TTyTransferArrowButton`、`TTyTreeSelectTree` 不动。组件编辑器与 `Dialogs.CascaderEditor.pas:77` 保持（D2）。无放宽条目。

- [ ] **Step 1: 拆** 3 个类。
- [ ] **Step 2: 测试**：`TThirdCascader`（发布 `Nodes`、`Separator`）、`TThirdTransfer`（发布 `Items`、`Selected`）；T-a…T-e；T-c 对 `Nodes` 这类集合属性确认往返（若它走 `DefineProperties` 就按 N20 单列）。
- [ ] **Step 3: `CPending` → `CSplit`**、提交。

### Task 16: 树与列表视图

**Files:** `source/tyControls.TreeView.pas`（8233 行）、`ShellTreeView.pas`、`ListView.pas`（4247 行）、`ShellListView.pas`、`HeaderControl.pas`、`designtime/tyControls.Design.PropEditors.pas`（:771、:772）、`tests/test.designeditors.pas`（`RegisterClasses` 块）、测试单元。

| 类 | Custom 父类 | R3 |
|---|---|---|
| TTyTreeView | TTyCustomControl | `TabStop default True` |
| TTyShellTreeView | TTyShellTreeLink（不动） | — |
| TTyListView | TTyCustomControl | `TabStop default True` |
| TTyShellListView | TTyListView | — |
| TTyHeaderControl | TTyCustomControl | `TabStop default True` |

- [ ] **Step 1: 拆**。TreeView.pas 的事件类型约 20 个写死 `Sender: TTyTreeView`（`TreeView.pas:127-244`），HeaderControl 3 个（`:78/82/90`）——按 R7 不改类型，Custom 里加 `AsPublished`，所有触发处 `FOnXxx(AsPublished, ...)`；每个事件类型记进附录 D。`TTyShellTreeView.GetFilesInDir` / `GetBasePath`（class function）随 R1 进 Custom。`TTyShellTreeLink` 不动；`TTyShellListView` 与 `TTyShellTreeView` 互指的 interface 属性类型不改。
- [ ] **Step 2: 类型判断**：C16-1（TreeView 节点集合取所有者 ×2）、C16-2（ListView 项集合取所有者的图片列表）放宽；C16-3（`Dialogs.TreeNodesEditor.pas:73`、`CompEditors.pas:530/874/917`）保持（D2）。
- [ ] **Step 3: 设计期**：`PropEditors.pas:771/772` 的 `TTyShellListView` / `TTyShellTreeView` → Custom 类；test.designeditors 的 `RegisterClasses` 加这两个 Custom 类。
- [ ] **Step 4: 测试**：`TThirdTreeView`（发布 `Items`、`OnGetText`；隐藏 `DefaultNodeHeight`）——T-f：`OnGetText` 被触发时 `Sender` 就是这个第三方实例（类型写的是 `TTyTreeView`，`Sender.ClassType = TThirdTreeView`），这条钉住 `AsPublished` 的行为与限制；`TThirdListView`（发布 `ViewStyle`、`Items`）；T-a…T-e。S16-1：`TThirdTreeView` 的节点集合改动后宿主刷新（节点数随 `Items` 变）；变异：C16-1 改回 → 红。S16-2：`TThirdListView` 设了 `LargeImages`，项取图片列表时拿到它；变异：C16-2 改回 → 红。
- [ ] **Step 5: `CPending` → `CSplit`**、提交。

### Task 17: 表格

**Files:** `source/tyControls.Grid.pas`（16017 行）、测试单元。

| 类 | Custom 父类 |
|---|---|
| TTyDrawGrid | TTyCustomGrid（不动） |
| TTyStringGrid | TTyDrawGrid |

- [ ] **Step 1: 拆**：只动 `TTyDrawGrid`（`Grid.pas:1885` 起）与 `TTyStringGrid`；`TTyCustomGrid` 一个字不改（B1、N15）。`split.py impl` 分两次，**确认没有误改 `TTyCustomGrid.` 的实现头**（`grep -c "^\(procedure\|function\|constructor\|destructor\) TTyCustomGrid\." source/tyControls.Grid.pas` 前后相等）。interface 里 `: TTyStringGrid`（`:3211`）等按 R7。`TTyGridFilterList` 不动。
- [ ] **Step 2: 测试**：`TThirdStringGrid = class(TTyCustomStringGrid)`（发布 `RowCount`、`ColCount`；这两个若不在本层而在 `TTyCustomGrid`，就换成 `TTyStringGrid` 本层新发布的两个，以 `split.py block TTyStringGrid TTyDrawGrid` 的输出为准）、`TThirdDrawGrid`（发布 `OnGetCellText`）；T-a…T-e；T-c 用 `tests/test.grid.streaming.pas` 的往返写法。
- [ ] **Step 3: `CPending` → `CSplit`**、提交。

### Task 18: 2 期收尾

同 Task 10 的 Step 1–6，范围换成本期 40 个类；变异加 M-G6c（`TTyCustomTabSheet` 的 `Left stored False` 删掉 → 红）、M-T（选 Panel 家族）、本期 S 条目（S11-1、S13-1、S13-2、S16-1、S16-2 及实际写了的其它）；签收后同样通知「3.0 问题修复」会话。

---

## 第 3 期：其余

**本期新建** `tests/test.customclasses.p3.pas`（suite `TTyCustomClassesP3Test`，Task 19 建）。

### Task 19: 条

**Files:** `source/tyControls.StatusBar.pas`、`ToolBar.pas`（ToolBar + ToolButton + ToolSeparator）、`ToolBarEx.pas`、`Alert.pas`、`Pagination.pas`、`Steps.pas`、`Breadcrumb.pas`、`ScrollBar.pas`、测试单元。

| 类 | Custom 父类 | R3 |
|---|---|---|
| TTyStatusBar / TTyToolBar / TTyToolSeparator / TTySteps | TTyCustomControl | — |
| TTyToolButton | TTyGlyphButtonBase（不动） | `TabStop default False`；`GlyphLayout stored FGlyphLayoutExplicit nodefault` |
| TTyToolBarEx | TTyToolBar | — |
| TTyAlert / TTyBreadcrumb | TTyGraphicControl | — |
| TTyPagination / TTyScrollBar | TTyCustomControl | `TabStop default True` |

- [ ] **Step 1: 拆**：ToolBar.pas 三个类分三次 `impl`。`TTyDrawPanelEvent(AStatusBar: TTyStatusBar; ...)`（`StatusBar.pas:60`）按 R7。`TTyScrollBar` 被很多控件内嵌（Memo、ListBox、ListView、TreeView、Grid、Terminal 建的是 `TTyScrollBar` 实例），这些内嵌点与 `EmbedsScrollBar(ABar: TTyScrollBar)` 之类签名都不改。
- [ ] **Step 2: 类型判断**：C19-1（ToolButton 认 `Parent is TTyToolBar`）、C19-2（ToolBar / ToolBarEx 认 `is TTyToolButton` ×10）、C19-3（StatusBar 面板集合取所有者）放宽；C19-4（`is TTyGlyphButtonBase`）保持（类没变）。
- [ ] **Step 3: 测试**：`TThirdToolBar`（发布 `ButtonWidth`、`Flat`）、`TThirdToolButton = class(TTyCustomToolButton)`（发布 `Style`、`Down`）、`TThirdStatusBar`（发布 `Panels`、`SimpleText`）、`TThirdScrollBar`（发布 `Position`、`Max`）；T-a…T-e。S19-1：`TThirdToolButton` 放在 `TTyToolBar` 上，按 `ButtonWidth` 拿到宽度下限（`EffectiveToolWidth`），并且 `Style = tbsSeparator` 时不被打上 `ghost`；变异：C19-2 的那两处改回 → 红。S19-2：`TTyToolButton` 放进 `TThirdToolBar`，`GetToolBar` 返回它；变异：C19-1 改回 → 红。S19-3：`TThirdStatusBar` 加一个面板后重画（能观察就写）。
- [ ] **Step 4: `CPending` → `CSplit`**、提交。

### Task 20: Ribbon

**Files:** `source/tyControls.Ribbon.pas`（Ribbon + Page + Group）、`RibbonAppMenu.pas`、`RibbonQuickAccess.pas`、`RibbonGallery.pas`、`RibbonBackstage.pas`、`designtime/tyControls.Design.PropEditors.pas`（:653-663、:757）、`tests/test.designeditors.pas`、测试单元。

| 类 | Custom 父类 | R3 |
|---|---|---|
| TTyRibbon | TTyCustomTabStrip（不动） | `Align default alTop` |
| TTyRibbonPage / TTyRibbonGroup / TTyRibbonQuickAccess | TTyCustomControl | — |
| TTyRibbonAppMenu | TTyMenuButton | — |
| TTyRibbonGallery / TTyRibbonBackstage | TTyCustomControl | `TabStop default True` |

- [ ] **Step 1: 拆**：Ribbon.pas 三个类分三次 `impl`；interface 里 `Pages: TTyRibbonPage`、`Backstage: TTyRibbonBackstage` 等按 R7。
- [ ] **Step 2: 类型判断**：C20-1（RibbonPage 认宿主 ×2）、C20-2（Ribbon 数组 / 摆放 RibbonGroup ×3）、C20-3（Ribbon 移除通知认页）、C20-4（设计期 `Context` 下拉列宿主的页 `PropEditors.pas:653/661`）放宽。
- [ ] **Step 3: 设计期**：`PropEditors.pas:757` `TTyRibbonPage` → `TTyCustomRibbonPage`；test.designeditors 的 `RegisterClasses` 加它。
- [ ] **Step 4: 测试**：`TThirdRibbonPage`（发布 `Caption`、`Context`）、`TThirdRibbonGroup`（发布 `Caption`、`ShowCaption`）；T-a…T-e。S20-1：`TThirdRibbonPage` 放进 `TTyRibbon`，被 `RegisterPage` 收进页列表、改 `Context` 触发宿主重排；变异：C20-1 改回 → 红。S20-2：`TThirdRibbonGroup` 参与组的计数与右对齐；变异：C20-2 改回 → 红。
- [ ] **Step 5: `CPending` → `CSplit`**、提交。

### Task 21: 窗体镶边与菜单栏

**Files:** `source/tyControls.Form.pas`（只拆 `TTyTitleBar`，`Form.pas` 共 2909 行，`TTyForm` 不动）、`Menu.pas`（只拆 `TTyMenuBar`；`TTyPopupMenu` 等非可视不拆）、测试单元。两个类 Custom 父类 = `TTyCustomControl`；`TTyMenuBar` 的 R3 若有 `TabStop default True` 照办（附录 A 显示有）。

- [ ] **Step 1: 拆**：`RegisterClass(TTyTitleBar)`、`RegisterClass(TTyMenuBar)`（`Form.pas:2904/2907`）保持。`TTyTitleBar = class(TTyCustomControl, ITyTitleBarTag)` 的接口列表随 R1 上 Custom 类头。`TTyForm.TitleBar: TTyTitleBar`、`MenuBar: TTyMenuBar` 等属性类型不改（R7，附录 D——这意味着第三方 `TTyCustomTitleBar` 子类挂不到 `TTyForm.TitleBar` 上，文档写清）。
- [ ] **Step 2: 类型判断**：C21-1（`TTyForm.Notification` 里 `AComponent is TTyTitleBar`）放宽——释放一个关联着的标题栏时窗体清引用。
- [ ] **Step 3: 测试**：`TThirdTitleBar`（发布 `Caption`、`ShowMinimize`）、`TThirdMenuBar`（发布 `Menu`、`AutoSizeWidth`）；T-a…T-e（标题栏不关联窗体时也能建、流式）。S21-1：经 R7 的强转把 `TThirdTitleBar` 赋给 `TTyForm.TitleBar`（测试里用 `TTyTitleBar(third)`，注释说明这是附录 D 的限制），释放它后 `Form.TitleBar = nil`；变异：C21-1 改回 → 红。若这条写起来本身就依赖类型假话、主控觉得不值，可改成「—：TitleBar 属性类型写死，第三方本来就挂不上，4.0 一起做」并在附录 C 改结论为保持。
- [ ] **Step 4: `CPending` → `CSplit`**、提交。

### Task 22: 图像与图形

**Files:** `source/tyControls.CharImage.pas`、`Image.pas`、`PreviewBox.pas`、`ImageView.pas`、`Shape.pas`、`StarShape.pas`、`Arrow.pas`、`Chart.pas`、`designtime/tyControls.Design.PropEditors.pas`（:752）、`tests/test.designeditors.pas`、测试单元。`TTyPreviewBox`、`TTyImageView` → `TTyCustomControl`（ImageView 的 R3 `TabStop default True`）；其余 6 个 → `TTyGraphicControl`。`RegisterClass(TTyChart)`（`Chart.pas:1720`）保持。无放宽条目。

- [ ] **Step 1: 拆** 8 个类。
- [ ] **Step 2: 设计期**：`PropEditors.pas:752` `TTyCharImage` → `TTyCustomCharImage`；test.designeditors 的 `RegisterClasses` 加它（`TTyCharImage` 已在）。
- [ ] **Step 3: 测试**：`TThirdCharImage`（发布 `IconFont`、`GlyphName`）、`TThirdShape`（发布 `Shape`、`OnShapeClick`）、`TThirdChart`（发布 `ChartType`、`Series`）；T-a…T-e。
- [ ] **Step 4: `CPending` → `CSplit`**、提交。

### Task 23: 取色器与终端

**Files:** `source/tyControls.ColorGrid.pas`、`LColorPicker.pas`、`HSColorPicker.pas`、`Terminal.pas`（3741 行）、测试单元。四个类 Custom 父类 = `TTyCustomControl`，R3 都是 `TabStop default True`。`TTyTerminalViewComponentEditor`（`CompEditors.pas:980`）保持（D2）。`Dialogs.Color.pas:105` 的 `TTyColorGrid` 内嵌实例不改。

- [ ] **Step 1: 拆** 4 个类；终端的 `ITy…` 接口、IME、`DefineProperties`（若有）随 R1 进 Custom；终端示例（`examples/terminal`）也被 tests 的搜索路径引用（`tests/tytests.lpi` 的 `OtherUnitFiles`），那里的单元不改。
- [ ] **Step 2: 测试**：`TThirdTerminalView`（发布 `Scrollback`、`CursorStyle`）、`TThirdColorGrid`（发布 `Columns`、`Selected`）；T-a…T-e；T-f：终端模拟子类收一段文本后缓冲区里有它（证明核心逻辑在 Custom）。
- [ ] **Step 3: `CPending` → `CSplit`**、提交。

### Task 24（可选，D6 选「拆」才做）: 工具窗口

**Files:** `source/tyControls.ToolWindows.pas`（7841 行）、`ToolWindows.DesignRules.pas`、`ToolWindows.Manager.pas`（只放宽 implementation 里的判断）、`designtime/tyControls.Design.CompEditors.pas`（不改注册，D2）、测试单元。三个类 Custom 父类 = `TTyCustomControl`；R3：Bar 的 `Width stored WidthIsStored`、`Height stored HeightIsStored`；Window 的 `Controller / Left / Top / Width / Height / TabOrder / Visible stored False`；Actions 的 `Controller stored False`、`Left / Top / Width / Height stored IsBoundsStored`。

- [ ] **Step 1: 拆**；`ToolWindows.Manager` / `DesignRules` 的 interface 签名全部按 R7 不改（附录 D 一整段）。
- [ ] **Step 2: 类型判断**：附录 C 的 C24 段（43 处）逐处放宽，`InheritsFrom` 的四处（设计期拖放规则 `:2268/2269/2812-2814/3292`）一并。
- [ ] **Step 3: 测试**：`TThirdToolWindow`（发布 `Caption`、`ImageName`）进 `TTyToolWindowBar` 后被登记、能激活、释放后从栏里移除；`TThirdToolWindowBar` 收 `TTyToolWindow`；设计规则接受第三方窗口作为栏的子控件。各配变异。
- [ ] **Step 4: `CPending` → `CSplit`**、提交。

### Task 25: 文档

**Files:**（按 D8）Create `docs/subclassing.md`、`docs/subclassing.en.md`；Modify `README.md`、`README.en.md`（文档索引各一行）、`docs/controls/README.md`（顶部一句）；（需主控确认）`CONTRIBUTING.md` / `CONTRIBUTING.en.md` 的「几条硬规矩」加一条「新的可视控件一开始就拆成 TTyCustomXxx + TTyXxx（G5 会查）」。

内容（仓库记忆「文档要原生语感」，中英各写一遍，不是互译腔）：
1. 什么时候派生 `TTyCustomXxx`（只想露一部分属性）、什么时候派生 `TTyXxx`（全要、再加）。
2. 一个完整的最小例子：`TMyTagEdit = class(TTyCustomEdit)`，published 段 `property Text; property ReadOnly; property OnChange;`，注册到自己的包；说明 default / stored 会跟过来、顺序由你的 published 段决定（N1 的结论，用户能感知的那一面：先写会钳住别人的属性，比如先 `Max` 后 `Position`）。
3. 限制（D7 的三条，N13、B1 的派生控件、附录 D 的公开签名），各一句话。
4. 设计期：属性编辑器自动跟着用；组件编辑器要自己注册（给出 `RegisterComponentEditor(TMyTree, TTyTreeViewComponentEditor)` 的写法）；`DefineProperties` 存的数据照样存（N20）。
5. 第三方要访问 protected 属性时：在自己的类里提成 public（`public property Text;`）。
- [ ] **Step 1: 写文档**；`python scripts/check-example-po.py .` 不受影响（无 `.po` 变化）。
- [ ] **Step 2: 提交** `docs: deriving from Ty controls through TTyCustomXxx`。

### Task 26: 3 期收尾、撤快照守卫、用户验收清单

- [ ] **Step 1–5**：同 Task 10 的 Step 1–5，范围是本期类；变异加本期 S 条目与 M-T（选 Ribbon 或 ToolBar 家族）。审查另加：**全计划**的结构复核——`CPending` 为空；`git diff a0606352..HEAD --stat -- source designtime` 里没有出现共享文件与排除单元；附录 C 每行都有落实（改 / 保持 / 测试或理由）；附录 D 补全。
- [ ] **Step 6: 撤迁移期守卫（D9）**：删 `TestPublishedSnapshotUnchanged` 与 `tests/fixtures/customclasses/published-snapshot.txt`、删 `CPending` 及 G5 里与它有关的分支；G1–G5 留下。重编、跑守卫 suite 与全量，全绿。单独提交 `test(controls): retire the migration snapshot; the structural guards stay`。
- [ ] **Step 7: 签收**写进本计划末尾（同 Task 10 Step 6，外加三期合计）；【主控执行】通知「3.0 问题修复」会话；把「用户验收项」交给主控。

---

## 用户验收项（三期做完一次性验收，主控交给用户）

1. 装上本分支的两个包，组件面板与之前一样（组数、图标、顺序）。
2. 任挑十个控件（各期至少三个，含 Edit、ComboBox、PageControl、TreeView、StringGrid、ToolBar、Ribbon），放到窗体上，对象查看器里的属性列表与 main 上一致（名字、默认值是否加粗）。
3. 打开 3 个自己现有的项目（或示例 `controls`、`toolbar`、`grid`），编译运行，界面与行为如常；在设计器里随便改一个属性存盘，`.lfm` 的 diff 只有那一行。
4. 照 `docs/subclassing.md` 的例子写一个 `TMyTagEdit` 小包装进 IDE：面板上出现、对象查看器只显示自己发布的那几个（加上 N13 的通用属性）、换主题它跟着变、存盘再打开值都在。
5. 读一遍文档的「限制」一节，确认说法可以直接贴给 issue #8。

---

## 附录 A：清单（173 个注册类）

列说明：**published 声明数 / 其中新发布** 是对类自己的 published 段做静态解析的结果（含事件；「新发布」= 名字不在祖先 published 集合里的），精确值以 Task 0 的快照为准；**已在父类发布、带说明符的重声明** 是 R3 里需要特别留意的行；**库内类型判断** 是 `source/` + `designtime/` 里去掉注释误报后的 `is` / `as` / `InheritsFrom` 处数（逐处见附录 C；不含不带 `is` 的裸强转）；**设计期注册** 是 `designtime/` 里出现这个类名的 `RegisterPropertyEditor` / `RegisterComponentEditor` / `RegisterNoIcon` 行数；后代一列括号里的是未注册的内部子类。

| 类 | 单元 | 当前父类 | 后代 | published 声明数 / 新发布 | 已在父类发布、带说明符的重声明 | 库内类型判断 | 设计期注册 | 处置 |
|---|---|---|---|---|---|---|---|---|
| TTyStyleController | Controller | TTyComponent | — | 7/7 | — | 0 | 7 | 不拆 |
| TTyNativeStyler | NativeStyler | TTyComponent | — | 6/6 | — | 0 | 0 | 不拆 |
| TTyButton | Button | TTyCustomControl | ColorButton, DropDownButton, MenuButton, (GlyphButtonBase), (TransferArrowButton) | 21/14 | TabStop default True | 4 | 0 | T1 |
| TTyGlyphButton | GlyphButtons | TTyGlyphButtonBase | — | 0/0 | — | 0 | 0 | T1 |
| TTyGlyphContainerButton | GlyphButtons | TTyGlyphButtonBase | — | 1/0 | GlyphLayout default glTop | 0 | 0 | T1 |
| TTySpeedButton | GlyphButtons | TTyGlyphButtonBase | — | 3/2 | TabStop default False | 3 | 0 | T1 |
| TTyDropDownButton | DropButtons | TTyButton | — | 3/3 | — | 0 | 0 | T1 |
| TTyMenuButton | DropButtons | TTyButton | RibbonAppMenu | 2/2 | — | 0 | 0 | T1 |
| TTyColorButton | ColorButton | TTyButton | — | 7/6 | Alignment default taLeftJustify | 0 | 0 | T1 |
| TTyButtonGroup | ButtonGroup | TTyCustomControl | — | 10/6 | TabStop default True | 0 | 0 | T1 |
| TTyLabel | TyLabel | TTyGraphicControl | — | 14/8 | — | 0 | 0 | T2 |
| TTyHtmlLabel | HtmlLabel | TTyCustomControl | — | 7/5 | — | 0 | 0 | T2 |
| TTyLinkLabel | LinkLabel | TTyGraphicControl | — | 13/7 | — | 0 | 0 | T2 |
| TTyShadowLabel | ShadowLabel | TTyGraphicControl | — | 14/8 | — | 0 | 0 | T2 |
| TTyGlowLabel | GlowLabel | TTyGraphicControl | — | 13/7 | — | 0 | 0 | T2 |
| TTyTag | Tag | TTyGraphicControl | — | 11/5 | — | 0 | 0 | T2 |
| TTyBadge | Badge | TTyGraphicControl | — | 9/6 | — | 0 | 0 | T2 |
| TTyEdit | Edit | TTyCustomControl | ComboEdit, MaskEdit, NumericEdit, URLEdit, (ValueEdit) | 20/14 | TabStop default True | 0 | 0 | T3 |
| TTyNumericEdit | NumericEdit | TTyEdit | CalcEdit, CurrencyEdit, FloatSpinEdit, TrackEdit | 4/4 | — | 0 | 0 | T3 |
| TTyCurrencyEdit | CurrencyEdit | TTyNumericEdit | CalcCurrencyEdit | 2/2 | — | 0 | 0 | T3 |
| TTyMaskEdit | MaskEdit | TTyEdit | — | 4/3 | Text write SetMaskedText | 0 | 0 | T3 |
| TTyURLEdit | URLEdit | TTyEdit | — | 0/0 | — | 0 | 0 | T3 |
| TTyComboEdit | ComboEdit | TTyEdit | — | 1/1 | — | 0 | 0 | T3 |
| TTyTrackEdit | TrackEdit | TTyNumericEdit | — | 0/0 | — | 0 | 0 | T3 |
| TTyCalcEdit | CalcEdit | TTyNumericEdit | — | 0/0 | — | 0 | 0 | T3 |
| TTyCalcCurrencyEdit | CalcCurrencyEdit | TTyCurrencyEdit | — | 0/0 | — | 0 | 0 | T3 |
| TTyCalculator | Calculator | TTyCustomControl | — | 8/5 | TabStop default True | 0 | 0 | T4 |
| TTyMemo | Memo | TTyCustomControl | — | 50/16 | TabStop default True | 0 | 0 | T4 |
| TTyTerminalView | Terminal | TTyCustomControl | — | 41/40 | TabStop default True | 1 | 1 | T23 |
| TTySpinEdit | SpinEdit | TTyCustomControl | — | 18/14 | TabStop default True | 0 | 0 | T4 |
| TTyFloatSpinEdit | FloatSpinEdit | TTyNumericEdit | — | 3/2 | UseThousands default False | 0 | 0 | T4 |
| TTyUpDown | UpDown | TTyGraphicControl | — | 19/17 | — | 1 | 0 | T4 |
| TTyCheckBox | CheckBox | TTyCustomControl | — | 15/8 | TabStop default True | 0 | 0 | T5 |
| TTyRadioButton | CheckBox | TTyCustomControl | — | 14/7 | TabStop default True | 2 | 0 | T5 |
| TTyToggleSwitch | ToggleSwitch | TTyCustomControl | — | 10/5 | TabStop default True | 0 | 0 | T5 |
| TTyRadioGroup | RadioGroup | TTyGroupBox | — | 10/8 | — | 0 | 0 | T12 |
| TTyCheckGroup | CheckGroup | TTyGroupBox | — | 5/5 | — | 0 | 0 | T12 |
| TTySegmented | Segmented | TTyCustomControl | — | 10/5 | TabStop default True | 0 | 0 | T5 |
| TTyComboBox | ComboBox | TTyCustomControl | AdvancedComboBox, CheckComboBox, ColorBox, ComboBoxEx, FilterComboBox, FontComboBox, FontSizeComboBox, MRUComboBox, OfficeComboBox, ShellComboBox | 24/21 | TabStop default True | 1 | 0 | T6 |
| TTyMRUComboBox | MRUComboBox | TTyComboBox | — | 1/1 | — | 0 | 0 | T6 |
| TTyComboBoxEx | ComboBoxEx | TTyComboBox | — | 2/2 | — | 3 | 0 | T6 |
| TTyOfficeComboBox | OfficeComboBox | TTyComboBox | — | 0/0 | — | 0 | 0 | T6 |
| TTyAdvancedComboBox | AdvancedComboBox | TTyComboBox | — | 1/1 | — | 1 | 0 | T6 |
| TTyCheckComboBox | CheckComboBox | TTyComboBox | — | 4/4 | — | 1 | 0 | T6 |
| TTyListBox | ListBox | TTyCustomControl | AdvancedListBox, CheckListBox, ColorListBox, FontListBox, OfficeListBox, ValueListEditor, (ComboPopupList) | 16/13 | TabStop default True | 0 | 0 | T14 |
| TTyCheckListBox | CheckListBox | TTyListBox | (CheckComboPopupList), (GridFilterList) | 2/2 | — | 3 | 0 | T14 |
| TTyOfficeListBox | OfficeListBox | TTyListBox | — | 0/0 | — | 0 | 0 | T14 |
| TTyAdvancedListBox | AdvancedListBox | TTyListBox | — | 1/1 | — | 0 | 0 | T14 |
| TTyValueListEditor | ValueListEditor | TTyListBox | — | 8/8 | — | 0 | 0 | T14 |
| TTyTransfer | Transfer | TTyCustomControl | — | 13/10 | — | 0 | 0 | T15 |
| TTyTreeSelect | TreeSelect | TTyCustomControl | — | 15/9 | TabStop default True | 1 | 1 | T15 |
| TTyCascader | Cascader | TTyCustomControl | — | 12/8 | TabStop default True | 2 | 1 | T15 |
| TTyColorBox | ColorBox | TTyComboBox | ColorComboBox | 7/6 | Style: TTyColorBoxStyle read FPaletteStyle write SetPaletteStyle | 1 | 0 | T7 |
| TTyColorComboBox | ColorComboBox | TTyColorBox | — | 1/1 | — | 0 | 0 | T7 |
| TTyColorListBox | ColorListBox | TTyListBox | — | 8/8 | — | 0 | 0 | T14 |
| TTyColorGrid | ColorGrid | TTyCustomControl | — | 8/5 | TabStop default True | 0 | 0 | T23 |
| TTyLColorPicker | LColorPicker | TTyCustomControl | — | 9/6 | TabStop default True | 0 | 0 | T23 |
| TTyHSColorPicker | HSColorPicker | TTyCustomControl | — | 9/6 | TabStop default True | 0 | 0 | T23 |
| TTyFontComboBox | FontComboBox | TTyComboBox | — | 0/0 | — | 0 | 0 | T7 |
| TTyFontListBox | FontListBox | TTyListBox | — | 0/0 | — | 0 | 0 | T14 |
| TTyFontSizeComboBox | FontSizeComboBox | TTyComboBox | — | 0/0 | — | 0 | 0 | T7 |
| TTyFilterComboBox | FilterComboBox | TTyComboBox | — | 4/4 | — | 0 | 1 | T7 |
| TTyShellComboBox | ShellComboBox | TTyComboBox | — | 2/2 | — | 1 | 1 | T7 |
| TTyGauge | Gauge | TTyGraphicControl | — | 15/12 | — | 0 | 0 | T8 |
| TTyMeter | Meter | TTyGraphicControl | — | 14/11 | — | 0 | 0 | T8 |
| TTyLevelMeter | LevelMeter | TTyGraphicControl | — | 14/11 | — | 0 | 0 | T8 |
| TTyDial | Dial | TTyCustomControl | — | 15/11 | TabStop default True | 0 | 0 | T9 |
| TTyGearDial | GearDial | TTyCustomControl | — | 16/12 | TabStop default True | 0 | 0 | T9 |
| TTyAnalogClock | AnalogClock | TTyGraphicControl | — | 9/6 | — | 0 | 0 | T9 |
| TTyCircularProgress | CircularProgress | TTyGraphicControl | — | 12/9 | — | 0 | 0 | T8 |
| TTyActivityIndicator | ActivityIndicator | TTyGraphicControl | — | 7/5 | — | 0 | 0 | T8 |
| TTyActivityBar | ActivityBar | TTyGraphicControl | — | 5/3 | — | 0 | 0 | T8 |
| TTyGearActivityIndicator | GearActivityIndicator | TTyGraphicControl | — | 6/4 | — | 0 | 0 | T8 |
| TTySparkline | Sparkline | TTyGraphicControl | — | 10/7 | — | 0 | 0 | T8 |
| TTyRating | Rating | TTyCustomControl | — | 11/7 | TabStop default True | 0 | 0 | T9 |
| TTyTrackBar | TrackBar | TTyCustomControl | — | 18/14 | TabStop default True | 0 | 0 | T9 |
| TTyProgressBar | ProgressBar | TTyGraphicControl | — | 13/11 | — | 0 | 0 | T8 |
| TTyScrollBar | ScrollBar | TTyCustomControl | — | 18/15 | TabStop default True | 0 | 0 | T19 |
| TTyStatusBar | StatusBar | TTyCustomControl | — | 11/9 | — | 1 | 0 | T19 |
| TTyToolBar | ToolBar | TTyCustomControl | ToolBarEx | 17/15 | — | 1 | 0 | T19 |
| TTyToolButton | ToolBar | TTyGlyphButtonBase | — | 10/7 | TabStop default False; GlyphLayout stored FGlyphLayoutExplicit nodefault | 10 | 0 | T19 |
| TTyToolSeparator | ToolBar | TTyCustomControl | — | 3/1 | — | 0 | 0 | T19 |
| TTyToolBarEx | ToolBarEx | TTyToolBar | — | 1/0 | — | 0 | 0 | T19 |
| TTyControlBar | ControlBar | TTyPanel | CoolBar | 4/4 | — | 0 | 0 | T11 |
| TTyCoolBar | CoolBar | TTyControlBar | — | 9/5 | — | 1 | 0 | T11 |
| TTyAlert | Alert | TTyGraphicControl | — | 15/8 | — | 0 | 0 | T19 |
| TTyPagination | Pagination | TTyCustomControl | — | 14/8 | TabStop default True | 0 | 0 | T19 |
| TTySteps | Steps | TTyCustomControl | — | 12/8 | — | 0 | 0 | T19 |
| TTyBreadcrumb | Breadcrumb | TTyGraphicControl | — | 11/4 | — | 0 | 0 | T19 |
| TTyHeaderControl | HeaderControl | TTyCustomControl | — | 6/5 | TabStop default True | 0 | 0 | T16 |
| TTyPanel | Panel | TTyCustomControl | ControlBar, ExPanel, GridPanel, PaintPanel, RelativePanel, ScrollBox | 18/16 | — | 0 | 0 | T11 |
| TTyGroupBox | GroupBox | TTyCustomControl | CheckGroup, RadioGroup, ToolGroupPanel | 17/15 | — | 0 | 0 | T12 |
| TTyBevel | Bevel | TTyGraphicControl | — | 7/4 | — | 0 | 0 | T12 |
| TTyDivider | Divider | TTyGraphicControl | — | 7/5 | — | 0 | 0 | T12 |
| TTySplitter | Splitter | TTyCustomControl | — | 9/7 | — | 0 | 0 | T12 |
| TTyPaintPanel | PaintPanel | TTyPanel | — | 3/1 | — | 0 | 0 | T11 |
| TTySizeBox | SizeBox | TTyGraphicControl | — | 5/2 | — | 0 | 0 | T12 |
| TTyScrollBox | ScrollBox | TTyPanel | ScrollPanel | 6/2 | — | 0 | 0 | T11 |
| TTyScrollPanel | ScrollPanel | TTyScrollBox | — | 3/3 | — | 0 | 0 | T11 |
| TTyExPanel | ExPanel | TTyPanel | — | 5/5 | — | 0 | 0 | T11 |
| TTyGridPanel | GridPanel | TTyPanel | — | 5/5 | — | 1 | 0 | T11 |
| TTyRelativePanel | RelativePanel | TTyPanel | — | 5/1 | — | 0 | 0 | T11 |
| TTyToolGroupPanel | ToolGroupPanel | TTyGroupBox | — | 4/2 | — | 0 | 0 | T12 |
| TTyListGroupPanel | ListGroupPanel | TTyCustomControl | — | 16/13 | TabStop default True | 3 | 1 | T13 |
| TTyPageControl | PageControl | TTyCustomTabStrip | — | 14/14 | — | 5 | 1 | T13 |
| TTyTabSheet | TabSheet | TTyCustomControl | — | 15/7 | Left stored False; Top stored False; Width stored False; Height stored False; TabOrder stored False; Visible stored False | 1 | 0 | T13 |
| TTyTabSet | TabSet | TTyCustomTabStrip | — | 5/5 | — | 0 | 0 | T13 |
| TTyTitleBar | Form | TTyCustomControl | — | 8/8 | — | 1 | 0 | T21 |
| TTyCard | Card | TTyCustomControl | — | 8/6 | — | 0 | 0 | T12 |
| TTyEmpty | Empty | TTyCustomControl | — | 12/6 | — | 0 | 0 | T12 |
| TTyToolWindowBar | ToolWindows | TTyCustomControl | — | 13/11 | Width stored WidthIsStored; Height stored HeightIsStored | 15 | 1 | T24（可选，D6） |
| TTyToolWindowManager | ToolWindows.Manager | TTyCustomToolWindowManager | — | 4/4 | — | 1 | 0 | 不拆 |
| TTyTreeView | TreeView | TTyCustomControl | (ShellTreeLink), (TreeSelectTree) | 66/56 | TabStop default True | 5 | 1 | T16 |
| TTyListView | ListView | TTyCustomControl | ShellListView | 43/40 | TabStop default True | 1 | 0 | T16 |
| TTyShellListView | ShellListView | TTyListView | — | 13/13 | — | 0 | 1 | T16 |
| TTyShellTreeView | ShellTreeView | TTyShellTreeLink | — | 11/11 | — | 0 | 1 | T16 |
| TTyPreviewBox | PreviewBox | TTyCustomControl | — | 8/4 | — | 0 | 0 | T22 |
| TTyImageView | ImageView | TTyCustomControl | — | 19/14 | TabStop default True | 0 | 0 | T22 |
| TTyCalendar | Calendar | TTyCustomControl | — | 21/17 | TabStop default True | 0 | 0 | 排除 |
| TTyDateTimePicker | DateTimePicker | TTyCustomControl | — | 30/24 | TabStop default True | 0 | 0 | 排除 |
| TTyDrawGrid | Grid | TTyCustomGrid | StringGrid | 1/1 | — | 0 | 0 | T17 |
| TTyStringGrid | Grid | TTyDrawGrid | — | 55/55 | — | 0 | 0 | T17 |
| TTyMenuBar | Menu | TTyCustomControl | — | 7/4 | TabStop default True | 0 | 0 | T21 |
| TTyPopupMenu | Menu | TPopupMenu | ImagesMenu | 2/2 | — | 0 | 1 | 不拆 |
| TTyImagesMenu | Menu | TTyPopupMenu | MenuEx | 1/1 | — | 0 | 0 | 不拆 |
| TTyMenuEx | Menu | TTyImagesMenu | — | 2/2 | — | 0 | 0 | 不拆 |
| TTyRibbon | Ribbon | TTyCustomTabStrip | — | 10/9 | Align default alTop | 2 | 0 | T20 |
| TTyRibbonPage | Ribbon | TTyCustomControl | — | 4/2 | — | 3 | 1 | T20 |
| TTyRibbonGroup | Ribbon | TTyCustomControl | — | 7/5 | — | 3 | 0 | T20 |
| TTyRibbonAppMenu | RibbonAppMenu | TTyMenuButton | — | 5/5 | — | 0 | 0 | T20 |
| TTyRibbonQuickAccess | RibbonQuickAccess | TTyCustomControl | — | 6/4 | — | 0 | 0 | T20 |
| TTyRibbonGallery | RibbonGallery | TTyCustomControl | — | 11/8 | TabStop default True | 0 | 0 | T20 |
| TTyRibbonBackstage | RibbonBackstage | TTyCustomControl | — | 16/13 | TabStop default True | 0 | 0 | T20 |
| TTyIconFont | IconFont | TTyComponent | (IconPackFont) | 4/4 | — | 3 | 4 | 不拆 |
| TTyLucideIconFont | Icons.Lucide | TTyIconPackFont | — | 1/1 | — | 0 | 4 | 不拆 |
| TTyLucideImageList | Icons.Lucide | TTyVirtualImageList | — | 2/1 | IconFont stored False | 0 | 3 | 不拆 |
| TTyCharImage | CharImage | TTyGraphicControl | — | 11/6 | — | 0 | 1 | T22 |
| TTyGlyphImageList | GlyphImageList | TTyComponent | — | 4/4 | — | 0 | 0 | 不拆 |
| TTyImage | Image | TTyGraphicControl | — | 22/17 | — | 0 | 0 | T22 |
| TTyImageCollection | ImageCollection | TTyComponent | — | 1/1 | — | 1 | 2 | 不拆 |
| TTyVirtualImageList | ImageCollection | TCustomImageList | LucideImageList | 7/7 | — | 10 | 2 | 不拆 |
| TTyHint | Hint | TTyComponent | — | 2/2 | — | 0 | 0 | 不拆 |
| TTyBalloonHint | BalloonHint | TTyComponent | — | 5/5 | — | 0 | 0 | 不拆 |
| TTyPopover | Popover | TTyComponent | — | 11/11 | — | 1 | 1 | 不拆 |
| TTyShape | Shape | TTyGraphicControl | — | 8/5 | — | 0 | 0 | T22 |
| TTyStarShape | StarShape | TTyGraphicControl | — | 9/6 | — | 0 | 0 | T22 |
| TTyArrow | Arrow | TTyGraphicControl | — | 10/7 | — | 0 | 0 | T22 |
| TTyChart | Chart | TTyGraphicControl | — | 15/11 | — | 0 | 0 | T22 |
| TTyAdvanceChart | AdvanceChart | TTyCustomControl | — | 20/6 | TabStop default False | 1 | 2 | 排除 |
| TTyMessage | Dialogs | TTyComponent | — | 7/7 | — | 1 | 0 | 不拆 |
| TTyInputDialog | Dialogs | TTyComponent | — | 6/6 | — | 1 | 0 | 不拆 |
| TTyPasswordDialog | Dialogs | TTyComponent | — | 7/7 | — | 1 | 0 | 不拆 |
| TTyTextDialog | Dialogs | TTyComponent | — | 6/6 | — | 1 | 0 | 不拆 |
| TTySelectValueDialog | Dialogs | TTyComponent | — | 7/7 | — | 1 | 0 | 不拆 |
| TTySelectPathDialog | Dialogs.SelectPath | TTyComponent | — | 6/6 | — | 1 | 2 | 不拆 |
| TTyColorDialog | Dialogs.Color | TTyComponent | — | 6/6 | — | 1 | 0 | 不拆 |
| TTyFontDialog | Dialogs.Font | TTyComponent | — | 5/5 | — | 1 | 0 | 不拆 |
| TTyFindDialog | Dialogs.Find | TTyComponent | ReplaceDialog | 7/7 | — | 1 | 0 | 不拆 |
| TTyReplaceDialog | Dialogs.Find | TTyFindDialog | — | 2/2 | — | 0 | 0 | 不拆 |
| TTyProgressDialog | Dialogs.Progress | TTyComponent | — | 10/10 | — | 1 | 0 | 不拆 |
| TTyAboutDialog | Dialogs.About | TComponent | — | 10/10 | — | 1 | 0 | 不拆 |
| TTyOpenDialog | Dialogs.FileDialog | TTyCustomFileDialog | OpenPictureDialog, OpenPreviewDialog | 0/0 | — | 0 | 0 | 不拆 |
| TTySaveDialog | Dialogs.FileDialog | TTyCustomFileDialog | SavePictureDialog, SavePreviewDialog | 0/0 | — | 0 | 0 | 不拆 |
| TTyOpenPictureDialog | Dialogs.FileDialog | TTyOpenDialog | — | 0/0 | — | 0 | 0 | 不拆 |
| TTySavePictureDialog | Dialogs.FileDialog | TTySaveDialog | — | 0/0 | — | 0 | 0 | 不拆 |
| TTyOpenPreviewDialog | Dialogs.FileDialog | TTyOpenDialog | — | 0/0 | — | 0 | 0 | 不拆 |
| TTySavePreviewDialog | Dialogs.FileDialog | TTySaveDialog | — | 0/0 | — | 0 | 0 | 不拆 |
| TTyNotification | Notification | TTyComponent | — | 11/11 | — | 0 | 0 | 不拆 |
| TTyIconBrowserDialog | Dialogs.IconBrowser | TTyComponent | — | 6/6 | — | 1 | 0 | 不拆 |
| TTyGridCell | GridPanel | TTyCustomControl | — | 8/5 | — | 1 | 1 | 不拆 |
| TTyToolWindow | ToolWindows | TTyCustomControl | — | 18/10 | Controller stored False; Left stored False; Top stored False; Width stored False; Height stored False; TabOrder stored False; Visible stored False | 22 | 3 | T24（可选，D6） |
| TTyToolWindowActions | ToolWindows | TTyCustomControl | — | 5/0 | Controller stored False; Left stored IsBoundsStored; Top stored IsBoundsStored; Width stored IsBoundsStored; Height stored IsBoundsStored | 6 | 2 | T24（可选，D6） |
| TTyFormSurface | FormSurface | TTyCustomControl | — | 4/3 | — | 1 | 38 | 不拆 |

非可视 35 个（`TTyStyleController`、`TTyNativeStyler`、`TTyPopupMenu`、`TTyImagesMenu`、`TTyMenuEx`、`TTyIconFont`、`TTyLucideIconFont`、`TTyLucideImageList`、`TTyGlyphImageList`、`TTyImageCollection`、`TTyVirtualImageList`、`TTyHint`、`TTyBalloonHint`、`TTyPopover`、`TTyNotification`、对话框 19 个、`TTyToolWindowManager`）的「不拆」理由见 D4；`TTyFormSurface`、`TTyGridCell` 见 D5。**均需主控确认。**

---

## 附录 B：排除的单元与补拆（第 4 期模板，本计划不执行）

| 类 | 单元 | 为什么排除 | 何时补拆 |
|---|---|---|---|
| `TTyAdvanceChart` | `AdvanceChart.pas` | 用户已定 AdvChart 不拆；`feat/advancechart` / `tmp/an1` 有 83–84 个未进 main 的提交改它，published 属性还在变 | `feat/advancechart` 合进 main 之后，用户另行决定 |
| `TTyCalendar` | `Calendar.pas` | `feat/advancechart` 的 `ab4487d8` 把 `TyDateTimeNames` 挪出这个单元 | 同上，合并后 |
| `TTyDateTimePicker` | `DateTimePicker.pas` | 同上 | 同上 |

补拆时照本计划的 Task 0 Step 3 重新核实分支；拍一份只含这 3 个类（及其父类 `TTyCustomControl`）的快照（用 `TY_WRITE_GOLDEN_CLASS`，若快照测试已在 Task 26 删除，就临时恢复它、做完再删）；按「每个类的标准步骤」拆；G1–G5 常驻守卫自动生效（把它们从 `CNotSplit` 挪进 `CSplit`）；`TTyAdvanceChart` 的组件编辑器与 `Option` 属性编辑器照 D2（属性编辑器挪 Custom、组件编辑器留最终类），`Design.AdvChart.Editor.pas:710` 的 `is TTyAdvanceChart` 属设计期，保持。

---

## 附录 C：库内类型判断逐处结论（可视控件；行号以 `a0606352` 为准）

「放宽」= 改成 Custom 类；「保持」= 不改；测试列是 `test.customclasses.pN` 里的条目。注释里提到类名的（如 `Badge.pas:67`、`TyLabel.pas:331`、`ColorBox.pas:179/503`、`FloatSpinEdit.pas:171`、`ScrollBox.pas:720/722`、`ListView.pas:1869/4187`、`GearDial.pas:16` 等）不是判断，不列。

| 编号 | 位置 | 现在 | 语义 | 结论 | 测试 |
|---|---|---|---|---|---|
| C1-1 | `GlyphButtons.pas:962, 987, 1008-1010`（`FindDownButton` 返回类型 `:361` 不改） | `is TTySpeedButton` + 强转 | 同组互斥：父控件上所有速度按钮 | 放宽 | S1-1 |
| C1-2 | `ToolBar.pas:1838`（`ApplyToButton(B: TTyButton)` 若为虚方法则签名不改、调用处强转；否则放宽参数） | `is TTyButton` | 宿主处理所有按钮子控件 | 放宽 | S1-2 |
| C1-3 | `ToolBarEx.pas:236-253, 393-396, 445-446` | `is TTyButton` + 强转 | 同上；溢出弹层包装点击 | 放宽 | S1-3（或「—」） |
| C4-1 | `UpDown.pas:633-634` | `is TTyUpDown` | 同一父控件上的步进器关联互斥 | 放宽 | S4-1 |
| C5-1 | `CheckBox.pas:545-547` | `is TTyRadioButton` | 单选同组互斥 | 放宽 | S5-1 |
| C5-2 | `RadioGroup.pas:527-528` | `is TTyRadioButton` | Sender 只会是组自己建的按钮 | 保持 | — |
| C6-1 | `ComboBox.pas:565-569`（`TyComboOwnerOf`，implementation 私有，调用处 :575/583/590/597） | `Owner is TTyComboBox` | 弹层列表找宿主 | 放宽（返回类型一起放宽） | S6-1 |
| C6-2 | `ComboBoxEx.pas:425, 557, 574-576` | `is TTyComboBoxEx` | 项集合 / 弹层找宿主 | 放宽 | S6-2 |
| C6-3 | `AdvancedComboBox.pas:98-100` | `Owner is TTyAdvancedComboBox` | 弹层找宿主取 Images | 放宽 | S6-3（或「—」） |
| C6-4 | `CheckComboBox.pas:194-199` | `Owner is TTyCheckComboBox` | 弹层找宿主 | 放宽 | S6-4（或「—」） |
| C6-5 | `CheckComboBox.pas:348-349, 554-555, 565-566` | `is TTyCheckListBox` | 弹层是自己建的 `TTyCheckComboPopupList` | 保持 | — |
| C7-1 | `ColorBox.pas:468-470` | `Owner is TTyColorBox` | 弹层找宿主取色块几何 | 放宽 | S7-1 |
| C7-2 | `ShellComboBox.pas:200-202` | `Owner is TTyShellComboBox` | 弹层找宿主 | 放宽 | S7-2（或「—」） |
| C11-1 | `GridPanel.pas:725-726` | `AParent is TTyGridPanel` | 格认宿主 | 放宽 | S11-1 |
| C11-2 | `CoolBar.pas:896` | `GetOwner is TTyCoolBar` | bands 集合找宿主 | 放宽 | S11-2（或「—」） |
| C11-3 | `GridPanel.pas:566`、`Form.pas:2192-2193` | `is TTyGridCell` / `is TTyFormSurface` | 类不拆（D5） | 保持 | — |
| C13-1 | `TabSheet.pas:240, 243, 247-248, 274-275, 284-287` | `is TTyPageControl` + 强转 | 页认宿主 | 放宽（读写宿主原 published 属性用 access 类） | S13-1 |
| C13-2 | `PageControl.pas:382-383` | `AComponent is TTyTabSheet` | 宿主处理页的释放 | 放宽 | S13-2 |
| C13-3 | `TabSheet.pas:256` | `is TTyCustomTabStrip` | 类不变 | 保持 | — |
| C13-4 | `CompEditors.pas:405, 512, 569`、`Dialogs.ListGroupsEditor.pas:67` | `as TTyListGroupPanel` / `as TTyPageControl` | 组件编辑器（D2 留最终类） | 保持 | — |
| C15-1 | `CompEditors.pas:921, 941`、`Dialogs.CascaderEditor.pas:77` | `as TTyTreeSelect` / `as TTyCascader` | 组件编辑器 | 保持 | — |
| C16-1 | `TreeView.pas:1392-1393, 1629-1636` | `is TTyTreeView` | 节点集合找宿主 | 放宽 | S16-1 |
| C16-2 | `ListView.pas:849-854` | `own is TTyListView` | 项集合找宿主的图片列表 | 放宽 | S16-2 |
| C16-3 | `CompEditors.pas:530, 874`、`Dialogs.TreeNodesEditor.pas:73` | `as TTyTreeView` | 组件编辑器 | 保持 | — |
| C19-1 | `ToolBar.pas:924-925` | `Parent is TTyToolBar` | 按钮认宿主 | 放宽 | S19-2 |
| C19-2 | `ToolBar.pas:1581, 1592-1594, 1607, 1651, 1675, 1719, 1759-1765, 1777-1778, 1846`、`ToolBarEx.pas:237-238` | `is TTyToolButton` + 强转 | 宿主处理所有工具按钮 | 放宽 | S19-1 |
| C19-3 | `StatusBar.pas:262` | `GetOwner is TTyStatusBar` | 面板集合找宿主 | 放宽 | S19-3（或「—」） |
| C19-4 | `ToolBar.pas:1746-1747` | `is TTyGlyphButtonBase` | 类不变 | 保持 | — |
| C20-1 | `Ribbon.pas:1100-1101, 1107-1108` | `is TTyRibbon` | 页认宿主 | 放宽 | S20-1 |
| C20-2 | `Ribbon.pas:1187, 1194, 1200-1201` | `is TTyRibbonGroup` | 宿主处理所有组 | 放宽 | S20-2 |
| C20-3 | `Ribbon.pas:1051-1052` | `AComponent is TTyRibbonPage` | 宿主处理页的释放 | 放宽 | S20-1 一并 |
| C20-4 | `PropEditors.pas:653-654, 661-663` | `is TTyRibbonPage` | `Context` 属性编辑器列出同宿主的页 | 放宽 | —（设计期，无头测不到；审查覆盖） |
| C21-1 | `Form.pas:2177-2178` | `AComponent is TTyTitleBar` | 窗体处理标题栏的释放 | 放宽 | S21-1（或「—」，见 Task 21） |
| C23-1 | `CompEditors.pas:980` | `as TTyTerminalView` | 组件编辑器 | 保持 | — |
| C24 | `ToolWindows.pas`：Bar 15 处（:1660, 1941, 2076, 2105, 2110, 2269, 2813, 3444, 3502, 3553, 3610, 7668 等）、Window 21 处（:2268, 2812, 2819, 2824, 2930, 2950, 3292, 3949, 4423, 4819, 6515, 6539, 6553, 6564, 6599, 6670, 6861, 6868, 6966, 7041, 7337）、Actions 6 处（:1699, 2184, 2191, 2204, 2299, 2814）；`ToolWindows.DesignRules.pas:107, 125`；`ToolWindows.Manager.pas:742`；`CompEditors.pas:659, 749` | `is` / `InheritsFrom` | 栏 / 窗口 / 动作区互认、设计期拖放规则 | 只有 D6 选拆才看：除 `CompEditors` 两处（保持）外全部放宽 | Task 24 |

非可视与排除类的判断（`CompEditors.pas:962-973` 的对话框预览、`ImageDraw.pas` 的 `is TTyVirtualImageList` ×9、`PropEditors.pas:336/478/506` 等、`Design.AdvChart.Editor.pas:710`）类都不拆，全部保持。

---

## 附录 D：公开签名里写死最终类的地方（3.x 不改，4.0 待办）

写计划时在各单元 interface 段静态扫到的（执行中按 R7 新增的追加到这里）：
- **事件类型的 Sender**：`TreeView.pas:127-244`（约 20 个 `procedure(Sender: TTyTreeView; ...)`）、`HeaderControl.pas:78/82/90`、`StatusBar.pas:60`（`TTyDrawPanelEvent`）。
- **宿主属性 / 方法里的子项类型**：`PageControl.pas:17-86`（`TTyTabSheet`）、`Ribbon.pas:74-239`（`TTyRibbonPage` / `TTyRibbonBackstage` / `TTyRibbonGroup`）、`RibbonAppMenu.pas:66/107`、`RadioGroup.pas:54/144`（`TTyRadioButton`）、`CheckGroup.pas:38/77/109`（`TTyCheckBox`）、`ToolBar.pas:121/249/347/379/416/445/447`、`Form.pas:279/355/356/510/515/659`（`TTyForm.TitleBar` / `MenuBar`）、`GlyphButtons.pas:361`（`FindDownButton`）、`RibbonQuickAccess.pas:62`（`TTyGlyphButton`）。
- **互指的 shell 控件**：`ShellTreeView.pas:187/390`、`FilterComboBox.pas:37/83`（`TTyShellListView`）。
- **内嵌控件的类型**（多半本来就该是最终类，列出备查）：`ScrollBar.pas:72`、`ScrollBox.pas:132`、`ListBox.pas:118`、`ListView.pas:509/510/569/607`、`Memo.pas:691`、`Terminal.pas:589/632`、`TreeView.pas:832/1064/1065/1097`、`Grid.pas:1505/1560/1561/2289-2308/2991/3005/3211`、`ComboBox.pas` 等弹层的 `TTyListBox`、`Transfer.pas:248-320`、`TreeSelect.pas:108-226`、`Dialogs*.pas` 里对话框自己的控件。
- **集合 / 辅助类的所有者**：`CoolBar.pas:178`（`OwnerBar: TTyCoolBar`）、`ListGroupPanel.pas:190`、`RibbonGallery.pas:56`、`ToolWindows.pas` / `ToolWindows.Manager.pas` / `ToolWindows.DesignRules.pas` 的全部窗口 / 栏参数（D6）。

---

## 签收（执行时填）

### Task 0 基线
（全量条数、红名单、快照类头数与 `x` 个数、合并 main 后的 HEAD）

### 1 期
### 2 期
### 3 期
### 计划外发现
### 遗留
