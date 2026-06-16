# TTyCaptionButton — API 参考

## 1. 概述

`TTyCaptionButton` 是 TyControls 标题栏的功能按钮控件，对应窗口的关闭、最小化、最大化和还原操作。`Kind` 属性同时决定两件事：**StyleClass 变体**（控制外观）和**字形（Glyph）**（控制绘制的图标），两者联动，无需分别配置。

`TTyCaptionButton` 是 `TTyTitleBar` 的**代码持有子组件**：由标题栏构造函数自动创建，每个标题栏持有三个实例（最小化/最大化/关闭），**不单独出现在调色板上、不单独放置**。其种类（kinds）与样式变体未变。

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Form` |
| typeKey | `TyCaptionButton` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Kind` | `TTyCaptionButtonKind` | `cbkClose`（枚举第一个值） | 按钮种类，同时决定 StyleClass 变体和字形。写入时自动更新 `StyleClass := KindVariant` 并触发 `Invalidate`。 |
| `ShowGlyphOnHoverOnly` | `Boolean` | `False` | 为 `True` 时，字形（关闭/最小化/最大化图标）仅在鼠标悬停（`FHover = True`）或按下（`FPressed = True`）时绘制；平时只显示背景。常用于 traffic-light 风格：圆圈始终可见，图标在悬停时才出现。详见 [docs/recipes-traffic-lights.md](../recipes-traffic-lights.md)。 |
| `OnClick` | `TNotifyEvent` | `nil` | 点击事件（继承自 `TControl`，在 published 中显式声明）。 |

### 类型定义

```pascal
TTyCaptionButtonKind = (cbkClose, cbkMin, cbkMax, cbkRestore);
```

### Kind 与 StyleClass / 字形的映射

| `Kind` 值 | `StyleClass`（KindVariant） | 字形（KindGlyph） | 用途 |
|-----------|---------------------------|-------------------|------|
| `cbkClose` | `'close'` | `tgClose` | 关闭窗口 |
| `cbkMin` | `'min'` | `tgMinimize` | 最小化窗口 |
| `cbkMax` | `'max'` | `tgMaximize` | 最大化窗口 |
| `cbkRestore` | `'restore'` | `tgRestore` | 还原窗口（最大化后替换 Max 按钮） |

### 继承的通用成员（来自 TTyCustomControl）

| 成员 | 说明 |
|------|------|
| `StyleClass` | 由 `Kind` 自动维护，**不应手动覆盖**（手动写入后，下次设置 `Kind` 会再次覆盖） |
| `Controller` | 关联的样式控制器（通常继承自 TTyTitleBar 所在的控制器链） |
| `Enabled` | 启用/禁用 |

## 4. 事件与方法

### public 方法

#### `function GetStyleTypeKey: string`（override）

返回 `'TyCaptionButton'`，用于主题样式查找。

#### `function KindVariant: string`

根据当前 `Kind` 返回对应的 CSS 变体类名字符串（`'close'`、`'min'`、`'max'`、`'restore'`）。由 `SetKind` 自动调用，通常无需外部直接调用。

#### `function KindGlyph: TTyGlyphKind`

根据当前 `Kind` 返回对应的字形枚举值。由 `RenderTo` 在绘制时调用，通常无需外部直接调用。

### protected 方法

| 方法 | 说明 |
|------|------|
| `procedure Click` | 重写后调用 `inherited Click`（触发 `OnClick`），无额外逻辑——系统按钮的窗口操作由 `TTyForm` 接线到各按钮的 `OnClick`。 |
| `procedure RenderTo(...)` | 绘制背景框架，然后在居中的 10×10 逻辑像素区域内绘制对应字形，线宽 1 逻辑像素（DPI 缩放后）。 |

### 事件

| 事件 | 类型 | 说明 |
|------|------|------|
| `OnClick` | `TNotifyEvent` | 用户点击按钮时触发。作为 `TTyForm` 标题栏系统按钮时，`TTyForm` 把此事件接线到窗口操作（最小化 → `WindowState := wsMinimized`；最大化/还原 → 引擎 `ToggleMaximize`；关闭 → `Close`）。 |

## 5. 状态与主题

### 状态

TTyCaptionButton 继承 `TTyCustomControl` 的状态机制：

| 状态常量 | 触发条件 |
|----------|----------|
| `tysNormal` | 正常 |
| `tysHover` | 鼠标悬停 |
| `tysActive` | 鼠标左键按下 |
| `tysFocused` | 键盘焦点 |
| `tysDisabled` | `Enabled = False` |

### light.tycss 内置规则

基础规则（适用于所有 Kind）：

```css
TyCaptionButton {
  background: alpha(#FFFFFF, 0);  /* 完全透明背景 */
  color: var(--on-surface);       /* #1F2937 */
  border-radius: 0px;
}
TyCaptionButton:hover  { background: darken(--surface, 12%); }
TyCaptionButton:active { background: darken(--surface, 20%); }
```

变体规则（由 `Kind` 自动设置的 `StyleClass` 触发）：

```css
/* close 变体 — 悬停时变红色背景，字形变白 */
TyCaptionButton.close:hover  { background: var(--danger); color: #FFFFFF; }
TyCaptionButton.close:active { background: darken(--danger, 10%); color: #FFFFFF; }

/* min/max 变体 — 仅定义 hover，与基础规则相同 */
TyCaptionButton.min:hover    { background: darken(--surface, 12%); }
TyCaptionButton.max:hover    { background: darken(--surface, 12%); }
```

`cbkRestore`（`'restore'`）在 light.tycss 中没有专属变体规则，继承基础规则。

### 渲染细节

- 字形绘制在按钮区域的正中央，固定逻辑尺寸 10×10 像素（DPI 缩放后为物理像素）。
- 字形颜色来自当前样式的 `TextColor`（即 CSS `color` 字段），因此 `close:hover` 时字形会变白（规则覆盖了 `color: #FFFFFF`）。
- 字形线宽 `P.Scale(1)`，即 1 逻辑像素（高 DPI 下按比例放大）。

## 6. 代码示例

### 独立使用

```pascal
uses tyControls.Form;

var
  Btn: TTyCaptionButton;
begin
  Btn := TTyCaptionButton.Create(Self);
  Btn.Parent := Self;
  Btn.SetBounds(200, 0, 46, 32);
  Btn.Kind := cbkClose;   // 自动设置 StyleClass = 'close'，字形 = tgClose
  Btn.OnClick := @OnCloseClick;
end;
```

### 运行时切换 Max/Restore

```pascal
// 最大化后，将 Max 按钮切换为 Restore 外观
TitleBar.MaxButton.Kind := cbkRestore;  // StyleClass → 'restore'，字形 → tgRestore
// 还原后，切换回 Max
TitleBar.MaxButton.Kind := cbkMax;      // StyleClass → 'max'，字形 → tgMaximize
```

（`TTyChromeEngine.ToggleMaximize` 内部即是此逻辑。）

### 自定义 close 按钮悬停颜色

在自定义主题文件中覆盖：

```css
TyCaptionButton.close:hover {
  background: #FF6B6B;
  color: #FFFFFF;
}
```

## 7. 注意事项

1. **Kind 自动维护 StyleClass：** 设置 `Kind` 时，内部会执行 `StyleClass := KindVariant`。若手动写入 `StyleClass`，下次写 `Kind` 时会再次覆盖——建议只通过 `Kind` 控制外观，不要手动设置 `StyleClass`。
2. **cbkRestore 无专属主题规则：** light.tycss 中没有 `TyCaptionButton.restore` 的变体规则，还原按钮使用与普通按钮相同的 hover/active 颜色。如需区分，在自定义主题中添加 `TyCaptionButton.restore:hover { ... }` 规则。
3. **按钮尺寸由 TTyTitleBar 控制：** 按钮宽度 46px、高度等于标题栏高度，由 `TTyTitleBar.LayoutButtons` 通过 `SetBounds` 强制设定，单独修改按钮的 `Width`/`Height` 在重新布局后会被覆盖。
4. **OnClick 的窗口操作由 TTyForm 接线：** 作为 `TTyForm` 标题栏系统按钮时，三个按钮的 `OnClick` 被窗体接线到最小化/最大化/关闭操作；若在 `TTyForm` 之外独立使用这些按钮，需要自行绑定 `OnClick`。
5. **tabStop 与焦点：** `TTyCaptionButton` 继承的 `TabStop` 默认为 `False`（标题按钮通常不参与键盘导航）。
