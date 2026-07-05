# TTyRating

## 1. 概述

TTyRating 是**交互式星级评分**控件,继承自 `TTyCustomControl`(可获焦、响应鼠标与键盘)。横向排列 `Count` 颗五角星,已评部分(accent = `TyGaugeFill`)按 `Value` 填充,其余描边;`AllowHalf` 时支持半星(左半填充)。鼠标悬停实时预览光标下的分值,点击提交;再次点击当前的单星值可清零。星形由 BGRABitmap `Canvas2D` 抗锯齿绘制。直接操作**吸附**(无动画),跨平台像素一致。用于打分、满意度、难度等场景。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Rating` |
| `GetStyleTypeKey` 返回值 | `'TyGauge'`(**复用**:星形描边 / 空星取其 `color`,边宽取其 `border-width`)|
| 填充 typeKey | `'TyGaugeFill'`(已评星取其 `background` = accent)|

复用 `TTyGauge` 主题规则,无新增 `.tycss`。

```pascal
uses tyControls.Rating;
```

---

## 3. 属性表

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Count` | `Integer` | `5` | 星数(≥1);减小时 `Value` 随之夹紧。 |
| `Value` | `Double` | `0` | 当前分值,夹紧到 `0..Count`;赋值仅在**真正变化**时触发 `OnChange`。 |
| `AllowHalf` | `Boolean` | `False` | 允许半星(0.5 步);关闭时把已有半星四舍五入到整星。 |
| `ReadOnly` | `Boolean` | `False` | 只读:忽略鼠标 / 键盘改值,并丢弃悬停预览。 |

继承:`Font` / `Align` / `Anchors` / `StyleClass` / `Controller` / `TabStop`(默认 `True`)。

---

## 4. 事件

| 事件 | 触发时机 |
|------|----------|
| `OnChange` | `Value` **真正改变**时(点击 / 键盘 / 程序赋值统一经 `ApplyValue` 单一出口;同值赋值不触发)。 |

另暴露 `TTyCustomControl` 基线事件集。见 [../events.md](../events.md)。

---

## 5. 状态与主题

复用 `TyGauge`(星形描边 / 空星取 `color`、边宽取 `border-width`)/ `TyGaugeFill`(已评星取 `background`)。**渲染:** 把宽度均分为 `Count` 个星格,每格居中画一颗五角星(10 个内外交替顶点的多边形,顶点在正上方)。`Value ≥ i+1` 的星整颗 accent 填充;`Value ≥ i+0.5` 的星裁剪到左半 accent 填充再整颗描边(半星);其余仅描边。**交互:** 悬停用 `TyRatingValueFromX` 预览光标下分值(不改 `Value`),移出还原;左键点击提交;整星模式下再次点击当前单星值清零。方向键 ± 一步(半星模式为 0.5)、Home=0、End=Count。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.Rating;

TyDefaultController.LoadTheme('themes/light.tycss');

var Rt: TTyRating;
Rt := TTyRating.Create(Self);
Rt.Parent := Self;
Rt.SetBounds(20, 20, 140, 28);
Rt.Count := 5;
Rt.AllowHalf := True;
Rt.Value := 3.5;              // 三星半
Rt.OnChange := @HandleRate;   // 用户改分时回调
```

---

## 7. 注意事项

- **交互 vs 只读展示:** 需要用户打分用本控件(默认可交互);纯展示可设 `ReadOnly := True`,或用弧 / 指针式的 [TTyGauge](gauge.md) / [TTyMeter](meter.md)。
- **清零手势:** 整星模式下,点击**当前分值所在的那颗星**会清零(0);半星模式不启用该手势(避免与半步选择冲突)。
- **纯逻辑可测:** x → 分值映射 `TyRatingValueFromX`(整 / 半步、越界夹紧、`Count`/宽度 ≤ 0 安全)为纯函数并已单元测试。
- **无动画:** 评分为离散选择,直接吸附到目标分值,headless 渲染稳定。
- **主题驱动:** 颜色 / 边宽取自 `TyGauge` / `TyGaugeFill`,不硬编码。
