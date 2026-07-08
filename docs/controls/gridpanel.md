# TTyGridPanel — API 参考

## 1. 概述

`TTyGridPanel` 是 TyControls 库中的**固定网格布局容器**，继承自 [`TTyPanel`](panel.md)。它把客户区划分为「列 × 行」的单元格网格，把每个已分配的子控件摆放到它所占据（可跨列 / 跨行）的单元格并集矩形内，并在四周内缩一个 `Spacing` 边距。

典型用途：把一批子控件按行列对齐地铺开——表单的「标签 + 输入框」两列布局、按钮阵列、仪表盘卡片网格等；无需为每个子控件手算坐标，改变面板尺寸时所有单元格按各自的**轨道尺寸策略**自动重新分配空间。

它是**真正的 LCL 容器**（有窗口句柄），子控件直接以其为 `Parent`；外观（边框 / 圆角 / 背景 / 内边距）全部沿用 `TyPanel` 主题——网格布局只决定子控件的位置与大小，不额外绘制格线。

**核心价值 = 正确的布局数学**：布局解算被拆成两个**纯单元级函数**（`TyGridTrackSizes` / `TyGridCellRect`），可脱离窗口句柄直接测试；控件本身只是一层薄壳——在 `Resize`、`SetCell` 或轨道 / 计数 / 间距变化时，跑一遍纯解算器再对每个子控件 `SetBounds`。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.GridPanel` |
| `GetStyleTypeKey` 返回值 | `'TyPanel'`（**继承自 `TTyPanel`，未重写**——不新增任何 `.tycss`） |
| 基类 | `TTyPanel`（继承自 `TTyCustomControl` → `TCustomControl`） |
| 默认尺寸 | 200 × 150（逻辑像素） |
| 默认网格 | 2 列 × 2 行，全部为 `tgtStar`（等分）轨道 |

```pascal
uses tyControls.GridPanel;
```

> **主题说明：** `TTyGridPanel` 刻意复用 `TyPanel` 的 typeKey，因此在 `.tycss` 中给 `TyPanel` 写的所有规则都会应用到网格面板本体；无需为它单独写样式。如需与普通面板区分，用 `StyleClass` 加一个类选择器（如 `TyPanel.grid { … }`）。

---

## 3. 轨道尺寸策略（`TTyGridTrackKind`）

每条列 / 行「轨道」以三种方式之一定尺寸：

| 取值 | 含义 | `Value` 语义 |
|------|------|--------------|
| `tgtAbsolute` | 固定像素长度 | 该轨道的逻辑像素数（`< 0` 夹为 0） |
| `tgtPercent` | 占**原始可用长度**的百分比 | 百分比 `0..100`（`≥ 100` 取满、`≤ 0` 取 0） |
| `tgtStar` | 「星 / 自动」轨道 | 忽略 `Value`；**均分**其余轨道用剩的空间 |

轨道记录类型：

```pascal
type
  TTyGridTrackKind = (tgtAbsolute, tgtPercent, tgtStar);
  TTyGridTrack = record
    Kind: TTyGridTrackKind;
    Value: Integer;
  end;
  TTyGridTracks = array of TTyGridTrack;
```

**解算顺序**（与 WPF / CSS Grid 语义一致）：
1. `tgtAbsolute` 轨道先各取自身像素；
2. `tgtPercent` 轨道取「百分比 × 可用长度」（可用长度 = 轴长 − 轨间空隙，**不**因绝对轨道而减小）；
3. 剩余空间（可用 − 绝对 − 百分比，下限 0）在所有 `tgtStar` 轨道间**均分**，**最后一个** star 轨道吸收整数除法的余数（保证总和精确）。

**超额分配**（绝对 + 百分比之和超过可用长度）永不产生负轨道，星轨道池夹到 0。

---

## 4. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `ColumnCount` | `Integer` | `2` | 列数。**增大**时新增列以 `tgtStar` 填充；**减小**时截去尾部列。落在新边界外的单元格分配会解析为空矩形（不报错）。 |
| `RowCount` | `Integer` | `2` | 行数，语义同上。 |
| `Spacing` | `Integer` | `4` | 子控件在其所占单元格矩形内四周内缩的边距（逻辑像素），从而也充当相邻单元格之间的间隙；负值夹为 0。 |

### 继承自 TTyPanel 的 published 成员

| 属性 | 说明 |
|------|------|
| `Caption` / `Alignment` | 面板本体标题（网格场景一般不用；若设置会被子控件覆盖）。 |
| `Align` / `Anchors` | 在父容器内的停靠 / 锚点；常设 `alClient` 让网格填满宿主。 |
| `StyleClass` | CSS 变体类名，对应 `TyPanel.classname` 选择器。 |
| `Controller` | 关联的样式控制器；`nil` 时回退到全局 `TyDefaultController`。 |

---

## 5. 方法

### 轨道尺寸设置

| 方法 | 签名 | 说明 |
|------|------|------|
| `SetColumnStyle` | `(AIndex: Integer; AKind: TTyGridTrackKind; AValue: Integer = 0)` | 设置第 `AIndex` 列的尺寸策略。`AIndex` 超过当前列数时**自动扩展**列数组（中间空缺以 `tgtStar` 补齐），便于给尚未声明的轨道定尺寸；触发重排。 |
| `SetRowStyle` | `(AIndex: Integer; AKind: TTyGridTrackKind; AValue: Integer = 0)` | 设置第 `AIndex` 行的尺寸策略，语义同上。 |
| `ColumnStyle` | `(AIndex: Integer): TTyGridTrack` | 读回某列的尺寸策略；越界索引返回 `tgtStar / 0` 默认值。 |
| `RowStyle` | `(AIndex: Integer): TTyGridTrack` | 读回某行的尺寸策略。 |

### 单元格分配（代码优先 API）

| 方法 | 签名 | 说明 |
|------|------|------|
| `SetCell` | `(AControl: TControl; ACol, ARow: Integer; AColSpan: Integer = 1; ARowSpan: Integer = 1)` | 把 `AControl`（须是本面板的子控件）放到 `(ACol, ARow)` 单元格，跨 `AColSpan` 列、`ARowSpan` 行。对同一控件重复调用即**更新**其分配。跨度 `< 1` 夹为 1；触发重排。分配以**控件为键**存入内部列表。 |
| `RemoveCell` | `(AControl: TControl)` | 移除某控件的单元格分配（控件本身留在原地，不再被布局）。未分配则为 no-op。 |
| `GetCell` | `(AControl; out ACol, ARow, AColSpan, ARowSpan): Boolean` | 查询某控件是否已分配并回填参数（供测试 / 调用者用）。 |
| `CellCount` | `: Integer` | 当前已分配子控件数。 |

> **子控件释放自动解绑：** 每个被 `SetCell` 分配的控件都通过 `FreeNotification` 被跟踪；控件被 `Free`（或改父）时，`Notification` 会自动丢弃它的单元格分配，不留悬挂键。

---

## 6. 纯函数（单元级，可 headless 测试）

单元 `tyControls.GridPanel` 导出以下纯函数，是网格布局的可测核心（无控件状态、无窗口句柄）：

| 函数 | 签名 | 说明 |
|------|------|------|
| `TyGridTrackSizes` | `(ATotal, ASpacing: Integer; const ATracks: TTyGridTracks): TTyGridIntArray` | 把一条轴上的轨道解算为具体像素长度：先绝对、再百分比（取原始可用长度）、最后星轨道均分剩余（末位吸收余数）。永不为负；超额分配夹取。空轨道列表返回空数组。 |
| `TyGridCellRect` | `(const AColX, AColW, ARowY, ARowH: TTyGridIntArray; ACol, ARow, AColSpan, ARowSpan: Integer): TRect` | 给定各列的左起点 / 宽、各行的上起点 / 高，返回子控件所跨单元格的**并集矩形**。跨度夹取到网格边界；越界 `ACol/ARow`（或空轨道）返回空矩形 `Rect(0,0,0,0)`。 |
| `TyGridTrackOrigins` | `(const ALengths: TTyGridIntArray; ASpacing: Integer): TTyGridIntArray` | 由「解算后的长度数组 + 空隙」求各轨道起点：`origin[0]=0`，`origin[i]=origin[i-1]+length[i-1]+spacing`。把长度转成位置。 |

```pascal
var tracks: TTyGridTracks; sizes: TTyGridIntArray;
SetLength(tracks, 3);
tracks[0].Kind := tgtAbsolute; tracks[0].Value := 100;   // 固定 100px
tracks[1].Kind := tgtPercent;  tracks[1].Value := 25;    // 25%
tracks[2].Kind := tgtStar;                                // 剩余全给它
sizes := TyGridTrackSizes(400, 0, tracks);
// sizes = [100, 100, 200]   (绝对 100 + 25%×400=100 + 剩余 200)
```

---

## 7. 布局机制

1. **重排流程：** 客户区宽 / 高分别喂给 `TyGridTrackSizes` 得到列宽 / 行高数组 → `TyGridTrackOrigins` 得到列 / 行起点 → 对每个已分配子控件用 `TyGridCellRect` 求所跨单元格并集 → 四周内缩 `Spacing`、折入客户区原点 → `SetBounds`。
2. **重排时机：** `Resize`（尺寸变化）、`SetCell`、以及 `ColumnCount / RowCount / Spacing / SetColumnStyle / SetRowStyle` 任一变化时。
3. **只排已分配子控件：** 只有经 `SetCell` 分配了单元格的子控件参与网格布局；未分配的子控件保持自身坐标不动。
4. **再入保护：** `SetBounds` 会回环触发容器的布局逻辑，内部 `FInLayout` 标志防止重入递归。

> **无窗口句柄下的行为（headless / 测试）：** 网格数学（轨道解算 / 单元格并集 / 起点推导）是单元级纯函数，可直接验证；子控件实际 `SetBounds` 由控件薄壳完成，在真实 GUI 与 headless `TForm.CreateNew` 下均生效。

---

## 8. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.GridPanel, tyControls.Label, tyControls.Edit;

// 加载主题（通常在窗体 Create 顶部执行一次）
TyDefaultController.LoadTheme('themes/light.tycss');

var Grid: TTyGridPanel;
Grid := TTyGridPanel.Create(Self);
Grid.Parent := Self;
Grid.Align := alClient;
Grid.Spacing := 6;

// 两列：左列固定 90px 放标签，右列 star 放输入框；三行 star。
Grid.ColumnCount := 2;
Grid.RowCount := 3;
Grid.SetColumnStyle(0, tgtAbsolute, 90);
Grid.SetColumnStyle(1, tgtStar);

// 逐行放「标签 + 输入框」
var i: Integer;
const Fields: array[0..2] of string = ('用户名', '邮箱', '电话');
for i := 0 to 2 do
begin
  var Lbl := TTyLabel.Create(Grid);
  Lbl.Parent := Grid;
  Lbl.Caption := Fields[i];
  Grid.SetCell(Lbl, 0, i);          // 第 0 列、第 i 行

  var Ed := TTyEdit.Create(Grid);
  Ed.Parent := Grid;
  Grid.SetCell(Ed, 1, i);           // 第 1 列、第 i 行
end;

// 跨列示例：一个横幅按钮占满最底行的两列
var Banner := TTyButton.Create(Grid);
Banner.Parent := Grid;
Banner.Caption := '提交';
Grid.RowCount := 4;
Grid.SetCell(Banner, 0, 3, 2, 1);   // 从 (0,3) 起跨 2 列
```

---

## 9. 注意事项

1. **不新增 `.tycss`：** 复用父类 `TyPanel` 令牌绘制边框 / 背景；主题化时写 `TyPanel` 选择器即可，`.tycss` 中不存在 `TyGridPanel`。网格不绘制格线。
2. **只摆放已 `SetCell` 的子控件：** 拖进来但未分配单元格的子控件不会被网格移动。设计期请配合代码 `SetCell`（设计期集合流式化是真机集成事项，本控件提供的是代码优先 API）。
3. **`Spacing` 兼作间距与内缩：** 它既是子控件在单元格内四周的内缩，也因此形成相邻单元格之间的视觉间隙；网格本身不再单独绘制沟槽。
4. **百分比基于原始可用长度：** `tgtPercent` 的基准是「轴长 − 轨间空隙」，**不**因绝对轨道占用而缩小——这与 CSS `%` 语义一致；若百分比 + 绝对超额，星轨道池夹到 0，且不会有负轨道。
5. **末位 star 吸收余数：** 多个 star 轨道均分时用整数除法，余数记在**最后一个** star 轨道上，保证各段之和精确等于可用长度（无 1px 累积误差）。
6. **跨度自动夹取：** `SetCell` 的跨度会在布局时夹到网格边界——跨到网格外的部分停在最后一列 / 行；`ACol/ARow` 越界的分配解析为空矩形（子控件被折叠成 0 尺寸，不报错）。
7. **子控件释放安全：** 分配过的子控件被 `Free` 会经 `FreeNotification` 自动解绑，不会留下悬挂引用。

---

参见 [[TTyPanel]]（父类，提供主题化边框 + 真容器能力）。
