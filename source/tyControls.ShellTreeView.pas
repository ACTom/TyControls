unit tyControls.ShellTreeView;
{$mode objfpc}{$H+}
{ TTyShellTreeView -- a file-system-backed TTyTreeView showing only FOLDERS.

  Design: docs/superpowers/specs/2026-07-11-phase7-shell-filedialogs-design.md
  Plan  : docs/superpowers/plans/2026-07-11-phase7-shelltreeview.md

  This is a LAZY directory tree. Its roots are the portable "places" from
  tyControls.FileSystem.TyFsRoots (drives on Windows; '/', home, mounted volumes
  on Unix); a node's children are enumerated on FIRST EXPAND only, via
  TyFsReadDirectory(path, '*', [fotFolders] (+ fotHidden)). Files are never shown.

  It generalises the tree wiring that tyControls.Dialogs.SelectPath's
  TTySelectPathForm hand-rolled: a node stores a single Integer index into an
  FPaths string array, OnGetText renders the leaf name (or a root's curated
  Display), OnInitNode stamps the has-children arrow via the cheap TyFsHasSubdir
  probe, OnExpanding populates children the first time, OnGetImageIndex picks a
  drive-vs-folder glyph, and OnChange caches the focused path + fires OnPathChange
  (the seam a file dialog uses to drive its file list off the tree selection).

  It reuses the tree theme tokens (GetStyleTypeKey = 'TyTreeView', inherited);
  zero new theme tokens. }

interface

uses
  Classes, SysUtils, Graphics, Controls, ImgList,
  BGRABitmap, BGRABitmapTypes,
  tyControls.TreeView, tyControls.ImageCollection, tyControls.FileSystem;

const
  { The pixel edge of the tree's icon list. The 128px BGRA masters are rendered
    down into this; 16px matches the default Indent slot and the 22px row height. }
  TyShellTreeIconSize = 16;
  { The glyph indices in FImages, in the order BuildGlyphs adds them. }
  TyShellTreeFolderGlyph = 0;
  TyShellTreeDriveGlyph  = 1;

type
  { ===================================================================
    TTyShellTreeView
    =================================================================== }
  TTyShellTreeView = class(TTyTreeView)
  private
    FPaths:        array of string;   { node-data index -> absolute path }
    FRoots:        TTyFsRootArray;    { the roots seeded by PopulateRoots (for their Display) }
    FShowHidden:   Boolean;           { toggles the fotHidden bit passed to TyFsReadDirectory }
    FIcons:        TTyImageCollection;{ owned; the 128px folder/drive BGRA masters }
    FImages:       TImageList;        { owned; the down-rendered list assigned to Images }
    FSelectedPath: string;           { the focused directory, cached from OnChange }
    FOnPathChange: TNotifyEvent;

    { Build the fixed-palette folder + drive glyphs and assign them to Images. }
    procedure BuildGlyphs;
    { node data = one Integer index into FPaths. }
    function  AddPathNode(AParent: PTyTreeNode; const AFullPath: string): PTyTreeNode;
    { Lazy child fill: enumerate NodePath(Node)'s subdirectories (folders only). }
    procedure PopulateChildren(Node: PTyTreeNode);
    procedure SetShowHidden(AValue: Boolean);
  protected
    { The shell behaviour, as OVERRIDES of the base's virtuals.

      These five used to be handlers wired to the PUBLISHED OnGetText / OnInitNode /
      OnExpanding / OnGetImageIndex / OnChange slots in the constructor, so the shell and
      the application were fighting over one slot each: assign OnGetText on a shell tree
      and it stopped showing filenames, with nothing to say why. As overrides the events
      belong to the app, which is how LCL's TShellTreeView is built. Each calls inherited,
      so an app handler runs AFTER the shell has filled its answer in and can replace it. }
    procedure DoGetText(Node: PTyTreeNode; var AText: string); override;
    procedure DoInitNode(AParent, Node: PTyTreeNode;
      var AStates: TTyNodeInitStates); override;
    procedure DoExpanding(Node: PTyTreeNode; var AAllowed: Boolean); override;
    procedure DoGetImageIndex(Node: PTyTreeNode; AKind: TTyVTImageKind; AColumn: Integer;
      var AGhosted: Boolean; var AIndex: Integer); override;
    procedure DoTreeChange(Node: PTyTreeNode); override;
    { The absolute path a node maps to (its Integer node-data indexes FPaths).
      Protected so a subclass/test can observe the node<->path mapping. }
    function  NodePath(Node: PTyTreeNode): string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;

    { Clear the tree and re-seed one node per TyFsRoots place. }
    procedure PopulateRoots;
    { The focused directory (cached from the last OnChange), or '' when none. }
    function  SelectedPath: string;
    { Reveal APath: expand from the containing root down to the target node and
      focus it (which caches the path + fires OnPathChange). Silent if no root is
      a prefix of APath or a segment is unreachable. }
    procedure SelectPath(const APath: string);
  published
    { The selection as a path. Reading returns SelectedPath; writing reveals +
      focuses it (SelectPath). }
    property Directory: string read SelectedPath write SelectPath;
    { Whether hidden directories are enumerated. Flag-only: the new value takes
      effect on the next (re-)expand; call PopulateRoots for an immediate refresh. }
    property ShowHidden: Boolean read FShowHidden write SetShowHidden default False;
    { Fires whenever the focused directory changes (SelectedPath is the new path). }
    property OnPathChange: TNotifyEvent read FOnPathChange write FOnPathChange;
  end;

implementation

{ ---------------------------------------------------------------------------
  Lifecycle
  --------------------------------------------------------------------------- }

constructor TTyShellTreeView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FShowHidden := False;
  SetLength(FPaths, 0);

  { node data = one Integer index into FPaths; no managed types in raw node memory. }
  NodeDataSize    := SizeOf(Integer);
  { No published event slot is claimed here any more -- the shell behaviour is in the
    DoXxx overrides, leaving all five events to the application. }

  { A 16px glyph needs a little more than the default 18px row; HotTrack + the
    (already-default) ShowRoot give root nodes their own expand triangle. }
  DefaultNodeHeight := 22;
  HotTrack          := True;

  BuildGlyphs;
  PopulateRoots;
end;

destructor TTyShellTreeView.Destroy;
begin
  { FImages/FIcons are created ownerless (see BuildGlyphs). Free FImages first --
    its FreeNotification nils the inherited Images reference before we drop it. }
  FImages.Free;
  FIcons.Free;
  inherited Destroy;
end;

{ Build a folder glyph + a drive glyph as 128px BGRA masters in a private
  TTyImageCollection, render them down into a plain LCL TImageList, and assign
  that list to the inherited Images.

  WHY TWO OBJECTS: the tree paints its icons from a plain TImageList (Images:
  TImageList, drawn via TImageList.Draw); a TTyVirtualImageList is a TComponent,
  not a TImageList, so -- unlike TTyShellListView, whose base takes a virtual
  list -- it cannot be assigned to Images without editing tyControls.TreeView
  (forbidden). We therefore author the masters in a TTyImageCollection (the 128px
  BGRA + fixed-palette contract) and bridge each into the TImageList.

  THEME EXEMPTION (deliberate, documented, consistent with TTyShellListView):
  these glyphs use a FIXED tasteful palette, not theme tokens. They are CONTENT
  (a folder vs. a drive), not control chrome, and the constructor runs before the
  Controller/theme is resolved. An app that wants themed icons can assign its own
  Images. }
procedure TTyShellTreeView.BuildGlyphs;
const
  G = 128;   { master edge, px }

  function Shade(const C: TBGRAPixel; AFactor: Single): TBGRAPixel;
  begin
    Result := BGRA(Round(C.red * AFactor), Round(C.green * AFactor),
                   Round(C.blue * AFactor), C.alpha);
  end;

  { A manila folder: back tab + body + a soft top lip. }
  procedure AddFolder(const AName: string; ABody: TBGRAPixel);
  var
    bmp: TBGRABitmap;
  begin
    bmp := TBGRABitmap.Create(G, G, BGRAPixelTransparent);
    try
      bmp.FillRoundRectAntialias(8, 20, 60, 46, 6, 6, Shade(ABody, 0.82));   { tab }
      bmp.FillRoundRectAntialias(8, 34, 120, 112, 8, 8, ABody);             { body }
      bmp.FillRectAntialias(8, 34, 120, 42, BGRA(255, 255, 255, 40));       { top lip }
      FIcons.AddBitmap(AName, bmp);
    finally
      bmp.Free;
    end;
  end;

  { An external-drive chassis: rounded box + a highlight band, a media slot and a
    small green activity LED. }
  procedure AddDrive(const AName: string; ABody: TBGRAPixel);
  var
    bmp: TBGRABitmap;
  begin
    bmp := TBGRABitmap.Create(G, G, BGRAPixelTransparent);
    try
      bmp.FillRoundRectAntialias(14, 40, 114, 100, 10, 10, ABody);            { chassis }
      bmp.FillRectAntialias(14, 40, 114, 66, BGRA(255, 255, 255, 30));        { top band }
      bmp.FillRoundRectAntialias(26, 78, 90, 86, 3, 3, Shade(ABody, 0.45));   { media slot }
      bmp.FillEllipseAntialias(100, 82, 5, 5, BGRA(120, 220, 140, 255));      { activity LED }
      FIcons.AddBitmap(AName, bmp);
    finally
      bmp.Free;
    end;
  end;

  { Render master AName down to the icon size and push it into the LCL list. The
    BGRA master carries an alpha channel, transferred through TBGRABitmap.Bitmap
    into the (ILC_COLOR32) image list. }
  procedure PushGlyph(const AName: string);
  var
    scaled: TBGRABitmap;
  begin
    scaled := FIcons.GetBitmap(AName, TyShellTreeIconSize);   { caller-owned copy }
    try
      FImages.Add(scaled.Bitmap, nil);
    finally
      scaled.Free;
    end;
  end;

begin
  FIcons := TTyImageCollection.Create(nil);
  { Order MUST match the TyShellTree*Glyph constants: folder (0), drive (1). }
  AddFolder('folder', BGRA(226, 176, 66));    { warm amber }
  AddDrive('drive',   BGRA(96, 116, 150));    { steel blue }

  FImages := TImageList.Create(nil);
  FImages.Width  := TyShellTreeIconSize;
  FImages.Height := TyShellTreeIconSize;
  PushGlyph('folder');
  PushGlyph('drive');

  Images := FImages;
end;

{ ---------------------------------------------------------------------------
  Node <-> path mapping
  --------------------------------------------------------------------------- }

function TTyShellTreeView.AddPathNode(AParent: PTyTreeNode; const AFullPath: string): PTyTreeNode;
var
  idx: Integer;
begin
  Result := AddChild(AParent);
  idx := Length(FPaths);
  SetLength(FPaths, idx + 1);
  FPaths[idx] := AFullPath;
  PInteger(GetNodeData(Result))^ := idx;
  { Materialise now (headless: no paint loop to lazy-init it) so the has-children
    arrow is stamped via OnInitNode from TyFsHasSubdir. }
  InitNode(Result);
end;

function TTyShellTreeView.NodePath(Node: PTyTreeNode): string;
var
  p: Pointer;
  idx: Integer;
begin
  Result := '';
  if Node = nil then Exit;
  p := GetNodeData(Node);
  if p = nil then Exit;
  idx := PInteger(p)^;
  if (idx >= 0) and (idx <= High(FPaths)) then
    Result := FPaths[idx];
end;

procedure TTyShellTreeView.PopulateChildren(Node: PTyTreeNode);
var
  entries: TTyFsEntryArray;
  opts: TTyFsObjectTypes;
  i: Integer;
begin
  opts := [fotFolders];
  if FShowHidden then
    Include(opts, fotHidden);
  { Folders only -- TyFsReadDirectory drops files, and the mask applies to files
    only, so '*' never affects the directory list. }
  entries := TyFsReadDirectory(NodePath(Node), '*', opts);
  for i := 0 to High(entries) do
    AddPathNode(Node, entries[i].FullPath);
end;

{ ---------------------------------------------------------------------------
  Tree event handlers
  --------------------------------------------------------------------------- }

procedure TTyShellTreeView.DoGetText(Node: PTyTreeNode; var AText: string);
var
  p: string;
  i: Integer;
begin
  p := NodePath(Node);
  { A root node renders its curated Display ('C:', '/', a volume/home name)
    rather than the bare path. }
  AText := '';
  for i := 0 to High(FRoots) do
    if SameFileName(FRoots[i].Path, p) then
    begin
      AText := FRoots[i].Display;
      Break;
    end;
  if AText = '' then
  begin
    AText := ExtractFileName(ExcludeTrailingPathDelimiter(p));
    if AText = '' then
      AText := p;   { defensive: a rooted path that collapses to '' }
  end;
  { inherited unconditionally. The root branch used to Exit here, so on exactly the nodes
    a shell tree shows FIRST -- the drives and places -- an application's OnGetText was
    never reached. Half a fix reads worse than none: the event works on some rows and not
    others, which is harder to diagnose than not working at all. }
  inherited DoGetText(Node, AText);
end;

procedure TTyShellTreeView.DoInitNode(AParent, Node: PTyTreeNode;
  var AStates: TTyNodeInitStates);
begin
  { Show an expand arrow iff this directory has at least one subdirectory. The
    probe stops at the first hit -- it never enumerates the children (that waits
    for the first expand). }
  if TyFsHasSubdir(NodePath(Node)) then
    Include(AStates, ivsHasChildren);
  { inherited LAST so an application handler sees -- and may change -- what the shell
    decided, rather than being overwritten by it. }
  inherited DoInitNode(AParent, Node, AStates);
end;

procedure TTyShellTreeView.DoExpanding(Node: PTyTreeNode; var AAllowed: Boolean);
begin
  AAllowed := True;
  { Lazy population: enumerate subdirs on the first expand only. AddChild bumps
    ChildCount, so the base's InitChildren no-ops (its ChildCount>0 guard). }
  if Node^.ChildCount = 0 then
    PopulateChildren(Node);
  inherited DoExpanding(Node, AAllowed);   { an app handler may still veto }
end;

procedure TTyShellTreeView.DoGetImageIndex(Node: PTyTreeNode; AKind: TTyVTImageKind;
  AColumn: Integer; var AGhosted: Boolean; var AIndex: Integer);
begin
  { Top-level nodes are the TyFsRoots "places" -> drive glyph; everything below
    is a folder. (Kind is ignored: the same glyph serves normal/selected.) }
  if (Node <> nil) and (Node^.Parent = RootNode) then
    AIndex := TyShellTreeDriveGlyph
  else
    AIndex := TyShellTreeFolderGlyph;
  inherited DoGetImageIndex(Node, AKind, AColumn, AGhosted, AIndex);
end;

procedure TTyShellTreeView.DoTreeChange(Node: PTyTreeNode);
begin
  { OnChange fires on every focus/selection move (mouse, keyboard, or a
    programmatic FocusedNode from SelectPath). Cache the path + notify. }
  FSelectedPath := NodePath(Node);
  if Assigned(FOnPathChange) then
    FOnPathChange(Self);
  inherited DoTreeChange(Node);            { OnChange belongs to the app now }
end;

{ ---------------------------------------------------------------------------
  Public API
  --------------------------------------------------------------------------- }

procedure TTyShellTreeView.PopulateRoots;
var
  i: Integer;
begin
  Clear;
  SetLength(FPaths, 0);
  FRoots := TyFsRoots;
  for i := 0 to High(FRoots) do
    AddPathNode(nil, FRoots[i].Path);
end;

function TTyShellTreeView.SelectedPath: string;
begin
  Result := FSelectedPath;
end;

procedure TTyShellTreeView.SelectPath(const APath: string);

  { True when ABase is ADir itself or a parent directory of it (case-insensitive,
    component-aware so 'C:\Us' is not a prefix of 'C:\Users'). }
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
  target := ExcludeTrailingPathDelimiter(Trim(APath));
  if target = '' then Exit;

  { Find the root node that contains the target. }
  match := nil;
  node := GetFirst;
  while node <> nil do
  begin
    if IsSelfOrAncestor(ExcludeTrailingPathDelimiter(NodePath(node)), target) then
    begin
      match := node;
      Break;
    end;
    node := GetNextSibling(node);
  end;
  if match = nil then Exit;   { no root is a prefix -- silent }

  { Descend segment by segment: expand (lazily populates children) then pick the
    child that still contains the target. Stop at the target or deepest reachable. }
  node := match;
  while not SameFileName(ExcludeTrailingPathDelimiter(NodePath(node)), target) do
  begin
    Expanded[node] := True;
    match := nil;
    child := GetFirstChild(node);
    while child <> nil do
    begin
      cur := ExcludeTrailingPathDelimiter(NodePath(child));
      if IsSelfOrAncestor(cur, target) then
      begin
        match := child;
        Break;
      end;
      child := GetNextSibling(child);
    end;
    if match = nil then Break;   { a segment is missing (permissions / case) }
    node := match;
  end;

  FocusedNode := node;    { fires OnChange -> TreeChange caches path + OnPathChange }
  ScrollIntoView(node);   { FocusedNode does not scroll on its own }
end;

{ ---------------------------------------------------------------------------
  Setters
  --------------------------------------------------------------------------- }

procedure TTyShellTreeView.SetShowHidden(AValue: Boolean);
begin
  if FShowHidden = AValue then Exit;
  FShowHidden := AValue;
  { Flag-only, deliberately: the new setting takes effect the next time a node is
    (re-)expanded and PopulateChildren enumerates. We do NOT rebuild the tree here
    -- a property write must never free node handles a consumer (or a lazy re-walk
    like SelectPath) is holding, and on a host whose only writable tree sits under
    a hidden ancestor, a rebuild-on-toggle would also strand the current path.
    A consumer that wants an immediate visible refresh calls PopulateRoots. }
end;

initialization
  { So a .lfm that streams a TTyShellTreeView resolves the class. }
  RegisterClass(TTyShellTreeView);

end.
