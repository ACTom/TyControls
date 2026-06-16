# TTyTitleBar — API 参考

## 1. 概述

`TTyTitleBar` 是 TyControls 自绘窗框方案的标题栏控件。它自绘背景并在左侧渲染窗口标题文本，右侧自动放置三个 `TTyCaptionButton` 系统按钮（最小化、最大化/还原、关闭），按钮随控件宽度动态布局。

`TTyTitleBar` 现在是 **`TTyForm` 的子组件**——由 `TTyForm` 构造函数代码创建并停靠在顶部（`alTop`，"条带 0"），通过窗体的只读 `TitleBar` 属性访问。它**不再单独出现在 Lazarus 调色板**上（不可单独拖放）。你仍可在代码里独立创建一个 `TTyTitleBar` 用作装饰性标题区域，但常规用法是继承 `TTyForm` 后用 `TitleBar` 访问它。新窗口模型详见 [ttyform.md](ttyform.md)。

### 可定制内容区（Q2）

标题栏现在有一个真正的内容区：它覆写了 `AdjustClientRect`，把客户区收缩为**中间条带**——左侧留出标题/图标内缩、右侧留出**所有可见系统按钮之和**的内缩（`RightInset = VisibleButtonCount × ButtonWidth`，随 `ShowMinimize`/`ShowMaximize` 变化）。因此放在标题栏上的**对齐（aligned）子控件**会自动被约束在标题/图标与系统按钮之间的中间区域，便于放置 VS-Code 风格的按钮、下拉、菜单等。

> **范围说明：** 本周期支持运行期放置的、且**对齐**的标题栏子控件。自由放置（`alNone`）的标题栏子控件在设计期的完整 WYSIWYG 与窗体内容区有相同的 `alNone` 注意事项，**已推迟**（未来可能引入一个对称于内容面板的标题栏内层内容子面板）。

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Form` |
| typeKey | `TyTitleBar` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸 | 200 × 32（逻辑像素） |

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Caption` | `string` | `''` | 标题栏显示的文本。赋值时若值变化则触发 `Invalidate`。 |
| `Align` | `TAlign` | `alNone` | 对齐方式（继承自 LCL，现 published）。作为 `TTyForm` 子组件时由窗体设为 `alTop`。 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 锚定（继承自 LCL，现 published）。 |
| `ButtonWidth` | `Integer` | `46` | 每个系统按钮的宽度（逻辑像素）。写入时重排按钮并刷新右侧内缩（`RightInset`）。 |

### public 只读属性 / 方法（non-published）

| 成员 | 类型 | 说明 |
|------|------|------|
| `MinButton` | `TTyCaptionButton` | 最小化按钮（`Kind = cbkMin`），由构造函数创建。 |
| `MaxButton` | `TTyCaptionButton` | 最大化/还原按钮（`Kind = cbkMax`，最大化后切换为 `cbkRestore`）。 |
| `CloseButton` | `TTyCaptionButton` | 关闭按钮（`Kind = cbkClose`）。 |
| `RightInset` | `function: Integer` | 返回右侧系统按钮占用的总宽度 = `VisibleButtonCount × ButtonWidth`；`AdjustClientRect` 用它收缩客户区右边。 |

这三个按钮的 `Parent` 设为 `TTyTitleBar` 自身（**代码持有**），由 `LayoutButtons` 在构造和 `Resize` 时自动排布在右侧空槽。

### 继承的通用成员（来自 TTyCustomControl / TTyGraphicControl）

| 成员 | 说明 |
|------|------|
| `StyleClass` | CSS 变体类名 |
| `Controller` | 关联的样式控制器 |
| `Enabled` | 启用/禁用（影响状态渲染） |
| `Align` / `Anchors` | 布局属性 |

## 4. 事件与方法

### public 方法

#### `function GetStyleTypeKey: string`（override）

返回 `'TyTitleBar'`，用于主题样式查找。

### protected 方法（内部使用）

| 方法 | 说明 |
|------|------|
| `procedure LayoutButtons` | 从右到左依次放置可见的 CloseButton、MaxButton、MinButton，每个宽度为 `ButtonWidth`（默认 46px），高度等于 `ClientHeight`。隐藏的按钮（`ShowMinimize`/`ShowMaximize` = False）不占位。 |
| `procedure Resize` | 重写 `TCustomControl.Resize`，在控件尺寸变化时调用 `LayoutButtons`。 |
| `procedure AdjustClientRect(var ARect)` | 覆写：在 `inherited` 基础上左侧加标题/图标内缩、右侧减 `RightInset`（可见按钮总宽），返回中间内容条带，使对齐子控件自动约束于此。 |
| `procedure RenderTo(...)` | 绘制背景框架和标题文本，文本左边距 8px，右边界止于系统按钮区左边缘（`ClientWidth - RightInset`）。 |

### 事件

`TTyTitleBar` 本身没有额外的 published 事件，但其 published 的 `OnMouseDown/OnMouseMove/OnMouseUp/OnDblClick` 事件槽位**对用户开放**。

标题栏的窗口交互（拖动移动窗口、双击最大化）不再占用这些事件槽位——`TTyTitleBar` 改为**方法覆写**（`MouseDown/MouseMove/MouseUp/DblClick` 各方法先调 `inherited`，再委托给 `TTyForm` 拥有的 `TTyChromeEngine`）。因此你可以自由挂接 `TitleBar.OnMouseDown/...`，不会破坏拖动 / 最大化逻辑。

三个系统按钮的 `OnClick` 由 `TTyForm` 接线：最小化 → `WindowState := wsMinimized`；最大化/还原 → 引擎 `ToggleMaximize`；关闭 → `Close`。

## 5. 状态与主题

### 状态

TTyTitleBar 继承 `TTyCustomControl` 的状态机制，但实际使用中通常处于 `tysNormal` 状态（不需要 hover/focus 效果）：

| 状态常量 | 触发条件 |
|----------|----------|
| `tysNormal` | 正常 |
| `tysHover` | 鼠标悬停 |
| `tysActive` | 鼠标左键按下 |
| `tysFocused` | 键盘焦点（罕见） |
| `tysDisabled` | `Enabled = False` |

### light.tycss 内置规则

```css
TyTitleBar {
  background: darken(--surface, 6%);  /* 略深于窗体背景 */
  color: var(--on-surface);           /* #1F2937 */
  border-color: var(--border);        /* #D1D5DB */
  border-width: 1px;
  font-size: 10px;
  font-weight: 700;                   /* 标题加粗 */
}
```

内置主题没有定义 `:hover`、`:active`、`:focus` 或命名变体规则（标题栏通常不需要交互状态样式）。

### 按钮布局

可见的按钮从右到左排列，右边对齐控件右边缘（每个宽度 `ButtonWidth`，默认 46px）：

```
[  标题文本  ...  ] [ Min ] [ Max ] [ Close ]
```

文本区域：`Left + 8px` 到 `Right - RightInset`，其中 `RightInset = VisibleButtonCount × ButtonWidth`（三个全可见时为 138px = 3 × 46；隐藏最小化/最大化按钮会相应缩小内缩）。

## 6. 代码示例

### 配合 TTyForm（推荐方式）

```pascal
// 窗体继承自 TTyForm，标题栏通过只读 TitleBar 属性访问，由窗体负责创建与管理。
type
  TMainForm = class(TTyForm)
  end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  TitleBar.Caption := Application.Title;     // 同步标题
  TitleBar.ButtonWidth := 40;                // 可选：调整系统按钮宽度
  // 隐藏最大化按钮（即时重排按钮与内容区右侧内缩）：
  ShowMaximize := False;
end;
```

### 独立使用（装饰性标题区域）

```pascal
uses tyControls.Form;

var
  TBar: TTyTitleBar;
begin
  TBar := TTyTitleBar.Create(Self);
  TBar.Parent := Self;
  TBar.Align := alTop;
  TBar.Caption := '我的窗口';
  // 独立使用时需自行绑定系统按钮的 OnClick：
  TBar.CloseButton.OnClick := @CloseButtonClick;
end;

procedure TForm1.CloseButtonClick(Sender: TObject);
begin
  Close;
end;
```

## 7. 注意事项

1. **由 TTyForm 管理：** 作为 `TTyForm` 子组件时，`TitleBar` 的 `Parent` 是窗体、`Align = alTop`；不要手动重设其 `Parent`。通过窗体只读 `TitleBar` 属性访问它。
2. **按钮宽度可配：** `ButtonWidth` 现为 published 属性（默认 46）；写入后自动重排按钮并刷新右侧内缩，无需子类化。
3. **Caption 与窗体 Caption 不同步：** `TTyTitleBar.Caption` 与窗体 `Caption` 是独立属性，修改窗体 `Caption` 不会自动更新标题栏，需手动赋值 `TitleBar.Caption := Caption`。
4. **子按钮 StyleClass 自动设置：** 三个 `TTyCaptionButton` 子控件的 `StyleClass` 由其 `Kind` 属性自动设置（`'min'`、`'max'`/`'restore'`、`'close'`），无需手动干预。
5. **设计期皮肤未换肤：** 与全库一致，标题栏自绘**皮肤**在 Lazarus 设计器中以内置默认外观呈现（设计器无运行期主题），布局/几何则是 WYSIWYG 的。详见 [ttyform.md](ttyform.md) 第 6 节。
