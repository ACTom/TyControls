# TTyHSColorPicker

## 1. 概述

TTyHSColorPicker 是一个**二维「色相 × 饱和度」方块**。X 轴是色相(Hue,`0..360`,左→右),Y 轴是饱和度(Sat,**顶部 = 1 满饱和,底部 = 0**),在一个**固定的明度(Value)**下绘制——因此可以由外部的 [TTyLColorPicker](lcolorpicker.md) 明度条来驱动这块方块的亮度,两者合成一个经典的 HSL/HSV 取色器。点击或拖动方块内任意位置即可选出 `(Hue, Sat)`,当前点上有一个十字准星圆圈,选中的颜色暴露为 `SelectedColor`。

继承自 [TTyCustomControl](../../source/tyControls.Base.pas)(带自有窗口句柄的图形控件),按库标准的 `TTyPainter` 方式绘制,主题上归属自己的 `'TyHSColorPicker'` 键(方块边框 / 准星色)。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.HSColorPicker` |
| `GetStyleTypeKey` 返回值 | `'TyHSColorPicker'`(边框 `BorderColor` / `BorderWidth`、准星 `TextColor`)|

### 子部件 typeKey

**本控件没有子部件键。** 它只解析盒键这一个键——方块内部是**算出来的颜色数据**,不由主题提供:

| typeKey | 绘制什么 | 读取的样式属性 |
|---------|----------|----------------|
| `TyHSColorPicker` | 方块四周的描边;当前点上的十字准星圆圈 | `border-color` / `border-width`(描边)/ `color`(准星) |

本控件**不再复用** `TyGauge`。方块内容是生成的颜色,仪表的 `background` / fill token 在这里毫无意义;它真正消费的只有 `color`(准星必须在整条色相带上都看得清)和 `border-color`。颜色对话框内部的同类控件早就有自己的 `TyColorArea` 键(见 `tyControls.Dialogs.Color`),公开版控件还挂着 `TyGauge` 属于前后不一致。

> 主题作者注意:base 层按 typeKey **全有或全无**地回落。只覆盖了 `TyGauge` 的第三方主题**不会**覆盖到 `TyHSColorPicker`;需要在皮肤里补上这条选择器。
> 准星与边框的**尺寸**不在本次拆键范围内(准星半径、线宽在绘制代码里是常量),暂时不可主题化。

```pascal
uses tyControls.HSColorPicker;
```

---

## 3. 属性 / 事件

| 成员 | 说明 |
|------|------|
| `Hue: Single` | 色相 `0..360`,默认 `0`。**setter 会钳制到 `[0,360]`**、重画并触发 `OnChange`(仅在值真正改变时)。 |
| `Sat: Single` | 饱和度 `0..1`,默认 `1`。**setter 会钳制到 `[0,1]`**、重画并触发 `OnChange`(仅在值真正改变时)。 |
| `Value: Single` | 固定明度 `0..1`,默认 `1`——方块以此亮度绘制。**setter 会钳制、仅重画,不触发 `OnChange`**(它是由外部明度条驱动的输入,不是本控件选出的值)。 |
| `SelectedColor: TTyColor`(只读) | 当前 Hue/Sat/Value 对应的不透明颜色,等价于 `TyHSVToRGB(Hue, Sat, Value, 255)`。 |
| `OnChange: TNotifyEvent` | `Hue` 或 `Sat` 改变(拖动或程序赋值)时触发。 |

另继承 `Align` / `Anchors` / `StyleClass` / `Controller` 等通用属性。

---

## 4. 交互

- **在方块上按下 / 拖动(左键)** → 按鼠标 X 设置 `Hue`(左=0,右=360)、按鼠标 Y 设置 `Sat`(顶=1,底=0);两个 setter 各自完成钳制与 `OnChange`。
- 十字准星圆圈落在 `(round(Hue/360*(w-1)), round((1-Sat)*(h-1)))`。

---

## 5. 主题与渲染

本控件是**窗口化控件**(自有 HWND),因此先用 `TyFillParentBg` 把整个矩形铺成父窗体背景,方块四周的空白才会露出窗体(或图片主题的照片)而不是 HWND 的白刷。方块本身用**两趟**快速绘制(非逐像素):

1. **色相打底** — 沿 X 逐列填一个满饱和、固定 Value 的水平色相渐变(每列一条 1px 竖线)。
2. **饱和度叠加** — 自上而下逐行叠一条水平灰线,alpha 从顶部 0(保留满饱和)到底部 255(灰 = `TyHSVToRGB(0,0,Value)`,即 S=0)。

准星与边框取自 `'TyHSColorPicker'` 样式:

- **边框** — `BorderColor` / `BorderWidth`(存在且宽度 > 0 时才描边)。
- **准星** — 一个小圆圈,用 `TextColor`。

所有 chrome 颜色 / 尺寸均由主题 token 驱动,未硬编码;方块内的渐变像素是由 HSV 计算出的**数据**。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.HSColorPicker, tyControls.LColorPicker;

var HS: TTyHSColorPicker; LP: TTyLColorPicker;
HS := TTyHSColorPicker.Create(Self);
HS.Parent := Self;
HS.SetBounds(20, 20, 180, 140);

LP := TTyLColorPicker.Create(Self);
LP.Parent := Self;
LP.SetBounds(210, 20, 28, 140);

// 用明度条驱动方块的亮度:
LP.OnChange := @LPChanged;   // 在处理器里 HS.Value := LP.Position;
// c := HS.SelectedColor;    // 取出选中的颜色
```

---

## 7. 注意事项

- **拖动是真机验证项:** 纯状态逻辑(`Hue`/`Sat`/`Value` 钳制、`SelectedColor` 计算、`OnChange` 只在真正改变时触发、`Value` 不触发 `OnChange`)已 headless 单测;鼠标拖动需真机验证。
- **Value 是输入而非输出:** `Value` 刻意不触发 `OnChange`——它是方块被绘制的固定亮度,通常由外部明度条(TTyLColorPicker)驱动;真正被本控件选出的是 `Hue` 与 `Sat`。
