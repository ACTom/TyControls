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
  Classes, SysUtils, Graphics, fpcunit, testregistry,
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
    // a walk that asks for values, checked against the whole parse
    procedure CheckWalkValues(const AMsg: string; const ABytes: TBytes);
    procedure WalkValue(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
      var AContinue: Boolean);
  private
    FWalkLazy, FWalkFull: TTyRichDocument;
    FWalkMsg: string;
    FWalked: Integer;
  published
    procedure TestLazyAndFullParseAgree;
    procedure TestOpeningParsesOnlyWhatIsShown;
    procedure TestAnEditAtTheEndOfALazyDocumentRewritesOnlyThatParagraph;
    procedure TestAnEditAtTheEndOfALazyDocumentSavesTheRestVerbatim;
    // the index, slices, tables across intervals, what stays parsed, undo over unparsed text
    procedure TestIndexCountsAreTheFullParse;
    procedure TestLoadingInSlices;
    procedure TestCancelKeepsWhatWasIndexed;
    procedure TestATableAcrossASnapshotBoundary;
    procedure TestABigTableIsSplitIntoLockedParts;
    procedure TestScrollingThroughEverythingStaysBounded;
    procedure TestDeletedUnparsedParagraphsComeBackOnUndo;
    procedure TestWordPadsOwnWritingStaysBounded;
    procedure TestTablesOneAfterAnotherDoNotChain;
    procedure TestReadingInsideATableWhileItLoads;
    procedure TestAGroupParsedWhileLoadingAnswersForItsIntervalOnly;
    procedure TestAReadScopeKeepsWhatWasRead;
    procedure TestTheLeastRecentlyUsedIntervalGoes;
    procedure TestUntouchedCellsStayTheFilesOwnAfterTheirIntervalGoes;
    procedure TestAnIntervalParsedAgainInsideAScopeKeepsItsParagraphs;
    procedure TestARowWithANestedTableIsSavedAsItWas;
    procedure TestTheFullLoadIsOneParseThatStays;
    procedure TestDeletedParagraphsUndoneAfterTheirIntervalWentAreStillTheFilesOwn;
    procedure TestAWalkWithValuesGivesTheParseAndSetsNothing;
    procedure TestARowReadWhileItLoadsStaysOneRow;
    procedure TestAnEditUndoneInsideAParagraphGivesTheFileBack;
    procedure TestAnUndoneInsertKeepsTheEditNotTheParagraph;
    procedure TestUndoAndRedoCopyAParagraphOnce;
    procedure TestRandomEditsUndoneAndRedone;
    procedure TestAPlainParagraphUndoneAfterItsIntervalWentIsTheFilesOwn;
    procedure TestKeptValuesCostLittleInAnyOrder;
    procedure TestTheDefaultFontNamedAgainInTheBody;
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

const
  // a header for generated documents: one Chinese font
  PlainHead = '{\rtf1\ansi\ansicpg936\deff0{\fonttbl{\f0\fnil\fcharset134 SimSun;}}' + #13#10 +
    '\pard\f0\fs24 ';

{ ARows rows of three cells, as RichEdit writes them. }
procedure AddRows(var ABuilder: TByteBuilder; ARows: Integer);
var
  i: Integer;
begin
  for i := 0 to ARows - 1 do
    ABuilder.Add('\trowd\trgaph108\cellx2400\cellx4800\cellx7200' + #13#10 +
      '\pard\intbl r' + IntToStr(i) + ' a\cell r' + IntToStr(i) + ' b\cell r' +
      IntToStr(i) + ' c\cell\row' + #13#10);
end;

{ One paragraph and a table of ARows rows, again and again up to ATarget bytes: almost every
  snapshot lies inside a table. }
function TablesDocument(ARows: Integer; ATarget: Int64): TBytes;
var
  bb: TByteBuilder;
  k: Integer;
begin
  bb := Default(TByteBuilder);
  bb.Add(PlainHead);
  k := 0;
  while bb.Len < ATarget do
  begin
    bb.Add('\pard between tables ' + IntToStr(k) + '\par' + #13#10);
    AddRows(bb, ARows);
    Inc(k);
  end;
  bb.Add('\pard the end\par' + #13#10 + '}');
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

  // A document that says how many paragraph values are alive.
  TCountingDoc = class(TTyRichDocument)
  public
    function Live: Integer;
  end;

function TCountingDoc.Live: Integer;
begin
  Result := LiveParaData;
end;

class function TBuilderAccess.Value(ADoc: TTyRichDocument; AIndex: Integer): Pointer;
begin
  Result := ParagraphValue(ADoc, AIndex);
end;

{ ---- TTyRtfLazyTest: helpers ---- }

function TTyRtfLazyTest.NextRandom(AMax: Integer): Integer;
begin
  // (a linear congruential step: it wraps around by design)
  {$PUSH}{$Q-}{$R-}
  FSeed := FSeed * 1103515245 + 12345;
  {$POP}
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
  if A.RawUc <> B.RawUc then Exit(False);
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
      AssertEquals(msg + ' row holds a nested table', cf.Row.HoldsNestedTable,
        cl.Row.HoldsNestedTable);
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
  // what WordPad itself saved: character words never reset, a table from Word in every
  // screenful
  CheckLazyAgainstFull('wp-zh-table x 1 MB', Generate('wp-zh-table.rtf', MB), True);
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

{ ---- the index, slices, tables across intervals, what stays parsed, undo ---- }

procedure TTyRtfLazyTest.TestIndexCountsAreTheFullParse;
const
  Inline: array[0..9] of RawByteString = (
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
    '{\rtf1 {\qwe a}{{}}\par{\b\par}{\i x}}',
    // \u with a number that is no character: counted as the one character it reads as
    '{\rtf1 a\u1114112?b\par c\par}',
    '{\rtf1 a\u-70000?b\u70000?\par c\par}',
    '{\rtf1 a\u2147483647?b\par c\par}');
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
  CheckIndex('wp-zh-table x 2 MB', Generate('wp-zh-table.rtf', 2 * MB));
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
    // (a memory manager that does not count would let every bound below pass)
    AssertTrue('the heap is counted: the file''s bytes are in it',
      GetFPCHeapStatus.CurrHeapUsed - base >= Length(b));
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

{ WordPad's files, as large ones: it writes character properties as bare words and resets
  none (the table sample toggles LANG and KERNING in every screenful). The parse state must
  not grow with the document: a snapshot is as small at the end as at the start, a read
  parses its interval, a run carries the words in effect and no more, the formats are the
  few the file has, and reading everything leaves no more than the usual behind. }
procedure TTyRtfLazyTest.TestWordPadsOwnWritingStaysBounded;

  procedure Check(const ASample: string; ATarget: Int64);
  var
    b: TBytes;
    s: TBytesStream;
    d: TTyRichDocument;
    load: TTyRtfLoad;
    base, loaded, grown, before: Int64;
    n, i, j, extra, maxExtra: Integer;
    r: TTyRunArray;
  begin
    b := Generate(ASample, ATarget);
    s := TBytesStream.Create(b);
    d := TTyRichDocument.Create;
    try
      base := GetFPCHeapStatus.CurrHeapUsed;
      TyRichLoadRtf(d, s);
      load := TyRichRtfLoadOf(d);
      // (a memory manager that does not count would let every bound below pass)
      AssertTrue(ASample + ': the heap is counted: the file''s bytes are in it',
        GetFPCHeapStatus.CurrHeapUsed - base >= Length(b));
      n := d.Text.ParaCount;
      loaded := GetFPCHeapStatus.CurrHeapUsed - base;
      AssertTrue(Format('%s: after loading %d bytes for %d paragraphs, file %d', [ASample, loaded,
        n, Length(b)]), loaded <= Int64(Length(b)) + 40 * Int64(n) + load.SnapshotBytes + MB);
      AssertTrue(ASample + ': snapshots', load.SnapshotCount >= ATarget div CRtfSnapshotBytes - 2);
      AssertTrue(Format('%s: %d snapshots hold %d bytes', [ASample, load.SnapshotCount,
        load.SnapshotBytes]), load.SnapshotBytes <= Int64(load.SnapshotCount) * 1024);
      // one read parses one interval (two when a table lies across its end)
      before := load.ParsedBytes;
      d.EnsureParsed(n - 1);
      AssertTrue(Format('%s: reading the last paragraph parsed %d bytes', [ASample,
        load.ParsedBytes - before]), load.ParsedBytes - before <= 3 * CRtfSnapshotBytes);
      before := load.ParsedBytes;
      d.EnsureParsed(n div 2);
      AssertTrue(Format('%s: reading a middle paragraph parsed %d bytes', [ASample,
        load.ParsedBytes - before]), load.ParsedBytes - before <= 3 * CRtfSnapshotBytes);
      maxExtra := 0;
      for i := 0 to n - 1 do
      begin
        r := d.RunsOf(i);
        for j := 0 to High(r) do
        begin
          extra := d.Formats.CharFormat(r[j].Format).Extra.Count;
          if extra > maxExtra then maxExtra := extra;
        end;
        ParaText(d, i);
      end;
      AssertTrue(Format('%s: a run carries %d kept words', [ASample, maxExtra]), maxExtra <= 2);
      AssertTrue(Format('%s: %d character formats', [ASample, d.Formats.CharCount]),
        d.Formats.CharCount <= 16);
      AssertTrue(Format('%s: %d intervals stay parsed', [ASample, load.ResidentIntervals]),
        load.ResidentIntervals <= load.MaxResidentIntervals);
      // what stays is what the load left and the intervals still parsed, whatever the size
      // of the file (an interval's paragraphs, runs, cells and text: a few times its bytes)
      grown := GetFPCHeapStatus.CurrHeapUsed - base;
      AssertTrue(Format('%s: after reading everything %d bytes, after loading %d', [ASample, grown,
        loaded]), grown <= loaded + Int64(load.MaxResidentIntervals) * 8 * CRtfSnapshotBytes);
      AssertEquals(ASample + ': integrity', '', d.Text.CheckIntegrity);
    finally
      d.Free;
      s.Free;
    end;
  end;

begin
  Check('wp-zh-table.rtf', 3 * MB);
  Check('wp-zh-mixed.rtf', 3 * MB);
end;

{ A document that is mostly tables has a table across almost every snapshot. Tables that
  lie in the same intervals are parsed together, so that each is one table - but only up to
  CRtfGroupIntervals intervals: past that the tables are a chain (each links two intervals,
  the next links on), and a read parses its block of CRtfGroupIntervals intervals, the
  tables cut at the block's ends being parts that cannot grow. }
procedure TTyRtfLazyTest.TestTablesOneAfterAnotherDoNotChain;

  procedure Check(ARows: Integer; AChain: Boolean);
  var
    b: TBytes;
    d, full: TTyRichDocument;
    load: TTyRtfLoad;
    i, k, lo, hi, mid, locked, rows, fullRows: Integer;
    before, limit: Int64;
    tables: TFPList;
    t: TTyRichTable;
    msg: string;
  begin
    msg := Format('tables of %d rows', [ARows]);
    b := TablesDocument(ARows, 4 * MB);
    full := LoadWith(b, True);
    d := LoadWith(b, False);
    tables := TFPList.Create;
    try
      load := TyRichRtfLoadOf(d);
      AssertTrue(msg + ': intervals', load.IntervalCount >= 40);
      // a block, and the row or the paragraph that ends it
      limit := Int64(CRtfGroupIntervals + 1) * CRtfSnapshotBytes;
      // (a paragraph inside a block, not at its start)
      mid := d.Text.ParaCount * 5 div 8;
      d.EnsureParsed(mid);
      AssertEquals(msg + ': one parse', 1, load.ParseCount);
      AssertTrue(Format('%s: reading one paragraph parsed %d bytes', [msg, load.ParsedBytes]),
        load.ParsedBytes <= limit);
      AssertTrue(Format('%s: %d intervals parsed for it', [msg, load.ResidentIntervals]),
        load.ResidentIntervals <= CRtfGroupIntervals);
      if AChain then
      begin
        // the block is the same whichever of its paragraphs is asked for: its first and
        // its last are there
        k := 0;
        while (k + 1 < load.IntervalCount) and (load.IntervalFirstPara(k + 1) <= mid) do Inc(k);
        lo := k - k mod CRtfGroupIntervals;
        hi := lo + CRtfGroupIntervals;
        AssertTrue(Format('%s: interval %d is inside its block', [msg, k]), (k > lo) and (k < hi - 1));
        d.EnsureParsed(load.IntervalFirstPara(lo));
        if hi < load.IntervalCount then d.EnsureParsed(load.IntervalFirstPara(hi) - 1)
        else d.EnsureParsed(d.Text.ParaCount - 1);
        AssertEquals(msg + ': the block''s first and last paragraph were parsed with it', 1,
          load.ParseCount);
        AssertTrue(msg + ': the block''s first paragraph is set',
          TBuilderAccess.Value(d, load.IntervalFirstPara(lo)) <> nil);
      end;
      // its neighbours in the block are there; the next block is one more parse of a block
      before := load.ParsedBytes;
      d.EnsureParsed(mid + 1);
      d.EnsureParsed(mid - 1);
      AssertTrue(msg + ': the paragraphs beside it', load.ParseCount <= 2);
      d.EnsureParsed(d.Text.ParaCount - 1);
      d.EnsureParsed(0);
      AssertTrue(Format('%s: two more reads parsed %d bytes', [msg, load.ParsedBytes - before]),
        load.ParsedBytes - before <= 2 * limit);
      // everything read: the text and the cells of the full parse, every row in one table
      // or one part, and what is cut is locked
      load.MaxResidentIntervals := MaxInt;
      locked := 0;
      rows := 0;
      fullRows := 0;
      for i := 0 to full.Text.ParaCount - 1 do
      begin
        AssertText(Format('%s paragraph %d', [msg, i]), ParaText(full, i), ParaText(d, i));
        AssertEquals(Format('%s paragraph %d in a table', [msg, i]), full.CellAt(i) <> nil,
          d.CellAt(i) <> nil);
        if full.CellAt(i) = nil then Continue;
        AssertEquals(Format('%s paragraph %d cell', [msg, i]), full.CellAt(i).Index, d.CellAt(i).Index);
        if (full.CellAt(i).Index = 0) then Inc(fullRows);
        t := d.CellAt(i).Table;
        if tables.IndexOf(t) >= 0 then Continue;
        tables.Add(t);
        Inc(rows, t.RowCount);
        if t.RowCount <> ARows then
        begin
          AssertTrue(Format('%s paragraph %d: a part of a table cannot grow', [msg, i]),
            t.StructureLocked);
          Inc(locked);
        end
        else
          AssertFalse(Format('%s paragraph %d: a whole table is not locked', [msg, i]),
            t.StructureLocked);
      end;
      AssertEquals(msg + ': every row in one table or part', fullRows, rows);
      if AChain then AssertTrue(Format('%s: %d parts', [msg, locked]), locked >= 2);
      // at most the one table at each block's end is cut, in two
      AssertTrue(Format('%s: %d parts for %d intervals', [msg, locked, load.IntervalCount]),
        locked <= 2 * (load.IntervalCount div CRtfGroupIntervals + 1));
      AssertEquals(msg + ': integrity', '', d.Text.CheckIntegrity);
    finally
      tables.Free;
      d.Free;
      full.Free;
    end;
  end;

begin
  // 2 KB tables (now and then a snapshot falls between two of them), and tables longer
  // than an interval (one chain from the first to the last)
  Check(20, False);
  Check(1000, True);
end;

{ A table still open where the scan stands is as long as the scan has come: once that is
  more than a big table, reading one of its paragraphs parses that paragraph's interval,
  not the table from its start. }
procedure TTyRtfLazyTest.TestReadingInsideATableWhileItLoads;
var
  bb: TByteBuilder;
  b: TBytes;
  s: TBytesStream;
  d, full: TTyRichDocument;
  load: TTyRtfLoad;
  before: Int64;
  i, n: Integer;
begin
  bb := Default(TByteBuilder);
  bb.Add(PlainHead);
  bb.Add('first\par' + #13#10);
  AddRows(bb, 30000);
  bb.Add('\pard the end\par' + #13#10 + '}');
  b := bb.Done;
  AssertTrue('a table of 3 MB', Length(b) > 3 * MB);
  full := LoadWith(b, True);
  d := TTyRichDocument.Create;
  s := TBytesStream.Create(b);
  try
    // (the table is not yet as long as a big one when the first read comes)
    load := TyRichBeginLoadRtf(d, s, MB);
    AssertTrue('still loading', d.Loading);
    AssertTrue('less than a big table is indexed', load.BytesIndexed <= CRtfBigTableBytes + 4096);
    // near the start, and near the end of what is indexed
    d.EnsureParsed(5);
    AssertTrue(Format('reading paragraph 5 parsed %d bytes', [load.ParsedBytes]),
      load.ParsedBytes <= 2 * CRtfSnapshotBytes);
    before := load.ParsedBytes;
    n := d.Text.ParaCount;
    d.EnsureParsed(n - 5);
    AssertTrue(Format('reading near the indexed end parsed %d bytes', [load.ParsedBytes - before]),
      load.ParsedBytes - before <= 2 * CRtfSnapshotBytes);
    AssertTrue('a part of the table', d.CellAt(n - 5).Table.StructureLocked);
    AssertTrue(Format('%d intervals parsed', [load.ResidentIntervals]), load.ResidentIntervals <= 2);
    load.Step(MB);
    before := load.ParsedBytes;
    n := d.Text.ParaCount;
    d.EnsureParsed(n - 5);
    AssertTrue(Format('after a slice: reading near the indexed end parsed %d bytes',
      [load.ParsedBytes - before]), load.ParsedBytes - before <= 2 * CRtfSnapshotBytes);
    while not load.Step(64 * MB) do ;
    before := load.ParsedBytes;
    d.EnsureParsed(d.Text.ParaCount div 2);
    AssertTrue(Format('after the load: reading a middle paragraph parsed %d bytes',
      [load.ParsedBytes - before]), load.ParsedBytes - before <= 2 * CRtfSnapshotBytes);
    AssertTrue(Format('%d intervals stay parsed', [load.ResidentIntervals]),
      load.ResidentIntervals <= 5);
    // and what was read while it loaded is what the whole file says
    load.MaxResidentIntervals := MaxInt;
    AssertEquals('paragraphs', full.Text.ParaCount, d.Text.ParaCount);
    for i := 0 to full.Text.ParaCount - 1 do
    begin
      if (i mod 97 <> 0) and (i > 20) and (i < full.Text.ParaCount - 20) then Continue;
      AssertText(Format('paragraph %d', [i]), ParaText(full, i), ParaText(d, i));
      AssertEquals(Format('paragraph %d in a table', [i]), full.CellAt(i) <> nil, d.CellAt(i) <> nil);
      if full.CellAt(i) <> nil then
        AssertEquals(Format('paragraph %d cell', [i]), full.CellAt(i).Index, d.CellAt(i).Index);
    end;
    AssertEquals('integrity', '', d.Text.CheckIntegrity);
  finally
    d.Free;
    s.Free;
    full.Free;
  end;
end;

{ An interval parsed while it was the last one indexed answers for its own paragraphs, not
  for everything after it: a paragraph of a later interval that is parsed is found there. }
procedure TTyRtfLazyTest.TestAGroupParsedWhileLoadingAnswersForItsIntervalOnly;
var
  bb: TByteBuilder;
  b: TBytes;
  s: TBytesStream;
  d: TTyRichDocument;
  load: TTyRtfLoad;
  i, p0, k0, last, parses: Integer;
  v: Pointer;
  r: TTyRtfRange;
begin
  bb := Default(TByteBuilder);
  bb.Add(PlainHead);
  i := 0;
  while bb.Len < 2 * MB do
  begin
    bb.Add('Paragraph ' + IntToStr(i) + ' with some text \''d6\''d0 in it.\par' + #13#10);
    Inc(i);
  end;
  bb.Add('}');
  b := bb.Done;
  d := TTyRichDocument.Create;
  s := TBytesStream.Create(b);
  try
    load := TyRichBeginLoadRtf(d, s, 300 * 1024);
    // the last paragraph there is, read while the file loads
    p0 := d.Text.ParaCount - 1;
    d.EnsureParsed(p0);
    ParaText(d, p0);
    while not load.Step(64 * MB) do ;
    k0 := 0;
    while (k0 + 1 < load.IntervalCount) and (load.IntervalFirstPara(k0 + 1) <= p0) do Inc(k0);
    AssertTrue('p0 is not in the last interval', k0 < load.IntervalCount - 2);
    // the document's last paragraph: its interval is parsed
    last := d.Text.ParaCount - 1;
    d.EnsureParsed(last);
    ParaText(d, last);
    v := TBuilderAccess.Value(d, last);
    AssertTrue('the last paragraph is parsed', v <> nil);
    // a paragraph of the interval parsed while loading (its group is the latest used now)
    ParaText(d, load.IntervalFirstPara(k0));
    parses := load.ParseCount;
    // another paragraph of the last interval: parsed already
    ParaText(d, last - 1);
    d.EnsureParsed(last - 1);
    AssertEquals('no parse for a paragraph of a parsed interval', parses, load.ParseCount);
    AssertTrue('the last paragraph kept its value', TBuilderAccess.Value(d, last) = v);
    AssertTrue('and is the file''s own', load.ParaSource(last, r));
    AssertTrue(Format('%d intervals parsed', [load.ResidentIntervals]), load.ResidentIntervals <= 3);
  finally
    d.Free;
    s.Free;
  end;
end;

{ A read that parses may send the least recently used intervals back to unparsed, and their
  tables and cells go with them - but not inside a read scope: what was read there stays
  until the scope ends. TableParas holds a table while it reads the table's neighbours, so
  it is one. }
procedure TTyRtfLazyTest.TestAReadScopeKeepsWhatWasRead;
var
  b: TBytes;
  d: TTyRichDocument;
  load: TTyRtfLoad;
  firstCell, a, z, parses: Integer;
  t: TTyRichTable;
  c: TTyRichCell;
  raised: Boolean;
begin
  // the table starts right after the first snapshot (taken at the first \par that ends at
  // or after 64 KB; a paragraph of the padding ends with \par CR LF): its first paragraph
  // begins interval 1
  b := TableDocument(CRtfSnapshotBytes + 2, 30);
  d := LoadWith(b, False);
  try
    load := TyRichRtfLoadOf(d);
    load.MaxResidentIntervals := 1;
    AssertTrue('intervals', load.IntervalCount >= 2);
    firstCell := load.IntervalFirstPara(1);
    d.BeginRead;
    try
      t := d.TableAt(firstCell);
      AssertTrue('the table begins the second interval', t <> nil);
      AssertTrue('the paragraph before it is outside', d.TableAt(firstCell - 1) = nil);
      // two intervals are parsed now, one more than may stay: nothing went
      AssertEquals('both intervals parsed', 2, load.ParseCount);
      AssertEquals('both stay inside the scope', 2, load.ResidentIntervals);
      AssertTrue('the table is still the paragraph''s', d.TableAt(firstCell) = t);
      AssertEquals('its rows', 30, t.RowCount);
      AssertEquals('no parse to see it again', 2, load.ParseCount);
      // scopes nest
      d.BeginRead;
      d.EndRead;
      AssertEquals('an inner scope ends nothing', 2, load.ResidentIntervals);
    finally
      d.EndRead;
    end;
    AssertEquals('the scope ended: one interval stays', 1, load.ResidentIntervals);
    raised := False;
    try
      d.EndRead;
    except
      on ETyRichModel do raised := True;
    end;
    AssertTrue('EndRead without BeginRead raises', raised);
    // TableParas reads the paragraph before the table (the other interval) in the middle
    // of its walk: each interval is parsed once for it, and the table is found whole
    d.EnsureParsed(firstCell + 4);
    parses := load.ParseCount;
    AssertTrue('in a table', d.TableParas(firstCell + 4, a, z));
    AssertEquals('the table''s first paragraph', firstCell, a);
    AssertEquals('the table''s last paragraph', firstCell + 89, z);
    AssertTrue(Format('TableParas parsed %d times', [load.ParseCount - parses]),
      load.ParseCount - parses <= 1);
    AssertEquals('one interval stays after it', 1, load.ResidentIntervals);
    // CellParas the same, from the last row to a cell of the first
    d.BeginRead;
    try
      c := d.CellAt(firstCell + 1);
      parses := load.ParseCount;
      AssertTrue('the cell is found', d.CellParas(firstCell + 88, c, a, z));
      AssertEquals('the cell''s paragraph', firstCell + 1, a);
      AssertEquals('one paragraph', firstCell + 1, z);
      AssertEquals('no parse inside the table', parses, load.ParseCount);
    finally
      d.EndRead;
    end;
    AssertEquals('integrity', '', d.Text.CheckIntegrity);
  finally
    d.Free;
  end;
end;

{ "Least recently used" means used: reading a paragraph that is parsed already counts. }
procedure TTyRtfLazyTest.TestTheLeastRecentlyUsedIntervalGoes;
var
  b: TBytes;
  d: TTyRichDocument;
  load: TTyRtfLoad;
  p1, p3, p5, p7, p9, q: Integer;
begin
  b := Generate('re-zh-mixed.rtf', MB);
  d := LoadWith(b, False);
  try
    load := TyRichRtfLoadOf(d);
    load.MaxResidentIntervals := 2;
    AssertTrue('intervals', load.IntervalCount >= 11);
    p1 := load.IntervalFirstPara(1) + 1;
    p3 := load.IntervalFirstPara(3) + 1;
    p5 := load.IntervalFirstPara(5) + 1;
    p7 := load.IntervalFirstPara(7) + 1;
    p9 := load.IntervalFirstPara(9) + 1;
    d.EnsureParsed(p1);
    d.EnsureParsed(p3);
    AssertEquals('two parses', 2, load.ParseCount);
    // the first one again: parsed already, and now the one used last
    d.ParaFormatOf(p1);
    AssertEquals('no parse', 2, load.ParseCount);
    d.EnsureParsed(p5);
    AssertEquals('two intervals stay', 2, load.ResidentIntervals);
    AssertTrue('the interval read last before it stays', TBuilderAccess.Value(d, p1) <> nil);
    AssertTrue('the one not read since went', TBuilderAccess.Value(d, p3) = nil);
    AssertTrue('the new one is there', TBuilderAccess.Value(d, p5) <> nil);
    // a run of reads in one interval, another interval parsed between two of them
    d.RunsOf(p1);
    d.EnsureParsed(p7);
    AssertTrue('the interval of the run stays', TBuilderAccess.Value(d, p1) <> nil);
    AssertTrue('the other went', TBuilderAccess.Value(d, p5) = nil);
    d.RunsOf(p1 + 1);
    d.EnsureParsed(p9);
    AssertTrue('the run goes on: its interval stays again', TBuilderAccess.Value(d, p1) <> nil);
    AssertTrue('the one parsed between went', TBuilderAccess.Value(d, p7) = nil);
    AssertEquals('five parses in all', 5, load.ParseCount);
    AssertEquals('integrity', '', d.Text.CheckIntegrity);
  finally
    d.Free;
  end;
  // an edit moves the paragraphs: a read after it still finds the interval it reads
  d := LoadWith(b, False);
  try
    load := TyRichRtfLoadOf(d);
    load.MaxResidentIntervals := 2;
    p1 := load.IntervalFirstPara(1) + 1;
    p3 := load.IntervalFirstPara(3) + 1;
    d.EnsureParsed(p1);
    // the first two paragraphs go (the first interval is parsed for it, and its paragraphs
    // are the ones read last: the command read them). What was the second interval's second
    // paragraph is now two places up - where the first interval's paragraphs were
    AssertTrue('deleted', d.Execute(TTyRichDelete.Create(0, d.Text.ParaStart(2))));
    AssertEquals('two intervals parsed', 2, load.ResidentIntervals);
    q := p1 - 2;
    AssertTrue('the second interval''s paragraph is there', TBuilderAccess.Value(d, q) <> nil);
    AssertTrue('a paragraph of the first interval is there', TBuilderAccess.Value(d, 5) <> nil);
    d.ParaFormatOf(q);
    d.EnsureParsed(p3 - 2);
    AssertEquals('two stay', 2, load.ResidentIntervals);
    AssertTrue('after the edit: the interval read last stays', TBuilderAccess.Value(d, q) <> nil);
    AssertTrue('after the edit: the first interval went', TBuilderAccess.Value(d, 5) = nil);
    AssertEquals('integrity', '', d.Text.CheckIntegrity);
  finally
    d.Free;
  end;
end;

{ One cell of a table edited: the table's other paragraphs stay as the load set them, also
  when their interval is sent back to unparsed (the table is one object for all of them, so
  they stay set). They are still the file's own then - a save copies their bytes - however
  far the reader went before saving. }
procedure TTyRtfLazyTest.TestUntouchedCellsStayTheFilesOwnAfterTheirIntervalGoes;
var
  bb: TByteBuilder;
  b, o: TBytes;
  d: TTyRichDocument;
  load: TTyRtfLoad;
  s: TBytesStream;
  i, k, cA, cB, otherA, otherB, round, paras: Integer;
  tableA, secondRowA, tableB, secondRowB, tail, mid, at: Int64;
  r: TTyRtfRange;
  vA, vB: Pointer;
  msg: string;
  bold: TTyCharFormat;

  function Find(const AHay: TBytes; AFrom: Int64; const ANeedle: TBytes; ANeedleAt, ACount: Int64): Int64;
  var
    p: Int64;
  begin
    for p := AFrom to Int64(Length(AHay)) - ACount do
      if (AHay[p] = ANeedle[ANeedleAt]) and CompareMem(@AHay[p], @ANeedle[ANeedleAt], ACount) then
        Exit(p);
    Result := -1;
  end;

begin
  // 30 paragraphs, a table of 10 rows, paragraphs up to 1.5 MB, a table of 5 rows,
  // paragraphs up to 3 MB
  bold := TyDefaultCharFormat;
  bold.Style := [fsBold];
  bb := Default(TByteBuilder);
  bb.Add(PlainHead);
  for i := 0 to 29 do bb.Add('Paragraph ' + IntToStr(i) + ' before the table.\par' + #13#10);
  cA := 30;
  tableA := bb.Len;
  AddRows(bb, 1);
  secondRowA := bb.Len;
  AddRows(bb, 9);
  bb.Add('\pard ');
  paras := cA + 30;
  while bb.Len < 3 * MB div 2 do
  begin
    bb.Add('Paragraph ' + IntToStr(paras) + ' between the tables, with some text \''d6\''d0 in it.\par' + #13#10);
    Inc(paras);
  end;
  cB := paras;
  tableB := bb.Len;
  AddRows(bb, 1);
  secondRowB := bb.Len;
  AddRows(bb, 4);
  bb.Add('\pard ');
  i := 0;
  while bb.Len < 3 * MB do
  begin
    bb.Add('Paragraph ' + IntToStr(i) + ' after the tables, with some text \''d6\''d0 in it.\par' + #13#10);
    Inc(i);
  end;
  bb.Add('}');
  b := bb.Done;
  d := LoadWith(b, False);
  s := TBytesStream.Create;
  try
    load := TyRichRtfLoadOf(d);
    load.MaxResidentIntervals := 1;
    AssertTrue('the first table''s first cell', (d.CellAt(cA) <> nil) and (d.CellAt(cA - 1) = nil));
    AssertTrue('the second table''s first cell', (d.CellAt(cB) <> nil) and (d.CellAt(cB - 1) = nil));
    otherA := cA + 7;   // a cell of the third row
    otherB := cB + 4;   // a cell of the second row
    AssertTrue('before the edit: the file''s own', load.ParaSource(otherA, r));
    // a cell of the second table first, then one of the first: the second table's interval
    // goes first, and the first table's records come before its own
    AssertTrue('typed into the second table', d.Execute(TTyRichInsertText.Create(d.Text.ParaStart(cB), 'Y')));
    AssertTrue('typed into the first table', d.Execute(TTyRichInsertText.Create(d.Text.ParaStart(cA), 'X')));
    AssertFalse('an edited cell is not the file''s own', load.ParaSource(cA, r));
    AssertTrue('after the edit: the file''s own', load.ParaSource(otherA, r));
    vA := TBuilderAccess.Value(d, otherA);
    vB := TBuilderAccess.Value(d, otherB);
    AssertTrue('parsed', (vA <> nil) and (vB <> nil));
    for round := 1 to 2 do
    begin
      msg := Format('round %d: ', [round]);
      // every interval but the tables' read: theirs go back to unparsed
      for k := 1 to load.IntervalCount - 1 do
      begin
        if k + 1 < load.IntervalCount then paras := load.IntervalFirstPara(k + 1)
        else paras := d.Text.ParaCount;
        if (load.IntervalFirstPara(k) > cB + 15) or (paras <= cB) then
          d.EnsureParsed(load.IntervalFirstPara(k) + 1);
      end;
      AssertEquals(msg + 'one interval stays parsed', 1, load.ResidentIntervals);
      AssertTrue(msg + 'a paragraph beside the first table went back to unparsed',
        TBuilderAccess.Value(d, 3) = nil);
      AssertTrue(msg + 'a paragraph beside the second table went back to unparsed',
        TBuilderAccess.Value(d, cB - 2) = nil);
      AssertTrue(msg + 'the tables'' cells stay as they were set',
        (TBuilderAccess.Value(d, otherA) = vA) and (TBuilderAccess.Value(d, otherB) = vB));
      for i := cA + 1 to cA + 29 do
        AssertTrue(Format('%sparagraph %d of the first table is still the file''s own', [msg, i]),
          load.ParaSource(i, r));
      for i := cB + 1 to cB + 14 do
        AssertTrue(Format('%sparagraph %d of the second table is still the file''s own', [msg, i]),
          load.ParaSource(i, r));
      AssertFalse(msg + 'the edited cells are not', load.ParaSource(cA, r) or load.ParaSource(cB, r));
      // the first table's interval read again: its paragraphs are the load's as before
      d.EnsureParsed(3);
      AssertTrue(msg + 'parsed again, the cell keeps its value', TBuilderAccess.Value(d, otherA) = vA);
      AssertTrue(msg + 'parsed again, still the file''s own', load.ParaSource(otherA, r));
      AssertTrue(msg + 'the second table too', load.ParaSource(otherB, r));
    end;
    d.EnsureParsed(d.Text.ParaCount - 1);
    // saved: everything but the two edited rows is the file's bytes
    TyRichSaveRtf(d, s);
    o := Copy(s.Bytes, 0, s.Size);
    AssertTrue('the file up to the first table', (Length(o) > tableA) and
      CompareMem(@o[0], @b[0], tableA));
    tail := Length(b) - secondRowB;
    AssertTrue('the output holds the rest', Length(o) > tableA + tail);
    AssertTrue('from the second table''s second row on: the file''s bytes',
      CompareMem(@o[Length(o) - tail], @b[secondRowB], tail));
    // between them: from the first table's second row to the second table
    mid := tableB - secondRowA;
    at := Find(o, tableA, b, secondRowA, 200);
    AssertTrue('the first table''s second row is in the output', at >= tableA);
    AssertTrue('from there to the second table: the file''s bytes',
      (at + mid <= Length(o)) and CompareMem(@o[at], @b[secondRowA], mid));
    AssertTrue(Format('the first edited row is all that was rewritten there (%d bytes for %d)',
      [at - tableA, secondRowA - tableA]), at - tableA < 4 * (secondRowA - tableA) + 400);
    AssertTrue(Format('and the second (%d bytes for %d)',
      [Length(o) - tail - (at + mid), secondRowB - tableB]),
      Length(o) - tail - (at + mid) < 4 * (secondRowB - tableB) + 400);
    // a format changed in a cell whose interval is not parsed: it has another value than
    // the one recorded, and is no longer the file's own
    d.EnsureParsed(d.Text.ParaCount - 1);
    load.Trim;
    AssertTrue('the second table''s interval is not parsed',
      (load.ResidentIntervals = 1) and (TBuilderAccess.Value(d, cB - 2) = nil));
    AssertTrue('before the change', load.ParaSource(otherB, r));
    AssertTrue('made bold', d.Execute(TTyRichSetCharFormat.Create(
      TyRichRange(d.Text.ParaStart(otherB), d.Text.ParaLength(otherB)), [cffBold], bold)));
    AssertFalse('a changed cell is not the file''s own', load.ParaSource(otherB, r));
    AssertTrue('its neighbour is', load.ParaSource(otherB + 1, r));
    AssertEquals('integrity', '', d.Text.CheckIntegrity);
  finally
    s.Free;
    d.Free;
  end;
end;

{ An interval parsed while the file was still loading holds the paragraphs indexed by then.
  When a later paragraph of it is read, it is parsed again - and inside a read scope (or a
  command) the paragraphs set before must stay as they are: they keep their values and are
  still the file's own. }
procedure TTyRtfLazyTest.TestAnIntervalParsedAgainInsideAScopeKeepsItsParagraphs;
var
  bb: TByteBuilder;
  b: TBytes;
  s: TBytesStream;
  d: TTyRichDocument;
  load: TTyRtfLoad;
  i, p0, k0, parses: Integer;
  v: Pointer;
  r: TTyRtfRange;
begin
  bb := Default(TByteBuilder);
  bb.Add(PlainHead);
  i := 0;
  while bb.Len < MB do
  begin
    bb.Add('Paragraph ' + IntToStr(i) + ' with some text \''d6\''d0 in it.\par' + #13#10);
    Inc(i);
  end;
  bb.Add('}');
  b := bb.Done;
  d := TTyRichDocument.Create;
  s := TBytesStream.Create(b);
  try
    load := TyRichBeginLoadRtf(d, s, 300 * 1024);
    p0 := d.Text.ParaCount - 1;
    d.EnsureParsed(p0);
    v := TBuilderAccess.Value(d, p0);
    AssertTrue('parsed while loading', v <> nil);
    while not load.Step(64 * MB) do ;
    k0 := 0;
    while (k0 + 1 < load.IntervalCount) and (load.IntervalFirstPara(k0 + 1) <= p0) do Inc(k0);
    AssertTrue('the interval got more paragraphs after that',
      load.IntervalFirstPara(k0 + 1) > p0 + 5);
    AssertTrue('one of them is not parsed', TBuilderAccess.Value(d, p0 + 5) = nil);
    parses := load.ParseCount;
    d.BeginRead;
    try
      d.EnsureParsed(p0 + 5);
      AssertEquals('the interval is parsed again', parses + 1, load.ParseCount);
      AssertTrue('the later paragraph is set', TBuilderAccess.Value(d, p0 + 5) <> nil);
      AssertTrue('the paragraph set before keeps its value', TBuilderAccess.Value(d, p0) = v);
      AssertTrue('and is the file''s own', load.ParaSource(p0, r));
      AssertTrue('as the paragraph before it is', load.ParaSource(p0 - 1, r));
    finally
      d.EndRead;
    end;
    AssertTrue('after the scope too', load.ParaSource(p0, r));
    AssertEquals('integrity', '', d.Text.CheckIntegrity);
  finally
    d.Free;
    s.Free;
  end;
end;

{ Word's table with a table in one cell: the row that holds it cannot be typed into, and
  "select all, make it bold" changes everything but that row - so the row is saved as the
  file has it, nested table and all, whatever is done around it. }
procedure TTyRtfLazyTest.TestARowWithANestedTableIsSavedAsItWas;

  function Count(const AHay: TBytes; const ANeedle: RawByteString): Integer;
  var
    i: Integer;
  begin
    Result := 0;
    for i := 0 to Length(AHay) - Length(ANeedle) do
      if (AHay[i] = Byte(ANeedle[1])) and CompareMem(@AHay[i], @ANeedle[1], Length(ANeedle)) then
        Inc(Result);
  end;

  function Save(ADoc: TTyRichDocument): TBytes;
  var
    s: TBytesStream;
  begin
    s := TBytesStream.Create;
    try
      TyRichSaveRtf(ADoc, s);
      Result := Copy(s.Bytes, 0, s.Size);
    finally
      s.Free;
    end;
  end;

  procedure Check(const AName: string; AFirst: Integer);
  var
    b, o: TBytes;
    d, r: TTyRichDocument;
    load: TTyRtfLoad;
    i, j, at: Integer;
    range, last: TTyRtfRange;
    bold: TTyCharFormat;
    runs: TTyRunArray;
    found: Boolean;
  begin
    b := Fixture(AName);
    d := LoadWith(b, False);
    r := nil;
    try
      load := TyRichRtfLoadOf(d);
      AssertTrue(AName + ': the row is marked', d.CellAt(AFirst).Row.HoldsNestedTable);
      // typing into G, deleting a character of the nested cell, the row's last paragraph
      AssertFalse(AName + ': no typing in the row',
        d.Execute(TTyRichInsertText.Create(d.Text.ParaStart(AFirst + 1), 'X')));
      AssertFalse(AName + ': no deleting in the row',
        d.Execute(TTyRichDelete.Create(d.Text.ParaStart(AFirst + 2), 1)));
      AssertFalse(AName + ': the row does not lose its last paragraph',
        d.Execute(TTyRichDelete.Create(d.Text.ParaStart(AFirst + 4) - 1, 1)));
      AssertFalse(AName + ': no object in the row', d.Execute(TTyRichInsertObject.Create(
        d.Text.ParaStart(AFirst + 1), TTyRichOpaque.Create('{\*\x}'))));
      AssertFalse(AName + ': nothing changed', d.Modified);
      AssertFalse(AName + ': nothing to undo', d.CanUndo);
      o := Save(d);
      AssertTrue(AName + ': saved as it was', (Length(o) = Length(b)) and
        CompareMem(@o[0], @b[0], Length(b)));
      // select all, bold
      bold := TyDefaultCharFormat;
      bold.Style := [fsBold];
      AssertTrue(AName + ': bold over everything', d.Execute(TTyRichSetCharFormat.Create(
        TyRichRange(0, d.Text.Length), [cffBold], bold)));
      for i := AFirst to AFirst + 4 do
        AssertTrue(Format('%s: paragraph %d of the row is still the file''s own', [AName, i]),
          load.ParaSource(i, range));
      AssertFalse(AName + ': the paragraph before the table was changed', load.ParaSource(0, range));
      AssertFalse(AName + ': a cell of another row was changed', load.ParaSource(AFirst - 1, range));
      AssertTrue(AName + ': the row''s first paragraph', load.ParaSource(AFirst, range));
      AssertTrue(AName + ': the row''s last paragraph', load.ParaSource(AFirst + 4, last));
      o := Save(d);
      // the row's bytes are in the output as they are in the file
      found := False;
      for at := 0 to Length(o) - (last.Stop - range.Start) do
        if (o[at] = b[range.Start]) and CompareMem(@o[at], @b[range.Start], last.Stop - range.Start) then
        begin
          found := True;
          Break;
        end;
      AssertTrue(AName + ': the row is in the output byte for byte', found);
      AssertEquals(AName + ': the inner cells', Count(b, '\nestcell'), Count(o, '\nestcell'));
      AssertEquals(AName + ': the inner table''s properties', Count(b, 'nesttableprops'),
        Count(o, 'nesttableprops'));
      AssertTrue(AName + ': the sample has them', (Count(b, '\nestcell') = 2) and
        (Count(b, 'nesttableprops') = 1));
      // read again: the same paragraphs, bold all but the row's
      r := LoadWith(o, True);
      AssertEquals(AName + ': paragraphs', d.Text.ParaCount, r.Text.ParaCount);
      for i := 0 to r.Text.ParaCount - 1 do
      begin
        AssertText(Format('%s: paragraph %d', [AName, i]), ParaText(d, i), ParaText(r, i));
        runs := r.RunsOf(i);
        for j := 0 to High(runs) do
          AssertEquals(Format('%s: paragraph %d run %d bold', [AName, i, j]),
            (i < AFirst) or (i > AFirst + 4),
            fsBold in r.Formats.CharFormat(runs[j].Format).Style);
        AssertEquals(Format('%s: paragraph %d marked', [AName, i]),
          (i >= AFirst) and (i <= AFirst + 4),
          (r.CellAt(i) <> nil) and r.CellAt(i).Row.HoldsNestedTable);
      end;
      // undone: the file again
      d.Undo;
      o := Save(d);
      AssertTrue(AName + ': undone, saved as it was', (Length(o) = Length(b)) and
        CompareMem(@o[0], @b[0], Length(b)));
    finally
      r.Free;
      d.Free;
    end;
  end;

begin
  Check('hand-word-table-merged.rtf', 7);
  Check('word-table-merged.rtf', 6);
end;

{ TyRichLoadRtfFull is what the other tests compare parsing on demand with: it must not be
  that same path under another name. The whole file is read by one parse from its first
  byte - no snapshot is resumed, no table is cut where intervals meet - and what it set
  stays, whatever the limit of parsed intervals. The document still has its load (a writer
  copies its paragraphs as the file's own bytes). }
procedure TTyRtfLazyTest.TestTheFullLoadIsOneParseThatStays;
var
  b, o: TBytes;
  full, lazy: TTyRichDocument;
  load: TTyRtfLoad;
  i, n, first, last: Integer;
  t: TTyRichTable;
  s: TBytesStream;
  range: TTyRtfRange;
  m: TTyRtfSourceMap;
begin
  // a table of 1.5 MB (parsed on demand it is cut into parts) between plain paragraphs
  b := TableDocument(400, 12000);
  m := TTyRtfSourceMap.Create;
  full := LoadWith(b, True, m);
  lazy := LoadWith(b, False);
  try
    load := TyRichRtfLoadOf(full);
    AssertTrue('the document has its load', load <> nil);
    AssertTrue('which says it was parsed as a whole', load.Whole);
    AssertFalse('a document parsed on demand does not', TyRichRtfLoadOf(lazy).Whole);
    AssertTrue('the file has many intervals', load.IntervalCount > 20);
    AssertEquals('one parse', 1, load.ParseCount);
    AssertTrue(Format('of the whole file: %d bytes', [load.ParsedBytes]),
      (load.ParsedBytes >= load.Trailer.Start) and (load.ParsedBytes <= Length(b)));
    AssertEquals('every interval is parsed', load.IntervalCount, load.ResidentIntervals);
    AssertEquals('nothing was parsed in the other document', 0, TyRichRtfLoadOf(lazy).ParseCount);
    AssertFalse('loading is no change', full.Modified);
    AssertFalse('it can be changed', full.Loading);
    n := full.Text.ParaCount;
    AssertEquals('as many paragraphs', lazy.Text.ParaCount, n);
    // every paragraph has its formats before anybody reads it; parsed on demand none has
    for i := 0 to n - 1 do
    begin
      if TBuilderAccess.Value(full, i) = nil then Fail(Format('paragraph %d is set by the load', [i]));
      if TBuilderAccess.Value(lazy, i) <> nil then Fail(Format('paragraph %d is not set on demand yet', [i]));
    end;
    // the map is the index's
    AssertEquals('the map has every paragraph', n, m.ParaCount);
    AssertEquals('the map''s header', load.Header.Stop, m.Header.Stop);
    AssertEquals('the map''s trailer', load.Trailer.Start, m.Trailer.Start);
    // the table is one table: not cut, not locked
    first := -1;
    for i := 0 to n - 1 do
      if full.TableAt(i) <> nil then
      begin
        first := i;
        Break;
      end;
    AssertTrue('there is a table', first >= 0);
    t := full.TableAt(first);
    AssertTrue('its paragraphs', full.TableParas(first, i, last));
    AssertEquals('it starts where it was found', first, i);
    AssertEquals('all its rows are one table''s', 12000, t.RowCount);
    AssertFalse('which is whole', t.StructureLocked);
    AssertTrue('parsed on demand it is a part', lazy.TableAt(first).StructureLocked);
    // reading everything parses nothing more, and nothing goes when the limit is one
    load.MaxResidentIntervals := 1;
    for i := 0 to n - 1 do
    begin
      full.EnsureParsed(i);
      if i mod 997 = 0 then ParaText(full, i);
    end;
    load.Trim;
    AssertEquals('still one parse', 1, load.ParseCount);
    AssertEquals('still every interval', load.IntervalCount, load.ResidentIntervals);
    AssertTrue('the table is the object it was', full.TableAt(first) = t);
    AssertTrue('and its last paragraph has it too', full.TableAt(last) = t);
    // every paragraph is the file's own: saved, it is the file
    for i := 0 to n - 1 do
      if not load.ParaSource(i, range) then Fail(Format('paragraph %d is the file''s own', [i]));
    s := TBytesStream.Create;
    try
      TyRichSaveRtf(full, s);
      o := Copy(s.Bytes, 0, s.Size);
    finally
      s.Free;
    end;
    AssertEquals('saved: as long as the file', Length(b), Length(o));
    AssertTrue('saved: the file', CompareMem(@b[0], @o[0], Length(b)));
    // an edit, and undoing it: nothing is parsed for either
    AssertTrue('typed', full.Execute(TTyRichInsertText.Create(full.Text.ParaStart(first), 'X')));
    AssertFalse('the edited paragraph is no longer the file''s', load.ParaSource(first, range));
    AssertTrue('its neighbour is', load.ParaSource(first + 1, range));
    AssertEquals('an edit parses nothing', 1, load.ParseCount);
  finally
    lazy.Free;
    full.Free;
    m.Free;
  end;
end;

{ Paragraphs that are deleted take their values out of the text; an undo brings both back.
  When their interval is sent back to unparsed in between, they must still be the file's
  own afterwards: a writer copies them as their bytes. For a row that holds a nested table
  - which may be deleted whole, and cannot be written from the model - that decides
  whether the document can be saved at all. And what the load keeps for it is let go of
  when no undo can bring the paragraphs back any more. }
procedure TTyRtfLazyTest.TestDeletedParagraphsUndoneAfterTheirIntervalWentAreStillTheFilesOwn;

  function Save(ADoc: TTyRichDocument): TBytes;
  var
    s: TBytesStream;
  begin
    s := TBytesStream.Create;
    try
      TyRichSaveRtf(ADoc, s);
      Result := Copy(s.Bytes, 0, s.Size);
    finally
      s.Free;
    end;
  end;

var
  b, o: TBytes;
  d: TCountingDoc;
  s: TBytesStream;
  load: TTyRtfLoad;
  i, n, first, last, plain, live0, parses: Integer;
  row: TTyRichRow;
  range: TTyRtfRange;
  values: array of Pointer;
  fmt: TTyParaFormat;
  text: RawByteString;
begin
  // the sample with a nested table, its body repeated: many intervals
  b := Generate('hand-word-table-merged.rtf', 1536 * 1024);
  d := TCountingDoc.Create;
  s := TBytesStream.Create(b);
  try
    TyRichLoadRtf(d, s);
    load := TyRichRtfLoadOf(d);
    load.MaxResidentIntervals := 1;
    AssertTrue('many intervals', load.IntervalCount > 10);
    n := d.Text.ParaCount;
    // the first row that holds a nested table, and a paragraph in no table further down
    first := -1;
    for i := 0 to 100 do
      if (d.CellAt(i) <> nil) and d.CellAt(i).Row.HoldsNestedTable then
      begin
        first := i;
        Break;
      end;
    AssertTrue('there is such a row', first >= 0);
    d.BeginRead;
    try
      row := d.CellAt(first).Row;
      last := first;
      while (d.CellAt(last + 1) <> nil) and (d.CellAt(last + 1).Row = row) do Inc(last);
    finally
      d.EndRead;
    end;
    AssertTrue('the row has several paragraphs', last > first);
    plain := -1;
    for i := load.IntervalFirstPara(3) + 1 to load.IntervalFirstPara(4) - 2 do
      if d.CellAt(i) = nil then
      begin
        plain := i;
        Break;
      end;
    AssertTrue('there is a paragraph in no table in the fourth interval', plain >= 0);
    // delete that paragraph, then the whole row (two undo steps)
    AssertTrue('the plain paragraph deleted', d.Execute(TTyRichDelete.Create(d.Text.ParaStart(plain),
      d.Text.ParaStart(plain + 1) - d.Text.ParaStart(plain))));
    d.BreakMerge;
    // (the row is parsed when it goes: its paragraphs have the values the load gave them)
    d.EnsureParsed(first);
    SetLength(values, last - first + 1);
    for i := first to last do
    begin
      values[i - first] := TBuilderAccess.Value(d, i);
      AssertTrue(Format('paragraph %d of the row is parsed', [i]), values[i - first] <> nil);
    end;
    AssertTrue('the whole row deleted', d.Execute(TTyRichDelete.Create(d.Text.ParaStart(first),
      d.Text.ParaStart(last + 1) - d.Text.ParaStart(first))));
    AssertEquals('paragraphs left', n - 1 - (last - first + 1), d.Text.ParaCount);
    // reading far away: the intervals of both go
    d.EnsureParsed(d.Text.ParaCount - 1);
    d.EnsureParsed(d.Text.ParaCount div 2);
    AssertTrue('their intervals went', load.ResidentIntervals <= 2);
    d.Undo;
    d.Undo;
    AssertEquals('undone: every paragraph is back', n, d.Text.ParaCount);
    for i := first to last do
    begin
      AssertTrue(Format('undone: paragraph %d of the row has the value it had', [i]),
        TBuilderAccess.Value(d, i) = values[i - first]);
      AssertTrue(Format('undone: paragraph %d of the row is the file''s own', [i]),
        load.ParaSource(i, range));
    end;
    AssertTrue('undone: the plain paragraph is the file''s own', load.ParaSource(plain, range));
    // so the file is saved as it was (the row could not be written from the model)
    o := Save(d);
    AssertEquals('saved: as long as the file', Length(b), Length(o));
    AssertTrue('saved: the file', CompareMem(@b[0], @o[0], Length(b)));
    // their interval parsed again (a paragraph of it that went back to unparsed is read):
    // they are that interval's own as before
    parses := load.ParseCount;
    d.EnsureParsed(0);
    AssertTrue('the interval is parsed again', load.ParseCount > parses);
    AssertTrue('parsed again: still the value', TBuilderAccess.Value(d, first) = values[0]);
    AssertTrue('parsed again: still the file''s own', load.ParaSource(first, range));
    // deleted for good - no undo step left that could bring the row back - the values go
    // when their interval is next parsed
    AssertTrue('the whole row deleted again', d.Execute(TTyRichDelete.Create(d.Text.ParaStart(first),
      d.Text.ParaStart(last + 1) - d.Text.ParaStart(first))));
    d.EnsureParsed(d.Text.ParaCount - 1);
    d.EnsureParsed(d.Text.ParaCount div 2);
    d.BreakMerge;
    AssertTrue('typed elsewhere', d.Execute(TTyRichInsertText.Create(d.Text.Length, 'X')));
    d.MaxUndoBytes := 1;
    AssertEquals('one undo step is left', 1, d.UndoDepth);
    d.EnsureParsed(d.Text.ParaCount - 1);
    d.EnsureParsed(d.Text.ParaCount div 2);
    live0 := d.Live;
    d.EnsureParsed(0);
    d.EnsureParsed(d.Text.ParaCount - 1);
    d.EnsureParsed(d.Text.ParaCount div 2);
    // (the row's paragraphs, and the value of the paragraph after the row, which the undo
    // step of the delete held as well)
    AssertEquals('the deleted row''s values are let go of, and the one after it',
      live0 - (last - first + 2), d.Live);
  finally
    s.Free;
    d.Free;
  end;
  // a paragraph that was given another format, its interval gone, parsed again and gone
  // again: undone, it is the file's own
  d := TCountingDoc.Create;
  s := TBytesStream.Create(b);
  try
    TyRichLoadRtf(d, s);
    load := TyRichRtfLoadOf(d);
    load.MaxResidentIntervals := 1;
    n := d.Text.ParaCount;
    fmt := TyDefaultParaFormat;
    fmt.SpaceBefore := 77;
    AssertTrue('a format', d.Execute(TTyRichSetParaFormat.Create(plain, plain, [pffSpaceBefore], fmt)));
    AssertFalse('changed: not the file''s own', load.ParaSource(plain, range));
    d.EnsureParsed(n - 1);
    d.EnsureParsed(plain + 1);
    d.EnsureParsed(n - 1);
    AssertFalse('changed, its interval parsed again and gone: still not the file''s own',
      load.ParaSource(plain, range));
    d.Undo;
    AssertTrue('undone: the file''s own again', load.ParaSource(plain, range));
    o := Save(d);
    AssertTrue('undone: saved as the file', (Length(o) = Length(b)) and CompareMem(@b[0], @o[0], Length(b)));
  finally
    s.Free;
    d.Free;
  end;
  // plain paragraphs all share one value, which says nothing about any one of them: no
  // record is ever kept of it, however many of them come and go
  text := '{\rtf1 ';
  for i := 1 to 60000 do text := text + 'a\par ';
  text := text + '}';
  d := TCountingDoc.Create;
  s := TBytesStream.Create(BytesOf(text));
  try
    TyRichLoadRtf(d, s);
    load := TyRichRtfLoadOf(d);
    load.MaxResidentIntervals := 1;
    AssertTrue('several intervals', load.IntervalCount > 4);
    AssertTrue('a paragraph deleted', d.Execute(TTyRichDelete.Create(d.Text.ParaStart(5),
      d.Text.ParaStart(6) - d.Text.ParaStart(5))));
    for i := 0 to load.IntervalCount - 1 do d.EnsureParsed(load.IntervalFirstPara(i) + 1);
    for i := load.IntervalCount - 1 downto 0 do d.EnsureParsed(load.IntervalFirstPara(i) + 1);
    AssertEquals('no record of a plain paragraph', 0, load.KeptValues);
  finally
    s.Free;
    d.Free;
  end;
end;

{ One step of the walk: the value the walk hands out for an unparsed paragraph is what the
  whole parse gives it - its format, runs, cell and marker text - read from the value alone. }
procedure TTyRtfLazyTest.WalkValue(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
  var AContinue: Boolean);
var
  fmt: TTyParaFormatId;
  runs, rf: TTyRunArray;
  cell, cf: TTyRichCell;
  msg: string;
  j: Integer;
  src, n: Int64;
begin
  Inc(FWalked);
  msg := Format('%s paragraph %d', [FWalkMsg, AIndex]);
  if not FWalkLazy.ReadValue(AData, fmt, runs, cell) then
  begin
    // no value only where there are no bytes to parse: an empty last paragraph
    AssertFalse(msg + ': no value, but bytes of its own',
      FWalkLazy.Text.ParaLazySource(AIndex, src, n));
    AssertEquals(msg + ': no value, so empty', 0, ALen);
    AssertTrue(msg + ': no value, so in no table', FWalkFull.CellAt(AIndex) = nil);
    Exit;
  end;
  AssertTrue(msg + ' paragraph format', FWalkLazy.Formats.ParaFormat(fmt).Equals(
    FWalkFull.Formats.ParaFormat(FWalkFull.ParaFormatOf(AIndex))));
  rf := FWalkFull.RunsOf(AIndex);
  AssertEquals(msg + ' runs', Length(rf), Length(runs));
  for j := 0 to High(rf) do
  begin
    AssertEquals(Format('%s run %d start', [msg, j]), rf[j].Start, runs[j].Start);
    AssertTrue(Format('%s run %d format', [msg, j]), FWalkLazy.Formats.CharFormat(
      runs[j].Format).Equals(FWalkFull.Formats.CharFormat(rf[j].Format)));
    AssertTrue(Format('%s run %d object', [msg, j]), SameObject(runs[j].Obj, rf[j].Obj));
  end;
  cf := FWalkFull.CellAt(AIndex);
  AssertEquals(msg + ' in a table', cf <> nil, cell <> nil);
  if cf <> nil then
  begin
    AssertEquals(msg + ' cell', cf.Index, cell.Index);
    AssertEquals(msg + ' row', cf.Row.Index, cell.Row.Index);
    AssertEquals(msg + ' row''s cells', cf.Row.CellCount, cell.Row.CellCount);
    AssertEquals(msg + ' row holds a nested table', cf.Row.HoldsNestedTable,
      cell.Row.HoldsNestedTable);
    AssertText(msg + ' row format', cf.Row.RawFormat, cell.Row.RawFormat);
    AssertEquals(msg + ' rows', cf.Table.RowCount, cell.Table.RowCount);
  end;
  AssertText(msg + ' marker', FWalkFull.ListTextOf(AIndex), FWalkLazy.ValueListText(AData));
end;

{ A walk over every paragraph of a lazily read document that asks for values: every value is
  the whole parse's, and afterwards no paragraph is parsed, no value is left alive, and no
  interval was parsed twice. }
procedure TTyRtfLazyTest.CheckWalkValues(const AMsg: string; const ABytes: TBytes);
var
  full: TTyRichDocument;
  lazy: TCountingDoc;
  s: TBytesStream;
  load: TTyRtfLoad;
  i, live0: Integer;
begin
  full := LoadWith(ABytes, True);
  lazy := TCountingDoc.Create;
  s := TBytesStream.Create(ABytes);
  try
    TyRichLoadRtf(lazy, s);
    load := TyRichRtfLoadOf(lazy);
    AssertEquals(AMsg + ': paragraphs', full.Text.ParaCount, lazy.Text.ParaCount);
    live0 := lazy.Live;
    FWalkLazy := lazy;
    FWalkFull := full;
    FWalkMsg := AMsg;
    FWalked := 0;
    lazy.BeginRead;
    try
      lazy.Text.WalkParaTexts(0, lazy.Text.ParaCount - 1, @WalkValue, True);
    finally
      lazy.EndRead;
    end;
    AssertEquals(AMsg + ': every paragraph walked', lazy.Text.ParaCount, FWalked);
    AssertEquals(AMsg + ': no value left alive', live0, lazy.Live);
    for i := 0 to lazy.Text.ParaCount - 1 do
      if TBuilderAccess.Value(lazy, i) <> nil then
        Fail(Format('%s: paragraph %d was parsed', [AMsg, i]));
    AssertTrue(Format('%s: an interval parsed at most once (%d parses, %d intervals)',
      [AMsg, load.ParseCount, load.IntervalCount]), load.ParseCount <= load.IntervalCount);
  finally
    FWalkLazy := nil;
    FWalkFull := nil;
    s.Free;
    lazy.Free;
    full.Free;
  end;
end;

{ WalkParaTexts with AValues hands each unparsed paragraph of a lazily read RTF the value
  the parse that decoded it gives - for every sample, tables (some across a snapshot boundary,
  in WordPad's writing too) and a file with more intervals than the load lets pile up, so that
  intervals go during the walk - and leaves nothing parsed. }
procedure TTyRtfLazyTest.TestAWalkWithValuesGivesTheParseAndSetsNothing;
var
  sr: TSearchRec;
  files: Integer;
begin
  files := 0;
  if FindFirst(FixtureDir + '*.rtf', faAnyFile, sr) = 0 then
  try
    repeat
      Inc(files);
      CheckWalkValues(sr.Name, Fixture(sr.Name));
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
  AssertTrue('samples', files >= 12);
  CheckWalkValues('re-zh-table x 1 MB', Generate('re-zh-table.rtf', MB));
  CheckWalkValues('wp-zh-table x 1 MB', Generate('wp-zh-table.rtf', MB));
  CheckWalkValues('re-zh-mixed x 3 MB', Generate('re-zh-mixed.rtf', 3 * MB));
end;

{ the first slice ends inside a row, so the text ends with the row's first cell and
  its other cells are not appended yet. That cell is read (its interval is parsed: the row's
  other cells are records the text does not hold), the load goes on, and then a paragraph
  after the row in the same interval is read, which parses the interval again. The row's
  cells must still be cells of one row of one table - the first cell must not keep the table
  of the parse that saw it alone. Once outside a read scope, once inside one (where nothing
  read may be let go of until the scope ends), and once with the row's interval sent back to
  unparsed (trimmed) before the row's other cells come. }
procedure TTyRtfLazyTest.TestARowReadWhileItLoadsStaysOneRow;
var
  b: TBytes;
  s: TBytesStream;
  d, full: TTyRichDocument;
  load: TTyRtfLoad;
  at, last, pass, i: Integer;
  msg: string;
  r: TTyRtfRange;
begin
  full := nil;
  try
    for pass := 0 to 2 do
    begin
      case pass of
        0: msg := 'outside a scope';
        1: msg := 'inside a read scope';
      else
        msg := 'trimmed before the row is whole';
      end;
      // pass 2: the table begins the second interval
      if pass < 2 then b := TableDocument(0, 20)
      else b := TableDocument(CRtfSnapshotBytes + 2, 20);
      // inside row 10, after its second cell's end and before its third's
      at := Pos('\cell r10 \''d6', StrOf(b, 0, Length(b)));
      AssertTrue('row 10 is there', at > 0);
      at := at - 1 + Length('\cell r1');
      FreeAndNil(full);
      full := LoadWith(b, True);
      d := TTyRichDocument.Create;
      s := TBytesStream.Create(b);
      try
        load := TyRichBeginLoadRtf(d, s, at);
        AssertTrue(msg + ': still loading', d.Loading);
        if pass < 2 then AssertEquals(msg + ': one interval', 1, load.IntervalCount)
        else AssertEquals(msg + ': two intervals', 2, load.IntervalCount);
        last := d.Text.ParaCount - 1;
        // the text ends with the row's first cell
        AssertText(msg + ': the last paragraph', 'r10 a', ParaText(d, last));
        AssertTrue(msg + ': it is a cell', d.CellAt(last) <> nil);
        AssertEquals(msg + ': the row''s first', 0, d.CellAt(last).Index);
        if pass = 2 then
        begin
          // a read of the first interval sends the row's back to unparsed
          load.MaxResidentIntervals := 1;
          d.EnsureParsed(0);
          AssertEquals(msg + ': one interval stays', 1, load.ResidentIntervals);
        end;
        if pass = 1 then d.BeginRead;
        try
          while not load.Step(64 * MB) do ;
          // a paragraph after the row, in the same interval: parsed again
          AssertText(msg + ': the paragraph after the table', 'after the table',
            ParaText(d, d.Text.ParaCount - 1));
          d.EnsureParsed(d.Text.ParaCount - 1);
          for i := last to last + 2 do
          begin
            AssertTrue(Format('%s: paragraph %d is a cell', [msg, i]), d.CellAt(i) <> nil);
            AssertEquals(Format('%s: paragraph %d cell', [msg, i]), i - last, d.CellAt(i).Index);
          end;
          AssertTrue(msg + ': cells 0 and 1 in one row', d.CellAt(last).Row = d.CellAt(last + 1).Row);
          AssertTrue(msg + ': cells 1 and 2 in one row', d.CellAt(last + 1).Row = d.CellAt(last + 2).Row);
          AssertTrue(msg + ': the row before in the same table',
            d.CellAt(last - 1).Table = d.CellAt(last).Table);
          // (inside a scope what was read stays as it was returned: the rows read before
          // the parse keep the table part they had, so only outside one is it the whole)
          if pass <> 1 then
            AssertEquals(msg + ': the table''s rows', full.CellAt(last).Table.RowCount,
              d.CellAt(last).Table.RowCount);
        finally
          if pass = 1 then d.EndRead;
        end;
        // after the scope, too, and every paragraph as the whole parse has it
        AssertTrue(msg + ': after: one row', (d.CellAt(last).Row = d.CellAt(last + 1).Row) and
          (d.CellAt(last + 1).Row = d.CellAt(last + 2).Row));
        AssertEquals(msg + ': paragraphs', full.Text.ParaCount, d.Text.ParaCount);
        for i := 0 to full.Text.ParaCount - 1 do
        begin
          AssertEquals(Format('%s: paragraph %d in a table', [msg, i]), full.CellAt(i) <> nil,
            d.CellAt(i) <> nil);
          if full.CellAt(i) = nil then Continue;
          AssertEquals(Format('%s: paragraph %d cell', [msg, i]), full.CellAt(i).Index,
            d.CellAt(i).Index);
          AssertEquals(Format('%s: paragraph %d row', [msg, i]), full.CellAt(i).Row.Index,
            d.CellAt(i).Row.Index);
        end;
        AssertTrue(msg + ': the row''s first cell is the file''s own', load.ParaSource(last, r));
        AssertEquals(msg + ': integrity', '', d.Text.CheckIntegrity);
      finally
        d.Free;
        s.Free;
      end;
    end;
  finally
    full.Free;
  end;
end;

function SaveOf(ADoc: TTyRichDocument): TBytes;
var
  s: TBytesStream;
begin
  s := TBytesStream.Create;
  try
    TyRichSaveRtf(ADoc, s);
    Result := Copy(s.Bytes, 0, s.Size);
  finally
    s.Free;
  end;
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

{ "Typed by mistake, Ctrl+Z, save" gives the file back: an undo that returns a paragraph to
  what it was returns it to its file's bytes - a character typed (at the paragraph's start, in
  it, at its end), Enter, one character deleted, a merged run of typing, and an undo after a
  redo - in a hand-written, a WordPad, a RichEdit and a Word file. The paragraph's lazy piece
  the edit decoded and split is put back by the undo (the deletion's way), so the writer copies
  it again. (The engine keeps no saved point: Modified stays True after the undo.) }
procedure TTyRtfLazyTest.TestAnEditUndoneInsideAParagraphGivesTheFileBack;

  procedure Check(const AName: string);
  var
    b: TBytes;
    d: TTyRichDocument;
    t: TTyRichText;
    paras: array of Integer;
    k, i, n, pc: Integer;
    ps, len: TTyRichPos;
    what: string;

    procedure Back(const AOp: string);
    begin
      d.Undo;
      AssertEquals(Format('%s: %s: the text is whole', [what, AOp]), '', t.CheckIntegrity);
      AssertTrue(Format('%s: %s undone: saved as the file', [what, AOp]), SameBytes(SaveOf(d), b));
    end;

  begin
    b := Fixture(AName);
    d := LoadWith(b, False);
    try
      t := d.Text;
      AssertTrue(AName + ': saved untouched as the file', SameBytes(SaveOf(d), b));
      // paragraphs with some text that may be edited: the first three and the last
      paras := nil;
      n := 0;
      for k := 0 to t.ParaCount - 1 do
        if (t.ParaLength(k) >= 3) and d.CanChange(t.ParaStart(k), 0) and
          d.CanChange(t.ParaStart(k) + 1, 1) then
        begin
          if n < 3 then
          begin
            SetLength(paras, n + 1);
            paras[n] := k;
            Inc(n);
          end
          else
            paras[n - 1] := k;
        end;
      AssertTrue(AName + ': paragraphs to edit', n >= 2);
      for i := 0 to n - 1 do
      begin
        k := paras[i];
        what := Format('%s paragraph %d', [AName, k]);
        ps := t.ParaStart(k);
        len := t.ParaLength(k);
        pc := t.ParaCount;
        AssertTrue(what + ': typed in it', d.Execute(TTyRichInsertText.Create(ps + 1, 'x')));
        Back('a character typed in it');
        AssertTrue(what + ': typed at its start', d.Execute(TTyRichInsertText.Create(ps, 'x')));
        Back('a character typed at its start');
        AssertTrue(what + ': typed at its end', d.Execute(TTyRichInsertText.Create(ps + len, 'x')));
        Back('a character typed at its end');
        AssertTrue(what + ': Enter', d.Execute(TTyRichInsertText.Create(ps + 1, #10,
          TyRichInheritFormat, False)));
        AssertEquals(what + ': Enter made a paragraph', pc + 1, t.ParaCount);
        Back('Enter');
        AssertTrue(what + ': one deleted', d.Execute(TTyRichDelete.Create(ps + 1, 1)));
        Back('a character deleted');
        AssertTrue(what + ': a run', d.Execute(TTyRichInsertText.Create(ps + 1, 'a')));
        AssertTrue(what + ': a run', d.Execute(TTyRichInsertText.Create(ps + 2, 'b')));
        AssertTrue(what + ': a run', d.Execute(TTyRichInsertText.Create(ps + 3, 'c')));
        AssertEquals(what + ': one step', 1, d.UndoDepth);
        Back('a merged run of typing');
        AssertTrue(what + ': typed again', d.Execute(TTyRichInsertText.Create(ps + 1, 'x')));
        d.Undo;
        d.Redo;
        AssertEquals(what + ': redone', 'x', string(t.GetText(ps + 1, 1)));
        Back('an undo after a redo');
      end;
      // the empty last paragraph the load appended (it has no piece: the text remembers it)
      if t.ParaLength(t.ParaCount - 1) = 0 then
      begin
        what := AName + ' the last paragraph';
        AssertTrue(what + ': typed in it', d.Execute(TTyRichInsertText.Create(t.Length, 'x')));
        Back('a character typed in the empty last paragraph');
      end;
    finally
      d.Free;
    end;
  end;

begin
  Check('hand-word-list.rtf');
  Check('wp-zh-plain.rtf');
  Check('re-zh-plain.rtf');
  Check('word-list.rtf');
end;

{ What the undo of an insert keeps of the storage is what the insert replaced - the lazy
  piece, a reference - not the paragraph's text: a character typed in a paragraph of 100,000
  costs the step a few hundred bytes, and its undo gives the file back. }
procedure TTyRtfLazyTest.TestAnUndoneInsertKeepsTheEditNotTheParagraph;
var
  b: TBytes;
  d: TTyRichDocument;
  s: RawByteString;
  bytes: Int64;
begin
  s := '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}' + #13#10 + '\pard\f0 ' +
    StringOfChar('a', 100000) + '\par' + #13#10 + '\pard tail\par' + #13#10 + '}';
  b := BytesOf(s);
  d := LoadWith(b, False);
  try
    AssertEquals('the long paragraph', Int64(100000), d.Text.ParaLength(0));
    AssertTrue('typed', d.Execute(TTyRichInsertText.Create(50000, 'x')));
    bytes := d.UndoStep.MemSize;
    AssertTrue(Format('the step keeps %d bytes', [bytes]), bytes < 1024);
    d.Undo;
    AssertTrue('undone: saved as the file', SameBytes(SaveOf(d), b));
  finally
    d.Free;
  end;
end;

{ an undo gives a paragraph its lazy piece back, and the next edit of
  it - a redo, or the same character typed again - takes the copy of its text the add buffer
  already holds, not a new one: a thousand cycles of each in a paragraph of 100,000 characters
  cost what the edits cost (a few bytes each; the copy alone is 100,003), and the file comes
  back when all is undone. }
procedure TTyRtfLazyTest.TestUndoAndRedoCopyAParagraphOnce;
const
  Cycles = 1000;
  PerCycle = 16;   // bytes a cycle may add: the typed character and slack
var
  b: TBytes;
  d: TTyRichDocument;
  s: RawByteString;
  a0, a1, a2, a3: Int64;
  i: Integer;
begin
  s := '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}' + #13#10 + '\pard\f0 ' +
    StringOfChar('a', 100000) + '\par' + #13#10 + '\pard tail\par' + #13#10 + '}';
  b := BytesOf(s);
  d := LoadWith(b, False);
  try
    a0 := d.Text.AddedBytes;
    AssertTrue('typed', d.Execute(TTyRichInsertText.Create(50000, 'x')));
    a1 := d.Text.AddedBytes;
    AssertTrue(Format('the first edit copies the paragraph (%d bytes)', [a1 - a0]),
      a1 - a0 >= 100000);
    d.Undo;
    for i := 1 to Cycles do
    begin
      d.Redo;
      d.Undo;
    end;
    a2 := d.Text.AddedBytes;
    AssertTrue(Format('%d redo / undo cycles add %d bytes', [Cycles, a2 - a1]),
      a2 - a1 <= Cycles * PerCycle);
    for i := 1 to Cycles do
    begin
      d.BreakMerge;
      AssertTrue('typed again', d.Execute(TTyRichInsertText.Create(50000, 'x')));
      d.Undo;
    end;
    a3 := d.Text.AddedBytes;
    AssertTrue(Format('%d type / undo cycles add %d bytes', [Cycles, a3 - a2]),
      a3 - a2 <= Cycles * PerCycle);
    AssertEquals('the text', '', d.Text.CheckIntegrity);
    AssertEquals('the paragraph as it was', Int64(100000), d.Text.ParaLength(0));
    AssertTrue('all undone: saved as the file', SameBytes(SaveOf(d), b));
    // and the copy taken again still reads as the paragraph (a redo, then a read across it)
    d.Redo;
    AssertEquals('redone: the character in', 'aax', d.Text.GetText(49998, 3));
    AssertEquals('redone: the paragraph''s end', 'aa', d.Text.GetText(100000 - 1, 2));
  finally
    d.Free;
  end;
end;

{ random commands - typing that merges, Enter and pastes with breaks, deletions across
  paragraphs and cells, paragraph formats, update blocks, the run broken, reads that churn the
  loader, undo and redo, some runs with a small MaxUndoBytes and ClearUndo - on fixtures with
  and without tables and on a file of plain paragraphs that ends with the empty lazy one
  (a fixed seed). After every undo the text is the one before
  the step, after every redo the one after it, the index is whole after every command, and
  with everything undone (no step dropped) the save is the file. }
procedure TTyRtfLazyTest.TestRandomEditsUndoneAndRedone;
var
  seed: Cardinal;

  function Rnd(AMax: Integer): Integer;
  begin
    // (a linear congruential step: it wraps around by design)
    {$PUSH}{$Q-}{$R-}
    seed := seed * 1103515245 + 12345;
    {$POP}
    if AMax <= 0 then Exit(0);
    Result := Integer((seed shr 8) mod Cardinal(AMax));
  end;

  function AllText(ADoc: TTyRichDocument): RawByteString;
  begin
    Result := ADoc.Text.GetText(0, ADoc.Text.Length);
    SetCodePage(Result, CP_NONE, False);
  end;

  procedure Stress(const AName: string; const B: TBytes; ASeed: Cardinal; AOps: Integer;
    AMaxUndo: Int64);
  var
    d: TTyRichDocument;
    t: TTyRichText;
    undoT, redoT: TStringList;
    i, op, k: Integer;
    pos, len: Int64;
    before, orig: RawByteString;
    ok, dropped: Boolean;
    pf: TTyParaFormat;
    ins: UTF8String;
    top: TTyRichCommand;
    what: string;

    procedure AfterExec(AOk: Boolean);
    begin
      if not AOk then Exit;
      if d.UndoStep <> top then
      begin
        undoT.Add(before);
        redoT.Clear;
      end
      else if AllText(d) <> before then
        // merged into the step before
        redoT.Clear;
    end;

  begin
    seed := ASeed;
    d := LoadWith(B, False);
    undoT := TStringList.Create;
    redoT := TStringList.Create;
    try
      t := d.Text;
      dropped := False;
      if AMaxUndo > 0 then d.MaxUndoBytes := AMaxUndo;
      orig := AllText(d);
      AssertTrue(AName + ': untouched, saved as the file', SameBytes(SaveOf(d), B));
      for i := 1 to AOps do
      begin
        what := Format('%s seed %d op %d', [AName, ASeed, i]);
        op := Rnd(100);
        top := d.UndoStep;
        before := AllText(d);
        try
          if op < 30 then
          begin
            pos := Rnd(t.Length + 1);
            case Rnd(4) of
              0: ins := 'x';
              1: ins := 'yz';
              2: ins := #$E4#$B8#$AD;
            else
              ins := ' ';
            end;
            AfterExec(d.Execute(TTyRichInsertText.Create(pos, ins)));
          end
          else if op < 40 then
          begin
            pos := Rnd(t.Length + 1);
            if Rnd(2) = 0 then ins := #10 else ins := 'p' + #10 + 'q' + #10;
            AfterExec(d.Execute(TTyRichInsertText.Create(pos, ins, TyRichInheritFormat, False)));
          end
          else if op < 60 then
          begin
            if t.Length = 0 then Continue;
            pos := Rnd(t.Length);
            if Rnd(3) = 0 then len := 1 + Rnd(60) else len := 1 + Rnd(3);
            if pos + len > t.Length then len := t.Length - pos;
            AfterExec(d.Execute(TTyRichDelete.Create(pos, len)));
          end
          else if op < 65 then
          begin
            k := Rnd(t.ParaCount);
            pf := TyDefaultParaFormat;
            pf.SpaceBefore := 10 + Rnd(50);
            AfterExec(d.Execute(TTyRichSetParaFormat.Create(k, k, [pffSpaceBefore], pf)));
          end
          else if op < 70 then
          begin
            if t.Length < 4 then Continue;
            pos := Rnd(t.Length - 2);
            d.BeginUpdate('block');
            try
              ok := d.Execute(TTyRichDelete.Create(pos, 1 + Rnd(2)));
              if ok then d.Execute(TTyRichInsertText.Create(pos, 'B', TyRichInheritFormat, False));
            finally
              d.EndUpdate;
            end;
            AfterExec(ok);
          end
          else if op < 73 then
            d.BreakMerge
          else if (op < 74) and (AMaxUndo > 0) and (Rnd(8) = 0) then
          begin
            d.ClearUndo;
            undoT.Clear;
            redoT.Clear;
            dropped := True;
          end
          else if op < 78 then
            d.EnsureParsed(Rnd(t.ParaCount))
          else if op < 92 then
          begin
            if d.UndoDepth = 0 then Continue;
            d.Undo;
            AssertTrue(what + ': after an undo, the text before the step',
              AllText(d) = undoT[undoT.Count - 1]);
            redoT.Add(before);
            undoT.Delete(undoT.Count - 1);
          end
          else
          begin
            if d.RedoDepth = 0 then Continue;
            d.Redo;
            AssertTrue(what + ': after a redo, the text the step left',
              AllText(d) = redoT[redoT.Count - 1]);
            undoT.Add(before);
            redoT.Delete(redoT.Count - 1);
          end;
        except
          // a command the engine refuses (a row that holds a nested table) changes nothing
          on E: ETyRichRefused do ;
        end;
        while (AMaxUndo > 0) and (undoT.Count > d.UndoDepth) do
        begin
          undoT.Delete(0);
          dropped := True;
        end;
        AssertEquals(what + ': the history''s depth', undoT.Count, d.UndoDepth);
        AssertEquals(what + ': the index', '', t.CheckIntegrity);
      end;
      while d.UndoDepth > 0 do d.Undo;
      AssertEquals(AName + ': all undone, the index', '', t.CheckIntegrity);
      if not dropped then
      begin
        AssertTrue(AName + ': all undone, the text', AllText(d) = orig);
        AssertTrue(AName + ': all undone, saved as the file', SameBytes(SaveOf(d), B));
      end;
    finally
      undoT.Free;
      redoT.Free;
      d.Free;
    end;
  end;

const
  Names: array[0..7] of string = ('hand-word-list.rtf', 'wp-zh-plain.rtf', 're-zh-plain.rtf',
    'word-list.rtf', 're-zh-table.rtf', 're-styles.rtf', 'hand-word-table-merged.rtf',
    'word-table-merged.rtf');
var
  i: Integer;
  b: TBytes;
  text: RawByteString;
begin
  for i := 0 to High(Names) do
  begin
    b := Fixture(Names[i]);
    Stress(Names[i], b, 1000 * (i + 1) + 1, 600, 0);
    Stress(Names[i], b, 1000 * (i + 1) + 2, 600, 0);
    Stress(Names[i], b, 1000 * (i + 1) + 3, 600, 0);
    Stress(Names[i], b, 5000 * (i + 1) + 1, 600, 900 + 100 * i);
  end;
  // plain paragraphs, the last the empty lazy one the load appends
  text := '{\rtf1 ';
  for i := 1 to 300 do text := text + 'abc def\par ';
  text := text + '}';
  for i := 1 to 4 do Stress('plain-300', BytesOf(text), 9000 + i, 600, 0);
end;

type
  // the builder's questions a reader asks (protected)
  TBuildAccess = class(TTyRichDocBuilder)
  end;

{ An edit undone gives the file back, in a big file. A plain paragraph (the value all plain parsed
  paragraphs share) typed in, or deleted, whose interval the loader let go before the undo, is
  the file's own again after it: saved byte for byte as the file - at the start, in the middle
  and at the end of a file of several megabytes read with a small residency; saved at once
  (no group knows the paragraph: the file's paragraph is parsed again to tell) and after the
  paragraph is read again (its group takes it as its own). }
procedure TTyRtfLazyTest.TestAPlainParagraphUndoneAfterItsIntervalWentIsTheFilesOwn;
var
  b: TBytes;
  text: TByteBuilder;
  i, p, way, where, n, k, pc: Integer;
  d: TTyRichDocument;
  load: TTyRtfLoad;
  r: TTyRtfRange;
  what: string;
begin
  text := Default(TByteBuilder);
  text.Add('{\rtf1 ');
  for i := 1 to 400000 do text.Add('abc\par ');
  text.Add('}');
  b := text.Done;
  AssertTrue('several megabytes', Length(b) > 3 * 1000 * 1000);
  for where := 0 to 2 do
    for way := 0 to 3 do
    begin
      d := LoadWith(b, False);
      try
        load := TyRichRtfLoadOf(d);
        load.MaxResidentIntervals := 2;
        n := load.IntervalCount;
        AssertTrue('many intervals', n > 8);
        case where of
          0: p := 5;
          1: p := d.Text.ParaCount div 2;
        else
          p := d.Text.ParaCount - 3;
        end;
        what := Format('paragraph %d, %s, %s', [p, BoolToStr(way and 1 = 0, 'typed in',
          'deleted'), BoolToStr(way and 2 = 0, 'saved at once', 'read again')]);
        d.EnsureParsed(p);
        AssertTrue(what + ': the file''s own before', load.ParaSource(p, r));
        if way and 1 = 0 then
          AssertTrue(what + ': typed', d.Execute(TTyRichInsertText.Create(d.Text.ParaStart(p) + 1,
            'x')))
        else
          AssertTrue(what + ': deleted', d.Execute(TTyRichDelete.Create(d.Text.ParaStart(p),
            d.Text.ParaStart(p + 1) - d.Text.ParaStart(p))));
        // elsewhere: intervals far from it read, so that its own goes
        k := 0;
        while (k < n - 1) and (load.IntervalFirstPara(k + 1) <= p) do Inc(k);
        d.EnsureParsed(load.IntervalFirstPara((k + n div 2) mod n) + 1);
        d.EnsureParsed(load.IntervalFirstPara((k + n div 3) mod n) + 1);
        d.EnsureParsed(load.IntervalFirstPara((k + n div 4) mod n) + 1);
        d.Undo;
        if way and 2 <> 0 then
        begin
          { Its interval read again (a paragraph near it, unparsed, is read - a deletion's
            undo gave the paragraph after it a value too -: its group sets what is
            unparsed and takes the paragraph, which has a value already, as its own): when that
            group goes too the paragraph is unparsed again, as any untouched one, and a save
            parses nothing for it. }
          d.EnsureParsed(p + 2);
          d.EnsureParsed(load.IntervalFirstPara((k + n div 2) mod n) + 1);
          d.EnsureParsed(load.IntervalFirstPara((k + n div 3) mod n) + 1);
          d.EnsureParsed(load.IntervalFirstPara((k + n div 4) mod n) + 1);
          pc := load.ParseCount;
          AssertTrue(what + ': saved as the file', SameBytes(SaveOf(d), b));
          AssertEquals(what + ': the save parsed nothing', pc, load.ParseCount);
        end;
        AssertTrue(what + ': the file''s own after the undo', load.ParaSource(p, r));
        AssertTrue(what + ': saved as the file', SameBytes(SaveOf(d), b));
      finally
        d.Free;
      end;
    end;
  { And the other way: a centred paragraph of the file made plain by a command has that same
    shared value, with its text the file's - it is not the file's own (the file makes it
    centred), after its interval went too: saved as it is now. }
  text := Default(TByteBuilder);
  text.Add('{\rtf1 ');
  for i := 1 to 200000 do
    if i = 100000 then text.Add('\qc xyz\par\pard ') else text.Add('abc\par ');
  text.Add('}');
  b := text.Done;
  d := LoadWith(b, False);
  try
    load := TyRichRtfLoadOf(d);
    load.MaxResidentIntervals := 2;
    n := load.IntervalCount;
    p := 99999;
    d.EnsureParsed(p);
    AssertEquals('the centred paragraph', 'xyz', d.Text.GetText(d.Text.ParaStart(p), 3));
    AssertTrue('made plain', d.Execute(TTyRichSetParaFormat.Create(p, p, [pffAlign],
      TyDefaultParaFormat)));
    AssertTrue('its value is the shared plain one',
      TBuildAccess.IsPlainValue(d, TBuildAccess.ParagraphValue(d, p)));
    k := 0;
    while (k < n - 1) and (load.IntervalFirstPara(k + 1) <= p) do Inc(k);
    d.EnsureParsed(load.IntervalFirstPara((k + n div 2) mod n) + 1);
    d.EnsureParsed(load.IntervalFirstPara((k + n div 3) mod n) + 1);
    AssertFalse('not the file''s own', load.ParaSource(p, r));
    AssertFalse('saved as it is now, not as the file', SameBytes(SaveOf(d), b));
    d.EnsureParsed(p);
    AssertFalse('read again: still not the file''s own', load.ParaSource(p, r));
  finally
    d.Free;
  end;
end;

{ The values the loader records as the file's own when their group goes (undo records still
  hold them) are kept in a table where a record costs a few moves and looks, whatever the
  order they come in: edits walked from a large file's end gave each record the front of a
  sorted list (a replace walked from the end of a 100 MB RTF took 56 s). Both directions. }
procedure TTyRtfLazyTest.TestKeptValuesCostLittleInAnyOrder;
var
  text: string;
  sb: TStringBuilder;
  d: TCountingDoc;
  s: TBytesStream;
  load: TTyRtfLoad;
  i, k, dir, n: Integer;
  most: Integer;
begin
  sb := TStringBuilder.Create;
  try
    sb.Append('{' + #92 + 'rtf1 ');
    for i := 1 to 40000 do
    begin
      sb.Append('{' + #92 + 'b w}');
      sb.Append(IntToStr(i));
      sb.Append(#92 + 'par ');
    end;
    sb.Append('}');
    text := sb.ToString;
  finally
    sb.Free;
  end;
  for dir := 0 to 1 do
  begin
    d := TCountingDoc.Create;
    s := TBytesStream.Create(BytesOf(text));
    try
      TyRichLoadRtf(d, s);
      load := TyRichRtfLoadOf(d);
      load.MaxResidentIntervals := 1;
      AssertTrue('several intervals', load.IntervalCount > 4);
      n := d.Text.ParaCount;
      most := 0;
      for i := 0 to (n - 2) div 4 do
      begin
        if dir = 0 then k := 4 * i else k := n - 2 - 4 * i;
        AssertTrue(d.Execute(TTyRichInsertText.Create(d.Text.ParaStart(k), 'x')));
        load.Trim;
        if load.KeptValues > most then most := load.KeptValues;
      end;
      AssertTrue(Format('%d: many records (%d)', [dir, most]), most > 1000);
      AssertTrue(Format('%d: a few moves and looks a use (%d for %d uses, %d records at most)',
        [dir, load.KeptWork, load.KeptOps, most]), load.KeptWork <= 4 * load.KeptOps);
    finally
      s.Free;
      d.Free;
    end;
  end;
end;

{ The default font named again in the body (\deffN after text): what has no font of its own
  is in the new font from there on - its bytes too - and the index scan and a parse that
  begins anywhere take the change at the same place: nothing raises, the index is the whole
  parse's, and the lazy read is the whole read paragraph by paragraph in any order. (The
  decoder is kept by the font's number, and the number of "no font" stays what it was: the
  parse went on with the old default font's code page where the scan had looked the new
  one up, a paragraph decoded to another count of characters than the index had for it,
  and reading the file raised - also in a field's result, with the file cut short there.)
  The files are D1 to D4 of tests/fixtures/rtf/find; the last names the default font in
  the header alone, and reads as it always did. }
procedure TTyRtfLazyTest.TestTheDefaultFontNamedAgainInTheBody;
const
  CBullet = #$E2#$80#$A2;
  CObject = #$EF#$BF#$BC;
  Names: array[0..3] of string = ('D1.rtf', 'D2.rtf', 'D3.rtf', 'D4.rtf');
  Texts: array[0..3] of RawByteString = (
    // (95 is a bullet in the Greek font, and the first half of a pair in Big5)
    'filler' + #10 + CBullet + 'ab' + #10 + 'zz',
    // (FE is a letter in the Greek font; in GBK the first half of a pair, left waiting)
    'filler' + #10 + 't?' + CObject,
    'filler' + #10 + 't?' + CObject + 'c' + #10 + 'zz',
    'filler' + #10 + CBullet + 'ab' + #10 + 'zz');
var
  i: Integer;
  b: TBytes;
  full: TTyRichDocument;
  s: RawByteString;
begin
  for i := 0 to High(Names) do
  begin
    b := ReadFileBytes(FixtureDir + 'find' + PathDelim + Names[i]);
    full := LoadWith(b, True);
    try
      s := StringReplace(full.Text.GetText(0, full.Text.Length), #13#10, #10, [rfReplaceAll]);
      AssertTrue(Names[i] + ': the text, read whole', s = Texts[i]);
    finally
      full.Free;
    end;
    CheckIndex(Names[i], b);
    CheckLazyAgainstFull(Names[i], b, True);
  end;
end;

initialization
  RegisterTest(TTyRtfLazyTest);
end.
