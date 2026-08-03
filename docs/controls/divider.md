# TTyDivider

## 1. 概述

`TTyDivider` 是 TyControls 库中的主题化「带标题的水平分割线」控件，继承自 `TTyGraphicControl`（图形控件，无窗口句柄，不能作为父容器）。它把一段标题文字与一条 1 像素水平细线组合成一个分区标题：文字用解析后的 `TyDivider` 主题样式绘制，细线填充标题之外的横向空间、垂直居中，颜色由主题令牌驱动。典型用途：在表单、设置面板中划分小节（例如「常规」「高级」等分组标题），比裸标签更有「一栏到底」的分区感。

标题相对细线的位置由 `Alignment` 决定：

- `taLeftJustify`（默认）——标题在左，细线填充其右侧；
- `taRightJustify`——镜像（标题在右，细线在其左侧）；
- `taCenter`——标题居中，两侧各一段细线。

另有 `LeftIndent`：标题前缘距内容区左边的**像素**偏移（LCL `TDividerBevel` 的同名属性），用于表达
`Alignment` 说不出的「往里缩 60 像素」。**`LeftIndent >= 0` 时它赢，`Alignment` 被忽略**；默认
`TyDividerIndentAuto`（`-1`，任何负值同义）表示「不用这个旋钮，交给 `Alignment`」。详见第 3 节。

标题为空字符串时，退化为一条贯穿整宽的水平细线（可当作纯分隔线使用）。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Divider` |
| `GetStyleTypeKey` 返回值 | `'TyDivider'`（**自有键**；标题文字与细线颜色都由它解析） |
| 基类 | `TTyGraphicControl`（继承自 `TGraphicControl`） |
| 默认尺寸 | 150 × 24（逻辑像素，构造时设置） |

`TyDivider` 是本控件自己的键。它在 `themes/light.tycss` 中与 `TyLabel` 并列写在同一条规则的选择器列表里（`TyLabel, TyHtmlLabel, ..., TyDivider, TyCharImage { }`），所以解析出来的值与从前一致，但主题现在**能单独够到这条分割线**：写 `TyDivider { border-color: ...; }` 只染分割线，而**不会**给全应用的每一个标签都加上边框。这正是本控件从借 `TyLabel` 改为自有键的原因——它画的是一条**线**，不是文字装饰。

```pascal
uses tyControls.Divider;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Caption` | `TCaption` | `''` | 标题文字，用解析后的 `TyDivider` 样式绘制（**不**读取 LCL `Font.*`）；为空时绘制一条贯穿整宽的细线。**它就是 `TControl.Caption`**：`Caption` 与 `Text` 是同一个字符串（早先本控件另有一个自己的 `FCaption` 影子字段，写 `Caption` 时 `Text` 仍是空的），重绘经重写 `TextChanged` 触发。 |
| `Alignment` | `TAlignment` | `taLeftJustify` | 标题相对细线的位置：`taLeftJustify`（标题在左 + 右侧细线）/ `taRightJustify`（镜像）/ `taCenter`（标题居中 + 两侧细线，`default taLeftJustify`）。**`LeftIndent >= 0` 时本属性不生效**。赋值触发 `Invalidate`。 |
| `LeftIndent` | `Integer` | `TyDividerIndentAuto`（`-1`） | 标题前缘距内容区左边的**逻辑像素**偏移。`>= 0` 时**覆盖** `Alignment`；负值 = 交给 `Alignment`（写入时任何负数都归一成 `-1`）。赋值触发 `Invalidate`。 |
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式（常用 `alTop` 让分割线横贯一栏）。 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点。 |

### `Alignment` 与 `LeftIndent`：为什么两个都要，以及谁赢

LCL 的 `TDividerBevel` 只有 `LeftIndent`（`dividerbevel.pas:80`，`default 60`），一个 Integer 说三件事
（`:322-333`）：`> 0` = 缩进这么多像素、`= 0` = 顶左、`< 0` = 居中。它**说不出「右对齐」**。
本控件原本只有 `Alignment`，三个离散位置，**说不出「往里缩 60 像素」**。两者互不包含，所以两个都保留。

**平局规则（只有一条）：`LeftIndent >= 0` 是一个明确的像素位置，它赢；任何负值表示"我没在用这个旋钮"。**

| `TDividerBevel` | 这里怎么写 |
|---|---|
| `LeftIndent := 60` | `LeftIndent := 60` |
| `LeftIndent := 0`（顶左，无前置细线） | `LeftIndent := 0`，或 `Alignment := taLeftJustify`（两者几何**完全一致**，有测试钉住） |
| `LeftIndent := -1`（居中） | `Alignment := taCenter`（保持 `LeftIndent` 为默认） |
| —（做不到） | `Alignment := taRightJustify` |

> **移植陷阱（唯一一处语义不同）：** `TDividerBevel` 的**负值 = 居中**，而这里**负值 = 交给 `Alignment`**。
> 居中请直接写 `Alignment := taCenter` —— 类型名本身就说明了意图，不需要靠一个负数来暗示。

默认值刻意**不是** LCL 的 `60`：那会让现存的每一条分割线在升级后悄悄往里缩一截。默认 `-1` 意味着
不碰这个属性的代码渲染结果一字节不变。

`LeftIndent` 是**逻辑像素**（和 `Width` / `Height` 同一坐标系），绘制时与间隙、线厚一起过 `P.Scale`，
所以在 96 / 192 dpi 下缩进看起来一样。它是**几何默认值**，不是绘制值，因此不走主题令牌 ——
与本单元既有的 `P.Scale(6)` / `P.Scale(4)` / `P.Scale(1)` 同一处理方式（见 5 节末尾）。

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

const
  TyDividerIndentAuto = -1;   // ALeftIndent 的「交给 AAlign」值

function TyDividerLayout(AClientWidth, AClientHeight, ACaptionWidth: Integer;
  AAlign: TAlignment; ALeftIndent: Integer;
  AGap, AMinRule, ARuleThick: Integer): TTyDividerLayout;
```

> **签名变更（`ALeftIndent` 是新加的第 5 个参数）：** 这是个 public 的单元级函数，加参数会打断现有调用方；
> 库内唯一调用方是本控件自己的 `RenderTo`，测试同步更新。传 `TyDividerIndentAuto` 即得到与从前**逐像素相同**
> 的结果（`tests/test.parity.shelldivider.pas` 的 `TestIndentAutoLeavesAlignmentInCharge` 就是钉这一点的）。

`TyDividerLayout` 是本控件的核心：给定内容区宽高、已测量的标题宽度、放置方式（`AAlign` 或 `ALeftIndent`），以及间隙 / 最短细线 / 细线厚度（均为**设备像素**），算出标题矩形与最多两段细线的几何。全部为整数入参、无控件状态、无句柄依赖，因此测试可直接调用验证（`tests/test.divider.pas`、`tests/test.parity.shelldivider.pas`）。要点：

- 细线波段**垂直居中**于内容高度（`(H - ARuleThick) div 2`）。
- 标题与相邻细线之间留 `AGap` 间隙；细线段长度 `< AMinRule` 时**整段丢弃**（避免标题占满宽度时残留 1 像素的小凸起）。
- `ACaptionWidth = 0` → 无标题，返回一条整宽细线（放在 `RightRule`）；此时 `ALeftIndent` 不参与。
- `ACaptionWidth > AClientWidth` → 夹紧到整宽，无细线容身。
- `AClientWidth <= 0` → 全空（三个矩形都为空）。
- `ALeftIndent >= 0` → 走缩进分支：标题前缘置于 `ALeftIndent`，**忽略 `AAlign`**；两侧各算一段细线（各自按 `AMinRule` 判丢弃）。
  缩进大到标题会越过右边缘时**夹紧**（`capLeft` 上限 `AClientWidth - ACaptionWidth`，下限 `0`）——宁可缩进停止增长，也不让标题被推出去。
- `ALeftIndent = 0` 与 `AAlign = taLeftJustify` 的几何**完全一致**（LCL `LeftIndent = 0` 同样不画前置细线）。
- `ALeftIndent < 0` → 完全按 `AAlign` 走，与本参数加入之前一致。

### 绘制流程（`RenderTo`）

`RenderTo(ACanvas, ARect, APPI)` 与库内其它控件一致：创建 `TTyPainter` → `BeginPaint` → 取 `CurrentStyle` → 按 `padding` 内缩内容区 → 用 `P.MeasureText` 测量标题宽度 → 调 `TyDividerLayout` 得几何 → 用 `P.FillBackground`（实心、无圆角）画细线段、用 `P.DrawText` 画标题 → `EndPaint`。`Paint` 只是 `RenderTo(Canvas, ClientRect, Font.PixelsPerInch)`。

**细线颜色（主题令牌驱动，绝不写死）：**

- 若解析样式含 `border-color` 且不透明 → 细线用该 `border-color`；
- 否则从 `color`（文字色）派生一条淡化细线（取文字色、透明度降到 40%）。

两者都直接来自解析后的 `TyDivider` 样式，不在控件代码中硬编码任何颜色值。

> **现状提醒：** 随库发布的主题（`light` / `dark` / `auto` / `green` 及 15 套 builtin）目前**都没有**给 `TyDivider` 定义 `border-color`，因此实际走的是第二条分支——那条 40% 淡化比例是代码里的常数。要拿回细线颜色的控制权，在自己的主题里补一条 `TyDivider { border-color: var(--border); }` 即可。

---

## 5. 状态与主题

### 支持的伪类状态

`TTyDivider` 绘制时只解析 `CurrentStyle`（普通态），**不区分** `:hover`/`:focus`/`:active` 的差异化外观。它是透明叠加控件（像默认的 `TTyLabel`）：**不**绘制主题背景填充，但仍尊重 `opacity` 令牌（如 `:disabled { opacity: 0.5 }`），因此禁用时会整体变淡。

### 解析的主题键

| typeKey | 画什么 |
|---------|--------|
| `TyDivider` | 整个控件：标题文字的 `color` / `font-family` / `font-size` / `font-weight`；细线颜色（首选 `border-color`，无则由 `color` 淡化派生）；`padding`（标题与细线到控件左右边缘的内缩）；`opacity`（`:disabled` 时整体变淡）。 |

**没有子部件键。** 细线与标题共用同一条规则——细线**没有**自己的 typeKey（形如 `TyDividerRule` 的键**不存在**，属于本轮有意推迟的子部件扩展，别往主题里写）。间隙 `P.Scale(6)`、最短细线 `P.Scale(4)`、线厚 `P.Scale(1)` 目前也都是代码字面量，不是令牌；`LeftIndent` 与它们同一处理方式——由使用方给定的**几何**值，过 `P.Scale` 转设备像素，不经主题令牌（它决定的是「放在哪」，不是「画成什么颜色/材质」）。

```css
/* light.tycss 中本控件所在的那条规则（与 TyLabel 等同列） */
TyLabel, TyHtmlLabel, TyLinkLabel, TyShadowLabel, TyGlowLabel, TyDivider, TyCharImage {
  background: alpha(#FFFFFF, 0);
  color: var(--on-surface);        /* 标题文字颜色，也是细线的派生来源 */
  font-size: var(--font-size-base);
  font-weight: var(--font-weight-normal);
}
/* 随库主题都没给这条规则写 border-color / padding；想要就单独补本控件自己的键： */
TyDivider { border-color: var(--border); padding: 0 8px; }
```

要让某些分割线换一种细线颜色，可给它设 `StyleClass`（对应 `.tycss` 里 `TyDivider.myclass { border-color: ...; }`），或用 `StyleOverride: 'border-color: var(--accent);'`。

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
- **文字用主题样式，不读 LCL Font：** 标题按解析后的 `TyDivider` 样式（`color`/`font-size`/`font-weight`/`font-family`）在 `Paint` 中绘制，**不**依赖 LCL 的 `Font.*`（遵循「主题锁定的标签」约定）。要改字号/字色，改主题令牌或用 `StyleClass`/`StyleOverride`。
- **细线颜色来自令牌：** 细线首选 `border-color`，无则由 `color` 淡化派生，**绝不写死颜色**（视觉值必须由主题驱动）。
- **标题占满宽度时细线会消失：** 当标题宽度加间隙后剩余空间不足 `AMinRule`（默认 4 逻辑像素），对应细线段整段丢弃，只显示文字——这是有意为之，避免残留 1 像素小凸起。
- **透明叠加、不画背景：** 控件不填充主题背景，直接叠在宿主表面上；确保它所在的父背景已铺好（如放在 `TTyPanel` 内会显出面板底色）。仍然尊重 `opacity`，禁用时整体变淡。
- **默认尺寸：** 构造时 `Width=150, Height=24`；通常用 `SetBounds` 或 `Align := alTop` 调整为实际所需宽度。高度决定细线垂直居中的位置。
