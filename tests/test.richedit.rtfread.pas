unit test.richedit.rtfread;

{ Reading RTF into TTyRichEdit's document: Chinese (and Big5, Shift-JIS) decoded by the code
  page of the font in effect, double-byte pairs joined across groups and control words,
  \uN with its fallback, the three East Asian font slots, the formats, lists, pictures and
  tables, and everything the reader does not understand kept as the file's own bytes. The
  file's bytes are cut into a header, one range per paragraph and a trailer that together
  are the file, so a writer can put an unchanged paragraph back as it was. The samples are
  tests/fixtures/rtf (see its README.md). }

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, Graphics, fpcunit, testregistry,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.RtfRead;

type
  TTyRtfReadTest = class(TTestCase)
  private
    function Fixture(const AName: string): TBytes;
    function LoadBytes(const ABytes: TBytes; AMap: TTyRtfSourceMap = nil): TTyRichDocument;
    function LoadString(const ASource: RawByteString; AMap: TTyRtfSourceMap = nil): TTyRichDocument;
    procedure CheckTiles(const AMsg: string; const ABytes: TBytes; ADoc: TTyRichDocument;
      AMap: TTyRtfSourceMap);
    procedure CheckParas(const AMsg: string; ADoc: TTyRichDocument;
      const ALines: array of UTF8String);
  published
    // the brief
    procedure TestWordPadChineseSamplesDecode;
    procedure TestFormatsOfStyleSample;
    procedure TestBig5AndShiftJis;
    procedure TestNegativeUnicodeEscapeAndUc0;
    procedure TestADoubleByteCharSplitByAGroupStillDecodes;
    procedure TestHalvesInDifferentFontsDoNotJoin;
    procedure TestEastAsianFontSwitching;
    procedure TestUnknownContentIsKept;
    procedure TestTablesRead;
    // the rulings
    procedure TestTheLastParDoesNotMakeAParagraph;
    procedure TestRangesTileTheFile;
    procedure TestKeptBytesAreTheFileBytes;
    procedure TestFieldShowsItsResult;
    procedure TestPictures;
    procedure TestLists;
    procedure TestSpecialCharacters;
    procedure TestDefaultsAndPage;
    procedure TestTruncatedFilesLoadWhatIsThere;
    procedure TestMalformedInput;
    // for the on-demand reader (Task 6)
    procedure TestCountingAgreesAndResumesFromASnapshot;
    // what the real WordPad and Word files showed
    procedure TestGb18030AsTheFileCodePage;
    // the review of batch A
    procedure TestALaterUnknownWordReplacesTheEarlierOne;
    procedure TestARowThatHoldsANestedTableIsMarked;
  end;

implementation

function RepoRoot: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim;
end;

function FixtureDir: string;
begin
  Result := RepoRoot + 'tests' + PathDelim + 'fixtures' + PathDelim + 'rtf' + PathDelim;
end;

function ReadFileBytes(const APath: string): TBytes;
var
  f: TFileStream;
begin
  Result := nil;
  f := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[0], f.Size);
  finally
    f.Free;
  end;
end;

function BytesOf(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

function StrOf(const B: TBytes; AStart, ACount: Int64): RawByteString;
begin
  Result := '';
  SetLength(Result, ACount);
  if ACount > 0 then Move(B[AStart], Result[1], ACount);
end;

{ The bytes of a UTF8String literal, so comparisons never convert. }
function U(const S: UTF8String): RawByteString;
begin
  Result := S;
  SetCodePage(Result, CP_NONE, False);
end;

{ A code point as UTF-8 bytes (a #$xx literal here is a code point, not a byte). }
function UC(ACode: Cardinal): UTF8String;
begin
  if ACode < $80 then Result := Chr(ACode)
  else if ACode < $800 then Result := Chr($C0 or (ACode shr 6)) + Chr($80 or (ACode and $3F))
  else if ACode < $10000 then
    Result := Chr($E0 or (ACode shr 12)) + Chr($80 or ((ACode shr 6) and $3F)) +
      Chr($80 or (ACode and $3F))
  else
    Result := Chr($F0 or (ACode shr 18)) + Chr($80 or ((ACode shr 12) and $3F)) +
      Chr($80 or ((ACode shr 6) and $3F)) + Chr($80 or (ACode and $3F));
  SetCodePage(RawByteString(Result), CP_UTF8, False);
end;

function ObjChar: UTF8String;
begin
  Result := UC($FFFC);
end;

function Shown(const S: RawByteString): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if (S[i] >= ' ') and (S[i] < #$7F) then Result := Result + S[i]
    else Result := Result + '<' + IntToHex(Ord(S[i]), 2) + '>';
end;

procedure AssertText(const AMsg: string; const AExpected, AActual: RawByteString);
begin
  if (Length(AExpected) = Length(AActual)) and
     ((AExpected = '') or CompareMem(@AExpected[1], @AActual[1], Length(AExpected))) then
    Exit;
  raise EAssertionFailedError.CreateFmt('%s: expected <%s> but was <%s>',
    [AMsg, Shown(AExpected), Shown(AActual)]);
end;

function ParaText(ADoc: TTyRichDocument; AIndex: Integer): RawByteString;
begin
  Result := ADoc.Text.GetText(ADoc.Text.ParaStart(AIndex), ADoc.Text.ParaLength(AIndex));
  SetCodePage(Result, CP_NONE, False);
end;

function WithoutObjects(const S: RawByteString): RawByteString;
var
  o: RawByteString;
  i: Integer;
begin
  o := U(ObjChar);
  Result := S;
  i := Pos(o, Result);
  while i > 0 do
  begin
    Delete(Result, i, Length(o));
    i := Pos(o, Result);
  end;
end;

{ The lines of a UTF-8 file, each ended by LF. }
type
  TRawLines = array of RawByteString;

function FileLines(const APath: string): TRawLines;
var
  b: TBytes;
  s: RawByteString;
  i, start, n: Integer;
begin
  b := ReadFileBytes(APath);
  s := StrOf(b, 0, Length(b));
  Result := nil;
  n := 0;
  start := 1;
  for i := 1 to Length(s) do
    if s[i] = #10 then
    begin
      SetLength(Result, n + 1);
      Result[n] := Copy(s, start, i - start);
      Inc(n);
      start := i + 1;
    end;
  if start <= Length(s) then
    raise EAssertionFailedError.CreateFmt('%s: the last line has no LF', [APath]);
end;

function IndexOfStr(const AHay: TBytes; const ANeedle: RawByteString; AFrom: Int64 = 0): Int64;
var
  i: Int64;
begin
  if ANeedle = '' then Exit(-1);
  for i := AFrom to Int64(Length(AHay)) - Length(ANeedle) do
    if CompareMem(@AHay[i], @ANeedle[1], Length(ANeedle)) then Exit(i);
  Result := -1;
end;

{ Where the group whose brace is at AStart ends (after its closing brace), counted on the file
  itself: control symbols are skipped, so an escaped brace or backslash is no brace. }
function GroupEnd(const AB: TBytes; AStart: Int64): Int64;
var
  depth: Integer;
begin
  depth := 0;
  Result := AStart;
  while Result < Length(AB) do
  begin
    case Chr(AB[Result]) of
      '\': Inc(Result);
      '{': Inc(depth);
      '}':
        begin
          Dec(depth);
          if depth = 0 then Exit(Result + 1);
        end;
    end;
    Inc(Result);
  end;
end;

function RunIndex(const ARuns: TTyRunArray; AOffset: Integer): Integer;
begin
  Result := High(ARuns);
  while (Result > 0) and (ARuns[Result].Start > AOffset) do Dec(Result);
end;

function CharAt(ADoc: TTyRichDocument; APara, AOffset: Integer): TTyCharFormat;
var
  r: TTyRunArray;
begin
  r := ADoc.RunsOf(APara);
  Result := ADoc.Formats.CharFormat(r[RunIndex(r, AOffset)].Format);
end;

function ObjAt(ADoc: TTyRichDocument; APara, AOffset: Integer): TTyRichObject;
var
  r: TTyRunArray;
  i: Integer;
begin
  r := ADoc.RunsOf(APara);
  i := RunIndex(r, AOffset);
  if r[i].Start = AOffset then Result := r[i].Obj else Result := nil;
end;

function ParaFmt(ADoc: TTyRichDocument; APara: Integer): TTyParaFormat;
begin
  Result := ADoc.Formats.ParaFormat(ADoc.ParaFormatOf(APara));
end;

function HasFragment(const A: TTyOpaqueAttrs; const AFragment: RawByteString): Boolean;
var
  i: Integer;
begin
  for i := 0 to A.Count - 1 do
    if A.Item(i) = AFragment then Exit(True);
  Result := False;
end;

{ Every object in the paragraph, in order. }
function ObjectsOf(ADoc: TTyRichDocument; APara: Integer): TFPList;
var
  r: TTyRunArray;
  i: Integer;
begin
  Result := TFPList.Create;
  r := ADoc.RunsOf(APara);
  for i := 0 to High(r) do
    if r[i].Obj <> nil then Result.Add(r[i].Obj);
end;

function FindOpaque(ADoc: TTyRichDocument; APara: Integer;
  const APrefix: RawByteString): TTyRichOpaque;
var
  l: TFPList;
  i: Integer;
begin
  Result := nil;
  l := ObjectsOf(ADoc, APara);
  try
    for i := 0 to l.Count - 1 do
      if (TObject(l[i]) is TTyRichOpaque) and
         (Copy(TTyRichOpaque(l[i]).Bytes, 1, Length(APrefix)) = APrefix) then
        Exit(TTyRichOpaque(l[i]));
  finally
    l.Free;
  end;
end;

{ ---- helpers ---- }

function TTyRtfReadTest.Fixture(const AName: string): TBytes;
begin
  Result := ReadFileBytes(FixtureDir + AName);
end;

function TTyRtfReadTest.LoadBytes(const ABytes: TBytes; AMap: TTyRtfSourceMap): TTyRichDocument;
var
  s: TBytesStream;
begin
  Result := TTyRichDocument.Create;
  s := TBytesStream.Create(ABytes);
  try
    try
      TyRichLoadRtf(Result, s, AMap);
    except
      Result.Free;
      raise;
    end;
  finally
    s.Free;
  end;
end;

function TTyRtfReadTest.LoadString(const ASource: RawByteString;
  AMap: TTyRtfSourceMap): TTyRichDocument;
begin
  Result := LoadBytes(BytesOf(ASource), AMap);
end;

procedure TTyRtfReadTest.CheckTiles(const AMsg: string; const ABytes: TBytes;
  ADoc: TTyRichDocument; AMap: TTyRtfSourceMap);
var
  i: Integer;
  at: Int64;
begin
  AssertEquals(AMsg + ': one range per paragraph', ADoc.Text.ParaCount, AMap.ParaCount);
  AssertEquals(AMsg + ': the header starts the file', 0, AMap.Header.Start);
  at := AMap.Header.Stop;
  AssertTrue(AMsg + ': header', at >= AMap.Header.Start);
  for i := 0 to AMap.ParaCount - 1 do
  begin
    AssertEquals(Format('%s: paragraph %d starts where the one before ends', [AMsg, i]), at,
      AMap.Paras[i].Start);
    AssertTrue(Format('%s: paragraph %d is no negative range', [AMsg, i]),
      AMap.Paras[i].Stop >= AMap.Paras[i].Start);
    at := AMap.Paras[i].Stop;
  end;
  AssertEquals(AMsg + ': the trailer follows the last paragraph', at, AMap.Trailer.Start);
  AssertEquals(AMsg + ': the trailer ends the file', Int64(Length(ABytes)), AMap.Trailer.Stop);
  AssertEquals(AMsg + ': the map holds the file', Int64(Length(ABytes)), Int64(Length(AMap.Bytes)));
  if Length(ABytes) > 0 then
    AssertTrue(AMsg + ': the map holds the file''s bytes',
      CompareMem(@ABytes[0], @AMap.Bytes[0], Length(ABytes)));
end;

procedure TTyRtfReadTest.CheckParas(const AMsg: string; ADoc: TTyRichDocument;
  const ALines: array of UTF8String);
var
  i: Integer;
begin
  for i := 0 to High(ALines) do
    if i < ADoc.Text.ParaCount then
      AssertText(Format('%s: paragraph %d', [AMsg, i]), U(ALines[i]), ParaText(ADoc, i));
  AssertEquals(AMsg + ': paragraphs', Length(ALines), ADoc.Text.ParaCount);
  AssertEquals(AMsg + ': integrity', '', ADoc.Text.CheckIntegrity);
end;

{ ---- the brief ---- }

procedure TTyRtfReadTest.TestWordPadChineseSamplesDecode;
var
  sr: TSearchRec;
  base, expFile: string;
  lines: TRawLines;
  visible: Boolean;
  d: TTyRichDocument;
  i, files: Integer;
  got: RawByteString;
begin
  files := 0;
  if FindFirst(FixtureDir + '*.rtf', faAnyFile, sr) = 0 then
  try
    repeat
      base := FixtureDir + ChangeFileExt(sr.Name, '');
      visible := False;
      expFile := base + '.expected.txt';
      if not FileExists(expFile) then
      begin
        expFile := base + '.visible.txt';
        visible := True;
        if not FileExists(expFile) then Continue;
      end;
      Inc(files);
      lines := FileLines(expFile);
      d := LoadBytes(Fixture(sr.Name));
      try
        for i := 0 to High(lines) do
          if i < d.Text.ParaCount then
          begin
            got := ParaText(d, i);
            if visible then got := WithoutObjects(got);
            AssertText(Format('%s paragraph %d', [sr.Name, i]), lines[i], got);
          end;
        AssertEquals(sr.Name + ': paragraphs', Length(lines), d.Text.ParaCount);
        AssertEquals(sr.Name + ': integrity', '', d.Text.CheckIntegrity);
      finally
        d.Free;
      end;
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
  // 11 samples with an expected text and 1 with a visible text are there today; a test that
  // finds none checks nothing
  AssertTrue(Format('samples found: %d', [files]), files >= 12);
end;

procedure TTyRtfReadTest.TestFormatsOfStyleSample;
const
  Files: array[0..1] of string = ('re-styles.rtf', 'wp-styles.rtf');
var
  i: Integer;
  errors: string;

  procedure Check(const AName: string);
  var
    d: TTyRichDocument;
    c: TTyCharFormat;
    p: TTyParaFormat;
    i: Integer;
  begin
    d := LoadBytes(Fixture(AName));
    try
      AssertEquals('paragraphs', 12, d.Text.ParaCount);
      // paragraph 0: 普通，粗体，斜体，下划线，删除线，粗斜体。
      c := CharAt(d, 0, 0);
      AssertText('font', U('宋体'), c.FontName);
      AssertEquals('charset', 134, c.Charset);
      AssertEquals('size', 24, c.SizeHalfPt);
      AssertTrue('普 plain', c.Style = []);
      AssertTrue('粗 bold', CharAt(d, 0, 3).Style = [fsBold]);
      AssertTrue('， after bold plain', CharAt(d, 0, 5).Style = []);
      AssertTrue('斜 italic', CharAt(d, 0, 6).Style = [fsItalic]);
      AssertTrue('下 underlined', CharAt(d, 0, 9).Style = [fsUnderline]);
      AssertTrue('删 struck', CharAt(d, 0, 13).Strike);
      AssertFalse('， after strike', CharAt(d, 0, 16).Strike);
      AssertTrue('粗斜 bold italic', CharAt(d, 0, 17).Style = [fsBold, fsItalic]);
      AssertTrue('。 plain', CharAt(d, 0, 20).Style = []);
      // paragraph 1: H2O, E=mc2, 红字, 蓝字, 黄底, 大字, 小字.
      AssertTrue('H', CharAt(d, 1, 0).VertAlign = vaNone);
      AssertTrue('2 subscript', CharAt(d, 1, 1).VertAlign = vaSub);
      AssertTrue('O', CharAt(d, 1, 2).VertAlign = vaNone);
      AssertTrue('2 superscript', CharAt(d, 1, 9).VertAlign = vaSuper);
      AssertEquals('红 red', RGBToColor(255, 0, 0), CharAt(d, 1, 12).Color);
      AssertEquals(', auto colour', clDefault, CharAt(d, 1, 14).Color);
      AssertEquals('蓝 blue', RGBToColor(0, 112, 192), CharAt(d, 1, 16).Color);
      AssertEquals('黄 highlight', RGBToColor(255, 255, 0), CharAt(d, 1, 20).HighlightColor);
      AssertEquals(', no highlight', clNone, CharAt(d, 1, 22).HighlightColor);
      AssertEquals('大 18 pt', 36, CharAt(d, 1, 24).SizeHalfPt);
      AssertEquals('小 8 pt', 16, CharAt(d, 1, 28).SizeHalfPt);
      AssertEquals('. 12 pt', 24, CharAt(d, 1, 30).SizeHalfPt);
      // paragraph formats
      for i := 0 to 1 do
      begin
        p := ParaFmt(d, i);
        AssertTrue(Format('paragraph %d left', [i]), p.Align = paraLeft);
        AssertEquals(Format('paragraph %d indent', [i]), 0, p.LeftIndent);
        AssertTrue(Format('paragraph %d single', [i]), p.LineSpacing = lsSingle);
      end;
      AssertTrue('centred', ParaFmt(d, 2).Align = paraCenter);
      AssertTrue('right', ParaFmt(d, 3).Align = paraRight);
      AssertTrue('justified', ParaFmt(d, 4).Align = paraJustify);
      p := ParaFmt(d, 5);
      AssertTrue('5 left again', p.Align = paraLeft);
      AssertEquals('5 first', 360, p.FirstIndent);
      AssertEquals('5 left', 720, p.LeftIndent);
      AssertEquals('5 right', 360, p.RightIndent);
      p := ParaFmt(d, 6);
      AssertEquals('6 hanging', -360, p.FirstIndent);
      AssertEquals('6 left', 720, p.LeftIndent);
      AssertEquals('6 right', 0, p.RightIndent);
      AssertTrue('7 1.5', ParaFmt(d, 7).LineSpacing = ls15);
      AssertTrue('8 double', ParaFmt(d, 8).LineSpacing = lsDouble);
      p := ParaFmt(d, 9);
      AssertTrue('9 exact', p.LineSpacing = lsExact);
      AssertEquals('9 20 pt', 400, p.LineSpacingValue);
      p := ParaFmt(d, 10);
      AssertEquals('10 before', 240, p.SpaceBefore);
      AssertEquals('10 after', 120, p.SpaceAfter);
      AssertTrue('10 single', p.LineSpacing = lsSingle);
      p := ParaFmt(d, 11);
      AssertEquals('11 tabs', 3, Length(p.Tabs));
      AssertEquals('tab 1', 1440, p.Tabs[0].Position);
      AssertTrue('tab 1 left', p.Tabs[0].Align = ttaLeft);
      AssertEquals('tab 2', 4320, p.Tabs[1].Position);
      AssertTrue('tab 2 centre', p.Tabs[1].Align = ttaCenter);
      AssertEquals('tab 3', 8640, p.Tabs[2].Position);
      AssertTrue('tab 3 right', p.Tabs[2].Align = ttaRight);
      AssertEquals('10 has no tabs', 0, Length(ParaFmt(d, 10).Tabs));
    finally
      d.Free;
    end;
  end;

begin
  // what WordPad's engine streams out, and what WordPad itself saved from it (the same but for
  // \ansicpg54936); both are checked, and a failure names every file that failed
  errors := '';
  for i := 0 to High(Files) do
    try
      Check(Files[i]);
    except
      on E: EAssertionFailedError do errors := errors + Files[i] + ': ' + E.Message + '; ';
    end;
  if errors <> '' then Fail(errors);
end;

procedure TTyRtfReadTest.TestBig5AndShiftJis;
var
  d: TTyRichDocument;
begin
  d := LoadBytes(Fixture('hand-big5.rtf'));
  try
    CheckParas('big5', d, [
      '這是一份繁體中文的範例文件。',
      '許多功能都需要測試，包括標點符號「」與數字 2026。',
      '混排 TyControls 與 RichEdit 兩個英文單字。',
      '沒有字元集的字型也要讀對：臺灣、香港。']);
    AssertText('big5 font name', U('新細明體'), CharAt(d, 0, 0).FontName);
    AssertEquals('big5 charset', 136, CharAt(d, 0, 0).Charset);
    AssertText('Arial', 'Arial', CharAt(d, 2, 3).FontName);
    // f2 names no charset: its name and its text go through \ansicpg950
    AssertText('f2 name', U('細明體'), CharAt(d, 3, 0).FontName);
  finally
    d.Free;
  end;
  d := LoadBytes(Fixture('hand-sjis.rtf'));
  try
    CheckParas('sjis', d, [
      'これは日本語のサンプル文書です。',
      'ソフトウェアの表示を確認します。',
      '半角カタカナ ｱｲｳ と全角 ＡＢＣ と ASCII abc。']);
    AssertText('sjis font name', U('ＭＳ 明朝'), CharAt(d, 0, 0).FontName);
    AssertEquals('sjis charset', 128, CharAt(d, 0, 0).Charset);
  finally
    d.Free;
  end;
end;

procedure TTyRtfReadTest.TestNegativeUnicodeEscapeAndUc0;
const
  Head = '{\rtf1\ansi\ansicpg936\deff0{\fonttbl{\f0\fcharset134 S;}{\f1\fcharset0 A;}}';
var
  d: TTyRichDocument;
begin
  d := LoadBytes(Fixture('hand-uc.rtf'));
  try
    CheckParas('hand-uc', d, ['，a', '中b', '中c', '中文', '€d', '😀e', 'plain ASCII']);
  finally
    d.Free;
  end;
  // \uc0: nothing after \u is skipped, so the \'xx pair is a character of its own
  d := LoadString(Head + '{\uc0\u-244\''d6\''d0}\par}');
  try
    CheckParas('uc0', d, ['，中']);
  finally
    d.Free;
  end;
  // the default \uc1 skips one item: a character, one \'xx, or a control symbol
  d := LoadString(Head + '\u-244?x\u20013\''d6y\u20013\~z\par}');
  try
    CheckParas('uc1', d, ['，x中y中z']);
  finally
    d.Free;
  end;
  // a control word or a brace ends the fallback early
  d := LoadString(Head + '{\uc3\u20013 a\tab b}{\uc2\u25991}cd\par}');
  try
    CheckParas('cut short', d, ['中' + #9 + 'b文cd']);
  finally
    d.Free;
  end;
  // \uc is scoped by its group
  d := LoadString(Head + '{\uc2\u20013 ab}\u25991 cd\par}');
  try
    CheckParas('scoped', d, ['中文d']);
  finally
    d.Free;
  end;
  // {\upr{ansi}{\*\ud{unicode}}}: the \ud part
  d := LoadString(Head + 'x{\upr{\''d6\''d0}{\*\ud{\u20013?}}}y\par}');
  try
    CheckParas('upr', d, ['x中y']);
  finally
    d.Free;
  end;
end;

procedure TTyRtfReadTest.TestADoubleByteCharSplitByAGroupStillDecodes;
var
  d: TTyRichDocument;
begin
  d := LoadBytes(Fixture('hand-split-dbcs.rtf'));
  try
    AssertEquals('paragraphs', 4, d.Text.ParaCount);
    AssertText('split by a group end', U('x中y'), ParaText(d, 0));
    AssertText('split by a control word', U('x中y'), ParaText(d, 1));
    AssertText('split by a group start', U('x中y'), ParaText(d, 2));
  finally
    d.Free;
  end;
  // a trail byte below 0x80 may be written as the character itself (81 40 is 丂 in GBK)
  d := LoadString('{\rtf1\ansi\ansicpg936{\fonttbl{\f0\fcharset134 S;}}\f0 a\''81@b\par}');
  try
    CheckParas('literal trail byte', d, ['a丂b']);
  finally
    d.Free;
  end;
end;

procedure TTyRtfReadTest.TestHalvesInDifferentFontsDoNotJoin;
var
  d: TTyRichDocument;
begin
  d := LoadBytes(Fixture('hand-split-dbcs.rtf'));
  try
    AssertText('different fonts', U('x?Ðy'), ParaText(d, 3));
  finally
    d.Free;
  end;
  // the same code page in two fonts is still two fonts
  d := LoadString('{\rtf1\ansi\ansicpg936{\fonttbl{\f0\fcharset134 S;}{\f1\fcharset134 H;}}' +
    '\f0 x\''d6\f1\''d6\''d0 y\par}');
  try
    CheckParas('two GBK fonts', d, ['x?中 y']);
  finally
    d.Free;
  end;
end;

procedure TTyRtfReadTest.TestEastAsianFontSwitching;
var
  d: TTyRichDocument;
  c: TTyCharFormat;
begin
  d := LoadBytes(Fixture('hand-word-zh.rtf'));
  try
    // TyControls 的富文本控件 4.0
    c := CharAt(d, 0, 0);
    AssertText('Latin', 'Calibri', c.FontName);
    AssertEquals('Latin charset', 0, c.Charset);
    c := CharAt(d, 0, 11);
    AssertText('Chinese', U('宋体'), c.FontName);
    AssertEquals('Chinese charset', 134, c.Charset);
    AssertText('4.0', 'Calibri', CharAt(d, 0, 19).FontName);
    // café 和 naïve 里的重音字母
    AssertText('é decoded in 1252', U('café 和 naïve 里的重音字母'), ParaText(d, 1));
    AssertText('é', 'Calibri', CharAt(d, 1, 3).FontName);
    AssertText('和', U('宋体'), CharAt(d, 1, 5).FontName);
    AssertText('ï', 'Calibri', CharAt(d, 1, 9).FontName);
    AssertText('\u text', U('宋体'), CharAt(d, 2, 0).FontName);
  finally
    d.Free;
  end;
  // the same in what Word itself saved
  d := LoadBytes(Fixture('word-zh.rtf'));
  try
    // TyControls 的富文本控件 4.0，用 Word 保存。
    c := CharAt(d, 0, 0);
    AssertText('Word: Latin', 'Calibri', c.FontName);
    AssertEquals('Word: Latin charset', 0, c.Charset);
    c := CharAt(d, 0, 11);
    AssertText('Word: Chinese', U('宋体'), c.FontName);
    AssertEquals('Word: Chinese charset', 134, c.Charset);
    AssertText('Word: 4.0', 'Calibri', CharAt(d, 0, 18).FontName);
    AssertText('Word: ，', U('宋体'), CharAt(d, 0, 21).FontName);
    AssertText('Word: Word', 'Calibri', CharAt(d, 0, 24).FontName);
    // café 和 naïve ...: é is the GBK pair a8 a6 in the East Asian font; ï is \'ef in the
    // high-ANSI slot in the middle of a Latin run
    AssertText('Word: é decoded', U('café 和 naïve'), Copy(ParaText(d, 1), 1, Length(U('café 和 naïve'))));
    AssertText('Word: c', 'Calibri', CharAt(d, 1, 0).FontName);
    AssertText('Word: é in the East Asian font', U('宋体'), CharAt(d, 1, 3).FontName);
    AssertText('Word: 和', U('宋体'), CharAt(d, 1, 5).FontName);
    AssertText('Word: ï', 'Calibri', CharAt(d, 1, 9).FontName);
    AssertText('Word: v after ï', 'Calibri', CharAt(d, 1, 10).FontName);
    // 这一段的中文用黑体，English stays Calibri。
    AssertText('Word: 黑体', U('黑体'), CharAt(d, 2, 0).FontName);
    AssertText('Word: English in 黑体''s paragraph', 'Calibri', CharAt(d, 2, 10).FontName);
    AssertText('Word: 。 in 黑体', U('黑体'), CharAt(d, 2, 31).FontName);
    // 表情 😀 和生僻字 龘 ...: the emoji is one character
    AssertEquals('Word: the emoji is one character', 21, d.Text.ParaLength(3));
    AssertText('Word: the emoji', U(UC($1F600)), Copy(ParaText(d, 3), 8, 4));
    AssertText('Word: 和 after it', U('宋体'), CharAt(d, 3, 5).FontName);
    // 粗体的中文 and bold English，后面是普通的。
    AssertTrue('Word: bold Chinese', fsBold in CharAt(d, 4, 0).Style);
    AssertTrue('Word: bold English', fsBold in CharAt(d, 4, 21).Style);
    AssertText('Word: bold English in Calibri', 'Calibri', CharAt(d, 4, 21).FontName);
    AssertFalse('Word: ， plain', fsBold in CharAt(d, 4, 22).Style);
  finally
    d.Free;
  end;
  // one run, three slots: each character takes the font of its class
  d := LoadString('{\rtf1\ansi\ansicpg936{\fonttbl{\f0\fcharset134 S;}{\f1\fcharset0 L;}}' +
    '\loch\af1\hich\af1\dbch\f0 ab\''d6\''d0\par}');
  try
    CheckParas('slots', d, ['ab中']);
    AssertText('a: the low-ANSI slot', 'L', CharAt(d, 0, 0).FontName);
    AssertText('中: the double-byte slot', 'S', CharAt(d, 0, 2).FontName);
  finally
    d.Free;
  end;
end;

procedure TTyRtfReadTest.TestUnknownContentIsKept;
var
  b: TBytes;
  m: TTyRtfSourceMap;
  d: TTyRichDocument;
  o: TTyRichOpaque;
  formula: RawByteString;
  errors: string;

  { The object's bytes are where they are in the file, inside its paragraph; a group is the
    whole group, from its brace to the one that closes it. }
  procedure CheckOpaque(const AWhat: string; APara: Integer; const APrefix: RawByteString);
  var
    at: Int64;
  begin
    o := FindOpaque(d, APara, APrefix);
    AssertNotNull(AWhat + ': an object', o);
    at := IndexOfStr(b, o.Bytes, m.Paras[APara].Start);
    AssertTrue(AWhat + ': its bytes are in the file', at >= 0);
    AssertTrue(AWhat + ': inside its paragraph', at + Length(o.Bytes) <= m.Paras[APara].Stop);
    if o.Bytes[1] = '{' then
      AssertEquals(AWhat + ': the whole group', GroupEnd(b, at), at + Length(o.Bytes));
  end;

  procedure Check(const AName: string; const AField, AAnchor, AComment, AFormula,
    ADataStore: RawByteString; ADeletedStop: Integer);
  var
    header, trailer: RawByteString;
    r: TTyRunArray;
    i: Integer;
    revised, deleted: Boolean;
  begin
    b := Fixture(AName);
    m := TTyRtfSourceMap.Create;
    d := LoadBytes(b, m);
    try
      header := StrOf(b, m.Header.Start, m.Header.Stop - m.Header.Start);
      trailer := StrOf(b, m.Trailer.Start, m.Trailer.Stop - m.Trailer.Start);
      // the style: the style sheet in the header, \s1 on the paragraph
      AssertTrue('style sheet in the header', Pos('{\stylesheet{', header) > 0);
      AssertTrue('\s1 on the heading', HasFragment(ParaFmt(d, 0).Extra, '\s1'));
      AssertFalse('no \s1 on the next paragraph', HasFragment(ParaFmt(d, 1).Extra, '\s1'));
      // the field
      CheckOpaque('field', 1, AField);
      AssertText('field result', U('链接'), o.DisplayText);
      AssertText('the field''s bytes', '}}}', Copy(o.Bytes, Length(o.Bytes) - 2, 3));
      // the revisions: the table in the header, the marks on the runs
      AssertTrue('revision table in the header',
        Pos('{\*\revtbl {Unknown;}{TyControls;}}', header) > 0);
      r := d.RunsOf(2);
      revised := False;
      deleted := False;
      for i := 0 to High(r) do
      begin
        if HasFragment(d.Formats.CharFormat(r[i].Format).Extra, '\revised') then revised := True;
        if HasFragment(d.Formats.CharFormat(r[i].Format).Extra, '\deleted') then deleted := True;
      end;
      AssertTrue('inserted text marked', revised);
      AssertTrue('deleted text marked', deleted);
      // 修订：新加的字原来的字。
      AssertTrue('the inserted text''s run', HasFragment(CharAt(d, 2, 3).Extra, '\revised'));
      AssertFalse('text before it is no revision', HasFragment(CharAt(d, 2, 0).Extra, '\revised'));
      AssertTrue('the deleted text''s run', HasFragment(CharAt(d, 2, 7).Extra, '\deleted'));
      AssertFalse('the deleted text is no insertion', HasFragment(CharAt(d, 2, 7).Extra, '\revised'));
      if ADeletedStop < d.Text.ParaLength(2) then
        AssertFalse('text after it is no deletion',
          HasFragment(CharAt(d, 2, ADeletedStop).Extra, '\deleted'));
      // the comment
      CheckOpaque('comment anchor', 3, AAnchor);
      CheckOpaque('comment end', 3, '{\*\atrfend ');
      CheckOpaque('comment', 3, AComment);
      CheckOpaque('comment mark', 3, '\chatn ');
      // the footnote, the formula, the bookmark
      CheckOpaque('footnote mark', 4, '\chftn ');
      CheckOpaque('footnote', 4, '{\footnote \ltrpar');
      CheckOpaque('formula', 5, AFormula);
      formula := o.Bytes;
      CheckOpaque('bookmark', 6, '{\*\bkmkstart mark1}');
      CheckOpaque('bookmark end', 6, '{\*\bkmkend mark1}');
      // Word's blocks after the last paragraph
      AssertTrue('theme', Pos('{\*\themedata 504b', trailer) = 1);
      AssertTrue('data store', Pos(ADataStore, trailer) > 0);
      AssertTrue('latent styles', Pos('{\*\latentstyles', trailer) > 0);
      CheckTiles(AName, b, d, m);
    finally
      d.Free;
      m.Free;
    end;
  end;

begin
  // both files are checked; a failure names every file that failed
  errors := '';
  try
    Check('hand-word-unknown.rtf', '{\field{\*\fldinst', '{\*\atrfstart 1}',
      '{\*\annotation{\*\atnref 1}', '{\mmath {\*\moMath', '{\*\datastore 0105000002000000}}', 11);
  except
    on E: EAssertionFailedError do errors := errors + 'hand-word-unknown.rtf: ' + E.Message + '; ';
  end;
  // what Word saved: a field Word may edit, a comment numbered by Word, the formula with its
  // picture fallback (\mmathPict: a PNG and a metafile of it) inside the one object
  try
    Check('word-unknown.rtf', '{\field\fldedit{\*\fldinst', '{\*\atrfstart 2028305068}',
      '{\*\annotation{\*\atnref 2028305068}', '{\mmath{\*\moMath', '{\*\datastore 01050000'#13#10, 9);
    AssertTrue('the formula keeps its fallback picture', Pos('{\mmathPict{\*\shppict', formula) > 0);
  except
    on E: EAssertionFailedError do errors := errors + 'word-unknown.rtf: ' + E.Message + '; ';
  end;
  if errors <> '' then Fail(errors);
end;

procedure TTyRtfReadTest.TestTablesRead;
var
  d: TTyRichDocument;
  t: TTyRichTable;
  i, f, l: Integer;
begin
  // the real files first, so that a reader change shows on them before the stand-ins
  // a table copied from Word and pasted into WordPad, as WordPad saved it
  d := LoadBytes(Fixture('wp-zh-table.rtf'));
  try
    CheckParas('wp table', d, ['表格是从 Word 复制来的：', '品名', '数量', '单价', '铅笔 pencil',
      '12', '1.50', '', '表格后的段落。']);
    AssertNull('wp: before the table', d.TableAt(0));
    t := d.TableAt(1);
    AssertNotNull('wp: a table', t);
    for i := 1 to 6 do
      AssertSame(Format('wp: one table, paragraph %d', [i]), t, d.TableAt(i));
    AssertNull('wp: after the table', d.TableAt(7));
    AssertNull('wp: the last paragraph', d.TableAt(8));
    AssertFalse('wp: not locked', t.StructureLocked);
    AssertEquals('wp: rows', 2, t.RowCount);
    AssertEquals('wp: cells', 6, t.CellCount);
    for i := 1 to 6 do
    begin
      AssertSame(Format('wp: paragraph %d row', [i]), t.Rows[(i - 1) div 3], d.CellAt(i).Row);
      AssertEquals(Format('wp: paragraph %d cell', [i]), (i - 1) mod 3, d.CellAt(i).Index);
    end;
    AssertTrue('wp: Word''s borders in the row', Pos('\trbrdr', t.Rows[0].RawFormat) > 0);
  finally
    d.Free;
  end;
  // what Word saved: two cells merged across are one wider cell
  d := LoadBytes(Fixture('word-table-merged.rtf'));
  try
    CheckParas('Word merged', d, ['表格前', '跨两列', 'C', '跨两行', 'E', 'F', '', 'G', '内一',
      '内二', '', '表格后']);
    t := d.TableAt(1);
    AssertNotNull('Word merged: a table', t);
    AssertNull('Word merged: before', d.TableAt(0));
    AssertNull('Word merged: after', d.TableAt(11));
    for i := 1 to 10 do
      AssertSame(Format('Word merged: one table, paragraph %d', [i]), t, d.TableAt(i));
    AssertTrue('Word merged: locked', t.StructureLocked);
    AssertEquals('Word merged: rows', 3, t.RowCount);
    AssertEquals('Word merged: row 1 is two cells', 2, t.Rows[0].CellCount);
    AssertEquals('Word merged: row 2', 3, t.Rows[1].CellCount);
    AssertEquals('Word merged: row 3', 3, t.Rows[2].CellCount);
    AssertSame('Word merged: 跨两列', t.Rows[0], d.CellAt(1).Row);
    AssertEquals('Word merged: 跨两列 is cell 0', 0, d.CellAt(1).Index);
    AssertEquals('Word merged: C is cell 1', 1, d.CellAt(2).Index);
    AssertSame('Word merged: the cell merged down', t.Rows[2], d.CellAt(6).Row);
    AssertEquals('Word merged: G', 1, d.CellAt(7).Index);
    AssertTrue('Word merged: the last cell', d.CellParas(1, t.Rows[2].Cells[2], f, l));
    AssertEquals('Word merged: the last cell: first', 8, f);
    AssertEquals('Word merged: the last cell: last', 10, l);
  finally
    d.Free;
  end;
  d := LoadBytes(Fixture('re-zh-table.rtf'));
  try
    AssertEquals('paragraphs', 11, d.Text.ParaCount);
    AssertNull('before the table', d.TableAt(0));
    AssertNull('after the table', d.TableAt(10));
    t := d.TableAt(1);
    AssertNotNull('a table', t);
    for i := 1 to 9 do
      AssertSame(Format('one table, paragraph %d', [i]), t, d.TableAt(i));
    AssertEquals('rows', 3, t.RowCount);
    AssertEquals('cells', 9, t.CellCount);
    AssertFalse('not locked', t.StructureLocked);
    AssertEquals('columns', 3, t.ColBoundaryCount);
    AssertEquals('column 1', 2400, t.ColBoundaries[0]);
    AssertEquals('column 3', 7200, t.ColBoundaries[2]);
    for i := 0 to 2 do
    begin
      AssertEquals(Format('row %d cells', [i]), 3, t.Rows[i].CellCount);
      AssertEquals(Format('row %d boundaries', [i]), 3, t.Rows[i].BoundaryCount);
      AssertTrue(Format('row %d raw format', [i]), Pos('\trowd\trgaph108', t.Rows[i].RawFormat) = 1);
      AssertTrue(Format('row %d raw format end', [i]), Pos('\cellx7200', t.Rows[i].RawFormat) > 0);
    end;
    for i := 1 to 9 do
    begin
      AssertSame(Format('paragraph %d row', [i]), t.Rows[(i - 1) div 3], d.CellAt(i).Row);
      AssertEquals(Format('paragraph %d cell', [i]), (i - 1) mod 3, d.CellAt(i).Index);
    end;
    AssertText('cell 1,2', U('研发 R&D'), ParaText(d, 5));
    AssertText('cell 2,2', U('两个字'), ParaText(d, 9));
  finally
    d.Free;
  end;
  d := LoadBytes(Fixture('hand-word-table-merged.rtf'));
  try
    AssertEquals('paragraphs', 13, d.Text.ParaCount);
    t := d.TableAt(1);
    AssertNotNull('merged: a table', t);
    AssertNull('merged: before', d.TableAt(0));
    AssertNull('merged: after', d.TableAt(12));
    AssertSame('merged: the last cell', t, d.TableAt(11));
    AssertTrue('merged cells lock the structure', t.StructureLocked);
    AssertEquals('merged: rows', 3, t.RowCount);
    for i := 0 to 2 do
      AssertEquals(Format('merged: row %d cells', [i]), 3, t.Rows[i].CellCount);
    AssertEquals('merged: columns', 3, t.ColBoundaryCount);
    AssertEquals('merged: column 3', 8412, t.ColBoundaries[2]);
    // the nested table's two cells and the cell's own paragraph are the outer cell's
    AssertTrue('the last cell', d.CellParas(1, t.Rows[2].Cells[2], f, l));
    AssertEquals('the last cell: first', 9, f);
    AssertEquals('the last cell: last', 11, l);
    AssertText('nested one', U('内一'), ParaText(d, 9));
    AssertText('nested two', U('内二'), ParaText(d, 10));
    AssertTrue('Word''s row definition', Pos('\trowd \irow2', t.Rows[2].RawFormat) = 1);
  finally
    d.Free;
  end;
  // merged cells alone lock (across, and down)
  d := LoadString('{\rtf1 \trowd\clmgf\cellx1000\clmrg\cellx2000\pard\intbl a\cell\cell\row' +
    '\pard b\par}');
  try
    CheckParas('merged across', d, ['a', '', 'b']);
    AssertTrue('merged across: locked', d.TableAt(0).StructureLocked);
  finally
    d.Free;
  end;
  d := LoadString('{\rtf1 \trowd\clvmgf\cellx1000\cellx2000\pard\intbl a\cell b\cell\row' +
    '\trowd\clvmrg\cellx1000\cellx2000\pard\intbl\cell c\cell\row\pard d\par}');
  try
    CheckParas('merged down', d, ['a', 'b', '', 'c', 'd']);
    AssertTrue('merged down: locked', d.TableAt(0).StructureLocked);
    AssertEquals('merged down: rows', 2, d.TableAt(0).RowCount);
  finally
    d.Free;
  end;
  // a nested table alone locks too
  d := LoadString('{\rtf1 \trowd\cellx1000\cellx2000\pard\intbl a\cell \pard\intbl\itap2 x' +
    '\nestcell{\*\nesttableprops\trowd\cellx500\nestrow}{\nonesttables\par}\pard\intbl\cell' +
    '\row\pard b\par}');
  try
    CheckParas('nested', d, ['a', 'x', '', 'b']);
    AssertNotNull('nested: table', d.TableAt(0));
    AssertTrue('nested: locked', d.TableAt(0).StructureLocked);
    AssertEquals('nested: one row of two cells', 2, d.TableAt(0).CellCount);
  finally
    d.Free;
  end;
end;

{ ---- the rulings ---- }

procedure TTyRtfReadTest.TestTheLastParDoesNotMakeAParagraph;
var
  d: TTyRichDocument;
begin
  d := LoadString('{\rtf1 A\par}');
  try
    CheckParas('one \par', d, ['A']);
  finally
    d.Free;
  end;
  d := LoadString('{\rtf1 A\par\par}');
  try
    CheckParas('two \par', d, ['A', '']);
  finally
    d.Free;
  end;
  d := LoadString('{\rtf1 A\par B}');
  try
    CheckParas('text after the \par', d, ['A', 'B']);
  finally
    d.Free;
  end;
  d := LoadString('{\rtf1 A\par\pard\qc }');
  try
    CheckParas('formatting after the last \par', d, ['A']);
  finally
    d.Free;
  end;
  d := LoadString('{\rtf1 }');
  try
    CheckParas('nothing', d, ['']);
  finally
    d.Free;
  end;
  d := LoadBytes(Fixture('re-zh-plain.rtf'));
  try
    AssertEquals('WordPad''s file', 5, d.Text.ParaCount);
    AssertText('its empty paragraph', '', ParaText(d, 3));
  finally
    d.Free;
  end;
end;

procedure TTyRtfReadTest.TestRangesTileTheFile;
const
  Inline: array[0..6] of RawByteString = (
    '{\rtf1 A\par}', '{\rtf1 }', '{\rtf1 {\b A}}', '{\rtf1 {\b A\par B\par} C\par}',
    '{\rtf1{\fonttbl{\f0 X;}}\f0 A}}trailing', '{\rtf1 A', '{\rtf1{\*\bkmkstart x}A\par}');
var
  sr: TSearchRec;
  b: TBytes;
  m: TTyRtfSourceMap;
  d: TTyRichDocument;
  i, files: Integer;
begin
  files := 0;
  if FindFirst(FixtureDir + '*.rtf', faAnyFile, sr) = 0 then
  try
    repeat
      Inc(files);
      b := Fixture(sr.Name);
      m := TTyRtfSourceMap.Create;
      d := LoadBytes(b, m);
      try
        CheckTiles(sr.Name, b, d, m);
      finally
        d.Free;
        m.Free;
      end;
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
  AssertTrue('samples', files >= 12);
  for i := 0 to High(Inline) do
  begin
    b := BytesOf(Inline[i]);
    m := TTyRtfSourceMap.Create;
    d := LoadBytes(b, m);
    try
      CheckTiles(Shown(Inline[i]), b, d, m);
    finally
      d.Free;
      m.Free;
    end;
  end;
  // where the cuts fall: WordPad's header ends before the first \pard, every paragraph is
  // one line with its \par and line break, the trailer is "}", CR LF, NUL
  b := Fixture('re-zh-plain.rtf');
  m := TTyRtfSourceMap.Create;
  d := LoadBytes(b, m);
  try
    AssertText('header end', '\viewkind4\uc1 '#13#10,
      StrOf(b, m.Header.Stop - 17, 17));
    AssertText('paragraph 0 start', '\pard\f0\fs24\''b8',
      StrOf(b, m.Paras[0].Start, 17));
    AssertText('paragraph 0 end', '\par'#13#10, StrOf(b, m.Paras[0].Stop - 6, 6));
    AssertText('the empty paragraph', '\par'#13#10,
      StrOf(b, m.Paras[3].Start, m.Paras[3].Stop - m.Paras[3].Start));
    AssertText('trailer', '}'#13#10#0, StrOf(b, m.Trailer.Start, m.Trailer.Stop - m.Trailer.Start));
  finally
    d.Free;
    m.Free;
  end;
  // a table row's end belongs to its last cell; Word's group around a paragraph's \par too
  b := Fixture('re-zh-table.rtf');
  m := TTyRtfSourceMap.Create;
  d := LoadBytes(b, m);
  try
    AssertText('last cell of row 1', '\cell\row', StrOf(b, m.Paras[3].Stop - 9, 9));
    AssertText('row 2 starts with its definition', '\trowd', StrOf(b, m.Paras[4].Start, 6));
    AssertText('last cell', '\cell\row '#13#10, StrOf(b, m.Paras[9].Stop - 12, 12));
  finally
    d.Free;
    m.Free;
  end;
  b := Fixture('hand-word-zh.rtf');
  m := TTyRtfSourceMap.Create;
  d := LoadBytes(b, m);
  try
    AssertText('Word: header end', '\sftnbj ', StrOf(b, m.Header.Stop - 8, 8));
    AssertText('Word: paragraph start', '\pard\plain', StrOf(b, m.Paras[0].Start, 11));
    AssertText('Word: paragraph end', '\par }', StrOf(b, m.Paras[0].Stop - 6, 6));
    AssertText('Word: trailer', '{\*\themedata', StrOf(b, m.Trailer.Start, 13));
  finally
    d.Free;
    m.Free;
  end;
end;

procedure TTyRtfReadTest.TestKeptBytesAreTheFileBytes;
var
  sr: TSearchRec;
  b: TBytes;
  m: TTyRtfSourceMap;
  d: TTyRichDocument;
  p, i, j, kept: Integer;
  r: TTyRunArray;
  pf: TTyParaFormat;
  cf: TTyCharFormat;
  t: TTyRichTable;

  { An object is inside its paragraph's bytes. A property fragment is somewhere before the
    paragraph's end: properties hold from where they are written on, across paragraphs. }
  procedure Check(const AWhat: string; APara: Integer; const AFragment: RawByteString;
    AInside: Boolean);
  var
    at: Int64;
  begin
    if AInside then at := IndexOfStr(b, AFragment, m.Paras[APara].Start)
    else at := IndexOfStr(b, AFragment);
    AssertTrue(Format('%s %s paragraph %d: %s is the file''s bytes', [sr.Name, AWhat, APara,
      Shown(Copy(AFragment, 1, 40))]), (at >= 0) and
      (at + Length(AFragment) <= m.Paras[APara].Stop));
    Inc(kept);
  end;

begin
  kept := 0;
  if FindFirst(FixtureDir + '*.rtf', faAnyFile, sr) = 0 then
  try
    repeat
      b := Fixture(sr.Name);
      m := TTyRtfSourceMap.Create;
      d := LoadBytes(b, m);
      try
        for p := 0 to d.Text.ParaCount - 1 do
        begin
          pf := ParaFmt(d, p);
          for j := 0 to pf.Extra.Count - 1 do
            Check('paragraph extra', p, pf.Extra.Item(j), False);
          r := d.RunsOf(p);
          for i := 0 to High(r) do
          begin
            cf := d.Formats.CharFormat(r[i].Format);
            for j := 0 to cf.Extra.Count - 1 do Check('run extra', p, cf.Extra.Item(j), False);
            if r[i].Obj is TTyRichOpaque then
              Check('object', p, TTyRichOpaque(r[i].Obj).Bytes, True)
            else if r[i].Obj is TTyRichPicture then
              Check('picture', p, TTyRichPicture(r[i].Obj).RawRtf, True);
          end;
          t := d.TableAt(p);
          if (t <> nil) and (d.CellAt(p).Index = 0) then
            AssertTrue(sr.Name + ' row format', IndexOfStr(b, d.CellAt(p).Row.RawFormat) >= 0);
        end;
      finally
        d.Free;
        m.Free;
      end;
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
  AssertTrue(Format('fragments checked: %d', [kept]), kept > 100);
end;

procedure TTyRtfReadTest.TestFieldShowsItsResult;
const
  Src: RawByteString = '{\rtf1\ansi\ansicpg936{\fonttbl{\f0\fcharset134 S;}}\f0 a{\field' +
    '{\*\fldinst HYPERLINK "x"}{\fldrslt {\b \''c1\''b4\u25991?}}}b\par}';
var
  d: TTyRichDocument;
  o, c: TTyRichObject;
begin
  d := LoadString(Src);
  try
    CheckParas('field', d, ['a' + ObjChar + 'b']);
    o := ObjAt(d, 0, 1);
    AssertTrue('an opaque object', o is TTyRichOpaque);
    AssertText('display text', U('链文'), TTyRichOpaque(o).DisplayText);
    AssertText('bytes', Copy(Src, Pos('{\field', Src), Pos('}}}b', Src) + 3 - Pos('{\field', Src)),
      TTyRichOpaque(o).Bytes);
    c := o.Clone;
    try
      AssertText('clone keeps it', TTyRichOpaque(o).DisplayText, TTyRichOpaque(c).DisplayText);
    finally
      c.Free;
    end;
    AssertFalse('b is not bold', fsBold in CharAt(d, 0, 2).Style);
  finally
    d.Free;
  end;
end;

procedure TTyRtfReadTest.TestPictures;
const
  Png: array[0..7] of Byte = ($89, $50, $4E, $47, $0D, $0A, $1A, $0A);
var
  b: TBytes;
  d: TTyRichDocument;
  p: TTyRichPicture;
  o: TTyRichObject;
  raw: RawByteString;
begin
  b := Fixture('re-zh-picture.rtf');
  d := LoadBytes(b);
  try
    o := ObjAt(d, 1, 0);
    AssertTrue('picture starting a paragraph', o is TTyRichPicture);
    p := TTyRichPicture(o);
    AssertTrue('png', p.PictureFormat = rpfPng);
    AssertTrue('png signature', (Length(p.Data) > 8) and CompareMem(@p.Data[0], @Png[0], 8));
    AssertEquals('PNG data length', 211, Length(p.Data));
    AssertEquals('width', 720, p.WidthTwips);
    AssertEquals('height', 480, p.HeightTwips);
    AssertText('raw start', '{\pict{\*\picprop', Copy(p.RawRtf, 1, 17));
    AssertText('raw end', '426082'#13#10'}', Copy(p.RawRtf, Length(p.RawRtf) - 8, 9));
    AssertTrue('raw is the file''s', IndexOfStr(b, p.RawRtf) > 0);
    o := ObjAt(d, 2, 11);
    AssertTrue('picture inside a line', o is TTyRichPicture);
    p := TTyRichPicture(o);
    AssertEquals('width 2', 360, p.WidthTwips);
    AssertEquals('height 2', 240, p.HeightTwips);
    AssertTrue('png 2', CompareMem(@p.Data[0], @Png[0], 8));
  finally
    d.Free;
  end;
  // Word's pair: one picture, the pair's bytes, shown as the first; scaling; \bin
  raw := '{\*\shppict{\pict\pngblip\picwgoal1000\pichgoal800\picscalex50\picscaley25 89504e47}}' +
    '{\nonshppict{\pict\wmetafile8\picwgoal1000\pichgoal800 0102}}';
  d := LoadString('{\rtf1 a' + raw + 'b{\pict\jpegblip\picw10\pich20\bin4 {}\\}x\par}');
  try
    CheckParas('pair', d, ['a' + ObjChar + 'b' + ObjChar + 'x']);
    p := ObjAt(d, 0, 1) as TTyRichPicture;
    AssertTrue('the pair shows the first', p.PictureFormat = rpfPng);
    AssertEquals('the pair: 4 bytes', 4, Length(p.Data));
    AssertEquals('scaled width', 500, p.WidthTwips);
    AssertEquals('scaled height', 200, p.HeightTwips);
    AssertText('the pair''s bytes', raw, p.RawRtf);
    p := ObjAt(d, 0, 3) as TTyRichPicture;
    AssertTrue('jpeg', p.PictureFormat = rpfJpeg);
    AssertEquals('\bin data', 4, Length(p.Data));
    AssertEquals('\bin data: the brace is data', Ord('{'), p.Data[0]);
    AssertEquals('pixels to twips', 150, p.WidthTwips);
    AssertEquals('pixels to twips (height)', 300, p.HeightTwips);
  finally
    d.Free;
  end;
end;

procedure TTyRtfReadTest.TestLists;
var
  d: TTyRichDocument;
  i: Integer;
  l: TTyListFormat;
begin
  d := LoadBytes(Fixture('re-zh-list.rtf'));
  try
    AssertEquals('paragraphs', 9, d.Text.ParaCount);
    for i := 0 to 8 do
    begin
      l := ParaFmt(d, i).List;
      case i of
        1..3:
          begin
            AssertTrue(Format('%d bullet', [i]), l.Kind = lkBullet);
            AssertEquals(Format('%d level', [i]), 0, l.Level);
          end;
        5..7:
          begin
            AssertTrue(Format('%d decimal', [i]), l.Kind = lkDecimal);
            AssertEquals(Format('%d level', [i]), 0, l.Level);
            AssertEquals(Format('%d start', [i]), 1, l.StartAt);
          end;
      else
        AssertTrue(Format('%d no list', [i]), l.Kind = lkNone);
      end;
    end;
    AssertEquals('list indent', 720, ParaFmt(d, 1).LeftIndent);
    AssertEquals('list hanging', -360, ParaFmt(d, 1).FirstIndent);
    // what TTyListFormat cannot say stays on the paragraph
    AssertTrue('bullet font', HasFragment(ParaFmt(d, 1).Extra, '\pnf1'));
    AssertTrue('bullet text', HasFragment(ParaFmt(d, 1).Extra, '{\pntxtb\''B7}'));
  finally
    d.Free;
  end;
  d := LoadString('{\rtf1{\*\listtable{\list\listtemplateid1{\listlevel\levelnfc4\levelstartat3' +
    '{\leveltext\''02\''00.;}{\levelnumbers\''01;}}{\listlevel\levelnfc2\levelstartat1' +
    '{\leveltext\''02\''01.;}{\levelnumbers\''01;}}\listid77}{\list{\listlevel\levelnfc23' +
    '{\leveltext\''01\u8226 ?;}}\listid88}}{\*\listoverridetable{\listoverride\listid77' +
    '\listoverridecount0\ls1}{\listoverride\listid88\listoverridecount0\ls2}}' +
    '\pard\ls1{\listtext a.\tab}one\par\ls1\ilvl1{\listtext i.\tab}two\par\pard\ls2 three\par' +
    '\pard\ls9 four\par\pard\pnlvl3\pnucrm\pnstart4 five\par\pard\pnlvlbody\pnucltr six\par}');
  try
    CheckParas('Word lists', d, ['one', 'two', 'three', 'four', 'five', 'six']);
    l := ParaFmt(d, 0).List;
    AssertTrue('lower letter', l.Kind = lkLowerAlpha);
    AssertEquals('starts at 3', 3, l.StartAt);
    AssertEquals('level 0', 0, l.Level);
    l := ParaFmt(d, 1).List;
    AssertTrue('lower roman', l.Kind = lkLowerRoman);
    AssertEquals('level 1', 1, l.Level);
    AssertTrue('bullet', ParaFmt(d, 2).List.Kind = lkBullet);
    AssertTrue('the reference stays', HasFragment(ParaFmt(d, 2).Extra, '\ls2 '));
    AssertTrue('unknown list', ParaFmt(d, 3).List.Kind = lkNone);
    AssertTrue('unknown list kept', HasFragment(ParaFmt(d, 3).Extra, '\ls9 '));
    l := ParaFmt(d, 4).List;
    AssertTrue('upper roman', l.Kind = lkUpperRoman);
    AssertEquals('pn level', 2, l.Level);
    AssertEquals('pn start', 4, l.StartAt);
    AssertTrue('upper letter', ParaFmt(d, 5).List.Kind = lkUpperAlpha);
  finally
    d.Free;
  end;
end;

procedure TTyRtfReadTest.TestSpecialCharacters;
var
  d: TTyRichDocument;
begin
  d := LoadString('{\rtf1 a\line b\tab c\~d\_e\-f\ldblquote\rdblquote\lquote\rquote\emdash' +
    '\endash\bullet\emspace\enspace\qmspace\{\}\\'#13#10'g'#9'h\par}');
  try
    CheckParas('specials', d, ['a'#11'b'#9'c' + UC($A0) + 'd' + UC($2011) + 'ef' +
      UC($201C) + UC($201D) + UC($2018) + UC($2019) + UC($2014) + UC($2013) + UC($2022) +
      UC($2003) + UC($2002) + UC($2005) + '{}\g'#9'h']);
    AssertTrue('the optional hyphen rides on the character after it',
      HasFragment(CharAt(d, 0, 9).Extra, '\-'));
    AssertFalse('only on that one', HasFragment(CharAt(d, 0, 10).Extra, '\-'));
    AssertFalse('nor before it', HasFragment(CharAt(d, 0, 8).Extra, '\-'));
  finally
    d.Free;
  end;
  // a backslash before a line break is a \par
  d := LoadString('{\rtf1 a\'#13#10'b\par}');
  try
    CheckParas('\<CR><LF>', d, ['a', 'b']);
  finally
    d.Free;
  end;
  // unknown character words ride on the run, unknown paragraph words on the paragraph
  d := LoadString('{\rtf1 \pard\keepn\qc a{\kerning2\insrsid5 b}c\par}');
  try
    AssertTrue('\keepn on the paragraph', HasFragment(ParaFmt(d, 0).Extra, '\keepn'));
    AssertTrue('centred', ParaFmt(d, 0).Align = paraCenter);
    AssertEquals('a: none', 0, CharAt(d, 0, 0).Extra.Count);
    AssertEquals('b: two, in order', 2, CharAt(d, 0, 1).Extra.Count);
    AssertText('b: first', '\kerning2', CharAt(d, 0, 1).Extra.Item(0));
    AssertText('b: second', '\insrsid5 ', CharAt(d, 0, 1).Extra.Item(1));
    AssertEquals('c: none again', 0, CharAt(d, 0, 2).Extra.Count);
  finally
    d.Free;
  end;
end;

procedure TTyRtfReadTest.TestDefaultsAndPage;
var
  d: TTyRichDocument;
begin
  d := LoadBytes(Fixture('hand-word-zh.rtf'));
  try
    AssertText('\deff0', 'Times New Roman', d.DefaultCharFormat.FontName);
    AssertEquals('12 pt', 24, d.DefaultCharFormat.SizeHalfPt);
    AssertEquals('paper width', 11906, d.PaperWidth);
    AssertEquals('paper height', 16838, d.PaperHeight);
    AssertEquals('left margin', 1800, d.MarginLeft);
    AssertEquals('right margin', 1800, d.MarginRight);
  finally
    d.Free;
  end;
  // no \deff: the first font; no \fs: 12 pt; no page: the document's own
  d := LoadString('{\rtf1{\fonttbl{\f3 Third;}{\f1 First;}} plain\par}');
  try
    AssertText('first font', 'Third', d.DefaultCharFormat.FontName);
    AssertText('the text''s font', 'Third', CharAt(d, 0, 0).FontName);
    AssertEquals('the text''s size', 24, CharAt(d, 0, 0).SizeHalfPt);
    AssertTrue('left', ParaFmt(d, 0).Align = paraLeft);
    AssertTrue('single', ParaFmt(d, 0).LineSpacing = lsSingle);
    AssertEquals('WordPad''s paper', 12240, d.PaperWidth);
  finally
    d.Free;
  end;
  // \plain and \pard go back to those defaults
  d := LoadString('{\rtf1\deff1{\fonttbl{\f0 Zero;}{\f1 One;}}\f0\fs40\b\qc a\plain b\pard c\par}');
  try
    AssertText('a', 'Zero', CharAt(d, 0, 0).FontName);
    AssertText('b font', 'One', CharAt(d, 0, 1).FontName);
    AssertEquals('b size', 24, CharAt(d, 0, 1).SizeHalfPt);
    AssertTrue('b not bold', CharAt(d, 0, 1).Style = []);
    AssertTrue('\pard: left', ParaFmt(d, 0).Align = paraLeft);
  finally
    d.Free;
  end;
end;

procedure TTyRtfReadTest.TestTruncatedFilesLoadWhatIsThere;

  procedure Cut(const AName: string; AStep: Integer);
  var
    b, part: TBytes;
    n: Integer;
    d: TTyRichDocument;
    m: TTyRtfSourceMap;
  begin
    b := Fixture(AName);
    n := 0;
    while n <= Length(b) do
    begin
      part := Copy(b, 0, n);
      m := TTyRtfSourceMap.Create;
      try
        d := nil;
        try
          d := LoadBytes(part, m);
        except
          on E: ETyRichRtf do
            if n >= 5 then
              Fail(Format('%s cut at %d: %s', [AName, n, E.Message]));
          on E: Exception do
            Fail(Format('%s cut at %d: %s: %s', [AName, n, E.ClassName, E.Message]));
        end;
        if d <> nil then
        try
          AssertEquals(Format('%s cut at %d: integrity', [AName, n]), '', d.Text.CheckIntegrity);
          CheckTiles(Format('%s cut at %d', [AName, n]), part, d, m);
        finally
          d.Free;
        end
        else
          AssertTrue(Format('%s cut at %d is no RTF yet', [AName, n]), n < 5);
      finally
        m.Free;
      end;
      Inc(n, AStep);
    end;
  end;

begin
  Cut('hand-uc.rtf', 1);
  Cut('re-zh-table.rtf', 1);
  Cut('hand-word-unknown.rtf', 37);
end;

procedure TTyRtfReadTest.TestMalformedInput;
const
  OutOfRange: array[0..3] of string = ('1114112', '-70000', '2147483647', '-99999999999999');
var
  d: TTyRichDocument;
  m: TTyRtfSourceMap;
  raised: Boolean;
  i: Integer;
begin
  // not RTF
  raised := False;
  try
    LoadString('hello').Free;
  except
    on ETyRichRtf do raised := True;
  end;
  AssertTrue('not RTF raises', raised);
  raised := False;
  try
    LoadString('').Free;
  except
    on ETyRichRtf do raised := True;
  end;
  AssertTrue('empty raises', raised);
  // \bin past the end: its data is what is there
  d := LoadString('{\rtf1 a{\pict\pngblip\bin100 xy');
  try
    CheckParas('\bin past the end', d, ['a' + ObjChar]);
    AssertEquals('the data there', 2, Length((ObjAt(d, 0, 1) as TTyRichPicture).Data));
  finally
    d.Free;
  end;
  // \' with one hex digit: dropped with its digit
  d := LoadString('{\rtf1 a\''4 b\''\par}');
  try
    CheckParas('one hex digit', d, ['a b']);
  finally
    d.Free;
  end;
  // unbalanced braces: a missing } ends at the end; after the document's } nothing is read
  d := LoadString('{\rtf1 {\b a\par b');
  try
    CheckParas('missing braces', d, ['a', 'b']);
    AssertTrue('b bold', fsBold in CharAt(d, 1, 0).Style);
  finally
    d.Free;
  end;
  m := TTyRtfSourceMap.Create;
  d := LoadString('{\rtf1 a}} b\par}', m);
  try
    CheckParas('extra braces', d, ['a']);
    AssertEquals('the rest is the trailer', 8, m.Trailer.Start);
  finally
    d.Free;
    m.Free;
  end;
  d := LoadString('{\rtf1 a}}}}}}}}{{{{{{\par}');
  try
    CheckParas('braces only', d, ['a']);
  finally
    d.Free;
  end;
  // a NUL in the text is ignored, as CR and LF are
  d := LoadString('{\rtf1 a'#0'b'#13#10'c\''00d\par}');
  try
    CheckParas('NUL', d, ['abcd']);
  finally
    d.Free;
  end;
  // deep nesting and a huge number do not hurt
  d := LoadString('{\rtf1 ' + StringOfChar('{', 100000) + 'a' + StringOfChar('}', 100000) +
    '\fs99999999999999 b\par}');
  try
    CheckParas('deep', d, ['ab']);
  finally
    d.Free;
  end;
  // \u with a number no character has (one too many, below the 16-bit range, saturated):
  // U+FFFD, one character in the index and in the text alike
  for i := 0 to High(OutOfRange) do
  begin
    d := LoadString('{\rtf1 a\u' + OutOfRange[i] + '?b\par c\par}');
    try
      CheckParas('\u' + OutOfRange[i], d, ['a' + UC($FFFD) + 'b', 'c']);
      AssertEquals('\u' + OutOfRange[i] + ': characters', 3, d.Text.ParaLength(0));
    finally
      d.Free;
    end;
  end;
  // ... and in a font's name
  d := LoadString('{\rtf1{\fonttbl{\f0 A\u1114112?B;}}\f0 x\par}');
  try
    AssertText('a font name with \u out of range', U('A' + UC($FFFD) + 'B'), CharAt(d, 0, 0).FontName);
  finally
    d.Free;
  end;
  d := LoadString('{\rtf1{\fonttbl{\f0 A\u-10179?B;}}\f0 x\par}');
  try
    AssertText('a font name with half a surrogate pair', U('A' + UC($FFFD) + 'B'),
      CharAt(d, 0, 0).FontName);
  finally
    d.Free;
  end;
  // a huge \uc: the fallback runs to the next control word, no further
  d := LoadString('{\rtf1 a\uc99999999999999\u20013 xyz\par b\par}');
  try
    CheckParas('huge \uc', d, ['a' + UC(20013), 'b']);
  finally
    d.Free;
  end;
  // \bin with a negative count has no data; one too long for a number takes what is there
  d := LoadString('{\rtf1 a{\pict\pngblip\bin-5 4142}b\par}');
  try
    CheckParas('\bin-5', d, ['a' + ObjChar + 'b']);
    AssertEquals('\bin-5: the hex after it is the data', 2, Length((ObjAt(d, 0, 1) as TTyRichPicture).Data));
  finally
    d.Free;
  end;
  d := LoadString('{\rtf1 a{\pict\pngblip\bin99999999999999999999 xy}b\par}');
  try
    CheckParas('\bin saturated', d, ['a' + ObjChar]);
    AssertEquals('\bin saturated: to the end of the file', 9, Length((ObjAt(d, 0, 1) as TTyRichPicture).Data));
  finally
    d.Free;
  end;
end;

procedure TTyRtfReadTest.TestCountingAgreesAndResumesFromASnapshot;
const
  // groups that stay open across paragraphs, and properties that change between them
  Inline: array[0..2] of RawByteString = (
    '{\rtf1 {\b A\par B}x\i{\ul C\par}D\par}',
    '{\rtf1{\fonttbl{\f0\fcharset134 S;}}\f0{\uc2 a\par\''d6{\b\''d0}b}\''d6\''d0\par}',
    '{\rtf1 \trowd\cellx100\cellx200\pard\intbl{a\cell b}\cell\row\pard c\par}');
var
  sr: TSearchRec;
  files, i: Integer;

  procedure Check(const AName: string; const B: TBytes);
  var
    m: TTyRtfSourceMap;
    d: TTyRichDocument;
    pool: TTyFormatPool;
    p, c, q: TTyRtfParser;
    i, j, k: Integer;
    msg: string;
    rp, rq: TTyRtfParaRec;
  begin
    m := TTyRtfSourceMap.Create;
    d := LoadBytes(B, m);
    pool := TTyFormatPool.Create;
    p := TTyRtfParser.Create(B, pool);
    c := TTyRtfParser.Create(B, nil);
    try
      p.KeepSnapshots := True;
      p.Parse;
      // counting only: the same characters per paragraph, the same byte ranges
      c.Parse;
      AssertEquals(AName + ': paragraphs counted', d.Text.ParaCount, c.ParaCount);
      for i := 0 to c.ParaCount - 1 do
      begin
        msg := Format('%s paragraph %d', [AName, i]);
        AssertEquals(msg + ': characters', d.Text.ParaLength(i), c.ParaRec(i).Chars);
        AssertEquals(msg + ': start', m.Paras[i].Start, c.ParaRec(i).Src.Start);
        AssertEquals(msg + ': stop', m.Paras[i].Stop, c.ParaRec(i).Src.Stop);
      end;
      AssertEquals(AName + ': trailer', m.Trailer.Start, Int64(c.TrailerStart));
      // resumed from the state after any paragraph, the rest reads the same: characters,
      // ranges, formats, runs
      AssertTrue(AName + ': a snapshot after every paragraph (the last may end at the end)',
        p.SnapshotCount >= p.ParaCount - 1);
      for k := 0 to p.SnapshotCount - 1 do
      begin
        q := TTyRtfParser.Create(B, pool);
        try
          q.CopyTablesFrom(p);
          q.Resume(p.Snapshot(k));
          q.Parse;
          msg := Format('%s resumed after paragraph %d', [AName, k]);
          AssertEquals(msg + ': paragraphs', p.ParaCount - k - 1, q.ParaCount);
          for i := 0 to q.ParaCount - 1 do
          begin
            rp := p.ParaRec(k + 1 + i);
            rq := q.ParaRec(i);
            msg := Format('%s resumed after paragraph %d: paragraph %d', [AName, k, k + 1 + i]);
            AssertEquals(msg + ' characters', rp.Chars, rq.Chars);
            AssertEquals(msg + ' start', rp.Src.Start, rq.Src.Start);
            AssertEquals(msg + ' stop', rp.Src.Stop, rq.Src.Stop);
            AssertEquals(msg + ' format', rp.Format, rq.Format);
            AssertEquals(msg + ' cell', rp.Cell, rq.Cell);
            AssertEquals(msg + ' runs', Length(rp.Runs), Length(rq.Runs));
            for j := 0 to High(rp.Runs) do
            begin
              AssertEquals(Format('%s run %d start', [msg, j]), rp.Runs[j].Start, rq.Runs[j].Start);
              AssertEquals(Format('%s run %d format', [msg, j]), rp.Runs[j].Format,
                rq.Runs[j].Format);
              AssertEquals(Format('%s run %d object', [msg, j]), rp.Runs[j].Obj = nil,
                rq.Runs[j].Obj = nil);
            end;
          end;
          AssertEquals(msg + ': trailer', Int64(p.TrailerStart), Int64(q.TrailerStart));
        finally
          q.Free;
        end;
      end;
    finally
      c.Free;
      p.Free;
      pool.Free;
      d.Free;
      m.Free;
    end;
  end;

begin
  files := 0;
  if FindFirst(FixtureDir + '*.rtf', faAnyFile, sr) = 0 then
  try
    repeat
      Inc(files);
      Check(sr.Name, Fixture(sr.Name));
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
  AssertTrue('samples', files >= 12);
  for i := 0 to High(Inline) do Check(Shown(Inline[i]), BytesOf(Inline[i]));
end;

{ ---- what the real WordPad and Word files showed ---- }

procedure TTyRtfReadTest.TestGb18030AsTheFileCodePage;
var
  d: TTyRichDocument;
begin
  // WordPad on a Chinese system writes \ansicpg54936; a font that names no charset reads in it
  d := LoadString('{\rtf1\ansi\ansicpg54936\deff0{\fonttbl{\f0\fnil Arial;}}\f0 \''d6\''d0' +
    '\''ce\''c4\par}');
  try
    CheckParas('\ansicpg54936', d, ['中文']);
  finally
    d.Free;
  end;
  // ... and so does the font's name
  d := LoadString('{\rtf1\ansi\ansicpg54936{\fonttbl{\f0\fnil\fcharset1 \''cb\''ce\''cc\''e5;}}' +
    '\f0 a\par}');
  try
    AssertText('font name in GB18030', U('宋体'), CharAt(d, 0, 0).FontName);
  finally
    d.Free;
  end;
  // a font's own \cpg54936 in a Western file
  d := LoadString('{\rtf1\ansi\ansicpg1252{\fonttbl{\f0\fnil\cpg54936 X;}{\f1\fnil Y;}}' +
    '\f0 \''d6\''d0\f1 \''e9\par}');
  try
    CheckParas('\cpg54936', d, ['中é']);
  finally
    d.Free;
  end;
  // a four-byte GB18030 sequence (81 30 81 30 is U+0080) is not decoded: the lead byte reads
  // '?' and the digit byte as itself, as in a GBK file; WordPad writes such characters as \u
  d := LoadString('{\rtf1\ansi\ansicpg54936{\fonttbl{\f0\fnil A;}}\f0 x\''81\''30\''81\''30y\par}');
  try
    CheckParas('four bytes', d, ['x?0?0y']);
  finally
    d.Free;
  end;
end;

{ ---- the review of batch A ---- }

{ An Extra list's fragments, one after the other with | between them. }
function Joined(const A: TTyOpaqueAttrs): RawByteString;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to A.Count - 1 do
  begin
    if i > 0 then Result := Result + '|';
    Result := Result + A.Item(i);
  end;
end;

{ WordPad writes character properties as bare words at the top level and never resets them:
  \lang2052 ... \lang1033 ... \lang2052. Every such word must take the place of the one of
  its name the run already carries, or the list (and with it every format, every snapshot)
  grows with the document. }
procedure TTyRtfReadTest.TestALaterUnknownWordReplacesTheEarlierOne;
var
  d: TTyRichDocument;
  r: TTyRunArray;
  src: RawByteString;
  i, last: Integer;
begin
  d := LoadString('{\rtf1 \pard\lang1033 a\lang2052 b\lang1033 c\kerning2 d\lang1033\kerning0 e\par}');
  try
    CheckParas('toggles', d, ['abcde']);
    AssertText('a', '\lang1033 ', Joined(CharAt(d, 0, 0).Extra));
    AssertText('b: the later value alone', '\lang2052 ', Joined(CharAt(d, 0, 1).Extra));
    AssertText('c', '\lang1033 ', Joined(CharAt(d, 0, 2).Extra));
    r := d.RunsOf(0);
    AssertEquals('five runs', 5, Length(r));
    AssertEquals('c has a''s very format again', r[0].Format, r[2].Format);
    AssertText('d: a second word joins', '\lang1033 |\kerning2 ', Joined(CharAt(d, 0, 3).Extra));
    AssertText('e: in the order they were last written', '\lang1033|\kerning0 ',
      Joined(CharAt(d, 0, 4).Extra));
  finally
    d.Free;
  end;
  // the reviewer's file: plain WordPad-style paragraphs, no group, no \plain
  src := '{\rtf1\ansi\ansicpg936\deff0{\fonttbl{\f0\fnil\fcharset134 SimSun;}}'#13#10 +
    '\pard\f0\fs24 ';
  for i := 0 to 299 do
    src := src + '\lang2052\''d6\''d0\''ce\''c4 ' + IntToStr(i) +
      ' \lang1033 with some English words in it.\par'#13#10;
  d := LoadString(src + '}');
  try
    AssertEquals('paragraphs', 300, d.Text.ParaCount);
    last := d.Text.ParaCount - 1;
    AssertText('the last run carries one word', '\lang1033 ',
      Joined(CharAt(d, last, d.Text.ParaLength(last) - 1).Extra));
    AssertText('the first run of the last paragraph too', '\lang2052',
      Joined(CharAt(d, last, 0).Extra));
    for i := 0 to last do d.EnsureParsed(i);
    AssertTrue(Format('%d character formats for two kinds of run', [d.Formats.CharCount]),
      d.Formats.CharCount <= 8);
  finally
    d.Free;
  end;
  // Word's pair for the other writing direction: \fcs says which of the two it follows, so
  // both stay - and written again, the same five take the old ones' place
  d := LoadString('{\rtf1 \pard\rtlch\fcs1 \af0 \ltrch\fcs0 a\rtlch\fcs1 \af0 \ltrch\fcs0 b' +
    '\ltrch\fcs1 \af0 \rtlch\fcs0 c\par}');
  try
    AssertText('Word''s pair', '\rtlch|\fcs1 |\af0 |\ltrch|\fcs0 ', Joined(CharAt(d, 0, 0).Extra));
    r := d.RunsOf(0);
    AssertEquals('two runs', 2, Length(r));
    AssertEquals('b: the same format', 2, r[1].Start);
    AssertText('c: the other direction', '\ltrch|\fcs1 |\af0 |\rtlch|\fcs0 ',
      Joined(CharAt(d, 0, 2).Extra));
  finally
    d.Free;
  end;
  // a control symbol and a property group are replaced by their like
  d := LoadString('{\rtf1 a\|b\|c{\*\oldcprops \b}d{\*\oldcprops \i}e\par}');
  try
    AssertText('one symbol', '\|', Joined(CharAt(d, 0, 2).Extra));
    AssertText('the later group', '\||{\*\oldcprops \i}', Joined(CharAt(d, 0, 4).Extra));
  finally
    d.Free;
  end;
  // the paragraph's words: the same word again replaces; a bar tab is one of several, and
  // a border's words belong to the side named before them
  d := LoadString('{\rtf1 \pard\keep\s1 a\par\keep\s2 b\par' +
    '\pard\tb100\tb200\tb100 c\par' +
    '\pard\brdrt\brdrs\brdrw10 \brdrb\brdrs\brdrw20 d\par\brdrt\brdrdb\brdrw30 e\par' +
    '\pard\ls1\ilvl0\ls2 f\par}');
  try
    AssertText('a', '\keep|\s1 ', Joined(ParaFmt(d, 0).Extra));
    AssertText('b: the later style', '\keep|\s2 ', Joined(ParaFmt(d, 1).Extra));
    AssertText('c: two bar tabs', '\tb200|\tb100 ', Joined(ParaFmt(d, 2).Extra));
    AssertText('d: two borders', '\brdrt|\brdrs|\brdrw10 |\brdrb|\brdrs|\brdrw20 ',
      Joined(ParaFmt(d, 3).Extra));
    AssertText('e: the top border again', '\brdrb|\brdrs|\brdrw20 |\brdrt|\brdrdb|\brdrw30 ',
      Joined(ParaFmt(d, 4).Extra));
    AssertText('f: the later list', '\ilvl0|\ls2 ', Joined(ParaFmt(d, 5).Extra));
  finally
    d.Free;
  end;
end;

{ The model has no table inside a cell: the inner cells' paragraphs are the outer cell's.
  The row that holds one is marked (the model then keeps it as the file has it), and only
  that row. }
procedure TTyRtfReadTest.TestARowThatHoldsANestedTableIsMarked;
const
  // a row of two cells, and what its second cell holds besides its own paragraph
  Before = '{\rtf1 \trowd\cellx100\cellx200\pard\intbl a\cell ';
  After = '\pard\intbl c\cell\row\trowd\cellx100\cellx200\pard\intbl d\cell e\cell\row' +
    '\pard f\par}';
  Signs: array[0..5] of RawByteString = (
    '\pard\intbl\itap2 b\par',
    'b\nestcell ',
    '{\*\nesttableprops\trowd\cellx50\nestrow}b\par',
    '\nestrow b\par',
    '{\nonesttables\par}b\par',
    // the level named and taken back before a paragraph ends at it
    '\itap2\pard\intbl b\par');
var
  d: TTyRichDocument;
  i, p: Integer;

  function Marked(APara: Integer): Boolean;
  begin
    Result := (d.CellAt(APara) <> nil) and d.CellAt(APara).Row.HoldsNestedTable;
  end;

  procedure Check(const AName: string; AFirst, ALast: Integer);
  var
    k: Integer;
  begin
    d := LoadBytes(Fixture(AName));
    try
      for k := 0 to d.Text.ParaCount - 1 do
        AssertEquals(Format('%s paragraph %d is in the row that holds the nested table',
          [AName, k]), (k >= AFirst) and (k <= ALast), Marked(k));
      AssertText(AName + ': the outer cell before the nested table', 'G', ParaText(d, AFirst + 1));
      AssertTrue(AName + ': one row', d.CellAt(AFirst).Row = d.CellAt(ALast).Row);
      AssertTrue(AName + ': the row before it is another', d.CellAt(AFirst - 1).Row <> d.CellAt(AFirst).Row);
      AssertTrue(AName + ': such a table is locked', d.TableAt(AFirst).StructureLocked);
    finally
      d.Free;
    end;
  end;

begin
  // the third row: an empty cell, G, and the cell with the 1 x 2 table and its own paragraph
  Check('hand-word-table-merged.rtf', 7, 11);
  Check('word-table-merged.rtf', 6, 10);
  // each sign by itself marks the row it is in, and not the row after it
  for i := 0 to High(Signs) do
  begin
    d := LoadString(Before + Signs[i] + After);
    try
      CheckParas(Format('sign %d', [i]), d, ['a', 'b', 'c', 'd', 'e', 'f']);
      for p := 0 to 5 do
        AssertEquals(Format('sign %d: paragraph %d marked', [i, p]), p <= 2, Marked(p));
    finally
      d.Free;
    end;
  end;
  // a nesting level set in one row and never taken back holds in the next
  d := LoadString('{\rtf1 \trowd\cellx100\pard\intbl\itap2 a\cell\row' +
    '\trowd\cellx100 b\cell\row\trowd\cellx100\pard\intbl c\cell\row\pard d\par}');
  try
    CheckParas('a level that lasts', d, ['a', 'b', 'c', 'd']);
    AssertTrue('the row it was set in', Marked(0));
    AssertTrue('the row after it', Marked(1));
    AssertFalse('the row that set it back', Marked(2));
  finally
    d.Free;
  end;
  // a sign after a table's last row is no row's: the next table starts clean
  d := LoadString('{\rtf1 \trowd\cellx100\pard\intbl a\cell\row\nestrow\pard b\par' +
    '\trowd\cellx100\pard\intbl c\cell\row\pard d\par}');
  try
    CheckParas('a stray sign', d, ['a', 'b', 'c', 'd']);
    AssertFalse('the row before it', Marked(0));
    AssertFalse('the next table''s row', Marked(2));
  finally
    d.Free;
  end;
  // no sign, no mark: a table as RichEdit writes one
  d := LoadBytes(Fixture('re-zh-table.rtf'));
  try
    for p := 0 to d.Text.ParaCount - 1 do
      AssertFalse(Format('re-zh-table paragraph %d', [p]), Marked(p));
  finally
    d.Free;
  end;
end;

initialization
  RegisterTest(TTyRtfReadTest);
end.
