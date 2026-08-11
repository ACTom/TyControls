unit tyControls.Dialogs.FileDialog;
{$mode objfpc}{$H+}

{ Phase 7 batch 5 -- the four themed file dialogs.

  Design: docs/superpowers/specs/2026-07-11-phase7-shell-filedialogs-design.md
  Plan  : docs/superpowers/plans/2026-07-11-phase7-filedialogs.md

  ONE form -- TTyFileDialogForm(TTyDialog) -- parameterised by two flags:
    * SaveMode    Save (editable name + save-name resolve + overwrite confirm) vs
                  Open (reflects the selection, may multi-select).
    * PreviewMode picture variant (right-hand TTyImage preview + an image default
                  filter) vs a plain file dialog.
  The four public dialogs are thin component wrappers over the two-flag form:
    TTyOpenDialog / TTySaveDialog / TTyOpenPictureDialog / TTySavePictureDialog.

  It COMPOSES the already-shipped shell controls (tree / list / look-in combo /
  filter combo) plus a name edit + Up / New-Folder buttons; it does NOT modify any
  of them, nor the TTyDialog base, nor any theme token.

  The ONLY headless-testable seam is the pure function TyFileDialogResolveName --
  the windowed form cannot be instantiated under the console test runner, so all
  "what path does OK return" logic is factored into that function. }

interface

uses
  Classes, SysUtils, Types, Controls, Dialogs, Forms, Graphics,
  LazFileUtils,
  tyControls.Dialogs, tyControls.ShellTreeView, tyControls.ShellListView,
  tyControls.ShellComboBox, tyControls.FilterComboBox,
  tyControls.Edit, tyControls.Button, tyControls.TyLabel, tyControls.PreviewBox,
  tyControls.Panel, tyControls.Splitter,
  tyControls.ListView, tyControls.FileSystem, tyControls.Component, tyControls.StrConsts;

{ ---------------------------------------------------------------------------
  The pure resolver -- the OK path the dialog returns. UNIT-TESTED headless.

  Save : = TyFsResolveSaveName(ADir, ATyped, ADefaultExt) -- a bare typed name is
         expanded against ADir; a default ext is appended only when the resolved
         name has none; an empty ATyped -> ''.
  Open : a path-bearing ATyped verbatim; else the focused item ASelected; else a
         bare ATyped expanded against ADir; else ''.
  --------------------------------------------------------------------------- }
function TyFileDialogResolveName(ASaveMode: Boolean;
  const ADir, ATyped, ASelected, ADefaultExt: string): string;

type
  { The LCL-parity option set. }
  TTyFileDialogOption  = (fdoOverwritePrompt, fdoFileMustExist, fdoPathMustExist,
                          fdoAllowMultiSelect);
  TTyFileDialogOptions = set of TTyFileDialogOption;

  { Fires as the preview refreshes for AFileName (the focused selection; '' or a
    directory when nothing previewable is focused). Draw into APreview yourself
    (ShowImage / ShowText / ShowMessage / ShowCustom) and set AHandled := True to
    skip the built-in image/text dispatch. }
  TTyFileDialogPreviewEvent = procedure(Sender: TObject; const AFileName: string;
    APreview: TTyPreviewBox; var AHandled: Boolean) of object;

  { ===================================================================
    TTyFileDialogForm -- the composed, two-flag file dialog form.
    =================================================================== }
  TTyFileDialogForm = class(TTyDialog)
  private
    FSaveMode:    Boolean;
    FPreviewMode: Boolean;
    { Composed children (all owned by the form -> auto-freed). The mode-conditional
      one (FPreview) is created lazily by its flag setter; FBtnNewFolder is a bottom-bar
      action button built for EVERY mode in TyBuildFileDialog. }
    FLookIn:       TTyShellComboBox;
    FMidPanel:     TTyPanel;         { invisible layout host for the tree|list|preview band }
    FTree:         TTyShellTreeView;
    FSplitTree:    TTySplitter;      { drag: resize the tree (its left neighbour) }
    FList:         TTyShellListView;
    FSplitPrev:    TTySplitter;      { drag: resize the preview (its right neighbour); PreviewMode }
    FFilter:       TTyFilterComboBox;
    FNameEdit:     TTyEdit;
    FBtnUp:        TTyButton;
    FBtnNewFolder: TTyButton;
    FPreview:      TTyPreviewBox;
    FLblLookIn:    TTyLabel;
    FLblName:      TTyLabel;
    FLblFilter:    TTyLabel;
    { State. }
    FSyncing:    Boolean;   { guards tree<->list<->look-in navigation from re-entering }
    FResultName: string;    { the primary OK result (a full path) }
    FDefaultExt: string;
    FFiles:      TStrings;   { the Open multi-select result set (a TStringList instance) }
    FOptions:    TTyFileDialogOptions;
    FPreviewAllowsText: Boolean;   { seeds FPreview.AllowText each refresh (picture=False) }
    FOnPreview:  TTyFileDialogPreviewEvent;
    { Flag setters -- create/toggle the conditional children. }
    procedure SetSaveMode(AValue: Boolean);
    procedure SetPreviewMode(AValue: Boolean);
    { Public in/out property plumbing. }
    procedure SetInitialDir(const AValue: string);
    procedure SetSeedFileName(const AValue: string);
    function  GetFilter: string;
    procedure SetFilter(const AValue: string);
    function  GetFilterIndex: Integer;
    procedure SetFilterIndex(AValue: Integer);
    procedure SetOptions(AValue: TTyFileDialogOptions);
    { Four-way wiring handlers. }
    procedure TreePathChange(Sender: TObject);
    procedure LookInSelectPath(Sender: TObject);
    procedure ListDirectoryChange(Sender: TObject);
    procedure FilterChange(Sender: TObject);
    procedure ListSelectItem(Sender: TObject; AIndex: Integer; ASelected: Boolean);
    procedure ListFileActivate(Sender: TObject; AIndex: Integer);
    procedure BtnUpClick(Sender: TObject);
    procedure NewFolderClick(Sender: TObject);
    { Navigate every view to APath (fires the list's directory-change sync). }
    procedure NavigateTo(const APath: string);
    { mrOK validation: harvest + validate; returns False to veto (keep the dialog). }
    function  AcceptSelection: Boolean;
    { Load the focused image into the preview pane (PreviewMode only, crash-safe). }
    procedure RefreshPreview;
  protected
    procedure LayoutContent; override;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    destructor  Destroy; override;
    function    CloseQuery: Boolean; override;
    { = FList.Directory (the directory the list is currently showing). }
    function CurrentDirectory: string;
    { Two-flag configuration (write = mode; read = current). SaveMode drives the OK
      caption/validation + New-Folder visibility; PreviewMode adds the preview pane. }
    property SaveMode: Boolean read FSaveMode write SetSaveMode;
    property PreviewMode: Boolean read FPreviewMode write SetPreviewMode;
    { The public in/out contract (seed before ShowModal; read on mrOK). }
    property InitialDir: string write SetInitialDir;               { write = navigate start }
    property FileName: string read FResultName write SetSeedFileName; { write = prefill; read = result }
    property Files: TStrings read FFiles;                          { read-only; Open multi-select }
    property Filter: string read GetFilter write SetFilter;
    property FilterIndex: Integer read GetFilterIndex write SetFilterIndex;
    property DefaultExt: string read FDefaultExt write FDefaultExt;
    property Options: TTyFileDialogOptions read FOptions write SetOptions;
    { PreviewMode extras: whether the preview pane also renders text files, and a
      hook to render an unrecognised format yourself. Seeded before ShowModal. }
    property PreviewAllowsText: Boolean read FPreviewAllowsText write FPreviewAllowsText;
    property OnPreview: TTyFileDialogPreviewEvent read FOnPreview write FOnPreview;
  end;

{ Construct-only builder: create + set the two flags + OK/Cancel + size + layout. }
function TyBuildFileDialog(ASaveMode, APreviewMode: Boolean; const ATitle: string): TTyFileDialogForm;

{ Globals -- LCL-parity one-liners. }
function TyOpenDialog(var AFileName: string; const AFilter: string = ''): Boolean;
function TySaveDialog(var AFileName: string; const AFilter, ADefaultExt: string): Boolean;
function TyOpenPictureDialog(var AFileName: string): Boolean;
function TySavePictureDialog(var AFileName: string): Boolean;

type
  { ===================================================================
    Component wrappers -- one base + four subclasses (two flags each).
    =================================================================== }
  TTyCustomFileDialog = class(TTyComponent)
  private
    FTitle, FFilter, FFileName, FInitialDir, FDefaultExt: string;
    FFilterIndex: Integer;
    FOptions: TTyFileDialogOptions;
    FFiles: TStrings;
    FOnShow: TNotifyEvent;
    FOnClose: TCloseEvent;
    FOnCanClose: TCloseQueryEvent;
    FOnPreview: TTyFileDialogPreviewEvent;
  protected
    { Subclasses override to pick the variant. }
    function SaveMode: Boolean; virtual;
    function PreviewMode: Boolean; virtual;
    { PreviewMode panes: whether text files also preview (picture variants keep the
      default False -> image-only; the preview-dialog variants override True). }
    function PreviewAllowsText: Boolean; virtual;
    { The filter used when Filter is empty (picture subclasses give an image filter). }
    function DefaultFilter: string; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { build -> seed -> ShowModal -> read back -> free (leak-safe). }
    function Execute: Boolean;
  published
    property Title: TCaption read FTitle write FTitle;
    property Filter: string read FFilter write FFilter;
    property FilterIndex: Integer read FFilterIndex write FFilterIndex default DefaultFilterIndex;
    property FileName: string read FFileName write FFileName;
    property InitialDir: string read FInitialDir write FInitialDir;
    property DefaultExt: string read FDefaultExt write FDefaultExt;
    property Options: TTyFileDialogOptions read FOptions write FOptions default [];
    property Files: TStrings read FFiles;   { read-only result set }
    property OnShow: TNotifyEvent read FOnShow write FOnShow;
    property OnClose: TCloseEvent read FOnClose write FOnClose;
    property OnCanClose: TCloseQueryEvent read FOnCanClose write FOnCanClose;
    { PreviewMode-only: render a selection into the preview pane yourself. Ignored by
      non-preview variants (no preview pane to draw into). }
    property OnPreview: TTyFileDialogPreviewEvent read FOnPreview write FOnPreview;
  end;

  { Open a single/multiple existing file(s). }
  TTyOpenDialog = class(TTyCustomFileDialog);

  { Save to a (possibly new) file name. }
  TTySaveDialog = class(TTyCustomFileDialog)
  protected
    function SaveMode: Boolean; override;
  end;

  { Open an image with a live preview pane. }
  TTyOpenPictureDialog = class(TTyOpenDialog)
  protected
    function PreviewMode: Boolean; override;
    function DefaultFilter: string; override;
  end;

  { Save an image with a live preview pane. }
  TTySavePictureDialog = class(TTySaveDialog)
  protected
    function PreviewMode: Boolean; override;
    function DefaultFilter: string; override;
  end;

  { Open a file with a general preview pane (image AND text). }
  TTyOpenPreviewDialog = class(TTyOpenDialog)
  protected
    function PreviewMode: Boolean; override;
    function PreviewAllowsText: Boolean; override;
    function DefaultFilter: string; override;
  end;

  { Save a file with a general preview pane (image AND text). }
  TTySavePreviewDialog = class(TTySaveDialog)
  protected
    function PreviewMode: Boolean; override;
    function PreviewAllowsText: Boolean; override;
    function DefaultFilter: string; override;
  end;

{ Globals -- LCL-parity one-liners for the general preview dialogs. }
function TyOpenPreviewDialog(var AFileName: string): Boolean;
function TySavePreviewDialog(var AFileName, ADefaultExt: string): Boolean;

implementation

{ The rsFd* / rsPvCannotPreview strings live in tyControls.StrConsts (already in uses)
  so they share the central package .po like every other user-facing string. }

const
  Gap = 8;   { inter-control gap inside the content area }

{ ---------------------------------------------------------------------------
  The pure resolver
  --------------------------------------------------------------------------- }

function TyFileDialogResolveName(ASaveMode: Boolean;
  const ADir, ATyped, ASelected, ADefaultExt: string): string;
begin
  Result := '';
  if ASaveMode then
    { Save: the FileSystem helper is the single source of truth (bare name expands
      against ADir + a default ext is appended only when missing). }
    Result := TyFsResolveSaveName(ADir, ATyped, ADefaultExt)
  else
  begin
    { Open: a non-empty typed name always wins (it is what the user sees + edits in the
      name box, which auto-fills from the selection but the user can override) -- a
      path-bearing name verbatim, a bare name expanded against the directory; only an
      EMPTY box falls back to the focused item; else nothing. }
    if ATyped <> '' then
    begin
      if ExtractFilePath(ATyped) <> '' then
        Result := ATyped
      else
        Result := ExpandFileNameUTF8(ATyped, ADir);
    end
    else if ASelected <> '' then
      Result := ASelected
    else
      Result := '';
  end;
end;

{ ---------------------------------------------------------------------------
  TTyFileDialogForm -- lifecycle
  --------------------------------------------------------------------------- }

constructor TTyFileDialogForm.CreateNew(AOwner: TComponent; Num: Integer);

  function MkLabel(const ACaption: string): TTyLabel;
  begin
    Result := TTyLabel.Create(Self);
    Result.Parent := Self;
    Result.Caption := ACaption;
  end;

begin
  inherited CreateNew(AOwner, Num);
  Resizable := True;
  { Roughly double the old ~560 min width: the right-hand file list was far too narrow
    (real-machine testing), so the whole dialog opens wide + a little taller. }
  Constraints.MinWidth  := 900;
  Constraints.MinHeight := 460;

  FSaveMode := False;
  FPreviewMode := False;
  FPreviewAllowsText := False;
  FSyncing := False;
  FDefaultExt := '';
  FOptions := [];
  FFiles := TStringList.Create;

  { The always-present children (mode-conditional ones are created by the flag
    setters). Create + parent only -- LayoutContent does the positioning. }
  FLblLookIn := MkLabel(rsFdLookIn);
  FLblName   := MkLabel(rsFdFileNameLbl);
  FLblFilter := MkLabel(rsFdFileTypeLbl);

  FLookIn := TTyShellComboBox.Create(Self);
  FLookIn.Parent := Self;
  FLookIn.OnSelectPath := @LookInSelectPath;

  { The tree | list | preview band lives inside an invisible host panel so LCL alignment
    + TTySplitter give draggable dividers. The host keeps the theme surface fill (same as
    the dialog, so it does not read as a box) but drops the panel padding + border, and the
    aligned children cover it edge-to-edge anyway. Explicit Left values order the same-align
    siblings deterministically (code-created alLeft/alRight otherwise dock in reverse order). }
  FMidPanel := TTyPanel.Create(Self);
  FMidPanel.Parent := Self;
  FMidPanel.StyleOverride := 'padding: 0; border-width: 0;';

  FTree := TTyShellTreeView.Create(Self);
  FTree.Parent := FMidPanel;
  FTree.Align := alLeft;
  FTree.Width := 190;             { narrow-ish -> more room for the file list }
  FTree.Left := 0;
  FTree.OnPathChange := @TreePathChange;

  FSplitTree := TTySplitter.Create(Self);
  FSplitTree.Parent := FMidPanel;
  FSplitTree.Align := alLeft;
  FSplitTree.Left := 190;         { sorts after the tree -> sits to its right }
  FSplitTree.Width := 6;
  FSplitTree.MinSize := 120;      { min tree width }

  FList := TTyShellListView.Create(Self);
  FList.Parent := FMidPanel;
  FList.Align := alClient;        { fills between the tree splitter and the preview splitter }
  FList.OnDirectoryChange := @ListDirectoryChange;
  FList.OnSelectItem      := @ListSelectItem;   { selection change -> name edit + preview }
  FList.OnFileActivate    := @ListFileActivate; { double-click a file (folders navigate internally) }

  FFilter := TTyFilterComboBox.Create(Self);
  FFilter.Parent := Self;
  FFilter.OnFilterChange := @FilterChange;

  FNameEdit := TTyEdit.Create(Self);
  FNameEdit.Parent := Self;

  FBtnUp := TTyButton.Create(Self);
  FBtnUp.Parent := Self;
  FBtnUp.Caption := rsFdUp;
  FBtnUp.OnClick := @BtnUpClick;
end;

destructor TTyFileDialogForm.Destroy;
begin
  FFiles.Free;   { child controls are owned by the form and freed with it }
  inherited Destroy;
end;

{ ---------------------------------------------------------------------------
  Flag setters -- create/toggle the conditional children
  --------------------------------------------------------------------------- }

procedure TTyFileDialogForm.SetSaveMode(AValue: Boolean);
begin
  FSaveMode := AValue;
  { New Folder is now a bottom-bar action button built for every mode in TyBuildFileDialog,
    so there is nothing mode-conditional to create here. SaveMode still drives the OK caption
    + save-name validation (the builder + AcceptSelection). }
  if FList <> nil then
    LayoutContent;
end;

procedure TTyFileDialogForm.SetPreviewMode(AValue: Boolean);
begin
  FPreviewMode := AValue;
  if AValue and (FPreview = nil) then
  begin
    { Right-docked preview + a splitter to its left, both in the layout host. The preview
      sorts rightmost (large Left); the splitter sorts just left of it. }
    FPreview := TTyPreviewBox.Create(Self);
    FPreview.Parent := FMidPanel;
    FPreview.Align := alRight;
    FPreview.Width := 220;
    FPreview.Left := 10000;

    FSplitPrev := TTySplitter.Create(Self);
    FSplitPrev.Parent := FMidPanel;
    FSplitPrev.Align := alRight;
    FSplitPrev.Left := 9990;      { sorts just left of the preview }
    FSplitPrev.Width := 6;
    FSplitPrev.MinSize := 140;    { min preview width }
  end;
  if FPreview <> nil then
    FPreview.Visible := AValue;
  if FSplitPrev <> nil then
    FSplitPrev.Visible := AValue;
  if FList <> nil then
    LayoutContent;
end;

{ ---------------------------------------------------------------------------
  Public in/out plumbing
  --------------------------------------------------------------------------- }

procedure TTyFileDialogForm.SetInitialDir(const AValue: string);
var
  dir: string;
begin
  dir := AValue;
  if (dir = '') or not DirectoryExistsUTF8(dir) then
    dir := GetCurrentDirUTF8;   { always land the list somewhere usable }
  NavigateTo(dir);
end;

procedure TTyFileDialogForm.SetSeedFileName(const AValue: string);
var
  dirPart: string;
begin
  FResultName := AValue;
  if AValue = '' then Exit;
  { A path-bearing seed also navigates to its directory. }
  dirPart := ExtractFileDir(AValue);
  if (dirPart <> '') and DirectoryExistsUTF8(dirPart) then
    NavigateTo(dirPart);
  if FNameEdit <> nil then
    FNameEdit.Text := ExtractFileName(AValue);
end;

function TTyFileDialogForm.GetFilter: string;
begin
  Result := FFilter.Filter;
end;

procedure TTyFileDialogForm.SetFilter(const AValue: string);
begin
  FFilter.Filter := AValue;
  FList.Mask := FFilter.Mask;   { reflect the initial filter into the list at once }
end;

function TTyFileDialogForm.GetFilterIndex: Integer;
begin
  Result := FFilter.FilterIndex;
end;

procedure TTyFileDialogForm.SetFilterIndex(AValue: Integer);
begin
  FFilter.FilterIndex := AValue;
  FList.Mask := FFilter.Mask;
end;

procedure TTyFileDialogForm.SetOptions(AValue: TTyFileDialogOptions);
begin
  FOptions := AValue;
  { Multi-select is Open-mode only; the flag maps straight onto the list. }
  if FList <> nil then
    FList.MultiSelect := fdoAllowMultiSelect in AValue;
end;

function TTyFileDialogForm.CurrentDirectory: string;
begin
  Result := FList.Directory;
end;

{ ---------------------------------------------------------------------------
  Navigation + four-way wiring (an FSyncing guard breaks the loops)
  --------------------------------------------------------------------------- }

procedure TTyFileDialogForm.NavigateTo(const APath: string);
begin
  if (APath = '') or not DirectoryExistsUTF8(APath) then Exit;
  { LoadDirectory fires OnDirectoryChange -> ListDirectoryChange keeps the tree +
    look-in combo in step. A user action (not a sync), so FSyncing stays clear. }
  FList.LoadDirectory(APath);
end;

procedure TTyFileDialogForm.TreePathChange(Sender: TObject);
begin
  if FSyncing then Exit;
  FSyncing := True;
  try
    FList.LoadDirectory(FTree.SelectedPath);
  finally
    FSyncing := False;
  end;
end;

procedure TTyFileDialogForm.LookInSelectPath(Sender: TObject);
begin
  { A user action, NOT a sync: leave FSyncing clear so ListDirectoryChange reveals the
    picked directory in the tree (it sets FSyncing itself around SelectPath, so the
    TreePathChange that fires early-exits -- no loop). Setting it here would suppress
    the tree reveal and leave the tree highlight on the old directory. }
  NavigateTo(FLookIn.SelectedPath);
end;

procedure TTyFileDialogForm.ListDirectoryChange(Sender: TObject);
begin
  { Pure display sync of the look-in field (its setter fires no event + guards
    re-entry). }
  FLookIn.Directory := FList.Directory;
  { New Folder needs a directory to create the subfolder under -- enable it once the list
    is actually showing one (it starts disabled, before any navigation). }
  if FBtnNewFolder <> nil then
    FBtnNewFolder.Enabled := FList.Directory <> '';
  { Reveal the directory in the tree -- but only when the change did NOT originate
    from a tree/look-in navigation (else FSyncing is set and this would loop). }
  if not FSyncing then
  begin
    FSyncing := True;
    try
      FTree.SelectPath(FList.Directory);
    finally
      FSyncing := False;
    end;
  end;
end;

procedure TTyFileDialogForm.FilterChange(Sender: TObject);
begin
  FList.Mask := FFilter.Mask;
end;

procedure TTyFileDialogForm.ListSelectItem(Sender: TObject; AIndex: Integer;
  ASelected: Boolean);
begin
  { The event now also reports the row the user just LEFT (ASelected = False). Naming a
    file the user is no longer on would overwrite the edit with the wrong name -- and in
    Save mode, with a name they had already typed over. }
  if not ASelected then Exit;
  { Reflect the focused file's name into the edit (both modes -- Save lets the user
    edit it afterwards). A folder's name is intentionally not forced in. }
  if (FNameEdit <> nil) and (AIndex >= 0) then
  begin
    if not DirectoryExistsUTF8(FList.FileAt(AIndex)) then
      FNameEdit.Text := ExtractFileName(FList.FileAt(AIndex));
  end;
  RefreshPreview;
end;

procedure TTyFileDialogForm.ListFileActivate(Sender: TObject; AIndex: Integer);
begin
  { Fires for FILES only (a folder navigates internally). Fill the name; in Open
    mode a double-click on a file also accepts the dialog. }
  if AIndex >= 0 then
    FNameEdit.Text := ExtractFileName(FList.FileAt(AIndex));
  if not FSaveMode then
    ModalResult := mrOK;
end;

procedure TTyFileDialogForm.BtnUpClick(Sender: TObject);
begin
  NavigateTo(TyFsParent(FList.Directory));
end;

procedure TTyFileDialogForm.NewFolderClick(Sender: TObject);
var
  nm, full: string;
begin
  if FList.Directory = '' then Exit;   { no listed directory -> nothing to create under }
  nm := '';
  if not TyInputQuery(rsDlgNewFolder, rsDlgNewFolderPrompt, nm) then Exit;
  if nm = '' then Exit;
  full := AppendPathDelim(FList.Directory) + nm;
  if CreateDirUTF8(full) then
    { UpdateView, NOT Refresh: the shell list's Refresh now only repaints (LCL semantics);
      UpdateView re-reads the current directory from disk so the new folder actually shows. }
    FList.UpdateView
  else
    TyMessageDlg(Format(rsDlgCreateFolderErr, [full]), mtError, [mbOK]);
end;

{ ---------------------------------------------------------------------------
  Preview
  --------------------------------------------------------------------------- }

procedure TTyFileDialogForm.RefreshPreview;
var
  path: string;
  handled: Boolean;
begin
  if (not FPreviewMode) or (FPreview = nil) then Exit;
  FPreview.AllowText := FPreviewAllowsText;
  path := FList.SelectedFile;
  { Let a wired OnPreview render it (custom formats); AHandled skips the built-in. }
  handled := False;
  if Assigned(FOnPreview) then
    FOnPreview(Self, path, FPreview, handled);
  if not handled then
  begin
    if (path = '') or DirectoryExistsUTF8(path) then
      FPreview.Clear
    else
      FPreview.PreviewFile(path);   { crash-safe; unpreviewable -> a placeholder }
  end;
end;

{ ---------------------------------------------------------------------------
  OK validation -- CloseQuery -> AcceptSelection
  --------------------------------------------------------------------------- }

function TTyFileDialogForm.CloseQuery: Boolean;
begin
  { Respect any wired OnCanClose first, then gate an OK on our own validation. }
  Result := inherited CloseQuery;
  if not Result then Exit;
  if ModalResult <> mrOK then Exit;
  Result := AcceptSelection;   { False -> LCL resets ModalResult, dialog stays open }
end;

function TTyFileDialogForm.AcceptSelection: Boolean;
var
  i: Integer;
  f: string;
begin
  Result := False;
  if FSaveMode then
  begin
    { Save: resolve the typed name against the current directory. }
    FResultName := TyFileDialogResolveName(True, CurrentDirectory, FNameEdit.Text,
      FList.SelectedFile, FDefaultExt);
    if FResultName = '' then Exit;                       { empty name -> veto }
    if (fdoOverwritePrompt in FOptions) and FileExistsUTF8(FResultName) then
      if TyMessageDlg(Format(rsFdOverwritePrompt, [FResultName]),
           mtConfirmation, [mbYes, mbNo]) <> mrYes then
        Exit;                                            { declined -> veto }
    FFiles.Clear;
    FFiles.Add(FResultName);
    Result := True;
  end
  else
  begin
    { Open: collect the selected set, then the primary result. }
    FFiles.Clear;
    if FList.MultiSelect and (FList.SelCount > 1) then
    begin
      i := -1;
      while FList.GetNextSelected(i) do
      begin
        f := FList.FileAt(i);
        if (f <> '') and not DirectoryExistsUTF8(f) then   { files only }
          FFiles.Add(f);
      end;
    end;
    FResultName := TyFileDialogResolveName(False, CurrentDirectory, FNameEdit.Text,
      FList.SelectedFile, FDefaultExt);
    if FResultName = '' then Exit;                       { nothing chosen -> veto }
    if DirectoryExistsUTF8(FResultName) then
    begin
      { A folder resolved as the result (single-clicked + empty name box) -> enter it
        and keep the dialog open, rather than returning a directory as the chosen file. }
      NavigateTo(FResultName);
      Exit;
    end;
    if FFiles.Count = 0 then
      FFiles.Add(FResultName);
    if (fdoFileMustExist in FOptions) and not FileExistsUTF8(FResultName) then
    begin
      TyMessageDlg(Format(rsFdMustExist, [FResultName]), mtError, [mbOK]);
      Exit;                                              { missing -> veto }
    end;
    Result := True;
  end;
end;

{ ---------------------------------------------------------------------------
  Layout
  --------------------------------------------------------------------------- }

procedure TTyFileDialogForm.LayoutContent;
const
  RowH    = 30;    { = TyDlgEditH }
  LblH    = 20;
  LblW    = 64;
  UpW     = 72;
  FilterW = 180;   { fixed width of the file-type combo on the shared name row }
var
  cr: TRect;
  pad, x0, w, y, curRight, lookInX: Integer;
  yRow, nameX, filterX, filterLblX, nameW, midTop, midH: Integer;
begin
  if (FList = nil) or (FMidPanel = nil) then Exit;   { called during construction, before children exist }
  cr := ContentRect;
  pad := TyDlgPad;
  x0 := cr.Left + pad;
  w  := (cr.Right - cr.Left) - 2 * pad;

  { Row 1: look-in combo + Up, laid out right-to-left. (New Folder now lives on the bottom
    button bar, not here.) }
  y := cr.Top + pad;
  curRight := cr.Right - pad;
  FBtnUp.SetBounds(curRight - UpW, y, UpW, RowH);
  curRight := curRight - UpW - Gap;
  FLblLookIn.SetBounds(x0, y + (RowH - LblH) div 2, LblW, LblH);
  lookInX := x0 + LblW + Gap;
  FLookIn.SetBounds(lookInX, y, curRight - lookInX, RowH);

  { Bottom row -- ONE row now (Windows Open/Save idiom): the file-name edit fills the left,
    the file-type combo is a fixed-width field to its RIGHT. Collapsing what used to be two
    stacked rows hands the freed vertical space to the list. The right cluster
    ([File type:][combo]) is anchored to the right edge; the name edit stretches to meet it. }
  yRow := cr.Bottom - pad - RowH;
  filterX := (cr.Right - pad) - FilterW;
  FFilter.SetBounds(filterX, yRow, FilterW, RowH);
  filterLblX := filterX - Gap - LblW;
  FLblFilter.SetBounds(filterLblX, yRow + (RowH - LblH) div 2, LblW, LblH);
  FLblName.SetBounds(x0, yRow + (RowH - LblH) div 2, LblW, LblH);
  nameX := x0 + LblW + Gap;
  nameW := (filterLblX - Gap) - nameX;
  if nameW < 80 then nameW := 80;   { never collapse the name edit even on a very narrow dialog }
  FNameEdit.SetBounds(nameX, yRow, nameW, RowH);

  { Middle band: the host panel fills between the look-in row and the single name/type row;
    LCL alignment + the two splitters lay out tree | list | preview inside it. }
  midTop := y + RowH + Gap;
  midH := (yRow - Gap) - midTop;
  if midH < 60 then midH := 60;
  FMidPanel.SetBounds(x0, midTop, w, midH);
end;

{ ---------------------------------------------------------------------------
  Builder + globals
  --------------------------------------------------------------------------- }

function TyBuildFileDialog(ASaveMode, APreviewMode: Boolean; const ATitle: string): TTyFileDialogForm;
var
  btn: TTyButton;
begin
  Result := TTyFileDialogForm.CreateNew(Application);
  Result.SaveMode := ASaveMode;         { OK caption + save-name validation }
  Result.PreviewMode := APreviewMode;   { builds the preview pane }
  { A TTyDialog derives its title-bar text from the form Caption. }
  if ATitle <> '' then
    Result.Caption := ATitle
  else if ASaveMode then
    Result.Caption := rsFdSaveTitle
  else
    Result.Caption := rsFdOpenTitle;
  { OK/Cancel on the bottom button bar (OK caption differs by mode). }
  if ASaveMode then
    Result.AddButton(rsFdBtnSave, mrOK, True, False)
  else
    Result.AddButton(rsFdBtnOpen, mrOK, True, False);
  Result.AddButton(rsMsgBtnCancel, mrCancel, False, True);
  { New Folder: an mrNone action button (does NOT close the dialog) available in EVERY mode
    now (Open + Save), matching Windows. Added after OK/Cancel so it sits leftmost in the
    right-aligned cluster, clear of the primary buttons. Starts disabled; ListDirectoryChange
    enables it once the list is showing a directory (there must be a folder to create under).
    Same pattern as SelectPath's New-Folder button. }
  btn := Result.AddButton(rsDlgNewFolder, mrNone);
  btn.OnClick := @Result.NewFolderClick;
  btn.Enabled := False;
  Result.FBtnNewFolder := btn;
  { Sizing: open roughly twice as wide as the original (~520 -> ~950) and a little taller,
    because the file list was far too cramped. A preview pane needs room of its own ON TOP of
    that so the list is not squeezed to share the width with the preview. }
  if APreviewMode then
    Result.AutoSizeToContent(920 + 220 + 8, 420)
  else
    Result.AutoSizeToContent(920, 420);
  Result.LayoutContent;
end;

function TyOpenDialog(var AFileName: string; const AFilter: string): Boolean;
var
  d: TTyFileDialogForm;
begin
  d := TyBuildFileDialog(False, False, '');
  try
    if AFilter <> '' then d.Filter := AFilter else d.Filter := rsFdAllFilesFilter;
    d.FileName := AFileName;
    Result := (d.ShowModal = mrOK);
    if Result then AFileName := d.FileName;
  finally
    d.Free;
  end;
end;

function TySaveDialog(var AFileName: string; const AFilter, ADefaultExt: string): Boolean;
var
  d: TTyFileDialogForm;
begin
  d := TyBuildFileDialog(True, False, '');
  try
    if AFilter <> '' then d.Filter := AFilter else d.Filter := rsFdAllFilesFilter;
    d.DefaultExt := ADefaultExt;
    d.FileName := AFileName;
    Result := (d.ShowModal = mrOK);
    if Result then AFileName := d.FileName;
  finally
    d.Free;
  end;
end;

function TyOpenPictureDialog(var AFileName: string): Boolean;
var
  d: TTyFileDialogForm;
begin
  d := TyBuildFileDialog(False, True, '');
  try
    d.Filter := rsFdPictureFilter;
    d.FileName := AFileName;
    Result := (d.ShowModal = mrOK);
    if Result then AFileName := d.FileName;
  finally
    d.Free;
  end;
end;

function TySavePictureDialog(var AFileName: string): Boolean;
var
  d: TTyFileDialogForm;
begin
  d := TyBuildFileDialog(True, True, '');
  try
    d.Filter := rsFdPictureFilter;
    d.FileName := AFileName;
    Result := (d.ShowModal = mrOK);
    if Result then AFileName := d.FileName;
  finally
    d.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  TTyCustomFileDialog
  --------------------------------------------------------------------------- }

constructor TTyCustomFileDialog.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFiles := TStringList.Create;
  FFilterIndex := DefaultFilterIndex;
  FOptions := [];
end;

destructor TTyCustomFileDialog.Destroy;
begin
  FFiles.Free;
  inherited Destroy;
end;

function TTyCustomFileDialog.SaveMode: Boolean;
begin
  Result := False;
end;

function TTyCustomFileDialog.PreviewMode: Boolean;
begin
  Result := False;
end;

function TTyCustomFileDialog.PreviewAllowsText: Boolean;
begin
  Result := False;   { picture variants keep this False -> image-only preview }
end;

function TTyCustomFileDialog.DefaultFilter: string;
begin
  Result := rsFdAllFilesFilter;
end;

function TTyCustomFileDialog.Execute: Boolean;
var
  d: TTyFileDialogForm;
begin
  d := TyBuildFileDialog(SaveMode, PreviewMode, FTitle);
  try
    d.InitialDir := FInitialDir;
    if FFilter <> '' then d.Filter := FFilter else d.Filter := DefaultFilter;
    d.FilterIndex := FFilterIndex;
    d.DefaultExt := FDefaultExt;
    d.Options := FOptions;
    d.PreviewAllowsText := PreviewAllowsText;   { virtual: image-only vs image+text }
    d.OnPreview := FOnPreview;                  { custom-render hook (PreviewMode only) }
    d.FileName := FFileName;   { seed AFTER InitialDir so a path-bearing name wins }
    TyForwardDialogEvents(d, FOnShow, FOnClose, FOnCanClose);
    Result := (d.ShowModal = mrOK);
    if Result then
    begin
      FFileName := d.FileName;
      FFiles.Assign(d.Files);
    end;
  finally
    d.Free;
  end;
end;

{ Subclass flag overrides }

function TTySaveDialog.SaveMode: Boolean;
begin
  Result := True;
end;

function TTyOpenPictureDialog.PreviewMode: Boolean;
begin
  Result := True;
end;

function TTyOpenPictureDialog.DefaultFilter: string;
begin
  Result := rsFdPictureFilter;
end;

function TTySavePictureDialog.PreviewMode: Boolean;
begin
  Result := True;
end;

function TTySavePictureDialog.DefaultFilter: string;
begin
  Result := rsFdPictureFilter;
end;

function TTyOpenPreviewDialog.PreviewMode: Boolean;
begin
  Result := True;
end;

function TTyOpenPreviewDialog.PreviewAllowsText: Boolean;
begin
  Result := True;
end;

function TTyOpenPreviewDialog.DefaultFilter: string;
begin
  Result := rsFdCommonFilter;
end;

function TTySavePreviewDialog.PreviewMode: Boolean;
begin
  Result := True;
end;

function TTySavePreviewDialog.PreviewAllowsText: Boolean;
begin
  Result := True;
end;

function TTySavePreviewDialog.DefaultFilter: string;
begin
  Result := rsFdCommonFilter;
end;

{ ---------------------------------------------------------------------------
  Preview-dialog globals
  --------------------------------------------------------------------------- }

function TyOpenPreviewDialog(var AFileName: string): Boolean;
var
  d: TTyFileDialogForm;
begin
  d := TyBuildFileDialog(False, True, '');
  try
    d.PreviewAllowsText := True;
    d.Filter := rsFdCommonFilter;
    d.FileName := AFileName;
    Result := (d.ShowModal = mrOK);
    if Result then AFileName := d.FileName;
  finally
    d.Free;
  end;
end;

function TySavePreviewDialog(var AFileName, ADefaultExt: string): Boolean;
var
  d: TTyFileDialogForm;
begin
  d := TyBuildFileDialog(True, True, '');
  try
    d.PreviewAllowsText := True;
    d.Filter := rsFdCommonFilter;
    d.DefaultExt := ADefaultExt;
    d.FileName := AFileName;
    Result := (d.ShowModal = mrOK);
    if Result then AFileName := d.FileName;
  finally
    d.Free;
  end;
end;

initialization
  { So a .lfm that streams any of these resolves the class. }
  RegisterClass(TTyOpenDialog);
  RegisterClass(TTySaveDialog);
  RegisterClass(TTyOpenPictureDialog);
  RegisterClass(TTySavePictureDialog);
  RegisterClass(TTyOpenPreviewDialog);
  RegisterClass(TTySavePreviewDialog);

end.
