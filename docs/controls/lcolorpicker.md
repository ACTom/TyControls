# TTyLColorPicker

## 1. 概述

TTyLColorPicker 是一个**竖直的 HSV 明度(V / 亮度)选择条**。在固定的 Hue + Sat 下,画一条从上到下的明度渐变(**顶部 V=1 最亮,底部 V=0 最暗**),并带一个可拖动的标记。它选出一个位于 `[0..1]` 的标量 `Position`(即 V 值),并把对应的颜色暴露为 `SelectedColor`。

继承自 [TTyCustomControl](../../source/tyControls.Base.pas)(带自有窗口句柄的图形控件),按库标准的 `TTyPainter` 方式绘制。复用 `'TyGauge'` 主题(条身背景 / 边框 / 标记文字色),**无需新增 `.tycss` 规则**。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.LColorPicker` |
| typeKey | `'TyGauge'`(条身背景 `Background` / 边框 `BorderColor` / 标记 `TextColor`)|

无新增 `.tycss`。

```pascal
uses tyControls.LColorPicker;
```

---

## 3. 属性 / 事件

| 成员 | 说明 |
|------|------|
| `Hue: Single` | 固定色相,`0..360`,默认 `0`。改变会重画。 |
| `Sat: Single` | 固定饱和度,`0..1`,默认 `1`。改变会重画。 |
| `Position: Single` | 选中的明度值 `0..1`,默认 `1`。**setter 会钳制到 `[0,1]`**、重画并触发 `OnChange`(仅在值真正改变时)。 |
| `SelectedColor: TTyColor`(只读) | 当前 Hue/Sat/Position 对应的不透明颜色,等价于 `TyHSVToRGB(Hue, Sat, Position, 255)`。 |
| `OnChange: TNotifyEvent` | `Position` 改变(拖动或程序赋值)时触发。 |

另继承 `Align` / `Anchors` / `StyleClass` / `Controller` 等通用属性。

---

## 4. 交互

- **在条上按下 / 拖动(左键)** → 按鼠标 Y 位置设置 `Position`(顶部=1,底部=0),`Position` 的 setter 完成钳制与 `OnChange`。
- 顶部代表最亮(V=1),底部代表最暗(V=0)。

---

## 5. 主题

条身、边框与标记全部取自 `'TyGauge'` 样式:

- **条身渐变** — 每一行按当前 V 值调用 `TyHSVToRGB(Hue, Sat, v)` 逐扫描线填充。
- **边框** — `BorderColor` / `BorderWidth`(存在且宽度 > 0 时才描边)。
- **标记** — 一条细的水平线,用 `TextColor`。

所有 chrome 颜色 / 尺寸均由主题 token 驱动,未硬编码。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.LColorPicker;

var LP: TTyLColorPicker;
LP := TTyLColorPicker.Create(Self);
LP.Parent := Self;
LP.SetBounds(20, 20, 28, 180);
LP.Hue := 210;      // 固定为一抹蓝
LP.Sat := 0.8;
LP.Position := 0.6; // 明度 0.6
// c := LP.SelectedColor;   // 取出选中的颜色
```

---

## 7. 注意事项

- **拖动是真机验证项:** 纯状态逻辑(`Position` 钳制、`SelectedColor` 计算、`OnChange` 只在真正改变时触发)已 headless 单测;鼠标拖动需真机验证。
- **Position 才是选中值:** 刻意命名为 `Position` 而非 `Value`,以免与其它带范围的控件混淆——它就是 HSV 的 V 分量。
