# TTyGridPanel / TTyGridCell — API 参考

## 1. 概述

`TTyGridPanel` 是 TyControls 库中的**可在设计器里拖放的网格布局容器**，继承自 [`TTyPanel`](panel.md)。设 `ColumnCount × RowCount`，它就**自动生成同样数量的 [`TTyGridCell`](#2-单元与-typekey) 格子容器**——每个格子是一个真正的透明子容器，你把控件拖进(或代码 parent 进)某个格子，`alClient` 的子控件就被 LCL 约束在**它所在格子**的范围内。

这套模型照抄库里已跑通的 [`TTyPageControl` / `TTyTabSheet`](pagecontrol.md):格子是 **form 拥有、parent 是网格、走 `GetChildren` 流式化**的真组件,所以整套布局(格子 + 拖进去的控件)都能在 `.lfm` 里保存,并在设计器里可视化编辑。

典型用途:表单的「标签 + 输入框」两列布局、仪表盘卡片网格、按钮阵列——无需为每个子控件手算坐标,改变面板尺寸时各列 / 行按 `ColumnSizes` / `RowSizes` 的**轨道尺寸策略**自动重分配。

> **与旧版的区别(破坏性):** 早期 `TTyGridPanel` 是「代码优先」的:靠 `SetCell(control, col, row)` / `SetColumnStyle` 把任意子控件指派到虚拟单元格,分配存在未发布的数组里、`.lfm` 存不下。**这些 API 已删除。** 新模型用真正的 `TTyGridCell` 子容器 + `.lfm` 表达布局。迁移见 [§8 代码示例](#8-代码示例)。

---

## 2. 单元与 typeKey

| 项目 | `TTyGridPanel` | `TTyGridCell` |
|------|-----|-----|
| 单元 | `tyControls.GridPanel` | `tyControls.GridPanel`(与网格同单元;`tyControls.GridCell` 是兼容再导出) |
| 基类 | `TTyPanel`(→ `TTyCustomControl` → `TCustomControl`) | `TTyCustomControl`(→ `TCustomControl`) |
| `GetStyleTypeKey` | `'TyGridPanel'`(**默认无主题规则 → 透明布局宿主**;格间距露出父容器颜色。主题可定义该键来要一个可见的网格表面) | `'TyGridCell'`(默认无主题规则,**透明**) |
| 默认尺寸 / 网格 | 200 × 150;默认 2 × 2 全等分 | 由网格定位,不单独设尺寸 |
| 设计器注册 | 面板:`TyControls Containers` 组 | `RegisterNoIcon`(网格自动建,不从面板单独拖) |

```pascal
uses tyControls.GridPanel, tyControls.GridCell;
```

`TTyGridCell` 默认**不画背景、不画边框**——它只负责定位 + 裁剪 + 逐格内边距。可见内容由你放进去的控件(卡片、输入框等)提供。

> **主题说明:** `TTyGridPanel` 有自己的 typeKey `TyGridPanel`,而**随库主题刻意不定义它**——
> 网格本体是个纯布局宿主,间隔区应当透明地露出父容器,而不是自己涂一层面板底色
> (`tests/test.gridpanel.pas` 断言没有任何内置主题给它背景)。
> 想给网格本体上色,写 `TyGridPanel { … }` 即可;**不要**去改 `TyPanel`——那会重涂全应用的面板,
> 而网格本体纹丝不动(它已经不借那个键了)。
>
> 另注意**撞名**:格子的 typeKey `TyGridCell` 与数据网格(`TTyStringGrid`)正文单元格用的是**同一个名字**,
> 而后者在 `light.tycss` 里是有规则的。今天视觉上不冲突(`TTyGridCell.Paint` 是空实现),
> 但给 `TyGridCell` 写规则会同时影响两者。

---

## 3. 轨道尺寸策略

每条列 / 行「轨道」以三种方式之一定尺寸,在 `.lfm` / OI 里用 `ColumnSizes` / `RowSizes` 字符串表达(逗号分隔),或由纯函数直接构造:

| 语法(字符串) | `TTyGridTrackKind` | `Value` 语义 |
|------|------|--------------|
| `100` | `tgtAbsolute` | 固定逻辑像素数(`< 0` 夹为 0) |
| `30%` | `tgtPercent` | 占**原始可用长度**的百分比 `0..100` |
| `*` / `2*` | `tgtStar` | **份数**(`Value`,下限 1):按权重分配剩余空间。`*` = 1 份,`2*` = 两倍于 `*` |

- **空字符串** = `ColumnCount`(或 `RowCount`)条**全 star 等分**轨道——这就是「设 N×M 显 N×M 等分格」的默认。
- 例:`ColumnSizes = '2*, *'` → 第一列是第二列的两倍宽;`RowSizes = '100, *, 30%'` → 固定 / star / 百分比混用。

轨道记录类型:

```pascal
type
  TTyGridTrackKind = (tgtAbsolute, tgtPercent, tgtStar);
  TTyGridTrack = record
    Kind: TTyGridTrackKind;
    Value: Integer;   // px(abs)/ 0..100(percent)/ 份数 >=1(star)
  end;
  TTyGridTracks = array of TTyGridTrack;
```

**解算顺序**(与 WPF / CSS Grid 语义一致):
1. `tgtAbsolute` 轨道先各取自身像素;
2. `tgtPercent` 轨道取「百分比 × 可用长度」(可用长度 = 轴长 − 轨间空隙,**不**因绝对轨道而减小);
3. 剩余空间(可用 − 绝对 − 百分比,下限 0)在 `tgtStar` 轨道间**按权重比例**分配,**最后一个** star 轨道吸收整数除法的余数(保证总和精确)。

**超额分配**(绝对 + 百分比之和超过可用长度)永不产生负轨道,星轨道池夹到 0。

---

## 4. 属性表

### `TTyGridPanel` 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `ColumnCount` | `Integer` | `2` | 列数。变化时**自动建 / 删** `TTyGridCell`:落在新 (col,row) 范围内的格子(连同其内容)**保留**,越界的格子被释放。 |
| `RowCount` | `Integer` | `2` | 行数,语义同上。 |
| `ColumnSizes` | `string` | `''` | 列轨道模板(见 [§3](#3-轨道尺寸策略));空 = 全等分。 |
| `RowSizes` | `string` | `''` | 行轨道模板;空 = 全等分。 |
| `Spacing` | `Integer` | `4` | 格与格之间的**间距(gutter)**;负值夹为 0。 |

**只读访问器:** `Cells[ACol, ARow]: TObject`(取某格,`nil` 表示越界,需 cast 到 `TTyGridCell`)、`CellCount: Integer`、`CellAt(AIndex): TObject`(按注册序)。

### `TTyGridCell` 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Padding` | `Integer` | `0` | 该格**内容四周内缩**的逻辑像素(逐格可单独设,DPI 缩放)。`alClient` 子控件拿到的是「格矩形 − Padding」。 |
| `Col` / `Row` | `Integer` | (网格设) | 该格在网格里的坐标;published 以便**流式化加载时**格子知道自己该落哪。 |

> **两级间距:** 网格的 `Spacing` = 格**间**距;格子的 `Padding` = 格**内**缩。

### 继承自 TTyPanel 的常用 published 成员

`Align` / `Anchors`(常设 `alClient` 或 `[akLeft,akTop,akRight]` 让网格随宿主伸缩)、`StyleClass`、`Controller`。

---

## 5. 单元格模型与设计器集成

- **格子是显式的 `.lfm` 对象**(像每个 TabSheet 页):`object KpiCell0: TTyGridCell … end`,form 拥有、parent 是网格、走默认 `TWinControl.GetChildren` 流式化(网格无需重写 `GetChildren`——它是 TWinControl,直属子控件自动嵌套)。
- **`TTyGridCell.SetParent`** 里向所属网格**自注册**(`RegisterCell`,幂等),`Notification(opRemove)` 时注销——所有路径(网格建格、设计器拖、流式化加载)统一维护格子列表。
- **加载对账:** 构造函数无条件播种默认 2×2 并标记为「临时」;若 `.lfm` 里有真格子流式化进来(注册发生在 `csLoading` 期),`Loaded` 丢弃临时格子、保留流式格子;没有格子对象的老 / 手改 `.lfm` 则保留临时默认并按 count 对账。**这样保存的窗体加载后格子数正确,不会翻倍。**
- **设计期格线:** `csDesigning` 下 `Paint` 画虚线列 / 行格线,使 N×M 格子在 IDE 里可见。
- **约束到格:** 格内子控件设 `Align = alClient` 即被 LCL 约束在该格(父容器就是格子),不会溢出到别的格。

> **非目标:** 不支持跨格 / 合并单元格(colspan/rowspan)——每格恒为 1×1。需要不等宽行用 `ColumnSizes` 表达,或嵌套一层网格。

---

## 6. 纯函数(单元级,可 headless 测试)

单元 `tyControls.GridPanel` 导出以下纯函数,是网格布局的可测核心(无控件状态、无窗口句柄):

| 函数 | 签名 | 说明 |
|------|------|------|
| `TyParseGridTracks` | `(const ASpec: string; ADefaultCount: Integer): TTyGridTracks` | 把 `ColumnSizes` / `RowSizes` 字符串解析成轨道:`N*`/`*` = star(份数,默认 1)、`N%` = 百分比、`N` = 绝对;空串 → `ADefaultCount` 条全 star。 |
| `TyGridTrackSizes` | `(ATotal, ASpacing: Integer; const ATracks: TTyGridTracks): TTyGridIntArray` | 把一条轴解算为像素长度:先绝对、再百分比(取原始可用长度)、最后 star **按权重**分配剩余(末位吸收余数)。永不为负;超额夹取;空列表返回空数组。 |
| `TyGridCellRect` | `(const AColX, AColW, ARowY, ARowH: TTyGridIntArray; ACol, ARow, AColSpan, ARowSpan: Integer): TRect` | 给定各列左起点 / 宽、各行上起点 / 高,返回 (col,row) 单元格矩形(网格内部以跨度 1 调用)。越界返回空矩形。 |
| `TyGridTrackOrigins` | `(const ALengths: TTyGridIntArray; ASpacing: Integer): TTyGridIntArray` | 由「长度数组 + 空隙」求各轨道起点:`origin[0]=0`,`origin[i]=origin[i-1]+length[i-1]+spacing`。 |

```pascal
var tracks: TTyGridTracks; sizes: TTyGridIntArray;
tracks := TyParseGridTracks('2*, *', 0);          // 两条 star:权重 2 和 1
sizes  := TyGridTrackSizes(300, 0, tracks);
// sizes = [200, 100]   (300 按 2:1 分)
```

---

## 7. 布局机制

1. **重排流程:** 客户区宽 / 高分别喂给 `TyGridTrackSizes`(轨道来自 `TyParseGridTracks(ColumnSizes/RowSizes, Count)`)得列宽 / 行高 → `TyGridTrackOrigins` 得起点 → 对每个格子用 `TyGridCellRect` 求其 (Col,Row) 矩形 → 折入客户区原点 → 对格子 `SetBounds`。格内 `Padding` 由 `TTyGridCell.AdjustClientRect` 施于**格内子控件**,不在此处重复内缩。
2. **重排时机:** `Resize`、`ColumnCount / RowCount / ColumnSizes / RowSizes / Spacing` 任一变化、格子增删。
3. **再入保护:** `FInLayout` 标志防止 `SetBounds` 回环递归。

> **无窗口句柄下(headless / 测试):** 网格数学(轨道解算 / 起点 / 单元格矩形)是纯函数可直接验证;格子 `SetBounds`、Padding 内缩、流式化往返均有 headless 测试。**设计器里的真拖放手感、格线绘制需在运行的 Lazarus IDE 里人眼确认。**

---

## 8. 代码示例

### 8a. 在 `.lfm` 里(推荐——设计器 / 可视化)

```
object GridForm: TTyGridPanel
  ColumnCount = 2
  RowCount = 3
  ColumnSizes = '60, *'        # 左列 60px 放标签,右列 star 放输入
  Spacing = 6
  object GfLabelCell0: TTyGridCell
    Col = 0
    Row = 0
    Padding = 2
    object LblUser: TTyLabel
      Align = alClient
      Caption = '用户名'
    end
  end
  object GfEditCell0: TTyGridCell
    Col = 1
    Row = 0
    Padding = 2
    object EditUser: TTyEdit
      Align = alClient
    end
  end
  # … 其余 4 个格子(Col/Row 0..1 × 0..2)
end
```

### 8b. 纯代码

```pascal
uses tyControls.GridPanel, tyControls.GridCell, tyControls.Edit;

var Grid: TTyGridPanel; Ed: TTyEdit;
Grid := TTyGridPanel.Create(Self);
Grid.Parent := Self;
Grid.Align := alClient;
Grid.ColumnCount := 2;             // 建 2×3 = 6 个格子
Grid.RowCount := 3;
Grid.ColumnSizes := '60, *';
Grid.Spacing := 6;

Ed := TTyEdit.Create(Self);
Ed.Parent := TTyGridCell(Grid.Cells[1, 0]);   // 放进 (1,0) 格
Ed.Align := alClient;                          // 约束在该格内
```

---

## 9. 注意事项

1. **网格本体与格子默认都不画:** `TyGridPanel` 被随库主题刻意留空(间隔透明),`TTyGridCell.Paint` 为空实现。要上色就写 `TyGridPanel` 选择器——**别改 `TyPanel`**,它已经不借那个键了。
2. **格子是真组件、进 `.lfm`:** 布局(格子 + 内容)全部可在设计器编辑并保存;不再有代码优先的 `SetCell`。
3. **`Spacing`(格间) vs 每格 `Padding`(格内)** 各司其职。
4. **加载不翻倍:** 构造播种的临时格子在有流式格子时于 `Loaded` 丢弃(见 [§5](#5-单元格模型与设计器集成))。
5. **权重 star:** `2*` 是 `*` 的两倍份额;末位 star 吸收整除余数,总和精确。
6. **缩小网格是破坏性的:** 减少 `ColumnCount` / `RowCount` 会释放越界格子及其内容。
7. **不支持跨格。**

---

参见 [`TTyPanel`](panel.md)(父类)、[`TTyPageControl`](pagecontrol.md)(同款 form-owned 子容器设计器模式)。
