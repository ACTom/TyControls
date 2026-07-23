# TTyImage

## 1. 概述

TTyImage 是 TyControls 库中的**主题化位图图像控件**，继承自 `TTyGraphicControl`（叶子图形控件，无窗口句柄、不可聚焦）。它显示一个 `TPicture`（任意 LCL 图形——PNG / BMP / JPG，支持 alpha 透明），并通过 `TTyPainter` 自绘，从而与主题化界面无缝融合。功能对标 LCL `TImage`，提供**拉伸 / 等比 / 居中**三种摆放模式。

> 主题：`GetStyleTypeKey` 返回 `'TyImage'`（本控件**自有**的键）。默认 `Transparent = True` 时**不绘制背景**；置为 `False` 时先用 `DrawFrame` 画出 `TyImage` 表面（填充 + 边框）再叠加图像。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Image` |
| `GetStyleTypeKey` 返回值 | `'TyImage'`（**自有 typeKey**） |

它从前返回 `'TyPanel'`。这里借用面板键的代价最直观：本控件在默认透明模式下唯一读取的样式属性就是 `opacity`（源码注释承诺"禁用的图片会变淡"），而 `light.tycss` 给 `TyPanel` **没有**定义任何状态规则，所以那句承诺当时并不成立——而唯一的补法 `TyPanel:disabled { opacity }` 会让全应用的容器一起变淡。现在写 `TyImage:disabled { opacity: 0.5 }` 就只作用于图片。`TyImage` 已作为附加选择器并入主题里 `TyPanel` 的规则块，解析值与从前逐字节相同，**开钩子而不动像素**；第三方主题若只覆盖了 `TyPanel`，需要补上 `TyImage`（主题层按 typeKey 全有全无地回落）。

### 子部件 typeKey

**没有。** 控件只解析这一个盒子样式：`Transparent = False` 时它是图片的衬底（填充 + 边框 + 圆角），`Transparent = True` 时只取其中的 `opacity`。

```pascal
uses tyControls.Image;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Picture` | `TPicture` | 空图 | 要显示的图像（控件拥有；其 `OnChange` 触发重绘，`AutoSize=True` 时同时重新适配尺寸）。 |
| `Stretch` | `Boolean` | `False` | `True` 时图像**填满**客户区（不保持宽高比）；`Proportional=True` 时本项被忽略。 |
| `Proportional` | `Boolean` | `False` | `True` 时**等比缩放**以完整装入客户区（letterbox 留边），保持宽高比。 |
| `Center` | `Boolean` | `True` | 图像未填满时是否居中（`False` 则左上角对齐）。 |
| `Transparent` | `Boolean` | `True` | `True`（默认）不画背景，透出下层；`False` 先画 `TyImage` 表面。 |
| `Enabled` | `Boolean` | `True` | 为 `False` 时触发 `:disabled` 主题状态（通常降低不透明度，图像一并变淡）。 |
| `AutoSize` | `Boolean` | `False` | `True` 时控件尺寸跟随图像原始尺寸（`CalculatePreferredSize` 返回 `Picture.Width/Height`）。 |
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式。 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点。 |

### 继承的通用成员

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分。 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器。 |

**构造时默认尺寸：** `Width = 90`，`Height = 90`（可在创建后自由调整；`AutoSize=True` 时随图像尺寸变化）。

> **注意：** TTyImage 继承自 `TTyGraphicControl`（`TGraphicControl` 的子类），**没有窗口句柄**，因此不可获得键盘焦点，也就**没有** `:focus` 伪类状态。

---

## 4. 三种摆放模式

摆放几何由纯函数 `TyImageFitRect` 计算（模块级、已单元测试），返回图像在客户区内的目标矩形（客户区坐标）：

```pascal
function TyImageFitRect(ASrcW, ASrcH, ADstW, ADstH: Integer;
  AStretch, AProportional, ACenter: Boolean): TRect;
```

| 模式 | `Stretch` | `Proportional` | 行为 |
|------|-----------|----------------|------|
| **原始尺寸** | `False` | `False` | 按图像原始像素尺寸绘制，**不缩放**；`Center=True` 时居中，否则贴左上角。图像大于客户区时会溢出（被裁剪）。 |
| **拉伸填充** | `True` | `False` | 图像**精确填满**客户区 `Rect(0,0,W,H)`，不保持宽高比（可能变形）。 |
| **等比适配** | 忽略 | `True` | 图像**等比缩放**以完整装入客户区（保持宽高比、留 letterbox 边），`Center=True` 时居中。`Proportional` 优先于 `Stretch`。 |

举例：源 `100×50` 装入 `200×200`——

- 原始尺寸 + 居中：`Rect(50, 75, 150, 125)`
- 拉伸填充：`Rect(0, 0, 200, 200)`
- 等比适配 + 居中：放大 2 倍成 `200×100`，垂直居中 → `Rect(0, 50, 200, 150)`

---

## 5. 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnClick` | `TNotifyEvent` | 鼠标点击时（`TGraphicControl` 内置支持）。 |

> **基线事件集：** 仅暴露 **Tier A** 基线事件（鼠标 / 通用），**无** Tier B 键盘 / 焦点事件（不可聚焦）。完整清单见 [../events.md](../events.md)。

---

## 6. 状态与主题

### 支持的伪类状态

| 伪类 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停 |
| `:active` | 鼠标左键按下 |
| `:disabled` | `Enabled = False` |

> `:focus` **不支持**（`TTyGraphicControl` 无窗口句柄，不可聚焦）。

### 主题来源

走 `TyImage` 选择器（默认取值与 [panel.md](panel.md) 相同，但名字独立）。默认 `Transparent = True` 时背景完全不绘制，图像浮在下层内容之上；仅当 `Transparent = False` 时才画出 `TyImage` 的填充 + 圆角边框作为图像衬底。无论透明与否，`:disabled` 的 `opacity` 都会作用到最终像素上（图像随之变淡）——**但内置主题并未声明这条状态规则**，要让禁用的图片真的变淡，需要主题自己写：

```css
/* 盒子样式（内置主题中与 TyPanel 同值同块），仅在 Transparent=False 时可见 */
TyImage {
  background: var(--surface);
  border-color: var(--border);
  border-width: 1px;
  border-radius: var(--radius);
  padding: 8px;
}
/* 想要"禁用即变淡"就加这一条——只影响图片，不影响任何容器 */
TyImage:disabled { opacity: 0.5; }
```

---

## 7. 代码示例

```pascal
uses
  Graphics, tyControls.Controller, tyControls.Image;

TyDefaultController.LoadTheme('themes/light.tycss');

var Img: TTyImage;
Img := TTyImage.Create(Self);
Img.Parent := Self;
Img.SetBounds(16, 16, 240, 160);
Img.Picture.LoadFromFile('assets/photo.png');

// 等比适配：完整装入控件、保持宽高比、居中留边
Img.Proportional := True;
Img.Center := True;

// 或：拉伸填满（可能变形）
// Img.Stretch := True;

// 带衬底：画出 TyImage 表面再叠加图像
Img.Transparent := False;
```

---

## 8. 注意事项

- **默认透明：** `Transparent = True`（不同于面板），图像直接浮在下层内容上，不画任何背景；需要衬底或圆角边框时置为 `False`。
- **模式优先级：** `Proportional = True` 时 `Stretch` 被忽略——等比适配永远保持宽高比，不会变形填满。
- **空图安全：** `Picture` 为空（`Graphic = nil` 或 `Empty`）时绘制阶段直接跳过，不解引用、不崩溃，适用于无头 / 单元测试环境。
- **AutoSize 跟随原始尺寸：** `AutoSize = True` 时控件尺寸取 `Picture.Width/Height`；空图时保持当前尺寸。
- **alpha 支持：** 通过 `TBGRABitmap.Create(Picture.Graphic)` 载入并以 `dmDrawWithTransparency` 合成，PNG 等带 alpha 的图像会正确透明叠加。
- **不可聚焦：** 基类是 `TGraphicControl`，没有 HWND，`:focus` 伪类永不生效。
- **多图管理：** 若需按名字 / 索引管理一批图像（喂给工具栏、树视图等），见 [[TTyImageCollection]]。
