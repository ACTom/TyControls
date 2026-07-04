# TTyDateTimePicker

## 1. 概述

`TTyDateTimePicker` 是 TyControls 库中的主题化日期 / 时间选择控件，继承自 `TTyCustomControl`。它在一个带边框的字段内以固定宽度分段渲染当前日期或时间，支持逐段编辑（←/→ 切换字段、↑/↓ 或滚轮步进、直接键入数字）。`Kind = dtkDate` 时右侧渲染一个向下 V 形（chevron），单击弹出一个下拉的 `TTyCalendar` 供选日期；`Kind = dtkTime` 时右侧渲染上/下箭头，用于步进当前时间字段。典型用途：表单里的出生日期、预约时间、可空的截止日期（配合 `ShowCheckBox`）等。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.DateTimePicker` |
| `GetStyleTypeKey` 返回值 | `'TyDateTimePicker'` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸 | 130 × 24（逻辑像素，构造时设置） |

在 `.tycss` 文件中，该控件对应的选择器前缀为 `TyDateTimePicker`。

> **共享子部件：** 日期下拉弹层复用了与组合框相同的 `TTyDropdownPopup`（`tyControls.Popup`），弹层内嵌一个 `TTyCalendar`（`tyControls.Calendar`）。所有样式解析统一走 `ActiveController`（`Controller` 为 `nil` 时回退到全局 `TyDefaultController`），因此即使控件仅通过全局默认控制器主题化，弹出日历也不会因 `Controller.Model` 空引用而崩溃。

```pascal
uses tyControls.DateTimePicker;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `DateTime` | `TDateTime` | `Now`（构造时） | 统一读写日期 + 时间的核心属性。写入时先夹紧到 `[MinDate, MaxDate]`（任一端为 `0` 表示不限制），值实际改变时清空数字缓冲、触发 `OnChange` 并重绘。 |
| `Kind` | `TTyDateTimeKind` | `dtkDate` | `dtkDate` = 日期模式（右侧 chevron + 下拉日历）；`dtkTime` = 时间模式（右侧上/下箭头步进）。切换时重建分段。 |
| `DateFormat` | `string` | `''` | `dtkDate` 模式的格式串；为空时用 `DefaultFormatSettings.ShortDateFormat`。单字母字段会被规范化为双字母（`m`→`mm`、`d`→`dd` 等）以保证定宽渲染。 |
| `TimeFormat` | `string` | `''` | `dtkTime` 模式的格式串；为空时用 `DefaultFormatSettings.ShortTimeFormat`。同样按定宽规范化（`h`→`hh`、`n`→`nn`、`s`→`ss`）。 |
| `MinDate` | `TDateTime` | `0` | 允许的下界；`0` 表示不限制。设置后若当前值越界会立即夹紧。 |
| `MaxDate` | `TDateTime` | `0` | 允许的上界；`0` 表示不限制。设置后若当前值越界会立即夹紧。 |
| `ReadOnly` | `Boolean` | `False` | 为 `True` 时禁止步进 / 数字录入（仍可切换字段、打开下拉查看）。 |
| `ShowCheckBox` | `Boolean` | `False` | 为 `True` 时字段左侧绘制一个复选框；未勾选（`Checked=False`）时字段进入 inert 空态。 |
| `Checked` | `Boolean` | `True` | 仅在 `ShowCheckBox=True` 时有意义。为 `False` 时控件 inert：所有编辑、步进、滚轮、下拉均被屏蔽，文字置灰。 |
| `DroppedDown` | `Boolean` | —（运行时状态） | 读取返回下拉日历当前是否打开；写入 `True` 调用 `OpenDropDown`，`False` 调用 `CloseDropDown`。 |
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式。 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 锚点布局。 |
| `Font` | `TFont` | 系统默认 | 传递 PPI 给渲染器；字体族与大小优先由主题控制。 |
| `TabStop` | `Boolean` | `True` | 是否参与键盘 Tab 焦点循环。 |

> **`Date` / `Time` 为 public（非 published）便捷属性：** `Date` 只读写日期部分（保留时间），`Time` 只读写时间部分（保留日期），二者内部都转发到 `SetDateTime`，因此同样会夹紧并触发 `OnChange`。它们不出现在对象查看器中。

### 继承的通用成员

TTyDateTimePicker 继承自 `TTyCustomControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分。 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器；控件内部统一经 `ActiveController` 解析样式。 |

### 状态跟踪字段（protected / private）

| 字段 | 类型 | 说明 |
|------|------|------|
| `FActiveSeg` | `Integer` | 当前激活的分段索引（`-1` 表示无）；决定高亮与步进/录入的目标字段。 |
| `FDigitBuffer` | `string` | 逐位键入时的数字缓冲，未写入 `FDateTime` 前显示在激活段，避免过早钳位闪烁。 |
| `FMouseDownOnButton` | `Boolean` | MouseDown 命中 chevron 时置位，实际开合下拉延迟到 `Click`（避免 mouse-up 立即失活关闭）。 |
| `FCloseUpTick` | `QWord` | 上次关闭下拉的 tick，用于 200 ms 内的重开竞态守卫。 |

> `ActiveSeg` / `Segments` / `DigitBuffer` / `Popup` / `Calendar` 均以 public **只读**属性暴露，仅供测试探针使用。

---

## 4. 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TNotifyEvent` | `DateTime` 实际改变时触发（无论逐段编辑、步进、日历导航还是程序化 `DateTime :=`）。仅在夹紧后的值不同于旧值时发出。 |
| `OnDropDown` | `TNotifyEvent` | `OpenDropDown` 实际打开日历弹层时触发（仅 `dtkDate`）。 |
| `OnCloseUp` | `TNotifyEvent` | 下拉日历关闭时触发（失焦关闭 / Esc / 选定日期）。 |
| `OnChecked` | `TNotifyEvent` | 用户点击复选框区域切换 `Checked` 时触发（仅 `ShowCheckBox=True`）。程序化 `Checked :=` **不**触发。 |
| `OnClick` | `TNotifyEvent` | 单击控件时（Tier A 基线，另单独 published）。 |

> 除上表外，TTyDateTimePicker 还暴露**基线事件集**（Tier A 鼠标 / 通用事件 + Tier B 键盘 / 焦点事件，因其为可聚焦的 `TTyCustomControl`）。完整清单见 [../events.md](../events.md)。

---

## 5. 状态与主题

### 支持的伪类状态

控件沿用 `TTyCustomControl` 的状态机制（未重写 `CurrentStates`），内置主题使用以下伪类：

| 伪类 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停 |
| `:focus` | 获得键盘焦点 |
| `:disabled` | `Enabled = False` |

### light.tycss 内置规则摘要

```css
TyDateTimePicker {
  background: var(--input-bg);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: var(--input-border-width);
  border-radius: var(--radius);
  padding: 4px 6px;
  font-size: var(--font-size-base);
}
TyDateTimePicker:hover    { border-color: var(--input-border-hover); }
TyDateTimePicker:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }
TyDateTimePicker:disabled { opacity: var(--disabled-opacity); }

/* 右侧按钮区域的独立选择器 */
TyDateTimeButton        { background: var(--surface-chrome); color: var(--on-surface); }
TyDateTimeButton:hover  { background: var(--surface-hover);  color: var(--accent); }
```

**渲染细节：**

- 主题的 `background` / `border-*` / `padding` 作用于整个字段外框（经 `DrawFrame` 路径，`:disabled` 的 `opacity` 生效）。
- 右侧按钮列固定宽度由 `TyFieldButtonWidth` 决定（DPI 缩放）。`dtkDate` 绘制一个 `tgChevronDown` 字形；`dtkTime` 在上下半区分别绘制 `tgArrowUp` / `tgArrowDown`。按钮字形颜色跟随字段的 `TextColor`。
- 激活分段的高亮矩形使用 `TyTextSelection` 令牌的 `background` 作为填充色，仅在**控件获得焦点且非 inert** 时绘制。
- `ShowCheckBox` 时左侧复选框的填充 / 边框 / 勾号从 **`TyCheckBox`** typeKey 解析（勾选态用 `[tysActive]` 变体）；inert 空态下字段文字取 `TyCheckBox:disabled` 的 `TextColor` 作为置灰色。

---

## 6. 代码示例

```pascal
uses
  DateUtils,
  tyControls.Controller, tyControls.DateTimePicker;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

// ── 日期选择器（下拉日历）──
var DatePicker: TTyDateTimePicker;
DatePicker := TTyDateTimePicker.Create(Self);
DatePicker.Parent := Self;
DatePicker.SetBounds(150, 54, 180, 26);
DatePicker.Kind := dtkDate;
DatePicker.DateFormat := 'yyyy-mm-dd';
DatePicker.DateTime := Now;
DatePicker.MinDate := EncodeDate(2000, 1, 1);
DatePicker.MaxDate := EncodeDate(2099, 12, 31);
DatePicker.OnChange := @DateChanged;
DatePicker.OnDropDown := @DropDownOpened;
DatePicker.OnCloseUp := @DropDownClosed;

// ── 时间选择器（上/下步进）──
var TimePicker: TTyDateTimePicker;
TimePicker := TTyDateTimePicker.Create(Self);
TimePicker.Parent := Self;
TimePicker.SetBounds(150, 94, 180, 26);
TimePicker.Kind := dtkTime;
TimePicker.TimeFormat := 'hh:nn:ss';
TimePicker.DateTime := Now;

// ── 可空日期（ShowCheckBox）──
var CheckPicker: TTyDateTimePicker;
CheckPicker := TTyDateTimePicker.Create(Self);
CheckPicker.Parent := Self;
CheckPicker.SetBounds(150, 134, 180, 26);
CheckPicker.Kind := dtkDate;
CheckPicker.DateFormat := 'yyyy/mm/dd';
CheckPicker.ShowCheckBox := True;
CheckPicker.Checked := False;      // 初始为空（字段置灰）
CheckPicker.OnChecked := @CheckPickerChecked;

// OnChange 处理器
procedure TMainForm.DateChanged(Sender: TObject);
begin
  ShowMessage('日期：' +
    FormatDateTime('yyyy-mm-dd', TTyDateTimePicker(Sender).DateTime));
end;

// 程序化开合下拉
DatePicker.DroppedDown := True;    // 打开日历
if DatePicker.DroppedDown then
  DatePicker.DroppedDown := False; // 关闭
```

---

## 7. 注意事项

- **`DateTime` 是唯一权威值：** 日期与时间都存在同一个 `TDateTime` 里。`Date` / `Time` 只是分别读写整数 / 小数部分的便捷属性，最终都转发 `SetDateTime`（含夹紧 + `OnChange`）。
- **分段无进位（roll-within-field）：** ↑/↓ 步进只改动当前字段并在其自身范围内回绕，**不**向相邻字段进位（如「月 12 +1 → 月 1，年不变」「时 23 +1 → 时 0，日不变」）。月/年滚动后日会被钳到当月天数。
- **数字录入是"离开时提交"模型：** 键入的数字先进入 `FDigitBuffer` 并直接显示，直到该段填满（长度足够或再乘 10 会越界）、按 ←/→/Home/End/Enter、↑/↓ 步进、或失焦时才写入 `DateTime`。Esc 丢弃当前缓冲。
- **`OnChange` 防重触发：** 仅当夹紧后的新值真正不同于旧值才触发；程序化设为当前值不触发。日历方向键导航（`OnChange` 路径）实时更新字段但**不**关闭弹层；点击日期或回车（`OnAccept` 路径）才提交并关闭。
- **ShowCheckBox 空态（inert）：** `ShowCheckBox=True` 且 `Checked=False` 时控件进入 inert——所有编辑、步进、滚轮、下拉一律屏蔽，文字置灰。点击复选框区域切换 `Checked` 并触发 `OnChecked`（程序化 `Checked :=` 不触发）。`ShowCheckBox=False` 时 `Checked` 无意义、控件永不 inert。
- **下拉仅 `dtkDate` 有：** `OpenDropDown` 对 `dtkTime` 直接返回；`dtkTime` 的右侧是上/下步进按钮而非 chevron。下拉的开合在 `Click` 而非 `MouseDown` 中完成（配合 200 ms 重开守卫），以避免 mouse-up 立即失活关闭刚弹出的日历。
- **键盘：** ←/→ 切换字段，Home/End 跳到首/末段，↑/↓ 步进当前段，Enter 提交缓冲，Esc 关闭下拉或丢弃缓冲，`Alt+↓` / `F4` 开合下拉（仅 `dtkDate`）。
- **DFM 序列化：** `Kind`（`default dtkDate`）、`ReadOnly`（`default False`）、`ShowCheckBox`（`default False`）、`Checked`（`default True`）、`TabStop`（`default True`）声明了默认值，等于默认值时不写入 `.lfm`/`.dfm`。`DateTime` / `MinDate` / `MaxDate` / `DateFormat` / `TimeFormat` 无 `default`，始终按当前值流式保存。
- **主题一致性：** 弹出日历与右侧按钮区分别对应 `TyCalendar` 与 `TyDateTimeButton` 选择器，复选框复用 `TyCheckBox` 令牌——自定义主题时应一并覆盖，才能保持整体外观一致。
