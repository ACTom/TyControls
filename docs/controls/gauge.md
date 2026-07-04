# TTyGauge

## 1. 概述

TTyGauge 是 TyControls 的**数值仪表控件**,继承自 `TTyGraphicControl`(叶子图形控件,无焦点/子控件)。用一条 track(轨道)+ 一段 value fill(值填充)表示 `Value` 在 `Min..Max` 区间内的比例。支持四种样式:线性横条、线性竖条、开口弧形(speedometer)、整环。弧线由 BGRABitmap 的 `Canvas2D` 抗锯齿绘制,在 Windows/Linux/macOS 上像素一致。典型用途:仪表盘、进度环、CPU/温度/音量等指示。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Gauge` |
| `GetStyleTypeKey` 返回值 | `'TyGauge'`(轨道 / 文字)|
| 值填充 typeKey | `'TyGaugeFill'`(单独解析,承载填充色,可渐变)|

轨道与文字来自 `TyGauge` 规则,值填充来自 `TyGaugeFill` 规则——与 `TyProgressBar` / `TyProgressFill` 同一套路,主题可分别定制。

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
| `Caption` | `string` | 见 `TTyGraphicControl`(本控件当前不绘制 Caption,预留)。 |
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
| `:disabled` | `Enabled = False`(整体 `opacity` 降低)。 |

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

**渲染细节:** 线性样式经 `DrawFrame` 画轨道背景+边框,再在内缩后的轨道上按比例填充(左锚 / 底锚),四角圆角来自 `TyGaugeFill.border-radius`。弧/环样式用 `Painter.Bitmap.Canvas2D` 以 `Thickness` 笔宽、圆头端帽先画整段 track 弧(`TyGauge.background.color`),再画 `Value` 比例的 fill 弧(`TyGaugeFill.background.color`);`ShowValue` 时在中央绘制数值。**弧形填充为纯色**——若主题给 `TyGaugeFill` 指定了渐变,弧形取其基色,线性样式则完整呈现渐变。green 主题给轨道用半透明色(它无 `--surface-sunk` 且是照片背景)。

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

- **值缓动:** `Value` 变化时按 ~240ms 缓出动画过渡;无窗口句柄(headless 渲染 / 测试)时直接吸附,保证像素测试稳定(与 `TTyProgressBar` 同机制)。
- **弧形角度:** 角度为度、顺时针、0=正东。默认 `StartAngle=135` + `SweepAngle=270` 得到底部开口的速度表样式;`gsRing` 固定从顶端起整圈,忽略 `StartAngle/SweepAngle`。
- **厚度 HiDPI:** `Thickness` 是逻辑像素,绘制时经 `Painter.Scale` 缩放。
- **纯几何可测:** `TyGaugeFraction` / `TyGaugeSweepEnd` / `TyGaugeLinearFill` 为纯函数,已单元测试;比例在 `Max<=Min` 时安全返回 0。
- **主题驱动:** 轨道 / 填充 / 文字全部取自 `TyGauge` / `TyGaugeFill` 主题规则,控件不硬编码任何颜色。
