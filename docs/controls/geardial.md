# TTyGearDial

## 1. 概述

TTyGearDial 是**带齿轮齿的旋钮**(交互式),继承自 `TTyCustomControl`。旋钮本体是一个实心圆盘,沿圆周均匀分布若干"齿"(短径向梯形),中央有轴心,一根强调色指针从中心指向 `Value` 在 `Min..Max` 中对应的角度。可拖动旋钮、滚轮或方向键改变 `Value`,变化时触发 `OnChange`。齿 / 指针由 BGRABitmap `Canvas2D` 抗锯齿绘制。交互直接吸附(无缓动),跨平台像素一致。用于音量 / 增益 / 参数微调等"物理旋钮"式输入。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.GearDial` |
| `GetStyleTypeKey` 返回值 | `'TyGauge'`(**复用**:本体 / 齿 / 边框取 `background` / `border`,内圈 / 文字取 `color`)|
| 指针 typeKey | `'TyGaugeFill'`(指针 / 轴心取其 `background` = accent)|

复用 `TTyGauge` 主题规则,无新增 `.tycss`。

```pascal
uses tyControls.GearDial;
```

---

## 3. 属性表

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Min` / `Max` | `Double` | `0` / `100` | 量程。 |
| `Value` | `Double` | `0` | 当前值;写入即夹紧,真正变化时触发 `OnChange`。 |
| `StartAngle` | `Integer` | `135` | 指针起始角(度,顺时针,0=正东)。 |
| `SweepAngle` | `Integer` | `270` | 指针扫过角度(≥1)。 |
| `Teeth` | `Integer` | `12` | 齿轮齿数(均匀分布整圈)。 |
| `Step` | `Double` | `1` | 方向键 / 滚轮步长(≤0 时按 1)。 |
| `ShowValue` | `Boolean` | `False` | 是否在中央显示数值。 |
| `ValueFormat` | `string` | `'%.0f'` | 数值 `Format` 格式串。 |

继承:`Font` / `Align` / `Anchors` / `StyleClass` / `Controller` / `TabStop`(默认 `True`)。

---

## 4. 事件

| 事件 | 说明 |
|------|------|
| `OnChange` | `Value` 真正变化时触发(拖动 / 滚轮 / 按键 / 程序赋值同一 `ApplyValue` 出口,值未变不触发)。 |

另暴露 `TTyCustomControl` 基线事件集。见 [../events.md](../events.md)。

---

## 5. 状态与主题

复用 `TyGauge`(本体 / 齿 `background`、边框 `border`、内圈 / 文字 `color`)/ `TyGaugeFill`(指针 / 轴心 `background`)。**渲染:** 先沿圆周画 `Teeth` 个短径向梯形齿(本体色),再叠一个实心圆盘本体、描一圈边框、画一圈内圈,然后从内半径向外画一根强调色指针指到 `Value` 角度,中央为强调色实心轴心;`ShowValue` 时在中央绘制数值。

**交互:** 在旋钮上拖动(绕中心取角)、滚轮(上增下减)、方向键(← ↓ 减、→ ↑ 增、PageUp/Down ×10、Home/End 到量程端点)均经单一 `ApplyValue` 出口:夹紧到 `Min..Max`,仅在值真正改变时 `Invalidate` 并触发 `OnChange`。直接操作吸附(无动画),无窗口句柄时渲染稳定。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.GearDial;

TyDefaultController.LoadTheme('themes/light.tycss');

var K: TTyGearDial;
K := TTyGearDial.Create(Self);
K.Parent := Self;
K.SetBounds(20, 20, 90, 90);
K.Min := 0;  K.Max := 11;     // 例如 0..11 增益档
K.Teeth := 16;
K.Value := 7;
K.OnChange := @GearChanged;   // 拖动 / 滚轮 / 按键改变时回调
```

---

## 7. 注意事项

- **旋钮 vs 表盘:** 需要用户**输入**的旋钮用本控件(交互);只读的"指针指向刻度"表盘用 [TTyMeter](meter.md);"填充弧"进度用 [TTyGauge](gauge.md)。
- **与 TTyDial 的区别:** 交互模型完全相同(复用 `TyDialValueFromAngle` 角度换算),仅本体外观多了齿轮齿与内圈。见 [dial.md](dial.md)。
- **纯逻辑可测:** 齿角 `TyGearToothAngle`(本单元)、比例 `TyGaugeFraction`、指针角 `TyGaugeSweepEnd`、角度取值 `TyDialValueFromAngle`(见 gauge / dial 单元)均为纯函数并已单元测试。
- **仅真变化触发:** `OnChange` 只在值真正改变时触发(单一 `ApplyValue` 出口),重复赋同值不触发。
- **主题驱动:** 颜色取自 `TyGauge` / `TyGaugeFill`,不硬编码。
