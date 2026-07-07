# TTyOfficeComboBox

## 1. 概述

TTyOfficeComboBox 是**下拉列表带分组标题行的组合框**(Office 风格分组组合框)。继承自 [TTyComboBox](combobox.md),用一个自绘弹出列表(`TTyOfficeComboPopupList`)把**标题行**画成着色带 + 加粗文字,**普通行**同 `TTyListBox`。某行是不是标题,存在 `Items.Objects[i]`(`1`=标题,`0`=普通条目),排序 / 删除都跟着走;弹出列表的 Items 由 `Assign` 从组合框拷贝,标志随之带过去。用 `AddHeader` / `AddItem` 构建列表。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.OfficeComboBox` |
| typeKey | `'TyComboBox'`(字段)/ `'TyListBox'` / `'TyListItem'`(弹出行)+ `'TyGroupBox'`(标题带)|

无新增 `.tycss`。标题带文字色取自 `'TyGroupBox'` 主题;若该 token 底色为透明(多数主题如此),则从主题文字色派生一层半透明底,使分组带在任何主题下都可见(仍是主题色派生,非硬编码)。

```pascal
uses tyControls.OfficeComboBox;
```

---

## 3. 属性 / 方法 / 事件

| 成员 | 说明 |
|------|------|
| `AddHeader(const S)` | 追加一条分组标题行(着色带 + 加粗,不可选)。 |
| `AddItem(const S)` | 追加一条普通条目行(可选)。 |
| `IsHeader(AIndex): Boolean` | 第 i 行是否为标题行。 |

另继承 `TTyComboBox` 的 `Items` / `ItemIndex` / `Text` / `Sorted` / `OnChange` / `OnSelect` 等。

---

## 4. 交互

- 弹出列表里点击**普通行** → 正常选中并关闭。
- 点击**标题行** / 键盘导航落到标题行 / 代码设 `ItemIndex` 为标题行 → 自动重定向到该组最近的可选条目(所有选择路径都经覆写的 `SelectItem` 汇聚,标题行永不可被选中)。
- **只读:** 控件锁定为 `csDropDownList`(仅从列表挑选);分组组合框本就是挑选式,可编辑模式的前缀过滤会绕过标题保护,故忽略改成 `csDropDown` 的尝试。

---

## 5. 代码示例

```pascal
uses tyControls.Controller, tyControls.OfficeComboBox;

var CB: TTyOfficeComboBox;
CB := TTyOfficeComboBox.Create(Self);
CB.Parent := Self;
CB.SetBounds(20, 20, 180, 26);
CB.AddHeader('水果');
CB.AddItem('苹果');
CB.AddItem('芒果');
CB.AddHeader('蔬菜');
CB.AddItem('胡萝卜');
CB.ItemIndex := 1;   // 选中"苹果"
```

---

## 6. 注意事项

- **Objects 被占用:** 标题标志存在 `Items.Objects[i]`——**别再用 `Objects` 存自己的数据**(并行数组会在排序时错位)。
- **自包含:** 本单元不引用 `TTyOfficeListBox`,自带弹出列表与标题带绘制。
- **标题带随主题:** 文字色来自 `'TyGroupBox'` token;底色透明时从主题文字色派生半透明底,均不硬编码。
- **交互是真机验证项:** 纯状态逻辑(`AddHeader` / `AddItem` / `IsHeader` / 标题不可选重定向)已 headless 单测;弹出、点击选择需真机验证。
