# TTyAnalogClock

## 1. 概述

TTyAnalogClock 是**模拟时钟表盘**(12 时刻度 + 时针 / 分针 / 秒针 + 轴心),继承自 `TTyGraphicControl`。表盘四周绘制 12 根时刻度,中央伸出时针(短粗)与分针(长细),外加一根细秒针(accent 强调色)和一个实心轴心。指针 / 刻度由 BGRABitmap `Canvas2D` 抗锯齿绘制,跨平台像素一致。`Running` 为 `True` 且已绘制(有窗口句柄)时每秒自动把 `Time` 推进到 `Now`;无句柄(headless)时静止,渲染测试像素稳定。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.AnalogClock` |
| `GetStyleTypeKey` 返回值 | `'TyAnalogClock'`(表盘 + 时刻度)|

### 子部件 typeKey

两个子部件键在代码里由 `GetStyleTypeKey + 'Hand'` / `+ 'SecondHand'` 拼出,与盒键绑死、不会各自漂移。

| typeKey | 绘制什么 | 读取的样式属性 |
|---------|----------|----------------|
| `TyAnalogClock` | 12 根时刻度 | `color`(即 `TextColor`) |
| `TyAnalogClockHand` | 时针 + 分针 | `color` |
| `TyAnalogClockSecondHand` | 秒针 + 中央轴心 | `background` |

本控件**不再复用** `TyGauge` / `TyGaugeFill`。表盘是最典型的可换肤对象(Win7 小工具、暗色座舱、扁平瑞士钟),原先它被钉在一个进度环的 token 上:**刻度与指针共用同一个颜色**,所以经典的「淡刻度 + 黑指针」这一档根本写不出来。现在刻度、时针 / 分针、秒针 / 轴心是三条各自可写的选择器。

> 主题作者注意:base 层按 typeKey **全有或全无**地回落。只覆盖了 `TyGauge` / `TyGaugeFill` 的第三方主题**不会**覆盖到这三个键;需要在皮肤里补上。
> 子部件以**空状态集**解析,`TyAnalogClockHand:disabled` 之类的选择器不会生效;伪类只对盒键 `TyAnalogClock` 有效。
> 本控件不画表盘底板(不走 `DrawFrame`),因此 `TyAnalogClock` 的 `background` / `border-*` 目前**不参与绘制**——盒键在这里只提供刻度的 `color`。

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

刻度取 `TyAnalogClock.color`,时针 / 分针取 `TyAnalogClockHand.color`,秒针 / 轴心取 `TyAnalogClockSecondHand.background`。**渲染:** 沿表盘四周画 12 根短径向刻度线(表盘文字色);从中央画时针(约 0.5 半径、较粗)与分针(约 0.78 半径、中粗),两者同用**指针色**、已与刻度色解耦;`ShowSeconds` 时再画一根约 0.85 半径的细秒针(秒针色);中央为实心轴心(同秒针色)。0 点朝正上方(以东为基准的 0° 减 90°),顺时针。

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
- **主题驱动:** 颜色取自 `TyAnalogClock` / `TyAnalogClockHand` / `TyAnalogClockSecondHand`,不硬编码。改表盘外观请改这三个键——**不要**去改 `TyGauge`,那会连带改掉仪表 / 评分 / 进度环等一整族控件。
