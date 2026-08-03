# TTyArrow

## 1. 概述

`TTyArrow` 是 TyControls 的**方向性箭头**矢量形状控件，继承自 `TTyGraphicControl`（图形控件，无窗口句柄，不能作为父容器）。它有两种字形，由 `Shape` 选择：

- **`tasBlock`（默认）**——经典的 **7 顶点块状箭头**：一段矩形箭杆在末端展宽成三角箭头，指向上 / 下 / 左 / 右四个方向之一。箭头头部长度（占总长度的比例）与箭杆粗细（占宽度的比例）可分别通过 `HeadRatio` / `ShaftRatio` 调整。
- **`tasTriangle`**——LCL `TArrow` 的字形：光秃的 **3 顶点三角形**，顶角由 `ArrowPointerAngle`（度，默认 60 即等边）决定，按该角度拟合进客户区并居中。本库此前画不出这个字形，别的控件也没有一个能画有方向的三角形。

典型用途：流程图 / 引导图中的指向标记、"下一步 / 上一步"装饰箭头、方向指示徽标等。形状用 BGRABitmap 的 `Canvas2D` 抗锯齿矢量路径绘制，跨平台像素一致。

**颜色全部来自主题**：控件解析自己的 `TyArrow` 样式——填充取 `TyArrow` 的 `background`（纯色），描边取其 `border-color` / `border-width`。控件代码里**不硬编码任何颜色**；要给某个箭头单独换色，用 `StyleClass` / `StyleOverride`。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Arrow` |
| `GetStyleTypeKey` 返回值 | `'TyArrow'`（**自有 typeKey**）|
| 基类 | `TTyGraphicControl`（继承自 `TGraphicControl`）|
| 默认尺寸 | 120 × 64（逻辑像素，构造时设置）|

它从前返回 `'TyPanel'`。箭头既不画框也不画标题，它只是一块有向的示意图墨迹；借用面板键让示意图家族（[`TTyShape`](shape.md) / [`TTyStarShape`](starshape.md) / `TTyArrow`，在组件面板上就是并排注册的）与全应用的容器共用一个颜色，于是"示意图用强调色、容器保持中性"这句话根本无法表达。现在三者各有其名。`TyArrow` 已作为附加选择器并入主题里 `TyPanel` 的规则块，解析值与从前逐字节相同，**开钩子而不动像素**；第三方主题若只覆盖了 `TyPanel`，需要补上 `TyArrow`（主题层按 typeKey 全有全无地回落）。

### 子部件 typeKey

**没有。** 箭头只有一个盒子样式。仍在代码里写死、主题够不着的一处：拐角为固定尖角（`lineJoin = 'miter'`），因此描边一旦加粗，箭尾的倒角会长出尖刺，而主题无从干预。`tasTriangle` 用同一套描边设置，所以顶角很锐（接近下限 20°）且边框较粗时，尖端同样会拉出 miter 尖刺。

```pascal
uses tyControls.Arrow;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Direction` | `TTyArrowDirection` | `tadRight` | 箭头指向：`tadRight` / `tadLeft` / `tadUp` / `tadDown`。赋值触发 `Invalidate`。 |
| `Shape` | `TTyArrowShape` | `tasBlock` | 画哪种字形：`tasBlock` = 7 顶点块状箭头（本库观感，**默认不变**）；`tasTriangle` = LCL `TArrow` 的 3 顶点三角形。赋值触发 `Invalidate`。 |
| `ArrowPointerAngle` | `Integer` | `60` | **仅 `tasTriangle` 生效**：三角形的**顶角**度数，**夹紧到 20..160**。60° 即等边三角形。名字、默认值、上下限均与 LCL `TArrow` 逐字一致。赋值触发 `Invalidate`。 |
| `HeadRatio` | `Single` | `0.45` | **仅 `tasBlock` 生效**：三角箭头占**总长度**（沿指向轴的方向）的比例，**夹紧到 0.1..0.9**。越大箭头越长、箭杆越短。赋值触发 `Invalidate`。 |
| `ShaftRatio` | `Single` | `0.5` | **仅 `tasBlock` 生效**：箭杆粗细占**宽度**（垂直于指向轴的方向）的比例，**夹紧到 0.1..0.9**。越大箭杆越粗。赋值触发 `Invalidate`。 |

**枚举：** `TTyArrowDirection = (tadRight, tadLeft, tadUp, tadDown)`、`TTyArrowShape = (tasBlock, tasTriangle)`。

> 两组比例互不干扰：`HeadRatio` / `ShaftRatio` 只描述块状箭头，`ArrowPointerAngle` 只描述三角形，在另一种字形下各自静默失效。它们都是**几何**而非绘制值，因此与 `HeadRatio` 一样走单元常量 + published 属性，**不走主题令牌**——皮肤给箭头换色，不重新设计它。

### 继承的通用成员

| 属性 | 类型 | 说明 |
|------|------|------|
| `StyleClass` | `string` | `.tycss` 类名（作用于 `TyArrow` 解析，可给某些箭头单独换色）。 |
| `StyleOverride` | `string` | 单实例内联 CSS 覆盖块（可引用 `var(--...)`），例如 `'background: var(--accent); border-color: var(--accent);'`。 |
| `Controller` | `TTyStyleController` | 指定样式控制器（`nil` 时用全局默认）。 |
| `Align` / `Anchors` | — | 父容器内布局 / 锚点。 |

---

## 4. 关键成员

### 纯几何函数（单元级，可无句柄直接调用）

```pascal
function TyArrowPolygon(const ARect: TRect; ADir: TTyArrowDirection;
  AHeadRatio, AShaftRatio: Single): ArrayOfTPointF;
```

`TyArrowPolygon` 是本控件的核心：给定外接矩形 `ARect`、指向 `ADir`、头部 / 箭杆比例，返回**恰好 7 个** `TPointF`（设备像素），即块状箭头的顶点。全部为值入参、无控件状态、无句柄依赖，因此测试可直接调用验证（`tests/test.arrow.pas`）。要点：

- 返回顶点从**箭尖**（`Result[0]`）开始，绕头部两侧倒钩、沿一侧箭杆到箭杆尾、横过尾部、再沿另一侧箭杆回绕，顺序一致。
- **箭尖恰好落在指向边的中点**（右箭头 → 右边中点，依此类推）。
- `AHeadRatio` / `AShaftRatio` 内部**夹紧到 0.1..0.9**，越界值不会画出超出矩形的顶点。
- 所有顶点在任意方向、任意（含极端）比例下都保持在 `ARect` 之内。

```pascal
function TyArrowTrianglePolygon(const ARect: TRect; ADir: TTyArrowDirection;
  AAngleDeg: Integer): ArrayOfTPointF;
```

`tasTriangle` 的几何。顶角度数固定了三角形的**底:高 = 2·tan(角/2)**，因此哪条轴会破坏这个比例就把那条轴缩小，再在 `ARect` 里**居中**——与 LCL `CalcTrianglePoints`（`arrow.pp`）同一套拟合。两处刻意的偏离：

- **全程浮点**。LCL 用 `Trunc` 截断成整数，这正是它需要为"角 = 90°"单独打补丁的原因（`arrow.pp` 里那段 `// angle=90: 1pixel shift appears`）；浮点不需要那个特例。
- **不做 2px 内缩**。LCL 的 `cInnerOffset` / `Dec(FR.Bottom)` 只是为 `TArrow` 的投影阴影腾地方，本控件不画阴影，照抄就是抄一个不存在的需求。

要点：恰好 3 个顶点，同样**从箭尖起**、绕向与 `TyArrowPolygon` 一致（两种字形描边表现相同）；顶点全部落在 `ARect` 内；`AAngleDeg` 在几何层就**夹紧到 20..160**，绕开属性直接调函数也逃不掉。**箭尖落在指向轴的中线上，但未必落在那条边上**——角度比矩形窄时整个三角形居中、短于该边，这是角度拟合的固有结果（LCL 同理）。

### 绘制流程（`RenderTo`）

`RenderTo(ACanvas, ARect, APPI)` 与库内其它矢量控件一致：创建 `TTyPainter` → `BeginPaint` → 取 `CurrentStyle` → 按（缩放后的）描边宽度内缩一圈（使边框完整落在客户区内）→ 按 `Shape` 调 `TyArrowTrianglePolygon`（3 顶点）或 `TyArrowPolygon`（7 顶点）→ 用 `Canvas2D` 的 `beginPath` / `moveTo` / `lineTo` / `closePath` 构建路径 → 先 `fill`（当背景为可见纯色时）再 `stroke`（当边框可见时）→ `EndPaint`。两种字形只在取顶点那一步分叉，其余共用。`Paint` 只是 `RenderTo(Canvas, ClientRect, Font.PixelsPerInch)`。

**颜色（主题令牌驱动，绝不写死）：**

- **填充** = 解析样式的 `background`，仅当 `Kind` 为纯色且不透明时绘制（否则跳过填充，保持透明）。
- **描边** = 解析样式的 `border-color`，线宽 `max(1, Scale(border-width))`，仅当 `TyBorderVisible` 为真（声明了 `border-color`、`border-width > 0`、且未显式 `border-style: none`）时绘制。

两者都直接来自解析后的 `TyArrow` 样式，控件代码不含任何字面颜色值。

---

## 5. 状态与主题

### 支持的伪类状态

| 伪类 | 触发条件 |
|------|----------|
| `:disabled` | `Enabled = False`（`TyArrow` 若定义 `opacity` 则整体变淡）。 |

（无 hover / focus / active——纯展示控件。）

### TyArrow 令牌摘要

```css
TyArrow {
  background: var(--surface);      /* 箭头填充色 */
  border-color: var(--border);     /* 箭头描边色 */
  border-width: 1px;               /* 描边线宽（经 Scale 做 HiDPI 缩放）*/
}
```

内置主题把 `TyArrow` 与 `TyPanel` 等键写在同一条规则里（取值相同、名字各自独立），所以默认观感仍与面板一致；要让示意图整体换色，单独写一条 `TyArrow { ... }`——**别去改 `TyPanel`**，那会重涂全应用的容器。要让某个箭头换色，给它设 `StyleClass`（对应 `.tycss` 里 `TyArrow.myclass { background: ...; }`），或用 `StyleOverride`。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.Arrow;

TyDefaultController.LoadTheme('themes/light.tycss');

// 一个向右的默认块状箭头
var A: TTyArrow;
A := TTyArrow.Create(Self);
A.Parent := Self;
A.SetBounds(20, 20, 120, 64);
A.Direction := tadRight;

// 一个向上、头长杆细的强调色箭头
var Up: TTyArrow;
Up := TTyArrow.Create(Self);
Up.Parent := Self;
Up.SetBounds(20, 100, 64, 120);
Up.Direction := tadUp;
Up.HeadRatio := 0.6;    // 更长的箭头
Up.ShaftRatio := 0.3;   // 更细的箭杆
Up.StyleOverride := 'background: var(--accent); border-color: var(--accent);';

// LCL TArrow 的三角形字形：一个 45° 的窄尖指示器
var Tri: TTyArrow;
Tri := TTyArrow.Create(Self);
Tri.Parent := Self;
Tri.SetBounds(160, 20, 40, 40);
Tri.Shape := tasTriangle;
Tri.Direction := tadLeft;
Tri.ArrowPointerAngle := 45;   // 60 = 等边；夹紧到 20..160
```

---

## 7. 注意事项

- **与 LCL `TArrow` 的差异，只剩一条真的。** ① **形状**：`TArrow` 画三顶点**三角形**，本控件默认画七顶点**块状箭头**——但三角形不再够不着，`Shape := tasTriangle` 即可，`ArrowPointerAngle` 连名字带默认值带上下限都与 LCL 一致；② **默认朝向**：`TArrow.ArrowType` 默认 `atLeft`，本控件默认 `tadRight`——一个没配置过的箭头指的是反方向。**这条不改**：翻转默认值会把所有既有窗体上的箭头静默转向，而属性名本来也不叫 `ArrowType`，没人会照名字直接移植；③ 属性名是 `Direction`，不是 `ArrowType`（先发布的名字，改不动了）。
- **默认字形没有变。** 加三角形是**增量**：`Shape` 默认仍是 `tasBlock`，既有窗体逐像素不变。改默认值才会重画每一个既有箭头，那不是补齐 API，那是回归。
- **图形控件，非容器：** `TTyArrow` 继承自 `TGraphicControl`，**没有窗口句柄，不能作为父容器**（子控件不能以它为 `Parent`）。
- **7 顶点纯几何可测：** `TyArrowPolygon` 是纯函数（返回 7 个 `TPointF`），已 headless 单元测试覆盖顶点数、在矩形内、箭尖落在指向边中点、比例夹紧、对称性等（`tests/test.arrow.pas`）。
- **比例自动夹紧：** `HeadRatio` / `ShaftRatio` 越界（如设 `0` 或 `2.0`）会夹紧到 `0.1..0.9`，不会画出畸形或超框的箭头。
- **主题驱动、绝不写死颜色：** 填充与描边全部由 `TyArrow` 主题规则推导，换主题即换箭头颜色；单独调色用 `StyleClass` / `StyleOverride`（视觉值必须由主题驱动，是库的硬性规则）。拐角样式仍是代码字面量。
- **HiDPI：** 描边线宽为逻辑像素，经 `Painter.Scale` 缩放；高 DPI 下描边按比例加粗，矢量路径抗锯齿。
- **透明填充：** 若解析样式的背景不是可见纯色，箭头**不填充**（只描边或完全透明），直接叠在宿主表面上。
