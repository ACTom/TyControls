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
| `Style` | `TTyComboBoxStyle` | `csDropDownList` | 下拉模式，4 个值。`csDropDownList` 为只读下拉（点击任意处均展开）；`csDropDown` 显示内嵌编辑器，文本可直接输入，此时只有点击右侧箭头才展开；`csOwnerDrawFixed` / `csOwnerDrawEditableFixed` 是这两者的自绘版本，下拉行（前者还包括关闭态字段）交给 `OnDrawItem`。切换会显示/隐藏编辑器并同步 `Text`。详见 [§8.1](#81-style4-个值lcl-有-7-个且默认相反) / [§8.2](#82-自绘csownerdrawfixed--csownerdraweditablefixed--ondrawitem)。 |
| `Items` | `TStringList` | `[]`（空列表） | 可选项列表。赋值时调用 `Assign` 复制内容并触发 `Invalidate`。 |
| `ItemIndex` | `Integer` | `-1` | 当前选中项的索引。写入时等价于调用 `SelectItem(AValue)`。读取返回当前索引；-1 表示无选中项。 |
| `Text` | `string` | `''` | 当前显示的文本。独立于 `Items`，可手动赋值（不触发 `OnChange`）；`SelectItem` 同步更新此字段。 |
| `DropDownCount` | `Integer` | `8` | **（API parity 新增）** 下拉列表滚动前可见的最大行数；写入时夹紧到 `>= 1`。同时供无头度量（`ComputePopupHeight`）使用。 |
| `Sorted` | `Boolean` | `False` | **（API parity 新增）** 为 `True` 时 `Items` 保持升序（不区分大小写）；切换时按**文本**重新定位先前选中项，保持同一逻辑选中。 |
| `MaxLength` | `Integer` | `0` | 转发给内嵌编辑器。`Style = csDropDown`（可编辑）时生效，限制可输入的字符数；`csDropDownList`（只读下拉）下无可编辑文本，自然无影响。 |
| `CharCase` | `TEditCharCase` | `ecNormal` | 转发给内嵌编辑器。`Style = csDropDown` 时对输入文本做大小写变换，并同步回 `Text`。 |
| `ItemHeight` | `Integer` | `0` | **（API parity 新增）** 下拉行高（逻辑像素）。`0` = 跟随主题的 `--item-height`（密度切换仍生效）；正值钉死行高，并同时决定弹层高度（见 `ComputePopupHeight`）。子类自定义的高行（如 `TTyAdvancedComboBox` 的 40）在 `0` 时不受影响。 |
| `ItemWidth` | `Integer` | `0` | **（API parity 新增）** 下拉列表的**最小**宽度（逻辑像素）。`0` = 与字段同宽；正值让列表比字段更宽（长路径列表）。永远不会窄于字段。 |
| `TextHint` | `TCaption` | `''` | **（API parity 新增）** 字段为空时显示的灰色占位文字。`csDropDown` 下转发给内嵌 `TTyEdit`；`csDropDownList` 下由字段自己绘制（用 `TyTextHint` 主题令牌取色，不硬编码）。 |
| `ReadOnly` | `Boolean` | `False` | **（API parity 新增）** 转发给内嵌编辑器：可编辑外观但拒绝键入，下拉照常工作。`csDropDownList` 下本就无可编辑文本，无影响。 |
| `OnGetItems` | `TNotifyEvent` | `nil` | **（API parity 新增）** 见下方事件表。 |
| `OnDrawItem` | `TTyDrawItemEvent` | `nil` | **（API parity 新增）** 由应用绘制一行下拉项——`csOwnerDrawFixed` 下还包括关闭态字段。只在 `Style` 为自绘值时触发；不挂就照旧走主题默认绘制。见 [§8.2](#82-自绘csownerdrawfixed--csownerdraweditablefixed--ondrawitem)。 |
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

#### `property DroppedDown: Boolean`（读 / 写）

读：弹出窗口已创建且可见时为 `True`。写：`True` 调用 `DropDown`（虚方法，子类覆写照常生效），`False` 调用 `CloseUp`。

> **（API parity 修正）** 这里从前是 `function DroppedDown: Boolean`，于是 `Combo.DroppedDown := True`——"用按钮 / 快捷键打开下拉"的标准写法——**编译不过**。现在与 LCL 和本库的 `TTyDateTimePicker` 一致。属性是 **public 不是 published**：开合是运行期状态，不该进 `.lfm`。

#### `procedure DropDown`

打开下拉弹出列表。行为：

- 若 `Items.Count = 0`，为空操作（无弹出）。
- 首次调用时懒创建弹出 `TForm`（`BorderStyle=bsNone`，`ShowInTaskBar=stNever`，`PopupParent` 指向父窗体）。
- 弹出窗口内嵌一个 `TTyListBox`（`Align=alClient`），内容从 `Items` 复制，`ItemIndex` 与当前选中项同步。
- 弹出高度 = `Min(Items.Count, DropDownCount)` 行 × 缩放后行高 + 2px 边距（唯一实现在 `ComputePopupHeight`，无头计算与真实弹层共用）；宽度等于控件宽度；位置在控件下方（`ControlToScreen` 计算）。
- 调用 `FPopup.Show` 显示弹出窗口（非模态）。

#### `procedure CloseUp`

关闭下拉弹出列表。幂等操作，在弹出窗口未打开时调用安全无副作用。

#### 控件级列表方法（API parity 新增）

LCL 的组合框在**控件本身**上提供的一组列表方法，本控件从前只能经 `Items` 绕行——移植代码光是方法名就编译不过。

| 方法 | 说明 |
|------|------|
| `procedure Clear` | 清空 `Items`，**并且**把 `ItemIndex` 置 `-1`、`Text` 置 `''`（含内嵌编辑器）。手工调 `Items.Clear` 不等价：`ItemsChanged` → `ResyncIndexFromText` 只在 `csDropDownList` 下清空显示，`csDropDown` 下会**故意**保留字段里的自由文本，于是字段还显示着一个已经不在列表里的项。 |
| `procedure ClearSelection` | 只丢选择、不动列表，等价于 `SelectItem(-1)`（LCL 的叫法；`ItemIndex := -1` 同义，但前提是你已经知道 `-1` 是哨兵值）。 |
| `procedure AddItem(const AItem: string; AnObject: TObject)` | 追加一项及其关联对象，转发 `Items.AddObject`。**virtual + overload**：子类可以改道（`TTyComboBoxEx` 把对象放进它自己的行条目的 `Data`，因为那里的 `Objects[]` 归控件所有），也可以在旁边再加一个带图片 / 状态的重载而不遮蔽本方法。 |
| `function Count: Integer` | 项数，转发 `Items.Count`。 |

#### 编辑区选择 API（API parity 新增）

`Style = csDropDown` 时字段是一个内嵌 `TTyEdit`；以下四个成员全部转发给它，`csDropDownList` 下是安静的空操作（读 `0` / `''`，写被忽略），**不抛异常**——通用代码（例如一个格式工具条）会在不知道模式的情况下碰它们。

| 成员 | 说明 |
|------|------|
| `SelStart: Integer`（读/写） | 选区起点（UTF-8 位置）。 |
| `SelLength: Integer`（读/写） | 选区长度（UTF-8 长度）。 |
| `SelText: string`（读/写） | 选中的文本；写入等价于"替换选区"。 |
| `procedure SelectAll` | 全选字段文本。 |

#### 历史项（MRU）促位（API parity 新增）

```pascal
procedure AddHistoryItem(const AItem: string; AMaxHistoryCount: Integer;
  ASetAsText, ACaseSensitive: Boolean);
procedure AddHistoryItem(const AItem: string; AnObject: TObject;
  AMaxHistoryCount: Integer; ASetAsText, ACaseSensitive: Boolean);
```

把 `AItem` 移到第 0 行：已存在则**先删旧位置再插到最前**（不重复），超过 `AMaxHistoryCount` 从**尾部**裁掉（最久未用的先走），`ASetAsText = True` 时顺带写入 `Text`。`ACaseSensitive` 决定"已存在"怎么比。

与 LCL 一样挂在**每个**组合框上，不只是 `TTyMRUComboBox`——后者的 [`AddToHistory`](mrucombobox.md) 保留自己的名字与已发布面，但促位本身就是转调这里，只是把参数钉死成"大小写不敏感、不带对象、上限 = `MaxItems`"，另外加上它自己的两条约定（去首尾空白 / 忽略空串，以及促位后 `ItemIndex := 0`）。

> **`Sorted = True` 时**：`TStringList` 不允许在排序列表上 `InsertObject`，而 MRU 顺序按定义就不是字母序。实现会临时关掉 `Sorted` 再恢复——不会抛异常，但恢复时会重新排序，所以"促到最前"在视觉上是个空操作。要 MRU 顺序就别开 `Sorted`。

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

以上导航键直接调用 `SelectItem`，因此会触发 `OnChange`（仅当选项实际变化时）。上表描述的是默认的 `csDropDownList`（只读下拉）；`Style = csDropDown` 时字段由内嵌 `TTyEdit` 承担，关闭态可直接键入文本（带前缀自动补全，见第 3 节 `Style`）。

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
| `OnDrawItem` | `TTyDrawItemEvent` | **（API parity 新增）** `Style` 为 `csOwnerDrawFixed` / `csOwnerDrawEditableFixed` 时，每绘制一行下拉项触发一次（`csOwnerDrawFixed` 下关闭态字段也触发一次，`AState` 带 `odComboBoxEdit`）。**在画笔合成之后**跑，见 [§8.2](#82-自绘csownerdrawfixed--csownerdraweditablefixed--ondrawitem)。 |
| `OnGetItems` | `TNotifyEvent` | **（API parity 新增）** 列表**即将展开**时触发，用于按需填充 `Items`（懒加载：文件、数据库查询）。**在 `DropDown` 的"空列表就退出"守卫之前触发**——这正是关键：懒加载的组合框一开始是空的，守卫之后再触发就永远填不上，用户第一次点击什么也不会发生。`OnDropDown` 顶替不了它（那个在弹层已经显示之后才发）。 |

> 除上表外，TTyComboBox 还暴露**基线事件集**（Tier A + Tier B，因其为可聚焦的 `TTyCustomControl`）。完整清单见 [../events.md](../events.md)。
>
> **`MaxLength` / `CharCase` 何时生效：** 二者作用于**可编辑文本框**，因此只在 `Style = csDropDown` 时有意义——此时它们被转发给内嵌编辑器并正常工作。默认的 `csDropDownList` 是只读下拉，没有可编辑文本，赋值会被保存并在切到 `csDropDown` 后生效。

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
2. **两种模式：** 默认 `Style = csDropDownList` 为只读下拉，关闭态不接受任意文本输入；`Style = csDropDown` 显示内嵌编辑器，可直接键入（前缀自动补全），此时只有点击右侧箭头才展开完整列表。
3. **Text 与 Items 独立：** 直接写 `Text` 属性不会修改 `ItemIndex`，也不触发 `OnChange`；应优先使用 `SelectItem` 或写 `ItemIndex`。
4. **Items 赋值用 Assign：** 写入 `Items` 属性时内部调用 `FItems.Assign(AValue)`，原有内容被替换，`ItemIndex` 和 `Text` 不自动重置，需手动调用 `SelectItem(-1)`（或 `ClearSelection`）清空选中状态。要连列表一起清空并同步字段显示，用控件自己的 `Clear` 而非 `Items.Clear`（见第 4 节）。
5. **OnChange 防重入：** 若 `SelectItem` 被调用但新值与旧值完全相同，则不触发 `OnChange`，无需在回调中判断是否重复。
6. **TabStop 默认 True：** 控件默认可获得键盘焦点，会渲染 `:focus` 状态样式。
7. **弹出窗口生命周期：** `FPopup` 在首次 `DropDown` 时懒创建，在控件 `Destroy` 时释放。`FPopupList` 由 `FPopup` 拥有，随之释放。
8. **类型超前在下拉打开时不生效：** `UTF8KeyPress` 中无 `DroppedDown` 检查，但下拉打开时焦点转移至弹出窗口，实际键盘事件不会路由到组合框，因此 type-ahead 仅在关闭态有效。

## 8. 与 LCL `TComboBox` 已知的差异（未做）

移植 LCL 代码前请先看这里——下面这些**故意**没有对齐，写了会编译不过或行为不同。

### 8.1 `Style`：4 个值（LCL 有 7 个），且默认相反

LCL 的 `TComboBoxStyle` 有 7 个值（`stdctrls.pp:262`），默认 `csDropDown`（可编辑）；本控件的 `TTyComboBoxStyle` 有 4 个：`csDropDownList` / `csDropDown` / `csOwnerDrawFixed` / `csOwnerDrawEditableFixed`，默认 `csDropDownList`（只读）。

- **默认相反是有意保留的。** 库里和用户工程里的 `.lfm` 普遍不写 `Style`，改默认会把**每一个**已有组合框翻成可编辑的——`default` 指令一改，所有省略该属性的 `.lfm` 都被重新解释。
- **新值是追加的，不是插进去的。** `.lfm` 按标识符存 `Style`，但 published 属性上的 `default csDropDownList` 存的是**序数**，所有省略 `Style` 的 `.lfm` 都按它读。所以 `csDropDownList` 必须一直是 0。
- 注意两边的标识符**同名**：`csDropDownList` / `csDropDown` / `csOwnerDrawFixed` / `csOwnerDrawEditableFixed` 在两边都能编译且含义相同，所以只有下面 3 个缺的值会报错，默认值的差异是**静默**的。
- **仍缺的 3 个值**：`csSimple`（列表常驻在字段下方，不是弹层）、`csOwnerDrawVariable` / `csOwnerDrawEditableVariable`（逐行不同高度）。写了**编译不过**——这是有意的：给一个不兑现的枚举值，会把编译错误换成一次静默的错误渲染。

**为什么 Variable 两个值没做**：下拉行由 `TTyListBox` 画，而它只有**一个** `ItemHeight`；行循环在 `TTyListBox.RenderTo` 里，`ItemRect` / `RowAtY` / `VisibleRows` / 滚动条量程全部从这一个高度算出来。要让每行有自己的高度，必须在 `tyControls.ListBox.pas` 里开口子（本次改动不碰该文件）。`OnMeasureItem` 同理一并未做——只有 Variable 才会问它，published 一个永远不被调用的事件比没有更糟。

### 8.2 自绘（`csOwnerDrawFixed` / `csOwnerDrawEditableFixed` + `OnDrawItem`）

```pascal
type
  TTyDrawItemEvent = procedure(Sender: TObject; ACanvas: TCanvas; Index: Integer;
    ARect: TRect; AState: TOwnerDrawState) of object;
```

| 项 | 说明 |
|----|------|
| `csOwnerDrawFixed` | 只读下拉 + 自绘行，**并且自绘关闭态字段**（对应 Windows 给 `CBS_DROPDOWNLIST` 的 edit 区发 `WM_DRAWITEM`）。 |
| `csOwnerDrawEditableFixed` | 可编辑（内嵌 `TTyEdit`）+ 自绘行。字段**不**走 `OnDrawItem`：那块被真实编辑器盖住，handler 画了也看不见——LCL/Win32 也是这么分的。 |
| 没挂 `OnDrawItem` | 照旧走主题默认绘制。**光设 `Style` 永远不会把控件画空。** |
| `Index` | 是 `Items` 的下标。弹层可能装的是前缀过滤后的子集（可编辑模式的自动补全），库会替你映射回去（重名行映射到第一个，与 `PopupListChange` 的提交口径一致）。 |
| `ARect` | 行/字段实际绘制的矩形，**并且剪裁区就设成它**：handler 画到界外的部分被裁掉，不会串到邻行、边框或箭头区上。 |
| `AState` | 行：`odBackgroundPainted` 恒有（主题的行底色/选中高亮已经画好了，别再自己铺一层），选中行加 `odSelected`，控件 disabled 时加 `odDisabled + odGrayed`。字段：额外带 `odComboBoxEdit`（这是共用一个 handler 时区分"字段"与"行"的标志），聚焦时加 `odFocused`。 |
| 行高 | 由 `ItemHeight` 决定（名字里的 Fixed 就是这个意思）；`0` = 跟随主题。 |

**`ACanvas` 是本库多出来的参数。** LCL 的 `TDrawItemEvent`（`stdctrls.pp:282`）没有画布参数，host 走 `Control.Canvas`——因为 LCL 的 `TCustomComboBox` 继承自 `TWinControl`，自己 new 了一个 `TControlCanvas`（`customcombobox.inc:891`），画谁就把它的 Handle 指到谁的 DC 上。**本控件继承自 `TCustomControl`，已经有一个绑定在自己窗口上的 `Canvas`**，而下拉行是**另一个控件、另一个窗口**画的——`Control.Canvas` 不可能是它们的画布。照抄 LCL 的路子就得用另一个对象去遮蔽继承来的属性，任何走到祖先 `Canvas` 的代码都会画到错窗口上。所以画布进签名，这也是本库另外两个自绘控件（`TTyTreeView.OnDrawNode`，以及 LCL **自己**的菜单自绘 `TMenuDrawItemEvent`）的做法。`Sender` 仍是组合框，`Items[Index]` 的写法与 LCL 一致。

**回调在合成之后跑。** 画笔先把内容画进 BGRA 层，`EndPaint` 再整层贴到画布上——在那之前画到 `ACanvas` 上的东西会被抹掉。所以字段的回调在 `RenderTo` 的 `P.EndPaint` **之后**，行的回调在下拉列表 `Paint` 的 `inherited` **之后**。每次回调用 `ACanvas.SaveHandleState` / `RestoreHandleState` 包起来（**不是** `SaveDC` / `RestoreDC`：后者换回 DC 里选中的字体/画笔，而 LCL 的 `TCanvas` 还以为自己的对象仍被选中，于是从**第二次**回调起 `Font.Color := X` 变成静默空操作，用上一行的墨色画——这个缺陷在 `TTyTreeView` 和 `TTyPopupMenu` 上都发过货，见 `2477173` / `7629c14`）。

**覆盖到哪些子类**：`TTyComboBox` 自身、`TTyComboBoxEx`、`TTyCheckComboBox`（自绘时行上的**勾选框**也一并交给 handler，因为你要的就是整行自己画；点击切换不受影响，命中测试不在绘制路径上）。另外 6 个自带下拉列表的子类（`TTyAdvancedComboBox` / `TTyColorBox` / `TTyColorComboBox` / `TTyFontComboBox` / `TTyOfficeComboBox` / `TTyShellComboBox`）**行**还没接进来：它们的字段照常自绘（`RenderTo` 是唯一入口），行则仍走各自的 `PaintItemContent`。接进来的做法是两行：让它的 popup list 改继承 `TTyComboPopupList`，并在它的 `PaintItemContent` 开头加 `if TyComboCollectRowOwnerDraw(Self, ARowRect, AIndex) then Exit;`。其中 `TTyAdvancedComboBox` 与 `TTyColorBox`（含 `TTyColorComboBox`）的 `SetStyle` 目前把**任何**值都压成 `csDropDownList`，要先照 `TTyCheckComboBox` 改成 `inherited SetStyle(TyComboStylePickOnly(AValue))` 才能设进自绘模式。

```pascal
procedure TForm1.ComboDrawItem(Sender: TObject; ACanvas: TCanvas; Index: Integer;
  ARect: TRect; AState: TOwnerDrawState);
begin
  if odComboBoxEdit in AState then
    ACanvas.Font.Style := [fsBold]        // 关闭态字段
  else
    ACanvas.Font.Style := [];             // 下拉行
  if odSelected in AState then ACanvas.Font.Color := clHighlightText;
  // 底色已经画好了（odBackgroundPainted），直接写内容即可
  ACanvas.TextOut(ARect.Left + 4, ARect.Top + 2, TTyComboBox(Sender).Items[Index]);
end;

Combo.OnDrawItem := @ComboDrawItem;
Combo.Style := csOwnerDrawFixed;
```

### 8.3 其余未做项

| LCL 成员 | 现状 |
|----------|------|
| `Items: TStrings` | 本控件是 `TStringList`。`Combo.Items := Screen.Fonts`（`TStrings`）编译不过，要写 `Items.Assign(...)`。 |
| `AutoComplete` / `AutoCompleteText` / `AutoDropDown` / `AutoSelect` | 全无。本控件可编辑模式下**恒定**在每次按键时过滤并弹出建议列表（`AutoDropDown` 相当于永远开着且无法关闭），也没有"把匹配的剩余部分补进字段"的就地补全，没有获得焦点自动全选。 |
| `AutoSize`（LCL 默认 `True`） | 未 published。高度在构造函数里定死（`TyDensityHeight(..., 26)`）。 |
| `OnMeasureItem` | 无。只有 `csOwnerDrawVariable*` 会用到它，而那两个值没做（见 8.1）。 |
| `ArrowKeysTraverseList` / `Canvas` / `EmulatedTextHintStatus` / `MatchListItem` | 无。 |
