unit tyControls.Dialogs.SelectPath;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Dialogs, Forms, Graphics, ImgList,
  tyControls.Dialogs, tyControls.TreeView, tyControls.Button, tyControls.Edit,
  tyControls.StrConsts;

function TySubdirectories(const APath: string): TStringArray;
function TyPathHasSubdir(const APath: string): Boolean;
function TyDriveRoots: TStringArray;

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
    procedure BuildIcons;
    // Reveal APath in the tree (expand roots->leaf lazily) and return its node, or the
    // deepest reachable one; nil if no root is a prefix. Best-effort (visual feedback only).
    function  RevealPath(const APath: string): PTyTreeNode;
    // The path field changed (typed / pasted): if it names an existing directory, reveal
    // + select it in the tree. Guarded against the tree->edit sync.
    procedure PathEditChanged(Sender: TObject);
    // Node-data helpers (node data = an Integer index into FPaths).
    function  AddPathNode(AParent: PTyTreeNode; const AFullPath: string): PTyTreeNode;
    function  NodePath(Node: PTyTreeNode): string;
    procedure PopulateChildren(Node: PTyTreeNode);
    // Tree event handlers.
    procedure TreeGetText(Sender: TTyTreeView; Node: PTyTreeNode; var AText: string);
    procedure TreeInitNode(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
      var InitStates: TTyNodeInitStates);
    procedure TreeExpanding(Sender: TTyTreeView; Node: PTyTreeNode; var Allowed: Boolean);
    procedure TreeGetImageIndex(Sender: TTyTreeView; Node: PTyTreeNode;
      Kind: TTyVTImageKind; Column: Integer; var Ghosted: Boolean; var ImageIndex: Integer);
    procedure TreeFocusChanged(Sender: TTyTreeView; Node: PTyTreeNode);
    procedure NewFolderClick(Sender: TObject);
  protected
    procedure LayoutContent; override;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    destructor  Destroy; override;
    // Add one root node per configured source (a single FRoot, else every drive).
    procedure PopulateRoots;
    function  SelectedPath: string;
    // Create a subfolder AName under AParent, refresh the tree so it shows, and
    // focus/select it. Returns True on success. Non-modal — the headless-testable
    // seam that NewFolderClick wraps around TyInputQuery.
    function  CreateSubfolder(AParent: PTyTreeNode; const AName: string): Boolean;
    // Test/introspection seam: the display text a node renders (same path as OnGetText).
    function  NodeText(Node: PTyTreeNode): string;
    property  Tree: TTyTreeView read FTree;
    property  Root: string read FRoot write FRoot;
  end;

{ Construct-only builder: create + configure + populate roots + size. No ShowModal. }
function TyBuildSelectPathDialog(const ACaption, ARoot: string): TTySelectPathForm;
{ Show a folder picker modally; on OK, ADir := chosen path. Leak-safe. }
function TySelectDirectory(const ACaption, ARoot: string; var ADir: string): Boolean;

type
  TTySelectPathDialog = class(TComponent)
  private
    FCaption, FRoot, FDirectory: string;
    FOnShow: TNotifyEvent;
    FOnClose: TCloseEvent;
    FOnCanClose: TCloseQueryEvent;
  public
    function Execute: Boolean;
  published
    property Caption: string read FCaption write FCaption;
    property Root: string read FRoot write FRoot;
    property Directory: string read FDirectory write FDirectory;
    property OnShow: TNotifyEvent read FOnShow write FOnShow;
    property OnClose: TCloseEvent read FOnClose write FOnClose;
    property OnCanClose: TCloseQueryEvent read FOnCanClose write FOnCanClose;
  end;

implementation

function TySubdirectories(const APath: string): TStringArray;
var
  sr: TSearchRec;
  list: TStringList;
  base: string;
  i: Integer;
begin
  Result := nil;
  list := TStringList.Create;
  try
    list.CaseSensitive := False;
    base := IncludeTrailingPathDelimiter(APath);
    if FindFirst(base + '*', faDirectory, sr) = 0 then
    try
      repeat
        if ((sr.Attr and faDirectory) <> 0) and (sr.Name <> '.') and (sr.Name <> '..') then
          list.Add(sr.Name);
      until FindNext(sr) <> 0;
    finally
      FindClose(sr);
    end;
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
  Result := Length(TySubdirectories(APath)) > 0;
end;

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

{ TTySelectPathForm }

constructor TTySelectPathForm.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  Resizable := True;
  Constraints.MinWidth  := 320;
  Constraints.MinHeight := 320;
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

procedure TTySelectPathForm.TreeGetText(Sender: TTyTreeView; Node: PTyTreeNode; var AText: string);
var p: string;
begin
  p := NodePath(Node);
  AText := ExtractFileName(ExcludeTrailingPathDelimiter(p));
  if AText = '' then AText := p;   // a drive root like 'C:\' collapses to '' above
end;

procedure TTySelectPathForm.TreeInitNode(Sender: TTyTreeView;
  ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates);
begin
  { show an expand arrow iff this directory actually has subdirectories }
  if TyPathHasSubdir(NodePath(Node)) then
    Include(InitStates, ivsHasChildren);
end;

procedure TTySelectPathForm.TreeGetImageIndex(Sender: TTyTreeView; Node: PTyTreeNode;
  Kind: TTyVTImageKind; Column: Integer; var Ghosted: Boolean; var ImageIndex: Integer);
begin
  { Single folder glyph for every node — every entry in this tree is a
    directory, so there is no file/folder distinction to make. }
  ImageIndex := 0;
end;

procedure TTySelectPathForm.TreeExpanding(Sender: TTyTreeView; Node: PTyTreeNode; var Allowed: Boolean);
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

procedure TTySelectPathForm.TreeFocusChanged(Sender: TTyTreeView; Node: PTyTreeNode);
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
  if (s = '') or not DirectoryExists(s) then Exit;
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
  r := ContentRect;
  x := r.Left + TyDlgPad;
  w := (r.Right - r.Left) - 2*TyDlgPad;
  editH := TyDlgEditH;
  { Path field across the top, tree fills the rest. }
  if FPathEdit <> nil then
    FPathEdit.SetBounds(x, r.Top + TyDlgPad, w, editH);
  FTree.SetBounds(x, r.Top + TyDlgPad + editH + Gap, w,
    (r.Bottom - r.Top) - 2*TyDlgPad - editH - Gap);
end;

function TTySelectPathForm.SelectedPath: string;
var s: string;
begin
  { The path field is the source of truth: it mirrors the tree selection AND holds
    any directly typed/pasted path. Prefer it when it names an existing folder (covers
    a pasted path the tree could not reveal); otherwise fall back to the tree node. }
  if FPathEdit <> nil then
  begin
    s := Trim(FPathEdit.Text);
    if (s <> '') and DirectoryExists(s) then
      Exit(s);
  end;
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
  Result.AutoSizeToContent(360, 420);
  Result.LayoutContent;
end;

function TySelectDirectory(const ACaption, ARoot: string; var ADir: string): Boolean;
var d: TTySelectPathForm;
begin
  d := TyBuildSelectPathDialog(ACaption, ARoot);
  try
    Result := (d.ShowModal = mrOK);
    if Result then ADir := d.SelectedPath;
  finally d.Free; end;
end;

{ TTySelectPathDialog }

function TTySelectPathDialog.Execute: Boolean;
var d: TTySelectPathForm;
begin
  // Inline the build/show (rather than call TySelectDirectory) so the wrapper's
  // OnShow/OnClose/OnCanClose forward onto the form before ShowModal.
  d := TyBuildSelectPathDialog(FCaption, FRoot);
  try
    TyForwardDialogEvents(d, FOnShow, FOnClose, FOnCanClose);
    Result := (d.ShowModal = mrOK);
    if Result then FDirectory := d.SelectedPath;
  finally d.Free; end;
end;

end.
