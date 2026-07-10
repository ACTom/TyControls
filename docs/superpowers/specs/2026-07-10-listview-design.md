# TTyListView 设计

> 状态:**待批准**。批准后转 `docs/superpowers/plans/2026-07-10-listview.md` 实施计划。
> 上游:`docs/superpowers/specs/2026-07-05-controls-expansion-roadmap.md`(Phase 8 → 提前)

## 为什么现在做

TTyListView 原本排在 Phase 8(最后一期)。但重读路线图发现 **Phase 7 反向依赖它**:

- `TTyShellListView` 的规格写着 "(over **TTyListView**)"
- `TTyFileListView`、`TTyDirTreeView` 都是 list/tree 视图
- 自绘 `TTyOpenDialog` / `TTySaveDialog` 的文件面板就是一个 ListView

而 `TTyListView` 在 `source/` 里不存在。路线图"Shell + file dialogs (7) — build on the views"这句里的 views,有一半还没造。所以把它从 Phase 8 单独提前;`TTyGrid` 仍留在最后,单独出设计稿。

## 摸底结论(已逐条核实)

| 事实 | 出处 |
|---|---|
| `TTyTreeView.RenderTo` **不是 virtual**,1034 行,循环里直接读 `node^.Parent / States / CheckType` | `tyControls.TreeView.pas:535` 声明、实现 1034 行 |
| TreeView 单元里 **0 个纯自由函数** | `grep -c "^function Ty"` = 0 |
| TreeView **没有** OwnerData / 虚拟数据模式 | `grep -ci ownerdata` = 0 |
| 列模型与 TreeView **零耦合** | `tyControls.Columns.pas` 只 `uses Classes, SysUtils, Math, ImgList` |
| 主题 token `TyTreeView` / `TyTreeNode` / `TyTreeHeader` / `TyTreeHeaderSection` / `TyListItem` 均已存在 | `themes/light.tycss:474-483, 201` |

推论:

1. **不能继承 `TTyTreeView`,也不能从它抽基类。** 它的绘制核心是一个非虚的、绑死节点树的巨函数;抽基类要重写绘制核心,直接威胁 golden 快照和 2437 个测试。这与 Phase 3 里 `TTyRibbon` 复用 `TTyCustomTabStrip` 不同 —— TabStrip 本来就是按模板方法写的,TreeView 不是。
2. **列模型原样复用。** 已在 `a1f8bc0` 里把它从 TreeView 命名空间搬到 `tyControls.Columns`(`TTyColumn` / `TTyColumns` / `TTyHeader`),旧名保留为弃用别名 + 兼容 shim。62 个既有列测试继续覆盖它。
3. **零新增主题 token 可达。** `GetStyleTypeKey` 返回 `'TyTreeView'`,行解析 `'TyTreeNode'`,表头解析 `'TyTreeHeader'` / `'TyTreeHeaderSection'`。不动 6 个 `.tycss`、不动 `DefaultTheme.pas` / `BuiltinThemeData.pas`、不重生成 golden。
4. TreeView 之所以至今只能靠眼睛验,正是因为它没有一行纯函数。**新控件必须反着来。**

## 架构

```
tyControls.Columns          (已有,复用)  列模型 + 列命中 + 分隔线命中 + 自动宽度 + 弹性分配
tyControls.ListView.Layout  (新,纯函数)  流式布局 / 命中 / 网格导航 / 区间选择 / 比较器 / 类型前缀匹配
tyControls.ListView         (新,控件)    TTyListView = class(TTyCustomControl)
```

`TTyTreeView` 源码**一行不动**,其测试因此按构造保持绿色。

### 基类

`TTyCustomControl`(窗口化)。理由和 `TTyTreeView` / `TTyListBox` / `TTyScrollBox` 一样:要键盘焦点做网格导航与首字母定位、要真实 HWND 承载内嵌的 `TTyScrollBar` 子控件、要 MouseCapture 做表头拖拽与框选。`TTyGraphicControl` 三样都没有。

### 数据从哪来 —— 单一取数口

这是三份候选设计唯一分歧的地方,也是本设计唯一的架构决策。

**取数走 protected virtual 方法。** 这是本库既有的接缝风格(`TTyListBox.PaintItemContent`、`TTyComboBox.SelectItem` / `CreatePopupList` / `DoPopupPick` 全是这样开的),不是新约定:

```pascal
protected
  function GetItemCount: Integer; virtual;
  function GetItemText(AIndex, AColumn: Integer): string; virtual;
  function GetItemImageIndex(AIndex, AColumn: Integer): Integer; virtual;
  function GetItemState(AIndex: Integer): TTyListItemStates; virtual;
```

默认实现:`OwnerData = True` 时转发到 `OnGetItemText` / `OnGetItemImage` / `OnGetItemState` 事件(照抄 LCL `TListView` 的约定);否则读自带的 `Items: TTyListItems` 集合。

**绘制路径只有一条** —— 它只调这四个虚方法,永远不分支判断"现在是虚拟模式还是集合模式"。

后果:

- 10 万个文件的目录 → 虚拟模式,**零行对象**。
- `TTyShellListView` → override 两个虚方法,不实现接口、不碰 refcount。
- 自带集合只是这些虚方法的默认后备存储,不是必需品。

**明确否决的方案:** 一个 `ITyListDataProvider` 接口 + `TTyEventListProvider` + `providerIndex/displayPos` 双坐标系。它在"Phase 7 适配性"和"可测性"两项上评分最高,但引入了本库没有先例的接口约定,且提出它的设计自己把双坐标称作 "a bug magnet"。虚方法接缝拿到它的全部收益,不付这份税。

### 排序与选择 —— 稳定 index

排序**只置换一个 `FOrder: array of Integer`**(display 位置 → item index),从不改动底层数据。选择集是 `array of Boolean`,**按稳定的 item index 存**。

于是:重排序、切换视图模式之后,选中项不跑。而且 shell provider 的数据本来就不可变 —— 一个"排序时改写自带集合"的设计在 Phase 7 会当场撞墙。

代价:公开 API 必须逐个写清楚它收/返的是哪个 index。约定:

- **item index**(稳定):`Selected[]`、`ItemIndex`、`GetItemText`、`OnCompare`、所有事件
- **display 位置**(排序后):仅限布局 / 命中 / 绘制内部,不出现在公开 API 里

### 绘制接缝

```pascal
protected
  procedure RenderItem(P: TTyPainter; AIndex: Integer; const ACell: TRect;
    const AStyle: TTyStyleSet; AStates: TTyStateSet); virtual;
```

正是 TreeView 缺的那个 per-item 接缝。`RenderTo` 按 `ViewStyle` 分派到流式路径(icon/smallicon/list/tile)或报表路径,两条都调 `RenderItem`。

### 纯函数(新单元 `tyControls.ListView.Layout`)

无窗口、无 painter、无句柄。控件把设备像素喂进去,拿几何和索引出来。

```pascal
type
  TTyListViewStyle = (lvsIcon, lvsSmallIcon, lvsList, lvsReport, lvsTile);
  TTyListNavKey    = (lnLeft, lnRight, lnUp, lnDown, lnHome, lnEnd, lnPageUp, lnPageDown);
  TTyListSortKind  = (lskText, lskNumber, lskDateTime);
  TTyListHitPart   = (lhpNowhere, lhpIcon, lhpLabel, lhpCheck, lhpHeader, lhpDivider);
  TTyListMetrics   = record
    ViewStyle: TTyListViewStyle;
    ViewportW, ViewportH: Integer;
    CellW, CellH, IconPx, LabelH, HGap, VGap, RowH, HeaderH: Integer;   { 全设备像素 }
  end;

  TTyItemTextFn = function(AIndex: Integer): string of object;

function TyListCellSize(const M: TTyListMetrics): TSize;
function TyListTracks(const M: TTyListMetrics): Integer;
function TyListContentExtent(ACount: Integer; const M: TTyListMetrics): TSize;
function TyListItemRect(ADisplayPos, ACount: Integer; const M: TTyListMetrics;
  AScrollX, AScrollY: Integer): TRect;
function TyListItemAt(const APt: TPoint; ACount: Integer; const M: TTyListMetrics;
  AScrollX, AScrollY: Integer): Integer;
function TyListVisibleRange(ACount: Integer; const M: TTyListMetrics;
  AScrollX, AScrollY: Integer; out AFirst, ALast: Integer): Boolean;
function TyListNavigate(ACurrent, ACount: Integer; AKey: TTyListNavKey;
  const M: TTyListMetrics): Integer;
function TyListRangeBounds(AAnchor, ATarget: Integer; out ALo, AHi: Integer): Boolean;
function TyListMarqueeHits(const ABox: TRect; ACount: Integer; const M: TTyListMetrics;
  AScrollX, AScrollY: Integer; out ALo, AHi: Integer): Boolean;
function TyListPrefixMatch(AGetText: TTyItemTextFn; ACount, AStartAfter: Integer;
  const APrefix: string): Integer;
function TyListCompareCells(const A, B: string; AKind: TTyListSortKind;
  ADir: TTySortDirection): Integer;
function TyReportRowAt(AY, AScrollY, AHeaderH, ARowH, ARowCount: Integer): Integer;
```

两条纪律:

1. **`TyListItemRect` 是唯一的几何来源** —— 绘制和命中都调它,两者不可能漂移。这条抄自 TreeView 的 `InternalCellRect`,是它为数不多做对的事。
2. **`TyListPrefixMatch` / `TyListMarqueeHits` 收回调,自己循环**,而不是"控件循环、函数只判一格"。整个首字母定位和框选因此都能无头测试。

单元格尺寸**恒定**,所以 `TyListVisibleRange` 是 O(1) 闭式解,不需要 TreeView 那套 `FPositionCache`。代价见下方非目标。

### 报表模式的 x 轴

全部来自 `tyControls.Columns`,不重造:`UpdatePositions` / `ColumnFromPosition`(列命中)/ `DetermineSplitterIndex`(分隔线命中)/ `ApplyAutoSize` / `DistributeSpring`。表头是 `TTyHeader`(`TPersistent` 描述符),由控件内联绘制,不是子控件 —— 和 TreeView 一致。

### 滚动条

内嵌两个 `TTyScrollBar` 子控件,构造函数里建、`csNoDesignVisible`(否则会漏进 IDE 设计器,见 [[designer-internal-subcontrol-leak]])。滚动数学复用 `tyControls.ScrollBox` 的纯函数,不重新推导 —— 双轴滚动条互相抢占对方视口的那个 off-by-one,是经典坑。

## 范围

### SP1 —— Phase 7 真正依赖的部分(先合并)

- `ViewStyle`:`lvsReport` / `lvsList` / `lvsIcon` / `lvsSmallIcon` / `lvsTile`,运行时可切
- 报表模式:列 + 表头 + 点击表头排序 + 拖拽改列宽 + `GridLines`
- 数据:自带 `TTyListItems` 集合 **和** `OwnerData` 虚拟模式(同一条绘制路径)
- 选择:单选 + `MultiSelect`(Ctrl / Shift / Ctrl+A)、`Selected[]`、`SelCount`、`GetNextSelected`
- 排序:`SortColumn` / `SortDirection` / `AutoSort` / `OnCompare`,`FOrder` 置换,选中项跨排序稳定
- 图标:`LargeImages` / `SmallImages`(`TTyVirtualImageList`)
- 键盘:二维网格导航、首字母定位、`PageUp/Down`、`Home/End`
- 鼠标:滚轮、双击 `OnItemActivate`、`GetItemAt` / `GetHitPart`、框选(marquee)
- `ScrollIntoView`、`BeginUpdate` / `EndUpdate`、`ItemsChanged`

### SP2 —— 用户点名要、但不挡 Phase 7

- 行内重命名(F2 编辑标题)。**抄 `TTyValueListEditor` 那 8 条行内编辑器检查表**(`csDestroying` 守卫、Sorted 列表提交、Controller 下传、滚动时提交并关闭、按行标识而非索引提交、焦点归还)。虚拟模式下它只能发 `OnEdited(index, newText)` 让 app 改自己的存储 —— TreeView 可以直接写节点文本,这里不行。
- 行首复选框(`Checkboxes` + `OnItemChecked`)
- 分组视图(`GroupView`)—— 会让流式布局的纯函数复杂一档

### 非目标(明确不做)

- **可变行高 / 单元格自动换行。** 恒定单元格尺寸是 O(1) 闭式虚拟化的前提。要变高就得引入 TreeView 那套位置缓存。这是真实的天花板,现在接受。
- **富缩略图网格。** 那是 Phase 8 的 `TTyGridView`。icon/tile 只做定尺流式格。
- **从 `TTyTreeView` 抽公共基类。** 见上文。若日后要做,必须是独立的重构,并且逐字节复现 golden 快照 —— 绝不放在 Phase 7 的关键路径上。
- **新增主题 token。** 未来若真需要 ListView 专属外观,再起 `TyListView` / `TyListViewItem`,那时要同步 8 个文件 + 重生成 golden。现在推迟是对的,但这是一笔已知的将来成本。
- DB 绑定 / 富文本 —— 路线图早已排除。

## 风险

| 风险 | 缓解 |
|---|---|
| 虚拟模式下控件观察不到 app 改动自己的存储,`FOrder` / 选择位可能失效或越界 | 强制 `BeginUpdate` / `EndUpdate` + 显式 `ItemsChanged`;绘制和命中对超出 `ItemCount` 的陈旧索引一律防御性钳制,不得崩 |
| 虚拟排序会调 `GetItemText` 约 `n log n` 次(10 万行 ≈ 170 万次)。若 `OnGetItemText` 背后是昂贵的 shell PIDL→显示名,排序会卡 | SP1 不解决。接缝要留好:日后可加可选的 `GetSortKey(AIndex, AColumn)` 虚方法或控件侧缓存,不破坏现有签名 |
| 报表 + 流式两套布局 = 两条代码路径、两张测试矩阵 | 两条都收敛到 `TyListItemRect`;测试矩阵按 `ViewStyle` 参数化 |
| 首字母定位、行内编辑器与 TreeView 存在 ~30-50 行平行逻辑 | 把可纯化的部分(前缀匹配、区间选择)做成共享纯函数;字段管道的重复暂时接受,不在 Phase 7 关键路径上做提取 |

## 验收

- 全量测试仍为 **0 失败**;新增测试全部针对纯函数(无窗口)。
- `themes/*.tycss`、`tyControls.DefaultTheme.pas`、`tyControls.BuiltinThemeData.pas`、`tests/golden/*` **零改动**。
- `source/tyControls.TreeView.pas` **零改动**。
- 调色板图标 + 漂移守卫同步(`gen-icons.ps1` 输出 "130 registered components all have icons")。
- `examples/listview` 可双击运行:报表 + 四种视图切换 + 排序 + 多选 + 一个 10 万行的虚拟模式页签(证明零对象)。
- 对抗性审查:按维度(布局几何 / 选择与排序 / 绘制与主题 / 组件与流式化)分别评审,逐条反驳。

## 之后

`TTyListView` 落地即解锁 Phase 7:`TTyShellListView`(override 两个虚方法)、`TTyFileListView`、`TTyDirTreeView`,以及自绘 `TTyOpenDialog` / `TTySaveDialog` 的文件面板。
