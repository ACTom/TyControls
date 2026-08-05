# TTyButtonGroup

## 1. 概述

`TTyButtonGroup` 是 TyControls 库中的**分段按钮条**（segmented control）控件，继承自 `TTyCustomControl`。它把 N 个标题渲染成一排**紧邻的分段单元**（segment），每段外观像一个按钮，共同拼成一个整体控件——最左段圆左角、最右段圆右角、中间各段方角。支持两种选择模式：

- **单选（radio，默认）**：像 iOS/桌面的分段控件，同一时刻只有一段选中，由 `ItemIndex` 表达（`-1` = 无选中）。
- **多选（toggle set）**：`MultiSelect := True` 时每段是一个独立的开关，可任意组合，由 `IsSelected` / `SetSelected` 读写。

选中段以主题的 `:selected` 状态样式绘制，悬停段以 `:hover` 绘制。典型用途：视图切换器（列表/网格）、对齐方式选择、粗体/斜体/下划线一类的格式工具条。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ButtonGroup` |
| `GetStyleTypeKey` 返回值 | `'TyButtonGroup'`（**自有键**） |
| 基类 | `TTyCustomControl`（`tyControls.Base`） |
| 默认尺寸 | 240 × 30（逻辑像素，`Create` 中设置） |

> **自有 `TyButtonGroup` 键：** 从前它返回 `'TyButton'`，于是「一个按钮」和「一条选择条」在主题层是同一样东西——皮肤给按钮设了胶囊圆角，这条分段条就变成两头圆、接缝方，而皮肤**没有任何选择器**能纠正它。现在每段解析的都是 `TyButtonGroup`：选中段 `TyButtonGroup:selected`（等价 `:checked`），悬停段 `TyButtonGroup:hover`，`Enabled = False` 时全段 `TyButtonGroup:disabled`。`themes/light.tycss` 把 `TyButtonGroup` 并列写进了 `TyButton` 那条规则的选择器列表，所以默认外观与从前一致；但**要调它的外观请写 `TyButtonGroup`，不要改 `TyButton`**——那会改掉全应用的每一个按钮。

```pascal
uses tyControls.ButtonGroup;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Items` | `TStrings` | `[]`（空列表） | 各分段的标题列表。内部由 `TStringList` 支撑（以获得 `OnChange`），声明类型为 `TStrings`。写入时调用 `Assign` 复制内容；列表变化（增删改）自动重算分段布局、夹紧越界的 `ItemIndex` 并重绘。标题支持 `&` 助记符显示（下划线）。 |
| `MultiSelect` | `Boolean` | `False` | `False` = 单选（`ItemIndex`）；`True` = 多选（`IsSelected` / `SetSelected`）。切换模式会**清空全部选中**（避免残留位），并把 `ItemIndex` 复位为 `-1`。 |
| `ItemIndex` | `Integer` | `-1` | **单选模式**下当前选中的分段索引，`-1` = 无选中。写入越界值等价于 `-1`；实际改变时触发 `OnSelectionChange`，设为当前值不触发。声明 `default -1`。多选模式下此属性不代表选中集（用 `IsSelected`）。 |
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式。 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 锚点布局。 |

### 自有 public 方法

| 成员 | 签名 | 说明 |
|------|------|------|
| `IsSelected` | `function IsSelected(AIndex: Integer): Boolean` | 段 `AIndex` 是否选中。单选：`AIndex = ItemIndex`；多选：其内部位。越界返回 `False`。 |
| `SetSelected` | `procedure SetSelected(AIndex: Integer; AValue: Boolean)` | 设置段 `AIndex` 的选中标志。多选：置位/清位（实际改变才触发 `OnSelectionChange`）。单选：`AValue = True` 选中它（`= ItemIndex := AIndex`）；`AValue = False` 仅当它正是当前选中段时才清除。越界为安全空操作。 |
| `Count` | `function Count: Integer` | 分段数量（`= Items.Count`）。 |

### 继承的通用成员

`TTyButtonGroup` 从 `TTyCustomControl` 继承以下 published 属性：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分；作用于**整条**（每段都用同一变体，如 `'primary'` 让全部分段用主色按钮主题） |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器；为 `nil` 时回退到全局默认 |

### 状态跟踪字段（protected，不 published）

| 字段 | 类型 | 说明 |
|------|------|------|
| `FHoverSeg` | `Integer` | 鼠标悬停的分段索引（`-1` = 无），触发该段的 `:hover` 绘制 |
| `FSelected` | `array of Boolean` | 多选模式的位集，始终与 `Items.Count` 同长 |

---

## 4. 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnSelectionChange` | `TNotifyEvent` | 选中集**实际改变**后触发。单选：`ItemIndex` 变为不同值（点同一段的无操作、设为当前值均不触发）。多选：某段被点击切换、或 `SetSelected` 改变了某段的位。 |

> 除 `OnSelectionChange` 外，`TTyButtonGroup` 还暴露**基线事件集**（Tier A 鼠标 / 通用事件 + Tier B 键盘 / 焦点事件，因其为可聚焦的 `TTyCustomControl`）。完整清单见 [../events.md](../events.md)。

---

## 5. 状态与主题

### 支持的伪类状态（每个分段独立解析）

| 伪类 | 触发条件 |
|------|----------|
| `:selected`（别名 `:checked`） | 该段被选中（单选：`= ItemIndex`；多选：其位为 `True`） |
| `:hover` | 鼠标悬停在该段上（`FHoverSeg`） |
| `:disabled` | `Enabled = False`（优先级最高，全段禁用，不叠加其它状态） |
| `:normal` | 既未选中也未悬停的普通段 |

### 解析的主题键

| typeKey | 画什么 |
|---------|--------|
| `TyButtonGroup` | **每一段**都用它解析：段背景 `background`、段边框 `border-color` / `border-width`、标题 `color` / `font-*` / `padding`；整条的外圆角取自它的 `border-radius`（只作用于最左段左侧两角、最右段右侧两角）。 |

**没有子部件键。** 分段没有自己的 typeKey——形如 `TyButtonGroupItem` 的键**并不存在**（子部件拆键属于本轮有意推迟的扩展，别往主题里写）。整条也没有独立的「轨道」底色：`Items` 为空时控件只填父背景，不画自己的底。段与段的区分完全靠每段自身的边框在接缝处叠合。

> **随库主题的覆盖情况：** 选中段解析为 `TyButtonGroup` + `[tysSelected]`。全部 20 份随库样式表
> 都已把 `TyButtonGroup` 列进 `TyButton` 的每一条规则——含 `.ghost:selected` 与 `:disabled`，
> 所以 `StyleClass := 'ghost'` 的选中反馈和 `Enabled := False` 的变淡都是开箱可用的。
> （唯一例外 `system.tycss` 没有 `:disabled`，但那是因为它**连 `TyButton:disabled` 都没写**，
> 两者一致，非本控件特有。）
>
> **裸 `TyButtonGroup:selected` 仍未定义**——随库主题只给 `.ghost` 变体写了选中态。想让默认变体
> 也有可见选中反馈，在自己的主题里补一条：
>
> ```css
> TyButtonGroup:selected { background: var(--surface-active); border-color: var(--accent); }
> ```
>
> **第三方主题注意：** base 层是**按 typeKey 全有全无**的。你的 `.tycss` 只要写过 `TyButtonGroup`，
> 内置基础层对这个键就整体不再兜底——上面那些状态你得自己写全，或者干脆一条别写、让它完全继承。
> 详见 [tycss-reference §8.1](../tycss-reference.md)。

### 渲染细节

- **等分布局：** 各分段等宽平分客户区宽度，**最后一段吸收整数除法的余数**，因此拼贴严丝合缝覆盖 `[0, Width)`，段间无缝隙、无重叠。
- **外圆角、内方角：** 圆角半径取自解析后的基础样式（`border-radius` 令牌）；仅最左段圆其左侧两角、最右段圆其右侧两角，中间各段与接缝处为方角，整体读作一个圆角胶囊。
- **接缝分隔线：** 相邻两段各自描边，共享接缝上两条 1px 边框叠合读作单条分隔线；这样每段的状态边框（如选中/accent 描边）都能在自身边缘可见。
- **标题：** 每段标题在段内水平垂直居中，按样式的左右 `padding` 内缩；超宽裁剪（`clipping = True`）。
- **无头安全：** 0 段时绘制与命中测试均不崩溃（只填基础背景、不做任何分段计算）。

---

## 6. 纯布局辅助函数（可单元测试）

单元级导出两个**纯函数**（无控件状态），供命中测试与布局，并被测试直接覆盖：

| 函数 | 签名 | 说明 |
|------|------|------|
| `TySegmentAt` | `function TySegmentAt(AX, AWidthPx, ACount: Integer): Integer` | 设备像素横坐标 `AX`（从组左边缘起）落在第几段。等分，最后一段吸收余数。`ACount <= 0`、零宽、或 `AX` 不在 `[0, AWidthPx)` 时返回 `-1`。 |
| `TySegmentRect` | `function TySegmentRect(AIndex, AWidthPx, AHeightPx, ACount: Integer): TRect` | 第 `AIndex` 段的设备像素矩形。等宽从左到右拼贴，最后一段延伸到 `AWidthPx`（吸收余数）。索引越界或 `ACount <= 0` 返回空矩形。 |

```pascal
// 300px 宽、3 段：等分 100px。
TySegmentAt(50,  300, 3);   // -> 0
TySegmentAt(150, 300, 3);   // -> 1
TySegmentAt(250, 300, 3);   // -> 2
TySegmentAt(-1,  300, 3);   // -> -1（越界）
TySegmentRect(2, 301, 30, 4).Right;   // -> 301（末段吸收余数，覆盖全宽）
```

---

## 7. 单选 vs 多选

| | 单选（默认） | 多选 |
|--|------|------|
| `MultiSelect` | `False` | `True` |
| 选中集表达 | `ItemIndex`（`-1` = 无） | 每段独立位（`IsSelected` / `SetSelected`） |
| 点击行为 | 选中该段（点已选中段无操作） | 切换该段的选中位 |
| `OnSelectionChange` | `ItemIndex` 改变时 | 任一段位改变时 |
| 典型用途 | 视图/模式切换器 | 格式工具条（粗体/斜体/下划线组合） |

> 切换 `MultiSelect` 会清空全部选中并把 `ItemIndex` 复位为 `-1`，避免两种表达之间残留状态。

---

## 8. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.ButtonGroup;

// 加载主题（通常在窗体 Create 顶部执行一次）
TyDefaultController.LoadTheme('themes/light.tycss');

// —— 单选：视图切换器 ——
var ViewSwitch: TTyButtonGroup;
ViewSwitch := TTyButtonGroup.Create(Self);
ViewSwitch.Parent := Self;
ViewSwitch.SetBounds(20, 20, 240, 30);
ViewSwitch.StyleClass := 'ghost';           // 需主题里有 TyButtonGroup.ghost:selected 才有可见选中态
ViewSwitch.Items.Add('列表');
ViewSwitch.Items.Add('网格');
ViewSwitch.Items.Add('详情');
ViewSwitch.ItemIndex := 0;                   // 默认选中第一段
ViewSwitch.OnSelectionChange := @ViewChanged;

procedure TMainForm.ViewChanged(Sender: TObject);
begin
  case (Sender as TTyButtonGroup).ItemIndex of
    0: ShowListView;
    1: ShowGridView;
    2: ShowDetailView;
  end;
end;

// —— 多选：格式工具条 ——
var FormatBar: TTyButtonGroup;
FormatBar := TTyButtonGroup.Create(Self);
FormatBar.Parent := Self;
FormatBar.SetBounds(20, 60, 180, 30);
FormatBar.MultiSelect := True;
FormatBar.Items.Add('B');
FormatBar.Items.Add('I');
FormatBar.Items.Add('U');
FormatBar.SetSelected(0, True);              // 预置“粗体”开启
FormatBar.OnSelectionChange := @FormatChanged;

procedure TMainForm.FormatChanged(Sender: TObject);
var G: TTyButtonGroup;
begin
  G := Sender as TTyButtonGroup;
  ApplyBold(G.IsSelected(0));
  ApplyItalic(G.IsSelected(1));
  ApplyUnderline(G.IsSelected(2));
end;
```

---

## 9. 注意事项

- **主题化写 `TyButtonGroup`，别写 `TyButton`：** 分段用本控件自己的令牌绘制，`StyleClass` 作用于整条（全部分段同一变体）；主题化时写 `TyButtonGroup` / `TyButtonGroup:selected` / `TyButtonGroup:hover`。去改 `TyButton` 只会波及全应用的按钮，改不动这条分段条。
- **选中反馈依赖 `:selected` 规则：** 若主题未为当前变体定义 `TyButtonGroup:selected`，选中段与普通段外观相同；随库的 light / dark / auto 目前正是这种情况，需自行补规则（见第 5 节）。
- **`Items` 赋值用 `Assign`：** 写入 `Items` 属性时内部 `Assign` 整体替换；`ItemIndex` 不自动重置，仅在超过新上界时被夹到 `-1`（多选位集同步重设长度）。
- **`ItemIndex` 与多选：** 多选模式下 `ItemIndex` 不表达选中集（切模式时已复位为 `-1`）；请用 `IsSelected` / `SetSelected`。
- **末段吸收余数：** 当客户区宽度不能被段数整除时，最后一段略宽以吸收余数，保证无缝拼贴。
- **DFM 序列化：** `ItemIndex` 声明 `default -1`、`MultiSelect` 声明 `default False`，取默认值时不写入 `.lfm`/`.dfm`。
- **无头安全：** 0 段时 `Paint` 与命中测试都不崩溃；命中不到任何段的点击为空操作。

---

参见 [[TTyButton]] —— 视觉原型相同，但两者是各自独立的 typeKey（`TyButton` / `TyButtonGroup`），主题里要分别定义。语义更接近的近亲是分段控件 `TySegmented` / `TySegmentedItem`。
- **右到左镜像：暂不支持，且是刻意的。** `TySegmentAt` 直接把点击的原始 x 映射成分段下标（`MouseDown` / `MouseMove` 都走它）。只反转绘制的话，点击会选中鼠标位置镜像点上的那一段——在一个专门用来"选"的控件上尤其难发现。理由与 [dropbuttons.md](dropbuttons.md) 相同，同样由 `tests/test.rtl.pas` 的 `TRtlExclusionTest` 钉住。
