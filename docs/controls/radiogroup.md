# TTyRadioGroup — API 参考

## 1. 概述

`TTyRadioGroup` 是 TyControls 库中的**单选组容器**控件，继承自 [`TTyGroupBox`](groupbox.md)。它复用了父类的主题化标题边框与客户区内缩（`AdjustClientRect` 在标题带下方留出空间），并在此基础上**自动为 `Items` 中的每一行文字生成一个 `TTyRadioButton` 子控件**，在客户区内按列布局。

这些单选子控件是**内部辅助控件**：由控件自身拥有（`Owner = Self`）、标记为 `csNoDesignVisible`（不会泄漏到 IDE 的对象树 / 组件列表中），并在 `Items` 变化时整体重建。所有子单选按钮共享同一 `Parent`（即本控件）且 `GroupIndex = 0`，因此借助 `TTyRadioButton.UncheckSiblings` 天然互斥——无需额外的分组名属性。

与 [`TTyButtonGroup`](buttongroup.md)（纯自绘的分段按钮条）不同，`TTyRadioGroup` 使用的是**真实的子控件**，因此每个选项都是可聚焦、可键盘操作（空格选中）的标准单选按钮。但整组**只占一个 Tab 位**：只有当前选中项（一项都没选时是第 0 项）的 `TabStop` 为 `True`，Tab 键进组、落在当前选择上、再按一次就离开——组内的移动交给方向键。

典型用途：一组互斥的配置选项（如"对齐方式：左 / 中 / 右"），带一个可见的分组标题框。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.RadioGroup` |
| typeKey | `TyGroupBox`（**继承自父类，复用同一主题规则，无新增 .tycss**） |
| 基类 | `TTyGroupBox`（继承自 `TTyCustomControl`） |
| 子控件类型 | `TTyRadioButton`（`tyControls.CheckBox`） |
| 默认尺寸 | 185 × 130（逻辑像素） |
| 客户区顶边内缩 | 16 逻辑像素（继承自 `TTyGroupBox.AdjustClientRect`） |

```pascal
uses tyControls.RadioGroup;
```

> **主题说明：** `TTyRadioGroup` 的框体样式取自 `TyGroupBox` 规则；子单选按钮的样式取自 `TyRadioButton` 规则。两者都无需为本控件单独声明 CSS。

---

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Items` | `TStrings` | 空 | 选项文本列表，**每一行对应一个 `TTyRadioButton` 子控件**。写入（`Assign`）或增删行都会触发子控件重建 + 重新布局。 |
| `Columns` | `Integer` | `1` | 子控件在客户区内的列数（≥ 1，小于 1 会被夹取为 1）。布局为**列优先**（先填满第 0 列，再填第 1 列……）。 |
| `ItemIndex` | `Integer` | `-1` | 当前选中项的索引（`-1` = 无选中）。**读**：返回当前处于 `Checked` 状态的子控件索引；**写**：选中对应子控件（其余自动取消），越界值则清空所有选中。**程序化写入同样触发 `OnSelectionChanged` 与 `OnClick`**（写入值与当前值相同时不触发）。 |
| `Caption` | `string` | `''` | 分组框标题（继承自 `TTyGroupBox`）。 |
| `Alignment` | `TAlignment` | `taLeftJustify` | 标题在顶部边框带内的对齐方式（继承自 `TTyGroupBox`）。 |

### public 方法

| 方法 | 返回 | 说明 |
|------|------|------|
| `Count` | `Integer` | 当前子单选按钮数量（等于 `Items.Count`）。 |

---

## 4. 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnSelectionChanged` | `TNotifyEvent` | **`ItemIndex` 发生改变时**触发，不论改变来自用户点击还是程序化赋值。只有 `Items` 重建时的选中恢复**不会**触发本事件（重建不是一次选择）。一次用户手势（点击 → 目标选中 + 兄弟取消，共触发多个子控件的 `OnChange`）只会汇聚为**一次** `OnSelectionChanged`。 |
| `OnClick` | `TNotifyEvent` | 与 `OnSelectionChanged` **同时同条件**触发（先 `OnSelectionChanged` 后 `OnClick`）。这是为从 Lazarus 移植的代码准备的：`TCustomRadioGroup` 把选择变化报在 `OnClick` 上，而 `TControl` 原生的 `OnClick` 只在**分组框本身**被点到时才发——本控件的表面被子控件铺满，那等于永不触发。 |

---

## 5. 布局几何：`TyRadioGroupCellRect`

布局的核心是一个**纯函数**（无控件状态，可独立单元测试）：

```pascal
function TyRadioGroupCellRect(const AClient: TRect;
  ACount, AColumns, AIndex: Integer): TRect;
```

- **`AClient`**：**已内缩**的客户区矩形（即标题带下方的内容区，直接传 `ClientRect` 即可）。
- **`ACount`**：总单元数。
- **`AColumns`**：列数。
- **`AIndex`**：0 基索引。
- **返回**：该单元的矩形；对退化请求（`ACount <= 0`、`AColumns <= 0`、索引越界、客户区零面积）返回空矩形。

### 布局规则（**列优先 / column-major**）

1. 行数 `rows = ceil(ACount / AColumns)`；
2. 索引到网格的映射：`col = AIndex div rows`，`row = AIndex mod rows`——即**先纵向填满一列，再填下一列**（与经典 VCL/LCL `TRadioGroup` 一致）；
3. 列宽均分客户区宽度，**最后一列吸收整除余数**延伸到右边界，保证 `[Left, Right)` 无缝铺满；
4. 每个单元固定行高 22 逻辑像素；整个网格在客户区高度内**垂直居中**（当网格高于客户区时改为顶对齐），使短列表不会紧贴标题带。

### 示例

`AClient = (0,0,200,120)`，`ACount = 4`，`AColumns = 2` → `rows = 2`：

| 索引 | col / row | 矩形（左, 上偏移, 右, 下偏移） |
|------|-----------|-------------------------------|
| 0 | 0 / 0 | 左列上行 |
| 1 | 0 / 1 | 左列下行 |
| 2 | 1 / 0 | 右列上行 |
| 3 | 1 / 1 | 右列下行 |

即 `0,1` 在左列（`Left = 0..100`），`2,3` 在右列（`Left = 100..200`）。

---

## 6. 状态与主题

框体的 `:hover` / `:active` / `:disabled` 等状态与 `TyGroupBox` 一致（见 [groupbox.md](groupbox.md)）。子单选按钮各自解析 `TyRadioButton` 规则（选中项进入 `:active` 得到强调色圆点，见 [checkbox.md](checkbox.md)）。

### light.tycss 相关规则（无需为 RadioGroup 单独声明）

```css
TyGroupBox   { background: var(--surface); color: var(--on-surface);
               border-color: var(--border); border-width: 1px;
               border-radius: var(--radius); font-size: 10px; }
TyRadioButton { /* 圆点框 + 标题的样式，选中态见 :active 规则 */ }
```

---

## 7. 代码示例

### 基础单选组

```pascal
uses
  tyControls.Controller, tyControls.RadioGroup;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

var RG: TTyRadioGroup;
RG := TTyRadioGroup.Create(Self);
RG.Parent := Self;
RG.SetBounds(16, 16, 200, 140);
RG.Caption := '对齐方式';
RG.Items.Add('左对齐');
RG.Items.Add('居中');
RG.Items.Add('右对齐');
RG.ItemIndex := 0;              // 默认选中第一项（同样会触发 OnSelectionChanged / OnClick）
```

### 双列布局 + 选中变化事件

```pascal
type
  TForm1 = class(TForm)
    procedure GroupSelectionChanged(Sender: TObject);
  end;

var RG: TTyRadioGroup;
RG := TTyRadioGroup.Create(Self);
RG.Parent := Self;
RG.SetBounds(16, 16, 260, 120);
RG.Caption := '尺寸';
RG.Columns := 2;               // 两列，列优先填充
RG.Items.Add('特小');
RG.Items.Add('小');
RG.Items.Add('中');
RG.Items.Add('大');
RG.OnSelectionChanged := @GroupSelectionChanged;

procedure TForm1.GroupSelectionChanged(Sender: TObject);
begin
  // 用户点击与 ItemIndex := 赋值都会进入这里
  Caption := '已选择索引 ' + IntToStr((Sender as TTyRadioGroup).ItemIndex);
end;
```

---

## 8. 注意事项

1. **子控件是内部辅助控件：** 由 `TTyRadioGroup` 自身创建并拥有，标记 `csNoDesignVisible`，**不会**出现在 IDE 设计器的对象树中。请勿手动往 `TTyRadioGroup` 里拖放子控件——用 `Items` 驱动。
2. **`Items` 变化会整体重建子控件：** `TStrings.OnChange` 不携带差异信息，因此每次变化都会释放旧子控件、重建新集合。重建后，**若原 `ItemIndex` 仍在有效范围内则恢复选中**，否则清空为 `-1`。
3. **`ItemIndex` 是"读=已选/写=去选"的活属性：** 读取时实时扫描子控件的 `Checked` 状态，写入时选中目标并互斥其余。它不缓存独立字段，与子控件状态始终一致。
4. **程序化设值同样通知：** `ItemIndex :=` 赋值与用户点击走同一条通知路径（`OnSelectionChanged` + `OnClick`）。以前它是静默的，于是"让详情面板跟着选择走"这类处理器在用户点击时有效、在程序恢复一个存档选择时静默失效。内部的重入守卫只负责把"选中目标 + 取消兄弟"这一串子控件事件收敛成**一次**通知，不负责让程序化赋值变哑。只有 `Items` 重建恢复选中仍保持静默——重建不是一次选择。
5. **整组只占一个 Tab 位：** 只有当前选中项（未选中时为第 0 项）`TabStop = True`，选择变化与 `Items` 重建后都会重算。以前每个子控件各占一位，于是一个五项的单选组在 Tab 序里就是五站，而真正用来移动选择的方向键反倒无事可做。
6. **布局纯几何：** 位置由纯函数 `TyRadioGroupCellRect` 计算（列优先、最后一列吸收余数、垂直居中）；控件在 `SetParent` / 尺寸变化 / `Columns` 变化 / 重建时调用它重新摆放子控件。若需自定义排布，可直接调用该函数。
7. **复用 `TyGroupBox` 主题：** 本控件不引入任何新 typeKey 或新 .tycss 规则；框体走 `TyGroupBox`，子控件走 `TyRadioButton`。
```
