# TTyButton

## 1. 概述

TTyButton 是 TyControls 库中的主题化按钮控件，继承自 `TTyCustomControl`。典型用途：触发操作（提交、确认、删除等），支持默认、`primary`、`danger` 三种视觉变体，通过 `StyleClass` 切换。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Button` |
| `GetStyleTypeKey` 返回值 | `'TyButton'` |

在 `.tycss` 文件中，该控件对应的选择器前缀为 `TyButton`，变体用点号分隔，例如 `TyButton.primary`。

```pascal
uses tyControls.Button;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Caption` | `string` | `''` | 按钮显示文字，居中绘制 |
| `Enabled` | `Boolean` | `True` | 为 `False` 时触发 `:disabled` 主题状态，控件不响应交互 |
| `Font` | `TFont` | 系统默认 | 传递 PPI 给渲染器；字体族与大小优先由主题控制 |
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点 |

### 继承的通用成员

每个 TyControls 控件都从 `TTyCustomControl`（`tyControls.Base`）继承以下两个 published 属性：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分；空字符串表示使用基础规则 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器；为 `nil` 时自动回退到全局默认控制器 |

**状态跟踪字段（protected，不 published）：**

| 字段/状态 | 类型 | 说明 |
|-----------|------|------|
| `FHover` | `Boolean` | 鼠标悬停时为 `True`，触发 `:hover` 主题状态 |
| `FPressed` | `Boolean` | 鼠标左键按下时为 `True`，触发 `:active` 主题状态 |
| `Focused`（继承自 `TCustomControl`） | `Boolean` | 获得键盘焦点时触发 `:focus` 主题状态 |
| `Enabled = False` | — | 触发 `:disabled` 主题状态，优先级最高（disabled 时其他状态均不生效） |

---

## 4. 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnClick` | `TNotifyEvent` | 鼠标点击或通过 `Click` 方法触发时 |

---

## 5. 状态与主题

### 支持的伪类状态

| 伪类 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停 |
| `:focus` | 获得键盘焦点 |
| `:active` | 鼠标左键按下 |
| `:disabled` | `Enabled = False` |

### light.tycss 内置规则摘要

```css
TyButton {
  background: var(--surface);        /* #FFFFFF */
  color: var(--on-surface);          /* #1F2937 */
  border-color: var(--border);       /* #D1D5DB */
  border-width: 1px;
  border-radius: var(--radius);      /* 6px */
  padding: 6px;
  font-size: 10px;
  font-weight: 400;
}
TyButton:hover    { background: darken(--surface, 4%); }
TyButton:focus    { border-color: var(--accent); }      /* #3B82F6 */
TyButton:active   { background: darken(--surface, 10%); }
TyButton:disabled { opacity: 0.5; }

/* StyleClass = 'primary' */
TyButton.primary  { background: var(--accent); color: #FFFFFF; border-color: var(--accent); }
TyButton.primary:hover  { background: lighten(--accent, 8%); }
TyButton.primary:active { background: darken(--accent, 8%); }

/* StyleClass = 'danger' */
TyButton.danger   { background: var(--danger); color: #FFFFFF; border-color: var(--danger); }
TyButton.danger:hover   { background: lighten(--danger, 8%); }
TyButton.danger:active  { background: darken(--danger, 8%); }
```

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.Button;

// 加载主题（通常在窗体 Create 最顶部执行一次）
TyDefaultController.LoadTheme('themes/light.tycss');

// 默认按钮
var Btn: TTyButton;
Btn := TTyButton.Create(Self);
Btn.Parent := Self;
Btn.SetBounds(24, 24, 160, 32);
Btn.Caption := '默认按钮';
Btn.OnClick := @HandleClick;

// 主要按钮（蓝色填充）
var BtnPrimary: TTyButton;
BtnPrimary := TTyButton.Create(Self);
BtnPrimary.Parent := Self;
BtnPrimary.SetBounds(24, 64, 160, 32);
BtnPrimary.Caption := '确认';
BtnPrimary.StyleClass := 'primary';
BtnPrimary.OnClick := @HandleClick;

// 危险按钮（红色填充）
var BtnDanger: TTyButton;
BtnDanger := TTyButton.Create(Self);
BtnDanger.Parent := Self;
BtnDanger.SetBounds(24, 104, 160, 32);
BtnDanger.Caption := '删除';
BtnDanger.StyleClass := 'danger';

// 禁用态
BtnDanger.Enabled := False;
```

完整可运行示例参见 `examples/button/umain.pas`。

---

## 7. 状态过渡动画 (v1.10)

`TTyButton` 支持悬停/离开时背景色在 普通态 与 `:hover` 态之间平滑渐变的过渡动画，由 `tyControls.Animation` 单元的 `TTyAnimator` 驱动。

### 开关属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `AnimationsEnabled` | `Boolean` | `False` | 是否启用背景色悬停渐变动画。**public 属性，不 published**（不写入 `.lfm`），需在代码中设置。 |

> 这是唯一的动画开关。**没有**单独的时长 / 缓动曲线属性可供配置——时长与缓动在控件内部固定（见下）。

### 行为

- **默认关闭（`False`）：** 鼠标进入/离开时背景色**瞬间切换**到目标颜色。这是无窗口（headless）/ 测试场景的默认行为，保证逐像素绘制结果与状态严格对应。
- **启用（`True`）且控件已分配窗口句柄（`HandleAllocated`）时：** `MouseEnter` 让背景色由普通态颜色平滑渐变到 `:hover` 态颜色，`MouseLeave` 反向渐变回普通态。
- 启用了动画但控件尚无窗口句柄时，仍按"瞬间切换"处理。

### 实现细节

- **驱动方式：** 启用动画后，控件按需创建一个内部 `TTimer`（`Interval = 16`，约 60fps），在 `OnTimer` 中按经过的毫秒数推进动画；动画走完（背景色抵达目标）后定时器自动停止。`TTyAnimator` 本身不持有时钟，只接受显式的毫秒步进，因此动画逻辑可在测试中确定性地驱动。
- **时长：** 一次完整的 普通↔悬停 渐变约 **120ms**（与 `TTyToggleSwitch` 旋钮滑动同节奏）。
- **缓动曲线：** `teEaseOutCubic`（先快后慢的减速曲线 `1 - (1 - t)³`）。
- **颜色插值：** 渲染时通过 `TyLerpColor` 在普通态背景色与 `:hover` 态背景色之间按缓动进度（`Eased`）混合。仅当两个状态的背景均为**纯色填充**（`tfkSolid`）时才进行渐变插值；渐变中间帧（`0 < Eased < 1`）会显式解析普通态与 `:hover` 态两套样式取色，使可见颜色完全由动画进度驱动，与 `FHover` 字段无关。`:focus`、`:active`、`:disabled` 等其它状态不参与此背景渐变。

```pascal
var Btn: TTyButton;
Btn := TTyButton.Create(Self);
Btn.Parent := Self;
Btn.Caption := '悬停我';
Btn.AnimationsEnabled := True;   // 启用悬停背景色渐变（需在有窗口句柄时生效）
```

---

## 8. 注意事项

- `Caption` 文字在渲染时水平和垂直均居中，文本超出宽度时会裁剪（`clipping = True`）。
- `StyleClass` 区分大小写，须与 `.tycss` 文件中的类名完全一致（如 `'primary'`、`'danger'`）。
- `Font` 属性中的 `PixelsPerInch` 用于 HiDPI 缩放；字体族（`FontName`）和大小（`FontSize`）优先从主题读取，`Font.Name`、`Font.Size` 作为备用。
- 控件不需要背景擦除（继承自 `TCustomControl`），由 `Paint` 完整重绘整个区域，不会出现闪烁。
- 同一窗体上所有未显式指定 `Controller` 的控件共享 `TyDefaultController`；若需要在同一窗体上使用多套主题，为不同控件分别设置不同的 `TTyStyleController` 实例即可。
