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
| 外框 typeKey | `TyListGroupPanel`（**自有**：背景+边框+圆角） |
| 分组标题 typeKey | `TyListGroupHeader`（自己的键） |
| 条目行 typeKey | `TyListGroupItem`（自己的键） |
| 基类 | `TTyCustomControl`（→ `TCustomControl`，windowed，可获取焦点/鼠标捕获） |
| 默认尺寸 | 200 × 260（逻辑像素） |
| 默认标题栏高度 | 26 逻辑像素（常量 `TyListGroupDefaultHeaderHeight`；被 `--listgroup-header-height` 覆盖） |
| 默认条目行高 | 24 逻辑像素（常量 `TyListGroupDefaultItemHeight`；被 `--listgroup-item-height` 覆盖） |

```pascal
uses tyControls.ListGroupPanel;
```

**三个键全部是自己的**：早期版本里,分组标题/条目行借了 `TyTreeHeaderSection` / `TyListItem`——但这两个键**同时被 `TTyTreeView` / `TTyListView` 的列头/行用着**，导致想给侧边导航换装就会毁掉数据控件的列头,侧边栏的观感**主题根本够不着**。那两个已经拆开了;剩下的**外框**直到本次才拆:它从前返回 `'TyPanel'`,于是"行能调、承载行的侧边栏本身调不了"——`TyPanel { border-radius }` 会把导航栏像卡片一样抠圆,而"贴边、无圆角"这句话无处可说。现在三层各有其名:

| 视觉元素 | typeKey | 用到的状态 |
|----------|---------|-----------|
| 控件外框（背景/边框/圆角，即侧边栏的底） | `TyListGroupPanel` | — |
| 分组标题（**仅当设了 `background` 才填底**；右侧 chevron 取其 `TextColor`；可选左侧图标） | `TyListGroupHeader` | `:hover` / `:selected`（该分组**已展开**） |
| 条目行（选中态画成**内缩圆角药丸**，非满宽色条；可选左侧图标） | `TyListGroupItem` | `:hover` / `:active`（**选中**） / `:disabled` |

**关键设计**：分组标题**不设 `background` = 无底色带**(现代侧边栏的样子,不是默认灰带);选中条目的**内缩量与圆角由主题驱动**——控件负责内缩+抠圆角,`--listgroup-item-inset` 定内缩、`border-radius` 定圆角、`background` 定色。所有颜色/尺寸均主题驱动,控件代码中**无硬编码**。

**图标**:`AddGroup(caption, AImageIndex)` / `AddItem(gi, caption, AImageIndex)` 带图标索引,`Images: TTyVirtualImageList` 供图(同 `TTyComboBoxEx`)。索引 < 0 或未设 `Images` = 纯文字。

**尺寸令牌**(均可选,未设走兜底常量/已发布属性):`--listgroup-header-height`、`--listgroup-item-height`、`--listgroup-chevron-size`(14)、`--listgroup-icon-size`(16)、`--listgroup-icon-gap`(6)、`--listgroup-item-inset`(4)。高度令牌**优先于**已发布的 `HeaderHeight`/`ItemHeight`——"行距留白"是皮肤的决定,单实例仍可覆盖。

**没有更细的子部件键**:chevron 三角、图标槽、药丸的内缩都由上表三个键 + `--listgroup-*` 尺寸令牌控制,不存在第四个键。外框键 `TyListGroupPanel` 在内置主题里与 `TyPanel` 等键写在同一条规则中(取值相同、名字独立),所以默认观感不变;第三方主题若只覆盖了 `TyPanel`,需要补上 `TyListGroupPanel`(主题层按 typeKey 全有全无地回落)。要让侧边栏贴边平铺,写 `TyListGroupPanel { border-radius: 0px; border-width: 0px; }`,**不要**去改 `TyPanel`。

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

### 设计期分组集合 Groups

```pascal
property Groups: TTyListGroups;          // published 嵌套集合,OI 可编辑、进 .lfm
// 每个 TTyListGroup:
//   Caption / ImageIndex
//   Expanded                            — 设计器默认展开,AddGroup 门面保持历史默认收起
//   Items: TTyListGroupItems            — 该组自己的条目集合
//     每条 TTyListGroupItem: Caption / ImageIndex
```

侧边栏现在可以完全在设计器里搭:双击控件(或右键「编辑分组...」)打开 Groups 集合编辑器,先加分组;选中某个分组,在 OI 里点它的 `Items` 旁的 `...` 再编辑该组的条目——先建组、组下建项,和写代码时的心智一致。属性直接在 OI 改,随 `.lfm` 存盘。代码 API(`AddGroup`/`AddItem`/`ItemCaption`/`Expanded[]` 等)全部保留,底层同一个集合。

### 整栏收缩（侧边栏折叠）

```pascal
property Collapsed: Boolean;              // True = 收成图标轨道；运行时可随时切换
property ShowCollapseTrigger: Boolean;    // 底部触发带（默认 False，现有界面不变）
property CollapsedWidth: Integer;         // 轨道宽的逻辑 px 回落值（默认 48）
property OnCollapsedChange: TNotifyEvent; // 每次真实切换触发一次
```

- `Collapsed := True` 把整个面板收窄成图标轨道：条目和分组头只画居中图标（无图标的行留空），选中胶囊保留;展开时恢复收缩前的宽度。面板通常 `Align = alLeft`,宽度变化会带动整窗重排——这就是"给内容让位"。
- `ShowCollapseTrigger` 在底部加一条整宽触发带,点击即切换;箭头方向指向边缘将要移动的方向(右停靠的面板自动镜像)。触发带的高度计入滚动视口(行不会画到带子底下,末行仍能完整滚入)。
- 主题令牌:`--listgroup-collapsed-width`、`--listgroup-trigger-height`(令牌优先于属性回落值);触发带借用 `TyListGroupHeader` 的常态样式着色。
- 从 `.lfm` 以 `Collapsed = True` 加载时保留流化的宽度;首次运行时展开由宿主自定宽度,此后收/展按捕获值往返。
- 示例:examples/antdesign 的 Sider 已开 `ShowCollapseTrigger`。

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
