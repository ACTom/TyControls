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

| # | 待核的事实 | 影响 |
|---|---|---|
| V1 | 第一期节点「按路径从根现找」的实现，以及 `PropertyAt`、`ExpandedProperties`、`Refresh` 在结构变化时自动重建的逻辑 | 多根要改哪几处 |
| V2 | `TCollection.Add` / `Delete` / `TCollectionItem.Index :=` 在 `TTyGridColumns` 等本库集合上会不会触发宿主的重排、通知（`Update`、`Notify`），有没有集合不允许用户增删（比如由宿主自动生成的列） | 增删要不要问宿主 |
| V3 | 本库的右键菜单（`TTyPopupMenu`）在控件里怎么挂、测试里怎么点菜单项；ValueListEditor 有没有现成的右键菜单，会不会冲突 | D2 的菜单 |
| V4 | ValueListEditor 能不能有不可编辑、不带值的「分组标题行」；没有的话，用 `ReadOnly` + 加粗 + 空值的行能不能做到，样式怎么区分 | D3 |

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
- 删除不弹确认框：集合项删了，宿主多半有撤销或者重新加的办法；需要确认的应用用 `OnCollectionChanging` 自己问。
- 做完之后行重建，展开状态保留，当前行落在新加 / 被移动的那一项上；删了就落在原位置的下一项（没有就上一项，再没有就集合行）。
- 菜单文字走 resourcestring，补 zh_CN。

**D3 属性分类**
- `ShowCategories: Boolean`，默认 False（保持第一期的平铺列表）。开了之后，顶层按分类分组，每组一个不可编辑的标题行，可展开 / 收起，组内仍按 `PropertyOrder` 排。
- 分类从哪来：内置一张小表，按属性名归到几个常见分类——「布局」（`Left`、`Top`、`Width`、`Height`、`Align`、`Anchors`、`AutoSize`、`BorderSpacing`、`Constraints`、`ChildSizing`）、「外观」（`Color`、`Font`、`Caption`、`Text`、`Visible`、`StyleClass`、`StyleOverride`、`Images`、`ImageIndex`、`Cursor`、`ParentColor`、`ParentFont`）、「行为」（`Enabled`、`ReadOnly`、`TabStop`、`TabOrder`、`Hint`、`ShowHint`、`PopupMenu`、`Action`）、「事件」（全部 `tkMethod`）、其余归「其他」。分类名走 resourcestring。
- `OnGetPropertyCategory(Sender; AInstance: TPersistent; const APropName: string; var ACategory: string)` 可以改任何属性的分类（包括自创分类）。分类组的顺序：内置几类按上面的顺序，自创的排在「其他」之前、按名字排。
- 分类只作用于顶层属性；子属性跟着它的父行走。
- 标题行的展开状态也记进 `ExpandedProperties`（用 `@分类名` 的形式，不会和属性名撞）。

**D4 按名字过滤**
- `FilterText: string`：非空时只显示名字（不区分大小写）包含它的属性；子属性命中时，它的父行跟着显示并自动展开，让命中的那行看得见。清空后恢复原来的展开状态。
- 不在控件里内置搜索框：自绘控件里嵌一个编辑框，牵涉焦点、Tab 顺序、主题，还会让「只要一个表格」的场景多出一块。应用放一个 `TTyEdit`，在 `OnChange` 里设 `FilterText` 就行，示例照这么演示。
- `FilterText` 和 `OnFilterProperty` 同时生效：先问事件，再按文字过滤。

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

## 签收（执行时填）
