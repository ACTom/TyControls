# 控件拆出 TTyCustomXxx 父类 实现计划（4.0）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（项目约定，优先于子技能的默认做法）**：分 0–4 共五期，每期**连续写完**——每个任务只改代码 + 写测试并单独提交，任务之间**不编译、不跑测试**（例外：Task 0 的基线编译、生成快照夹具、跑全量，这些产出要进 git；Task 1 改完基类后编译一次、跑快照与全量，因为后面每个任务都站在它上面）；每期最后一个任务（Task 11 / 19 / 26 / 32）**一次编译**、跑本期 suite 和全量、集中修红、集中变异、【主控执行】编包 / 编全部示例 / 冒烟、期末审查、签收。中途不汇报、不问要不要提交。**全部做完用户一次性验收**（验收项在本计划末尾）。
>
> **谁来做**：标 **【主控执行】** 的步骤实现 agent **不做**、直接跳过：问用户、编 `tycontrols.lpk` / `tycontrols_dt.lpk`、编 `examples/`、启动 GUI 冒烟、通知别的会话。实现 agent 只编 `tests/tytests.lpi`；`examples/`、`tools/` 里的 `.pas` 由实现 agent 照本计划改，但不编译它们。
>
> **共享文件**：`source/tyControls.Base.pas` 与 `source/tyControls.Component.pas` **只在 Task 1 改**（D7，用户已同意），而且只改 published / public 段，不动方法；`Painter.pas`、`StyleModel.pas`、`TextMenu.pas`、`DefaultTheme.pas`、`Css.Catalog.pas`、`StrConsts.pas` **不改**（AdvChart 分支在改它们；本计划没有新的用户可见文字，也不动主题）。执行中发现非改不可，停下交主控，主控先问用户。

**Goal:** 每个控件 `TTyXxx` 拆成「`TTyCustomXxx` 放全部实现、属性按 LCL 的可见性放 public / protected」+「`TTyXxx` 只有一段 published」，继承链照 LCL（`TTyCustomGlyphButton` 挂在 `TTyCustomButton` 一系下，而不是挂在 `TTyButton` 下），基类 `TTyCustomControl` / `TTyGraphicControl` 不再发布任何东西（照 LCL 的 `TControl`）。第三方（GitHub issue #8，PascalSCADA）从 `TTyCustomXxx` 派生，只发布自己想露的属性。**用户的 `.lfm` 照常加载，每个控件的属性名、默认值、写出顺序、尺寸、主题 typeKey 一个都不变**；类层级、可见性、少数签名类型的变化进「不兼容变化清单」，随 4.0 发布。

**Architecture:** 三层改动，依次落地：① Task 1 把基类的 published 段拆掉（照 LCL 可见性），每个直接子类在自己的 published 段开头按原 RTTI 顺序补发布这些名字；② 每个家族按「根先、派生后」把 `TTyXxx = class(P)` 改名为 `TTyCustomXxx = class(<P 的 Custom 类>)`，原属性降到 LCL 的可见性，后面接一个只含 `property X;` 的 `TTyXxx = class(TTyCustomXxx)`；③ 库里对「这一族」的类型判断改判 Custom 类（内置派生控件不再是父控件的后代，不改就是 bug）。重新发布的顺序、default、stored、typeKey 由 Task 0 拍下的快照逐项钉死；拆的形状（父类、不多发布、不多字段、发布段只有 `property X;`、派生控件挂在 Custom 链上）由常驻结构守卫钉死。

**Tech Stack:** FPC 3.2.2 / Lazarus 4.4 LCL（最低仍是 Lazarus 3.0）、fpcunit（`tests/tytests.lpi`）、Python 3（辅助脚本，只放 scratchpad 不进仓库）。

**设计依据：** GitHub issue #8；主控 brief（2026-10-02）；用户 2026-10-02 的决定（见「决定」一节，含 4.0 / 3.0 LTS、照 LCL）；GitHub #14（typeKey 链，排在本计划之后）。

**工作树：** `D:/Projects/ty-split`，分支 `feat/custom-classes`，起点 `main` @ `a0606352`。

**版本：** main 的下一版是 **4.0**（GitHub 里程碑已从 3.1 改名 4.0）；**3.0 作为 LTS 维护**，不受本计划影响。

**不在本计划**：`TTyAdvanceChart`、`TTyCalendar`、`TTyDateTimePicker` 的拆分（排除，见附录 B；但 Task 1 要给它们补基类发布段，Q3）；菜单三件与 11 个对话框（LCL 不拆，附录 F）；`TTyForm` / `TTyDialog`（Q5）；typeKey 链（#14，见「后续」）；CHANGELOG（发版时写）；合 `main`。

---

## 总目录

| 期 | 任务 | 内容 | 类数 |
|---|---|---|---|
| 0 | Task 0 | 起点核实、RTTI + typeKey 快照夹具、常驻结构守卫、辅助脚本、基线全量 | — |
| | Task 1 | 基类不再发布（D7）：`Base.pas`、`Component.pas`；全部直接子类补发布段（含排除的 3 个与不拆的类） | 约 110 个类的发布段 |
| 1 输入与显示 | Task 2 | 按钮：Button → DropDownButton、MenuButton、ColorButton、（中间类 GlyphButtonBase）→ GlyphButton、GlyphContainerButton、SpeedButton；ButtonGroup | 8 |
| | Task 3 | 标签：TyLabel、HtmlLabel、LinkLabel、ShadowLabel、GlowLabel、Tag、Badge | 7 |
| | Task 4 | 编辑框 I：Edit → NumericEdit → CurrencyEdit / TrackEdit / CalcEdit → CalcCurrencyEdit；MaskEdit、URLEdit、ComboEdit | 9 |
| | Task 5 | 编辑框 II：Calculator、Memo、SpinEdit、FloatSpinEdit、UpDown | 5 |
| | Task 6 | 选择：CheckBox、RadioButton、ToggleSwitch、Segmented | 4 |
| | Task 7 | 组合框 I：ComboBox → MRUComboBox、ComboBoxEx、OfficeComboBox、AdvancedComboBox、CheckComboBox | 6 |
| | Task 8 | 组合框 II：ColorBox → ColorComboBox；FontComboBox、FontSizeComboBox、FilterComboBox、ShellComboBox；**属性编辑器第一次挪到 Custom 类，改 test.designeditors** | 6 |
| | Task 9 | 进度与指示：ProgressBar、Gauge、Meter、LevelMeter、CircularProgress、ActivityIndicator、ActivityBar、GearActivityIndicator、Sparkline | 9 |
| | Task 10 | 旋钮与滑块：Rating、Dial、GearDial、AnalogClock、TrackBar | 5 |
| | Task 11 | 1 期收尾 | — |
| 2 容器 / 列表 / 表格 | Task 12 | 面板：Panel → PaintPanel、ExPanel、GridPanel、RelativePanel、ScrollBox → ScrollPanel、ControlBar → CoolBar；GridCell、ScrollContent | 11 |
| | Task 13 | 分组与装饰：GroupBox → RadioGroup、CheckGroup、ToolGroupPanel；Card、Empty、Bevel、Divider、Splitter、SizeBox | 10 |
| | Task 14 | 页签：（中间类 CustomTabStrip 降级）PageControl、TabSet、TabSheet、ListGroupPanel；Ribbon 先补发布段 | 4 |
| | Task 15 | 列表框：ListBox → CheckListBox、OfficeListBox、AdvancedListBox、ValueListEditor、ColorListBox、FontListBox；组合框弹层 API 放宽到 `TTyCustomListBox` | 7 |
| | Task 16 | 复合选择：Transfer、TreeSelect、Cascader | 3 |
| | Task 17 | 树与列表视图：TreeView →（中间类 ShellTreeLink）→ ShellTreeView；ListView → ShellListView；HeaderControl；事件类型（D10） | 5 |
| | Task 18 | 表格：（中间类 CustomGrid 降级）DrawGrid → StringGrid | 2 |
| | Task 19 | 2 期收尾 | — |
| 3 其余可视 | Task 20 | 条：StatusBar、ToolBar → ToolBarEx、ToolButton、ToolSeparator、Alert、Pagination、Steps、Breadcrumb、ScrollBar | 10 |
| | Task 21 | Ribbon：Ribbon、RibbonPage、RibbonGroup、RibbonAppMenu、RibbonQuickAccess、RibbonGallery、RibbonBackstage | 7 |
| | Task 22 | 窗体镶边：TitleBar、MenuBar、FormSurface | 3 |
| | Task 23 | 图像与图形：CharImage、Image、PreviewBox、ImageView、Shape、StarShape、Arrow、Chart | 8 |
| | Task 24 | 取色器与终端：ColorGrid、LColorPicker、HSColorPicker、TerminalView | 4 |
| | Task 25 | 工具窗口：ToolWindowBar、ToolWindow、ToolWindowActions（D6 改为必做） | 3 |
| | Task 26 | 3 期收尾 | — |
| 4 非可视与文档 | Task 27 | 控制器：StyleController、NativeStyler（含 D11 的 `Controller` 属性类型） | 2 |
| | Task 28 | 图标字体与图像：IconFont →（中间类 IconPackFont）→ LucideIconFont；VirtualImageList → LucideImageList；GlyphImageList、ImageCollection；`IconFont` 属性类型 | 6 |
| | Task 29 | 提示与通知：Hint、BalloonHint、Popover、Notification | 4 |
| | Task 30 | 对话框：Message、InputDialog、PasswordDialog、TextDialog、SelectValueDialog、ProgressDialog、AboutDialog、IconBrowserDialog | 8 |
| | Task 31 | 文档：`docs/subclassing.md` + 英文版（含「从 3.0 升级」）、README、CONTRIBUTING | — |
| | Task 32 | 4 期收尾、撤迁移期快照守卫、用户验收清单 | — |

规模：组件面板（含 `RegisterNoIcon`）173 个类 + 只 `RegisterClass` 不上面板、却会出现在 `.lfm` 里的 `TTyScrollContent`（V19）。**拆 156**（可视 136 = 原 130 + 工具窗口 3 + `TTyGridCell` + `TTyFormSurface` + `TTyScrollContent`；非可视 20）、**不拆 17**（菜单 3、对话框 11、`TTyForm` / `TTyDialog`、`TTyToolWindowManager`——最后一个是形状豁免，Q4）、**排除 3**（附录 B）。另有 5 个中间类改挂 / 降级（`TTyGlyphButtonBase`、`TTyCustomTabStrip`、`TTyCustomGrid`、`TTyShellTreeLink`、`TTyIconPackFont`），3 个基类降级（`TTyCustomControl`、`TTyGraphicControl`、`TTyComponent`）。**派生控件 55 个**（可视 53、非可视 2）换了父类链，其中 51 个对某个原祖先最终类的 `is` 答案从 True 变 False（附录 C-0）。逐类清单见附录 A。

---

## 决定（用户 / 主控 2026-10-02 定）

> **状态**：D1–D9 由用户 / 主控 2026-10-02 定；三条覆盖性的补充（D3、D4–D6、D7「照 LCL」）同日由用户定；版本定为 4.0、3.0 为 LTS，同日由用户定。用户原话：「不想破坏 LCL 的通用做法」「如果实在是不兼容，大不了改 4.0，不是问题」。**以 LCL 的做法为准，不为保兼容打折扣；但用户的 `.lfm` 照常加载、属性名 / 默认值 / 顺序不变这几条仍然要守**（快照守卫照旧）。D10、D11 与 Q1–Q8 是照这个原则推出来的、规模较大或碰到排除单元的点，**需主控确认**，没回复就按建议做。

**D1 继承链：A（LCL 式）。** 派生控件 `TTyCustomX2 = class(TTyCustomX1)`、`TTyX2 = class(TTyCustomX2)`，例如 `TTyCustomNumericEdit = class(TTyCustomEdit)`、`TTyNumericEdit = class(TTyCustomNumericEdit)`。链上每一层都有 Custom 类；中间类（不在面板上、本来就为家族服务的 `TTyGlyphButtonBase` 等）当作 Custom 层，改挂到上一层的 Custom 类并降级，名字不变（Q1）。代价：55 个派生控件的类层级变了，`TTyGlyphButton is TTyButton`、`TTyNumericEdit is TTyEdit`、`TTyColorBox is TTyComboBox`、`TTyScrollBox is TTyPanel`、`TTyShellTreeView is TTyTreeView`、`TTyLucideImageList is TTyVirtualImageList` 等从 True 变 False——进「不兼容变化清单」第 1 条，库内、测试、示例、工具里的判断逐处处理（「`is` / `as` 翻转」一节、附录 C）。

**D2 设计期注册。** 属性编辑器（`RegisterPropertyEditor`）改注册到 Custom 类（LCL 按 `InheritsFrom` 取最派生的一条，对象查看器只显示 published 的属性，第三方子类发布了就用上、没发布就看不见）；`THiddenPropertyEditor` 那几条留在最终类（它们管的是最终类在对象查看器里的样子）。组件编辑器（`RegisterComponentEditor`）留在最终类（动词会改属性，第三方子类没发布、又不靠 `DefineProperties` 存，就静默丢）；**凡是原来靠继承落到派生控件上的组件编辑器，A 下在注册行里把那些派生最终类显式加上**（实有一处：`[TTyIconFont, TTyVirtualImageList]` 的图标浏览器原来覆盖 `TTyLucideIconFont` / `TTyLucideImageList`，Task 28；`TTyTreeView` 的节点编辑器原来也落到 `TTyShellTreeView`，但在那里没有动词，A 下改由默认编辑器接手、行为不变，只改注释，Task 17）。

**D3 Custom 类里属性的可见性：照 LCL。** 有 LCL 对应类的控件，同名属性照抄它在 LCL Custom 类处的可见性（most-derived 声明，`split.py vis` 查）；同义属性（名字不同、意思相同，如 `TTyGauge.Value` ↔ `TCustomProgressBar.Position`）照对应的那个；Ty 独有的属性照该对应类自身属性的多数（附录 E 的「独有属性」列）；没有对应类的控件按 LCL 主流——**public**（V16：LCL 92 对 `TCustomX`/`TX` 里 73 对多数在 public、10 对多数在 protected）。对照表见附录 E。LCL 有两个异例在 Custom 类里就 published（`TCustomTrackBar`、`TCustomHeaderControl`），我们不照抄 published（那会让 Custom 类失去意义、违反 G2），用 public（Q6）。

**D4–D6 拆不拆：照 LCL。** 对每个候选找 LCL 对应物：LCL 有 `TCustomXxx` + `TXxx` 拆法的照拆（`TCustomImageList`、`TCustomTaskDialog` 等）；LCL 不拆的不拆（`TPopupMenu`、`TColorDialog`、`TFontDialog`、`TFindDialog`、`TOpenDialog` 这一系，各层直接 published）；没有对应物的按可视控件的规则拆（控制器、图标字体、图像集合、提示、通知、工具窗口、`TTyGridCell`、`TTyFormSurface`……）。逐个清单与 LCL 文件:行见附录 F。结果：非可视 35 个里拆 20、不拆 14、`TTyToolWindowManager` 形状豁免（Q4）；工具窗口三件改为必拆（Task 25）；`TTyGridCell`、`TTyFormSurface` 拆（原 D5 的「不拆」理由变成文档里的限制）。

**D7 基类发布的通用属性：照 LCL 拆掉。** `TTyGraphicControl` 发布的 41 个、`TTyCustomControl` 发布的 52 个（完整列表与 LCL 可见性映射见附录 G）全部回到 LCL 的可见性：LCL 的属性就是删掉重声明那一行（`TControl` / `TWinControl` 里本来就是那个可见性；`Hint`、`Cursor` 在 `TControl` 里本来就 published，删掉不改变任何东西）；Ty 自己的 `Version`、`StyleClass`、`StyleOverride`、`Controller` 放 **public**。每个直接子类按**原 RTTI 顺序**在自己的 published 段开头补发布（Task 1，快照逐项比对）。`TTyComponent.Version` 同样降到 public（Q2）。影响：直接继承两个基类的第三方类失去这些 published 属性——「不兼容变化清单」第 2 条。

**D8 文档。** 新建 `docs/subclassing.md` + `docs/subclassing.en.md`（含「从 3.0 升级」一节）；`README.md` / `README.en.md` 文档索引各加一行；`docs/controls/README.md` 顶部一句指过去；`CONTRIBUTING.md` / `.en.md` 的「几条硬规矩」加一条「新控件生来就拆成 `TTyCustomXxx` + `TTyXxx`（G5 会查）」。CHANGELOG 发版时在「变更」写一条并关联 #8（CONTRIBUTING：changelog 发版时写，不在功能分支里改）。

**D9 守卫去留。** 迁移期快照守卫 G6 在 Task 32 撤掉（附录 B 补拆时临时恢复）；结构守卫 G1–G5、G7、G8 常驻；第 0、1 期期末修复加的 G9（生成的第三方模拟子类与最终类逐项相同）也常驻；第 2 期期末修复加的 G10（每个注册类新实例写进窗体文件的文本，冻结成夹具）常驻，接 G6 退役后留下的那块：Custom 类上的 default / stored / 构造值漂移。

**D10 事件类型里的 Sender（需主控确认，建议照 LCL 改）。** LCL 在有 Custom 类的家族里，事件的 Sender 写 Custom 类（`comctrls.pp` 的 `TTVCustomDrawEvent = procedure(Sender: TCustomTreeView; ...)`、`TLVCustomDrawEvent = procedure(Sender: TCustomListView; ...)`、`TCustomSectionNotifyEvent = procedure(HeaderControl: TCustomHeaderControl; ...)`）。A 下这一条对 TreeView 是**被迫的**：`TTyShellTreeView` 不再是 `TTyTreeView`，`TTyCustomTreeView` 里 `FOnGetText(Self, ...)` 只有两条路——Sender 改成 `TTyCustomTreeView`，或者把一个 ShellTreeView 当成 `TTyTreeView` 硬转传出去（对内置控件说类型假话）。建议 27 个事件类型（TreeView 21、HeaderControl 3、StatusBar 1、RibbonGroup 1、ToolButton 1，附录 D）全部改 Custom 类。代价：用户代码里这些事件的处理过程要改签名（`Sender: TTyTreeView` → `TTyCustomTreeView`）；仓库里 tests 约 200 个、examples 约 110 个处理过程跟着改（机械）。`.lfm` 不受影响（流式按方法名找，不查签名）。不改的话：A 下 TreeView 那 21 个仍用 `AsPublished` 硬转，文档写明「ShellTreeView 的事件里 Sender 的类型是假的」。

**D11 引用组件的属性类型（需主控确认，建议照 LCL 改）。** LCL 引用可拆组件的属性写 Custom 类（`Images: TCustomImageList`，`controls.pp`）。A 下 `IconFont: TTyIconFont` 是**被迫的**：`TTyLucideIconFont` 不再是 `TTyIconFont`，不改的话 Lucide 字体根本挂不上任何 `IconFont` 属性。建议：`IconFont`（8 个 published 属性及其字段 / 参数，共 44 处）→ `TTyCustomIconFont`（必改）；`Controller`（11 个属性，含 `Base.pas` 的两个，127 处类型）→ `TTyCustomStyleController`、`ImageCollection` 类属性（7 个）→ `TTyCustomImageCollection`、`TTyVirtualImageList` 类属性（1 个）→ `TTyCustomVirtualImageList`（照 LCL，非被迫）。属性**类型名**变了，快照的 `TypeName` 列随之变——G6 用「允许的类型改名表」比对（Task 0 定义），其余列照旧逐项相同。`.lfm` 不受影响（组件引用按名字流式）。

---

## 需主控确认（没回复就按建议做）

| 编号 | 问题 | 建议 |
|---|---|---|
| Q1 | 中间类 `TTyGlyphButtonBase`、`TTyShellTreeLink`、`TTyIconPackFont` 改挂、`TTyCustomTabStrip`、`TTyCustomGrid` 降级时**保留原名**，还是改名成 `TTyCustomGlyphButtonBase` 之类 | 保留原名。它们已经是「不上面板、为家族服务」的 Custom 层；用户举的 `TTyCustomGlyphButton = class(TTyCustomButton)` 实际是 `TTyCustomGlyphButton = class(TTyGlyphButtonBase)`、`TTyGlyphButtonBase = class(TTyCustomButton)` |
| Q2 | `TTyComponent.Version` 是否随 D7 降到 public（用户的 D7 只点了两个可视基类） | 降。`TComponent` 只发布 Name / Tag；不降的话拆出来的非可视 Custom 类都带着一个 `Version` |
| Q3 | Task 1 要给排除的 `TTyAdvanceChart`、`TTyCalendar`、`TTyDateTimePicker` 补基类发布段（不补，基类一降它们就丢 50 个 published）——碰排除单元 | 补，只在 published 段开头插入生成的块、一行别的都不动，单独一个提交；【主控执行】把提交号告诉 AdvChart 会话，请它在 `feat/advancechart` 上 cherry-pick；合并冲突的解法：取 AdvChart 一侧的 published 段，在段首重新生成基类块（`split.py base`） |
| Q4 | `TTyToolWindowManager` 已是 `TTyCustomToolWindowManager`（0 发布）+ 最终类，但最终类在另一个单元里带着实现（为单元依赖），不满足「最终类无代码」 | 形状豁免：列入 `CNotSplit`（理由写明），G1 照查父类、G4 / G3b 不查它；文档写「派生 `TTyToolWindowManager`」 |
| Q5 | `TTyForm` / `TTyDialog` 拆不拆（LCL 有 `TCustomForm` / `TForm`） | 不拆。它们扮演的是 `TForm` 的角色：用户的窗体从它派生，就像从 `TForm` 派生 |
| Q6 | LCL 的 `TCustomTrackBar`（`comctrls.pp:2733`）、`TCustomHeaderControl`（`:4033`）在 Custom 类里直接 published（LCL 异例） | 不照抄，用 public（D3） |
| Q7 | = D10 | 照 LCL 改 |
| Q8 | = D11 | 照 LCL 改（`IconFont` 是被迫的，另三类是照 LCL） |

> **状态**：主控 2026-10-02 按建议定（用户确认计划）：Q1–Q8 全部照「建议」列执行；Q3 的提交单独做（签收「Task 1 基类」记了提交号），由主控转告 AdvChart 会话摘取；Q8 下 `Controller` 等引用属性要再碰 `Base.pas`（Task 27），用户已同意。

---

## 不兼容变化清单（这些变化进 4.0；3.0 是 LTS，不受影响）

每条：变化、影响面、迁移写法。发版时 CHANGELOG「变更」据此写，`docs/subclassing.md`「从 3.0 升级」据此写。

1. **类层级（D1）。** 55 个派生控件改挂到 Custom 链上（附录 C-0 有全表：控件、3.0 的父类、4.0 的父类）。影响：用户代码里 `X is TTyButton`、`Sender as TTyEdit`、`TTyComboBox(c)` 这类判断，对 `TTyGlyphButton` / `TTyNumericEdit` / `TTyColorBox` 等派生控件答案变了——`is` 静默变 False、`as` 运行期抛 `EInvalidCast`、把派生控件赋给声明为父控件类型的变量编不过。迁移：**想表示「任意 Xxx」就判 `TTyCustomXxx`**；只想要「恰好这个类」的保持。仓库里就有现成的例子：`examples/toolbar/umain.pas:162` 的 `(Sender as TTyButton).Caption` 挂在 13 个 `TTyButton`、4 个 `TTyToolButton`、3 个 `TTyGlyphButton` 上，4.0 下点后两种就抛异常，改成 `Sender as TTyCustomButton`。
2. **基类不再发布（D7）。** `TTyCustomControl` / `TTyGraphicControl` / `TTyComponent` 不再 published 任何东西。影响：**直接**继承它们的第三方类（自己写的控件）在对象查看器里少了 Enabled、Visible、Font、OnClick……约 50 个属性，用户 `.lfm` 里写了这些的读入时报「Unknown property」。迁移：在自己的类里 `published property Enabled; property Visible; ...`（`docs/subclassing.md` 给出 Ty 控件用的那一段，可整段复制）。从任何 `TTyXxx` 最终类派生的不受影响。
3. **中间类不再发布。** `TTyGlyphButtonBase`、`TTyCustomTabStrip`、`TTyCustomGrid`、`TTyIconPackFont` 的 published 段降级；`TTyGlyphButtonBase`、`TTyShellTreeLink`、`TTyIconPackFont` 的父类也变了。影响：直接继承它们的第三方类；`.lfm` 里写 `object X: TTyCustomGrid`（它在 `Grid.pas:16012` 被 `RegisterClasses` 过，面板上没有）。迁移：改从对应的最终类或 Custom 类派生，自己发布需要的属性。
4. **可见性（D3）。** 原 published 属性在 Custom 类里按 LCL 是 public 或 protected。影响：拿 `TTyCustomXxx` 类型的引用（包括第 1 条迁移后的写法）访问一个 protected 属性编不过——最终类类型的引用不受影响。迁移：判完 `is TTyCustomXxx` 后若要动的属性是 protected，就强转成最终类（对内置控件这是真话），或在自己的子类里提成 public。
5. **签名类型。** 被迫的：组合框弹层 API 的 `TTyListBox` → `TTyCustomListBox`（`CreatePopupList` 等，Task 15）、`IconFont` 属性 / 参数 `TTyIconFont` → `TTyCustomIconFont`（Task 28）、`TTyToolBar.ApplyToButton` / `TTyCalcDropdown.Create` 等内部签名（Task 2、4、20）。照 LCL 的：事件 Sender（D10）、`Controller` 等组件引用属性（D11）；**宿主交出「它接受的任意子项」的返回类型**（R7-4，第 0、1 期期末修复改定）：`TTySpeedButton.FindDownButton` 返回 `TTyCustomSpeedButton`（LCL `TCustomSpeedButton.FindDownButton: TCustomSpeedButton`，`buttons.pp:409`；已做），`TTyPageControl.ActivePage` / `Pages[]` → `TTyCustomTabSheet`（Task 14）、`TTyRibbon.ActivePage` / `Pages[]` 等 → Custom 类（Task 21）、`TTyToolBar.Buttons[]` → `TTyCustomToolButton`（Task 20）、`TTyShellTreeView.ShellListView` → `TTyCustomShellListView`（LCL `TCustomShellTreeView.ShellListView: TCustomShellListView`，`shellctrls.pas:139`；第 2 期期末修复；`TTyFilterComboBox.ShellListView` 照 LCL `filectrl.pp:167` 保持 `TTyShellListView`）。影响：覆写了这些虚方法、写了这些事件处理过程的用户代码要改签名；`var B: TTySpeedButton := Sb.FindDownButton`、`var Ts: TTyTabSheet := Pc.ActivePage`、`var L: TTyShellListView := Tree.ShellListView` 这类赋值编不过。迁移：类型换成 Custom 类；确知拿到的是内置控件、又要用它最终类才有的东西时 `as TTySpeedButton`（对内置控件是真话，对第三方子项会抛 `EInvalidCast` 而不是静默读错）。
6. **3.0 → 4.0 摘修复要手工移植。** 不影响用户，影响维护：拆过的单元里实现头都成了 `TTyCustomXxx.Foo`、published 段都换了地方，`3.0-fixes` 的修复 cherry-pick 到 main 必冲突（N10）。
7. **`TTyIconFont.Version: Integer` 改名 `ChangeStamp`（1 期执行中发现，Task 1）。** 3.0 的 `TTyIconFont` 在 public 段声明了一个 `Version: Integer` 变更计数，遮住 `TTyComponent` 发布的库版本 `Version: string`。Q2 让基类不再发布之后，`TTyIconFont` 得自己发布字符串 `Version`，而同一个类里不能既声明又重新发布同名属性（FPC：Duplicate identifier）。照 `TTyImageCollection` 早有的先例改名 `ChangeStamp`。影响：读 `IconFont.Version` 当计数器的代码（库内 `ImageCollection.pas` 两处、`test.iconfont` 已改）。迁移：改读 `ChangeStamp`。文档里没写过这个计数器。
8. **`Checked` 等在 Custom 类里是 protected（D3 的直接结果，举例写进文档）。** `TTyCustomCheckBox` / `TTyCustomRadioButton` / `TTyCustomToggleSwitch` 的 `Checked` 照 LCL（`TButtonControl.Checked` protected）放 protected；组合框的 `OnChange` / `OnDrawItem` / `ItemHeight` 等照 `TCustomComboBox` protected；标签、`TTyCustomUpDown`、`TTyCustomMaskEdit` 的独有属性 protected。经最终类引用访问不受影响；经 Custom 引用访问要强转或在子类里提成 public（第 4 条）。

9. **经基类（或 Custom 类）类型的引用访问 LCL 里本是 protected 的那些成员，编不过（D7 的直接结果；第 0、1 期期末修复补列）。** 3.0 的两个基类把 `TControl` 的一批 protected 成员提成了 published，所以 `TTyCustomControl(C).OnMouseDown := ...`、`TTyGraphicControl(G).DragMode := dmAutomatic` 这类写法能编过；4.0 基类不再发布，它们回到 LCL 的可见性，经 `TTyCustomControl` / `TTyGraphicControl` / 任何 `TTyCustomXxx` 类型的引用访问就编不过（经最终类类型的引用照常，最终类都发布了它们）。逐个（`C:/lazarus/lcl/controls.pp` 为准，脚本按类的可见性段读出）：`TControl` protected 的 21 个——`OnDblClick`、`OnMouseDown`、`OnMouseUp`、`OnMouseMove`、`OnMouseEnter`、`OnMouseLeave`、`OnMouseWheel`、`OnMouseWheelUp`、`OnMouseWheelDown`、`OnMouseWheelHorz`、`OnMouseWheelLeft`、`OnMouseWheelRight`、`OnContextPopup`、`DragMode`、`DragKind`、`DragCursor`、`OnDragOver`、`OnDragDrop`、`OnStartDrag`、`OnEndDrag`、`ParentShowHint`；窗口化基类另加 `OnEditingDone`（`TControl` protected），图形基类另加 `OnPaint`（`TGraphicControl` protected；`TCustomControl.OnPaint` 是 public，窗口化的不受影响）——各 22 个。**不在此列**：`OnKeyDown` / `OnKeyUp` / `OnKeyPress` / `OnUTF8KeyPress` / `OnEnter` / `OnExit` / `TabOrder` / `TabStop` / `BorderWidth` / `ChildSizing`（`TWinControl` public）与 `Enabled` / `Visible` / `Font` / `OnClick` / `PopupMenu` 等 13 个（`TControl` public），经任何引用都照常。迁移：对象就是某个内置控件时，强转成那个最终类（`TTyButton(C).OnMouseDown := ...`，对内置控件是真话）；要对「任意 Ty 控件」统一挂事件，用 LCL 的惯用写法——单元里声明 `type TControlAccess = class(TControl);`，`TControlAccess(C).OnMouseDown := ...`（对一切 `TControl` 都成立）；或者按 RTTI `SetMethodProp(C, 'OnMouseDown', TMethod(Handler))`（每个最终类都发布了这些名字）。第三方 Custom 子类要让外面直接访问，在自己的类里 `public property OnMouseDown;` 提上去。

**仍然守的（与版本号无关，为了用户的窗体文件不坏）**：每个已注册类（及 `TTyScrollContent`）的 published 属性名、类型（`CSnapshotTypeRenames` 列出的除外：D11 的四个按类型整体改名，R7-4 的按类 + 属性逐条放行）、default、stored、index、读写、**写出顺序**；新实例的 `IsStoredProp` 与默认值比较；`GetStyleTypeKey` 与默认 `StyleClass`、子部件 typeKey；新实例的默认尺寸。全部由快照守卫 G6 逐项比对；G6 在 Task 32 退役后，新实例写进窗体文件的文本由 G10（冻结夹具）、说明符在哪一层由 G9 / G3b 继续守。组件面板（组、顺序、图标）不动，由 `test.paletteicons` 与【主控】编包核对。

---

## `is` / `as` 翻转（D1 = A）

**为什么必须处理**：上一版计划建议的「只加类、不改祖先」（B1）下库内判断「不改也不会坏」，A 下不是——内置派生控件不再是父控件的后代，凡是语义为「这一族都算」的判断，不改就是现成的 bug（例：`ToolBar.pas:1838` 的 `kids[i] is TTyButton` 决定扁平工具栏上的按钮打不打 `ghost` 样式类，A 下 `TTyGlyphButton` / `TTySpeedButton` / `TTyToolButton` 全部掉出去）。

**规则**：
- 判断对象是**类型判断与强转**：`is`、`as`、`InheritsFrom`、`ClassType =`、硬转 `TTyXxx(x)`、以及隐式向上转型（把派生控件赋给 / 传给声明为父控件类型的变量、参数、返回值——A 下这些**编不过**）。
- 语义是「这一族都算」（父子关系、所有者、同组互斥、宿主处理子控件、按类找控件）→ 改判 `TTyCustomXxx`；语义是「恰好这个类」（库自己建的那个具体对象、只有这一个类会走到）→ 保持。
- 改判 Custom 后要读写的属性若在 Custom 类里是 protected：库内用单元内 access 类（N17）；测试 / 示例 / 工具里若对象必然是内置最终类，强转成那个最终类是真话，可以用。
- **硬转**：A 下 `TTyButton(aGlyphButton)` 仍然「能用」（最终类不加字段、不加方法，内存布局相同），但它对内置控件说了类型假话，一律按上面的规则改，不留。
- 每处「必改」配一条测试，**判据写「把这一处改回判最终类，在哪个测试下必须红」**；变异在期末集中做。驱动不到的写「—」并给理由（一般是与另一处同一个判断、已被那条测试覆盖，或示例代码无测试——此时列进【主控】冒烟或用户验收）。

**范围与结论**：附录 C。分四段：C-0 父类变化全表；C-1「A 下必改」（内置派生控件的答案翻转，库内 + 测试 + 示例 + 工具，逐处）；C-2「为第三方放宽」（答案对内置控件不变，上一版计划 B1 就有的放宽项）；C-3「保持」；C-4「编译期必改」（隐式向上转型与签名）。执行中编译器报 `Incompatible types: got "TTyCustomXxx" expected "TTyXxx"` 或 `got "TTyGlyphButton" expected "TTyButton"` 的每一处，都按规则判断并补进附录 C（签收里列出）。

**守卫**：G7（派生控件挂在 Custom 链上、链上没有任何注册最终类）+ G1（每个 `TTyXxx` 的直接父类是 `TTyCustomXxx`），见 Task 0。

---

## 核实记录（写计划时读源码与实验，2026-10-02，`main` @ `a0606352`）

**V1. 组件面板清单**：`designtime/tyControls.Design.pas:132-224` 的 `RegisterComponents` 共 15 组 + `RegisterNoIcon` 3 处（`TTyGridCell`；`TTyToolWindow`、`TTyToolWindowActions`；`TTyFormSurface`），合计 173 个类名（`TTyOpenDialog` 是 `TTyCustomFileDialog` 的空子类，单行声明 `Dialogs.FileDialog.pas:212`）。`RegisterDesignerBaseClass` 另有 `TTyForm`、`TTyDialog`。`tests/test.designregistry.pas` 的 `CollectRegisteredClassNames` 在运行时解析同一文件，`tests/test.version.pas:473-499` 把这些名字全部 `RegisterClasses`。**另**：`TTyScrollContent` 不在面板上，但 `ScrollContent.pas:168` `RegisterClass` 了它，`examples/containers/umain.lfm:270/814` 里就有 `object SbView: TTyScrollContent`——它也要进快照、也要拆（V19）。

**V2. 现有「Custom」与「Base」类**：
| 类 | 位置 | 自己发布 | 子类 | 本计划里 |
|---|---|---|---|---|
| `TTyCustomControl` | `Base.pas:335` | 52（`Base.pas:418-515`） | 所有窗口化控件 | Task 1 降级（D7） |
| `TTyGraphicControl` | `Base.pas:79` | 41（`Base.pas:254-333`） | 所有图形控件 | Task 1 降级（D7） |
| `TTyComponent` | `Component.pas:29` | 1（`Version`） | 非可视组件 | Task 1 降级（Q2） |
| `TTyGlyphButtonBase` | `GlyphButtons.pas:100`，`class(TTyButton)` | 11 | GlyphButton、GlyphContainerButton、SpeedButton、ToolButton | Task 2 改挂到 `TTyCustomButton` 并降级 |
| `TTyCustomTabStrip` | `TabStrip.pas:62` | 约 16（`TabStrip.pas:524-572`） | PageControl、TabSet、Ribbon | Task 14 降级 |
| `TTyCustomGrid` | `Grid.pas:777` | 约 68（`Grid.pas:1644-1877`） | DrawGrid → StringGrid | Task 18 降级 |
| `TTyShellTreeLink` | `ShellListView.pas:62`，`class(TTyTreeView)` | 0 | ShellTreeView | Task 17 改挂到 `TTyCustomTreeView` |
| `TTyIconPackFont` | `IconFont.pas:205`，`class(TTyIconFont)` | （Task 0 快照为准） | LucideIconFont | Task 28 改挂到 `TTyCustomIconFont` 并降级 |
| `TTyCustomFileDialog` | `Dialogs.FileDialog.pas:170`，`class(TTyComponent)` | 12 | 打开 / 保存 / 图片 / 预览对话框 | 不拆（LCL `TFileDialog` 各层 published）；Task 1 补 `Version` |
| `TTyCustomToolWindowManager` | `ToolWindows.pas:1403`，`class(TTyComponent)` | 0 | `TTyToolWindowManager`（`ToolWindows.Manager.pas:45`，带实现） | 形状豁免（Q4）；Task 1 给最终类补 `Version` |

**V3. LCL 祖先已经 published 的**（`lcl/controls.pp`）：`TComponent`：Name、Tag。`TControl` 的 published 段（`controls.pp:1836-1850`）：AnchorSideLeft / Top / Right / Bottom、Cursor、Left、Height、Hint、Top、Width、HelpType、HelpKeyword、HelpContext（13 个）。`TWinControl`、`TCustomControl`、`TGraphicControl` **没有** published 段。D7 之后，Ty 的每个 Custom 类、每个基类都只带这 15 个（非可视只带 Name / Tag）。

**V4. LCL 里常被 Ty 控件重新发布的属性原本的可见性**：见附录 G（逐个列出了 `controls.pp` 的行号）。

**V5. FPC 3.2.2 的 RTTI 与重声明（实验，scratchpad `rtti/probe.lpr`、`rtti2/p2.lpr`、`rtti2/p3.lpr`）**：
1. `TWriter.WriteProperties`（`rtl/objpas/classes/writer.inc:841`）用 `GetPropList`，后者调 `GetPropInfos`（`rtl/objpas/typinfo.pp:1443`），**不排序**：数组下标就是 `NameIndex`。`.lfm` 的写出顺序 = `NameIndex` 顺序；读入按文件顺序调 setter。
2. `NameIndex` 的分配：从最老的祖先往下数，**一个名字第一次在 published 段出现时**拿下一个号；派生类里再声明（重新发布、改 default、换类型）沿用那个号。
3. 不带说明符的 `property X;` 重声明继承 default、nodefault、stored（常量 / 字段 / 方法）、index、读写方法；跨单元也一样。
4. 在派生类里把已 published 的属性重声明到 protected，藏不掉（Pascal 不能取消 publish）。
5. 把 public 属性在派生类重声明到 protected，不影响外部访问（编译器继续往祖先找）——误降级编得过，但误导读者。
6. 嵌套类型、`class var`、`class function` 放在 Custom 类里，经最终类访问照常。
7. **选项 A + D7 的顺序实验（2026-10-02 补，scratchpad `split/order/`：`ordbase.pas`、`ordx2.pas`、`ordprobe.lpr`，结果 `result.txt`）**：`TCtl` 扮 `TControl`（published Left / Hint，public Enabled / TabStop / Visible，protected TabOrd）；3.0 形状 `TBaseOrig`（发布 Version、Enabled、Visible、Hint、TabOrd、TabStop、StyleClass）→ `TX1Orig`（发布 Caption、`TabStop default True`、Max、Position、Kind、`Foo stored IsFooStored`）→ `TX2Orig`（发布 Extra、`Max default 50`、`Left stored False`、`Visible stored False`）；4.0 形状 `TBaseNew`（Version、StyleClass 在 public，什么都不发布）→ `TCustomX1`（`public property TabStop default True;`，其余 protected）→ `TX1`（只有 `property X;`）、`TCustomX2 = class(TCustomX1)`（另一个单元；`protected property Max default 50;`、`public property Visible stored False;`、`published property Left stored False;`）→ `TX2`（把整条链的名字按 `TX2Orig` 的 RTTI 顺序写一遍）。结果：
   - `TX2Orig` 与 `TX2`、`TX1Orig` 与 `TX1` 的 `GetPropList` **逐项相同**（16 / 15 行：位置、名字、类型、default、stored 种类、index、读写）。原来由基类 / `TX1` 发布、现在改由 `TX2` 重新发布的属性，在 RTTI 里的位置**不变**：祖先 `TCtl` 已 published 的（Left、Hint）保持原位（下标 2、3）；其余按 `TX2` 发布段的声明顺序拿号，而原 RTTI 顺序本来就是「基类层的名字在前、`TX1` 层的在中、`TX2` 自己的在后」，只要按原顺序写，就一致。
   - 把 `Position` 写在 `Max` 前面的 `TX2Shuffled`：RTTI 下标 11 / 12 对调，流出的文本里 `Position = 55` 跑到 `Max = 60` 前面——**顺序就是发布段的书写顺序**，所以发布段只能从快照生成。
   - 设了同样的非默认值后，`TX2Orig` 与 `TX2` 流出的文本（类名归一后）**完全相同**；`Left = 12`、`Visible = False` 因 stored False 都没写出——`TCustomX2` 里 public 段的 `Visible stored False` 与 published 段的 `Left stored False` 都传到了最终类。
   - 改 default 的重声明放在 Custom 类的 **public**（`TabStop default True`，LCL 里是 public）或 **protected**（`Max default 50`）段都行，最终类 `property X;` 拿到的是改过的 default（TX1 的 TabStop default = 1、TX2 的 Max default = 50）。
   - `TCustomX2` 的 published 集合 = `TCtl` 的（Name、Tag、Left、Hint），`Left` 一行带着 stored False——LCL 根已 published 的名字，改说明符的重声明只能留在 Custom 类的 published 段（R3），G2 允许它。
   - `TX2.InheritsFrom(TX1) = False`、`TX2.InheritsFrom(TCustomX1) = True`、`TX2Orig.InheritsFrom(TX1Orig) = True`——A 的 `is` 翻转被实验确认。
8. 结论写进规则：发布段从快照生成（R5）；改说明符的重声明放 Custom 类（R2 / R3）；快照逐项比对（G6）。

**V6. 设计期注册的匹配方式**：属性编辑器按 `Obj.InheritsFrom(PersistentClass)` 取最派生的一条（`components/ideintf/propedits.pp:2824-2870`）；组件编辑器 `GetComponentEditor`（`components/ideintf/componenteditors.pas:608-631`）用 `Component is P^.ComponentClass` 取最派生的一条。注册清单：`designtime/tyControls.Design.PropEditors.pas:678-848`、`designtime/tyControls.Design.CompEditors.pas:1143-1181`。A 下靠继承落到派生控件上的：组件编辑器 `TTyTreeView`（→ ShellTreeView，无动词，`CompEditors.pas:1153-1157` 注释写着）、`[TTyIconFont, TTyVirtualImageList]`（→ 两个 Lucide 类，`:1161`）；属性编辑器 `TTyGlyphButtonBase.GlyphName`（中间类本身仍是 4 个按钮的祖先，不受影响）、`TTyIconFont.FontFamily / FontFile`（Lucide 类另有 Hidden 编辑器盖住）。

**V7. `tests/test.designeditors.pas:157` `TestEveryRegistrationTargetsARealProperty`** 要求「注册里写的类本身 publish 了这个属性」。D2 + D7 之后基类、中间类、Custom 类都不发布 → 规则改成「注册类本身 publish 了它，**或**有某个注册最终类 `InheritsFrom` 注册类且 publish 了它」（R8），Task 8 改。

**V8. 类名查表**：样式 typeKey 全是字面量（`GetStyleTypeKey` 109 处实现，没有 `is` / `ClassType` / `ClassName` 分支；子部件 key：`TTyListBox.GetItemStyleTypeKey`（`ListBox.pas:131`，ValueListEditor 覆写）、`TTyPopover.StyleTypeKey / TitleStyleTypeKey`（`Popover.pas:299-300`，class function）、`TTyNotification.StyleTypeKey / CloseStyleTypeKey`（`Notification.pas:305-306`）、`TTyTreeSelect.StyleTypeKey`（`TreeSelect.pas:129`））。`ClassName` 的用法只有错误消息（`CheckGroup.pas:438`、`RadioGroup.pas:379/567`、`TreeView.pas:3493`、`Form.pas:2115`）和设计期起名（`CompEditors.pas:634/736/850`）——**A 下这些仍是实例的最终类名，消息与起名一字不变；没有任何主题 / 样式路径依赖类名**（V22）。`RegisterClass` 写在最终类上，保持；`Grid.pas:16012` 的 `RegisterClasses([TTyCustomGrid, ...])` 保持（无害，不兼容清单第 3 条提一句）。没有 `FindClass` / `GetClass` / `ClassNameIs` 查控件类、没有 `class of TTyXxx`、没有 class helper。`.po` 里没有控件类名做键。组件面板图标按最终类名，不变。

**V9. 命名冲突**：全仓库现有的 `TTyCustom*` 只有 `TTyCustomControl`、`TTyCustomGrid`、`TTyCustomTabStrip`、`TTyCustomToolWindowManager`、`TTyCustomFileDialog`。要新建的 156 个名字（`TTyCustom` + 去掉 `TTy` 的类名）与它们不撞（没有叫 `TTyControl`、`TTyGrid`、`TTyTabStrip`、`TTyToolWindowManager` 要拆成 `TTyCustomToolWindowManager` 的——它是 Q4 豁免）。`TTyCustomStyleController`、`TTyCustomIconFont`、`TTyCustomVirtualImageList` 等非可视新名字执行前 grep 一遍。

**V10. 排除清单的核实**：
| 来源 | 未进 main 的提交 | 碰到的控件单元 | 结论 |
|---|---|---|---|
| `feat/advancechart`（ty-advchart） | 107 | `AdvanceChart.pas`（83 次，published 段 main 20 行 / 分支 27 行）、`Calendar.pas`（分支删 111 行）、`DateTimePicker.pas`（+5 行）；`Base.pas`（V21）、`Painter.pas`、`FontUnits.pas`、`DefaultTheme.pas`、`Css.Catalog.pas`、`StrConsts.pas`；`tests/tytests.lpr` | 3 个类不拆；Task 1 只在它们的 published 段首插基类块（Q3） |
| `tmp/an1`（ty-an1） | 108 | 同上 | 同上 |
| `3.0-fixes` | 6 | `HtmlLabel.pas`、`Types.pas`、`Painter.pas`、`designtime/…NewItems.pas` | 3.0-fixes 先合进 main 再开工；Task 0 复核为 0 |
| `feat/theme-builder`（ty-3.1） | 163 | 不碰控件单元 | `tests/tytests.lpr`、`tests/tytests.lpi` 会冲突（手工合）；合完 grep `tools/themebuilder/` 里的 `is TTy` / `as TTy`，按附录 C 的规则判断 |

**V11. 文件格式**：`source/`、`designtime/`、`tests/` 的 `.pas` 全部 CRLF、无混合换行；只有 `tests/test.treeview.pas` 带 UTF-8 BOM。补丁工具并进 `split.py`。

**V12. 内部辅助子类**（未注册，库里自己建）：`TTyComboPopupList(TTyListBox)` 及其 7 个子类、`TTyCheckComboPopupList(TTyCheckListBox)`、`TTyGridFilterList(TTyCheckListBox)`、`TTyTransferArrowButton(TTyButton)`、`TTyTreeSelectTree(TTyTreeView)`、`TTyValueEdit(TTyEdit)`。它们照旧从最终类派生（库自己建、第三方碰不到，N23）。**A 的连带后果**：`TTyCheckListBox` 在 Task 15 改挂到 `TTyCustomListBox` 后，`TTyCheckComboPopupList` / `TTyGridFilterList` 不再是 `TTyListBox`——而组合框弹层 API 全写的 `TTyListBox`（`ComboBox.pas:144/161/290/349/373/396/513-520`、10 个 `CreatePopupList` 覆写、`CheckComboBox.pas:339`），Task 15 必须把这套签名放宽到 `TTyCustomListBox`（`ComboBox.pas:359` 的注释早就说过「CheckCombo 的弹层从 TTyCheckListBox 来，单继承」）。

**V13. 没有控件在 published 段里放方法或字段**；没有控件在第一个可见性关键字之前写属性。

**V14. `scripts/check-lfm-props.py` 只按属性名查**，抓不到「漏了重新发布」（那个名字还在 Custom 类里）。能抓到的是快照守卫和【主控】的示例冒烟（`scripts/smoke-launch-examples.ps1`，`.lfm` 读不进来会弹 `#32770` 错误框）。

**V15. LCL 对应类的位置与形状**（`C:/lazarus/lcl`，scratchpad `split/pasclasses.py` 解析；附录 E / F 用）：例如 `TCustomButton` `stdctrls.pp:1214`（public 8 / protected 1）、`TCustomEdit` `stdctrls.pp:764`（23 / 3）、`TCustomLabel` `stdctrls.pp:1556`（2 / 7）、`TCustomComboBox` `stdctrls.pp:289`（22 / 12）、`TCustomListBox` `stdctrls.pp:537`（51 / 0）、`TCustomTreeView` `comctrls.pp:3382`（32 / 46）、`TCustomListView` `comctrls.pp:1395`（27 / 46）、`TCustomGrid` `grids.pas:744`（6 / 100）、`TCustomDrawGrid` `grids.pas:1397`（112 / 2）、`TCustomImageList` `imglist.pp:266`（25 / 0）、`TCustomTaskDialog` `dialogs.pp:723`（41 / 0）。LCL **不**拆的：`TPopupMenu` `menus.pp:465`、`TMenu` `menus.pp:362`（基类自己就 published 9 个）、`TCommonDialog` `dialogs.pp:87`（published 5）、`TFileDialog` `:141`、`TOpenDialog` `:239`、`TColorDialog` `:305`、`TFontDialog` `:416`、`TFindDialog` `:454`、`TReplaceDialog` `:515`、`TSelectDirectoryDialog` `:281`、`TOpenPictureDialog` `extdlgs.pas:74`、`TStatusBar` `comctrls.pp:120`、`TToolBar` `:2262`、`TToolButton` `:2103`、`TBevel` `extctrls.pp:671`、`TArrow` `arrow.pp:33`、`TApplicationProperties` `forms.pp:1788`（LCL 4.4 没有 `TCustomApplicationProperties`）。`TCustomTimer` `customtimer.pas:31` / `TTimer` `extctrls.pp:195`、`TCustomTrayIcon` `extctrls.pp:1408`、`TCustomActionList` `actnlist.pas:76` 是拆的（本库没有对应控件）。

**V16. LCL 的主流可见性**（scratchpad `split/lclstats.py`）：全部 92 对「`TX = class(TCustomX)`」里，`TX` 发布、且在 `TCustomX` 一层（不含 `TControl` / `TWinControl` 等通用层）声明的属性：public 1524、protected 489。按对数：73 对多数 public、10 对多数 protected（`TActionList`、`TBoundLabel`、`TDBGrid`、`TDBText`、`TLabel`、`TListView`、`TShellListView`、`TShellTreeView`、`TTreeView`、`TUpDown`）、2 对持平。**主流 = public**；protected 为主的是标签、树、列表视图、上下按钮、网格基类。

**V17. D7 的属性清单**：见附录 G。图形基类 41 个 = Ty 自有 4（Version、StyleClass、StyleOverride、Controller）+ `TControl` 已 published 2（Hint、Cursor）+ LCL public 13 + LCL protected 22；窗口化基类 52 个 = 4 + 2 + public 24 + protected 22。

**V18. 直接继承基类、又依赖基类 published 的**：注册类 105 个（窗口化 57、图形 28、`TTyComponent` 20）+ 中间类 `TTyCustomTabStrip`、`TTyCustomGrid`、`TTyCustomFileDialog` + `TTyScrollContent` + 经 `TTyCustomToolWindowManager` 的 `TTyToolWindowManager`。**内部非注册**、直接继承 `TTyCustomControl` 的 10 个（`TTyCascaderPanel`、`TTyHSVSquare`、`TTyHueBar`、`TTyIconGrid`、`TTyCaptionButton`、`TTyMenuView`、`TTyGalleryGrid`、`TTySplitterBand`、`TTyToolWindowDropPreview`，以及 V19 单列的 `TTyScrollContent`）：都由库在代码里建、不进 `.lfm`、没有 `SetSubComponent(True)`（全库 0 处），库里对它们也没有 RTTI 访问——**不需要补发布**，D7 之后它们的 Enabled 等照样经 public 访问。

**V19. 只 `RegisterClass`、会出现在 `.lfm` 里的控件类**：`TTyScrollContent`（`ScrollContent.pas:168`，`examples/containers` 里两处）——自己一个 published 都没有，全靠基类；D7 后不补就读不进 `.lfm`。它没有 LCL 对应物，按可视规则拆（Task 12），快照要包含它。`TTyCustomGrid` 也被 `RegisterClasses` 了（`Grid.pas:16012`），但面板上没有、仓库里没有 `.lfm` 用它，不兼容清单第 3 条记一句。

**V20. 库里按 RTTI 读写属性的地方**：`NativeStyler.pas:190-219`（`IsPublishedProp(AControl, 'Font' / 'ParentFont' / 'Color' / 'ParentColor')`，对象是原生 LCL 控件）、`UpDown.pas:566-589`（`GetPropInfo(FAssociate, 'Text')`，关联的控件）、`PropEditors.pas:476-477/504-505`（宿主的 `IconFont`）。最终类照旧发布这些名字，行为不变；第三方 Custom 子类若不发布 ~~`Text` / `IconFont`，UpDown 驱动不了它、~~ `IconFont`，GlyphName 编辑器拿不到字体——文档写进限制。**UpDown 一条已解决（第 0、1 期期末修复）**：UpDown 找不到 published `Text` 时退回写 `Caption`（LCL 的做法），而 `TTyCustomEdit` / `TTyCustomMemo` / `TTyCustomComboBox` 现在照 LCL 覆写 `RealGetText` / `RealSetText` 指向各自的 `Text`（Caption 就是 Text，`TTyCustomMaskEdit` 的走带掩码的 setter），不发布 `Text` 的第三方编辑框照样被驱动；为了对现有控件零副作用，三个 Custom 类去掉了 `csSetCaption`（否则 LCL 的 `SetName` 会把新控件的名字写进文字）并在 `ActionChange` 期间不让 Caption 写进文字（否则关联的 Action 每变一次就把它的 Caption 盖到用户输入上）。

**V21. `feat/advancechart` 对 `Base.pas` 的改动**（`git diff main...feat/advancechart -- source/tyControls.Base.pas`，+36 / −10）：在两个基类的 protected 段各加一个 `PointerStateChanged` 虚方法声明，实现段里 MouseEnter / Leave 等改调它。**与 published 段不重叠**；Task 1 只删 published 段、在 public 段加 4 行，git 应能自动合并；冲突时两边都要（published 段取本分支的结果、方法声明取 AdvChart 的）。

**V22. typeKey 与类名**：主题选择器认的是 `GetStyleTypeKey` 返回的字面量（`TTyButton` → `'TyButton'`；`TTyGlyphButton` 没覆写，继承 `'TyButton'`；`TTySpeedButton` → `'TySpeedButton'`），不是 Pascal 类名。R1 把覆写搬进 Custom 类，最终类不覆写——每个最终类的 typeKey 与拆分前完全一致，Custom 类与第三方子类自动吃同名 tycss 规则；`.tycss` 里永远不出现 Custom。第三方覆写成自己的新 typeKey 时，主题里没有它的规则就走不到样式（仓库记忆「Borrowed typeKey unreachable」「theme-base-layer-fallback」）——文档提醒，#14 是根治。G6 的 `#typekey` 行逐类钉住。

---

## 拆分规则（每期每个类都照做）

下面「原父类」指 `TTyXxx` 在 3.0 的父类；「Custom 父类」指 A 下 `TTyCustomXxx` 的父类：原父类是基类（`TTyCustomControl` / `TTyGraphicControl` / `TTyComponent`）或 LCL 类的不变；原父类是一个 Ty 最终类 `TTyP` 的，换成 `TTyCustomP`；原父类是中间类的，仍是那个中间类（它已在家族根的任务里改挂、降级）。每个类的 Custom 父类列在各任务的表里和附录 C-0。

- **R0 形状**：
  ```pascal
    TTyCustomXxx = class(<Custom 父类>, <原接口列表>)
    private ... protected ... public ...      // 原样搬，见 R1–R4
    published
      { 只有 R3 的那几行（多半为空，为空就不写 published 段） }
    end;

    TTyXxx = class(TTyCustomXxx)
    published
      property A;   // R5：整条链的名字，顺序照快照
      property B;
    end;
  ```
  `TTyXxx` 紧跟在 `TTyCustomXxx` 的 `end;` 后面，同一个 `type` 段。**`TTyXxx` 里只许有 `property X;` 行**（不许字段、方法、override、构造 / 析构、接口、`class var`、带类型或说明符的属性）——G3b 查源码、G4 查 InstanceSize。
- **R1 搬进 Custom 的**：全部字段、方法（含构造 / 析构、`Loaded`、`DefineProperties`、`Notification`、`GetStyleTypeKey` 与子部件 key——第三方子类照样吃主题）、接口列表、类常量 / `class var` / `class function` / 嵌套类型、原 private / protected / public 段一个字不改。
- **R2 原 published 段里、名字不是 LCL 根已 published 的属性**（D7 之后，Ty 的任何一层都不再发布东西，所以「原父类发布过」不再豁免）：
  - 本类带类型声明的 → 原样放 Custom，可见性照 **D3**（`split.py vis <LCL 对应类> <名字>`；查不到就用附录 E 该家族的「独有属性」规则）；read / write / index / default / nodefault / stored 一个都不许动。
  - 不带类型、带说明符的重声明（`property TabStop default True;`、`property Max default 50;`、`property Text write SetMaskedText;`、同名换类型的 `property Style: TTyColorBoxStyle read ...`）→ 放 Custom，可见性照 D3。`split.py block` 的 stderr 里 `R2s` 行就是这一类的检查表（它比对原父类快照与本类快照，说明符不同的都列出来——包括原来写在父控件里、这一层改了 default 的）。
  - 纯重新发布（`property Align;`）→ 不进 Custom，只出现在 R5 的发布段。**例外**：D3 要求比继承来的可见性更高（LCL 对应类把它从 protected 提到 public，如 `TCustomDrawGrid` 对一大批网格属性）→ 在 Custom 的 public 段写一行不带说明符的 `property X;`。
- **R3 名字是 LCL 根已 published 的（V3 的 15 个），且本类改了说明符**（`property Left stored False;`）→ 原样留在 Custom 的 published 段（藏不掉，也不新增名字）。`split.py block` 的 stderr 里 `R3` 行。
- **R4 Custom 类之外的同单元代码**：实现头 `procedure TTyXxx.Foo` → `TTyCustomXxx.Foo`（`split.py impl`）；`{ TTyXxx }` 分隔注释改成 `{ TTyCustomXxx }`；单元里别处的 `TTyXxx` 引用按 R6 / R7 逐处判断，不批量替换。
- **R5 `TTyXxx` 的发布段**：`python split.py block TTyXxx` 从快照生成——快照里 `TTyXxx` 的全部名字去掉 LCL 根已 published 的，按 RTTI 顺序，每个写成 `property X;`。**不手写、不调整顺序**（N1、V5-7）。
- **R6 类型判断**：按「`is` / `as` 翻转」一节与附录 C。
- **R7 签名里的类型**（A 下改写）：
  1. 事件类型的 Sender / 第一个参数写着被拆的控件 → 改 Custom 类（D10，需确认；不改就按旧做法在 Custom 里加 `AsPublished` 硬转，并记附录 D）。
  2. 参数、返回值、字段、局部变量里会有**内置派生控件流过**的 → 改 Custom 类（编译器会逼你；附录 C-4 列了已知的）。
  3. implementation 段私有函数、protected / 内部方法的参数 → 一律放宽到 Custom 类。
  4. 宿主的公开属性写着子项的最终类型（`TTyPageControl.ActivePage: TTyTabSheet`、`TTyForm.TitleBar: TTyTitleBar`、`Pages[]`……）→ ~~**保持**（LCL 先例：`TPageControl.ActivePage: TTabSheet`，`comctrls.pp:577` 起，LCL 自己在 getter 里把 `TCustomPage` 转成 `TTabSheet`）；Custom 类代码里需要把内部存的 Custom 引用交出去时，照 LCL 在 getter 里强转，记附录 D。~~ **第 0、1 期期末修复改定（先例读反了）**：LCL 那个强转是真话——`TPageControl.ChildClassAllowed` 只收 `GetPageClass = TTabSheet` 的后代（`include/pagecontrol.inc:113-117`），LCL 也没有 `TCustomTabSheet`，进得了 `TPageControl` 的页一定是 `TTabSheet`；宿主接受「任意页」的那一层 `TCustomTabControl` 对外就写 `TCustomPage`（`ActivePageComponent` / `Page[]`，`comctrls.pp:457/500`），`TCustomSpeedButton.FindDownButton` 写 `TCustomSpeedButton`（`buttons.pp:409`）。所以规则按「宿主实际会交出什么」分两种：① 宿主只交出**它自己建的**那个类（`TTyRadioGroup` 的 `TTyRadioButton`、`TTyCheckGroup` 的 `TTyCheckBox`、`AddPage` 建的 `TTyTabSheet`）→ 保持最终类，那是真话；属性的 setter 也写最终类、第三方子项根本挂不上的（`TTyForm.TitleBar` / `MenuBar`）→ 保持，文档写限制。② 宿主**接受第三方 Custom 子项**（附录 C-2 放宽过的：同组的 speed button、页认宿主的 TabSheet / RibbonPage、宿主处理的 ToolButton / RibbonGroup）→ 交出它们的属性 / 返回值写 **Custom 类**，不许在 getter 里强转成最终类（那是对第三方子项说类型假话：`is TTyTabSheet` 为 False，却以 `TTyTabSheet` 类型交出去）。改了的进不兼容清单第 5 条、记附录 D。
  5. 引用组件的属性类型 → D11（`IconFont` 必改，其余照 LCL）。
- **R8 设计期**：属性编辑器注册类改成 Custom 类（D2）；`THiddenPropertyEditor`、组件编辑器、`RegisterComponents`、`RegisterNoIcon`、`RegisterClass`、新建项模板保持最终类；原来靠继承覆盖派生控件的组件编辑器，注册行里显式加上那些派生最终类（D2）。`tests/test.designeditors.pas` 的检查在 Task 8 改成：「注册类本身 publish 了该属性，**或**有某个注册最终类（`CollectRegisteredClassNames` 解析得到的）`InheritsFrom` 注册类、且 publish 了它」；失败消息里说明两种合法情形。新出现的 Custom 类加进它的 `RegisterClasses` 块（`GetClass` 要用）。
- **R9 前向声明**：保留 `TTyXxx = class;`；别的类声明需要 Custom 类型时加 `TTyCustomXxx = class;`。
- **R10 守卫清单**：每拆一个类，在 `tests/test.customclasses.pas` 里把它从 `CPending` 挪进 `CSplit`；它是派生控件的，同时在 `CChain` 里那一行生效（G7）；降级了中间类的，把它加进 `CDemoted`（G8）。

**中间类降级时**：同一个任务里，给它的**全部**已注册后代（含不在本任务拆的，如 Task 2 的 `TTyToolButton`、Task 14 的 `TTyRibbon`）补上完整的发布段（此时它们仍是普通最终类、`class(<中间类>)` 不变），否则快照跨任务红。不在本任务拆的后代**不是**拆分形状，发布段不能只剩 `property X;`：按快照顺序（`split.py block` 输出的顺序）写出整条链的全部名字，**它自己带类型（或带说明符）声明过的名字在原位置保留原声明**，只有原来从中间类 / 基类继承来的名字写成 `property X;`（同 Task 1 的合并，一个名字在一个类里只声明一次）。照 block 输出整段替换会把它自己的属性声明全删掉（第 0、1 期 Task 2 执行时发现，期末修复改正本段与 Task 2 / Task 14 的 Step 1）。最终类改挂到 Custom 链上（如 Task 2 的 `TTyMenuButton`），它自己的发布段由 R5 生成、已含整条链的名字，仍从它派生的下游（`TTyRibbonAppMenu`）不受影响，等到自己的任务再改挂。

---

## 注意事项（每条：为什么 / 怎么防）

**N1 published 属性的顺序就是 `.lfm` 的写出顺序**
- 为什么：`TWriter` 按 RTTI 的 `NameIndex` 顺序写（V5-1），`TReader` 按文件顺序调 setter。顺序一变，新存的 `.lfm` 里 `Position` 可能跑到 `Max` 前面，读回来被默认的 `Max = 100` 钳住；老 `.lfm` 照样读得进来，示例冒烟和单测都可能是绿的。
- 规则（V5-2、V5-7）：A + D7 下几乎所有名字都在最终类第一次 published，位置 = 发布段里的书写顺序；只有 LCL 根已 published 的 15 个位置固定。
- 怎么防：R5 发布段只从快照生成；G6 逐行比对（含位置列）；变异 M-G6a（对调两行）必须红。

**N2 default 必须等于构造值；default / stored 不能丢、不能变**
- 为什么：`.lfm` 只写「不等于 default」的值。default 变了，用户设的值等于新 default 时不写、读回来却是构造值——**静默丢值**。stored 丢了，`stored False` 的位置 / 尺寸开始写进 `.lfm`。
- 容易漏的：① 改 default 的重声明（`TabStop default True` 等，附录 A 那一列）必须在 **Custom** 类里（R2 / R3），只写在最终类里时最终类快照照样绿，但第三方 `TTyCustomEdit` 子类的 `TabStop` default 回到 LCL 的 False；② 发布段写成 `property MaxLength: Integer;`（带类型）就是一个新属性，default 全丢；③ A 下**原来写在父控件里**的改动（`TTyMaskEdit` 的 `Text write SetMaskedText`、`TTyFloatSpinEdit` 的 `UseThousands default False`、`TTyColorBox` 的 `Style`）现在都在派生控件自己的 Custom 类里，`split.py block` 的 `R2s` 行列出它们。
- 怎么防：G3b（最终类只有 `property X;`，所以最终类的属性来自 Custom）+ G6（最终类与快照逐项相同）合起来，等于 Custom 类的属性与 3.0 相同；第三方模拟子类的 T-e 再从外面验一次。变异 M-G3b（在 `TTyEdit` 发布段写 `property TabStop default True;`、同时删掉 Custom 里那行）→ G3b 红；M-G6b（删一个 `default`）、M-G6c（删一个 `stored`）→ G6 红。

**N3 守卫先行**：Task 0 在任何控件改动之前拍快照并提交；后面每个任务都不许重生成快照（`TY_WRITE_GOLDEN=1` 只在 Task 0 用；N24 的合并情形例外）。快照覆盖面见 G6。

**N4 库里的类型判断**：见「`is` / `as` 翻转」一节、附录 C。

**N5 设计期注册**：见 D2、R8、V6、V7。组件面板图标（按最终类名）、默认尺寸（在构造里，随 R1 进 Custom）、新建项模板（只涉及 `TTyForm` / `TTyDialog` / `TTyTitleBar` / `TTyStyleController`，不改类名）不变。Task 8 改 test.designeditors 时保住原来的抓错能力——变异 M-D1：把 Custom 类上的注册属性名改错（`'Directory'` → `'Directry'`）必须红；M-D2：把某条注册改到一个没有任何注册后代发布该属性的类（如 `TTyCustomEdit`）必须红。

**N6 按类名推导东西的地方**：见 V8、V22。新加的 Custom 类**不要** `RegisterClass`。审查时 grep 一遍 `ClassName`、`ClassType`、`ClassParent`、`FindClass`、`GetClass` 有没有新增。

**N7 命名冲突**：见 V9。同一单元多个类同时拆（CheckBox.pas、ToolBar.pas、Ribbon.pas、GlyphButtons.pas、DropButtons.pas、Grid.pas、ImageCollection.pas、Icons.Lucide.pas）：`split.py impl` 每次只改一个类，按类分次跑。

**N8 改文件的工具坑**（仓库记忆「Git Bash sed -i 吃 CRLF」「Bash heredoc 吃反斜杠」「CRLF 上的变异替换 = 假存活」）
- **绝不用 `sed -i`**。
- 含反斜杠的脚本、正则、测试数据用 Write 工具落文件，不用 heredoc。
- 改 `.pas` 用 Edit 工具或 `split.py pt`；`split.py check <file>` 确认换行风格和 BOM 没变。
- FPC 的 `{ }` 注释会嵌套：注释里别带 `{`；线索是第一条 `Comment level 2` 警告。
- 变异：替换后**读回来和原文比**；`finally` 里还原后**重编一次**。

**N9 测试里的 cracker 类**：`TXxxAccess = class(TTyXxx)` 访问 protected 成员照常可用（成员在 Custom 里，最终类继承它们）。A 下要注意：cracker 若被拿来**硬转一个派生控件**（`TListBoxAccess(aValueListEditor)`），派生控件已不是 `TTyXxx` 的后代——改成 `class(TTyCustomXxx)`。全量里 cracker 相关的编译错误若是「有人往 `TTyXxx` 里留了代码」，回去按 R0 挪进 Custom，别改测试。

**N10 合并与后续**
- 3.0 是 LTS，修复先进 `3.0-fixes` 再 cherry-pick 进 main。拆过的单元**必冲突**，手工移植：补丁里的 `TTyXxx.` 换成 `TTyCustomXxx.`；published 段的改动换到 Custom 的 public / protected（D3）与 R5 发布段；基类 published 段的改动换到 Task 1 之后的各子类发布段。**【主控执行】每期签收后告诉「3.0 问题修复」会话：哪些单元已拆、移植的规矩。**
- `feat/advancechart` 合进 main 时：`Base.pas` 见 V21；`AdvanceChart.pas` / `Calendar.pas` / `DateTimePicker.pas` 的 published 段首有 Task 1 插的基类块（Q3）——冲突时取 AdvChart 一侧的 published 段，段首用 `split.py base` 重新生成；然后按附录 B 补拆。
- `feat/theme-builder` 合进 main 时：`tests/tytests.lpr`、`tests/tytests.lpi` 手工合；合完 grep `tools/themebuilder/` 的 `is TTy` / `as TTy` / `TTy...(` 硬转，按附录 C 的规则判断。
- 开工前先 `git merge main`。

**N11 示例与文档**
- A 下示例 `.pas` **要改**（附录 C-1 的示例行、D10 的处理过程签名）；`.lfm` 一个字不改。【主控执行】每期末编全部示例 + `scripts/smoke-launch-examples.ps1` + `python scripts/check-lfm-props.py`。
- 文档见 D8 / Task 31。合 main 前按仓库记忆「合 main 前查 i18n 与 README」查一遍——本计划不加用户可见文字。

**N12 性能与二进制**：多一层类只多一个 VMT 和一份类型信息（156 个合计几十 KB）；published 属性的 RTTI 条目总数基本不变（基类不发布了，子类各发布一份——每个类多 37–48 个条目，合计约 100 KB 量级的 RTTI，可接受）。运行时分派与属性访问的生成代码不变。

**N13 LCL 根发布的 15 个属性藏不掉**：`TComponent` 的 Name / Tag、`TControl` 的 13 个（V3）。D7 之后第三方 `TTyCustomEdit` 子类在对象查看器里只带这 15 个（以前是 67 个）。文档写进限制。

**N14 改继承链会改 `is` 的答案**：这是 D1 = A 的已知代价，处理见「`is` / `as` 翻转」一节；审查时专门核附录 C-1 每一行都落实了、都有测试或理由。

**N15 既有的「Custom」类**：`TTyCustomTabStrip`、`TTyCustomGrid` 在本计划里降级成真正的 Custom 层（Task 14 / 18）；`TTyCustomFileDialog` 不动（LCL `TFileDialog` 本来就各层 published）；`TTyCustomToolWindowManager` 见 Q4。

**N16 原 published 段在 Custom 里放哪**：见 R2 / R3 / D3。最容易犯的错是图省事把整个 `published` 改成 `protected`：编得过，快照也绿，但 ① D3 要 public 的成了 protected（第三方经 Custom 引用访问不到）；② `property Align;` 之类变成「把 public 降成 protected」的重声明，误导读者。按 R2 / R3 / D3 分拣，不整段改关键字。审查对每个类抽 5 个属性跑 `split.py vis` 核对。

**N17 跨单元读写 Custom 类的 protected 属性**：放宽类型判断后，另一个单元拿 `TTyCustomXxx` 去读写一个 D3 定为 protected 的属性会编不过。在**用的那个单元**的 implementation 段声明 `type TTyCustomXxxAccess = class(TTyCustomXxx);`，强转后访问，注释写「protected since the custom-class split (LCL visibility); the access class reaches it for any TTyCustomXxx」。不许为此把属性提成 public（违反 D3），也不许退回强转成最终类（对第三方子类是类型假话）。

**N18 test.designeditors 的规则要改**：见 V7 / R8 / N5。

**N19 组件编辑器为什么不跟着挪**：见 D2。

**N20 `DefineProperties` 照写**：随 R1 进 Custom，第三方子类哪怕不发布 `Items`，`DefineProperties` 写的隐藏数据照样进 `.lfm`（状态不丢，但第三方可能意外）。文档写一句；第三方模拟子类的流式测试把 `DefineProperties` 写的名字单列，不当成泄漏。

**N21 check-lfm-props.py 抓不到漏发布**：见 V14。

**N22 同单元的引用、实现头、类方法**：实现头漏改一个，编译器报「方法未在类里声明」——好事。外部按 `TTyShellTreeView.GetFilesInDir(...)` 调类方法照常（V5-6）。编译器报 `Incompatible types` 时按 R7 判断，不是公开签名就放宽。

**N23 内部辅助子类不动**（V12），例外是它们流进的签名（Task 15 的弹层 API）。

**N24 快照守卫是迁移期的**：别的分支给已拆控件加 / 改 published 属性，合进来就会让 G6 红——这时只重生成**那一个类**的快照段（`TY_WRITE_GOLDEN_CLASS`），提交说明写清。Task 32 删除（D9）。

**N25 以后的新控件**：G5 常驻——以后谁往面板加一个类，不拆、也不写进 `CNotSplit` 说明理由，全量就红；G8 常驻——谁往基类加 published，全量就红。CONTRIBUTING 加一句（D8）。

**N26 无头测试**：第三方模拟子类不建窗口句柄；渲染比较走现成的 `RenderTo`（仓库记忆「验窗口化控件用 RenderTo」）；对齐靠手调 `AdjustClientRect` + `AlignControls`（仓库记忆「跑不到 LCL 对齐引擎」）。快照给每个注册类建一个新实例读 `IsStoredProp` / 序数值 / typeKey，个别 getter 无父窗口会抛——记成 `x`。

**N27 注释**：类头上方的大段说明留在 Custom 类上；最终类上方只写一行 `{ TTyXxx publishes ...; everything lives in TTyCustomXxx. }`。不要把旧注释里的 `TTyXxx` 全换成 `TTyCustomXxx`——注释讲的是用户看到的控件。注释里写着「is a TTyButton」「descends from TTyListBox」这类**层级事实**的（如 `CompEditors.pas:1153-1157`、`test.scrollbar.autohide.pas:1411-1413`、`ComboBox.pas:359`），A 下改写成真话。

**N28 一个属性两段声明时的顺序陷阱**：快照顺序以 RTTI 为准，`split.py block` 已处理；手工检查时别以「源码里第一个 published 段」为准。

**N29 typeKey 跟着 Custom 类走**：见 V22。`GetStyleTypeKey` 与子部件 key 的覆写一律在 Custom 类（R1）；G6 的 `#typekey` 行钉住每个注册类拆前拆后相同；变异 M-G6k（删掉 `TTyCustomSpeedButton` 的 `GetStyleTypeKey` 覆写，它会退回 `'TyButton'`）必须红。文档写清：Custom 类与第三方子类自动吃同名 tycss 规则，`.tycss` 里永远不写 Custom；第三方覆写成新 typeKey 时主题里要有它的规则（#14 之前没有回落）。

**N30 D7 之后的测试探针类**：`tests/` 里有 12 个探针类直接继承 `TTyCustomControl` / `TTyGraphicControl`（`test.base.pas:9`、`test.controller.pas:9`、`test.fontcascade.pas:16` 等）。若某条测试经流式或 RTTI 依赖它们的基类 published 属性，Task 1 的全量会红——给探针类自己补 published，不改断言（这本身就是「不兼容清单第 2 条」的迁移写法的现场证明，签收里记下有几处）。

**N31 G6 不比 stored 方法与 setter 的身份**（第 0、1 期期末修复补）
- 为什么：快照的 `Stored` 列只记「常量 True / 常量 False / 方法或字段」三种，`Access` 只记 `R` / `W` / `RW`——`stored IsFooStored` 换成另一个方法、`write SetMaskedText` 换成 `write SetText`，快照一字不变。
- 谁兜底：说明符**写在哪一层**由 G3b（最终类只许 `property X;`，最终类上不可能有一个不同的 setter / stored）与 G9（照抄发布段的第三方模拟类与最终类逐项相同，含新实例流出的文本）守住；Custom 类**自己**把 setter / stored 方法换错了（两边一起错），结构守卫看不见，靠行为测试——`TestThirdMaskEdit`（`Text` 必须走带掩码的 setter）、`TestCaptionIsTextOnEditMemoAndCombo`、各控件自己的 suite。新拆的家族里有「同名重声明换 setter / stored」的（`R2s` 行），每个配一条行为测试。

---

## 实现期的地雷（每个任务开工前看一眼）

1. **不 amend、不 rebase、不 reset、不 stash、不 checkout 丢改动**；一个任务一个提交，修复另起提交。
2. **绝不用 `sed -i`**；含反斜杠的内容用 Write 落文件；`.pas` 用 Edit 或 `split.py pt`（N8）。
3. **只按 PID 结束进程，绝不 `taskkill -im`**。
4. **不编 `.lpk`、不编 `examples/`**（【主控执行】）；只编 `tests/tytests.lpi`。
5. **不改** `Painter.pas`、`StyleModel.pas`、`TextMenu.pas`、`DefaultTheme.pas`、`Css.Catalog.pas`、`StrConsts.pas`；`Base.pas` / `Component.pas` 只在 Task 1 改；排除的 `AdvanceChart.pas`、`Calendar.pas`、`DateTimePicker.pas` 只在 Task 1 插基类块（Q3），别处一行不碰。
6. **家族根先拆**：派生控件的 Custom 父类必须已经存在；中间类降级的任务里给它的全部注册后代补发布段。
7. **发布段只用 `split.py block` / `split.py base` 生成**，不手写、不调顺序（N1）；不重生成快照（N3）。
8. **类型判断按附录 C**：C-1「必改」一处不漏，C-2 放宽，C-3 保持；新发现的照规则补进附录 C 并写测试。
9. **编译探针别把 `.ppu` 写进 `source/`**：任何手编都带 `-FU`；每期编译前 `ls source/*.ppu source/*.o 2>/dev/null` 必须为空。
10. **跑 tytests 用复制出来的 `tytests-split.exe`，输出重定向到文件**；判据是每个 suite 那一行有 `Number of run tests`、errors / failures 为 0。
11. **单跑绿 / 全量红**：先 `lazbuild -B` 重编，再查进程级状态。
12. **注释与代码风格**：库里新加的注释用英文、照所在单元的惯例；提交说明英文。

---

## 跑测试的固定套路（只在 Task 0、Task 1 与每期收尾跑）

改了 `source/` 或 `designtime/` 之后必须 `lazbuild -B`。

```bash
cd /d/Projects/ty-split && ls source/*.ppu source/*.o 2>/dev/null | wc -l && lazbuild -B tests/tytests.lpi > /tmp/split-build.txt 2>&1 || { tail -30 /tmp/split-build.txt; false; } && grep -c "Error:" /tmp/split-build.txt; cd tests && cp tytests.exe tytests-split.exe && for s in $SUITES; do ./tytests-split.exe --suite=$s --format=plain > /tmp/split-$s.txt 2>&1; printf '%s: ' $s; grep -E "Number of (run tests|errors|failures|ignored)" /tmp/split-$s.txt | tr '\n' ' '; echo; done
```

第一个数必须是 0。`SUITES` 至少包含：`TTyCustomClassesGuardTest TVersionTest TDesignEditorsTest TPaletteIconTest TTyFocusTabStopTest TTyClickFocusTest`，加上当期的 `TTyCustomClassesP1Test` … `P4Test`，再加当期动过的控件自己的 suite（`grep -l "TTyXxx" tests/test.*.pas` 找出单元，再取其中 `RegisterTest(...)` 的类名）。

全量（输出必须重定向到文件）：

```bash
cd /d/Projects/ty-split/tests && ./tytests-split.exe --all --format=plain > /tmp/split-all.txt 2>&1; grep -E "Number of (run tests|errors|failures|ignored)" /tmp/split-all.txt; grep -E "^\s+(Failed|Error):" /tmp/split-all.txt | head -40
```

---

## 辅助脚本 `split.py`（scratchpad，不进仓库）

每期开工时若 scratchpad 里没有，用 **Write 工具**（不是 heredoc）原样写到 `<scratchpad>/split.py`。在 `D:/Projects/ty-split` 下运行。写计划时已在 scratchpad 里用假快照测过 `base` / `block`，用真 LCL 源码测过 `vis`（与 `pasclasses.py` 结果一致），用 CRLF 文件测过 `impl`（换行保住）。

```python
#!/usr/bin/env python
"""Custom-class split helper. Run from the repo root (D:/Projects/ty-split).

  python split.py base <Class>
      Task 1 (D7). The base-class names <Class> must now publish itself, in RTTI
      order: the names its Ty base (TTyCustomControl / TTyGraphicControl /
      TTyComponent) published that the LCL root does not. To stderr: every one whose
      attributes on <Class> differ from the base's -- that line must carry <Class>'s
      own specifiers (copy them from its source) and its later duplicate is deleted.
  python split.py block <TTyXxx>
      The TTyXxx published block (option A + D7): every name the snapshot has for
      TTyXxx minus the names its LCL root publishes, in RTTI order, one `property X;`
      per line. To stderr:
        R3  name: the LCL root publishes it and TTyXxx changes its attributes -> that
            redeclaration stays in TTyCustomXxx's published section, verbatim;
        R2s name: the original Ty parent has it with other attributes -> TTyCustomXxx
            redeclares it with TTyXxx's specifiers (visibility per D3, `vis`).
  python split.py vis <LclClass> [<Prop>...]
      Visibility of each property as seen at <LclClass> (most-derived declaration at
      or above it) and where it is declared, from C:/lazarus/lcl sources. No props =
      all of them.
  python split.py impl <unit.pas> <TTyXxx>
      Rename implementation headers `procedure TTyXxx.` (function / constructor /
      destructor / class procedure / class function / operator) to TTyCustomXxx.
      Prints the count; refuses 0.
  python split.py pt <file> <patchfile>
      Blocks of '@@@@ OLD [n]' / '@@@@ NEW' / '@@@@ END'. Each OLD must occur exactly
      n times (default 1). Newline style and BOM preserved.
  python split.py check <file>
      Newline style and BOM of <file> must equal `git show HEAD:<file>`.
"""
import os, re, subprocess, sys

SNAP = 'tests/fixtures/customclasses/published-snapshot.txt'
LCL = os.environ.get('TY_LCL_DIR', 'C:/lazarus/lcl')
TY_BASES = ('TTyCustomControl', 'TTyGraphicControl', 'TTyComponent')


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


# ---------------------------------------------------------------- snapshot

def load_snapshot():
    """{class: {'chain': [ancestors, parent first], 'rows': [10 fields]}}"""
    t, _, _ = read(SNAP)
    out, cur = {}, None
    for line in t.split('\n'):
        if line.startswith('# '):
            parts = line[2:].split()
            cur = parts[0]
            chain = []
            for p in parts[1:]:
                if p.startswith('chain='):
                    chain = [c for c in p[6:].split(',') if c]
            out[cur] = {'chain': chain, 'rows': []}
        elif line.startswith('#'):
            continue  # '#typekey' and other non-property lines
        elif line and cur:
            f = line.split('\t')
            if len(f) != 10:
                die('bad snapshot line: ' + line)
            out[cur]['rows'].append(f)
    return out


def attrs(f):
    return f[3:9]  # type, kind, default, stored, index, access


def lcl_root(s, cls):
    for c in s[cls]['chain']:
        if not c.startswith('TTy'):
            if c not in s:
                die('%s: LCL root %s is not in the snapshot' % (cls, c))
            return c
    die(cls + ': no LCL ancestor in its chain')


def base(cls):
    s = load_snapshot()
    if cls not in s:
        die(cls + ' is not in the snapshot')
    tybase = next((c for c in s[cls]['chain'] if c in TY_BASES), None)
    if tybase is None:
        die(cls + ' does not descend from a Ty base class')
    root = lcl_root(s, cls)
    rootnames = {f[2].lower() for f in s[root]['rows']}
    bmap = {f[2].lower(): f for f in s[tybase]['rows']}
    for f in s[cls]['rows']:
        k = f[2].lower()
        if k in bmap and k not in rootnames:
            print('    property %s;' % f[2])
            if attrs(bmap[k]) != attrs(f):
                sys.stderr.write('merge %s: %s=%s  %s=%s\n' % (
                    f[2], tybase, '|'.join(attrs(bmap[k])), cls, '|'.join(attrs(f))))


def block(final):
    s = load_snapshot()
    if final not in s:
        die(final + ' is not in the snapshot')
    root = lcl_root(s, final)
    rmap = {f[2].lower(): f for f in s[root]['rows']}
    parent = s[final]['chain'][0] if s[final]['chain'] else None
    pmap = {f[2].lower(): f for f in s[parent]['rows']} if parent in s else {}
    print('  %s = class(TTyCustom%s)' % (final, final[3:]))
    print('  published')
    for f in s[final]['rows']:
        k = f[2].lower()
        if k in rmap:
            if attrs(rmap[k]) != attrs(f):
                sys.stderr.write('R3 %s: %s=%s  %s=%s\n' % (
                    f[2], root, '|'.join(attrs(rmap[k])), final, '|'.join(attrs(f))))
            continue
        print('    property %s;' % f[2])
        if k in pmap and attrs(pmap[k]) != attrs(f):
            sys.stderr.write('R2s %s: %s=%s  %s=%s\n' % (
                f[2], parent, '|'.join(attrs(pmap[k])), final, '|'.join(attrs(f))))
    print('  end;')


# ---------------------------------------------------------------- LCL visibility

CLS = re.compile(r'^\s*(\w+)\s*=\s*class\s*(?:\(([^)]*)\))?\s*(;)?', re.I)
VIS = re.compile(r'^\s*(?:strict\s+)?(private|protected|public|published)\b', re.I)
PROP = re.compile(r'^\s*(?:class\s+)?property\s+(\w+)', re.I)
END = re.compile(r'^\s*end\s*;', re.I)


def strip_comments(t):
    out = []; i = 0; n = len(t)
    while i < n:
        c = t[i]
        if c == '{':
            j = t.find('}', i + 1); j = n if j < 0 else j + 1
            out.append(re.sub(r'[^\n]', ' ', t[i:j])); i = j
        elif t.startswith('(*', i):
            j = t.find('*)', i + 2); j = n if j < 0 else j + 2
            out.append(re.sub(r'[^\n]', ' ', t[i:j])); i = j
        elif t.startswith('//', i):
            j = t.find('\n', i); j = n if j < 0 else j
            out.append(' ' * (j - i)); i = j
        elif c == "'":
            j = i + 1
            while j < n and t[j] != "'" and t[j] != '\n':
                j += 1
            out.append(t[i:j + 1]); i = j + 1
        else:
            out.append(c); i += 1
    return ''.join(out)


def lcl_index():
    idx = {}
    for r, _, fs in os.walk(LCL):
        for fn in fs:
            if not fn.lower().endswith(('.pp', '.pas')):
                continue
            path = os.path.join(r, fn)
            t = open(path, 'rb').read().decode('utf-8', 'replace').replace('\r\n', '\n')
            lines = strip_comments(t).split('\n')
            i = 0
            while i < len(lines):
                m = CLS.match(lines[i])
                if (not m or m.group(3) or re.search(r'\bend\s*;', lines[i], re.I)
                        or re.match(r'^\s*\w+\s*=\s*class\s+of\b', lines[i], re.I)):
                    i += 1; continue
                name, parent = m.group(1), (m.group(2) or 'TObject').split(',')[0].strip()
                vis, props, depth, j = 'default', [], 0, i + 1
                while j < len(lines):
                    L = lines[j]
                    if re.match(r'^\s*\w+\s*=\s*(packed\s+)?(record|class\b(?!\s+of)|object|interface)\b(?!.*;\s*$)',
                                L, re.I) and not re.search(r'\bclass\s*\([^)]*\)\s*;', L):
                        depth += 1
                    elif re.search(r':\s*(packed\s+)?record\b', L, re.I):
                        depth += 1
                    if END.match(L):
                        if depth == 0:
                            break
                        depth -= 1
                    elif depth == 0:
                        vm = VIS.match(L)
                        if vm:
                            vis = vm.group(1).lower()
                        pm = PROP.match(L)
                        if pm:
                            props.append((pm.group(1), vis, j + 1))
                    j += 1
                k = name.lower()
                if k not in idx or len(props) > len(idx[k][2]):
                    idx[k] = (name, parent, props, path, i + 1)
                i = j + 1
    return idx


def vis(cls, names):
    idx = lcl_index()
    if cls.lower() not in idx:
        die(cls + ' not found under ' + LCL)
    seen, c, chain = {}, cls.lower(), []
    while c in idx:
        name, parent, props, path, line = idx[c]
        chain.append('%s(%s:%d)' % (name, os.path.relpath(path, LCL).replace('\\', '/'), line))
        for p, v, ln in props:
            seen.setdefault(p.lower(), (p, v, name, os.path.basename(path), ln))
        c = parent.lower()
    print('# ' + ' <- '.join(chain))
    want = [n.lower() for n in names] or sorted(seen)
    for k in want:
        if k in seen:
            p, v, d, f, ln = seen[k]
            print('%-28s %-10s %s %s:%d' % (p, v, d, f, ln))
        else:
            print('%-28s %-10s (no LCL declaration: use the family rule of the D3 table)' % (k, '-'))


# ---------------------------------------------------------------- source edits

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
    if a[:1] == ['base'] and len(a) == 2:
        base(a[1])
    elif a[:1] == ['block'] and len(a) == 2:
        block(a[1])
    elif a[:1] == ['vis'] and len(a) >= 2:
        vis(a[1], a[2:])
    elif a[:1] == ['impl'] and len(a) == 3:
        impl(a[1], a[2])
    elif a[:1] == ['pt'] and len(a) == 3:
        pt(a[1], a[2])
    elif a[:1] == ['check'] and len(a) == 2:
        check(a[1])
    else:
        die(__doc__)
```

**每个类的标准步骤**（Task 2–30 的「拆」都指这一串，任务里不再重复）：
1. `python split.py block TTyXxx`，把输出和 stderr 的 R3 / R2s 清单存进 scratchpad 草稿；对 `R2s` 与本类带类型的属性，`python split.py vis <附录 E 的 LCL 对应类> <名字...>` 定可见性，写进草稿。
2. 在单元里把类头 `TTyXxx = class(<原父类>` 改成 `TTyCustomXxx = class(<Custom 父类>`（Edit 工具）。
3. 按 R2 / R3 / D3 分拣原 published 段（附录 A 的「带说明符的重声明」列 + 第 1 步的清单是检查表）。
4. 在 Custom 类 `end;` 后贴第 1 步打印的最终类声明，前面加一行注释（N27）。
5. `python split.py impl source/tyControls.Xxx.pas TTyXxx`；改 `{ TTyXxx }` 分隔注释。
6. 同单元内其余 `TTyXxx` 引用按 R6 / R7 / 附录 C 处理。
7. `tests/test.customclasses.pas`：`CPending` → `CSplit`（R10）；然后在仓库根跑 `python <scratchpad>/gen-mimic.py`，重生成 `tests/test.customclasses.mimic.pas`（G9；不重跑，G9 报「split class without a mimic」）。生成器拒绝发布段里有 `property X;` 以外内容的最终类（与 G3b 同一条规矩）。
8. `python split.py check` 本任务动过的每个文件。

---

## 辅助脚本 `gen-mimic.py`（scratchpad，不进仓库；第 0、1 期期末修复加）

每期开工时若 scratchpad 里没有，用 **Write 工具**原样写到 `<scratchpad>/gen-mimic.py`。在 `D:/Projects/ty-split` 下运行，无参数；输出 `tests/test.customclasses.mimic.pas`（CRLF）。生成物进仓库（G9 读它），手不改它。

```python
#!/usr/bin/env python
"""Generate tests/test.customclasses.mimic.pas. Run from the repo root (D:/Projects/ty-split).

For every class in CSplit (the AddAll(GSplit, [...]) block of tests/test.customclasses.pas) it
finds `TTyXxx = class(TTyCustomXxx)` in source/*.pas and writes `TGenXxx = class(TTyCustomXxx)`
with the final class's published section copied line by line (comments dropped). The guard
TestGeneratedMimicsMatchTheirFinalClass then holds each pair to identical RTTI, fresh stream,
type key, default size and resolved style -- i.e. a third party that publishes what the final
class publishes gets exactly the final class. Re-run after every split task; the guard turns red
when a split class has no mimic."""
import glob, io, re, sys

GUARD = 'tests/test.customclasses.pas'
OUT = 'tests/test.customclasses.mimic.pas'


def strip_comments(src):
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '{':
            j = src.find('}', i)
            j = n - 1 if j < 0 else j
            out.append('\n' * src[i:j + 1].count('\n'))
            i = j + 1
            continue
        if src.startswith('(*', i):
            j = src.find('*)', i)
            j = n - 2 if j < 0 else j
            out.append('\n' * src[i:j + 2].count('\n'))
            i = j + 2
            continue
        if src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if c == "'":
            j = src.find("'", i + 1)
            j = n - 1 if j < 0 else j
            out.append(src[i:j + 1])
            i = j + 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def split_names():
    g = io.open(GUARD, encoding='utf-8').read()
    m = re.search(r'AddAll\(GSplit,\s*\[(.*?)\]\);', g, re.S)
    if not m:
        sys.exit('no AddAll(GSplit, [...]) block in ' + GUARD)
    body = re.sub(r'//[^\n]*', '', m.group(1))
    return re.findall(r"'(TTy\w+)'", body)


def main():
    names = split_names()
    found = {}
    for f in sorted(glob.glob('source/*.pas')):
        raw = io.open(f, encoding='utf-8', errors='replace').read().replace('\r\n', '\n')
        unit = re.search(r'^unit\s+([\w.]+)\s*;', raw, re.M | re.I).group(1)
        lines = strip_comments(raw).split('\n')
        for i, l in enumerate(lines):
            m = re.match(r'\s*(TTy\w+)\s*=\s*class\((TTyCustom\w+)\)\s*$', l)
            if not m or m.group(1) not in names:
                continue
            if m.group(2) != 'TTyCustom' + m.group(1)[3:]:
                continue
            body, j = [], i + 1
            while not re.match(r'\s*end\s*;', lines[j]):
                t = lines[j].strip()
                if t:
                    if not re.match(r'^(published|property\s+\w+\s*;)$', t, re.I):
                        sys.exit('%s: %s is not property-only: %r' % (f, m.group(1), t))
                    body.append('    ' + t if t.lower().startswith('property') else '  ' + t)
                j += 1
            found[m.group(1)] = (unit, m.group(2), body)
    missing = [n for n in names if n not in found]
    if missing:
        sys.exit('split classes without a declaration in source/: ' + ', '.join(missing))
    units = sorted(set(v[0] for v in found.values()))
    out = []
    out.append('unit test.customclasses.mimic;')
    out.append('{$mode objfpc}{$H+}')
    out.append('')
    out.append('{ GENERATED by the plan\'s gen-mimic.py -- do not edit by hand; re-run it after every split.')
    out.append('')
    out.append('  One mimic per split class: TGenXxx derives from TTyCustomXxx the way a third party does')
    out.append('  (issue #8) and publishes exactly the lines the library\'s TTyXxx publishes. The guard')
    out.append('  TestGeneratedMimicsMatchTheirFinalClass (test.customclasses) holds each pair to the same')
    out.append('  RTTI, fresh stream, type key, default size and resolved style -- so every default, stored')
    out.append('  clause and type key a final class shows must come from its custom class, where a third')
    out.append('  party gets it too. }')
    out.append('')
    out.append('interface')
    out.append('')
    out.append('uses')
    uses = ['Classes'] + units
    line = '  '
    for k, u in enumerate(uses):
        piece = u + (',' if k < len(uses) - 1 else ';')
        if len(line) + len(piece) + 1 > 100:
            out.append(line.rstrip())
            line = '  '
        line += piece + ' '
    out.append(line.rstrip())
    out.append('')
    out.append('type')
    for n in sorted(found):
        unit, cust, body = found[n]
        out.append('  TGen%s = class(%s)' % (n[3:], cust))
        out.extend(body)
        out.append('  end;')
        out.append('')
    out.append('const')
    out.append('  { (mimic, final class) }')
    out.append('  CGenMimics: array[0..%d, 0..1] of TClass = (' % (len(found) - 1))
    pairs = ['    (TGen%s, %s)' % (n[3:], n) for n in sorted(found)]
    out.append(',\n'.join(pairs) + ');')
    out.append('')
    out.append('implementation')
    out.append('')
    out.append('end.')
    io.open(OUT, 'w', encoding='utf-8', newline='\r\n').write('\n'.join(out) + '\n')
    print('%s: %d mimics' % (OUT, len(found)))


if __name__ == '__main__':
    main()
```

---

## 关于判据和变异

- 守卫与模拟子类写**判据**（比什么、怎么数、失败打印什么），测试代码执行时现写（仓库记忆「plan 里写判据别写测试代码」）。快照格式这种「数据契约」写死在 Task 0。
- 每条判据写明「**在哪个变异下必须红**」；变异在每期收尾集中做：改一行 → **读回来与原文比** → `lazbuild -B` → 跑相关 suite → **必须红** → 改回 → 重编 → 重跑 → 绿。没红先查改没改对地方（CRLF 假存活）、再查是不是「这条路走不到」；确实没红，当场补测试，签收写一句。
- 断言里那个量要真的变过（仓库记忆「断言里那个量从没变过」）：「内置派生控件被宿主认出」之前先证明**改回最终类时**它不被认出（变异就是这个）；「第三方子类的 `TabStop` default 与构造值一致」之前先证明这个类的构造值确实不是 LCL 的默认。
- 「—」= 不做变异，理由写在表里。

---

## 第 0 期：快照与基类

### Task 0: 起点、RTTI + typeKey 快照、常驻结构守卫、基线

**Files:**
- Create: `tests/test.customclasses.pas`（suite `TTyCustomClassesGuardTest`）
- Create: `tests/fixtures/customclasses/published-snapshot.txt`
- Modify: `tests/tytests.lpr`（uses 末尾加 `test.customclasses`）
- 不进仓库：`<scratchpad>/split.py`

- [x] **Step 1: 【主控执行】需主控确认的 Q1–Q8**：答复写进「需主控确认」表下方（加一个「状态」引用块）；没回复就按建议做。Q7（D10）选「不改」时，Task 17 / 20 / 21 改回 `AsPublished` 做法；Q8（D11）只做被迫的 `IconFont` 时，Task 27 / 28 跳过另三类属性类型。

- [x] **Step 2: 起点**

```bash
cd /d/Projects/ty-split && git status --short && git branch --show-current && git merge --no-edit main && git log --oneline -1 && git cherry main 3.0-fixes | grep -c '^+'
```

Expected：工作区干净；分支 `feat/custom-classes`；合并成功；**最后一个数除下列 6 个外为 0**（主控 2026-10-02 核实、用户确认 3.0 已合完）：`d87ed893 release: 3.0.0-RC2`、`4a21ebeb release: 3.0.0-RC3`、`e41a8908 docs(readme): 165 controls…` 只属于 3.0 的发版 / 文档提交；另 3 个（ClearType 文字、3.0.0 发版、设计期注册内置主题）在 main 上以不同补丁存在（`b23893ba`、`cd9907e9`、`ca2596db`）。多出这 6 个以外的 = 3.0-fixes 还有修复没进 main，**停下交主控**。

- [x] **Step 3: 复核排除清单**

```bash
cd /d/Projects/ty-split && for b in feat/advancechart tmp/an1; do for c in $(git cherry main $b | grep '^+' | awk '{print $2}'); do git show --name-only --format= $c; done; done | grep -E '^(source|designtime)/' | grep -vE 'AdvChart\.|AdvanceChart|Base\.pas|Painter\.pas|FontUnits|DefaultTheme|Css\.Catalog|StrConsts' | sort -u; for t in /d/Projects/ty-advchart /d/Projects/ty-an1 /d/Projects/ty-3.1; do git -C $t status --short | grep -E '(source|designtime)/'; done; for c in $(git cherry main feat/theme-builder | grep '^+' | awk '{print $2}'); do git show --name-only --format= $c; done | grep -E '^source/tyControls\.' | grep -vE 'ThemeLint|Css\.' | sort -u; git diff main...feat/advancechart -- source/tyControls.Base.pas | grep -cE '^[-+]\s+property '
```

Expected：第一段只有 `Calendar.pas`、`DateTimePicker.pas`；第二段只有 AdvChart 相关与共享单元；第三段为空；**最后一个数是 0**（AdvChart 没碰基类的 published 段，V21）。多出任何控件单元：把它的类移进 `CNotSplit`（理由「touched by <branch>, split after it merges」），从对应任务里划掉，附录 B 加一行，签收写明。最后一个数不为 0：停下交主控（Task 1 会和它冲突）。

- [x] **Step 4: 辅助脚本**：照「辅助脚本 `split.py`」一节用 Write 工具写进 scratchpad；`python split.py` 不带参数应打印用法并以 1 退出；`python split.py vis TCustomEdit Text` 应打印 `Text  public  TCustomEdit stdctrls.pp:878`。

- [x] **Step 5: 守卫单元 `tests/test.customclasses.pas`**（单元头注释：为什么有它——issue #8 的拆分要保证「`.lfm` 一个字不变、主题一个规则不变、第三方子类拿到同样的默认值」，快照在拆分前由当时的代码生成；G6 是迁移期的，Task 32 删除，G1–G5、G7、G8 常驻）。uses `test.designregistry`（`CollectRegisteredClassNames`、`RepoRoot`）、`test.version`（它的 initialization 把所有注册类 `RegisterClasses`）、各基类 / 中间类所在单元、`ScrollContent`。

  **清单常量**（R10）：
  - `CSplit`：已拆的最终类，Task 0 为空（initialization 里填的动态数组）。
  - `CPending`：Task 0 填入附录 A「处置」列为 T2–T30 的 156 个名字，每个任务挪走自己那几个；Task 32 删掉这个清单。
  - `CNotSplit`：名字 + 一句英文理由：`TTyForm`、`TTyDialog`（designer base classes, the TForm role; Q5）；`TTyPopupMenu`、`TTyImagesMenu`、`TTyMenuEx`（LCL does not split TPopupMenu, menus.pp:465）；11 个对话框（LCL does not split TCommonDialog descendants, dialogs.pp:87-515 / extdlgs.pas:74）；`TTyToolWindowManager`（already TTyCustomToolWindowManager + final; the final carries the implementation for unit dependencies; Q4）；`TTyAdvanceChart`、`TTyCalendar`、`TTyDateTimePicker`（split after feat/advancechart merges, appendix B）。
  - `CStreamOnly`：`TTyScrollContent`（RegisterClass'd, appears in .lfm, not on the palette）。
  - `CSnapshotInputs`（只用作 `split.py` 的输入，不比对；类引用直接写）：`TTyCustomControl`、`TTyGraphicControl`、`TTyComponent`、`TTyGlyphButtonBase`、`TTyCustomTabStrip`、`TTyCustomGrid`、`TTyShellTreeLink`、`TTyIconPackFont`、`TTyCustomFileDialog`、`TTyCustomToolWindowManager`。
  - `CLclRoots`（输入，**也比对**——它们永远不该变）：`TComponent`、`TCustomControl`、`TGraphicControl`、`TCustomImageList`。
  - `CSnapshotTypeRenames`（G6 比对时允许的类型名变化，D11）：`TTyIconFont→TTyCustomIconFont`，Q8 照建议时再加 `TTyStyleController→TTyCustomStyleController`、`TTyImageCollection→TTyCustomImageCollection`、`TTyVirtualImageList→TTyCustomVirtualImageList`。
  - `CChain`（G7，A 下派生控件的期望链）：附录 C-0 的 55 行，每行「最终类、它的 Custom 类的期望父类」（如 `TTyGlyphButton → TTyGlyphButtonBase`、`TTyNumericEdit → TTyCustomEdit`、`TTyStringGrid → TTyCustomDrawGrid`）；再加 5 个中间类的期望父类（`TTyGlyphButtonBase → TTyCustomButton`、`TTyShellTreeLink → TTyCustomTreeView`、`TTyIconPackFont → TTyCustomIconFont`、`TTyCustomTabStrip → TTyCustomControl`、`TTyCustomGrid → TTyCustomControl`）。一行只在它的最终类（或中间类的家族根）进了 `CSplit` 之后生效。
  - `CDemoted`（G8）：Task 0 为空；Task 1 加三个基类，各家族任务加它降级的中间类。

  **G6 `TestPublishedSnapshotUnchanged`（迁移期）**：
  - 总体 = `CollectRegisteredClassNames` 经 `GetClass` 解析的类 ∪ `CStreamOnly` ∪ `CSnapshotInputs` ∪ `CLclRoots`，按类名排序。
  - 每个类先一行头 `# <ClassName> n=<published 属性个数> chain=<父类>,<祖父类>,...,TPersistent`（`ClassParent` 一路往上的类名，逗号分隔，无空格）。
  - 对注册类与 `CStreamOnly` 再一行 `#typekey<Tab><key><Tab><StyleClass><Tab><sub><Tab><size>`（`size` = 新实例是 `TControl` 时 `<Width>x<Height>`，否则 `-`——钉住默认尺寸，它随构造进 Custom 类）：用 `Create(nil)`（`TCustomForm` 后代用 `CreateNew(nil)`）建一个新实例；`key` = `Supports(inst, ITyStyleable, s)` 时 `s.GetStyleTypeKey`，否则 `-`；`StyleClass` = 该类发布了 `StyleClass` 时 `GetStrProp`，否则 `-`；`sub` = 子部件 key，`|` 分隔：`TTyListBox` 一系（在 Task 0 时用 `InheritsFrom(TTyListBox)` 判断，经测试单元的 access 类读 `GetItemStyleTypeKey`；**Task 15 把这个判断与 access 类改成 `TTyCustomListBox`**，N9）、`TTyTreeSelect.StyleTypeKey`、`TTyPopover.StyleTypeKey|TitleStyleTypeKey`、`TTyNotification.StyleTypeKey|CloseStyleTypeKey`，其余 `-`；任一步抛异常记 `x`。
  - 再按 `GetPropList(cls, L)` 的顺序每个属性一行，10 列以 **Tab** 分隔：`Class  Pos  Name  TypeName  Kind  Default  Stored  Index  Access  Fresh`
    - `Pos`：在 `GetPropList` 结果里的下标（0 起）；`TypeName` = `PropType^.Name`；`Kind` = `GetEnumName(TypeInfo(TTypeKind), Ord(Kind))`；`Default` = `PropInfo^.Default` 的十进制；`Stored`：`(PropProcs shr 4) and 3 = ptConst` 时 `StoredProc <> nil` 记 `T`、否则 `F`，其余记 `D`；`Index` = `PropInfo^.Index`；`Access` = `R` / `W` / `RW`。
    - `Fresh`：只对注册类与 `CStreamOnly` 算（其余记 `-`）：同一个新实例，记 `s=<1|0>`（`IsStoredProp`）加 `,d=<eq|ne|->`（Kind 为序数类且 `Default <> Low(LongInt)` 时比较 `GetOrdProp(实例, PI) = Default`，否则 `-`）；抛异常记 `x`。
  - 写模式：`TY_WRITE_GOLDEN=1` 时把输出写进夹具（LF、UTF-8、无 BOM）后通过；`TY_WRITE_GOLDEN_CLASS=<类名>` 只替换那一个类的段（N24）。否则读夹具，两边 CRLF 都换成 LF；**比对范围 = 注册类、`CStreamOnly`、`CLclRoots` 的段（`CSnapshotInputs` 的段不比——它们的变化是本计划的目的，由 G2 / G8 管）**；比对前把夹具行的 `TypeName` 列按 `CSnapshotTypeRenames` 映射；不同则失败信息打印：不同的行数、第一处不同的行号、两边那一行、所在类名。
  - 判据：夹具里 `TTyEdit` 段的 `chain=` 以 `TTyCustomControl,TCustomControl,TWinControl,TControl` 开头、第一行属性是 `Name`、包含 `Text`、`TabStop` 行的 `Default` 为 1、`#typekey` 行的 key 是 `TyEdit`、`size` 不是 `0x0`；`TTyGlyphButton` 的 key 是 `TyButton`、`TTySpeedButton` 的是 `TySpeedButton`；`TTyScrollContent` 段存在；类头个数预计约 190（注册 175 + 1 + 输入 10 + LCL 根 4），以实际为准，签收记下。
  - 变异：M-G6a 对调 `TTyEdit` 发布段相邻两行；M-G6b 删掉 `TTyCustomEdit` 里 `MaxLength` 的 `default 0`；M-G6c 删掉 `TTyCustomTabSheet` 里 `Left` 的 `stored False`（2 期做）；M-G6k 删掉 `TTyCustomSpeedButton` 的 `GetStyleTypeKey` 覆写（1 期做）——都必须红。

  **G1 `TestSplitClassesSitOnTheirCustomClass`**：对 `CSplit` 每个类 `C`：`C.ClassParent.ClassName = 'TTyCustom' + Copy(C.ClassName, 4, MaxInt)`。失败列出全部不符的类。（G5 保证每个注册类不在 `CSplit` 就在 `CNotSplit`；Task 32 删掉 `CPending` 之后，G1 + G5 就是「遍历全部注册类：每个 `TTyXxx` 的直接父类是 `TTyCustomXxx`，例外都写明了理由」。）变异 M-G1：把一个已拆的最终类改回直接继承 Custom 父类（同时保留 Custom 类）→ 红。

  **G2 `TestCustomClassesPublishNothingNew`**：对 `CSplit` 每个类：`Custom := C.ClassParent`；Custom 的 published 名字集合（不区分大小写）= 它的 LCL 根（`ClassParent` 链上第一个不以 `TTy` 开头的类）的 published 名字集合。失败列出「类：多出的名字」。变异 M-G2：在 `TTyCustomEdit` 的 published 段留一行 `property MaxLength ...` → 红。

  **G3 `TestCustomAndFinalAgree`**：~~(a) RTTI：对 `CSplit` 每个类，Custom 发布的每个属性（只会是 LCL 根的 15 个）与最终类同名属性的 `TypeName`、`Default`、`Stored`、`Index`、`Access` 一致。~~ **(a) 第 0、1 期期末修复删除**：最终类只有 `property X;`（(b)）时它原样继承每个说明符，(a) 只可能在 (b) 已经红的地方红，没有哪个变异能单独让它红——它是自证的；说明符写在 Custom 还是最终类里，从第三方那一侧由 G9 查、对 3.0 由 G6 查。(b) **源码**：读 `source/` 下每个单元，找出 `CSplit` 每个类的 `TTyXxx = class(TTyCustomXxx)` 声明块（到 `end;`），去掉注释后每个非空行都必须匹配 `^\s*(published|property\s+\w+\s*;)\s*$`。失败列出「类：违规的行」。变异：M-G3a 把 `TTyCustomTabSheet` 的 `property Left stored False;` 挪到 `TTyTabSheet` → ~~(a) 红（且 G3b 红）~~ G3b 红、G9 红（期末修复后 (a) 不存在）；M-G3b 在 `TTyEdit` 发布段写 `property TabStop default True;`、删掉 Custom 里那行 → (b) 红。

  **G4 `TestFinalClassesAddNoFields`**：对 `CSplit` 每个类：`C.InstanceSize = C.ClassParent.InstanceSize`。变异 M-G4：给 `TTyEdit` 加一个 `FDummy: Integer` 字段 → 红。

  **G5 `TestEveryRegisteredClassIsAccountedFor`**：总体 = 注册类 ∪ `CStreamOnly`（含非可视）。① 每个都恰好在 `CSplit`、`CPending`、`CNotSplit` 之一；② 三者两两不相交；③ `CNotSplit` 和 `CPending` 里的类**没有**被拆（`ClassParent.ClassName` 不是 `'TTyCustom' + …`；`TTyToolWindowManager` 的父类恰好是 `TTyCustomToolWindowManager`，按 Q4 在 ③ 里豁免）；④ `CSplit` 的每个都在总体里。变异 M-G5：拆完一个类却忘了把它挪出 `CPending` → ③ 红。

  **G7 `TestDerivedControlsHangOnTheCustomChain`（A）**：对 `CChain` 里已生效的每一行：① 期望父类对上：最终类行查 `C.ClassParent.ClassParent.ClassName`，中间类行查 `C.ClassParent.ClassName`；② **链上没有注册最终类**：从 `C.ClassParent` 一路往上到 LCL 根，经过的每个类名都不在注册类集合里；③ 正向：`C.InheritsFrom(<期望父类>)`。失败分三类列名字。这条就是「派生控件是其 Custom 父类的子类」与「不再是原父控件的子类」。变异 M-G7：把 `TTyCustomGlyphButton` 改挂回 `TTyButton`（`class(TTyButton)`）→ ①② 红。

  **G8 `TestDemotedClassesPublishOnlyTheLclRoot`（D7 与中间类）**：对 `CDemoted` 每个类：published 名字集合 = 它的 LCL 根的；外加 `TTyCustomControl`、`TTyGraphicControl`、`TTyComponent` 三者在 Task 1 之后恒成立。变异 M-G8：在 `Base.pas` 的 `TTyCustomControl` 里留一行 `published property Enabled;` → 红。

  **G9 `TestGeneratedMimicsMatchTheirFinalClass`（第 0、1 期期末修复加，常驻，不随 Task 32 退役）**：`tests/test.customclasses.mimic.pas` 由 `gen-mimic.py`（见「辅助脚本 `gen-mimic.py`」）从源码生成：对 `CSplit` 每个类 `TTyXxx`，写一个 `TGenXxx = class(TTyCustomXxx)`，发布段逐行照抄 `TTyXxx` 的；常量 `CGenMimics` 列出（模拟类，最终类）对。判据：① 覆盖：`CGenMimics` 的最终类集合 = `CSplit`（少一个就红——每个任务拆完都要重跑生成器），每个模拟类与最终类同父类；② 每对 RTTI 行逐项相同（位置、名字、类型、default、stored、index、读写）；③ 各放在一个新 `TForm.CreateNew` 上（两个窗体，免得 TabOrder 互相影响）的新实例，~~流式文本去掉首行后相同~~ **第 2 期期末修复改**：流式**宿主窗体**、取它写给子组件的那段（去掉首个 `object` 行与窗体的 `end`）后相同——当根流式时控件把自己建、自己拥有的子组件（滚动条、单元格编辑器）也写出来，`.lfm` 从不带它们，其中网格的日期编辑器构造时取 `Now`，八次跑七次红；构造时取自时钟的 `TDateTime` 值（`TTyAnalogClock.Time`）两边钉成同一个值；每对之间 `DestroyComponents` 清掉宿主上的残留（GridPanel 的格归窗体所有，比面板活得长）。核实：101 对里只有 25 个类当根流式时多写了自建子组件，其余逐行与宿主流式一致；GridPanel 反而多比了它归窗体所有的 4 个格；④ typeKey 相同；⑤ 默认尺寸相同；⑥ `CurrentStyle` 解析出的样式相同（背景、文字、边框、圆角、内距、字体、透明度、阴影、外框）。为什么要它：G6 比的是最终类与 3.0，改 default 的重声明写在 Custom 类还是最终类里它都绿；G9 比的是「第三方照抄发布段」与最终类，default / stored / typeKey / 构造值有任何一样只在最终类上，就红——这是审查 M2 / M3（「Custom 类声明的默认值对第三方生效」）在 P1 全绿下漏掉的视角。变异 M-G9：把 `TTyCustomSpeedButton` 的 `property TabStop default False;` 挪进 `TTySpeedButton` → G9 红（G3b 也红，G6 绿）。

  **G10 `TestFreshFormFileTextUnchanged`（第 2 期期末修复加，常驻，不随 Task 32 退役）**：每个注册类（`CNotSplit` 除外：窗体放不到窗体上，AdvChart 分支的类还在别处改）的新实例放在一个新宿主窗体上，取窗体写给它的文本（同 G9 ③），与 `tests/fixtures/customclasses/fresh-streams.txt` 逐类比对；`TY_WRITE_FRESH_STREAMS=1` 重写夹具（只在「窗体文件写什么」正是这次提交要改的东西时，夹具的 diff 就是审查对象）。比对前：时钟值钉住（同 G9）；取自本机的值（`CMachineValues`：已装字体、驱动器数）只留属性行、值换成 `<from the machine>`；**所有字符串值**换成 `<text>`（构造值里的字符串来自资源串、区域设置或本机，全量里先跑的 suite 装过翻译就全变，G9 已在同一次运行里逐个比字符串）。尺寸按 Windows 量，与 G6 的默认尺寸同一类环境依赖。夹具在 G6 全绿时冻结，所以它记的就是 3.0 写的东西（G6 的 `s=` / `d=` 列逐属性比过新实例的 stored 与默认值）。为什么要它：DEFDEL（删 `TTyCustomTabSheet.TabVisible` 的 `default True`）时新 TabSheet 开始写出 `TabVisible = True`，G9 与 P2 全绿（模拟类与最终类一起变），G6 退役后就没人看见了。变异：DEFDEL → G10 红。

- [x] **Step 6: 注册**：`tests/tytests.lpr` uses 末尾加 `test.customclasses`。

- [x] **Step 7: 基线编译、生成夹具、跑全量**：

```bash
cd /d/Projects/ty-split && ls source/*.ppu source/*.o 2>/dev/null | wc -l && lazbuild -B tests/tytests.lpi > /tmp/split-build.txt 2>&1 || { tail -30 /tmp/split-build.txt; false; }; cd tests && cp tytests.exe tytests-split.exe && mkdir -p fixtures/customclasses && TY_WRITE_GOLDEN=1 ./tytests-split.exe --suite=TTyCustomClassesGuardTest --format=plain > /tmp/split-gold-w.txt 2>&1; ./tytests-split.exe --suite=TTyCustomClassesGuardTest --format=plain > /tmp/split-gold.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/split-gold.txt; grep -c "^# " fixtures/customclasses/published-snapshot.txt; grep -c "^#typekey" fixtures/customclasses/published-snapshot.txt; wc -l fixtures/customclasses/published-snapshot.txt; grep -c "	x$" fixtures/customclasses/published-snapshot.txt
```

Expected：编译 0 错；第二次跑 8 条全过；类头个数、typekey 行数（= 注册类 + 1）、`x` 的个数记下（执行中不许变）。然后跑全量，条数与红名单记进草稿。**除已知偶发失败外有别的红就停。**

- [x] **Step 8: 提交**

```bash
cd /d/Projects/ty-split && git add tests/test.customclasses.pas tests/fixtures/customclasses tests/tytests.lpr && git commit -m "test(controls): snapshot every published property and type key before the custom-class split

Issue #8 asks for a TTyCustomXxx parent behind every control, hung the
LCL way (TTyCustomNumericEdit on TTyCustomEdit), with the base classes
publishing nothing and every final class republishing what it had. A
republished property inherits its default and stored clause, but its
position in RTTI -- and so its place in a saved .lfm -- is wherever it
is first published. This fixture holds, for every registered class, the
name, type, default, stored clause, index, access and position of every
published property, plus the style type key a fresh instance reports,
so the split can prove nothing a form file or a theme sees has moved.

Structural guards go in with it and stay after the migration: every
split class sits directly on its custom class, the custom class
publishes nothing beyond the LCL root, the final class is nothing but
property lines and adds no field, derived controls hang on the custom
chain, the demoted bases publish nothing, and every registered class is
either split or listed with a reason.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 1: 基类不再发布（D7）

**Files:** Modify `source/tyControls.Base.pas`、`source/tyControls.Component.pas`（Q2）；每个直接子类所在单元（V18 的清单：窗口化 57 + 图形 28 + `TTyComponent` 20 个注册类、`TTyCustomTabStrip`、`TTyCustomGrid`、`TTyCustomFileDialog`、`TTyScrollContent`、`TTyToolWindowManager`；其中 `AdvanceChart.pas`、`Calendar.pas`、`DateTimePicker.pas` 单独一个提交，Q3）；`tests/test.customclasses.pas`（`CDemoted` 加三个基类）；N30 涉及的测试探针。

- [x] **Step 1: 生成每个类的基类块**：对上面每个类 `python split.py base <Class> > <scratchpad>/base/<Class>.txt 2> <scratchpad>/base/<Class>.merge`。`.merge` 非空的（预计就是附录 A「带说明符的重声明」列里 `TabStop default True / False` 那 40 来个类、TabSheet / ToolWindow 的 `TabOrder / Visible stored False`、ToolWindow / ToolWindowActions 的 `Controller stored False`）：块里那一行换成该类源码里的那条带说明符的声明，并删掉它在原 published 段里的那一行（同一个类里一个名字只能声明一次）。
- [x] **Step 2: 插块**：每个类的 published 段**开头**插入它的块（注释一行：`{ The universal properties the base classes stopped publishing in 4.0 (LCL visibility); RTTI order is the 3.0 order. }`）。没有 published 段的（`TTyScrollContent`）新开一段。中间类 `TTyCustomTabStrip` / `TTyCustomGrid` 插在它们自己的段首（它们在 Task 14 / 18 才降级）；`TTyCustomToolWindowManager` 不发布东西（Q4），块插进 `TTyToolWindowManager`（只有 `Version`）。
- [x] **Step 3: 改基类**：`Base.pas` 两个基类的 published 段整段删掉，其中 `Version`、`StyleClass`、`StyleOverride`、`Controller` 四行移到各自的 public 段（说明注释跟着走；`Visible` / `AutoSize` / 拖放那几段注释讲的是「为什么基类要发布」——改写成一句「4.0: published by every final class, not here (LCL TControl publishes none of these)」放在 public 段那四行上方，旧长注释删掉，内容并进 `docs/subclassing.md` 的历史说明里）。`Component.pas`：`Version` 移到 public（Q2）。**方法、protected 段一个字不动**（V21）。
- [x] **Step 4: 编译、快照、全量**（本任务的例外：后面每个任务都站在它上面）。Expected：G6 全绿（逐项相同、typeKey 相同）；G8 对三个基类绿；全量与 Task 0 基线相同。红了按 N30 处理探针，或回去查块 / 合并。
- [x] **Step 5: 测试**：`test.customclasses.pas` 加 `TestBaseClassesPublishNothing`（就是 G8 对三个基类的实例；单列一条方便签收）与 `TestThirdPartyOnTheBareBaseSeesOnlyTheLclRoot`：一个直接继承 `TTyCustomControl` 的测试类不写 published 段，`GetPropList` 的名字集合 = `TCustomControl` 的 15 个（这条就是不兼容清单第 2 条的现场证明）。
- [x] **Step 6: 提交**（两个）：先 `git add` 三个排除单元单独提交 `refactor(controls): republish the base-class properties on the excluded charts and date controls`（正文写明只插了块、为什么、Q3；结尾 Co-Authored-By）；再提交其余 `refactor(controls): the base classes publish nothing; every control republishes them in the 3.0 order`。【主控执行】把第一个提交号告诉 AdvChart 会话（Q3）。

---

## 第 1 期：输入与显示

**本期新建** `tests/test.customclasses.p1.pas`（suite `TTyCustomClassesP1Test`，Task 2 建；`tests/tytests.lpr` uses 加 `test.customclasses.p1`）。单元头注释说明它装的是「第三方模拟子类」「A 下内置派生控件的类型判断」「为第三方放宽的类型判断」三类测试。

**第三方模拟子类的统一判据**（每个任务列出它的模拟类；名字 `TThirdXxx = class(TTyCustomXxx)`，published 段写任务里点名的 2 个属性；测试单元的 initialization 里 `RegisterClass` 它们）：
- T-a 能建：`TThirdXxx.Create(Form)` 不抛；放到一个 `TForm.CreateNew(nil)` 上。
- T-b 只发布了点名的：`GetPropList(TThirdXxx)` 的名字集合 = LCL 根（`TCustomControl` / `TGraphicControl` / `TComponent`）的名字集合 ∪ 点名的 2 个。
- T-c 流式往返：点名的 2 个设成非默认值，任务里点名的「隐藏属性」经 access 类设成非默认值；`WriteComponent` → `ObjectBinaryToText`：文本里有那 2 个名字、**没有**隐藏属性的名字（`DefineProperties` 写的按 N20 单列）；`ReadComponent` 回来 2 个值相等。
- T-d 主题相同：经 `ITyStyleable` 取 `GetStyleTypeKey`，与同设置的 `TTyXxx` 实例相等；有现成 `RenderTo` 的，同尺寸、同 Caption / 值渲染到白底位图，逐像素相等。
- T-e 默认值站得住：对点名的 2 个属性，新实例的值 = 该属性的 `Default`（有 default 的）或 `IsStoredProp = False`。
- T-v 可见性：点名的隐藏属性在 `TTyCustomXxx` 里的可见性 = 附录 E 定的（用一个与测试单元不同的单元里的引用编译检查做不到，改为：任务里点名一个 D3 定为 public 的属性，测试直接经 `TTyCustomXxx` 类型的变量读写它——编得过就是 public；定为 protected 的走 access 类）。
- 变异：M-T（每期一条代表）：把某个家族的 `GetStyleTypeKey` 从 Custom 挪到最终类 → 该家族模拟子类 T-d 红。

### Task 2: 按钮

**Files:** Modify `source/tyControls.Button.pas`、`GlyphButtons.pas`、`DropButtons.pas`、`ColorButton.pas`、`ButtonGroup.pas`、`ToolBar.pas`（只改附录 C-1 的 A2-1 与 C-4 的 `ApplyToButton`；给 `TTyToolButton` 补发布段）、`ToolBarEx.pas`（A2-2、A2-3）、`examples/toolbar/umain.pas`（A2-4）、`tools/gallery/tyGalleryCapture.pas`（A2-5）、`tests/test.parity.buttons.pas`、`tests/test.parity.pas`（C-4 的隐式向上转型）、`tests/test.customclasses.pas`；Create `tests/test.customclasses.p1.pas`；Modify `tests/tytests.lpr`。

| 类 | 3.0 父类 | 4.0 Custom 父类 | LCL 对应（D3） |
|---|---|---|---|
| TTyButton | TTyCustomControl | TTyCustomControl | `TCustomButton`（public） |
| TTyDropDownButton | TTyButton | **TTyCustomButton** | `TCustomButton` |
| TTyMenuButton | TTyButton | **TTyCustomButton** | `TCustomButton` |
| TTyColorButton | TTyButton | **TTyCustomButton** | `TColorButton` 的父类 `TCustomSpeedButton`（public） |
| （中间类）TTyGlyphButtonBase | TTyButton | 改挂 **TTyCustomButton**、降级（Q1） | `TCustomBitBtn`（public） |
| TTyGlyphButton | TTyGlyphButtonBase | TTyGlyphButtonBase | `TCustomBitBtn` |
| TTyGlyphContainerButton | TTyGlyphButtonBase | TTyGlyphButtonBase | `TCustomBitBtn` |
| TTySpeedButton | TTyGlyphButtonBase | TTyGlyphButtonBase | `TCustomSpeedButton` |
| TTyButtonGroup | TTyCustomControl | TTyCustomControl | 无（public） |

- [x] **Step 1: 拆（父先子后）**：`TTyButton` → `TTyDropDownButton`、`TTyMenuButton`、`TTyColorButton`（`R2s` 预计有 ColorButton 的 `Alignment default taLeftJustify`）→ `TTyGlyphButtonBase`：类头改 `class(TTyCustomButton)`，published 段按 R2 / R3 / D3 降级（它的 11 个属性变成 Custom 层的声明），**同一任务里**给它的 4 个注册后代补发布段：GlyphButton、GlyphContainerButton、SpeedButton 随拆分生成，`TTyToolButton`（ToolBar.pas，3 期才拆；它仍是 `class(TTyGlyphButtonBase)`）的 published 段按快照顺序（`split.py block TTyToolButton` 输出的顺序）写全部名字：**它自己带类型声明过的名字（`Style`、`Grouped`、`Wrap`……）在原位置保留原声明**，从中间类 / 基类继承来的写成 `property X;`；stderr 里 `R2s` 列出的 `TabStop`、`GlyphLayout` 两个名字同理用它源码里原来带说明符的写法（`property TabStop default False;`、`property GlyphLayout stored FGlyphLayoutExplicit nodefault;`——同 Task 1 的合并，一个名字只声明一次；3 期拆它时这些带类型、带说明符的声明按 R2 挪进 `TTyCustomToolButton`）。~~此刻只取 `property X;` 行替换现有 published 段的全部内容~~（期末修复改正：那样会删掉它自己的声明；实际就是按上面做的）；G6 确认位置与说明符都没动→ GlyphButton、GlyphContainerButton（`R2s` 有 `GlyphLayout default glTop`）、SpeedButton（`R2s` 有 `TabStop default False`）→ ButtonGroup。`TTyRibbonAppMenu`（`class(TTyMenuButton)`，3 期）与 `TTyTransferArrowButton`（内部）不受影响。`CDemoted` 加 `TTyGlyphButtonBase`。
- [x] **Step 2: A 下必改**（附录 C-1）：A2-1 `ToolBar.pas:1838`（`is TTyButton` + 强转，扁平样式）→ `TTyCustomButton`，同时 `ApplyToButton(B: TTyButton)`（`:416/1713`）参数放宽到 `TTyCustomButton`（C-4；读写 protected 属性用 access 类）；A2-2 `ToolBarEx.pas:236/248-253`、A2-3 `ToolBarEx.pas:393-396/445-446`（溢出弹层包装 OnClick）→ `TTyCustomButton`（`OnClick` 在 LCL 是 public，直接用）；A2-4 `examples/toolbar/umain.pas:162` `ToolClicked`：`(Sender as TTyButton).Caption` → `(Sender as TTyCustomButton).Caption`（它挂在 13 个 TTyButton、4 个 TTyToolButton、3 个 TTyGlyphButton 上）；`:172` `ToolToggle` 只挂在 TTyButton 上、要读写 `Down`——保持 `as TTyButton`（C-3，「恰好这个类」）；A2-5 `tools/gallery/tyGalleryCapture.pas:157`（按标题在示例窗体上找按钮，示例里有 GlyphButton）→ `TTyCustomButton`。C-4：`tests/test.parity.buttons.pas:500/562/1293/1314/1328/1343/1364`、`tests/test.parity.pas:321/769/783/1296/1538` 的 `B: TTyButton := TTyGlyphButton / TTyColorButton / TTySpeedButton.Create(...)` → 声明改 `TTyCustomButton`（读写 protected 的属性就强转回那个最终类——对象就是它，是真话）。
- [x] **Step 3: 为第三方放宽**（附录 C-2）：C1-1（GlyphButtons 同组互斥 `is TTySpeedButton`，`:962/987/1008-1010`）→ `TTyCustomSpeedButton`。
- [x] **Step 4: 测试**（`test.customclasses.p1.pas`）：
  - S2-1：`Flat = True` 的 `TTyToolBar` 上放一个 `TTyGlyphButton`、一个 `TTySpeedButton`，手调一次布局（N26），两者 `StyleClass = 'ghost'`。**把 A2-1 改回 `is TTyButton` 必须红。**
  - S2-2：同 S2-1，换成 `TTyToolBarEx`。**A2-2 改回必须红。**
  - S2-3：`TTyToolBarEx` 溢出时，弹层里的 `TTyGlyphButton` 被点击后宿主收到 `PopupItemClick`、关闭弹层后原 `OnClick` 还原。**A2-3 改回必须红**；溢出弹层无头驱动不到就写「—：与 S2-2 同一判断，审查覆盖」。
  - S2-4：`TTyToolButton` 发布段没动——由 G6 覆盖（变异：把它块里两行对调 → G6 红）。
  - A2-4 / A2-5：「—：示例与工具无测试」；【主控执行】冒烟时在 toolbar 示例里点一个 GlyphButton 与一个 ToolButton，状态栏显示标题、不弹异常（列进 Task 11 Step 4）。
  - S1-1：同一父控件上一个 `TTySpeedButton` 和一个 `TThirdSpeedButton`，`GroupIndex = 1`：按下一个，另一个弹起；两个方向。C1-1 改回 → 红。
  - 模拟类：`TThirdButton`（发布 `Caption`、`Down`；隐藏 `ModalResult`）、`TThirdSpeedButton`（发布 `GroupIndex`、`Down`；隐藏 `AllowAllUp`）；T-a…T-e、T-v。
  - G7 生效的几行：`TTyDropDownButton`、`TTyMenuButton`、`TTyColorButton` → `TTyCustomButton`；`TTyGlyphButtonBase` → `TTyCustomButton`；三个 glyph 按钮 → `TTyGlyphButtonBase`。
- [x] **Step 5: `CPending` → `CSplit`**：上表 8 个类。
- [x] **Step 6: 提交**：`refactor(controls): split the button family into TTyCustomXxx and a published TTyXxx`（正文：A 的链、为什么工具栏与示例的判断跟着改、`TTyToolButton` 先补了发布段；结尾 Co-Authored-By）。

### Task 3: 标签

**Files:** `source/tyControls.TyLabel.pas`、`HtmlLabel.pas`、`LinkLabel.pas`、`ShadowLabel.pas`、`GlowLabel.pas`、`Tag.pas`、`Badge.pas`、测试单元。

全部 Custom 父类 = 原父类（`TTyHtmlLabel` 是 `TTyCustomControl`，其余 `TTyGraphicControl`）。LCL 对应：`TCustomLabel`（`stdctrls.pp:1556`，独有属性 **protected**）给 TyLabel、HtmlLabel、LinkLabel、ShadowLabel、GlowLabel；Tag、Badge 无对应（public）。无附录 C 条目。`TTyLabel` 是主题锁定的（仓库记忆），画法全在 Custom 里。

- [x] **Step 1: 拆** 7 个类。
- [x] **Step 2: 测试**：`TThirdLabel`（发布 `Caption`、`WordWrap`；隐藏 `Layout`）、`TThirdTag`（发布 `Caption`、`Closable`；隐藏属性从附录 A 该类新发布的非事件属性里挑）；T-a…T-e、T-v，`TTyLabel` 走 `RenderTo` 逐像素。
- [x] **Step 3: `CPending` → `CSplit`**、提交 `refactor(controls): split the label family ...`。

### Task 4: 编辑框 I

**Files:** `source/tyControls.Edit.pas`、`NumericEdit.pas`、`CurrencyEdit.pas`、`MaskEdit.pas`、`URLEdit.pas`、`ComboEdit.pas`、`TrackEdit.pas`、`CalcEdit.pas`、`CalcCurrencyEdit.pas`、`examples/grid/umain.pas`（A4-2）、`tests/test.calcedit.pas`（A4-1）、测试单元。

| 类 | 3.0 父类 | 4.0 Custom 父类 | LCL 对应 |
|---|---|---|---|
| TTyEdit | TTyCustomControl | TTyCustomControl | `TCustomEdit`（public） |
| TTyNumericEdit | TTyEdit | **TTyCustomEdit** | `TCustomFloatSpinEdit`（同义：Value / MinValue / MaxValue / DecimalPlaces；public） |
| TTyCurrencyEdit | TTyNumericEdit | **TTyCustomNumericEdit** | 同上 |
| TTyTrackEdit | TTyNumericEdit | **TTyCustomNumericEdit** | 同上 |
| TTyCalcEdit | TTyNumericEdit | **TTyCustomNumericEdit** | `TCalcEdit` 的父类 `TCustomEditButton`（`editbtn.pas:63`，protected）——它 0 个新属性，只影响继承来的名字：照 `TCustomFloatSpinEdit` |
| TTyCalcCurrencyEdit | TTyCurrencyEdit | **TTyCustomCurrencyEdit** | 同上 |
| TTyMaskEdit | TTyEdit | **TTyCustomEdit** | `TCustomMaskEdit`（`maskedit.pp:206`，独有属性 protected 5 / public 4 → protected） |
| TTyURLEdit | TTyEdit | **TTyCustomEdit** | `TCustomEdit` |
| TTyComboEdit | TTyEdit | **TTyCustomEdit** | `TCustomEditButton`（protected） |

- [x] **Step 1: 拆**：Edit → NumericEdit → Currency / Track / Calc → CalcCurrency；Mask / URL / ComboEdit。`TTyEdit` 的接口列表 `ITyTextEditActions, ITyImeEditable` 写在 `TTyCustomEdit` 类头上（R1）。`TTyMaskEdit` 的 `Text write SetMaskedText` 是 `R2s`（原来在 R3，A + D7 下 Text 不是 LCL 根已 published 的），带着它上面那段「静态绑定」注释放 `TTyCustomMaskEdit`，可见性照 `TCustomMaskEdit` 的 Text（`split.py vis TCustomMaskEdit Text`）。`TTyValueEdit`（内部）不动。
- [x] **Step 2: A 下必改**：A4-1 `tests/test.calcedit.pas:40/60`：原断言 `e is TTyNumericEdit` / `e is TTyCurrencyEdit`（e 是 CalcEdit / CalcCurrencyEdit）A 下变假——改写成两句：`e is TTyCustomNumericEdit`（「仍是数值编辑框一族」）与 `not (e is TTyNumericEdit)`（「4.0 起不再是 TTyNumericEdit 的后代——LCL 式继承链」，注释写明这是有意的不兼容变化、见计划清单第 1 条）；货币那条同理（`TTyCustomCurrencyEdit` / `not ... TTyCurrencyEdit`）。这两句本身就是层级的钉子：**把 `TTyCustomCalcEdit` 改挂回 `TTyNumericEdit`，第二句必须红**（G7 也红）。A4-2 `examples/grid/umain.pas:1332-1334`：网格的格编辑器有 `TTyCalcEdit`、`TTyMaskEdit`（`Grid.pas:8024/8031`），`AEditor is TTyEdit` A 下认不出它们 → `TTyCustomEdit`，`Font` 是 LCL public，直接 `TTyCustomEdit(AEditor).Font.Color`。「—：示例无测试」，【主控】冒烟时在 grid 示例打开一个计算列，编辑器字体为红（列进 Task 11）。C-4：`CalcEdit.pas:16/22/78` `TTyCalcDropdown` 的 `FEdit` / `Create(AEdit: TTyNumericEdit)`——两个 calc 编辑框都把 `Self` 传进来，A 下 `Self` 不是 `TTyNumericEdit` → 放宽到 `TTyCustomNumericEdit`（内部类）。
- [x] **Step 3: 测试**：`TThirdEdit`（发布 `Text`、`ReadOnly`；隐藏 `MaxLength`）；T-a…T-e、T-v，T-f：`Supports(TThirdEdit 实例, ITyImeEditable)` 与 `ITyTextEditActions` 都为 True（变异：接口列表挪到 `TTyEdit` 类头 → 红）。`TThirdMaskEdit`（发布 `EditMask`、`Text`；隐藏 `SpaceChar`）：经 `Text` 赋值走带掩码的 setter（与 `TTyMaskEdit` 同输入同输出；变异：把 `Text write SetMaskedText` 从 Custom 挪到最终类 → 红）。S4-1：`TTyCalcEdit` 下拉计算器打开、算完回写到编辑框（经 `TTyCalcDropdown` 的放宽参数）——C-4 是编译期的，这条只证明行为没变。
- [x] **Step 4: `CPending` → `CSplit`**、提交。

### Task 5: 编辑框 II

**Files:** `source/tyControls.Calculator.pas`、`Memo.pas`、`SpinEdit.pas`、`FloatSpinEdit.pas`、`UpDown.pas`、测试单元。

| 类 | 3.0 父类 | 4.0 Custom 父类 | LCL 对应 |
|---|---|---|---|
| TTyCalculator | TTyCustomControl | TTyCustomControl | 无（public） |
| TTyMemo | TTyCustomControl | TTyCustomControl | `TCustomMemo`（`stdctrls.pp:902`，public） |
| TTySpinEdit | TTyCustomControl | TTyCustomControl | `TCustomSpinEdit`（`spin.pp:146`，public） |
| TTyFloatSpinEdit | TTyNumericEdit | **TTyCustomNumericEdit**（Task 4 已有） | `TCustomFloatSpinEdit`（`spin.pp:33`，public） |
| TTyUpDown | TTyGraphicControl | TTyGraphicControl | `TCustomUpDown`（`comctrls.pp:1922`，独有属性 **protected**） |

- [x] **Step 1: 拆**；FloatSpinEdit 的 `UseThousands default False` 是 `R2s`（原来 R3），放 `TTyCustomFloatSpinEdit`。
- [x] **Step 2: 为第三方放宽**：C4-1（UpDown 关联互斥）→ `TTyCustomUpDown`。
- [x] **Step 3: 测试**：`TThirdMemo`（发布 `Lines`、`ReadOnly`；隐藏 `WantTabs`）、`TThirdUpDown`（发布 `Associate`、`Position`；隐藏 `Increment`）；T-a…T-e、T-v。S4-2：同一父控件上 `TTyUpDown` 已关联某个编辑框，`TThirdUpDown` 再关联同一个 → 抛异常；反过来也一样。C4-1 改回 → 红。`TTyFloatSpinEdit` 的 `UseThousands` default：新实例 `UseThousands = False` 且 RTTI default = 0（先证明 `TTyNumericEdit` 的是 1）；变异：把那行从 Custom 挪到最终类 → G3b 红。
- [x] **Step 4: `CPending` → `CSplit`**、提交。

### Task 6: 选择

**Files:** `source/tyControls.CheckBox.pas`（CheckBox + RadioButton）、`ToggleSwitch.pas`、`Segmented.pas`、测试单元。四个类 Custom 父类 = `TTyCustomControl`；LCL 对应 `TCustomCheckBox`（`stdctrls.pp:1326`，public）给前三个，Segmented 无（public）。`TabStop default True` 都是 `R2s` → Custom 的 public 段（LCL `TWinControl.TabStop` 是 public）。

- [x] **Step 1: 拆**：CheckBox.pas 两个类分两次 `impl`；确认 `a0606352` 的 AutoSize 改动随 R1 进了 Custom。
- [x] **Step 2: 类型判断**：C5-1 放宽（单选同组互斥 → `TTyCustomRadioButton`）；C5-2 保持（RadioGroup 的 Sender 只会是它自己建的 `TTyRadioButton`）。
- [x] **Step 3: 测试**：`TThirdCheckBox`（发布 `Checked`、`Caption`；隐藏 `AllowGrayed`）、`TThirdRadioButton`（发布 `Checked`、`GroupIndex`）；T-a…T-e、T-v。S5-1：同一父控件、同 `GroupIndex` 的 `TTyRadioButton` 与 `TThirdRadioButton`，勾一个另一个取消，两个方向。C5-1 改回 → 红。
- [x] **Step 4: `CPending` → `CSplit`**、提交。

### Task 7: 组合框 I

**Files:** `source/tyControls.ComboBox.pas`、`MRUComboBox.pas`、`ComboBoxEx.pas`、`OfficeComboBox.pas`、`AdvancedComboBox.pas`、`CheckComboBox.pas`、`tests/test.parity.combo.pas`（C-4）、`tools/gallery/tyGalleryCapture.pas`（C-3 核对）、测试单元。

| 类 | 3.0 父类 | 4.0 Custom 父类 | LCL 对应 |
|---|---|---|---|
| TTyComboBox | TTyCustomControl | TTyCustomControl | `TCustomComboBox`（`stdctrls.pp:289`，public 22 / protected 12 → public） |
| TTyMRUComboBox | TTyComboBox | **TTyCustomComboBox** | `TCustomComboBox` |
| TTyComboBoxEx | TTyComboBox | **TTyCustomComboBox** | `TCustomComboBoxEx`（`comboex.pas:136`，public） |
| TTyOfficeComboBox | TTyComboBox | **TTyCustomComboBox** | `TCustomComboBox` |
| TTyAdvancedComboBox | TTyComboBox | **TTyCustomComboBox** | `TCustomComboBox` |
| TTyCheckComboBox | TTyComboBox | **TTyCustomComboBox** | `TCustomCheckCombo`（`comboex.pas:271`，public） |

- [x] **Step 1: 拆**：`TTyComboPopupList` 及其子类（内部）不动。弹层 API 的 `TTyListBox` 本任务**不动**（`TTyCustomListBox` 还不存在；Task 15 放宽，V12）。
- [x] **Step 2: A 下必改**：A7-1 `ComboBox.pas:565-569` `TyComboOwnerOf`：弹层的 `Owner is TTyComboBox`——A 下 5 个派生组合框（本任务）与 6 个（Task 8）全部认不出，弹层的行自绘 / 量行高全断 → `TTyCustomComboBox`，返回类型一起放宽（implementation 私有），调用处 `:575/583/590/597` 随之；`BeginRowOwnerDraw` 等若是 protected，用 access 类。C-4：`tests/test.parity.combo.pas` 的 `c: TTyComboBox := TTyComboBoxEx / TTyCheckComboBox / TTyColorBox / ... .Create`（`:443/461/484/500/512/534/553/574/875/1598/1734-1738/1754/1778-1784/2006`，27 处）→ 声明 `TTyCustomComboBox`；`PopulateForFamily(C: TTyComboBox)`（`:1638`）参数 → `TTyCustomComboBox`，其中 `C is TTyColorBox`（`:1647`，C 可能是 `TTyColorComboBox`）属 Task 8 的 A8-2。`tests/test.parity.pas:490/506` 的 `C: TTyComboBox := TTyColorBox.Create` 在 Task 8 改（ColorBox 那时才改挂；此刻 ColorBox 仍是 `TTyComboBox` 的后代，编得过）。
- [x] **Step 3: 为第三方放宽**：C6-2（ComboBoxEx 的 ItemsEx 所有者 ×3）、C6-3（AdvancedComboBox 弹层取 Images）、C6-4（CheckComboBox 弹层所有者）→ 各自的 Custom 类；C6-5（`is TTyCheckListBox` ×3，弹层是自己建的）保持——**Task 15 复核**：`TTyCheckComboPopupList` 仍从 `TTyCheckListBox` 派生，保持成立。
- [x] **Step 4: 测试**：S7-1：`TTyComboBoxEx`（内置派生）设 owner-draw 风格 + 行绘制事件，建它的弹层列表画一行，事件被调用。**把 A7-1 改回 `Owner is TTyComboBox` 必须红**（先证明事件确实只经 `TyComboOwnerOf` 这条路到达）。S7-2：`TThirdComboBoxEx = class(TTyCustomComboBoxEx)` 发布 `ItemsEx`、`Images`，往 `ItemsEx` 加一项，`Items.Count` 跟着变。C6-2 的 `Update` 那一处改回 → 红。C6-3、C6-4：能观察就写，驱动不到写「—」与理由。模拟类 `TThirdComboBox`（发布 `Items`、`ItemIndex`；隐藏 `DropDownCount`）；T-a…T-e、T-v。
- [x] **Step 5: `CPending` → `CSplit`**、提交。

### Task 8: 组合框 II，属性编辑器第一次挪到 Custom 类

**Files:** `source/tyControls.ColorBox.pas`、`ColorComboBox.pas`、`FontComboBox.pas`、`FontSizeComboBox.pas`、`FilterComboBox.pas`、`ShellComboBox.pas`、`designtime/tyControls.Design.PropEditors.pas`（:765、:770）、`tests/test.designeditors.pas`、`tests/test.colorbox.pas`（A8-3）、`tests/test.parity.combo.pas`（A8-2）、`tests/test.parity.pas`（C-4）、测试单元。

| 类 | 3.0 父类 | 4.0 Custom 父类 | LCL 对应 |
|---|---|---|---|
| TTyColorBox | TTyComboBox | **TTyCustomComboBox** | `TCustomColorBox`（`colorbox.pas:46`，public） |
| TTyColorComboBox | TTyColorBox | **TTyCustomColorBox** | `TCustomColorBox` |
| TTyFontComboBox / TTyFontSizeComboBox / TTyShellComboBox | TTyComboBox | **TTyCustomComboBox** | `TCustomComboBox` |
| TTyFilterComboBox | TTyComboBox | **TTyCustomComboBox** | `TCustomFilterComboBox`（`filectrl.pp:147`，public） |

- [x] **Step 1: 拆**：`TTyColorBox` 的 `Style: TTyColorBoxStyle read FPaletteStyle write SetPaletteStyle ...`（同名换类型）是 `R2s`，整条原样放 `TTyCustomColorBox`，可见性照 `TCustomColorBox.Style`（public）。`RegisterClass(TTyFilterComboBox)` 保持。`TTyFilterComboBox.ConvertFilterToStrings`（class procedure）随 R1 进 Custom。
- [x] **Step 2: A 下必改**：A8-1 `ColorBox.pas:468-470`（弹层 `Owner is TTyColorBox` 取色块几何与伪行颜色）——~~A 下 `TTyColorComboBox` 认不出，下拉画回原始哨兵色、忽略 `ColorRectWidth`~~（执行中核实：`TTyColorComboBox` 的下拉是它自己的 `TTyColorMorePopupList`，从不走这条判断，不是翻转；放宽是为了第三方 `TTyCustomColorBox` 子类，已归 C-2）→ `TTyCustomColorBox`（`SwatchColorFor`、`EffectiveRectWidth` 若 protected 用 access 类）。A8-2 `tests/test.parity.combo.pas:1647-1651` `C is TTyColorBox`（`PopulateForFamily` 对 `TTyColorComboBox` 也要填色）→ `TTyCustomColorBox`，`AddColor` 照 D3 可见性访问。A8-3 `tests/test.colorbox.pas:97-99` `TTyComboBox(c).Style`（经祖先拿组合框的下拉模式）A 下是对内置控件的类型假话 → `TTyCustomComboBox(c).Style`（`TCustomComboBox.Style` 是 public；ColorBox 的 `Style` 在 `TTyCustomColorBox` 里换了类型，经 `TTyCustomComboBox` 类型拿到的是组合框那个）；源码注释 `ColorBox.pas:179/503` 的 `TTyComboBox(Box).Style` 一并改成 `TTyCustomComboBox(Box).Style`（N27）。C-4：`tests/test.parity.pas:490/506` 声明 → `TTyCustomComboBox`。
- [x] **Step 3: 为第三方放宽**：C7-2（ShellComboBox 弹层所有者）→ `TTyCustomShellComboBox`。
- [x] **Step 4: 设计期**（R8）：`PropEditors.pas:765` `TTyFilterComboBox` → `TTyCustomFilterComboBox`；`:770` `TTyShellComboBox` → `TTyCustomShellComboBox`。`tests/test.designeditors.pas`：`TestEveryRegistrationTargetsARealProperty` 改成 R8 的规则（失败消息里说明两种合法情形）——基类上的 `StyleClass` / `StyleOverride` / `Version` 注册（Task 1 之后基类不发布了）、`TTyGlyphButtonBase.GlyphName`（Task 2 之后不发布了）也靠新规则的第二种情形通过；`RegisterClasses` 块加两个 Custom 类。
- [x] **Step 5: 测试**：S8-1：~~`TTyColorComboBox`~~ 第三方模拟类 `TThirdColorBox`（执行时改：`TTyColorComboBox` 不走这条路，见 Step 2）设一个非默认 `ColorRectWidth`，弹层画一行，色块宽度用的是它的值（两个不同宽度画出的行不同）。**A8-1 改回必须红。** A8-2：`test.parity.combo` 里依赖 `PopulateForFamily` 的那条对 `TTyColorComboBox` 的断言——**A8-2 改回必须红**（若那条断言对空列表也成立，先补强：断言填色后行数 = 3）。A8-3 是硬转、无运行时差异：「—：类型假话，审查覆盖」。模拟类 `TThirdColorBox`（发布 `Selected`、`Style`；隐藏 `ColorRectWidth`）、`TThirdShellComboBox`（发布 `Directory`、`Items`）；T-a…T-e、T-v。S8-2：ShellComboBox 弹层能观察就写，否则「—」。
- [x] **Step 6: `CPending` → `CSplit`**、提交（正文提一句 test.designeditors 的新规则）。

### Task 9: 进度与指示

**Files:** `source/tyControls.ProgressBar.pas`、`Gauge.pas`、`Meter.pas`、`LevelMeter.pas`、`CircularProgress.pas`、`ActivityIndicator.pas`、`ActivityBar.pas`、`GearActivityIndicator.pas`、`Sparkline.pas`、测试单元。9 个类 Custom 父类 = `TTyGraphicControl`；LCL 对应：ProgressBar、Gauge、Meter、LevelMeter、CircularProgress ↔ `TCustomProgressBar`（`comctrls.pp:1814`，public；同义：Value ↔ Position）；其余无（public）。无附录 C 条目。

- [x] **Step 1: 拆** 9 个类。
- [x] **Step 2: 测试**：`TThirdProgressBar`（发布 `Position`、`Max`；隐藏 `Step`）——T-c 额外断言：`Max = 50, Position = 40` 写出的文本里 `Max` 在 `Position` 前面（第三方自己的发布顺序决定，V5-7）；`TThirdGauge`（发布 `Value`、`Max`）；T-a…T-e、T-v。
- [x] **Step 3: `CPending` → `CSplit`**、提交。

### Task 10: 旋钮与滑块

**Files:** `source/tyControls.Rating.pas`、`Dial.pas`、`GearDial.pas`、`AnalogClock.pas`、`TrackBar.pas`、测试单元。`TTyRating`、`TTyDial`、`TTyGearDial`、`TTyTrackBar` 父类 `TTyCustomControl`；`TTyAnalogClock` 父类 `TTyGraphicControl`。LCL 对应：TrackBar ↔ `TCustomTrackBar`（异例，Q6：public）；其余无（public）。

- [x] **Step 1: 拆** 5 个类。
- [x] **Step 2: 测试**：`TThirdTrackBar`（发布 `Position`、`Max`；隐藏 `TickMarks`）；T-a…T-e、T-v；T-e 特别验 `TabStop`：`TThirdTrackBar` 新实例 `TabStop = True`，且一个发布 `TabStop` 的第三方子类 `GetPropInfo(...,'TabStop')^.Default = 1`（先证明 `TCustomControl` 的是 0）。变异：把 `TTyCustomTrackBar` 的 `TabStop default True` 挪进 `TTyTrackBar` → 这条红（G3b 也红）。
- [x] **Step 3: `CPending` → `CSplit`**、提交。

### Task 11: 1 期收尾——编译、全量、集中变异、主控编包冒烟、审查、签收

- [x] **Step 1: 一次编译 + 本期 suite + 全量**。Expected：守卫与 P1 suite 全 0 / 0；全量 errors / failures 与 Task 1 后相同、总数 = 基线 + 本期新增。红了集中修：拆错的以快照与 G1–G8 为准；修复提交 `fix(controls): ...`，一个问题一个提交。编译器报出的、附录 C 没列的类型错误：按规则改并补进附录 C（签收列出）。
- [x] **Step 2: 结构核对（不看测试）**：本期 59 个类逐个看源码：最终类只有 `property X;`（R0）；Custom 类头带着原接口列表；R3 的行在 Custom 的 published 段；`R2s` 的行在 Custom 里、可见性照 D3（每类抽 5 个跑 `split.py vis`）；`git diff <Task 1 HEAD>..HEAD -- source | grep -E "^[-+]\s+T\w+ = class\("` 里每个改了父类的都在附录 C-0；没有新增的 `RegisterClass`；`split.py check` 对本期每个改过的文件都 ok；附录 C-1 本期的每一行都落实了。
- [x] **Step 3: 集中变异**：M-G1、M-G2、M-G3a（用 TabSheet 前先用本期的 `TTyCustomMaskEdit` 若有 R3 行，否则留到 2 期）、M-G3b、M-G4、M-G5、M-G6a、M-G6b、M-G6k、M-G7、M-G8、M-T（Button 家族）、M-D1、M-D2，以及本期 S / A 条目的变异（S2-1、S2-2、S2-3、S1-1、A4-1、S4-2、S5-1、S7-1、S7-2、S8-1、A8-2，加上实际写了的其它）。逐条记「红 / 补强 / 等价」。
- [ ] **Step 4: 【主控执行】编包、编全部示例、冒烟**

```bash
cd /d/Projects/ty-split && lazbuild -B tycontrols.lpk > /tmp/split-pkg.txt 2>&1; tail -3 /tmp/split-pkg.txt; lazbuild -B tycontrols_dt.lpk > /tmp/split-dt.txt 2>&1; tail -3 /tmp/split-dt.txt; for p in examples/*/*.lpi; do lazbuild -B "$p" > /tmp/split-ex.txt 2>&1 || echo "FAIL $p"; done; python scripts/check-lfm-props.py; powershell -File scripts/smoke-launch-examples.ps1; git status --short
```

Expected：两个包编过；没有 `FAIL`；两个脚本都过；`git status` 干净。另手点两处：toolbar 示例里点一个 GlyphButton、一个 ToolButton（A2-4），grid 示例打开计算列编辑器字体为红（A4-2）。编包会改机器级包注册，主控决定用不用私有 `--pcp`。
- [ ] **Step 5: 期末审查（主控派两个审查 agent）**：规格核对（R0–R10、D3 抽查、附录 C 对本期的每一行）与代码质量（`git diff <Task 0 的 HEAD>..HEAD`）。重点：R2 / R3 / D3 分拣（N16）、C-1 每处都有测试或理由、没有动共享文件与排除单元（Task 1 的插块除外）。审出来的问题修完回到 Step 1。
- [x] **Step 6: 签收写进本计划末尾，提交**：全量条数（基线 → 签收）、提交区间、本期 suite 条数、变异结果、R7 新增的签名（补进附录 D）、附录 C 新增行、计划外发现。【主控执行】通知「3.0 问题修复」会话：本期已拆的单元清单与移植规矩（N10）。

```bash
cd /d/Projects/ty-split && git add docs/superpowers/plans/2026-10-02-custom-classes.md && git commit -m "docs(controls): custom-class split phase 1 sign-off

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 第 2 期：容器、列表与表格

**本期新建** `tests/test.customclasses.p2.pas`（suite `TTyCustomClassesP2Test`，Task 12 建）。判据同 1 期（T-a…T-e、T-v）。

### Task 12: 面板（含格子与视口）

**Files:** `source/tyControls.Panel.pas`、`PaintPanel.pas`、`ExPanel.pas`、`GridPanel.pas`（GridPanel + GridCell）、`RelativePanel.pas`、`ScrollBox.pas`、`ScrollPanel.pas`、`ScrollContent.pas`、`ControlBar.pas`、`CoolBar.pas`、测试单元。

| 类 | 3.0 父类 | 4.0 Custom 父类 | LCL 对应 |
|---|---|---|---|
| TTyPanel | TTyCustomControl | TTyCustomControl | `TCustomPanel`（`extctrls.pp:1123`，public） |
| TTyPaintPanel / TTyExPanel / TTyGridPanel / TTyRelativePanel | TTyPanel | **TTyCustomPanel** | `TCustomPanel` |
| TTyScrollBox | TTyPanel | **TTyCustomPanel** | `TScrollingWinControl`（`forms.pp:168`；HorzScrollBar / VertScrollBar 在那里 published，其余 public） |
| TTyScrollPanel | TTyScrollBox | **TTyCustomScrollBox** | 同上 |
| TTyControlBar | TTyPanel | **TTyCustomPanel** | `TCustomControlBar`（`extctrls.pp:1571`，public） |
| TTyCoolBar | TTyControlBar | **TTyCustomControlBar** | `TCustomCoolBar`（`comctrls.pp:2556`，public） |
| TTyGridCell | TTyCustomControl | TTyCustomControl | 无（public）；D4–D6 改为拆 |
| TTyScrollContent | TTyCustomControl | TTyCustomControl | 无（public）；V19 |

- [x] **Step 1: 拆** 11 个类（父先子后）。`RegisterClass(TTyControlBar / TTyCoolBar / TTyGridCell / TTyScrollContent)` 保持。`TTyScrollContent` 也在 `CPending` 里（Task 0 的 156 个含它），照常挪进 `CSplit`；它同时留在 `CStreamOnly`（G5 / G6 的总体靠这个清单把它带进来）。
- [x] **Step 2: A 下**：本家族库内无「必改」判断（`is TTyPanel` 0 处，附录 C-1）；编译器若报，按规则改并补进附录 C。
- [x] **Step 3: 为第三方放宽**：C11-1（GridPanel 的格认父 `AParent is TTyGridPanel`）→ `TTyCustomGridPanel`；C11-2（CoolBar 的 bands 集合取所有者）→ `TTyCustomCoolBar`；C11-3（`GridPanel.pas:566` 的 `is TTyGridCell`，格的归属）→ `TTyCustomGridCell`（原 D5「不拆」改为拆）；C12-1 `ScrollBox.pas:366` `AControl is TTyScrollContent`（盒子认视口）→ `TTyCustomScrollContent`。
- [x] **Step 4: 测试**：`TThirdPanel`（发布 `Caption`、`Alignment`；隐藏 `WordWrap`）、`TThirdGridPanel = class(TTyCustomGridPanel)`（发布 `ColumnCount`、`RowCount`）；T-a…T-e、T-v。S12-1：`TTyGridCell` 的 Parent 设成 `TThirdGridPanel`，格子被它接管（手调对齐）；C11-1 改回 → 红。S12-2：`TThirdScrollContent` 放进 `TTyScrollBox`，盒子把它当视口（`ContentHost` 返回它）；C12-1 改回 → 红。S12-3：`TThirdCoolBar` 的 `Bands.Add` 之后宿主重排（能观察就写，否则「—」；执行时：经 Custom 引用挂 `OnChange`，改一个 band 的 `Break` 后宿主收到通知——走的就是 `OwnerBar` → `BandsChanged`）。`TTyScrollContent` 的流式：`examples/containers/umain.lfm` 那种 `object SbView: TTyScrollContent` 带 Left / Height / Top / Width 与子控件的文本，`ReadComponent` 读得回来（这条也是 Task 1 的回归钉子：D7 后它要靠自己的发布段）。
- [x] **Step 5: `CPending` → `CSplit`**、提交。

### Task 13: 分组与装饰

**Files:** `source/tyControls.GroupBox.pas`、`RadioGroup.pas`、`CheckGroup.pas`、`ToolGroupPanel.pas`、`Card.pas`、`Empty.pas`、`Bevel.pas`、`Divider.pas`、`Splitter.pas`、`SizeBox.pas`、测试单元。

| 类 | 3.0 父类 | 4.0 Custom 父类 | LCL 对应 |
|---|---|---|---|
| TTyGroupBox | TTyCustomControl | TTyCustomControl | `TCustomGroupBox`（`stdctrls.pp:165`，public） |
| TTyRadioGroup | TTyGroupBox | **TTyCustomGroupBox** | `TCustomRadioGroup`（`extctrls.pp:717`，public） |
| TTyCheckGroup | TTyGroupBox | **TTyCustomGroupBox** | `TCustomCheckGroup`（`extctrls.pp:854`，public） |
| TTyToolGroupPanel | TTyGroupBox | **TTyCustomGroupBox** | `TCustomGroupBox` |
| TTyCard / TTyEmpty | TTyCustomControl | TTyCustomControl | Card ↔ `TCustomPanel`；Empty 无（public） |
| TTySplitter | TTyCustomControl | TTyCustomControl | `TCustomSplitter`（`extctrls.pp:370`，public） |
| TTyBevel / TTyDivider / TTySizeBox | TTyGraphicControl | TTyGraphicControl | LCL `TBevel` 不拆、无 Custom 对应 → public |

RadioGroup / CheckGroup 的错误消息用 `ClassName`（V8），实例类名不变。`ToolGroupPanel.pas:48/203` `AddButton: TTyButton`（建的就是 `TTyButton`）保持。

- [x] **Step 1: 拆** 10 个类。
- [x] **Step 2: A 下**：库内 `is TTyGroupBox` 0 处；编译器若报按规则改。
- [x] **Step 3: 测试**：`TThirdGroupBox`（发布 `Caption`、`Alignment`）、`TThirdRadioGroup = class(TTyCustomRadioGroup)`（发布 `Items`、`ItemIndex`；隐藏 `Columns`）——它自己建的子按钮仍是 `TTyRadioButton`，点第二个后 `ItemIndex = 1`；T-a…T-e、T-v。
- [x] **Step 4: `CPending` → `CSplit`**、提交。

### Task 14: 页签

**Files:** `source/tyControls.TabStrip.pas`（中间类降级）、`PageControl.pas`、`TabSheet.pas`、`TabSet.pas`、`ListGroupPanel.pas`、`Ribbon.pas`（只给 `TTyRibbon` 补发布段）、测试单元。

| 类 | 3.0 父类 | 4.0 Custom 父类 | LCL 对应 |
|---|---|---|---|
| （中间类）TTyCustomTabStrip | TTyCustomControl | 不变，降级 | `TCustomTabControl`（`comctrls.pp:373`，public 21 / protected 6 → public） |
| TTyPageControl | TTyCustomTabStrip | TTyCustomTabStrip | `TCustomTabControl`（`TPageControl` `:577`） |
| TTyTabSet | TTyCustomTabStrip | TTyCustomTabStrip | `TCustomTabControl` |
| TTyTabSheet | TTyCustomControl | TTyCustomControl | `TCustomPage`（`comctrls.pp:236`，public） |
| TTyListGroupPanel | TTyCustomControl | TTyCustomControl | 无（public） |

- [x] **Step 1: 降级中间类**：`TTyCustomTabStrip` 的 published 段（含 Task 1 插的基类块）按 R2 / R3 / D3 降级；**同一任务里**给它的 3 个注册后代补发布段：PageControl、TabSet 随拆分生成；`TTyRibbon`（3 期才拆，仍是 `class(TTyCustomTabStrip)`）的 published 段按快照顺序（`split.py block TTyRibbon` 输出的顺序）写全部名字，**它自己带类型声明过的名字在原位置保留原声明**，从中间类 / 基类继承来的写成 `property X;`，`R2s` 列出的 `Align` 用 `property Align default alTop;`（同 Task 1 的合并；3 期拆它时这些声明按 R2 挪进 `TTyCustomRibbon`）。~~只取 `property X;` 行、替换现有 published 段的全部内容~~（期末修复改正，理由同 Task 2）；G6 确认位置与说明符都没动。`CDemoted` 加 `TTyCustomTabStrip`。
- [x] **Step 2: 拆** PageControl、TabSet、TabSheet、ListGroupPanel。TabSheet 的 `Left / Top / Width / Height stored False` 是 **R3**（`TControl` 已 published），留在 `TTyCustomTabSheet` 的 published 段；`TabOrder / Visible stored False` 是 `R2s`，放 Custom 的 public 段（LCL public）。~~`TTyPageControl.ActivePage: TTyTabSheet`、`Pages[]` 保持（R7-4，LCL `TPageControl.ActivePage: TTabSheet` 先例），Custom 内部存 `TTyCustomTabSheet`、getter 处强转，记附录 D。~~ **第 0、1 期期末修复改定**（评估见 R7-4）：C13-1 放宽之后第三方 `TTyCustomTabSheet` 子类进库内 PageControl 是本任务的主要场景（S14-1 / S14-2 就是它），getter 强转成 `TTyTabSheet` 对它是类型假话；LCL 的强转之所以是真话，是因为 `TPageControl` 只收 `TTabSheet`（`pagecontrol.inc:113-117`）。改法：`TTyCustomPageControl` 的 `FPages`、`GetPage` / `GetActivePage` / `SetActivePage`、`Pages[]`、`ActivePage` 一律写 `TTyCustomTabSheet`（对应 LCL `TCustomTabControl.ActivePageComponent` / `Page[]: TCustomPage`）；`AddPage` / `AddTab` / `AddTabSheet` 建的就是 `TTyTabSheet`，返回类型保持（R7-4 ①）；`RegisterPage` / `UnregisterPage` / `MovePage` 照 R7-3 放宽。`ActivePage` 是 published 的，快照里 `TTyPageControl` 那一行的 `TypeName` 由 `TTyTabSheet` 变 `TTyCustomTabSheet`：`CSnapshotTypeRenames` 加 `('TTyTabSheet', 'TTyCustomTabSheet')`（全快照里 `TTyTabSheet` 作属性类型只这一行，G6 其余列照旧逐项比）；`.lfm` 不受影响（组件引用按名字流式），对象查看器按 InheritsFrom 列候选，第三方页也能选。测试加 S14-3：`TThirdTabSheet` 当活动页时 `PC.ActivePage = third` 且 `not (PC.ActivePage is TTyTabSheet)`，再用 `function: TTyCustomTabSheet of object` 的过程变量钉住 getter 的声明类型（同 `FindDownButton` 的写法；执行时改：getter 在另一单元是 private，取不到方法指针，改由 RTTI 钉住——`GetPropInfo(TTyPageControl, 'ActivePage')^.PropType^.Name = 'TTyCustomTabSheet'`，这也正是快照改名表放行的那一列；把属性类型改回 `TTyTabSheet` 时测试里 `pc.ActivePage := 第三方页` 编不过，等价于红）。不兼容清单第 5 条已写；附录 D 记「改」。
- [x] **Step 3: 为第三方放宽**：C13-1（TabSheet 认宿主 ×4，含强转）→ `TTyCustomPageControl`，读写宿主 protected 属性用 access 类（N17）；`RegisterPage` / `UnregisterPage` / `MovePage` 的参数放宽到 `TTyCustomTabSheet`（R7-3）；C13-2（PageControl 移除通知认页）→ `TTyCustomTabSheet`。设计期：`TTyPageControlEditor`（`CompEditors.pas:569`）、ListGroupPanel 编辑器（`:405/:512`）、`Dialogs.ListGroupsEditor.pas:67` 保持（D2）。
- [x] **Step 4: 测试**：`TThirdPageControl = class(TTyCustomPageControl)`（发布 `ActivePageIndex`、`TabPosition`）；T-a…T-e、T-v。S14-1：`TTyTabSheet` 的 Parent 设成 `TThirdPageControl`，`Sheet.PageControl` 返回它、页数 +1、激活后可见；C13-1 第一处改回 → 红。S14-2：`TThirdTabSheet = class(TTyCustomTabSheet)` 放进 `TTyPageControl` 当活动页后释放，`ActivePage` 变 nil（判据写「释放后 `ActivePage = nil`」，仓库记忆「AssertSame on a freed pointer」）；C13-2 改回 → 红。另：`TThirdTabSheet` 的 `Left` 设非零后流式文本里**没有** `Left`（R3 到了 Custom；M-G6c / M-G3a 同类）。
- [x] **Step 5: `CPending` → `CSplit`**、提交。

### Task 15: 列表框，组合框弹层 API 放宽

**Files:** `source/tyControls.ListBox.pas`、`CheckListBox.pas`、`OfficeListBox.pas`、`AdvancedListBox.pas`、`ValueListEditor.pas`、`ColorListBox.pas`、`FontListBox.pas`、`ComboBox.pas` 与 10 个组合框单元（弹层 API，C-4）、`CheckComboBox.pas`、`tests/test.scrollbar.autohide.pas`（A15-1）、`tests/test.parity.combo.pas`（`MakePopupList`）、`tests/test.customclasses.pas`（G6 子部件 key 的判断，N9）、测试单元。

| 类 | 3.0 父类 | 4.0 Custom 父类 | LCL 对应 |
|---|---|---|---|
| TTyListBox | TTyCustomControl | TTyCustomControl | `TCustomListBox`（`stdctrls.pp:537`，public） |
| TTyCheckListBox | TTyListBox | **TTyCustomListBox** | `TCustomCheckListBox`（`checklst.pas:36`，public） |
| TTyColorListBox | TTyListBox | **TTyCustomListBox** | `TCustomColorListBox`（`colorbox.pas:170`，public） |
| TTyOfficeListBox / TTyAdvancedListBox / TTyFontListBox / TTyValueListEditor | TTyListBox | **TTyCustomListBox** | `TCustomListBox`（LCL `TValueListEditor` 是网格系，名字对不上的照 `TCustomListBox`） |

- [x] **Step 1: 拆** 7 个类；`TTyColorListBox` 若有同名换类型的 `Style`，走 `R2s`。内部 `TTyComboPopupList`（从 `TTyListBox` 派生，仍是 `TTyListBox`）、`TTyValueEdit` 不动。
- [x] **Step 2: 弹层 API（C-4，被迫）**：`TTyCheckListBox` 改挂后，`TTyCheckComboPopupList` / `TTyGridFilterList` 不再是 `TTyListBox`（V12）。把组合框弹层的类型统一放宽到 `TTyCustomListBox`：`ComboBox.pas` 的 `FPopupList`（:144）、`RowSourceIndex`（:161/1315）、`CreatePopupList`（:290/2113，virtual）、`PopupList`（:349/2008）、`CollectRowOwnerDraw`（:373/1345）、`MeasureRowHeight`（:396/1294）、interface 函数 `TyComboBeginRowOwnerDraw` / `TyComboCollectRowOwnerDraw` / `TyComboDispatchRowOwnerDraw` / `TyComboMeasureRowHeight`（:513-520/572-594）、`TyComboOwnerOf` 的参数（:565）；10 个 `CreatePopupList` 覆写（AdvancedComboBox :48/187、CheckComboBox :95/569、ColorBox :142/642、ColorComboBox :30/93、ComboBoxEx :176/887、FontComboBox :33/91、OfficeComboBox :29/112、ShellComboBox :73/388）；`CheckComboBox.pas:339` 局部变量。内部读写列表 protected 成员的地方用 access 类。`ComboBox.pas:359` 的注释改写成真话（N27）。这是不兼容清单第 5 条的一项：覆写 `CreatePopupList` 的用户代码要改返回类型。
- [x] **Step 3: A 下必改**：A15-1 `tests/test.scrollbar.autohide.pas:1415` `TTyValueListEditor.InheritsFrom(TTyListBox)`——这条测试的意图是「VLE 白拿列表框的滚动条属性与两条惰性内嵌条」，A 下 VLE 是 `TTyCustomListBox` 的后代 → 改成 `InheritsFrom(TTyCustomListBox)`，注释改写（「4.0 起挂在 Custom 链上；白拿的仍是 TTyCustomListBox 里的实现」）并加一句 `not InheritsFrom(TTyListBox)` 钉住层级。**把 `TTyCustomValueListEditor` 改挂回 `TTyListBox`，第二句必须红**（G7 也红）。G6 的子部件 key 判断与 access 类改成 `TTyCustomListBox`（Task 0 说过；不改的话 ValueListEditor 等的 `sub` 列在本任务后会变成 `-`，G6 红——这正是要的提醒）。`tests/test.parity.combo.pas:1630` `TComboFactoryAccess.MakePopupList: TTyListBox` → `TTyCustomListBox`。
- [x] **Step 4: 测试**：`TThirdListBox`（发布 `Items`、`ItemIndex`；隐藏 `Sorted`）、`TThirdCheckListBox = class(TTyCustomCheckListBox)`（发布 `Items`、`AllowGrayed`）；T-a…T-e、T-v。S15-1：`TTyCheckComboBox` 下拉、勾一项、关闭，宿主的勾选状态被回写（弹层是 `TTyCheckComboPopupList`，经放宽后的弹层 API 走通）——编译期问题，这条证明行为没变（执行时：下拉要真窗口，改为经 access 类调 `CreatePopupList` 拿到弹层、断言它是 `TTyCheckListBox` 而不是 `TTyListBox`、勾一项后经 `PullChecksForTest` 回写宿主）。
- [x] **Step 5: `CPending` → `CSplit`**、提交。

### Task 16: 复合选择

**Files:** `source/tyControls.Transfer.pas`、`TreeSelect.pas`、`Cascader.pas`、测试单元。三个类 Custom 父类 = `TTyCustomControl`；无 LCL 对应（public）。内部 `TTyTransferArrowButton`、`TTyTreeSelectTree` 不动；`Transfer.pas` 的 `TTyListBox` 窗格是它自己建的 `TTyListBox`，保持。组件编辑器与 `Dialogs.CascaderEditor.pas:77` 保持（D2）。

- [x] **Step 1: 拆** 3 个类。
- [x] **Step 2: 测试**：`TThirdCascader`（发布 `Nodes`、`Separator`）、`TThirdTransfer`（发布 `Items`、`Selected`）；T-a…T-e、T-v；T-c 对 `Nodes` 这类集合属性确认往返。
- [x] **Step 3: `CPending` → `CSplit`**、提交。

### Task 17: 树与列表视图

**Files:** `source/tyControls.TreeView.pas`、`ShellListView.pas`（中间类 `TTyShellTreeLink` 与 ShellListView）、`ShellTreeView.pas`、`ListView.pas`、`HeaderControl.pas`、`designtime/tyControls.Design.PropEditors.pas`（:771、:772）、`designtime/tyControls.Design.CompEditors.pas`（注释）、`tests/test.designeditors.pas`、D10 涉及的 tests / examples 处理过程、测试单元。

| 类 | 3.0 父类 | 4.0 Custom 父类 | LCL 对应 |
|---|---|---|---|
| TTyTreeView | TTyCustomControl | TTyCustomControl | `TCustomTreeView`（`comctrls.pp:3382`，独有属性 **protected**） |
| （中间类）TTyShellTreeLink | TTyTreeView | 改挂 **TTyCustomTreeView**（0 发布，不用降级） | — |
| TTyShellTreeView | TTyShellTreeLink | TTyShellTreeLink | `TCustomShellTreeView`（`shellctrls.pas:80`，public） |
| TTyListView | TTyCustomControl | TTyCustomControl | `TCustomListView`（`comctrls.pp:1395`，独有属性 **protected**） |
| TTyShellListView | TTyListView | **TTyCustomListView** | `TCustomShellListView`（`shellctrls.pas:257`，public） |
| TTyHeaderControl | TTyCustomControl | TTyCustomControl | `TCustomHeaderControl`（异例，Q6：public） |

- [x] **Step 1: 拆**：TreeView → ShellTreeLink 改挂 → ShellTreeView；ListView → ShellListView；HeaderControl。`TTyShellTreeView.GetFilesInDir` / `GetBasePath`（class function）随 R1 进 Custom。~~`TTyShellListView` 与 `TTyShellTreeView` 互指的 interface 属性类型不改（R7-4）。~~ **第 2 期期末修复改定（主控定，照 LCL）**：`TTyCustomShellTreeView.ShellListView`（字段、setter、属性）改为 `TTyCustomShellListView`——LCL `TCustomShellTreeView.ShellListView: TCustomShellListView`（`shellctrls.pas:139`），第三方的 shell 列表也挂得上（R7-4 ②）；反方向 `TTyCustomShellListView.ShellTreeView` 本来就是接缝类 `TTyShellTreeLink`，第三方 `TTyCustomShellTreeView` 子类同样挂得上，不改；`TTyFilterComboBox.ShellListView` 照 LCL（`TFilterComboBox.ShellListView: TShellListView`，`filectrl.pp:167`）保持最终类。`ShellListView` 是 published 的，快照改名表 `CSnapshotTypeRenames` 因此改成**按类 + 属性限定**（类型整体改名会把 FilterComboBox 那一行也放过去）；见证 `TestShellTreeDrivesAThirdPartyShellList`（P2）。`TreeSelect.pas:108/164/348/436` 的 `TTyTreeView`（它自己建的 `TTyTreeSelectTree`，仍是 `TTyTreeView`）保持。
- [x] **Step 2: 事件类型（D10，需确认，建议照 LCL）**：`TreeView.pas:127-244` 的 21 个、`HeaderControl.pas:78/82/90` 的 3 个事件类型，Sender 改 `TTyCustomTreeView` / `TTyCustomHeaderControl`；触发处直接传 `Self`。仓库里的处理过程跟着改签名：tests（`test.treeview.pas` 116、`test.treeview.edit.pas` 26、`test.parity.treeview.pas` 14、`test.treeview.drag.pas` 10、`test.treeview.items.pas` 6、`test.headercontrol.pas` 6、`test.parity.header.pas` 6、`test.rtl.pas`、`test.treeselect.pas` 等）、examples（`treeview/showcasemain.pas` 80、`demo/mainform.pas` 16、`rtl/umain.pas` 6 等）——改前 `grep -rnE "Sender:\s*TTy(TreeView|HeaderControl)\b" tests examples tools` 列全，改后同一 grep 为 0。不是事件处理过程、只是普通参数的（如测试辅助函数 `procedure Fill(T: TTyTreeView)`）按 R6 判断，多数保持。Q7 选「不改」：改为在 Custom 里加 `AsPublished`、触发处 `FOnXxx(AsPublished, ...)`，附录 D 记下，处理过程不动。
- [x] **Step 3: A 下必改**：A17-1 `TreeView.pas:1392-1393`（节点取图片列表：`nodes.GetOwner is TTyTreeView`；执行中核实**不是翻转**：`TTyShellTreeView` 覆写 `SupportsItemModel = False`，往它的 `Items` 加条目当场抛 `ETyTreeItemMode`，节点条目取图片列表这条路它走不到——改归 C-2 的 C17-1，见证改用第三方模拟类）、A17-2 `:1629-1636`（节点集合改动通知宿主：`FOwner is TTyTreeView`）——A 下 `TTyShellTreeView` 的节点图标与刷新全断 → `TTyCustomTreeView`；A17-3 `ListView.pas:849-854`（项取宿主的 Large / SmallImages）——A 下 `TTyShellListView` 的项没有图标 → `TTyCustomListView`（`LargeImages` 照 D3 若 protected 用 access 类）。设计期：`CompEditors.pas:1153-1157` 的注释（「also covers TTyShellTreeView」）改写成真话：4.0 起 ShellTreeView 由默认编辑器接手，反正那里没有动词（D2）；`:530/874/917` 与 `Dialogs.TreeNodesEditor.pas:73` 的 `as TTyTreeView` 只会遇到 `TTyTreeView` / `TTyTreeSelectTree`，保持（C-3）。
- [x] **Step 4: 设计期**：`PropEditors.pas:771/772` 的 `TTyShellListView` / `TTyShellTreeView` → Custom 类；test.designeditors 的 `RegisterClasses` 加这两个 Custom 类。
- [x] **Step 5: 测试**：S17-1：~~`TTyShellTreeView`（内置派生）~~ `TThirdTreeView`（执行时改，理由见 Step 3 的 A17-1）设 `Images`，节点按 `ImageName` 解析出下标、按下标回写出名字。**A17-1 改回必须红。** S17-2：`TTyShellTreeView` 的节点集合改动后宿主节点数随之变（执行时：ShellTreeView 拒绝条目模型，见证改为「往它的 `Items` 加一项，宿主听到并抛 `ETyTreeItemMode`」——旧判断下它听不到、一声不响；另用 `TThirdTreeView` 证明加条目后节点建出来、改条目文字传到节点）。**A17-2 改回必须红**（若 ShellTreeView 的节点由它自己按目录生成、测试驱动不到，就用一个 `TThirdTreeView` 走同一条路，并在表里写明内置派生控件的覆盖靠 G7 + 审查）。S17-3：`TTyShellListView` 设 `SmallImages`，项取图片列表拿到它。**A17-3 改回必须红。** 模拟类 `TThirdTreeView`（发布 `Items`、`OnGetText`；隐藏 `DefaultNodeHeight`）——T-f：`OnGetText` 触发时 `Sender` 就是这个第三方实例、类型是 `TTyCustomTreeView`；`TThirdListView`（发布 `ViewStyle`、`Items`）；T-a…T-e、T-v。
- [x] **Step 6: `CPending` → `CSplit`**、`CDemoted` 不加（ShellTreeLink 不发布）、提交。

### Task 18: 表格

**Files:** `source/tyControls.Grid.pas`、测试单元。

| 类 | 3.0 父类 | 4.0 Custom 父类 | LCL 对应 |
|---|---|---|---|
| （中间类）TTyCustomGrid | TTyCustomControl | 不变，降级 | `TCustomGrid`（`grids.pas:744`，**protected** 100 / public 6） |
| TTyDrawGrid | TTyCustomGrid | TTyCustomGrid | `TCustomDrawGrid`（`grids.pas:1397`，public 112——LCL 在这一层把大批网格属性提成 public） |
| TTyStringGrid | TTyDrawGrid | **TTyCustomDrawGrid** | `TCustomStringGrid`（`grids.pas:1751`，public） |

- [x] **Step 1: 降级中间类**：`TTyCustomGrid` 的 published 段（约 68 + 基类块）按 R2 / R3 / D3 降级——同名属性照 `TCustomGrid` 的可见性（多数 protected）；同一任务里 DrawGrid、StringGrid 的发布段随拆分生成。`CDemoted` 加 `TTyCustomGrid`。`RegisterClasses([TTyCustomGrid, ...])`（:16012）保持（V19，不兼容清单第 3 条）。
- [x] **Step 2: 拆** DrawGrid、StringGrid：`TTyCustomDrawGrid` 照 `TCustomDrawGrid` 在 public 段写不带说明符的 `property X;` 把对应属性提成 public（R2 的例外，`split.py vis TCustomDrawGrid` 列出 LCL 在这一层提了哪些）。`split.py impl` 分两次，**确认没有误改 `TTyCustomGrid.` 的实现头**（`grep -c "^\(procedure\|function\|constructor\|destructor\) TTyCustomGrid\." source/tyControls.Grid.pas` 前后相等）。`TTyGridFilterList` 不动。
- [x] **Step 3: 测试**：`TThirdStringGrid = class(TTyCustomStringGrid)`（发布 `RowCount`、~~`ColCount`~~ `Header`——执行时改：本库网格没有 `ColCount`，列就是 `Header.Columns`）、`TThirdDrawGrid`（发布 `OnGetCellText`）；T-a…T-e、T-v；T-c 用 `tests/test.grid.streaming.pas` 的往返写法。
- [x] **Step 4: `CPending` → `CSplit`**、提交。

### Task 19: 2 期收尾

同 Task 11 的 Step 1–6，范围换成本期 42 个类与 3 个中间类；变异加 M-G6c、M-G3a（TabSheet）、M-T（Panel 家族）、本期 S / A 条目（S12-1、S12-2、S14-1、S14-2、A15-1、S17-1、S17-2、S17-3 及实际写了的其它）；【主控】冒烟另手点：containers 示例的 ScrollBox / 视口（`TTyScrollContent` 从 `.lfm` 读入）、shell 示例的树与列表有图标（A17-1、A17-3）。签收后同样通知「3.0 问题修复」会话。

---

## 第 3 期：其余可视

**本期新建** `tests/test.customclasses.p3.pas`（suite `TTyCustomClassesP3Test`，Task 20 建）。

### Task 20: 条

**Files:** `source/tyControls.StatusBar.pas`、`ToolBar.pas`（ToolBar + ToolButton + ToolSeparator）、`ToolBarEx.pas`、`Alert.pas`、`Pagination.pas`、`Steps.pas`、`Breadcrumb.pas`、`ScrollBar.pas`、D10 涉及的处理过程、测试单元。

| 类 | 3.0 父类 | 4.0 Custom 父类 | LCL 对应 |
|---|---|---|---|
| TTyStatusBar / TTyToolSeparator / TTySteps / TTyPagination | TTyCustomControl | TTyCustomControl | StatusBar ↔ `TStatusBar`（不拆，public）；其余无（public） |
| TTyToolBar | TTyCustomControl | TTyCustomControl | `TToolBar`（不拆，public） |
| TTyToolBarEx | TTyToolBar | **TTyCustomToolBar** | 无（public） |
| TTyToolButton | TTyGlyphButtonBase | TTyGlyphButtonBase（Task 2 已改挂） | `TToolButton`（不拆，public） |
| TTyAlert / TTyBreadcrumb | TTyGraphicControl | TTyGraphicControl | 无（public） |
| TTyScrollBar | TTyCustomControl | TTyCustomControl | `TCustomScrollBar`（`stdctrls.pp:68`，public） |

- [ ] **Step 1: 拆**：ToolBar.pas 三个类分三次 `impl`。`TTyToolButton` 现有发布段（Task 2 写的，含它自己带类型的声明）里，带类型、带说明符的声明先按 R2 / D3 挪进 `TTyCustomToolButton`，再把发布段换成 `split.py block` 的输出（此时它已是拆分形状，只剩 `property X;`），其中 `TabStop default False`（`R2s` → Custom 的 public 段）、`GlyphLayout stored FGlyphLayoutExplicit nodefault`（`R2s` → 照 `TCustomBitBtn` 的 GlyphLayout 可见性）挪进 `TTyCustomToolButton`。`TTyScrollBar` 被很多控件内嵌（建的是 `TTyScrollBar` 实例），内嵌点与 `EmbedsScrollBar(ABar: TTyScrollBar)` 之类签名保持。
- [ ] **Step 2: 事件类型（D10）**：`StatusBar.pas:60` `TTyDrawPanelEvent(AStatusBar: TTyStatusBar; ...)` → `TTyCustomStatusBar`；`ToolBar.pas` 里 Sender 为 `TTyToolButton` 的事件类型 → `TTyCustomToolButton`；处理过程（tests `test.toolbar.paintbutton.pas` 8、`test.parity.barsmenus.pas` 2、examples `toolbar/umain.pas` 2 等）跟着改。
- [ ] **Step 3: A 下必改**：A20-1 `ToolBar.pas:924-925`（`TTyToolButton.GetToolBar`：`Parent is TTyToolBar`）——A 下放在 `TTyToolBarEx` 上的工具按钮认不出宿主 → `TTyCustomToolBar`，`GetToolBar` 返回类型（`:121/922`）与本单元 11 处 `bar: TTyToolBar` 局部变量（`:932/941/1103/1131/1153/1181/1205/1229/1257/1499`）放宽到 `TTyCustomToolBar`（C-4）。
- [ ] **Step 4: 为第三方放宽**：C19-2（ToolBar / ToolBarEx 认 `is TTyToolButton` ×12）→ `TTyCustomToolButton`；C19-3（StatusBar 面板集合取所有者）→ `TTyCustomStatusBar`；C19-4（`is TTyGlyphButtonBase`）保持（中间类本身就是 Custom 层）。C19-2 放宽之后 `TTyToolBar.Buttons[]` / `GetButton`（`ToolBar.pas:499/565`）交出的是任意工具按钮，返回类型改 `TTyCustomToolButton`、`IndexOfButton` 参数放宽（R7-4 ②，第 0、1 期期末修复改定；LCL `TToolButton` 不拆，所以 `TToolBar.Buttons[]: TToolButton` 在 LCL 是真话），附录 D 记「改」，不兼容清单第 5 条。
- [ ] **Step 5: 测试**：S20-1：`TTyToolButton` 放在 `TTyToolBarEx` 上，`GetToolBar` 返回它、按 `ButtonWidth` 拿到宽度下限。**A20-1 改回必须红。** S20-2：`TThirdToolButton = class(TTyCustomToolButton)`（发布 `Style`、`Down`）放在 `TTyToolBar` 上，拿到宽度下限，且 `Style = tbsSeparator` 时不被打上 `ghost`；C19-2 那两处改回 → 红。S20-3：`TThirdStatusBar` 加一个面板后重画（能观察就写）。模拟类 `TThirdToolBar`（发布 `ButtonWidth`、`Flat`）、`TThirdStatusBar`（发布 `Panels`、`SimpleText`）、`TThirdScrollBar`（发布 `Position`、`Max`）；T-a…T-e、T-v。`tests/test.toolbarex.pas:694-696` 的 `TTyToolButton(TB.Controls[i])`（建的就是 ToolButton）保持。
- [ ] **Step 6: `CPending` → `CSplit`**、提交。

### Task 21: Ribbon

**Files:** `source/tyControls.Ribbon.pas`（Ribbon + Page + Group）、`RibbonAppMenu.pas`、`RibbonQuickAccess.pas`、`RibbonGallery.pas`、`RibbonBackstage.pas`、`designtime/tyControls.Design.PropEditors.pas`（:653-663、:757）、`tests/test.designeditors.pas`、D10 涉及的处理过程、测试单元。

| 类 | 3.0 父类 | 4.0 Custom 父类 | LCL 对应 |
|---|---|---|---|
| TTyRibbon | TTyCustomTabStrip | TTyCustomTabStrip（Task 14 已降级） | 无（public） |
| TTyRibbonPage / TTyRibbonGroup / TTyRibbonQuickAccess / TTyRibbonGallery / TTyRibbonBackstage | TTyCustomControl | TTyCustomControl | 无（public） |
| TTyRibbonAppMenu | TTyMenuButton | **TTyCustomMenuButton**（Task 2 已有） | `TCustomButton` 一系 |

- [ ] **Step 1: 拆**：Ribbon.pas 三个类分三次 `impl`；`TTyRibbon` 现有发布段（Task 14 写的，含它自己带类型的声明）里，带类型、带说明符的声明先按 R2 / D3 挪进 `TTyCustomRibbon`，再把发布段换成 `split.py block` 的输出，`Align default alTop` 是 `R2s`（Align 不是 LCL 根已 published 的）→ `TTyCustomRibbon` 的 public 段（LCL `TControl.Align` public）。interface 里 ~~`Pages: TTyRibbonPage`、`Backstage: TTyRibbonBackstage` 等按 R7-4 保持、附录 D~~ **（第 0、1 期期末修复改定，R7-4）**：`Pages[]` / `ActivePage` / `FPages` 与页里的组数组（C20-1 / C20-2 放宽后会装第三方页、组）→ `TTyCustomRibbonPage` / `TTyCustomRibbonGroup`（都不是 published，快照不动）；`AddPage` 建的 `TTyRibbonPage`、setter 写最终类的 `Backstage: TTyRibbonBackstage` 保持（R7-4 ①）；逐个记附录 D。`TTyRibbonAppMenu` 改挂 `TTyCustomMenuButton`。`RibbonQuickAccess.pas:62` 的 `TTyGlyphButton`（它自己建的）保持。
- [ ] **Step 2: 事件类型（D10）**：Sender 为 `TTyRibbonGroup` 的事件类型 → `TTyCustomRibbonGroup`；处理过程（examples `ribbon/umain.pas` 2）跟着改。
- [ ] **Step 3: 为第三方放宽**：C20-1（RibbonPage 认宿主 ×2）、C20-2（Ribbon 数组 / 摆放 RibbonGroup ×3）、C20-3（Ribbon 移除通知认页）、C20-4（设计期 `Context` 下拉列宿主的页 `PropEditors.pas:653/661`）→ 各自的 Custom 类。
- [ ] **Step 4: 设计期**：`PropEditors.pas:757` `TTyRibbonPage` → `TTyCustomRibbonPage`；test.designeditors 的 `RegisterClasses` 加它。
- [ ] **Step 5: 测试**：`TThirdRibbonPage`（发布 `Caption`、`Context`）、`TThirdRibbonGroup`（发布 `Caption`、`ShowCaption`）；T-a…T-e、T-v。S21-1：`TThirdRibbonPage` 放进 `TTyRibbon`，被收进页列表、改 `Context` 触发宿主重排；C20-1 改回 → 红。S21-2：`TThirdRibbonGroup` 参与组的计数与右对齐；C20-2 改回 → 红。`examples/ribbon/umain.pas:1155-1156` 的 `is TTyRibbonGroup`（示例里只有内置组）保持（C-3）。
- [ ] **Step 6: `CPending` → `CSplit`**、提交。

### Task 22: 窗体镶边

**Files:** `source/tyControls.Form.pas`（只拆 `TTyTitleBar`、`TTyMenuBar`；`TTyForm` 不动，Q5）、`Menu.pas`（`TTyMenuBar` 若在这里；`TTyPopupMenu` 等不拆）、`FormSurface.pas`、测试单元。三个类 Custom 父类 = `TTyCustomControl`；无 LCL 对应（public）。

- [ ] **Step 1: 拆**：`RegisterClass(TTyTitleBar / TTyMenuBar / TTyFormSurface)` 保持。`TTyTitleBar = class(TTyCustomControl, ITyTitleBarTag)` 的接口列表上 Custom 类头。`TTyForm.TitleBar: TTyTitleBar`、`MenuBar: TTyMenuBar` 等属性类型按 R7-4 保持（附录 D：第三方 Custom 子类挂不到这两个属性上，文档写清）。`TTyFormSurface` 的设计期 Hidden 编辑器（`PropEditors.pas:801-847`）留在最终类（D2）。
- [ ] **Step 2: 为第三方放宽**：C21-1（`Form.pas:2177-2178` `TTyForm.Notification` 里 `AComponent is TTyTitleBar`）→ `TTyCustomTitleBar`；C11-3 的 `Form.pas:2192-2193`（`is TTyFormSurface`，窗体认自己的内容宿主）→ `TTyCustomFormSurface`。
- [ ] **Step 3: 测试**：`TThirdTitleBar`（发布 `Caption`、`ShowMinimize`）、`TThirdMenuBar`（发布 `Menu`、`AutoSizeWidth`）、`TThirdFormSurface`（发布 `Purpose`）；T-a…T-e、T-v（标题栏不关联窗体时也能建、流式）。S22-1：一个关联着的标题栏被释放时窗体清引用——第三方子类挂不上 `TitleBar`（R7-4），这条用内置 `TTyTitleBar` 证明行为不变，C21-1 改回不会红 →「—：TitleBar 属性类型写死最终类，第三方本来就挂不上；放宽是为了与 LCL 一致的语义，审查覆盖」。
- [ ] **Step 4: `CPending` → `CSplit`**、提交。

### Task 23: 图像与图形

**Files:** `source/tyControls.CharImage.pas`、`Image.pas`、`PreviewBox.pas`、`ImageView.pas`、`Shape.pas`、`StarShape.pas`、`Arrow.pas`、`Chart.pas`、`designtime/tyControls.Design.PropEditors.pas`（:752）、`tests/test.designeditors.pas`、测试单元。`TTyPreviewBox`、`TTyImageView` → `TTyCustomControl`；其余 6 个 → `TTyGraphicControl`。LCL 对应：CharImage、Image、ImageView ↔ `TCustomImage`（`extctrls.pp:529`，public）；Shape、StarShape ↔ `TCustomShape`（`extctrls.pp:274`，public）；Arrow ↔ `TArrow`（不拆，public）；PreviewBox、Chart 无（public）。`RegisterClass(TTyChart)` 保持。无放宽条目。`IconFont` 属性类型在 Task 28 改（D11）。

- [ ] **Step 1: 拆** 8 个类。
- [ ] **Step 2: 设计期**：`PropEditors.pas:752` `TTyCharImage` → `TTyCustomCharImage`；test.designeditors 的 `RegisterClasses` 加它。
- [ ] **Step 3: 测试**：`TThirdCharImage`（发布 `IconFont`、`GlyphName`）、`TThirdShape`（发布 `Shape`、`OnShapeClick`）、`TThirdChart`（发布 `ChartType`、`Series`）；T-a…T-e、T-v。
- [ ] **Step 4: `CPending` → `CSplit`**、提交。

### Task 24: 取色器与终端

**Files:** `source/tyControls.ColorGrid.pas`、`LColorPicker.pas`、`HSColorPicker.pas`、`Terminal.pas`、测试单元。四个类 Custom 父类 = `TTyCustomControl`；无 LCL 对应（public）。`TTyTerminalViewComponentEditor`（`CompEditors.pas:980`）保持（D2）。`Dialogs.Color.pas:105` 的 `TTyColorGrid` 内嵌实例不改。

- [ ] **Step 1: 拆** 4 个类；终端的接口、IME、`DefineProperties` 随 R1 进 Custom；`examples/terminal` 里被 tests 引用的单元不改。
- [ ] **Step 2: 测试**：`TThirdTerminalView`（发布 `Scrollback`、`CursorStyle`）、`TThirdColorGrid`（发布 `Columns`、`Selected`）；T-a…T-e、T-v；T-f：终端模拟子类收一段文本后缓冲区里有它。
- [ ] **Step 3: `CPending` → `CSplit`**、提交。

### Task 25: 工具窗口（D4–D6：没有 LCL 对应物，按可视规则拆）

**Files:** `source/tyControls.ToolWindows.pas`、`ToolWindows.DesignRules.pas`、`ToolWindows.Manager.pas`（只放宽 implementation 里的判断；`TTyToolWindowManager` 按 Q4 不拆）、`designtime/tyControls.Design.CompEditors.pas`（不改注册，D2）、测试单元。三个类 Custom 父类 = `TTyCustomControl`；无 LCL 对应（public）。R3：Window 的 `Left / Top / Width / Height stored False`、Actions 的 `Left / Top / Width / Height stored IsBoundsStored`、Bar 的 `Width stored WidthIsStored`、`Height stored HeightIsStored`（都是 `TControl` 已 published 的名字）；`R2s`：Window 的 `Controller / TabOrder / Visible stored False`、Actions 的 `Controller stored False`（public）。设计期 Hidden 编辑器（`PropEditors.pas:73-74`，`Controller`）留在最终类。

- [ ] **Step 1: 拆**；`ToolWindows.Manager` / `DesignRules` 的 interface 签名里的栏 / 窗口 / 动作区类型：R7-3 内部的放宽；`TTyCustomToolWindowManager` 的公开 API（宿主属性、事件参数）照 R7-1 / R7-4 判断，每个改了的或保持的记附录 D。
- [ ] **Step 2: 为第三方放宽**：附录 C-2 的 C24 段（43 处）逐处放宽，`InheritsFrom` 的四处（设计期拖放规则）一并；`CompEditors.pas:659/749` 保持。
- [ ] **Step 3: 测试**：`TThirdToolWindow`（发布 `Caption`、`ImageName`）进 `TTyToolWindowBar` 后被登记、能激活、释放后从栏里移除；`TThirdToolWindowBar` 收 `TTyToolWindow`；设计规则接受第三方窗口作为栏的子控件。各配变异（把对应判断改回最终类 → 红）。
- [ ] **Step 4: `CPending` → `CSplit`**、提交。

### Task 26: 3 期收尾

同 Task 11 的 Step 1–6，范围是本期 35 个类；变异加 M-T（Ribbon 或 ToolBar 家族）、本期 S / A 条目（S20-1、S20-2、S21-1、S21-2、Task 25 的各条）；【主控】冒烟另手点 toolbar 示例里 ToolBarEx 上的工具按钮（A20-1）、ribbon 示例、窗体标题栏。签收后通知「3.0 问题修复」会话。

---

## 第 4 期：非可视组件与文档

**本期新建** `tests/test.customclasses.p4.pas`（suite `TTyCustomClassesP4Test`，Task 27 建）。非可视模拟子类的判据：T-a（`Create(nil)` 不抛）、T-b（LCL 根 = `TComponent` 或 `TCustomImageList`）、T-c、T-e、T-v；没有 T-d。

### Task 27: 控制器

**Files:** `source/tyControls.Controller.pas`、`NativeStyler.pas`、（D11）`Base.pas` 的 `Controller` 属性与字段类型、其余 9 个 `Controller: TTyStyleController` 属性所在单元、`designtime/tyControls.Design.PropEditors.pas`（`TTyStyleController` 的 ThemeName / Mode / ThemeFile / StyleOverride 四条 → Custom）、测试单元。两个类 Custom 父类 = `TTyComponent`；无 LCL 对应（public）。

- [ ] **Step 1: 拆** 2 个类。
- [ ] **Step 2: D11（需确认，建议照 LCL）**：`Controller` 属性的类型改 `TTyCustomStyleController`（`Base.pas` 两处——这是共享文件，本步骤是 Task 1 之外唯一一次碰它，只改属性与字段的类型名，**需主控确认**；其余 9 处、全库 127 处类型出现按 R7 逐个判断：属性、字段、参数放宽，库内需要最终类型的地方保持）。`CSnapshotTypeRenames` 已含这一项；`Controller` 行在 G6 里只允许 `TypeName` 变。**同一提交**把按类类型注册的三条 Hidden 编辑器（`PropEditors.pas:742-743` `TTyToolWindow` / `TTyToolWindowActions`、`:837` `TTyFormSurface`，都是 `TypeInfo(TTyStyleController)`，行号以 `41509003` 为准）改成 `TypeInfo(TTyCustomStyleController)`：IDE 按「属性的类 InheritsFrom 注册的类」匹配（`propedits.pp:2838-2846`），`TTyCustomStyleController` 不是 `TTyStyleController` 的后代，不改就静默失配、藏掉的 `Controller` 又出现在对象查看器里。守卫：`test.designeditors` 的 `TestClassTypedRegistrationsMatchThePropertyType`（第 0、1 期期末修复加的，现在绿；属性改了类型而注册没改，它就红）。Q8 选「只改被迫的」时跳过本步骤。
- [ ] **Step 3: 测试**：`TThirdStyleController`（发布 `ThemeName`、`Mode`；隐藏 `ThemeFile`）；T-a、T-b、T-c、T-e、T-v；S27-1：把它赋给一个 `TTyButton.Controller`（D11 之后编得过），按钮按它的主题解析样式。D11 不做时：「—：第三方控制器挂不上 Controller 属性，文档写限制」。
- [ ] **Step 4: `CPending` → `CSplit`**、提交。

### Task 28: 图标字体与图像

**Files:** `source/tyControls.IconFont.pas`（IconFont + 中间类 IconPackFont）、`Icons.Lucide.pas`（LucideIconFont + LucideImageList）、`ImageCollection.pas`（ImageCollection + VirtualImageList）、`GlyphImageList.pas`、`ImageDraw.pas`（A28-1）、8 个 `IconFont` 属性所在单元（`CharImage.pas:59`、`Dialogs.IconBrowser.pas:101/195`、`GlyphButtons.pas:225`、`GlyphImageList.pas:72`、`ImageCollection.pas:471`、`RibbonBackstage.pas:109`、`RibbonGallery.pas:123`）、`designtime/tyControls.Design.CompEditors.pas`（:282-286、:1161）、`designtime/tyControls.Design.PropEditors.pas`（:478-484、:506-516 与注册）、测试单元。

| 类 | 3.0 父类 | 4.0 Custom 父类 | LCL 对应 |
|---|---|---|---|
| TTyIconFont | TTyComponent | TTyComponent | 无（public） |
| （中间类）TTyIconPackFont | TTyIconFont | 改挂 **TTyCustomIconFont**、降级 | — |
| TTyLucideIconFont | TTyIconPackFont | TTyIconPackFont | 无（public） |
| TTyVirtualImageList | TCustomImageList | TCustomImageList | `TCustomImageList`（`imglist.pp:266`，public） |
| TTyLucideImageList | TTyVirtualImageList | **TTyCustomVirtualImageList** | 同上 |
| TTyGlyphImageList / TTyImageCollection | TTyComponent | TTyComponent | 无（public） |

- [ ] **Step 1: 拆**：IconFont → IconPackFont 改挂并降级（`CDemoted` 加它；`TTyLucideIconFont` 随拆分生成发布段）→ LucideIconFont；VirtualImageList → LucideImageList（`IconFont stored False` 是 `R2s`）；GlyphImageList、ImageCollection。`RegisterClass(TTyImageCollection / TTyVirtualImageList)` 保持。Lucide 两个类 `THiddenPropertyEditor` 藏掉的属性（`PropEditors.pas:61-69`）**照旧发布、照旧藏**（快照要求名字不变；不发布它们是 4.x 以后可以考虑的事）。
- [ ] **Step 2: A 下必改**：A28-1 `ImageDraw.pas:95/101-105/112-113/120-121/162/209-213/250-254/284-288/330-335` 的 `AList is TTyVirtualImageList` + 强转（9 处判断）——A 下 `TTyLucideImageList` 不再是 `TTyVirtualImageList`，**所有用 Lucide 图像列表的控件退回光栅路径、按名字取图全失效** → `TTyCustomVirtualImageList`（`Names` / `IndexOf` / `NameOf` / `RenderIndex` 照 D3 可见性，protected 的用 access 类；`TyTakeVectorBitmap` 的参数放宽）。A28-2 `CompEditors.pas:282-286`（图标浏览器找字体 / 列表：`is TTyIconFont` / `is TTyVirtualImageList`，注释写着「covers TTyIconPackFont / TTyLucideIconFont」）→ Custom 类；`:1161` 的注册 `[TTyIconFont, TTyVirtualImageList]` 照 D2 显式加上 `TTyLucideIconFont`、`TTyLucideImageList`（注释改写）。A28-3 `PropEditors.pas:478-484/506-516`（GlyphName 编辑器从宿主的 `IconFont` 取字体：`fnt is TTyIconFont`）→ `TTyCustomIconFont`。保持：`IconFont.pas:1071`（缓存里只放它自己建的 `TTyIconFont`）、`tests/test.lucide.pas:319`、`tests/test.toolwindow.images.pas:255-256`、`tests/test.imagename.pas` 的 `TTyVirtualImageList(FList)`（对象就是它）。
- [ ] **Step 3: `IconFont` 属性类型（D11，被迫）**：8 个 published `IconFont: TTyIconFont` 与其字段、setter 参数、全库 44 处类型出现 → `TTyCustomIconFont`（按 R7 逐个判断）。**同一提交**改设计期按类类型的注册与判断：`PropEditors.pas:738` `TypeInfo(TTyIconFont)`（Lucide 列表藏 `IconFont`）→ `TypeInfo(TTyCustomIconFont)`；D11 一并改 `ImageCollection` 类属性时 `:737` `TypeInfo(TTyImageCollection)`（藏 `Collection`）→ `TypeInfo(TTyCustomImageCollection)`；`:478` / `:506` 的 `fnt is TTyIconFont`（GlyphName 编辑器，A28-3）→ `TTyCustomIconFont`（行号以 `41509003` 为准）。前两条由 `TestClassTypedRegistrationsMatchThePropertyType` 守住（属性改了、注册没改就红）；后两处是运行期判断，测试驱动不到，审查对着本句核。不改的话 `TTyLucideIconFont` 挂不上任何 `IconFont` 属性（examples 里大量这样用）。属性编辑器 `TTyIconFont` 的 FontFamily / FontFile（`PropEditors.pas:37-40`）→ `TTyCustomIconFont`；`TTyLucideIconFont` 的 Hidden 编辑器留在最终类（更派生，照样盖住）。
- [ ] **Step 4: 测试**：S28-1：一个 `TTyGlyphButton` 用 `TTyLucideImageList` + `ImageName`，`RenderTo` 画出矢量图（与 3.0 行为一致：按名字取到索引、走矢量路径——用 `ImageDraw` 的「是否矢量」判断函数断言 True）。**A28-1 改回必须红。** S28-2：`TTyCharImage.IconFont := TTyLucideIconFont 实例` 编得过且 `GlyphName` 解析出字形（D11 的钉子；编译期，「改回」就是编不过）。A28-2、A28-3：设计期，「—：IDE 内才走得到，审查覆盖；【主控】在 IDE 里双击 Lucide 图标字体出图标浏览器（用户验收项 2）」。模拟类 `TThirdIconFont`（发布 `FontFamily`、`Glyphs`）、`TThirdVirtualImageList`（发布 `Names`、`ImageCollection`）；T-a、T-b、T-c、T-e、T-v。
- [ ] **Step 5: `CPending` → `CSplit`**、提交。

### Task 29: 提示与通知

**Files:** `source/tyControls.Hint.pas`、`BalloonHint.pas`、`Popover.pas`、`Notification.pas`、`designtime/tyControls.Design.PropEditors.pas`（`TTyPopover` 的 StyleClass → Custom）、测试单元。四个类 Custom 父类 = `TTyComponent`；无 LCL 对应（LCL 的 `THintWindow` `forms.pp:978` 是窗体、不是组件；public）。子部件 key（`StyleTypeKey` / `TitleStyleTypeKey` / `CloseStyleTypeKey`，class function）随 R1 进 Custom，G6 的 `sub` 列钉住。

- [ ] **Step 1: 拆** 4 个类。
- [ ] **Step 2: 测试**：`TThirdPopover`（发布 `Content`、`Placement`）、`TThirdNotification`（发布 `Title`、`Text`）；T-a、T-b、T-c、T-e、T-v；T-k：`TThirdPopover.StyleTypeKey = TTyPopover.StyleTypeKey`。`examples/antdesign/umain.pas:416` 的 `TTyNotification` 判断（示例里只有内置）保持。
- [ ] **Step 3: `CPending` → `CSplit`**、提交。

### Task 30: 对话框

**Files:** `source/tyControls.Dialogs.pas`（Message、InputDialog、PasswordDialog、TextDialog、SelectValueDialog）、`Dialogs.Progress.pas`、`Dialogs.About.pas`、`Dialogs.IconBrowser.pas`、`designtime/tyControls.Design.CompEditors.pas`（对话框预览编辑器注册保持，D2）、测试单元。

| 类 | 3.0 父类 | 4.0 Custom 父类 | LCL 对应 |
|---|---|---|---|
| TTyMessage | TTyComponent | TTyComponent | `TCustomTaskDialog`（`dialogs.pp:723`，public）——LCL 拆的 |
| TTyInputDialog / TTyPasswordDialog / TTyTextDialog / TTySelectValueDialog / TTyProgressDialog / TTyIconBrowserDialog | TTyComponent | TTyComponent | 无（`InputQuery` 等是函数；public） |
| TTyAboutDialog | TComponent | TComponent | 无（public） |

不拆的 11 个（附录 F）只在 Task 1 补了 `Version`，本任务不碰。

- [ ] **Step 1: 拆** 8 个类。`CompEditors.pas:962-973` 的对话框预览（`as` 最终类）保持（D2，组件编辑器）。
- [ ] **Step 2: 测试**：`TThirdMessage`（发布 `Text`、`Buttons`）、`TThirdInputDialog`（发布 `Prompt`、`Value`）；T-a、T-b、T-c、T-e、T-v。
- [ ] **Step 3: `CPending` → `CSplit`**、提交。

### Task 31: 文档

**Files:** Create `docs/subclassing.md`、`docs/subclassing.en.md`；Modify `README.md`、`README.en.md`（文档索引各一行）、`docs/controls/README.md`（顶部一句）、`CONTRIBUTING.md` / `CONTRIBUTING.en.md`（「几条硬规矩」加一条「新控件生来就拆成 `TTyCustomXxx` + `TTyXxx`，G5 会查」）。

内容（仓库记忆「文档要原生语感」，中英各写一遍，不是互译腔）：
1. 什么时候派生 `TTyCustomXxx`（只想露一部分属性）、什么时候派生 `TTyXxx`（全要、再加）。
2. 一个完整的最小例子：`TMyTagEdit = class(TTyCustomEdit)`，published 段 `property Text; property ReadOnly; property OnChange;`，注册到自己的包；default / stored 会跟过来；**顺序由你的 published 段决定**（V5-7 用户能感知的那一面：先写会钳住别人的属性，比如先 `Max` 后 `Position`）。逐个写明（第 0、1 期期末修复核实）：**数值编辑框一族（`TTyCustomNumericEdit` 及 Currency / Track / Calc / CalcCurrency / FloatSpin）与顺序无关**——加载期间 `Value` 先暂存、`Loaded` 时按最终的 `Decimals` / `MinValue` / `MaxValue` 设入；**仍要求「范围在前、值在后」的**：`TTyCustomSpinEdit`（`MinValue` / `MaxValue` 先于 `Value`）、`TTyCustomProgressBar`（`Max` 先于 `Position`）、`TTyCustomGauge`（`Max` 先于 `Value`）、`TTyCustomTrackBar`（`Min` / `Max` 先于 `Position`）——这几个的值是 setter 当场钳住的，照最终类的发布顺序写就对；2–4 期新拆的家族核实后追加到这张单子。
3. **主题**：typeKey 跟着 Custom 类走——`TTyCustomEdit` 的子类自动吃 `TyEdit` 的 tycss 规则，`.tycss` 里永远不写 Custom；若覆写 `GetStyleTypeKey` 换成自己的 key，主题里要写它的规则，否则走不到样式（#14 之后会有回落）。
4. 可见性：Custom 类里的属性照 LCL 是 public 或 protected（附录 E 的结论用一句话说清：编辑框、组合框、列表框、按钮多为 public，标签、树、列表视图、网格基类多为 protected）；要从外面访问 protected 的，在自己的类里 `public property X;`。
5. 设计期：属性编辑器自动跟着用；~~组件编辑器要自己注册（`RegisterComponentEditor(TMyTree, TTyTreeViewComponentEditor)`）~~ **组件编辑器不跟着来，也不能把库里的直接注册给自己的类**（第 2 期期末修复改写）：D2 把组件编辑器留在最终类上（`CompEditors.pas` 的 `RegisterComponentEditor(TTyPageControl, ...)` 等），实现里写的也是最终类（`Component as TTyPageControl`、`as TTyTreeView`、`as TTyCascader`……，附录 C-3），所以第三方 `TMyPageControl = class(TTyCustomPageControl)` 在设计器里右键**没有**「加页 / 删页 / 下一页 / 显示页」，而照旧写法把 `TTyPageControlEditor` 注册给它，一点菜单就抛 `EInvalidCast`。文档给出自行注册的完整写法：在自己的设计期包里写一个 `TDefaultComponentEditor` 子类，`GetVerbCount` / `GetVerb` / `ExecuteVerb` 照 `TTyPageControlEditor.ExecuteVerb` 的「加页」分支（`Hook` 取 `GetHook`；`TTyTabSheet.Create(PC.Owner)`；先 `Parent := PC` 再 `GetDesigner.CreateUniqueComponentName` 起名、设 `Caption` / `Name`；`PC.ActivePage := NewPage`；`Hook.PersistentAdded(NewPage, True)`；`Modified`），其中 `PC` 写成 `Component as TTyCustomPageControl`（加页、删页、翻页用到的 `Pages[]` / `PageCount` / `ActivePage` / `ActivePageIndex` 在 Custom 类上都是 public），`Register` 里 `RegisterComponentEditor(TMyPageControl, TMyPageControlEditor)`；第三方别的家族（树的节点编辑器、级联选择的节点编辑器……）同理，文档列出库里哪些组件编辑器存在、各自对应哪个最终类。属性编辑器（`Directory`、`GlyphName`、`ImageName` 等）注册在 Custom 类或按属性类型注册，第三方子类自动有。`DefineProperties` 存的数据照样存（N20）。
6. 限制：LCL 根的 15 个属性藏不掉（N13）；宿主属性写死子项最终类型的（`TTyForm.TitleBar` 等，附录 D；~~`TTyPageControl.ActivePage`~~ 期末修复改为 Custom 类型，见 R7-4）；~~UpDown 按 RTTI 找 `Text`、~~ GlyphName 编辑器按 RTTI 找 `IconFont`（V20；UpDown 已不是限制：编辑框一族的 Caption 就是 Text，不发布 `Text` 的子类照样被驱动——这句写进文档的「可以放心不发布的」那一侧）；`TTyGridCell` 由 GridPanel 自己建，第三方子类只能手动放进去；直接继承 `TTyCustomControl` 写全新控件时，Ty 控件惯用的那段通用属性（给出可复制的 published 段）。
7. **从 3.0 升级**（一节）：「不兼容变化清单」逐条的用户版；全部父类变化的控件表（附录 C-0 的 55 行：控件、3.0 的父类、4.0 的父类）；一条规则（**想表示「任意 Xxx」就判 `TTyCustomXxx`**）；示例代码改前改后（`Sender as TTyButton` → `Sender as TTyCustomButton`；`if AEditor is TTyEdit` → `TTyCustomEdit`；TreeView 事件处理过程的签名；直接继承基类的类补 published 段）；`.lfm` 不用改、主题不用改。
8. **同步现有文档里「基类发布基线属性与事件」的说法**（第 0、1 期期末修复补列）：`docs/events.md` / `docs/events.en.md`（开头「基线事件全部由两个基类统一 published」、Tier A / Tier B 两表的「两个基类都有」「仅 `TTyCustomControl`」、`:60` 的「声明在基类的 `published` 段」、`:78` / `:127`（en `:124`）的「在 `TTyCustomControl` 上 published」——4.0 起是每个最终类发布、基类与 Custom 类按 LCL 可见性，事件表本身不变）、`docs/controls/button.md`（`:49`「每个 TyControls 控件都从 `TTyCustomControl` 继承以下两个 published 属性」、`:76`「基线事件集」）、`docs/controls/buttongroup.md`、`docs/controls/panel.md`、`docs/controls/spinedit.md`、`docs/controls/tabset.md`（同类说法，执行时 `grep -n "基类\|TTyCustomControl\|TTyGraphicControl\|published"` 逐处改）。
9. **Task 1 从 `Base.pas` 删掉的长注释的去处**（原文在 `6fff2bd3:source/tyControls.Base.pas:254-333`（图形基类）与 `:418-515`（窗口化基类））：`Visible`「此前哪儿都没发布、只能在代码里藏」、`AutoSize`「21 个控件早就实现了 `CalculatePreferredSize`」、拖放七个「分发全在 LCL，自绘控件白拿」、横向 / 倾斜滚轮三个「侧向滚动控件只从它们收到手势」、`OnShowHint`「逐实例提示的唯一接缝」、`BorderWidth` / `ChildSizing`「只对窗口化容器有意义」——这些「为什么 Ty 控件发布它们」并进 `docs/subclassing.md` 给出的那段可复制 published 段的逐行说明（第三方照抄时知道每行是干什么的），`docs/events.md` 里已有的拖放、`Visible`、`BorderWidth` 说明保留并改指向；`OnPaint` 的契约（画完之后触发、不是 owner-draw、在缓存容器上于贴图之后触发所以不进缓存）`docs/events.md:43/129-133` 已写，`Base.pas` 的 `WMPaint` / `PaintWindow` 实现注释（`:1663`、`:2076` 一带）也还在——核对两处与原注释一致，缺的补进 `docs/events.md`。

- [ ] **Step 1: 写文档**；`python scripts/check-example-po.py .` 不受影响。
- [ ] **Step 2: 提交** `docs: deriving from Ty controls through TTyCustomXxx, and upgrading from 3.0`。

### Task 32: 4 期收尾、撤快照守卫、用户验收清单

- [ ] **Step 1–5**：同 Task 11 的 Step 1–5，范围是本期类；变异加本期 S / A 条目（S27-1、S28-1、T-k）与 M-T（IconFont 家族）。审查另加**全计划**的结构复核：`CPending` 为空；`git diff a0606352..HEAD --stat -- source designtime` 里共享文件只有 Task 1（与 Q8 的 Task 27）那几处、排除单元只有 Task 1 的插块；附录 C 每行都有落实；附录 D 补全；「不兼容变化清单」与实际改动一致（每条都能在 diff 里找到，diff 里每个公开签名的类型变化都在清单里）。
- [ ] **Step 6: 撤迁移期守卫（D9）**：**先**（G6 还在、还绿的时候）确认每个注册类新实例经宿主窗体流出的文本已冻结成常驻快照守卫 G10（第 2 期期末修复已建 `TestFreshFormFileTextUnchanged` 与 `tests/fixtures/customclasses/fresh-streams.txt`，覆盖第 1、2 期的类；3、4 期新拆的类在各自任务里照常跑它——夹具不该变，变了就是漂移；若 3、4 期有意改了某类窗体文件写的东西，在那个提交里用 `TY_WRITE_FRESH_STREAMS=1` 重写并在签收里写明），它抓的是 G6 一走就没人看的那块：Custom 类上的 default / stored / 构造值漂移（审查的 DEFDEL：删 `TTyCustomTabSheet.TabVisible` 的 `default True` 时 G9 与 P2 全绿）。然后删 `TestPublishedSnapshotUnchanged` 与 `tests/fixtures/customclasses/published-snapshot.txt`、删 `CPending`、`CSnapshotInputs`、`CSnapshotTypeRenames` 及 G5 里与 `CPending` 有关的分支；G1–G5、G7、G8、G9、G10 留下。重编、跑守卫 suite 与全量，全绿。单独提交 `test(controls): retire the migration snapshot; the structural guards stay`。
- [ ] **Step 7: 签收**写进本计划末尾（同 Task 11 Step 6，外加五期合计、不兼容清单的最终版）；【主控执行】通知「3.0 问题修复」会话；把「用户验收项」交给主控；发版时 CHANGELOG「变更」写一条并关联 #8（不在本分支改）。

---

## 用户验收项（全部做完一次性验收，主控交给用户）

1. 装上本分支的两个包，组件面板与之前一样（组数、图标、顺序）。
2. 任挑十个控件（含 Edit、ComboBox、PageControl、TreeView、StringGrid、ToolBar、Ribbon、GlyphButton、LucideImageList），放到窗体上，对象查看器里的属性列表与 main 上一致（名字、默认值是否加粗）；双击 Lucide 图标字体出图标浏览器。
3. 打开 3 个自己现有的项目（或示例 `controls`、`toolbar`、`grid`、`containers`），编译运行，界面、主题与行为如常；在设计器里随便改一个属性存盘，`.lfm` 的 diff 只有那一行。自己代码里若有 `is TTyButton` 这类判断，按 `docs/subclassing.md`「从 3.0 升级」改一处，确认说法够用。
4. 照 `docs/subclassing.md` 的例子写一个 `TMyTagEdit` 小包装进 IDE：面板上出现、对象查看器只显示自己发布的那几个（加上 LCL 根的 15 个）、换主题它跟着变、存盘再打开值都在。
5. 读一遍文档的「限制」与「从 3.0 升级」两节，确认说法可以直接贴给 issue #8。

---

## 后续（不在本计划）

- **#14 typeKey 链**：子类报自己的 typeKey，同时继承父类的主题规则（`TMyTagEdit` 报 `MyTagEdit`、没有它的规则时落回 `TyEdit`）。排在本计划之后；本计划只保证 typeKey 一个不变（G6）并在文档里提醒现状。
- 附录 B 的三个类在 `feat/advancechart` 合进 main 之后补拆。
- `TTyLucideImageList` / `TTyLucideIconFont` 不再发布、而不是用 Hidden 编辑器藏掉父类的属性（要改 `.lfm` 兼容，单独评估）。
- `feat/theme-builder` 合并后的 `tools/themebuilder/` 类型判断复核（N10）。

---

## 附录 A：清单（173 个注册类 + 1）

列说明：**published 声明数 / 其中新发布** 是对类自己的 published 段做静态解析的结果（含事件），精确值以 Task 0 的快照为准；**已在父类发布、带说明符的重声明** 是 3.0 下的写法——A + D7 下除 `TControl` 已 published 的名字（R3）外都变成 `R2s`，`split.py block` 的 stderr 为准；**库内类型判断** 是 `source/` + `designtime/` 里去掉注释误报后的 `is` / `as` / `InheritsFrom` 处数（逐处见附录 C）；**设计期注册** 是 `designtime/` 里出现这个类名的注册行数；**处置** 是任务号（T2–T30）、「不拆」或「排除」。

| 类 | 单元 | 当前父类 | 后代 | published 声明数 / 新发布 | 已在父类发布、带说明符的重声明 | 库内类型判断 | 设计期注册 | 处置 |
|---|---|---|---|---|---|---|---|---|
| TTyStyleController | Controller | TTyComponent | — | 7/7 | — | 0 | 7 | T27 |
| TTyNativeStyler | NativeStyler | TTyComponent | — | 6/6 | — | 0 | 0 | T27 |
| TTyButton | Button | TTyCustomControl | ColorButton, DropDownButton, MenuButton, (GlyphButtonBase), (TransferArrowButton) | 21/14 | TabStop default True | 4 | 0 | T2 |
| TTyGlyphButton | GlyphButtons | TTyGlyphButtonBase | — | 0/0 | — | 0 | 0 | T2 |
| TTyGlyphContainerButton | GlyphButtons | TTyGlyphButtonBase | — | 1/0 | GlyphLayout default glTop | 0 | 0 | T2 |
| TTySpeedButton | GlyphButtons | TTyGlyphButtonBase | — | 3/2 | TabStop default False | 3 | 0 | T2 |
| TTyDropDownButton | DropButtons | TTyButton | — | 3/3 | — | 0 | 0 | T2 |
| TTyMenuButton | DropButtons | TTyButton | RibbonAppMenu | 2/2 | — | 0 | 0 | T2 |
| TTyColorButton | ColorButton | TTyButton | — | 7/6 | Alignment default taLeftJustify | 0 | 0 | T2 |
| TTyButtonGroup | ButtonGroup | TTyCustomControl | — | 10/6 | TabStop default True | 0 | 0 | T2 |
| TTyLabel | TyLabel | TTyGraphicControl | — | 14/8 | — | 0 | 0 | T3 |
| TTyHtmlLabel | HtmlLabel | TTyCustomControl | — | 7/5 | — | 0 | 0 | T3 |
| TTyLinkLabel | LinkLabel | TTyGraphicControl | — | 13/7 | — | 0 | 0 | T3 |
| TTyShadowLabel | ShadowLabel | TTyGraphicControl | — | 14/8 | — | 0 | 0 | T3 |
| TTyGlowLabel | GlowLabel | TTyGraphicControl | — | 13/7 | — | 0 | 0 | T3 |
| TTyTag | Tag | TTyGraphicControl | — | 11/5 | — | 0 | 0 | T3 |
| TTyBadge | Badge | TTyGraphicControl | — | 9/6 | — | 0 | 0 | T3 |
| TTyEdit | Edit | TTyCustomControl | ComboEdit, MaskEdit, NumericEdit, URLEdit, (ValueEdit) | 20/14 | TabStop default True | 0 | 0 | T4 |
| TTyNumericEdit | NumericEdit | TTyEdit | CalcEdit, CurrencyEdit, FloatSpinEdit, TrackEdit | 4/4 | — | 0 | 0 | T4 |
| TTyCurrencyEdit | CurrencyEdit | TTyNumericEdit | CalcCurrencyEdit | 2/2 | — | 0 | 0 | T4 |
| TTyMaskEdit | MaskEdit | TTyEdit | — | 4/3 | Text write SetMaskedText | 0 | 0 | T4 |
| TTyURLEdit | URLEdit | TTyEdit | — | 0/0 | — | 0 | 0 | T4 |
| TTyComboEdit | ComboEdit | TTyEdit | — | 1/1 | — | 0 | 0 | T4 |
| TTyTrackEdit | TrackEdit | TTyNumericEdit | — | 0/0 | — | 0 | 0 | T4 |
| TTyCalcEdit | CalcEdit | TTyNumericEdit | — | 0/0 | — | 0 | 0 | T4 |
| TTyCalcCurrencyEdit | CalcCurrencyEdit | TTyCurrencyEdit | — | 0/0 | — | 0 | 0 | T4 |
| TTyCalculator | Calculator | TTyCustomControl | — | 8/5 | TabStop default True | 0 | 0 | T5 |
| TTyMemo | Memo | TTyCustomControl | — | 50/16 | TabStop default True | 0 | 0 | T5 |
| TTyTerminalView | Terminal | TTyCustomControl | — | 41/40 | TabStop default True | 1 | 1 | T24 |
| TTySpinEdit | SpinEdit | TTyCustomControl | — | 18/14 | TabStop default True | 0 | 0 | T5 |
| TTyFloatSpinEdit | FloatSpinEdit | TTyNumericEdit | — | 3/2 | UseThousands default False | 0 | 0 | T5 |
| TTyUpDown | UpDown | TTyGraphicControl | — | 19/17 | — | 1 | 0 | T5 |
| TTyCheckBox | CheckBox | TTyCustomControl | — | 15/8 | TabStop default True | 0 | 0 | T6 |
| TTyRadioButton | CheckBox | TTyCustomControl | — | 14/7 | TabStop default True | 2 | 0 | T6 |
| TTyToggleSwitch | ToggleSwitch | TTyCustomControl | — | 10/5 | TabStop default True | 0 | 0 | T6 |
| TTyRadioGroup | RadioGroup | TTyGroupBox | — | 10/8 | — | 0 | 0 | T13 |
| TTyCheckGroup | CheckGroup | TTyGroupBox | — | 5/5 | — | 0 | 0 | T13 |
| TTySegmented | Segmented | TTyCustomControl | — | 10/5 | TabStop default True | 0 | 0 | T6 |
| TTyComboBox | ComboBox | TTyCustomControl | AdvancedComboBox, CheckComboBox, ColorBox, ComboBoxEx, FilterComboBox, FontComboBox, FontSizeComboBox, MRUComboBox, OfficeComboBox, ShellComboBox | 24/21 | TabStop default True | 1 | 0 | T7 |
| TTyMRUComboBox | MRUComboBox | TTyComboBox | — | 1/1 | — | 0 | 0 | T7 |
| TTyComboBoxEx | ComboBoxEx | TTyComboBox | — | 2/2 | — | 3 | 0 | T7 |
| TTyOfficeComboBox | OfficeComboBox | TTyComboBox | — | 0/0 | — | 0 | 0 | T7 |
| TTyAdvancedComboBox | AdvancedComboBox | TTyComboBox | — | 1/1 | — | 1 | 0 | T7 |
| TTyCheckComboBox | CheckComboBox | TTyComboBox | — | 4/4 | — | 1 | 0 | T7 |
| TTyListBox | ListBox | TTyCustomControl | AdvancedListBox, CheckListBox, ColorListBox, FontListBox, OfficeListBox, ValueListEditor, (ComboPopupList) | 16/13 | TabStop default True | 0 | 0 | T15 |
| TTyCheckListBox | CheckListBox | TTyListBox | (CheckComboPopupList), (GridFilterList) | 2/2 | — | 3 | 0 | T15 |
| TTyOfficeListBox | OfficeListBox | TTyListBox | — | 0/0 | — | 0 | 0 | T15 |
| TTyAdvancedListBox | AdvancedListBox | TTyListBox | — | 1/1 | — | 0 | 0 | T15 |
| TTyValueListEditor | ValueListEditor | TTyListBox | — | 8/8 | — | 0 | 0 | T15 |
| TTyTransfer | Transfer | TTyCustomControl | — | 13/10 | — | 0 | 0 | T16 |
| TTyTreeSelect | TreeSelect | TTyCustomControl | — | 15/9 | TabStop default True | 1 | 1 | T16 |
| TTyCascader | Cascader | TTyCustomControl | — | 12/8 | TabStop default True | 2 | 1 | T16 |
| TTyColorBox | ColorBox | TTyComboBox | ColorComboBox | 7/6 | Style: TTyColorBoxStyle read FPaletteStyle write SetPaletteStyle | 1 | 0 | T8 |
| TTyColorComboBox | ColorComboBox | TTyColorBox | — | 1/1 | — | 0 | 0 | T8 |
| TTyColorListBox | ColorListBox | TTyListBox | — | 8/8 | — | 0 | 0 | T15 |
| TTyColorGrid | ColorGrid | TTyCustomControl | — | 8/5 | TabStop default True | 0 | 0 | T24 |
| TTyLColorPicker | LColorPicker | TTyCustomControl | — | 9/6 | TabStop default True | 0 | 0 | T24 |
| TTyHSColorPicker | HSColorPicker | TTyCustomControl | — | 9/6 | TabStop default True | 0 | 0 | T24 |
| TTyFontComboBox | FontComboBox | TTyComboBox | — | 0/0 | — | 0 | 0 | T8 |
| TTyFontListBox | FontListBox | TTyListBox | — | 0/0 | — | 0 | 0 | T15 |
| TTyFontSizeComboBox | FontSizeComboBox | TTyComboBox | — | 0/0 | — | 0 | 0 | T8 |
| TTyFilterComboBox | FilterComboBox | TTyComboBox | — | 4/4 | — | 0 | 1 | T8 |
| TTyShellComboBox | ShellComboBox | TTyComboBox | — | 2/2 | — | 1 | 1 | T8 |
| TTyGauge | Gauge | TTyGraphicControl | — | 15/12 | — | 0 | 0 | T9 |
| TTyMeter | Meter | TTyGraphicControl | — | 14/11 | — | 0 | 0 | T9 |
| TTyLevelMeter | LevelMeter | TTyGraphicControl | — | 14/11 | — | 0 | 0 | T9 |
| TTyDial | Dial | TTyCustomControl | — | 15/11 | TabStop default True | 0 | 0 | T10 |
| TTyGearDial | GearDial | TTyCustomControl | — | 16/12 | TabStop default True | 0 | 0 | T10 |
| TTyAnalogClock | AnalogClock | TTyGraphicControl | — | 9/6 | — | 0 | 0 | T10 |
| TTyCircularProgress | CircularProgress | TTyGraphicControl | — | 12/9 | — | 0 | 0 | T9 |
| TTyActivityIndicator | ActivityIndicator | TTyGraphicControl | — | 7/5 | — | 0 | 0 | T9 |
| TTyActivityBar | ActivityBar | TTyGraphicControl | — | 5/3 | — | 0 | 0 | T9 |
| TTyGearActivityIndicator | GearActivityIndicator | TTyGraphicControl | — | 6/4 | — | 0 | 0 | T9 |
| TTySparkline | Sparkline | TTyGraphicControl | — | 10/7 | — | 0 | 0 | T9 |
| TTyRating | Rating | TTyCustomControl | — | 11/7 | TabStop default True | 0 | 0 | T10 |
| TTyTrackBar | TrackBar | TTyCustomControl | — | 18/14 | TabStop default True | 0 | 0 | T10 |
| TTyProgressBar | ProgressBar | TTyGraphicControl | — | 13/11 | — | 0 | 0 | T9 |
| TTyScrollBar | ScrollBar | TTyCustomControl | — | 18/15 | TabStop default True | 0 | 0 | T20 |
| TTyStatusBar | StatusBar | TTyCustomControl | — | 11/9 | — | 1 | 0 | T20 |
| TTyToolBar | ToolBar | TTyCustomControl | ToolBarEx | 17/15 | — | 1 | 0 | T20 |
| TTyToolButton | ToolBar | TTyGlyphButtonBase | — | 10/7 | TabStop default False; GlyphLayout stored FGlyphLayoutExplicit nodefault | 10 | 0 | T20（T2 先补发布段） |
| TTyToolSeparator | ToolBar | TTyCustomControl | — | 3/1 | — | 0 | 0 | T20 |
| TTyToolBarEx | ToolBarEx | TTyToolBar | — | 1/0 | — | 0 | 0 | T20 |
| TTyControlBar | ControlBar | TTyPanel | CoolBar | 4/4 | — | 0 | 0 | T12 |
| TTyCoolBar | CoolBar | TTyControlBar | — | 9/5 | — | 1 | 0 | T12 |
| TTyAlert | Alert | TTyGraphicControl | — | 15/8 | — | 0 | 0 | T20 |
| TTyPagination | Pagination | TTyCustomControl | — | 14/8 | TabStop default True | 0 | 0 | T20 |
| TTySteps | Steps | TTyCustomControl | — | 12/8 | — | 0 | 0 | T20 |
| TTyBreadcrumb | Breadcrumb | TTyGraphicControl | — | 11/4 | — | 0 | 0 | T20 |
| TTyHeaderControl | HeaderControl | TTyCustomControl | — | 6/5 | TabStop default True | 0 | 0 | T17 |
| TTyPanel | Panel | TTyCustomControl | ControlBar, ExPanel, GridPanel, PaintPanel, RelativePanel, ScrollBox | 18/16 | — | 0 | 0 | T12 |
| TTyGroupBox | GroupBox | TTyCustomControl | CheckGroup, RadioGroup, ToolGroupPanel | 17/15 | — | 0 | 0 | T13 |
| TTyBevel | Bevel | TTyGraphicControl | — | 7/4 | — | 0 | 0 | T13 |
| TTyDivider | Divider | TTyGraphicControl | — | 7/5 | — | 0 | 0 | T13 |
| TTySplitter | Splitter | TTyCustomControl | — | 9/7 | — | 0 | 0 | T13 |
| TTyPaintPanel | PaintPanel | TTyPanel | — | 3/1 | — | 0 | 0 | T12 |
| TTySizeBox | SizeBox | TTyGraphicControl | — | 5/2 | — | 0 | 0 | T13 |
| TTyScrollBox | ScrollBox | TTyPanel | ScrollPanel | 6/2 | — | 0 | 0 | T12 |
| TTyScrollPanel | ScrollPanel | TTyScrollBox | — | 3/3 | — | 0 | 0 | T12 |
| TTyExPanel | ExPanel | TTyPanel | — | 5/5 | — | 0 | 0 | T12 |
| TTyGridPanel | GridPanel | TTyPanel | — | 5/5 | — | 1 | 0 | T12 |
| TTyRelativePanel | RelativePanel | TTyPanel | — | 5/1 | — | 0 | 0 | T12 |
| TTyToolGroupPanel | ToolGroupPanel | TTyGroupBox | — | 4/2 | — | 0 | 0 | T13 |
| TTyListGroupPanel | ListGroupPanel | TTyCustomControl | — | 16/13 | TabStop default True | 3 | 1 | T14 |
| TTyPageControl | PageControl | TTyCustomTabStrip | — | 14/14 | — | 5 | 1 | T14 |
| TTyTabSheet | TabSheet | TTyCustomControl | — | 15/7 | Left stored False; Top stored False; Width stored False; Height stored False; TabOrder stored False; Visible stored False | 1 | 0 | T14 |
| TTyTabSet | TabSet | TTyCustomTabStrip | — | 5/5 | — | 0 | 0 | T14 |
| TTyTitleBar | Form | TTyCustomControl | — | 8/8 | — | 1 | 0 | T22 |
| TTyCard | Card | TTyCustomControl | — | 8/6 | — | 0 | 0 | T13 |
| TTyEmpty | Empty | TTyCustomControl | — | 12/6 | — | 0 | 0 | T13 |
| TTyToolWindowBar | ToolWindows | TTyCustomControl | — | 13/11 | Width stored WidthIsStored; Height stored HeightIsStored | 15 | 1 | T25 |
| TTyToolWindowManager | ToolWindows.Manager | TTyCustomToolWindowManager | — | 4/4 | — | 1 | 0 | 不拆（Q4） |
| TTyTreeView | TreeView | TTyCustomControl | (ShellTreeLink), (TreeSelectTree) | 66/56 | TabStop default True | 5 | 1 | T17 |
| TTyListView | ListView | TTyCustomControl | ShellListView | 43/40 | TabStop default True | 1 | 0 | T17 |
| TTyShellListView | ShellListView | TTyListView | — | 13/13 | — | 0 | 1 | T17 |
| TTyShellTreeView | ShellTreeView | TTyShellTreeLink | — | 11/11 | — | 0 | 1 | T17 |
| TTyPreviewBox | PreviewBox | TTyCustomControl | — | 8/4 | — | 0 | 0 | T23 |
| TTyImageView | ImageView | TTyCustomControl | — | 19/14 | TabStop default True | 0 | 0 | T23 |
| TTyCalendar | Calendar | TTyCustomControl | — | 21/17 | TabStop default True | 0 | 0 | 排除（T1 插块） |
| TTyDateTimePicker | DateTimePicker | TTyCustomControl | — | 30/24 | TabStop default True | 0 | 0 | 排除（T1 插块） |
| TTyDrawGrid | Grid | TTyCustomGrid | StringGrid | 1/1 | — | 0 | 0 | T18 |
| TTyStringGrid | Grid | TTyDrawGrid | — | 55/55 | — | 0 | 0 | T18 |
| TTyMenuBar | Menu | TTyCustomControl | — | 7/4 | TabStop default True | 0 | 0 | T22 |
| TTyPopupMenu | Menu | TPopupMenu | ImagesMenu | 2/2 | — | 0 | 1 | 不拆（LCL） |
| TTyImagesMenu | Menu | TTyPopupMenu | MenuEx | 1/1 | — | 0 | 0 | 不拆（LCL） |
| TTyMenuEx | Menu | TTyImagesMenu | — | 2/2 | — | 0 | 0 | 不拆（LCL） |
| TTyRibbon | Ribbon | TTyCustomTabStrip | — | 10/9 | Align default alTop | 2 | 0 | T21（T14 先补发布段） |
| TTyRibbonPage | Ribbon | TTyCustomControl | — | 4/2 | — | 3 | 1 | T21 |
| TTyRibbonGroup | Ribbon | TTyCustomControl | — | 7/5 | — | 3 | 0 | T21 |
| TTyRibbonAppMenu | RibbonAppMenu | TTyMenuButton | — | 5/5 | — | 0 | 0 | T21 |
| TTyRibbonQuickAccess | RibbonQuickAccess | TTyCustomControl | — | 6/4 | — | 0 | 0 | T21 |
| TTyRibbonGallery | RibbonGallery | TTyCustomControl | — | 11/8 | TabStop default True | 0 | 0 | T21 |
| TTyRibbonBackstage | RibbonBackstage | TTyCustomControl | — | 16/13 | TabStop default True | 0 | 0 | T21 |
| TTyIconFont | IconFont | TTyComponent | (IconPackFont) | 4/4 | — | 3 | 4 | T28 |
| TTyLucideIconFont | Icons.Lucide | TTyIconPackFont | — | 1/1 | — | 0 | 4 | T28 |
| TTyLucideImageList | Icons.Lucide | TTyVirtualImageList | — | 2/1 | IconFont stored False | 0 | 3 | T28 |
| TTyCharImage | CharImage | TTyGraphicControl | — | 11/6 | — | 0 | 1 | T23 |
| TTyGlyphImageList | GlyphImageList | TTyComponent | — | 4/4 | — | 0 | 0 | T28 |
| TTyImage | Image | TTyGraphicControl | — | 22/17 | — | 0 | 0 | T23 |
| TTyImageCollection | ImageCollection | TTyComponent | — | 1/1 | — | 1 | 2 | T28 |
| TTyVirtualImageList | ImageCollection | TCustomImageList | LucideImageList | 7/7 | — | 10 | 2 | T28 |
| TTyHint | Hint | TTyComponent | — | 2/2 | — | 0 | 0 | T29 |
| TTyBalloonHint | BalloonHint | TTyComponent | — | 5/5 | — | 0 | 0 | T29 |
| TTyPopover | Popover | TTyComponent | — | 11/11 | — | 1 | 1 | T29 |
| TTyShape | Shape | TTyGraphicControl | — | 8/5 | — | 0 | 0 | T23 |
| TTyStarShape | StarShape | TTyGraphicControl | — | 9/6 | — | 0 | 0 | T23 |
| TTyArrow | Arrow | TTyGraphicControl | — | 10/7 | — | 0 | 0 | T23 |
| TTyChart | Chart | TTyGraphicControl | — | 15/11 | — | 0 | 0 | T23 |
| TTyAdvanceChart | AdvanceChart | TTyCustomControl | — | 20/6 | TabStop default False | 1 | 2 | 排除（T1 插块） |
| TTyMessage | Dialogs | TTyComponent | — | 7/7 | — | 1 | 0 | T30 |
| TTyInputDialog | Dialogs | TTyComponent | — | 6/6 | — | 1 | 0 | T30 |
| TTyPasswordDialog | Dialogs | TTyComponent | — | 7/7 | — | 1 | 0 | T30 |
| TTyTextDialog | Dialogs | TTyComponent | — | 6/6 | — | 1 | 0 | T30 |
| TTySelectValueDialog | Dialogs | TTyComponent | — | 7/7 | — | 1 | 0 | T30 |
| TTySelectPathDialog | Dialogs.SelectPath | TTyComponent | — | 6/6 | — | 1 | 2 | 不拆（LCL） |
| TTyColorDialog | Dialogs.Color | TTyComponent | — | 6/6 | — | 1 | 0 | 不拆（LCL） |
| TTyFontDialog | Dialogs.Font | TTyComponent | — | 5/5 | — | 1 | 0 | 不拆（LCL） |
| TTyFindDialog | Dialogs.Find | TTyComponent | ReplaceDialog | 7/7 | — | 1 | 0 | 不拆（LCL） |
| TTyReplaceDialog | Dialogs.Find | TTyFindDialog | — | 2/2 | — | 0 | 0 | 不拆（LCL） |
| TTyProgressDialog | Dialogs.Progress | TTyComponent | — | 10/10 | — | 1 | 0 | T30 |
| TTyAboutDialog | Dialogs.About | TComponent | — | 10/10 | — | 1 | 0 | T30 |
| TTyOpenDialog | Dialogs.FileDialog | TTyCustomFileDialog | OpenPictureDialog, OpenPreviewDialog | 0/0 | — | 0 | 0 | 不拆（LCL） |
| TTySaveDialog | Dialogs.FileDialog | TTyCustomFileDialog | SavePictureDialog, SavePreviewDialog | 0/0 | — | 0 | 0 | 不拆（LCL） |
| TTyOpenPictureDialog | Dialogs.FileDialog | TTyOpenDialog | — | 0/0 | — | 0 | 0 | 不拆（LCL） |
| TTySavePictureDialog | Dialogs.FileDialog | TTySaveDialog | — | 0/0 | — | 0 | 0 | 不拆（LCL） |
| TTyOpenPreviewDialog | Dialogs.FileDialog | TTyOpenDialog | — | 0/0 | — | 0 | 0 | 不拆（LCL） |
| TTySavePreviewDialog | Dialogs.FileDialog | TTySaveDialog | — | 0/0 | — | 0 | 0 | 不拆（LCL） |
| TTyNotification | Notification | TTyComponent | — | 11/11 | — | 0 | 0 | T29 |
| TTyIconBrowserDialog | Dialogs.IconBrowser | TTyComponent | — | 6/6 | — | 1 | 0 | T30 |
| TTyGridCell | GridPanel | TTyCustomControl | — | 8/5 | — | 1 | 1 | T12 |
| TTyToolWindow | ToolWindows | TTyCustomControl | — | 18/10 | Controller stored False; Left stored False; Top stored False; Width stored False; Height stored False; TabOrder stored False; Visible stored False | 22 | 3 | T25 |
| TTyToolWindowActions | ToolWindows | TTyCustomControl | — | 5/0 | Controller stored False; Left stored IsBoundsStored; Top stored IsBoundsStored; Width stored IsBoundsStored; Height stored IsBoundsStored | 6 | 2 | T25 |
| TTyFormSurface | FormSurface | TTyCustomControl | — | 4/3 | — | 1 | 38 | T22 |
| TTyScrollContent（只 RegisterClass） | ScrollContent | TTyCustomControl | — | 0/0 | — | 1 | 0 | T12 |

---

## 附录 B：排除的单元与补拆（本计划不执行）

| 类 | 单元 | 为什么排除 | 何时补拆 |
|---|---|---|---|
| `TTyAdvanceChart` | `AdvanceChart.pas` | 用户已定 AdvChart 不拆；`feat/advancechart` / `tmp/an1` 有 83–84 个未进 main 的提交改它，published 属性还在变（main 20 行、分支 27 行） | `feat/advancechart` 合进 main 之后，用户另行决定 |
| `TTyCalendar` | `Calendar.pas` | `feat/advancechart` 改它（删 111 行） | 同上，合并后 |
| `TTyDateTimePicker` | `DateTimePicker.pas` | 同上（+5 行） | 同上 |

三个类在 Task 1 都插了基类块（Q3），所以 D7 之后照常可用。补拆时：照 Task 0 Step 3 重新核实分支；临时恢复快照测试，用 `TY_WRITE_GOLDEN_CLASS` 只拍这 3 个类（Custom 父类都是 `TTyCustomControl`），按「每个类的标准步骤」拆，D3 的 LCL 对应：Calendar ↔ `TCustomCalendar`（`calendar.pp:78`，public）、DateTimePicker ↔ `TCustomDateTimePicker`（`components/datetimectrls/datetimepicker.pas:150`）、AdvanceChart 无（public）；G1–G5、G7、G8 自动生效；`TTyAdvanceChart` 的组件编辑器与 `Option` 属性编辑器照 D2，`Design.AdvChart.Editor.pas:710` 的 `is TTyAdvanceChart` 属设计期，保持。

---

## 附录 C：类型判断逐处结论（行号以 `a0606352` 为准）

扫描方法：scratchpad `split/scan.py`（去掉注释与字符串后匹配 `is X`、`as X`、`InheritsFrom(X)`、`ClassType =`、硬转 `X(`，X 取全部被拆类与中间类）+ `split/upcast.py`（隐式向上转型）。全仓库（`source`、`designtime`、`tests`、`examples`、`tools`）对被拆类的判断与硬转共 310 + 非可视 / 新拆类约 250 行，下面按结论分段列出；注释里提到类名的（`Badge.pas:67`、`TyLabel.pas:331` 等）不是判断，不列。

### C-0 父类变化全表（55 个派生类；G7 的 `CChain` 与文档「从 3.0 升级」的表就是这张）

「翻转」= 对某个原祖先**最终类**的 `is` 从 True 变 False（列出那几个最终类）；「—」= 原父类是中间类、对最终类的答案不变。

| 控件 | 3.0 父类 | 4.0 父类（即 `TTyCustomXxx` 的父类） | 不再是谁的后代 |
|---|---|---|---|
| TTyDropDownButton | TTyButton | TTyCustomButton | TTyButton |
| TTyMenuButton | TTyButton | TTyCustomButton | TTyButton |
| TTyColorButton | TTyButton | TTyCustomButton | TTyButton |
| TTyGlyphButton | TTyGlyphButtonBase | TTyGlyphButtonBase（← TTyCustomButton） | TTyButton |
| TTyGlyphContainerButton | TTyGlyphButtonBase | TTyGlyphButtonBase | TTyButton |
| TTySpeedButton | TTyGlyphButtonBase | TTyGlyphButtonBase | TTyButton |
| TTyToolButton | TTyGlyphButtonBase | TTyGlyphButtonBase | TTyButton |
| TTyRibbonAppMenu | TTyMenuButton | TTyCustomMenuButton | TTyMenuButton、TTyButton |
| TTyNumericEdit | TTyEdit | TTyCustomEdit | TTyEdit |
| TTyMaskEdit | TTyEdit | TTyCustomEdit | TTyEdit |
| TTyURLEdit | TTyEdit | TTyCustomEdit | TTyEdit |
| TTyComboEdit | TTyEdit | TTyCustomEdit | TTyEdit |
| TTyCurrencyEdit | TTyNumericEdit | TTyCustomNumericEdit | TTyNumericEdit、TTyEdit |
| TTyTrackEdit | TTyNumericEdit | TTyCustomNumericEdit | TTyNumericEdit、TTyEdit |
| TTyCalcEdit | TTyNumericEdit | TTyCustomNumericEdit | TTyNumericEdit、TTyEdit |
| TTyFloatSpinEdit | TTyNumericEdit | TTyCustomNumericEdit | TTyNumericEdit、TTyEdit |
| TTyCalcCurrencyEdit | TTyCurrencyEdit | TTyCustomCurrencyEdit | TTyCurrencyEdit、TTyNumericEdit、TTyEdit |
| TTyMRUComboBox | TTyComboBox | TTyCustomComboBox | TTyComboBox |
| TTyComboBoxEx | TTyComboBox | TTyCustomComboBox | TTyComboBox |
| TTyOfficeComboBox | TTyComboBox | TTyCustomComboBox | TTyComboBox |
| TTyAdvancedComboBox | TTyComboBox | TTyCustomComboBox | TTyComboBox |
| TTyCheckComboBox | TTyComboBox | TTyCustomComboBox | TTyComboBox |
| TTyColorBox | TTyComboBox | TTyCustomComboBox | TTyComboBox |
| TTyFontComboBox | TTyComboBox | TTyCustomComboBox | TTyComboBox |
| TTyFontSizeComboBox | TTyComboBox | TTyCustomComboBox | TTyComboBox |
| TTyFilterComboBox | TTyComboBox | TTyCustomComboBox | TTyComboBox |
| TTyShellComboBox | TTyComboBox | TTyCustomComboBox | TTyComboBox |
| TTyColorComboBox | TTyColorBox | TTyCustomColorBox | TTyColorBox、TTyComboBox |
| TTyCheckListBox | TTyListBox | TTyCustomListBox | TTyListBox |
| TTyOfficeListBox | TTyListBox | TTyCustomListBox | TTyListBox |
| TTyAdvancedListBox | TTyListBox | TTyCustomListBox | TTyListBox |
| TTyValueListEditor | TTyListBox | TTyCustomListBox | TTyListBox |
| TTyColorListBox | TTyListBox | TTyCustomListBox | TTyListBox |
| TTyFontListBox | TTyListBox | TTyCustomListBox | TTyListBox |
| TTyRadioGroup | TTyGroupBox | TTyCustomGroupBox | TTyGroupBox |
| TTyCheckGroup | TTyGroupBox | TTyCustomGroupBox | TTyGroupBox |
| TTyToolGroupPanel | TTyGroupBox | TTyCustomGroupBox | TTyGroupBox |
| TTyPaintPanel | TTyPanel | TTyCustomPanel | TTyPanel |
| TTyExPanel | TTyPanel | TTyCustomPanel | TTyPanel |
| TTyGridPanel | TTyPanel | TTyCustomPanel | TTyPanel |
| TTyRelativePanel | TTyPanel | TTyCustomPanel | TTyPanel |
| TTyScrollBox | TTyPanel | TTyCustomPanel | TTyPanel |
| TTyControlBar | TTyPanel | TTyCustomPanel | TTyPanel |
| TTyScrollPanel | TTyScrollBox | TTyCustomScrollBox | TTyScrollBox、TTyPanel |
| TTyCoolBar | TTyControlBar | TTyCustomControlBar | TTyControlBar、TTyPanel |
| TTyToolBarEx | TTyToolBar | TTyCustomToolBar | TTyToolBar |
| TTyShellTreeView | TTyShellTreeLink | TTyShellTreeLink（← TTyCustomTreeView） | TTyTreeView |
| TTyShellListView | TTyListView | TTyCustomListView | TTyListView |
| TTyPageControl | TTyCustomTabStrip | TTyCustomTabStrip | — |
| TTyTabSet | TTyCustomTabStrip | TTyCustomTabStrip | — |
| TTyRibbon | TTyCustomTabStrip | TTyCustomTabStrip | — |
| TTyDrawGrid | TTyCustomGrid | TTyCustomGrid | — |
| TTyStringGrid | TTyDrawGrid | TTyCustomDrawGrid | TTyDrawGrid |
| TTyLucideIconFont | TTyIconPackFont | TTyIconPackFont（← TTyCustomIconFont） | TTyIconFont |
| TTyLucideImageList | TTyVirtualImageList | TTyCustomVirtualImageList | TTyVirtualImageList |

挂在不拆 / 排除的类下面的派生类：只有整族不拆的家族内部（`TTyImagesMenu` / `TTyMenuEx` 在 `TTyPopupMenu` 下，`TTyReplaceDialog` 在 `TTyFindDialog` 下，图片 / 预览对话框在 `TTyOpenDialog` / `TTySaveDialog` 下），父类不变、不涉及 A；排除的 `TTyAdvanceChart`、`TTyCalendar`、`TTyDateTimePicker` 没有后代；`TTyToolWindowManager`（Q4）没有后代。

中间类：`TTyGlyphButtonBase` 3.0 `class(TTyButton)` → 4.0 `class(TTyCustomButton)`；`TTyShellTreeLink` `class(TTyTreeView)` → `class(TTyCustomTreeView)`；`TTyIconPackFont` `class(TTyIconFont)` → `class(TTyCustomIconFont)`；`TTyCustomTabStrip`、`TTyCustomGrid` 父类不变、不再发布。

### C-1 A 下必改（内置派生控件的答案翻转）

| 编号 | 位置 | 现在 | 翻转的是谁 | 改成 | 任务 | 改回最终类时必须红的测试 |
|---|---|---|---|---|---|---|
| A2-1 | `source/tyControls.ToolBar.pas:1838`（+ `ApplyToButton` :416/1713） | `kids[i] is TTyButton` + 强转 | GlyphButton、SpeedButton、ToolButton、DropDown / Menu / Color 按钮 | `TTyCustomButton` | T2 | S2-1 |
| A2-2 | `ToolBarEx.pas:236, 248-253` | `is TTyButton` + 强转（扁平样式） | 同上 | `TTyCustomButton` | T2 | S2-2 |
| A2-3 | `ToolBarEx.pas:393-396, 445-446` | `is TTyButton` + 强转（溢出弹层包装 OnClick） | 同上 | `TTyCustomButton` | T2 | S2-3（或「—」：与 S2-2 同一判断） |
| A2-4 | `examples/toolbar/umain.pas:162` `ToolClicked` | `(Sender as TTyButton).Caption` | 挂在 3 个 GlyphButton、4 个 ToolButton 上，A 下抛 `EInvalidCast` | `TTyCustomButton` | T2 | —：示例无测试；【主控】冒烟手点（Task 11 Step 4） |
| A2-5 | `tools/gallery/tyGalleryCapture.pas:157` | `(c is TTyButton) and (TTyButton(c).Caption = ACaption)` | 示例窗体上的 GlyphButton 找不到 | `TTyCustomButton` | T2 | —：工具无测试；下次跑 gallery 时核对 |
| A4-1 | `tests/test.calcedit.pas:40, 60` | `e is TTyNumericEdit` / `e is TTyCurrencyEdit` | CalcEdit / CalcCurrencyEdit | 改写成 `is TTyCustomNumericEdit` + `not ... is TTyNumericEdit`（货币同理） | T4 | 它自己：把 `TTyCustomCalcEdit` 改挂回 `TTyNumericEdit`，第二句红 |
| A4-2 | `examples/grid/umain.pas:1332-1334` | `AEditor is TTyEdit` + `TTyEdit(AEditor)` | 网格建的 `TTyCalcEdit`、`TTyMaskEdit`（`Grid.pas:8024/8031`） | `TTyCustomEdit` | T4 | —：示例无测试；【主控】冒烟（Task 11 Step 4） |
| A7-1 | `ComboBox.pas:565-569`（`TyComboOwnerOf`，调用处 :575/583/590/597） | `AList.Owner is TTyComboBox` + 强转 | 10 个派生组合框的弹层 | `TTyCustomComboBox`（返回类型一起） | T7 | S7-1 |
| ~~A8-1~~ | — | — | **挪到 C-2（第 0、1 期期末修复）**：执行中核实不是翻转，见 C-2 的 C8-1 行 | — | — | — |
| A8-2 | `tests/test.parity.combo.pas:1647-1651`（+ 参数 `C: TTyComboBox` :1638） | `C is TTyColorBox` + 强转 | 传进来的 `TTyColorComboBox` | `TTyCustomColorBox` | T8 | test.parity.combo 里对 ColorComboBox 行数的断言（必要时补强） |
| A8-3 | `tests/test.colorbox.pas:97-99`；源码注释 `ColorBox.pas:179/503` | `TTyComboBox(c).Style` | ColorBox 不再是 TTyComboBox（硬转成了类型假话） | `TTyCustomComboBox(c).Style` | T8 | —：硬转无运行时差异，审查覆盖 |
| A15-1 | `tests/test.scrollbar.autohide.pas:1415` | `TTyValueListEditor.InheritsFrom(TTyListBox)` | ValueListEditor | `InheritsFrom(TTyCustomListBox)` + `not InheritsFrom(TTyListBox)` | T15 | 它自己：把 `TTyCustomValueListEditor` 改挂回 `TTyListBox`，第二句红 |
| ~~A17-1~~ | — | — | **挪到 C-2（第 2 期执行中核实）**：ShellTreeView 拒绝条目模型，走不到这条路，见 C-2 的 C17-1 行 | — | — | — |
| A17-2 | `TreeView.pas:1629-1636` | `FOwner is TTyTreeView` + 强转 | ShellTreeView 的节点集合通知（执行时核实：翻转的是「往 ShellTreeView 的 `Items` 加条目时它当场拒绝条目模型」——旧判断下它听不到自己集合的改动） | `TTyCustomTreeView` | T17 | S17-2（`TestShellTreeViewHearsItsNodeCollection`；另 `TestThirdTreeViewNodeCollectionBuildsTheTree`） |
| A17-3 | `ListView.pas:849-854` | `own is TTyListView` + 强转 | ShellListView 的项图标（项按 `ImageName` 对宿主的 Large / Small 列表解析） | `TTyCustomListView` | T17 | S17-3 |
| A17-4 | `designtime/tyControls.Design.CompEditors.pas:1153-1157`（注释） | 「also covers TTyShellTreeView」 | 组件编辑器不再落到 ShellTreeView（那里无动词，行为不变） | 改写注释 | T17 | —：注释 |
| A20-1 | `ToolBar.pas:924-925`（+ `GetToolBar` :121/922、11 处 `bar: TTyToolBar`） | `Parent is TTyToolBar` + 强转 | ToolBarEx 上的工具按钮 | `TTyCustomToolBar` | T20 | S20-1 |
| A28-1 | `ImageDraw.pas:95, 101-105, 112-113, 120-121, 162, 209-213, 250-254, 284-288, 330-335` | `AList is TTyVirtualImageList` + 强转（9 处判断） | LucideImageList：退回光栅、按名字取图失效 | `TTyCustomVirtualImageList` | T28 | S28-1 |
| A28-2 | `designtime/…CompEditors.pas:282-286`（+ 注册 :1161） | `is TTyIconFont` / `is TTyVirtualImageList` + 强转 | Lucide 字体 / 列表的图标浏览器 | Custom 类；注册行显式加两个 Lucide 类 | T28 | —：IDE 内才走得到；用户验收项 2 |
| A28-3 | `designtime/…PropEditors.pas:478-484, 506-516` | `fnt is TTyIconFont` + 强转 | 宿主挂的是 Lucide 字体时 GlyphName 编辑器 | `TTyCustomIconFont` | T28 | —：IDE 内才走得到；审查覆盖 |

### C-2 为第三方放宽（对内置控件答案不变）

| 编号 | 位置 | 现在 | 语义 | 改成 | 测试 |
|---|---|---|---|---|---|
| C1-1 | `GlyphButtons.pas:962, 964, 987, 989, 1008-1010` | `is TTySpeedButton` + 强转（~~`FindDownButton` 返回类型 `:361` 照 R7-4 保持~~ 期末修复：`FindDownButton` 返回 `TTyCustomSpeedButton`，照 LCL `buttons.pp:409`，删前向声明与两处强转） | 同组互斥 | `TTyCustomSpeedButton` | S1-1（含第三方成员按下时 `FindDownButton` 交出它、不假定 `is TTySpeedButton`，过程变量钉住返回类型） |
| C4-1 | `UpDown.pas:633-634` | `is TTyUpDown` | 关联互斥 | `TTyCustomUpDown` | S4-2 |
| C5-1 | `CheckBox.pas:545-547` | `is TTyRadioButton` | 单选同组互斥 | `TTyCustomRadioButton` | S5-1 |
| C6-2 | `ComboBoxEx.pas:425, 557, 574-576` | `is TTyComboBoxEx` | 项集合 / 弹层找宿主 | `TTyCustomComboBoxEx` | S7-2 |
| C6-3 | `AdvancedComboBox.pas:98-100` | `Owner is TTyAdvancedComboBox` | 弹层取 Images | `TTyCustomAdvancedComboBox` | 或「—」 |
| C6-4 | `CheckComboBox.pas:194-199` | `Owner is TTyCheckComboBox` | 弹层找宿主 | `TTyCustomCheckComboBox` | 或「—」 |
| C6-5（原在 C-3，第 2 期期末修复改归此处） | `CheckComboBox.pas:348-349, 554-555, 565-566`（修复时的行号 `:427-428, 633-634, 644-645`），连同 `PushChecksToList` / `PullChecksFromList` / `PullChecksForTest` 的参数 | `is TTyCheckListBox` + 强转 | 下拉时把勾选推进弹层、弹层上点勾回写组合框、`SetState` 同步开着的弹层。原判「弹层是自己建的 `TTyCheckComboPopupList`」，但 `CreatePopupList` 是 virtual、Task 15 起返回 `TTyCustomListBox`，派生组合框可以交出自己的 `TTyCustomCheckListBox`，旧判断下三件事全部静默不做——对内置控件答案不变，放宽是为第三方。弹层的 `OnClickCheck` 改由组合框在 `DropDown` 里补接（弹层没有自己的处理过程时）：第三方的 `CreatePopupList` 够不着私有的 `PopupCheckClick` | `TTyCustomCheckListBox` | `TestCheckComboDropsAThirdPartyCheckList`（P2） |
| C7-2 | `ShellComboBox.pas:200-202` | `Owner is TTyShellComboBox` | 弹层找宿主 | `TTyCustomShellComboBox` | S8-2（或「—」） |
| C8-1（原 A8-1） | `ColorBox.pas:468-470` | `Owner is TTyColorBox` + 强转 | 共享的 `TTyColorPopupList` 从宿主取色块几何与伪行颜色。原以为 `TTyColorComboBox` 会翻转，执行中核实：它的下拉是自己的 `TTyColorMorePopupList`，3.0 起就不读宿主几何、从不走这条判断——对内置控件答案不变，放宽是为第三方 `TTyCustomColorBox` 子类 | `TTyCustomColorBox` | S8-1（见证改为第三方模拟类 `TThirdColorBox`） |
| C11-1 | `GridPanel.pas:725-726` | `AParent is TTyGridPanel` | 格认宿主 | `TTyCustomGridPanel` | S12-1 |
| C11-2 | `CoolBar.pas:896` | `GetOwner is TTyCoolBar` | bands 集合找宿主 | `TTyCustomCoolBar` | S12-3（或「—」） |
| C11-3 | `GridPanel.pas:566`；`Form.pas:2192-2193` | `is TTyGridCell` / `is TTyFormSurface` | 格的归属 / 窗体认内容宿主（D4–D6 改为拆） | Custom 类 | 审查覆盖（与 S12-1 / Task 22 同一路径） |
| C12-1 | `ScrollBox.pas:366-368` | `AControl is TTyScrollContent` | 盒子认视口 | `TTyCustomScrollContent` | S12-2 |
| C13-1 | `TabSheet.pas:240, 243, 247-248, 274-275, 284-287` | `is TTyPageControl` + 强转 | 页认宿主 | `TTyCustomPageControl`（access 类） | S14-1 |
| C13-2 | `PageControl.pas:382-383` | `AComponent is TTyTabSheet` | 宿主处理页的释放 | `TTyCustomTabSheet` | S14-2 |
| C17-1（原 A17-1） | `TreeView.pas:1392-1393` | `nodes.GetOwner is TTyTreeView` + 强转 | 节点按 `ImageName` 取树的图片列表。原以为 `TTyShellTreeView` 会翻转，执行中核实：它覆写 `SupportsItemModel = False`、条目层当场拒绝，从不走这条路——对内置控件答案不变，放宽是为第三方 `TTyCustomTreeView` 子类 | `TTyCustomTreeView` | S17-1（见证改为 `TThirdTreeView`） |
| C19-2 | `ToolBar.pas:1581, 1592-1594, 1607, 1651, 1675, 1719, 1759-1765, 1777-1778, 1846`、`ToolBarEx.pas:237-238` | `is TTyToolButton` + 强转 | 宿主处理所有工具按钮 | `TTyCustomToolButton` | S20-2 |
| C19-3 | `StatusBar.pas:262` | `GetOwner is TTyStatusBar` | 面板集合找宿主 | `TTyCustomStatusBar` | S20-3（或「—」） |
| C20-1 | `Ribbon.pas:1100-1101, 1107-1108` | `is TTyRibbon` | 页认宿主 | `TTyCustomRibbon` | S21-1 |
| C20-2 | `Ribbon.pas:1187, 1194, 1200-1201` | `is TTyRibbonGroup` | 宿主处理所有组 | `TTyCustomRibbonGroup` | S21-2 |
| C20-3 | `Ribbon.pas:1051-1052` | `AComponent is TTyRibbonPage` | 宿主处理页的释放 | `TTyCustomRibbonPage` | S21-1 一并 |
| C20-4 | `designtime/…PropEditors.pas:653-654, 661-663` | `is TTyRibbonPage` | `Context` 编辑器列出同宿主的页 | `TTyCustomRibbonPage` | —（设计期，审查覆盖） |
| C21-1 | `Form.pas:2177-2178` | `AComponent is TTyTitleBar` | 窗体处理标题栏的释放 | `TTyCustomTitleBar` | —（见 Task 22） |
| C24 | `ToolWindows.pas`：Bar 15 处、Window 21 处、Actions 6 处（行号见 3.0 版附录 C）；`ToolWindows.DesignRules.pas:107, 125`；`ToolWindows.Manager.pas:742` | `is` / `InheritsFrom` | 栏 / 窗口 / 动作区互认、设计期拖放规则 | Custom 类（`CompEditors.pas:659, 749` 保持） | Task 25 |

### C-3 保持

- 库内：`RadioGroup.pas:527-528`（C5-2，Sender 只会是组自己建的 `TTyRadioButton`）；~~`CheckComboBox.pas:348-349, 554-555, 565-566`（C6-5）~~ 第 2 期期末修复改归 C-2（派生组合框可以经 `CreatePopupList` 交出第三方的 `TTyCustomCheckListBox`）；`TabSheet.pas:256`（`is TTyCustomTabStrip`，中间类就是 Custom 层）；`ToolBar.pas:1746-1747`（`is TTyGlyphButtonBase`，同上）；`Dialogs.pas:1058`（`TTyListBox(Sender)`，对话框自己建的列表）；`IconFont.pas:1071`（缓存里只有自建的 `TTyIconFont`）；`Grid.pas` 的 `FEditor` / `FFilterEditor` / `FFilterSearch: TTyEdit`、`FPickEditor: TTyComboBox`、`FFilterPanel: TTyPanel`、`FFilterOk / FFilterCancel: TTyButton`（都是它自己建的那个类）；`ToolGroupPanel.pas:48/203` `AddButton: TTyButton`；`Ribbon.pas:205` `FMoreBtn: TTyButton`；`ListView.pas:327` `FEditor: TTyEdit`；`TreeSelect.pas:108/164/348/436`（`TTyTreeSelectTree` 仍是 `TTyTreeView`）；`Transfer.pas` 的 `TTyListBox` 窗格；`RibbonQuickAccess.pas:62`。
- 设计期组件编辑器（D2 留最终类，且只会遇到那个类）：`CompEditors.pas:405, 512, 569`、`Dialogs.ListGroupsEditor.pas:67`（C13-4）；`CompEditors.pas:921, 941`、`Dialogs.CascaderEditor.pas:77`（C15-1）；`CompEditors.pas:530, 874, 917`、`Dialogs.TreeNodesEditor.pas:73`（C16-3：只会遇到 `TTyTreeView` / `TTyTreeSelectTree`；ShellTreeView 4.0 起由默认编辑器接手）；`CompEditors.pas:980`（C23-1）；`CompEditors.pas:962-973`（对话框预览）。
- 不拆 / 排除的类：`ImageDraw.pas` 之外的 `is TTyVirtualImageList` 无；`PropEditors.pas:336` 等非可视、`Design.AdvChart.Editor.pas:710`。
- tests（对象就是那个类、或是叶子类，A 下答案不变）：`test.combobox.simple.pas:287, 344`（`as TTyComboBox`，建的就是它）；`test.dpi.controls.pas:442`（组合框内嵌的 `TTyEdit`）；`test.focus.tabstop.pas:578-583`（计算器的键是 `TTyButton`）、`:623`（`TTyEdit(Sender)`，`:839` 建的就是它）；`test.formsurface.pas:57`、`test.pagecontrol.streaming.pas:63`、`test.grid.streaming.pas:187`（`is TTyButton`，标记按钮就是 `TTyButton`）；`test.grid.streaming.pas:331-341`、`test.treeview.items.pas:387, 393, 640`、`test.treeview.streaming.pas:50`（`as TTyListView / TTyTreeView`，建的就是它）；`test.parity.combo.pas:180`（`OnGetItems` 挂在 `TTyComboBox` 上，`:427`）；叶子类：`test.checkgroup.pas:65-119`（TTyCheckBox）、`test.dialogs.font.pas:132-152`、`test.dialogs.pas:555`、`test.dpi.containers.pas:331-332`、`test.dpi.controls.pas:198-213`、`test.focus.tabstop.pas:537-541, 680-683`、`test.formsurface.pas:50`、`test.grid.streaming.pas:168-182, 273`、`test.gridpanel.pas:395-518`、`test.imagecollection.streaming.pas:291, 394, 418, 788`、`test.imagename.pas:76-390`（`TTyVirtualImageList(FList)`）、`test.listbox.pas:125-127`、`test.listbox.scroll.pas:179-191`、`test.listgrouppanel.entries.pas:111, 177`、`test.lucide.pas:319`、`test.memo*.pas`（TTyScrollBar）、`test.pagecontrol.streaming.pas:52`、`test.parity.combo.pas:661, 742, 1641-1645`、`test.parity.maskedit.pas:246`、`test.parity.numeric.pas:762, 1039`、`test.parity.pas:1367, 1565-1570`、`test.parity.valuelist.pas:605`、`test.radiogroup.pas:141-683`、`test.ribbonquickaccess.pas:89`、`test.rtl.pas`（TTyScrollBar 多处、`:820` TTyScrollContent、`:963`）、`test.scrollbar.*.pas`、`test.scrollbox.pas:126-558`、`test.steps.pas:1231`、`test.tabset.pas:105`、`test.terminal.view*.pas`、`test.toolbarex.pas:694-696`、`test.toolwindow.images.pas:255-256`、`test.treeselect.pas:400`；工具窗口相关 94 处（叶子类）。
- examples：`button/umain.pas:107, 112`、`antdesign/umain.pas:1432`、`toolbar/umain.pas:172`（`as TTyButton`，只挂在 `TTyButton` 上——「恰好这个类」；`:172` 还要读写 `Down`）；`combobox/umain.pas:136-152`（只挂在 2 个 `TTyComboBox` 上）；`edit/umain.pas:146`（只挂在 1 个 `TTyEdit` 上）；叶子类：`antdesign/umain.pas:416, 1043, 1196, 1298`、`grid/umain.pas:688`、`ribbon/umain.pas:801-802, 948-960, 1155-1156`、`toolbar/umain.pas:183, 191`、`trackbar/umain.pas:110-132`。
- tools：`gallery/tyGalleryCapture.pas:137, 155, 259, 343-351, 403`（PageControl、ToggleSwitch、`ThemeCombo` 在全部示例里都是 `TTyComboBox`）、`painter-regress/painterregress.lpr:149-152, 1132`。

### C-4 编译期必改（隐式向上转型与签名）

| 位置 | 现在 | 为什么 A 下编不过 | 改成 | 任务 |
|---|---|---|---|---|
| `ToolBar.pas:416/1713` `ApplyToButton(B: TTyButton)` | 参数 | A2-1 要传 GlyphButton / ToolButton | `TTyCustomButton` | T2 |
| `tests/test.parity.buttons.pas:500, 562, 1293, 1314, 1328, 1343, 1364`；`tests/test.parity.pas:321, 769, 783, 1296, 1538` | `B: TTyButton := TTyGlyphButton / TTyColorButton / TTySpeedButton.Create` | 不再是 TTyButton | `TTyCustomButton` | T2 |
| `CalcEdit.pas:16, 22, 78` `TTyCalcDropdown` | `FEdit` / `Create(AEdit: TTyNumericEdit)` | 两个 calc 编辑框传 `Self` | `TTyCustomNumericEdit` | T4 |
| `tests/test.parity.combo.pas:443, 461, 484, 500, 512, 534, 553, 574, 875, 1598, 1734-1738, 1754, 1778-1784, 2006`（27 处）+ `:1638` 参数 | `c: TTyComboBox := <派生组合框>.Create` | 不再是 TTyComboBox | `TTyCustomComboBox` | T7（ColorBox 系那几处 T8） |
| `tests/test.parity.pas:490, 506` | `C: TTyComboBox := TTyColorBox.Create` | 同上 | `TTyCustomComboBox` | T8 |
| `ComboBox.pas` 弹层 API（`:144, 161, 290, 349, 373, 396, 513-520, 565-597, 1294, 1315, 1345, 2008, 2113`）、10 个 `CreatePopupList` 覆写、`CheckComboBox.pas:339`、`tests/test.parity.combo.pas:1630` | `TTyListBox` | `TTyCheckComboPopupList` 不再是 TTyListBox（V12） | `TTyCustomListBox` | T15 |
| TreeView 21 个、HeaderControl 3 个事件类型；StatusBar `TTyDrawPanelEvent`、ToolButton、RibbonGroup 各 1（附录 D） | `Sender: TTyXxx` | TreeView：ShellTreeView 触发时 `Self` 不是 TTyTreeView（D10） | Custom 类；tests 约 200、examples 约 110 个处理过程跟着改 | T17 / T20 / T21 |
| `ToolBar.pas:121, 922`（`GetToolBar`）、`:932, 941, 1103, 1131, 1153, 1181, 1205, 1229, 1257, 1499`（`bar: TTyToolBar`） | `TTyToolBar` | ToolBarEx | `TTyCustomToolBar` | T20 |
| 8 个 `IconFont: TTyIconFont` 属性及字段 / 参数（全库 44 处类型出现） | `TTyIconFont` | Lucide 字体挂不上（D11） | `TTyCustomIconFont` | T28 |
| `TyTakeVectorBitmap` 等 `ImageDraw.pas` 内部函数的参数 | `TTyVirtualImageList` | A28-1 | `TTyCustomVirtualImageList` | T28 |

| `tests/test.trailingzone.pas:42/56/124/155`（1 期编译发现） | `ctls: array of TTyEdit`、`ZoneOf(AEdit: TTyEdit)`、`TEditAccess = class(TTyEdit)` | 数组里放 ComboEdit / URLEdit / Calc / FloatSpin / TrackEdit | `TTyCustomEdit`（cracker 同理，N9） | T4（签收补） |
| `tests/test.combohint.pas:23/29/50`（1 期编译发现） | `TComboRenderAccess = class(TTyComboBox)`、`RendersDiffer(A, B: TTyComboBox)` | 传入整族派生组合框 | `TTyCustomComboBox` | T7（签收补） |
| `tests/test.parity.combo.pas:1625/1664/1668/1684/1723/1764`（原表 C-4 的行号多数已是精确类型，无需改） | `TComboFactoryAccess = class(TTyComboBox)`（硬转派生组合框）、`Build` / `BuildList` / 两个循环变量 | 派生组合框 | `TTyCustomComboBox`；`OnDrawItem` 在 Custom 里 protected，经 `TComboFactoryAccess` 写 | T7 |
| `tests/test.parity.buttons.pas:500…1364`、`tests/test.parity.pas:321…1538`（原表所列） | 执行时核实：变量本来就声明成 `TTyGlyphButton` / `TTyColorButton` / `TTySpeedButton`，不是 `TTyButton`——无需改 | — | — | T2 |
| `source/tyControls.GlyphButtons.pas`（1 期编译发现） | `FindDownButton: TTySpeedButton` 在 Custom 类里先于最终类声明 | 前向声明缺失 | ~~加 `TTySpeedButton = class;`（R9）~~ 期末修复：返回类型改 `TTyCustomSpeedButton`，前向声明删掉 | T2（修复提交 `9cbe2e6d`，被期末修复取代） |
| `GridPanel.pas` 的 `FCells` 硬转与局部变量（`TTyGridCell(FCells[i])` ×10、`c` / `cell` / `wanted`）（2 期实现时） | `TTyGridCell` | C11-1 / C11-3 放宽后格表里可以是第三方 `TTyCustomGridCell`，硬转成最终类是类型假话 | `TTyCustomGridCell`（`GridPanel.pas` 自己建的格仍 `TTyGridCell.Create`） | T12 |
| `CoolBar.pas` `TTyCoolBands.OwnerBar` 返回类型、两处 `bar` 局部、`TTyCoolBar = class;` 前向声明（2 期实现时） | `TTyCoolBar` | C11-2 放宽后宿主可以是第三方 `TTyCustomCoolBar` | `TTyCustomCoolBar`（前向声明改为它） | T12 |
| `ListGroupPanel.pas` `TTyListGroups.Create(APanel)` / `FPanel`、前向声明（2 期实现时） | `TTyListGroupPanel` | 宿主在 Custom 类构造里传 `Self` | `TTyCustomListGroupPanel` | T14 |
| `TabSheet.pas` 宿主局部 `Host` 与三处强转（C13-1 一并） | `TTyPageControl` | 页认任意 `TTyCustomPageControl` | `TTyCustomPageControl`（`RegisterPage` / `UnregisterPage` / `MovePage` / `PageCount` / `Pages` 都是 public，不需要 access 类） | T14 |
| `examples/tabcontrol/umain.pas` `PageTitle` / `IsFixedPage` 参数、两个 `Page` 局部；`tests/test.parity.container.pas` 三个 `Sheet` / `First` 局部（2 期实现时） | `TTyTabSheet` | `ActivePage` / `Pages[]` 交出 `TTyCustomTabSheet`（R7-4） | `TTyCustomTabSheet`（只用到 public 成员） | T14 |
| `tests/test.parity.combo.pas` `RenderAnyPopupList` / `ListRenderDiffers` 参数、`BuildList` 返回、`lOwn` / `lPlain`；`tests/test.customclasses.p1.pas` `TP1ComboCracker.MakePopupList` 与两个 `l` 局部（2 期实现时） | `TTyListBox` | 弹层 API 交出 `TTyCustomListBox` | `TTyCustomListBox` | T15 |
| `TreeSelect.pas` `TTyTreeSelectTree.FPicker` / `Picker`、前向声明（2 期实现时） | `TTyTreeSelect` | 字段在 Custom 类构造里设 `Self` | `TTyCustomTreeSelect` | T16 |
| `TreeView.pas` 实现段私有函数 `FullExpandSubtree` / `FullCollapseSubtree` / `MergeSortedLists` / `MergeSortList` / `SortTreeNode` 的 `Tree` 参数、`AlphaCompare` / `CustomSortCompare` 的 `Sender`（2 期实现时） | `TTyTreeView` | 内部比较器是 `TTyTreeCompareEvent`、`Self` 是 Custom 类 | `TTyCustomTreeView`（R7-3） | T17 |
| D10 处理过程：`source/tyControls.Dialogs.SelectPath.pas`（10）、`Dialogs.StructureEditor.pas`（2）；tests 10 个单元（188）；examples `treeview/showcasemain.pas`（84）、`demo/mainform.pas`（16）、`rtl/umain.pas`（6）、`containers/umain.pas`（4）、`antdesign/umain.pas`（2） | `Sender: TTyTreeView` / `AHeader: TTyHeaderControl` | 事件类型改 Custom 类 | Custom 类；处理过程体里经 `Sender` 只用到 public 成员（脚本逐个核过），无需强转 | T17 |
| `Grid.pas` `TTyGridStrings.Create(AGrid)` / `FGrid`（2 期实现时） | `TTyStringGrid` | 网格在 Custom 类里传 `Self` | `TTyCustomStringGrid` | T18 |

执行中编译器报出的其它处，按规则判断后补进本表（签收列出）。

---

## 附录 D：签名里写着最终类的地方（R7）

写计划时在各单元 interface 段静态扫到的；执行中改了的标「改」、保持的标「保持」，新增的追加：
- **事件类型的 Sender**（D10，建议全改 Custom）：`TreeView.pas:127-244`（21 个 `procedure(Sender: TTyTreeView; ...)`；**改**，Task 17）、`HeaderControl.pas:78/82/90`（**改**，Task 17）、`StatusBar.pas:60`（`TTyDrawPanelEvent`）、`ToolBar.pas`（Sender 为 `TTyToolButton` 的 1 个）、`Ribbon.pas`（Sender 为 `TTyRibbonGroup` 的 1 个）。
- **宿主属性 / 方法里的子项类型**（R7-4；~~保持，LCL `TPageControl.ActivePage: TTabSheet` 先例；getter 里强转~~ 期末修复改定：只交出自建子项、或 setter 写死最终类的保持，接受第三方 Custom 子项的改 Custom 类，见 R7-4）：`PageControl.pas:17-86`（`TTyTabSheet`；**改**：`ActivePage` / `Pages[]` / `FPages` → `TTyCustomTabSheet`，`AddPage` 等保持，Task 14）、`Ribbon.pas:74-239`（`TTyRibbonPage` / `TTyRibbonBackstage` / `TTyRibbonGroup`；**改**：页与组的数组和访问器 → Custom，`Backstage` 保持，Task 21）、`RibbonAppMenu.pas:66/107`、`RadioGroup.pas:54/144`（`TTyRadioButton`）、`CheckGroup.pas:38/77/109`（`TTyCheckBox`）、`ToolBar.pas:249/347/379/445/447`、`Form.pas:279/355/356/510/515/659`（`TTyForm.TitleBar` / `MenuBar`）、`GlyphButtons.pas:361`（`FindDownButton`；~~1 期执行：返回类型保持 `TTySpeedButton`，体内对 `Self` 与找到的 `TTyCustomSpeedButton` 兄弟强转，加前向声明~~ **改**：期末修复照 LCL 返回 `TTyCustomSpeedButton`，同组可以有第三方成员）、`RibbonQuickAccess.pas:62`（`TTyGlyphButton`）。内部注册方法（`RegisterPage` 等）照 R7-3 放宽。
- **互指的 shell 控件**：`ShellTreeView.pas:187/390`（`TTyShellListView`；**改**，第 2 期期末修复：照 LCL `shellctrls.pas:139` 改 `TTyCustomShellListView`，R7-4 ②）；`FilterComboBox.pas:37/83`（`TTyShellListView`；**保持**，照 LCL `TFilterComboBox.ShellListView: TShellListView`，`filectrl.pp:167`）；`ShellListView.pas` 的 `ShellTreeView: TTyShellTreeLink`（接缝类，第三方 `TTyCustomShellTreeView` 子类挂得上；保持）。
- **内嵌控件的类型**（保持，本来就该是最终类）：`ScrollBar.pas:72`、`ScrollBox.pas:132`、`ListBox.pas:118`、`ListView.pas:509/510/569/607`、`Memo.pas:691`、`Terminal.pas:589/632`、`TreeView.pas:832/1064/1065/1097`、`Grid.pas:1505/1560/1561/2289-2308/2991/3005/3211`、`Transfer.pas:248-320`、`TreeSelect.pas:108-226`、`Dialogs*.pas` 里对话框自己的控件。
- **被迫放宽的**（改）：附录 C-4。
- **组件引用属性**（D11）：`IconFont`（改，被迫）、`Controller`（改，照 LCL，需确认）、`ImageCollection` 类属性 7 个、`TTyVirtualImageList` 类属性 1 个（改，照 LCL，需确认）。
- **集合 / 辅助类的所有者**：`CoolBar.pas:178`（`OwnerBar: TTyCoolBar`；**改（私有）**：Task 12 改 `TTyCustomCoolBar`，C11-2 放宽后宿主可以是第三方 Custom 子类；`private`，不进不兼容清单）、`ListGroupPanel.pas:190`、`RibbonGallery.pas:56`、`ToolWindows.pas` / `ToolWindows.Manager.pas` / `ToolWindows.DesignRules.pas` 的全部窗口 / 栏参数（Task 25 逐个定）。

---

## 附录 E：D3 可见性对照表（我们的控件 → LCL 对应类 → 规则）

规则：① **同名属性**：照 LCL 对应类处的可见性（`split.py vis <对应类> <名字>`，most-derived 声明）；② **同义属性**：照表里写的那个 LCL 名字；③ **Ty 独有属性**：照「独有属性」列（= 该 LCL 类自身声明的属性里 public / protected 的多数；没有对应类的 = LCL 主流 public，V16）；④ LCL 对应类自己在 Custom 层 published 的异例（`TCustomTrackBar`、`TCustomHeaderControl`、`TScrollingWinControl` 的两个滚动条）：用 public（Q6）；⑤ 基类层的名字（Enabled、OnClick……）已在 Task 1 回到 `TControl` / `TWinControl` 的可见性，不在这里管。括号里是 LCL 类自身属性的 public / protected 数。

| 我们的控件 | LCL 对应类（文件:行） | 独有属性 |
|---|---|---|
| Button、DropDownButton、MenuButton、RibbonAppMenu | `TCustomButton`（stdctrls.pp:1214，8 / 1） | public |
| GlyphButtonBase、GlyphButton、GlyphContainerButton | `TCustomBitBtn`（buttons.pp:163，15 / 0） | public |
| SpeedButton、ColorButton | `TCustomSpeedButton`（buttons.pp:322，21 / 1；`TColorButton` dialogs.pp:330 的父类） | public |
| ToolButton | `TToolButton`（comctrls.pp:2103，不拆）；继承来的名字照 `TCustomBitBtn` | public |
| ButtonGroup、Segmented、Calculator | 无 | public |
| TyLabel、HtmlLabel、LinkLabel、ShadowLabel、GlowLabel | `TCustomLabel`（stdctrls.pp:1556，2 / 7） | **protected** |
| Tag、Badge | 无 | public |
| Edit、URLEdit | `TCustomEdit`（stdctrls.pp:764，23 / 3） | public |
| NumericEdit、CurrencyEdit、TrackEdit、CalcEdit、CalcCurrencyEdit | `TCustomFloatSpinEdit`（spin.pp:33，7 / 0；同义 Value / MinValue / MaxValue / DecimalPlaces） | public |
| MaskEdit | `TCustomMaskEdit`（maskedit.pp:206，4 / 5） | **protected** |
| ComboEdit | `TCustomEditButton`（editbtn.pas:63，0 / 16） | **protected** |
| Memo | `TCustomMemo`（stdctrls.pp:902，7 / 0） | public |
| SpinEdit | `TCustomSpinEdit`（spin.pp:146，4 / 0） | public |
| FloatSpinEdit | `TCustomFloatSpinEdit`（spin.pp:33） | public |
| UpDown | `TCustomUpDown`（comctrls.pp:1922，0 / 15） | **protected** |
| CheckBox、RadioButton、ToggleSwitch | `TCustomCheckBox`（stdctrls.pp:1326，6 / 0） | public |
| ComboBox、MRUComboBox、OfficeComboBox、AdvancedComboBox、FontComboBox、FontSizeComboBox、ShellComboBox | `TCustomComboBox`（stdctrls.pp:289，22 / 12） | public |
| ComboBoxEx | `TCustomComboBoxEx`（comboex.pas:136，6 / 0） | public |
| CheckComboBox | `TCustomCheckCombo`（comboex.pas:271，7 / 0） | public |
| ColorBox、ColorComboBox | `TCustomColorBox`（colorbox.pas:46，10 / 0） | public |
| FilterComboBox | `TCustomFilterComboBox`（filectrl.pp:147，2 / 0） | public |
| ProgressBar、Gauge、Meter、LevelMeter、CircularProgress | `TCustomProgressBar`（comctrls.pp:1814，8 / 0；同义 Value ↔ Position） | public |
| ActivityIndicator、ActivityBar、GearActivityIndicator、Sparkline、Rating、Dial、GearDial、AnalogClock | 无 | public |
| TrackBar | `TCustomTrackBar`（comctrls.pp:2733，异例：17 个 published） | public（Q6） |
| Panel、PaintPanel、ExPanel、GridPanel、RelativePanel、Card | `TCustomPanel`（extctrls.pp:1123，11 / 3） | public |
| ScrollBox、ScrollPanel | `TScrollingWinControl`（forms.pp:168；HorzScrollBar / VertScrollBar 在那里 published） | public |
| ControlBar | `TCustomControlBar`（extctrls.pp:1571，17 / 0） | public |
| CoolBar | `TCustomCoolBar`（comctrls.pp:2556，17 / 0） | public |
| GridCell、ScrollContent、Empty、SizeBox、ListGroupPanel | 无 | public |
| GroupBox、ToolGroupPanel | `TCustomGroupBox`（stdctrls.pp:165，1 / 0） | public |
| RadioGroup | `TCustomRadioGroup`（extctrls.pp:717，10 / 0） | public |
| CheckGroup | `TCustomCheckGroup`（extctrls.pp:854，8 / 0） | public |
| Bevel、Divider | `TBevel`（extctrls.pp:671，不拆） | public |
| Splitter | `TCustomSplitter`（extctrls.pp:370，11 / 0） | public |
| CustomTabStrip、PageControl、TabSet | `TCustomTabControl`（comctrls.pp:373，21 / 6） | public |
| TabSheet | `TCustomPage`（comctrls.pp:236，11 / 1） | public |
| ListBox、OfficeListBox、AdvancedListBox、FontListBox、ValueListEditor | `TCustomListBox`（stdctrls.pp:537，51 / 0） | public |
| CheckListBox | `TCustomCheckListBox`（checklst.pas:36，9 / 0） | public |
| ColorListBox | `TCustomColorListBox`（colorbox.pas:170，10 / 0） | public |
| Transfer、TreeSelect、Cascader | 无 | public |
| TreeView | `TCustomTreeView`（comctrls.pp:3382，32 / 46） | **protected** |
| ShellTreeView | `TCustomShellTreeView`（shellctrls.pas:80，9 / 1）；继承来的名字照 `TCustomTreeView` | public |
| ListView | `TCustomListView`（comctrls.pp:1395，27 / 46） | **protected** |
| ShellListView | `TCustomShellListView`（shellctrls.pas:257，9 / 1） | public |
| HeaderControl | `TCustomHeaderControl`（comctrls.pp:4033，异例：11 个 published） | public（Q6） |
| CustomGrid | `TCustomGrid`（grids.pas:744，6 / 100） | **protected** |
| DrawGrid | `TCustomDrawGrid`（grids.pas:1397，112 / 2；把大批继承属性提成 public） | public |
| StringGrid | `TCustomStringGrid`（grids.pas:1751，9 / 2） | public |
| StatusBar | `TStatusBar`（comctrls.pp:120，不拆） | public |
| ToolBar、ToolBarEx、ToolSeparator | `TToolBar`（comctrls.pp:2262，不拆） | public |
| ScrollBar | `TCustomScrollBar`（stdctrls.pp:68，10 / 0） | public |
| Alert、Pagination、Steps、Breadcrumb、Ribbon 全部、TitleBar、MenuBar、FormSurface、PreviewBox、Chart、ColorGrid、LColorPicker、HSColorPicker、TerminalView、ToolWindowBar、ToolWindow、ToolWindowActions | 无 | public |
| CharImage、Image、ImageView | `TCustomImage`（extctrls.pp:529，30 / 0） | public |
| Shape、StarShape | `TCustomShape`（extctrls.pp:274，5 / 0） | public |
| Arrow | `TArrow`（arrow.pp:33，不拆） | public |
| VirtualImageList、LucideImageList | `TCustomImageList`（imglist.pp:266，25 / 0） | public |
| Message | `TCustomTaskDialog`（dialogs.pp:723，41 / 0） | public |
| StyleController、NativeStyler、IconFont、IconPackFont、LucideIconFont、GlyphImageList、ImageCollection、Hint、BalloonHint、Popover、Notification、InputDialog、PasswordDialog、TextDialog、SelectValueDialog、ProgressDialog、AboutDialog、IconBrowserDialog | 无 | public |

规模：58 行，覆盖 156 个拆分类与 5 个中间类；有 LCL 对应类的 39 行（其中 7 行独有属性为 protected：标签、MaskEdit、ComboEdit、UpDown、TreeView、ListView、CustomGrid）。

---

## 附录 F：D4–D6 拆不拆的依据（照 LCL）

| 我们的类 | LCL 对应物（文件:行） | LCL 拆不拆 | 我们 |
|---|---|---|---|
| TTyStyleController、TTyNativeStyler | 无（LCL 没有主题控制器） | — | 拆（T27） |
| TTyPopupMenu、TTyImagesMenu、TTyMenuEx | `TPopupMenu = class(TMenu)`（menus.pp:465；`TMenu` menus.pp:362 自己就 published 9 个） | 不拆 | 不拆 |
| TTyIconFont、TTyIconPackFont、TTyLucideIconFont | 无 | — | 拆（T28） |
| TTyVirtualImageList、TTyLucideImageList | `TCustomImageList`（imglist.pp:266）/ `TImageList`（controls.pp:2492，经 `TDragImageList` controls.pp:436） | 拆 | 拆（T28） |
| TTyGlyphImageList | 无（它是 `TTyComponent`，不是 `TCustomImageList`） | — | 拆（T28） |
| TTyImageCollection | 无（LCL 4.4 没有图像集合组件） | — | 拆（T28） |
| TTyHint、TTyBalloonHint | 无（`THintWindow` forms.pp:978 是窗体；LCL 没有 `TBalloonHint`） | — | 拆（T29） |
| TTyPopover、TTyNotification | 无 | — | 拆（T29） |
| TTyMessage | `TCustomTaskDialog`（dialogs.pp:723）/ `TTaskDialog`（:844） | 拆 | 拆（T30） |
| TTyInputDialog、TTyPasswordDialog、TTyTextDialog、TTySelectValueDialog | 无（`InputQuery` / `PasswordBox` 等是函数） | — | 拆（T30） |
| TTyProgressDialog、TTyAboutDialog、TTyIconBrowserDialog | 无 | — | 拆（T30） |
| TTySelectPathDialog | `TSelectDirectoryDialog = class(TOpenDialog)`（dialogs.pp:281） | 不拆 | 不拆 |
| TTyColorDialog | `TColorDialog = class(TCommonDialog)`（dialogs.pp:305，直接 published） | 不拆 | 不拆 |
| TTyFontDialog | `TFontDialog`（dialogs.pp:416） | 不拆 | 不拆 |
| TTyFindDialog、TTyReplaceDialog | `TFindDialog`（dialogs.pp:454）、`TReplaceDialog`（:515） | 不拆 | 不拆 |
| TTyCustomFileDialog、TTyOpenDialog、TTySaveDialog | `TFileDialog`（dialogs.pp:141，published 8）、`TOpenDialog`（:239，published 4）、`TSaveDialog`（:270）——属性在各层直接 published，`TCommonDialog`（:87）也 published 5 个 | 不拆 | 不拆 |
| TTyOpenPictureDialog、TTySavePictureDialog | `TOpenPictureDialog`（extdlgs.pas:74）、`TSavePictureDialog`（:102） | 不拆 | 不拆 |
| TTyOpenPreviewDialog、TTySavePreviewDialog | `TPreviewFileDialog` 一系（extdlgs.pas，`class(TOpenDialog)`） | 不拆 | 不拆 |
| TTyToolWindowManager | 无（LCL 的停靠管理 `TDockManager` 不是组件） | — | 已是 Custom + 最终类；形状豁免（Q4） |
| TTyToolWindowBar、TTyToolWindow、TTyToolWindowActions | 无（`TToolWindow` 是 `TToolBar` 的基类，不是工具窗口） | — | 拆（T25） |
| TTyGridCell | 无（LCL 网格面板没有格子控件） | — | 拆（T12） |
| TTyFormSurface | 无 | — | 拆（T22） |
| TTyScrollContent | 无 | — | 拆（T12） |
| TTyForm、TTyDialog | `TForm`（forms.pp:831）——用户窗体从它派生的那一层 | LCL 拆成 `TCustomForm` / `TForm`，但我们扮演的是 `TForm` | 不拆（Q5） |
| （参考）`TApplicationProperties` | forms.pp:1788，`class(TLCLComponent)` | LCL 4.4 不拆（没有 `TCustomApplicationProperties`） | 本库无对应 |
| （参考）`TTimer`、`TTrayIcon`、`TActionList` | `TCustomTimer`（customtimer.pas:31）、`TCustomTrayIcon`（extctrls.pp:1408）、`TCustomActionList`（actnlist.pas:76） | 拆 | 本库无对应 |

规模：35 个非可视候选里拆 20、不拆 14、豁免 1；另 3 个可视候选（GridCell、FormSurface、ScrollContent）与工具窗口 3 件改为拆。

---

## 附录 G：D7 基类属性的完整列表与 LCL 可见性

来源：`source/tyControls.Base.pas:254-333`（图形基类，41 个）、`:418-515`（窗口化基类，52 个）；LCL 可见性取 `C:/lazarus/lcl/controls.pp` 的 most-derived 声明（`split.py vis TGraphicControl` / `TCustomControl`）。「Task 1 怎么做」：删 = 删掉重声明那一行（回到 LCL 的可见性）；public = 移到 public 段。

| 属性 | 图形基类 | 窗口化基类 | LCL 声明处（controls.pp） | LCL 可见性 | Task 1 怎么做 |
|---|---|---|---|---|---|
| Version | ✓ | ✓ | —（Ty 自有） | — | public |
| StyleClass | ✓ | ✓ | — | — | public |
| StyleOverride | ✓ | ✓ | — | — | public |
| Controller | ✓ | ✓ | — | — | public |
| Hint | ✓ | ✓ | TControl :1844 | **published** | 删（本来就 published，位置不变） |
| Cursor | ✓ | ✓ | TControl :1841 | **published** | 删（同上） |
| Enabled | ✓ | ✓ | TControl :1805 | public | 删 |
| Visible | ✓ | ✓ | TControl :1817 | public | 删 |
| Font | ✓ | ✓ | TControl :1806 | public | 删 |
| ShowHint | ✓ | ✓ | TControl :1816 | public | 删 |
| OnClick | ✓ | ✓ | TControl :1811 | public | 删 |
| OnResize | ✓ | ✓ | TControl :1812 | public | 删 |
| OnChangeBounds | ✓ | ✓ | TControl :1810 | public | 删 |
| AutoSize | ✓ | ✓ | TControl :1789 | public | 删 |
| OnShowHint | ✓ | ✓ | TControl :1813 | public | 删 |
| PopupMenu | ✓ | ✓ | TControl :1815 | public | 删 |
| Constraints | ✓ | ✓ | TControl :1801 | public | 删 |
| BorderSpacing | ✓ | ✓ | TControl :1790 | public | 删 |
| Action | ✓ | ✓ | TControl :1785 | public | 删 |
| OnDblClick | ✓ | ✓ | TControl :1582 | protected | 删 |
| OnMouseDown / OnMouseUp / OnMouseMove | ✓ | ✓ | TControl :1589 / 1591 / 1590 | protected | 删 |
| OnMouseEnter / OnMouseLeave | ✓ | ✓ | TControl :1592 / 1593 | protected | 删 |
| OnMouseWheel / OnMouseWheelUp / OnMouseWheelDown | ✓ | ✓ | TControl :1594 / 1596 / 1595 | protected | 删 |
| OnMouseWheelHorz / OnMouseWheelLeft / OnMouseWheelRight | ✓ | ✓ | TControl :1597 / 1598 / 1599 | protected | 删 |
| OnContextPopup | ✓ | ✓ | TControl :1581 | protected | 删 |
| DragMode / DragKind / DragCursor | ✓ | ✓ | TControl :1572 / 1571 / 1570 | protected | 删 |
| OnDragOver / OnDragDrop | ✓ | ✓ | TControl :1586 / 1585 | protected | 删 |
| OnStartDrag / OnEndDrag | ✓ | ✓ | TControl :1601 / 1588 | protected | 删 |
| ParentShowHint | ✓ | ✓ | TControl :1577 | protected | 删 |
| OnPaint | ✓ | ✓ | 图形：TGraphicControl :2457 / 窗口化：TCustomControl :2486 | 图形 **protected** / 窗口化 public | 删 |
| TabOrder / TabStop | | ✓ | TWinControl :2341 / 2342 | public | 删 |
| BorderWidth / ChildSizing | | ✓ | TWinControl :2324 / 2329 | public | 删 |
| OnKeyDown / OnKeyUp / OnKeyPress / OnUTF8KeyPress | | ✓ | TWinControl :2349 / 2351 / 2350 / 2353 | public | 删 |
| OnEnter / OnExit | | ✓ | TWinControl :2347 / 2348 | public | 删 |
| OnEditingDone | | ✓ | TControl :1602 | protected | 删 |
| （`TTyComponent`）Version | | | —（`Component.pas:35`） | — | public（Q2） |

合计：图形基类 41 = Ty 自有 4 + 已 published 2 + public 13 + protected 22；窗口化基类 52 = 4 + 2 + public 24 + protected 22。Task 1 之后两个基类的 published 集合 = `TGraphicControl` / `TCustomControl` 的 15 个（G8）。

---

## 签收（执行时填）

### Task 0 基线
- 起点：`feat/custom-classes` @ `6fff2bd3`（已含 main `9cb48996`），`git merge main` 无新内容。`git cherry main 3.0-fixes` = 6，正是 Step 2 判据里列明的 6 个（主控核实），其余为 0。排除清单复核与 V10 一致：AdvChart 两个分支只碰 `Calendar.pas` / `DateTimePicker.pas` 与 AdvChart / 共享单元；theme-builder 不碰控件单元；AdvChart 对 `Base.pas` 的改动不含 property 行（0）。
- 提交：`12ec0e78`（守卫单元 `tests/test.customclasses.pas`、快照夹具、`tytests.lpr` 注册）。
- 快照：类头 **190**（注册 175 + `TTyScrollContent` + 输入 10 + LCL 根 4）、`#typekey` 行 **176**、文件 **12440** 行、`x` **0** 个。判据逐项核过：`TTyEdit` 的 chain 以 `TTyCustomControl,TCustomControl,TWinControl,TControl` 开头、第一行属性 `Name`、含 `Text`、`TabStop` default 1、typekey `TyEdit`、尺寸 `140x28`；`TTyGlyphButton` → `TyButton`，`TTySpeedButton` → `TySpeedButton`；`TTyScrollContent` 段在。
- 基线全量：**8590** 条，0 错 0 败（18 分钟）。
- 守卫实现上与计划文字的两处差异（判据不变）：① G6 比对时类头行只比类名与 `n=`，**不比 `chain=`**——父类链正是拆分要改的东西（G1 / G7 管它），比 chain 的话第一个拆分就红；② `CSnapshotTypeRenames` 两边都映射（不只映射夹具一侧），否则改名落地前的每一次比对都红。
- `split.py` 的 `check` 改用 `git cat-file --filters HEAD:<file>`：仓库 `core.autocrlf=true`，索引里是 LF、工作区是 CRLF，原写法拿 LF 的 blob 比 CRLF 的工作区，永远报「换行变了」。

### Task 1 基类
- 提交：**Q3 单独提交 `e4f3c648`**（`AdvanceChart.pas` / `Calendar.pas` / `DateTimePicker.pas` 只插基类块；三个类原本在 published 段里重声明过的基类名字——`TabStop default False`、`Font`、`OnClick` 等——同一个类不能声明两次，只能挪进块里它的 3.0 位置，连同上方注释，别的一行没动；该提交单独可编译，供 AdvChart 会话 cherry-pick）；其余 `950fe415`。
- 插块：**110** 个类（窗口化 60 = 注册 57 + `TTyCustomGrid` + `TTyCustomTabStrip` + `TTyScrollContent`；图形 28；`TTyComponent` 一系 21 = 注册 20 + `TTyCustomFileDialog`，另 `TTyToolWindowManager` 只插 `Version`）。说明符合并 **39** 个类（`TabStop default True` 36、TabSheet / ToolWindow 的 `TabOrder` / `Visible stored False`、ToolWindow / ToolWindowActions 的 `Controller stored False`）；此外 106 个类原来就在 published 段里重声明了部分基类名字（多是无说明符的 `StyleClass` / `Controller` / `Font`），一并挪进块、去重。
- N30 探针补 published：**0** 处（`test.base` 的 `TestBaselinePropertiesPublished` 查的是最终类，照常绿）。
- 计划外但非改不可：① **`TTyIconFont.Version: Integer` 改名 `ChangeStamp`**——它在 public 段遮住了库版本 `Version: string`；Q2 之后最终类要自己发布字符串 `Version`，同一类里不能既声明又重发布同名属性（FPC Duplicate identifier，scratchpad 探针确认）。照 `TTyImageCollection` 的先例改名；`ImageCollection.pas` 两处、`test.iconfont` 跟着改。进不兼容清单第 7 条。② **R8（test.designeditors 的新规则）从 Task 8 提前到 Task 1**：基类不再发布 `Version` / `StyleClass` / `StyleOverride` 之后，注册在基类上的 7 条属性编辑器按旧规则立即红，而 Task 1 Step 4 要求全量与基线相同。
- 全量（Task 1 编译）：**8592** 条，0 错，1 败 = `EveryTestUnitThatRegistersTestsIsLinked`——全量跑的时候我在磁盘上新建了 `test.customclasses.p1.pas`、还没写进 `tytests.lpr`，测试按磁盘扫描所以报它；不是代码问题，1 期全量里这条绿。

### 1 期
- 提交区间：`321deaea`（Task 2）…`8a2205a3`（Task 10）+ 收尾修复 `9cbe2e6d`、`be07479b`、`1bfa1276`、`151fba70`（另 `d5b83c89` 是 Task 6 后补强的测试）。逐任务：Task 2 `321deaea`、Task 3 `1ea68a36`、Task 4 `aab24e7f`、Task 5 `ca9d04a5`、Task 6 `69cf1006`、Task 7 `ba5b5ce6`、Task 8 `e0924b7e`、Task 9 `b6d7d7e1`、Task 10 `8a2205a3`。
- 拆分：59 个最终类全部进 `CSplit`（`CPending` 剩 97 个，全是 2–4 期的）；`TTyGlyphButtonBase` 改挂 `TTyCustomButton` 并降级、进 `CDemoted`；`TTyToolButton` 先补了完整发布段。设计期：`TTyFilterComboBox` / `TTyShellComboBox` 的属性编辑器挪到 Custom 类（`PropEditors.pas`）。`designtime/` 用 fpc 对着测试构建产出的运行时单元单独编过（7 个单元，0 错，4 个既有警告都在 AdvChart 编辑器）；输出只写 scratchpad。
- 本期 suite：守卫 10 条、`TTyCustomClassesP1Test` 25 条，全绿；`TVersionTest` 6、`TDesignEditorsTest` 5、`TPaletteIconTest` 3、`TTyFocusTabStopTest` 7、`TTyClickFocusTest` 4，全绿。
- 全量：一次编译后 **8617** 条，0 错 2 败——`test.parity.buttons` 两条断言「`TTyGlyphButtonBase` 本身发布 GlyphLayout / Spacing」，钉的正是要拆掉的旧形状，改成按 4.0 说法（`151fba70`）。变异之后 `lazbuild -B` 再跑全量（终验）：**8617** 条（= 基线 8590 + Task 1 的 2 + P1 的 25），**0 错 0 败**；红名单为空。
- 编译器在收尾时报出、补进附录 C-4 的：`test.trailingzone`（数组 / `ZoneOf` / access 类）、`test.combohint`（`RendersDiffer` / access 类）、`GlyphButtons.pas` 缺 `TTySpeedButton` 前向声明。原 C-4 表里 `test.parity.buttons` / `test.parity` 的行执行时核实无需改（变量本来就是派生类型）。
- 结构核对（不看测试）：最终类只有 `property X;`（G3b 绿，人工抽看 Button / Edit / ColorBox / UpDown）；带接口的 Custom 类头保住接口（`TTyCustomEdit`、`TTyCustomMemo`）；本期没有 R3 行；`git diff 950fe415..HEAD -- source` 里改了父类的类都在附录 C-0；没有新增 `RegisterClass`；不许碰的共享文件与排除单元自 Q3 提交后 0 行改动，`Base.pas` / `Component.pas` 只在 Task 1 动过；每个改过的文件 `split.py check` 都 ok。D3 分拣由脚本按附录 E 的 LCL 对应类逐个查 `vis` 决定，抽查：`TTyCustomEdit.AutoSelect` protected、标签独有属性 protected、`TTyCustomUpDown` 全部 protected、`TTyCustomCheckBox.Checked` protected（`TButtonControl`）、`TTyCustomComboBox` 的 `Sorted` / `MaxLength` / `ItemHeight` / `ItemWidth` / 各条目事件 protected、`TTyCustomTrackBar` 全 public（Q6）。
- 附录 C-1 本期逐行：A2-1、A2-2、A2-3、A2-4、A2-5、A4-1、A4-2、A7-1、A8-2、A8-3 已落实；**A8-1 执行中核实不是翻转**（`TTyColorComboBox` 的弹层是自己的 `TTyColorMorePopupList`，3.0 起就不读宿主色块几何），改归 C-2，S8-1 改用第三方模拟类作见证（附录 C 已改写那一行）。C-2 本期：C1-1、C4-1、C5-1、C6-2、C6-3、C6-4、C7-2 已放宽。C-3：C5-2（RadioGroup）、C6-5 保持。
- 集中变异（`<scratchpad>/mut.py`：改 → 读回比对 → 编译 → 跑点名 suite → 写回原字节并核对 → 最后 `-B` 重编；28 条）：
  - **红**（26）：M-G1（改用 `TTyCalcCurrencyEdit` 改挂 `TTyCustomCurrencyEdit`；URLEdit 那个写法编不过，测试用到它的方法）、M-G2、M-G3b、M-G4、M-G5（把已拆的 `TTyBadge` 也写进 `CPending`）、M-G6a、M-G6b、M-G6k（`TTyCustomSpeedButton` 的 typeKey 改回 `'TyButton'`，与删覆写等价）、M-G7（改用 MRUComboBox 改挂回 `TTyComboBox`）、M-G8、M-T（**改在标签家族**：`GetStyleTypeKey` 从 `TTyCustomLabel` 挪到 `TTyLabel` → `TestThirdLabel` 红）、M-D1、M-D2（Filter 编辑器注册到 `TTyCustomShellComboBox`，它的注册后代都不发布 Filter）、S2-1、S2-2、S1-1、A4-1、S4-2、S5-1、S7-1、S7-2、S8-1、A8-2、S8-2、MaskEdit 的 `Text write SetMaskedText` 挪到最终类（`TestThirdMaskEdit` + G3b）、FloatSpinEdit 的 `UseThousands default False` 挪到最终类（G3b）、TrackBar 的 `TabStop default True` 挪到最终类（`TestThirdTrackBar` T-e + G3b）。
  - **编译期即挡住**（2，等价于红，没法跑到测试）：M-T 按计划写在按钮家族——`ToolBar.pas` 的 `TTyToolButton.GetStyleTypeKey` 调 `inherited`，覆写一离开 `TTyCustomButton` 就成了调抽象方法，编不过；Edit 的接口列表挪到 `TTyEdit`——`Edit.pas` 自己把 `Self` 当 `ITyTextEditActions` 传，编不过。
  - 本期没做：M-G3a / M-G6c（本期没有 R3 行，留 2 期 TabSheet）；S2-3（溢出弹层要真窗口，与 S2-2 同一判断，「—」）；S4-1（计算器弹层要真窗口；C-4 是编译期的，编过即证，「—」）。
- 判据上与计划文字的差异：
  - T-e 实现为「新实例流出的文本里没有这个名字；序数且有 default 的再比读值」——计划写的「= Default 或 IsStoredProp = False」对没有 default 的字符串属性（Caption 等）恒不成立，而写不写进 `.lfm` 才是要守的事。几处按 3.0 实情排除并写了注释：`TTyColorBox.Selected`、`TTyComboBox.ItemIndex`、`TTyGauge.Max`（三者 3.0 就没有 default，新实例就会写）、`ItemsEx`（集合属性在没有祖先可比时 TWriter 一律写，`writer.inc`）。
  - `TThirdMaskEdit` 发布 `Mask` 而不是 `EditMask`：`EditMask` 是 `stored False` 的别名，流不出来。
  - `TThirdGauge` 先发布 `Max` 再 `Value`：反过来读回时 Value 被默认 Max=100 钳住——这正是 N1 / V5-7 说的顺序问题，在第三方身上照样成立（文档要写）。
  - `TThirdUpDown` 的 `Associate` 是组件引用，单独流一个 up-down 没有 owner 可解析，不进 T-c；由 S4-2 驱动。
  - `TTyToolButton` 补发布段：计划写「只取 block 输出的 `property X;` 行替换整个发布段」会把它自己带类型的声明（Style、Grouped、Wrap…）全删掉；实际做法是按快照顺序写全部名字，它自己声明过的名字在原位置用它自己的声明（同 Task 1 的合并）。
  - 纯重发布行（`property AutoSize;` 等）上方的说明注释挪到了最终类发布段里对应行的上方（G3b 去掉注释再查，不受影响）；降级的 `TTyGlyphButtonBase` 没有最终类，那段 AutoSize 注释留在它的 public 段、措辞改成「由各最终类发布」。
- R7 新增签名（已补附录 D / C-4）：`TTyCalcDropdown.Create(AEdit: TTyCustomNumericEdit)`、`TyComboOwnerOf` 返回 `TTyCustomComboBox`、`TTyToolBar.ApplyToButton(B: TTyCustomButton)`；~~`FindDownButton` 返回类型保持 `TTySpeedButton`（R7-4），体内强转~~（期末修复改为返回 `TTyCustomSpeedButton`，见「第 0、1 期期末修复」）。
- 注释（N27）：写着层级事实的改成真话（`GlyphButtons` / `DropButtons` / `ColorButton` / 编辑框一族 / `ColorBox` / `FontComboBox` / `ComboBoxEx` / `FloatSpinEdit` 的单元头与几处行内注释，`ToolBar` 的 `Default` 遮蔽说明）；`{ TTyXxx }` 与 `{ --- TTyXxx --- }` 分隔注释都改成 Custom 名。
- 【主控执行】待办：编 `tycontrols.lpk` / `tycontrols_dt.lpk`、编全部 examples（本期改了 `examples/toolbar/umain.pas`、`examples/grid/umain.pas` 与 `tools/gallery/tyGalleryCapture.pas`，未编）、`check-lfm-props.py`、冒烟手点两处（toolbar 示例点一个 GlyphButton 与一个 ToolButton，状态栏显示标题不弹异常；grid 示例打开计算列，编辑器字体为红）、期末审查。
### 第 0、1 期期末修复（2026-10-02，起点 `41509003`）
- 起因：主控派的两个期末审查（规格核对、代码质量）与审查探针（scratchpad `splitrv1/`：`gen.py` 生成的 `test.zz.genmimic`、`test.zz.rvprobe`）。
- 提交（每个问题一个，正文 `Refs #8`）：

| # | 提交 | 处理 |
|---|---|---|
| 1 | `05797028` | `FindDownButton` 照 LCL（`buttons.pp:409`）返回 `TTyCustomSpeedButton`，删前向声明与两处强转；S1-1 加「第三方成员按下时交出它、不假定 `is TTySpeedButton`」，过程变量钉住返回类型。附录 C-2 的 C1-1、C-4、附录 D、不兼容清单第 5 条同步。**PageControl.ActivePage 重新评估**：先例读反了——LCL 的 getter 强转是真话，因为 `TPageControl.ChildClassAllowed` 只收 `TTabSheet`（`pagecontrol.inc:113-117`），LCL 也没有 `TCustomTabSheet`；接受任意页的 `TCustomTabControl` 对外写 `TCustomPage`。R7-4 改成按「宿主实际交出什么」分两种，Task 14（`ActivePage` / `Pages[]` → `TTyCustomTabSheet`，`CSnapshotTypeRenames` 加一行，S14-3）、Task 20（`Buttons[]` → `TTyCustomToolButton`）、Task 21（Ribbon 页、组 → Custom）写明改法；本次不改 PageControl 代码 |
| 2 | `97bb38e8` | 计划原文：中间类降级时尚未拆的后代（Task 2 的 `TTyToolButton`、Task 14 的 `TTyRibbon`）按快照顺序写全部名字、自己带类型 / 说明符的声明原位保留；Task 20 / 21 先把这些声明挪进 Custom 再换成 block 输出。2–4 期其它任务（Task 18、28 的降级）后代同任务拆，无此写法 |
| 3 | `72b0dfdc` | `test.designeditors` 加 `TestClassTypedRegistrationsMatchThePropertyType`（按名字沿属性类的祖先链找注册类型，至少 6 条），现在绿；Task 27 / 28 写明改类型的同一提交改 `PropEditors.pas:737-738/742-743/837` 的注册与 `:478/506` 的 `is TTyIconFont` |
| 4 | `2419f944` | `TTyCustomEdit` / `TTyCustomMemo` / `TTyCustomComboBox` 覆写 `RealGetText` / `RealSetText` 指向 `Text`（`TTyCustomMaskEdit` 的走 `SetMaskedText`）。核实副作用时发现两处 LCL 行为会改变 3.0 窗体，都挡掉：`csSetCaption`（`SetName` 会把新控件的名字写进文字）从三个 Custom 类的 `ControlStyle` 去掉；`ActionChange`（关联的 Action 每变一次把它的 Caption 盖到文字上）期间不让 Caption 写进文字。`.lfm` 里没有 Caption（示例 / 测试全扫）、`Text` 的 stored / default 不变、Caption 不 published、Text 写入的 `OnChange` 次数不变（测试钉住）、主题 / 绘制不读 Caption。V20、Task 31 第 6 条、`docs/controls/updown.md` 从「限制」改为「已解决」 |
| 5 | `800565ad` | `TTyCustomNumericEdit` 加载期间暂存 `Value`、`Loaded` 时设入（Currency / Track / Calc / CalcCurrency / FloatSpin 继承，核实它们都不覆写 `SetValue`）；测试：第三方按「Value、Decimals」发布，Decimals=4、Value=3.14159 往返得 3.1416，「Value、MaxValue、MinValue」发布 -5 不被半个范围钳住。仍与顺序有关的（SpinEdit、ProgressBar、Gauge、TrackBar：setter 当场钳）写进 Task 31 第 2 条 |
| 6 | `0a152cbd` | `check-lfm-props.py` 从 `lcl/controls.pp` 读 `TControl` / `TWinControl` / `TCustomControl` / `TGraphicControl` 的 published 段、从 FPC rtl 的 `classesh.inc` 读 `TComponent` 的（读出的正是 V3 的 15 个），找不到 Lazarus 源码就以 2 退出。重跑 0 误报；临时坏 `.lfm`（`Bogusity = 1`）仍报出，已删 |
| 7 | `8e8b088b` | G9 常驻守卫 `TestGeneratedMimicsMatchTheirFinalClass` + 生成的 `tests/test.customclasses.mimic.pas`（59 对）；生成器 `gen-mimic.py` 写进计划，「每个类的标准步骤」第 7 步要求每次拆完重跑 |
| 7 | `d17e6ed0` | P1 每家族一条真实消息路径（按钮 / 标签 / 进度条点击、编辑框打字与退格、多行回车、复选框空格与点击、组合框与滑块方向键 / End），与最终类并排比 |
| 7 | `7bbe1c34` | SpeedButton / Edit / CheckBox / ComboBox 的 `TabStop`、FloatSpinEdit 的 `UseThousands` 改读「只发布这一个属性的第三方子类」的 RTTI default，并先证明上一层的值不同 |
| 7 | `6fb06bf1` | T-d 逐像素补上 Tag、Edit、Memo、CheckBox、RadioButton、ComboBox、ProgressBar、TrackBar（防空图：位图里必须有非哨兵像素）。MaskEdit 由 G9 的 typeKey / 样式比较与 `TestThirdMaskEdit` 覆盖，没单独画 |
| 7 | `8f489161` | G3(a) 删除：最终类只有 `property X;` 时它原样继承，(a) 只会在 (b) 已红处红，没有变异能单独让它红；说明符在哪一层由 G9（第三方一侧）与 G6（对 3.0）查 |
| 8 | `475bf84f` | 注释：`ColorBox.pas:549`、`GlyphButtons.pas` 的 `GlyphLayout`「Published so」与 `UnpressSiblings` / 类头「sibling TTySpeedButtons」、`CalcEdit.pas:30-31`、`CalcCurrencyEdit.pas:11`；`tools/gallery/tyGalleryCapture.pas` 的 `TButtonAccess = class(TTyCustomButton)` |
| 8 | `2110cefd` | `docs/controls/iconfont.md` 补 `ChangeStamp`；工具窗口规格 `:579` 原处标注改名 |
| 8 | `3986167e` | 不兼容清单第 9 条（经基类 / Custom 引用访问 LCL protected 的 22 个成员，按 `controls.pp` 逐个列出，`OnKeyDown` 等 `TWinControl` public 的不在此列）与迁移写法；Task 31 第 8、9 条（要同步的 6 个文档、`Base.pas` 删掉的长注释的去处）；A8-1 挪进 C-2（C8-1），Task 8 Step 2 / 5 的见证改为 `TThirdColorBox`；N31（G6 不比 stored 方法与 setter 身份，由 G3b、G9 与行为测试兜底） |

- 全量（`lazbuild -B` 后复制成 `tests/tytests-split1fix.exe`，输出重定向）：**8631** 条，**0 错 0 败**（= 1 期签收的 8617 + P1 新增 12 + 设计期检查 1 + G9 1），红名单空。守卫 11 条、P1 37 条。
- `check-lfm-props.py` 0 误报；`check-example-po` 101 个文件 0 问题；设计期单元用 fpc 对着测试构建产出的运行时单元单独编过（7 个单元，0 错，4 个既有警告都在 AdvChart 编辑器），输出只写 scratchpad。
- 变异（改 → 读回比对 → `lazbuild -B` → 跑点名 suite → 写回原字节并核对；最后 `-B` 重编再跑全量）：全部红。
  - `FindDownButton` 返回类型改回 `TTySpeedButton`（+ 前向声明、强转）→ 编译期红（S1-1 的过程变量赋值 Incompatible types）。
  - `PropEditors.pas:738` 注册类型改成更派生的 `TTyLucideIconFont`（模拟 D11 后的失配）→ `TestClassTypedRegistrationsMatchThePropertyType` 红。
  - Edit 的 `RealGetText` / `RealSetText` 改回 inherited → UpDown 驱动测试与 Caption 测试红；Edit 保留 `csSetCaption` → 「命名不改文字」红；去掉 Edit 的 ActionChange 守卫 → 「Action 不盖文字」红；MaskEdit 的 `RealSetText` 不走掩码 → 红；Memo、ComboBox 的 `RealSetText` 改回 inherited → 各红。
  - NumericEdit 去掉加载期暂存 → `TestNumericValueSurvivesAnyPublishingOrder` 红。
  - M-G9：`TTyCustomSpeedButton` 的 `TabStop default False` 挪进 `TTySpeedButton` → G9、G3b、`TestThirdSpeedButton`（新 RTTI 断言）红，G6 绿——正是 G9 要补的视角。Edit 的 `TabStop default True` 挪进 `TTyEdit` → G9、G3b、G6、`TestThirdEdit` 红。
  - 真实输入：Edit 的 `UTF8KeyPress` 只对 `TTyEdit` 生效 → `TestInputThirdEditTakesTypingAndBackspace` 红。
  - 逐像素：CheckBox 的 typeKey 只对 `TTyCheckBox` 给 `'TyCheckBox'` → `TestMimicsPaintLikeTheirFinalClass`、`TestThirdCheckBox`、G9 红。
  - **S2-4**（补跑）：`TTyToolButton` 发布段对调 `Version` / `Enabled` 两行 → G6 红。
  - G9 覆盖：从生成单元删掉 `TTyBadge` 那一对 → G9 红（「split class without a mimic」）。
- 偏差：
  - 第 4 条比提示多做两件：`TTyCustomMaskEdit` 的 Caption 走掩码（否则 Caption 与 Text 对掩码框说的不是一回事）；`csSetCaption` 与 `ActionChange` 两处防护（核实副作用时发现的，见上表）。这是 LCL `TEdit` 有、3.0 Ty 编辑框没有的两种行为，选的是「3.0 行为不变」。
  - 第 5 条的数值族修成与顺序无关；SpinEdit / ProgressBar / Gauge / TrackBar 没改代码，按提示写进 Task 31 的发布顺序要求。
  - 第 7 条 G3(a) 选「删除并说明」而不是改判据：最终类只剩 `property X;` 之后，RTTI 一侧能红的判据就是 G9。
  - G9 的流式比较要两个宿主窗体（同一父控件上两个实例的 TabOrder 会不同），已写进判据。
  - 工具（`tools/gallery`）只改了一行类型，未编译（实现 agent 不编 tools）。
- 主控已做（本轮修复之前，在 `41509003` 上）：`lazbuild -B` 编过 `tycontrols.lpk`、`tycontrols_dt.lpk`（0 错）与全部 49 个 examples（0 失败）；逐个启动 49 个示例枚举窗口类，全部只有主窗体、没有 `#32770` 错误框；`check-example-po` 0 问题；`check-lfm-props.py` 的 51 处 Hint / Cursor 报告判为脚本误报（本轮第 6 条已修）；已通知 AdvChart 会话摘取 `e4f3c648`、通知 3.0 会话移植规矩。
- 主控待做：本轮改了 `source/`（Edit、MaskEdit、Memo、ComboBox、NumericEdit、UpDown 注释、GlyphButtons、ColorBox / CalcEdit / CalcCurrencyEdit 注释）、`designtime/`（未改）与 `tools/gallery/tyGalleryCapture.pas`——重编两个包与全部 examples、`check-lfm-props.py`、冒烟（toolbar 示例点 GlyphButton / ToolButton，grid 示例计算列编辑器字体为红；顺手在任一示例里拖一个 TTyEdit 到窗体，确认文字不是控件名）；本轮新增的「Caption 就是 Text」与 NumericEdit 加载期暂存是 3.0 没有的行为，告诉 3.0 会话**不要**移植（4.0 才有第三方子类这个场景）；gallery 工具下次跑时核对。
### 2 期
- 起点：`feat/custom-classes` @ `22935b75`（第 0、1 期签收、期末修复与主控编包冒烟之后）。
- 提交（正文都带 `Refs #8`）：Task 12 `2a614fbf`、Task 13 `120e73c5`、Task 14 `2603e09b`、Task 15 `d21b9d25`、Task 16 `150f7539`、Task 17 `70329204`、Task 18 `f045364b`；收尾修复 `e5bac174`（CoolBar）、`880b8d8a`（P2 测试）、`b683cae2`（TabHeight 探针）。
- 拆分：42 个最终类进 `CSplit`（`CPending` 剩 55 个，全是 3、4 期的）；`TTyCustomTabStrip`、`TTyCustomGrid` 降级进 `CDemoted`；`TTyShellTreeLink` 改挂 `TTyCustomTreeView`（0 发布，不进 `CDemoted`）；`TTyRibbon`（3 期才拆）按快照顺序写了整条链的发布段，`Align default alTop` 原位保留。`CSnapshotTypeRenames` 加 `TTyTabSheet→TTyCustomTabSheet`。G9 的模拟子类 101 对。设计期：`TTyShellListView` / `TTyShellTreeView` 的 `Directory` 编辑器挪到 Custom 类；`designtime/` 用 fpc 对着测试构建产出的运行时单元单独编过（0 错，4 个既有警告都在 AdvChart 编辑器），输出只写 scratchpad。
- 本期 suite：守卫 11 条、`TTyCustomClassesP2Test` 27 条、P1 37 条；`TVersionTest` 6、`TDesignEditorsTest` 6、`TPaletteIconTest` 3、`TTyFocusTabStopTest` 7、`TTyClickFocusTest` 4，全绿。
- 全量：一次编译（P2 单元缺 4 个 uses，补上即过）后 **8659** 条，0 错 1 败——`TTabHeightSentinelTest.TestExplicitHeightIsStreamedAndZeroRoundTrips`：测试探针直接继承 `TTyCustomTabStrip`、靠它发布的 `TabHeight` 流式，降级后不流了；按 N30 给探针自己补 `published property TabHeight;`（不改断言，`b683cae2`）。变异之后 `lazbuild -B` 再跑全量（终验）：****8659** 条，**0 错 0 败**，红名单空**。
- 基线对账：8659 = 1 期签收后的 8631 + P2 的 27 + CoolBar 回归 1。
- 编译器与运行报出、补进附录 C-4 的：`GridPanel` 的格表硬转、`CoolBar` 的 `OwnerBar`、`ListGroupPanel` 的 `TTyListGroups`、`TreeSelect` 的 `Picker`、`Grid` 的 `TTyGridStrings`、`TreeView` 实现段私有函数与比较器、`ActivePage` / `Pages[]` 的使用者（tabcontrol 示例、`test.parity.container`）、弹层 API 的测试侧（`test.parity.combo`、P1 的 access 类）、D10 的全部处理过程。
- 结构核对（不看测试）：最终类只有 `property X;`（G3b 绿）；带接口的 Custom 类头保住接口（`TTyCustomListBox` / `TTyCustomListView` / `TTyCustomTreeView` / `TTyCustomScrollBox` / `TTyCustomGrid` 的 `ITyScrollBarFrameHost`）；R3 行只有 `TTyCustomTabSheet` 的 Left / Top / Width / Height，在 Custom 的 published 段；`git diff 22935b75..HEAD -- source` 里改了父类的类都在附录 C-0；没有新增 `RegisterClass`；不许碰的共享文件、排除单元与 `Base.pas` / `Component.pas` 本期 0 行改动；每个改过的文件 `split.py check` 都 ok。D3 由脚本按附录 E 的对应类逐个查 `vis` 决定，抽查：`TTyCustomPanel.Alignment` public、`VerticalAlignment` / `WordWrap` / `ShowAccelChar` protected（`TCustomPanel`）；`TTyCustomTreeView` 的 `Images` / `Items` / `Options` public、`Indent` 与 Ty 独有的事件 protected；`TTyCustomListView` 的 `LargeImages` / `SmallImages` / `ViewStyle` protected、`Checkboxes` / `MultiSelect` public；`TTyCustomTabStrip` 的 `OnChange` protected、`TabStop` public（Q6）；`TTyCustomGrid` 的网格属性 protected，`TTyCustomDrawGrid` 照 `TCustomDrawGrid` 把 ~~13~~ 14 个（RowCount、FixedRows、FixedCols、Options、默认行高列宽等；第 2 期期末修复补上漏提的 `OnHeaderClick`，`grids.pas:1561`）提成 public；`TTyCustomStringGrid` 的 `RangeSelectMode` / `OnGetCellHint` protected（`TCustomGrid`），其余 public。
- 附录 C 本期逐行：C-1 的 A15-1、A17-2、A17-3、A17-4 已落实；**A17-1 执行中核实不是翻转**（ShellTreeView 覆写 `SupportsItemModel = False`，条目层当场拒绝，走不到节点取图片列表这条路），改归 C-2 的 C17-1，见证改用 `TThirdTreeView`（附录 C 已改写）。C-2：C11-1、C11-2、C11-3（格表与释放通知；无独立测试，与 S12-1 同一路径，审查覆盖）、C12-1、C13-1、C13-2 已放宽。C-3：RadioGroup 的 C5-2、`ToolGroupPanel.AddButton`、Transfer 的窗格、`TreeSelect` 的内部树、设计期组件编辑器保持。
- R7 本期新增 / 改的签名（附录 D 已标）：`TTyPageControl.ActivePage` / `Pages[]` / `FPages` → `TTyCustomTabSheet`（`AddPage` / `AddTab` / `AddTabSheet` 仍返回 `TTyTabSheet`，`RegisterPage` / `UnregisterPage` 放宽）；组合框弹层 API（`CreatePopupList` 及 10 个覆写、`PopupList`、行自绘 / 量行高）→ `TTyCustomListBox`；TreeView 21 个、HeaderControl 3 个事件类型的 Sender → Custom 类（D10）；`TTyCoolBands.OwnerBar` → `TTyCustomCoolBar`。`docs/controls/pagecontrol.md`、`treeview.md`、`treeselect.md`、`headercontrol.md` 的类型与处理过程签名同步改了。
- 集中变异（`<scratchpad>/mut2.py`，沿用 1 期的 `mut.py`：改 → 读回比对 → 编译 → 跑点名 suite → 写回原字节并核对 → 最后重编；22 条）：
  - **红**（18）：M-G6c（删 TabSheet `Left` 的 `stored False`）、M-G3a（挪进 `TTyTabSheet` → G3b 与 G9 红）、TabSheet 的 R2s `TabOrder stored False` 删掉（G6）、M-G9（ListBox 的 `TabStop default True` 挪进最终类 → G9、G3b、G6）、M-G7（`TTyCustomScrollPanel` 改挂回 `TTyScrollBox` → G7、G2）、M-T（**Panel 家族**：`GetStyleTypeKey` 只对 `TTyPanel` 给 `'TyPanel'` → `TestThirdPanel` 红）、S12-1、S12-2、S12-3、S14-1、S14-2、A15-1（`TTyCustomValueListEditor` 改挂回 `TTyListBox` → 那条测试的第二句与 G7、G2 红）、S17-1、S17-2（ShellTreeView 与模拟树两条都红）、S17-3、CoolBar 修复去掉守卫（`TestFreeingTheBarWhileItsOwnerLives` 红）。
  - **编译期即挡住**（4，等价于红）：M-T 按「把覆写挪进最终类」写——`test.controls.panel` 经 access 类调 `GetStyleTypeKey`，编不过（改用上面的写法再变一次，红）；S14-3 把 `ActivePage` 改回 `TTyTabSheet`——测试里 `pc.ActivePage := 第三方页` 编不过；D10 把 `OnGetText` 的 Sender 改回 `TTyTreeView`——`TTyCustomTreeView` 自己传 `Self` 编不过；`TTyCustomDrawGrid` 少提一个 `FixedRows`——经 Custom 引用访问的测试编不过。
  - 本期没做：C11-3（与 S12-1 同一判断，审查覆盖）；S15-1（编译期放宽，编过即证）；T-f 的 Sender（同 D10，编译期）。
- 判据上与计划文字的差异：
  - **S14-3** 的类型钉子改用 RTTI（`ActivePage` 的 `PropType^.Name = 'TTyCustomTabSheet'`）：getter 在另一单元是 private，取不到方法指针。
  - **S15-1** 无头化：经 access 类调 `CreatePopupList` 拿到检查组合框的弹层，断言它是 `TTyCheckListBox` 而不是 `TTyListBox`，勾一项后经 `PullChecksForTest` 回写宿主。
  - **S17-1 / S17-2**：见证见上（A17-1 改归 C-2；ShellTreeView 的见证是「加条目当场抛 `ETyTreeItemMode`」）。S17-3 用内置 `TTyShellListView`：它的内置图标同时挂在 Large / Small 两个列表上，测试把两个都换成测试图片表。
  - **S12-3**：观察的是 `OnChange`——改 band 的 `Break` 后宿主收到通知。
  - **`TThirdStringGrid`** 发布 `RowCount`、`Header`（没有 `ColCount`，列就是 `Header.Columns`）；`TThirdDrawGrid` 发布 `RowCount`、`OnGetCellText`；另加 `TestDrawGridPromotesWhatTCustomDrawGridPromotes`（经 `TTyCustomDrawGrid` 引用读写提升的那批）。
  - **T-c 的宿主窗体往返**：RadioGroup、Transfer 自己建并拥有子控件，当根流式会把它们当子对象写出、读回时重复（Transfer 的箭头按钮类没注册，RadioGroup 的 ItemIndex 被多出来的按钮吞掉）——改为流式拥有它的窗体，`.lfm` 就是这么存的。
  - **T-e** 照 1 期：Cascader 的 `Nodes`（集合）与 `Separator`（3.0 就没有 default）新实例必写，不做 T-e，写了注释；GridPanel / ListBox 的集合类属性同理只验序数类。
  - P1 的 fixture 与 T-b / T-c / T-d / T-e 四个检查提成基类 `TTyCustomClassesPhaseCase`（P1、P2 共用），`NewSentinelBitmap` / `HasProp` / `NeedWidgetSet` / `MousePos` / `CSentinel` 挪到接口段。
  - 发布段之外丢掉的注释：cs.py 只认紧贴属性的那一块注释，几处「两块注释相邻」或「段尾孤立注释」被丢，逐个补回（CoolBar 的 GripperWidth、TreeView 的 `C3: paint events`、Grid 的两句中文、ExPanel / CheckGroup 的 Caption 说明改写成真话）；GroupBox 那段「AutoSize 由基类发布」的说明已不成立，删掉、在最终类 `AutoSize` 上方写一句它为什么能贴合内容。cs.py 对 TabStrip 里 `{$R-}` 嵌在注释中的写法解析失败，TabStrip 的降级改为手工（只删纯重发布行、`OnChange` 挪到 protected）。
- 注释（N27）：单元头与行内写着「subclass of TTyPanel / TTyGroupBox / TTyListView / TTyTreeView」的改成真话；`{ TTyXxx }` 一类分隔注释改成 Custom 名；`CompEditors.pas` 的「also covers TTyShellTreeView」改写为「4.0 起由默认编辑器接手，反正那里没有动词」。
- 计划外发现：**`TTyCoolBar` 运行期被 `Free`（窗体还活着）必 AV**——拥有者在 `RemoveComponent` 里把移除通知发给它拥有的每个组件，正在析构的 bar 也收到，而它的析构已经释放了 band 列表，`Notification` 去旧列表里找「被释放的子控件」。3.0 同一份代码（`e5bac174` 修，带回归测试）；随窗体一起释放的路径不经过这里，所以既有测试与示例都没碰到，是 G9「宿主活着时逐个释放」第一次走到。**3.0 也该修**。
- 【主控执行】待办：编 `tycontrols.lpk` / `tycontrols_dt.lpk`、编全部 examples（本期改了 `examples/tabcontrol/umain.pas`、`treeview/showcasemain.pas`、`demo/mainform.pas`、`rtl/umain.pas`、`containers/umain.pas`、`antdesign/umain.pas`，未编）、`check-lfm-props.py`、冒烟；手点：containers 示例的 ScrollBox / 视口（`TTyScrollContent` 从 `.lfm` 读入）、shell 示例的树与列表有图标、tabcontrol 示例关页 / 删页 / 切页（状态栏标题）、treeview 示例的虚拟树与列（处理过程签名改了）；期末审查；通知 3.0 会话：本期已拆单元与移植规矩，外加 CoolBar 的 `Free` 崩溃要在 3.0 修。
### 第 2 期期末修复（2026-10-02，起点 `cadb94d2`）
- 起因：主控派的第 2 期期末审查（规格核对、代码质量）与审查探针（scratchpad `splitrv2/`：`lfmrt/`、`probe/`、`isas/`、`mut.py`、`g9-*.txt`）。
- 提交（每个问题一个，正文 `Refs #8`）：

| # | 提交 | 处理 |
|---|---|---|
| 1 | `39fbf45c` | **G9 闪烁**：比较改为流式**宿主窗体**、取它写给子组件的那段（`FreshStreamBody(host)`），控件自建并自己拥有的子组件不再写出——与 `.lfm` 实际存法一致；构造时取自时钟的 `TDateTime`（`TTyAnalogClock.Time`，同一类隐患，八次没赶上而已）两边钉成同一值；每对之间 `DestroyComponents` 清掉宿主残留（GridPanel 的格归窗体所有，比面板活得长，原先会写进之后每个类的比较）；宿主什么都没写出时记为不同（防空比较）。核实没有漏比：临时插桩把两种流式逐类落盘对比，101 对的控件自身那段逐行相同；其中 25 个类（组合框一族、列表、树、网格、Transfer、ScrollBox 等）根流式多出的只是自建子组件；GridPanel 反而多比了归窗体所有的 4 个格。同一次插桩里旧写法又红了一次（StringGrid 的 `DateTime`）。计划 G9 ③ 的判据随第 10 行一起改写 |
| 2 | `40e5ae48` | **索引先于条目读入**：`TTyCustomRadioGroup.ItemIndex`、`TTyCustomListBox.ItemIndex` / `TopIndex`（ListBox 一族全部继承：CheckListBox、OfficeListBox、AdvancedListBox、ValueListEditor、ColorListBox、FontListBox）、`TTyCustomStringGrid.Col` / `Row`：读入期间值还指不到条目时暂存，`Loaded` 生效（LCL `radiogroup.inc:383-384` 的 `FReading`、`:504-510` 的 `ReadState`；本库 TabStrip / Segmented 同法）。读入时就落得下的照旧当场生效——最终类都先发布条目，3.0 窗体的行为一字不变。延后生效的不发通知（读窗体不是选择变化）；ListBox 在 `Loaded` 里按最终类的顺序先落 `ItemIndex`、再落读到过的 `TopIndex`（否则滚动被选中行带走）；RadioGroup 读完仍越界（坏 `.lfm`）照旧落成 -1 不抛。`TTyCustomListBox.TopIndex` 的属性写入改走新的 `WriteTopIndex`（只给流式记值，内部滚动仍调虚方法 `SetTopIndex`）。`TThirdRadioGroup` 改回 LCL 顺序（`extctrls.pp:808-809`），`TThirdListBox` 同（注明 LCL `TListBox` 恰好 Items 在前）；新增 `TestIndexesReadBeforeTheirItemsWaitForThem`（TopIndex/ItemIndex/Items 倒序的列表、Col/Row 先于列与行数的网格）。逐类扫过、无需改的：CheckGroup（`Checked[]` 不流式）、GridPanel（尺寸是字符串、格在 `Loaded` 对账）、PageControl / TabSet（TabStrip 已暂存）、ListView `SortColumn`（不按列钳）、Transfer（`Selected` 是字符串表）、ListGroupPanel / TreeSelect（选中不发布） |
| 2 | `a30d4906` | 扫描中发现的同类：**ColorListBox / ColorBox 的 `Selected`** 依赖 `Style` 组出的色板，而色板在 `Loaded` 才重建；读入时在默认 16 色里找不到扩展 / 系统色就落成「没选中」。**最终类在 3.0 就坏**（`TTyColorListBox` 把 `Selected` 发布在 `Style` 前；`TTyColorBox` 的 `Style` 在前但重建同样延到 `Loaded`）：IDE 存过的窗体选 `clMoneyGreen` 读回来是 `clDefault`。改法照 LCL（`colorbox.pas:871-878` 保存颜色本身、`:1058-1062` 在 `Loaded` 里落）：读入期间暂存颜色，`Loaded` 重建色板时就按它保留、再选中。测试：`TColorBoxTest` / `TColorListBoxTest` 各一条最终类窗体往返，P2 一个 `Selected` 先于 `Style` 的模拟类 |
| 2 | `48bf5c8b` | 第 1 期的同类（计划外，按第 2 条一并做）：**`TTyCustomComboBox.ItemIndex`**（LCL `TComboBox` 就是 ItemIndex 在前，`stdctrls.pp:474-475`；LCL 在 `customcombobox.inc:1040-1043` 读入期间同样存着）与 **`TTyCustomButtonGroup.ItemIndex`**：同法暂存、`Loaded` 生效且不发 `OnChange`。`TThirdComboBox` 改回 LCL 顺序，加 `TestButtonGroupIndexReadBeforeItsItemsWaits` |
| 3 | `9e167ed5` | **CheckComboBox**：`PushChecksToList` / `PullChecksFromList` / `PullChecksForTest` 参数、`SetState` / `PopupCheckClick` / `DropDown` 的判断与强转放宽到 `TTyCustomCheckListBox`；第三方 `CreatePopupList` 够不着私有的 `PopupCheckClick`，所以 `DropDown` 在弹层没有自己的 `OnClickCheck` 时由组合框补接。附录 C 的 C6-5 从 C-3 改归 C-2。见证 `TestCheckComboDropsAThirdPartyCheckList`：覆写 `CreatePopupList` 交出自己的 `TTyCustomCheckListBox` 子类，下拉推送勾选、弹层点勾回写、开着时 `State[]` 同步、`OnClickCheck` 已接上，四句各对应一个变异 |
| 4 | `3ccbd108` | **`TTyCustomShellTreeView.ShellListView`** 字段 / setter / 属性改 `TTyCustomShellListView`（LCL `shellctrls.pas:139`）；`TTyFilterComboBox.ShellListView` 照 LCL `filectrl.pp:167` 保持最终类（附录 D）；反方向 `ShellTreeView: TTyShellTreeLink` 本来就是接缝类，不改。`CSnapshotTypeRenames` 改成四列（类、属性、旧类型、新类型），D11 四行保留 `*`（按类型整体改名是本意），`ActivePage` 与 `ShellListView` 两行按类 + 属性限定。Task 17 Step 1、附录 D、不兼容清单第 5 条与「仍然守的」一段改写；`docs/controls/shelltreeview.md` 补一句。见证 `TestShellTreeDrivesAThirdPartyShellList`（第三方 `TTyCustomShellListView` 挂到树上、联动 `Directory`、释放后解链、RTTI 类型名） |
| 5 | `fb7e8b7a` | `TTyCustomDrawGrid` public 段加 `property OnHeaderClick;`（`grids.pas:1561`）；`TestDrawGridPromotesWhatTCustomDrawGridPromotes` 补它；2 期签收里的 13 改 14 |
| 6 | `455a1e2b`、`2fc82953` | `TTyCustomTabSet.TabIndex` 改 public 并注明原因（祖先 `TTyCustomTabStrip` 已 public，protected 重声明挡不住，N16；LCL `TCustomTabControl` 是 protected，`comctrls.pp:471`）；加一条经 Custom 引用读写的测试。**变异改回 protected 仍绿**——FPC 回落到祖先的 public 那个，这正是改它的理由；第二个提交把这一点写进测试注释，不冒充见证 |
| 7 | `ed8304f6` | `TTyCustomStringGrid` 析构释放 `FFilterAllValues` / `FFilterChecked`。回归 `TGridLifetimeTest.TestFreeingAGridLeavesNothingBehind`：热身两轮后建放 20 张网格，堆增长须小于 20 个 `TStringList`；修前稳定 +6400 字节（每张 320 = 两个列表） |
| 8 | `422e3ee0` | **第 8 条现在就做了**：常驻守卫 **G10 `TestFreshFormFileTextUnchanged`** + `tests/fixtures/customclasses/fresh-streams.txt`（156 个类，`CNotSplit` 之外的全部注册类，覆盖第 1、2 期已拆与 3、4 期待拆的类）。经宿主窗体流式（同 G9），时钟值钉住；本机来的值（`CMachineValues`：FontComboBox / FontListBox 的已装字体、ShellTreeView 的驱动器数）只留行、值打码；**全部字符串值打码**（资源串、区域设置、本机——全量里先跑的 suite 装过翻译就全变；字符串由 G9 在同一次运行里逐个比）。夹具在 G6 全绿时冻结。计划 Task 32 Step 6 改为「G6 退役前确认新实例流式文本已冻结成常驻守卫」，D9、G9 ③、G10 判据、「仍然守的」一段同步 |
| 9 | `7d9748d4` | 注释：`ShellListView.pas` 接缝类说明（唯一直接后代是 `TTyCustomShellTreeView`）与 `ShellTreeView` 属性说明、`GridPanel.pas` 的格表三处（外加 `RegisterCell` 上「a different unit」的假话）、`CoolBar.pas` 的 typeKey 注释；`docs/controls/colorbox.md` 三个钩子的 4.0 签名；`docs/controls/shelllistview.md` 接缝段。计划：Task 31 第 5 条改写（见偏差）；附录 D 的 `OwnerBar` 标「改（私有）」 |

- 全量（`lazbuild -B` 后复制成 `tests/tytests-split2fix.exe`，输出重定向）：**8668** 条，**0 错 0 败**，红名单空。对账：8659 + P2 新增 4（索引、第三方弹层、第三方 shell 列表、TabSet）+ P1 1（ButtonGroup）+ G10 1 + 颜色往返 2 + 网格寿命 1 = 8668。守卫 12 条、P1 38 条、P2 31 条。
- **G9 连跑**：开发中间构建上 12 次全绿；终版 `-B` 构建上守卫 suite 单独连跑 **12 次全绿**（G10 一并）。修前审查记录 8 次红 7 次。
- `check-lfm-props.py` 通过；`check-example-po` 101 个文件 0 问题；设计期单元用 fpc 对着测试构建产出的运行时单元单独编过（0 错，4 个既有警告都在 AdvChart 编辑器），输出只写 scratchpad。
- 变异（`<scratchpad>/s2fix/muts.py`：改 → 读回比对 → 编译 → 跑点名 suite → 写回原字节并核对哈希；最后 `-B` 重编再跑全量；25 条）：
  - **红**（22）：MG9（ListBox 的 `TabStop default True` 挪进最终类 → G9 在宿主流式下仍红，G3b、G6、G10 也红）；DEFDEL（删 `TTyCustomTabSheet.TabVisible` 的 `default True` → **G10 红**、G6 红，G9 与 P2 绿——正是 G10 要补的那块）；RadioGroup 不暂存、ListBox 不暂存 ItemIndex / 不暂存 TopIndex / 不重落 TopIndex / 延后落时发通知、网格不暂存 Col / Row、ComboBox 不暂存 / 延后落时发 `OnChange`、ButtonGroup 不暂存（各自那句断言红）；ColorListBox / ColorBox 不暂存 `Selected`（最终类往返与 P2 模拟类红）；CheckComboBox 四处各改回 `TTyCheckListBox` / 不补接 `OnClickCheck`（见证测试对应的那一句红）；FilterComboBox 的 `ShellListView` 也改成 Custom（→ G6 红：限定后的改名表不再放行）；网格析构不释放（`TGridLifetimeTest` 红）。
  - **编译期即挡住**（2，等价于红）：ShellTreeView 的 `ShellListView` 改回 `TTyShellListView`（见证里挂第三方列表编不过）；`TTyCustomDrawGrid` 去掉 `OnHeaderClick`（测试经 Custom 引用赋值编不过）。
  - **绿**（1）：TabSet 的 `TabIndex` 改回 protected——见第 6 行，无行为差异，属文档性修正。
- 偏差：
  - 第 2 条的做法是「读入时落不下才暂存」，不是 TabStrip / LCL 的「读入期间一律暂存」：前者让先发布条目的最终类（3.0 的窗体）读入路径一字不变，后者会把 RadioGroup 读入时触发 `OnClick` 的 3.0 行为也改掉。延后生效的那一步不发通知（同 LCL 读入）。
  - 第 2 条扫描范围比提示多出第 1 期的 ComboBox / ButtonGroup 与 ColorBox（同一类缺陷），各自单独提交。
  - 第 4 条测试 RTTI 钉类型名，而不是过程变量（getter 是字段读）。
  - 第 8 条 G10 的打码（字符串、本机值）是为让夹具不随环境变；尺寸仍按 Windows 量，与 G6 默认尺寸同一类依赖，写进了判据。
  - 第 9 条 Task 31 第 5 条原写「`RegisterComponentEditor(TMyTree, TTyTreeViewComponentEditor)`」是错的：库里组件编辑器的实现都 `as` 最终类（`CompEditors.pas` 的 `as TTyPageControl` / `as TTyTreeView` 等，附录 C-3），照抄会一点菜单就 `EInvalidCast`。改写为「自己写一个 `TDefaultComponentEditor` 子类、`PC` 写成 `Component as TTyCustomPageControl`」并给出加页的完整步骤。
  - G9 的计划判据改写放在 G10 那个提交里（同一处判据文字），没有单独提交。
- 计划外发现：
  - **ColorListBox / ColorBox 读窗体丢 `Selected`（3.0 就有）**：本轮 `a30d4906` 修，**3.0 也该修**。
  - **`TTyColorListBox` / `TTyColorBox` 的 `Items` 是 published 的（3.0 起）**：IDE 存窗体时把色板名字写成 `Items.Strings`，颜色（`Objects[]`）不流式；读回来、`Style` 没写的窗体不重建色板，每一行都是黑色色块、默认选中也丢（探针：默认样式往返后第 2 行 `ColorAt(1)` = 0、`ItemIndex` = -1）。示例 `.lfm` 是手写的、没带 `Items`，所以冒烟看不到。LCL 的 `TColorListBox` / `TColorBox` 不发布 `Items`，`Loaded` 无条件 `SetColorList`。本轮**没改**（动 published 段与 `Loaded` 语义，超出范围），交主控定：3.0 修法可以是 `Loaded` 无条件按 `Style` 重建（但 `SetPaletteStyle` 的注释说不重建是为保留手填的 `Items`，要权衡）。
  - StringGrid 每实例漏两个 `TStringList`：`ed8304f6` 修，**main / 3.0 同样有**（主控移交）。
  - `docs/controls/checkcombobox.md:5` 还写「继承自 TTyComboBox」：归 Task 31 的「从 3.0 升级」一并改。
- 主控已做（本轮修复之前，在 `cadb94d2` 上）：`lazbuild -B` 编过两个包（0 错）与全部 49 个 examples（0 失败）；`check-lfm-props` 通过、`check-example-po` 0 问题；逐个启动 49 个示例无错误框。CoolBar 的 3.0 崩溃已移交 3.0 会话。
- 主控待做：本轮改了 `source/`（RadioGroup、ListBox、Grid、ComboBox、ButtonGroup、ColorBox、ColorListBox、CheckComboBox、ShellTreeView、TabSet、GridPanel / CoolBar / ShellListView 注释），`designtime/` 未改、`examples/` 未改——重编 `tycontrols.lpk`、`tycontrols_dt.lpk` 与全部 examples 并冒烟（顺手：inputs 示例的颜色列表、shell 示例的树与列表联动、grid 示例的值筛选面板开关几次）；移交 3.0：ColorBox / ColorListBox 的 `Selected`、StringGrid 泄漏两个修复，以及「`Items` 发布导致色块全黑」这一条待定的发现；告诉 3.0 会话**不要**移植第 2 条的读入暂存（ComboBox / ListBox / RadioGroup / Grid / ButtonGroup：只有第三方按 LCL 顺序发布时才用得上，4.0 才有这个场景）。
### 3 期
### 4 期
### 计划外发现
- `TTyColorComboBox` 的下拉列表（`TTyColorMorePopupList`）不读宿主的 `ColorRectWidth` / `ColorRectOffset` 与伪行颜色，只有字段区用得上——3.0 起如此，与本计划无关；`TTyColorBox` 的下拉（`TTyColorPopupList`）是读的。是否算 bug 交主控定。
- `TTyIconFont.Version: Integer` 遮住库版本 `Version: string` 的写法（见 Task 1 签收），已按 `ChangeStamp` 先例改名。
- 计划 C-4 列的 `test.parity.buttons` / `test.parity` 行号是声明成派生类型的变量，原本就编得过；真正要改的在 `test.trailingzone`、`test.combohint`、`test.parity.combo` 的 access 类，编译器报出来才补上。
### 遗留

#### 第 0、1 期 · 主控已做（4a870bc5 之上）

- `lazbuild -B` 编 `tycontrols.lpk`、`tycontrols_dt.lpk`：0 错；全部 49 个 examples：0 失败。
- `check-lfm-props.py`：通过（0 误报）；`check-example-po.py`：0 问题。
- 冒烟：逐个启动 49 个示例并枚举可见窗口类，全部只有主窗体、没有 `#32770` 错误框（`scripts/smoke-launch-examples.ps1` 不认错误框，主控另用按窗口类判断的脚本）。
- 已通知 AdvChart 会话摘取 `e4f3c648`；已告知 3.0 会话拆分后的移植规矩。审查用的临时工作树 `split-mut` 已删除。
