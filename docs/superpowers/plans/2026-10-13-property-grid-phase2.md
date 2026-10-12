# 属性表格第二期 实现计划（#65）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or subagent-driven-development) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（项目约定）**：测试先行；每个任务改代码 + 写测试并单独提交；任务之间只编 `tests/tytests.lpi`、跑本任务的 suite；最后一个任务跑一次全量、集中做变异、签收。中途不汇报，也不问要不要提交。测试写成「判据 + 必须变红的变异」。
>
> **谁来做**：标 **【主控执行】** 的步骤实现 agent 不做：编 `.lpk`、编 `examples/`、Lazarus 3.0 构建、GUI 冒烟、推送。
>
> **不改的文件**：`Painter.pas`、`StyleModel.pas`、`TextMenu.pas`、`Base.pas`、`Component.pas`、`Css.Parser.pas`、`AdvanceChart.pas` 及 `AdvChart.*`、`CHANGELOG*`。

**Goal:** 第一期（9b03fccb，计划 `2026-10-12-property-grid.md`）的 D7 留下的四件：同时检查多个对象、集合项的增删和排序、属性分类、按名字过滤。

**Architecture:** 都建在第一期的 `TTyPropertyRows`（对象 → 行）和 `TTyCustomPropertyGrid` 上。多选把「一个根对象」换成「一组根对象」，节点照旧按属性路径从根现找，每个根各找一次。分类和过滤只影响行的组织和可见，不碰读写。

**工作树：** `D:/Projects/ty-controls/.claude/worktrees/property-grid-2`，分支 `feat/property-grid-2`，起点 main `9b03fccb`。

**设计决定**：2026-10-12 用户让主控按自己的意见定（「把 1、2 都做了吧」，第一期的 D9 也是这样授权的）。下面的 D 项就是定案；执行中发现理由不成立的，在原处标注改了什么、为什么。

---

## 核实记录（执行前补）

| # | 待核的事实 | 影响 | 核实结果（2026-10-12，实现 agent 读源码） |
|---|---|---|---|
| V1 | 第一期节点「按路径从根现找」的实现，以及 `PropertyAt`、`ExpandedProperties`、`Refresh` 在结构变化时自动重建的逻辑 | 多根要改哪几处 | 节点不存实例，`HolderOf` 在父节点为 nil 时返回唯一的 `FRoot`，其余经 `ValueObject`（父节点的属性值，集合项按下标）一路往上找。读写全走这两个：`ReadText`、`WriteOn` / `WriteText`、`StoreFont`、`WriteStrings`、`ChangeOf`、`PropertyOf`（`PropertyAt` 只是转一手）、`ComponentNames`（候选根取 `FRoot`）、`StructureChanged`（逐个对象节点比 `FBuiltClass` / `FBuiltCount`）。另一个隐含的单根假设：节点只存**一个** `PPropInfo`（取自第一个对象的类），而 `GetOrdProp` 等是按 `PropInfo` 的 getter 偏移读的，换一个类（`TTyButton` 和 `TTyEdit` 的 `Caption`）必须按名字另找 `PropInfo`。`ExpandedProperties` 只按 `Path` 记（`HarvestExpanded` / `ApplyExpanded` 只读行，不碰对象），`RebuildRows` 按路径保留当前行，与根的个数无关，不用改。→ 多根改成「第 k 个根」版本的 `HolderIn` / `ValueObjectIn` / `PropInfoIn`，原函数等于 k = 0。 |
| V2 | `TCollection.Add` / `Delete` / `TCollectionItem.Index :=` 在 `TTyGridColumns` 等本库集合上会不会触发宿主的重排、通知（`Update`、`Notify`），有没有集合不允许用户增删（比如由宿主自动生成的列） | 增删要不要问宿主 | FPC 3.2.2：`Add` → 项的构造里 `Notify(cnAdded)`；`Delete` → `Notify(cnDeleting)` 再释放；`Index :=`（`SetIndex`，virtual）只 `FItems.Move` + `Changed(True)` → `Update(nil)`，**不发 `Notify`**。表格的列是 `TTyStringGrid.Header.Columns`（`TTyColumns`，不是 `TTyGridColumns`）：它覆盖 `Notify`，增删时维护「显示位置 → 下标」表并 `DoChange` → 表格 `HeaderChanged`（列几何缓存作废、重画）；**不覆盖 `Update`**，所以 `Index :=` 之后表格不知道，列几何缓存（`BuildColumnCache` 按下标累加宽度）是旧的，直到别的事让它作废。另外字符串表格的单元格按**列下标**存，集合层面的删、移不搬单元格（表格自己的 `DeleteColumn` / `MoveColumn` 才搬或改显示位置），所以经集合删一列，后面的列会显示被删那列的数据；移一列，表头动、数据不动。本库没有「不允许用户增删」的集合标记，也没有宿主钩子。→ 属性表格只用 `TCollection` 自己的接口（和 Lazarus 对象查看器的集合编辑器一样），宿主要连带搬数据的，在 `OnCollectionChanging` 里拒绝并调宿主自己的方法；为此事件要带上目标下标（见 D2 的改动）。~~`TTyColumns` 的 `Index :=` 不通知宿主，属于列模型的问题，本计划不改，报告主控。~~ **改（执行时）**：Task 2 的测试按计划要求「表格跟着变」，移列之后表格的单元格几何确实没跟上（变异 B8 证实），所以在 `TTyColumn` 上加了一个 `SetIndex` 覆盖：移完之后 `UpdatePositions` + 通知宿主（`DoChange`），只补「告诉宿主」，显示顺序的语义（位置表）不变。单元格内容按列下标存、集合层面移列不搬数据这件事没改，写进文档。 |
| V3 | 本库的右键菜单（`TTyPopupMenu`）在控件里怎么挂、测试里怎么点菜单项；ValueListEditor 有没有现成的右键菜单，会不会冲突 | D2 的菜单 | 现成做法是 `TTyEdit` / `TTyMemo`：覆盖 `DoContextPopup`，先 `inherited`（发 `OnContextPopup`，可置 `Handled`），应用自己设了 `PopupMenu` 就让给它，否则懒建一个无主的 `TTyPopupMenu`（`TTyTextEditMenu`），每次弹出前刷新各项的 `Enabled`，`PopUp(屏幕坐标)`，`Handled := True`；`(-1,-1)` 是菜单键。测试点菜单项走 `TTyPopupMenu.ActivateRowForTest(i)`：按渲染器的行（不可见的项跳过、分隔线占一行）找到项，禁用的不触发，否则 `Item.Click`。值列表编辑器没有自己的右键菜单，只继承了 `PopupMenu` / `OnContextPopup`；内嵌的行内编辑器是 `TTyEdit`，右键在它上面弹的是文字菜单，是另一个控件，不冲突。值列表编辑器的 `Insert` / `Ctrl+Delete` 只在 `KeyOptions` 含 `keyAdd` / `keyDelete` 时处理，属性表格的 `KeyOptions` 恒为 `[]`，不冲突；`Ctrl+↑/↓` 列表框按普通 ↑/↓ 移选择（不看 Ctrl），属性表格要在 `inherited` 之前拦下。右键按下列表框不选行（只处理左键），菜单要自己把当前行挪到右键的那一行。 |
| V4 | ValueListEditor 能不能有不可编辑、不带值的「分组标题行」；没有的话，用 `ReadOnly` + 加粗 + 空值的行能不能做到，样式怎么区分 | D3 | 没有标题行的概念。`TTyValueRow` 有 `ReadOnly`、`EditorKind = vekReadOnly`、`DisplayKey` / `DisplayValue`、`Bold`、`TextColor`，但 `Bold` 和 `TextColor` 只作用于**值**列；键列一律用行样式的字重和 `TyValueListEditorKey` 的颜色画，分隔线每行都画，值格画 `EffectiveValue`。所以 `ReadOnly` + 空值 + 有子行能做出「不可编辑、可展开收起、没有值」的行，但和普通的只读对象行（如 `Constraints` 只是值为 `(TSizeConstraints)`）看不出区别：键不能加粗，分隔线去不掉。要区分得在值列表编辑器里加一个只加不改的 protected 钩子（比如按行决定键的字重 / 是否画分隔线，或者行上一个「标题」标志），留给 Task 3 定。**定（Task 3）**：行上的 `Heading` 标志，见 D3 的补记。 |

## 设计

**D1 多选**
- 入口：`procedure SelectObjects(const AObjects: array of TPersistent);`、`function SelectedCount: Integer;`、`property SelectedObjects[AIndex: Integer]: TPersistent`。`SelectedObject := X` 等于只选 X。`SelectedObject` 读回的是第一个。
- 只显示所有对象都有的属性：同名，而且类型相同（`PTypeInfo` 相同；类属性要求子对象的类相同，否则这一行只读、不展开）。
- 值都一样时显示这个值；不一样时值格是空的（文档写明）。布尔、集合元素不一样时也是空的，按空格或选一次就统一成选中的值。
- 改一处，所有对象都写。`OnPropertyChanging` 对每个对象各问一次，任何一个拒绝就一个都不写。`OnPropertyChanged` 每个对象各发一次。某个对象的 setter 抛异常时，前面已经写成的不回滚（和 Object Inspector 一样），行重读，显示实际状态，`OnPropertyError` 报那个对象。
- 集合（`TCollection`）在多选时只显示 `(…)`、只读、不展开：两组项一一对应没有意义。组件引用的下拉以第一个对象的清单根为准，`OnGetComponentNames` 照常可改。
- 任一对象被释放，就从选择里去掉它（`FreeNotification`），剩下的照常显示。
- `SelectedComponent`（发布的那个）只对应单选；多选时读回 nil。

**D2 集合项的增删和排序**
- 集合行与项行有右键菜单：「添加」「删除」「上移」「下移」。另有键盘：在集合行或项行上按 Insert 添加（加在当前项后面，在集合行上就加在末尾），Ctrl+Delete 删除当前项，Ctrl+↑ / Ctrl+↓ 移动当前项。
- 同样的事也有公开方法：`AddCollectionItem(const APath: string): TCollectionItem`、`DeleteCollectionItem(const APath: string)`、`MoveCollectionItem(const APath: string; ADelta: Integer)`，路径和 `ExpandedProperties` 一样用点号。
- 事件：`OnCollectionChanging(Sender; ACollection: TCollection; AAction: TTyCollectionAction; AIndex: Integer; var AAllow: Boolean)`，`AAction` 是 `caAdd` / `caDelete` / `caMove`，拒绝就不动；`OnCollectionChanged` 在做完之后发。
  - **改（执行时，V2）**：两个事件都在 `AIndex` 后面加一个 `ANewIndex: Integer`。`caAdd`：两个都是新项将要（已经）占的下标；`caDelete`：`AIndex` 是被删的项，`ANewIndex` 为 -1；`caMove`：从 `AIndex` 移到 `ANewIndex`。理由：只给一个下标，移动时应用不知道往哪移；而 V2 查出字符串表格的单元格按列下标存，集合层面移列不搬数据，应用要在 `OnCollectionChanging` 里拒绝、改调宿主自己的 `MoveColumn(from, to)`，两个下标缺一不可。
- 删除不弹确认框：集合项删了，宿主多半有撤销或者重新加的办法；需要确认的应用用 `OnCollectionChanging` 自己问。
- 做完之后行重建，展开状态保留，当前行落在新加 / 被移动的那一项上；删了就落在原位置的下一项（没有就上一项，再没有就集合行）。
- 菜单文字走 resourcestring，补 zh_CN。

**D3 属性分类**
- `ShowCategories: Boolean`，默认 False（保持第一期的平铺列表）。开了之后，顶层按分类分组，每组一个不可编辑的标题行，可展开 / 收起，组内仍按 `PropertyOrder` 排。
- 分类从哪来：内置一张小表，按属性名归到几个常见分类——「布局」（`Left`、`Top`、`Width`、`Height`、`Align`、`Anchors`、`AutoSize`、`BorderSpacing`、`Constraints`、`ChildSizing`）、「外观」（`Color`、`Font`、`Caption`、`Text`、`Visible`、`StyleClass`、`StyleOverride`、`Images`、`ImageIndex`、`Cursor`、`ParentColor`、`ParentFont`）、「行为」（`Enabled`、`ReadOnly`、`TabStop`、`TabOrder`、`Hint`、`ShowHint`、`PopupMenu`、`Action`）、「事件」（全部 `tkMethod`）、其余归「其他」。分类名走 resourcestring。
- `OnGetPropertyCategory(Sender; AInstance: TPersistent; const APropName: string; var ACategory: string)` 可以改任何属性的分类（包括自创分类）。分类组的顺序：内置几类按上面的顺序，自创的排在「其他」之前、按名字排。
- 分类只作用于顶层属性；子属性跟着它的父行走。
- 标题行的展开状态也记进 `ExpandedProperties`（用 `@分类名` 的形式，不会和属性名撞）。
  - **补（执行时）**：一个分类第一次出现时是展开的（表格记着见过哪些标题，第一次见就把 `@名字` 加进列表），之后跟着用户和列表走；`@名字` 用的是显示出来的（翻译过的）名字。名字为空算「其他」；分类列表不区分大小写，处理程序给的 `layout` 并进内置的 Layout。多选时按第一个对象问。
  - **补（执行时，V4）**：标题行靠值列表编辑器新加的 `TTyValueRow.Heading`（只加不改，默认 False）：键横跨整行、粗体，没有分隔线和值，`BeginEdit` / `BeginKeyEdit` / `InvokeRowDialog` 一律不开，Enter 展开 / 收起。样式走新子键 `TyValueListEditorGroup`，经 `TyTryRegisterTypeKeyParent` 挂在 `TyValueListEditorRow` 下，只读它**平时**的样子（悬停、选中时照普通行画，选中在每个皮肤下都一致；行状态经 `ItemStatesFor` 覆盖记下）。底色原定 `var(--surface-chrome)`，主题测试查出 adwaita / bootstrap / fluent 的暗色下和列表底色差不到 12（三通道差之和），改成正文色的 8% 透明度 `alpha(var(--on-surface), 0.08)`，深浅主题下都看得出来。

**D4 按名字过滤**
- `FilterText: string`：非空时只显示名字（不区分大小写）包含它的属性；子属性命中时，它的父行跟着显示并自动展开，让命中的那行看得见。清空后恢复原来的展开状态。
- 不在控件里内置搜索框：自绘控件里嵌一个编辑框，牵涉焦点、Tab 顺序、主题，还会让「只要一个表格」的场景多出一块。应用放一个 `TTyEdit`，在 `OnChange` 里设 `FilterText` 就行，示例照这么演示。
- `FilterText` 和 `OnFilterProperty` 同时生效：先问事件，再按文字过滤。
  - **补（执行时）**：`FilterText` 只是 public，不发布（设计期写死一个过滤只会让人找不到属性）。过滤不删行：值列表编辑器新加 `TTyValueRow.Hidden`（只加不改），被滤掉的行连同子行不进显示列表，节点、值、展开状态都还在。匹配看节点名，所以集合元素（`fsBold`）、集合项里的属性也算；一行自己匹配时它下面的行都保留（不自动展开）。开始过滤时把 `ExpandedProperties` 存一份，清空时原样放回，过滤期间手动的展开 / 收起不保留。全是空格算没过滤。

**D6 可扩展性不丢**（2026-10-13 用户追加，约束全部任务）：内置只管常见情况，没内置的，应用自己能加上——经事件、虚方法、公开方法，永远不必改控件。
- (a) **不显示的类型**（接口、变体、记录、超过 32 个元素的集合，以及应用想换个方式处理的类，比如把 `TPicture` 当文件名）：加 `OnGetPropertyText(Sender; AInstance: TPersistent; APropInfo: PPropInfo; var AText: string; var AHandled: Boolean)` 和 `OnSetPropertyText(Sender; AInstance: TPersistent; APropInfo: PPropInfo; const AText: string; var AHandled: Boolean)`。`OnFilterProperty` 对**每个** published 属性都问（`TypeFilter`、`HiddenProperties` 先滤，不支持的种类 `AShow` 进来是 False）；不支持的属性在 `AShow := True` 且 `OnGetPropertyText` 处理了（`AHandled`）时列出，没挂 `OnSetPropertyText` 就只读。支持的类型，这两个事件处理了就跳过内置的转换。加上已有的 `OnGetPropertyRow`（编辑器种类、选项）和 `OnEditProperty`（对话框），应用能完整支持一种我们不认识的类型。多选时按对象各发一次。（整数子界的集合第一期已支持，不在此列。）
- (b) **集合操作**：内置右键菜单只在表格的 `PopupMenu` 没设时出现；应用自己的菜单用公开的 `AddCollectionItem` / `DeleteCollectionItem` / `MoveCollectionItem` 加 `PropertyAt` 做同样的事（执行时补：`PropertyAt` 对集合项的行答 False、也不给路径，所以另加公开的 `SelectedRow`（当前行）和 `RowPath(ARow)`（行的点号路径，格式同 `ExpandedProperties`），应用的菜单才拿得到路径）。`OnCreateCollectionItem(Sender; ACollection: TCollection; var AItem: TCollectionItem)` 让应用自己建项（特定的项类、初值）；留 nil 就用内置的 `Add`。
- (c) **留给 Task 3**：分类有 `OnGetPropertyCategory`，过滤有 `OnFilterProperty` + `FilterText`。另把「建一行」做成 protected virtual（如 `CreatePropertyRow`），子类能整个接管某种类型的行。
  - **改（执行时）**：叫 `BuildPropertyRow(ANode)`，不叫 Create——行由映射建好、挂好节点（键是属性名、`Data` 指向节点），虚方法负责填它和建它下面的行，默认是 `PropertyRows.FillRow` + `PropertyRows.AddChildren`（两者改成 public）。只有这一个不够：接管了的行，值的读写还走表格自己的转换（`Refresh` 会把子类填的值盖掉，写也写不进去），所以另加 `GetPropertyText` / `SetPropertyText` 两个 protected virtual，默认就是去问 `OnGetPropertyText` / `OnSetPropertyText`。映射一侧是 `TTyPropertyRows` 的三个 protected virtual（`BuildRow`、`GetPropText`、`SetPropText`），表格内部用一个子类 `TTyGridPropertyRows` 把它们转给表格的虚方法。`OnGetPropertyRow` 现在在行**连同子行**建好之后才调（原来在子行之前）。节点加了 `FChildrenBuilt`：子类没建子行的对象节点，`Refresh` 不再拿它比结构（否则每次 `Refresh` 都重建）。

**D5 与第一期的关系**：第一期的发布属性、事件、默认行为一律不变；新属性的默认值让行为和第一期一样（`ShowCategories = False`、`FilterText = ''`、单选）。

## 任务

### Task 1：多选（D1）
- 测试走真实路径：三个 `TTyButton`，选中后只出现共同属性；`Caption` 不同时值格为空，改了之后三个都变；`OnPropertyChanging` 拒绝其中一个时三个都不变；某个 setter 抛异常时，前面的保持已写、行显示实际值、`OnPropertyError` 报那个对象；释放其中一个后剩下两个照常；布尔不一致时按空格统一；`Font` 子属性改了三个都改；集合在多选时只读不展开。
- 变异必须变红：拒绝只拦下被拒的那个；值不一致时显示第一个的值；类型不同的同名属性也显示出来；释放后还留在选择里（投毒验证）。

### Task 2：集合项的增删和排序（D2）
- 测试：右键菜单的四项、四个快捷键、三个公开方法；`OnCollectionChanging` 拒绝；做完后当前行的位置；展开状态保留；对 `TTyStringGrid.Columns` 实际生效（列数、顺序变了，表格跟着变）。
- 变异必须变红：Ctrl+↑ 在第一项上越界；删除后当前行落在已经不存在的项上；拒绝了仍然执行；菜单项绕过事件。

### Task 3：分类与过滤（D3、D4）
- 测试：开分类后的分组和顺序、标题行不可编辑、收起展开、`OnGetPropertyCategory` 改分类和自创分类、子属性不参与分类、标题行的展开状态往返；`FilterText` 命中子属性时父行自动展开、清空后恢复、和 `OnFilterProperty` 叠加、不区分大小写。
- 变异必须变红：自创分类排到「其他」之后；过滤时父行不展开；清空过滤后展开状态没恢复；标题行可以编辑。

### Task 4：示例、文档
- `examples/propertygrid`：左边控件支持 Ctrl+点击多选（标题上显示选了几个）；顶部的过滤框改成设 `FilterText`（`OnFilterProperty` 的演示改成另一个开关，比如「只看可写的属性」，让两个都有示例）；加一个「分类」开关；左边的表格演示集合项的增删。`.lfm` 与 `.po` 照规矩。
- `docs/controls/propertygrid.md`：补多选、集合项增删、分类、过滤四节，和 LCL `TTIPropertyGrid` 的区别表更新；第二期完成，「以后再说」一节只留确实没做的东西。

### Task 5：编译、全量、变异、Lazarus 3.0、冒烟、签收【主控执行为主】


## 实现记录（Task 3–4，按实际做成的样子）

Task 3（`dd286a3e`）、Task 4（`27091a25`）。D3、D4、D6 (c)、V4 的改动和补充记在原处，这里只记上面没写的：

- **值列表编辑器只加不改**：`TTyValueRow` 加 `Heading`、`Hidden` 两个字段（默认 False），`ItemStatesFor` 覆盖只记下行状态、原样返回；`initialization` 挂 `TyValueListEditorGroup → TyValueListEditorRow`。`themes/light.tycss` 加一条规则，`gen-defaulttheme.ps1`、`gen-tycss-catalog.ps1` 重跑（改之前先空跑一遍确认能原样生成），生成的两处差异逐行看过：只多出那条规则和它的注释、目录里多一个键。`tools/themebuilder/tbcoverage.pas` 的值列表编辑器那一行加上新键。没有改任何皮肤文件：新键没有皮肤定义，经基础层在每个主题下都有。
- **分类的名字**是 resourcestring（`rsTyPropGridCatLayout` 等五个，补了 zh_CN），另有公开函数 `TyPropertyGridCategoryOf(名字, 种类)` 返回内置归类。`.pot`、zh_CN `.po` 补条目，`.po` 原样拷到主题编辑器和示例的 `languages/`。
- **集合操作与分类**：增删、移动后要展开的祖先，从按节点的父链改成按行的父链，这样分类标题也会打开。
- **示例**：左边 Ctrl+点击（`ssModifier`，Mac 上是 Cmd）多选，标题栏写选了几个；过滤框设 `FilterText`；「只看可写的」开关演示 `OnFilterProperty`（没有 setter 的去掉，类属性留着）；「分类」开关；检查字符串表格时，它的列经 `OnCollectionChanging` 拒绝后改调表格自己的 `InsertColumn` / `DeleteColumn` / `MoveColumn`，单元格跟着列走（V2 的做法），处理程序里调 `Refresh`。`MoveColumn` 改的是显示位置，所以属性表格里列的下标顺序不变，文档写明。示例的 `languages/tycontrols.zh_CN.po` 第一期之后没跟上 Task 2 的四条菜单文字，这次一起补齐（与库目录那份逐字节相同）。
- **文档**：`docs/controls/propertygrid.md` 加了多选、文字事件、派生类、集合项、分类、过滤六节，一张「没内置的 → 应用怎么加」表，LCL 对照表更新，「以后再说」只剩两条（多选时的集合、布尔复选框）。`valuelisteditor.md` 和 `tycss-reference`（中英）补了 `Heading` / `Hidden` 和新键；两个 README 的示例说明跟着改。

## 签收（执行时填）

### 测试部分（Task 3–4 实现 agent，2026-10-13）

提交：Task 3 `dd286a3e`，Task 4 `27091a25`。

**本计划的 suite**（均全绿）：新 suite `TPropertyGridCategoriesTest` 9、`TPropertyGridFilterTest` 7、`TPropertyGridBuildRowTest` 1、`TValueListHeadingTest` 2（其中一条把 17 个内置主题 × 亮 / 暗逐个画出来：标题行在文字以外的像素与普通行的底色差 ≥ 12，标题行上没有分隔线，普通行有，点标题行不开编辑器）。已有的：`TPropertyGridMultiTest` 15、`TPropertyGridTextEventsTest` 6、`TPropertyGridCollectionsTest` 18、`TPropertyGridControlTest` 26、`TPropertyGridEditTest` 18、`TPropertyGridObjectsTest` 13、`TPropertyGridButtonTest` 11、`TPropertyRowsTest` 12、`TPropertyGridTypeKeyTest` 4、`TValueListEditorTest` 21、`TValueListCommitHookTest` 14、`TValueListKeyOptionsTest` 23、`TValueListParityTest` 8、`TValueListRowApiTest` 3、`TValueListViewportMetricTest` 5。守卫：`TTyCustomClassesGuardTest` 11（mimic 加了 `ShowCategories`、`OnGetPropertyCategory`）、`TTyCustomClassesP1–P4Test`、`TCssCatalogTest` 14、`TBuiltinThemeTest`、`TBuiltinThemesTest`、`TBuiltinSkinsSyncTest`、`TBuiltinSyncTest`、`TTestThemes` 19、`TTestThemeGolden` 8、`TModeCoherenceTest` 7、`TTypeKeyChainTest` 31、`TTbCoverageTests` 10、`TTbPickTests` 11、`TTbMainFormTests` 84、`TI18NTest` 9、`TTranslatableTest`、`TEnglishFitTest`、`TExampleLfmTest`、`TSkinFitTest`、`TDanglingRefsTest`、`TTyFocusTabStopTest`、`TTyClickFocusTest`。`scripts/check-lfm-props.py`、`scripts/check-example-po.py` 无问题。

**变异**（每条：改 → 重编 → 跑四个新 suite → 确认红 → 还原 → 校验哈希；最后一条还原后重编；13 条全红、全部还原、哈希一致）：

| # | 变异 | 变红的测试 |
|---|---|---|
| M1 | 自创分类排到「其他」之后 | `TestOnGetPropertyCategoryMovesAndInvents` |
| M2 | 过滤时父行不展开（`ApplyExpanded` 不看 `FFilterOpen`） | 过滤 3 条（子属性命中、清空恢复、带分类） |
| M3 | 清空过滤后不放回原来的展开状态 | `TestClearingPutsTheExpansionBack`、`TestWithCategoriesOnlyTheHeadingsWithAMatch` |
| M4 | 标题行可以编辑（`BeginEdit` 不看 `Heading`） | `TestAHeadingIsNeverEdited`、标题行 2 条 |
| M5 | 映射绕过 `BuildRow`，直接 `FillRow` + `AddChildren` | `TestADescendantTakesOverATypesRow` |
| M6 | 标题行不画底色 | 主题 × 亮暗那条 |
| M7 | 标题行照画分隔线和值 | 主题 × 亮暗那条 |
| M8 | 过滤区分大小写 | 过滤 6 条 |
| M9 | `AppendFlat` 不管 `Hidden` | 过滤 5 条、`TestAHeadingIsNotEditedOnAPlainEditor` |
| M10 | 第一次出现的分类不展开（不加进列表） | 分类 3 条、过滤 1 条、主题那条 |
| M11 | 子属性也分类（去掉「只在顶层」） | 分类 7 条、过滤 1 条 |
| M12 | 标题行上 Enter 不展开 / 收起 | `TestAHeadingIsNeverEdited`、`TestAHeadingIsNotEditedOnAPlainEditor` |
| M13 | `Refresh` 不看 `FChildrenBuilt`（子类没建子行也拿来比结构） | `TestADescendantTakesOverATypesRow`（行被重建） |

**全量**（`27091a25`，报告时间 12 分 50 秒，墙钟 47 分 51 秒）：N 11597，E 0，F 0，I 1。I：`TSelectPathOptionsTest.TestNoReadOnlyReturn`（本机条件，原有）。已知偶发的那几个这次都没出。

**留给主控**：编 `.lpk` / dt 包和 `examples/propertygrid`（没编过：示例用到 `ssModifier`、`GetKeyShiftState`，Lazarus 3.0 的 controls.pp 里都有）；Lazarus 3.0 构建；GUI 冒烟（分类标题行在几个皮肤下的样子、过滤框、Ctrl+点击多选、给字符串表格增删 / 移动列）。面板没有新类，不用生成图标。
