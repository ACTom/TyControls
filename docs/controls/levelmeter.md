# TTyLevelMeter

## 1. 概述

TTyLevelMeter 是**电平条 / VU 表**(音频风格),继承自 `TTyGraphicControl`。在一条轨道圆角矩形内,按 `Value` 在 `Min..Max` 中的比例,用强调色点亮一段(可为连续平滑填充,也可为若干等分离散段),并可选绘制**峰值保持**标记(一根细线停在历史最高值处)。轨道 / 点亮段由 `TTyPainter` 抗锯齿绘制,数值变化带缓动,跨平台像素一致。用于音量 / 电平 / 强度等"条形"式实时展示。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.LevelMeter` |
| `GetStyleTypeKey` 返回值 | `'TyGauge'`(**复用**:轨道背景 / 边框 / 文字)|
| 点亮段 typeKey | `'TyGaugeFill'`(点亮部分 / 峰值线取其 `background` = accent)|

复用 `TTyGauge` 主题规则,无新增 `.tycss`。

```pascal
uses tyControls.LevelMeter;
```

---

## 3. 属性表

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Min` / `Max` | `Double` | `0` / `100` | 量程。 |
| `Value` | `Double` | `0` | 当前值;夹紧后缓动到新的填充位置。 |
| `Orientation` | `TTyLevelOrientation` | `loHorizontal` | `loHorizontal` 左→右填充;`loVertical` 下→上填充。 |
| `Segments` | `Integer` | `0` | `0` = 连续平滑填充;`>0` = 该数量的等分离散段,点亮到 `ceil(比例*段数)` 段。 |
| `PeakHold` | `Boolean` | `False` | `True` 时记住历史最高值,并画一根细峰值标记线(仅当更高值到来时上移;或调用 `ResetPeak`)。 |
| `ShowValue` | `Boolean` | `False` | 是否在轨道上居中叠加数值文字。 |
| `ValueFormat` | `string` | `'%.0f'` | 数值 `Format` 格式串。 |
| `AnimationsEnabled` | `Boolean` | `True` | 值缓动;无窗口句柄时吸附。 |

方法:`ResetPeak` — 将峰值标记清回当前值。

继承:`Font` / `Align` / `Anchors` / `StyleClass` / `Controller`。

---

## 4. 事件

暴露 `TTyGraphicControl` 基线事件集。见 [../events.md](../events.md)。

---

## 5. 状态与主题

复用 `TyGauge`(轨道 `background` / 边框 / 文字 `color`)/ `TyGaugeFill`(点亮部分 / 峰值线取 `background`)。**渲染:** 先按 `DrawFrame` 画轨道圆角矩形背景与边框;再在轨道内按 `Value` 比例点亮:`Segments=0` 为单块圆角填充(水平左锚 / 垂直底锚),`Segments>0` 为 N 个带间隙的等分段点亮到 `ceil(比例*段数)`;`PeakHold` 时在历史最高比例处画一根强调色细线;`ShowValue` 时居中叠加数值。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.LevelMeter;

TyDefaultController.LoadTheme('themes/light.tycss');

var L: TTyLevelMeter;
L := TTyLevelMeter.Create(Self);
L.Parent := Self;
L.SetBounds(20, 20, 180, 24);
L.Min := 0;  L.Max := 100;
L.Segments := 20;      // 20 段离散电平
L.PeakHold := True;    // 保持峰值标记
L.Value := 72;         // 缓动点亮到 72%
```

---

## 7. 注意事项

- **连续 vs 分段:** `Segments=0` 为平滑填充;`Segments>0` 为离散段(经典 VU 表观感)。段数变更立即重绘。
- **方向:** `Orientation` 切换水平(左→右)/ 垂直(下→上),无需单独控件。
- **峰值保持:** `PeakHold` 只随更高值上移,不自动衰减;需归零时调用 `ResetPeak`。
- **纯逻辑可测:** 比例 `TyGaugeFraction`(见 gauge 单元)与点亮段数 `TyLevelSegmentsLit`(本单元)均为纯函数并已单元测试。
- **主题驱动:** 颜色取自 `TyGauge` / `TyGaugeFill`,不硬编码。
