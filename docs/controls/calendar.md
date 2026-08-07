# TTyCalendar

## 1. 概述

TTyCalendar 是 TyControls 库中的主题化日历 / 日期选择控件，继承自 `TTyCustomControl`。它在一个带边框的区域内绘制"表头 + 星期名行 + 6×7 日期网格"，支持点击标题在 天 → 月 → 年 → 十年 之间逐级下钻（zoom-out）、点击格子逐级上钻（zoom-in），并可用键盘导航选择日期。典型用途：作为独立的日期选择面板，或作为下拉式日期选择器（配合宿主弹窗）的内嵌选择面。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Calendar` |
| `GetStyleTypeKey` 返回值 | `'TyCalendar'` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸 | 240 × 220（逻辑像素，`Create` 中设置） |

在 `.tycss` 文件中，该控件对应的选择器前缀为 `TyCalendar`。除主体外，控件在渲染时还向样式模型查询若干**子部件 typeKey**：`TyCalendarTitle`（标题）、`TyCalendarWeekday`（星期名 / 周数）、`TyCalendarCell`（日期 / 月 / 年 / 十年格子）。

```pascal
uses tyControls.Calendar;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Date` | `TDateTime` | 构造时为 `DateOf(Now)`（今天） | 当前选中日期，取 `DateOf`（丢弃时间部分）；仅当日期实际变化时更新并 `Invalidate`。**写入越界值抛 `ETyInvalidDate`**，原日期保持不变（详见第 7 节）。**无 `default`，始终写入 DFM/LFM。** |
| `DateTime` | `TDateTime` | 同 `Date` | LCL 同名访问器的别名，同一份存储、同一套越界检查。`stored False`（`Date` 才是被序列化的那个）。 |
| `MinDate` | `TDateTime` | `0`（无下界） | 可选日期下界。`0` 表示不限制。写入后把当前 `Date` **夹紧**到新区间（改的是规则不是值，所以不抛），并始终重绘（越界格子的灰显外观会变化）。 |
| `MaxDate` | `TDateTime` | `0`（无上界） | 可选日期上界。`0` 表示不限制。写入后同样夹紧当前 `Date` 并重绘。 |
| `FirstDayOfWeek` | `TTyWeekDay` | `wdLocaleDefault` | 每周第一列的星期。除 `wdSunday`..`wdSaturday` 外新增 `wdLocaleDefault`（= LCL 的 `dowDefault`）：跟随操作系统区域设置。**3.0 起这是默认值**（原为写死的 `wdSunday`）——见第 7 节的破坏性变更说明。另提供 `dowMonday`..`dowSunday` / `dowDefault` 常量别名，方便从 LCL 移植的代码原样编译。 |
| `DisplaySettings` | `TTyCalDisplaySettings` | `[dsShowHeadings, dsShowDayNames]` | 控制画哪些"外围装饰"，与 LCL 的 `TDisplaySettings` 同名同成员：`dsShowHeadings`（表头带）、`dsShowDayNames`（星期名行）、`dsNoMonthChange`（点击相邻月格子**不**翻页）、`dsShowWeekNumbers`（周数列）。去掉某个标志时，让出的空间**归日期网格**，不会留空洞。 |
| `WeekNumbers` | `Boolean` | `False` | `DisplaySettings` 中 `dsShowWeekNumbers` 的布尔视图——**同一份存储**，两者不可能不一致。`stored False`（序列化走 `DisplaySettings`）；旧 `.lfm` 里的 `WeekNumbers = True` 仍能正常加载。 |
| `ShowToday` | `Boolean` | `True` | 为 `True` 时给"今天"的格子描一圈高亮环（未被选中时）。 |
| `ReadOnly` | `Boolean` | `False` | 为 `True` 时禁止一切选择：`SelectDate`、日期格点击、键盘导航均被拦截（表头翻页 / 下钻仍可用）。 |
| `Font` | `TFont` | 系统默认 | 传递 PPI 给渲染器；字体族与大小优先由主题控制。 |
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式。 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点。 |
| `TabStop` | `Boolean` | `True`（`default True`，构造时亦设置） | 是否参与键盘 Tab 焦点循环。 |

### 继承的通用成员

TTyCalendar 继承自 `TTyCustomControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器 |

### 只读运行时状态（public，非 published）

这些属性反映当前的下钻 UI 状态，属于**瞬态**，不参与流式序列化：

| 属性 | 类型 | 说明 |
|------|------|------|
| `ViewMode` | `TTyCalView` | 当前视图层级：`cvmDays` / `cvmMonths` / `cvmYears` / `cvmDecades`。 |
| `ViewMonth` | `Word` | 当前视图锚定的月份（1–12）。 |
| `ViewYear` | `Word` | 当前视图锚定的年份。 |

### 公开方法

| 方法 | 说明 |
|------|------|
| `SetDateClamped(AValue: TDateTime)` | 把选中日期移到 `[MinDate, MaxDate]` 内**最近**的一天，**永不抛异常**。用在越界值属于预期且无害的场合（spin 走出边界、从更宽的数据源取值）；越界属于 bug 时用 `Date :=`。两者并存是刻意的——由调用方言明自己的意图，读代码的人一眼能看出来。 |
| `HitTest(APoint: TPoint): TTyCalendarPart` | 判断客户区坐标落在哪个区域：`cpNoWhere` / `cpDate` / `cpWeekNumber` / `cpTitle` / `cpTitleBtn` / `cpTitleMonth` / `cpTitleYear`（与 LCL 的 `TCalendarPart` 成员一一对应）。标题里"月份"与"年份"的分界是**实测**的——标题居中绘制，宽度取决于主题字体与区域月份名，所以不能按字符数猜。 |
| `GetCalendarView: TTyCalendarView` | 用 LCL 的命名与**页面**粒度报告当前下钻层级：`cvMonth` / `cvYear` / `cvDecade` / `cvCentury`。注意与 `ViewMode` 差一级——LCL 的 `cvMonth`（"一个月的日期网格"）对应我们的 `cvmDays`，**不是** `cvmMonths`。两者并存，读代码时不必猜是哪一种读法。 |
| `RenderToPublic(...)` | 把控件渲染到任意 `TCanvas`，供测试与嵌入使用。 |

### 单元级辅助

| 名称 | 说明 |
|------|------|
| `TyLocaleFirstDayOfWeek: TTyWeekDay` | 启动时从操作系统读一次的"一周从周几开始"（Windows 走 `LOCALE_IFIRSTDAYOFWEEK`；其他平台缺少可靠来源，保持 `wdSunday`，由宿主自行赋值）。是变量而非函数，便于测试固定它。 |
| `TyResolveFirstDayOfWeek(AValue): TTyWeekDay` | 把 `wdLocaleDefault` 解析成实际星期，其余原样返回。凡是按星期做下标运算的地方都必须先过这个函数——`wdLocaleDefault` 的序号是 7，不是某一列。 |

> **状态跟踪：** TTyCalendar **没有** `FHover` / `FPressed` 之类的成员状态字段。格子的 `:selected` / `:disabled` / `:hover` 是在渲染时**逐格计算**并向样式模型查询的（见第 5 节），而非控件级 `CurrentStates` 重写。控件自身的 `CurrentStyle`（主体边框 + 背景）走基类默认的状态机（`:hover`/`:focus`/`:active`/`:disabled`）。

---

## 4. 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TNotifyEvent` | 选中日期**实际改变**时触发——键盘方向 / 翻月导航（`SelectDate`）以及日期格点击改变了日期时。设为同一日期不触发。 |
| `OnAccept` | `TNotifyEvent` | 用户**确认**当前日期时：按 `Enter` / `Space`，或**点击一个日期格**。即使日期未变，日期格点击也会触发（用户确认了该日期）。宿主弹窗应监听此事件来提交 + 关闭，而**不是** `OnChange`，这样下拉内的方向键导航不会误关弹窗。 |
| `OnViewChange` | `TNotifyEvent` | `ViewMode` 改变（下钻 / 上钻）时触发。 |
| `OnYearChanged` | `TNotifyEvent` | 选中日期的**年**分量改变时触发；表头翻页跨年时也触发。 |
| `OnMonthChanged` | `TNotifyEvent` | 选中日期的**月**分量改变时触发；**表头箭头翻页**时也触发——"翻到某月就去加载该月日程"的常规接线用的就是它（此前翻页不触发任何事件）。 |
| `OnDayChanged` | `TNotifyEvent` | 选中日期的**日**分量改变时触发。 |

> 选择变化的触发**顺序**与 LCL 一致（`calendar.pp` 的 `LMChanged`）：`OnYearChanged` → `OnMonthChanged` → `OnDayChanged` → `OnChange`。顺序是有承载的：先在 `OnMonthChanged` 里重载数据、再在 `OnChange` 里读 `Date` 的处理链依赖它。**代码写入** `Date` / `DateTime` 不触发上述任何事件（它不是一次选择动作）。

> 除上表外，TTyCalendar 还暴露**基线事件集**（Tier A 鼠标 / 通用事件 + Tier B 键盘 / 焦点事件，因其为可聚焦的 `TTyCustomControl`）。完整清单见 [../events.md](../events.md)。

---

## 5. 状态与主题

### 主体伪类状态

控件**主体**（外框 + 背景，经 `CurrentStyle` / `DrawFrame`）沿用 `TTyCustomControl` 的默认状态机：`:hover` / `:focus` / `:active` / `:disabled`。内置主题只对 `TyCalendar` 主体定义了基础外观，未加主体级状态规则。

### 子部件与格子伪类

真正承载"选中 / 禁用 / 悬停"视觉的是**子部件 typeKey**，在渲染时逐格向样式模型查询：

| 子部件 typeKey | 用途 | 用到的伪类 |
|----------------|------|-----------|
| `TyCalendarTitle` | 表头标题（月份 / 年份区间文本） | `:hover` |
| `TyCalendarWeekday` | 星期名行 + 周数列 | 无（仅 normal） |
| `TyCalendarCell` | 日期 / 月 / 年 / 十年格子 | `:selected`、`:disabled`、`:hover` |

格子状态的判定逻辑（`RenderTo` / drill-down 渲染）：
- **`:selected`（`tysSelected`）**——该格 == 当前 `Date`（月视图中月份匹配、年 / 十年视图中相应匹配）。
- **`:disabled`（`tysDisabled`）**——该格属于相邻月（other-month）**或**落在 `[MinDate, MaxDate]` 之外；在年 / 十年视图中还包括"溢出格"（spill：所显示十年 / 世纪之外的引导 / 收尾格）。
- 其余为 normal。今日环（`ShowToday`）不是伪类，而是复用 `:selected` 背景色描的一圈描边环。

### light.tycss 内置规则

```css
TyCalendar        { background: var(--input-bg); color: var(--on-surface); border-color: var(--border); border-width: var(--input-border-width); border-radius: var(--radius); padding: 6px; font-size: var(--font-size-base); }
TyCalendarTitle   { color: var(--on-surface); font-weight: var(--font-weight-bold); }
TyCalendarTitle:hover   { color: var(--accent); }
TyCalendarWeekday { color: var(--muted); font-size: var(--font-size-base); }
TyCalendarCell    { background: none; color: var(--on-surface); border-radius: var(--radius-sm); }
TyCalendarCell:hover    { background: var(--surface-hover); }
TyCalendarCell:selected { background: var(--accent); color: var(--on-accent); }
TyCalendarCell:disabled { color: var(--muted); }
```

### 渲染 / 布局细节

- 布局按当前尺寸 + PPI 自适应：表头带高 28 逻辑像素（`dsShowHeadings` 去掉则为 0）、星期名行高 20（`dsShowDayNames` 去掉则为 0）、周数列宽 24（`dsShowWeekNumbers` 时），其余按 7 列 × 6 行均分——**被去掉的带高会让给日期网格**。下钻视图（月 / 年 / 十年）使用 4×3 网格，表头带高同样 28。注意：表头是进入下钻视图的唯一入口，去掉 `dsShowHeadings` 就得到一块纯日期网格。
- 表头为 `[←] [标题] [→]`：左右箭头用主体 `TextColor` 绘制的字形（`tgArrowLeft`/`tgArrowRight`），标题居中。
- 相邻月 / 越界格子若主题未显式给 `color`，则回退为**主体文本色的低透明度版本**（alpha≈100）做灰显。
- 今日环颜色复用 `TyCalendarCell:selected` 的 `background`（即 `var(--accent)`），线宽为缩放后的 1px 发丝线。

---

## 6. 代码示例

```pascal
uses
  DateUtils,
  tyControls.Controller, tyControls.Calendar;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

var
  Cal: TTyCalendar;
  Today: TDateTime;
begin
  Today := DateOf(Now);

  Cal := TTyCalendar.Create(Self);
  Cal.Parent := Self;
  Cal.SetBounds(20, 20, 320, 300);
  Cal.Date := Today;                    // 初始选中今天
  Cal.FirstDayOfWeek := wdMonday;       // 周一为每周第一列
  Cal.WeekNumbers := True;              // 左侧显示 ISO 周数
  Cal.ShowToday := True;               // 今日高亮描边
  Cal.MinDate := IncDay(Today, -20);   // 限定可选区间：今天 ±20 天
  Cal.MaxDate := IncDay(Today, 20);
  Cal.OnChange := @CalChanged;         // 选中日期变化
  Cal.OnAccept := @CalAccepted;        // 点击日期格 / 回车确认
  Cal.OnViewChange := @CalViewChanged; // 下钻 / 上钻
end;

// 选中日期变化时回显
procedure TMainForm.CalChanged(Sender: TObject);
begin
  ShowMessage('已选：' + FormatDateTime('yyyy-mm-dd',
    (Sender as TTyCalendar).Date));
end;

// 确认（供弹窗提交 + 关闭）
procedure TMainForm.CalAccepted(Sender: TObject);
begin
  // 例如：宿主下拉在此 Close
end;
```

只读展示日历：

```pascal
Cal.ReadOnly := True;   // 禁止选择；表头翻页/下钻仍可用
```

---

## 7. 注意事项

- **`Date` 只保留日期部分：** 写入 `Date` 时内部做 `DateOf`（丢弃时间）。
- **`Date` 越界会抛异常（3.0 起的行为变更）：** 写入落在 `[MinDate, MaxDate]` 之外的日期抛 `ETyInvalidDate`，消息里带上越界日期与两侧边界；原日期与视图锚点保持不变。以前是**静默夹紧**——调用方读回 `Date` 拿到的是自己从没赋过的一天，`Cal.Date := 从数据库取的值` 分不清"接受了"和"被悄悄改了"。LCL 同样抛（`EInvalidDate`，`calendar.pp:293-304`），本单元同时提供 `EInvalidDate = ETyInvalidDate` 别名，方便从 Lazarus 移植的 `except on EInvalidDate` 原样编译。**需要旧的夹紧行为就用 `SetDateClamped`。**
  - 三条路径**不抛**：① 流式加载（`csLoading`）改为夹紧，`.lfm` 里一个漂移的日期不该让整个窗体打不开；② 改 `MinDate`/`MaxDate` 是调用方改规则不是传坏值，按 LCL 的 `ApplyLimits` 夹紧；③ 用户手势（点越界格、方向键走到边界）照旧静默拒绝。
- **`Date` 无 `default`：** 始终写入 `.lfm`/`.dfm`（与有 `default False/True` 的布尔属性不同）。`MinDate`/`MaxDate` 亦无 `default`，`0` 表示该侧无界。
- **`DateTime` 只是 `Date` 的别名：** 两者共用同一字段与 setter（同样夹紧 + `DateOf`），不是两份状态；`DateTime` 声明为 `stored False`，`.lfm`/`.dfm` 里只出现 `Date` 一份。注意 LCL 的 `TCustomCalendar.Date` 是 `string` 类型，本控件的 `Date` 是 `TDateTime`——移植时按类型对齐，别按名字对齐。
- **`OnAccept` vs `OnChange` 的分工：** `OnChange` 只在日期**改变**时发；`OnAccept` 是"确认"手势（回车 / 空格 / 点日期格），**即便日期没变**点击日期格也会触发。做下拉选择器时请用 `OnAccept` 决定何时关闭弹窗，避免方向键导航误关。
- **`ReadOnly` 只锁选择：** `ReadOnly=True` 拦截 `SelectDate`、日期格点击与键盘选择，但表头的 ←/→ 翻月、标题下钻 / 上钻仍然工作（只浏览不选择）。
- **下钻状态是瞬态的：** `ViewMode` / `ViewMonth` / `ViewYear` 为只读运行时状态，不 published、不序列化；每次运行从 `Date` 派生初值（`FViewMode := cvmDays`）。
- **点击语义：** Days 视图点标题 → 下钻到 Months；点日期格 → 选中该日（`OnChange` + `OnAccept`）。Months/Years/Decades 视图点标题 → 再上一层，点格子 → 选定并下钻一层。越界（`MinDate`/`MaxDate` 之外）格子点击被忽略。
- **点相邻月的灰格会翻页（3.0 起的行为变更）：** 以前这一击被直接丢掉——灰格是死的，也没有任何提示。现在默认**选中那一天并把视图翻到它所属的月**，与 LCL 的默认一致（`dsNoMonthChange` 不在 `DefaultDisplaySettings` 里）。**要恢复旧行为，把 `dsNoMonthChange` 放进 `DisplaySettings`。**
- **`FirstDayOfWeek` 默认改为跟随系统（3.0 起的行为变更）：** 原来写死 `wdSunday`，于是周一开头的区域（欧洲 / 亚洲大部分）开箱即得一个美式周布局，而且**没有**任何取值能表达"跟随系统"——只能硬写 `wdMonday`，应用换语言后又错了。现在默认 `wdLocaleDefault`。**依赖原来周日开头的窗体请显式写 `FirstDayOfWeek := wdSunday`。**（几何相关的测试同理：断言里的列坐标必须自己钉住 `wdSunday`，否则那是在测开发机的控制面板。）
- **键盘导航：** 方向键移动一天 / 一周（越界自动夹紧），`PageUp`/`PageDown` 换上 / 下月（保留日、月末夹紧），`Home`/`End` 跳到当月首 / 末个可选日，`Enter`/`Space` 触发 `OnAccept`。这些键在 Days 视图 + 非 `ReadOnly` 时生效。
- **主体无成员状态字段：** 与 CheckBox 等不同，本控件不缓存 `FHover`/`FPressed`；格子的 `:selected`/`:disabled`/`:hover` 由渲染时逐格向 `ActiveController.Model.ResolveStyle` 查询决定。
- **视觉由主题令牌驱动：** 颜色 / 字体 / 圆角一律来自 `.tycss` 令牌（`--accent`、`--muted`、`--surface-hover` 等），不在控件代码写死；可通过 `StyleClass` 或覆盖上述子部件 typeKey 规则定制外观。

---

## 8. 月份 / 星期名跟谁的语言（3.0 起的行为变更）

标题里的"八月 2026"、星期行的"周日 周一"、月视图格子里的"1月..12月"——这些是本控件唯一**自己生产**的文字，而它们有两个都讲得通的来源：

- **操作系统区域**（`DefaultFormatSettings`，3.0 之前的唯一来源）——不做国际化的应用在中文机器上理应看到中文月名；
- **应用语言**（库的翻译目录）——一个切到英文的应用在同一台机器上理应看到 `August`，旧行为在这里是 bug（应用全英文、日历标题却是八月）。

两个来源各对一半，所以现在渲染统一经过 `tyControls.Calendar` 里的一个解析口，按固定优先级取值：

| 优先级 | 来源 | 生效条件 |
|--------|------|----------|
| 1 | 应用显式指定 | `TyDateTimeNameSource := dnLocale`（强制系统区域）或 `dnTranslation`（强制库 resourcestring） |
| 2 | 已加载的翻译目录 | 默认值 `dnAuto` 下，检测到进程加载过 tycontrols 目录（含英文目录） |
| 3 | 操作系统区域 | `dnAuto` 且没加载过任何目录——**不做 i18n 的应用行为与 2.x 完全一致** |

要点：

- **"加载过目录"怎么判定：** 库里有一个哨兵 resourcestring（`rsTyDateTimeNamesLang`，缺省值 `'__locale__'`）；每个随库发布的目录——**包括英文目录**——都会把它翻成自己的语言码。于是"哨兵 ≠ 缺省值"精确等价于"有人主动加载了目录"：英文目录其余条目虽与 msgid 相同，哨兵是 `'en'`，照样判得出来；而进程里没有别的东西会改 resourcestring，不会误报。`languages/tycontrols.strconsts.en.po` 因此**不是可删的空文件**——删掉它，`--lang=en` 的月名就静默退回系统区域（test.i18n 有守卫钉住）。
- **只换名字，不换写法：** 分隔符、年月日顺序、`DateFormat` 留空时回落的短日期**格式**始终跟系统区域——英文应用在中文机器上仍写 `2026/8/7`，只是要月名的地方写 `August`。语言管名字，区域管惯例。
- **每次重绘现取：** 解析发生在渲染时，不在构造时缓存；运行中切语言（重新 `SetDefaultLang`）下一次重绘即生效。
- **自定义名字：** 想要两个来源都没有的名字（自定义缩写、第三种语言），要么改写 `DefaultFormatSettings` 各名字数组并强制 `dnLocale`，要么自带一份 tycontrols 目录（记得翻哨兵）走 `dnAuto`。库不再设第三份名字存储。
- **给某语言保留系统月名：** 某语言的目录若**故意不翻**哨兵，该语言就停在第 3 层（系统区域名）——这是文档化的退出通道，不是缺陷。
- **测试注意：** 断言里出现月 / 星期名时，别盲读机器的 `DefaultFormatSettings`——要么 `TyDateTimeNameSource := dnTranslation`（固定英文，跨机器稳定），要么本地保存 / 改写 / 还原 `DefaultFormatSettings`。见 `tests/tytests.lpr` 头部注释。
