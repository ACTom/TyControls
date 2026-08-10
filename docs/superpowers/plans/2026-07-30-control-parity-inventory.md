# 控件对齐缺口全量清单

16 个枚举 agent 逐控件把本库的 published/public 成员面与 LCL/Delphi 同名控件并排比对,
再经一道**机械预筛**分级。

## 为什么这份是 697 而上一份是 44

上一轮审计的第二类("能力根本不存在")被显式截断成 `highest-value only`,只留 3 条全局项 ——
而"一个控件十几条"的缺口全在那一类。这一轮把它完整枚举了。

| | 上一轮 | 这一轮 |
|---|---|---|
| 语义/默认值/类型/改名不一致 | 28 | 225 |
| 能力根本不存在 | 3(截断) | 472 |
| **合计** | **44** | **697** |

## 结论 —— 先读这一节

三轮:16 个 agent 枚举 → 机械预筛 → 58 个 agent 分批对抗验证 → 一道机械复审。
**697 条全部判过,没有剩下未判的。**

| 结论 | 条数 |
|---|---|
| **已验证 · 成立** | **404** |
| **复审 · published 缺失仍成立** | **162** |
| 推翻 | 131 |

**站得住 566 / 697(81%),推翻 131(19%)。**

### 为什么中途出现过一个 22% 和一个 59%,以及该信哪个

抽样那批测出 22% 推翻率,全量那批测出 59%。差距不是数据波动,**是我的方法学错误**:
两批之间我改了提示词,加了"能力换个名字/形状能达到就算外观差异"这条更严的判据,
还带了倾向推翻的框架。两批测的不是同一件事,那个 22% 的外推因此作废。

全量那批 201 条推翻里,**207 条理由**(有重叠)属于"我们有等价物"。手工抽查 8 条发现:
3 条推翻正确(是我这轮刚提交的代码,属于边修边验)、1 条正确(对标配错对)、
**4 条过度推翻** —— 理由都是同一形状:"从代码里能达到,所以不是缺口"。

其中一条的推翻理由自己写着 *the real residue is the PUBLISHED surface* —— 那**正是缺口**。
本轮已经因为完全相同的理由修了 `Visible` 和整个 Drag 面:`TControl` 里是 public,
所以代码永远编得过,少的是属性面板和 `.lfm`。**没 published 就是缺口。**

所以最后一步不是再跑一轮 agent,而是把判断换成能验的检查:建一个**只认 published 段**的
祖先链索引,对全部 293 条推翻做机械复审 —— 凡是被以"代码里能用"为由推翻、而名字在
published 段里确实找不到的,**恢复为成立**。恢复了 162 条。

### 分层可信度

| 层 | 判了 | 成立 | 推翻 | 推翻率 |
|---|---|---|---|---|
| 预筛标为可疑 | 72 | 24 | 48 | 67% |
| 语义/默认值/类型/改名 | 225 | 198 | 27 | 12% |
| 机械确认缺失 | 400 | 344 | 56 | 14% |

和直觉相反的一点:**语义类是最可靠的一类,不是最不可靠的** —— 84 条 `semantic-mismatch`
只有 3 条真错。先前把它和 `name-mismatch` 一起叫"误报重灾区"是错的;真正不可靠的是
`name-mismatch` 和 `absent-method`。

### 有些缺口不能靠 republish 关掉

复审恢复的 162 条里,只有一小部分是"一行 republish"。`AutoSize`/`BorderWidth`/`ChildSizing`
是(已做),但 `BiDiMode`/`ParentBiDiMode` 和 `OnPaint` **不是** —— grep 显示
`tyControls.Painter.pas` 与 `tyControls.Base.pas` 里对 BiDi 的引用数是 **0**,绘制链里也
没有任何 OnPaint 钩子。只 published 不做行为,就是在制造这轮一直在清的那种缺陷:
属性面板给你一个控件根本不看的开关(`TTyColorButton.Caption` 就是这么来的)。
`tests/test.parity.pas` 里有一条 `LyingPropertiesStayUnpublished` 专门钉住这件事。

## 按控件(站得住的条数,降序)

| 控件 | **站得住** | 其中 SMALL | 推翻 | 合计 |
|---|---|---|---|---|
| `TTyStringGrid` | **37** | 21 | 7 | 44 |
| `TTyDateTimePicker` | **33** | 19 | 10 | 43 |
| `TTyTreeView` | **29** | 12 | 9 | 38 |
| `TTyCustomGrid` | **27** | 18 | 8 | 35 |
| `TTyImage` | **16** | 13 | 4 | 20 |
| `TTyShellTreeView` | **16** | 10 | 1 | 17 |
| `TTySpinEdit` | **16** | 6 | 1 | 17 |
| `TTyCalendar` | **15** | 8 | 1 | 16 |
| `TTyListView` | **15** | 7 | 1 | 16 |
| `TTyCustomTabStrip` | **13** | 6 | 0 | 13 |
| `TTyShellListView` | **13** | 11 | 1 | 14 |
| `TTyPanel` | **13** | 7 | 3 | 16 |
| `TTyListBox` | **12** | 4 | 6 | 18 |
| `TTyComboBox` | **12** | 7 | 2 | 14 |
| `TTyHeaderControl` | **11** | 7 | 2 | 13 |
| `TTyEdit` | **10** | 7 | 2 | 12 |
| `TTyMaskEdit` | **10** | 3 | 1 | 11 |
| `TTyToolBar` | **10** | 1 | 0 | 10 |
| `TTyPopupMenu` | **10** | 6 | 0 | 10 |
| `TTyUpDown` | **10** | 5 | 3 | 13 |
| `TTyTrackBar` | **10** | 7 | 4 | 14 |
| `TTyScrollBox` | **10** | 8 | 1 | 11 |
| `TTyDivider` | **9** | 6 | 0 | 9 |
| `TTyGridColumn` | **8** | 5 | 0 | 8 |
| `TTyValueListEditor` | **8** | 3 | 5 | 13 |
| `TTyMemo` | **7** | 3 | 2 | 9 |
| `TTyColorListBox` | **7** | 5 | 0 | 7 |
| `TTySplitter` | **7** | 5 | 7 | 14 |
| `TTyRadioGroup` | **6** | 5 | 1 | 7 |
| `TTyTabSheet` | **6** | 3 | 0 | 6 |
| `TTyCheckListBox` | **6** | 2 | 1 | 7 |
| `TTyMenuBar` | **6** | 3 | 1 | 7 |
| `TTyProgressBar` | **6** | 1 | 2 | 8 |
| `TTyImageCollection` | **5** | 0 | 3 | 8 |
| `TTyColorBox` | **5** | 3 | 0 | 5 |
| `TTyCheckComboBox` | **5** | 2 | 1 | 6 |
| `TTyLabel` | **5** | 3 | 0 | 5 |
| `TTyCheckBox / TTyRadioButton` | **4** | 3 | 0 | 4 |
| `TTyCheckGroup / TTyRadioGroup` | **4** | 1 | 1 | 5 |
| `TTyPageControl` | **4** | 3 | 2 | 6 |
| `TTyGlyphButtonBase` | **4** | 3 | 0 | 4 |
| `TTyColorButton` | **4** | 3 | 1 | 5 |
| `TTyComboBoxEx` | **4** | 1 | 0 | 4 |
| `TTyShape` | **4** | 3 | 2 | 6 |
| `TTyTreeView, TTyListView` | **4** | 2 | 1 | 5 |
| `TTyListItem` | **4** | 2 | 0 | 4 |
| `TTyCheckGroup` | **3** | 3 | 1 | 4 |
| `TTySpeedButton` | **3** | 3 | 0 | 3 |
| `TTyStatusBar` | **3** | 2 | 0 | 3 |
| `TTyCoolBar` | **3** | 1 | 1 | 4 |
| `TTyControlBar` | **3** | 0 | 1 | 4 |
| `TTyScrollBar` | **3** | 1 | 2 | 5 |
| `TTyPaintPanel` | **3** | 2 | 0 | 3 |
| `TTyArrow` | **3** | 1 | 0 | 3 |
| `TTyPageControl / TTyTabSheet` | **2** | 0 | 2 | 4 |
| `TTyButton (all six button classes)` | **2** | 2 | 0 | 2 |
| `TTyCoolBand` | **2** | 0 | 0 | 2 |
| `TTyFilterComboBox` | **2** | 1 | 0 | 2 |
| `TTyGridColumn / TTyColumn` | **2** | 2 | 1 | 3 |
| `TTyColumns` | **2** | 1 | 1 | 3 |
| `TTyValueRow` | **2** | 1 | 1 | 3 |
| `TTyRadioButton` | **1** | 1 | 0 | 1 |
| `TTyCheckBox / TTyRadioButton / TTyGroupBox / T` | **1** | 0 | 1 | 2 |
| `TTyToggleSwitch (closest counterpart)` | **1** | 0 | 0 | 1 |
| `TTyGroupBox (and its descendants TTyCheckGroup` | **1** | 0 | 0 | 1 |
| `TTyGroupBox (and its descendants)` | **1** | 1 | 1 | 2 |
| `TTyGroupBox` | **1** | 0 | 0 | 1 |
| `TTyVirtualImageList / TTyGlyphImageList` | **1** | 1 | 2 | 3 |
| `TTyVirtualImageList / TTyImageCollection` | **1** | 1 | 0 | 1 |
| `TTyCustomTabStrip / TTyPageControl` | **1** | 0 | 0 | 1 |
| `TTyGlyphButton / TTyGlyphButtonBase` | **1** | 0 | 0 | 1 |
| `TTyButton (and every descendant)` | **1** | 0 | 1 | 2 |
| `TTyGlyphButtonBase (TTyGlyphButton/TTySpeedBut` | **1** | 0 | 0 | 1 |
| `TTySpeedButton / TTyGlyphButton` | **1** | 0 | 0 | 1 |
| `TTyGlyphButtonBase.GlyphLayout` | **1** | 0 | 0 | 1 |
| `TTySpeedButton (TTyCustomControl-based)` | **1** | 0 | 0 | 1 |
| `TTySpeedButton / TTyColorButton` | **1** | 1 | 0 | 1 |
| `TTyColorButton.SelectedColor` | **1** | 1 | 0 | 1 |
| `TTyColorButton.OnColorChange` | **1** | 1 | 0 | 1 |
| `TTyGlyphButtonBase (Images/ImageName, GlyphSiz` | **1** | 1 | 0 | 1 |
| `TTyGlyphButtonBase.HasGlyphSource` | **1** | 1 | 0 | 1 |
| `TTyGlyphButton / TTyButton` | **1** | 1 | 0 | 1 |
| `TTySpeedButton / TTyButton` | **1** | 1 | 0 | 1 |
| `TTyColorButton.Click` | **1** | 1 | 0 | 1 |
| `TTySpeedButton.AllowAllUp` | **1** | 1 | 0 | 1 |
| `TTyButton` | **1** | 1 | 0 | 1 |
| `TTyStatusPanel` | **1** | 0 | 0 | 1 |
| `TTyStatusBar / TTyStatusPanel` | **1** | 0 | 0 | 1 |
| `TTyCoolBand / TTyCoolBar` | **1** | 0 | 0 | 1 |
| `TTyCoolBar / TTyCoolBand` | **1** | 0 | 0 | 1 |
| `TTyCoolBar / TTyControlBar` | **1** | 1 | 0 | 1 |
| `TTyToolBar / TTyStatusBar / TTyCoolBar / TTyCo` | **1** | 0 | 0 | 1 |
| `TTyStatusBar / TTyStatusPanel / TTyCoolBar / T` | **1** | 0 | 0 | 1 |
| `TTyDial, TTyLevelMeter, TTyMeter (also TTyGaug` | **1** | 0 | 0 | 1 |
| `TTyDial, TTyLevelMeter, TTyMeter (base: TTyGra` | **1** | 1 | 4 | 5 |
| `TTyGauge` | **1** | 1 | 0 | 1 |
| `TTyScrollPanel` | **1** | 1 | 0 | 1 |
| `TTyLabel, TTyLinkLabel` | **1** | 1 | 0 | 1 |
| `TTyLabel, TTyDivider` | **1** | 0 | 0 | 1 |
| `TTyShape, TTyBevel, TTyArrow` | **1** | 1 | 0 | 1 |
| `TTyLinkLabel` | **1** | 0 | 0 | 1 |
| `TTyBevel` | **1** | 1 | 1 | 2 |
| `TTyListItem / TTyListView` | **1** | 0 | 0 | 1 |
| `TTyListItems` | **1** | 0 | 0 | 1 |
| `TTyColumn (via TTyListView.Header)` | **1** | 1 | 0 | 1 |
| `TTyColumn / TTyHeader` | **1** | 1 | 0 | 1 |
| `TTyListView / TTyColumn` | **1** | 0 | 0 | 1 |
| `TTyListView / TTyListItems` | **1** | 1 | 0 | 1 |
| `TTyHeaderControl (library-wide)` | **1** | 0 | 0 | 1 |

全部推翻、无站得住条目的控件(枚举时报过但审下来没有缺口):

`TTyCustomTabStrip / TTyTabSet`, `TTyDial, TTyLevelMeter, TTyMeter (and ev`, `TTyDial, TTyLevelMeter, TTyMeter (base: `, `TTyDrawGrid`, `TTyGlyphButtonBase / TTyGlyphButton`, `TTyGraphicControl / TTyCustomControl (wh`, `TTyLabel, TTyArrow, TTyDivider`, `TTyLabel, TTyShape, TTyArrow, TTyDivider`, `TTyPageControl / TTyCustomTabStrip`, `TTyStatusBar / TTyStatusPanels / TTyStat`, `TTyToolBar (and TTyStatusBar / TTyCoolBa`, `TTyTreeView, TTyListView, TTyHeaderContr`

---

## 逐控件明细

每节内按 分级 → 成本 排;`确认缺失` 的先列。

### `TTyDateTimePicker`  (对标 `TDateTimePicker`) — 43 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `ShowMonthNames` | 属性 | Boolean (default False) that turns month-name display on -- the pre-MonthDisplay switch, still published. | Ported forms lose the property; combined with MonthDisplay/CustomMonthNames, the entire named-month feature family is missing. | SMALL |
| **成立** | `MinDate / MaxDate defaults` | 默认值 | LCL initialises the bounds to real sentinels -- TheSmallestDate (1 Oct 1752) and TheBiggestDate (31 Dec 9999) -- so the picker is ALWAYS bounded and reads back a non-zero limit. | Two divergences: code that inspects the bounds (`if DTP.MinDate = 0 then ...` vs `if DTP.MinDate = TheSmallestDate`) reads the opposite answer after porting, and our field accepts dates before 1752 that LCL deliberately  | SMALL |
| **成立** | `OnCheckBoxChange -> OnChecked` | 改名 | Fires when the optional checkbox is toggled. | A ported form's `OnCheckBoxChange = DTPCheckBoxChange` line fails to load and the handler is silently orphaned -- the checkbox appears to have stopped notifying. | SMALL |
| **成立** | `OnChange on programmatic DateTime assignment` | 语义 | LCL fires OnChange only for USER edits unless dtpoDoChangeOnSetDateTime is in Options; a programmatic `DTP.DateTime := X` is silent by default. | Ported code that loads a record into the picker (`DTP.DateTime := Rec.Due;`) now re-enters its own OnChange handler -- the classic dirty-flag / infinite-update bug, and there is no flag to switch the old behaviour back o | SMALL |
| **成立** | `A / P keys set AM/PM` | 语义 | With the AM/PM part selected, pressing A or P sets AM or PM directly. | In a 12-hour format the user must arrow/spin the AM/PM field instead of typing the letter -- the standard gesture on every other date picker, and the one keystroke that makes 12-hour entry fast. | SMALL |
| **成立** | `Space toggles the checkbox` | 语义 | When ShowCheckBox is on, the Space key toggles Checked from the keyboard. | A keyboard-only or accessibility user cannot clear/set the checkbox at all -- the control is reachable by Tab but its checkbox is mouse-only, and clearing it is what makes the field null-ish in the first place. | SMALL |
| **成立** | `TimeFormat` | 类型 | LCL's TimeFormat is an enum TTimeFormat = (tf12, tf24) selecting 12-hour-with-am/pm vs 24-hour display. | Same property name, incompatible type: `DTP.TimeFormat := tf24` fails to compile and an .lfm carrying `TimeFormat = tf24` fails to stream into a string property. This is the picker's twin of the Calendar Date-string trap | SMALL |
| **成立** | `millisecond part (dtpMiliSec / tdHMSMs)` | 属性 | A fourth time field for milliseconds, separately selectable and spinnable (SelectMiliSec / IncreaseMiliSec / DecreaseMiliSec), separated by DecimalSeparator. | Sub-second timestamps (logs, lab/instrument data) cannot be edited at all; our EncodeDateTime keeps the MS component (:641) so the value silently carries a millisecond the user can never see or change. | MEDIUM |
| **成立** | `CenturyFrom` | 属性 | The pivot year (default 1941) used to expand a typed 2-digit year: below the pivot's last two digits -> next century, otherwise this one. | With a 'yy'/'dd/mm/yy' format, typing 26 yields the year 0026 here instead of 2026 -- silently wrong data, not a visible error. There is no property to tune the pivot either. | MEDIUM |
| **成立** | `LeadingZeros` | 属性 | When False, day/month/hour are shown without a padding zero (9/7/2026 rather than 09/07/2026); default True. | Users who want the compact non-padded look LCL offers cannot get it, and even an explicit 'd/m/yyyy' DateFormat is silently rewritten to 'dd/mm/yyyy' -- a format string that appears to be ignored. | MEDIUM |
| **成立** | `DateMode` | 属性 | Chooses the right-hand editing affordance for date kinds: dmComboBox (drop-down calendar button), dmUpDown (spin buttons) or dmNone (no button at all). | A date field that should spin (no popup) or show no button at all -- e.g. inside a grid cell or a compact toolbar -- is not achievable; the ported property fails to load. | MEDIUM |
| **成立** | `Alignment` | 属性 | Horizontal alignment of the whole date/time text inside the field (taLeftJustify default, taCenter, taRightJustify). | Right-aligned dates in a data-entry column (the usual convention next to numeric fields) are impossible; a ported `Alignment = taRightJustify` line fails to load. | MEDIUM |
| **成立** | `AutoSize` | 属性 | Published AutoSize (default True on the LCL picker) backed by a real CalculatePreferredSize that measures digits, separators, month text, checkbox and button. | The failure mode this codebase already logged for skin variance: a skin with a larger font or fatter padding overflows the fixed 130px field and the text clips, where the LCL control would grow. AutoSize=True also does n | MEDIUM |
| **成立** | `Options (TDateTimePickerOptions)` | 属性 | A set property with five flags: dtpoDoChangeOnSetDateTime, dtpoEnabledIfUnchecked, dtpoAutoCheck, dtpoFlatButton, dtpoResetSelection. | Five distinct behaviours are frozen at our choice, and a ported .lfm carrying `Options = [dtpoEnabledIfUnchecked]` fails to load. Notably dtpoEnabledIfUnchecked -- letting the user still spin fields while the checkbox is | MEDIUM |
| **成立** | `Escape = revert edit (UndoChanges / ConfirmChanges)` | 语义 | LCL snapshots the value on focus-in (FConfirmedDateTime) and Escape restores that whole snapshot, then fires EditingDone. | The universal "Escape undoes my edit" reflex silently does almost nothing here: a user who spun the month with the arrow keys and pressed Escape keeps the changed month, believing they cancelled. | MEDIUM |
| **成立** | `separator keys advance the selection (/ . , - etc.)` | 语义 | Typing a date/time separator (or the numpad divide/minus/decimal keys) moves the selection to the next field, so a user can type 12/25/2026 straight through. | Touch-typing a full date fails at the first slash: with a 1-digit day the field never auto-advances (2 digits are required, :890-893) and the '/' does nothing, so '1/5/2026' silently becomes something else. This is the m | MEDIUM |
| **成立** | `NullInputAllowed / NullDate` | 属性 | The whole null/empty-date model: NullInputAllowed (default True) lets the user clear the field to a null value (Ctrl-free single 'N' key), represented by the NullDate sentinel and shown as TextForNull | A database NULL date cannot be represented or entered -- the explicit reason the LCL control has the feature. Binding our picker to a nullable column forces the app to invent its own sentinel and to intercept every edit. | LARGE |
| ~~推翻~~ | `OnShowHint` | 事件 | Lets the application rewrite or cancel the hint just before it is shown. | **推翻:** OnShowHint is already published for every TTy control via tyControls.Base.pas:277 (TTyCustomControl) and :154 (TTyGraphicControl). Dynamic hints work today and a ported OnShowHint assignment loads fine. | SMALL |
| ~~推翻~~ | `DateIsNull` | 方法 | Public predicate telling the caller whether the current value is the null sentinel. | **推翻:** Equivalent already provided: Checked (published, default True) is our null flag, per the unit's own contract comment at line 62; DateIsNull is a naming difference, not a missing predicate. | SMALL |
| ~~推翻~~ | `SelectDate` | 方法 | Public method that moves the selection into the DATE portion of the field (first visible date part), skipping hidden parts. | **推翻:** TCustomDateTimePicker renders ONE field that can hold date and time parts together (Kind dtkDateTime), so SelectDate/SelectTime exist to jump the caret between the date block and the time block while skipping FEffectiveH | SMALL |
| ~~推翻~~ | `SelectTime` | 方法 | Public method that moves the selection into the TIME portion of the field. | **推翻:** No impact: SelectTime is meaningful only for LCL's dtkDateTime combined field, which our two-kind model (dtkDate \| dtkTime) does not have. In dtkTime the whole field is the time already. | SMALL |
| ~~推翻~~ | `SendExternalKey / SendExternalKeyCode` | 方法 | Public methods that feed a character or virtual-key code into the picker's editing state machine from outside (used to drive it from an on-screen keypad, a grid editor host, or tests). | **推翻:** Reachable by a different shape: post WM_KEYDOWN/WM_CHAR to the (windowed) picker's Handle — the standard route for every windowed TTy control — or call the protected StepActiveSeg from a descendant. Only the named conven | SMALL |
| ~~推翻~~ | `DateDisplayOrder -> DateFormat` | 改名 | Chooses d-m-y / m-d-y / y-m-d field order, or ddoTryDefault to derive it from the locale ShortDateFormat. | **推翻:** DateDisplayOrder is not missing capability -- DateFormat covers all three orders and its empty default already reproduces ddoTryDefault (locale ShortDateFormat). The only cost is rewriting `DateDisplayOrder = ddoYMD` as  | SMALL |
| ~~推翻~~ | `AddHandlerOnChange / RemoveHandlerOnChange / AddHandlerOnCheckBoxChange / RemoveHandlerOnCheckBoxChange` | 方法 | Multicast handler lists (TMethodList) so several observers can subscribe to OnChange / OnCheckBoxChange without stealing the single event slot, with AsFirst ordering control. | **推翻:** Multiple observers are reachable by chaining: capture the existing OnChange, install your own, invoke the captured one. LCL's multicast lists are a per-control convenience unique to TCustomDateTimePicker, not a framework | MEDIUM |
| ~~推翻~~ | `CustomMonthNames` | 子对象 | A TStrings sub-object holding the 12 user-supplied month names used when MonthDisplay = mdCustom, with a change hook that re-measures the field. | **推翻:** Locale month names already work via the format string; only application-specific overrides would need an owned TStrings, and that is a deliberate design omission, not a lost capability. Depends on 123, which is refuted. | MEDIUM |
| ~~推翻~~ | `CalendarWrapperClass / DefaultCalendarWrapperClass` | 子对象 | A pluggable wrapper class (TCalendarControlWrapperClass) deciding WHICH calendar control the dropdown hosts, per instance or application-wide via the DefaultCalendarWrapperClass variable. | **推翻:** Deliberate architecture, not a missing member: the dropdown hosts our themed TTyCalendar (exposed read-only via the Calendar property) because the library's hard rule bars raw LCL/third-party controls in the self-drawn U | MEDIUM |
| ~~推翻~~ | `Kind (dtkDateTime)` | 类型 | LCL's TDateTimeKind has three members -- dtkDate, dtkTime and dtkDateTime -- the last showing date AND time in one field. | **推翻:** dtkDateTime as an enum literal does not exist, so `Kind := dtkDateTime` and an .lfm carrying it must be rewritten. But combined date+time editing IS supported today: Kind=dtkDate with DateFormat set to a combined pattern | MEDIUM |
| ? | `TimeDisplay` | 属性 | Selects which time fields are editable: tdHM, tdHMS or tdHMSMs (with milliseconds); default tdHMS. | No declarative way to say "I want seconds" -- users must know FormatDateTime pattern syntax and hand-write 'hh:nn:ss'; a ported `TimeDisplay = tdHMS` line does not load. | SMALL |
| ? | `TextForNullDate` | 属性 | The caption drawn when the value is null; default the literal 'NULL'. | Even if null support is added later, there is no property to localise or blank the placeholder; ported forms carrying `TextForNullDate = ''` fail to load. | SMALL |
| ? | `DateSeparator` | 属性 | Overrides the character(s) drawn between date fields, independently of the locale. | Ported forms lose the property; users wanting 2026-07-30 with the locale's own field order must hand-build a format string instead of setting one character. | SMALL |
| ? | `TimeSeparator` | 属性 | Overrides the character(s) between time fields. | Same as DateSeparator: an .lfm/`DTP.TimeSeparator := '.'` port break, and no one-value way to change ':' to '.'. | SMALL |
| ? | `DecimalSeparator` | 属性 | The separator drawn before the millisecond field. | Ported property assignment fails; blocked anyway by the missing millisecond part. | SMALL |
| ? | `UseDefaultSeparators` | 属性 | Switch that snaps all three separators back to the current locale's values (and keeps them following it). | No published way to say "go back to the locale"; the ported property fails to load. | SMALL |
| ? | `TrailingSeparator` | 属性 | Draws a trailing separator after the last field (e.g. '2026.07.30.'), needed by locales that write dates that way; default False. | Hungarian/Japanese-style trailing-dot dates are not expressible as a setting; ported forms lose the property. | SMALL |
| ? | `ArrowShape` | 属性 | Per-instance choice of the drop-down arrow's drawing: asClassicSmaller, asClassicLarger, asModernSmaller, asModernLarger, asYetAnotherShape or asTheme (default). | Two pickers on one form cannot differ in arrow style, and a ported `ArrowShape = asClassicSmaller` line fails to load. | SMALL |
| ? | `CalAlignment` | 属性 | Aligns the dropped calendar to the picker's left or right edge (dtaLeft/dtaRight/dtaDefault, where default follows BiDiMode). | A wide picker near the right screen edge cannot be told to right-align its calendar; ported property fails to load. | SMALL |
| ? | `AutoButtonSize` | 属性 | Scales the drop-down/spin button width with the control's height instead of using a fixed width; default False. | On a deliberately tall picker (touch/HiDPI form) our button stays narrow and looks detached; the ported property fails to load. | SMALL |
| ? | `AutoAdvance` | 属性 | Whether finishing a field's digits jumps the selection to the next field; default True, and settable to False. | Users who type a day, notice a typo and expect to keep typing in the same field are pushed to the next one with no way to turn that off; ported property fails to load. | SMALL |
| ? | `Date, Time (published)` | 属性 | LCL republishes both Date and Time on the concrete picker, so each is settable in the Object Inspector and streamed to the .lfm. | The properties work from code but are invisible in the Object Inspector and are dropped on save, so an .lfm ported from Lazarus that carries `Date = 45000` (or a designer-set Time) fails to stream in. | SMALL |
| ? | `MonthDisplay` | 属性 | Shows the month as a NAME rather than a number: mdShort, mdLong (default) or mdCustom. | A named-month picker ('30 July 2026') is impossible, and typing 'mmm' into DateFormat is silently downgraded to a 2-digit number -- a format string that appears to be ignored. | MEDIUM |
| ? | `HideDateTimeParts` | 属性 | A set (TDateTimeParts over dtpDay..dtpMiliSec) that removes individual fields from the control -- e.g. a month+year-only picker -- with AMPM hiding tied to hour. | The common month/year-only or hour-only picker needs a format-string rewrite here, and a ported `HideDateTimeParts = [dtpDay]` line fails to load. | MEDIUM |
| ? | `Cascade` | 属性 | When True, spinning a field CARRIES into the neighbouring one (hour 23 +1 -> next day; month 12 +1 -> next year); default False. | Spinning past the end of a field can never roll the date the way a user scrubbing a timestamp expects; the ported property fails to load and the behaviour it selects is unreachable. | MEDIUM |
| ? | `BiDiMode / ParentBiDiMode (RTL layout)` | 属性 | Right-to-left layout: the field's text origin, part order, checkbox side and button side all mirror, with an overridden SetBiDiMode re-arranging the sub-controls. | Arabic/Hebrew forms get an LTR field inside an RTL layout -- the checkbox and drop-down button land on the wrong side and the ported BiDiMode property fails to load. Fixing it means mirroring every rect and the click hit | LARGE |

### `TTyStringGrid`  (对标 `TCustomGrid`) — 44 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `SortColRow(IsColumn=False, ...)` | 方法 | Sort by a ROW - i.e. reorder the COLUMNS according to the values in one row - and the range-limited overload SortColRow(IsColumn, Index, FromIndex, ToIndex). | Transposed / matrix-style grids cannot be sorted along the other axis, and no sort can be limited to a sub-range of rows. | SMALL |
| **成立** | `RangeSelectMode: TRangeSelectMode` | 属性 | Chooses rsmSingle (one selection rectangle) or rsmMulti (Ctrl-click builds several disjoint rectangles). | An app whose logic assumes exactly one selected block (the LCL default) gets multi-range behaviour it cannot switch off, and its 'the selection' code silently sees only the last block. | SMALL |
| **成立** | `ExtendedSelect` | 属性 | Whether Shift+click / Shift+arrow extends the selection at all. | A single-cell-only grid cannot forbid range selection. | SMALL |
| **成立** | `Modified: Boolean` | 属性 | Read/write dirty flag set by any cell edit; the grid maintains it so the app can prompt 'save changes?'. | Every host reimplements the dirty flag by hooking OnCellEdited, and any edit path we add later (paste, fill handle, undo) has to be remembered again in each app. | SMALL |
| **成立** | `SaveToCSVStream(..., VisibleColumnsOnly) / LoadFromCSVStream(..., SkipEmptyLines)` | 属性 | Skip hidden columns when exporting; skip blank lines when importing. | Exporting a grid whose columns the user hid still dumps the hidden data - a surprise and, for some data, a leak; and a CSV with blank separator lines imports phantom empty rows. | SMALL |
| **成立** | `Selection: TGridRect (writable)` | 改名 | Read AND write the selection rectangle in one property; assigning it moves the selection (and, with goSelectionActive, the cursor too). | 'Grid.Selection := R' - a normal LCL idiom, including round-tripping a saved rect - has to be rewritten as SelectRange with four arguments. | SMALL |
| **成立** | `ClearSelections` | 改名 | Drops all committed selection ranges (plural - the multi-select list). | One-character porting break on a routinely-called method. | SMALL |
| **成立** | `EditorMode: Boolean (writable)` | 改名 | Read/write property: setting True opens the in-place editor on the current cell, False closes it; reading tells you whether it is open. | 'Grid.EditorMode := True' is the standard way to drop into edit mode from a toolbar button; it needs rewriting, and there is no single settable property to bind to. | SMALL |
| **成立** | `Clear` | 改名 | Empties the whole grid: removes non-fixed rows AND columns and their content in one call. | Grid.Clear - probably the single most-typed grid call - does not exist, and the nearest name does something narrower, so a port that maps Clear->ClearCells leaves the old columns behind. | SMALL |
| **成立** | `DeleteCol / DeleteColRow / InsertColRow / ExchangeColRow / MoveColRow` | 改名 | The IsColumn-parameterised structural family, so one call site handles both axes, plus the singular DeleteCol name. | Generic 'delete whichever axis the user picked' code must be un-generalised; DeleteCol->DeleteColumn is a silent compile break; and swapping two COLUMNS has no method at all. | SMALL |
| **成立** | `HideSortArrow` | 改名 | Clears the sort indicator from the header without changing the row order. | Server-side-sorted grids (where the host sorted the data and only wants the glyph managed) cannot show or hide the arrow independently of our own sorting. | SMALL |
| **成立** | `OnButtonClick / OnEditButtonClick` | 改名 | Fires when the button in a cbsButton / cbsEllipsis / cbsButtonColumn cell is pressed, with (aCol, aRow). | Two names to discover instead of one, and neither matches ported code. | SMALL |
| **成立** | `OnCheckboxToggled` | 改名 | Fires after a checkbox cell is toggled, with the new state. | Straight rename break on a commonly used event. | SMALL |
| **成立** | `OnCellProcess: TCellProcessEvent` | 改名 | One event that transforms a cell's text on BOTH copy and paste (cpCopy / cpPaste discriminated by a parameter). | 'strip the currency symbol on copy' has to be done by rewriting the whole clipboard blob instead of per cell. | SMALL |
| **成立** | `OnGetEditText / OnSetEditText` | 事件 | The editor's value is fetched from and written back to the host, letting the string shown in the editor differ from the cell's display text, and letting the grid edit data it does not store. | A virtual grid backed by the host's own data cannot be made editable through TTyDrawGrid at all, and 'edit the raw number while displaying a formatted one' has no hook. | MEDIUM |
| **成立** | `SelectedRange[AIndex] / SelectedRangeCount / HasMultiSelection` | 方法 | Enumerate the disjoint selection rectangles: how many there are, each one's TGridRect, and a quick 'is more than one thing selected'. | We let the user Ctrl-click several blocks and then give the host no way to find out what they picked - a host iterating 'the selection' processes only the last rectangle and silently drops the rest. | MEDIUM |
| **成立** | `SaveToFile / LoadFromFile + SaveOptions: TSaveOptions + OnSaveColumn / OnLoadColumn` | 方法 | Persist the whole grid to an XML file and read it back, choosing what to include (soDesign = col/row count and Options, soAttributes = font/brush/text style, soContent = cell text, soPosition = cursor | 'Grid.SaveToFile(f) / LoadFromFile(f)' - the one-line way to persist a whole grid including its content and cursor - has no counterpart; the host must roll its own format and cannot round-trip attributes or cursor positi | MEDIUM |
| **成立** | `OnSelectEditor` | 改名 | Fires with (Sender; aCol, aRow; var Editor: TWinControl) so the host can swap in a different editor control for one cell by simple assignment. | Swapping an editor per cell goes from a one-line var-assignment to writing and owning a class; a very common LCL pattern does not port mechanically. | MEDIUM |
| **成立** | `OnValidateEntry` | 改名 | Fires with (ACol, ARow; const OldValue; var NewValue): boolean - the host may rewrite the value or reject the edit, paired with ValidateOnSetSelection so the check also runs when the cursor is moved p | Ported validation handlers do not compile; and the 'normalise what the user typed' half of validation (trim, upcase, reformat a date) is impossible - only accept/reject is. | MEDIUM |
| **成立** | `VisibleRowCount` | 语义 | THEIRS: how many rows currently fit in the viewport (a viewport metric, used for PageUp/PageDown maths). OURS: how many data rows pass the filter (a data metric). | Ported code that scrolls by VisibleRowCount pages silently computes garbage - with 10000 filtered-in rows it will page 10000 rows at a time. The name collides while meaning something else. | MEDIUM |
| **成立** | `Editor: TWinControl (writable) / InplaceEditor` | 语义 | Editor is READ/WRITE: assign any TWinControl (or one produced by EditorByStyle) and the grid drives it as the cell editor. InplaceEditor is the read-only view of the same field. | Code that does 'Grid.Editor := MyCombo' - the documented LCL way to plug in a custom editor - has to be rewritten as an EditLink subclass; and 'Editor' on our side means something narrower (a TTyEdit) than the same ident | MEDIUM |
| **成立** | `SaveToStream / LoadFromStream` | 语义 | THEIRS: writes/reads the full grid state as XMLConfig (structure + attributes + content + position, gated by SaveOptions). OURS: same names, but the payload is plain CSV text with a delimiter. | Signature-compatible enough to compile in ported code but writes a completely different format, so a stream written by one and read by the other loses everything except cell text - and column layout/cursor silently vanis | MEDIUM |
| **成立** | `ClearRows / ClearCols` | 语义 | THEIRS: ClearRows/ClearCols DELETE all non-fixed rows/columns (structure) and return Boolean 'anything changed'. OURS: same two names take (AFrom, ACount) and blank the cell CONTENT of a range, return | The most dangerous kind of collision: 'if Grid.ClearRows then' fails to compile in the good case, and any wrapper that calls ClearRows expecting the grid to empty out instead clears a two-cell band. Also, no method exist | MEDIUM |
| **成立** | `SaveToCSVStream(..., WriteTitles) / LoadFromCSVStream(..., UseTitles)` | 语义 | CSV round-trip where the header row is OPTIONAL: WriteTitles=False emits data only, UseTitles=False treats line 0 as data. | Headerless CSV is impossible in both directions: exporting data-only for a downstream tool, and importing a file that has no header, which silently eats the first data row as captions. | MEDIUM |
| **成立** | `Objects[ACol, ARow]: TObject` | 属性 | An arbitrary object pointer stored per cell alongside its text - the standard place to hang the record a row came from. | 'which database record is this row?' has no storage; hosts must keep a parallel array keyed by row index and re-sync it on every insert, delete, sort and move - exactly the bookkeeping the grid already does for its own c | LARGE |
| **成立** | `Cols[index]: TStrings / Rows[index]: TStrings (TStringGridStrings)` | 子对象 | A whole column or row exposed as a live, ASSIGNABLE TStrings - 'Grid.Rows[3] := MyList', 'Memo.Lines := Grid.Cols[0]', Rows[r].CommaText, and per-cell Objects through it. The item class TStringGridStr | The whole idiom of filling or reading a grid row-at-a-time (and of piping a row into any TStrings consumer) is unavailable; every port has to be rewritten as a per-cell loop. | LARGE |
| ~~推翻~~ | `AutoAdjustColumns / AutoSizeColumns` | 方法 | Auto-fit EVERY column to its content in one call (LCL has both the TCustomGrid virtual and the string-grid pair AutoSizeColumn / AutoSizeColumns). | **推翻:** Missing is only the all-columns wrapper (a for-loop over Header.Columns calling AutoFitColumn), which is asymmetric with the AutoFitRows we do ship (Grid.pas:10010-10018). Worth adding as sugar; not a capability gap. | SMALL |
| ~~推翻~~ | `InsertRowWithValues(Index; Values: array of String)` | 方法 | Insert a row and fill it from an open array in one call - the standard way to populate a string grid. | **推翻:** Pure convenience-signature gap. Route today: InsertRow + Cells[] (or LoadFromCSVText / PasteFromText for whole tables), wrapped in BeginUpdate/EndUpdate and OpenUndoGroup/CloseUndoGroup so it is one undo step and one rep | SMALL |
| ~~推翻~~ | `Clean / Clean(CleanOptions: TGridZoneSet) / Clean(aRect, ...) / Clean(StartCol,StartRow,EndCol,EndRow, ...)` | 改名 | Four overloads that blank cell content, optionally restricted to a rectangle AND to grid zones (gzNormal / gzFixedCols / gzFixedRows / gzFixedCells) - so 'clear the data but keep the header captions'  | **推翻:** Zone-filtered clearing is a non-issue in our model (captions are column objects, never cells, so ClearCells preserves them; ClearRows/ClearCols take a band and can skip FixedRows). Only the rect-restricted Clean overload | SMALL |
| ~~推翻~~ | `CopyToClipboard(AUseSelection: boolean = false)` | 改名 | Copy the WHOLE grid, or just the selection, depending on the argument. | **推翻:** Whole-grid export without touching the selection already works via SaveToCSVText/SaveToHTMLText; only the CopyToClipboard(AUseSelection) name and LCL's specific clipboard formats are missing. | SMALL |
| ~~推翻~~ | `SortOrder: TSortOrder (writable)` | 类型 | Read/WRITE the current sort direction; assigning it flips the sort without naming a column. | **推翻:** LCL's SortOrder write is a plain field assignment that changes nothing until a sort is triggered; ours folds direction into SortByColumn(ACol,ADirection) and ToggleSortColumn(SortColumn) reverses in place. Name/read-only | SMALL |
| ~~推翻~~ | `OnBeforeSelection / OnAfterSelection / OnSelection` | 类型 | Three TOnSelectEvent hooks (Sender; aCol, aRow) around a selection change: before it commits, after it commits, and during rubber-banding. | **推翻:** The genuine residue is a naming/typing gap only: OnBeforeSelection/OnAfterSelection/OnSelection do not exist by name, and the post-move notification carries no (aCol,aRow). Before-with-coords is covered by OnSelectCell,  | SMALL |
| ~~推翻~~ | `DefaultDrawCell` | 方法 | Lets an OnDrawCell handler call the grid's own default painting for that cell, then draw on top of it. | **推翻:** We invert LCL's shape: default painting brackets the hook (background before, text after unless AHandled) instead of being callable from inside it. Consequence is only z-order - an overlay drawn in the handler ends up un | MEDIUM |
| ? | `OnPickListSelect` | 事件 | Fires when the user picks an item from a cell's drop-down pick list. | Cascading drop-downs ('choose a country, now reload the city list') have no hook to trigger on. | SMALL |
| ? | `OnGetEditMask` | 事件 | Supplies a per-CELL edit mask on demand. | A settings-style grid where the mask depends on the row (phone here, postcode there) needs one column per format. | SMALL |
| ? | `OnUserCheckboxBitmap / OnUserCheckboxImage` | 事件 | Let the host supply the bitmap / image-list entry used to draw a checkbox cell in a given state. | Tri-state or domain-specific marks (a lock icon, a partial tick) cannot replace the standard check glyph per cell. | SMALL |
| ? | `AutoEdit` | 属性 | When True a plain click on the focused cell opens the editor straight away; when False editing needs F2 / a second click. | A grid used mainly for browsing cannot suppress accidental edit-on-click, and a fast-entry grid cannot turn it on. | SMALL |
| ? | `SelectActive` | 属性 | Read/write flag saying a rubber-band selection is in progress; setting it starts/stops range extension from code (what Shift+arrow does internally). | Code that drives selection extension programmatically (e.g. a 'select to end' command) cannot put the grid into extend mode. | SMALL |
| ? | `FastEditing` | 属性 | Typing a printable character on a focused cell immediately opens the editor and seeds it with that character (spreadsheet type-over). | Data-entry users cannot get (or turn off) the Excel-like 'just start typing' behaviour. | SMALL |
| ? | `StrictSort` | 属性 | Forces a strict (total-order, no equal-keys shortcut) comparison during sorting. | Rows with equal keys can reorder unpredictably between sorts with no way to demand determinism. | SMALL |
| ? | `OnColRowDeleted / OnColRowInserted / OnColRowExchanged / OnColRowMoved` | 事件 | Four AFTER-the-fact structural notifications (IsColumn, index / FromIndex, ToIndex) so the host can keep its parallel data in step. | A host keeping its own array beside the grid gets told it MAY delete a row but never that the deletion happened, so it must guess or re-scan; and code ported from the LCL events silently stops running. | MEDIUM |
| ? | `OnGetCheckboxState / OnSetCheckboxState` | 事件 | The host supplies and receives the checkbox state of a cell (TCheckboxState) instead of the grid deriving it from cell text. | Checkbox columns must be backed by our string convention; a host holding real booleans cannot feed them in, and a virtual grid cannot have working checkboxes at all. | MEDIUM |
| ? | `AutoAdvance: TAutoAdvance / TabAdvance: TAutoAdvance` | 属性 | Where the cell cursor goes after a commit (aaNone, aaDown, aaRight, aaLeft, aaRightDown, aaLeftDown, aaRightUp, aaLeftUp), with a separate direction for the Tab key. | Data-entry grids that must advance down a column after Enter (the classic ledger pattern) cannot be configured - the host has to intercept keys itself. | MEDIUM |
| ? | `CellHintPriority + goTruncCellHints + GetTruncCellHintText` | 属性 | Automatically hints the FULL text of a cell whose text is truncated, and chooses how that combines with the control Hint and OnGetCellHint (chpAll / chpAllNoDefault / chpTruncOnly). | Narrow columns clip their content to '...' and the user has no way to read it - the single most-noticed missing affordance in a grid with fixed column widths. | MEDIUM |

### `TTyTreeView`  (对标 `TCustomTreeView / TTreeNodes / TTreeNode`) — 38 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `RowSelect / MultiSelect / ShowLines / ReadOnly (option-vs-property naming)` | 改名 | The four most-used TTreeView switches: full-row selection, multi-select, connector lines, and whether F2/click editing is allowed. | Every ported line — Tree.RowSelect := True, Tree.MultiSelect := True, Tree.ShowLines := False, Tree.ReadOnly := False — fails to compile, and the ReadOnly default is inverted, so ported code silently loses inline editing | SMALL |
| **成立** | `DefaultItemHeight (+ tvoAutoItemHeight)` | 改名 | Default row height, optionally auto-derived from the font. | Tree.DefaultItemHeight := 24 does not compile, and rows never follow the control's Font size (they follow the theme token instead). | SMALL |
| **成立** | `Selections[AIndex] / SelectionCount / GetFirstMultiSelected / GetLastMultiSelected` | 改名 | Random-access to the multi-selection list plus its count. | `for i := 0 to Tree.SelectionCount-1 do Use(Tree.Selections[i])` — the standard multi-select loop — has to be rewritten as a pointer walk. | SMALL |
| **成立** | `OnEditingEnd / OnEdited naming` | 改名 | OnEdited hands back the edited string for validation/rewrite; OnEditingEnd fires once whether the edit was committed or cancelled (Cancel: Boolean). | An edit cannot be validated-and-corrected on commit (the text is const), and 'the editor closed, re-enable my buttons' needs two handlers instead of one. | SMALL |
| **成立** | `OnHasChildren` | 改名 | Function event asked whether a node has children, so a lazy tree can show an expander without materialising the children. | A node that gains children later (a directory that becomes non-empty) cannot be re-asked; you must re-init the node with ivsReInit. | SMALL |
| **成立** | `NodeEffect (and the Ghosted out-param)` | 语义 | Per-node image draw effect (gdeNormal/gdeDisabled/gdeHighlighted/gde1Bit) — e.g. a greyed icon for a cut or unavailable node. | Setting Ghosted:=True in OnGetImageIndex looks supported and does nothing; there is no way to grey a node's icon. | SMALL |
| **成立** | `Images type` | 类型 | The node image list. LCL accepts any TCustomImageList descendant. | Code that keeps its icons in a TCustomImageList descendant (including this library's own TTyVirtualImageList, which TTyListView requires) will not compile against TTyTreeView.Images. | SMALL |
| **成立** | `Selected: TTreeNode` | 类型 | The one selected/current node — read it, or assign a node to select it. | The single most-typed line in TreeView code (`if Tree.Selected <> nil then ... Tree.Selected.Text`) compiles to something completely different or not at all — a silent porting trap rather than a clean error. | SMALL |
| **成立** | `GetNodeAt(X, Y)` | 类型 | Returns the node at a client point. | `Tree.GetNodeAt(X, Y)` compiles against ours (Y is taken as the scroll-space Y, X's value is written into ANodeTop) and returns the wrong node instead of failing — the worst kind of porting break. | SMALL |
| **成立** | `OnChanging (vetoable selection change)` | 事件 | Fires before the selection moves; setting AllowChange := False cancels it (e.g. 'you have unsaved edits on this node'). | You cannot keep the user on a node with pending edits; the selection has already moved by the time you hear about it. | MEDIUM |
| **成立** | `OnCustomDraw / OnCustomDrawItem / OnAdvancedCustomDraw / OnAdvancedCustomDrawItem (whole-control and staged dr` | 事件 | Custom drawing of the whole control or a whole node row, with pre/post stages and a DefaultDraw veto, plus PaintImages control. | You cannot repaint a whole row (e.g. a full-width status band behind the node) or draw beneath the default content — only after it, cell by cell. | MEDIUM |
| **成立** | `SortType / AlphaSort / CustomSort` | 属性 | SortType (stNone/stData/stText/stBoth) keeps a tree auto-sorted as nodes are added; AlphaSort sorts by text with no handler; CustomSort(SortProc) sorts with a plain function. | 'Sort this tree alphabetically' needs an OnCompareNodes handler, and there is no auto-resort-on-insert mode at all. | MEDIUM |
| **成立** | `Visible` | 属性 | Hide an individual node (and its subtree) without deleting it — used for filtering. | Filtering a tree means deleting and re-adding nodes; the engine already supports invisible nodes but the switch is not exposed. | MEDIUM |
| **成立** | `Enabled (per node) + DisabledFontColor + aEnabledOnly navigation` | 属性 | Grey out a single node so it cannot be selected, with a dedicated disabled ink colour, and skip such nodes when navigating. | You cannot present an unavailable node; the whole tree is all-or-nothing enabled. | MEDIUM |
| **成立** | `Cut / DropTarget (per-node display states)` | 属性 | Mark a node as cut (dimmed, for clipboard cut) or as the current drop target (highlight box while dragging over it). | External drag-and-drop cannot highlight the node under the cursor, and a cut/paste UI has no dimmed-source feedback. | MEDIUM |
| **成立** | `DisplayRect / DisplayTextLeft / DisplayExpandSignRect / Node.Top / Node.Bottom / GetNodeWithExpandSignAt` | 改名 | Per-node geometry: the row rect, the text-only rect, the expander rect, and the node's absolute Y — used for custom hit-tests, in-place editors and drag feedback. | Custom overlays/tooltips anchored to a node's text (not its whole cell) cannot be positioned, and off-screen node geometry is unavailable. | MEDIUM |
| **成立** | `SelectedIndex / StateIndex / OverlayIndex / StateImages / OnGetSelectedIndex` | 语义 | A node can show a different icon when selected, a second 'state' icon from a separate image list, and an overlay badge. | The API advertises four image kinds but only the normal one works; a folder tree cannot show an open-folder icon on the selected node, and checkbox/state overlays via StateImages are impossible. | MEDIUM |
| **成立** | `OnDragOver name/type collision` | 语义 | LCL's OnDragOver is the standard drag-and-drop hook: procedure(Sender, Source: TObject; X, Y: Integer; State: TDragState; var Accept: Boolean). | You cannot use the tree as an LCL drop target at all — the property that would do it is taken by an unrelated internal event, and assigning a normal TDragOverEvent handler is a type error. | MEDIUM |
| **成立** | `Items: TTreeNodes (whole node object model)` | 子对象 | A streamable, design-time-editable tree of TTreeNode objects: Items.AddChild(nil,'Root'), the OI 'TreeView Items Editor', nodes saved in the .lfm, Items.Count/Item[i]/TopLvlItems, Items.BeginUpdate/En | A TTreeView can be filled in the designer and shipped in the .lfm; a TTyTreeView cannot be populated at all without writing OnGetText/OnInitNode code. Every ported unit that touches Tree.Items fails to compile. | LARGE |
| ~~推翻~~ | `Select(Node, ShiftState) / Select(array of TTreeNode) / Select(TList)` | 方法 | Programmatically set the selection, either honouring a shift-state (as if clicked) or replacing it with a whole set of nodes at once. | **推翻:** Batch selection already exists under other names: public event-free InternalSetSelected for arbitrary sets, SelectRange(anchor, target) for ranges, SelectAll, ClearSelection, and GetFirstSelected/GetNextSelected to save  | SMALL |
| ~~推翻~~ | `AddFirst / Insert / InsertBehind / AddChildFirst / AddNode(..., TNodeAttachMode) / Node.MoveTo` | 方法 | Create or relocate a node at a chosen position: as first child, before/behind a given sibling, or via naAdd/naAddFirst/naAddChild/naAddChildFirst/naInsert/naInsertBehind. | **推翻:** Arbitrary placement and relocation exist under different names: MoveNode/CanMoveNode/IsDescendant (dmAbove/dmOn/dmBelow) are the MoveTo + naInsert/naInsertBehind/naAddChild equivalents, and Sort/SortTree handle ordered i | MEDIUM |
| ~~推翻~~ | `BeginUpdate / EndUpdate` | 方法 | Suppresses repaint/relayout while a batch of nodes is added or changed, then does one update. | **推翻:** No measurable bulk-load cost: layout invalidation is O(1) and deferred, cache rebuild and paint happen once. The bulk-load idiom here is RootNodeCount / SetChildCount, not a Begin/EndUpdate bracket. Only source-level com | MEDIUM |
| ~~推翻~~ | `LoadFromFile / LoadFromStream / SaveToFile / SaveToStream` | 方法 | Persist the whole node tree (text + image indices + expanded state) to a text file or stream and read it back. | **推翻:** Not a separate gap. LCL's tree serialisation is only meaningful because TTreeNode owns the text; in a virtual tree the app owns the data and therefore the file format. If 613 is ever closed with an item layer, persistenc | MEDIUM |
| ~~推翻~~ | `StoreCurrentSelection / ApplyStoredSelection / LockSelectionChangeEvent / UnlockSelectionChangeEvent / Selecti` | 方法 | Save the selection by text path and restore it after a refresh, suppress OnSelectionChanged while doing bulk work, and scroll/clean the selection. | **推翻:** Only StoreCurrentSelection/ApplyStoredSelection is genuinely missing, and it is not portable to this control: LCL stores selection as text paths because TTreeNode owns its caption, whereas TTyTreeView is a virtual tree w | MEDIUM |
| ~~推翻~~ | `MoveToNextNode / MoveToPrevNode / MovePageDown / MovePageUp / MoveLeft / MoveRight / MoveExpand / MoveCollapse` | 方法 | Public keyboard-motion API so an external toolbar/shortcut can drive the tree exactly as the arrow keys do. | **推翻:** Cosmetic naming gap, not a capability gap. Eight of the ten are one-liners over already-public primitives; only MovePageUp/MovePageDown need arithmetic the app must write itself (ClientHeight/DefaultNodeHeight/ContentHei | MEDIUM |
| ~~推翻~~ | `FindNodeWithText / FindNodeWithTextPath / FindNodeWithData / FindNode / IndexOfText / GetTextPath / PathDelimi` | 方法 | Locate a node by its caption, by a delimited caption path ('Root/Child/Leaf'), or by its Data pointer; and produce a node's text path. | **推翻:** Not a real gap for this node model. Find-by-data and find-by-text are ~5 lines over the public structural walk GetFirst/GetNext (:491-492) plus GetNodeData/OnGetText, and the app usually already holds the pointer↔key map | MEDIUM |
| ~~推翻~~ | `GetPrev / GetNextSkipChildren / GetLastSubChild / GetFirstSibling / GetLastSibling / GetNextChild / GetPrevChi` | 方法 | The rest of the node-traversal vocabulary: full-tree backwards walk, skip a subtree, jump to the deepest last node, first/last sibling, child stepping, ancestor at a given level. | **推翻:** No missing traversal capability — only missing aliases. The one true structural absentee is a full-tree structural GetPrev (we have the visible-order GetPreviousVisibleNoInit), which differs only across collapsed subtree | MEDIUM |
| ~~推翻~~ | `DeleteChildren / ExpandParents / MakeVisible / MultiSelectGroup` | 方法 | Delete just a node's children, expand every ancestor so a node becomes reachable, scroll it into view, and select a whole sibling group. | **推翻:** Only ExpandParents is absent, and it is a four-line loop over the public writable Expanded[] (:516) and GetParent (:489). The real finding hiding inside this claim is a behavioural trap worth logging separately: ScrollIn | MEDIUM |
| ? | `ShowSeparators / SeparatorColor` | 属性 | Draws a horizontal separator line under each top-level row, in a settable colour. | No row rules in a tree; a report-style tree cannot show the separators the LCL control offers. | SMALL |
| ? | `AutoExpand` | 属性 | Automatically expands the node that gains focus and collapses the previous one. | A navigation tree that opens as you move through it must be hand-coded in OnFocusChanged. | SMALL |
| ? | `RightClickSelect` | 属性 | A right-click moves the selection to the clicked node before the popup menu opens. | A context menu on a tree acts on whatever was selected before the right-click — the classic 'wrong node' bug. | SMALL |
| ? | `OnAddition / OnDeletion / OnNodeChanged` | 事件 | Fires when a node is added, when one is about to be freed (release app-side data), and when any node property changed (with a TTreeNodeChangeReason). | An app mirroring the tree into its own model gets no add/change notifications, only OnFreeNode. | MEDIUM |
| ? | `InsertMarkNode / InsertMarkType / SetInsertMark / SetInsertMarkAt / GetInsertMarkAt (+ tvoAutoInsertMark)` | 属性 | Draws an insertion caret between nodes while dragging (as-first-child / as-prev-sibling / as-next-sibling), optionally maintained automatically. | A reorder-by-drag UI built on standard LCL drag-and-drop has no way to show where the node will land. | MEDIUM |
| ? | `TopItem / BottomItem / ScrolledLeft / ScrolledTop (writable scroll position)` | 属性 | Read and SET the scroll position: which node is at the top, and the pixel scroll offsets. | Save/restore of a tree's scroll position across a refresh is impossible; you can only re-scroll to a node. | MEDIUM |
| ? | `ExpandSignType / ExpandSignSize / ExpandSignWidth / ExpandSignColor / OnCustomDrawArrow` | 属性 | Chooses the expander look (themed / +- / arrow / filled arrow / angle bracket), its size, line thickness and colour, or lets you draw it yourself. | The expander is always a chevron in the node text colour — a Win-classic +/- tree or a custom arrow is impossible, and the theme's own glyph token does not even reach it. | MEDIUM |
| ? | `TreeLineColor / TreeLinePenStyle` | 属性 | Colour and pen style (psPattern/psDot/psSolid) of the connector lines between nodes. | Tree lines cannot be recoloured or dotted, and they silently inherit whatever the theme sets as the control's border colour — so no themed equivalent exists either. | MEDIUM |
| ? | `MultiSelectStyle (msControlSelect/msShiftSelect/msVisibleOnly/msSiblingOnly)` | 属性 | Controls what multi-select is allowed to do: ctrl-click, shift-range, visible nodes only, siblings only. | A tree that should only allow selecting siblings (or only visible nodes) cannot be restricted; the gesture set is fixed. | MEDIUM |
| ? | `Text` | 属性 | Per-node caption stored on the node: Node.Text := 'x' / s := Node.Text. | Node captions cannot be set or read at all; every tree needs an OnGetText handler plus an app-side text store, so the simplest possible use (a static tree of labels) is impossible. | LARGE |

### `TTyCustomGrid`  (对标 `TCustomGrid`) — 35 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `DefaultColWidth` | 属性 | Width new/unsized columns get, the column twin of DefaultRowHeight. | Setting a uniform column width for a wide grid means writing a loop; and the theme's density axis cannot drive column width the way it drives DefaultRowHeight. | SMALL |
| **成立** | `GridWidth / GridHeight` | 属性 | Read-only total pixel extent of all columns / rows - what you compare against ClientWidth to know whether the content overflows. | A host that wants to size a panel to the grid's content, or decide whether scrolling is needed, has to re-sum the column widths itself. | SMALL |
| **成立** | `ColWidths[aCol]` | 改名 | Indexed read/write column width in pixels, the twin of RowHeights[]. | The RowHeights/ColWidths symmetry every LCL grid user relies on is broken; column width needs a two-step cast through the header. | SMALL |
| **成立** | `ScrollBars: TScrollStyle` | 改名 | Single published property selecting ssNone / ssHorizontal / ssVertical / ssBoth / ssAutoHorizontal / ssAutoVertical / ssAutoBoth. | ScrollBars=ssNone in a ported .lfm raises 'Unknown property'; and even in code the ty equivalents cannot be set at design time. | SMALL |
| **成立** | `FadeUnfocusedSelection` | 改名 | Draw the selection dimmed when the grid does not have focus. | Different name plus not designer-settable: a ported .lfm fails on the property, and the ty equivalent cannot be set in the Object Inspector. | SMALL |
| **成立** | `FocusRectVisible` | 改名 | Whether the focus rectangle is drawn around the current cell. | Ported .lfm breaks, and the ty property is invisible in the designer. | SMALL |
| **成立** | `TitleImageList / TitleImageListWidth` | 改名 | A dedicated image list for column-title icons, plus a width used to pick the right resolution at high DPI. | Header icons and cell images must come from the same list, so they cannot be sized independently; and the published Header.Images property is dead - anything a user assigns there is ignored. | SMALL |
| **成立** | `OnHeaderClick: THdrEvent (IsColumn, Index)` | 类型 | Fires for a click on a column header OR a row header, saying which axis it was. | 'user clicked row header 5 - select that record' has no event; and ported handlers with the (IsColumn, Index) signature do not compile. | SMALL |
| **成立** | `OnTopLeftChanged` | 事件 | Fires whenever the first visible cell changes, i.e. on every scroll. | Anything that must track the viewport - a synchronised second grid, a lazy data fetch for the visible window, a scroll-position save - has no hook at all and must poll. | MEDIUM |
| **成立** | `InvalidateCell / InvalidateCol / InvalidateRow / InvalidateRange` | 方法 | Repaint exactly one cell, one column, one row, or a rectangle of cells. | A host that changes one cell from a timer or a socket must repaint the entire grid; on a big grid that is the difference between a smooth live view and a flickering one. | MEDIUM |
| **成立** | `AutoFillColumns` | 属性 | Distributes all spare width across every column proportionally, honouring each column's MinSize/MaxSize/SizePriority. | A grid that should share its width across all columns on resize can only fatten one designated column; the spring code we already have is unreachable from any control. | MEDIUM |
| **成立** | `HeaderHotZones / HeaderPushZones: TGridZoneSet (goHeaderHotTracking / goHeaderPushedLook)` | 属性 | Which fixed zones (gzFixedCols, gzFixedRows, gzFixedCells) hot-track under the mouse and which render pushed while clicked. | Header sections never highlight on hover and never look pressed on click, so the header does not read as clickable - and the hoHotTrack flag a user sets in the Object Inspector silently does nothing. | MEDIUM |
| **成立** | `GridLineStyle` | 语义 | THEIRS: the pen style of the grid lines (psSolid, psDash, psDot, psDashDot...). OURS: which AXES get lines (glsNone/glsHorizontal/glsVertical/glsBoth). Same identifier, unrelated meaning and incompati | The worst kind of porting break: GridLineStyle := psDot compiles-fails, and a .lfm carrying GridLineStyle=psDash streams into our enum by ordinal and silently means 'horizontal lines only'. Also: no dotted/dashed grid, a | MEDIUM |
| ~~推翻~~ | `OnMouseWheelHorz / OnMouseWheelLeft / OnMouseWheelRight` | 事件 | Horizontal wheel / tilt-wheel notifications. | **推翻:** OnMouseWheelHorz/Left/Right are already published on the ancestor TTyCustomControl (tyControls.Base.pas:272-274), with a comment naming 'a wide grid' as the motivating case, so TTyCustomGrid inherits all three as publish | SMALL |
| ~~推翻~~ | `OnShowHint` | 事件 | Last-chance hook to rewrite or suppress the hint just before it is shown. | **推翻:** OnShowHint is already published on both TTy base classes (tyControls.Base.pas:154 and :277) and is therefore inherited by TTyCustomGrid/TTyDrawGrid/TTyStringGrid. The claim's grep result ('hits only Chart.pas') is false  | SMALL |
| ~~推翻~~ | `IsCellVisible / IsFixedCellVisible` | 改名 | Boolean: is this cell currently within the visible area (and the fixed-area variant). | **推翻:** Visibility testing exists: `not IsRectEmpty(Grid.CellVisibleRect(ACol, ARow))` is the exact equivalent of IsCellVisible, and the pane clipping makes it cover IsFixedCellVisible as well. Only the predicate wrapper is abse | SMALL |
| ~~推翻~~ | `MouseCoord / MouseToCell / MouseToLogcell / MouseToGridZone / CellToGridZone` | 改名 | The whole family of point-to-cell and cell-to-zone conversions, including a two-out-parameter MouseToCell overload and the zone (gzNormal / gzFixedCols / gzFixedRows / gzFixedCells / gzInvalid) at a p | **推翻:** The family is covered: CellAt(X,Y) returns Part/Col/Row in one call (MouseCoord + MouseToCell + MouseToGridZone), CellPane(ACol,APos) gives the fixed/normal band (CellToGridZone), and DisplayToData/DataToDisplay give the | SMALL |
| ~~推翻~~ | `ColumnClickSorts` | 改名 | Grid-level boolean: clicking a column header sorts by it. | **推翻:** The equivalent is the hoHeaderClickAutoSort flag in Header.Options (Columns.pas:38, read at Grid.pas:6992); it is fully published and OI-settable through the published Header property, so it is neither missing nor undisc | SMALL |
| ~~推翻~~ | `OnHeaderSizing / OnHeaderSized: THeaderSizingEvent / THdrEvent` | 改名 | One event pair for BOTH axes (IsColumn, AIndex, ASize) covering during-drag and after-drag. | **推翻:** Both axes and both phases are covered by four published events, OnColumnSizing/OnEndColumnSize/OnRowSizing/OnEndRowSize (Grid.pas:1264-1267); only the axis-agnostic IsColumn-discriminated shape is absent. | SMALL |
| ~~推翻~~ | `AlternateColor: TColor / AltColorStartNormal` | 类型 | The actual colour of the banded rows, plus a flag saying whether banding counts from the first fixed row or the first normal row. | **推翻:** AlternateColor's role is filled by the TyGridCellAlt theme key plus RowColor/Colors/OnGetCellStyle overrides; AltColorStartNormal has no analogue because our zebra index counts display data rows only (Grid.pas:4272), so  | SMALL |
| ~~推翻~~ | `OnPrepareCanvas` | 改名 | Fires before each cell is drawn so the host can change Canvas.Brush / Font / TextStyle for that cell. | **推翻:** Conditional row/cell colouring is done with the published OnGetCellStyle (Grid.pas:1255, type at 518-521) plus OnGetCellBorder and OnGetHeaderStyle; a TCanvas-shaped hook cannot exist because the grid paints through TTyP | MEDIUM |
| ? | `Options2: TGridOptions2` | 属性 | Second flag set: goScrollToLastCol / goScrollToLastRow (allow the last col/row to become LeftCol/TopRow), goEditorParentColor, goEditorParentFont, goCopyWithoutTrailingLinebreak. | Cannot let the user scroll so the last row sits at the top of the viewport, and clipboard text always carries whatever trailing newline our exporter emits. | SMALL |
| ? | `VisibleColCount` | 属性 | How many columns currently fit in the viewport. | Horizontal paging and 'how much of the grid is the user actually seeing' cannot be answered. | SMALL |
| ? | `SelectedColumn: TGridColumn` | 属性 | Read-only shortcut to the column object under the cursor. | 'if Grid.SelectedColumn.ReadOnly then...' needs a manual index-and-cast, and the helper that would do it (GridColumn) is protected. | SMALL |
| ? | `ExtendedColSizing / ExtendedRowSizing` | 属性 | Let the user grab a column/row divider anywhere in the BODY, not only in the header/indicator strip. | On a grid with no header band (or no indicator) the user has nowhere to grab and can never resize a column or row. | SMALL |
| ? | `ImageIndexSortAsc / ImageIndexSortDesc` | 属性 | Take the ascending/descending sort glyph from TitleImageList by index instead of drawing the built-in triangle. | An app with its own icon set cannot make the grid's sort arrows match the rest of its chrome. | SMALL |
| ? | `MouseWheelOption: TMouseWheelOption` | 属性 | Whether the wheel moves the cell CURSOR (mwCursor) or scrolls the GRID (mwGrid). | LCL's DEFAULT is mwCursor, so a ported grid's wheel behaviour changes silently - and cursor-moving wheel cannot be had at all. | SMALL |
| ? | `DefaultDrawing` | 属性 | One switch that turns off the grid's own cell painting so OnDrawCell owns every cell. | A fully custom-painted grid must set AHandled in every callback instead of flipping one design-time flag - and it cannot be expressed in a .lfm. | SMALL |
| ? | `DefaultTextStyle: TTextStyle` | 属性 | The TTextStyle record (alignment, layout, single-line, word-break, clipping, opaque, show-prefix...) applied to every cell unless overridden. | 'centre every cell in this grid' requires wiring an event handler; there is no default alignment/layout setting at all. | SMALL |
| ? | `ColSizingCursor / RowSizingCursor / ColRowDraggingCursor / ColRowDragIndicatorColor` | 属性 | Which cursor to show while resizing a column (crHSplit), resizing a row (crVSplit) or dragging a col/row (crMultiDrag), and the colour of the drag insert indicator. | An app with a custom cursor set cannot make the grid's resize/drag cursors match, and the drag indicator colour is fixed. | SMALL |
| ? | `AllowOutboundEvents` | 属性 | When False, MouseToCell-style coordinate translation refuses to report cells for points outside the grid, so drag handlers do not get phantom cells. | Drag-out-of-grid gestures cannot be clamped, so a host has to bounds-check every hit itself. | SMALL |
| ? | `ColCount` | 属性 | Read/write column count; setting it grows or shrinks the grid without touching a Columns collection. | Grid.ColCount := 8 - the single most common line in TStringGrid code - does not compile; the host must loop Header.Columns.Add / Delete itself. | MEDIUM |
| ? | `LeftCol / TopRow` | 属性 | Read/write index of the first visible column / row - the scroll position expressed in CELLS, which is how grid code scrolls ('TopRow := 500'). | Saving and restoring a user's scroll position, or jumping the view to a row without moving the cursor, has no API - and reading the current first visible row is impossible from outside. | MEDIUM |
| ? | `Options: TGridOptions` | 属性 | One published set of ~32 behaviour flags the designer user flips in one place: goEditing, goRangeSelect, goRowSizing, goColSizing, goRowMoving, goColMoving, goTabs, goRowSelect, goAlwaysShowEditor, go | Any .lfm that sets Options=[...] cannot be ported at all; each flag must be hand-translated and about eight of them (goAutoAddRows, goAlwaysShowEditor, goTruncCellHints, goFixedColSizing, goDblClickAutoSize, goHeaderPush | LARGE |
| ? | `BiDiMode / ParentBiDiMode` | 属性 | Right-to-left layout: column order, text alignment and scrollbar side all mirror. | The control cannot be used in Arabic/Hebrew locales - the columns run the wrong way and there is no switch. | LARGE |

### `TTySpinEdit`  (对标 `TFloatSpinEdit/TCustomFloatSpinEdit`) — 17 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `GetLimitedValue / ValueToStr / StrToValue` | 方法 | Three public virtual seams: clamp a proposed value, format a value into the field's text, and parse the field's text back into a value. | A descendant cannot change the display or parse rules -- hex, thousands separators, a unit suffix like '12 px', or a snap-to-multiple clamp -- without reimplementing the control. LCL descendants routinely override exactl | SMALL |
| **成立** | `Modified` | 属性 | Read/write dirty flag: True once the user has edited the field, resettable by the host after a save. | A form cannot ask 'did the user touch this field?' to drive an enable-Save / prompt-on-close decision without shadowing the value itself. | SMALL |
| **成立** | `CaretPos` | 属性 | Read/write caret position in the editor. | A host cannot place the caret when it activates the field (e.g. 'put the cursor where the user clicked in the cell'), and cannot read it to drive its own hints. Note the type also differs from LCL's TPoint, so even once  | SMALL |
| **成立** | `TextHint` | 属性 | Placeholder text shown greyed in an empty field. | No placeholder on a spin edit. Combined with the missing ValueEmpty, an 'unset' numeric field cannot be communicated at all -- even though the theme token for the hint ink already exists. | SMALL |
| **成立** | `MaxValue default (0 vs 100)` | 默认值 | MaxValue's out-of-the-box value, which in LCL is 0 and -- because MaxValue<=MinValue means 'unbounded' -- makes a freshly dropped spin edit accept any integer. | A .lfm ported from Lazarus almost never stores MaxValue (it equals LCL's default), so it silently arrives here as 0..100 and any user entry above 100 is clamped without a diagnostic. The failure looks like a data bug in  | SMALL |
| **成立** | `SelectAll / ClearSelection / Clear` | 方法 | Select the whole text, drop the selection, or empty the field. | The universal 'focus the field and select-all so typing overwrites' pattern must be hand-rolled, and it cannot be -- there is no selection model to drive. Ctrl+A does nothing. | MEDIUM |
| **成立** | `CopyToClipboard / CutToClipboard / PasteFromClipboard` | 方法 | Clipboard operations on the editor's text/selection. | A user cannot paste a copied number into the field -- for a spin edit holding an ID or a measured value that is the single most common interaction after typing. Nothing about it can be worked around from outside the cont | MEDIUM |
| **成立** | `Undo / CanUndo` | 方法 | Undo the last edit in the field, and query whether an undo is available. | Ctrl+Z in the field does nothing and there is no programmatic undo, even though the library ships an undo stack the sibling edit already reuses. | MEDIUM |
| **成立** | `EditorEnabled` | 属性 | Makes the text portion non-typeable while the spin buttons keep working -- 'choose with the arrows, do not type'. | The 'arrows only, no keyboard' spin edit -- the standard way to force a value onto a legal grid (even numbers, multiples of 5) -- cannot be built: our ReadOnly kills the arrows too, so the control becomes inert instead o | MEDIUM |
| **成立** | `ValueEmpty` | 属性 | Lets the field show BLANK rather than a number -- the 'no value entered yet / mixed selection' state -- and reports whether it is currently blank. | There is no way to render 'not set': a filter form or a property inspector row must show 0, which is a legal value and therefore a lie. Clearing the text with Backspace snaps back to a number on the next commit. | MEDIUM |
| **成立** | `Text` | 属性 | Read/write access to the raw text currently in the editor, independent of the parsed numeric Value. | You cannot read what the user has typed before it commits, cannot preset the field to a non-canonical string, and cannot implement 'validate as they type'. Anything touching .Text on a ported TSpinEdit fails to compile. | MEDIUM |
| **成立** | `SelStart / SelLength / SelText` | 属性 | Programmatic read/write of the selection inside the editor. | No 'select the digits so the next keystroke replaces them', no programmatic replace-selection, and no way for a host (a grid inplace editor) to place the selection when it activates the cell. | MEDIUM |
| **成立** | `AutoSelect / AutoSelected` | 属性 | AutoSelect (default True) selects the whole text when the control receives focus; AutoSelected reports whether that auto-selection is still intact. | Tabbing into a spin edit leaves the caret in the middle of the existing number instead of selecting it, so the first keystroke appends digits to the old value rather than replacing it. This is LCL's default behaviour, so | MEDIUM |
| **成立** | `OnChange firing semantics` | 语义 | In LCL, OnChange is the EDIT's change notification: it fires on every text change (keystroke, paste, spin-button step), not only when a committed value differs. | A ported handler that recomputes something live as the user types goes quiet until the user presses Enter or tabs away, and the app looks frozen. Because both sides compile and both fire *sometimes*, the difference is on | MEDIUM |
| **成立** | `TFloatSpinEdit (Value: Double, DecimalPlaces, Increment: Double)` | 子对象 | The whole fractional variant of the spin edit: a Double Value, DecimalPlaces to control the displayed precision, a Double Increment, and a decimal-separator-aware input filter. | Any form using a TFloatSpinEdit (prices, percentages, scale factors, coordinates) has no counterpart at all -- the user must either lose the spin buttons by moving to TTyNumericEdit or bolt a TTyUpDown onto it by hand. | LARGE |
| ~~推翻~~ | `OnMouseWheelHorz / OnMouseWheelLeft / OnMouseWheelRight` | 事件 | Horizontal (tilt) wheel notifications on the spin edit. | **推翻:** All three are inherited-published on TTySpinEdit today: visible in the Object Inspector, streamed from .lfm, dispatched by TControl's own DoMouseWheelHorz. Ported handlers compile. TTySpinEdit correctly adds none of its  | SMALL |
| ? | `AutoSize` | 属性 | Sizes the edit's height to its font (LCL edits default AutoSize to True). | The same skin-variance trap this codebase already recorded: a theme with a larger font or bigger vertical padding clips the digits in a spin edit fixed at density-28, and there is no AutoSize to grow it. LCL's default is | SMALL |

### `TTyImage`  (对标 `TCustomImage/TImage`) — 20 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `OnPictureChanged` | 事件 | Fires whenever the assigned picture changes (assigned, edited in place, or cleared) so the host can re-caption, enable a Save button, update a status bar. | Hosts cannot react to a new image (dimensions label, dirty flag, thumbnail refresh) without polling or subclassing. | SMALL |
| **成立** | `OnPaint` | 事件 | Lets the host draw over the control after the image has been painted (TImage runs inherited Paint with the ancestor canvas specifically so OnPaint fires). | No way to annotate on top of the image (crop rectangle, hotspot markers, watermark) from the form's code. | SMALL |
| **成立** | `ImageIndex` | 属性 | Selects which entry of Images is shown (default 0); changing it repaints. | No way to say 'show icon 3 of the shared list'; a ported .lfm carrying ImageIndex= fails to stream. | SMALL |
| **成立** | `AntialiasingMode` | 属性 | Chooses the scaling/AA quality used when the picture is drawn scaled (amDontCare/amOn/amOff), i.e. smooth interpolation vs hard nearest-neighbour edges. | Pixel art / QR codes / sprite sheets scaled up come out blurred with no way to ask for crisp nearest-neighbour, and a ported .lfm with AntialiasingMode= will not stream. | SMALL |
| **成立** | `StretchInEnabled` | 属性 | Default True. Gate on ENLARGING: when False a picture smaller than the control is never scaled up, even with Stretch/Proportional set. | Small icons in a large placeholder get upscaled to mush with no opt-out; the standard LCL recipe 'shrink big photos, never enlarge small ones' is unexpressible. | SMALL |
| **成立** | `StretchOutEnabled` | 属性 | Default True. Gate on SHRINKING: when False a picture larger than the control is not scaled down (it clips instead). | Cannot ask for 'show at 1:1 and clip if too big' while still letting Stretch/Proportional handle the other direction; ported .lfm values silently vanish. | SMALL |
| **成立** | `Center` | 默认值 | Whether an unscaled picture is centred in the client area or placed at the top-left. | Silent layout change when porting: a .lfm converted from TImage does not store Center (it was the default False), so on TTyImage the image jumps to the middle of the control instead of the top-left, and pixel-exact layou | SMALL |
| **成立** | `Proportional` | 语义 | LCL's Proportional only engages when the picture is bigger than the control (PicOutsidePartial) unless Stretch is also set — a small picture stays at native size. It is a 'shrink to fit, never grow' s | Identical .lfm, different picture: a 32x32 logo in a 200x200 Proportional image stays 32x32 under LCL but is upscaled to 200x200 here — blurry logos appear after a port with nothing in the form file to blame. | SMALL |
| **成立** | `Paint (design-time placeholder frame)` | 语义 | At design time TCustomImage always outlines itself with a black dashed rectangle so an empty image control is visible and selectable on the form. | A freshly dropped or not-yet-assigned TTyImage is completely invisible in the Lazarus form designer — it cannot be found, clicked or resized without going through the Object Inspector's component list. | SMALL |
| **成立** | `Images` | 属性 | Lets the control display one entry from an image list instead of a TPicture; the list is the DPI-aware icon source, and AutoSize/DestRect fall back to the list's size when Picture is empty. | A single themed icon on a form cannot be sourced from the app's shared image list; the user must duplicate the bitmap into the control's Picture, losing the one-place-to-change icon set and the per-DPI rendering the coll | MEDIUM |
| **成立** | `Transparent` | 语义 | On LCL, Transparent is pushed into the GRAPHIC (Picture.Graphic.Transparent), i.e. it turns the bitmap's own mask/transparent colour on so the form shows through the image's background pixels; default | Same property name, opposite default and different subject: setting Transparent=False on a masked BMP under LCL makes the mask colour paint solid; here it paints the panel background instead and the bitmap's mask is neve | MEDIUM |
| **成立** | `Canvas` | 语义 | On TCustomImage, Canvas is REDIRECTED to the picture's own bitmap canvas (auto-creating a TBitmap the size of the control if Picture is empty), so 'Image1.Canvas.LineTo(...)' draws INTO the image and  | The very common LCL idiom 'use a TImage as a scratch drawing surface' compiles here and then silently loses every stroke at the next repaint, because the same property name now means the transient control canvas. | MEDIUM |
| ~~推翻~~ | `OnMouseWheelHorz / OnMouseWheelLeft / OnMouseWheelRight` | 事件 | Horizontal wheel / trackpad side-scroll notifications, separate from the vertical trio. | **推翻:** The horizontal wheel trio is published on both base classes (tyControls.Base.pas:147-149, :270-272), so it is present on TTyImage and on every TTy control, not missing library-wide. | SMALL |
| ~~推翻~~ | `DestRect` | 方法 | Public virtual function returning the rect (in client coords) the picture actually occupies right now — the basis for hit-testing a click back to an image pixel, drawing selection handles, or overridi | **推翻:** Use the public TyImageFitRect; a thin 'function DestRect: TRect' wrapper over it would be a two-line convenience, and making it virtual is the only real difference (a descendant currently changes placement by overriding  | SMALL |
| ~~推翻~~ | `OnDragDrop / OnDragOver / OnEndDrag / OnStartDrag` | 事件 | The four LCL drag-and-drop events that make a control a drop target and a drag source. | **推翻:** All four LCL drag events are published on both TTy base classes, hence on TTyImage. The only place a real problem remains is TTyTreeView, where its own TTyTreeDragOverEvent shadows the inherited OnDragOver (see claim 279 | MEDIUM |
| ~~推翻~~ | `DragMode / DragCursor` | 属性 | Published LCL drag-and-drop configuration: dmAutomatic starts a drag on mouse-down, DragCursor sets the cursor shown while dragging. | **推翻:** DragMode/DragKind/DragCursor are published library-wide on BOTH base classes (tyControls.Base.pas:138-140 and :261-263), so TTyImage has them. Nothing missing. | MEDIUM |
| ? | `OnPaintBackground` | 事件 | Called during Paint with the canvas and the computed destination rect, BEFORE the image is drawn, so the host can paint a checkerboard/matte/gradient behind a transparent PNG. | The standard 'alpha checkerboard behind a transparent image' pattern is impossible on this control; the user must drop a TTyPaintPanel behind it and keep the two rects in sync by hand. | SMALL |
| ? | `ImageWidth` | 属性 | Picks WHICH resolution of the image list to draw (a specific logical width, 0 = the list's default), so the same control can request 16px or 32px art. | Even once Images exists there is no way to ask for a specific icon size; the control cannot express 'draw the 24px variant here'. | SMALL |
| ? | `KeepOriginXWhenClipped / KeepOriginYWhenClipped` | 属性 | Two published Booleans (default False). When Center is on and the picture is BIGGER than the control, centring would push the origin negative and cut off the top/left; these pin the origin at 0 on tha | Showing the top-left corner of an oversized image (maps, screenshots, scans) is impossible: it is always centre-cropped. | SMALL |
| ? | `HasGraphic` | 属性 | Public read-only Boolean: True when there is anything to draw (a picture OR a valid image-list entry). Guards Paint and AutoSize. | Host code must reach into Image.Picture.Graphic and null/Empty-check it by hand to decide whether to show a placeholder. | SMALL |

### `TTyShellTreeView`  (对标 `TCustomShellTreeView/TShellTreeView`) — 17 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `OnSortCompare: TFileItemCompareEvent` | 事件 | User comparator over two TFileItem entries; assigning it switches FileSortType to fstCustom and re-sorts the tree. | Custom ordering of a directory's children (by extension, by date, natural-numeric) cannot be expressed on the raw file records. | SMALL |
| **成立** | `OnAddItem: TAddItemEvent` | 事件 | Per-entry veto hook fired while a node is being populated: (ABasePath, AFileInfo, var CanAdd) lets the app filter out individual folders. | No way to hide specific folders (.git, system junctions, symlink loops) from the tree; the only filter is the coarse hidden-attribute flag. | SMALL |
| **成立** | `Refresh(ANode: TTreeNode)` | 方法 | Re-reads one node's children (nil = the root), leaving the rest of the tree alone. | After the app itself creates or deletes a folder, it cannot refresh just the affected branch; the branch keeps showing stale children forever (see the ExpandCollapseMode entry). | SMALL |
| **成立** | `GetPathFromNode(ANode: TTreeNode): string` | 方法 | Public node -> absolute path mapping, used by every consumer that walks or hit-tests the tree itself. | An app cannot resolve the path of any node other than the focused one -- no multi-select harvesting, no path lookup from an OnGetImageIndex/OnDrawNode handler, no drag-source path -- without subclassing the control. | SMALL |
| **成立** | `FileSortType: TFileSortType` | 属性 | How enumerated children are ordered: fstNone, fstAlphabet, fstFoldersFirst, fstCustom (defers to OnSortCompare). | Directory children appear in raw filesystem order (on NTFS roughly alphabetical, on ext4 effectively random), and there is no property to ask for alphabetical or folders-first. A capability that already exists in the Fil | SMALL |
| **成立** | `Path` | 改名 | Read/write the selected node's full path. Reading appends a trailing path delimiter for directories and prefixes GetRootPath for relative nodes; writing accepts absolute OR root-relative paths. | Porting break: `ShellTreeView1.Path := X` does not compile. Also a value difference -- ours returns the raw FullPath with no trailing delimiter and accepts absolute paths only (SelectPath, line 372-387), so root-relative | SMALL |
| **成立** | `GetBasePath / GetRootPath / GetFilesInDir` | 改名 | Class/instance helpers exposing the platform base path, the effective root path, and a static directory enumerator that other classes reuse. | Porting break only: code that calls TShellTreeView.GetFilesInDir(...) must be rewritten against tyControls.FileSystem. The functionality is present. | SMALL |
| **成立** | `EInvalidPath / EShellCtrl (invalid Root or Path)` | 语义 | Assigning a Root or Path that does not exist (or selecting a node whose file has been deleted) raises a typed exception the app can catch and report. | A dialog that restores a saved last-used folder cannot tell whether the restore worked: the tree just focuses the nearest surviving ancestor (or nothing) with no error, so the app shows a stale path in its edit box. | SMALL |
| **成立** | `ShowHidden write semantics (vs SetObjectTypes)` | 语义 | On the LCL side, changing which object types are enumerated immediately refreshes the visible tree (BeginUpdate/UpdateView/EndUpdate). | A 'Show hidden files' checkbox wired straight to ShowHidden appears broken: nothing changes until the user collapses and re-expands, and the only immediate refresh available (PopulateRoots) throws away the whole tree sta | SMALL |
| **成立** | `UpdateView(AStartDir: String = '')` | 方法 | Re-reads every currently expanded node from AStartDir down (or from the root), reacting to filesystem changes while preserving the expansion state and selection. | There is no way to say 'the disk changed, refresh what is on screen'. The only refresh collapses the entire tree back to the drive list, which loses the user's place. | MEDIUM |
| **成立** | `Root` | 属性 | Roots the whole tree at one directory ('' = machine base path). Setting it clears and repopulates the tree, and propagates to the linked ShellListView.Root. | You cannot show a tree scoped to one folder (a project folder, a document root). Every TTyShellTreeView always shows all drives/places, so a chooser confined to one subtree is impossible without subclassing. | MEDIUM |
| **成立** | `ExpandCollapseMode: TExpandCollapseMode` | 属性 | Chooses whether expanding a node re-reads its children from disk (ecmRefreshedExpanding, the LCL default), keeps already-built children (ecmKeepChildren), or discards children on collapse (ecmCollapse | Children are enumerated exactly once per node for the control's lifetime, so files/folders created or deleted after the first expand never appear; and because ours differs from the LCL DEFAULT, a port silently loses the  | MEDIUM |
| **成立** | `OnChange / OnExpanding / OnGetImageIndex / OnInitNode / OnGetText` | 语义 | On TShellTreeView all of these stay free for the application -- the shell behaviour lives in overridden virtuals (CanExpand, DoSelectionChanged, DrawBuiltInIcon, NodeHasChildren), so OnChange/OnExpand | Assigning OnChange in the Object Inspector silently kills path caching and OnPathChange; assigning OnExpanding kills lazy population (the tree stops expanding); assigning OnGetText makes every node blank. The failure loo | MEDIUM |
| ~~推翻~~ | `TShellTreeNode (per-node object: ShortFilename / FullFilename / IsDirectory / BasePath / FileInfo)` | 子对象 | A dedicated node class that carries each node's TSearchRec plus its base path, so per-node attributes (size, timestamp, attributes, is-directory) are available without touching the disk again. | **推翻:** Our node data is an Integer index into FPaths (constructor line 109, NodePath line 242). From that: FullFilename = NodePath(Node); ShortFilename = ExtractFileName(ExcludeTrailingPathDelimiter(NodePath(Node))), which is e | MEDIUM |
| ? | `UseBuiltinIcons` | 属性 | Switches the control's own drawn folder/drive glyphs off so an assigned Images list (or no icons at all) is used instead. Default True. | A text-only or app-iconography tree needs Images := nil after construction, and the two BGRA masters are rendered on every instance regardless. The themed equivalent is missing too -- there is no token to suppress the co | SMALL |
| ? | `ObjectTypes: TObjectTypes` | 属性 | Which entries the tree enumerates: otFolders, otNonFolders (files shown as leaf nodes), otHidden. Default [otFolders]; assigning re-reads the view. | A tree that shows files as well as folders (the classic Explorer left pane with otNonFolders) is impossible, and the hidden-files toggle is a different, narrower property name than every ported TShellTreeView code path e | MEDIUM |
| ? | `ShellListView` | 属性 | Design-time two-way link to a shell list view: selecting a folder in the tree sets the list's Root, and the list's UpdateView refreshes the tree. | The canonical two-control file browser cannot be assembled in the Object Inspector; every app must hand-write the OnPathChange -> Directory plumbing, and there is no reverse (list -> tree) refresh at all. | MEDIUM |

### `TTyPanel`  (对标 `TCustomPanel/TPanel`) — 16 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `OnPaint` | 事件 | Owner-draw hook fired from Paint with the control's Canvas ready, so a host can draw on top of (or instead of) the panel's own rendering. | Assigning OnPaint on a TTyPanel (or any TTyPanel descendant — ScrollBox, GridPanel, RelativePanel) silently does nothing: no compile error, no runtime error, no drawing. Only TTyPaintPanel offers a (different) surface ho | SMALL |
| **成立** | `WordWrap` | 属性 | Wraps a long panel caption over several lines instead of keeping it on one line (TS.Wordbreak / TS.SingleLine). | A panel used as a caption/banner cannot show a two-line title — the text is silently ellipsised. Capability built (painter + labels), never wired to the panel. | SMALL |
| **成立** | `VerticalAlignment` | 属性 | Positions the caption at the top, centre or bottom of the panel (taAlignTop/taAlignBottom/taVerticalCenter, default taVerticalCenter). | A caption cannot be pinned to the top or bottom of a panel — e.g. a section header band with the label at the top and children below is not expressible without abandoning the panel's own Caption. | SMALL |
| **成立** | `ShowAccelChar` | 属性 | Interprets '&' in the caption as a mnemonic marker: the '&' is removed and the next character is underlined (TTextStyle.ShowPrefix). | A panel Caption of 'File &Options' paints the ampersand literally, and there is no Alt-key underline on containers/group captions — inconsistent with every other ty control that already does mnemonics. | SMALL |
| **成立** | `AccessibleRole / AccessibleDescription (default value)` | 默认值 | The accessibility identity a screen reader announces. LCL gives each concrete control a sensible default in its constructor: larGroup + a localized description for a panel, larResizeGrip for a splitte | Screen readers announce every ty container and splitter as an unidentified control rather than a group / resize grip, so keyboard-and-screen-reader users lose the structural landmarks a stock LCL form gives them for free | SMALL |
| **成立** | `Caption` | 语义 | On LCL the panel caption IS TControl.Caption/Text: it is routed through GetText/SetText, csSetCaption is set, and RealSetText is overridden to Invalidate, so anything that writes the control's text (a | Two concrete breakages: (1) `TControl(Panel).Caption := 'x'` or `Panel.Text := 'x'` sets the LCL text and paints nothing; (2) the base class publishes Action (tyControls.Base.pas:231) and TControl.ActionChange assigns `C | SMALL |
| **成立** | `ChildSizing (TControlChildSizing sub-object)` | 子对象 | A whole child-layout sub-object on every TWinControl container: Layout (cclNone/cclLeftToRightThenTopToBottom/...), ControlsPerLine, EnlargeHorizontal/EnlargeVertical, ShrinkHorizontal/ShrinkVertical, | A ported .lfm that used Panel1.ChildSizing (a very common way to lay out a row of buttons or a form-field column in Lazarus) does not load/compile, and there is no substitute: the user must hand-place or hand-anchor ever | LARGE |
| ~~推翻~~ | `OnDragOver / OnDragDrop / OnStartDrag / OnEndDrag` | 事件 | The four events that make a control a drag SOURCE and a drop TARGET: accept/reject feedback while a payload hovers, handle the drop, and start/finish notifications. | **推翻:** OnDragOver, OnDragDrop, OnStartDrag and OnEndDrag are republished on both base classes — tyControls.Base.pas:141-144 and :264-267. Every TTy control including TTyPanel is already a designer-configurable drag source and d | SMALL |
| ~~推翻~~ | `DragMode / DragCursor / DragKind` | 属性 | LCL drag-and-drop configuration: dmAutomatic starts a drag on mouse-down without any code, DragCursor is the cursor shown while dragging, DragKind selects drag vs dock. | **推翻:** DragMode, DragKind and DragCursor are republished on BOTH shared base classes: tyControls.Base.pas:138-140 (TTyGraphicControl) and :261-263 (TTyCustomControl), with a comment describing that very fix. TTyPanel descends f | SMALL |
| ~~推翻~~ | `BevelOuter / BevelWidth / BevelColor` | 改名 | Per-instance 3D framing of the panel: raised/lowered/space/none, its thickness, and an explicit bevel colour (clDefault = derive from the system face). | **推翻:** TTyPanel inherits published StyleOverride from TTyCustomControl (Base.pas:296); override text runs the same declaration parser as a theme (TTyStyleModel.ResolveOverride -> TyApplyDeclaration, StyleModel.pas:1572-1597), a | SMALL |
| ? | `ClientWidth / ClientHeight` | 属性 | Published, designer/stream-settable CLIENT size: setting it sizes the control so its client area is exactly that big (frame/bevel/scrollbar excluded), and it is what a .lfm records for containers. | A .lfm that stores ClientWidth/ClientHeight for a panel or scroll box (what the Lazarus designer writes when the frame is non-zero) will not stream onto a ty container, and the user cannot dimension a container by its us | SMALL |
| ? | `AutoSize` | 属性 | Makes the panel shrink/grow to fit its content (its caption and/or its children); TCustomPanel additionally opts into csAutoSize0x0 so an empty panel can collapse. | A self-sizing panel (toolbar strip, caption band, wrapper that hugs its child) is not expressible; the user must compute and set Height/Width by hand and re-do it on every theme/DPI/skin change — exactly the case the cod | MEDIUM |
| ? | `BevelInner` | 属性 | A SECOND, inner 3D frame drawn inside BorderWidth, independently raised or lowered from the outer one — the classic double-bevel panel look. | The Win9x/classic double-bevel panel (raised outer + lowered inner) cannot be reproduced, even via the theme — the render-style token expands to a single bevel only. Blocks faithful classic-era skins for panels. | MEDIUM |
| ? | `BorderWidth` | 属性 | Per-instance inner margin between the container's edge (or bevel) and its child controls — subtracted in AdjustClientRect so aligned children keep clear of the frame. | Children of a TTyPanel sit flush against the frame; the only way to inset them is the theme's container padding (which moves every panel in the app) or manual per-child BorderSpacing. A single 'this panel has an 8px inne | MEDIUM |
| ? | `BiDiMode / ParentBiDiMode` | 属性 | Right-to-left support: BiDiMode flips the caption alignment (BidiFlipAlignment) and sets TS.RightToLeft when drawing, and ParentBiDiMode inherits the mode from the parent. | No Arabic/Hebrew layout on any container in the library: captions stay left/centre-aligned in the LTR sense and a ported RTL form loses its mirroring. Affects every TTyPanel descendant. | LARGE |
| ? | `DockSite / UseDockManager / OnDockDrop / OnDockOver / OnUnDock / OnStartDock / OnEndDock / OnGetSiteInfo / OnG` | 属性 | The docking surface: a panel can be declared a dock site, given a dock manager, and notified when a client docks/undocks; OnGetSiteInfo negotiates the drop and GetDefaultDockCaption/OnGetDockCaption s | Dockable-pane IDE-style layouts (the most common reason a TPanel is used as a container in Lazarus/Delphi apps) cannot be built on ty containers at all; a ported form silently loses every dock relationship. | LARGE |

### `TTyCalendar`  (对标 `TCustomCalendar`) — 16 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `OnDayChanged` | 事件 | Fires only when the day-of-month component of the selection changed. | Handlers that need to react to day-only movement must re-derive the old day themselves in OnChange (we do not pass the previous value), and a ported form's OnDayChanged= assignment fails to load. | SMALL |
| **成立** | `OnYearChanged` | 事件 | Fires when the year component of the selection changed. | No hook for year rollover; ported forms lose the handler assignment. | SMALL |
| **成立** | `FirstDayOfWeek (dowDefault / locale)` | 默认值 | LCL's default dowDefault defers to the widgetset/locale, so the calendar starts on Monday in de/fr/zh locales and Sunday in en-US. | Out of the box in every Monday-first locale (most of Europe/Asia) our calendar shows a US week layout, and there is no value the user can set that means "follow the system" -- they must hardcode wdMonday and it then stay | SMALL |
| **成立** | `DisplaySettings.dsShowWeekNumbers -> WeekNumbers` | 改名 | Shows the ISO week-number column at the left of the day grid. | Same feature, incompatible spelling and shape: `Cal.DisplaySettings := Cal.DisplaySettings + [dsShowWeekNumbers]` must be rewritten as `Cal.WeekNumbers := True` when porting a form. | SMALL |
| **成立** | `GetCalendarView / TCalendarView -> ViewMode / TTyCalView` | 改名 | Reports which drill-down level the calendar is currently showing (month / year / decade / century). | Same concept, different name AND different enum identifiers (cvMonth vs cvmDays, and ours names the CELL granularity while theirs names the PAGE granularity), so `if Cal.GetCalendarView = cvMonth` must be rewritten as `i | SMALL |
| **成立** | `EInvalidDate / CheckRange (out-of-range assignment)` | 语义 | Assigning a date outside MinDate..MaxDate (or outside SysUtils.MinDateTime..MaxDateTime) RAISES EInvalidDate with a formatted message. | Opposite failure modes for the same statement: validation code built around `try Cal.DateTime := X except on EInvalidDate ...` never fires here and the bad value is quietly coerced instead, so an out-of-range date from a | SMALL |
| **成立** | `Date` | 类型 | LCL's Date is a STRING (parsed with StrToDate, raises on bad input); the TDateTime accessor there is called DateTime. | Ported code that does `Cal.Date := DateToStr(D)` or `S := Cal.Date` fails to compile here; conversely code written here does not compile there. Same identifier, different static type -- the worst-shaped porting break, an | SMALL |
| **成立** | `FirstDayOfWeek` | 类型 | Which weekday occupies grid column 0. | `Cal.FirstDayOfWeek := dowMonday` does not compile; worse, an .lfm/RTTI value that survives (integer 0) means Monday there and Sunday here, so a ported form silently shifts the whole grid by one column. | SMALL |
| **成立** | `OnMonthChanged` | 事件 | Fires when the month component of the selection changed (e.g. arrow-navigating across a month boundary). | The common "load this month's appointments when the user pages the calendar" wiring has no hook: paging with our header arrows raises no event whatsoever. | MEDIUM |
| **成立** | `HitTest(APoint): TCalendarPart` | 方法 | Classifies a point into cpNoWhere/cpDate/cpWeekNumber/cpTitle/cpTitleBtn/cpTitleMonth/cpTitleYear -- the public way to ask what part of the calendar the mouse is over. | A host that wants a context menu or custom tooltip per calendar region ("you right-clicked the year in the title") has to reimplement our private layout maths, and it cannot -- CalcLayout is private. | MEDIUM |
| **成立** | `DisplaySettings` | 属性 | A set property (TDisplaySettings) with dsShowHeadings, dsShowDayNames, dsNoMonthChange, dsShowWeekNumbers, controlling which calendar chrome is drawn; default [dsShowHeadings, dsShowDayNames]. | A .lfm streamed from Lazarus containing `DisplaySettings = [dsShowHeadings, dsShowDayNames]` fails to load, and no single property exists to configure calendar chrome. Also blocks the three flags listed separately below. | MEDIUM |
| **成立** | `DisplaySettings.dsShowHeadings` | 属性 | When excluded, the month/year title band (and its navigation buttons) is not drawn at all -- a bare day grid. | A user embedding the calendar in a panel that already shows the month elsewhere cannot suppress our header; ~28-40px of the control is permanently spent on chrome they do not want. | MEDIUM |
| **成立** | `DisplaySettings.dsShowDayNames` | 属性 | When excluded, the Su/Mo/Tu weekday-name row is not drawn. | No way to build a compact date grid; the weekday row always consumes a row of height even at tiny control sizes. | MEDIUM |
| **成立** | `DisplaySettings.dsNoMonthChange` | 属性 | When included, clicking a spill-over day from the previous/next month does not scroll the view to that month. | Two divergences at once: LCL users who relied on clicking a grey day to jump to that month find the click silently ignored here, and users who want LCL's dsNoMonthChange discipline have no property to set. | MEDIUM |
| ~~推翻~~ | `OnMouseWheelHorz / OnMouseWheelLeft / OnMouseWheelRight` | 事件 | Horizontal-wheel (tilt-wheel / trackpad two-finger sideways) notification events. | **推翻:** TTyCalendar already has all three events, published via TTyCustomControl (tyControls.Base.pas:272-274). A ported form assigning OnMouseWheelHorz loads fine. | SMALL |
| ? | `AutoSize` | 属性 | Published AutoSize; the control reports a preferred size and shrink-wraps to it. | AutoSize=True on a .lfm ported from Lazarus does not stream (unknown property) and, if set in code, our control has no preferred size to grow to -- the skin-variance failure mode this codebase already logged: a roomier s | MEDIUM |

### `TTyListBox`  (对标 `TCustomListBox/TListBox`) — 18 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `OnSelectionChange(Sender; User: Boolean) — ours is OnChange(Sender) (plus LockSelectionChange/UnlockSelectionC` | 改名 | Selection-changed notification carrying whether the change came from the USER or from code, with a lock pair so bulk programmatic updates fire it once (or not at all). | Ported handlers do not compile under the LCL name, and a handler that must ignore programmatic selection (to avoid feedback loops when code sets ItemIndex) has no User flag to test and no lock to hold. | SMALL |
| **成立** | `Items: TStrings (ours: TStringList)` | 类型 | The item collection. LCL types it as the abstract TStrings so any TStrings descendant can be assigned or passed. | `LB.Items := AnyTStrings` and `procedure P(L: TStrings)` call sites that compile against TListBox fail to compile here; hosts must copy through a temporary TStringList. | SMALL |
| **成立** | `OnDrawItem: TDrawItemEvent` | 事件 | Per-row custom paint callback giving the host the Canvas, the row rect and the TOwnerDrawState (selected/focused/disabled/background-painted). | Any per-row decoration a user wants (icons, two-line rows, progress bars in rows) requires subclassing our unit instead of assigning one event handler. | MEDIUM |
| **成立** | `OnMeasureItem: TMeasureItemEvent (+ protected MeasureItem)` | 事件 | Asks the host for the height of an individual row, so rows may differ in height (lbOwnerDrawVariable). | Variable-height rows are impossible; a list mixing one-line and two-line entries cannot be built even by subclassing, because the row loop assumes a uniform height. | MEDIUM |
| **成立** | `Columns: Integer` | 属性 | Newspaper-style multi-column layout: the list wraps into N columns and scrolls horizontally instead of vertically. | A short-item picker that should show 3 columns in a wide box can only be shown as one tall scrolling column. | MEDIUM |
| **成立** | `ExtendedSelect: Boolean` | 属性 | With MultiSelect on, chooses between extended selection (plain click replaces, Ctrl toggles, Shift ranges) and simple multi-select (every plain click toggles that row, no modifier needed). | Touch/kiosk style pick-many lists, where each tap toggles a row without holding Ctrl, cannot be built. | MEDIUM |
| **成立** | `ScrollWidth: Integer (and horizontal scrolling generally)` | 属性 | Sets the horizontal scroll extent so items wider than the client area can be scrolled into view. | Long item text is simply cut off at the right edge with no way to read the rest — a file-path or SQL list is unusable. | LARGE |
| ~~推翻~~ | `OnShowHint; OnMouseWheelHorz; OnMouseWheelLeft; OnMouseWheelRight` | 事件 | Hint-about-to-show customisation (per-row tooltips) and horizontal mouse-wheel / tilt-wheel notifications. | **推翻:** Present via ancestor. Per-row tooltips are buildable today: OnShowHint (inherited) plus the public GetIndexAtY/ItemRect on TTyListBox. | SMALL |
| ~~推翻~~ | `Clear; AddItem(const Item: String; AnObject: TObject); DeleteSelected; SelectRange(ALow, AHigh, ASelected); Ge` | 方法 | The control-level list-manipulation surface: empty the list (also resetting ItemIndex), append text+object, delete every selected row, select/deselect a range programmatically, and read all selected i | **推翻:** Already implemented (recent commit 'the drag surface, and the list methods ported code expects'). Only divergence: DeleteSelected is a function returning the removed count rather than a procedure -- still callable as a s | SMALL |
| ~~推翻~~ | `ItemAtPos(Pos, Existing); GetIndexAtXY(X, Y); GetIndexAtY(Y); ItemRect(Index): TRect; ItemVisible(Index); Item` | 方法 | The public hit-test / row-geometry / scroll-into-view surface: which row is under a point, where a row is on screen, whether it is (fully) visible, and scroll the current row into view. | **推翻:** Genuinely absent are only the thin wrappers ItemAtPos, GetIndexAtXY, ItemVisible, ItemFullyVisible, MakeCurrentVisible -- each a one-liner over the existing ItemRect/GetIndexAtY/VisibleRows/TopIndex. The claim's 'grep re | SMALL |
| ~~推翻~~ | `DragCursor / DragKind / DragMode + OnDragDrop / OnDragOver / OnEndDrag / OnStartDrag` | 属性 | LCL drag-and-drop: automatic drag start, drop targeting, and the four notification events. | **推翻:** Already wired via the base class (commit 'the drag surface...'). The claim's grep looked only at TTyMemo and missed tyControls.Base.pas. | SMALL |
| ~~推翻~~ | `BorderStyle: TBorderStyle (default bsSingle)` | 改名 | Turns the control's frame on or off (bsNone / bsSingle). | **推翻:** BorderStyle is absent library-wide, deliberately: a borderless list is expressed as a theme/StyleClass override (border-width:0), not a per-control bsNone toggle. If this is worth doing it is a library-wide chrome-token  | SMALL |
| ~~推翻~~ | `ItemHeight = 0 meaning 'measure from Font' (protected CalculateStandardItemHeight)` | 语义 | In LCL, an unset (0) ItemHeight makes each row as tall as the control's Font needs, recomputed when the font changes; writing 0 again returns the list to that automatic mode. | **推翻:** The one real residual defect is narrower: SetItemHeight sets FItemHeightExplicit := True unconditionally and clamps to >=1, so `ItemHeight := 0` yields 1px rows instead of returning to the automatic (--item-height) mode  | MEDIUM |
| ? | `ClickOnSelChange: Boolean` | 属性 | When true (the Delphi default), a selection change — including a keyboard-driven one — also fires OnClick; the flag lets a host turn that coupling off. | Delphi/LCL code that hangs its logic on OnClick and relies on arrow-key selection firing it silently stops working after a port. | SMALL |
| ? | `Count: Integer; IntegralHeight: Boolean` | 属性 | Count is the Delphi-compatibility alias for Items.Count on the control itself; IntegralHeight makes the box show only whole rows (no clipped last row). | `if LB.Count = 0` — a very common idiom — does not compile; IntegralHeight is a straight porting break (though a no-op in LCL too, so behaviour parity is already there for it). | SMALL |
| ? | `Style: TListBoxStyle (lbStandard / lbOwnerDrawFixed / lbOwnerDrawVariable / lbVirtual)` | 属性 | Selects the drawing/data model of the list: standard text rows, owner-drawn fixed-height rows, owner-drawn variable-height rows, or a virtual list whose rows are supplied on demand. | A host cannot switch our list box into owner-draw mode at all, and there is no virtual mode, so a list of 100k rows must be materialised as 100k TStringList entries. | MEDIUM |
| ? | `Options: TListBoxOptions (lboDrawFocusRect)` | 属性 | Controls whether a focus rectangle is drawn on the FOCUSED row, which in a multi-select list is distinct from the selected rows. | In a multi-select list the user cannot see where the keyboard cursor is, so Shift+arrow extension is blind guessing. | MEDIUM |
| ? | `BidiMode / ParentBidiMode` | 属性 | Right-to-left layout: mirrors item alignment, the scrollbar side, and (on TCheckListBox) the check column. | Arabic/Hebrew UIs get a mirrored form with a stubbornly left-aligned, left-scrollbar list — the library cannot ship into RTL locales. | LARGE |

### `TTySplitter`  (对标 `TCustomSplitter/TSplitter`) — 14 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Cursor when disabled` | 语义 | LCL re-derives the splitter cursor from Enabled: a disabled splitter shows crDefault (and its band paints in the trBandDisabled state), and CM_ENABLEDCHANGED re-runs the derivation when Enabled flips. | A disabled splitter still shows the resize cursor, inviting a drag that does nothing — the exact 'looks interactive, is inert' problem the recent fixes in this branch were about. | SMALL |
| **成立** | `ResizeStyle (rsLine / rsPattern / rsNone)` | 语义 | Three of the four styles defer the resize until mouse-up and give live feedback in the meantime: rsLine draws a solid rubber-band line, rsPattern a themed dotted band; rsNone shows nothing. Only rsUpd | Two published enum values are accepted and then behave wrongly: rsPattern and rsNone drag with no feedback and leave the pane at its original size, so the drag looks broken. rsLine resizes but shows nothing, so the user  | MEDIUM |
| **成立** | `ResizeAnchor` | 属性 | Selects which side the splitter resizes (akLeft/akTop/akRight/akBottom) INDEPENDENTLY of Align — the documented second mode where Align=alNone plus AnchorSides plus ResizeAnchor drives an anchored lay | Only the four Align-docked splitter arrangements work. An anchored splitter — the flexible mode LCL documents for anchor-based layouts, and the only way to split two anchored panes without Align — is silently inert: it p | LARGE |
| ~~推翻~~ | `MoveSplitter(Offset)` | 方法 | Public, virtual: move the splitter by Offset pixels and resize the affected pane(s) exactly as a drag would — the one entry point through which every programmatic and interactive move runs. | **推翻:** Programmatic/scripted/animated pane moves are reachable today via the pane's Width/Height plus the public TySplitterNewSize helper. The real residue is narrower and non-user-facing: ApplySize is private and non-virtual,  | SMALL |
| ~~推翻~~ | `SetSplitterPosition / GetSplitterPosition` | 方法 | Read and set the splitter's absolute position along its axis (Left for a vertical bar, Top for a horizontal one) — the natural way to persist and restore a layout. | **推翻:** Save/restore of user pane sizes works today by persisting the resized control's Width/Height (with TySplitterNewSize available to re-clamp). This claim also duplicates 459 — same capability, different spelling. | SMALL |
| ~~推翻~~ | `GetOtherResizeControl` | 方法 | Returns the control on the OTHER side of the splitter, so a host (and MoveSplitter itself) can reason about both panes — e.g. clamp against the far pane's minimum size. | **推翻:** The user-visible issue is that TTySplitter.ApplySize clamps only against Parent.ClientWidth/Height and ignores the opposite control's Constraints — that belongs to the Constraints claim. Exposing a GetOtherResizeControl- | SMALL |
| ~~推翻~~ | `Constraints of the resized control (honoured during a drag)` | 语义 | LCL's MoveSplitter clamps the new size to the resized control's own Constraints.EffectiveMinWidth/MaxWidth (or Min/MaxHeight) as well as to MinSize, so a pane declaring MinWidth=200 cannot be dragged  | **推翻:** A pane cannot be dragged below its Constraints.MinWidth here either: ApplySize assigns FTarget.Width/Height and TControl.ChangeBounds calls DoConstrainedResize (lcl/include/control.inc:695, :1460-1514), which clamps to C | SMALL |
| ~~推翻~~ | `OnMoved (firing condition)` | 语义 | LCL fires OnMoved once at the end of every splitter drag, unconditionally, as the 'the user finished moving me' notification. | **推翻:** The only drags our version swallows are those that left the target at exactly its starting size (vetoed by OnCanResize, clamped, or dragged out and back). In those states a layout-persisting or re-layout handler has noth | SMALL |
| ~~推翻~~ | `OnCanResize (event type)` | 类型 | Same signature, different declared type: LCL uses the shared TCanResizeEvent so a handler can be reused across splitters/controls. | **推翻:** A handler METHOD with that signature — what the IDE generates and what a ported form declares — assigns to either property with no cast, since FPC checks method-to-procedural-type compatibility structurally. Only a varia | SMALL |
| ~~推翻~~ | `AnchorSplitter(Kind, AControl)` | 方法 | Wires the splitter and a control together in one call: it anchors the control's side to the splitter and the splitter's opposite sides to the control's neighbours, building an anchor-based split witho | **推翻:** TTySplitter is an Align-based splitter by design (FindResizeTarget requires Align in alLeft..alBottom). The anchored split mode as a whole is the open question (ResizeAnchor), not the sugar on top of it; the Align route  | MEDIUM |
| ? | `OnCanOffset` | 事件 | Veto/adjust hook on the splitter OFFSET (var NewOffset, var Accept) — complements OnCanResize by letting the host constrain the movement itself (snapping to a grid, refusing a direction) rather than t | Snap-to-grid or direction-limited dragging cannot be implemented: by the time OnCanResize fires the offset has already been converted to a size, and the handler cannot see or alter the movement itself. | SMALL |
| ? | `OnPaint` | 事件 | On TCustomSplitter, OnPaint does more than add drawing: assigning it SUPPRESSES the built-in themed band/gripper, so it is the documented way to give a splitter a custom look. | A custom splitter appearance (a thin hairline, a branded handle, a hover chevron) can only be done by editing the theme for every splitter in the app or by subclassing; the per-instance escape hatch LCL provides has no c | SMALL |
| ? | `ResizeControl` | 属性 | Public read/write property naming the control this splitter resizes: reading it resolves the current target, writing it repositions/re-anchors the splitter to that control. | Code cannot ask which pane a splitter drives, nor point it at a specific control — so no 'reset the sidebar to 200 px' or 'move the splitter next to this pane' logic, and no way to disambiguate when several siblings touc | SMALL |
| ? | `Beveled` | 属性 | Draws a raised outer edge around the splitter bar (BDR_RAISEDOUTER) so it reads as a physical divider — the classic Delphi splitter look. | A ported .lfm with Beveled = True does not stream, and there is no per-instance way to give one splitter a raised edge (the theme's border tokens would change every splitter in the app). | SMALL |

### `TTyValueListEditor`  (对标 `TValueListEditor`) — 13 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `InsertRow(const KeyName, Value: string; Append: Boolean): Integer` | 类型 | Insert or append a row and RETURN its index; Append=False inserts at the current row. | Same name, incompatible signature: ported calls fail, and inserting a row at a chosen position (rather than at the end) is not possible at all. | SMALL |
| **成立** | `RowCount (published, read/write)` | 类型 | Published read/write row count: settable to grow or trim the list, and streamable. | 'VLE.RowCount := 10' does not compile, and RowCount cannot be read as a property (e.g. by RTTI or a binding layer). | SMALL |
| **成立** | `DisplayOptions: TDisplayOptions / TitleCaptions: TStrings / TitleFont` | 属性 | doColumnTitles shows a header row over the two columns, TitleCaptions supplies its two captions (localisable), doAutoColResize keeps the value column filling the width, doKeyColFixed freezes the key c | LCL's DEFAULT includes doColumnTitles, so every ported value-list editor loses its 'Key \| Value' header, and there is no way to label the two columns. | MEDIUM |
| **成立** | `Values[const Key: string]: string` | 语义 | THEIRS: Values is indexed BY KEY - 'VLE.Values[''Name''] := ''Bob''' - the single most used member of the class. OURS: the identifier Values exists but is indexed by INTEGER row number, and the key-in | The worst collision in this pairing: our Values takes exactly the parameter theirs does NOT. 'Values[''Name'']' fails to compile, and any numeric-looking key expression could compile against the wrong accessor and addres | MEDIUM |
| **成立** | `KeyOptions: TKeyOptions` | 属性 | What the USER may do to the row set at run time: keyEdit (rename a key), keyAdd (Insert adds a row), keyDelete (Ctrl+Delete removes one), keyUnique (reject duplicate keys). | A user-editable name/value list (the classic ini or environment-variable editor) is impossible: the user can change values but never add, remove or rename an entry. | LARGE |
| ~~推翻~~ | `IsEmptyRow / IsEmptyRow(aRow) / RestoreCurrentRow` | 方法 | Ask whether the current (or a given) row is blank, and undo the in-progress edit of the current row, restoring both its key and value. | **推翻:** IsEmptyRow and RestoreCurrentRow are absent as named members, but both stated impacts are already covered: Escape during an inline edit reverts the value (EditorKeyDown, :1182-1188), and blank-row commits cannot arise be | SMALL |
| ~~推翻~~ | `Keys[Index: Integer] (writable)` | 类型 | Read AND write the key (name) of row Index - renaming a row in place. | **推翻:** Keys[] is indeed read-only, so a ported 'VLE.Keys[0] := ...' will not compile — but renaming a row in place IS supported via the public row object: Row(i).Key := 'x' followed by UpdateRows. The claim that 'a row's key ca | SMALL |
| ~~推翻~~ | `FindRow(const KeyName: string; out aRow: Integer): Boolean` | 方法 | Locate the row index for a key. | **推翻:** Key lookup is reachable by scanning Keys[]. The genuine, unclaimed hole is narrower: for NESTED rows there is no public mapping from a row (or key path) to the flat visible index BeginEdit takes — a `FlatIndexOf(ARow)` a | MEDIUM |
| ~~推翻~~ | `Sort / Sort(Index, IndxFrom, IndxTo) / Sort(ACol: TVleSortCol)` | 方法 | Sort the rows by key or by value (TVleSortCol = colKey, colValue), optionally over a range, keeping each row's ItemProps with it. | **推翻:** Alphabetised display is achieved by building/re-adding rows in order. What is missing is in-place reordering (no MoveRow/Exchange) and, more to the point, any user-driven sort gesture — which is blocked by the absent col | MEDIUM |
| ~~推翻~~ | `Strings: TValueListStrings` | 子对象 | The editor's entire data model published as a TStringList of 'Key=Value' lines: assignable in one statement, sortable, streamable, editable in the designer's string-list editor, and carrying a paralle | **推翻:** Equivalent access exists as AddRow/AddChild/Clear/Keys[]/Values[]/ValueOf[] (tyControls.ValueListEditor.pas:174-203). The only true residue is DESIGN-TIME content authoring: rows can be created only in code, and a string | LARGE |
| ? | `OnStringsChange / OnStringsChanging` | 事件 | Fire around any change to the whole row set (add, delete, sort, bulk assign), not just a single value edit. | A dirty flag or a live preview cannot be driven off the editor - clearing and refilling it produces no notification at all. | SMALL |
| ? | `OnGetPickList: TGetPickListEvent` | 事件 | Fires with the row's key and a TStrings to fill, so the drop-down options are computed when the list opens. | Options that depend on live state (the list of open documents, the current database's tables) cannot be offered - the row must be rebuilt to change its choices. | MEDIUM |
| ? | `OnValidate: TOnValidateEvent` | 事件 | Fires with (ACol, ARow, KeyName, KeyValue) BEFORE a change is accepted, so the host can raise and reject. | A bad value cannot be refused - the host can only detect it afterwards and write a correction back, which the user sees flicker. | MEDIUM |

### `TTyHeaderControl`  (对标 `THeaderSection / THeaderSections`) — 13 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `MinWidth / MaxWidth (per section)` | 属性 | Per-section resize constraints, enforced during the drag. | You cannot pin a narrow fixed-width section (a 24px checkbox column) or cap a wide one; every section shares one 16px floor. | SMALL |
| **成立** | `Visible (per section)` | 属性 | Hide a section without deleting it, so column visibility can be toggled and restored. | A 'choose columns' menu cannot hide/show sections; it must delete and rebuild them. | SMALL |
| **成立** | `Anchors / BorderWidth` | 属性 | Standard layout properties: anchor the strip to its parent's edges; reserve an inner border. | A header strip cannot be anchored (e.g. left+right+top with a fixed height) in the designer — only Align-docked. | SMALL |
| **成立** | `Add / Insert / Delete / AddItem naming` | 改名 | Collection-style section management, including inserting at a position. | Header setup code does not port (HC.Sections.Add.Text := 'x' → HC.AddSection('x')), and adding a section anywhere but the end requires rebuilding the strip. | SMALL |
| **成立** | `Images / ImagesWidth + Section.ImageIndex` | 属性 | An icon in a header section, from an image list on the control. | No icons in a standalone header strip at all. | MEDIUM |
| **成立** | `DragReorder + OnSectionDrag + OnSectionEndDrag` | 属性 | Lets the user drag sections into a new order, with a vetoable OnSectionDrag(FromSection, ToSection, var AllowDrag) and an end-of-drag notification. | Users cannot reorder columns on a standalone header strip, although they can on TTyTreeView — an inconsistency inside the library. | MEDIUM |
| **成立** | `OnSectionClick / OnSectionResize / OnSectionTrack signatures (+ TSectionTrackState)` | 语义 | LCL passes the HeaderControl and the THeaderSection object; OnSectionTrack additionally reports the phase (tsTrackBegin / tsTrackMove / tsTrackEnd). | Handlers do not port; and 'begin a live preview on drag-start, tear it down on drag-end' cannot be expressed — only the width stream is available. | MEDIUM |
| **成立** | `Sections as a collection of section OBJECTS` | 子对象 | THeaderSections is a TCollection of THeaderSection (TCollectionItem) — editable in the Object Inspector, streamed into the .lfm, addressable as objects with per-section properties, Add/Insert/Delete/A | A THeaderControl is normally set up entirely in the designer and saved in the .lfm; TTyHeaderControl must be filled by code in FormCreate every time, and its sections cannot be edited, streamed, subclassed or referenced  | LARGE |
| ~~推翻~~ | `GetSectionAt(P: TPoint)` | 方法 | Public hit-test: which section is at this client point. | **推翻:** Hit-testing exists as the exported pure function TyHeaderSectionAtX (and TyHeaderResizeEdgeAtX for dividers). The only real friction is that it wants DEVICE widths while EffectiveSectionWidth is logical -- a public insta | SMALL |
| ~~推翻~~ | `PaintSection(Index) virtual` | 方法 | Per-section paint seam a descendant overrides to draw one section its own way. | **推翻:** Per-section appearance is a theme concern here ('TyTreeHeaderSection' + states); differentiating a single section by index is done by overriding Paint and drawing over the rect returned by the public TyHeaderSectionRects | MEDIUM |
| ? | `OnSectionSeparatorDblClick` | 事件 | Fires when the user double-clicks a divider — the standard 'auto-fit this column' gesture. | Double-clicking a divider on a TTyHeaderControl does nothing; there is no hook to auto-size the section. | SMALL |
| ? | `Left / Right (section bounds)` | 属性 | The on-screen left/right edge of a section — needed to align a control or a popup under it. | Placing a filter box or a dropdown under section N requires re-deriving the whole tiling by hand. | SMALL |
| ? | `State (hsNormal/hsHot/hsPressed) + OriginalIndex + SectionFromOriginalIndex` | 属性 | Query/force a section's visual state, and address a section by an index that survives user reordering. | Nothing can be keyed to a section reliably once positions move, and the pressed/hot state cannot be read for coordinated painting. | SMALL |

### `TTyComboBox`  (对标 `TCustomComboBox / TComboBox`) — 14 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `OnGetItems` | 事件 | Fires when the list is about to be shown so the application can populate Items just-in-time (lazy/expensive lists — files, DB lookups) instead of filling them up front. | No lazy population hook. Because DropDown early-exits on an empty Items list, the natural workaround (fill in OnDropDown) is structurally impossible — the first click on an empty lazy combo does nothing. | SMALL |
| **成立** | `TextHint` | 属性 | Grey placeholder text shown in the (empty) edit field, e.g. 'Select a country'. LCL emulates it where the widgetset lacks it, tracked via EmulatedTextHintStatus. | No placeholder on any combo. Forms ported from LCL lose their hint text silently, and the one-line forward to the embedded editor is already sitting there unused. | SMALL |
| **成立** | `SelStart, SelLength, SelText, SelectAll` | 属性 | The text-selection API of the combo's edit portion (UTF-8 positions), plus SelectAll to highlight everything — used to preselect on focus, to replace the selection, or to read what the user highlighte | On an editable combo there is no way to read or set the selection, or to select-all — so 'highlight the text when the field gets focus' and 'replace what the user selected' cannot be written at all, even though TTyEdit a | SMALL |
| **成立** | `AddHistoryItem (2 overloads) -> TTyMRUComboBox.AddToHistory` | 改名 | Promotes an item to the top of the list, de-duplicating (with a CaseSensitive flag), capping the list at MaxHistoryCount, optionally setting it as Text, and with an overload carrying an associated TOb | Ported code calling Combo.AddHistoryItem(s, 10, True, False) fails to compile, and the rename comes with three lost knobs: no per-call cap, no CaseSensitive choice (ours is always case-insensitive, MRUComboBox.pas:69 Sam | SMALL |
| **成立** | `DroppedDown (read/write property)` | 类型 | On LCL DroppedDown is a read/WRITE property: assigning True opens the list programmatically, False closes it. | `Combo.DroppedDown := True` — a common idiom for opening a combo from a button or a shortcut — does not compile; the caller must find and call DropDown instead. Reading also differs syntactically (DroppedDown vs DroppedD | SMALL |
| **成立** | `AutoComplete, AutoCompleteText, AutoDropDown, AutoSelect (+ AutoSelected)` | 属性 | Four separate behaviour switches for the editable field: AutoComplete/AutoCompleteText (default [cbactEndOfLineComplete, cbactSearchAscending]) COMPLETE the typed text in place, with options for case  | Four ported properties fail to compile, and the runtime behaviour differs both ways: users get a dropdown on every keystroke they cannot switch off, and never get the LCL 'type P, see Portugal completed and selected' in- | MEDIUM |
| **成立** | `Items (TStrings vs TStringList)` | 类型 | LCL types Items as TStrings so any TStrings source (Screen.Fonts, a TMemo.Lines, a TStringList) can be assigned directly, and the widgetset can substitute its own TStrings descendant. | `Combo.Items := SomeTStrings` (e.g. Screen.Fonts, ShellList.Items) is a compile error on our side — the caller must rewrite it as Items.Assign(...). A silent porting break in every place LCL code assigns Items. | MEDIUM |
| **成立** | `Style (TComboBoxStyle)` | 类型 | LCL's Style has 7 values (csDropDown, csSimple, csDropDownList, csOwnerDrawFixed, csOwnerDrawVariable, csOwnerDrawEditableFixed, csOwnerDrawEditableVariable) and defaults to csDropDown (editable). csS | A ported .lfm/.pas that sets Style := csSimple or any csOwnerDraw* value will not compile. Worse, the DEFAULT is inverted: an LCL combo is editable out of the box, ours is pick-only, so a form ported without an explicit  | LARGE |
| ~~推翻~~ | `Clear, ClearSelection, AddItem(const Item: String; AnObject: TObject), MatchListItem` | 方法 | Four public list methods: Clear empties Items AND blanks Text; ClearSelection unselects (ItemIndex := -1); AddItem appends a caption with an associated object; MatchListItem finds the item matching a  | **推翻:** Only MatchListItem(const AValue: TCaption): Integer (stdctrls.pp:412) is genuinely absent from TTyComboBox. Clear, ClearSelection and the two-arg AddItem are present and public; the claim's inventory was generated agains | SMALL |
| ~~推翻~~ | `DragMode, DragCursor, DragKind, OnDragDrop, OnDragOver, OnStartDrag, OnEndDrag` | 属性 | The standard LCL drag-and-drop surface — make the control a drag source (DragMode/DragKind/DragCursor) and a drop target (OnDragOver/OnDragDrop), with start/end notifications. | **推翻:** The gap was closed in HEAD (commit 425f56c, 'the drag surface ... republished on both base classes', which also added OnMouseWheelHorz/Left/Right and OnShowHint). The inventory this claim came from predates that commit. | SMALL |
| ? | `ItemHeight, ItemWidth` | 属性 | ItemHeight fixes the pixel height of a dropdown row (and drives AdjustDropDown's popup height); ItemWidth (default 0) sets the minimum pixel width allocated to the dropdown list, letting the list be w | No design-time control over dropdown row height or dropdown width. Rows always follow the theme's --item-height, so a combo of long paths cannot widen its list beyond the field, and an ItemHeight=32 in a ported .lfm is d | SMALL |
| ? | `ReadOnly` | 属性 | Makes the edit portion non-typable while the dropdown still works — the standard way to get 'pick from list, but keep the edit look/selection API' on an editable combo. | `Combo.ReadOnly := True` does not compile. There is no way to have an editable-looking combo that rejects typing but still exposes SelStart/SelText — the only option changes the control's whole appearance. | SMALL |
| ? | `OnDrawItem (TDrawItemEvent), OnMeasureItem (TMeasureItemEvent)` | 事件 | The owner-draw contract: with a csOwnerDraw* Style, OnDrawItem(Control, Index, ARect, State) lets the application paint each row on the combo's Canvas, and OnMeasureItem(Control, Index, var AHeight) g | Custom row rendering requires SUBCLASSING (a new unit, a CreatePopupList override) where LCL needs one event handler in the form — so no design-time custom drawing at all, and no variable-height rows: a combo of two-line | MEDIUM |
| ? | `AutoSize (default True)` | 属性 | On LCL a combo auto-sizes its height to the font/theme by DEFAULT; ShouldAutoAdjust restricts it to the height axis. | A combo whose font grows (or a skin with fatter padding) clips its text instead of growing, and the LCL default is inverted: ported code that relies on auto-height gets a hard 26px-derived height. This is exactly the fai | MEDIUM |

### `TTyTrackBar`  (对标 `TCustomTrackBar/TTrackBar`) — 14 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `TickStyle` | 属性 | How ticks are generated: tsNone (none), tsAuto (one every Frequency units, the default), tsManual (only ticks explicitly added by SetTick). | tsNone survives only as the non-obvious Frequency=0 idiom (a porting break for TickStyle:=tsNone), and tsManual -- irregular ticks at hand-chosen values, e.g. a gamma curve -- cannot be expressed at all. | SMALL |
| **成立** | `AutoSize` | 属性 | Lets the control size its cross-axis to what the groove, ticks and scale actually need (TCustomTrackBar overrides ShouldAutoAdjust so only the cross axis is auto-sized). | Bites exactly where this codebase has been bitten before: a skin that changes tick length, padding or the readout font makes a fixed Height=24 track bar clip its ticks or its value text, and there is no AutoSize to absor | SMALL |
| **成立** | `Max default (10 vs 100)` | 默认值 | The range ceiling a freshly dropped track bar starts with. | A .lfm ported from Lazarus that left Max at its default (so the value is not stored) silently becomes a 0..100 bar here, and every stored Position now means a tenth of what it used to -- the thumb lands near the left end | SMALL |
| **成立** | `PageSize default (2 vs 10)` | 默认值 | How far PgUp/PgDn moves the value by default. | Paging jumps five times as far as on the native control, and on the LCL default range (0..10) a page in LCL is a fifth of the range while ours would be the whole range. Not stored in a ported .lfm, so it changes behaviou | SMALL |
| **成立** | `Orientation (TTrackBarOrientation vs TTyTrackOrientation)` | 改名 | Horizontal or vertical track. | `TrackBar1.Orientation := trVertical` does not compile and a ported .lfm carrying Orientation=trVertical will not stream. Note the type is also named TTyTrackOrientation, not TTyTrackBarOrientation, so it does not even f | SMALL |
| **成立** | `Orientation (does not swap Width/Height)` | 语义 | LCL's SetOrientation swaps Width and Height (outside csLoading) so switching to vertical turns a wide short bar into a narrow tall one. | Setting Orientation to vertical at run time (or in the designer, which is the same code path) produces a visually broken control -- a 160x24 'vertical' bar whose thumb can barely move -- instead of a tall slider. The use | SMALL |
| **成立** | `Reversed` | 属性 | Flips the value axis independently of Orientation, so a horizontal bar can run max-to-min left-to-right, or a vertical bar can put Min at the top. | Two whole configurations are unreachable: a horizontal bar counting down left-to-right, and a vertical bar with Min at the top (a volume/attenuation slider). Ours forces vertical=inverted and horizontal=normal with no op | MEDIUM |
| **成立** | `SelStart / SelEnd / ShowSelRange` | 属性 | A highlighted sub-range on the track (the classic 'selection' band drawn between two values), with ShowSelRange to toggle it. | Any 'valid band' / 'selected interval' UI (audio trim, allowed-range indicator) cannot be expressed; a ported .lfm carrying SelStart/SelEnd/ShowSelRange fails to stream. | MEDIUM |
| **成立** | `TickMarks` | 属性 | Which side of the groove the tick marks are drawn on: tmBottomRight (default), tmTopLeft, or tmBoth. | Ticks can only sit below (horizontal) or right (vertical). A slider that needs ticks above its groove, or ticks on both sides, is impossible, and TickMarks=tmBoth in a ported .lfm will not load. | MEDIUM |
| ~~推翻~~ | `OnMouseWheelHorz / OnMouseWheelLeft / OnMouseWheelRight` | 事件 | Horizontal (tilt) wheel notifications, the natural gesture for a horizontal slider. | **推翻:** All three horizontal-wheel events are published library-wide at tyControls.Base.pas:149-151 / :272-274. What is genuinely still true is only that TTyTrackBar.DoMouseWheel handles the vertical wheel and does not itself mo | SMALL |
| ~~推翻~~ | `DragCursor / DragMode / OnDragDrop / OnDragOver / OnEndDrag / OnStartDrag / OnStartDock` | 事件 | LCL drag-and-drop participation: dmAutomatic starts a drag, the events let the control be a drag source or drop target, DragCursor picks the feedback cursor. | **推翻:** DragCursor/DragMode/OnDragDrop/OnDragOver/OnEndDrag/OnStartDrag are all published on both ty base classes (tyControls.Base.pas:138-144 and :261-267) and are inherited by TTyTrackBar. Separately, OnStartDock is not publis | MEDIUM |
| ~~推翻~~ | `SetTick` | 方法 | Adds a single tick mark at a caller-chosen value (the companion of TickStyle=tsManual). | **推翻:** SetTick is a Win32-only, handle-scoped, non-streamed widgetset pass-through -- not a portable API worth porting on its own. If non-uniform / manual ticks are actually wanted, the real gap is the absent TickStyle (tsNone/ | MEDIUM |
| ~~推翻~~ | `SetParams(APosition, AMin, AMax)` | 方法 | Sets position, minimum and maximum in one call so the three are validated together exactly once instead of clamping each other during the intermediate states. | **推翻:** Our SetMin/SetMax clamp Position exactly as LCL's do, and LCL's SetParams also requires the caller to supply the new position — so no route anywhere preserves a Position that falls outside the new range. `Max := 100; Min | MEDIUM |
| ? | `ScalePos` | 属性 | Where the numeric scale is drawn relative to the groove: trLeft, trRight, trTop (default) or trBottom. | No scale annotation at all, and the single value readout we do have cannot be moved to the other side. A ported .lfm carrying ScalePos will not stream. | SMALL |

### `TTyListView`  (对标 `TCustomListView`) — 16 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `GetNearestItem / GetNextItem` | 方法 | Find the item nearest to a point in a given direction, and step from an item in a direction filtered by state — the primitives behind icon-view arrow navigation. | 'Select the item nearest where the user clicked/dropped' and state-filtered stepping must be reimplemented from the layout primitives. | SMALL |
| **成立** | `ReadOnly default` | 默认值 | Whether the user can rename a row in place (F2 / click-on-label). | A ported form that never mentions ReadOnly loses inline rename silently — the .lfm streams nothing, so nothing hints at the change. | SMALL |
| **成立** | `Columns / Column[AIndex] / ColumnCount` | 改名 | The report columns collection, plus index shortcuts. | LV.Columns[0].Width := 120 and LV.ColumnCount do not compile; the extra Header hop also changes what the .lfm looks like, so designer files are not portable. | SMALL |
| **成立** | `ViewStyle enum + default` | 改名 | Icon / small-icon / list / report view selection. | `LV.ViewStyle := vsReport` does not compile, and a control left at its default shows a report instead of a list — a silent layout change on port. | SMALL |
| **成立** | `SortType / AlphaSort / CustomSort` | 改名 | SortType (stNone/stData/stText/stBoth) selects what auto-sorting compares; AlphaSort sorts column 0 ascending; CustomSort takes a plain compare function. | LV.SortType := stText does not compile; sorting by the item Data pointer (stData) has no equivalent, and a non-method compare function cannot be used. | SMALL |
| **成立** | `OnSelectItem signature` | 语义 | Fires for both select AND deselect, with a Selected: Boolean saying which. | A handler cannot tell selection from deselection, so multi-select bookkeeping has to re-scan the whole selection on every event. | SMALL |
| **成立** | `OwnerDraw + OnDrawItem + OnCustomDraw* / OnAdvancedCustomDraw*` | 事件 | The published owner-draw surface: OwnerDraw switches it on, OnDrawItem draws a whole report row, and the custom-draw family gives per-item/per-subitem/staged hooks with a DefaultDraw veto. | Custom row rendering in a list requires deriving a new class, while the sibling tree control can do it with a handler — an inconsistency inside this very group. | MEDIUM |
| **成立** | `OnInsert / OnDeletion` | 事件 | Fires when an item is inserted, and when one is about to be deleted (release the Data payload). | Items carrying an owned object in Data leak: there is no hook to free it when the row goes away. | MEDIUM |
| **成立** | `OnDataHint / OnDataFind / OnDataStateChange` | 事件 | Virtual-mode support beyond text: OnDataHint pre-fetches a visible index window, OnDataFind resolves searches in the app's store, OnDataStateChange reports selection/state changes over a range. | A million-row virtual list cannot batch-fetch the visible window (one call per cell instead), and search/selection in virtual mode has no delegation point. | MEDIUM |
| **成立** | `TopItem / VisibleRowCount / BoundingRect / ViewOrigin` | 属性 | Viewport queries (first visible item, how many rows fit, the bounding rect of all items) and the readable/writable scroll origin. | Saving and restoring a list's scroll position across a refresh is impossible, and page-sized navigation cannot be computed by the app. | MEDIUM |
| **成立** | `IconOptions (Arrangement / AutoArrange / WrapText)` | 子对象 | Icon-view layout options: icons arranged top-down or left-right, auto re-arrange, and whether long captions wrap. | Icon view is take-it-or-leave-it: no left-to-right arrangement and no caption wrapping, so long file names are simply clipped. | MEDIUM |
| **成立** | `OnChange(Item, Change) / OnChanging (vetoable)` | 语义 | OnChange says WHICH item changed and HOW (ctText/ctImage/ctState); OnChanging can veto the change. | A handler cannot tell which row or what aspect changed (so it must re-scan everything), and a change cannot be refused. | MEDIUM |
| **成立** | `Selected: TListItem / ItemFocused / LastSelected` | 类型 | Selected returns (or sets) the selected ITEM OBJECT; ItemFocused is the focused item; LastSelected the previous one. | `if LV.Selected <> nil then Edit1.Text := LV.Selected.Caption` — the canonical ListView idiom — does not port; ours is an index-first API throughout. | MEDIUM |
| **成立** | `LargeImages / SmallImages type` | 类型 | The row image lists. | Every app that already has a TImageList of file icons must rebuild it as a TTyImageCollection + TTyVirtualImageList before it can show any icon in the list. | MEDIUM |
| ~~推翻~~ | `Clear / AddItem(Item: string; AObject: TObject)` | 方法 | Control-level convenience: empty the list, and append a captioned row with a payload in one call. | **推翻:** Items.Clear (TCollection) empties the list and ItemCount is a published read/write property, so `LV.Items.Clear` / `LV.ItemCount := 0` covers both data modes today — the claim that Items.Clear 'cannot' reset ItemCount ig | SMALL |
| ? | `HotTrackStyles` | 属性 | How hot-tracking looks: hand cursor, underline always, or underline on hover. | A web-style link list (hand cursor + underline on hover) cannot be configured per control; only the theme can change it globally. | SMALL |

### `TTyMaskEdit`  (对标 `TCustomMaskEdit`) — 11 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `ValidateEdit` | 方法 | Public virtual: validates the current contents against the mask and, if incomplete/invalid, raises EDBEditError or fires OnValidationError (per ValidationErrorMode). The documented 'is this field acce | There is no built-in validation moment: a half-typed '12/__/____' leaves the control silently and reaches business code unless the developer remembers to poll IsComplete at every exit point. | MEDIUM |
| **成立** | `SpaceChar` | 属性 | The blank placeholder character (default '_') that fills unentered slots, so an empty date field reads '__/__/____' and the user can see how much is left to type. | A masked field gives the user no shape to fill in — no '__/__/____' skeleton, no indication of how many characters the mask wants — which is the main reason mask edits exist. TextHint partly compensates but disappears as | MEDIUM |
| **成立** | `EnableSets` | 属性 | Opts the mask parser into Lazarus set syntax — [abc], [a-z], [!abc] negation, [\|abc] optional — so a slot can accept an arbitrary character class. | Custom character classes are impossible: masks like a product code whose second slot must be one of [ABX] cannot be expressed, and a mask string using set syntax degrades into literals with no error. | MEDIUM |
| **成立** | `Text (assignment is not mask-validated)` | 语义 | LCL routes every Text assignment through the mask: RealSetText -> SetTextApplyMask/ApplyMaskToText pads, truncates and restores literals so the control can never hold a value the mask disallows. | Programmatic assignment (loading a record into the form, restoring a draft) bypasses the mask entirely, so the control's central invariant — 'contents always conform to the mask' — does not hold, and IsComplete then answ | MEDIUM |
| **成立** | `EditMask (mask language)` | 语义 | LCL/Delphi mask language: ~20 token codes (l/L letter, a/A alphanumeric, c/C any UTF-8 char, 9/0 digit, # digit-or-sign, h/H hex, b/B binary, > < case forcing, \\ escape, [abc] sets, : / locale separa | The worst kind of porting break: same property name, same type, compiles clean, and the field then silently accepts no input (or the wrong input) because the mask string means something else. Also blocks copying any of t | LARGE |
| **成立** | `caret placement / in-place slot editing` | 语义 | LCL mask editing is positional overwrite: the caret can be placed in (or arrowed/tabbed to) any editable slot, typing overwrites just that slot, literals are skipped automatically, and Backspace/Delet | Correcting one wrong digit in the middle of a date means deleting everything after it and retyping; and because arrows still move the caret while typing still appends, the control does something other than what the caret | LARGE |
| ~~推翻~~ | `Clear (mask-aware)` | 方法 | Resets the field to the EMPTY MASK — all literals restored, every editable slot back to the blank char — not merely to an empty string. | **推翻:** TTyEdit.Clear exists (tyControls.Edit.pas:153/477) and is inherited by TTyMaskEdit; the claim's grep missed it. And because this mask never renders blank placeholders (literals are deferred until the next slot fills, Mas | SMALL |
| ? | `OnValidationError` | 事件 | Fired when the contents fail mask validation (under mvemEvent), letting the form show its own message instead of an exception dialog. | No notification hook for invalid input: the designer's Events tab offers nothing between 'text changed' and manual polling of IsComplete. | SMALL |
| ? | `IsMasked` | 属性 | Read-only Boolean: is a (non-empty, valid) mask currently in force? The standard guard before running mask-specific logic. | Generic code that handles both masked and unmasked edits has no property to branch on, and IsComplete is easy to mistake for it (an empty mask makes IsComplete return False, not 'unmasked'). | SMALL |
| ? | `ValidationErrorMode` | 属性 | Chooses how a failed validation is reported: mvemException (raise, the default) or mvemEvent (call OnValidationError instead). | Applications cannot choose between an exception and a quiet callback for bad input — there is no reporting channel to configure in the first place. | SMALL |
| ? | `EditText` | 属性 | The raw contents of the control INCLUDING mask literals and blank placeholders, as distinct from Text (the data). Read/write; the pair is how mask edits separate presentation from value. | No supported way to read or set the field's literal display string, so 'restore exactly what the user saw' and partial-value round-tripping have no API; the value/display split that defines a mask edit is missing. | MEDIUM |

### `TTyImageCollection`  (对标 `TCustomImageList/TImageList`) — 8 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `OnChange / RegisterChanges / UnRegisterChanges / TChangeLink` | 事件 | Push notification that the image list changed: a direct OnChange event plus a TChangeLink registry so every consuming control repaints itself automatically when the list is edited. | Adding or replacing an icon at runtime does not repaint the toolbars/trees/menus that display it — every consuming control would have to poll ChangeStamp on a timer or the app must Invalidate everything by hand. | MEDIUM |
| **成立** | `AddSliced / AddSlice / AddSliceCentered / ReplaceSlice` | 方法 | Cuts one source bitmap into a grid of images (AHorizontalCount x AVerticalCount) or takes one sub-rectangle out of it — the usual way an icon SHEET becomes an image list. | A sprite sheet (very common for icon sets) has to be cut up by the caller with BGRA code before each piece can be added, and there is no way to reference a sub-rect of an existing master. | MEDIUM |
| **成立** | `GetBitmap(Index, TCustomBitmap) / GetIcon(Index, TIcon)` | 方法 | Exports one entry into an LCL TBitmap or TIcon (optionally with a draw effect) so it can be handed to native LCL controls, a clipboard, a TPicture, or saved to a file. | Handing a themed icon to a native LCL control, a TPicture, the clipboard or a file needs a hand-written BGRA-to-TBitmap conversion at every call site — the known-fragile path in this codebase. | MEDIUM |
| **成立** | `design-time / streamed image storage (DefineProperties, Bitmap+Data pseudo-properties)` | 子对象 | TCustomImageList streams its actual PIXELS into the form file via DefineProperties/WriteData/ReadData, which is what makes the IDE image-list editor (add/delete/preview images at design time) possible | A TTyImageCollection dropped on a form is permanently empty: there is no designer editor and nothing persists to the .lfm, so every icon set must be built in code at runtime. This is the single biggest usability gap vers | LARGE |
| **成立** | `multi-resolution masters (AddMultipleResolutions / RegisterResolutions / Resolution[] / ResolutionByIndex / Re` | 子对象 | One logical image can hold several hand-authored resolutions (16/24/32/48...); the list then serves the best one for a target PPI, and exposes per-resolution objects plus the SizeForPPI/WidthForPPI/He | Small sizes can only be produced by downscaling the big master, so a hand-tuned 16px icon (redrawn, not shrunk) is impossible — the exact reason LCL added multi-resolution lists. Consumers also have no 'what size will yo | LARGE |
| ~~推翻~~ | `BeginUpdate / EndUpdate` | 方法 | Batches a run of mutations: change notifications are suppressed and coalesced into one Change at EndUpdate. | **推翻:** BeginUpdate/EndUpdate on TTyImageCollection would suppress nothing — there is no notification mechanism and mutation is already O(1)+one lazy flush. The real (unclaimed) gap is the absence of an OnChange/observer surface | SMALL |
| ~~推翻~~ | `Delete / Insert / Move` | 方法 | Remove one image, insert one at a position, and reorder entries. | **推翻:** The only genuine residue is single-entry removal: there is no Remove(AName)/Delete, so dropping one icon means Clear plus rebuild. File a one-line `procedure Remove(const AName: string)` convenience item with no memory-l | SMALL |
| ~~推翻~~ | `AddMasked / AddIcon / AddLazarusResource / AddResourceName` | 方法 | The other standard ways to get pixels into a list: AddMasked(TBitmap, MaskColor) makes a colour-key transparent; AddIcon/InsertIcon/ReplaceIcon take a TCustomIcon (multi-size .ico); AddLazarusResource | **推翻:** Only AddMasked (colour-key -> alpha for legacy magenta-keyed BMPs) has no equivalent, and that is a 16-bit-era asset format the library never targets. At most add `AddMaskedBitmap(AName, ABmp, AKeyColor)`; the icon/resou | MEDIUM |

### `TTyCustomTabStrip`  (对标 `TCustomTabControl / TTabControl`) — 13 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `ShowTabs: Boolean` | 改名 | Boolean that hides the whole tab band while keeping the pages (default True). | Ported code and .lfm files that set ShowTabs=False do not compile/load; and hiding the band via a magic 0 in a size property is not discoverable in the object inspector, nor reversible without remembering the old height. | SMALL |
| **成立** | `DisplayRect / TabRect(AIndex)` | 改名 | DisplayRect: the rectangle the active page occupies inside the control. TabRect(Index): the rectangle of one tab header. | PC.TabRect(i) and PC.DisplayRect do not compile after a port; custom drawing/hit-testing code that positions overlays over a tab or over the page area must be rewritten against Ty-prefixed names, and there is no accessor | SMALL |
| **成立** | `ScrollTabs(Delta)` | 改名 | Scrolls the tab band by Delta tabs. | Ported calls do not compile, and the unit differs (px vs tabs), so a mechanical rename produces a scroll of the wrong distance. | SMALL |
| **成立** | `OnCloseTabClicked: TNotifyEvent` | 改名 | Fires when the user clicks a tab's close button. | Ported handlers do not compile and the .lfm event name is unknown; LCL also hands the handler the PAGE while ours hands an index, so the body needs rewriting too. | SMALL |
| **成立** | `TabHeight` | 语义 | Height of the tab band. In LCL it is a Smallint where 0 means 'let the widget size it from the font' and it is stored only when > 0. | Same property name, opposite meaning at the boundary value: a ported form that leaves TabHeight=0 for 'automatic' gets a page control with no tab band at all and looks broken. Type also narrows/widens (Smallint vs Intege | SMALL |
| **成立** | `OnChanging: TTabChangingEvent` | 类型 | Pre-switch veto fired before the selection moves. | Same event name, incompatible signature: an existing OnChanging handler will not assign, and the .lfm event link resolves to a method the compiler rejects. (Ours carries more information, so the break is one-directional  | SMALL |
| **成立** | `IndexOfTabAt(X,Y) / IndexOfTabAt(P) / IndexOfPageAt(X,Y) / IndexOfPageAt(P) / GetHitTestInfoAt(X,Y)` | 方法 | Point-to-index hit testing: which tab is under a point, which page is under a point, and what part of the control a point falls on (THitTests). | No supported way to write a tab context menu, tooltip-per-tab, or drag-to-another-pager: you cannot ask 'which tab did the user right-click?'. Ported code calling IndexOfTabAt does not compile. | MEDIUM |
| **成立** | `TabWidth: Smallint` | 属性 | Forces every tab to a fixed pixel width (0 = size to caption). | Cannot make tabs equal-width; captions of differing length give a ragged strip, and there is no way to pin a uniform grid of tabs. | MEDIUM |
| **成立** | `MultiLine / RaggedRight / ScrollOpposite / RowCount` | 属性 | The multi-row tab band: wrap tabs onto several rows (MultiLine), do not stretch the last row to full width (RaggedRight), keep the selected row on the opposite side (ScrollOpposite), and report how ma | A page control with 20 tabs can only be scrolled, never wrapped, so users must hunt with arrows where LCL shows all tabs at once; RowCount-based layout code cannot be ported. | LARGE |
| **成立** | `Images / ImagesWidth / ImageIndex / OnGetImageIndex / GetImageIndex` | 子对象 | The whole tab-icon feature: an image list on the control, a per-resolution width, a per-page ImageIndex, a callback to supply an index per tab, and a public getter. | Tabs cannot carry icons at all — the single most requested tab decoration, and standard in every ported Delphi/Lazarus form. TTyVirtualImageList already exists, so this is wiring, not new infrastructure. | LARGE |
| ? | `Style: TTabStyle` | 属性 | Renders the tab band as classic tabs, as raised buttons, or as flat buttons (tsTabs/tsButtons/tsFlatButtons), default tsTabs. | The button-strip look (used for wizard/segment style tab bars) is unavailable, and Style=tsButtons in a ported form is a load error. | MEDIUM |
| ? | `Options: TCTabControlOptions` | 属性 | Set of behaviour flags: nboShowCloseButtons, nboMultiLine, nboHidePageListPopup, nboKeyboardTabSwitch, nboShowAddTabButton, nboDoChangeOnSetIndex. | No add-tab '+' button and no page-list popup for overflow (LCL's alternative to scroll arrows); OnChange always fires on a programmatic index set, with no nboDoChangeOnSetIndex opt-out; Options=[...] in a ported form fai | MEDIUM |
| ? | `HotTrack / MultiSelect / OwnerDraw` | 属性 | HotTrack: highlight the tab under the mouse (default False). MultiSelect: allow several tabs selected in button styles (default False). OwnerDraw: let the app paint tabs itself (default False; the pai | Hover highlight cannot be turned off (a deliberate design choice in flat/static skins); no multi-select tab strip; an app that owner-draws its tabs has no escape hatch, and HotTrack/MultiSelect/OwnerDraw in a ported .lfm | MEDIUM |

### `TTyToolBar`  (对标 `TToolBar / TToolButton`) — 10 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Indent` | 默认值 | Blank space reserved at the leading edge of the bar before the first tool. | A ported .lfm that omits Indent (i.e. relied on LCL's 1) silently gets 4 logical px of leading gap, and because our Indent doubles as the vertical pad the whole bar also gets 8 px taller than the same value produced in L | SMALL |
| **成立** | `OnPaintButton, OnPaint` | 事件 | OnPaintButton(Sender: TToolButton; State: integer) lets the app custom-draw an individual tool; OnPaint lets it draw over the bar's own surface after the bar paints. (TControlBar publishes OnPaint too | An app that decorated one tool (an overlay badge, a custom pressed look) or drew on the bar background has nowhere to hook and must subclass the control instead of assigning an event. | MEDIUM |
| **成立** | `ButtonWidth, DropDownWidth, ButtonDropWidth, SetButtonSize` | 属性 | The uniform width side of button metrics: ButtonWidth forces every tool to the same width (paired with ButtonHeight), DropDownWidth sizes the arrow half of a tbsDropDown tool, ButtonDropWidth is the r | A ported ToolBar with ButtonWidth=64 loses uniform buttons: each tool keeps whatever width it happens to have, so the bar reads ragged and .lfm ButtonWidth/DropDownWidth values are silently dropped. | MEDIUM |
| **成立** | `Images` | 语义 | On LCL the bar's image list is the icon source for every child tool: TToolButton.ImageIndex selects from it, GetCurrentIcon resolves list+index+effect, and assigning it re-measures and repaints every  | Setting Bar.Images does nothing visible — the property exists, streams from a ported .lfm, and silently has no effect, which is worse than a compile error. And a TCustomImageList-typed list (the usual case, including thi | MEDIUM |
| **成立** | `ShowCaptions` | 语义 | Turns the tools' text on: with ShowCaptions=False a tool is icon-only, with True the caption is drawn too, and the bar re-measures every button so the row grows. | Toggling ShowCaptions at design time or run time changes nothing at all, so an icon-only bar cannot be switched to icon+text (or back) the way the LCL property implies. | MEDIUM |
| **成立** | `TToolButton (whole class: Style tbsButton/tbsCheck/tbsDropDown/tbsSeparator/tbsDivider/tbsButtonDrop, Down, Gr` | 子对象 | The LCL toolbar's item class. One TGraphicControl per tool with six styles (push / latching check / dropdown-with-arrow / separator / divider / button+arrow), radio grouping via Grouped+AllowAllUp, an | Every ported form that declares `object ToolButton1: TToolButton` fails to stream. There is no latching/radio tool, no per-item icon index, no per-item dropdown arrow, and no Wrap, so a ported toolbar has to be rebuilt o | LARGE |
| ? | `ButtonCount, Buttons[Index], ButtonList, RowCount, GetEnumerator (TToolBarEnumerator), BeginUpdate, EndUpdate` | 属性 | The bar's programmatic surface: a typed indexed list of its tools, the count, the raw TList, how many wrapped rows the current layout produced, a for-in enumerator, and BeginUpdate/EndUpdate to batch  | `for i := 0 to Bar.ButtonCount-1 do Bar.Buttons[i].Enabled := ...` — the single most common toolbar idiom — does not compile; nor does `for B in Bar do`. Adding ten tools in a loop re-runs the full layout ten times becau | MEDIUM |
| ? | `HotImages, DisabledImages, ImagesWidth` | 属性 | The rest of the icon-list family: a separate hover image set, a separate greyed image set used when a tool is disabled (instead of auto-greying), and ImagesWidth to pick the HiDPI resolution to draw f | Ported .lfm properties are lost; there is no way to supply hover or disabled artwork, and no way to tell a multi-resolution image list which pixel size to use on a HiDPI screen. | MEDIUM |
| ? | `List` | 属性 | Places each tool's caption to the RIGHT of its icon instead of below it — the classic 'large icons with text beside' toolbar mode; the bar re-measures buttons horizontally when it flips. | No bar-wide icon/text arrangement switch. Every child must be configured individually (and only if it happens to be a TTyGlyphButton), so a ported List=True toolbar loses its layout mode. | MEDIUM |
| ? | `EdgeBorders, EdgeInner, EdgeOuter, Transparent` | 属性 | The bar's own chrome: EdgeBorders picks WHICH sides get an edge (TToolBar defaults to [ebTop]), EdgeInner/EdgeOuter choose raised/lowered/none for the inner and outer bevel of those edges, and Transpa | A ported bar's edge always lands on the bottom regardless of EdgeBorders, an ebLeft/ebRight-bordered vertical bar is impossible, and Transparent=True cannot be expressed as a property (only by hand-writing CSS into Style | MEDIUM |

### `TTyCheckListBox`  (对标 `TCheckListBox/TCustomCheckListBox`) — 7 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `State[AIndex]: TCheckBoxState (tri-state incl. cbGrayed)` | 属性 | Per-row three-state check value, and the tri-state cycle Unchecked -> Checked -> Grayed on toggle. | A 'partially selected' row (a parent whose children are mixed) cannot be shown, and ported code using CLB.State[i] does not compile. | MEDIUM |
| **成立** | `ItemEnabled[AIndex]: Boolean` | 属性 | Disables an individual row: it renders greyed and neither the click nor the Space key can toggle it. | An options list where some choices are unavailable (licence-gated, mutually exclusive) must instead delete the rows or fight the control in an event handler. | MEDIUM |
| **成立** | `Header[AIndex]: Boolean` | 属性 | Marks a row as a group header: it is drawn without a checkbox, in the header colours, spanning the full row width. | A grouped check list ('Fonts / Effects / Advanced' bands) is not expressible; the user would have to fake headers as checkable rows. | MEDIUM |
| ~~推翻~~ | `Toggle(AIndex); CheckAll(AState, aAllowGrayed, aAllowDisabled); Exchange(AIndex1, AIndex2)` | 方法 | Programmatically toggle one row, set every row at once (optionally skipping grayed/disabled rows), and swap two rows together with their check state. | **推翻:** 'No supported way to toggle a row from code' is false: Checked[AIndex] is a public read/write property (tyControls.CheckListBox.pas:30), so Checked[i] := not Checked[i] toggles, and a check-all/uncheck-all button is a th | SMALL |
| ? | `AllowGrayed: Boolean` | 属性 | Decides whether the user's toggle cycles through the grayed state or only Checked/Unchecked. | Even after tri-state is added there is no switch to opt in/out, and the property name that exists on our own TTyCheckBox is missing here — inconsistent within the library. | SMALL |
| ? | `HeaderColor: TColor; HeaderBackgroundColor: TColor` | 属性 | The ink and band colour used for header rows (LCL defaults clInfoText on clInfoBk). | Porting code that sets these fails to compile. Note the raw-TColor form is wrong for this library anyway — the themed equivalent would be a header/band token, which is what should be added instead of the two properties. | SMALL |
| ? | `'Data' binary pseudo-property (DefineProperties / ReadData / WriteData)` | 属性 | Streams every row's check state into the .lfm alongside Items, so boxes ticked at design time come back at run time. | A developer who ticks rows in the Object Inspector sees them all unchecked when the program runs, with no error to explain it; defaults must be re-applied in FormCreate. | MEDIUM |

### `TTyUpDown`  (对标 `TCustomUpDown/TUpDown`) — 13 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `OnClick(Sender; Button: TUDBtnType)` | 改名 | The direction-carrying click event: tells the handler which arrow was pressed, per step, including each auto-repeat tick. | The trap the header comment describes is real in both directions: ported code assigning UpDown1.OnClick compiles here against a TNotifyEvent and silently loses the direction, and code assigning the direction handler must | SMALL |
| **成立** | `Orientation (TUDOrientation vs TTyUpDownOrientation)` | 改名 | Stacks the two halves vertically (default) or side by side. | `UpDown1.Orientation := udHorizontal` does not compile, and a .lfm carrying Orientation=udHorizontal will not stream. Pure porting friction -- behaviour matches. | SMALL |
| **成立** | `Wrap (arithmetic)` | 语义 | How a step that runs past a bound wraps: LCL carries the overshoot around modularly (Min + (pos+Inc-Max) - 1), so the remainder is preserved. | Identical for Increment=1 (the common case) and different for every larger increment: on Min=0/Max=10/Increment=3 from 9, LCL lands on 1 and we land on 0. A stepper cycling non-unit increments drifts onto the wrong value | SMALL |
| **成立** | `OnChanging` | 事件 | Veto hook fired before the position moves: the handler sets AllowChange := False to refuse the step. | There is no way to refuse a step (e.g. 'cannot exceed the quantity in stock'): OnChange fires after the fact, so the handler must push the value back, which re-enters the setter and fires OnChange again. LCL's veto is on | MEDIUM |
| **成立** | `Associate` | 属性 | Binds the spin-button pair to a companion TWinControl (normally an edit): the up/down positions itself against that control, keeps its own bounds/enabled/visible in sync with it, and writes Position b | The headline reason people drop a TUpDown on a form -- 'glue this to Edit1' -- does not port. Every user must hand-write an OnChange handler that formats the number into the edit, re-parses it back, repositions the butto | LARGE |
| ~~推翻~~ | `OnMouseWheelHorz / OnMouseWheelLeft / OnMouseWheelRight` | 事件 | Horizontal (tilt) wheel events; on TCustomUpDown they are wired to real behaviour -- DoMouseWheelLeft/Right are overridden so a tilt steps the value. | **推翻:** The three events exist and are assignable from the Object Inspector. What is genuinely missing is narrower and different in kind: LCL's TCustomUpDown OVERRIDES DoMouseWheelLeft/DoMouseWheelRight (comctrls.pp:1978-1979) s | SMALL |
| ~~推翻~~ | `Flat` | 改名 | Per-instance switch between a flat and a raised/3D button pair. | **推翻:** Excluded by the theme-token rule, not a gap: the flat/raised distinction is expressed as a StyleClass on the shared 'TyButton' key. Adding a per-instance Boolean Flat would be a rule violation, not a fix. | SMALL |
| ~~推翻~~ | `Min / Max / Position (SmallInt vs Integer)` | 类型 | LCL types the range and value as SmallInt (-32768..32767); ours are Integer. | **推翻:** Not a parity gap. Integer is wider than LCL's SmallInt and accepts every LCL-legal value; nothing a ported program could previously do stops working. If anything the note belongs in migration docs, not in a gap list. | SMALL |
| ? | `MinRepeatInterval` | 属性 | Floor on the auto-repeat interval while a button is held (default 100 ms, clamped to >= 25), i.e. how fast a held button accelerates. | Hold-to-repeat speed is not tunable: a range of 0..10000 is unusable at 60 ms/step, and an accessibility setting that wants it slower cannot be honoured. | SMALL |
| ? | `Thousands` | 属性 | Whether the position written into the associated control's text is grouped with thousand separators (LCL default True). | Dependent on Associate, so it is currently moot -- but it means a ported .lfm carrying Thousands=False cannot stream, and once Associate lands the grouping default (True in LCL) will differ. | SMALL |
| ? | `OnChangingEx` | 事件 | The richer veto hook: besides AllowChange it hands the handler the PROPOSED NewValue and the Direction (updUp/updDown) of the pending step. | A handler cannot decide 'allow this specific value but not that one' -- it sees neither the target value nor (with veto power) the direction. Any ported OnChangingEx handler has nowhere to go. | MEDIUM |
| ? | `AlignButton` | 属性 | Which side of the associated control the button pair snaps to: udLeft, udRight (default), udTop or udBottom. | Even once Associate exists, the buttons cannot be placed on the left of the field (common in RTL layouts and in some form styles); today the user must position them by hand and re-position on every resize. | MEDIUM |
| ? | `ArrowKeys` | 属性 | When True (LCL's default) the Up/Down arrow keys step the value -- including arrows pressed inside the ASSOCIATED control, which LCL forwards via AssociateKeyDown. | The up/down is mouse-only: it can never be reached by Tab and no key can drive it, so a keyboard-only user cannot change the value. This is structural (graphic vs windowed control), not a one-property fix. | LARGE |

### `TTyScrollBox`  (对标 `TScrollBox/TScrollingWinControl`) — 11 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `OnConstrainedResize` | 事件 | Fires during size negotiation so a host can clamp MinWidth/MaxWidth/MinHeight/MaxHeight for this resize pass (var parameters), before the new bounds are applied. | Dynamic size limits (e.g. 'this pane may never exceed half the form') cannot be expressed — only the fixed Constraints values. A ported form loses the handler silently. | SMALL |
| **成立** | `ScrollInView(AControl)` | 方法 | Scrolls the minimum amount needed to bring a given child control fully into the viewport (clamping when the child is larger than the client area). | Focus/keyboard navigation inside a scroll box does not follow the content: tabbing to a child below the fold leaves it invisible, and the host has no one-liner to fix it (and no public scroll setter to hand-roll it, see  | SMALL |
| **成立** | `VertScrollBar.Position / HorzScrollBar.Position` | 属性 | Read AND write the current scroll offset per axis — the way a host scrolls programmatically (jump to top, restore a saved position, follow a selection). | An application cannot scroll its own scroll box: no 'scroll to top', no persisting/restoring the scroll position across sessions, no scrolling in response to a keyboard or search hit. The user is limited to the mouse whe | SMALL |
| **成立** | `VertScrollBar.Increment` | 属性 | How far one 'line' scrolls — the step used by an arrow click and the wheel (default 8 px). | Wheel/step granularity is fixed and theme-dependent (it changes with --scrollbar-size), so a list of 20 px rows and a page of 200 px cards scroll by the same odd amount and neither can be tuned to a row height. | SMALL |
| **成立** | `VertScrollBar.Visible / HorzScrollBar.Visible` | 属性 | Per-axis opt-out/opt-in for a scrollbar: hide one axis entirely (vertical-only scrolling) or keep a bar reserved so the layout does not jump when content grows. | You cannot build a vertical-only scroll region (a wide child will always raise a horizontal bar), nor reserve a gutter to stop the content reflowing when a bar appears — the classic 'content jumps sideways as it grows' c | SMALL |
| **成立** | `AutoScroll` | 属性 | Master switch for automatic scrollbars: True (TScrollBox's default) computes ranges and shows/hides bars as content changes; False hides both bars and stops the automatic range computation. | A ported .lfm carrying AutoScroll = False does not stream, and there is no way to freeze a scroll box as a plain clipping viewport (bars off, no measuring) — useful when the host drives the offset itself. | SMALL |
| **成立** | `UpdateScrollbars` | 改名 | Public 'recompute ranges and refresh the bars now' entry point, called after the host changes content outside the normal notification paths. | Pure porting friction: existing code calling ScrollBox1.UpdateScrollbars fails to compile and must be renamed; the two names also invite the belief that the ty version does something different. | SMALL |
| **成立** | `ScrollBy(DeltaX, DeltaY)` | 语义 | On a scrolling container, ScrollBy is the public 'scroll the view by this delta' operation: TScrollingWinControl overrides it to do a widgetset scroll so the client origin AND the scrollbar state stay | Calling Box.ScrollBy(0, -50) — the documented LCL way to scroll a container — moves the children AND the two scrollbars off their docked edges while FScrollY stays 0. The very next UpdateScrollRange re-measures the moved | SMALL |
| **成立** | `HorzScrollBar / VertScrollBar (TControlScrollBar sub-objects)` | 子对象 | Two published sub-objects that ARE the scrolling API: Increment, Page, Position, Range, Smooth, Tracking and Visible per axis, settable in the OI and from code, plus Assign/IsScrollBarVisible/ScrollPo | None of the scrolling behaviour is configurable or observable from outside the control: no design-time scroll settings, and code that reads or writes ScrollBox1.VertScrollBar.* (the standard LCL/Delphi idiom) does not co | MEDIUM |
| ~~推翻~~ | `OnMouseWheelHorz / OnMouseWheelLeft / OnMouseWheelRight` | 事件 | Horizontal wheel / tilt-wheel / trackpad-swipe input, dispatched by TControl.DoMouseWheelHorz and DoMouseWheelLeft/Right. | **推翻:** All three events are already published on both base classes (tyControls.Base.pas:149-151 and :272-274), so they are available on TTyScrollBox from code, the Object Inspector and a .lfm. The only thing that could still be | SMALL |
| ? | `VertScrollBar.Range (+ CalculateAutoRanges hook)` | 属性 | The scrollable content extent per axis, settable explicitly (Range) and overridable by a descendant (CalculateAutoRanges) — the way you scroll content that is DRAWN rather than made of child controls. | A scrollable owner-drawn surface (a big diagram, a canvas, a custom timeline) cannot be built on TTyScrollBox: the only way to obtain a scroll range is to add real child controls sized to the content. Descendants have no | MEDIUM |

### `TTyEdit`  (对标 `TCustomEdit`) — 12 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `AddHandlerOnChange / RemoveHandlerOnChange` | 方法 | Multicast OnChange: several observers can subscribe to text changes without stealing the single OnChange slot. | Library or framework code that wants to observe an edit (a validator, a dirty-tracker, a live preview) must take the one OnChange property away from the application, or the application must chain the calls by hand. | SMALL |
| **成立** | `Modified` | 属性 | Read/write dirty flag: set True by any user text change, cleared by a programmatic Text assignment; the standard 'has the user edited this field' test. | No way to ask whether the user touched the field; save/validate/'discard changes?' logic ported from LCL or Delphi must be rewritten with a manual OnChange flag. Missing on all three controls. | SMALL |
| **成立** | `HideSelection` | 属性 | When True (the default) the selection highlight is hidden while the control is not focused; the selection itself is preserved. | An unfocused TTyEdit keeps painting its selection band, so a form with several edits shows two or three 'active-looking' selections at once. The capability is already implemented one unit away (TTyMemo) and simply not wi | SMALL |
| **成立** | `AccessibleRole` | 默认值 | TCustomEdit's constructor announces itself to assistive technology as a single-line text editor; a memo inherits the same role. | A screen reader reads a TTyEdit as an unidentified custom control rather than a text field, so the whole self-drawn text-input family is opaque to assistive technology. One assignment per control class fixes it. | SMALL |
| **成立** | `ClearSelection` | 语义 | LCL: DELETES the selected text (SelText := '' when SelLength > 0). | The single most dangerous entry in this group: ported code that calls ClearSelection to delete the highlighted text silently keeps the text (a Delete/Clear menu item stops working) and the compiler cannot warn, because t | SMALL |
| **成立** | `EchoMode / PasswordChar` | 类型 | EchoMode (emNormal/emPassword/emNone) selects how text is echoed; PasswordChar is a single Char (default #0 = no masking) and the two are kept in sync (setting one drives the other). | Ported code assigning Edit.PasswordChar := '*' compiles (string accepts a char literal) but PasswordChar := #0 to turn masking OFF silently masks with NUL instead, and any use of EchoMode (notably emNone, 'show nothing a | SMALL |
| **成立** | `CaretPos` | 类型 | Caret position as a TPoint (X = character index in the line, Y = line index; for a single-line edit Y is always 0). | Code written against LCL/Delphi (Edit.CaretPos := Point(n, 0), or reading CaretPos.X) does not compile; a same-named property with an incompatible type is worse than an absent one because the porting error surfaces at ev | SMALL |
| **成立** | `AutoSelect (and AutoSelected)` | 属性 | Default True: the whole text is selected when the control gains focus by keyboard/Enter and on the first left click, so typing replaces the old value. AutoSelected is the 'already did it' latch. | Tabbing into a TTyEdit leaves the caret wherever it was instead of selecting the value, so the standard 'tab in, type the new number' data-entry flow needs an explicit SelectAll in every OnEnter handler, and forms ported | MEDIUM |
| **成立** | `AutoSize` | 属性 | Default True on TCustomEdit: the control's height follows the font (CalculatePreferredSize returns the font-derived height and ignores width). | Raising Font.Size on a TTyEdit leaves the box its original height and clips the glyphs; the designer/user must re-height every edit by hand, and a .lfm ported from LCL (which relied on AutoSize) comes out the wrong heigh | MEDIUM |
| ~~推翻~~ | `Clear` | 方法 | Public one-liner that empties the control (Text := ''). | **推翻:** Clear exists on TTyEdit (tyControls.Edit.pas:153 decl, :477 body) and is inherited by TTyMemo/TTyMaskEdit. No gap. | SMALL |
| ~~推翻~~ | `DragMode / DragKind / DragCursor + OnDragDrop / OnDragOver / OnStartDrag / OnEndDrag` | 属性 | The whole LCL drag-and-drop surface: make the control a drag source (dmAutomatic) or drop target and handle the four drag events. | **推翻:** DragMode/DragKind/DragCursor + OnDragOver/OnDragDrop/OnStartDrag/OnEndDrag are published at tyControls.Base.pas:138-144 and :261-267 and are therefore live on TTyEdit and every other TTy control. | SMALL |
| ? | `BidiMode / ParentBidiMode` | 属性 | Right-to-left support: mirrors text direction, caret side, alignment and the horizontal scroll origin for Hebrew/Arabic. | RTL languages are unusable in every text-input control of this library: the caret, the selection band and the horizontal scroll all run the wrong way and there is no property to ask for the other direction. Concept has n | LARGE |

### `TTyShellListView`  (对标 `TCustomShellListView/TShellListView`) — 14 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `OnAddItem: TAddItemEvent` | 事件 | Per-entry veto during population: (ABasePath, AFileInfo, var CanAdd). | Filtering beyond a filename mask -- by size, date, attribute, or an app blocklist -- requires post-processing that the control does not expose (FEntries is read-only, :102). | SMALL |
| **成立** | `MaskCaseSensitivity: TMaskCaseSensitivity` | 属性 | Whether the file Mask matches case-sensitively, case-insensitively, or per platform default (mcsPlatformDefault). | On Linux/macOS a mask of '*.PAS' matches lowercase .pas files, unlike a native TShellListView at its default setting, and an app that needs exact-case matching has no way to ask for it. | SMALL |
| **成立** | `AutoSizeColumns` | 属性 | Redistributes the Name/Size/Type column widths as a percentage of the client width on every resize; default True. | Widening or narrowing the pane leaves a dead gap on the right (or clips Modified); with a wide window the Name column stays 220px while the rest is empty. Every host has to hand-code column sizing. | SMALL |
| **成立** | `Root` | 改名 | The directory whose contents are listed; assigning it re-reads the folder. | Porting break: `ShellListView1.Root := Dir` does not compile, and the tree/list linkage code in LCL examples (which assigns ShellListView.Root) has to be rewritten. | SMALL |
| **成立** | `UpdateView` | 改名 | Re-reads the current directory in reaction to filesystem changes AND restores the previously selected row by CAPTION (FindCaption), then cascades the refresh to the linked ShellTreeView. | Two losses: the method name a port calls does not exist, and after a refresh the selection stays pinned to a row INDEX -- so if a file was added or removed above it, the highlighted row is now a different file than the u | SMALL |
| **成立** | `Items (TListItems of TShellListItem: isFolder, FileInfo: TSearchRec)` | 改名 | The per-file item objects, each carrying its TSearchRec, exposed publicly ('Protected properties which users may want to access, see bug 15374') plus Caption/SubItems/Data/ImageIndex per row. | Porting break plus a live trap: `ShellListView1.Items[i].Caption` compiles against our control (Items is published) and silently returns nothing, because the real data is in Entries. There is no per-item object to attach | SMALL |
| **成立** | `Refresh` | 语义 | On every LCL control Refresh means 'repaint now' (Invalidate + Update). LCL's shell list keeps that meaning and uses UpdateView for the disk re-read. | Generic code that calls Refresh on a control to force a repaint (a theme switch, a custom draw loop) unknowingly triggers a synchronous directory scan on every call -- a disk hit and a possible re-sort where a repaint wa | SMALL |
| **成立** | `OnCompare / OnItemActivate` | 语义 | TShellListView publishes OnCompare for the application (its own sorting goes through SortType/SortColumn), and leaves OnDblClick/OnSelectItem free. | Assigning OnCompare in the Object Inspector silently reverts sorting to lexical display-string order -- exactly the '10 KB before 9 KB' bug the unit header warns about -- and assigning OnItemActivate kills folder navigat | SMALL |
| **成立** | `Size column formatting (sShellCtrlsBytes / sShellCtrlsKB / sShellCtrlsMB)` | 语义 | LCL renders the Size column through localized resourcestrings from LCLStrConsts, so the unit words follow the application language. | The Size column cannot be translated and always shows English units with a dot decimal separator, even in a fully localized app -- and the strings are invisible to the project's i18n pass. | SMALL |
| **成立** | `ObjectTypes: TObjectTypes` | 属性 | Published set choosing folders / non-folders / hidden. LCL default is [otNonFolders] -- a files-only pane. | A files-only pane (the LCL default!) or a folders-only pane cannot be configured; every TTyShellListView always mixes folders and files. Also a silent default change for anyone porting a .lfm. | MEDIUM |
| **成立** | `ShellTreeView` | 属性 | Design-time link to a shell tree; the list's UpdateView also refreshes the linked tree at the same directory (guarded against recursion by FLockUpdate). | Diving into a folder in the list does not move the companion tree unless the app writes the glue; and the pair cannot be connected in the designer at all. | MEDIUM |
| ~~推翻~~ | `GetPathFromItem(ANode: TListItem): string` | 改名 | Maps a list item to its full path. | **推翻:** The path-from-row capability EXISTS as tyControls.ShellListView.pas:581 `function FileAt(AIndex: Integer): string` plus SelectedFile (:576). LCL's TListItem parameter type has no counterpart in a virtual list, so a GetPa | SMALL |
| ? | `OnFileAdded: TCSLVFileAddedEvent` | 事件 | Fires with the freshly created TListItem for each accepted file, so the app can decorate the row (extra sub-items, state image, colour). | No hook to annotate rows as the directory is read (e.g. mark read-only files, attach per-file data); an app must re-derive everything from Entries afterwards. | SMALL |
| ? | `UseBuiltInIcons` | 属性 | Turns the control's own file-kind glyphs off (default True), so an assigned Small/LargeImages list -- or no icon column -- is used. | No supported way to run the list without the built-in content icons (a compact text-only file pane), and no themed equivalent of the switch either. | SMALL |

### `TTyDivider`  (对标 `TDividerBevel`) — 9 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `bold caption (Font.Style default)` | 默认值 | TDividerBevel's constructor adds fsBold to Font.Style, so a section divider's caption is bold unless the user clears it. | A ported section divider loses its bold caption and cannot get it back the obvious way (Font.Style); it needs a theme rule or a StyleOverride string, so ported forms lose the visual weight that separated their sections. | SMALL |
| **成立** | `LeftIndent (ours: Alignment)` | 语义 | Pixel offset of the caption from the leading edge, default 60; 0 means flush to the edge and any negative value means 'centre the caption' - so it expresses alignment AND an exact indent. | TDividerBevel's default is a 60px indent, so every ported divider's caption jumps to the left edge; and a caption aligned to a form's label column (the usual reason for the indent) cannot be expressed. Ours does add taRi | SMALL |
| **成立** | `Caption` | 语义 | TDividerBevel publishes TControl's own Caption, i.e. the control's Text, so Caption/Text are one string and a change routes through TextChanged/CM_TEXTCHANGED. | Same name, different storage: dropping a TTyDivider in the designer sets Text to the component name and leaves Caption empty (TDividerBevel shows its name), and any generic/RTTI or LCL path that writes Text updates a str | SMALL |
| **成立** | `Orientation: TTrackBarOrientation` | 属性 | trHorizontal/trVertical (default trHorizontal). A vertical divider swaps the bevel axis and draws the caption rotated 900, and ShouldAutoAdjust flips which axis auto-sizes. | There is no vertical section divider: a two-column dialog or side-by-side panel pair cannot get a labelled vertical rule, and a ported .lfm with Orientation = trVertical fails to load. | MEDIUM |
| **成立** | `Style: TGrabStyle` | 属性 | Which decoration the rule is drawn with: gsSimple (default), gsDouble (two rules), gsHorLines / gsVerLines (repeating shadow+highlight line pairs), gsGripper (the themed splitter gripper) and gsButton | Five of six divider looks are unavailable, including the gripper and button faces used as drag handles/section headers; a ported Style = gsGripper both fails to load and has no visual equivalent. | MEDIUM |
| **成立** | `AutoSize (default True) + CalculatePreferredSize + ShouldAutoAdjust` | 属性 | TDividerBevel auto-sizes by default: CalculatePreferredSize returns max(caption height, bevel height) on the layout axis and 0 on the other, ShouldAutoAdjust restricts growth to the right axis, and Se | A divider whose caption uses a large font or a roomier skin clips its text and nothing corrects it (the 24px ctor guess is frozen at construction), and a ported .lfm carrying AutoSize = True fails to stream. | MEDIUM |
| ? | `BevelStyle, BevelWidth` | 属性 | BevelStyle (bsLowered/bsRaised, default bsLowered) picks a sunken or raised 3D rule; BevelWidth (default -1) sets its thickness, -1 meaning 'derive from the caption height' (max(3, textheight div 5)). | The divider is permanently a 1px flat hairline: no raised/lowered groove (the classic section-divider look) and no thicker rule to match a large-font heading; both .lfm properties fail to stream. | SMALL |
| ? | `CaptionSpacing` | 属性 | Pixels of clear space between the caption and the rule on each side, default 10. | The caption-to-rule gap cannot be changed by property or by skin, and a ported divider's 10px spacing silently becomes 6px, so a form's dividers no longer match the spacing rhythm they were designed for. | SMALL |
| ? | `Transparent` | 属性 | Boolean, default True. When False the control fills its client rect with Color before drawing the bevel and caption. | A divider over a photo/glass background cannot be given an opaque plate to keep its caption legible, and any theme rule that sets a background for TyDivider is ignored outright. | SMALL |

### `TTyGridColumn`  (对标 `TGridColumn`) — 8 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Layout: TTextLayout` | 属性 | Per-column VERTICAL alignment of cell text (tlTop / tlCenter / tlBottom). | On a tall, word-wrapped row, text cannot be top-aligned per column without writing an event handler - and never from the .lfm. | SMALL |
| **成立** | `ButtonStyle: TColumnButtonStyle` | 改名 | Declares the column's in-cell control: cbsAuto, cbsEllipsis, cbsNone, cbsPickList, cbsCheckboxColumn, cbsButton, cbsButtonColumn - note the two '...Column' variants mean the control shows in EVERY cel | A ported .lfm's ButtonStyle=cbsCheckboxColumn has to be translated into two of our properties, and there is no single property that describes 'what kind of column is this'. | SMALL |
| **成立** | `Color: TColor` | 属性 | Per-column cell background colour, streamed from the .lfm. | 'shade the read-only columns grey' - a design-time, one-property job in LCL - requires either an event handler or writing a colour into every cell of the column (and re-writing it on every row insert). | MEDIUM |
| **成立** | `Font: TFont` | 属性 | Per-column cell font, streamed from the .lfm. | A monospaced amount column or a bold key column must be produced by an event handler; nothing about it can be set in the designer. | MEDIUM |
| **成立** | `ValueChecked / ValueUnchecked` | 属性 | The exact strings this column's checkbox cells write and recognise for checked / unchecked (default '1' and '0'), so the grid matches the host's data vocabulary. | A grid whose data says 'Y'/'N' in one column and 'true'/'false' in another cannot use checkbox cells correctly - toggling silently writes our vocabulary and corrupts the host's data. | MEDIUM |
| ? | `DropDownRows: Longint` | 属性 | How many items the column's pick-list shows before it scrolls. | A pick list with 40 options either fills the screen or is fixed at whatever our code chose; the host cannot cap it. | SMALL |
| ? | `SizePriority: Integer` | 属性 | Per-column weight used when AutoFillColumns distributes spare width; 0 means 'never auto-size me'. | When the grid is resized, all stretchable columns must stretch equally; a layout like 'give the description column most of the slack' is not expressible. | SMALL |
| ? | `Expanded: Boolean` | 属性 | Whether an expandable (grouped/parent) column is showing its child columns. | Grouped column headers cannot be collapsed to hide their member columns. | SMALL |

### `TTyColorListBox`  (对标 `TColorListBox/TCustomColorListBox`) — 7 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `ColorRectWidth: Integer; ColorRectOffset: Integer` | 属性 | Width of the colour swatch and its inset from the row edge (LCL defaults 14 and 3), both DPI-adjusted. | Wide 'colour bar' rows or tight compact swatches are impossible, and this is exactly the kind of visual value that should be a theme token in this library — it is currently a literal 4 in shared code. | SMALL |
| **成立** | `Colors[Index]: TColor (read AND write); ColorNames[Index]: string` | 改名 | Indexed access to a row's colour — readable and writable — and to its display name. | `CLB.Colors[3] := clRed` — recolouring one row in place, e.g. after the user edits it — does not compile and has no equivalent; the whole palette must be rebuilt. Ported reads also need renaming to ColorAt. | SMALL |
| **成立** | `Selected: TColor (published, default clBlack)` | 语义 | The chosen colour, settable and streamable from the designer with a documented default. | A form's initial colour selection cannot be set at design time or streamed; it must be assigned in code at run time, and the default is implicit (our constructor happens to select index 0 = Black, tyControls.ColorListBox | SMALL |
| **成立** | `Style: TColorBoxStyle (cbStandardColors, cbExtendedColors, cbSystemColors, cbIncludeNone, cbIncludeDefault, cb` | 属性 | Declaratively composes which colour groups populate the list — the 16 standard colours, the 4 extended ones, the system (clBtnFace…) colours, a clNone row, a clDefault row, a user-picked custom row, p | A colour picker that must offer system colours, or a 'None'/'Default' entry, cannot be configured — the host has to ClearColors and re-add every colour with its own name strings. | MEDIUM |
| **成立** | `ColorDialog: TColorDialog (+ protected PickCustomColor, cbCustomColor row)` | 子对象 | Links a colour dialog to the list so the first row ('Custom…') opens the picker and the chosen colour becomes that row's value. | The standard 'pick any colour' affordance is missing even though the library ships its own colour dialog — each host must wire a button plus TySelectColor by hand. | MEDIUM |
| ? | `OnGetColors: TLBGetColorsEvent` | 事件 | Fires while the palette is being (re)built (cbCustomColors) so the host can append its own colours into the Items it is handed — and is re-fired whenever the list rebuilds. | Brand/theme palettes have to be pushed in imperatively after construction, and anything that would rebuild the list silently loses them. | SMALL |
| ? | `DefaultColorColor: TColor; NoneColorColor: TColor` | 属性 | The colour actually painted in the swatch for the clDefault and clNone rows (both default clBlack). | Once None/Default rows exist there is no way to say what they should look like; and today, code that sets these properties after a port simply fails to compile. | SMALL |

### `TTyProgressBar`  (对标 `TCustomProgressBar/TProgressBar`) — 8 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `BarShowText` | 属性 | Draws the progress as text inside the bar, formatted from a value/limits/percent template. | The extremely common '47%' readout inside the bar is unavailable; users must overlay a separate label and keep it in sync, even though three sibling controls in this same library already know how to render their own valu | MEDIUM |
| **成立** | `Style (pbstNormal / pbstMarquee)` | 改名 | Switches the bar between determinate (fill tracks Position) and marquee/indeterminate (a segment sweeps continuously, for unknown duration). | Porting break rather than a missing feature: `ProgressBar1.Style := pbstMarquee` (and any .lfm carrying Style=pbstMarquee) cannot be made to work -- the user has to delete the control and drop a TTyActivityBar in its pla | MEDIUM |
| **成立** | `Orientation (4 values vs 2)` | 类型 | LCL's TProgressBarOrientation has four fill directions: pbHorizontal (left->right), pbVertical (bottom->up), pbRightToLeft and pbTopDown. | Two of four documented fill directions are missing (a right-to-left bar for RTL locales, a top-down bar for a 'draining' meter), and even the two we have carry different enum identifiers, so `Orientation := pbVertical` d | MEDIUM |
| **成立** | `TabStop / TabOrder / OnEnter / OnExit` | 属性 | LCL's progress bar is a TWinControl, so it can take the focus and publishes the tab-order and focus events. | Low in practice -- almost nobody tabs to a progress bar -- but a ported .lfm carrying TabStop/TabOrder on a TProgressBar will not stream, and an accessibility pass that wants the bar in the focus order to announce progre | LARGE |
| ~~推翻~~ | `DragCursor / DragKind / DragMode / OnDragDrop / OnDragOver / OnEndDrag / OnStartDrag / OnStartDock` | 事件 | Drag-and-drop / docking participation for the progress bar. | **推翻:** Seven of the eight listed members are already published and inherited by TTyProgressBar via tyControls.Base.pas:136-143. Only OnStartDock is missing (and OnEndDock, which the claim did not list) — docking plumbing, which | SMALL |
| ~~推翻~~ | `StepIt / StepBy` | 方法 | StepIt advances Position by Step (clamped to Min/Max); StepBy(Delta) advances it by an ad-hoc delta. | **推翻:** Cosmetic naming gap. `PB.Position := PB.Position + N` is exact-equivalent to StepBy(N) because our setter clamps to Min/Max and fires OnChange only on a real change; note also that LCL's StepBy is itself implemented by f | SMALL |
| ? | `Step` | 属性 | The increment used by StepIt -- how far one 'tick' of progress advances (default 10). | The idiomatic loop `for i := 1 to n do begin Work; ProgressBar1.StepIt; end` has no equivalent; every caller must track and assign Position itself. | SMALL |
| ? | `Smooth` | 属性 | Chooses between a continuous fill (Smooth=True) and the classic segmented/chunked block fill (Smooth=False, the default). | The segmented look -- which is the LCL DEFAULT and what a classic/Win7-era skin is expected to reproduce -- cannot be selected, so a classic-theme demo cannot match the native control it is imitating. | MEDIUM |

### `TTyShape`  (对标 `TShape/TCustomShape`) — 6 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `OnShapeClick` | 事件 | Fires on click only when the pointer is inside the actual drawn shape, as opposed to OnClick which fires anywhere in the bounding rectangle. | On a diagram made of circles/triangles, a click in a shape's empty corner is reported as a hit on that shape; there is no 'clicked the ink' event, so hit accuracy has to be re-implemented per app. | SMALL |
| **成立** | `TShapeType values stRoundSquare, stSquaredDiamond, stTriangleLeft, stTriangleRight, stTriangleDown` | 属性 | Five of the fifteen TShapeType kinds: the square-locked rounded rectangle and diamond, and the three non-upward triangles. | A flowchart or state diagram needing a left/right/down-pointing triangle (flow-direction markers, play/back glyphs) has no equivalent, and those five .lfm enum values fail to load - 5 of 15 kinds unrepresentable. | SMALL |
| **成立** | `TShapeType values stStar / stStarDown` | 改名 | A 5-point star, point-up or point-down, as one of the Shape enum values. | Porting Shape = stStar means replacing the component class (and its whole .lfm entry) rather than editing a property; and a point-down star cannot be produced at all without adding rotation to TTyStarShape. | SMALL |
| **成立** | `stPolygon + OnShapePoints (TShapePointsEvent)` | 事件 | Shape=stPolygon asks the app for the vertices: the event hands back a TPointArray plus a Winding flag, so any polygon at all can be drawn (and the designer shows a dashed placeholder). | This is TShape's extensibility escape hatch - the answer to every shape the enum lacks (hexagons, callouts, custom marks). Without it the missing kinds above are permanently missing and the app must write its own TTyGrap | MEDIUM |
| ~~推翻~~ | `PtInShape + shape-precise hit testing (CM_MASKHITTEST / UpdateMask)` | 方法 | PtInShape(P) answers whether a client point is on the drawn shape (via a monochrome mask re-render); CMShapeHitTest makes the LCL/designer hit-test shape-precise, so clicks off the shape fall through  | **推翻:** CM_MASKHITTEST/UpdateMask buy exactly one thing: shape-precise SELECTION in the Lazarus form designer (designer.pp:501). At runtime a TShape swallows its whole bounding box just like TTyShape does. The only genuine runti | MEDIUM |
| ~~推翻~~ | `Pen and Brush (TPen / TBrush sub-objects)` | 子对象 | Per-instance stroke and fill objects: Pen.Color/Width/Style (psSolid, psDash, psDot, psDashDot)/Mode and Brush.Color/Style (bsClear, bsHorizontal, bsCross, bsDiagCross...)/Bitmap, each with an OnChang | **推翻:** The true residual is much narrower than 'Pen and Brush': the border-style keyword set is solid/none/outset/inset only (TyParseBorderStyleKw, tyControls.StyleModel.pas:512-518) - no dashed/dotted - and there is no hatch/b | MEDIUM |

### `TTyCheckGroup / TTyRadioGroup`  (对标 `TCustomCheckGroup / TCustomRadioGroup`) — 5 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Out-of-range index handling on Checked[] / ItemIndex (raise vs. silent)` | 语义 | LCL raises a descriptive exception (rsIndexOutOfBounds / rsIndexOutOfBoundsMinusOne naming the class, the bad index and the maximum) when an item index is out of range. | An off-by-one that Lazarus reported immediately as an exception at the guilty line now fails silently: Checked[n] reads False for an item that does not exist, a write is dropped, and ItemIndex := (stale index) quietly wi | SMALL |
| **成立** | `Child key-event forwarding (ItemKeyDown / ItemKeyUp / ItemKeyPress / ItemUTF8KeyPress → the group's OnKeyDown ` | 事件 | LCL hooks every child item's key events and re-raises them on the GROUP, so a handler on the group sees keys typed while focus is on any item — that is the only reason TRadioGroup/TCheckGroup can publ | A ported form with an OnKeyDown on the radio/check group (the usual place to catch Enter or a letter shortcut for the whole option block) silently never fires — the handler is still assignable, which is what makes it a s | MEDIUM |
| **成立** | `ColumnLayout: TColumnLayout (default clHorizontalThenVertical)` | 属性 | Chooses the fill order of the item grid: clHorizontalThenVertical fills across each row first, clVerticalThenHorizontal fills down each column first. | Two failures at once: the property is missing so ported code that set it will not compile, AND the default differs — a ported 6-item, 2-column group that read 1 2 / 3 4 / 5 6 in Lazarus now reads 1 4 / 2 5 / 3 6, silentl | MEDIUM |
| ~~推翻~~ | `function Rows: Integer` | 方法 | Reports how many rows the current item count occupies at the current Columns — the number host code needs to compute a sensible height for the box. | **推翻:** Cosmetic: `Rows := (Group.Count + Group.Columns - 1) div Group.Columns` reproduces it exactly, since our cell helpers compute rows with that same ceil. If content-sizing is the real want, the missing piece is an exposed/ | SMALL |
| ? | `AutoFill: Boolean (default True)` | 属性 | Switches the child grid between 'stretch the items to fill the box evenly' (True → ChildSizing.Enlarge* = crsHomogenousChildResize) and 'leave each item its natural size and just anchor them' (False → | A ported group that set AutoFill=False to keep short captions from being stretched across a wide box will not compile, and the stretched layout cannot be turned off. | MEDIUM |

### `TTyPageControl`  (对标 `TPageControl / TCustomTabControl`) — 6 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `TabIndex / PageIndex` | 改名 | LCL publishes TabIndex (index among VISIBLE tabs) and exposes PageIndex (index among ALL pages) as the selection; the two differ when a page has TabVisible=False. | Ported code doing PC.TabIndex := n or PC.PageIndex := n does not compile against TTyPageControl, and a .lfm containing TabIndex= fails to load; the visible-tab vs all-pages distinction does not exist at all. | SMALL |
| **成立** | `AddTabSheet: TTabSheet` | 改名 | Creates a new page owned by the pager and returns it (no caption argument). | PC.AddTabSheet does not compile after a port — a one-line fix per call site, but it is the single most common way pages are created in existing code. | SMALL |
| **成立** | `ActivePage` | 语义 | The active page object, PUBLISHED on TPageControl so the designer/.lfm can select the shown page by page name (TCustomTabControl also has ActivePage: String, the active page's caption). | A .lfm cannot say which page is active by name — only by numeric index, which silently points at the wrong page after pages are reordered or inserted. The object inspector shows no page picker. | SMALL |
| ~~推翻~~ | `Clear` | 方法 | Deletes and frees every page in one call. | **推翻:** Cosmetic naming gap. `while PageCount > 0 do RemovePage(0);` clears and frees every page today (source/tyControls.PageControl.pas:155-192). If added, Clear should be a thin wrapper over exactly that loop. | SMALL |
| ~~推翻~~ | `FindNextPage / SelectNextPage(GoForward[, CheckTabVisible])` | 方法 | Finds, or moves the selection to, the next/previous page, optionally skipping pages whose tab is hidden. | **推翻:** Reachable by another shape and partly inapplicable: TabIndex/ActivePageIndex is clamping, and our KeyDown already implements the wrap (Ctrl+Tab) and clamp (Ctrl+PageUp/Down) policies internally (tyControls.TabStrip.pas:1 | MEDIUM |
| ? | `DockSite / OnDockDrop / OnDockOver / OnStartDock / OnEndDock / OnUnDock / OnGetSiteInfo / OnGetDockCaption` | 事件 | TPageControl is a dock site: controls can be docked into it as pages, with the full dock notification set and a caption callback. | IDE-style dockable tabbed panels cannot be built on TTyPageControl, and a ported form that used it as a dock site loses that behaviour silently (the properties simply do not exist). | LARGE |

### `TTyTabSheet`  (对标 `TCustomPage / TTabSheet`) — 6 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Left / Top / Width / Height / TabOrder / Visible (stored False)` | 默认值 | LCL redeclares all of a page's bounds plus TabOrder and Visible as stored False, so a page never streams geometry or visibility — the pager owns both. | Every page writes Visible = False and stale bounds into the .lfm; the file is noisier, diffs churn on every designer visit, and a page's persisted Visible=False depends on Loaded/ShowOnlyPage running to undo it rather th | SMALL |
| **成立** | `PageControl: TPageControl` | 改名 | The pager this page belongs to, READ/WRITE — assigning it moves the page to another pager. | Sheet.PageControl does not compile after a port; callers must use Parent and hard-cast, losing the compile-time type check that the parent really is a pager. | SMALL |
| **成立** | `Caption` | 语义 | On LCL a page's Caption IS TControl.Caption (backed by Text via RealSetText, which also refreshes the tab), so Caption and Text are one value. | Sheet.Text and Sheet.Caption diverge: generic code that walks controls as TControl and reads Caption/Text (translation passes, accessibility, docking captions, LCL's own Text-based paths) sees an empty string, while the  | SMALL |
| **成立** | `OnShow / OnHide` | 事件 | Fire when this page becomes the active page and when it stops being it — the per-page activation hooks (lazy content loading, validation on leave). | Per-page code must be centralised into the pager's OnChange and dispatched with a case/if chain on the index; a page cannot own its own enter/leave logic, and ported OnShow/OnHide handlers are dropped silently by the .lf | MEDIUM |
| **成立** | `TabVisible: Boolean` | 属性 | Hides this page's TAB while the page itself stays in the collection (default True) — the standard way to build wizards and conditional steps. | A wizard cannot pre-create its steps and reveal them progressively — pages must be created and destroyed instead, losing child state — and any ported form with TabVisible=False fails to load. | MEDIUM |
| **成立** | `PageIndex: Integer (read/write)` | 属性 | A page's position in the pager, ASSIGNABLE — setting it moves the page (and its tab) to that position. | Pages can only be reordered by the user dragging tabs; code cannot move a page (or insert one at a position) at all, so ordering that depends on data — most recently used tabs, sorted documents — is impossible. | MEDIUM |

### `TTyGlyphButtonBase`  (对标 `TCustomBitBtn / TCustomSpeedButton`) — 4 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Spacing (Integer, default 4)` | 属性 | Per-control pixel gap between the glyph and the caption (-1 centres the pair). | One tight icon+label button next to one airy one is impossible: changing the gap retunes every glyph button in the application, so a designer who wants a 12px gap on a single hero button has to change the skin. | SMALL |
| **成立** | `Images (TCustomImageList)` | 类型 | The image source is any standard LCL TCustomImageList/TImageList — including the IDE's LCLGlyphs and multi-resolution lists, with change-link tracking so edits to the list repaint the button. | Same property name, incompatible type: `Btn.Images := ImageList1` fails to compile, and an app that already keeps its icons in a TImageList (shared with menus, tree views, third-party controls) must duplicate every icon  | MEDIUM |
| ? | `Margin (integer, default -1)` | 属性 | Inset of the glyph from the button edge; -1 means centre the glyph+caption block instead of pinning the glyph. | The glyph's distance from the edge is whatever the skin's padding says; a ported button that used Margin to nudge its icon inward (or Margin=-1 to keep the icon+text pair centred while the button is wide) lays out differ | SMALL |
| ? | `GlyphShowMode (TGlyphShowMode, default gsmApplication)` | 属性 | Whether the glyph is shown always, never, per the application setting (Application.ShowButtonGlyphs) or per the OS/desktop setting — the mechanism behind LCL's app-wide 'no icons on buttons' preferenc | An application that honours the desktop's 'don't show icons on buttons' setting (or offers it as a preference) cannot include ty buttons — theirs keep their icons while the native TBitBtns next to them drop them, so one  | SMALL |

### `TTySpeedButton`  (对标 `TCustomSpeedButton/TSpeedButton`) — 3 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `FindDownButton: TCustomSpeedButton` | 方法 | Public query returning the currently-pressed button of this button's group (nil when all are up). | Reading back which tool is selected in a radio group — the single most common thing you ask a speed-button group — requires hand-rolling a typed sibling scan in every app, and ported code calling FindDownButton does not  | SMALL |
| **成立** | `ShowCaption (Boolean, default true)` | 属性 | Hide the caption while keeping it set — an icon-only button that still has text for its hint, action and accelerator. | An icon-only toolbar button loses its Alt-accelerator and its action text along with its label; and a user-toggleable 'show text labels' toolbar option must clear and restore every Caption by hand instead of flipping one | SMALL |
| ? | `Flat (Boolean, default false)` | 属性 | Per-instance switch between a flat, borderless resting look (frame appears on hover/press) and full push-button chrome. | An app cannot mix flat and framed speed buttons on the same form (e.g. a flat toolbar plus one framed primary action): the resting frame is a theme-wide decision for the whole TySpeedButton key, so the only per-instance  | SMALL |

### `TTyColorButton`  (对标 `TColorButton`) — 5 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `ButtonColor setter -> OnColorChanged firing` | 语义 | LCL fires OnColorChanged on ANY colour change (programmatic assignment included), suppressed only while csLoading — so one handler keeps the app in sync however the colour was set. | Ported code that relies on the handler running when the app restores a saved colour (Btn.ButtonColor := Config.Color) silently skips its side effects — the preview pane or document does not update, and the difference is  | SMALL |
| **成立** | `inherited TCustomSpeedButton surface: Flat / GroupIndex / AllowAllUp / Down / Layout / Margin / Spacing / Tran` | 语义 | TColorButton IS a TCustomSpeedButton, so it publishes the whole speed-button surface: it can be flat, grouped as a radio, glyph-laid-out, spaced and transparent. | A ported colour button loses eight properties at once. Concretely, a palette row of grouped colour buttons (GroupIndex so exactly one swatch is selected) cannot be built, and the .lfm of any TColorButton that set Flat=Tr | MEDIUM |
| ~~推翻~~ | `ColorDialog (TColorDialog) + ShowColorDialog (protected virtual)` | 子对象 | A design-time reference to a configured TColorDialog component (its CustomColors list, Options, Title, OnShow/OnClose handlers), plus an overridable ShowColorDialog hook; with none assigned LCL create | **推翻:** TTyColorButton opens our own themed picker: Click calls TySelectColor from tyControls.Dialogs.Color (tyControls.ColorButton.pas:252-270) and publishes DialogCaption for its title, with OnColorChange firing only on an acc | MEDIUM |
| ? | `ButtonColorSize (Integer, default 16) / ButtonColorAutoSize (Boolean, default True)` | 属性 | Swatch sizing: with ButtonColorAutoSize the swatch expands to fill the button minus the caption/margins; turn it off and the swatch is a fixed ButtonColorSize square. | A row of colour buttons cannot show a consistent small square swatch beside varying captions — the swatch always tracks the button's height — and a 16x16 swatch on a tall button is unobtainable. | SMALL |
| ? | `BorderWidth (Integer, default 2)` | 属性 | Width of the frame drawn around the colour swatch, which also serves as the swatch's margin when Margin is -1. | The swatch outline is a fixed hairline; a light-yellow or white swatch on a light surface cannot be given a heavier frame to stay visible, and porting a TColorButton with BorderWidth=0 (no frame) or 4 changes its appeara | SMALL |

### `TTyControlBar`  (对标 `TCustomControlBar / TControlBar`) — 4 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `AutoDrag, AutoDock, DockSite, RowSnap (and the band drag they configure)` | 语义 | A TControlBar's defining behaviour: the user grabs a band's grabber and drags it to another row or position, bands snap to the row grid (RowSnap, default True), AutoDrag (default True) lets a band be  | The control looks like a ControlBar and lays out like one but cannot be manipulated: dragging a gripper does nothing, so the end user cannot rearrange bands, and no toolbar can be docked into it. Four published .lfm prop | LARGE |
| ~~推翻~~ | `TCtrlBand (band object) + HitTest, MouseToBandPos, StickControls, BeginUpdate, EndUpdate` | 子对象 | TCtrlBand is the run-time band object (BandRect, Left/Top/Right/Bottom, Height/Width, Control, ControlLeft/ControlTop/ControlWidth/ControlHeight, Visible/ControlVisible), reachable from the app via Hi | **推翻:** We expose no band OBJECT on purpose — bands are a layout result, not a persisted model — but: which band a child sits on is TTyControlBar.BandIndexOf(AControl) (tyControls.ControlBar.pas:76, backed by the per-child assig | MEDIUM |
| ? | `DrawingStyle, GradientDirection, GradientStartColor, GradientEndColor, Picture, BevelInner, BevelOuter, BevelW` | 属性 | The bar's own look: DrawingStyle dsNormal/dsGradient, the gradient's direction and start/end colours, a Picture tiled behind the bands, and the inherited panel bevels (TControlBar re-defaults BevelInn | A ported bar loses its gradient, its background picture and its recessed bevel frame, and the eight .lfm properties do not stream. The gradient and bevel can only be recovered by hand-writing CSS into StyleOverride per i | MEDIUM |
| ? | `OnBandDrag, OnBandInfo, OnBandMove, OnBandPaint, OnCanResize, OnConstrainedResize, OnPaint` | 事件 | The ControlBar's whole customization contract: OnBandDrag vetoes a band drag per control, OnBandInfo supplies a band's Insets/PreferredSize/RowCount so the app can size it, OnBandMove reports/adjusts  | Nothing about a band's size, drag permission or appearance can be customized from the application. Every ported form that assigned any of these seven handlers fails to compile, and the behaviour they implemented has to b | LARGE |

### `TTyColorBox`  (对标 `TColorBox / TCustomColorBox`) — 5 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Selected (published, default clBlack); Colors[Index]; ColorNames[Index]` | 语义 | Selected is TColorBox's headline PUBLISHED property — the chosen colour, settable in the Object Inspector and streamed to the .lfm, default clBlack. Colors[Index] and ColorNames[Index] are indexed rea | A designer cannot pick the initial colour in the Object Inspector and it is not saved in the .lfm — every colour box must be seeded in code. Ported code reading Colors[i] or ColorNames[i] does not compile (ColorAt / Item | SMALL |
| **成立** | `Style (TColorBoxStyle set)` | 语义 | On TColorBox, Style is a SET that composes the palette: cbStandardColors, cbExtendedColors, cbSystemColors (the default trio), cbIncludeNone, cbIncludeDefault, cbCustomColor (first row is a user-picka | Two failures at once. Ported code assigning a set to Style does not compile, and code that assigns our inherited Style compiles but does nothing. Users also cannot get system colours, clNone/clDefault rows or pretty name | LARGE |
| ? | `OnGetColors (TGetColorsEvent)` | 事件 | Published hook fired while the palette is being (re)built — the handler receives the Items list and appends application-specific colours (brand palette, recently used, colours found in the document).  | No event-based way to contribute colours, so a colour box cannot show a live 'colours used in this document' section — the app must remember to re-run ClearColors/AddColor itself at every point the palette should change. | SMALL |
| ? | `ColorRectWidth, ColorRectOffset, DefaultColorColor, NoneColorColor` | 属性 | Published swatch appearance: ColorRectWidth (default 14, DPI-adjusted) and ColorRectOffset (default 3) size and inset the colour rectangle drawn on each row; DefaultColorColor and NoneColorColor (both | Swatch size/inset cannot be changed at all — not per instance and not via the theme — so a colour box cannot be made to match a denser or wider design, and a ported ColorRectWidth=24 is dropped. And since clNone/clDefaul | SMALL |
| ? | `ColorDialog (+ PickCustomColor)` | 属性 | A published link to a TColorDialog component; with cbCustomColor in Style the first row opens THAT dialog (so the app controls its title, initial custom colours and options) and the chosen colour beco | You cannot point a colour box at your own configured colour dialog, and TTyColorBox offers no custom-colour row at all — the author must switch class to TTyColorComboBox and accept its hardcoded dialog and caption. A por | MEDIUM |

### `TTyCheckComboBox`  (对标 `TCheckComboBox / TCustomCheckCombo`) — 6 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `OnItemChange (TCheckItemChange = procedure(Sender: TObject; AIndex: Integer))` | 事件 | Published event telling the application WHICH item changed, fired on both user toggles and programmatic Checked[]/State[] writes. | A handler cannot tell which row the user ticked — it must diff the whole list on every OnChange. And because SetChecked fires nothing, a programmatic Checked[i] := True notifies no one, so a view bound to the combo silen | SMALL |
| **成立** | `CheckAll, Toggle, AddItem(AItem, AState, AEnabled), AssignItems, DeleteItem` | 方法 | The check combo's public mutation API: CheckAll(AState, AAllowGrayed, AAllowDisabled) bulk-sets every row honouring the grayed/disabled exclusions; Toggle(AIndex) flips one row and notifies; AddItem(A | Five ported calls break, and each substitute is more code with a correctness trap: a bulk 'check all' loop must skip nothing (no disabled/grayed notion), and Items.Add + Checked[Items.Count-1] is an index the caller has  | SMALL |
| **成立** | `AllowGrayed, State[AIndex]: TCheckBoxState` | 属性 | Tri-state checks. State[] reads/writes cbUnchecked / cbChecked / cbGrayed per item and fires OnItemChange; AllowGrayed (default False) lets the user cycle into the grayed state. Grayed is how 'partial | No third state anywhere in the check-combo path: a 'some children selected' row cannot be represented, and ported code reading or writing State[i] does not compile. The library already renders a grayed checkbox for TTyCh | MEDIUM |
| **成立** | `ItemEnabled[AIndex]: Boolean` | 属性 | Per-item enabled flag: a disabled row is drawn greyed and cannot be toggled by the user, while remaining visible and programmatically settable. CheckAll's AAllowDisabled parameter also honours it. | Rows cannot be individually disabled — the common 'this option is unavailable for the current licence, show it greyed' pattern is impossible; the app must delete the row or fight the user's clicks. Ported code touching I | MEDIUM |
| **成立** | `Objects[AIndex]: TObject (per-item user data)` | 语义 | LCL keeps each row's check state in a TCheckComboItemState object hung off Items.Objects[], and that state object carries a separate Data: TObject field, surfaced as the read/write Objects[AIndex] pro | Silent data corruption on port, not a compile error. Existing code that stores a payload in a check combo's Objects[] still compiles against our inherited TStringList — and every write clobbers the check flags (a non-nil | MEDIUM |
| ~~推翻~~ | `Count` | 改名 | A published read-only item count, so the count is visible to RTTI/design-time consumers as well as to code. | **推翻:** TTyCheckComboBox inherits `function Count: Integer` from TTyComboBox (tyControls.ComboBox.pas:133, body :424). Ported `Combo.Count` compiles as-is. The only residual difference is function-vs-property, which is invisible | SMALL |

### `TTyScrollBar`  (对标 `TCustomScrollBar/TScrollBar`) — 5 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Kind default (sbHorizontal vs sbVertical)` | 默认值 | The orientation a freshly created scroll bar starts with. | A .lfm ported from Lazarus that left Kind at LCL's default stores nothing, so the bar arrives here as VERTICAL while keeping the stored wide-and-short bounds -- a visibly wrong control. The reverse is true for any .lfm w | SMALL |
| **成立** | `LargeChange` | 属性 | The value step used for a page action (track click, PgUp/PgDn, scPageUp/scPageDown), independent of PageSize which only sizes the thumb. | You cannot have a proportional thumb and a page step that differ: setting PageSize=1 to get a small thumb also shrinks a page click to one line, and setting PageSize=50 to get a 50-unit page click fattens the thumb to ha | MEDIUM |
| **成立** | `BidiMode / ParentBidiMode` | 属性 | Right-to-left mode: in RTL the horizontal bar's coordinate system is mirrored, so Position increases leftward and the arrow/page codes are applied with an inverted sign. | An Arabic/Hebrew UI gets a scroll bar that scrolls the wrong way relative to the mirrored content, and a ported .lfm carrying BidiMode=bdRightToLeft will not even load. | LARGE |
| ~~推翻~~ | `DragCursor / DragKind / DragMode / OnDragDrop / OnDragOver / OnEndDrag / OnStartDrag` | 事件 | Drag-and-drop / docking participation for the scroll bar. | **推翻:** All seven members are present and published on TTyScrollBar via TTyCustomControl (tyControls.Base.pas:261-267). The stated impact was doubly wrong: even before that commit these were never a compile error, because TContr | SMALL |
| ~~推翻~~ | `SetParams(APosition, AMin, AMax[, APageSize])` | 方法 | Two overloads that set position, range and (optionally) page size atomically, so no intermediate clamp can move Position. | **推翻:** Reachable with no value loss by ordering the writes: Min := ...; Max := ...; PageSize := ...; Position := ... . SetMin/SetMax only clamp Position when it falls outside the NEW range (tyControls.ScrollBar.pas:344-358), an | MEDIUM |

### `TTyLabel`  (对标 `TCustomLabel/TLabel`) — 5 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Layout` | 默认值 | Vertical placement of the caption block inside the control (tlTop/tlCenter/tlBottom). | A .lfm converted from TLabel omits Layout because tlTop was the default, so after the port every non-autosized label's caption jumps to the vertical centre of its box - a silent, whole-form text shift with nothing in the | SMALL |
| **成立** | `OptimalFill (+ public AdjustFontForOptimalFill / CalcFittingFontHeight)` | 属性 | OptimalFill=True binary-searches the largest Font.Height at which the caption still fits the label's fixed box, re-running on every bounds change; the two public methods expose that search. | A caption that must fill a fixed banner/splash box cannot shrink-to-fit; the text is ellipsised/clipped instead. Loading an existing .lfm that carries OptimalFill = True raises an unknown-property read error. | MEDIUM |
| **成立** | `Font.Orientation (rotated caption)` | 语义 | TCustomLabel honours Font.Orientation: the caption is drawn at the requested angle and CalculatePreferredSize returns the rotated bounding box, so a vertical (900) label works out of the box. | Setting Font.Orientation := 900 on a TTyLabel (a chart axis caption, a narrow sidebar title) is accepted in the OI and silently does nothing - the text stays horizontal and gets clipped by the tall thin box the user size | MEDIUM |
| ? | `ShowAccelChar` | 属性 | Boolean, default True. When False the caption is drawn literally: '&' is a normal glyph and no letter is underlined/activated (DT_NOPREFIX). | A caption containing a real ampersand ('Research & Development', a Windows path with '&') silently loses the character and underlines the next letter, and there is no way to turn parsing off. Every ported .lfm line ShowA | SMALL |
| ? | `BorderStyle: TStaticBorderStyle` | 属性 | sbsNone / sbsSingle / sbsSunken - a per-instance frame around the static text. | A ported TStaticText with BorderStyle=sbsSunken loses its frame (unknown property on load) and can only get it back by writing a theme rule or a StyleOverride string - the single most common reason people used TStaticTex | SMALL |

### `TTyTreeView, TTyListView`  (对标 `TCustomTreeView, TCustomListView`) — 5 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `ScrollBars: TScrollStyle` | 属性 | Chooses which scrollbars exist (ssNone/ssHorizontal/ssVertical/ssBoth/ssAuto*). | A tree/list embedded in an outer scroller cannot suppress its own bars, and ssNone (fixed viewport) is unreachable. | SMALL |
| **成立** | `GetHitTestInfoAt: THitTests` | 改名 | Standard hit-test result set (htOnItem, htOnButton, htOnIcon, htOnLabel, htOnIndent, htNowhere, htOnRight...). | Ported hit-test code (`if htOnButton in Tree.GetHitTestInfoAt(X,Y)`) will not compile; the enums are single-valued, so 'on item AND on label' cannot be expressed. | SMALL |
| **成立** | `HideSelection` | 属性 | When the control loses focus the selection highlight is hidden (or kept, if False). | Two side-by-side lists both show a strong selection, so the user cannot tell which one has focus — the exact problem HideSelection exists to solve. | MEDIUM |
| **成立** | `ToolTips` | 属性 | Automatic per-item tooltip showing the full text when a caption is clipped by the column/viewport. | Long file names in a narrow column are unreadable — there is no way to reveal the full text on hover. | MEDIUM |
| ~~推翻~~ | `DragMode / DragKind / DragCursor / OnDragDrop / OnStartDrag / OnEndDrag` | 属性 | The standard LCL drag-and-drop surface: start a drag automatically, choose the drag cursor, accept drops, and be notified at start/end. | **推翻:** Both classes already expose the full LCL DnD surface via TTyCustomControl (tyControls.Base.pas:261-267). TTyTreeView additionally has its own node-level OnDragOver: TTyTreeDragOverEvent (:658) for internal node moves — a | MEDIUM |

### `TTyListItem`  (对标 `TListItem`) — 4 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `StateIndex + control StateImages/StateImagesWidth` | 属性 | A second, independent icon per row drawn from a state image list (status lights, overlay marks) beside the main icon. | Row status marks (the classic sync/error overlay column) cannot be drawn; only one image per row exists. | MEDIUM |
| ? | `SubItemImages[AIndex]` | 属性 | An icon per sub-item, so columns 1..N can each carry a small image. | With the built-in Items collection you cannot put an icon in a non-first column (e.g. a per-column status glyph). | SMALL |
| ? | `Position / Left / Top` | 属性 | Free placement of icons in icon view: read or set an item's pixel position (drag icons anywhere, save the arrangement). | lvsIcon is always an auto-arranged grid — a desktop-like view where the user drags icons to arbitrary spots is impossible. | SMALL |
| ? | `Focused / DropTarget / Selected (per-item states) + GetStates` | 属性 | Read/write an item's display state directly on the item: focused, drop-target highlight, selected. | A drag-over row cannot be highlighted, and item-centric code (`Item.Selected := True`) must be rewritten against the control's index API. | MEDIUM |

### `TTyMemo`  (对标 `TCustomMemo`) — 9 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `ScrollBars / WordWrap (defaults)` | 默认值 | TCustomMemo ships with ScrollBars = ssNone and WordWrap = True: a memo dropped on a form wraps its text and shows no bars. | Both defaults are inverted relative to TMemo, and because each side declares its own 'default', a .lfm streamed from an LCL form (which omits the properties it considers default) produces the OPPOSITE behaviour after por | SMALL |
| **成立** | `ClearSelection` | 语义 | LCL: public, DELETES the selected text. A memo inherits it unchanged from TCustomEdit. | Two failures at once: Memo1.ClearSelection does not compile (protected), and a developer who reaches it via a subclass gets the collapse-don't-delete behaviour, so a Delete/Clear command silently leaves the text in place | SMALL |
| **成立** | `ScrollBy(DeltaX, DeltaY)` | 语义 | TCustomMemo overrides TWinControl.ScrollBy to scroll the memo's TEXT VIEW by a pixel delta (ScrollBy_WS). | A ported Memo1.ScrollBy(0, -40) compiles and runs but does not scroll the text — instead it drags the memo's own scrollbar children out of position, i.e. it visibly corrupts the control rather than failing loudly. | SMALL |
| **成立** | `Alignment / CharCase` | 属性 | Alignment left/center/right-justifies every line of the memo; CharCase force-uppercases or lowercases typed and assigned text. | A centred title block or an upper-case-only note field cannot be built from TTyMemo, and .lfm/code ported from TMemo that sets either property fails to stream/compile. | MEDIUM |
| **成立** | `VertScrollBar / HorzScrollBar (TMemoScrollbar)` | 子对象 | Two public scrollbar sub-objects exposing Position, Range, Page, Increment, Smooth, Size and Visible, so code can read or drive the memo's scroll state (e.g. pin a log view to the bottom). | No public way to query or set the scroll position of a memo: 'scroll to bottom after appending', 'restore the previous scroll offset', or reading Range/Page for a custom indicator are all impossible from outside the clas | MEDIUM |
| **成立** | `SelStart / SelLength (line-break units)` | 语义 | On an LCL memo the flat offsets index the same string Text returns — Lines.Text, whose separators are LineEnding (two characters, CR+LF, on Windows). | Any ported code that computes a flat offset from the text itself (Pos(...)-1, Length of a prefix, a saved caret offset) lands one character earlier per preceding line on Windows: the caret/selection drifts further off th | MEDIUM |
| **成立** | `CaretPos (line/column)` | 类型 | Caret position as a TPoint on a multi-line control: X = column, Y = line — the natural addressing for a memo (status bar 'Ln 12, Col 4', jump-to-line, error highlighting). | Same name, incompatible type, and the information a memo user actually wants (line and column) is not reachable at all from outside the class — every 'Ln/Col' indicator or go-to-line feature has to subclass to get at the | MEDIUM |
| ~~推翻~~ | `OnMouseWheelHorz / OnMouseWheelLeft / OnMouseWheelRight` | 事件 | Horizontal wheel / tilt-wheel notifications, which is how a non-wrapping memo is scrolled sideways on a trackpad or tilt wheel. | **推翻:** OnMouseWheelHorz/Left/Right are already published on both base classes (tyControls.Base.pas:149-151 and :272-274, with a comment naming exactly the non-wrapping-memo case), so TTyMemo has them. The LCL implements the dis | SMALL |
| ~~推翻~~ | `Append` | 方法 | Public convenience method: appends one line to the end of the text (Lines.Add). | **推翻:** Append exists and is public: tyControls.Memo.pas:480 'procedure Append(const AValue: string);', implemented at :1354 as FLines.Add(AValue) -- identical to LCL's custommemo.inc:39-42. No gap. | SMALL |

### `TTyCheckBox / TTyRadioButton`  (对标 `TCustomCheckBox (published on TCheckBox, TRadioButton, TToggleBox)`) — 4 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Alignment: TLeftRight (default taRightJustify)` | 属性 | Chooses which side of the caption the check/radio indicator sits on. taLeftJustify sets BS_RIGHTBUTTON, i.e. the indicator is drawn to the RIGHT of the text; the default taRightJustify is the normal i | A form ported from Lazarus that set Alignment=taLeftJustify (a common look for right-hand-side option lists, and the standard order in RTL locales) will not compile against TTyCheckBox/TTyRadioButton, and there is no way | SMALL |
| **成立** | `AutoSize default True` | 默认值 | Whether the control sizes itself to its caption out of the box. | A .lfm streamed from Lazarus carries no AutoSize line when it is True (that being the declared default there); loaded here it silently becomes False, so a checkbox whose caption is longer than the designed width (a trans | SMALL |
| **成立** | `GetActionLinkClass → TButtonActionLink (Action.Checked ⇄ Checked linkage)` | 方法 | Two-way binding between a linked TAction's Checked and the control's Checked/State: assigning Action checks the box, clicking the box updates the action (and, in LCL, TAction.Grayed follows cbGrayed). | A ported form that drove a checkbox from a TAction (the standard way to keep a menu item, a toolbar toggle and a checkbox in sync) silently loses the sync: the checkbox no longer reflects Action.Checked and clicking it n | MEDIUM |
| ? | `ShortCut / ShortCutKey2: TShortcut (public, read-only)` | 属性 | Exposes the accelerator LCL derived from the '&' in the caption, so host code (a keyboard-shortcut cheat-sheet, a help overlay, an automated test) can read what key activates this control. | Code that enumerated controls to build a shortcut list, or asserted on the parsed accelerator in a test, has nothing to read here and must re-parse Caption itself. | SMALL |

### `TTyGroupBox (and its descendants)`  (对标 `TGroupBox / TRadioGroup / TCheckGroup`) — 2 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ~~推翻~~ | `ChildSizing: TControlChildSizing (whole sub-object)` | 子对象 | LCL's per-container child layout engine: Layout (cclLeftToRightThenTopToBottom / cclTopToBottomThenLeftToRight), ControlsPerLine, LeftRightSpacing / TopBottomSpacing, HorizontalSpacing / VerticalSpaci | **推翻:** ChildSizing is declared on TWinControl (C:/lazarus/lcl/controls.pp:2329, public) and its layout engine lives in TWinControl's align code, so TTyGroupBox (= TTyCustomControl -> TCustomControl -> TWinControl) already has a | LARGE |
| ? | `ClientWidth / ClientHeight (published)` | 属性 | Sets/streams the size of the CLIENT area rather than the outer bounds — on a group box the two differ by the caption band and the frame, so it is the natural way to say 'I need this much room inside'. | A .lfm ported from Lazarus that pinned ClientHeight/ClientWidth on a group box loses those lines on load, and a designer user cannot type a client size in the OI — they have to add the frame/caption inset by hand. | SMALL |

### `TTyRadioGroup`  (对标 `TCustomRadioGroup`) — 7 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `OnItemEnter / OnItemExit: TNotifyEvent` | 事件 | Fire when focus enters/leaves an individual radio item, with Sender = that item — the hook for per-option help text, a status-bar hint, or a preview that follows the keyboard. | A ported dialog that showed a description for whichever option the keyboard was on goes dead — and there is no accessor for the children either (no Buttons[]), so it cannot be rebuilt from outside the class. | SMALL |
| **成立** | `Buttons[Index]: TRadioButton` | 属性 | Hands out the hosted child radio button by index. | There is no way to reach an individual option — to disable one choice, retint it, attach a hint, or assert on it in a test — short of walking Controls[] and type-casting, which also picks up nothing useful because the ch | SMALL |
| **成立** | `OnClick (redeclared: fires on ItemIndex change, not on a mouse click)` | 语义 | TCustomRadioGroup shadows TControl.OnClick with its own FOnClick and fires it whenever the selection changes — Delphi compatibility, so OnClick and OnSelectionChanged are two names for the same notifi | Same property name, opposite trigger: a ported handler written for 'the selection changed' now runs when the user clicks the group's frame or caption instead — and never runs when the selection changes by keyboard. It co | SMALL |
| **成立** | `ItemIndex — programmatic write fires OnClick + OnSelectionChanged in LCL, silent here` | 语义 | In LCL, setting ItemIndex from code notifies exactly as a user click does (explicitly, for Delphi compatibility and for issue #15989 even with no handle allocated). | A ported form that relied on 'set ItemIndex, let the OnClick/OnSelectionChanged handler update the dependent UI' now sets the radio silently and leaves the rest of the form stale — the initial-state case (FormCreate assi | SMALL |
| **成立** | `UpdateTabStops — the group is ONE tab stop (only the checked child has TabStop)` | 语义 | LCL keeps TabStop True on the selected radio and False on all the others, so Tab enters the group once, lands on the current selection, and arrows move within it. | Tab traversal of a ported dialog gets much longer — a 6-item group adds 6 stops instead of 1 — and, combined with the missing arrow navigation, the platform-standard 'one stop per group, arrows inside' behaviour is unrea | SMALL |
| **成立** | `Arrow-key navigation between items (ItemKeyDown / MoveSelection)` | 方法 | Left/Right/Up/Down move the selection to the neighbouring item, honouring the column layout, wrapping at the ends and skipping hidden/disabled items, then focusing the newly selected radio. This is th | Keyboard-only users cannot move within a ported radio group: arrows do nothing, so the only way to change the option is Tab-to-each-item plus Space — which also means the selection changes as they traverse. | MEDIUM |
| ~~推翻~~ | `function CanModify: Boolean (public virtual)` | 方法 | The 'may the user change the selection?' hook — always True in the base, overridden by descendants (this is the seam TDBRadioGroup and read-only variants use) and callable by host code before offering | **推翻:** extctrls.pp:768 does declare `function CanModify: boolean; virtual;` and radiogroup.inc:493-496 returns True — but grep of radiogroup.inc shows those are the ONLY occurrences: LCL never consults CanModify anywhere in its | SMALL |

### `TTyPageControl / TTyTabSheet`  (对标 `TCustomTabControl / TCustomPage / TTabSheet`) — 4 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `BiDiMode / ParentBiDiMode` | 属性 | Right-to-left layout and reading order for the control and its children. | No Arabic/Hebrew tab layout: tabs, close buttons and overflow arrows stay left-to-right regardless of locale. The concept has a real themed equivalent (mirrored layout) that the painter would have to grow. | LARGE |
| ~~推翻~~ | `DragMode / DragKind / DragCursor / OnDragDrop / OnDragOver / OnStartDrag / OnEndDrag` | 事件 | LCL's drag-and-drop surface, published on both the pager and each page — lets the app accept drops on a tab or a page and start drags from them. | **推翻:** Drag-and-drop is already published on both TTyPageControl and TTyTabSheet via the shared base classes (tyControls.Base.pas:138-144 / :261-267); it was landed in commit 425f56c ('the drag surface'). Nothing is missing. Th | MEDIUM |
| ~~推翻~~ | `TabToPageIndex / PageToTabIndex / VisibleIndex / TTabSheet.TabIndex` | 方法 | Maps between the visible-tab index space and the all-pages index space, and lets a page report its own position in each (VisibleIndex, TabSheet.TabIndex). | **推翻:** This is not an independent gap: it is 100% derivative of the missing TabVisible/hidden-tab feature. If TabVisible is ever added, the mapping pair becomes real work; until then the only defensible micro-addition is a read | MEDIUM |
| ? | `AutoSize / BorderWidth / ChildSizing` | 属性 | TWinControl layout properties LCL publishes on the pager and the page: size to content (AutoSize), an inner margin inside the page (BorderWidth), and the child auto-layout collection (ChildSizing). | A page cannot inset its children with one property (every child needs its own BorderSpacing) and cannot use LCL's ChildSizing auto-layout; a pager cannot size itself to its largest page. | MEDIUM |

### `TTyButton (all six button classes)`  (对标 `TCustomSpeedButton/TSpeedButton`) — 2 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Alignment (TAlignment, default taCenter)` | 属性 | Horizontal alignment of the caption inside the button — taLeftJustify / taRightJustify / taCenter. | Left-aligned command buttons — the standard look for a vertical navigation rail or a ribbon's file-menu column, where icon+label must line up down the left edge — cannot be built; every caption is force-centred. | SMALL |
| ? | `ShowAccelChar (Boolean, default true)` | 属性 | Turn '&' mnemonic processing off so the caption is rendered literally. | A caption that legitimately contains an ampersand ('AT&T', 'Save & Close', or any string coming from data) silently loses the character and acquires a stray accelerator; the fix requires escaping every value at every ass | SMALL |

### `TTyCoolBar`  (对标 `TCustomCoolBar`) — 4 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `ShowText` | 默认值 | Draws each band's Text caption beside its grip and reserves layout room for it. | Inverted default and inverted streaming. A ported .lfm that set band captions and relied on LCL's ShowText=True streams nothing for the property, so all the band captions silently disappear and the bands also pack tighte | SMALL |
| **成立** | `FixedSize (bar-level), FixedOrder` | 属性 | FixedSize on the BAR makes every band the same height and suppresses band resizing bar-wide; FixedOrder forbids dragging bands into a different order (they may still move between rows). | Locking a whole bar takes one assignment per band instead of one on the bar, and FixedOrder=True in a ported .lfm is dropped. The deeper issue is that our bands cannot be reordered within a row in the first place, so a u | MEDIUM |
| ~~推翻~~ | `AutosizeBands, MouseToBandPos, EndUpdate, TCoolBands.FindBandIndex` | 方法 | AutosizeBands shrinks every band to its content in one call; MouseToBandPos(X, Y; out ABand: Integer; out AGrabber: Boolean) is the public hit-test telling the app which band index is under a point an | **推翻:** FindBandIndex: TTyCoolBands.FindBand(AControl) exists (tyControls.CoolBar.pas) and TTyCoolBand is a TCollectionItem, so FindBand(Ctl).Index is the index. Batching: TTyCoolBands descends from TOwnedCollection/TCollection, | MEDIUM |
| ? | `GrabStyle` | 属性 | Chooses how the grab handle is drawn: gsSimple, gsDouble (the default), gsHorLines, gsVerLines, gsGripper, gsButton. | A ported bar's GrabStyle is dropped and every grip looks the same. gsButton in particular (a raised button-like grab) is a visibly different affordance that cannot be reproduced, not even via the theme. | MEDIUM |

### `TTyComboBoxEx`  (对标 `TComboBoxEx / TCustomComboBoxEx`) — 4 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `AutoCompleteOptions, StyleEx` | 属性 | Two published option sets specific to the Ex combo. AutoCompleteOptions (default [acoAutoAppend]) selects the shell-style completion behaviour: acoAutoSuggest, acoAutoAppend, acoSearch, acoFilterPrefi | Two published sets are missing, so a ported form does not load. Concretely: no way to say 'do not draw the icon in the closed field' (csExNoEditImage) or to make matching case-sensitive, and no control over completion be | SMALL |
| **成立** | `Add (2 overloads), Insert, Delete, DeleteSelected, AssignItemsEx (2 overloads); AddItem signature` | 方法 | The Ex combo's item-mutation API, all image-aware: Add returns a new index or appends (ACaption, AIndent, AImgIdx, AOverlayImgIdx, ASelectedImgIdx); Insert does the same at a position; Delete(AIndex)  | Only appending is supported. Inserting an item with an image, deleting the selected item, or bulk-assigning items requires hand-writing the Objects[] +1 encoding — and if the caller gets it wrong the image silently shift | MEDIUM |
| **成立** | `Images (TCustomImageList vs TTyVirtualImageList), ImagesWidth` | 类型 | Images is typed TCustomImageList — any LCL TImageList, TDragImageList or shared IDE image list can be assigned. ImagesWidth (default 0) selects the resolution to draw from a multi-resolution image lis | An existing TImageList cannot be assigned — `ComboEx.Images := ImageList1` does not compile, and the app must migrate its icons into a TTyImageCollection. A ported .lfm referencing an ImageList (or ImagesWidth) fails to  | MEDIUM |
| **成立** | `ItemsEx (TComboExItems collection of TComboExItem) — whole sub-object` | 子对象 | TComboBoxEx's defining feature: a published, design-time-editable COLLECTION replacing the flat string list. Each TComboExItem carries Caption, ImageIndex, OverlayImageIndex, SelectedImageIndex (a dif | There is no Object Inspector collection editor for items — every entry must be added in code via AddItem, and a ported .lfm streaming an ItemsEx block fails outright. Four per-item capabilities are simply unavailable: ov | LARGE |

### `TTyColumns`  (对标 `TGridColumns`) — 3 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `ColumnByTitle(const aTitle: string): TGridColumn` | 方法 | Find a column by its header caption. | Code that addresses columns by name - the normal way to keep a CSV importer or a report generator independent of column order - must write its own scan. | SMALL |
| **成立** | `Items[Index]: TGridColumn (default) and Add: TGridColumn` | 类型 | A typed default array property and a typed Add, so column code reads Columns[3].Width := 40 with no casting. | Every line of ported column code needs a hard cast, and Columns[i] (the default-array form) does not compile at all - a constant tax on the most-touched part of the API. | MEDIUM |
| ~~推翻~~ | `VisibleCount / VisibleIndex(Index) / RealIndex(Index) / HasIndex(Index)` | 方法 | Map between 'nth visible column' and 'nth collection item', count the visible ones, and bounds-check an index. | **推翻:** Convenience-only. Visibility lives in TTyColumn.Options (coVisible), and 'how many are visible' / 'the nth visible one' is a two-line loop over Items; TotalWidth already walks exactly that visible set, and ColumnByPositi | SMALL |

### `TTyValueRow`  (对标 `TItemProp (via TValueListEditor.ItemProps)`) — 3 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `PickList: TStrings / EditStyle: TEditStyle` | 改名 | PickList is the row's drop-down options as a TStrings; EditStyle chooses esSimple / esEllipsis / esPickList. | Ported code assigning a TStrings of options must be rewritten to build a newline-joined string; and the option list cannot be shared with any other TStrings consumer. | SMALL |
| ~~推翻~~ | `ItemProps[const AKeyOrIndex: Variant]: TItemProp` | 子对象 | A per-row property object addressable BY KEY OR INDEX, carrying EditMask, EditStyle, KeyDesc, PickList, MaxLength and ReadOnly - the row's editing contract, separate from its value. | **推翻:** TTyValueRow (tyControls.ValueListEditor.pas:19-46) already carries the row's editing contract on the row itself: ReadOnly, EditorKind (== TItemProp.EditStyle, plus typed kinds LCL does not have: vekBoolean/vekColor/vekFo | MEDIUM |
| ? | `EditMask / MaxLength / KeyDesc` | 属性 | Per-row input mask, maximum input length, and a human-readable description of the key (shown instead of the raw key). | A property inspector row that must accept a date, a phone number, or at most 8 characters cannot enforce it - the user types anything and validation happens (if at all) after the fact. | MEDIUM |

### `TTyCheckBox / TTyRadioButton / TTyGroupBox / TTyCheckGroup / TTyRadioGroup`  (对标 `TCheckBox / TRadioButton / TGroupBox / TCheckGroup / TRadioGroup`) — 2 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ~~推翻~~ | `DragMode, DragKind, DragCursor, OnStartDrag, OnDragOver, OnDragDrop, OnEndDrag` | 属性 | The LCL drag-and-drop / drag-docking surface every TControl implements: dmAutomatic starts a drag on mouse-down, and the four events let a target accept the payload. | **推翻:** The whole Drag*/OnDrag* surface is already published on both TTy base classes; `Chk.DragMode := dmAutomatic` compiles and streams. The claim's cited line numbers (tyControls.Base.pas:196-246) predate the change. | SMALL |
| ? | `BiDiMode / ParentBiDiMode (RTL mirroring)` | 属性 | Right-to-left layout: mirrors the control's content (indicator moves to the right of the caption, text aligns right, child grids fill right-to-left) for Arabic/Hebrew locales. | An app localised to an RTL language cannot mirror any control in this group; the whole family stays LTR (indicator left, caption left-aligned, columns filling left-to-right) while the surrounding native LCL controls flip | LARGE |

### `TTyToggleSwitch (closest counterpart)`  (对标 `TToggleBox`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ? | `State: TCheckBoxState / AllowGrayed (tri-state on the button-shaped checkbox)` | 属性 | TToggleBox is a checkbox drawn as a latching push button, and it keeps the full checkbox contract: Checked, State (cbUnchecked/cbChecked/cbGrayed) and AllowGrayed. | A ported TToggleBox has to be hand-mapped to TTyToggleSwitch or TTyButton.Down, and any code that used its indeterminate state (State := cbGrayed for 'mixed', the usual 'some children selected' indicator) has nowhere to  | MEDIUM |

### `TTyGroupBox (and its descendants TTyCheckGroup, TTyRadioGroup)`  (对标 `TGroupBox / TRadioGroup / TCheckGroup`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ? | `AutoSize` | 属性 | Lets the frame size itself to the children it contains. | A group box cannot be made to hug its contents; every ported form that relied on AutoSize gets a fixed 185x105-ish frame that either clips its children or leaves a wide empty margin, and the property is missing from the  | MEDIUM |

### `TTyGroupBox`  (对标 `TGroupBox`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ? | `DockSite + OnDockDrop, OnDockOver, OnEndDock, OnGetSiteInfo, OnStartDock, OnUnDock` | 属性 | Makes the group box a docking host: other controls can be docked into it, with the six events driving accept/place/undock. | A ported form that used a group box as a dock target (a common shape for tool panels) will not compile against these names and cannot get docking back on this control. | MEDIUM |

### `TTyCheckGroup`  (对标 `TCustomCheckGroup`) — 4 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `CheckEnabled[Index: Integer]: Boolean` | 属性 | Enables/disables ONE item of the check group while the rest stay usable (and, in LCL, the flag is persisted with the checked state). | The standard 'this option is not available in your edition' pattern — one greyed line in an otherwise live check list — is impossible; the only lever is Enabled on the whole group. | SMALL |
| **成立** | `Buttons[Index]: TCheckBox (public) — ours is CheckBoxAt(), protected` | 改名 | Hands out the hosted child checkbox so host code can reach anything the group does not re-expose (its Font, Hint, Enabled, PopupMenu, an event hook). | Ported code written as CheckGroup1.Buttons[2].Enabled := False does not compile, and because our equivalent is protected it cannot even be renamed at the call site — the caller has to subclass the group. | SMALL |
| **成立** | `OnItemClick: TCheckGroupClicked — ours is OnItemChange: TCheckGroupItemEvent` | 改名 | Fires when the user toggles item Index. Identical signature (Sender: TObject; Index/AIndex: Integer), different event and type name. | Every ported handler assignment and every .lfm OnItemClick= line has to be renamed by hand, and the handler's declared type changes too; the compiler error points at the property name, not at the fact that the feature ex | SMALL |
| ~~推翻~~ | `DefineProperties / ReadData / WriteData — the binary 'Data' property that streams per-item Checked + CheckEnab` | 方法 | Persists which items are ticked (and which are individually enabled) into the .lfm, so a designer-set or programmatically-set check state survives save/load. | **推翻:** LCL's Data blob persists a checked/CheckEnabled state that in practice only ever exists at run time; the OI offers no way to create it. The only genuine porting residue is that a legacy .lfm literally carrying a `Data =  | MEDIUM |

### `TTyVirtualImageList / TTyGlyphImageList`  (对标 `TCustomImageList`) — 3 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Draw (parameter order)` | 类型 | Same method name, different signature: LCL is Draw(ACanvas, AX, AY, AIndex[, AEnabled]); ours is Draw(ACanvas, AIndex, AX, AY, ASizePx) — index and coordinates are swapped and a size argument is manda | Porting 'Images.Draw(C, X, Y, Idx)' to 'Draw(C, X, Y, Idx, 16)' compiles clean and silently draws image number X at position (Y, Idx) — a wrong-icon-in-a-wrong-place bug with no compiler help. | SMALL |
| ~~推翻~~ | `Draw(..., AEnabled: Boolean) / Draw(..., ADrawEffect: TGraphicsDrawEffect)` | 方法 | Draws the image with a visual effect — most importantly the greyed/faded 'disabled' rendering (AEnabled=False, gdeDisabled), also gdeHighlighted/gdeShadowed. | **推翻:** Our image lists are intentionally not TCustomImageList descendants and expose a colour-tint model (Draw(..., AColor) on TTyGlyphImageList; tinted rendering in TTyImageCollection) rather than LCL's TGraphicsDrawEffect enu | MEDIUM |
| ~~推翻~~ | `DrawOverlay / Overlay / HasOverlays` | 方法 | Overlay support: mark up to 15 images as overlay masks, then draw any image with one composited on top (the standard shortcut-arrow / share-badge / state-marker mechanism used by list and tree views). | **推翻:** Reachable by another shape: TTyImageCollection.AddBitmap(name, TBGRABitmap) / AddPicture composes an icon+badge once at runtime and the composite is then referenced by NAME (no separate on-disk icon set, which is what th | MEDIUM |

### `TTyCustomTabStrip / TTyPageControl`  (对标 `TCustomTabControl / TPageControl / TTabControl`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `TabPosition: TTabPosition` | 属性 | Puts the tab band on the top, bottom, left or right edge (tpTop/tpBottom/tpLeft/tpRight), default tpTop. | No vertical/sider tab layout and no bottom tabs at all — a very common design (left-hand settings tabs, bottom-docked output tabs) is unbuildable; a ported .lfm with TabPosition=tpLeft fails to load. | LARGE |

### `TTyPageControl / TTyCustomTabStrip`  (对标 `TCustomTabControl / TTabControl`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ~~推翻~~ | `IndexOf(APage) / CanChangePageIndex / GetMinimumTabWidth / GetMinimumTabHeight / DoCloseTabClicked / IndexOfTa` | 方法 | Public query/notify API: index of a given page object, whether the selection may change right now, the widget's minimum tab width/height, the public close-tab entry point, and the index of the tab wit | **推翻:** IndexOf(APage) is Pages[]/PageCount plus a two-line loop (and TTyPageControl.SetActivePage already does exactly that loop internally); GetMinimumTabWidth/Height are widgetset-supplied native minimums with no meaning for  | MEDIUM |

### `TTyCustomTabStrip / TTyTabSet`  (对标 `TTabControl / TTabControlStrings`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ~~推翻~~ | `BeginUpdate / EndUpdate / IsUpdating` | 方法 | Brackets a batch of tab insertions/deletions so the band is measured and repainted once, and reports whether an update is in flight. | **推翻:** TTyTabSet.Tabs is a TStrings (TStringList), so Tabs.BeginUpdate/EndUpdate already brackets a batch on the data side and suppresses the per-line OnChange → TabsChanged → Invalidate. No measurement is amortised because non | MEDIUM |

### `TTyGlyphButton / TTyGlyphButtonBase`  (对标 `TCustomBitBtn/TBitBtn`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Kind (TBitBtnKind) + BitBtnModalResults/BitBtnImages tables` | 属性 | One property turns a button into a stock dialog button: bkOK/bkCancel/bkHelp/bkYes/bkNo/bkClose/bkAbort/bkRetry/bkIgnore/bkAll/bkNoToAll/bkYesToAll each set the localized Caption, the stock glyph and  | Every ported dialog loses its one-line button setup: `Btn.Kind := bkCancel` does not compile, and the author must restate caption text (untranslated), ModalResult and Cancel on each button — three chances to disagree, an | MEDIUM |

### `TTyButton (and every descendant)`  (对标 `TButton/TBitBtn/TSpeedButton`) — 2 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `BiDiMode / ParentBiDiMode` | 属性 | Per-control right-to-left mode: mirrors the glyph/caption layout and switches text reading order (LCL also flips the glyph layout for you via BidiAdjustButtonLayout). | An Arabic/Hebrew form cannot be built: BiDiMode is settable from code (it is public on TControl) but our self-drawn buttons ignore it, so glyphs stay on the left of the caption and nothing mirrors, while the surrounding  | LARGE |
| ~~推翻~~ | `DragMode / DragKind / DragCursor + OnDragDrop / OnDragOver / OnStartDrag / OnEndDrag` | 属性 | The LCL drag-and-drop surface: dmAutomatic starts a drag on mouse-down, dkDock vs dkDrag chooses docking, DragCursor sets the feedback cursor, and the four events accept/reject/complete the drop. | **推翻:** DragMode / DragKind / DragCursor / OnDragOver / OnDragDrop / OnStartDrag / OnEndDrag are all published on both library base classes at tyControls.Base.pas:138-144 and :261-267, so they are visible in the Object Inspector | SMALL |

### `TTyGlyphButtonBase (TTyGlyphButton/TTySpeedButton/TTyGlyphContainerButton)`  (对标 `TCustomBitBtn / TCustomSpeedButton`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ? | `Glyph (TBitmap) + NumGlyphs` | 属性 | Assign an ordinary TBitmap as the button icon; NumGlyphs (1..5) splits that bitmap into an up/disabled/down/exclusive/hot strip so one image supplies every state. | A user with a .bmp/.png icon (or a runtime-generated bitmap) has no way to put it on a button: they must first build a TTyImageCollection or an icon font. Every ported .lfm that streams a Glyph.Data blob loses its icons  | MEDIUM |

### `TTySpeedButton / TTyGlyphButton`  (对标 `TCustomSpeedButton / TCustomBitBtn`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `DisabledImageIndex / HotImageIndex / PressedImageIndex / SelectedImageIndex` | 属性 | Per-state icons: a different image index for disabled, hover, pressed and exclusive-down, each defaulting to -1 (fall back to the normal image). | A toolbar cannot show a greyed icon when disabled or a coloured/filled variant on hover — only the theme's opacity/tint can change, so an icon set designed with explicit disabled and hover artwork (the normal case for ha | MEDIUM |

### `TTySpeedButton / TTyColorButton`  (对标 `TSpeedButton / TColorButton`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `OnPaint` | 事件 | A user paint hook fired from Paint, so an app can draw over/instead of the button's own rendering. | Assigning Button.OnPaint compiles (it is inherited) and then silently never fires — the worst failure mode, since there is no error to chase. Any ported code that decorated a speed button in OnPaint stops drawing with no | SMALL |

### `TTyGlyphButtonBase / TTyGlyphButton`  (对标 `TCustomBitBtn / TCustomSpeedButton`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ~~推翻~~ | `LoadGlyphFromResourceName / LoadGlyphFromLazarusResource / LoadGlyphFromStock / LoadGlyphFromResource` | 方法 | Four public one-call glyph loaders: from a named resource in any module instance, from a Lazarus resource, from the widgetset's themed stock icon by idButton, and the DPI-aware LCLGlyphs variant. | **推翻:** Resource-shipped icons are loadable today via TTyImageCollection.AddPicture/AddBitmap feeding the button's Images/ImageName. Absent is a one-call convenience wrapper and, deliberately, any access to widgetset stock icons | MEDIUM |

### `TTyGlyphButton / TTyButton`  (对标 `TCustomBitBtn/TBitBtn`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ? | `DefaultCaption (Boolean, default False)` | 属性 | Makes the Caption follow Kind automatically (and re-follow it on a language change) instead of holding a hand-typed string. | Dialog buttons cannot pick up the LCL's already-translated stock captions (rsmbOK/rsmbCancel/...); each app re-types and re-translates 'OK'/'Cancel'/'Yes'/'No' per form, and a runtime language switch leaves the old text  | SMALL |

### `TTyButton`  (对标 `TCustomButton/TButton`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ? | `Active / ShortCut / ShortCutKey2 (read-only) + the ActiveDefaultControl protocol` | 属性 | Active is True while this button currently OWNS the default role (LCL hands the role to a focused button, which is why ExecuteDefaultAction clicks when FActive or FDefault); ShortCut/ShortCutKey2 expo | Two things: ported code reading Btn.Active or Btn.ShortCut does not compile; and the behaviour behind Active is missing too — with focus on a non-default TTyButton, Enter still fires the form's Default button instead of  | SMALL |

### `TTyStatusBar`  (对标 `TStatusBar`) — 3 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `SimplePanel` | 默认值 | Switches the bar between one full-width SimpleText line (True) and the Panels collection (False). | Opposite out-of-the-box behaviour and an inverted streaming rule. A ported .lfm that set SimplePanel=False (a value LCL had to stream because its default is True) is fine, but one that relied on the True default — the co | SMALL |
| **成立** | `GetPanelIndexAt → PanelAtPos` | 改名 | Returns the index of the panel under a client-space point, or -1. | Straight porting break: `if StatusBar1.GetPanelIndexAt(X,Y) = 2 then` fails to compile even though the capability is right there under a different name. | SMALL |
| **成立** | `AutoHint, OnHint` | 事件 | The status bar as the application's hint line: with AutoHint=True the bar automatically shows Application.Hint text in panel 0 / SimpleText as the mouse moves over controls; OnHint lets the app interc | The single most common status-bar use — 'hover a toolbar button, read its hint down here' — is not available. Apps must wire Application.OnHint themselves and push text into SimpleText. | MEDIUM |

### `TTyStatusPanel`  (对标 `TStatusPanel`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ? | `Bevel` | 属性 | Per-panel frame: pbLowered (the default sunken well), pbRaised, or pbNone for a flat panel. | Individual panels cannot be flattened or raised; a ported bar that used pbNone on its stretch panel loses that and gets the separator rule anyway. | MEDIUM |

### `TTyStatusBar / TTyStatusPanel`  (对标 `TStatusBar / TStatusPanel`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `TStatusPanel.Style (psText/psOwnerDraw) + TStatusBar.OnDrawPanel` | 事件 | Owner-drawn panels: set a panel's Style to psOwnerDraw and the bar fires OnDrawPanel(StatusBar, Panel, Rect) so the app paints that cell itself (progress bars, icons, coloured indicators in a status c | A status cell can only ever be plain text. Every ported bar that drew a progress indicator, a lock icon or a coloured state dot in a panel loses that feature entirely, with no substitute. | MEDIUM |

### `TTyCoolBand`  (对标 `TCoolBand`) — 2 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `MinHeight, Height, Left, Top, Right, AutosizeWidth, InvalidateCoolBar` | 属性 | The band's vertical floor (MinHeight, default 25) and its read-only realized geometry — Height/Left/Top/Right — plus AutosizeWidth to shrink the band to exactly its content and InvalidateCoolBar to re | Bands cannot have individual heights or height floors — everything is forced to the bar's uniform BandHeight (tyControls.ControlBar.pas:310) — and code that read Band.Left/Top/Right/Height to position something relative  | MEDIUM |
| **成立** | `Break, Width, MinWidth (defaults)` | 默认值 | Break=True means this band starts a new row; Width is the band's assigned width (180 default); MinWidth is its resize floor (100 default). | Inverted and zeroed defaults change the layout of every ported CoolBar. LCL gives each band its own row unless told otherwise; ours packs them all onto row 1 unless every band's Break is set. A ported .lfm that omitted W | MEDIUM |

### `TTyCoolBand / TTyCoolBar`  (对标 `TCoolBand / TCustomCoolBar`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ? | `TCoolBand.Bitmap, Color, ParentColor, ParentBitmap, FixedBackground, ImageIndex + TCustomCoolBar.Bitmap, Image` | 属性 | Per-band decoration: a band can carry its own tiled background Bitmap or solid Color (or inherit the bar's via ParentBitmap/ParentColor), keep that background fixed while the band moves (FixedBackgrou | Rebar bands are all one flat themed colour with no icons. Any ported CoolBar that identified bands by colour or a small glyph loses that, and a ported .lfm's Band.Color/Band.ImageIndex/CoolBar.Bitmap will not stream. | MEDIUM |

### `TTyCoolBar / TTyCoolBand`  (对标 `TCustomCoolBar / TCoolBand`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `BandBorderStyle, TCoolBand.BorderStyle, HorizontalOnly, Themed, BandMaximize` | 属性 | BandBorderStyle (bsSingle default) and the per-band BorderStyle override give each band a frame; HorizontalOnly hides a band when the bar is vertical; Themed=True makes the bar paint with the OS theme | Bands cannot be individually framed, a vertical rebar shows bands that were meant to be horizontal-only, and four published .lfm properties are silently dropped on port. | MEDIUM |

### `TTyToolBar / TTyStatusBar / TTyCoolBar / TTyControlBar`  (对标 `TToolBar / TStatusBar / TCoolBar / TControlBar`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `AutoSize` | 属性 | Lets the bar size itself to its content through CalculatePreferredSize — a status bar takes its height from the font, a wrapping toolbar grows/shrinks by rows, a cool bar/control bar by band rows — an | A host cannot pin a toolbar/control bar height (the auto-grow always wins and overwrites a designed Height), and cannot get a status bar to follow the font — a larger UI font overflows its fixed 22px bar. AutoSize=False  | MEDIUM |

### `TTyStatusBar / TTyStatusPanel / TTyCoolBar / TTyControlBar`  (对标 `TStatusBar / TStatusPanel / TCoolBar / TControlBar`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ? | `BiDiMode, ParentBiDiMode` | 属性 | Right-to-left support. All four LCL bars publish BiDiMode, TStatusPanel adds its own BidiMode/ParentBiDiMode, and the layout code actually honours it — the cool bar keeps FRightToLeft and mirrors band | An Arabic/Hebrew UI gets left-to-right bars: status panels start at the left, toolbar buttons and rebar bands pack from the left with the grip on the wrong side. Ported .lfm BiDiMode settings are dropped silently, and th | LARGE |

### `TTyFilterComboBox`  (对标 `TFilterComboBox / TCustomFilterComboBox`) — 2 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `class procedure ConvertFilterToStrings -> TyFsParseFilter` | 改名 | A public CLASS method usable without an instance: parses an LCL filter string into a TStrings, with flags to clear the target, add the descriptions and/or add the patterns (AClearStrings, AAddDescript | Code calling TFilterComboBox.ConvertFilterToStrings(...) must be rewritten against a differently-shaped API (record array instead of filling a caller-supplied TStrings, and no 'append to an existing list' mode). Pure ren | SMALL |
| **成立** | `ShellListView` | 属性 | Published link to a TShellListView: selecting a filter row automatically pushes the new mask into that list view (and Notification nils the link if the view is freed). The whole point of the control — | The design-time wiring is gone: every filter combo needs a hand-written OnFilterChange/OnSelect handler that copies Mask into the list, and a ported .lfm with ShellListView = ShellListView1 fails to load. Both classes al | MEDIUM |

### `TTyPopupMenu`  (对标 `TPopupMenu`) — 10 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Alignment: TPopupAlignment` | 语义 | Whether the popup is left-aligned, right-aligned or centred on the invocation point (paLeft/paRight/paCenter). | Setting Alignment := paRight/paCenter has no effect -- the menu always drops down-right of the cursor. A right-aligned drop-down under a right-hand toolbar button spills off the intended edge (it only reflows when it hit | SMALL |
| **成立** | `TrackButton: TTrackButton` | 语义 | Which mouse button tracks and activates rows once the menu is up (tbRightButton default, tbLeftButton for press-and-drag right-button menus). | The published property is inert: a press-hold-right-button-drag-release context menu (tbLeftButton semantics) cannot be built, and the OI setting misleads. | SMALL |
| **成立** | `GlyphShowMode: TGlyphShowMode` | 语义 | Per-item control over whether the icon is drawn: gsmAlways / gsmNever / gsmApplication (Application.ShowMenuGlyphs) / gsmSystem (the OS setting). Default gsmApplication. | Items marked gsmNever still show their icon, and an app (or a user's OS preference) that turns menu glyphs off is ignored -- the themed menu always shows icons. | SMALL |
| **成立** | `Hint (menu item hint -> Application.Hint)` | 语义 | Highlighting a menu item publishes its Hint to Application.Hint, which is how a status-bar/long-hint description of the selected command appears. | Apps that describe the highlighted command in a status bar (the standard OnHint/Application.Hint pattern) go silent under themed menus -- item hints are dead data. | SMALL |
| **成立** | `ShowAlwaysCheckable` | 语义 | Draws the item as checkable even when unchecked -- i.e. an empty check box/frame is painted in the glyph slot so the user can see it is a toggle. | A toggle item reads as an ordinary command until the first time it is switched on, so users cannot tell which entries are checkable. The property is settable and inert. | SMALL |
| **成立** | `SubMenuImages / SubMenuImagesWidth` | 语义 | A per-submenu image list: items inside that submenu resolve their ImageIndex against SubMenuImages instead of the parent menu's Images (GetImageList checks it first). | A submenu with its own icon set (a Recent Files list with per-app icons, an insert-symbol cascade) shows indices resolved against the wrong list -- wrong pictures rather than none, which is worse than a blank slot. | SMALL |
| **成立** | `Bitmap: TBitmap (and HasBitmap / GetImageList)` | 属性 | A per-item glyph assigned directly as a bitmap, independent of any image list -- the oldest and most common way to put an icon on a Delphi/LCL menu item. | Items whose icon was assigned as Item.Bitmap (or streamed into a .lfm as an item Bitmap) render with an empty icon slot in every themed menu, with no error and no fallback. | MEDIUM |
| **成立** | `OwnerDraw / OnDrawItem / OnMeasureItem` | 语义 | The owner-draw protocol: with OwnerDraw True, each item's size comes from OnMeasureItem/DoMeasureItem and its pixels from OnDrawItem/DoDrawItem (canvas, rect, TOwnerDrawState). | Any app that owner-draws menu items (colour swatches, font previews, two-line entries, per-item bitmaps) gets the plain themed row instead and its handlers never fire. There is no themed substitute hook on the view eithe | MEDIUM |
| **成立** | `Images: TCustomImageList / ImagesWidth` | 类型 | The menu-wide icon source every item's ImageIndex resolves against (TMenuItem.GetImageList walks SubMenuImages then the parent menu's Images), plus the width hint for HiDPI resolution. | A TTyPopupMenu with the ordinary LCL Images list assigned (which the OI offers and which every ported project uses) shows no icons at all; you must switch the class to TTyImagesMenu and rebuild the image list as a TTyVir | MEDIUM |
| **成立** | `BidiMode / ParentBidiMode / IsRightToLeft` | 语义 | Right-to-left menus: the check/icon column moves to the right, shortcut text to the left, submenu arrows point left and cascades open leftward. | Arabic/Hebrew UIs get mirrored-language text in a left-to-right menu frame: glyph column on the wrong side, cascades opening off the reading direction. The published BidiMode gives no clue that it is inert. | LARGE |

### `TTyMenuBar`  (对标 `TMainMenu (TMenuItem.Enabled)`) — 7 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Enabled (top-level item)` | 语义 | A disabled top-level menu is drawn greyed out and cannot be opened by click or by its Alt mnemonic. | Disabling a whole top menu (the common 'no document open -> Edit menu off' pattern) has no visible effect and the dropdown still opens on click, so users reach commands the app has declared unavailable. | SMALL |
| **成立** | `top-level item with no children (Count = 0) never fires OnClick` | 语义 | In a native menu bar a childless top-level item is a command button: clicking it (or pressing its Alt mnemonic) fires its OnClick / its Action. | A top-level command such as 'Help' or 'About' with no submenu is completely dead in a TTyMenuBar -- clicking it does nothing at all, silently. This is not a missing option; it is a working LCL menu that stops working whe | SMALL |
| **成立** | `RightJustify` | 语义 | Pushes a top-level bar item to the right end of the bar (the classic right-aligned Help/Window menu). | A right-aligned top-level menu is impossible; items marked RightJustify sit in normal left-packed order, so ported menu bars lose their intended layout with no diagnostic. | SMALL |
| **成立** | `Merge / Unmerge / MergedItems` | 方法 | MDI/plugin menu merging: Merge(Menu) folds another TMainMenu's items into this one by GroupIndex, and the rendered menu is then driven by MergedItems (VisibleCount/VisibleItems), not by the raw Items  | Merged menus are invisible in a themed bar or popup: after MainMenu1.Merge(PluginMenu), the merged-in items simply do not appear (and replaced items are not hidden), so MDI/plugin menu architectures silently lose entries | MEDIUM |
| **成立** | `Images / ImagesWidth` | 属性 | The TMainMenu-wide icon list that every item's ImageIndex resolves against, so bar dropdowns show icons. | An application menu bar can never show item icons: assigning MainMenu1.Images (the only place the OI offers) is ignored, and unlike the context menu there is no TTyImagesMenu-style opt-in for the bar at all. | MEDIUM |
| ~~推翻~~ | `Items: TMenuItem` | 改名 | The root TMenuItem holding the bar's top-level items -- the object every add/remove/iterate call goes through. | **推翻:** Not a parity gap but an intentional composition split: TTyMenuBar is not, and does not claim to be, a drop-in TMainMenu subclass. An `Items` alias would be cosmetic sugar; nothing is currently unreachable. | SMALL |
| ? | `OnChange / MenuChanged (model-change notification)` | 事件 | TMainMenu.MenuChanged fires on every structural or caption change and notifies the host window (CM_MENUCHANGED) so the bar re-measures and repaints; OnChange is the published user hook. | Runtime menu edits do not reach the bar: renaming a top item, hiding one, or adding one leaves the painted cells stale (and an AutoSizeWidth bar the wrong width) until some unrelated repaint happens. Apps must call Inval | MEDIUM |

### `TTyDial, TTyLevelMeter, TTyMeter (also TTyGauge / TTyActivityIndicator / TTyAnalogClock — same bases)`  (对标 `TIndustrialBase`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ? | `AntiAliasingMode` | 属性 | Published TAntialiasingMode (amDontCare / amOn / amOff), default amDontCare; the one and only published member the whole industrial family adds. Its setter calls GraphicChanged, which Invalidates, so  | A .lfm/.dfm ported from an industrial control that carries AntiAliasingMode=amOff raises an unknown-property error on load, and on classic / pixel-exact skins there is no way to ask for hard-edged needles, segments or ti | MEDIUM |

### `TTyDial, TTyLevelMeter, TTyMeter (base: TTyGraphicControl / TTyCustomControl)`  (对标 `TArrow (TIndustrialBase family) / TGraphicControl`) — 5 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ~~推翻~~ | `OnDragDrop` | 事件 | TDragDropEvent fired when a dragged object is dropped on the control — the control acting as a drag TARGET (e.g. dropping a signal/channel onto a meter). | **推翻:** OnDragDrop is published library-wide at tyControls.Base.pas:142 and :265; all three instruments already expose it in the Object Inspector and stream it. | SMALL |
| ~~推翻~~ | `OnDragOver` | 事件 | TDragOverEvent fired while a drag passes over the control, where the handler sets Accept — the only way to give accept/reject feedback before a drop. | **推翻:** OnDragOver (the LCL TDragOverEvent passthrough) is published on both ty base classes at tyControls.Base.pas:141 / :264. | SMALL |
| ~~推翻~~ | `OnEndDrag` | 事件 | TEndDragEvent fired when a drag that STARTED on this control finishes (dropped or cancelled) — the cleanup half of the drag lifecycle. | **推翻:** OnEndDrag is published on both ty base classes at tyControls.Base.pas:144 / :267. | SMALL |
| ~~推翻~~ | `OnStartDrag` | 事件 | TStartDragEvent fired when a drag begins on the control, where the handler may substitute the TDragObject — the control acting as a drag SOURCE (e.g. dragging a knob's value onto a chart). | **推翻:** OnStartDrag is published on both ty base classes at tyControls.Base.pas:143 / :266. | SMALL |
| ? | `OnPaint` | 事件 | TNotifyEvent fired as part of the control's paint, letting user code draw extra ink on the control's Canvas (a red-line limit mark, a unit label, a custom scale) without subclassing. | Code ported from an LCL instrument that assigns Dial1.OnPaint := ... fails to compile, and a user who wants to overlay anything on a gauge/meter must descend a new class. Note the library's own trap: any such handler mus | SMALL |

### `TTyLabel, TTyDivider`  (对标 `TLabel / TStaticText / TDividerBevel`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ? | `BidiMode, ParentBidiMode (RTL text)` | 属性 | BidiMode flips alignment and enables RTL reading order for the caption; ParentBidiMode inherits it from the parent. | An Arabic/Hebrew UI gets left-aligned, LTR-ordered captions on every ty label and divider; there is no RTL story anywhere in this control family and no property to stream from a ported form. | LARGE |

### `TTyShape, TTyBevel, TTyArrow`  (对标 `TShape / TBevel / TArrow`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `OnPaint` | 事件 | TGraphicControl.Paint fires OnPaint after the control has drawn itself, so an app can annotate the graphic (a label inside the shape, tick marks, a highlight) without subclassing. | No supported way to draw on top of a shape/bevel/arrow from application code; users must subclass and override RenderTo, and ported forms lose their OnPaint handler wiring. | SMALL |

### `TTyLinkLabel`  (对标 `TCustomLabel/TLabel (nearest LCL label; no TLinkLabel in this LCL)`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ? | `WordWrap` | 属性 | Wraps the caption over several lines inside the control width instead of one clipped line. | A long link ('Terms of Service and Privacy Policy') is drawn on one line and clipped, and the accent underline clamps to the content width (source/tyControls.LinkLabel.pas:296-304) so the mark stops mid-sentence - the vi | MEDIUM |

### `TTyBevel`  (对标 `TBevel`) — 2 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Assign(Source: TPersistent)` | 方法 | Public override that copies Shape and Style from another TBevel, so a decoration can be cloned at runtime. | NewBevel.Assign(OldBevel) - the ordinary Pascal way to duplicate a component's settings when building UI in code - raises at runtime instead of copying Shape/Style. | SMALL |
| ~~推翻~~ | `TBevelShape / TBevelStyle enum identifiers (bsBox..bsSpacer, bsLowered/bsRaised)` | 改名 | The value sets behind Shape and Style; the property names match ours exactly, only the enum type names and every value identifier are renamed. | **推翻:** Nothing is missing: Shape/Style with identical seven-shape / two-style semantics and identical defaults exist on TTyBevel. Only the enum identifiers carry the library-wide t-prefix, a convention applied to every type in  | SMALL |

### `TTyArrow`  (对标 `TArrow`) — 3 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `ArrowType (ours: Direction)` | 改名 | Which way the arrow points; TArrowType = (atUp, atDown, atLeft, atRight) with default atLeft. | Two breaks in one member: 'ArrowType = atUp' in a ported .lfm fails to load, and a freshly dropped arrow points RIGHT where TArrow pointed LEFT - so a form relying on the default silently reverses direction. | SMALL |
| **成立** | `ArrowPointerAngle (and the triangle-vs-block-arrow geometry)` | 语义 | ArrowPointerAngle is the apex angle in degrees (default 60 = equilateral, clamped 20..160) of a 3-POINT TRIANGLE that TArrow scales to fit the client rect. | Same-named control, different picture: a ported TArrow turns from a bare triangle into a block arrow with a shaft, and the one dimension the user tuned (the apex angle) has no counterpart - HeadRatio is a length fraction | MEDIUM |
| ? | `ShadowType, ShadowColor` | 属性 | ShadowType = (stNone, stIn, stOut, stEtchedIn, stEtchedOut, stFilled), default stEtchedIn, draws a 3D edge along the arrow (or an offset drop triangle for stFilled); ShadowColor (default cl3DShadow) i | TArrow's DEFAULT look is etched (stEtchedIn), so every ported arrow loses its 3D edge and becomes flat, with no property and no theme token to restore it. | MEDIUM |

### `TTyGridColumn / TTyColumn`  (对标 `TGridColumn`) — 3 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `MinSize / MaxSize` | 改名 | The column's width bounds. | Rename break, plus a default difference: theirs default to 0 (unbounded) while ours default to 10 / 10000, so a ported column silently gains bounds. | SMALL |
| **成立** | `Visible: Boolean` | 改名 | Per-column visibility as its own published boolean. | Columns[i].Visible := False does not compile and does not appear as a checkbox in the column collection editor; the user has to find a set element instead. | SMALL |
| ~~推翻~~ | `Title: TGridColumnTitle` | 子对象 | A whole per-column title object with its own Alignment, Caption, Color, Font, ImageIndex, ImageLayout, Layout (vertical), MultiLine and PrefixOption - so the header cell can be styled independently of | **推翻:** Header caption/alignment/image ARE per-column here: TTyColumn.Text, TTyColumn.CaptionAlignment, TTyColumn.ImageIndex (tyControls.Columns.pas). What is genuinely missing is only the decorative remainder of TGridColumnTitl | LARGE |

### `TTyListItem / TTyListView`  (对标 `TListItem`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `DisplayRect(Code) / DisplayRectSubItem` | 方法 | The on-screen rect of a row, its icon, its label or its select-bounds — and the same for a sub-item cell. | You cannot position a popup, badge or custom editor over a row — the control knows every rect but hands none of them out. | MEDIUM |

### `TTyListItems`  (对标 `TListItems`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `FindCaption / FindData` | 方法 | Search the items for a caption (partial/whole, wrapping, from an index) or for a Data pointer. | 'Select the row for this record' needs a manual loop, even though the control already has a prefix matcher inside. | MEDIUM |

### `TTyColumn / TTyHeader`  (对标 `TListColumn / TCustomListView`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ? | `SortIndicator (per column) + AutoSortIndicator` | 属性 | Each column carries its own siNone/siAscending/siDescending arrow, optionally maintained automatically on sort. | A multi-key sort (or an indicator on a column that is not the active sort key) cannot be shown. | SMALL |

### `TTyListView / TTyListItems`  (对标 `TCustomListView`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ? | `OnCreateItemClass` | 事件 | Lets the app supply its own TListItem descendant so rows can carry typed fields. | Row payloads must go through the untyped Data pointer instead of a typed item subclass. | SMALL |

### `TTyHeaderControl (library-wide)`  (对标 `THeaderControl`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ? | `BiDiMode / ParentBiDiMode` | 属性 | Right-to-left layout: sections tile from the right, captions and sort glyphs mirror. | No RTL support anywhere in this control family: an Arabic/Hebrew UI gets a left-to-right header over a left-to-right list. | LARGE |

### `TTyRadioButton`  (对标 `TRadioButton`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `TabStop default False` | 默认值 | Whether every radio button in a set is its own Tab stop. LCL deliberately keeps radios OUT of the Tab cycle (the group is entered once, then arrow keys move within it). | On a ported form with five radio options, Tab now visits all five instead of one, so keyboard traversal of a dialog takes many more presses and no longer matches the platform convention. | SMALL |

### `TTyVirtualImageList / TTyImageCollection`  (对标 `TImageList`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Width / Height (vs DefaultSize) and StretchDraw` | 改名 | TImageList publishes Width and Height (both default 16) as the list's nominal image size — two independent axes, so non-square icons (e.g. 24x16 flags) are first class — and StretchDraw(Canvas, Index, | Non-square icons are padded into a transparent square and cannot be drawn to a non-square rect, so wide glyphs (flags, logos, 24x16 toolbar art) render smaller than intended with dead space; a porter looking for Width/He | SMALL |

### `TTyGlyphButtonBase.GlyphLayout`  (对标 `TCustomSpeedButton / TCustomBitBtn Layout`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Layout (TButtonLayout)` | 改名 | Published four-way glyph placement relative to the caption: blGlyphLeft (default), blGlyphRight, blGlyphTop, blGlyphBottom. | Two of the four layouts do not exist (icon to the RIGHT of the caption — the common 'more ▾' / trailing-icon pattern — and icon BELOW), and even the two we have cannot be chosen from the Object Inspector: the app must su | MEDIUM |

### `TTySpeedButton (TTyCustomControl-based)`  (对标 `TCustomSpeedButton (TGraphicControl-based)`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `class ancestry: graphic vs windowed control` | 语义 | TCustomSpeedButton is a TGraphicControl: no window handle, so it is genuinely transparent over the parent's painted background, cannot take focus, cannot clip sibling graphic controls, and costs no OS | A speed button on a gradient/image panel shows a rectangular patch of the resolved parent colour rather than the real backdrop, it clips any graphic-control sibling it overlaps (the known windowed-sibling clipping trap), | LARGE |

### `TTyColorButton.SelectedColor`  (对标 `TColorButton.ButtonColor`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `ButtonColor (TColor)` | 改名 | The colour the button displays and returns from the picker. | `Btn.ButtonColor := clRed` — the single line every TColorButton user writes — does not compile, and even after renaming, a TColor must be converted (TyColorFromLCL) or the value is misread as ARGB. A .lfm carrying Button | SMALL |

### `TTyColorButton.OnColorChange`  (对标 `TColorButton.OnColorChanged`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `OnColorChanged` | 改名 | Fired when the button's colour changes. | A one-character difference that breaks every ported handler assignment and every .lfm event binding, with a compiler error that reads like the event is missing altogether. | SMALL |

### `TTyGlyphButtonBase (Images/ImageName, GlyphSize)`  (对标 `TCustomSpeedButton / TCustomBitBtn`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `ImageIndex (TImageIndex, default -1) / ImageWidth (Integer, default 0)` | 改名 | ImageIndex selects the icon by integer index in the image list; ImageWidth picks which resolution of a multi-resolution list to draw at. | Icon assignment does not port: `Btn.ImageIndex := 3` must become a name lookup, and code that walks a toolbar assigning sequential indices from a shared TImageList has to be rewritten around string keys — with no compile | SMALL |

### `TTyGlyphButtonBase.HasGlyphSource`  (对标 `TCustomBitBtn.CanShowGlyph`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `CanShowGlyph(AWithShowMode: Boolean = False): Boolean` | 改名 | Public query: will this button actually paint a glyph right now (optionally also honouring GlyphShowMode)? | Layout code that asks a button whether it is currently showing an icon — to decide a toolbar's row height or to align a column of labels — must subclass to reach the protected twin. | SMALL |

### `TTySpeedButton / TTyButton`  (对标 `TCustomSpeedButton/TSpeedButton`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Transparent (Boolean, default true)` | 改名 | Per-instance switch: paint no background at all (the parent shows through) vs paint the button face. | The capability exists but under a name nobody will guess when porting: `Btn.Transparent := False` does not compile, and the replacement is a magic StyleClass string whose behaviour depends on the loaded skin defining a . | SMALL |

### `TTyColorButton.Click`  (对标 `TColorButton.Click`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Click / OnClick ordering relative to the colour dialog` | 语义 | LCL runs the inherited Click (firing OnClick) FIRST and opens the picker afterwards, so an OnClick handler observes the pre-dialog colour and can prepare state for it. | A ported OnClick handler that guarded the dialog (validating, stashing the previous colour for undo, or vetoing) now runs after the user has already picked, so its 'before' snapshot is the 'after' value — an undo step re | SMALL |

### `TTySpeedButton.AllowAllUp`  (对标 `TCustomSpeedButton.AllowAllUp`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `AllowAllUp setter -> UpdateExclusive` | 语义 | Changing AllowAllUp re-evaluates the whole group (UpdateExclusive) so the group's pressed/unpressed invariant is restored immediately and the affected buttons repaint. | Flipping AllowAllUp to False while the whole group happens to be up leaves the group in a state LCL forbids (no button down, yet no click can produce one via the AllowAllUp path), and setting it in code produces no repai | SMALL |

### `TTyStatusBar / TTyStatusPanels / TTyStatusPanel`  (对标 `TStatusBar / TStatusPanels / TStatusPanel`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ~~推翻~~ | `BeginUpdate, EndUpdate, InvalidatePanel, UpdatingStatusBar, SizeGripEnabled + TStatusPanel.StatusBar, GetDispl` | 方法 | Batching and back-navigation: BeginUpdate/EndUpdate coalesce many panel edits into one repaint, UpdatingStatusBar reports the lock, InvalidatePanel(i, parts) repaints one cell instead of the bar, Size | **推翻:** BeginUpdate/EndUpdate/InvalidatePanel/UpdatingStatusBar are the native-rebar handle-batching layer, not a general API: statusbar.inc:242-260 forwards to Panels.BeginUpdate purely so repeated UpdateHandleObject calls are  | MEDIUM |

### `TTyCoolBar / TTyControlBar`  (对标 `TCustomCoolBar`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `GrabWidth → GripperWidth; HorizontalSpacing / VerticalSpacing → BandSpacing` | 改名 | GrabWidth is the width of the grab handle strip; HorizontalSpacing and VerticalSpacing are the independent gaps between bands along a row and between rows. | Three properties fail to compile / fail to stream under their LCL names. Worse for the spacings: they are not just renamed but merged, so LCL's asymmetric default (5 horizontal, 3 vertical) is unreachable — asking for 5  | SMALL |

### `TTyToolBar (and TTyStatusBar / TTyCoolBar / TTyControlBar)`  (对标 `TToolBar (and TStatusBar / TCoolBar / TControlBar)`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ~~推翻~~ | `DragCursor, DragKind, DragMode, OnDragDrop, OnDragOver, OnStartDrag, OnEndDrag (+ DockSite, OnDockDrop, OnDock` | 属性 | LCL drag-and-drop and docking, published on all four bars: DragMode dmAutomatic starts a drag on mouse-down, DragKind dkDock turns the drag into a dock operation, and the OnDrag*/OnDock* events let th | **推翻:** All four bars inherit the drag set: TTyToolBar (tyControls.ToolBar.pas:22) and TTyStatusBar (tyControls.StatusBar.pas:36) descend from TTyCustomControl directly, TTyControlBar/TTyCoolBar via TTyPanel (tyControls.Panel.pa | MEDIUM |

### `TTyDial, TTyLevelMeter, TTyMeter (base: TTyGraphicControl / TTyCustomControl — affects every ty control)`  (对标 `TArrow (TIndustrialBase family) / TControl`) — 3 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ~~推翻~~ | `OnMouseWheelHorz` | 事件 | TMouseWheelEvent for HORIZONTAL wheel/trackpad input (WM_MOUSEHWHEEL, two-finger sideways swipe), with WheelDelta and a Handled flag. | **推翻:** OnMouseWheelHorz is published on both ty base classes (tyControls.Base.pas:149 / :272), so every ty control exposes it. Any remaining gap is per-control DoMouseWheelHorz handling, not the event. | SMALL |
| ~~推翻~~ | `OnMouseWheelLeft` | 事件 | TMouseWheelUpDownEvent — the pre-decoded 'wheel went left' half of horizontal wheel input, the sideways twin of OnMouseWheelUp. | **推翻:** OnMouseWheelLeft is published on both ty base classes at tyControls.Base.pas:150 / :273. | SMALL |
| ~~推翻~~ | `OnMouseWheelRight` | 事件 | TMouseWheelUpDownEvent — the 'wheel went right' half of horizontal wheel input. | **推翻:** OnMouseWheelRight is published on both ty base classes at tyControls.Base.pas:151 / :274. | SMALL |

### `TTyDial, TTyLevelMeter, TTyMeter (and every other ty instrument)`  (对标 `TArrow (TIndustrialBase family) / TControl`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ~~推翻~~ | `Color` | 改名 | The control's background colour, published on the concrete industrial control and settable in the OI or a .lfm. | **推翻:** Two factual corrections. (1) The kind is mis-filed as name-mismatch while the claim names no counterpart on our side — it is an absent-property claim. (2) Color is not unavailable in code: TControl declares it public, so | SMALL |

### `TTyGauge`  (对标 `TIndustrialBase (family contract; note TGauge itself is absent from this LCL — see coverage_note)`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `Caption / ControlStyle-csSetCaption` | 语义 | The industrial family removes csSetCaption in its constructor, so a family instrument NEVER acquires its Name as caption text and publishes no Caption at all (TArrow's published list has none) — an in | The OI shows Caption on a TTyGauge and typing into it changes nothing (a dead published property, the same class of bug as the recent ColorButton 'paint the Caption it has published all along' fix), while the auto-assign | SMALL |

### `TTyScrollPanel`  (对标 `TScrollBox/TScrollingWinControl`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `AutoScroll` | 语义 | On LCL, AutoScroll on a scrolling container means 'automatically show/hide scrollbars and recompute ranges'. On TTyScrollPanel the same identifier means something unrelated: the master switch for edge | A porter who sets ScrollPanel1.AutoScroll := False expecting the scrollbars to go away instead silently disables edge auto-pan while the bars keep appearing — same name, same type, same default, opposite subsystem. The c | SMALL |

### `TTyPaintPanel`  (对标 `TPaintBox`) — 3 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `GetControlClassDefaultSize (default drop size)` | 默认值 | The size a freshly dropped control gets from the palette. TPaintBox chooses a square 105x105 because a drawing surface has no intrinsic aspect. | A paint surface dropped from the palette arrives as a 185x41 letterbox strip, so the first thing a user must do is resize it; anyone previewing drawing code at the default size sees a clipped result. | SMALL |
| **成立** | `OnPaint` | 改名 | The single reason TPaintBox exists: a TNotifyEvent fired inside the paint pass with Canvas.Font/Brush already prepared, so the host draws with the ordinary TCanvas API. | An existing TPaintBox handler cannot be moved over: the parameter list differs, so every ported handler must be rewritten, and the familiar `OnPaint` name silently accepts an assignment that never fires (see the TTyPanel | SMALL |
| **成立** | `class ancestry (TGraphicControl vs TCustomControl)` | 语义 | TPaintBox is a GRAPHIC control: no window handle, it paints into its parent's DC, so it is transparent where it does not draw, can be layered over other controls, and never clips or occludes siblings. | TTyPaintPanel cannot be used the way TPaintBox commonly is — as a transparent annotation/overlay layer on top of another control — and being windowed it clips and occludes what sits under it (the windowed-sibling clippin | LARGE |

### `TTyLabel, TTyLinkLabel`  (对标 `TCustomLabel/TLabel`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `AutoSize` | 默认值 | AutoSize=True makes a label size itself to its caption; TCustomLabel turns it on in the constructor and re-declares the default as True. | Dropping a TTyLabel, or porting one from TLabel, gives a fixed box that clips the caption instead of growing with it; every label in a ported form needs AutoSize=True added by hand, and .lfm files omit the property preci | SMALL |

### `TTyLabel, TTyArrow, TTyDivider`  (对标 `TLabel / TStaticText / TArrow / TDividerBevel`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ~~推翻~~ | `Color (and TArrow.ArrowColor)` | 改名 | Color is the control's own background colour (painted when Transparent=False); TArrow.ArrowColor is the triangle's fill colour, default clBlack. | **推翻:** Colour on a ty control is set via StyleOverride (e.g. 'background: #f00;') or a StyleClass rule; Color/ArrowColor are intentionally absent because a themed self-drawn control must not carry a hard-coded colour. A .lfm po | SMALL |

### `TTyLabel, TTyShape, TTyArrow, TTyDivider (all TTyGraphicControl)`  (对标 `TLabel / TShape / TArrow / TDividerBevel`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ~~推翻~~ | `DragMode, DragKind, DragCursor, OnDragDrop, OnDragOver, OnStartDrag, OnEndDrag (+ TShape's OnStartDock/OnEndDo` | 属性 | The LCL drag-and-drop / docking surface: dmAutomatic starts a drag on mouse-down, and the events let the control be a drag source or drop target designed entirely in the OI. | **推翻:** The whole drag surface is already published on both base classes (tyControls.Base.pas:138-144, :261-267) as of commit 425f56c. Designer-authored drag-and-drop works today; only OnStartDock/OnEndDock (true docking) remain | MEDIUM |

### `TTyGraphicControl / TTyCustomControl (whole library)`  (对标 `TControl (published by TLabel, TStaticText, TShape, TArrow)`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ~~推翻~~ | `OnMouseWheelHorz, OnMouseWheelLeft, OnMouseWheelRight` | 事件 | Horizontal-wheel / tilt-wheel / trackpad side-scroll notifications, the horizontal twins of the vertical wheel events. | **推翻:** All three horizontal-wheel events are published library-wide (tyControls.Base.pas:149-151, :272-274). What is genuinely missing is any DoMouseWheelHorz override turning the notification into built-in sideways scrolling - | SMALL |

### `TTyDrawGrid`  (对标 `TCustomDrawGrid / TDrawGrid`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ~~推翻~~ | `Col, Row, Selection, Editor, EditorMode (on the draw-grid level)` | 属性 | LCL's TDrawGrid is a fully interactive grid: it has a cell cursor, a selection rectangle, an in-place editor and OnGetEditText/OnSetEditText, while still getting its content from the host. Only the st | **推翻:** The cursor/selection/editor layer lives on TTyStringGrid, a direct descendant of TTyDrawGrid, and costs nothing on a virtual host-fed grid because storage is sparse. Only which class in the chain carries it differs; noth | LARGE |

### `TTyTreeView, TTyListView, TTyHeaderControl`  (对标 `TTreeView, TListView, THeaderControl`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| ~~推翻~~ | `OnMouseWheelHorz / OnMouseWheelLeft / OnMouseWheelRight (horizontal wheel)` | 事件 | Horizontal wheel / trackpad-swipe scrolling and its events. | **推翻:** The three events are published on TTyCustomControl (tyControls.Base.pas:272-274) and so on all three controls. Still absent is a DoMouseWheelHorz override that scrolls the control itself (LCL TTreeView overrides it at co | MEDIUM |

### `TTyColumn (via TTyListView.Header)`  (对标 `TListColumn`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `AutoSize (per column)` | 改名 | A column that keeps itself sized to its content/caption automatically. | Columns do not re-fit when the data changes; AutoFitColumn must be called by hand after every refresh, and AutoWidthLastColumn has to be emulated via Header.AutoSizeIndex. | SMALL |

### `TTyListView / TTyColumn`  (对标 `TListColumn`) — 1 条

| 结论 | 成员 | 类型 | 那边做什么 | 用户因此做不到什么 / 推翻理由 | 成本 |
|---|---|---|---|---|---|
| **成立** | `ImageIndex (column header icon)` | 语义 | An icon in a column header, next to the caption. | Setting Header.Images and a column's ImageIndex looks like it should work and silently draws nothing — a built-but-unwired capability. | MEDIUM |

---

## 覆盖漏洞

- `industrial-gauges` 组三个配对里**两个没法比**:`TTyDial`/`TTyLevelMeter`/`TTyMeter` 在本机
  找不到 LCL 对应物,枚举 agent 没有编造、如实上报。这三个控件等于**没审**。
- 两处 brief 里给的 LCL 路径不存在,agent 自行改用了真实文件名
  (`customtrackbar.inc`→`trackbar.inc`、`customspeedbutton.inc`→`speedbutton.inc`)。
- 本库自有、LCL 无对应物的控件(Alert/Badge/Card/Cascader/Segmented/Steps/Tag/Transfer/
  Pagination/Popover/Rating/Sparkline 等约 40 个)**不在本次范围**内 —— 没有对齐基准。
