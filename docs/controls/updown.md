# TTyUpDown

## 1. 概述

TTyUpDown 是**独立的上/下微调按钮对**,继承自 `TTyGraphicControl`。点一下按钮把 `Position` 按 `Increment` 步进;**按住自动连发**(先一段延迟,再快速重复)。竖排(默认)上按钮在上、下按钮在下;横排则下按钮在左、上按钮在右。它自身不含编辑框——通过 `OnChange` 读 `Position`,可绑定到任意控件(编辑框、标签等)。复用 `TyButton` 主题,无新增 `.tycss`。

> 若要"编辑框 + 内置上下箭头"的一体控件,用 [TTySpinEdit](spinedit.md);TTyUpDown 是**分离**的按钮对。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.UpDown` |
| `GetStyleTypeKey` 返回值 | `'TyButton'`(复用按钮框 / 背景 / 边框 / 文字)|

复用 `TTyButton` 主题规则(含 `:hover` / `:active`),无新增 `.tycss`。

```pascal
uses tyControls.UpDown;
```

---

## 3. 属性表

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Min` | `Integer` | `0` | 下限。 |
| `Max` | `Integer` | `100` | 上限。 |
| `Position` | `Integer` | `0` | 当前值(夹紧到 `[Min,Max]`)。 |
| `Increment` | `Integer` | `1` | 每步增量(下限 1)。 |
| `Orientation` | `TTyUpDownOrientation` | `udoVertical` | `udoVertical` / `udoHorizontal`。 |
| `Wrap` | `Boolean` | `False` | 越界时是否回绕到另一端(而非停在边界)。 |
| `OnChange` | `TNotifyEvent` | — | `Position` 变化时触发。 |

继承:`Align` / `Anchors` / `StyleClass` / `Controller`。

---

## 4. 事件

| 事件 | 说明 |
|------|------|
| `OnChange` | `Position` 改变(点击 / 连发 / 代码设值)后触发。 |

---

## 5. 状态与主题

复用 `TyButton`。**渲染**:整体一个 `DrawFrame` 画框 + 背景 + 边框,中间一条边框色分隔线,两半各画一个箭头字形;被 hover / 按下的那一半用 `TyButton:hover` / `:active` 的背景色叠加高亮。

---

## 6. 代码示例(绑定到一个编辑框)

```pascal
uses tyControls.Controller, tyControls.UpDown, tyControls.Edit;

var Ud: TTyUpDown; Ed: TTyEdit;
Ed := TTyEdit.Create(Self); Ed.Parent := Self; Ed.SetBounds(20, 20, 60, 26);
Ud := TTyUpDown.Create(Self); Ud.Parent := Self; Ud.SetBounds(82, 20, 22, 26);
Ud.Min := 0; Ud.Max := 20; Ud.Position := 5;
Ud.OnChange := @UpDownChanged;   // 在处理器里:Ed.Text := IntToStr(Ud.Position);
```

---

## 7. 注意事项

- **分离 vs 一体:** 一体式数值框用 [TTySpinEdit](spinedit.md);需要把上下按钮贴到别处(如自定义布局)时用 TTyUpDown。
- **自动连发:** 按住某一半会先延迟 ~0.4s 再以 ~60ms 间隔连续步进,松开 / 移出即停。
- **纯逻辑可测:** 半区命中 `TyUpDownHit`、半区矩形 `TyUpDownButtonRect`、夹紧 / 回绕 `TyUpDownClamp` 都是纯函数,已单元测试(`test.updown`)。
- **主题驱动:** 颜色取自 `TyButton`,不硬编码。
