# TTyListView SP2b 契约 —— 分组视图

> 前置:SP1(`7c39709`)+ SP2a(`6277bb5`)已合并。
> 这是唯一动**纯布局层地基**的一批,所以先做布局单元,单独一次提交,再做控件。

## 地基为什么必须动

SP1 的 `TyListVisibleRange` 是 O(1) 闭式解,前提是**单元格尺寸恒定**。分组之后:

- 单元格在**组内**仍然恒定 → 组内几何还是闭式的;
- 但每组高度 = 组头 + `ceil(Count/Tracks) * PitchY`,**各组不同** → 全局 Y 只能靠**前缀和**;
- 折叠的组只占一条组头。

所以视口→项的映射变成:**在组的前缀和数组上二分**(O(log G)),再在组内闭式求解。项数 10 万、组数 20,
依旧是常数级。**不引入任何按项遍历。**

## 索引不变式的修改 —— 全文最危险的一处

SP1 说:display 位置 ∈ `[0, ItemCount-1]`,`FOrder` 长度 = `ItemCount`。

SP2b 起,**display 位置只覆盖「当前可见」的项**:

| | SP1 | SP2b |
|---|---|---|
| `FOrder` 长度 | `ItemCount` | **可见项数**(折叠组的项不在里面) |
| `FRank` 长度 | `ItemCount` | `ItemCount`(不变) |
| `FRank[i] = -1` | 越界 | 越界 **或 该项在折叠组里** |
| display 位置范围 | `[0, ItemCount-1]` | `[0, VisibleCount-1]` |

未开启分组时 `VisibleCount = ItemCount`,一切退化回 SP1,**现有纯函数一行不改**:
只要把 `ACount` 参数喂成 `VisibleCount` 就对了。

推论(必须逐条测):

- **选择集仍按 item index 存 → 折叠一个组,里面的选中项不丢。** 展开回来还在。
- `SelectAll` 是**数据级**操作,选中**全部**项,包括折叠组里的。
- 首字母定位、键盘导航、框选**只走可见项**(它们本来就只看 display 位置)。
- `ScrollIntoView(i)`,`i` 在折叠组里(`FRank[i] = -1`)→ **静默返回**,不自动展开。
- `SyncArrays` 里的 `Length(FOrder) <> cnt` 判据要改成看 `FRank`。

---

## 任务 1 契约 —— `tyControls.ListView.Layout` 的分组函数

现有函数**一个都不改签名**。新增一组平行 API,控件在 `RenderTo` / 命中 / 导航的顶层分支一次。

### 类型

```pascal
type
  TTyListGroupInfo = record
    Count:     Integer;   { 组内项数,允许 0 }
    Collapsed: Boolean;
    HasHeader: Boolean;   { False = 收容「无有效分组」项的隐式桶,不画组头 }
  end;
  TTyListGroupInfoArray = array of TTyListGroupInfo;

  { 一次布局构建一次的垂直映射。O(G)。 }
  TTyListGroupMap = record
    Groups:       TTyListGroupInfoArray;
    Tops:         TTyIntArray;   { 长度 G+1。Tops[g] = 第 g 组组头带的内容 Y。
                                   Tops[G] = 内容总高。 }
    FirstVisible: TTyIntArray;   { 长度 G+1。FirstVisible[g] = 第 g 组第一项的 display 位置,
                                   只累计**展开**的组。FirstVisible[G] = 可见项总数。
                                   折叠组贡献 0。 }
  end;
```

> **内容 Y 的原点是 item 区顶部**,不含报表模式的列表头(`M.HeaderH`)。所有返回客户区坐标的函数
> 自己加回 `M.HeaderH` 并减去滚动量,和 `TyListItemRect` 一致。

### 函数

```pascal
{ 构建映射。O(G)。AHeaderH = 组头带高度(设备像素);HasHeader=False 的组贡献 0。
  组高 = 组头 + 组体;折叠组只有组头。
  组体:行优先 rows := Ceil(Count/Tracks),body := Max(0, rows*PitchY - VGap);
        lvsReport body := Count * RowH。Count = 0 → body = 0。 }
function TyListBuildGroupMap(const AGroups: TTyListGroupInfoArray;
  const M: TTyListMetrics; AHeaderH: Integer): TTyListGroupMap;

{ 内容总高 = Tops[High(Tops)]。 }
function TyListGroupContentHeight(const AMap: TTyListGroupMap): Integer;

{ 第 g 组的组头带,客户区坐标。HasHeader=False 或 g 越界 → Rect(0,0,0,0)。
  横向铺满 [0, ViewportW],不随 AScrollX 移动(组头不横滚)。 }
function TyListGroupHeaderRect(const AMap: TTyListGroupMap; AGroup: Integer;
  const M: TTyListMetrics; AHeaderH, AScrollY: Integer): TRect;

{ 第 g 组第 i 项的单元格,客户区坐标。**唯一几何来源。**
  g 或 i 越界、或该组折叠 → Rect(0,0,0,0)。 }
function TyListGroupItemRect(const AMap: TTyListGroupMap; AGroup, AIndexInGroup: Integer;
  const M: TTyListMetrics; AHeaderH, AScrollX, AScrollY: Integer): TRect;

{ 与视口相交的组区间(闭区间)。空映射 → False,两个 out 置 -1。
  实现必须在 Tops 上**二分**,不得线性扫描。 }
function TyListGroupVisibleRange(const AMap: TTyListGroupMap; const M: TTyListMetrics;
  AScrollY: Integer; out AFirst, ALast: Integer): Boolean;

{ 命中测试。
  - 命中某项 → True,AGroup/AIndexInGroup 有效;
  - 命中组头带 → True,AIndexInGroup = -1;
  - 未命中(格间间隙、折叠组的组体、列表头带、视口空白)→ False,两个 out 置 -1。
  与 TyListItemAt 同一纪律:先算候选,再用 TyListGroupItemRect 回算 PtInRect 校验。 }
function TyListGroupHitTest(const AMap: TTyListGroupMap; const APt: TPoint;
  const M: TTyListMetrics; AHeaderH, AScrollX, AScrollY: Integer;
  out AGroup, AIndexInGroup: Integer): Boolean;

{ display 位置 ↔ (组, 组内序号)。都只覆盖**可见**项。
  越界 → False / -1。 }
function TyListGroupOfDisplayPos(const AMap: TTyListGroupMap; APos: Integer;
  out AGroup, AIndexInGroup: Integer): Boolean;
function TyListGroupDisplayPos(const AMap: TTyListGroupMap;
  AGroup, AIndexInGroup: Integer): Integer;

{ 跨组的二维网格导航。收/返 **display 位置**(可见项序)。
  - lnLeft/lnRight/lnHome/lnEnd:就是扁平的 display 位置 ±1 / 0 / VisibleCount-1;
    方向键越界不移动(同 SP1)。
  - 行优先的 lnUp/lnDown:先在**组内**按 Tracks 上下移。
    判据是「**本组还有没有下一行 / 上一行**」,**不是**「正下方那格存不存在」——
    最后一行可能是残行(`Count=6, Tracks=4` 时第 2 列下方没有格子),此时应**钳到本组最后一项**,
    而不是当成"越出本组"跳去下一组、把那一行上真实存在的项跳过去。
    只有当前已在本组的**最后一行 / 第一行**,才算越出本组:
      * lnDown 落到**下一个展开且非空**的组的第一行,**保持列号**(不足则取该行最后一项);
      * lnUp 落到**上一个展开且非空**的组的最后一行,同样保持列号;
      * 再没有这样的组 → 不移动。
  - lvsReport 的 lnUp/lnDown = ±1(组头不占 display 位置)。
  - lnPageUp/lnPageDown:按一屏格数移动并钳位到 [0, VisibleCount-1]。 }
function TyListGroupNavigate(const AMap: TTyListGroupMap; ACurrent: Integer;
  AKey: TTyListNavKey; const M: TTyListMetrics): Integer;
```

### 明确不支持

- **`lvsList`(列优先)不支持分组。** 它横向流、横向滚,组头无处安放。控件在 `lvsList` 下
  **忽略 `GroupView`**,退化为 SP1 的扁平路径。契约里写死,不留想象空间。

### 边界清单(测试必须覆盖)

1. 空 `AGroups`(G=0):每个函数不崩,`ContentHeight = 0`,`VisibleRange` 返回 False。
2. `Count = 0` 的组:仍占一条组头,`body = 0`;`FirstVisible[g+1] = FirstVisible[g]`。
3. 折叠组:只占组头;`FirstVisible` 不增长;`TyListGroupItemRect` 对它的任何项返回空矩形;
   `TyListGroupHitTest` 在它的组头**之下**(下一组的地盘)不会错认成它的项。
4. `HasHeader = False` 的隐式桶:不占组头高度,`TyListGroupHeaderRect` 返回空矩形。
5. **全部组折叠**:`ContentHeight = G * AHeaderH`,`FirstVisible[G] = 0`,导航一律返回 `-1`。
6. `Tops` 严格非降;`Tops[G]` = 各组高度之和。
7. `TyListGroupItemRect` 与 `TyListGroupHitTest` **互逆**:对每个可见 (g,i),
   格子左上角 +(1,1) 的点(钳进 item 区)必须命中回 (g,i)。滚动量非 0 时仍成立。
8. 组头带上的点 → `True` + `AIndexInGroup = -1`。
9. `TyListGroupOfDisplayPos` / `TyListGroupDisplayPos` 互逆,遍历所有可见位置。
10. `TyListGroupNavigate`:组内上下;跨组下移**保持列号**;末组末行下移不动;首组首行上移不动;
    跳过折叠组和空组;`Home`/`End` 总是移动;`PageUp`/`PageDown` 钳位。
11. `TyListGroupVisibleRange` 必须二分:构造 200 个组,断言不会 O(G) —— 用一个**计数探针**
    (传入一个可数的 `Tops` 访问器不现实,改为断言结果正确 + 复杂度靠 code review)。
    **至少断言**:滚到中间时返回的组区间只覆盖视口内的组,不是全部。
12. `PitchY <= 0`、`Tracks` 退化时不得除零。

---

## 任务 2 契约 —— 控件接线

> 前置:任务 1(`e5d48c4`)已合并。**零新增主题 token**:组头带复用已有的 `'TyTreeHeader'`。

### 核心思路 —— 为什么改动比看上去小

控件现有的绘制 / 命中 / 导航 / 选择**几乎全部**经 `DisplayToItem`(=`FOrder[pos]`)和
`ItemToDisplay`(=`FRank[item]`)转换。所以启用分组只需两件事:

1. `FOrder` 改成**只装可见项**(按组顺序,折叠组的项不进);
2. `FRank[item]` 对折叠组的项 = `-1`(`ItemToDisplay` 已经对 `-1` 做了正确处理)。

于是白拿:`SelectAll` / `GetNextSelected` 本来就按 item index 遍历 → **折叠不丢选中、SelectAll 含隐藏项**,
一行不用改。`ScrollIntoView(item)` 里 `ItemToDisplay(item) = -1` 时本就该 `Exit` → 隐藏项自动 no-op。

### 分组模型

```pascal
type
  TTyListGroup = class(TCollectionItem)
  published
    property Caption: string;
    property Collapsed: Boolean default False;
  end;

  TTyListGroups = class(TCollection)
    function Add: TTyListGroup;
    property Items[i: Integer]: TTyListGroup read GetItem write SetItem; default;
  end;

  TTyListGroupEvent = procedure(Sender: TObject; AGroup: Integer) of object;

published
  property GroupView: Boolean default False;
  property Groups: TTyListGroups;
  property OnGetItemGroup: TTyListGroupEvent... { 见下,签名用 var }
  property OnGroupCollapsed: TTyListGroupEvent; { 折叠状态改变后触发,收组序号 }
```

`TTyListItem` 增 `published GroupIndex: Integer default -1`。

**`Groups` 始终是真实集合**,即便 `OwnerData` —— 虚拟模式只虚拟**项**,不虚拟组(组数总是很小)。

### 取组 —— 第五个虚方法,和取数四方法并列

```pascal
protected
  function GetItemGroup(AItemIndex: Integer): Integer; virtual;   { 返回组序号,或 -1 = 隐式桶 }
```

默认实现:`OwnerData` → 触发 `OnGetItemGroup(Self, i, var g)`(未接则 `-1`);否则读 `Items[i].GroupIndex`。
返回值不在 `[0, Groups.Count-1]` 内 → 归到**隐式桶**。

### 隐式桶

组序号无效(`-1` 或越界)的项收进**一个隐式桶**,排在所有真实组**之后**,`HasHeader = False`(不画组头、不占组头高度)、**不可折叠**。全部项都有有效组时,桶为空、不出现。

### `FOrder` 的分组构建

`GroupView = True` 且 `FViewStyle <> lvsList` 时,`RebuildOrder` / `Sort` 改走分组路径:

1. 按 item index 升序,把每项分进 `groupItems[g]`(g ∈ `[0, Groups.Count]`,最后一个是隐式桶)。
2. 排序时,对**每个** `groupItems[g]` 用同一个比较器稳定排序(平局按 item index)。
3. `FOrder` := 依次拼接**未折叠**组的 `groupItems[g]`。
4. `FRank` 全置 `-1`,再遍历 `FOrder` 回填。
5. 缓存 `FGroupMap := TyListBuildGroupMap(infoArray, m, groupHeaderH)`,`infoArray[g]` 的
   `Count = Length(groupItems[g])`、`Collapsed`(桶恒 False)、`HasHeader`(桶 False)。

**`lvsList` 或 `GroupView = False` → 一字不动地走 SP1 扁平路径。** 这是 2623 个既有测试原样通过的保证。

`VisibleCount = Length(FOrder)`。

### 绘制

`RenderTo` 顶层分支:分组时用 `TyListGroupVisibleRange` 取可见组区间,逐组:

- `HasHeader` → 画组头带(`ResolveStyle('TyTreeHeader', …)`,内容 = `Caption + ' (' + Count + ')'` + 折叠三角);
- 组未折叠 → 逐可见项:`item := FOrder[FirstVisible[g] + i]`,`cell := TyListGroupItemRect(...)`,`RenderItem`。

组头带**不横滚**(X 固定 `[0, ViewportW]`),但**随内容纵滚**。

### 命中 / 交互

- `GetItemAt` / `GetHitPart`:分组时走 `TyListGroupHitTest`。命中组头(`AIndexInGroup = -1`)→ 新 hit part
  `lhpGroupHeader`(加进 `TTyListHitPart`);命中项 → `FOrder[FirstVisible[g]+i]` 换回 item index。
- **点击组头** → 切换 `Groups[g].Collapsed`,重建 order,触发 `OnGroupCollapsed(Self, g)`,`Invalidate`。
  折叠后 `FItemIndex` 若落进被折叠的组(`ItemToDisplay = -1`)→ 焦点不动、但它已不可见(可接受;不自动改焦点)。
- 键盘导航:分组时 `TyListGroupNavigate(FGroupMap, curPos, key, m)`,收/返 display 位置。
- 滚动量程:分组时 `TyListGroupContentHeight(FGroupMap)` 取代 `TyListContentExtent`。

### 不变式(逐条测)

1. `GroupView = False`:所有行为 = SP1(既有 2623 测试原样过)。
2. `lvsList` + `GroupView = True`:忽略分组,走扁平路径。
3. 集合模式:`FOrder` 按 `Groups` 顺序、组内按 item index(未排序时)/ 比较器(排序时)。
4. 折叠一个组:该组的项从 `FOrder` 消失,`FRank[它们] = -1`;**它们的选中位不变**,展开回来仍选中。
5. `SelectAll` 选中**全部**项(含折叠组里的)。`SelCount` 计全部。
6. `ScrollIntoView(隐藏项)` → no-op(不自动展开)。
7. `GetItemGroup`:集合读 `GroupIndex`;OwnerData 触发 `OnGetItemGroup`;越界 → 隐式桶。
8. 无效组序号的项进隐式桶,排在最后,无组头。
9. 切 `GroupView` 开 / 关,`FOrder`/`FRank` 长度与内容自洽,不崩。
10. 点组头切换 `Collapsed` 并触发 `OnGroupCollapsed`。

## 验收(任务 2)

- 全量测试 0 失败(基线 2676 + 新增)
- `themes/*.tycss`、`DefaultTheme.pas`、`BuiltinThemeData.pas`、`tests/golden/*`、
  `tyControls.TreeView.pas` **零改动**
- **未开启分组的既有测试全部原样通过**(退化证据)

## 验收

- 全量测试 0 失败(基线 2623 + 新增)
- `themes/*.tycss`、`DefaultTheme.pas`、`BuiltinThemeData.pas`、`tests/golden/*`、
  `tyControls.TreeView.pas` **零改动**
- 任务 1 落地后,**未开启分组的所有既有测试必须原样通过** —— 这是"退化回 SP1"的证据
