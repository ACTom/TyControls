# TTyActivityIndicator

## 1. 概述

TTyActivityIndicator 是**不确定态忙碌指示器**(spinner),继承自 `TTyGraphicControl`。在一个淡色轨道环上,一段 accent 弧持续旋转,表示"正在处理、时长未知"。弧由 BGRABitmap `Canvas2D` 抗锯齿绘制,跨平台像素一致。用于加载 / 等待场景(与表示确定进度的 [TTyCircularProgress](circularprogress.md) 相对)。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ActivityIndicator` |
| `GetStyleTypeKey` 返回值 | `'TyActivityIndicator'`(轨道环)|

### 子部件 typeKey

子部件键在代码里由 `GetStyleTypeKey + 'Fill'` 拼出,与盒键绑死、不会各自漂移。

| typeKey | 绘制什么 | 读取的样式属性 |
|---------|----------|----------------|
| `TyActivityIndicator` | 淡色整环 track | `background` |
| `TyActivityIndicatorFill` | 旋转的 accent 弧 | `background` |

本控件**不再复用** `TyGauge` / `TyGaugeFill`。忙碌指示器与数据展示是两类东西:它常被调暗、常画在模态遮罩上需要浅色压深色、扁平风格还常要求 track **完全透明**——轨道被钉死在仪表的 sunk-track token 上时这些都写不出来。

> 主题作者注意:base 层按 typeKey **全有或全无**地回落。只覆盖了 `TyGauge` 的第三方主题**不会**覆盖到 `TyActivityIndicator` / `TyActivityIndicatorFill`;需要在皮肤里补上这两条选择器。
> 子部件以**空状态集**解析,`TyActivityIndicatorFill:hover` / `:disabled` 之类的选择器不会生效;伪类只对盒键有效。
> 本控件不画外框(不走 `DrawFrame`),因此盒键的 `border-*` 目前**不参与绘制**——它只提供 track 环的 `background`。

```pascal
uses tyControls.ActivityIndicator;
```

---

## 3. 属性表

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Active` | `Boolean` | `True` | 是否旋转;`False` 时停转(静止显示)。 |
| `Thickness` | `Integer` | `6` | 弧笔宽(逻辑像素,经 `Painter.Scale` 缩放)。 |
| `Sweep` | `Integer` | `270` | 旋转 accent 弧的长度(度,夹紧到 10..350)。 |

继承:`Align` / `Anchors` / `StyleClass` / `Controller`。

只读 `Angle: Double`(当前旋转角,供内省 / 测试)。

---

## 4. 事件

暴露 `TTyGraphicControl` 基线事件集(无自有事件)。见 [../events.md](../events.md)。

---

## 5. 状态与主题

轨道来自 `TyActivityIndicator`,旋转弧来自 `TyActivityIndicatorFill`。**渲染**:先画整环 track,再画从 `Angle` 起、长 `Sweep` 的 accent 弧;`Angle` 由内部 `TTimer` 以 ~1.1s / 圈连续推进。

**旋转条件:** 只有 `Active` **且**控件正在绘制(父窗口有句柄)时才转;**无句柄(headless / 渲染测试)时静止**——保证像素测试稳定。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.ActivityIndicator;

TyDefaultController.LoadTheme('themes/light.tycss');

var Spin: TTyActivityIndicator;
Spin := TTyActivityIndicator.Create(Self);
Spin.Parent := Self;
Spin.SetBounds(20, 20, 32, 32);
// 忙碌时显示,空闲时停转
Spin.Active := Working;
```

---

## 7. 注意事项

- **确定 vs 不确定:** 已知进度用 [TTyCircularProgress](circularprogress.md);未知时长用本控件。
- **纯逻辑可测:** 角度推进 `TyActivityAdvance(cur, ms, periodMs)` 是纯函数(环绕到 `[0,360)`),已单元测试(`test.activityindicator`)。
- **停转即省电:** `Active := False` 会停掉内部计时器。
- **主题驱动:** 颜色取自 `TyActivityIndicator` / `TyActivityIndicatorFill`,不硬编码。改本控件外观请改这两个键——**不要**去改 `TyGauge`,那会连带改掉仪表 / 时钟 / 评分等一整族控件。
