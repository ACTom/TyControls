# TTyCircularProgress

## 1. 概述

TTyCircularProgress 是**环形进度指示器**——`TTyProgressBar` 的环形版,继承自 `TTyGraphicControl`。用一个整环的填充比例表示 `Position` 在 `Min..Max` 区间内的进度,中央可显示百分比文字。环形弧由 BGRABitmap `Canvas2D` 抗锯齿绘制,值变化带缓动动画,跨平台像素一致。适合加载 / 完成度 / 占用率等圆形展示。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.CircularProgress` |
| `GetStyleTypeKey` 返回值 | `'TyCircularProgress'`(轨道 / 文字)|

### 子部件 typeKey

子部件键在代码里由 `GetStyleTypeKey + 'Fill'` 拼出,与盒键绑死、不会各自漂移。

| typeKey | 绘制什么 | 读取的样式属性 |
|---------|----------|----------------|
| `TyCircularProgress` | 整环 track;中央百分比文字 | `background`(track)/ `color`(文字) |
| `TyCircularProgressFill` | 按比例扫过的值环 | `background` |

本控件**不再复用** `TyGauge` / `TyGaugeFill`。理由与 `TTyProgressBar` 拥有 `TyProgressBar` / `TyProgressFill` 而不借仪表键是同一条:多个皮肤会把线性进度条单独做成胶囊形或另配色,环形版必须能跟着走。

> 主题作者注意:base 层按 typeKey **全有或全无**地回落。只覆盖了 `TyGauge` 的第三方主题**不会**覆盖到 `TyCircularProgress` / `TyCircularProgressFill`;需要在皮肤里补上这两条选择器。
> 子部件以**空状态集**解析,`TyCircularProgressFill:disabled` 之类的选择器不会生效;伪类只对盒键有效。
> 本控件不画外框(不走 `DrawFrame`),因此盒键的 `border-*` 目前**不参与绘制**——它只提供 track 环的 `background` 与读数的 `color`。

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

轨道取 `TyCircularProgress.background`,文字取 `TyCircularProgress.color`,值环取 `TyCircularProgressFill.background`。light.tycss 里这两个键与仪表族共用同一条规则块(解析值今天与 `TyGauge` 逐字相同),但它们是**独立的选择器**——皮肤单独覆写 `TyCircularProgressFill` 不会动到别的仪表。light.tycss 里有 `TyCircularProgress:disabled { opacity }` 一条,但 `opacity` 是在 `DrawFrame` 里落地的,而本控件不走 `DrawFrame`——因此该规则目前**不产生视觉效果**(与 `TTyGauge` 的 `gsArc` / `gsRing` 同因)。

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

- **与 TTyGauge 的关系:** 本控件在几何上等价于 `TTyGauge` 的 `gsRing` 样式,但提供进度式的整数 `Position/Min/Max` API(与 `TTyProgressBar` 一致),**主题上则是独立的一对键**。需要弧形 / 线性 / 可调角度时用 [TTyGauge](gauge.md)。
- **值缓动:** 与 `TTyProgressBar` / `TTyGauge` 同机制;无窗口句柄时吸附,保证像素测试稳定。
- **纯几何可测:** 比例经 `TyGaugeFraction`(见 gauge 单元,已单元测试);`Position` 夹紧由 `test.circularprogress` 覆盖。
- **主题驱动:** 颜色全部取自 `TyCircularProgress` / `TyCircularProgressFill`,控件不硬编码。改本控件外观请改这两个键——**不要**去改 `TyGauge`,那会连带改掉仪表 / 时钟 / 评分等一整族控件。
