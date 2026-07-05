# TTySparkline

## 1. 概述

TTySparkline 是**内联迷你趋势图**(无坐标轴、无图例、无标签),继承自 `TTyGraphicControl`。它只表现一段数据序列的"形状":通过 `SetValues` 喂入一组采样,每个值映射到内边距客户区中的一个点(X 均匀分布,Y 由纯函数 `TySparklineY` 反转映射:最小值→底、最大值→顶),再以 accent 折线(`ssLine`)或从基线起的 accent 柱(`ssBar`)绘出,末点可加一个实心圆点。由 BGRABitmap `Canvas2D` 抗锯齿绘制,跨平台像素一致。适合放在表格单元格、卡片、状态栏里做"一眼看趋势"。数据驱动,无动画。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Sparkline` |
| `GetStyleTypeKey` 返回值 | `'TyGauge'`(**复用**:边框 / 基线 / 文字取其 `color`)|
| 折线 / 柱 / 圆点 typeKey | `'TyGaugeFill'`(取其 `background` = accent)|

复用 `TTyGauge` 主题规则,无新增 `.tycss`。

```pascal
uses tyControls.Sparkline;
```

---

## 3. 属性表

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Style` | `TTySparkStyle` | `ssLine` | `ssLine`=折线;`ssBar`=柱状(自基线起)。 |
| `ShowLast` | `Boolean` | `True` | 末点是否画一个实心 accent 圆点。 |
| `AutoRange` | `Boolean` | `True` | `True` 时量程取数据的 min/max;`False` 时用 `MinValue`/`MaxValue`。 |
| `MinValue` / `MaxValue` | `Double` | `0` / `100` | 手动量程(仅 `AutoRange=False` 时生效)。 |
| `Count` | `Integer` | (只读) | 当前序列长度。 |

继承:`Font` / `Align` / `Anchors` / `StyleClass` / `Controller`。

**方法:** `procedure SetValues(const AValues: array of Double)` —— 把 `AValues` **复制**进内部序列并重绘(不引用调用方数组)。

---

## 4. 事件

暴露 `TTyGraphicControl` 基线事件集。见 [../events.md](../events.md)。

---

## 5. 状态与主题

复用 `TyGauge`(边框 / 基线 / 文字取 `color`)/ `TyGaugeFill`(折线 / 柱 / 圆点取 `background`)。**渲染:** 先 `DrawFrame` 画主题背景 + 边框,内缩一圈内边距为绘图带;在零(或量程下限)处画一条 `color` 淡基线;然后按 `Style` 画 accent 折线或柱;`ShowLast` 时在末点画 accent 实心圆点。空序列或 1 个采样都不会崩溃(1 点折线画一条水平标记线,末点圆点靠右)。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.Sparkline;

TyDefaultController.LoadTheme('themes/light.tycss');

var S: TTySparkline;
S := TTySparkline.Create(Self);
S.Parent := Self;
S.SetBounds(20, 20, 120, 36);
S.Style := ssLine;
S.SetValues([3, 5, 4, 8, 6, 9, 7, 11, 10, 13]);   // 数据自动定量程
// 固定量程(便于多条 Sparkline 纵向对比):
// S.AutoRange := False; S.MinValue := 0; S.MaxValue := 20;
```

---

## 7. 注意事项

- **折线 vs 柱:** 连续趋势用 `ssLine`;离散计数 / 直方感用 `ssBar`(柱从基线起)。
- **固定 vs 自动量程:** 多条 Sparkline 要能纵向对比时关掉 `AutoRange` 并统一 `MinValue`/`MaxValue`;否则各自 auto-range 会让相同高度代表不同数值。
- **纯逻辑可测:** 值→纵坐标映射 `TySparklineY`(反转、越界夹紧、空量程居中防除零)为纯函数并已单元测试。
- **空 / 单点安全:** 空序列不绘制数据层;单个采样画一条水平标记线,不会除零或崩溃。
- **主题驱动:** 颜色取自 `TyGauge` / `TyGaugeFill`,不硬编码。
- **无动画:** 与 [TTyGauge](gauge.md) / [TTyMeter](meter.md) 不同,Sparkline 是数据驱动的即时重绘,`SetValues` 立即生效。
