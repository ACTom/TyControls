# TTyComboBox — API 参考

## 1. 概述

`TTyComboBox` 是 TyControls 库中的下拉选择控件。它在一个带边框的矩形区域内显示当前选中项的文本，右侧固定渲染一个向下的 V 形字形（chevron）作为下拉指示。

> **v1 重要限制：** TTyComboBox 在 v1 中**没有真正的弹出下拉层**。单击控件会**循环切换**到 `Items` 列表的下一项（到末尾后回到第 0 项）；浮动弹出列表是 Tier-2 计划项目。详见 [Known Gaps](../KNOWN_GAPS.md)。

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
| `OnChange` | `TNotifyEvent` | `nil` | 选中项变化时触发（仅当 `ItemIndex` 或 `Text` 实际改变时）。 |
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

#### `procedure Click`（override，protected）

单击时循环切换：

```
Items.Count = 0 → 无操作
ItemIndex < 0   → SelectItem(0)           // 选第一项
ItemIndex < Count-1 → SelectItem(ItemIndex+1)  // 选下一项
ItemIndex = Count-1 → SelectItem(0)       // 绕回第一项
```

#### `function GetStyleTypeKey: string`（override）

返回固定字符串 `'TyComboBox'`，用于主题样式查找。

### 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TNotifyEvent` | `SelectItem` 引起 `ItemIndex` 或 `Text` 真实变化时 |

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

1. **无弹出层（v1）：** 点击只是循环切换列表项，不会弹出任何浮层。用户无法通过鼠标直接跳转到指定项，只能逐项点击循环。
2. **Text 与 Items 独立：** 直接写 `Text` 属性不会修改 `ItemIndex`，也不触发 `OnChange`；应优先使用 `SelectItem` 或写 `ItemIndex`。
3. **Items 赋值用 Assign：** 写入 `Items` 属性时内部调用 `FItems.Assign(AValue)`，原有内容被替换，`ItemIndex` 和 `Text` 不自动重置，需手动调用 `SelectItem(-1)` 清空选中状态。
4. **OnChange 防重入：** 若 `SelectItem` 被调用但新值与旧值完全相同，则不触发 `OnChange`，无需在回调中判断是否重复。
5. **TabStop 默认 True：** 控件默认可获得键盘焦点，会渲染 `:focus` 状态样式。
