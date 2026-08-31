# TTyTreeSelect

## 1. 概述

`TTyTreeSelect` 是 TyControls 库中的主题化「树形下拉选择」控件，继承自 `TTyCustomControl`（**窗口化**控件，有自己的句柄，能取焦点）。它是一个**长得像组合框的字段**，但下拉出来的是一棵**真正的 `TTyTreeView`**：在一行的高度里，从**层级结构**中选出一个值。

**它补的是哪个缺口：** 本库既有树、也有组合框，但**没有两者的结合**。一个「选部门 / 选分类 / 选目录」的表单行此前只能每次手工拼——组合框显示不出结构，而树是一整块满高面板，塞不进一行。典型用途：部门 / 组织架构选择、分类目录选择、文件夹选择、任何「候选值本身是一棵树」的表单字段。

**它是组合（composition），不是重新实现。** 两个久经考验的部件被接在一起，且**都没有被复制**：

- `TTyDropdownPopup`（`tyControls.Popup`）——无边框弹出窗口：下弹/上翻定位、圆角窗口区域、Qt/Wayland 变通、失活关闭、重开竞态 tick。`TTyComboBox` 与 `TTyDateTimePicker` 用的是同一个 helper。
- `TTyTreeView`——就是那个真控件，以公开的 `Tree` 属性暴露出来，宿主像用一棵独立的树那样建节点、答 `OnGetText`。

本单元只添加两者都没有的东西：**一个把选中项画出来的字段**，以及**把「某个节点被点了」翻译成「某个值被选了」的规则**。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.TreeSelect` |
| 基类 | `TTyCustomControl`（→ `TCustomControl`），**窗口化** |
| `GetStyleTypeKey` 返回值 | **`'TyComboBox'`**（故意不是自己的键——见下方）。字段本体：`background` / `border-*` / `color` / `font-*` / `padding` / `opacity` / `outline` |
| 下拉内容 typeKey | `'TyTreeView'`（连同 `TyTreeNode` 等——那是**树自己的**键，本控件不插手） |
| 空字段提示 typeKey | `'TyTextHint'`（全库通用的提示墨色，与 `TTyEdit.TextHint` 同键同色） |
| 默认尺寸 | 145 × 26（逻辑像素，构造时设置——**就是 `TTyComboBox` 的尺寸**） |
| 新增令牌 | `--treeselect-drop-height`（见 6.3） |

```pascal
uses tyControls.TreeSelect;
```

**为什么是窗口化控件（有句柄）？** 与同批的 `TTyTag` / `TTyAlert` 相反，也与 `TTyComboBox` 一致：它要**取焦点**，`Alt+Down` / `F4` 要能展开、`Escape` 要能收起——图形控件没有句柄，这些**一件都做不到**。

**为什么 typeKey 是 `'TyComboBox'`，而不是自己的键？** 因为**它就是一个组合框字段**：同样的边框、同样的 `padding`、同样的 chevron 区，坐在与真组合框同一个表单行里；而整个组合框家族（`TTyColorBox` / `TTyCheckComboBox` / `TTyComboBoxEx` / `TTyMRUComboBox`…）本来就靠继承共用这一个键。复用它意味着 **TreeSelect 落地当天就被每一个皮肤主题化**——不用改任何 `.tycss`，也**不可能**出现「控件没被主题定义」的裸奔。代价见 6.4 与第 8 节第一条。

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `TextHint` | `string` | `''` | **没有任何选中项时**，字段以 `TyTextHint` 的墨色绘制的占位文字。**选中节点的空标题不算空状态**，不会把它召回来（见 5.1 的 `TyTreeSelectFieldText`）。 |
| `DropDownWidth` | `Integer` | `0` | 下拉窗口宽度，**逻辑像素**；`0`（默认）= 与字段同宽。写入负数会被**归一化为 `0`**（「跟随字段」只有一种写法）。 |
| `DropDownHeight` | `Integer` | `0` | 下拉窗口高度，**逻辑像素**；`0`（默认）= 用主题的 `--treeselect-drop-height`。负数同样归一化为 `0`。 |
| `TabStop` | `Boolean` | `True`（构造时设置，且 `default True`） | 可用 Tab 聚焦。 |

改 `DropDownWidth` / `DropDownHeight` **不会**实时改变已经打开的下拉：尺寸在**打开的那一刻**决定，在用户指针底下把窗口缩放一遍比「下次展开再生效」更糟。

### 继承的通用成员

`TTyTreeSelect` 继承自 `TTyCustomControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | **变体入口**。因为字段解析的是 `'TyComboBox'`，所以这些就是**组合框的变体**——`TyComboBox.small` 会把 TreeSelect 和 ComboBox **打扮得一模一样**，这正是共用键的意义。 |
| `StyleOverride` | `string` | `''` | 单实例内联 CSS 声明块（可引用 `var(--...)` 令牌）。 |
| `Controller` | `TTyStyleController` | `nil`（用全局 `TyDefaultController`） | 指定样式控制器。**重新赋值时会一并同步给内部的树和弹出 helper**，否则树会一直留在旧主题上直到下次展开。 |

另暴露 `Align` / `Anchors` / `Enabled` / `Font`。

### 公开（非 published）属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `Tree` | `TTyTreeView`（只读） | **面向宿主的主战场**：在它上面建层级（`AddChild` / `RootNodeCount` / `OnInitChildren`）、答 `OnGetText`、设 `Options` / `Images` / `Indent`。本身不是 published（虚拟树的节点是指针），**设计期填树请用下面的 `Items`**。 |
| `Items`（published） | `TTyTreeNodes` | 下拉树的**设计期条目模型**，转发到内嵌树：**双击控件**（或右键「编辑节点...」）打开与 `TTyTreeView` 同一个节点结构编辑器,填好的树随 `.lfm` 流式保存。填了 `Items` 即进入条目模式;留空则维持经典的虚拟 API 路径（代码里 `RootNodeCount`/`OnGetText`）——两条路互斥,混用会由树自己的闸门报错。 |
| `SelectedNode` | `PTyTreeNode`（读写） | 选中的节点，或 `nil`。**写它 = 程序化选取**：`Text` 重新缓存、`OnChange` 触发，但**下拉不会关**，树也**不会被动到**，直到它下次展开（见 `SyncTreeToSelection`）。**这个指针是宿主的**：把节点从树里删掉，它就悬空——和宿主自己持有的任何 `PTyTreeNode` 完全一样，请先清空或改设。 |
| `Text` | `string`（**只读**） | 选中项的标题；无选中项时为 `''`。只读是**有意的**：这里的值是一个**节点**——文字只是它的样子，不是它本身，写一个标题命名不了任何节点。 |

---

## 4. 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TNotifyEvent` | 选中项**真的变了**——用户选取，或宿主写 `SelectedNode`。**重复选同一个节点不触发**（setter 先比较）。`UpdateText`（仅标题变了）**不触发**。 |
| `OnDropDown` | `TNotifyEvent` | **在弹出窗口显示之前**触发——**与 `TTyComboBox` 相反**（它是显示之后）。理由：树是本库唯一一种「内容经常按需现建」的下拉，这个钩子**必须**能在尺寸还没定下来之前（重新）填充 `Tree`。控件在它之后才 `SyncTreeToSelection`，所以**刚建好的树也能开在当前值上**。 |
| `OnCloseUp` | `TNotifyEvent` | 下拉关闭之后——**任何原因**都算：点击别处、`Escape`、选取、程序调用 `CloseUp`。无窗口（headless / 已关闭）时也照样触发，宿主两种路径看到的事件序列一致。 |

---

## 5. 关键成员

### 5.1 纯几何 / 纯规则函数（单元级，可无句柄直接调用）

全部是整数 / 字符串 / 枚举入参，无控件状态、无句柄依赖，测试直接调用（`tests/test.treeselect.pas`）。

```pascal
type
  { 字段几何，DEVICE 像素，相对控件矩形左上角 }
  TTyTreeSelectLayout = record
    TextRect: TRect;     // 选中项（或提示）的绘制带；空 => 什么都不画
    ButtonRect: TRect;   // 右侧 chevron 区；仅当没给宽度时才为空
  end;

function TyTreeSelectFieldLayout(AClientWidth, AClientHeight, APadLeft, APadTop,
  APadRight, APadBottom, AButtonWidth: Integer): TTyTreeSelectLayout;

function TyTreeSelectDropSize(AFieldWidth, ADropWidth, ADropHeight,
  ADefaultHeight: Integer): TSize;

function TyTreeSelectFieldText(AHasSelection: Boolean; const ANodeText, ATextHint: string;
  out AIsHint: Boolean): string;

function TyTreeSelectCommitsOn(APart: TTyTreeHitPart; AFullRowSelect: Boolean): Boolean;

function TyTreeSelectNodeText(ATree: TTyTreeView; ANode: PTyTreeNode): string;
```

**`TyTreeSelectFieldLayout`** —— 字段的排布：

- **chevron 区最先服务**：它是「这东西能展开」的**唯一提示**（沿用 `TyTagLayout` 给自己 `x` 槽位的规矩）。它是**贴右边缘、占满整个高度**的竖条（**不**被 `padding` 内缩——chevron 自己在区内居中）。
- 文字带 = 字段按 `padding` 内缩，再**右夹到 chevron 区的左边缘**。
- **chevron 区就是右侧的水槽**：所以**宽 chevron 会覆盖主题的右 `padding`，而不是与之相加**；反过来，`AButtonWidth = 0` 时才轮到主题的右 `padding` 收住文字。
- 字段窄到放不下两者：**chevron 保留**（区被夹到左边缘 `0`），**文字带塌缩为空**——「打不开的字段」比「没有文字的字段」更糟。
- `padding` 吃掉整个字段 → 无文字带，**但 chevron 仍在**；宽或高 ≤ 0 → 两个矩形都为空。**绝不出现反向矩形**。

> 这正是 `TTyComboBox.RenderTo` 内联做的事；这里抽成**一个函数**，于是绘制与命中检测**不可能漂移**。

**`TyTreeSelectDropSize`** —— 下拉窗口尺寸（DEVICE 像素）：

- `ADropWidth <= 0` → **跟随字段宽度**。默认跟随，是因为「下拉与字段对齐」才让两者读起来像**同一个部件**；需要展示很深缩进的宿主再自己指定更宽的。
- `ADropHeight <= 0` → 用 `ADefaultHeight`（即解析出的 `--treeselect-drop-height`）。
- **两轴都下限为 1**：弹出的必须是一个窗口，不是一条缝。

**`TyTreeSelectFieldText`** —— 字段说什么，以及那是不是提示：

- **有选中项 → 显示它的标题，哪怕是空标题**，且 `AIsHint = False`。标题为空的节点**仍然是一个被选中的节点**，在它上面显示「请选择…」是**在谎报控件状态**。
- 无选中项 → 显示 `ATextHint`，`AIsHint := ATextHint <> ''`（**没设提示 = 空字段，不是「把空提示画得灰灰的」**）。

> 这条规则正是它与**长得一模一样的** `TTyEdit.TextHint` 的分野：编辑框没有「选中项」这回事，所以对它而言**空文字就是空状态**。这里的提示严格地只表示「什么都没选」。

**`TyTreeSelectCommitsOn`** —— 点在节点的哪个部位才算「选定这个值」：

| `APart` | 提交？ | 理由 |
|---------|--------|------|
| `hpLabel` / `hpImage` | ✅ 总是 | 树自己就在这两处选中 |
| `hpIndent` | 仅当 `AFullRowSelect`（树处于 `toFullRowSelect`） | 镜像树自己的规则：不开整行选中时，裸缩进本就不是一次选中命中 |
| `hpButton`（展开箭头） | ❌ 从不 | **展开一个分支去看看里面，绝不能等于选中它并「啪」地关掉下拉** |
| `hpCheckBox` | ❌ 从不 | 复选框拥有自己的手势 |
| `hpNowhere` / `hpHeaderSection` / 其余 | ❌ 从不 | 压根不是节点 |

> 它**镜像 `TTyTreeView` 自己的选中规则**，所以选择器**永远不会**提交一个树没有选中的节点（也不会拒绝一个树选中了的）。`case` 的 `else` 分支是**兜底**：将来往 `TTyTreeHitPart` 里加新部位，默认是「不提交」——一个悄悄选中了值的新部位是更坏的 bug。

**`TyTreeSelectNodeText`** —— 通过**树自己的**文字事件读取节点主列标题：优先 `OnGetTextWithType`（`Header.MainColumn`，`ttNormal`），否则 `OnGetText`。这**正是 `TTyTreeView.RenderTo` 画那一行时走的路**，所以字段显示的字与弹出行显示的字**一模一样**。对 `nil` 树 / `nil` 节点 / 隐藏根 / 什么文字都不答的树，一律返回 `''`。

### 5.2 公开方法

```pascal
procedure DropDown;               // 展开。Enabled=False / 已展开 / 距上次 CloseUp 200ms 内 => 空操作
procedure CloseUp;                // 收起（幂等）。触发 OnCloseUp
function  DroppedDown: Boolean;
procedure PickNode(ANode: PTyTreeNode);  // 提交 ANode 为选中值：选中它（值真变了才 OnChange）并收起下拉
procedure ClearSelection;         // 清空选中：Text 变空，TextHint（若有）接管
procedure UpdateText;             // 重新读取当前选中节点的标题到 Text。不触发 OnChange
function  DropDownSize: TSize;    // 本字段 PPI 下下拉窗口的 DEVICE 像素尺寸——即 DropDown 将要请求的尺寸
```

- **`PickNode` 是公开的**：点击 / 回车在弹出里跑的就是它，宿主也可以从快捷键或右键菜单驱动同一个手势。
- **`UpdateText` 什么时候用**：树对**当前选中项**答的文字变了（宿主把节点改名了）。**不触发 `OnChange`**——**值没变，只是它的标签变了**。
- **`DropDownSize` 是公开的**：宿主可能想知道，而且它是尺寸规则被测试穿过的**接缝**（打开一个真窗口不是 headless 行为）。

---

## 6. 状态与主题

### 6.1 支持的伪类状态

字段解析 `'TyComboBox'` 并带上本控件的 `StyleClass`；`:hover` / `:active` / `:focus` / `:disabled` 全部由基类状态机计算。下拉里的树用**它自己的** `TyTreeView` / `TyTreeNode` 状态，本控件不插手。

弹出窗口的**圆角形状**在每次展开时按**树自己解析出的 `border-radius`** 塑形（`FPopup.CornerRadiusLogical := treeStyle.BorderRadius`），所以窗口的角与树画进这些角里的填充是**对齐的**——`TTyComboBox` 用它列表的圆角做同样的事。

### 6.2 主题令牌摘要

字段（**这才是本控件真正解析的键**，`themes/light.tycss`）：

```css
TyComboBox {
  background: var(--input-bg);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: var(--input-border-width);
  border-radius: var(--radius);
  padding: 4px;                        /* 决定文字带；右侧被 chevron 区覆盖 */
  font-size: var(--font-size-base);
}
TyComboBox:hover    { border-color: var(--input-border-hover); }
TyComboBox:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }
TyComboBox:disabled { opacity: var(--disabled-opacity); }
```

下拉内容（树自己的键，本控件不插手）：

```css
TyTreeView { background: var(--input-bg); color: var(--on-surface); border-color: var(--border);
             border-width: var(--input-border-width); border-radius: var(--radius);
             padding: 2px; font-size: var(--font-size-base); }
TyTreeNode { background: none; color: var(--on-surface); }
TyTreeNode:hover    { background: var(--surface-hover); }
TyTreeNode:selected { background: var(--accent); color: var(--on-accent); }
```

空字段提示（全库通用键）：

```css
TyTextHint { color: var(--muted); }
```

### 6.3 可调尺寸令牌（v3/C 约定）

| 令牌 | 内置默认（逻辑像素） | 作用 |
|------|------|------|
| `--treeselect-drop-height` | `220`（= `TyTreeSelectDropHeight`，令牌名常量为 `TyTreeSelectDropHeightVar`） | 宿主未指定 `DropDownHeight` 时，下拉窗口的高度 |

这是本单元**唯一**的 `Metric()` 调用。**注意：目前没有任何随库发布的主题声明这个令牌**（`themes/*.tycss` 与 `DefaultTheme` 里都没有），所以除非宿主 / 皮肤自己写上，它**总是**回落到内置的 `220`。

> **为什么是「高度」而不是像 `TTyComboBox.DropDownCount` 那样的「行数」？** 因为树的行会随分支展开 / 收起而出现和消失——「8 行高」意味着**每展开一次就在用户指针底下把窗口缩放一遍**。树的下拉是一个**固定视口**，靠滚动。

`chevron 区宽度`**不是**主题令牌：它是共享常量 `TyFieldButtonWidth = 18`（`tyControls.Types`，逻辑像素），`TTyComboBox` / `TTySpinEdit` / `TTyDateTimePicker` / `TTyCascader` 用的是同一个——这正是这些字段的 chevron 能在一个表单里对齐的原因。想改它请改那个常量（会同时影响全部字段），控件本身没有暴露它。

### 6.4 未定义时如何降级

`RenderTo` 严格遵守「**降级，绝不崩溃，绝不发明颜色**」：

| 情形 | 行为 |
|------|------|
| `TyComboBox` 解析不出 `background` | **整个字段什么都不画**（画布原样不动），而不是画一个硬编码的字段。 |
| 有 `background` 但解析不出 `color` | 画出边框层（`DrawFrame`：背景 + 边框 + 阴影 + 不透明度 + 焦点环），**但文字和 chevron 都不画**——两者都得凭空发明墨色。边框仍然告诉用户「字段在这」。 |
| `TyTextHint` 解析不出 `color` | 提示**改用字段自己的 `color`**（更淡当然更好看，但发明一个灰色不是选项）。**不会**回退到任何硬编码颜色，也**不会**消失。 |

> 注意「有规则但没给 `background`」也算未定义：给某个 typeKey 写了规则却不给底色，会**压制内置层**对该键的全部贡献（`TTyStyleModel.UserHasTypeKey`），字段于是真的解析不出填充。

---

## 7. 代码示例

```pascal
uses tyControls.Controller, tyControls.TreeView, tyControls.TreeSelect;

TyDefaultController.LoadTheme('themes/light.tycss');

// —— 建字段（.lfm 里放控件，代码里填树）——
procedure TForm1.FormCreate(Sender: TObject);
var
  Root, N: PTyTreeNode;
begin
  DeptSelect.TextHint := '请选择部门';

  // NodeDataSize 决定分配步长，必须在任何 AddChild 之前设置
  DeptSelect.Tree.NodeDataSize := SizeOf(Integer);
  DeptSelect.Tree.OnGetText := @TreeGetText;

  Root := DeptSelect.Tree.AddChild(nil);           // 「技术中心」
  PInteger(DeptSelect.Tree.GetNodeData(Root))^ := 0;
  N := DeptSelect.Tree.AddChild(Root);             // 「后端组」
  PInteger(DeptSelect.Tree.GetNodeData(N))^ := 1;

  DeptSelect.OnChange := @DeptChanged;
end;

// 树答文字的路径 —— 字段显示的就是这里给出的字
procedure TForm1.TreeGetText(Sender: TTyTreeView; Node: PTyTreeNode; var Text: string);
begin
  Text := FDeptNames[PInteger(Sender.GetNodeData(Node))^];
end;

procedure TForm1.DeptChanged(Sender: TObject);
begin
  StatusLabel.Caption := '已选：' + DeptSelect.Text;   // Text 只读，取的是缓存的标题
end;
```

按需现建的树（`OnDropDown` 在窗口显示**之前**触发，正是为此）：

```pascal
procedure TForm1.DeptSelectDropDown(Sender: TObject);
begin
  if DeptSelect.Tree.RootNodeCount = 0 then
    LoadDepartmentsInto(DeptSelect.Tree);   // 尺寸尚未定下，此时填充刚好
end;
```

给深层级更宽的下拉，并让皮肤之外的这一个实例更矮：

```pascal
DeptSelect.DropDownWidth  := 320;   // 逻辑像素；0 = 与字段同宽
DeptSelect.DropDownHeight := 160;   // 逻辑像素；0 = 主题的 --treeselect-drop-height
```

---

## 8. 注意事项

- **主题里的 `TyTreeSelect` 规则块是「死」的（重要陷阱）：** `themes/light.tycss` 曾经声明过一个 `TyTreeSelect { … }` 块（3.0 起已删除，原处只留一条解释性注释），但本控件的 `GetStyleTypeKey` 返回的是 **`'TyComboBox'`**，**永远不会去解析 `TyTreeSelect`**（`tests/test.treeselect.pas` 的 `TestTypeKeyIsComboBox` 就钉死了这一点）。之所以一直没被发现，是因为那个块的内容与 `TyComboBox` 块**逐条相同**，改不改都看不出差别。**后果：想把树形选择器与普通组合框在视觉上区分开、于是去改 `TyTreeSelect { … }` 的主题作者，会发现毫无效果**——请改 `TyComboBox`（会同时影响整个组合框家族），或用 `StyleClass` / `StyleOverride` 给这一个实例上妆。那个块已经删掉了，所以现在**连找都找不到**——`TyTreeSelect` 是一个纯粹的死名字，写进主题不会被任何代码解析。
- **变体是组合框的变体：** 因为共用 `'TyComboBox'` 键，`StyleClass := 'small'` 命中的是 `TyComboBox.small`——TreeSelect 与 ComboBox 会被**打扮得完全一样**。这是共用键的**目的**，也是它的**代价**。
- **`Text` 是选中时缓存的，绘制时绝不解引用节点：** 节点指针是宿主的，宿主随时可以释放（`TTyTreeView` 是虚拟树），绘制时再去读一个已删节点，会变成每次 `Invalidate` 都悬空读。所以**宿主背着控件改了标题，字段不会自己知道**——改完请调 `UpdateText`。
- **`SelectedNode` 会悬空：** 把节点从树里删掉，这个指针就悬空了，和宿主自己持有的任何 `PTyTreeNode` 一样。**删之前先 `ClearSelection` 或改设**。
- **`Tree` 不是 published;设计期填树用 `Items`（转发到内嵌树,随 `.lfm` 流式）,运行时动态树走虚拟 API：** 两条路互斥。
- **仓库老坑——给树加列时，`Header.MainColumn` 必须在 `Columns.Add` 之后设：** 先设会被夹到 `NoColumn`，主列**永远不画**。
- **展开分支 ≠ 选中它：** 点展开箭头和点复选框**都不提交**（见 `TyTreeSelectCommitsOn`）——否则「展开看看里面」就会顺手选中并关掉下拉。
- **只有 `Alt+Down` / `F4` 展开，没有单独的上下键步进：** 后者是组合框的做法。**层级没有一个「下一个值」可供盲目步进**，而且从收起的字段步进到一个折叠分支里，会选中用户根本看不见的节点。`Escape` 收起（不提交）。
- **每次展开都会用字段的选中项重新播种树：** 所以下拉**总是开在当前值上**（哪怕这个值是程序化设置的、从未碰过树）；反过来，一次被取消的浏览（方向键动过树自己的选中）也会**在下次展开时被抹掉**，不会漏进字段。选中项为 `nil` 时会**清空树的选中**——弹出里不能高亮一个字段并不认的行。
- **200ms 重开保护：** 下拉在本控件的 `Click` 跑起来**之前**就已经因失活而关闭了，`Click` 会看到一个已关闭的弹出并把它**重新打开**。`DropDown` 因此忽略距上次 `CloseUp` 200ms 内的请求。整个字段都是展开热区（没有像 `TTyComboBox.csDropDown` 那样需要保护的可编辑区）。
- **选取后是「延迟」关闭的：** `PickNode` 用 `Application.QueueAsyncCall` 收起。在树的鼠标/键盘处理器里**同步**隐藏弹出，会让 LCL 的点击收尾焦点路径指向一个已隐藏的窗体（`EInvalidOperation '[TCustomForm.SetFocus] … Can not focus'`）。
- **`DropDownWidth` / `DropDownHeight` 与令牌都是逻辑像素**，弹出窗口要的是**设备像素**——控件按 `Font.PixelsPerInch` 换算。但**宽度跟随字段时不再缩放**：`Width` 本来就已经是设备像素了，缩放两遍是 bug。
- **改下拉尺寸不影响已打开的下拉：** 尺寸在展开的那一刻决定。
- **树归控件所有，只是被「寄养」进弹出窗体：** `TTyDropdownPopup.SetContent` 只做 `Parent`（`alClient`），**不转移所有权**，所以析构时窗体和树可以各自独立释放。
