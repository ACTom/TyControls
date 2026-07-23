# TTyRating

## 1. 概述

TTyRating 是**交互式星级评分**控件,继承自 `TTyCustomControl`(可获焦、响应鼠标与键盘)。横向排列 `Count` 颗五角星,已评部分(取自 `TyRatingStar`)按 `Value` 填充,其余描边;`AllowHalf` 时支持半星(左半填充)。鼠标悬停实时预览光标下的分值,点击提交;再次点击当前的单星值可清零。星形由 BGRABitmap `Canvas2D` 抗锯齿绘制。直接操作**吸附**(无动画),跨平台像素一致。用于打分、满意度、难度等场景。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Rating` |
| `GetStyleTypeKey` 返回值 | `'TyRating'`(空星 / 半星的描边)|

### 子部件 typeKey

子部件键在代码里由 `GetStyleTypeKey + 'Star'` 拼出,与盒键绑死、不会各自漂移。

| typeKey | 绘制什么 | 读取的样式属性 |
|---------|----------|----------------|
| `TyRating` | 空星与半星的描边轮廓 | `color`(描边墨色)/ `border-width`(描边线宽) |
| `TyRatingStar` | 已评星的实心星形 | `background` |

本控件**不再复用** `TyGauge` / `TyGaugeFill`。星星那抹金色是 UI 套件里最「主题专属」的颜色,不该在构造上就等于 app 的 accent:旧安排下改评分颜色会顺手改掉每一个进度环、spinner 和时钟指针。

**`TyRatingStar` 支持 `:hover`。** 悬停预览进行中(`FHoverValue >= 0`)时,星形样式是带 `:hover` 状态解析的,所以皮肤可以给「预览中的星」单独配色——这是本次新开的一条轴,旧安排下预览只能沿用已提交的填充色。light.tycss 刻意**不写** `TyRatingStar:hover`,于是它回落到普通规则、像素与从前一致;想要预览态变色的皮肤自己加这条选择器即可。

> 主题作者注意:base 层按 typeKey **全有或全无**地回落。只覆盖了 `TyGauge` 的第三方主题**不会**覆盖到 `TyRating` / `TyRatingStar`;需要在皮肤里补上这两条选择器。
> 本控件不画外框(不走 `DrawFrame`),星形描边用的是 `border-width` 配 `color`,因此 `TyRating` 的 `background` / `border-color` 目前**不参与绘制**。

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

描边 / 空星取 `TyRating.color`、边宽取 `TyRating.border-width`;已评星取 `TyRatingStar.background`(悬停预览时以 `:hover` 状态解析)。**渲染:** 本控件是**窗口化控件**(自有 HWND),先用 `TyFillParentBg` 把整个矩形铺成父窗体背景(星与星之间的空隙才不会露出 HWND 的白刷);再把宽度均分为 `Count` 个星格,每格居中画一颗五角星(10 个内外交替顶点的多边形,顶点在正上方)。`Value ≥ i+1` 的星整颗填 `TyRatingStar`;`Value ≥ i+0.5` 的星裁剪到左半填充再整颗描边(半星);其余仅描边。**交互:** 悬停用 `TyRatingValueFromX` 预览光标下分值(不改 `Value`),移出还原;左键点击提交;整星模式下再次点击当前单星值清零。方向键 ± 一步(半星模式为 0.5)、Home=0、End=Count。

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
- **主题驱动:** 颜色 / 边宽取自 `TyRating` / `TyRatingStar`,不硬编码。改评分外观请改这两个键——**不要**去改 `TyGauge`,那会连带改掉仪表 / 时钟 / 进度环等一整族控件。
