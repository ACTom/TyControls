unit umain;

{ TTyShellTreeView + TTyShellListView 示例 —— 一个迷你「文件浏览器」。

  左边是目录树(TTyShellTreeView):只显示文件夹,懒加载 —— 展开一个目录时才去读它的
  子目录,所以哪怕挂一整块盘也不会卡。右边是文件列表(TTyShellListView):当前目录的
  内容,四列(名称/大小/类型/修改时间),可切五种视图、点表头排序、F2 重命名、按类型分组。

  两边双向联动:在树里点一个目录 → 右边列表加载它;在列表里双击一个文件夹 → 潜进去,
  左边的树也跟着定位到该目录(靠列表的 OnDirectoryChange + 树的 SelectPath,一个 FSyncing
  标志防止来回触发成死循环)。双击文件则弹一条状态提示。

  两个控件都不引入任何新主题 token —— 树复用 TyTreeView,列表复用 TyTreeView/TyTreeNode/
  TyTreeHeader;文件夹/文件的图标是控件自带的固定调色板字形,示例不需要任何图片资源。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.TyLabel,
  tyControls.Button, tyControls.CheckBox,
  tyControls.FileSystem, tyControls.ShellListView, tyControls.ShellTreeView,
  tyControls.ListView;

type
  TMainForm = class(TTyForm)
    TitleBar1: TTyTitleBar;

    BtnUp:       TTyButton;
    ChkHidden:   TTyCheckBox;
    ChkGroup:    TTyCheckBox;
    BtnMaskAll:  TTyButton;
    BtnMaskCode: TTyButton;
    BtnMaskDoc:  TTyButton;
    LblPath:     TTyLabel;

    Tree1: TTyShellTreeView;
    List1: TTyShellListView;
    LblStatus: TTyLabel;

    procedure FormCreate(Sender: TObject);
    procedure Tree1PathChange(Sender: TObject);
    procedure List1DirectoryChange(Sender: TObject);
    procedure List1FileActivate(Sender: TObject; AIndex: Integer);
    procedure ChkHiddenChange(Sender: TObject);
    procedure ChkGroupChange(Sender: TObject);
    procedure BtnUpClick(Sender: TObject);
    procedure BtnMaskAllClick(Sender: TObject);
    procedure BtnMaskCodeClick(Sender: TObject);
    procedure BtnMaskDocClick(Sender: TObject);
  private
    { Guards the tree<->list two-way sync so a tree-driven list load, or a list-driven
      tree reveal, does not bounce back and re-fire forever. }
    FSyncing: Boolean;
    procedure NavigateTo(const APath: string);
    procedure ShowPath(const APath: string);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

function ThemesDir: string;
var
  Dir: string;
  i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  startDir: string;
begin
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  { The list renames on F2 (opt-in; the default is read-only so a stray F2 can't rename). }
  List1.ReadOnly := False;

  Tree1.PopulateRoots;

  { Start in the user's home: a normal (non-hidden) path the tree can reveal with
    ShowHidden off. Loading it fires List1.OnDirectoryChange, which reveals it in the tree. }
  startDir := ExcludeTrailingPathDelimiter(GetUserDir);
  if not DirectoryExists(startDir) then
    startDir := ExtractFileDrive(ExpandFileName(ParamStr(0))) + PathDelim;
  NavigateTo(startDir);

  ApplyChromeTheme(TyDefaultController);
end;

{ ---------------------------------------------------------------------------
  Navigation + two-way sync
  --------------------------------------------------------------------------- }

procedure TMainForm.ShowPath(const APath: string);
begin
  LblPath.Caption := '当前目录:' + APath;
end;

{ Drive the list; its OnDirectoryChange then reveals the path in the tree. }
procedure TMainForm.NavigateTo(const APath: string);
begin
  List1.LoadDirectory(APath);
end;

procedure TMainForm.Tree1PathChange(Sender: TObject);
begin
  ShowPath(Tree1.SelectedPath);
  if FSyncing then Exit;
  FSyncing := True;
  try
    List1.LoadDirectory(Tree1.SelectedPath);   { fires List1.OnDirectoryChange, guarded }
  finally
    FSyncing := False;
  end;
end;

procedure TMainForm.List1DirectoryChange(Sender: TObject);
begin
  ShowPath(List1.Directory);
  if FSyncing then Exit;
  FSyncing := True;
  try
    Tree1.SelectPath(List1.Directory);   { reveal in the tree; fires Tree1.OnPathChange, guarded }
  finally
    FSyncing := False;
  end;
end;

procedure TMainForm.List1FileActivate(Sender: TObject; AIndex: Integer);
begin
  { Only files reach here -- a folder double-click navigates instead (handled by the control). }
  LblStatus.Caption := '打开文件:' + List1.FileAt(AIndex);
end;

procedure TMainForm.BtnUpClick(Sender: TObject);
var
  parentDir: string;
begin
  parentDir := TyFsParent(List1.Directory);
  if (parentDir <> '') and (parentDir <> List1.Directory) then
    NavigateTo(parentDir);
end;

{ ---------------------------------------------------------------------------
  Options
  --------------------------------------------------------------------------- }

procedure TMainForm.ChkHiddenChange(Sender: TObject);
begin
  { The list re-reads the current directory in place. The tree is flag-only -- the new
    setting applies on the next expand -- so re-seed its roots for an immediate refresh. }
  List1.ShowHidden := ChkHidden.Checked;
  Tree1.ShowHidden := ChkHidden.Checked;
  Tree1.PopulateRoots;
  Tree1.SelectPath(List1.Directory);
end;

procedure TMainForm.ChkGroupChange(Sender: TObject);
begin
  List1.GroupByKind := ChkGroup.Checked;
end;

procedure TMainForm.BtnMaskAllClick(Sender: TObject);
begin
  List1.Mask := '*';
  LblStatus.Caption := '筛选:全部文件';
end;

procedure TMainForm.BtnMaskCodeClick(Sender: TObject);
begin
  List1.Mask := '*.pas;*.lpr;*.inc';
  LblStatus.Caption := '筛选:*.pas;*.lpr;*.inc（目录始终显示）';
end;

procedure TMainForm.BtnMaskDocClick(Sender: TObject);
begin
  List1.Mask := '*.md;*.txt';
  LblStatus.Caption := '筛选:*.md;*.txt（目录始终显示）';
end;

end.
