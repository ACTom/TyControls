# TTyGauge

## 1. 概述

TTyGauge 是 TyControls 的**数值仪表控件**,继承自 `TTyGraphicControl`(叶子图形控件,无焦点/子控件)。用一条 track(轨道)+ 一段 value fill(值填充)表示 `Value` 在 `Min..Max` 区间内的比例。支持四种样式:线性横条、线性竖条、开口弧形(speedometer)、整环。弧线由 BGRABitmap 的 `Canvas2D` 抗锯齿绘制,在 Windows/Linux/macOS 上像素一致。典型用途:仪表盘、进度环、CPU/温度/音量等指示。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Gauge` |
| `GetStyleTypeKey` 返回值 | `'TyGauge'`(轨道 / 文字)|

### 子部件 typeKey

| typeKey | 绘制什么 | 读取的样式属性 |
|---------|----------|----------------|
| `TyGauge` | 线性样式的轨道背景 + 边框(`DrawFrame`);弧 / 环样式的整段 track;中央数值文字 | `background` / `border-color` / `border-width` / `border-radius` / `color`(文字) |
| `TyGaugeFill` | 按比例的值填充(线性填充块 / 值弧) | `background`(可为渐变)/ `border-radius` |

与其它子部件键不同,`TyGaugeFill` 是**写死的字面量**而不是由 `GetStyleTypeKey + 'Fill'` 拼出的——TTyGauge 是这两个键的**定义者**。

**TTyGauge 保留 `TyGauge` / `TyGaugeFill`,不是「复用」。** 3.0 之前有十三个互不相干的控件(指针表、电平表、旋钮、齿轮旋钮、时钟、进度环、两种 spinner、齿轮 spinner、sparkline、评分、两个取色器)也硬返回 `'TyGauge'`、并且全都解析同一个 `'TyGaugeFill'`,结果是**一个星级评分、一根时钟秒针和一个进度环在构造上就必须同色**。它们现在各自拥有自己的盒键与子部件键,详见各自文档;`TyGauge` / `TyGaugeFill` 从此只属于本控件。

> 主题作者注意:base 层按 typeKey **全有或全无**地回落。旧皮肤里只写了 `TyGauge` / `TyGaugeFill` 的那一段,现在**只影响 TTyGauge**;那十三个控件的键需要在皮肤里各自补上,否则它们回落到内置 light 值(在图片主题上会显示成一块不透明的灰底)。完整键名清单见本次发版的 CHANGELOG。
> `TyGaugeFill` 以**空状态集**解析,`TyGaugeFill:disabled` 之类的选择器不会生效;伪类只对盒键 `TyGauge` 有效。

```pascal
uses tyControls.Gauge;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Min` | `Double` | `0` | 量程下限。 |
| `Max` | `Double` | `100` | 量程上限;`Max<=Min` 时比例恒为 0(不会除零)。 |
| `Value` | `Double` | `0` | 当前值;写入时夹紧到 `[Min,Max]`,并**缓动**到新值(见 `AnimationsEnabled`)。 |
| `Style` | `TTyGaugeStyle` | `gsArc` | `gsLinearH`(横条)/ `gsLinearV`(竖条)/ `gsArc`(开口弧)/ `gsRing`(整环)。 |
| `ShowValue` | `Boolean` | `True` | 是否在中央绘制格式化后的数值文字。 |
| `ValueFormat` | `string` | `'%.0f'` | 数值文字的 `Format` 格式串(参数为 `Value`)。 |
| `Thickness` | `Integer` | `12` | 弧/环笔宽 与 线性轨道厚度的逻辑像素数(经 `Painter.Scale` 做 HiDPI 缩放)。 |
| `StartAngle` | `Integer` | `135` | 弧形起始角(度,顺时针,0=正东);`gsRing` 忽略(固定从顶端起整圈)。 |
| `SweepAngle` | `Integer` | `270` | 弧形扫过角度;`gsRing` 忽略(固定 360)。 |
| `AnimationsEnabled` | `Boolean` | `True` | 有窗口句柄时,`Value` 变化会缓动;无句柄(每个渲染测试)时直接吸附到终值。 |

### 继承的通用成员

| 属性 | 类型 | 说明 |
|------|------|------|
| `Font` | `TFont` | 传递 PPI;数值文字大小由控件尺寸推导。 |
| `StyleClass` | `string` | `.tycss` 类名(同时作用于 `TyGauge` 与 `TyGaugeFill` 的解析)。 |
| `Controller` | `TTyStyleController` | 指定样式控制器(nil 时用全局默认)。 |
| `Align` / `Anchors` | — | 布局。 |

**枚举:** `TTyGaugeStyle = (gsLinearH, gsLinearV, gsArc, gsRing)`。

---

## 4. 事件

TTyGauge 暴露 `TTyGraphicControl` 的**基线事件集**(Tier A 鼠标 / 通用事件)。本控件自身不新增命令事件(纯指示控件)。完整清单见 [../events.md](../events.md)。

---

## 5. 状态与主题

### 支持的伪类状态

| 伪类 | 触发条件 |
|------|----------|
| `:disabled` | `Enabled = False`(整体 `opacity` 降低;**仅线性样式**,见下方渲染细节)。 |

（无 hover/focus/active——纯展示控件。）

### light.tycss 内置规则摘要

```css
TyGauge {
  background: var(--surface-sunk);   /* 轨道色 */
  color: var(--on-surface);          /* 数值文字色 */
  border-color: var(--border);
  border-width: var(--input-border-width);   /* 线性轨道边框 */
  border-radius: var(--radius);
}
TyGauge:disabled { opacity: var(--disabled-opacity); }

TyGaugeFill {
  background: var(--accent);         /* 值填充色(可为 linear-gradient) */
  border-radius: var(--radius);
}
```

**渲染细节:** 线性样式经 `DrawFrame` 画轨道背景+边框,再在内缩后的轨道上按比例填充(左锚 / 底锚),四角圆角来自 `TyGaugeFill.border-radius`。弧/环样式用 `Painter.Bitmap.Canvas2D` 以 `Thickness` 笔宽、圆头端帽先画整段 track 弧(`TyGauge.background.color`),再画 `Value` 比例的 fill 弧(`TyGaugeFill.background.color`);`ShowValue` 时在中央绘制数值。注意 `opacity` 是在 `DrawFrame` 里落地的,因此上表的 `:disabled` 只在**线性样式**上生效,`gsArc` / `gsRing` 不走 `DrawFrame`。**弧形填充为纯色**——若主题给 `TyGaugeFill` 指定了渐变,弧形取其基色,线性样式则完整呈现渐变。green 主题给轨道用半透明色(它无 `--surface-sunk` 且是照片背景)。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.Gauge;

TyDefaultController.LoadTheme('themes/light.tycss');

var G: TTyGauge;
G := TTyGauge.Create(Self);
G.Parent := Self;
G.SetBounds(20, 20, 140, 140);
G.Style := gsArc;
G.Min := 0;  G.Max := 100;
G.ValueFormat := '%.0f%%';
G.Value := 72;          // 缓动到 72%

// 环形进度
var R: TTyGauge;
R := TTyGauge.Create(Self);
R.Parent := Self;
R.SetBounds(180, 20, 120, 120);
R.Style := gsRing;
R.Thickness := 10;
R.Value := 45;
```

---

## 7. 注意事项

- **仪表没有标题:** `Caption` 不再 published——它从前挂在对象检查器上,而 `Paint` 一个字都不读,等于给了一个拧了没反应的旋钮。控件同时去掉了 `csSetCaption`,因此仪表不会再把自己的 `Name` 当作看不见的标题文字白白写进 `.lfm`。要给仪表配文字说明,在旁边放一个 [[TTyLabel]]。
- **值缓动:** `Value` 变化时按 ~240ms 缓出动画过渡;无窗口句柄(headless 渲染 / 测试)时直接吸附,保证像素测试稳定(与 `TTyProgressBar` 同机制)。
- **弧形角度:** 角度为度、顺时针、0=正东。默认 `StartAngle=135` + `SweepAngle=270` 得到底部开口的速度表样式;`gsRing` 固定从顶端起整圈,忽略 `StartAngle/SweepAngle`。
- **厚度 HiDPI:** `Thickness` 是逻辑像素,绘制时经 `Painter.Scale` 缩放。
- **纯几何可测:** `TyGaugeFraction` / `TyGaugeSweepEnd` / `TyGaugeLinearFill` 为纯函数,已单元测试;比例在 `Max<=Min` 时安全返回 0。
- **主题驱动:** 轨道 / 填充 / 文字全部取自 `TyGauge` / `TyGaugeFill` 主题规则,控件不硬编码任何颜色。
- **改 `TyGauge` 只会改到本控件:** 3.0 起 `TyGauge` / `TyGaugeFill` 不再被别的控件借用。想改指针表、电平表、时钟、评分、sparkline、取色器等的外观,请改它们**各自**的键(`TyMeter*` / `TyLevelMeter*` / `TyAnalogClock*` / `TyRating*` / `TySparkline*` / `TyHSColorPicker` / `TyLColorPicker` …)。
