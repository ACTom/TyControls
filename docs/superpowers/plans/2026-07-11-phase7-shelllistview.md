# Phase 7 批次 2 —— `TTyShellListView` 实施计划

> 设计:`docs/superpowers/specs/2026-07-11-phase7-shell-filedialogs-design.md`(已批准)
> 前置:批 1 `tyControls.FileSystem`(`099e001`)已合并。
> **这是底座的第一个真实消费者** —— 用它证明批 1 的签名对得上,再往上叠树/combo/对话框。

## 交付物

| # | 产物 |
|---|---|
| 1 | `source/tyControls.ShellListView.pas` —— `TTyShellListView = class(TTyListView)` |
| 2 | `tests/test.shelllistview.pas` —— 无头,临时目录;测状态机(取数/排序/重命名/目录切换),不测绘制 |
| 3 | `tycontrols.lpk` `<Item>`;`tests/tytests.lpr` uses;`designtime/tyControls.Design.pas` 注册进 **TyControls Containers** 组;调色板图标(genicons + gen-icons.ps1 + test.paletteicons,数组上界 +1)|
| 4 | `docs/controls/shelllistview.md` + README 索引 |

**零新增主题 token**:继承 `TTyListView` 的 `GetStyleTypeKey := 'TyTreeView'`,一切照旧。

## 契约

`TTyShellListView = class(TTyListView)` —— **纯适配器**。状态只有目录、文件数组、掩码、对象类型、
列→SortKey 映射。绘制/滚动/命中/框选/多选/首字母/表头排序/F2 编辑器/列/分组全部**继承不动**。

### 状态

```pascal
private
  FDirectory:   string;
  FEntries:     TTyFsEntryArray;      { 唯一后备存储;item index == 下标 }
  FMask:        string;               { 当前过滤,默认 '*' }
  FObjectTypes: TTyFsObjectTypes;     { 默认 [fotFolders, fotFiles] }
  FFoldersFirst: Boolean;             { 默认 True }
  FIcons:       TTyVirtualImageList;  { 自带的种类字形(见下)}
```

### 构造(在构造函数里,不在 .lfm)

- `OwnerData := True`。
- 建四列(用继承的 `Header.Columns`):名称 220 / 大小 90 `taRightJustify` / 类型 120 / 修改时间 140;
  `Header.Options` 开 `hoVisible, hoColumnResize, hoShowSortGlyphs, hoHeaderClickAutoSort`。
- `OnCompare := @DoCompare`(内部私有方法)。
- 建自带种类字形图标表,赋给 `SmallImages`/`LargeImages`(见"图标")。
- 默认 `FMask := '*'`,`FObjectTypes := [fotFolders, fotFiles]`,`FFoldersFirst := True`。

### override 的五个取值方法

```pascal
function GetItemCount: Integer; override;                    { = Length(FEntries) —— 不碰磁盘! }
function GetItemText(AIndex, AColumn: Integer): string; override;
  { case col: 0=Name / 1=大小(空目录留空,FormatFileSize)/ 2=TypeName / 3=修改时间(空则留空) }
function GetItemImageIndex(AIndex, AColumn: Integer): Integer; override;
  { col<=0 时返回种类字形索引(目录 vs 文件类型);其余列 -1 }
function GetItemGroup(AItemIndex: Integer): Integer; override;
  { 按类型分组时返回组序号(目录一组、各扩展一组);GroupView 关时此方法不被调用 }
procedure CommitEdit(AIndex: Integer; const AText: string); override;
  { F2 重命名的落点:RenameFileUTF8(FEntries[i].FullPath, 新路径),成功则重载目录。
    OwnerData 默认什么都不写,所以不 override 就改不了盘。空名/同名/非法名静默放弃。 }
```

**`GetItemCount` 绝不碰磁盘** —— 它每帧每次滚动排序都被调,读 `Length(FEntries)`。

### 排序 —— 全 phase 最容易踩的坑(spec 已警示)

`TTyListView.FSortKind` 是跨列共享的单标量、且解析**显示串**。所以**必须**用 `OnCompare`:

```pascal
procedure DoCompare(Sender: TObject; AIndex1, AIndex2, AColumn: Integer; var ACompare: Integer);
begin
  { AIndex1/2 是 item index → FEntries 下标;按列映射到 SortKey,比原始值 }
  ACompare := TyFsCompareEntries(FEntries[AIndex1], FEntries[AIndex2],
                ColumnSortKey(AColumn), SortDirection = sdAscending, FFoldersFirst);
end;
```

`ColumnSortKey(0)=fskName, 1=fskSize, 2=fskType, 3=fskModified`。**漏掉这个映射会静默排错。**
注意 `TyFsCompareEntries` 自己处理目录优先 + 升降序,所以 `DoCompare` 把方向原样传进去,**不再自己取反**
(否则双重取反)。

### 公开 API

```pascal
public
  procedure LoadDirectory(const APath: string);   { 读盘 → FEntries → ItemsChanged }
  procedure Refresh;                               { = LoadDirectory(FDirectory) }
  function  SelectedFile: string;                  { 焦点项的 FullPath,无则 '' }
  function  FileAt(AIndex: Integer): string;       { item index → FullPath,越界 '' }
  property  Entries: TTyFsEntryArray read FEntries; { 只读,给对话框拿选中集 }
published
  property Directory: string read FDirectory write LoadDirectory;
  property Mask: string read FMask write SetMask;                 { 改后自动 Refresh }
  property ShowHidden: Boolean;                                    { 改 FObjectTypes 的 fotHidden 位 + Refresh }
  property FoldersFirst: Boolean read FFoldersFirst write SetFoldersFirst default True;
  property GroupByKind: Boolean;                                   { = 继承的 GroupView + 建种类组 }
  property OnFileActivate: TTyListItemEvent;                       { 双击文件夹→进入;双击文件→触发 }
```

`LoadDirectory`:`FEntries := TyFsReadDirectory(APath, FMask, FObjectTypes)`;`FDirectory := APath`;
`ItemsChanged`(继承的 public seam,重设 order/rank/selection、按 AutoSort 重排)。**不自己排序** —— `ItemsChanged`
在 `AutoSort and SortColumn>=0` 时自动调 `Sort`,`Sort` 走 `OnCompare`。

**双击进入目录**:override `DblClick` 或用继承的 `OnItemActivate`。焦点是文件夹 → `LoadDirectory(它的 FullPath)`;
是文件 → 触发 `OnFileActivate`。(对话框会接这个。)

### 图标 —— 自带种类字形

控件在构造函数里建一个私有 `TTyImageCollection` + `TTyVirtualImageList`,画一小组 BGRA 字形
(文件夹、通用文件、文本、图像、表格、可执行),`GetItemImageIndex` 按 `FEntries[i]` 的 IsDir/扩展名映射。
字形用 BGRA `FillRoundRectAntialias`/`FillPolyAntialias` 画,master **128px**(降采样锐利,见图标缓存的教训),
参照 `examples/listview/umain.pas` 的 `BuildIcons`。

**这些是内容图标,用一小组固定的、雅致的调色板**(和调色板字形、示例图标一样),**不**从主题取色 ——
理由:构造时 `Controller`/主题可能还没解析,主题取色会引入"构造时无主题 + 换主题要重建"的复杂度,不值得;
而且这是**内容**(文件类型),不是控件 chrome。这是对"视觉值主题驱动"规则的一个**有意豁免**,和
`examples/listview` 的做法一致,理由写进代码注释。应用可用 `SmallImages`/`LargeImages` 整个覆盖。

## 无头测试要点

- 临时目录建可控树(同批 1)。测:
  - `LoadDirectory` 后 `GetItemCount = 可见条目数`;`GetItemText(i,col)` 各列正确;`FileAt`/`SelectedFile`。
  - **排序按原始值**:造两个文件,显示大小 `'9 KB'` vs `'10 KB'`(字典序 `'1'<'9'` 会排反),按大小列排序后
    顺序按 Int64 正确 —— 这条专门钉那个"解析显示串会排错"的坑,**变异测试**:把 `DoCompare` 换成默认字符串排序,它必须挂。
  - 目录永远在文件前(升序降序都测)。
  - `CommitEdit` 真的重命名磁盘文件(建文件→CommitEdit→断言旧名没了新名在),空名放弃。
  - `Mask := '*.txt'` 后只剩 txt + 目录;`ShowHidden` 切换隐藏项。
- 不测绘制(无头画不了),但可测 `GetItemImageIndex` 对目录/文件返回不同的合法索引。
- 用 `TTyShellListViewAccess` 子类暴露 protected(override 的取值方法、`DoCompare`)。

## 验收

- 全量测试 0 失败(基线 2765 + 新增)。
- `themes/*`、`DefaultTheme.pas`、`BuiltinThemeData.pas`、`tests/golden/*`、`tyControls.TreeView.pas`、
  `tyControls.ListView*.pas`、`tyControls.FileSystem.pas` **零改动**(这批只加新单元 + 集成文件)。
- 调色板漂移守卫通过(`gen-icons.ps1` 输出 "N registered components all have icons")。
- 排序坑的变异测试通过(撤掉列→SortKey 映射,大小排序测试必挂)。
