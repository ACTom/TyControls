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
| `ReadOnly` | `Boolean` | `False` | 为 `True` 时拦截用户编辑（打字/回车/退格/删除/词级删除/粘贴），保留导航、选区、复制、全选；`Lines :=` 程序化写入仍可用；`CutToClipboard` 退化为 `CopyToClipboard`。 |
| `MaxLength` | `Integer` | `0`（无限） | 按**全模型内容码点数**（所有逻辑行 `UTF8Length` 之和，**换行不计**）封顶；`0` 表示无限制；打字满则拒插；粘贴时截断到余量；回车/退格/删除/合并不受限。 |
| `OnChange` | `TNotifyEvent` | `nil` | 文本模型变化（插入/拆分/退格/删除/合并）后触发；纯光标移动不触发。 |
| `Enabled` | `Boolean` | `True` | 为 `False` 时键盘与滚轮输入一律被忽略（v1.5 策略：禁用时不消费按键、`DoMouseWheel` 返回 `False`）。 |
| `Font` | `TFont` | — | 字体；其 `PixelsPerInch` 参与行高/列宽度量。 |
| `Align` | `TAlign` | — | 父容器内的停靠方式。 |
| `Anchors` | `TAnchors` | — | 锚点布局。 |
| `StyleClass` | `string` | `''` | CSS 变体类名。 |
| `Controller` | `TTyStyleController` | `nil`（全局默认） | 关联的样式控制器；内嵌滚动条会继承同一 Controller。 |
| `OnClick` | `TNotifyEvent` | `nil` | 鼠标点击时触发。 |

### 继承的通用成员

TTyMemo 继承自 `TTyCustomControl`（`tyControls.Base`）的通用状态机制。`TabStop` 在构造时置为 `True`。

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

---

## 10. v1 限制 / 缺口（Gaps）

`TTyMemo` 在可靠的多行编辑核心（逐码点编辑、跨行合并、二维导航、垂直滚动）之上，于 **v1.11** 补齐了对标 `TTyEdit` 的**二维文本选区**层：选区锚点（`Shift`+方向键/Home/End 扩展、鼠标拖拽高亮、逐行选区带、`SelText`/`SelectAll`/`ClearSelection`）、**区间剪贴板**（`Ctrl/Cmd+A/C/X/V`，粘贴按 CR/LF 拆分为多行，复制/剪切经与 `TTyEdit` 同源的虚方法 `ReadClipboardText`/`WriteClipboardText`）、以及**按词导航**（`Ctrl/Alt+←/→` 跨行按词移动，`Ctrl/Alt+Backspace/Delete` 按词删除并在行边界退化为跨行合并）。下列条目仍被**有意推迟**（deferred），当前版本**尚未**实现，下游开发者在选型/集成时应知悉：

| 缺口 | 说明 / 当前行为 |
|------|------|
| **无自动换行（no word-wrap）** | 渲染时 `WordBreak = False`：一条逻辑行始终绘制为一行，不会按控件宽度回绕到下一行。逻辑行与可见行严格一一对应。 |
| **无水平滚动 / 长行被裁剪（no horizontal scroll, long lines clipped）** | 没有水平滚动条，也没有水平自动滚动。超出内容区宽度的长行在右缘被画布**直接裁剪**；当光标移动到可见区右侧之外时也不会水平滚动跟随（光标可能被画到内容区外而不可见）。仅垂直方向有滚动条/滚轮。 |

> **v1.11 已交付：** 文本选区、区间剪贴板（`Ctrl/Cmd+A/C/X/V`）、以及按词 / `Shift` 扩展导航均已落地（见 §5），不再是缺口。
> **v1.12 已交付：** 基于快照的**撤销 / 重做**（`Ctrl/Cmd+Z`、`Ctrl/Cmd+Y` / `Ctrl/Cmd+Shift+Z`）已落地（见 §11），不再是缺口。
> **Batch ①（本批次）已交付：** `ReadOnly`、`MaxLength`（`published` 属性，见 §3）、运行期光标闪烁（约 530 ms，无头静态）均已落地，不再是缺口。
> 以上剩余条目均为可在后续 Tier-2 增强层补齐的项；当前不实现它们是经过权衡的范围决策，而非缺陷。`TTyEdit` 的相关说明亦记录于 [docs/KNOWN_GAPS.md](../KNOWN_GAPS.md)。

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
