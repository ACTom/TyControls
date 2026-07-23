# TTyDial

## 1. 概述

TTyDial 是**可交互旋钮**(rotary knob),继承自 `TTyCustomControl`(可获焦、响应鼠标 / 滚轮 / 键盘)。圆形旋钮体上有一根从中心指向轮缘的指针(notch),指向 `Value` 在 `Min..Max` 中的位置。用户可**绕中心拖动**、或用**滚轮 / 方向键**改变 `Value`。旋钮体 / 指针由 BGRABitmap `Canvas2D` 抗锯齿绘制。用于音量 / 增益 / 亮度等"旋钮"式输入。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Dial` |
| `GetStyleTypeKey` 返回值 | `'TyDial'`(旋钮体 / 边框 / 文字)|

### 子部件 typeKey

子部件键在代码里由 `GetStyleTypeKey + 'Pointer'` 拼出,与盒键绑死、不会各自漂移。

| typeKey | 绘制什么 | 读取的样式属性 |
|---------|----------|----------------|
| `TyDial` | 旋钮实心圆体;轮缘描边;`ShowValue` 的中央数值 | `background`(体)/ `border-width`(轮缘线宽)/ `color`(数值文字**及轮缘描边色**) |
| `TyDialPointer` | 从内半径指向轮缘的指针 / 缺口 | `background` |

本控件**不再复用** `TyGauge` / `TyGaugeFill`。旋钮是「实体物件」隐喻(塑料 / 金属体 + 对比色帽),而仪表的 `background` 语义上是一个**下沉的轨道色**,套在一个凸起的旋钮体上本就不对;而且旋钮帽在旧安排下没有自己的颜色可写。

> 主题作者注意:base 层按 typeKey **全有或全无**地回落。只覆盖了 `TyGauge` 的第三方主题**不会**覆盖到 `TyDial` / `TyDialPointer`;需要在皮肤里补上这两条选择器。
> 子部件以**空状态集**解析,`TyDialPointer:hover` 之类的选择器不会生效;伪类只对盒键有效。
> **已知偏差(源码注释亦有记载):** 轮缘描边用的是 `TyDial` 的 `border-width` 但配 `color`(文字色),因此 `TyDial.border-color` 目前**够不着**轮缘。这是本次纯拆键、不动像素的刻意留置,改成读 `border-color` 属于另一次有意的视觉变更。

```pascal
uses tyControls.Dial;
```

---

## 3. 属性表

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Min` / `Max` | `Double` | `0` / `100` | 量程。 |
| `Value` | `Double` | `0` | 当前值;写入(含拖动 / 滚轮 / 键盘)时夹紧,真正变化才触发 `OnChange`。 |
| `StartAngle` | `Integer` | `135` | 指针起始角(度,顺时针,0=正东)。 |
| `SweepAngle` | `Integer` | `270` | 指针扫过角度(即 `Min..Max` 对应的张角)。 |
| `Step` | `Double` | `1` | 滚轮 / 方向键单步增量;`<=0` 时按 `1` 处理。 |
| `ShowValue` | `Boolean` | `False` | 是否在中央显示数值。 |
| `ValueFormat` | `string` | `'%.0f'` | 数值 `Format` 格式串。 |

事件:`OnChange`(`Value` 真正变化时触发,同值写入不触发)。

继承:`Font` / `Align` / `Anchors` / `StyleClass` / `Controller` / `TabStop`(默认 `True`)。

---

## 4. 事件

`OnChange` 之外,暴露 `TTyCustomControl` 基线可获焦事件集(`OnKeyDown` / `OnMouseWheel` / `OnEnter` / `OnExit` 等)。见 [../events.md](../events.md)。

---

## 5. 状态与主题

旋钮体 `TyDial.background`、轮缘线宽 `TyDial.border-width`、文字 `TyDial.color`;指针 `TyDialPointer.background`。**渲染:** 本控件是**窗口化控件**(自有 HWND),因此先用 `TyFillParentBg` 把整个矩形铺成父窗体背景(圆旋钮之外的方角才不会露出 HWND 的白刷),再画实心圆旋钮体 + 细边框,再从内半径向轮缘画一根指针指到 `Value` 对应角度(accent 色);`ShowValue` 时在中央绘制数值。**交互:** 左键按下 / 拖动把光标相对中心的角度映射为 `Value`(**直接吸附,无缓动**,指针紧跟光标);滚轮上 / 下与方向键按 `Step` 步进,`Home`/`End` 到 `Min`/`Max`,`PageUp`/`PageDown` 走 `10*Step`。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.Dial;

TyDefaultController.LoadTheme('themes/light.tycss');

var K: TTyDial;
K := TTyDial.Create(Self);
K.Parent := Self;
K.SetBounds(20, 20, 72, 72);
K.Min := 0;  K.Max := 11;    // 例如增益旋钮
K.Step := 0.5;
K.Value := 5;
K.OnChange := @DialChanged;   // Value 变化回调
```

---

## 7. 注意事项

- **旋钮 vs 指针表 vs 弧:** 需要**输入**用本控件;只读"指针指向刻度"用 [TTyMeter](meter.md);只读"填充弧 / 环"用 [TTyGauge](gauge.md)(`gsArc`/`gsRing`)。
- **直接操作吸附:** 拖动 knob 时 `Value` 直接吸附(不缓动),既紧跟光标又保证无窗口句柄(headless)下渲染像素稳定。
- **死区夹紧:** `StartAngle`/`SweepAngle` 之间的空缺扇区内的点会夹紧到**最近**的端点(Min 或 Max),不会跳到中间值。
- **纯逻辑可测:** 点→值映射 `TyDialValueFromAngle`(本单元)、比例 `TyGaugeFraction`、指针角 `TyGaugeSweepEnd`(见 gauge 单元)均为纯函数并已单元测试(含往返)。
- **主题驱动:** 颜色 / 边框宽度取自 `TyDial` / `TyDialPointer`,不硬编码。改旋钮外观请改这两个键——**不要**去改 `TyGauge`,那会连带改掉仪表 / 时钟 / 评分等一整族控件。
