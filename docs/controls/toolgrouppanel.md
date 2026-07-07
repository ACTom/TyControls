# TTyToolGroupPanel

## 1. 概述

`TTyToolGroupPanel` 是 TyControls 库中的**工具按钮分组面板**，继承自 [`TTyGroupBox`](groupbox.md)。它的外观是一个带标题的圆角边框盒子（复用分组框的主题令牌），内部横向**流式排布**一排工具按钮（`TTyButton`），当一行放不下时**自动换行**到下一行——即一个可以放在 **Ribbon 之外**使用的“Ribbon 分组”式命令盒。

因为继承自 `TTyGroupBox`（进而 `TTyCustomControl`），它**免费获得**：

- 主题化的带标题边框（`RenderTo` / `Paint` / `Caption` / `Alignment`）；
- 标题栏下方的客户区内缩（`AdjustClientRect` 已把 `ClientRect.Top` 下移一个标题带高度）——子按钮直接落在标题下方；
- 真容器能力（`csAcceptsControls`）——IDE 设计期可把子控件拖进面板。

两种填充方式：

- **`AddButton`（代码）**：创建一个 `StyleClass = 'ghost'` 的 `TTyButton` 子控件，流式定位后返回，供调用者继续配置。
- **设计期拖放**：直接把子控件放进面板，下一次重排时进入同一套流式布局。

典型用途：工具箱/命令面板、格式工具组、非 Ribbon 场景下的“分组命令区”。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ToolGroupPanel` |
| `GetStyleTypeKey` 返回值 | `'TyGroupBox'`（**继承自 `TTyGroupBox`，未重写**） |
| 基类 | `TTyGroupBox`（`tyControls.GroupBox`） → `TTyCustomControl` |
| 默认尺寸 | 220 × 92（逻辑像素，`Create` 中设置） |

> **复用 `TyGroupBox` 令牌：** 本控件刻意**不重写** `GetStyleTypeKey`，直接沿用父类的 `'TyGroupBox'`——因此**不新增任何 `.tycss` 规则**，边框/标题带/背景全部走现有分组框主题。内部工具按钮各自解析 `TyButton.ghost` 令牌。

```pascal
uses tyControls.ToolGroupPanel;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Spacing` | `Integer` | `4` | 相邻按钮之间、以及换行后行与行之间的间距（逻辑像素）。写入负值夹紧为 `0`；改变时触发重排。 |
| `ButtonHeight` | `Integer` | `26` | 流式排布时每个按钮统一使用的高度（逻辑像素，宽度保留各按钮自身宽度）。写入 `< 1` 夹紧为 `1`；改变时触发重排。 |

### 自有 public 方法

| 成员 | 签名 | 说明 |
|------|------|------|
| `AddButton` | `function AddButton(const ACaption: string; AOnClick: TNotifyEvent = nil): TTyButton` | 创建一个由本面板 owns、`Parent = Self`、`StyleClass = 'ghost'`、`Height = ButtonHeight` 的 `TTyButton` 子控件，设置标题（可选 `OnClick`），流式定位进客户区并返回。返回的按钮归调用者继续配置。**不**标记 `csNoDesignVisible`——这是用户控件，不是内部辅助控件。 |

### 继承的关键成员（来自 `TTyGroupBox`）

| 成员 | 类型/签名 | 说明 |
|------|------|------|
| `Caption` | `string` | 面板顶部嵌入边框的标题。 |
| `Alignment` | `TAlignment` | 标题在标题带内的水平对齐。 |
| `AdjustClientRect` | `procedure(var ARect)` override | 把客户区顶边下移一个标题带高度（16 逻辑像素 @96ppi），子按钮从标题下方开始排布。 |

### 继承的通用成员（来自 `TTyCustomControl`）

| 属性 | 说明 |
|------|------|
| `StyleClass` | CSS 变体类名（作用于面板自身的 `TyGroupBox` 令牌）。 |
| `Controller` | 关联的样式控制器；`nil` 时回退到全局 `TyDefaultController`。 |
| `Align` / `Anchors` / `Enabled` / `Font` | 标准布局与状态属性。 |

---

## 4. 布局机制

- **流式换行：** 子按钮从客户区左上角起横向排布，每个按钮宽度取自身、高度统一为 `ButtonHeight`；当下一个按钮的右边缘会超出客户区右边界时换到新行（行高 = `ButtonHeight`，行间距 = `Spacing`）。
- **首个不换行：** 一行上的**第一个**按钮永不换行——即使它比整个客户区还宽，也会在当前行获得矩形（溢出而非丢失/死循环）。
- **重排时机：** 每次 `AddButton` 之后、`Spacing` / `ButtonHeight` 改变时、以及父类 `AlignControls`（尺寸变化/`Realign`）时重排。
- **只排 `alNone` 子控件：** 手动流式布局只作用于 `Align = alNone` 的可见子控件；`alTop`/`alClient` 等锚定子控件交给 LCL 的 `inherited AlignControls` 先行处理（与 Ribbon 分组一致）。
- **再入保护：** `SetBounds` 会回环触发 `AlignControls`，内部 `FInLayout` 标志防止重入递归。

---

## 5. 纯布局辅助函数（可单元测试）

单元级导出一个**纯函数**（无控件状态），是流式布局的核心，被测试直接覆盖：

| 函数 | 签名 |
|------|------|
| `TyToolFlowRects` | `function TyToolFlowRects(const AClient: TRect; const AButtonSizes: array of TSize; ASpacing, AButtonHeight: Integer): TTyRectArray` |

给定客户区矩形 `AClient`、各按钮尺寸、间距与统一行高，返回每个按钮的绝对矩形（坐标已折入 `AClient` 原点）：横向左到右排布，右边缘超界时换行；每个矩形保留按钮自身宽度、强制 `AButtonHeight` 高；每行首个按钮不换行。`ASpacing < 0` 视为 `0`，`AButtonHeight < 1` 视为 `1`。

```pascal
var sizes: array[0..2] of TSize; r: TTyRectArray;
sizes[0].cx := 60; sizes[1].cx := 60; sizes[2].cx := 60;   // 三个 60px 按钮
r := TyToolFlowRects(Rect(0, 0, 100, 200), sizes, 4, 26);
// 客户区宽 100 放不下两个 60px -> 每个各占一行:
r[0].Top;   // -> 0
r[1].Top;   // -> 30  (26 + 4)
r[2].Top;   // -> 60
r[1].Left;  // -> 0   (换行回到左边)
```

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.ToolGroupPanel, tyControls.Button;

// 加载主题（通常在窗体 Create 顶部执行一次）
TyDefaultController.LoadTheme('themes/light.tycss');

var Grp: TTyToolGroupPanel;
Grp := TTyToolGroupPanel.Create(Self);
Grp.Parent := Self;
Grp.SetBounds(16, 16, 220, 92);
Grp.Caption := '剪贴板';
Grp.Spacing := 6;
Grp.ButtonHeight := 28;

// 用 AddButton 逐个添加工具按钮（自动流式排布 + 换行）
Grp.AddButton('剪切',   @DoCut);
Grp.AddButton('复制',   @DoCopy);
Grp.AddButton('粘贴',   @DoPaste);
Grp.AddButton('格式刷', @DoFormatPainter);   // 放不下时自动换到第二行

procedure TMainForm.DoCut(Sender: TObject);
begin
  // ...
end;
```

---

## 7. 注意事项

1. **不新增 `.tycss`：** 复用父类 `TyGroupBox` 令牌绘制边框与标题带；主题化时写 `TyGroupBox` 选择器即可，`.tycss` 中不存在 `TyToolGroupPanel`。内部按钮走 `TyButton.ghost`。
2. **子按钮是用户控件：** `AddButton` 创建的按钮**不**标记 `csNoDesignVisible`——本控件是真容器，不是自动填充的辅助控件族（对比 `TTyRadioGroup` 一类的隐藏子控件）。因此它们会正常出现在 IDE 设计器中。
3. **客户区自动内缩：** 继承 `TTyGroupBox.AdjustClientRect`，子按钮从标题带下方开始排布，`ClientRect` 已内缩，无需手动加顶部偏移。
4. **换行按客户区宽度：** 流式布局以 `ClientRect` 宽度为界；面板变窄会触发换行、变宽会回流。行高恒为 `ButtonHeight`。
5. **`ButtonHeight` 统一高度：** 所有流式按钮高度被强制为 `ButtonHeight`（宽度各自保留）；单独改某按钮的 `Height` 会在下次重排时被覆盖。
6. **首个按钮不换行：** 超宽的单个按钮会溢出当前行而非丢失或死循环。

---

参见 [[TTyGroupBox]]（父类，提供带标题边框 + 客户区内缩）与 [[TTyButton]]（流式子按钮，复用其 `ghost` 变体主题）。
