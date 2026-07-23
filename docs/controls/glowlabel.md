# TTyGlowLabel

## 1. 概述

TTyGlowLabel 是**带柔光(Vista 风格辉光)的静态文本标签**,继承自 `TTyGraphicControl`(非 `TCustomControl`,**不可获得键盘焦点**)。文字背后会渲染一层柔和的光晕:把同一段文字用 `GlowColor` 光栅化到独立图层、经高斯模糊(`GlowRadius`,逻辑像素、随 PPI 缩放)后叠加数遍以增强,再在其上绘制清晰文字(颜色取自主题 `CurrentStyle.TextColor`)。背景透明,适合在深色 / 图片背景上做发光标题。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.GlowLabel` |
| `GetStyleTypeKey` 返回值 | `'TyGlowLabel'`(**自有键**:清晰文字的颜色 / 字体 / 字重取自它)|

`TyGlowLabel` 在 `themes/light.tycss` 中与 `TyLabel` 并列写在同一条规则的选择器列表里,所以解析值
与从前逐字节相同 —— 这一步开的是钩子,不改外观。要让发光标题用与静态标签不同的字号/字重,单写
`TyGlowLabel { ... }`;**不要**改 `TyLabel`,那会一并改掉全应用的每个静态标签。

光晕本身(`GlowColor` / `GlowRadius`)是控件自有属性,**不走主题**,见下文「状态与主题」。

```pascal
uses tyControls.GlowLabel;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Caption` | `string` | `''` | 标签文字;支持 `&` 助记符(渲染时按主机策略显示下划线)。 |
| `Alignment` | `TAlignment` | `taLeftJustify` | 文字**水平**对齐(左 / 右 / 居中)。 |
| `Layout` | `TTextLayout` | `tlCenter` | 文字**垂直**对齐(顶 / 居中 / 底)。 |
| `GlowColor` | `TTyColor` | `TyRGBA(255,255,255,200)` | 光晕颜色($AARRGGBB);默认为半透明白色柔光。**建议带 alpha**,以便叠加时自然堆积。 |
| `GlowRadius` | `Integer` | `4` | 光晕高斯模糊半径(逻辑像素,绘制时按 PPI 缩放);setter 夹紧到 `0..64`,`0` 表示不模糊。 |
| `Enabled` | `Boolean` | `True` | 为 `False` 时触发 `:disabled` 主题状态(通常降低不透明度,连同光晕一起变淡)。 |
| `Font` | `TFont` | 系统默认 | 传递 PPI 给渲染器;字体族 / 大小优先由主题控制。 |

继承:`Align` / `Anchors` / `StyleClass` / `Controller`。

### 继承的通用成员

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名,对应 `.tycss` 选择器的 `.classname` 部分。 |
| `Controller` | `TTyStyleController` | `nil`(用全局 `TyDefaultController`) | 指定使用哪个样式控制器。 |

> **注意:** 继承自 `TTyGraphicControl`(`TGraphicControl` 子类),**无窗口句柄**,不支持键盘焦点,故**无** `:focus` 伪类。

---

## 4. 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnClick` | `TNotifyEvent` | 鼠标点击时(`TGraphicControl` 内置支持)。 |

> **基线事件集:** 仅暴露 **Tier A** 基线事件(鼠标 / 通用),**无** Tier B 键盘 / 焦点事件。完整清单见 [../events.md](../events.md)。

---

## 5. 状态与主题

### 解析的主题键

| typeKey | 画什么 |
|---------|--------|
| `TyGlowLabel` | 整个控件:背景(默认透明)、**清晰那一层**文字的 `color`、`font-family` / `font-size` / `font-weight`、`opacity`(`:disabled` 时文字与光晕一并变淡)。 |

**没有子部件键 —— 光晕层暂不可主题化。** 光晕的颜色与半径来自控件自有属性 `GlowColor`(默认半透明白)
与 `GlowRadius`(默认 4),构造函数里写死,主题层够不着:任何深色或扁平皮肤都关不掉这层 Vista 白光。
样式模型其实已有 `shadow: dx dy blur color` 令牌可以承载它(偏移取 0 即为光晕),但本控件尚未接线。
这属于本轮**有意推迟**的扩展,别在主题里写 `TyGlowLabelGlow` 之类的键 —— 它不存在。

**渲染:** 若 `Caption` 非空,先把文字以 `GlowColor` 画到一张与画布等大的透明 BGRA 图层,`FilterBlurRadial(P.Scale(GlowRadius))` 高斯模糊后,按半径叠加 `1 + min(3, blurDev div 4)` 遍以加厚光晕(径向模糊会摊薄 alpha);随后在其上用 `CurrentStyle.TextColor` 绘制清晰文字。`GlowRadius = 0` 时跳过模糊,直接把 `GlowColor` 文字作为轻微底衬。`:disabled` 的 `opacity` 会作用于整帧(文字与光晕一并变淡)。

支持伪类:`:hover` / `:active` / `:disabled`(不支持 `:focus`)。另注:本控件**不读 `padding`**,内容区取整个矩形(与 `TTyLabel` 不同)。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.GlowLabel;

TyDefaultController.LoadTheme('themes/dark.tycss');

var G: TTyGlowLabel;
G := TTyGlowLabel.Create(Self);
G.Parent := Self;
G.SetBounds(24, 24, 320, 48);
G.Caption := '发光标题';
G.GlowColor := TyRGBA(80, 180, 255, 210);   // 青蓝辉光
G.GlowRadius := 8;                           // 更弥散的光晕
G.Alignment := taCenter;
```

---

## 7. 注意事项

- **光晕在图层上模糊,不污染背景:** 光晕画在独立的透明图层再叠加,背景保持透明,透出父 / 窗体内容。
- **GlowColor 带 alpha 更自然:** 叠加多遍时半透明色会平滑堆积;纯不透明色可能显得生硬。
- **半径夹紧:** `GlowRadius` 经 setter 夹紧到 `0..64`;`0` = 不模糊。`TyGlowClampRadius` 为纯函数并已单元测试。
- **主题驱动:** 文字颜色 / 字体 / 字重取自本控件自己的 `TyGlowLabel` 规则,**从不硬编码**;仅光晕颜色 / 半径是控件自有特效属性,目前主题够不着。
- **不可聚焦:** 基类是 `TGraphicControl`,无 HWND,`:focus` 永不生效。
