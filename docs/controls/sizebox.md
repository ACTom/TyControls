# TTySizeBox

## 1. 概述

TTySizeBox 是 TyControls 库中的主题化**尺寸手柄（size grip）**控件，继承自 `TTyGraphicControl`。它在自身右下角绘制一组经典 Windows 风格的**对角点阵握把**（3/2/1 三角形排列的 6 个立体小方点），按住鼠标左键在握把区域拖动，即可按鼠标位移实时调整其 `Target`（一个 `TControl`）的宽高。典型用途：放在无边框窗体（`TTyForm`）或面板的右下角，提供一个可视化的、可拖拽的窗口/面板缩放入口——正是很多状态栏右端那个“搓衣板”手柄。默认尺寸约 16×16，鼠标指针在握把上显示 `crSizeNWSE`（西北—东南双向箭头）。

握把点颜色**不硬编码**：从当前解析样式的 `border-color`（若无则 `color`）派生出高光（`TyLighten`）与阴影（`TyDarken`）两层，因此更换主题即换色。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.SizeBox` |
| `GetStyleTypeKey` 返回值 | `'TySizeBox'`（**自有 typeKey**） |
| 基类 | `TTyGraphicControl`（继承自 `TGraphicControl`，无窗口句柄、不能作父容器） |

在 `.tycss` 文件中，该控件对应选择器 `TySizeBox`（背景/边框/文字令牌）。

它从前返回 `'TyPanel'`：点阵握把根本不是面板会画的东西，而借用面板键意味着主题层完全够不着它——想调握把只能连带重涂全应用的面板。现在 `TySizeBox` 已作为附加选择器并入主题里 `TyPanel` 的规则块，解析值与从前逐字节相同，**开钩子而不动像素**；第三方主题若只覆盖了 `TyPanel`，需要补上 `TySizeBox`（主题层按 typeKey 全有全无地回落，否则会掉回内置 light 取值）。

### 子部件 typeKey

**没有。** 6 个握把点不是可单独寻址的子部件：它们的高光/阴影色在代码里从上面那个盒子样式派生（`TyLighten(seed, 55)` / `TyDarken(seed, 30)`），点边长/间距/内边距（逻辑 2 / 4 / 3 px）也是 Pascal 常量而非主题 metric。子部件键与相应 metric（`TySizeBoxDot`、`--sizebox-dot-size` / `-step` / `-pad`）的扩展已被**刻意推迟**，这些名字当前**并不存在**，写进 `.tycss` 解析不到任何东西。

```pascal
uses tyControls.SizeBox;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Target` | `TControl` | `nil` | 拖动握把时被缩放的控件。为 `nil` 时按顺序回退：**拥有者窗体**（`Owner` 若为 `TCustomForm`）→ **父控件**（`Parent`）。赋值时登记 `FreeNotification`，目标被释放时自动置 `nil`（见第 7 节） |

### 继承的通用成员

TTySizeBox 继承自 `TTyGraphicControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点（右下角手柄通常设 `[akRight, akBottom]`） |
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分 |
| `StyleOverride` | `string` | `''` | 逐实例 CSS 声明块，叠加在主题之上，可引用 `var(--...)` |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器 |

**状态跟踪字段（private/protected，不 published）：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `FDragging` | `Boolean` | 在握把命中区按下左键后为 `True`，`MouseUp` 复位 |
| `FMouseStart` | `TPoint` | 拖动起点的鼠标**屏幕**坐标（1:1 跟随，屏幕偏移在求 delta 时相互抵消） |
| `FStartW` / `FStartH` | `Integer` | 拖动开始时目标控件的宽 / 高 |

**构造时默认值：** `Width = 16`，`Height = 16`，`Cursor = crSizeNWSE`。

---

## 4. 纯几何函数（单元级，无需窗口句柄，可直接单测）

本控件的价值在于**正确的几何**。以下三个单元级函数是握把的绘制与命中判定基础，均为纯计算，测试直接调用：

| 函数 | 签名 | 说明 |
|------|------|------|
| `TySizeGripDots` | `(const ARect: TRect; APPI: Integer): TTyRectArray` | 返回握把 6 个点的矩形（设备像素），锚定在 `ARect` 右下角，按 3/2/1 对角三角阵排列；点边长/间距/内边距随 `APPI` 缩放（逻辑 2 / 4 / 3 px） |
| `TySizeGripHit` | `(const ARect: TRect; APPI: Integer; const APt: TPoint): Boolean` | 判定 `APt` 是否落在握把命中区——右下角、且在反对角线以内（`dxFromRight + dyFromBottom <= 3*step + pad`）；命中区随 `APPI` 放大 |
| `TySizeApplyDelta` | `(AStartW, AStartH, ADx, ADy, AMinW, AMinH: Integer): TSize` | 纯算术：`(起始尺寸 + 位移)` 后按最小值钳制；`AMinW/AMinH <= 0` 视为 `1`（控件永不塌陷到 0） |

> 实际的 `SetBounds`（拖动落地）属于交互路径，需真机验证；上述几何函数则完全 headless 可测。

---

## 5. 事件

TTySizeBox 未在 `published` 节声明专有事件；作为 `TTyGraphicControl`，它暴露 **Tier A 基线鼠标/通用事件**（`OnMouseDown`/`OnMouseUp`/`OnMouseMove`/`OnClick` 等，完整清单见 [../events.md](../events.md)）。缩放逻辑内建于 `MouseDown`/`MouseMove`/`MouseUp`，不经外部事件。

---

## 6. 状态与主题

### 支持的伪类状态

沿用 `TTyGraphicControl` 的基础状态机制（`:hover` / `:active` / `:disabled`）。具体着色由主题的 `TySizeBox` 规则决定。

### 渲染细节

`RenderTo` 先走 `DrawFrame` 路径（应用 `TySizeBox` 的 `background`/`border`，若主题设了的话），再在右下角绘制握把点阵：

1. **颜色派生（主题驱动，不硬编码）**：种子色取 `border-color`（`tpBorderColor in Present`）否则取 `color`（`TextColor`）；高光 = `TyLighten(seed, 55)`，阴影 = `TyDarken(seed, 30)`。
2. **立体点**：先在每个点右下偏移 `+1` 设备像素处画阴影方点，再在原位画高光方点，形成经典“凸起/雕刻”观感。
3. 点阵位置、边长、间距全部经 `MulDiv(logical, APPI, 96)` 做 DPI 缩放。

> 若不希望握把带背景框，在主题里给 `TySizeBox` 设 `background: none; border-width: 0px;` 即可——握把点阵仍会绘制，颜色从 `border-color`/`color` 派生。这条规则只作用于本控件，不会波及任何面板。

---

## 7. 代码示例

```pascal
uses
  Forms, tyControls.Controller, tyControls.SizeBox, tyControls.StatusBar;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

var
  Grip: TTySizeBox;
begin
  // 放在窗体右下角，锚定右/下，随窗口伸缩始终贴角
  Grip := TTySizeBox.Create(Self);
  Grip.Parent := Self;
  Grip.Anchors := [akRight, akBottom];
  Grip.SetBounds(ClientWidth - 16, ClientHeight - 16, 16, 16);
  // 缺省即缩放拥有者窗体（Self 为 TCustomForm）；也可显式指定：
  // Grip.Target := SomePanel;
end;
```

拖动时缩放遵守目标的 `Constraints`：新宽高会被钳制到 `MinWidth`/`MinHeight`（下界）与 `MaxWidth`/`MaxHeight`（上界，`0` 表示不限）。

---

## 8. 注意事项

- **自有 typeKey：** `GetStyleTypeKey` 返回 `'TySizeBox'`。要单独把握把做扁平（去框、去 3D），改 `TySizeBox` 规则；**不要**去改 `TyPanel`——那会重涂全应用的面板。
- **颜色必须主题驱动：** 高光/阴影两层都由 `border-color`（或 `color`）经 `TyLighten`/`TyDarken` 派生，切勿在控件代码里写死颜色；换主题即换握把色。两个混合量（55 / 30）以及 +1 设备像素的阴影偏移目前仍是代码字面量，主题改不了。
- **Target 回退顺序：** `nil` → 拥有者窗体（`Owner is TCustomForm`）→ `Parent`。若既无窗体拥有者也无父控件，拖动无效果（安全 no-op）。
- **仅在握把命中区起拖：** `MouseDown` 先用 `TySizeGripHit` 判定命中，只有落在右下三角握把区才开始拖动；点在左上等区域按下不触发缩放。
- **屏幕坐标测 delta：** 记录 `FMouseStart` 为屏幕坐标，拖动时以屏幕坐标求位移——容器随缩放在指针下伸缩时仍 1:1 跟随（本地坐标会漂移）。
- **目标释放安全：** `Target` 赋值时登记 `FreeNotification`；目标被 `Free` 时 `Notification` 把 `FTarget` 置 `nil`，不留悬垂引用。
- **图形控件、非容器：** 继承自 `TGraphicControl`，无窗口句柄，不能作为其它控件的 `Parent`；它只负责“画握把 + 拖动缩放目标”。
- **约束钳制：** 拖动结果经 `TySizeApplyDelta`（下界）与显式的 `Constraints.MaxWidth/MaxHeight`（上界）双向钳制；`TySizeApplyDelta` 还把 `<=0` 的最小值兜底为 `1`。
