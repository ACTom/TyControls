# TTyFilterComboBox

## 概述

`TTyFilterComboBox` 是一个列出**过滤预设**的下拉框(`TTyComboBox` 子类)。把一条 LCL 过滤串
(`'文本 (*.txt)|*.txt|所有文件|*.*'`)解析成若干段,每段的 Caption 作为一行;选中某段后,该段的
模式串就是生效的 `Mask` —— 文件列表读它:`List.Mask := FilterCombo.Mask`。

锁 `csDropDownList`(选择型,不可编辑)。**零新增主题 token**(继承 `TTyComboBox`)。

## 用法

```pascal
uses tyControls.FilterComboBox;

Filter := TTyFilterComboBox.Create(Self);
Filter.Parent := Panel1;
Filter.ShellListView := List;              // 接上文件列表:选行即自动改它的 Mask
Filter.Filter := '文本 (*.txt)|*.txt|所有文件|*.*';
```

`ShellListView` 在对象查看器里赋值即可,**不需要**任何 handler。要在换掩码时另做别的事,再接
`OnFilterChange`(它在掩码已经推给列表**之后**触发,所以 handler 读到的列表是新的):

```pascal
Filter.OnFilterChange := @FilterChanged;
```

## 属性 / 方法 / 事件

| 成员 | 说明 |
|---|---|
| `Filter: string` | LCL 过滤串。写它重新解析并重建下拉;**不触发** `OnFilterChange`(初始化用,随后直接读 `Mask`)。 |
| `FilterIndex: Integer` | 生效段,**1-based**(LCL 约定)。写它选中该段并触发 `OnFilterChange`。默认 `1`。 |
| `Mask: string` | 只读:生效段的模式串(`FSpecs[FilterIndex-1].Patterns`),无段时 `''`。等价 `TyFsFilterPatterns(Filter, FilterIndex)`。 |
| `ShellListView` | 设计期可赋值的**目标文件列表**:选行即把新 `Mask` 推给它。这是本控件存在的意义,而它以前是缺的 —— 每个过滤下拉都得手写一个把 `Mask` 抄过去的 `OnFilterChange`,而且一个带 `ShellListView = ShellListView1` 的移植 `.lfm` 会加载失败。对应 `filectrl.pp:167`(published 在 `:195`,推送在 `Select` `:551`,解链在 `Notification` `:565`)。 |
| `OnFilterChange` | 生效掩码变化时触发(用户选行 / 写 `FilterIndex`)。在掩码**已经**推给 `ShellListView` 之后才触发。 |
| `class procedure ConvertFilterToStrings(AFilter, AStrings, AClearStrings, AAddDescription, AAddFilter)` | 把过滤串解析进**调用方给的** `TStrings` —— LCL `filectrl.pp:163-164` 的同名类方法,参数逐个对齐,移植代码原样能编。`AClearStrings = False` 是**追加**模式:自由函数 `TyFsParseFilter` 表达不了它(它返回一个全新的记录数组),所以"把一条过滤并进一个已有列表"以前没有办法。 |

## 关键设计

- **锁 `csDropDownList`**:可编辑下拉会前缀过滤行,行索引会对不上解析出的段数组(ColorBox 的坑)。
- **每行的模型索引存进 `Objects[]`**(`TObject(PtrInt(i))`),读、写两侧都经它取段 —— 即便被 `Sorted` 重排,
  数据映射也不错(读侧 `DoSelect` 与写侧 `SelectModel` 都扫 `Objects[]`)。
- 畸形 / 空过滤串不崩:`TyFsParseFilter` 保证 `''` → 无行、无管道的标题 → 一段 `Patterns=''`。

## 消费者

Phase 7 文件对话框(`TTyOpenDialog`/`TTySaveDialog`)底部的类型过滤下拉。见
`docs/superpowers/specs/2026-07-11-phase7-shell-filedialogs-design.md`。
