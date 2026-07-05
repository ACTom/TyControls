# TTyAnalogClock

## 1. 概述

TTyAnalogClock 是**模拟时钟表盘**(12 时刻度 + 时针 / 分针 / 秒针 + 轴心),继承自 `TTyGraphicControl`。表盘四周绘制 12 根时刻度,中央伸出时针(短粗)与分针(长细),外加一根细秒针(accent 强调色)和一个实心轴心。指针 / 刻度由 BGRABitmap `Canvas2D` 抗锯齿绘制,跨平台像素一致。`Running` 为 `True` 且已绘制(有窗口句柄)时每秒自动把 `Time` 推进到 `Now`;无句柄(headless)时静止,渲染测试像素稳定。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.AnalogClock` |
| `GetStyleTypeKey` 返回值 | `'TyGauge'`(**复用**:刻度 / 时针 / 分针取其 `color`)|
| 秒针 / 轴心 typeKey | `'TyGaugeFill'`(秒针 / 轴心取其 `background` = accent)|

复用 `TTyGauge` 主题规则,无新增 `.tycss`。

```pascal
uses tyControls.AnalogClock;
```

---

## 3. 属性表

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Time` | `TDateTime` | 创建时的 `Now` | 显示的时间;`Running` 走时时每秒被推进到 `Now`。 |
| `ShowSeconds` | `Boolean` | `True` | 是否绘制秒针。 |
| `ShowTicks` | `Boolean` | `True` | 是否绘制 12 时刻度。 |
| `Running` | `Boolean` | `True` | 走时;`True` 且有窗口句柄时每秒推进 `Time`,无句柄时静止。 |

继承:`Font` / `Align` / `Anchors` / `StyleClass` / `Controller`。

---

## 4. 事件

暴露 `TTyGraphicControl` 基线事件集。见 [../events.md](../events.md)。

---

## 5. 状态与主题

复用 `TyGauge`(刻度 / 时针 / 分针取 `color`)/ `TyGaugeFill`(秒针 / 轴心取 `background`)。**渲染:** 沿表盘四周画 12 根短径向刻度线;从中央画时针(约 0.5 半径、较粗)与分针(约 0.78 半径、中粗),均用面板文字色;`ShowSeconds` 时再画一根约 0.85 半径的细秒针(强调色);中央为实心轴心(强调色)。0 点朝正上方(以东为基准的 0° 减 90°),顺时针。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.AnalogClock;

TyDefaultController.LoadTheme('themes/light.tycss');

var C: TTyAnalogClock;
C := TTyAnalogClock.Create(Self);
C.Parent := Self;
C.SetBounds(20, 20, 160, 160);
C.Running := True;           // 自动走时
// 或显示一个固定时刻:
// C.Running := False;
// C.Time := EncodeTime(10, 8, 30, 0);
```

---

## 7. 注意事项

- **走时机制:** `Running` 且有窗口句柄时每秒 `TTimer` 把 `Time := Now` 并重绘;无句柄(headless / 未显示的父窗体)时定时器不启动,`Time` 保持不变,故渲染测试像素稳定。定时器在首次 `Paint` 时惰性创建、`Destroy` 中释放。
- **静态显示:** 设 `Running := False` 后自行设置 `Time` 即可显示任意固定时刻。
- **纯逻辑可测:** 时针角 `TyClockHourAngle(h,m)`、分针角 `TyClockMinuteAngle(m,s)`、秒针角 `TyClockSecondAngle(s)` 均为纯函数(度,0=正上方,顺时针)并已单元测试(如 3:00 → 时针 90°)。
- **主题驱动:** 颜色取自 `TyGauge` / `TyGaugeFill`,不硬编码。
