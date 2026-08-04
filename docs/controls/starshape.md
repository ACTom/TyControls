# TTyStarShape

## 1. 概述

TTyStarShape 是 TyControls 的**装饰性矢量星形控件**,继承自 `TTyGraphicControl`(叶子图形控件,无焦点 / 子控件)。它用 BGRABitmap `Canvas2D` 抗锯齿绘制一个 N 角星:星形居中,外半径 = `min(宽,高)/2` 减去一个小边距,内半径 = 外半径 × `InnerRatio`,第一个外顶点指向**正上方**。填充色 / 边框色全部来自本控件自有 typeKey `TyStarShape` 的解析结果,因此星形跟随当前主题——**不硬编码任何颜色**。

典型用途:评级 / 收藏 / 奖励类装饰徽标、加载 / 空状态占位图形、纯装饰性的角标。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.StarShape` |
| `GetStyleTypeKey` 返回值 | `'TyStarShape'`(**自有 typeKey**)|

它从前返回 `'TyPanel'`:一颗装饰星不是容器表面,而借用面板键的实际后果是——想给徽标星换个金色,就必须把全应用里每一个容器一起重涂。现在 `TyStarShape` 已作为附加选择器并入主题里 `TyPanel` 的规则块,解析值与从前逐字节相同,**开钩子而不动像素**;第三方主题若只覆盖了 `TyPanel`,需要补上 `TyStarShape`(主题层按 typeKey 全有全无地回落)。

> 注意区分:[`TTyRating`](rating.md) 的星星走的是它自己的 `TyRatingStar`,与本控件无关——这里是一颗**装饰**星,那里是一个评分部件的星。

**填充** = 解析后 `TyStarShape` 样式的 `background`(纯色且非全透明时才填);**边框** = 其 `border-color`,线宽 `max(1, Scale(border-width))`,`border-style: none` 或 `border-width: 0` 会关掉描边。要单独调色用 `StyleClass` / `StyleOverride`(如 `StyleOverride := 'background: #E11; border-color: #700;'`)。

### 子部件 typeKey

**没有。** 星形只有一个盒子样式。仍在代码里写死、主题够不着的两处:边缘内缩常量 `TyStarMargin = 2`(逻辑像素),以及固定的圆角拐点(`lineJoin = 'round'`)——所以"尖角星"目前无法通过主题表达。

```pascal
uses tyControls.StarShape;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Points` | `Integer` | `5` | 星形外角数;setter 夹紧到 `>= 3`(低于 3 视为三角星)。 |
| `InnerRatio` | `Single` | `0.42` | 内半径占外半径的比例;setter 夹紧到 `0.05 .. 0.95`。 |
| `PointDown` | `Boolean` | `False` | 把整个顶点环转半步,顶点 0 改指正下方(6 点方向)。对应 LCL 的 `stStarDown`——本控件从前**没有任何旋转手段**,这个形状在任何属性组合下都画不出来。 |

### 继承的通用成员

| 属性 | 类型 | 说明 |
|------|------|------|
| `StyleClass` | `string` | `.tycss` 类名(作用于 `TyStarShape` 解析)。 |
| `StyleOverride` | `string` | 每实例 CSS 覆盖块(可用 `var(--...)`),用于单独指定填充 / 边框色。 |
| `Controller` | `TTyStyleController` | 指定样式控制器(nil 时用全局默认)。 |
| `Align` / `Anchors` | — | 布局。 |

---

## 4. 事件与命中测试

TTyStarShape 暴露 `TTyGraphicControl` 的**基线事件集**(Tier A 鼠标 / 通用事件),外加一个自有事件。完整清单见 [../events.md](../events.md)。

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnShapeClick` | `TNotifyEvent` | 点击**落在星形墨迹上**时(而非只落在外接矩形内)。对应 `TShape.OnShapeClick`——本库用这个独立控件顶替 `Shape = stStar`,事件名也一并对齐。 |

### 命中测试按**形状**,不按外接矩形

星形是这件事最极端的例子:五个尖角之间是五道很深的凹口,加上四个空角,外接矩形里有一大片**根本没画过的画布**。从前控件对这些位置一律回答"是我的",于是**任何压在星角背后的控件都点不到**。

| 成员 | 说明 |
|------|------|
| `PtInShape(APt: TPoint): Boolean` | `APt` 为**客户区像素**(判的是像素格中心 `(x+0.5, y+0.5)`);返回它是否落在星形的填充或描边上。 |
| `StarGeometry: TTyStarGeometry` | 下一次绘制将使用的几何(内缩后的外接盒、夹紧后的 `Points` / `InnerRatio`、`PointDown`、描边宽度、是否描边、是否退化)。**绘制与命中测试读的是同一条记录**——`RenderTo` 自己不再算任何一个数。 |
| `CM_HITTEST` | 运行期钩子,**非 0 表示命中**;答 0 的控件被跳过,消息落到下层。 |
| `CM_MASKHITTEST` | 设计期钩子(仅 Lazarus 设计器)。**极性相反:0 才表示"在形状上"**。取不到设计器窗体时回落为 0(可选中)。 |

判定是**解析式**的(交叉数法判点在凹多边形内,再按 `描边宽度 / 2` 外扩出描边带),不是渲染掩码。守卫测试直接比对渲染出来的墨迹与命中区域(`tests/test.parity.starshape.pas`),这是唯一能抓住"绘制路径又自己推了一遍几何"的检查。

---

## 5. 状态与主题

### 支持的伪类状态

| 伪类 | 触发条件 |
|------|----------|
| `:disabled` | `Enabled = False`(`TyStarShape` 若定义 `opacity` 则整体变淡)。 |

（无 hover / focus / active——纯展示控件。）

### 绘制

1. 由纯函数 `TyStarPolygon(ARect, Points, InnerRatio)` 求出 `2*Points` 个交替外 / 内半径的顶点(设备像素,顶点 0 指向正上方)。传入的矩形已内缩 `Scale(2) + ceil(线宽/2)`:外顶点正落在该矩形边上,而 Canvas2D 的描边以路径为中心线,不多留这半个线宽的话,粗边框(或高 DPI)会把星尖描边裁掉。
2. 用 `Canvas2D` 沿这些顶点 `beginPath` → `moveTo`/`lineTo` → `closePath` 描出闭合星形路径。
3. **填充**:`background` 为纯色且非全透明时 `fill`(否则跳过——星形透明,底下内容透出)。
4. **描边**:仅当 `TyBorderVisible` 为真(声明了 `border-color`、`border-width > 0`、且未显式 `border-style: none`)时,以 `max(1, Scale(border-width))` 的线宽 `stroke`。

因颜色取自 `TyStarShape` 主题规则,更换主题即更换星形配色;要让星形与容器分道扬镳,写一条 `TyStarShape { background: gold; border-color: ...; }` 即可,不必也不应去动 `TyPanel`。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.StarShape;

TyDefaultController.LoadTheme('themes/light.tycss');

// 默认五角星(主题面板配色)
var Star: TTyStarShape;
Star := TTyStarShape.Create(Self);
Star.Parent := Self;
Star.SetBounds(16, 16, 96, 96);

// 一个瘦长的红色八角星
var Burst: TTyStarShape;
Burst := TTyStarShape.Create(Self);
Burst.Parent := Self;
Burst.SetBounds(130, 16, 96, 96);
Burst.Points := 8;
Burst.InnerRatio := 0.6;
Burst.StyleOverride := 'background: #E11; border-color: #700;';
```

---

## 7. 注意事项

- **顶点朝上:** 第一个外顶点(索引 0)默认指向正上方(12 点方向),`PointDown = True` 时改指正下方;外顶点在偶数索引、内顶点在奇数索引。
- **顶点环只有一份实现:** 环本身是 `tyControls.Shape` 的 `TyStarRingPolygon`,`TTyShape` 的 `tskStar` / `tskStarDown` 与本控件都调它;`TyStarPolygon` 只是套了本控件 `Points` / `InnerRatio` 夹紧规则的薄封装。两份顶点表就是两处会分歧的几何。
- **外半径取短边:** 非正方形控件中外半径 = `min(宽,高)/2 - 边距`,星形不会溢出较长边。
- **无自身矩形填充:** 只填充 / 描边星形本身,矩形其余区域保持透明——叠在其他背景之上不会遮挡。
- **纯几何可测:** `TyStarPolygon` 是纯函数(输入 `TRect` + 参数,返回顶点数组),已 headless 单元测试(顶点数 = `2*max(3,Points)`、内外半径交替、全部落在 `ARect` 内、`Points<3` 与 `InnerRatio` 越界均夹紧、左右对称)。
- **HiDPI:** 边距与边框线宽经 `Painter.Scale` 缩放。
- **主题驱动:** 填充 / 边框颜色全部由 `TyStarShape` 主题规则推导,控件不硬编码任何颜色(库的硬性规则)。拐角样式与 `TyStarMargin` 边距仍是代码字面量。
