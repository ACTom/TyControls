# TTyControlBar

## 1. 概述

`TTyControlBar` 是 TyControls 库中的**可停靠工具带宿主**（band host），继承自 [`TTyPanel`](panel.md)。它把作为其子控件（`Parent := ControlBar`）的控件——典型是工具条 / 小面板——排布成若干**水平工具带（band，即“行”）**：每个子控件停靠在某条 band 上；一条 band 可并排容纳多个子控件；当当前行放不下时，下一个子控件自动**换行**到下方的新 band。每条 band 在左侧绘制一个**抓手（gripper）**——由主题色画出的两条竖直点状导轨——band 上的所有子控件都从抓手右侧开始，因而可通过抓手“抓住”整条 band（对应经典 VCL `TControlBar` / Office rebar）。

核心排布逻辑抽成一个**纯函数** `TyControlBarPack`（无窗口句柄，直接被单元测试驱动）；控件本身是一层薄壳，在 `AlignControls` 里跑解算器并对每个子控件 `SetBounds`。实时拖拽换带是真机后续工作（拖拽交互），但**每个子控件所属的 band（band 索引）以子控件为键存储**，跨重排保留，子控件被释放时通过 `Notification` 自动清除。

典型用途：文档编辑器 / 主窗口顶部承载多条可换行的工具条带。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ControlBar` |
| `GetStyleTypeKey` 返回值 | `'TyPanel'`（**刻意复用** `TTyPanel` 的 typeKey，借用其主题化边框 / 令牌，**不新增任何 .tycss**） |
| 基类 | `TTyPanel`（继承自 `TTyCustomControl` → `TCustomControl`） |
| 默认尺寸 | 320 × 32（逻辑像素） |

在 `.tycss` 文件中，本控件对应选择器前缀 `TyPanel`（与普通面板共用规则）。

```pascal
uses tyControls.ControlBar;
```

---

## 3. 属性表

### 3.1 TTyControlBar 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `BandHeight` | `Integer` | `26` | 每条 band（行）的统一逻辑高度；排布时每个子控件的高度被强制设为此值。改值触发重排。 |
| `RowSize` | `Integer` | `26` | `BandHeight` 的 VCL 习惯别名（读写同一字段），二者等价。 |
| `GripperWidth` | `Integer` | `12` | 每条 band 左侧为抓手预留的逻辑宽度；子控件从此宽度右侧开始排布。改值触发重排。 |
| `BandSpacing` | `Integer` | `3` | 相邻 band 之间（以及一行内相邻子控件之间）的逻辑间距。改值触发重排。 |

### 3.2 继承自 TTyPanel / TTyCustomControl 的成员

`TTyControlBar` 继承 [`TTyPanel`](panel.md) 的全部 published 成员：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Caption` | `string` | `''` | 面板标题文本（继承自 `TTyPanel`；band 宿主一般留空）。 |
| `Alignment` | `TAlignment` | `taCenter` | `Caption` 的水平对齐（继承）。 |
| `Align` | `TAlign` | `alNone` | 停靠方式；设为 `alTop` / `alBottom` 时控件随 band 行数**自动增高**（见 [第 7 节](#7-注意事项)）。 |
| `Anchors` | `TAnchors` | — | 锚点布局（继承）。 |
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分。 |
| `Controller` | `TTyStyleController` | `nil`（用全局 `TyDefaultController`） | 指定样式控制器。 |

### 3.3 公有查询方法

| 方法 | 返回 | 说明 |
|------|------|------|
| `BandIndexOf(AControl: TControl): Integer` | band 索引（从 0 起） | 返回某子控件当前所在的 band 索引；控件不是本 band 宿主的子控件、或尚未排布时返回 `-1`。这是排布结果的只读视图。 |

---

## 4. 纯排布函数 `TyControlBarPack`

```pascal
function TyControlBarPack(const AChildSizes: array of TSize;
  AAvail, ABandHeight, AGripperW, ASpacing: Integer): TTyRectArray;
```

把 `AChildSizes` 中的每个子控件（设备像素宽/高）从左到右装入高度为 `ABandHeight` 的水平 band，每条 band 左侧内缩 `AGripperW` 的抓手，行内子控件之间及 band 之间留 `ASpacing` 间距；当下一个子控件会溢出 `AAvail` 时换行到新 band。返回每个子控件的矩形（设备像素，`(0,0)` 局部坐标），**每个矩形高度恒为 `ABandHeight`**（子控件自身的 `cy` 仅供将来居中用，不影响 band 高度）。

行为要点（均有单元测试覆盖）：

- **零子控件** → 返回空数组。
- **单条 band** → 多个能放下的子控件共用同一 `Top`。
- **抓手内缩** → 每条 band 首个子控件的 `Left = AGripperW`。
- **换行** → 越过一行可用宽度（`AAvail - AGripperW`）的子控件换到下一条 band，`Top` 递增 `ABandHeight + ASpacing`，并从抓手内缩处重新开始。
- **超宽子控件** → 比一行可用宽度还宽的子控件被**钳制**到可用宽度并独占其 band（不会死循环），其后子控件换到下一条 band。
- **退化 avail** → `AAvail <= AGripperW` 时可用宽度钳为 0，子控件被钉在抓手边缘、宽度为 0。

该函数是控件排布的唯一真值来源；控件只是把子控件列表喂给它、再套用返回的矩形。

---

## 5. 事件

`TTyControlBar` **无自有专有事件**——它只 published 布局属性，不发出 `OnChange` 之类通知。命令响应发生在**子控件（工具条 / 按钮）**上，请挂接各子控件自身的事件。

> 本控件暴露 `TTyCustomControl` 的**基线事件集**（Tier A 鼠标 / 通用事件 + Tier B 键盘 / 焦点事件）。完整清单见 [../events.md](../events.md)。band 宿主自身通常无需挂接。

---

## 6. 状态与主题

### 支持的伪类状态

作为容器，`TTyControlBar` 不跟踪 hover / pressed / focus，渲染时始终使用 `CurrentStyle`（`tysNormal` 基础样式），因此内置主题**未为它定义任何伪类规则**。

### 内置规则（复用 TyPanel）

本控件复用 `TyPanel` 选择器，无独立规则：

```css
TyPanel {
  background: var(--surface);
  border-color: var(--border);
  border-radius: var(--radius);
  /* ... */
}
```

### 渲染细节

- **面板框架：** `Paint` 先调用 `inherited Paint`（`TTyPanel` 的框架绘制，走 `CurrentStyle`），画出主题化背景 / 边框。
- **band 抓手：** 随后为每条**已占用**的 band 在其左侧抓手列内绘制两条竖直导轨；颜色取当前样式的 `border-color`（缺省时回落 `text-color`），上下各内缩若干像素。band 行数由存储的子控件分配推导。
- 抓手颜色**完全由主题令牌驱动**，控件代码不硬编码任何颜色（遵循库的主题可定制原则）。

---

## 7. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.ControlBar, tyControls.ToolBar, tyControls.Button;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

var
  Bar: TTyControlBar;
  TB1, TB2, TB3: TTyToolBar;

// 顶部可停靠工具带宿主
Bar := TTyControlBar.Create(Self);
Bar.Parent := Self;
Bar.Align := alTop;          // 随 band 行数自动增高
Bar.BandHeight := 28;        // 每条 band 高度
Bar.GripperWidth := 14;      // 抓手宽度
Bar.BandSpacing := 4;        // band / 行内间距

// 把三条工具条作为子控件放入 band 宿主，放不下时自动换到下一条 band
TB1 := TTyToolBar.Create(Self); TB1.Parent := Bar; TB1.Align := alNone; TB1.Width := 160;
TB2 := TTyToolBar.Create(Self); TB2.Parent := Bar; TB2.Align := alNone; TB2.Width := 120;
TB3 := TTyToolBar.Create(Self); TB3.Parent := Bar; TB3.Align := alNone; TB3.Width := 200;

// 查询某条工具条落在第几条 band
ShowMessage(Format('TB3 在第 %d 条 band', [Bar.BandIndexOf(TB3)]));
```

> 子控件请设 `Align := alNone`，交由 band 宿主排布（若保留 `alTop`/`alClient`，LCL 对齐引擎会与 band 排布冲突）。

---

## 8. 注意事项

- **子控件即 band 项：** 把控件的 `Parent` 设为 band 宿主即完成停靠；宿主是 `csAcceptsControls` 容器（继承自 `TTyPanel`），在 `AlignControls` 里按子控件顺序（仅可见者）逐个装带。band 高度由 `BandHeight` 统一覆盖子控件高度，子控件只需设 `Width`。
- **Align 自动增高：** 当 `Align in [alTop, alBottom]` 时，宿主高度按 band 行数自动调整（`bands*BandHeight + (bands-1)*BandSpacing + 边距`）——不要在代码里硬设与之冲突的 `Height`。
- **重入守卫：** `AlignControls` 末尾对 `Height` 的赋值会再次触发 `AlignControls`，`FInLayout` 守卫防止无限递归。
- **band 分配以子控件为键：** 每个子控件所属 band 索引存于以子控件为键的并行数组，跨重排保留；子控件被释放时经 `Notification(opRemove)` 从数组中剔除并压实，不会留下悬挂键。
- **超宽子控件：** 比一行可用宽度还宽的子控件被钳制到可用宽度并独占其 band（不会死循环）；如需完整显示，请增大宿主宽度或减小 `GripperWidth`。
- **复用 TyPanel typeKey：** 本控件 `GetStyleTypeKey` 返回 `'TyPanel'`，与普通面板共用 tycss 规则，**未新增任何主题令牌**；抓手 / band 分隔色取 `border-color`。
- **实时拖拽换带：** band 间拖拽换带属于真机交互，当前版本的排布是纯几何的（`TyControlBarPack`）；`BandIndexOf` 提供只读的 band 归属查询，供拖拽逻辑将来更新分配。
- **DFM 序列化：** `BandHeight`/`RowSize`/`GripperWidth`/`BandSpacing` 均声明了默认值，等于默认值时不写入 `.lfm`/`.dfm`。
