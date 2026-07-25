unit umain;

{ TTyShellTreeView + TTyShellListView + TTyShellComboBox + TTyFilterComboBox demo
  -- a mini "file browser", also the layout prototype for the Phase 7 file dialog.

  Top is the "look-in" dropdown (TTyShellComboBox): the breadcrumb ancestors of the current
  directory + each drive; click a row to jump there.
  Left is the directory tree (TTyShellTreeView): folders only, lazy-loaded. Right is the file
  list (TTyShellListView): the current directory's contents, four columns, with view switching /
  header-click sorting / F2 rename / grouping by kind. Bottom is the "file type" dropdown
  (TTyFilterComboBox): pick a filter preset and the list's Mask follows (directories always show).

  All four stay in sync: click a directory in the tree, double-click a folder in the list, pick an
  ancestor/drive in look-in -- navigate anywhere and the other three follow. An FSyncing flag blocks
  the "tree -> list -> tree" feedback loop. The look-in dropdown is display-only sync (setting its
  Directory fires no event), so it is written directly inside the sync, outside FSyncing.

  None of the four controls introduce any new theme token; no image assets are needed (the
  folder/file glyphs are built into the controls). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.TyLabel,
  tyControls.Button, tyControls.CheckBox, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.BuiltinThemes,
  tyControls.FileSystem, tyControls.ShellListView, tyControls.ShellTreeView,
  tyControls.ShellComboBox, tyControls.FilterComboBox, tyControls.ListView;

type
  TMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    TitleBar1: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;

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
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
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
  i: Integer;
begin
  { Built-in themes are compiled in, so the switcher works without locating a themes/ folder. }
  TyRegisterBuiltinThemes;
  TyDefaultController.ThemeName := 'default';
  for i := 0 to High(TyBuiltinThemeNames) do
    ThemeCombo.Items.Add(TyBuiltinThemeNames[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');

  { The list renames on F2 (opt-in; the default is read-only so a stray F2 can't rename). }
  List1.ReadOnly := False;

  { Filter presets: a segment Caption + its ';'-separated pattern list. Selecting one sets
    List1.Mask via OnFilterChange. Directories are always shown regardless of the mask. }
  FilterCombo.Filter :=
    'All files (*.*)|*.*|' +
    'Code (*.pas;*.lpr;*.inc)|*.pas;*.lpr;*.inc|' +
    'Document (*.md;*.txt)|*.md;*.txt';
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
  LblStatus.Caption := 'Current directory:' + APath;
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
  LblStatus.Caption := 'Open file:' + List1.FileAt(AIndex);
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

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  // Flip the light/dark @mode axis (independent of which theme ThemeCombo picked).
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
end;

end.
