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
Filter.Filter := '文本 (*.txt)|*.txt|所有文件|*.*';
Filter.OnFilterChange := @FilterChanged;   // 生效掩码变了

procedure TForm1.FilterChanged(Sender: TObject);
begin
  List.Mask := Filter.Mask;   // 把新掩码交给文件列表
end;
```

## 属性 / 方法 / 事件

| 成员 | 说明 |
|---|---|
| `Filter: string` | LCL 过滤串。写它重新解析并重建下拉;**不触发** `OnFilterChange`(初始化用,随后直接读 `Mask`)。 |
| `FilterIndex: Integer` | 生效段,**1-based**(LCL 约定)。写它选中该段并触发 `OnFilterChange`。默认 `1`。 |
| `Mask: string` | 只读:生效段的模式串(`FSpecs[FilterIndex-1].Patterns`),无段时 `''`。等价 `TyFsFilterPatterns(Filter, FilterIndex)`。 |
| `OnFilterChange` | 生效掩码变化时触发(用户选行 / 写 `FilterIndex`)。 |

## 关键设计

- **锁 `csDropDownList`**:可编辑下拉会前缀过滤行,行索引会对不上解析出的段数组(ColorBox 的坑)。
- **每行的模型索引存进 `Objects[]`**(`TObject(PtrInt(i))`),读、写两侧都经它取段 —— 即便被 `Sorted` 重排,
  数据映射也不错(读侧 `DoSelect` 与写侧 `SelectModel` 都扫 `Objects[]`)。
- 畸形 / 空过滤串不崩:`TyFsParseFilter` 保证 `''` → 无行、无管道的标题 → 一段 `Patterns=''`。

## 消费者

Phase 7 文件对话框(`TTyOpenDialog`/`TTySaveDialog`)底部的类型过滤下拉。见
`docs/superpowers/specs/2026-07-11-phase7-shell-filedialogs-design.md`。
