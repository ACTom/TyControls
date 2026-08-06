# TTyToolBar + TTyToolSeparator

## 1. 概述

`TTyToolBar` 是 TyControls 库中的水平工具条控件，继承自 `TTyCustomControl`。它是一个 `csAcceptsControls` 容器，把作为其子控件（`Parent := ToolBar`）的 `TTyButton` 停靠成一条工具按钮带；默认 `Align := alTop` 紧贴窗体顶部。同单元还提供 `TTyToolSeparator`——一条用于在按钮组之间分隔的竖线（见 [第 3.3 节](#33-ttytoolseparator分隔线)）。典型用途：文档编辑器 / 主窗口顶部的命令按钮栏。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ToolBar` |
| `GetStyleTypeKey` 返回值（`TTyToolBar`） | `'TyToolBar'` |
| `GetStyleTypeKey` 返回值（`TTyToolSeparator`） | `'TyToolSeparator'`（**自己的键**，不再借工具条的） |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸（`TTyToolBar`） | 300 × 30（逻辑像素） |
| 默认尺寸（`TTyToolSeparator`） | 8 × 24（宽固定 8；高走密度轴 `TyDensityHeight(…, 24)`，现代密度下更高） |

| typeKey | 画什么 |
|---|---|
| `TyToolBar` | 工具条：`background` 铺满整块（图片主题下叠在照片上），`border-color` + `border-width` 画**底部一条 hairline**（无四周边框） |
| `TyToolSeparator` | 分隔线：`background` 用来与工具条底色无缝衔接，`border-color` 是那条 1px 竖线的颜色 |

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
| `ButtonSpacing` | `Integer` | `2` | 相邻工具项之间的水平间距（换行时也用作行间距）。改值触发 `Relayout`。 |
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

### 3.2 继承的通用成员

`TTyToolBar` 与 `TTyToolSeparator` 均继承自 `TTyCustomControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分。 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器。 |

> `TTyToolBar` 未跟踪 `FHover` / `FPressed` 等交互状态字段——它是纯容器，仅绘制背景与底部发丝线，本身不参与 `:hover` / `:active`。私有布局字段（`FButtonHeight` / `FButtonSpacing` / `FIndent` / `FWrapable` / `FShowCaptions` / `FFlat` / `FImages` / `FInLayout`）由上表 published 属性驱动，`FInLayout` 是 `AlignControls` 的重入守卫。

### 3.3 TTyToolSeparator（分隔线）

`TTyToolSeparator` 是一条平凡的竖线控件，把它 `Parent := ToolBar` 即可作为普通工具项参与排布（占据一个 8px 宽的格位，在中央绘制 1px 竖线）。它自身**没有专有 published 属性**，仅 published 继承来的三项：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Align` | `TAlign` | `alNone` | 停靠方式（继承）。 |
| `StyleClass` | `string` | `''` | CSS 类名。 |
| `Controller` | `TTyStyleController` | `nil` | 样式控制器。 |

竖线颜色取 `TyToolSeparator` 样式的 `BorderColor`，竖线上下各内缩 3 逻辑像素（`P.Scale(3)`）；同一样式的 `background` 用于铺底，好让它与所在工具条无缝衔接。

---

## 4. 事件

`TTyToolBar` 与 `TTyToolSeparator` **均无自有专有事件**——工具条只 published 布局属性，不发出 `OnChange` 之类的通知。用户交互（点击）发生在**子按钮**上，请挂接各个子 `TTyButton` 的 `OnClick`（见 [第 6 节](#6-代码示例)）。

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

---

## 7. 注意事项

- **子控件即工具项：** 把 `TTyButton`（及 `TTyToolSeparator`）的 `Parent` 设为工具条即完成停靠；工具条是 `csAcceptsControls` 容器，在 `AlignControls` 里按子控件顺序（仅可见者）逐个排布。子按钮**只需设 `Width`**，高度被 `ButtonHeight` 统一覆盖。
- **Flat 只动它自己设过的 StyleClass：** `Flat=True` 把**空** `StyleClass` 设为 `'ghost'`，`Flat=False` 把 `'ghost'` 改回 `''`；子按钮上宿主写的其它变体（`'primary'`、`'danger'`…）**会保留**。
- **命令响应走子按钮：** 工具条自身无 `OnClick` 语义的专有事件；请挂接各子按钮的 `OnClick`（Tier A 基线事件）。
- **Wrapable 自动增高：** 当 `Align in [alTop, alBottom]` 且 `Wrapable=True` 时，一行放不下的工具项换行，工具条高度按 `padY*2 + rows*ButtonHeight + (rows-1)*ButtonSpacing` 自动调整（`padY` = 主题令牌 `--toolbar-pad-y`，缺省 4；**不再是 `Indent`**，横向留白不该参与高度）——不要在代码里硬设一个与之冲突的 `Height`。
- **重入守卫：** `AlignControls` 末尾对 `Height` 的赋值会再次触发 `AlignControls`，`FInLayout` 守卫防止无限递归。
- **强制断行目前只在排布函数上：** `TyToolbarLayout` 已经接受 `ABreakBefore`（见 [第 5.1 节](#51-排布函数-tytoolbarlayout)），但 `TTyToolBar` 自身还**没有**哪个 published 属性去填它——控件调用的仍是无断行的那个重载。它是为 `TToolButton.Wrap` 预备的输入，等那个类落地时再接线。
- **`TTyToolBarEx` 整份重写了 `AlignControls`：** `Wrapable = True` 时它把活儿原样交回基类（`inherited AlignControls`），于是走的是同一个排布函数、同一套几何；`Wrapable = False` 时它走自己的溢出 chevron 路径，**完全不调用 `TyToolbarLayout`**，那条路上只有一行，也就没有"断行"可言。改基类的排布时这两条路都要一起验——`TToolBarExControlTest.TestWrapableGeometryIsTheBaseSolvers` 就是钉住前者的那颗钉子。
- **ShowCaptions 的默认值是 `False`（与 LCL 一致）：** 它只对**能画图标**的工具项（`TTyGlyphButtonBase` 一族）生效，且只把标题换成图标——**解析不出图标的工具项照旧显示标题**，所以给一条纯文字工具条打开这个默认值不会把它抹白。工具项上一旦有人写过 `ShowCaption`，工具条就不再管它。
- **Images 借给工具项：** 工具条把自己的 `TTyImageCollection` 借给**没有 `Images` 的**子图标按钮，于是工具项只需设 `ImageName`；自带集合的工具项不受影响。工具项**加入工具条之后**才设 `Images` 也有效（`InsertControl` 里也会下发一次）。
- **无四周边框：** 主题的 `border-color` / `border-width` 只画工具条**底部一条 hairline**，不绘制四周边框；工具条不参与任何伪类状态。
- **分隔线有独立 typeKey：** `TTyToolSeparator.GetStyleTypeKey` 返回 `'TyToolSeparator'`。内建主题让它与 `TyToolBar` 共写一条规则，所以默认观感不变；但要调竖线的颜色/底色，请写 `TyToolSeparator` 选择器，改 `TyToolBar` 会顺带改掉整条工具条。
- **DFM 序列化：** `Align` 声明了 `default alTop`，`ButtonHeight`/`ButtonSpacing`/`Indent`/`Wrapable`/`ShowCaptions`/`Flat` 均声明了默认值，等于默认值时不写入 `.lfm`/`.dfm`。
