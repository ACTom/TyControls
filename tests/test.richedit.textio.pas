unit test.richedit.textio;

{ Plain text files in TTyRichEdit's document: the encoding is found (BOM, then valid UTF-8,
  then the ANSI code page) and kept, and so are the BOM and every line break, so a file that
  is opened and saved without a change comes back byte for byte - also bytes that are not
  text in the file's encoding. New line breaks take the file's majority kind. Loading
  replaces the document in place and keeps no second copy of the file; saving streams. The
  samples are tests/fixtures/txt (scripts/gen-richedit-fixtures.py). }

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, Graphics, fpcunit, testregistry,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.TextIO;

type
  TIODocAccess = class(TTyRichDocument)
  end;

  TIONullLoader = class(TTyRichParaLoader)
  public
    procedure LoadParagraph(ADoc: TTyRichDocument; AIndex: Integer); override;
  end;

  { A stream that only compares what is written with the bytes expected, and notes the
    highest heap use seen while it is written to: the saver's working memory. }
  TCheckingStream = class(TStream)
  private
    FExpected: TBytes;
    FPos: Int64;
    FHeap0: PtrUInt;
    FPeak: PtrUInt;
    FFirstDiff: Int64;
    FWrites: Integer;
  public
    constructor Create(const AExpected: TBytes);
    function Write(const Buffer; Count: Longint): Longint; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    property Written: Int64 read FPos;
    property PeakGrowth: PtrUInt read FPeak;
    property FirstDiff: Int64 read FFirstDiff;
  end;

  TTyRichTextIOTest = class(TTestCase)
  private
    FChanges: array of TTyRichChange;
    procedure DocChanged(Sender: TObject; const AChange: TTyRichChange);
    function Fixture(const AName: string): TBytes;
    function LoadBytes(const ABytes: TBytes; AEncoding: TTyTextEncoding = teAuto;
      ACodePage: Integer = 0): TTyRichDocument;
    function LoadFixture(const AName: string; AEncoding: TTyTextEncoding = teAuto;
      ACodePage: Integer = 0): TTyRichDocument;
    function SaveBytes(ADoc: TTyRichDocument): TBytes;
    procedure CheckParagraphs(const AMsg: string; ADoc: TTyRichDocument;
      const ALines: array of UTF8String);
  published
    procedure TestEncodingDetection;
    procedure TestOpenSaveIsByteIdentical;
    procedure TestMixedLineEndingsRoundTripAndMajorityForNewLines;
    procedure TestAForcedEncodingWins;
    procedure TestBytesThatAreNotTextRoundTrip;
    procedure TestLoadingReplacesTheDocumentInPlace;
    procedure TestNewDocumentIsUtf8WithThePlatformBreak;
    procedure TestLoadingUtf8KeepsOneCopy;
    procedure TestLoadingGbkKeepsNoOriginal;
    procedure TestSavingUsesAFixedBuffer;
  end;

implementation

const
  // the lines every sample but gbk.txt holds (gen-richedit-fixtures.py), the last one empty
  // because the file ends with a line break
  SampleLines: array[0..5] of UTF8String = (
    'TyControls 富文本控件的文本样本。',
    '第二行：中英混排 mixed text，全角标点“”，和一个表情 😀。',
    '',
    '第四行前面是一个空行。',
    'The last line is plain ASCII.',
    '');
  // GBK has no emoji: the second line goes without it
  GbkLine2: UTF8String = '第二行：中英混排 mixed text，全角标点“”。';

function RepoRoot: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim;
end;

function FromBytes(const B: array of Byte): UTF8String;
begin
  Result := '';
  SetLength(Result, System.Length(B));
  if System.Length(B) > 0 then Move(B[0], Result[1], System.Length(B));
end;

{ A literal as UTF-8 before it meets raw bytes: a literal on its own is a UnicodeString
  here, and concatenating raw bytes to it would convert them. }
function U(const S: UTF8String): UTF8String;
begin
  Result := S;
end;

function BytesOf(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, System.Length(S));
  if S <> '' then Move(S[1], Result[0], System.Length(S));
end;

function Concat(const A, B: TBytes): TBytes;
begin
  Result := nil;
  SetLength(Result, System.Length(A) + System.Length(B));
  if System.Length(A) > 0 then Move(A[0], Result[0], System.Length(A));
  if System.Length(B) > 0 then Move(B[0], Result[System.Length(A)], System.Length(B));
end;

{ A then B then C: the bytes with B put in at AAt. }
function Splice(const A: TBytes; AAt: Integer; const B: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, System.Length(A) + System.Length(B));
  if AAt > 0 then Move(A[0], Result[0], AAt);
  if B <> '' then Move(B[1], Result[AAt], System.Length(B));
  if AAt < System.Length(A) then
    Move(A[AAt], Result[AAt + System.Length(B)], System.Length(A) - AAt);
end;

function IndexOfBytes(const AHay: TBytes; const ANeedle: RawByteString): Integer;
var
  i: Integer;
begin
  for i := 0 to System.Length(AHay) - System.Length(ANeedle) do
    if CompareMem(@AHay[i], @ANeedle[1], System.Length(ANeedle)) then Exit(i);
  Result := -1;
end;

function Shown(const S: RawByteString): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to System.Length(S) do
    if (S[i] >= ' ') and (S[i] < #$7F) then Result := Result + S[i]
    else Result := Result + '<' + IntToHex(Ord(S[i]), 2) + '>';
end;

procedure AssertSameBytes(const AMsg: string; const AExpected, AActual: TBytes);
var
  i, n: Integer;
begin
  if (System.Length(AExpected) = System.Length(AActual)) and ((System.Length(AExpected) = 0) or
     CompareMem(@AExpected[0], @AActual[0], System.Length(AExpected))) then
    Exit;
  n := System.Length(AExpected);
  if System.Length(AActual) < n then n := System.Length(AActual);
  i := 0;
  while (i < n) and (AExpected[i] = AActual[i]) do Inc(i);
  raise EAssertionFailedError.CreateFmt('%s: %d bytes expected, %d written, first difference ' +
    'at byte %d', [AMsg, System.Length(AExpected), System.Length(AActual), i]);
end;

procedure AssertText(const AMsg: string; const AExpected, AActual: RawByteString);
begin
  if (System.Length(AExpected) = System.Length(AActual)) and
     ((AExpected = '') or CompareMem(@AExpected[1], @AActual[1], System.Length(AExpected))) then
    Exit;
  raise EAssertionFailedError.CreateFmt('%s: expected <%s> but was <%s>',
    [AMsg, Shown(AExpected), Shown(AActual)]);
end;

function ParaText(ADoc: TTyRichDocument; AIndex: Integer): UTF8String;
begin
  Result := ADoc.Text.GetText(ADoc.Text.ParaStart(AIndex), ADoc.Text.ParaLength(AIndex));
end;

function HeapUsed: PtrUInt;
begin
  Result := GetFPCHeapStatus.CurrHeapUsed;
end;

{ ABytes repeated until the result is at least ASize bytes long. }
function Repeated(const ABytes: TBytes; ASize: Integer): TBytes;
var
  n, i: Integer;
begin
  n := (ASize + System.Length(ABytes) - 1) div System.Length(ABytes);
  Result := nil;
  SetLength(Result, n * System.Length(ABytes));
  for i := 0 to n - 1 do
    Move(ABytes[0], Result[i * System.Length(ABytes)], System.Length(ABytes));
end;

{ ---- helpers ---- }

procedure TIONullLoader.LoadParagraph(ADoc: TTyRichDocument; AIndex: Integer);
begin
end;

constructor TCheckingStream.Create(const AExpected: TBytes);
begin
  inherited Create;
  FExpected := AExpected;
  FFirstDiff := -1;
  FHeap0 := HeapUsed;
end;

function TCheckingStream.Write(const Buffer; Count: Longint): Longint;
var
  p: PByte;
  i: Integer;
  h: PtrUInt;
begin
  h := HeapUsed;
  if (h > FHeap0) and (h - FHeap0 > FPeak) then FPeak := h - FHeap0;
  Inc(FWrites);
  p := @Buffer;
  if FFirstDiff < 0 then
    for i := 0 to Count - 1 do
      if (FPos + i >= System.Length(FExpected)) or (FExpected[FPos + i] <> p[i]) then
      begin
        FFirstDiff := FPos + i;
        Break;
      end;
  Inc(FPos, Count);
  Result := Count;
end;

function TCheckingStream.Read(var Buffer; Count: Longint): Longint;
begin
  raise EStreamError.Create('TCheckingStream is write-only');
end;

function TCheckingStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  if ((Origin = soCurrent) and (Offset = 0)) or ((Origin = soBeginning) and (Offset = FPos)) then
    Exit(FPos);
  raise EStreamError.Create('TCheckingStream does not seek');
end;

procedure TTyRichTextIOTest.DocChanged(Sender: TObject; const AChange: TTyRichChange);
begin
  SetLength(FChanges, System.Length(FChanges) + 1);
  FChanges[High(FChanges)] := AChange;
end;

function TTyRichTextIOTest.Fixture(const AName: string): TBytes;
var
  f: TFileStream;
begin
  f := TFileStream.Create(RepoRoot + 'tests' + PathDelim + 'fixtures' + PathDelim + 'txt' +
    PathDelim + AName, fmOpenRead or fmShareDenyNone);
  try
    Result := nil;
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[0], f.Size);
  finally
    f.Free;
  end;
end;

function TTyRichTextIOTest.LoadBytes(const ABytes: TBytes; AEncoding: TTyTextEncoding;
  ACodePage: Integer): TTyRichDocument;
var
  s: TBytesStream;
begin
  Result := TTyRichDocument.Create;
  s := TBytesStream.Create(ABytes);
  try
    TyRichLoadText(Result, s, AEncoding, ACodePage);
  finally
    s.Free;
  end;
end;

function TTyRichTextIOTest.LoadFixture(const AName: string; AEncoding: TTyTextEncoding;
  ACodePage: Integer): TTyRichDocument;
begin
  Result := LoadBytes(Fixture(AName), AEncoding, ACodePage);
end;

function TTyRichTextIOTest.SaveBytes(ADoc: TTyRichDocument): TBytes;
var
  s: TBytesStream;
begin
  s := TBytesStream.Create;
  try
    TyRichSaveText(ADoc, s);
    Result := Copy(s.Bytes, 0, s.Size);
  finally
    s.Free;
  end;
end;

procedure TTyRichTextIOTest.CheckParagraphs(const AMsg: string; ADoc: TTyRichDocument;
  const ALines: array of UTF8String);
var
  i: Integer;
begin
  AssertEquals(AMsg + ': paragraphs', System.Length(ALines), ADoc.Text.ParaCount);
  for i := 0 to High(ALines) do
    AssertText(Format('%s: paragraph %d', [AMsg, i]), ALines[i], ParaText(ADoc, i));
end;

{ ---- tests ---- }

procedure TTyRichTextIOTest.TestEncodingDetection;

  procedure Check(const AName: string; AEnc: TTyTextEncoding; ABom: Boolean;
    ACodePage: Integer; ABreak: TTyRichSeparator; const ALines: array of UTF8String);
  var
    d: TTyRichDocument;
  begin
    // 936 for the ANSI fallback, so gbk.txt reads the same on a system that is not Chinese
    d := LoadFixture(AName, teAuto, 936);
    try
      AssertTrue(AName + ': encoding ' + IntToStr(Ord(d.SourceEncoding)), d.SourceEncoding = AEnc);
      AssertEquals(AName + ': BOM', ABom, d.SourceHasBom);
      AssertEquals(AName + ': code page', ACodePage, d.SourceCodePage);
      AssertTrue(AName + ': majority line break ' + IntToStr(Ord(d.DominantLineBreak)),
        d.DominantLineBreak = ABreak);
      CheckParagraphs(AName, d, ALines);
      AssertFalse(AName + ': loading is not a change', d.Modified);
    finally
      d.Free;
    end;
  end;

var
  ascii, original: TBytes;
  d: TTyRichDocument;
begin
  Check('utf8-bom.txt', teUtf8Bom, True, 0, rsCRLF, SampleLines);
  Check('utf8-nobom.txt', teUtf8, False, 0, rsLF, SampleLines);
  Check('utf16le.txt', teUtf16LE, True, 0, rsCRLF, SampleLines);
  Check('utf16be.txt', teUtf16BE, True, 0, rsCRLF, SampleLines);
  Check('gbk.txt', teAnsi, False, 936, rsCRLF, [SampleLines[0], GbkLine2, SampleLines[2],
    SampleLines[3], SampleLines[4], SampleLines[5]]);
  Check('mixed-eol.txt', teUtf8Bom, True, 0, rsLF, ['第一行', 'second line', '第三行', '第四行',
    'fifth line', '第六行', '第七行', '最后一行，后面没有换行']);
  // text that stops being UTF-8 only after the first megabyte the reader looks at first
  ascii := Repeated(BytesOf('plain ASCII line'#13#10), 3 * 1024 * 1024);
  original := Concat(ascii, Fixture('gbk.txt'));
  d := LoadBytes(original, teAuto, 936);
  try
    AssertTrue('GBK after 3 MB of ASCII: ANSI', d.SourceEncoding = teAnsi);
    AssertEquals('GBK after 3 MB of ASCII: 936', 936, d.SourceCodePage);
    AssertText('GBK after 3 MB of ASCII: decoded', GbkLine2,
      ParaText(d, System.Length(ascii) div 18 + 1));
    AssertSameBytes('GBK after 3 MB of ASCII: saved as read', original, SaveBytes(d));
  finally
    d.Free;
  end;
end;

procedure TTyRichTextIOTest.TestOpenSaveIsByteIdentical;
const
  Names: array[0..7] of string = ('utf8-bom.txt', 'utf8-nobom.txt', 'utf16le.txt',
    'utf16be.txt', 'gbk.txt', 'mixed-eol.txt', 'gbk-badbytes.txt', 'utf8-badbytes.txt');
var
  i: Integer;
  d: TTyRichDocument;
  original: TBytes;
begin
  for i := 0 to High(Names) do
  begin
    original := Fixture(Names[i]);
    d := LoadBytes(original, teAuto, 936);
    try
      AssertSameBytes(Names[i] + ' opened and saved', original, SaveBytes(d));
      // and once more, from what was saved
      AssertSameBytes(Names[i] + ' saved twice', original, SaveBytes(d));
    finally
      d.Free;
    end;
  end;
  // an empty file is UTF-8 without a BOM and stays empty
  d := LoadBytes(nil);
  try
    AssertTrue('empty: UTF-8', d.SourceEncoding = teUtf8);
    AssertFalse('empty: no BOM', d.SourceHasBom);
    AssertEquals('empty: saved empty', 0, System.Length(SaveBytes(d)));
  finally
    d.Free;
  end;
end;

procedure TTyRichTextIOTest.TestMixedLineEndingsRoundTripAndMajorityForNewLines;
var
  d: TTyRichDocument;
  original, expected: TBytes;
  at: Integer;
begin
  // five LF and two CRLF: LF is the majority, and new breaks of any kind become LF
  original := Fixture('mixed-eol.txt');
  d := LoadBytes(original);
  try
    AssertTrue('LF is the majority', d.DominantLineBreak = rsLF);
    AssertTrue('the second line keeps its CRLF', d.Text.ParaSeparator(1) = rsCRLF);
    d.Execute(TTyRichInsertText.Create(d.Text.ParaStart(2), 'inserted'#13#10, TyRichInheritFormat,
      False));
    d.Execute(TTyRichInsertText.Create(d.Text.Length, 'x'#13'y'#13#10, TyRichInheritFormat, False));
    AssertTrue('the inserted break is the majority kind', d.Text.ParaSeparator(2) = rsLF);
    AssertTrue('the old CRLF stays', d.Text.ParaSeparator(1) = rsCRLF);
    at := IndexOfBytes(original, '第三行');
    AssertTrue('third line found', at > 0);
    expected := Splice(original, at, 'inserted'#10);
    expected := Concat(expected, BytesOf('x'#10'y'#10));
    AssertSameBytes('existing breaks as they were, new ones LF', expected, SaveBytes(d));
  finally
    d.Free;
  end;
  // the other way round: in a CRLF file a typed LF or CR is written CRLF
  original := Fixture('utf8-bom.txt');
  d := LoadBytes(original);
  try
    AssertTrue('CRLF is the majority', d.DominantLineBreak = rsCRLF);
    d.Execute(TTyRichInsertText.Create(0, 'a'#10'b'#13, TyRichInheritFormat, False));
    expected := Splice(original, 3, 'a'#13#10'b'#13#10);
    AssertSameBytes('new breaks CRLF', expected, SaveBytes(d));
  finally
    d.Free;
  end;
end;

procedure TTyRichTextIOTest.TestAForcedEncodingWins;
var
  d: TTyRichDocument;
  original: TBytes;
begin
  original := Fixture('utf8-nobom.txt');
  d := LoadBytes(original, teAnsi, 936);
  try
    AssertTrue('read as ANSI', d.SourceEncoding = teAnsi);
    AssertEquals('code page 936', 936, d.SourceCodePage);
    AssertFalse('no BOM', d.SourceHasBom);
    // E5 AF 8C E6 96 87 E6 9C as GBK pairs: U+7035 U+5C7E U+6783 U+93C8
    AssertText('the UTF-8 bytes read as GBK', U('TyControls 瀵屾枃鏈'),
      Copy(ParaText(d, 0), 1, System.Length(U('TyControls 瀵屾枃鏈'))));
    AssertEquals('the line breaks are the same', 6, d.Text.ParaCount);
    AssertText('ASCII is ASCII', SampleLines[4], ParaText(d, 4));
    AssertSameBytes('saved as it was read', original, SaveBytes(d));
  finally
    d.Free;
  end;
end;

procedure TTyRichTextIOTest.TestBytesThatAreNotTextRoundTrip;

  procedure Check(const AMsg: string; const AOriginal: TBytes; AEnc: TTyTextEncoding;
    ACodePage: Integer; AExpectEnc: TTyTextEncoding; const ALines: array of UTF8String);
  var
    d: TTyRichDocument;
  begin
    d := LoadBytes(AOriginal, AEnc, ACodePage);
    try
      AssertTrue(AMsg + ': encoding', d.SourceEncoding = AExpectEnc);
      CheckParagraphs(AMsg, d, ALines);
      AssertSameBytes(AMsg + ': opened and saved', AOriginal, SaveBytes(d));
    finally
      d.Free;
    end;
  end;

begin
  // A byte that is not text in a converted encoding reads as two characters: F8+(b shr 6),
  // 80+(b and 3F) - bytes that are never UTF-8, so nothing typed can look like them.
  // GBK: a lone FF; a lead byte 81 right before the line end
  Check('gbk-badbytes', Fixture('gbk-badbytes.txt'), teAuto, 936, teAnsi,
    [U('第一行') + FromBytes([$FB, $BF]) + U('还有字'), U('第二行') + FromBytes([$FA, $81]), '第三行', '']);
  // UTF-8 (forced): an overlong C0 AF, a lone 80, a sequence cut short at the end - kept as
  // they are, each byte a character
  Check('utf8-badbytes', Fixture('utf8-badbytes.txt'), teUtf8, 0, teUtf8,
    [U('第一行') + FromBytes([$C0, $AF]) + 'ok', FromBytes([$80]) + U('第二行'),
     U('第三') + FromBytes([$E8, $A1])]);
  // UTF-16LE: a lone high and a lone low surrogate, and an odd byte at the end
  Check('utf16 lone surrogates', BytesOf(FromBytes([$FF, $FE, $61, 0, 0, $D8, $62, 0, 0, $DC,
    13, 0, 10, 0, $63, 0, $41])), teAuto, 0, teUtf16LE,
    ['a' + FromBytes([$F8, $80, $FB, $98]) + 'b' + FromBytes([$F8, $80, $FB, $9C]),
     'c' + FromBytes([$F9, $81])]);
  // cp932: 81 E0 and 87 90 both decode to U+2252; the second could not be written back as it
  // was, so it travels as two escaped bytes
  Check('cp932 duplicate', BytesOf(FromBytes([$81, $E0, $87, $90, 13, 10, $41])), teAnsi, 932,
    teAnsi, [U('≒') + FromBytes([$FA, $87, $FA, $90]), 'A']);
end;

procedure TTyRichTextIOTest.TestLoadingReplacesTheDocumentInPlace;
var
  d: TIODocAccess;
  s: TBytesStream;
  f: TTyCharFormat;
  oldLen: TTyRichPos;
begin
  d := TIODocAccess.CreateFromUtf8(BytesOf('old'#13#10'text'#13#10'here'));
  s := nil;
  try
    f := TyDefaultCharFormat;
    f.Style := [fsBold];
    d.Execute(TTyRichSetCharFormat.Create(TyRichRange(0, 6), [cffBold], f));
    d.Execute(TTyRichInsertText.Create(0, 'more '));
    d.Undo;
    d.InstallLoader(TIONullLoader.Create, True);
    AssertTrue('there is something to undo', d.CanUndo);
    AssertTrue('and to redo', d.CanRedo);
    AssertTrue('formatted paragraphs are alive', d.LiveParaData > 0);
    oldLen := d.Text.Length;
    d.OnChange := @DocChanged;
    FChanges := nil;

    // not inside an update block: the block's commands would refer to the old text
    s := TBytesStream.Create(BytesOf('new'#10'content'));
    d.BeginUpdate;
    try
      TyRichLoadText(d, s);
      Fail('loading inside an update block must raise');
    except
      on E: ETyRichModel do ;
    end;
    d.EndUpdate;
    AssertEquals('the refused load left the text alone', oldLen, d.Text.Length);

    s.Position := 0;
    FChanges := nil;
    TyRichLoadText(d, s);
    AssertText('the new text', 'new'#10'content', d.Text.GetText(0, d.Text.Length));
    AssertFalse('no undo', d.CanUndo);
    AssertFalse('no redo', d.CanRedo);
    AssertEquals('no history bytes', Int64(0), d.HistoryBytes);
    AssertFalse('loading is not a change', d.Modified);
    AssertEquals('the old values are gone', 0, d.LiveParaData);
    AssertNull('the loader of the old content is gone', d.Loader);
    AssertEquals('the new paragraphs are plain', d.DefaultParaFormatId, d.ParaFormatOf(1));
    AssertEquals('one change', 1, System.Length(FChanges));
    AssertTrue('everything changed', FChanges[0].Kinds = [rckText, rckFormat, rckStructure]);
    AssertEquals('from the start', Int64(0), FChanges[0].Pos);
    AssertEquals('the old length', oldLen, FChanges[0].OldLen);
    AssertEquals('the new length', d.Text.Length, FChanges[0].NewLen);
    AssertEquals('first paragraph', 0, FChanges[0].FirstPara);
    AssertEquals('old paragraphs', 3, FChanges[0].OldParaCount);
    AssertEquals('new paragraphs', 2, FChanges[0].NewParaCount);
    AssertTrue('the document still works', d.Execute(TTyRichInsertText.Create(0, 'x')));
    AssertTrue('and undoes', d.CanUndo);
  finally
    s.Free;
    d.Free;
  end;
end;

procedure TTyRichTextIOTest.TestNewDocumentIsUtf8WithThePlatformBreak;
var
  d: TTyRichDocument;
  platformBreak: TTyRichSeparator;
begin
  if sLineBreak = #13#10 then platformBreak := rsCRLF
  else if sLineBreak = #13 then platformBreak := rsCR
  else platformBreak := rsLF;
  AssertTrue('TyRichPlatformLineBreak', TyRichPlatformLineBreak = platformBreak);
  d := TTyRichDocument.Create;
  try
    AssertTrue('UTF-8', d.SourceEncoding = teUtf8);
    AssertFalse('no BOM', d.SourceHasBom);
    AssertEquals('no code page', 0, d.SourceCodePage);
    AssertTrue('the platform break', d.DominantLineBreak = platformBreak);
    d.Execute(TTyRichInsertText.Create(0, 'a'#13'b'#10'c'#13#10'd'));
    AssertText('typed breaks are the platform kind', 'a' + sLineBreak + 'b' + sLineBreak + 'c' +
      sLineBreak + 'd', d.Text.GetText(0, d.Text.Length));
    AssertSameBytes('saved as UTF-8 without a BOM', BytesOf('a' + sLineBreak + 'b' + sLineBreak +
      'c' + sLineBreak + 'd'), SaveBytes(d));
  finally
    d.Free;
  end;
  // a tie goes to the platform break, and so does a text without any
  AssertTrue('tie', TyRichMajorityLineBreak(2, 2, 2) = platformBreak);
  // two-way ties, one of which leaves the platform's kind out whatever the platform is
  AssertTrue('tie CR LF', TyRichMajorityLineBreak(2, 2, 0) = platformBreak);
  AssertTrue('tie CR CRLF', TyRichMajorityLineBreak(2, 0, 2) = platformBreak);
  AssertTrue('tie LF CRLF', TyRichMajorityLineBreak(0, 2, 2) = platformBreak);
  AssertTrue('none', TyRichMajorityLineBreak(0, 0, 0) = platformBreak);
  AssertTrue('CR', TyRichMajorityLineBreak(3, 1, 2) = rsCR);
end;

procedure TTyRichTextIOTest.TestLoadingUtf8KeepsOneCopy;
var
  d: TTyRichDocument;
  m: TMemoryStream;
  content: TBytes;
  h0, h1: PtrUInt;
  budget: Int64;
begin
  content := Repeated(Fixture('utf8-nobom.txt'), 16 * 1024 * 1024);
  m := TMemoryStream.Create;
  d := TTyRichDocument.Create;
  try
    m.WriteBuffer(content[0], System.Length(content));
    m.Position := 0;
    h0 := HeapUsed;
    TyRichLoadText(d, m);
    h1 := HeapUsed;
    AssertTrue('UTF-8', d.SourceEncoding = teUtf8);
    AssertEquals('every byte is in the text', Int64(System.Length(content)), d.Text.ByteCount);
    budget := System.Length(content) + Int64(d.Text.ParaCount) * 32 + 1024 * 1024;
    AssertTrue(Format('loading %d bytes in %d paragraphs took %d bytes of heap, budget %d',
      [System.Length(content), d.Text.ParaCount, Int64(h1) - Int64(h0), budget]),
      Int64(h1) - Int64(h0) <= budget);
  finally
    d.Free;
    m.Free;
  end;
end;

procedure TTyRichTextIOTest.TestLoadingGbkKeepsNoOriginal;
var
  d: TTyRichDocument;
  f: TFileStream;
  path: string;
  content: TBytes;
  h0, h1: PtrUInt;
  budget: Int64;
begin
  content := Repeated(Fixture('gbk.txt'), 16 * 1024 * 1024);
  path := GetTempDir(False) + Format('tyrichedit-gbk-%d.txt', [GetProcessID]);
  f := TFileStream.Create(path, fmCreate);
  try
    f.WriteBuffer(content[0], System.Length(content));
  finally
    f.Free;
  end;
  content := nil;
  // the code page's tables are built once, on first use: not part of a load's cost
  LoadFixture('gbk.txt', teAnsi, 936).Free;
  d := TTyRichDocument.Create;
  f := TFileStream.Create(path, fmOpenRead or fmShareDenyNone);
  try
    h0 := HeapUsed;
    TyRichLoadText(d, f, teAuto, 936);
    h1 := HeapUsed;
    AssertTrue('GBK', d.SourceEncoding = teAnsi);
    AssertText('decoded', SampleLines[0], ParaText(d, 0));
    budget := d.Text.ByteCount + Int64(d.Text.ParaCount) * 32 + 1024 * 1024;
    AssertTrue(Format('loading %d bytes of GBK (%d of UTF-8, %d paragraphs) took %d bytes of ' +
      'heap, budget %d', [f.Size, d.Text.ByteCount, d.Text.ParaCount, Int64(h1) - Int64(h0),
      budget]), Int64(h1) - Int64(h0) <= budget);
  finally
    f.Free;
    d.Free;
    DeleteFile(path);
  end;
end;

procedure TTyRichTextIOTest.TestSavingUsesAFixedBuffer;

  procedure Check(const AMsg: string; const AContent: TBytes; AEncoding: TTyTextEncoding;
    ACodePage: Integer);
  var
    d: TTyRichDocument;
    c: TCheckingStream;
  begin
    d := LoadBytes(AContent, AEncoding, ACodePage);
    c := nil;
    try
      c := TCheckingStream.Create(AContent);
      TyRichSaveText(d, c);
      AssertEquals(AMsg + ': every byte written', Int64(System.Length(AContent)), c.Written);
      AssertEquals(AMsg + ': the bytes as they were', Int64(-1), c.FirstDiff);
      AssertTrue(Format('%s: saving %d bytes used %d bytes of heap', [AMsg,
        System.Length(AContent), c.PeakGrowth]), c.PeakGrowth <= 1024 * 1024);
    finally
      c.Free;
      d.Free;
    end;
  end;

begin
  Check('UTF-8', Repeated(Fixture('utf8-bom.txt'), 16 * 1024 * 1024), teAuto, 0);
  Check('GBK', Repeated(Fixture('gbk.txt'), 16 * 1024 * 1024), teAnsi, 936);
  Check('UTF-16', Concat(BytesOf(#$FF#$FE), Repeated(Copy(Fixture('utf16le.txt'), 2, MaxInt),
    16 * 1024 * 1024)), teAuto, 0);
end;

initialization
  RegisterTest(TTyRichTextIOTest);
end.
