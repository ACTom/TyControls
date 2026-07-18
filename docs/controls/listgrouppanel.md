# TTyListGroupPanel — API 参考

## 1. 概述

`TTyListGroupPanel` 是 TyControls 库中的 **Outlook 风格分组可展开列表（手风琴/accordion）** 容器，继承自 `TTyCustomControl`。它把内容组织成一列纵向堆叠的**分组（group）**：

- 每个分组有一段**标题栏（header band）**：内含一个展开/折叠三角形箭头（chevron，复用 `TTyExPanel` 的箭头几何）和分组 `Caption`。点击标题栏即切换该分组的 `Expanded` 状态（并触发 `OnGroupToggle`）。
- 分组**展开时**在其标题栏下方显示该分组的**条目（item）**，每行一个条目 `Caption`（可选 `ImageIndex`）。点击某条目即选中它（`SelectedGroup` / `SelectedItem`），并触发 `OnItemClick`。

**滚动策略**：当所有分组堆叠后的内容高度超过控件高度时，内容会被**裁剪（clip）到客户区**，并由**鼠标滚轮**平移（`FScrollOffset`）——本控件**不内嵌子滚动条**，以便把整套布局保留在纯几何函数里（便于 headless 测试）。内容比客户区矮时，偏移固定为 0。

典型用途：侧边栏导航、Outlook 式邮件/联系人分组、属性分类列表。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ListGroupPanel` |
| 外框 typeKey | `TyPanel`（**复用**：背景+边框+圆角，同 `TTyExPanel`） |
| 分组标题 typeKey | `TyListGroupHeader`（自己的键） |
| 条目行 typeKey | `TyListGroupItem`（自己的键） |
| 基类 | `TTyCustomControl`（→ `TCustomControl`，windowed，可获取焦点/鼠标捕获） |
| 默认尺寸 | 200 × 260（逻辑像素） |
| 默认标题栏高度 | 26 逻辑像素（常量 `TyListGroupDefaultHeaderHeight`；被 `--listgroup-header-height` 覆盖） |
| 默认条目行高 | 24 逻辑像素（常量 `TyListGroupDefaultItemHeight`；被 `--listgroup-item-height` 覆盖） |

```pascal
uses tyControls.ListGroupPanel;
```

**它有自己的 typeKey**：早期版本借了 `TyTreeHeaderSection` / `TyListItem`——但这两个键**同时被 `TTyTreeView` / `TTyListView` 的列头/行用着**，导致想给侧边导航换装就会毁掉数据控件的列头,侧边栏的观感**主题根本够不着**。现在拆成自己的键：

| 视觉元素 | typeKey | 用到的状态 |
|----------|---------|-----------|
| 控件外框（背景/边框/圆角） | `TyPanel` | — |
| 分组标题（**仅当设了 `background` 才填底**；右侧 chevron 取其 `TextColor`；可选左侧图标） | `TyListGroupHeader` | `:hover` / `:selected`（该分组**已展开**） |
| 条目行（选中态画成**内缩圆角药丸**，非满宽色条；可选左侧图标） | `TyListGroupItem` | `:hover` / `:active`（**选中**） / `:disabled` |

**关键设计**：分组标题**不设 `background` = 无底色带**(现代侧边栏的样子,不是默认灰带);选中条目的**内缩量与圆角由主题驱动**——控件负责内缩+抠圆角,`--listgroup-item-inset` 定内缩、`border-radius` 定圆角、`background` 定色。所有颜色/尺寸均主题驱动,控件代码中**无硬编码**。

**图标**:`AddGroup(caption, AImageIndex)` / `AddItem(gi, caption, AImageIndex)` 带图标索引,`Images: TTyVirtualImageList` 供图(同 `TTyComboBoxEx`)。索引 < 0 或未设 `Images` = 纯文字。

**尺寸令牌**(均可选,未设走兜底常量/已发布属性):`--listgroup-header-height`、`--listgroup-item-height`、`--listgroup-chevron-size`(14)、`--listgroup-icon-size`(16)、`--listgroup-icon-gap`(6)、`--listgroup-item-inset`(4)。高度令牌**优先于**已发布的 `HeaderHeight`/`ItemHeight`——"行距留白"是皮肤的决定,单实例仍可覆盖。

```css
/* base(light.tycss)给的中性外观,每个主题继承: */
TyListGroupHeader          { color: var(--muted); font-weight: var(--font-weight-bold); padding: 0px 10px; }
TyListGroupHeader:hover    { color: var(--on-surface); }
TyListGroupHeader:selected { color: var(--accent); }   /* 分组已展开 */
TyListGroupItem          { color: var(--on-surface); border-radius: var(--radius); padding: 0px 8px; }
TyListGroupItem:hover    { background: var(--surface-hover); }
TyListGroupItem:active   { background: var(--selection); color: var(--accent); }   /* 选中:淡强调色药丸 */
```

---

## 3. 公共 API

### 3.1 模型操作

| 成员 | 说明 |
|------|------|
| `function AddGroup(const ACaption: string): Integer` | 新增一个分组（默认折叠），返回其索引 |
| `function AddItem(AGroupIndex: Integer; const ACaption: string; AImageIndex: Integer = -1): Integer` | 向指定分组追加条目，返回条目索引；分组索引非法时返回 `-1` |
| `procedure Clear` | 清空所有分组、选中与滚动偏移 |
| `function GroupCount: Integer` | 分组数 |
| `function ItemCount(AGroupIndex: Integer): Integer` | 指定分组的条目数（非法索引返回 0） |
| `function ItemCaption(AGroupIndex, AItemIndex: Integer): string` | 条目文字 |
| `function ItemImageIndex(AGroupIndex, AItemIndex: Integer): Integer` | 条目图标索引（无则 `-1`） |

### 3.2 展开 / 选中

| 成员 | 说明 |
|------|------|
| `procedure ToggleGroup(AGroupIndex: Integer)` | 翻转分组展开状态（真变化时触发 `OnGroupToggle`） |
| `procedure SelectItem(AGroupIndex, AItemIndex: Integer)` | 选中条目（真变化时触发 `OnItemClick`）；传入非法索引则清空选中为 `(-1, -1)` |
| `property Expanded[AGroup: Integer]: Boolean` | 读/写某分组的展开状态（写入并触发 `OnGroupToggle`） |
| `property GroupCaption[AGroup: Integer]: string` | 读/写分组标题 |
| `property SelectedGroup: Integer` | 当前选中条目所属分组（无选中为 `-1`） |
| `property SelectedItem: Integer` | 当前选中条目索引（无选中为 `-1`） |
| `property ScrollOffset: Integer` | 只读，当前纵向滚动偏移（设备像素，`0..MaxScrollOffset`） |

### 3.3 published 属性与事件

| 成员 | 默认 | 说明 |
|------|------|------|
| `HeaderHeight: Integer` | 26 | 标题栏逻辑高度（`--listgroup-header-height` 优先） |
| `ItemHeight: Integer` | 24 | 条目行逻辑高度（`--listgroup-item-height` 优先） |
| `Images: TTyVirtualImageList` | `nil` | 分组/条目图标源（按 `ImageIndex` 取；`nil` = 纯文字） |
| `OnGroupToggle: TTyListGroupToggleEvent` | — | `procedure(Sender; AGroupIndex)`，分组展开状态真变化时触发 |
| `OnItemClick: TTyListGroupItemEvent` | — | `procedure(Sender; AGroupIndex, AItemIndex)`，选中条目真变化时触发 |
| `Align` / `Anchors` / `StyleClass` / `Controller` / `TabStop` | — | 继承自基类的常规属性 |

---

## 4. 纯几何函数（headless 直接测试）

布局在**内容坐标系**中计算（y 从第一个标题栏顶部的 0 向下增长；控件在绘制/命中测试时再叠加滚动偏移）。全部以**设备像素**表达（调用方自行缩放 `HeaderHeight` / `ItemHeight`）。

```pascal
{ 每个分组的形状：是否展开 + 条目数量。 }
TTyListGroupShape = record Expanded: Boolean; ItemCount: Integer; end;
TTyListGroupShapes = array of TTyListGroupShape;

{ 一条布局项：标题栏 or 条目，及其矩形。ItemIndex 对标题栏为 -1。 }
TTyListGroupPartKind = (lgpHeader, lgpItem);
TTyListGroupPart = record
  Kind: TTyListGroupPartKind;
  GroupIndex: Integer;
  ItemIndex: Integer;
  Rect: TRect;
end;
TTyListGroupParts = array of TTyListGroupPart;

{ 命中结果。 }
TTyListGroupHit = record
  Hit: Boolean; Kind: TTyListGroupPartKind; GroupIndex, ItemIndex: Integer;
end;
```

| 函数 | 说明 |
|------|------|
| `TyListGroupLayout(const AGroups; AHeaderH, AItemHeight, AClientW): TTyListGroupParts` | 自上而下堆叠：每个分组产出 1 个标题栏项；仅**展开**的分组再产出其条目项。空的展开分组只产出标题栏。所有矩形宽度为 `[0..AClientW]`，y 从 0 开始（不含滚动偏移），按视觉顺序返回。 |
| `TyListGroupContentHeight(const AParts): Integer` | 布局总高 = 最后一项底边（无分组时为 0）。 |
| `TyListGroupHitTest(const AParts; const APt): TTyListGroupHit` | 对**内容坐标**的点做命中测试（调用方需先把滚动偏移加回去），返回首个包含该点的布局项；未命中 `Hit=False`。 |

**已覆盖的测试场景**：全部折叠（仅标题栏）、部分展开（仅展开分组贡献条目）、条目矩形只属于展开分组、空分组仅标题栏、内容高度堆叠、标题栏 vs 条目命中、内容下方未命中、矩形满宽。

---

## 5. 交互与滚动

- **鼠标点击**：`MouseDown` 用 `TyListGroupHitTest`（把 `FScrollOffset` 加回点坐标）路由——命中标题栏 → `ToggleGroup`；命中条目 → `SelectItem`。
- **鼠标悬停**：`MouseMove` 更新悬停项，驱动标题栏/条目的 `:hover` 态；`MouseLeave` 清除。
- **滚轮**：内容溢出时，滚轮每格平移 `3 × ItemHeight`；内容适配时不滚动。折叠某分组导致内容变矮时，`ScrollOffset` 会**重新钳制**回合法范围。

---

## 6. 用法示例

```pascal
uses tyControls.ListGroupPanel;

var
  Panel: TTyListGroupPanel;
  g: Integer;
begin
  Panel := TTyListGroupPanel.Create(Self);
  Panel.Parent := Self;
  Panel.Align := alLeft;
  Panel.Width := 220;

  g := Panel.AddGroup('联系人');
  Panel.AddItem(g, 'Alice');
  Panel.AddItem(g, 'Bob');
  Panel.Expanded[g] := True;      // 默认展开这一组

  g := Panel.AddGroup('任务');
  Panel.AddItem(g, '写报告');
  Panel.AddItem(g, '发布版本');

  Panel.OnItemClick := @HandleItemClick;
  Panel.OnGroupToggle := @HandleGroupToggle;
end;
```
