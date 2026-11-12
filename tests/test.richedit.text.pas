unit test.richedit.text;

{ The text storage under TTyRichEdit: a piece table whose pieces hang in a paragraph index
  tree. Positions are code points, a separator (CR, LF or CRLF) is one character, the
  original buffer is referenced and never copied, and every lookup walks O(log n) tree
  nodes. TTyRichLazyTextTest covers pieces whose text a provider decodes on demand (the
  RTF reader's paragraphs, known at load time only by their byte range in the file). }

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  tyControls.RichEdit.Text;

type
  ETestStop = class(Exception);

  TRefUnits = array of UTF8String;
  TPosArray = array of Int64;
  { The reference for the height index: a paragraph's measured height, -1 unmeasured. }
  THeightRef = array of Int64;

  TTyRichTextTest = class(TTestCase)
  private
    FSeed: Cardinal;
    FChanges: TStringList;
    FDropped: TList;
    FRuns: array of TTyRichByteRun;
    FWalkText: TTyRichText;
    FWalkPieces: TTyRichPieces;
    FWalkTried, FWalkRefused: Integer;
    FWalkRaise: Boolean;
    procedure TryEdits;
    function EditInMap(AIndex: Integer; AData: Pointer): Pointer;
    procedure EditInWalk(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
      var AContinue: Boolean);
    procedure EditInRun(const ARun: TTyRichByteRun; var AContinue: Boolean);
    function NextRandom(AMax: Integer): Integer;
    function RandomText(AMaxUnits: Integer): UTF8String;
    procedure ParasChanged(Sender: TObject; AFirst, AOldCount, ANewCount: Integer);
    procedure DataDropped(Sender: TObject; AData: Pointer);
    procedure CollectRun(const ARun: TTyRichByteRun; var AContinue: Boolean);
    procedure CheckSame(const AWhat: string; AText: TTyRichText; const ARef: TRefUnits;
      AFull: Boolean);
    procedure CheckHeights(const AWhat: string; AText: TTyRichText; const ARef: THeightRef);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestInsertDeleteKeepsTextAndParaIndex;
    procedure TestPositionsAreCodePoints;
    procedure TestCrLfIsOneSeparator;
    procedure TestIndexIsLogarithmic;
    procedure TestOriginalBufferIsNotCopied;
    procedure TestDeletingEverythingStoresPiecesNotText;
    procedure TestSeparatorsAreNotRepaired;
    procedure TestInvalidUtf8BytesAreKeptAsCharacters;
    procedure TestParaDataStaysWithItsParagraph;
    procedure TestSnapshotRestorePutsParaDataBack;
    procedure TestRunsTellOriginalFromEdited;
    procedure TestHeightIndex;
    procedure TestUnmeasuredParagraphsCountAsTheDefault;
    procedure TestHeightIndexAgainstAReference;
    procedure TestSettingHeightsRecomputesNothing;
    procedure TestUnmeasureAllHoldsThroughAMerge;
    procedure TestManyEditsKeepTheTreeConsistent;
    procedure TestDeepTreeStaysConsistent;
    procedure TestSmallInsertsDoNotMakeALeafEach;
    procedure TestTypingNeverJoinsBytesCountedApart;
    procedure TestWalksRefuseAnEditFromTheirCallback;
    procedure TestABigInsertKeepsNoScanBuffer;
    procedure TestControlCharactersAreCharacters;
    procedure TestScannedPiecesMustBePossible;
  end;

  { Decodes paragraph i from a table; the "file offset" of paragraph i is i*1000+7, so the
    calls it records tell exactly which paragraphs were decoded. }
  TFakeRichProvider = class(TTyRichTextProvider)
  public
    Texts: array of UTF8String;
    Calls: TStringList;
    WrongCount: Boolean;
    constructor Create(ACount: Integer);
    destructor Destroy; override;
    function DecodeParagraph(ASrcOffset, ASrcBytes, ACharCount: Int64): UTF8String; override;
    function CallLog: string;
  end;

  TTyRichLazyTextTest = class(TTestCase)
  private
    FProvider: TFakeRichProvider;
    FText: TTyRichText;
    FRuns: array of TTyRichByteRun;
    procedure CollectRun(const ARun: TTyRichByteRun; var AContinue: Boolean);
    procedure BuildLazy(ACount: Integer);
    function ParaText(AIndex: Integer): UTF8String;
  protected
    procedure TearDown; override;
  published
    procedure TestLazyIndexNeedsNoDecoding;
    procedure TestLazyDecodesOnlyWhatIsRead;
    procedure TestLazyDecodesOnlyWhatIsEdited;
    procedure TestLazySnapshotRestoreKeepsPiecesLazy;
    procedure TestLazyRunsKeepSourceRanges;
    procedure TestLazyCountMismatchRaises;
    procedure TestReopenGoesOnOnlyFromAnUntouchedEnd;
    procedure TestLazySourceLookupMissesEditedParagraphs;
    procedure TestIntegritySeesLazyPiecesOutOfOrder;
  end;

implementation

const
  LazyStride = 1000;
  LazyBase = 7;

{ ---- helpers ---- }

function Bytes(const S: UTF8String): TBytes;
begin
  Result := nil;
  SetLength(Result, System.Length(S));
  if S <> '' then
    Move(S[1], Result[0], System.Length(S));
end;

function FromBytes(const B: array of Byte): UTF8String;
begin
  Result := '';
  SetLength(Result, System.Length(B));
  if System.Length(B) > 0 then
    Move(B[0], Result[1], System.Length(B));
end;

function Esc(const S: UTF8String): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to System.Length(S) do
    if (Ord(S[i]) < 32) or (Ord(S[i]) > 126) then
      Result := Result + '#' + IntToStr(Ord(S[i]))
    else
      Result := Result + S[i];
end;

{ On a mismatch the message shows the first differing byte and a little around it: the
  texts can be megabytes long. }
procedure AssertBytesEqual(const AMsg: string; const AExpected, AActual: UTF8String);
var
  i, n: Integer;
begin
  if (System.Length(AExpected) = System.Length(AActual)) and
     ((AExpected = '') or CompareMem(@AExpected[1], @AActual[1], System.Length(AExpected))) then
    Exit;
  n := System.Length(AExpected);
  if System.Length(AActual) < n then n := System.Length(AActual);
  i := 1;
  while (i <= n) and (AExpected[i] = AActual[i]) do Inc(i);
  raise EAssertionFailedError.CreateFmt('%s: lengths %d and %d, first difference at byte %d: ' +
    'expected <%s> but was <%s>', [AMsg, System.Length(AExpected), System.Length(AActual), i,
    Esc(Copy(AExpected, Max(1, i - 20), 60)), Esc(Copy(AActual, Max(1, i - 20), 60))]);
end;

{ The reference model splits text into characters the way the storage does for valid
  UTF-8: CRLF is one unit, a lead byte says how long its sequence is. }
function SplitUnits(const S: UTF8String): TRefUnits;
var
  i, n, len, cnt: Integer;
  b: Byte;
begin
  Result := nil;
  SetLength(Result, System.Length(S));
  cnt := 0;
  i := 1;
  n := System.Length(S);
  while i <= n do
  begin
    b := Ord(S[i]);
    if (b = 13) and (i < n) and (S[i + 1] = #10) then len := 2
    else if b < $C0 then len := 1
    else if b < $E0 then len := 2
    else if b < $F0 then len := 3
    else len := 4;
    Result[cnt] := Copy(S, i, len);
    Inc(cnt);
    Inc(i, len);
  end;
  SetLength(Result, cnt);
end;

function IsSepUnit(const U: UTF8String): Boolean;
begin
  Result := (U = #13) or (U = #10) or (U = #13#10);
end;

function RefText(const R: TRefUnits): UTF8String;
var
  i, total, p: Integer;
begin
  total := 0;
  for i := 0 to High(R) do Inc(total, System.Length(R[i]));
  Result := '';
  SetLength(Result, total);
  p := 1;
  for i := 0 to High(R) do
  begin
    Move(R[i][1], Result[p], System.Length(R[i]));
    Inc(p, System.Length(R[i]));
  end;
end;

procedure RefInsert(var R: TRefUnits; APos: Integer; const AText: UTF8String);
var
  ins: TRefUnits;
  i, n: Integer;
begin
  ins := SplitUnits(AText);
  n := System.Length(R);
  SetLength(R, n + System.Length(ins));
  for i := n - 1 downto APos do
    R[i + System.Length(ins)] := R[i];
  for i := 0 to High(ins) do
    R[APos + i] := ins[i];
end;

procedure RefDelete(var R: TRefUnits; APos, ALen: Integer);
var
  i: Integer;
begin
  for i := APos to System.Length(R) - ALen - 1 do
    R[i] := R[i + ALen];
  SetLength(R, System.Length(R) - ALen);
end;

function RefParaStarts(const R: TRefUnits): TPosArray;
var
  i, cnt: Integer;
begin
  Result := nil;
  SetLength(Result, System.Length(R) + 1);
  Result[0] := 0;
  cnt := 1;
  for i := 0 to High(R) do
    if IsSepUnit(R[i]) then
    begin
      Result[cnt] := i + 1;
      Inc(cnt);
    end;
  SetLength(Result, cnt);
end;

function Utf8Chars(const S: UTF8String): Integer;
begin
  Result := System.Length(SplitUnits(S));
end;

{ A buffer of ACount lines of mixed Chinese and English, each ending with the separator
  ACount mod 3 picks, so the original pieces carry all three kinds. }
procedure AddStr(var ABuf: UTF8String; var ALen: Integer; const S: UTF8String);
begin
  if S = '' then Exit;
  if ALen + System.Length(S) > System.Length(ABuf) then
    SetLength(ABuf, Max(2 * System.Length(ABuf), ALen + System.Length(S) + 1024));
  Move(S[1], ABuf[ALen + 1], System.Length(S));
  Inc(ALen, System.Length(S));
end;

function MixedLines(ACount: Integer; ASeed: Integer): UTF8String;
const
  Words: array[0..7] of UTF8String = ('alpha', '中文', 'β', 'line', '混排', '😀', 'x', ' ');
  Seps: array[0..2] of UTF8String = (#13#10, #10, #13);
var
  i, j, len: Integer;
begin
  Result := '';
  len := 0;
  for i := 0 to ACount - 1 do
  begin
    for j := 0 to (i * 7 + ASeed) mod 6 do
      AddStr(Result, len, Words[(i * 3 + j * 5 + ASeed) mod 8]);
    AddStr(Result, len, Seps[i mod 3]);
  end;
  SetLength(Result, len);
end;

{ ---- the height reference ---- }

function RefH(const R: THeightRef; ADefault: Int64; AIndex: Integer): Int64;
begin
  if R[AIndex] < 0 then Result := ADefault else Result := R[AIndex];
end;

function RefTop(const R: THeightRef; ADefault: Int64; AIndex: Integer): Int64;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to AIndex - 1 do Inc(Result, RefH(R, ADefault, i));
end;

{ The first paragraph whose bottom is below the row, else the last. }
function RefAtHeight(const R: THeightRef; ADefault, AY: Int64): Integer;
var
  i: Integer;
  bottom: Int64;
begin
  bottom := 0;
  for i := 0 to High(R) do
  begin
    Inc(bottom, RefH(R, ADefault, i));
    if bottom > AY then Exit(i);
  end;
  Result := High(R);
end;

function RefMeasured(const R: THeightRef): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(R) do
    if R[i] >= 0 then Inc(Result);
end;

procedure RefRemove(var R: THeightRef; AFirst, ACount: Integer);
var
  i: Integer;
begin
  for i := AFirst to System.Length(R) - ACount - 1 do R[i] := R[i + ACount];
  SetLength(R, System.Length(R) - ACount);
end;

procedure RefInsertUnmeasured(var R: THeightRef; AAt, ACount: Integer);
var
  i, n: Integer;
begin
  n := System.Length(R);
  SetLength(R, n + ACount);
  for i := n - 1 downto AAt do R[i + ACount] := R[i];
  for i := AAt to AAt + ACount - 1 do R[i] := -1;
end;

function LinesOf(ACount: Integer): TBytes;
var
  i: Integer;
begin
  Result := nil;
  SetLength(Result, ACount * 3);
  for i := 0 to ACount - 1 do
  begin
    Result[i * 3] := Ord('a');
    Result[i * 3 + 1] := Ord('b');
    Result[i * 3 + 2] := 10;
  end;
end;

{ ---- TTyRichTextTest ---- }

procedure TTyRichTextTest.SetUp;
begin
  FSeed := 20261111;
  FChanges := TStringList.Create;
  FDropped := TList.Create;
  FRuns := nil;
end;

procedure TTyRichTextTest.TearDown;
begin
  FChanges.Free;
  FDropped.Free;
  FRuns := nil;
end;

function TTyRichTextTest.NextRandom(AMax: Integer): Integer;
begin
  {$PUSH}{$Q-}{$R-}
  FSeed := FSeed * 1103515245 + 12345;
  {$POP}
  Result := Integer((FSeed shr 8) mod Cardinal(AMax));
end;

function TTyRichTextTest.RandomText(AMaxUnits: Integer): UTF8String;
const
  Pool: array[0..10] of UTF8String = ('a', 'b', 'Z', ' ', '中', '文', '😀', 'é', #13, #10, #13#10);
var
  i: Integer;
begin
  Result := '';
  for i := 0 to NextRandom(AMaxUnits) do
    Result := Result + Pool[NextRandom(11)];
end;

procedure TTyRichTextTest.ParasChanged(Sender: TObject; AFirst, AOldCount, ANewCount: Integer);
begin
  FChanges.Add(Format('%d,%d,%d', [AFirst, AOldCount, ANewCount]));
end;

procedure TTyRichTextTest.DataDropped(Sender: TObject; AData: Pointer);
begin
  FDropped.Add(AData);
end;

procedure TTyRichTextTest.CollectRun(const ARun: TTyRichByteRun; var AContinue: Boolean);
begin
  SetLength(FRuns, System.Length(FRuns) + 1);
  FRuns[High(FRuns)] := ARun;
end;

procedure TTyRichTextTest.CheckSame(const AWhat: string; AText: TTyRichText;
  const ARef: TRefUnits; AFull: Boolean);
var
  starts: TPosArray;
  i: Integer;
  len, stop: Int64;
  integrity: string;
begin
  integrity := AText.CheckIntegrity;
  AssertEquals(AWhat + ': tree integrity', '', integrity);
  AssertEquals(AWhat + ': Length', System.Length(ARef), AText.Length);
  AssertBytesEqual(AWhat + ': text', RefText(ARef), AText.GetText(0, AText.Length));
  starts := RefParaStarts(ARef);
  AssertEquals(AWhat + ': ParaCount', System.Length(starts), AText.ParaCount);
  if not AFull then Exit;
  for i := 0 to High(starts) do
  begin
    AssertEquals(Format('%s: ParaStart(%d)', [AWhat, i]), starts[i], AText.ParaStart(i));
    if i < High(starts) then stop := starts[i + 1] - 1 else stop := System.Length(ARef);
    len := stop - starts[i];
    AssertEquals(Format('%s: ParaLength(%d)', [AWhat, i]), len, AText.ParaLength(i));
    AssertEquals(Format('%s: ParaOfPos(start of %d)', [AWhat, i]), i,
      AText.ParaOfPos(starts[i]));
    AssertEquals(Format('%s: ParaOfPos(end of %d)', [AWhat, i]), i,
      AText.ParaOfPos(stop));
  end;
end;

procedure TTyRichTextTest.TestInsertDeleteKeepsTextAndParaIndex;
var
  t: TTyRichText;
  ref: TRefUnits;
  buf: UTF8String;
  op, pos, len, kind: Integer;
  s: UTF8String;
begin
  buf := MixedLines(600, 1);
  ref := SplitUnits(buf);
  t := TTyRichText.CreateFromUtf8(Bytes(buf));
  try
    CheckSame('loaded', t, ref, True);
    for op := 1 to 200 do
    begin
      kind := NextRandom(10);
      if (kind < 6) or (t.Length = 0) then
      begin
        s := RandomText(6);
        case NextRandom(4) of
          0: pos := 0;
          1: pos := t.Length;
          2: pos := t.ParaStart(NextRandom(t.ParaCount));
        else
          pos := NextRandom(t.Length + 1);
        end;
        t.Insert(pos, s);
        RefInsert(ref, pos, s);
      end
      else
      begin
        pos := NextRandom(t.Length);
        if NextRandom(10) = 0 then
          len := 1 + NextRandom(t.Length - pos)
        else
          len := 1 + NextRandom(Min(30, t.Length - pos));
        t.Delete(pos, len);
        RefDelete(ref, pos, len);
      end;
      CheckSame(Format('op %d', [op]), t, ref, True);
    end;
  finally
    t.Free;
  end;
end;

procedure TTyRichTextTest.TestPositionsAreCodePoints;
var
  t: TTyRichText;
begin
  t := TTyRichText.CreateFromUtf8(Bytes('中a😀'));
  try
    AssertEquals('three code points', 3, t.Length);
    AssertEquals('bytes stay bytes', 8, t.ByteCount);
    t.Insert(1, 'b');
    AssertBytesEqual('inserted after the first code point', '中ba😀', t.GetText(0, t.Length));
    AssertBytesEqual('a range of code points', 'a😀', t.GetText(2, 2));
    t.Delete(3, 1);
    AssertBytesEqual('the emoji goes as one', '中ba', t.GetText(0, t.Length));
  finally
    t.Free;
  end;
end;

procedure TTyRichTextTest.TestCrLfIsOneSeparator;
var
  t: TTyRichText;
begin
  t := TTyRichText.CreateFromUtf8(Bytes('a'#13#10'b'#10'c'#13'd'));
  try
    AssertEquals('paragraphs', 4, t.ParaCount);
    AssertEquals('length', 7, t.Length);
    AssertEquals('para 1 starts after CRLF', 2, t.ParaStart(1));
    AssertEquals('para 3 starts after CR', 6, t.ParaStart(3));
    AssertEquals('separator kind 0', Ord(rsCRLF), Ord(t.ParaSeparator(0)));
    AssertEquals('separator kind 1', Ord(rsLF), Ord(t.ParaSeparator(1)));
    AssertEquals('separator kind 2', Ord(rsCR), Ord(t.ParaSeparator(2)));
    AssertEquals('the last paragraph has none', Ord(rsNone), Ord(t.ParaSeparator(3)));
    AssertBytesEqual('the CRLF is one character', 'a'#13#10'b', t.GetText(0, 3));
    t.Delete(1, 1);
    AssertBytesEqual('deleting it removes both bytes', 'ab'#10'c'#13'd', t.GetText(0, t.Length));
    AssertEquals('three paragraphs left', 3, t.ParaCount);
  finally
    t.Free;
  end;
end;

procedure TTyRichTextTest.TestIndexIsLogarithmic;
const
  Lines = 2000000;
var
  t: TTyRichText;
  buf: TBytes;
  i, k, limit, got: Integer;
  v: Int64;
  y: Int64;
begin
  buf := nil;
  SetLength(buf, Lines * 3);
  for i := 0 to Lines - 1 do
  begin
    buf[i * 3] := Ord('a');
    buf[i * 3 + 1] := Ord('b');
    buf[i * 3 + 2] := 10;
  end;
  t := TTyRichText.CreateFromUtf8(buf);
  try
    AssertEquals('paragraphs', Lines + 1, t.ParaCount);
    k := 0;
    while k < t.ParaCount do
    begin
      t.SetParaHeight(k, 16);
      Inc(k, 16);
    end;
    limit := Floor(4 * Log2(t.ParaCount));
    for i := 1 to 1000 do
    begin
      k := NextRandom(t.ParaCount);
      v := t.NodeVisits;
      AssertEquals('ParaStart value', Int64(3) * k, t.ParaStart(k));
      AssertTrue(Format('ParaStart(%d) visited %d nodes, limit %d', [k, t.NodeVisits - v, limit]),
        t.NodeVisits - v <= limit);
      v := t.NodeVisits;
      got := t.ParaOfPos(Min(Int64(3) * k + 1, t.Length));
      AssertTrue(Format('ParaOfPos visited %d nodes, limit %d', [t.NodeVisits - v, limit]),
        t.NodeVisits - v <= limit);
      if k < Lines then
        AssertEquals('ParaOfPos value', k, got);
      y := NextRandom(t.TotalHeight);
      v := t.NodeVisits;
      got := t.ParaAtHeight(y);
      AssertTrue(Format('ParaAtHeight visited %d nodes, limit %d', [t.NodeVisits - v, limit]),
        t.NodeVisits - v <= limit);
      AssertEquals('ParaAtHeight value', (y div 16) * 16, got);
    end;
  finally
    t.Free;
  end;
end;

procedure TTyRichTextTest.TestOriginalBufferIsNotCopied;
const
  Size = 100 * 1024 * 1024;
var
  t: TTyRichText;
  buf: TBytes;
  line: UTF8String;
  lines, i, rest, lineChars: Integer;
  h0, h1, budget: Int64;
begin
  line := 'Mixed 中文 and English, 混排的一行文字 line '#10;
  lineChars := Utf8Chars(line);
  lines := Size div System.Length(line);
  rest := Size - lines * System.Length(line);
  buf := nil;
  SetLength(buf, Size);
  for i := 0 to lines - 1 do
    Move(line[1], buf[i * System.Length(line)], System.Length(line));
  for i := lines * System.Length(line) to Size - 1 do
    buf[i] := Ord('x');
  h0 := GetFPCHeapStatus.CurrHeapUsed;
  t := TTyRichText.CreateFromUtf8(buf);
  try
    h1 := GetFPCHeapStatus.CurrHeapUsed;
    AssertEquals('paragraphs', lines + 1, t.ParaCount);
    AssertEquals('length', Int64(lines) * lineChars + rest, t.Length);
    budget := Int64(t.ParaCount) * 32 + 1024 * 1024;
    AssertTrue(Format('the text allocated %d bytes for %d paragraphs, budget %d',
      [h1 - h0, t.ParaCount, budget]), h1 - h0 <= budget);
    buf[0] := Ord('Q');
    AssertBytesEqual('the buffer is referenced, not copied', 'Qixed', t.GetText(0, 5));
  finally
    t.Free;
  end;
end;

procedure TTyRichTextTest.TestDeletingEverythingStoresPiecesNotText;
const
  Sentence: UTF8String = 'A line of 中文 and English text. ';
var
  t: TTyRichText;
  buf, line, expected: UTF8String;
  i, len: Integer;
  p: TTyRichPieces;
  h0, h1, added: Int64;
begin
  line := '';
  for i := 1 to 10 do line := line + Sentence;
  line := line + #13#10;
  buf := '';
  len := 0;
  for i := 1 to 20000 do AddStr(buf, len, line);
  SetLength(buf, len);
  t := TTyRichText.CreateFromUtf8(Bytes(buf));
  try
    t.Insert(5, 'edit');
    t.Insert(t.ParaStart(100), 'new'#13#10);
    t.Delete(t.ParaStart(200) + 3, 400);
    expected := t.GetText(0, t.Length);
    added := t.AddedBytes;
    h0 := GetFPCHeapStatus.CurrHeapUsed;
    p := t.PieceSnapshot(0, t.Length);
    h1 := GetFPCHeapStatus.CurrHeapUsed;
    AssertTrue(Format('the snapshot allocated %d bytes for %d pieces of %d bytes', [h1 - h0,
      System.Length(p.Pieces), SizeOf(TTyRichPiece)]),
      h1 - h0 <= Int64(System.Length(p.Pieces)) * SizeOf(TTyRichPiece) + 64 * 1024);
    AssertTrue('the pieces are far smaller than the text', h1 - h0 < System.Length(buf) div 4);
    AssertEquals('the snapshot covers the whole text', t.Length, p.CharCount);
    t.Delete(0, t.Length);
    AssertEquals('empty', 0, t.Length);
    AssertEquals('one empty paragraph', 1, t.ParaCount);
    t.RestorePieces(0, p);
    AssertEquals('no text was copied into the add buffer', added, t.AddedBytes);
    AssertBytesEqual('restored', expected, t.GetText(0, t.Length));
    AssertEquals('integrity', '', t.CheckIntegrity);
  finally
    t.Free;
  end;
end;

procedure TTyRichTextTest.TestSeparatorsAreNotRepaired;
var
  t: TTyRichText;
begin
  t := TTyRichText.CreateFromUtf8(Bytes('a'#13'b'));
  try
    t.Insert(2, #10'x');
    AssertBytesEqual('the bytes are adjacent', 'a'#13#10'xb', t.GetText(0, t.Length));
    AssertEquals('but the separators stay two characters', 5, t.Length);
    AssertEquals('three paragraphs', 3, t.ParaCount);
    AssertEquals('the old one is still a CR', Ord(rsCR), Ord(t.ParaSeparator(0)));
    AssertEquals('the new one is an LF', Ord(rsLF), Ord(t.ParaSeparator(1)));
    t.Insert(0, 'p'#13#10'q');
    AssertEquals('within one inserted string CRLF is one separator', 8, t.Length);
    AssertEquals('four paragraphs', 4, t.ParaCount);
    AssertEquals('kind CRLF', Ord(rsCRLF), Ord(t.ParaSeparator(0)));
    t.Delete(2, 3);
    AssertBytesEqual('deleting q, a and the CR', 'p'#13#10#10'xb', t.GetText(0, t.Length));
    AssertEquals('the CRLF and the LF are still two', 3, t.ParaCount);
  finally
    t.Free;
  end;
end;

procedure TTyRichTextTest.TestInvalidUtf8BytesAreKeptAsCharacters;
var
  t: TTyRichText;
  raw: UTF8String;
begin
  // a, FF, truncated E4 B8, b, overlong C0 80, surrogate ED A0 80, then a real 中
  raw := FromBytes([Ord('a'), $FF, $E4, $B8, Ord('b'), $C0, $80, $ED, $A0, $80,
    $E4, $B8, $AD, 13, $E4]);
  t := TTyRichText.CreateFromUtf8(Bytes(raw));
  try
    AssertEquals('each stray byte is one character', 13, t.Length);
    AssertEquals('two paragraphs', 2, t.ParaCount);
    AssertEquals('the trailing lone lead byte is a paragraph of one', 1, t.ParaLength(1));
    AssertBytesEqual('kept as they are', raw, t.GetText(0, t.Length));
    t.Insert(3, 'z');
    AssertBytesEqual('inserting between the stray bytes',
      FromBytes([Ord('a'), $FF, $E4, Ord('z'), $B8, Ord('b'), $C0, $80, $ED, $A0, $80,
        $E4, $B8, $AD, 13, $E4]), t.GetText(0, t.Length));
    t.Delete(1, 1);
    AssertBytesEqual('deleting one stray byte deletes one byte', FromBytes([Ord('a'), $E4,
      Ord('z'), $B8]), t.GetText(0, 4));
    AssertBytesEqual('the real character is one', FromBytes([$E4, $B8, $AD]), t.GetText(10, 1));
  finally
    t.Free;
  end;
end;

procedure TTyRichTextTest.TestParaDataStaysWithItsParagraph;
var
  t: TTyRichText;
  i: Integer;
begin
  t := TTyRichText.CreateFromUtf8(Bytes('p0'#10'p1'#10'p2'#10'p3'#10'p4'));
  try
    t.OnParasChanged := @ParasChanged;
    t.OnParaDataDropped := @DataDropped;
    for i := 0 to 4 do
    begin
      AssertTrue('nil by default', t.ParaData[i] = nil);
      t.ParaData[i] := Pointer(PtrUInt(100 + i));
    end;
    // split paragraph 0 at its start: the first part keeps the data, the new one is nil
    t.Insert(0, 'new'#10);
    AssertEquals('event for the split', '0,1,2', FChanges[0]);
    AssertTrue('the first part keeps the data', t.ParaData[0] = Pointer(100));
    AssertTrue('the new paragraph gets nil', t.ParaData[1] = nil);
    for i := 1 to 4 do
      AssertTrue(Format('paragraph p%d moved down with its data', [i]),
        t.ParaData[i + 1] = Pointer(PtrUInt(100 + i)));
    // the last paragraph's slot follows the same rule
    t.Insert(t.Length, #10'tail');
    AssertTrue('the last paragraph keeps its data when split', t.ParaData[5] = Pointer(104));
    AssertTrue('the new last paragraph is nil', t.ParaData[6] = nil);
    // merge p1..p3 (paragraphs 2..4): the first keeps its data, the others are reported
    t.Delete(t.ParaStart(2) + 1, t.ParaStart(4) + 1 - (t.ParaStart(2) + 1));
    AssertEquals('event for the merge', '2,3,1', FChanges[FChanges.Count - 1]);
    AssertBytesEqual('merged text', 'p3', t.GetText(t.ParaStart(2), t.ParaLength(2)));
    AssertTrue('the merged paragraph keeps the first one''s data', t.ParaData[2] = Pointer(101));
    AssertEquals('two dropped', 2, FDropped.Count);
    AssertTrue('p2 dropped', FDropped[0] = Pointer(102));
    AssertTrue('p3 dropped', FDropped[1] = Pointer(103));
    AssertTrue('p4 still has its data', t.ParaData[3] = Pointer(104));
    // a delete inside one paragraph changes one paragraph and drops nothing
    t.Delete(t.ParaStart(3), 1);
    AssertEquals('one paragraph changed', '3,1,1', FChanges[FChanges.Count - 1]);
    AssertEquals('nothing more dropped', 2, FDropped.Count);
  finally
    t.Free;
  end;
end;

procedure TTyRichTextTest.TestSnapshotRestorePutsParaDataBack;
var
  t: TTyRichText;
  p: TTyRichPieces;
  a, b: Int64;
  i: Integer;
  before: UTF8String;
begin
  t := TTyRichText.CreateFromUtf8(Bytes('p0'#10'p1'#10'p2'#10'p3'#10'p4'));
  try
    t.OnParaDataDropped := @DataDropped;
    for i := 0 to 4 do
      t.ParaData[i] := Pointer(PtrUInt(100 + i));
    before := t.GetText(0, t.Length);
    // from inside p1 to inside p3: paragraphs 1..3 merge
    a := t.ParaStart(1) + 1;
    b := t.ParaStart(3) + 1;
    p := t.PieceSnapshot(a, b - a);
    t.Delete(a, b - a);
    AssertEquals('three paragraphs', 3, t.ParaCount);
    AssertEquals('p2 and p3 dropped', 2, FDropped.Count);
    t.RestorePieces(a, p);
    AssertBytesEqual('text back', before, t.GetText(0, t.Length));
    for i := 0 to 4 do
      AssertTrue(Format('data of p%d back', [i]), t.ParaData[i] = Pointer(PtrUInt(100 + i)));
    // the same across the end of the text (the last paragraph's slot)
    a := t.ParaStart(3);
    p := t.PieceSnapshot(a, t.Length - a);
    t.Delete(a, t.Length - a);
    t.RestorePieces(a, p);
    AssertBytesEqual('text back again', before, t.GetText(0, t.Length));
    for i := 0 to 4 do
      AssertTrue(Format('data of p%d back again', [i]), t.ParaData[i] = Pointer(PtrUInt(100 + i)));
    AssertEquals('integrity', '', t.CheckIntegrity);
  finally
    t.Free;
  end;
end;

procedure TTyRichTextTest.TestRunsTellOriginalFromEdited;
var
  t: TTyRichText;
  buf: TBytes;
  i: Integer;
  total: Int64;
begin
  buf := Bytes('ab'#13#10'cd'#10'ef');
  t := TTyRichText.CreateFromUtf8(buf);
  try
    t.ForEachRun(0, t.Length, @CollectRun);
    AssertEquals('one run per untouched paragraph', 3, System.Length(FRuns));
    AssertEquals('original', Ord(rpkOriginal), Ord(FRuns[0].Kind));
    AssertEquals('offset 0', 0, FRuns[0].SrcOffset);
    AssertEquals('with its CRLF', 4, FRuns[0].ByteCount);
    AssertEquals('chars', 3, FRuns[0].CharCount);
    AssertEquals('ends with CRLF', Ord(rsCRLF), Ord(FRuns[0].Separator));
    AssertTrue('points into the buffer', FRuns[0].Bytes = @buf[0]);
    AssertEquals('second at offset 4', 4, FRuns[1].SrcOffset);
    AssertTrue('second points into the buffer', FRuns[1].Bytes = @buf[4]);
    AssertEquals('third', 7, FRuns[2].SrcOffset);
    AssertEquals('third ends the text', Ord(rsNone), Ord(FRuns[2].Separator));
    // edit paragraph 1: its runs are no longer one original run
    t.Insert(4, 'X');
    FRuns := nil;
    t.ForEachRun(t.ParaStart(1), t.ParaLength(1) + 1, @CollectRun);
    AssertEquals('c, X, d+LF', 3, System.Length(FRuns));
    AssertEquals('c original', Ord(rpkOriginal), Ord(FRuns[0].Kind));
    AssertEquals('X added', Ord(rpkAdded), Ord(FRuns[1].Kind));
    AssertTrue('added bytes are readable', FRuns[1].Bytes^ = Ord('X'));
    AssertEquals('d original at 5', 5, FRuns[2].SrcOffset);
    // a partial range reports partial runs
    FRuns := nil;
    t.ForEachRun(1, 3, @CollectRun);
    total := 0;
    for i := 0 to High(FRuns) do Inc(total, FRuns[i].ByteCount);
    AssertEquals('b, CRLF, c', 4, total);
    AssertEquals('starts at b', 1, FRuns[0].SrcOffset);
  finally
    t.Free;
  end;
end;

procedure TTyRichTextTest.TestHeightIndex;
var
  t: TTyRichText;
begin
  t := TTyRichText.CreateFromUtf8(Bytes('a'#10'b'#10'c'#10'd'));
  try
    t.SetParaHeight(0, 10);
    t.SetParaHeight(1, 20);
    t.SetParaHeight(3, 5);
    AssertEquals('total', 35, t.TotalHeight);
    AssertEquals('top of 2', 30, t.ParaTop(2));
    AssertEquals('top of 3', 30, t.ParaTop(3));
    AssertEquals('height of 1', 20, t.ParaHeight(1));
    AssertEquals('y 0', 0, t.ParaAtHeight(0));
    AssertEquals('y 9', 0, t.ParaAtHeight(9));
    AssertEquals('y 10', 1, t.ParaAtHeight(10));
    AssertEquals('y 30 skips the empty-height paragraph', 3, t.ParaAtHeight(30));
    AssertEquals('below the end is the last', 3, t.ParaAtHeight(1000));
    AssertEquals('above the start is the first', 0, t.ParaAtHeight(-4));
    // a split leaves the height with the first part
    t.Insert(t.ParaStart(1) + 1, #10);
    AssertEquals('first part keeps 20', 20, t.ParaHeight(1));
    AssertEquals('new paragraph 0', 0, t.ParaHeight(2));
    AssertEquals('total unchanged', 35, t.TotalHeight);
    // a merge keeps the first one's height
    t.Delete(t.ParaStart(1), 3);
    AssertEquals('merged keeps 20', 20, t.ParaHeight(1));
    AssertEquals('total', 35, t.TotalHeight);
  finally
    t.Free;
  end;
end;

procedure TTyRichTextTest.CheckHeights(const AWhat: string; AText: TTyRichText;
  const ARef: THeightRef);
var
  d, total, y: Int64;
  i, k, last: Integer;
begin
  d := AText.DefaultParaHeight;
  last := High(ARef);
  AssertEquals(AWhat + ': ParaCount', System.Length(ARef), AText.ParaCount);
  total := RefTop(ARef, d, System.Length(ARef));
  AssertEquals(AWhat + ': TotalHeight', total, AText.TotalHeight);
  AssertEquals(AWhat + ': MeasuredParaCount', RefMeasured(ARef), AText.MeasuredParaCount);
  for i := 0 to 5 do
  begin
    // the two ends, and anywhere
    case i of
      0: k := 0;
      1: k := last;
    else
      k := NextRandom(System.Length(ARef));
    end;
    AssertEquals(Format('%s: ParaMeasured(%d)', [AWhat, k]), ARef[k] >= 0, AText.ParaMeasured(k));
    AssertEquals(Format('%s: ParaHeight(%d)', [AWhat, k]), RefH(ARef, d, k), AText.ParaHeight(k));
    AssertEquals(Format('%s: ParaTop(%d)', [AWhat, k]), RefTop(ARef, d, k), AText.ParaTop(k));
    y := NextRandom(total + 5);
    AssertEquals(Format('%s: ParaAtHeight(%d)', [AWhat, y]), RefAtHeight(ARef, d, y),
      AText.ParaAtHeight(y));
  end;
end;

{ A paragraph is measured or not. Unmeasured ones count as DefaultParaHeight in every
  lookup; a measured height of 0 is a height (the default does not replace it). }
procedure TTyRichTextTest.TestUnmeasuredParagraphsCountAsTheDefault;
var
  t: TTyRichText;

  procedure Refused(const AWhat: string; AKind: Integer);
  var
    raised: Boolean;
  begin
    raised := False;
    try
      case AKind of
        0: t.SetParaHeights(2, [4, -1]);
        1: t.SetParaHeights(3, [1, 1]);
        2: t.SetParaHeight(0, Int64(TyRichMaxParaHeight) + 1);
        3: t.SetParaHeight(0, -1);
        4: t.DefaultParaHeight := -1;
        5: t.UnmeasureParas(2, 4);
      end;
    except
      on ETyRichText do raised := True;
    end;
    AssertTrue(AWhat + ' must raise', raised);
  end;

var
  p: TTyRichPieces;
begin
  t := TTyRichText.CreateFromUtf8(Bytes('a'#10'b'#10'c'#10'd'));
  try
    // nothing measured and no default yet: no paragraph has a row
    AssertEquals('nothing measured', 0, t.MeasuredParaCount);
    AssertEquals('no height at all', 0, t.TotalHeight);
    AssertEquals('every row is past the end then', 3, t.ParaAtHeight(0));
    t.DefaultParaHeight := 7;
    AssertEquals('four defaults', 28, t.TotalHeight);
    AssertEquals('still nothing measured', 0, t.MeasuredParaCount);
    AssertFalse('paragraph 1 is not measured', t.ParaMeasured(1));
    AssertEquals('it counts as the default', 7, t.ParaHeight(1));
    AssertEquals('top of 2', 14, t.ParaTop(2));
    AssertEquals('row 0', 0, t.ParaAtHeight(0));
    AssertEquals('row 6', 0, t.ParaAtHeight(6));
    AssertEquals('row 7', 1, t.ParaAtHeight(7));
    AssertEquals('the last row', 3, t.ParaAtHeight(27));
    AssertEquals('past the end is the last', 3, t.ParaAtHeight(28));
    AssertEquals('above the start is the first', 0, t.ParaAtHeight(-1));
    // measured ones, the last paragraph among them, next to unmeasured ones
    t.SetParaHeight(1, 20);
    t.SetParaHeight(3, 5);
    AssertEquals('7 + 20 + 7 + 5', 39, t.TotalHeight);
    AssertEquals('two measured', 2, t.MeasuredParaCount);
    AssertTrue('paragraph 1 is measured', t.ParaMeasured(1));
    AssertTrue('the last one too', t.ParaMeasured(3));
    AssertEquals('top of 2 after the measured 1', 27, t.ParaTop(2));
    AssertEquals('top of 3', 34, t.ParaTop(3));
    AssertEquals('row 26', 1, t.ParaAtHeight(26));
    AssertEquals('row 27', 2, t.ParaAtHeight(27));
    AssertEquals('row 34', 3, t.ParaAtHeight(34));
    // a measured 0 is a height: the default no longer applies, and no row is its own
    t.SetParaHeight(2, 0);
    AssertTrue('0 is measured', t.ParaMeasured(2));
    AssertEquals('and is 0', 0, t.ParaHeight(2));
    AssertEquals('7 + 20 + 0 + 5', 32, t.TotalHeight);
    AssertEquals('three measured', 3, t.MeasuredParaCount);
    AssertEquals('it sits at the top of its successor', t.ParaTop(3), t.ParaTop(2));
    AssertEquals('the row at its top is the successor''s', 3, t.ParaAtHeight(27));
    // the default moves the unmeasured paragraphs only
    t.DefaultParaHeight := 100;
    AssertEquals('100 + 20 + 0 + 5', 125, t.TotalHeight);
    AssertEquals('top of 1', 100, t.ParaTop(1));
    AssertEquals('the measured 0 stays 0', 0, t.ParaHeight(2));
    // back to unmeasured: one paragraph, then a range with the last paragraph
    t.UnmeasureParas(2, 2);
    AssertFalse('paragraph 2 is unmeasured again', t.ParaMeasured(2));
    AssertEquals('100 + 20 + 100 + 5', 225, t.TotalHeight);
    AssertEquals('row 120 is its own now', 2, t.ParaAtHeight(120));
    t.UnmeasureParas(1, 3);
    AssertEquals('four defaults again', 400, t.TotalHeight);
    AssertEquals('none measured', 0, t.MeasuredParaCount);
    // several at once, up to the last paragraph
    t.SetParaHeights(1, [1, 2, 3]);
    AssertEquals('100 + 1 + 2 + 3', 106, t.TotalHeight);
    AssertEquals('top of 3 after a range', 103, t.ParaTop(3));
    AssertEquals('three measured again', 3, t.MeasuredParaCount);
    AssertEquals('the last got the last', 3, t.ParaHeight(3));
    // a refused call changes nothing
    Refused('a negative height in a range', 0);
    AssertEquals('the height before the bad one was not stored', 2, t.ParaHeight(2));
    Refused('a range past the last paragraph', 1);
    Refused('a height above the maximum', 2);
    Refused('a negative height', 3);
    Refused('a negative default', 4);
    Refused('unmeasuring past the last paragraph', 5);
    AssertEquals('all as before', 106, t.TotalHeight);
    t.SetParaHeight(0, TyRichMaxParaHeight);
    AssertEquals('the maximum is stored', Int64(TyRichMaxParaHeight), t.ParaHeight(0));
    AssertEquals('and summed', Int64(TyRichMaxParaHeight) + 6, t.TotalHeight);
    // everything at once
    t.UnmeasureAll;
    AssertEquals('all unmeasured', 0, t.MeasuredParaCount);
    AssertEquals('four defaults after the reset', 400, t.TotalHeight);
    AssertEquals('top of 3 after the reset', 300, t.ParaTop(3));
    AssertFalse('the last paragraph was reset too', t.ParaMeasured(3));
    // a split leaves the height with the first part; what it adds is unmeasured
    t.SetParaHeight(1, 20);
    t.Insert(t.ParaStart(1) + 1, #10);
    AssertTrue('the first part is still measured', t.ParaMeasured(1));
    AssertEquals('with its height', 20, t.ParaHeight(1));
    AssertFalse('the new paragraph is not', t.ParaMeasured(2));
    AssertEquals('100 + 20 + 100 + 100 + 100', 420, t.TotalHeight);
    // paragraphs that come back from a snapshot are unmeasured
    t.SetParaHeights(0, [1, 2, 3, 4, 5]);
    p := t.PieceSnapshot(t.ParaStart(1), t.ParaStart(4) - t.ParaStart(1));
    t.Delete(t.ParaStart(1), t.ParaStart(4) - t.ParaStart(1));
    // paragraphs 1..4 are one now
    AssertEquals('the merged paragraph keeps the first one''s height', 2, t.ParaHeight(1));
    AssertEquals('1 + 2', 3, t.TotalHeight);
    t.RestorePieces(t.ParaStart(1), p);
    AssertEquals('five paragraphs again', 5, t.ParaCount);
    AssertEquals('1 + 2 + 100 + 100 + 100', 303, t.TotalHeight);
    AssertEquals('only the two in front are measured', 2, t.MeasuredParaCount);
    AssertEquals('integrity', '', t.CheckIntegrity);
  finally
    t.Free;
  end;
end;

{ Every way of setting and dropping heights, mixed with splits, merges and restores on a
  tree two inner levels deep, against a plain array. }
procedure TTyRichTextTest.TestHeightIndexAgainstAReference;
const
  Lines = 20000;
var
  t: TTyRichText;
  buf: TBytes;
  more: UTF8String;
  ref: THeightRef;
  hs: array of Int64;
  op, kind, i, k, c, n: Integer;
  a, b: Int64;
  p: TTyRichPieces;
begin
  buf := LinesOf(Lines);
  more := '';
  SetLength(more, System.Length(buf));
  Move(buf[0], more[1], System.Length(buf));
  t := TTyRichText.CreateFromUtf8(buf);
  try
    AssertTrue('two inner levels', t.TreeDepth >= 2);
    ref := nil;
    RefInsertUnmeasured(ref, 0, t.ParaCount);
    hs := nil;
    CheckHeights('loaded', t, ref);
    for op := 1 to 600 do
    begin
      n := t.ParaCount;
      kind := NextRandom(20);
      if (kind = 12) and (NextRandom(3) > 0) then kind := 0;
      if (kind >= 15) and (n < 3) then kind := 0;
      case kind of
        0..5:
          begin
            k := NextRandom(n);
            c := NextRandom(40);
            t.SetParaHeight(k, c);
            ref[k] := c;
          end;
        6..8:
          begin
            k := NextRandom(n);
            c := 1 + NextRandom(Min(700, n - k));
            SetLength(hs, c);
            for i := 0 to c - 1 do hs[i] := NextRandom(40);
            t.SetParaHeights(k, hs);
            for i := 0 to c - 1 do ref[k + i] := hs[i];
          end;
        9..10:
          begin
            k := NextRandom(n);
            c := NextRandom(Min(700, n - k));
            t.UnmeasureParas(k, k + c);
            for i := k to k + c do ref[i] := -1;
          end;
        11: t.DefaultParaHeight := NextRandom(30);
        12:
          begin
            t.UnmeasureAll;
            for i := 0 to High(ref) do ref[i] := -1;
          end;
        13..14:
          begin
            // a split by two separators: the first part keeps the height
            k := NextRandom(n);
            t.Insert(t.ParaStart(k) + NextRandom(t.ParaLength(k) + 1), 'x'#10'y'#13#10'z');
            RefInsertUnmeasured(ref, k + 1, 2);
          end;
      else
        // paragraphs k..k+c merge (now and then enough of them to empty inner nodes)
        k := NextRandom(n - 1);
        if NextRandom(10) = 0 then c := 1 + NextRandom(Min(6000, n - 1 - k))
        else c := 1 + NextRandom(Min(300, n - 1 - k));
        a := t.ParaStart(k) + NextRandom(t.ParaLength(k) + 1);
        b := t.ParaStart(k + c) + NextRandom(t.ParaLength(k + c) + 1);
        if kind <= 17 then
        begin
          t.Delete(a, b - a);
          RefRemove(ref, k + 1, c);
        end
        else
        begin
          // and come back: what a restore brings is unmeasured
          p := t.PieceSnapshot(a, b - a);
          t.Delete(a, b - a);
          t.RestorePieces(a, p);
          for i := k + 1 to k + c do ref[i] := -1;
        end;
      end;
      CheckHeights(Format('op %d (kind %d)', [op, kind]), t, ref);
      if op mod 20 = 0 then
        AssertEquals(Format('op %d: integrity', [op]), '', t.CheckIntegrity);
      if t.ParaCount < 8000 then
      begin
        t.Insert(t.Length, more);
        RefInsertUnmeasured(ref, System.Length(ref), Lines);
        CheckHeights(Format('op %d: refilled', [op]), t, ref);
      end;
    end;
    AssertEquals('integrity', '', t.CheckIntegrity);
  finally
    t.Free;
  end;
end;

{ The layout sets heights while it scrolls and drops them all when the width changes, in a
  document of millions of paragraphs: a height costs one descent and recomputes no node, a
  range goes leaf by leaf, and the default and the reset touch nothing at all. }
procedure TTyRichTextTest.TestSettingHeightsRecomputesNothing;
const
  Lines = 2000000;
  Singles = 10000;
  RangeFirst = 500000;
  RangeCount = 1000000;
var
  t: TTyRichText;
  ref, tops, hs: array of Int64;
  n, i, k, depth, lo, hi, mid: Integer;
  v, s, limit, y: Int64;

  procedure Sum;
  var
    j: Integer;
  begin
    tops[0] := 0;
    for j := 0 to n - 1 do
      if ref[j] < 0 then tops[j + 1] := tops[j] + t.DefaultParaHeight
      else tops[j + 1] := tops[j] + ref[j];
  end;

  procedure Lookups(const AWhat: string);
  var
    j: Integer;
  begin
    AssertEquals(AWhat + ': TotalHeight', tops[n], t.TotalHeight);
    for j := 1 to 200 do
    begin
      k := NextRandom(n);
      v := t.NodeVisits;
      AssertEquals(Format('%s: ParaTop(%d)', [AWhat, k]), tops[k], t.ParaTop(k));
      AssertTrue(Format('%s: ParaTop visited %d nodes', [AWhat, t.NodeVisits - v]),
        t.NodeVisits - v <= depth + 1);
      // every height here is above 0, so each row has one paragraph
      y := tops[k] + NextRandom(tops[k + 1] - tops[k]);
      v := t.NodeVisits;
      AssertEquals(Format('%s: ParaAtHeight(%d)', [AWhat, y]), k, t.ParaAtHeight(y));
      AssertTrue(Format('%s: ParaAtHeight visited %d nodes', [AWhat, t.NodeVisits - v]),
        t.NodeVisits - v <= depth + 1);
    end;
    AssertEquals(AWhat + ': no summary was recomputed', s, t.SumScans);
  end;

begin
  t := TTyRichText.CreateFromUtf8(LinesOf(Lines));
  try
    n := t.ParaCount;
    depth := t.TreeDepth;
    ref := nil;
    SetLength(ref, n);
    for i := 0 to n - 1 do ref[i] := -1;
    tops := nil;
    SetLength(tops, n + 1);
    s := t.SumScans;

    // the estimate for everything: no node is touched
    v := t.NodeVisits;
    t.DefaultParaHeight := 20;
    AssertEquals('the default visits nothing', v, t.NodeVisits);
    Sum;
    AssertEquals('every paragraph counts as the default', Int64(20) * n, tops[n]);
    Lookups('default');

    // single heights: a descent each
    v := t.NodeVisits;
    for i := 1 to Singles do
    begin
      t.SetParaHeight(i * 199, 16);
      ref[i * 199] := 16;
    end;
    limit := Int64(Singles) * (depth + 1);
    AssertTrue(Format('%d heights visited %d nodes, limit %d', [Singles, t.NodeVisits - v, limit]),
      t.NodeVisits - v <= limit);
    AssertEquals('measured', Singles, t.MeasuredParaCount);
    Sum;
    Lookups('single heights');

    // a range: one descent, then leaf by leaf
    hs := nil;
    SetLength(hs, RangeCount);
    for i := 0 to RangeCount - 1 do
    begin
      hs[i] := 10 + i mod 7;
      ref[RangeFirst + i] := hs[i];
    end;
    v := t.NodeVisits;
    t.SetParaHeights(RangeFirst, hs);
    limit := RangeCount div 100 + 4 * (depth + 1);
    AssertTrue(Format('a range of %d visited %d nodes, limit %d', [RangeCount, t.NodeVisits - v,
      limit]), t.NodeVisits - v <= limit);
    Sum;
    Lookups('range');

    // a range dropped again
    v := t.NodeVisits;
    t.UnmeasureParas(100000, 899999);
    limit := 800000 div 100 + 4 * (depth + 1);
    AssertTrue(Format('unmeasuring 800000 visited %d nodes, limit %d', [t.NodeVisits - v, limit]),
      t.NodeVisits - v <= limit);
    for i := 100000 to 899999 do ref[i] := -1;
    Sum;
    Lookups('range dropped');

    // everything dropped: nothing is walked
    v := t.NodeVisits;
    t.UnmeasureAll;
    AssertEquals('the reset visits nothing', v, t.NodeVisits);
    AssertEquals('nothing is measured', 0, t.MeasuredParaCount);
    for i := 0 to n - 1 do ref[i] := -1;
    Sum;
    AssertEquals('every paragraph counts as the default again', Int64(20) * n, tops[n]);
    Lookups('reset');

    // heights set after the reset hold, also in leaves the range walk is the first to enter
    t.SetParaHeights(700000, hs[0..49999]);
    for i := 0 to 49999 do ref[700000 + i] := hs[i];
    t.SetParaHeight(n - 1, 5);
    ref[n - 1] := 5;
    t.SetParaHeight(3, 8);
    ref[3] := 8;
    AssertEquals('measured after the reset', 50002, t.MeasuredParaCount);
    Sum;
    Lookups('after the reset');
    // a second reset right after
    t.UnmeasureAll;
    t.SetParaHeight(1500000, 9);
    for i := 0 to n - 1 do ref[i] := -1;
    ref[1500000] := 9;
    Sum;
    Lookups('second reset');
    AssertEquals('integrity', '', t.CheckIntegrity);

    // the reference's own search, so the test does not lean on its own expectations only
    y := tops[n] div 3;
    lo := 0;
    hi := n - 1;
    while lo < hi do
    begin
      mid := (lo + hi) div 2;
      if tops[mid + 1] > y then hi := mid else lo := mid + 1;
    end;
    AssertEquals('a row a third down', lo, t.ParaAtHeight(y));
  finally
    t.Free;
  end;
end;

{ UnmeasureAll walks nothing, so a leaf nobody has entered since still has its old heights
  written in it. When a neighbour takes its pieces in, they must not come along. }
procedure TTyRichTextTest.TestUnmeasureAllHoldsThroughAMerge;
var
  t: TTyRichText;
  hs: array of Int64;
  i: Integer;
begin
  // one piece per paragraph, 128 to a leaf: leaf 1 is paragraphs 128..255, leaf 2 256..383
  t := TTyRichText.CreateFromUtf8(LinesOf(1000));
  try
    hs := nil;
    SetLength(hs, t.ParaCount);
    for i := 0 to High(hs) do hs[i] := 10;
    t.SetParaHeights(0, hs);
    AssertEquals('all measured', 10010, t.TotalHeight);
    // thin leaf 2 out while its heights still count
    t.Delete(t.ParaStart(260), t.ParaStart(381) - t.ParaStart(260));
    AssertEquals('121 paragraphs fewer', 8800, t.TotalHeight);
    t.DefaultParaHeight := 3;
    t.UnmeasureAll;
    AssertEquals('all unmeasured', Int64(3) * 880, t.TotalHeight);
    // thin leaf 1 out: it takes leaf 2 in, which no lookup has entered since the reset
    t.Delete(t.ParaStart(130), t.ParaStart(251) - t.ParaStart(130));
    AssertEquals('paragraphs', 759, t.ParaCount);
    AssertEquals('nothing is measured', 0, t.MeasuredParaCount);
    AssertEquals('every paragraph is the default', Int64(3) * 759, t.TotalHeight);
    AssertEquals('top of a paragraph behind the merge', 600, t.ParaTop(200));
    AssertEquals('integrity', '', t.CheckIntegrity);
  finally
    t.Free;
  end;
end;

procedure TTyRichTextTest.TestManyEditsKeepTheTreeConsistent;
var
  t: TTyRichText;
  ref: TRefUnits;
  buf, s: UTF8String;
  op, pos, len, kind: Integer;
  p: TTyRichPieces;
begin
  buf := MixedLines(3000, 2);
  ref := SplitUnits(buf);
  t := TTyRichText.CreateFromUtf8(Bytes(buf));
  try
    for op := 1 to 1500 do
    begin
      kind := NextRandom(20);
      if (kind < 8) or (t.Length = 0) then
      begin
        s := RandomText(40);
        pos := NextRandom(t.Length + 1);
        t.Insert(pos, s);
        RefInsert(ref, pos, s);
      end
      else if kind < 14 then
      begin
        pos := NextRandom(t.Length);
        len := 1 + NextRandom(Min(3000, t.Length - pos));
        t.Delete(pos, len);
        RefDelete(ref, pos, len);
      end
      else if kind < 19 then
      begin
        // what an undo of a delete does: the range comes back from its pieces
        pos := NextRandom(t.Length);
        len := 1 + NextRandom(Min(5000, t.Length - pos));
        p := t.PieceSnapshot(pos, len);
        t.Delete(pos, len);
        t.RestorePieces(pos, p);
      end
      else
      begin
        // delete everything and put it back
        p := t.PieceSnapshot(0, t.Length);
        t.Delete(0, t.Length);
        AssertEquals('emptied', 0, t.Length);
        t.RestorePieces(0, p);
      end;
      CheckSame(Format('op %d', [op]), t, ref, op mod 100 = 0);
    end;
    CheckSame('end', t, ref, True);
  finally
    t.Free;
  end;
end;

{ Big edits on a tree two inner levels deep, so inner nodes split, merge and empty. The
  expected text comes from the state before each edit. }
procedure TTyRichTextTest.TestDeepTreeStaysConsistent;
var
  t: TTyRichText;
  buf, s, expected: UTF8String;
  op, pos, len: Integer;
  p: TTyRichPieces;
begin
  buf := MixedLines(40000, 3);
  t := TTyRichText.CreateFromUtf8(Bytes(buf));
  try
    AssertTrue('two inner levels', t.TreeDepth >= 2);
    for op := 1 to 300 do
    begin
      case NextRandom(3) of
        0:
          begin
            s := RandomText(3000);
            pos := NextRandom(t.Length + 1);
            expected := t.GetText(0, pos) + s + t.GetText(pos, t.Length - pos);
            t.Insert(pos, s);
          end;
        1:
          begin
            pos := NextRandom(t.Length);
            len := 1 + NextRandom(Min(200000, t.Length - pos));
            expected := t.GetText(0, pos) + t.GetText(pos + len, t.Length - pos - len);
            t.Delete(pos, len);
          end;
      else
        pos := NextRandom(t.Length);
        len := 1 + NextRandom(t.Length - pos);
        expected := t.GetText(0, t.Length);
        p := t.PieceSnapshot(pos, len);
        t.Delete(pos, len);
        AssertEquals(Format('op %d: integrity after the delete', [op]), '', t.CheckIntegrity);
        t.RestorePieces(pos, p);
      end;
      AssertEquals(Format('op %d: integrity', [op]), '', t.CheckIntegrity);
      AssertBytesEqual(Format('op %d: text', [op]), expected, t.GetText(0, t.Length));
      if t.Length < 100000 then
        t.Insert(t.Length, buf);
    end;
    // take it all apart from the front, a leaf's worth and more at a time
    while t.Length > 0 do
    begin
      t.Delete(0, Min(t.Length, 1 + NextRandom(50000)));
      AssertEquals('integrity while emptying', '', t.CheckIntegrity);
    end;
    AssertEquals('one empty paragraph', 1, t.ParaCount);
    AssertEquals('depth collapses', 0, t.TreeDepth);
  finally
    t.Free;
  end;
end;

{ After a load every leaf is full. A character typed inside a paragraph adds two pieces to
  its leaf; the index may grow by about those pieces, not by a leaf for each of them. }
procedure TTyRichTextTest.TestSmallInsertsDoNotMakeALeafEach;
const
  Lines = 20000;
var
  t: TTyRichText;
  buf: TBytes;
  ref: UTF8String;
  i, len: Integer;
  h0, h1, h2, index, pieces0, added, budget: Int64;
begin
  buf := nil;
  SetLength(buf, Lines * 5);
  for i := 0 to Lines - 1 do
  begin
    buf[i * 5] := Ord('a');
    buf[i * 5 + 1] := Ord('b');
    buf[i * 5 + 2] := Ord('c');
    buf[i * 5 + 3] := Ord('d');
    buf[i * 5 + 4] := 10;
  end;
  h0 := GetFPCHeapStatus.CurrHeapUsed;
  t := TTyRichText.CreateFromUtf8(buf);
  try
    h1 := GetFPCHeapStatus.CurrHeapUsed;
    index := h1 - h0;
    pieces0 := t.PieceCount;
    // sparse: one insert in every leaf's worth of paragraphs. However few pieces come in, a
    // leaf that splits leaves two half-full ones, so the index can at most double
    i := 0;
    while i < Lines do
    begin
      t.Insert(t.ParaStart(i) + 2, 'x');
      Inc(i, 64);
    end;
    h2 := GetFPCHeapStatus.CurrHeapUsed;
    AssertTrue(Format('sparse inserts grew an index of %d bytes by %d', [index, h2 - h1]),
      h2 - h1 <= index + 64 * 1024);
    // dense: a character typed inside every paragraph
    for i := 0 to Lines - 1 do
      if i mod 64 <> 0 then
        t.Insert(t.ParaStart(i) + 2, 'x');
    h2 := GetFPCHeapStatus.CurrHeapUsed;
    added := t.PieceCount - pieces0;
    AssertEquals('two pieces per insert', Int64(2) * Lines, added);
    // leaves at least half full, the inner nodes and the add buffer on top
    budget := added * 3 * SizeOf(TTyRichPiece) + 128 * 1024;
    AssertTrue(Format('%d pieces added grew the heap by %d bytes (%d each), budget %d',
      [added, h2 - h1, (h2 - h1) div added, budget]), h2 - h1 <= budget);
    AssertEquals('integrity', '', t.CheckIntegrity);
    ref := '';
    len := 0;
    for i := 0 to Lines - 1 do AddStr(ref, len, 'abxcd'#10);
    SetLength(ref, len);
    AssertBytesEqual('text', ref, t.GetText(0, t.Length));
  finally
    t.Free;
  end;
  // lines added at the end one by one still pack the leaves: the full leaf is left alone
  h0 := GetFPCHeapStatus.CurrHeapUsed;
  t := TTyRichText.Create;
  try
    for i := 0 to Lines - 1 do
      t.Insert(t.Length, 'abcd'#10);
    h1 := GetFPCHeapStatus.CurrHeapUsed;
    AssertEquals('a piece per line', Lines, t.PieceCount);
    // the add buffer doubles, so it holds at most twice its text
    budget := Int64(Lines) * SizeOf(TTyRichPiece) * 5 div 4 + 2 * t.AddedBytes + 64 * 1024;
    AssertTrue(Format('%d appended pieces took %d bytes, budget %d', [Lines, h1 - h0, budget]),
      h1 - h0 <= budget);
    AssertEquals('integrity after appends', '', t.CheckIntegrity);
  finally
    t.Free;
  end;
end;

{ Each insert is counted on its own, and a lookup counts the bytes of a piece together. So
  the piece typing extends must not take text that completes a sequence its own bytes began:
  the joined bytes would be fewer characters than the two counts say. }
procedure TTyRichTextTest.TestTypingNeverJoinsBytesCountedApart;
const
  // a three-byte, a two-byte and a four-byte character
  Whole: array[0..2] of UTF8String = ('中', 'é', '😀');
var
  t: TTyRichText;
  w, cut, i: Integer;
  first, second, all: UTF8String;
begin
  for w := 0 to High(Whole) do
    for cut := 1 to System.Length(Whole[w]) - 1 do
    begin
      first := Copy(Whole[w], 1, cut);
      second := Copy(Whole[w], cut + 1, MaxInt);
      all := first + second;
      t := TTyRichText.Create;
      try
        t.Insert(0, first);
        t.Insert(cut, second);
        AssertEquals(Format('%d/%d: every stray byte is a character', [w, cut]),
          System.Length(all), t.Length);
        AssertEquals(Format('%d/%d: integrity', [w, cut]), '', t.CheckIntegrity);
        for i := 1 to System.Length(all) do
          AssertBytesEqual(Format('%d/%d: character %d', [w, cut, i - 1]), Copy(all, i, 1),
            t.GetText(i - 1, 1));
        // what undoing the second insert does
        t.Delete(cut, System.Length(second));
        AssertEquals(Format('%d/%d: length after the undo', [w, cut]), cut, t.Length);
        AssertBytesEqual(Format('%d/%d: text after the undo', [w, cut]), first,
          t.GetText(0, t.Length));
        AssertEquals(Format('%d/%d: integrity after the undo', [w, cut]), '', t.CheckIntegrity);
      finally
        t.Free;
      end;
    end;
  // typing whole characters still grows the one piece
  t := TTyRichText.Create;
  try
    t.Insert(0, 'a');
    t.Insert(1, '中');
    t.Insert(2, 'é');
    t.Insert(3, 'b');
    AssertEquals('typing is one piece', 1, t.PieceCount);
    AssertEquals('four characters', 4, t.Length);
    AssertBytesEqual('typed', 'a中éb', t.GetText(0, t.Length));
    AssertEquals('integrity of the typed piece', '', t.CheckIntegrity);
  finally
    t.Free;
  end;
end;

{ What a walk's callback may not do: every way of changing the text, each tried once. They
  all aim at the end of a text of one leaf, so that a walk without its guard goes on over
  memory that is still there and the test fails instead of crashing. }
procedure TTyRichTextTest.TryEdits;
var
  kind: Integer;
begin
  if FWalkText.GetText(0, 1) <> 'p' then
    raise Exception.Create('a walk must let its callback read the text');
  for kind := 0 to 2 do
  begin
    Inc(FWalkTried);
    try
      case kind of
        0: FWalkText.Insert(FWalkText.Length, 'z');
        1: FWalkText.Delete(FWalkText.Length - 1, 1);
      else
        FWalkText.RestorePieces(FWalkText.Length, FWalkPieces);
      end;
    except
      on ETyRichText do Inc(FWalkRefused);
    end;
  end;
  if FWalkRaise then raise ETestStop.Create('stop');
end;

function TTyRichTextTest.EditInMap(AIndex: Integer; AData: Pointer): Pointer;
begin
  TryEdits;
  Result := AData;
end;

procedure TTyRichTextTest.EditInWalk(AIndex: Integer; AData: Pointer; ASrcOffset,
  ASrcBytes: Int64; var AContinue: Boolean);
begin
  AContinue := False;
  TryEdits;
end;

procedure TTyRichTextTest.EditInRun(const ARun: TTyRichByteRun; var AContinue: Boolean);
begin
  AContinue := False;
  TryEdits;
end;

{ All three walks hold their place in the tree while foreign code runs: an edit from the
  callback is refused (a defined failure, not a walk over freed nodes), and the refusal ends
  with the walk - also when the callback raises. }
procedure TTyRichTextTest.TestWalksRefuseAnEditFromTheirCallback;
const
  Names: array[0..2] of string = ('MapParaData', 'WalkParas', 'ForEachRun');
var
  t: TTyRichText;
  before: UTF8String;
  walk: Integer;
  raising, stopped: Boolean;
  what: string;
begin
  t := TTyRichText.CreateFromUtf8(Bytes('p0'#10'p1'#10'p2'#10'p3'#10'p4'));
  try
    FWalkText := t;
    FWalkPieces := t.PieceSnapshot(0, 1);
    before := t.GetText(0, t.Length);
    for walk := 0 to 2 do
      for raising := False to True do
      begin
        what := Names[walk];
        if raising then what := what + ' (callback raises)';
        FWalkTried := 0;
        FWalkRefused := 0;
        FWalkRaise := raising;
        stopped := False;
        try
          case walk of
            0: t.MapParaData(0, 0, @EditInMap);
            1: t.WalkParas(0, @EditInWalk);
          else
            t.ForEachRun(0, t.Length, @EditInRun);
          end;
        except
          on ETestStop do stopped := True;
        end;
        AssertEquals(what + ': the callback ran once', 3, FWalkTried);
        AssertEquals(what + ': every edit was refused', 3, FWalkRefused);
        AssertEquals(what + ': the callback''s exception came out', raising, stopped);
        AssertBytesEqual(what + ': the text is as it was', before, t.GetText(0, t.Length));
        // the walk is over: the text can change again
        t.Insert(0, 'q');
        t.Delete(0, 1);
        AssertBytesEqual(what + ': edits work after the walk', before, t.GetText(0, t.Length));
        AssertEquals(what + ': integrity', '', t.CheckIntegrity);
      end;
  finally
    FWalkText := nil;
    t.Free;
  end;
end;

{ The pieces of an insert are found in a buffer of the text's; after a paste of many lines
  that buffer is as big as the index it filled, and must not stay for the object's life. }
procedure TTyRichTextTest.TestABigInsertKeepsNoScanBuffer;
const
  Lines = 100000;
var
  t: TTyRichText;
  buf: TBytes;
  s: UTF8String;
  h0, h1, budget: Int64;
begin
  buf := LinesOf(Lines);
  s := '';
  SetLength(s, System.Length(buf));
  Move(buf[0], s[1], System.Length(buf));
  buf := nil;
  h0 := GetFPCHeapStatus.CurrHeapUsed;
  t := TTyRichText.Create;
  try
    t.Insert(0, s);
    h1 := GetFPCHeapStatus.CurrHeapUsed;
    AssertEquals('a piece per line', Lines, t.PieceCount);
    // the packed index and the text in the add buffer
    budget := Int64(Lines) * SizeOf(TTyRichPiece) * 5 div 4 + 2 * t.AddedBytes + 64 * 1024;
    AssertTrue(Format('an insert of %d lines left %d bytes, budget %d', [Lines, h1 - h0, budget]),
      h1 - h0 <= budget);
    // and the next insert still works
    t.Insert(1, 'x'#10'y');
    AssertBytesEqual('inserted after the big one', 'ax'#10'yb'#10, t.GetText(0, 6));
    AssertEquals('integrity', '', t.CheckIntegrity);
  finally
    t.Free;
  end;
end;

procedure TTyRichTextTest.TestControlCharactersAreCharacters;
var
  t: TTyRichText;
begin
  t := TTyRichText.CreateFromUtf8(Bytes('ab'));
  try
    t.Insert(1, #0#9#0);
    AssertEquals('NUL and TAB are a character each', 5, t.Length);
    AssertEquals('and no separator', 1, t.ParaCount);
    AssertBytesEqual('kept as they are', 'a'#0#9#0'b', t.GetText(0, t.Length));
    AssertBytesEqual('one of them', #9, t.GetText(2, 1));
    t.Delete(1, 1);
    AssertBytesEqual('a NUL deleted', 'a'#9#0'b', t.GetText(0, t.Length));
    AssertEquals('integrity', '', t.CheckIntegrity);
  finally
    t.Free;
  end;
end;

{ A reader that finds the pieces itself hands them in unchecked against the bytes (that would
  be the scan it saves); what cannot be a piece at all is refused. }
procedure TTyRichTextTest.TestScannedPiecesMustBePossible;

  procedure Refused(const AWhat: string; ABytes, AChars: LongInt; ASep: TTyRichSeparator);
  var
    t: TTyRichText;
    raised: Boolean;
  begin
    t := TTyRichText.CreateScanned;
    try
      raised := False;
      try
        t.AppendScanned(ABytes, AChars, ASep);
      except
        on ETyRichText do raised := True;
      end;
      AssertTrue(AWhat + ' must raise', raised);
    finally
      t.Free;
    end;
  end;

var
  t: TTyRichText;
begin
  Refused('no bytes', 0, 0, rsNone);
  Refused('more characters than bytes', 2, 3, rsNone);
  Refused('a CRLF in one byte', 1, 1, rsCRLF);
  Refused('two characters before a CRLF in three bytes', 3, 3, rsCRLF);
  Refused('two characters before an LF in two bytes', 2, 3, rsLF);
  t := TTyRichText.CreateScanned;
  try
    t.AppendScanned(2, 1, rsCRLF);
    t.AppendScanned(4, 2, rsLF);
    t.AppendScanned(1, 1, rsNone);
    t.EndScanned(Bytes(#13#10'中'#10'x'), 0);
    AssertEquals('three paragraphs', 3, t.ParaCount);
    AssertEquals('four characters', 4, t.Length);
    AssertEquals('integrity', '', t.CheckIntegrity);
  finally
    t.Free;
  end;
end;

{ ---- TFakeRichProvider ---- }

constructor TFakeRichProvider.Create(ACount: Integer);
const
  Han: UTF8String = ' 中文';
var
  i: Integer;
begin
  inherited Create;
  Calls := TStringList.Create;
  Texts := nil;
  SetLength(Texts, ACount);
  for i := 0 to ACount - 1 do
    Texts[i] := 'para ' + UTF8String(IntToStr(i)) + Han + UTF8String(Copy('xyzzy', 1, i mod 5));
end;

destructor TFakeRichProvider.Destroy;
begin
  Calls.Free;
  inherited Destroy;
end;

function TFakeRichProvider.DecodeParagraph(ASrcOffset, ASrcBytes, ACharCount: Int64): UTF8String;
var
  idx: Integer;
begin
  idx := (ASrcOffset - LazyBase) div LazyStride;
  Calls.Add(IntToStr(idx));
  Result := Texts[idx];
  if WrongCount then Result := Result + 'extra';
end;

function TFakeRichProvider.CallLog: string;
begin
  Calls.Delimiter := ',';
  Result := Calls.DelimitedText;
end;

{ ---- TTyRichLazyTextTest ---- }

procedure TTyRichLazyTextTest.TearDown;
begin
  FreeAndNil(FText);
  FreeAndNil(FProvider);
  FRuns := nil;
end;

procedure TTyRichLazyTextTest.CollectRun(const ARun: TTyRichByteRun; var AContinue: Boolean);
begin
  SetLength(FRuns, System.Length(FRuns) + 1);
  FRuns[High(FRuns)] := ARun;
end;

procedure TTyRichLazyTextTest.BuildLazy(ACount: Integer);
var
  i: Integer;
  sep: TTyRichSeparator;
begin
  FProvider := TFakeRichProvider.Create(ACount);
  FText := TTyRichText.CreateLazy(FProvider, False);
  for i := 0 to ACount - 1 do
  begin
    if i < ACount - 1 then sep := rsCR else sep := rsNone;
    FText.AppendLazyParagraph(Utf8Chars(FProvider.Texts[i]), i * LazyStride + LazyBase,
      40 + i mod 9, sep);
  end;
  FText.EndLazyLoad;
end;

function TTyRichLazyTextTest.ParaText(AIndex: Integer): UTF8String;
begin
  Result := FText.GetText(FText.ParaStart(AIndex), FText.ParaLength(AIndex));
end;

procedure TTyRichLazyTextTest.TestLazyIndexNeedsNoDecoding;
var
  i: Integer;
  start, total, bytes: Int64;
begin
  BuildLazy(1000);
  start := 0;
  bytes := 0;
  for i := 0 to 999 do
  begin
    AssertEquals(Format('ParaStart(%d)', [i]), start, FText.ParaStart(i));
    AssertEquals(Format('ParaLength(%d)', [i]), Utf8Chars(FProvider.Texts[i]), FText.ParaLength(i));
    AssertEquals(Format('ParaOfPos(%d)', [i]), i, FText.ParaOfPos(start));
    Inc(start, Utf8Chars(FProvider.Texts[i]) + 1);
    Inc(bytes, 40 + i mod 9);
  end;
  total := start - 1;
  AssertEquals('Length', total, FText.Length);
  AssertEquals('ParaCount', 1000, FText.ParaCount);
  AssertEquals('byte count is the source byte count', bytes, FText.ByteCount);
  AssertEquals('separator kind', Ord(rsCR), Ord(FText.ParaSeparator(3)));
  AssertEquals('integrity', '', FText.CheckIntegrity);
  AssertEquals('nothing decoded', '', FProvider.CallLog);
end;

procedure TTyRichLazyTextTest.TestLazyDecodesOnlyWhatIsRead;
var
  a, b: Int64;
  expected: UTF8String;
begin
  BuildLazy(100);
  AssertBytesEqual('paragraph 5', FProvider.Texts[5], ParaText(5));
  AssertEquals('decoded 5', '5', FProvider.CallLog);
  AssertBytesEqual('paragraph 5 again', FProvider.Texts[5], ParaText(5));
  AssertEquals('decoded once', '5', FProvider.CallLog);
  a := FText.ParaStart(7) + 1;
  b := FText.ParaStart(10);
  expected := Copy(FProvider.Texts[7], 2, MaxInt) + #13 + FProvider.Texts[8] + #13 +
    FProvider.Texts[9] + #13;
  AssertBytesEqual('across paragraphs', expected, FText.GetText(a, b - a));
  AssertEquals('decoded 7, 8, 9', '5,7,8,9', FProvider.CallLog);
end;

procedure TTyRichLazyTextTest.TestLazyDecodesOnlyWhatIsEdited;
var
  a, b: Int64;
  count: Integer;
begin
  BuildLazy(100);
  FText.Insert(FText.ParaStart(20) + 2, 'X');
  AssertEquals('editing inside decodes that paragraph', '20', FProvider.CallLog);
  AssertBytesEqual('edited', Copy(FProvider.Texts[20], 1, 2) + 'X' +
    Copy(FProvider.Texts[20], 3, MaxInt), ParaText(20));
  FText.Insert(FText.ParaStart(30), 'Y');
  AssertEquals('typing at its start decodes it', '20,30', FProvider.CallLog);
  FText.Insert(FText.ParaStart(35), 'Z'#13);
  AssertEquals('a whole new paragraph before it leaves it alone', '20,30', FProvider.CallLog);
  count := FText.ParaCount;
  a := FText.ParaStart(40);
  FText.Delete(a, FText.ParaStart(50) - a);
  AssertEquals('deleting whole paragraphs decodes nothing', '20,30', FProvider.CallLog);
  AssertEquals('ten fewer', count - 10, FText.ParaCount);
  a := FText.ParaStart(60) + 1;
  b := FText.ParaStart(62) + 1;
  FText.Delete(a, b - a);
  // paragraphs 60 and 62 are the provider's 69 and 71: one paragraph was inserted before
  // them and ten were deleted
  AssertEquals('a merge decodes the two paragraphs it cuts, not the one between',
    '20,30,69,71', FProvider.CallLog);
  AssertEquals('integrity', '', FText.CheckIntegrity);
end;

procedure TTyRichLazyTextTest.TestLazySnapshotRestoreKeepsPiecesLazy;
var
  a, b: Int64;
  p: TTyRichPieces;
  starts: array of Int64;
  i: Integer;
begin
  BuildLazy(50);
  starts := nil;
  SetLength(starts, 50);
  for i := 0 to 49 do starts[i] := FText.ParaStart(i);
  a := FText.ParaStart(10);
  b := FText.ParaStart(20);
  p := FText.PieceSnapshot(a, b - a);
  FText.Delete(a, b - a);
  AssertEquals('forty left', 40, FText.ParaCount);
  FText.RestorePieces(a, p);
  AssertEquals('fifty again', 50, FText.ParaCount);
  for i := 0 to 49 do
    AssertEquals(Format('ParaStart(%d)', [i]), starts[i], FText.ParaStart(i));
  AssertEquals('nothing decoded', '', FProvider.CallLog);
  FText.ForEachRun(FText.ParaStart(12), FText.ParaLength(12) + 1, @CollectRun);
  AssertEquals('one run', 1, System.Length(FRuns));
  AssertEquals('still lazy', Ord(rpkLazy), Ord(FRuns[0].Kind));
  AssertEquals('its source offset', 12 * LazyStride + LazyBase, FRuns[0].SrcOffset);
  AssertBytesEqual('paragraph 15 reads right', FProvider.Texts[15], ParaText(15));
  AssertEquals('decoded only 15', '15', FProvider.CallLog);
end;

procedure TTyRichLazyTextTest.TestLazyRunsKeepSourceRanges;
var
  i: Integer;
begin
  BuildLazy(20);
  FText.ForEachRun(0, FText.Length, @CollectRun);
  AssertEquals('a run per paragraph', 20, System.Length(FRuns));
  for i := 0 to 19 do
  begin
    AssertEquals('lazy', Ord(rpkLazy), Ord(FRuns[i].Kind));
    AssertEquals('offset', i * LazyStride + LazyBase, FRuns[i].SrcOffset);
    AssertEquals('source bytes', 40 + i mod 9, FRuns[i].ByteCount);
    AssertTrue('no bytes in memory', FRuns[i].Bytes = nil);
  end;
  AssertEquals('walking decodes nothing', '', FProvider.CallLog);
  // read but unchanged: still the original source range, so a writer copies it verbatim
  ParaText(3);
  FRuns := nil;
  FText.ForEachRun(FText.ParaStart(3), FText.ParaLength(3) + 1, @CollectRun);
  AssertEquals('one run', 1, System.Length(FRuns));
  AssertEquals('decoded but unchanged is still lazy', Ord(rpkLazy), Ord(FRuns[0].Kind));
  AssertEquals('its offset', 3 * LazyStride + LazyBase, FRuns[0].SrcOffset);
  FText.Insert(FText.ParaStart(3) + 1, 'Q');
  FRuns := nil;
  FText.ForEachRun(FText.ParaStart(3), FText.ParaLength(3) + 1, @CollectRun);
  for i := 0 to High(FRuns) do
    AssertTrue('edited is no longer lazy', FRuns[i].Kind <> rpkLazy);
  AssertEquals('decoded once', '3', FProvider.CallLog);
end;

procedure TTyRichLazyTextTest.TestLazyCountMismatchRaises;
var
  raised: Boolean;
begin
  BuildLazy(5);
  FProvider.WrongCount := True;
  raised := False;
  try
    ParaText(2);
  except
    on ETyRichText do raised := True;
  end;
  AssertTrue('a provider that breaks the character count is an error', raised);
end;

{ A load that goes on (a file indexed in slices) picks up at the last paragraph: while it
  is open the text cannot be read, and it cannot be opened once that paragraph was edited. }
procedure TTyRichLazyTextTest.TestReopenGoesOnOnlyFromAnUntouchedEnd;
var
  i: Integer;
  sep: TTyRichSeparator;
  raised: Boolean;
begin
  FProvider := TFakeRichProvider.Create(8);
  FText := TTyRichText.CreateLazy(FProvider, False);
  for i := 0 to 4 do
  begin
    if i < 4 then sep := rsCR else sep := rsNone;
    FText.AppendLazyParagraph(Utf8Chars(FProvider.Texts[i]), i * LazyStride + LazyBase, 40, sep);
  end;
  FText.EndLazyLoad;
  FText.ParaData[4] := Pointer(44);
  FText.SetParaHeight(4, 9);
  AssertBytesEqual('readable after the first slice', FProvider.Texts[4], ParaText(4));

  FText.ReopenLazyLoad(rsCR);
  raised := False;
  try
    FText.GetText(0, 1);
  except
    on ETyRichText do raised := True;
  end;
  AssertTrue('the text cannot be read while the load is open', raised);
  raised := False;
  try
    FText.ParaStart(1);
  except
    on ETyRichText do raised := True;
  end;
  AssertTrue('nor looked up', raised);
  FText.AppendLazyParagraph(Utf8Chars(FProvider.Texts[5]), 5 * LazyStride + LazyBase, 40, rsCR);
  FText.AppendLazyParagraph(Utf8Chars(FProvider.Texts[6]), 6 * LazyStride + LazyBase, 40, rsNone);
  FText.EndLazyLoad;
  AssertEquals('seven paragraphs', 7, FText.ParaCount);
  AssertBytesEqual('the old last paragraph', FProvider.Texts[4], ParaText(4));
  AssertEquals('it has its separator now', Ord(rsCR), Ord(FText.ParaSeparator(4)));
  AssertTrue('its data moved with it', FText.ParaData[4] = Pointer(44));
  AssertEquals('and its height', 9, FText.ParaHeight(4));
  AssertTrue('measured', FText.ParaMeasured(4));
  AssertFalse('the new last paragraph is not', FText.ParaMeasured(6));
  AssertBytesEqual('the new last paragraph', FProvider.Texts[6], ParaText(6));
  AssertEquals('integrity', '', FText.CheckIntegrity);

  // the last paragraph edited: the load cannot go on behind it
  FText.Insert(FText.Length, 'z');
  raised := False;
  try
    FText.ReopenLazyLoad(rsCR);
  except
    on ETyRichText do raised := True;
  end;
  AssertTrue('reopening after an edit of the last paragraph must raise', raised);
  AssertBytesEqual('and the text stays readable', FProvider.Texts[6] + 'z', ParaText(6));
end;

procedure TTyRichLazyTextTest.TestLazySourceLookupMissesEditedParagraphs;
begin
  BuildLazy(6);
  AssertEquals('by its source', 3, FText.ParaOfLazySource(3 * LazyStride + LazyBase));
  AssertEquals('no paragraph starts there', -1, FText.ParaOfLazySource(3 * LazyStride + LazyBase + 1));
  AssertEquals('before the first', -1, FText.ParaOfLazySource(0));
  AssertEquals('past the last', -1, FText.ParaOfLazySource(6 * LazyStride + LazyBase));
  ParaText(3);
  AssertEquals('read is not edited', 3, FText.ParaOfLazySource(3 * LazyStride + LazyBase));
  FText.Insert(FText.ParaStart(3) + 1, 'X');
  AssertEquals('an edited paragraph is no longer the file''s', -1,
    FText.ParaOfLazySource(3 * LazyStride + LazyBase));
  FText.Delete(FText.ParaStart(1), FText.ParaStart(2) - FText.ParaStart(1));
  AssertEquals('a deleted paragraph is not found', -1,
    FText.ParaOfLazySource(1 * LazyStride + LazyBase));
  AssertEquals('the ones behind it moved up', 1, FText.ParaOfLazySource(2 * LazyStride + LazyBase));
  AssertEquals('the last one', 4, FText.ParaOfLazySource(5 * LazyStride + LazyBase));
end;

{ ParaOfLazySource finds a paragraph by walking towards its offset, so lazy pieces must stay
  in the order of their offsets. A restore puts pieces back where they were; pieces put
  somewhere else break the order, and the integrity check says so. }
procedure TTyRichLazyTextTest.TestIntegritySeesLazyPiecesOutOfOrder;
var
  p: TTyRichPieces;
  a: Int64;
begin
  BuildLazy(20);
  a := FText.ParaStart(5);
  p := FText.PieceSnapshot(a, FText.ParaStart(8) - a);
  FText.Delete(a, FText.ParaStart(8) - a);
  FText.RestorePieces(a, p);
  AssertEquals('back where they were', '', FText.CheckIntegrity);
  // the same pieces again, in front of paragraph 2
  FText.RestorePieces(FText.ParaStart(2), p);
  AssertEquals('pieces put elsewhere', 'lazy pieces out of source order', FText.CheckIntegrity);
end;

initialization
  RegisterTest(TTyRichTextTest);
  RegisterTest(TTyRichLazyTextTest);
end.
