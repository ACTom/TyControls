unit test.filesystem;
{ Phase 7 batch 1 — headless tests for the PURE tyControls.FileSystem unit.

  Written from the SPEC CONTRACT ONLY (docs/superpowers/specs/2026-07-11-phase7-
  shell-filedialogs-design.md, section "Foundation —— tyControls.FileSystem.pas" + its
  9-item edge-case checklist). The implementation is being written independently by
  another agent and is deliberately NOT consulted, so nothing here can ratify an
  implementation bug.

  Every filesystem touch in SetUp/TearDown goes through the LazFileUtils *UTF8
  wrappers so the unicode round-trip test really exercises non-ASCII names. The
  unicode file name is built from code points via UTF8Encode so the assertion does
  not depend on this source file's on-disk encoding. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Types,
  LazFileUtils, FileUtil,
  fpcunit, testregistry,
  tyControls.FileSystem;

type
  { ---------------------------------------------------------------------------
    Rules 1,2,3,4 (enumeration side) + Size field + rule 9 (unicode round-trip).
    Builds a controlled temp tree in SetUp, deletes it in TearDown.
    --------------------------------------------------------------------------- }
  TFsReadDirTest = class(TTestCase)
  private
    FRoot: string;         { the enumerated directory, no trailing delimiter }
    FSubA: string;         { an EMPTY subdirectory — doubles as the empty-dir case }
    FUnicodeName: string;  { 'test-file.bin' (Chinese name), built from code points, UTF-8 bytes }
    procedure WriteBytes(const AFullName: string; ACount: Integer);
    function IndexOfName(const A: TTyFsEntryArray; const AName: string): Integer;
    function HasName(const A: TTyFsEntryArray; const AName: string): Boolean;
    function CountDirs(const A: TTyFsEntryArray): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { Rule 1: an empty directory enumerates to an empty array. }
    procedure TestEmptyDirectoryYieldsEmptyArray;
    { Rule 1: a non-existent directory enumerates to an empty array, no crash. }
    procedure TestNonExistentDirectoryYieldsEmptyArray;
    { Rule 2: fotFolders alone -> only directories. }
    procedure TestFoldersOnlyReturnsOnlyDirs;
    { Rule 2: fotFiles alone -> only files (hidden dropped, no fotHidden). }
    procedure TestFilesOnlyReturnsOnlyFiles;
    { Rule 2: fotFolders+fotFiles -> every visible entry, hidden dropped. }
    procedure TestFoldersAndFilesReturnsAllVisible;
    { Rule 2/3: the hidden file is dropped when fotHidden is OFF. }
    procedure TestHiddenDroppedWithoutFotHidden;
    { Rule 3: the hidden file is kept when fotHidden is ON, with IsHidden=True. }
    procedure TestHiddenKeptWithFotHidden;
    { Rule 3: visible entries report IsHidden=False. }
    procedure TestVisibleEntriesNotHidden;
    { Rule 4: '*.txt;*.md' matches those files only; both dirs still shown. }
    procedure TestMaskFiltersFilesDirsAlwaysShown;
    { Rule 4: a single-extension mask narrows the file set, dirs stay. }
    procedure TestSingleExtensionMask;
    { Rule 4: '*.*' is equivalent to all. }
    procedure TestStarDotStarMaskIsAll;
    { Rule 4: '' is equivalent to all. }
    procedure TestEmptyMaskIsAll;
    { Size:Int64 field reflects the real byte count of the file. }
    procedure TestSizeFieldReflectsBytes;
    { IsDir + FullPath fields: a dir entry is IsDir and its FullPath exists. }
    procedure TestDirEntryFieldsConsistent;
    { Rule 9: the Chinese-named file round-trips through the *UTF8 enumeration. }
    procedure TestUnicodeNameRoundTrip;
  end;

  { ---------------------------------------------------------------------------
    Rule 4 (mask predicate) — pure string function, no filesystem.
    --------------------------------------------------------------------------- }
  TFsMatchTest = class(TTestCase)
  published
    { A single-extension pattern matches its extension and rejects others. }
    procedure TestSingleExtensionMatch;
    { A ';'-separated pattern list matches any listed extension. }
    procedure TestSemicolonListMatch;
    { '*.*' is normalised to all — even a name with NO extension matches. }
    procedure TestStarDotStarMatchesNoExtensionName;
    { '' is normalised to all. }
    procedure TestEmptyPatternMatchesEverything;
    { A non-matching extension returns False. }
    procedure TestNonMatchReturnsFalse;
    { Case-insensitive request matches across letter case (file-dialog quirk). }
    procedure TestCaseInsensitiveMatch;
    { 'foo.*' matches a name with no extension (file-dialog convention). }
    procedure TestFooDotStarQuirk;
  end;

  { ---------------------------------------------------------------------------
    Rule 5 — TyFsParseFilter / TyFsFilterPatterns, pure string functions.
    --------------------------------------------------------------------------- }
  TFsFilterParseTest = class(TTestCase)
  published
    { A two-segment pipe filter parses to 2 specs with correct captions/patterns. }
    procedure TestTwoSegmentFilter;
    { A three-segment filter parses to 3 specs; a multi-pattern segment is kept whole. }
    procedure TestThreeSegmentFilter;
    { TyFsFilterPatterns is 1-based and returns the segment's pattern string. }
    procedure TestFilterPatternsOneBased;
    { An index below 1 clamps to the first segment. }
    procedure TestFilterPatternsClampLow;
    { An index past the end clamps to the last segment. }
    procedure TestFilterPatternsClampHigh;
    { A malformed (odd) filter does not crash and still yields the first pair. }
    procedure TestMalformedFilterNoCrash;
    { An empty filter string does not crash. }
    procedure TestEmptyFilterNoCrash;
  end;

  { ---------------------------------------------------------------------------
    Rule 6 — TyFsCompareEntries / TyFsSortEntries, pure on hand-built records.
    --------------------------------------------------------------------------- }
  TFsCompareSortTest = class(TTestCase)
  private
    function MkEntry(const AName: string; AIsDir: Boolean; ASize: Int64;
      AModified: TDateTime): TTyFsEntry;
  published
    { Directories sort before files when ascending and AFoldersFirst. }
    procedure TestFoldersBeforeFilesAscending;
    { Directories sort before files even when descending (direction never flips this). }
    procedure TestFoldersBeforeFilesDescending;
    { With AFoldersFirst=False the folder-first rule is off; the key decides. }
    procedure TestFoldersFirstFalseUsesKey;
    { fskName ascending vs descending flips the comparable-value ordering. }
    procedure TestNameAscendingThenDescending;
    { fskSize compares as Int64 (values beyond 32-bit are not truncated). }
    procedure TestSizeComparedAsInt64;
    { fskModified compares as TDateTime. }
    procedure TestModifiedComparedAsDateTime;
    { Name comparison follows OS case rules (case-insensitive on Windows). }
    procedure TestNameFollowsOSCaseRule;
    { In-place sort: folders first, then files, name-ascending within each group. }
    procedure TestSortFoldersFirstNameAscending;
    { In-place sort descending: folders still first, order reversed within groups. }
    procedure TestSortFoldersFirstNameDescending;
  end;

  { ---------------------------------------------------------------------------
    Rule 7 — TyFsResolveSaveName, exercised against a real temp directory.
    --------------------------------------------------------------------------- }
  TFsResolveTest = class(TTestCase)
  private
    FDir: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { A bare name gets DefaultExt and is expanded against ADir. }
    procedure TestBareNameGetsDefaultExtInDir;
    { A name that already has an extension keeps it (DefaultExt not applied). }
    procedure TestExistingExtensionUntouched;
    { A name whose extension differs from DefaultExt still keeps its own. }
    procedure TestDifferentExistingExtensionUntouched;
  end;

  { ---------------------------------------------------------------------------
    Rule 8 — TyFsRoots.
    --------------------------------------------------------------------------- }
  TFsRootsTest = class(TTestCase)
  published
    { At least one root is returned and it does not crash. }
    procedure TestReturnsAtLeastOneRoot;
    { No root has an empty Path. }
    procedure TestNoRootHasEmptyPath;
    { The OS-expected root kind is present (drive on Windows; root+home on Unix). }
    procedure TestOSExpectedKindPresent;
  end;

  { ---------------------------------------------------------------------------
    Ancillary contract functions — TyFsParent / TyFsBreadcrumb / TyFsTypeName.
    Not in the numbered 9, but part of the published signature set.
    --------------------------------------------------------------------------- }
  TFsPathTest = class(TTestCase)
  private
    FRoot, FSub: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { The parent of a subdirectory is its containing directory. }
    procedure TestParentOfSubIsRoot;
    { A breadcrumb of a nested path returns a non-empty list, no crash. }
    procedure TestBreadcrumbNonEmpty;
    { Breadcrumb crumbs are CUMULATIVE navigable paths, root first. }
    procedure TestBreadcrumbCumulativePathsUnix;
    procedure TestBreadcrumbCumulativePathsWindows;
    procedure TestBreadcrumbRootAlone;
    procedure TestBreadcrumbEmptyPath;
    { TypeName heuristic yields a non-empty label for a file and a directory. }
    procedure TestTypeNameNonEmpty;
  end;

implementation

const
  DIR_NAME = 'tyfs_test_readdir';
  { the four Chinese code points -> UTF-8 via UTF8Encode, then '.bin' appended }
  CN_TEST  = UnicodeString(#$6D4B#$8BD5#$6587#$4EF6);

{ ===========================================================================
  TFsReadDirTest
  =========================================================================== }

procedure TFsReadDirTest.WriteBytes(const AFullName: string; ACount: Integer);
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

function TFsReadDirTest.IndexOfName(const A: TTyFsEntryArray;
  const AName: string): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(A) do
    if A[i].Name = AName then
      Exit(i);
end;

function TFsReadDirTest.HasName(const A: TTyFsEntryArray;
  const AName: string): Boolean;
begin
  Result := IndexOfName(A, AName) >= 0;
end;

function TFsReadDirTest.CountDirs(const A: TTyFsEntryArray): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(A) do
    if A[i].IsDir then
      Inc(Result);
end;

procedure TFsReadDirTest.SetUp;
var
  hidden: string;
begin
  FRoot := ChompPathDelim(AppendPathDelim(GetTempDir) + DIR_NAME);
  { start clean }
  if DirectoryExistsUTF8(FRoot) then
    DeleteDirectory(FRoot, False);
  ForceDirectoriesUTF8(FRoot);

  FSubA := AppendPathDelim(FRoot) + 'sub_a';
  ForceDirectoriesUTF8(FSubA);                          { empty dir }
  ForceDirectoriesUTF8(AppendPathDelim(FRoot) + 'sub_b'); { empty dir }

  { visible files with distinct extensions and sizes }
  WriteBytes(AppendPathDelim(FRoot) + 'a.txt', 4);
  WriteBytes(AppendPathDelim(FRoot) + 'b.md', 10);
  WriteBytes(AppendPathDelim(FRoot) + 'big.dat', 5000);
  WriteBytes(AppendPathDelim(FRoot) + 'photo.png', 20);

  { unicode-named file — built from code points so the assertion is encoding-safe }
  FUnicodeName := UTF8Encode(CN_TEST) + '.bin';
  WriteBytes(AppendPathDelim(FRoot) + FUnicodeName, 8);

  { hidden file: leading dot (hides on Unix); also set faHidden on Windows }
  hidden := AppendPathDelim(FRoot) + '.hidden';
  WriteBytes(hidden, 3);
  {$IFDEF MSWINDOWS}
  FileSetAttrUTF8(hidden, faHidden);
  {$ENDIF}
end;

procedure TFsReadDirTest.TearDown;
begin
  if (FRoot <> '') and DirectoryExistsUTF8(FRoot) then
    DeleteDirectory(FRoot, False);
end;

procedure TFsReadDirTest.TestEmptyDirectoryYieldsEmptyArray;
var
  a: TTyFsEntryArray;
begin
  { sub_a is empty; every object type requested }
  a := TyFsReadDirectory(FSubA, '*', [fotFolders, fotFiles, fotHidden]);
  AssertEquals('empty dir -> 0 entries', 0, Length(a));
end;

procedure TFsReadDirTest.TestNonExistentDirectoryYieldsEmptyArray;
var
  a: TTyFsEntryArray;
begin
  a := TyFsReadDirectory(AppendPathDelim(FRoot) + 'nope_missing', '*',
    [fotFolders, fotFiles, fotHidden]);
  AssertEquals('missing dir -> 0 entries', 0, Length(a));
end;

procedure TFsReadDirTest.TestFoldersOnlyReturnsOnlyDirs;
var
  a: TTyFsEntryArray;
  i: Integer;
begin
  a := TyFsReadDirectory(FRoot, '*', [fotFolders]);
  AssertEquals('folders-only count = 2', 2, Length(a));
  for i := 0 to High(a) do
    AssertTrue('every entry is a dir', a[i].IsDir);
  AssertTrue('sub_a present', HasName(a, 'sub_a'));
  AssertTrue('sub_b present', HasName(a, 'sub_b'));
end;

procedure TFsReadDirTest.TestFilesOnlyReturnsOnlyFiles;
var
  a: TTyFsEntryArray;
  i: Integer;
begin
  a := TyFsReadDirectory(FRoot, '*', [fotFiles]);
  { 5 visible files; hidden dropped (no fotHidden); dirs dropped (no fotFolders) }
  AssertEquals('files-only count = 5', 5, Length(a));
  for i := 0 to High(a) do
    AssertTrue('every entry is a file', not a[i].IsDir);
  AssertTrue('hidden dropped', not HasName(a, '.hidden'));
end;

procedure TFsReadDirTest.TestFoldersAndFilesReturnsAllVisible;
var
  a: TTyFsEntryArray;
begin
  a := TyFsReadDirectory(FRoot, '*', [fotFolders, fotFiles]);
  { 2 dirs + 5 visible files, hidden dropped }
  AssertEquals('all-visible count = 7', 7, Length(a));
  AssertEquals('2 of them are dirs', 2, CountDirs(a));
end;

procedure TFsReadDirTest.TestHiddenDroppedWithoutFotHidden;
var
  a: TTyFsEntryArray;
begin
  a := TyFsReadDirectory(FRoot, '*', [fotFolders, fotFiles]);
  AssertTrue('.hidden absent without fotHidden', not HasName(a, '.hidden'));
end;

procedure TFsReadDirTest.TestHiddenKeptWithFotHidden;
var
  a: TTyFsEntryArray;
  idx: Integer;
begin
  a := TyFsReadDirectory(FRoot, '*', [fotFolders, fotFiles, fotHidden]);
  { 2 dirs + 5 visible files + 1 hidden file }
  AssertEquals('count with hidden = 8', 8, Length(a));
  idx := IndexOfName(a, '.hidden');
  AssertTrue('.hidden present with fotHidden', idx >= 0);
  AssertTrue('.hidden reports IsHidden', a[idx].IsHidden);
end;

procedure TFsReadDirTest.TestVisibleEntriesNotHidden;
var
  a: TTyFsEntryArray;
  idx: Integer;
begin
  a := TyFsReadDirectory(FRoot, '*', [fotFolders, fotFiles]);
  idx := IndexOfName(a, 'a.txt');
  AssertTrue('a.txt enumerated', idx >= 0);
  AssertTrue('a.txt not hidden', not a[idx].IsHidden);
end;

procedure TFsReadDirTest.TestMaskFiltersFilesDirsAlwaysShown;
var
  a: TTyFsEntryArray;
begin
  a := TyFsReadDirectory(FRoot, '*.txt;*.md', [fotFolders, fotFiles]);
  { dirs always shown (2) + files matching txt/md (a.txt, b.md) = 4 }
  AssertEquals('masked count = 4', 4, Length(a));
  AssertTrue('sub_a shown despite mask', HasName(a, 'sub_a'));
  AssertTrue('sub_b shown despite mask', HasName(a, 'sub_b'));
  AssertTrue('a.txt matches', HasName(a, 'a.txt'));
  AssertTrue('b.md matches', HasName(a, 'b.md'));
  AssertTrue('big.dat excluded', not HasName(a, 'big.dat'));
  AssertTrue('photo.png excluded', not HasName(a, 'photo.png'));
end;

procedure TFsReadDirTest.TestSingleExtensionMask;
var
  a: TTyFsEntryArray;
begin
  a := TyFsReadDirectory(FRoot, '*.dat', [fotFolders, fotFiles]);
  { 2 dirs + big.dat = 3 }
  AssertEquals('single-ext masked count = 3', 3, Length(a));
  AssertTrue('big.dat matches', HasName(a, 'big.dat'));
  AssertTrue('a.txt excluded', not HasName(a, 'a.txt'));
end;

procedure TFsReadDirTest.TestStarDotStarMaskIsAll;
var
  a: TTyFsEntryArray;
begin
  a := TyFsReadDirectory(FRoot, '*.*', [fotFolders, fotFiles]);
  AssertEquals('*.* == all visible = 7', 7, Length(a));
end;

procedure TFsReadDirTest.TestEmptyMaskIsAll;
var
  a: TTyFsEntryArray;
begin
  a := TyFsReadDirectory(FRoot, '', [fotFolders, fotFiles]);
  AssertEquals('empty mask == all visible = 7', 7, Length(a));
end;

procedure TFsReadDirTest.TestSizeFieldReflectsBytes;
var
  a: TTyFsEntryArray;
  idx: Integer;
begin
  a := TyFsReadDirectory(FRoot, '*.dat', [fotFiles]);
  idx := IndexOfName(a, 'big.dat');
  AssertTrue('big.dat enumerated', idx >= 0);
  AssertEquals('Size = written byte count', Int64(5000), a[idx].Size);
end;

procedure TFsReadDirTest.TestDirEntryFieldsConsistent;
var
  a: TTyFsEntryArray;
  idx: Integer;
begin
  a := TyFsReadDirectory(FRoot, '*', [fotFolders]);
  idx := IndexOfName(a, 'sub_a');
  AssertTrue('sub_a enumerated', idx >= 0);
  AssertTrue('sub_a IsDir', a[idx].IsDir);
  AssertTrue('sub_a FullPath points at a real directory',
    DirectoryExistsUTF8(a[idx].FullPath));
end;

procedure TFsReadDirTest.TestUnicodeNameRoundTrip;
var
  a: TTyFsEntryArray;
  idx: Integer;
begin
  a := TyFsReadDirectory(FRoot, '*', [fotFiles]);
  idx := IndexOfName(a, FUnicodeName);
  AssertTrue('unicode-named file enumerated back', idx >= 0);
  AssertEquals('enumerated Name matches bytes written', FUnicodeName, a[idx].Name);
end;

{ ===========================================================================
  TFsMatchTest
  =========================================================================== }

procedure TFsMatchTest.TestSingleExtensionMatch;
begin
  AssertTrue('a.txt matches *.txt',
    TyFsMatchesFilter('a.txt', '*.txt', False));
end;

procedure TFsMatchTest.TestSemicolonListMatch;
begin
  AssertTrue('a.txt matches *.txt;*.md',
    TyFsMatchesFilter('a.txt', '*.txt;*.md', False));
  AssertTrue('b.md matches *.txt;*.md',
    TyFsMatchesFilter('b.md', '*.txt;*.md', False));
end;

procedure TFsMatchTest.TestStarDotStarMatchesNoExtensionName;
begin
  { '*.*' is normalised to '*', so a name with no dot must still match }
  AssertTrue('README matches *.*',
    TyFsMatchesFilter('README', '*.*', False));
end;

procedure TFsMatchTest.TestEmptyPatternMatchesEverything;
begin
  AssertTrue('README matches empty pattern',
    TyFsMatchesFilter('README', '', False));
end;

procedure TFsMatchTest.TestNonMatchReturnsFalse;
begin
  AssertTrue('big.dat does not match *.txt',
    not TyFsMatchesFilter('big.dat', '*.txt', False));
end;

procedure TFsMatchTest.TestCaseInsensitiveMatch;
begin
  { case-insensitive request: differing letter case still matches }
  AssertTrue('A.TXT matches *.txt case-insensitively',
    TyFsMatchesFilter('A.TXT', '*.txt', False));
end;

procedure TFsMatchTest.TestFooDotStarQuirk;
begin
  { file-dialog convention: 'report.*' matches a name with no extension }
  AssertTrue('report matches report.*',
    TyFsMatchesFilter('report', 'report.*', False));
end;

{ ===========================================================================
  TFsFilterParseTest
  =========================================================================== }

procedure TFsFilterParseTest.TestTwoSegmentFilter;
var
  s: TTyFsFilterSpecArray;
begin
  s := TyFsParseFilter('Text files (*.txt)|*.txt|All files (*.*)|*.*');
  AssertEquals('2 specs', 2, Length(s));
  AssertEquals('spec0 caption', 'Text files (*.txt)', s[0].Caption);
  AssertEquals('spec0 patterns', '*.txt', s[0].Patterns);
  AssertEquals('spec1 caption', 'All files (*.*)', s[1].Caption);
  AssertEquals('spec1 patterns', '*.*', s[1].Patterns);
end;

procedure TFsFilterParseTest.TestThreeSegmentFilter;
var
  s: TTyFsFilterSpecArray;
begin
  s := TyFsParseFilter('Images|*.png;*.jpg|Documents|*.pdf|All|*.*');
  AssertEquals('3 specs', 3, Length(s));
  AssertEquals('spec0 caption', 'Images', s[0].Caption);
  AssertEquals('spec0 patterns kept whole', '*.png;*.jpg', s[0].Patterns);
  AssertEquals('spec1 caption', 'Documents', s[1].Caption);
  AssertEquals('spec1 patterns', '*.pdf', s[1].Patterns);
  AssertEquals('spec2 caption', 'All', s[2].Caption);
  AssertEquals('spec2 patterns', '*.*', s[2].Patterns);
end;

procedure TFsFilterParseTest.TestFilterPatternsOneBased;
const
  F = 'Text files (*.txt)|*.txt|All files (*.*)|*.*';
begin
  AssertEquals('index 1 -> first patterns', '*.txt', TyFsFilterPatterns(F, 1));
  AssertEquals('index 2 -> second patterns', '*.*', TyFsFilterPatterns(F, 2));
end;

procedure TFsFilterParseTest.TestFilterPatternsClampLow;
const
  F = 'Text files (*.txt)|*.txt|All files (*.*)|*.*';
begin
  AssertEquals('index 0 clamps to first', '*.txt', TyFsFilterPatterns(F, 0));
end;

procedure TFsFilterParseTest.TestFilterPatternsClampHigh;
const
  F = 'Text files (*.txt)|*.txt|All files (*.*)|*.*';
begin
  AssertEquals('index 99 clamps to last', '*.*', TyFsFilterPatterns(F, 99));
end;

procedure TFsFilterParseTest.TestMalformedFilterNoCrash;
var
  s: TTyFsFilterSpecArray;
begin
  { odd segment count — must not crash; the leading complete pair survives }
  s := TyFsParseFilter('Text|*.txt|Orphan');
  AssertTrue('at least the first pair parsed', Length(s) >= 1);
  AssertEquals('first caption', 'Text', s[0].Caption);
  AssertEquals('first patterns', '*.txt', s[0].Patterns);
end;

procedure TFsFilterParseTest.TestEmptyFilterNoCrash;
var
  s: TTyFsFilterSpecArray;
begin
  s := TyFsParseFilter('');
  AssertEquals('empty filter -> 0 specs', 0, Length(s));
end;

{ ===========================================================================
  TFsCompareSortTest
  =========================================================================== }

function TFsCompareSortTest.MkEntry(const AName: string; AIsDir: Boolean;
  ASize: Int64; AModified: TDateTime): TTyFsEntry;
begin
  Result := Default(TTyFsEntry);
  Result.Name := AName;
  Result.FullPath := AName;
  Result.IsDir := AIsDir;
  Result.IsHidden := False;
  Result.Size := ASize;
  Result.Modified := AModified;
  Result.Attr := 0;
  Result.TypeName := '';
end;

procedure TFsCompareSortTest.TestFoldersBeforeFilesAscending;
var
  d, f: TTyFsEntry;
begin
  d := MkEntry('zzz', True, 0, 0);   { dir, name sorts LAST }
  f := MkEntry('aaa', False, 0, 0);  { file, name sorts FIRST }
  { folders-first must beat the name key: dir before file -> negative }
  AssertTrue('dir before file (asc)',
    TyFsCompareEntries(d, f, fskName, True, True) < 0);
end;

procedure TFsCompareSortTest.TestFoldersBeforeFilesDescending;
var
  d, f: TTyFsEntry;
begin
  d := MkEntry('aaa', True, 0, 0);
  f := MkEntry('zzz', False, 0, 0);
  { direction must NOT flip the folder-first rule: dir still before file }
  AssertTrue('dir before file (desc)',
    TyFsCompareEntries(d, f, fskName, False, True) < 0);
end;

procedure TFsCompareSortTest.TestFoldersFirstFalseUsesKey;
var
  d, f: TTyFsEntry;
begin
  d := MkEntry('zzz', True, 0, 0);
  f := MkEntry('aaa', False, 0, 0);
  { AFoldersFirst=False -> name key decides: 'aaa' < 'zzz' so file before dir }
  AssertTrue('file before dir when folders-first off',
    TyFsCompareEntries(d, f, fskName, True, False) > 0);
end;

procedure TFsCompareSortTest.TestNameAscendingThenDescending;
var
  a, b: TTyFsEntry;
begin
  a := MkEntry('apple', False, 0, 0);
  b := MkEntry('banana', False, 0, 0);
  AssertTrue('apple < banana ascending',
    TyFsCompareEntries(a, b, fskName, True, True) < 0);
  AssertTrue('apple > banana descending',
    TyFsCompareEntries(a, b, fskName, False, True) > 0);
end;

procedure TFsCompareSortTest.TestSizeComparedAsInt64;
var
  a, b: TTyFsEntry;
begin
  { b's size exceeds 32-bit MaxInt; a naive 32-bit compare would misorder }
  a := MkEntry('a', False, 100, 0);
  b := MkEntry('b', False, Int64(5000000000), 0);
  AssertTrue('100 < 5e9 ascending',
    TyFsCompareEntries(a, b, fskSize, True, True) < 0);
  AssertTrue('100 > 5e9 descending',
    TyFsCompareEntries(a, b, fskSize, False, True) > 0);
end;

procedure TFsCompareSortTest.TestModifiedComparedAsDateTime;
var
  a, b: TTyFsEntry;
begin
  a := MkEntry('a', False, 0, EncodeDate(2020, 1, 1));
  b := MkEntry('b', False, 0, EncodeDate(2021, 1, 1));
  AssertTrue('2020 < 2021 ascending',
    TyFsCompareEntries(a, b, fskModified, True, True) < 0);
end;

procedure TFsCompareSortTest.TestNameFollowsOSCaseRule;
var
  a, b: TTyFsEntry;
begin
  a := MkEntry('a.txt', False, 0, 0);
  b := MkEntry('A.TXT', False, 0, 0);
  {$IFDEF MSWINDOWS}
  AssertEquals('case-insensitive equal on Windows',
    0, TyFsCompareEntries(a, b, fskName, True, True));
  {$ELSE}
  AssertTrue('case-sensitive distinct on Unix',
    TyFsCompareEntries(a, b, fskName, True, True) <> 0);
  {$ENDIF}
end;

procedure TFsCompareSortTest.TestSortFoldersFirstNameAscending;
var
  arr: TTyFsEntryArray;
begin
  SetLength(arr, 4);
  arr[0] := MkEntry('banana', False, 0, 0);
  arr[1] := MkEntry('zoo', True, 0, 0);
  arr[2] := MkEntry('apple', False, 0, 0);
  arr[3] := MkEntry('alpha', True, 0, 0);
  TyFsSortEntries(arr, fskName, True, True);
  { dirs first, name-ascending: alpha, zoo ; then files: apple, banana }
  AssertEquals('pos0 = alpha (dir)', 'alpha', arr[0].Name);
  AssertEquals('pos1 = zoo (dir)', 'zoo', arr[1].Name);
  AssertEquals('pos2 = apple (file)', 'apple', arr[2].Name);
  AssertEquals('pos3 = banana (file)', 'banana', arr[3].Name);
end;

procedure TFsCompareSortTest.TestSortFoldersFirstNameDescending;
var
  arr: TTyFsEntryArray;
begin
  SetLength(arr, 4);
  arr[0] := MkEntry('banana', False, 0, 0);
  arr[1] := MkEntry('zoo', True, 0, 0);
  arr[2] := MkEntry('apple', False, 0, 0);
  arr[3] := MkEntry('alpha', True, 0, 0);
  TyFsSortEntries(arr, fskName, False, True);
  { dirs still first; within groups descending: zoo, alpha ; banana, apple }
  AssertTrue('pos0/1 are the dirs', arr[0].IsDir and arr[1].IsDir);
  AssertEquals('pos0 = zoo (dir, desc)', 'zoo', arr[0].Name);
  AssertEquals('pos1 = alpha (dir, desc)', 'alpha', arr[1].Name);
  AssertEquals('pos2 = banana (file, desc)', 'banana', arr[2].Name);
  AssertEquals('pos3 = apple (file, desc)', 'apple', arr[3].Name);
end;

{ ===========================================================================
  TFsResolveTest
  =========================================================================== }

procedure TFsResolveTest.SetUp;
begin
  FDir := ChompPathDelim(AppendPathDelim(GetTempDir) + 'tyfs_test_resolve');
  if DirectoryExistsUTF8(FDir) then
    DeleteDirectory(FDir, False);
  ForceDirectoriesUTF8(FDir);
end;

procedure TFsResolveTest.TearDown;
begin
  if (FDir <> '') and DirectoryExistsUTF8(FDir) then
    DeleteDirectory(FDir, False);
end;

procedure TFsResolveTest.TestBareNameGetsDefaultExtInDir;
var
  r: string;
begin
  r := TyFsResolveSaveName(FDir, 'report', '.txt');
  { DefaultExt appended to the bare name }
  AssertEquals('bare name gains DefaultExt', 'report.txt', ExtractFileName(r));
  { expanded against ADir: the directory portion is a real, existing directory }
  AssertTrue('result carries a directory', ExtractFileDir(r) <> '');
  AssertTrue('resolved directory exists (expanded against ADir)',
    DirectoryExistsUTF8(ExtractFileDir(r)));
end;

procedure TFsResolveTest.TestExistingExtensionUntouched;
var
  r: string;
begin
  r := TyFsResolveSaveName(FDir, 'data.csv', '.txt');
  AssertEquals('existing .csv kept, DefaultExt not applied',
    'data.csv', ExtractFileName(r));
end;

procedure TFsResolveTest.TestDifferentExistingExtensionUntouched;
var
  r: string;
begin
  r := TyFsResolveSaveName(FDir, 'archive.tar', '.zip');
  AssertEquals('own extension survives a different DefaultExt',
    'archive.tar', ExtractFileName(r));
end;

{ ===========================================================================
  TFsRootsTest
  =========================================================================== }

procedure TFsRootsTest.TestReturnsAtLeastOneRoot;
var
  r: TTyFsRootArray;
begin
  r := TyFsRoots;
  AssertTrue('at least one root', Length(r) >= 1);
end;

procedure TFsRootsTest.TestNoRootHasEmptyPath;
var
  r: TTyFsRootArray;
  i: Integer;
begin
  r := TyFsRoots;
  for i := 0 to High(r) do
    AssertTrue(Format('root %d has a Path', [i]), r[i].Path <> '');
end;

procedure TFsRootsTest.TestOSExpectedKindPresent;
var
  r: TTyFsRootArray;
  i: Integer;
  {$IFDEF MSWINDOWS}
  hasDrive: Boolean;
  {$ELSE}
  hasRoot, hasHome: Boolean;
  {$ENDIF}
begin
  r := TyFsRoots;
  {$IFDEF MSWINDOWS}
  hasDrive := False;
  for i := 0 to High(r) do
    if r[i].Kind = rkDrive then
      hasDrive := True;
  AssertTrue('Windows roots include a drive', hasDrive);
  {$ELSE}
  hasRoot := False;
  hasHome := False;
  for i := 0 to High(r) do
  begin
    if r[i].Kind = rkRoot then hasRoot := True;
    if r[i].Kind = rkHome then hasHome := True;
  end;
  AssertTrue('Unix roots include the filesystem root', hasRoot);
  AssertTrue('Unix roots include home', hasHome);
  {$ENDIF}
end;

{ ===========================================================================
  TFsPathTest
  =========================================================================== }

procedure TFsPathTest.SetUp;
begin
  FRoot := ChompPathDelim(AppendPathDelim(GetTempDir) + 'tyfs_test_path');
  if DirectoryExistsUTF8(FRoot) then
    DeleteDirectory(FRoot, False);
  FSub := AppendPathDelim(FRoot) + 'child';
  ForceDirectoriesUTF8(FSub);
end;

procedure TFsPathTest.TearDown;
begin
  if (FRoot <> '') and DirectoryExistsUTF8(FRoot) then
    DeleteDirectory(FRoot, False);
end;

procedure TFsPathTest.TestParentOfSubIsRoot;
var
  p: string;
begin
  p := TyFsParent(FSub);
  AssertEquals('parent of child is root',
    0, CompareFilenames(ChompPathDelim(p), ChompPathDelim(FRoot)));
end;

procedure TFsPathTest.TestBreadcrumbNonEmpty;
var
  b: TStringArray;
begin
  b := TyFsBreadcrumb(FSub);
  AssertTrue('breadcrumb is non-empty', Length(b) >= 1);
end;

{ The crumbs are the cumulative ancestor PATHS, not display labels -- a look-in combo
  navigates to each. These use literal paths, so they pin the shape on any host. }

procedure TFsPathTest.TestBreadcrumbCumulativePathsUnix;
var
  b: TStringArray;
begin
  b := TyFsBreadcrumb('/home/tom');
  AssertEquals('3 crumbs', 3, Length(b));
  AssertEquals('crumb 0 is the root', '/', b[0]);
  AssertEquals('crumb 1 is /home', '/home', b[1]);
  AssertEquals('crumb 2 is the full path', '/home/tom', b[2]);
end;

procedure TFsPathTest.TestBreadcrumbCumulativePathsWindows;
var
  b: TStringArray;
begin
  b := TyFsBreadcrumb('C:\Users\Tom');
  AssertEquals('3 crumbs', 3, Length(b));
  AssertEquals('drive root keeps its separator', 'C:\', b[0]);
  AssertEquals('crumb 1 has no trailing separator', 'C:\Users', b[1]);
  AssertEquals('crumb 2 is the full path', 'C:\Users\Tom', b[2]);
end;

procedure TFsPathTest.TestBreadcrumbRootAlone;
var
  u, w: TStringArray;
begin
  u := TyFsBreadcrumb('/');
  AssertEquals('a bare unix root is one crumb', 1, Length(u));
  AssertEquals('and it is /', '/', u[0]);
  w := TyFsBreadcrumb('C:\');
  AssertEquals('a bare drive root is one crumb', 1, Length(w));
  AssertEquals('and it keeps the separator', 'C:\', w[0]);
end;

procedure TFsPathTest.TestBreadcrumbEmptyPath;
begin
  AssertEquals('empty path -> empty array', 0, Length(TyFsBreadcrumb('')));
end;

procedure TFsPathTest.TestTypeNameNonEmpty;
var
  eFile, eDir: TTyFsEntry;
begin
  eFile := Default(TTyFsEntry);
  eFile.Name := 'a.txt';
  eFile.FullPath := AppendPathDelim(FRoot) + 'a.txt';
  eFile.IsDir := False;

  eDir := Default(TTyFsEntry);
  eDir.Name := 'child';
  eDir.FullPath := FSub;
  eDir.IsDir := True;

  AssertTrue('file TypeName non-empty', TyFsTypeName(eFile) <> '');
  AssertTrue('dir TypeName non-empty', TyFsTypeName(eDir) <> '');
end;

initialization
  RegisterTest(TFsReadDirTest);
  RegisterTest(TFsMatchTest);
  RegisterTest(TFsFilterParseTest);
  RegisterTest(TFsCompareSortTest);
  RegisterTest(TFsResolveTest);
  RegisterTest(TFsRootsTest);
  RegisterTest(TFsPathTest);
end.
