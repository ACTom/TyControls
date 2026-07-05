# TTyShadowLabel

## 1. 概述

TTyShadowLabel 是 TyControls 库中带**投影(drop shadow)文字效果**的主题化静态文本控件，继承自 `TTyGraphicControl`（非 `TCustomControl`，因此**不可获得键盘焦点**）。它把 `Caption` 绘制两遍：先按 `(ShadowOffsetX, ShadowOffsetY)` 偏移、以 `ShadowColor` 画出阴影，再在正常位置以主题文字色画出正文，从而形成投影质感。典型用途：标题、图片/彩色背景上的醒目文字、需要与背景拉开层次的标签。

> 复用标签主题：`GetStyleTypeKey` 返回 `'TyLabel'`，因此**不新增任何 `.tycss` 规则**，字体族 / 字号 / 字重 / 文字颜色全部来自已解析的主题样式（`CurrentStyle`）。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ShadowLabel` |
| `GetStyleTypeKey` 返回值 | `'TyLabel'`（**复用** TyLabel 主题，不引入新选择器） |

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

### 主题来源

复用 `TyLabel` 选择器（见 [label.md](label.md)）：透明背景、无边框、文字颜色 `--on-surface`。`ShadowColor` 是控件自有属性，**不**由主题驱动（阴影颜色是效果参数），但正文颜色 `CurrentStyle.TextColor` 完全来自主题。`:disabled` 的 `opacity: 0.5` 会让阴影与正文一并半透明。

```css
/* 复用的规则（来自 light.tycss 的 TyLabel） */
TyLabel {
  background: alpha(#FFFFFF, 0);
  color: var(--on-surface);
  font-size: 10px;
  font-weight: 400;
}
TyLabel:disabled { opacity: 0.5; }
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
- **复用主题：** typeKey 为 `'TyLabel'`，与 [TTyLabel](label.md) 共享 `.tycss` 规则，无需为本控件单独写主题。
