# TTyHeaderControl 列头控件

`TTyHeaderControl` 是一个独立的**列头条**(column-header strip):一排有序的
**分节**(section),每节有标题文字、宽度、对齐方式和一个排序状态。它常用于给一个自绘的
列表 / 表格提供可点击、可拖拽调宽的表头,而不必依赖完整的表格控件。

控件继承自 `TTyCustomControl`(有窗口句柄,支持鼠标捕获,用于边界拖拽调宽)。

## 外观与主题

- `GetStyleTypeKey` **复用** `TyTreeHeader`:整条的背景/边框来自该 token。
- 每一节用 `TyTreeHeaderSection` 解析出的样式绘制(标题文字颜色、字体);
  鼠标悬停的那一节使用 `TyTreeHeaderSection:hover` 的背景高亮。
- 排序时在该节右侧画一个排序指示三角:升序朝上、降序朝下。
- 节与节之间画一条分隔线,颜色取自整条样式的 `border-color`。

以上颜色**全部来自主题**,控件代码不硬编码任何视觉数值,也**不新增任何 `.tycss`**。

## 交互

| 操作 | 结果 |
| --- | --- |
| 点击某一节的**主体**(非边界) | 循环切换该节排序 none → asc → desc → asc,并触发 `OnSectionClick` |
| 在**节边界**附近按下并拖动 | 调整该边界左侧那一节的宽度(使用 `MouseCapture`),拖动中持续触发 `OnSectionResize`,松开时再触发一次 |
| 鼠标移到边界 | 光标变为水平调整光标(`crHSplit`) |

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
property SectionWidth[AIndex: Integer]: Integer;           // 单独读写宽度(逻辑像素)
property Sort[AIndex: Integer]: TTyHeaderSortDirection;    // 单独读写排序状态
```

节记录 `TTyHeaderSection` 含 `Text` / `Width`(逻辑像素) / `Alignment` / `SortDirection`。
排序方向枚举 `TTyHeaderSortDirection = (hsdNone, hsdAscending, hsdDescending)`。

宽度有下限 `TyHeaderMinSectionWidth`(16 逻辑像素),低于它会被夹紧。

### 事件

```pascal
property OnSectionClick: procedure(Sender: TObject; AIndex: Integer) of object;
property OnSectionResize: procedure(Sender: TObject; AIndex, AWidth: Integer) of object;
```

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
