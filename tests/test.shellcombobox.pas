unit test.shellcombobox;
{ Phase 7 batch 4 -- headless tests for TTyShellComboBox + the pure TyLookInPlaces.

  Written FROM THE PLAN/SPEC CONTRACT ONLY
  (docs/superpowers/plans/2026-07-11-phase7-shellcombos.md +
   docs/superpowers/specs/2026-07-11-phase7-shell-filedialogs-design.md). The
  implementation (source/tyControls.ShellComboBox.pas) is being written
  independently by another agent and is deliberately NOT consulted here.

  Two seams are exercised:
    * TyLookInPlaces(dir) -- an exported PURE function; tested directly.
    * The control's Directory/SelectedPath/OnSelectPath state machine -- driven
      headless (Create(nil), never parented/painted). A user pick from the (unbuilt)
      dropdown is simulated the way the real dropdown funnels it -- set ItemIndex,
      then invoke the protected DoSelect -- via the TTyShellComboBoxAccess subclass.

  Any test needing a real directory uses a PROCESS-UNIQUE temp tree (a fixed name
  lets a crashed prior run leave stale state -- the batch-2 lesson). }

{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types,
  LazFileUtils, FileUtil,
  fpcunit, testregistry,
  tyControls.FileSystem,      { TyFsBreadcrumb, TyFsRoots, TyFsParent }
  tyControls.ComboBox,
  tyControls.ShellComboBox;   { the unit under test }

type
  { A user pick lands on DoSelect after ItemIndex is set: exactly what a dropdown
    row click funnels through. Expose it for headless driving. }
  TTyShellComboBoxAccess = class(TTyShellComboBox)
  public
    procedure PickRow(AIndex: Integer);   { set ItemIndex := AIndex; DoSelect }
  end;

  TShellComboBoxTest = class(TTestCase)
  private
    FRoot:  string;     { process-unique temp dir }
    FChild: string;     { FRoot\sub -- gives a guaranteed navigable ancestor (FRoot) }
    FPicks: Integer;    { OnSelectPath fire counter }
    procedure OnSelectPathFired(Sender: TObject);
    { The Items row whose Objects[] payload maps to a place SameFileName APath;
      -1 if none. Reads the payload back the way the control does. }
    function RowForPath(c: TTyShellComboBox; const APath: string): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { TyLookInPlaces (pure) }
    procedure TestLookInPlacesUnixBreadcrumbDepths;
    procedure TestLookInPlacesWindowsBreadcrumbDepths;
    procedure TestLookInPlacesEmptyIsRootsOnly;
    procedure TestLookInPlacesRootsDoNotRepeatCurrentRoot;
    { The control }
    procedure TestDirectorySelectsMatchingRow;
    procedure TestUserPickAncestorFiresAndSelectsIt;
    procedure TestSameDirectoryEarlyExitsWithoutFiring;
    procedure TestEmptyDirectoryClearsSelection;
  end;

implementation

const
  DIR_NAME = 'ty_shellcombo_';

{ TTyShellComboBoxAccess }

procedure TTyShellComboBoxAccess.PickRow(AIndex: Integer);
begin
  ItemIndex := AIndex;   { public setter (fires OnChange, NOT OnSelectPath) }
  DoSelect;              { the protected user-pick seam (reads Objects[ItemIndex]) }
end;

{ TShellComboBoxTest }

procedure TShellComboBoxTest.OnSelectPathFired(Sender: TObject);
begin
  Inc(FPicks);
end;

function TShellComboBoxTest.RowForPath(c: TTyShellComboBox; const APath: string): Integer;
var
  i, model: Integer;
  places: TTyLookInPlaceArray;
begin
  { The model behind the current Items is TyLookInPlaces(Directory) (a pure function),
    so the test can recompute it and map a row's Objects[] payload to a Path. }
  Result := -1;
  places := TyLookInPlaces(c.Directory);
  for i := 0 to c.Items.Count - 1 do
  begin
    model := PtrInt(c.Items.Objects[i]);
    if (model >= 0) and (model < Length(places))
       and SameFileName(places[model].Path, APath) then
      Exit(i);
  end;
end;

procedure TShellComboBoxTest.SetUp;
begin
  FPicks := 0;
  { Process-unique so a crashed prior run can never leave a stale tree behind. }
  FRoot  := ChompPathDelim(AppendPathDelim(GetTempDir) + DIR_NAME + IntToStr(GetProcessID));
  if DirectoryExistsUTF8(FRoot) then
    DeleteDirectory(FRoot, False);
  ForceDirectoriesUTF8(FRoot);
  FChild := AppendPathDelim(FRoot) + 'sub';
  ForceDirectoriesUTF8(FChild);
  FChild := ChompPathDelim(FChild);
end;

procedure TShellComboBoxTest.TearDown;
begin
  if (FRoot <> '') and DirectoryExistsUTF8(FRoot) then
    DeleteDirectory(FRoot, False);
end;

procedure TShellComboBoxTest.TestLookInPlacesUnixBreadcrumbDepths;
var places: TTyLookInPlaceArray;
begin
  { Unix-shaped input '/a/b': breadcrumb crumbs '/','/a','/a/b' -> Depths 0/1/2;
    a non-root crumb's Display is its leaf name; the last crumb's Path is the input. }
  places := TyLookInPlaces('/a/b');
  AssertTrue('at least the 3 breadcrumb rows', Length(places) >= 3);
  AssertEquals('crumb 0 depth', 0, places[0].Depth);
  AssertEquals('crumb 1 depth', 1, places[1].Depth);
  AssertEquals('crumb 2 depth', 2, places[2].Depth);
  AssertEquals('crumb 1 display is leaf name', 'a', places[1].Display);
  AssertEquals('crumb 2 display is leaf name', 'b', places[2].Display);
  AssertEquals('crumb 1 path', '/a', places[1].Path);
  AssertTrue('last crumb path equals the input', SameFileName(places[2].Path, '/a/b'));
end;

procedure TShellComboBoxTest.TestLookInPlacesWindowsBreadcrumbDepths;
var places: TTyLookInPlaceArray;
begin
  { Windows-shaped input 'C:\a\b': crumbs 'C:\','C:\a','C:\a\b' -> Depths 0/1/2;
    non-root crumbs show leaf names; last crumb Path equals the input. }
  places := TyLookInPlaces('C:\a\b');
  AssertTrue('at least the 3 breadcrumb rows', Length(places) >= 3);
  AssertEquals('crumb 0 depth', 0, places[0].Depth);
  AssertEquals('crumb 1 depth', 1, places[1].Depth);
  AssertEquals('crumb 2 depth', 2, places[2].Depth);
  AssertEquals('crumb 1 display is leaf name', 'a', places[1].Display);
  AssertEquals('crumb 2 display is leaf name', 'b', places[2].Display);
  AssertTrue('last crumb path equals the input', SameFileName(places[2].Path, 'C:\a\b'));
end;

procedure TShellComboBoxTest.TestLookInPlacesEmptyIsRootsOnly;
var places: TTyLookInPlaceArray; i: Integer;
begin
  { ADir='' -> no crumbs -> only the roots, every Depth 0. }
  places := TyLookInPlaces('');
  AssertEquals('empty dir yields exactly the roots', Length(TyFsRoots), Length(places));
  AssertTrue('roots list is never empty', Length(places) > 0);
  for i := 0 to High(places) do
    AssertEquals('every root row is depth 0', 0, places[i].Depth);
end;

procedure TShellComboBoxTest.TestLookInPlacesRootsDoNotRepeatCurrentRoot;
var
  places: TTyLookInPlaceArray;
  crumbs: TStringArray;
  i, n: Integer;
begin
  { The appended roots must exclude the current chain's own root (crumbs[0]), so the
    current chain's root appears exactly once across the whole model. Use a real dir so
    crumbs[0] is genuinely one of TyFsRoots (the meaningful, otherwise-duplicated case). }
  crumbs := TyFsBreadcrumb(FChild);
  AssertTrue('breadcrumb has a root', Length(crumbs) >= 1);
  places := TyLookInPlaces(FChild);
  n := 0;
  for i := 0 to High(places) do
    if SameFileName(places[i].Path, crumbs[0]) then
      Inc(n);
  AssertEquals('current-chain root appears exactly once', 1, n);
end;

procedure TShellComboBoxTest.TestDirectorySelectsMatchingRow;
var c: TTyShellComboBoxAccess; row: Integer;
begin
  { Directory := <temp subdir> -> ItemIndex lands on the row whose Path SameFileName's
    Directory; SelectedPath = Directory. }
  c := TTyShellComboBoxAccess.Create(nil);
  try
    c.Directory := FChild;
    row := RowForPath(c, FChild);
    AssertTrue('a row matches the directory', row >= 0);
    AssertEquals('ItemIndex is the matching row', row, c.ItemIndex);
    AssertTrue('SelectedPath equals Directory', SameFileName(c.SelectedPath, FChild));
    AssertTrue('Directory normalised (no trailing sep)', SameFileName(c.Directory, FChild));
  finally c.Free; end;
end;

procedure TShellComboBoxTest.TestUserPickAncestorFiresAndSelectsIt;
var c: TTyShellComboBoxAccess; ancestorRow: Integer;
begin
  { Simulate a user pick of an ancestor breadcrumb row -> OnSelectPath fires and
    SelectedPath = that ancestor. FRoot is FChild's real navigable parent. }
  c := TTyShellComboBoxAccess.Create(nil);
  try
    c.Directory := FChild;
    ancestorRow := RowForPath(c, FRoot);          { FRoot = TyFsParent(FChild) }
    AssertTrue('parent row present in the breadcrumb', ancestorRow >= 0);
    FPicks := 0;
    c.OnSelectPath := @OnSelectPathFired;
    c.PickRow(ancestorRow);                        { the dropdown-click funnel }
    AssertEquals('OnSelectPath fired once', 1, FPicks);
    AssertTrue('SelectedPath is the picked ancestor', SameFileName(c.SelectedPath, FRoot));
    AssertTrue('Directory navigated to the ancestor', SameFileName(c.Directory, FRoot));
  finally c.Free; end;
end;

procedure TShellComboBoxTest.TestSameDirectoryEarlyExitsWithoutFiring;
var c: TTyShellComboBoxAccess;
begin
  { Re-setting Directory to the SAME path (with and without a trailing delimiter)
    early-exits: OnSelectPath does NOT fire. Proves the re-entrancy guard. }
  c := TTyShellComboBoxAccess.Create(nil);
  try
    c.Directory := FChild;
    FPicks := 0;
    c.OnSelectPath := @OnSelectPathFired;
    c.Directory := FChild;                         { identical }
    c.Directory := AppendPathDelim(FChild);        { same path + trailing separator }
    AssertEquals('same-path set never fires OnSelectPath', 0, FPicks);
    AssertTrue('still on the same directory', SameFileName(c.Directory, FChild));
  finally c.Free; end;
end;

procedure TShellComboBoxTest.TestEmptyDirectoryClearsSelection;
var c: TTyShellComboBoxAccess;
begin
  { Directory := '' -> ItemIndex = -1 (no row SameFileName's ''), no crash. }
  c := TTyShellComboBoxAccess.Create(nil);
  try
    c.Directory := FChild;                         { start from a real selection }
    c.Directory := '';
    AssertEquals('no selected row for an empty directory', -1, c.ItemIndex);
  finally c.Free; end;
end;

initialization
  RegisterTest(TShellComboBoxTest);
end.
