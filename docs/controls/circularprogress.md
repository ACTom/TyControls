# TTyCircularProgress

## 1. 概述

TTyCircularProgress 是**环形进度指示器**——`TTyProgressBar` 的环形版,继承自 `TTyGraphicControl`。用一个整环的填充比例表示 `Position` 在 `Min..Max` 区间内的进度,中央可显示百分比文字。环形弧由 BGRABitmap `Canvas2D` 抗锯齿绘制,值变化带缓动动画,跨平台像素一致。适合加载 / 完成度 / 占用率等圆形展示。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.CircularProgress` |
| `GetStyleTypeKey` 返回值 | `'TyGauge'`(**复用**仪表的轨道 / 文字样式)|
| 值填充 typeKey | `'TyGaugeFill'`(复用仪表的填充色)|

本控件**复用 `TTyGauge` 的主题规则**,不引入新的 `.tycss` 规则——因此与仪表的 accent 一致、无额外主题维护。

```pascal
uses tyControls.CircularProgress;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Min` | `Integer` | `0` | 下限。 |
| `Max` | `Integer` | `100` | 上限。 |
| `Position` | `Integer` | `0` | 当前进度;写入夹紧到 `[Min,Max]`,并缓动到新值。 |
| `Thickness` | `Integer` | `10` | 环的笔宽(逻辑像素,经 `Painter.Scale` 缩放)。 |
| `ShowValue` | `Boolean` | `True` | 是否在中央绘制百分比文字。 |
| `ValueFormat` | `string` | `'%.0f%%'` | 百分比文字的 `Format` 格式串(参数为 `0..100` 的百分数)。 |
| `AnimationsEnabled` | `Boolean` | `True` | 有窗口句柄时 `Position` 变化缓动;无句柄时直接吸附(渲染测试稳定)。 |

### 继承的通用成员

`Font` / `Align` / `Anchors` / `StyleClass` / `Controller`(见 `TTyGraphicControl`)。

---

## 4. 事件

暴露 `TTyGraphicControl` 的基线事件集(纯指示控件,无自有命令事件)。见 [../events.md](../events.md)。

---

## 5. 状态与主题

复用 `TyGauge` / `TyGaugeFill` 规则(见 [gauge.md](gauge.md) §5):轨道取 `TyGauge.background`,文字取 `TyGauge.color`,值填充取 `TyGaugeFill.background`。`:disabled` 经 `TyGauge:disabled { opacity }` 生效。

**渲染细节:** 从顶端(12 点钟)顺时针,先画整环 track(`Thickness` 笔宽、圆头端帽),再画 `Position` 比例的 fill 弧;`ShowValue` 时在中央绘制百分比。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.CircularProgress;

TyDefaultController.LoadTheme('themes/light.tycss');

var C: TTyCircularProgress;
C := TTyCircularProgress.Create(Self);
C.Parent := Self;
C.SetBounds(20, 20, 100, 100);
C.Thickness := 12;
C.Position := 0;
C.Position := 68;    // 缓动到 68%
```

---

## 7. 注意事项

- **与 TTyGauge 的关系:** 本控件等价于 `TTyGauge` 的 `gsRing` 样式,但提供进度式的整数 `Position/Min/Max` API(与 `TTyProgressBar` 一致),并复用仪表主题。需要弧形 / 线性 / 可调角度时用 [TTyGauge](gauge.md)。
- **值缓动:** 与 `TTyProgressBar` / `TTyGauge` 同机制;无窗口句柄时吸附,保证像素测试稳定。
- **纯几何可测:** 比例经 `TyGaugeFraction`(见 gauge 单元,已单元测试);`Position` 夹紧由 `test.circularprogress` 覆盖。
- **主题驱动:** 颜色全部取自 `TyGauge` / `TyGaugeFill`,控件不硬编码。
