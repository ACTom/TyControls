unit test.shelltreeview;
{ Phase 7 batch 3 — headless state-machine tests for TTyShellTreeView.

  Written FROM THE PLAN/SPEC CONTRACT ONLY
  (docs/superpowers/plans/2026-07-11-phase7-shelltreeview.md +
   docs/superpowers/specs/2026-07-11-phase7-shell-filedialogs-design.md). The
  implementation (source/tyControls.ShellTreeView.pas) is being written
  independently by another agent and is deliberately NOT consulted here, so
  nothing in this file can ratify an implementation bug.

  No windowing: the control is Create(nil), never parented, never painted, never
  given a Handle. The lazy directory tree runs its whole state machine (seed roots
  / lazy-expand / path->node mapping / focus) headless — the same way the
  TTySelectPathForm template does.

  The protected NodePath seam is reached through a TTyShellTreeViewAccess
  subclass declared in this unit — a descendant declared here can read its
  ancestor's protected members across units, which is exactly the mechanism the
  plan prescribes. Node walking (GetFirst / GetFirstChild / GetNextSibling /
  Expanded / SetChildCount / FocusedNode / Selected) is done through the PUBLIC
  TTyTreeView surface the control inherits.

  Every filesystem touch goes through the LazFileUtils *UTF8 wrappers so the tree
  behaves the same on every platform.

  A note on reachability (a genuine contract looseness, see the return summary):
  GetTempDir on Windows sits under a HIDDEN ancestor (…\AppData\…). SelectPath
  navigates the visible tree (like the template's RevealPath), so with
  ShowHidden=False that hidden ancestor is never enumerated and the temp subtree
  cannot be reached. Every test that must navigate to the temp root therefore sets
  ShowHidden:=True first. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Types, Graphics,
  LazFileUtils, FileUtil,
  fpcunit, testregistry,
  tyControls.FileSystem,   { TyFsHasSubdir, TyFsRoots, TTyFsRootArray, kinds }
  tyControls.TreeView,     { PTyTreeNode, TTyNodeState, nsHasChildren }
  tyControls.ShellTreeView;{ the unit under test }

type
  { Re-exposes the protected NodePath seam. A descendant declared here can read
    its ancestor's protected members even across units, which is precisely why
    the contract routes the tests through this subclass. }
  TTyShellTreeViewAccess = class(TTyShellTreeView)
  public
    { node -> the absolute directory path it maps to (the protected NodePath). }
    function XNodePath(ANode: PTyTreeNode): string;
  end;

  { One controlled temp tree per test, a fresh control per test.

    Tree built in SetUp (under a process-unique dir name — a fixed name would let
    a crashed prior run leave stale state, as batch 2 learned):

      <root>/
        a/              (dir, has subdirs -> TyFsHasSubdir True)
          b/            (empty leaf dir)
          c/            (empty leaf dir)
        d/              (empty leaf dir -> TyFsHasSubdir False)
        files_only/     (dir with only a FILE inside -> TyFsHasSubdir False)
          only.txt
        hsub/           (HIDDEN dir -> ShowHidden toggles its visibility)
        f1.txt          (file, must be filtered out of the folders-only tree)
        f2.dat          (file, must be filtered out of the folders-only tree) }
  TShellTreeViewTest = class(TTestCase)
  private
    FRoot:  string;   { enumerated directory, no trailing delimiter }
    FDirA:  string;   { <root>/a  — has subdirs }
    FDirD:  string;   { <root>/d  — empty leaf }
    FFilesOnly: string;{ <root>/files_only — only a file inside }
    FHidden: string;  { <root>/hsub — hidden dir }
    FFile1: string;   { <root>/f1.txt }
    FFile2: string;   { <root>/f2.dat }
    FTree:  TTyShellTreeViewAccess;
    { OnPathChange observation }
    FPathChangeCount: Integer;
    FPathChangeSeen:  string;
    procedure WriteByteFile(const AFullName: string);
    procedure HandlePathChange(Sender: TObject);
    { Reach the temp root node via SelectPath (needs ShowHidden=True, see header).
      Asserts it was reached; returns the focused node. }
    function ReachTempRoot: PTyTreeNode;
    { True when ANode has an immediate child whose basename = ABaseName. }
    function ChildHasBaseName(ANode: PTyTreeNode; const ABaseName: string): Boolean;
    { Count of ANode's immediate children. }
    function ChildCountOf(ANode: PTyTreeNode): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { PopulateRoots seeds one node per TyFsRoots, and the roots include the kind
      expected for this OS (a drive on Windows; '/' on Unix). }
    procedure TestPopulateRootsSeedsRootsWithExpectedKind;
    { SelectPath(temp root) sets SelectedPath to that path; Directory reads it back. }
    procedure TestSelectPathSetsSelectedPathAndDirectoryReadsBack;
    { Expanding a directory node yields children that are ALL directories and NONE
      of the files created in that directory. }
    procedure TestExpandingDirYieldsOnlyDirectoriesNoFiles;
    { LAZY: a freshly-populated-roots node has 0 children until expanded; after
      expand it has > 0 (for a root that has subdirs). }
    procedure TestLazyRootHasNoChildrenUntilExpanded;
    { TyFsHasSubdir: a dir with a subdir is True; a leaf dir (and a dir with only
      files) is False; a non-existent path is False. }
    procedure TestHasSubdirTrueForParentFalseForLeafAndMissing;
    { ShowHidden toggles whether a hidden subdirectory appears among a node's
      children. }
    procedure TestShowHiddenTogglesHiddenSubdirInChildren;
    { OnPathChange fires when the focused directory changes, and SelectedPath is
      the new path. }
    procedure TestOnPathChangeFiresOnDirectoryChangeWithNewPath;
    { This tree owns its data, so the base's item collection is refused OUT LOUD
      rather than half-working. Without the refusal the item layer would rebuild
      the tree and PopulateRoots would then raise from AddChild -- loud, but
      naming the wrong cause. The message must be about the shell tree, not about
      a node insertion. }
    procedure TestItemsAreRefusedBecauseThisTreeOwnsItsData;
  end;

implementation

const
  DIR_NAME = 'tyshell_test_';

{ Normalised path equality: trailing-delimiter- and case-insensitive (on Windows).
  ExcludeTrailingPathDelimiter collapses 'C:\' -> 'C:' and '/' -> '' consistently
  on both sides, then SameFileName applies the OS case rule. }
function SamePath(const A, B: string): Boolean;
begin
  Result := SameFileName(ExcludeTrailingPathDelimiter(A),
                         ExcludeTrailingPathDelimiter(B))
            or SameFileName(A, B);
end;

{ The display basename of a directory path (the last component). }
function BaseNameOf(const APath: string): string;
begin
  Result := ExtractFileName(ExcludeTrailingPathDelimiter(APath));
end;

{ ===========================================================================
  TTyShellTreeViewAccess
  =========================================================================== }

function TTyShellTreeViewAccess.XNodePath(ANode: PTyTreeNode): string;
begin
  Result := NodePath(ANode);
end;

{ ===========================================================================
  TShellTreeViewTest — fixture
  =========================================================================== }

procedure TShellTreeViewTest.WriteByteFile(const AFullName: string);
var
  h: THandle;
  b: Byte;
begin
  h := FileCreateUTF8(AFullName);
  try
    b := Ord('x');
    FileWrite(h, b, 1);
  finally
    FileClose(h);
  end;
end;

procedure TShellTreeViewTest.SetUp;
begin
  FPathChangeCount := 0;
  FPathChangeSeen  := '';

  FRoot := ChompPathDelim(AppendPathDelim(GetTempDir) + DIR_NAME + IntToStr(GetProcessID));
  if DirectoryExistsUTF8(FRoot) then
    DeleteDirectory(FRoot, False);
  ForceDirectoriesUTF8(FRoot);

  FDirA := AppendPathDelim(FRoot) + 'a';
  FDirD := AppendPathDelim(FRoot) + 'd';
  FFilesOnly := AppendPathDelim(FRoot) + 'files_only';
  FHidden := AppendPathDelim(FRoot) + 'hsub';
  FFile1 := AppendPathDelim(FRoot) + 'f1.txt';
  FFile2 := AppendPathDelim(FRoot) + 'f2.dat';

  ForceDirectoriesUTF8(FDirA);
  ForceDirectoriesUTF8(AppendPathDelim(FDirA) + 'b');   { empty leaf }
  ForceDirectoriesUTF8(AppendPathDelim(FDirA) + 'c');   { empty leaf }
  ForceDirectoriesUTF8(FDirD);                          { empty leaf }
  ForceDirectoriesUTF8(FFilesOnly);
  WriteByteFile(AppendPathDelim(FFilesOnly) + 'only.txt');  { a file, but no subdir }

  { hidden subdir: leading dot hides on Unix; also flag faHidden on Windows }
  ForceDirectoriesUTF8(FHidden);
  {$IFDEF MSWINDOWS}
  FileSetAttrUTF8(FHidden, faHidden);
  {$ENDIF}

  { two files directly in the root — must never appear in the folders-only tree }
  WriteByteFile(FFile1);
  WriteByteFile(FFile2);

  FTree := TTyShellTreeViewAccess.Create(nil);
end;

procedure TShellTreeViewTest.TearDown;
begin
  FreeAndNil(FTree);
  if (FRoot <> '') and DirectoryExistsUTF8(FRoot) then
    DeleteDirectory(FRoot, False);
end;

procedure TShellTreeViewTest.HandlePathChange(Sender: TObject);
begin
  Inc(FPathChangeCount);
  FPathChangeSeen := FTree.SelectedPath;
end;

function TShellTreeViewTest.ReachTempRoot: PTyTreeNode;
begin
  { ShowHidden must be on so SelectPath can descend through a hidden ancestor
    (…\AppData\… on Windows); on Unix (/tmp) it is harmless. }
  FTree.ShowHidden := True;
  FTree.PopulateRoots;
  FTree.SelectPath(FRoot);
  Result := FTree.FocusedNode;
  AssertTrue('SelectPath reached the temp root (a node is focused)', Result <> nil);
  AssertTrue('focused node path = temp root',
    SamePath(FTree.XNodePath(Result), FRoot));
end;

function TShellTreeViewTest.ChildHasBaseName(ANode: PTyTreeNode;
  const ABaseName: string): Boolean;
var
  ch: PTyTreeNode;
begin
  Result := False;
  if ANode = nil then Exit;
  ch := FTree.GetFirstChild(ANode);
  while ch <> nil do
  begin
    if SameFileName(BaseNameOf(FTree.XNodePath(ch)), ABaseName) then
      Exit(True);
    ch := FTree.GetNextSibling(ch);
  end;
end;

function TShellTreeViewTest.ChildCountOf(ANode: PTyTreeNode): Integer;
var
  ch: PTyTreeNode;
begin
  Result := 0;
  if ANode = nil then Exit;
  ch := FTree.GetFirstChild(ANode);
  while ch <> nil do
  begin
    Inc(Result);
    ch := FTree.GetNextSibling(ch);
  end;
end;

{ ===========================================================================
  Tests
  =========================================================================== }

procedure TShellTreeViewTest.TestPopulateRootsSeedsRootsWithExpectedKind;
var
  roots: TTyFsRootArray;
  node: PTyTreeNode;
  i, rootNodeCount: Integer;
  found: Boolean;
  {$IFDEF MSWINDOWS}
  anyDrive: Boolean;
  {$ELSE}
  hasUnixRoot: Boolean;
  {$ENDIF}
begin
  FTree.PopulateRoots;

  { at least one root node exists }
  node := FTree.GetFirst;
  AssertTrue('PopulateRoots produced at least one root node', node <> nil);

  { one node per TyFsRoots entry (the plan: 'one root node per TyFsRoots entry') }
  rootNodeCount := 0;
  node := FTree.GetFirst;
  while node <> nil do
  begin
    Inc(rootNodeCount);
    node := FTree.GetNextSibling(node);
  end;
  roots := TyFsRoots;
  AssertEquals('one root node per TyFsRoots entry', Length(roots), rootNodeCount);

  { every TyFsRoots path appears as some root node's path }
  for i := 0 to High(roots) do
  begin
    found := False;
    node := FTree.GetFirst;
    while node <> nil do
    begin
      if SamePath(FTree.XNodePath(node), roots[i].Path) then
      begin found := True; Break; end;
      node := FTree.GetNextSibling(node);
    end;
    AssertTrue('root ' + roots[i].Path + ' is present as a tree node', found);
  end;

  { OS-expected kind is present among the roots }
  {$IFDEF MSWINDOWS}
  anyDrive := False;
  {$ELSE}
  hasUnixRoot := False;
  {$ENDIF}
  node := FTree.GetFirst;
  while node <> nil do
  begin
    {$IFDEF MSWINDOWS}
    { a drive root: 'X:\...' — second char is the drive delimiter, and it exists }
    if (Length(FTree.XNodePath(node)) >= 2)
       and (FTree.XNodePath(node)[2] = DriveDelim)
       and DirectoryExistsUTF8(FTree.XNodePath(node)) then
      anyDrive := True;
    {$ELSE}
    if SamePath(FTree.XNodePath(node), '/') then
      hasUnixRoot := True;
    {$ENDIF}
    node := FTree.GetNextSibling(node);
  end;
  {$IFDEF MSWINDOWS}
  AssertTrue('a drive root is present on Windows', anyDrive);
  {$ELSE}
  AssertTrue('the filesystem root ''/'' is present on Unix', hasUnixRoot);
  {$ENDIF}
end;

procedure TShellTreeViewTest.TestSelectPathSetsSelectedPathAndDirectoryReadsBack;
begin
  ReachTempRoot;   { asserts the node was reached }
  AssertTrue('SelectedPath = the selected path', SamePath(FTree.SelectedPath, FRoot));
  AssertTrue('Directory reads SelectedPath back', SamePath(FTree.Directory, FRoot));
end;

procedure TShellTreeViewTest.TestExpandingDirYieldsOnlyDirectoriesNoFiles;
var
  node, ch: PTyTreeNode;
  p: string;
begin
  node := ReachTempRoot;
  FTree.Expanded[node] := True;   { lazy population happens here }

  AssertTrue('the root has children after expand', ChildCountOf(node) > 0);

  { every child is a real directory, and none is one of the files we created }
  ch := FTree.GetFirstChild(node);
  while ch <> nil do
  begin
    p := FTree.XNodePath(ch);
    AssertTrue('child is a directory: ' + p, DirectoryExistsUTF8(p));
    AssertTrue('child is not file f1.txt', not SamePath(p, FFile1));
    AssertTrue('child is not file f2.dat', not SamePath(p, FFile2));
    ch := FTree.GetNextSibling(ch);
  end;

  { the real subdirectories ARE present (the folders were not dropped) }
  AssertTrue('subdir a present', ChildHasBaseName(node, 'a'));
  AssertTrue('subdir d present', ChildHasBaseName(node, 'd'));
  AssertTrue('subdir files_only present', ChildHasBaseName(node, 'files_only'));
  { and the files are NOT present by basename }
  AssertTrue('file f1.txt not among children', not ChildHasBaseName(node, 'f1.txt'));
  AssertTrue('file f2.dat not among children', not ChildHasBaseName(node, 'f2.dat'));
end;

procedure TShellTreeViewTest.TestLazyRootHasNoChildrenUntilExpanded;
var
  node, pick: PTyTreeNode;
begin
  FTree.PopulateRoots;

  { pick a freshly-seeded root node that actually has subdirectories (a drive on
    Windows / '/' on Unix) — the lazy contract is about "expand triggers the first
    enumeration", so we need a node whose expansion yields children. }
  pick := nil;
  node := FTree.GetFirst;
  while node <> nil do
  begin
    if TyFsHasSubdir(FTree.XNodePath(node)) then
    begin pick := node; Break; end;
    node := FTree.GetNextSibling(node);
  end;
  AssertTrue('a root with at least one subdirectory exists', pick <> nil);

  { LAZY: not enumerated until first expand }
  AssertEquals('root has 0 children before expand', 0, ChildCountOf(pick));

  FTree.Expanded[pick] := True;
  AssertTrue('root has > 0 children after expand', ChildCountOf(pick) > 0);
end;

procedure TShellTreeViewTest.TestHasSubdirTrueForParentFalseForLeafAndMissing;
begin
  { a directory that contains a subdirectory }
  AssertTrue('dir with a subdir -> True', TyFsHasSubdir(FDirA));
  { an empty leaf directory }
  AssertTrue('empty leaf dir -> False', not TyFsHasSubdir(FDirD));
  { a directory that holds only a FILE (no subdirectory) }
  AssertTrue('dir with only a file -> False', not TyFsHasSubdir(FFilesOnly));
  { a path that does not exist }
  AssertTrue('non-existent path -> False',
    not TyFsHasSubdir(AppendPathDelim(FRoot) + 'does_not_exist_xyz'));
end;

procedure TShellTreeViewTest.TestShowHiddenTogglesHiddenSubdirInChildren;
var
  node: PTyTreeNode;
begin
  { --- ShowHidden ON: the hidden subdir appears among the children --- }
  node := ReachTempRoot;                { ReachTempRoot already sets ShowHidden:=True }
  FTree.Expanded[node] := True;
  AssertTrue('hidden subdir hsub present with ShowHidden on',
    ChildHasBaseName(node, 'hsub'));
  { sanity: a normal subdir is present too }
  AssertTrue('normal subdir a present with ShowHidden on',
    ChildHasBaseName(node, 'a'));

  { --- ShowHidden OFF --- }
  { This used to be followed by a hand-rolled collapse / SetChildCount(0) /
    re-stamp nsHasChildren / re-expand dance, because the property write itself
    did NOTHING and the test had to force the re-enumeration by hand. The write
    now refreshes (see TTyShellTreeView.UpdateView), so the dance is gone -- and
    it would be a use-after-free if it stayed: a refresh re-creates every node
    below the roots, so `node` is dangling the instant this line returns. }
  FTree.ShowHidden := False;

  { Re-walk instead of reusing the pointer. On Windows GetTempDir sits under
    ...\AppData\..., which is itself hidden, so with the flag off the fixture's
    own ANCESTOR is filtered out and the walk stops short of it -- the same rule
    applied one level up, and now a reportable one rather than silence. }
  if FTree.SelectPath(FRoot) then
  begin
    node := FTree.FocusedNode;
    FTree.Expanded[node] := True;
    AssertTrue('hidden subdir hsub absent with ShowHidden off',
      not ChildHasBaseName(node, 'hsub'));
    AssertTrue('normal subdir a still present with ShowHidden off',
      ChildHasBaseName(node, 'a'));
  end
  else
    AssertEquals('the fixture is under a hidden ancestor, so it is filtered too',
      Ord(speUnreachable), Ord(FTree.LastPathError));
end;

procedure TShellTreeViewTest.TestOnPathChangeFiresOnDirectoryChangeWithNewPath;
var
  node, child: PTyTreeNode;
  childPath: string;
begin
  node := ReachTempRoot;
  FTree.Expanded[node] := True;

  child := FTree.GetFirstChild(node);
  AssertTrue('the root has a child directory', child <> nil);
  childPath := FTree.XNodePath(child);
  AssertTrue('the child is a directory', DirectoryExistsUTF8(childPath));

  { observe from a clean slate — ignore any path changes during setup/navigation }
  FTree.OnPathChange := @HandlePathChange;
  FPathChangeCount := 0;
  FPathChangeSeen  := '';

  { change the focused directory to the child. Drive both the focus-change and the
    selection-change paths so the test does not depend on which of the two the
    implementation routes OnPathChange through. }
  FTree.FocusedNode := child;
  FTree.NodeSelected[child] := True;

  AssertTrue('OnPathChange fired on the directory change', FPathChangeCount > 0);
  AssertTrue('SelectedPath is the new (child) path',
    SamePath(FTree.SelectedPath, childPath));
  AssertTrue('SelectedPath seen at fire time is the new path',
    SamePath(FPathChangeSeen, childPath));
end;

procedure TShellTreeViewTest.TestItemsAreRefusedBecauseThisTreeOwnsItsData;
var
  raised: Boolean;
begin
  AssertFalse('这棵树自己拥有节点数据,不支持条目模型', FTree.SupportsItemModel);

  raised := False;
  try
    FTree.Items.AddChild(nil, 'Root');
  except
    on E: ETyTreeItemMode do
    begin
      raised := True;
      { 报错要指向真正的原因。走到 AddChild 才抛的话消息里不会有 DoGetText —— 那种
        消息响是响,指的却是节点插入,而不是"这棵树的数据源归它自己"。 }
      AssertTrue('报错要说清是数据源归它自己,而不是某次节点插入失败',
        Pos('DoGetText', E.Message) > 0);
    end;
  end;
  AssertTrue('填 Items 必须当场被拒', raised);
  AssertFalse('并且没有半路切进条目模式', FTree.IsItemMode);
end;

{ ===== The built-in glyphs, after the image list under them was replaced =========

  BuildGlyphs used to hand-fill a TImageList at a hardcoded 16px; it now renders the same three
  BGRA masters through a TTyVirtualImageList into a TTyLCLImageList. Nothing in this file said
  anything about the icons before, so the swap was entirely unguarded -- and "the tests are
  green" would have been true with three blank squares, or with the order reversed.

  The order is load-bearing: TyShellTreeFolderGlyph/DriveGlyph/FileGlyph are 0/1/2 and the tree
  looks a node's icon up by those constants. }
type
  TShellTreeGlyphTest = class(TTestCase)
  private
    { The dominant non-transparent colour of slot AIndex, as a coarse (r,g,b). }
    function SlotInk(ATree: TTyShellTreeView; AIndex: Integer; out AR, AG, AB: Integer): Boolean;
  published
    procedure TheThreeBuiltinGlyphsAreThereInOrder;
    procedure EachGlyphActuallyHasInk;
    procedure TheThreeGlyphsAreDistinct;
  end;

function TShellTreeGlyphTest.SlotInk(ATree: TTyShellTreeView; AIndex: Integer;
  out AR, AG, AB: Integer): Boolean;
var
  bmp: TBitmap;
  x, y, n: Integer;
  c: TColor;
begin
  AR := 0; AG := 0; AB := 0; n := 0;
  Result := False;
  if (ATree.Images = nil) or (AIndex >= ATree.Images.Count) then Exit;
  bmp := TBitmap.Create;
  try
    ATree.Images.GetBitmap(AIndex, bmp);
    if (bmp.Width = 0) or (bmp.Height = 0) then Exit;
    for y := 0 to bmp.Height - 1 do
      for x := 0 to bmp.Width - 1 do
      begin
        c := bmp.Canvas.Pixels[x, y];
        { Skip the black/transparent surround; average what is left. }
        if c = clBlack then Continue;
        Inc(AR, Red(c)); Inc(AG, Green(c)); Inc(AB, Blue(c)); Inc(n);
      end;
    if n = 0 then Exit;
    AR := AR div n; AG := AG div n; AB := AB div n;
    Result := True;
  finally
    bmp.Free;
  end;
end;

procedure TShellTreeGlyphTest.TheThreeBuiltinGlyphsAreThereInOrder;
var tree: TTyShellTreeView;
begin
  tree := TTyShellTreeView.Create(nil);
  try
    AssertTrue('the built-in icons are assigned', tree.Images <> nil);
    AssertEquals('folder, drive, file -- and the constants below index them',
      3, tree.Images.Count);
    AssertEquals('at the documented size', TyShellTreeIconSize, tree.Images.Width);
  finally
    tree.Free;
  end;
end;

procedure TShellTreeGlyphTest.EachGlyphActuallyHasInk;
var
  tree: TTyShellTreeView;
  i, r, g, b: Integer;
begin
  { Three blank squares would satisfy a Count assertion perfectly. }
  tree := TTyShellTreeView.Create(nil);
  try
    for i := 0 to 2 do
      AssertTrue(Format('slot %d drew nothing at all', [i]), SlotInk(tree, i, r, g, b));
  finally
    tree.Free;
  end;
end;

procedure TShellTreeGlyphTest.TheThreeGlyphsAreDistinct;
var
  tree: TTyShellTreeView;
  r0, g0, b0, r1, g1, b1, r2, g2, b2: Integer;
begin
  { Amber folder, steel-blue drive, neutral-grey file. If the fill ever collapsed to one master
    repeated -- the obvious way to get this wrong -- every node would wear the same icon and
    Count would still say 3. }
  tree := TTyShellTreeView.Create(nil);
  try
    AssertTrue('folder', SlotInk(tree, TyShellTreeFolderGlyph, r0, g0, b0));
    AssertTrue('drive', SlotInk(tree, TyShellTreeDriveGlyph, r1, g1, b1));
    AssertTrue('file', SlotInk(tree, TyShellTreeFileGlyph, r2, g2, b2));
    { Each slot pinned to ITS OWN identity, not to an ordering. The first version compared them
      relatively -- "folder warmer than drive", "drive bluer than file" -- and REVERSING the
      three names passed it, because neutral grey sits between amber and blue on both counts.
      Its own mutation test is what said so. Measured: folder (222,174,70), drive (104,122,151),
      file (148,154,162); the margins below are wide against those and impossible for any other
      slot. }
    AssertTrue(Format('slot %d should be the AMBER folder, measured (%d,%d,%d)',
      [TyShellTreeFolderGlyph, r0, g0, b0]), r0 - b0 > 100);
    AssertTrue(Format('slot %d should be the STEEL-BLUE drive, measured (%d,%d,%d)',
      [TyShellTreeDriveGlyph, r1, g1, b1]), b1 - r1 > 30);
    AssertTrue(Format('slot %d should be the NEUTRAL-GREY file, measured (%d,%d,%d)',
      [TyShellTreeFileGlyph, r2, g2, b2]), Abs(r2 - b2) < 25);
  finally
    tree.Free;
  end;
end;

initialization
  RegisterTest(TShellTreeGlyphTest);
  RegisterTest(TShellTreeViewTest);
end.
