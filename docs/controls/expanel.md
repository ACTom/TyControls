# TTyExPanel — API 参考

## 1. 概述

`TTyExPanel` 是 TyControls 库中的**可折叠/展开面板容器**，继承自 `TTyCustomPanel`（后者继承自 `TTyCustomControl`）。它在控件顶部绘制一段**标题栏（header band）**：内含一个展开/折叠的 chevron（展开时 V、折叠时 >）和 `Caption` 文字；点击标题栏即切换 `Collapsed` 状态。标题栏下方是**主体区（body）**，用于放置用户的子控件。

- **折叠时**：控件的 `Height` 收缩到只剩标题栏高度；`ExpandedHeight` 记住折叠前的完整高度。
- **展开时**：`Height` 恢复到 `ExpandedHeight`。

折叠/展开使用库内的缓动动画内核（`TTyAnimator` / `TyEase` / `TyLerpI`）：**运行时**由一个 `TTimer` 逐帧驱动高度平滑过渡；**无窗口句柄（headless / 测试环境）或动画时长为 0** 时，高度**直接跳到最终值**（不启动定时器）。

`TTyExPanel` 是一个**真容器**（保留 `csAcceptsControls`）：主体区的子控件由用户放置，LCL 的 `AdjustClientRect` 机制会把客户区顶边下移一个标题栏高度，使子控件落在标题栏下方。**只有标题栏由面板自绘**（不是一个独立的子控件）。

典型用途：属性检查器 / 选项分区 / 侧边栏中可展开收起的分段。

当作侧栏里的一节来用时，标题栏还能做三件事（第 7 节）：末端放一个**操作区**（`TTyExPanelActions`），里面是这一节自己的小按钮；标题栏能拿键盘焦点，空格、回车、左右方向键控制展开和折叠；`StyleClass = 'embedded'` 去掉面板自己的边框和圆角。把几节上下堆起来、按权重分高度、拖动边界，用 [`TTyAccordion`](accordion.md)。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ExPanel` |
| 盒子 typeKey | `TyExPanel`（**自有 typeKey**） |
| 标题栏 typeKey | `TyExPanelHeader`（**自有子部件键**，支持 `:hover`、`:focus`） |
| 操作区 typeKey | `TyExPanelActions`（`TTyExPanelActions` 自己的键） |
| 基类 | `TTyCustomPanel`（继承自 `TTyCustomControl` → `TCustomControl`） |
| 默认尺寸 | 200 × 140（逻辑像素） |
| 默认标题栏高度 | 26 逻辑像素（常量 `TyExPanelDefaultHeaderHeight`）；没设 `HeaderHeight` 时，标题的字体放不下就随字体长高 |
| 客户区顶边内缩 | 一个标题栏高度（`AdjustClientRect` 实现，随 DPI 缩放） |

```pascal
uses tyControls.ExPanel;
```

### 这两个键各画什么

| 键 | 画什么 | 读哪些属性 |
|----|--------|-----------|
| `TyExPanel` | 整个控件的框（`DrawFrame`：背景 + 边框 + 圆角），标题栏与主体共用这一张表面；标题文字的**右内缩**也取它的 `padding.right` | `background` / `border-color` / `border-width` / `border-radius` / `padding` / `color` / `font-*` |
| `TyExPanelHeader` | 标题栏band 的**墨色与字体**（chevron 与 `Caption` 一起上色），以及**可选的**band 底色、顶边线和焦点环 | `color` / `font-name` / `font-size` / `font-weight`；`background` 是**opt-in**：声明了才填底（band 会自动从边框内缩、外圆角跟随面板），不声明则完全不填，面板那一张表面原样透出。`border-color` + `border-width` 在这个键上是 band **顶边的一条线**（写法同 `TyStatusBar` 的顶线），不声明就不画。`:focus` 里的 `outline` 是标题栏的焦点环。支持 `:hover`——band 是唯一可点区域，因此悬停只作用于它，而不是整个客户区 |
| `TyExPanelActions` | 操作区自己的底 | 内置主题不给它 `background`：这时它把标题栏的底色、悬停色、顶边线和焦点环接着画过去，按钮像是直接放在标题栏上。给了 `background`，它就按自己的画 |

> **早期版本返回 `'TyPanel'`，那份文档还写着"不应为 `TTyExPanel` 新增 `.tycss` 规则；调整外观请修改主题中的 `TyPanel` 规则"——照做会重涂全应用的每一个面板。`TTyExPanel` 之所以存在自己的键，正是为了不必那样做。** 现在：改折叠面板的框写 `TyExPanel { … }`，改标题栏的字色 / band 底 / 悬停写 `TyExPanelHeader { … }`，两者都不会波及普通面板。
>
> `TyExPanel` 已作为附加选择器并入主题里 `TyPanel` 的规则块，解析值与从前逐字节相同，**开钩子而不动像素**；第三方主题若只覆盖了 `TyPanel`，需要补上 `TyExPanel`（主题层按 typeKey 全有全无地回落，否则会掉回内置 light 取值）。内置主题只给 `TyExPanelHeader` 声明了 `color`，故意不给 `background` / `font-size` / `font-weight`——band 保持无底色带、字体跟随面板，正是今天的观感。
>
> 除这两个键外**没有更细的子部件键**：chevron 与 `Caption` 共用 `TyExPanelHeader` 的墨色（真实折叠头就是这么联动的），不单独可着色。chevron 是全库统一的展开标记：大小取 `--glyph-chevron-size`、墨色再乘 `--glyph-chevron-alpha`，`--glyph-chevron-down` / `--glyph-chevron-right` 可以把它换成图标字体字形（见 [tycss 参考](../tycss-reference.md) 第 16 条）。

---

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Collapsed` | `Boolean` | `False` | 是否折叠。写入 `True` 时记住当前 `Height` 到 `ExpandedHeight` 并将高度收缩到标题栏高度（触发 `OnCollapse`）；写入 `False` 时恢复到 `ExpandedHeight`（触发 `OnExpand`）。值未变化时为 no-op（不触发事件）。折叠期间主体里的子控件退出 Tab 顺序；折叠时焦点若在主体里，会移到面板之后的下一个控件，免得按键落进看不见的控件。 |
| `HeaderHeight` | `Integer` | `26` | 标题栏高度（逻辑像素，最小 1）。改变后会重新计算主体区内缩并重绘；若当前处于折叠态（且无动画进行中），控件高度同步跟随。 |
| `AnimationDuration` | `Integer` | `160` | 折叠/展开动画时长（毫秒）。`0` = 瞬间跳变（不启动定时器）。运行时由 `TTimer` 逐帧驱动，headless 环境下始终跳变。 |
| `OnExpand` | `TNotifyEvent` | `nil` | 从折叠切换到展开时触发。 |
| `OnCollapse` | `TNotifyEvent` | `nil` | 从展开切换到折叠时触发。 |
| `ActionsVisibility` | `TTyExPanelActionsVisibility` | `eavAlways` | 标题栏操作区什么时候显示。`eavAlways`：一直显示；`eavHoverOrFocus`：只在鼠标停在标题栏上（包括停在操作区上）或焦点在这个面板里时显示。不显示时操作区宽度为 0，标题文字占满标题栏。 |
| `TabStop` | `Boolean` | `False` | 设为 `True` 后标题栏能用 Tab 走到、点击标题栏也会拿到焦点，键盘操作见第 7 节。默认值没有变，老窗体的 Tab 顺序不受影响。 |
| `Caption` | `string` | `''` | **继承自 `TTyCustomPanel`**。绘制在标题栏内、箭头右侧，垂直居中。 |
| `Align` / `Anchors` / `StyleClass` / `Controller` | — | — | 继承自基类的通用容器成员。 |

### public 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `ExpandedHeight` | `Integer` | 完整（展开）高度。折叠时它是展开将要恢复到的高度；构造时以初始 `Height` 播种，折叠瞬间以当前 `Height` 更新。可读写。与 `Height` 一样是设备像素，DPI 变化时跟着缩放。放在 `TTyAccordion` 里时它是这一节的**权重**：展开的各节按它的比例分高度，折叠时不再用 `Height` 覆盖它，展开着也会存进 `.lfm`。 |

### public 方法（标题栏的几何与操作区）

| 方法 | 说明 |
|------|------|
| `HeaderActions: TTyCustomExPanelActions` | 标题栏的操作区：子控件里的第一个 `TTyExPanelActions`，没有就是 `nil`。 |
| `EnsureHeaderActions: TTyCustomExPanelActions` | 没有操作区就建一个再返回。建出来的归窗体所有，会存进 `.lfm`。 |
| `ActionsShowing: Boolean` | 操作区此刻是否占着标题栏的位置（有操作区、里面有可见的子控件、`ActionsVisibility` 允许）。 |
| `HeaderHot: Boolean` | 鼠标是否在标题栏上（操作区算标题栏的一部分）。 |
| `HitTest(X, Y): TTyExPanelHit` | 客户区坐标落在哪一块：`ephHeader`（标题栏，点了会切换）、`ephActions`（操作区，不切换）、`ephBody`、`ephNone`。 |
| `HeaderRect` / `HeaderGeom` / `ActionsRect` / `BodyRect` | 标题栏、它的三块（chevron、标题文字、操作区）、操作区、主体区的矩形，设备像素、客户区坐标。绘制、命中测试、摆放操作区用的是同一份。 |
| `HeaderHeightPx: Integer` | 标题栏高度，设备像素。 |

### 常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `TyExPanelDefaultHeaderHeight` | `26` | 默认标题栏逻辑高度。 |

---

## 4. 纯几何函数（可独立单元测试）

以下几个单元级函数为纯计算（**设备像素**，无副作用），是折叠面板逻辑的**受测核心**——测试直接调用它们，无需真实窗口。渲染路径与命中测试均复用这些函数，保证「画在哪里」与「点哪里生效」一致。

```pascal
{ 顶部标题栏矩形：整宽、AHeaderHeight 高，超过客户区高度时钳制到客户区高度。 }
function TyExPanelHeaderRect(const AClient: TRect; AHeaderHeight: Integer): TRect;

{ 展开/折叠箭头三角形的三个顶点，位于标题栏左侧的一个小方形区域内。
  AExpanded=True → 向下（主体展开）；False → 向右（主体隐藏）。
  面板已不再画这个实心三角（改画下面那个 chevron），函数为兼容保留。 }
function TyExPanelChevronPoints(const AHeaderRect: TRect; AExpanded: Boolean): TTyTriangle;

{ 标题栏画的 chevron：展开时 tgChevronDown，折叠时 tgChevronRight。 }
function TyExPanelChevronKind(AExpanded: Boolean): TTyGlyphKind;

{ 缓动参数 t（0..1）下的插值高度：t=0 → ACollapsedH，t=1 → AExpandedH。
  在 t 上线性（调用方传入已缓动的 t）。 }
function TyExPanelHeightAt(ACollapsedH, AExpandedH: Integer; t: Single): Integer;

{ 标题栏的三块。AHeader 是整条标题栏，AInner 是它在面板边框以内的那一段（操作区从这一段的
  末端切出来）；AInset 是 BorderWidth；ATrailingPad 是没有操作区时标题文字的末端留白；
  AActionsWidth 是操作区想要的宽（0 = 没有）。放不下时先挤标题文字，再挤操作区，chevron 始终完整。
  ARightToLeft 时三块整体镜像。 }
function TyExPanelHeaderLayout(const AHeader, AInner: TRect; AInset, ATrailingPad,
  AActionsWidth: Integer; ARightToLeft: Boolean): TTyExPanelHeaderGeom;

{ 操作区里那一排子控件：从前导端依次排，两端各留 APad、相邻两个之间留 AGap，各自在 AAvailH 里
  垂直居中（比标题栏高的上下都被操作区裁掉）。整排比 AAvailW 宽时保住末端那几个。 }
function TyExPanelActionsFlow(const AWidths, AHeights: array of Integer;
  AAvailW, AAvailH, APad, AGap: Integer; ARightToLeft: Boolean): TTyExPanelFlow;
```

其中 `TTyTriangle = array[0..2] of TPoint`（在 `tyControls.ExPanel` 中声明）。

---

## 5. 方法与事件

### AdjustClientRect（protected override）

在继承实现基础上将 `ARect.Top` 增加 `ScaledHeaderHeight`（即 `HeaderHeight` 按当前 DPI 缩放后的物理像素）。放在面板内的子控件 `Top = 0` 即等价于标题栏下方，无需手动偏移。

### MouseDown / MouseMove / MouseLeave（protected override）

- `MouseDown`：左键点击且落在标题栏上（`HitTest = ephHeader`）时切换 `Collapsed`（`Enabled = False` 时忽略）。点在操作区上不切换。`TabStop = True` 时这一下点击也把焦点放到面板上。
- `MouseMove` / `MouseLeave`：跟踪鼠标是否悬停在**标题栏**上。这个标志会替换掉控件级的 hover 参与 `TyExPanelHeader` 的状态解析——只有 band 可点，所以也只有 band 该读作 hot；主题写 `TyExPanelHeader:hover { … }` 即可生效。鼠标移到操作区的按钮上仍算在标题栏上。

### KeyDown / HeaderKeyDown / UserToggle（protected）

`KeyDown` 先调 `OnKeyDown`（把 `Key` 置 0 就拦下了），再调 `HeaderKeyDown`。`HeaderKeyDown` 是虚方法，内置的按键见第 7 节，子类可以覆盖它加自己的键。点击和按键切换时走的都是虚方法 `UserToggle`（`Collapsed := not Collapsed`）。

### 事件

- `OnCollapse`：`Collapsed` 由 `False` 变为 `True` 时触发。
- `OnExpand`：`Collapsed` 由 `True` 变为 `False` 时触发。

---

## 6. 折叠动画与 headless 语义（重要）

`SetCollapsed` 决定目标高度后调用内部的 `StartHeightAnimation`：

- **有窗口句柄且 `AnimationDuration > 0`**：从当前 `Height` 起，用 `teEaseOutCubic` 缓动，由 16ms（约 60fps）的 `TTimer` 逐帧把 `Height` 推向目标；每帧 `Height` 变化会触发 LCL 重新布局子控件并重绘。
- **无句柄（headless / 测试）或 `AnimationDuration = 0`**：`Height` **立即设为最终值**（`SetTargetImmediate`，不启动定时器）。

> **契约**：在无句柄环境中切换 `Collapsed`，`Height` 会**同步**变为最终高度（折叠 = `ScaledHeaderHeight`，展开 = `ExpandedHeight`）。测试据此直接断言 `Height`，无需等待定时器。真实逐帧动画属于真机行为。

---

## 7. 作为一节：操作区、键盘、无边框

### 标题栏操作区

`TTyExPanelActions` 是放在标题栏末端的小容器，里面放按钮之类的真实子控件（刷新、新建、全部折叠……）。

- **设计期**：从组件面板的「TyControls Containers」页把 `TTyExPanelActions` 放到 `TTyExPanel` 上，它会自己贴到标题栏末端；再把按钮放进去。空着的时候设计器里显示一个方槽，运行时空的操作区不占位置。
- **代码里**：`Panel.EnsureHeaderActions` 返回操作区，把按钮的 `Parent` 设成它。
- 子控件按创建顺序排成一排，垂直居中，比标题栏高的部分被裁掉；它们自己的 `Align` / `Anchors` 不起作用。两端留白和间距读主题令牌 `--expander-actions-pad`（默认 4）、`--expander-actions-gap`（默认 2），也可以写在操作区自己的 `StyleOverride` 里。
- 标题文字在操作区前面结束，放不下就出省略号；实在太窄时操作区也让位，chevron 始终完整。从右往左的界面里整条标题栏镜像，操作区在左端。
- 一个面板只认第一个操作区。多出来的（比如粘贴进来的）和没放在 `TTyExPanel` 里的，只在设计期显示，方便删掉。
- 面板折叠时主体里的控件退出 Tab 顺序，操作区里的按钮**不退**；Tab 顺序里它们排在主体控件前面。
- `ActionsVisibility = eavHoverOrFocus` 时，操作区平时宽度为 0，鼠标移到标题栏上或焦点进入面板（Tab 到标题栏、到操作区里的按钮、到主体里的控件都算）才出现，所以只用键盘也够得到。

```pascal
var Act: TTyCustomExPanelActions;
    Btn: TTySpeedButton;
Act := Panel.EnsureHeaderActions;
Btn := TTySpeedButton.Create(Self);
Btn.Parent := Act;
Btn.SetBounds(0, 0, 20, 20);
Btn.StyleClass := 'ghost';
Btn.OnClick := @RefreshClick;
Panel.ActionsVisibility := eavHoverOrFocus;
```

### 键盘

把面板的 `TabStop` 设为 `True`，标题栏就能拿焦点（焦点在面板自己身上，不在子控件上）：

| 按键 | 作用 |
|------|------|
| 空格、回车 | 切换展开 / 折叠 |
| ← | 折叠 |
| → | 展开 |

从右往左的界面里 ← 和 → 对调。带 Shift / Ctrl / Alt 的组合不处理。这几个键即使没事可做也会被标题栏吃掉，免得 LCL 把方向键当成「跳到下一个控件」。在 `TTyAccordion` 里，↑ / ↓ 在各节标题栏之间移动焦点。

焦点环画在标题栏上：`TyExPanelHeader:focus { outline: … }`，内置主题是 2px 的 `--focus-ring`。

### 无边框的一节

`StyleClass := 'embedded'`：面板没有边框和圆角（`TyExPanel.embedded`），标题栏有底色和一条顶边线（`TyExPanelHeader.embedded`）。几节这样的面板堆在一起看起来是一整块表面，只由标题栏分隔。这个外观只由 `StyleClass` 选择，放进 `TTyAccordion` 不会自动套上。

> 自己的主题如果给 `TyExPanel` 写了规则，要把 `TyExPanel.embedded { border-width: 0; border-radius: 0; }` 再写一遍：主题给某个键写了规则，内置层这个键的整套规则（连同变体）就不再生效。

### 放在堆叠容器里

父控件实现了 `ITyExPanelHost`（`TTyAccordion` 就是）时，面板把高度交给父控件：切换 `Collapsed` 时不再自己改 `Height`，而是通知父控件重新分配（动画时长仍取这个面板的 `AnimationDuration`）；`OnExpand` / `OnCollapse` 照常触发，仍然是应用自己的事件。`ExpandedHeight` 在这里是权重，见属性表。

## 8. 状态与主题

`TTyExPanel` 用自己的两个键：

```css
/* 盒子：内置主题里与 TyPanel 等键同值同块（名字各自独立） */
TyExPanel {
  background: var(--surface);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: 1px;
  border-radius: var(--radius);
}

/* 标题栏：内置主题只声明 color，band 底色故意留空（不填 = 面板表面透出） */
TyExPanelHeader        { color: var(--on-surface); }
/* 想要一条有底色、悬停会亮的标题栏，加这两条即可——不影响任何普通面板 */
TyExPanelHeader        { background: var(--surface-hover); }
TyExPanelHeader:hover  { background: var(--selection); color: var(--accent); }

/* 标题栏拿到焦点时的焦点环（内置） */
TyExPanelHeader:focus  { outline: 2px var(--focus-ring); }

/* 无边框的一节（内置）：StyleClass = 'embedded' */
TyExPanel.embedded             { border-width: 0; border-radius: 0; }
TyExPanelHeader.embedded       { background: var(--surface-chrome); border-color: var(--border);
                                 border-width: var(--input-border-width); }
TyExPanelHeader.embedded:hover { background: var(--surface-hover); }

/* 操作区（内置不给底色，标题栏的底接着画过去） */
TyExPanelActions       { color: var(--on-surface); }
```

布局令牌：`--expander-header-height`（标题栏高度）、`--expander-actions-pad`（操作区两端留白，默认 4px）、`--expander-actions-gap`（操作区里相邻两个子控件的间距，默认 2px）。

### 渲染细节

绘制顺序（`RenderTo`）：

1. **整体框架**：`DrawFrame` 以 `TyExPanel` 样式绘制整个控件的背景 + 边框（标题栏与主体共用同一主题化表面，标题栏即其顶部一段）；
2. **band 底色、顶边线、焦点环（都是 opt-in）**：仅当 `TyExPanelHeader` 声明了 `background` 才填底——band 会从边框内缩、上方两角跟随面板圆角，避免二次填充糊掉抗锯齿的角弧；声明了 `border-color` + `border-width` 才画顶边线；`:focus` 解析出 `outline` 才画焦点环（环绕标题栏，在面板边框以内）。都不声明则一笔不画。操作区盖住的那一段由操作区接着画；
3. **chevron**：在标题栏左侧、与标题栏等高的方格里画全库统一的展开标记（`TyDrawChevron`），墨色是 `TyExPanelHeader` 叠加在面板样式之上后的 `TextColor`（主题两边都没声明时落回面板的墨色），展开时向下、折叠时向右（`TyExPanelChevronKind`）。以前这里填的是实心三角，那是库里留给“步进”的形状（微调、滚动条）；点击区域一直是整条标题栏，没有变；
4. **标题文字**：`Caption` 非空时以同一墨色 / 字体绘制在箭头右侧、标题栏内垂直居中（右内缩仍取**面板**的 `padding.right`——band 的盒子就是面板的盒子，标题栏键只管墨色与字体）。有操作区时文字在操作区前面结束。

---

## 9. 代码示例

### 基础可折叠面板

```pascal
uses
  tyControls.Controller, tyControls.ExPanel, tyControls.CheckBox;

TyDefaultController.LoadTheme('themes/light.tycss');

var Panel: TTyExPanel;
Panel := TTyExPanel.Create(Self);
Panel.Parent := Self;
Panel.SetBounds(16, 16, 240, 160);
Panel.Caption := '高级选项';
Panel.HeaderHeight := 28;
Panel.AnimationDuration := 180;

// 主体区放置子控件——Top=0 已自动位于标题栏下方
var Chk: TTyCheckBox;
Chk := TTyCheckBox.Create(Panel);
Chk.Parent := Panel;
Chk.SetBounds(12, 12, 180, 24);
Chk.Caption := '启用日志';

// 初始折叠
Panel.Collapsed := True;
```

### 监听展开/折叠

```pascal
procedure TForm1.PanelExpand(Sender: TObject);
begin
  StatusBar.Caption := '面板已展开';
end;

procedure TForm1.PanelCollapse(Sender: TObject);
begin
  StatusBar.Caption := '面板已折叠';
end;

// ...
Panel.OnExpand := @PanelExpand;
Panel.OnCollapse := @PanelCollapse;
```

完整可运行示例参见 `examples/containers/`。

---

## 10. 注意事项

1. **它有自己的 typeKey，请用它**：调整外观写 `TyExPanel`（框）/ `TyExPanelHeader`（标题栏墨色、band 底、悬停），单实例差异化才用 `StyleClass` / `StyleOverride`。**不要**为了改折叠面板去改 `TyPanel`——那会重涂全应用的每一个面板。
2. **`ExpandedHeight` 在折叠瞬间捕获**：展开恢复的是**折叠时**的高度，而非构造时的尺寸。若在折叠态直接改 `Height` 无意义（下次展开仍恢复 `ExpandedHeight`）；需要改变展开高度请在展开态设 `Height`，或直接写 `ExpandedHeight`。
3. **headless 高度即时到位**：测试 / 无句柄环境中 `Collapsed` 切换后 `Height` 立即是最终值；真机上是逐帧缓动。
4. **只有标题栏自绘**：标题栏是面板绘制出来的一段区域，不是子控件；`AdjustClientRect` 已把主体客户区下移一个标题栏高度，子控件不会遮住标题。
5. **`HeaderHeight` 随 DPI 缩放**：内部一律用 `MulDiv(HeaderHeight, PixelsPerInch, 96)`，绘制、命中测试、客户区内缩三者一致。
