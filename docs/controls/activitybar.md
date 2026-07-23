# TTyActivityBar

## 1. 概述

TTyActivityBar 是**不确定态线性进度条**(marching band),继承自 `TTyGraphicControl`。在一条淡色轨道上,两段 accent 色块相隔半个周期持续从左向右"行进",表示"正在处理、时长未知"。色块由 BGRABitmap 抗锯齿绘制,跨平台像素一致。用于加载 / 等待场景(与表示确定进度的 [TTyProgressBar](progressbar.md)、以及圆形忙碌指示器 [TTyActivityIndicator](activityindicator.md) 相对)。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ActivityBar` |
| `GetStyleTypeKey` 返回值 | `'TyActivityBar'`(轨道 / 边框)|

### 子部件 typeKey

子部件键在代码里由 `GetStyleTypeKey + 'Fill'` 拼出,与盒键绑死、不会各自漂移。

| typeKey | 绘制什么 | 读取的样式属性 |
|---------|----------|----------------|
| `TyActivityBar` | 轨道:圆角背景 + 边框(`DrawFrame`) | `background` / `border-color` / `border-width` / `border-radius` |
| `TyActivityBarFill` | 两段行进色块 | `background` / `border-radius` |

本控件**不再复用** `TyGauge` / `TyGaugeFill`——它是 [TTyProgressBar](progressbar.md) 的不确定态兄弟而非仪表的变体:它占的是对话框里同一个槽位,主题把 `TyProgressBar` / `TyProgressFill` 做成胶囊形时(多个内置皮肤如此),本控件必须跟着走,挂在仪表键上时这做不到。

> 主题作者注意:base 层按 typeKey **全有或全无**地回落。只覆盖了 `TyGauge` 的第三方主题**不会**覆盖到 `TyActivityBar` / `TyActivityBarFill`,这两个键会回落到内置 light 值;需要在皮肤里补上这两条选择器。
> 子部件是以**空状态集**解析的,因此 `TyActivityBarFill:hover` / `:disabled` 之类的选择器不会生效;伪类只对盒键 `TyActivityBar` 有效。

```pascal
uses tyControls.ActivityBar;
```

---

## 3. 属性表

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Active` | `Boolean` | `True` | 是否行进;`False` 时停下(静止显示)。 |

继承:`Align` / `Anchors` / `StyleClass` / `Controller`。

只读 `Phase: Double`(当前行进相位 `[0,1)`,供内省 / 测试)。

---

## 4. 事件

暴露 `TTyGraphicControl` 基线事件集(无自有事件)。见 [../events.md](../events.md)。

---

## 5. 状态与主题

轨道 + 边框来自 `TyActivityBar`,行进色块来自 `TyActivityBarFill`。**渲染**:先用 `DrawFrame` 画圆角轨道(背景 + 边框),再在轨道内画两段宽约轨道 35% 的 accent 色块——两段相隔半个周期,因此**总有一段可见,行进无断点**。相位由内部 `TTimer` 以 ~1.6s / 圈连续推进。

**行进条件:** 只有 `Active` **且**控件正在绘制(父窗口有句柄)时才动;**无句柄(headless / 渲染测试)时静止**——保证像素测试稳定。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.ActivityBar;

TyDefaultController.LoadTheme('themes/light.tycss');

var Busy: TTyActivityBar;
Busy := TTyActivityBar.Create(Self);
Busy.Parent := Self;
Busy.SetBounds(20, 20, 200, 8);
// 忙碌时显示,空闲时停下
Busy.Active := Working;
```

---

## 7. 注意事项

- **确定 vs 不确定:** 已知进度用 [TTyProgressBar](progressbar.md);未知时长用本控件(线性)或 [TTyActivityIndicator](activityindicator.md)(圆形)。
- **纯逻辑可测:** 相位推进 `TyActivityBarAdvance(phase, ms, periodMs)`(环绕到 `[0,1)`)与色块跨度 `TyActivityBarSpan(phase, left, right, segW)`(夹紧到轨道内)都是纯函数,已单元测试(`test.activitybar`)。
- **停下即省电:** `Active := False` 会停掉内部计时器。
- **主题驱动:** 颜色取自 `TyActivityBar` / `TyActivityBarFill`,不硬编码。改本控件外观请改这两个键——**不要**去改 `TyGauge`,那会连带改掉仪表 / 时钟 / 评分等一整族控件。
