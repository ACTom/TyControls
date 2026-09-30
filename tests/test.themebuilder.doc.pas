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

  TTbTemplatesTests = class(TTestCase)
  published
    procedure TestFromBuiltinIsTheThemeUnderAHeader;
    procedure TestTheMinimalTemplateWorksInBothModes;
    procedure TestTheMinimalTemplateSeeds;
    procedure TestTheMinimalTemplateLintsClean;
  end;

implementation

uses
  FileUtil, LazUTF8, LConvEncoding, SynEdit, tbdocument, tbsettings, tbtemplates, tbpreview,
  tyControls.ThemeLint, tyControls.BuiltinThemes, tyControls.Controller,
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
    AssertEquals('S3: and leaves its old place', FDir + 'f9.tycss', st.Recent[3]);
    AssertEquals('S3: the oldest still there', FDir + 'f3.tycss', st.Recent[9]);
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

{ ---- TTbTemplatesTests ---- }

procedure TTbTemplatesTests.TestFromBuiltinIsTheThemeUnderAHeader;
var
  names: TStringArray;
  i: Integer;
  t, h: string;
begin
  names := TyBuiltinThemeNames;
  AssertTrue('there are built-in themes', Length(names) > 5);
  for i := 0 to High(names) do
  begin
    t := TbFromBuiltin(names[i]);
    h := TbBuiltinHeader(names[i]);
    AssertEquals('T1: ' + names[i] + ' starts with the header', 1, Pos(h, t));
    AssertTrue('T1: ' + names[i] + ' then the theme verbatim',
      Copy(t, Length(h) + 1, MaxInt) = TyBuiltinThemeCss(names[i]));
  end;
  AssertEquals('T1: an unknown name', '', TbFromBuiltin('nope'));
end;

procedure TTbTemplatesTests.TestTheMinimalTemplateWorksInBothModes;
var
  ctl: TTyStyleController;
  modes: TStringArray;
  err: string;
  ok: Boolean;
begin
  ctl := TTyStyleController.Create(nil);
  try
    ctl.Model.LoadFromCss(TbMinimalTemplate);
    modes := ctl.Model.ModeNames;
    AssertEquals('T2: two modes', 2, Length(modes));
    AssertEquals('T2: light first', 'light', modes[0]);
    AssertEquals('T2: then dark', 'dark', modes[1]);
    ctl.Mode := 'light';
    ok := TbProbeResolve(ctl.Model, err);
    AssertTrue('T2: light resolves: ' + err, ok);
    ctl.Mode := 'dark';
    ok := TbProbeResolve(ctl.Model, err);
    AssertTrue('T2: dark resolves: ' + err, ok);
  finally
    ctl.Free;
  end;
end;

procedure TTbTemplatesTests.TestTheMinimalTemplateSeeds;
const
  cSeeds: array[0..11] of string = (
    '--accent: #3B82F6;', '--surface: #FFFFFF;', '--on-surface: #1F2937;',
    '--border: #D1D5DB;', '--danger: #EF4444;', '--radius: 6px;',
    '--accent: #60A5FA;', '--surface: #1E1E1E;', '--on-surface: #E5E7EB;',
    '--border: #3F3F46;', '--danger: #F87171;', '--radius: 6px;');
  cNames: array[0..5] of string = ('--accent:', '--surface:', '--on-surface:', '--border:',
    '--danger:', '--radius:');

  function CountOf(const ASub, S: string): Integer;
  var
    p, from: Integer;
  begin
    Result := 0;
    from := 1;
    repeat
      p := Pos(ASub, Copy(S, from, MaxInt));
      if p > 0 then
      begin
        Inc(Result);
        from := from + p + Length(ASub) - 1;
      end;
    until p = 0;
  end;

var
  t, light, dark: string;
  i, darkAt: Integer;
begin
  t := TbMinimalTemplate;
  darkAt := Pos('@mode dark', t);
  AssertTrue('T3: a dark block', darkAt > 0);
  light := Copy(t, 1, darkAt - 1);
  dark := Copy(t, darkAt, MaxInt);
  for i := 0 to 5 do
  begin
    AssertTrue('T3: light ' + cSeeds[i], Pos(cSeeds[i], light) > 0);
    AssertTrue('T3: dark ' + cSeeds[i + 6], Pos(cSeeds[i + 6], dark) > 0);
    { '--surface:' is also inside '--on-surface:', so count the whole declarations }
    if cNames[i] <> '--surface:' then
      AssertEquals('T3: ' + cNames[i] + ' twice', 2, CountOf(cNames[i], t));
  end;
end;

procedure TTbTemplatesTests.TestTheMinimalTemplateLintsClean;
var
  r: TTyLintIssues;
begin
  r := TyLintCssEx(TbMinimalTemplate);
  AssertEquals('T4: no problems', 0, Length(r));
end;

initialization
  RegisterTest(TTbDocumentTests);
  RegisterTest(TTbSettingsTests);
  RegisterTest(TTbTemplatesTests);
end.
