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
| `Alignment` | `TAlignment` | `taLeftJustify` | 整串日期 / 时间文字在字段内的水平对齐。分段高亮与点击命中一起移动。这是**阅读序**的值：镜像布局下 `taLeftJustify` 解析到右边缘（见第 8 节）。 |
| `NullInputAllowed` | `Boolean` | `True` | 用户能否用键盘把字段清空（`N` / `Delete`）。**只管用户**，不管代码：`DTP.DateTime := TyNullDate` 任何时候都写得进去——宿主把一条 NULL 列读进窗体是在传数据，不是在打字。LCL 同样只在按键分支里查它。 |
| `TextForNullDate` | `TCaption` | `'NULL'` | 空态字段显示的文字。**无 `default`**（与 LCL 一致）：初值非空，所以想要"空字符串"的窗体必须能把它流出来。默认值是**字面量而非 resourcestring**——它是属性默认值，翻译了会让窗体存出的 `.lfm` 随保存时的语言变。要本地化的措辞由应用自己赋值、自己翻译。 |
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

> **`Date` / `Time` 为 public（非 published）便捷属性：** `Date` 只读写日期部分（保留时间），`Time` 只读写时间部分（保留日期），二者内部都转发到 `SetDateTime`，因此同样会夹紧并触发 `OnChange`。它们不出现在对象查看器中。**字段为空时二者读回 `TyNullDate`**（而不是 `Trunc` / `Frac` 一个越界浮点数得到的垃圾），写入时也各自知道"没有另一半可保留"——见第 8 节。

> **`DateIsNull: Boolean`（public 方法）** 回答"这个字段有没有日期"。宿主把值写进可空列之前问的就是它。LCL 同名（`datetimepicker.pas:4194`）。

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
- **键盘：** ←/→ 切换字段，Home/End 跳到首/末段，↑/↓ 步进当前段，Enter 提交缓冲，Esc 关闭下拉或撤销整次编辑，`Alt+↓` / `F4` 开合下拉（需 `DateMode=dmComboBox` 且 `Kind=dtkDate`），`Space` 切换 `Checked`（仅 `ShowCheckBox=True`，见上一条），`N` / `Delete` 清空字段（见下）。**镜像布局下 ←/→ 对调，Home/End 不变**——见第 8 节。
- **`A` / `P` 直接设 AM / PM：** 激活段是 AM/PM 段时，`A` 设为上午、`P` 设为下午——是**设定**不是切换，连按两次 `A` 仍是 AM。从前该段只能靠 ↑/↓ 或滚轮改，从左往右打字的用户填到最后一段会撞上死路，而 `A`/`P` 是各原生选择器都接受的键。
- **分隔符键提交当前段并前移：** `/` `-` `.` `,` `:` 与空格会提交正在录入的段并跳到下一段，于是可以一路打 `1/2/2026`。从前只有在某段"填满"时才自动前移，单个数字的月份会把光标卡在原地。（`ShowCheckBox=True` 时空格已被上面的 `Checked` 切换消费，不再作分隔符用。）
- **格式串按写的那样渲染，分段位置按渲染出来的结果算：** 以前控件会把单字母字段翻倍（`d`→`dd`）以保证"格式串第 N 个字符 == 渲染文本第 N 个字符"，分段高亮与点击命中就靠这条等式。代价有两个：`LeadingZeros=False` 在结构上不可能实现；而且这条等式对**月份名**本来就是假的（`mmmm` 是 4 个格式字符，`September` 是 9 个渲染字符），于是月份之后的每个字段都偏了，点年份会选中月份。现在渲染时直接记录每段落在结果串里的字节区间（`TyRenderDateTime`），两者都随之解决。`TyEffectiveFormat` 作为公开辅助函数保留，但控件不再依赖它。
- **DFM 序列化：** `Kind`（`default dtkDate`）、`ReadOnly`、`ShowCheckBox`、`Checked`、`TabStop`、`Alignment`（`taLeftJustify`）、`LeadingZeros`（`True`）、`CenturyFrom`（`1941`）、`Options`（`[]`）、`DateMode`（`dmComboBox`）、`NullInputAllowed`（`True`）声明了默认值，等于默认值时不写入 `.lfm`/`.dfm`。`DateTime` / `MinDate` / `MaxDate` / `DateFormat` / `TimeFormat` / `TextForNullDate` 无 `default`，始终按当前值流式保存。`OnCheckBoxChange` 为 `stored False`（与 `OnChecked` 同一存储）。
- **流式加载不会因越界日期而失败：** `.lfm` 按声明顺序写属性，于是 `DateTime` 先于 `MinDate`/`MaxDate` 到达——值到的时候字段还没有界。本控件的 setter **夹紧而不抛异常**，所以哪怕手写的 `.lfm` 把顺序调了、值也确实在自己的界外，`ReadComponent` 照样返回、窗体照样打开。（`TTyCalendar` 的 `Date` setter 会抛，因此它另外挖了一个 `csLoading` 分支；这里不需要，但这条行为由测试钉着，免得日后一次"加个校验"把它悄悄改掉。）
- **主题一致性：** 弹出日历对应 `TyCalendar` 选择器，复选框复用 `TyCheckBox` 令牌——自定义主题时应一并覆盖，才能保持整体外观一致。右侧按钮区**没有**自己的键（`TyDateTimeButton` 是死键，见上），它跟随字段的 `color`。

---

## 8. 空值（"没选日期"）

`TDateTime` 没有多余的成员可以当"空"：范围内每一个位型都是一个真实时刻，`0` 是 1899-12-30——一个窗体完全可能合法持有的日期。所以空态是一个**远在范围之外**的值，取的就是 LCL 的那一个（`datetimepicker.pas:60`），数值也一样，于是从 LCL picker 交过来、或从同一个数据库列读出来的空值，到这里仍然是空的。

```pascal
const TyNullDate = TDateTime(1.7e+308);   // 别名 NullDate（LCL 拼写）

function TyDateIsNull(const ADateTime: TDateTime): Boolean;
function TyEqualDateTime(const A, B: TDateTime): Boolean;
```

- `TyDateIsNull` 是**范围判定**，不是等值判定：经过 `.lfm` 往返、浮点转换、或数据库驱动给回一个 NaN 的值未必位位相同，而"稍微不一样的无穷大"绝不能被读成"公元四千年的某一天"。NaN 排在最前面判——对 NaN 的任何比较都是 False，先做范围比较会把它当成一个再普通不过的日期放过去。
- `TyEqualDateTime` 把两个空值视为相等。普通的 `=` 会对它们答 False，于是"值没变"变成一次莫须有的 `OnChange`；更糟的方向是 `Esc` 判定"没变化"，把用户想清掉的日期留在字段里。
- **每一次写入都归一到恰好 `TyNullDate`**，所以控件内部存的空值永远是同一个，下游的普通浮点比较依旧成立。

### 每条写入路径都同意这件事

半吊子的空值支持比没有更糟：调用方从一扇门写进空值、从另一扇门读回一个真实日期，而它无从知道自己刚才走的是哪扇。所以下面每一条都单独处理了空态，每一条也都有守卫钉着：

| 路径 | 空态下的行为 |
|---|---|
| `DateTime :=` | 先判空、**再**夹紧。反过来的话，那个防止用户键入公元 0001 年的夹紧会把"没有日期"变成 9999-12-31。 |
| `MinDate :=` / `MaxDate :=` | 移动边界会重夹越界的现值，而空值天生越界——不加守卫，一行根本没提到值的代码就会把用户刚清空的字段填回去。 |
| `Date :=` / `Time :=` | 各自保留自己不写的那一半，而空值没有半边可留：`Date` 写进去从零点起算，`Time` 写进去落在**种子日**（见下）而不是 1899。 |
| `Date` / `Time` 读取 | 返回 `TyNullDate`，不是 `Trunc` / `Frac` 一个越界浮点得到的数——那个数会被直接写进宿主的记录。 |
| 失焦 / `Enter` 提交 | 提交路径整体跳过夹紧，只跑通知。 |
| `Esc`（`UndoChanges`） | 快照比较走 `TyEqualDateTime`。 |
| 键入数字 / ↑↓ / 滚轮 | 从**种子日**起算（见下）。空字段可以直接开始打字。 |
| 下拉日历 | 种子日做初始月份。日历的 `Date` setter 对越界值**会抛异常**，所以这里不加守卫不是"月份不对"，是从那一次点击里抛出去。打开下拉本身**不会**填上字段。 |
| `CalculatePreferredSize` | 取"该格式可能渲染出的最宽文字"与 `TextForNullDate` 的**较大者**。只量日期的话，一个 `TextForNullDate` 设成"未设定截止日"的 `AutoSize` 字段一被清空就会截字。 |

**种子日** = 今天，夹进 `[MinDate, MaxDate]` 与绝对边界。空字段被键入或步进时需要一个合法日期去修改，而随手挑一个（比如裸的 `0` = 1899-12-30）会让用户的第一次按键把自己甩到另一个世纪。

### 键盘与显示

- **`N`** 清空字段——LCL 的键（`datetimepicker.pas:3731`）。**`Delete`** 也清空，这一个是本库加的：LCL 只绑了那个没人猜得到的字母，而 `Delete` 才是用户清字段时会去按的键。
- 两者都是**用户手势**，所以会触发 `OnChange`（与默认静默的程序化写入相反）；连按两次第二次不再通知。`ReadOnly`、inert 空态（`ShowCheckBox` 未勾选）、以及 `NullInputAllowed = False` 都会拒掉它们。
- `ShowCheckBox` 的 inert 空态与本节的空值是**两件独立的事**：前者是"这个字段现在不可用"，后者是"这个字段没有值"。取消勾选不会把值清空，清空也不会去动勾选框（`dtpoAutoCheck` 在清空时刻意不触发——值消失的那一刻去勾上"我有日期"是反的）。
- 空字段仍然可以用 ←/→ 在字段间移动：**字段列表来自格式串，不来自值**，所以它在有没有日期时都存在——否则 Tab 进一个空字段就再没有可以落脚开始打字的地方。
- 空字段**不画分段高亮**，点击也不会选中任何字段：屏幕上是 `NULL`，里面根本没有"年"，按日期的偏移量量出来的高亮会盖在不存在的字符上。
- **正在键入时显示的是正在成形的日期，不是 `NULL`。** 数字缓冲是"离开时提交"模型，所以第一个数字下去时值**仍然是空的**；这时若还固执地显示 `NULL`，用户的按键就消失在一个从不回应的字段里。

---

## 9. 月份 / 星期名跟谁的语言（3.0 起的行为变更）

`DateFormat` 里的 `mmm`/`mmmm`/`ddd`/`dddd` 会渲染出月份 / 星期**名字**，下拉里的 `TTyCalendar` 也画标题月名与星期行。这些名字统一走 `tyControls.Calendar` 的 `TyDateTimeNames` 解析，优先级为 **应用显式指定（`TyDateTimeNameSource`）> 已加载的翻译目录 > 系统区域**——完整机制、目录哨兵与自定义方法见 [`calendar.md` 第 8 节](calendar.md)。本控件额外要点：

- **名字换语言，惯例不换。** `DateFormat`/`TimeFormat` **留空时**回落的短日期 / 短时间**格式**、`/'` 与 `':'` 展开成的分隔符，始终来自 `DefaultFormatSettings`：英文应用在中文机器上仍是 `2026/8/7` 的顺序，只有名字类字段说英文。
- **宽度测量同源。** `CalculatePreferredSize` 用与渲染**相同**的解析结果去量"最宽可渲染值"——语言切换后首选宽度随之变化，字段不会按另一种语言的月名定宽。注意 LCL 会**缓存**首选尺寸：运行中切语言后，`AutoSize` 的 picker 要重新量宽需调 `InvalidatePreferredSize`（重绘不用，渲染每帧现取）。
- **与 `TextForNullDate` 的分工别搞混**（见第 3 节属性表）：`TextForNullDate` 是**属性默认值**，翻译它会让窗体存出的 `.lfm` 随保存时语言变，所以它保持字面量、由应用自己赋值；月 / 星期名是**渲染期输出**，不进 `.lfm`，所以它们跟随语言是安全的。一个是存进窗体的值，一个是画在屏幕上的字——两条规则各管各的，并不矛盾。

---

## 10. 右到左镜像

`BiDiMode := bdRightToLeft` 时整个字段镜像。跨控件的部分见 [`../rtl.md`](../rtl.md)。

| 部件 | 镜像后 |
|---|---|
| 按钮列（下拉 V 形 / 上下箭头） | 移到**物理左**边缘——两个方向下都是尾缘，也是 Windows 在 `WS_EX_LAYOUTRTL` 下放它的位置 |
| 文本框 | 拿走剩下的宽度 |
| 复选框 | 移到文本框的**阅读起点**，即右端；字串从它左侧一个间隙外开始 |
| 上下微调半区 | **不动**——上下是阅读方向够不着的轴，它们各自反射到自己身上 |
| 文字 | `Alignment` 按阅读序解析：默认的 `taLeftJustify` 贴右边缘 |
| 下拉日历 | 右边缘对齐锚点右边缘（`TyPopupRect` 的 `ARightToLeft`） |
| ←/→ | **对调**：← 走向下一个字段 |
| Home / End | **不变**：仍是首 / 末字段 |

- **一次反射，作用在成品上。** 四组槽位不是各自加一个方向分支，而是 `TyDateTimeRects` 在最后对整条记录做一次 `BidiFlipRect`。绘制与命中读的是**同一条记录**，所以"镜像了绘制、没镜像命中"在结构上不可表达——那正是这个控件已经出过一次的 bug（点年份选中月份）。**没有画出来的部件（`dmNone` 的按钮列、没开的复选框）不参与反射**，留在原点。
- **`Alignment` 是被覆盖，不是只改默认值。** 作者显式写死的 `taLeftJustify` 在镜像窗体里也坐在右边；`TAlignment` 没有"未设定"成员，"只翻作者没写的那个"表达不出来。存储的属性从不被改写，只有当帧用到的值变。
- **←/→ 属于布局方向。** 判据（`plans/2026-08-04-rtl-mirroring-scope.md` §6.3 第 4 条）不是"这个控件能不能打字"，而是"这一下按键移动的是什么"：这里移动的是**字段**（年→月→日），不是字符间的光标。本控件就是那条判据专门为之写下的唯一案例。
- **文字本身的顺序不随镜像改变，这是刻意的边界。** 日期是数字与分隔符，在任何段落方向下都是从左到右的 run，所以镜像的 picker 画出的仍是 `15 September 2026`，只有**盒子**换了边。若格式串里放了右到左脚本的字面量或月份名，painter 会走双向布局把 run 重排，而本控件按**前缀宽度**量字段位置，量不出重排——**高亮与命中依旧彼此一致**（两者同源），但都不跟随重排后的字形。这一项与镜像无关、镜像前后一样，`docs/rtl.md` 里也记着。
