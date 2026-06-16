# TTyComboBox — API 参考

## 1. 概述

`TTyComboBox` 是 TyControls 库中的下拉选择控件。它在一个带边框的矩形区域内显示当前选中项的文本，右侧固定渲染一个向下的 V 形字形（chevron）作为下拉指示。单击控件会打开一个浮动弹出列表（`TTyListBox`），再次单击或选择列表项后自动关闭。

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ComboBox` |
| typeKey | `TyComboBox` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸 | 145 × 26（逻辑像素） |

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Items` | `TStringList` | `[]`（空列表） | 可选项列表。赋值时调用 `Assign` 复制内容并触发 `Invalidate`。 |
| `ItemIndex` | `Integer` | `-1` | 当前选中项的索引。写入时等价于调用 `SelectItem(AValue)`。读取返回当前索引；-1 表示无选中项。 |
| `Text` | `string` | `''` | 当前显示的文本。独立于 `Items`，可手动赋值（不触发 `OnChange`）；`SelectItem` 同步更新此字段。 |
| `DropDownCount` | `Integer` | `8` | **（API parity 新增）** 下拉列表滚动前可见的最大行数；写入时夹紧到 `>= 1`。同时供无头度量（`ComputePopupHeight`）使用。 |
| `Sorted` | `Boolean` | `False` | **（API parity 新增）** 为 `True` 时 `Items` 保持升序（不区分大小写）；切换时按**文本**重新定位先前选中项，保持同一逻辑选中。 |
| `MaxLength` | `Integer` | `0` | **（API parity 新增，存储但不生效）** 直接字段写入，**无任何效果**。本控件为只读下拉（`csDropDownList`），无可编辑文本可截断；该属性仅为**原生 API 对齐 / 流式往返**而 published，留待将来可编辑模式。 |
| `CharCase` | `TEditCharCase` | `ecNormal` | **（API parity 新增，存储但不生效）** `SetCharCase` 仅赋值字段，**不**改写显示文本（只读下拉无可编辑文本）；同样仅为 API 对齐保留。 |
| `OnChange` | `TNotifyEvent` | `nil` | 选中项变化时触发（仅当 `ItemIndex` 或 `Text` 实际改变时）。 |
| `OnSelect` | `TNotifyEvent` | `nil` | **（API parity 新增）** 仅 **用户驱动** 的选择（下拉选取 / 键盘导航）后触发；程序化设置 `ItemIndex` **不**触发。 |
| `OnDropDown` | `TNotifyEvent` | `nil` | **（API parity 新增）** 下拉列表打开时触发。 |
| `OnCloseUp` | `TNotifyEvent` | `nil` | **（API parity 新增）** 下拉列表收起时触发。 |
| `TabStop` | `Boolean` | `True` | 是否参与键盘 Tab 焦点循环。 |
| `Align` | `TAlign` | — | 布局对齐方式（继承自 `TControl`）。 |
| `Anchors` | `TAnchors` | — | 锚点布局（继承自 `TControl`）。 |
| `StyleClass` | `string` | `''` | CSS 变体类名，对应 tycss 中的 `.class` 选择器。 |
| `Controller` | `TTyStyleController` | `nil`（使用全局默认） | 关联的样式控制器。 |

### 内部只读字段（非 published）

- `FItems: TStringList` — 内部拥有的字符串列表，在 `Create` 中创建，`Destroy` 中释放。
- `FItemIndex: Integer` — 当前选中索引，初始为 `-1`。
- `FText: string` — 当前文本，初始为 `''`。

## 4. 方法与事件

### public 方法

#### `procedure SelectItem(AIndex: Integer)`

核心选择方法。行为：

- 若 `AIndex` 在 `[0, Items.Count-1]` 范围内，设置 `FItemIndex := AIndex`，`FText := Items[AIndex]`。
- 若 `AIndex` 越界（包括负值），清空选中状态：`FItemIndex := -1`，`FText := ''`。
- 若新索引与新文本均与当前值相同，**不触发任何操作**（防止重复刷新）。
- 有效变化时：触发 `Invalidate`；若 `OnChange` 已赋值则调用之。

#### `function DroppedDown: Boolean`

只读属性函数。当弹出窗口已创建且可见时返回 `True`，否则返回 `False`。

#### `procedure DropDown`

打开下拉弹出列表。行为：

- 若 `Items.Count = 0`，为空操作（无弹出）。
- 首次调用时懒创建弹出 `TForm`（`BorderStyle=bsNone`，`ShowInTaskBar=stNever`，`PopupParent` 指向父窗体）。
- 弹出窗口内嵌一个 `TTyListBox`（`Align=alClient`），内容从 `Items` 复制，`ItemIndex` 与当前选中项同步。
- 弹出高度 = `Min(8, Items.Count)` 行 × 缩放后行高 + 2px 边距；宽度等于控件宽度；位置在控件下方（`ControlToScreen` 计算）。
- 调用 `FPopup.Show` 显示弹出窗口（非模态）。

#### `procedure CloseUp`

关闭下拉弹出列表。幂等操作，在弹出窗口未打开时调用安全无副作用。

#### `procedure Click`（override，protected）

切换下拉状态：

```
DroppedDown = True  → CloseUp
DroppedDown = False → DropDown
```

不再循环切换列表项（v1 的循环行为已移除）。

#### `function GetStyleTypeKey: string`（override）

返回固定字符串 `'TyComboBox'`，用于主题样式查找。

#### 关闭态键盘导航（`KeyDown` override）

下拉列表**关闭**时，以下键直接在控件本身操作：

| 按键 | 行为 |
|------|------|
| `↓`（Down） | 选中下一项（若无选中则选第 0 项；已到末项则停留） |
| `↑`（Up） | 选中上一项（若无选中则选第 0 项；已到首项则停留） |
| `Home` | 选中第 0 项 |
| `End` | 选中最后一项 |
| `Alt+↓` 或 `F4` | 打开下拉列表（已打开则关闭） |
| `ESC` | 关闭下拉列表（未打开时无操作） |

以上导航键直接调用 `SelectItem`，因此会触发 `OnChange`（仅当选项实际变化时）。此控件为**只读下拉**——关闭态不支持直接文本输入编辑（可编辑模式留后续 spec）。

#### 类型超前（Type-ahead，`UTF8KeyPress` override）

在控件获得焦点且下拉列表**关闭**时，按可打印字符键会累积前缀缓冲并自动跳选：

- 按键追加到内部缓冲 `FTypeAhead`；
- 在 `Items` 中从**当前选中项之后**开始循环搜索，找到第一个**前缀匹配**（不区分大小写）的项并调用 `SelectItem`；
- 超过约 **600 ms** 无新按键后，下次按键会重置缓冲（从新字符重新开始匹配）。

例：`Items = ['Apple', 'Apricot', 'Banana']`，当前选中 `Apple`，先按 `A` → 跳到 `Apricot`；再等待 600 ms 后按 `B` → 重置后跳到 `Banana`。

### 关闭路径

弹出窗口通过以下三条路径关闭：

1. **失焦关闭**：`FPopup.OnDeactivate` → `CloseUp`（点击弹出窗口外部时触发）。
2. **ESC 键**：弹出窗口的 `KeyPreview=True`，`OnKeyDown` 捕获 `VK_ESCAPE` → `CloseUp`；组合框自身的 `KeyDown` 也处理 `VK_ESCAPE`（当 `DroppedDown=True` 时）。
3. **列表项选中**：`TTyListBox.OnChange` 触发 → `SelectItem` + `CloseUp`。

### 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TNotifyEvent` | `SelectItem` 引起 `ItemIndex` 或 `Text` 真实变化时（含程序化） |
| `OnSelect` | `TNotifyEvent` | **（API parity 新增）** 仅用户驱动的选择（下拉选取 / 关闭态键盘导航）实际改变选项后触发；程序化 `ItemIndex :=` 不触发。在 `OnChange` 之后发出。 |
| `OnDropDown` | `TNotifyEvent` | **（API parity 新增）** `DropDown` 实际打开弹出列表时触发。 |
| `OnCloseUp` | `TNotifyEvent` | **（API parity 新增）** `CloseUp` 关闭弹出列表时触发。 |

> 除上表外，TTyComboBox 还暴露**基线事件集**（Tier A + Tier B，因其为可聚焦的 `TTyCustomControl`）。完整清单见 [../events.md](../events.md)。
>
> **`MaxLength` / `CharCase` 为何不生效：** 二者在原生组合框中作用于**可编辑文本框**。本控件是只读下拉（`csDropDownList`），没有可编辑文本，因此它们被 published 仅为**原生 API 对齐**与 DFM/LFM 流式往返，对显示的选中文本无任何影响，留作将来可编辑模式的预留接口。

## 5. 状态与主题

### 状态

TTyComboBox 继承 `TTyCustomControl` 的状态机制，支持以下状态（由 `CurrentStates` 计算）：

| 状态常量 | 触发条件 |
|----------|----------|
| `tysNormal` | 正常（非其他状态） |
| `tysHover` | 鼠标悬停 |
| `tysActive` | 鼠标左键按下 |
| `tysFocused` | 键盘焦点 |
| `tysDisabled` | `Enabled = False` |

### light.tycss 内置规则

```css
TyComboBox {
  background: var(--surface);       /* #FFFFFF */
  color: var(--on-surface);         /* #1F2937 */
  border-color: var(--border);      /* #D1D5DB */
  border-width: 1px;
  border-radius: var(--radius);     /* 6px */
  padding: 4px;
  font-size: 10px;
}
TyComboBox:hover    { border-color: darken(--border, 10%); }
TyComboBox:focus    { border-color: var(--accent); /* #3B82F6 */ }
TyComboBox:disabled { opacity: 0.5; }
```

内置主题没有定义命名变体（`.class`）；可通过 `StyleClass` 添加自定义变体。

### 布局细节

- 右侧 chevron 区域固定宽度 18 逻辑像素（由 `ButtonWidthLogical` 返回）。
- 文本区域从 `Padding.Left` 开始，右边界止于 chevron 区域左边缘，上下各留 `Padding.Top/Bottom`。
- Chevron 字形颜色跟随当前样式的 `TextColor`，线宽 2px。

## 6. 代码示例

### 基本用法

```pascal
uses tyControls.ComboBox;

var
  Combo: TTyComboBox;
begin
  Combo := TTyComboBox.Create(Self);
  Combo.Parent := Self;
  Combo.Left := 20;
  Combo.Top := 40;
  Combo.Items.Add('选项一');
  Combo.Items.Add('选项二');
  Combo.Items.Add('选项三');
  Combo.ItemIndex := 0;        // 初始选中第一项
  Combo.OnChange := @OnComboChange;
end;

procedure TForm1.OnComboChange(Sender: TObject);
begin
  ShowMessage('当前选中：' + TTyComboBox(Sender).Text);
end;
```

### 程序化控制弹出层

```pascal
// 手动打开下拉
Combo.DropDown;

// 检查是否打开
if Combo.DroppedDown then
  Combo.CloseUp;  // 手动关闭
```

### 越界清空示例

```pascal
// Items.Count = 3，当前 ItemIndex = 2
Combo.SelectItem(5);   // 越界 → ItemIndex = -1, Text = ''
Combo.SelectItem(-1);  // 同上
```

### 使用 StyleClass 添加自定义变体

```pascal
Combo.StyleClass := 'compact';
// 在 tycss 中：
// TyComboBox.compact { padding: 2px; font-size: 9px; }
```

## 7. 注意事项

1. **单击切换弹出层：** 单击控件会打开或关闭下拉列表，不再循环切换 `Items`。
2. **只读下拉：** 当前实现为只读模式，关闭态不接受任意文本输入；可编辑模式留后续 spec 实现。
3. **Text 与 Items 独立：** 直接写 `Text` 属性不会修改 `ItemIndex`，也不触发 `OnChange`；应优先使用 `SelectItem` 或写 `ItemIndex`。
4. **Items 赋值用 Assign：** 写入 `Items` 属性时内部调用 `FItems.Assign(AValue)`，原有内容被替换，`ItemIndex` 和 `Text` 不自动重置，需手动调用 `SelectItem(-1)` 清空选中状态。
5. **OnChange 防重入：** 若 `SelectItem` 被调用但新值与旧值完全相同，则不触发 `OnChange`，无需在回调中判断是否重复。
6. **TabStop 默认 True：** 控件默认可获得键盘焦点，会渲染 `:focus` 状态样式。
7. **弹出窗口生命周期：** `FPopup` 在首次 `DropDown` 时懒创建，在控件 `Destroy` 时释放。`FPopupList` 由 `FPopup` 拥有，随之释放。
8. **类型超前在下拉打开时不生效：** `UTF8KeyPress` 中无 `DroppedDown` 检查，但下拉打开时焦点转移至弹出窗口，实际键盘事件不会路由到组合框，因此 type-ahead 仅在关闭态有效。
