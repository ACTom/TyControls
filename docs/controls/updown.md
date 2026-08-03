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
| `Wrap` | `Boolean` | `False` | 越界时是否回绕到另一端(而非停在边界)。**回绕会带着溢出量继续走,不丢弃**:`Min=0` / `Max=10` / `Increment=4` 时从 9 往上一步得 **2**(9→10→0→1→2),而不是直接跳到 `Min`。早前是直接贴到对端,于是步长大于 1 的回绕微调器悄悄从"加法器"变成了"复位钮"。 |
| `OnChange` | `TNotifyEvent` | — | `Position` 变化时触发。 |
| `OnArrowClick` | `TTyUpDownClickEvent` | — | **(API parity 新增)** 每一"步"触发一次,并告诉你按的是哪半边:`procedure(Sender: TObject; AButton: TTyUpDownButton) of object`,`AButton` 取 `udbPrev`(下 / 减)或 `udbNext`(上 / 加)。 |

继承:`Align` / `Anchors` / `StyleClass` / `Controller`。

---

## 4. 事件

| 事件 | 说明 |
|------|------|
| `OnChange` | `Position` 改变(点击 / 连发 / 代码设值)后触发。 |
| `OnArrowClick` | **每一步**触发一次(含按住时的每一次连发 tick,与 LCL `TUpDown.OnClick` 一致),并带上方向 `udbPrev` / `udbNext`。与 `OnChange` 不同,**值没动也照发**(已经顶到 `Min` 或 `Max` 时),所以"用户按了但没反应"是可观测的;反过来,代码直接写 `Position` 没有"按下"可言,不触发它。 |

> **为什么另起一个名字,而不是用 `OnClick`:** TTyUpDown 从基类继承来的 `OnClick` 是普通的
> `TNotifyEvent`,而 LCL 的 `TUpDown` 把**同一个名字**给了 `(Sender; Button: TUDBtnType)` 事件。
> 从 Lazarus 移植过来的代码能编译、能把那个"以为会收到方向"的处理器挂上去,然后什么方向也收不到
> ——两边都合法,没有任何诊断。改继承来的那个不在选项内,于是带方向的事件用自己的名字。

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
- **自动连发:** 按住某一半会先延迟 ~0.4s 再以 ~60ms 间隔连续步进,松开 / 移出即停。连发的每一 tick 都会发 `OnArrowClick`。
- **`Wrap` 带进位:** 回绕不丢溢出量(见第 3 节 `Wrap`);`Wrap=False` 时仍是贴到边界停住。
- **纯逻辑可测:** 半区命中 `TyUpDownHit`、半区矩形 `TyUpDownButtonRect`、夹紧 / 回绕 `TyUpDownClamp` 都是纯函数,已单元测试(`test.updown`)。
- **主题驱动:** 颜色取自 `TyUpDown`,不硬编码;唯一例外是悬停 / 按下半边的背景仍解析 `TyButton`(见第 5 节)。
- **`:disabled` 在随库主题下不变淡:** `light` / `dark` / `auto` 的 `:disabled` 选择器列表里没有 `TyUpDown`,而主题一旦定义过某 typeKey,内置基础层对该键就整体不再兜底,所以禁用时不会降透明度。需要就在自己的主题里补一条 `TyUpDown:disabled { opacity: var(--disabled-opacity); }`(`green.tycss` 与 `aero` / `bootstrap` / `office` / `xp` 四套 builtin 已有)。
