# TTyOfficeListBox

## 1. 概述

TTyOfficeListBox 是**带分组标题行的列表框**(Office 风格分组列表)。继承自 [TTyListBox](listbox.md),覆写 `PaintItemContent`:**标题行**画一条着色带 + 加粗文字,**普通行**同 `TTyListBox`。某行是不是标题,存在 `Items.Objects[i]`(`1`=标题,`0`=普通条目),与条目天然对齐(排序 / 删除都跟着走,不会错位)。标题行**不可选中**——点击会被吞掉。用 `AddHeader` / `AddItem` 构建列表。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.OfficeListBox` |
| typeKey | `'TyListBox'` / `'TyListItem'`(行)+ `'TyGroupBox'`(标题带)|

无新增 `.tycss`。标题带文字色取自 `'TyGroupBox'` 主题;若该 token 底色为透明(多数主题如此),则从主题文字色派生一层半透明底,使分组带在任何主题下都可见(仍是主题色派生,非硬编码)。

```pascal
uses tyControls.OfficeListBox;
```

---

## 3. 属性 / 方法 / 事件

| 成员 | 说明 |
|------|------|
| `AddHeader(const S)` | 追加一条分组标题行(着色带 + 加粗,不可选)。 |
| `AddItem(const S)` | 追加一条普通条目行(可选)。 |
| `IsHeader(AIndex): Boolean` | 第 i 行是否为标题行。 |

另继承 `TTyListBox` 的 `Items` / `ItemIndex` / `OnChange` / `Sorted` 等。

---

## 4. 交互

- 点击**标题行** → 被吞掉,不选中、不改变 `ItemIndex`。
- 点击**普通行** → 正常选中(同 `TTyListBox`)。
- **键盘上下 / `Home` / `End` / 代码设 `ItemIndex`** → 若落到标题行,自动按移动方向跳到相邻的可选条目;标题行在**任何路径**(键盘 / 程序 / 鼠标)都不可选。

---

## 5. 代码示例

```pascal
uses tyControls.Controller, tyControls.OfficeListBox;

var LB: TTyOfficeListBox;
LB := TTyOfficeListBox.Create(Self);
LB.Parent := Self;
LB.SetBounds(20, 20, 200, 240);
LB.AddHeader('水果');
LB.AddItem('苹果');
LB.AddItem('芒果');
LB.AddHeader('蔬菜');
LB.AddItem('胡萝卜');
```

---

## 6. 注意事项

- **Objects 被占用:** 标题标志存在 `Items.Objects[i]`——所以**别再用 `Objects` 存自己的数据**(并行数组会在排序时错位)。
- **标题带随主题:** 底色 / 文字色来自 `'TyGroupBox'` token,不硬编码;要让标题带显色,选一个给 `TyGroupBox` 配了不透明背景的主题。
- **交互是真机验证项:** 纯状态逻辑(`AddHeader` / `AddItem` / `IsHeader` / 排序不错位)已 headless 单测;鼠标吞点击需真机验证。
