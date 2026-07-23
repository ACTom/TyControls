# TTyGearDial

## 1. 概述

TTyGearDial 是**带齿轮齿的旋钮**(交互式),继承自 `TTyCustomControl`。旋钮本体是一个实心圆盘,沿圆周均匀分布若干"齿"(短径向梯形),中央有轴心,一根强调色指针从中心指向 `Value` 在 `Min..Max` 中对应的角度。可拖动旋钮、滚轮或方向键改变 `Value`,变化时触发 `OnChange`。齿 / 指针由 BGRABitmap `Canvas2D` 抗锯齿绘制。交互直接吸附(无缓动),跨平台像素一致。用于音量 / 增益 / 参数微调等"物理旋钮"式输入。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.GearDial` |
| `GetStyleTypeKey` 返回值 | `'TyGearDial'`(本体 / 边框 / 内圈 / 文字)|

### 子部件 typeKey

两个子部件键在代码里由 `GetStyleTypeKey + 'Teeth'` / `+ 'Pointer'` 拼出,与盒键绑死、不会各自漂移。

| typeKey | 绘制什么 | 读取的样式属性 |
|---------|----------|----------------|
| `TyGearDial` | 实心圆盘本体;轮缘描边;机械感内圈;`ShowValue` 的中央数值 | `background`(本体)/ `border-width`(轮缘线宽)/ `color`(数值文字、轮缘与内圈描边色) |
| `TyGearDialTeeth` | 轮缘上的齿(短径向梯形) | `background` |
| `TyGearDialPointer` | 指针 / 缺口 + 中央轴心 | `background` |

本控件**不再复用** `TyGauge` / `TyGaugeFill`。关键差别在**齿**:旧安排下齿取的是本体自己的 `background`,也就是齿根本**无法被单独上色**——而这恰恰是工业风皮肤对一个机械感旋钮唯一想做的事。现在齿是一条独立选择器。

> 主题作者注意:base 层按 typeKey **全有或全无**地回落。只覆盖了 `TyGauge` 的第三方主题**不会**覆盖到这三个键;需要在皮肤里补上。
> 子部件以**空状态集**解析,`TyGearDialTeeth:hover` 之类的选择器不会生效;伪类只对盒键有效。
> **已知偏差(源码注释亦有记载):** 轮缘与内圈的描边用的是 `TyGearDial` 的 `border-width` 但配 `color`(文字色),因此 `TyGearDial.border-color` 目前**够不着**它们。这是本次纯拆键、不动像素的刻意留置。

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

本体 `TyGearDial.background`、轮缘线宽 `TyGearDial.border-width`、内圈 / 文字 `TyGearDial.color`;齿 `TyGearDialTeeth.background`;指针 / 轴心 `TyGearDialPointer.background`。**渲染:** 本控件是**窗口化控件**(自有 HWND),先用 `TyFillParentBg` 把整个矩形铺成父窗体背景(齿轮之外的方角才不会露出 HWND 的白刷);再沿圆周画 `Teeth` 个短径向梯形齿(**齿色**,已与本体色解耦),叠一个实心圆盘本体、描一圈轮缘、画一圈内圈,然后从内半径向外画一根指针色的指针指到 `Value` 角度,中央为同色实心轴心;`ShowValue` 时在中央绘制数值。

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
- **与 TTyDial 的区别:** 交互模型完全相同(复用 `TyDialValueFromAngle` 角度换算),仅本体外观多了齿轮齿与内圈;主题上两者是各自独立的键族(`TyDial*` vs `TyGearDial*`)。见 [dial.md](dial.md)。
- **纯逻辑可测:** 齿角 `TyGearToothAngle`(本单元)、比例 `TyGaugeFraction`、指针角 `TyGaugeSweepEnd`、角度取值 `TyDialValueFromAngle`(见 gauge / dial 单元)均为纯函数并已单元测试。
- **仅真变化触发:** `OnChange` 只在值真正改变时触发(单一 `ApplyValue` 出口),重复赋同值不触发。
- **主题驱动:** 颜色取自 `TyGearDial` / `TyGearDialTeeth` / `TyGearDialPointer`,不硬编码。改本控件外观请改这三个键——**不要**去改 `TyGauge`,那会连带改掉仪表 / 时钟 / 评分等一整族控件。
