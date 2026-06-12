# TTyTitleBar — API 参考

## 1. 概述

`TTyTitleBar` 是 TyControls 自定义窗框方案的标题栏控件。它自绘背景并在左侧渲染窗口标题文本，右侧自动放置三个 `TTyCaptionButton` 子控件（最小化、最大化/还原、关闭），按钮随控件宽度动态布局。

`TTyTitleBar` 通常由 `TTyFormChrome` 自动创建和管理，但也可以独立放置在普通窗体上用于装饰性标题区域。

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

### public 只读属性（non-published）

| 属性 | 类型 | 说明 |
|------|------|------|
| `MinButton` | `TTyCaptionButton` | 最小化按钮（`Kind = cbkMin`），由构造函数创建。 |
| `MaxButton` | `TTyCaptionButton` | 最大化/还原按钮（`Kind = cbkMax`，最大化后切换为 `cbkRestore`）。 |
| `CloseButton` | `TTyCaptionButton` | 关闭按钮（`Kind = cbkClose`）。 |

这三个按钮的 `Parent` 设为 `TTyTitleBar` 自身，由 `LayoutButtons` 在构造和 `Resize` 时自动排布。

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
| `procedure LayoutButtons` | 从右到左依次放置 CloseButton、MaxButton、MinButton，每个宽度固定 46px，高度等于 `ClientHeight`。 |
| `procedure Resize` | 重写 `TCustomControl.Resize`，在控件尺寸变化时调用 `LayoutButtons`。 |
| `procedure RenderTo(...)` | 绘制背景框架和标题文本，文本左边距 8px，右边界止于按钮区左边缘（`ClientWidth - 3 * 46`）。 |

### 事件

`TTyTitleBar` 本身没有额外的 published 事件。标题栏的鼠标交互（拖动窗口、双击最大化）由 `TTyFormChrome` 通过注入 `OnMouseDown/OnMouseMove/OnMouseUp/OnDblClick` 实现。

各子按钮的 `OnClick` 也由 `TTyFormChrome` 在 `InstallChrome` 时绑定。

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

三个按钮从右到左排列，右边对齐控件右边缘：

```
[  标题文本  ...  ] [ Min 46px ] [ Max 46px ] [ Close 46px ]
```

文本区域：`Left + 8px` 到 `Right - 138px`（3 × 46）。

## 6. 代码示例

### 独立使用（不依赖 TTyFormChrome）

```pascal
uses tyControls.Form;

var
  TBar: TTyTitleBar;
begin
  TBar := TTyTitleBar.Create(Self);
  TBar.Parent := Self;
  TBar.Align := alTop;
  TBar.Caption := '我的窗口';
  // 手动绑定关闭按钮
  TBar.CloseButton.OnClick := @CloseButtonClick;
  // 隐藏最大化按钮
  TBar.MaxButton.Visible := False;
end;

procedure TForm1.CloseButtonClick(Sender: TObject);
begin
  Close;
end;
```

### 配合 TTyFormChrome（推荐方式）

```pascal
// 通常不需要直接访问 TitleBar，TTyFormChrome 负责全部管理。
// 若需要修改标题文本：
Chrome.TitleBar.Caption := Application.Title;
```

## 7. 注意事项

1. **由 TTyFormChrome 管理：** 在 `TTyFormChrome.Active := True` 的场景下，`TitleBar` 的 `Parent` 会被设置为宿主窗体并对齐 `alTop`；不要手动重新设置其 `Parent` 或 `Align`。
2. **按钮宽度固定：** `FButtonWidth` 在构造函数中硬编码为 46，目前没有 published 属性可以修改；如需自定义宽度，需子类化并重写 `LayoutButtons`。
3. **Caption 与窗体 Caption 不同步：** `TTyTitleBar.Caption` 与宿主 `TForm.Caption` 是独立属性，修改 `TForm.Caption` 不会自动更新标题栏，需手动赋值 `Chrome.TitleBar.Caption := Form.Caption`。
4. **子按钮 StyleClass 自动设置：** 三个 `TTyCaptionButton` 子控件的 `StyleClass` 由其 `Kind` 属性自动设置（`'min'`、`'max'`/`'restore'`、`'close'`），无需手动干预。
