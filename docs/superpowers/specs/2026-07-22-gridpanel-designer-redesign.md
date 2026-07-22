# TTyGridPanel 重做:设计器可拖放的格子布局

日期:2026-07-22
状态:设计已确认,待写实现计划

## 一句话

把 `TTyGridPanel` 从"代码优先 `SetCell`"重做成**设计器可拖放**的格子布局:设 `ColumnCount`×`RowCount` 就出现 N×M 个真容器格子,往每格拖控件,`alClient` 的子控件被 LCL 约束在格内——照 `TTyPageControl` / `TTyTabSheet` 那套已在本库跑通的 form-owned 子容器模式。

## 背景 / 动机

现状的 `TTyGridPanel` 用一组**未发布的平行数组**存"控件 → (列,行,跨格)"映射,只有 `SetCell` 代码能写。后果:
- 组件在面板上(`TyControls Containers` 组),容器也能拖子控件进去,但**没有格子指派机制**——拖进去的控件停在落点像素、无视网格,`.lfm` 也存不下指派。
- 想要 Qt Designer 那种"设 3×2 → 逐格拖控件"做不到。

**关键事实(已核实)**:Lazarus LCL **没有** `TGridPanel`(那是 Delphi VCL);LCL 只有 `TFlowPanel`(流式)和 `ChildSizing`(等分但按序填、不可寻址)。所以"逐格可寻址拖放"没有 LCL 现成控件可抄。**但本库自己的 `TTyPageControl`/`TTyTabSheet` 就是"form-owned 子容器、设计器逐页拖控件"的跑通先例**——本设计照抄它。

## 已确认的决策

1. **能力档位**:配置行列尺寸(star / 固定px / 百分比,默认全等分),**不做跨格**。N×M 个独立格子,模型保持干净。
2. **旧 API**:**原地重做 `TTyGridPanel`**,删 `SetCell`/平行数组;同步改 `examples/containers`。
3. **格子外观**:**透明布局区域**(默认无背景无边框),每格有自己的 `Padding`。
4. **范围**:控件 + `examples/containers` 示例 + 顺手迁 antdesign 仪表盘页。

## 架构

两个控件。

### `TTyGridCell`(新)—— 一个格子
- 轻量**透明容器**:继承 `TTyCustomControl`(windowed、能裁剪子控件),**默认不画主题背景 / 边框**(不走 `TTyPanel` 那层背景填充)。只做定位 + 裁剪。是真组件:**form(Root)拥有、parent 是 grid、走 `GetChildren` 流式化**——设计器能往里拖控件,`alClient` 子控件的父容器就是它,被 LCL 自然约束在格内。
- `csAcceptsControls`(真容器)。
- 发布属性:
  - **`Padding`**(四边可分):逐格内边距,在 OI 上每格单独设。
  - **`Col` / `Row`**:该格在网格里的位置。published 以便**加载对账**(加载时每格知道自己该落哪),OI 里只读呈现。
- `SetParent` 里向所属 grid **自注册 / 注销**(照 `TTyTabSheet.SetParent → RegisterPage`)。

### `TTyGridPanel`(原地重做)—— 管一堆格子
- 继承不变(windowed 容器)。内部持有 N×M 个 `TTyGridCell`。
- 复用现成、已测的纯解算器:`TyGridTrackSizes` / `TyGridTrackOrigins` / `TyGridCellRect`。

## 设计器面向的属性(全部可在 OI / `.lfm` 设)

| 属性 | 作用 |
|---|---|
| `ColumnCount` / `RowCount` | 设 3×2 → **自动建/删 6 个 `TTyGridCell`**,默认全等分。 |
| `ColumnSizes` / `RowSizes`(string,进阶) | 留空 = 全 star 等分;`'2*, *, *'` = 第一列双宽;`'100, *, 30%'` = 固定/star/百分比混用。解析成轨道喂给解算器。 |
| `Spacing` | 格与格之间的**间距(gutter)**。 |
| `Cells[col,row]`(只读访问器) | 取某格。 |
| 每个 `TTyGridCell.Padding` | 格**内缩**。 |

两级间距各司其职:**grid 的 Spacing = 格间距**;**cell 的 Padding = 格内缩**。

## 尺寸模型

- 每列 / 每行是一条轨道:`tgtAbsolute`(px)/ `tgtPercent`(0..100)/ `tgtStar`(平分剩余,最后一条吸收余数)。
- `ColumnSizes`/`RowSizes` 字符串是设计器友好的轨道来源:逗号分隔,`N*`=star(N 份)、`N`=absolute px、`N%`=percent。空串 → 全 star。
- 默认(未设 sizes)= 全 star = 等分,正好对上"设 N×M 显 N×M 等分格"。

## 格子生命周期

- `ColumnCount`/`RowCount` 变化时,按 (col,row) 重新匹配:落在新范围内的格子(连同拖进去的内容)**保留**;超出的格子被释放(**破坏性**,文档标注:缩小网格会丢弃越界格及其内容)。
- 加载期(`csLoading`)**不自动建格**:`Loaded` 里认领已流式化的格子,按各自 `Col`/`Row` 归位;数量对不上(手改 `.lfm`)才补建 / 释放多余。

## 布局(Relayout)

1. `TyGridTrackSizes` 把 `ClientRect` 按轨道切成列宽 / 行高,`Spacing` 作为 (n-1) 个 gutter 扣除。
2. 每个 `TTyGridCell` 摆到它 (col,row) 的矩形(`TyGridCellRect` + origins),四周减 `Spacing`(gutter)。
3. cell 再用自己的 `Padding` 内缩它的内容(cell 的 `AdjustClientRect`)——所以格内 `alClient` 子控件拿到的是"格矩形 − Padding"。
- 触发点:`Resize`、count/sizes/spacing 变化、格子增删。

## 流式化 / 设计器集成(照 `TTyPageControl`)

- 格子是**显式 `.lfm` 对象**(像每个 TabSheet 页):form 拥有、parent 是 grid、`GetChildren` 流式化;`TTyGridCell.SetParent` 自注册。
- 设计器改 `ColumnCount` → grid **当场建出新 `TTyGridCell` 组件** → 存进 `.lfm`。
- 设计期画**格线**(`csDesigning`),让 N×M 格子可见。
- 可选:`TTyGridPanel` 组件编辑器,右键"加一行 / 加一列"(照 `TTyPageControlEditor`)。
- 内部子控件泄漏防护:参考 `designer-internal-subcontrol-leak` 教训,格子在设置 Visible 相关状态时注意 `csNoDesignVisible` 时序。

## 破坏性改动 + containers 示例

- **删**:`SetCell` / `RemoveCell` / `GetCell` / 按控件存的平行数组 / `SetColumnStyle(AControl,...)` 之类。
- **留 / 加**:`ColumnCount` / `RowCount` / `Spacing`;新增 `ColumnSizes` / `RowSizes` / `Cells[col,row]` / `TTyGridCell`。
- `examples/containers`(现用 `SetCell` 演示)改成新模型,演示"设计器格子 + `.lfm`"。
- 注册:`TTyGridCell` 需在 `designtime/tyControls.Design.pas` 注册(或 `RegisterNoIcon`——格子通常不单独从面板拖,由 grid 建);面板图标生成器 `$classes` 同步(见 `palette-icons` 漂移守卫)。

## 仪表盘迁移(两个 grid,因不跨格)

- `GridKPI`:4×1 等分 → 4 张 KPI 卡各进一格。
- `GridMain`:2×1,`ColumnSizes='2*, *'`(chart 宽、状态窄)→ chart 卡 + 状态卡各进一格。
- 卡片进格子、保留自己的 `--pad-card`;拖窗口卡片**等比伸缩**(响应式),去掉手算 Left/Width + akRight。
- 两个 grid 上下堆叠定位:`GridKPI` 贴顶(高 ~228),`GridMain` 在其下(高 ~404),各自 `Anchors`/显式 bounds;不引入第三个外层 grid,保持简单。

## 测试策略

**headless 可验(必须绿)**:
- 轨道解算数学(现成测试延用);
- 改 count → 格子增删数量正确;
- Relayout 后各格矩形:默认等分、`ColumnSizes` 的 abs/percent/star 正确;
- 逐格 `Padding` 真把内容内缩;
- **格内 `alClient` 子控件 bounds == 格内容矩形**(不溢出到 grid);
- **流式化往返**:grid + 格子 + 拖进去的控件存进流再读回,结构 / 归位一致;`Loaded` 对账正确;
- runtime 探针渲染成网格 + 迁移后的仪表盘渲染。

**须在真机 Lazarus IDE 验(我 headless 做不到)**:
- 真拖放子控件进格、`alClient` 约束的设计器观感;
- 设计期格线绘制;
- 组件编辑器右键项。

## 非目标(有意不做)

- **跨格 / 合并单元格**(colspan/rowspan)—— 打破"每格独立面板"的干净模型,且合并格的设计器交互复杂、无法 headless 验。留作后续。
- 嵌套 grid 的可视化编辑器糖(手动嵌套即可)。
- 仪表盘之外的其它示例迁移。

## 相关

`formsurface-program`(子控件必须是容器子控件)、`pagecontrol-redesign-program`(form-owned 子容器先例)、`designer-internal-subcontrol-leak`、`palette-icons-and-sizes`、`no-native-controls-in-ui`、`demo-edits-lfm-not-code`。
