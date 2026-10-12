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

| # | 待核的事实 | 影响 |
|---|---|---|
| V1 | ValueListEditor 的编辑器是否都已接线：文本、整数、浮点、布尔、枚举、颜色、字体、对话框、只读。开头那段注释说只做了文本和只读，已过时。2026-10-12 主控粗看是全接了。 | 映射直接用，顺手改掉过时注释 |
| V2 | 提交路径：`CommitEditorRow`（私有）→ `Value` → `OnValueChanged` → `PropagateUp`；字体行的子行（name/size/Bold…）各自也会触发 `OnValueChanged` | 写回挂在哪、字体整体写回还是逐项写回 |
| V3 | `TypInfo` 在 FPC 3.2 上的读写：`GetPropList`、`GetOrdProp`、`SetOrdProp`、`GetFloatProp`、`SetStrProp`、`GetEnumName`、`SetToString`、`StringToSet`、`GetObjectProp`、`tkSet` / `tkClass` / `tkMethod` / `tkInterface`；Lazarus 3.0 下同样可用 | 只用 3.0 就有的接口 |
| V4 | `TColor` 的识别：属性的 `PTypeInfo` 名为 `TColor` / `TGraphicsColor`；`ColorToString` / `IdentToColor` | 颜色行 |
| V5 | LCL `RTTIGrids.TTIPropertyGrid` 的公开接口名（`TIObject`、`Filter`、`ExpandedProperties`…） | 只借名字和习惯，代码自己写 |

## 设计

**D1 控件**：`TTyCustomPropertyGrid` / `TTyPropertyGrid`。`SelectedObject: TPersistent` 是 public，不发布：它运行时才有意义，写进 `.lfm` 就成了对某个组件的引用，设计期反而碍事。设计期可以发布 `SelectedComponent: TComponent`，存成普通组件引用，被引用的组件释放时经 `Notification` 自动清空。

**D2 行的生成**：
- 列出 published 属性。默认按名字排序（同 Object Inspector），`PropertyOrder = poDeclared` 时按声明顺序。
- 每行 `Key` 是属性名，`Data` 指向内部的属性节点：实例、`PPropInfo`、所属的父节点。
- `TypeFilter: TTypeKinds` 的默认值是除 `tkMethod` 外的全部种类，事件默认不显示。另有 `HiddenProperties: TStrings`，以及 `OnFilterProperty(Sender; AInstance: TPersistent; const APropName: string; var AShow: Boolean)`。

**D3 类型 → 编辑器**：

| 属性类型 | 行 |
|---|---|
| 整数、Int64、QWord、字符 | `vekInteger`（字符用 `vekText`，限一个字符） |
| 浮点 | `vekFloat`；`TDateTime` / `TDate` / `TTime` 显示成日期文字，按文本编辑、按本机格式解析 |
| 字符串（含 `TCaption`、`TTranslateString`） | `vekText` |
| 布尔 | `vekBoolean` |
| 枚举 | `vekEnum`，选项取 `GetEnumName` 的全部名字 |
| 集合 | 显示 `[a,b]`；子行是每个元素一个 `vekBoolean`；改子行会重算父行并写回 |
| `TColor` | `vekColor` |
| `TFont` | `vekFont`：沿用编辑器现成的字体行和子行，写回时把整个字体 `Assign` 回去 |
| 其他 `TPersistent` 类属性（`Constraints`、`BorderSpacing` 这类子对象） | 显示 `(TClassName)`，只读；子行是它的 published 属性，递归往下，有深度上限防止循环引用 |
| 组件引用（`TComponent` 子类，如 `PopupMenu`、`Images`） | `vekEnum`：选项是 `(none)` 加上同一个 `Owner` 下类型兼容的组件名 |
| `TStrings` | `vekDialog`：经 `OnEditRow` 的默认处理弹一个多行文本对话框（用本库的对话框，测试可替换） |
| `TCollection` | 第一期显示 `(N items)`、只读；编辑器放第二期 |
| 事件（`tkMethod`） | 默认不显示；`TypeFilter` 里加上 `tkMethod` 时显示处理程序名，只读 |
| 接口、变体、记录、其他 | 不显示 |

只读属性（没有 setter）一律 `ReadOnly`；类属性没有 setter 也照样展开子行，因为子对象自己的属性可写。

**D4 写回**：在提交前的钩子里写对象。写之前先过 `OnPropertyChanging(Sender; AInstance; const APropName, ANewValue: string; var AAllow: Boolean)`，写成功后触发 `OnPropertyChanged(Sender; AInstance; const APropName: string)`。setter 抛异常时，行保持旧值，并触发 `OnPropertyError(Sender; AInstance; const APropName: string; E: Exception)`。没挂这个事件时按 LCL 惯例重新抛出，交给 `Application.HandleException`。写回后，同一对象上其他行的显示值要重新读：一个属性的 setter 常会改到别的属性，比如 `AutoSize` 改 `Width`。

**D5 刷新**：`Refresh` 重新读所有行的值，不重建行、不丢展开状态和当前行。`SelectedObject` 换成别的对象时整体重建，同类对象之间切换保留展开的路径（`ExpandedProperties` 按属性路径记录）。对象被释放：组件会经 `FreeNotification` 自动清空；非组件的 `TPersistent` 由调用者负责在释放前清空，文档写明。

**D6 扩展点**（用户原则：内置只做常用行为，其余走事件和公开几何）：
- `OnFilterProperty`、`OnPropertyChanging` / `OnPropertyChanged` / `OnPropertyError`。
- `OnGetPropertyRow(Sender; AInstance; APropInfo: PPropInfo; ARow: TTyValueRow)`：行建好之后调用，应用可以改编辑器种类、枚举选项、显示文字、样式，或者把行设成只读。
- 公开 `PropertyAt(ARow: TTyValueRow; out AInstance: TPersistent; out APropName: string): Boolean`：应用的 `OnEditRow` 能据此给某种属性接上自己的对话框。

**D7 第二期（本计划不做，写进 #65）**：同时选中多个对象（只显示共同属性，改一处写回全部）、`TCollection` 编辑器、属性分类与分组、搜索过滤框。

**D8 主题**：typeKey `TyPropertyGrid` → `TyValueListEditor`，经 #14 的链回退，不加新令牌。

**D9 需主控确认**（不回复就按建议）：
1. 新控件 `TTyPropertyGrid`，不做「挂在任意 ValueListEditor 上的非可视适配器」。映射类独立，以后要做适配器可以复用。
2. `SelectedObject` 是 public，设计期发布 `SelectedComponent`。
3. 默认按名字排序，事件默认隐藏。
4. 组件引用用下拉，只列同一 `Owner` 下的组件。
5. `TCollection`、多选放第二期。

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
- 集合子行和父行重算；类属性递归展开和深度上限；`TFont` 整体 `Assign`；组件引用下拉；`TStrings` 对话框（经 protected virtual 弹出，测试替换）。
- 测试用真实控件：一个 `TTyButton`，看 `Font`、`Constraints`、`Anchors`（集合）、`PopupMenu`（组件引用）。
- 变异：集合子行改了不写回；循环引用不设深度上限（测试里构造一个互相引用的夹具）；组件下拉列出不同 `Owner` 的组件；字体只改了名字没改大小。

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

## 签收（执行时填）
