unit test.themebuilder.doc;
{ The theme builder's document model, settings and new-document templates (phase 1).
  Document: a file read and written back through a SynEdit comes out byte for byte the same
  (LF, CRLF, CR, BOM, no final line break, a repo theme); a file that is not UTF-8 is
  converted and says from what; the disk watch reports one change once and not the tool's
  own saves; a failed read leaves the document alone; the "run the generator" hint only in
  a repo checkout. Settings: defaults, a round trip, the recent list. Templates: a built-in
  theme copied verbatim under a header; the minimal template works in both modes. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry;

type
  TTbTempDirTest = class(TTestCase)
  protected
    FDir: string;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure WriteBytes(const AFileName, ABytes: string);
    function ReadBytes(const AFileName: string): string;
  end;

  TTbDocumentTests = class(TTbTempDirTest)
  private
    procedure RoundTrip(const ALabel, ABytes: string);
  published
    procedure TestLfRoundTrip;
    procedure TestCrLfRoundTrip;
    procedure TestNoFinalLineBreak;
    procedure TestBomRoundTrip;
    procedure TestCrRoundTrip;
    procedure TestNotUtf8IsConverted;
    procedure TestARepoThemeRoundTrip;
    procedure TestDiskChangedAnswersOncePerChange;
    procedure TestAFailedReadLeavesTheDocument;
    procedure TestRegenerateHintOnlyInACheckout;
  end;

  TTbSettingsTests = class(TTbTempDirTest)
  published
    procedure TestDefaults;
    procedure TestRoundTrip;
    procedure TestRecentList;
    procedure TestSaveCreatesTheFolder;
  end;

implementation

uses
  FileUtil, LazUTF8, LConvEncoding, SynEdit, tbdocument, tbsettings,
  test.themebuilder.golden;

var
  GTempSeq: Integer = 0;

{ ---- TTbTempDirTest ---- }

procedure TTbTempDirTest.SetUp;
begin
  Inc(GTempSeq);
  FDir := IncludeTrailingPathDelimiter(GetTempDir(False)) +
    Format('tb1-%d-%d', [GetProcessID, GTempSeq]) + PathDelim;
  ForceDirectories(FDir);
end;

procedure TTbTempDirTest.TearDown;
begin
  if (FDir <> '') and DirectoryExists(FDir) then
    DeleteDirectory(ExcludeTrailingPathDelimiter(FDir), False);
end;

procedure TTbTempDirTest.WriteBytes(const AFileName, ABytes: string);
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

function TTbTempDirTest.ReadBytes(const AFileName: string): string;
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

{ ---- TTbDocumentTests ---- }

procedure TTbDocumentTests.RoundTrip(const ALabel, ABytes: string);
var
  doc: TTbDocument;
  ed: TSynEdit;
begin
  WriteBytes(FDir + 'in.tycss', ABytes);
  doc := TTbDocument.Create;
  ed := TSynEdit.Create(nil);
  try
    doc.LoadFromFile(FDir + 'in.tycss');
    ed.Lines.Text := doc.EditorText;
    doc.SaveToFile(FDir + 'out.tycss', ed.Lines);
    AssertTrue(ALabel + ': the bytes came back the same', ReadBytes(FDir + 'out.tycss') = ABytes);
  finally
    ed.Free;
    doc.Free;
  end;
end;

procedure TTbDocumentTests.TestLfRoundTrip;
var
  doc: TTbDocument;
begin
  RoundTrip('D1', 'a {}'#10'b {}'#10);
  doc := TTbDocument.Create;
  try
    doc.LoadFromFile(FDir + 'in.tycss');
    AssertEquals('D1: LF', Ord(tleLF), Ord(doc.LineEnding));
    AssertTrue('D1: a final line break', doc.TrailingEol);
    AssertFalse('D1: no BOM', doc.HasBom);
  finally
    doc.Free;
  end;
end;

procedure TTbDocumentTests.TestCrLfRoundTrip;
var
  doc: TTbDocument;
begin
  RoundTrip('D2', 'a {}'#13#10'b {}'#13#10);
  doc := TTbDocument.Create;
  try
    doc.LoadFromFile(FDir + 'in.tycss');
    AssertEquals('D2: CRLF', Ord(tleCRLF), Ord(doc.LineEnding));
  finally
    doc.Free;
  end;
end;

procedure TTbDocumentTests.TestNoFinalLineBreak;
begin
  RoundTrip('D3', 'a {}'#13#10'b {}');
end;

procedure TTbDocumentTests.TestBomRoundTrip;
var
  doc: TTbDocument;
begin
  RoundTrip('D4', #$EF#$BB#$BF'a {}'#10);
  doc := TTbDocument.Create;
  try
    doc.LoadFromFile(FDir + 'in.tycss');
    AssertTrue('D4: BOM', doc.HasBom);
    AssertTrue('D4: the text does not start with it', Copy(doc.EditorText, 1, 3) <> #$EF#$BB#$BF);
  finally
    doc.Free;
  end;
end;

procedure TTbDocumentTests.TestCrRoundTrip;
var
  doc: TTbDocument;
begin
  RoundTrip('D5', 'a {}'#13'b {}'#13);
  doc := TTbDocument.Create;
  try
    doc.LoadFromFile(FDir + 'in.tycss');
    AssertEquals('D5: CR', Ord(tleCR), Ord(doc.LineEnding));
  finally
    doc.Free;
  end;
end;

procedure TTbDocumentTests.TestNotUtf8IsConverted;
var
  doc: TTbDocument;
  raw, enc: string;
begin
  { one byte E9: e-acute in Latin-1 / CP1252, not UTF-8. What it becomes depends on the
    system code page (GuessEncoding); that it becomes valid UTF-8 and says so does not. }
  raw := '/* '#$E9' */'#10;
  WriteBytes(FDir + 'latin.tycss', raw);
  doc := TTbDocument.Create;
  try
    doc.LoadFromFile(FDir + 'latin.tycss');
    AssertTrue('D6: it says it converted', doc.ConvertedFrom <> '');
    AssertTrue('D6: the text is UTF-8 now',
      FindInvalidUTF8Codepoint(PChar(doc.EditorText), Length(doc.EditorText)) < 0);
    enc := NormalizeEncoding(doc.ConvertedFrom);
    if (enc = 'cp1252') or (enc = 'iso88591') or (enc = 'iso-8859-1') then
      AssertTrue('D6: e-acute as UTF-8', Pos(#$C3#$A9, doc.EditorText) > 0);
    AssertEquals('D6: the same conversion LConvEncoding makes',
      ConvertEncoding('/* '#$E9' */'#10, doc.ConvertedFrom, EncodingUTF8), doc.EditorText);
  finally
    doc.Free;
  end;
end;

procedure TTbDocumentTests.TestARepoThemeRoundTrip;
begin
  RoundTrip('D7', ReadBytes(TbThemesDir + 'builtin' + PathDelim + 'win11.tycss'));
end;

procedure TTbDocumentTests.TestDiskChangedAnswersOncePerChange;
var
  doc: TTbDocument;
  ed: TSynEdit;
  fs: TFileStream;
  b: Byte;
begin
  WriteBytes(FDir + 'w.tycss', 'a {}'#10);
  doc := TTbDocument.Create;
  ed := TSynEdit.Create(nil);
  try
    doc.LoadFromFile(FDir + 'w.tycss');
    AssertFalse('D8: nothing changed yet', doc.DiskChanged);
    fs := TFileStream.Create(FDir + 'w.tycss', fmOpenReadWrite);
    try
      fs.Seek(0, soEnd);
      b := 10;
      fs.WriteBuffer(b, 1);
    finally
      fs.Free;
    end;
    AssertTrue('D8: another program changed it', doc.DiskChanged);
    AssertFalse('D8: the same change is not reported twice', doc.DiskChanged);
    DeleteFile(FDir + 'w.tycss');
    AssertFalse('D8: a file that went away is not reported', doc.DiskChanged);
    ed.Lines.Text := 'b {}';
    doc.SaveToFile(FDir + 'w.tycss', ed.Lines);
    AssertFalse('D8: our own save is not a change', doc.DiskChanged);
  finally
    ed.Free;
    doc.Free;
  end;
end;

procedure TTbDocumentTests.TestAFailedReadLeavesTheDocument;
var
  doc: TTbDocument;
  raised: Boolean;
begin
  WriteBytes(FDir + 'ok.tycss', 'a {}'#10);
  doc := TTbDocument.Create;
  try
    doc.LoadFromFile(FDir + 'ok.tycss');
    raised := False;
    try
      doc.LoadFromFile(FDir + 'nope.tycss');
    except
      raised := True;
    end;
    AssertTrue('D9: the read raised', raised);
    AssertEquals('D9: the file name stayed', ExpandFileName(FDir + 'ok.tycss'), doc.FileName);
    AssertEquals('D9: the text stayed', 'a {}'#10, doc.EditorText);
  finally
    doc.Free;
  end;
end;

procedure TTbDocumentTests.TestRegenerateHintOnlyInACheckout;

  function Hint(const ARel: string): string;
  var
    doc: TTbDocument;
  begin
    WriteBytes(FDir + ARel, 'a {}'#10);
    doc := TTbDocument.Create;
    try
      doc.LoadFromFile(FDir + ARel);
      Result := doc.RegenerateHint;
    finally
      doc.Free;
    end;
  end;

var
  d: string;
begin
  d := PathDelim;
  WriteBytes(FDir + 'root' + d + 'scripts' + d + 'gen-builtinthemes.ps1', '');
  AssertEquals('D10: builtin', 'gen-builtinthemes.ps1',
    Hint('root' + d + 'themes' + d + 'builtin' + d + 'x.tycss'));
  AssertEquals('D10: auto', 'gen-builtinthemes.ps1', Hint('root' + d + 'themes' + d + 'auto.tycss'));
  AssertTrue('D10: light', Pos('gen-defaulttheme.ps1',
    Hint('root' + d + 'themes' + d + 'light.tycss')) > 0);
  AssertEquals('D10: a palette', '', Hint('root' + d + 'themes' + d + 'palettes' + d + 'p.tycss'));
  AssertEquals('D10: not a checkout', '',
    Hint('other' + d + 'themes' + d + 'builtin' + d + 'x.tycss'));
end;

{ ---- TTbSettingsTests ---- }

procedure TTbSettingsTests.TestDefaults;
var
  st: TTbSettings;
begin
  WriteBytes(FDir + 'empty.ini', '');
  st := TTbSettings.Create(FDir + 'empty.ini');
  try
    st.Load;
    AssertEquals('S1: theme', 'default', st.EditorTheme);
    AssertFalse('S1: editor dark', st.EditorDark);
    AssertFalse('S1: preview dark', st.PreviewDark);
    AssertFalse('S1: preview modern', st.PreviewModern);
    AssertEquals('S1: recent', 0, st.Recent.Count);
  finally
    st.Free;
  end;
end;

procedure TTbSettingsTests.TestRoundTrip;
var
  a, b: TTbSettings;
begin
  a := TTbSettings.Create(FDir + 's.ini');
  b := TTbSettings.Create(FDir + 's.ini');
  try
    a.EditorTheme := 'xp';
    a.EditorDark := True;
    a.PreviewDark := True;
    a.PreviewModern := True;
    a.AddRecent(FDir + 'one.tycss');
    a.AddRecent(FDir + 'two.tycss');
    a.Save;
    b.Load;
    AssertEquals('S2: theme', 'xp', b.EditorTheme);
    AssertTrue('S2: editor dark', b.EditorDark);
    AssertTrue('S2: preview dark', b.PreviewDark);
    AssertTrue('S2: preview modern', b.PreviewModern);
    AssertEquals('S2: recent count', 2, b.Recent.Count);
    AssertEquals('S2: recent order', FDir + 'two.tycss', b.Recent[0]);
    AssertEquals('S2: recent order', FDir + 'one.tycss', b.Recent[1]);
  finally
    a.Free;
    b.Free;
  end;
end;

procedure TTbSettingsTests.TestRecentList;
var
  st: TTbSettings;
  i: Integer;
begin
  st := TTbSettings.Create(FDir + 'r.ini');
  try
    for i := 1 to 12 do
      st.AddRecent(FDir + 'f' + IntToStr(i) + '.tycss');
    AssertEquals('S3: at most ten', TbMaxRecent, st.Recent.Count);
    AssertEquals('S3: the last added is first', FDir + 'f12.tycss', st.Recent[0]);
    st.AddRecent(st.Recent[2]);
    AssertEquals('S3: a repeat moves to the front', FDir + 'f10.tycss', st.Recent[0]);
    AssertEquals('S3: without growing', TbMaxRecent, st.Recent.Count);
    {$IFDEF MSWINDOWS}
    st.AddRecent(UpperCase(FDir + 'f9.tycss'));
    AssertEquals('S3: case does not make it another file', TbMaxRecent, st.Recent.Count);
    AssertEquals('S3: it moved to the front', UpperCase(FDir + 'f9.tycss'), st.Recent[0]);
    {$ENDIF}
  finally
    st.Free;
  end;
end;

procedure TTbSettingsTests.TestSaveCreatesTheFolder;
var
  st: TTbSettings;
begin
  st := TTbSettings.Create(FDir + 'sub' + PathDelim + 'deeper' + PathDelim + 's.ini');
  try
    st.Save;
    AssertTrue('S4: the folder and the file exist', FileExists(st.FileName));
  finally
    st.Free;
  end;
end;

initialization
  RegisterTest(TTbDocumentTests);
  RegisterTest(TTbSettingsTests);
end.
