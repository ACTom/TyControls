# TTyToolBar + TTyToolSeparator

## 1. 概述

`TTyToolBar` 是 TyControls 库中的水平工具条控件，继承自 `TTyCustomControl`。它是一个 `csAcceptsControls` 容器，把作为其子控件（`Parent := ToolBar`）的 `TTyButton` 停靠成一条工具按钮带；默认 `Align := alTop` 紧贴窗体顶部。同单元还提供 `TTyToolSeparator`——一条用于在按钮组之间分隔的竖线（见 [第 3.3 节](#33-ttytoolseparator分隔线)）。典型用途：文档编辑器 / 主窗口顶部的命令按钮栏。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ToolBar` |
| `GetStyleTypeKey` 返回值（`TTyToolBar`） | `'TyToolBar'` |
| `GetStyleTypeKey` 返回值（`TTyToolSeparator`） | `'TyToolSeparator'`（**自己的键**，不再借工具条的） |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸（`TTyToolBar`） | 300 × 30（逻辑像素） |
| 默认尺寸（`TTyToolSeparator`） | 8 × 24（宽固定 8；高走密度轴 `TyDensityHeight(…, 24)`，现代密度下更高） |

| typeKey | 画什么 |
|---|---|
| `TyToolBar` | 工具条：`background` 铺满整块（图片主题下叠在照片上），`border-color` + `border-width` 画**底部一条 hairline**（无四周边框） |
| `TyToolSeparator` | 分隔线：`background` 用来与工具条底色无缝衔接，`border-color` 是那条 1px 竖线的颜色 |

> **分隔线从"借用"变成了"自有"。** 它画的是工具条不画的墨迹——一条内缩的竖线；借 `TyToolBar` 时，
> 这条竖线**必然**与工具条自己的底部 hairline 同色，主题想做"有边框的工具条 + 更淡的内嵌分隔线"
> 这种经典搭配根本做不到。现在两者可分开配。
> 内建主题里 `TyToolBar, TyToolSeparator` 仍共写一条规则（观感不变），要单独调分隔线请写
> `TyToolSeparator` 选择器——**别去改 `TyToolBar`**，那会连整条工具条的底色和底线一起改。

```pascal
uses tyControls.ToolBar, tyControls.Button;
```

---

## 3. 属性表

### 3.1 TTyToolBar 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `ButtonHeight` | `Integer` | 跟随密度轴 | 所有子按钮的统一逻辑高度；排布时每个子控件的高度被强制设为此值（`AlignControls` 中 `SetBounds(..., bh)`）。**未显式赋值时跟随主题的 `--control-height`**（经典 24 / 现代 38），一经写入即固定并写进 `.lfm`。改值触发 `Relayout`。 |
| `ButtonSpacing` | `Integer` | `2` | 相邻工具项之间的水平间距（换行时也用作行间距）。改值触发 `Relayout`。 |
| `Indent` | `Integer` | `4` | 首项 / 顶边留白（左、上内缩）。改值触发 `Relayout`。 |
| `Wrapable` | `Boolean` | `True` | 为 `True` 时，一行放不下的工具项自动折到下一行；`Align in [alTop, alBottom]` 时工具条随行数自动增高。改值触发 `Relayout`。 |
| `ShowCaptions` | `Boolean` | `False` | **（保留，暂未接线）** 复用 `TTyButton` 的模型下每个子按钮各自持有 caption/image，此属性当前**无任何效果**，仅为将来 LCL 对齐保留。改值触发 `Relayout`。 |
| `Flat` | `Boolean` | `True` | 为 `True` 时，工具条把每个子 `TTyButton` 的 `StyleClass` 统一改为 `'ghost'`（平面外观）；为 `False` 时改为 `''`。改值触发 `Relayout`。 |
| `Images` | `TImageList` | `nil` | **（存储但暂未接线）** 图像列表；当前不向子按钮传播（预留 hook）。`Notification` 中随 `opRemove` 置 `nil`。改值触发 `Relayout`。 |
| `Align` | `TAlign` | `alTop` | 停靠方式（**默认 `alTop`**，与原生工具条一致）。 |
| `Anchors` | `TAnchors` | — | 锚点布局（继承）。 |

### 3.2 继承的通用成员

`TTyToolBar` 与 `TTyToolSeparator` 均继承自 `TTyCustomControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分。 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器。 |

> `TTyToolBar` 未跟踪 `FHover` / `FPressed` 等交互状态字段——它是纯容器，仅绘制背景与底部发丝线，本身不参与 `:hover` / `:active`。私有布局字段（`FButtonHeight` / `FButtonSpacing` / `FIndent` / `FWrapable` / `FShowCaptions` / `FFlat` / `FImages` / `FInLayout`）由上表 published 属性驱动，`FInLayout` 是 `AlignControls` 的重入守卫。

### 3.3 TTyToolSeparator（分隔线）

`TTyToolSeparator` 是一条平凡的竖线控件，把它 `Parent := ToolBar` 即可作为普通工具项参与排布（占据一个 8px 宽的格位，在中央绘制 1px 竖线）。它自身**没有专有 published 属性**，仅 published 继承来的三项：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Align` | `TAlign` | `alNone` | 停靠方式（继承）。 |
| `StyleClass` | `string` | `''` | CSS 类名。 |
| `Controller` | `TTyStyleController` | `nil` | 样式控制器。 |

竖线颜色取 `TyToolSeparator` 样式的 `BorderColor`，竖线上下各内缩 3 逻辑像素（`P.Scale(3)`）；同一样式的 `background` 用于铺底，好让它与所在工具条无缝衔接。

---

## 4. 事件

`TTyToolBar` 与 `TTyToolSeparator` **均无自有专有事件**——工具条只 published 布局属性，不发出 `OnChange` 之类的通知。用户交互（点击）发生在**子按钮**上，请挂接各个子 `TTyButton` 的 `OnClick`（见 [第 6 节](#6-代码示例)）。

> 两个控件都暴露**基线事件集**（Tier A 鼠标 / 通用事件 + Tier B 键盘 / 焦点事件，因二者均为 `TTyCustomControl`）。完整清单见 [../events.md](../events.md)。工具条自身通常无需挂接这些事件；命令响应走子按钮的 `OnClick`。

---

## 5. 状态与主题

### 支持的伪类状态

`TTyToolBar` 未重写 `CurrentStates`，且作为容器不跟踪 hover/pressed/focus，实际渲染时始终使用 `CurrentStyle`（`tysNormal` 基础样式）。因此内置主题**未为工具条定义任何伪类规则**（无 `:hover` / `:focus` / `:active` / `:disabled`），其外观仅由基础规则决定。

### light.tycss 内置规则

```css
/* 两个键共写一条规则：解析值完全相同，但现在可以各写各的 */
TyToolBar, TyToolSeparator {
  background: var(--surface-chrome);
  border-color: var(--border);
  border-width: var(--input-border-width);
}
```

### 渲染细节

- **工具条背景：** 先铺一层 `FillSharpBackdrop`（图片主题下透出照片，纯色主题为 no-op），再在存在 `background` 令牌时用 `S.Background` 直接填充整块——alpha 背景会叠加在照片之上（毛玻璃效果），与 `TTyPanel` 一致。
- **底部发丝线：** 存在 `border-color` 令牌时，在工具条底部画一条高度为 `Scale(BorderWidth)`（最小 1px）的水平线（`Rect(0, H-bw, W, H)`）；工具条**只有底边一条 hairline**，无四周边框。
- **分隔线：** `TTyToolSeparator` 同样先铺 backdrop、再（若有）填自身样式的 `background` 与工具条无缝衔接，最后在中央画一条自身 `BorderColor` 的 1px 竖线（上下内缩 `Scale(3)`）。
- **子按钮 ghost 变体：** 当 `Flat = True`（默认）时，工具条在排布阶段把每个子 `TTyButton.StyleClass` 覆写为 `'ghost'`，使按钮呈平面外观；`Flat = False` 时覆写为 `''`（常规按钮）。**工具条完全接管子按钮的 ghost/非 ghost StyleClass**，不保留子按钮加入前原有的 `StyleClass`（见源码注释）。

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.ToolBar, tyControls.Button;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

var
  ToolBar: TTyToolBar;
  Btn: TTyButton;
  Sep: TTyToolSeparator;

// 顶部工具条（默认 Align = alTop）
ToolBar := TTyToolBar.Create(Self);
ToolBar.Parent := Self;
ToolBar.Flat := True;          // 子按钮统一改为 ghost 平面变体（默认即 True）
ToolBar.Wrapable := True;      // 宽度不足自动换行，工具条随行数增高
ToolBar.ButtonHeight := 28;    // 统一按钮高度
ToolBar.ButtonSpacing := 4;    // 相邻按钮间距
ToolBar.Indent := 6;           // 首按钮 / 顶边留白

// 添加工具按钮：Parent = 工具条 → 由工具条负责排布与 ghost 变体
Btn := TTyButton.Create(Self);
Btn.Parent := ToolBar;         // 关键：父控件是工具条，而非窗体
Btn.Width := 72;               // 只需设宽度，高度由 ButtonHeight 统一接管
Btn.Caption := '新建';
Btn.OnClick := @ToolClicked;   // 命令响应挂在子按钮上

// 在按钮组之间插入分隔竖线
Sep := TTyToolSeparator.Create(Self);
Sep.Parent := ToolBar;         // 作为普通工具项参与排布

// 事件处理器
procedure TMainForm.ToolClicked(Sender: TObject);
begin
  FStatus.Caption := Format('已触发工具：%s', [(Sender as TTyButton).Caption]);
end;
```

---

## 7. 注意事项

- **子控件即工具项：** 把 `TTyButton`（及 `TTyToolSeparator`）的 `Parent` 设为工具条即完成停靠；工具条是 `csAcceptsControls` 容器，在 `AlignControls` 里按子控件顺序（仅可见者）逐个排布。子按钮**只需设 `Width`**，高度被 `ButtonHeight` 统一覆盖。
- **Flat 覆写 StyleClass：** 工具条完全接管子 `TTyButton` 的 `StyleClass`（`Flat=True → 'ghost'`，否则 `''`），**不保留**子按钮加入前的 `StyleClass`。若需自定义按钮变体，此处会被覆盖。
- **命令响应走子按钮：** 工具条自身无 `OnClick` 语义的专有事件；请挂接各子按钮的 `OnClick`（Tier A 基线事件）。
- **Wrapable 自动增高：** 当 `Align in [alTop, alBottom]` 且 `Wrapable=True` 时，一行放不下的工具项换行，工具条高度按 `Indent*2 + rows*ButtonHeight + (rows-1)*ButtonSpacing` 自动调整——不要在代码里硬设一个与之冲突的 `Height`。
- **重入守卫：** `AlignControls` 末尾对 `Height` 的赋值会再次触发 `AlignControls`，`FInLayout` 守卫防止无限递归。
- **ShowCaptions / Images 暂未接线：** 二者已 published 但**当前无效果**——复用 `TTyButton` 的模型下每个子按钮自带 caption/image。它们仅为将来 LCL 对齐保留，可安全忽略。
- **无四周边框：** 主题的 `border-color` / `border-width` 只画工具条**底部一条 hairline**，不绘制四周边框；工具条不参与任何伪类状态。
- **分隔线有独立 typeKey：** `TTyToolSeparator.GetStyleTypeKey` 返回 `'TyToolSeparator'`。内建主题让它与 `TyToolBar` 共写一条规则，所以默认观感不变；但要调竖线的颜色/底色，请写 `TyToolSeparator` 选择器，改 `TyToolBar` 会顺带改掉整条工具条。
- **DFM 序列化：** `Align` 声明了 `default alTop`，`ButtonHeight`/`ButtonSpacing`/`Indent`/`Wrapable`/`ShowCaptions`/`Flat` 均声明了默认值，等于默认值时不写入 `.lfm`/`.dfm`。
