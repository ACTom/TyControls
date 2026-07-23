# TTyGearActivityIndicator

## 1. 概述

TTyGearActivityIndicator 是**不确定态忙碌指示器(齿轮 spinner)**,继承自 `TTyGraphicControl`。一个齿轮持续旋转,表示"正在处理、时长未知"。是 [TTyActivityIndicator](activityindicator.md)(旋转弧)的**装饰变体**,复用它的 `TyActivityAdvance` 旋转推进与 [TTyGearDial](geardial.md) 的 `TyGearToothAngle` 齿位布局。齿轮由 BGRABitmap `Canvas2D` 抗锯齿绘制,跨平台像素一致。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.GearActivityIndicator` |
| `GetStyleTypeKey` 返回值 | `'TyGearActivityIndicator'`(**被掏空的中心孔**)|

### 子部件 typeKey

子部件键在代码里由 `GetStyleTypeKey + 'Fill'` 拼出,与盒键绑死、不会各自漂移。

| typeKey | 绘制什么 | 读取的样式属性 |
|---------|----------|----------------|
| `TyGearActivityIndicator` | 齿轮中央那个孔 | `background` |
| `TyGearActivityIndicatorFill` | 齿 + 齿轮圆盘本体 | `background` |

**注意两个 token 的角色与仪表是反的:** 盒键画的是一个**孔**,而不是「填充背后的轨道」。这正是旧安排最难受的地方——中心孔被钉死在仪表的 sunk-track 色上,于是这个齿轮不论放在卡片、工具条还是暗色遮罩上,中间都塞着一块颜色不对的塞子,而且没有任何主题规则能修。

> 主题作者注意:base 层按 typeKey **全有或全无**地回落。只覆盖了 `TyGauge` 的第三方主题**不会**覆盖到这两个键;需要在皮肤里补上。
> 子部件以**空状态集**解析,`TyGearActivityIndicatorFill:disabled` 之类的选择器不会生效;伪类只对盒键有效。
> 本控件不画外框(不走 `DrawFrame`),因此盒键的 `border-*` 目前**不参与绘制**——它只提供中心孔的 `background`。

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

中心孔取 `TyGearActivityIndicator.background`,齿 + 圆盘取 `TyGearActivityIndicatorFill.background`。**渲染**:画 `Teeth` 个绕轮缘均布的齿(随 `Angle` 旋转)+ 同色圆盘,再在中央挖出一个孔色的圆;`Angle` 由内部 `TTimer` 以 ~1.4s / 圈连续推进。

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
- **主题驱动:** 颜色取自 `TyGearActivityIndicator` / `TyGearActivityIndicatorFill`,不硬编码。改本控件外观请改这两个键——**不要**去改 `TyGauge`,那会连带改掉仪表 / 时钟 / 评分等一整族控件。
