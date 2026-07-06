# TTyMaskEdit

## 1. 概述

TTyMaskEdit 是**掩码编辑框**(日期 / 电话 / IP …),继承自 [TTyEdit](edit.md),复用它的文本引擎与 `'TyEdit'` 主题。**从左到右追加式录入**:每个键若匹配下一个可编辑槽就接受(自动补上字面量),否则拒绝;退格删除最后一个有效字符。显示的 `Text` 始终由有效字符经 `TyMaskApply` 推导——**没有独立模型需要同步**。`Mask=''` 时退化为普通编辑。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.MaskEdit` |
| `GetStyleTypeKey` | `'TyEdit'`(继承)|

无新增 `.tycss`。

```pascal
uses tyControls.MaskEdit;
```

---

## 3. 掩码码

| 码 | 含义 |
|----|------|
| `#` | 数字 `0-9` |
| `L` | 字母 `A-Za-z` |
| `C` | 任意非空格字符 |
| 其它 | **字面量**(如 `/` `-` `(` `)` 空格),自动插入 |

例:`##/##/####`(日期)、`(###) ###-####`(电话)、`###.###.###.###`(IP)。

---

## 4. 属性 / 方法

| 成员 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Mask` | `string` | `''` | 掩码模板;改变会清空当前内容。 |
| `IsComplete` | `function: Boolean` | — | 所有槽是否填满(可用于校验 / 门控 OK 按钮)。 |

另继承 [TTyEdit](edit.md) 的 `Text`(掩码后的显示串)/ `Alignment` / `OnChange` 等。

---

## 5. 行为

- **`UTF8KeyPress`**:提取当前有效字符 → 看下一个槽的类型 → 匹配则套用 `TyMaskApply` 重算 `Text`,否则吞掉。
- **`KeyDown` 退格**:删最后一个有效字符后重算。
- 纯函数 `TyMaskApply` / `TyMaskExtract` / `TyMaskNextSlot` / `TyMaskSlotAccepts` / `TyMaskIsComplete` 承载全部逻辑,已单元测试。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.MaskEdit;

TyDefaultController.LoadTheme('themes/light.tycss');

var D: TTyMaskEdit;
D := TTyMaskEdit.Create(Self);
D.Parent := Self;
D.SetBounds(20, 20, 160, 28);
D.Mask := '##/##/####';    // 键入 12312024 -> 显示 12/31/2024
// if D.IsComplete then ...
```

---

## 7. 注意事项

- **追加式:** 从左往右录入,不支持在中间插入编辑(掩码字段常态);光标始终停在末尾。
- **换掩码清空:** 设置新 `Mask` 会清空当前内容(掩码一般在使用前设定)。
- **粘贴:** 粘贴不走按键过滤;需要严格约束时靠 `IsComplete` 在提交处校验。
