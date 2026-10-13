# 属性表格（PropertyGrid）第一期 实现计划（#65）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or subagent-driven-development) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（项目约定）**：测试先行；每个任务改代码、写测试并单独提交；任务之间只编 `tests/tytests.lpi`、跑本任务的 suite，最后一个任务跑一次全量、集中做变异、签收。中途不汇报，也不问要不要提交。测试写成「判据 + 必须变红的变异」。
>
> **谁来做**：标 **【主控执行】** 的步骤，实现 agent 不做：编 `.lpk`、编 `examples/`、生成面板图标、Lazarus 3.0 构建、GUI 冒烟、推送。
>
> **不改的文件**：`Painter.pas`、`StyleModel.pas`、`TextMenu.pas`、`Base.pas`、`Component.pas`、`Css.Parser.pas`、`AdvanceChart.pas` 及 `AdvChart.*`、`CHANGELOG*`。

**Goal:** 设 `SelectedObject := Button1`，表格就列出这个对象的 published 属性，按属性类型配编辑器，改完直接写回对象。

**Architecture:** 建在 `TTyCustomValueListEditor` 上：`TTyCustomPropertyGrid = class(TTyCustomValueListEditor)`，`TTyPropertyGrid` 只负责发布。对象 → 行的映射放在一个独立的类 `TTyPropertyRows`（新单元 `tyControls.PropertyGrid.pas`），只用 RTL 的 `TypInfo`，不依赖 IDEIntf 的 `PropEdits`。所以留在主包 `tycontrols.lpk`，不带来新依赖。ValueListEditor 只加两样东西：`TTyValueRow.Data` 指针，以及一个提交前的 protected virtual 钩子。

**工作树：** `D:/Projects/ty-controls/.claude/worktrees/property-grid`，分支 `feat/property-grid`，从 main `e2313a7c` 拉出。

---

## 核实记录（执行前补）

| # | 待核的事实 | 影响 | 核实结果（2026-10-12，实现 agent 读源码） |
|---|---|---|---|
| V1 | ValueListEditor 的编辑器是否都已接线：文本、整数、浮点、布尔、枚举、颜色、字体、对话框、只读。开头那段注释说只做了文本和只读，已过时。2026-10-12 主控粗看是全接了。 | 映射直接用，顺手改掉过时注释 | **全接了。** `BeginEdit` 按种类分派：文本/整数/浮点走行内编辑器（数字模式只收数字、开头的 `-`、浮点再收一个 `.`）；布尔/枚举走下拉；颜色走色板下拉，末行「更多…」异步弹 `TySelectColor`；字体/对话框行内只读，「…」打开内置字体对话框或 `OnEditRow`；只读行、Style 复合行拒绝编辑。另外两点：控件**不处理空格键**（单选时列表不吃 Space），「空格切换布尔」要属性表格自己做；字体对话框和取色器在 `EditFontRow` / `DeferredColorDialog` 里直接创建，测试没有替身的缝，只能弹真模态框。顺带看到「更多…」「选择颜色」两处写死的中文，不是 resourcestring（未改，不在本计划范围）。 |
| V2 | 提交路径：`CommitEditorRow`（私有）→ `Value` → `OnValueChanged` → `PropagateUp`；字体行的子行（name/size/Bold…）各自也会触发 `OnValueChanged` | 写回挂在哪、字体整体写回还是逐项写回 | 经过 `CommitEditorRow` 的：行内（`EndEdit`→`CommitEditor`）、下拉（`HandleDropCommit`→`CommitEditor`）、颜色「更多…」（`DeferredColorDialog`）、没有子行的字体行、`SetRowValue`。**绕开它的**：有子行的字体对话框（`SyncFontChildren` 直接改各子行 `Value`、逐个发 `OnValueChanged`，再 `RecomputeComposite`）；`Values[]` / `ValueFromIndex[]`（`SetValueFromIndex` 直接改）；`OnEditRow` 处理程序自己改 `ARow.Value`，控件看不见。`PropagateUp` / `RecomputeComposite` 只改派生值，不算提交。→ 钩子放进 `CommitEditorRow`、`SetValueFromIndex`，有子行的字体对话框在字体行上整体问一次（对话框选中的字体经 protected `CommitFont` 给子类，整体写回）。 |
| V3 | `TypInfo` 在 FPC 3.2 上的读写：`GetPropList`、`GetOrdProp`、`SetOrdProp`、`GetFloatProp`、`SetStrProp`、`GetEnumName`、`SetToString`、`StringToSet`、`GetObjectProp`、`tkSet` / `tkClass` / `tkMethod` / `tkInterface`；Lazarus 3.0 下同样可用 | 只用 3.0 就有的接口 | 两套安装（`C:\lazarus`、`D:\lazarus30`）都是 FPC 3.2.2，`typinfo.pp` 逐字节相同，列出的函数都在。要注意的：`GetPropList` 自带的排序是区分大小写的 ShortString 比较，按名排序自己做（`CompareText`）；不排序时是 NameIndex 顺序（祖先在前，重新发布的属性留在首次发布的位置），这就是「声明顺序」；`GetOrdProp` / `SetToString` 只处理不超过 4 字节的集合，超过 32 个元素的集合会被截断，所以不显示；集合的元素类型可能是整数子界，不能用 `GetEnumName`；`TDateTime` / `TDate` / `TTime` 是三个 `type Double`，各有自己的 `PTypeInfo`。 |
| V4 | `TColor` 的识别：属性的 `PTypeInfo` 名为 `TColor` / `TGraphicsColor`；`ColorToString` / `IdentToColor` | 颜色行 | `TColor = TGraphicsColor`（graphics.pp:59）是别名，FPC 3.2.2 下 RTTI 名字是 **`TGraphicsColor`**；FPC ≥ 3.2.3 时 graphtype 改用 `System.UITypes.TColor`，名字变成 `TColor`。识别先比 `PropType = TypeInfo(TGraphicsColor)`，再按两个名字兜底。`ColorToString` / `StringToColorDef` / `IdentToColor` 都在 Graphics，3.0 同样有。 |
| V5 | LCL `RTTIGrids.TTIPropertyGrid` 的公开接口名（`TIObject`、`Filter`、`ExpandedProperties`…） | 只借名字和习惯，代码自己写 | `TTIPropertyGrid` → `TTICustomPropertyGrid` → `TCustomPropertiesGrid`（objectinspector.pp）。检查对象叫 `TIObject: TPersistent`（public，在 `TTIPropertyGrid` 里发布，靠专门的属性编辑器给下拉）；`Filter: TTypeKinds`（`TTIPropertyGrid` 用 `AllTypeKinds`，事件也显示；IDE 的对象查看器用 `DefaultOITypeKinds`）；`ExpandedProperties: TStringList`，记点号路径（`PropertyPath`：`Font.Style`）；另有 `OnModified`、`OnEditorFilter`、`CheckboxForBoolean`、`SplitterX`。我们沿用点号路径；过滤属性按 D2 叫 `TypeFilter`。 |

## 设计

**D1 控件**：`TTyCustomPropertyGrid` / `TTyPropertyGrid`。
- 两个入口，背后是同一个字段。`SelectedObject: TPersistent` 是 public，运行时可以检查任何 `TPersistent`。`SelectedComponent: TComponent` 发布出去，对象查看器里就是一个组件下拉，窗体一载入就显示那个组件：设置面板直接绑一个组件，一行代码都不用写。读 `SelectedComponent` 时，当前对象是组件就返回它，否则返回 nil。不只发布一个 `TPersistent` 类型的属性，是因为对象查看器对这种属性给的是「展开子属性」，没有组件下拉。
- 被检查的组件释放时，经 `FreeNotification` 自动清空。
- 设计期照样列出行，方便看效果，但不能编辑：设计器拦了鼠标，而且绕过设计器去改被设计的组件，设计器不会知道。
- 作为属性表格，ValueListEditor 里针对「名字/值列表」的东西不发布：`KeyOptions`（固定为 []，属性名不能改、行不能增删）、`Items`、`Sorted`、`MultiSelect`、`ExtendedSelect`、`OnKeyChanged`、`OnKeyRejected`。行由表格自己管，文档写明：别用 `AddRow` / `DeleteRow` 去动它们。

**D2 行的生成**：
- 列出 published 属性。默认按名字排序（同 Object Inspector），`PropertyOrder = poDeclared` 时按声明顺序。
- 每行 `Key` 是属性名，`Data` 指向内部的属性节点：实例、`PPropInfo`、所属的父节点。
- `TypeFilter: TTypeKinds` 的默认值是除 `tkMethod` 外的全部种类，事件默认不显示。另有 `HiddenProperties: TStrings`，以及 `OnFilterProperty(Sender; AInstance: TPersistent; const APropName: string; var AShow: Boolean)`。

**D3 类型 → 编辑器**：

| 属性类型 | 行 |
|---|---|
| 整数、Int64、QWord、字符 | `vekInteger`（字符用 `vekText`，限一个字符） |
| 浮点 | `vekFloat`，显示与解析都固定用 `.` 作小数点（编辑器的数字模式只收 `.`；照本机格式的话，德语系统上会是 `,`，两边就对不上了）；`TDateTime` / `TDate` / `TTime` 显示成本机格式的日期文字，按文本编辑、按本机格式解析 |
| 字符串（含 `TCaption`、`TTranslateString`） | `vekText` |
| 布尔 | `vekBoolean` |
| 枚举 | `vekEnum`，选项取 `GetEnumName` 的全部名字 |
| 集合 | 显示 `[a,b]`；子行是每个元素一个 `vekBoolean`；改子行会重算父行并写回 |
| `TColor` | `vekColor` |
| `TFont` | `vekFont`：沿用编辑器现成的字体行和子行，写回时把整个字体 `Assign` 回去 |
| 其他 `TPersistent` 类属性（`Constraints`、`BorderSpacing` 这类子对象），以及带 `csSubComponent` 的子组件 | 显示 `(TClassName)`，只读；子行是它的 published 属性，递归往下，有深度上限防止循环引用 |
| 组件引用（其余 `TComponent` 子类，如 `PopupMenu`、`Images`、`Controller`） | `vekEnum`：选项是 `(none)` 加上被检查组件的 `Owner` 名下（**已由 D11(a) 改：被检查的是窗体 / 数据模块 / 框架时取它自己名下，候选根本身也列入**）、类型兼容的组件名；当前值不在其中时也列上。`OnGetComponentNames(Sender; AInstance; APropInfo; AList: TStrings)` 可以改这份清单（比如跨窗体）。被检查的对象没有 `Owner` 时只有 `(none)` 和当前值 |
| `TStrings` | `vekDialog`：经 `OnEditRow` 的默认处理弹一个多行文本对话框（用本库的对话框，测试可替换） |
| `TCollection` | 显示 `(N items)`；子行是每一项（`[0] 项的 DisplayName`），每一项再展开成它的 published 属性，可以直接改。增删项、调整顺序放第二期 |
| 事件（`tkMethod`） | 默认不显示；`TypeFilter` 里加上 `tkMethod` 时显示处理程序名，只读 |
| 接口、变体、记录、其他 | 不显示 |

只读属性（没有 setter）一律 `ReadOnly`；类属性没有 setter 也照样展开子行，因为子对象自己的属性可写。

**D4 写回**：在提交前的钩子里写对象。写之前先过 `OnPropertyChanging(Sender; AInstance; const APropName, ANewValue: string; var AAllow: Boolean)`，写成功后触发 `OnPropertyChanged(Sender; AInstance; const APropName: string)`。setter 抛异常时，行保持旧值，并触发 `OnPropertyError(Sender; AInstance; const APropName: string; E: Exception)`。没挂这个事件时按 LCL 惯例重新抛出，交给 `Application.HandleException`。写回后，同一对象上其他行的显示值要重新读：一个属性的 setter 常会改到别的属性，比如 `AutoSize` 改 `Width`。

**D5 刷新**：`Refresh` 重新读所有行的值，不重建行、不丢展开状态和当前行。`SelectedObject` 换成别的对象时整体重建，同类对象之间切换保留展开的路径（`ExpandedProperties` 按属性路径记录）。对象被释放：组件会经 `FreeNotification` 自动清空；非组件的 `TPersistent` 由调用者负责在释放前清空，文档写明。

**D6 扩展点**（用户原则：内置只做常用行为，其余走事件和公开几何）：
- `OnFilterProperty`、`OnPropertyChanging` / `OnPropertyChanged` / `OnPropertyError`。
- `OnGetPropertyRow(Sender; AInstance; APropInfo: PPropInfo; ARow: TTyValueRow)`：行建好之后调用，应用可以改编辑器种类、枚举选项、显示文字、样式，或者把行设成只读。
- 公开 `PropertyAt(ARow: TTyValueRow; out AInstance: TPersistent; out APropName: string): Boolean`：应用的 `OnEditRow` 能据此给某种属性接上自己的对话框。（**已由 D11(b) 改：对话框行走 `OnEditProperty`，`OnEditRow` 不发布。**）

**D7 第二期（本计划不做，写进 #65）**：同时选中多个对象（只显示共同属性，改一处写回全部）、集合项的增删和排序、属性分类与分组、搜索过滤框。

**D10 界面文字**：`(none)`、`(N items)`、`TStrings` 对话框的标题和按钮走 resourcestring，`languages/` 里补 zh_CN。

**D8 主题**：typeKey `TyPropertyGrid` → `TyValueListEditor`，经 #14 的链回退，不加新令牌。

**D9 定案**（2026-10-12 用户让主控「再仔细想想，然后根据你的意见来做」，复核后定为）：
1. **新控件，不做非可视适配器。** 适配器能让现成的 ValueListEditor 也能检查对象，但同一个编辑器里手建的行和 RTTI 行混在一起，谁管哪行说不清；LCL 也是单独一个 `TTIPropertyGrid`。映射类独立，真要适配器以后能复用。补充：ValueListEditor 针对「名字/值列表」的属性不发布（见 D1）。
2. **`SelectedObject`（public）+ `SelectedComponent`（发布），共用一个字段。** 设计期只显示、不编辑（见 D1）。
3. **默认按名字排序，事件默认隐藏。** 运行时没有代码可挂，事件显示了也只能看。
4. **组件引用用下拉，默认清单是 `Owner` 名下的组件，再加一个 `OnGetComponentNames` 事件。** 原方案只有同一 `Owner`，运行时用 `Owner = nil` 建的组件就什么都选不了，跨窗体也没办法；按用户原则，常用的内置，其余给事件。
5. **改：集合（`TCollection`）在第一期就能展开、改每一项的属性。** 原方案第一期只显示 `(N items)`，但表格的列、状态栏的面板都是集合，看得见改不了太弱；展开复用类属性那套递归，代价很小。增删和排序才放第二期。多选仍放第二期：它要的是另一套数据模型（多个对象求共同属性）。

复核时另外补上的：带 `csSubComponent` 的子组件按类属性展开，而不是当成引用；浮点固定用 `.`；界面文字走 resourcestring（D10）。

**D11 定案**（2026-10-12，主控复核 Task 1–3 的报告后定，约束 Task 4–5）：
- (a) **组件引用的候选根**：被检查的组件是 `TCustomForm`、`TDataModule` 或 `TCustomFrame` 时，候选根是它自己，不是它的 `Owner`（检查一个窗体，`ActiveControl` 要能从窗体上的控件里选）；其他组件的候选根是 `Owner`。候选根本身类型兼容时也列入。`OnGetComponentNames` 仍有最后决定权。
- (b) **对话框行带「已处理」标志**：发布 `OnEditProperty(Sender; ARow: TTyValueRow; AInstance: TPersistent; const APropName: string; var AHandled: Boolean)`，任何对话框行先触发它；没处理就走内置默认（`TStrings` 对话框，其他行什么都不做）。`TTyPropertyGrid` 不发布继承来的 `OnEditRow`。D6 的 `OnGetPropertyRow`、`PropertyAt` 照原计划。
- (c) **文档要写明**：控件可能自己维护某些属性（如 `TTyButton` 把 `Constraints.MinWidth` 维持在内容宽度），写进去的值可能被控件改掉；`Refresh` 显示的是真实值。

## 任务

### Task 1：ValueListEditor 的两个钩子（只加不改）
- `TTyValueRow.Data: Pointer`（默认 nil，不拥有）。
- `protected function CanCommitValue(ARow: TTyValueRow; const AText: string): Boolean; virtual;`：在 `CommitEditorRow` 里、改 `Value` 之前调用，返回 False 就不改，`OnValueChanged` 也不发。字体对话框、颜色下拉和行内编辑三条路都要经过它。
- 顺手改掉开头那段过时的「Layer 1」注释。
- 测试：钩子拒绝时三条路的值都不变、事件不发；默认行为不变（现有 ValueListEditor 的两个 suite 原样通过）。
- 变异：某一条路绕过钩子 → 红。

### Task 2：`TTyPropertyRows` 与基本类型
- 新单元 `tyControls.PropertyGrid.pas`：节点树、属性列举、排序、过滤（`TypeFilter`、`HiddenProperties`、`OnFilterProperty`）。
- 整数、浮点、字符串、字符、布尔、枚举、`TColor` 的读、显示、写回；只读属性。
- 测试夹具：一个自写的 `TPersistent` 子类，覆盖每种类型，并带一个 setter 会改动另一属性的属性、一个 setter 会抛异常的属性。
- 变异：枚举选项缺了一个；颜色按整数显示；只读属性可编辑；排序关掉。

### Task 3：集合、类属性、字体、组件引用、`TStrings`
- 集合子行和父行重算；类属性和子组件递归展开、深度上限；`TCollection` 展开到每一项及其属性；`TFont` 整体 `Assign`；组件引用下拉与 `OnGetComponentNames`；`TStrings` 对话框（经 protected virtual 弹出，测试替换）。
- 测试用真实控件：一个 `TTyButton`，看 `Font`、`Constraints`、`Anchors`（集合）、`PopupMenu`（组件引用）。
- 变异：集合子行改了不写回；循环引用不设深度上限（测试里构造一个互相引用的夹具）；组件下拉列出不同 `Owner` 的组件；`OnGetComponentNames` 改的清单没用上；字体只改了名字没改大小；集合项的属性改了没写到那一项；子组件被当成引用。

### Task 4：控件、写回事件、刷新
- `TTyCustomPropertyGrid` / `TTyPropertyGrid`：`SelectedObject`、`SelectedComponent`、`Refresh`、`ExpandedProperties`、`PropertyOrder`、D4 与 D6 的事件、`PropertyAt`。
- 测试走真实路径：点值格、打字、按 Enter，下拉选项，空格切换布尔，F2。写回之后对象上的值、其他行的刷新、setter 异常时保持旧值并触发 `OnPropertyError`、`OnPropertyChanging` 拒绝、对象被释放后清空、换对象时保留展开路径。
- 拆分登记（`CSplit` / `CChain`）、G10 夹具、focus.tabstop 等守卫。
- 变异：写回后其他行不刷新；异常后行显示新值；`Notification` 不清空（用投毒验证释放后不再访问，见 use-after-free 那条记忆）。

### Task 5：主题、注册、示例、文档
- typeKey 链；17 主题 × 亮 / 暗下解析结果与 `TyValueListEditor` 相同。
- 面板注册：`'TyControls'` 页，排在 `TTyValueListEditor` 后面；图标【主控执行】。
- 示例 `examples/propertygrid`：`.lfm`、真标题栏、运行时换肤。左边是几个控件（按钮、编辑框、复选框、进度条、面板），点哪个右边就检查哪个；顶部有「显示事件」开关和一个过滤输入框（用 `OnFilterProperty` 实现，示例里演示怎么用这个事件）。字符串进示例的 `.po`。
- 文档 `docs/controls/propertygrid.md`：用法、类型映射表、扩展点、和 LCL `TTIPropertyGrid` 的区别、第二期的内容；README 控件表和总数。

### Task 6：编译、全量、变异、Lazarus 3.0、冒烟、签收【主控执行为主】

## 实现记录（Task 4–5，按实际做成的样子）

Task 4（`677944c4`）、Task 5（`32406302`）。和上文不同或上文没写的：

- **排序枚举改名**：`TTyPropertyOrder = (poAlphabetical, poDeclared)`（Task 2 时叫 `poByName`，主控 Task 4 指令用 `poAlphabetical`）。`TyPropertyGridDefaultTypeFilter` 改成无类型常量，才能当发布属性 `TypeFilter` 的 `default`。
- **发布面**：`TTyPropertyGrid` 发布的是值列表编辑器的那份清单，去掉 `KeyOptions`、`Items`、`ItemIndex`、`TopIndex`、`Sorted`、`MultiSelect`、`ExtendedSelect`、`ScrollWidth`、`Action`、`AutoSize`、`ChildSizing`、`OnKeyChanged`、`OnKeyRejected`、`OnEditRow`、`OnValueChanged`；加上 `SelectedComponent`、`PropertyOrder`、`TypeFilter`、`HiddenProperties`、`ExpandedProperties`（也发布：设计期可以预先展开 `Font`）和七个事件。`KeyOptions` 在自定义类里重声明成只读、恒为 `[]`。
- **`OnEditRow`**：自定义类里重声明为 public（字段是表格自己的），防止应用改掉继承来的 `OnEditRow` 让表格失灵；`OnEditProperty` 没处理时它先被问，赋了值就当已处理。只是 public，不发布（D11(b)）。
- **写回事件的对象和名字**：`AInstance` 是真正拥有这个属性的对象。集合元素一行报整个集合（`ANewValue` 是写入后的 `[a,b]`）；字体子行报在那个 `TFont` 上（`Size`），字体对话框整体换报在宿主上（`Font`）。`OnPropertyChanged` 写完后重新解析对象，不用写之前拿到的指针。处理程序里重建了行（`FBuildCount` 变了）就不再碰调用方的行。
- **出错**：没挂 `OnPropertyError` 时异常照常抛出（经事件链到 `Application.HandleException`）；挂了就交给它、到此为止。两种情况都先把所有行按对象重读一遍。顺带修了值列表编辑器：下拉列表里选的值提交时抛异常，列表以前不关，现在 `try/finally` 关掉（`HandleDropCommit`）。
- **`Refresh`**：值重读；对象的结构变了（集合项数变了、子对象出现 / 消失 / 换了类）才自动重建。`Rebuild` 和换对象都按路径保留当前行；`Rebuild` / `Refresh` 保留滚动位置，换对象从顶部开始。
- **`ExpandedProperties`**：懒同步。有人读它、或者重建之前，从行上收（展开的加、收起的删，当前对象没有的路径留着）；重建之后、或者列表本身被改时，写回行上。
- **载入**：`csLoading` 时设 `SelectedComponent` 只记下来，`Loaded` 里统一建行（实测 fixup 在 `Loaded` 之前，变异 M12 证明 `Loaded` 是必需的）。
- **设计期**：`WriteProperty`、`KeyDown` 的空格、对话框行都不写；行照样列出。
- **守卫**：Task 4 时重新引入 `CNotYetOnThePalette`（Task 5 删掉）；`test.danglingrefs` 把 `BeginPoison` / `EndPoison` 导出到 interface，供释放后不读取的测试用；点击聚焦探针（`ClickProbeControls`）也加了属性表格。
- **主题**：`GetStyleTypeKey = 'TyPropertyGrid'`，`initialization` 里 `TyTryRegisterTypeKeyParent('TyPropertyGrid', 'TyValueListEditor')`，`finalization` 注销；行和各部件仍用值列表编辑器的键。没改任何主题文件。
- **示例**：`examples/propertygrid`，`.lfm` 里直接设 `SelectedComponent = Button1`、`ExpandedProperties = ('Font')`；字符串表格的列在 `Header.Columns` 里，演示集合就地编辑。`languages/` 里的 `tycontrols.zh_CN.po` 是库目录那份的拷贝（含本计划新增的 `rsTyPropGrid*`）。

## 签收（执行时填）

### 测试部分（Task 4–5 实现 agent，2026-10-12）

提交：Task 4 `677944c4`，Task 5 `32406302`，另有 `5b80eaef`（全量查出：主题编辑器带的库目录副本 `tools/themebuilder/languages/tycontrols.zh_CN.po` 没跟上 Task 2/3 加的 `rsTyPropGrid*`，照抄一份）。

**本计划的 suite**（均为全绿）：`TPropertyRowsTest` 12、`TPropertyGridEditTest` 18、`TPropertyGridObjectsTest` 13、`TPropertyGridButtonTest` 11、`TPropertyGridControlTest` 26（新）、`TPropertyGridTypeKeyTest` 4（新）、`TValueListCommitHookTest` 14、`TValueListEditorTest` 21。守卫：`TTyCustomClassesGuardTest` 11（G9 / G10 含新类，G10 只多出 `TTyPropertyGrid` 一节，与值列表编辑器的相同）、`TVersionTest` 6、`TTyFocusTabStopTest` 8、`TTyClickFocusTest` 8（探针名单加了属性表格）、`TDanglingRefsTest` 6、`TComponentLeakTest`、`TFreeWhileOwnerLivesTest`、`TWheelEventTest`、`TDesignEditorsTest`、`TTranslatableTest`、`TTyMeasureFontDpiTest`、`TI18NTest`、`TReleaseManifestTest`、`TDBTypeKeysTest`。`scripts/check-lfm-props.py`、`scripts/check-example-po.py` 无问题。

**变异**（每条：改 → 重编 → 跑 → 确认红 → 还原 → 校验哈希 → 重编；16 条全红、全部还原、哈希一致）：

| # | 变异 | 变红的测试 |
|---|---|---|
| M1 | 写回后不重读其他行 | `TestASetterThatMovesAnotherPropertyRefreshesItsRow`；按钮 suite 4 条 |
| M2 | 挂了 `OnPropertyError` 后行显示新值 | `TestOnPropertyErrorTakesTheException…`、`TestAValueThatDoesNotParse…` |
| M3 | `Notification` 不清空 | 两条释放测试（投毒下 `EAccessViolation`） |
| M4 | D11(a) 候选根退回 `Owner` | `TestAFormListsTheControlsOnIt` |
| M5 | D11(b) 已处理也跑内置对话框 | `TestOnEditPropertyCanTakeTheStringsRow`、`TestOnEditPropertyReachesAnyDialogRow` |
| M6 | 忽略 `OnPropertyChanging` 的否决 | `TestOnPropertyChangingCanRefuse` |
| M7 | 重建后不恢复展开 | 往返流、集合增长、跨对象展开 3 条 |
| M8 | `Refresh` 从不重建 | `TestRefreshRebuildsWhenACollectionGrows` |
| M9 | 设计期照写 | `TestAtDesignTimeTheRowsAreListedButNothingIsWritten` |
| M10 | 下拉提交抛异常时不关列表（值列表编辑器） | `TestAPickThatRaisesStillClosesTheList` |
| M11 | 集合元素按元素报（`True`） | `TestASetElementIsAnnouncedAsTheWholeSet` |
| M12 | `Loaded` 不建行 | `TestTheSelectionAndTheSettingsComeBackFromAFormFile` |
| M13 | 候选根本身不列入 | `TestAFormListsTheControlsOnIt` |
| M14 | 重建丢当前行 | `TestRefreshRebuildsWhenACollectionGrows` |
| T1 | 表格答值列表编辑器的键 | `TestTheGridAnswersItsOwnKeyOnTheEditorsChain` |
| T2 | 不把 `TyPropertyGrid` 挂到 `TyValueListEditor` | 类型键 suite 3 条（136 处样式不同） |

**全量**（`32406302`，12 分 35 秒报告时间，墙钟约 75 分钟）：N 11522，E 0，F 2，I 1。F：`TPaletteIconTest.TestEveryPaletteClassHasItsIconResources`（新类还没有面板图标，预期，主控生成）；`TTbMainFormTests.TestTheLibraryCatalogueIsACopy`（见上，`5b80eaef` 修后单跑 84/84 绿）。I：`TSelectPathOptionsTest.TestNoReadOnlyReturn`（本机条件，原有）。

**留给主控**：面板图标（`tools/genicons/genicons.lpr` + `scripts/gen-icons.ps1`）；编 `.lpk` / dt 包、`examples/propertygrid`；Lazarus 3.0 构建；GUI 冒烟。
