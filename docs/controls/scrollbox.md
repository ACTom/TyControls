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

```pascal
uses tyControls.ScrollBox;
```

### 这些键各画什么

| 键 | 画什么 |
|----|--------|
| `TyScrollBox` | 视口本体的框：`background` / `border-color` / `border-width` / `border-radius` / `padding`（`padding` 只影响本体绘制，不约束子控件） |
| `TyScrollBar` / `TyScrollThumb` | 两条内嵌滚动条的轨道与缩略块，由 `TTyScrollBar` 自身解析（见 [scrollbar.md](scrollbar.md)） |

> **主题说明：** 早期版本里 `TTyScrollBox` 返回 `'TyPanel'`，于是滚动井与面板在主题层完全无法分辨；那时文档给出的变通办法是"用 `StyleClass` 加个类选择器（如 `TyPanel.scroll`）"。**这个变通已经不需要了，也不该再用**——直接写 `TyScrollBox { ... }` 就只作用于滚动框。内置主题把 `TyScrollBox` 与 `TyPanel` 等键写在同一条规则里（取值相同、名字独立），所以默认观感不变；第三方主题若只覆盖了 `TyPanel`，需要补上 `TyScrollBox`（主题层按 typeKey 全有全无地回落，否则会掉回内置 light 取值）。
>
> **子部件 typeKey：没有。** 视口本身只有这一个盒子样式；两条滚动条是真正的 `TTyScrollBar` 子控件，走它们自己的键。

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

> `Caption` / `Alignment` 从 `TTyPanel` 继承而来，滚动框场景一般不使用（若设置了 `Caption`，它会被子控件覆盖）。

---

## 4. 方法

| 方法 | 说明 |
|------|------|
| `procedure UpdateScrollRange` | 重新测量子控件包围盒，据此显示 / 隐藏 / 定位两个滚动条，并把滚动偏移夹取到合法范围。**通常不需要你调用**：控件在 `Resize`、`.lfm` 流式化结束（`Loaded`）、以及**每一轮子控件布局之后**（`ControlsAligned`，涵盖增删子控件、改子控件位置 / 大小）都会自动重算。留作 public 是给"绕过 LCL 布局直接改了子控件几何"这类特殊场景兜底。 |

---

## 5. 滚动机制

1. **滚动范围** = 全部非滚动条子控件在**逻辑（未滚动）坐标**下的包围盒。每个子控件的逻辑坐标 = 其当前 `Left/Top`（已被滚动平移过）+ 当前偏移 `FScrollX/FScrollY`。范围从视口原点 `(0,0)` 量到内容最远的右 / 下边界。
2. **滚动条可见性**：某一轴的 `内容尺寸 > 视口尺寸` 时才显示该轴滚动条。两条滚动条互相影响——显示垂直条会占掉水平方向的可用宽度，可能进而需要水平条（反之亦然），`UpdateScrollRange` 内部对这种相互依赖做了二次判定。
3. **拖动滚动条**：在滚动条 `OnChange` 中，计算新目标偏移与当前偏移的差值 `dx/dy`，调用 `inherited ScrollBy(-dx, -dy)` 平移**所有**子控件；由于 `ScrollBy` 也会移动那两个内嵌滚动条，随后把它们重新吸附回右 / 下边缘，并提交新的偏移值。
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

> **无窗口句柄下的行为（headless / 测试）：** 纯滚动数学（范围 / 夹取 / 可见性阈值 / 缩略块 PageSize）是单元级纯函数，可直接验证；对齐子控件的实际布局需要 LCL 对齐引擎真的跑起来，而 `TForm.CreateNew` 且从不 `Show` 的窗体会命中 `AutoSizeDelayedHandle`，对齐被整体推迟——所以这一层要在真机验收探针 `tests/scrollverify` 里验，headless 断言会假绿。

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
