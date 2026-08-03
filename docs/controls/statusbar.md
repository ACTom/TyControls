# TTyStatusBar

## 1. 概述

`TTyStatusBar` 是 TyControls 库中的主题化状态栏控件，继承自 `TTyCustomControl`。它是一条通常停靠在窗体底部的多面板信息条：默认 `Align = alBottom`，横向排布若干 `TTyStatusPanel` 面板（各有自己的文本、宽度、对齐方式），右下角可绘制一个尺寸手柄（SizeGrip）。也可切换到 `SimplePanel` 单一整条文本模式。典型用途：显示"就绪"提示、行列号、点击计数、右侧品牌 / 时间等状态信息。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.StatusBar` |
| `GetStyleTypeKey` 返回值 | `'TyStatusBar'` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸 | 200 × 22（逻辑像素，构造时设置；实际使用中一般由 `alBottom` 停靠拉伸宽度） |

在 `.tycss` 文件中，该控件对应的选择器前缀为 `TyStatusBar`。

```pascal
uses tyControls.StatusBar;
```

> 面板项类型 `TTyStatusPanel`、集合类型 `TTyStatusPanels`（`TOwnedCollection` 子类）也定义在同一单元内。

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Panels` | `TTyStatusPanels` | `[]`（空集合） | 面板集合；写入时对内部集合执行 `Assign`。每个面板是一个 `TTyStatusPanel`（见下表）。任何面板属性变化都会重绘状态栏。 |
| `SimplePanel` | `Boolean` | `False` | 为 `True` 时切换到单一整条文本模式：忽略 `Panels`，改为绘制 `SimpleText`（左对齐、垂直居中）。 |
| `SimpleText` | `string` | `''` | `SimplePanel = True` 时显示的整条文本。写入时仅当当前处于 `SimplePanel` 模式才触发重绘。 |
| `SizeGrip` | `Boolean` | `True` | 为 `True` 时在控件右下角绘制 3 个对角小点组成的尺寸手柄（`default True`）。 |
| `Align` | `TAlign` | `alBottom` | 停靠方式，**默认已重声明为 `alBottom`**（`property Align default alBottom;`），构造函数也显式设为 `alBottom`。 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点。 |

### `TTyStatusPanel`（`Panels` 集合项）的 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Text` | `string` | `''` | 该面板显示的文本。 |
| `Width` | `Integer` | `50` | 面板逻辑宽度（`default 50`）。**`Width <= 0` 的面板为"填充面板"**：占据其余固定宽度面板之外的全部剩余空间；若有多个 `<= 0` 面板，只有**第一个**吃掉剩余空间，其后的 `<= 0` 面板宽度为 0。**最后一个面板的 `Width` 只是下限**：它总是延伸到右侧内边距处（见 §7）。 |
| `Alignment` | `TAlignment` | `taLeftJustify` | 面板内文本的水平对齐（`taLeftJustify` / `taCenter` / `taRightJustify`，`default taLeftJustify`）。垂直方向固定居中。 |

> `TTyStatusPanels` 额外提供 `function Add: TTyStatusPanel;` 与默认索引器 `Items[AIndex]: TTyStatusPanel`（即 `Panels[i]`）以便按类型访问面板项。

### 继承的通用成员

TTyStatusBar 继承自 `TTyCustomControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器 |

> **无独立的交互状态跟踪字段：** `TTyStatusBar` 未声明自己的 `FHover` / `FPressed` 等字段，也**未重写** `CurrentStates`；绘制仅读取 `CurrentStyle`（普通态样式）。状态栏是信息展示控件，不响应悬停 / 焦点等交互态视觉变化。

---

## 4. 事件

`TTyStatusBar` **未声明任何自有专有事件**（无 `OnChange` / `OnPanelClick` 等）。

> `TTyStatusBar` 暴露**基线事件集**（Tier A 鼠标 / 通用事件 + Tier B 键盘 / 焦点事件，因其为可聚焦的 `TTyCustomControl`）。若要响应面板点击，可挂接基线 `OnMouseDown` / `OnClick`，并用公开方法 `PanelAtPos(X, Y): Integer` 把坐标映射到面板索引（`SimplePanel` 模式或点击空白处返回 `-1`）。完整基线清单见 [../events.md](../events.md)。

---

## 5. 状态与主题

### 支持的伪类状态

`TTyStatusBar` 绘制时只解析 `CurrentStyle`（普通态），**不区分** `:hover` / `:focus` / `:active` 的差异化外观；内置主题也未为其定义任何伪类规则。`:disabled`（`Enabled = False`）等仍由基类的通用状态机计算，但状态栏本身无交互态视觉切换。

### light.tycss 内置规则摘要

```css
TyStatusBar {
  background: var(--surface-chrome);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: var(--input-border-width);
  font-size: var(--font-size-base);
  font-weight: var(--font-weight-normal);
}
```

内置主题未为 `TyStatusBar` 定义命名变体（`.class`）或伪类规则；可通过 `StyleClass` 添加自定义变体。

**渲染细节：**

- **背景与顶部边线：** 先铺一层 `FillSharpBackdrop`（让 alpha 背景可透出窗体照片，形成玻璃感；纯色 / 非图片主题无影响），再用 `background` 令牌整条填充，然后在**顶部**画一条 `border-color` 的 1px 细线（`border-width` 缩放，最小 1px）——是"状态栏顶线"外观，**不是完整边框**。
- **多面板模式：** 面板矩形由 `TyStatusPanelRects` 依据各面板 `Width` 计算（左右各留 6 逻辑像素内边距 `CStatusBarPadX`）；**最后一个面板的右边界一律拉到 `总宽 - 内边距`**（见 §7）。第一个之后的每个面板左侧画一条 1px 分隔线（仅当主题存在 `border-color` 时；上下各内缩 3 逻辑像素）。面板文字用 `color`（`TextColor`）绘制，水平按各面板 `Alignment`、垂直居中，左右各再内缩 2 逻辑像素。
- **SimplePanel 模式：** 忽略面板，直接在 `[padX, W-padX]` 区域绘制 `SimpleText`，左对齐、垂直居中。
- **SizeGrip：** `SizeGrip = True` 时在右下角用 `TextColor` 画 3 个对角排列的 2×2 小点（间距 4 逻辑像素）。

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.StatusBar;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

var
  Bar: TTyStatusBar;
  P: TTyStatusPanel;
begin
  Bar := TTyStatusBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alBottom;      // 默认已是 alBottom
  Bar.Height := 24;
  Bar.SizeGrip := True;       // 右下角尺寸手柄

  // 面板 0：状态（填充面板，Width <= 0 撑满剩余空间）
  P := Bar.Panels.Add;
  P.Text := '就绪';
  P.Width := 0;
  P.Alignment := taLeftJustify;

  // 面板 1：点击计数（居中，固定宽）
  P := Bar.Panels.Add;
  P.Text := '点击：0';
  P.Width := 110;
  P.Alignment := taCenter;

  // 面板 2：右对齐品牌（固定宽）
  P := Bar.Panels.Add;
  P.Text := 'TyControls';
  P.Width := 110;
  P.Alignment := taRightJustify;
end;

// 运行时更新某个面板文本（自动重绘）
Bar.Panels[1].Text := '点击：3';

// 切换到单一整条文本模式
Bar.SimplePanel := True;
Bar.SimpleText := '正在保存…';
```

---

## 7. 注意事项

- **默认停靠底部：** `Align` 默认值即 `alBottom`（既在 published 声明处 `default alBottom`，构造函数也显式赋值），因此值为 `alBottom` 时不写入 `.lfm`/`.dfm`。放到窗体上默认贴底，无需手动设置。
- **填充面板规则：** `Width <= 0` 的面板吃掉剩余空间，但**只有第一个** `<= 0` 面板生效，其后的 `<= 0` 面板宽度为 0（会退化成零宽面板）。若剩余空间为负则夹紧到 0。
- **最后一个面板顶到右边缘：** 无论给它设了多宽，最后一个面板的右边界都会拉到 `总宽 - 内边距`（与原生状态栏一致，win32 把末个面板的 right 设为 -1）。否则各面板宽度之和凑不满客户区时，末个面板与边框之间会露出一条父窗体底色的空带。
- **SimplePanel 屏蔽面板：** `SimplePanel = True` 时完全忽略 `Panels` 集合，只画 `SimpleText`；此时 `PanelAtPos` 恒返回 `-1`。切回多面板模式时面板内容仍在（未被清空）。
- **面板变更即重绘：** `TTyStatusPanel` 的 `Text`/`Width`/`Alignment` setter 调用 `Changed(False)`，经 `TTyStatusPanels.Update` 触发宿主 `Invalidate`——运行时改面板文本会自动刷新，无需手动 `Invalidate`。
- **无面板点击事件：** 控件没有内建的面板点击事件；需要时用基线 `OnMouseDown`/`OnClick` 配合 `PanelAtPos(X, Y)` 自行判定被点面板索引。
- **SizeGrip 仅为视觉提示：** `SizeGrip` 绘制的是 3 个装饰性小点，表示可拖拽调整窗口大小的位置提示；它本身只是绘制，`default True` 故值为 `True` 时不写入序列化。
- **状态栏顶线而非边框：** 主题的 `border-color`/`border-width` 只作用于**顶部一条细线**，不绘制四周完整边框；面板之间的分隔线同样依赖 `border-color` 令牌存在才绘制。
- **视觉全部由主题驱动：** 背景、文字颜色、字号、字重均取自 `.tycss` 令牌（见上表），不在控件代码中写死；控件也不暴露 `Color`/`Font`（族/字号）等与主题冲突的原生属性。
