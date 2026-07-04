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
| `Date` | `TDateTime` | 构造时为 `DateOf(Now)`（今天） | 当前选中日期。写入时先按 `[MinDate, MaxDate]` 夹紧并取 `DateOf`（丢弃时间部分）；仅当日期实际变化时更新并 `Invalidate`。**无 `default`，始终写入 DFM/LFM。** |
| `MinDate` | `TDateTime` | `0`（无下界） | 可选日期下界。`0` 表示不限制。写入后重新夹紧 `Date` 并始终重绘（越界格子的灰显外观会变化）。 |
| `MaxDate` | `TDateTime` | `0`（无上界） | 可选日期上界。`0` 表示不限制。写入后重新夹紧 `Date` 并始终重绘。 |
| `FirstDayOfWeek` | `TTyWeekDay` | `wdSunday` | 每周第一列的星期（`wdSunday`..`wdSaturday`），决定星期名行与网格列的排列顺序。 |
| `WeekNumbers` | `Boolean` | `False` | 为 `True` 时在网格左侧增加一列 ISO 8601 周数（列宽 24 逻辑像素）。 |
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

> **状态跟踪：** TTyCalendar **没有** `FHover` / `FPressed` 之类的成员状态字段。格子的 `:selected` / `:disabled` / `:hover` 是在渲染时**逐格计算**并向样式模型查询的（见第 5 节），而非控件级 `CurrentStates` 重写。控件自身的 `CurrentStyle`（主体边框 + 背景）走基类默认的状态机（`:hover`/`:focus`/`:active`/`:disabled`）。

---

## 4. 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TNotifyEvent` | 选中日期**实际改变**时触发——键盘方向 / 翻月导航（`SelectDate`）以及日期格点击改变了日期时。设为同一日期不触发。 |
| `OnAccept` | `TNotifyEvent` | 用户**确认**当前日期时：按 `Enter` / `Space`，或**点击一个日期格**。即使日期未变，日期格点击也会触发（用户确认了该日期）。宿主弹窗应监听此事件来提交 + 关闭，而**不是** `OnChange`，这样下拉内的方向键导航不会误关弹窗。 |
| `OnViewChange` | `TNotifyEvent` | `ViewMode` 改变（下钻 / 上钻）时触发。 |

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

- 布局按当前尺寸 + PPI 自适应：表头带高 28 逻辑像素、星期名行高 20、周数列宽 24（`WeekNumbers=True` 时），其余按 7 列 × 6 行均分。下钻视图（月 / 年 / 十年）使用 4×3 网格，表头带高同样 28。
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

- **`Date` 只保留日期部分：** 写入 `Date` 时内部做 `DateOf`（丢弃时间），并按 `[MinDate, MaxDate]` 夹紧。若赋一个越界值，会被夹到最近的边界。
- **`Date` 无 `default`：** 始终写入 `.lfm`/`.dfm`（与有 `default False/True` 的布尔属性不同）。`MinDate`/`MaxDate` 亦无 `default`，`0` 表示该侧无界。
- **`OnAccept` vs `OnChange` 的分工：** `OnChange` 只在日期**改变**时发；`OnAccept` 是"确认"手势（回车 / 空格 / 点日期格），**即便日期没变**点击日期格也会触发。做下拉选择器时请用 `OnAccept` 决定何时关闭弹窗，避免方向键导航误关。
- **`ReadOnly` 只锁选择：** `ReadOnly=True` 拦截 `SelectDate`、日期格点击与键盘选择，但表头的 ←/→ 翻月、标题下钻 / 上钻仍然工作（只浏览不选择）。
- **下钻状态是瞬态的：** `ViewMode` / `ViewMonth` / `ViewYear` 为只读运行时状态，不 published、不序列化；每次运行从 `Date` 派生初值（`FViewMode := cvmDays`）。
- **点击语义：** Days 视图点标题 → 下钻到 Months；点日期格 → 选中该日（`OnChange` + `OnAccept`）。Months/Years/Decades 视图点标题 → 再上一层，点格子 → 选定并下钻一层。相邻月 / 越界格子点击被忽略。
- **键盘导航：** 方向键移动一天 / 一周（越界自动夹紧），`PageUp`/`PageDown` 换上 / 下月（保留日、月末夹紧），`Home`/`End` 跳到当月首 / 末个可选日，`Enter`/`Space` 触发 `OnAccept`。这些键在 Days 视图 + 非 `ReadOnly` 时生效。
- **主体无成员状态字段：** 与 CheckBox 等不同，本控件不缓存 `FHover`/`FPressed`；格子的 `:selected`/`:disabled`/`:hover` 由渲染时逐格向 `ActiveController.Model.ResolveStyle` 查询决定。
- **视觉由主题令牌驱动：** 颜色 / 字体 / 圆角一律来自 `.tycss` 令牌（`--accent`、`--muted`、`--surface-hover` 等），不在控件代码写死；可通过 `StyleClass` 或覆盖上述子部件 typeKey 规则定制外观。
