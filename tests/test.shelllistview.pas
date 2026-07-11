unit test.shelllistview;
{ Phase 7 batch 2 — headless state-machine tests for TTyShellListView.

  Written FROM THE PLAN/SPEC CONTRACT ONLY
  (docs/superpowers/plans/2026-07-11-phase7-shelllistview.md +
   docs/superpowers/specs/2026-07-11-phase7-shell-filedialogs-design.md). The
  implementation (source/tyControls.ShellListView.pas) is being written
  independently by another agent and is deliberately NOT consulted here, so
  nothing in this file can ratify an implementation bug.

  No windowing: the control is Create(nil), never parented, never painted, never
  given a Handle — the ty-controls list-view family is designed to run its whole
  state machine (take / sort / rename / directory-switch) headless.

  The overridden PROTECTED accessors (GetItemCount / GetItemText /
  GetItemImageIndex / GetItemGroup / CommitEdit) and the inherited display<->item
  index seams (DisplayToItem / ItemToDisplay) are reached through a
  TTyShellListViewAccess subclass declared in this unit — exactly the mechanism
  the plan prescribes ("expose the protected members via a TTyShellListViewAccess
  subclass").

  Every filesystem touch goes through the LazFileUtils *UTF8 wrappers so the tree
  behaves the same on every platform. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Types,
  LazFileUtils, FileUtil,
  fpcunit, testregistry,
  tyControls.Columns,       { TTySortDirection, sdAscending, sdDescending }
  tyControls.FileSystem,    { TTyFsEntry(Array), fotFolders/fotFiles/fotHidden }
  tyControls.ShellListView; { the unit under test }

type
  { Re-exposes the protected accessors + the two index-space seams. A descendant
    declared here can read its ancestor's protected members even across units,
    which is precisely why the contract routes the tests through this subclass. }
  TTyShellListViewAccess = class(TTyShellListView)
  public
    function XGetItemCount: Integer;
    function XGetItemText(AIndex, AColumn: Integer): string;
    function XGetItemImageIndex(AIndex, AColumn: Integer): Integer;
    function XGetItemGroup(AIndex: Integer): Integer;
    procedure XCommitEdit(AIndex: Integer; const AText: string);
    { display position -> stable item index (the inherited DisplayToItem seam). }
    function XOrderAt(ADisplayPos: Integer): Integer;
    { item index -> display position (the inherited ItemToDisplay seam). }
    function XItemToDisplay(AItem: Integer): Integer;
  end;

  { One controlled temp tree per test, a fresh control per test. Files are named so
    their raw sizes and their display sizes disagree lexically (the sort trap). }
  TShellListViewTest = class(TTestCase)
  private
    FRoot: string;                 { enumerated directory, no trailing delimiter }
    FLV:   TTyShellListViewAccess;
    FDirChangeCount: Integer;      { OnDirectoryChange fire counter }
    { --- column indices per the four-column contract (Name/Size/Type/Modified) --- }
    const COL_NAME = 0; COL_SIZE = 1; COL_TYPE = 2; COL_MODIFIED = 3;
  private
    procedure WriteBytes(const AFullName: string; ACount: Integer);
    procedure HandleDirChange(Sender: TObject);
    function  ItemIndexOfName(const AName: string): Integer;
    function  HasItemNamed(const AName: string): Boolean;
    function  CountItems: Integer;
    function  EntryIndexIsDir(AIndex: Integer): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { ----- take: count, per-column text, FileAt / SelectedFile ----- }
    { LoadDirectory then GetItemCount = number of VISIBLE entries (dirs + non-hidden
      files); the hidden entry is excluded by default. }
    procedure TestLoadDirectoryCountIsVisibleEntries;
    { GetItemText column 0 is the entry Name for every row. }
    procedure TestNameColumnIsEntryName;
    { GetItemText column 2 is the entry TypeName for every row. }
    procedure TestTypeColumnIsEntryTypeName;
    { GetItemText size column: non-empty for a file, blank for a directory. }
    procedure TestSizeColumnFileNonEmptyDirBlank;
    { GetItemText modified column: non-empty for a file with a real timestamp. }
    procedure TestModifiedColumnNonEmptyForFile;
    { FileAt maps an item index to its FullPath; out-of-range indices return ''. }
    procedure TestFileAtReturnsFullPathAndClampsOutOfRange;
    { SelectedFile is the focused item's FullPath, '' when nothing is focused. }
    procedure TestSelectedFileFollowsFocus;

    { ----- GetItemCount never re-reads the disk ----- }
    { Repeated GetItemCount calls return the same value (no disk re-read per call). }
    procedure TestGetItemCountStableAcrossCalls;
    { Mutating the filesystem WITHOUT LoadDirectory does not change GetItemCount;
      only an explicit Refresh picks the new file up. }
    procedure TestGetItemCountIgnoresDiskUntilRefresh;

    { ----- THE SORT TRAP (highest value) ----- }
    { A ~9 KB and a ~10 KB file: their DISPLAY sizes sort lexically opposite to
      their raw sizes ('10...' < '9...'). Sorting by the Size column ascending must
      order them by NUMERIC size — 9 KB row before 10 KB row. A DoCompare that
      sorted the display string would reverse this and fail here. }
    procedure TestSizeSortIsNumericNotLexical;

    { ----- folders always sort before files, both directions ----- }
    procedure TestFoldersBeforeFilesAscending;
    procedure TestFoldersBeforeFilesDescending;

    { ----- CommitEdit renames the real file ----- }
    { CommitEdit renames on disk (old gone, new present) and, after Refresh, the
      entry carries the new Name. }
    procedure TestCommitEditRenamesOnDisk;
    { An empty new name leaves the file unchanged. }
    procedure TestCommitEditEmptyNameLeavesFileUnchanged;

    { ----- mask + hidden ----- }
    { Mask '*.txt' leaves only .txt files, but every directory is still shown. }
    procedure TestMaskLeavesTxtFilesPlusDirectories;
    { ShowHidden toggles the hidden entry in/out of the view. }
    procedure TestShowHiddenTogglesHiddenEntry;

    { ----- kind glyphs ----- }
    { GetItemImageIndex is a valid (>=0), DIFFERENT index for a directory vs a file. }
    procedure TestImageIndexDirDiffersFromFile;

    { ----- GroupByKind: per-kind buckets ----- }
    { With GroupByKind on: two directories share a group; a directory and a file
      differ; two same-extension files share a group; two different-extension files
      differ. (Only the equality relation is asserted, never the numeric group id.) }
    procedure TestGroupByKindBucketsByKind;

    { ----- OnDirectoryChange ----- }
    { LoadDirectory fires OnDirectoryChange, and again when it navigates into a
      subfolder; Directory reflects the new path each time. }
    procedure TestOnDirectoryChangeFiresOnLoadAndNavigate;

    { ----- navigation clears selection ----- }
    { LoadDirectory (a navigation) clears the focus + selection, so entering a new
      directory never auto-picks the same-row item as the just-double-clicked folder. }
    procedure TestLoadDirectoryClearsSelection;
  end;

implementation

const
  DIR_NAME  = 'tyshelllv_test';
  { The sort-trap pair: raw sizes 9 KB vs 10 KB. Any human-readable formatter
    renders these '9...' and '10...', which sort lexically in the WRONG order. }
  SIZE_9KB  = 9 * 1024;    { 9216  -> '9 KB'-ish, display starts '9' }
  SIZE_10KB = 10 * 1024;   { 10240 -> '10 KB'-ish, display starts '1' }

{ ===========================================================================
  TTyShellListViewAccess
  =========================================================================== }

function TTyShellListViewAccess.XGetItemCount: Integer;
begin
  Result := GetItemCount;
end;

function TTyShellListViewAccess.XGetItemText(AIndex, AColumn: Integer): string;
begin
  Result := GetItemText(AIndex, AColumn);
end;

function TTyShellListViewAccess.XGetItemImageIndex(AIndex, AColumn: Integer): Integer;
begin
  Result := GetItemImageIndex(AIndex, AColumn);
end;

function TTyShellListViewAccess.XGetItemGroup(AIndex: Integer): Integer;
begin
  Result := GetItemGroup(AIndex);
end;

procedure TTyShellListViewAccess.XCommitEdit(AIndex: Integer; const AText: string);
begin
  CommitEdit(AIndex, AText);
end;

function TTyShellListViewAccess.XOrderAt(ADisplayPos: Integer): Integer;
begin
  Result := DisplayToItem(ADisplayPos);
end;

function TTyShellListViewAccess.XItemToDisplay(AItem: Integer): Integer;
begin
  Result := ItemToDisplay(AItem);
end;

{ ===========================================================================
  TShellListViewTest — helpers
  =========================================================================== }

procedure TShellListViewTest.WriteBytes(const AFullName: string; ACount: Integer);
var
  h: THandle;
  data: array of Byte;
begin
  h := FileCreateUTF8(AFullName);
  try
    if ACount > 0 then
    begin
      SetLength(data, ACount);
      FillChar(data[0], ACount, Ord('x'));
      FileWrite(h, data[0], ACount);
    end;
  finally
    FileClose(h);
  end;
end;

procedure TShellListViewTest.HandleDirChange(Sender: TObject);
begin
  Inc(FDirChangeCount);
end;

function TShellListViewTest.ItemIndexOfName(const AName: string): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to FLV.XGetItemCount - 1 do
    if FLV.XGetItemText(i, COL_NAME) = AName then
      Exit(i);
end;

function TShellListViewTest.HasItemNamed(const AName: string): Boolean;
begin
  Result := ItemIndexOfName(AName) >= 0;
end;

function TShellListViewTest.CountItems: Integer;
begin
  Result := FLV.XGetItemCount;
end;

function TShellListViewTest.EntryIndexIsDir(AIndex: Integer): Boolean;
begin
  { The public read-only Entries property is the backing store; item index == its
    subscript per the whole-phase invariant. }
  Result := FLV.Entries[AIndex].IsDir;
end;

procedure TShellListViewTest.SetUp;
var
  hidden: string;
begin
  { A process-unique dir: a fixed name lets a crashed prior run leave a stale file behind,
    and a real rename correctly refuses to overwrite an existing target (RenameFileUTF8 =
    MoveFile fails on Windows if the target exists), so a leftover 'renamed.zzz' would make
    the rename test fail. Unique-per-run isolates it. }
  FRoot := ChompPathDelim(AppendPathDelim(GetTempDir) + DIR_NAME + IntToStr(GetProcessID));
  if DirectoryExistsUTF8(FRoot) then
    DeleteDirectory(FRoot, False);
  ForceDirectoriesUTF8(FRoot);

  { two directories (folders-first + one-group-for-folders) }
  ForceDirectoriesUTF8(AppendPathDelim(FRoot) + 'dir_a');
  ForceDirectoriesUTF8(AppendPathDelim(FRoot) + 'dir_b');

  { visible files: two .txt (same-extension group), one .md, plus the sort-trap pair }
  WriteBytes(AppendPathDelim(FRoot) + 'a.txt', 4);
  WriteBytes(AppendPathDelim(FRoot) + 'b.txt', 12);
  WriteBytes(AppendPathDelim(FRoot) + 'c.md', 20);
  WriteBytes(AppendPathDelim(FRoot) + 'small.dat', SIZE_9KB);
  WriteBytes(AppendPathDelim(FRoot) + 'large.dat', SIZE_10KB);

  { a hidden file: leading dot hides on Unix; also flag faHidden on Windows }
  hidden := AppendPathDelim(FRoot) + '.secret';
  WriteBytes(hidden, 3);
  {$IFDEF MSWINDOWS}
  FileSetAttrUTF8(hidden, faHidden);
  {$ENDIF}

  FLV := TTyShellListViewAccess.Create(nil);
end;

procedure TShellListViewTest.TearDown;
begin
  FreeAndNil(FLV);
  if (FRoot <> '') and DirectoryExistsUTF8(FRoot) then
    DeleteDirectory(FRoot, False);
end;

{ ===========================================================================
  take: count, per-column text, FileAt / SelectedFile
  =========================================================================== }

procedure TShellListViewTest.TestLoadDirectoryCountIsVisibleEntries;
begin
  FLV.LoadDirectory(FRoot);
  { 2 dirs + 5 non-hidden files; the hidden '.secret' is excluded by default. }
  AssertEquals('visible entry count', 7, FLV.XGetItemCount);
  AssertTrue('hidden entry not shown by default', not HasItemNamed('.secret'));
end;

procedure TShellListViewTest.TestNameColumnIsEntryName;
var
  i: Integer;
begin
  FLV.LoadDirectory(FRoot);
  for i := 0 to FLV.XGetItemCount - 1 do
    AssertEquals('name column = entry Name',
      FLV.Entries[i].Name, FLV.XGetItemText(i, COL_NAME));
end;

procedure TShellListViewTest.TestTypeColumnIsEntryTypeName;
var
  i: Integer;
begin
  FLV.LoadDirectory(FRoot);
  for i := 0 to FLV.XGetItemCount - 1 do
    AssertEquals('type column = entry TypeName',
      FLV.Entries[i].TypeName, FLV.XGetItemText(i, COL_TYPE));
end;

procedure TShellListViewTest.TestSizeColumnFileNonEmptyDirBlank;
var
  iFile, iDir: Integer;
begin
  FLV.LoadDirectory(FRoot);
  iFile := ItemIndexOfName('a.txt');
  iDir  := ItemIndexOfName('dir_a');
  AssertTrue('a.txt present', iFile >= 0);
  AssertTrue('dir_a present', iDir >= 0);
  AssertTrue('file size column is non-empty',
    FLV.XGetItemText(iFile, COL_SIZE) <> '');
  AssertEquals('directory size column is blank',
    '', FLV.XGetItemText(iDir, COL_SIZE));
end;

procedure TShellListViewTest.TestModifiedColumnNonEmptyForFile;
var
  iFile: Integer;
begin
  FLV.LoadDirectory(FRoot);
  iFile := ItemIndexOfName('a.txt');
  AssertTrue('a.txt present', iFile >= 0);
  AssertTrue('modified column non-empty for a real file',
    FLV.XGetItemText(iFile, COL_MODIFIED) <> '');
end;

procedure TShellListViewTest.TestFileAtReturnsFullPathAndClampsOutOfRange;
var
  i: Integer;
begin
  FLV.LoadDirectory(FRoot);
  i := ItemIndexOfName('a.txt');
  AssertTrue('a.txt present', i >= 0);
  AssertEquals('FileAt = entry FullPath', FLV.Entries[i].FullPath, FLV.FileAt(i));
  AssertEquals('FileAt(-1) is empty', '', FLV.FileAt(-1));
  AssertEquals('FileAt(count) is empty', '', FLV.FileAt(FLV.XGetItemCount));
end;

procedure TShellListViewTest.TestSelectedFileFollowsFocus;
var
  i: Integer;
begin
  FLV.LoadDirectory(FRoot);
  i := ItemIndexOfName('c.md');
  AssertTrue('c.md present', i >= 0);

  FLV.ItemIndex := i;
  AssertEquals('SelectedFile = focused entry FullPath',
    FLV.Entries[i].FullPath, FLV.SelectedFile);

  FLV.ItemIndex := -1;
  AssertEquals('SelectedFile is empty with nothing focused', '', FLV.SelectedFile);
end;

{ ===========================================================================
  GetItemCount never re-reads the disk
  =========================================================================== }

procedure TShellListViewTest.TestGetItemCountStableAcrossCalls;
var
  c1, c2: Integer;
begin
  FLV.LoadDirectory(FRoot);
  c1 := FLV.XGetItemCount;
  c2 := FLV.XGetItemCount;
  AssertEquals('repeated GetItemCount is stable', c1, c2);
end;

procedure TShellListViewTest.TestGetItemCountIgnoresDiskUntilRefresh;
var
  before, afterWrite, afterRefresh: Integer;
begin
  FLV.LoadDirectory(FRoot);
  before := FLV.XGetItemCount;

  { mutate the filesystem behind the control's back }
  WriteBytes(AppendPathDelim(FRoot) + 'appeared.txt', 5);

  afterWrite := FLV.XGetItemCount;
  AssertEquals('GetItemCount unchanged without LoadDirectory (no per-call disk read)',
    before, afterWrite);

  FLV.Refresh;
  afterRefresh := FLV.XGetItemCount;
  AssertEquals('Refresh picks up the new file', before + 1, afterRefresh);
end;

{ ===========================================================================
  THE SORT TRAP
  =========================================================================== }

procedure TShellListViewTest.TestSizeSortIsNumericNotLexical;
var
  iSmall, iLarge, posSmall, posLarge: Integer;
begin
  FLV.LoadDirectory(FRoot);

  FLV.SortColumn    := COL_SIZE;
  FLV.SortDirection := sdAscending;
  FLV.Sort;

  iSmall := ItemIndexOfName('small.dat');    { raw 9 KB, display starts '9' }
  iLarge := ItemIndexOfName('large.dat');    { raw 10 KB, display starts '1' }
  AssertTrue('small.dat present', iSmall >= 0);
  AssertTrue('large.dat present', iLarge >= 0);

  { sanity: the raw sizes really are 9 KB < 10 KB }
  AssertTrue('raw size small < large',
    FLV.Entries[iSmall].Size < FLV.Entries[iLarge].Size);

  posSmall := FLV.XItemToDisplay(iSmall);
  posLarge := FLV.XItemToDisplay(iLarge);
  AssertTrue('both rows visible', (posSmall >= 0) and (posLarge >= 0));

  { NUMERIC order: the 9 KB row precedes the 10 KB row. A display-string sort would
    put '10 KB' before '9 KB' and flip this. }
  AssertTrue('size sort is numeric: 9 KB row before 10 KB row',
    posSmall < posLarge);
end;

{ ===========================================================================
  folders always sort before files, both directions
  =========================================================================== }

procedure TShellListViewTest.TestFoldersBeforeFilesAscending;
var
  pos, item, lastDirPos, firstFilePos: Integer;
begin
  FLV.LoadDirectory(FRoot);
  FLV.SortColumn    := COL_NAME;
  FLV.SortDirection := sdAscending;
  FLV.Sort;

  lastDirPos   := -1;
  firstFilePos := MaxInt;
  for pos := 0 to FLV.XGetItemCount - 1 do
  begin
    item := FLV.XOrderAt(pos);
    if EntryIndexIsDir(item) then
    begin
      if pos > lastDirPos then lastDirPos := pos;
    end
    else if pos < firstFilePos then
      firstFilePos := pos;
  end;

  AssertTrue('there are dirs and files', (lastDirPos >= 0) and (firstFilePos < MaxInt));
  AssertTrue('ascending: every folder precedes every file',
    lastDirPos < firstFilePos);
end;

procedure TShellListViewTest.TestFoldersBeforeFilesDescending;
var
  pos, item, lastDirPos, firstFilePos: Integer;
begin
  FLV.LoadDirectory(FRoot);
  FLV.SortColumn    := COL_NAME;
  FLV.SortDirection := sdDescending;
  FLV.Sort;

  lastDirPos   := -1;
  firstFilePos := MaxInt;
  for pos := 0 to FLV.XGetItemCount - 1 do
  begin
    item := FLV.XOrderAt(pos);
    if EntryIndexIsDir(item) then
    begin
      if pos > lastDirPos then lastDirPos := pos;
    end
    else if pos < firstFilePos then
      firstFilePos := pos;
  end;

  AssertTrue('there are dirs and files', (lastDirPos >= 0) and (firstFilePos < MaxInt));
  AssertTrue('descending: every folder STILL precedes every file',
    lastDirPos < firstFilePos);
end;

{ ===========================================================================
  CommitEdit renames the real file
  =========================================================================== }

procedure TShellListViewTest.TestCommitEditRenamesOnDisk;
var
  i: Integer;
  oldPath, newPath: string;
begin
  FLV.LoadDirectory(FRoot);
  i := ItemIndexOfName('a.txt');
  AssertTrue('a.txt present', i >= 0);

  oldPath := AppendPathDelim(FRoot) + 'a.txt';
  newPath := AppendPathDelim(FRoot) + 'renamed.zzz';
  AssertTrue('precondition: old file exists', FileExistsUTF8(oldPath));

  FLV.XCommitEdit(i, 'renamed.zzz');

  AssertTrue('old name gone on disk',   not FileExistsUTF8(oldPath));
  AssertTrue('new name present on disk',    FileExistsUTF8(newPath));

  FLV.Refresh;
  AssertTrue('after Refresh the new name is an entry',  HasItemNamed('renamed.zzz'));
  AssertTrue('after Refresh the old name is gone',  not HasItemNamed('a.txt'));
end;

procedure TShellListViewTest.TestCommitEditEmptyNameLeavesFileUnchanged;
var
  i: Integer;
  path: string;
begin
  FLV.LoadDirectory(FRoot);
  i := ItemIndexOfName('b.txt');
  AssertTrue('b.txt present', i >= 0);
  path := AppendPathDelim(FRoot) + 'b.txt';

  FLV.XCommitEdit(i, '');

  AssertTrue('empty new name leaves the file on disk', FileExistsUTF8(path));
  FLV.Refresh;
  AssertTrue('b.txt still an entry after an empty-name commit', HasItemNamed('b.txt'));
end;

{ ===========================================================================
  mask + hidden
  =========================================================================== }

procedure TShellListViewTest.TestMaskLeavesTxtFilesPlusDirectories;
begin
  FLV.LoadDirectory(FRoot);
  FLV.Mask := '*.txt';   { contract: setting Mask auto-refreshes }

  { .txt files kept }
  AssertTrue('a.txt kept', HasItemNamed('a.txt'));
  AssertTrue('b.txt kept', HasItemNamed('b.txt'));
  { non-.txt files dropped }
  AssertTrue('c.md dropped',      not HasItemNamed('c.md'));
  AssertTrue('small.dat dropped', not HasItemNamed('small.dat'));
  AssertTrue('large.dat dropped', not HasItemNamed('large.dat'));
  { directories always shown regardless of the file mask }
  AssertTrue('dir_a still shown', HasItemNamed('dir_a'));
  AssertTrue('dir_b still shown', HasItemNamed('dir_b'));
end;

procedure TShellListViewTest.TestShowHiddenTogglesHiddenEntry;
begin
  FLV.LoadDirectory(FRoot);
  AssertTrue('hidden absent with ShowHidden off', not HasItemNamed('.secret'));

  FLV.ShowHidden := True;   { contract: toggles fotHidden + refreshes }
  AssertTrue('hidden present with ShowHidden on', HasItemNamed('.secret'));

  FLV.ShowHidden := False;
  AssertTrue('hidden absent again with ShowHidden off', not HasItemNamed('.secret'));
end;

{ ===========================================================================
  kind glyphs
  =========================================================================== }

procedure TShellListViewTest.TestImageIndexDirDiffersFromFile;
var
  iDir, iFile, imgDir, imgFile: Integer;
begin
  FLV.LoadDirectory(FRoot);
  iDir  := ItemIndexOfName('dir_a');
  iFile := ItemIndexOfName('a.txt');
  AssertTrue('dir_a present', iDir >= 0);
  AssertTrue('a.txt present', iFile >= 0);

  imgDir  := FLV.XGetItemImageIndex(iDir, COL_NAME);
  imgFile := FLV.XGetItemImageIndex(iFile, COL_NAME);

  AssertTrue('directory image index is valid (>= 0)', imgDir >= 0);
  AssertTrue('file image index is valid (>= 0)',      imgFile >= 0);
  AssertTrue('directory and file glyphs differ',      imgDir <> imgFile);
end;

{ ===========================================================================
  GroupByKind: per-kind buckets
  =========================================================================== }

procedure TShellListViewTest.TestGroupByKindBucketsByKind;
var
  iDirA, iDirB, iTxt1, iTxt2, iMd: Integer;
begin
  FLV.LoadDirectory(FRoot);
  FLV.GroupByKind := True;   { contract: GroupByKind = inherited GroupView + kind groups }

  iDirA := ItemIndexOfName('dir_a');
  iDirB := ItemIndexOfName('dir_b');
  iTxt1 := ItemIndexOfName('a.txt');
  iTxt2 := ItemIndexOfName('b.txt');
  iMd   := ItemIndexOfName('c.md');
  AssertTrue('all probe entries present',
    (iDirA >= 0) and (iDirB >= 0) and (iTxt1 >= 0) and (iTxt2 >= 0) and (iMd >= 0));

  { folders are one group }
  AssertEquals('two directories share a group',
    FLV.XGetItemGroup(iDirA), FLV.XGetItemGroup(iDirB));
  { one group per extension }
  AssertEquals('two .txt files share a group',
    FLV.XGetItemGroup(iTxt1), FLV.XGetItemGroup(iTxt2));
  { different extensions are different groups }
  AssertTrue('.txt and .md are different groups',
    FLV.XGetItemGroup(iTxt1) <> FLV.XGetItemGroup(iMd));
  { a directory and a file are different groups }
  AssertTrue('a directory and a file are different groups',
    FLV.XGetItemGroup(iDirA) <> FLV.XGetItemGroup(iTxt1));
end;

procedure TShellListViewTest.TestOnDirectoryChangeFiresOnLoadAndNavigate;
var
  subdir: string;
begin
  FLV.OnDirectoryChange := @HandleDirChange;
  FDirChangeCount := 0;

  FLV.LoadDirectory(FRoot);
  AssertEquals('OnDirectoryChange fired on the initial load', 1, FDirChangeCount);
  AssertEquals('Directory reflects the loaded path', FRoot, FLV.Directory);

  { navigate into a subfolder (what HandleItemActivate does for a directory row) }
  subdir := AppendPathDelim(FRoot) + 'dir_a';
  FLV.LoadDirectory(subdir);
  AssertEquals('OnDirectoryChange fired again on navigate', 2, FDirChangeCount);
  AssertEquals('Directory reflects the subfolder', subdir, FLV.Directory);
end;

procedure TShellListViewTest.TestLoadDirectoryClearsSelection;
var
  i: Integer;
begin
  FLV.LoadDirectory(FRoot);
  i := ItemIndexOfName('a.txt');
  AssertTrue('a.txt present', i >= 0);
  FLV.MultiSelect := True;
  FLV.ItemIndex := i;              { focus + select a row, as a click would }
  AssertTrue('a row is selected before navigating', FLV.SelCount > 0);

  { navigate (LoadDirectory) -> the focus + selection must be cleared }
  FLV.LoadDirectory(FRoot);
  AssertEquals('ItemIndex cleared after navigation', -1, FLV.ItemIndex);
  AssertEquals('selection cleared after navigation', 0, FLV.SelCount);
end;

initialization
  RegisterTest(TShellListViewTest);
end.
