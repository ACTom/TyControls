# TTySteps

## 1. 概述

`TTySteps` 是 TyControls 库中的主题化「步骤条 / 向导轨」控件，继承自 `TTyCustomControl`（窗口化控件，可获得焦点）。它把若干个带编号的标记（marker）用连线串成一条轨道——横着是向导的页眉（标记在上、标题在下、线向右跑），竖着是安装器的左侧轨（标记在左、标题在旁、线向下掉）——一眼说清**哪几步已走完、当前在哪一步、还剩哪几步**。

**它补的是哪个缺口：** 安装 / 配置向导离不开它，而此前只能每处手工拼——每步一个 `TTyLabel`，再加一个手工染色的 `TTyPanel` 当线，即**每处硬编码一份颜色**，且每加一步就得手工重排一次。库里此前**根本没有**「在一串具名阶段中的进度」这个语义：`TTyProgressBar` 是没有名字的连续分数，`TTyTabSet` / `TTyPageControl` 是**用户驱动**的页面装饰，而这里是**宿主驱动**的状态。

**每步的状态是「推导」出来的，不是存起来的**（`TTyStepStatus`）：`StepIndex` 之前的都已完成，`StepIndex` 那一步是当前步，其余的都在等待。宿主只挪**一个整数**，整条轨道自己重读——没有任何需要同步的每步状态。

---

## 2. 基本信息

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Steps` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| `GetStyleTypeKey` 返回值 | `'TySteps'`（**轨道本体**：`background` / `border-*` / `color` / `font-*` / `padding` / `opacity` / `shadow` / `outline`；它的 `color` / `font-*` 还是每一步文字的兜底） |
| 步骤 typeKey | `'TyStepsItem'`（**一步**：`background` / `border-*` / `color` / `font-*`。`:selected` = 当前步，`:disabled` = 等待中的步，**静止层 = 已完成的步**） |
| 连线 typeKey | `'TyStepsConnector'`（**两个标记之间的线**：只读 `background`，不画任何文字） |
| 默认尺寸 | 360 × 56（逻辑像素，构造时设置——设计器里够放三四步的向导页眉） |
| 新增 token | `--steps-marker-size` / `--steps-gap` / `--steps-connector-gap` / `--steps-connector-size` / `--steps-connector-length`（见第 5 节） |
| 变体约定 | `TyStepsItem.error`（常量 `TyStepsErrorVariant = 'error'`） |

```pascal
uses tyControls.Steps;
```

**为什么是窗口化控件（有句柄）？** 因为 `Clickable := True` 时它要**取焦点**、要用**方向键**走轨道——这两件事图形控件都做不到（没句柄就没焦点、收不到 key message）。这是它与同批次的 `TTyTag` / `TTyAlert`（图形控件）分道的**唯一**理由；保持 `Clickable = False` 默认值的轨道则是一条**永不吃 Tab** 的惰性状态显示。

**为什么连线要有自己的 typeKey？** 因为它的颜色**推导不出来**：标准观感下，已完成的标记是一枚淡色 chip + 一圈描边 + 一个勾，而从它出发的那条线是实心的——那个颜色既不是 chip 的 `background`，也不是勾的 `color`，更不是描边的 `border-color`。它取什么状态见第 6 节。

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Items` | `TStrings` | 空 | 各步骤，**一行一个标题**。用解析后的 `TyStepsItem` 样式绘制（**不**读取 LCL `Font.*`），**左对齐**、放不下时省略号截断（`Config…`）。**不解析助记符**：轨道不激活任何东西，`&` 就是字面字符。编辑列表会重新贴合自动尺寸的轨道；**不会**重新校验 `StepIndex`。 |
| `StepIndex` | `Integer` | `-1` | 向导**正处在**哪一步：它之前的都已完成，之后的都在等待。**不夹取到列表范围内**——`-1` = 「尚未开始」，`Count` = 「全部完成」，两者都是向导真实经过的状态（见第 4 节）。变化时触发 `OnChange`。 |
| `ErrorIndex` | `Integer` | `-1` | **失败**的那一步，`-1` = 无。失败步会在「它所处位置的状态」之上再叠一个 `TyStepsItem.error` 变体，并把数字换成错误标记。**不**触发 `OnChange`（向导并没有挪窝），也**不**重新贴合。 |
| `Orientation` | `TTyStepsOrientation` | `soHorizontal` | `(soHorizontal, soVertical)`。改它会重新贴合自动尺寸的轨道（两种布局的自然尺寸**完全不同**），并清掉残留的悬停。 |
| `Clickable` | `Boolean` | `False` | 让**用户**能点一步、或用方向键走到一步上（Ant 的 onChange Steps）。**默认关**：向导自己用 Next/Back 驱动 `StepIndex`，一条能让用户悄悄跳到第 5 步的进度条在多数向导里是 bug。打开它会**顺带把轨道变成可聚焦的**（它会去设 `TabStop`），因为方向键正是它买来的一半价值。 |
| `OnChange` | `TNotifyEvent` | `nil` | 见第 4 节。 |
| `AutoSize` | `Boolean` | `False` | 开启后轨道在**两个轴**上都贴合自然尺寸：主轴是「每步一个自然格」，交叉轴是「标记 + 间隙 + 标题块」。 |

### 继承的通用成员

`TTySteps` 继承自 `TTyCustomControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | **变体入口**：对应 `.tycss` 里 `TySteps.<classname>`。解析每一步 / 每条连线时**带上同一个 `StyleClass`**，所以 `TyStepsItem.compact` 能跟着轨道一起换。 |
| `StyleOverride` | `string` | `''` | 单实例内联 CSS 声明块（可引用 `var(--...)` 令牌）。 |
| `Controller` | `TTyStyleController` | `nil`（用全局 `TyDefaultController`） | 指定样式控制器。 |
| `TabStop` | `Boolean` | **`False`**（构造时显式设置） | 跟着 `Clickable` 走：`Clickable := True` 把它设为 `True`，`:= False` 再还回去。**流式加载（`.lfm`）期间 setter 不动它**，改由 `Loaded` 在所有流式值就位后**重新断言**这条耦合。曾经的理由是「设计器跑过同一个 setter，存下来的值本就是对的」——**那是错的**：`TabStop` 的**声明默认值**是 `False`（`TWinControl` 的），所以设计器写出的 `TabStop = True` 只是因为 setter 已经先翻过它；而**手写的 `.lfm`（本仓库每个 example 都是手写的）只会写 `Clickable = True`，对 `TabStop` 只字不提**。于是轨道曾以 `TabStop = False` 流进来：Tab 到不了，鼠标也点不到焦点（`TTyCustomControl.MouseDown` 的点击取焦点以 `TabStop` 为闸门），方向键——`Clickable` 买来的另一半——于是永远拿不到按键。这就是论坛 #8「方向键无效」的真正成因，`55adc88` 修的正是这里。想要「可点但不可聚焦」的轨道，仍可在加载后自行赋 `TabStop`。 |

另暴露 `Enabled` / `Font` / `Align` / `Anchors` / `OnClick` 及 `TTyCustomControl` 基线事件集（含 `OnKeyDown` / `OnEnter` / `OnExit` 等），见 [../events.md](../events.md)。

---

## 4. 事件

| 事件 | 触发时机 |
|------|----------|
| `OnChange` | `StepIndex` **确实发生变化**时触发——点击、按键、代码赋值一视同仁。重复设成同一个值不是变化，**不**触发。**流式加载（`.lfm`）期间不触发**：加载一张窗体不是一次步骤变更，而此时 `.lfm` 里的处理器已经挂上了，在窗体还没显示时就告诉宿主「步骤变了」是错的。 |
| `OnClick` | `TControl` 基线点击事件，照常触发。 |

> **`StepIndex` 不是选择，是「进度游标」**（这是它与 `TTySegmented.ItemIndex` 的根本分野）：它可以合法地**指在两步之间**。`-1` 表示「尚未开始」（每一步都在等），`Count` 表示「全部完成」——后者恰恰就是最后一次 Next 点击产生的值。像 `TTyListBox` 夹取 `ItemIndex` 那样夹它，会把这两个状态直接毁掉。

---

## 5. 关键成员

### 纯规则 / 几何函数（单元级，可无句柄直接调用）

```pascal
type
  TTyStepsOrientation = (soHorizontal, soVertical);
  TTyStepStatus = (sstWait, sstProcess, sstFinish, sstError);

  TTyStepsLayout = record
    MarkerRect: TRect;      // 方形标记槽位（数字 / 勾 / 错误标记）
    TitleRect: TRect;       // 标题的行带（画笔在其中垂直居中）
    ConnectorRect: TRect;   // 通向「下一步」的线（最后一步恒为空）
  end;

function TyStepStatus(AIndex, AStepIndex, AErrorIndex, ACount: Integer): TTyStepStatus;
function TyStepStates(AIndex, AStepIndex, ACount: Integer): TTyStateSet;

function TyStepsCellRect(AClientWidth, AClientHeight, ACount, AIndex: Integer;
  AVertical: Boolean; APadLeft, APadTop, APadRight, APadBottom: Integer): TRect;
function TyStepsIndexAt(AClientWidth, AClientHeight, ACount: Integer;
  AVertical: Boolean; APadLeft, APadTop, APadRight, APadBottom, X, Y: Integer): Integer;

function TyStepsItemLayout(const ACell: TRect; AVertical, AIsLast: Boolean;
  AMarkerSize, AGap, ATitleHeight, AConnectorGap, AConnectorSize: Integer): TTyStepsLayout;

procedure TyStepsPreferredSize(ACount, AWidestTitle, ATitleHeight, AMarkerSize, AGap,
  AConnectorGap, AConnectorLength, APadLeft, APadTop, APadRight, APadBottom: Integer;
  AVertical: Boolean; out AWidth, AHeight: Integer);

function TyStepsStepIndex(ACurrent, ACount, ADelta: Integer): Integer;
```

全部整数 / 布尔入参，无控件状态、无句柄、无主题依赖，测试直接调用（`tests/test.steps.pas`）。要点：

- **`TyStepStatus`** —— **整个控件赖以存在的那条规则**，也是「没有任何每步状态被存起来」的原因：
  - `AIndex < AStepIndex` → `sstFinish`（已走过）
  - `AIndex = AStepIndex` → `sstProcess`（你在这）
  - `AIndex > AStepIndex` → `sstWait`（还没到）
  - `AIndex = AErrorIndex` **压倒**上面三条，**不论它在哪**：失败的步就是失败的，无论它是当前步还是已走过的步（Ant 的规矩）。`AErrorIndex = -1` 永远匹配不上（`AIndex` 已知 ≥ 0）。
  - `[0, ACount)` 之外的 index **根本不是一步**，答 `sstWait`。
- **`TyStepStates`** —— status → state 的**全部**词汇表，且**一个新词都没发明**，每个值都是既有的 `TTyState`：`sstFinish` → `[tysNormal]`、`sstProcess` → `[tysSelected]`、`sstWait` → `[tysDisabled]`。**永不返回空集**。**错误不在这里**（这个函数压根不吃 error index）：错误是**变体**不是状态——状态集里没有 error 成员，硬造一个会和其余每个控件的词汇表撞车。所以失败步**保留它所处位置的状态**（失败的当前步**仍然**是 `:selected`），再叠上 `TyStepsItem.error`；两个轴**叠加**而不是打架。
- **`TyStepsCellRect`** —— 一步的「格」（它在轨道里分到的那份），设备像素、相对控件左上角。各格沿主轴**精确铺满** padding 带：**第 i 格的远边就是第 i+1 格的近边**，没有点击会掉进去的缝。用整数除法切分，除不尽时各格相差至多 1px，而不是把余数堆到某一格上。退化请求（无步骤 / index 越界 / 零面积 / padding 吃掉整条轨道）返回零尺寸矩形，**绝不反向**。
- **`TyStepsIndexAt`** 是 `TyStepsCellRect` 的**精确逆**（它就是扫描后者产出的矩形），所以**点到哪一步，就是画在那里的那一步**，两者永远不会漂移。**整个格都是命中区，不只是标记**——标题是死的轨道是很糟的点击目标。轨道的 padding 边沟不属于任何一步，答 `-1`。
- **`TyStepsItemLayout`** —— 一格之内标记 / 标题 / 连线的位置。两种布局都把标记锚在格的**前缘**而**不是**居中，**这正是这个函数得以保持「纯」的诀窍**：下一格的标记就在它自己的前缘上，而那就是本格的远边——于是一条跑到本格远边的线，**恰好**接上下一个标记，而本函数**从不需要知道第 i+1 格的存在**。标记若居中，这里就必须做跨格算术。
  - **横向**：标记在格的左侧、标题在它**正下方**（两者都左对齐，所以标题绝不会从自己的标记那儿漂走），这一整块在格高里居中；连线从标记向右跑，跑在**标记的中线高度**上——即**在标题上方**，两者永不重叠。
  - **纵向**：标记在格的**左上角**、标题在它**旁边**并以标记中线为准居中；连线从标记下方掉下去，沿标记的中轴。
  - 格里塞不下某样东西时，该矩形为**空**，而不是反向或溢出的；槽位只会被**压进**格里，绝不越界。
- **`TyStepsPreferredSize`** 是上面两者的**逆**：把它的结果当客户区尺寸回喂（同样的参数），每一格都是一个自然格，且里面**正好**是 `AConnectorLength` 那么长的线（已有往返测试守护）。**主轴** = `ACount` 个自然格，一个自然格 = 标记 + 它的连线跑道（gap + length + gap），若最宽的标题比它还长则取标题——**每格取同一个尺寸**，因为各步大小参差的轨道看着就是坏的。**交叉轴** = 标记 + gap + 标题块（横向）或 标记 + gap + 最宽标题（纵向），**与 `ACount` 无关**。**最后一格照样保留它的连线跑道**当尾部空白，尽管它不画线：各格必须均匀铺满，短一截的末格会让那一步的标记和其余所有标记**错位**——那是一条轨道**绝对不能**犯的错。
- **`TyStepsStepIndex`** —— 方向键的规则：`ACurrent + ADelta`，**夹到一个真实的步骤上**、**不回绕**（一条短序列一眼看得全，跑到头就该停而不是瞬移回起点；沿用 `TTySegmented` 的规矩）。它**永远落在某一步上**，所以键盘**无法**把游标停在「尚未开始」（-1）或「全部完成」（`ACount`）那两个位置上——那是**宿主**设的状态，不是用户能用方向键走进去的。无步骤时答 `-1`。

### 公开成员

```pascal
function Count: Integer;                       // 步骤数
function StepStatus(AIndex: Integer): TTyStepStatus;   // 推导出的状态，给想「问」而不是自己重推的宿主
function TyStepRect(AIndex: Integer): TRect;   // 第 AIndex 格（设备像素，(0,0)-local）；越界为空
function TyStepLayout(AIndex: Integer): TTyStepsLayout; // 该步的三个矩形（同上）；越界时三者全空
function TyStepAt(X, Y: Integer): Integer;     // 客户区 (X,Y) 落在哪一步；边沟 / 界外为 -1
```

这几个查询与绘制**同源**（同一批纯函数、同一份主题令牌），因此「画在哪」和「点得中哪」天然一致。

---

## 6. 状态与主题

### 三个 typeKey 各自取什么状态

- **轨道**（`TySteps`）：`:hover` / `:active` / **`:focus`** / `:disabled` 由基类状态机计算。**焦点属于整条轨道**，不属于某一步——这不需要任何代码：基类的 `CurrentStates` 已经把 `tysFocused` 给了轨道自己的样式，主题写一条 `TySteps:focus { outline: ... }` 就能像其余可聚焦控件一样被 `DrawFrame` 描一圈。
- **标记**（`TyStepsItem`）：取 `TyStepStates` 推导出的**这一步自己的**状态，另加：
  - **`:hover`**：仅在 `Clickable` 且指针落在**这一格**里时。**等待中的步也能悬停**——`Clickable` 让每一步都可达，未来的那几步恰恰就是用户瞄准的目标，那里指针是死的会读成「坏了」。`:disabled` + `:hover` **不是**需要主题去化解的矛盾：引擎最后才套 `:disabled`（最高优先级），所以两条规则都设的属性上它赢；想给指针下加个色调就写 `TyStepsItem:disabled:hover`。
  - **控件 `Enabled = False`**：每一步都补上 `:disabled`，但**当前步保留 `:selected`**。丢掉它，整条轨道会读成「没有当前步」而不是「这个你改不了」，而「你在哪一步」是这个控件**唯一**要说的话。引擎的 `ResolveLayer` 把 `:selected` 当静止层最先套、把 `:disabled` 最后套，所以底片留得住、禁用的笔色照样压得过它——控件里不需要任何分支。禁用时**没有**悬停。
- **标题**：用**同一个** `TyStepsItem` key，但**去掉 `tysSelected`** 后解析（去空后补 `[tysNormal]`）。这是 `TTyCheckBox` 已经解决过的「两种笔色」问题：当前步的标记是一枚 accent 实心 chip + on-accent 笔色，标题**若也用那份笔色**，就成了「轨道表面上的 on-accent 文字」，即**看不见**。所以标题落在静止层、保留轨道原本的文字色，而 `:selected` 就只是一条**标记专用**的规则。**`:disabled` 是故意留着的**——这正是等待中的步「标题变灰」的由来，也是唯一一个值得区分的按状态标题差异；已完成步和当前步的标题读起来一样，就像 checkbox 的 caption 勾不勾都一样。
- **连线**（`TyStepsConnector`）：取的是它**通向**的那一步的状态，**不是**它离开的那一步。这一个选择就让轨迹「用户走到哪就亮到哪」，既没有代码分支也没有第三套状态规则：
  - 通向**已完成**的步 → `[tysNormal]`（静止层规则）
  - 通向**当前**步 → `[tysSelected]`
  - 通向**等待中**的步 → `[tysDisabled]`
  
  反过来取「离开的那一步」的状态，会逼着静止层规则去表示「已走过」而 `:selected` 表示「还没走」——同一幅画倒着写。连线只带**轨道的 `StyleClass`**，**不带 error 变体**：某一步失败并不该给「通向它的那条路」重新上色（Ant 也不动它），而且连线压根没有「错误观感」可定义。

### 变体（`error`）怎么和 `StyleClass` 相处

失败步解析用的 variant 串是 `'error <用户的 StyleClass>'`——**`'error'` 在前，用户的 class 在后**。引擎按文本顺序套用 variant 规则（后者按属性覆盖前者），于是一个显式的 class 能**逐属性**叠在错误观感之**上**，而不是把它整个替换掉。这是 `TTyAlert.StyleVariant` 的规矩，它保证 `Steps.StyleClass := 'compact'` 只是个 padding 微调，**失败步照样是红的**。

### 主题令牌摘要

`themes/light.tycss` 中本控件的规则（原文）：

```css
/* Steps: markers on a rail. The done/current/waiting reading is carried by the item states. */
TySteps         { background: alpha(#FFFFFF, 0); color: var(--on-surface); font-size: var(--font-size-base); }
TySteps:disabled { opacity: var(--disabled-opacity); }
TyStepsItem          { background: var(--surface-track); color: var(--muted);
                       border-color: var(--border); border-width: var(--input-border-width);
                       border-radius: var(--radius-round); font-size: var(--font-size-base); }
TyStepsItem:selected { background: var(--accent); color: var(--on-accent); border-color: var(--accent); }
TyStepsItem:hover    { border-color: var(--accent); }
TyStepsItem:disabled { color: var(--muted); }
/* The connector is a plain filled line: it reads ONLY `background` and draws no text, so it
   deliberately declares no `color` — a colour here would be dead, and (since it would have to
   match the fill to be right) the lint would flag the pair as low-contrast text. */
TyStepsConnector          { background: var(--border); }
TyStepsConnector:selected { background: var(--accent); }
```

读这份规则时值得留意的几点（都是**主题的选择**，不是控件的行为）：

- `TySteps` 的底色是 `alpha(#FFFFFF, 0)`——**全透明但「已定义」**。这一点是刻意的：控件只看 `background` **在不在**（见下方降级），所以轨道既能浮在任何表面上，又不会因为「没底色」而整个不画。
- 它**没写 `padding`**，所以各格铺满整个客户区；也**没写 `:focus`**，所以基础主题下聚焦不描环（要环就自己加一条 `TySteps:focus { outline: 2px var(--focus-ring); }`）。
- `TyStepsConnector` **只有**静止层和 `:selected` 两条规则、**没有** `:disabled`。按上面的映射，这意味着基础主题下「通向已完成步」和「通向等待步」的线**同为 `var(--border)`**，只有紧挨当前步的那一条是 accent。想要 Ant 那种「走过的路整段点亮」，主题需要把静止层改成 accent、再补一条 `TyStepsConnector:disabled` 当作「还没走」。

### 可调尺寸令牌（v3/C 约定）

| 令牌 | 内置默认（逻辑像素） | 作用 |
|------|------|------|
| `--steps-marker-size` | `24`（= `TyStepsMarkerSize`） | 方形标记槽位的边长。**故意谁也不对齐**——它是库里唯一的那枚大圆 chip |
| `--steps-gap` | `8`（= `TyStepsGap`） | 标记与它的标题之间的间隙（单元头部注释称它对齐 `TyCheckBoxGap`，好让「标记→标题」的节奏读起来像 checkbox 的「方框→caption」；但今天 `TyCheckBoxGap` 是 `6`，两者**并不**相等——以本表的常量为准） |
| `--steps-connector-gap` | `8`（= `TyStepsConnectorGap`） | 标记与连线**两端**的清空距离 |
| `--steps-connector-size` | `1`（= `TyStepsConnectorSize`） | 连线的**粗细**。1px 是因为 96 PPI 下轨道的线就是一根**发丝线** |
| `--steps-connector-length` | `32`（= `TyStepsConnectorLength`） | `AutoSize` 为连线留出的**自然跑道**。它**不是上限**：比自然尺寸更宽的轨道只是摊开，多出来的余量全归连线 |

五个常量都**只是该令牌的默认值**（主题不写时才用得上），在每个调用点按 PPI 缩放到设备像素（`MulDiv(v, PPI, 96)`，与 `TTyPainter.Scale` 同一套换算，所以**命中检测量的就是绘制画的**）。它们被写成具名常量而非字面量，是因为**三个调用点**（`RenderTo`、`CalculatePreferredSize`、测试）必须拼写一致——任何一处笔误都会让那个点悄悄停在默认值上，于是**画出来的几何**和**量出来的几何**开始漂移。

标记里的两个字形也都支持图标字体覆盖（v3/C5）：勾是 `--glyph-check`，错误标记是 `--glyph-close`（用 `x` 而不是自造一个字形种类：在步骤标记上，`x` **就是**错误标记，另发明一个 `TTyGlyphKind` 会和其余每个单元的撞车）。

### 未定义时优雅降级（均有测试守护）

| 缺什么 | 结果 |
|--------|------|
| `TySteps` 的 `background` | **什么都不画**——标记、连线、文字**一个都不画**，哪怕 `TyStepsItem` / `TyStepsConnector` 有定义。主题没认领这个 key，控件就不自己发明观感。（`DrawFrame` 仍会先跑：**窗口化控件**无论主题怎么说都得把父表面填上，否则自己的窗口会从圆角缺口里透出来。） |
| `TyStepsItem` 的 `background` | **不画 chip**，但标记里的数字 / 勾 / 错误标记照画。于是只给 `:selected` 写填充的主题，白得「只有你所在的那一步有一枚实心圆盘」——控件里没有对应的分支。 |
| `TyStepsItem` 的 `color` / `font-*` | 回退到**轨道自己的**（`InheritText`）。只给 `TySteps` 写了 `color` / `font-size` 的主题，照样得到可读、字号正确的标题和数字。**绝不**回退到任何硬编码颜色。（`background` / `border` **不**这样继承：一步没有自己的底色，就该不画 chip。） |
| `TyStepsItem.error` 规则 | 失败步**退化成一个看起来普通的步**，**绝不**变成硬编码的红色。（**注意**：字形仍然会变——错误标记来自 `StepStatus`，不来自主题。） |
| `TyStepsConnector` 的 `background` | **不画线**，标记照画。 |
| `--steps-connector-size` = 0 | 同样不画线（几何层就把它塌缩掉了），无论主题的 gap 怎么写。 |

> **想自己验降级时的一个坑：** 编译进来的 base 层（`themes/light.tycss`）会垫在每个主题下面，凡是主题**省略**的 typeKey 都由它兜底。所以「把规则整条删掉」**测不到**降级。任何**用户规则**都会把该 typeKey 的整个 base 层压制掉（`TTyStyleModel.UserHasTypeKey`），因此要造一个真正「没有底色」的 key，得写一条**存在但不含 `background`** 的规则（测试就是这么做的）。

---

## 7. 代码示例

```pascal
uses tyControls.Controller, tyControls.Steps;

TyDefaultController.LoadTheme('themes/light.tycss');

var S: TTySteps;

// 向导页眉：宿主驱动，用户点不动
S := TTySteps.Create(Self);
S.Parent := Surface;
S.Align := alTop;
S.Items.Add('许可协议');
S.Items.Add('选择组件');
S.Items.Add('安装位置');
S.Items.Add('完成');
S.StepIndex := 0;            // 站在第一步上
```

宿主挪**一个整数**，整条轨道自己重读：

```pascal
procedure TForm1.NextClick(Sender: TObject);
begin
  Steps.StepIndex := Steps.StepIndex + 1;   // 到 Count 就是「全部完成」，不必特判
  ShowPageFor(Steps.StepIndex);
end;

procedure TForm1.InstallFailed;
begin
  Steps.ErrorIndex := Steps.StepIndex;      // 就地标红，游标不动，OnChange 不响
end;
```

安装器的左侧轨（纵向 + 自动尺寸）：

```pascal
S := TTySteps.Create(Self);
S.Parent := Surface;
S.Align := alLeft;
S.Orientation := soVertical;
S.AutoSize := True;          // 高度 = 每步一格，宽度 = 标记 + 间隙 + 最宽标题
S.Items.AddStrings(FStageNames);
S.StepIndex := -1;           // 尚未开始：每一步都在等
```

可导航的轨道 + 宿主否决非法跳转：

```pascal
S.Clickable := True;         // 顺带把 TabStop 变成 True
S.OnChange := @HandleStepChange;

procedure TForm1.HandleStepChange(Sender: TObject);
var
  T: TTySteps;
begin
  T := Sender as TTySteps;
  // 控件不知道哪些跳转宿主允许：不允许就在这里把游标设回去。
  if T.StepIndex > FMaxReached then
    T.StepIndex := FMaxReached
  else
    ShowPageFor(T.StepIndex);
end;
```

---

## 8. 注意事项

- **`StepIndex` 不夹取，`Items` 编辑也不重新校验它**（`TTySegmented` 恰恰会在这个时机重新校验它的 `ItemIndex`）：3 步轨道上的游标 `3` 意思是「已完成」，追加第 4 步之后它仍然有意义——那时它正确地表示「在最后一步上」。没有哪个「夹取后的值」会比宿主设的那个更对。
- **`ErrorIndex` 是一个索引，不是每步一份状态**：一个向导一次只会有一件事出错，而「与 `Items` 平行的一张状态表」正是这个控件为了消灭它才存在的簿记。
- **错误是变体，不是状态**：失败的当前步**仍然**是 `:selected`。两个轴叠加，主题分别写 `TyStepsItem:selected` 和 `TyStepsItem.error` 即可。
- **点击在「按下」时就生效**（不是抬起时）：轨道是个开关，家里的页签条也是按下即切。按在**边沟**（轨道的 `padding`）上是**惰性**的——答 `-1`，绝不把用户看得见的游标清掉。
- **`Clickable` 让每一步都可达，包括等待中的**：控件不知道哪些跳转宿主允许，要拒绝就在 `OnChange` 里把 `StepIndex` 设回去。
- **方向键跟着 `Orientation` 走**：横向是 Left/Right，纵向是 Up/Down——沿着轨道指的那对键才是移动键，另一对留给窗体；Home/End 跳两端（与 `TTyCustomTabStrip` 的键盘一致）。所有被处理的键都会被**吞掉**（`Key := 0`）；反过来，**未开 `Clickable`** 或**空列表**时按键**不吞**，留给窗体去做它本来要做的事。
- **键盘走不到「尚未开始」和「全部完成」**：`TyStepsStepIndex` 永远夹到一个真实的步骤上，那两个游标位置只有**宿主**能设。
- **禁用时输入通路直接返回**：`MouseDown` / `MouseMove` / `KeyDown` 都在 `not Enabled` 时**先于** `inherited` 返回，所以禁用的轨道也不会派发基类的鼠标 / 按键事件。
- **几何取的是「静止态」的轨道样式**：格的铺排和 `AutoSize` 的测量都用 `[tysNormal]` 解析出的 `padding`，**不是** `CurrentStyle` 的——轨道的几何不该因为控件拿到了焦点或指针进来了就动（否则一条 `:focus` 规则就能在脚下把 `padding` 重新调掉）。
- **一条行高管所有步**，用**静止态**的标题样式量出来：主题把当前步加粗 / 改字号，**不能**让那一步的标记和邻居们不一样高，也不能让轨道尺寸取决于向导恰好走到了第几步。
- **标题只有标题，没有描述**：Ant 的每步 `description` 需要每项第二个字符串，而 `TStrings` 上唯一能挂它的地方是 `Objects[]` 指针——那会让宿主每行拥有一个堆对象、任何没手工清理的编辑都漏它，且别人塞一个普通 `TStringList` 进来时悄悄崩掉。将来老实的做法是再 published 一个与之同步的 `Descriptions: TStrings`；现在还不需要。
- **标题省略号截断、标记里的数字不截断**：标题左对齐在自己的标记下方 / 旁边，窄了显示 `Config…` 而不是在格边被剪断或漫进下一步；标记是个固定方块，`1…` 说的比一个被裁的数字还少。
- **不解析助记符**：轨道不激活任何东西，`&` 是字面字符。
- **文字用主题样式，不读 LCL Font：** 遵循「主题锁定」约定，改字号 / 字色请改主题令牌或用 `StyleClass` / `StyleOverride`。
- **`AutoSize` 需要已实现句柄的父窗体：** LCL 的 `AutoSizeDelayed` 在父窗体未实现句柄时会抑制所有重新贴合（headless 场景下 `AutoSize` 不生效）——这是 LCL 行为，不是本控件的。测试因此直接验 `CalculatePreferredSize`。
