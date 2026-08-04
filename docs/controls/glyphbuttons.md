# 图标命令按钮 (TTyGlyphButton / TTyGlyphContainerButton / TTySpeedButton)

## 1. 概述

这三个控件把 [[TTyIconFont]] 的**图标字体字形**和按钮标题配对，全部继承自 [[TTyButton]]，共享同一套框架、悬停背景淡入、状态、焦点环与数字角标（主题令牌见 §2，三者**并不共用一个键**）：

| 控件 | 布局 | 典型用途 | 默认尺寸 |
|------|------|----------|----------|
| `TTyGlyphButton` | 图标在**左**、标题在右 | 紧凑的命令按钮（图标 + 文字并排） | ~96 × 30 |
| `TTyGlyphContainerButton` | 大图标在**上**、标题在下 | Ribbon 风格的大按钮 | ~72 × 64（默认字形更大） |
| `TTySpeedButton` | 图标在左（扁平/工具栏） | 可分组的工具栏切换按钮 | ~32 × 32 |

它们共用一个基类 **`TTyGlyphButtonBase`**（本身不注册到组件面板），基类只做三件事：加上图标字体接线、按 `GlyphLayout` 放置字形、然后把标题交给继承的 `DrawContent` 画在剩余矩形里。字形的光栅化完全委托给 `TTyIconFont.RenderGlyph`（与 [[TTyCharImage]] 完全一致，返回调用方拥有的透明 BGRA 位图，用完释放）。

> 三者的框架、`:hover`/`:active`/`:focus`/`:disabled`/`:selected` 状态、悬停背景渐变和角标都由 [[TTyButton]] 的绘制路径**免费**提供；字形默认与标题同色（取解析后的 `TextColor`）。但**主题令牌不是同一个**——见下节。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.GlyphButtons` |

| 控件 | `GetStyleTypeKey` 返回值 |
|------|-----|
| `TTyGlyphButton` | `'TyButton'`（**继承未重写** —— 它就是一个带图标的普通按钮，框、内边距、各状态与 [[TTyButton]] 完全同义，唯一区别是内容区被切成"字形 + 标题"两块，这个借用是对的） |
| `TTyGlyphContainerButton` | `'TyGlyphContainerButton'`（自己的键） |
| `TTySpeedButton` | `'TySpeedButton'`（自己的键） |

后两者各自成键的原因：

- **`TTyGlyphContainerButton` 是 ribbon 的一块**瓷砖**（`glTop`、字形 24、72×64，`examples/ribbon` 就是把它丢进 `TyRibbonGroup`），不是一个按压按钮。**借 `TyButton` 时，瓷砖的背景/边框/圆角/内边距与对话框上那个"确定"按钮出自同一条规则**——主题想给瓷砖那种"常态无框透明、悬停才上色"的常规观感，就必须把全库按钮一起压平。`TyRibbon` 与 `TyRibbonGroup` 早就各有其键，这是那条命令带缺的第三个键。
- **`TTySpeedButton` 是扁平的工具栏切换钮**：它常态无框，而按压按钮常态有框，**这该由主题决定，不该由应用代码决定**。借 `TyButton` 时只剩一个杠杆——给每个 speed button 挂一个 `'ghost'`/`'toolbar'` 的 `StyleClass`；这把样式决策推给了每个应用,而工具栏**之外**用的 speed button 则拿到完整的按压按钮外框,主题无从干预。有了自己的键,皮肤只需声明一次"speed button 常态扁平",到处生效。

内建主题把 `TyButton, TySpeedButton, TyGlyphContainerButton, TyRibbonAppMenu, TyButtonGroup, TyUpDown` 写在同一组规则里(含 `.primary` / `.danger` / `.ghost` 变体与全部伪类),所以**解析值一个没变**;变的是你现在能只改其中一个。

```pascal
uses tyControls.IconFont, tyControls.GlyphButtons;
```

---

## 3. 属性表

### 3.1 共有（`TTyGlyphButtonBase` 新增，三者都有）

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `IconFont` | `TTyIconFont` | `nil` | 字形来源。用 `FreeNotification`/`Notification` 挂钩：所指字体被释放时自动置 `nil`，不留悬垂引用。 |
| `GlyphName` | `string` | `''` | 要绘制的字形名（对应 IconFont 的 `Glyphs` 映射，如 `save`）。为空或未映射 → 不画字形，标题占满内容区（退化为普通按钮）。 |
| `GlyphSize` | `Integer` | `0` | 字形边长（**逻辑像素**，随 PPI 经 `TTyPainter.Scale` 缩放）。`0` = 自动：堆叠布局（`glTop` / `glBottom`）取内容区短边，并排布局（`glLeft` / `glRight`）取内容区高度。 |
| `GlyphColor` | `TTyColor` | `TyGlyphButtonColorDefault` | 字形填充色。默认哨兵值 `TyGlyphButtonColorDefault`（即全透明 `$00000000`，表示“**用主题**”）→ 取 `TextColor`，与标题同色；设为其他值则覆盖。 |
| `Images` | `TTyImageCollection` | `nil` | **跨平台图像**字形源（一组 BGRA 图标）。同样用 `FreeNotification` 置 `nil`。 |
| `ImageName` | `string` | `''` | 要画的图标名。`Images` + `ImageName` **同时**设定时**优先于** `IconFont`/`GlyphName`（图标按 `GlyphColor`/`TextColor` 染色）；与系统图标字体不同，它在每个 OS 上渲染一致。为空则回落到图标字体。 |
| `GlyphLayout` | `TTyGlyphLayout` | `glLeft` | 字形相对标题的朝向（见下表）。**以前是 protected**——想要非默认朝向必须继承一个子类；现在设计器里直接选。`TTyGlyphContainerButton` 重新声明为 `default glTop`（与它构造函数一致，免得每个 `.lfm` 都写一行）。 |
| `Spacing` | `Integer` | `-1` | 字形与标题之间的间距，单位**逻辑像素**。`-1`（默认）= 交给主题令牌 `--glyph-button-gap`；`>= 0` = 本控件用这个字面像素值。 |
| `ShowCaption` | `Boolean` | `True` | `False` 让按钮**只显示图标**：字形在整个内容盒里两轴居中，完全不画标题。**解析不出字形的按钮（既无 `Images`+`ImageName` 也无 `IconFont`+`GlyphName`）不受影响，照旧显示标题**——没有东西能顶替标题的位置，藏掉它只会画出一个空盒子。`ShowCaption` 只做"拿图标换标题"这一件事。 |

> **`ShowCaption` 与工具条的关系。** [`TTyToolBar.ShowCaptions`](toolbar.md#31-ttytoolbar-自有-published-属性) 通过
> `AdoptShowCaption` 把自己的值当作**容器默认值**下发给每个工具项；**一旦宿主自己写过这个按钮的
> `ShowCaption`，容器就不再动它**（哪怕写进去的值恰好和容器的一样）。容器在工具项加入、以及它自己的
> 标志变化时都会重下发一遍，无条件覆盖会静默抹掉逐按钮的选择——这正是 `Flat` 从前覆写 `StyleClass`
> 踩过的坑。
>
> 属性声明上**刻意不写 `default True`**，改用 `stored`：显式写下的 `ShowCaption := True` 必须能过一趟
> `.lfm` 往返，而 `default True` 恰好会把这一种情况省掉不写——按钮重新加载后就成了"没人写过"，容器
> 会拿自己的值盖上去。

**`TTyGlyphLayout` 的四个值**（对应 LCL `TButtonLayout`，`buttons.pp:42-48`）：

| 值 | 字形位置 | 典型用途 |
|------|----------|----------|
| `glLeft` | 图标在标题**左**侧 | 默认；紧凑命令按钮、工具栏 |
| `glTop` | 图标在标题**上**方 | ribbon 瓷砖（`TTyGlyphContainerButton` 的默认值） |
| `glRight` | 图标在标题**右**侧 | 'more ▾' / 展开箭头那种尾随图标 |
| `glBottom` | 图标在标题**下**方 | 标题在上、图标在下的瓷砖 |

> `glRight` / `glBottom` 是**追加**在枚举末尾的，`glLeft` / `glTop` 的序数没变——已有的 `.lfm` 读回来仍是原来那个成员。

> **`Spacing` 与 LCL 的分歧。** LCL 的 `TCustomSpeedButton.Spacing`（`buttons.pp:433`，`default 4`）把 `-1`
> 解释为"把图标 + 标题整体居中"，这里 `-1` 解释为"**主题说了算**"（`--glyph-button-gap`）。移植过来的按钮
> 若 `Spacing` 是 `4` 这类具体值，得到的就是字面 4 逻辑像素，行为一致。

**共有 public 方法：**

| 方法 | 返回 | 说明 |
|------|------|------|
| `CanShowGlyph` | `Boolean` | 这个按钮此刻是否真的会画图标（`Images` + `ImageName`，或 `IconFont` + `GlyphName`）。以前叫 `HasGlyphSource` 且是 protected，外部布局代码（决定工具条行高、对齐一列标题）够不着。对应 LCL 的 `TCustomBitBtn.CanShowGlyph`（`buttons.pp:214`，public）。**LCL 的签名带一个 `AWithShowMode` 参数，服务于它的 `Application.ShowButtonGlyphs` 机制；本库没有那套机制，所以参数是省略掉的，而不是收下再忽略。** |

### 3.2 `TTySpeedButton` 额外新增

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `GroupIndex` | `Integer` | `0` | `0` = 普通按钮（`Click` 仅触发 `OnClick`）。`>0` 时表现为**单选**：按下自己并抬起**同 Parent、同 GroupIndex** 的其它 `TTySpeedButton`。**代码里写 `Down := True` 与用户点击等效**——互斥逻辑在 `SetDown` 里，不是只在 `Click` 里（与 LCL 的 `SetDown → UpdateExclusive` 一致），所以"恢复上次保存的工具模式"这类代码不会留下一组全按下的按钮。 |
| `AllowAllUp` | `Boolean` | `False` | `True` 时，点击**已按下**的按钮会把它切回抬起（整组可全部抬起）；`False`（默认）时已按下的按钮再点保持按下（严格单选），代码写 `Down := False` 同样被拒绝——只有分组自己的换选能放开它。**把它从 `True` 改回 `False` 会当场重建约束**：若此时整组无人按下，就按下正在配置的这一个（否则会留下一个"什么都没选"的单选组，直到用户碰巧点一下）。 |

**`TTySpeedButton` public 方法：**

| 方法 | 返回 | 说明 |
|------|------|------|
| `FindDownButton` | `TTySpeedButton` | 本按钮所在分组当前被按下的那一个；全部弹起时返回 `nil`，`GroupIndex = 0`（未分组）也返回 `nil`。以前只有"释放兄弟"的写侧、没有读侧，每个 app 都得自己写一遍带类型判断的 `Parent.Controls` 扫描。**作用域分歧要说清楚**：本实现只扫**直接父容器**，与 `UnpressSiblings`、与 LCL 的 `UpdateExclusive`（`include/speedbutton.inc:479-491`，`Parent.Broadcast`）一致；LCL 自己的 `FindDownButton` 却扫整个窗体（`include/speedbutton.inc:81-111`），因而可能返回一个它自己的分组逻辑根本不管的按钮。 |

### 3.3 继承自 [[TTyButton]] 的常用成员

`Caption`、`Down`（`:selected` 常驻选中态）、`Default`、`Cancel`、`ModalResult`、`ShowBadge`/`BadgeValue`/`BadgePosition`/`OnBadgeDisplay`（数字角标）、`AnimationsEnabled`（悬停背景渐变）、`Enabled`、`Font`、`Align`、`Anchors`、`StyleClass`、`Controller`、`OnClick` 等——细节见 [button.md](button.md)。

---

## 4. 绘制机制（DrawContent + 字形）

三者都**只重写** `DrawContent`（`TTySpeedButton` 另重写 `Click` / `SetDown`，各自重写 `Create` 设默认值），不触碰框架/状态/角标绘制路径：

1. 基类 `RenderTo`（继承自 TTyButton）先画框架、算内边距，再把已内缩的内容矩形交给 `DrawContent`。
2. `TTyGlyphButtonBase.DrawContent`：
   - 若 `IconFont = nil`、`GlyphName` 为空或内容区退化 → 直接 `inherited DrawContent`（居中标题，即普通按钮）。**这几条提前返回在 `ShowCaption` 之前，正是"没有图标的按钮永远不会被藏掉标题"的实现所在。**
   - 否则算出字形像素大小（显式 `GlyphSize` 优先，否则按布局自动适配），再按 `ShowCaption` 分两路切内容矩形：
     - `True`（默认）→ 纯函数 **`TyGlyphButtonSplit`** 切成 **字形矩形 + 标题矩形**（中间的间隔：`Spacing >= 0` 时用它，否则用主题令牌 `--glyph-button-gap`）；
     - `False` → 纯函数 **`TyGlyphButtonIconOnlyRect`** 给出两轴居中的字形矩形，标题矩形为空。
   - `IconFont.RenderGlyph(GlyphName, px, color)` 光栅化字形，居中合成进字形矩形，释放位图。
   - 最后 `inherited DrawContent(APainter, 标题矩形, AStyle)` 在剩余矩形里画标题（`ShowCaption = False`、空标题或无空间时跳过）。

### 纯函数 `TyGlyphButtonSplit`（可无头单测）

```pascal
procedure TyGlyphButtonSplit(const AContentRect: TRect; AGlyphPx, AGapPx: Integer;
  ALayout: TTyGlyphLayout; out AGlyphRect, ACaptionRect: TRect);
```

- `glLeft`：字形是靠左、垂直居中的 `AGlyphPx` 见方正方形；标题取其右侧（跨过 `AGapPx`）到内容区右边。
- `glRight`：镜像——字形靠右、垂直居中；标题取其左侧（跨过 `AGapPx`）到内容区左边。
- `glTop`：字形是靠上、水平居中的正方形；标题取其下方（跨过 `AGapPx`）到内容区底边。
- `glBottom`：镜像——字形靠下、水平居中；标题取其上方（跨过 `AGapPx`）到内容区顶边。
- `AGlyphPx <= 0`（无字形）→ 字形矩形为空，标题保留整个内容矩形。
- 字形被**钳制**在内容盒内，超大字形绝不会把标题挤成负宽/负高矩形。

例（内容区 100×40、字形 20px、间隔 6px、glyph-left）：字形 `(0,10)-(20,30)`，标题 `(26,0)-(100,40)`。

### 纯函数 `TyGlyphButtonIconOnlyRect`（可无头单测）

```pascal
function TyGlyphButtonIconOnlyRect(const AContentRect: TRect; AGlyphPx: Integer): TRect;
```

`ShowCaption = False` 时的字形矩形：内容区里**两轴居中**的 `AGlyphPx` 见方正方形，并钳制到内容盒的短边，
超大字形绝不会探出盒外。`AGlyphPx <= 0` 或内容区退化 → 返回内容区原点处的空矩形（绝不返回负矩形）。

> **它不是"标题矩形为空的 `TyGlyphButtonSplit`"。** `TyGlyphButtonSplit` 把字形**贴边**放
> （`glLeft` 靠左、`glTop` 靠上），正是因为后面跟着标题；标题一旦没有了，这个贴边就让图标歪在一侧、
> 原先放文字的地方空出一片，一排只显示图标的工具项看上去参差不齐。

---

## 5. 状态与主题

伪类状态与 [[TTyButton]] 完全一致：`:hover` / `:focus` / `:active` / `:disabled` / `:selected`（由 `Down` 驱动，`TTySpeedButton` 分组用它做单选高亮）。

内建主题让三者与 `TyButton` 共写规则，所以**默认外观就是一个普通按钮**。要改扁平/瓷砖观感，有两条路：

**① 写各自的 typeKey（推荐，一次配置到处生效）** —— 这正是它们各自成键的意义：

```css
/* 全库的 speed button 常态扁平,只在悬停/选中时显底 */
TySpeedButton           { background: alpha(--surface, 0); border-color: alpha(--border, 0); }
TySpeedButton:hover     { background: var(--surface-hover); }
TySpeedButton:selected  { background: var(--surface-active); }
/* ribbon 瓷砖同理,与对话框按钮互不相干 */
TyGlyphContainerButton  { background: alpha(--surface, 0); border-color: alpha(--border, 0); }
```

**② 挂 `StyleClass`（逐实例）** —— 内置的 `ghost` 变体对三个键都有定义：

```css
TyButton.ghost, TySpeedButton.ghost, TyGlyphContainerButton.ghost { background: alpha(--surface, 0); border-color: alpha(--border, 0); }
```

> ⚠️ 放在 [`TTyToolBar`](toolbar.md) 里的 speed button：工具条的 `Flat` 只在 `StyleClass` **为空**时写入
> `'ghost'`，所以宿主自己设的变体现在能保留下来。但 [`TTyToolBarEx`](toolbarex.md) 仍然整体覆写——
> 在溢出工具条上请走第 ① 条。
>
> 另外，`TTyGlyphButton` 没有自己的键（它解析 `TyButton`），所以改它的外观 = 改 `TyButton` = 改全库按钮。

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.Types,
  tyControls.IconFont, tyControls.GlyphButtons;

TyDefaultController.LoadTheme('themes/light.tycss');

// 1) 一个共享的图标字体源
var Icons: TTyIconFont;
Icons := TTyIconFont.Create(Self);
Icons.FontFile := 'assets/fontawesome.ttf';   // Windows 进程私有加载
Icons.FontFamily := 'Font Awesome 6 Free';
Icons.MapGlyph('save', $F0C7);
Icons.MapGlyph('open', $F07C);

// 2) 紧凑命令按钮:图标 + 文字并排
var Cmd: TTyGlyphButton;
Cmd := TTyGlyphButton.Create(Self);
Cmd.Parent := Self;
Cmd.SetBounds(24, 24, 96, 30);
Cmd.IconFont := Icons;
Cmd.GlyphName := 'save';
Cmd.Caption := '保存';
// Cmd.GlyphColor := TyRGB(40, 120, 220);   // 可选:覆盖字形色(默认与标题同色)

// 3) Ribbon 风格大按钮:大图标在上,文字在下
var Ribbon: TTyGlyphContainerButton;
Ribbon := TTyGlyphContainerButton.Create(Self);
Ribbon.Parent := Self;
Ribbon.SetBounds(140, 24, 72, 64);
Ribbon.IconFont := Icons;
Ribbon.GlyphName := 'open';
Ribbon.Caption := '打开';
Ribbon.GlyphSize := 28;   // 更大的字形(默认 24)

// 4) 工具栏分组切换(单选,像 TSpeedButton)
var i: Integer; Names: array[0..2] of string = ('save', 'open', 'save');
for i := 0 to 2 do
begin
  var Sp: TTySpeedButton;
  Sp := TTySpeedButton.Create(Self);
  Sp.Parent := Self;
  Sp.SetBounds(24 + i * 36, 108, 32, 32);
  Sp.IconFont := Icons;
  Sp.GlyphName := Names[i];
  Sp.StyleClass := 'ghost';   // 扁平观感
  Sp.GroupIndex := 1;         // 同组单选
end;
// 点击其中一个 -> 它 Down、同组其它抬起。设 AllowAllUp := True 可再点抬起。
```

---

## 7. 注意事项

- **字形像素需要真实的图标字体（真机）：** 渲染出的字形依赖已加载/安装的图标字体。请通过 [[TTyIconFont]] 的 `FontFile`（Windows 进程私有加载）或在系统安装对应字体族，并把 `FontFamily` 设为该族名。**无头/单元测试环境下没有字体，`RenderGlyph` 返回空透明位图——逻辑正确但画不出可见字形**，属预期；此时按钮仍正常显示标题与框架。
- **无字形即普通按钮：** `IconFont = nil` 或 `GlyphName` 未映射时，`DrawContent` 干净退化为居中标题的普通 [[TTyButton]]，绝不崩溃。
- **`GlyphColor` 哨兵：** 默认 `TyGlyphButtonColorDefault`（全透明 `$00000000`）表示“用主题 `TextColor`”，与标题同色；设为任意其它 `TTyColor`（`$AARRGGBB`）即覆盖。
- **尺寸随 PPI 缩放：** `GlyphSize` 与字形-标题间隔（`Spacing`，或它为 `-1` 时的主题令牌 `--glyph-button-gap`）都是逻辑像素，渲染时经 `TTyPainter.Scale` 按目标 DPI 缩放。
- **`TTySpeedButton` 分组：** 单选/互斥在 `SetDown` 里实现（同 Parent 扫描同 `GroupIndex` 的兄弟），因此**代码写 `Down := True`、直接调用 `Click`、用户点击**三条路都会触发分组逻辑；`Enabled = False` 时 `Click` 为空操作（不按下、不影响兄弟）。选中高亮复用 `Down` 的 `:selected` 状态。
- **`ShowCaption` 不会画出空按钮：** 无字形源时它不生效（标题照画）；这条规则让 `TTyToolBar.ShowCaptions` 那个与 LCL 对齐的 `False` 默认值不至于把现有应用里的纯文字工具条全部抹白。
- **基类不注册面板：** `TTyGlyphButtonBase` 仅作共享父类，不出现在组件面板;面板上注册的是三个具体类。

---

## 相关

- [[TTyButton]] —— 基类，提供框架、状态、悬停渐变、角标、Default/Cancel/ModalResult。
- [[TTyIconFont]] —— 图标字体源，`RenderGlyph` 光栅化字形。
- [[TTyCharImage]] —— 只显示单个字形的叶子图形控件（同样的字形合成机制）。
