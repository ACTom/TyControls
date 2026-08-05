# TTyTreeView

## 1. 概述

`TTyTreeView` 是 TyControls 库中的**虚拟树控件**，继承自 `TTyCustomControl`。它借鉴 VirtualTreeView 的架构：节点不是常规对象树，而是紧凑的 `TTyTreeNode` 记录链，**按需（懒惰）初始化**——控件只知道每层有多少节点，节点的文本 / 图标 / 子节点数量全部通过事件在真正需要绘制时才计算。因此它能在恒定内存下承载百万级节点。典型用途：文件资源管理器、多列数据表、带复选框 / 单选钮的层级列表、可拖拽重排的分组树。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.TreeView`（列 / 表头模型在 `tyControls.Columns`） |
| `GetStyleTypeKey` 返回值 | `'TyTreeView'` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |

在 `.tycss` 文件中，控件外框对应选择器前缀 `TyTreeView`。此外控件在绘制时还会解析若干**子部件 typeKey**（均不是独立控件，只是主题查找键）：`TyTreeNode`（行）、`TyTreeHeader`（表头带）、`TyTreeHeaderSection`（表头分区）、`TyTreeCheckBox`（复选 / 单选框槽）。详见第 5 节。

```pascal
uses tyControls.TreeView, tyControls.Columns;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Options` | `TTyTreeOptions` | `[]` | 树级功能开关集合（见下表），默认全部关闭 |
| `Header` | `TTyHeader` | 见下 | 表头 / 列模型子对象（`TPersistent`，随控件流式保存） |
| `NodeDataSize` | `Integer` | `-1` | 每个节点尾部附带的用户数据块字节数；`-1` 表示无数据块。设置后每个节点分配 `TreeNodeSize + NodeDataSize` 字节 |
| `DefaultNodeHeight` | `Integer` | `18` | 未启用变高时每行的逻辑像素高度 |
| `RootNodeCount` | `Cardinal` | `0` | 根级（顶层）节点数量。写入即创建这么多未初始化的根节点骨架 |
| `Indent` | `Integer` | `16` | 每一层的缩进逻辑像素 |
| `Images` | `TCustomImageList` | `nil` | 主列节点图标的图像列表，配合 `OnGetImageIndex` 使用。类型是 `TCustomImageList`（对齐 LCL），任何派生自它的列表都能赋值 |
| `EmptyListMessage` | `string` | `''` | 树为空时在内容区居中显示的提示文字 |
| `ShowButtons` | `Boolean` | `True` | 是否绘制展开 / 折叠按钮（±方块） |
| `ShowTreeLines` | `Boolean` | `True` | 是否绘制连接父子节点的树状连线 |
| `ShowRoot` | `Boolean` | `True` | 根节点是否显示展开按钮 / 缩进（`False` 时根节点平铺无缩进） |
| `ToggleOnDblClick` | `Boolean` | `True` | 双击一行是否展开 / 折叠该节点 |
| `HotTrack` | `Boolean` | `False` | 是否高亮鼠标悬停行（`:hover` 状态） |
| `SearchTimeout` | `Integer` | `1000` | 键入查找（type-to-find）缓冲区空闲多少毫秒后自动重置 |
| `ScrollBars` | `TScrollStyle` | `ssBoth` | 允许出现哪些方向的滚动条。`ssNone` = 视口固定（嵌在外层滚动容器里时用）；被禁掉的那一轴偏移会归零 |
| `AutoExpand` | `Boolean` | `False` | 焦点移入的节点自动展开、移出的自动折叠（新焦点在旧节点子树内时不折叠） |
| `RightClickSelect` | `Boolean` | `True` | 右键按下是否把焦点移到点中的节点。**默认与 LCL 不同**：LCL 默认 `False`，本控件一直是"右键跟随"，故保留 `True`；要 LCL 行为设 `False` |
| `HideSelection` | `Boolean` | `True` | 控件失去焦点时是否隐藏选中高亮（并排两棵树不会都显示强高亮）。隐藏＝该行按普通行的主题样式绘制，不在控件里凭空造颜色 |
| `ShowSeparators` | `Boolean` | `False` | 是否在每个顶层行下画一条分隔线（颜色取控件边框色 token，与树状连线同源） |
| `TabStop` | `Boolean` | `True` | 是否参与键盘 Tab 焦点循环 |

#### LCL 名字的等价成员（public，不 published）

这些成员只是把已有状态换成 LCL 的拼法暴露出来，**不额外流式保存**（避免 `.lfm` 里同一个开关出现两份互相打架的值）：

| 成员 | 等价于 | 说明 |
|------|--------|------|
| `RowSelect` | `toFullRowSelect in Options` | 整行选中 |
| `MultiSelect` | `toMultiSelect in Options` | 多选 |
| `ShowLines` | `ShowTreeLines` | 树状连线 |
| `ReadOnly` | `not (toEditable in Options)` | **默认 `True`**（本控件就地编辑是 opt-in）；`ReadOnly := False` 等于 `Options + [toEditable]` |
| `DefaultItemHeight` | `DefaultNodeHeight` | 同一个读写器，未显式设定时同样跟随 `--item-height` 密度令牌 |

#### `Options` 集合（`TTyTreeOption`）

| 标志 | 作用 |
|------|------|
| `toMultiSelect` | 启用多选（Ctrl / Shift / Ctrl+A + 键盘范围扩展） |
| `toCheckSupport` | 启用复选框 / 三态 / 单选钮支持（`CheckType` 生效、点击复选槽切换状态） |
| `toFullRowSelect` | 整行高亮（而非仅标签区） |
| `toAutoTristateTracking` | 复选状态自动向下传播（父勾则子全勾）+ 向上重算三态父节点 |
| `toVariableNodeHeight` | 启用每节点变高，配合 `OnMeasureItem` 返回逐行高度 |
| `toIncrementalSearch` | 启用键入查找：有焦点时键入可打印字符跳转到下一匹配的可见节点 |
| `toOwnerDraw` | 启用逐单元格自绘 `OnDrawNode`（完全替换默认单元格内容） |
| `toEditable` | 启用就地编辑：F2 / 双击可编辑单元格弹出主题化 `TTyEdit` 覆盖框 |
| `toNodeDrag` | 启用树内节点拖放（拖动节点在兄弟间重排 / 重设父级） |

#### `Header`（`TTyHeader`）子对象属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Height` | `Integer` | `22` | 表头带高度 |
| `Columns` | `TTyColumns` | 空集合 | 列集合（`TCollection`）；`Columns.Add` 追加一个 `TTyColumn` |
| `MainColumn` | `Integer` | `0` | **主列**（绘制展开按钮 / 图标 / 树缩进的那一列）。见下方警告 |
| `SortColumn` | `Integer` | `-1` | 当前排序列（`-1` = 未排序）；点击表头自动更新 |
| `SortDirection` | `TTySortDirection` | `sdAscending` | 当前排序方向 |
| `AutoSizeIndex` | `Integer` | `-1` | 自动填充剩余宽度的列索引（配合 `hoAutoResize`） |
| `Images` | `TTyVirtualImageList` | `nil` | 列头图标的图像源，按 `TTyColumn.ImageIndex` 取图。以前的类型是 LCL 的 `TCustomImageList`——而 `TTyVirtualImageList` 并非它的后代，于是能赋给它的恰恰全是本库画不了的列表，这个属性从类型上就是不可用的。**目前只有 `TTyListView` 的报表表头会读它**；树的表头绘制尚未接上。|
| `Options` | `TTyHeaderOptions` | `[hoVisible, hoColumnResize, hoShowSortGlyphs, hoHeaderClickAutoSort, hoDrag]` | 表头选项（见下） |

> **⚠️ 关键陷阱：`MainColumn` 必须在列添加之后设置。** `SetMainColumn` 在 `Columns.Count = 0` 时会把任何赋值**夹紧为 `NoColumn`（-1）**。若在添加任何列之前写 `MainColumn := 0`，它会被夹成 -1，导致主列块永远不匹配——展开按钮、节点图标、主列文字**全部消失**，只剩平铺文本格。**正确顺序是先 `Columns.Add`，再设 `MainColumn`。** 作为兜底，控件在**添加第一列**且 `MainColumn` 仍为 `NoColumn` 时会自动把它默认为 `0`（与 VirtualTreeView 一致）；但显式的错误顺序仍应避免。示例（来自 showcase）：
>
> ```pascal
> with ColTree.Header do
> begin
>   Columns.Add;  Columns.Add;  Columns.Add;  Columns.Add;  // 先加 4 列
>   MainColumn := 0;                                        // 再设主列
> end;
> ```

#### `Header.Options`（`TTyHeaderOption`）

| 标志 | 作用 |
|------|------|
| `hoVisible` | 在节点区上方绘制表头带 |
| `hoColumnResize` | 允许拖动列分隔线调整列宽 |
| `hoShowSortGlyphs` | 在排序列显示排序三角字形 |
| `hoHeaderClickAutoSort` | 点击表头分区触发 `SortTree` |
| `hoDrag` | 允许拖动列头重排列顺序 |
| `hoAutoResize` | 令 `AutoSizeIndex` 列填充剩余宽度 |
| `hoHotTrack` | 高亮悬停的表头分区 |

#### `TTyColumn`（列项）自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Width` | `Integer` | `100` | 列宽（写入时夹紧到 `[MinWidth, MaxWidth]`） |
| `MinWidth` | `Integer` | `10` | 最小列宽 |
| `MaxWidth` | `Integer` | `10000` | 最大列宽 |
| `Position` | `Cardinal` | 添加顺序 | 视觉位置（0 基），可与集合 `Index` 不同（拖拽重排后） |
| `Alignment` | `TAlignment` | `taLeftJustify` | 单元格文本对齐 |
| `CaptionAlignment` | `TAlignment` | `taLeftJustify` | 表头标题对齐 |
| `Text` | `string` | `''` | 表头标题文字 |
| `ImageIndex` | `Integer` | `-1` | 表头图标索引 |
| `Options` | `TTyColumnOptions` | `[coVisible, coResizable, coAllowClick, coDraggable]` | 列级选项（`coVisible` / `coResizable` / `coAllowClick` / `coDraggable` / `coAutoSpring`） |
| `Tag` | `NativeInt` | `0` | 用户自定义标记 |
| `Visible` | `Boolean` | `True` | 列可见性。**存储仍是 `Options` 里的 `coVisible`**,这是它的一个视图(对标 LCL `TGridColumn.Visible`);`stored False`,由 `Options` 负责流式化 |
| `MinSize` / `MaxSize` | `Integer` | 同 `MinWidth` / `MaxWidth` | LCL 对宽度上下限的叫法,别名。注意默认值与 LCL 不同:LCL 的 `DEFMINSIZE`/`DEFMAXSIZE` 都是 0(无界),这里是 10 / 10000 —— 要无界请显式写 0 |
| `SizePriority` | `Integer` | `1` | 分配多余宽度时这一列的权重(见 `TTyCustomGrid.AutoFillColumns`)。0 = 永不自动调宽。对标 LCL `TGridColumn.SizePriority` |

### 继承的通用成员

`TTyTreeView` 继承自 `TTyCustomControl`（`tyControls.Base`），并 re-publish 了下列成员：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Align` | `TAlign` | `alNone` | 父容器内停靠方式 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 锚点布局 |
| `Font` | `TFont` | 系统默认 | 仅用于传递 PPI；字体族 / 字号由主题控制 |
| `StyleClass` | `string` | `''` | CSS 变体类名，对应 `.tycss` 选择器的 `.classname` |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定样式控制器 |

### 状态跟踪字段（protected / 内部）

树的行状态不存在单一 `FHover` / `FPressed` 上，而是**逐节点**记录在 `TTyTreeNode.States`（`TTyNodeStates`）里，绘制时逐行解析样式：

| 字段 / 集合成员 | 说明 |
|-----------------|------|
| `FHotNode` | 鼠标悬停的节点（`HotTrack` 时触发该行 `:hover`）；`nil` 表示无 |
| `nsSelected`（节点状态） | 该节点被选中，触发行 `:selected` |
| `nsExpanded` / `nsHasChildren` | 展开态 / 是否有子节点（含未物化） |
| `nsInitialized` / `nsHeightMeasured` | 懒惰初始化 / 变高测量标记 |
| `FFocusedNode` / `FSelectedNode` | 当前焦点 / 单选节点指针 |
| `FSelectionCount` | 多选计数（`SelectedCount` 读取） |

> 控件**没有**重写 `CurrentStates`——`TyTreeView` 外框沿用基类的 `:hover`/`:focus`/`:disabled` 机制；行 / 复选框的 `:hover`/`:selected` 是绘制时对子 typeKey 单独解析样式实现的（见第 5 节）。

---

## 4. 事件

`TTyTreeView` 暴露的专有事件极多，按用途分组：

### 虚拟模型 / 生命周期

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnInitNode` | `TTyTreeInitNodeEvent` | 节点首次初始化时；app 在 `var InitStates` 里 `Include(ivsHasChildren)` 等声明该节点特性 |
| `OnInitChildren` | `TTyTreeInitChildrenEvent` | 展开一个已声明 `ivsHasChildren` 的节点时；app 通过 `var ChildCount` 返回子节点数 |
| `OnFreeNode` | `TTyTreeNodeEvent` | 节点被释放前（用于清理节点数据块中的托管字段） |
| `OnExpanding` | `TTyTreeChangingEvent` | 展开**之前**；`var Allowed := False` 可否决 |
| `OnExpanded` | `TTyTreeNodeEvent` | 展开完成后 |
| `OnCollapsing` | `TTyTreeChangingEvent` | 折叠**之前**；`var Allowed := False` 可否决 |
| `OnCollapsed` | `TTyTreeNodeEvent` | 折叠完成后 |

### 选择 / 焦点 / 交互

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnChanging` | `TTyTreeChangingEvent` | 选择 / 焦点移动**之前**；`var Allowed := False` 可否决——焦点和选中都不动。一次手势只问一次（`FocusedNode := X` 内部会转调 `SetSelected`，不会重复发问），对"同一个节点再设一次"这种空操作不发问 |
| `OnChange` | `TTyTreeNodeEvent` | 单选选择集实际变化时（`SetSelected` / `ClearSelection`） |
| `OnFocusChanged` | `TTyTreeNodeEvent` | 焦点节点变化时 |
| `OnSelectionChanged` | `TNotifyEvent` | **多选**集合每次手势变化后触发一次（`toMultiSelect`） |
| `OnNodeClick` | `TTyTreeNodeEvent` | 单击某节点 |
| `OnNodeDblClick` | `TTyTreeNodeEvent` | 双击某节点 |

### 复选框

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnChecking` | `TTyTreeCheckingEvent` | 勾选状态变化**之前**；`var Allowed := False` 可否决 |
| `OnChecked` | `TTyTreeNodeEvent` | 勾选状态变化后 |

### 文本 / 图标 / 绘制

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnGetText` | `TTyTreeGetTextEvent` | 取节点文本（简单签名 `var Text`；单列 / 主列常用） |
| `OnGetTextWithType` | `TTyTreeGetTextWithTypeEvent` | 取单元格文本（完整签名，带 `Column` + `TextType: ttNormal/ttStatic`；多列用） |
| `OnGetImageIndex` | `TTyTreeGetImageIndexEvent` | 取节点图标索引（带 `Kind` + `Column` + `var Ghosted`）。`Ghosted := True` **会被采纳**：该行图标按"不可用"绘制（走 `TCustomImageList.Draw` 的禁用灰化）。以前这个标志被收下就丢掉；后来只在**多列**分支接上，0 列（默认形态）仍然丢——现在两条分支都接上了。`Kind` 现在会被真的问到三次：`ikNormal` 每行都问，`ikSelected` 只对选中行问（**以当前 `ikNormal` 结果为初值**，handler 不管它就保持原图标，老代码渲染不变），`ikOverlay` 初值 `-1`、答了就叠画在普通图标之上。`ikState` 仍未实现（需要第二个图像列表和自己的槽位，见"注意事项"） |
| `OnPaintText` | `TTyTreePaintTextEvent` | 文本绘制后的钩子 |
| `OnMeasureItem` | `TTyTreeMeasureItemEvent` | 从 `InitNode` 触发（仅 `toVariableNodeHeight`），app 通过 `var ANodeHeight` 返回逐行高度（逻辑像素） |
| `OnDrawNode` | `TTyTreeDrawNodeEvent` | 逐单元格**完全自绘**（仅 `toOwnerDraw`）；在 BGRA 合成后、裁剪到单元格设备矩形时触发，跳过默认单元格内容 |
| `OnAfterCellPaint` | `TTyTreeCellPaintEvent` | 每个绘制单元格之上的**叠加层**（独立于 `toOwnerDraw`），用于徽标 / 焦点环等装饰 |
| `OnIncrementalSearch` | `TTyTreeIncrementalSearchEvent` | 键入查找的自定义匹配谓词（不赋值时默认对主列文本做大小写不敏感前缀匹配） |

### 列 / 表头 / 排序

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnColumnResized` | `TTyTreeColumnEvent` | 某列被拖动改变宽度后 |
| `OnColumnReorder` | `TTyTreeColumnReorderEvent` | 列被拖到新位置后（`OldPosition, NewPosition`） |
| `OnCompareNodes` | `TTyTreeCompareEvent` | 排序引擎比较两节点；app 返回 `<0 / 0 / >0`（自然序，方向由内部处理） |
| `OnHeaderClick` | `TTyTreeColumnEvent` | 点击表头分区后（若触发了排序，在排序之后发出） |

### 就地编辑

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnEditing` | `TTyTreeEditingEvent` | 编辑器打开**之前**；`var Allowed`（默认 `True`）设 `False` 否决该单元格编辑 |
| `OnNewText` | `TTyTreeNewTextEvent` | 提交时**仅在文本实际改变**才触发；app 把 `NewText` 写入自己的节点数据块 |
| `OnEditCancelled` | `TTyTreeColumnNodeEvent` | Esc / 程序化 `CancelEdit` 时 |
| `OnEditingEnd` | `TTyTreeEditingEndEvent` | 编辑会话结束时**必定触发一次**，提交 `Cancel = False`，取消 `Cancel = True`。`OnNewText` 只在文本变了才发，所以它不能当"编辑器关了"的信号用 |

### 节点拖放

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnNodeDragOver` | `TTyTreeDragOverEvent` | 拖拽过程中的逐目标 / 逐模式否决；`Allowed` 入参为 `CanMoveNode(...)` 结果，handler **只能进一步收紧**（对无效移动设 `Allowed := True` 仍被 `MoveNode` 的硬闸拦下）。**此前叫 `OnDragOver`**，那个名字已还给 LCL 的拖放钩子 |
| `OnNodeMoved` | `TTyTreeNodeEvent` | 一次成功放下后（`Node.Parent` 已是新父节点） |

> 除上表外，`TTyTreeView` 还暴露**基线事件集**（Tier A 鼠标 / 通用 + Tier B 键盘 / 焦点事件，因其为可聚焦的 `TTyCustomControl`）。完整清单见 [../events.md](../events.md)。内部内嵌的两个滚动条（`VScroll` / `HScroll`）是私有子部件，不暴露其事件。

---

## 5. 状态与主题

### 支持的伪类状态

外框 `TyTreeView` 沿用基类状态机；行 / 复选框子部件在绘制时单独解析伪类：

| 子 typeKey | 伪类 | 触发条件 |
|-----------|------|----------|
| `TyTreeView` | `:hover` / `:focus` / `:disabled` | 外框整体（基类 `CurrentStates`） |
| `TyTreeNode` | `:hover` | 该行被鼠标悬停（`HotTrack = True` 时的 `FHotNode`） |
| `TyTreeNode` | `:selected` | 该节点 `nsSelected` |
| `TyTreeNode` | `:disabled` | 该节点不可用 |
| `TyTreeHeaderSection` | 无 | 表头分区的底色 / 文字色 / 字体，**以空状态集解析**——树的表头不做悬停或排序列高亮，写 `TyTreeHeaderSection:hover` / `:selected` 不会生效（独立的 [`TTyHeaderControl`](headercontrol.md) 才消费 `:hover`） |
| `TyTreeCheckBox` | `:active` / `:selected` / `:disabled` | 已勾选 / 选中行内 / 禁用的复选槽 |

### light.tycss 内置规则摘要

```css
TyTreeView { background: var(--input-bg); color: var(--on-surface);
             border-color: var(--border); border-width: var(--input-border-width);
             border-radius: var(--radius); padding: 2px;
             font-size: var(--font-size-base); }

TyTreeNode          { background: none; color: var(--on-surface); }
TyTreeNode:hover    { background: var(--surface-hover); }
TyTreeNode:selected { background: var(--accent); color: var(--on-accent); }
TyTreeNode:disabled { color: var(--muted); }

TyTreeHeader        { background: var(--surface-chrome); border-color: var(--border);
                      border-width: var(--input-border-width); color: var(--on-surface);
                      font-size: var(--font-size-base); font-weight: var(--font-weight-bold); }
TyTreeHeaderSection         { background: none; color: var(--on-surface);
                              border-color: var(--border); }
TyTreeHeaderSection:hover   { background: var(--surface-hover); }
TyTreeHeaderSection:selected{ background: var(--surface-active); }

TyTreeCheckBox          { background: var(--input-bg); color: var(--on-surface);
                          border-color: var(--border);
                          border-width: var(--input-border-width);
                          border-radius: var(--radius-sm); }
TyTreeCheckBox:active   { background: var(--accent); color: var(--on-accent);
                          border-color: var(--accent); }
TyTreeCheckBox:selected { background: var(--accent); color: var(--on-accent);
                          border-color: var(--accent); }
TyTreeCheckBox:disabled { color: var(--muted); }
```

### 渲染细节

- 每行独立解析 `TyTreeNode` 样式：先按 `:selected` / `:hover` 求得行背景，再在其上绘制展开按钮、树连线、图标、复选槽、文本。
- 主列（`MainColumn`）承载缩进 / 展开按钮 / 图标 / 复选槽；其余列只绘制平铺文本。`Indent` 决定每层左移量。
- 复选槽（`TyTreeCheckBox`）依 `CheckType` 绘制勾号（`ctCheckBox` / `ctTriStateCheckBox`）或圆点（`ctRadioButton`）；三态 `csMixed` 绘制半勾。
- 排序三角字形仅在 `hoShowSortGlyphs` 且该列为 `SortColumn` 时绘制。
- 内嵌滚动条使用各自的 `TyScrollBar` 主题，且 thumb 不做缓动动画（内嵌滚动直接跟随）。

> **横轴只有两处算 x。** 列的屏幕跨度出自 `TyColumnSpan`(`tyControls.Columns.pas`)——
> 绘制、表头、拖列浮标、`GetCellRect` 与两个命中函数都从它取 `Left`/`Right`;
> 节点内部的缩进 / 展开槽 / 复选槽 / 图标槽 / 标题起点出自 `NodeCaptionSlots`
> (它包装纯函数 `TyTreeCaptionSlots`)——两处绘制、命中判定、`CellTextRect`
> 和 `DisplayExpandSignRect` 都读它。这两条是有意维持的:
> "画在这边、点在那边"这类 bug 只能从第二份算式里长出来。
> 改这个文件时请保持它 —— 任何在这两个函数之外新算出来的 x,都是一条会走散的第二路径。
>
> 已知偏差(**尚未修复**,见 `GetNodeAtPoint` 的注释):命中判定给 `NodeCaptionSlots`
> 传的锚点是 `0`,即假设主列从内容区左缘开始。`Header.MainColumn` 不是最左可见列时该假设
> 不成立,展开箭头会画在 `Scale(MainColumn.Left)` 之外、却在原处接收点击 —— 点箭头不展开。

---

## 6. 代码示例

下例镜像 showcase 中「Columns + Sort」页的用法：多列 + 数据在节点 + 稳定排序 + 就地编辑 + 图标。

```pascal
uses
  tyControls.Controller, tyControls.TreeView, tyControls.Columns;

type
  { 稳定的逐节点数据（存在节点数据块里，不依赖 Node^.Index，排序后仍随行走） }
  TRowRec = record NameIdx, Kind: Integer; Size: Int64; end;
  PRowRec = ^TRowRec;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

// 创建树
var Tree: TTyTreeView;
Tree := TTyTreeView.Create(Self);
Tree.Parent := Self;
Tree.Align := alClient;

// 每节点附带 TRowRec 数据块
Tree.NodeDataSize := SizeOf(TRowRec);

// 启用就地编辑
Tree.Options := [toEditable];

// 挂接虚拟模型 + 绘制 + 排序事件
Tree.OnInitNode        := @TreeInitNode;
Tree.OnInitChildren    := @TreeInitChildren;
Tree.OnGetTextWithType := @TreeGetText;
Tree.OnCompareNodes    := @TreeCompareNodes;

// 建列 —— 先加列，再设 MainColumn（顺序至关重要，见第 3 节警告）
with Tree.Header do
begin
  Options := [hoVisible, hoColumnResize, hoShowSortGlyphs,
              hoHeaderClickAutoSort, hoDrag];
  (Columns.Add as TTyColumn).Text := 'Name';
  (Columns.Add as TTyColumn).Text := 'Size';
  MainColumn := 0;                 // ← 一定在 Columns.Add 之后
end;

// 3 个根节点（懒惰初始化，此刻不创建任何子结构）
Tree.RootNodeCount := 3;

// —— 事件处理器 ——

procedure TForm1.TreeInitNode(Sender: TTyTreeView;
  ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates);
var data: PRowRec;
begin
  if Sender.GetNodeLevel(Node) = 0 then
    Include(InitStates, ivsHasChildren);   // 顶层是文件夹，可展开
  data := PRowRec(Sender.GetNodeData(Node));
  if data <> nil then
    data^.NameIdx := Integer(Node^.Index); // 存稳定 key，排序后不失效
end;

procedure TForm1.TreeInitChildren(Sender: TTyTreeView;
  Node: PTyTreeNode; var ChildCount: Cardinal);
begin
  ChildCount := 5;                         // 展开时懒惰返回子节点数
end;

procedure TForm1.TreeGetText(Sender: TTyTreeView; Node: PTyTreeNode;
  Column: Integer; TextType: TTyVSTTextType; var CellText: string);
var data: PRowRec;
begin
  if TextType <> ttNormal then Exit;
  data := PRowRec(Sender.GetNodeData(Node));
  case Column of
    0: CellText := Format('Item %d', [data^.NameIdx]);
    1: CellText := IntToStr(data^.Size);
  end;
end;

procedure TForm1.TreeCompareNodes(Sender: TTyTreeView;
  Node1, Node2: PTyTreeNode; Column: Integer; var CompareResult: Integer);
var d1, d2: PRowRec;
begin
  d1 := PRowRec(Sender.GetNodeData(Node1));
  d2 := PRowRec(Sender.GetNodeData(Node2));
  CompareResult := d1^.NameIdx - d2^.NameIdx;   // 读数据块，绝不读 Node^.Index
end;
```

启用其他能力只需改 `Options` + 挂对应事件：

```pascal
// 复选框（三态自动传播）
Tree.Options := [toCheckSupport, toAutoTristateTracking];
// 在 OnInitNode 里：Node^.CheckType := ctTriStateCheckBox;（或 ctCheckBox / ctRadioButton）

// 多选 + 整行高亮
Tree.Options := [toMultiSelect, toFullRowSelect];
Tree.OnSelectionChanged := @OnSelChanged;   // 内读 Tree.SelectedCount

// 节点拖放
Tree.Options := [toNodeDrag];
Tree.OnNodeMoved := @OnMoved;
```

---

## 7. 与 LCL `TTreeView` 对齐（含 3 个不兼容改名）

### 三个撞名成员：名字还给 LCL，我们的含义换了名字

| 现在 | 以前 | 为什么必须改 |
|------|------|--------------|
| `GetNodeAt(X, Y: Integer): PTyTreeNode` | —— | LCL 的 `GetNodeAt` 就是"客户区某点上的节点"（`comctrls.pp:3716`） |
| `GetNodeAtOffset(Y; out ANodeTop)` | `GetNodeAt(Y; out ANodeTop)` | **同名、同参数个数、两个参数都是 `Integer`**，所以移植过来的 `Tree.GetNodeAt(X, Y)` 会**编译通过**：把调用方的 X 当成滚动空间的 Y 用，再把调用方的 Y 变量用 out 参数覆写掉，返回错误的节点且没有任何警告。改名当天本仓库自己的 12 条断言立刻变红，就是这条路径 |
| `NodeSelected[Node]: Boolean` | `Selected[Node]: Boolean` | `Selected` 在 LCL 是**当前节点**（`comctrls.pp:3778`）。`if Tree.Selected <> nil` / `Tree.Selected := N` 这两句最常写的代码在带下标的布尔属性上根本编不过 |
| `OnNodeDragOver` | `OnDragOver` | `OnDragOver` 是 `TControl` 的 LCL 拖放钩子，基类本来就 published。树把这个名字占成了内部节点拖放的否决事件，于是**整个库里只有这一个控件不能当 LCL 拖放目标**——往上挂一个正常的 `TDragOverEvent` 是类型错误 |

迁移只有三条替换：`GetNodeAt(y, top)` → `GetNodeAtOffset(y, top)`；`Selected[n]` → `NodeSelected[n]`；`OnDragOver := @H` → `OnNodeDragOver := @H`。

### 新增的 LCL 成员

| 成员 | 说明 |
|------|------|
| `Selected: PTyTreeNode` | 当前节点。读：焦点节点（选中时），否则第一个选中节点，都没有则 `nil`。写：独占选中并把焦点移过去；写 `nil` 等于 `ClearSelection` |
| `SelectionCount` / `Selections[i]` | 多选的随机访问，让 `for i := 0 to SelectionCount-1 do Use(Selections[i])` 直接可用。**类型是 `Integer` 不是 LCL 的 `Cardinal`**——空选择时 `Cardinal(0) - 1` 会绕成 40 亿。`Selections[i]` 每次都是 O(n) 线性走，热循环仍请用 `GetFirstSelected` / `GetNextSelected` |
| `GetLastSelected` | 屏幕序里最后一个选中节点 |
| `NodeVisible[Node]: Boolean` | 隐藏单个节点及其子树而不删除它——过滤要的就是这个形状。引擎一直支持不可见节点（各处遍历都看 `nsVisible`），只是开关没暴露，于是过滤只能删了再加。隐藏会把该节点的子树高度从祖先链上扣掉（`ContentHeight` / 滚动条 / 位置缓存同步），并且**不会**把光标或选中留在一个不绘制的行上。**故意不叫 `Visible`**：LCL 把它挂在 `TTreeNode`（一个类）上，我们的节点是记录，只能挂到控件上——而控件上的 `Visible` 已经是"这个控件显不显示"，同名带下标属性会把 `TControl.Visible` 遮掉，`Tree.Visible := False` 直接编不过。命名与 `NodeSelected` 一致 |
| `HasChildren[Node]: Boolean` | 可反复设置的"有没有子节点"。以前只能从 `OnInitNode` 的 `ivsHasChildren` 回答一次，`ivsReInit` 又没有公开触发点，所以一个"后来才变成非空"的目录永远长不出展开箭头。写 `False` 会先折叠，避免留下一堆没法收起来的行 |
| `ScrolledTop` / `ScrolledLeft` | 可读**可写**的滚动位置（LCL 的符号约定：已滚走的像素数，即 `-OffsetY` / `-OffsetX`）。刷新前后保存 / 恢复滚动位置靠它 |
| `TopItem` / `BottomItem` | 视口顶 / 底的节点；`TopItem := N` 把 N 滚到顶部 |
| `DisplayRect(Node, TextOnly, out R)` | 行矩形 / 仅标题矩形（设备像素，`ContentRect` 坐标系） |
| `DisplayTextLeft(Node, out L)` | 标题起始 X——把浮层锚到**文字**而不是整格时要的那个值 |
| `DisplayExpandSignRect(Node, out R)` | 展开箭头的方框；没有箭头的节点返回 `False` |
| `GetNodeWithExpandSignAt(X, Y)` | 只在展开箭头上才回答的命中测试 |
| `GetHitTestInfoAt(X, Y): THitTests` | LCL 的**集合**型命中结果（`comctrls.pp:41`），能同时表达 `htOnItem` + `htOnLabel`；我们自己的 `GetNodeAtPoint` 返回的是单值枚举，表达不了这种组合 |
| `AlphaSort(Node = nil)` | 按节点主列文本排序，**不需要任何 compare handler**。`Sort` / `SortTree` 都走 `DoCompare` → `OnCompareNodes`，没挂 handler 时返回 0，也就是说"按字母排序"这个最常见的需求以前是个静默的空操作 |
| `CustomSort(SortProc, Node = nil)` | 用一个**普通函数**（非方法指针）排序；结束后归还 app 原来的 `OnCompareNodes` |

### 已知仍未对齐

- `Items` / `TTreeNodes` / `Node.Text` 那套**可流式化的节点对象模型**没有，也不打算有：本控件是虚拟树，节点是定长记录 + 用户数据块，文本由 `OnGetText` 现算。设计期的"TreeView Items Editor"与 `.lfm` 里的节点树因此都不存在。
- `ikState` / `StateImages`：需要第二个图像列表**和它自己的行内槽位**（会牵动命中测试、标题矩形、编辑器定位三处几何），本轮没做。`ikNormal` / `ikSelected` / `ikOverlay` 已可用。
- `ToolTips`：没有"标题被裁剪时自动弹出完整文本"的逐项提示，只有继承自 `TControl` 的整控件 `Hint`。
- `SortType`（插入时自动保持有序）、`Cut` / `DropTarget` 逐节点显示态、逐节点 `Enabled` / `DisabledFontColor`、`OnCustomDraw*` 整行/整控件分阶段绘制、`InsertMark*` 外部拖放插入标记——均未实现。
- `TreeLineColor` / `TreeLinePenStyle` / `ExpandSignColor|Size|Width` / `SeparatorColor` 这类**逐控件颜色与线型旋钮**按本库硬规则不做：视觉值一律走主题 token。树状连线与分隔线取控件边框色 token，展开箭头取行文字色 token 并支持 `--glyph-chevron-down` / `--glyph-chevron-right` 覆盖。

---

## 8. 注意事项

- **`MainColumn` 必须在列添加之后设置**（本文档最重要的陷阱）：`Columns.Count = 0` 时 `SetMainColumn` 把值夹紧为 `NoColumn(-1)`，主列块永不匹配 → 展开按钮 / 图标 / 主列文字全部消失。控件仅在**添加第一列时**自动把 `NoColumn` 兜底为 `0`；显式错误顺序仍会出问题。删除列时控件会自动跟随重编号修正 `MainColumn`。
- **虚拟 = 数据在你手里，不在树里**：树本身不存文本 / 图标 / 子节点。文本经 `OnGetText` / `OnGetTextWithType` 现算；子节点数经 `OnInitChildren` 现算。持久数据放进节点数据块（`NodeDataSize` + `GetNodeData`），**不要**用 `Node^.Index` 作为持久 key——排序会重新戳 `Index`，稳定 key 必须存在数据块里。
- **三阶段懒惰初始化**：① `RootNodeCount :=` 创建根节点骨架（未初始化）；② 首次需要一个节点时 `InitNode` 触发 `OnInitNode`，app 声明 `ivsHasChildren` / `ivsExpanded` / `ivsSelected`；③ 展开一个声明了有子节点的节点时 `InitChildren` 触发 `OnInitChildren` 物化子节点。恒定内存直到用户实际展开。
- **变高节点**：`toVariableNodeHeight` + `OnMeasureItem` 才生效；测量在 `InitNode` 末尾进行一次。未启用时每行都用 `DefaultNodeHeight`。
- **`OnNodeDragOver` 只能收紧不能放宽**：`CanMoveNode` 是硬闸（非空、模式非 `dmNone`、目标不在源子树内、非空操作等），对无效移动即便 handler 设 `Allowed := True` 也会被 `MoveNode` 拦下。
- **`OnAfterCellPaint` 与 `OnDrawNode` 的裁剪时机**：二者都在 BGRA 图层合成到画布**之后**触发（跨平台后处理路径）。因此没有「在默认文本下方绘制背景」的 `OnBeforeCellPaint`——那需要不同的绘制路径，目前未实现。
- **`toCheckSupport` 是复选框总开关**：未加入 `Options` 时，即使给节点设了 `CheckType`，`ToggleCheck` 也直接返回、不绘制复选槽。三态自动传播还额外需要 `toAutoTristateTracking`。
- **单选 vs 多选事件**：单选走 `OnChange`（`FSelectedNode` 变化）；多选走 `OnSelectionChanged`（每次手势后一次）。二者是不同的通道。
- **`Enabled = False` 不响应输入**：与全库一致，禁用时不触发点击 / 键盘 / 滚轮驱动的事件。
- **你设的 `Cursor` 不会被吞掉**：拖放反馈（`crDrag` / `crNoDrop`）与列分隔线提示（`crHSplit`）都只是**临时借用** `Cursor`，手势结束后还原成你原本设的那个。以前是硬还原成 `crDefault`——给树设了 `crHandPoint`，只要在分隔线上划过一次就永久没了。
- **五个事件同时是子类的重写点**：`OnGetText` / `OnInitNode` / `OnExpanding` / `OnGetImageIndex` / `OnChange` 各有一个 protected 虚方法（`DoGetText` / `DoInitNode` / `DoExpanding` / `DoGetImageIndex` / `DoTreeChange`），默认实现就是"发这个事件"。像 [`TTyShellTreeView`](shelltreeview.md) 这样自带行为的子类**重写虚方法**而不是抢占事件槽，因此应用照常可以挂这些事件，不会把子类的行为顶掉（重写里调 `inherited` 即可两者兼得）。
- **DFM / LFM 序列化**：声明了 `default` 的属性（`Options=[]`、`NodeDataSize=-1`、`DefaultNodeHeight=18`、`RootNodeCount=0`、`Indent=16`、`ShowButtons/ShowTreeLines/ShowRoot/ToggleOnDblClick=True`、`HotTrack=False`、`SearchTimeout=1000`、`ScrollBars=ssBoth`、`AutoExpand=False`、`RightClickSelect=True`、`HideSelection=True`、`ShowSeparators=False`、`TabStop=True`）等于默认值时不写入文件。`Header` / `Columns` 作为子对象随控件流式保存（列类已在单元 `initialization` 中 `RegisterClass`）。
- **内嵌滚动条是私有的**：`VScroll` / `HScroll` 只读可访问（供测试 / 布局），不暴露 `OnScroll`，且不做缓动动画。应监听宿主树自身的事件。
