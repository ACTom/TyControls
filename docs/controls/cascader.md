# TTyCascader

## 1. 概述

`TTyCascader` 是**级联选择器**：一个 combo 样式的字段，点开后落下一块**多列面板**。在第 N 列选一项，就展开第 N+1 列（那一项的子选项）；选到**没有子项**的那一项即为一次完整选择——**提交并关闭**。经典的「省 / 市 / 区」字段。

它填补的缺口很具体：`TTyComboBox` 只能从**一张平表**里挑一行；`TTyTreeView` 能展示层级，但它不是字段。两者都表达不了「在一个字段大小的控件里，选出穿过层级的**一条路径**」——而地址 / 分类 / 组织架构选择器要的正是这个。

**值是一条路径**：`TTyCascaderPath = array of Integer`，每层一个子项下标，`[1, 0, 3]` 表示「根选项 1 → 它的子项 0 → 再下一层的子项 3」，`[]` 表示未选。`Text` 就是这些节点的 `Caption` 按 `Separator` 拼起来的串。

**草稿（draft）与值（value）是分开的**：面板编辑的是**草稿路径**，只有落在**叶子**上的选择才会改动字段的 `Path`（Ant Design 的规则）。所以浏览到「华东 → 浙江」后直接关掉弹窗，已提交的值原封不动，字段不会被卡在半截的 `'华东 / 浙江'` 上。

典型用途：省市区地址、商品分类、组织单元、多级筛选。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Cascader` |
| 基类 | `TTyCustomControl`（窗口化，可取焦点、吃按键） |
| `GetStyleTypeKey` 返回值 | `'TyCascader'`（闭合的**字段**：表面 / 边框 / 焦点环 / 文字 / chevron 笔色 / `padding`） |
| 面板 typeKey | `'TyCascaderPanel'`（浮动的**多列面板**：popup 层级的 `background` / `border-*` / `border-radius` / `padding`，且它的 `border-color` 就是**列间分隔线**的颜色） |
| 行 typeKey | `'TyCascaderItem'`（一列里的**一行**：`:selected` / `:hover` / `:disabled` 才是面板可读的原因，同 `TySegmented` → `TySegmentedItem` 的关系） |
| 默认尺寸 | 145 × 26（逻辑像素，构造时设置——**与 `TTyComboBox` 同尺寸**，两者要能排在同一列表单里） |
| 新增 token | `--cascader-column-width` / `--cascader-row-height` / `--cascader-expand-size` / `--cascader-expand-gap` / `--cascader-button-width`（见第 6 节） |

```pascal
uses tyControls.Cascader;
```

**为什么是三个 typeKey？** 字段有自己的键、不借用 `'TyComboBox'`——它不是 combo（模型是树，不是 `TStringList`），且本库每个字段控件都按惯例持有自己的键。面板是**另一块表面**：它浮在窗体之上，主题要给它 popup 的立体感（圆角 / 边框 / 阴影）。行则需要独立的状态。

---

## 3. 数据模型

选项树是一棵普通的 `TCollection`——**刻意不用 `TTyTreeView` 的节点模型**：那是一套虚拟的、认列的、绑图像列表的**视图**结构，节点存在的意义就是被树画出来，离开树没有意义。级联的一个选项只需要「标题 + 子项 + 能否选中」，`TCollection` 是承载它的最简结构，**同时**又是 Lazarus 设计器和 `.lfm` 流化器**本来就会编辑与往返**的结构：嵌套 collection 递归流化，整棵选项树直接躺在 `.lfm` 里，**零自定义流化代码**。

### `TTyCascaderNode`（`TCollectionItem`）

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Caption` | `string` | `''` | 选项文字。用解析后的 `TyCascaderItem` 样式绘制（**不**读 LCL `Font.*`），并由 `Separator` 拼进字段的 `Text`。**不解析助记符**：选项不激活任何东西，`&` 就是字面字符。 |
| `Children` | `TTyCascaderNodes` | 空集合 | 本选项的子选项。为空 ⇒ 它是**叶子**。写入走 `Assign`（**不换指针**——`FChildren` 由本节点负责释放，`.lfm` 读取器也是往既有集合里写）。 |
| `Enabled` | `Boolean` | `True` | `False` 时该行变灰（`TyCascaderItem:disabled`），鼠标点不动，方向键**跨过**它。**它的子项随它一起不可达**——「穿不过一个你选不了的选项」。 |
| `Tag` | `NativeInt` | `0` | 留给宿主：数据库 id、指针大小的载荷，随便。控件从不读它。 |

`function IsLeaf: Boolean` —— 无子项即为真。**对构造期 nil 安全**：`TCollectionItem.Create` 在本类构造体跑之前就通知了它的集合，而那次通知会一路冒泡到控件，此时 `FChildren` 还没建好。

### `TTyCascaderNodes`（`TCollection`）

| 成员 | 说明 |
|------|------|
| `Items[i]` / `default` | `TTyCascaderNode`。 |
| `function Add: TTyCascaderNode` | 追加一个空选项。 |
| `function AddNode(const ACaption: string): TTyCascaderNode` | 追加一个带标题的选项——代码建树的一行式写法。 |
| `property OnChange: TNotifyEvent` | **控件只挂在根集合上**。子集合自己没有钩子：树里**任何位置**的改动都会冒泡到**根**集合并在那里触发（`DoNodesChanged`），所以第四层改一个 `Caption` 也能抵达控件的重绘。 |

---

## 4. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Nodes` | `TTyCascaderNodes` | 空 | 选项树。**在任何位置编辑它都会静默地重新校验选中值**（见 §8）并重排已打开的面板。 |
| `Separator` | `string` | `' / '`（`TyCascaderSeparator`） | `Text` 用什么把两个 `Caption` 拼起来。**这不是控件自己的文案**——控件从不发明词，只在宿主给的两个标题之间放这个串；`' / '` 是 Ant Design 的写法，中英文读起来都对。 |
| `DropDownRows` | `Integer` | `8` | 一列滚动前最多可见几行（对齐 `TTyComboBox.DropDownCount`）。**钳到至少 1**。它是个**计数、不是观感**，所以是属性，而行**高**是主题 metric。 |
| `TabStop` | `Boolean` | `True` | |
| `Align` / `Anchors` / `StyleClass` / `StyleOverride` / `Controller` | — | — | 继承自基类的通用成员。 |

`DropDownRows` **不会**热改已打开的弹窗：高度在 `DropDown` 时定死——在用户点击底下把窗口改尺寸，比等下一次打开更糟。

### public 属性 / 方法

| 成员 | 类型 / 返回 | 说明 |
|------|------|------|
| `Path` | `TTyCascaderPath` | 选中路径。**赋值会归一化**（见 `TyCascaderValidPath`）：不符合当前树的路径会被**静默**截回仍然成立的前缀——既不会被钳到相邻选项上，也不会抛异常。**是值不是别名**：读出来的是副本，写进去的也被拷贝一份（FPC 动态数组是引用计数的，但**不是** copy-on-write，直接交出 `FPath` 等于让调用方绕过 setter 改选中值）。 |
| `Text` | `string`（只读） | 选中标题按 `Separator` 拼成的串；未选时为 `''`。**只读且是派生值**——要写请用 `SelectByText`（或 `Path`）。它**刻意遮蔽**了 `TTyCascader` 静态类型上的 `TControl.Text`（`TTyComboBox.Text` 已是这么做的）；把控件看成 `TControl` 的 LCL 代码拿到的仍是继承来的 `Caption` 文本。 |
| `procedure DropDown` | — | 打开面板。**没有选项时是惰性的**（`TTyComboBox` 的规则：绝不显示空弹窗）。 |
| `procedure CloseUp` | — | 关闭面板。未打开时（headless 路径 / 已关闭）**仍会**记下 tick 并触发 `OnCloseUp`，让重开守卫行为一致。 |
| `function DroppedDown: Boolean` | `Boolean` | 面板是否打开。 |
| `procedure Clear` | — | 清空选择（`Path := []`）。**原本有选中时**才触发 `OnChange`。 |
| `function SelectedNode: TTyCascaderNode` | 节点 | `Path` 选中的节点；未选时 `nil`。 |
| `function PathDepth: Integer` | 层数 | 选中了几层。 |
| `function SelectByText(const AText: string): Boolean` | 是否命中 | 按拼好的标题路径选中（`'华东 / 浙江 / 杭州'`）。**未命中时返回 `False` 且选择原样不动**——调用方打错一个字不该悄悄丢掉已有的值。匹配规则见 `TyCascaderPathFromText`。 |
| `function DropDownPanel: TTyCascaderPanel` | 面板 | 首次调用时创建的下拉面板。public 是因为它是宿主可能想够到的活对象——**也因为它是选择规则的测试缝**：面板可以在**从没有窗口出现过**的情况下被创建并完整播种。 |
| `function TyCascaderTextRect: TRect` | 设备像素 | 字段的文字带，`(0,0)`-local，**就是绘制用的那个矩形**。 |
| `function TyCascaderButtonRect: TRect` | 设备像素 | 字段的 chevron 区，同上。 |

### 继承的通用成员

`TTyCascader` 继承自 `TTyCustomControl`（`tyControls.Base`），另暴露 `Version` / `Enabled` / `Font` / `Hint` / `TabOrder` / `PopupMenu` / `Constraints` 及基线事件集（`OnClick` / `OnKeyDown` / `OnEnter` / `OnExit` / …），见 [../events.md](../events.md)。

---

## 5. 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TNotifyEvent` | **`Path` 真的变了**才触发——叶子提交，或代码赋值。重复赋同一条路径**不触发**。**浏览面板不触发**：面板编辑的是草稿，只有**叶子**选择才提交。**编辑 `Nodes` 也不触发**（见 §8）。 |
| `OnDropDown` | `TNotifyEvent` | `DropDown` 成功弹出后。 |
| `OnCloseUp` | `TNotifyEvent` | 每次收起后（含未打开时调用 `CloseUp` 的记账路径）。 |

---

## 6. 关键成员

单元顶部把**每一条**关于路径与列的规则都做成了**自由函数**（进去是普通整数 / 集合，出来是值——无控件、无句柄、无主题），因为**这些规则就是本控件的行为**，必须能无头测试（`tests/test.cascader.pas`）。

### 纯规则：路径与列

```pascal
type
  TTyCascaderPath = array of Integer;

function TyCascaderCopyPath(const APath: TTyCascaderPath): TTyCascaderPath;
function TyCascaderTruncatePath(const APath: TTyCascaderPath; ALength: Integer): TTyCascaderPath;
function TyCascaderPathsEqual(const APathA, APathB: TTyCascaderPath): Boolean;
function TyCascaderChildrenOf(ANode: TTyCascaderNode): TTyCascaderNodes;
function TyCascaderNodeAt(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath;
  ADepth: Integer): TTyCascaderNode;
function TyCascaderValidPath(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath): TTyCascaderPath;
function TyCascaderColumnNodes(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath;
  AColumn: Integer): TTyCascaderNodes;
function TyCascaderColumnCount(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath): Integer;
function TyCascaderSelectedInColumn(const APath: TTyCascaderPath; AColumn: Integer): Integer;
function TyCascaderMaxColumnRows(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath): Integer;
function TyCascaderPickPath(const APath: TTyCascaderPath; AColumn, AIndex: Integer): TTyCascaderPath;
function TyCascaderPathIsLeaf(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath): Boolean;
function TyCascaderPathText(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath;
  const ASeparator: string): string;
function TyCascaderPathFromText(ARoot: TTyCascaderNodes; const AText, ASeparator: string;
  out APath: TTyCascaderPath): Boolean;
```

要点：

- **`TyCascaderCopyPath` 是按值拷贝**：交出去和收进来的路径都是值，绝不是控件自己数组的别名（就地改它的调用方会毁掉选中值）。
- **`TyCascaderTruncatePath` 两头都钳**：负长度得 `[]`，超过末尾得整条路径——调用方无需先做边界检查。
- **`TyCascaderPathsEqual` 逐项比较**，就是变化检测；长度不同即不同。
- **`TyCascaderChildrenOf` 无子项时答 `nil`，不是空集合**：`nil` 是「它是不是叶子」与「它后面还有没有列」的**唯一**答案，这样叶子和「子表被清空的分支」永远读不出差别。
- **`TyCascaderNodeAt`**：`ADepth` 钳进 `[0, Length(APath)]`；下标越界、或路径走进了叶子 ⇒ `nil`。**深度 0 选中的是根「列表」，它不是节点，所以答 `nil`**。
- **`TyCascaderValidPath` 是归一化器**，进入控件的每条路径都过它：**在第一个不指向「真实且 `Enabled`」节点的项上截断**。路径**从不被拒绝、也从不被钳到相邻选项**上，只是被截回仍然成立于当前树的前缀（沿用 `TTyListBox.ItemIndex` 的家规：不存在的下标意味着「没选」，不是「最近的那个」）。
- **`TyCascaderColumnNodes`**：列 0 是根列表，列 k 是 `APath[0..k-1]` 所指节点的子项。该列不存在时答 `nil`——调用方就是这么知道列用完了的。
- **`TyCascaderColumnCount`**：根列 + 每个「其节点有子项」的路径项各一列；完全没有选项时为 0。**这就是面板宽度的来源**，且它**停在路径第一个错的地方**，所以一条无效路径只可能显示**更少**的列，绝不会显示一列坏的。
- **`TyCascaderSelectedInColumn`**：列 k 的选中行**就是** `APath[k]`——这个恒等式正是「值为下标路径」的全部理由。
- **`TyCascaderPickPath` 是唯一的选择规则**：在列 `AColumn` 选中行 `AIndex` ⇒ **截断到 `AColumn` 项，再追加 `AIndex`**。这一条覆盖所有情形：往深处选是延长；在某层**重选**会丢掉它右边的一切（你改了省，原来的市就不再是答案的一部分）；在某层**重选同一行**也照样丢掉右边（用户重新选了这一层，这是对其下各层的一个表态）。退化的选择（无列 / 无行）原样返回。
- **`TyCascaderPathText`**：路径走错时**拼出它走对的前缀**而不是抛异常——`Text` 每次绘制都要算，它绝不能成为拖垮窗体的那个东西。**数的是层级、不是拼出的串**：标题为空的选项照样占住两个分隔符之间的位置，不会凭空消失。
- **`TyCascaderPathFromText` 是 `TyCascaderPathText` 的逆**：某段在其层级匹配不到子项 ⇒ 返回 `False` 且 `APath = []`。匹配**区分大小写**并取**第一个**命中——标题是数据，两个同名兄弟是调用方自己的歧义，不该由这个函数去猜。空 `AText` 解析为空路径并返回 `True`：`''` 是合法值，意思是「什么都没选」。空 `ASeparator` 直接 `False`（拼不起来就拆不开）。

### 纯规则：键盘

```pascal
function TyCascaderStepIndex(ALevel: TTyCascaderNodes; ACurrent, ADelta: Integer): Integer;
function TyCascaderStepPath(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath;
  ADelta: Integer): TTyCascaderPath;
function TyCascaderEnterPath(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath): TTyCascaderPath;
function TyCascaderLeavePath(const APath: TTyCascaderPath): TTyCascaderPath;
```

- **`TyCascaderStepIndex`**：只读 `ADelta` 的**符号**（一次按键走一行），**跨过**禁用项。**两端钳住、不回绕**：一列是用户看得见的短表，走到头就该停，不该瞬移（沿用 `TTyCustomTabStrip` / `TTySegmented` 的家规）。从 `-1` 起步时**从来的那一端进入**：向下落在第一个可用项，向上落在最后一个。整列没有可落脚的项时答 `-1`。
- **`TyCascaderStepPath`** 移动**最深可见列**的选择。哪一列是最深列**不需要游标状态**：它永远是 `TyCascaderColumnCount - 1`，且在两种形态下都正好对：选中的是分支时，最深列就是用户正在看的那列崭新的、未选中的列；选中的是叶子时，最深列就是叶子所在的那列。
- **`TyCascaderEnterPath`** 下潜一层，落在当前选中节点的**第一个可用子项**上。未选中 / 是叶子 / 子项全禁用时，路径不动。
- **`TyCascaderLeavePath`** 退出一层（丢掉最后一项）；空路径仍为空。

### 纯规则：几何

```pascal
type
  TTyCascaderFieldLayout = record
    TextRect: TRect;     // 拼好的路径画在哪（空 => 放不下）
    ButtonRect: TRect;   // chevron 区（空 => 没有）
  end;

  TTyCascaderRowLayout = record
    CaptionRect: TRect;  // 选项文字带
    ExpandRect: TRect;   // '>' 槽位（叶子上为空；行太窄挤不下时也为空）
  end;

function TyCascaderFieldLayout(AClientWidth, AClientHeight, APadLeft, APadTop, APadRight,
  APadBottom, AButtonWidth: Integer): TTyCascaderFieldLayout;
function TyCascaderColumnRect(APanelWidth, APanelHeight, AColumnCount, AColumnWidth,
  APadLeft, APadTop, APadRight, APadBottom, AIndex: Integer): TRect;
function TyCascaderColumnAt(APanelWidth, APanelHeight, AColumnCount, AColumnWidth,
  APadLeft, APadTop, APadRight, APadBottom, X, Y: Integer): Integer;
function TyCascaderPanelSize(AColumnCount, AColumnWidth, AVisibleRows, ARowHeight,
  APadLeft, APadTop, APadRight, APadBottom: Integer): TSize;
function TyCascaderVisibleRows(AColumnHeight, ARowHeight: Integer): Integer;
function TyCascaderRowRect(const AColumnRect: TRect; ARowHeight, AFirstRow, AIndex: Integer): TRect;
function TyCascaderRowAt(const AColumnRect: TRect; ARowHeight, AFirstRow, ACount,
  X, Y: Integer): Integer;
function TyCascaderClampFirstRow(AFirstRow, ACount, AVisibleRows: Integer): Integer;
function TyCascaderScrollToShow(AFirstRow, ARow, ACount, AVisibleRows: Integer): Integer;
function TyCascaderRowLayout(const ARowRect: TRect; AHasChildren: Boolean;
  APadLeft, APadRight, AGap, AExpandSize: Integer): TTyCascaderRowLayout;
```

**坐标空间：全部是设备像素。** 字段布局相对**控件矩形左上角**；面板的列 / 行矩形在**面板自己的空间**里（不同于 `TyTagLayout` 的控件-local 矩形——一行活在一列里、一列活在面板里，把原点一路带下去才能让绘制与命中检测落在同一个矩形上）。

- **`TyCascaderFieldLayout`**：chevron 区**贴的是完整矩形的右边**（不是 padding 带的右边）并**跨满高度**，文字带**止于 chevron 区**——右侧 padding **刻意不在这里生效**，chevron 区**就是**字段的右内缩。这是**与 `TTyComboBox.RenderTo` 完全一致的**：级联器和下拉框摆在同一个表单里时，文字左边缘对齐、chevron 位置对齐。padding 吃光整个字段、或尺寸为 0 ⇒ 两个矩形都为空，**绝不反转**。
- **`TyCascaderColumnRect`**：列从 padding 带的左边缘起**依次平铺**，每列正好 `AColumnWidth` 宽；会溢出带右边缘的列被**裁到**带上（绝不画到面板自己的 padding 之外）。退化请求（无列 / 下标越界 / 零面积面板 / padding 吃光面板）⇒ 空矩形，绝不反转。
- **`TyCascaderColumnAt` 是 `TyCascaderColumnRect` 的精确逆**（它就是扫那个函数自己产出的矩形），所以用户点到的列就是画在那儿的列。**面板的 padding 沟槽不属于任何列。**
- **`TyCascaderPanelSize` 是 `TyCascaderColumnRect` 的逆**：把结果喂回去（其余参数不变），每列恰好 `AColumnWidth` 宽、恰好 `AVisibleRows` 行高。**退化主题下也至少 1×1**——弹窗是个窗口，它总得有地方待着。
- **`TyCascaderVisibleRows`**：只数**整行**。**半行不算行**：它会被从字形中间裁断，也没法安全点击，所以这一列干脆就到此为止。
- **`TyCascaderRowRect`**：滚出顶部、或**只能放下一半**的行 ⇒ 空矩形。
- **`TyCascaderRowAt` 是 `TyCascaderRowRect` 的精确逆**：它先算出行号，再**重新推导那一行自己的矩形**来确认——所以点在「半行本该占据的那道缝」里答 `-1`，而不是选中一个用户看不全的选项。
- **`TyCascaderClampFirstRow`**：钳进 `[0, max(0, ACount - AVisibleRows)]`；整列放得下时顶行只可能是 0。
- **`TyCascaderScrollToShow`**：以**最小移动量**把 `ARow` 带进视野——已可见则不动，在带上方则它自己成为顶行，在带下方则把它带到带底。结果同样被钳。这是**方向键**滚动用的；鼠标不需要它（点击本来就落不到不可见的行上）。
- **`TyCascaderRowLayout`：文字赢得空间**——这**正好与 `TyTagLayout` 的规则相反**，而且理由是同一条道理反过来读：标签的 `x` 是它唯一的可操作对象，所以它保留槽位；而级联的一行**整行都可点**，它的 `>` 只是在说「这底下还有」——纯装饰。所以放不下两者的窄行**丢掉标记、留下文字**。行比标记自身还矮时，标记被**压进**行高，绝不越界。

### `TyCascaderInheritText`

```pascal
function TyCascaderInheritText(const AParent, AChild: TTyStyleSet): TTyStyleSet;
```

嵌套键画**文字**时用的令牌：主题给了就用它自己的，没给就用父表面的（`TextColor` / `FontName` / `FontSize` / `FontWeight` 四项）。这是把家规「没颜色就继承父的笔色」按同一逻辑延伸到了字体上——只定义了 `TyCascaderPanel` 的主题**仍然**必须得到可读的、字号正确的行，且**绝不**是硬编码颜色。**`background` 与 `border` 刻意不这样继承**：没有自己背景的行就不该画出底片。

---

## 7. 状态与主题

### 支持的伪类状态

- **字段**（`TyCascader`）：`:hover` / `:focus` / `:active` / `:disabled` 由基类状态机计算。
- **行**（`TyCascaderItem`）：状态由面板逐行算出——
  - `:selected` —— 该行**就是**本列的选中项（`TyCascaderSelectedInColumn`）。注入的是 `TTyButton.Down` 与 `TTySegmented` 的 chip **同一个**静息状态，所以一条 `:selected` 主题规则同时管住三者。
  - `:disabled` —— 面板 `Enabled = False`、该列不存在、下标越界，或该选项 `Enabled = False`。**禁用仍保留 `:selected`**（`TTySegmented` 的规则：灰掉的行也必须显示它就是当前生效的那个）。级联层做剩下的事：`ResolveLayer` 把 `:selected` 当静息层铺上，再以最高优先级最后应用 `:disabled`——底片留住，禁用的笔色压过它。**`:hover` 刻意缺席**：禁用行不吃 hover。
  - `:hover` —— 指针精确落在该行上。
  - `:normal` —— 以上都不成立时。

### 主题令牌摘要

```css
TyCascader {
  background: var(--input-bg);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: var(--input-border-width);
  border-radius: var(--radius);
  padding: 4px;
  font-size: var(--font-size-base);
}
TyCascader:hover    { border-color: var(--input-border-hover); }
TyCascader:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }
TyCascader:disabled { opacity: var(--disabled-opacity); }
TyCascaderPanel { background: var(--surface); color: var(--on-surface);
                  border-color: var(--border); border-width: var(--input-border-width);
                  border-radius: var(--radius); }
TyCascaderItem          { background: alpha(#FFFFFF, 0); color: var(--on-surface);
                          font-size: var(--font-size-base); padding: 0px 8px; }
TyCascaderItem:hover    { background: var(--surface-listitem-hover); }
TyCascaderItem:selected { background: var(--accent); color: var(--on-accent); }
TyCascaderItem:disabled { color: var(--muted); }
```

> 这一段写在 **base 层**（`themes/light.tycss`）：本控件没有表面键就什么都不画，所以规则放在 base，**每个主题都继承它**，然后可以各自重写。

**列间分隔线**取的是**面板自己的** `border-color` / `border-width`（宽度至少 1 设备像素），且**只有在主题真给了面板一圈可见边框时才画**——无边框的弹窗就得到无分隔的列。**绝不是硬编码的线色。**

**`>` 标记**取的是**行的笔色**（它自己键的 `color`，或继承自面板的）——只有三个 typeKey，所以标记是选项文字颜色的一部分，禁用行的标记随它的字一起变灰。

**面板 `padding` 决定列带**：`light.tycss` 的 `TyCascaderPanel` **没有声明 `padding`**（= 0），所以默认下列直接贴着面板边框铺。

### 可调尺寸令牌（v3/C 约定）

`themes/` 下**目前没有任何主题定义这几个 token**，因此它们全部落在下表的内置默认上。每个调用点都会把逻辑像素按 PPI 缩放到设备像素（`MulDiv(..., APPI, 96)`，与 `TTyPainter.Scale` 同一换算——所以命中检测量的就是绘制画的）。

| 令牌 | 内置默认（逻辑像素） | 作用 |
|------|------|------|
| `--cascader-column-width` | `120`（= `TyCascaderColumnWidth`） | 一列的宽度 |
| `--cascader-row-height` | `24`（= `TyCascaderRowHeight`） | 一个选项行的高度。**钳到至少 1**——零高的行会让命中检测除零 |
| `--cascader-expand-size` | `12`（= `TyCascaderExpandSize`） | 分支行上 `>` 的方形槽边长 |
| `--cascader-expand-gap` | `4`（= `TyCascaderExpandGap`） | 文字与 `>` 槽位之间的间隙 |
| `--cascader-button-width` | `18`（= `TyCascaderButtonWidth` = `TyFieldButtonWidth`） | 字段的 chevron 区宽度。**刻意就是 `TyFieldButtonWidth`**：级联器的 chevron 区和下拉框的一样宽，两个字段在表单里才对得齐 |

> **为什么是具名常量而不是内联字面量：** 几何、测量、测试这几个调用点必须对 token 的**拼写**达成一致——某一处打错字会让它悄悄停在默认值上，几何就与命中检测漂移了。

字形本身还支持图标字体覆盖（v3/C5）：字段的下拉指示符用 `--glyph-dropdown`（`TTyComboBox` 已在用的那个 token——一条主题规则重调所有字段的 chevron），分支行的标记用 `--glyph-chevron-right`。

### 主题未定义时的降级

严格按代码所写：

- **`TyCascader` 无 `background`** ⇒ **整个字段什么都不画**：不画文字，连主题**确实定义了**笔色的 chevron 也不画。降级，绝不发明观感。
- **`TyCascaderPanel` 无 `background`** ⇒ **整块面板什么都不画**，**一行也不画**——没有表面就没有面板（即使 `TyCascaderItem` 定义得完完整整）。
- **`TyCascaderItem` 无 `background`** ⇒ **不画底片**，而下面的文字照画：只填 `:selected` / `:hover` 的主题**零代码分支**地得到经典的「只有当前项有块底」。
- **`TyCascaderItem` 无 `color` / `font-*`** ⇒ 取**面板的**（`TyCascaderInheritText`）。**绝不**回退到任何硬编码颜色。

---

## 8. 代码示例

```pascal
uses tyControls.Controller, tyControls.Cascader;

TyDefaultController.LoadTheme('themes/light.tycss');

var
  Cas: TTyCascader;
  East, ZJ: TTyCascaderNode;

Cas := TTyCascader.Create(Self);
Cas.Parent := Surface;
Cas.SetBounds(20, 20, 200, 26);
Cas.DropDownRows := 10;
Cas.OnChange := @HandleAreaChange;

// 代码建树：AddNode 是一行式写法；.lfm 里则整棵树递归流化,无需任何代码
East := Cas.Nodes.AddNode('华东');
ZJ   := East.Children.AddNode('浙江');
ZJ.Children.AddNode('杭州');
ZJ.Children.AddNode('宁波');
East.Children.AddNode('江苏').Children.AddNode('南京');
Cas.Nodes.AddNode('海南');                      // 根上的叶子：一次点击即可提交
Cas.Nodes.AddNode('禁区').Enabled := False;     // 灰掉,且它底下的一切都不可达

// 按拼好的标题路径选中（用当前 Separator 解析）
if not Cas.SelectByText('华东 / 浙江 / 杭州') then
  Cas.Clear;                                    // 未命中时 SelectByText 不动选择,由你决定
```

读取选中值：

```pascal
procedure TForm1.HandleAreaChange(Sender: TObject);
var
  Cas: TTyCascader;
begin
  Cas := Sender as TTyCascader;
  // Path 是每层一个下标；Text 是拼好的串；SelectedNode 是末端节点(可读它的 Tag)
  Caption := Cas.Text;                                    // '华东 / 浙江 / 杭州'
  if Cas.SelectedNode <> nil then
    FAreaId := Cas.SelectedNode.Tag;                      // 宿主自己的载荷
end;
```

---

## 9. 注意事项

- **草稿 vs 值，是本控件最该先理解的一条：** 面板改的是**草稿**，只有**叶子**选择才会写进 `Path` 并触发 `OnChange`。选到分支只是开出下一列——此时关掉弹窗，字段的值**原封不动**。`Enter` 同理：落在分支上是**惰性的**，绝不提交半截路径（鼠标也做不到这件事）。
- **编辑 `Nodes` 会静默重新校验选择：** 删掉 / 禁用选中路径上的某一项，`Path` 会被截回仍然成立的前缀，但**不触发 `OnChange`**——编辑 `Nodes` 是宿主自己的动作、不是用户的选择，把它当事件报回去等于报告一件宿主自己干的、也没问过的事（`TTySegmented` 对同一情形的规则）。宿主在自己编辑之后**自行读 `Path`**。
- **禁用一个选项等于禁掉它整棵子树：** 「穿不过一个你选不了的选项」——`TyCascaderValidPath` 在它那里截断，`PickAt` 对它惰性，方向键跨过它。
- **面板的 `StyleClass` 不由字段传递。** 行样式解析用的是**面板自己的** `StyleClass`，而字段**从不**把自己的 `StyleClass` 赋给面板（`SyncPanel` 只同步 controller / Wayland 标志 / `Root` / 草稿）。唯一用到字段 `StyleClass` 去解析 `TyCascaderPanel` 的地方是 `DropDown` 里算弹窗窗口区域的圆角。要给下拉面板 / 行加变体，请自己设 `DropDownPanel.StyleClass`。
- **`TTyCascaderPanel` 是内部件，不是调色板组件。** 它由字段首次使用时创建、托管在下拉弹窗里；**不得**注册到组件面板上（往表单上放一个没有任何意义）。它是窗口化的（`TTyCustomControl`）——它是弹窗的 `alClient` 内容，而图形控件没有句柄，当不了窗体的内容。它的 `TabStop` **刻意为 `False`**：让弹窗**窗体**保持焦点，其 `KeyPreview` 钩子来路由键盘（与 `TTyComboBox` 把 Escape 路由给它的列表同一套路），这样一次点行也偷不走激活。
- **键盘：** 弹窗打开时，`↓`/`↑` 移动最深列、`→` 下潜一层、`←` 退出一层、`Enter` 在叶子上提交并关闭、`Esc` **丢弃草稿**并关闭（下次 `DropDown` 会用 `Path` 重新播种）。字段本身：`Alt+↓` / `F4` 切换下拉，`Esc` 在已打开时收起。
- **鼠标：** 行是**按下即选**（一列级联就是一个菜单，本库每个菜单都在按下时提交）。**按在 padding 沟槽里什么也不碰、且是惰性的**——它绝不能清掉用户正看着的草稿。**滚轮滚的是指针底下的那一列**，不是「面板」：列各自独立滚动，而用户在读的只有其中一列。
- **`Path` 是值不是别名：** 读出来是副本，写进去被拷贝。FPC 动态数组是引用计数的，但**不是** copy-on-write。
- **`Text` 只读，且遮蔽 `TControl.Text`：** 只对 `TTyCascader` 静态类型成立；把它看作 `TControl` 的 LCL 代码拿到的仍是继承的 `Caption` 文本。
- **文字用主题样式，不读 LCL `Font`；不解析助记符：** 字段与选项文字都取解析后的样式，放不下时**省略号截断**（`'华东 / 浙江 / 杭…'`、`'内蒙古自治…'`），而不是在裁剪边缘把字形切成两半。选项不激活任何东西，`Caption` 里的 `&` 就是字面字符。
- **重开守卫：** 弹窗打开时点字段，会先由窗体的 deactivate 触发关闭（`DroppedDown` 在 `Click` 里已经是 `False` 了），朴素的 toggle 会立刻重开。因此 **200ms 内刚关过就不重开**（`TTyComboBox` 的守卫，同一套机制）。
- **提交后的关闭是异步的：** 还在面板自己的鼠标处理里同步隐藏弹窗，会让 LCL 的点击完成焦点路径指向一个已隐藏的窗体（`EInvalidOperation 'Can not focus'`）。所以关闭被 `QueueAsyncCall` 推到下一个消息循环。
- **Wayland：** 弹窗窗口无法做形状裁剪，此时字段把面板的 `ForceSquareSurface` 置位，面板以**直角**绘制表面以匹配直角的窗口（`TTyListBox` 的同一标志、同一规则）。
