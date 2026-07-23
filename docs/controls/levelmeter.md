# TTyLevelMeter

## 1. 概述

TTyLevelMeter 是**电平条 / VU 表**(音频风格),继承自 `TTyGraphicControl`。在一条轨道圆角矩形内,按 `Value` 在 `Min..Max` 中的比例,用强调色点亮一段(可为连续平滑填充,也可为若干等分离散段),并可选绘制**峰值保持**标记(一根细线停在历史最高值处)。轨道 / 点亮段由 `TTyPainter` 抗锯齿绘制,数值变化带缓动,跨平台像素一致。用于音量 / 电平 / 强度等"条形"式实时展示。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.LevelMeter` |
| `GetStyleTypeKey` 返回值 | `'TyLevelMeter'`(轨道背景 / 边框 / 文字)|

### 子部件 typeKey

两个子部件键在代码里由 `GetStyleTypeKey + 'Fill'` / `+ 'Peak'` 拼出,与盒键绑死、不会各自漂移。

| typeKey | 绘制什么 | 读取的样式属性 |
|---------|----------|----------------|
| `TyLevelMeter` | 轨道:圆角背景 + 边框(`DrawFrame`);`ShowValue` 的叠加数值 | `background` / `border-color` / `border-width` / `border-radius` / `color`(文字) |
| `TyLevelMeterFill` | 点亮的一段(连续填充或离散段) | `background` |
| `TyLevelMeterPeak` | 峰值保持标记线 | `background` |

本控件**不再复用** `TyGauge` / `TyGaugeFill`。VU 表是皮肤最典型要从「通用仪表」里拆出来单独做的控件;更要命的是**峰值标记**:它是画**在**点亮条上的,跟填充共用一个颜色就等于在信号真正到顶的那一刻它变得看不见,而且没有任何主题规则能补救。现在它有自己的键。

> 主题作者注意:base 层按 typeKey **全有或全无**地回落。只覆盖了 `TyGauge` 的第三方主题**不会**覆盖到这三个键;需要在皮肤里补上。
> 子部件以**空状态集**解析,`TyLevelMeterFill:disabled` 之类的选择器不会生效;伪类只对盒键 `TyLevelMeter` 有效。

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

轨道 `TyLevelMeter.background` / 边框 / 文字 `color`;点亮段 `TyLevelMeterFill.background`;峰值线 `TyLevelMeterPeak.background`。**渲染:** 先按 `DrawFrame` 画轨道圆角矩形背景与边框;再在轨道内按 `Value` 比例点亮:`Segments=0` 为单块圆角填充(水平左锚 / 垂直底锚),`Segments>0` 为 N 个带间隙的等分段点亮到 `ceil(比例*段数)`;`PeakHold` 时在历史最高比例处画一根**峰值色**细线(与点亮段各自取色);`ShowValue` 时居中叠加数值。

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
- **峰值保持:** `PeakHold` 只随更高值上移,不自动衰减;需归零时调用 `ResetPeak`。峰值线走 `TyLevelMeterPeak`,与点亮段的 `TyLevelMeterFill` 分开配色才看得见(内置 light 主题里两者取值相同,皮肤应当把峰值线改成对比色)。
- **纯逻辑可测:** 比例 `TyGaugeFraction`(见 gauge 单元)与点亮段数 `TyLevelSegmentsLit`(本单元)均为纯函数并已单元测试。
- **主题驱动:** 颜色取自 `TyLevelMeter` / `TyLevelMeterFill` / `TyLevelMeterPeak`,不硬编码。改本控件外观请改这三个键——**不要**去改 `TyGauge`,那会连带改掉仪表 / 时钟 / 评分等一整族控件。
