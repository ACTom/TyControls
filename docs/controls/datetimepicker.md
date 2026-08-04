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
| `DateTime` | `TDateTime` | `Now`（构造时） | 统一读写日期 + 时间的核心属性。写入时先夹紧到 `[MinDate, MaxDate]`（任一端为 `0` 表示不限制）再夹进绝对边界，值实际改变时清空数字缓冲并重绘。**代码写入默认不触发 `OnChange`**（3.0 起的行为变更，见第 7 节）；要恢复旧行为把 `dtpoDoChangeOnSetDateTime` 放进 `Options`。 |
| `Kind` | `TTyDateTimeKind` | `dtkDate` | `dtkDate` = 日期模式；`dtkTime` = 时间模式。右侧按钮画什么由 `DateMode` 与 `Kind` 共同决定（见 `DateMode`）。切换时重建分段。 |
| `DateFormat` | `string` | `''` | `dtkDate` 模式的格式串；为空时用 `DefaultFormatSettings.ShortDateFormat`。**按写的那样渲染**：`'d/m/yyyy'` 不再被改写成 `'dd/mm/yyyy'`——补零与否由 `LeadingZeros` 决定。`mmm`/`mmmm` 出月份名、`ddd`/`dddd` 出星期名，且分段高亮与点击命中会跟着实际渲染宽度走。 |
| `TimeFormat` | `string` | `''` | `dtkTime` 模式的格式串；为空时用 `DefaultFormatSettings.ShortTimeFormat`。含 `am/pm`（或 `a/p`）时小时按 12 小时制显示与录入。`z`/`zzz` 是**毫秒**字段，可选中、可键入、可步进。常量 `tf12` / `tf24` 是 LCL 同名枚举成员所选的那两种模式对应的格式串，可直接赋值。 |
| `MinDate` | `TDateTime` | `0` | 允许的下界；`0` 表示不限制。设置后若当前值越界会立即夹紧。 |
| `MaxDate` | `TDateTime` | `0` | 允许的上界；`0` 表示不限制。设置后若当前值越界会立即夹紧。 |
| `Alignment` | `TAlignment` | `taLeftJustify` | 整串日期 / 时间文字在字段内的水平对齐。分段高亮与点击命中一起移动。 |
| `LeadingZeros` | `Boolean` | `True` | `False` 时**日 / 月 / 时**不补前导零（`9/7/2026` 而非 `09/07/2026`）。分 / 秒 / 毫秒始终补零（`9:5` 不是时间）——与 LCL 的取舍一致。 |
| `CenturyFrom` | `Word` | `1941` | 键入**少于三位**的年份时的展开枢轴：不小于枢轴后两位的归枢轴所在世纪，小于的归下一个世纪。三位 / 四位输入视为明确年份，原样保留。 |
| `Options` | `TTyDateTimePickerOptions` | `[]` | LCL 同名集合：`dtpoDoChangeOnSetDateTime`（代码写入也触发 `OnChange`）、`dtpoEnabledIfUnchecked`（复选框未勾选时仍可编辑）、`dtpoAutoCheck`（值被改动时自动勾上复选框）、`dtpoResetSelection`（每次获得焦点都回到第一个字段）。 |
| `DateMode` | `TTyDTDateMode` | `dmComboBox` | 右侧交互件：`dmComboBox` = 保持由 `Kind` 决定（日期→下拉日历，时间→上下箭头）；`dmUpDown` = 一律上下箭头（日期字段也只步进、不弹日历）；`dmNone` = **没有按钮，也不预留按钮列**——文字拿回这块宽度，用于表格单元格 / 紧凑工具条。 |
| `AutoSize` | `Boolean` | `False` | 打开后控件按"内边距 + 复选框 + 该格式可能渲染出的最宽文字 + 按钮列"自行测量并收缩包裹。默认关闭（LCL 的 picker 默认是开的）——统一打开会改动现有窗体上每一个字段的尺寸。 |
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
| `OnChecked` | `TNotifyEvent` | `Checked` 改变时触发（仅 `ShowCheckBox=True` 才有意义）。触发点在 **setter** 里，所以鼠标点复选框、`Space` 键、`dtpoAutoCheck` 自动勾选、以及程序化 `Checked :=` 走的都是同一条通知路径。（3.0 之前只有鼠标那一条会通知，`Space` 改了状态却不告诉任何人。）LCL 同样在自己的 setter 里发 `CheckBoxChange`。 |
| `OnCheckBoxChange` | `TNotifyEvent` | 同一事件的 LCL 拼写别名——同一份存储，`stored False`（序列化走 `OnChecked`）。移植过来的 `.lfm` 里的 `OnCheckBoxChange = Handler` 能直接流入，不会变成一个没人接的处理器。 |
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

```

> **`TyDateTimeButton` 是一个死键,别写它。** 它在几份随库样式表里还留着定义,但 `source/` 里
> **没有任何解析点** —— 右侧的下拉箭头与上下微调箭头都用字段自己(`TyDateTimePicker`)解析出的
> `TextColor` 画(`tyControls.DateTimePicker.pas` 里画的是 `tgChevronDown` / `tgArrowUp` /
> `tgArrowDown` 三个字形)。想改按钮区的字形颜色,改 `TyDateTimePicker` 的 `color`。
> 见 [tycss-reference §8.6](../tycss-reference.md)。

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
- **`OnChange` 现在只代表"用户改的"（3.0 起的行为变更）：** `DTP.DateTime := Rec.Due` 这类**代码写入**默认**不**再触发 `OnChange`。原来是无条件触发的，于是"把一条记录读进窗体"这行普通代码会回调应用自己的 `OnChange`——没人碰过的窗体亮起脏标记，回写模型的处理器还会自激循环，而且没有开关可以关掉。需要旧行为就把 `dtpoDoChangeOnSetDateTime` 放进 `Options`（这也是 LCL 的做法与默认值）。用户手势（键入、步进、滚轮、在下拉里点日期）照常触发。仅当夹紧后的新值真正不同于旧值才触发。日历方向键导航实时更新字段但**不**关闭弹层；点击日期或回车（`OnAccept` 路径）才提交并关闭。
- **`Esc` 撤销整次编辑（3.0 起的行为变更）：** 获得焦点时（以及每次代码写入 `DateTime` 时）控件会记下当时的值；`Esc` 恢复到那个快照。以前 `Esc` 只丢弃半截的数字缓冲，于是用方向键把月份调过头的用户按下 `Esc`、以为取消了，改动却留着。`ConfirmChanges` / `UndoChanges` 是这一对动作的公开入口（LCL 同名）。下拉打开时 `Esc` 仍然优先关闭下拉。
- **两位年份会按 `CenturyFrom` 展开：** 在 `yyyy` 格式里键入 `26` 再离开，得到的是 2026 而不是公元 26 年。以前是原样写入并在失焦时提交的——一个看不见的错误数据。三位 / 四位输入不动。
- **12 小时格式里键入的小时留在当前半天：** 格式含 `am/pm` 时字段显示 1..12，所以键入的数字按 12 小时读法回填（下午 3 点键入 `04` 得 16:00，上午键入 `12` 得 0:00）。以前是原样存 24 小时值，于是显示还写着 "04 PM"、实际值却差了 12 小时。
- **ShowCheckBox 空态（inert）：** `ShowCheckBox=True` 且 `Checked=False` 时控件进入 inert——所有编辑、步进、滚轮、下拉一律屏蔽，文字置灰。点击复选框区域切换 `Checked` 并触发 `OnChecked`（程序化 `Checked :=` 不触发）。**`Space` 键同样切换 `Checked`**：这个分支**排在 inert 拦截之前**，否则未勾选的控件会拒掉所有按键——连唯一能把它打开的那一个也拒掉，而复选框只有约 12px 的鼠标靶面，键盘用户 Tab 过来就再没有办法让它可编辑。`Space` 走的是 `Checked` 属性 setter，而通知点就在 setter 里，因此**同样触发** `OnChecked`（3.0 起；此前只有鼠标那条路径通知）。`ReadOnly=True` 时 `Space` 不生效。`ShowCheckBox=False` 时 `Checked` 无意义、控件永不 inert。加了 `dtpoEnabledIfUnchecked` 则未勾选时也可编辑。
- **下拉由 `DateMode` 决定，不再只看 `Kind`：** 只有 `DateMode = dmComboBox` 且 `Kind = dtkDate` 才有下拉日历（`OpenDropDown`、`Alt+↓`、`F4` 在其余组合下直接返回）。`dmUpDown` 一律给上下箭头；`dmNone` 既不画按钮也不预留按钮列。下拉的开合在 `Click` 而非 `MouseDown` 中完成（配合 200 ms 重开守卫），以避免 mouse-up 立即失活关闭刚弹出的日历。
- **绝对边界：** 即使 `MinDate`/`MaxDate` 都是 `0`（不限制），值也会被夹在 `TyTheSmallestDate`（1752-10-01）与 `TyTheBiggestDate`（9999-12-31）之间——四位年份字段本来可以键入 0001，而早于 1752 的日期各 widgetset 的原生日历都画不对，而这里录入的值是会被交给它们的。两个常量另有 `TheSmallestDate` / `TheBiggestDate` 的 LCL 拼写别名。注意与 LCL 的差别：LCL 把 `MinDate`/`MaxDate` **初始化**成这两个哨兵，本控件保留 `0 = 不限制`（改掉会翻转所有 `if MinDate <> 0` 的含义）。
- **键盘：** ←/→ 切换字段，Home/End 跳到首/末段，↑/↓ 步进当前段，Enter 提交缓冲，Esc 关闭下拉或撤销整次编辑，`Alt+↓` / `F4` 开合下拉（需 `DateMode=dmComboBox` 且 `Kind=dtkDate`），`Space` 切换 `Checked`（仅 `ShowCheckBox=True`，见上一条）。
- **`A` / `P` 直接设 AM / PM：** 激活段是 AM/PM 段时，`A` 设为上午、`P` 设为下午——是**设定**不是切换，连按两次 `A` 仍是 AM。从前该段只能靠 ↑/↓ 或滚轮改，从左往右打字的用户填到最后一段会撞上死路，而 `A`/`P` 是各原生选择器都接受的键。
- **分隔符键提交当前段并前移：** `/` `-` `.` `,` `:` 与空格会提交正在录入的段并跳到下一段，于是可以一路打 `1/2/2026`。从前只有在某段"填满"时才自动前移，单个数字的月份会把光标卡在原地。（`ShowCheckBox=True` 时空格已被上面的 `Checked` 切换消费，不再作分隔符用。）
- **格式串按写的那样渲染，分段位置按渲染出来的结果算：** 以前控件会把单字母字段翻倍（`d`→`dd`）以保证"格式串第 N 个字符 == 渲染文本第 N 个字符"，分段高亮与点击命中就靠这条等式。代价有两个：`LeadingZeros=False` 在结构上不可能实现；而且这条等式对**月份名**本来就是假的（`mmmm` 是 4 个格式字符，`September` 是 9 个渲染字符），于是月份之后的每个字段都偏了，点年份会选中月份。现在渲染时直接记录每段落在结果串里的字节区间（`TyRenderDateTime`），两者都随之解决。`TyEffectiveFormat` 作为公开辅助函数保留，但控件不再依赖它。
- **DFM 序列化：** `Kind`（`default dtkDate`）、`ReadOnly`、`ShowCheckBox`、`Checked`、`TabStop`、`Alignment`（`taLeftJustify`）、`LeadingZeros`（`True`）、`CenturyFrom`（`1941`）、`Options`（`[]`）、`DateMode`（`dmComboBox`）声明了默认值，等于默认值时不写入 `.lfm`/`.dfm`。`DateTime` / `MinDate` / `MaxDate` / `DateFormat` / `TimeFormat` 无 `default`，始终按当前值流式保存。`OnCheckBoxChange` 为 `stored False`（与 `OnChecked` 同一存储）。
- **主题一致性：** 弹出日历对应 `TyCalendar` 选择器，复选框复用 `TyCheckBox` 令牌——自定义主题时应一并覆盖，才能保持整体外观一致。右侧按钮区**没有**自己的键（`TyDateTimeButton` 是死键，见上），它跟随字段的 `color`。
