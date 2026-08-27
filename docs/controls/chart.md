# TTyChart

## 1. 概述

`TTyChart` 是 TyControls 库中的主题化图表控件，继承自 `TTyGraphicControl`（图形控件，无窗口句柄，不能作为父容器），用 BGRA `Canvas2D` 抗锯齿绘制。支持四种图表类型：**折线（`ctLine`）/ 柱（`ctBar`）/ 饼（`ctPie`）/ 环形（`ctDonut`）**；设计期可编辑系列，自动 Y 轴量程 + 漂亮刻度 + 网格、图例、标题。

**鼠标悬停在数据点 / 柱 / 扇区上会弹出 tooltip**，显示该数据的分类、系列名与数值（饼 / 环形还带占比）。tooltip 是**画在图表内部的覆盖层**，不是 LCL 提示窗口——理由见第 8 节。

图表自身的外观（背景 / 标题 / 坐标轴文字 / 网格线）走它**自己的** `TyChart` 主题样式；tooltip 走 `TyChartTooltip`；**系列颜色**用内置雅致调色板（`TyChartPalette`，Tableau-10 色相），可按系列用 `TTyChartSeriesItem.Color` 覆盖。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Chart` |
| `GetStyleTypeKey` 返回值 | `'TyChart'`（**自有 typeKey**；见下表：图表外框 + 标题 / 图例 / 刻度文字 / 坐标轴 / 网格线全部从这一个键取色） |
| tooltip typeKey | `'TyChartTooltip'`（悬停提示框的 `background` / `border-*` / `color` / `padding` / `font-*` / `shadow`） |
| 基类 | `TTyGraphicControl`（继承自 `TGraphicControl`） |
| 默认尺寸 | 260 × 180（逻辑像素，构造时设置） |

图表从前返回 `'TyPanel'`——一个画着整套数据可视化的控件，却只能通过「全应用的面板」被主题触及：想把网格线调淡就得改所有面板的边框色，想让图表底比卡片深一点则根本无从表达。现在它有了自己的键。`TyChart` 已作为附加选择器并入主题里 `TyPanel` 的规则块，解析值与从前逐字节相同，**开钩子而不动像素**；第三方主题若只覆盖了 `TyPanel`，需要补上 `TyChart`（主题层按 typeKey 全有全无地回落）。

### 这两个键各画什么

| 键 | 画什么 | 读哪些属性 |
|----|--------|-----------|
| `TyChart` | 图表外框（`DrawFrame`）；标题；图例文字；X/Y 刻度标签；左 + 下坐标轴折线；水平网格线 | `background` / `border-color` / `border-width` / `border-radius` / `color`。**坐标轴**用 `border-color` 原色，**网格线**用同一颜色但 alpha 被代码固定压到 70，**所有文字**（标题 / 图例 / 刻度）用 `color` |
| `TyChartTooltip` | 悬停提示框 | `background` / `border-*` / `color` / `padding` / `font-*` / `shadow` |

### 子部件 typeKey

**目前只有 `TyChartTooltip` 一个。** 标题、图例、坐标轴、网格、刻度标签**没有**各自的键——它们的字号 / 字重是代码里的字面量（标题 `11/700`、图例 `9/400`、刻度 `8/400`，且都用控件的 `Font.Name` 而非样式的 `font-name`），网格线的 70 alpha 也是字面量。子部件键（`TyChartTitle` / `TyChartLegend` / `TyChartAxis` / `TyChartGrid` / `TyChartLabel` / `TyChartSeries1..8`）的扩展已被**刻意推迟**——其中系列色那一组一旦落地会真的改变像素——这些名字当前**并不存在**，写进 `.tycss` 解析不到任何东西。

```pascal
uses tyControls.Chart;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `ChartType` | `TTyChartType` | `ctLine` | `(ctLine, ctBar, ctPie, ctDonut)`。一图一类型（不混合）。`ctDonut` **追加在枚举末尾**，已有 `.lfm` 的序数不受影响。 |
| `Series` | `TTyChartSeries` | 空 | 系列集合（设计期可编辑）。每项：`Name` / `Color`（`clDefault` = 按调色板循环）/ `Values`（逗号分隔数值，`.` 小数点）。 |
| `Categories` | `TStrings` | 空 | X 轴分类（折线 / 柱）；饼 / 环形下是**扇区名**（图例即取此）。缺失时回退为 1-based 序号。 |
| `Title` | `string` | `''` | 标题，占据内容区顶部一条 20 逻辑像素的带。 |
| `ShowLegend` | `Boolean` | `True` | 底部图例条。**关掉会把这条空间还给数据区**，不是只停止绘制。 |
| `ShowGrid` | `Boolean` | `True` | 水平网格线（折线 / 柱）。 |
| `ShowValues` | `Boolean` | `False` | 常驻数值标注（柱 / 折线为数值，饼 / 环形为百分比）。与 tooltip 相互独立。 |
| `ShowTooltip` | `Boolean` | `True` | 悬停 tooltip 总开关。关掉时**立即**抹掉屏上已显示的 tooltip，不等下次鼠标移动。 |
| `OnGetTooltip` | `TTyChartTooltipEvent` | `nil` | 见第 4 节。 |

> **为什么叫 `ShowTooltip` 而不是 `ShowHint`？** `TControl` 已经 published 了 `ShowHint` / `Hint` / `OnShowHint`（整控件级的 OS 提示窗口），`TTyGraphicControl` 继承并暴露了它们——名字**已被占用**（Pascal 大小写不敏感，重名即编译错误）。而且两者本来就是不同的东西：`Hint` 是「这个图表是干嘛的」，`ShowTooltip` 是「指针下这个**数据点**是多少」。事件同理命名为 `OnGetTooltip`（与属性配对，且不与 `OnShowHint` 冲突）。

### 继承的通用成员

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | 对应 `.tycss` 里 `TyChart.<classname>`；**tooltip 用同一个 `StyleClass` 解析**，所以 `TyChartTooltip.compact` 能跟随 `TyChart.compact`。 |
| `StyleOverride` | `string` | `''` | 单实例内联 CSS 声明块。 |
| `Controller` | `TTyStyleController` | `nil`（用全局 `TyDefaultController`） | 指定样式控制器。 |

另暴露 `Align` / `Anchors` / `Font` 及 `TTyGraphicControl` 基线事件集，见 [../events.md](../events.md)。

---

## 4. 事件

| 事件 | 触发时机 |
|------|----------|
| `OnGetTooltip` | 图表**即将绘制 tooltip 之前**触发。`procedure(Sender: TObject; ASeries, APoint: Integer; var AText: string) of object`。进来时 `AText` 已经是 `TyChartDefaultTooltip` 生成的默认文本（多行以 `#10` 分隔）；可以**追加**、**整个替换**，或**清空**（`AText := ''`）来只屏蔽这一个点的 tooltip 而不影响其余数据点。`ASeries` / `APoint` 分别索引 `Series[]` 与该系列解析后的数值数组。 |

```pascal
procedure TForm1.ChartGetTooltip(Sender: TObject; ASeries, APoint: Integer;
  var AText: string);
begin
  // 在默认的「分类 / 系列: 数值」下面再加一行业务信息
  AText := AText + #10 + '同比 ' + FYoY[ASeries][APoint];
end;
```

---

## 5. 关键成员

### 纯几何 / 规则函数（单元级，可无句柄直接调用）

绘制路径与命中检测**调用同一批纯函数**，因此「指针报告的数据」与「那个像素上画的数据」永远不会漂移（TTySegmented 那条规矩）。全部为普通矩形 / 数值入参、无控件状态、无句柄依赖，测试直接调用（`tests/test.chart.pas`）。

```pascal
type
  TDoubleArray      = array of Double;
  TDoubleArrayArray = array of TDoubleArray;   // 每系列一条，喂给命中检测

  TTyChartHit = record
    SeriesIndex: Integer;   // 与 PointIndex 同为 -1 表示「无」
    PointIndex: Integer;
  end;

  TTyChartLayout = record
    Plot: TRect;      // 折线 / 柱的绘图带
    PieArea: TRect;   // 饼 / 环形的圆盘外接带
    Legend: TRect;    // 图例条
  end;
```

**量程 / 布局**

| 函数 | 作用 |
|------|------|
| `TyChartNiceRange` | Heckbert nice-numbers：把数据范围扩到漂亮边界（step ∈ {1,2,5}×10^k），含 0 基线。 |
| `TyChartValueToY` | 值 → 像素 Y（线性）。 |
| `TyChartBarXRange` | 把 `[L,R]` 均分为 N 段并各自内缩，保证**不重叠、在界内**。 |
| `TyChartLayoutFor` | 控件尺寸 → `Plot` / `PieArea` / `Legend` 三条带（设备像素）。**绘制与命中检测都调它**。任何算出来会空 / 会反向的带一律返回**空矩形**。 |

**数据几何**

| 函数 | 作用 |
|------|------|
| `TyChartBarRect` | 一根柱的矩形：分类槽再按系列细分（**这就是分组柱状图**，见第 6 节）。柱从零基线跨到数值，负值**向下挂**。 |
| `TyChartPointCenter` | 一个折线标记点的圆心（分类槽中点 + 值对应的 Y）。 |
| `TyChartPieSweeps` | 各值的 `(StartDeg, SweepDeg)`，sweep 和 = 360，负值夹到 0，全零安全（不除零）。 |
| `TyChartDonutHoleRadius` | 环形内孔半径 = 外半径的 `APercent`%，夹在 `[0, TyChartDonutHoleMaxPercent]`。 |

**命中检测**

| 函数 | 语义 |
|------|------|
| `TyChartBarHitTest` | `TyChartBarRect` 的**逆**（直接扫它画出来的矩形）。柱互不重叠，第一个包含点的胜出。 |
| `TyChartLineHitTest` | 标记点只有几像素宽，靠包含判定抓不住 → 给指针一个**抓取半径**（欧氏，不是包围盒），**最近者胜**；平手归**较小的系列序号**（稳定：同一像素永远给同一答案）。容差 ≤ 0 = 关闭折线悬停。 |
| `TyChartPieHitTest` | DrawPie 的逆（同样的 −90° 偏移、同样的屏幕坐标系角度）。圆盘外 / **环形内孔里** / 零 sweep 扇区 → `-1`。 |
| `TyChartNoHit` / `TyChartHitValid` | 「无命中」值与**唯一**的判定入口。 |

**tooltip 规则**

| 函数 | 语义 |
|------|------|
| `TyChartDefaultTooltip(ACategory, ASeriesName, AValue, APercent)` | 生成默认文本（`#10` 分隔）：第 0 行 = 分类（空则整行省略），第 1 行 = `<系列>: <值>`（系列名空则省略前缀）。`APercent >= 0` 追加 ` (NN.N%)`，传负数则不带。数值用 `'0.###'` + `.` 小数点、无千分位——**与坐标轴刻度标签同一格式**（tooltip 若跟它下面的坐标轴对不上，比没有 tooltip 更糟），且**不跟随 locale**。 |
| `TyChartTooltipRect(AAnchorX, AAnchorY, AWidth, AHeight, AGap, ABounds)` | 放置：默认在数据点**右上方** `AGap` 处（不遮住正在读的数据点，也不压在光标下）；越界则**先翻转**到另一侧，**再夹**回 `ABounds` 内。比图表还大的框会被**钉在**里面而不是藏起来——被裁的 tooltip 也比没有强。 |

### 公开成员

```pascal
function HitTestAt(X, Y: Integer): TTyChartHit;   // 客户区设备像素 -> 数据点（用 TyChartHitValid 判定）
```

与 tooltip 用的是同一个答案——需要「点击下钻」的应用在 `OnClick` / `OnMouseDown` 里读它，不必自己重推几何。

```pascal
procedure SaveToFile(const AFileName: string);                             // 按控件当前尺寸导出
procedure SaveToFile(const AFileName: string; AWidth, AHeight: Integer);   // 按指定尺寸重排版导出
```

把图表导出为图片，格式由扩展名决定：`.png`、`.bmp`、`.jpg`/`.jpeg`、`.tif`。带尺寸的重载按给定宽高重新排版（小图表可以导出成大图），文字保持控件的 PPI。背景取当前主题，导出图不透明。

---

## 6. 类型语义

| 类型 | 语义 |
|------|------|
| `ctLine` | 多系列，每系列一条折线 + 标记点；`Categories` 作 X 轴。 |
| `ctBar` | 多系列，**每分类一组并排柱**（见下）；`Categories` 作 X 轴。 |
| `ctPie` | **第一个系列**的各值为扇区；`Categories` 作扇区名 / 图例。 |
| `ctDonut` | 同 `ctPie`，中间挖一个主题可调的孔。 |

### 分组柱状图（多系列并排）

`ctBar` 下多系列**确实**是并排分组、互不重叠的，机制是两层嵌套的 `TyChartBarXRange`：

```
绘图带 ──按 catCount 切──> 分类槽 ──按 seriesCount 再切──> 每系列一根柱
```

两层都各自内缩（每边 15%，至少 1px），所以**分类之间**和**同分类内的系列之间**都有硬间隙。`TyChartBarRect` 把这两步封装成一个纯函数，绘制与命中检测都调它。测试 `TestBarRectGroupedSeriesNeverOverlap` / `TestBarHitTestRoundTripsEveryBar` 直接守护这条（3 系列 × 4 分类，逐个断言不重叠、且每根柱的中心能反查回自己）。

> 极窄图表下会退化成 1px 细柱（`TyChartBarXRange` 的 `if AX1 < AX0 then AX1 := AX0` 保证不反向），但不会重叠。

### 环形（`ctDonut`）

- **饼就是孔 = 0 的环形**：`DrawPie` 只有**一条**路径——沿起始边出去、绕外弧、沿终止边回来、再沿内弧反向绕回（两条弧绕向相反，因此无论用哪种填充规则孔都是孔）。`hole = 0` 时两条径向段塌缩到圆心，**逐像素等同于**原来的 `moveTo(圆心)/arc/closePath` 扇形——`ctPie` 的渲染没有任何变化。
- **孔不填色，是「不画」**：孔里露出的是面板自身的背景。因此图片主题下孔里是照片，而不是一块糊上去的纯色。分隔线（surface 色）会顺带描出内孔的一圈干净边缘。
- `ShowValues` 的百分比标签放在**环带厚度的 60%** 处（`hole + (radius-hole)*0.6`）；`hole = 0` 时正好是 `radius*0.6`，即饼原来的位置。

---

## 7. 状态与主题

### 主题令牌摘要

图表本体走 `TyChart`（内置主题里与 `TyPanel` 等键同值同块，见第 2 节）；除它以外，图表**唯一**拥有的键是 tooltip：

```css
/* themes/light.tycss —— 基础层，所有主题继承 */
TyChartTooltip {
  background: var(--surface);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: var(--input-border-width);
  border-radius: var(--radius-sm);
  padding: 5px 9px;
  font-size: var(--font-size-base);
}
```

它**读起来就是 `TyHint`**——因为它本来就是一个提示，只不过画在图表内部而不是 OS 窗口里。想让框浮起来的皮肤可以加 `shadow: <ox> <oy> <blur> <color>`，控件会照做；基础层保持 light 一贯的扁平（light.tycss 里没有任何阴影）。

**未定义时优雅降级**（绝不回退到硬编码颜色）：

| 缺什么 | 结果 |
|--------|------|
| 整个 `TyChartTooltip` 未定义 | 无 `background` → **不画框**（图表其余部分照常） |
| 只缺 `color` | 文字用图表自身（`TyChart`）的 `color` |
| 只缺 `shadow` | 不画阴影 |
| 只缺 `border-*` | 不描边 |

### 可调尺寸令牌（v3/C 约定）

| 令牌 | 内置默认 | 常量 | 作用 |
|------|------|------|------|
| `--chart-donut-hole` | `55`（**百分比**，非像素） | `TyChartDonutHolePercent` | 环形内孔半径占外半径的百分比。55% = Ant Design 的环。夹在 `[0, TyChartDonutHoleMaxPercent]`（= 90）——皮肤不能把图表抹掉。 |
| `--chart-hit-radius` | `12`（逻辑像素） | `TyChartHitRadius` | 折线标记点的抓取半径。设为 0 = 关闭折线悬停。 |
| `--chart-tooltip-gap` | `10`（逻辑像素） | `TyChartTooltipGap` | 数据点与 tooltip 框之间的间隙。 |
| `--chart-tooltip-swatch` | `8`（逻辑像素） | `TyChartTooltipSwatch` | tooltip 里的系列色块（方形，与图例色块同形状）。设为 0 = 不画色块。 |
| `--chart-tooltip-swatch-gap` | `5`（逻辑像素） | `TyChartTooltipSwatchGap` | 色块与文字之间的间隙。 |

> **为什么孔是百分比而不是长度？** 主题 metric 是整数，而圆盘尺寸由**控件**决定（不是主题）——写死像素的孔在改变控件大小时就错了。所以它是相对外半径的比例。这是本控件唯一一个「metric 不是长度」的令牌，代码里有注释标明。

### 系列调色板的边界

系列 / 扇区颜色**不走主题**，用代码里的 `TyChartPalette`（Tableau-10）。这是有意的：图表需要一组**互相可区分**的定性色相，这是数据可视化的约束，不是皮肤的审美选择；一个 5-seed 的主题调色板派生不出 8 个可区分的色相。要换色：按系列设 `TTyChartSeriesItem.Color`（`clDefault` 以外的值即覆盖）。tooltip 的色块、图例的色块、柱 / 线 / 扇区**共用同一个解析入口**（`SeriesColor` / `SliceColor`），不会各说各话。

---

## 8. 代码示例

```pascal
uses tyControls.Controller, tyControls.Chart;

TyDefaultController.LoadTheme('themes/light.tycss');

var C: TTyChart;

// 分组柱状图 + tooltip（默认就开）
C := TTyChart.Create(Self);
C.Parent := Surface;
C.Align := alClient;
C.ChartType := ctBar;
C.Title := '季度销量';
C.Categories.Text := 'Q1'#10'Q2'#10'Q3'#10'Q4';
with C.Series.Add do begin Name := '华东'; Values := '12, 19, 15, 22'; end;
with C.Series.Add do begin Name := '华南'; Values := '9, 14, 18, 16'; end;
// 悬停任一根柱 -> 弹出「Q3 / 华东: 15」

// 环形图
C := TTyChart.Create(Self);
C.Parent := Surface;
C.ChartType := ctDonut;
C.Title := '流量来源';
C.Categories.Text := '直接'#10'搜索'#10'社交'#10'其他';
with C.Series.Add do Values := '335, 310, 234, 135';
// 悬停任一扇区 -> 弹出「搜索 / 310 (29.8%)」（环形 / 饼自动带占比）
```

自定义 tooltip 文本：

```pascal
C.OnGetTooltip := @ChartGetTooltip;

procedure TForm1.ChartGetTooltip(Sender: TObject; ASeries, APoint: Integer;
  var AText: string);
begin
  if FIsForecast[APoint] then
    AText := AText + #10 + '（预测值）'
  else if FIsRedacted[ASeries] then
    AText := '';        // 只屏蔽这一个点，其余数据点照常
end;
```

点击下钻：

```pascal
procedure TForm1.ChartClick(Sender: TObject);
var
  hit: TTyChartHit;
  pos: TPoint;
begin
  pos := (Sender as TTyChart).ScreenToClient(Mouse.CursorPos);
  hit := (Sender as TTyChart).HitTestAt(pos.X, pos.Y);
  if TyChartHitValid(hit) then
    ShowDetail(hit.SeriesIndex, hit.PointIndex);
end;
```

---

## 9. 注意事项

- **tooltip 是画进去的覆盖层，不是 LCL 提示窗口。** 三个理由：(1) LCL 的 `THintWindow` 由 `Application` 的提示计时器驱动、每控件一份文本，天生表达不了「指针下的**数据点**」这种每像素都可能变的内容；(2) 它是**独立的顶层窗口**，会在图表外面投影、抢夺激活、在 Wayland 下走 popup 那套坑；(3) 画在自己的位图里意味着它跟着图表一起被主题解析、一起被 `TyChartTooltipRect` 夹在控件边界内，不会飘到窗口外。代价：tooltip **不能超出图表控件的边界**——图表做得太小时框会被夹进去甚至裁掉（`TestTooltipRectOversizedIsPinnedNotHidden` 明确守护「宁可裁也不藏」）。
- **零值柱不可悬停。** 零值画出来是零高度、什么都看不见，所以它的矩形不包含任何点，tooltip 不会声称那里有数据。这是刻意的（`TestBarHitTestZeroValueIsNotHittable`），不是漏洞。
- **数据变了会抹掉悬停状态。** `Series` / `Categories` / `ChartType` 变化时停放的命中会被清掉（旧索引可能指向已经不存在的数据）；绘制路径**还会再校验一次**索引——因为鼠标不动时系列也可能在脚下缩短。
- **重绘只在数据点变化时发生**，不是每移动一个像素——整个图表每次都是从零重画的，逐像素 invalidate 是肉眼可见的开销。
- **图形控件，非容器：** 无窗口句柄，子控件不能以它为 `Parent`。
- **tooltip 不用 `DrawFrame`。** `DrawFrame` 是**控件自身**外框的路径，它会把 `tpOpacity` 推给 painter，而 `EndPaint` 会把这个透明度作用到**整张位图**上——tooltip 样式里若带 `opacity` 就会把整个图表一起淡掉。所以 tooltip 走「子元素自绘表面」那一套（同 `TTyTag` 的关闭底片）。
- **`ShowValues` 与 `ShowTooltip` 相互独立**：前者是常驻标注（打印 / 截图用），后者是交互式的。
- **空数据 / 系列短于 Categories / max == min / 全零饼 / 极小控件**全部安全（不崩、不除零、不产生反向矩形）。

---

## 10. 关联

见 `docs/design/2026-07-16-antd-gap-controls.md`。装饰性矢量图元见 [TTyShape](shape.md)；单值迷你趋势线见 [TTySparkline](sparkline.md)。
