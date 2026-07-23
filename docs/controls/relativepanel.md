# TTyRelativePanel — API 参考

## 1. 概述

`TTyRelativePanel` 是 TyControls 库中的**相对布局容器**，继承自 [`TTyPanel`](panel.md)，风格对标 Android `RelativeLayout` / WinUI `RelativePanel`。它托管任意子控件，每个子控件通过一组**规则**声明自己相对于**兄弟控件**或**父容器**的摆放方式，容器在 `Resize`（以及规则变化后）自动求解每个子控件的 `Left/Top` 并 `SetBounds`。

核心价值是一套**纯布局数学**：把子控件的规则集拓扑排序后逐个定位，被引用的兄弟先定位、再定位引用它的子控件；对**依赖环**做了保护（环中的子控件回退到父容器原点，永不死循环）。这套求解逻辑以纯函数 `TyRelativeSolve` 暴露，可脱离窗口句柄直接单元测试。

它是**真正的 LCL 容器**（有窗口句柄，`csAcceptsControls`），子控件直接以其为 `Parent`。外观、边框、圆角、内边距全部沿用 `TyPanel` 主题——它自己一个像素都不画，因此**刻意不设独立 typeKey**（理由见第 2 节）。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.RelativePanel` |
| `GetStyleTypeKey` 返回值 | `'TyPanel'`（**刻意借用**，见下） |
| 基类 | `TTyPanel`（继承自 `TTyCustomControl` → `TCustomControl`） |
| 默认尺寸 | 240 × 160（逻辑像素） |

```pascal
uses tyControls.RelativePanel;
```

> **为什么这个借用是对的：** 2026-07 的 typeKey 审计把 51 个借别人键的控件改成了各自持有自己的键，`TTyRelativePanel` 是**明确判定为不该改**的三个之一。它**一个像素都不自己画**——整个单元里没有 `Paint`、没有 `RenderTo`，全部输出来自 `TTyPanel.RenderTo`；它的全部内容是纯求解器 `TyRelativeSolve` 加 `PerformLayout` 里的 `SetBounds`。也就是说它**就是一个面板**：同样的框、同样的可选标题、同样的内边距，差别只在**布局策略**——而布局策略不是皮肤需要区分的视觉身份。给它一个独立的键，只会造出一个任何渲染差异都分辨不出来的选择器。
>
> 同类仍然借用 `TyPanel` 的还有 [`TTyPaintPanel`](paintpanel.md)（它是面板，只是把画笔交给了调用方）。**注意：[`TTyScrollBox`](scrollbox.md) 已经不再是同类**——它现在有自己的 `TyScrollBox` 键（滚动井的观感与面板相反），别再拿它当"刻意借用"的例子。
>
> 因此：在 `.tycss` 中给 `TyPanel` 写的规则（`background` / `border` / `radius` / `padding` …）都会作用到它，这是预期行为。子控件的定位以「内容区」（本体扣除主题 `padding` 后的内部矩形）为坐标系原点。
>
> **子部件 typeKey：没有。** 本控件不绘制任何子部件。

---

## 3. 规则模型

一个子控件的规则集是一个 `TTyRelativeRules`（`set of TTyRelativeRule`）。规则分四类：

### 3.1 相对兄弟——位置（把本控件摆到兄弟旁边，位置规则会插入 `Spacing` 间距）

| 规则 | 含义 |
|------|------|
| `trRightOf` | 本控件左边界 = 兄弟右边界 + `Spacing` |
| `trLeftOf` | 本控件右边界 = 兄弟左边界 − `Spacing`（即 `Left = 该值 − Width`） |
| `trBelow` | 本控件上边界 = 兄弟下边界 + `Spacing` |
| `trAbove` | 本控件下边界 = 兄弟上边界 − `Spacing`（即 `Top = 该值 − Height`） |

### 3.2 相对兄弟——边对齐（与兄弟共享同一条边，**不**加间距）

| 规则 | 含义 |
|------|------|
| `traAlignLeftOf` | `Left` = 兄弟 `Left` |
| `traAlignRightOf` | `Right` = 兄弟 `Right`（`Left = 兄弟Right − Width`） |
| `traAlignTopOf` | `Top` = 兄弟 `Top` |
| `traAlignBottomOf` | `Bottom` = 兄弟 `Bottom`（`Top = 兄弟Bottom − Height`） |

### 3.3 相对父容器——边对齐

| 规则 | 含义 |
|------|------|
| `traAlignParentLeft` | 贴内容区左边 |
| `traAlignParentRight` | 贴内容区右边（`Left = 右边 − Width`） |
| `traAlignParentTop` | 贴内容区上边 |
| `traAlignParentBottom` | 贴内容区下边（`Top = 下边 − Height`） |

### 3.4 居中

| 规则 | 含义 |
|------|------|
| `traCenterHorizontal` | 在父容器内水平居中 |
| `traCenterVertical` | 在父容器内垂直居中 |
| `traCenterInParent` | 水平 + 垂直都居中 |

> **优先级（同一坐标轴内，后者覆盖前者）：** 父容器原点 → 父容器边对齐 → 居中 → 兄弟边对齐 → 兄弟位置。因此若同时给出 `traAlignLeftOf` 与 `trRightOf`，最终以 `trRightOf`（位置规则）为准。水平与垂直两轴相互独立，可自由组合（例如「`trRightOf` 兄弟 + `traAlignParentTop`」）。

---

## 4. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Spacing` | `Integer` | `8` | 位置规则（`trRightOf/trLeftOf/trBelow/trAbove`）在兄弟之间插入的间距（px）。**边对齐 / 父对齐规则不受此值影响。** 修改后自动重排。 |

### 继承自 TTyPanel / TTyCustomControl 的 published 成员

| 属性 | 类型 | 说明 |
|------|------|------|
| `Align` | `TAlign` | 父容器内停靠方式；常设 `alClient`。 |
| `Anchors` | `TAnchors` | 锚点布局。 |
| `StyleClass` | `string` | CSS 类名，对应 `.tycss` 中 `TyPanel.classname` 选择器。 |
| `Controller` | `TTyStyleController` | 指定样式控制器（`nil` = 全局 `TyDefaultController`）。 |

---

## 5. 方法

| 方法 | 说明 |
|------|------|
| `procedure SetRules(AControl: TControl; ARules: TTyRelativeRules; AAnchor: TControl = nil)` | 为 `AControl`（本容器的子控件）**赋予 / 替换**规则集。`AAnchor` 是兄弟类规则引用的**兄弟控件**（仅用父 / 居中规则时传 `nil`）。传入**空规则集**等价于清除该子控件的规则。会立即重排。 |
| `function GetRules(AControl: TControl): TTyRelativeRules` | 取回 `AControl` 的规则集（无则空集）。 |
| `function GetAnchor(AControl: TControl): TControl` | 取回 `AControl` 的锚点兄弟（无则 `nil`）。 |
| `procedure ClearRules(AControl: TControl)` | 彻底移除 `AControl` 的规则（此后它保持自身位置）。 |
| `procedure PerformLayout` | **核心方法。** 重新求解并摆放所有有规则的子控件。`Resize` 及每次规则 / `Spacing` 变化时自动调用；**你在代码中移动 / 改变子控件尺寸后**，手动调一次即可刷新。 |
| `function RuledChildCount: Integer` | 当前携带规则集的子控件数量。 |

> **每个子控件保留自身的 `Width/Height`：** 求解器只计算 `Left/Top`，从不改动子控件尺寸。没有规则的子控件保持它自己的位置。

---

## 6. 求解机制（拓扑排序 + 环保护）

1. **依赖顺序求解：** 引用了兄弟的子控件，一定在**被引用的那个兄弟**摆好之后才摆放。求解器反复做「就绪扫描」——每一轮摆放所有「无兄弟依赖，或兄弟已摆好」的子控件，直到全部就位。
2. **环保护（永不死循环）：** 若某一轮一个都摆不动却仍有剩余，说明它们构成依赖环（A 依赖 B、B 依赖 A）。这些子控件被**强制回退**到父容器原点：它们的**兄弟规则被丢弃**，但父对齐 / 居中规则仍然生效。
3. **未知锚点：** 若锚点 id 指向一个不存在的子控件（例如兄弟已被销毁），该子控件的兄弟规则被忽略（视作无兄弟），父 / 居中规则仍生效。
4. **自引用：** 一个子控件以自身为锚点不构成依赖，其自指的兄弟规则被跳过。

---

## 7. 纯函数（单元级，可 headless 测试）

单元 `tyControls.RelativePanel` 导出布局求解核心：

```pascal
function TyRelativeSolve(const AItems: TTyRelativeItemArray;
  const AParent: TRect; ASpacing: Integer): TTyRelativePosArray;
```

- **输入** `AItems`：每项含 `Id`（本项 id）、`W/H`（期望尺寸）、`Rules`（规则集）、`AnchorId`（兄弟类规则引用的兄弟 id，`-1` = 无兄弟）。
- **输入** `AParent`：内容矩形（通常是扣除 `padding` 后的内部区域），求解结果以它的左上角为坐标基准。
- **输入** `ASpacing`：位置规则的间距。
- **输出**：与 `AItems` 等长、同序的 `TTyRelativePosArray`，每项给出求解出的 `Left/Top`。

该函数**确定性**、**环安全**、不依赖任何控件，可直接在 fpcunit 中穷举验证（链式定位、四边父对齐、父内居中、兄弟边对齐、2 项 / 3 项环回退、未知锚点忽略、自引用忽略等）。

---

## 8. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.RelativePanel, tyControls.Button;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

var
  RP: TTyRelativePanel;
  BtnOK, BtnCancel, Title: TTyButton;
begin
  RP := TTyRelativePanel.Create(Self);
  RP.Parent := Self;
  RP.Align := alClient;
  RP.Spacing := 12;

  // 标题：顶部居中
  Title := TTyButton.Create(RP);  Title.Parent := RP;  Title.SetBounds(0, 0, 120, 28);
  RP.SetRules(Title, [traCenterHorizontal, traAlignParentTop]);

  // 「取消」按钮：贴右下角
  BtnCancel := TTyButton.Create(RP);  BtnCancel.Parent := RP;
  BtnCancel.SetBounds(0, 0, 90, 32);
  RP.SetRules(BtnCancel, [traAlignParentRight, traAlignParentBottom]);

  // 「确定」按钮：放在「取消」左侧、并与其顶端对齐
  BtnOK := TTyButton.Create(RP);  BtnOK.Parent := RP;
  BtnOK.SetBounds(0, 0, 90, 32);
  RP.SetRules(BtnOK, [trLeftOf, traAlignTopOf], BtnCancel);

  // 若之后用代码改动了子控件尺寸，手动刷新一次
  RP.PerformLayout;
end;
```

---

## 9. 注意事项

- **规则数据按子控件（`TControl`）为键存储：** 每个子控件的规则集与锚点存在一张内部列表里，以控件实例为键。子控件被 `Free` 时通过 `FreeNotification/Notification` 自动删除其条目；若被销毁的是**别人的锚点**，引用它的子控件会丢掉锚点（兄弟规则随之回退到父原点），但保留其余父 / 居中规则。
- **增删 / 移动子控件后调 `PerformLayout`：** 控件仅在 `Resize`、规则变化、`Spacing` 变化时自动重排。运行时用代码 `SetBounds` 改了子控件尺寸后，调一次 `PerformLayout` 才能让依赖它的兄弟跟随更新。
- **锚点必须是本容器的子控件：** `SetRules` 的 `AAnchor` 应当是同一 `TTyRelativePanel` 下、且已通过 `SetRules` 登记过的兄弟；否则该兄弟不在求解输入里，兄弟规则会被当作「未知锚点」忽略。
- **空规则集 = 清除：** `SetRules(child, [])` 等价于 `ClearRules(child)`，该子控件此后保持自身位置。
- **不做尺寸自适应：** 与 `TTyPanel` 一致，容器不会根据子控件内容自动改变自身或子控件的大小；求解器只摆放位置。
- **刻意借用 `TyPanel` 主题：** 本控件自己不画任何东西，共用面板的键是有意为之（见第 2 节）；因此改 `TyPanel` 样式会同时影响普通面板与相对布局面板。需要区分时用 `StyleClass` 加类选择器（如 `TyPanel.form { … }`）——这是本控件**唯一**的区分手段，它没有自己的 typeKey 可写。
```
