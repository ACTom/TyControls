# TTyStarShape

## 1. 概述

TTyStarShape 是 TyControls 的**装饰性矢量星形控件**,继承自 `TTyGraphicControl`(叶子图形控件,无焦点 / 子控件)。它用 BGRABitmap `Canvas2D` 抗锯齿绘制一个 N 角星:星形居中,外半径 = `min(宽,高)/2` 减去一个小边距,内半径 = 外半径 × `InnerRatio`,第一个外顶点指向**正上方**。填充色 / 边框色全部来自主题解析(复用 `TyPanel` token),因此星形跟随当前主题——**不硬编码任何颜色**。

典型用途:评级 / 收藏 / 奖励类装饰徽标、加载 / 空状态占位图形、纯装饰性的角标。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.StarShape` |
| `GetStyleTypeKey` 返回值 | `'TyPanel'`(复用面板 typeKey,不新增主题 token)|

**填充** = 解析后 `TyPanel` 样式的 `background`(纯色且非全透明时才填);**边框** = 其 `border-color`,线宽 `max(1, Scale(border-width))`,`border-style: none` 或 `border-width: 0` 会关掉描边。要单独调色用 `StyleClass` / `StyleOverride`(如 `StyleOverride := 'background: #E11; border-color: #700;'`)。

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

### 继承的通用成员

| 属性 | 类型 | 说明 |
|------|------|------|
| `StyleClass` | `string` | `.tycss` 类名(作用于 `TyPanel` 解析)。 |
| `StyleOverride` | `string` | 每实例 CSS 覆盖块(可用 `var(--...)`),用于单独指定填充 / 边框色。 |
| `Controller` | `TTyStyleController` | 指定样式控制器(nil 时用全局默认)。 |
| `Align` / `Anchors` | — | 布局。 |

---

## 4. 事件

TTyStarShape 暴露 `TTyGraphicControl` 的**基线事件集**(Tier A 鼠标 / 通用事件)。作为纯装饰控件,自身不新增任何命令事件。完整清单见 [../events.md](../events.md)。

---

## 5. 状态与主题

### 支持的伪类状态

| 伪类 | 触发条件 |
|------|----------|
| `:disabled` | `Enabled = False`(`TyPanel` 若定义 `opacity` 则整体变淡)。 |

（无 hover / focus / active——纯展示控件。）

### 绘制

1. 由纯函数 `TyStarPolygon(ARect, Points, InnerRatio)` 求出 `2*Points` 个交替外 / 内半径的顶点(设备像素,顶点 0 指向正上方)。传入的矩形已内缩 `Scale(2) + ceil(线宽/2)`:外顶点正落在该矩形边上,而 Canvas2D 的描边以路径为中心线,不多留这半个线宽的话,粗边框(或高 DPI)会把星尖描边裁掉。
2. 用 `Canvas2D` 沿这些顶点 `beginPath` → `moveTo`/`lineTo` → `closePath` 描出闭合星形路径。
3. **填充**:`background` 为纯色且非全透明时 `fill`(否则跳过——星形透明,底下内容透出)。
4. **描边**:仅当 `TyBorderVisible` 为真(声明了 `border-color`、`border-width > 0`、且未显式 `border-style: none`)时,以 `max(1, Scale(border-width))` 的线宽 `stroke`。

因颜色取自 `TyPanel` 主题规则,更换主题即更换星形配色。

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

- **顶点朝上:** 第一个外顶点(索引 0)恒指向正上方(12 点方向),外顶点在偶数索引、内顶点在奇数索引。
- **外半径取短边:** 非正方形控件中外半径 = `min(宽,高)/2 - 边距`,星形不会溢出较长边。
- **无自身矩形填充:** 只填充 / 描边星形本身,矩形其余区域保持透明——叠在其他背景之上不会遮挡。
- **纯几何可测:** `TyStarPolygon` 是纯函数(输入 `TRect` + 参数,返回顶点数组),已 headless 单元测试(顶点数 = `2*max(3,Points)`、内外半径交替、全部落在 `ARect` 内、`Points<3` 与 `InnerRatio` 越界均夹紧、左右对称)。
- **HiDPI:** 边距与边框线宽经 `Painter.Scale` 缩放。
- **主题驱动:** 填充 / 边框颜色全部由 `TyPanel` 主题规则推导,控件不硬编码任何颜色(库的硬性规则)。
