# TTyGearActivityIndicator

## 1. 概述

TTyGearActivityIndicator 是**不确定态忙碌指示器(齿轮 spinner)**,继承自 `TTyGraphicControl`。一个齿轮持续旋转,表示"正在处理、时长未知"。是 [TTyActivityIndicator](activityindicator.md)(旋转弧)的**装饰变体**,复用它的 `TyActivityAdvance` 旋转推进与 [TTyGearDial](geardial.md) 的 `TyGearToothAngle` 齿位布局。齿轮由 BGRABitmap `Canvas2D` 抗锯齿绘制,跨平台像素一致。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.GearActivityIndicator` |
| `GetStyleTypeKey` 返回值 | `'TyGauge'`(**复用**仪表:齿轮中心 faint 色)|
| 齿轮 typeKey | `'TyGaugeFill'`(复用仪表填充 = accent 齿轮)|

复用 `TTyGauge` 主题规则,无新增 `.tycss`。

```pascal
uses tyControls.GearActivityIndicator;
```

---

## 3. 属性表

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Active` | `Boolean` | `True` | 是否旋转;`False` 时停转(静止显示)。 |
| `Teeth` | `Integer` | `9` | 齿数(夹紧到 3..24)。 |

继承:`Align` / `Anchors` / `StyleClass` / `Controller`。

只读 `Angle: Double`(当前旋转角,供内省 / 测试)。

---

## 4. 事件

暴露 `TTyGraphicControl` 基线事件集(无自有事件)。见 [../events.md](../events.md)。

---

## 5. 状态与主题

复用 `TyGauge`(齿轮中心 faint 色)/ `TyGaugeFill`(accent 齿轮)。**渲染**:画 `Teeth` 个绕轮缘均布的齿(随 `Angle` 旋转)+ accent 圆盘 + faint 中心孔;`Angle` 由内部 `TTimer` 以 ~1.4s / 圈连续推进。

**旋转条件:** 只有 `Active` **且**控件正在绘制(父窗口有句柄)时才转;**无句柄(headless / 渲染测试)时静止**——保证像素测试稳定。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.GearActivityIndicator;

TyDefaultController.LoadTheme('themes/light.tycss');

var Spin: TTyGearActivityIndicator;
Spin := TTyGearActivityIndicator.Create(Self);
Spin.Parent := Self;
Spin.SetBounds(20, 20, 40, 40);
Spin.Active := Working;
```

---

## 7. 注意事项

- **装饰变体:** 功能与 [TTyActivityIndicator](activityindicator.md) 相同,只是外观是齿轮;喜欢简洁就用旋转弧,喜欢机械感就用齿轮。
- **纯逻辑可测:** 旋转推进复用 `TyActivityAdvance`(环绕到 `[0,360)`),齿位复用 `TyGearToothAngle`,均已单元测试。
- **停转即省电:** `Active := False` 会停掉内部计时器。
- **主题驱动:** 颜色取自 `TyGauge` / `TyGaugeFill`,不硬编码。
