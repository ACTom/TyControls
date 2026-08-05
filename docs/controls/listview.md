# TTyListView

## 1. 概述

`TTyListView` 是 TyControls 的**平铺项视图**——TreeView 的非层级兄弟。它提供报表(带列、排序、拖拽改列宽)、列表、大图标、小图标、平铺共五种视图模式,单选与多选,以及一个**虚拟模式**:控件不拥有任何行对象,数据由回调按需提供。十万个文件的目录因此不会产生十万个对象。

它不继承 `TTyTreeView`,也不与它共享绘制核心 —— TreeView 的 `RenderTo` 是一个绑死节点树的非虚方法,且只会自上而下堆叠整宽行,表达不了图标/平铺模式的流式布局。两者共享的只有**列模型**(`tyControls.Columns`);**主题 token 各归各的**,见下一节。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ListView`(几何在 `tyControls.ListView.Layout`,列/表头模型在 `tyControls.Columns`) |
| `GetStyleTypeKey` 返回值 | `'TyListView'` |
| 基类 | `TTyCustomControl` |

**本控件自成一套 typeKey,不再借用树的键。** 它画的是图标 / 平铺 / 小图标流式格、可横向滚动的报表列带、网格线、可折叠的分组带和框选橡皮筋 —— 树没有这些部件。此前它整体解析 `TyTreeView`,皮肤既没法让一个资源管理器式的文件列表与大纲树长得不一样,连**列头带**和**分组带**都分不开(两者曾解析同一个 `TyTreeHeader` 字面量)。现在的部件表:

| typeKey | 画什么 |
|---|---|
| `TyListView` | 外框:背景、边框、圆角、内边距、基准字号 |
| `TyListViewItem` | 一行 / 一个流式格,按 `:hover` / `:selected` / `:disabled` 取状态 |
| `TyListViewHeader` | 报表模式的列头**带**(整条) |
| `TyListViewHeaderSection` | 列头带里的**单个**列头格,含 `:hover` / `:selected` |
| `TyListViewGroupHeader` | 可折叠的分组带(与列头带彻底分开) |
| `TyListViewCheckBox` | 行首复选框,勾选态取 `:active` |
| `TyListViewLine` | `GridLines` 的行/列格线 |
| `TyListViewMarquee` | 空白处拖拽的框选橡皮筋 |

> `TyListViewLine` 与 `TyListViewMarquee` 是**可选钩子**:`themes/light.tycss` 有意不定义它们,绘制侧各有一条后备链 —— 格线回落到外框的 `border-color`,橡皮筋回落到 `TyListViewItem:selected` 的背景、再回落到外框边框色。皮肤想改就写一条 `background:`,不写则维持原样。橡皮筋的**色相**来自主题,只有半透明度是固定常数。

```pascal
uses tyControls.ListView, tyControls.ListView.Layout, tyControls.Columns;
```

---

## 3. 两套索引 —— 用之前必须先弄清

控件内部同时存在两种索引,**都是 `0..ItemCount-1` 的整数,编译器不会帮你区分**:

| 名称 | 含义 | 出现在哪 |
|---|---|---|
| **item index** | 稳定标识,与排序无关 | **所有 public / published 成员和所有事件** |
| **display 位置** | 排序后的可见次序 | 仅控件内部(`protected` 及以下) |

规则很简单:**你在外面看到的每一个 `AIndex` 都是 item index。** 排序不改变它。所以:

```pascal
LV.Selected[3] := True;
LV.SortColumn := 1;
LV.Sort;
// Selected[3] 仍然是 True,ItemIndex 仍然是 3 —— 只是它在屏幕上换了位置
```

后代若需要知道"第 N 行显示的是哪个 item",用 protected 的 `DisplayToItem(APos)` / `ItemToDisplay(AIndex)`。

---

## 4. 数据从哪来

取数只有一个入口 —— 四个 protected 虚方法:

```pascal
function GetItemCount: Integer; virtual;
function GetItemText(AIndex, AColumn: Integer): string; virtual;
function GetItemImageIndex(AIndex, AColumn: Integer): Integer; virtual;
function GetItemState(AIndex: Integer): TTyListItemStates; virtual;
```

绘制、命中、排序、首字母定位**全部**只调这四个,控件里没有第二处 `if OwnerData`。它们的默认实现有两种后备:

**① 自带集合(`OwnerData = False`,默认)**

```pascal
with LV.Items.Add do
begin
  Caption := 'report.docx';        // 第 0 列
  SubItems.Add('12 KB');           // 第 1 列
  SubItems.Add('2026-07-10 08:30'); // 第 2 列
  ImageIndex := 2;
end;
```

**② 虚拟模式(`OwnerData = True`)** —— 大目录用这个

```pascal
LV.OwnerData := True;
LV.ItemCount := 100000;            // 零行对象
LV.OnGetItemText := @GetText;

procedure TForm1.GetText(Sender: TObject; AIndex, AColumn: Integer; var AText: string);
begin
  case AColumn of
    0: AText := FFiles[AIndex].Name;
    1: AText := FFiles[AIndex].SizeText;
  end;
end;
```

**③ 后代重写** —— `TTyShellListView` 走的就是这条:override `GetItemCount` + `GetItemText` 即可,不需要接口、不需要事件。

> **虚拟模式的失效防护:** 控件观察不到你改自己的存储。改完 `ItemCount` 或底层数据后**必须调 `ItemsChanged`**,它会重设内部数组长度、把 `ItemIndex` / 锚点钳回范围、按需重排。绘制与命中对越界索引一律防御性钳制,不会崩,但选中状态可能已经不是你想要的。批量修改用 `BeginUpdate` / `EndUpdate` 包住。

---

## 5. 排序

```pascal
LV.SortColumn := 1;                 // -1 = 不排序
LV.SortKind := lskNumber;           // lskText / lskNumber / lskDateTime
LV.SortDirection := sdDescending;
LV.Sort;
```

- 排序**只置换内部的显示顺序,从不改动 `Items`**。所以一个不可变的数据源(shell 目录)也能排序。
- 平局按 item index 兜底,**排序是稳定的**。
- `AutoSort = True`(默认)时点击表头即排序,并切换升/降序。
- `lskNumber` / `lskDateTime` 解析不了的单元格**永远排在最后,与升降序无关** —— 按大小降序排文件,你想看到的是最大的文件在顶上,不是一堆空白。
- `lskDateTime` 只认 ISO 格式(`2026-07-10` / `2026-07-10 08:30`),避免排序结果依赖机器 locale。文本更花哨的列请用 `OnCompare`。
- `OnCompare` 已接则完全接管比较,收到的是两个 **item index**。

---

## 6. 属性表

### 视图

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `ViewStyle` | `TTyListViewStyle` | `lvsReport` | `lvsIcon` / `lvsSmallIcon` / `lvsList` / `lvsReport` / `lvsTile`,运行时可切 |
| `RowHeight` | `Integer` | `22` | 报表模式行高(逻辑像素,自动按 DPI 缩放) |
| `Header` | `TTyHeader` | — | 列模型子对象,`Header.Columns` 是列集合 |
| `Columns` | `TTyColumns` | — | **public(不 published)**,就是 `Header.Columns` 那个对象。`LV.Columns[0].Width := 120` 是所有移植过来的列代码的写法(LCL `comctrls.pp:1582`),以前必须多绕一层 `Header`。不 published 是故意的:`Header` 已经在流式化这个集合,再开一条 published 路径会把它写进 .lfm 两次 |
| `Column[AIndex]` | `TTyColumn` | — | **public**,第 i 列;越界返回 `nil`(不抛异常,与本控件其它 index-first 接口一致) |
| `ColumnCount` | `Integer` | — | **public**,列数(LCL `comctrls.pp:1665`) |
| `ShowColumnHeaders` | `Boolean` | `True` | 报表模式是否画表头带 |
| `GridLines` | `Boolean` | `False` | 报表模式行/列网格线 |
| `RowSelect` | `Boolean` | `True` | 整行高亮,而非仅第 0 列 |
| `HotTrack` | `Boolean` | `False` | 鼠标悬停高亮 |
| `LargeImages` | `TTyVirtualImageList` | `nil` | `lvsIcon` / `lvsTile` 用 |
| `SmallImages` | `TTyVirtualImageList` | `nil` | 其余模式用；表头列图标在 `Header.Images` 为空时也取它 |
| `Header.Images` | `TTyVirtualImageList` | `nil` | **列头图标**的图像源，按 `TTyColumn.ImageIndex` 取图；为空时回退到 `SmallImages` |

#### 列头图标

给某一列设 `ImageIndex`(>= 0),该列的表头就会在标题**左边**画出对应图标,标题相应右移让位:

```pascal
LV.SmallImages := ImgList;                                        // 或 LV.Header.Images := HdrImgList;
(LV.Header.Columns.Items[0] as TTyColumn).ImageIndex := 0;
```

图标取自 `Header.Images`;它为 `nil` 时改取 `SmallImages`——Delphi / LCL 的
`TListColumn.ImageIndex` 本来就是按列表控件的 `SmallImages` 解析的(`TListView` 根本没有
单独的表头图像列表),所以这个回退就是移植过来的代码所期望的行为;`Header.Images` 是给
表头想用自己那一套图时的**覆盖**。一旦设了 `Header.Images`,它就说了算,不会再回退。

图标槽宽与图标到标题的间距走主题令牌 `--listview-header-icon-size` /
`--listview-header-icon-gap`(默认与小图标边长、文字内距一致,所以没有图标的表头分毫未变)。

### 数据

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Items` | `TTyListItems` | — | 自带集合(`OwnerData = False` 时生效) |
| `OwnerData` | `Boolean` | `False` | 虚拟模式开关 |
| `ItemCount` | `Integer` | `0` | 虚拟模式下的行数 |

### 分组视图

| 属性 / 事件 | 说明 |
|---|---|
| `GroupView: Boolean` | 打开后按 `Groups` 把项分成可折叠的组;`lvsList`(列优先)不支持分组,会忽略此开关 |
| `Groups: TTyListGroups` | 组集合,每组有 `Caption` 和 `Collapsed` |
| `TTyListItem.GroupIndex` | 项属于哪个组(item index → 组序号);无效值归入末尾的**隐式桶**(无组头) |
| `OnGetItemGroup` | 虚拟模式取组:`(Sender; AIndex; var AGroup)` |
| `OnGroupCollapsed` | **点击组头**折叠 / 展开后触发(程序性 `Collapsed :=` 不触发) |

> **折叠一个组,里面的选中和勾选不丢。** 展开回来还在。因为选中态按 **item index** 存,而"可见顺序"
> 只是折叠时把该组的项从显示序里抽走 —— 和排序不动数据是同一套机制。`SelectAll` 选中**全部**项(含
> 折叠组里的);`ScrollIntoView` 一个折叠组里的项是 no-op(不自动展开)。

### 复选框 / 重命名

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Checkboxes` | `Boolean` | `False` | 每行左侧画一个复选框(自己的 `TyListViewCheckBox` token,与树的复选框可分开配色) |
| `ReadOnly` | `Boolean` | `True` | **默认禁止改名**。这与 LCL `TListView.ReadOnly = False` 相反,是有意的:文件对话框的文件面板不该因为误按 F2 就进入改名。设 `False` 才能 F2 重命名 |

| 成员 | 说明 |
|---|---|
| `Checked[AIndex]: Boolean` | 勾选态(item index)。读 = `lisChecked in GetItemState(i)` |
| `BeginEdit(AIndex)` / `EndEdit(ACommit)` / `Editing` | 行内重命名 |
| `OnItemChecked` | 勾选变化,收 item index |
| `OnEditing(Sender; AIndex; var AAllow)` | `AAllow := False` 否决改名 |
| `OnEdited(Sender; AIndex; var AText)` | 提交前触发;可改写 `AText`;**置 `''` 视为放弃**(用户自己清空也一样) |

### 结构通知(内置集合模式)

| 事件 | 说明 |
|---|---|
| `OnInsert(Sender; AIndex)` | 一行**刚刚**加入内置集合之后触发(LCL `comctrls.pp:1613`) |
| `OnDeletion(Sender; AIndex)` | 一行**即将**离开内置集合之前触发(LCL `comctrls.pp:1610`)。`Items.Clear` 和控件析构时**逐行**触发 |

> **`OnDeletion` 是 `Data` 里那个「归你所有」的对象唯一的释放时机**——它触发时行还在、索引还有效、`Items[AIndex].Data` 还读得到。
> 在此之前 `TTyListItems` 是个 `TCollection`,`Notify` 是 protected 且已被控件自己消费掉,应用除了派生集合类之外**没有任何**钩子,于是每一个这样的载荷都漏掉了。
>
> 控件析构时也会逐行触发,所以析构顺序已相应调整:**先放 `Items`(通知期间控件仍然完整,处理器可以回调),再放 `Header`**。
>
> `OwnerData` 模式下两者都不触发:那里没有集合生命周期可报告,存储本来就是应用自己的。

> **勾选态和选中态一样,按 item index 存,跨排序稳定。**
>
> ⚠️ **`OwnerData` 模式下控件不缓存勾选态。** 点击和 `Space` 算的是 `not Checked[i]`,而 `Checked[i]`
> 读的是你的 `OnGetItemState`。所以你**必须**在 `OnItemChecked` 里改自己的存储 —— 否则
> `GetItemState` 永远返回旧值,勾选框看起来点不动。这是"控件不拥有数据"的必然代价,和
> `OnEdited` 必须自己写回标题是同一回事。

### 排序 / 选择

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `SortColumn` | `Integer` | `-1` | `-1` = 不排序 |
| `SortDirection` | `TTySortDirection` | `sdAscending` | |
| `SortKind` | `TTyListSortKind` | `lskText` | 内建比较器用哪种 |
| `AutoSort` | `Boolean` | `True` | 点表头排序 |
| `MultiSelect` | `Boolean` | `False` | |

### 选择相关的 public 成员

| 成员 | 说明 |
|---|---|
| `ItemIndex: Integer` | 焦点项(item index),`-1` = 无。**赋值即独占选中**(focus-selects,同 `TTyTreeView.SetFocusedNode`);赋一个不存在的索引一律变成 `-1`,不会钳到最近的行 |
| `Selected[AIndex]: Boolean` | 选中态(item index)。**置位不移动焦点** —— 它是"选中",不是"聚焦" |
| `SelCount: Integer` | |
| `SelectAll` / `ClearSelection` | |
| `GetNextSelected(var AIndex): Boolean` | 传 `-1` 取第一个,按 item index 升序遍历 |
| `GetItemAt(X, Y): Integer` | 命中测试 → item index,未命中 `-1` |
| `GetHitPart(X, Y): TTyListHitPart` | 命中到哪个部件(表头 / 分隔线 / 标签 / 无) |
| `ScrollIntoView(AIndex)` | |
| `AutoFitColumn(AColumn)` | 把列宽调整到刚好容纳表头标题与单元格文字。**双击列右侧的分隔线**触发同一逻辑 |

> `MultiSelect := False` 折叠选择集时的**确定顺序**:① 焦点项在范围内 → 留它;② 否则若有选中位 → 取**第一个选中位**作为焦点(因为 `Selected[i] := True` 不移动焦点,可能出现"有选中、无焦点",此时静默清空是错的);③ 否则空。

### 事件

| 事件 | 说明 |
|---|---|
| `OnGetItemText` / `OnGetItemImage` / `OnGetItemState` | 虚拟模式取数 |
| `OnCompare` | 自定义比较,收两个 item index |
| `OnColumnClick` | 点击表头分区 |
| `OnSelectItem(Sender; AIndex: Integer; ASelected: Boolean)` | 某一项的选中状态**翻转**了:被选上 → `ASelected = True`,被放开 → `False`。**一次操作会为每一个翻转的项各触发一次** |
| `OnChanging(Sender; AIndex; AChange: TTyItemChange; var AAllowChange: Boolean)` | 选择变化**之前**触发,置 `AAllowChange := False` 即否决——控件不动选择位,后续的 `OnChange` / `OnSelectItem` 也都不发 |
| `OnChange(Sender; AIndex: Integer; AChange: TTyItemChange)` | 变化**之后**触发,说明是哪一项、变的是什么 |
| `OnItemActivate` | 双击 / Enter |

`TTyItemChange = (ctText, ctImage, ctState)`——与 LCL 的 `TItemChange` 逐值对应,所以从 `TListView`
处理器里搬过来的 `case AChange of` 不用改就能编译。`ctImage` 是为这份对齐而声明的,**内建数据路径
从不发它**:本控件没有逐项的图像可改(图像是数据源对 `GetItemImageIndex` 的回答),自带图像存储的
后代可以通过 protected 的 `DoChange` 发出来。

`AIndex = -1` 表示**一次没有单一主语的批量变化**(全选、清空选择、框选一片、`MultiSelect` 关闭时的
选择集折叠),对应 LCL 的 `Item = nil`。

> **三个事件槽永远属于应用。** 库内部的行为挂在 protected 虚方法 `DoChange` / `CanChange` /
> `DoSelectItem` 上,不占用 published 的事件——否则应用赋值上去的处理器会静默地什么也不做。
>
> **`OnSelectItem` 现在是状态增量**:重复选中一个已选中的行**不再**触发它(这是 LCL 的行为)。
> 从前它只在"选上"时发,应用**分辨不出"第 3 行被选中了"和"第 3 行被放开了"**——后者根本收不到事件。
> 改选一行现在会收到两次:旧行 `False`、新行 `True`。
>
> **重命名与勾选框有各自的否决口**(`OnEditing` / `OnItemChecked`),不走 `OnChanging`,不会被否决两次。

---

## 7. 交互

- **鼠标**:单击选中;`Ctrl` 加选;`Shift` 区间选;空白处拖拽框选(marquee);双击触发 `OnItemActivate`;拖拽表头分隔线改列宽;点击表头分区排序;滚轮沿当前视图的滚动轴滚动。
  鼠标移到表头分隔线上时光标变为 `crHSplit`,判据与 `MouseDown` 完全相同(都走 `GetHitPart`),所以"光标暗示能拖"和"按下去真能拖"不可能不一致。移开后**恢复应用自己设的 `Cursor`**,而不是粗暴地置为 `crDefault`。
  **双击分隔线** = `AutoFitColumn(该列)`,把列宽调到刚好容纳内容。

> **自适应宽度只采样前 500 行。** 资源管理器会量遍所有行,但 BGRA 的文字测量对一个 10 万行的虚拟列表来说太慢了。普通列表(行数不超过 500)因此是**精确**贴合;超出的部分按前 500 个显示行估算。宽度里还预留了排序箭头的位置(不管当前是否按该列排序),所以点击表头排序时列宽不会跳。
- **键盘**:方向键二维网格导航(图标模式下 ↑↓ 跨行、←→ 跨列;列表模式相反);`Home` / `End`;`PageUp` / `PageDown`;`Ctrl+A` 全选;`Space` 切换选中;`Enter` 触发 `OnItemActivate`;直接敲字母做**首字母定位**(按屏幕上看到的顺序查找,重复敲同一字母循环到下一个匹配)。

---

## 8. 自定义绘制

```pascal
protected
  procedure RenderItem(P: TTyPainter; AIndex: Integer; const ACell: TRect;
    const AStyle: TTyStyleSet; AStates: TTyStateSet); virtual;
```

后代重写它即可接管单项的绘制。`ACell` 是客户区坐标,`AStyle` 是已按 `AStates` 解析好的 `TyListViewItem` 样式。这是 `TTyTreeView` 一直没有的 per-item 接缝(它的 `RenderTo` 非虚且绑死节点)。

---

## 9. 设计取舍

- **单元格尺寸恒定。** 这是 O(1) 闭式虚拟化窗口(`TyListVisibleRange` 不遍历任何项)的前提。因此**不支持可变行高与单元格自动换行** —— 需要那些就得引入 TreeView 那套位置缓存。
- **几何全在纯函数里。** 布局、命中、网格导航、框选、首字母定位、排序比较器都在 `tyControls.ListView.Layout`,无窗口、无 painter、可无头单元测试。`TyListItemRect` 是绘制与命中**唯一**的几何来源,`TyListItemAt` 内部回调它做 `PtInRect` 校验 —— 两者不可能漂移。
- **列的横轴同理。** report 模式下列的屏幕跨度只出自 `TyColumnSpan`(`tyControls.Columns.pas`):
  报表行、表头格、网格竖线三处绘制,以及 `ColumnFromPosition` / `DetermineSplitterIndex`
  两个命中函数,都从它取 `Left`/`Right`,自己不算坐标。它取的是**原点**而不是滚动量 ——
  正因如此,本控件的 `FOffsetX >= 0`(传 `-FOffsetX`)与 `TTyTreeView` 的 `FOffsetX <= 0`
  (传 `+FOffsetX`)才能共用同一个公式,而不必各写一遍符号。
- **富缩略图网格不属于这里。** 图标/平铺只做定尺流式格。

---

## 10. 示例

见 [examples/listview](../../examples/listview/)。
