# TTyCharImage

## 1. 概述

TTyCharImage 是一个**叶子图形控件**，把 [[TTyIconFont]] 中的**单个图标字体字形**当作一张图片来显示：居中、着色、按指定大小缩放。可以把它理解为“扔在窗体上的一个可缩放矢量图标”——指定一个 IconFont、一个字形名、一个尺寸和颜色即可。

它自身不持有字体，光栅化完全委托给所指定的 `TTyIconFont.RenderGlyph`（返回一张调用方拥有的透明 BGRA 位图），再把该位图**居中合成**到画布并释放。当未指定 IconFont、`GlyphName` 为空或字形未映射时，控件**什么都不画**——`RenderGlyph` 在这些情况下返回空透明位图，因此绘制路径始终是**无头安全**的（无字体、无句柄、不崩溃）。

继承自 `TTyGraphicControl`（`TGraphicControl` 的子类），**没有窗口句柄**，因此**不可获得键盘焦点**，也就没有 `:focus` 伪类状态。

> 复用标签主题：`GetStyleTypeKey` 返回 `'TyLabel'`，因此**不新增任何 `.tycss` 规则**。背景默认透明（与标签一致），字形颜色回退到主题解析出的文字色 `TextColor`，`:disabled` 的不透明度会像标签文字变淡一样让字形一并变淡。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.CharImage` |
| `GetStyleTypeKey` 返回值 | `'TyLabel'`（**复用** TyLabel 主题，不引入新选择器） |

```pascal
uses tyControls.IconFont, tyControls.CharImage;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `IconFont` | `TTyIconFont` | `nil` | 字形来源。用 `FreeNotification`/`Notification` 挂钩：所指字体被释放时自动置 `nil`，不留悬垂引用。 |
| `GlyphName` | `string` | `''` | 要显示的字形名（对应 IconFont 的 `Glyphs` 映射，如 `save`）。为空则不绘制。 |
| `GlyphSize` | `Integer` | `0` | 字形边长（**逻辑像素**，随 PPI 经 `P.Scale` 缩放）。`0` = 自动：适配较小的一边减去两侧内边距（`TyCharImagePad`）。 |
| `GlyphColor` | `TTyColor` | `TyGlyphColorDefault` | 字形填充色。默认哨兵值 `TyGlyphColorDefault`（即全透明 `$00000000`，表示“**用主题**”）→ 取 `CurrentStyle.TextColor`；设为其他值则覆盖主题色。 |
| `AutoSize` | `Boolean` | `False` | 为 `True` 且 `GlyphSize>0` 时，控件按字形尺寸 + 内边距自适应大小。 |
| `Enabled` | `Boolean` | `True` | 为 `False` 时触发 `:disabled` 主题状态（通常降低不透明度，字形一并变淡）。 |
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式。 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点。 |

### 继承的通用成员

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分。 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器。 |

> **注意：** TTyCharImage 继承自 `TTyGraphicControl`（`TGraphicControl` 的子类），**没有窗口句柄**，因此**不支持键盘焦点**，也就**没有** `:focus` 伪类状态。

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

复用 `TyLabel` 选择器（见 [label.md](label.md)）：透明背景、无边框、文字颜色 `--on-surface`。字形颜色取自 `CurrentStyle.TextColor`（即 `TyLabel` 的 `color`），除非用 `GlyphColor` 显式覆盖。`:disabled` 的 `opacity` 会让字形一并半透明。

```css
/* 复用的规则（来自 light.tycss 的 TyLabel） */
TyLabel {
  background: alpha(#FFFFFF, 0);
  color: var(--on-surface);
}
TyLabel:disabled { opacity: 0.5; }
```

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.Types,
  tyControls.IconFont, tyControls.CharImage;

TyDefaultController.LoadTheme('themes/light.tycss');

// 1) 准备一个图标字体源（一次即可，多个 CharImage 共享）
var Icons: TTyIconFont;
Icons := TTyIconFont.Create(Self);
Icons.FontFile := 'assets/fontawesome.ttf';   // 进程私有加载（Windows）
Icons.FontFamily := 'Font Awesome 6 Free';
Icons.MapGlyph('save', $F0C7);

// 2) 放一个字形图标
var Ico: TTyCharImage;
Ico := TTyCharImage.Create(Self);
Ico.Parent := Self;
Ico.SetBounds(24, 24, 48, 48);
Ico.IconFont := Icons;
Ico.GlyphName := 'save';
Ico.GlyphSize := 32;                 // 逻辑像素；0 = 自动适配控件

// 3) 用主题色（默认）或显式着色
Ico.GlyphColor := TyGlyphColorDefault;   // 用主题 TextColor（默认）
// Ico.GlyphColor := TyRGB(220, 40, 40); // 或强制红色
```

---

## 7. 注意事项

- **需要字体已加载/安装：** 渲染出的字形像素依赖真实的图标字体。请通过 [[TTyIconFont]] 的 `FontFile`（Windows 进程私有加载）或在系统中安装对应字体族，并把 `FontFamily` 设为该族名。**无头/单元测试环境下没有字体，字形渲染为空透明位图——逻辑正确但画不出可见像素**，属预期。
- **`GlyphColor` 哨兵：** 默认 `TyGlyphColorDefault`（全透明 `$00000000`）表示“用主题”，绝不会作为真实可见颜色，因此可安全兼作“未设置”标记；设为任意其他 `TTyColor`（`$AARRGGBB`）即覆盖主题色。
- **尺寸随 PPI 缩放：** `GlyphSize` 是逻辑像素，渲染时经 `TTyPainter.Scale` 按目标 DPI 缩放，高分屏下视觉一致。`0` 时自动适配较小边减两侧内边距。
- **透明背景：** 与标签一样默认透明，仅绘制字形本身；`:disabled` 的不透明度会让字形一并变淡。
- **不可聚焦：** 基类是 `TGraphicControl`，没有 HWND，`:focus` 伪类永不生效。
- 单字形图像用本控件；若需要把多个字形当作 `TImageList` 那样按索引取用（例如喂给工具栏 / 树视图），见 [[TTyGlyphImageList]]。
