# TTyAdvancedComboBox

## 1. 概述

TTyAdvancedComboBox 是一个**富行(rich row)下拉框**:下拉列表的每一项可带一张**左侧图片** + 一行**加粗标题(Title)** + 一行**暗色副标题(Subtitle)**;由于字段(field)很短,选中项在字段里**只画图片 + 标题**(单行)。它是 [TTyAdvancedListBox](advancedlistbox.md) 的下拉版孪生控件。

继承自 [TTyComboBox](../../source/tyControls.ComboBox.pas)。它自带**自己的弹出列表** `TTyAdvancedComboPopupList`(重写 `CreatePopupList` 返回),因此不依赖 `TTyAdvancedListBox` 存在;两者仅共用 `tyControls.AdvancedListBox` 里的行绘制 / 拆分辅助函数,保证字段、弹出行、独立列表框渲染一致。图片来自 [TTyVirtualImageList](../../source/tyControls.ImageCollection.pas)(按索引寻址)。

**数据模型(排序安全,无并行数组):** 与 [TTyAdvancedListBox](advancedlistbox.md) 完全相同 —— 两行文字合并成 `Title + LineEnding + Subtitle`,图片索引存进 `Items.Objects[i]`(`AImageIndex + 1`,`0` = 无图)。`Items.Assign` 把 `Objects[]` 一并复制进弹出列表,故弹出行读到同一批索引;排序按整段合并串比较(标题在前)。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.AdvancedComboBox` |
| typeKey | `'TyComboBox'`(字段,继承)/ 弹出行 `'TyListItem'`(继承)|

无新增 `.tycss`。副标题**复用 `TyListItem` 的 `TextColor`** 并降低 alpha,颜色仍随主题变化。

```pascal
uses tyControls.AdvancedComboBox;
```

---

## 3. 属性 / 方法 / 事件

| 成员 | 说明 |
|------|------|
| `Images: TTyVirtualImageList` | 栅格图片来源(按索引)。设置时注册 `FreeNotification`,列表先释放会自动置 nil。 |
| `AddItem(const ATitle, ASubtitle: string; AImageIndex: Integer)` | 追加一项富项。`ASubtitle` 可为 `''`;`AImageIndex < 0` 表示无图。 |
| `TitleOf(AIndex): string` | 该项的标题(越界返回 `''`)。 |
| `SubtitleOf(AIndex): string` | 该项的副标题(无副标题 / 越界返回 `''`)。 |
| `ImageIndexOf(AIndex): Integer` | 该项的图片索引;无图 / 越界返回 `-1`。 |

另继承 `Items` / `ItemIndex` / `Text` / `DropDownCount` / `Sorted` / `Style` / `OnChange` / `OnSelect` / `OnDropDown` / `OnCloseUp` / `Align` / `Anchors` / `StyleClass` / `Controller` 等。

---

## 4. 交互

- 与 [TTyComboBox](../../source/tyControls.ComboBox.pas) 一致:点击雪佛龙(chevron)展开 / 收起、方向键 / Home / End 选择、首字母 type-ahead、`Alt+Down` / `F4` 切换下拉、`Esc` 关闭。
- **字段**:选中项的图片 + 标题(单行居中,不画副标题)。
- **弹出行**:图片 + 标题(加粗)+ 副标题(小一号、暗一档),行高 40。

---

## 5. 主题

- **字段标题 / 弹出标题** — `FontName` / `TextColor`,字重固定 `700`(加粗)。
- **弹出副标题** — 同一 `FontName`,字号 = `ResolveFontSize - 2`,颜色 = `TextColor` 降低 alpha(仍是主题色)。
- **雪佛龙 / 边框 / 弹出背景** — 由基类按 `TyComboBox` / `TyListBox` / `TyListItem` 解析。

所有 chrome 颜色 / 尺寸均由主题 token 驱动,未硬编码。

---

## 6. 代码示例

```pascal
uses tyControls.ImageCollection, tyControls.AdvancedComboBox;

var
  Coll: TTyImageCollection;
  Imgs: TTyVirtualImageList;
  CB: TTyAdvancedComboBox;
begin
  Coll := TTyImageCollection.Create(Self);
  Coll.AddPicture('alice', AlicePic);   // AlicePic: TPicture
  Coll.AddPicture('bob',   BobPic);
  Imgs := TTyVirtualImageList.Create(Self);
  Imgs.Collection := Coll;
  Imgs.Names.Add('alice');   // index 0
  Imgs.Names.Add('bob');     // index 1

  CB := TTyAdvancedComboBox.Create(Self);
  CB.Parent := Self;
  CB.SetBounds(20, 20, 240, 28);
  CB.Images := Imgs;
  CB.AddItem('Alice', 'Senior Engineer', 0);
  CB.AddItem('Bob',   'Product Designer', 1);
  CB.AddItem('Carol', '', -1);   // 无副标题、无图
  CB.ItemIndex := 0;             // 字段显示 Alice 的图片 + 标题
end;
```

---

## 7. 注意事项

- **自带弹出列表:** `CreatePopupList` 返回 `TTyAdvancedComboPopupList`,并把其 `ItemHeight` 设为 40 以匹配两行行高;弹出行通过 `Owner` 回取本 combo 的 `Images`。
- **两行合并成一个 item / 图片索引在 `Objects[]`(偏移 +1):** 与 [TTyAdvancedListBox](advancedlistbox.md) 同一约定;用 `AddItem` / `TitleOf` / `SubtitleOf` 存取,不要直接改 `Items[i]`。
- **字段只画标题:** 字段短,故 `PaintFieldContent` 仅绘图片 + 标题(单行居中),不画副标题。
- **副标题颜色来自主题:** 只降 `TextColor` 的 alpha,不硬编码灰色。
- **绘制是真机验证项:** 数据逻辑(拆分、图片索引读写、排序保序)已 headless 单测;字段 / 弹出的图片渲染与排版需真机眼验。
