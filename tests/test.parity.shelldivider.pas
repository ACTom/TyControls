unit test.parity.shelldivider;
{ API-parity guards for TTyShellTreeView and TTyDivider.

  Three defects, three groups:

  D1 — an invalid Root/Path used to fail SILENTLY. TCustomShellTreeView raises a
       typed EInvalidPath (C:/lazarus/lcl/shellctrls.pas:428 declares it; :625
       SetRoot and :1549/:1561/:1580/:1604 SetPath raise it), guarded so it never
       fires at design time (:621-624). Ours now reports through BOTH channels:
       SelectPath is a function returning Boolean + LastPathError, and the
       published Directory setter (which has no return channel) raises
       ETyShellInvalidPath outside csLoading/csDesigning.

  D2 — ShowHidden used to be flag-only: the new value did nothing until a node
       happened to be re-expanded. LCL re-enumerates immediately
       (TCustomShellTreeView.SetObjectTypes -> UpdateView, shellctrls.pas:687).
       Ours now does too, via a public UpdateView that re-enumerates the already
       expanded nodes and re-reveals the focused path.

  D3 — TDividerBevel.LeftIndent (C:/lazarus/components/lazcontrols/dividerbevel.pas:80,
       default 60) is a PIXEL offset of the caption; our Alignment is three discrete
       positions. Neither is a superset, so TTyDivider now carries both, with
       LeftIndent >= 0 winning over Alignment and any negative value meaning
       "Alignment decides" (TyDividerIndentAuto).

  FIXTURE LOCATION (deliberate, not laziness): the tree is built under GetUserDir,
  NOT GetTempDir. On Windows GetTempDir lives under ...\AppData\... which carries
  FILE_ATTRIBUTE_HIDDEN, so with ShowHidden=False the whole temp subtree is
  unreachable and the D2 guards could not observe a hide/reveal at all. Every
  component of GetUserDir (C:\, Users, <user> / $HOME) is visible on both
  platforms, so the fixture is reachable with ShowHidden either way. SetUp asserts
  that precondition rather than assuming it. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls,
  LazFileUtils, FileUtil,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller,
  tyControls.TreeView,
  tyControls.ShellTreeView,
  tyControls.Divider;

type
  { Re-exposes the protected NodePath seam (a descendant may read its ancestor's
    protected members across units). }
  TShellAccess = class(TTyShellTreeView)
  public
    function XNodePath(ANode: PTyTreeNode): string;
  end;

  { D1 + D2 — both need the same on-disk fixture, so they share one case. }
  TShellRefreshParityTest = class(TTestCase)
  private
    FRoot:   string;   { <userdir>/tyshellparity_<pid>, no trailing delimiter }
    FDirA:   string;   { <root>/a       — visible, holds b }
    FHidden: string;   { <root>/hsub    — HIDDEN }
    FTree:   TShellAccess;
    FRefreshDuringWalk: Boolean;
    procedure HandlePathChangeSetsShowHidden(Sender: TObject);
    { The node currently mapped to FRoot. A refresh re-creates every node below
      the roots, so callers must RE-FIND it rather than hold a pointer. }
    function  NodeForRoot: PTyTreeNode;
    function  ChildHasBaseName(ANode: PTyTreeNode; const ABaseName: string): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { --- D1: an unreachable path must be observable ---------------------- }
    { The happy path still says so: True + speNone. }
    procedure TestSelectPathSucceedsOnRealDirectory;
    { A path that is simply not there is speNoSuchPath, not "nothing happened". }
    procedure TestSelectPathReportsNoSuchPath;
    { A path that exists but sits under no seeded root is a DIFFERENT failure. }
    procedure TestSelectPathReportsNoRootWhenTreeHasNoRoots;
    { A path that exists and is under a root but cannot be walked to reports
      speUnreachable AND leaves the focus on the deepest reachable ancestor. }
    procedure TestSelectPathReportsUnreachableAndFocusesDeepestAncestor;
    { The published setter has no return channel, so it raises. }
    procedure TestDirectoryRaisesOnInvalidPath;
    { ...but '' is an absent selection, not a failed one. }
    procedure TestDirectoryEmptyStringIsSilent;
    { ...and it must never raise at design time (a stale .lfm path must not take
      the IDE with it), while still recording what went wrong. }
    procedure TestDirectoryDoesNotRaiseWhileDesigning;

    { --- D2: ShowHidden must take effect on the property write ------------ }
    { ShowHidden:=True must reveal the hidden child of an ALREADY-EXPANDED node
      with no further caller action. }
    procedure TestShowHiddenTrueRevealsHiddenChildImmediately;
    { ...and ShowHidden:=False must hide it again, same deal. }
    procedure TestShowHiddenFalseHidesChildImmediately;
    { UpdateView re-reads from disk while preserving expansion and focus. }
    procedure TestUpdateViewPicksUpNewDirectoryKeepingFocusAndExpansion;
    { A ShowHidden write from inside a tree walk (OnPathChange fires during
      SelectPath) must be DEFERRED to the end of the walk, never freeing the
      nodes the walk is holding — and must still be applied. }
    procedure TestShowHiddenWriteDuringWalkIsDeferredThenApplied;
  end;

  { D3 — TyDividerLayout stays a pure function; LeftIndent is one more integer in
    and no control state. }
  TDividerIndentParityTest = class(TTestCase)
  private
    FForm: TForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { TyDividerIndentAuto must leave all three alignments exactly as they were —
      this is the guard that says "adding LeftIndent restyled nothing". }
    procedure TestIndentAutoLeavesAlignmentInCharge;
    { A non-negative indent puts the caption's leading edge exactly there. }
    procedure TestIndentPlacesCaptionAtPixelOffset;
    { The documented tie-break: LeftIndent >= 0 beats Alignment. }
    procedure TestIndentOverridesAlignment;
    { LeftIndent = 0 and taLeftJustify must agree (LCL's LeftIndent=0 case). }
    procedure TestIndentZeroEqualsLeftJustify;
    { An indent past the right edge clamps instead of pushing the caption out. }
    procedure TestIndentClampedSoCaptionStaysInside;
    { The control defaults to "off", not to LCL's 60. }
    procedure TestDefaultIsAutoAndNegativesNormalise;
    { The property is actually wired into the paint path, not just stored. }
    procedure TestIndentShiftsThePaintedCaption;
  end;

implementation

{ Normalised path equality (trailing delimiter + OS case rule). }
function SamePath(const A, B: string): Boolean;
begin
  Result := SameFileName(ExcludeTrailingPathDelimiter(A),
                         ExcludeTrailingPathDelimiter(B))
            or SameFileName(A, B);
end;

function BaseNameOf(const APath: string): string;
begin
  Result := ExtractFileName(ExcludeTrailingPathDelimiter(APath));
end;

{ ===========================================================================
  TShellAccess
  =========================================================================== }

function TShellAccess.XNodePath(ANode: PTyTreeNode): string;
begin
  Result := NodePath(ANode);
end;

{ ===========================================================================
  TShellRefreshParityTest
  =========================================================================== }

procedure TShellRefreshParityTest.SetUp;
var
  probe: PTyTreeNode;
begin
  FRefreshDuringWalk := False;

  { Process-unique name: a crashed prior run must not leave state a later run
    silently inherits. }
  FRoot := ChompPathDelim(AppendPathDelim(GetUserDir) +
                          'tyshellparity_' + IntToStr(GetProcessID));
  if DirectoryExistsUTF8(FRoot) then
    DeleteDirectory(FRoot, False);
  ForceDirectoriesUTF8(FRoot);

  FDirA   := AppendPathDelim(FRoot) + 'a';
  FHidden := AppendPathDelim(FRoot) + 'hsub';
  ForceDirectoriesUTF8(AppendPathDelim(FDirA) + 'b');
  ForceDirectoriesUTF8(FHidden);
  {$IFDEF MSWINDOWS}
  FileSetAttrUTF8(FHidden, faHidden);
  {$ENDIF}

  FTree := TShellAccess.Create(nil);

  { PRECONDITION, asserted not assumed: with ShowHidden OFF the fixture must be
    reachable, i.e. no ancestor of GetUserDir is hidden on this host. If this
    fails the D2 guards below would be meaningless rather than wrong. }
  FTree.ShowHidden := False;
  FTree.PopulateRoots;
  FTree.SelectPath(FRoot);
  probe := FTree.FocusedNode;
  AssertTrue('fixture reachable with ShowHidden=False (no hidden ancestor)',
    (probe <> nil) and SamePath(FTree.XNodePath(probe), FRoot));
end;

procedure TShellRefreshParityTest.TearDown;
begin
  FreeAndNil(FTree);
  if (FRoot <> '') and DirectoryExistsUTF8(FRoot) then
    DeleteDirectory(FRoot, False);
end;

procedure TShellRefreshParityTest.HandlePathChangeSetsShowHidden(Sender: TObject);
begin
  { Fire once: the refresh this triggers re-reveals the path and would otherwise
    re-enter here forever. }
  if FRefreshDuringWalk then Exit;
  FRefreshDuringWalk := True;
  FTree.ShowHidden := True;   { written from INSIDE SelectPath's walk }
end;

function TShellRefreshParityTest.NodeForRoot: PTyTreeNode;
begin
  FTree.SelectPath(FRoot);
  Result := FTree.FocusedNode;
  AssertTrue('temp root is reachable', Result <> nil);
  AssertTrue('focused node is the temp root',
    SamePath(FTree.XNodePath(Result), FRoot));
end;

function TShellRefreshParityTest.ChildHasBaseName(ANode: PTyTreeNode;
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

{ --- D1 -------------------------------------------------------------------- }

procedure TShellRefreshParityTest.TestSelectPathSucceedsOnRealDirectory;
begin
  AssertTrue('SelectPath reports success for a reachable directory',
    FTree.SelectPath(FDirA));
  AssertEquals('LastPathError is speNone after a success',
    Ord(speNone), Ord(FTree.LastPathError));
  AssertTrue('Directory reads the selection back', SamePath(FTree.Directory, FDirA));
end;

procedure TShellRefreshParityTest.TestSelectPathReportsNoSuchPath;
var
  bogus: string;
begin
  bogus := AppendPathDelim(FRoot) + 'no_such_dir_xyz';
  AssertTrue('precondition: the path really is absent',
    not DirectoryExistsUTF8(bogus));

  AssertTrue('SelectPath reports failure for a path that does not exist',
    not FTree.SelectPath(bogus));
  AssertEquals('...and says WHICH failure it was',
    Ord(speNoSuchPath), Ord(FTree.LastPathError));
end;

procedure TShellRefreshParityTest.TestSelectPathReportsNoRootWhenTreeHasNoRoots;
begin
  { An existing directory with no seeded root above it -- e.g. SelectPath called
    before PopulateRoots. A different diagnosis from "no such directory", and the
    caller has to be able to tell them apart to know whether to fix the path or
    to seed the tree. }
  FTree.Clear;
  AssertTrue('SelectPath fails when no root is a prefix',
    not FTree.SelectPath(FRoot));
  AssertEquals('...reported as speNoRoot',
    Ord(speNoRoot), Ord(FTree.LastPathError));
end;

procedure TShellRefreshParityTest.TestSelectPathReportsUnreachableAndFocusesDeepestAncestor;
var
  node: PTyTreeNode;
  fresh: string;
begin
  node := NodeForRoot;
  FTree.Expanded[node] := True;      { children cached as of NOW }

  { Created AFTER the enumeration, so the tree's cached child list cannot know
    about it: the path exists on disk and lies under a root, but the walk runs
    out of nodes partway. That is neither a typo nor an empty directory, and it
    used to be indistinguishable from both. }
  fresh := AppendPathDelim(FRoot) + 'zz_fresh';
  ForceDirectoriesUTF8(AppendPathDelim(fresh) + 'leaf');

  AssertTrue('SelectPath fails on a segment it cannot walk',
    not FTree.SelectPath(AppendPathDelim(fresh) + 'leaf'));
  AssertEquals('...reported as speUnreachable',
    Ord(speUnreachable), Ord(FTree.LastPathError));
  AssertTrue('focus is left on the deepest reachable ancestor, not nowhere',
    SamePath(FTree.SelectedPath, FRoot));
end;

procedure TShellRefreshParityTest.TestDirectoryRaisesOnInvalidPath;
var
  raised: Boolean;
  bogus: string;
begin
  bogus := AppendPathDelim(FRoot) + 'no_such_dir_xyz';
  raised := False;
  try
    FTree.Directory := bogus;
  except
    on E: ETyShellInvalidPath do
      raised := True;
  end;
  AssertTrue('a property write that cannot be honoured raises', raised);
  AssertEquals('...and the reason is still readable afterwards',
    Ord(speNoSuchPath), Ord(FTree.LastPathError));
end;

procedure TShellRefreshParityTest.TestDirectoryEmptyStringIsSilent;
var
  raised: Boolean;
begin
  raised := False;
  try
    FTree.Directory := '';
  except
    on E: ETyShellInvalidPath do
      raised := True;
  end;
  AssertTrue('assigning '''' is an absent selection, not a failed one', not raised);
  AssertEquals('recorded as speEmptyPath',
    Ord(speEmptyPath), Ord(FTree.LastPathError));
end;

procedure TShellRefreshParityTest.TestDirectoryDoesNotRaiseWhileDesigning;
var
  raised: Boolean;
  bogus: string;
begin
  bogus := AppendPathDelim(FRoot) + 'no_such_dir_xyz';
  FTree.SetDesigning(True, False);
  raised := False;
  try
    FTree.Directory := bogus;
  except
    on E: ETyShellInvalidPath do
      raised := True;
  end;
  FTree.SetDesigning(False, False);
  { LCL makes the same carve-out (shellctrls.pas:621-624): a stale path in a form
    must not crash the designer. }
  AssertTrue('no raise at design time', not raised);
  AssertEquals('but the failure is still recorded, so the designer is not blind',
    Ord(speNoSuchPath), Ord(FTree.LastPathError));
end;

{ --- D2 -------------------------------------------------------------------- }

procedure TShellRefreshParityTest.TestShowHiddenTrueRevealsHiddenChildImmediately;
var
  node: PTyTreeNode;
begin
  node := NodeForRoot;
  FTree.Expanded[node] := True;          { enumerated with ShowHidden = False }
  AssertTrue('precondition: hidden child absent while ShowHidden is off',
    not ChildHasBaseName(node, 'hsub'));
  AssertTrue('precondition: visible child present', ChildHasBaseName(node, 'a'));

  { The whole defect: THIS write alone must change what the tree shows. No
    collapse, no SetChildCount, no PopulateRoots by the caller. }
  FTree.ShowHidden := True;

  node := NodeForRoot;   { the refresh re-seeds children; re-find the node }
  AssertTrue('hidden child revealed by the ShowHidden write alone',
    ChildHasBaseName(node, 'hsub'));
  AssertTrue('visible child survived the refresh', ChildHasBaseName(node, 'a'));
  AssertTrue('focused path preserved across the refresh',
    SamePath(FTree.SelectedPath, FRoot));
end;

procedure TShellRefreshParityTest.TestShowHiddenFalseHidesChildImmediately;
var
  node: PTyTreeNode;
begin
  FTree.ShowHidden := True;
  node := NodeForRoot;
  FTree.Expanded[node] := True;
  AssertTrue('precondition: hidden child present while ShowHidden is on',
    ChildHasBaseName(node, 'hsub'));

  FTree.ShowHidden := False;

  node := NodeForRoot;
  AssertTrue('hidden child hidden again by the ShowHidden write alone',
    not ChildHasBaseName(node, 'hsub'));
  AssertTrue('visible child survived the refresh', ChildHasBaseName(node, 'a'));
end;

procedure TShellRefreshParityTest.TestUpdateViewPicksUpNewDirectoryKeepingFocusAndExpansion;
var
  node: PTyTreeNode;
begin
  node := NodeForRoot;
  FTree.Expanded[node] := True;
  AssertTrue('precondition: the fresh dir does not exist yet',
    not ChildHasBaseName(node, 'zz_fresh'));

  ForceDirectoriesUTF8(AppendPathDelim(FRoot) + 'zz_fresh');
  AssertTrue('precondition: the cached child list is stale',
    not ChildHasBaseName(node, 'zz_fresh'));

  FTree.UpdateView;

  node := NodeForRoot;
  AssertTrue('UpdateView re-read the directory from disk',
    ChildHasBaseName(node, 'zz_fresh'));
  AssertTrue('the node it was expanded on is still expanded',
    FTree.Expanded[node]);
  AssertTrue('the focused path survived the refresh',
    SamePath(FTree.SelectedPath, FRoot));
end;

procedure TShellRefreshParityTest.TestShowHiddenWriteDuringWalkIsDeferredThenApplied;
var
  node: PTyTreeNode;
  reached: Boolean;
begin
  { OnPathChange fires from inside SelectPath (FocusedNode := node). A refresh
    that ran THERE would free the nodes the walk still holds. It must be queued
    and applied after the walk unwinds -- and it must actually be applied. }
  node := NodeForRoot;
  FTree.Expanded[node] := True;         { children cached with ShowHidden = False }
  AssertTrue('precondition: hidden child is not in the cached child list',
    not ChildHasBaseName(node, 'hsub'));

  { Move the focus off FRoot so the SelectPath below genuinely CHANGES it --
    re-focusing the node that is already focused fires no OnChange, and the
    handler would never run. }
  FTree.SelectPath(FDirA);

  FTree.OnPathChange := @HandlePathChangeSetsShowHidden;
  reached := FTree.SelectPath(FRoot);   { the handler flips ShowHidden mid-walk }
  FTree.OnPathChange := nil;

  AssertTrue('the handler did run (ShowHidden was written mid-walk)',
    FRefreshDuringWalk);
  { The walk's OWN verdict must survive the refresh it triggered. A refresh that
    ran immediately would free `node` inside SelectPath, and the "did I land on
    the target?" check that follows would then read a dead node -- so this is the
    assertion that fails if the deferral is removed. }
  AssertTrue('the walk still reported success after triggering a refresh', reached);
  AssertEquals('...with no error recorded',
    Ord(speNone), Ord(FTree.LastPathError));
  AssertTrue('ShowHidden holds the value written mid-walk', FTree.ShowHidden);

  { No re-expand here, deliberately: FRoot was ALREADY expanded, so the only way
    hsub can be in its child list is if the deferred refresh really ran. }
  node := NodeForRoot;
  AssertTrue('the deferred refresh actually re-enumerated the expanded node',
    ChildHasBaseName(node, 'hsub'));
  AssertTrue('...and the node it re-enumerated is still expanded',
    FTree.Expanded[node]);
  AssertTrue('the walk still landed on the requested path',
    SamePath(FTree.SelectedPath, FRoot));
end;

{ ===========================================================================
  TDividerIndentParityTest
  =========================================================================== }

type
  { Reaches the protected RenderTo so the paint path can be probed headless. }
  TDividerAccess = class(TTyDivider)
  public
    procedure XRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

procedure TDividerAccess.XRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TDividerIndentParityTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
end;

procedure TDividerIndentParityTest.TearDown;
begin
  FForm.Free;
end;

procedure TDividerIndentParityTest.TestIndentAutoLeavesAlignmentInCharge;
var
  L: TTyDividerLayout;
begin
  { The regression guard for the whole change: with the indent off, every
    alignment must land exactly where it landed before LeftIndent existed. }
  L := TyDividerLayout(200, 24, 40, taLeftJustify, TyDividerIndentAuto, 6, 4, 1);
  AssertEquals('auto + left: caption at 0', 0, L.CaptionRect.Left);
  AssertEquals('auto + left: rule after caption+gap', 46, L.RightRule.Left);
  AssertEquals('auto + left: no left rule', 0, L.LeftRule.Right - L.LeftRule.Left);

  L := TyDividerLayout(200, 24, 40, taRightJustify, TyDividerIndentAuto, 6, 4, 1);
  AssertEquals('auto + right: caption hugs the right', 160, L.CaptionRect.Left);
  AssertEquals('auto + right: left rule ends at caption-gap', 154, L.LeftRule.Right);
  AssertEquals('auto + right: no right rule', 0, L.RightRule.Right - L.RightRule.Left);

  L := TyDividerLayout(200, 24, 40, taCenter, TyDividerIndentAuto, 6, 4, 1);
  AssertEquals('auto + centre: caption centred', 80, L.CaptionRect.Left);
  AssertEquals('auto + centre: left rule to caption-gap', 74, L.LeftRule.Right);
  AssertEquals('auto + centre: right rule from caption+gap', 126, L.RightRule.Left);
end;

procedure TDividerIndentParityTest.TestIndentPlacesCaptionAtPixelOffset;
var
  L: TTyDividerLayout;
begin
  { The thing Alignment could never say: "60 pixels in" (TDividerBevel's default,
    dividerbevel.pas:80). }
  L := TyDividerLayout(200, 24, 40, taLeftJustify, 60, 6, 4, 1);
  AssertEquals('caption leading edge sits at the indent', 60, L.CaptionRect.Left);
  AssertEquals('caption ends at indent + width', 100, L.CaptionRect.Right);
  AssertEquals('left rule runs 0..indent-gap', 0, L.LeftRule.Left);
  AssertEquals('left rule ends before the caption', 54, L.LeftRule.Right);
  AssertEquals('right rule starts after caption+gap', 106, L.RightRule.Left);
  AssertEquals('right rule reaches the edge', 200, L.RightRule.Right);
end;

procedure TDividerIndentParityTest.TestIndentOverridesAlignment;
var
  L: TTyDividerLayout;
begin
  { The documented tie-break, asserted for the alignment that disagrees most:
    taRightJustify would put the caption at 160, the indent says 60. }
  L := TyDividerLayout(200, 24, 40, taRightJustify, 60, 6, 4, 1);
  AssertEquals('a set LeftIndent wins over Alignment', 60, L.CaptionRect.Left);
  L := TyDividerLayout(200, 24, 40, taCenter, 60, 6, 4, 1);
  AssertEquals('...for taCenter too', 60, L.CaptionRect.Left);
end;

procedure TDividerIndentParityTest.TestIndentZeroEqualsLeftJustify;
var
  A, B: TTyDividerLayout;
begin
  { LCL's LeftIndent = 0 case (dividerbevel.pas:325-326) draws no leading bevel.
    The two spellings of "hard left" must produce identical geometry, or the
    property pair is incoherent. }
  A := TyDividerLayout(200, 24, 40, taLeftJustify, 0, 6, 4, 1);
  B := TyDividerLayout(200, 24, 40, taLeftJustify, TyDividerIndentAuto, 6, 4, 1);
  AssertEquals('same caption left', B.CaptionRect.Left, A.CaptionRect.Left);
  AssertEquals('same caption right', B.CaptionRect.Right, A.CaptionRect.Right);
  AssertEquals('same right-rule start', B.RightRule.Left, A.RightRule.Left);
  AssertEquals('indent 0 leaves no leading rule', 0, A.LeftRule.Right - A.LeftRule.Left);
end;

procedure TDividerIndentParityTest.TestIndentClampedSoCaptionStaysInside;
var
  L: TTyDividerLayout;
begin
  { 180 + 40 would run 20px past the edge. Clamp rather than clip: a divider that
    silently loses its label is worse than one whose indent stops growing. }
  L := TyDividerLayout(200, 24, 40, taLeftJustify, 180, 6, 4, 1);
  AssertEquals('caption pushed back to fit', 160, L.CaptionRect.Left);
  AssertEquals('caption ends exactly at the edge', 200, L.CaptionRect.Right);
  AssertEquals('no right rule left to draw', 0, L.RightRule.Right - L.RightRule.Left);

  { An indent wider than the whole content rect floors at 0. }
  L := TyDividerLayout(30, 24, 40, taLeftJustify, 500, 6, 4, 1);
  AssertEquals('caption floored at 0', 0, L.CaptionRect.Left);
end;

procedure TDividerIndentParityTest.TestDefaultIsAutoAndNegativesNormalise;
var
  D: TTyDivider;
begin
  D := TTyDivider.Create(FForm);
  try
    { NOT LCL's 60: inheriting that default would silently re-indent every
      divider that already exists. }
    AssertEquals('default LeftIndent is auto',
      TyDividerIndentAuto, D.LeftIndent);
    D.LeftIndent := -7;
    AssertEquals('any negative normalises to the named sentinel',
      TyDividerIndentAuto, D.LeftIndent);
    D.LeftIndent := 24;
    AssertEquals('a non-negative indent is kept verbatim', 24, D.LeftIndent);
  finally
    D.Free;
  end;
end;

{ TestIndentShiftsThePaintedCaption
  A stored-but-unused property is the same defect in a new place, so probe the
  PAINT. Green caption on white: with the indent off there are glyph pixels near
  the left edge; with LeftIndent = 60 that band must be clean and the glyphs must
  have moved to the right of it. }
procedure TDividerIndentParityTest.TestIndentShiftsThePaintedCaption;
const
  W = 200;
  H = 24;

  { True when a green-dominant (= caption text) pixel exists in x in [AX1..AX2]. }
  function HasCaptionPixel(ABmp: TBGRABitmap; AX1, AX2: Integer): Boolean;
  var
    x, y: Integer;
    Px: TBGRAPixel;
  begin
    Result := False;
    for y := 2 to H - 3 do
      for x := AX1 to AX2 do
      begin
        Px := ABmp.GetPixel(x, y);
        if (Px.green > 120) and (Px.green > Px.red + 30) and (Px.green > Px.blue + 30) then
          Exit(True);
      end;
  end;

  function RenderAt(AIndent: Integer): TBGRABitmap;
  var
    Ctl: TTyStyleController;
    D: TDividerAccess;
    F: TForm;
    Bmp: TBitmap;
  begin
    Ctl := TTyStyleController.Create(nil);
    F := TForm.CreateNew(nil);
    Bmp := TBitmap.Create;
    try
      Ctl.LoadThemeCss('TyDivider { color: #10B981; border-color: #D1D5DB; ' +
        'border-width: 1px; padding: 0px; font-size: 12px; }');
      D := TDividerAccess.Create(F);
      D.Parent := F;
      D.Controller := Ctl;
      D.Font.PixelsPerInch := 96;      { scale 1: LeftIndent px == device px }
      D.Alignment := taLeftJustify;
      D.Caption := 'Section';
      D.LeftIndent := AIndent;
      D.SetBounds(0, 0, W, H);

      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(W, H);
      Bmp.Canvas.Brush.Color := clWhite;
      Bmp.Canvas.FillRect(0, 0, W, H);
      D.XRenderTo(Bmp.Canvas, Rect(0, 0, W, H), 96);
      Result := TBGRABitmap.Create(Bmp);
    finally
      Bmp.Free;
      F.Free;
      Ctl.Free;
    end;
  end;

var
  auto, indented: TBGRABitmap;
begin
  auto := RenderAt(TyDividerIndentAuto);
  try
    AssertTrue('baseline: the caption paints at the left edge with no indent',
      HasCaptionPixel(auto, 0, 20));
  finally
    auto.Free;
  end;

  indented := RenderAt(60);
  try
    AssertTrue('LeftIndent cleared the leading band',
      not HasCaptionPixel(indented, 0, 50));
    AssertTrue('LeftIndent moved the caption to the offset',
      HasCaptionPixel(indented, 55, 140));
  finally
    indented.Free;
  end;
end;

initialization
  RegisterTest(TShellRefreshParityTest);
  RegisterTest(TDividerIndentParityTest);
end.
</content>
</invoke>
