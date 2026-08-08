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
| `Text` | `string` | `''` | 输入框当前内容；赋值会触发重绘，**并触发** `OnChange`（`SetText` 末尾调用 `DoChange`，与 LCL `TCustomEdit` 一致）。赋值时光标移动到文本末尾，选区收起。 |
| `ReadOnly` | `Boolean` | `False` | 为 `True` 时拦截用户编辑（打字/退格/删除/词级删除/粘贴），保留光标移动、选区、复制、全选；程序化 `Text :=` 仍可写；`CutToClipboard` 退化为 `CopyToClipboard`。 |
| `MaxLength` | `Integer` | `0`（无限） | 按**码点**封顶；`0` 表示无限制；满则不再插入；粘贴时截断到余量。 |
| `PasswordChar` | `string` | `''`（关闭） | 单个 UTF-8 码点（如 `'●'`）；渲染与宽度测量都用掩码字符替代实际内容；掩码激活时**禁用复制/剪切**（防明文外泄）。LCL 那边是 `Char`，这里刻意放宽成字符串——大家真正想用的 `'●'`（U+25CF）塞不进一个 `Char`。**`#0` 现在等同于 `''`（关闭掩码）**：LCL 的“关掉”就是写 `#0`，而 `Ed.PasswordChar := #0` 在这里能编译（`Char` 转 `string`），从前会得到一个装着 NUL 的单字符串——于是该显示明文的时候仍在打码，且打的是一个谁也看不见的字形。 |
| `EchoMode` | `TEchoMode` | `emNormal` | **（API parity 新增）** 回显方式：`emNormal` 显示文本 / `emPassword` 打码 / `emNone` **什么都不显示**。与 `PasswordChar` **双向联动**，规则照抄 LCL（`include/customedit.inc:374-387`、`408-424`）：`''`↔`emNormal`、`' '`↔`emNone`、其余↔`emPassword`。`emNone` 从前在这里没有任何等价写法。 |
| `HideSelection` | `Boolean` | `True` | **（API parity 新增）** 与 `TEdit` 同默认：控件**失焦时不画选区高亮**（选区本身保留，只是不画）。从前只按 `HasSelection` 画，于是一张窗体上三个输入框会同时显示三段“像是活动的”选区。 |
| `AutoSelect` | `Boolean` | `True` | **（API parity 新增）** 与 `TEdit` 同默认：**键盘**获得焦点（Tab/Enter）时全选内容，本次焦点访问内的**第一次左键单击**也全选（`AutoSelected` 是那个闩）。鼠标点击定位光标不受影响——LCL 用 `csLButtonDown` 区分两者，这里照做。没有它，“Tab 进去直接打新值”这套录入流程要在每个输入框的 `OnEnter` 里手写 `SelectAll`。 |
| `TextHint` | `string` | `''` | 占位符文本；仅在 `Text` 为空时绘制，颜色取子部件 typeKey `TyTextHint` 的 `color`（默认 `var(--muted)`，弱化前景）。 |
| `Alignment` | `TAlignment` | `taLeftJustify` | **（API parity 新增）** 文本水平对齐（左 / 右 / 居中）；影响文本绘制起点，光标定位随对齐偏移。 |
| `CharCase` | `TEditCharCase` | `ecNormal` | **（API parity 新增）** 输入字符大小写转换：`ecNormal`（原样） / `ecUpperCase`（转大写） / `ecLowerCase`（转小写）。 |
| `NumbersOnly` | `Boolean` | `False` | **（API parity 新增）** 为 `True` 时仅接受数字字符输入（非数字键被拦截）。 |
| `Enabled` | `Boolean` | `True` | 为 `False` 时触发 `:disabled`，控件不响应键盘/鼠标输入 |
| `Font` | `TFont` | 系统默认 | 传递 PPI 给渲染器；字体族与大小优先由主题控制 |
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点 |

### public 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `CaretPos` | `Integer`（读写） | 光标的码点索引，范围 `[0, UTF8Length(Text)]`。写入时收起选区（`FSelAnchor := FCaretPos`）并重绘。**刻意与 LCL 的 `TPoint` 不同**：`TCustomEdit` 那边之所以是点，是因为同一个类还要撑起 memo；单行输入框没有第二根轴。两个类型之间不存在赋值，所以移植代码是**编译不过**（响的那种失败），不是悄悄跑歪。兄弟控件 `TTySpinEdit` 早先也是这么定的，两处口径一致。多行控件真正需要的行/列形式在 `TTyMemo.CaretLine` / `CaretCol`。 |
| `Modified` | `Boolean`（读写） | **（API parity 新增）** 脏标记，同 LCL `TCustomEdit.Modified`：**用户**改过（打字/删除/粘贴/剪切/撤销）为 `True`，程序化 `Text :=` 之后回到 `False`。这个区分正是它的全部内容，也是应用层用 `OnChange` **搭不出来**的东西——`OnChange` 两种情况都触发。用于驱动“保存”按钮可用性、关闭前提示等。 |
| `AutoSelected` | `Boolean`（读写） | **（API parity 新增）** `AutoSelect` 的闩：本次焦点访问已经自动全选过了，于是已聚焦状态下再点一次不会重新全选；失焦时清除。 |
| `procedure AddHandlerOnChange(AEvent; AsFirst = False)` / `RemoveHandlerOnChange(AEvent)` | **（API parity 新增）** 多播 `OnChange`（LCL `stdctrls.pp:853-855`）。唯一的那个 `OnChange` 属性是**应用**的；库内或框架层的观察者（校验器、脏标记跟踪、实时预览）不该为了看一眼输入而把它抢走，两个观察者也得能共存。`RemoveAllHandlersOfObject` 已重写，被释放的观察者会自动摘除。 |

### public 选区 API（读写属性 + 只读方法）

> **（API parity 变更）** `SelStart` / `SelLength` / `SelText` 现为 **public 读写属性**（早前为只读方法），对齐原生 `TEdit` 的选区属性，便于程序化设置选区。仍为 public（非 published）。

| 属性 / 方法 | 类型 | 说明 |
|------|------|------|
| `SelStart` | `Integer`（读写） | 选区起始码点索引（`FCaret` 与 `FSelAnchor` 中较小者）；无选区时等于光标位置。写入时移动选区起点。 |
| `SelLength` | `Integer`（读写） | 选区长度（码点数，无选区时为 0）。写入时从 `SelStart` 起扩展选区到指定长度。 |
| `SelText` | `string`（读写） | 选区内容的 UTF-8 字符串；无选区时为空串。写入时以新文本替换当前选区。 |
| `function HasSelection: Boolean` | — | 当前是否有非空选区（`FCaret <> FSelAnchor`）。 |
| `procedure SelectAll` | 全选：将选区锚点设为 0，光标移到末尾。 |
| `procedure ClearSelection` | **（API parity 变更，破坏性）删除选区文本**——与 LCL / Delphi `TCustomEdit.ClearSelection` 一致（内部转发 `DeleteSelection`，因此带撤销步、移动光标并触发 `OnChange`）；无选区时退化为收起选区。**早前它只收起选区、不删文本**：同一个名字两种相反含义，而沉默的那种更危险——从 Lazarus 移植来的代码调用它想删掉用户选中的内容，文本却纹丝不动，也没有任何提示。 |
| `procedure CollapseSelection` | **（API parity 新增）** 收起选区、**不动文本**：将 `FSelAnchor := FCaret`。即 `ClearSelection` 的旧行为，保留并单独命名。 |

### public 文本方法

| 方法 | 说明 |
|------|------|
| `procedure Clear` | **（API parity 新增）** 清空内容，等价于 `Text := ''`——移植代码写的是 `Ed.Clear`，从前只能改写成 `Text := ''`。走 `SetText` 路径，因此记一个撤销步并触发 `OnChange`。 |

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
| `OnChange` | `TNotifyEvent` | **（v1.12 新增）** 文本内容因键盘编辑、剪贴板操作或撤销/重做发生变化时触发；通过 `Text :=` 直接赋值（`SetText`）**同样触发**。 |
| `OnEditingDone` | `TNotifyEvent` | **（API parity 基线 Tier B）** 编辑完成（失焦或回车提交）时触发。 |

> **基线事件集：** 除上表外，TTyEdit 还暴露全部**基线事件**（Tier A 鼠标 / 通用 + Tier B 键盘 / 焦点，因其为可聚焦的 `TTyCustomControl`）。完整清单见 [../events.md](../events.md)。

> **OnChange（v1.12 新增）：** 自 v1.12 起 TTyEdit 提供 published 的 `OnChange` 事件（早前版本没有）。它在文本因按键编辑、剪贴板或撤销/重做变化时触发；纯光标移动不触发；`Text :=` 赋值触发。详见上方「撤销 / 重做」节末的「`OnChange` 事件」小节。

### 键盘表

| 按键 | 无修饰键 | +Shift | +Ctrl 或 +Alt（Option） | +Ctrl/Alt+Shift | +Cmd（Meta，无 Shift） |
|------|----------|--------|------------------------|------------------|------------------------|
| `←` | 移动光标左移一码点；若有选区则折叠到选区左端 | 向左扩展/收缩选区 | **词级左移**：光标跳到上一词边界并收起选区 | **词级向左扩展选区**（保持锚点，仅移动光标到上一词边界） | 不拦截（透传给系统/父控件） |
| `→` | 移动光标右移一码点；若有选区则折叠到选区右端 | 向右扩展/收缩选区 | **词级右移**：光标跳到下一词边界并收起选区 | **词级向右扩展选区**（保持锚点，仅移动光标到下一词边界） | 不拦截（透传） |
| `Home` | 光标移到文本开头，收起选区 | 扩展选区到文本开头 | 不拦截（透传） | 扩展选区到文本开头 | 不拦截（透传） |
| `End` | 光标移到文本末尾，收起选区 | 扩展选区到文本末尾 | 不拦截（透传） | 扩展选区到文本末尾 | 不拦截（透传） |
| `Enter` | **提交编辑**：调用 `EditingDone`（触发 `OnEditingDone`）。**不消费按键**（`Key` 不置 0），窗体的默认按钮仍能收到它 | — | — | — | — |
| `Backspace` | 删除光标前一码点；有选区则删除选区 | — | **删除前一个词**（无选区时）；有选区则只删除选区 | — | — |
| `Delete` | 删除光标后一码点；有选区则删除选区 | — | **删除后一个词**（无选区时）；有选区则只删除选区 | — | — |
| `A` | — | — | 全选（`SelectAll`，Ctrl/Cmd+A） | — | 全选（`SelectAll`） |
| `C` | — | — | 复制选区到剪贴板（Ctrl/Cmd+C） | — | 复制选区到剪贴板 |
| `X` | — | — | 剪切选区到剪贴板（Ctrl/Cmd+X） | — | 剪切选区到剪贴板 |
| `V` | — | — | 粘贴（剥离换行后插入，Ctrl/Cmd+V） | — | 粘贴（剥离换行后插入） |
| `Z` | — | — | **撤销**（Undo，Ctrl/Cmd+Z，无 Shift） | **重做**（Redo，Ctrl/Cmd+Shift+Z） | **撤销**（Undo） |
| `Y` | — | — | **重做**（Redo，Ctrl/Cmd+Y） | — | **重做**（Redo） |
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

## 撤销 / 重做（Undo / Redo，v1.12）

自 v1.12 起，TTyEdit 内置基于**快照**（snapshot）的撤销/重做历史。

### 模型

- **快照式历史：** 每次会改变可编辑状态的操作（mutation）**之前**，控件先把完整的可编辑状态——光标位置、选区锚点与文本——序列化为一个不透明字符串快照压入撤销栈。撤销即恢复上一个快照（并把当前状态移入重做栈），重做则重新应用。序列化由 protected 的 `CaptureState: string` / `RestoreState(const S: string)` 完成，复用同一个可单元测试的 `TTyUndoStack`（`tyControls.UndoStack`）。
- **有界栈：** 撤销/重做栈各自上限约 **200** 步（`TTyUndoStack.FCap = 200`）；超出后丢弃最旧的条目。
- **输入合并（typing coalescing）：** 连续的**单字符插入**合并为**一个**撤销步——连打一串字符后一次撤销即可全部回退。任何**非输入**类操作会开启一个全新步：删除 / 退格 / 词级删除 / 粘贴 / 剪切 / 通过 `Text :=` 赋值。此外，任何**光标导航或选区变化**（方向键、Home/End、点击/拖选、词级移动等）都会**打断**当前的合并串，使下一次输入从新的步开始。
- **新编辑清空重做栈：** 撤销之后若再产生任何新编辑，重做栈立即被清空（标准编辑器语义）。
- **复合操作单步可逆：** 粘贴 / 剪切等内部包含「先删选区再插入」的复合操作，在操作开始处只捕获**一个**撤销步（内部子操作被 `FSuspendUndo` 抑制），因此一次撤销即整体回退。

### 键位

| 操作 | 键位 |
|------|------|
| 撤销（Undo） | `Ctrl+Z`（Windows/Linux）或 `Cmd+Z`（macOS，`ssMeta`），**不带** Shift |
| 重做（Redo） | `Ctrl+Y` / `Cmd+Y`，**或** `Ctrl/Cmd+Shift+Z` |

重做分支先于撤销分支判定，确保 `Ctrl/Cmd+Shift+Z` 不会被普通 `Ctrl/Cmd+Z` 误吞。两者均会消费按键（`Key := 0`）。

### 行为说明

- **受 `Enabled` 守卫：** 与所有其他键盘输入一致，`Enabled = False` 时撤销/重做快捷键不生效；`Undo` / `Redo` 方法本身在禁用时也是空操作。
- **触发 `OnChange`：** 撤销/重做会改变文本状态，因此 `RestoreState` 末尾调用 `DoChange`，**触发 `OnChange`**（见下方「`OnChange` 事件」）。
- **公开 API：** `procedure Undo; procedure Redo; function CanUndo: Boolean; function CanRedo: Boolean;`。

### `OnChange` 事件（v1.12 新增）

> **v1.12 新增：** 早前版本的 TTyEdit **没有** `OnChange`（见旧版「注意事项」）。自 v1.12 起新增 published 事件 `OnChange: TNotifyEvent`，在文本内容因键盘编辑、剪贴板操作、撤销/重做等发生变化时触发。**注意：** 通过 `Text :=` 直接赋值（`SetText`）**同样触发** `OnChange`——`SetText` 末尾调用 `DoChange`，与 LCL `TCustomEdit` 一致。

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
  font-size: 9px;
}
TyEdit:hover    { border-color: darken(--border, 10%); }
TyEdit:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }   /* 蓝色高亮边框 + 焦点环 */
TyEdit:disabled { opacity: 0.5; }

/* 选区底色与占位符颜色由独立子部件 typeKey 决定（Batch ④） */
TyTextSelection { background: var(--selection); }   /* accent 着色的半透明选区带 */
TyTextHint      { color: var(--muted); }            /* 占位符 / 提示文字 */
```

聚焦时除边框变蓝外，渲染器还会在光标位置绘制一条 1px 宽的竖线（颜色与 `TextColor` 相同）。光标在运行期**闪烁**（约 530 ms 间隔，`TTimer` 懒创建并仅在句柄分配后启动）；无头测试与设计器中计时器不启动，光标保持静态，确保像素测试确定性。

**选区底色（Batch ④）：** 有选区时，选区高亮带底色取子部件 typeKey **`TyTextSelection`** 的 `background`（默认 `var(--selection)` = `alpha(var(--accent), 0.30)`，accent 着色的半透明蓝带），文字在其上正常绘制。这取代了早前写死的"`:focus` 的 `border-color` 加 35% alpha（`$59`）"，使选区底色与 `TyListItem:active`（列表选中行）视觉同源，并可在主题中统一定制。详见 [tycss-reference.md](../tycss-reference.md) §3.3 / §8.2。

**占位符颜色（Batch ④）：** `TextHint` 占位符文字颜色取子部件 typeKey **`TyTextHint`** 的 `color`（默认 `var(--muted)`），取代早前对 `TextColor` 叠加 `$80` alpha 的写死做法。

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

- **无障碍：** 构造时声明 `AccessibleRole := larTextEditorSingleline`，与 LCL `TCustomEdit.Create`（`include/customedit.inc:87`）同一行。自绘控件没有可供辅助技术回退的原生对等物，不声明的话整个文本输入族对读屏软件都是不透明的。`TTyMaskEdit` 继承同一角色，`TTyMemo` 用 `larTextEditorMultiline`。
- **`InjectBackspace` / `InjectDelete` 现在是 `virtual` 的。** 它们是 `InjectKey` 的删除对偶，但与 `InjectKey` 不同——不经过 `FilterInsert`，而是直接改 `FText`，于是重写整串显示的子类（`TTyMaskEdit`）在这里**没有接缝**，这两个方法会从它的显示串里挖掉一个原始字符，掩码字面量和占位符一并挖走。这和 `FilterInsert` 出现之前粘贴路径上的洞是同一个形状。

- **UTF-8 安全操作：** 退格、删除、光标移动、选区均按 UTF-8 码点（字符）操作，不会截断多字节序列。内部使用 `LazUTF8` 函数库。
- **ReadOnly：** `ReadOnly = True` 时拦截打字/退格/删除/词级删除/粘贴；导航、选区、复制、全选、撤销/重做快捷键仍可用（但撤销/重做历史在只读模式下不会产生新步）；`CutToClipboard` 退化为 `CopyToClipboard`；`Text :=` 程序化赋值不受限制。
- **MaxLength：** 按码点数（`UTF8Length`）计算总文本长度；满则新打字被拦截；粘贴时截断到余量（`FMaxLength - UTF8Length(FText)`）；`0` 为无限制。
- **PasswordChar：** 赋值超过 1 个码点时自动截取首个码点；掩码激活时 `CopyToClipboard`/`CutToClipboard` 为空操作（防止明文外泄）；光标位置测量基于掩码字符串，保持与显示一致。
- **TextHint：** 仅在 `FText = ''` 时绘制；颜色取子部件 typeKey `TyTextHint` 的 `color`（默认 `var(--muted)`，弱化前景）——见上方「占位符颜色」。
- **光标闪烁：** 聚焦时以约 530 ms 间隔启动闪烁；`TTimer` 懒创建，仅在 `HandleAllocated` 后启动，因此无头测试与设计器中光标静态、像素测试确定性不变。
- **销毁一个「正持有焦点」的编辑框时，`OnExit` 会在析构中途跑起来——文本引擎必须活过 `inherited Destroy`。** `TWinControl.Destroy` 会调 `RemoveFocus` 交出焦点，回来的 `WM_KILLFOCUS` 是**同步**派发的：`CM_EXIT` → `DoExit` → `OnExit`。也就是说，在 `inherited Destroy` 内部会跑到普通的应用代码，而且是最自然的那种写法——`TTyNumericEdit` 失焦要重排显示、应用的 `OnExit` 处理器习惯写 `Edit.Text := ...` 提交字段。这个写入会重新进入 `SetTextInternal` → `BeginUndoStep` → `FUndoStack.Push`。所以 `TTyEdit.Destroy` 把撤销栈与测量位图放在 `inherited Destroy` **之后**才释放（并且用 `FreeAndNil`：`FMeasureBmp` 是按 `if FMeasureBmp = nil` 懒重建的，悬垂非空指针会被当成活对象用）。曾经反过来写，后果是**释放后使用**：`EAccessViolation` 在 widgetset 的 WindowProc 里抛出，`Free` 的调用方 `try...except` 根本看不到它，LCL 的 `TApplication.HandleException` 接住后弹**模态**错误框——GUI 里是关窗时蹦一个访问违例框，控制台/测试进程里则是没人能关掉它，进程永远卡在 `ShowModal`，CPU 为 0。真机那一半由 `tests/editteardownverify` 守着（**不装**异常陷阱地跑，回归就复现「卡死」本身，所以要配外部超时；`-trap` 则把它变成具名失败）；单元套件那一半在 `tests/test.focus.tabstop.pas`，它必须自己装一个 `Application.OnException` 陷阱，否则回归是把整个 runner 拖住而不是判红。
- **OnChange 事件（v1.12 新增）：** 自 v1.12 起提供 published `OnChange`，文本因键盘编辑/剪贴板/撤销/重做变化时触发；`Text :=` 赋值**同样触发**（`SetText` 末尾调用 `DoChange`，与 LCL `TCustomEdit` 一致）。详见「撤销 / 重做」节。
- **鼠标操作：** 单击定位光标（`CaretIndexAtX` 计算最近码点边界）；左键按住拖动扩展选区；双击全选（`SelectAll`）。
- **选区底色：** 选区底色取子部件 typeKey `TyTextSelection` 的 `background`（默认 `var(--selection)`，即 accent 着色的半透明），在浅色主题下表现为半透明蓝色带；与列表选中行（`TyListItem:active`）视觉同源。见上方「选区底色（Batch ④）」。
- **粘贴剥离换行：** `PasteFromClipboard` 会过滤掉剪贴板文本中所有的 CR（`#13`）和 LF（`#10`）字符，因为这是单行控件。
- **词级导航（v1.8）：** `Ctrl`（Windows/Linux）或 `Alt`（macOS Option，`ssAlt`）+左右键实现词级光标移动；带 Shift 时为词级扩展选区；`Ctrl/Alt`+`Backspace`/`Delete` 删除前一个/后一个词。词边界基于 Unicode 码点，词字符 = 非空白且非 ASCII 标点。详见上方「词级导航」小节。这些组合会消费按键，不再透传。
- **`Cmd`/Meta+方向键透传：** 仅 `Cmd`（macOS Command，`ssMeta`，无 Shift）+方向键以及 `Ctrl/Alt/Meta`（无 Shift）+`Home`/`End` 不被消费（`Key` 不置 0），透传给父窗口/系统，留作整行移动等用途。
- **横向自动滚动（v1.2）：** 文本超宽时自动横向滚动保持光标可见；HOME 键将视口还原至文本起始端，鼠标点击坐标已计入滚动偏移。
- **Tab 导航：** 构造时自动启用 `TabStop`，可与其他 `TTyCustomControl` 子类一起参与 Tab 键顺序导航。
- **Text 赋值触发 `OnChange`：** `SetText` 更新字段、把光标移到末尾、记一个非输入类撤销步、重绘，并在末尾调用 `DoChange` 触发 `OnChange`。
- **`ClearSelection` 会删字（API parity 破坏性变更）：** 它现在删除选区文本（LCL / Delphi 语义）；只想去掉高亮而保留文本请改用新增的 `CollapseSelection`。
- **`Enter` 提交字段：** 无修饰键的回车调用 `EditingDone`（触发 `OnEditingDone`），但**不消费按键**，窗体的默认按钮仍能收到；`Enabled = False` 时同其他按键一样不生效。
- **I-beam 光标（batch⑤+⑥）：** 构造时把 `Cursor` 设为 `crIBeam`，鼠标移到文本区域时呈现标准的文本输入「I 形」光标，与原生单行编辑框观感一致。
- **双向文本（阿拉伯语 / 希伯来语）：光标、点击、选区、方向键都按字形走。** `TTyPainter.DrawText` 把含右到左文字的字符串按 Unicode 双向算法排版，本控件的光标模型也跟上了：显示文本里出现右到左字符时，控件为该行建一份**同向段（run）表**——每段是一段连续的逻辑码点加上它在屏幕上的左右边界——此后的每次查询都只是查表。
  - **点击**落在哪个字形上，光标就贴在那个字形边上，内嵌段的两端都点得到。
  - **选区**是逻辑区间，跨书写方向时会**按段各画一条**高亮带，所以高亮盖住的正是这段区间点名的那些字形，中间没被选中的字形不会被顺带涂上。
  - **左右方向键是视觉移动**：按哪边光标就往哪边走一个字形，跨段时按**屏幕顺序**跨（右到左段内部则是逻辑序往回走）。这是 `plans/2026-08-04-rtl-mirroring-scope.md` §6.3 第 4 条划的线——**文本**里的左右键归双向层，列表 / 表格 / 页签 / 菜单里的左右键是布局方向，归尚未开工的镜像层。
  - **`Home` / `End` 仍是逻辑的**（首 / 末码点，不管它画在哪儿），`Ctrl`+左右的词级跳转同理——词是码点的连续段，不是字形的。

  **一个索引两个位置**：内嵌段与两侧文本的交界处，同一个码点索引对应屏幕上**两个**点（该段的两端），Unicode 算法本身不替你选。控件记住最后一次光标移动隐含的是哪一侧（输入与向右走 = 贴前一个字符，点击 = 贴用户瞄准的那一段），所以两个位置都到得了。BGRA 的 `TBidiTextLayout.GetCaret` 只会给出「在此处结束的那一段」的那一个，另一个直接丢掉——本控件因此自己排版并缓存，而不是调用 `TTyPainter.TextCaretX`（它还要求 painter 正处在 `BeginPaint`/`EndPaint` 之间，而光标是鼠标、按键和闪烁定时器问出来的）。两者的答案由 `tests/test.edit.bidi.pas` 对齐。

  **对左到右文本零代价**：判定走 `TyTextHasRTL` 字节扫描，且**每次文本变化只问一次**，之后每次光标查询只多一个布尔判断（实测 ≤ 0.2 µs，对比光标查询本身约 23 µs，落在噪声里）；它挡住的那份排版建一次约 3.3 ms。掩码（`PasswordChar`）字段按**显示串**判定，所以密码框永远走不到双向路径。

  由本控件派生的 `TTyNumericEdit` / `TTyCurrencyEdit` / `TTyCalcEdit` / `TTyTrackEdit` / `TTyMaskEdit` / `TTyURLEdit` / `TTyComboEdit` / `TTyValueEdit` 都不覆写光标与绘制路径，因此一并生效。`TTyMemo` 尚未跟进，仍是逻辑序前缀和。详见 [rtl.md](../rtl.md)。
