# TTyEdit

## 1. 概述

TTyEdit 是 TyControls 库中的主题化单行文本输入控件，继承自 `TTyCustomControl`。典型用途：用户输入姓名、搜索关键词、数字等单行文本，支持完整的文本编辑能力：UTF-8 安全退格与删除、光标移动、选区（拖选/Shift+方向键）、词级导航（v1.8：词级光标移动、词级扩展选区、词级删除）、全选、剪贴板操作（Ctrl/Cmd+A/C/X/V）、鼠标点击定位与双击全选。

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

| 按键 | 无修饰键 | +Shift | +Ctrl 或 +Alt（Option） | +Ctrl/Alt+Shift | +Cmd（Meta，无 Shift） |
|------|----------|--------|------------------------|------------------|------------------------|
| `←` | 移动光标左移一码点；若有选区则折叠到选区左端 | 向左扩展/收缩选区 | **词级左移**：光标跳到上一词边界并收起选区 | **词级向左扩展选区**（保持锚点，仅移动光标到上一词边界） | 不拦截（透传给系统/父控件） |
| `→` | 移动光标右移一码点；若有选区则折叠到选区右端 | 向右扩展/收缩选区 | **词级右移**：光标跳到下一词边界并收起选区 | **词级向右扩展选区**（保持锚点，仅移动光标到下一词边界） | 不拦截（透传） |
| `Home` | 光标移到文本开头，收起选区 | 扩展选区到文本开头 | 不拦截（透传） | 扩展选区到文本开头 | 不拦截（透传） |
| `End` | 光标移到文本末尾，收起选区 | 扩展选区到文本末尾 | 不拦截（透传） | 扩展选区到文本末尾 | 不拦截（透传） |
| `Backspace` | 删除光标前一码点；有选区则删除选区 | — | **删除前一个词**（无选区时）；有选区则只删除选区 | — | — |
| `Delete` | 删除光标后一码点；有选区则删除选区 | — | **删除后一个词**（无选区时）；有选区则只删除选区 | — | — |
| `A` | — | — | 全选（`SelectAll`，Ctrl/Cmd+A） | — | 全选（`SelectAll`） |
| `C` | — | — | 复制选区到剪贴板（Ctrl/Cmd+C） | — | 复制选区到剪贴板 |
| `X` | — | — | 剪切选区到剪贴板（Ctrl/Cmd+X） | — | 剪切选区到剪贴板 |
| `V` | — | — | 粘贴（剥离换行后插入，Ctrl/Cmd+V） | — | 粘贴（剥离换行后插入） |
| 其他可打印字符 | 插入字符（经 `UTF8KeyPress`） | — | — | — | — |

> **修饰键+方向键说明：** 自 v1.8 起，`Ctrl`（Windows/Linux）或 `Alt`（macOS Option，`ssAlt`）与左/右方向键组合实现**词级导航**（详见下方「词级导航」小节）；带 Shift 时为词级扩展选区。`Cmd`（macOS Command，`ssMeta`，无 Shift）+方向键事件**不被消费**（`Key` 不置 0），透传给父窗口/系统，留作整行移动/系统快捷键。`Home`/`End` 在带 `Ctrl/Alt/Meta`（无 Shift）时同样透传不拦截。

> **剪贴板/全选快捷键的修饰键：** `A`/`C`/`X`/`V` 同时接受 `Ctrl` 与 `Cmd`（`ssMeta`），跨平台一致。

### 词级导航 (v1.8)

自 v1.8 起，TTyEdit 支持完整的词级（word-wise）光标导航、扩展选区与删除。

#### 键位绑定

词级操作的修饰键跨平台统一为 **`Ctrl` 或 `Alt`**（二者皆可触发）：

| 平台 | 触发修饰键 | 实现细节 |
|------|-----------|----------|
| Windows / Linux | `Ctrl`（`ssCtrl`） | 与系统约定一致 |
| macOS | `Option`（`ssAlt`） | 与 macOS 约定一致；`Cmd`（`ssMeta`）**不**用于词级，留作整行移动并透传 |

| 操作 | 键位 | 行为 |
|------|------|------|
| 词级左移 | `Ctrl/Alt` + `←` | 光标移到**上一词边界**（`PrevWordBoundary`），并收起选区 |
| 词级右移 | `Ctrl/Alt` + `→` | 光标移到**下一词边界**（`NextWordBoundary`），并收起选区 |
| 词级向左扩展选区 | `Ctrl/Alt` + `Shift` + `←` | 锚点不动，仅光标移到上一词边界，选区随之扩展/收缩 |
| 词级向右扩展选区 | `Ctrl/Alt` + `Shift` + `→` | 锚点不动，仅光标移到下一词边界，选区随之扩展/收缩 |
| 删除前一个词 | `Ctrl/Alt` + `Backspace` | 删除光标到上一词边界之间的内容（无选区时）；若有选区则**只删除选区** |
| 删除后一个词 | `Ctrl/Alt` + `Delete` | 删除光标到下一词边界之间的内容（无选区时）；若有选区则**只删除选区** |

> 双击仍为「全选」（不是选中单词）。词级操作均会消费按键（`Key := 0`），不会再透传给父窗口；只有 `Cmd`（`ssMeta`，无 Shift）+方向键不被消费。

#### 词边界规则

词边界基于 **Unicode 码点**（codepoint），而非字节，因此对多字节字符（带重音的拉丁字母、CJK、emoji 等）安全。判定规则（`IsWordCodepoint`）：

- **词字符**：既**不是空白**也**不是 ASCII 标点**的任意码点 —— 包括字母、数字、CJK 汉字、emoji、组合记号等。
- **非词字符**：
  - 空白：空格（`#32`）、制表符（`#9`）、不换行空格 U+00A0（`#$C2#$A0`）。
  - ASCII 标点：`` ! " # $ % & ' ( ) * + , - . / : ; < = > ? @ [ \ ] ^ ` { | } ~ ``

边界计算逻辑：

- **`NextWordBoundary(idx)`**：先跳过当前所在的**词字符连续段**，再跳过紧随其后的**非词字符连续段**，落在下一词的起点（或文本末尾）。
- **`PrevWordBoundary(idx)`**：先跳过光标前的**非词字符连续段**，再跳过其前的**词字符连续段**，落在当前/上一词的起点（或文本开头）。
- 索引超出 `[0, UTF8Length(Text)]` 会被先钳制再计算。

#### 示例

以 ASCII 文本 `foo bar baz`（长度 11 码点）为例：

```
foo bar baz
0   4   8  11      ← 词边界码点索引
```

- 光标在 0，连续 `Ctrl/Alt+→`：`0 → 4 → 8 → 11`（到末尾后停住）。
- 光标在 11，连续 `Ctrl/Alt+←`：`11 → 8 → 4 → 0`（到开头后停住）。
- 光标在 0，`Ctrl/Alt+Shift+→`：选中 `'foo '`（选区长度 4）；再按一次选中 `'foo bar '`（长度 8）。
- 光标在 11，`Ctrl/Alt+Backspace`：删成 `'foo bar '`（光标 8）；再按一次删成 `'foo '`（光标 4）。
- 光标在 0，`Ctrl/Alt+Delete`：删成 `'bar baz'`；再按一次删成 `'baz'`。

标点作为独立的非词段，会让词级移动在标点处停顿。文本 `foo.bar`：

- `NextWordBoundary(0)` = 4（跳过 `foo`，再跳过 `.`，落在 `bar` 起点）；`NextWordBoundary(4)` = 7。
- 光标在 7（末尾）按 `Ctrl/Alt+Backspace` → `'foo.'`（光标 4，在标点处停下，不会一次删到行首）。

多字节示例 `café bàr`（8 个码点）：光标在 0 按 `Ctrl/Alt+→` 落在码点索引 5（跳过 `café` 的 4 个码点再跳过空格）；末尾按 `Ctrl/Alt+Backspace` → `'café '`（光标 5）。

CJK 示例 `你好 世界`（5 个码点，每个汉字 1 码点）：光标在 0 按 `Ctrl/Alt+→` 落在码点索引 3（落在 `世` 起点）。

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
- **词级导航（v1.8）：** `Ctrl`（Windows/Linux）或 `Alt`（macOS Option，`ssAlt`）+左右键实现词级光标移动；带 Shift 时为词级扩展选区；`Ctrl/Alt`+`Backspace`/`Delete` 删除前一个/后一个词。词边界基于 Unicode 码点，词字符 = 非空白且非 ASCII 标点。详见上方「词级导航」小节。这些组合会消费按键，不再透传。
- **`Cmd`/Meta+方向键透传：** 仅 `Cmd`（macOS Command，`ssMeta`，无 Shift）+方向键以及 `Ctrl/Alt/Meta`（无 Shift）+`Home`/`End` 不被消费（`Key` 不置 0），透传给父窗口/系统，留作整行移动等用途。
- **横向自动滚动（v1.2）：** 文本超宽时自动横向滚动保持光标可见；HOME 键将视口还原至文本起始端，鼠标点击坐标已计入滚动偏移。
- **Tab 导航：** 构造时自动启用 `TabStop`，可与其他 `TTyCustomControl` 子类一起参与 Tab 键顺序导航。
- **Text 赋值不触发回调：** `SetText` 仅更新内部字段并重绘，不会触发任何事件。
