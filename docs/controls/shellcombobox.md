# TTyShellComboBox

## 概述

`TTyShellComboBox` 是一个"查找范围"下拉框(`TTyComboBox` 子类,look-in combo)。展开后显示**当前目录的
面包屑祖先链**(根 → 当前,按深度缩进)加上**其它根**(盘符 / places),用户点任一行即跳到该目录。
字段里显示当前目录的干净标签(叶名 / 根 Display)。

锁 `csDropDownList`。**零新增主题 token**(继承 `TTyComboBox`)。下拉行与字段带**图标**:深度 0 的行(根)用
驱动器字形、更深的面包屑行用文件夹字形;层级用**像素缩进**表达。字形是固定调色板的内容图标(同
[[shelltreeview]]/[[shelllistview]],128px master 降采样,构造时主题未解析),内建于控件,无需图片资源。

## 用法

```pascal
uses tyControls.ShellComboBox;

LookIn := TTyShellComboBox.Create(Self);
LookIn.Parent := Panel1;
LookIn.Directory := 'C:\Users\Tom\Documents';   // 重建下拉,选中当前目录行;不触发事件
LookIn.OnSelectPath := @PlacePicked;             // 用户点了某个 place

procedure TForm1.PlacePicked(Sender: TObject);
begin
  List.LoadDirectory(LookIn.SelectedPath);   // 跳到用户选的目录
end;
```

## 属性 / 方法 / 事件

| 成员 | 说明 |
|---|---|
| `Directory: string` | 当前目录。写它=重建下拉并选中当前目录行;**不触发** `OnSelectPath`。同一路径(含/不含尾分隔符)early-exit,防重入循环。留空时下拉里是各个根(盘符)。下拉的行由它生成,`Items` 不写进 `.lfm`,对象查看器里也不显示。 |
| `SelectedPath: string` | 当前选中行的可导航路径(经 `Objects[]` 取模型),否则 `Directory`。 |
| `ShowPlaces: Boolean` | **public(非 published)**,默认 `False`。打开后,下拉里在当前路径的各级之后、其他根之前,列出用户的常用文件夹(桌面、文档、下载、图片、音乐、视频),用文件夹图标;当前目录正好是其中一个时,字段显示它的名字(「文档」)。文件对话框会打开它。3.0.5 新增。 |
| `OnSelectPath` | 用户点了某个 place(祖先目录或其它盘符)时触发;宿主据此 `List.LoadDirectory(SelectedPath)`。 |

## 纯函数 `TyLookInPlaces`

```pascal
type
  TTyLookInPlace = record Path, Display: string; Depth: Integer; Folder: Boolean; end;
  TTyLookInPlaceArray = array of TTyLookInPlace;
function TyLookInPlaces(const ADir: string): TTyLookInPlaceArray;
function TyLookInPlaces(const ADir: string; const AFolders: TTyFsRootArray): TTyLookInPlaceArray;
```

第二个重载(3.0.5)在链和其他根之间插入 `AFolders`(常用文件夹):每个一行,`Depth = 0`、`Folder = True`、
`Display` 是它的名字。即使某个文件夹已经在链上也照列——位置列表不随当前目录变,同一个位置总在固定的行上。

给定 `ADir`:先 `TyFsBreadcrumb(ADir)` 的每个累积路径(`Depth = 0..N`,`Display` = 匹配的根 Display 否则叶名),
再追加每个 `TyFsRoots` 里 Path 不等于链首的根(`Depth 0`,不重复当前盘符)。`ADir=''` → 只有根。无头可测。

> **根目录保留分隔符(#247,3.0.5)。** `Directory` 存下来时去掉末尾分隔符,但根目录除外:`C:\`、`/` 原样保留。
> 以前一律去掉,`C:\` 变成 `C:`(那是 C 盘的**当前目录**,不是根),当前路径那一行就和任何一个根都对不上,
> 停在盘符根目录时这个盘会在下拉里出现两次。

## 关键设计

- **锁 `csDropDownList`** + **每行模型索引存 `Objects[]`**(同 [[filtercombobox]] / ColorBox);读侧 `SelectedPath`/`DoSelect`
  与写侧的当前行匹配都经它,Sort-safe。
- **图标**:私有 `TTyImageCollection`(drive/folder 两个 128px 字形)经 `TTyVirtualImageList` 索引寻址;下拉行由
  自定义 popup 列表(`TTyListBox.PaintItemContent`)按 `DepthOfModel` 取深度 → `GlyphForDepth` 选字形 + 像素缩进绘制,
  字段由 `PaintFieldContent` 画当前目录字形 + 标签(不缩进)。模式照搬 `TTyAdvancedComboBox`。
- **`SetDirectory` 同路径 early-exit**:用户点行 → `OnSelectPath` → 宿主导航 → 宿主回写 `Directory :=` 同一路径 →
  early-exit,不二次触发,循环终止。
- **`FUpdating` 守护重建**:重建 Items + 设 `ItemIndex` 期间 `DoSelect` 被挡,不误触发 `OnSelectPath`。
- 字段用 `PaintFieldContent` 画不带缩进的干净标签(下拉行才缩进)。

## 消费者

[文件对话框](filedialog.md)顶部的"查找范围"下拉,和目录树 / 文件列表双向联动。
