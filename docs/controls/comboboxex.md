# TTyComboBoxEx

## 1. 概述

TTyComboBoxEx 是**每个条目可带一张图片 + 文字**的下拉框。继承自 [TTyComboBox](combobox.md),覆写 `PaintFieldContent`(字段区)与自定义弹出列表的 `PaintItemContent`(下拉行),在图片右侧画文字——**字段和下拉里画的是同一套图文布局**(共享 `DrawImageText`)。

**图片索引存在 `Items.Objects[i]`(以 `索引 + 1` 保存,`0` 表示无图)**,与条目名天然对齐:排序 / 删除都跟着走,不会错位;下拉列表通过 `Items.Assign` 连 `Objects[]` 一起拷贝,所以下拉和字段读到的是同一份索引。图片来源为 [`TTyVirtualImageList`](imagecollection.md)(按索引寻址、`CachedIndex(索引, 像素尺寸)` 借用一张按目标像素缩放的缓存位图)。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ComboBoxEx` |
| typeKey | `'TyComboBox'`(字段)/ `'TyListBox'` `'TyListItem'`(下拉行)|

无新增 `.tycss`;文字颜色 / 字号 / 字重全部取自解析后的主题样式。

```pascal
uses tyControls.ComboBoxEx, tyControls.ImageCollection;
```

---

## 3. 属性 / 方法 / 事件

| 成员 | 说明 |
|------|------|
| `Images: TTyVirtualImageList` | 图片来源(按索引寻址)。赋值会登记 `FreeNotification`,来源先被释放时自动置空引用。 |
| `AddItem(const S: string; AImageIndex: Integer)` | 追加一个条目;`AImageIndex < 0` 表示无图(仅文字)。索引存进 `Items.Objects[]`。 |
| `ImageIndexOf(AIndex): Integer` | 读第 i 行的图片索引;无图 / 越界返回 `-1`。 |
| `DrawImageText(P; ARect; S; AImageIndex; AStyle)` | 共享绘制:左图右文。字段与下拉行都调它。 |

另继承 `TTyComboBox` 的 `Items` / `ItemIndex` / `Text` / `Sorted` / `DropDownCount` / `OnChange` / `OnSelect` 等。

---

## 4. 主题

- 文字用行 / 字段解析出的 `FontName` / 字号(`ResolveFontSize`)/ `FontWeight` / `TextColor`,不硬编码。
- 图片按行高自适应(`行高 - 6` 逻辑像素,最小 8px),纵向居中;由 `Images.CachedIndex` 按目标像素缩放(结果缓存复用),一份母图服务各 DPI。

---

## 5. 代码示例

```pascal
uses tyControls.Controller, tyControls.ComboBoxEx, tyControls.ImageCollection;

var
  Coll: TTyImageCollection;
  Imgs: TTyVirtualImageList;
  Cb: TTyComboBoxEx;
begin
  // 图片母库(名字 -> 母图)
  Coll := TTyImageCollection.Create(Self);
  Coll.AddPicture('save', SavePic);   // SavePic: TPicture
  Coll.AddPicture('open', OpenPic);

  // 按索引暴露的图片列表
  Imgs := TTyVirtualImageList.Create(Self);
  Imgs.Collection := Coll;
  Imgs.Names.Add('save');   // 索引 0
  Imgs.Names.Add('open');   // 索引 1

  Cb := TTyComboBoxEx.Create(Self);
  Cb.Parent := Self;
  Cb.SetBounds(20, 20, 180, 28);
  Cb.Images := Imgs;
  Cb.AddItem('保存', 0);     // 带图片 0
  Cb.AddItem('打开', 1);     // 带图片 1
  Cb.AddItem('(无图)', -1);  // 仅文字
  Cb.ItemIndex := 0;
end;
```

---

## 6. 注意事项

- **Objects 被占用:** 图片索引存在 `Items.Objects[i]`——**别再用 `Objects` 存自己的数据**(并行数组会在排序时错位,见 [colorbox.md](colorbox.md) 的同一教训)。
- **Images 是 `TTyVirtualImageList`(按索引)**,不是 `TTyImageCollection`(按名字);`AddItem` 里的图片索引对应 `Images.Names` 的行号。
- **纯状态逻辑已 headless 单测**(`AddItem` / `ImageIndexOf` / 排序不错位);图文绘制、下拉交互需真机验证。
