# 数据感知（DB）控件第一期 实现计划（#34）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or subagent-driven-development) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（项目约定，优先于子技能默认做法）**：测试先行；每个任务改代码 + 写测试并单独提交；任务之间只编 `tests/tytests.lpi` 跑本任务的 suite，Task 13 一次全量、集中变异、签收。中途不汇报、不问要不要提交。测试写「判据 + 必须变红的变异」，测试代码由实现者按判据写（不在计划里预写，见仓库记忆）。
>
> **谁来做**：标 **【主控执行】** 的步骤实现 agent 不做：编 `tycontrols.lpk` / `tycontrols_db.lpk` / `tycontrols_dt.lpk`、编 `examples/`、Lazarus 3.0 构建、GUI 冒烟与手点、推送。实现 agent 只编 `tests/tytests.lpi`。
>
> **不改的文件**：`Painter.pas`、`StyleModel.pas`、`TextMenu.pas`、`Base.pas`、`Component.pas`、`AdvanceChart.pas` 及 `AdvChart.*`。`CHANGELOG.md` 不改（发版时写）。核心控件单元只做 Task 2 列出的那几处「只加不改」的钩子。

**Goal:** GitHub #34 第一期——新包 `tycontrols_db.lpk` 提供 21 个数据感知控件（LCL 有的 13 个 + 本库独有的 8 个），绑 `TDataSource` / 字段即用，现有主题不改就能上样式。

**Architecture:** 每个 DB 控件拆成 `TTyCustomDBXxx = class(TTyCustomXxx)`（数据连接与全部实现）+ `TTyDBXxx = class(TTyCustomDBXxx)`（只发布）。数据连接直接用 LCL `DBCtrls` 单元的 `TFieldDataLink`、`TDBLookup`、`ChangeDataSource`（接口部分，3.0 与 4.4 相同），不移植。区分「用户改的」和「从字段装载的」靠每个控件里的**装载标记 + 装载值比较**：装载时置标记，任何变化通知只在「不在装载中且值与装载值不同」时才算用户编辑（进入编辑、标记修改）。核心控件里观察不到用户改动的四处补 protected virtual 汇集点。每个控件有自己的 typeKey，经 #14 的链回退到基础控件的键。

**Tech Stack:** FPC 3.2.2 / Lazarus 4.4 LCL（最低 Lazarus 3.0）、FCL-DB（`DB`、`BufDataset`）、LCL `DBCtrls`、BGRABitmap、fpcunit（`tests/tytests.lpi`）。

**工作树：** `D:/Projects/ty-db`，分支 `feat/db-controls`，起点 `main` @ ~~`a30a69f5`~~ `01c56a06`（已含全部 TTyCustomXxx 拆分、#14 typeKey 链；开工时 main 已带上 V10 的修复）。

---

## 范围（用户 2026-10-05 定）

| 组 | 控件（`TTyDB` + 名字） | 建在 | LCL 对应 |
|---|---|---|---|
| 文本 | Edit、MaskEdit、Memo、Text | `TTyCustomEdit`、`TTyCustomMaskEdit`、`TTyCustomMemo`、`TTyCustomLabel` | TDBEdit、（TDBEdit 的掩码）、TDBMemo、TDBText |
| 数值（本库独有） | NumericEdit、CurrencyEdit、SpinEdit、FloatSpinEdit | `TTyCustomNumericEdit`、`TTyCustomCurrencyEdit`、`TTyCustomSpinEdit`、`TTyCustomFloatSpinEdit` | 无（LCL 只能当文本编辑） |
| 选择 | CheckBox、RadioGroup；独有：ToggleSwitch、Segmented、Rating | `TTyCustomCheckBox`、`TTyCustomRadioGroup`、`TTyCustomToggleSwitch`、`TTyCustomSegmented`、`TTyCustomRating` | TDBCheckBox、TDBRadioGroup |
| 列表 | ComboBox、ListBox、LookupComboBox、LookupListBox | `TTyCustomComboBox`、`TTyCustomListBox`、`TTyCustomDBComboBox`、`TTyCustomDBListBox` | TDBComboBox、TDBListBox、TDBLookupComboBox、TDBLookupListBox |
| 其他 | Image、DateTimePicker、Calendar、Navigator | `TTyCustomImage`、`TTyCustomDateTimePicker`、`TTyCustomCalendar`、`TTyCustomControl` | TDBImage、TDBDateTimePicker、TDBCalendar、TDBNavigator |

共 21 个。**以后有需求再做**（不在本计划）：CalcEdit、CalcCurrencyEdit、TrackEdit、TrackBar、ColorBox / ColorComboBox、HtmlLabel、LinkLabel、Badge / Tag、ImageView、ComboEdit、URLEdit、TreeSelect / Cascader 当查找控件。**不做**：多值（CheckGroup、CheckListBox、CheckComboBox、Transfer）、多记录（TreeView、ListView、Grid——Grid 是第二期，另立计划）、选系统资源的（字体、Shell、文件、筛选器）、汇总指示器（Gauge、Meter、进度条、Dial、图表）、容器 / 按钮 / 菜单 / 对话框。

## 核实记录（动手前查过的事实）

| # | 事实 | 出处 | 对设计的影响 |
|---|---|---|---|
| V1 | `TFieldDataLink`（:43）、`TDBLookup`（:116）、`ChangeDataSource`（:1535）、`TDBNavButtonType` / `TDBNavButtonSet` / `TDBNavButtonDirection` / `TDBNavClickEvent` / `DefaultDBNavigatorButtons`（:1329-1345）都在 `DBCtrls` 的接口部分（实现从 :1540 起）；`FieldIsEditable`（:1579）、`FieldCanAcceptKey`（:1585）只在实现部分 | `C:/lazarus/lcl/dbctrls.pp` | 前者直接用；后两个在 `tyControls.DB.Common` 里各写一份（三四行，照 LCL 语义：非计算、非自增、非查找字段；再加 `Field.IsValidChar`）。Navigator 复用 LCL 的枚举与事件类型，`.lfm` 里 `VisibleButtons = [nbFirst, ...]` 与 LCL 同名。 |
| V2 | `dbctrls.pp` 与各 `db*.inc` 在 Lazarus 3.0（`D:/lazarus30`）与 4.4 内容相同；差异只有 4.4 的 macOS 按键分支（dbedit.inc:131-143、dbmemo.inc:153-171）、`LoadMemo` 只在文本变了才赋值、`dbdateedit.inc` 的空值判断 | 调研 | 用 `TFieldDataLink` 不受 3.0 / 4.4 差异影响；macOS 分支照抄语义（按键先 `Edit`，失败丢键）。 |
| V3 | `TFieldDataLink.IsModified` 是私有字段，LCL 的 `TDBEdit` 因同单元直接写它（dbedit.inc:248） | 调研 | 只用公开的 `Modified` / `Reset` / `UpdateRecord` / `Edit`；失焦后清修改标记用 `Reset`（会重读字段，正是失焦后想要的显示）。 |
| V4 | `TFieldDataLink.Reset` = 触发 `OnDataChange` 再清修改标记；`UpdateData` 只在已修改时才触发 `OnUpdateData`；数据集 `Post` 经 FCL 的 `deUpdateRecord` 也会走到 `UpdateData` | dbctrls.pp:1819、1936 | 写回有两条路：控件的 `EditingDone` / 失焦调 `UpdateRecord`，或别处 `Post`。用户改动之后**必须** `Modified`，否则 `Post` 不写回（LCL `TDBCalendar` 就是这个 bug：从不调 `Edit` / `Modified`，值永远写不回去——我们不照抄）。 |
| V5 | 本库**每个**目标控件用代码设值时都会触发 OnChange（或同等事件）；`TTyCustomNumericEdit` 在获得 / 失去焦点时还会因重排格式触发 OnChange（值不变） | 调研 Edit.pas:1100-1127、NumericEdit.pas:265-340、ToggleSwitch.pas:212、Segmented.pas:374、Rating.pas:188 | 不能把「OnChange 触发」当成「用户改了」：用装载标记 + 装载值比较（D2）。 |
| V6 | 观察不到用户改动的四处：`TTyCustomComboBox` 打字路径 `EditorChange`（私有）直接触发 `FOnChange`（ComboBox.pas:1589/1600/1803/2095）；`TTyCustomDateTimePicker` 六处直接触发 `FOnChange`，其中日历下拉的改动不经过控件自己的键鼠覆写（DateTimePicker.pas:1774/1795/2103/2130/2696/2723）；`TTyCustomRadioGroup` 的点击落在子单选按钮上，经私有 `NotifySelection`（RadioGroup.pas:580）；`TTyCustomImage.PictureChanged` 私有（Image.pas:66、586） | 调研 | Task 2 在这四处补 protected virtual 汇集点（D3）。其余控件：Edit / Memo 有公开的多播 `AddHandlerOnChange`；CheckBox 的 `Click` 是 public virtual；ListBox 的 `DoSelectionChange(AUser)` 是 protected virtual；ToggleSwitch / Segmented / Rating / Calendar 的用户输入只经自己的 `Click` / `KeyDown` / `MouseDown` 覆写，DB 类在覆写里比较前后值即可。 |
| V7 | `TTyCustomNumericEdit` 失焦把空文本补成 `0.00`（NumericEdit.pas:338），没有空值表示；`Value` 每次从 `Text` 解析，`MinValue < MaxValue` 时读写都静默钳制；解析固定 `.` 小数点、`,` 千分位 | 调研 | 补一个 protected 开关 `EmptyAllowed`（Task 2）：为 True 时失焦不补 0、空文本保持空；DB 数值控件开它，空 ↔ NULL（D5）。写回用 `Field.AsFloat` / `AsCurrency` / `AsInteger`，不经文本，避开本地化。 |
| V8 | `TTyCustomMaskEdit` 不认 `'#'` 掩码字符（MaskEdit.pas:233-238，抛 `ETyMaskError`）；运行时改掩码会清空文本（:950）；`ValidateEdit` 在不完整时抛异常 | 调研 | 取字段的 `EditMask`（`CustomEditMask = False` 时，照 LCL）：解析失败就不套掩码、不抛（D6）；改完掩码重新装载值。 |
| V9 | `TTyCustomCalendar.Date :=` 越界抛 `ETyInvalidDate`；`SetDateClamped` 不抛 | Calendar.pas:595、227 | DB 日历装载用 `SetDateClamped`。 |
| V10 | `TTyDateTimePicker.ReadOnly` 不挡下拉日历（`OpenDropDown` 只查 `IsInert`）；LCL 只读时不开日历（datetimepicker.pas:3758）。3.0.0 起就有 | 本计划核实 | 已移交「3.0 问题修复」会话修在 3.0-fixes 并摘到 main。**Task 8 依赖它**：动手前 `git log main` 确认已摘到；没摘到就停下交主控。 |
| V11 | `TTyCustomComboBox.ReadOnly` 只转给内嵌编辑框，`csDropDownList` 下照样能从列表选 | ComboBox.pas:1084 | 与 LCL 组合框一致，不算 bug；DB 组合框自己挡（D4）。 |
| V12 | `tyControls.Icons.Lucide` 不许被库内其他单元引用（`tests/test.lucide.pas` 守着）；Painter 的 `TTyGlyphKind` 没有首 / 末、加、减、编辑、刷新 | 调研 | Navigator 的图标：主题令牌 `--glyph-db-*` 可换图标字体字形，缺省由 Navigator 单元自己用画家的线 / 多边形画（D9），不改 Painter。 |
| V13 | 几乎所有守卫与脚本写死了两个 `.lpk`，只扫 `source/*.pas`、`designtime/*.pas` 一层：`test.release`（:394、:524）、`test.version`（:373、`Reg` 块 :425-471）、`gen-mimic.py`（:104）、`check-lfm-props.py`（:66）、`make-release.ps1`（:90-92）/ `.sh`、`scripts/opm/*`、`build-matrix.sh`（:19-22）；`tests/tytests.lpi` 的搜索路径（:53）不含子目录 | 调研 | Task 1 / Task 12 逐个接上；新包放在别处不接，所有守卫都**静默放过**——这正是要避免的（仓库记忆「新单元漏进 .lpk」）。 |
| V14 | `test.i18n.TestEveryPotHasAChineseCatalogue` 要求每个 `languages/*.pot` 有同名小写的 `.zh_CN.po` 且含全部条目 | test.i18n.pas:338 | 新 `tyControls.DB.StrConsts` 自动被它管住。 |
| V15 | `gen-tycss-catalog.ps1` 只从 `themes/light.tycss` 的选择器头收 typeKey | :35 | 主题里不写 `TyDBXxx`，目录就没有它们；样式覆盖编辑器补全里不出现。可以接受（它们回退到父键），文档写明「要单独给 DB 控件写规则，选择器写 `TyDBEdit` 即可」。 |
| V16 | LCL `TCustomDBComboBox` / `TCustomDBListBox` 里 `DataField`、`DataSource`、`ReadOnly`、`Field` 是 public | dbctrls.pp | D3 的可见性：所有 DB 类的这几个都放 public。 |

## 设计

**D1 包与目录（需主控确认）**
- 运行期包 `tycontrols_db.lpk`（仓库根），单元放 `source/db/`，输出 `lib/$(TargetCPU)-$(TargetOS)/db`，依赖 `tycontrols`（MinVersion 同主版本）、`FCL`（MinVersion 1）、`LCL`（MinVersion 3）；i18n 开、输出 `languages`。
- **设计期注册放进现有的 `tycontrols_dt.lpk`**（建议）：`Design.pas` 加一页 `'TyControls Data Controls'`，dt 包加依赖 `tycontrols_db`。理由：IDE 本来就带 FCL-DB（LCL 自己的 DB 控件就在 IDE 里），装设计期包不多出新东西；应用拖一个 `TTyDBEdit` 时 IDE 自动把 `tycontrols_db` 加进工程，不用的工程照样只依赖 `tycontrols`；所有解析 `designtime/` 的守卫（面板、图标、注册名）不用改就认得新类。另一选择是再建一个 `tycontrols_db_dt.lpk`，代价是图标 `.lrs`、守卫、发版脚本、OPM 都要再接一套。
- 单元：`tyControls.DB.Common`（共用辅助）、`tyControls.DB.StrConsts`（resourcestring）、`tyControls.DB.Edits`（文本 + 数值 8 个）、`tyControls.DB.Choices`（选择 5 个）、`tyControls.DB.Lists`（列表 4 个）、`tyControls.DB.Image`、`tyControls.DB.DateTime`（2 个）、`tyControls.DB.Navigator`。

**D2 共用骨架**（每个 `TTyCustomDBXxx` 都照这个，细节放 `DB.Common` 的小记录 / 过程里，不搞多重继承）
- 字段：`FDataLink: TFieldDataLink`（构造里建，`Control := Self`，挂 `OnDataChange := @DataChange`、`OnUpdateData := @UpdateData`、`OnEditingChange`、`OnActiveChange`）、`FLoading: Boolean`、装载值（按值的类型存一份，文本 / Double / Boolean / Integer / TDateTime）。
- `DataChange`：`FLoading := True`，按字段写控件（空值按 D5），记装载值，`FLoading := False`。
- 用户编辑判定：变化通知到来、`not FLoading` 且当前值 ≠ 装载值 → `FDataLink.Edit`；成功则 `FDataLink.Modified`；失败（只读、`AutoEdit = False` 且不在编辑中、字段不可改）→ `FDataLink.Reset`（把值改回字段的）。
- 写回：`UpdateData` 把控件值按类型写字段；`EditingDone`（以及没有 `EditingDone` 的控件的失焦）调 `FDataLink.UpdateRecord`；Escape → `FDataLink.Reset`（照各 LCL 对应控件：组合框类在 `EditingSource` 时 `DataSet.Cancel`）。
- 公开：`DataSource`、`DataField`、`ReadOnly`（控件自己的只读 OR 连接只读，照 LCL `GetReadOnly` / `SetReadOnly`）、`Field`（只读）。`Notification(opRemove)` 置 `DataSource := nil`；`DataSource` 的写方法用 `ChangeDataSource`。`CM_GETDATALINK` 返回 `PtrUInt(FDataLink)`。`ExecuteAction` / `UpdateAction` 转给连接。`ControlStyle` 加 `csReplicatable`。
- typeKey：覆写 `GetStyleTypeKey` 返回 `'TyDBXxx'`；单元 `initialization` 用 `TyTryRegisterTypeKeyParent('TyDBXxx', '<父键>')`，`finalization` 用 `TyUnregisterTypeKeyParent`（照 `docs/tycss-reference` 对包的建议）。

**D3 核心类钩子（Task 2；只加不改，公开 API 与触发顺序不变）**
- `TTyCustomComboBox`：protected virtual `Change`（LCL 同名），四处 `if Assigned(FOnChange) then FOnChange(Self)` 改为调它；`Change` 内触发 `FOnChange`。
- `TTyCustomDateTimePicker`：protected virtual `Change`（LCL 同名），六处同上（`dtpoDoChangeOnSetDateTime` 那处的判断留在调用点）。
- `TTyCustomRadioGroup`：protected virtual `SelectionChanged`，`NotifySelection` 里触发 `OnSelectionChanged` 之前调它（基类实现为空）。
- `TTyCustomImage`：protected virtual `DoPictureChanged`，`PictureChanged` 里触发 `OnPictureChanged` 之前调它（基类实现为空）。
- `TTyCustomNumericEdit`：protected `EmptyAllowed: Boolean`（字段默认 False，不发布）；为 True 时 `DoExit` / `Reformat` 不把空文本补成 0。
- 不改的：Edit / Memo（用 `AddHandlerOnChange`）、CheckBox（`Click`）、ListBox（`DoSelectionChange`）、ToggleSwitch / Segmented / Rating / Calendar / SpinEdit（覆写各自的键鼠方法比较前后值；SpinEdit 另有 protected virtual `DoValueChange`）。

**D4 只读与「挡不住就改回来」**：没有 `ReadOnly` 的基础控件（CheckBox、ListBox、RadioGroup、ToggleSwitch、Segmented、Image）和 `csDropDownList` 下只读不生效的 ComboBox，DB 类在用户改动时 `Edit` 失败就 `Reset` 改回字段值（LCL TDBCheckBox / TDBListBox / TDBRadioGroup 就是这样）。能在动之前挡的就挡：CheckBox / ToggleSwitch 覆写 `Click`（以及 ToggleSwitch 的 `KeyDown`）在不可改时不调 inherited；Rating 有 `ReadOnly`，DB 类把它设成 `ReadOnly or not CanModify`（照 LCL TDBDateTimePicker 的 `CheckField`）；DateTimePicker 同理（依赖 V10）。

**D5 空值（需主控确认）**

| 控件 | 字段 NULL 时显示 | 用户怎么写出 NULL |
|---|---|---|
| Edit / Memo / MaskEdit / ComboBox | 空文本 | 清空文本（照 LCL：写 `Field.Text := ''`，字符串字段得到空串；非字符串字段由 `TField.SetAsString('')` 变 NULL） |
| NumericEdit / CurrencyEdit / FloatSpinEdit | 空文本（`EmptyAllowed`） | 清空文本 → `Field.Clear` |
| SpinEdit | `ValueEmpty = True` | 做不到（基础控件不允许用户清空），文档写明 |
| CheckBox | `cbGrayed`（照 LCL） | 只有 `AllowGrayed` 时点到灰态 → `Field.Clear` |
| ToggleSwitch | 关 | 做不到（开关没有第三态），文档写明 |
| RadioGroup / Segmented / ListBox | `ItemIndex = -1` | 做不到（没有「取消选择」手势），文档写明 |
| Rating | 0 星 | 把当前整星再点一下清到 0 → 字段非 `Required` 时 `Field.Clear`，`Required` 时写 0 |
| DateTimePicker | `TyNullDate`（空字段） | `NullInputAllowed` 时按 N / Delete → `Field.Clear` |
| Calendar | 不改当前显示（日历没有空态） | 做不到，文档写明 |
| Image | 空图 | 程序把 `Picture` 清空 → `Field.Clear` |

**D6 各组的值映射**
- 文本：照 LCL TDBEdit——获得焦点且可改时显示 `Field.Text`，否则 `Field.DisplayText`；写回 `Field.Text := Text`；字符串字段 `MaxLength = 0` 时取 `Field.Size`；复制字段的 `Alignment`。Memo：`AutoDisplay`（默认 True）、blob 字段照 LCL `LoadMemo` / `UpdateData` 规则（有 `OnGetText` / `OnSetText` 用 `Text`，否则 `AsString`）。Text：`Caption := Field.DisplayText`，设计期无字段时显示 `Name`。MaskEdit：`CustomEditMask`（默认 False，照 LCL）为 False 时套字段的 `EditMask`；解析失败（含 `'#'`）就不套、不抛；改掩码后重新装载。
- 数值：装载按字段类型 `AsFloat` / `AsCurrency` / `AsInteger` 写 `Value`；写回同类型写字段；`MinValue` / `MaxValue` 照基础控件钳制显示，文档写明「字段里越界的值会按范围显示，用户改动后写回的是范围内的值」。
- CheckBox：`ValueChecked` / `ValueUnchecked`（默认 `BoolToStr(True)` / `BoolToStr(False)`，`;` 分隔多个词），布尔字段走 `AsBoolean`，照 LCL `GetFieldCheckState` / `UpdateData`；改动立即写回（LCL：`Edit → Modified → UpdateRecord`）。ToggleSwitch 同 CheckBox 的值映射（无灰态）。
- RadioGroup / Segmented：`Values: TStrings`（第 i 项为空时用 `Items[i]`，照 LCL `GetButtonValue`），按 `Field.Text` 找下标；写回 `Field.Text := Value`；`Value: string` public。
- Rating：数值字段 `AsFloat`；`AllowHalf` 关时写回取整。
- ComboBox：显示 `Field.Text`，写回 `Text`；打字在 `Change` 里进入编辑（不照抄 LCL 的投递消息延后编辑——我们的通知是同步的，延后没有必要）。ListBox：`ItemIndex := Items.IndexOf(Field.Text)`。
- Lookup 两个：`TDBLookup.Create(Self)`，`Initialize(FDataLink, Items)`，发布 `KeyField`、`ListField`、`ListFieldIndex`、`ListSource`、`LookupCache`、`NullValueKey`、`EmptyValue`、`DisplayEmpty`、`ScrollListDataset`（照 LCL）；`KeyValue` public。组合框默认 `Style` 用本库组合框的默认（`csDropDownList`，与 LCL 的 `csDropDown` 不同——查找控件只该选列表里的值；需主控确认，见 D10）。`NullValueKey`：按键匹配就 `Field.Clear`（LCL 的 `HandleNullKey` 私有，自己写）。
- Image：读——字段是 blob，先试 LCL 的扩展名头（`ReadAnsiString`），再 `OnDBImageRead`，再按内容识别（`TPicture.LoadFromStream`）；写——`WriteHeader`（默认值照 LCL）决定写不写头，`OnDBImageWrite`；`AutoDisplay`、`QuickDraw` 照 LCL 发布。行为照 LCL，**自己实现，不抄 LCL 代码**。
- DateTimePicker：照 LCL TDBDateTimePicker——装载 `AsDateTime`，NULL → `TyNullDate`；`inherited ReadOnly := ReadOnly or not CanModify`；`EditingDone` → `UpdateRecord`；Escape 的 `UndoChanges` 变成 `Reset`。Calendar：装载 `SetDateClamped(AsDateTime)`；用户选日（`MouseDown` / `KeyDown` 比较前后 `Date`）→ `Edit` + `Modified`；`OnAccept` 或 `EditingDone` → `UpdateRecord`（这是对 LCL TDBCalendar 写不回去的修正，文档写明）。

**D7 拆分与可见性**：照 CONTRIBUTING——每个 DB 类拆分、进 `CSplit`、`gen-mimic.py` 生成镜像、`TY_WRITE_FRESH_STREAMS=1` 补夹具。Custom 类里 DB 属性（`DataSource`、`DataField`、`ReadOnly`、`Field`、Lookup 一组、`ValueChecked` 等）放 public（V16）；最终类发布段 = 基础控件最终类的发布段原样 + DB 属性，顺序：基础控件的全部名字在前，DB 属性按 LCL 对应类的发布顺序在后。

**D8 typeKey 父键**：TyDBEdit / TyDBMaskEdit / TyDBNumericEdit / TyDBCurrencyEdit / TyDBFloatSpinEdit → `TyEdit`；TyDBSpinEdit → `TySpinEdit`；TyDBMemo → `TyMemo`；TyDBText → `TyLabel`；TyDBCheckBox → `TyCheckBox`；TyDBToggleSwitch → `TyToggleSwitch`；TyDBRadioGroup → `TyGroupBox`；TyDBSegmented → `TySegmented`；TyDBRating → `TyRating`；TyDBComboBox → `TyComboBox`；TyDBLookupComboBox → `TyDBComboBox`；TyDBListBox → `TyListBox`；TyDBLookupListBox → `TyDBListBox`；TyDBImage → `TyImage`；TyDBDateTimePicker → `TyDateTimePicker`；TyDBCalendar → `TyCalendar`；TyDBNavigator → `TyToolBar`，它的按钮 `TyDBNavigatorButton` → `TyButton`。

**D9 Navigator**：一个自绘控件（不建子窗口——本机每个窗口控件约 30 ms 启动开销，见仓库记忆），十个按钮按 `Direction` 横排 / 竖排均分。发布（照 LCL）：`DataSource`、`VisibleButtons`（默认 `DefaultDBNavigatorButtons`）、`ConfirmDelete`（默认 True）、`ShowButtonHints`（默认 True）、`Hints: TStrings`（空行用默认提示）、`Direction`、`Images`（`Images[Ord(btn)]` 优先于内置字形）、`BeforeAction`、`OnClick: TDBNavClickEvent`。不发布 LCL 的 `Options`（`navFocusableButtons`）、`Flat`：控件本身不可聚焦（`TabStop` 默认 False），按钮是图形不是窗口。启用规则照 LCL `DataChanged` / `EditingChanged` / `ActiveChanged`；Refresh 用 `Active and not Editing`（LCL 两套按钮在这里不一致，取可聚焦那套的写法，文档写明）。删除确认用 `TyMessageDlg`（主题化，不用原生），经 protected virtual `ConfirmDeleteRecord: Boolean` 调用，测试替身覆写它。按钮样式解析 `TyDBNavigatorButton` 的 `:hover` / `:active` / `:disabled`；字形先试主题令牌 `--glyph-db-first`、`-prior`、`-next`、`-last`、`-insert`、`-delete`、`-edit`、`-post`、`-cancel`、`-refresh`（`TyTryDrawGlyphOverride`），没有就由本单元用画家的线 / 多边形画（首 = 竖线 + 左尖、加 / 减 / 对勾 / 叉 / 铅笔 / 环形箭头），颜色取按钮的文字色。默认尺寸照 LCL 241 × 25（96 PPI 逻辑像素，构造里设，与其他控件一样按 PPI 缩放）。

**D10 需主控确认的点汇总**：① D1 设计期注册放进 `tycontrols_dt.lpk`（建议）还是另建 `tycontrols_db_dt.lpk`；② D5 空值表（特别是 Rating 的 0 ↔ NULL、数值控件的空 ↔ NULL）；③ 查找组合框默认 `csDropDownList`（与 LCL 不同）；④ Navigator 不可聚焦、不发布 `Options` / `Flat`。没回复就按建议做。

## 文件

- 新建 `tycontrols_db.lpk`、`tycontrols_db.pas`（包主单元，IDE 生成格式）、`source/db/tyControls.DB.*.pas`（8 个单元，D1）。
- 改 `tycontrols_dt.lpk`（依赖）、`designtime/tyControls.Design.pas`（新面板页）、`tools/genicons/genicons.lpr`（`Glyphs[]` 加 21 项）、`scripts/gen-icons.ps1`（`$classes`）、生成 `designtime/icons/*.png`、`designtime/tycontrols_icons.lrs`。
- 改核心：`source/tyControls.ComboBox.pas`、`DateTimePicker.pas`、`RadioGroup.pas`、`Image.pas`、`NumericEdit.pas`（Task 2）。
- 新建 `languages/tyControls.DB.StrConsts.pot`、`languages/tycontrols.db.strconsts.zh_CN.po`。
- 测试：新建 `tests/dbfixtures.pas`（内存数据集夹具）、`tests/test.db.common.pas`、`test.db.edits.pas`、`test.db.numeric.pas`、`test.db.choices.pas`、`test.db.lists.pas`、`test.db.image.pas`、`test.db.datetime.pas`、`test.db.navigator.pas`、`test.db.typekeys.pas`、`test.corehooks.pas`；改 `tests/tytests.lpi`（搜索路径加 `../source/db`）、`tests/tytests.lpr`（uses）、`tests/test.release.pas`、`tests/test.version.pas`、`tests/test.customclasses.pas`、生成 `tests/test.customclasses.mimic.pas`、`tests/fixtures/customclasses/fresh-streams.txt`。
- 脚本：`scripts/gen-mimic.py`、`scripts/check-lfm-props.py`（加扫 `source/db`）、`scripts/make-release.ps1` / `.sh`、`scripts/opm/TyControls.json.template`、`scripts/opm/update_TyControls.json`、`scripts/build-matrix.sh`。
- 示例：新建 `examples/dbcontrols/`。
- 文档：新建 `docs/controls/dbcontrols.md`；改 `docs/controls/README.md`、`README.md` / `README.en.md`（控件表、总数、示例表）、`CONTRIBUTING.md` / `.en.md`（第 75 行）、`docs/subclassing.md` / `.en.md`（「没有拆的类」之后加一句 DB 控件也拆了）。

---

## 每个 DB 控件共用的测试判据（C1–C10）

夹具（`tests/dbfixtures.pas`）：`TBufDataset` 内存表——`ID: ftInteger`、`Name: ftString(40)`、`Note: ftMemo`、`Amount: ftFloat`、`Price: ftCurrency`、`Qty: ftInteger`、`Active: ftBoolean`、`Flag: ftString(1)`（'Y' / 'N'）、`Born: ftDate`、`At: ftDateTime`、`Stars: ftFloat`、`Kind: ftString(10)`、`CityID: ftInteger`、`Pic: ftBlob`；三行数据，第三行除 `ID` 外全 NULL。查找表 `Cities(ID, Name)` 三行。`CreateDataset; Open`，挂 `TDataSource`。

| # | 判据 | 必须变红的变异 |
|---|---|---|
| C1 | 打开 / 换行后控件显示该行字段值；NULL 按 D5 显示 | 去掉 `DataChange` 里的写控件 |
| C2 | **装载不进入编辑**：打开、换行、`Refresh` 后 `DataSet.State = dsBrowse`，`FDataLink.Editing = False` | 去掉装载标记（`FLoading` 恒 False）→ 换行后进入 `dsEdit`；把「值与装载值比较」去掉 → NumericEdit 获得焦点就进 `dsEdit` |
| C3 | 用**真实的用户路径**（按键注入 `KeyDown` / `UTF8KeyPress`、`MouseDown` + `MouseUp`、`Click`、日历选日），不是属性赋值，改值后 `State = dsEdit`、修改标记已置 | 去掉 `FDataLink.Modified` → 随后 `Post` 字段不变（C4 红） |
| C4 | 改值后 `EditingDone`（或失焦 / `Post`）→ 字段等于控件值，类型正确（`AsFloat` / `AsBoolean` / `AsDateTime` 比较，不比文本） | `UpdateData` 写错类型或不写 |
| C5 | 改值后 Escape → 显示回到字段值 | 去掉 Escape 处理 |
| C6 | `ReadOnly := True`、`Field.ReadOnly := True`、`DataSource.AutoEdit := False`（不在编辑中）三种各自：用户改动不生效，显示等于字段，数据集不进编辑 | 去掉 `Edit` 失败后的 `Reset`（或 D4 里的 `Click` 拦截） |
| C7 | 先释放 `TDataSource` 再动控件：`DataSource = nil`、不 AV；改 `DataField` 后重新取字段 | 去掉 `Notification` 的置空 |
| C8 | `Perform(CM_GETDATALINK, 0, 0) = PtrUInt(FDataLink)` | 去掉消息处理 |
| C9 | 见 Task 10：typeKey 与链、内置主题下样式与父键一致 | — |
| C10 | `.lfm` 往返：`DataSource`、`DataField` 与 DB 专有属性写出后读回相同；新鲜实例写出的文本进 G10 夹具 | — |

每个控件的测试至少覆盖 C1–C8；组内共性用一个参数化的辅助过程跑，控件特有的另写（见各任务）。

---

### Task 0: 工作树与基线【主控执行】

- [ ] `git worktree add D:/Projects/ty-db -b feat/db-controls a30a69f5`。
- [ ] 基线：`lazbuild tests/tytests.lpi`，复制成唯一文件名跑 `--all --format=plain` 重定向到文件，记下失败（已知 H6 计时偶发另有任务在追）。
- [ ] 确认 V10 的修复是否已摘到 main：`git log --oneline a30a69f5..main -- source/tyControls.DateTimePicker.pas`。没有就继续前面的任务，Task 8 之前再看。

### Task 1: 包骨架与守卫接线

**Files:** 新建 `tycontrols_db.lpk`、`tycontrols_db.pas`、`source/db/tyControls.DB.Common.pas`、`source/db/tyControls.DB.StrConsts.pas`、`languages/tyControls.DB.StrConsts.pot`、`languages/tycontrols.db.strconsts.zh_CN.po`；改 `tests/tytests.lpi`、`tests/test.release.pas`、`tests/test.version.pas`、`scripts/gen-mimic.py`、`scripts/check-lfm-props.py`；新建 `tests/dbfixtures.pas`、`tests/test.db.common.pas`；改 `tests/tytests.lpr`。

- [ ] **Step 1：`DB.Common`**

```pascal
unit tyControls.DB.Common;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, DB, DBCtrls, LCLType;

{ LCL's DBCtrls keeps these two in its implementation section (dbctrls.pp:1579, :1585). }
function TyFieldIsEditable(AField: TField): Boolean;
function TyFieldCanAcceptKey(AField: TField; AKey: Char): Boolean;

{ The value a control showed when DataChange last loaded it, kept per kind so "did the user
  change it" is a comparison, not a guess from OnChange (which fires on loads too). }
type
  TTyDBLoadedValue = record
    Kind: (lvNone, lvText, lvNumber, lvBool, lvIndex, lvDate);
    Text: string;
    Number: Double;
    Bool: Boolean;
    Index: Integer;
    Date: TDateTime;
    IsNull: Boolean;
  end;

implementation
...
```

`TyFieldIsEditable`：`(AField <> nil) and (AField.FieldKind <> fkCalculated) and (AField.DataType <> ftAutoInc) and (AField.FieldKind <> fkLookup)`；`TyFieldCanAcceptKey`：`TyFieldIsEditable(AField) and AField.IsValidChar(AKey)`。共用骨架（D2）的其余部分各控件直接写在自己类里——每类二三十行，抽象成基类做不到（各自继承不同的基础控件）。

- [ ] **Step 2：`DB.StrConsts`** — 本任务先放 Navigator 的十条提示与删除确认（英文原文照 LCL `lclstrconsts.pas:83-95` 的意思自己写，不照抄措辞）：`rsTyDBNavFirst` … `rsTyDBNavRefresh`、`rsTyDBNavConfirmDelete`；`.pot` 由 IDE / lazbuild 生成格式手写一份，`zh_CN.po` 写中文（首条记录、上一条、下一条、末条记录、插入、删除、编辑、保存、取消、刷新；「删除这条记录吗？」）。

- [ ] **Step 3：`tycontrols_db.lpk`**：照 `tycontrols.lpk` 的格式（Version 与 `TyVersion` 相同；`SearchPaths/OtherUnitFiles = source/db`；`UnitOutputDirectory = lib/$(TargetCPU)-$(TargetOS)/db`；i18n 开、`OutDir = languages`；`RequiredPkgs`：`tycontrols`、`FCL`（MinVersion 1）、`LCL`（MinVersion 3））；`Files` 列本任务的两个单元（后面每加一个单元同步加一行）。`tycontrols_db.pas` 照 `tycontrols.pas` 的格式（执行中改：它是 lazbuild 生成物，照 `tycontrols.pas` 加进 `.gitignore`、不提交）。

- [ ] **Step 4：守卫接线**
  - `tests/tytests.lpi` 搜索路径加 `../source/db`。
  - `test.release`：`EveryUnitOnDiskIsListedInItsPackage` 加 `CheckDir('source' + PathDelim + 'db', 'tycontrols_db.lpk')`；`EveryFileThePackagesNameIsShipped` 加 `tycontrols_db.lpk`；发版脚本那两条（`BothScriptsShipTheSameTrees` 等）在 Task 12 改脚本时一起过。
  - `test.version.TestPackageVersionsMatchTyVersion` 加第三个包。
  - `gen-mimic.py`：扫描 `source/*.pas` 与 `source/db/*.pas`；uses 行照常按单元名生成。
  - `check-lfm-props.py`：声明的属性同样从两处收。

- [ ] **Step 5：夹具与测试** — `tests/dbfixtures.pas` 建上面的两张表（函数 `NewDbFixture(AOwner): TDbFixture`，含 `DS: TBufDataset`、`Src: TDataSource`、`Cities`、`CitySrc`，`Free` 时按依赖逆序释放）。`test.db.common`：`TyFieldIsEditable` 对计算字段、自增、查找字段、普通字段；`TyFieldCanAcceptKey` 对数值字段拒字母。

判据 / 变异：M1（`tycontrols_db.lpk` 的 `Files` 漏一个 `source/db` 单元）→ `EveryUnitOnDiskIsListedInItsPackage` 红；M2（`CheckDir` 那行删掉）→ 用 M1 再跑一遍，必须变成**不红**——证明这条守卫就是那一行，记进签收；M3（包版本改成别的）→ `TestPackageVersionsMatchTyVersion` 红。

- [ ] **Step 6：提交** `build(db): the tycontrols_db package and its guards`，`Refs #34`。

### Task 2: 核心类钩子（D3）

**Files:** `source/tyControls.ComboBox.pas`、`DateTimePicker.pas`、`RadioGroup.pas`、`Image.pas`、`NumericEdit.pas`；新建 `tests/test.corehooks.pas`。

- [ ] **Step 1：测试**（探针子类覆写钩子计数，并记下与 `OnChange` 的先后）
  - ComboBox：用户选列表项、打字（csDropDown）、代码设 `ItemIndex` 各一次 → `Change` 次数与 `OnChange` 次数**逐次相同**（钩子就是原来的触发点，一个不多一个不少）。
  - DateTimePicker：按键改段、滚轮、步进按钮、日历选日（`CalendarChange` / `CalendarAccepted` 的无头路径）、Escape `UndoChanges`、`dtpoDoChangeOnSetDateTime` 下的代码设值 → `Change` 与 `OnChange` 次数相同；不带该选项的代码设值两者都是 0。
  - RadioGroup：点子按钮、代码设 `ItemIndex` → `SelectionChanged` 在 `OnSelectionChanged` **之前**各一次。
  - Image：`Picture.LoadFromFile` / `Picture.Assign` / `Picture.Clear` → `DoPictureChanged` 在 `OnPictureChanged` 之前各一次。
  - NumericEdit：`EmptyAllowed` 默认 False（失焦空文本变 `0.00`，与改动前相同）；探针置 True 后失焦空文本仍为空、`Value = 0`。
- [ ] **Step 2：实现**（D3）。每处只把 `if Assigned(FOnChange) then FOnChange(Self)` 换成调 `Change`，条件判断留在原处。
- [ ] **Step 3：提交** `feat(controls): protected change hooks for data-aware subclasses`，`Refs #34`。

判据 / 变异：M4（ComboBox 打字路径仍直接触发 `FOnChange`、不经 `Change`）→ 次数断言红；M5（DateTimePicker 日历路径漏改）→ 红；M6（`SelectionChanged` 放到事件之后）→ 先后断言红；M7（`EmptyAllowed` 不起作用）→ 红；M8（默认改成 True）→ 默认值断言红。

### Task 3: 文本组——Edit、MaskEdit、Memo、Text

**Files:** 新建 `source/db/tyControls.DB.Edits.pas`（本任务写这 4 个）、`tests/test.db.edits.pas`；改 `tycontrols_db.lpk`（`Files`）、`tests/tytests.lpr`。

- [ ] **Step 1：测试** — 四个控件各跑 C1–C8；另：
  - Edit：获得焦点且可改时显示 `Field.Text`、失焦显示 `DisplayText`（给 `Amount` 设 `DisplayFormat = '0.00 元'` 区分）；`Name` 字段 `MaxLength` 取 40；`Field.Alignment = taRightJustify` 时控件右对齐；按键前先 `Edit`，`Edit` 失败丢键（`TyFieldCanAcceptKey` 拒的字符不进文本）；剪贴板粘贴在不可改时被挡。
  - MaskEdit：字段 `EditMask = '000-0000;1;_'` 时套用；`'#'` 掩码不套、不抛；`CustomEditMask = True` 时用控件自己的 `EditMask`；改掩码后显示的仍是字段值。
  - Memo：blob 字段 `AutoDisplay = False` 时显示 `(Note)`（`DisplayLabel` 加括号），按 Enter 才装载；`Lines.Add` 之类的代码改动不算用户编辑（C2 的 Memo 版本）。
  - Text：只读显示，无字段时设计期显示 `Name`、运行期空。
- [ ] **Step 2：实现**（D2、D6）。Edit / MaskEdit / Memo 用 `AddHandlerOnChange` 接通知；Escape 在 `KeyDown` 里处理并吞键；Enter 走基础控件已有的 `EditingDone`。
- [ ] **Step 3：拆分登记** — 4 个类进 `CSplit`（`test.customclasses.pas` 的 `AddAll(GSplit, ...)` 末尾新开一段 `// DB`），跑 `python scripts/gen-mimic.py` 并核对 diff 只多这 4 个镜像类，`TY_WRITE_FRESH_STREAMS=1` 补夹具并核对只多 4 段。
- [ ] **Step 4：提交** `feat(db): text controls -- TTyDBEdit, TTyDBMaskEdit, TTyDBMemo, TTyDBText`，`Refs #34`。

### Task 4: 数值组——NumericEdit、CurrencyEdit、SpinEdit、FloatSpinEdit

**Files:** `source/db/tyControls.DB.Edits.pas`（续）、`tests/test.db.numeric.pas`。

- [ ] **Step 1：测试** — C1–C8；另：
  - 写回走数值不走文本：`DecimalSeparator` 设成 `','` 的进程环境里（测试前后还原，见仓库记忆「期望值来自环境」）改值写回，`Field.AsFloat` 正确。
  - 空 ↔ NULL（D5）：NULL 行显示空文本；用户清空文本、`EditingDone` → `Field.IsNull`；SpinEdit 的 NULL 行 `ValueEmpty = True`。
  - **获得 / 失去焦点不进编辑**（V5：`Reformat` 触发 OnChange 但值不变）——这是 C2 在数值组最容易漏的形态。
  - `MinValue = 0`、`MaxValue = 10` 时字段值 99：显示按范围；不动它就不写回（`Post` 后字段仍是 99）。
- [ ] **Step 2：实现**；构造里 `EmptyAllowed := True`（数值三个）。
- [ ] **Step 3：拆分登记**（同 Task 3 Step 3，4 个类）。
- [ ] **Step 4：提交** `feat(db): numeric controls`，`Refs #34`。

判据 / 变异：M9（去掉装载值比较、只靠 `FLoading`）→「获得焦点不进编辑」红；M10（写回用 `Field.Text := Text`）→ 逗号小数点那条红。

### Task 5: 选择组——CheckBox、ToggleSwitch、RadioGroup、Segmented、Rating

**Files:** 新建 `source/db/tyControls.DB.Choices.pas`、`tests/test.db.choices.pas`。

- [ ] **Step 1：测试** — C1–C8（C5 Escape 对这组无意义的跳过，测试里写明原因）；另：
  - CheckBox：`ValueChecked = 'Y;Yes'`、`ValueUnchecked = 'N;No'` 对 `Flag` 字段（大小写不敏感匹配）；写回取列表第一个词；布尔字段走 `AsBoolean`；NULL → `cbGrayed`；点击后**立即**写回（不等 `EditingDone`）；不可改时点击不翻转（`State` 不变，不只是事后改回）。
  - ToggleSwitch：同 CheckBox 的值映射；空格键与点击都走得到（覆写了 `Click` 和 `KeyDown`）。
  - RadioGroup / Segmented：`Values` 第 i 项为空时用 `Items[i]`；`Value` 读写；字段值不在列表里 → `ItemIndex = -1`。
  - Rating：`AllowHalf = False` 时写回取整；清到 0 星 → 非 `Required` 字段 NULL、`Required` 字段 0；`ReadOnly` 随 `CanModify` 变。
- [ ] **Step 2–4：实现、拆分登记（5 个）、提交** `feat(db): choice controls`，`Refs #34`。

判据 / 变异：M11（CheckBox 的 `Click` 拦截去掉）→「不可改时点击不翻转」红；M12（ToggleSwitch 只覆写 `Click` 不覆写 `KeyDown`）→ 空格键那条红；M13（RadioGroup 不用 `SelectionChanged`、只覆写自身 `MouseDown`）→ 点子按钮那条红。

### Task 6: 列表组——ComboBox、ListBox、LookupComboBox、LookupListBox

**Files:** 新建 `source/db/tyControls.DB.Lists.pas`、`tests/test.db.lists.pas`。

- [ ] **Step 1：测试** — C1–C8；另：
  - ComboBox：`csDropDown` 下打字立即进入编辑（经 Task 2 的 `Change`）；`csDropDownList` 下只读时从列表选不生效（D4、V11）；Escape 在本控件开启编辑时 `DataSet.Cancel`、否则 `Reset`（照 LCL `EditingSource`）。
  - ListBox：`ItemIndex = Items.IndexOf(Field.Text)`；`DoSelectionChange(AUser = False)` 不算编辑。
  - Lookup 两个：`ListSource = CitySrc`、`KeyField = 'ID'`、`ListField = 'Name'`、`DataField = 'CityID'`：显示城市名；选另一项写回 `CityID`；`KeyValue` 读写；`EmptyValue` / `DisplayEmpty` 时列表首项是空项；`NullValueKey = VK_DELETE` 时按 Delete → `CityID` 为 NULL；查找表增删行后列表跟着变（`TDBLookup` 的 `DatasetChange`）；字段本身是 `fkLookup` 查找字段时用字段自带的定义。
- [ ] **Step 2–4：实现、拆分登记（4 个）、提交** `feat(db): list controls and lookups`，`Refs #34`。

### Task 7: Image

**Files:** 新建 `source/db/tyControls.DB.Image.pas`、`tests/test.db.image.pas`。

- [ ] **Step 1：测试** — C1–C4、C6–C8；另：PNG 写进 `Pic` 后读回像素相同；带 LCL 扩展名头的 blob（测试里按 LCL 格式手工写：`WriteAnsiString('png')` 后跟数据）能读；`WriteHeader` 两种取值写出的 blob 各自被另一种设置读回；`OnDBImageRead` / `OnDBImageWrite` 被调用；`Picture.Clear` 后写回 → `Field.IsNull`；`AutoDisplay = False` 时不装载。
- [ ] **Step 2–4：实现（经 Task 2 的 `DoPictureChanged`）、拆分登记、提交** `feat(db): TTyDBImage`，`Refs #34`。

### Task 8: DateTimePicker、Calendar

**Files:** 新建 `source/db/tyControls.DB.DateTime.pas`、`tests/test.db.datetime.pas`。

- [ ] **Step 0**：确认 V10 已在 main（Task 0）；没有就停下交主控。
- [ ] **Step 1：测试** — C1–C8；另：
  - DateTimePicker：NULL → 空字段，`NullInputAllowed` 下 N 键 → NULL 写回；`ReadOnly` 或字段只读时下拉日历不开（依赖 V10）；Escape → `Reset`（不是基础控件的 `UndoChanges` 回到获得焦点时的值）；`Born`（`ftDate`）写回不带时间部分。
  - Calendar：越界字段值不抛（`SetDateClamped`）；鼠标选日 / 方向键 → 编辑 + 修改；`OnAccept` → 写回（**LCL TDBCalendar 写不回去，这里要能**：选日后 `Post`，字段等于所选日期）。
- [ ] **Step 2–4：实现、拆分登记（2 个）、提交** `feat(db): date and time controls`，`Refs #34`。

判据 / 变异：M14（Calendar 选日后不调 `Modified`——即照抄 LCL）→ `Post` 写回那条红。

### Task 9: Navigator

**Files:** 新建 `source/db/tyControls.DB.Navigator.pas`、`tests/test.db.navigator.pas`；改 `DB.StrConsts`（已有条目）。

- [ ] **Step 1：测试**
  - 启用规则：数据集关闭全灰；首行时 First / Prior 灰；末行时 Next / Last 灰；浏览时 Post / Cancel 灰、Edit / Insert 亮；编辑中相反；只读数据源（`AutoEdit` 与 `ReadOnly` 组合）时 Insert / Delete / Edit / Post / Cancel 灰；Refresh = `Active and not Editing`。
  - 点击：无头注入 `MouseDown` + `MouseUp` 到每个按钮的矩形中心 → 对应数据集方法（`First` … `Refresh`）被执行；`BeforeAction` 在执行前、`OnClick` 在执行后；删除时 `ConfirmDelete = True` 走 `ConfirmDeleteRecord`（探针返回 False → 不删）。
  - 布局：`VisibleButtons` 去掉两个后其余均分宽度；`Direction = nbdVertical` 时按高度均分；RTL 时横排顺序镜像（First 在右）。
  - 提示：`Hints` 第 3 行设了就用它，其余行用 resourcestring；`ShowButtonHints = False` 时没有提示。
  - 渲染：哨兵底色（仓库记忆）上每个可见按钮矩形里都有字形墨迹；主题给 `--glyph-db-next` 设了图标字体字形时用它（字形墨迹与内置画法不同）；禁用按钮的墨迹颜色是 `:disabled` 的文字色。
- [ ] **Step 2–4：实现（D9）、拆分登记、提交** `feat(db): TTyDBNavigator`，`Refs #34`。

判据 / 变异：M15（启用规则里 Next 漏判 `EOF`）→ 末行那条红；M16（RTL 不镜像）→ 红；M17（删除不问 `ConfirmDeleteRecord`）→ 红。

### Task 10: typeKey 与主题（C9）

**Files:** 新建 `tests/test.db.typekeys.pas`。

- [ ] **Step 1：测试** — 21 个类各：`GetStyleTypeKey = 'TyDBXxx'`；`TyTypeKeyChain('TyDBXxx')` 等于 D8 的链；17 个内置主题 × 默认 / `:hover` / `:focus` / `:disabled` 下，DB 控件解析出的样式与其基础控件逐项相同（主题没写 `TyDBXxx` 规则时）；主题写一条 `TyDBEdit { background: #FF0000 }` 后只有 DB 编辑框变、`TyEdit` 不变。Navigator 按钮键 `TyDBNavigatorButton` 同样检查。
- [ ] **Step 2：提交** `test(db): type keys fall back to the base controls in every built-in theme`，`Refs #34`。

判据 / 变异：M18（某个单元的 `initialization` 漏登记父键）→ 链断言与主题一致性都红。

### Task 11: 设计期注册与图标

**Files:** `tycontrols_dt.lpk`、`designtime/tyControls.Design.pas`、`tools/genicons/genicons.lpr`、`scripts/gen-icons.ps1`、`designtime/icons/*`、`designtime/tycontrols_icons.lrs`、`tests/test.version.pas`（`Reg` 块）。

- [ ] **Step 1**：`Design.pas` 的 uses 加 `tyControls.DB.Edits` 等，`Register` 里在 `'TyControls Data Views'` 之后加：

```pascal
  // Data-aware controls (tycontrols_db).
  RegisterComponents('TyControls Data Controls',
    [TTyDBNavigator, TTyDBText, TTyDBEdit, TTyDBMaskEdit, TTyDBNumericEdit, TTyDBCurrencyEdit,
     TTyDBSpinEdit, TTyDBFloatSpinEdit, TTyDBMemo, TTyDBCheckBox, TTyDBToggleSwitch,
     TTyDBRadioGroup, TTyDBSegmented, TTyDBRating, TTyDBComboBox, TTyDBLookupComboBox,
     TTyDBListBox, TTyDBLookupListBox, TTyDBImage, TTyDBDateTimePicker, TTyDBCalendar]);
```

  `tycontrols_dt.lpk` 的 `RequiredPkgs` 加 `tycontrols_db`。属性编辑器：`DataField` 用 LCL 的字段名编辑器（`TFieldProperty`，IDE 已为 `DataField: string` 名注册的会自动生效——实现者查 `C:/lazarus/components/ideintf` 确认；没有自动生效就显式注册到 Custom 类，D2 规则）。
- [ ] **Step 2**：`test.version` 的 `Reg([...])` 加 21 个类名。
- [ ] **Step 3【主控执行】**：`genicons.lpr` 的 `Glyphs[]` 与 `gen-icons.ps1` 的 `$classes` 各加 21 项（图标取基础控件的图标叠一个小圆柱「数据库」角标；Navigator 画一排小三角），运行 `scripts/gen-icons.ps1` 生成 PNG 与 `.lrs`，`test.paletteicons` 必须绿。
- [ ] **Step 4：提交** `feat(design): the Data Controls palette page`，`Refs #34`。

### Task 12: 示例、文档、发版脚本

- [ ] **Step 1：示例 `examples/dbcontrols/`**（照 `examples/button/` 的文件组与写法：`.lfm` 窗体、`TTyTitleBar`、主题下拉与暗色开关、`.ico` + DPI 清单）。`FormCreate` 建内存 `TBufDataset`（人员表：姓名、备注、金额、数量、在职、等级（Segmented）、评分、生日、城市（查找）、照片）和城市表，三五行示例数据；照片用示例目录里的两三张小 PNG。窗体：左侧 `TTyDBNavigator` + 表单区放全部 21 个控件（每个配一个说明标签），右侧一个只读的 `TTyDBText` 区显示「当前行原始字段值」便于对照。`.lpi` 依赖 `tycontrols`、`tycontrols_db`、`tycontrols_dt`、`LCL`，`OtherUnitFiles` 加 `../../source/db`；~~`.lpr` 多一句 `TranslateUnitResourceStringsEx('', LangDir, 'tycontrols.db', 'tyControls.DB.StrConsts')`；`languages/` 放两份库目录（`tycontrols.zh_CN.po`、`tycontrols.db.zh_CN.po`）~~ **执行中改（d2582a4e）**：目录名用 `'tycontrols_db'`、文件 `tycontrols_db.zh_CN.po`——LCL `lcltranslator.pas:163` 用 `ChangeFileExt` 拼文件名，`'tycontrols.db'` 会去读 `tycontrols.zh_CN.po`，导航条提示永远是英文与自己的 `.po`。
- [ ] **Step 2：文档** — `docs/controls/dbcontrols.md`（一页讲整族：概述、包与安装、共用属性、各控件的值映射与空值表（D5、D6）、主题（typeKey 链，单独给 DB 控件写规则的写法）、与 LCL 的差异（Calendar 能写回、查找组合框默认 `csDropDownList`、Navigator 不可聚焦、数值控件按数值读写）、代码示例）；`docs/controls/README.md` 链上；`README.md` / `.en.md` 加「TyControls Data Controls」一节控件表、改控件总数与面板页数、示例表加一行；`CONTRIBUTING.md` / `.en.md` 第 75 行改成「新单元加进 `tycontrols.lpk`（设计期的加进 `tycontrols_dt.lpk`；带来新依赖的放进自己的包，如数据感知控件在 `tycontrols_db.lpk`）」；`docs/subclassing.md` / `.en.md` 加一句数据感知控件同样拆分、可从 `TTyCustomDBXxx` 派生。
- [ ] **Step 3：发版脚本** — `make-release.ps1` / `.sh` 根文件加 `tycontrols_db.lpk`、~~`tycontrols_db.pas`~~（执行中改：它和 `tycontrols.pas` 一样由 lazbuild 生成、已 gitignore，不发）（`source/` 整树已含 `source/db`）；`scripts/opm/TyControls.json.template` 加第三个 `PackageFiles` 项（依赖 `tycontrols, FCL, LCL`，`LazCompatibility` 同前两个），`update_TyControls.json` 同步；`build-matrix.sh` 在两个包之间编 `tycontrols_db.lpk`。`test.release` 的脚本解析守卫必须绿。
- [ ] **Step 4：提交**（三个提交：`feat(examples): data controls example`、`docs(db): the data-aware controls`、`build(release): ship tycontrols_db`），`Refs #34`。

### Task 13: 编译、全量、变异、Lazarus 3.0、冒烟、签收【主控执行为主】

- [ ] 实现 agent：编 `tests/tytests.lpi`，全量重定向到文件；集中变异 M1–M18 逐个「改 → 重编 → 跑相关 suite → 记红 → 还原 → 重编」（仓库记忆：变异后必须重编再全量；CRLF 文件上的替换先断言命中数）。
- [ ] 主控：`lazbuild -B` 编 `tycontrols.lpk`、`tycontrols_db.lpk`、`tycontrols_dt.lpk`；全部 examples（含新的 `dbcontrols`）；`check-lfm-props.py`、`check-example-po.py`；按窗口类逐个启动示例（无 `#32770`）。
- [ ] 主控：Lazarus 3.0（`D:/lazarus30`，私有 `--pcp`，`--skip-dependencies`，`--add-package-link` 不接 `=`）编三个包与 `tests`，跑全量。
- [ ] 主控：手点 `dbcontrols` 示例——换行、编辑、Escape、保存、取消、删除确认、只读切换、查找下拉、照片、换主题与暗色、150% 缩放下各控件尺寸。
- [ ] 签收段写进本文件：全量数字、变异结果表、3.0 结果、偏离与原因。

## 签收（执行时填）

### 第一期签收（2026-10-06，主控）

**提交**（`feat/db-controls`，起点 `69966f4b` 计划提交）：1dc2ab82 包骨架与守卫 · c3d75db0 核心钩子 · 61727ac9 文本组 · 4c7a5101 数值组 · 23203ef4 R12 测试改为不假设类型键注册表为空 · f64dcd79 绑定后改范围不算编辑 · 148ce7f3 选择组 · ae4bc785 列表组与查找 · ad658272 绑定后改 Decimals 不算编辑 · 9bb3cf6b 写回后刷新装载值 · 049503d6 Image · e850c797 日期与时间 · d866b03e 放宽范围后重新显示字段值 · a2f7c21f Navigator · 37e81d57 类型键与内置主题 · 408ef0b4 合入 main（货币符号修复 cc348529）· 5ffd126e 面板页与 KeyField/ListField 编辑器 · 37c555f3 修 Task 1 的 .po 头 · a544527f 示例 · d2582a4e 示例翻译目录名 · ac77914f 文档 · 45762097 发版脚本 / OPM / build-matrix · 42f9bd9c DPI 截图诊断认得新示例 · dad29145 面板图标。

**验证**
- 变异：计划列的 M1–M18 全部按判据变红（M2 按要求「不红」）；各批另做了数十个自选变异（每批报告里的表），每次改 → 重编 → 跑 → 还原，后几批用 sha1 核对还原。
- Lazarus 4.4：私有 `--pcp`（不碰全局注册）`-B` 编 `tycontrols` / `tycontrols_db` / `tycontrols_dt` 三个包 0 错；50 个示例全部编过；按窗口类逐个启动无 `#32770`；`check-lfm-props.py` 通过；`check-example-po.py .` 106 个文件 0 问题。
- Lazarus 3.0（`D:/lazarus30`，私有 `--pcp`）：三个包与 `tests` 编过，全量 11054 / 0 / 0。
- Lazarus 4.4 全量：见下一条（最后一遍，图标已生成）。

**偏离计划（均有测试或文档）**
- 选择组五个控件、DBImage 改动立即写进记录（单选组点击落在子按钮上、图片控件拿不到焦点，都没有 EditingDone / 失焦可等）；C5 对它们改为「改动保留」。
- RadioGroup、ComboBox 从代码设 `ItemIndex` / `Value` / `Text` 算编辑（它们唯一的变化钩子在代码设值时也触发，LCL 同）；其余控件代码设值不算编辑；查找控件写 `KeyValue` 不算。
- CheckBox / ToggleSwitch 写回取词表第一个词（LCL 会把整串写进去）；默认 `ValueChecked` / `ValueUnchecked` 照 FPC 实际为 `'-1'` / `'0'`。
- Rating 不开半星时装载即四舍五入到整星；Calendar 写日期时间字段保留原时分；Image 的扩展名头先校验再信（LCL 会把裸 PNG 的前 4 字节当长度）、写错格式时回退按内容识别；Image 不提供剪贴板方法。
- Navigator：`ShowHint` 出生为 True（按钮不是子控件，控件自己要收 `CM_HINTSHOW`），`.lfm` 因此写出 `ParentShowHint = False`；按住 Prior / Next 不连续翻页；两个新度量 `--dbnav-gap`、`--dbnav-glyph-size` 用 `Metric(名字, 兜底)`，内置主题不写（Task 10 要求 DB 控件与基础控件解析一致）。
- 设计期：`DataField` 的字段名编辑器 IDE 已按名字注册给一切组件（ideintf/dbpropedits.pas:211），不用注册；`KeyField` / `ListField` 注册到两个查找控件的 Custom 类。
- 守卫：计划 V13 漏列了 `test.customclasses`、`test.lucide`、`test.glyphthickness`、`test.dpi.*` 等只扫 `source/` 的扫描，统一改用 `LibrarySourceFiles`；`test.release` 另加两条：根目录每个 `.lpk` 两个发版脚本都发、OPM 两个文件都列。

**发现、已移交或待定**
- `TTyCurrencyEdit` 符号含 `.` 时丢值（3.0 起）：移交「3.0 问题修复」，已修（#38，cc348529），已合入本分支。
- 可编辑组合框（`csDropDown`）内嵌编辑框裁掉字母下伸部分、字体与下拉列表样式不同：移交「3.0 问题修复」复现。
- StyleModel 解析渐变背景时 `TTyFill` 的 `SliceRepeat` / `ImageMode` / `Blur` / `GlassTint` 未初始化（同一渐变解析两次结果不同；绘制按背景类型取字段，目前看不出）：StyleModel 是共享文件，待用户定。
- `update_TyControls.json` 已列 `tycontrols_db.lpk`：合进 main 后、发版前，OPM 读到的会是不含这个包的 3.0 压缩包，待用户定是否发版时再加。
- 示例：`DBCurrencyEdit` 显示控件自己的 `CurrencySymbol`（默认 `$`），字段的 `DisplayText` 走系统区域货币（中文 Windows 上是 `¥`），示例里两列不一致。
