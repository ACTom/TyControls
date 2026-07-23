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
| `procedure UpdateScrollRange` | **核心公开方法。** 重新测量子控件包围盒，据此显示 / 隐藏 / 定位两个滚动条，并把滚动偏移夹取到合法范围。控件在 `Resize`（尺寸变化）时会自动调用；**当你在代码中增删子控件、或改变子控件位置 / 大小后，需手动调用一次**，让滚动范围与滚动条同步刷新。 |

---

## 5. 滚动机制

1. **滚动范围** = 全部非滚动条子控件在**逻辑（未滚动）坐标**下的包围盒。每个子控件的逻辑坐标 = 其当前 `Left/Top`（已被滚动平移过）+ 当前偏移 `FScrollX/FScrollY`。范围从视口原点 `(0,0)` 量到内容最远的右 / 下边界。
2. **滚动条可见性**：某一轴的 `内容尺寸 > 视口尺寸` 时才显示该轴滚动条。两条滚动条互相影响——显示垂直条会占掉水平方向的可用宽度，可能进而需要水平条（反之亦然），`UpdateScrollRange` 内部对这种相互依赖做了二次判定。
3. **拖动滚动条**：在滚动条 `OnChange` 中，计算新目标偏移与当前偏移的差值 `dx/dy`，调用 `inherited ScrollBy(-dx, -dy)` 平移**所有**子控件；由于 `ScrollBy` 也会移动那两个内嵌滚动条，随后把它们重新吸附回右 / 下边缘，并提交新的偏移值。
4. **鼠标滚轮**：优先滚动溢出的垂直轴（无垂直溢出时滚动水平轴），每格约一个滚动条厚度的内容距离。

> **无窗口句柄下的行为（headless / 测试）：** 纯滚动数学（范围 / 夹取 / 可见性阈值 / 缩略块 PageSize）是单元级纯函数，可直接验证；子控件实际平移由 `ScrollBy` 完成，在真实 GUI 中生效。

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

// 代码增删 / 移动子控件后，手动刷新一次滚动范围
Box.UpdateScrollRange;
```

---

## 8. 注意事项

- **子控件不受 padding 约束：** 与 `TTyPanel` 一致，`padding` 只影响本体绘制，不自动约束子控件布局；子控件坐标需自行设置。
- **增删子控件后要调 `UpdateScrollRange`：** 控件仅在 `Resize` 时自动重算范围。在运行时用代码 `Create` / `Free` / `SetBounds` 改动子控件后，调用一次 `UpdateScrollRange` 才能让滚动条即时反映新内容。
- **两个滚动条是内部子控件：** 它们由滚动框自身拥有并创建，标记为 `csNoDesignVisible`，不会出现在 IDE 设计器的子控件列表里，也不会被流式化。请勿在设计器里手动摆放滚动条。
- **`Controller` 自动传播：** 给滚动框设置 `Controller` 后，两个内嵌滚动条会在下次 `UpdateScrollRange` 时继承同一控制器，保证主题一致。
- **偏移永远非负：** `ScrollX/ScrollY` 始终 `≥ 0`，且被夹取在 `[0, 内容-视口]`；当宿主放大到内容可完整容纳时，偏移自动归零、滚动条自动隐藏。
- **有自己的主题键：** 滚动框走 `TyScrollBox`，与 `TyPanel` 互不影响。要让滚动井下沉（例如更深的底色、无圆角、内描边），直接写 `TyScrollBox { … }`——**不要**改 `TyPanel`，那会重涂全应用的面板。旧文档建议的 `StyleClass` 变通（`TyPanel.scroll`）已经过时，只在需要同一控件的多种变体时才用得上。
