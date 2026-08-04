# TTyMRUComboBox

## 1. 概述

TTyMRUComboBox 是**带最近使用历史(MRU)的可编辑下拉框**。继承自 [TTyComboBox](combobox.md),构造时即为 `csDropDown`(可编辑)。用户输入或从下拉列表挑选一个值后,该值会**冒泡到列表顶部**;重复值(大小写不敏感)会被去重后上移,而不是产生副本。列表长度上限由 `MaxItems` 控制,超出时最旧的条目从尾部丢弃。外观与 `TTyComboBox` 完全一致(条目为纯文本,复用 `'TyComboBox'` 主题样式)。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.MRUComboBox` |
| typeKey | `'TyComboBox'`(继承自基类,无新增)|

无新增 `.tycss`。

```pascal
uses tyControls.MRUComboBox;
```

---

## 3. 属性 / 方法 / 事件

| 成员 | 说明 |
|------|------|
| `MaxItems: Integer` | 记住的最大条目数(默认 10,最小 1)。调小时会立即裁掉尾部多余条目。 |
| `AddToHistory(const S: string)` | 把 `S`(去首尾空白;空串忽略)插入历史顶部。若已存在(大小写不敏感)则上移而非重复;随后按 `MaxItems` 裁尾,并选中新条目(`ItemIndex := 0`)。这是本控件的固有 API 名;冒泡 / 去重 / 裁尾本身**转调基类的 `AddHistoryItem`**(见 [TTyComboBox](combobox.md)),参数固定为"大小写不敏感、不带对象、上限 = `MaxItems`"。 |

另继承 `TTyComboBox` 的 `Items` / `ItemIndex` / `Text` / `OnChange` / `OnSelect` 等。

---

## 4. 交互

- **从下拉挑选一个值** → 触发基类 `DoSelect`,该值自动 `AddToHistory` 冒泡到顶部。
- **在编辑框输入新值后失焦(Tab / 点击别处)** → 该值自动记录到历史顶部(经基类 `DoEditorCommit` 钩子;这是新输入值进入历史的路径,因为 `DoSelect` 只在下拉挑选时触发)。
- **重复挑选 / 输入一个已有值** → 上移到顶部,不产生副本,总条目数不变。
- **手动记录** → 代码里显式调用 `AddToHistory`(例如把一次成功的搜索词存进历史)。

---

## 5. 代码示例

```pascal
uses tyControls.Controller, tyControls.MRUComboBox;

var MRU: TTyMRUComboBox;
MRU := TTyMRUComboBox.Create(Self);
MRU.Parent := Self;
MRU.SetBounds(20, 20, 200, 26);
MRU.MaxItems := 8;

// 记录一次输入(例如搜索确认后)
MRU.AddToHistory(MRU.Text);
// 顶部即最近一次:MRU.Items[0]
```

---

## 6. 注意事项

- **可编辑模式:** 控件构造即 `csDropDown`,别再改回 `csDropDownList`(那样就失去了"记住输入值"的意义)。
- **去重是大小写不敏感的:** `AddToHistory('File')` 与 `AddToHistory('file')` 视为同一条,只保留最新一次的写法冒泡到顶部。折叠规则与基类 `AddHistoryItem(…, ACaseSensitive := False)` 完全一致(**行为变更**:改为转调基类后,非 ASCII 字母如 `'Café'` / `'CAFÉ'` 也会被折叠成一条;此前只折叠 ASCII,会留下两条)。
- **排序无意义且安全:** MRU 顺序是"最近"而非字母序;`AddToHistory` 记录时强制取消排序**且不再恢复**,故即使误设 `Sorted:=True` 也不会崩溃、也不会把历史重排成字母序。这一点与基类 `AddHistoryItem` 不同——基类临时关掉 `Sorted` 后会恢复,恢复时就重排了(见 [TTyComboBox](combobox.md) 的说明)。
- **交互是真机验证项:** 纯逻辑(顺序 / 去重冒泡 / 裁尾 / 空串忽略 / 排序不崩溃)已 headless 单测;鼠标挑选(`DoSelect`)与失焦记录(`DoEditorCommit`)的链路需真机验证。
