# TTySpinEdit — API 参考

## 1. 概述

`TTySpinEdit` 是 TyControls 库中的主题化**可内联编辑的整数微调控件**，继承自 `TTyCustomControl`。控件显示一个整数值，右侧有上/下两个小箭头按钮。用户既可以**直接键入数字与前导 `-`**（轻量内联编辑缓冲，无选区/剪贴板），也可以点击箭头按钮、使用上/下方向键、或滚动鼠标滚轮来按 `Increment` 步进改变 `Value`。`Enter` 或失焦时**提交**编辑缓冲（解析 → 夹紧 `[MinValue, MaxValue]` → 写 `Value`）；`Esc` **还原**到当前 `Value`；非法输入（空串或仅 `-`）提交时退回当前 `Value`。值在**区间非空（`MaxValue > MinValue`）时**被夹紧到 `[MinValue, MaxValue]`，`MaxValue <= MinValue` 表示不限制。**通知分两个事件**：`OnChange` 是「编辑框文字变了」（每一次按键 / 删除 / 步进 / 夹紧 / 程序赋值都会触发，与 LCL 各编辑类控件一致），`OnValueChange` 是「提交后的整数值真的动了」。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.SpinEdit` |
| typeKey | `TySpinEdit` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸 | 120 × 28（逻辑像素） |

```pascal
uses tyControls.SpinEdit;
```

---

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `MinValue` | `Integer` | `0` | 最小值。赋值后当前 `Value` 会**走 `Value` setter 同一条夹紧路径**重新过一遍（空区间同样不夹紧）；若因此移动了值，则与其他值变化一样触发 `OnChange` + `OnValueChange`。 |
| `MaxValue` | `Integer` | `0` | 最大值。同 `MinValue`：重新过一遍 setter，动了就通知。**默认 `0`（= `MinValue`）即"不限制"**，与 LCL `spin.pp` 的 `DefMaxValue = 0` 一致——刚拖到窗体上的微调框接受任意整数。**破坏性变更**：早前默认 `100`，于是一个未配置的控件会把用户键入的 250 悄悄改成 100，没有任何提示。 |
| `Value` | `Integer` | `0` | 当前值。**仅当 `MaxValue > MinValue`（区间非空）时才夹紧到 `[MinValue, MaxValue]`；`MaxValue <= MinValue` 表示"不限制"，任何值原样写入**（与 LCL `spinedit.inc` 的 `GetLimitedValue` 一致）。值真正变化时触发 `OnValueChange`；显示文字随之改写，因此也触发 `OnChange`。 |
| `Increment` | `Integer` | `1` | 每步步进量。赋值小于 1 时被强制置为 1。 |
| `ReadOnly` | `Boolean` | `False` | **（API parity 新增）** 为 `True` 时拦截内联文本编辑**与** ± 步进（箭头按钮 / 方向键 / 滚轮）；程序化 `Value :=` 不受限。 |
| `EditorEnabled` | `Boolean` | `True` | **（API parity 新增）** 为 `False` 时**只锁键盘**：不能键入 / 退格 / 删除，但箭头按钮、方向键、滚轮照常步进——即"只能用箭头选，不许手打"，把值限制在合法刻度（5 的倍数、偶数……）上的标准做法。与 `ReadOnly` 正交（LCL `spin.pp:79`）：`ReadOnly` 锁死整个值，这个只锁输入。 |
| `ValueEmpty` | `Boolean` | `False` | **（API parity 新增）** 让字段显示**空白**而不是数字——"尚未填写 / 多选混合"这种 `0` 无法诚实表达的状态（LCL `spin.pp:84`）。与 LCL 一样是**程序设置、真实输入清除**的状态：键入数字、删除字符或写入 `Value` 都会让它回到 `False`。 |
| `TextHint` | `TCaption` | `''` | **（API parity 新增）** 字段为空时用 `TyTextHint` 的弱化墨色绘制的占位文字（LCL `stdctrls.pp:879`），与兄弟控件 `TTyEdit` 同一个 token、同一条绘制规则。 |
| `Alignment` | `TAlignment` | `taLeftJustify` | **（API parity 新增）** 内联文本的水平对齐（左 / 右 / 居中）；光标随对齐偏移（`AlignOffset`）。 |
| `MaxLength` | `Integer` | `0`（无限） | **（API parity 新增）** 按码点封顶内联编辑缓冲长度；`0` 表示无限制；插入时检查。 |
| `OnChange` | `TNotifyEvent` | `nil` | **编辑框文字变化时触发**——每按一个数字键、每次退格/删除、箭头按钮 / 方向键 / 滚轮步进、夹紧、`Esc` 还原、程序化 `Value :=` 都算（等价于 LCL `TCustomEdit.Change`）。文字没真的变（同值再写一次）则不触发。 |
| `OnValueChange` | `TNotifyEvent` | `nil` | **提交后的 `Value` 真的移动时触发**；键入过程中不触发（半截数字还没提交）。给"值现在是 N"这类回调用。 |
| `TabStop` | `Boolean` | `True` | 是否参与 Tab 键导航（构造时自动置为 `True`）。 |
| `Align` | `TAlign` | — | 父容器内的停靠方式。 |
| `Anchors` | `TAnchors` | — | 锚点布局。 |
| `StyleClass` | `string` | `''` | CSS 变体类名。 |
| `Controller` | `TTyStyleController` | `nil`（全局默认） | 关联的样式控制器。 |
| `OnClick` | `TNotifyEvent` | `nil` | 鼠标点击时触发。 |

### public 成员（不进 .lfm，代码可用）

| 成员 | 类型 / 签名 | 说明 |
|------|------|------|
| `Text` | `TCaption` | **（API parity 新增）** 编辑框里**尚未提交**的原始文字，等价于 LCL `TCustomEdit.Text`（`stdctrls.pp:878`）。读：拿到用户正在键入的字符串；写：能解析成整数就写进 `Value`（照常夹紧 + 通知），解析不了就**原样保留**，于是可以把字段预置成非规范字符串（与 LCL `RealSetText` 一致）。`Caption` 同源。 |
| `CaretPos` | `Integer` | **（API parity 新增）** 光标位置（**码点下标**），赋值自动夹紧到 `0..长度`。宿主接管字段时可以据此把光标放到该放的地方。**与 LCL 的 `TPoint` 类型不同**——单行数字框没有第二个轴；这条差异是编译期报错的响亮失败，不是静默的错答案。与兄弟控件 `TTyEdit.CaretPos` 一致。 |
| `Modified` | `Boolean` | **（API parity 新增）** 脏标记：**用户**改过（键入 / 删除 / 箭头按钮 / 方向键 / 滚轮）为 `True`；**程序**写 `Value` 或 `Text` 后回到 `False`；`Enter` / 失焦提交**保留**它（提交是用户在收尾，不是代码在覆盖）。宿主可据此驱动"启用保存"/"关闭前提示"。LCL 同样区分（`include/spinedit.inc:38-42, 163-165`）。 |
| `GetLimitedValue` | `function(const AValue: Integer): Integer; virtual` | **（API parity 新增）** 夹紧规则。 |
| `ValueToStr` | `function(const AValue: Integer): string; virtual` | **（API parity 新增）** 值 → 显示文字。 |
| `StrToValue` | `function(const S: string): Integer; virtual` | **（API parity 新增）** 显示文字 → 值。 |

上面三个 `virtual` 就是 LCL `spin.pp:74-76` 的那三个缝：控件内**每一次**夹紧、格式化、解析都走它们，所以派生类可以改成十六进制、带单位后缀（`12 px`）、千分位或"吸附到某个倍数"，而不必重写整个控件。

### 继承的通用成员

TTySpinEdit 继承自 `TTyCustomControl`（`tyControls.Base`）的通用状态机制。**基线事件集**（Tier A + Tier B，含 `OnEditingDone`）全部暴露——见 [../events.md](../events.md)。

`AutoSize`（基类已 published）现在**有东西可问**了：控件实现了 `CalculatePreferredSize`，按主题字号 + padding + 边框算出**高度**（宽度返回 `0` = 该轴无意见，由窗体作者决定）。换一个字号更大或内距更厚的皮肤时，`AutoSize := True` 的微调框会长高而不是把数字裁掉。

---

## 4. 几何辅助函数

```pascal
function TySpinUpButtonRect(const ALocal: TRect; APPI: Integer): TRect;
function TySpinDownButtonRect(const ALocal: TRect; APPI: Integer): TRect;
```

返回上/下箭头按钮在给定客户区矩形 `ALocal` 中的像素矩形（以 `APPI` 为 DPI 基准）。按钮宽度为 `MulDiv(18, APPI, 96)`（贴齐控件右缘），上下按钮各占客户区高度的一半。例如在 120 × 28、96 DPI 下：上按钮 `Rect(102, 0, 120, 14)`、下按钮 `Rect(102, 14, 120, 28)`。

这两个函数是纯几何函数（无副作用），既用于渲染也用于命中测试，可在测试中直接断言。

---

## 5. 键盘与交互

| 操作 | 行为 |
|------|------|
| 数字键 `0`–`9` | 在光标处插入数字字符，更新内联编辑缓冲，触发 `OnChange`，重绘 |
| `-` | 仅在光标位于位置 0 且缓冲中尚无 `-` 时插入（允许键入负数），其余位置忽略 |
| `←` | 光标左移一码点（到达缓冲开头后停止） |
| `→` | 光标右移一码点（到达缓冲末尾后停止） |
| `Home` | 光标移到缓冲开头 |
| `End` | 光标移到缓冲末尾 |
| `Backspace` | 删除光标前一码点（真的删掉了才触发 `OnChange`；光标在开头时什么都不做也不通知） |
| `Delete` | 删除光标后一码点（同上） |
| `Enter` | **提交**：将缓冲解析为整数（`StrToIntDef`，无法解析时退回当前 `Value`）→ 夹紧 `[MinValue, MaxValue]` → 写入 `Value`（若值移动则触发 `OnValueChange`）→ 回填缓冲（文字变了就触发 `OnChange`） |
| `Esc` | **还原**：丢弃编辑缓冲，重新同步到当前 `Value`（`SyncBufferToValue`），重绘；`Value` 不动所以不触发 `OnValueChange`，但显示文字被改回去了，触发 `OnChange` |
| `↑`（Up） | `Value += Increment`（到达 `MaxValue` 后停止），同步回填缓冲，消费按键 |
| `↓`（Down） | `Value -= Increment`（到达 `MinValue` 后停止），同步回填缓冲，消费按键 |
| 鼠标左键点击上箭头 | `Value += Increment`，同步回填缓冲 |
| 鼠标左键点击下箭头 | `Value -= Increment`，同步回填缓冲 |
| 鼠标滚轮向上 | `Value += Increment`，同步回填缓冲 |
| 鼠标滚轮向下 | `Value -= Increment`，同步回填缓冲 |
| 失焦（`DoExit`） | 等同 `Enter`：自动提交当前缓冲 |

> **注意：** 当 `Enabled = False` 时，`KeyDown` 不消费按键、`DoMouseWheel` 返回 `False`、`MouseDown` 直接返回——即禁用状态下所有输入都不生效。滚轮处理会先调用 `inherited`（即用户的 `OnMouseWheel`），若用户已消费事件则不再步进。
>
> **上表中的"到达 `MinValue`/`MaxValue` 后停止"以及提交时的夹紧，都只在 `MaxValue > MinValue` 时成立**：空区间（`MaxValue <= MinValue`）表示不限制，步进与提交都不再夹紧（见第 8 节第 1 条）。

---

## 6. 状态与主题：typeKey `TySpinEdit`

| 状态 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停在控件上 |
| `:focus` | 获得键盘焦点 |
| `:disabled` | `Enabled = False` |

上/下箭头使用 `TTyPainter.DrawGlyph` 以 `tgArrowUp` / `tgArrowDown` 字形绘制（tier-b 单色字形），颜色取自解析样式的 `TextColor`。获得焦点时在编辑缓冲的光标位置绘制 1px 竖条光标，以约 530 ms 间隔**闪烁**（`TTimer` 懒创建，无头测试与设计器中光标保持静态）。

**数值文字字号由主题 `font-size` 决定（Batch ④）：** 数值文字与光标定位统一经 `ResolveFontSize(S)` 取字号——优先用主题 `TySpinEdit { font-size }`（内置 9px），其次 `Font.Size`，再退到默认 9。绘制（`DrawText`）与光标横坐标测量（`CaretPixelX`）共用同一字号，保证光标始终对齐。早前写死的孤立字号 12 已移除。

### light.tycss 示例规则

```css
TySpinEdit {
  background: var(--surface);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: 1px;
  border-radius: var(--radius);
  padding: 4px;
  font-size: 10px;
}
TySpinEdit:hover    { border-color: darken(--border, 10%); }
TySpinEdit:focus    { border-color: var(--accent); }
TySpinEdit:disabled { opacity: 0.5; }
```

---

## 7. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.SpinEdit;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

// 创建微调控件
var SE: TTySpinEdit;
SE := TTySpinEdit.Create(Self);
SE.Parent := Self;
SE.SetBounds(24, 24, 120, 28);
SE.MinValue := 0;
SE.MaxValue := 100;
SE.Increment := 5;
SE.Value := 10;
SE.OnChange      := @OnSpinTextChange;    // 每次按键都到（实时校验用）
SE.OnValueChange := @OnSpinValueChange;   // 只有提交后的值动了才到

procedure TMainForm.OnSpinTextChange(Sender: TObject);
begin
  // 用户还在输入：这里适合亮/灭"确定"按钮
  BtnOK.Enabled := (Sender as TTySpinEdit).Value >= 0;
end;

procedure TMainForm.OnSpinValueChange(Sender: TObject);
begin
  with Sender as TTySpinEdit do
    Label1.Caption := Format('当前值：%d', [Value]);
end;
```

完整可运行示例参见 `examples/spinedit/umain.pas`。

---

## 8. 注意事项

1. **值夹紧走同一条路径：** 任何修改 `Value` 的路径（属性赋值、按钮、方向键、滚轮、`Enter`/失焦提交）都通过同一 setter。但**空区间（`MaxValue <= MinValue`）表示"无限制"而非"全部钉到最小值"**：早前无条件夹紧，于是 `MinValue := 0` / `MaxValue := 0`——正是"不设限"的写法——把 `Value` 强按成 0，键入什么都进不去。
2. **两个事件各司其职（API parity 修正）：** `OnChange` 是**编辑框**的变化通知——LCL 里 `TSpinEdit` 就是一个 `TCustomEdit`，每次按键都会走 `TCustomEdit.Change`。早前本控件只在"提交后的值变了"时才触发，于是**用户键入期间程序完全听不到**：做实时校验、"输入合法才点亮确定按钮"的回调在整个输入过程中是死的（半截数字可能永远提交不了）。现在 `OnChange` 覆盖所有文字变化，`OnValueChange` 单独承担"值真的动了"。旧的 `OnChange` 触发点是新语义的**子集**，老代码不会漏事件，只会多收到键入期间的通知。
3. **两者都只在"真的变了"时触发：** 同值再写一次 → 文字没变 → 两个事件都不触发；步进到已经在的边界值同理。
4. **Min/Max 修改会重新过一遍 `Value` setter：** 改范围后当前值按**同一条**夹紧规则重算（空区间照样不夹紧），若因此移动则照常触发 `OnChange` + `OnValueChange`——早前这里是静默改写显示值的，校验回调根本不知道值动过。
5. **Increment 下限为 1：** 给 `Increment` 赋小于 1 的值会被强制置为 1。
6. **按钮几何固定：** 上/下箭头按钮宽度固定为 18 逻辑像素（DPI 缩放后）、贴齐右缘，各占高度一半，不可通过属性调整。
7. **内联编辑缓冲轻量：** 编辑缓冲（`FEditText`/`FCaret`）无选区、无剪贴板、无撤销栈；步进操作（方向键/滚轮/按钮）总是立即提交并回填缓冲，不经过缓冲层。
8. **非法输入安全退回：** 提交时若缓冲为空串或仅含 `-`（`StrToIntDef` 返回当前 `FValue` 作为默认值），则 `Value` 不变、`OnValueChange` 不触发；缓冲回填为当前 `Value` 的字符串表示，这一步改写了显示文字，因此触发 `OnChange`。
9. **光标闪烁：** 聚焦时以约 530 ms 间隔启动；`TTimer` 懒创建，仅在 `HandleAllocated` 后启动，无头测试与设计器中光标静态。
10. **`ReadOnly` 与 `EditorEnabled` 是两把不同的锁（API parity 新增）：** `ReadOnly := True` 锁死整个值——键入不行、箭头 / 方向键 / 滚轮也不动（这**就是** LCL 的语义：Win32 部件在 `win32wsspin.pp:274` 的 `UDN_DELTAPOS` 分支里明确 `if not SpinEdit.ReadOnly`）。`EditorEnabled := False` 只锁键盘，箭头照常工作。早前只有前者，于是"只许用箭头选、不许手打"的微调框做不出来——把它设成 `ReadOnly` 会让控件彻底变成死的。
11. **空白状态与占位文字（API parity 新增）：** `ValueEmpty := True` 让字段真的空着（`0` 是一个合法值，拿它冒充"没填"是在说谎）；配合 `TextHint` 就能显示"请选择年份"这类提示。真实输入会清掉空白状态，这与 LCL 一致（`include/spinedit.inc:76`）——它是程序设置的状态，不是键入能产生的状态。
12. **`OnChange` 是状态问题，`Modified` 是意图问题：** `OnChange` 回答"字段现在是什么"，所以程序赋值也触发（每一次变化都是事实）；`Modified` 回答"用户碰过没有"，所以程序赋值把它清成 `False`（把代码写的值算成用户输入就是在撒谎）。
13. **I-beam 光标（batch⑤+⑥）：** 构造时把 `Cursor` 设为 `crIBeam`，鼠标移到控件上时呈现标准的文本输入「I 形」光标，提示内联数字编辑区可直接键入。
14. **和 `TTyUpDown` + `TTyEdit` 的分工：** [`TTyUpDown.Associate`](updown.md#31-绑定伴随字段associate) 现在可以把一对上下按钮绑到任意编辑框上，双向同步。两条路的区别只有一个，但它很关键：绑定方案里的输入框是一个**完整的 `TTyEdit`**（选区、剪贴板、撤销、IME 全都在），而 `TTySpinEdit` 自带的是轻量行缓冲（见第 8 条）。需要在数字字段里选择 / 粘贴 / 撤销，就用绑定方案；要一个开箱即用、能 Tab 进去的一体控件，用 `TTySpinEdit`。
15. **小数版本是一个单独的控件：[`TTyFloatSpinEdit`](floatspinedit.md)。** 它**不是** `TTySpinEdit` 的后代——LCL 把家族反着建（整数版继承小数版，`spin.pp:146`），而本控件那三个 `Integer` 的 `public virtual` 缝（`GetLimitedValue` / `ValueToStr` / `StrToValue`）已经有外部覆写者，改不成 `Double`。小数版改为继承 [`TTyNumericEdit`](numericedit.md)，因此顺带拥有 `TTyEdit` 的完整文本引擎（选区 / 剪贴板 / 撤销 / IME），而本控件只有轻量行缓冲（见第 7 条）。两者的其他差别：`Increment` 那边是 `Double` 且**不**钳到 ≥ 1；按钮不贴右缘而是落在 `TTyEdit` 被内距内缩过的尾部区里（刻意，与 `TTyComboEdit` / `TTyURLEdit` 的尾部按钮对齐）。
