# TTyToolBar + TTyToolButton + TTyToolSeparator

## 1. 概述

`TTyToolBar` 是 TyControls 库中的水平工具条控件，继承自 `TTyCustomControl`。它是一个 `csAcceptsControls` 容器，把作为其子控件（`Parent := ToolBar`）的按钮停靠成一条工具按钮带；默认 `Align := alTop` 紧贴窗体顶部。同单元还提供两个配套控件：

- **`TTyToolButton`**——工具条**自己的**按钮类（对标 LCL 的 `TToolButton`），六种 `Style`、`Down`/`Grouped` 单选组、`DropdownMenu` + 箭头区、`Wrap` 强制断行、`ImageIndex` 按下标取图标（见 [第 3.2 节](#32-ttytoolbutton工具按钮)）。工具条**并不要求**用它——任何 `TTyButton`（乃至编辑框、下拉框）都能当工具项——但只有它才带上面这些工具条语义。
- **`TTyToolSeparator`**——一条独立的分隔竖线控件（见 [第 3.4 节](#34-ttytoolseparator分隔线)）。它与 `TTyToolButton` 的 `tbsDivider` **画的是同一份墨迹**（同一个 typeKey、同一个绘制例程），二选一即可。

典型用途：文档编辑器 / 主窗口顶部的命令按钮栏。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ToolBar` |
| `GetStyleTypeKey` 返回值（`TTyToolBar`） | `'TyToolBar'` |
| `GetStyleTypeKey` 返回值（`TTyToolButton`） | `'TyButton'`；`Style` 为 `tbsSeparator` / `tbsDivider` 时是 `'TyToolSeparator'`（**随 `Style` 变**，见下） |
| `GetStyleTypeKey` 返回值（`TTyToolSeparator`） | `'TyToolSeparator'`（**自己的键**，不再借工具条的） |
| 基类（`TTyToolBar` / `TTyToolSeparator`） | `TTyCustomControl`（继承自 `TCustomControl`） |
| 基类（`TTyToolButton`） | `TTyGlyphButtonBase` → `TTyButton` → `TTyCustomControl` |
| 默认尺寸（`TTyToolBar`） | 300 × 30（逻辑像素） |
| 默认尺寸（`TTyToolButton`） | 23 × 22（= LCL `TToolButton.GetControlClassDefaultSize`；高走密度轴。放上工具条后高度由 `ButtonHeight` 接管，所以这个尺寸只决定**不在**工具条上时的样子） |
| 默认尺寸（`TTyToolSeparator`） | 8 × 24（宽固定 8；高走密度轴 `TyDensityHeight(…, 24)`，现代密度下更高） |

| typeKey | 画什么 |
|---|---|
| `TyToolBar` | 工具条：`background` 铺满整块（图片主题下叠在照片上），`border-color` + `border-width` 画**底部一条 hairline**（无四周边框） |
| `TyToolSeparator` | 分隔线：`background` 用来与工具条底色无缝衔接，`border-color` 是那条 1px 竖线的颜色 |
| `TyButton` | 工具按钮：整套按钮外框/状态/焦点环都从这里来 |

> **`TTyToolButton` 为什么没有自己的 typeKey？** 它**就是**一个按钮，扁平外观由工具条发下来的
> `'ghost'` StyleClass 负责（`Flat = True`，也正是 LCL `TToolBar.Flat` 唯一拉的那根杆），所以皮肤要单独
> 调工具按钮写 `TyButton.ghost` 即可，不必新增一个键、也不必给 15 套内建主题各补一条规则。
> 这一点与 `TTySpeedButton` 不同：速度按钮**会**用在工具条外面，没人给它 `'ghost'`，所以它必须有自己的键。
>
> **但 `tbsSeparator` / `tbsDivider` 例外**：它们画的是分隔线的墨迹，于是解析 `'TyToolSeparator'`——
> 皮肤调暗分隔线时，独立的分隔控件和作为按钮样式的分隔线**一起**变暗，主题作者不用记住两处拼写。
> 这条由 `TToolButtonApiParityTest.TestSpaceHolderBorrowsTheSeparatorKey` 与逐像素的
> `TToolButtonSeparatorPixelTest.TestDividerInkMatchesTheSeparatorControl` 一起钉住。

> **分隔线从"借用"变成了"自有"。** 它画的是工具条不画的墨迹——一条内缩的竖线；借 `TyToolBar` 时，
> 这条竖线**必然**与工具条自己的底部 hairline 同色，主题想做"有边框的工具条 + 更淡的内嵌分隔线"
> 这种经典搭配根本做不到。现在两者可分开配。
> 内建主题里 `TyToolBar, TyToolSeparator` 仍共写一条规则（观感不变），要单独调分隔线请写
> `TyToolSeparator` 选择器——**别去改 `TyToolBar`**，那会连整条工具条的底色和底线一起改。

```pascal
uses tyControls.ToolBar, tyControls.Button;
```

---

## 3. 属性表

### 3.1 TTyToolBar 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `ButtonHeight` | `Integer` | 跟随密度轴 | 所有子按钮的统一逻辑高度；排布时每个子控件的高度被强制设为此值（`AlignControls` 中 `SetBounds(..., bh)`）。**未显式赋值时跟随主题的 `--control-height`**（经典 24 / 现代 38），一经写入即固定并写进 `.lfm`。改值触发 `Relayout`。 |
| `ButtonWidth` | `Integer` | 未设 = 无下限 | LCL 语义的**宽度下限**，不是统一宽度：比它窄的**真按钮**（`tbsButton` / `tbsCheck` / `tbsDropDown`——LCL 自己的样式集合，**不含** `tbsButtonDrop`）按此宽度排布，比它宽的保留自己的宽度。`AutoSize` 的按钮、占位样式、非 `TTyToolButton` 子控件一概不碰——四条豁免全是 LCL 的（`toolbar.inc` `CalculatePosition`）。**调低下限会还原各按钮自己的宽度**：工具条记着自己"借"出去的宽度（`FLentImages` 模式的宽度版），所以设计器里试一个值不会把 `.lfm` 里的宽度棘轮掉。与 `ButtonHeight` 同单位、同 `stored` 机制（写过才存）。**与 LCL 的差异**：LCL 未设时是主题化的 ~23px 下限（它的按钮宽度本来就逐次从内容推导）；这里按钮宽度是 `.lfm` 拥有的**设计值**，默认下限会悄悄改宽现存的每一条工具条，故未设 = 完全没有下限（读回 0）。 |
| `ButtonSpacing` | `Integer` | `2` | 相邻工具项之间的水平间距（换行时也用作行间距）。改值触发 `Relayout`。 |
| `DropDownWidth` | `Integer` | `0`（跟随令牌） | 两种下拉样式箭头区的**逻辑宽度**。`0`（默认）跟随主题令牌 `--drop-arrow-width`（全库尾随箭头共用的那一个）；正值则**钉住本条工具按钮**的箭头区——画出来的箭头区、`tbsDropDown` 的命中测试、首选宽度三者读的是**同一个**仲裁值（`DropArrowLogicalWidth`），一起动。这是标签条 `ImagesWidth` 的既有约定：0 = 跟令牌，非零 = 钉住。LCL 把 `tbsButtonDrop` 的箭头也钥在同一属性上（其 `ButtonDropWidth` 推导），这里两种样式读同一个值，有测试钉住。**碰不到**恰好摆在工具条上的 `TTyDropDownButton` / `TTyMenuButton`——那些不是工具按钮，箭头仍跟令牌。负值按 0 处理。 |
| `List` | `Boolean` | `True`（**与 LCL 反向**） | LCL 的列表模式：`True` 图标在标题**旁边**（`glLeft`），`False` 图标叠在标题**上方**（`glTop`）。只下发给 `TTyToolButton`（LCL 的 `List` 也只够得着它的 `FButtons`），走 `AdoptGlyphLayout`——宿主自己写过 `GlyphLayout` 的工具项永远不碰（`AdoptShowCaption` 的同一契约）。**默认值反向是有意的**（先例：组合框反向的 pick-only 默认）：本库自动尺寸的图标按内容盒推导（`MeasureGlyphSlot`），叠放布局 + 自动 `GlyphSize` 会占满行高、把标题挤成零高——若默认 `False`，`ShowCaptions=True` 会在每个图标工具上**一个标题都画不出来**，按构造就是说谎属性。要用 `False`（叠放）请**同时设显式 `GlyphSize`**：高度下限（`MeasureContentHeight`）会把行撑高给标题留位，与 ribbon 大按钮一直以来的做法相同。另一处差异顺带记录：LCL 只在列表模式下承认逐按钮的 `ShowCaption=False`（"allow hide caption only in list mode"），这里**两种模式都承认**——既有机制本来就更强。 |
| `Indent` | `Integer` | `4` | 工具条**前缘**（每行第一项之前）的留白，仅此而已。改值触发 `Relayout`。**曾经它还兼任上下内边距**，工具条自动增高时算的是 `Indent*2 + rows`，于是 `Indent := 24`（在 LCL 里是再普通不过的取值，用来给一个 logo 或前置标签让位）会静悄悄地把工具条撑高 48px、把所有工具往下推 24px——那不是任何 LCL 窗体设这个值时想要的。纵向留白现在是它自己的值（主题令牌 `--toolbar-pad-y`，缺省 4 = 原来 `Indent` 的缺省），两个旋钮各走各的。与 LCL 仍有一处不同：`TToolBar.Indent` 的缺省是 1，这里是 4。这一点是**有意保留**的——`default` 指令决定的是所有省略了该值的既有 `.lfm` 怎么被读回，改掉它等于给现存的每一条工具条重新缩进。从 LCL 移植、依赖缺省 1 的窗体请显式写 `Indent := 1`。 |
| `Wrapable` | `Boolean` | `True` | 为 `True` 时，一行放不下的工具项自动折到下一行；`Align in [alTop, alBottom]` 时工具条随行数自动增高。改值触发 `Relayout`。**这只管"宽度不够时自动换行"这一条规则**，与"某一项强制另起一行"是两回事——后者走排布函数的 `ABreakBefore` 参数（见 [第 5.1 节](#51-排布函数-tytoolbarlayout)），且**两种模式下都生效**。 |
| `ShowCaptions` | `Boolean` | `False` | 与 LCL 一致：`False`（默认）让工具项**只显示图标**，`True` 才画标题。它下发到每个**能画图标**的子控件（`TTyGlyphButtonBase` 一族：`TTyGlyphButton` / `TTySpeedButton` / `TTyGlyphContainerButton`），走 `AdoptShowCaption`——对已被宿主自己写过 `ShowCaption` 的工具项是空操作。普通 `TTyButton` 没有图标模型，不受影响；**解析不出图标的工具项保留标题**（否则画出来是个空盒子），所以 `False` 这个默认值不会把现有的纯文字工具条抹白。改值触发 `Relayout`。 |
| `Flat` | `Boolean` | `True` | 为 `True` 时，工具条把子 `TTyButton` 的 `StyleClass` 设为 `'ghost'`（平面外观）——但**只在它还是空串时**；为 `False` 时只把 `'ghost'` 改回 `''`。宿主自己写的 `StyleClass := 'primary'` 会保留下来。改值触发 `Relayout`。 |
| `Images` | `TTyImageCollection` | `nil` | 工具项的图标来源：**没有自己 `Images` 的子图标按钮由工具条把这个集合借给它**，于是工具项只需设 `ImageName`。已经自带集合的工具项不受影响——工具条只管自己借出去的那一份引用（重新指向或收回）。用 `FreeNotification` 挂钩，集合被释放时连同"借出标记"一起置 `nil`。改值触发 `Relayout`。 |
| `Align` | `TAlign` | `alTop` | 停靠方式（**默认 `alTop`**，与原生工具条一致）。 |
| `Anchors` | `TAnchors` | — | 锚点布局（继承）。 |

> **`Images` 是 `TTyImageCollection`，不是 LCL 的 `TImageList`。** 本库所有图标都出自按名字取用的 BGRA
> 集合（见 [imagecollection.md](imagecollection.md)），没有任何一处从按下标取用的 `TImageList` 渲染——
> 所以这里放一个 `TImageList` 无论宿主怎么赋值都到不了工具按钮。这正是它从前"存下来什么也不做"的原因。
>
> 工具条**借**而不**夺**：`ApplyToolProperties` 只写那些 `Images = nil` 或仍持有工具条上次借出那份集合的
> 工具项，自带集合的工具项永远不动。它在三个时机跑——两个 setter，以及工具项加入工具条时
> （`InsertControl`）——**刻意不放在排布过程里**：排布一次 resize 要跑很多遍，那样反复覆写宿主可见的状态，
> 正是 `Flat` 从前覆写 `StyleClass` 会出事的原因。

#### 条上有意**没有**做的成员

| LCL 成员 | 为什么没有 |
|---|---|
| `HotImages` / `DisabledImages` | LCL 用它们在悬停 / 禁用时**换一份图集**（同一个 `ImageIndex` 打到另一个 `TImageList` 上），经典用途是"彩色图标禁用时换灰度版"。本库不带它们，两个原因：**其一**，本库的图形管线把集合里的每张图**染成当前状态解析出的 `TextColor`**（`TyTintBitmapAlpha` 整体替换 RGB、保留 alpha）——"每个状态换个颜色处理"这份工作**本来就是主题的**，每套皮肤经 `:hover` / `:disabled` 规则自己定；换进来的图照样会被同样染色，第二份集合唯一能加的只有"每个状态换个**形状**"。**其二**，为这点残余开两个属性，等于在主题的状态模型旁边再立一套按条配置的图像状态模型，还带着按名字的静默回退（备选集合里缺某个名字就显示基础图标）——一个"有时生效"的表面。真要按状态换形状，正确的缝是在 `TTyGlyphButtonBase` 上加一个受保护的虚 glyph 源解析器、让它的 `DrawContent` 咨询——先把那个建出来，再删 `TToolBarMembersApiParityTest.TestHotAndDisabledImagesAreDeliberatelyAbsent` 里的断言；不要放宽它。 |

### 3.1.1 TTyToolBar 的按钮列表（LCL 的 `Buttons[]`）

| 成员 | 类型 | 说明 |
|------|------|------|
| `ButtonCount` | `Integer`（只读） | 工具条的 **`TTyToolButton` 子控件**个数 |
| `Buttons[Index]` | `TTyToolButton`（只读） | 按子控件顺序的第 `Index` 个工具按钮；越界返回 `nil`（不抛异常） |
| `IndexOfButton(B)` | `Integer` | `B` 在 `Buttons[]` 里的下标，不是本工具条的返回 `-1` |

> **只装 `TTyToolButton`，别的都不算。** 这与 LCL 一致：`TToolBar.FButtons` 里只有 `TToolButton`。
> 于是夹在两个单选按钮之间的普通 `TTyButton`、编辑框或 `TTyToolSeparator` **不会把它们的单选组切断**
> ——它们根本不在这个下标空间里。`Grouped` 与 `TTyToolButton.Index` 说的都是这个下标空间。

### 3.2 TTyToolButton（工具按钮）

对标 LCL 的 `TToolButton`（`comctrls.pp:2103`）。它和工具条**放在同一个单元里**，理由和 LCL 一样：
`Grouped`（"我和 bar 上相邻的成组按钮是一组"）、`Wrap`（"bar 的行在我之后断开"）、`Index`（"我在 bar 的按钮表里的位置"）
这三个属性的定义**都以工具条为参照**，放在别的单元里既够不着工具条、工具条也够不着它（循环引用）。

因为继承自 `TTyGlyphButtonBase`，它**白拿**了整套图标机制：`Images` / `ImageName` / `IconFont` / `GlyphName` /
`GlyphSize` / `GlyphColor` / `GlyphLayout` / `Spacing` / `ShowCaption` / `AutoSize`（见 [glyphbuttons.md](glyphbuttons.md)），
工具条现成的"借出 Images / 下发 ShowCaptions"也就直接对它生效，没有一行新代码。

> **`GlyphLayout` 在本类上改了存储方式**（语义不变）：工具条的 `List` 会把布局**下发**给从没被宿主写过
> `GlyphLayout` 的工具按钮（`AdoptGlyphLayout`，`AdoptShowCaption` 的同一契约），所以下发来的布局**不许**
> 写进 `.lfm`——否则重载后经 setter 变成"宿主写过"，`List` 从此再也动不了它。于是本类重声明
> `property GlyphLayout stored FGlyphLayoutExplicit nodefault`：写过才存，且去掉基类的 `default glLeft`
> （不去掉的话，`List=False` 的条上显式写 `glLeft` 恰好等于旧默认、会被 streamer 略过，round-trip 就丢）。
> 与 `ShowCaption` 的安排逐字相同，由 `TestGlyphLayoutStreamsOnlyWhenTheHostWroteIt` 钉住。

#### 3.2.1 `Style`——六种样式

```pascal
TTyToolButtonStyle = (tbsButton, tbsCheck, tbsDropDown, tbsSeparator, tbsDivider, tbsButtonDrop);
```

**成员名与顺序都照抄 LCL**，因为 `.lfm` 里枚举是按**标识符**存的：从 LCL 窗体里复制出来的 `Style = tbsDropDown` 得能原样读回来。
（同样的取舍状态栏早就做过——`TTyStatusPanelStyle` 就是 LCL 的 `psText` / `psOwnerDraw` 原样。）
代价是：**同时 `uses ComCtrls` 和本单元**的窗体里，LCL 的 `TToolButtonStyle` 成员会被这里的遮住，需要时写全名
`tyControls.ToolBar.tbsButton`。

| 成员 | 行为 | 点击 |
|------|------|------|
| `tbsButton` | 普通命令按钮（默认值） | 触发 `OnClick` |
| `tbsCheck` | 开关：点击翻转 `Down`；可用 `Grouped` 组成单选组 | 先翻 `Down`，再触发 `OnClick` |
| `tbsDropDown` | **分裂**：主区 + 右侧箭头区，两个独立命中区，中间一条 1px 分隔线 | 主区 → `OnClick`；箭头区 → 弹 `DropdownMenu`，**没有菜单时**才触发 `OnArrowClick`，且**永远不**触发主区的 `OnClick` |
| `tbsSeparator` | 占位：占 8 逻辑像素的宽度，**不画任何墨迹** | 吞掉（不是控件表面） |
| `tbsDivider` | 占位 + 一条 1px 竖线，占 5 逻辑像素 | 吞掉 |
| `tbsButtonDrop` | 按钮 + **附着**的箭头：只有一个命中区，没有分隔线 | 任意位置点击都弹 `DropdownMenu`，**并且**照常触发 `OnClick`；`OnArrowClick` 在这个样式上够不着 |

改成 `tbsSeparator` / `tbsDivider` 时按钮会被**重设宽度**为 8 / 5（`TyToolSeparatorWidth` / `TyToolDividerWidth`，
即 LCL 的 `cDefSeparatorWidth` / `cDefDividerWidth`），与 LCL `SetStyle` 一致。

> **流式化期间（`csLoading`）不重设。** `Width` 声明在 `TControl` 上、`Style` 声明在本类上，所以 `.lfm` 里
> **`Width` 写在前、`Style` 写在后**。若无条件重设，设计器里被加宽到 20 的分隔位会在**每一次加载**时被它自己的
> `Style` 行掰回 8，设计值永远存不下来。交互式改 `Style` 照旧会吸附到 8 / 5——那正是这个属性在设计器里好用的原因。
> 由 `TToolButtonTest.TestStreamedWidthOutranksTheStylesDefault` 钉住。

> **箭头区有多宽？** 默认走主题度量 `--drop-arrow-width`（缺省 18px）——这正是 `TTyMenuButton` 用的
> 同一个度量，所以全库的下拉箭头宽度是一个数、换肤一起动。宿主工具条可以用 `DropDownWidth`（LCL 把
> 这个属性就放在**工具条**上）钉住本条的箭头区：`0`（默认）= 令牌做主，正值 = 本条工具按钮统一用这个
> 逻辑宽度——标签条 `ImagesWidth` 的既有约定。三处读的是同一个仲裁值（按钮的 `DropArrowLogicalWidth`）：
> 画出来的箭头区、命中测试、首选宽度，所以钉住之后三者一起动。
> 命中测试与绘制走的是**同一个** `TyDropArrowHit`（`tyControls.DropButtons`）——和 `TTyDropDownButton` 共用一条规则，
> 两个控件不可能对"箭头区从哪开始"产生分歧。
>
> **已知偏差（与 `TTyDropDownButton` 同源，非本类新引入）：** 命中区是从控件**右边缘**往回量的
> （`TyDropArrowHit(X, Width, …)`），而箭头是画在**内容区**里的——内容区已经被主题的 `padding`
> （`--pad-button`，缺省 6px）内缩过。于是两者错开约一个右内边距：画出来的箭头最左边那几像素点下去会走主区，
> 而最右边紧贴边框的那几像素虽然没画东西却算箭头区。修法是命中区也按解析出的右内边距内缩一次
> （`tyControls.DropButtons.pas` 的 `TTyDropDownButton.IsInArrowZone` 与本类的 `IsInArrowZone` 一起改，
> 两处必须同时改，否则就把共用那条规则的意义破坏了）。本轮**没有**改，因为 `DropButtons` 不在本次改动范围内，
> 单改一边会让两个控件对"箭头区从哪开始"产生分歧。

#### 3.2.2 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Style` | `TTyToolButtonStyle` | `tbsButton` | 见上表 |
| `Grouped` | `Boolean` | `False` | **相邻**单选组：与 bar 上**紧挨着**的、同样 `Grouped` 且为 `tbsCheck` 的按钮组成一个互斥组（组内的占位样式 `tbsSeparator` / `tbsDivider` **不切断**这个连续段，其它任何东西都切断）。按下一个会弹起同组其余的。 |
| `AllowAllUp` | `Boolean` | `False` | 允许点击已按下的成员把它弹起，让整组都是弹起状态。它是**组的**属性不是按钮的：LCL 问的是"组里**有没有**成员开了这个"。把它从 `True` 改回 `False` 时，若整组当前都是弹起的，会把**正在配置的这个**按下——否则会留下一个"互斥但没有选中项"的组。 |
| `Wrap` | `Boolean` | `False` | LCL 的**后置**断行：bar 的这一行在本按钮**之后**结束，下一个按钮另起一行。见 [第 3.2.4 节](#324-wrap两处与-lcl-的差异) |
| `ImageIndex` | `Integer` | `-1` | 按**位置**取图标（而不是按名字）。见 [第 3.2.3 节](#323-imageindex是-imagename-的另一种拼法) |
| `DropdownMenu` | `TTyPopupMenu` | `nil` | `tbsDropDown` 箭头区 / `tbsButtonDrop` 整面弹出的主题化菜单。LCL 写的是 `TPopupMenu`；这里收窄成它的后代 `TTyPopupMenu`（本库另外两个下拉按钮也是这个类型），否则会在自绘工具条中间弹出一个系统原生菜单。`FreeNotification` 跟踪。 |
| `OnArrowClick` | `TNotifyEvent` | — | `tbsDropDown` 箭头区被点击**且没有弹出菜单**时触发（照抄 LCL 的抑制规则：这个事件是菜单的**替代品**，不是菜单**前面**的钩子）。要在菜单弹出**之前**跑代码（比如现场构建菜单），用 `TTyDropDownButton.OnDropDown`。 |
| `Down` | `Boolean` | `False` | 继承自 `TTyButton`。在 `tbsCheck` 上它就是点击翻转的"选中"状态，并由 `Grouped` 维持互斥；其它样式上只是 `:selected` 外观。 |
| `TabStop` | `Boolean` | `False` | 工具按钮**不取焦点**——工具条的意义就是点它之后光标还留在编辑器里。与 `TTySpeedButton` 同。 |

#### 只读公开成员

| 成员 | 说明 |
|------|------|
| `Index` | 本按钮在宿主工具条 `Buttons[]` 里的下标；不在工具条上时 `-1`（LCL 同名同义） |
| `ToolBar` | 宿主工具条，或 `nil` |
| `PointInArrow(X, Y)` | LCL 同名同签名：`(X, Y)` 是否落在箭头区内——**只有** `tbsDropDown` 有箭头区 |
| `ArrowClick` | 触发 `OnArrowClick`（`virtual`，与 LCL 同） |
| `CheckMenuDropdown` | 有菜单就弹；返回值 = "**会不会**弹"，所以无窗口的调用方（测试）也能拿到这个决定。**差异**：LCL 还要求 `DropdownMenu.AutoPopup`、并接受用 `MenuItem` 代替；本库不看 `AutoPopup`（另外两个下拉按钮也不看），于是全库一条规则——"挂了菜单就会弹"。 |
| `GetGroupBounds(out AStart, AEnd)` | 本按钮所在单选组在 `Buttons[]` 下标空间里的 `[AStart..AEnd]`；不是"成组的 `tbsCheck` 且在 bar 上"时返回 `False`（`-1/-1`） |
| `GroupAllUpAllowed` | 整组是否可以全部弹起 |
| `RequestedPopup` | 上一次 `CheckMenuDropdown` 是否有菜单可弹（测试缝） |
| `DropDownForTest` | 无 GUI 地跑一遍下拉决定（测试缝，镜像 `TTyDropDownButton.DropDownForTest`） |

#### 3.2.3 `ImageIndex`：是 `ImageName` 的另一种拼法

这个按钮上**只有一份**图标状态，就是继承来的 `ImageName`：

- **写** `ImageIndex` → 用 `TTyImageCollection.NameOf`（**插入顺序**）把位置换成名字，存进 `ImageName`；
- **读** `ImageIndex` → 用 `IndexOf` 报出当前 `ImageName` 的位置。

所以两者是**同一件事的两种拼法**，没有"谁优先"这种需要记的规则——最后写的那个赢，因为没有别的东西可赢。
`-1` 表示"不按下标取图标"，显式写 `-1` 会清掉图标（与 LCL 同）；**只用过 `ImageName` 的按钮永远不会被它碰**。

集合还没到位时写的 `ImageIndex`（代码里先设值后设 `Parent`，或者 `.lfm`——读取器是把属性读完**之后**才修复组件引用的）
会被**记住**，并在集合到位的那一刻兑现。兑现点正好两个，各自覆盖对方够不着的情形：

- **工具条把集合交过来时**（`TTyToolBar.ApplyToolProperties`）——工具**加入**已有集合的 bar，以及已有工具的 bar **被赋予**集合，两种顺序都在这里；
- **`Loaded`**——工具条够不着的那一种：按钮在 `.lfm` 里**自带** `Images`。这个组件引用是属性读完之后才修复的，而那次赋值走的是基类的私有 setter，本类挂不上钩。

> **与 LCL 的差异（有意）：** LCL 把下标原样存着、到绘制时才查表；这里**名字**才是权威。
> 于是重排集合**不会**悄悄改掉一个已有按钮画的图标，改掉的是它 `ImageIndex` 读回来的值。
>
> **为什么下标是打到 `TTyImageCollection`（按名字取用的集合）上的？** 因为那是工具条唯一能给出的下标空间：
> `TTyToolBar.Images` 早就是 `TTyImageCollection`（并且被测试钉死了类型），而 `TTyImageCollection` 本来就
> 公开 `Count` / `NameOf(i)` / `IndexOf(name)`，`FItems` 是**不排序**的 `TStringList`，即插入顺序稳定。
> 在 bar 上再挂一个 `TTyVirtualImageList`（标签条那边的做法）会让一个控件有两个图标源，那才是本轮明令禁止的"含义重叠"。

#### 3.2.4 `Wrap`：两处与 LCL 的差异

`Wrap` 保持 LCL 的**后置**语义（"行在本按钮**之后**断开"），这样从 LCL 复制来的 `.lfm` 说什么就是什么。
工具条内部再把它换算成排布函数的**前置**标志，换算就是文档里那一行，并且它本身就是一个函数：

```pascal
function TyToolWrapToBreakBefore(const AWrapAfter: array of Boolean): TBooleanDynArray;
// breakBefore[i] := (i > 0) and wrapAfter[i - 1]
```

| | LCL | 本库 |
|---|---|---|
| `Wrapable = True` 时读不读 `Wrap` | **不读**（`toolbar.inc:1003` 只在 `not Wrapable` 时读） | **读**。宿主已经明说要断在哪里，照办不算意外；跟着 LCL 禁掉的话，这个能力在默认工具条上永远够不着（`Wrapable` 缺省是 `True`） |
| 最后一个按钮上的 `Wrap` | 照样把行数加一，于是报出**一行什么都没有**的高度 | **丢弃**。工具条高度是直接按行数算的，那一行会变成看得见的空白 |

另外两点：**不可见**的工具项不参与排布，所以它没有"行"可以结束，它的 `Wrap` 不生效；
`TTyToolBarEx` 在**溢出模式**（`Wrapable = False`）下整份重写了排布、按构造只有一行，`Wrap` 在那条路上无从生效
（它的换行模式原样交回基类，`Wrap` 照常有效）。

#### 3.2.5 有意**没有**做的

| LCL 成员 | 为什么没有 |
|---|---|
| `Marked` | **LCL 自己就是个说谎属性**：`FMarked` 存下来、`Invalidate` 一下，然后 `Paint` 和 `GetButtonDrawDetail` **谁都不读它**。照抄属性表正是把缺陷一起移植过来的方式，而本轮存在的意义就是清掉这一类缺陷。由 `TestLclsLyingPropertiesAreNotCopied` 钉住"不许 published"。**要做就先把绘制做出来再删那一行断言，不要放宽它。** |
| `Indeterminate` | 同上，同样是存了不画。 |
| `GroupIndex` | **有意不与 `Grouped` 并存**。见下。 |
| `MenuItem` | 纯粹是范围问题（不是说谎）：它从一个 `TMenuItem` 抄 caption/enabled/image/checked 再弹出它，等于在 `DropdownMenu` 之上再叠一套菜单模型。本库的菜单是 `TTyPopupMenu`，要接得单独设计。 |

> **`Grouped` 与 `GroupIndex`：一个类只能有一种分组模型。**
> LCL 的 `TToolButton` 按**相邻**分组（`Grouped: Boolean`）；本库的 `TTySpeedButton` 按**编号**分组（`GroupIndex: Integer`）。
> 两者回答的是同一个问题，同时 published 会让宿主设下一个"相邻规则根本不看"的 `GroupIndex`——按构造就是个说谎属性。
> 所以：**`TTyToolButton` 取 `Grouped`**（它移植的就是那个 LCL 类），**`TTySpeedButton` 保留 `GroupIndex`**，
> 需要编号分组时就用速度按钮。两者**可以精确互译**：把每一段极大的 `Grouped` 连续段各给一个 `GroupIndex` 即可。
> 这条决定由 `TToolButtonApiParityTest.TestGroupedIsTheOneGroupingModel` 双向钉住（`TTyToolButton` 上没有
> `GroupIndex`，`TTySpeedButton` 上没有 `Grouped`）。

### 3.3 继承的通用成员

`TTyToolBar` 与 `TTyToolSeparator` 均继承自 `TTyCustomControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分。 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器。 |

> `TTyToolBar` 未跟踪 `FHover` / `FPressed` 等交互状态字段——它是纯容器，仅绘制背景与底部发丝线，本身不参与 `:hover` / `:active`。私有布局字段（`FButtonHeight` / `FButtonSpacing` / `FIndent` / `FWrapable` / `FShowCaptions` / `FFlat` / `FImages` / `FInLayout`）由上表 published 属性驱动，`FInLayout` 是 `AlignControls` 的重入守卫。

### 3.4 TTyToolSeparator（分隔线）

`TTyToolSeparator` 是一条平凡的竖线控件，把它 `Parent := ToolBar` 即可作为普通工具项参与排布（占据一个 8px 宽的格位，在中央绘制 1px 竖线）。它自身**没有专有 published 属性**，仅 published 继承来的三项：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Align` | `TAlign` | `alNone` | 停靠方式（继承）。 |
| `StyleClass` | `string` | `''` | CSS 类名。 |
| `Controller` | `TTyStyleController` | `nil` | 样式控制器。 |

竖线颜色取 `TyToolSeparator` 样式的 `BorderColor`，竖线上下各内缩 3 逻辑像素（`P.Scale(3)`）；同一样式的 `background` 用于铺底，好让它与所在工具条无缝衔接。

---

## 4. 事件

### 4.1 `OnPaintButton`——逐按钮自绘（LCL 同名同义）

```pascal
TTyToolBarOnPaintButton = procedure(Sender: TTyToolButton; AState: Integer) of object;
property OnPaintButton: TTyToolBarOnPaintButton;
```

挂上它之后，本条**每个** `TTyToolButton` 的绘制被处理器**整体替换**——六种样式全部，分隔占位也在内（LCL 就是在样式分派**之前**调用并返回的），设计器里同样触发（LCL 也没有 `csDesigning` 门）。清掉处理器恢复主题默认绘制——所以只"赋一个什么都不画的处理器"会得到一个空白按钮（那正是"整体替换"的证明），而**不赋**它则一个像素都不变。

- **画布**是 `Sender.Canvas`（与 LCL 相同——按钮自己就是绘制表面，所以事件签名不必带画布参数，LCL 手写的处理器原样可用）。回调外层已套 `SaveHandleState` / `RestoreHandleState` 并按按钮裁剪，处理器画出界不会污染邻居。
- **`AState`** 是 LCL 的主题状态整数：`1` 常态 / `2` 悬停 / `3` 按下（指针仍在按钮上）/ `4` 禁用 / `5` 选中（`Down`）/ `6` 选中+悬停。禁用**压过**选中（LCL 先判 `Enabled`）。换算是纯函数 `TyToolButtonPaintState`，无窗口可测。
- **差异（有意）**：LCL 在 `Flat = False` 时把状态 1 / 4 谎报成 2（Win32 "常抬起"渲染补偿，会把禁用按钮说成悬停）；这里 `AState` 永远是真实状态，`Flat` 只管它本来那根杆（ghost `StyleClass`）。由 `TToolBarPaintButtonTest.TestFlatDoesNotDistortTheState` 钉住。
- 它是 **Paint 路径**的钩子（与 LCL 一致）：走 `RenderTo` 的离屏渲染（golden 等）不经过它。

除此之外 `TTyToolBar` 与 `TTyToolSeparator` **无别的自有事件**——工具条不发出 `OnChange` 之类的通知。用户交互（点击）发生在**子按钮**上，请挂接各个子 `TTyButton` 的 `OnClick`（见 [第 6 节](#6-代码示例)）。

> 两个控件都暴露**基线事件集**（Tier A 鼠标 / 通用事件 + Tier B 键盘 / 焦点事件，因二者均为 `TTyCustomControl`）。完整清单见 [../events.md](../events.md)。工具条自身通常无需挂接这些事件；命令响应走子按钮的 `OnClick`。

---

## 5. 状态与主题

### 5.1 排布函数 `TyToolbarLayout`

排布本身是单元级的**纯函数**，不需要窗口句柄，测试直接喂它、直接读结果；控件只是薄壳，在 `AlignControls` 里跑它、再把结果 `SetBounds` 到子控件上。它有两个重载：

```pascal
{ 无强制断行——既有调用方一直用的这个 }
function TyToolbarLayout(const AItemSizes: array of TSize;
  ABarWidth, AIndent, ATopPad, ASpacing, AButtonHeight: Integer;
  AWrapable: Boolean; out ARows: Integer): TTyRectArray; overload;

{ 带强制断行 }
function TyToolbarLayout(const AItemSizes: array of TSize;
  const ABreakBefore: array of Boolean;
  ABarWidth, AIndent, ATopPad, ASpacing, AButtonHeight: Integer;
  AWrapable: Boolean; out ARows: Integer): TTyRectArray; overload;
```

| 参数 | 含义 |
|------|------|
| `AItemSizes` | 各工具项尺寸；`cy` 不参与排布（行高由 `AButtonHeight` 决定），只是让调用方少建一个数组 |
| `ABreakBefore` | **强制断行**，与 `AItemSizes` 平行：第 `i` 项**另起一行**，不管它本来放不放得下 |
| `ABarWidth` | 工具条可用宽度（控件传 `ClientWidth`） |
| `AIndent` | 每行**前缘**留白（横向） |
| `ATopPad` | 第一行**上方**留白（纵向，控件传 `ContentPadY`） |
| `ASpacing` | 项间距，同时用作行间距 |
| `AButtonHeight` | 统一行高 |
| `AWrapable` | 宽度不够时是否自动换行 |
| `ARows` | 出参：占用的行数——**工具条的自动高度就是按它算的** |

`ABreakBefore` 有三条不那么显然的规则：

- **可以短，也可以不给。** 越界的条目读作 `False`。所以只知道前几项标志的调用方传前几项就行，传空数组等于"一处都不断"。这与 `TyCoolBarPack`（`tyControls.CoolBar`）的 `ABreaks` 是同一套形状和同一套容差——两个 packer 并排读起来是一样的。
- **标志是"前置"的**：`ABreakBefore[i]` 表示"第 i 项**开始**新的一行"。LCL 的 `TToolButton.Wrap` 是"**后置**"的——`toolbar.inc` 在"挪到下一个位置"那一步才处理它，所以它推动的是**下一个**控件。两者的换算是

  ```pascal
  breakBefore[i] := (i > 0) and wrapAfter[i - 1];
  ```

  这道位移是最容易差一位的地方，所以它由测试钉死（`TToolBarBreakTest.TestLclWrapAfterMapsOntoBreakBefore`），而不是留给调用方自己重新想一遍。选"前置"还有一个好处：**空行根本表达不出来**。第 0 项没有上一行可以离开，它的断行标志被忽略；而 LCL 那边，最后一个按钮上的 `Wrap` 照样会把 `FRowCount` 加一，于是报出一行什么都没有的高度。
- **不受 `AWrapable` 约束。** `AWrapable = False` 时这正是 LCL 的行为（LCL 也只在这个模式下才读 `Wrap`）；`AWrapable = True` 时我们**额外**允许强制断行与宽度换行叠加，这一点 LCL 不做。宿主已经明说要断在哪里，照办不算意外；反过来，若也跟着 LCL 把它禁掉，这个能力在默认工具条上就永远够不着——`Wrapable` 的缺省值是 `True`。

> **无断行时与从前逐像素相同。** 不带 `ABreakBefore` 的重载是一次**纯转发**，不是第二份循环——只有一份实现，所以"没设断行就跟以前一模一样"是构造上成立的，不靠两份代码互相看齐。

### 支持的伪类状态

`TTyToolBar` 未重写 `CurrentStates`，且作为容器不跟踪 hover/pressed/focus，实际渲染时始终使用 `CurrentStyle`（`tysNormal` 基础样式）。因此内置主题**未为工具条定义任何伪类规则**（无 `:hover` / `:focus` / `:active` / `:disabled`），其外观仅由基础规则决定。

### light.tycss 内置规则

```css
/* 两个键共写一条规则：解析值完全相同，但现在可以各写各的 */
TyToolBar, TyToolSeparator {
  background: var(--surface-chrome);
  border-color: var(--border);
  border-width: var(--input-border-width);
}
```

### 渲染细节

- **工具条背景：** 先铺一层 `FillSharpBackdrop`（图片主题下透出照片，纯色主题为 no-op），再在存在 `background` 令牌时用 `S.Background` 直接填充整块——alpha 背景会叠加在照片之上（毛玻璃效果），与 `TTyPanel` 一致。
- **底部发丝线：** 存在 `border-color` 令牌时，在工具条底部画一条高度为 `Scale(BorderWidth)`（最小 1px）的水平线（`Rect(0, H-bw, W, H)`）；工具条**只有底边一条 hairline**，无四周边框。
- **分隔线：** `TTyToolSeparator` 同样先铺 backdrop、再（若有）填自身样式的 `background` 与工具条无缝衔接，最后在中央画一条自身 `BorderColor` 的 1px 竖线（上下内缩 `Scale(3)`）。
- **子按钮 ghost 变体：** 当 `Flat = True`（默认）时，工具条在排布阶段把 `StyleClass` **为空**的子 `TTyButton` 设为 `'ghost'`，使按钮呈平面外观；`Flat = False` 时把 `'ghost'` 改回 `''`。**宿主自己设的 `StyleClass` 会保留**——从前这里是无条件赋值，于是每次排布都抹掉调用方写的 `StyleClass := 'primary'`，而排布随任何一次尺寸变化触发，样式是在一个说不准的时刻消失的。
- **工具项图标：** `Images` + `ShowCaptions` 由 `ApplyToolProperties` 下发给子图标按钮（见 [第 3.1 节](#31-ttytoolbar-自有-published-属性)），**不在排布阶段做**。

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.ToolBar, tyControls.Button;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

var
  ToolBar: TTyToolBar;
  Btn: TTyButton;
  Sep: TTyToolSeparator;

// 顶部工具条（默认 Align = alTop）
ToolBar := TTyToolBar.Create(Self);
ToolBar.Parent := Self;
ToolBar.Flat := True;          // 子按钮统一改为 ghost 平面变体（默认即 True）
ToolBar.Wrapable := True;      // 宽度不足自动换行，工具条随行数增高
ToolBar.ButtonHeight := 28;    // 统一按钮高度
ToolBar.ButtonSpacing := 4;    // 相邻按钮间距
ToolBar.Indent := 6;           // 首按钮 / 顶边留白

// 添加工具按钮：Parent = 工具条 → 由工具条负责排布与 ghost 变体
Btn := TTyButton.Create(Self);
Btn.Parent := ToolBar;         // 关键：父控件是工具条，而非窗体
Btn.Width := 72;               // 只需设宽度，高度由 ButtonHeight 统一接管
Btn.Caption := '新建';
Btn.OnClick := @ToolClicked;   // 命令响应挂在子按钮上

// 在按钮组之间插入分隔竖线
Sep := TTyToolSeparator.Create(Self);
Sep.Parent := ToolBar;         // 作为普通工具项参与排布

// 事件处理器
procedure TMainForm.ToolClicked(Sender: TObject);
begin
  FStatus.Caption := Format('已触发工具：%s', [(Sender as TTyButton).Caption]);
end;
```

### 6.1 用 `TTyToolButton` 的完整一条：图标 + 单选组 + 下拉 + 断行

```pascal
uses
  tyControls.Controller, tyControls.ToolBar, tyControls.ImageCollection, tyControls.Menu;

var
  Bar: TTyToolBar;
  Icons: TTyImageCollection;
  B: TTyToolButton;

Icons := TTyImageCollection.Create(Self);
Icons.AddPicture('new',  PicNew);      // 插入顺序 = ImageIndex 的下标空间
Icons.AddPicture('open', PicOpen);
Icons.AddPicture('save', PicSave);

Bar := TTyToolBar.Create(Self);
Bar.Parent := Self;
Bar.Images := Icons;                   // 借给每个没有自己 Images 的工具项
Bar.ShowCaptions := False;             // 与 LCL 一致：只显示图标

// 一个普通命令按钮，图标按下标取
B := TTyToolButton.Create(Self);
B.Parent := Bar;
B.Caption := '新建';                    // ShowCaptions=False 时不画，但仍是 Hint / 助记键的来源
B.ImageIndex := 0;                     // 等价于 B.ImageName := 'new'
B.OnClick := @NewClicked;

// 一段互斥的对齐方式：三个相邻的 tbsCheck + Grouped
for I := 0 to 2 do
begin
  B := TTyToolButton.Create(Self);
  B.Parent := Bar;
  B.Style := tbsCheck;
  B.Grouped := True;                   // 与相邻的成组 tbsCheck 组成一组
  B.Caption := AlignNames[I];
  if I = 0 then B.Down := True;        // 预选：SetDown 会弹起同组其余的
end;

// 一条分隔线（用样式，不用单独的控件；两者画的是同一份墨迹）
B := TTyToolButton.Create(Self);
B.Parent := Bar;
B.Style := tbsDivider;                 // 宽度自动变成 5

// 分裂下拉：主区是"保存"，右边箭头弹出"另存为…"菜单
B := TTyToolButton.Create(Self);
B.Parent := Bar;
B.Style := tbsDropDown;
B.Caption := '保存';
B.ImageIndex := 2;
B.OnClick := @SaveClicked;             // 只有主区会触发它
B.DropdownMenu := SaveMenu;            // 箭头区弹这个；有菜单时 OnArrowClick 不触发
B.Wrap := True;                        // 这一行到此为止，后面的工具另起一行
```

---

## 7. 注意事项

- **子控件即工具项：** 把 `TTyButton`（及 `TTyToolSeparator`）的 `Parent` 设为工具条即完成停靠；工具条是 `csAcceptsControls` 容器，在 `AlignControls` 里按子控件顺序（仅可见者）逐个排布。子按钮**只需设 `Width`**，高度被 `ButtonHeight` 统一覆盖。
- **Flat 只动它自己设过的 StyleClass：** `Flat=True` 把**空** `StyleClass` 设为 `'ghost'`，`Flat=False` 把 `'ghost'` 改回 `''`；子按钮上宿主写的其它变体（`'primary'`、`'danger'`…）**会保留**。
- **命令响应走子按钮：** 工具条自身无 `OnClick` 语义的专有事件；请挂接各子按钮的 `OnClick`（Tier A 基线事件）。
- **Wrapable 自动增高：** 当 `Align in [alTop, alBottom]` 且 `Wrapable=True` 时，一行放不下的工具项换行，工具条高度按 `padY*2 + rows*ButtonHeight + (rows-1)*ButtonSpacing` 自动调整（`padY` = 主题令牌 `--toolbar-pad-y`，缺省 4；**不再是 `Indent`**，横向留白不该参与高度）——不要在代码里硬设一个与之冲突的 `Height`。
- **重入守卫：** `AlignControls` 末尾对 `Height` 的赋值会再次触发 `AlignControls`，`FInLayout` 守卫防止无限递归。
- **强制断行已经接线了：** `TyToolbarLayout` 的 `ABreakBefore`（见 [第 5.1 节](#51-排布函数-tytoolbarlayout)）由 `TTyToolButton.Wrap` 填入——`AlignControls` 把每个**可见**工具项的 `Wrap` 收成一个后置数组，再过一遍 `TyToolWrapToBreakBefore` 换成前置标志。没有任何工具项设 `Wrap` 时结果是全 `False`，排布函数读它与从前的无断行重载**逐像素相同**，所以既有工具条一个像素都不会动。两处与 LCL 的差异见 [第 3.2.4 节](#324-wrap两处与-lcl-的差异)。
- **工具项不必是 `TTyToolButton`：** 工具条照旧排布任何可见子控件（`TTyButton`、`TTyToolSeparator`、编辑框、下拉框……）。只是 `Wrap` / `Grouped` / `Index` / `ImageIndex` / 六种 `Style` 这些**工具条语义**只有 `TTyToolButton` 才有，别的子控件在这些规则里读作"没有标志"——条上的 `ButtonWidth` 下限、`DropDownWidth`、`List` 同理，只够得着 `TTyToolButton`。`Buttons[]` 里也只有 `TTyToolButton`。
- **`ButtonWidth` 是可逆的下限：** 调低（或清成 0）会还原各按钮自己的设计宽度——工具条记着它借出的宽度，不会把 `.lfm` 值棘轮掉。但**内容下限仍在**：按钮自己的 `Constraints.MinWidth`（标题 + 内边距 + 箭头区）比 `ButtonWidth` 大时按内容算，这与 LCL"取 preferred 与 ButtonWidth 的较大者"一致。
- **`OnPaintButton` 是整体替换：** 挂上即接管每个工具按钮的全部绘制（含分隔占位），清掉即恢复主题默认。要"在主题绘制**之上**补一笔"用继承来的 `OnPaint`（[../events.md](../events.md)），不要用它。
- **占位样式不吃 `Flat` 的 ghost：** `Flat = True` 时工具条会把空 `StyleClass` 的子 `TTyButton` 设成 `'ghost'`，但 `Style` 为 `tbsSeparator` / `tbsDivider` 的工具按钮**被跳过**——它解析的是 `TyToolSeparator` 键，套上按钮族的变体等于向主题要一条 `TyToolSeparator.ghost`（没有哪套皮肤定义过），还会在宿主从没设过样式的控件上留下一个 `StyleClass`。
- **`TTyToolBarEx` 整份重写了 `AlignControls`：** `Wrapable = True` 时它把活儿原样交回基类（`inherited AlignControls`），于是走的是同一个排布函数、同一套几何；`Wrapable = False` 时它走自己的溢出 chevron 路径，**完全不调用 `TyToolbarLayout`**，那条路上只有一行，也就没有"断行"可言。改基类的排布时这两条路都要一起验——`TToolBarExControlTest.TestWrapableGeometryIsTheBaseSolvers` 就是钉住前者的那颗钉子。
- **ShowCaptions 的默认值是 `False`（与 LCL 一致）：** 它只对**能画图标**的工具项（`TTyGlyphButtonBase` 一族）生效，且只把标题换成图标——**解析不出图标的工具项照旧显示标题**，所以给一条纯文字工具条打开这个默认值不会把它抹白。工具项上一旦有人写过 `ShowCaption`，工具条就不再管它。
- **Images 借给工具项：** 工具条把自己的 `TTyImageCollection` 借给**没有 `Images` 的**子图标按钮，于是工具项只需设 `ImageName`；自带集合的工具项不受影响。工具项**加入工具条之后**才设 `Images` 也有效（`InsertControl` 里也会下发一次）。
- **无四周边框：** 主题的 `border-color` / `border-width` 只画工具条**底部一条 hairline**，不绘制四周边框；工具条不参与任何伪类状态。
- **分隔线有独立 typeKey：** `TTyToolSeparator.GetStyleTypeKey` 返回 `'TyToolSeparator'`。内建主题让它与 `TyToolBar` 共写一条规则，所以默认观感不变；但要调竖线的颜色/底色，请写 `TyToolSeparator` 选择器，改 `TyToolBar` 会顺带改掉整条工具条。
- **DFM 序列化：** `Align` 声明了 `default alTop`，`ButtonSpacing`/`Indent`/`Wrapable`/`ShowCaptions`/`Flat`/`DropDownWidth`（`default 0`）/`List`（`default True`）均声明了默认值，等于默认值时不写入 `.lfm`/`.dfm`；`ButtonHeight` 与 `ButtonWidth` 走 `stored` 旗（显式写过才存）。工具按钮的 `GlyphLayout` 同样走 `stored` 旗且 `nodefault`（见 [第 3.2 节](#32-ttytoolbutton工具按钮)的存储说明）。
