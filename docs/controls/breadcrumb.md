# TTyBreadcrumb

## 1. 概述

`TTyBreadcrumb` 是 TyControls 库中的主题化「面包屑 / 路径条」控件，继承自 `TTyGraphicControl`（图形控件，无窗口句柄，不能作为父容器）。它把「你是怎么走到这儿的」画成一行：一串可点的祖先，中间用主题化的分隔标记隔开，结尾停在**你现在所在的位置**。

**它补的是哪个缺口：** Shell 一族控件（`TTyShellTreeView` / `TTyShellListView`）本来就在路径里导航，却**没有任何控件能把这条路径显示出来**。手工拼一排 `TTyLinkLabel` + `TTyLabel` 是当前的替代方案，但它既没有「最后一节不是链接」这条语法，也对「路径长过路径条」毫无办法——而这两件事恰恰是「面包屑」区别于「一排链接」的全部。典型用途：文件浏览器的当前路径、设置页里的层级位置、向导 / 文档站的「你在这儿」。

颜色 / 尺寸变体**不是**枚举，而是普通的 `StyleClass`——`Bar.StyleClass := 'compact'` 对应 `.tycss` 里的 `TyBreadcrumb.compact { ... }`。控件本身不认识任何变体名，主题想定义多少种就定义多少种，加变体**不需要改代码**。**同一个 `StyleClass` 也会带给每一节**，所以 `TyBreadcrumbItem.compact` 会跟着路径条一起走。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Breadcrumb` |
| `GetStyleTypeKey` 返回值 | `'TyBreadcrumb'`（路径条本体：`background` / `border-*` / `color` / `font-*` / `padding` / `opacity` / `shadow`；它的 `color` **同时**是分隔标记的笔色） |
| 每一节的 typeKey | `'TyBreadcrumbItem'`（链接上有 `:hover`，当前位置上有 `:selected`；这条键的 `:selected` 规则**就是**面包屑的全部视觉语法） |
| 基类 | `TTyGraphicControl`（继承自 `TGraphicControl`） |
| 默认尺寸 | 300 × 24（逻辑像素，构造时设置） |
| 新增令牌 | `--breadcrumb-separator-size`、`--breadcrumb-separator-gap`（见第 6 节） |

```pascal
uses tyControls.Breadcrumb;
```

**为什么是图形控件（无句柄）？** 要句柄无非是为了焦点，而面包屑**恰恰不想要焦点**：它是一个**次要**可视对象，那条路径的主控件（一棵树、一个列表）本来就拥有它、也早已把它放进了 Tab 序——把同一批目的地在 Tab 序里放**两遍**只会让窗体更糟，不是更好。它不承载子控件、不吃按键。直接画在父控件画布上，圆角**之外**的缺口天然显出父表面（图片主题下则是照片），省掉窗口化控件必须做的补角处理，而且一整条路径**零 HWND**。

**为什么分隔标记没有自己的 typeKey？** 标记是**路径条的装饰件**，不是一节路径。所以它取路径条的 `color`：`TyBreadcrumb { color: var(--muted) }` 染所有分隔标记，`TyBreadcrumbItem { color: var(--accent) }` 染所有链接——两条键已经说尽了第三条键能说的一切。

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Items` | `TStrings` | 空 | 整条路径，**根在最前、当前位置在最后**，一节一行。用解析后的 `TyBreadcrumbItem` 样式绘制（**不**读取 LCL `Font.*`），被裁到时省略号截断，**永不换行**。**不解析助记符**：一节路径没有 Alt+键路径，`&` 就是字面字符。改动它会清掉可能被搁浅的悬停 / 按下状态（见第 8 节），`AutoSize` 时重新贴合，并重绘。 |
| `OnCrumbClick` | `TTyBreadcrumbClickEvent` | `nil` | 见第 4 节。 |
| `AutoSize` | `Boolean` | `False`（LCL 默认） | 开启后路径条**宽度**贴合整条路径（于是溢出规则永远不会触发），**高度**贴合一行带 `padding` 的文字。 |

### 继承的通用成员

`TTyBreadcrumb` 继承自 `TTyGraphicControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | **变体入口**：对应 `.tycss` 里 `TyBreadcrumb.<classname>`；**同一个串**也用来解析 `TyBreadcrumbItem.<classname>`。 |
| `StyleOverride` | `string` | `''` | 单实例内联 CSS 声明块（可引用 `var(--...)` 令牌）。 |
| `Controller` | `TTyStyleController` | `nil`（用全局 `TyDefaultController`） | 指定样式控制器。 |

另暴露 `Enabled` / `Font` / `Align` / `Anchors` / `OnClick` 及 `TTyGraphicControl` 基线事件集，见 [../events.md](../events.md)。

> **`AutoSize` 与 `Align` 怎么相处：** 一条 `alTop` / `alClient` 的路径条会保持宿主给的宽度、只贴合高度——这也是摆放它最常见的方式。此时溢出规则是**活的**，窄了就折叠中间。

---

## 4. 事件

| 事件 | 触发时机 |
|------|----------|
| `OnCrumbClick` | 用户**激活**了一节路径：按下与抬起**都**落在**同一个链接**上。`procedure(Sender: TObject; AIndex: Integer) of object`，`AIndex` 是它的 `Items` 下标。**永不**为最后一节（你已经在那儿了）、`…`（它是标记，不是地方）、或路径节之间的空隙触发。 |
| `OnClick` | 路径条上的**任意**点击，**包括**当前位置和空隙。 |

> **为什么 `OnClick` 不被吞掉（与 `TTyTag` 的 `x` 不同）：** 一节路径不是「藏在控件里的第二个控件」，它**就是**路径条本身——所以「用户点了路径条」这句话在导航发生时**同样成立**。`OnCrumbClick` 才是那个说「用户选了一个目的地」的事件。

**按下再拖开 = 取消。** 和任何按钮一致：按住一个链接、抬起在**另一节**上（或抬在当前位置上、或抬到条外），整个手势作废，**不会**导航到手指落下的那一节。

---

## 5. 关键成员

### 常量与类型

```pascal
const
  TyBreadcrumbSepSize       = 14;   // 分隔字形方形槽位边长（逻辑像素）
  TyBreadcrumbSepGap        = 2;    // 槽位【两侧各】的留白（逻辑像素）
  TyBreadcrumbSepSizeVar    = '--breadcrumb-separator-size';
  TyBreadcrumbSepGapVar     = '--breadcrumb-separator-gap';
  TyBreadcrumbEllipsisText  = '…';  // 折叠标记的文字
  TyBreadcrumbEllipsisIndex = -1;   // 折叠标记在 plan / slot 里报的 Items 下标

type
  TTyBreadcrumbWidths = array of Integer;   // 每一节的【完整】宽度（含它自己的左右 padding），设备像素
  TTyBreadcrumbPlan   = array of Integer;   // 当前显示的 Items 下标，-1 = '…'

  TTyBreadcrumbSlot = record
    ItemIndex: Integer;   // Items 下标，或 TyBreadcrumbEllipsisIndex
    ItemRect: TRect;      // 这一节自己的矩形：底片填它，命中检测量它。放不下 => 空
    SepRect: TRect;       // 这一节【之后】的分隔槽位。最后一节为空；跑出band的也为空
  end;
  TTyBreadcrumbSlots = array of TTyBreadcrumbSlot;

  TTyBreadcrumbClickEvent = procedure(Sender: TObject; AIndex: Integer) of object;
```

> **为什么 `TTyBreadcrumbWidths` 存的是「完整宽度」而不是「内容宽 + 一份共用的 padding」：** 每一节都解析**自己的**样式——当前位置和链接是两条不同的主题规则，完全可能被主题给了不同的 `padding`（或不同的字重）。

> **为什么两个常量各有一个具名的 `...Var`：** 三个调用点（`SlotsWith`、`CalculatePreferredSize`、测试）必须拼写一致；其中一处打错字会**静默地**把它撂在默认值上，几何于是和测量悄悄分了家。

### 纯规则 / 几何函数（单元级，可无句柄、无主题、无控件直接调用）

```pascal
function TyBreadcrumbIsLink(AIndex, ACount: Integer): Boolean;
function TyBreadcrumbItemStates(AIndex, ACount: Integer;
  AHovered, AEnabled: Boolean): TTyStateSet;

function TyBreadcrumbCrumbWidth(ATextWidth, APadLeft, APadRight: Integer): Integer;
function TyBreadcrumbSepAdvance(ASepSize, ASepGap: Integer): Integer;
function TyBreadcrumbTrailWidth(const AWidths: array of Integer;
  ASepSize, ASepGap: Integer): Integer;

function TyBreadcrumbVisiblePlan(AAvailWidth: Integer; const AWidths: array of Integer;
  AEllipsisWidth, ASepSize, ASepGap: Integer): TTyBreadcrumbPlan;
function TyBreadcrumbLayout(AClientWidth, AClientHeight: Integer;
  const APlan: TTyBreadcrumbPlan; const AWidths: array of Integer; AEllipsisWidth: Integer;
  APadLeft, APadTop, APadRight, APadBottom, ASepSize, ASepGap: Integer): TTyBreadcrumbSlots;
function TyBreadcrumbIndexAt(const ASlots: TTyBreadcrumbSlots; X, Y: Integer): Integer;

function TyBreadcrumbPreferredWidth(const AWidths: array of Integer;
  APadLeft, APadRight, ASepSize, ASepGap: Integer): Integer;
function TyBreadcrumbPreferredHeight(APadTop, APadBottom, AItemHeight,
  ASepSize: Integer): Integer;
```

全部整数入参、无控件状态、无句柄依赖，测试直接调用（`tests/test.breadcrumb.pas`）。

#### `TyBreadcrumbIsLink` —— 面包屑的全部语法

`(ACount > 0) and (AIndex >= 0) and (AIndex < ACount - 1)`。**最后一节是你已经在的地方**：它是当前位置，不是链接，所以它**永不悬停**、**永不触发 `OnCrumbClick`**。这条规则以**一个函数**的形式存在，就是为了让绘制、悬停与点击**永远不可能**在这件事上产生分歧。`…`（`-1`）也不是链接——它是标记，不是地方。单节路径**没有任何链接**（那一节就是你所在处）。

#### `TyBreadcrumbItemStates` —— 每一节歇在哪个状态

| 情形 | 结果 |
|------|------|
| 最后一节（`AIndex = ACount - 1`，且 `ACount > 0`） | `[tysSelected]` |
| 链接，静息 | `[tysNormal]` |
| 链接，悬停 | `[tysHover]` |
| `…`（`AIndex = -1`） | `[tysNormal]`，**空路径上也是** |
| `AEnabled = False`，最后一节 | `[tysSelected, tysDisabled]` |
| `AEnabled = False`，链接（哪怕 `AHovered`） | `[tysDisabled]` |

- **当前位置带的是 `tysSelected`**——和 `TTyButton.Down` 注入的、`TTySegmented` 选中段带的是**同一个**静息状态，所以**一条** `:selected` 主题规则同时管住三者。
- **禁用**时 `:selected` **保留**（与 `TTyButton.Down` 不同，后者会丢掉它）：一条灰掉的路径**仍然必须说出你在哪儿**——丢了当前位置的底片，读起来会变成「这条路径哪儿也不是」，而不是「你没法从这儿导航」。级联负责其余部分：`ResolveLayer` 先套 `:selected` 作为静息层、`:disabled` **最后**套且优先级最高，于是底片活下来、而禁用的墨色压过它。悬停被**刻意**排除：禁用控件不吃悬停。
- `ACount > 0` 这个守卫也顺手把 `-1` 挡在「当前位置」分支外（空路径上 `-1 = 0-1` 本会命中）。

#### 溢出规则 `TyBreadcrumbVisiblePlan` —— **折叠中间**

不是裁掉，也不是滚动：

* **最后一节永远保留**——那是你所在处，一条丢了它的路径条什么都没说；
* **第一节（根）能放下就保留**——根（`C:\`、`Home`）说明的是「这条路径在**哪棵**树里」；
* **靠近末端的祖先按「还放得下就加回来」逐个恢复**——近的那些才是你真会去点的；
* 被丢掉的那一段**折叠成一个 `…` 节**，而且**只在它确实藏住了东西时**才会出现。

> **为什么不是「右对齐尾部」：** 那个方案保留同样一批可见节点，却**悄悄丢掉根**，还留下一条参差的左边缘——读起来像渲染 bug，而不是「上面还有路径」。

退化端：空 `Items` → 空 plan；窄到连 `… › Here` 都放不下 → **只剩最后一节**，交给绘制去省略号截断（一条只显示 `…` 的路径条什么都没说）。**非空路径永远不会得到空 plan。**

以测试里那条 4 节路径（宽 40/50/60/30，`…` 20，槽 10 + 两侧各 5 → 一个标记推进 20px，整条 240px）为例：

| 可用带宽 | plan | 说明 |
|------|------|------|
| ≥ 240 | `0,1,2,3` | 正好放下也算放下：无标记、无决策、整条路径 |
| 239 | `0,-1,2,3` | 只丢**最没用的**那个祖先——离末端最远的那个 |
| 210 | `0,-1,2,3` | 多一个像素就把 crumb 2 买回来 |
| 209 | `0,-1,3` | 尾巴停在钱不够的地方 |
| 130 | `0,-1,3` | `根 › … › 此处` = 40+20+20+20+30 |
| 129 | `-1,3` | **根也不是神圣的**：它自己放不下时，标记连它一起代表 |
| 69 / 0 | `3` | 地板：连 `… › 此处`（70px）都放不下，只说你在哪儿 |

两节路径是个特例：根与末端**之间**没有任何东西可供 `…` 代表，所以 `根 › … › 尾` 那个形态用不上（代码里 `n >= 3` 才考虑它）——但根**自己**仍然可以被丢掉：4 节里的 `[W0, W3]` 在 90 显示 `0,1`，在 89 给出 `-1,1`，而**不是**一个被裁掉的 `0,1`（那会把钱花在根上，把唯一要紧的那一节干净利落地裁出带外）。

#### `TyBreadcrumbLayout` —— 摆开

- **`Length(Result) = Length(APlan)` 恒成立**，所以绘制可以拿 plan 和 slots 一起走；放不下的东西用**空（绝不反向）矩形**说话，而不是靠「不在数组里」。
- band = 路径条**按自己四边的 `padding` 内缩**。整条路径在 band 里**左对齐**（根是眼睛开始的地方）。
- **一节路径占满 band 的整个高度**：底片**就是**这一节，它的命中目标也是——一条链接只有字形那么高的路径，会变成一场像素狩猎。
- 分隔槽位**是正方形**，在 band 里**垂直居中**；band 比槽位矮时**顶在 band 顶、底被夹进 band**，而**不是**溢出（沿用 `TyTagLayout` 对自己槽位的规矩）。
- 被 band 裁到的一节：右边界夹到 `bandR`，**不反向**；绘制端由 `DrawText` 省略号截断。
- **步进不吃夹紧的亏**：下一节的起点用的是 `sepL + ASepSize + ASepGap`，**不是** `sepR`——一个被夹短的标记不该把整条路径的节奏也带短。
- `padding` 吃掉整条 / 宽高 ≤ 0 → 所有矩形都为空。

#### `TyBreadcrumbIndexAt` —— 摆开的**逆**

它扫的就是 `TyBreadcrumbLayout` 自己产出的那些矩形，所以**用户点到的那一节，永远就是画在那儿的那一节**。分隔标记、节与节之间的空气**不属于任何一节**；`…` 也一样——**它的 `ItemIndex` 就是 `-1`**，于是「空隙和标记都不是目的地」这件事由**同一行代码**免费得到。左闭右开：一节拥有自己的左边缘，**不拥有**右边缘。

#### 两个 Preferred

- `TyBreadcrumbPreferredWidth` = `padLeft + 整条路径宽 + padRight`，是**溢出规则的逆**：把结果减去 padding 回喂给 `TyBreadcrumbVisiblePlan`，就会拿回每一节（已有往返测试守护：正好那个宽度显示 `0,1,2,3`，**少一个像素就不行**）。它**故意不**下限到 1——**精确的逆**才是契约；控件在自己的 `CalculatePreferredSize` 里下限到 1，那里 LCL 需要。
- `TyBreadcrumbPreferredHeight` = `padTop + max(AItemHeight, ASepSize) + padBottom`。**标记是在 band 里居中的**，所以 band 比槽位矮就会把字形压扁——band 必须**连光槽位也清得下**（和 `TTyTag` 拿自己的 `x` 卡高度是同一个道理）。

### 公开成员

```pascal
function Count: Integer;                        // 路径【有】几节 —— 含被折叠掉的（Items 是路径，plan 只是当下放得下的）
function TyCrumbSlots: TTyBreadcrumbSlots;      // 当下摆开的样子（设备像素，(0,0)-local）：绘制填的、命中检测量的，就是这些矩形
function TyVisiblePlan: TTyBreadcrumbPlan;      // 当下【显示】什么：Items 下标，-1 = '…'
function TyCrumbRect(AIndex: Integer): TRect;   // 第 AIndex 节的矩形；越界或被折叠掉 => 空
function TyCrumbAt(X, Y: Integer): Integer;     // 客户区设备坐标处的 Items 下标，或 -1（分隔标记 / 空隙 / '…' 都是 -1）
```

`TyVisiblePlan` 是**从 slots 上读回来的**，而不是重新决策一遍——`TyBreadcrumbLayout` 保证一个 plan 项一个 slot，所以它**就是**那个 plan，两者永不漂移。`TyCrumbRect` 对被折叠掉的一节返回**空矩形而不是异常**——一节被折叠掉的路径，是真的哪儿也没有。

---

## 6. 状态与主题

### 支持的伪类状态

- **路径条**（`TyBreadcrumb`）：`:hover` / `:active` / `:disabled` 由基类状态机计算。
- **每一节**（`TyBreadcrumbItem`）：由 `TyBreadcrumbItemStates` 计算（见第 5 节表）。解析时带上**路径条的 `StyleClass`**，因此变体能同时抵达两条键。**只有链接会亮**：当前位置亮起等于承诺一个不可能发生的导航，而 `…` 是标记、不是地方。

### 主题令牌摘要（`themes/light.tycss`）

```css
/* Breadcrumb: a transparent trail; the mark takes the BAR's ink (it has no key of its own). */
TyBreadcrumb         { background: alpha(#FFFFFF, 0); color: var(--muted); font-size: var(--font-size-base); padding: 2px 4px; }
TyBreadcrumb:disabled { opacity: var(--disabled-opacity); }
TyBreadcrumbItem          { color: var(--accent); font-size: var(--font-size-base); padding: 0px 4px; }
TyBreadcrumbItem:hover    { color: var(--accent-hover); }
/* The last crumb IS the current location: not a link, so it reads as plain ink. */
TyBreadcrumbItem:selected { color: var(--on-surface); }
TyBreadcrumbItem:disabled { color: var(--muted); }
```

要点：

- `background: alpha(#FFFFFF, 0)` 是**透明**，不是「没有 background」——路径条通常不想要自己的底色，而透明**是一个已定义的 background**，不是一个缺席的。这个区别是致命的：见下面的降级规则。
- 基线主题**只染墨色、不给任何一节底片**（`TyBreadcrumbItem` 没有 `background`）。想要「指针下的链接亮起来」的经典效果，主题加一条 `TyBreadcrumbItem:hover { background: ... }` 即可，**控件里没有对应的代码分支**；想要当前位置有块底板，同理加 `TyBreadcrumbItem:selected { background: ... }`。
- 路径条的 `padding: 2px 4px` 决定 band；每一节的 `padding: 0px 4px` 决定它自己的完整宽度。

### 可调尺寸令牌（v3/C 约定）

| 令牌 | 内置默认（逻辑像素） | 作用 |
|------|------|------|
| `--breadcrumb-separator-size` | `14`（= `TyBreadcrumbSepSize`，与 `TyTagCloseSize` / `TyTabCloseSize` 一致，全库字形槽位观感统一） | 分隔字形方形槽位边长 |
| `--breadcrumb-separator-gap` | `2`（= `TyBreadcrumbSepGap`） | 槽位**两侧各**的留白 |

**两个令牌 `themes/light.tycss` 都没有声明**，所以基线主题下两者都歇在上面的编译内默认值上。皮肤可以各自重调；每个调用点都会把它们缩放到设备像素。

> 槽位与 `TyTagCloseSize` 对齐，是为了让分隔标记读起来和标签的 `x`、页签的 `x` 是**同一份量的字形**——画笔会在槽位**内部**自己内缩留白，所以 96 PPI 下一个 14px 的槽位画出的是约 6px 的 chevron。

分隔字形本身还支持图标字体覆盖（`--glyph-chevron-right`，v3/C5）：皮肤不改代码就能把 chevron 换成 `/`。

### 未定义时的降级

严格照代码所写：

- **路径条没有 `background`** → **整条什么都不画**：不画底片、不画每一节、不画标记。哪怕 `TyBreadcrumbItem` 那条键**是**定义了的。降级，而不是发明一个外观。
- **某一节没有 `background`** → **不画底片**，但**标签照常画**。于是「只填 `:hover`」的主题白得「指针下的链接亮起来」，「只填 `:selected`」的主题白得当前位置的底板——都不需要控件里的代码分支。
- **某一节没有 `color` / `font-name` / `font-size` / `font-weight`** → 逐项回退到**路径条自己的**（`ItemTextStyle`）。这是本库「没有颜色就继承父级墨色」的降级惯例，按同一逻辑扩展到了字体：一个只定义了 `TyBreadcrumb` 的主题，仍然必须得到**可读、尺寸正确**的路径节，而且**永远不会**是硬编码的颜色。
- **`background` / `border` 刻意不走这条继承**：一节没有自己的 background，就**必须不画底片**。
- **分隔标记取的是路径条的 `color`**（`S.TextColor`），永远如此——这正是它不需要第三条 typeKey 的原因。

**注意「留空」不等于「未定义」：** 编译进库的基线层（`themes/light.tycss`）会垫在每个主题下面，为主题省略的每条 typeKey 兜底。想真正得到一条「没有 background 的键」，得**写出这条规则但不给 background**——用户为某条 typeKey 写的**任何**规则都会整体压掉该键的基线层（`TTyStyleModel.UserHasTypeKey`）。测试里两个降级用例正是这么构造的。

---

## 7. 代码示例

```pascal
uses tyControls.Controller, tyControls.Breadcrumb;

TyDefaultController.LoadTheme('themes/light.tycss');

var B: TTyBreadcrumb;

// 贴在内容区顶部的路径条：宽度交给 alTop，高度自己贴合
B := TTyBreadcrumb.Create(Self);
B.Parent := Surface;
B.Align := alTop;
B.AutoSize := True;              // 高度贴合；宽度由 alTop 给
B.Items.Add('此电脑');           // 根
B.Items.Add('D:');
B.Items.Add('Projects');
B.Items.Add('ty-controls');      // ← 当前位置（最后一节，不是链接）
B.OnCrumbClick := @HandleCrumbClick;
```

响应导航，并把路径条重新指向新位置：

```pascal
procedure TForm1.HandleCrumbClick(Sender: TObject; AIndex: Integer);
var
  i: Integer;
  Path: string;
begin
  // AIndex 是【祖先】的 Items 下标 —— 最后一节永远不会走到这里。
  Path := '';
  for i := 0 to AIndex do
    Path := Path + Crumbs.Items[i] + PathDelim;
  ShellTree.Path := Path;

  // 把当前位置之后的路径节摘掉：新的末节就是新的当前位置。
  while Crumbs.Count > AIndex + 1 do
    Crumbs.Items.Delete(Crumbs.Count - 1);
end;
```

主题层给链接加悬停底片、给当前位置加底板（控件侧零代码）：

```css
TyBreadcrumbItem:hover    { background: var(--overlay-hover); border-radius: var(--radius); }
TyBreadcrumbItem:selected { background: var(--overlay-hover); color: var(--on-surface); }
```

---

## 8. 注意事项

- **最后一节不是链接：** 它是当前位置——不悬停、不触发 `OnCrumbClick`。这不是可配置项，是面包屑的定义。
- **`…` 是标记，不是地方：** 它的 `ItemIndex` 就是 `-1`，所以它命中检测为「什么都不是」，不悬停、不触发 `OnCrumbClick`；状态上它**歇在 `:normal`（像个链接），而不是 `:selected`**——把它打扮成当前位置是撒谎。
- **`OnClick` 不被吞：** 与 `TTyTag` 的 `x` 相反，导航发生时 `OnClick` **同样**会触发（一节路径不是藏在控件里的第二个控件，它就是路径条）。要「选了目的地」这个语义请用 `OnCrumbClick`。
- **改 `Items` 会清掉搁浅的鼠标状态：** 一次列表编辑可能把活着的悬停 / 按下状态撂在一节**已经没了**的路径上——更糟的是撂在一节**刚刚变成最后一节、因而不再是链接**的路径上，那会让当前位置像链接一样亮着，并在抬起时**向你已经在的地方发起一次导航**。`ItemsChanged` 用 `TyBreadcrumbIsLink` 重新校验两个下标。
- **测量排除悬停，且用画笔而不是 LCL 画布：** 每一节按**自己的静息样式**测（当前位置和链接是两条不同的主题规则，主题若给它加粗，用链接的字体量出来的宽度会把它裁掉）。悬停被**刻意**排除——一节在指针下变宽会把整条路径推得横向乱窜，而溢出规则会随着鼠标移动来回抖。
- **`…` 永远会被测量**，哪怕整条路径放得下：溢出规则必须先知道这个标记**要花多少钱**，才能决定用它值不值。
- **`AutoSize` 关掉溢出：** `AutoSize` 时路径条贴合整条路径，于是溢出规则**永远不会触发**。要它折叠，就得给路径条一个固定 / 对齐得来的宽度。
- **图形控件，非容器：** 无窗口句柄，子控件不能以它为 `Parent`。它也**不进 Tab 序**（有意为之，见第 2 节）。
- **文字用主题样式，不读 LCL Font：** 遵循「主题锁定」约定，改字号 / 字色请改主题令牌或用 `StyleClass` / `StyleOverride`。
- **变体是 `StyleClass`，不是枚举：** 新增一种外观只改 `.tycss`，控件代码不动；同一个 `StyleClass` 自动抵达 `TyBreadcrumb` 和 `TyBreadcrumbItem` 两条键。
- **`AutoSize` 需要已实现句柄的父窗体：** LCL 的 `AutoSizeDelayed` 在父窗体未实现句柄时会抑制所有重新贴合（headless 场景下 `AutoSize` 不生效）——这是 LCL 行为，不是本控件的。测试因此直接验 `CalculatePreferredSize`。
- **`TyDrawGlyph` 槽位的实用下限约 12px：** 画笔会把矢量字形**每侧内缩 4 个逻辑像素**，所以一个 10px 的槽位只剩 1px 宽的 chevron——两个淡到看不见的抗锯齿像素。默认的 14 是安全的；皮肤把 `--breadcrumb-separator-size` 调得太小会让标记事实上消失。
