# TTyUpDown

## 1. 概述

TTyUpDown 是**独立的上/下微调按钮对**,继承自 `TTyGraphicControl`。点一下按钮把 `Position` 按 `Increment` 步进;**按住自动连发**(先一段延迟,再快速重复)。竖排(默认)上按钮在上、下按钮在下;横排则下按钮在左、上按钮在右。它自身不含编辑框——通过 `OnChange` 读 `Position`,可绑定到任意控件(编辑框、标签等)。typeKey 是它自己的 `'TyUpDown'`。

> 若要"编辑框 + 内置上下箭头"的一体控件,用 [TTySpinEdit](spinedit.md);TTyUpDown 是**分离**的按钮对。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.UpDown` |
| `GetStyleTypeKey` 返回值 | `'TyUpDown'`(**自有键**:外框 / 背景 / 边框 / 箭头墨色 / 中缝分隔线)|

从前它返回 `'TyButton'`,于是「一个命令按钮」和「一个附在字段旁的微调器」在主题层无法区分:皮肤
给按钮做个 accent 填充的悬停态,微调器就有半边被涂成强调色,而皮肤没有任何选择器能把它们分开。
`themes/light.tycss` 把 `TyUpDown` 并列写进了 `TyButton` 那条规则的选择器列表,所以默认外观与从前
一致;要调它请写 `TyUpDown`,**不要**改 `TyButton` —— 那会改掉全应用的每一个按钮。

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

### 解析的主题键

| typeKey | 画什么 |
|---------|--------|
| `TyUpDown` | 整个控件的普通态:`DrawFrame` 的背景 + 边框 + 圆角、两个箭头字形的墨色(取 `color`),以及两半之间那条中缝分隔线(取 `border-color`,厚度 = `border-width`)。 |
| `TyButton` | **仅**悬停 / 按下那一半的背景叠加色。见下方提醒。 |

**没有子部件键。** 上下两半没有各自的 typeKey——形如 `TyUpDownButton` 的键**并不存在**(子部件拆键
属于本轮有意推迟的扩展,别往主题里写)。箭头也不走图标字体覆盖:本控件直接调 `P.DrawGlyph`,因此
`--glyph-arrow-up` / `--glyph-arrow-down` 这类令牌(`TTySpinEdit` 认)在这里**不生效**,箭头笔画粗细
也是代码字面量 `3`。

> **状态背景仍读 `TyButton`(现状,非设计):** `Paint` 中给悬停 / 按下的那一半叠背景时,代码写的是
> `ResolveStyle('TyButton', StyleClass, states)` —— 唯一一处没有跟着换成自有键的地方。也就是说
> `TyUpDown:hover` / `TyUpDown:active` 的 `background` **画不出来**,那半边的高亮色仍由
> `TyButton:hover` / `TyButton:active` 决定。除背景外的一切(外框、边框、中缝、箭头墨色)都已走
> `TyUpDown`。要改半边高亮色,眼下只能改 `TyButton` 的状态背景(会波及全应用按钮)。

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
- **主题驱动:** 颜色取自 `TyUpDown`,不硬编码;唯一例外是悬停 / 按下半边的背景仍解析 `TyButton`(见第 5 节)。
- **`:disabled` 在随库主题下不变淡:** `light` / `dark` / `auto` 的 `:disabled` 选择器列表里没有 `TyUpDown`,而主题一旦定义过某 typeKey,内置基础层对该键就整体不再兜底,所以禁用时不会降透明度。需要就在自己的主题里补一条 `TyUpDown:disabled { opacity: var(--disabled-opacity); }`(`green.tycss` 与 `aero` / `bootstrap` / `office` / `xp` 四套 builtin 已有)。
