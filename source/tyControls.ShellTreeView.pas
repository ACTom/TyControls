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
  Classes, SysUtils, TypInfo, Graphics, Controls, ImgList,
  LazFileUtils,
  BGRABitmap, BGRABitmapTypes,
  tyControls.TreeView, tyControls.ImageCollection, tyControls.FileSystem;

const
  { The pixel edge of the tree's icon list. The 128px BGRA masters are rendered
    down into this; 16px matches the default Indent slot and the 22px row height. }
  TyShellTreeIconSize = 16;
  { The glyph indices in FImages, in the order BuildGlyphs adds them. }
  TyShellTreeFolderGlyph = 0;
  TyShellTreeDriveGlyph  = 1;

  { The ETyShellInvalidPath message. A DEVELOPER diagnostic (you assigned a path
    this tree cannot show), so it stays English rather than becoming a
    resourcestring: only tyControls.StrConsts is wired into the runtime's
    per-unit TranslateUnitResourceStrings call, and the i18n spec already keeps
    technical errors (the CSS-syntax family) English-only. }
  TyShellInvalidPathMsg = 'TTyShellTreeView.Directory: cannot select "%s" -- %s';

type
  { Why a path assignment did not land on its target.

    This exists because the failure used to be UNOBSERVABLE: SelectPath returned
    nothing and Directory read back the OLD path, so "the path is wrong" and "the
    path is right and this tree simply has nothing to show" produced byte-identical
    results. LCL raises a typed EInvalidPath instead (shellctrls.pas:428 declares
    it; SetRoot:625 and SetPath:1549/1561/1580/1604 raise it) -- catchable, but it
    carries only a message, so an app that wants to BRANCH on the reason has to
    parse English. The enum is the branchable half; ETyShellInvalidPath below is
    the catchable half. }
  TTyShellPathError = (
    speNone,          { the target node was reached and focused }
    speEmptyPath,     { '' or whitespace -- nothing was asked for, nothing happened }
    speNoSuchPath,    { no such directory on this machine (the typo case) }
    speNoRoot,        { it exists, but no seeded root is a prefix of it -- e.g.
                        SelectPath before PopulateRoots, or a drive TyFsRoots
                        does not enumerate }
    speUnreachable);  { a root matched but a segment was not enumerable
                        (permissions, or hidden while ShowHidden is False);
                        focus was left on the DEEPEST reachable ancestor }

  { Raised by the published Directory setter -- and only by it. A property write
    has no return channel, so silence there is unrecoverable; SelectPath, which
    does have one, reports through Boolean + LastPathError and never raises. }
  ETyShellInvalidPath = class(Exception);
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
    FLastPathError: TTyShellPathError;
    { >0 while a tree walk (SelectPath / UpdateView) is holding node pointers.
      Any refresh requested during that window is queued in FPendingRefresh and
      applied when the outermost walk unwinds -- refreshing in the middle would
      free the very nodes the walk is standing on. }
    FBusy:           Integer;
    FPendingRefresh: Boolean;
    FDraining:       Boolean;

    { Build the fixed-palette folder + drive glyphs and assign them to Images. }
    procedure BuildGlyphs;
    { node data = one Integer index into FPaths. }
    function  AddPathNode(AParent: PTyTreeNode; const AFullPath: string): PTyTreeNode;
    { Lazy child fill: enumerate NodePath(Node)'s subdirectories (folders only). }
    procedure PopulateChildren(Node: PTyTreeNode);
    procedure SetShowHidden(AValue: Boolean);
    { The published Directory setter (see ETyShellInvalidPath). }
    procedure SetDirectory(const AValue: string);
    { Apply a refresh that was queued while a walk was in progress. }
    procedure DrainPendingRefresh;
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
    { Re-enumerate the tree against the current filesystem + ShowHidden setting,
      preserving which nodes are expanded and where the focus sits.

      This is the middle ground between "do nothing" (what ShowHidden used to do)
      and PopulateRoots (which throws the whole tree away, focus included). Only
      nodes that were ALREADY expanded are re-read -- a collapsed node was never
      enumerated, so there is nothing of it to refresh; it will pick up the new
      setting when it is first expanded, exactly as before. The ROOT nodes keep
      their handles; every node below them is re-created, which is unavoidable
      (the point of a refresh is that the child set may have changed) and is why
      this is a method you call, not something that happens behind your back.

      Focus is restored by PATH, not by pointer, and degrades: if the focused
      directory is no longer visible (you just turned ShowHidden off while
      standing under a hidden ancestor) the focus lands on the deepest ancestor
      that IS still reachable, rather than being stranded on a freed node or lost.

      Called during a walk (from an OnPathChange / OnExpanding handler, say), it
      queues itself instead and runs when the walk unwinds. LCL's equivalent is
      TCustomShellTreeView.UpdateView (shellctrls.pas:1250); the name matches
      TTyShellListView.UpdateView, which already means exactly this. }
    procedure UpdateView;
    { The focused directory (cached from the last OnChange), or '' when none. }
    function  SelectedPath: string;
    { Reveal APath: expand from the containing root down to the target node and
      focus it (which caches the path + fires OnPathChange).

      Returns True only when the TARGET itself was reached; False otherwise, with
      LastPathError saying which of the four ways it went wrong. It never raises
      -- a caller with a return channel does not need an exception, and a file
      dialog resolving a path the user typed is not an exceptional event. On
      speUnreachable the focus is still moved, to the deepest reachable ancestor. }
    function  SelectPath(const APath: string): Boolean;
    { Why the last SelectPath / Directory write did not reach its target
      (speNone after a successful one). Read-only: nothing but a path assignment
      writes it. }
    property LastPathError: TTyShellPathError read FLastPathError;
  published
    { The selection as a path. Reading returns SelectedPath; writing reveals +
      focuses it.

      BREAKING (deliberate): a write that cannot reach its target now raises
      ETyShellInvalidPath instead of doing nothing. A property write has no
      return value, so the old no-op left the caller holding a Directory that
      silently still read back the PREVIOUS path -- indistinguishable from
      success. Suppressed under csLoading/csDesigning so a stale path in a .lfm
      cannot break streaming or take the IDE down with it, which is the same
      carve-out LCL makes (shellctrls.pas:621-624). Assigning '' remains a
      silent no-op: no path was asked for, so none failed.

      Use SelectPath when you would rather test a Boolean than catch. }
    property Directory: string read SelectedPath write SetDirectory;
    { Whether hidden directories are enumerated. Writing it re-enumerates the
      already-expanded nodes IMMEDIATELY (see UpdateView) -- it used to be
      flag-only, which meant the setting appeared to do nothing until some node
      happened to be re-expanded. LCL refreshes on the same kind of write
      (TCustomShellTreeView.SetObjectTypes -> UpdateView, shellctrls.pas:687). }
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

function TTyShellTreeView.SelectPath(const APath: string): Boolean;

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
  Result := False;
  FLastPathError := speEmptyPath;
  target := ExcludeTrailingPathDelimiter(Trim(APath));
  if target = '' then Exit;

  { Separate "there is no such directory" from "there is, but this tree cannot
    walk to it" BEFORE touching the tree. They need different fixes -- one is a
    typo, the other is a ShowHidden/permissions problem -- and reporting a single
    undifferentiated failure for both is barely better than the old silence. }
  { AppendPathDelim, not the bare target: ExcludeTrailingPathDelimiter turns a
    Windows drive root 'C:\' into 'C:', which names the process's CURRENT
    directory on that drive rather than its root, and probing that would reject a
    perfectly good drive. }
  if not DirectoryExistsUTF8(AppendPathDelim(target)) then
  begin
    FLastPathError := speNoSuchPath;
    Exit;
  end;

  Inc(FBusy);   { we are about to hold node pointers across expands }
  try
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
    if match = nil then
    begin
      FLastPathError := speNoRoot;
      Exit;
    end;

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

    { Landing on an ancestor is still a FAILURE to select what was asked for --
      the focus moved, so the caller is not left nowhere, but Directory would
      read back something other than what was written. Say so. }
    if SameFileName(ExcludeTrailingPathDelimiter(NodePath(node)), target) then
    begin
      FLastPathError := speNone;
      Result := True;
    end
    else
      FLastPathError := speUnreachable;
  finally
    Dec(FBusy);
    DrainPendingRefresh;
  end;
end;

procedure TTyShellTreeView.UpdateView;
var
  keep: array of string;   { paths of the nodes that were expanded, pre-order }
  focus: string;
  node: PTyTreeNode;

  { Collect the expanded paths of ANode and its siblings' subtrees. Expansion is
    remembered as a PATH, not a pointer: every one of those pointers is about to
    be freed. }
  procedure Remember(ANode: PTyTreeNode);
  var
    n: Integer;
  begin
    while ANode <> nil do
    begin
      if nsExpanded in ANode^.States then
      begin
        n := Length(keep);
        SetLength(keep, n + 1);
        keep[n] := ExcludeTrailingPathDelimiter(NodePath(ANode));
        Remember(GetFirstChild(ANode));
      end;
      ANode := GetNextSibling(ANode);
    end;
  end;

  function WasExpanded(const APath: string): Boolean;
  var
    i: Integer;
  begin
    for i := 0 to High(keep) do
      if SameFileName(keep[i], APath) then Exit(True);
    Result := False;
  end;

  { Drop a root's cached subtree so the next expand re-reads it from disk. }
  procedure ResetRoot(ANode: PTyTreeNode);
  begin
    if ANode^.ChildCount = 0 then Exit;   { never enumerated -- nothing cached }
    Expanded[ANode] := False;
    SetChildCount(ANode, 0);
    { SetChildCount(_, 0) also clears nsHasChildren, and SetExpanded bails on a
      node that does not carry it -- so re-stamp the arrow from the same cheap
      probe DoInitNode uses, or the re-expand below silently does nothing at all
      and every previously-expanded node comes back collapsed and empty. }
    if TyFsHasSubdir(NodePath(ANode)) then
      Include(ANode^.States, nsHasChildren)
    else
      Exclude(ANode^.States, nsHasChildren);
  end;

  { FPaths is append-only, so without this every refresh would leak the whole
    previous child set into it. The surviving root nodes are the only holders of
    an index now; re-seed the array from them and re-stamp their node data. }
  procedure CompactPaths;
  var
    kept: array of string;
    n: Integer;
    r: PTyTreeNode;
  begin
    SetLength(kept, 0);
    r := GetFirst;
    while r <> nil do
    begin
      n := Length(kept);
      SetLength(kept, n + 1);
      kept[n] := NodePath(r);          { read the OLD index before overwriting it }
      PInteger(GetNodeData(r))^ := n;
      r := GetNextSibling(r);
    end;
    FPaths := kept;
  end;

  { Re-expand what was expanded. Each expand runs the normal lazy path, so the
    children come back enumerated with the CURRENT ShowHidden setting. }
  procedure ReExpand(ANode: PTyTreeNode);
  begin
    while ANode <> nil do
    begin
      if WasExpanded(ExcludeTrailingPathDelimiter(NodePath(ANode))) then
      begin
        Expanded[ANode] := True;
        ReExpand(GetFirstChild(ANode));
      end;
      ANode := GetNextSibling(ANode);
    end;
  end;

begin
  if FBusy > 0 then
  begin
    { A walk is holding node pointers. Refreshing now would free them under it. }
    FPendingRefresh := True;
    Exit;
  end;

  Inc(FBusy);
  try
    focus := FSelectedPath;
    SetLength(keep, 0);
    Remember(GetFirst);

    node := GetFirst;
    while node <> nil do
    begin
      ResetRoot(node);
      node := GetNextSibling(node);
    end;
    CompactPaths;

    ReExpand(GetFirst);

    { Restore the focus by path. DeleteNode already nulled FFocusedNode when it
      freed the old node, but it does it by assigning the FIELD -- no OnChange,
      so FSelectedPath still holds the pre-refresh string. }
    if focus <> '' then
      SelectPath(focus);
    if (FocusedNode = nil) and (FSelectedPath <> '') then
    begin
      { The old directory is gone from disk entirely. Do not keep reporting it:
        SelectedPath must never name a directory the tree is not standing on. }
      FSelectedPath := '';
      if Assigned(FOnPathChange) then
        FOnPathChange(Self);
    end;
  finally
    Dec(FBusy);
    DrainPendingRefresh;
  end;
end;

procedure TTyShellTreeView.DrainPendingRefresh;
begin
  if (FBusy > 0) or FDraining then Exit;   { an outer walk still owns the tree }
  if not FPendingRefresh then Exit;
  FDraining := True;
  try
    FPendingRefresh := False;
    UpdateView;
  finally
    { FDraining bounds this to ONE deferred refresh per walk. A handler that
      re-requests a refresh from inside the refresh it caused would otherwise
      recurse without end; the re-request stays queued for the next walk. }
    FDraining := False;
  end;
end;

{ ---------------------------------------------------------------------------
  Setters
  --------------------------------------------------------------------------- }

procedure TTyShellTreeView.SetShowHidden(AValue: Boolean);
begin
  if FShowHidden = AValue then Exit;
  FShowHidden := AValue;
  { Refresh NOW. This used to set the flag and stop, on the grounds that a
    property write must not free node handles a consumer is holding, and that on
    a host whose current directory sits under a hidden ancestor a rebuild would
    strand that path. Both hazards are real and both are handled rather than
    avoided: UpdateView defers itself while a walk is in progress (FBusy), and it
    restores the focus by path, degrading to the deepest still-reachable ancestor
    instead of stranding it. What is NOT defensible is the visible result of
    doing nothing -- the setting appeared broken until some unrelated re-expand
    happened to apply it, and TTyShellListView.ShowHidden, the sibling control in
    the same family, has always re-read on the write. }
  UpdateView;
end;

procedure TTyShellTreeView.SetDirectory(const AValue: string);
begin
  if SelectPath(AValue) then Exit;
  { '' is not a failed selection, it is an absent one. }
  if FLastPathError in [speNone, speEmptyPath] then Exit;
  { Streaming a stale .lfm path, or typing one into the object inspector, must
    not break form loading or take the IDE down -- the same carve-out LCL makes
    at shellctrls.pas:621. LastPathError still records what happened, so a
    designer-time caller is not blind either. }
  if ([csLoading, csDesigning] * ComponentState) <> [] then Exit;
  raise ETyShellInvalidPath.CreateFmt(TyShellInvalidPathMsg,
    [AValue, GetEnumName(TypeInfo(TTyShellPathError), Ord(FLastPathError))]);
end;

initialization
  { So a .lfm that streams a TTyShellTreeView resolves the class. }
  RegisterClass(TTyShellTreeView);

end.
