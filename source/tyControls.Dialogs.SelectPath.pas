unit tyControls.Dialogs.SelectPath;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Dialogs, Forms, Graphics, ImgList, LazFileUtils,
  tyControls.Dialogs, tyControls.TreeView, tyControls.Button, tyControls.Edit,
  tyControls.StrConsts, tyControls.Component, tyControls.FileSystem,
  tyControls.Controller;

function TySubdirectories(const APath: string): TStringArray;
function TyPathHasSubdir(const APath: string): Boolean;
function TyDriveRoots: TStringArray;

type
  { What OK may do with a folder path (LCL's TSelectDirectoryDialog reading of TOpenOptions). }
  TTySelectPathCheck = (
    spcOK,             // accept (a missing path with none of the options below: the tree's choice)
    spcParentMissing,  // ofPathMustExist: the folder above it does not exist -> error
    spcMissing,        // ofFileMustExist: the folder itself does not exist -> error
    spcNotWritable,    // ofNoReadOnlyReturn: an existing folder that cannot be written to
    spcAskCreate       // ofCreatePrompt: it does not exist -> ask, Yes creates it
  );

{ For an existing folder only ofNoReadOnlyReturn applies. For a missing one, in order:
  ofPathMustExist (parent), ofFileMustExist, ofCreatePrompt; with none of them it is spcOK,
  which leaves the dialog to return the tree's choice, as 3.0 did. APath is a full path: the
  dialog turns a relative one typed into its path field into one first (TypedPath). }
function TySelectPathCheck(const APath: string; AOptions: TOpenOptions): TTySelectPathCheck;

type
  { Concrete resizable directory-tree folder picker. Declared in the interface so
    the tree callbacks + the New-Folder click can be proper method pointers
    ("of object"). Callers normally hold it via the builder / TySelectDirectory. }
  TTySelectPathForm = class(TTyDialog)
  private
    FTree:  TTyTreeView;
    FPathEdit: TTyEdit;    // top-of-content path field: shows the selection, accepts typed/pasted paths
    FSyncing:  Boolean;    // guards the edit<->tree two-way sync from re-entering
    FPaths: TStringList;   // node-data index -> absolute path (owned; freed in dtor)
    FRoot:  string;        // '' = all drive roots, else a single rooted subtree
    FIcons: TImageList;    // 16x16 folder glyph(s); owned by the form (Self)
    FNewBtn: TTyButton;    // "New Folder" action button; enabled only when a node is selected
    FOptions: TOpenOptions;
    procedure BuildIcons;
    // Reveal APath in the tree (expand roots->leaf lazily) and return its node, or the
    // deepest reachable one; nil if no root is a prefix. Best-effort (visual feedback only).
    function  RevealPath(const APath: string): PTyTreeNode;
    // The path field changed (typed / pasted): if it names an existing directory by its full
    // path, reveal + select it in the tree. Guarded against the tree->edit sync.
    procedure PathEditChanged(Sender: TObject);
    // Node-data helpers (node data = an Integer index into FPaths).
    function  AddPathNode(AParent: PTyTreeNode; const AFullPath: string): PTyTreeNode;
    function  NodePath(Node: PTyTreeNode): string;
    procedure PopulateChildren(Node: PTyTreeNode);
    // Tree event handlers.
    procedure TreeGetText(Sender: TTyCustomTreeView; Node: PTyTreeNode; var AText: string);
    procedure TreeInitNode(Sender: TTyCustomTreeView; ParentNode, Node: PTyTreeNode;
      var InitStates: TTyNodeInitStates);
    procedure TreeExpanding(Sender: TTyCustomTreeView; Node: PTyTreeNode; var Allowed: Boolean);
    procedure TreeGetImageIndex(Sender: TTyCustomTreeView; Node: PTyTreeNode;
      Kind: TTyVTImageKind; Column: Integer; var Ghosted: Boolean; var ImageIndex: Integer);
    procedure TreeFocusChanged(Sender: TTyCustomTreeView; Node: PTyTreeNode);
    procedure NewFolderClick(Sender: TObject);
    { mrOK validation per Options: a typed folder that does not exist, then the result's
      writability. False keeps the dialog open. }
    function  AcceptSelection: Boolean;
  protected
    procedure LayoutContent; override;
    { Says why OK was refused: an error box. Virtual so a test can read the message instead of
      putting a modal window up. }
    procedure ReportProblem(const AMsg: string); virtual;
    { Asks a yes / no question before OK goes through (ofCreatePrompt); True = yes. Virtual for
      the same reason. }
    function  ConfirmChoice(const AMsg: string): Boolean; virtual;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    destructor  Destroy; override;
    function  CloseQuery: Boolean; override;
    // Add one root node per configured source (a single FRoot, else every drive).
    procedure PopulateRoots;
    function  SelectedPath: string;
    procedure SetDirectory(const APath: string);
    { The path field as a folder. A full path as typed; a relative one is taken under the
      folder selected in the tree -- the field shows that folder's full path, so a bare name
      typed over it means "in here", as in the Windows folder picker -- and never under the
      program's current directory. '' when the field is empty, or relative with no folder
      selected. }
    function  TypedPath: string;
    // test seam: the path field, as the user types into it
    function  PathEdit: TTyEdit;
    // The in/out selection (idiomatic dialog pattern): assign before ShowModal to pre-select a
    // folder (reveal + focus it); read after OK for the chosen folder. No-op if unreachable.
    property  Directory: string read SelectedPath write SetDirectory;
    // Create a subfolder AName under AParent, refresh the tree so it shows, and
    // focus/select it. Returns True on success. Non-modal — the headless-testable
    // seam that NewFolderClick wraps around TyInputQuery.
    function  CreateSubfolder(AParent: PTyTreeNode; const AName: string): Boolean;
    // Test/introspection seam: the display text a node renders (same path as OnGetText).
    function  NodeText(Node: PTyTreeNode): string;
    property  Tree: TTyTreeView read FTree;
    property  Root: string read FRoot write FRoot;
    { LCL's TOpenOptions as a folder picker reads them; see TySelectPathCheck. }
    property  Options: TOpenOptions read FOptions write FOptions;
  end;

{ Construct-only builder: create + configure + populate roots + size. No ShowModal. }
function TyBuildSelectPathDialog(const ACaption, ARoot: string): TTySelectPathForm;
{ Show a folder picker modally; on OK, ADir := chosen path. Leak-safe. }
function TySelectDirectory(const ACaption, ARoot: string; var ADir: string): Boolean;

type
  TTySelectPathDialog = class(TTyComponent)
  private
    FCaption, FRoot, FDirectory: string;
    FOnShow: TNotifyEvent;
    FOnClose: TCloseEvent;
    FOnCanClose: TCloseQueryEvent;
    FOptions: TOpenOptions;
    FOnHelpClicked: TNotifyEvent;
    procedure FormHelpClick(Sender: TObject);
  public
    { The form Execute shows -- roots, the pre-selected Directory, Options, Help under
      ofShowHelp, the three events forwarded -- without showing it. The caller frees it. }
    function BuildForm: TTySelectPathForm;
    function Execute: Boolean;
  published
    { The universal properties the base classes stopped publishing in 4.0 (LCL visibility);
      RTTI order is the 3.0 order. }
    property Version;
    property Caption: TCaption read FCaption write FCaption;
    property Root: string read FRoot write FRoot;
    property Directory: string read FDirectory write FDirectory;
    property OnShow: TNotifyEvent read FOnShow write FOnShow;
    property OnClose: TCloseEvent read FOnClose write FOnClose;
    property OnCanClose: TCloseQueryEvent read FOnCanClose write FOnCanClose;
    { LCL's TOpenOptions, as LCL's TSelectDirectoryDialog has them. ofPathMustExist,
      ofFileMustExist, ofCreatePrompt and ofNoReadOnlyReturn check the folder on OK,
      ofShowHelp adds Help, and without ofNoResolveLinks the result's links are resolved;
      the rest have no effect or do not apply -- see docs/controls/dialogs.md. }
    property Options: TOpenOptions read FOptions write FOptions default [];
    { The Help button (shown with ofShowHelp) was clicked. Sender is this component. }
    property OnHelpClicked: TNotifyEvent read FOnHelpClicked write FOnHelpClicked;
  end;

implementation

function TySubdirectories(const APath: string): TStringArray;
var
  entries: TTyFsEntryArray;
  list: TStringList;
  i: Integer;
begin
  Result := nil;
  { Delegate the enumeration to the shell FileSystem unit (UTF8-correct, one code
    path) but keep this helper's own contract: subdirectory NAMES, hidden included,
    case-insensitively sorted. fotFolders drops files; fotHidden keeps hidden dirs. }
  entries := TyFsReadDirectory(APath, '*', [fotFolders, fotHidden]);
  list := TStringList.Create;
  try
    list.CaseSensitive := False;
    for i := 0 to High(entries) do
      list.Add(entries[i].Name);
    list.Sort;   // case-insensitive because CaseSensitive := False
    SetLength(Result, list.Count);
    for i := 0 to list.Count - 1 do
      Result[i] := list[i];
  finally
    list.Free;
  end;
end;

function TyPathHasSubdir(const APath: string): Boolean;
begin
  { Same semantics as Length(TySubdirectories(APath)) > 0 -- any subdirectory,
    hidden counted -- but stops at the first hit instead of listing them all. }
  Result := TyFsHasSubdir(APath);
end;

{ Deliberately NOT delegated to tyControls.FileSystem.TyFsRoots: this picker's root
  set is drives-only (Unix = just '/'), while TyFsRoots also surfaces home + mounted
  volumes. Folding them would change this dialog's root list, so it stays standalone. }
function TyDriveRoots: TStringArray;
{$IFDEF MSWINDOWS}
var
  c: Char;
  n: Integer;
begin
  Result := nil;
  n := 0;
  for c := 'A' to 'Z' do
    if DirectoryExists(c + ':\') then
    begin
      SetLength(Result, n + 1);
      Result[n] := c + ':\';
      Inc(n);
    end;
end;
{$ELSE}
begin
  SetLength(Result, 1);
  Result[0] := '/';
end;
{$ENDIF}

function TySelectPathCheck(const APath: string; AOptions: TOpenOptions): TTySelectPathCheck;
var
  p, parent: string;
begin
  Result := spcOK;
  p := Trim(APath);
  if p = '' then Exit;
  if DirectoryExistsUTF8(p) then
  begin
    if (ofNoReadOnlyReturn in AOptions) and not DirectoryIsWritable(p) then
      Result := spcNotWritable;
    Exit;
  end;
  parent := ExtractFileDir(ExcludeTrailingPathDelimiter(p));
  if (ofPathMustExist in AOptions) and (parent <> '') and not DirectoryExistsUTF8(parent) then
    Exit(spcParentMissing);
  if ofFileMustExist in AOptions then Exit(spcMissing);
  if ofCreatePrompt in AOptions then Exit(spcAskCreate);
end;

{ TTySelectPathForm }

constructor TTySelectPathForm.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  Resizable := True;
  Constraints.MinWidth  := Px(320);
  Constraints.MinHeight := Px(320);
  FPaths := TStringList.Create;
  BuildIcons;
  FTree := TTyTreeView.Create(Self);
  FTree.Parent := Self;
  { node data = one Integer index into FPaths; no managed types in raw node memory }
  FTree.NodeDataSize   := SizeOf(Integer);
  FTree.OnGetText      := @TreeGetText;
  FTree.OnInitNode     := @TreeInitNode;
  FTree.OnExpanding    := @TreeExpanding;
  FTree.Images         := FIcons;
  FTree.OnGetImageIndex := @TreeGetImageIndex;
  { Enable/disable the New-Folder button as the focused (folder) node changes. }
  FTree.OnFocusChanged  := @TreeFocusChanged;
  { Appearance: the default 18px row is cramped once a 16px icon is added;
    HotTrack lights up the theme's TyTreeNode:hover state on mouse-over
    (previously dead code — no hover feedback at all). ShowRoot=True gives the
    top-level (drive/root) nodes their own expand triangle — with ShowRoot=False
    a root node's indent collapses to 0 and its expand button is pushed off the
    left edge, so the user cannot expand roots from the triangle. }
  FTree.DefaultNodeHeight := 22;
  FTree.HotTrack          := True;
  FTree.ShowRoot          := True;
  { This is a PICKER: the folder pre-selected via Directory (or typed into the path
    field) must stay visibly highlighted even though initial keyboard focus sits on the
    path edit, not the tree. HideSelection=True (LCL default) would hide the highlight
    of an unfocused tree, so the pre-selection looked unselected. }
  FTree.HideSelection     := False;
  { Path field at the top of the content: mirrors the tree selection and lets the
    user type or paste a folder path to jump straight to it. }
  FPathEdit := TTyEdit.Create(Self);
  FPathEdit.Parent   := Self;
  FPathEdit.TextHint := rsDlgFolderPath;
  FPathEdit.OnChange := @PathEditChanged;
end;

{ Build a single 16x16 manila-folder glyph (amber body + darker back-tab lip,
  clFuchsia-keyed so it composites transparently on any theme). Ported from
  the folder glyph in examples/treeview/showcasemain.pas (BuildFileIcons). }
procedure TTySelectPathForm.BuildIcons;
var
  bmp: TBitmap;
  C: TCanvas;
begin
  FIcons := TImageList.Create(Self);   { Owner = form -> auto-freed }
  FIcons.Width  := 16;
  FIcons.Height := 16;

  bmp := TBitmap.Create;
  try
    bmp.SetSize(16, 16);
    bmp.Canvas.Brush.Color := clFuchsia;   { transparency key }
    bmp.Canvas.FillRect(0, 0, 16, 16);
    bmp.Canvas.Pen.Style := psSolid;
    bmp.Canvas.Pen.Width := 1;

    C := bmp.Canvas;
    C.Brush.Color := $0033B0E8;   { warm amber body (BGR of #E8B033) }
    C.Pen.Color   := $001E84B8;   { darker amber edge }
    C.RoundRect(1, 5, 15, 14, 3, 3);
    { Back tab lip peeking over the top-left. }
    C.Brush.Color := $0055C8F0;
    C.Pen.Color   := $001E84B8;
    C.Polygon([Point(2, 5), Point(2, 3), Point(6, 3), Point(8, 5)]);
    FIcons.AddMasked(bmp, clFuchsia);
  finally
    bmp.Free;
  end;
end;

destructor TTySelectPathForm.Destroy;
begin
  FPaths.Free;    // FTree is owned by the form (Create(Self)) and freed with it
  inherited Destroy;
end;

function TTySelectPathForm.CloseQuery: Boolean;
begin
  { A wired OnCanClose first, then gate an OK on the options. }
  Result := inherited CloseQuery;
  if not Result then Exit;
  if ModalResult <> mrOK then Exit;
  Result := AcceptSelection;   // False -> LCL resets ModalResult, the dialog stays open
end;

function TTySelectPathForm.AcceptSelection: Boolean;
var
  raw, typed, dir: string;
begin
  Result := False;
  raw := '';
  if FPathEdit <> nil then raw := Trim(FPathEdit.Text);
  typed := TypedPath;
  if (raw <> '') and (typed = '')
     and (FOptions * [ofPathMustExist, ofFileMustExist, ofCreatePrompt] <> []) then
  begin
    { A relative name with no folder selected to put it under: no folder it could mean
      exists, and creating it would put it wherever the program happens to run. }
    ReportProblem(Format(rsFdPathMustExist, [raw]));
    Exit;
  end;
  if (typed <> '') and not DirectoryExistsUTF8(typed) then
    case TySelectPathCheck(typed, FOptions) of
      spcParentMissing:
        begin
          ReportProblem(Format(rsFdPathMustExist,
            [ExtractFileDir(ExcludeTrailingPathDelimiter(typed))]));
          Exit;
        end;
      spcMissing:
        begin
          ReportProblem(Format(rsFdPathMustExist, [typed]));
          Exit;
        end;
      spcAskCreate:
        begin
          if not ConfirmChoice(Format(rsFdCreatePrompt, [typed])) then Exit;
          if not ForceDirectoriesUTF8(typed) then
          begin
            ReportProblem(Format(rsDlgCreateFolderErr, [typed]));
            Exit;
          end;
          { it exists now, so SelectedPath below returns it }
        end;
    end;
  dir := SelectedPath;
  if (dir <> '') and (TySelectPathCheck(dir, FOptions) = spcNotWritable) then
  begin
    ReportProblem(Format(rsFdNotWritable, [dir]));
    Exit;
  end;
  Result := True;
end;

procedure TTySelectPathForm.ReportProblem(const AMsg: string);
begin
  TyMessageDlg(AMsg, mtError, [mbOK]);
end;

function TTySelectPathForm.ConfirmChoice(const AMsg: string): Boolean;
begin
  Result := TyMessageDlg(AMsg, mtConfirmation, [mbYes, mbNo]) = mrYes;
end;

function TTySelectPathForm.TypedPath: string;
var s, base: string;
begin
  Result := '';
  if FPathEdit = nil then Exit;
  s := Trim(FPathEdit.Text);
  if s = '' then Exit;
  if FilenameIsAbsolute(s) then Exit(s);
  base := NodePath(FTree.FocusedNode);
  if base = '' then Exit;
  Result := CreateAbsolutePath(s, base);
end;

function TTySelectPathForm.PathEdit: TTyEdit;
begin
  Result := FPathEdit;
end;

function TTySelectPathForm.AddPathNode(AParent: PTyTreeNode; const AFullPath: string): PTyTreeNode;
begin
  Result := FTree.AddChild(AParent);
  PInteger(FTree.GetNodeData(Result))^ := FPaths.Add(AFullPath);
  { Materialise this node now (headless: no paint loop to lazy-init it) so its
    has-children arrow is stamped via OnInitNode based on TyPathHasSubdir. }
  FTree.InitNode(Result);
end;

function TTySelectPathForm.NodePath(Node: PTyTreeNode): string;
var p: Pointer; idx: Integer;
begin
  Result := '';
  if Node = nil then Exit;
  p := FTree.GetNodeData(Node);
  if p = nil then Exit;
  idx := PInteger(p)^;
  if (idx >= 0) and (idx < FPaths.Count) then
    Result := FPaths[idx];
end;

procedure TTySelectPathForm.PopulateChildren(Node: PTyTreeNode);
var subs: TStringArray; i: Integer; base: string;
begin
  base := IncludeTrailingPathDelimiter(NodePath(Node));
  subs := TySubdirectories(NodePath(Node));
  for i := 0 to High(subs) do
    AddPathNode(Node, base + subs[i]);
end;

procedure TTySelectPathForm.PopulateRoots;
var roots: TStringArray; i: Integer;
begin
  FTree.Clear;
  FPaths.Clear;
  if (FRoot <> '') and DirectoryExists(FRoot) then
    AddPathNode(nil, FRoot)
  else
  begin
    roots := TyDriveRoots;
    for i := 0 to High(roots) do
      AddPathNode(nil, roots[i]);
  end;
end;

procedure TTySelectPathForm.TreeGetText(Sender: TTyCustomTreeView; Node: PTyTreeNode; var AText: string);
var p: string;
begin
  p := NodePath(Node);
  AText := ExtractFileName(ExcludeTrailingPathDelimiter(p));
  if AText = '' then AText := p;   // a drive root like 'C:\' collapses to '' above
end;

procedure TTySelectPathForm.TreeInitNode(Sender: TTyCustomTreeView;
  ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates);
begin
  { show an expand arrow iff this directory actually has subdirectories }
  if TyPathHasSubdir(NodePath(Node)) then
    Include(InitStates, ivsHasChildren);
end;

procedure TTySelectPathForm.TreeGetImageIndex(Sender: TTyCustomTreeView; Node: PTyTreeNode;
  Kind: TTyVTImageKind; Column: Integer; var Ghosted: Boolean; var ImageIndex: Integer);
begin
  { Single folder glyph for every node — every entry in this tree is a
    directory, so there is no file/folder distinction to make. }
  ImageIndex := 0;
end;

procedure TTySelectPathForm.TreeExpanding(Sender: TTyCustomTreeView; Node: PTyTreeNode; var Allowed: Boolean);
begin
  Allowed := True;
  { lazy population: enumerate subdirs on first expand only. AddChild bumps
    ChildCount, so the base SetExpanded's InitChildren call no-ops (its
    ChildCount>0 guard) — the two materialisation models never collide. }
  if Node^.ChildCount = 0 then
    PopulateChildren(Node);
end;

function TTySelectPathForm.CreateSubfolder(AParent: PTyTreeNode; const AName: string): Boolean;
var full: string; child, found: PTyTreeNode;
begin
  Result := False;
  if (AParent = nil) or (AName = '') then Exit;
  full := IncludeTrailingPathDelimiter(NodePath(AParent)) + AName;
  if not CreateDir(full) then Exit;
  Result := True;

  { Refresh so the new folder shows. The tree has NO re-init API (ivsReInit is
    declared but never consumed; InitNode early-exits on nsInitialized), so the
    "collapse + SetChildCount(0) + InitNode + expand" chain is a dead end —
    SetChildCount(0) clears nsHasChildren and nothing re-stamps it, so the expand
    bails. Use incremental add instead. }
  if (nsExpanded in AParent^.States) and (AParent^.ChildCount > 0) then
    { Parent already expanded + populated: append the new folder as a child.
      AddChild also (re)sets nsHasChildren on the parent (TreeView.pas:2060). }
    found := AddPathNode(AParent, full)
  else
  begin
    { Parent not yet populated: force a full (sorted) populate so EVERY subdir —
      including the new one — is listed. AddPathNode on the parent has already
      created the dir on disk, so TyPathHasSubdir is now true; AddChild inside
      PopulateChildren stamps nsHasChildren, letting the expand proceed. First
      ensure children are cleared so PopulateChildren's ChildCount=0 guard runs. }
    if AParent^.ChildCount > 0 then FTree.SetChildCount(AParent, 0);
    { nsHasChildren is required by SetExpanded; the dir now has ≥1 subdir. Seed one
      child so nsHasChildren is set, then re-clear and let the expand fully populate. }
    if not (nsHasChildren in AParent^.States) then
    begin
      AddPathNode(AParent, full);          // sets nsHasChildren on AParent
      FTree.SetChildCount(AParent, 0);     // drop the seed; keep nsHasChildren (ChildCount checked, not the flag)
      Include(AParent^.States, nsHasChildren);  // SetChildCount(0) cleared it — re-assert
    end;
    FTree.Expanded[AParent] := True;       // OnExpanding -> PopulateChildren lists all subdirs sorted
    { locate the freshly-created folder among the now-materialised children }
    found := nil;
    child := FTree.GetFirstChild(AParent);
    while child <> nil do
    begin
      if SameFileName(ExcludeTrailingPathDelimiter(NodePath(child)),
                      ExcludeTrailingPathDelimiter(full)) then
      begin found := child; Break; end;
      child := FTree.GetNextSibling(child);
    end;
  end;

  if found <> nil then FTree.FocusedNode := found;
end;

procedure TTySelectPathForm.TreeFocusChanged(Sender: TTyCustomTreeView; Node: PTyTreeNode);
begin
  { Every node in this tree is a folder, so "a folder node is selected" reduces
    to "the tree has a focused node". Node is nil when nothing is selected. }
  if FNewBtn <> nil then
    FNewBtn.Enabled := (Node <> nil);
  { Mirror the selection into the path field (guarded so the OnChange it triggers
    does not bounce back into RevealPath). }
  if FPathEdit <> nil then
  begin
    FSyncing := True;
    try FPathEdit.Text := NodePath(Node); finally FSyncing := False; end;
  end;
end;

function TTySelectPathForm.RevealPath(const APath: string): PTyTreeNode;

  // True when ABase is ADir itself or a parent directory of it (case-insensitive,
  // component-aware so 'C:\Us' is not treated as a prefix of 'C:\Users').
  function IsSelfOrAncestor(const ABase, ADir: string): Boolean;
  begin
    Result := SameFileName(ABase, ADir) or
      ((Length(ADir) > Length(ABase)) and
       SameFileName(Copy(ADir, 1, Length(ABase)), ABase) and
       (ADir[Length(ABase) + 1] = PathDelim));
  end;

var
  target, cur: string;
  node, child, match: PTyTreeNode;
begin
  Result := nil;
  target := ExcludeTrailingPathDelimiter(Trim(APath));
  if target = '' then Exit;

  { Find the root node (drive root or FRoot) that contains the target. }
  match := nil;
  node := FTree.GetFirst;
  while node <> nil do
  begin
    if IsSelfOrAncestor(ExcludeTrailingPathDelimiter(NodePath(node)), target) then
    begin match := node; Break; end;
    node := FTree.GetNextSibling(node);
  end;
  if match = nil then Exit;

  { Descend segment by segment: expand (lazily populates children) then pick the
    child that still contains the target. Stop at the target or the deepest reachable. }
  node := match;
  while not SameFileName(ExcludeTrailingPathDelimiter(NodePath(node)), target) do
  begin
    FTree.Expanded[node] := True;
    match := nil;
    child := FTree.GetFirstChild(node);
    while child <> nil do
    begin
      cur := ExcludeTrailingPathDelimiter(NodePath(child));
      if IsSelfOrAncestor(cur, target) then begin match := child; Break; end;
      child := FTree.GetNextSibling(child);
    end;
    if match = nil then Break;   // a segment is missing (permissions / case) — stop here
    node := match;
  end;
  Result := node;
end;

procedure TTySelectPathForm.PathEditChanged(Sender: TObject);
var s: string; node: PTyTreeNode;
begin
  if FSyncing then Exit;   // change came from TreeFocusChanged, not the user
  s := Trim(FPathEdit.Text);
  { Only a full path is followed while typing. A relative one is resolved against the selected
    folder on OK (TypedPath); following it here would move that folder under the user's fingers
    -- and DirectoryExists would read it against the current directory. }
  if (s = '') or not FilenameIsAbsolute(s) or not DirectoryExists(s) then Exit;
  node := RevealPath(s);
  if node <> nil then
    FTree.FocusedNode := node;   // fires TreeFocusChanged -> re-syncs the field (guarded)
end;

procedure TTySelectPathForm.NewFolderClick(Sender: TObject);
var parentNode: PTyTreeNode; nm: string;
begin
  parentNode := FTree.FocusedNode;
  if parentNode = nil then Exit;
  nm := '';
  if not TyInputQuery(rsDlgNewFolder, rsDlgNewFolderPrompt, nm) then Exit;
  if nm = '' then Exit;
  if not CreateSubfolder(parentNode, nm) then
    TyMessageDlg(Format(rsDlgCreateFolderErr,
      [IncludeTrailingPathDelimiter(NodePath(parentNode)) + nm]), mtError, [mbOK]);
end;

procedure TTySelectPathForm.LayoutContent;
const Gap = 8;
var r: TRect; x, w, editH: Integer;
begin
  if FTree = nil then Exit;
  { Every number below is a 96-PPI design number and goes through Px: see TTyDialog.Px. }
  r := ContentRect;
  x := r.Left + Px(TyDlgPad);
  w := (r.Right - r.Left) - 2 * Px(TyDlgPad);
  { Density-aware like every other field -- the sibling IconBrowser already reads it this
    way; this one kept the classic literal and came up short under modern density. }
  editH := Px(TyDensityHeight(Controller, TyDlgEditH));
  { Path field across the top, tree fills the rest. The tree starts below the field AS IT
    IS, not as it was asked to be: SetBounds clamps a control up to its own floor. }
  if FPathEdit <> nil then
  begin
    FPathEdit.SetBounds(x, r.Top + Px(TyDlgPad), w, editH);
    editH := FPathEdit.Height;
  end;
  FTree.SetBounds(x, r.Top + Px(TyDlgPad) + editH + Px(Gap), w,
    (r.Bottom - r.Top) - 2 * Px(TyDlgPad) - editH - Px(Gap));
end;

procedure TTySelectPathForm.SetDirectory(const APath: string);
var node: PTyTreeNode;
begin
  if Trim(APath) = '' then Exit;
  node := RevealPath(APath);
  if node <> nil then
  begin
    FTree.FocusedNode := node;    // fires TreeFocusChanged -> syncs the path field
    FTree.ScrollIntoView(node);   // FocusedNode does not scroll on its own; bring a deep node into view
  end;
end;

function TTySelectPathForm.SelectedPath: string;
var s: string;
begin
  { The path field is the source of truth: it mirrors the tree selection AND holds
    any directly typed/pasted path. Prefer it when it names an existing folder (covers
    a pasted path the tree could not reveal); otherwise fall back to the tree node. }
  s := TypedPath;
  if (s <> '') and DirectoryExists(s) then
    Exit(s);
  Result := NodePath(FTree.FocusedNode);
end;

function TTySelectPathForm.NodeText(Node: PTyTreeNode): string;
begin
  Result := '';
  TreeGetText(FTree, Node, Result);
end;

{ Free functions }

function TyBuildSelectPathDialog(const ACaption, ARoot: string): TTySelectPathForm;
var btn: TTyButton;
begin
  Result := TTySelectPathForm.CreateNew(Application);
  { A TTyDialog title bar renders the form Caption; default to the localized
    "Select Folder" so the title bar is never blank. }
  if ACaption <> '' then
    Result.Caption := ACaption
  else
    Result.Caption := rsDlgSelectPathTitle;
  Result.Root := ARoot;
  Result.PopulateRoots;
  { New Folder (left of OK/Cancel) is an mrNone action button — it must NOT close
    the dialog; wire its click to create a folder under the focused node. Start
    disabled; TreeFocusChanged enables it once a folder node is selected. }
  btn := Result.AddButton(rsDlgNewFolder, mrNone);
  btn.OnClick := @Result.NewFolderClick;
  btn.Enabled := False;
  Result.FNewBtn := btn;
  Result.AddButton(rsMsgBtnOK, mrOK, True, False);
  Result.AddButton(rsMsgBtnCancel, mrCancel, False, True);
  Result.AutoSizeToContent(Result.Px(360), Result.Px(420));
  Result.LayoutContent;
end;

function TySelectDirectory(const ACaption, ARoot: string; var ADir: string): Boolean;
var d: TTySelectPathForm;
begin
  d := TyBuildSelectPathDialog(ACaption, ARoot);
  try
    d.Directory := ADir;                    // pre-select the current directory (in)
    Result := (d.ShowModal = mrOK);
    if Result then ADir := d.Directory;     // chosen directory (out)
  finally d.Free; end;
end;

{ TTySelectPathDialog }

function TTySelectPathDialog.BuildForm: TTySelectPathForm;
var btn: TTyButton;
begin
  Result := TyBuildSelectPathDialog(FCaption, FRoot);
  Result.Options := FOptions;
  Result.Directory := FDirectory;              // pre-select the current directory (in)
  if ofShowHelp in FOptions then
  begin
    btn := Result.AddButton(rsMsgBtnHelp, mrNone);   // mrNone: the dialog stays open
    btn.OnClick := @FormHelpClick;
  end;
  // The wrapper's OnShow/OnClose/OnCanClose forward onto the form before it shows.
  TyForwardDialogEvents(Result, FOnShow, FOnClose, FOnCanClose);
end;

procedure TTySelectPathDialog.FormHelpClick(Sender: TObject);
begin
  if Assigned(FOnHelpClicked) then FOnHelpClicked(Self);
end;

function TTySelectPathDialog.Execute: Boolean;
var
  d: TTySelectPathForm;
  dir: string;
begin
  d := BuildForm;
  try
    Result := (d.ShowModal = mrOK);
    if Result then
    begin
      dir := d.Directory;                      // chosen directory (out)
      { LCL's TOpenDialog.DoExecute: links resolved unless ofNoResolveLinks (Unix; Windows
        returns the name as it is). }
      if (dir <> '') and not (ofNoResolveLinks in FOptions) then
        dir := GetPhysicalFilename(dir, pfeOriginal);
      FDirectory := dir;
    end;
  finally d.Free; end;
end;

end.
