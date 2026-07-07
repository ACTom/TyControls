# TTyValueListEditor

## 1. 概述

TTyValueListEditor 是**名/值两列编辑器**(轻量「属性表」):每行是一对 `键=值`,存在继承来的 `Items`(一个 `TStringList`,故 `Items.Names[i]` / `Items.ValueFromIndex[i]` 就是两列)。**键列**是只读标签,**值列**用一个主题化 [TTyEdit](edit.md) 覆盖层**就地编辑**(点值单元格,或在选中行按 `F2` / `Enter`;`Enter`/失焦提交,`Esc` 取消)。两列的分界由 `KeyColumnWidth`(逻辑 px)控制。行布局、选择、滚动都来自 [TTyListBox](listbox.md);一条细的主题色分隔线隔开两列。用 `InsertRow`(或 `Items.Add('键=值')`)构建,用 `Keys[]` / `Values[]` / `ValueOf[]` 读写。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ValueListEditor` |
| typeKey | `'TyListBox'` / `'TyListItem'`(行)+ 值编辑器用 `'TyEdit'` |

无新增 `.tycss`。

```pascal
uses tyControls.ValueListEditor;
```

---

## 3. 属性 / 方法 / 事件

| 成员 | 说明 |
|------|------|
| `InsertRow(const AKey, AValue)` | 追加一行 `键=值`。 |
| `DeleteRow(AIndex)` | 删除某行(会先结束进行中的编辑)。 |
| `RowCount: Integer` | 行数。 |
| `Keys[AIndex]: string` | 第 i 行的键(只读)。 |
| `Values[AIndex]: string` | 第 i 行的值(读/写;写会提交并触发 `OnValueChanged`)。 |
| `ValueOf[const AKey]: string` | 按键名读/写值(键不存在时读为 `''`)。 |
| `BeginEdit(ARow)` | 就地编辑某行的值(`ReadOnly` 或越界时空操作)。 |
| `EditingRow: Integer` | 正在编辑的行,或 `-1`。 |
| `KeyColumnWidth: Integer` | 键列宽度 / 分界线位置(逻辑 px,默认 100)。 |
| `ReadOnly: Boolean` | 为 `True` 时值列不可编辑(仅显示)。 |
| `OnValueChanged` | 值提交且发生变化后触发(带行号 / 键 / 新值)。 |

另继承 `TTyListBox` 的 `Items` / `ItemIndex` / `OnChange` 等。

---

## 4. 交互

- **点值列** → 就地弹出编辑框改该行的值;**点键列** → 仅选中该行(并提交正在进行的编辑)。
- 选中行按 **`F2` / `Enter`** → 开始编辑值。
- 编辑中:**`Enter`** / 点别处 / 失焦 → 提交;**`Esc`** → 取消。
- 编程 `Values[i] := ...` / `ValueOf['键'] := ...` 直接改值。

---

## 5. 代码示例

```pascal
uses tyControls.Controller, tyControls.ValueListEditor;

var VLE: TTyValueListEditor;
VLE := TTyValueListEditor.Create(Self);
VLE.Parent := Self;
VLE.SetBounds(20, 20, 260, 180);
VLE.KeyColumnWidth := 90;
VLE.InsertRow('宽度', '100');
VLE.InsertRow('高度', '50');
VLE.InsertRow('标题', '未命名');
VLE.OnValueChanged := @HandleValueChanged;   // (Sender; ARow; const AKey, AValue: string)
// 读回:VLE.ValueOf['宽度']
```

---

## 6. 注意事项

- **每行是 `键=值`:** `Items.NameValueSeparator` 被设为 `'='`;别把不含 `=` 的裸串塞进 `Items`。
- **值列可编辑、键列只读:** 首版键作为标签(不可改);需要改键名可另起扩展。
- **内联编辑器是内部子控件:** 打了 `csNoDesignVisible`,不会漏进窗体设计器;`Enter`/失焦提交、`Esc` 取消(同 TreeView 内联编辑);编辑器主题跟随本控件的 `Controller`。
- **编辑时列表滚动会先提交并关闭编辑器**(编辑器无法跟着行走);改列宽 / 缩放会让打开的编辑器随动;删掉正在编辑的行或其上方的行会取消编辑。
- **不要排序:** 值编辑器的行序是有意义的;`Sorted` 无意义(提交时会强制取消排序以避免 `TStringList` 报错)。键不能含 `=`(首个 `=` 即键/值分界),但值可以含 `=`。
- **交互是真机验证项:** 纯数据逻辑(增删 / 读写 / 按键名 / 空值 / 列宽钳制 / 只读拦截 / 排序不崩溃 / 值含等号)已 headless 单测;就地编辑器的显示、聚焦、滚动提交、销毁安全需真机验证。
