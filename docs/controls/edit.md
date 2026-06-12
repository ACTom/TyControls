# TTyEdit

## 1. 概述

TTyEdit 是 TyControls 库中的主题化单行文本输入控件，继承自 `TTyCustomControl`。典型用途：用户输入姓名、搜索关键词、数字等单行文本，支持完整的文本编辑能力：UTF-8 安全退格与删除、光标移动、选区（拖选/Shift+方向键）、全选、剪贴板操作（Ctrl/Cmd+A/C/X/V）、鼠标点击定位与双击全选。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Edit` |
| `GetStyleTypeKey` 返回值 | `'TyEdit'` |

在 `.tycss` 文件中，该控件对应的选择器前缀为 `TyEdit`。

```pascal
uses tyControls.Edit;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Text` | `string` | `''` | 输入框当前内容；赋值会触发重绘，但**不**触发 `OnChange` 事件（见注意事项）。赋值时光标移动到文本末尾，选区收起。 |
| `Enabled` | `Boolean` | `True` | 为 `False` 时触发 `:disabled`，控件不响应键盘/鼠标输入 |
| `Font` | `TFont` | 系统默认 | 传递 PPI 给渲染器；字体族与大小优先由主题控制 |
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点 |

### public 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `CaretPos` | `Integer`（读写） | 光标的码点索引，范围 `[0, UTF8Length(Text)]`。写入时收起选区（`FSelAnchor := FCaretPos`）并重绘。 |

### public 只读方法（选区 API）

| 方法 | 说明 |
|------|------|
| `function SelStart: Integer` | 选区起始码点索引（`FCaret` 与 `FSelAnchor` 中较小者）；无选区时等于光标位置。 |
| `function SelLength: Integer` | 选区长度（码点数，无选区时为 0）。 |
| `function SelText: string` | 选区内容的 UTF-8 字符串；无选区时为空串。 |
| `function HasSelection: Boolean` | 当前是否有非空选区（`FCaret <> FSelAnchor`）。 |
| `procedure SelectAll` | 全选：将选区锚点设为 0，光标移到末尾。 |
| `procedure ClearSelection` | 收起选区：将 `FSelAnchor := FCaret`。 |

### public 剪贴板方法

| 方法 | 说明 |
|------|------|
| `procedure CopyToClipboard` | 将选区内容写入剪贴板；无选区时无操作。 |
| `procedure CutToClipboard` | 将选区内容写入剪贴板并删除选区；无选区时无操作。 |
| `procedure PasteFromClipboard` | 读取剪贴板文本，**剥离所有 CR（`#13`）和 LF（`#10`）字符**（单行控件），将过滤后的内容插入当前光标位置；若有选区则先删除。剪贴板为空时完全无操作；若剪贴板非空但过滤后为空（纯换行内容）则仅删除选区。 |

### 继承的通用成员

TTyEdit 继承自 `TTyCustomControl`（`tyControls.Base`），与其他 TyControls 控件共享以下 published 属性：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器 |

**状态跟踪字段（protected，不 published）：**

| 字段/状态 | 类型 | 说明 |
|-----------|------|------|
| `FHover` | `Boolean` | 鼠标悬停时为 `True`，触发 `:hover` 主题状态 |
| `FPressed` | `Boolean` | 鼠标左键按下时为 `True`，触发 `:active` 主题状态 |
| `Focused` | `Boolean` | 获得键盘焦点时触发 `:focus` 主题状态，并显示光标 |
| `Enabled = False` | — | 触发 `:disabled` 主题状态 |

**构造时自动设置 `TabStop := True`**，确保控件可以被 Tab 键导航。

---

## 4. 事件与键盘

### 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnClick` | `TNotifyEvent` | 鼠标点击控件时 |

> **注意：** 当前版本没有 `OnChange` 事件。文本通过按键实时变化，但没有回调通知。若需要监听内容变化，可继承 `TTyEdit` 并重写 `UTF8KeyPress` / `KeyDown`，或在用户完成输入后主动读取 `Text` 属性。

### 键盘表

| 按键 | 无修饰键 | +Shift | +Ctrl 或 +Cmd（Meta） |
|------|----------|--------|----------------------|
| `←` | 移动光标左移一码点；若有选区则折叠到选区左端 | 向左扩展/收缩选区 | 不拦截（透传给系统/父控件） |
| `→` | 移动光标右移一码点；若有选区则折叠到选区右端 | 向右扩展/收缩选区 | 不拦截（透传） |
| `Home` | 光标移到文本开头，收起选区 | 扩展选区到文本开头 | 不拦截（透传） |
| `End` | 光标移到文本末尾，收起选区 | 扩展选区到文本末尾 | 不拦截（透传） |
| `Backspace` | 删除光标前一码点；有选区则删除选区 | — | — |
| `Delete` | 删除光标后一码点；有选区则删除选区 | — | — |
| `A` | — | — | 全选（`SelectAll`） |
| `C` | — | — | 复制选区到剪贴板 |
| `X` | — | — | 剪切选区到剪贴板 |
| `V` | — | — | 粘贴（剥离换行后插入） |
| 其他可打印字符 | 插入字符（经 `UTF8KeyPress`） | — | — |

> **修饰键+方向键说明：** `Ctrl/Alt/Meta`（无 Shift）与方向键组合时，按键事件**不被消费**（`Key` 不置 0），由父窗口/系统处理（通常用于词级跳转）。带 Shift 的修饰键+方向键仍会触发扩展选区逻辑。

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
TyEdit {
  background: var(--surface);        /* #FFFFFF */
  color: var(--on-surface);          /* #1F2937 */
  border-color: var(--border);       /* #D1D5DB */
  border-width: 1px;
  border-radius: var(--radius);      /* 6px */
  padding: 4px;
  font-size: 10px;
}
TyEdit:hover    { border-color: darken(--border, 10%); }
TyEdit:focus    { border-color: var(--accent); }   /* #3B82F6，蓝色高亮边框 */
TyEdit:disabled { opacity: 0.5; }
```

聚焦时除边框变蓝外，渲染器还会在光标位置绘制一条 1px 宽的竖线（颜色与 `TextColor` 相同）。有选区时，选区底色为 `:focus` 的 `border-color`（即 `var(--accent)`）加 35% alpha（约 `#59` 十六进制 alpha），文字在其上正常绘制。

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.Edit, tyControls.Button, tyControls.TyLabel;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

// 基础输入框
var Edit: TTyEdit;
Edit := TTyEdit.Create(Self);
Edit.Parent := Self;
Edit.SetBounds(24, 48, 300, 32);
Edit.Text := '初始内容';

// 禁用态
var EditDisabled: TTyEdit;
EditDisabled := TTyEdit.Create(Self);
EditDisabled.Parent := Self;
EditDisabled.SetBounds(24, 100, 300, 32);
EditDisabled.Text := '只读，无法编辑';
EditDisabled.Enabled := False;

// 读取输入内容
procedure TMainForm.ReadClicked(Sender: TObject);
begin
  ShowMessage('输入内容：' + Edit.Text);
end;
```

完整可运行示例参见 `examples/edit/umain.pas`。

---

## 7. 注意事项

- **UTF-8 安全操作：** 退格、删除、光标移动、选区均按 UTF-8 码点（字符）操作，不会截断多字节序列。内部使用 `LazUTF8` 函数库。
- **无 OnChange 事件：** 当前实现不提供 `OnChange`，如需监听输入变化，参考上方事件节的替代方案。
- **鼠标操作：** 单击定位光标（`CaretIndexAtX` 计算最近码点边界）；左键按住拖动扩展选区；双击全选（`SelectAll`）。
- **选区底色：** 选区使用 `:focus` 规则的 `border-color` 加 35% alpha（约 `$59` alpha byte），在浅色主题下表现为半透明蓝色带。
- **粘贴剥离换行：** `PasteFromClipboard` 会过滤掉剪贴板文本中所有的 CR（`#13`）和 LF（`#10`）字符，因为这是单行控件。
- **修饰键+方向键不拦截：** `Ctrl/Alt/Meta`（无 Shift）与方向键组合时，按键不被消费，由父窗口/系统处理（如词级跳转）。
- **无横向滚动（v1.1 已知限制）：** 当文本宽度超过控件宽度时，右侧内容不可见，光标也无法通过鼠标点击访问超出部分。视口固定在文本起始端。
- **无词级跳转（v1.1 已知限制）：** 不支持 Ctrl/Cmd+左右键实现词级光标移动（按键透传给父窗口，但不做词边界计算）。
- **Tab 导航：** 构造时自动启用 `TabStop`，可与其他 `TTyCustomControl` 子类一起参与 Tab 键顺序导航。
- **Text 赋值不触发回调：** `SetText` 仅更新内部字段并重绘，不会触发任何事件。
