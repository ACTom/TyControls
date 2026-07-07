# TTyDivider

## 1. 概述

`TTyDivider` 是 TyControls 库中的主题化「带标题的水平分割线」控件，继承自 `TTyGraphicControl`（图形控件，无窗口句柄，不能作为父容器）。它把一段标题文字与一条 1 像素水平细线组合成一个分区标题：文字用解析后的 `TyLabel` 主题样式绘制，细线填充标题之外的横向空间、垂直居中，颜色由主题令牌驱动。典型用途：在表单、设置面板中划分小节（例如「常规」「高级」等分组标题），比裸标签更有「一栏到底」的分区感。

标题相对细线的位置由 `Alignment` 决定：

- `taLeftJustify`（默认）——标题在左，细线填充其右侧；
- `taRightJustify`——镜像（标题在右，细线在其左侧）；
- `taCenter`——标题居中，两侧各一段细线。

标题为空字符串时，退化为一条贯穿整宽的水平细线（可当作纯分隔线使用）。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Divider` |
| `GetStyleTypeKey` 返回值 | `'TyLabel'`（**复用** TyLabel 令牌，本控件不引入新的 `.tycss` 令牌） |
| 基类 | `TTyGraphicControl`（继承自 `TGraphicControl`） |
| 默认尺寸 | 150 × 24（逻辑像素，构造时设置） |

在 `.tycss` 文件中，本控件复用 `TyLabel` 选择器前缀——标题文字取 `TyLabel` 的 `color`/`font-*`，细线颜色优先取 `TyLabel` 的 `border-color`（见下文），无需为分割线单独定义主题规则。

```pascal
uses tyControls.Divider;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Caption` | `string` | `''` | 标题文字，用解析后的 `TyLabel` 样式绘制（**不**读取 LCL `Font.*`）；为空时绘制一条贯穿整宽的细线。赋值触发 `Invalidate`。 |
| `Alignment` | `TAlignment` | `taLeftJustify` | 标题相对细线的位置：`taLeftJustify`（标题在左 + 右侧细线）/ `taRightJustify`（镜像）/ `taCenter`（标题居中 + 两侧细线，`default taLeftJustify`）。赋值触发 `Invalidate`。 |
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式（常用 `alTop` 让分割线横贯一栏）。 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点。 |

### 继承的通用成员

`TTyDivider` 继承自 `TTyGraphicControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分（可用来给某些分割线单独换色）。 |
| `StyleOverride` | `string` | `''` | 单实例内联 CSS 声明块（可引用 `var(--...)` 令牌）。 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器。 |

> **无独立交互状态字段：** `TTyDivider` 未声明自己的 `FHover`/`FPressed` 逻辑，也未重写 `CurrentStates`；它是纯展示控件，绘制只解析 `CurrentStyle`（普通态样式）。`:disabled`（`Enabled = False`）等仍由基类状态机计算，但控件本身无交互态视觉切换。

---

## 4. 关键成员

### 纯几何函数（单元级，可无句柄直接调用）

```pascal
type
  TTyDividerLayout = record
    CaptionRect: TRect;   // 标题绘制矩形（空 => 无标题）
    LeftRule: TRect;      // 左侧细线段（Left..Right 跨度，Top..Bottom 波段）
    RightRule: TRect;     // 右侧细线段
  end;

function TyDividerLayout(AClientWidth, AClientHeight, ACaptionWidth: Integer;
  AAlign: TAlignment; AGap, AMinRule, ARuleThick: Integer): TTyDividerLayout;
```

`TyDividerLayout` 是本控件的核心：给定内容区宽高、已测量的标题宽度、对齐方式，以及间隙 / 最短细线 / 细线厚度（均为**设备像素**），算出标题矩形与最多两段细线的几何。全部为整数入参、无控件状态、无句柄依赖，因此测试可直接调用验证（`tests/test.divider.pas`）。要点：

- 细线波段**垂直居中**于内容高度（`(H - ARuleThick) div 2`）。
- 标题与相邻细线之间留 `AGap` 间隙；细线段长度 `< AMinRule` 时**整段丢弃**（避免标题占满宽度时残留 1 像素的小凸起）。
- `ACaptionWidth = 0` → 无标题，返回一条整宽细线（放在 `RightRule`）。
- `ACaptionWidth > AClientWidth` → 夹紧到整宽，无细线容身。
- `AClientWidth <= 0` → 全空（三个矩形都为空）。

### 绘制流程（`RenderTo`）

`RenderTo(ACanvas, ARect, APPI)` 与库内其它控件一致：创建 `TTyPainter` → `BeginPaint` → 取 `CurrentStyle` → 按 `padding` 内缩内容区 → 用 `P.MeasureText` 测量标题宽度 → 调 `TyDividerLayout` 得几何 → 用 `P.FillBackground`（实心、无圆角）画细线段、用 `P.DrawText` 画标题 → `EndPaint`。`Paint` 只是 `RenderTo(Canvas, ClientRect, Font.PixelsPerInch)`。

**细线颜色（主题令牌驱动，绝不写死）：**

- 若解析样式含 `border-color` 且不透明 → 细线用该 `border-color`；
- 否则从 `color`（文字色）派生一条淡化细线（取文字色、透明度降到 40%）。

两者都直接来自解析后的 `TyLabel` 样式，不在控件代码中硬编码任何颜色值。

---

## 5. 状态与主题

### 支持的伪类状态

`TTyDivider` 绘制时只解析 `CurrentStyle`（普通态），**不区分** `:hover`/`:focus`/`:active` 的差异化外观。它是透明叠加控件（像默认的 `TTyLabel`）：**不**绘制主题背景填充，但仍尊重 `opacity` 令牌（如 `:disabled { opacity: 0.5 }`），因此禁用时会整体变淡。

### 复用 TyLabel 令牌摘要

```css
TyLabel {
  color: var(--on-surface);        /* 标题文字颜色，也是细线的派生来源 */
  border-color: var(--border);     /* 若存在，则为细线首选颜色 */
  font-size: var(--font-size-base);
  font-weight: var(--font-weight-normal);
  padding: ...;                    /* 决定标题/细线到控件左右边缘的内边距 */
}
```

要让某些分割线换一种细线颜色，可给它设 `StyleClass`（对应 `.tycss` 里 `TyLabel.myclass { border-color: ...; }`），或用 `StyleOverride: 'border-color: var(--accent);'`。

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.Divider;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

var
  D: TTyDivider;
begin
  // 左对齐分区标题：文字在左，细线延伸到右边缘
  D := TTyDivider.Create(Self);
  D.Parent := Self;
  D.Caption := '常规';
  D.Alignment := taLeftJustify;
  D.SetBounds(16, 16, 300, 24);

  // 居中标题：两侧各一段细线
  D := TTyDivider.Create(Self);
  D.Parent := Self;
  D.Caption := '高级选项';
  D.Alignment := taCenter;
  D.SetBounds(16, 120, 300, 24);

  // 纯分隔线（无标题）：一条贯穿整宽的细线
  D := TTyDivider.Create(Self);
  D.Parent := Self;
  D.Caption := '';
  D.SetBounds(16, 200, 300, 24);

  // 用 alTop 让分割线横贯一栏（配合 Panel/表单分区）
  D := TTyDivider.Create(Self);
  D.Parent := Self;
  D.Caption := '危险区';
  D.Align := alTop;
  D.StyleOverride := 'border-color: var(--danger);';  // 该条细线换成危险色
end;
```

---

## 7. 注意事项

- **图形控件，非容器：** `TTyDivider` 继承自 `TGraphicControl`，**没有窗口句柄，不能作为父容器**（子控件不能以它为 `Parent`）。它只负责画一行「标题 + 细线」，用于分区视觉，而不是真正切分布局。若需要真正容纳子控件的分组框，请用 `TTyPanel` / `TTyGroupBox`。
- **文字用主题样式，不读 LCL Font：** 标题按解析后的 `TyLabel` 样式（`color`/`font-size`/`font-weight`/`font-family`）在 `Paint` 中绘制，**不**依赖 LCL 的 `Font.*`（遵循「主题锁定的 TyLabel」约定）。要改字号/字色，改主题令牌或用 `StyleClass`/`StyleOverride`。
- **细线颜色来自令牌：** 细线首选 `border-color`，无则由 `color` 淡化派生，**绝不写死颜色**（视觉值必须由主题驱动）。
- **标题占满宽度时细线会消失：** 当标题宽度加间隙后剩余空间不足 `AMinRule`（默认 4 逻辑像素），对应细线段整段丢弃，只显示文字——这是有意为之，避免残留 1 像素小凸起。
- **透明叠加、不画背景：** 控件不填充主题背景，直接叠在宿主表面上；确保它所在的父背景已铺好（如放在 `TTyPanel` 内会显出面板底色）。仍然尊重 `opacity`，禁用时整体变淡。
- **默认尺寸：** 构造时 `Width=150, Height=24`；通常用 `SetBounds` 或 `Align := alTop` 调整为实际所需宽度。高度决定细线垂直居中的位置。
