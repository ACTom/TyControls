# TTyAdvancedListBox

## 1. 概述

TTyAdvancedListBox 是一个**富行(rich row)列表框**:每一行可带一张**左侧图片** + 一行**加粗标题(Title)** + 一行**暗色副标题(Subtitle)**,行高比普通列表更高,用于呈现「头像 + 名字 + 说明」这类两行信息。

继承自 [TTyListBox](../../source/tyControls.ListBox.pas),只重写 `PaintItemContent` 来画富行,其余滚动 / 选中 / 键盘导航行为完全复用基类。图片来自 [TTyVirtualImageList](../../source/tyControls.ImageCollection.pas)(按索引寻址)。

**数据模型(排序安全,无并行数组):**

- 两行文字**合并**存进一个 item 字符串:`Title + LineEnding + Subtitle`(副标题可为空)。
- 图片索引存进 `Items.Objects[i]`,值为 `TObject(PtrInt(AImageIndex + 1))`(`0` 表示无图)。

因此标题、副标题、图片索引三者天然与该行绑定,经 `Sorted` / `Delete` 都不会错位,并被 `Items.Assign` 原样复制(供 combo 弹出列表读同一批行)。排序按整段合并串比较(标题在前,故等价于按标题排序)。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.AdvancedListBox` |
| typeKey | `'TyListBox'`(继承)/ 行样式 `'TyListItem'`(继承)|

无新增 `.tycss`。副标题**复用 `TyListItem` 的 `TextColor`**,只降低 alpha 以示弱化,颜色仍随主题变化。

```pascal
uses tyControls.AdvancedListBox;
```

---

## 3. 属性 / 方法 / 事件

| 成员 | 说明 |
|------|------|
| `Images: TTyVirtualImageList` | 栅格图片来源(按索引)。设置时注册 `FreeNotification`,列表先释放会自动置 nil。 |
| `AddItem(const ATitle, ASubtitle: string; AImageIndex: Integer)` | 追加一行富项。`ASubtitle` 可为 `''`;`AImageIndex < 0` 表示无图。 |
| `TitleOf(AIndex): string` | 该行的标题(越界返回 `''`)。 |
| `SubtitleOf(AIndex): string` | 该行的副标题(无副标题 / 越界返回 `''`)。 |
| `ImageIndexOf(AIndex): Integer` | 该行的图片索引;无图 / 越界返回 `-1`。 |

另继承 `Items` / `ItemIndex` / `Sorted` / `MultiSelect` / `OnChange` / `Align` / `Anchors` / `StyleClass` / `Controller` 等。构造时 `ItemHeight` 默认设为 **40**(容纳两行)。

---

## 4. 交互

- 与 [TTyListBox](../../source/tyControls.ListBox.pas) 一致:左键点击选中行、滚轮 / 方向键滚动、`Sorted` 排序、可选多选。
- 富行绘制:左图(方形,行高减内边距,垂直居中)→ 标题(加粗 700,上半)→ 副标题(小一号、暗一档,下半);无副标题时标题在整行垂直居中。

---

## 5. 主题

- **标题** — `TyListItem` 的 `FontName` / `TextColor`,字重固定 `700`(加粗)。
- **副标题** — 同一 `FontName`,字号 = `ResolveFontSize - 2`,颜色 = `TextColor` 降低 alpha(仍是主题色)。
- **行背景 / 悬停 / 选中** — 由基类按 `TyListItem` 各状态填充。

所有 chrome 颜色 / 尺寸均由主题 token 驱动,未硬编码。

---

## 6. 代码示例

```pascal
uses tyControls.ImageCollection, tyControls.AdvancedListBox;

var
  Coll: TTyImageCollection;
  Imgs: TTyVirtualImageList;
  LB: TTyAdvancedListBox;
begin
  // 图片源(名字寻址的集合 + 按索引暴露的虚拟列表)
  Coll := TTyImageCollection.Create(Self);
  Coll.AddPicture('alice', AlicePic);   // AlicePic: TPicture
  Coll.AddPicture('bob',   BobPic);
  Imgs := TTyVirtualImageList.Create(Self);
  Imgs.Collection := Coll;
  Imgs.Names.Add('alice');   // index 0
  Imgs.Names.Add('bob');     // index 1

  LB := TTyAdvancedListBox.Create(Self);
  LB.Parent := Self;
  LB.SetBounds(20, 20, 240, 200);
  LB.Images := Imgs;
  LB.AddItem('Alice', 'Senior Engineer', 0);
  LB.AddItem('Bob',   'Product Designer', 1);
  LB.AddItem('Carol', '', -1);   // 无副标题、无图
end;
```

---

## 7. 注意事项

- **两行合并成一个 item:** 用 `AddItem` / `TitleOf` / `SubtitleOf` 存取,不要直接改 `Items[i]`,否则要自行维护 `Title + LineEnding + Subtitle` 的约定。
- **图片索引在 `Objects[]` 里(偏移 +1):** 存的是 `AImageIndex + 1`,`0` 才代表无图——这样 `Sorted` 重排后仍与该行同步,不用并行数组。
- **副标题颜色来自主题:** 只降低 `TextColor` 的 alpha,不硬编码灰色;换主题时副标题颜色随之变化。
- **绘制是真机验证项:** 数据逻辑(拆分标题 / 副标题、图片索引读写、排序保序)已 headless 单测;图片渲染与两行排版需真机眼验。
