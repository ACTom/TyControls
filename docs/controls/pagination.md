# TTyPagination

## 1. 概述

`TTyPagination` 是 TyControls 库中的主题化「分页器」控件，继承自 `TTyCustomControl`（窗口化控件，拥有自己的句柄）。它是一条格子带：可选的上一页 / 下一页箭头，夹着一串页码格子，页码被省略的地方画 `...`——即 `< 1 ... 97 98 99 ... 195 >`。

**它补的是哪个缺口：** 本库此前没有任何东西能说「我现在在结果集的第几页」。`TTySegmented` 是从**一眼看得全**的一小排里挑一个**值**；分页器面对的是几百页的长跑，因此**必须省略**——而省略是一条**规则**，不是一种布局。

它**自己什么都不驱动**：不持有列表、不持有查询、不持有 Grid——它只报告「现在是第几页」，宿主从 `OnChange` 里自己去重填 `TTyListView` / `TTyListBox` / 自绘列表。这正是它**不是** Grid 的一个部件的全部理由。

**页码从 0 开始。** `PageIndex` 就是本库里其它所有索引那样的索引（`ItemIndex` / `TabIndex` / `TPageControl.PageIndex`），**只有标签是 1-based**：第 0 页画成 `1`。

典型用途：列表页脚的翻页条、搜索结果的页码带、表格下方的分页。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Pagination` |
| `GetStyleTypeKey` 返回值 | `'TyPagination'`（**格子带本体**，即格子所在的那个框：`background` / `border-*` / `color` / `font-*` / `padding` / `opacity` / `shadow`） |
| 格子 typeKey | `'TyPaginationItem'`（**每个格子各自解析**：`background` / `border-*` / `color` / `font-*` / `padding`。让这个控件**读得出来**的正是这个 key 的 `:selected` / `:hover` / `:disabled`） |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸 | 320 × 32（逻辑像素，构造时设置） |
| 新增尺寸令牌 | `--pagination-gap` / `--pagination-min-cell-width` / `--pagination-glyph-size`（见第 6 节） |

```pascal
uses tyControls.Pagination;
```

**为什么是窗口化控件（有句柄）？** 与同族的 `TTySegmented` 一样、与 `TTyTag` 不一样：它**要取焦点**，左右方向键要能翻页——而图形控件两样都做不到（无句柄 ⇒ 无焦点、收不到按键消息）。这就是选这个基类的全部理由。

**为什么只有两个 typeKey？** 每个格子解析 `'TyPaginationItem'` 时会带上一个说明它**是哪一类**的 variant 令牌（`'prev'` / `'page'` / `'ellipsis'` / `'next'`）——沿用 `TTyAlert` 的先例。于是主题写 `TyPaginationItem.ellipsis` 就能把页码格子的边框从省略号上摘掉，而本单元**不需要长出第三个 typeKey**。

**默认尺寸 320 × 32 是怎么来的？** 它是「默认旋钮下、完全省略的一条带，一个格子都不掉」所需的尺寸：prev + `1` + `...` + `97` + `98` + `99` + `...` + `195` + next = **9 个格子**（各取 32px 下限）+ **8 个间隙**（各 4px）= 320。

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `PageCount` | `Integer` | `1` | 宿主一共有几页。负数被夹到 `0`；**`0` 表示「没什么可分页的」，格子带一个格子都不画**（连两个死箭头也不画——那会谎称有东西可翻）。**缩短页数会静默重夹 `PageIndex`**（不发 `OnChange`，见第 4 节）。 |
| `PageIndex` | `Integer` | `0` | 宿主正在显示的页，**0-based**——第 0 页就是标签写着 `1` 的那个格子。越界被**夹进**页数范围内，**不是**复位成 `-1`（见 `TyPaginationValidIndex`）；只有 `PageCount = 0` 时它才是 `-1`。 |
| `SiblingCount` | `Integer` | `1` | 当前页**每一侧**各保留几页可见。负数按 `0` 处理。 |
| `BoundaryCount` | `Integer` | `1` | 整条页序列**每一端**各保留几页可见。**夹到 `>= 1`**：低于 1 首页和末页就会藏进省略号里再也够不着，而那是分页器**唯一必须永远提供**的东西。 |
| `ShowPrevNext` | `Boolean` | `True` | 用两个步进箭头夹住整条。关掉就是一条光秃秃的数字带。关掉时会一并清掉可能指向箭头的残留悬停索引。 |
| `OnChange` | `TNotifyEvent` | `nil` | 见第 4 节。 |

> **为什么 `SiblingCount` / `BoundaryCount` 是 published 属性、而不是主题令牌？** 它们是省略规则**仅有的两个**参数（Ant Design 把这两个数写死了）。published 是因为**窗口宽度正是分页器贴合宿主的方式**——窄页脚要 `0`，宽页脚要 `2`；不给出来就等于写死一个窗口，那和写死一个颜色是同一种罪。而它们**不是**主题令牌，是因为它们改的是这条带**说了什么**，不是它**长什么样**。

### 继承的通用成员

`TTyPagination` 继承自 `TTyCustomControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `AutoSize` | `Boolean` | `False` | 开启后格子带贴合它**当前的**格子（宽和高都测量）。注意格子**不等宽**——见第 8 节。 |
| `TabStop` | `Boolean` | **`True`**（构造时置位，且 `default True`） | **窗口化基类的全部意义**：它取焦点、吃方向键。 |
| `StyleClass` | `string` | `''` | **变体入口**：对应 `.tycss` 里 `TyPagination.<classname>`；**同一个 `StyleClass` 还会追加到格子的 kind 之后**，所以 `TyPaginationItem.page.small` 能跟着整条带一起变。 |
| `StyleOverride` | `string` | `''` | 单实例内联 CSS 声明块（可引用 `var(--...)` 令牌）。 |
| `Controller` | `TTyStyleController` | `nil`（用全局 `TyDefaultController`） | 指定样式控制器。 |

另暴露 `Align` / `Anchors` / `OnClick`，以及 `TTyCustomControl` 基线成员集（`Enabled` / `Font` / `Hint` / `TabOrder` / 键鼠事件 / `OnEnter` / `OnExit` 等），见 [../events.md](../events.md)。

**变体不是枚举：** 控件自己**不声明任何变体枚举**，所以主题想定义多少个 `TyPagination.<x>` 都行，**不需要改代码**。

---

## 4. 事件

| 事件 | 触发时机 |
|------|----------|
| `OnChange` | **`PageIndex` 真的变了**的时候——点击、按键、或代码赋值，**三条路都算**。宿主就在这里重填自己的列表，因此它不必在每个 setter 现场重复那一次调用。**设成同一页不是变化，保持静默**（点击当前页所在的格子同理）。 |
| `OnClick` | 基类的普通点击事件。 |

> **两处刻意的静默：**
> - **改 `PageCount` 不发 `OnChange`**，哪怕它把停在范围外的 `PageIndex` 重夹了。设 `PageCount` 是**宿主自己的动作**（它刚重查了数据、并且会自己把 `PageIndex` 读回去）；`OnChange` 是留给宿主**没做过**的那个手势的。（沿用 `TTySegmented.ItemsChanged` 的规矩。）
> - **`Loaded` 里应用流式化的 `PageIndex` 也不发**：加载窗体不是用户手势，而此时 `.lfm` 里的 `OnChange` 处理器**已经接好了**——在这里发，等于在窗体还没显示出来之前，就先塞给宿主一个「用户翻页了」事件。

---

## 5. 关键成员

### 纯规则 / 几何函数（单元级，可无句柄直接调用）

```pascal
type
  TTyPaginationItemKind = (pikPrev, pikPage, pikEllipsis, pikNext);

  TTyPaginationItem = record
    Kind: TTyPaginationItemKind;
    Page: Integer;    // 点它要去的 0-BASED 页；< 0 表示这个格子是「惰性的」
  end;

  TTyPaginationItems = array of TTyPaginationItem;
  TTyPaginationRects = array of TRect;

const
  TyPaginationEllipsis = '...';

{ 页码规则 }
function TyPaginationValidIndex(ACurrent, ACount: Integer): Integer;
function TyPaginationStepIndex(ACurrent, ACount, ADelta: Integer): Integer;

{ 省略规则 —— 这个控件的心脏 }
function TyPaginationItems(APageCount, APageIndex, ASiblingCount, ABoundaryCount: Integer;
  AShowPrevNext: Boolean): TTyPaginationItems;
function TyPaginationItemVariant(AKind: TTyPaginationItemKind): string;
function TyPaginationItemLabel(const AItem: TTyPaginationItem): string;

{ 几何 }
function TyPaginationItemRects(AClientWidth, AClientHeight: Integer;
  APadLeft, APadTop, APadRight, APadBottom, AGap, AMinCellWidth: Integer;
  const AContentWidths: array of Integer): TTyPaginationRects;
function TyPaginationIndexAt(const ARects: TTyPaginationRects; X, Y: Integer): Integer;
function TyPaginationPreferredWidth(APadLeft, APadRight, AGap, AMinCellWidth: Integer;
  const AContentWidths: array of Integer): Integer;
function TyPaginationPreferredHeight(AStripPadTop, AStripPadBottom, ALineHeight,
  ACellPadTop, ACellPadBottom, AGlyphSize: Integer): Integer;
function TyPaginationGlyphRect(const ACell: TRect; ASize: Integer): TRect;
```

全部整数 / 记录入参，无控件状态、无句柄、无主题依赖，测试直接调用（`tests/test.pagination.pas`）。

#### 页码规则

- **`TyPaginationValidIndex`**：`ACount <= 0` → `-1`（「没有页」）；否则把 `ACurrent` **夹进** `0..ACount-1`。这是对 `TySegmentedValidIndex`（以及本库 `ItemIndex` 惯例「越界答 `-1`」）的**刻意背离**：分段控件确实可以什么都没选中，但**列表总在显示某一页**，所以「我在第几页」在有页的时候永远不会是「没有」。宿主问「195 页里的第 500 页」是它自己算错了，答 `-1` 会让整条带**一个当前页都没有**——夹住则至少给它看数据真正拿得出来的最后一页。
- **`TyPaginationStepIndex`**：`ACurrent + ADelta`，**两端都夹住、不回卷**——跑出结果集的尽头应该**停下**，而不是把用户从第 195 页瞬移回第 1 页。**步进之前也先夹一次**：一个停在范围外的 `ACurrent` 必须从**带子实际显示着的**那页起步，而不是从一页不存在的页起步（`TyPaginationStepIndex(500, 195, -1) = 193`）。

#### 省略规则（`TyPaginationItems`）

规则本体：**永远**是开头 `ABoundaryCount` 页 + **永远**是结尾 `ABoundaryCount` 页 + **永远**是当前页两侧各 `ASiblingCount` 页的窗口，中间被省掉的整段画 `...`。两条性质让它读起来是个**稳的**控件而不是个**跳的**：

- **格子数是恒定的**。窗口**不是**简单的 `current ± s`：靠近任一端时它被**向内推**以保住完整宽度。所以 195 页的第 1 页是 `< 1 2 3 4 5 ... 195 >`，而**不是**一条会随着你往里走而变长的 `< 1 ... 195 >`。（没有这条，带子就会**恰好在用户瞄准它的那一刻**在指针底下改变长度。）测试逐页走完 195 页，断言格子数始终是 9。
- **一个省略号绝不会只藏一页**。被省掉的整段**恰好一页长**时，就把那一页**画出来**顶替本该出现的 `...`——同样的宽度、多一页够得着、而且没有一个 `...` 在谎报它藏了多少。

`APageCount <= 0` → **空列表，连箭头都没有**：没什么可分页的，而一条挂着两个死箭头的带子会谎称有。

默认旋钮（`sibling=1` / `boundary=1` / 带箭头）下的实际输出（取自测试）：

| 输入 | 输出 |
|------|------|
| `TyPaginationItems(0, 0, 1, 1, True)` | `（空）` |
| `TyPaginationItems(1, 0, 1, 1, True)` | `< 1 >`（两个箭头都在，且都惰性） |
| `TyPaginationItems(7, 3, 1, 1, True)` | `< 1 2 3 4 5 6 7 >`（**7 页是不省略的临界值**） |
| `TyPaginationItems(8, 3, 1, 1, True)` | `< 1 2 3 4 5 ... 8 >`（多一页就开始省，且**格子数不变**） |
| `TyPaginationItems(195, 0, 1, 1, True)` | `< 1 2 3 4 5 ... 195 >` |
| `TyPaginationItems(195, 4, 1, 1, True)` | `< 1 ... 4 5 6 ... 195 >`（头块与窗口脱开的第一页） |
| `TyPaginationItems(195, 97, 1, 1, True)` | `< 1 ... 97 98 99 ... 195 >`（这个控件存在的意义） |
| `TyPaginationItems(195, 194, 1, 1, True)` | `< 1 ... 191 192 193 194 195 >` |
| `TyPaginationItems(195, 97, 0, 1, True)` | `< 1 ... 98 ... 195 >` |
| `TyPaginationItems(195, 97, 2, 1, True)` | `< 1 ... 96 97 98 99 100 ... 195 >` |
| `TyPaginationItems(195, 97, 1, 2, True)` | `< 1 2 ... 97 98 99 ... 194 195 >` |
| `TyPaginationItems(195, 97, 1, 1, False)` | `1 ... 97 98 99 ... 195` |

**旋钮同样被夹**（函数自己夹，不依赖属性 setter）：`ABoundaryCount < 1` 按 `1` 算，`ASiblingCount < 0` 按 `0` 算，`APageIndex` 越界按 `TyPaginationValidIndex` 夹。

**「惰性」不是第二个标志位，而是目标的缺席**（`Page < 0`），一条规则覆盖全部情形：省略号代表的是它**没有点名**的那些页；首页上的 prev / 末页上的 next **无处可去**。绘制、命中检测、状态机**都只读 `Page < 0`**，别的什么都不需要知道。

- **`TyPaginationItemVariant`**：`'prev'` / `'page'` / `'ellipsis'` / `'next'`——主题写规则的那四个名字。`pikPage`（以及未来枚举扩展忘掉的任何值）都落到 `'page'` 这个基线上。
- **`TyPaginationItemLabel`**：**整个 0-based / 1-based 契约就这一行**——页格子给 `IntToStr(Page + 1)`，省略号给 `TyPaginationEllipsis`，**箭头给 `''`**（它们是字形，不是文字）。

#### 几何

- **`TyPaginationItemRects`**：结果是**设备像素**、相对控件矩形左上角，**每个格子一个矩形**（哪怕一个都没放下，所以结果的下标**永远**是格子列表的下标）。格子从「带子按主题 `padding` 内缩后」的左边缘起、间隔 `AGap` 向右排；每个格子**填满整条带的高度**（chip 就是格子本身）。
  - **各格子内容宽度是入参，不是这里量的**：只有这一部分需要字体。格子**故意不等宽**——`195` 和 `...` 比 `1` 宽。
  - **放不下**（放不**整**）的格子留**空矩形**，**它之后的每一个也都是空的**（游标只会向右）：带子太窄就**整个丢掉**放不下的格子，而不是画一条既读不了也瞄不准的残片；而**空矩形不可命中**，所以画和点二者天然一致。
  - **零宽格子不是格子**：既不占位置，也不占一个间隙。
  - `padding` 吃掉整条带 / 宽高 ≤ 0 → 全空矩形，**绝不出现反向矩形**。
- **`TyPaginationIndexAt`**：`TyPaginationItemRects` 的**精确逆函数**——它扫的就是那个函数自己的输出，所以**用户点到的格子永远是画在那儿的格子**，二者不可能漂移。**格子之间的间隙不属于任何格子**（不同于 `TTySegmented`——它的分段是**铺满**整条带的，而这条带有真正的落水槽）：点在间隙里答 `-1`，惰性。
- **`TyPaginationPreferredWidth`**：`TyPaginationItemRects` 的**逆**——把结果当 `AClientWidth` 回喂（其余参数相同），每个格子都恰好是它的自然宽度，最后一个的右边缘正落在右 `padding` 上（已有往返测试守护）。**间隙只在格子之间**，绝不出现在整条的两头（一个格子 ⇒ 零间隙）。空带子就只是它自己的 `padding`。宽度下限 `AMinCellWidth` **也参与测量**，不只参与布局。
- **`TyPaginationPreferredHeight`**：带子的 `padding` 包住一条「够高放下一行文字 + 该行自己的 `padding`」的格子带，**且永不低于箭头槽位**——槽位是在**格子**里居中的，否则会被压扁（沿用 `TTyTag` 关闭槽位的规矩）。注意**下限是光秃秃的槽位本身，不是「槽位 + padding」**：`TyPaginationPreferredHeight(2, 2, 4, 0, 0, 30) = 2 + 30 + 2`。
- **`TyPaginationGlyphRect`**：prev / next 格子里那个 `ASize` 见方的箭头槽位，**居中**，并且**夹进格子里**而不是任其溢出。没地方 / 没尺寸 → 空矩形。

### 公开成员

```pascal
function TyPaginationItemList: TTyPaginationItems;  // 当前五个属性产出的格子列表 —— 画和点用的就是它
function ItemCount: Integer;                        // 当前有几个格子
function TyPaginationCellRect(AIndex: Integer): TRect;  // 格子矩形（设备像素，(0,0)-local）；越界或没放下 => 空
function TyPaginationCellAt(X, Y: Integer): Integer;    // 客户区设备坐标处的格子，或 -1（含格子之间的落水槽）
```

> `TyPaginationItemList` 是**每次重算而非缓存**的：它是五个属性的**纯函数**，所以这里放缓存只可能变馊；而它本身很廉价（几条记录）。

---

## 6. 状态与主题

### 支持的伪类状态

- **格子带**（`TyPagination`）：`:hover` / `:active` / `:disabled` / `:focus` 由基类状态机计算。**焦点属于整条带，不属于某个格子**——这不需要任何代码：基类的 `CurrentStates` 本来就把 `tysFocused` 交给**带子自己**的样式，所以主题在 `TyPagination:focus` 上写一条普通的 outline 规则，就能像本库其它任何可聚焦控件一样，通过 `DrawFrame` 给它套上焦点环。
- **格子**（`TyPaginationItem`）：状态**逐格子**计算：

| 状态 | 何时出现 |
|------|----------|
| `:selected` | 该格子是 `pikPage` **且** `Page = PageIndex`——即**当前页**。这与 `TTyButton.Down` 注入的是**同一个** `tysSelected`，所以**一条 `:selected` 规则同时管住按下的按钮和当前页**。 |
| `:disabled` | 控件 `Enabled = False`（**整条带的所有格子**），**或者**该格子**惰性**（`Page < 0`：每个省略号、首页上的 prev、末页上的 next）。 |
| `:hover` | 指针下的那一个格子。 |
| `:normal` | 以上都不是。 |

> **两条刻意的规则：**
> - **禁用状态保留 `:selected`**（`TTySegmented` 对 `TTyButton.Down` 的背离，理由相同）：一个变灰的分页器**仍然必须显示当前生效的是哪一页**。丢掉那个 chip 读起来会是「没有页」，而不是「你改不了这个」。级联负责其余部分——`ResolveLayer` 先套 `:selected` 作静息层、`:disabled` **最后**套且优先级最高，于是 chip 活下来、而禁用的墨色压过它。**禁用时刻意没有 hover**：禁用的控件不接受悬停。
> - **惰性读作 `:disabled`**：那正是主题**已经有的**「这个你点不了」状态，所以四种 kind **不需要自己的状态词汇**；而且**画和 `MouseDown` 天然一致**（两边都读 `Page < 0`）。测试断言：即便指针**正压在**省略号上，它拿的也是 `:disabled` 而不是 `:hover`。

**kind variant 与 `StyleClass` 怎么相处：** 传给引擎的 variant 串是 `'<kind> <用户的 StyleClass>'`——**kind 永远先出**。`ResolveLayer` 按文本顺序套用 variant 令牌，所以 kind 的外观**一定会被套用**，而显式的 class 逐属性叠在它之上（引擎既有的多令牌级联，后者胜），与 `TTyAlert.StyleVariant` 完全同一套路。

### 主题令牌摘要

以下是 `themes/light.tycss` 中的**实际规则**（基础层，每个主题都继承它，然后可以任意重塑）：

```css
/* Pagination: a transparent strip of cells — the page numbers are the chrome, not a bar. */
TyPagination         { background: alpha(#FFFFFF, 0); color: var(--on-surface); font-size: var(--font-size-base); }
TyPagination:disabled { opacity: var(--disabled-opacity); }
TyPaginationItem          { background: alpha(#FFFFFF, 0); color: var(--on-surface);
                            border-color: var(--border); border-width: var(--input-border-width);
                            border-radius: var(--radius-sm); font-size: var(--font-size-base); padding: 0px 6px; }
TyPaginationItem:hover    { border-color: var(--accent); color: var(--accent); }
TyPaginationItem:selected { background: var(--accent); color: var(--on-accent); border-color: var(--accent); }
TyPaginationItem:disabled { color: var(--muted); border-color: var(--border); }
```

> **`background: alpha(#FFFFFF, 0)` 不是废话。** 带子和格子都要求「**没有 `background` 就什么都不画**」（见下方降级），所以要得到一条**透明**但**仍然会绘制**的带子，唯一的写法就是显式地给一个**全透明的**底色。页码本身就是 chrome，这条带子不该是一根 bar。
>
> **基础层没有定义 `TyPaginationItem.ellipsis`。** kind variant 这个钩子**是活的**（测试守护），但基础层没有用它——想要 Ant 那种「无边框省略号」的主题自己写 `TyPaginationItem.ellipsis { border-width: 0; }` 即可，本单元不需要改。
>
> **基础层也没有定义那三个尺寸令牌**，所以它们全部落在下表的内置兜底值上。

### 降级：主题没定义某个 key 时

| 情况 | 行为 |
|------|------|
| `TyPagination` **没有 `background`** | **整个控件什么都不画**——连格子也不画（哪怕 `TyPaginationItem` 定义得好好的）。降级，而不是发明一种外观。 |
| `TyPaginationItem` **没有 `background`** | **不画 chip**，但**标签照画**。于是「只填 `:selected`」的主题**白拿**经典的「只有当前页有 chip」，控件里没有为此写任何分支。 |
| `TyPaginationItem` 没有 `border` | 不描边（`TyBorderVisible` 判定）。 |
| `TyPaginationItem` 没有 `color` / `font-name` / `font-size` / `font-weight` | **逐属性回退到带子（`TyPagination`）自己的那一份**。这是本库「没有颜色就继承父级的墨色」这条降级规矩，按同样的逻辑延伸到了字体上——只给 `TyPagination` 写规则的主题，也必须得到**读得清、字号对**的页码，而且**绝不会**回退到任何硬编码颜色。 |

> 注意 `background` / `border` **刻意不走这条继承**：没有自己底色的格子**必须不画 chip**（否则每个格子都会顶着整条带的底色变成一块砖）。

### 可调尺寸令牌（v3/C 约定）

| 令牌 | 内置默认（逻辑像素） | 作用 |
|------|------|------|
| `--pagination-gap` | `4`（= `TyPaginationGap`） | 两个格子之间的间隙 |
| `--pagination-min-cell-width` | `32`（= `TyPaginationMinCellWidth`） | 单个格子宽度的**下限**（一个数字只量得出几个像素，那样的格子瞄不准；下限让每个格子都是个真靶子） |
| `--pagination-glyph-size` | `12`（= `TyPaginationGlyphSize`） | prev / next 箭头的方形槽位边长；**它同时也是整条带高度的下限** |

**三个都是真·可调**（测试守护）：改 `--pagination-gap` 会同时移动几何**和命中检测**；改 `--pagination-min-cell-width` 会重调格子宽度；把 `--pagination-glyph-size` 调到 `64px`，`CalculatePreferredSize` 报出的高度就正好是 `64`。

**带子自身的内缩不在其列**：那就是 `TyPagination` 样式**普通的 CSS `padding`**，而格子的水平内缩是 `TyPaginationItem` 的——两者**本来就是主题化属性**，再为它们发明令牌等于把同一件事说两遍。

**两个箭头字形还支持图标字体覆盖**（v3/C5）：`--glyph-arrow-left` / `--glyph-arrow-right`。用的是 `tgArrowLeft` / `tgArrowRight` **而不是**一对 V 形箭头：painter 有 `tgChevronRight` 但**没有** `tgChevronLeft`，半对 V 形会读成两个不同的记号。想要 V 形的皮肤就把它们塞进上面这两个令牌里。

---

## 7. 代码示例

```pascal
uses tyControls.Controller, tyControls.Pagination;

TyDefaultController.LoadTheme('themes/light.tycss');

var P: TTyPagination;

// 列表页脚的翻页条
P := TTyPagination.Create(Self);
P.Parent := Surface;
P.PageCount := 195;              // 宿主自己算出来的总页数
P.PageIndex := 0;                // 0-BASED：这画出来是「1」
P.OnChange := @HandlePageChange;
P.Left := 16; P.Top := 400;

// 窄页脚：把窗口收掉，只留首末页和当前页
P := TTyPagination.Create(Self);
P.Parent := Surface;
P.SiblingCount := 0;             // < 1 ... 98 ... 195 >
P.AutoSize := True;
P.PageCount := 195;
P.PageIndex := 97;
```

宿主在 `OnChange` 里重填自己的列表——**分页器自己不驱动任何东西**：

```pascal
procedure TForm1.HandlePageChange(Sender: TObject);
var
  Pag: TTyPagination;
begin
  Pag := Sender as TTyPagination;
  if Pag.PageIndex < 0 then Exit;             // PageCount = 0：没有页
  FillListView(FQuery.Fetch(Pag.PageIndex * PageSize, PageSize));
end;
```

宿主重查数据后更新页数（**这不会**回调 `OnChange`，`PageIndex` 自己读回去）：

```pascal
procedure TForm1.RequeryDone(ATotal: Integer);
begin
  Pag.PageCount := (ATotal + PageSize - 1) div PageSize;   // 停在范围外的当前页被静默重夹
  FillListView(FQuery.Fetch(Pag.PageIndex * PageSize, PageSize));
end;
```

---

## 8. 注意事项

- **页码从 0 开始，标签从 1 开始。** `PageIndex := 0` 画出来是 `1`。整个契约只活在 `TyPaginationItemLabel` 这一个函数里。宿主算偏移时用的是 `PageIndex`（0-based），不是标签。
- **`PageCount = 0` 时 `PageIndex = -1`，且一个格子都没有。** 这是「没有页」的唯一情形；`OnChange` 处理器要挡一下（见上面的示例）。
- **点击在「按下」时翻页，不是在「抬起」时**——本库开关类控件的既定规矩（`TTySegmented`、`TTyCustomTabStrip`）。
- **落水槽是惰性的。** 两个格子之间的间隙不属于任何格子，点它**不会**翻到「最近的那个」。这与 `TTySegmented` 不同——它的分段是铺满整条带的，这条带有真正的间隙。
- **一条规则管全部四种 kind：** 点击去往「该格子的目标页」，**没有目标的格子什么也不做**（省略号；首页上的 prev / 末页上的 next）。没有为它们单开分支。
- **键盘：** `Left` / `Right` 翻一页（**这就是它可聚焦的全部理由**），`Home` / `End` 跳到两端（与 `TTySegmented` 的键盘一致）。**每个被处理的键都会被吃掉**（`Key := 0`），绝不再传给窗体。**但**：`Enabled = False` 或 `PageCount = 0` 时，键**不被消费**——禁用的控件必须让按键继续传给窗体去做别的事。
- **不回卷。** 在第 195 页按 `Right`、在第 1 页按 `Left`，都是**停住**，而且**被挡住的翻页不是变化**（不发 `OnChange`）。
- **`AutoSize` 下带子会抖动几个像素：** 格子**不等宽**，所以用户在 `1 2 3` 和 `1 ... 97` 之间翻页时，自动尺寸的带子会重新贴合。**格子的「个数」是恒定的**（见 `TyPaginationItems`），**宽度不是**。不想抖就关掉 `AutoSize`，用 `Align` / `Anchors` 给它固定边界——带子会从它的左 `padding` 起排布格子。
- **`AutoSize` 需要已实现句柄的父窗体：** LCL 的 `AutoSizeDelayed` 在父窗体未实现句柄时会抑制所有重新贴合（headless 场景下 `AutoSize` 不生效）——这是 LCL 行为，不是本控件的。测试因此直接验 `CalculatePreferredSize`。
- **带子太窄会丢格子，且丢的是「从某一个起的全部」。** 放不整的格子留空，它之后的每一个也都空——不会画残片，也不可命中。**这不是错误状态，不会有任何提示**：宿主要么给够宽度（`AutoSize` 或 `TyPaginationPreferredWidth`），要么调小 `SiblingCount`。
- **省略号是三个 ASCII 句点，不是 U+2026。** 它正是 `TTyPainter.DrawText` 截断标签时追加的那个记号，于是**被省略的一段**和**被截断的一个标签**在同一条带里读起来是同一回事；同时也让本单元和这里其它每个源文件一样保持纯 ASCII。它是标点而非散文，所以是常量而**不是** resourcestring——里面没有可翻译的东西。
- **格子的高度测量取的是「页格子」的静息样式** + 一个稳定的参考字形（`'Ag'`）：页码是这条带的基线内容，所以一条窗口恰好全是省略号的带子，高度也和别的带子**一模一样**；而且**把当前页加粗的主题不会让带子的宽度取决于当前是第几页**（宽度测量同样用的是每种 kind 的**静息**样式）。
- **文字用主题样式，不读 LCL Font：** 遵循「主题锁定」约定，改字号 / 字色请改主题令牌或用 `StyleClass` / `StyleOverride`。标签**不解析助记符**——这里没有 Alt+key 通路，页码里也不会有 `&`。
- **窗口化控件：** `DrawFrame` 会先填上父级的不透明表面——窗口化控件**无论主题怎么说都需要这一步**（否则圆角缺口处会露出它自己的窗口）。而「我们自己的」那些绘制**全都**以「主题定义了 `TyPagination` 的 `background`」为闸门。
