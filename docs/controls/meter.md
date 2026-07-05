# TTyMeter

## 1. 概述

TTyMeter 是**模拟指针仪表**(表盘 + 刻度 + 指针),继承自 `TTyGraphicControl`。在一段扇形刻度上,一根指针指向 `Value` 在 `Min..Max` 中的位置,中央有轴心、下方可显示数值。指针 / 刻度由 BGRABitmap `Canvas2D` 抗锯齿绘制,指针移动带缓动,跨平台像素一致。用于速度 / 转速 / 音量 / 温度等"表盘"式展示。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Meter` |
| `GetStyleTypeKey` 返回值 | `'TyGauge'`(**复用**:表盘刻度 / 文字取其 `color`)|
| 指针 typeKey | `'TyGaugeFill'`(指针 / 轴心取其 `background` = accent)|

复用 `TTyGauge` 主题规则,无新增 `.tycss`。

```pascal
uses tyControls.Meter;
```

---

## 3. 属性表

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Min` / `Max` | `Double` | `0` / `100` | 量程。 |
| `Value` | `Double` | `0` | 当前值;夹紧后缓动到指针新角度。 |
| `StartAngle` | `Integer` | `150` | 刻度起始角(度,顺时针,0=正东)。 |
| `SweepAngle` | `Integer` | `240` | 刻度扫过角度(改它即得 90° / 120° / 240° 等表盘变体)。 |
| `Ticks` | `Integer` | `5` | 刻度数(均匀分布在起止角之间,含两端)。 |
| `ShowValue` | `Boolean` | `True` | 是否在下方显示数值。 |
| `ValueFormat` | `string` | `'%.0f'` | 数值 `Format` 格式串。 |
| `AnimationsEnabled` | `Boolean` | `True` | 指针缓动;无窗口句柄时吸附。 |

继承:`Font` / `Align` / `Anchors` / `StyleClass` / `Controller`。

---

## 4. 事件

暴露 `TTyGraphicControl` 基线事件集。见 [../events.md](../events.md)。

---

## 5. 状态与主题

复用 `TyGauge`(刻度 / 文字取 `color`)/ `TyGaugeFill`(指针 / 轴心取 `background`)。**渲染:** 沿刻度弧画 `Ticks` 根短径向刻度线,再从中央轴心画一根指针指到 `Value` 对应角度,轴心为实心圆点;`ShowValue` 时在底部居中绘制数值。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.Meter;

TyDefaultController.LoadTheme('themes/light.tycss');

var M: TTyMeter;
M := TTyMeter.Create(Self);
M.Parent := Self;
M.SetBounds(20, 20, 160, 130);
M.Min := 0;  M.Max := 220;   // 例如时速表
M.Ticks := 12;
M.Value := 88;               // 指针缓动到 88
```

---

## 7. 注意事项

- **弧 vs 指针:** 需要"填充弧"式的进度用 [TTyGauge](gauge.md)(`gsArc`);需要"指针指向刻度"式的表盘用本控件。
- **表盘变体:** `StartAngle` / `SweepAngle` 覆盖 90° / 120° / 240° 等不同张角(无需单独控件)。
- **纯逻辑可测:** 比例 `TyGaugeFraction`、指针角 `TyGaugeSweepEnd`(见 gauge 单元)、刻度角 `TyMeterTickAngle`(本单元)均为纯函数并已单元测试。
- **主题驱动:** 颜色取自 `TyGauge` / `TyGaugeFill`,不硬编码。
