unit test.richedit.rtflazy;

{ RTF parsed on demand: loading only indexes the file (each paragraph's bytes and characters,
  a snapshot of the parse state every CRtfSnapshotBytes), and a paragraph's formats and text
  are parsed when they are first read, from the snapshot before it. What that gives must be
  exactly what parsing the whole file at once gives (TyRichLoadRtfFull), in whatever order the
  paragraphs are read; the index's counts must be the full parse's; a table is one table; a
  load in slices can be read but not changed until it ends, and a cancelled one stays
  read-only; memory stays bounded when every paragraph is read; paragraphs deleted unparsed
  come back unparsed and still loadable. The samples are tests/fixtures/rtf. }

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$codepage utf8}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite;

type
  TTyRtfLazyTest = class(TTestCase)
  private
    FChanges: Integer;
    FAppendedParas: Int64;
    FBadChange: string;
    FProgress: array of Int64;
    FProgressTotal: Int64;
    FSeed: Cardinal;
    function NextRandom(AMax: Integer): Integer;
    procedure DocChanged(Sender: TObject; const AChange: TTyRichChange);
    procedure Progress(Sender: TObject; ADone, ATotal: Int64);
    procedure CheckAgree(const AMsg: string; ALazy, AFull: TTyRichDocument;
      AFirst, ACount: Integer);
    procedure CheckAgreeAt(const AMsg: string; ALazy, AFull: TTyRichDocument;
      ALazyFirst, AFullFirst, ACount: Integer);
    procedure CheckLazyAgainstFull(const AMsg: string; const ABytes: TBytes;
      ARandomOrder: Boolean);
    procedure CheckIndex(const AMsg: string; const ABytes: TBytes);
  published
    // the brief
    procedure TestLazyAndFullParseAgree;
    procedure TestOpeningParsesOnlyWhatIsShown;
    procedure TestAnEditAtTheEndOfALazyDocumentRewritesOnlyThatParagraph;
    procedure TestAnEditAtTheEndOfALazyDocumentSavesTheRestVerbatim;
    // the rulings
    procedure TestIndexCountsAreTheFullParse;
    procedure TestLoadingInSlices;
    procedure TestCancelKeepsWhatWasIndexed;
    procedure TestATableAcrossASnapshotBoundary;
    procedure TestABigTableIsSplitIntoLockedParts;
    procedure TestScrollingThroughEverythingStaysBounded;
    procedure TestDeletedUnparsedParagraphsComeBackOnUndo;
  end;

implementation

const
  MB = 1024 * 1024;

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

function Fixture(const AName: string): TBytes;
begin
  Result := ReadFileBytes(FixtureDir + AName);
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

function Shown(const S: RawByteString): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if (S[i] >= ' ') and (S[i] < #$7F) then Result := Result + S[i]
    else Result := Result + '<' + IntToHex(Ord(S[i]), 2) + '>';
  if Length(Result) > 200 then Result := Copy(Result, 1, 200) + '...';
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

function Utf8Chars(const S: RawByteString): Int64;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to Length(S) do
    if Byte(S[i]) and $C0 <> $80 then Inc(Result);
end;

function LoadWith(const ABytes: TBytes; AFull: Boolean; AMap: TTyRtfSourceMap = nil): TTyRichDocument;
var
  s: TBytesStream;
begin
  Result := TTyRichDocument.Create;
  s := TBytesStream.Create(ABytes);
  try
    try
      if AFull then TyRichLoadRtfFull(Result, s, AMap) else TyRichLoadRtf(Result, s, AMap);
    except
      Result.Free;
      raise;
    end;
  finally
    s.Free;
  end;
end;

{ A sample's header, its body (its paragraphs) repeated until the file has at least ATarget
  bytes, and its trailer. }
type
  // Appends bytes without copying what is there each time.
  TByteBuilder = record
    Data: TBytes;
    Len: Int64;
    procedure Add(const S: RawByteString);
    function Done: TBytes;
  end;

procedure TByteBuilder.Add(const S: RawByteString);
begin
  if Len + Length(S) > Length(Data) then SetLength(Data, (Len + Length(S)) * 2 + 4096);
  if S <> '' then Move(S[1], Data[Len], Length(S));
  Inc(Len, Length(S));
end;

function TByteBuilder.Done: TBytes;
begin
  Result := Copy(Data, 0, Len);
end;

{ The header, body (paragraphs) and trailer of a sample, as the full parse cuts it. }
procedure SampleParts(const ASample: string; out AHeader, ABody, ATrailer: RawByteString);
var
  b: TBytes;
  m: TTyRtfSourceMap;
  d: TTyRichDocument;
begin
  b := Fixture(ASample);
  m := TTyRtfSourceMap.Create;
  try
    d := LoadWith(b, True, m);
    d.Free;
    AHeader := StrOf(b, 0, m.Header.Stop);
    ABody := StrOf(b, m.Header.Stop, m.Trailer.Start - m.Header.Stop);
    ATrailer := StrOf(b, m.Trailer.Start, Length(b) - m.Trailer.Start);
  finally
    m.Free;
  end;
end;

{ A sample's header, its body repeated until the file has at least ATarget bytes, and its
  trailer. }
function Generate(const ASample: string; ATarget: Int64): TBytes;
var
  header, body, trailer: RawByteString;
  bb: TByteBuilder;
begin
  SampleParts(ASample, header, body, trailer);
  bb := Default(TByteBuilder);
  bb.Add(header);
  while bb.Len + Length(trailer) < ATarget do bb.Add(body);
  bb.Add(trailer);
  Result := bb.Done;
end;

{ The re-zh-table sample's header, APad bytes of plain paragraphs, a table of ARows rows of
  three cells, one paragraph after it, the closing brace. }
function TableDocument(APad, ARows: Integer): TBytes;
var
  header, body, trailer: RawByteString;
  i: Integer;
  bb: TByteBuilder;
begin
  SampleParts('re-zh-table.rtf', header, body, trailer);
  bb := Default(TByteBuilder);
  bb.Add(header);
  bb.Add('\pard\f0\fs24 ');
  i := 0;
  while bb.Len < APad do
  begin
    bb.Add('Padding paragraph ' + IntToStr(i) + ' before the table, \''d6\''d0.\par' + #13#10);
    Inc(i);
  end;
  for i := 0 to ARows - 1 do
    bb.Add('\trowd\trgaph108\cellx2400\cellx4800\cellx7200' + #13#10 +
      '\pard\intbl r' + IntToStr(i) + ' a\cell r' + IntToStr(i) + ' \b b\b0\cell r' +
      IntToStr(i) + ' \''d6\''d0\cell\row' + #13#10);
  bb.Add('\pard after the table\par' + #13#10 + '}' + #13#10);
  Result := bb.Done;
end;

{ \f0 is SimSun (GBK) in the header and Arial (1252) after a font table in the middle of
  the body; the same bytes \'d6\'d0 read as one character before it and two after it, with
  a few snapshots on either side. }
function FontTableInTheBody: TBytes;
var
  bb: TByteBuilder;
  i: Integer;
begin
  bb := Default(TByteBuilder);
  bb.Add('{\rtf1\ansi\ansicpg936\deff0{\fonttbl{\f0\fnil\fcharset134 SimSun;}' +
    '{\f1\fswiss\fcharset0 Arial;}}' + #13#10 + '\pard\f0\fs24 ');
  for i := 0 to 3000 do
    bb.Add('before ' + IntToStr(i) + ' \''d6\''d0 {\f1 \''e9}\par' + #13#10);
  bb.Add('{\fonttbl{\f0\fswiss\fcharset0 Arial;}}' + #13#10);
  for i := 0 to 3000 do
    bb.Add('after ' + IntToStr(i) + ' \''d6\''d0 {\f1 \''e9}\par' + #13#10);
  bb.Add('}');
  Result := bb.Done;
end;

type
  // The test's way to a paragraph's value without parsing it.
  TBuilderAccess = class(TTyRichDocBuilder)
  public
    class function Value(ADoc: TTyRichDocument; AIndex: Integer): Pointer;
  end;

class function TBuilderAccess.Value(ADoc: TTyRichDocument; AIndex: Integer): Pointer;
begin
  Result := ParagraphValue(ADoc, AIndex);
end;

{ ---- TTyRtfLazyTest: helpers ---- }

function TTyRtfLazyTest.NextRandom(AMax: Integer): Integer;
begin
  FSeed := FSeed * 1103515245 + 12345;
  Result := (FSeed shr 8) mod Cardinal(AMax);
end;

procedure TTyRtfLazyTest.DocChanged(Sender: TObject; const AChange: TTyRichChange);
var
  d: TTyRichDocument;
begin
  Inc(FChanges);
  d := Sender as TTyRichDocument;
  // a slice: paragraphs come after the last one, which gets its separator
  if (AChange.OldParaCount = 1) and (AChange.FirstPara + AChange.NewParaCount <> d.Text.ParaCount) and
     (FBadChange = '') then
    FBadChange := Format('change %d: paragraphs %d + %d, the text has %d',
      [FChanges, AChange.FirstPara, AChange.NewParaCount, d.Text.ParaCount]);
  if (AChange.OldParaCount = 1) and (AChange.Pos + AChange.NewLen <> d.Text.Length) and
     (FBadChange = '') then
    FBadChange := Format('change %d: %d + %d characters, the text has %d',
      [FChanges, AChange.Pos, AChange.NewLen, d.Text.Length]);
  Inc(FAppendedParas, AChange.NewParaCount - AChange.OldParaCount);
end;

procedure TTyRtfLazyTest.Progress(Sender: TObject; ADone, ATotal: Int64);
begin
  SetLength(FProgress, Length(FProgress) + 1);
  FProgress[High(FProgress)] := ADone;
  FProgressTotal := ATotal;
end;

function SameObject(A, B: TTyRichObject): Boolean;
var
  pa, pb: TTyRichPicture;
begin
  if (A = nil) or (B = nil) then Exit(A = B);
  if A.ClassType <> B.ClassType then Exit(False);
  if A is TTyRichOpaque then
    Exit((TTyRichOpaque(A).Bytes = TTyRichOpaque(B).Bytes) and
      (TTyRichOpaque(A).DisplayText = TTyRichOpaque(B).DisplayText));
  pa := A as TTyRichPicture;
  pb := B as TTyRichPicture;
  Result := (pa.PictureFormat = pb.PictureFormat) and (pa.WidthTwips = pb.WidthTwips) and
    (pa.HeightTwips = pb.HeightTwips) and (pa.RawRtf = pb.RawRtf) and
    (Length(pa.Data) = Length(pb.Data)) and
    ((Length(pa.Data) = 0) or CompareMem(@pa.Data[0], @pb.Data[0], Length(pa.Data)));
end;

procedure TTyRtfLazyTest.CheckAgree(const AMsg: string; ALazy, AFull: TTyRichDocument;
  AFirst, ACount: Integer);
begin
  CheckAgreeAt(AMsg, ALazy, AFull, AFirst, AFirst, ACount);
end;

{ ACount paragraphs from ALazyFirst and from AFullFirst: text, paragraph format, runs
  (formats by value, objects by content), table cells (one table there is one table here). }
procedure TTyRtfLazyTest.CheckAgreeAt(const AMsg: string; ALazy, AFull: TTyRichDocument;
  ALazyFirst, AFullFirst, ACount: Integer);
var
  i, j, k, f: Integer;
  rl, rf: TTyRunArray;
  msg: string;
  cl, cf: TTyRichCell;
  fullTables, lazyTables: TFPList;
begin
  fullTables := TFPList.Create;
  lazyTables := TFPList.Create;
  try
    for i := ALazyFirst to ALazyFirst + ACount - 1 do
    begin
      f := i - ALazyFirst + AFullFirst;
      msg := Format('%s paragraph %d', [AMsg, i]);
      AssertText(msg + ' text', ParaText(AFull, f), ParaText(ALazy, i));
      AssertTrue(msg + ' paragraph format', ALazy.Formats.ParaFormat(ALazy.ParaFormatOf(i)).Equals(
        AFull.Formats.ParaFormat(AFull.ParaFormatOf(f))));
      rl := ALazy.RunsOf(i);
      rf := AFull.RunsOf(f);
      AssertEquals(msg + ' runs', Length(rf), Length(rl));
      for j := 0 to High(rf) do
      begin
        AssertEquals(Format('%s run %d start', [msg, j]), rf[j].Start, rl[j].Start);
        AssertTrue(Format('%s run %d format', [msg, j]), ALazy.Formats.CharFormat(rl[j].Format).Equals(
          AFull.Formats.CharFormat(rf[j].Format)));
        AssertTrue(Format('%s run %d object', [msg, j]), SameObject(rl[j].Obj, rf[j].Obj));
      end;
      cf := AFull.CellAt(f);
      cl := ALazy.CellAt(i);
      AssertEquals(msg + ' in a table', cf <> nil, cl <> nil);
      if cf = nil then Continue;
      AssertEquals(msg + ' cell', cf.Index, cl.Index);
      AssertEquals(msg + ' row', cf.Row.Index, cl.Row.Index);
      AssertEquals(msg + ' row''s cells', cf.Row.CellCount, cl.Row.CellCount);
      AssertText(msg + ' row format', cf.Row.RawFormat, cl.Row.RawFormat);
      AssertEquals(msg + ' rows', cf.Table.RowCount, cl.Table.RowCount);
      AssertEquals(msg + ' locked', cf.Table.StructureLocked, cl.Table.StructureLocked);
      AssertEquals(msg + ' columns', cf.Table.ColBoundaryCount, cl.Table.ColBoundaryCount);
      for k := 0 to cf.Table.ColBoundaryCount - 1 do
        AssertEquals(msg + ' column', cf.Table.ColBoundaries[k], cl.Table.ColBoundaries[k]);
      k := fullTables.IndexOf(cf.Table);
      if k >= 0 then
        AssertTrue(msg + ' the same table as before', lazyTables[k] = Pointer(cl.Table))
      else
      begin
        AssertEquals(msg + ' a table of its own', -1, lazyTables.IndexOf(cl.Table));
        fullTables.Add(cf.Table);
        lazyTables.Add(cl.Table);
      end;
    end;
  finally
    fullTables.Free;
    lazyTables.Free;
  end;
end;

procedure TTyRtfLazyTest.CheckLazyAgainstFull(const AMsg: string; const ABytes: TBytes;
  ARandomOrder: Boolean);
var
  lazy, full: TTyRichDocument;
  order: array of Integer;
  i, j, t: Integer;
begin
  full := LoadWith(ABytes, True);
  lazy := nil;
  try
    lazy := LoadWith(ABytes, False);
    // every interval may stay parsed: this is about what is parsed, not when it goes
    TyRichRtfLoadOf(lazy).MaxResidentIntervals := MaxInt;
    AssertEquals(AMsg + ': paragraphs', full.Text.ParaCount, lazy.Text.ParaCount);
    order := nil;
    SetLength(order, lazy.Text.ParaCount);
    for i := 0 to High(order) do order[i] := i;
    if ARandomOrder then
      for i := High(order) downto 1 do
      begin
        j := NextRandom(i + 1);
        t := order[i];
        order[i] := order[j];
        order[j] := t;
      end;
    for i := 0 to High(order) do lazy.EnsureParsed(order[i]);
    AssertEquals(AMsg + ': integrity', '', lazy.Text.CheckIntegrity);
    CheckAgree(AMsg, lazy, full, 0, full.Text.ParaCount);
  finally
    lazy.Free;
    full.Free;
  end;
end;

{ The index (the lazy load's map and its characters per paragraph) is the full parse's; each
  paragraph then decodes to exactly its counted characters. }
procedure TTyRtfLazyTest.CheckIndex(const AMsg: string; const ABytes: TBytes);
var
  ml, mf: TTyRtfSourceMap;
  lazy, full: TTyRichDocument;
  i: Integer;
  msg: string;
  failedLazy, failedFull: Boolean;
begin
  ml := TTyRtfSourceMap.Create;
  mf := TTyRtfSourceMap.Create;
  lazy := nil;
  full := nil;
  try
    failedLazy := False;
    failedFull := False;
    try
      full := LoadWith(ABytes, True, mf);
    except
      on ETyRichRtf do failedFull := True;
    end;
    try
      lazy := LoadWith(ABytes, False, ml);
    except
      on ETyRichRtf do failedLazy := True;
    end;
    AssertEquals(AMsg + ': both refuse or both read', failedFull, failedLazy);
    if failedFull then Exit;
    AssertEquals(AMsg + ': paragraphs', full.Text.ParaCount, lazy.Text.ParaCount);
    AssertEquals(AMsg + ': ranges', mf.ParaCount, ml.ParaCount);
    AssertEquals(AMsg + ': header', mf.Header.Stop, ml.Header.Stop);
    AssertEquals(AMsg + ': trailer', mf.Trailer.Start, ml.Trailer.Start);
    AssertEquals(AMsg + ': trailer end', mf.Trailer.Stop, ml.Trailer.Stop);
    AssertEquals(AMsg + ': characters', full.Text.Length, lazy.Text.Length);
    for i := 0 to mf.ParaCount - 1 do
    begin
      msg := Format('%s paragraph %d', [AMsg, i]);
      AssertEquals(msg + ' start', mf.Paras[i].Start, ml.Paras[i].Start);
      AssertEquals(msg + ' stop', mf.Paras[i].Stop, ml.Paras[i].Stop);
      AssertEquals(msg + ' characters', full.Text.ParaLength(i), lazy.Text.ParaLength(i));
    end;
    // parsed on demand: the text storage raises when a paragraph decodes to another count
    for i := 0 to lazy.Text.ParaCount - 1 do
    begin
      lazy.EnsureParsed(i);
      AssertEquals(Format('%s paragraph %d decoded', [AMsg, i]), lazy.Text.ParaLength(i),
        Utf8Chars(ParaText(lazy, i)));
    end;
    AssertEquals(AMsg + ': integrity', '', lazy.Text.CheckIntegrity);
  finally
    lazy.Free;
    full.Free;
    ml.Free;
    mf.Free;
  end;
end;

{ ---- the brief ---- }

procedure TTyRtfLazyTest.TestLazyAndFullParseAgree;
var
  sr: TSearchRec;
  files: Integer;
  b: TBytes;
  d: TTyRichDocument;
  load: TTyRtfLoad;
begin
  FSeed := 20261108;
  files := 0;
  if FindFirst(FixtureDir + '*.rtf', faAnyFile, sr) = 0 then
  try
    repeat
      Inc(files);
      CheckLazyAgainstFull(sr.Name, Fixture(sr.Name), True);
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
  AssertTrue('samples', files >= 12);
  // WordPad's writing (\'xx text) over many snapshots
  b := Generate('re-zh-mixed.rtf', 5 * MB);
  CheckLazyAgainstFull('re-zh-mixed x 5 MB', b, True);
  // Word's: \uc2 set in the header, \u with two fallback bytes in every interval
  b := Generate('hand-word-zh.rtf', 2 * MB);
  d := LoadWith(b, False);
  try
    load := TyRichRtfLoadOf(d);
    AssertTrue('Word: snapshots in \uc2 text', load.SnapshotCount >= 20);
  finally
    d.Free;
  end;
  CheckLazyAgainstFull('hand-word-zh x 2 MB', b, True);
  // tables, some of them across a snapshot boundary
  CheckLazyAgainstFull('re-zh-table x 1 MB', Generate('re-zh-table.rtf', MB), True);
  // a font table again in the middle of the body: what comes after it decodes by it, what
  // comes before by the header's
  CheckLazyAgainstFull('a font table in the body', FontTableInTheBody, True);
end;

procedure TTyRtfLazyTest.TestOpeningParsesOnlyWhatIsShown;
var
  d: TTyRichDocument;
  load: TTyRtfLoad;
  last: Integer;
begin
  d := LoadWith(Generate('re-zh-mixed.rtf', 5 * MB), False);
  try
    load := TyRichRtfLoadOf(d);
    AssertTrue('loaded by the RTF reader', load <> nil);
    AssertEquals('opening parses nothing', 0, load.ParsedBytes);
    AssertTrue('a snapshot every 64 KB', load.SnapshotCount >= 5 * MB div CRtfSnapshotBytes - 1);
    d.EnsureParsed(0);
    AssertTrue('first paragraph', ParaText(d, 0) <> '');
    last := d.Text.ParaCount - 1;
    d.EnsureParsed(last);
    AssertTrue('last paragraph', ParaText(d, last) <> '');
    AssertEquals('two parses', 2, load.ParseCount);
    AssertTrue(Format('parsed %d bytes', [load.ParsedBytes]),
      load.ParsedBytes <= 3 * CRtfSnapshotBytes);
  finally
    d.Free;
  end;
end;

procedure TTyRtfLazyTest.TestAnEditAtTheEndOfALazyDocumentRewritesOnlyThatParagraph;
var
  b: TBytes;
  d: TTyRichDocument;
  load: TTyRtfLoad;
  m: TTyRtfSourceMap;
  last, i: Integer;
  src, bytes: Int64;
  r: TTyRtfRange;
begin
  b := Generate('re-zh-mixed.rtf', 5 * MB);
  m := TTyRtfSourceMap.Create;
  d := nil;
  try
    d := LoadWith(b, False, m);
    load := TyRichRtfLoadOf(d);
    last := d.Text.ParaCount - 1;
    AssertTrue('typed at the end', d.Execute(TTyRichInsertText.Create(d.Text.Length, 'X')));
    AssertTrue('the last paragraph is no longer the file''s',
      not d.Text.ParaLazySource(last, src, bytes));
    AssertFalse('the writer rewrites it', load.ParaSource(last, r));
    for i := 0 to last - 1 do
    begin
      AssertTrue(Format('paragraph %d is still the file''s', [i]),
        d.Text.ParaLazySource(i, src, bytes));
      AssertEquals(Format('paragraph %d at its bytes', [i]), m.Paras[i].Start, src);
      AssertEquals(Format('paragraph %d all its bytes', [i]), m.Paras[i].Stop - m.Paras[i].Start,
        bytes);
      AssertTrue(Format('paragraph %d goes back verbatim', [i]), load.ParaSource(i, r));
      AssertEquals(Format('paragraph %d range', [i]), m.Paras[i].Start, r.Start);
    end;
    AssertEquals('only the last interval was parsed', 1, load.ParseCount);
    AssertTrue(Format('parsed %d bytes', [load.ParsedBytes]),
      load.ParsedBytes <= 2 * CRtfSnapshotBytes);
  finally
    d.Free;
    m.Free;
  end;
end;

procedure TTyRtfLazyTest.TestAnEditAtTheEndOfALazyDocumentSavesTheRestVerbatim;
var
  b, o: TBytes;
  d, r: TTyRichDocument;
  load: TTyRtfLoad;
  s: TBytesStream;
  last, i: Integer;
  parsed, cursor: Int64;
  range: TTyRtfRange;
  before: RawByteString;
begin
  // the 5 MB document of the test above, 'X' typed at its end, saved
  b := Generate('re-zh-mixed.rtf', 5 * MB);
  d := LoadWith(b, False);
  r := nil;
  s := TBytesStream.Create;
  try
    load := TyRichRtfLoadOf(d);
    last := d.Text.ParaCount - 1;
    before := ParaText(d, last);
    AssertTrue('typed at the end', d.Execute(TTyRichInsertText.Create(d.Text.Length, 'X')));
    parsed := load.ParsedBytes;
    TyRichSaveRtf(d, s);
    o := Copy(s.Bytes, 0, s.Size);
    AssertEquals('saving parsed nothing', parsed, load.ParsedBytes);
    // the header's bytes, then every paragraph but the last from its range, byte for byte
    AssertTrue('the header', (Length(o) > load.Header.Stop) and
      CompareMem(@o[0], @b[0], load.Header.Stop));
    cursor := load.Header.Stop;
    for i := 0 to last - 1 do
    begin
      AssertTrue(Format('paragraph %d is the file''s', [i]), load.ParaSource(i, range));
      AssertEquals(Format('paragraph %d follows the one before', [i]), cursor, range.Start);
      if not CompareMem(@o[range.Start], @b[range.Start], range.Stop - range.Start) then
        Fail(Format('paragraph %d was not copied as it is', [i]));
      cursor := range.Stop;
    end;
    // then the last paragraph rewritten, then the trailer's bytes
    AssertTrue('the trailer', CompareMem(@o[Length(o) - (Length(b) - load.Trailer.Start)],
      @b[load.Trailer.Start], Length(b) - load.Trailer.Start));
    AssertTrue('the rewritten paragraph is all that lies between',
      Length(o) - (Length(b) - load.Trailer.Start) - cursor < 2000);
    r := LoadWith(o, True);
    AssertEquals('read back: paragraphs', d.Text.ParaCount, r.Text.ParaCount);
    // (as bytes: joining it to a literal would convert between code pages)
    SetLength(before, Length(before) + 1);
    before[Length(before)] := 'X';
    AssertText('read back: the last paragraph, with the X', before, ParaText(r, last));
    CheckAgreeAt('read back: in the model''s formats', d, r, last, last, 1);
  finally
    s.Free;
    r.Free;
    d.Free;
  end;
end;

{ ---- the rulings ---- }

procedure TTyRtfLazyTest.TestIndexCountsAreTheFullParse;
const
  Inline: array[0..6] of RawByteString = (
    // the halves of a pair in two fonts of one code page do not join
    '{\rtf1\ansi\ansicpg936{\fonttbl{\f0\fcharset134 S;}{\f1\fcharset134 H;}}' +
      '\f0 x\''d6\f1\''d0 z\par}',
    // a lead byte waiting across a group, a word and a literal trail byte
    '{\rtf1\ansi\ansicpg936{\fonttbl{\f0\fcharset134 S;}}\f0 a\''d6{\b\''d0}b\''d6\i A\''d6\par}',
    // Symbol bytes, control bytes written as \'xx and raw
    '{\rtf1\ansi{\fonttbl{\f0\fcharset2 Symbol;}{\f1 Arial;}}\f0\''41\''b7 a\f1\''01\''09b'#1'c'#9'd\par}',
    // \u with two fallback bytes, a fallback cut short by a word, \uc0
    '{\rtf1\ansicpg936{\fonttbl{\f0\fcharset134 S;}}\f0\uc2\u20013\''d6\''d0 x\u20013\''d6\b y{\uc0\u20013 z}\par}',
    // a row definition and its words, then text and cells
    '{\rtf1 \trowd\trgaph108\trleft0\clbrdrt\brdrs\cellx100\cellx200 a\cell \''41\cell\row b\par}',
    // \bin data, unknown words and symbols in the body
    '{\rtf1 a\foo7\bar-3 b{\*\baz q}\|c{\pict\pngblip\bin3 {}} d\par e}',
    // a group that opens with an unknown word, groups with nothing in them
    '{\rtf1 {\qwe a}{{}}\par{\b\par}{\i x}}');
var
  sr: TSearchRec;
  b: TBytes;
  i: Integer;

  procedure Prefixes(const AName: string);
  var
    whole: TBytes;
    n: Integer;
  begin
    whole := Fixture(AName);
    for n := 0 to Length(whole) do
      CheckIndex(Format('%s cut at %d', [AName, n]), Copy(whole, 0, n));
  end;

begin
  if FindFirst(FixtureDir + '*.rtf', faAnyFile, sr) = 0 then
  try
    repeat
      CheckIndex(sr.Name, Fixture(sr.Name));
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
  // what the scan reads in its own way, beside what the samples have
  for i := 0 to High(Inline) do CheckIndex(Format('inline %d', [i]), BytesOf(Inline[i]));
  b := Generate('re-zh-mixed.rtf', 3 * MB);
  CheckIndex('re-zh-mixed x 3 MB', b);
  CheckIndex('hand-word-zh x 3 MB', Generate('hand-word-zh.rtf', 3 * MB));
  CheckIndex('re-zh-table x 3 MB', Generate('re-zh-table.rtf', 3 * MB));
  Prefixes('hand-uc.rtf');
  Prefixes('re-zh-table.rtf');
end;

procedure TTyRtfLazyTest.TestLoadingInSlices;
var
  b: TBytes;
  s: TBytesStream;
  d, full: TTyRichDocument;
  load: TTyRtfLoad;
  steps, first, mid, i: Integer;
  before: RawByteString;
begin
  b := Generate('re-zh-mixed.rtf', 2 * MB);
  full := LoadWith(b, True);
  d := TTyRichDocument.Create;
  s := TBytesStream.Create(b);
  try
    FChanges := 0;
    FAppendedParas := 0;
    FBadChange := '';
    FProgress := nil;
    d.OnChange := @DocChanged;
    load := TyRichBeginLoadRtf(d, s, 128 * 1024);
    AssertEquals('the load begins with one change', 1, FChanges);
    load.OnLoadProgress := @Progress;
    AssertTrue('still loading', d.Loading);
    AssertFalse('not complete yet', load.Done);
    first := d.Text.ParaCount;
    AssertTrue(Format('a part is there (%d paragraphs)', [first]),
      (first > 100) and (first < full.Text.ParaCount));
    // what is there can be read, and is what the whole file says
    CheckAgree('first slice', d, full, 0, first - 1);
    // and cannot be changed
    before := ParaText(d, 0);
    AssertFalse('no command while loading', d.Execute(TTyRichInsertText.Create(0, 'X')));
    AssertText('unchanged', before, ParaText(d, 0));
    AssertFalse('not modified', d.Modified);
    steps := 0;
    while not load.Step(256 * 1024) do
    begin
      Inc(steps);
      // the paragraph that came last, read while the load goes on
      mid := d.Text.ParaCount - 1;
      d.EnsureParsed(mid);
      AssertTrue('readable while loading', ParaText(d, mid) <> '');
      AssertTrue('runaway load', steps < 1000);
    end;
    AssertTrue('several slices', steps >= 4);
    AssertEquals('changes: ' + FBadChange, '', FBadChange);
    // the load's first change took the empty document's one paragraph to the first slice
    AssertEquals('every paragraph reported', Int64(full.Text.ParaCount - 1), FAppendedParas);
    AssertTrue('progress reported', Length(FProgress) >= steps);
    for i := 1 to High(FProgress) do
      AssertTrue('progress grows', FProgress[i] >= FProgress[i - 1]);
    AssertEquals('progress ends at the total', FProgressTotal, FProgress[High(FProgress)]);
    AssertEquals('the total is the file', Int64(Length(b)), FProgressTotal);
    AssertFalse('loaded', d.Loading);
    AssertFalse('complete', d.Incomplete);
    AssertEquals('all paragraphs', full.Text.ParaCount, d.Text.ParaCount);
    AssertEquals('integrity', '', d.Text.CheckIntegrity);
    TyRichRtfLoadOf(d).MaxResidentIntervals := MaxInt;
    CheckAgree('after the slices', d, full, 0, full.Text.ParaCount);
    AssertTrue('editable now', d.Execute(TTyRichInsertText.Create(0, 'X')));
    AssertTrue('modified', d.Modified);
  finally
    d.Free;
    s.Free;
    full.Free;
  end;
end;

procedure TTyRtfLazyTest.TestCancelKeepsWhatWasIndexed;
var
  b: TBytes;
  s: TBytesStream;
  d, full: TTyRichDocument;
  load: TTyRtfLoad;
  n: Integer;
  r: TTyRtfRange;
begin
  b := Generate('re-zh-mixed.rtf', 2 * MB);
  full := LoadWith(b, True);
  d := TTyRichDocument.Create;
  s := TBytesStream.Create(b);
  try
    load := TyRichBeginLoadRtf(d, s, 128 * 1024);
    load.Step(128 * 1024);
    load.Cancel;
    n := d.Text.ParaCount;
    AssertTrue('a part', (n > 100) and (n < full.Text.ParaCount));
    AssertTrue('incomplete', d.Incomplete);
    AssertFalse('not loading', d.Loading);
    AssertTrue('cancelled', load.Cancelled);
    AssertFalse('never done', load.Step(MaxInt));
    AssertEquals('nothing more comes', n, d.Text.ParaCount);
    AssertFalse('read-only', d.Execute(TTyRichInsertText.Create(0, 'X')));
    AssertEquals('integrity', '', d.Text.CheckIntegrity);
    // the part is the file's first paragraphs, every one of them whole
    TyRichRtfLoadOf(d).MaxResidentIntervals := MaxInt;
    CheckAgree('cancelled', d, full, 0, n);
    AssertTrue('its last paragraph is the file''s', load.ParaSource(n - 1, r));
  finally
    d.Free;
    s.Free;
    full.Free;
  end;
end;

procedure TTyRtfLazyTest.TestATableAcrossASnapshotBoundary;
var
  b: TBytes;
  pass, i, firstCell, lastCell, k: Integer;
  full, d: TTyRichDocument;
  m: TTyRtfSourceMap;
  load: TTyRtfLoad;
  across: Boolean;
  t: TTyRichTable;
begin
  b := TableDocument(50000, 400);
  m := TTyRtfSourceMap.Create;
  full := LoadWith(b, True, m);
  try
    firstCell := -1;
    lastCell := -1;
    for i := 0 to full.Text.ParaCount - 1 do
      if full.CellAt(i) <> nil then
      begin
        if firstCell < 0 then firstCell := i;
        lastCell := i;
      end;
    AssertEquals('one table of 400 rows', 400, full.CellAt(firstCell).Table.RowCount);
    for pass := 0 to 1 do
    begin
      d := LoadWith(b, False);
      try
        load := TyRichRtfLoadOf(d);
        across := False;
        for k := 1 to load.IntervalCount - 1 do
          if (load.IntervalStart(k) > m.Paras[firstCell].Start) and
             (load.IntervalStart(k) < m.Paras[lastCell].Stop) then
            across := True;
        AssertTrue('a snapshot inside the table', across);
        // one order, then the other
        if pass = 0 then
        begin
          d.EnsureParsed(lastCell - 3);
          d.EnsureParsed(firstCell + 1);
        end
        else
        begin
          d.EnsureParsed(firstCell + 1);
          d.EnsureParsed(lastCell - 3);
        end;
        t := d.CellAt(firstCell).Table;
        for i := firstCell to lastCell do
          AssertTrue(Format('pass %d: paragraph %d in the one table', [pass, i]),
            d.CellAt(i).Table = t);
        AssertEquals('rows', 400, t.RowCount);
        AssertFalse('not locked', t.StructureLocked);
        load.MaxResidentIntervals := MaxInt;
        CheckAgree(Format('pass %d', [pass]), d, full, 0, full.Text.ParaCount);
      finally
        d.Free;
      end;
    end;
  finally
    full.Free;
    m.Free;
  end;
end;

procedure TTyRtfLazyTest.TestABigTableIsSplitIntoLockedParts;
var
  b: TBytes;
  full, d: TTyRichDocument;
  i, firstCell, lastCell, rows: Integer;
  parts: TFPList;
  t: TTyRichTable;
begin
  b := TableDocument(1000, 14000);
  AssertTrue('a table over 1 MB', Length(b) > CRtfBigTableBytes + 100000);
  full := LoadWith(b, True);
  d := LoadWith(b, False);
  parts := TFPList.Create;
  try
    // read from the middle first
    d.EnsureParsed(d.Text.ParaCount div 2);
    TyRichRtfLoadOf(d).MaxResidentIntervals := MaxInt;
    firstCell := -1;
    lastCell := -1;
    for i := 0 to full.Text.ParaCount - 1 do
    begin
      AssertText(Format('paragraph %d', [i]), ParaText(full, i), ParaText(d, i));
      AssertEquals(Format('paragraph %d in a table', [i]), full.CellAt(i) <> nil, d.CellAt(i) <> nil);
      if full.CellAt(i) = nil then Continue;
      if firstCell < 0 then firstCell := i;
      lastCell := i;
      AssertEquals(Format('paragraph %d cell', [i]), full.CellAt(i).Index, d.CellAt(i).Index);
      t := d.CellAt(i).Table;
      if parts.IndexOf(t) < 0 then parts.Add(t);
    end;
    AssertTrue('split into parts', parts.Count >= 2);
    rows := 0;
    for i := 0 to parts.Count - 1 do
    begin
      AssertTrue('a part cannot grow', TTyRichTable(parts[i]).StructureLocked);
      Inc(rows, TTyRichTable(parts[i]).RowCount);
    end;
    AssertEquals('every row in one part', 14000, rows);
    AssertEquals('the full parse: one table', 14000, full.CellAt(firstCell).Table.RowCount);
    AssertTrue('last cell', lastCell > firstCell);
  finally
    parts.Free;
    d.Free;
    full.Free;
  end;
end;

procedure TTyRtfLazyTest.TestScrollingThroughEverythingStaysBounded;
var
  b: TBytes;
  s: TBytesStream;
  d: TTyRichDocument;
  load: TTyRtfLoad;
  base, grown, bound: Int64;
  i, n, mid, parses: Integer;
  src, bytes: Int64;
  text0, textMid: RawByteString;
  runs0, runsMid: array of TTyCharFormat;
  r: TTyRunArray;
  fmt0, fmtMid: TTyParaFormat;

  procedure Capture(AIndex: Integer; out AText: RawByteString;
    var ARuns: array of TTyCharFormat; out AFormat: TTyParaFormat);
  var
    j: Integer;
  begin
    AText := ParaText(d, AIndex);
    r := d.RunsOf(AIndex);
    for j := 0 to High(r) do
      if j <= High(ARuns) then ARuns[j] := d.Formats.CharFormat(r[j].Format);
    AFormat := d.Formats.ParaFormat(d.ParaFormatOf(AIndex));
  end;

begin
  b := Generate('re-zh-mixed.rtf', 20 * MB);
  s := TBytesStream.Create(b);
  d := TTyRichDocument.Create;
  try
    base := GetFPCHeapStatus.CurrHeapUsed;
    TyRichLoadRtf(d, s);
    load := TyRichRtfLoadOf(d);
    n := d.Text.ParaCount;
    grown := GetFPCHeapStatus.CurrHeapUsed - base;
    bound := Int64(Length(b)) + 40 * Int64(n) + load.SnapshotBytes + MB;
    AssertTrue(Format('after loading: %d bytes for %d paragraphs, bound %d (snapshots %d)',
      [grown, n, bound, load.SnapshotBytes]), grown <= bound);
    SetLength(runs0, 64);
    SetLength(runsMid, 64);
    mid := n div 2;
    for i := 0 to n - 1 do
    begin
      d.EnsureParsed(i);
      if i = 0 then Capture(0, text0, runs0, fmt0)
      else if i = mid then Capture(mid, textMid, runsMid, fmtMid)
      else ParaText(d, i);
    end;
    grown := GetFPCHeapStatus.CurrHeapUsed - base;
    AssertTrue(Format('after reading everything: %d bytes, file %d', [grown, Length(b)]),
      grown <= 2 * Int64(Length(b)));
    AssertTrue(Format('%d intervals stay parsed', [load.ResidentIntervals]),
      load.ResidentIntervals <= load.MaxResidentIntervals);
    // the first and middle intervals went back to unparsed: asked again, the same answer
    parses := load.ParseCount;
    AssertTrue('paragraph 0 is the file''s', d.Text.ParaLazySource(0, src, bytes));
    AssertFalse('its text went', d.Text.IsDecoded(src));
    AssertTrue('its formats went', TBuilderAccess.Value(d, 0) = nil);
    AssertText('paragraph 0 again', text0, ParaText(d, 0));
    r := d.RunsOf(0);
    for i := 0 to High(r) do
      AssertTrue('paragraph 0 run again', d.Formats.CharFormat(r[i].Format).Equals(runs0[i]));
    AssertTrue('paragraph 0 format again', d.Formats.ParaFormat(d.ParaFormatOf(0)).Equals(fmt0));
    AssertTrue('parsed again', load.ParseCount > parses);
    AssertText('middle again', textMid, ParaText(d, mid));
    r := d.RunsOf(mid);
    for i := 0 to High(r) do
      AssertTrue('middle run again', d.Formats.CharFormat(r[i].Format).Equals(runsMid[i]));
    AssertTrue('middle format again', d.Formats.ParaFormat(d.ParaFormatOf(mid)).Equals(fmtMid));
    AssertEquals('integrity', '', d.Text.CheckIntegrity);
  finally
    d.Free;
    s.Free;
  end;
end;

procedure TTyRtfLazyTest.TestDeletedUnparsedParagraphsComeBackOnUndo;
var
  b: TBytes;
  full, d: TTyRichDocument;
  load: TTyRtfLoad;
  a, z, k, i, parses, b2, e2: Integer;
  pos, len: TTyRichPos;
  src, bytes: Int64;

  function Fresh: TTyRichDocument;
  begin
    Result := LoadWith(b, False);
    TyRichRtfLoadOf(Result).MaxResidentIntervals := MaxInt;
  end;

begin
  b := Generate('re-zh-mixed.rtf', 600 * 1024);
  full := LoadWith(b, True);
  try
    // paragraphs 10 to 20, deleted without being read, then the undo
    d := Fresh;
    try
      pos := d.Text.ParaStart(10);
      len := d.Text.ParaStart(21) - pos;
      AssertTrue('deleted', d.Execute(TTyRichDelete.Create(pos, len)));
      AssertEquals('11 paragraphs fewer', full.Text.ParaCount - 11, d.Text.ParaCount);
      d.Undo;
      AssertEquals('back', full.Text.ParaCount, d.Text.ParaCount);
      for i := 10 to 20 do
        AssertTrue(Format('paragraph %d is the file''s again', [i]),
          d.Text.ParaLazySource(i, src, bytes));
      CheckAgree('10-20 back', d, full, 0, full.Text.ParaCount);
    finally
      d.Free;
    end;
    // a whole interval deleted while nothing in it was parsed: it comes back unparsed and
    // loads from its source
    d := Fresh;
    try
      load := TyRichRtfLoadOf(d);
      AssertTrue('intervals', load.IntervalCount >= 6);
      k := 2;
      a := load.IntervalFirstPara(k);
      z := load.IntervalFirstPara(k + 1);
      pos := d.Text.ParaStart(a) - 1;
      len := d.Text.ParaStart(z) - pos;
      AssertTrue('deleted', d.Execute(TTyRichDelete.Create(pos, len)));
      AssertEquals('the intervals around it were parsed, not it', 2, load.ParseCount);
      // an edit elsewhere, before it
      AssertTrue('typed', d.Execute(TTyRichInsertText.Create(d.Text.ParaStart(3), 'abc' + #13#10 + 'def')));
      // what comes after reads right where it is now: z - a paragraphs fewer
      b2 := load.IntervalFirstPara(k + 2);
      e2 := load.IntervalFirstPara(k + 3);
      for i := b2 to e2 - 1 do d.EnsureParsed(i - (z - a));
      CheckAgreeAt('after the delete and the insert', d, full, b2 - (z - a), b2, e2 - b2);
      d.Undo;
      d.Undo;
      AssertEquals('back', full.Text.ParaCount, d.Text.ParaCount);
      for i := a to z - 1 do
      begin
        AssertTrue(Format('paragraph %d is the file''s again', [i]),
          d.Text.ParaLazySource(i, src, bytes));
        AssertTrue(Format('paragraph %d is unparsed again', [i]),
          TBuilderAccess.Value(d, i) = nil);
      end;
      parses := load.ParseCount;
      d.EnsureParsed(a + 1);
      AssertEquals('it is parsed once it is read', parses + 1, load.ParseCount);
      CheckAgree('interval back', d, full, 0, full.Text.ParaCount);
    finally
      d.Free;
    end;
  finally
    full.Free;
  end;
end;

initialization
  RegisterTest(TTyRtfLazyTest);
end.
