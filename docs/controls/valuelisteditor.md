# TTyValueListEditor

## 1. 概述

TTyValueListEditor 是**属性检查器级的名/值两列编辑器**:左列是**键**(可展开的多级树,带三角),右列是**可编辑的值**,中间是**可拖动的分隔条**。每行是一个 `TTyValueRow` 对象——`Key`/`DisplayKey`、`Value`/`DisplayValue`、值类型 `EditorKind`、`ReadOnly`、逐行样式(`Bold`/`TextColor`/`ImageIndex`)以及**子行**(嵌套)。用 `AddRow`(返回行对象,便于嵌套 / 定类型 / 设样式)构建,或用简单的 `InsertRow(key, value)`。行布局、选择、滚动来自 [TTyListBox](listbox.md);值单元用主题化 [TTyEdit](edit.md) 覆盖层就地编辑。

> **分层建设:** 本层(地基)= 行对象模型 + 多级树 + 分隔拖动 + 只读 + `DisplayKey`/`DisplayValue` + 值加粗/变色/图标 + **文本**内联编辑。**类型编辑器**(布尔 / 枚举 / 颜色下拉 / 字体 · "…" 对话框)按 `EditorKind` 分派,后续层加入。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ValueListEditor` |
| 类型 | `TTyValueListEditor` + `TTyValueRow` + `TTyValueEditorKind` |
| typeKey | `'TyListBox'` / `'TyListItem'`(行)+ 值编辑器用 `'TyEdit'` |

无新增 `.tycss`。

```pascal
uses tyControls.ValueListEditor;
```

---

## 3. 关键成员

**`TTyValueListEditor`**

| 成员 | 说明 |
|------|------|
| `AddRow(AKey, AValue): TTyValueRow` | 追加一根行,返回它(可继续 `AddChild` 嵌套 / 设 `EditorKind` / 样式)。 |
| `InsertRow(AKey, AValue)` | 简单形式,追加纯文本根行。 |
| `Row(AIndex): TTyValueRow` / `RowCount` | 第 i 根行 / 根行数。 |
| `VisibleRowCount` | 可见(展开后)行数。 |
| `Keys[i]` / `Values[i]` / `ValueOf[key]` | 根行的键/值读写(`Values[]` 写会触发 `OnValueChanged`)。 |
| `DeleteRow(i)` / `Clear` | 删根行 / 清空。 |
| `SetExpanded(ARow, bool)` | 展开/收起。 |
| `UpdateRows` | 直接 `AddChild` 加了子行后调用,刷新可见列表。 |
| `KeyColumnWidth` | 键列宽 / 分隔线位置(逻辑 px,默认 110,可拖)。 |
| `ReadOnly` / `Images` / `OnValueChanged(Sender, ARow)` | 全局只读 / 值单元图像源 / 值提交事件。 |

**`TTyValueRow`**:`Key`、`DisplayKey`、`Value`、`DisplayValue`、`EditorKind`、`EnumValues`、`ReadOnly`、`Bold`、`TextColor`、`ImageIndex`、`Expanded`;`AddChild(k,v)` / `ChildCount` / `Child[i]` / `HasChildren` / `EffectiveKey` / `EffectiveValue`。

---

## 4. 交互

- **点值列** → 就地编辑(文本);**点键列** → 选中该行。选中行按 **F2 / Enter** 也进入编辑。
- **点键列前的三角** → 展开/收起子行。
- **拖分隔条**(光标变 ↔)→ 调整键/值列宽。
- 编辑中:**Enter** / 点别处 / 失焦 → 提交;**Esc** → 取消。`ReadOnly` 行 / 全局 `ReadOnly` 不可编辑。

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

Row := VLE.AddRow('Font', '(TFont)');  // 多级
Row.AddChild('Size', '9');
Row.AddChild('Bold', 'False');
VLE.UpdateRows;                        // 直接加子行后刷新

VLE.OnValueChanged := @HandleChange;   // (Sender; ARow: TTyValueRow)
```

---

## 6. 注意事项

- **`AddChild` 后要 `UpdateRows`:** 行对象是直接被你改的,控件观察不到;`AddRow` / `InsertRow` / `DeleteRow` / `SetExpanded` 会自己刷新,只有直接 `AddChild` 需要手动 `UpdateRows`。
- **`DisplayKey`/`DisplayValue`:** 仅影响显示,不改实际 `Key`/`Value`(供 i18n / 格式化);值单元还可带 `ImageIndex`(图文)+ `Bold` / `TextColor`。
- **内联编辑器是内部子控件:** `csNoDesignVisible`,不漏进设计器;`Enter`/失焦提交、`Esc` 取消,主题跟随 `Controller`;滚动会先提交并关闭。
- **交互是真机验证项:** 数据 / 嵌套 / 展开 / 显示覆盖 / 只读 / 列宽钳制已 headless 单测;分隔拖动、三角点击、内联编辑器显示需真机验证。
