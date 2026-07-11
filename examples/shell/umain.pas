unit umain;

{ TTyShellTreeView + TTyShellListView + TTyShellComboBox + TTyFilterComboBox 示例
  —— 一个迷你「文件浏览器」,也是 Phase 7 文件对话框的布局雏形。

  顶部是「查找范围」下拉(TTyShellComboBox):当前目录的面包屑祖先 + 各盘符,点一行就跳过去。
  左边是目录树(TTyShellTreeView):只显示文件夹,懒加载。右边是文件列表(TTyShellListView):
  当前目录内容,四列,可切视图 / 点表头排序 / F2 改名 / 按类型分组。底部是「文件类型」下拉
  (TTyFilterComboBox):选一个过滤预设,列表的 Mask 跟着变(目录恒显)。

  四者联动:树点目录、列表双击文件夹、查找范围选祖先/盘符 —— 任一处导航,其它三处都跟着到位。
  一个 FSyncing 标志把「树→列表→树」的回环挡掉。查找范围下拉是纯显示同步(设它的 Directory 不触发事件),
  所以在同步里直接写,不进 FSyncing。

  四个控件都不引入任何新主题 token;不需要任何图片资源(文件夹/文件字形是控件自带的)。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.TyLabel,
  tyControls.Button, tyControls.CheckBox,
  tyControls.FileSystem, tyControls.ShellListView, tyControls.ShellTreeView,
  tyControls.ShellComboBox, tyControls.FilterComboBox, tyControls.ListView;

type
  TMainForm = class(TTyForm)
    TitleBar1: TTyTitleBar;

    BtnUp:     TTyButton;
    ChkHidden: TTyCheckBox;
    ChkGroup:  TTyCheckBox;

    LblLookIn: TTyLabel;
    LookIn:    TTyShellComboBox;

    Tree1: TTyShellTreeView;
    List1: TTyShellListView;

    LblFilter:  TTyLabel;
    FilterCombo: TTyFilterComboBox;
    LblStatus:  TTyLabel;

    procedure FormCreate(Sender: TObject);
    procedure Tree1PathChange(Sender: TObject);
    procedure List1DirectoryChange(Sender: TObject);
    procedure List1FileActivate(Sender: TObject; AIndex: Integer);
    procedure LookInSelectPath(Sender: TObject);
    procedure FilterComboFilterChange(Sender: TObject);
    procedure ChkHiddenChange(Sender: TObject);
    procedure ChkGroupChange(Sender: TObject);
    procedure BtnUpClick(Sender: TObject);
  private
    { Guards the tree<->list two-way sync so a tree-driven list load, or a list-driven
      tree reveal, does not bounce back and re-fire forever. }
    FSyncing: Boolean;
    procedure NavigateTo(const APath: string);
    procedure ShowCurrent(const APath: string);
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

  { Filter presets: a segment Caption + its ';'-separated pattern list. Selecting one sets
    List1.Mask via OnFilterChange. Directories are always shown regardless of the mask. }
  FilterCombo.Filter :=
    '所有文件 (*.*)|*.*|' +
    '代码 (*.pas;*.lpr;*.inc)|*.pas;*.lpr;*.inc|' +
    '文档 (*.md;*.txt)|*.md;*.txt';
  FilterCombo.FilterIndex := 1;

  Tree1.PopulateRoots;

  { Start in the user's home: a normal (non-hidden) path the tree can reveal with
    ShowHidden off. Loading it fires List1.OnDirectoryChange, which reveals it everywhere. }
  startDir := ExcludeTrailingPathDelimiter(GetUserDir);
  if not DirectoryExists(startDir) then
    startDir := ExtractFileDrive(ExpandFileName(ParamStr(0))) + PathDelim;
  NavigateTo(startDir);

  ApplyChromeTheme(TyDefaultController);
end;

{ ---------------------------------------------------------------------------
  Navigation + four-way sync
  --------------------------------------------------------------------------- }

{ Display sync only -- update the path label + the look-in field. Setting LookIn.Directory
  never fires OnSelectPath, so this is safe to call outside the FSyncing guard. }
procedure TMainForm.ShowCurrent(const APath: string);
begin
  LblStatus.Caption := '当前目录:' + APath;
  LookIn.Directory := APath;
end;

{ Drive the list; its OnDirectoryChange then reveals the path in the tree + look-in. }
procedure TMainForm.NavigateTo(const APath: string);
begin
  List1.LoadDirectory(APath);
end;

procedure TMainForm.Tree1PathChange(Sender: TObject);
begin
  ShowCurrent(Tree1.SelectedPath);
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
  ShowCurrent(List1.Directory);
  if FSyncing then Exit;
  FSyncing := True;
  try
    Tree1.SelectPath(List1.Directory);   { reveal in the tree; fires Tree1.OnPathChange, guarded }
  finally
    FSyncing := False;
  end;
end;

procedure TMainForm.LookInSelectPath(Sender: TObject);
begin
  { The user picked an ancestor / drive in the look-in combo. Navigate there; the resulting
    List1.OnDirectoryChange sets LookIn.Directory back (same path -> early-exit) and reveals
    the tree. }
  NavigateTo(LookIn.SelectedPath);
end;

procedure TMainForm.FilterComboFilterChange(Sender: TObject);
begin
  List1.Mask := FilterCombo.Mask;   { directories still show; only files are filtered }
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

end.
