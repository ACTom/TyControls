# TTyValueListEditor

## 1. 概述

TTyValueListEditor 是**属性检查器级的名/值两列编辑器**:左列是**键**(可展开的多级树,带 chevron),右列是**可编辑的值**,中间是**可拖动的分隔条**。每行是一个 `TTyValueRow` 对象——`Key`/`DisplayKey`、`Value`/`DisplayValue`、值类型 `EditorKind`、`ReadOnly`、逐行样式(`Bold`/`TextColor`/`ImageIndex`)以及**子行**(嵌套)。用 `AddRow`(返回行对象,便于嵌套 / 定类型 / 设样式)构建,或用简单的 `InsertRow(key, value)`。行布局、选择、滚动的**代码**来自 [TTyListBox](listbox.md)(但主题令牌自成一套,见 §2);值单元用主题化 [TTyEdit](edit.md) 覆盖层就地编辑。

**按 `EditorKind` 分派的值编辑器:**

| Kind | 编辑方式 |
|------|---------|
| `vekText` | 文本内联(可自由输入 / 选中 / 复制) |
| `vekInteger` / `vekFloat` | 文本内联,但**限制只能输入数字**(整数:数字 + 首位负号;浮点:再允许一个 `.`) |
| `vekBoolean` | `True` / `False` 下拉 |
| `vekEnum` | `EnumValues`(每行一项)下拉 |
| `vekColor` | **色板下拉**(每项一个色块),最后一行"更多…"弹主题色对话框(`TySelectColor`);单元显示色块 |
| `vekFont` | **只读**文本(可点/选/复制)+ 尾部"**…**"按钮——**只有点"…"** 才弹字体对话框(`TTyFontDialog`);若该行有子行(`Name`/`Size`/`Color` + 四个样式位 `Bold`/`Italic`/`Underline`/`StrikeOut`,或嵌套 `Style` 节点下的样式位),选好字体后**回写这些子行** |
| `vekDialog` | **用户侧自定义**:**只读**文本 + 尾部"**…**"按钮——点"…"触发 `OnEditRow`,应用**自己决定弹什么**(库自带 `TySelectDirectory` / `TyShowAbout` / `TyMessageDlg` …)、是否写回 `ARow.Value`(如"关于"这类纯只读信息就不写回) |
| `vekReadOnly` | 不可编辑 |

- **`vekFont`/`vekDialog` 的内联文本是只读的**:值由对话框决定,文本只供查看/复制,编辑一律走"…"(避免手输脏值,也让复合 Font 行与子行不脱节)。
- 用 `InvokeRowDialog(flat)` 可编程触发 `vekFont`/`vekDialog` 行的对话框(即"…"按钮所做的)。
- **要做对象检查器、而对象不在本进程里**(或者不是 Pascal 对象):行按描述来建,改动经 `OnValueChanging` 交出去,完整做法见 §8。
- **`vekDialog` 就是"用户侧自定义"入口**:一个 `OnEditRow` 事件覆盖全部 `vekDialog` 行,在处理器里按 `ARow.Key`(或行对象)分派到各自的动作——弹只读的关于框、选路径、跳消息框皆可。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ValueListEditor` |
| 类型 | `TTyValueListEditor` + `TTyValueRow` + `TTyValueEditorKind` |
| `GetStyleTypeKey` 返回值 | `'TyValueListEditor'`(自己的键,不是祖先 `TTyListBox` 的) |

它**只是复用**了 `TTyListBox` 的虚拟化行循环,并不是一个列表框:它画的两列 + 可拖分隔条、带缩进的键列、
逐行展开标记、带色块和"…"按钮的值列,列表框一样都没有。挂在 `TyListBox`/`TyListItem` 上时,皮肤既没法
给键列单独上色、没法给分隔条定色、没法改展开标记的颜色,也没法让检查器的选中行读起来与普通列表的选中行不同。
现在的部件表:

| typeKey | 画什么 |
|---|---|
| `TyValueListEditor` | 外框:背景、边框、圆角、内边距 |
| `TyValueListEditorRow` | 一根行(`GetItemStyleTypeKey`),含 `:hover` / `:active`(选中) |
| `TyValueListEditorKey` | 键列文字色 |
| `TyValueListEditorValue` | 值列**默认**文字色(逐行的 `TextColor` 覆盖仍然优先) |
| `TyValueListEditorDivider` | 键/值分隔线(读 `background`) |
| `TyValueListEditorExpander` | 展开/收起 chevron 的墨色(chevron 本身是全库统一的展开标记:大小 `--glyph-chevron-size`,`--glyph-chevron-down` / `-right` 可换成图标字体字形) |
| `TyValueListEditorGroup` | 标题行(`TTyValueRow.Heading`)**平时**的底色、文字色、字重;挂在 `TyValueListEditorRow` 下面。悬停、选中时标题行照普通行的 `:hover` / `:active` 画 |

> `Key`/`Value`/`Divider`/`Expander` 四个是**可选钩子**:`themes/light.tycss` 有意不定义它们,因为它们的后备值**随行状态而变**——
> 都回落到**当前行**解析出的颜色(分隔线回落到该颜色的 alpha `0x28`)。在基层写一个固定值反而会动像素:
> 选中行的后备墨色是 `--on-accent`,若在这里写死 `color: var(--on-surface)`,选中行的键名会直接看不清。
> **要用就连 `:hover` / `:active` 变体一起写。**

值编辑器是一个内嵌的 [TTyEdit](edit.md)(`TTyValueEdit`),解析 `TyEdit`——这个借用是对的:
它就是一个输入框,盒子、内边距和各状态都该与全库输入框一致,不同的只有输入过滤和尾部的"…"。
布尔/枚举/颜色下拉的弹出列表是 `TTyListBox`,解析 `TyListBox`,同理。

```pascal
uses tyControls.ValueListEditor;
```

---

## 3. 关键成员

**`TTyValueListEditor`**

| 成员 | 说明 |
|------|------|
| `AddRow(AKey, AValue): TTyValueRow` | 追加一根行,返回它(可继续 `AddChild` 嵌套 / 设 `EditorKind` / 样式)。 |
| `InsertRow(AKey, AValue, AAppend = True): Integer` | **(API parity 变更,破坏性)** 改成 LCL 的签名(`valedit.pas:188`):**返回新行的下标**,`AAppend = False` 时插到**当前选中根行之前**(LCL 的 not-Append 就是插在 grid 的当前行)。从前是只会追加的两参数 **procedure**,移植调用连参数个数都对不上;`AAppend` 有默认值,已有的两参数写法照旧可用。 |
| `InsertRowAt(AIndex, AKey, AValue): TTyValueRow` | **(API parity 新增)** 插到指定下标并返回该行 —— `InsertRow` 那个布尔量只是它的两种特例。从前这个类上**根本没有"插到某个位置"**:`AddRow` 追加、`DeleteRow` 删除,想按某个顺序建表只能整体重建。下标超出末尾即追加。 |
| `Row(AIndex): TTyValueRow` | 第 i 根行。 |
| `RowCount` | **(API parity 变更)根行数,现在是可读写的属性**(LCL `valedit.pas:237` 也是属性),所以能被 RTTI / 绑定层读到,`VLE.RowCount := 0` 这条"一行清空"的写法也能编译。写入时**从末尾**增删(增出来的是空行)。两处与 LCL 有意不同:只数**数据行**(LCL 的还含固定标题行,同一份列表在那边多 1),且是 public 而非 published —— 把活的行数写进 `.lfm` 会让设计器每次加载都凭空造出空行。 |
| `DisplayRowCount` | **(API parity 重命名,破坏性)** 当前**有显示位置**的行数 = 根行 + 已展开节点的后代。折叠会让它变小,改控件大小不会。**这个含义从前叫 `VisibleRowCount`。** |
| `VisibleRowCount` | **(API parity 变更,破坏性)视口**里现在装得下几行 —— 即 LCL `TCustomGrid.VisibleRowCount` 的含义(`grids.pas:1301`,实现 `:2274`),`TValueListEditor` 经 `TCustomStringGrid` → `TCustomDrawGrid`(`:1538` public 转发)继承而来,因为在那边这个类**就是**一个 grid。**它不是"有几行展开着"** —— 那是 `DisplayRowCount`。两者都是 `Integer`、都是 public,所以移植来的翻页算式编译得过、算出垃圾:500 行展开着就一次翻 500 行。与 LCL 一致到那个差一:答的是 `VisibleGrid.Bottom - VisibleGrid.Top`,比"碰到视口的行数"少一行(翻页留一行重叠);整份列表都装得下时不留重叠。这与 `TTyCustomGrid` 在 03c29b3 修的是同一个撞名,当时没落到这个类上,因为我们这个是 `TTyCustomListBox` 不是 grid。 |
| `Keys[i]` | 第 i 根行的键,**可读写**(LCL `valedit.pas:201` 就是 `read GetKey write SetKey`)。写入是**程序化改名**:触发 `OnKeyChanged` 并重绘,但**不查 `keyUnique`、不看 `ReadOnly`**——见 §7 末条。下标越界时写入是空操作(与 `ValueFromIndex[]` 同一条契约:行式索引只寻址**既有**行,绝不凭空造行)。 |
| `Values[key]` | **按键**读写根行的值(与 LCL / Delphi 的 `TValueListEditor.Values[const Key: string]` 同义)。查找**不分大小写**;写一个**不存在的键会追加一行**——移植过来的代码正是这样填这个控件的。 |
| `ValueFromIndex[i]` | **按行号**读写根行的值,与 `Keys[i]` 配对(名字取自 RTL 自己的 `TStrings.Values[Name]` / `ValueFromIndex[Index]` 一对)。 |
| `DeleteRow(i)` / `Clear` | 删根行 / 清空。 |
| `SetExpanded(ARow, bool)` | 展开/收起。 |
| `UpdateRows` | 直接 `AddChild` 加了子行后调用,刷新可见列表。 |
| `SetRowValue(ARow, AText)` | 按行对象改值(触发 `OnValueChanged`,并**向上更新复合父行**——见 §6)。 |
| `InvokeRowDialog(flat)` | 编程触发 `vekFont`/`vekDialog` 行的对话框(等同点"…")。 |
| `KeyColumnWidth` | 键列宽 / 分隔线位置(逻辑 px,默认 110,可拖)。 |
| `KeyOptions: TTyKeyOptions` | **(API parity 新增)运行时用户能对"行集合"做什么**:`keyEdit` 改键名、`keyAdd` 插行、`keyDelete` 删行、`keyUnique` 键名查重。默认 `[]`(= 从前的行为:值能改,行集合是死的)。详见 §7。 |
| `BeginKeyEdit(flat)` | **(新增)** 编程打开某行的**键**编辑器(等同点键列 / Shift+F2);没开 `keyEdit` 或 `ReadOnly` 时是空操作。与 `BeginEdit`(值列)配对。 |
| `IsEditingKey: Boolean` | **(新增)** 当前打开的编辑器是否盖在**键**列上。`EditingRow` 只说是哪一行,说不出是哪一列,而"哪个单元格开着"决定提交写到哪儿。 |
| `ReadOnly` / `Images` / `OnValueChanged(Sender, ARow)` | 全局只读 / 值单元图像源 / 值提交事件。 |
| `OnKeyChanged(Sender, ARow)` | **(新增)** 一次改名**已提交**(`ARow.Key` 已是新名)——`keyEdit` 手势或程序化 `Keys[i] :=` 两条路都报,与 `OnValueChanged` 对值的两条路对称。**刻意不复用 `OnValueChanged`**——那个事件的约定是"哪一行的**值**变了",拿它报改名会让它说谎。 |
| `OnKeyRejected(Sender, ARow, AKey)` | **(新增)** 一次改名被 `keyUnique` **拒绝**(该行仍是旧名),`AKey` 是用户想取的名字。LCL 在控件内部直接弹 `ShowMessage`(`valedit.pas:1614`);控件库不该这么干,所以只把拒绝报出来,要不要提示由应用决定。 |
| `OnValueChanging(Sender, ARow, var AText, var AAllow)` | 值**写进行之前**问一次,所有提交路径都问(内联编辑框、下拉选择、颜色和字体对话框、`SetRowValue`、`Values[]`、`ValueFromIndex[]`)。可以改写 `AText`(把 `007` 规整成 `7`),也可以把 `AAllow` 设成 `False` 拒绝:编辑框照常关闭,行保持原值,`OnValueChanged` 不触发。值存在别处(另一个进程、文件、设备)的宿主在这里先去写,见 §8.3。处理程序里不要释放 `ARow`,也不要重建行。 |
| `CommitFont: TFont` | 字体对话框选好的字体,只在 `OnValueChanging` 问字体行的那一刻有值,其余时候是 `nil`。带子行的字体行只在字体行上问一次(`AText` 是「名字, 字号 样式」的摘要),答应之后子行跟着改,不再逐个问。 |
| `FilterText` | 只显示键里含这段文字的行(不分大小写,`''` 表示全部显示),见 §8.5。public,不发布。 |
| `OnFilterRow(Sender, ARow, AFilter, var AMatch)` | `FilterText` 判断每一行时问:`AFilter` 是去掉首尾空格、转成小写的过滤文字,`AMatch` 进来时是控件自己的判断(`Key` 或 `DisplayKey` 里含这段文字;标题行自己不算命中),可以往任意一边改。 |
| `OnGetRowColors(Sender, ARow, AColors)` | 颜色行的下拉列表弹出前问:`AColors` 里已经放好控件自带的 16 种基本颜色(名字在 `AColors[i]`,颜色在 `Objects[i]`),可以增删,也可以整个换掉,见 §8.7。处理程序返回之后,行里现在的颜色如果不在列表里会补上,最后加「更多…」。 |
| `BeginUpdate` / `EndUpdate` | 成批建行:两者之间 `AddRow`、`InsertRowAt`、`UpdateRows`、`SetExpanded`、`RestoreExpanded` 都不重建显示列表,到最后一个 `EndUpdate` 才重建一次。可以嵌套。删行(`Clear`、`DeleteRow`、改 `RowCount`)仍然立刻重建,显示列表里不会留着已经释放的行。 |
| `RowPath(ARow): string` | 行从根算起的路径:键用点连起来(`Font.Style.fsBold`);以 `[` 开头的键直接接在后面(`Items[0].Caption`);标题行不算进它下面那些行的路径(是 `Caption`,不是 `@Appearance.Caption`),它自己的路径是 `@` 加键(`@Appearance`)。和 [TTyPropertyGrid](propertygrid.md) 的行路径是同一种写法。 |
| `FindRow(APath): TTyValueRow` | 按路径找行,不分大小写,找不到返回 `nil`。行不必正显示着(收起的、`Hidden` 的、被过滤掉的都找得到)。同一个父行下键相同的行,路径也相同,返回第一个。 |
| `DisplayRow(i)` / `DisplayIndexOf(ARow)` / `SelectedRow` | 显示位置和行对象互相换算:`ItemIndex`、`EditingRow`、`BeginEdit` 用的都是显示位置。没有显示位置的行(在收起的行里、`Hidden`、被过滤掉)得到 `-1`。`SelectedRow` 是当前选中的行。 |
| `SaveExpanded(APaths)` / `RestoreExpanded(APaths)` | 按路径记住哪些行展开着,重建行之后恢复,见 §8.4。 |

**`TTyValueRow`**:`Key`、`DisplayKey`、`Value`、`DisplayValue`、`EditorKind`、`EnumValues`、`ReadOnly`、`Bold`、`TextColor`、`ImageIndex`、`Expanded`、`Data`、`Heading`(标题行:键横跨整行、粗体、`TyValueListEditorGroup` 底色,没有分隔线和值,不能编辑,Enter 展开/收起)、`Hidden`(连同子行一起不显示,改完调 `UpdateRows`);`AddChild(k,v)` / `ChildCount` / `Child[i]` / `Parent` / `HasChildren` / `EffectiveKey` / `EffectiveValue`。

---

## 4. 交互

- **点值列** → 按该行 `EditorKind` 编辑:文本(可选中/复制,数字类型限数字)/ 布尔·枚举·颜色下拉 / 字体·自定义**点行尾画着的"…"** 直接弹对话框,点值列别处先进入只读文本(尾部同样有"…"),选中行按 **Ctrl+Enter** 也弹对话框;**点键列** → 选中该行(开了 `keyEdit` 则**同时进入改名**)。选中行按 **F2 / Enter** 也进入编辑。
- **`KeyOptions` 开出来的手势**(默认全关,见 §7):**点键列 / Shift+F2** 改键名(`keyEdit`)、**Insert** 在当前位置插空行(`keyAdd`)、**Ctrl+Delete** 删当前根行(`keyDelete`)。
- **点键列前的 chevron** → 展开/收起子行;选中行按 **Alt+→ / Alt+←** 也一样(和 Lazarus 的对象查看器一致)。**层级无上限**(如 `Font → Style → Bold`)。
- **拖分隔条**(光标变 ↔)→ 调整键/值列宽。
- 编辑中:**Enter** / 点别处 / 失焦 → 提交;**Esc** → 取消。`ReadOnly` 行 / 全局 `ReadOnly` 不可编辑。
- `OnEditingDone`:一次编辑结束时触发(编辑框提交、下拉选好、对话框关掉),开始编辑、焦点交给内联编辑框时不触发,和 LCL 的表格一样。
- **颜色 / 字体 / 自定义对话框全部用控件库自带的**(`TySelectColor` / `TTyFontDialog` / 你在 `OnEditRow` 里调 `TySelectDirectory` 等),不弹原生对话框。

---

## 5. 代码示例

```pascal
uses tyControls.Controller, tyControls.ValueListEditor;

var VLE: TTyValueListEditor; Row: TTyValueRow;
VLE := TTyValueListEditor.Create(Self);
VLE.Parent := Self; VLE.SetBounds(20, 20, 300, 240);
VLE.InsertRow('宽度', '1280');

Row := VLE.AddRow('主题', 'light.tycss');
Row.DisplayKey := '主题(只读)';      // 显示名覆盖(国际化 / 特殊显示)
Row.ReadOnly := True;

VLE.AddRow('宽度', '1280').EditorKind := vekInteger;   // 限数字输入

Row := VLE.AddRow('Font', 'Segoe UI, 9');   // vekFont + 子行:点"…"弹字体对话框,选完回写子行
Row.EditorKind := vekFont;
Row.AddChild('Name', 'Segoe UI');
Row.AddChild('Size', '9').EditorKind := vekInteger;
Row.AddChild('Color', 'clWindowText').EditorKind := vekColor;
VLE.UpdateRows;                        // 直接加子行后刷新

VLE.OnValueChanged := @HandleChange;   // (Sender; ARow: TTyValueRow)
```

---

## 6. 注意事项

- **`Values[]` 按键取用,`ValueFromIndex[]` 按行号:** 与 LCL / Delphi 的 `TValueListEditor` 一致。**从前 `Values[]` 是按行号的、按键的那个叫 `ValueOf[]`**,于是 `VLE.Values['Name'] := 'Bob'`(几乎每个移植过来的程序都有这一行)编译不过,报的还是一句指不到症结的 "Incompatible type for arg no. 1";而 `Values[0]` 在两个库上都能编译、含义却不同。两者**刻意不做成同名重载**——整数/字符串重载正是移植代码打错成员还照样编译的路子。
- **写 `Values[]` 的两种结果:** 键存在 → 改值并触发 `OnValueChanged`;键不存在 → **追加一行**(与 LCL 的 `SetValue` 落到 `Strings.Add` 一致),这一路**不触发** `OnValueChanged`——它是新增,不是改动。查找不分大小写。
- **窗体文件里存的是根行:** 每个根行存成一条 `键=值`,写在 `Items.Strings` 下;读回来时这些行变成真正的行(旧窗体文件里 `Items` 里的 `Name=Bob` 也一样)。继承来的 `Items` 只是视图的扁平键列表,对象查看器里不显示——加行请用 `AddRow` / `InsertRow` / `Values[]`。子行不存。
- **`AddChild` 后要 `UpdateRows`:** 行对象是直接被你改的,控件观察不到;`AddRow` / `InsertRow` / `DeleteRow` / `SetExpanded` 会自己刷新,只有直接 `AddChild` 需要手动 `UpdateRows`。
- **`DisplayKey`/`DisplayValue`:** 仅影响显示,不改实际 `Key`/`Value`(供 i18n / 格式化);值单元还可带 `ImageIndex`(图文)+ `Bold` / `TextColor`。
- **内联编辑器是内部子控件:** `csNoDesignVisible`,不漏进设计器;`Enter`/失焦提交、`Esc` 取消,主题跟随 `Controller`;滚动会先提交并关闭。
- **字体子行同步按键名匹配:** `vekFont` 行的直接子行里键名为 `Name`/`Size`/`Color` 或四个样式位 `Bold`/`Italic`/`Underline`/`StrikeOut`(也可放在嵌套 `Style` 节点下)会在选字体后被回写。**显示哪些子属性由你决定**——只 `AddChild` 你要暴露的那些即可(控件不设 `Options` 之类的隐藏开关,因为结构本就由你搭)。其它结构请自己在 `OnValueChanged` 里处理。
- **复合父行双向联动(Font / Style):** 改子行(如 `Bold`)会**向上**重算 `Style` 与 `Font` 的显示值(`Style`→`Regular`/`Bold, Italic`;`Font`→`Name, Size` + 尾随样式词);点 `Font` 的"…"选字体则**向下**回写全部子行并重算 `Style`/`Font`。编程改值用 `SetRowValue`(会触发同样的向上联动),别直接写 `ARow.Value`。仅 `style` 键名 + `Bold`/`Italic` 子行、及 `vekFont` 行被识别为复合;其它复合语义自理。
- **颜色"更多…"对话框是延迟弹的:** 走 `Application.QueueAsyncCall`,让弹出列表的鼠标事件先退栈(析构里 `RemoveAsyncCalls` 取消未决调用)。
- **交互是真机验证项:** 数据 / 嵌套 / 展开 / 显示覆盖 / 只读 / 列宽钳制 / 数字过滤已 headless 单测;分隔拖动、chevron 点击、下拉圆角、"…"按钮、颜色/字体对话框、字体子行回写需真机验证。

---

## 7. `KeyOptions` —— 让用户能改"行集合"

对标 LCL `TValueListEditor.KeyOptions`(`valedit.pas:310`,集合 `TKeyOption` 在 `:109`)。**从前这个控件完全没有对应物**:行只能从**代码**里加(`AddRow`/`InsertRow`)和删(`DeleteRow`),键列没有任何手势能改,也没有任何地方查过重复键。于是这个控件最该干的那件事——**用户可编辑的名/值列表**(ini 编辑器、环境变量编辑器)——根本做不出来:用户只能改值,别的什么都不能做。

```pascal
VLE.KeyOptions := [keyEdit, keyAdd, keyDelete, keyUnique];
```

| 标志 | 手势 | 效果 |
|------|------|------|
| `keyEdit` | 点键列 / **Shift+F2** | 键单元变成可编辑,用**同一个**内联编辑器盖在第 0 列上,提交写 `Row.Key`,触发 `OnKeyChanged`。 |
| `keyAdd` | **Insert**(不带修饰键) | 在**当前行位置**插一根空行(不是追加——LCL 也是 `InsertRow('','',False)`,让新行出现在用户正看着的地方)。 |
| `keyDelete` | **Ctrl+Delete** | 删掉当前**根**行。 |
| `keyUnique` | (改名提交时) | 与**同级兄弟**重名的改名**被拒**:该行保留旧名,`OnKeyRejected` 带着被拒的名字触发。 |

**默认 `[]`**,即从前的行为。`ReadOnly` **压过全部四个**——整张表只读时,既不能改名、也不能加删。

### 几个不是自明的点

- **`keyAdd` 会把 `keyEdit` 一起打开。** `KeyOptions := [keyAdd]` **读回来是 `[keyEdit, keyAdd]`**。LCL 的 setter 同样改写自己的入参(`valedit.pas:1037-1038`):一根加得出来却取不了名的空行没有意义。
- **`keyUnique` 只在"同级兄弟"里查重,不是全表。这是与 LCL 有意的分歧。** LCL 的列表是**平的**,所以在那边"兄弟"和"所有行"是同一批。我们这个是**树**,而这棵树**天生就会产生重名**:每根 `vekFont` 行都会长出叫 `Name`/`Size`/`Color` 的子行,一张表里放两个字体行就已经有两个 `Size` 了。若照搬全表规则,`keyUnique` 一打开就等于宣布控件自己的树非法,嵌套行从此改不了名。
- **空键不与任何东西冲突。** `keyAdd` 插进来的就是空行,而"正在填的表里有两根空行"是常态。LCL 跳过空 `Names[]` 也是同一个理由。
- **查重不分大小写**(LCL 用 `AnsiCompareText`,`valedit.pas:1610`),但**行不与自己冲突**——把 `Bold` 改成 `bold` 是允许的。
- **被拒时控件不弹窗。** LCL 在控件内部直接 `ShowMessage`;这里改成触发 `OnKeyRejected`,要不要提示、用哪个对话框由应用定(库自带 `TyMessageDlg`)。**没有处理器时改名就是静静地不生效**——这是刻意的,"改名不落地"才是 `keyUnique` 的义务,提示只是附带。
- **枚举的序号是 API。** 集合属性是按**位序**流式化的,所以 `TTyKeyOption` **只能往后追加**;插在中间会让所有已存的 `.lfm` 悄悄换意思(旧的 `[keyAdd]` 会读成 `keyDelete`)。守卫在 `tests/test.parity.valuelist.pas` 的 `TestKeyOptionOrdinalsAreFrozen`,外加一条真实的流式化往返 `TestKeyOptionsRoundTripsThroughTheStream`。
- **没有对应 LCL 的 `goAutoAddRows` 联动。** LCL 的 setter 会顺手开关 grid 的 `goAutoAddRows`(`valedit.pas:1040-1043`),因为它**是**一个 grid;我们这个是 `TTyListBox`,没有那套 `Options`,所以这条不存在。
- **`Keys[]` 可写,且写入不查 `keyUnique`、不看 `ReadOnly` —— 两条都是有意的,也都是 LCL 的原样。** LCL 的 `SetKey` 就是 `Cells[0,Index]:=Value`(`valedit.pas:1084`),从头到尾**没有**查重——查重只活在编辑器路径里(`ValidateEntry`,`:1614`),所以那边 `Keys[i] :=` 也会写进一个重名。`keyUnique` 管的是**用户手势**,API 归宿主自己负责——与 `ReadOnly` 挡编辑器却不挡 `Text :=` 是同一条分界。两条 bypass 都有测试钉着(`TestKeysWriteIsTheProgrammaticRenamePath`);别在某次"整理"里把 setter 绕去 `CommitKeyEdit`,那会让两个开关一开就顺带锁死 API。写入触发 `OnKeyChanged` 并重绘——从前只能 `Row(i).Key :=`,谁也不知道、界面也不刷。

---

## 8. 不靠 RTTI 的对象检查器

[TTyPropertyGrid](propertygrid.md) 靠 RTTI 工作:要检查的对象得是本进程里的一个 `TPersistent`。对象不在你的进程里(界面设计器里被设计的窗体跑在另一个进程)、不是 Pascal 对象(一段 JSON、一条数据库记录、一台设备的参数表),或者它的类根本没有编译进你的程序,属性表格就用不上了。

这时直接用 TTyValueListEditor。属性表格就是建在它上面的,编辑器、下拉列表、对话框、画法、键盘操作全是它的;属性表格多做的只有一件事:从 RTTI 生成行,再把改动写回对象。这件事换成你来做:**行由你按对象的描述来建,改动通过事件交给你去写**。

下面是一个完整的例子:对象在别处,这边只有它的描述和一组文字形式的值。

### 8.1 描述和远端

```pascal
type
  TPropKind = (pkText, pkInteger, pkFloat, pkEnum, pkColor, pkSet, pkObject);

  TPropDesc = record
    Path: string;       // 'Caption'、'Font.Size'
    Category: string;   // 顶层属性的分类
    Kind: TPropKind;
    Choices: string;    // 枚举的取值、集合的元素,逗号分隔
    ReadOnly: Boolean;
  end;

  { 对面那个进程的代理。怎么通信是你的事,检查器只用这两个调用。 }
  TRemoteObject = class
    function Read(const APath: string): string;
    { False = 对面不接受;AStored 是对面现在实际存着的值 }
    function Write(const APath, AText: string; out AStored: string): Boolean;
  end;
```

### 8.2 建行

分类用标题行(`Heading`),嵌套对象的属性是子行,集合拆成每个元素一行的布尔子行,枚举把取值放进 `EnumValues`:

```pascal
procedure TInspector.AddProp(AParent: TTyValueRow; const D: TPropDesc);
var
  Row, El: TTyValueRow;
  Names: TStringList;
  i: Integer;
begin
  Row := AParent.AddChild(LastName(D.Path), Merged(D.Path));   // Merged 见 8.6
  Row.ReadOnly := D.ReadOnly;
  case D.Kind of
    pkInteger: Row.EditorKind := vekInteger;
    pkFloat:   Row.EditorKind := vekFloat;
    pkColor:   Row.EditorKind := vekColor;
    pkEnum:
      begin
        Row.EditorKind := vekEnum;
        Row.EnumValues := StringReplace(D.Choices, ',', LineEnding, [rfReplaceAll]);
      end;
    pkSet:
      begin
        Row.ReadOnly := True;            // 集合本身只显示,通过元素来改
        Names := TStringList.Create;
        try
          Names.CommaText := D.Choices;
          for i := 0 to Names.Count - 1 do
          begin
            El := Row.AddChild(Names[i], BoolToStr(Pos(Names[i], Row.Value) > 0, 'True', 'False'));
            El.EditorKind := vekBoolean;
          end;
        finally
          Names.Free;
        end;
      end;
  end;
  for i := 0 to High(FDescs) do          // 嵌套对象:描述里路径在它下面的那些属性
    if SameText(ParentPath(FDescs[i].Path), D.Path) then AddProp(Row, FDescs[i]);
end;

procedure TInspector.BuildRows;
var
  i: Integer;
  Head: TTyValueRow;
begin
  for i := 0 to High(FDescs) do
  begin
    if FDescs[i].Category = '' then Continue;          // 嵌套的属性由父行去加
    Head := VLE.FindRow('@' + FDescs[i].Category);
    if Head = nil then
    begin
      Head := VLE.AddRow(FDescs[i].Category, '');
      Head.Heading := True;
    end;
    AddProp(Head, FDescs[i]);
  end;
end;
```

不用给每行另外记「它是哪个属性」:`VLE.RowPath(Row)` 就是 `Font.Size` 这样的路径,标题行不算在里面,正好拿去问远端。想挂自己的记录也行,`Row.Data` 是留给你的指针。

其他类型照这个思路配:组件引用用 `vekEnum`,把候选名字放进 `EnumValues`;字符串列表、集合项这类要弹窗的用 `vekDialog`,在 `OnEditRow` 里弹你自己的对话框(库里有 `TyTextQuery`);只读的设 `ReadOnly`。

### 8.3 写回:`OnValueChanging`

用户每提交一次,值进行之前先到 `OnValueChanging`。在这里去问远端,它答应了才放行:

```pascal
procedure TInspector.ValueChanging(Sender: TObject; ARow: TTyValueRow;
  var AText: string; var AAllow: Boolean);
var
  Owner: TPropDesc;
  Stored: string;
begin
  if (ARow.Parent <> nil) and DescAt(VLE.RowPath(ARow.Parent), Owner) and (Owner.Kind = pkSet) then
    { 集合的一个元素:把整个集合写过去 }
    AAllow := WriteAll(Owner.Path, SetWith(ARow, AText), Stored)
  else
  begin
    AAllow := WriteAll(VLE.RowPath(ARow), AText, Stored);
    if AAllow then AText := Stored;      // 行里显示远端实际存下的值:输入 007,显示 7
  end;
end;

procedure TInspector.ValueChanged(Sender: TObject; ARow: TTyValueRow);
var
  Owner: TPropDesc;
begin
  { 元素改了,集合那一行跟着变。这是宿主自己更新显示,直接写 Value,不必再问一遍 }
  if (ARow.Parent <> nil) and DescAt(VLE.RowPath(ARow.Parent), Owner) and (Owner.Kind = pkSet) then
  begin
    ARow.Parent.Value := Merged(Owner.Path);
    VLE.Invalidate;
  end;
end;
```

- **拒绝之后**:编辑框照常关闭,行保持原值,`OnValueChanged` 不触发。属性表格里属性写失败也是这样。要提示用户,在处理程序里自己弹。
- **远端的回答要等**:`OnValueChanging` 是同步的,两种做法都行。一是在处理程序里等到回答再返回;二是先拒绝(`AAllow := False`),把请求发出去,回答到了再直接写 `Row.Value` 并 `VLE.Invalidate`。
- **宿主自己更新显示**(远端说别的属性也跟着变了、定时刷新):直接写 `Row.Value` 再 `Invalidate`。这条路不问 `OnValueChanging`,也不触发 `OnValueChanged`。`SetRowValue` 是「替用户提交一次」,两个事件都会走。
- **字体行**(`vekFont`)带子行时只在字体行上问一次,选好的字体从 `VLE.CommitFont` 读;答应之后子行跟着更新,不再逐个问。

### 8.4 换一个对象:重建行,展开状态和当前行不丢

选中另一个对象就把行全部重建。重建前把展开着的行按路径存进一个列表,重建后照这个列表恢复;当前行也按路径找回来:

```pascal
procedure TInspector.Select(const AObjects: array of TRemoteObject);
var
  Current: string;
begin
  VLE.SaveExpanded(FOpen);                    // FOpen: TStringList,和检查器同寿命
  Current := VLE.RowPath(VLE.SelectedRow);
  SetSelection(AObjects);
  VLE.BeginUpdate;
  try
    VLE.Clear;
    BuildRows;
    VLE.RestoreExpanded(FOpen);
  finally
    VLE.EndUpdate;                            // 到这里才重建一次显示列表
  end;
  VLE.ItemIndex := VLE.DisplayIndexOf(VLE.FindRow(Current));
end;
```

`SaveExpanded` 是把列表**更新**到和现有的行一致:展开着的行,路径加进去;收起的,路径拿掉;现在没有对应行的路径原样留着。所以在按钮上展开过 `Font`,中间看了一个没有 `Font` 的对象,再回到按钮时 `Font` 还是展开的。`RestoreExpanded` 把列表里有的行展开,其余收起;想让分类一开始就展开,先往列表里放 `@Appearance` 这样的路径。只有带子行的行才算。

### 8.5 过滤

放一个 [TTyEdit](edit.md) 当搜索框:

```pascal
procedure TInspector.FilterEditChange(Sender: TObject);
begin
  VLE.FilterText := FilterEdit.Text;
end;
```

规则和属性表格的 `FilterText` 一样:

- 键里含这段文字的行显示(不分大小写,`Key` 和 `DisplayKey` 都算),它上面的各级父行也显示,并且为它展开;命中的行保留自己的子行。其余的行不显示。
- 标题行自己的文字不参与匹配,下面有命中的行它才显示。
- 过滤期间用户照样可以展开、收起。被过滤器展开的行收起之后,同一段文字不会再把它展开,换一段文字才会。
- 清空之后,每一行的展开状态回到过滤之前的样子。过滤期间调 `SaveExpanded` / `RestoreExpanded`,存取的也是过滤之前的状态,所以 8.4 的重建在过滤期间照样能用,新建的行马上就被过滤。
- 过滤不动行的 `Hidden`:你自己用 `Hidden` 藏起来的行一直藏着,也不会让它的父行算作「下面有命中」;被过滤掉的行,`Hidden` 仍然是 `False`。

想按别的条件匹配(值、类型、路径),用 `OnFilterRow`:

```pascal
procedure TInspector.FilterRow(Sender: TObject; ARow: TTyValueRow;
  const AFilter: string; var AMatch: Boolean);
begin
  if Pos(AFilter, LowerCase(ARow.Value)) > 0 then AMatch := True;   // 值里含也算
end;
```

### 8.6 同时检查多个对象

合并由宿主来做:只列出所有对象都有的属性,值一致就显示,不一致就让单元格空着。属性表格也是这样显示的。

```pascal
function TInspector.Merged(const APath: string): string;
var
  k: Integer;
begin
  Result := FObjects[0].Read(APath);
  for k := 1 to High(FObjects) do
    if FObjects[k].Read(APath) <> Result then Exit('');     // 不一致:空单元格
end;

function TInspector.WriteAll(const APath, AText: string; out AStored: string): Boolean;
var
  k: Integer;
begin
  Result := True;
  for k := 0 to High(FObjects) do
    if not FObjects[k].Write(APath, AText, AStored) then Exit(False);
end;
```

空单元格点开是空的编辑框,输入什么就写进每一个对象。想让「不一致」更显眼,把 `DisplayValue` 设成 `(多个值)` 之类的文字,`Value` 仍然留空:显示的是 `DisplayValue`,编辑框里是 `Value`;写入成功后把 `DisplayValue` 清掉。

### 8.7 颜色行给哪些颜色

颜色行的下拉列表默认只有 16 种基本颜色加「更多…」。组件的颜色多半是 `clBtnFace`、`clDefault` 这样的系统颜色,用 `OnGetRowColors` 把整套颜色名换进去(属性表格给的就是这一套):

```pascal
uses tyControls.ColorBox;

procedure TInspector.RowColors(Sender: TObject; ARow: TTyValueRow; AColors: TStrings);
begin
  TyBuildColorPalette(AColors, [cbStandardColors, cbExtendedColors, cbSystemColors,
    cbIncludeNone, cbIncludeDefault]);
end;
```

### 8.8 属性表格替你做了、这里要自己做的

| 事情 | 属性表格 | 用值列表编辑器自己做 |
|---|---|---|
| 行从哪来 | 读 RTTI | 按描述 `AddRow` / `AddChild`(8.2) |
| 写回 | 调属性的 setter | `OnValueChanging` 里交给远端(8.3) |
| 写之前拦一下 | `OnPropertyChanging` | 同一个 `OnValueChanging` |
| 写失败 | `OnPropertyError`,行保持原值 | `AAllow := False`,行保持原值 |
| 分类 | `ShowCategories` | 标题行 `Heading` |
| 按名字过滤 | `FilterText` | `FilterText`,规则相同(8.5) |
| 展开状态跨对象保留 | `ExpandedProperties` | `SaveExpanded` / `RestoreExpanded`(8.4) |
| 行的路径 | `RowPath` | `RowPath` / `FindRow`,写法相同 |
| 多个对象 | `SelectObjects` | 宿主合并,不一致留空(8.6) |
| 颜色列表 | 全套颜色名 | `OnGetRowColors`(8.7) |
| 字符串列表、集合项 | 内置对话框和右键菜单 | `vekDialog` + `OnEditRow`,自己弹窗、自己重建行 |
| 值变了刷新显示 | `Refresh` | 直接写 `Row.Value`,再 `Invalidate` |

这套做法有一份能跑的,在 `tests/test.rowinspector.pas`:`TFarObject` 是远端,`TFarInspector` 是宿主,整个单元没有用到 `TPersistent`。

---

## RTL 镜像：**不做**，并且是钉死的

本控件覆写了 `TTyCustomListBox.RtlRowLayout` 返回 `False`，所以在 `BiDiMode = bdRightToLeft` 的窗体上它保持从左往右——基类的行矩形、行文字、滚动条边都不跟着翻。

理由不是"来不及"，而是这个控件把 x 算了两遍：分隔条拖动（`OverSplit`）、点在哪一列上开编辑器、以及展开 chevron，都是从 `ContentLeftDp` / `SplitXDp` / `ContentRightDp` 算的（`:536`、`:576`、`:1542`），而 `PaintItemContent` 画的时候是从传进来的 `ARowRect` 切的（`:1426`）；`ContentRightDp` 甚至自己把滚动条从右边减掉了一次。基类一翻行矩形而这三处不动，分隔条就会画在一处、抓在另一处——正是这一轮一直在清的那类 bug。

**要拿掉这个覆写，先把两份算术并成一份**：让单元格矩形和命中都从 `CellRect` 来，然后镜像 `CellRect`。守卫在 `tests/test.rtl.pas` 的 `TRtlExclusionTest.ValueListEditorIsNotMirroredWhileItsSplitterIsHitTestedTwice`——先并再翻，覆写去掉的那一刻它会告诉你。
