# TTyComboBoxEx

## 1. 概述

TTyComboBoxEx 是**每一行带一套扩展数据（图片 / 缩进 / 载荷）+ 文字**的下拉框。继承自 [TTyComboBox](combobox.md),覆写 `PaintFieldContent`(字段区)与自定义弹出列表的 `PaintItemContent`(下拉行),在图片右侧画文字——**字段和下拉里画的是同一套图文布局**(共享 `DrawImageText` / `DrawExItem`)。

这个控件存在的理由是 **`ItemsEx`**:一个 published、**设计期可编辑的集合**(`TTyComboExItems`,元素为 `TTyComboExItem`)。每个条目带 `Caption` / `ImageIndex` / `OverlayImageIndex` / `SelectedImageIndex` / `Indent` / `Data`。没有它,这个控件就只是"多几步的组合框"。

**`ItemsEx` 是真值,继承来的 `Items`(`TStringList`)是它的投影**:每行的 `Items.Objects[i]` 装着那一行的 `TTyComboExItem`。这就是扩展数据跟着标题一起被排序 / 删除搬动而不错位的原因(没有并行数组),也是下拉列表(基类用 `Items.Assign` 填)和字段读到**同一批条目**的原因。**直接写 `Items` 仍然可用**:集合会被反向对齐(见 `ReconcileFromItems`),所以不可能出现"某一行没有条目"的状态。

图片来源为 [`TTyVirtualImageList`](imagecollection.md)(按索引寻址、`CachedIndex(索引, 像素尺寸)` 借用一张按目标像素缩放的缓存位图)。

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

## 3. `TTyComboExItem` —— 一行的扩展数据

| 成员 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Caption` | `TCaption` | `''` | 行标题。改它会同步到投影的 `Items[i]`。 |
| `ImageIndex` | `Integer` | `-1` | 行图片在 `Images` 里的索引;`-1` = 无图。 |
| `Indent` | `Integer` | `-1` | 左缩进(**逻辑像素**,绘制时按 DPI 缩放),做树状分组用;`<= 0` = 不缩进。 |
| `OverlayImageIndex` | `Integer` | `-1` | 叠在行图片**之上**的角标(状态 / 徽标)。只有本行确实画了图片时才有意义。 |
| `SelectedImageIndex` | `Integer` | `-1` | 本行**被选中时**改用的图片(字段里显示的那一行永远算"选中")。`-1` = 不换。 |
| `Data` | `TObject` | `nil` | **应用自己的每行数据**。非 published(对象引用无法流式化)——这就是从前 `Items.Objects[i]` 那个槽位,现在归控件所有了。 |

## 4. `TTyComboExItems` —— 集合

| 成员 | 说明 |
|------|------|
| `Add: TTyComboExItem` | 追加一个空条目。 |
| `AddItem(ACaption; AImageIndex; AOverlayImageIndex; ASelectedImageIndex; AIndent; AData)` | 一次调用建好一行(除 `ACaption` 外全部有默认值 `-1` / `nil`)。 |
| `Insert(AIndex): TTyComboExItem` | 在指定位置插入。 |
| `ComboItems[i]`(default) | 按索引取条目,`ItemsEx[0]` 即可。 |
| `CaseSensitive: Boolean`(published,默认 `False`) | 内建文本比较是否区分大小写(影响 `stText` / `stBoth`)。 |
| `SortType: TTyListItemsSortType`(published,默认 `stNone`) | `stNone` / `stData` / `stText` / `stBoth`。**赋值即立刻排序**(否则在 Object Inspector 里改了看不出动静)。 |
| `OnCompare: TTyListCompareEvent`(published) | `stData` / `stBoth` 时由它决定顺序(只有应用知道自己的 `Data` 是什么);没挂处理器时退回按文本比,排序不会变成静默的空操作。 |
| `Sort` / `CustomSort(ACompare)` | 手动排序。两者都只改条目的 `Index`,**不重建条目**,所以每行与它的标题的配对不会断。 |

## 5. `TTyComboBoxEx` 的属性 / 方法

| 成员 | 说明 |
|------|------|
| `ItemsEx: TTyComboExItems` | published 集合,设计期可编辑。**声明在依赖行集合的属性之前**,保证先流式化。 |
| `Images: TTyVirtualImageList` | 图片来源(按索引寻址)。赋值会登记 `FreeNotification`,来源先被释放时自动置空引用。 |
| `AddItem(const S: string; AImageIndex: Integer)` | 追加带图片的一行;`AImageIndex < 0` 表示无图。 |
| `AddItem(const AItem: string; AnObject: TObject)`(override) | 继承来的形式,**改道**:对象进这一行条目的 `Data`,不会被当成图片索引读出来。 |
| `Add: Integer` / `Add(ACaption; AIndent; AImgIdx; AOverlayImgIdx; ASelectedImgIdx)` | LCL 的两个 `Add` 重载。 |
| `Insert(AIndex; ACaption; AIndent; AImgIdx; AOverlayImgIdx; ASelectedImgIdx)` | 带图片的插入(不用再手写 `Objects[]` 编码)。 |
| `Delete(AIndex)` / `DeleteSelected` | 删一行 / 删当前选中行。 |
| `AssignItemsEx(AItems: TStrings)` / `AssignItemsEx(AItemsEx: TTyComboExItems)` | 批量装载(从字符串表 / 从另一个集合)。 |
| `ItemEx(AIndex): TTyComboExItem` | 第 i **行**对应的条目(越界返回 `nil`)。 |
| `ImageIndexOf(AIndex): Integer` | 第 i 行的图片索引;无图 / 越界返回 `-1`。 |
| `DrawImageText(P; ARect; S; AImageIndex; AStyle)` | 共享绘制:左图右文。 |
| `DrawExItem(P; ARect; AItem; ASelected; AStyle)` | 完整行绘制:应用 `Indent`、选中时换 `SelectedImageIndex`、再叠 `OverlayImageIndex`。 |

另继承 `TTyComboBox` 的 `Items` / `ItemIndex` / `Text` / `Sorted` / `DropDownCount` / `TextHint` / `OnChange` / `OnSelect` 等。

---

## 6. 主题

- 文字用行 / 字段解析出的 `FontName` / 字号(`ResolveFontSize`)/ `FontWeight` / `TextColor`,不硬编码。
- 图片按行高自适应(`行高 - 6` 逻辑像素,最小 8px),纵向居中;由 `Images.CachedIndex` 按目标像素缩放(结果缓存复用),一份母图服务各 DPI。
- `Indent` 是逻辑像素,绘制时走 `P.Scale`,HiDPI 下不会缩水。

---

## 7. 代码示例

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

  // 简单写法(老 API,仍然有效)
  Cb.AddItem('保存', 0);
  Cb.AddItem('(无图)', -1);

  // 完整写法:缩进 + 选中时换图 + 角标 + 自己的数据
  with Cb.ItemsEx.AddItem('打开', 1) do
  begin
    Indent := 12;
    SelectedImageIndex := 0;
    Data := MyCommandObject;
  end;

  Cb.ItemsEx.SortType := stText;   // 按标题排序,图片跟着走
  Cb.ItemIndex := 0;
end;
```

设计期:在 Object Inspector 里点开 `ItemsEx` 的集合编辑器逐条添加,`.lfm` 会写成一个 `ItemsEx = <...>` 块。

---

## 8. 注意事项

- **应用数据用条目的 `Data`,不是 `Items.Objects[i]`(API parity 修正):** `Items.Objects[i]` 是控件的槽位(放行条目),从前那里直接存的是 `图片索引 + 1`。现在 `Cb.ItemsEx[i].Data := X`,或者 `Cb.AddItem('x', SomeObject)`——继承来的两参形式从前被那个"两参但第二个是整数"的重载**整个遮蔽**了,移植代码 `AddItem('x', SomeObject)` 直接编译不过;现在它编译得过,而且**不会**被当成图片索引读出来。
- **`Items` 和 `ItemsEx` 双向同步:** 改集合会重建投影;直接 `Items.Add` / `Items.Delete` / `Items.Clear` 会反向对齐集合(缺条目的行补一个,没人引用的条目删掉),手工 `Items.AddObject(s, X)` 挂的对象会被接管进 `Data`。
- **`Sorted = True` 时集合顺序与显示顺序不同:** `Sorted` 排的是投影(显示),`ItemsEx` 保持插入顺序;配对靠 `Objects[]`,不会错。要**集合**也有序就用 `ItemsEx.SortType`。
- **`ItemIndex` 的流式化顺序:** `ItemIndex` 声明在祖先类,会**先于** `ItemsEx` 写进 `.lfm`,加载时列表还是空的、索引会被钳成 `-1`。控件在 `SelectItem` 里记住流式化期间的索引,并在 `Loaded` 里重新应用——所以设计期设的选中项能活下来。
- **`Images` 是 `TTyVirtualImageList`(按索引)**,不是 `TTyImageCollection`(按名字);图片索引对应 `Images.Names` 的行号。
- **未做(与 LCL `TComboBoxEx` 的差异):** `Images` 类型不是 `TCustomImageList`(现成的 `TImageList` **不能**直接赋值,`ComboEx.Images := ImageList1` 编译不过);没有 `ImagesWidth`;没有 `AutoCompleteOptions` 和 `StyleEx`(所以没法说"关闭字段里的图标" `csExNoEditImage`);`SortType` 少一个 `stCustom` 值(用 `CustomSort` 方法代替)。
- **纯状态逻辑已 headless 单测**(集合↔列表双向同步 / 各扩展字段 / 增删插 / 批量装载 / 排序不错位 / 对象重载不进图片槽);图文绘制、下拉交互需真机验证。
