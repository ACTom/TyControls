# TTyListBox — API 参考

## 1. 概述

`TTyListBox` 是 TyControls 库中的主题化列表框控件，继承自 `TTyCustomControl`。典型用途：显示一组文字条目，用户可通过鼠标或键盘选中其中一项。当条目数量超过可见区域时，右侧会自动出现一个内嵌的 `TTyScrollBar`；条目数量足够少时，滚动条自动隐藏。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ListBox` |
| typeKey（列表框本体） | `TyListBox` |
| typeKey（每一行条目） | `TyListItem` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸 | 160 × 120（逻辑像素） |

```pascal
uses tyControls.ListBox;
```

---

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Items` | `TStringList` | `''`（空列表） | 条目集合。通过赋值触发整体替换（`Assign`），同时校正 `TopIndex` 与 `ItemIndex`，自动更新滚动条并重绘。直接调用 `Items.Add` / `Items.Clear` 等方法也有效，但不触发自动夹取——`TopIndex` 会在下次重绘（`Paint` → `UpdateScrollBar`）时自动收敛到合法范围。 |
| `ItemIndex` | `Integer` | `-1` | 当前焦点行（光标行）的从 0 起始的索引；`-1` 表示无焦点。写入等价于调用 `SelectItem`：范围外的值被夹为 `-1`，并触发 `EnsureSelectionVisible`、滚动条更新及 `OnChange`。 |
| `MultiSelect` | `Boolean` | `False` | 是否允许多选。`False` 时为单选模式，行为与旧版相同；`True` 时启用多选，`Selected[]`、`SelCount`、`ClearSelection`、`SelectAll` 等多选方法生效。切换此属性会清空所有选择位。 |
| `ItemHeight` | `Integer` | `24` | 每行条目的逻辑像素高度（最小为 1）；写入时触发滚动条更新和重绘。实际像素高度在绘制时按 PPI 缩放。 |
| `TopIndex` | `Integer` | `0` | 当前最顶部可见行的索引，范围 `[0, MaxTopIndex]`，写入时自动夹紧。直接改 `Items` 后 `TopIndex` 会在下次更新时自动收敛。 |
| `OnChange` | `TNotifyEvent` | `nil` | 选中行变化时触发（`SelectItem` 中，仅当 `ItemIndex` 真正变化时触发）。 |
| `TabStop` | `Boolean` | `True` | 是否参与 Tab 键导航（构造时自动置为 `True`）。 |
| `Align` | `TAlign` | — | 父容器内的停靠方式。 |
| `Anchors` | `TAnchors` | — | 锚点布局。 |
| `StyleClass` | `string` | `''` | CSS 变体类名。 |
| `Controller` | `TTyStyleController` | `nil`（全局默认） | 关联的样式控制器。 |

### 继承的通用成员

TTyListBox 继承自 `TTyCustomControl`（`tyControls.Base`）的通用状态机制，参见 [stylecontroller.md](stylecontroller.md)。

---

## 4. 方法与事件

### public 方法

#### `procedure SelectItem(AIndex: Integer)`

选中指定索引的条目。若索引越界（`< 0` 或 `>= Items.Count`），则 `ItemIndex := -1`。方法内部：

1. 确定新索引（合法则保留，否则 `-1`）；
2. 若新索引与当前相同则退出（无操作）；
3. 更新 `FItemIndex`；
4. 调用 `EnsureSelectionVisible`（自动调整 `TopIndex` 使选中行可见）；
5. 调用 `UpdateScrollBar`；
6. 触发 `Invalidate`；
7. 若 `OnChange` 已绑定则触发。

#### `function VisibleRows: Integer`

返回当前控件高度下可见的完整行数（`Height div ScaledItemHeight`，最小为 1）。使用 `Height`（而非 `ClientHeight`）以便在无句柄的测试环境中也能正确运行。

#### `property Selected[AIndex: Integer]: Boolean`（读写，非 published）

读取或设置第 `AIndex` 行的选中位。

- **多选模式（`MultiSelect = True`）：** 直接读写内部 `FSelected` 位数组；写入时若值有变化则触发 `Invalidate` 和 `OnChange`。
- **单选模式（`MultiSelect = False`）：** 读取返回 `AIndex = ItemIndex`；写入 `True` 等价于 `SelectItem(AIndex)`；写入 `False` 无操作。

索引越界时读取返回 `False`，写入无操作。

#### `function SelCount: Integer`

返回当前选中的行数。多选模式下统计 `FSelected` 中为 `True` 的位；单选模式下返回 `0`（无选中）或 `1`（有选中）。

#### `procedure ClearSelection`

清除所有选中位（仅多选模式有效；单选模式下直接返回）。若有任何位被清除则触发 `Invalidate` 和 `OnChange`。

#### `procedure SelectAll`

选中所有行（仅多选模式有效；单选模式下直接返回）。若有任何位被设置则触发 `Invalidate` 和 `OnChange`。

---

## 5. 键盘与交互

### 单选模式（`MultiSelect = False`）

| 按键 | 行为 |
|------|------|
| `↑`（Up） | 选中前一条目（到达第 0 项后停在第 0 项） |
| `↓`（Down） | 选中后一条目（到达末项后停在末项） |
| `PageUp`（`VK_PRIOR`） | 向上翻一页（`ItemIndex -= VisibleRows`，夹至 0） |
| `PageDown`（`VK_NEXT`） | 向下翻一页（`ItemIndex += VisibleRows`，夹至末项） |
| `Home` | 选中第 0 项 |
| `End` | 选中最后一项 |

以上键通过 `SelectItem` 实现，自动触发 `EnsureSelectionVisible` 与 `OnChange`。

### 多选模式（`MultiSelect = True`）

多选模式下引入"锚点（anchor）"概念：锚点是最后一次普通点击或不带 Shift 的键盘移动时确定的行索引，`Shift+方向键/翻页键` 从锚点到当前行构成选中区间。

| 按键 | 行为 |
|------|------|
| `↑` / `↓` / `PageUp` / `PageDown` / `Home` / `End` | 移动焦点行，**清除所有选中位**，仅选中新焦点行，并将锚点设为新焦点行 |
| `Shift+↑/↓/PageUp/PageDown/Home/End` | 移动焦点行，**选中从锚点到新焦点行的连续区间**（区间外清除） |
| `Space` | 切换焦点行的选中位（不移动焦点，不影响其他行）；将锚点设为当前焦点行 |

### 鼠标交互

| 操作 | 单选模式 | 多选模式 |
|------|----------|----------|
| 普通左键点击 | 选中该行 | 清除所有选中，选中该行；锚点 = 该行 |
| `Ctrl+左键点击` | — | 切换该行选中位；焦点 = 锚点 = 该行 |
| `Shift+左键点击` | — | 选中从锚点到该行的连续区间；焦点 = 该行 |
| 鼠标左键点击（通用） | 点击后尝试获取键盘焦点 | 同左 |
| 滚轮上 | `TopIndex -= 3`（不改变 `ItemIndex`） | 同左 |
| 滚轮下 | `TopIndex += 3` | 同左 |

---

## 6. 状态与主题

### 列表框本体：typeKey `TyListBox`

| 状态 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停在控件上 |
| `:focus` | 控件拥有键盘焦点 |
| `:active` | 鼠标左键按下 |
| `:disabled` | `Enabled = False` |

### 条目子部件：typeKey `TyListItem`

每一行条目使用独立 typeKey `TyListItem` 解析样式，支持两个状态：

| 状态 | 含义 |
|------|------|
| `:hover` | 鼠标当前悬停在该行（非选中行） |
| `:active` | 该行为当前选中行（`ItemIndex` 等于该行索引） |

普通行使用 `TyListItem` 基础规则（无伪类）。

### light.tycss 示例规则

```css
TyListBox {
  background: var(--surface);
  border-color: var(--border);
  border-width: 1px;
  border-radius: var(--radius);
  padding: 4px;
}
TyListBox:focus { border-color: var(--accent); }

TyListItem { color: var(--on-surface); padding: 2px 4px; }
TyListItem:hover  { background: darken(--surface, 4%); }
TyListItem:active { background: var(--accent); color: #FFFFFF; }
```

### 内嵌滚动条

当 `Items.Count > VisibleRows` 时，右侧自动出现一个宽度为 12 逻辑像素（DPI 缩放后为物理像素）的 `TTyScrollBar`；条目减少到可见行内后自动隐藏。滚动条与列表框共用同一 `Controller`，样式由 `TyScrollBar` 规则决定。

---

## 7. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.ListBox;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

// 创建列表框
var LB: TTyListBox;
LB := TTyListBox.Create(Self);
LB.Parent := Self;
LB.SetBounds(24, 24, 200, 120);
LB.ItemHeight := 24;
LB.Items.Add('苹果');
LB.Items.Add('香蕉');
LB.Items.Add('芒果');
LB.Items.Add('草莓');
LB.Items.Add('蓝莓');
LB.ItemIndex := 0;           // 默认选中第一项
LB.OnChange := @OnListChange;

procedure TMainForm.OnListChange(Sender: TObject);
begin
  with Sender as TTyListBox do
    ShowMessage('选中：' + Items[ItemIndex]);
end;
```

完整可运行示例参见 `examples/listbox/umain.pas`。

---

## 8. 注意事项

1. **直接修改 Items 后的 TopIndex 收敛：** 直接调用 `Items.Add` / `Items.Delete` / `Items.Clear`（不经过 `SetItems`）时，不会立即夹取 `TopIndex`；夹取在下次 `Paint`（→ `UpdateScrollBar`）时发生。若需立即同步，可在修改后手动赋值 `LB.Items := LB.Items`（等价于 `SetItems`）或直接设置 `LB.TopIndex := LB.TopIndex`。
2. **ItemIndex 越界不报错：** 赋值越界值会被静默转换为 `-1`（无选中），不引发异常。
3. **VisibleRows 使用 Height 而非 ClientHeight：** 在无原生句柄的测试或离屏渲染环境中，`ClientHeight` 可能滞后；`VisibleRows` 始终使用 `Height`，两者在运行时 `BorderStyle = bsNone` 的控件上相等。
4. **滚动条宽度影响条目宽度：** 条目绘制区域会减去滚动条宽度（12 逻辑像素），确保文字不被遮盖。
5. **MultiSelect 切换重置选择：** 将 `MultiSelect` 从 `True` 改回 `False`（或反之）会清空所有 `FSelected` 位，但不重置 `ItemIndex`。
6. **ClearSelection / SelectAll 仅在多选模式有效：** 单选模式下这两个方法直接返回不做任何操作。
7. **Selected[] 非 published：** `Selected` 属性数组为 `public`，不可在 `.lfm` 中序列化；需在运行时代码中访问。
8. **OnChange 在多选操作时亦触发：** 鼠标 Ctrl/Shift 点击、键盘 Shift 扩展选区、Space 切换、`ClearSelection`、`SelectAll` 均在选择实际变化时触发 `OnChange`。
