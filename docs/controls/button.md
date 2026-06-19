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
| `Default` | `Boolean` | `False` | **（API parity 新增）** 为 `True` 时在宿主窗体上按 Enter 触发本按钮的 `Click`（注册到窗体 `DefaultControl`）；流式载入后在 `Loaded` 中重新注册（设置时 Parent 尚未就绪的情形）。 |
| `Cancel` | `Boolean` | `False` | **（API parity 新增）** 为 `True` 时在宿主窗体上按 Esc 触发本按钮的 `Click`（注册到窗体 `CancelControl`）；同样在 `Loaded` 中重新注册。 |
| `ModalResult` | `TModalResult` | `mrNone` | **（API parity 新增）** 非 `mrNone` 时，`Click` 在调用 `inherited Click`（即触发 `OnClick`）**之前**先把宿主窗体的 `ModalResult` 设为本值——遵循原生 `TButton` 语义，使 `OnClick` 处理器可通过 `Form.ModalResult := mrNone` 否决关闭。 |
| `AnimationsEnabled` | `Boolean` | `True` | **（API parity 新增 published）** 控制悬停背景淡入动画（约 120 ms，EaseOutCubic）；详见第 7 节。 |
| `Down` | `Boolean` | `False` | **（v1.11 新增）** 常驻**选中态**：为 `True` 时 `CurrentStates` 注入 `tysSelected`，触发主题 `:selected` 规则（如 `TyButton.ghost:selected`）。`Enabled = False` 时不生效（disabled 优先）。互斥分组由应用在 `OnClick` 里自行切换各按钮的 `Down`（不内建 `GroupIndex`）。详见第 9 节。 |
| `ShowBadge` | `Boolean` | `False` | **（v1.11 新增）** 角标总开关。详见第 9 节。 |
| `BadgeValue` | `Integer` | `0` | **（v1.11 新增）** 角标数值；仅数字，`>99` 显示 `99+`。 |
| `BadgePosition` | `TTyBadgePosition` | `bpBottomRight` | **（v1.11 新增）** 角标所在角：`bpTopLeft / bpTopRight / bpBottomLeft / bpBottomRight`。窗口控件不能越界,角标内嵌于按钮内并稍作内缩。 |
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
| `OnBadgeDisplay` | `TTyBadgeDisplayEvent` | **（v1.11 新增）** 角标绘制前回调：`procedure(Sender; AValue: Integer; var AText: string; var AVisible: Boolean)`。默认显示含 `0`，可在此改写 `AText` 或置 `AVisible := False` 自定义隐藏策略（如 `<3` 不显示）。详见第 9 节。 |

> **`ModalResult` 与 `OnClick` 的次序：** 当 `ModalResult <> mrNone` 时，`Click` 先把宿主窗体 `ModalResult` 设为本值，**再**调用 `inherited Click`（触发 `OnClick`）。因此 `OnClick` 处理器可在事件中读取/改写 `Form.ModalResult`（如置 `mrNone` 否决关闭）。
>
> **基线事件集：** 除 `OnClick` 外，TTyButton 还暴露全部**基线事件**（Tier A + Tier B，因其为可聚焦的 `TTyCustomControl`），见 [../events.md](../events.md)。

---

## 5. 状态与主题

### 支持的伪类状态

| 伪类 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停 |
| `:focus` | 获得键盘焦点 |
| `:active` | 鼠标左键按下 |
| `:disabled` | `Enabled = False` |
| `:selected`（别名 `:checked`） | `Down = True`（且 `Enabled`）；常驻选中态，详见第 9 节 |

### light.tycss 内置规则摘要

```css
TyButton {
  background: var(--surface);        /* #FFFFFF */
  color: var(--on-surface);          /* #1F2937 */
  border-color: var(--border);       /* #D1D5DB */
  border-width: 1px;
  border-radius: var(--radius);      /* 6px */
  padding: 6px;
  font-size: 9px;
  font-weight: 400;
}
TyButton:hover    { background: darken(--surface, 4%); border-color: darken(--border, 10%); }  /* 悬停背景变深 + 描边加深（Batch ④） */
TyButton:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }      /* #3B82F6 + 焦点环 */
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
| `AnimationsEnabled` | `Boolean` | `True` | 是否启用背景色悬停渐变动画。**public 属性，不 published**（不写入 `.lfm`），需在代码中设置。 |

> 这是唯一的动画开关。**没有**单独的时长 / 缓动曲线属性可供配置——时长与缓动在控件内部固定（见下）。

> **默认值变更（batch⑤+⑥）：** `AnimationsEnabled` 的默认值由早前的 `False` 改为 **`True`**——开箱即有悬停渐变手感。需要完全静态的外观（例如自定义测试或追求极简）时在代码中显式置 `False` 即可。注意无窗口（headless）下无论开关与否都会**瞬间吸附到终态**（见「行为」），因此既有的逐像素测试不受默认值翻转影响。

### 行为

- **启用（`True`，默认）且控件已分配窗口句柄（`HandleAllocated`）时：** `MouseEnter` 让背景色由普通态颜色平滑渐变到 `:hover` 态颜色，`MouseLeave` 反向渐变回普通态。
- **关闭（`False`）：** 鼠标进入/离开时背景色**瞬间切换**到目标颜色。逐像素绘制结果与状态严格对应。
- 控件尚无窗口句柄（headless / 设计器）时，无论开关如何都按"瞬间切换"处理（**headless-snap**），保证测试确定性。

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
// AnimationsEnabled 默认即为 True（悬停背景色渐变，需在有窗口句柄时生效）；
// 如需静态外观可显式关闭：
// Btn.AnimationsEnabled := False;
```

---

## 8. 注意事项

- `Caption` 文字在渲染时水平和垂直均居中，文本超出宽度时会裁剪（`clipping = True`）。
- `StyleClass` 区分大小写，须与 `.tycss` 文件中的类名完全一致（如 `'primary'`、`'danger'`）。
- `Font` 属性中的 `PixelsPerInch` 用于 HiDPI 缩放；字体族（`FontName`）和大小（`FontSize`）优先从主题读取，`Font.Name`、`Font.Size` 作为备用。
- 控件不需要背景擦除（继承自 `TCustomControl`），由 `Paint` 完整重绘整个区域，不会出现闪烁。
- 同一窗体上所有未显式指定 `Controller` 的控件共享 `TyDefaultController`；若需要在同一窗体上使用多套主题，为不同控件分别设置不同的 `TTyStyleController` 实例即可。

---

## 9. Ghost 变体 + 选中态 + 角标 (v1.11)

### 9.1 Ghost（透明）变体与选中态

`StyleClass := 'ghost'` 让按钮平时**透明无边框**（类似 VS Code 活动栏/工具栏按钮），仅在 `:hover` / `:active` / **选中** 时显示底色与边框。

- **选中是常驻状态**：`Button.Down := True;` 触发主题 `:selected` 规则（`TyButton.ghost:selected`），区别于瞬时的 hover/active。`Down` 为 `False` 时清除。`Enabled = False` 时 `Down` 不生效（disabled 优先）。
- **互斥分组**（同组仅一个选中，如活动栏）由应用在 `OnClick` 里自行切换各按钮的 `Down`；本控件不内建 `GroupIndex`。
- ghost 的 base 用 `alpha(<令牌>, 0)`（透明但仍是纯色），使既有的悬停背景淡入动画（alpha `0→255`）继续生效；透明边框保留 `border-width`，避免 hover 时尺寸跳动。所有内置主题均提供 `TyButton.ghost`。

### 9.2 角标（badge）

按钮某个角叠加一个**数字角标**（如未读数）。仅数字，`>99` 显示 `99+`。

| 成员 | 说明 |
|------|------|
| `ShowBadge: Boolean` | 总开关；`False` 时完全不绘制、不调用事件 |
| `BadgeValue: Integer` | 数值 |
| `BadgePosition: TTyBadgePosition` | 所在角（默认 `bpBottomRight`）；窗口控件不能越界,角标内嵌于按钮内并稍作内缩 |
| `OnBadgeDisplay` | 显示前回调，见下 |

**显示规则**：`ShowBadge = False` → 不画。`ShowBadge = True` → 先算默认文本（`>99` 截断为 `99+`，否则 `IntToStr(BadgeValue)`，**默认显示含 `0`**）与 `AVisible := True`，再调用 `OnBadgeDisplay`（若挂接）让用户改写 `AText` / 置 `AVisible := False`；最终 `AVisible and (AText <> '')` 才绘制。

样式由独立 typeKey **`TyBadge`** 主题化（默认 `var(--accent)` 蓝底胶囊，单字符近正圆）：

```css
TyBadge {
  background: var(--accent);
  color: var(--on-accent);
  border-radius: var(--radius-round);
  font-size: var(--font-size-base);
  font-weight: var(--font-weight-bold);
  padding: 0px 4px;
}
```

### 9.3 代码示例

```pascal
// Ghost + 选中(工具栏按钮)
GhostBtn := TTyButton.Create(Self);
GhostBtn.Parent := Self;
GhostBtn.StyleClass := 'ghost';
GhostBtn.Down := True;            // 常驻选中
// 点击切换选中:
//   procedure TForm1.GhostClick(Sender: TObject);
//   begin (Sender as TTyButton).Down := not (Sender as TTyButton).Down; end;

// 角标
BadgeBtn := TTyButton.Create(Self);
BadgeBtn.Parent := Self;
BadgeBtn.Caption := '消息';
BadgeBtn.ShowBadge := True;
BadgeBtn.BadgeValue := 128;       // 显示 "99+"
BadgeBtn.BadgePosition := bpBottomRight;
// 仅在 >=3 时显示:
//   procedure TForm1.OnBadge(Sender: TObject; AValue: Integer; var AText: string; var AVisible: Boolean);
//   begin AVisible := AValue >= 3; end;
//   BadgeBtn.OnBadgeDisplay := @OnBadge;
```
