unit tyControls.Dialogs.SelectPath;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Dialogs, Forms,
  tyControls.Dialogs, tyControls.TreeView, tyControls.Button, tyControls.StrConsts;

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
    FPaths: TStringList;   // node-data index -> absolute path (owned; freed in dtor)
    FRoot:  string;        // '' = all drive roots, else a single rooted subtree
    // Node-data helpers (node data = an Integer index into FPaths).
    function  AddPathNode(AParent: PTyTreeNode; const AFullPath: string): PTyTreeNode;
    function  NodePath(Node: PTyTreeNode): string;
    procedure PopulateChildren(Node: PTyTreeNode);
    // Tree event handlers.
    procedure TreeGetText(Sender: TTyTreeView; Node: PTyTreeNode; var AText: string);
    procedure TreeInitNode(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
      var InitStates: TTyNodeInitStates);
    procedure TreeExpanding(Sender: TTyTreeView; Node: PTyTreeNode; var Allowed: Boolean);
    procedure NewFolderClick(Sender: TObject);
  protected
    procedure LayoutContent; override;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    destructor  Destroy; override;
    // Add one root node per configured source (a single FRoot, else every drive).
    procedure PopulateRoots;
    function  SelectedPath: string;
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
  public
    function Execute: Boolean;
  published
    property Caption: string read FCaption write FCaption;
    property Root: string read FRoot write FRoot;
    property Directory: string read FDirectory write FDirectory;
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
  FTree := TTyTreeView.Create(Self);
  FTree.Parent := Self;
  { node data = one Integer index into FPaths; no managed types in raw node memory }
  FTree.NodeDataSize   := SizeOf(Integer);
  FTree.OnGetText      := @TreeGetText;
  FTree.OnInitNode     := @TreeInitNode;
  FTree.OnExpanding    := @TreeExpanding;
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

procedure TTySelectPathForm.TreeExpanding(Sender: TTyTreeView; Node: PTyTreeNode; var Allowed: Boolean);
begin
  Allowed := True;
  { lazy population: enumerate subdirs on first expand only. AddChild bumps
    ChildCount, so the base SetExpanded's InitChildren call no-ops (its
    ChildCount>0 guard) — the two materialisation models never collide. }
  if Node^.ChildCount = 0 then
    PopulateChildren(Node);
end;

procedure TTySelectPathForm.NewFolderClick(Sender: TObject);
var parentNode: PTyTreeNode; nm, full: string;
begin
  parentNode := FTree.FocusedNode;
  if parentNode = nil then Exit;
  nm := '';
  if not TyInputQuery(rsDlgNewFolder, rsDlgNewFolderPrompt, nm) then Exit;
  if nm = '' then Exit;
  full := IncludeTrailingPathDelimiter(NodePath(parentNode)) + nm;
  if CreateDir(full) then
  begin
    { re-expand the parent so the new folder appears. Clear its children so the
      next expand re-enumerates the directory (now including the new folder). }
    FTree.Expanded[parentNode] := False;
    FTree.SetChildCount(parentNode, 0);
    FTree.InitNode(parentNode);          // re-stamp has-children (it certainly does now)
    FTree.Expanded[parentNode] := True;
  end
  else
    TyMessageDlg(Format(rsDlgCreateFolderErr, [full]), mtError, [mbOK]);
end;

procedure TTySelectPathForm.LayoutContent;
var r: TRect;
begin
  if FTree = nil then Exit;
  r := ContentRect;
  FTree.SetBounds(r.Left + 16, r.Top + 16,
    (r.Right - r.Left) - 2*16, (r.Bottom - r.Top) - 2*16);
end;

function TTySelectPathForm.SelectedPath: string;
begin
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
  Result.Caption := ACaption;
  Result.Root := ARoot;
  Result.PopulateRoots;
  { New Folder (left of OK/Cancel) is an mrNone action button — it must NOT close
    the dialog; wire its click to create a folder under the focused node. }
  btn := Result.AddButton(rsDlgNewFolder, mrNone);
  btn.OnClick := @Result.NewFolderClick;
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
begin
  Result := TySelectDirectory(FCaption, FRoot, FDirectory);
end;

end.
