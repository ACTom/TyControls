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

- 排序时在该节右侧画一个排序指示三角:升序朝上、降序朝下,**填充色取该节的文字色**。
- 节与节之间画一条分隔线,颜色取整条样式的 `border-color`。

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
| 在**节边界**附近按下并拖动 | 调整该边界左侧那一节的宽度(使用 `MouseCapture`),拖动中持续触发 `OnSectionTrack`,**松开时触发一次** `OnSectionResize` |
| 鼠标移到边界 | 光标变为水平调整光标(`crHSplit`);移开后**还原为调用方自己设的 `Cursor`**,不再被抹成 `crDefault` |

排序是**单列排序**:某一节开始排序时,会清除其余各节的排序状态。

## 公共 API

```pascal
function AddSection(const AText: string; AWidth: Integer = 100): Integer;  // 追加一节,返回索引
procedure DeleteSection(AIndex: Integer);
procedure ClearSections;
procedure ToggleSort(AIndex: Integer);           // 循环该节排序(并清除其它节)

property SectionCount: Integer;
property Sections[AIndex: Integer]: TTyHeaderSection;        // 整条记录读写
property SectionText[AIndex: Integer]: string;              // 单独读写标题
property SectionWidth[AIndex: Integer]: Integer;           // 你**设**的宽度(逻辑像素),可读写
property EffectiveSectionWidth[AIndex: Integer]: Integer;  // 实际**画**出来的宽度(逻辑像素),只读
property Sort[AIndex: Integer]: TTyHeaderSortDirection;    // 单独读写排序状态
```

**`SectionWidth` 不总等于你看到的宽度。** 最后一节会吸收剩余的客户区宽度,好让整条铺满控件
(LCL 的做法是把余量留白)。这是有意的,但它从前是看不见的:你设 100、画出来 250、读回来还是 100,
于是任何拿这个值去排版的代码(表头下方的列表、宽度求和)都在最后一节上、且只在最后一节上悄悄算错。
需要"画出来的那个数"时读 `EffectiveSectionWidth` —— 它走的是绘制用的同一个纯几何函数,
两者不可能对不上。它是布局的**结果**而非输入,因此只读。

节记录 `TTyHeaderSection` 含 `Text` / `Width`(逻辑像素) / `Alignment` / `SortDirection`。
排序方向枚举 `TTyHeaderSortDirection = (hsdNone, hsdAscending, hsdDescending)`。

宽度有下限 `TyHeaderMinSectionWidth`(16 逻辑像素),低于它会被夹紧。

### 事件

```pascal
property OnSectionClick: procedure(Sender: TObject; AIndex: Integer) of object;
property OnSectionTrack:  procedure(Sender: TObject; AIndex, AWidth: Integer) of object;
property OnSectionResize: procedure(Sender: TObject; AIndex, AWidth: Integer) of object;
```

`OnSectionTrack` 是**拖动过程中**的连续事件(用于实时预览),`OnSectionResize` 在**松开鼠标时只发一次**,
带最终宽度。以前两者合一,于是一个做实事的处理器(重新查询、重排下方表格、写配置)在一次拖动里
要跑几百遍。LCL 的 `THeaderControl` 也是这样分的。

## 纯几何函数(可脱离窗口直接测试)

所有布局/命中判定都抽成**单元级纯函数**,单位均为**设备像素**;控件只是薄壳,
绘制与命中都调用它们,因此绘制像素与命中区域天然一致。

```pascal
// 把各节宽度从左到右平铺到 AClient;最后一节吸收剩余宽度(当各节宽度之和
// 不足以填满 AClient 时),否则保持自身宽度(允许溢出,不收缩)。
function TyHeaderSectionRects(const AWidths: array of Integer;
  const AClient: TRect): TTyHeaderRectArray;

// 返回设备 X 落在哪一节(-1 表示越界)。边界归属其左侧那一节。
function TyHeaderSectionAtX(const AWidths: array of Integer;
  const AClient: TRect; X: Integer): Integer;

// 当鼠标落在某个内部边界(第 0..n-2 节的右边)AGrip 设备像素范围内时,
// 返回该边界左侧节的索引(即被调宽的那一节);否则 -1。最后一节的右边
// 是控件边缘,不可调宽。重叠时取最近的边界。
function TyHeaderResizeEdgeAtX(const AWidths: array of Integer;
  const AClient: TRect; X, AGrip: Integer): Integer;

// 排序三角形的三个顶点(位于单元格右侧的小方形区域内),升序朝上、降序朝下。
function TyHeaderSortTriangle(const ACellRect: TRect;
  ADir: TTyHeaderSortDirection; ASizeDev: Integer): TTyHeaderTriangle;
```

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
