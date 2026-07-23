# TTyShadowLabel

## 1. 概述

TTyShadowLabel 是 TyControls 库中带**投影(drop shadow)文字效果**的主题化静态文本控件，继承自 `TTyGraphicControl`（非 `TCustomControl`，因此**不可获得键盘焦点**）。它把 `Caption` 绘制两遍：先按 `(ShadowOffsetX, ShadowOffsetY)` 偏移、以 `ShadowColor` 画出阴影，再在正常位置以主题文字色画出正文，从而形成投影质感。典型用途：标题、图片/彩色背景上的醒目文字、需要与背景拉开层次的标签。

> `GetStyleTypeKey` 返回它**自己的** `'TyShadowLabel'`：字体族 / 字号 / 字重 / 文字颜色全部来自已解析的主题样式（`CurrentStyle`）。该键在 `themes/light.tycss` 中与 `TyLabel` 并列写在同一条规则的选择器列表里，所以解析值与从前一致，但主题现在**能单独够到它**——改投影标题的字号不必再去动全应用的静态标签。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ShadowLabel` |
| `GetStyleTypeKey` 返回值 | `'TyShadowLabel'`（**自有键**；正文字色 / 字体 / 字重 / `:disabled` 透明度取自它） |

```pascal
uses tyControls.ShadowLabel;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Caption` | `string` | `''` | 标签显示文字，绘制两遍（阴影 + 正文）。 |
| `ShadowColor` | `TTyColor` | `TyRGBA(0,0,0,120)` | 阴影文字颜色，默认半透明黑；`$AARRGGBB` 格式，支持 alpha。 |
| `ShadowOffsetX` | `Integer` | `1` | 阴影相对正文的**水平**偏移（逻辑像素，随 PPI 经 `P.Scale` 缩放）。 |
| `ShadowOffsetY` | `Integer` | `1` | 阴影相对正文的**垂直**偏移（逻辑像素，随 PPI 经 `P.Scale` 缩放）。 |
| `Alignment` | `TAlignment` | `taLeftJustify` | 文字**水平**对齐（左 / 右 / 居中）；阴影与正文使用同一对齐。 |
| `Layout` | `TTextLayout` | `tlCenter` | 文字**垂直**对齐（顶 / 居中 / 底）。 |
| `Enabled` | `Boolean` | `True` | 为 `False` 时触发 `:disabled` 主题状态（通常降低不透明度，阴影与正文一并变淡）。 |
| `Font` | `TFont` | 系统默认 | 传递 PPI 给渲染器；字体族与大小优先由主题控制。 |
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式。 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点。 |

### 继承的通用成员

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分。 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器。 |

> **注意：** TTyShadowLabel 继承自 `TTyGraphicControl`（`TGraphicControl` 的子类），**没有窗口句柄**，因此**不支持键盘焦点**，也就**没有** `:focus` 伪类状态。

---

## 4. 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnClick` | `TNotifyEvent` | 鼠标点击时（`TGraphicControl` 内置支持）。 |

> **基线事件集：** 仅暴露 **Tier A** 基线事件（鼠标 / 通用），**无** Tier B 键盘 / 焦点事件（不可获得焦点）。完整清单见 [../events.md](../events.md)。

---

## 5. 状态与主题

### 支持的伪类状态

| 伪类 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停 |
| `:active` | 鼠标左键按下 |
| `:disabled` | `Enabled = False` |

> `:focus` **不支持**（`TTyGraphicControl` 无窗口句柄，不可聚焦）。

### 解析的主题键

| typeKey | 画什么 |
|---------|--------|
| `TyShadowLabel` | 整个控件：背景（默认透明）、正文墨色 `color`、`font-family` / `font-size` / `font-weight`、`opacity`（`:disabled` 时阴影与正文一并变淡）。 |

**没有子部件键。** 阴影那一遍用的是控件自有属性 `ShadowColor` / `ShadowOffsetX` / `ShadowOffsetY`，构造时写死为半透明黑与 (1,1)，**不走主题**。样式模型里其实已经有对应的 `shadow: dx dy blur color` 令牌（`TyButton` 在 builtin/adwaita 里就用了），但本控件还没接线——所以扁平皮肤压不平这层投影，深色皮肤也改不掉黑底黑影。这属于本轮**有意推迟**的子部件扩展，别在主题里编造 `TyShadowLabelShadow` 之类的键，它不存在。

```css
/* light.tycss 中本控件所在的那条规则（与 TyLabel 等同列） */
TyLabel, TyHtmlLabel, TyLinkLabel, TyShadowLabel, TyGlowLabel, TyDivider, TyCharImage {
  background: alpha(#FFFFFF, 0);
  color: var(--on-surface);
  font-size: var(--font-size-base);
  font-weight: var(--font-weight-normal);
}
TyLabel:disabled, ..., TyShadowLabel:disabled, ... { opacity: var(--disabled-opacity); }

/* 只想改投影标题、不动别的标签，就单写它自己的键： */
TyShadowLabel { font-size: 18px; font-weight: 700; }
```

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.Types, tyControls.ShadowLabel;

TyDefaultController.LoadTheme('themes/light.tycss');

var Lbl: TTyShadowLabel;
Lbl := TTyShadowLabel.Create(Self);
Lbl.Parent := Self;
Lbl.SetBounds(24, 24, 280, 32);
Lbl.Caption := '带投影的标题';

// 更强的投影：加大偏移、加深阴影
var Big: TTyShadowLabel;
Big := TTyShadowLabel.Create(Self);
Big.Parent := Self;
Big.SetBounds(24, 64, 280, 40);
Big.Caption := 'HELLO';
Big.ShadowColor := TyRGBA(0, 0, 0, 180);
Big.ShadowOffsetX := 2;
Big.ShadowOffsetY := 2;
Big.Alignment := taCenter;
```

---

## 7. 注意事项

- **两遍绘制：** 阴影先画、正文后画，因此正文始终盖在阴影之上；偏移为 0 时阴影被正文完全覆盖，视觉上等同普通标签。
- **偏移随 PPI 缩放：** `ShadowOffsetX/Y` 是逻辑像素，渲染时经 `TTyPainter.Scale` 按目标 DPI 缩放，高分屏下阴影距离视觉一致。
- **阴影颜色带 alpha：** 默认 `TyRGBA(0,0,0,120)` 为半透明黑，可与任意背景自然叠加；`TTyColor` 为 `$AARRGGBB`。
- **不可聚焦：** 基类是 `TGraphicControl`，没有 HWND，`:focus` 伪类永不生效。
- **自有 typeKey：** typeKey 为 `'TyShadowLabel'`。它与 [TTyLabel](label.md) 在 `light.tycss` 里同列一条规则，因此默认外观一致；要单独调它，写 `TyShadowLabel { ... }`，**不要**去改 `TyLabel`——那会波及全应用的静态标签。
