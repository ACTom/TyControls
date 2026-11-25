# 文件对话框 —— TTyOpenDialog / TTySaveDialog / TTyOpenPictureDialog / TTySavePictureDialog

## 概述

主题化的自绘文件对话框。四个变体由**一个** `TTyFileDialogForm`(`TTyDialog` 子类)靠两个标志
(`SaveMode` / `PreviewMode`)拼出:左栏的「位置」面板(`TTyShellPlacesView`)+ 文件列表
([TTyShellListView](shelllistview.md))+ 查找范围([TTyShellComboBox](shellcombobox.md))
+ 类型过滤([TTyFilterComboBox](filtercombobox.md))—— 加文件名框 + 确定/取消组装进对话框。图片变体右侧
多一个 [TTyImage](image.md) 预览窗格。**零新增主题 token**。

左栏从 4.0 起是「位置」面板:常用文件夹、应用固定的文件夹、最近去过的文件夹、各个盘,点一下就到,
和现在各平台自己的文件对话框一样。3.x 的目录树([TTyShellTreeView](shelltreeview.md))还在,
把 `LeftPane` 设成 `fdpFolderTree` 就换回来。详见下文「位置」。

三层 API 对齐 LCL 的 `TOpenDialog`/`TSaveDialog`/`TOpenPictureDialog`/`TSavePictureDialog`。

## 用法

**全局函数(最省事)**:
```pascal
uses tyControls.Dialogs.FileDialog;

var fn: string;
begin
  fn := 'C:\Users\Tom\notes.txt';
  if TyOpenDialog(fn, '文本 (*.txt)|*.txt|所有文件 (*.*)|*.*') then
    OpenFile(fn);                         // fn = 选中的文件

  if TySaveDialog(fn, '文本 (*.txt)|*.txt', 'txt') then
    SaveFile(fn);                         // fn 已补默认扩展名、已过覆盖确认

  if TyOpenPictureDialog(fn) then         // 默认图片过滤器 + 右侧预览
    LoadImage(fn);
end;
```

**可流式组件(拖到窗体上)**:
```pascal
Dlg := TTyOpenDialog.Create(Self);
Dlg.Title := '选择文档';
Dlg.Filter := '文本 (*.txt)|*.txt|所有文件 (*.*)|*.*';
Dlg.InitialDir := 'C:\Users\Tom';
Dlg.Options := [ofFileMustExist, ofAllowMultiSelect];   // LCL 的 TOpenOptions,uses Dialogs
if Dlg.Execute then
  for s in Dlg.Files do ...;             // 多选结果;单选时 Dlg.FileName
```

## 属性 / 方法(组件)

| 成员 | 说明 |
|---|---|
| `Execute: Boolean` | 弹模态;确定返回 True。 |
| `FileName: string` | 输入=预填名;输出=选中/解析后的结果。 |
| `Files: TStrings` | 只读;Open 多选的全部结果(单选时含一项)。 |
| `Filter` / `FilterIndex` | LCL 过滤串 / 生效段(1-based)。为空时回落到变体默认过滤器。 |
| `InitialDir: string` | 起始目录。 |
| `DefaultExt: string` | Save:文件名无扩展名时补它。 |
| `Options: TOpenOptions` | LCL 的选项类型,默认 `[]`。每个选项做什么见下文「Options」。 |
| `Title: string` | 标题栏文字。 |
| `LeftPane` | 文件列表左边放什么:`fdpPlaces`「位置」面板(默认)、`fdpFolderTree` 目录树、`fdpNone` 不放。4.0 新增。 |
| `PinnedFolders: TStrings` | 应用固定在「位置」里的文件夹,一行一个完整路径,列在「固定」下面。不存在的文件夹打开时不列。4.0 新增。 |
| `ShowRecentFolders: Boolean` | 要不要列「最近」这一组,并在确定后把这次的文件夹记进去。默认 `True`。4.0 新增。 |
| `OnPlaces` | 位置列好了、还没显示:应用可以往里加、删、调顺序。每次建对话框触发一次,`Sender` 是对话框组件。4.0 新增。 |
| `OnShow`/`OnClose`/`OnCanClose` | 转发给内部表单。 |
| `OnHelpClicked` | 点了「帮助」按钮(`ofShowHelp` 时才有),`Sender` 是对话框组件。 |
| `BuildForm: TTyFileDialogForm` | `Execute` 要显示的那个窗体(已按属性设好、已加帮助按钮、事件已转发),不显示;调用方负责释放。 |
| `ApplyResult(AOK, AFileName, AFiles)` | `Execute` 在窗体关闭后做的事:确定时取结果,再按 `ofNoResolveLinks`、`ofNoChangeDir`、`ofExtensionDifferent` 收尾。自己用 `BuildForm` 显示窗体的,关闭后调它。 |

四个组件类:`TTyOpenDialog`(F/F)、`TTySaveDialog`(T/F)、`TTyOpenPictureDialog`(F/T)、
`TTySavePictureDialog`(T/T),只覆写 `SaveMode`/`PreviewMode`/默认过滤器。

## 位置

左栏和查找范围的下拉用的是同一张位置表,分四组,空的组不显示:

| 组 | 内容 |
|---|---|
| 常用 | 桌面、文档、下载、图片、音乐、视频(只列存在的);Linux 和 macOS 上前面多一个「主目录」。 |
| 固定 | `PinnedFolders` 里的文件夹。 |
| 最近 | 最近几次确定时所在的文件夹,最新的在前;上面几组里已经有的不重复列。 |
| 设备 | Windows 的各个盘;Linux 的根目录和挂载点;macOS 的磁盘。 |

设备排在最后:盘多的机器上,应用固定的和最近去过的文件夹不该被挤到要滚动才看得见的地方。

点一下某个位置就进去;用方向键只移动高亮,按回车才进去。点组的标题可以把这一组收起来。
当前文件夹正好是某个位置时,它在面板里高亮。

查找范围的下拉:先是当前路径的各级,然后是同一张位置表。

**固定自己的文件夹**

```pascal
OpenDialog1.PinnedFolders.Add(ProjectDir);
OpenDialog1.PinnedFolders.Add(ProjectDir + PathDelim + 'templates');
```

**最近去过的文件夹**记在 `TyRecentFolders`(`tyControls.FileSystem`)里:整个程序一张表,所有文件对话框共用,
只在内存里 —— 库自己不写配置文件。什么都不做,最近位置在这次运行期间有效;想下次启动还在,
把这张表和程序的其他设置一起读、一起存:

```pascal
uses tyControls.FileSystem;

// 启动时
if FileExists(RecentFile) then TyRecentFolders.LoadFromFile(RecentFile);
// 退出时
TyRecentFolders.SaveToFile(RecentFile);
```

存在 ini、注册表或别的地方也一样,它就是一个 `TStrings`(`TyRecentFolders.Text`、`CommaText` 都能用)。
`TyRecentFoldersLimit`(默认 5)是这张表保留几个、对话框列几个。表里已经不存在的文件夹不显示,
但不会被删掉 —— 可能只是那个盘暂时没插上。某个对话框不想参与(比如选密钥文件的),
把它的 `ShowRecentFolders` 设成 `False`:不列,确定后也不记。

**自己增删位置**用 `OnPlaces`。表里每一项有四个字段:`Path`、`Caption`(显示的名字)、`Group`(组的标题)、
`Icon`(图标)。`Group` 可以是库的四个标题(`rsFdGroupPlaces`、`rsFdGroupPinned`、`rsFdGroupRecent`、
`rsFdGroupDevices`,在 `tyControls.StrConsts`),也可以是应用自己的文字,那就是一个新的组;
组按第一次出现的先后排。

```pascal
uses tyControls.ShellPlaces, tyControls.FileSystem, tyControls.StrConsts;

procedure TForm1.OpenDialog1Places(Sender: TObject; APlaces: TTyFilePlaces);
var
  i: Integer;
begin
  // 自己的一组,放在最前面
  APlaces.Insert(0, ProjectDir, '项目', '当前项目');
  APlaces.Insert(1, ProjectDir + PathDelim + 'assets', '项目', '素材', fpiPictures);
  // 不要「音乐」和「视频」
  for i := APlaces.Count - 1 downto 0 do
    if APlaces[i].Icon in [fpiMusic, fpiVideos] then APlaces.Delete(i);
end;
```

`TTyFilePlaces` 的方法:`Add`、`Insert`、`Delete`、`Move`、`Clear`、`IndexOf(路径)`、`Count`、`Items[]`。
图标是 `TTyFsPlaceIcon`:`fpiFolder`、`fpiDrive`、`fpiHome`、`fpiDesktop`、`fpiDocuments`、`fpiDownloads`、
`fpiPictures`、`fpiMusic`、`fpiVideos`;它们是库里画的,不依赖图标字体或图片文件。

全局函数(`TyOpenDialog` 等)用的是默认设置:位置面板、没有固定的文件夹、列最近位置。

## Options

`Options` 用 LCL 的 `TOpenOptions`(`Dialogs` 单元),为 LCL 写的代码和窗体可以直接搬过来。LCL 的 25 个选项分三类。

**起作用的(11 个)**

| 选项 | 效果 |
|---|---|
| `ofOverwritePrompt` | 保存时文件已存在,先问要不要替换;选「否」对话框不关。 |
| `ofAllowMultiSelect` | 打开时可以多选,结果在 `Files`。 |
| `ofFileMustExist` | 文件不存在就报错、不关。打开和保存都查(同 LCL),多选时每个文件都查。 |
| `ofPathMustExist` | 文件所在的文件夹不存在就报错、不关。 |
| `ofCreatePrompt` | 文件不存在,先问要不要创建;选「否」不关。对话框本身不建文件。 |
| `ofNoReadOnlyReturn` | 文件存在但不可写,或者是新文件而文件夹不可写,报错、不关。 |
| `ofForceShowHidden` | 文件列表和目录树显示隐藏的文件和文件夹。 |
| `ofShowHelp` | 按钮栏多一个「帮助」,点了触发 `OnHelpClicked`,对话框不关。 |
| `ofExtensionDifferent` | 输出位,不用自己设:确定后只选了一个文件、`DefaultExt` 不空且扩展名跟它不同时置上,否则清掉。 |
| `ofNoChangeDir` | 没有它时,确定后 `InitialDir` 改成结果所在的文件夹(同 LCL);有它时 `InitialDir` 不动。 |
| `ofNoResolveLinks` | 没有它时,确定后 `FileName` 和 `Files` 里的符号链接换成实际路径(同 LCL;只在 Linux / macOS 上有区别,Windows 原样返回)。 |

几个检查的先后跟 LCL 一样:文件夹存在 → 文件存在 → 可写 → 问创建 → 问覆盖,碰到第一个不通过的就停。

**收下但不起作用的(13 个)**:窗体照样能读、代码照样能编,只是对话框不看它们。

| 选项 | 为什么 |
|---|---|
| `ofEnableSizing` | 对话框总是能拖边框缩放。 |
| `ofViewDetail` | 总是从「详细信息」视图开始。 |
| `ofReadOnly`、`ofHideReadOnly` | Windows 老式对话框的「以只读方式打开」复选框,这里没有。 |
| `ofNoValidate` | 本来就不检查文件名里的非法字符。 |
| `ofShareAware` | Windows 的共享冲突处理。 |
| `ofNoTestFileCreate` | 本来就不试建文件。 |
| `ofNoNetworkButton` | Windows 老式对话框的「网络」按钮。 |
| `ofNoLongNames` | 8.3 短文件名。 |
| `ofOldStyleDialog` | Win9x 样式。 |
| `ofNoDereferenceLinks` | 本来就不解析 Windows 的 `.lnk` 快捷方式。 |
| `ofDontAddToRecent` | 本来就不往系统的「最近使用」里加。 |
| `ofAutoPreview` | 有没有预览窗格由对话框种类决定(Picture、Preview 两类有)。 |

**不适用的(1 个)**:`ofEnableIncludeNotify`,LCL 自己也没用,只为和 Delphi 兼容才声明。

LCL 的默认值是 `[ofEnableSizing, ofViewDetail]`,这里仍是 `[]`:这两个选项不起作用,而改默认值会让存过 `Options` 的旧窗体读进来少两位。LCL 窗体里存的 `Options` 照常读入。

### 从 3.0 升级

- **左栏默认不再是目录树,而是「位置」面板**(4.0)。想要原来的树,把对话框组件的 `LeftPane` 设成 `fdpFolderTree`;
  用 `TyBuildFileDialog` 自己建窗体的,设窗体的 `LeftPane`。对话框默认高了 40 像素,让面板少滚动。
  自己建窗体并用到 `ShellTree` 的代码注意:不是目录树模式时它返回 `nil`。
- 3.0 的 `Options` 是自己的 `TTyFileDialogOptions`(`fdoOverwritePrompt`、`fdoFileMustExist`、`fdoPathMustExist`、`fdoAllowMultiSelect`)。**旧窗体不用改**:读窗体时这四个旧名字照样认,对应到 `of*`;在 IDE 里存一次就写成新名字。**旧代码照样能编**:`TTyFileDialogOptions` 和四个 `fdo*` 常量还在,标了 `deprecated`,编译时有警告,换成 `TOpenOptions` 和 `of*`(`uses Dialogs`)就没了。
- 3.0.0 收下了 `fdoPathMustExist` 却从不检查,现在会检查。
- `ofFileMustExist` 现在保存对话框也查(3.0.0 只查打开),多选时每个文件都查(3.0.0 只查一个)。
- 这两处 3.0 的后续修复版也改了,行为和这里一样。
- `Execute` 确定后 `InitialDir` 会改成结果所在的文件夹,Linux / macOS 上 `FileName` 里的符号链接会换成实际路径,和 LCL 一样。要 3.0 的行为,加 `ofNoChangeDir`、`ofNoResolveLinks`。

## 关键设计

- **一个 form 两个标志 = 四变体**;`FBtnNewFolder` 仅 SaveMode 建,`FPreview` 仅 PreviewMode 建(标志 setter 懒建)。
- **左栏是「位置」面板(#246,4.0)**:窗体的 `RefreshPlaces` 列出位置(`TyFillFilePlaces`:这台机器的常用文件夹和根、
  `PinnedFolders`、最近位置),交给 `OnPlaces`,再同时交给面板和查找范围的下拉,所以两处永远是同一张表。
  位置从哪来见 [filesystem.md](filesystem.md) 的 `TyFsKnownFolders`;名字走库的翻译,所以中文界面显示「文档」。
  面板和目录树只建用到的那一个;树只在它是当前左栏时才跟着列表走(隐藏的树不去读盘)。
  目录树模式下,常用文件夹仍列在树的顶部(#245,3.0.5 起)。
- **四方联动**(左栏↔列表↔查找范围)靠一个 `FSyncing` 防回环;查找范围字段是纯显示同步(写 `Directory` 不触发事件)。
  过滤下拉 `OnFilterChange` → `List.Mask`。选中文件 → 填文件名框(**只认选中,不认取消选中** ——
  列表的 `OnSelectItem` 现在也会报告刚被**离开**的那一行,拿它去填名字会写进一个用户已经不在的文件名,
  Save 模式下还会盖掉用户刚敲进去的名字);双击文件(Open)→ 直接接受。
- **OK 在 `CloseQuery` 里校验**(不是按钮 OnClick),校验通过才问 `OnCanClose`(和 Windows 原生对话框的顺序一样),所以 `OnCanClose` 答应了就一定会关:Save 走 `TyFsResolveSaveName` 解析,Open 收集选中集;
  然后对每个文件跑纯函数 `TyFileDialogCheck`(按 `Options` 返回通过 / 报哪种错 / 问哪个问题),
  再由 `TyMessageDlg` 报错或提问;不通过返回 False 把对话框留住。
- **Open 手敲优先**:文件名框非空时以它为准(带路径原样、裸名对当前目录展开),空框才回落到列表选中项。
- **文件列表的列头和类型名走库的翻译(#249,3.0.5)**:名称 / 大小 / 类型 / 修改日期,以及类型一列里的
  「文件夹」「TXT 文件」。之前是写死的英文,见 [shelllistview.md](shelllistview.md)。
- **打开时焦点在文件名框**(打开和保存都是),可以直接输入文件名。Tab 按排布的顺序走:查找范围、视图、
  左栏(位置面板或目录树)、文件列表、文件名、文件类型,最后才是按钮(#243,3.0.5;之前焦点在「打开」按钮上,文件类型排在文件名前面)。
- **Save 存名解析**(`TyFileDialogResolveName` → `TyFsResolveSaveName`):裸名对当前目录展开,无扩展名补 `DefaultExt`,已有扩展名不动。
- **图片预览**:选中图片时 `TTyImage.Picture.LoadFromFile`(`try/except`,读不了清空),`Proportional+Center` 缩放适配;
  跨平台(PNG/JPG/BMP/GIF)。

## 通用预览对话框

`TTyOpenPreviewDialog` / `TTySavePreviewDialog` —— 右侧预览框默认支持**图片 + 文本**,并可经
`OnPreview` 事件自定义:

```pascal
Dlg := TTyOpenPreviewDialog.Create(Self);
Dlg.OnPreview := @MyPreview;
Dlg.Execute;

procedure TForm1.MyPreview(Sender: TObject; const AFileName: string;
  APreview: TTyPreviewBox; var AHandled: Boolean);
begin
  if ExtractFileExt(AFileName) = '.myfmt' then
  begin
    APreview.ShowImage(DecodeMyFormat(AFileName));   // 交出位图
    AHandled := True;                                // 跳过内建分派
  end;
  // 不 handled → 内建:图片→文本→"无法预览"
end;
```

预览框是可复用的 [TTyPreviewBox](previewbox.md);**图片变体也用同一个 box**(`AllowText=False`,图片-only),
全库一套预览机制。自定义 = 交出 bitmap/text(`APreview.ShowImage`/`ShowText`/`ShowMessage`),低层
`APreview.OnPaintPreview` 兜底。

六个组件:普通 `TTyOpenDialog`/`TTySaveDialog`、图片 `TTyOpenPictureDialog`/`TTySavePictureDialog`
(对齐 LCL)、通用预览 `TTyOpenPreviewDialog`/`TTySavePreviewDialog`(加值)。

## 位置面板 TTyShellPlacesView

`tyControls.ShellPlacesView`。文件对话框左栏用的控件,**不在组件面板上**,可以在代码里建。它是一个
[TTyListView](listview.md):一列、每行一个图标、每组一个标题带,键盘、滚动条、主题都是列表的。

| 成员 | 说明 |
|---|---|
| `SetPlaces(APlaces: TTyFilePlaces)` | 显示这张表(拷一份,按组归拢)。`nil` = 清空。 |
| `CurrentPath: string` | 宿主当前所在的文件夹。它正好是某个位置时那一行高亮,否则都不高亮。写它不触发事件。 |
| `SelectedPath: string` | 高亮的那个位置的文件夹;没有高亮时为空。 |
| `OnSelectPath` | 用户选了一个位置(点击,或在高亮行上按回车),而且不是宿主已经在的文件夹:宿主去 `SelectedPath`。 |
| `PlaceCount` / `PlaceAt(i)` | 按显示顺序读位置。 |
| `PlaceImages` | 行图标用的图像列表(`tyControls.ShellIcons` 的 `TyAddPlaceIcons` 填的)。 |

## 待办 / 后续

- 「位置」面板在 Linux 和 macOS 真机上没看过(常用文件夹的取法只在 Windows 上对照过系统);盘只显示盘符,不显示卷标。
- 真机眼验(六变体组装/联动/Save 覆盖流/图片+文本预览/自定义 `OnPreview`)。
- i18n 已完成:全部面向用户的文案(标题/按钮/"查找范围:"/过滤器名/"无法预览"等)走
  `tyControls.StrConsts` 的 `rsFd*` / `rsPv*` 资源串。
