# TTyTreeView

## 1. 概述

`TTyTreeView` 是 TyControls 库中的**虚拟树控件**，继承自 `TTyCustomControl`。它借鉴 VirtualTreeView 的架构：节点不是常规对象树，而是紧凑的 `TTyTreeNode` 记录链，**按需（懒惰）初始化**——控件只知道每层有多少节点，节点的文本 / 图标 / 子节点数量全部通过事件在真正需要绘制时才计算。因此它能在恒定内存下承载百万级节点。典型用途：文件资源管理器、多列数据表、带复选框 / 单选钮的层级列表、可拖拽重排的分组树。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.TreeView`（列 / 表头模型在 `tyControls.TreeView.Columns`） |
| `GetStyleTypeKey` 返回值 | `'TyTreeView'` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |

在 `.tycss` 文件中，控件外框对应选择器前缀 `TyTreeView`。此外控件在绘制时还会解析若干**子部件 typeKey**（均不是独立控件，只是主题查找键）：`TyTreeNode`（行）、`TyTreeHeader`（表头带）、`TyTreeHeaderSection`（表头分区）、`TyTreeCheckBox`（复选 / 单选框槽）。详见第 5 节。

```pascal
uses tyControls.TreeView, tyControls.TreeView.Columns;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Options` | `TTyTreeOptions` | `[]` | 树级功能开关集合（见下表），默认全部关闭 |
| `Header` | `TTyTreeHeader` | 见下 | 表头 / 列模型子对象（`TPersistent`，随控件流式保存） |
| `NodeDataSize` | `Integer` | `-1` | 每个节点尾部附带的用户数据块字节数；`-1` 表示无数据块。设置后每个节点分配 `TreeNodeSize + NodeDataSize` 字节 |
| `DefaultNodeHeight` | `Integer` | `18` | 未启用变高时每行的逻辑像素高度 |
| `RootNodeCount` | `Cardinal` | `0` | 根级（顶层）节点数量。写入即创建这么多未初始化的根节点骨架 |
| `Indent` | `Integer` | `16` | 每一层的缩进逻辑像素 |
| `Images` | `TImageList` | `nil` | 主列节点图标的图像列表，配合 `OnGetImageIndex` 使用 |
| `EmptyListMessage` | `string` | `''` | 树为空时在内容区居中显示的提示文字 |
| `ShowButtons` | `Boolean` | `True` | 是否绘制展开 / 折叠按钮（±方块） |
| `ShowTreeLines` | `Boolean` | `True` | 是否绘制连接父子节点的树状连线 |
| `ShowRoot` | `Boolean` | `True` | 根节点是否显示展开按钮 / 缩进（`False` 时根节点平铺无缩进） |
| `ToggleOnDblClick` | `Boolean` | `True` | 双击一行是否展开 / 折叠该节点 |
| `HotTrack` | `Boolean` | `False` | 是否高亮鼠标悬停行（`:hover` 状态） |
| `SearchTimeout` | `Integer` | `1000` | 键入查找（type-to-find）缓冲区空闲多少毫秒后自动重置 |
| `TabStop` | `Boolean` | `True` | 是否参与键盘 Tab 焦点循环 |

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

#### `Header`（`TTyTreeHeader`）子对象属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Height` | `Integer` | `22` | 表头带高度 |
| `Columns` | `TTyTreeColumns` | 空集合 | 列集合（`TCollection`）；`Columns.Add` 追加一个 `TTyTreeColumn` |
| `MainColumn` | `Integer` | `0` | **主列**（绘制展开按钮 / 图标 / 树缩进的那一列）。见下方警告 |
| `SortColumn` | `Integer` | `-1` | 当前排序列（`-1` = 未排序）；点击表头自动更新 |
| `SortDirection` | `TTySortDirection` | `sdAscending` | 当前排序方向 |
| `AutoSizeIndex` | `Integer` | `-1` | 自动填充剩余宽度的列索引（配合 `hoAutoResize`） |
| `Images` | `TCustomImageList` | `nil` | 表头图标图像列表 |
| `Options` | `TTyTreeHeaderOptions` | `[hoVisible, hoColumnResize, hoShowSortGlyphs, hoHeaderClickAutoSort, hoDrag]` | 表头选项（见下） |

> **⚠️ 关键陷阱：`MainColumn` 必须在列添加之后设置。** `SetMainColumn` 在 `Columns.Count = 0` 时会把任何赋值**夹紧为 `NoColumn`（-1）**。若在添加任何列之前写 `MainColumn := 0`，它会被夹成 -1，导致主列块永远不匹配——展开按钮、节点图标、主列文字**全部消失**，只剩平铺文本格。**正确顺序是先 `Columns.Add`，再设 `MainColumn`。** 作为兜底，控件在**添加第一列**且 `MainColumn` 仍为 `NoColumn` 时会自动把它默认为 `0`（与 VirtualTreeView 一致）；但显式的错误顺序仍应避免。示例（来自 showcase）：
>
> ```pascal
> with ColTree.Header do
> begin
>   Columns.Add;  Columns.Add;  Columns.Add;  Columns.Add;  // 先加 4 列
>   MainColumn := 0;                                        // 再设主列
> end;
> ```

#### `Header.Options`（`TTyTreeHeaderOption`）

| 标志 | 作用 |
|------|------|
| `hoVisible` | 在节点区上方绘制表头带 |
| `hoColumnResize` | 允许拖动列分隔线调整列宽 |
| `hoShowSortGlyphs` | 在排序列显示排序三角字形 |
| `hoHeaderClickAutoSort` | 点击表头分区触发 `SortTree` |
| `hoDrag` | 允许拖动列头重排列顺序 |
| `hoAutoResize` | 令 `AutoSizeIndex` 列填充剩余宽度 |
| `hoHotTrack` | 高亮悬停的表头分区 |

#### `TTyTreeColumn`（列项）自有 published 属性

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
| `Options` | `TTyTreeColumnOptions` | `[coVisible, coResizable, coAllowClick, coDraggable]` | 列级选项（`coVisible` / `coResizable` / `coAllowClick` / `coDraggable` / `coAutoSpring`） |
| `Tag` | `NativeInt` | `0` | 用户自定义标记 |

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
| `OnGetImageIndex` | `TTyTreeGetImageIndexEvent` | 取节点图标索引（带 `Kind` + `Column` + `var Ghosted`） |
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

### 节点拖放

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnDragOver` | `TTyTreeDragOverEvent` | 拖拽过程中的逐目标 / 逐模式否决；`Allowed` 入参为 `CanMoveNode(...)` 结果，handler **只能进一步收紧**（对无效移动设 `Allowed := True` 仍被 `MoveNode` 的硬闸拦下） |
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
| `TyTreeHeaderSection` | `:hover` / `:selected` | 悬停 / 当前排序的表头分区 |
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

---

## 6. 代码示例

下例镜像 showcase 中「Columns + Sort」页的用法：多列 + 数据在节点 + 稳定排序 + 就地编辑 + 图标。

```pascal
uses
  tyControls.Controller, tyControls.TreeView, tyControls.TreeView.Columns;

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
  (Columns.Add as TTyTreeColumn).Text := 'Name';
  (Columns.Add as TTyTreeColumn).Text := 'Size';
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

## 7. 注意事项

- **`MainColumn` 必须在列添加之后设置**（本文档最重要的陷阱）：`Columns.Count = 0` 时 `SetMainColumn` 把值夹紧为 `NoColumn(-1)`，主列块永不匹配 → 展开按钮 / 图标 / 主列文字全部消失。控件仅在**添加第一列时**自动把 `NoColumn` 兜底为 `0`；显式错误顺序仍会出问题。删除列时控件会自动跟随重编号修正 `MainColumn`。
- **虚拟 = 数据在你手里，不在树里**：树本身不存文本 / 图标 / 子节点。文本经 `OnGetText` / `OnGetTextWithType` 现算；子节点数经 `OnInitChildren` 现算。持久数据放进节点数据块（`NodeDataSize` + `GetNodeData`），**不要**用 `Node^.Index` 作为持久 key——排序会重新戳 `Index`，稳定 key 必须存在数据块里。
- **三阶段懒惰初始化**：① `RootNodeCount :=` 创建根节点骨架（未初始化）；② 首次需要一个节点时 `InitNode` 触发 `OnInitNode`，app 声明 `ivsHasChildren` / `ivsExpanded` / `ivsSelected`；③ 展开一个声明了有子节点的节点时 `InitChildren` 触发 `OnInitChildren` 物化子节点。恒定内存直到用户实际展开。
- **变高节点**：`toVariableNodeHeight` + `OnMeasureItem` 才生效；测量在 `InitNode` 末尾进行一次。未启用时每行都用 `DefaultNodeHeight`。
- **`OnDragOver` 只能收紧不能放宽**：`CanMoveNode` 是硬闸（非空、模式非 `dmNone`、目标不在源子树内、非空操作等），对无效移动即便 handler 设 `Allowed := True` 也会被 `MoveNode` 拦下。
- **`OnAfterCellPaint` 与 `OnDrawNode` 的裁剪时机**：二者都在 BGRA 图层合成到画布**之后**触发（跨平台后处理路径）。因此没有「在默认文本下方绘制背景」的 `OnBeforeCellPaint`——那需要不同的绘制路径，目前未实现。
- **`toCheckSupport` 是复选框总开关**：未加入 `Options` 时，即使给节点设了 `CheckType`，`ToggleCheck` 也直接返回、不绘制复选槽。三态自动传播还额外需要 `toAutoTristateTracking`。
- **单选 vs 多选事件**：单选走 `OnChange`（`FSelectedNode` 变化）；多选走 `OnSelectionChanged`（每次手势后一次）。二者是不同的通道。
- **`Enabled = False` 不响应输入**：与全库一致，禁用时不触发点击 / 键盘 / 滚轮驱动的事件。
- **DFM / LFM 序列化**：声明了 `default` 的属性（`Options=[]`、`NodeDataSize=-1`、`DefaultNodeHeight=18`、`RootNodeCount=0`、`Indent=16`、`ShowButtons/ShowTreeLines/ShowRoot/ToggleOnDblClick=True`、`HotTrack=False`、`SearchTimeout=1000`、`TabStop=True`）等于默认值时不写入文件。`Header` / `Columns` 作为子对象随控件流式保存（列类已在单元 `initialization` 中 `RegisterClass`）。
- **内嵌滚动条是私有的**：`VScroll` / `HScroll` 只读可访问（供测试 / 布局），不暴露 `OnScroll`，且不做缓动动画。应监听宿主树自身的事件。
