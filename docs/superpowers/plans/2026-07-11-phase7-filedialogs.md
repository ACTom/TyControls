# Phase 7 批次 5 —— 文件对话框(交付物)实施计划

> 设计:`docs/superpowers/specs/2026-07-11-phase7-shell-filedialogs-design.md`(已批准)。
> 前置:批 1–4 已合并(FileSystem / ShellListView / ShellTreeView / FilterComboBox+ShellComboBox)。
> **样板**:`tyControls.Dialogs.SelectPath`(组装 tree 的 TTyDialog + 三层 API)、`tyControls.Dialogs.Font`
> (seed/readback 的组件↔form 契约)。四个对话框把已建的 shell 控件拼进 TTyDialog。
> **用户加项**:`TTyOpenPictureDialog` / `TTySavePictureDialog` —— 右侧多一个图片预览窗格。

## 交付物

| # | 产物 |
|---|---|
| 1 | `source/tyControls.Dialogs.FileDialog.pas` —— form + 纯解析函数 + 4 个组件 + builder/全局函数 |
| 2 | `tests/test.dialogs.filedialog.pas` —— 无头,只测**纯函数**(form 窗口化建不了) |
| 3 | 集成:`tycontrols.lpk`、`tytests.lpr`、`designtime/tyControls.Design.pas`(注册进 **TyControls Dialogs**)、调色板图标 ×4(133→137) |
| 4 | `docs/controls/filedialog.md` + README 索引;`examples/filedialog` 图片对话框 demo(双击可跑) |

**零新增主题 token**;`themes/*`、`DefaultTheme.pas`、`BuiltinThemeData.pas`、`tests/golden/*`、批 1–4 的 shell 单元、
`tyControls.Dialogs.pas` 基类**零改动**。

## 架构:一个 form + 两个标志 → 四变体

`TTyFileDialogForm = class(TTyDialog)`,两个 Boolean 决定形态:
- `SaveMode`:Save(可编辑文件名 + 存名解析 + 覆盖确认)vs Open(反映选中 + 可多选)。
- `PreviewMode`:图片版(右侧预览窗格 + 默认图片过滤器)vs 普通。

四个变体 = 两标志的四种组合。组件层是薄包装:一个基类组件 + 4 个子类(只覆写两个标志 + 默认过滤器)。

## 组装(照 SelectPath:CreateNew 建、LayoutContent 用 SetBounds 摆进 ContentRect)

`CreateNew` override(先 `inherited CreateNew`),`Resizable:=True`,`Constraints.MinWidth:=560/MinHeight:=420`,
用 `Create(Self)` + `.Parent:=Self` 建子控件(表单拥有并释放),**不在 ctor 里定位**;`LayoutContent` override 里
`SetBounds` 摆进 `ContentRect`(内缩 `TyDlgPad=16`)。子控件:
- `FLookIn: TTyShellComboBox`(顶部"查找范围")
- `FTree: TTyShellTreeView`(左)
- `FList: TTyShellListView`(中)
- `FPreview: TTyImage`(右,仅 `PreviewMode`;`Proportional:=True; Center:=True`)
- `FNameEdit: TTyEdit`(文件名)
- `FFilter: TTyFilterComboBox`(文件类型)
- `FBtnUp`, `FBtnNewFolder: TTyButton`(内容区小按钮,`mrNone` + OnClick;新建文件夹仅 SaveMode 显示)
- 三个 `TTyLabel`(查找范围/文件名/文件类型)

OK/Cancel 走 `TTyDialog.AddButton`(底部按钮条):
`AddButton(rsMsgBtnOK, mrOK, True, False)`(Save 版 caption 用"保存",Open 用"打开")+ `AddButton(rsMsgBtnCancel, mrCancel, False, True)`。

### LayoutContent 几何(cr := ContentRect;pad := TyDlgPad;x0:=cr.Left+pad;W:=cr.Width-2*pad)

```
行1(y=cr.Top+pad,h=30):  LblLookIn(64w) | FLookIn(伸展,留出两按钮) | FBtnUp(72w) | FBtnNewFolder(96w,仅SaveMode)
中区(行1下 gap 到 底部两行上 gap):
    FTree:    x0,        treeTop, 240w, midH
    FList:    x0+240+gap, treeTop, listW, midH    { PreviewMode 时 listW 让出 previewW+gap }
    FPreview: cr.Right-pad-220, treeTop, 220w, midH   { 仅 PreviewMode }
行A(底部倒数第2,h=30):  LblName(64w)   | FNameEdit(伸展)
行B(底部倒数第1,h=30):  LblFilter(64w) | FFilter(伸展)
```
`LayoutContent` 开头 `if FList = nil then Exit`(构造期先于子控件)。builder 结尾显式调一次 `LayoutContent`。

## 四方联动接线(照 examples/shell,一个 `FSyncing` 防回环)

- `FTree.OnPathChange` → `FList.LoadDirectory(FTree.SelectedPath)`(FSyncing 内)。
- `FLookIn.OnSelectPath` → `FList.LoadDirectory(FLookIn.SelectedPath)`。
- `FList.OnDirectoryChange` → 纯显示同步:`FLookIn.Directory := FList.Directory`(不触发事件);FSyncing 内 `FTree.SelectPath(FList.Directory)`。
- `FFilter.OnFilterChange` → `FList.Mask := FFilter.Mask`。
- `FList` 选中变化(OnChange / 选择事件)→ `FNameEdit.Text := ExtractFileName(FList.SelectedFile)`(两个模式都填;Save 里用户可再改)。
- `FList.OnFileActivate`(仅文件,文件夹自己导航)→ 填 `FNameEdit`;**Open 模式**下 `ModalResult := mrOK`(双击文件=接受)。
- `FBtnUp.OnClick` → `NavigateTo(TyFsParent(FList.Directory))`。
- `FBtnNewFolder.OnClick`(SaveMode)→ 照 SelectPath:`TyInputQuery` 取名 → `CreateDirUTF8` → `FList.Refresh`。

## OK 验证 —— 用 `CloseQuery`(不是按钮 OnClick)

OK 按钮把 `ModalResult:=mrOK`,触发 `CloseQuery`。form override `CloseQuery`:
```pascal
function TTyFileDialogForm.CloseQuery: Boolean;
begin
  Result := True;
  if ModalResult <> mrOK then Exit;
  Result := AcceptSelection;   { 校验 + 定 FResultName;不通过返回 False 把对话框留住 }
end;
```
`AcceptSelection`:
- **Open**:收集选中集 → `FFiles`;主结果 `FResultName`;若 `fdoFileMustExist` 且 `not FileExistsUTF8(FResultName)` → `TyMessageDlg(..., mtError, [mbOK])` 后返回 False(留住)。
- **Save**:`FResultName := TyFsResolveSaveName(CurrentDirectory, FNameEdit.Text, FDefaultExt)`;空名返回 False;
  若 `fdoOverwritePrompt` 且 `FileExistsUTF8(FResultName)` → `TyMessageDlg(覆盖确认, mtConfirmation, [mbYes,mbNo]) <> mrYes` 返回 False。

## 纯解析函数(**唯一可无头测的**,form 建不了)

```pascal
{ OK 会返回的路径。Save:裸名对 ADir 展开 + 补 ADefaultExt(= TyFsResolveSaveName)。
  Open:优先带路径的 ATyped,否则用 ASelected(当前焦点项),否则裸 ATyped 对 ADir 展开;都空则 ''。 }
function TyFileDialogResolveName(ASaveMode: Boolean;
  const ADir, ATyped, ASelected, ADefaultExt: string): string;
```
语义(**测试逐条钉死**):
- Save,裸名 `report`,dir `<tmp>`,defExt `txt` → `<tmp>/report.txt`(= `TyFsResolveSaveName`,交叉验证)。
- Save,`report.md` + defExt `txt` → `<tmp>/report.md`(已有扩展名不动)。
- Save,空名 → `''`。
- Open,`ATyped=''`,`ASelected=<tmp>/a.txt` → `<tmp>/a.txt`。
- Open,`ATyped='b.txt'`(裸名),dir `<tmp>` → `<tmp>/b.txt`(对 dir 展开)。
- Open,`ATyped=<abs>/c.txt`(带路径)→ 原样。
- Open,`ATyped=''` 且 `ASelected=''` → `''`。

`AcceptSelection` 调它定 `FResultName`;`Files` 的收集(`GetNextSelected` 遍历)靠 form,不无头测(窗口化)。

## 三层 API(每个变体)

**form 的公开 in/out 契约**(seed 写、OK 后读):
```pascal
public
  property InitialDir: string write SetInitialDir;   { 写=导航起点 }
  property FileName: string read FResultName write SetSeedFileName;  { 写=预填名;读=结果 }
  property Files: TStrings read FFiles;               { 只读;Open 多选结果 }
  property Filter: string read GetFilter write SetFilter;
  property FilterIndex: Integer read GetFilterIndex write SetFilterIndex;
  property DefaultExt: string read FDefaultExt write FDefaultExt;
  property Options: TTyFileDialogOptions read FOptions write SetOptions;  { 写→FList.MultiSelect 等 }
  function CurrentDirectory: string;   { = FList.Directory }
```

**组件基类 + 4 子类**:
```pascal
TTyFileDialogOption  = (fdoOverwritePrompt, fdoFileMustExist, fdoPathMustExist, fdoAllowMultiSelect);
TTyFileDialogOptions = set of TTyFileDialogOption;

TTyCustomFileDialog = class(TComponent)
protected
  function SaveMode: Boolean; virtual;      { 子类覆写 }
  function PreviewMode: Boolean; virtual;
  function DefaultFilter: string; virtual;  { 图片子类给图片扩展名 }
public
  constructor Create(AOwner); override;   { FFiles := TStringList.Create }
  destructor Destroy; override;           { FFiles.Free }
  function Execute: Boolean;               { builder→seed→ShowModal→readback→Free(leak-safe) }
published
  property Title, Filter, FilterIndex, FileName, InitialDir, DefaultExt: ...;
  property Options: TTyFileDialogOptions ...;
  property Files: TStrings read FFiles;    { 只读结果 }
  property OnShow, OnClose, OnCanClose: ...;  { TyForwardDialogEvents }
end;

TTyOpenDialog        = class(TTyCustomFileDialog);   { SaveMode=F, PreviewMode=F }
TTySaveDialog        = class(TTyCustomFileDialog);   { SaveMode=T, PreviewMode=F }
TTyOpenPictureDialog = class(TTyOpenDialog);         { PreviewMode=T + 图片 DefaultFilter }
TTySavePictureDialog = class(TTySaveDialog);         { PreviewMode=T + 图片 DefaultFilter }
```
`Execute`(照 Font):`d := TyBuildFileDialog(SaveMode, PreviewMode, ...)`;seed(`d.InitialDir/Filter/FilterIndex/FileName/DefaultExt/Options`,Filter 空则用 `DefaultFilter`);`TyForwardDialogEvents`;`Result := d.ShowModal=mrOK`;OK 后 `FFileName := d.FileName; FFiles.Assign(d.Files)`;`finally d.Free`。

**builder + 全局函数**:
```pascal
function TyBuildFileDialog(ASaveMode, APreviewMode: Boolean; const ATitle: string): TTyFileDialogForm;
function TyOpenDialog(var AFileName: string; const AFilter: string = ''): Boolean;
function TySaveDialog(var AFileName: string; const AFilter, ADefaultExt: string): Boolean;
function TyOpenPictureDialog(var AFileName: string): Boolean;
function TySavePictureDialog(var AFileName: string): Boolean;
```

## 图片预览

- 默认图片过滤器:`'图片 (*.png;*.jpg;*.jpeg;*.bmp;*.gif)|*.png;*.jpg;*.jpeg;*.bmp;*.gif|所有文件 (*.*)|*.*'`。
- `PreviewMode` 时右侧 `FPreview: TTyImage`(`Proportional:=True; Center:=True`)。选中变化 → `RefreshPreview`:
  `try FPreview.Picture.LoadFromFile(FList.SelectedFile) except FPreview.Picture.Clear end`(读不了不崩,清空)。
  仅当选中是文件且扩展名像图片时加载;否则清空。
- **跨平台**:BGRABitmap/LCL 的 PNG/JPG/BMP/GIF reader;JPEG 解码器由链接 `Graphics` 传递引入,`try/except` 兜底。

## 无头测试(只测纯函数)

- `test.dialogs.filedialog.pas`:上面 `TyFileDialogResolveName` 的 7 条 + Save 分支与 `TyFsResolveSaveName` 交叉验证。
  进程唯一临时目录建 `a.txt`。**不建 form**(窗口化会撞 win32 基线错误)。
- form 的组装/接线/预览/多选/Save 覆盖流全部**真机眼验**(examples/filedialog),Windows + Linux 各一轮。

## 对抗式审查清单(第三个 agent;form 无头测不了,审查是主要保障)

1. **接线回环**:`FSyncing` 是否挡住 tree→list→tree、combo→list→combo 的回环;`FLookIn.Directory:=` 是纯显示同步(不触发事件)。
2. **生命周期**:子控件全 `Create(Self)`(表单释放);组件的 `FFiles: TStringList` ctor 建/dtor 释放;`FPreview` 仅 PreviewMode 建、随表单释放;`Execute` 的 `try..finally d.Free`(含异常路径);不重复释放。
3. **三层 API**:seed 写映射到 form、OK 后 readback、Filter 空回落 `DefaultFilter`、事件经 `TyForwardDialogEvents`。
4. **Save 流程**:`CloseQuery` 拦 mrOK;`TyFsResolveSaveName` 用当前目录;覆盖确认 / 必须存在 用 `TyMessageDlg`;不通过返回 False 留住对话框(ModalResult 被 LCL 复位)。
5. **四变体分支**:两标志 → 四形态;图片版默认过滤器 + 预览窗格;`FBtnNewFolder` 仅 SaveMode。
6. **不碰 `OnItemActivate`**(shell view 自己拥有;用 `OnFileActivate`);受保护文件零改;零新 token。
7. `TyFileDialogResolveName` 实现与契约/测试一致(1-based FilterIndex、路径规范化)。

## 验收

- 全量测试 0 失败(基线 2805 + 新增纯函数测试)。
- 零新增主题 token;受保护文件零改;调色板漂移守卫过(137 类)。
- `examples/filedialog` 双击可跑;真机 Windows(+ Linux 若可)眼验四变体 + 预览。
- 过 [[pre-merge-checklist]](i18n:对话框按钮/标题走 resourcestring;README 中英)。
