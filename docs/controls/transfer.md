# TTyTransfer

## 1. 概述

`TTyTransfer` 是 TyControls 库中的主题化「穿梭框 / 双列表移动框」控件，继承自 `TTyCustomControl`（窗口化，拥有自己的句柄）。左边一个**源**列表窗格，右边一个**目标**列表窗格，中间一条竖直的**箭头轨道（rail）**把行在两边搬来搬去。

它填的缺口是一个**经典桌面控件**：分组成员管理、列（字段）选择器、权限分配、播放列表编排——这个库一直没有。每个宿主自己拼两个 `TTyListBox` 加一竖排按钮，每份都有自己的移动规则、自己的**索引位移 off-by-one**、自己对「箭头什么时候该变灰」的理解。

**组合是刻意的：窗格是真的 `TTyListBox`，箭头是真的 `TTyButton`。** 滚动、滚动条、`MultiSelect` 的 ctrl/shift 连选、键盘导航、hover、`Sorted`、主题化的行——全都已经存在、已经被测过、已经被仓库里每个皮肤打扮过了；在这里重画两个列表只会得到第二个、更差的 listbox。同理，箭头按钮（`TTyTransferArrowButton`）**不改 typeKey**，于是它解析的是每个主题都已经发过的那条 `TyButton` 规则，hover / 按下 / 禁用 / 焦点、背景淡入、键盘激活、`:disabled` 的观感全部白送。**代价是：`TTyTransfer` 除了自己的框，只引入了一个新 typeKey。**

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Transfer` |
| 基类 | `TTyCustomControl`（→ `TCustomControl`）。**必须窗口化**：它要**承载**控件，图形控件没有句柄可挂子控件（同 `TTyCard` 的理由） |
| `GetStyleTypeKey` 返回值 | `'TyTransfer'`（外框：`background` / `border-*` / `border-radius` / `shadow` / `opacity` / `padding`。**`padding` 是整个布局向内计算的外缩进**） |
| 标题带 typeKey | `'TyTransferTitle'`（`background` = 带底色，`border-color`/`border-width` = 带下方的发丝分隔线，`color`/`font-*` = 标题文字） |
| 借用的 typeKey | `'TyListBox'` / `'TyListItem'`（两个窗格）、`'TyButton'`（轨道上的四个箭头）——**都不是新键**，已被现有主题打扮 |
| 默认尺寸 | 480 × 220（逻辑像素，构造时设置） |
| 新增尺寸令牌 | 7 个 `--transfer-*`，见 §6 |

```pascal
uses tyControls.Transfer;
```

**为什么标题带要单独一个键？** 和 `TyCardHeader` 同一个理由——一条 header 带是「带底色 + 分隔线 + 自己的墨色」，外框那一对 `background` / `color` 表达不了它。

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Items` | `TStrings` | 空 | **源池——就是左窗格自己的列表，不是副本**。直接编辑它没问题：轨道会从每一次编辑重新推导自己的 `Enabled`。写入时执行 `FLeftList.Items.Assign(AValue)`。 |
| `Selected` | `TStrings` | 空 | **目标列表——就是右窗格自己的列表，不是副本**。向右移动的行按**源顺序追加**到这里；在窗体显示前给它塞值，就是让穿梭框「一开始就半满」的做法。 |
| `LeftTitle` | `string` | `''` | 左窗格标题。用解析后的 `TyTransferTitle` 样式绘制（**不**读 LCL `Font.*`），放不下时省略号截断，**从不换行**，**不解析助记符**（标题不激活任何东西，`&` 是字面字符）。改它只 `Invalidate`，不重新布局。 |
| `RightTitle` | `string` | `''` | 同上，右窗格标题。 |
| `TitleAlignment` | `TAlignment` | `taLeftJustify` | 两条标题带内文字的水平对齐（**两条共用一个值**）。 |
| `ShowTitles` | `Boolean` | `True` | 是否绘制标题带**并**在窗格上方为它预留高度。**标志是权威，标题文字不是**：`LeftTitle` 为空时它的带**依然占位**，所以清空标题绝不会让窗格跳动（`TTyCard.ShowHeader` 的规则）。 |
| `ShowMoveAll` | `Boolean` | `True` | 轨道是否提供两个双箭头「全部移动」按钮。关掉后只剩两个单箭头，并在轨道里**重新居中**。 |
| `OnChange` | `TNotifyEvent` | `nil` | 见 §4。 |
| `Align` / `Anchors` / `StyleClass` / `StyleOverride` / `Controller` | — | — | 基类通用成员（`Controller` 会同步下发给两个窗格和四个箭头）。 |

### public 方法与属性

| 成员 | 返回 | 说明 |
|------|------|------|
| `DoMove(AMove: TTyTransferMove)` | — | 执行一次移动：把规则选中的行从源窗格取出、追加到目标窗格。**规则一行都没选中时静默且无副作用**。public 是为了让宿主能从菜单 / 快捷键 / 双击驱动轨道。 |
| `MoveRight` / `MoveAllRight` / `MoveLeft` / `MoveAllLeft` | — | 四个移动的具名版本，方便宿主代码可读。 |
| `CanMove(AMove)` | `Boolean` | 此刻这个移动有没有东西可搬——**和轨道 `Enabled` 是同一条规则**。 |
| `LeftTitleRect` / `RightTitleRect` | `TRect` | 已绘制的标题带（外框自身坐标）；`ShowTitles = False` 时为空。 |
| `RailRect` | `TRect` | 两窗格之间的按钮列（外框自身坐标）。 |
| `LeftPane` / `RightPane` | `TTyListBox` | 两个窗格。**由穿梭框持有**，穿过它们去用 listbox 自己的旋钮（`ItemHeight` / `Sorted` / `TopIndex` / 行样式）。**不要 `Free` 或改 `Parent`**；也注意它们的 `OnChange` **属于穿梭框**（那正是轨道 `Enabled` 保持诚实的机制），请改用 `TTyTransfer.OnChange`。 |
| `MoveButton[AMove]` | `TTyButton` | 轨道的按钮，按它执行的移动索引。由穿梭框持有。暴露出来是让宿主给它们挂 `Hint`（箭头说的是方向，不是含义）或 `StyleClass`。**它们的 `Enabled` 由选择推导，会被覆写。** |

`MoveButton` 返回的实际类型是 `TTyTransferArrowButton`——一个只重写了 `DrawContent`（在内容矩形里画箭头而不是 caption）的普通 `TTyButton`。`TTyButton` 没有字形词汇表；`TTyGlyphButton` 要的是 `ImageList` 而不是 `TTyGlyphKind`；而把按钮的 caption 写成 `'->'` 会让轨道的观感取决于系统字体——所以有了这个后代类。

### 类型与常量

```pascal
{ 四个移动，顺序就是它们自上而下堆叠的顺序（经典穿梭框次序：两个向右在上，
  每一对里「选中」在「全部」之上）。 }
TTyTransferMove = (tmMoveRight, tmMoveAllRight, tmMoveLeft, tmMoveAllLeft);

{ 升序、去重、落在范围内的源行号——下面每条规则说的都是它。 }
TTyTransferIndices = array of Integer;
```

七个内置逻辑像素兜底常量（96-PPI 基线）及其对应的令牌名，见 §6 的表。**令牌名是具名常量而不是内联字面量**：布局、箭头绘制、测试这几个调用点必须拼写一致，任何一处写错都会静默回落到兜底值，画出来的和算出来的就会漂移。

---

## 4. 事件

| 事件 | 触发时机 |
|------|----------|
| `OnChange` | 在一次移动**真的搬动了东西**之后触发。来自轨道点击、或来自 `DoMove` / `MoveXxx`——**代码驱动的移动和点击出来的是同一个事件**（`TTySegmented` 的规则）。 |

不触发 `OnChange` 的两种情况，都是刻意的：

- **搬了个空不算变化**（`DoMove` 在索引为空时直接 `Exit`；`TyTransferApplyMove` 返回 0 时也不发）。
- **宿主自己编辑 `Items` / `Selected` 也不发**：那一下是宿主自己造成的，不需要被告知。

> **一次手势，一个事件。** 一次移动内部要编辑两个列表、还要清一次选择，每一步都会触发内部钩子；`FMoving` 标志把它们全部吞掉，`UpdateMoveButtons` 在移动完整之后跑一次，`OnChange` 也只发一次。

---

## 5. 纯几何函数 / 纯规则（单元级，可无句柄直接调用）

全部整数 / 裸 `TRect` / 裸数组 / 裸 `TStringList` 入参，无控件、无句柄、无主题，测试直接调用（`tests/test.transfer.pas`）。

### 移动的分类

```pascal
function TyTransferMoveIsRightward(AMove: TTyTransferMove): Boolean;  // 从左窗格发往右窗格？
function TyTransferMoveIsAll(AMove: TTyTransferMove): Boolean;        // 无视高亮、整窗格全取？
```

### 带的几何

```pascal
type
  TTyTransferLayout = record
    LeftTitleRect: TRect;    // 标题带（关掉标题 / 没空间时为空）
    LeftPaneRect: TRect;     // 左 listbox 的位置
    RailRect: TRect;         // 中间的按钮列
    RightTitleRect: TRect;
    RightPaneRect: TRect;
  end;

function TyTransferLayout(const AClient: TRect; ARailWidth,
  ATitleHeight: Integer): TTyTransferLayout;
```

设备像素，与传入的（**已按主题 `padding` 内缩过的**）客户区**同一坐标空间**。`ATitleHeight` 传 0 即「无标题」。契约：

- **三列精确铺满客户区**：`LeftPane.Right = Rail.Left` 且 `Rail.Right = RightPane.Left`——两者之间不留一条没人认领的框条。
- **横向：轨道优先服务**（它是这个控件唯一的可操作物——`TyTagLayout` 给关闭槽位定的同一条规则），两个窗格分剩下的，而且**均分**：两个窗格不一样宽的穿梭框看着就是坏的，所以**奇数余量归轨道**（它关于中线对称，谁也看不出来）。轨道比客户区还宽 → 两个窗格都塌缩为空，**绝不反转**。
- **纵向：标题带占每一列的顶部**，窗格拿剩下的；带比客户区还高时**保留带、丢掉窗格**（空，不反转）。
- **轨道不被标题带缩短**：箭头对着整个盒子居中，这才让它们和两个列表的中部齐平。

```pascal
function TyTransferButtonRect(const ARail: TRect; ACount, AIndex, AButtonWidth,
  AButtonHeight, AButtonGap: Integer): TRect;
```

`ARail` 里第 `AIndex` / 共 `ACount` 个移动按钮的矩形，设备像素。按钮竖直堆叠、**整摞在轨道里横竖双向居中**；比轨道高时**钉在轨道顶部**（让前几个箭头还够得着，而不是一半从上下两头漏出去）；会越过轨道底的按钮被裁到轨道底；什么都不剩时返回**空矩形，绝不反转**。按钮比轨道宽 → **压到轨道宽，绝不溢出到窗格上**。

```pascal
function TyTransferArrowRect(const AContent: TRect; ACount, AIndex, ASize,
  AGap: Integer): TRect;
```

移动按钮**已按主题 `TyButton` padding 内缩过的**内容矩形里，第 `AIndex` / 共 `ACount` 个箭头的方格。`ACount` 是 1（普通移动）或 2（双箭头的「全部」）。`ACount` 个 `ASize` 见方、以 `AGap` 相隔的格子在 `AContent` 里双向居中，并且——**和这里其它所有几何相反——它会缩小去适应，而不是塌缩**：箭头就是按钮的全部内容，主题给 `TyButton` 定了慷慨的 padding 就必须得到一个更小的箭头，绝不是一个空按钮。**间隙保持整数不动，让字形让路**：两个挨着的箭头仍读作「全部」，两个消失的箭头读作坏按钮。只有连 1px 的箭头都放不下时才返回空。

### 移动规则

```pascal
function TyTransferNormalizeIndices(const AIndices: array of Integer;
  ACount: Integer): TTyTransferIndices;
```

把 `AIndices` 变成升序、去重、并夹到 `[0, ACount)`——下面每条规则期待的契约。**单独暴露（也单独测）是因为它正是让 `TyTransferApplyMove` 成为全函数的东西**：调用者按点击顺序递过来、或者递一个已经越界的陈旧索引，拿到的仍然是「存在的那些行、每行恰好一次、按列表顺序」。实现用 seen 位图而不是排序：定义域就是 `[0, ACount)`，一遍标记一遍输出即 O(n) 得到升序 + 去重，且不可能把相等的键排错。

```pascal
function TyTransferMoveIndices(const AHighlighted: array of Boolean;
  AAll: Boolean): TTyTransferIndices;
```

一次移动要取走的源行，升序。`AHighlighted[i]` 说第 i 行在源窗格里是否高亮；`AAll` 无视高亮、取每一行。**一个什么都没高亮的普通移动取走的是「什么都没有」**——它明确**不是**「那就全都搬走」，那是第二个按钮的活儿。

```pascal
function TyTransferCanMove(AHighlightedCount, ASourceCount: Integer; AAll: Boolean): Boolean;
```

一次移动有没有活干——**这就是把轨道变灰的规则**。空的源窗格永远给不出东西（两种按钮都灭）；否则「全部」移动永远是活的，普通移动至少要有一行高亮。

```pascal
function TyTransferApplyMove(ASource, ATarget: TStrings;
  const AIndices: array of Integer): Integer;
```

执行移动：把 `AIndices` 从 `ASource` 里取出，**按源顺序追加**到 `ATarget`。返回**实际搬了几行**（0 = 什么也没发生，这正是让控件「搬空不吭声」这条规则可表达的东西）。`AIndices` 在这里被归一化，所以它可以是任意顺序、带重复、或越界的。

> **删除是从后往前跑的。** 从前往后删会让每个后续索引位移一格、悄悄删掉错的行——**这就是每个手搓穿梭框都有的那个 bug**。（归一化正是让「从后往前」这个说法有定义的前提。）`ASource` / `ATarget` 为 `nil` 时惰性返回 0，而不是崩。

---

## 6. 状态与主题

### 支持的伪类状态

- **外框**（`TyTransfer`）：`:hover` / `:active` / `:disabled` / `:focus` 由基类状态机计算。
- **标题带**（`TyTransferTitle`）：**两条带一次解析**——同一个键、同一个 `StyleClass`（外框的）、同一组状态（外框的 `CurrentStates`）。标题带**没有自己的状态**：它是一个标签，不是可操作物。
- **窗格 / 轨道**：各自是独立控件，状态是它们自己的（`TyListBox` / `TyListItem` / `TyButton` 的常规状态）。

### 主题令牌摘要

`themes/light.tycss` 里的实际规则：

```css
/* Transfer: a frame around two list panes and the move rail. The panes/arrows reuse
   TyListBox / TyButton, which every theme already dresses. */
TyTransfer {
  background: alpha(#FFFFFF, 0);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: var(--input-border-width);
  border-radius: var(--radius);
  font-size: var(--font-size-base);
  padding: 0px;
}
TyTransfer:disabled { opacity: var(--disabled-opacity); }
TyTransferTitle { background: var(--surface-chrome); color: var(--on-surface);
                  border-color: var(--border); border-width: var(--input-border-width);
                  font-size: var(--font-size-base); font-weight: var(--font-weight-bold); padding: 0px 8px; }
```

> **`background: alpha(#FFFFFF, 0)` 是「全透明」，不是「没定义」。** 外框在 light 主题里只贡献一圈边框，让宿主表面透出来；但 `background` **确实被声明了**，所以 `tpBackground in Present` 为真——标题带照画不误（见下面的降级规则）。

### 可调尺寸令牌（v3/C 约定）

| 令牌 | 内置兜底（逻辑像素） | 作用 |
|------|------|------|
| `--transfer-rail-width` | `56`（= `TyTransferRailWidth`） | 两个窗格之间预留的整列宽度 |
| `--transfer-button-width` | `32`（= `TyTransferButtonWidth`） | 一个移动按钮的宽（在轨道里居中） |
| `--transfer-button-height` | `26`（= `TyTransferButtonHeight`） | 一个移动按钮的高（对齐紧凑型 `TTyButton`） |
| `--transfer-button-gap` | `6`（= `TyTransferButtonGap`） | 两个移动按钮之间的竖直间隙 |
| `--transfer-title-height` | `26`（= `TyTransferTitleHeight`） | 窗格上方的标题带高度（与按钮同高，所以带标题的穿梭框读作一个横带均匀的矩形） |
| `--transfer-arrow-size` | `12`（= `TyTransferArrowSize`） | 一个箭头字形的方形槽位边长 |
| `--transfer-arrow-gap` | `1`（= `TyTransferArrowGap`） | 「全部移动」按钮里两个箭头之间的间隙 |

**`light.tycss` 一个 `--transfer-*` 都没有声明**——七个全部走内置兜底。皮肤要重新调音就自己定义。

> **为什么没有「窗格与箭头之间的间距」令牌：** 轨道是一**列**（`rail-width`），按钮在它里面居中（`button-width`），所以窗格和箭头之间的空气就是 `(rail-width - button-width) / 2`——一次减法，而不是第三个没人会去单独调的 gutter 令牌。

箭头字形本身还支持图标字体覆盖（`--glyph-arrowright` / `--glyph-arrowleft`，v3/C5）。**「全部」画的是两个同向箭头，而不是一个自己的双人字符号**：双箭头就是经典的 `>>` 习语，它和向左的孪生兄弟保持对称（painter 没有向左的 chevron），而且不需要这个库尚未拥有的任何字形。

### 优雅降级

| 主题少定义了什么 | 结果 |
|------|------|
| `TyTransfer` 无 `background` | **既没有框，也没有标题带**——`RenderTo` 在 `DrawFrame` 之后直接 `Exit`。**窗格和轨道不受影响**：它们是拥有自己 typeKey 的独立控件。降级，绝不发明观感。 |
| `TyTransferTitle` 无 `background` | **不画带底色**，但**标题文字照画**。家规是「没有 background ⇒ 没有带」，不是「没有带 ⇒ 没有文字」。 |
| `TyTransferTitle` 无 `color` | 标题回落到**外框自己的墨色**。（空样式集的颜色是 `$00000000`——一个全**透明**、看不见的标题；回落让残缺的皮肤降级成一个能读的盒子，而**绝不**回落到这里发明的某个颜色。与 `TTyCard` 的 header 是同一条规则。） |
| `TyTransferTitle` 无 `border-color` / `border-width: 0` | 带下方**没有分隔线**。 |
| `TyTransferTitle` 无 `padding` | 标题的水平留白回落到**外框的 `padding`**——所以默认状态下标题和它下面的窗格对齐。 |

`DrawFrame` **总是**先跑（它要先填父控件的不透明表面，这是**窗口化**控件无论主题怎么说都需要的，否则自己的窗口会从圆角缺口里透出来）；**我们自己的**东西才全部以「主题定义了这个键」为门槛。

---

## 7. 代码示例

```pascal
uses tyControls.Controller, tyControls.Transfer;

TyDefaultController.LoadTheme('themes/light.tycss');

var T: TTyTransfer;

T := TTyTransfer.Create(Self);
T.Parent := Surface;
T.SetBounds(20, 20, 480, 220);
T.LeftTitle := '可选字段';
T.RightTitle := '已显示';
T.OnChange := @HandleTransferChange;

// 源池 —— 就是左窗格的列表本体
T.Items.AddStrings(['订单号', '客户', '金额', '下单时间', '状态', '备注']);
// 目标 —— 塞值即「一开始就半满」
T.Selected.AddStrings(['订单号', '客户']);

// 穿过窗格去用 listbox 自己的旋钮
T.LeftPane.Sorted := True;
// 箭头只说方向，不说含义 —— 给它挂 Hint
T.MoveButton[tmMoveAllRight].Hint := '全部添加';
```

从菜单 / 快捷键 / 双击驱动轨道，并读取结果：

```pascal
procedure TForm1.mnuAddClick(Sender: TObject);
begin
  T.MoveRight;                 // 等价于 DoMove(tmMoveRight)；没选中时静默无事发生
end;

procedure TForm1.HandleTransferChange(Sender: TObject);
begin
  StatusLabel.Caption := Format('已选 %d 项', [T.Selected.Count]);
  mnuAdd.Enabled := T.CanMove(tmMoveRight);   // 和轨道 Enabled 同一条规则
end;
```

---

## 8. 注意事项

- **`Items` / `Selected` 是窗格自己的列表，没有第三份副本。** 所以什么都漂不了，穿过 `LeftPane` / `RightPane` 的宿主看到的是同一批对象。**重复项不设防**：这就是两个普通字符串列表，控件从不拒绝任何字符串。
- **移动按索引进行**：取出的字符串从源里删掉、按**源顺序追加**到目标末尾（不是插入、不是合并、不是排序）。
- **只清源窗格的高亮，而且是在行离开之前清。** 窗格的选择位数组是按索引寻址的，三行里删掉第 1 行会把第 2 行的位滑到顶替它的那一行上——就成了用户从没选过的行上的一个陈旧高亮。**只清源**：目标的行是**追加**的，它原有的什么都没动，用户在那边为「回程」做的选择必须活下来。
- **轨道的 `Enabled` 只说一件事：「这个移动有东西可搬」。** 它**不**受穿梭框自身 `Enabled` 的门控——禁用的父窗口本来就会拒绝子控件的输入，这个库里也没有别的容器会手动把子控件变灰。
- **轨道不是 tab 站点**（`TabStop := False`）：穿梭框是从窗格里驱动的，两个列表中间夹四个箭头会让 Tab 在控件正中间爬行。点击仍然能聚焦按钮，所以它的焦点环还在。
- **窗格与按钮不是设计器里的子控件**（`csNoDesignVisible`，且在任何东西碰 `Visible` **之前**就设好——设计期的可见状态是在 `Visible` 变化时重新求值的）。控件也**不带 `csAcceptsControls`**：窗格和轨道填满了整个框，让设计器往穿梭框里「丢」一个控件只会丢到某个 listbox 上。
- **窗格跟随的是 `SetBounds`，不是 `Resize`。** 父窗体没有句柄时 LCL 会整个抑制 `Resize`（`AutoSizeDelayed`）——那是每一次 headless 测试，**也是设计器流式加载窗体的每一刻**。`SetBounds` 是唯一总会跑的接缝。同理 `CurrentLayout` 用的是 `Width`/`Height` 而不是 `ClientRect`（无句柄时后者会滞后于 `SetBounds`；对这个无边框自绘控件，运行期两者本就相同）。
- **窗格的 `Items.OnChange` 属于穿梭框，但它是「串接」而不是「抢走」。** `TTyListBox` 用自己的 `Items.OnChange` 让选择位数组 / `ItemIndex` / `TopIndex` 跟上列表，而一个 `TStrings` 只有**一个**处理器的位置；我们必须也知道编辑发生了（「全部」箭头依赖的是**行数**，而没有任何选择事件会报告它），于是构造时捕获 listbox 自己的处理器并**先调用它**。析构时会把处理器**还回去**（而不是置 `nil`）：字符串列表在清空时会触发 `OnChange`，而我们的处理器会去读继承的析构函数正在拆解的字段和兄弟子控件。
- **标题用主题样式，不读 LCL `Font`：** 遵循「主题锁定」约定，改字号 / 字色请改主题令牌或用 `StyleClass` / `StyleOverride`。
- **主题想让轨道不一样，改的是 `TyButton.<StyleClass>`：** 穿梭框自己不给箭头设任何 `StyleClass`，所以那条通道归宿主，入口是 `MoveButton` 属性。
