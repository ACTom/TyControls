# TTyValueListEditor

## 1. 概述

TTyValueListEditor 是**属性检查器级的名/值两列编辑器**:左列是**键**(可展开的多级树,带三角),右列是**可编辑的值**,中间是**可拖动的分隔条**。每行是一个 `TTyValueRow` 对象——`Key`/`DisplayKey`、`Value`/`DisplayValue`、值类型 `EditorKind`、`ReadOnly`、逐行样式(`Bold`/`TextColor`/`ImageIndex`)以及**子行**(嵌套)。用 `AddRow`(返回行对象,便于嵌套 / 定类型 / 设样式)构建,或用简单的 `InsertRow(key, value)`。行布局、选择、滚动的**代码**来自 [TTyListBox](listbox.md)(但主题令牌自成一套,见 §2);值单元用主题化 [TTyEdit](edit.md) 覆盖层就地编辑。

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
- **`vekDialog` 就是"用户侧自定义"入口**:一个 `OnEditRow` 事件覆盖全部 `vekDialog` 行,在处理器里按 `ARow.Key`(或行对象)分派到各自的动作——弹只读的关于框、选路径、跳消息框皆可。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ValueListEditor` |
| 类型 | `TTyValueListEditor` + `TTyValueRow` + `TTyValueEditorKind` |
| `GetStyleTypeKey` 返回值 | `'TyValueListEditor'`(自己的键,不是祖先 `TTyListBox` 的) |

它**只是复用**了 `TTyListBox` 的虚拟化行循环,并不是一个列表框:它画的两列 + 可拖分隔条、带缩进的键列、
逐行展开三角、带色块和"…"按钮的值列,列表框一样都没有。挂在 `TyListBox`/`TyListItem` 上时,皮肤既没法
给键列单独上色、没法给分隔条定色、没法改三角样式,也没法让检查器的选中行读起来与普通列表的选中行不同。
现在的部件表:

| typeKey | 画什么 |
|---|---|
| `TyValueListEditor` | 外框:背景、边框、圆角、内边距 |
| `TyValueListEditorRow` | 一根行(`GetItemStyleTypeKey`),含 `:hover` / `:active`(选中) |
| `TyValueListEditorKey` | 键列文字色 |
| `TyValueListEditorValue` | 值列**默认**文字色(逐行的 `TextColor` 覆盖仍然优先) |
| `TyValueListEditorDivider` | 键/值分隔线(读 `background`) |
| `TyValueListEditorExpander` | 展开/收起三角的填充色 |

> 后四个是**可选钩子**:`themes/light.tycss` 有意不定义它们,因为它们的后备值**随行状态而变**——
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
| `VisibleRowCount` | **(API parity 变更,破坏性)视口**里现在装得下几行 —— 即 LCL `TCustomGrid.VisibleRowCount` 的含义(`grids.pas:1301`,实现 `:2274`),`TValueListEditor` 经 `TCustomStringGrid` → `TCustomDrawGrid`(`:1538` public 转发)继承而来,因为在那边这个类**就是**一个 grid。**它不是"有几行展开着"** —— 那是 `DisplayRowCount`。两者都是 `Integer`、都是 public,所以移植来的翻页算式编译得过、算出垃圾:500 行展开着就一次翻 500 行。与 LCL 一致到那个差一:答的是 `VisibleGrid.Bottom - VisibleGrid.Top`,比"碰到视口的行数"少一行(翻页留一行重叠);整份列表都装得下时不留重叠。这与 `TTyCustomGrid` 在 03c29b3 修的是同一个撞名,当时没落到这个类上,因为我们这个是 `TTyListBox` 不是 grid。 |
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

**`TTyValueRow`**:`Key`、`DisplayKey`、`Value`、`DisplayValue`、`EditorKind`、`EnumValues`、`ReadOnly`、`Bold`、`TextColor`、`ImageIndex`、`Expanded`;`AddChild(k,v)` / `ChildCount` / `Child[i]` / `Parent` / `HasChildren` / `EffectiveKey` / `EffectiveValue`。

---

## 4. 交互

- **点值列** → 按该行 `EditorKind` 编辑:文本(可选中/复制,数字类型限数字)/ 布尔·枚举·颜色下拉 / 字体·自定义先进入可编辑文本、**点尾部"…"** 才弹对话框;**点键列** → 选中该行(开了 `keyEdit` 则**同时进入改名**)。选中行按 **F2 / Enter** 也进入编辑。
- **`KeyOptions` 开出来的手势**(默认全关,见 §7):**点键列 / Shift+F2** 改键名(`keyEdit`)、**Insert** 在当前位置插空行(`keyAdd`)、**Ctrl+Delete** 删当前根行(`keyDelete`)。
- **点键列前的三角** → 展开/收起子行。**层级无上限**(如 `Font → Style → Bold`)。
- **拖分隔条**(光标变 ↔)→ 调整键/值列宽。
- 编辑中:**Enter** / 点别处 / 失焦 → 提交;**Esc** → 取消。`ReadOnly` 行 / 全局 `ReadOnly` 不可编辑。
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
- **`AddChild` 后要 `UpdateRows`:** 行对象是直接被你改的,控件观察不到;`AddRow` / `InsertRow` / `DeleteRow` / `SetExpanded` 会自己刷新,只有直接 `AddChild` 需要手动 `UpdateRows`。
- **`DisplayKey`/`DisplayValue`:** 仅影响显示,不改实际 `Key`/`Value`(供 i18n / 格式化);值单元还可带 `ImageIndex`(图文)+ `Bold` / `TextColor`。
- **内联编辑器是内部子控件:** `csNoDesignVisible`,不漏进设计器;`Enter`/失焦提交、`Esc` 取消,主题跟随 `Controller`;滚动会先提交并关闭。
- **字体子行同步按键名匹配:** `vekFont` 行的直接子行里键名为 `Name`/`Size`/`Color` 或四个样式位 `Bold`/`Italic`/`Underline`/`StrikeOut`(也可放在嵌套 `Style` 节点下)会在选字体后被回写。**显示哪些子属性由你决定**——只 `AddChild` 你要暴露的那些即可(控件不设 `Options` 之类的隐藏开关,因为结构本就由你搭)。其它结构请自己在 `OnValueChanged` 里处理。
- **复合父行双向联动(Font / Style):** 改子行(如 `Bold`)会**向上**重算 `Style` 与 `Font` 的显示值(`Style`→`Regular`/`Bold, Italic`;`Font`→`Name, Size` + 尾随样式词);点 `Font` 的"…"选字体则**向下**回写全部子行并重算 `Style`/`Font`。编程改值用 `SetRowValue`(会触发同样的向上联动),别直接写 `ARow.Value`。仅 `style` 键名 + `Bold`/`Italic` 子行、及 `vekFont` 行被识别为复合;其它复合语义自理。
- **颜色"更多…"对话框是延迟弹的:** 走 `Application.QueueAsyncCall`,让弹出列表的鼠标事件先退栈(析构里 `RemoveAsyncCalls` 取消未决调用)。
- **交互是真机验证项:** 数据 / 嵌套 / 展开 / 显示覆盖 / 只读 / 列宽钳制 / 数字过滤已 headless 单测;分隔拖动、三角点击、下拉圆角、"…"按钮、颜色/字体对话框、字体子行回写需真机验证。

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

## RTL 镜像：**不做**，并且是钉死的

本控件覆写了 `TTyListBox.RtlRowLayout` 返回 `False`，所以在 `BiDiMode = bdRightToLeft` 的窗体上它保持从左往右——基类的行矩形、行文字、滚动条边都不跟着翻。

理由不是"来不及"，而是这个控件把 x 算了两遍：分隔条拖动（`OverSplit`）、点在哪一列上开编辑器、以及展开三角，都是从 `ContentLeftDp` / `SplitXDp` / `ContentRightDp` 算的（`:536`、`:576`、`:1542`），而 `PaintItemContent` 画的时候是从传进来的 `ARowRect` 切的（`:1426`）；`ContentRightDp` 甚至自己把滚动条从右边减掉了一次。基类一翻行矩形而这三处不动，分隔条就会画在一处、抓在另一处——正是这一轮一直在清的那类 bug。

**要拿掉这个覆写，先把两份算术并成一份**：让单元格矩形和命中都从 `CellRect` 来，然后镜像 `CellRect`。守卫在 `tests/test.rtl.pas` 的 `TRtlExclusionTest.ValueListEditorIsNotMirroredWhileItsSplitterIsHitTestedTwice`——先并再翻，覆写去掉的那一刻它会告诉你。
