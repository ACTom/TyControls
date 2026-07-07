# TTyColorComboBox

## 1. 概述

TTyColorComboBox 是 [TTyColorBox](colorbox.md) **加一个末尾"更多…"行**:选中它会弹出主题化的取色对话框([TTyColorDialog](../controls.md)),挑好的颜色被**插入到"更多…"之前并选中**。除此之外(色块+名、`Selected`、`Items.Objects` 存色、锁 `csDropDownList`)全部继承自 `TTyColorBox`。

"更多…"行用 **`clNone` 作哨兵**标记——所以它渲染成**纯文字(无色块)**,也无需额外标志位就能识别;它始终保持在最后,新加的自定义色排到它上面。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ColorComboBox` |
| typeKey | `'TyComboBox'` / `'TyListItem'`(经 `TTyColorBox` 继承)|

无新增 `.tycss`。

```pascal
uses tyControls.ColorComboBox;
```

---

## 3. 属性 / 方法

| 成员 | 说明 |
|------|------|
| `MoreCaption: string` | "更多…"行的文字(默认 `More…`);改动会重建该行。 |

另继承 [TTyColorBox](colorbox.md) 的 `Selected` / `AddColor` / `ClearColors` / `ColorAt`。

---

## 4. 机制

- 弹出列表用 `TTyColorMorePopupList`(经 `CreatePopupList` 注入):颜色为 `clNone` 的行画纯文字,其余画色块+名。
- `PaintFieldContent` 同理:选中"更多…"时字段显示纯文字。
- 覆写 `DoSelect`:选中"更多…"→ `TySelectColor` 弹对话框;OK 则 `Items.InsertObject` 把新色插到"更多…"前并选中,取消则恢复上次选择。

---

## 5. 代码示例

```pascal
uses tyControls.Controller, tyControls.ColorComboBox, Graphics;

var CB: TTyColorComboBox;
CB := TTyColorComboBox.Create(Self);
CB.Parent := Self;
CB.SetBounds(20, 20, 180, 28);
CB.MoreCaption := '自定义…';
CB.Selected := clNavy;
// 用户从下拉里选"自定义…"即可弹取色对话框挑任意色
```

---

## 6. 注意事项

- **哨兵是 clNone:** 真实颜色永不会是 `clNone`,所以用它标记"更多…"行安全无歧义。
- **取色对话框:** 复用现成的 `TySelectColor`(S3 取色器);挑的色会持久追加到列表里。
