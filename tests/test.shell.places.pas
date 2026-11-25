unit test.shell.places;
{$mode objfpc}{$H+}

{ #245: the user's common folders -- Desktop, Documents, Downloads, Pictures, Music, Videos --
  as places of the file dialogs: where the library finds them on each platform, and how the
  folder tree and the folder drop-down list them.

  What can be checked without the machine's own folders is checked that way: the parser of
  the XDG user-dirs file is pure, the filter takes folders made for the test, and the tree
  and the drop-down are handed places made for the test (their source is a virtual method).
  What cannot -- the Windows answer -- is held against a second source the shell keeps, the
  "User Shell Folders" registry key. }

interface

uses
  { Windows first: listed later it would put its own TBitmap and Rect in front of the LCL's. }
  {$IFDEF MSWINDOWS}Windows, Registry,{$ENDIF}
  Classes, SysUtils, Types, Graphics, Forms, Controls, fpcunit, testregistry, LazFileUtils,
  FileUtil, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.ListBox,
  tyControls.FileSystem, tyControls.StrConsts, tyControls.TreeView, tyControls.ShellTreeView,
  tyControls.ShellComboBox, tyControls.Dialogs.FileDialog;

type
  TFsPlacesTest = class(TTestCase)
  private
    FTemp: string;
    function Dir(const AName: string): string;        // made under FTemp
    function Names(const A: TTyFsRootArray): string;  // the Display names, blank-joined
    function Find(const A: TTyFsRootArray; const ADisplay: string): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { the XDG user-dirs file }
    procedure TheUserDirsFileGivesTheFoldersInOneFixedOrder;
    procedure AFolderPointedAtTheHomeDirectoryItselfIsSwitchedOff;
    procedure AnAbsolutePathAndANameInAnyScriptAreKept;
    procedure ALineThatIsNotAQuotedPathIsSkipped;
    { what is listed }
    procedure OnlyFoldersThatExistAreListedAndEachOnce;
    procedure TheKnownFoldersOfThisMachineExistAndAreNamed;
    {$IFDEF MSWINDOWS}
    procedure TheKnownFoldersAreWhereTheShellKeepsThem;
    procedure TheDownloadsFolderIsAskedOfTheShellNotGuessed;
    {$ENDIF}
    procedure ThePlacesAreTheKnownFoldersAndThenTheRoots;
  end;

  { A tree whose top level is what the test says: two places and one "drive", all folders
    made for the test, the places INSIDE the drive -- as Documents is inside C:. }
  TPlacesTree = class(TTyShellTreeView)
  protected
    function TopLevelPlaces: TTyFsRootArray; override;
  public
    Given: TTyFsRootArray;
    UseGiven: Boolean;
    function Top(AIndex: Integer): PTyTreeNode;
    function TopOf(ANode: PTyTreeNode): PTyTreeNode;
    function TextOf(ANode: PTyTreeNode): string;
    function GlyphOf(ANode: PTyTreeNode): Integer;
    function PathOf(ANode: PTyTreeNode): string;
    function ChildNamed(AParent: PTyTreeNode; const AName: string): PTyTreeNode;
  end;

  TShellTreePlacesTest = class(TTestCase)
  private
    FTemp, FDrive, FDocs, FDesk: string;
    FForm: TForm;
    function NewTree: TPlacesTree;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ThePlacesAreListedFirstUnderTheirNames;
    procedure APlaceShowsAFolderAndARootItsDrive;
    procedure APlaceExpandsLikeAnyFolder;
    procedure TheSameFolderInsideARootKeepsItsOwnName;
    procedure APathInsideAPlaceIsShownUnderThePlace;
    procedure TheSwitchIsOffUntilItIsAskedFor;
    procedure TurningTheSwitchKeepsTheFolderTheTreeIsIn;
    procedure AScopedTreeIsLeftAsItIs;
  end;

  TPlacesCombo = class(TTyShellComboBox)
  protected
    function KnownFolders: TTyFsRootArray; override;
  public
    Given: TTyFsRootArray;
    UseGiven: Boolean;
    procedure Pick(AIndex: Integer);
    function Caption0: string;   // what the closed field shows
    { How much of the two glyph colours the drop-down DRAWS on row ARow: the folder's amber
      and the drive's steel blue. }
    procedure RowGlyphInk(ARow: Integer; out AFolder, ADrive: Integer);
    { The rightmost column of the closed field's own paint that holds text ink. }
    function FieldInkRight: Integer;
  end;

  TLookInPlacesTest = class(TTestCase)
  private
    FTemp: string;
    FForm: TForm;
    FPicks: Integer;
    function Folders: TTyFsRootArray;
    procedure Picked(Sender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TheRowsAreThePathThenTheFoldersThenTheOtherRoots;
    procedure WithoutFoldersTheRowsAreWhatTheyWere;
    procedure AFolderRowShowsAFolderAndARootItsDrive;
    procedure TheDropDownDrawsAFolderRowWithTheFolderGlyph;
    procedure PickingAFolderGoesThereAndTheFieldSaysItsName;
    procedure TheFieldDrawsThePlacesName;
    procedure TheSwitchIsOffUntilItIsAskedFor;
    procedure TheFileDialogsTurnBothSwitchesOn;
    procedure AtTheRootOfADriveTheDriveIsListedOnce;
  end;

implementation

type
  { 4.0 does not publish the tree's RootNodeCount (#192); it is still there to be counted. }
  TTreeCount = class(TTyCustomShellTreeView);

procedure TFsPlacesTest.SetUp;
begin
  FTemp := ChompPathDelim(AppendPathDelim(GetTempDir) + 'typlaces_' + IntToStr(GetProcessID)
    + '_' + IntToStr(Random(1000000)));
  ForceDirectoriesUTF8(FTemp);
end;

procedure TFsPlacesTest.TearDown;
begin
  if (FTemp <> '') and DirectoryExistsUTF8(FTemp) then
    DeleteDirectory(FTemp, False);
end;

function TFsPlacesTest.Dir(const AName: string): string;
begin
  Result := AppendPathDelim(FTemp) + AName;
  ForceDirectoriesUTF8(Result);
end;

function TFsPlacesTest.Names(const A: TTyFsRootArray): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(A) do
  begin
    if i > 0 then Result := Result + ' ';
    Result := Result + A[i].Display;
  end;
end;

function TFsPlacesTest.Find(const A: TTyFsRootArray; const ADisplay: string): Integer;
var
  i: Integer;
begin
  for i := 0 to High(A) do
    if A[i].Display = ADisplay then Exit(i);
  Result := -1;
end;

{ --- the XDG user-dirs file ---------------------------------------------------------- }

procedure TFsPlacesTest.TheUserDirsFileGivesTheFoldersInOneFixedOrder;
var
  r: TTyFsRootArray;
  i: Integer;
const
  { As xdg-user-dirs writes it, but out of order, with the two keys the dialogs do not list. }
  cFile =
    '# This file is written by xdg-user-dirs-update'#10 +
    '# If you want to change or add directories, just edit the line you''re'#10 +
    'XDG_VIDEOS_DIR="$HOME/Videos"'#10 +
    'XDG_TEMPLATES_DIR="$HOME/Templates"'#10 +
    'XDG_MUSIC_DIR="$HOME/Music"'#10 +
    'XDG_DOWNLOAD_DIR="$HOME/Downloads"'#10 +
    'XDG_PUBLICSHARE_DIR="$HOME/Public"'#10 +
    'XDG_PICTURES_DIR="$HOME/Pictures"'#10 +
    'XDG_DESKTOP_DIR="$HOME/Desktop"'#10 +
    'XDG_DOCUMENTS_DIR="$HOME/Documents"'#10;
begin
  r := TyFsParseUserDirs(cFile, '/home/tom');
  AssertEquals('six folders, whatever order the file has them in',
    rsFdPlaceDesktop + ' ' + rsFdPlaceDocuments + ' ' + rsFdPlaceDownloads + ' '
    + rsFdPlacePictures + ' ' + rsFdPlaceMusic + ' ' + rsFdPlaceVideos, Names(r));
  AssertEquals('$HOME is the home directory given', '/home/tom/Desktop', r[0].Path);
  AssertEquals('each key to its own folder', '/home/tom/Downloads', r[2].Path);
  AssertEquals('to the last', '/home/tom/Videos', r[5].Path);
  for i := 0 to High(r) do
    AssertTrue('each is a place', r[i].Kind = rkPlace);
end;

procedure TFsPlacesTest.AFolderPointedAtTheHomeDirectoryItselfIsSwitchedOff;
var
  r: TTyFsRootArray;
begin
  { xdg-user-dirs' way of saying "this user has no such folder": the home directory itself. }
  r := TyFsParseUserDirs(
    'XDG_DESKTOP_DIR="$HOME/"'#10 +
    'XDG_DOCUMENTS_DIR="$HOME"'#10 +
    'XDG_MUSIC_DIR="$HOME/Music"'#10, '/home/tom');
  AssertEquals('only the one that names a folder of its own', rsFdPlaceMusic, Names(r));
end;

procedure TFsPlacesTest.AnAbsolutePathAndANameInAnyScriptAreKept;
var
  r: TTyFsRootArray;
begin
  r := TyFsParseUserDirs(
    'XDG_DOCUMENTS_DIR="/data/docs"'#10 +
    'XDG_DOWNLOAD_DIR="$HOME/下载"'#10 +
    'XDG_PICTURES_DIR="$HOME/My \"best\" pictures"'#13#10 +     // a CR LF file, an escaped quote
    'XDG_DESKTOP_DIR="$HOME/Рабочий стол"'#10, '/home/tom/');
  AssertEquals('all four', 4, Length(r));
  AssertEquals('a home directory given with its delimiter joins once',
    '/home/tom/Рабочий стол', r[0].Path);
  AssertEquals('an absolute path is the path', '/data/docs', r[1].Path);
  AssertEquals('a localized name is the name', '/home/tom/下载', r[2].Path);
  AssertEquals('an escaped quote is a quote', '/home/tom/My "best" pictures', r[3].Path);
end;

procedure TFsPlacesTest.ALineThatIsNotAQuotedPathIsSkipped;
var
  r: TTyFsRootArray;
begin
  r := TyFsParseUserDirs(
    'XDG_DESKTOP_DIR=$HOME/Desktop'#10 +            // not quoted
    'XDG_DOCUMENTS_DIR="Documents"'#10 +            // neither $HOME/... nor absolute
    '  # XDG_MUSIC_DIR="$HOME/Music"'#10 +          // a comment
    'XDG_PICTURES_DIR="$HOME/Pictures'#10 +         // the quote never closes
    'XDG_MUSIC_DIR=x/music"'#10 +                   // does not open with a quote, though one follows
    'XDG_VIDEOS_DIR = "$HOME/Videos"'#10 +          // blanks around the sign: still an assignment
    'MUSIC="$HOME/Music"'#10, '/home/tom');         // not one of the keys
  AssertEquals('only the well-formed assignment', rsFdPlaceVideos, Names(r));
  AssertEquals(0, Length(TyFsParseUserDirs('', '/home/tom')));
end;

{ --- what is listed ------------------------------------------------------------------ }

procedure TFsPlacesTest.OnlyFoldersThatExistAreListedAndEachOnce;
var
  c, r: TTyFsRootArray;
begin
  c := nil;
  SetLength(c, 4);
  c[0].Path := AppendPathDelim(Dir('Desk'));  c[0].Display := 'A'; c[0].Kind := rkPlace;
  c[1].Path := AppendPathDelim(FTemp) + 'gone'; c[1].Display := 'B'; c[1].Kind := rkPlace;
  c[2].Path := Dir('Docs');                   c[2].Display := 'C'; c[2].Kind := rkPlace;
  c[3].Path := Dir('Desk');                   c[3].Display := 'D'; c[3].Kind := rkPlace;   // the first again
  r := TyFsExistingPlaces(c);
  AssertEquals('the missing one and the repeat are left out, the order kept', 'A C', Names(r));
  AssertEquals('paths carry no trailing delimiter', AppendPathDelim(FTemp) + 'Desk', r[0].Path);
end;

procedure TFsPlacesTest.TheKnownFoldersOfThisMachineExistAndAreNamed;
var
  r: TTyFsRootArray;
  i, j, at, last: Integer;
  order: array[0..5] of string;
begin
  order[0] := rsFdPlaceDesktop;  order[1] := rsFdPlaceDocuments; order[2] := rsFdPlaceDownloads;
  order[3] := rsFdPlacePictures; order[4] := rsFdPlaceMusic;     order[5] := rsFdPlaceVideos;
  r := TyFsKnownFolders;
  last := -1;
  for i := 0 to High(r) do
  begin
    AssertTrue('exists: ' + r[i].Path, DirectoryExistsUTF8(r[i].Path));
    AssertTrue('a place', r[i].Kind = rkPlace);
    at := -1;
    for j := 0 to 5 do
      if r[i].Display = order[j] then at := j;
    AssertTrue('named as one of the six: ' + r[i].Display, at >= 0);
    AssertTrue('in the fixed order', at > last);
    last := at;
    for j := 0 to i - 1 do
      AssertFalse('each folder once', SameFileName(r[j].Path, r[i].Path));
  end;
end;

{$IFDEF MSWINDOWS}
procedure TFsPlacesTest.TheKnownFoldersAreWhereTheShellKeepsThem;
var
  reg: TRegistry;
  r: TTyFsRootArray;
  checked: Integer;

  { The folder the shell has on record under AValue, '' when it keeps none there. }
  function OnRecord(const AValue: string): string;
  var
    raw: UnicodeString;
    buf: array[0..1023] of WideChar;
  begin
    Result := '';
    if not reg.ValueExists(AValue) then Exit;
    raw := UTF8Decode(reg.ReadString(AValue));
    if raw = '' then Exit;
    if ExpandEnvironmentStringsW(PWideChar(raw), @buf[0], Length(buf)) = 0 then Exit;
    Result := ChompPathDelim(UTF8Encode(UnicodeString(PWideChar(@buf[0]))));
  end;

  procedure Check(const AValue, ADisplay: string);
  var
    want: string;
    i: Integer;
  begin
    want := OnRecord(AValue);
    if (want = '') or not DirectoryExistsUTF8(want) then Exit;   // this profile has none
    i := Find(r, ADisplay);
    AssertTrue(ADisplay + ' is listed', i >= 0);
    AssertTrue(Format('%s is "%s", as the shell has it; got "%s"', [ADisplay, want, r[i].Path]),
      SameFileName(want, r[i].Path));
    Inc(checked);
  end;

begin
  r := TyFsKnownFolders;
  checked := 0;
  reg := TRegistry.Create(KEY_READ);
  try
    reg.RootKey := HKEY_CURRENT_USER;
    AssertTrue('precondition: the shell''s own record can be read', reg.OpenKeyReadOnly(
      'Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'));
    Check('Desktop', rsFdPlaceDesktop);
    Check('Personal', rsFdPlaceDocuments);
    Check('{374DE290-123F-4565-9164-39C4925E467B}', rsFdPlaceDownloads);
    Check('My Pictures', rsFdPlacePictures);
    Check('My Music', rsFdPlaceMusic);
    Check('My Video', rsFdPlaceVideos);
  finally
    reg.Free;
  end;
  AssertTrue('precondition: this profile has at least the desktop and the documents on record',
    checked >= 2);
end;

procedure TFsPlacesTest.TheDownloadsFolderIsAskedOfTheShellNotGuessed;
var
  before, after: TTyFsRootArray;
  i, j: Integer;
  profile: UnicodeString;
  buf: array[0..1023] of WideChar;
begin
  { Downloads has no old-style folder number; where the newer call is missing the library
    falls back on <profile>\Downloads. On most machines that is the same folder, so the two
    ways cannot be told apart by their answer -- unless the profile variable points elsewhere
    for a moment: the shell does not read it, the fallback does. }
  before := TyFsKnownFolders;
  i := Find(before, rsFdPlaceDownloads);
  if i < 0 then Exit;   // this profile has no Downloads folder: nothing to tell apart
  FillChar(buf, SizeOf(buf), 0);
  GetEnvironmentVariableW('USERPROFILE', @buf[0], Length(buf));
  profile := UnicodeString(PWideChar(@buf[0]));
  SetEnvironmentVariableW('USERPROFILE', PWideChar(UTF8Decode(FTemp)));
  try
    after := TyFsKnownFolders;
  finally
    SetEnvironmentVariableW('USERPROFILE', PWideChar(profile));
  end;
  j := Find(after, rsFdPlaceDownloads);
  AssertTrue('still listed with the profile variable pointing at an empty folder', j >= 0);
  AssertTrue('and still the folder the shell has', SameFileName(before[i].Path, after[j].Path));
end;
{$ENDIF}

procedure TFsPlacesTest.ThePlacesAreTheKnownFoldersAndThenTheRoots;
var
  k, roots, p: TTyFsRootArray;
  i: Integer;
begin
  k := TyFsKnownFolders;
  roots := TyFsRoots;
  p := TyFsPlaces;
  AssertEquals('nothing lost, nothing added', Length(k) + Length(roots), Length(p));
  for i := 0 to High(k) do
    AssertEquals('the folders first, in their order', k[i].Path, p[i].Path);
  for i := 0 to High(roots) do
    AssertEquals('then the roots, in theirs', roots[i].Path, p[Length(k) + i].Path);
end;

{ ===================================================================== the tree == }

function TPlacesTree.TopLevelPlaces: TTyFsRootArray;
begin
  if UseGiven then Result := Given
  else Result := inherited TopLevelPlaces;
end;

function TPlacesTree.Top(AIndex: Integer): PTyTreeNode;
var
  i: Integer;
begin
  Result := GetFirst;
  for i := 1 to AIndex do
    if Result <> nil then Result := GetNextSibling(Result);
end;

function TPlacesTree.TopOf(ANode: PTyTreeNode): PTyTreeNode;
begin
  Result := ANode;
  while (Result <> nil) and (Result^.Parent <> RootNode) do
    Result := Result^.Parent;
end;

function TPlacesTree.TextOf(ANode: PTyTreeNode): string;
begin
  Result := '';
  DoGetText(ANode, Result);
end;

function TPlacesTree.GlyphOf(ANode: PTyTreeNode): Integer;
var
  ghosted: Boolean;
begin
  ghosted := False;
  Result := -1;
  DoGetImageIndex(ANode, ikNormal, 0, ghosted, Result);
end;

function TPlacesTree.PathOf(ANode: PTyTreeNode): string;
begin
  Result := NodePath(ANode);
end;

function TPlacesTree.ChildNamed(AParent: PTyTreeNode; const AName: string): PTyTreeNode;
begin
  Expanded[AParent] := True;
  Result := GetFirstChild(AParent);
  while Result <> nil do
  begin
    if SameFileName(ExtractFileName(NodePath(Result)), AName) then Exit;
    Result := GetNextSibling(Result);
  end;
end;

procedure TShellTreePlacesTest.SetUp;
begin
  FTemp := ChompPathDelim(AppendPathDelim(GetTempDir) + 'typlacetree_'
    + IntToStr(GetProcessID) + '_' + IntToStr(Random(1000000)));
  FDrive := AppendPathDelim(FTemp) + 'drive';
  FDocs := AppendPathDelim(FDrive) + 'Docs';
  FDesk := AppendPathDelim(FDrive) + 'Desk';
  ForceDirectoriesUTF8(AppendPathDelim(FDocs) + 'Sub');
  ForceDirectoriesUTF8(FDesk);
  ForceDirectoriesUTF8(AppendPathDelim(FDrive) + 'Other');
  FForm := TForm.CreateNew(nil);
end;

procedure TShellTreePlacesTest.TearDown;
begin
  FForm.Free;
  if (FTemp <> '') and DirectoryExistsUTF8(FTemp) then
    DeleteDirectory(FTemp, False);
end;

function TShellTreePlacesTest.NewTree: TPlacesTree;
begin
  Result := TPlacesTree.Create(FForm);
  Result.Parent := FForm;
  SetLength(Result.Given, 3);
  Result.Given[0].Path := FDocs;  Result.Given[0].Display := 'Documents'; Result.Given[0].Kind := rkPlace;
  Result.Given[1].Path := FDesk;  Result.Given[1].Display := 'Desktop';   Result.Given[1].Kind := rkPlace;
  Result.Given[2].Path := FDrive; Result.Given[2].Display := 'R:';        Result.Given[2].Kind := rkDrive;
  Result.UseGiven := True;
  Result.PopulateRoots;
end;

procedure TShellTreePlacesTest.ThePlacesAreListedFirstUnderTheirNames;
var
  t: TPlacesTree;
begin
  t := NewTree;
  AssertEquals('two places and the drive', 3, t.RootNodeCount);
  AssertEquals('a place is called by its name, not by its folder', 'Documents', t.TextOf(t.Top(0)));
  AssertEquals('the next place', 'Desktop', t.TextOf(t.Top(1)));
  AssertEquals('the drive after them, as it was shown', 'R:', t.TextOf(t.Top(2)));
  AssertTrue('and the place node is the folder', SameFileName(FDocs, t.PathOf(t.Top(0))));
end;

procedure TShellTreePlacesTest.APlaceShowsAFolderAndARootItsDrive;
var
  t: TPlacesTree;
begin
  t := NewTree;
  AssertEquals('a place: the folder glyph', TyShellTreeFolderGlyph, t.GlyphOf(t.Top(0)));
  AssertEquals('the other place too', TyShellTreeFolderGlyph, t.GlyphOf(t.Top(1)));
  AssertEquals('a drive: the drive glyph, as before', TyShellTreeDriveGlyph, t.GlyphOf(t.Top(2)));
end;

procedure TShellTreePlacesTest.APlaceExpandsLikeAnyFolder;
var
  t: TPlacesTree;
  sub: PTyTreeNode;
begin
  t := NewTree;
  sub := t.ChildNamed(t.Top(0), 'Sub');
  AssertTrue('the subfolder of the place is under it', sub <> nil);
  AssertEquals('under its own name', 'Sub', t.TextOf(sub));
end;

procedure TShellTreePlacesTest.TheSameFolderInsideARootKeepsItsOwnName;
var
  t: TPlacesTree;
  n: PTyTreeNode;
begin
  { Documents is also a folder somewhere under C:. Down there it is that folder: its own
    name, and no more a drive than its neighbours. }
  t := NewTree;
  n := t.ChildNamed(t.Top(2), 'Docs');
  AssertTrue('precondition: the place''s folder is found inside the drive', n <> nil);
  AssertTrue('precondition: it is the very folder the place names',
    SameFileName(FDocs, t.PathOf(n)));
  AssertEquals('its own name', 'Docs', t.TextOf(n));
  AssertEquals('a folder', TyShellTreeFolderGlyph, t.GlyphOf(n));
end;

procedure TShellTreePlacesTest.APathInsideAPlaceIsShownUnderThePlace;
var
  t: TPlacesTree;
begin
  t := NewTree;
  AssertTrue(t.SelectPath(AppendPathDelim(FDocs) + 'Sub'));
  AssertTrue('a folder inside a place is shown under the place',
    t.TopOf(t.FocusedNode) = t.Top(0));
  AssertTrue(t.SelectPath(FDocs));
  AssertTrue('the place''s own folder is the place', t.FocusedNode = t.Top(0));
  AssertTrue(t.SelectPath(AppendPathDelim(FDrive) + 'Other'));
  AssertTrue('a folder outside every place is shown under its drive',
    t.TopOf(t.FocusedNode) = t.Top(2));
end;

procedure TShellTreePlacesTest.TheSwitchIsOffUntilItIsAskedFor;
var
  t: TTyShellTreeView;
  known: TTyFsRootArray;
begin
  t := TTyShellTreeView.Create(FForm);
  t.Parent := FForm;
  AssertFalse('off: a stand-alone tree lists what it listed', t.ShowPlaces);
  AssertEquals('the roots', Length(TyFsRoots), TTreeCount(t).RootNodeCount);
  t.ShowPlaces := True;
  known := TyFsKnownFolders;
  AssertEquals('on: the known folders and the roots', Length(known) + Length(TyFsRoots),
    TTreeCount(t).RootNodeCount);
  t.ShowPlaces := False;
  AssertEquals('and off again', Length(TyFsRoots), TTreeCount(t).RootNodeCount);
end;

procedure TShellTreePlacesTest.TurningTheSwitchKeepsTheFolderTheTreeIsIn;
var
  t: TPlacesTree;
  other: string;
begin
  t := NewTree;
  other := AppendPathDelim(FDrive) + 'Other';
  AssertTrue(t.SelectPath(other));
  t.ShowPlaces := True;   // rebuilds the top level
  AssertTrue('the tree is still in the folder it was in', SameFileName(other, t.SelectedPath));
  AssertTrue('and has it focused', SameFileName(other, t.PathOf(t.FocusedNode)));
end;

procedure TShellTreePlacesTest.AScopedTreeIsLeftAsItIs;
var
  t: TPlacesTree;
begin
  { Root scopes the tree to one directory; there is no top level to put places on, and
    nothing to make again. }
  t := NewTree;
  t.Root := FDrive;
  AssertEquals('precondition: the one directory', 1, t.RootNodeCount);
  t.Expanded[t.Top(0)] := True;
  AssertTrue('precondition: opened', t.Expanded[t.Top(0)]);
  t.ShowPlaces := True;
  AssertEquals('still its one directory', 1, t.RootNodeCount);
  AssertTrue('and not built again: still open', t.Expanded[t.Top(0)]);
end;

{ ====================================================== the folder drop-down == }

type
  TListCrack = class(TTyCustomListBox);     // PaintItemContent
  TComboCrack2 = class(TTyShellComboBox);

procedure TPlacesCombo.RowGlyphInk(ARow: Integer; out AFolder, ADrive: Integer);
var
  list: TTyCustomListBox;
  bmp: TBitmap;
  img: TBGRABitmap;
  P: TTyPainter;
  r: TRect;
  x, y: Integer;
  px: PBGRAPixel;
begin
  AFolder := 0;
  ADrive := 0;
  r := Types.Rect(0, 0, 220, 24);
  list := CreatePopupList;   // the combo's own list class, as it makes it for the drop-down
  bmp := TBitmap.Create;
  P := TTyPainter.Create;
  try
    list.Items.Assign(Items);
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(r.Right, r.Bottom);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(r);
    P.BeginPaint(bmp.Canvas, r, 96);
    TListCrack(list).PaintItemContent(P, r, ARow,
      TyDefaultController.Model.ResolveStyle('TyListItem', '', []));
    P.EndPaint;
    img := TBGRABitmap.Create(bmp);
    try
      for y := 0 to img.Height - 1 do
      begin
        px := img.ScanLine[y];
        for x := 0 to img.Width - 1 do
          { the folder is drawn amber (226,176,66), the drive steel blue (96,116,150) }
          if (px[x].red > 190) and (px[x].green > 140) and (px[x].blue < 120) then Inc(AFolder)
          else if (px[x].blue > px[x].red + 30) and (px[x].blue > 110) and (px[x].red < 140) then
            Inc(ADrive);
      end;
    finally
      img.Free;
    end;
  finally
    P.Free;
    bmp.Free;
    list.Free;
  end;
end;

function TPlacesCombo.FieldInkRight: Integer;
var
  bmp: TBitmap;
  img: TBGRABitmap;
  r: TRect;
  x, y: Integer;
  px: PBGRAPixel;
begin
  Result := -1;
  r := Types.Rect(0, 0, Width, Height);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(Width, Height);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(r);
    RenderTo(bmp.Canvas, r, 96);
    bmp.Canvas.FillRect(r);
    RenderTo(bmp.Canvas, r, 96);
    img := TBGRABitmap.Create(bmp);
    try
      { dark pixels, left of the drop arrow's zone and clear of the frame: the caption }
      for y := 6 to img.Height - 7 do
      begin
        px := img.ScanLine[y];
        for x := 30 to img.Width - 41 do
          if (px[x].red < 110) and (px[x].green < 110) and (px[x].blue < 110) and (x > Result) then
            Result := x;
      end;
    finally
      img.Free;
    end;
  finally
    bmp.Free;
  end;
end;

function TPlacesCombo.KnownFolders: TTyFsRootArray;
begin
  if UseGiven then Result := Given
  else Result := inherited KnownFolders;
end;

procedure TPlacesCombo.Pick(AIndex: Integer);
begin
  ItemIndex := AIndex;
  DoSelect;
end;

function TPlacesCombo.Caption0: string;
begin
  Result := FieldCaption;
end;

procedure TLookInPlacesTest.SetUp;
begin
  FTemp := ChompPathDelim(AppendPathDelim(GetTempDir) + 'typlacecombo_'
    + IntToStr(GetProcessID) + '_' + IntToStr(Random(1000000)));
  ForceDirectoriesUTF8(AppendPathDelim(FTemp) + 'Docs');
  ForceDirectoriesUTF8(AppendPathDelim(FTemp) + 'here');
  FForm := TForm.CreateNew(nil);
  FPicks := 0;
end;

procedure TLookInPlacesTest.TearDown;
begin
  FForm.Free;
  if (FTemp <> '') and DirectoryExistsUTF8(FTemp) then
    DeleteDirectory(FTemp, False);
end;

procedure TLookInPlacesTest.Picked(Sender: TObject);
begin
  Inc(FPicks);
end;

function TLookInPlacesTest.Folders: TTyFsRootArray;
begin
  Result := nil;
  SetLength(Result, 2);
  Result[0].Path := AppendPathDelim(FTemp) + 'Docs'; Result[0].Display := 'Documents'; Result[0].Kind := rkPlace;
  Result[1].Path := AppendPathDelim(FTemp) + 'Desk'; Result[1].Display := 'Desktop';   Result[1].Kind := rkPlace;
end;

procedure TLookInPlacesTest.TheRowsAreThePathThenTheFoldersThenTheOtherRoots;
var
  here: string;
  crumbs: TStringArray;
  rows, plain: TTyLookInPlaceArray;
  i, n: Integer;
begin
  here := AppendPathDelim(FTemp) + 'here';
  crumbs := TyFsBreadcrumb(here);
  plain := TyLookInPlaces(here);
  rows := TyLookInPlaces(here, Folders);
  n := Length(crumbs);
  AssertEquals('two rows more than without the folders', Length(plain) + 2, Length(rows));
  for i := 0 to n - 1 do
  begin
    AssertEquals('first the levels of the path', crumbs[i], rows[i].Path);
    AssertFalse('which are not places', rows[i].Folder);
  end;
  AssertEquals('then the folders, by name', 'Documents', rows[n].Display);
  AssertEquals('each a row of its own path', AppendPathDelim(FTemp) + 'Docs', rows[n].Path);
  AssertEquals('at the left edge', 0, rows[n].Depth);
  AssertTrue('marked as a folder place', rows[n].Folder);
  AssertEquals('in the order given', 'Desktop', rows[n + 1].Display);
  AssertTrue('the second too', rows[n + 1].Folder);
  for i := n + 2 to High(rows) do
  begin
    AssertEquals('then the other roots, as before', plain[i - 2].Path, rows[i].Path);
    AssertFalse('which are not folder places', rows[i].Folder);
  end;
end;

procedure TLookInPlacesTest.WithoutFoldersTheRowsAreWhatTheyWere;
var
  here: string;
  a, b: TTyLookInPlaceArray;
  i: Integer;
begin
  here := AppendPathDelim(FTemp) + 'here';
  a := TyLookInPlaces(here);
  b := TyLookInPlaces(here, nil);
  AssertEquals(Length(a), Length(b));
  for i := 0 to High(a) do
  begin
    AssertEquals(a[i].Path, b[i].Path);
    AssertEquals(a[i].Display, b[i].Display);
    AssertEquals(a[i].Depth, b[i].Depth);
    AssertFalse(b[i].Folder);
  end;
end;

procedure TLookInPlacesTest.AFolderRowShowsAFolderAndARootItsDrive;
var
  c: TPlacesCombo;
  n: Integer;
begin
  c := TPlacesCombo.Create(FForm);
  c.Parent := FForm;
  c.Given := Folders;
  c.UseGiven := True;
  c.Directory := AppendPathDelim(FTemp) + 'here';
  n := Length(TyFsBreadcrumb(AppendPathDelim(FTemp) + 'here'));
  AssertEquals('precondition: the row after the path is the first folder', 'Documents', c.Items[n]);
  AssertEquals('a folder place: the folder glyph', TyLookInFolderGlyph, c.GlyphOfModel(n));
  AssertEquals('the root of the path: the drive glyph', TyLookInDriveGlyph, c.GlyphOfModel(0));
  AssertEquals('a level below it: the folder glyph', TyLookInFolderGlyph, c.GlyphOfModel(1));
  if c.Items.Count > n + 2 then
    AssertEquals('another root: the drive glyph', TyLookInDriveGlyph, c.GlyphOfModel(n + 2));
end;

procedure TLookInPlacesTest.TheDropDownDrawsAFolderRowWithTheFolderGlyph;
var
  c: TPlacesCombo;
  n, folder, drive: Integer;
begin
  { What the drop-down draws, not what the combo would answer if asked: the list asks the
    combo for each row's glyph, and asked by depth alone a place at depth 0 is a drive. }
  c := TPlacesCombo.Create(FForm);
  c.Parent := FForm;
  c.Given := Folders;
  c.UseGiven := True;
  c.Directory := AppendPathDelim(FTemp) + 'here';
  n := Length(TyFsBreadcrumb(AppendPathDelim(FTemp) + 'here'));
  c.RowGlyphInk(0, folder, drive);
  AssertTrue('precondition: the root of the path is drawn as a drive', (drive > 20) and (folder = 0));
  c.RowGlyphInk(n, folder, drive);
  AssertTrue('a folder place is drawn with the folder glyph', folder > 20);
  AssertEquals('and none of the drive''s', 0, drive);
end;

procedure TLookInPlacesTest.TheFieldDrawsThePlacesName;
var
  a, b: TPlacesCombo;
  docs: string;
  f: TTyFsRootArray;
begin
  { Two boxes in the same folder; one knows it as a place with a long name. The field of
    that one has to draw the longer text. }
  docs := AppendPathDelim(FTemp) + 'Docs';
  f := Folders;
  f[0].Display := 'Documents of this user, all of them';
  a := TPlacesCombo.Create(FForm);
  a.Parent := FForm;
  a.SetBounds(0, 0, 420, 30);
  a.Given := f;
  a.UseGiven := True;
  a.Directory := docs;
  b := TPlacesCombo.Create(FForm);
  b.Parent := FForm;
  b.SetBounds(0, 40, 420, 30);
  b.UseGiven := True;   // and Given is empty: no places
  b.Directory := docs;
  AssertEquals('precondition: without the place the field says the folder''s name', 'Docs', b.Caption0);
  AssertTrue('precondition: that name is drawn', b.FieldInkRight > 30);
  AssertTrue(Format('the place''s name is what is drawn: its ink runs further (%d) than the '
    + 'folder name''s (%d)', [a.FieldInkRight, b.FieldInkRight]),
    a.FieldInkRight > b.FieldInkRight + 60);
end;

procedure TLookInPlacesTest.PickingAFolderGoesThereAndTheFieldSaysItsName;
var
  c: TPlacesCombo;
  n: Integer;
  docs: string;
begin
  docs := AppendPathDelim(FTemp) + 'Docs';
  c := TPlacesCombo.Create(FForm);
  c.Parent := FForm;
  c.Given := Folders;
  c.UseGiven := True;
  c.OnSelectPath := @Picked;
  c.Directory := AppendPathDelim(FTemp) + 'here';
  AssertEquals('precondition: elsewhere, the field shows the folder''s own name', 'here', c.Caption0);
  n := Length(TyFsBreadcrumb(AppendPathDelim(FTemp) + 'here'));
  c.Pick(n);
  AssertEquals('the host is told once', 1, FPicks);
  AssertTrue('the box is in the folder of the place', SameFileName(docs, c.Directory));
  AssertTrue('and that is the path it hands out', SameFileName(docs, c.SelectedPath));
  AssertEquals('the field shows the place''s name', 'Documents', c.Caption0);
end;

procedure TLookInPlacesTest.TheSwitchIsOffUntilItIsAskedFor;
var
  c: TTyShellComboBox;
begin
  c := TTyShellComboBox.Create(FForm);
  c.Parent := FForm;
  AssertFalse('off: a stand-alone box lists what it listed', c.ShowPlaces);
  AssertEquals('the roots', Length(TyFsRoots), c.Items.Count);
  c.ShowPlaces := True;
  AssertEquals('on: the known folders and the roots',
    Length(TyFsKnownFolders) + Length(TyFsRoots), c.Items.Count);
  c.ShowPlaces := False;
  AssertEquals('and off again', Length(TyFsRoots), c.Items.Count);
end;

procedure TLookInPlacesTest.TheFileDialogsTurnBothSwitchesOn;
var
  d: TTyFileDialogForm;
begin
  { On main the left pane is the places pane (#246) and the folder box lists the pane's
    places; the tree is there on request, and then lists the places as on the 3.0 line. }
  d := TyBuildFileDialog(False, False, '');
  try
    d.LeftPane := fdpFolderTree;
    AssertTrue('the tree of the open dialog lists the places', d.ShellTree.ShowPlaces);
    AssertEquals('the tree: the known folders above the roots',
      Length(TyFsKnownFolders) + Length(TyFsRoots), TTreeCount(d.ShellTree).RootNodeCount);
    AssertTrue('the folder box lists them too: after the chain, the places',
      d.LookInBox.Items.Count >= Length(TyFsKnownFolders) + Length(TyFsRoots));
  finally
    d.Free;
  end;
  d := TyBuildFileDialog(True, True, '');
  try
    d.LeftPane := fdpFolderTree;
    AssertTrue('the save dialog, with a preview: the tree', d.ShellTree.ShowPlaces);
  finally
    d.Free;
  end;
end;

procedure TLookInPlacesTest.AtTheRootOfADriveTheDriveIsListedOnce;
var
  c: TTyShellComboBox;
  roots: TTyFsRootArray;
  root: string;
  i, seen: Integer;
begin
  { The root keeps its delimiter: 'C:' is not the root of drive C (it is the current directory
    on it), and '/' without its slash is no directory at all. Stripped, the row of the current
    path matched none of the roots, and the drive was listed a second time. }
  roots := TyFsRoots;
  root := roots[0].Path;
  c := TTyShellComboBox.Create(FForm);
  c.Parent := FForm;
  c.Directory := root;
  AssertTrue('the box is at the root, as it was given', c.Directory = root);
  AssertEquals('every root once, and nothing else', Length(roots), c.Items.Count);
  seen := 0;
  for i := 0 to c.Items.Count - 1 do
    if c.Items[i] = roots[0].Display then Inc(seen);
  AssertEquals('this root under its one label', 1, seen);
  AssertTrue('its row is the selected one', c.ItemIndex >= 0);
  AssertEquals('and shows the root''s label', roots[0].Display, c.Items[c.ItemIndex]);
  AssertTrue('and hands out the root', SameFileName(root, c.SelectedPath));
  { any other directory is still kept without a delimiter }
  c.Directory := AppendPathDelim(FTemp);
  AssertTrue('a folder given with a delimiter is kept without it', c.Directory = FTemp);
end;

initialization
  RegisterTest(TFsPlacesTest);
  RegisterTest(TShellTreePlacesTest);
  RegisterTest(TLookInPlacesTest);
end.
