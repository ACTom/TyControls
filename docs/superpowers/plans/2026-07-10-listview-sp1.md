# TTyListView SP1 实施计划

> 设计:`docs/superpowers/specs/2026-07-10-listview-design.md`(已批准)
> 前置:`a1f8bc0` 列模型已搬到 `tyControls.Columns`

## 任务顺序

| # | 任务 | 产物 |
|---|---|---|
| 1 | 纯布局单元 + 无头测试 | `source/tyControls.ListView.Layout.pas`、`tests/test.listview.layout.pas` |
| 2 | 控件 | `source/tyControls.ListView.pas`、`tests/test.listview.pas` |
| 3 | 集成 | lpk / Design.pas / genicons / gen-icons.ps1 / test.paletteicons / tytests.lpr / docs |
| 4 | 示例 | `examples/listview/` |
| 5 | 对抗性审查 | 按维度评审 + 逐条反驳 |

任务 1 的测试**由不看实现的另一个 agent 按本文档的契约独立编写**。测试和实现对不上的地方,就是契约含糊的地方 —— 那正是要看的。

---

## 任务 1 契约 —— `tyControls.ListView.Layout`

无窗口、无 painter、无句柄。只 `uses Classes, SysUtils, Math, Types, tyControls.Columns`(为了 `TTySortDirection`)。全部尺寸是**设备像素**,由控件用 `Painter.Scale` 换算后喂进来。

### 类型

```pascal
type
  TTyListViewStyle = (lvsIcon, lvsSmallIcon, lvsList, lvsReport, lvsTile);
  TTyListNavKey    = (lnLeft, lnRight, lnUp, lnDown, lnHome, lnEnd, lnPageUp, lnPageDown);
  TTyListSortKind  = (lskText, lskNumber, lskDateTime);
  TTyListHitPart   = (lhpNowhere, lhpIcon, lhpLabel, lhpCheck, lhpHeader, lhpDivider);

  TTyIntArray = array of Integer;
  TTyItemTextFn = function(AIndex: Integer): string of object;

  TTyListMetrics = record
    ViewStyle:  TTyListViewStyle;
    ViewportW:  Integer;   { 客户区宽,已扣掉可见滚动条 }
    ViewportH:  Integer;   { 客户区高,已扣掉可见滚动条,含 HeaderH }
    CellW:      Integer;   { 单元格宽(不含 HGap)}
    CellH:      Integer;   { 单元格高(不含 VGap)}
    HGap:       Integer;
    VGap:       Integer;
    RowH:       Integer;   { lvsReport 的行高 }
    HeaderH:    Integer;   { 仅 lvsReport 非 0;其余模式控件必须传 0 }
    ReportWidth: Integer;  { lvsReport 的内容宽 = Columns.TotalWidth }
    IconPx:     Integer;   { 图标边长,供 TyListCellSize }
    LabelH:     Integer;   { 标签行高,供 TyListCellSize }
    Pad:        Integer;   { 单元格内边距,供 TyListCellSize }
  end;
```

**流向定义**(三选一,后面所有函数都按它分派):

| ViewStyle | 流向 | 滚动轴 |
|---|---|---|
| `lvsReport` | 整宽行,自上而下堆叠 | 垂直(行)+ 水平(列宽) |
| `lvsList` | **列优先**:自上而下填满一列,再向右换列 | 水平 |
| `lvsIcon` / `lvsSmallIcon` / `lvsTile` | **行优先**:自左向右,到边换行 | 垂直 |

记 `PitchX = CellW + HGap`,`PitchY = CellH + VGap`。单元格占 `[x, x+CellW] × [y, y+CellH]`,格与格之间是间隙。

### 函数

```pascal
function TyListCellSize(const M: TTyListMetrics): TSize;
```
按 `ViewStyle` 从 `IconPx` / `LabelH` / `Pad` 算出单元格尺寸,供控件回填 `M.CellW/CellH`。
- `lvsIcon`:`(IconPx + 4*Pad, IconPx + LabelH + 3*Pad)` —— 图标在上、标签在下
- `lvsSmallIcon` / `lvsList`:`(IconPx + 12*Pad, Max(IconPx, LabelH) + 2*Pad)` —— 图标在左、标签在右
- `lvsTile`:`(IconPx + 20*Pad, Max(IconPx, 2*LabelH) + 2*Pad)` —— 图标在左、两行文字在右
- `lvsReport`:`(ReportWidth, RowH)`

```pascal
function TyListTracks(const M: TTyListMetrics): Integer;
```
一条轨道上能放几格。**永远 ≥ 1**,即使视口比一个单元格还窄。
- 行优先:`Max(1, (ViewportW + HGap) div PitchX)`
- 列优先:`Max(1, ((ViewportH - HeaderH) + VGap) div PitchY)`
- `lvsReport`:`1`
- `PitchX`/`PitchY` ≤ 0 时返回 1(防除零)

```pascal
function TyListContentExtent(ACount: Integer; const M: TTyListMetrics): TSize;
```
**item 区域**的可滚动内容尺寸,**不含表头**。喂给滚动条量程。
- `lvsReport`:`(ReportWidth, ACount * RowH)`
- 行优先:`Rows = Ceil(ACount / Tracks)`;`(ViewportW, Max(0, Rows*PitchY - VGap))`
- 列优先:`Cols = Ceil(ACount / Tracks)`;`(Max(0, Cols*PitchX - HGap), ViewportH - HeaderH)`
- `ACount = 0` → `(0, 0)`

```pascal
function TyListItemRect(ADisplayPos, ACount: Integer; const M: TTyListMetrics;
  AScrollX, AScrollY: Integer): TRect;
```
**唯一的几何来源。绘制和命中都必须调它。** 返回**客户区坐标**(已减去滚动偏移、已加上 `HeaderH`)。
- `ADisplayPos` 越界(`<0` 或 `>= ACount`)→ `Rect(0,0,0,0)`
- `lvsReport`:`Left = -AScrollX`,`Top = HeaderH + ADisplayPos*RowH - AScrollY`,`Right = Left + ReportWidth`,`Bottom = Top + RowH`
- 行优先:`col = pos mod Tracks`,`row = pos div Tracks`
- 列优先:`row = pos mod Tracks`,`col = pos div Tracks`
- 行/列优先共用:`Left = col*PitchX - AScrollX`,`Top = HeaderH + row*PitchY - AScrollY`,尺寸 `CellW × CellH`

```pascal
function TyListItemAt(const APt: TPoint; ACount: Integer; const M: TTyListMetrics;
  AScrollX, AScrollY: Integer): Integer;
```
`TyListItemRect` 的逆。返回 item 的 **display 位置**,未命中返回 `-1`。
- 点落在 `HeaderH` 以内 → `-1`(表头不是 item)
- 点落在**格间间隙**里 → `-1`(不能吸附到最近格)
- 反算出的位置 `>= ACount` → `-1`
- `lvsReport` 的行占满 `ReportWidth`;`APt.X` 超出 `ReportWidth - AScrollX` → `-1`

> 实现要求:算出候选位置后,**必须**用 `TyListItemRect` 回算并做 `PtInRect` 校验。这是"绘制与命中不可能漂移"的机械保证。

```pascal
function TyListVisibleRange(ACount: Integer; const M: TTyListMetrics;
  AScrollX, AScrollY: Integer; out AFirst, ALast: Integer): Boolean;
```
O(1) 闭式虚拟化窗口。`ACount = 0` → `False`,两个 out 参数置 `-1`。
- 结果是**闭区间** `[AFirst, ALast]`,含所有与视口相交的格(部分可见也算)。
- `AFirst` 钳到 `≥ 0`,`ALast` 钳到 `≤ ACount-1`。
- `lvsReport`:`vh = ViewportH - HeaderH`;`AFirst = AScrollY div RowH`;`ALast = (AScrollY + vh - 1) div RowH`
- 行优先:`firstRow = AScrollY div PitchY`;`lastRow = (AScrollY + (ViewportH-HeaderH) - 1) div PitchY`;`AFirst = firstRow*Tracks`;`ALast = (lastRow+1)*Tracks - 1`
- 列优先:同理沿 X 轴,用 `AScrollX` / `ViewportW` / `PitchX`
- 若钳位后 `AFirst > ALast` → `False`

```pascal
function TyListNavigate(ACurrent, ACount: Integer; AKey: TTyListNavKey;
  const M: TTyListMetrics): Integer;
```
二维网格导航。收/返 **display 位置**。
- `ACount = 0` → `-1`
- `ACurrent < 0` → 视作 `-1`,方向键从 0 开始(首次按键落到第一项)
- `lnHome` → `0`;`lnEnd` → `ACount-1`(总是移动)
- 方向键的**步长**:
  - `lvsReport`:`lnUp/lnDown = ∓1/±1`;`lnLeft/lnRight` **不移动**(返回 `ACurrent`)
  - 行优先:`lnLeft/lnRight = ∓1/±1`;`lnUp/lnDown = ∓Tracks/±Tracks`
  - 列优先:`lnUp/lnDown = ∓1/±1`;`lnLeft/lnRight = ∓Tracks/±Tracks`
- **方向键越界不移动**(返回 `ACurrent`),不钳位。理由:资源管理器里在首行按 ↑ 不会跳到第 0 项。
- `lnPageUp/lnPageDown` 的步长 = 一屏的格数,并**钳位**到 `[0, ACount-1]`:
  - `lvsReport`:`Max(1, (ViewportH - HeaderH) div RowH)`
  - 行优先:`Max(1, (ViewportH - HeaderH) div PitchY) * Tracks`
  - 列优先:`Max(1, ViewportW div PitchX) * Tracks`

```pascal
function TyListRangeBounds(AAnchor, ATarget: Integer; out ALo, AHi: Integer): Boolean;
```
Shift 区间。任一参数 `< 0` → `False`,out 置 `-1`。否则 `ALo = Min`,`AHi = Max`,`True`。

```pascal
function TyListMarqueeHits(const ABox: TRect; ACount: Integer; const M: TTyListMetrics;
  AScrollX, AScrollY: Integer): TTyIntArray;
```
框选。返回**与 `ABox` 相交**的所有 display 位置,**升序**。
- **不是连续区间**:icon 模式下框住 2×2 会命中 4 个跨行的位置。这就是它返回数组的原因。
- `ABox` 是客户区坐标,允许右上/左下方向(内部先 `NormalizeRect`)。
- 相交判据:与 `TyListItemRect` 的矩形有非空交集(碰到边算相交)。
- 无命中 → 长度 0 的数组(不是 nil 语义上的区别,`Length=0` 即可)。
- 实现不得遍历 `ACount`:先由 `ABox` 反算行/列跨度,只枚举其中的格。

```pascal
function TyListPrefixMatch(AGetText: TTyItemTextFn; ACount, AStartAfter: Integer;
  const APrefix: string): Integer;
```
首字母定位。**函数自己循环**,不是"控件循环、函数判一格" —— 这样整个查找都能无头测试。
- 从 `AStartAfter + 1` 开始,**环绕**一整圈(共查 `ACount` 项)。
- 命中条件:`AGetText(i)` 以 `APrefix` 开头,**不区分大小写**(用 `UTF8CompareText` 比较前缀切片)。
- `APrefix` 为空 或 `ACount <= 0` → `-1`。找不到 → `-1`。
- `AStartAfter` 可以是 `-1`(从 0 开始查)。

```pascal
function TyListCompareCells(const A, B: string; AKind: TTyListSortKind;
  ADir: TTySortDirection): Integer;
```
- `lskText`:`UTF8CompareText(A, B)`(不区分大小写)
- `lskNumber`:两边都能 `TryStrToFloat`(用 `TFormatSettings` 固定 `'.'`)→ 数值比较;**只有一边**能解析 → 能解析的排前;**都不能** → 退化为 `lskText`
- `lskDateTime`:同上,`TryStrToDateTime`;不可解析的排后
- `ADir = sdDescending` → 结果取反
- 相等返回 0(调用方负责稳定性:比较相等时按 item index 兜底)

```pascal
function TyReportRowAt(AY, AScrollY, AHeaderH, ARowH, ARowCount: Integer): Integer;
```
`AY < AHeaderH` → `-1`。`ARowH <= 0` → `-1`。`row = (AY - AHeaderH + AScrollY) div ARowH`;越界 → `-1`。

### 边界清单(测试必须覆盖)

1. `ACount = 0`:每个函数都不得崩、不得除零。
2. 视口比一个单元格还窄/矮:`Tracks` 仍为 1。
3. `PitchX` / `PitchY` = 0(CellW=HGap=0):不得除零。
4. 最后一行/列只有部分格:`VisibleRange` 的 `ALast` 必须钳到 `ACount-1`;`ItemAt` 对那一行的空位返回 `-1`。
5. `ItemRect` 与 `ItemAt` 在所有 5 种 ViewStyle 上**互逆**:对每个 `pos`,`ItemAt(ItemRect(pos).TopLeft + (1,1)) = pos`。
6. 间隙:`HGap > 0` 时,两格之间的点返回 `-1`。
7. 滚动偏移非 0 时 5 和 6 仍成立。
8. `Navigate`:首行 ↑ / 末行 ↓ / 首项 ← / 末项 → 均**不移动**;`Home`/`End` 总是移动;`PageUp`/`PageDown` 钳位。
9. `MarqueeHits`:icon 模式下框住 2×2 返回 4 个**不相邻**的位置;空框返回长度 0。
10. `PrefixMatch`:环绕;大小写无关;`AStartAfter = ACount-1` 时能绕回 0;查不到返回 `-1`。
11. `CompareCells`:`lskNumber` 混入不可解析值;`lskDateTime` 同理;`sdDescending` 取反。

---

## 任务 2 —— 控件

`TTyListView = class(TTyCustomControl)`,`GetStyleTypeKey = 'TyTreeView'`。

取数四虚方法(设计文档已定)。绘制路径唯一:`RenderTo` → 按 `ViewStyle` 分派 → 逐格调 `RenderItem`。

排序只置换 `FOrder: array of Integer`(display 位置 → item index);选择集 `FSelected: array of Boolean` **按 item index 存**。公开 API 一律收/返 item index;display 位置只在内部流转。

内嵌两个 `TTyScrollBar`,`csNoDesignVisible`。

抄现成的坑清单:
- `TTyListBox.ContentTopOffset` —— 行命中必须减去 padding-top,否则每行顶部一条带子命中上一行。
- 拖拽 `MouseMove` 必须在 `not (ssLeft in Shift)` 时退出。
- LCL `MouseDown` 的 `Shift` **含 `ssLeft`**,不要用 `Shift = []` 判断。
- 内部子控件设 `csNoDesignVisible`,且要在 `Visible` 之前设。

## 任务 3 —— 集成

`tycontrols.lpk` 加两个单元;`Design.pas` 注册进 `'TyControls Containers'`;`genicons.lpr` 加图标(数组上界 128 → 129);`gen-icons.ps1` `$classes`;`test.paletteicons.pas` `CClasses`(上界同步);`tytests.lpr` 加两个测试单元;`docs/controls/listview.md` + README 索引。跑 `.\scripts\gen-icons.ps1`,期望 "130 registered components all have icons"。

## 任务 4 —— 示例

`examples/listview/`,`.lfm` 设计。四种视图切换 + 报表排序 + 多选 + 一个 **10 万行虚拟模式**页签(证明零对象:切过去要瞬间)。

## 任务 5 —— 对抗性审查

维度:布局几何 / 选择与排序 / 绘制与主题 / 组件与流式化。每条发现派独立 agent 反驳。

## 验收

- 全量测试 0 失败(基线 2437 + 新增)
- `themes/*.tycss`、`DefaultTheme.pas`、`BuiltinThemeData.pas`、`tests/golden/*`、`tyControls.TreeView.pas` **零改动**
- `git diff --stat` 里不出现上述文件
