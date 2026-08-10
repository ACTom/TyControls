# TTyScrollBox — API 参考

## 1. 概述

`TTyScrollBox` 是 TyControls 库中的主题化**滚动视口容器**，继承自 [`TTyPanel`](panel.md)。典型用途：承载尺寸超过自身可视区域的子控件集合（例如一整块表单、一张大图、一组排布很长的控件），当内容在某个方向上溢出时，在该方向自动出现一个内嵌的 `TTyScrollBar`，用户拖动滚动条即可平移内容；内容能完整放下时，对应滚动条自动隐藏。

它是**真正的 LCL 容器**（有窗口句柄），子控件直接以其为 `Parent`，坐标系以视口左上角为原点。行为上与 [`TTyPanel`](panel.md) 的区别在于「内容超出视口时可滚动」；主题上它有**自己的 typeKey** `TyScrollBox`——滚动井在视觉惯例上是**下沉**的，而面板是**抬起**的，二者必须能分开表达。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ScrollBox` |
| `GetStyleTypeKey` 返回值 | `'TyScrollBox'`（**自有 typeKey**） |
| 基类 | `TTyPanel`（继承自 `TTyCustomControl` → `TCustomControl`；只继承框架与容器管道，不再共用它的键） |
| 默认尺寸 | 200 × 150（逻辑像素） |
| 内嵌滚动条 typeKey | `TyScrollBar` / `TyScrollThumb`（见 [scrollbar.md](scrollbar.md)） |
| 视口 typeKey | `TyScrollContent`（`TTyScrollContent`，可选的显式视口，见 §5） |

```pascal
uses tyControls.ScrollBox;
```

### 这些键各画什么

| 键 | 画什么 |
|----|--------|
| `TyScrollBox` | 滚动框本体的框：`background` / `border-color` / `border-width` / `border-radius` / `padding`（`padding` 只影响本体绘制，不约束子控件） |
| `TyScrollBar` / `TyScrollThumb` | 两条内嵌滚动条的轨道与缩略块，由 `TTyScrollBar` 自身解析（见 [scrollbar.md](scrollbar.md)） |
| `TyScrollContent` | 显式视口 `TTyScrollContent` 的**表面**（只画 `background`，**不画边框**——框归外面的滚动框画，视口再画一条会正好压在内容该穿过去的地方）。**必须有值且不透明**，理由见下 |

> **`TyScrollContent` 必须解析出一个不透明底色。** 视口是**窗口化**控件，而它的 `Paint` **除了这块底色什么都不画**（还包在 `if tpBackground in S.Present` 里）。所以主题不给值 ≠ "视口透明",而是**屏幕上留着 widgetset 给那个窗口的擦除色**。`TTyForm.ApplyChromeTheme` 只为**纯色**窗体底重新播种擦除色,渐变底皮肤(aero)因此会把一块陈旧的系统灰 `#F0F0F0` 留在井里——暗色模式下就是一圈刺眼的**亮斑**(真机取色实测:修复前 aero/dark 视口读到 `F0F0F0`,修复后读到 `1E1E1E`)。这个键此前**在任何一层都没有规则**,现已写进 `themes/light.tycss` 基础层;`tests/test.modecoherence.pas` 的 `cMustPaintKeys` 用不透明下限钉住它。自定义主题若整体覆盖了容器族,记得把它一并带上。

> **主题说明：** 早期版本里 `TTyScrollBox` 返回 `'TyPanel'`，于是滚动井与面板在主题层完全无法分辨；那时文档给出的变通办法是"用 `StyleClass` 加个类选择器（如 `TyPanel.scroll`）"。**这个变通已经不需要了，也不该再用**——直接写 `TyScrollBox { ... }` 就只作用于滚动框。内置主题把 `TyScrollBox` 与 `TyPanel` 等键写在同一条规则里（取值相同、名字独立），所以默认观感不变；第三方主题若只覆盖了 `TyPanel`，需要补上 `TyScrollBox`（主题层按 typeKey 全有全无地回落，否则会掉回内置 light 取值）。
>
> **子部件 typeKey：** 滚动框本体只有这一个盒子样式；两条滚动条是真正的 `TTyScrollBar` 子控件、走它们自己的键，显式视口是真正的 `TTyScrollContent` 子控件、走 `TyScrollContent`。

---

## 3. 属性表

### 自有 public 属性（只读）

| 属性 | 类型 | 说明 |
|------|------|------|
| `ContentWidth` | `Integer` | 内容逻辑总宽度 = 所有**非滚动条子控件**在未滚动坐标系下的包围盒右边界；`UpdateScrollRange` 后有效。 |
| `ContentHeight` | `Integer` | 内容逻辑总高度 = 包围盒下边界；`UpdateScrollRange` 后有效。 |
| `ScrollX` | `Integer` | 当前水平滚动偏移（≥ 0，逻辑像素），表示内容相对视口向左平移了多少。 |
| `ScrollY` | `Integer` | 当前垂直滚动偏移（≥ 0，逻辑像素）。 |

### 继承自 TTyPanel / TTyCustomControl 的 published 成员

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式；常设为 `alClient` 让滚动框填满宿主区域。 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 锚点布局。 |
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 中 `TyScrollBox.classname` 选择器。 |
| `Controller` | `TTyStyleController` | `nil`（全局 `TyDefaultController`） | 指定样式控制器；该值会自动传播给两个内嵌滚动条。 |
| `OnConstrainedResize` | `TConstrainedResizeEvent` | `nil` | 尺寸协商钩子，照 `TScrollBox` republish。它在 `TControl` 上是 **protected**，所以此前不只是对象检视器里没有——**代码里也够不着**，能表达的尺寸限制只有静态的 `Constraints` 值；"这一栏永远不超过窗体的一半"这类依赖运行期数值的限制无从表达。 |

> `Caption` / `Alignment` 从 `TTyPanel` 继承而来，滚动框场景一般不使用（若设置了 `Caption`，它会被子控件覆盖）。

---

## 4. 方法

| 方法 | 说明 |
|------|------|
| `procedure UpdateScrollRange` | 重新测量子控件包围盒，据此显示 / 隐藏 / 定位两个滚动条，并把滚动偏移夹取到合法范围。**通常不需要你调用**：控件在 `Resize`、`.lfm` 流式化结束（`Loaded`）、以及**每一轮子控件布局之后**（`ControlsAligned`，涵盖增删子控件、改子控件位置 / 大小）都会自动重算。留作 public 是给"绕过 LCL 布局直接改了子控件几何"这类特殊场景兜底。 |
| `procedure ScrollByDelta(ADx, ADy)` | 把**视图**按 `(ADx, ADy)` 挪一段，夹取到当前滚动范围（该轴没有滚动条时为 0），并同步两个缩略块。 |
| `procedure ScrollTo(AX, AY)` | 把**视图**滚到绝对偏移 `(AX, AY)`；内部走 `ScrollByDelta`，因此与增量路径共用同一套重新测量与夹取规则。 |
| `procedure ScrollBy(DeltaX, DeltaY); override` | **滚动视图**——与其他所有滚动容器上的语义一致。参数按 LCL 的约定是**内容**移动了多远，所以 `DeltaY` 为负 = 内容上移 = 向下滚。 |
| `procedure ScrollInView(AControl)` | 把 `AControl` 完整带进视口所需的**最小**滚动量。比视口还大的子控件按顶/左边缘对齐（追它的下边缘会把上边缘顶出另一头），与 LCL 的取舍一致。 |
| `procedure UpdateScrollbars` | `UpdateScrollRange` 的 LCL 名字（`TScrollingWinControl.UpdateScrollbars`），同一件事。保留为一行转发而非改名，因为仓库内所有调用点与文档用的都是原名。 |

> **`ScrollBy` 曾经是个"同名不同义"的陷阱。** 本类原先**没有**重写它，于是移植过来的 `Box.ScrollBy(0, -50)` 落到 `TWinControl.ScrollBy`（平移子控件）而不是 `TScrollingWinControl.ScrollBy`（滚动视图）——同名、同参数个数、同参数类型、无编译错误、结果是错的：它把**每一个**子控件都重新定位，包括那两条滚动条（它们被带离了吸附的边缘），而本单元开头声明为"唯一真相来源"的 `FScrollX/FScrollY` 纹丝不动。紧接着的一次 `UpdateScrollRange` 会把被挪走的子控件量成**更小**的内容范围（测量时会把偏移加回去），于是范围和缩略块双双失真，下一次拖动缩略块内容就跳一下。现在它按 LCL 的语义滚动视图；平移子控件的那个原版仍在，由 `ScrollContentTo` 以 `inherited ScrollBy` 取用——那是唯一需要它的调用点。
>
> `ScrollByDelta` / `ScrollTo` 是同一件事的另一种签名（参数直接是偏移增量，符号与 `ScrollBy` 相反），两者原先都是 protected，于是"再往下看一点"这个滚动容器最常见的诉求，只能靠去写内嵌滚动条的 `Position` 来碰运气。

---

## 5. 滚动机制

1. **滚动范围** = 全部非滚动条子控件在**逻辑（未滚动）坐标**下的包围盒。每个子控件的逻辑坐标 = 其当前 `Left/Top`（已被滚动平移过）+ 当前偏移 `FScrollX/FScrollY`。范围从视口原点 `(0,0)` 量到内容最远的右 / 下边界。
2. **滚动条可见性**：某一轴的 `内容尺寸 > 视口尺寸` 时才显示该轴滚动条。两条滚动条互相影响——显示垂直条会占掉水平方向的可用宽度，可能进而需要水平条（反之亦然），`UpdateScrollRange` 内部对这种相互依赖做了二次判定。
3. **拖动滚动条**：在滚动条 `OnChange` 中，计算新目标偏移与当前偏移的差值 `dx/dy`，调用 `inherited ScrollBy(-dx, -dy)`（`inherited` = `TWinControl` 那个平移子控件的原版，不是本类"滚动视图"的重写）平移**所有**子控件；由于它也会移动那两个内嵌滚动条，随后把它们重新吸附回右 / 下边缘。**偏移先提交、再平移**：`ScrollBy` 末尾的 `EnableAutoSizing` 可能就地重排子控件，那次重排读的是 `AdjustClientRect`，偏移若还是旧值，就会把每个对齐子控件放回原处、把这次滚动悄悄吃掉。
4. **鼠标滚轮**：优先滚动溢出的垂直轴（无垂直溢出时滚动水平轴），每格约一个滚动条厚度的内容距离。

### 容器契约（子控件可用区域）

滚动框是**真正的 LCL 容器**，所以它按 LCL 的方式向布局引擎申明"子控件能用哪块地方"。三个钩子各管一件事：

| 钩子 | 管什么 |
|------|--------|
| `GetClientRect` | **视口** = 整框减去可见滚动条占的槽。因此 `ClientWidth/ClientHeight` 报的是可视区域，与 LCL 的 `TScrollBox` 语义一致。 |
| `GetLogicalClientRect` | **子控件布局区的大小** = 视口，且在**真正会滚动的那一轴**上扩展到内容尺寸。 |
| `AdjustClientRect` | **子控件布局区的原点** = `(-ScrollX, -ScrollY)`。 |

三条都是必需的，缺一条就有具体的坏法：

1. **`ClientRect` 必须扣掉槽。** 不只是为了让 `alClient` 子控件让开滚动条——LCL 记录子控件的锚定基线用的是 `Parent.ClientWidth/ClientHeight`（`TControl.UpdateBaseBounds`），而排版用的是布局区。两者相差一个滚动条厚度时，每次 `ScrollBy` 给子控件写一次 bounds 就把这个差额记进去一次：`akRight` 锚定的子控件会**每滚一次少一个滚动条的宽度**，直到消失。
2. **布局区要能扩展到内容。** `DoAlign(alTop)` 会把堆叠位置钳在布局区的下边界内，布局区只有视口那么高的话，一列超出视口的 `alTop` 行会把**折线以下的行全部叠在最后一行可见行上面**。
3. **但只扩展会滚动的那一轴。** 对齐子控件的尺寸来自布局区、又反过来被计入内容尺寸；无条件扩展会让这个环自锁——一列 `alTop` 行会永远保持整框宽度、永远压在垂直条底下，再也回不到视口宽。
4. **原点跟着滚动偏移走。** 子控件的 `Left/Top` 存的是**已滚动**坐标（`ScrollBy` 平移的就是它们），布局引擎必须用同一个原点，否则每次重排都会把对齐子控件拉回未滚动位置，表现为"滑块在动、内容不动"。

> **内容范围按轴分别统计。** 宽度不计 `alTop` / `alBottom` / `alClient` 的子控件，高度不计 `alLeft` / `alRight` / `alClient` 的——它们在该轴上的尺寸由容器给定，计进去就是上面第 3 条的自锁。（LCL 用子控件的**首选尺寸**算 Range 来回避同一个问题。）
>
> **主题框仍然画满整框。** `TTyScrollBox` 重写了 `Paint`：`ClientRect` 已经缩到视口，但背景/边框要铺满整个控件，包括两条槽和它们相交的那个角。

> **无窗口句柄下的行为（headless / 测试）：** 纯滚动数学（范围 / 夹取 / 可见性阈值 / 缩略块 PageSize）是单元级纯函数，可直接验证；对齐子控件的实际布局需要 LCL 对齐引擎真的跑起来，而 `TForm.CreateNew` 且从不 `Show` 的窗体会命中 `AutoSizeDelayedHandle`，对齐被整体推迟——所以这一层要在真机验收探针里验，headless 断言会假绿。
>
> 这一层在开发期于真机上验证过两组场景：一组是重算时机（`.lfm` 流进来的子控件、运行期增删改、锚定、真 Z 序）；另一组是论坛 #12/#15 那一串（槽的像素归属、滚轮第一格、拖动的重绘代价、内容跳动），靠 **HWND 子类化数真 `WM_PAINT`**、靠 `PrintWindow` 取 DWM 合成表面（会话断开时 `GetDC(0)` 抓屏是一片空白，先自证再判定），并先实测一遍本机 LCL 上"移动一个子控件"要几轮 `ControlsAligned`，拿它当判据而不是拍脑袋定 1。

### 显式视口 `TTyScrollContent`（可选）

子控件是被**父窗口的客户区**裁剪的，而自绘容器的边框画在客户区**里面**——重写 `GetClientRect` 只改 LCL 的计算，动不了 widgetset 真正裁剪的那条边界。于是内容一滚就会压过上下边框；这不是谁用错了，而是每次滚动都会发生的常态（LCL 自己的 `TScrollBox` 看不到这个问题，因为它用 `BorderStyle := bsSingle` 把边框放进**非客户区**，由 OS 先裁子控件——主题化的边框住不进那里）。

所以裁剪边界必须是一个**真窗口**，这就是 `TTyScrollContent`（单元 `tyControls.ScrollContent`）：一个按边框内缩的普通容器，托住内容并在各 widgetset 上原生裁剪。它是**显式**的——内容要 `Parent` 到视口上，不是 `Parent` 到滚动框上，与 `TTyPageControl` 里的 `TTyTabSheet` 同构；隐式改写 `Parent` 会留下"`Parent` 不是你赋的那个、`ControlCount` 数不到内容、坐标悄悄挪了位"这一串隐规则。

- **可选，不改旧行为。** 没有给视口的滚动框照旧滚自己的子控件，重编译不会改变现有窗体的行为；裁剪是"给了它一个视口"之后才获得的。
- **视口是 chrome，不是内容。** 它的 bounds 由滚动框根据边框与可见滚动条算出（`csDesignFixedBounds`，设计器拖不动），因此不计入内容范围——否则布局会自锁。
- **认领时机：** 滚动框在 `InsertControl` 里认领视口，代码创建 / 设计器拖放 / `.lfm` 流式化三条路径都经过那里。`ContentHost` 返回视口（没有则返回滚动框自身）。
- **视口自己也讲同一套容器契约。** 一旦有了视口，内容就住在**视口**里，于是上面那两条（布局原点跟着偏移走、布局区涨到内容）对它们就统统失效了——那两个钩子在滚动框上，而它们不是滚动框的子控件。表现是**视口里的对齐子控件一格都不滚**：滑块走了、`ScrollY` 变了，`alTop` 的行还钉在原处（未对齐的子控件却滚得好好的，所以这个坏法看上去像"时灵时不灵"）。因此 `TTyScrollContent` 自己也重写了 `AdjustClientRect` 与 `GetLogicalClientRect`，由滚动框通过 `SetScrollOrigin` 把偏移和内容范围喂给它——视口两者都**不自己算**，"滚动原点"只能有一处权威。

> **两处停靠代码必然会走岔。** 滚动条的位置一度写了两遍：`MeasureAndDock` 停在 `(Width-thick-bw, bw)`，而 `ScrollContentTo` 里"`ScrollBy` 把条也搬走了，补停回去"那一步算成 `(Width-thick, 0)`。差一个边框宽，于是**每滚一步**两条都被搬开再搬回——肉眼就是 1px 抖动（论坛报的"拖滑块闪烁"），而每一次 `SetBounds` 都要整框重排一轮子控件，再由 `ControlsAligned` 触发一次重算、再把条搬回去。真机计数（开发期实测）：12 步拖动引发 **120 轮** `ControlsAligned`。现在停靠矩形由 `MeasureAndDock` 算一次、存进 `FVBarRect`/`FHBarRect`，补停只是把它**放回同一个矩形**（因而通常是个空操作），整个移动再包一层 `DisableAutoSizing`/`EnableAutoSizing` 合并成一轮——同样 12 步现在是 **24 轮**，正好等于本机 LCL 上"移动一个子控件"的实测底线（2 轮/步）。

---

## 6. 纯函数（单元级，可 headless 测试）

单元 `tyControls.ScrollBox` 导出以下纯函数，是滚动逻辑的可测核心：

| 函数 | 签名 | 说明 |
|------|------|------|
| `TyScrollNeeded` | `(AContentExtent, AViewport: Integer): Boolean` | 内容在该轴上是否溢出视口（需要滚动条）。`内容 > 视口` 时为 `True`。 |
| `TyClampScroll` | `(APos, ARange, AViewport: Integer): Integer` | 把偏移夹取到 `[0, 内容-视口]`；内容能放下时钉在 `0`。 |
| `TyScrollThumbPage` | `(AViewport, ARange: Integer): Integer` | 该轴滚动条的 `PageSize`（= 视口长度，用于按比例决定缩略块大小），下限 `1`。 |
| `TyScrollMax` | `(AContentExtent, AViewport: Integer): Integer` | 该轴的滚动范围（最大偏移）= `内容 - 视口`，下限 `0`；即滚动条的 `Max`。 |

---

## 7. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.ScrollBox, tyControls.Button, tyControls.Panel;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

// 创建一个填满宿主的滚动框
var Box: TTyScrollBox;
Box := TTyScrollBox.Create(Self);
Box.Parent := Self;
Box.Align := alClient;

// 放入一块比视口大得多的内容（例如很多按钮堆叠成长条）
var i: Integer;
var Btn: TTyButton;
for i := 0 to 29 do
begin
  Btn := TTyButton.Create(Box);
  Btn.Parent := Box;
  Btn.SetBounds(12, 12 + i * 40, 160, 32);
  Btn.Caption := Format('第 %d 项', [i + 1]);
end;

// 到此为止：滚动范围与滚动条已经自动跟上，无需再调 UpdateScrollRange。
```

---

## 8. 注意事项

- **子控件不受 padding 约束：** 与 `TTyPanel` 一致，`padding` 只影响本体绘制，不自动约束子控件布局；未对齐子控件的坐标需自行设置。
- **增删 / 改动子控件后不必手动刷新：** 控件在 `Resize`、`Loaded` 与每一轮子控件布局之后都会自动重算范围，`UpdateScrollRange` 只在特殊场景下才需要显式调用（见 §4）。
- **对齐子控件会让开滚动条、并跟着滚动：** `alTop` / `alLeft` / `alClient` 等对齐方式在滚动框里是**受支持**的，宽 / 高按扣掉滚动条槽之后的视口计算（见 §5 容器契约）。
- **两个滚动条是内部子控件：** 它们由滚动框自身拥有并创建，标记为 `csNoDesignVisible`，不会出现在 IDE 设计器的子控件列表里，也不会被流式化。请勿在设计器里手动摆放滚动条。
- **`Controller` 自动传播：** 给滚动框设置 `Controller` 后，两个内嵌滚动条会在下次 `UpdateScrollRange` 时继承同一控制器，保证主题一致。
- **偏移永远非负：** `ScrollX/ScrollY` 始终 `≥ 0`，且被夹取在 `[0, 内容-视口]`；当宿主放大到内容可完整容纳时，偏移自动归零、滚动条自动隐藏。
- **有自己的主题键：** 滚动框走 `TyScrollBox`，与 `TyPanel` 互不影响。要让滚动井下沉（例如更深的底色、无圆角、内描边），直接写 `TyScrollBox { … }`——**不要**改 `TyPanel`，那会重涂全应用的面板。旧文档建议的 `StyleClass` 变通（`TyPanel.scroll`）已经过时，只在需要同一控件的多种变体时才用得上。

---

## 9. RTL 镜像（`BiDiMode = bdRightToLeft`）

**竖向滚动条搬到左边缘**——这是一个窗口宣告自己从右往左读时，最响的一个信号。跟着一起动的有四处，它们必须同时动：

| 动的 | 怎么动 |
|---|---|
| 竖条 | 停靠到**左**边缘（框内，让开边框）；滚动一次之后重新贴边也贴同一侧 |
| 横条 | 起点让开竖条的槽，仍然在竖条那个角之前收住——角换了一端而已 |
| 视口（`TTyScrollContent`） | 左端让开竖条 |
| 子控件布局原点（`AdjustClientRect`） | 整体右移一个条宽 |
| `TTyScrollPanel` 的自动平移边带 | 跟着视口走 |

### 不动的两处，都是有意的

**`GetClientRect` 让出的仍然是右边。** 这一处最容易改错：`TControl.GetClientWidth` 就是 `ClientRect.Right`（`lcl/include/control.inc:1910`），所以把 `Dec(Result.Right, …)` 改成 `Inc(Result.Left, …)` 会让镜像后的框把**整个宽度**报成客户宽度，而布局矩形却窄一个滚动条——LCL 从前者记锚点基线、按后者布局，每次 `ScrollBy` 都把这个差额再记一遍，结果就是本仓库记录过的"`akRight` 子控件每滚一次少 12px 直到消失"。所以：**尺寸由 `GetClientRect` / `GetLogicalClientRect` 负责，与左右无关；镜像只搬原点，在 `AdjustClientRect` 里。**三个钩子的分工没变，只是第三个多了一个固定位移。

**横向滚动条自己不镜像**（`MirrorHorizontal` 保持 `False`）。盒子里的子控件按 `Align` / `Anchors` 布局，而这一层**不镜像**（LCL 的对齐引擎除 `ChildSizing` 表格路径外没有 BiDi 分支，我们跟着翻会和所有原生容器分叉、把移植过来的 `.lfm` 全摆错）。子控件既然仍是从左往右排的，内容的原点就真的是左边缘；此时把横条的 `Min` 放到右边，滑块指的就是文档的另一头。**条什么时候镜像，取决于它滚的东西什么时候镜像。**

守卫在 `tests/test.rtl.pas` 的 `TRtlScrollBoxTest`，其中 `MirroringChangesTheSideOfTheGuttersAndNotTheirCost` 专钉上面那个 12px 陷阱。
