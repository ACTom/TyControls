# 数据感知控件（tycontrols_db）

## 1. 概述

`tycontrols_db` 是一个单独的包，里面是 21 个绑定数据集字段的控件：把 `DataSource` 指向一个 `TDataSource`、`DataField` 填字段名，控件就显示当前记录的这个字段，用户改了值会写回去。用法和 LCL 的 `TDBEdit`、`TDBNavigator` 那一套一样，数据连接直接用的就是 LCL `DBCtrls` 单元里的 `TFieldDataLink` 和 `TDBLookup`；外观则和库里其他控件一样，由当前主题决定，现有主题不用改。

| 组 | 控件 | 建在 | LCL 对应 |
|---|---|---|---|
| 文本 | `TTyDBEdit`、`TTyDBMaskEdit`、`TTyDBMemo`、`TTyDBText` | `TTyEdit`、`TTyMaskEdit`、`TTyMemo`、`TTyLabel` | `TDBEdit`、`TDBEdit`（带掩码）、`TDBMemo`、`TDBText` |
| 数值 | `TTyDBNumericEdit`、`TTyDBCurrencyEdit`、`TTyDBSpinEdit`、`TTyDBFloatSpinEdit` | 同名基础控件 | 无（LCL 只能拿文本框绑数值字段） |
| 选择 | `TTyDBCheckBox`、`TTyDBRadioGroup`、`TTyDBToggleSwitch`、`TTyDBSegmented`、`TTyDBRating` | 同名基础控件 | `TDBCheckBox`、`TDBRadioGroup`；后三个 LCL 没有 |
| 列表 | `TTyDBComboBox`、`TTyDBListBox`、`TTyDBLookupComboBox`、`TTyDBLookupListBox` | `TTyComboBox`、`TTyListBox`；查找控件建在前两个 DB 控件上 | `TDBComboBox`、`TDBListBox`、`TDBLookupComboBox`、`TDBLookupListBox` |
| 其他 | `TTyDBImage`、`TTyDBDateTimePicker`、`TTyDBCalendar`、`TTyDBNavigator` | `TTyImage`、`TTyDateTimePicker`、`TTyCalendar`；导航条是独立的自绘控件 | `TDBImage`、`TDBDateTimePicker`、`TDBCalendar`、`TDBNavigator` |

完整的演示见 [examples/dbcontrols](../../examples/dbcontrols/)：21 个控件放在同一个窗体上，绑一张内存表（`TBufDataset`，不用数据库），旁边一列 `TTyDBText` 显示当前记录的原始字段值，方便对照。

---

## 2. 包与安装

| 项目 | 值 |
|---|---|
| 运行期包 | `tycontrols_db.lpk`（仓库根目录），依赖 `tycontrols`、`FCL`、`LCL` |
| 单元 | `tyControls.DB.Edits`（文本与数值 8 个）、`tyControls.DB.Choices`（选择 5 个）、`tyControls.DB.Lists`（列表 4 个）、`tyControls.DB.Image`、`tyControls.DB.DateTime`（日期 2 个）、`tyControls.DB.Navigator`；另有 `tyControls.DB.Common`（共用的小函数）、`tyControls.DB.StrConsts`（导航条的提示文字） |
| 组件面板 | `TyControls Data Controls` 页 |

不用另外安装：设计期包 `tycontrols_dt.lpk` 依赖 `tycontrols_db`，装好设计期包，面板上就有这一页。往窗体上拖一个 DB 控件时，IDE 会把 `tycontrols_db` 加进工程的依赖；不用这些控件的工程照旧只依赖 `tycontrols`。

对象查看器里，`DataField` 是一个字段名下拉（列出 `DataSource` 所连数据集的字段），这是 IDE 自带的编辑器，对任何组件的字符串 `DataField` 都生效；查找控件的 `KeyField`、`ListField` 也是下拉，列的是 `ListSource` 的字段。

**界面语言。** 导航条的十条按钮提示和删除确认在 `tyControls.DB.StrConsts` 里，有自己的翻译文件。部署时把 `languages/tycontrols.db.strconsts.<语言>.po` 改名为 `tycontrols_db.<语言>.po`，和库的主翻译放在同一个目录，启动时多加一行：

```pascal
TranslateUnitResourceStringsEx('', LangDir, 'tycontrols', 'tyControls.StrConsts');
TranslateUnitResourceStringsEx('', LangDir, 'tycontrols_db', 'tyControls.DB.StrConsts');
```

第三个参数里不能有点：LCL 把最后一个点后面的部分当扩展名换成语言代码，写成 `'tycontrols.db'` 会去读 `tycontrols.zh_CN.po`，里面没有这些条目，提示就一直是英文。

---

## 3. 共同的用法

### 3.1 属性

每个 DB 控件都在基础控件的属性之外多发布这几个（导航条只有 `DataSource`）：

| 属性 | 类型 | 说明 |
|---|---|---|
| `DataSource` | `TDataSource` | 连哪个数据源。数据源被释放时自动置空。 |
| `DataField` | `string` | 字段名。改了之后重新取字段、重新显示。 |
| `ReadOnly` | `Boolean` | 只读开关，读写的是数据连接的 `ReadOnly`（照 LCL）。打开后用户改不了字段，见 3.4。 |
| `Field` | `TField`（只读，public） | 当前绑定的字段；没绑上时为 `nil`。 |

每个控件都拆成两个类：`TTyCustomDBXxx` 放数据连接和全部实现，`TTyDBXxx` 只发布属性。`DataSource`、`DataField`、`ReadOnly`、`Field` 在 Custom 类上是 public，和 LCL 的 `TCustomDBComboBox` 一样；想做一个只露部分属性的数据感知控件，从 `TTyCustomDBXxx` 派生，见 [../subclassing.md](../subclassing.md)。

基础控件的值本身（编辑框的 `Text`、多行编辑框的 `Lines`、`TTyDBText` 的 `Caption`、图片的 `Picture`……）不写进 `.lfm`：值放在字段里。

### 3.2 什么时候算「用户改了」

控件从字段装载值的时候也会触发自己的 `OnChange`，所以 DB 控件不靠 `OnChange` 判断。每个控件记着最近一次从字段装载的值，只有**不在装载过程中、并且和装载的值不同**的变化才算用户改的。这时数据集进入编辑状态（`dsEdit`），连接被标记为已修改；之后不管是控件自己写回，还是别处调用 `Post`，字段都会拿到新值。

所以下面这些都**不会**让数据集进入编辑：打开数据集、换行、`Refresh`；数值框获得或失去焦点时重排格式；程序在绑定之后改 `MinValue`、`MaxValue` 或 `Decimals`。

### 3.3 什么时候写回

| 控件 | 写回时机 |
|---|---|
| 编辑框、数值框、多行编辑框、组合框、列表框、日期时间框、日历 | 按 Enter（`EditingDone`）、离开控件，或别处 `Post` |
| 复选框、开关、单选组、分段、评分、两个查找控件、图片 | 改的那一刻就写进记录（数据集同时进入编辑），由 `Post` / `Cancel` 决定去留 |

在编辑中按 Esc，控件回到字段的值。组合框有一点特别（照 LCL）：如果是它让记录进入编辑的，Esc 直接取消整条记录。选择类控件改了就已经写进记录，Esc 没有东西可退，要撤销用数据集的 `Cancel`（导航条上的 ✕）。

### 3.4 不能改的时候

`ReadOnly` 打开、字段不能改（只读字段、计算字段、自增字段），或者数据源的 `AutoEdit` 关着而记录又不在编辑中——这三种情况下用户的改动都不生效，控件显示的始终是字段的值，数据集也不会进入编辑。能事先拦住的就拦住：编辑框里的按键直接丢掉，复选框和开关点了不翻转（也不触发 `OnChange`），评分和日期时间框在这期间是只读的。拦不住的（单选组、分段、`csDropDownList` 下的组合框、列表框、图片）在改动之后马上改回字段的值。

---

## 4. 各控件的值怎么对应字段

### 文本

- **`TTyDBEdit`**：获得焦点并且可以编辑时显示 `Field.Text`，其余时候显示 `Field.DisplayText`（比如带 `DisplayFormat` 的数值字段，没焦点时显示格式化后的样子）。写回 `Field.Text := Text`。字符串字段、`MaxLength` 为 0 时取字段的 `Size`；对齐方式跟字段的 `Alignment`。
- **`TTyDBMaskEdit`**：`CustomEditMask` 为 False（默认，照 LCL）时用字段的 `EditMask`，为 True 时用控件自己的 `EditMask`。字段的掩码解析不了（比如本库不认的 `#`）就不套掩码，不报错。
- **`TTyDBMemo`**：备注（blob）字段用 `AsString` 装载，字段有 `OnGetText` / `OnSetText` 时用 `Text`。`AutoDisplay` 为 False 时先显示 `(字段名)` 这样的占位，按 Enter（或调用 `LoadMemo`）才装载，适合一屏显示很多大文本的场合。
- **`TTyDBText`**：只读，显示 `Field.DisplayText`。设计期没绑字段时显示自己的 `Name`，运行时为空。

### 数值

`TTyDBNumericEdit`、`TTyDBCurrencyEdit`、`TTyDBFloatSpinEdit`、`TTyDBSpinEdit` 按字段的类型用 `AsFloat`、`AsCurrency` 或 `AsInteger` 读写，**不经过文本**，所以系统小数点是逗号的环境里也不会读错。字段里的值超出 `MinValue`..`MaxValue` 时按范围显示；用户不动它就不写回，字段保持原值；用户一改，写回去的是范围内的值。

### 选择

- **`TTyDBCheckBox`**：布尔字段走 `AsBoolean`。其他字段按 `ValueChecked` / `ValueUnchecked` 匹配字段文本：可以用 `;` 分隔多个词（如 `'Y;Yes'`），比较不分大小写，写回时用第一个词。默认值和 LCL 一样是 `BoolToStr(True)` / `BoolToStr(False)`，即 `'-1'` / `'0'`。
- **`TTyDBToggleSwitch`**：值的对应规则同复选框，没有灰态。
- **`TTyDBRadioGroup`、`TTyDBSegmented`**：第 i 项对应 `Values[i]`，`Values` 这一行为空时用 `Items[i]` 本身（照 LCL）。按 `Field.Text` 找到对应项选中，写回 `Field.Text`。字段值不在列表里就什么都不选（`ItemIndex = -1`）。public 的 `Value` 可以直接读写当前值。单选组只能从子按钮的选择变化知道用户点了什么，所以程序设 `ItemIndex` / `Value` 也会改字段，这一点和 LCL 的 `TDBRadioGroup` 相同。
- **`TTyDBRating`**：数值字段，`AsFloat`。`AllowHalf` 关着时只显示、只写整星：字段里的 3.5 显示成 4，用户改了才写回。

### 列表

- **`TTyDBComboBox`**：显示 `Field.Text`（选中文字相同的那一项），写回控件的文字。`csDropDown` 下打字立刻进入编辑。程序设 `ItemIndex` 或 `Text` 也算编辑，和给 `TTyDBEdit` 设 `Text` 一样。组合框自己的 `ReadOnly` 只管得到可编辑的输入框，`csDropDownList` 下从列表选的改动会被改回去。
- **`TTyDBListBox`**：选中 `Items.IndexOf(Field.Text)` 那一项，写回选中项的文字。程序设 `ItemIndex` 不算编辑。
- **`TTyDBLookupComboBox`、`TTyDBLookupListBox`**：显示 `ListSource` 各行的 `ListField`，把选中行的 `KeyField` 写进 `DataField`；`DataField` 本身是查找字段（`fkLookup`）时用字段自己的定义。选中就写进记录。其他照 LCL：`ListFieldIndex`、`LookupCache`、`ScrollListDataset`、`KeyValue`（public，选中行的键；设它只选中行、不改字段，用于不绑 `DataSource` 当普通列表用的场合）、`EmptyValue` / `DisplayEmpty`（列表第一行放一个代表 `EmptyValue` 的空项）、`NullValueKey`（一个快捷键，按下就把字段清成 NULL，0 表示不用）。查找表增删行，列表跟着变。

### 其他

- **`TTyDBImage`**：blob 字段里存图片文件本身的格式（PNG、BMP、JPEG……）。默认在前面加一个扩展名头，格式和 LCL 的 `TDBImage` 一样，两边写的数据可以互相读；`WriteHeader` 为 False 时不加。读的时候有头用头，没有就按内容识别；`OnDBImageRead` / `OnDBImageWrite` 让程序读写自己的头。程序给 `Picture` 赋值、`LoadFromFile`、`Clear` 都算用户的改动，马上写进记录，清空的图写成 NULL。`AutoDisplay`、`QuickDraw`（和 LCL 一样不起作用）、`PictureLoaded`、`LoadPicture` 照 LCL。
- **`TTyDBDateTimePicker`**：`AsDateTime` 装载；日期字段只写日期部分，时间字段只写时间部分。不能改时下拉日历也打不开。在编辑中按 Esc 回到**字段**的值，而不是获得焦点时的值。
- **`TTyDBCalendar`**：显示字段的日期，超出 `MinDate`..`MaxDate` 时按范围显示，不抛异常。用户点某一天、用方向键或 PageUp/PageDown 换了日子都算编辑；点选确认、按 Enter / 空格、离开控件或别处 `Post` 时写回。日期时间字段保留原来的时刻。翻月不算编辑。
- **`TTyDBNavigator`**：一排十个按钮（首条、上一条、下一条、末条、插入、删除、编辑、保存、取消、刷新），类型和名字都用 LCL `DBCtrls` 里的：`VisibleButtons`（默认全部）、`Direction`（横排 / 竖排）、`Hints`、`ShowButtonHints`、`Images`（`Images[Ord(按钮)]` 优先于内置图标）、`ConfirmDelete`（默认 True）、`BeforeAction`、`OnClick`，所以给 `TDBNavigator` 写的窗体属性读进来含义相同。按钮的可用规则照 LCL；刷新在数据集打开且不在编辑中时可用。删除确认是主题化的消息框，经 protected virtual `ConfirmDeleteRecord` 调用，子类可以换掉。从右往左的布局里首条按钮在右边。默认尺寸 241 × 25。

---

## 5. 空值（NULL）

| 控件 | 字段为 NULL 时 | 用户怎样写出 NULL |
|---|---|---|
| 编辑框、掩码框、多行编辑框、组合框 | 空文本 | 清空文本。字符串字段得到空串，其他类型的字段由 `TField` 把空文本变成 NULL（照 LCL） |
| 数值框、货币框、小数微调框 | 空文本 | 清空文本 |
| 整数微调框 | `ValueEmpty = True` | 做不到：基础控件不让用户清空 |
| 复选框 | 灰态（`cbGrayed`） | `AllowGrayed` 打开时点到灰态 |
| 开关 | 关 | 做不到：开关没有第三态 |
| 单选组、分段、列表框 | 什么都不选 | 做不到：没有「取消选择」的手势 |
| 评分 | 0 颗星 | 清到 0 颗星（按 Home；`AllowHalf` 关着时再点一次当前那颗星也行）。字段是 `Required` 时写 0 而不是 NULL |
| 日期时间框 | 空（`TyNullDate`） | `NullInputAllowed` 打开时按 N 或 Delete |
| 日历 | 停在当前显示的那天 | 做不到：日历没有空的状态 |
| 图片 | 空图 | 程序清空 `Picture` |
| 查找控件 | 不选 | `NullValueKey` 设的那个键 |

---

## 6. 主题

每个 DB 控件有自己的 typeKey，并且登记了父键：主题里没写 `TyDBXxx` 规则时，DB 控件和它的基础控件长得一模一样。17 个内置主题都没有写 DB 专用的规则。

| typeKey | 父键 |
|---|---|
| `TyDBEdit`、`TyDBMaskEdit`、`TyDBNumericEdit`、`TyDBCurrencyEdit`、`TyDBFloatSpinEdit` | `TyEdit` |
| `TyDBSpinEdit` | `TySpinEdit` |
| `TyDBMemo` | `TyMemo` |
| `TyDBText` | `TyLabel` |
| `TyDBCheckBox` / `TyDBToggleSwitch` / `TyDBSegmented` | `TyCheckBox` / `TyToggleSwitch` / `TySegmented` |
| `TyDBRadioGroup` | `TyGroupBox` |
| `TyDBRating`（星星 `TyDBRatingStar`） | `TyRating`（`TyRatingStar`） |
| `TyDBComboBox` / `TyDBListBox` | `TyComboBox` / `TyListBox` |
| `TyDBLookupComboBox` / `TyDBLookupListBox` | `TyDBComboBox` / `TyDBListBox` |
| `TyDBImage` | `TyImage` |
| `TyDBDateTimePicker` / `TyDBCalendar` | `TyDateTimePicker` / `TyCalendar` |
| `TyDBNavigator`（每个按钮 `TyDBNavigatorButton`） | `TyToolBar`（`TyButton`） |

想单独给 DB 控件换个样子，选择器直接写它的键，比如让所有数据感知编辑框带一点底色：

```css
TyDBEdit { background: mix(var(--surface), var(--accent), 6%); }
```

只有 `TyDBEdit` 变，`TyEdit` 和其他控件不受影响；没写到的状态（`:hover`、`:focus`、`:disabled`）仍按 `TyEdit` 的规则来。链的合并规则见 [tycss 参考 §4.5](../tycss-reference.md)。这些键不在样式覆盖编辑器的补全列表里（补全只收 `themes/light.tycss` 里出现过的键），手写即可。

导航条按钮按各自的状态（`:hover`、`:active`、`:disabled`）解析 `TyDBNavigatorButton`，变体跟着导航条的 `StyleClass` 走（`StyleClass = 'ghost'` 时按钮用主题的 ghost 按钮样式）。按钮上的图标依次取：`Images` 里的图；主题令牌 `--glyph-db-first`、`--glyph-db-prior`、`--glyph-db-next`、`--glyph-db-last`、`--glyph-db-insert`、`--glyph-db-delete`、`--glyph-db-edit`、`--glyph-db-post`、`--glyph-db-cancel`、`--glyph-db-refresh` 指定的图标字体字形；都没有时用内置的矢量图形，颜色取按钮的文字色。图标大小是 `--dbnav-glyph-size`，按钮间距是 `--dbnav-gap`。

---

## 7. 和 LCL 不一样的地方

- **日历能写回。** LCL 的 `TDBCalendar` 从不把连接标记为已修改，用户选的日子 `Post` 时丢掉；`TTyDBCalendar` 会写回。
- **查找组合框默认 `csDropDownList`**（LCL 默认 `csDropDown`）：查找控件只该选列表里有的值。
- **导航条不可聚焦。** 十个按钮是控件自己画的矩形，不是子窗口，所以没有 LCL 的 `Options`（`navFocusableButtons`）和 `Flat`，按住上一条 / 下一条也不会连续翻动。
- **选择类控件和图片改了就写进记录。** LCL 的复选框和查找控件本来如此；LCL 的单选组要等 `EditingDone` 才写，图片要等 `Post`，而且图片在 LCL 里改了也不让数据集进入编辑。这里单选组和图片也是改了就写，开关、分段、评分同样处理。
- **数值按数值读写。** LCL 只能用文本框绑数值字段；这里的数值控件用 `AsFloat` / `AsCurrency` / `AsInteger`，不受系统小数点影响。
- **超出范围的值按范围显示。** 数值控件设了 `MinValue` / `MaxValue` 时，字段里越界的值按范围显示，用户不改就不写回。
- **空值**按第 5 节的表处理。
- **刷新按钮**在数据集打开且不在编辑中时可用（LCL 普通按钮那一套要求 `CanModify`，可聚焦按钮那一套是这个规则，这里取后者：只读数据集同样需要刷新）。
- **组合框打字立即进入编辑**，不像 LCL 那样投递一条消息延后处理。

---

## 8. 代码示例

窗体上放一个 `TDataSource`（`PeopleSrc`）和几个 DB 控件，在 `.lfm` 里连好：

```
object EdName: TTyDBEdit
  ...
  DataField = 'Name'
  DataSource = PeopleSrc
end
object CmbCity: TTyDBLookupComboBox
  ...
  DataField = 'CityID'
  DataSource = PeopleSrc
  KeyField = 'ID'
  ListField = 'Name'
  ListSource = CitySrc
end
object Navigator: TTyDBNavigator
  ...
  DataSource = PeopleSrc
end
```

数据集可以是任何 `TDataSet`；不连数据库时用 `TBufDataset` 建一张内存表：

```pascal
uses DB, BufDataset;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FPeople := TBufDataset.Create(Self);
  FPeople.FieldDefs.Add('ID', ftInteger);
  FPeople.FieldDefs.Add('Name', ftString, 40);
  FPeople.FieldDefs.Add('CityID', ftInteger);
  FPeople.CreateDataset;                        // 建好就是打开的
  FPeople.AppendRecord([1, 'Lin Chen', 1]);
  FPeople.First;
  PeopleSrc.DataSet := FPeople;
end;
```

导航条的某个按钮换成自己的提示，只填 `Hints` 对应的那一行，其余留空就用默认的（已翻译的）提示：

```pascal
Navigator.Hints.Text := LineEnding + LineEnding + LineEnding + LineEnding + '新增一名员工';
```
