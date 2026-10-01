unit test.themebuilder.export;
{ Exporting a theme bundle (phase 2): which files go in (the runtime's rules: @import from the
  importing file's folder, url() from the entry's), what is refused, the folder and the zip
  as the library's readers read them back, and nothing left behind when an export fails --
  a zip that was there is byte for byte as it was. Every target is in a folder of the test's
  own under the system's temporary folder. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, tbexport;

type
  TTbExportTests = class(TTestCase)
  private
    FDir: string;
    procedure WriteBytes(const AFileName, ABytes: string);
    function ReadBytes(const AFileName: string): string;
    function CopyGreen: string;           { the green theme and its picture; its text }
    function Collect(const AText, ABaseDir: string; out AFiles: TTbBundleFiles;
      out AError: string): Boolean;
    function Info(const AVersion: string = '1.0'): TTbBundleInfo;
    procedure AssertNothingLeft(const ATag, AParent: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheGreenThemeTakesItsPicture;
    procedure TestImportChains;
    procedure TestRefusedReferences;
    procedure TestAFolderBundle;
    procedure TestAZipBundle;
    procedure TestAZipCannotCarryFiles;
    procedure TestAFailedExportLeavesNothing;
    procedure TestAFolderMustBeNewOrEmpty;
    procedure TestReplacingAZip;
    procedure TestTheManifestEscapes;
    procedure TestTheDialog;
    procedure TestTheModernDensityIsTriedToo;
    procedure TestAFailedMoveKeepsTheFolder;
  end;

implementation

uses
  {$IFDEF MSWINDOWS}Windows,{$ENDIF}
  FileUtil, zipper, Controls, tyControls.ThemeBundle, tbtemplates, tbexportform, tbpreview,
  test.themebuilder.golden;

const
  { a 1x1 PNG }
  cPng = #$89'PNG'#13#10#$1A#10#0#0#0#13'IHDR'#0#0#0#1#0#0#0#1#8#6#0#0#0#$1F#$15#$C4#$89 +
    #0#0#0#13'IDATx'#$9C'c'#$F8#$FF#$FF'?'#0#5#$FE#2#$FE#$A7#$35#$81#$84 +
    #0#0#0#0'IEND'#$AE'B'#$60#$82;
  cFailingDoc = '@mode light { :root { --z: #ffffff; } }'#10'@mode dark { :root { --y: #000000; } }'#10 +
    'TyButton { background: var(--z); }';

var
  GExportSeq: Integer = 0;

procedure TTbExportTests.SetUp;
begin
  Inc(GExportSeq);
  FDir := IncludeTrailingPathDelimiter(GetTempDir(False)) +
    Format('tb2-export-%d-%d', [GetProcessID, GExportSeq]) + PathDelim;
  ForceDirectories(FDir);
end;

procedure TTbExportTests.TearDown;
begin
  if DirectoryExists(FDir) then
    DeleteDirectory(ExcludeTrailingPathDelimiter(FDir), False);
end;

procedure TTbExportTests.WriteBytes(const AFileName, ABytes: string);
var
  fs: TFileStream;
begin
  ForceDirectories(ExtractFileDir(AFileName));
  fs := TFileStream.Create(AFileName, fmCreate);
  try
    if ABytes <> '' then
      fs.WriteBuffer(ABytes[1], Length(ABytes));
  finally
    fs.Free;
  end;
end;

function TTbExportTests.ReadBytes(const AFileName: string): string;
var
  fs: TFileStream;
begin
  Result := '';
  fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, fs.Size);
    if fs.Size > 0 then
      fs.ReadBuffer(Result[1], fs.Size);
  finally
    fs.Free;
  end;
end;

function TTbExportTests.CopyGreen: string;
begin
  Result := ReadBytes(TbThemesDir + 'green.tycss');
  WriteBytes(FDir + 'theme' + PathDelim + 'green.tycss', Result);
  WriteBytes(FDir + 'theme' + PathDelim + 'assets' + PathDelim + 'background.jpg',
    ReadBytes(TbThemesDir + 'assets' + PathDelim + 'background.jpg'));
end;

function TTbExportTests.Collect(const AText, ABaseDir: string; out AFiles: TTbBundleFiles;
  out AError: string): Boolean;
begin
  Result := TbCollectBundleFiles(AText, ABaseDir, AFiles, AError);
end;

function TTbExportTests.Info(const AVersion: string): TTbBundleInfo;
begin
  Result.Name := 'green';
  Result.Author := 'Me';
  Result.Version := AVersion;
  Result.DualMode := False;
end;

procedure TTbExportTests.AssertNothingLeft(const ATag, AParent: string);
var
  files, dirs: TStringList;
  i: Integer;
begin
  files := FindAllFiles(AParent, '*.tbtmp*;*.tbbak', False);
  dirs := FindAllDirectories(AParent, False);
  try
    AssertEquals(ATag + ': no temporary file', 0, files.Count);
    for i := 0 to dirs.Count - 1 do
      AssertTrue(ATag + ': no temporary folder: ' + dirs[i], Pos('.tbtmp', dirs[i]) = 0);
  finally
    files.Free;
    dirs.Free;
  end;
end;

procedure TTbExportTests.TestTheGreenThemeTakesItsPicture;
var
  files: TTbBundleFiles;
  err: string;
begin
  AssertTrue('X1: collected: ' + err, Collect(CopyGreen, FDir + 'theme', files, err));
  AssertEquals('X1: one file', 1, Length(files));
  AssertEquals('X1: as referred to', 'assets/background.jpg', files[0].Archive);
  AssertTrue('X1: on disk', FileExists(files[0].Source));
end;

procedure TTbExportTests.TestImportChains;
var
  files: TTbBundleFiles;
  err, names: string;
  i: Integer;
begin
  WriteBytes(FDir + 'parts' + PathDelim + 'a.tycss', '@import "b.tycss";');
  WriteBytes(FDir + 'parts' + PathDelim + 'b.tycss',
    'TyPanel { background-image: url(img/x.png) slice(0 0 0 0); }');
  WriteBytes(FDir + 'img' + PathDelim + 'x.png', cPng);
  AssertTrue('X2: collected: ' + err, Collect('@import "parts/a.tycss";'#10'TyButton { color: #111111; }',
    FDir, files, err));
  names := '';
  for i := 0 to High(files) do
    names := names + files[i].Archive + ';';
  AssertEquals('X2: the chain and the picture, once each', 'parts/a.tycss;parts/b.tycss;img/x.png;', names);
end;

procedure TTbExportTests.TestRefusedReferences;
var
  files: TTbBundleFiles;
  err: string;
begin
  {$IFDEF MSWINDOWS}
  AssertFalse('X3: a drive path', Collect('TyPanel { background-image: url(C:\x.png); }', FDir, files, err));
  AssertTrue('X3: absolute: ' + err, Pos(rsTbExportAbsolute, err) > 0);
  {$ENDIF}
  AssertFalse('X3: a rooted path', Collect('TyPanel { background-image: url(/x.png); }', FDir, files, err));
  AssertTrue('X3: absolute: ' + err, Pos(rsTbExportAbsolute, err) > 0);
  AssertFalse('X3: out of the folder', Collect('@import "../x.tycss";', FDir, files, err));
  AssertTrue('X3: outside: ' + err, Pos(rsTbExportOutside, err) > 0);
  AssertFalse('X3: missing', Collect('TyPanel { background-image: url(nope.png); }', FDir, files, err));
  AssertTrue('X3: not found: ' + err, Pos(rsTbExportMissing, err) > 0);
  AssertFalse('X3: unsaved', Collect('TyPanel { background-image: url(a.png); }', '', files, err));
  AssertTrue('X3: save first: ' + err, Pos(rsTbExportUnsaved, err) > 0);
  AssertTrue('X3: unsaved, nothing referred to', Collect(TbMinimalTemplate, '', files, err));
  AssertEquals('X3: no files', 0, Length(files));
  AssertTrue('X3: a data URL', Collect('TyPanel { background-image: url(data:image/png;base64,AAAA); }',
    FDir, files, err));
  AssertEquals('X3: is not a file', 0, Length(files));
end;

procedure TTbExportTests.TestAFolderBundle;
var
  files: TTbBundleFiles;
  err, entry, target: string;
  found: TStringList;
  man: TTyThemeManifest;
  src: ITyThemeSource;
begin
  entry := CopyGreen;
  AssertTrue('collected', Collect(entry, FDir + 'theme', files, err));
  target := FDir + 'out' + PathDelim + 'green';
  ForceDirectories(FDir + 'out');
  AssertTrue('X4: exported: ' + err, TbExportBundle(entry, files, Info, tbfFolder, target, err));
  found := FindAllFiles(target, '*', True);
  try
    AssertEquals('X4: three files', 3, found.Count);
  finally
    found.Free;
  end;
  AssertTrue('X4: the entry as written', ReadBytes(target + PathDelim + 'theme.tycss') = entry);
  AssertTrue('X4: the picture as it was', ReadBytes(target + PathDelim + 'assets' + PathDelim + 'background.jpg')
    = ReadBytes(TbThemesDir + 'assets' + PathDelim + 'background.jpg'));
  src := TTyThemeDirSource.Create(target);
  man := src.Manifest;
  AssertEquals('X4: name', 'green', man.Name);
  AssertEquals('X4: author', 'Me', man.Author);
  AssertEquals('X4: version', '1.0', man.Version);
  AssertFalse('X4: one mode', man.DualMode);
  AssertEquals('X4: entry', 'theme.tycss', man.Entry);
  AssertNothingLeft('X4', FDir + 'out');
end;

procedure TTbExportTests.TestAZipBundle;
var
  err, target: string;
  inf: TTbBundleInfo;
  uz: TUnZipper;
  names: TStringList;
  i: Integer;
  src: ITyThemeSource;
begin
  target := FDir + 'minimal.zip';
  inf := Info;
  inf.DualMode := True;
  AssertTrue('X5: exported: ' + err, TbExportBundle(TbMinimalTemplate, nil, inf, tbfZip, target, err));
  uz := TUnZipper.Create;
  names := TStringList.Create;
  try
    uz.FileName := target;
    uz.Examine;
    for i := 0 to uz.Entries.Count - 1 do
      names.Add(uz.Entries[i].ArchiveFileName);
    names.Sort;
    AssertEquals('X5: two entries', 'theme.json,theme.tycss', names.CommaText);
  finally
    names.Free;
    uz.Free;
  end;
  src := TTyThemeZipSource.Create(target);
  AssertEquals('X5: the entry', StringReplace(TbMinimalTemplate, #13#10, #10, [rfReplaceAll]),
    StringReplace(src.RootCss, #13#10, #10, [rfReplaceAll]));
  AssertTrue('X5: two modes', src.Manifest.DualMode);
  AssertEquals('X5: its name', 'green', src.Manifest.Name);
  src := nil;
  AssertNothingLeft('X5', FDir);
end;

procedure TTbExportTests.TestAZipCannotCarryFiles;
var
  files: TTbBundleFiles;
  err, entry, target: string;
begin
  entry := CopyGreen;
  AssertTrue('collected', Collect(entry, FDir + 'theme', files, err));
  target := FDir + 'green.zip';
  AssertFalse('X6: refused', TbExportBundle(entry, files, Info, tbfZip, target, err));
  AssertEquals('X6: why', rsTbExportZipRefs, err);
  AssertFalse('X6: no zip', FileExists(target));
  AssertNothingLeft('X6', FDir);
end;

procedure TTbExportTests.TestAFailedExportLeavesNothing;
var
  err, target, old: string;
begin
  target := FDir + 'bad';
  AssertFalse('X7: a folder that does not load back', TbExportBundle(cFailingDoc, nil, Info, tbfFolder,
    target, err));
  AssertTrue('X7: says so: ' + err, Pos(rsTbExportVerifyFailed, err) = 1);
  AssertFalse('X7: no folder', DirectoryExists(target));
  AssertNothingLeft('X7 folder', FDir);
  target := FDir + 'bad.zip';
  AssertFalse('X7: a zip that does not load back', TbExportBundle(cFailingDoc, nil, Info, tbfZip,
    target, err));
  AssertTrue('X7: says so: ' + err, Pos(rsTbExportVerifyFailed, err) = 1);
  AssertFalse('X7: no zip', FileExists(target));
  AssertNothingLeft('X7 zip', FDir);
  old := 'not a zip, but the user''s file' + #0#1#2;
  WriteBytes(FDir + 'old.zip', old);
  AssertFalse('X7: over an old zip', TbExportBundle(cFailingDoc, nil, Info, tbfZip,
    FDir + 'old.zip', err));
  AssertTrue('X7: the old zip is as it was', ReadBytes(FDir + 'old.zip') = old);
  AssertNothingLeft('X7 old zip', FDir);
end;

procedure TTbExportTests.TestAFolderMustBeNewOrEmpty;
var
  err, target: string;
begin
  target := FDir + 'full';
  WriteBytes(target + PathDelim + 'keep.txt', 'keep');
  AssertFalse('X8: refused', TbExportBundle(TbMinimalTemplate, nil, Info, tbfFolder, target, err));
  AssertTrue('X8: why: ' + err, Pos(Format(rsTbExportFolderNotEmpty, [target]), err) > 0);
  AssertTrue('X8: the file is still there', FileExists(target + PathDelim + 'keep.txt'));
  AssertNothingLeft('X8', FDir);
  target := FDir + 'empty';
  ForceDirectories(target);
  AssertTrue('X8: an empty folder is taken: ' + err, TbExportBundle(TbMinimalTemplate, nil, Info,
    tbfFolder, target, err));
  AssertTrue('X8: the entry is in it', FileExists(target + PathDelim + 'theme.tycss'));
end;

procedure TTbExportTests.TestReplacingAZip;
var
  err, target: string;
  src: ITyThemeSource;
begin
  target := FDir + 'twice.zip';
  AssertTrue('first', TbExportBundle(TbMinimalTemplate, nil, Info('1.0'), tbfZip, target, err));
  AssertTrue('X9: again: ' + err, TbExportBundle(TbMinimalTemplate, nil, Info('2.0'), tbfZip, target, err));
  src := TTyThemeZipSource.Create(target);
  AssertEquals('X9: the new one', '2.0', src.Manifest.Version);
  src := nil;
  AssertFalse('X9: no backup left', FileExists(target + '.tbbak'));
  AssertNothingLeft('X9', FDir);
end;

procedure TTbExportTests.TestTheManifestEscapes;
var
  inf: TTbBundleInfo;
  man: TTyThemeManifest;
begin
  inf.Name := 'my "quoted" theme';
  inf.Author := 'C:\Users\me';
  inf.Version := #$E4#$B8#$AD#$E6#$96#$87;
  inf.DualMode := True;
  man := TyParseThemeManifest(TbManifestJson(inf), 'x');
  AssertTrue('X10: it parses', man.Loaded);
  AssertEquals('X10: name', inf.Name, man.Name);
  AssertEquals('X10: author', inf.Author, man.Author);
  AssertEquals('X10: version', inf.Version, man.Version);
  AssertTrue('X10: two modes', man.DualMode);
  AssertEquals('X10: entry', 'theme.tycss', man.Entry);
end;

procedure TTbExportTests.TestTheDialog;
var
  f: TTbExportForm;
  err, entry: string;
begin
  entry := CopyGreen;
  f := TTbExportForm.Create(nil);
  try
    f.Prepare(entry, FDir + 'theme', 'green', False);
    AssertTrue('X11: the picture is listed', f.LstFiles.Items.IndexOf('assets/background.jpg') >= 0);
    AssertFalse('X11: no zip for it', f.RadZip.Enabled);
    AssertTrue('X11: a folder', f.RadFolder.Checked);
    AssertFalse('X11: a folder target: ' + f.EdtTarget.Text, SameText(ExtractFileExt(f.EdtTarget.Text), '.zip'));
    AssertTrue('X11: export enabled', f.BtnExport.Enabled);
    f.EdtTarget.Text := FDir + 'dialog';
    AssertTrue('X11: exported: ' + err, f.DoExport(err));
    AssertEquals('X11: closes with OK', Ord(mrOk), Ord(f.ModalResult));
    AssertTrue('X11: the bundle', FileExists(FDir + 'dialog' + PathDelim + 'theme.tycss'));
  finally
    f.Free;
  end;
  f := TTbExportForm.Create(nil);
  try
    f.Prepare('TyPanel { background-image: url(a.png); }', '', 'x', False);
    AssertFalse('X11: an unsaved theme with a picture cannot go', f.BtnExport.Enabled);
    AssertTrue('X11: and says why: ' + f.LblNote.Caption, Pos(rsTbExportUnsaved, f.LblNote.Caption) > 0);
    { the review found it: only the button stood in the way -- DoExport itself went ahead and
      wrote a bundle without the picture }
    f.EdtTarget.Text := FDir + 'nopicture';
    AssertFalse('X13: DoExport refuses too', f.DoExport(err));
    AssertTrue('X13: with the reason: ' + err, Pos(rsTbExportUnsaved, err) > 0);
    AssertFalse('X13: nothing written', DirectoryExists(FDir + 'nopicture'));
  finally
    f.Free;
  end;
end;

{ The review found it: the bundle was read back and probed in the classic density only. A
  theme that uses a variable of the modern density pack as a colour loads and paints in the
  classic density, and cannot be drawn by an application that switches to the modern one. }
procedure TTbExportTests.TestTheModernDensityIsTriedToo;
const
  cDoc = ':root { --segmented-height: #123456; }'#10'TyButton { background: var(--segmented-height); }';
var
  err, target: string;
begin
  target := FDir + 'dense';
  AssertFalse('X12: refused', TbExportBundle(cDoc, nil, Info, tbfFolder, target, err));
  AssertTrue('X12: names the density: ' + err,
    Pos(Format(rsTbDensityFailed, [rsTbDensityModern, '']), err) > 0);
  AssertFalse('X12: no folder', DirectoryExists(target));
  AssertNothingLeft('X12', FDir);
  AssertTrue('X12: a theme that is fine in both goes: ' + err,
    TbExportBundle(TbMinimalTemplate, nil, Info, tbfFolder, target, err));
end;

{ the bundle cannot be moved into place (another program has the folder open): the move of
  the temporary bundle fails, with the system's reason }
function FailTheBundleMove(const AFrom, ATo: string): Boolean;
begin
  if Pos('.tbtmp', AFrom) > 0 then
  begin
    {$IFDEF MSWINDOWS}
    Windows.SetLastError(ERROR_ACCESS_DENIED);
    {$ENDIF}
    Exit(False);
  end;
  Result := RenameFile(AFrom, ATo);
end;

{ The review found it: an empty target folder was deleted first, and when the bundle could
  not be moved in after that, the user's folder was gone -- and the message said the folder
  did not exist. It is moved aside and put back, and the message says why the move failed. }
procedure TTbExportTests.TestAFailedMoveKeepsTheFolder;
var
  err, target: string;
begin
  target := FDir + 'mine';
  ForceDirectories(target);
  TbExportRenameForTest := @FailTheBundleMove;
  try
    AssertFalse('X14: the move fails', TbExportBundle(TbMinimalTemplate, nil, Info, tbfFolder, target, err));
  finally
    TbExportRenameForTest := nil;
  end;
  AssertTrue('X14: the user''s folder is still there', DirectoryExists(target));
  AssertFalse('X14: nothing moved aside is left', DirectoryExists(target + '.tbold'));
  AssertTrue('X14: says the move failed: ' + err, Pos(Format(rsTbExportMoveFailed, [target, '']), err) = 1);
  {$IFDEF MSWINDOWS}
  AssertTrue('X14: with the system''s reason: ' + err, Pos(SysErrorMessage(ERROR_ACCESS_DENIED), err) > 0);
  {$ENDIF}
  AssertNothingLeft('X14', FDir);
  AssertTrue('X14: and the next try goes in: ' + err,
    TbExportBundle(TbMinimalTemplate, nil, Info, tbfFolder, target, err));
  AssertFalse('X14: the folder it took is not left aside', DirectoryExists(target + '.tbold'));
end;

initialization
  RegisterTest(TTbExportTests);
end.
