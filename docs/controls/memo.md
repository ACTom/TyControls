# TTyMemo — API 参考

## 1. 概述

`TTyMemo` 是 TyControls 库中的主题化多行文本编辑控件，继承自 `TTyCustomControl`。控件以一个逻辑行一条 `TStrings` 行的方式维护文本模型，支持回车换行、退格/删除（含跨行合并）、方向键与 Home/End 导航；当逻辑行数超过可见行数时，右侧自动出现内嵌的 `TTyScrollBar` 垂直滚动条，并支持鼠标滚轮滚动。文本模型发生任何变化（插入/拆分/删除/合并）时触发 `OnChange`；纯光标移动不触发。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Memo` |
| typeKey | `TyMemo` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸 | 200 × 120（逻辑像素） |

```pascal
uses tyControls.Memo;
```

---

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Lines` | `TStrings` | 空 | 文本模型，一条 `TStrings` 行对应一条逻辑行。读取返回内部列表；写入通过 `SetLines` 进行 `Assign`，随后夹紧光标与滚动窗口并刷新滚动条。 |
| `Text` | `string` | `''` | **（API parity 新增）** 整段文本的扁平视图：读取拼接所有逻辑行（含换行）；写入重设全部行并收起光标。便于像单行控件一样整体存取。 |
| `ReadOnly` | `Boolean` | `False` | 为 `True` 时拦截用户编辑（打字/回车/退格/删除/词级删除/粘贴），保留导航、选区、复制、全选；`Lines :=` 程序化写入仍可用；`CutToClipboard` 退化为 `CopyToClipboard`。 |
| `MaxLength` | `Integer` | `0`（无限） | 按**全模型内容码点数**（所有逻辑行 `UTF8Length` 之和，**换行不计**）封顶；`0` 表示无限制；打字满则拒插；粘贴时截断到余量；回车/退格/删除/合并不受限。 |
| `WantTabs` | `Boolean` | `False` | **（API parity 新增）** 为 `True` 时 Tab 键插入制表符（字面量）；为 `False` 时 Tab 用于焦点导航。 |
| `WantReturns` | `Boolean` | `True` | **（API parity 新增）** 为 `True` 时回车插入换行；为 `False` 时回车不换行（留作提交语义）。 |
| `ScrollBars` | `TScrollStyle` | `ssAutoVertical` | 滚动条策略，与 `TMemo` 同义：`ssNone` 两条都不要；`ssVertical` / `ssBoth` 强制显示竖条，`ssAutoVertical` / `ssAutoBoth` 溢出才出现；`ssHorizontal` / `ssBoth` 强制显示横条，`ssAutoHorizontal` / `ssAutoBoth` 溢出才出现。横条只在 `WordWrap = False` 时有意义（回绕模式不会横向滚动）。 |
| `WordWrap` | `Boolean` | `False` | 软回绕开关。`True` 时长逻辑行按词边界折成多条可见行；`False`（默认）时长行改为横向滚动。 |
| `HideSelection` | `Boolean` | `True` | 失去焦点时是否隐藏选区高亮。 |
| `Alignment` | `TAlignment` | `taLeftJustify` | **（API parity 新增）** **每一条可见行**的水平对齐（`TMemo` 在 `stdctrls.pp:1023` 转发同名属性）。这是一个真正缺失的**能力**：从前渲染器永远从内容区左缘起画，居中的多行文字块**用任何办法都做不出来**，主题也不行。比视口**更宽**的行不参与对齐——没有可居中的余量，此时横向滚动拥有原点（与 `TTyEdit.AlignOffset` 同一条口径）。绘制、选区带、光标和**点击命中**共用同一个偏移量，不会彼此错位。 |
| `CharCase` | `TEditCharCase` | `ecNormal` | **（API parity 新增）** 打字与赋值都强制大小写（`stdctrls.pp:1028`），复用 `TTyEdit` 的折叠规则，两个控件表现一致；设置它会像 LCL 一样**重折已有文本**（否则切到 `ecUpperCase` 的字段还在显示原来的小写值）。 |
| `Modified` | `Boolean`（读写，非 published） | **（API parity 新增）** 脏标记，同 `TTyEdit.Modified`：用户改过为 `True`，程序化 `Text :=` / `Lines :=` 之后回到 `False`。 |
| `OnChange` | `TNotifyEvent` | `nil` | 文本模型变化（插入/拆分/退格/删除/合并）后触发；纯光标移动不触发。 |
| `OnSelectionChange` | `TNotifyEvent` | `nil` | **（API parity 新增）** 光标位置**或**选区范围变化时触发（方向键 / 点击 / Shift 选区 / 程序化设置光标 / 编辑导致光标移动）；自带去抖——caret 与 anchor 都未变则不触发。 |
| `Enabled` | `Boolean` | `True` | 为 `False` 时键盘与滚轮输入一律被忽略（v1.5 策略：禁用时不消费按键、`DoMouseWheel` 返回 `False`）。 |
| `Font` | `TFont` | — | 字体；其 `PixelsPerInch` 参与行高/列宽度量。 |
| `Align` | `TAlign` | — | 父容器内的停靠方式。 |
| `Anchors` | `TAnchors` | — | 锚点布局。 |
| `StyleClass` | `string` | `''` | CSS 变体类名。 |
| `Controller` | `TTyStyleController` | `nil`（全局默认） | 关联的样式控制器；内嵌滚动条会继承同一 Controller。 |
| `OnClick` | `TNotifyEvent` | `nil` | 鼠标点击时触发。 |

### public 扁平选区属性（非 published，API parity 新增）

> 这些属性以**扁平码点偏移**表达光标与选区，对齐原生 `TMemo` 的扁平 `Sel*` 模型，与内部二维
> `(CaretLine, CaretCol)` 之间自动换算。**偏移索引的是 `Text` 返回的那一个字符串**，行与行之间按
> **完整的换行符**计数——Windows 上 CRLF 就是 **2** 个码点。于是原生写法逐字成立：
>
> ```pascal
> Memo.SelStart := Pos(Needle, Memo.Text) - 1;
> Memo.SelLength := Length(Needle);
> ```
>
> **换行以前只计 1**，这不只是差一个字符的不便——那样的偏移**指的是另一个字符串**：每多一条前置行就
> 多错一位，而在第 1 行上永远是对的,也就是大家试它的地方。分隔符取自 `Text` 用的同一个 `LineBreak`
> 选择,重新赋过 `Lines.LineBreak` 也不会让两者漂开。落在 CRLF **内部**的偏移被钳到该行行尾,所以谁也
> 没法把光标塞进一个换行符中间。

| 属性 | 类型 | 说明 |
|------|------|------|
| `SelStart` | `Integer`（读写） | 选区起始的扁平码点偏移；写入时收起选区到该处。 |
| `SelLength` | `Integer`（读写） | 选区长度（扁平码点数）；写入时从 `SelStart` 起扩展光标。 |
| `SelText` | `string`（读写） | 选区内容；恒等于 `UTF8Copy(Text, SelStart + 1, SelLength)`。写入时以新文本替换选区，仅触发一次 `OnChange`。 |
| `CaretPos` | `Integer`（读写） | 光标的扁平码点偏移。**刻意不是 LCL 的 `TPoint`**：两个类型之间不存在赋值，移植代码是编译不过（响的失败），而且 `SelStart`/`SelLength`/`SelText` 都是扁平的，四者必须指向同一个字符串。真正缺的是**信息本身**，见下面两行。 |
| `CaretLine` / `CaretCol` | `Integer`（只读函数） | **（API parity 新增可达性）** 光标的**行**与**列**（0 起，按码点）——即 LCL 在 memo 上让 `CaretPos` 回答的东西。它们从前是 **protected**，于是每个“Ln 12, Col 4”指示器、跳转到行、错误高亮都得先派生一个子类。现在是 public。 |
| `SetCaret(ALine, ACol)` | — | **（API parity 新增可达性）** 同上，按行/列设置光标。 |
| `AddHandlerOnChange` / `RemoveHandlerOnChange` | — | **（API parity 新增）** 多播 `OnChange`，与 `TTyEdit` 同义。 |

> `SelectAll` 之后 `SelLength` 是 `UTF8Length(Text)` **减去** `TStrings.Text` 在最后一行之后补的那个
> 尾随换行符——那个位置不是一个光标能落脚的地方（LCL 自己的 `TCustomEdit.SelectAll` 把它算进去了）。

### public 方法（API parity 新增）

| 方法 | 说明 |
|------|------|
| `ClearSelection` | **删除**选中的文本（与 LCL / Delphi 同名方法一致）。**这是不兼容变更**——它从前只是收起高亮、把文字留着。 |
| `CollapseSelection` | 旧的 `ClearSelection` 行为：只收起选区，不动文字。 |
| `Append(AValue)` | 追加一条逻辑行（跑日志的那种写法）。 |
| `Clear` | 清空。 |
| `ScrollBy(DeltaX, DeltaY)` | 按设备像素滚动**文本视图**——这是 `TCustomMemo` 赋予 `ScrollBy` 的含义。**正**的 delta 把内容往下/往右推（露出更靠前的行/列，符号跟随 `TWinControl`）；纵向按整个可视行量化，不足一行的 `DeltaY` 是空操作，要按行走请用 `TopLine` / `SetTopLine`。 |

> **`ScrollBy` 从前是 `TWinControl` 的那个"搬子控件"版本**：调用它的人拿到的是把备忘录自己内嵌的
> 滚动条从停靠边上拖走，而文字纹丝不动。这里重写是安全的,也只有这里安全——`TTyScrollBox` 的
> `ScrollByDelta` 正是调 `ScrollBy` 要那个搬子控件的语义,在那儿重写会变成自己调自己。

### 继承的通用成员

TTyMemo 继承自 `TTyCustomControl`（`tyControls.Base`）的通用状态机制。`TabStop` 在构造时置为 `True`。**基线事件集**（Tier A 鼠标 / 通用 + Tier B 键盘 / 焦点）全部暴露——见 [../events.md](../events.md)。

---

## 4. 文本模型与光标

- 文本以逻辑行存储：`Lines[i]` 是第 i 条逻辑行的 UTF-8 字符串。空模型在视觉上仍为一条可承载光标的行（`LineCountLogical >= 1`）。
- 二维光标 `(CaretLine, CaretCol)`：`CaretLine` 在 `0 .. LineCountLogical-1`，`CaretCol` 是该行内的**码点**索引（`0 .. UTF8Length(line)`）。
- 垂直移动（↑/↓）会记忆“期望列”（desired column），跨越短行后仍尽量回到原列；行内编辑/水平移动会刷新期望列。
- 度量统一使用 `TyConfigureTextFont` 在 BGRA 位图上完成，使列宽（光标定位）与绘制结果一致（与 `TTyEdit` 的光标漂移修复同源）。

---

## 5. 键盘与交互

| 操作 | 行为 |
|------|------|
| 可打印字符 | 在 `CaretCol` 处插入码点，光标后移；触发 `OnChange` |
| `Enter`（回车） | 在光标处拆分当前行为两行，光标落到新（下）行行首；触发 `OnChange` |
| `Backspace`（退格） | 行内删除前一码点；位于行首且非首行时把当前行并入上一行末尾，光标落在接合点；位于 (0,0) 为空操作（消费按键但不触发 `OnChange`） |
| `Delete` | 行内删除后一码点；位于行尾且有后续行时把下一行上提合并；位于文档末尾为空操作（消费按键但不触发 `OnChange`） |
| `←` / `→` | 行内左右移动；越过行首/行尾时跳到上一行末尾 / 下一行行首 |
| `↑` / `↓` | 上下移动，按记忆的期望列定位（夹紧到目标行长度） |
| `Home` / `End` | 行首 / 行尾；配合 `Ctrl`（或 macOS `Cmd`/Meta）跳到文档开头 / 末尾 |
| `Shift+方向键` / `Shift+Home/End` | 在保持选区锚点的同时移动光标，**扩展二维选区**（与上面的导航一一对应，包括 `Shift+Ctrl/Cmd+Home/End` 扩展到文档首尾、`Shift+Ctrl/Alt+←/→` 按词扩展）；任何不带 `Shift` 的普通导航会**折叠选区**到光标处 |
| `Ctrl/Cmd+A` | 全选整个文档（锚点置于 `(0,0)`、光标置于末行末尾） |
| `Ctrl/Cmd+C` | 复制选区文本到剪贴板（多行以 `LineEnding` 连接；经虚方法 `WriteClipboardText`，便于无头测试覆写）；无选区时为空操作 |
| `Ctrl/Cmd+X` | 剪切选区（先复制再 `DeleteSelection`，触发 `OnChange`）；无选区时为空操作 |
| `Ctrl/Cmd+V` | 在光标处粘贴剪贴板文本（经虚方法 `ReadClipboardText`）；若文本含 `CR`/`LF` 则**按行拆分插入为多行**（首段并入当前行光标前缀、中间段成为新行、末段拼接原光标后缀）；有选区时先删除选区再插入；触发 `OnChange` |
| `Ctrl/Alt+←` / `Ctrl/Alt+→` | **按词移动**光标（行内复用 `TTyEdit` 的 `IsWordCodepoint`/`NextWordBoundary`/`PrevWordBoundary`）；位于行首/行尾时跨到上一行末尾 / 下一行行首；配合 `Shift` 则按词扩展选区 |
| `Ctrl/Alt+Backspace` | 删除**前一个词**（行内）；位于行首（列 0）时退化为跨行合并到上一行末尾；触发 `OnChange` |
| `Ctrl/Alt+Delete` | 删除**后一个词**（行内）；位于行尾时退化为把下一行上提合并；触发 `OnChange` |
| `Ctrl/Cmd+Z`（无 Shift） | **撤销**（Undo）：恢复上一个快照；触发 `OnChange`（v1.12，见 §11） |
| `Ctrl/Cmd+Y` 或 `Ctrl/Cmd+Shift+Z` | **重做**（Redo）：重新应用被撤销的快照；触发 `OnChange`（v1.12，见 §11） |
| 鼠标按下 / 拖拽 | 在指针下的 `(行, 列)` 落下光标并置选区锚点；按住左键拖拽时 `MouseMove` 把选区扩展到指针下的 `(行, 列)`，松开结束 |
| 鼠标滚轮 | 上滚 `TopLine -= 3`、下滚 `TopLine += 3`（先调用 `inherited`，即用户的 `OnMouseWheel`，若已消费则不再滚动） |

> **注意：** 当 `Enabled = False` 时所有键盘/滚轮输入都不生效，且 `KeyDown` 不消费按键（导航可下传）。
>
> **选区渲染：** 存在选区时，每条可见逻辑行在文本下方绘制一条**选区高亮带**（selection band）——内部整行的覆盖整行宽度，起始行/结束行只覆盖选中的 x 区间（与 `TTyEdit` 同源）；选区存在期间不绘制光标。选区带底色取子部件 typeKey **`TyTextSelection`** 的 `background`（默认 `var(--selection)`，accent 着色的半透明），与 `TTyEdit` 选区、`TyListItem:active` 选中行视觉同源（Batch ④，取代早前写死的 `:focus border-color + 35% alpha`）。剪贴板的读写经由可被测试覆写的虚方法 `ReadClipboardText` / `WriteClipboardText`（与 `TTyEdit` 一致，便于无头环境断言）。

---

## 6. 垂直滚动

- 可见行数 `VisibleRows = Height div LineHeight(Font.PixelsPerInch)`（下限 1）。
- 当 `LineCountLogical > VisibleRows` 时，惰性创建内嵌 `TTyScrollBar`（`Create(Self)`、`Parent := Self`、`Align := alRight`、`Kind := sbVertical`），其 `Min=0`、`Max=LineCountLogical-VisibleRows`、`PageSize=VisibleRows`、`Position=TopLine`；否则隐藏滚动条。
- 滚动条宽度为 `MulDiv(12, Font.PixelsPerInch, 96)`；可见时渲染会从内容区右缘减去该宽度。
- `TopLine -> 滚动条.Position` 与 `滚动条.OnChange -> SetTopLine` 之间用 `FSyncingScroll` 防重入护栏，避免来回抖动。
- 编辑或导航后 `EnsureCaretLineVisible` 会把光标行滚回 `[TopLine, TopLine+VisibleRows)` 可见窗口内，并夹紧到 `MaxTopLine`。
- 内嵌滚动条由控件自身（`Create(Self)`）拥有，随 `TComponent` 析构自动释放。

---

## 7. 状态与主题：typeKey `TyMemo`

| 状态 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停在控件上 |
| `:focus` | 获得键盘焦点 |
| `:disabled` | `Enabled = False` |

每条可见逻辑行用 Memo 自身解析出的样式绘制（无逐行条目解析），文本以固定行高 top 对齐绘制；光标为 1px 竖条（与 `TTyEdit` 一致），仅在获得焦点且光标行可见时绘制，并以约 530 ms 间隔**闪烁**（`TTimer` 懒创建，无头测试与设计器中光标保持静态）。

### light.tycss 示例规则

```css
TyMemo {
  background: var(--surface);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: 1px;
  border-radius: var(--radius);
  padding: 4px;
  font-size: 9px;
}
TyMemo:hover    { border-color: darken(--border, 10%); }
TyMemo:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }
TyMemo:disabled { opacity: 0.5; }

/* 多行选区高亮带底色（与 TTyEdit 同源，Batch ④） */
TyTextSelection { background: var(--selection); }
```

> 该样式块同时存在于 `themes/light.tycss`、`themes/dark.tycss`、`themes/showcase.tycss`，并与内置兜底皮肤 `TyBuiltinThemeCss` 中的 `TyMemo` 块逐字一致——因此未加载任何主题、或在设计器中拖放时控件也有合理外观。

---

## 8. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.Memo;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

// 创建多行编辑器
var M: TTyMemo;
M := TTyMemo.Create(Self);
M.Parent := Self;
M.SetBounds(16, 16, 388, 240);
M.Lines.Text := '第一行' + LineEnding + '第二行' + LineEnding + '第三行';
M.OnChange := @OnMemoChange;

procedure TMainForm.OnMemoChange(Sender: TObject);
begin
  Label1.Caption := Format('行数：%d', [(Sender as TTyMemo).Lines.Count]);
end;
```

完整可运行示例参见 `examples/memo/umain.pas`。

---

## 9. 注意事项

1. **UTF-8 码点为单位：** `CaretCol`、行内编辑、列宽度量均以码点（而非字节）为单位，多字节字符（中文/emoji）行为正确。
2. **行高/列宽与绘制一致：** 度量经由 `TyConfigureTextFont` 在 BGRA 位图上完成，禁止用 LCL `TBitmap.Canvas` 的负字体高度去量，否则会引入光标漂移。
3. **像素测试请固定 PPI=96：** macOS 下 `Font.PixelsPerInch` 默认 72；几何/像素断言需显式钉为 96 才能与设计基准对齐。
4. **直接改 `Lines` 后窗口自动校正：** 通过 `SetLines`（即 `Lines :=` / `Lines.Assign`）写入会夹紧光标与 `TopLine` 并刷新滚动条；渲染时也会再调用一次 `UpdateScrollBar` 兜底外部直接 mutate 的情况。
5. **`OnChange` 仅模型变化触发：** 纯光标移动（方向键/Home/End、(0,0) 退格、文档末尾删除）不触发 `OnChange`。
6. **`ReadOnly`：** 打字/回车/退格/删除/词级删除/粘贴均被拦截；导航、选区、复制、全选仍可用；`Lines :=` 赋值不受限；`CutToClipboard` 退化为 `CopyToClipboard`。
7. **`MaxLength`：** 基于 `ContentCodepointCount`（全行 `UTF8Length` 之和，换行不计）；打字满则拒插（`UTF8KeyPress` 早退）；粘贴时截断原始剪贴板字符串到余量码点数（截断发生在拆行**之前**，实际内容可能略低于上限，但绝不超过）；回车/退格/删除不受限。
8. **光标闪烁：** 聚焦时约 530 ms 间隔启动；`TTimer` 懒创建，仅在 `HandleAllocated` 后启动，无头测试与设计器中光标静态。
9. **I-beam 光标（batch⑤+⑥）：** 构造时把 `Cursor` 设为 `crIBeam`，鼠标移到文本区域时呈现标准的文本输入「I 形」光标，与原生多行编辑框观感一致。

---

## 10. v1 限制 / 缺口（Gaps）

> **API parity 第三轮已交付：** `Alignment`、`CharCase`、`Modified`、多播 `AddHandlerOnChange` /
> `RemoveHandlerOnChange`，以及公开的 `CaretLine` / `CaretCol` / `SetCaret`（见 §3）。
> `BidiMode` 仍然**不 published**，但理由已经变了。旧文写的是「LCL 的 RTL 是 widgetset 在原生 EDIT
> 句柄上实现的，自绘控件没有可继承的东西」——绘制这一半现在有了：`TTyPainter.DrawText` 会把含右到左
> 文字的字符串走 Unicode 双向算法排版（UAX #9），阿拉伯语/希伯来语的**词序与字形连写都是对的**。
> 没有的是**镜像**：指示器、滚动条、列的左右不翻转。所以 `BidiMode` 依然是一个「界面上给了、控件只兑现一半」
> 的属性，仍然不 published。
> **光标与点击定位现在也是视觉序的——「画对了、选不对」这个缺口已经补上。** 本段旧文写的是
> 「本控件的光标与点击定位仍是逻辑序的」，那已经不成立了：`TTyMemo` 现在**按视觉行**各建一份
> 同向段（run）表——是**视觉行**不是逻辑行，因为 `RenderTo` 是把每个视觉行当作**独立字符串**去画的，
> 光标要对齐的是那一行的重排结果——并由它回答：绘制的光标位置、点击与拖选命中、`←`/`→`、
> 上下方向键记住的位置、以及横向滚动。点哪个字形光标就落在哪个字形上，方向键按**按键指向**走一个字形，
> 拖选给出的是两个端点之间的范围。
>
> 两个必须先知道、而不是踩到才发现的后果：
>
> - **跨书写方向的选区会画成多条选区带**，因为一段连续的**逻辑**范围在屏幕上不是一个连续矩形。
>   所以在混排文本上拖选，可能高亮到指针没扫过的字形、也可能漏掉扫过的——那正是两个端点之间的范围，
>   其他编辑器也都是这样。
> - **`Home` / `End` 仍是逻辑端点**：右到左行上按 `Home`，光标落在墨迹的**右**边。只有 `←`/`→` 是视觉移动。
>
> 仍然**没有**做的是**镜像**那一半（与 `TTyEdit` 一致）：本控件自己的滚动条、边距、对齐都不翻转，
> 选中换行符时那条延伸到行尾的提示带也仍画在行的右侧。守卫在 `tests/test.memo.bidi.pas`，详见
> [rtl.md](../rtl.md)。
> **无障碍：** 构造时声明 `AccessibleRole := larTextEditorMultiline`（`TTyEdit` 是 `larTextEditorSingleline`）。


`TTyMemo` 在可靠的多行编辑核心（逐码点编辑、跨行合并、二维导航、垂直滚动）之上，于 **v1.11** 补齐了对标 `TTyEdit` 的**二维文本选区**层：选区锚点（`Shift`+方向键/Home/End 扩展、鼠标拖拽高亮、逐行选区带、`SelText`/`SelectAll`/`CollapseSelection`）、**区间剪贴板**（`Ctrl/Cmd+A/C/X/V`，粘贴按 CR/LF 拆分为多行，复制/剪切经与 `TTyEdit` 同源的虚方法 `ReadClipboardText`/`WriteClipboardText`）、以及**按词导航**（`Ctrl/Alt+←/→` 跨行按词移动，`Ctrl/Alt+Backspace/Delete` 按词删除并在行边界退化为跨行合并）。本节曾登记的缺口现已全部补齐：

> **自动换行与水平滚动条都已交付**，不再是缺口：`WordWrap`（默认 `False`）按词边界把长逻辑行折成多条
> 可见行；`WordWrap = False` 时长行改由内嵌**横向**滚动条 + `ScrollX` 承载（`ScrollBars` 的
> `ssHorizontal` / `ssBoth` / `ssAutoHorizontal` / `ssAutoBoth` 四个横向取值都是真的生效的）。
> 本节此前那两行"尚未实现"写在实现落地之前，一直没有人回来改——记在这里，好让下一位读者知道旧文
> 是错的，而不是在描述另一个版本。

> **v1.11 已交付：** 文本选区、区间剪贴板（`Ctrl/Cmd+A/C/X/V`）、以及按词 / `Shift` 扩展导航均已落地（见 §5），不再是缺口。
> **v1.12 已交付：** 基于快照的**撤销 / 重做**（`Ctrl/Cmd+Z`、`Ctrl/Cmd+Y` / `Ctrl/Cmd+Shift+Z`）已落地（见 §11），不再是缺口。
> **Batch ①（本批次）已交付：** `ReadOnly`、`MaxLength`（`published` 属性，见 §3）、运行期光标闪烁（约 530 ms，无头静态）均已落地，不再是缺口。
> 以上剩余条目均为可在后续 Tier-2 增强层补齐的项；当前不实现它们是经过权衡的范围决策，而非缺陷。`TTyEdit` 的相关说明亦记录于 [docs/rtl.md](../rtl.md)。

---

## 11. 撤销 / 重做（Undo / Redo，v1.12）

自 v1.12 起，`TTyMemo` 内置基于**快照**（snapshot）的撤销/重做历史，模型与 `TTyEdit` 同源，但快照覆盖**多行**状态。

### 模型

- **快照式历史：** 每次会改变可编辑状态的操作之前，控件先把完整可编辑状态序列化为一个不透明字符串快照压入撤销栈。对 Memo，快照包含二维光标 `(CaretLine, CaretCol)`、二维选区锚点 `(AnchorLine, AnchorCol)`、以及全部逻辑行内容（连同行数）。撤销恢复上一个快照（并把当前状态移入重做栈），重做重新应用。序列化由 protected 的 `CaptureState: string` / `RestoreState(const S: string)` 完成，复用同一个可单元测试的 `TTyUndoStack`（`tyControls.UndoStack`）。
- **多行 / 尾随空行保真：** 快照头部显式记录**行数**（`FLines.Count`），正文按 `#10` 拼接所有行；`RestoreState` 按行数逐行重建 `FLines`，**不**依赖 `TStrings.Text`（后者会丢弃尾随空行）。因此一个以空逻辑行结尾的文档——例如末尾按了一次回车——经撤销/重做后能**逐字精确还原**，包括尾随的空行数量。
- **有界栈：** 撤销/重做栈各自上限约 **200** 步（`TTyUndoStack.FCap = 200`）；超出后丢弃最旧的条目。
- **输入合并（typing coalescing）：** 连续的**单字符插入**合并为**一个**撤销步。任何**非输入**类操作开启全新步：删除 / 退格 / 回车（`Enter`，拆行）/ 词级删除 / 粘贴 / 剪切 / 通过 `Lines :=`（`SetLines`）赋值。此外，任何**光标导航或选区变化**（方向键、Home/End、点击/拖选、词级移动等）都会**打断**当前的合并串。
- **新编辑清空重做栈：** 撤销之后若再产生任何新编辑，重做栈立即被清空。
- **复合操作单步可逆：** 回车拆行、粘贴（多行拆分并入）、剪切等内部含「先删选区再插入/合并」的复合操作，在操作开始处只捕获**一个**撤销步（内部子操作被 `FSuspendUndo` 抑制），因此一次撤销即整体回退。

### 键位

| 操作 | 键位 |
|------|------|
| 撤销（Undo） | `Ctrl+Z`（Windows/Linux）或 `Cmd+Z`（macOS，`ssMeta`），**不带** Shift |
| 重做（Redo） | `Ctrl+Y` / `Cmd+Y`，**或** `Ctrl/Cmd+Shift+Z` |

重做分支先于撤销分支判定，确保 `Ctrl/Cmd+Shift+Z` 不会被普通 `Ctrl/Cmd+Z` 误吞。两者均会消费按键（`Key := 0`）。

### 行为说明

- **受 `Enabled` 守卫：** `Enabled = False` 时撤销/重做快捷键不生效；`Undo` / `Redo` 方法本身在禁用时也是空操作。
- **触发 `OnChange`：** `RestoreState` 末尾经由 `AfterEdit` 统一处理（夹紧光标、保持可见、刷新滚动条、重绘）并**触发 `OnChange`**——撤销/重做被视为一次状态变化，与正常编辑一致。
- **公开 API：** `procedure Undo; procedure Redo; function CanUndo: Boolean; function CanRedo: Boolean;`。
