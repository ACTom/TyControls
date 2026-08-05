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
| `Keys[i]` | 第 i 根行的键(只读)。 |
| `Values[key]` | **按键**读写根行的值(与 LCL / Delphi 的 `TValueListEditor.Values[const Key: string]` 同义)。查找**不分大小写**;写一个**不存在的键会追加一行**——移植过来的代码正是这样填这个控件的。 |
| `ValueFromIndex[i]` | **按行号**读写根行的值,与 `Keys[i]` 配对(名字取自 RTL 自己的 `TStrings.Values[Name]` / `ValueFromIndex[Index]` 一对)。 |
| `DeleteRow(i)` / `Clear` | 删根行 / 清空。 |
| `SetExpanded(ARow, bool)` | 展开/收起。 |
| `UpdateRows` | 直接 `AddChild` 加了子行后调用,刷新可见列表。 |
| `SetRowValue(ARow, AText)` | 按行对象改值(触发 `OnValueChanged`,并**向上更新复合父行**——见 §6)。 |
| `InvokeRowDialog(flat)` | 编程触发 `vekFont`/`vekDialog` 行的对话框(等同点"…")。 |
| `KeyColumnWidth` | 键列宽 / 分隔线位置(逻辑 px,默认 110,可拖)。 |
| `ReadOnly` / `Images` / `OnValueChanged(Sender, ARow)` | 全局只读 / 值单元图像源 / 值提交事件。 |

**`TTyValueRow`**:`Key`、`DisplayKey`、`Value`、`DisplayValue`、`EditorKind`、`EnumValues`、`ReadOnly`、`Bold`、`TextColor`、`ImageIndex`、`Expanded`;`AddChild(k,v)` / `ChildCount` / `Child[i]` / `Parent` / `HasChildren` / `EffectiveKey` / `EffectiveValue`。

---

## 4. 交互

- **点值列** → 按该行 `EditorKind` 编辑:文本(可选中/复制,数字类型限数字)/ 布尔·枚举·颜色下拉 / 字体·自定义先进入可编辑文本、**点尾部"…"** 才弹对话框;**点键列** → 选中该行。选中行按 **F2 / Enter** 也进入编辑。
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

## RTL 镜像：**不做**，并且是钉死的

本控件覆写了 `TTyListBox.RtlRowLayout` 返回 `False`，所以在 `BiDiMode = bdRightToLeft` 的窗体上它保持从左往右——基类的行矩形、行文字、滚动条边都不跟着翻。

理由不是"来不及"，而是这个控件把 x 算了两遍：分隔条拖动（`OverSplit`）、点在哪一列上开编辑器、以及展开三角，都是从 `ContentLeftDp` / `SplitXDp` / `ContentRightDp` 算的（`:536`、`:576`、`:1542`），而 `PaintItemContent` 画的时候是从传进来的 `ARowRect` 切的（`:1426`）；`ContentRightDp` 甚至自己把滚动条从右边减掉了一次。基类一翻行矩形而这三处不动，分隔条就会画在一处、抓在另一处——正是这一轮一直在清的那类 bug。

**要拿掉这个覆写，先把两份算术并成一份**：让单元格矩形和命中都从 `CellRect` 来，然后镜像 `CellRect`。守卫在 `tests/test.rtl.pas` 的 `TRtlExclusionTest.ValueListEditorIsNotMirroredWhileItsSplitterIsHitTestedTwice`——先并再翻，覆写去掉的那一刻它会告诉你。
