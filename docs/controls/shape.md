# TTyShape

## 1. 概述

TTyShape 是 TyControls 的**通用矢量形状控件**(TShape 的主题化重制),继承自 `TTyGraphicControl`(叶子图形控件,无焦点 / 子控件)。它用 BGRABitmap 的 `Canvas2D` 抗锯齿绘制一个矢量形状——矩形、圆角矩形、正方形、椭圆、圆、三角形、菱形或一条对角线——**填充色取自解析后的 `TyShape` 背景,描边取自 `TyShape` 边框**。控件不硬编码任何颜色:填充 / 边框全部来自解析后的 `TyShape` 样式,因此形状跟随当前主题。要给整套示意图换色,在主题里写 `TyShape { ... }`;要单独给某个形状换色,用 `StyleClass` / `StyleOverride`(例如 `StyleOverride := 'background: #E11; border-color: #700;'`)。

典型用途:流程图 / 示意图里的节点与连接、装饰性色块、分区图标。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Shape` |
| `GetStyleTypeKey` 返回值 | `'TyShape'`(**自有 typeKey**)|

它从前返回 `'TyPanel'`。示意图里的图元不是容器表面:借用面板键意味着"想让图形用强调色填充"就得把全应用的面板一起重涂,反过来"给面板加卡片式圆角 + 细边"也会同时改掉每一个圆角矩形节点和每一条连接线。现在 `TyShape` 已作为附加选择器并入主题里 `TyPanel` 的规则块,解析值与从前逐字节相同,**开钩子而不动像素**;第三方主题若只覆盖了 `TyPanel`,需要补上 `TyShape`(主题层按 typeKey 全有全无地回落)。同族的 [`TTyStarShape`](starshape.md)、[`TTyArrow`](arrow.md) 也各自有了键,三者可以分别调色。

- **填充** = `TyShape` 的 `background`(仅当为纯色且非全透明时填充);
- **描边** = `TyShape` 的 `border-color`,线宽 `max(1, Scale(border-width))`;`border-style: none`
  与 `border-width: 0` 都会关掉描边(判据 `TyBorderVisible`,与库内其它控件一致)。**例外**:
  `tskLine` 的那条线本身就是形状而非外框,始终绘制;
- **圆角矩形** 的圆角取自 `TyShape` 的 `border-radius`。

### 子部件 typeKey

**没有。** 形状只有一个盒子样式,没有子部件。仍在代码里写死、主题够不着的两处:`tskLine` 的端点是固定的圆头(`lineCap = 'round'`),多边形的拐角是固定的尖角(`lineJoin = 'miter'`,与 `TTyStarShape` 的 `'round'` 不一致)。

```pascal
uses tyControls.Shape;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Shape` | `TTyShapeKind` | `tskRectangle` | 绘制的矢量形状(见下表)。 |

**`TTyShapeKind` 取值:**

| 值 | 含义 |
|------|------|
| `tskRectangle` | 充满控件矩形的矩形(填充 + 描边)。 |
| `tskRoundRect` | 圆角矩形,圆角半径取自主题 `border-radius`。 |
| `tskSquare` | 内缩到控件矩形内**最大居中正方形**的正方形。 |
| `tskEllipse` | 充满控件矩形的椭圆。 |
| `tskCircle` | 内缩到最大居中正方形的圆。 |
| `tskTriangle` | 等腰三角形(顶点在上中,底边为矩形下两角)。 |
| `tskDiamond` | 菱形(四个顶点在矩形四边中点)。 |
| `tskLine` | 左上 → 右下的对角线,仅用边框色描边(无填充)。 |

### 继承的通用成员

| 属性 | 类型 | 说明 |
|------|------|------|
| `StyleClass` | `string` | `.tycss` 类名(作用于 `TyShape` 解析)。 |
| `StyleOverride` | `string` | 每实例 CSS 覆盖块(可用 `var(--...)`),用于单独设置本形状的填充 / 边框色。 |
| `Controller` | `TTyStyleController` | 指定样式控制器(nil 时用全局默认)。 |
| `Align` / `Anchors` | — | 布局。 |

**枚举:** `TTyShapeKind = (tskRectangle, tskRoundRect, tskSquare, tskEllipse, tskCircle, tskTriangle, tskDiamond, tskLine)`。

---

## 4. 事件

TTyShape 暴露 `TTyGraphicControl` 的**基线事件集**(Tier A 鼠标 / 通用事件)。作为纯展示控件,自身不新增任何命令事件。完整清单见 [../events.md](../events.md)。

---

## 5. 状态与主题

### 支持的伪类状态

| 伪类 | 触发条件 |
|------|----------|
| `:disabled` | `Enabled = False`(`TyShape` 若定义 `opacity` 则整体变淡)。 |

(无 hover / focus / active——纯展示控件。)

### 颜色推导

- **填充**:`background` 为纯色且 alpha > 0 时填充该色;否则(无背景 / 全透明)只描边不填充。
- **描边**:`border-color`,线宽 `max(1, Scale(border-width))`;仅当 `TyBorderVisible` 为真(声明了 `border-color`、`border-width > 0`、且未显式 `border-style: none`)时绘制。Canvas2D 的描边以路径为中心线,故几何四边各内缩 `ceil(线宽/2)`,使边框完整落在控件矩形内;无描边时形状铺满整个矩形。
- `tskLine` 只画对角线(边框色 + 圆头端点),不填充;它是形状本体,不受 `border-style: none` / `border-width: 0` 影响。

因填充 / 边框取自 `TyShape` 主题规则,更换主题即更换形状颜色。要单独调色,用 `StyleOverride`(例如 `'background: var(--accent); border-color: var(--border);'`)。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.Shape;

TyDefaultController.LoadTheme('themes/light.tycss');

// 一个填充的椭圆节点
var Node: TTyShape;
Node := TTyShape.Create(Self);
Node.Parent := Self;
Node.SetBounds(20, 20, 120, 80);
Node.Shape := tskEllipse;

// 一个强调色菱形判定框
var Decision: TTyShape;
Decision := TTyShape.Create(Self);
Decision.Parent := Self;
Decision.SetBounds(160, 20, 100, 100);
Decision.Shape := tskDiamond;
Decision.StyleOverride := 'background: #E11; border-color: #700;';

// 一条对角连接线
var Link: TTyShape;
Link := TTyShape.Create(Self);
Link.Parent := Self;
Link.SetBounds(20, 120, 240, 40);
Link.Shape := tskLine;
```

---

## 7. 注意事项

- **纯几何可测:** 顶点型形状(三角形 / 菱形)的顶点由纯函数 `TyShapePolygon(Kind, Rect)` 计算,`tskSquare` / `tskCircle` 的最大居中正方形由 `TyShapeSquareRect(Rect)` 计算;两者均无窗口句柄 / painter 依赖,已 headless 单元测试。矩形 / 圆角矩形 / 椭圆 / 线由 `RenderTo` 直接绘制,对这些 kind `TyShapePolygon` 返回 `[]`。
- **Square / Circle 内缩:** 取控件矩形内最大居中正方形,因此在非正方形控件上正方形 / 圆保持不变形。
- **RoundRect 圆角来自主题:** 圆角半径 = `TyShape` 的 `border-radius`(经 `Scale` 缩放,且不超过较短边的一半);主题半径为 0 时退化为普通矩形。现在这个半径与面板的半径互相独立——改面板圆角不会再连带改圆角矩形节点。
- **HiDPI:** 线宽与圆角均经 `Painter.Scale` 缩放。
- **主题驱动:** 填充 / 边框颜色全部由 `TyShape` 主题规则推导,控件不硬编码任何颜色(库的硬性规则)。端点 / 拐角样式(`round` / `miter`)仍是代码字面量,主题改不了。
