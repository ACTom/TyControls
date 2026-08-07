# TTyToolBarEx

## 1. 概述

`TTyToolBarEx` 是 TyControls 库中带**溢出折叠**能力的工具条，继承自 [`TTyToolBar`](toolbar.md)。当工具条**不换行**（`Wrapable = False`）且子按钮的总宽超过工具条可用宽度时，放不下的**尾部按钮**会被隐藏，右端出现一个 `»`（chevron，人字形）按钮；点击它弹出一个 `TTyPopupSurface` 浮层，把这些溢出按钮竖排展示——点击其中任一项**仍然触发它自己的 `OnClick`**（按钮只是被临时移入浮层，从不重新创建）。

窗口尺寸变化时会自动重新计算哪些按钮放得下，并相应显示 / 隐藏 `»` 按钮——**没有**任何 published 属性来手动开关 chevron（完全自动）。`Wrapable = True` 时行为与基类 `TTyToolBar` **完全一致**（跳过整个溢出路径，直接走基类换行布局），只有非换行的溢出路径是新增的。

典型用途：主窗口 / 编辑器顶部命令栏，宽度不足时把次要命令收进 `»` 菜单，而不是换行占用竖向空间。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ToolBarEx` |
| `GetStyleTypeKey` 返回值 | `'TyToolBar'`（**继承自基类，刻意复用**——不引入任何新 `.tycss` 选择器） |
| 基类 | `TTyToolBar`（→ `TTyCustomControl` → `TCustomControl`） |
| 默认尺寸 | 300 × 30（逻辑像素，继承自基类） |
| 默认 `Wrapable` | **`False`**（与基类不同——溢出是本控件的卖点，默认进入其生效的非换行模式） |

工具条本体、`»` 按钮、溢出浮层都对应选择器前缀 `TyToolBar`（浮层复用工具条的主题表面与边框色）。

```pascal
uses tyControls.ToolBarEx, tyControls.Button;
```

---

## 3. 属性表

`TTyToolBarEx` **不新增任何 published 属性**——它复用基类 [`TTyToolBar` 的全部属性](toolbar.md#3-属性表)（`ButtonHeight` / `ButtonSpacing` / `Indent` / `Wrapable` / `ShowCaptions` / `Flat` / `Images`（`TTyImageCollection`）/ `Align` / `Anchors` / `StyleClass` / `Controller` 等）。唯一区别是本控件把 `Wrapable` 重新 published 了一次以声明其新默认值语义（默认 `False`）。

`ShowCaptions` 与 `Images` 在这里同样生效：它们由基类在**工具项加入工具条时**（`InsertControl`）和两个 setter 里下发，
不依赖排布过程——而本控件重写了 `AlignControls`，正好绕开排布路径，所以这条下发时机是它能拿到图标的原因。

> **例外：`Flat` 在本控件上仍然整体覆写子按钮的 `StyleClass`。** 基类已改成只动它自己设过的那一份
> （空串 ↔ `'ghost'`），但本控件重写的 `AlignControls` 里还是无条件赋值，于是宿主写的
> `StyleClass := 'primary'` 会在下一次重排时被抹掉。要在 `TTyToolBarEx` 上做自定义按钮变体，
> 请改走主题选择器（见 [glyphbuttons.md 第 5 节](glyphbuttons.md#5-状态与主题)）。

### 3.1 溢出相关（非 published，供代码 / 测试查询）

| 成员 | 类型 | 说明 |
|------|------|------|
| `OverflowCount` | `function: Integer` | 当前被折进 `»` 浮层的按钮数（`0` = 全部放得下 / 正在换行模式）。 |
| `OverflowVisible` | `function: Boolean` | 当前 `»` chevron 是否显示。 |

> `»` chevron 是一个内部 `TTyButton`（由工具条 `Owner`，带 `csNoDesignVisible`，`StyleClass = 'ghost'`），**不会**出现在 IDE 设计器的子控件列表里，也**不会**被计入溢出按钮集。溢出集按**子控件（`TControl`）**为键记录；某个子按钮被 `Free` 时经 `Notification(opRemove)` 从集合中剔除，不留悬空指针。

---

## 4. 溢出决策纯函数（可 headless 测试）

```pascal
function TyToolbarOverflowCount(const AButtonWidths: array of Integer;
  AAvailPx, AChevronW: Integer): Integer;
```

给定每个**前导**按钮的宽度（设备像素，从左到右）与工具条可用宽度，返回在需要 `»` 之前放得下的**前导按钮数**：

- 若全部按钮的总宽 `<= AAvailPx`（可用宽度）→ 返回 `Length(AButtonWidths)`，**不需要** chevron；
- 否则在右端预留 `AChevronW` 宽的 chevron，返回剩余空间里放得下的前导按钮数——**始终至少 1**（即使第一个按钮单独就超宽也照样显示）；
- 空数组返回 `0`；`AChevronW` 为负时按 `0` 处理。

此函数是布局 / 溢出决策的**纯核心**，与窗口句柄无关，直接被单元测试逐例覆盖（见 [`tests/test.toolbarex.pas`](../../tests/test.toolbarex.pas) 的 `TToolBarExOverflowTest`）。控件本体只是"薄壳"：`AlignControls` 里调用该 solver 得到可见数，再对每个子控件 `SetBounds` / 设 `Visible`，把尾部溢出者移入浮层。

---

## 5. 事件

`TTyToolBarEx` **无自有专有事件**——与基类一样，命令响应发生在**子按钮**上，请挂接各个子 `TTyButton` 的 `OnClick`。溢出按钮被移入浮层后其 `OnClick` 依旧有效（点击照常触发）。

> 完整基线事件集（Tier A 鼠标 / 通用 + Tier B 键盘 / 焦点，因基类为 `TTyCustomControl`）见 [../events.md](../events.md)。

---

## 6. 状态与主题

- **无新增 `.tycss`：** 复用基类的 `TyToolBar` 规则（背景 / 底部发丝线，见 [toolbar.md 第 5 节](toolbar.md#5-状态与主题)）。
- **`»` chevron：** 一个 `StyleClass = 'ghost'` 的平面 `TTyButton`，外观随 `TyButton.ghost` 主题规则。
- **溢出浮层：** `TTyPopupSurface`，其 `StyleKey := 'TyToolBar'`，因此浮层背景 / 边框直接取工具条的主题表面色——与工具条视觉一致；浮层的定位（`TyPopupPlaceBelow`）、越屏翻转、Esc / 失焦关闭等由 `TTyPopupSurface` 提供。

---

## 7. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.ToolBarEx, tyControls.Button;

TyDefaultController.LoadTheme('themes/light.tycss');

var
  Bar: TTyToolBarEx;
  B: TTyButton;
  i: Integer;
begin
  Bar := TTyToolBarEx.Create(Self);
  Bar.Parent := Self;            // Align 默认 alTop
  Bar.Wrapable := False;         // 默认即 False：进入溢出模式（宽度不足时收进 »）
  Bar.ButtonHeight := 28;
  Bar.ButtonSpacing := 4;

  for i := 1 to 12 do
  begin
    B := TTyButton.Create(Self);
    B.Parent := Bar;             // 关键：父控件是工具条
    B.Width := 72;
    B.Caption := Format('命令 %d', [i]);
    B.OnClick := @ToolClicked;   // 折进 » 浮层后依然触发
  end;
  // 窗口变窄时，放不下的尾部命令自动收进右端的 » 浮层——无需任何额外代码。
end;

procedure TMainForm.ToolClicked(Sender: TObject);
begin
  ShowMessage((Sender as TTyButton).Caption);
end;
```

---

## 8. 注意事项

- **仅非换行模式生效：** 溢出折叠只在 `Wrapable = False` 时发生。设 `Wrapable := True` 时本控件与基类 `TTyToolBar` 表现**逐像素一致**（走基类换行布局，`»` 永不出现）。
- **子控件即工具项：** 把 `TTyButton` 的 `Parent` 设为工具条即可；子按钮只需设 `Width`，高度由 `ButtonHeight` 统一接管（与基类相同）。
- **自动、无开关：** `»` 的显示 / 隐藏由每次重排时的 fit 计算自动决定，没有 published 属性来手动控制它。
- **溢出按钮仍然工作：** 被折进浮层的按钮只是**临时改 `Parent`** 到浮层，控件实例不变——`OnClick` 照常触发；浮层关闭后它们被移回工具条（保持隐藏，直到下次重排重新决定谁放得下）。
- **变宽会恢复：** 每次布局都在**完整按钮集**上重算，因此工具条变宽后先前隐藏的尾部按钮会自动重新显示。
- **`ButtonWidth` 下限也管溢出判定：** 基类的宽度下限（[toolbar.md 3.1](toolbar.md#31-ttytoolbar-自有-published-属性)）经同一个 `EffectiveToolWidth` 进入 fit 计算——判定用的是按钮**将被排布**的宽度，而不是它较窄的自然宽度，否则一个被垫宽的按钮会被误判"放得下"再画到 chevron 底下。由 `TToolBarExControlTest.TestOverflowFitUsesFlooredWidths` 钉住。
- **`»` 不进设计器、不进溢出集：** chevron 是 `csNoDesignVisible` 的内部子控件，在布局扫描中被跳过，不会被误当成一个溢出内容按钮。
- **子按钮释放：** 溢出集按子控件记录，某子按钮被 `Free` 时经 `Notification` 自动剔除。
- **点击浮层里的项 = 真实机器行为：** fit 决策与"哪些按钮被隐藏"的集合是 headless 可测的；`»` 弹出浮层、把按钮移入、路由点击这部分薄壳逻辑需在真实 GUI 上验证。
```
