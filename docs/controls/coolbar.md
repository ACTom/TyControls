# TTyCoolBar

## 1. 概述

`TTyCoolBar` 是 TyControls 库中的 **rebar（可调节带）容器**，继承自 `TTyControlBar`（同批次由兄弟控件提供的"带打包"基类）。它把每个子控件停靠成一条水平"带"（band），并在每条带的左侧提供一个**夹具（gripper）**。

### 夹具手势一览

| 手势 | 结果 |
|------|------|
| 横向拖动夹具 | **移动这条缝**：夹具左边那条带变宽 / 变窄，被抓的带本身不改宽 |
| 横向拖动**该行首条带**的夹具 | 它左边没有带、也就没有缝 → 整个手势变成**移动**（重排），不是改宽 |
| 向下拖到别的行 | 该带独占一行（`Break`） |
| **向上拖回上一行** | **并回该行**：目标行上的带按需让出宽度（到各自 `MinWidth` 为止）腾位；让不出来则整个手势**被拒绝**，什么都不动 |
| 同行内拖过相邻带 | **两条带交换次序**（重排） |
| 拖到最后一行下方 | 该带移到末尾并独占新的一行 |

> **夹具是缝，不是把手。** 真实 rebar 里夹具代表的是它与**同一行前一条带**之间的边界；拖动它就是搬这条边界，一条带长多少、另一条就让多少。本库早期版本是"只改被拖的那条带"，那不是参考行为，也正是这个手势当初显得没用的原因。Lazarus 的 `TCoolBar` 改的是 `FVisiBands[FDraggedBandIndex-1].Width`（`lcl/include/coolbar.inc:938`），即被拖带的**前一条**；行首带的夹具在参考实现里被路由成移动（`coolbar.inc:899` 的 `IsFirstAtRow` 分支）。本控件与之一致。

> **往回拖为什么曾经完全没反应。** 一条带跑到下一行有**两个**原因：它自己的 `Break`（用户把它拖下去的），或者纯粹**放不下**（溢出）。而"往上拖"这个手势当初只做一件事——清 `Break`。对溢出下来的带，`Break` 本来就是 `False`，清了等于没清，下一趟打包照样把它挤下去：**手势不是被拒绝，而是悄无声息地什么也没做**。更糟的是重排跑在前面，拖动途中指针只要越过邻居的中点就会被判成**交换**，于是"只有交换还有反应"。现在向上拖由**并行（rejoin）**独占：先向目标行要宽度（`TyCoolRowMakeRoom`），要得到就并回去，要不到就拒绝且**一个像素都不动**。
>
> **这一条不是照 Lazarus 抄的。** `TCoolBar` 有同样的死手势——它的 `CalculateAndAlign` 只按溢出换行（`RowEndHelper`，`coolbar.inc:1391`），整个单元里没有任何一处会在落band时减少别的带的 `Width`。**参考是 Win32 的 rebar**：它会把行上的带压到各自的 `cxMinChild`，本库的 `BandMinWidth` 就是那个 `cxMinChild`。

与父类 `TTyControlBar` 的区别在于：`TTyCoolBar` 让每条带**可拖动重排、可拖动改宽**，并为每条带引入按子控件键控的 `Width` / `MinWidth` / `MaxWidth` 元数据。典型用途：经典 Office / IE 风格的可拖拽工具带条。

> **交互 vs 数学：** 真正的拖动（鼠标捕获）属于真机行为；**缝的归属**、**落点**、**命中判定**与**改宽钳制**四处几何都被抽成纯函数（`TyCoolBandSeamOwner` / `TyCoolBandDropIndex` / `TyCoolGripperHit` / `TyCoolBandResize`），可无窗口 headless 单测。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.CoolBar` |
| `GetStyleTypeKey` 返回值 | `'TyCoolBar'`（**自有 typeKey**） |
| 基类 | `TTyControlBar`（带打包容器；其 `GetStyleTypeKey` 为 `'TyControlBar'`） |
| 默认夹具宽度 | 10（逻辑像素） |
| 默认带最小宽度 | 24（逻辑像素） |

它从前和基类一样返回 `'TyPanel'`，主题层因此够不着它。现在两者各有其名：`TyCoolBar` 已作为附加选择器并入主题里 `TyPanel` 的规则块，解析值与从前逐字节相同，**开钩子而不动像素**；第三方主题若只覆盖了 `TyPanel`，需要补上 `TyCoolBar`（主题层按 typeKey 全有全无地回落）。

与基类分名是有实质理由的：`TTyCoolBar` 的夹具是**可交互**的（`MouseDown` 经 `TyCoolGripperHit` 命中后拖动即改宽 / 重排），而 `TTyControlBar` 的夹具只是装饰；一套皮肤完全有理由让"能拖的导轨"和"只是好看的导轨"读起来不一样。

### 子部件 typeKey

**没有。** 本控件没有自己的 `Paint`——像素全部来自 `TTyControlBar`（面板框架 + 每条带一个夹具），夹具颜色从盒子样式的 `border-color`（缺省回落 `color`）派生，粗细 / 间距 / 内缩是代码里的 `Scale()` 字面量。子部件键 `TyCoolBarGripper` 的扩展已被**刻意推迟**，该键当前**并不存在**，写进 `.tycss` 解析不到任何东西。

```pascal
uses tyControls.CoolBar, tyControls.ControlBar, tyControls.Panel;
```

---

## 3. 属性表

### 3.1 TTyCoolBar 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `GripperWidth` | `Integer` | `10` | 每条带左侧夹具列的逻辑宽度（像素）。夹具是可拖拽区域；改值触发 `Realign` 重新打包各带。 |
| `DefaultBandMinWidth` | `Integer` | `24` | 未单独设置 `MinWidth` 的带在拖动改宽时的下限（逻辑像素）。 |
| `Align` / `Anchors` | — | — | 停靠 / 锚点（继承）。 |
| `StyleClass` / `Controller` | — | — | CSS 类名 / 样式控制器（继承）。 |

### 3.2 每带元数据 API（按子控件键控）

带的宽度 / 钳制**不是**按位置索引的平行数组，而是以子控件 `TControl` 为键存储；因此**重排、删除其它带都不会串位**，子控件被 free 时其条目在 `Notification(opRemove)` 中自动丢弃。

| 方法 | 说明 |
|------|------|
| `SetBandWidth(ACtl, AWidth)` | 设定某带的固定 / 指定宽度（逻辑像素）；`AWidth <= 0` 清除为 auto。会把子控件宽度同步为该值并 `Realign`。 |
| `GetBandWidth(ACtl): Integer` | 读取某带的存储宽度（未设为 `0` = auto）。 |
| `SetBandMinWidth(ACtl, AMinWidth)` | 设定某带拖动改宽的下限；未设时回退 `DefaultBandMinWidth`。 |
| `SetBandMaxWidth(ACtl, AMaxWidth)` | 设定手填上限；`0` = 无上限。 |
| `BandMinWidth(ACtl): Integer` | 生效下限（自有 min 优先，否则默认，且不小于 1）。**改宽和并行挤压共用这一个下限**——两个手势不可能压到对方尊重不了的位置。 |
| `BandMaxWidth(ACtl): Integer` | 生效上限（`0` = 无上限）。**三个上限在这一个函数里合流**，见 3.4。 |
| `SetBandAutoMaxWidth(ACtl, AValue)` | 打开/关闭"按内容封顶"（见 3.4）。默认关。 |
| `BandAutoMaxWidth(ACtl): Boolean` | 该带是否按内容封顶。 |

### 3.4 带能被拖多宽：三个上限，一处合流

`MaxWidth` 是手填的数字，内容一变它就过期，也说不出"拖到没有控件可露了就该停"。`TTyCoolBand.AutoMaxWidth`（**默认 `False`**）改成去问宿主控件本人。

| 来源 | 何时生效 | 取自 |
|------|----------|------|
| `TTyCoolBand.MaxWidth` | 始终（`0` = 无意见） | 手填 |
| `Control.Constraints.MaxWidth` | 仅 `AutoMaxWidth = True` 时 | 控件作者显式声明的上限 |
| 控件的 **raw 首选宽度** | 仅 `AutoMaxWidth = True` 时 | `GetPreferredSize(..., Raw=True)` |

**优先级只有一条规则，且只写在 `BandMaxWidth` 一处：`0` 表示"无意见"、直接出局；剩下的取最小。** 所以两个上限永远不会打架——谁先用完谁停住手势；`AutoMaxWidth = False` 时答案与从前逐字节相同。

- **为什么必须是 `Raw`。** 非 raw 的 `GetPreferredSize` 在控件没有首选宽度时会**用控件当前的 `Width` 顶上**（`lcl/include/control.inc:5635`），而带的当前宽度正是拖动在改的那个数——拿它当上限等于把每条带钉死在它当下的位置，第一次外拖就变成死手势，也就是本次修的那类 bug。
- **为什么不用控件自己的 `Width`。** 同上，而且实测有误导性：本机上一条挂了三个按钮的 `TTyToolBarEx` 对齐后 `Width` 读到 600，raw 首选宽度是 125（它真正的内容宽）；`TTyEdit` raw 读 0（没有意见）、非 raw 读 140（只是它自己的宽度）。见 `tests/coolbarrejoin` case 4。
- **没有意见的控件不封顶。** 编辑框多宽都合理，本特性只给"内容有尽头"的带封顶，不替没有尽头的带凭空造一个。
- **上限的坐标系是"子控件宽度"，不含夹具/标题条。** 因为 `TTyCoolBand.Width` 设的、`TyCoolBandResize` 钳的都是这个数。Lazarus 的 `TCoolBand.Width` 是另一套约定（它的 `CalcPreferredWidth` 会加上 `CalcControlLeft`），照搬过来会让带比内容**多长出一个夹具**。用户看到的整条带 = `夹具 + 上限`，正好落在内容最后一个像素上。
- **到顶是"停住"，不是"没反应"。** 带先真的变宽、到内容边界才停——这与本次修掉的"从头到尾一动不动"是两回事。（到顶后继续拖确实不再动，这和 `MinWidth` 到底后继续拖一样。）
- **打开这个开关不会追溯性地缩窄已经比内容宽的带**：它约束的是**手势**，设计期勾一下就动别人已经摆好的版是更坏的行为。

### 3.3 继承成员

继承自 `TTyControlBar` → `TTyCustomControl`：`Enabled` / `Font` / `Hint` / `TabOrder` / Tier A 鼠标事件 + Tier B 键盘焦点事件等。完整清单见 [../events.md](../events.md)。

---

## 4. 纯函数（headless 单测的核心）

```pascal
{ 拖动夹具后带的新宽度：起始宽 AStartW + 位移 ADx，钳制到 [AMinW .. AMaxW]。
  AMaxW <= 0 表示无上限（只作用下限）；AMinW 至少为 1，带永不塌缩为 0。 }
function TyCoolBandResize(AStartW, ADx, AMinW, AMaxW: Integer): Integer;

{ 命中判定：APt 是否落在 ABandRect 左侧 AGripperW 像素宽的夹具列内（设备像素）。
  右边界半开、上闭下开，与 LCL 命中一致；AGripperW <= 0 → 无夹具 → 永远 False。 }
function TyCoolGripperHit(const ABandRect: TRect; AGripperW: Integer; const APt: TPoint): Boolean;

{ AIndex 这条带的夹具压在谁的尾边上——也就是拖动它真正改宽的那条带。
  返回同一行里它前面那条带的下标；AIndex 是本行首条时返回 -1（没有缝，手势改为移动）。
  行的判定用打包器写下的 Top（纵向时用 Left），与 BandRectFor 读的是同一个数，
  所以打包 / 绘制 / 命中不可能对"谁和谁同行"有分歧。 }
function TyCoolBandSeamOwner(const ARects: TTyRectArray; AIndex: Integer;
  AVertical: Boolean = False): Integer;

{ 拖动中的带应该落到哪个位置。返回目标下标（已扣除它自己离开原位的位移，可直接交给
  列表移动）；无变化时返回 ADragIndex；越过最后一行时返回 TyCoolDropNewRow(-2)，
  表示"移到末尾并独占新的一行"。
  用中点而非参考实现的尾边判定，因为本控件在拖动过程中**实时**提交：两条带一旦交换，
  指针就落在被拖带自己身上，函数返回 ADragIndex 而稳定下来；若用尾边判定并逐次
  重算，会在边界上来回抖动。 }
function TyCoolBandDropIndex(const ARects: TTyRectArray; ADragIndex: Integer;
  const APt: TPoint; ARightToLeft: Boolean = False): Integer;

{ 为"再挤进一条带"腾地方：目标行上已有的带按需让出宽度（到各自最小值为止）。
  AExtents/AMins/ALeads 是行上已有各带（行内次序，打包器的设备像素坐标系）；
  AInsertAt 是新带在行内落到第几位；AJoinLead/AJoinExtent 是新带自己的。
  让宽次序：先给**落点前面最近**那条，再往行首走；这一侧全到底了才轮到落点后面的，
  同样由近及远。近侧优先就是夹具那条"缝"的规则——被拖的带一落位就拥有这条边界；
  会往远侧继续，是为了让"拒绝"真的意味着"整行都没富余"，而不是"隔壁没富余"。
  返回 True = 挤得下（ANewExtents 是挤压后的宽度，本来就够时原样返回）；
  返回 False = 即使人人到最小值也放不下，此时 ANewExtents **原样返回**——
  拒绝绝不半途生效，否则版面动了而带还是没进来。 }
function TyCoolRowMakeRoom(const AExtents, AMins, ALeads: array of Integer;
  AInsertAt, AJoinLead, AJoinExtent, AAvail, ASpacing: Integer;
  out ANewExtents: TTyCoolExtents): Boolean;
```

- `TyCoolBandResize`：`AMaxW < AMinW` 的非法区间会塌缩到下限；`AMinW <= 0` 被抬到 1。
- `TyCoolGripperHit`：左边界 inclusive、右边界 `Left+AGripperW` exclusive；纵向 `Top` inclusive、`Bottom` exclusive。
- `TyCoolBandSeamOwner`：**不**接受方向参数——镜像后第 i-1 条带跑到第 i 条的右边，但它仍是这条缝的归属者，下标规则不变。
- `TyCoolBandDropIndex`：`ARightToLeft` 只翻转"越过中点"的比较方向，别的都不动。
- `TyCoolRowMakeRoom` 的行成本公式是 `Σ(lead+extent) + n*spacing + (joinLead+joinExtent)`：打包器每个**间隙**收一次 `spacing`，`n+1` 条带只有 `n` 个间隙，因此总成本与次序无关——落点只决定**谁让**，不决定**让多少**。
- `TyCoolRowMakeRoom` **没有自己的下限常量**：数字全部由调用方（`TTyCoolBar.BandMinWidth`，也正是改宽手势拿到的那一个）传入；函数内两处保护（`AMins` 比带少时补 1、`< 1` 抬到 1）与 `TyCoolBandResize` 对 `AMinW` 的处理逐字对应，改一个必须改另一个。
- `TyCoolBandDropIndex` 的 `AVertical` 走的是**转置**而不是分支：把矩形和落点的 x/y 对调后跑同一套规则，于是"落在哪一组"由 x 决定、"组内次序"由 y 决定，"越过最后一行"变成"越过最后一列"。写成两份分轴的实现，正是两根轴迟早差一个像素或差一个比较方向的来源。纵向时 `ARightToLeft` 被忽略：镜像纵向 rebar 反转的是**列序**，列内自上而下不是阅读方向。

---

## 5. 事件

`TTyCoolBar` **无自有专有事件**——它只暴露基线事件集。拖动重排 / 改宽的语义变更由基类打包机制处理；命令响应挂在各**子控件**上（如子带里的按钮 `OnClick`）。

---

## 6. 状态与主题

`TTyCoolBar` 的外观（背景 / 边框）由主题的 `TyCoolBar` 规则决定。内置主题把它与 `TyPanel`、`TyControlBar` 等键写在同一条规则里（取值相同、名字各自独立），所以默认观感与面板一致；想让 rebar 单独换一套（更暗的底、无圆角、无边框），另写一条 `TyCoolBar { ... }` 即可，**不要**去改 `TyPanel`——那会重涂全应用的面板。

夹具本身用 painter 图元（两条竖直导轨）在带左缘绘制（真机可见），颜色取自当前样式的边框 / 文本色，仍为主题令牌驱动；但夹具没有独立的键，"只改夹具不改带底色"目前做不到（见 2 节）。

---

## 7. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.CoolBar, tyControls.Panel, tyControls.Button;

var
  Cool: TTyCoolBar;
  Band1, Band2: TTyPanel;
begin
  TyDefaultController.LoadTheme('themes/light.tycss');

  Cool := TTyCoolBar.Create(Self);
  Cool.Parent := Self;
  Cool.Align := alTop;
  Cool.GripperWidth := 10;          // 每条带左侧夹具列宽度

  // 第一条带：一个子容器（可再放按钮 / 编辑器等）
  Band1 := TTyPanel.Create(Self);
  Band1.Parent := Cool;             // 关键：父控件是 CoolBar → 成为一条带
  Cool.SetBandWidth(Band1, 160);    // 给这条带一个固定宽度
  Cool.SetBandMinWidth(Band1, 80);  // 拖动改宽的下限

  // 第二条带
  Band2 := TTyPanel.Create(Self);
  Band2.Parent := Cool;
  Cool.SetBandWidth(Band2, 200);
  Cool.SetBandMaxWidth(Band2, 400); // 拖动改宽的上限
end;
```

---

## 8. 注意事项

- **子控件即一条带：** 把子控件 `Parent := CoolBar` 即成为一条带；`TTyCoolBar` 是 `csAcceptsControls` 容器（继承自基类）。
- **元数据按控件键控：** `Width` / `MinWidth` / `MaxWidth` 以子控件为键存储；重排、删除其它带不串位，子控件 free 时条目自动丢弃（`Notification/opRemove`）。切勿假设它按位置索引。
- **拖动分辨：** `MouseDown` 命中夹具后进入拖动；横向位移 → 改宽（移动缝），纵向位移 → 换行 / 重排。方向由 `TyCoolDragMode` 消歧，纵向优先——带被换行的次数远多于被改宽，横向抖动不该翻转手势含义。
- **向上拖优先于重排，这是有意的顺序：** 一次 `cdMove` 里先算指针在第几行。指针**在更上面的行** → 只走并行（rejoin），不给重排机会；否则才是重排（同行交换 / 拖到最后一行下方）。反过来（重排在前）就是这个 bug 的一半：向上拖的途中指针偶然越过某个邻居的中点，手势就被判成交换，带永远到不了目的地。
- **并行被拒绝时什么都不动：** 宽度、子控件次序、`Break`、`OnChange` 一个都不动。这是唯一一种"什么都没发生"的情况，其余向上拖都会动东西——和从前"每一次向上拖都什么也没发生"正相反。
- **纵向时"带的尺度"是高度：** `TTyCoolBand.Width`（以及 `SetBandWidth` / 并行挤压）赋的是子控件在**行程轴**上的尺寸——横向是 `Width`，纵向是 `Height`。纵向写 `Width` 会落在**列厚**那根轴上，而列厚由 `BandHeight` 决定、根本没人读那个赋值。
- **改宽改的是"缝左边那条带"：** 钳制用的 `MinWidth` / `MaxWidth` / `FixedSize` 都取自**缝的归属者**（被拖带的前一条），不是被拖的那条。给一条带设 `FixedSize := True`，挡住的是**它右邻**的夹具拖动。
- **重排改的是子控件次序：** 通过 `TWinControl.SetControlIndex` 把子控件挪到父控件列表的新位置。打包器就是按 `Controls[]` 的次序读的，所以布局、夹具绘制、命中判定全部自动跟随，没有第二份次序要同步。早期版本注释里说"LCL 只暴露 `SetZOrder(TopMost)`、无法任意定位子控件"——那是错的，`controls.pp:2400` 就是这个原语。
- **改宽是逻辑像素：** 拖动位移从设备像素折算为逻辑像素（`MulDiv(dx,96,PPI)`）再钳制，带宽以逻辑像素存储。
- **带不会压在自己的边框上：** 各带排布在 `BandContentRect`（客户区扣掉主题描边的那圈）里，而不是原始 `ClientRect`。带是窗口化子控件——它在父控件之后绘制，并且会把自己的矩形整个擦掉——所以压在描边上不是"盖住"而是"抹掉"。内缩宽度取自 `border-width` 主题令牌，边框更粗的皮肤（xp / classic）会自动一起让位。
- **自有 typeKey：** `GetStyleTypeKey` 返回 `'TyCoolBar'`（基类为 `'TyControlBar'`）。主题需要各自定义这些键——只写 `TyPanel` 不再覆盖 rebar。
- **DFM 序列化：** `GripperWidth`（`default 10`）/ `DefaultBandMinWidth`（`default 24`）/ `TTyCoolBand.AutoMaxWidth`（`default False`）声明了默认值，等于默认值时不写入 `.lfm`/`.dfm`——所以现存窗体的行为一个字节都不变。
- **没有宿主控件的带（纯标题分隔带）不参与布局：** 它在设计期集合里存在，但打包器读的是 `Controls[]`，它不贡献子控件，因此不会被打包、没有夹具、也不会被改宽。所以"内容封顶对空带意味着什么"这个问题不成立——不是"上限为 0"，而是这条带压根不在版面里。
- **右到左镜像（`BiDiMode := bdRightToLeft`）：** 每条带的专属夹具移到该带的**右**侧，带从右往左铺，`Break` 换行规则不变。横向 `TyCoolBarPack` 与纵向 `TyCoolBarPackVertical` 都新增了 `ARightToLeft`（纵向另需 `ACrossExtent`，因为它的 `AAvail` 描述的是**列的行程**即高度，要镜像的是另一根轴）；纵向镜像只反转**列序**，夹具仍在各自带的正上方——上下不是阅读方向。
- **拖动的符号跟着翻：** 带是朝着背离夹具的方向长的，镜像后夹具在右，所以**向左**拖才是变宽；纵向拖动换列同理改从右边缘计数。这类符号错误在任何静态截图上都看不出来——界面完全正确，一拖就朝反方向走。
- **夹具的绘制与命中共用一处：** `PaintGrippers` 画 `BandRectFor` 返回的条，`BandAtPoint` 命中同一个 `BandRectFor`，所以不存在“画在一边、抓在另一边”。纯函数 `TyCoolGripperHit` 有意**不加**方向参数：控件的命中不走它，给它加一个只会多出一份没人用的“夹具在哪一侧”的说法。见 [rtl.md](../rtl.md)。
