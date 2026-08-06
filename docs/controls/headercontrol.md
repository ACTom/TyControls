# TTyHeaderControl 列头控件

`TTyHeaderControl` 是一个独立的**列头条**(column-header strip):一排有序的
**分节**(section),每节有标题文字、宽度、对齐方式和一个排序状态。它常用于给一个自绘的
列表 / 表格提供可点击、可拖拽调宽的表头,而不必依赖完整的表格控件。

控件继承自 `TTyCustomControl`(有窗口句柄,支持鼠标捕获,用于边界拖拽调宽)。

## 外观与主题

`GetStyleTypeKey` 现在返回**自己的** `TyHeaderControl`,不再借树的 `TyTreeHeader`。
原因是同一批 token 对两个消费者含义不同:树把 `TyTreeHeader` 当作**自己框内的一条带**(只铺底色 +
画一条底线,从不描外框),而独立的列头条**本身就是那个框** —— 它走 `DrawFrame`,会用到
`border-radius`、`border` 描边和 `shadow`。同一个 `border-color`,在树里是列分隔线/表头下沿,
在这里是整条的外框线,两者调不开。

| typeKey | 画什么 |
|---|---|
| `TyHeaderControl` | 整条:背景、边框描边、圆角、阴影(`DrawFrame`),以及分隔线取的 `border-color` |
| `TyTreeHeaderSection` | 每一节的标题文字色与字体;`:hover` 的背景用于鼠标所在那一节 |

- 排序时在该节的**阅读末端**画一个排序指示三角:升序朝上、降序朝下,**填充色取该节的文字色**。
  从左到右时在右侧,`BiDiMode` 为右到左时在左侧(见"右到左镜像")。
- 节与节之间画一条分隔线,颜色取整条样式的 `border-color`;它画在每节与**后一节相邻**的那一边。

> **节的 typeKey 仍与树共享,这是"尚未拆分",不是"设计如此"。** `TyTreeHeaderSection` 目前同时被
> 树的列头和本控件使用,改它会同时改到树。本轮只拆了**盒子键**;`TyHeaderControlSection` /
> `TyHeaderControlSortMark` / `TyHeaderControlDivider` 这几个子部件键是**有意推迟**的,
> 现在**并不存在** —— 别在皮肤里写它们,写了也不会被解析。推迟原因与清单见
> `docs/superpowers/plans/2026-07-23-typekey-explicit-borrowers.md`。
>
> 顺带一提,本控件是 `TyTreeHeaderSection:hover` 的**唯一**真实消费者:树里那条 hover 分支是死代码。

**并非所有视觉数值都走了主题。** 目前仍写死在绘制代码里的有:节的左右内边距(`P.Scale(6)` —— 解析出的
`secStyle.Padding` 取到了却没用)、排序三角的尺寸(`P.Scale(9)`)与它预留的右侧留白(`sortSize * 2`)、
节间分隔线的固定 1px(不读 `S.BorderWidth`)、以及调宽感应区 `TyHeaderResizeGrip = 4`。要改这些,
现在只能改代码。

## 交互

| 操作 | 结果 |
| --- | --- |
| 点击某一节的**主体**(非边界) | 循环切换该节排序 none → asc → desc → asc,并触发 `OnSectionClick` |
| 在**节边界**附近按下并拖动 | 调整该边界所属那一节的宽度(正序是边界左侧那一节;镜像后是右侧那一节。使用 `MouseCapture`)。按下发 `OnSectionTrack(tsTrackBegin)`,拖动中每次变宽发 `tsTrackMove`,松手先发 `tsTrackEnd`、再**只发一次** `OnSectionResize` |
| 鼠标移到边界 | 光标变为水平调整光标(`crHSplit`);移开后**还原为调用方自己设的 `Cursor`**,不再被抹成 `crDefault` |

排序是**单列排序**:某一节开始排序时,会清除其余各节的排序状态。

## 公共 API

```pascal
function AddSection(const AText: string; AWidth: Integer = 100): Integer;  // 追加一节,返回索引
function InsertSection(AIndex: Integer; const AText: string;
  AWidth: Integer = 100): Integer;               // 在 AIndex 前插入,其余右移;越界即追加
procedure DeleteSection(AIndex: Integer);
procedure ClearSections;
procedure ToggleSort(AIndex: Integer);           // 循环该节排序(并清除其它节)

property SectionCount: Integer;
property Sections[AIndex: Integer]: TTyHeaderSection;        // 整条记录读写
property SectionText[AIndex: Integer]: string;              // 单独读写标题
property SectionWidth[AIndex: Integer]: Integer;           // 你**设**的宽度(逻辑像素),可读写
property EffectiveSectionWidth[AIndex: Integer]: Integer;  // 实际**画**出来的宽度(逻辑像素),只读
property SectionVisible[AIndex: Integer]: Boolean;         // 隐藏/显示某节(不删除)
property SectionMinWidth[AIndex: Integer]: Integer;        // 该节自己的宽度下限(0=用全条下限)
property SectionMaxWidth[AIndex: Integer]: Integer;        // 该节自己的宽度上限(0=不限)
property Sort[AIndex: Integer]: TTyHeaderSortDirection;    // 单独读写排序状态
```

**`SectionWidth` 不总等于你看到的宽度。** 最后一节会吸收剩余的客户区宽度,好让整条铺满控件
(LCL 的做法是把余量留白)。这是有意的,但它从前是看不见的:你设 100、画出来 250、读回来还是 100,
于是任何拿这个值去排版的代码(表头下方的列表、宽度求和)都在最后一节上、且只在最后一节上悄悄算错。
需要"画出来的那个数"时读 `EffectiveSectionWidth` —— 它走的是绘制用的同一个纯几何函数,
两者不可能对不上。它是布局的**结果**而非输入,因此只读。

节记录 `TTyHeaderSection` 含 `Text` / `Width`(逻辑像素) / `Alignment` / `SortDirection` /
`MinWidth` / `MaxWidth` / `Visible`。
排序方向枚举 `TTyHeaderSortDirection = (hsdNone, hsdAscending, hsdDescending)`。

宽度有下限 `TyHeaderMinSectionWidth`(16 逻辑像素),低于它会被夹紧 —— 但**只在该节没有自己的
`MinWidth` 时**。`MinWidth > 0` 就是这一节自己的下限,**高于或低于 16 都算数**:一个 12px 的
复选框列是真实存在的列,把它抬回 16 等于让它无法表达。`MaxWidth = 0` 表示不限(LCL 写作 10000,
零是记录天生就有的值,含义一样)。两个限制在**属性写入、整条记录写入、追加 / 插入、以及分隔线
实时拖动**四条路径上是同一个函数,不会互相矛盾 —— 一个"设得住、拖不住"的限制等于没有限制。

`SectionVisible[i] := False` 隐藏一节而**不删除**它:宽度与排序状态原样保留,以便"选择要显示的列"
菜单把它原样放回。隐藏节仍占着自己的索引位、按零宽度平铺,因此不被命中测试、不被绘制、
它的边界也抓不住;末节被隐藏时,剩余宽度改由**最后一个仍可见**的节吸收(否则刚被隐藏的那一节
会以整条剩余宽度重新出现)。

> 注意记录里 `Visible` 是**属性**而非字段,内部按"隐藏"取反存储。值记录出生即全零 ——
> `SetLength`、`Default(TTyHeaderSection)`、宿主自己拼一条记录交给 `Sections[i] :=` 都是 ——
> 若直接写成 `Visible: Boolean` 字段,这些节将全部生而不可见,与 `THeaderSection.Visible`
> 的 `default true`(`comctrls.pp:3996`)正好相反。

### 事件

```pascal
TTyHeaderTrackState = (tsTrackBegin, tsTrackMove, tsTrackEnd);

property OnSectionClick:  procedure(AHeader: TTyHeaderControl; AIndex: Integer) of object;
property OnSectionResize: procedure(AHeader: TTyHeaderControl; AIndex, AWidth: Integer) of object;
property OnSectionTrack:  procedure(AHeader: TTyHeaderControl; AIndex, AWidth: Integer;
                                    AState: TTyHeaderTrackState) of object;
```

`OnSectionTrack` 是**拖动过程中**的连续事件(用于实时预览),`OnSectionResize` 在**松开鼠标时只发一次**,
带最终宽度。以前两者合一,于是一个做实事的处理器(重新查询、重排下方表格、写配置)在一次拖动里
要跑几百遍。LCL 的 `THeaderControl` 也是这样分的。

`AState` 说明这一次 `OnSectionTrack` 处在拖动的哪个**阶段**:按住分隔线时发一次
`tsTrackBegin`,之后每次宽度变化发一次 `tsTrackMove`,松手时发一次 `tsTrackEnd`。
没有它的时候,一串调用彼此长得一模一样,处理器分不出哪一次是第一次、哪一次是最后一次
——而拖动开始时立起实时预览、拖动结束时撤掉正是连续事件唯一的用途。
松手时的顺序是 `tsTrackEnd` **先于** `OnSectionResize`(与 LCL 一致):
在 `tsTrackEnd` 里撤掉的预览,一定在 `OnSectionResize` 重排版面之前就没了。

三个事件的第一个参数都是**这条表头控件本身**(以前是裸 `TObject`)。LCL 在这里传的是
`THeaderSection` **对象**;我们的节是数组里的值记录,没有这样一个对象,**索引**就是它的身份——
对象能读到的每一项都在一跳之外:`AHeader.SectionText[AIndex]` / `SectionWidth[AIndex]` /
`Sort[AIndex]` / `Sections[AIndex]`。

## 纯几何函数(可脱离窗口直接测试)

所有布局/命中判定都抽成**单元级纯函数**,单位均为**设备像素**;控件只是薄壳,
绘制与命中都调用它们,因此绘制像素与命中区域天然一致。

```pascal
// 把各节宽度从左到右平铺到 AClient;最后一节吸收剩余宽度(当各节宽度之和
// 不足以填满 AClient 时),否则保持自身宽度(允许溢出,不收缩)。
// ARightToLeft=True 时把铺好的结果整体沿 AClient 的垂直中线**反射**:
// 第 0 节贴右边缘,整条向左延伸。
function TyHeaderSectionRects(const AWidths: array of Integer;
  const AClient: TRect; ARightToLeft: Boolean = False): TTyHeaderRectArray;

// 返回设备 X 落在哪一节(-1 表示越界)。各节区间是半开的 [Left, Right),
// 因此每个内部边界恰好归属一节;唯一特殊处理的是整条自己的外边缘,
// 它归属贴着它的那一节(正序是最后一节,镜像后是第 0 节)。
function TyHeaderSectionAtX(const AWidths: array of Integer;
  const AClient: TRect; X: Integer; ARightToLeft: Boolean = False): Integer;

// 当鼠标落在某个内部边界 AGrip 设备像素范围内时,返回被调宽的那一节的索引;
// 否则 -1。所谓内部边界是第 0..n-2 节与**后一节相邻**的那条边 —— 正序是它的
// 右边,镜像后是它的左边。整条的外边缘是控件边缘,不可调宽。重叠时取最近的。
function TyHeaderResizeEdgeAtX(const AWidths: array of Integer;
  const AClient: TRect; X, AGrip: Integer; ARightToLeft: Boolean = False): Integer;

// 排序三角形的三个顶点(位于单元格**阅读末端**的小方形区域内),升序朝上、
// 降序朝下。ARightToLeft 只反射三角形的中心 x,上下朝向不变 ——
// 排序方向是次序的方向,不是阅读的方向。
function TyHeaderSortTriangle(const ACellRect: TRect;
  ADir: TTyHeaderSortDirection; ASizeDev: Integer;
  ARightToLeft: Boolean = False): TTyHeaderTriangle;
```

## 右到左镜像(RTL)

把控件(或它的父窗体)的 `BiDiMode` 设为 `bdRightToLeft`,整条列头就镜像:
第 0 节贴右边缘、整条向左延伸,标题文字靠右,排序三角与分隔线换到每节的另一侧,
拖分隔线时**向左**拖是变宽。命中判定跟着一起动 —— 点在最左边的格子上,排序的是
**最后**一节,而不是第 0 节。

`BiDiMode` 目前**没有 published**(不在对象查看器里),要用请在代码里赋值;
原因见 `docs/rtl.md`:整库尚未全部镜像,提前 published 会给出一个在网格、
树、列表上无效的属性。

> **实现上只有一处算 x。** `TyHeaderSectionRects` 是唯一的平铺来源,绘制(`RenderTo`)、
> 两个命中函数、以及 `EffectiveSectionWidth` 全都从它取矩形,自己不算坐标;镜像也只是把
> 铺好的结果**反射**一次(走 LCL 的 `BidiFlipRect`),不是倒着再铺一遍。
> 这条性质是有意维持的:它让"画在这边、点在那边"这类 bug 在结构上不可能发生。
> 改这个文件时请保持它 —— 任何在 `TyHeaderSectionRects` 之外新算出来的 x,
> 都是一条会和另一条走散的第二路径。

不镜像的东西:节的**索引次序**不变(第 0 节仍是第 0 节,只是画在右边);
`SectionWidth` / `EffectiveSectionWidth` 的数值不变(反射不改变宽度);
排序三角的上下朝向不变。

## 用法示例

```pascal
var
  Header: TTyHeaderControl;
begin
  Header := TTyHeaderControl.Create(Self);
  Header.Parent := Self;
  Header.Align := alTop;
  Header.AddSection('名称', 160);
  Header.AddSection('大小', 80);
  Header.AddSection('修改日期', 140);
  Header.OnSectionClick := @HeaderSectionClick;   // 在这里对你的数据重新排序
  Header.OnSectionResize := @HeaderSectionResize; // 在这里同步下方列表的列宽
end;
```
