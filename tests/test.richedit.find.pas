unit test.richedit.find;

{ Finding and replacing in the engine (tyControls.RichEdit.Find): what a match is,
  rule by rule; the options alone and together; text that was never parsed - read by the
  reader as the search reaches it, and found where the file read whole has it (every
  fixture, every word at every place, every byte form the reader takes), the reader keeping
  no more of what was read than its bound; a find while a file loads; a find changes
  nothing; the replace command - one undo
  step however many turns it took, the format of what it replaces, undone the file's bytes.

  Headless, no control. Bounds are counts (paragraphs read, intervals parsed), never times. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, fpcunit, testregistry, tyControls.StrConsts,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.TextIO, tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite,
  tyControls.RichEdit.RowFormat, tyControls.RichEdit.Find;

type
  TTyRichFindTest = class(TTestCase)
  private
    FTotWords: Int64;
    function Positions(ADoc: TTyRichDocument; const ANeedle: UTF8String;
      AOptions: TTyRichFindOptions): string;
    function WholePositions(ADoc: TTyRichDocument; const ANeedle: UTF8String;
      AOptions: TTyRichFindOptions): string;
    function First(ADoc: TTyRichDocument; const ANeedle: UTF8String;
      AOptions: TTyRichFindOptions; AStart: TTyRichPos = 0; AEnd: TTyRichPos = -1): TTyRichPos;
    function Naive(ADoc: TTyRichDocument; const ANeedle: UTF8String;
      AOptions: TTyRichFindOptions): string;
    procedure CheckEveryWord(const AName: string; const ABytes: TBytes; ARtf: Boolean;
      AEncoding: TTyTextEncoding = teAuto);
  published
    procedure TestFindInsideUnparsedRtf;
    // read lazily against read whole: every fixture, and every form of a character the
    // reader takes
    procedure TestEveryWordOfEveryFixture;
    procedure TestEveryFormTheReaderTakes;
    procedure TestTheAdversarialFiles;
    procedure TestEveryByteFormOfEveryWord;
    procedure TestParagraphEndsAndOutsideTheBmp;
    // what a match is
    procedure TestEachOptionAloneAndTogether;
    procedure TestCaseFoldingPerScript;
    procedure TestWholeWordAndChinese;
    procedure TestTheEndsAndParagraphEnds;
    procedure TestAnObjectBreaksAMatch;
    procedure TestAnEscapedByteMatchesOnlyItself;
    procedure TestCellsInTextOrderAndMergedAwayNever;
    procedure TestBackwardFindsTheLastFirst;
    procedure TestARangeHoldsTheWholeMatch;
    // the steps
    procedure TestAStepIsBounded;
    procedure TestAStepIsBoundedInBytes;
    procedure TestAFindWhileLoading;
    procedure TestAFindChangesNothing;
    // replacing
    procedure TestReplaceIsOneStepOfParts;
    procedure TestReplaceKeepsFormatsAndObjects;
    procedure TestReplaceStopsAtTheLimit;
    procedure TestReplaceSkipsANestedRow;
    procedure TestAStoppedReplaceLeavesNothingToRedo;
    procedure TestAReplaceLetGoIsStoppedNotFinished;
    procedure TestReplaceParsesEachIntervalOnce;
    procedure TestReplaceUndoneSavesTheFile;
    procedure TestReplaceKeepsTheTableEdgeRule;
    procedure TestALongNeedleWithAParagraphEndEnds;
    procedure TestARerunGoesOnWhereItStopped;
    procedure TestAParagraphIsFetchedOnce;
    procedure TestOneHugeParagraphKeepsNoListOfItsMatches;
    procedure TestEveryPairOfDestinations;
    procedure TestGeneratedRowsThatEndInsideADestination;
    procedure TestAStopBetweenTouchingWholeWords;
    procedure TestALineOfTouchingMatchesIsReplacedInBoundedParts;
    procedure TestAPartOfEachKindTakesItsShareOfMatches;
  end;

implementation

type
  // the document's protected counts (what a find leaves behind)
  TDocAccess = class(TTyRichDocument)
  end;

const
  MB = 1024 * 1024;

function RepoRoot: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim;
end;

function FixtureDir(const AKind: string): string;
begin
  Result := RepoRoot + 'tests' + PathDelim + 'fixtures' + PathDelim + AKind + PathDelim;
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

{ RTF written with '|' for the backslash. }
function Rtf(const S: RawByteString): RawByteString;
var
  i: Integer;
begin
  Result := S;
  for i := 1 to Length(Result) do
    if Result[i] = '|' then Result[i] := #92;
end;

{ UTF-8 of code points. }
function U(const A: array of Cardinal): UTF8String;
var
  i: Integer;
  c: Cardinal;
begin
  Result := '';
  for i := 0 to High(A) do
  begin
    c := A[i];
    if c < $80 then Result := Result + Chr(c)
    else if c < $800 then
      Result := Result + Chr($C0 or (c shr 6)) + Chr($80 or (c and $3F))
    else if c < $10000 then
      Result := Result + Chr($E0 or (c shr 12)) + Chr($80 or ((c shr 6) and $3F)) +
        Chr($80 or (c and $3F))
    else
      Result := Result + Chr($F0 or (c shr 18)) + Chr($80 or ((c shr 12) and $3F)) +
        Chr($80 or ((c shr 6) and $3F)) + Chr($80 or (c and $3F));
  end;
end;

function LoadRtf(const ABytes: TBytes; AFull: Boolean): TTyRichDocument;
var
  s: TBytesStream;
begin
  Result := TTyRichDocument.Create;
  s := TBytesStream.Create(ABytes);
  try
    try
      if AFull then TyRichLoadRtfFull(Result, s) else TyRichLoadRtf(Result, s);
    except
      Result.Free;
      raise;
    end;
  finally
    s.Free;
  end;
end;

function LoadTxt(const ABytes: TBytes; AEncoding: TTyTextEncoding = teAuto): TTyRichDocument;
var
  s: TBytesStream;
begin
  Result := TTyRichDocument.Create;
  s := TBytesStream.Create(ABytes);
  try
    TyRichLoadText(Result, s, AEncoding, 936);
  finally
    s.Free;
  end;
end;

function TextDoc(const S: RawByteString): TTyRichDocument;
begin
  Result := LoadTxt(BytesOf(S), teUtf8);
end;

function SaveRtf(ADoc: TTyRichDocument): TBytes;
var
  m: TBytesStream;
begin
  m := TBytesStream.Create;
  try
    TyRichSaveRtf(ADoc, m);
    Result := Copy(m.Bytes, 0, m.Size);
  finally
    m.Free;
  end;
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

function Join(const A: array of Int64): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(A) do
  begin
    if i > 0 then Result := Result + ' ';
    Result := Result + IntToStr(A[i]);
  end;
end;

{ The matches a finder kept. }
function Joined(AFinder: TTyRichFinder): string;
var
  a: array of Int64;
  i: Integer;
begin
  a := nil;
  SetLength(a, AFinder.MatchCount);
  for i := 0 to AFinder.MatchCount - 1 do a[i] := AFinder.Match(i);
  Result := Join(a);
end;

{ The paragraphs of a cell merged into the one before it (as the layout reads a row). }
function HiddenPara(ADoc: TTyRichDocument; AIndex: Integer): Boolean;
var
  cell: TTyRichCell;
  d: TTyRowDisplay;
begin
  Result := False;
  cell := ADoc.CellAt(AIndex);
  if (cell = nil) or (cell.Index = 0) or (cell.Row.RawFormat = '') then Exit;
  d := TyRtfRowDisplay(cell.Row.RawFormat);
  Result := (cell.Index < Length(d.Cells)) and (d.Cells[cell.Index].HMerge = rcmContinue);
end;

{ ---- the reference: the whole text, compared at every place ---- }

function TTyRichFindTest.Naive(ADoc: TTyRichDocument; const ANeedle: UTF8String;
  AOptions: TTyRichFindOptions): string;
var
  text, needle: TTyRichCodeArray;
  hidden: array of Boolean;
  i, k, j, m: Integer;
  ps, pl: TTyRichPos;
  ok: Boolean;
  a, b: Cardinal;
  found: array of Int64;
begin
  text := TyRichFindCodes(ADoc.Text.GetText(0, ADoc.Text.Length));
  needle := TyRichFindCodes(ANeedle);
  SetLength(hidden, Length(text));
  ADoc.BeginRead;
  try
    for i := 0 to ADoc.Text.ParaCount - 1 do
      if HiddenPara(ADoc, i) then
      begin
        ps := ADoc.Text.ParaStart(i);
        pl := ADoc.Text.ParaLength(i);
        for k := ps to ps + pl do
          if k < Length(hidden) then hidden[k] := True;
      end;
  finally
    ADoc.EndRead;
  end;
  m := Length(needle);
  found := nil;
  i := 0;
  while (m > 0) and (i + m <= Length(text)) do
  begin
    ok := True;
    for j := 0 to m - 1 do
    begin
      a := text[i + j];
      b := needle[j];
      if (a = $FFFC) or hidden[i + j] then ok := False
      else if rfoMatchCase in AOptions then ok := a = b
      else ok := TyRichFoldChar(a) = TyRichFoldChar(b);
      if not ok then Break;
    end;
    if ok and (rfoWholeWord in AOptions) then
    begin
      if (i > 0) and (TyRichWordClass(text[i - 1]) = 1) and (TyRichWordClass(needle[0]) = 1) then
        ok := False;
      if (i + m < Length(text)) and (TyRichWordClass(text[i + m]) = 1) and
        (TyRichWordClass(needle[m - 1]) = 1) then
        ok := False;
    end;
    if ok then
    begin
      SetLength(found, Length(found) + 1);
      found[High(found)] := i;
      Inc(i, m);
    end
    else
      Inc(i);
  end;
  Result := Join(found);
end;

function TTyRichFindTest.Positions(ADoc: TTyRichDocument; const ANeedle: UTF8String;
  AOptions: TTyRichFindOptions): string;
var
  f: TTyRichFinder;
begin
  f := TTyRichFinder.Create(ADoc, ANeedle, AOptions);
  try
    f.Collect := True;
    AssertTrue('collected to the end', f.Run = rfrNotFound);
    Result := Joined(f);
  finally
    f.Free;
  end;
end;

{ The places in a document read whole, with nothing lazy in it: every paragraph was set by
  the one parse from the file's first byte to its last, and the finder has none parsed on
  demand. What the lazy read is held against. }
function TTyRichFindTest.WholePositions(ADoc: TTyRichDocument; const ANeedle: UTF8String;
  AOptions: TTyRichFindOptions): string;
var
  f: TTyRichFinder;
  load: TTyRtfLoad;
  parsed: Integer;
begin
  load := TyRichRtfLoadOf(ADoc);
  AssertTrue('the document was read whole', (load <> nil) and load.Whole);
  parsed := load.ParseCount;
  f := TTyRichFinder.Create(ADoc, ANeedle, AOptions);
  try
    f.Collect := True;
    AssertTrue('collected to the end', f.Run = rfrNotFound);
    AssertEquals('no paragraph was parsed for it', parsed, load.ParseCount);
    Result := Joined(f);
  finally
    f.Free;
  end;
end;

function TTyRichFindTest.First(ADoc: TTyRichDocument; const ANeedle: UTF8String;
  AOptions: TTyRichFindOptions; AStart: TTyRichPos; AEnd: TTyRichPos): TTyRichPos;
var
  f: TTyRichFinder;
begin
  f := TTyRichFinder.Create(ADoc, ANeedle, AOptions, AStart, AEnd);
  try
    if f.Run = rfrFound then Result := f.MatchPos else Result := -1;
  finally
    f.Free;
  end;
end;

{ Every word of the document (a run of word characters, as the caret's rule has them) at
  every place it is: the finder gives what the reference gives - in the file read whole and
  in the file read lazily. }
procedure TTyRichFindTest.CheckEveryWord(const AName: string; const ABytes: TBytes;
  ARtf: Boolean; AEncoding: TTyTextEncoding);
var
  full, lazy: TTyRichDocument;
  text: TTyRichCodeArray;
  words: TStringList;
  i, j: Integer;
  w: UTF8String;
  want: string;
  k, g, e: Int64;
  phrases: Integer;
begin
  phrases := 0;
  if ARtf then full := LoadRtf(ABytes, True) else full := LoadTxt(ABytes, AEncoding);
  words := TStringList.Create;
  try
    words.Sorted := True;
    words.Duplicates := dupIgnore;
    text := TyRichFindCodes(full.Text.GetText(0, full.Text.Length));
    i := 0;
    while i < Length(text) do
    begin
      if TyRichWordClass(text[i]) <> 1 then
      begin
        Inc(i);
        Continue;
      end;
      j := i;
      while (j < Length(text)) and (TyRichWordClass(text[j]) = 1) and
        (text[j] < TyRichFindRawByte) do
        Inc(j);
      if j > i then
      begin
        w := '';
        for k := i to j - 1 do w := w + U([text[k]]);
        words.Add(w);
        { and a phrase: the word, the spaces or punctuation after it, the next word - a
          needle with characters that are no word }
        g := j;
        while (g < Length(text)) and (g - j < 3) and (TyRichWordClass(text[g]) = 0) and
          (text[g] <> TyRichFindParaEnd) do
          Inc(g);
        if (g > j) and (g < Length(text)) and (TyRichWordClass(text[g]) = 1) and
          (text[g] < TyRichFindRawByte) and (phrases < 25) then
        begin
          e := g;
          while (e < Length(text)) and (TyRichWordClass(text[e]) = 1) and
            (text[e] < TyRichFindRawByte) do
            Inc(e);
          for k := j to e - 1 do w := w + U([text[k]]);
          if words.IndexOf(w) < 0 then Inc(phrases);
          words.Add(w);
        end;
      end;
      if j > i then i := j else Inc(i);
    end;
    for i := 0 to words.Count - 1 do
    begin
      w := words[i];
      want := Naive(full, w, [rfoMatchCase]);
      AssertTrue(AName + ': the reference finds ' + w, want <> '');
      if ARtf then
        AssertEquals(AName + ': read whole, ' + w, want, WholePositions(full, w, [rfoMatchCase]))
      else
        AssertEquals(AName + ': read whole, ' + w, want, Positions(full, w, [rfoMatchCase]));
      if ARtf then
      begin
        lazy := LoadRtf(ABytes, False);
        try
          AssertEquals(AName + ': lazily, ' + w, want, Positions(lazy, w, [rfoMatchCase]));
        finally
          lazy.Free;
        end;
        // any case
        lazy := LoadRtf(ABytes, False);
        try
          AssertEquals(AName + ': lazily, any case, ' + w, Naive(full, w, []),
            Positions(lazy, w, []));
        finally
          lazy.Free;
        end;
      end
      else
        AssertEquals(AName + ': any case, ' + w, Naive(full, w, []), Positions(full, w, []));
      Inc(FTotWords);
    end;
  finally
    words.Free;
    full.Free;
  end;
end;

{ A 5 MB RTF, opened and searched at once for a word that is only in its last paragraph (and
  split there by formatting groups): found. Every paragraph on the way was read by the
  reader - each interval of the file parsed, none twice - and of what was read no more
  stays than the reader keeps of any read: its bound of intervals, and no paragraph's text
  outside them. }
procedure TTyRichFindTest.TestFindInsideUnparsedRtf;
const
  Vocab: array[0..9] of string = ('alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot',
    'golf', 'hotel', 'india', 'juliet');
var
  m: TMemoryStream;
  s: RawByteString;
  doc: TTyRichDocument;
  load: TTyRtfLoad;
  f: TTyRichFinder;
  n, para, k: Integer;
  parsed0: Integer;
  want: TTyRichPos;
  src, bytes: Int64;
  seed: Cardinal;
begin
  m := TMemoryStream.Create;
  try
    s := Rtf('{|rtf1|ansi|ansicpg936|deff0{|fonttbl{|f0|fnil|fcharset134 SimSun;}{|f1|fswiss Arial;}}' +
      '|viewkind4|uc1|pard|f0|fs20 ');
    m.WriteBuffer(s[1], Length(s));
    seed := 7;
    n := 0;
    while m.Size < 5 * MB do
    begin
      s := '';
      for k := 0 to 11 do
      begin
        {$PUSH}{$Q-}{$R-}
        seed := seed * 1103515245 + 12345;
        {$POP}
        s := s + Vocab[(seed shr 16) mod 10] + ' ';
      end;
      s := Rtf('{|f1 ') + s + Rtf('}|u20013?|u25991?{|b ') + IntToStr(n) + Rtf('}|par') + #13#10;
      m.WriteBuffer(s[1], Length(s));
      Inc(n);
    end;
    s := Rtf('{|f1 the end: {|b Quix}{|i ot}ic}|par') + #13#10 + '}';
    m.WriteBuffer(s[1], Length(s));
    doc := TTyRichDocument.Create;
    try
      m.Position := 0;
      TyRichLoadRtf(doc, m);
      load := TyRichRtfLoadOf(doc);
      AssertTrue('more than 64 intervals', load.IntervalCount > 64);
      para := doc.Text.ParaCount - 1;
      if doc.Text.ParaLength(para) = 0 then Dec(para);
      want := doc.Text.ParaStart(para) + 9;
      parsed0 := load.ParseCount;
      f := TTyRichFinder.Create(doc, 'quixotic', []);
      try
        AssertTrue('found', f.Run = rfrFound);
        AssertEquals('at the end', want, f.MatchPos);
        AssertEquals('every paragraph was read', Int64(para + 1), f.ParasRead);
        AssertTrue(Format('the file''s bytes counted (%d of %d)', [f.FileBytes, m.Size]),
          (f.FileBytes > m.Size - 4096) and (f.FileBytes <= m.Size));
      finally
        f.Free;
      end;
      AssertTrue(Format('every interval was parsed for it (%d of %d)',
        [load.ParseCount - parsed0, load.IntervalCount]),
        load.ParseCount - parsed0 >= load.IntervalCount - 1);
      AssertTrue(Format('none twice (%d of %d)', [load.ParseCount - parsed0, load.IntervalCount]),
        load.ParseCount - parsed0 <= load.IntervalCount);
      // (a parse may bring a group of intervals in before the oldest go: twice the bound)
      AssertTrue(Format('the reader kept its bound of them (%d)', [load.ResidentIntervals]),
        load.ResidentIntervals <= 2 * load.MaxResidentIntervals + 1);
      AssertTrue(Format('and of the text only theirs (%d bytes)', [doc.Text.DecodedBytes]),
        doc.Text.DecodedBytes <= Int64(2 * load.MaxResidentIntervals + 1) * 128 * 1024);
      AssertTrue('a paragraph far from the hit is its bytes in the file again',
        doc.Text.ParaLazySource(para div 2, src, bytes) and not doc.Text.IsDecoded(src));
    finally
      doc.Free;
    end;
  finally
    m.Free;
  end;
end;

{ ---- read lazily against read whole ---- }

procedure TTyRichFindTest.TestEveryWordOfEveryFixture;
var
  sr: TSearchRec;
  names: TStringList;
  i: Integer;
begin
  names := TStringList.Create;
  try
    names.Sorted := True;
    if FindFirst(FixtureDir('rtf') + '*.rtf', faAnyFile, sr) = 0 then
    begin
      repeat
        names.Add(sr.Name);
      until FindNext(sr) <> 0;
      FindClose(sr);
    end;
    AssertTrue('the RTF fixtures are there', names.Count >= 20);
    for i := 0 to names.Count - 1 do
      CheckEveryWord(names[i], ReadFileBytes(FixtureDir('rtf') + names[i]), True);
    names.Clear;
    if FindFirst(FixtureDir('txt') + '*.txt', faAnyFile, sr) = 0 then
    begin
      repeat
        names.Add(sr.Name);
      until FindNext(sr) <> 0;
      FindClose(sr);
    end;
    AssertTrue('the text fixtures are there', names.Count >= 8);
    for i := 0 to names.Count - 1 do
      CheckEveryWord(names[i], ReadFileBytes(FixtureDir('txt') + names[i]), False);
    // the bytes no text: as they are (a forced UTF-8)
    CheckEveryWord('utf8-badbytes forced', ReadFileBytes(FixtureDir('txt') + 'utf8-badbytes.txt'),
      False, teUtf8);
    AssertTrue(Format('the words and phrases searched (%d)', [FTotWords]), FTotWords > 500);
  finally
    names.Free;
  end;
end;

{ Every way the reader turns bytes into a character of the needle, one paragraph each: the
  find in the file read lazily agrees with the whole parse. }
procedure TTyRichFindTest.TestEveryFormTheReaderTakes;
var
  body: RawByteString;
  bytes: TBytes;
  full, lazy: TTyRichDocument;
  needles: array of UTF8String;
  i: Integer;
  want: string;
begin
  body :=
    // \'xx pairs in GBK, a raw pair, a pair split by a group and a control word
    Rtf('|f0 |''d6|''d0|''ce|''c4 x|par ') +
    Rtf('|f0 ') + #$D6#$D0#$CE#$C4 + Rtf(' y|par ') +
    Rtf('|f0 |''d6{|b}|''d0|i |''ce|''c4 z|par ') +
    // \uN with a fallback skipped under \uc1, \uc2, \uc0, and across a group end
    Rtf('|uc1|u20013?|u25991? a|par ') +
    Rtf('{|uc2|u20013|''d6|''d0|u25991|''ce|''c4} b|par ') +
    Rtf('{|uc0|u20013|u25991} c|par ') +
    Rtf('{|uc1|u20013}?|u25991? d|par ') +
    // ASCII as \'xx, a word split by formatting groups and a bookmark
    Rtf('|''48|''65llo w{|b or}{|*|bkmkstart q}ld|par ') +
    // control words that are characters, and the control symbols
    Rtf('dash|emdash here|tab tab|~nb|_hy |{br|}ace|par ') +
    // \upr: the ANSI half is not read, the Unicode half is
    Rtf('{|upr{ansi half}{|*|ud{unicode half}}} after|par ') +
    // a Symbol charset font: its bytes are U+F000 + b
    Rtf('{|f2 abc} symbol|par ') +
    // a lone lead byte reads as a question mark
    Rtf('|f0 lone|''d6 lead|par ') +
    Rtf('done');
  bytes := BytesOf(Rtf('{|rtf1|ansi|ansicpg936|deff0{|fonttbl{|f0|fnil|fcharset134 SimSun;}' +
    '{|f1|fswiss Arial;}{|f2|ftech|fcharset2 Symbol;}}|pard ') + body + '}');
  // U+4E2D U+6587 are GBK D6 D0, CE C4
  needles := nil;
  SetLength(needles, 16);
  needles[0] := U([$4E2D, $6587]);
  needles[1] := U([$4E2D, $6587, 32, Ord('z')]);
  needles[2] := U([$6587, 32, Ord('b')]);
  // the question mark after the group is text: the group's end ended the \uc1 skip
  needles[3] := U([$4E2D, Ord('?'), $6587, 32, Ord('d')]);
  // (the bookmark is an object: 'Hello world' is not text)
  needles[4] := 'Hello wor';
  needles[5] := U([Ord('h'), $2014, Ord('h')]);
  needles[6] := U([Ord('e'), 9, Ord('t')]);
  needles[7] := U([$A0, Ord('n'), Ord('b'), $2011, Ord('h')]);
  needles[8] := U([Ord('{'), Ord('b'), Ord('r'), Ord('}')]);
  needles[9] := 'unicode half after';
  needles[10] := U([$F061, $F062]);
  needles[11] := 'lone? lead';
  needles[12] := U([$4E2D, $6587, 32, Ord('c')]);
  needles[13] := 'HELLO';
  needles[14] := U([$4E2D, $6587, 32, Ord('y')]);
  needles[15] := U([$4E2D, $6587, 32, Ord('x')]);
  full := LoadRtf(bytes, True);
  try
    for i := 0 to High(needles) do
    begin
      want := Naive(full, needles[i], []);
      AssertTrue(Format('needle %d is in the text', [i]), want <> '');
      lazy := LoadRtf(bytes, False);
      try
        AssertEquals(Format('needle %d lazily', [i]), want, Positions(lazy, needles[i], []));
      finally
        lazy.Free;
      end;
    end;
    // and what is not in the text is not found
    lazy := LoadRtf(bytes, False);
    try
      AssertEquals('ansi half: not text', '', Positions(lazy, 'ansi half', []));
      AssertEquals('the bookmark''s name: not text', '', Positions(lazy, 'orqld', []));
    finally
      lazy.Free;
    end;
    // a font whose code page is not the file's: \ansicpg1252, the text in a GBK font
    full.Free;
    full := nil;
    bytes := BytesOf(Rtf('{|rtf1|ansi|ansicpg1252|deff0{|fonttbl{|f0|fswiss Arial;}' +
      '{|f1|fnil|fcharset134 SimSun;}}|pard |f1 |''d6|''d0|''ce|''c4|f0  font|par}'));
    full := LoadRtf(bytes, True);
    AssertEquals('the GBK font''s text', '0', Naive(full, U([$4E2D, $6587]), []));
    lazy := LoadRtf(bytes, False);
    try
      AssertEquals('found through the font''s code page', '0',
        Positions(lazy, U([$4E2D, $6587]), []));
    finally
      lazy.Free;
    end;
  finally
    full.Free;
  end;
end;

{ The adversarial files (tests/fixtures/rtf/find, its cases.txt: the file, the needle as hex of
  its UTF-8, m for match case and w for whole word, the places it is found - "-" none): read
  whole (nothing lazy) and read lazily, the finder gives those places. Hex control bytes, a
  \u without a number, a font table and an \ansicpg
  given again in the body, a surrogate pair split by a group the reader passes over, a picture
  below the reader's group stack, a destination read in part and a paragraph that begins
  inside one (after a paragraph's end there, and after a row's end given to the last cell),
  a lead byte left waiting in a field's result (its ? comes out before the field's object,
  whatever follows the result inside the field) are among them: forms a search that judged
  a paragraph by its bytes once lost a hit in. The places pin what the reader makes of
  each, read whole and read lazily alike. }
procedure TTyRichFindTest.TestTheAdversarialFiles;
var
  lines: TStringList;
  parts: TStringArray;
  i, k, n: Integer;
  bytes: TBytes;
  full, lazy: TTyRichDocument;
  needle: UTF8String;
  opts: TTyRichFindOptions;
  want: string;
begin
  lines := TStringList.Create;
  try
    lines.LoadFromFile(FixtureDir('rtf') + 'find' + PathDelim + 'cases.txt');
    n := 0;
    for i := 0 to lines.Count - 1 do
    begin
      if Trim(lines[i]) = '' then Continue;
      parts := lines[i].Split([#9]);
      AssertEquals('a case line has five columns', 5, Length(parts));
      needle := '';
      SetLength(needle, Length(parts[1]) div 2);
      for k := 1 to Length(needle) do
        needle[k] := Chr(StrToInt('$' + Copy(parts[1], 2 * k - 1, 2)));
      opts := [];
      if Pos('m', parts[2]) > 0 then Include(opts, rfoMatchCase);
      if Pos('w', parts[2]) > 0 then Include(opts, rfoWholeWord);
      want := parts[3];
      if want = '-' then want := '';
      bytes := ReadFileBytes(FixtureDir('rtf') + 'find' + PathDelim + parts[0]);
      full := LoadRtf(bytes, True);
      try
        AssertEquals(parts[0] + ' ' + parts[1] + ': read whole', want,
          WholePositions(full, needle, opts));
      finally
        full.Free;
      end;
      lazy := LoadRtf(bytes, False);
      try
        AssertEquals(parts[0] + ' ' + parts[1] + ': lazily', want,
          Positions(lazy, needle, opts));
      finally
        lazy.Free;
      end;
      Inc(n);
    end;
    AssertEquals('the cases', 129, n);
    { And two of our own: a code page that only a later font table or an ansicpg word brings, used by a
      paragraph whose bytes do not hold that table or word. }
    bytes := BytesOf(Rtf('{|rtf1|ansi|ansicpg1252|deff0{|fonttbl{|f0|fswiss Arial;}}|pard one' +
      '{|fonttbl{|f5|fnil|fcharset134 SimSun;}}|par |f5 |''d6|''d0|par}'));
    lazy := LoadRtf(bytes, False);
    try
      AssertEquals('a font of a later table', '4', Positions(lazy, U([$4E2D]), []));
    finally
      lazy.Free;
    end;
    bytes := BytesOf(Rtf('{|rtf1|ansi|ansicpg1252|pard one|ansicpg1251|par |''cf|''f0|''e8|par}'));
    lazy := LoadRtf(bytes, False);
    try
      AssertEquals('a later ansicpg', '4', Positions(lazy, U([$41F, $440, $438]), [rfoMatchCase]));
    finally
      lazy.Free;
    end;
  finally
    lines.Free;
  end;
end;

{ The words of ADoc's text (runs of word characters), each once. }
procedure CollectWords(ADoc: TTyRichDocument; AWords: TStringList);
var
  text: TTyRichCodeArray;
  i, j, k: Integer;
  w: UTF8String;
begin
  AWords.Sorted := True;
  AWords.Duplicates := dupIgnore;
  text := TyRichFindCodes(ADoc.Text.GetText(0, ADoc.Text.Length));
  i := 0;
  while i < Length(text) do
  begin
    if TyRichWordClass(text[i]) <> 1 then
    begin
      Inc(i);
      Continue;
    end;
    j := i;
    while (j < Length(text)) and (TyRichWordClass(text[j]) = 1) and (text[j] < TyRichFindRawByte) do
      Inc(j);
    if j > i then
    begin
      w := '';
      for k := i to j - 1 do w := w + U([text[k]]);
      AWords.Add(w);
      i := j;
    end
    else
      Inc(i);
  end;
end;

{ By a generator: every word of every RTF fixture, written in each byte form the reader
  takes - \uN with a fallback of none, one and two bytes, \'xx and raw bytes in each code page
  of the fixture that has its characters, a control word and a group between any two of its
  letters - in a paragraph after another: the find in the file read lazily finds it there
  (and the whole parse reads it so). }
procedure TTyRichFindTest.TestEveryByteFormOfEveryWord;
var
  sr: TSearchRec;
  names, words: TStringList;
  f, i, k, cp, forms: Integer;
  bytes: TBytes;
  doc, lazy: TTyRichDocument;
  codes: TTyRichCodeArray;
  cps: array of Integer;
  table: Pointer;
  body, s: RawByteString;
  known: Boolean;
  v: Integer;

  function UWord(ACode: Cardinal; const AFallback: RawByteString): RawByteString;
  var
    hi, lo: Cardinal;
  begin
    if ACode > $FFFF then
    begin
      hi := $D800 + ((ACode - $10000) shr 10);
      lo := $DC00 + ((ACode - $10000) and $3FF);
      Result := UWord(hi, AFallback) + UWord(lo, AFallback);
      Exit;
    end;
    if ACode > $7FFF then Result := Rtf('|u') + IntToStr(Integer(ACode) - 65536)
    else Result := Rtf('|u') + IntToStr(ACode);
    Result := Result + AFallback;
  end;

  // the word's bytes in the code page of ATable (empty: a character it has not)
  function InCodePage(ARaw: Boolean): RawByteString;
  var
    j, b: Integer;

    function OneByte(AByte: Integer): RawByteString;
    begin
      // raw, but never a byte the lexer takes for markup, nor one above 7F written as is
      // where a control word right before it would swallow it
      if ARaw and (AByte >= $20) and not (AByte in [$5C, $7B, $7D]) then Result := Chr(AByte)
      else Result := Rtf('|''') + LowerCase(IntToHex(AByte, 2));
    end;

  begin
    Result := '';
    for j := 0 to High(codes) do
    begin
      b := TyRichCodePageBytes(table, codes[j]);
      if b = 0 then Exit('');
      if b > $FF then Result := Result + OneByte(b shr 8) + OneByte(b and $FF)
      else Result := Result + OneByte(b);
    end;
  end;

  procedure Check(const AForm: string; ACodePage: Integer; const ABody: RawByteString);
  var
    file_: RawByteString;
    want, got: string;
  begin
    file_ := Rtf('{|rtf1|ansi|ansicpg') + IntToStr(ACodePage) +
      Rtf('|deff0{|fonttbl{|f0|fnil Some Font;}}|pard filler|par ') + ABody + Rtf('|par}');
    doc := LoadRtf(BytesOf(file_), True);
    try
      want := Positions(doc, words[i], [rfoMatchCase]);
    finally
      doc.Free;
    end;
    AssertEquals(Format('%s: %s, %s is read', [names[f], words[i], AForm]), '7', want);
    lazy := LoadRtf(BytesOf(file_), False);
    try
      got := Positions(lazy, words[i], [rfoMatchCase]);
    finally
      lazy.Free;
    end;
    AssertEquals(Format('%s: %s, %s is found', [names[f], words[i], AForm]), want, got);
    Inc(forms);
  end;

begin
  names := TStringList.Create;
  words := TStringList.Create;
  forms := 0;
  try
    names.Sorted := True;
    if FindFirst(FixtureDir('rtf') + '*.rtf', faAnyFile, sr) = 0 then
    begin
      repeat
        names.Add(sr.Name);
      until FindNext(sr) <> 0;
      FindClose(sr);
    end;
    AssertTrue('the RTF fixtures are there', names.Count >= 20);
    for f := 0 to names.Count - 1 do
    begin
      bytes := ReadFileBytes(FixtureDir('rtf') + names[f]);
      words.Clear;
      // the fixture's code pages: 1252, the file's own and each of its fonts'
      lazy := LoadRtf(bytes, False);
      try
        cps := nil;
        for k := -2 to TyRichRtfLoadOf(lazy).Scan.FontCount - 1 do
        begin
          if k = -2 then cp := 1252
          else if k = -1 then cp := TyRichRtfLoadOf(lazy).Scan.AnsiCodePage
          else cp := TyRichRtfLoadOf(lazy).Scan.Font(k).CodePage;
          known := False;
          for v := 0 to High(cps) do
            if cps[v] = cp then known := True;
          if not known and (cp > 0) and (TyRichCodePageTable(cp) <> nil) then
          begin
            SetLength(cps, Length(cps) + 1);
            cps[High(cps)] := cp;
          end;
        end;
      finally
        lazy.Free;
      end;
      doc := LoadRtf(bytes, True);
      try
        CollectWords(doc, words);
      finally
        doc.Free;
      end;
      for i := 0 to words.Count - 1 do
      begin
        codes := TyRichFindCodes(words[i]);
        // \uN, its fallback none, one byte, two
        body := '';
        for k := 0 to High(codes) do body := body + UWord(codes[k], ' ');
        Check('\u, \uc0', 1252, Rtf('{|uc0 ') + body + '}');
        body := '';
        for k := 0 to High(codes) do body := body + UWord(codes[k], '?');
        Check('\u, \uc1', 1252, Rtf('{|uc1 ') + body + '}');
        body := '';
        for k := 0 to High(codes) do body := body + UWord(codes[k], Rtf('|''3f|''3f'));
        Check('\u, \uc2', 1252, Rtf('{|uc2 ') + body + '}');
        // \'xx and raw bytes in each code page that has the word's characters
        for k := 0 to High(cps) do
        begin
          table := TyRichCodePageTable(cps[k]);
          s := InCodePage(False);
          if s = '' then Continue;
          Check(Format('\''xx in %d', [cps[k]]), cps[k], s);
          Check(Format('raw bytes in %d', [cps[k]]), cps[k], InCodePage(True));
        end;
        // a control word, and a group, between any two characters
        body := '';
        for k := 0 to High(codes) do
        begin
          if k > 0 then body := body + Rtf('|i ');
          body := body + UWord(codes[k], '');
        end;
        Check('a control word between', 1252, Rtf('{|uc0 ') + body + '}');
        body := '';
        for k := 0 to High(codes) do
        begin
          if k > 0 then body := body + Rtf('{|b}');
          body := body + UWord(codes[k], '');
        end;
        Check('a group between', 1252, Rtf('{|uc0 ') + body + '}');
      end;
    end;
    AssertTrue(Format('every form of every word (%d)', [forms]), forms > 1000);
  finally
    words.Free;
    names.Free;
  end;
end;

{ Through the same comparison - a character outside the BMP (only \uN pairs make one), a
  needle that is only paragraph ends (the lengths in the paragraph tree say where; nothing
  is read but what a table holds), one of text and paragraph ends (the lengths of the
  paragraphs between say where it may be: only those few are read), and U+FFFD. }
procedure TTyRichFindTest.TestParagraphEndsAndOutsideTheBmp;
var
  s: RawByteString;
  bytes: TBytes;
  i: Integer;
  full, lazy: TTyRichDocument;
  load: TTyRtfLoad;
  f: TTyRichFinder;
  needles: array[0..5] of UTF8String;
  want: string;
  parsed: Integer;
begin
  s := Rtf('{|rtf1|ansi|ansicpg1252|deff0{|fonttbl{|f0|fswiss Arial;}}|pard ');
  for i := 0 to 2999 do
  begin
    s := s + Rtf('line of some words ') + IntToStr(i) + Rtf('|par ');
    if i = 1500 then s := s + Rtf('|par the |u-10179?|u-8704? face|par ');
    if i = 2500 then s := s + Rtf('|par |par end of it|par ');
  end;
  s := s + Rtf('last|par}');
  bytes := BytesOf(s);
  needles[0] := U([$1F600]);
  needles[1] := U([32, $1F600, 32, Ord('f')]);
  needles[2] := #10#10;
  needles[3] := #10#10#10;
  needles[4] := '2500'#10#10#10'end';
  needles[5] := U([$FFFD]);
  full := LoadRtf(bytes, True);
  try
    for i := 0 to High(needles) do
    begin
      want := Naive(full, needles[i], []);
      AssertEquals(Format('needle %d: read whole', [i]), want, WholePositions(full, needles[i], []));
      lazy := LoadRtf(bytes, False);
      try
        load := TyRichRtfLoadOf(lazy);
        parsed := load.ParseCount;
        f := TTyRichFinder.Create(lazy, needles[i], []);
        try
          f.Collect := True;
          f.Run;
          AssertEquals(Format('needle %d: the same places', [i]), want, Joined(f));
          if i in [2, 3, 4] then
          begin
            AssertTrue(Format('needle %d: few paragraphs read (%d)', [i, f.ParasRead]),
              f.ParasRead <= 4);
            AssertTrue(Format('needle %d: few intervals parsed (%d)', [i, load.ParseCount - parsed]),
              load.ParseCount - parsed <= 2);
            // paragraph ends alone: the lengths say it all, outside a table nothing is read
            if i in [2, 3] then
            begin
              AssertEquals(Format('needle %d: no paragraph read', [i]), 0, f.ParasRead);
              AssertEquals(Format('needle %d: no interval parsed', [i]), 0, load.ParseCount - parsed);
            end;
          end
          else
            AssertTrue(Format('needle %d: every paragraph read (%d)', [i, f.ParasRead]),
              f.ParasRead >= 3000);
        finally
          f.Free;
        end;
      finally
        lazy.Free;
      end;
    end;
  finally
    full.Free;
  end;
end;

{ ---- what a match is ---- }

procedure TTyRichFindTest.TestEachOptionAloneAndTogether;
var
  doc: TTyRichDocument;
begin
  doc := TextDoc('Cat cat CAT concat cat.' + #10 + 'cat');
  try
    AssertEquals('none', '0 4 8 15 19 24', Positions(doc, 'cat', []));
    AssertEquals('match case', '4 15 19 24', Positions(doc, 'cat', [rfoMatchCase]));
    AssertEquals('whole word', '0 4 8 19 24', Positions(doc, 'cat', [rfoWholeWord]));
    AssertEquals('whole word: not the start of a longer one', '', Positions(doc, 'ca', [rfoWholeWord]));
    AssertEquals('both', '4 19 24', Positions(doc, 'cat', [rfoMatchCase, rfoWholeWord]));
    AssertEquals('backward', 24, First(doc, 'cat', [rfoBackward]));
    AssertEquals('backward, match case, whole word, before 24', 19,
      First(doc, 'cat', [rfoBackward, rfoMatchCase, rfoWholeWord], 0, 24));
    AssertEquals('backward, whole word, before 19', 8,
      First(doc, 'cat', [rfoBackward, rfoWholeWord], 0, 19));
    AssertEquals('forward from 5', 8, First(doc, 'cat', [], 5));
    AssertEquals('forward from 5, match case', 15, First(doc, 'cat', [rfoMatchCase], 5));
    AssertEquals('not there', -1, First(doc, 'dog', []));
    AssertEquals('empty', -1, First(doc, '', []));
  finally
    doc.Free;
  end;
  // overlapping: leftmost, then after it
  doc := TextDoc('aaaaa');
  try
    AssertEquals('non-overlapping', '0 2', Positions(doc, 'aa', []));
    AssertEquals('backward takes the last', 3, First(doc, 'aa', [rfoBackward]));
  finally
    doc.Free;
  end;
end;

procedure TTyRichFindTest.TestCaseFoldingPerScript;
var
  doc: TTyRichDocument;
begin
  // Latin with diacritics, Greek (with a final sigma), Cyrillic, full-width Latin
  doc := TextDoc(U([$C4, $F6, $DF, 32, $3A3, $39F, $3A6, $399, $391, 32, $3C3, $3BF, $3C6, $3B9,
    $3C2, 32, $416, $401, 32, $FF21, $FF22, 32, $130]));
  try
    AssertEquals('Latin', '0', Positions(doc, U([$E4, $D6, $DF]), []));
    AssertEquals('Latin, case', '', Positions(doc, U([$E4, $D6, $DF]), [rfoMatchCase]));
    AssertEquals('Greek both ways', '4 10', Positions(doc, U([$3C3, $3BF, $3C6, $3B9]), []));
    AssertEquals('Greek, case', '10', Positions(doc, U([$3C3, $3BF, $3C6, $3B9]), [rfoMatchCase]));
    AssertEquals('sigma finds the final one too', '4 10 14', Positions(doc, U([$3C3]), []));
    AssertEquals('the final one finds sigma', '4 10 14', Positions(doc, U([$3C2]), []));
    AssertEquals('final sigma, case', '14', Positions(doc, U([$3C2]), [rfoMatchCase]));
    AssertEquals('Cyrillic', '16', Positions(doc, U([$436, $451]), []));
    AssertEquals('Cyrillic, case', '', Positions(doc, U([$436, $451]), [rfoMatchCase]));
    AssertEquals('full-width Latin', '19', Positions(doc, U([$FF41, $FF42]), []));
    AssertEquals('full-width Latin, case', '', Positions(doc, U([$FF41, $FF42]), [rfoMatchCase]));
    AssertEquals('the fold table', $3C3, TyRichFoldChar($3A3));
    // nothing is normalised: a and a combining diaeresis are not U+00E4
    AssertEquals('no normalisation', '', Positions(doc, U([Ord('a'), $308]), []));
    AssertEquals('...a full-width capital', $FF41, TyRichFoldChar($FF21));
    AssertEquals('...a byte that is no text is itself', TyRichFindRawByte + $C3,
      TyRichFoldChar(TyRichFindRawByte + $C3));
  finally
    doc.Free;
  end;
end;

procedure TTyRichFindTest.TestWholeWordAndChinese;
var
  doc: TTyRichDocument;
begin
  { An ideograph (kana, Hangul - the scripts written without spaces) bounds a word on
    both of its sides, as Windows' rich edit finds it: a Chinese needle is whole between
    ideographs, and a Latin word inside Chinese text is bounded by them. }
  doc := TextDoc(U([$4E2D, $6587, 32, $4E2D, $6587, $5B57, 32, $4E2D, $6587, Ord(','), Ord('a'),
    $4E2D, $6587]));
  try
    AssertEquals('anywhere', '0 3 7 11', Positions(doc, U([$4E2D, $6587]), []));
    AssertEquals('whole words, also inside a run of ideographs', '0 3 7 11',
      Positions(doc, U([$4E2D, $6587]), [rfoWholeWord]));
    AssertEquals('one ideograph of a run', '1 4 8 12', Positions(doc, U([$6587]), [rfoWholeWord]));
    // never refused: a needle whose end is no word character
    AssertEquals('a comma, whole', '9', Positions(doc, ',', [rfoWholeWord]));
    AssertEquals('a Chinese run and a comma', '7',
      Positions(doc, U([$4E2D, $6587, Ord(',')]), [rfoWholeWord]));
    AssertEquals('...also from inside the run', '8',
      Positions(doc, U([$6587, Ord(',')]), [rfoWholeWord]));
    AssertEquals('a Latin letter before an ideograph', '10', Positions(doc, 'a', [rfoWholeWord]));
  finally
    doc.Free;
  end;
  // Latin words inside Chinese text, and kana and Hangul
  doc := TextDoc(U([$4E2D, Ord('a'), Ord('b'), Ord('c'), $6587, 32, $3042, $3044, 32, $D55C,
    $AE00]));
  try
    AssertEquals('a Latin word between ideographs', '1', Positions(doc, 'abc', [rfoWholeWord]));
    AssertEquals('...not a part of it', '', Positions(doc, 'ab', [rfoWholeWord]));
    AssertEquals('kana', '7', Positions(doc, U([$3044]), [rfoWholeWord]));
    AssertEquals('Hangul', '9', Positions(doc, U([$D55C]), [rfoWholeWord]));
  finally
    doc.Free;
  end;
end;

procedure TTyRichFindTest.TestTheEndsAndParagraphEnds;
var
  doc: TTyRichDocument;
begin
  doc := TextDoc('ab' + #13#10 + 'cd' + #13#10 + #13#10 + 'ef' + #11 + 'ab');
  try
    AssertEquals('at the start and the end', '0 10', Positions(doc, 'ab', []));
    AssertEquals('CR LF in the needle', '1', Positions(doc, 'b' + #13#10 + 'c', []));
    AssertEquals('LF', '1', Positions(doc, 'b' + #10 + 'c', []));
    AssertEquals('CR', '1', Positions(doc, 'b' + #13 + 'c', []));
    AssertEquals('two ends and an empty paragraph', '4', Positions(doc, 'd' + #10#10 + 'e', []));
    AssertEquals('three paragraphs', '1', Positions(doc, 'b' + #10 + 'cd' + #10#10 + 'ef', []));
    AssertEquals('...whose middle one is another', '',
      Positions(doc, 'b' + #10 + 'cx' + #10#10 + 'ef', []));
    AssertEquals('...or longer', '', Positions(doc, 'b' + #10 + 'cdd' + #10#10 + 'ef', []));
    AssertEquals('a needle that ends with one', '3', Positions(doc, 'cd' + #10, []));
    AssertEquals('one that begins with one', '5', Positions(doc, #10#10 + 'e', []));
    AssertEquals('U+000B is its own character', '8', Positions(doc, 'f' + #11 + 'a', []));
    AssertEquals('...not a paragraph end', '', Positions(doc, 'f' + #10 + 'a', []));
    AssertEquals('no paragraph end after the last', '', Positions(doc, #11 + 'ab' + #10, []));
    AssertEquals('...but after the first', '0', Positions(doc, 'ab' + #10, []));
    AssertEquals('backward across paragraphs', 1, First(doc, 'b' + #10 + 'c', [rfoBackward]));
    AssertEquals('whole word across: "a" goes on before it', '',
      Positions(doc, 'b' + #10 + 'c', [rfoWholeWord]));
    AssertEquals('whole word across', '0', Positions(doc, 'ab' + #10 + 'cd', [rfoWholeWord]));
  finally
    doc.Free;
  end;
end;

procedure TTyRichFindTest.TestAnObjectBreaksAMatch;
var
  doc: TTyRichDocument;
  pic: TTyRichPicture;
begin
  doc := TextDoc('abcd abcd');
  try
    pic := TTyRichPicture.Create(rpfPng, nil, 100, 100);
    AssertTrue(doc.Execute(TTyRichInsertObject.Create(2, pic)));
    // a b <obj> c d   a b c d
    AssertEquals('across the object: never', '6', Positions(doc, 'abcd', []));
    AssertEquals('next to it', '0 6', Positions(doc, 'ab', []));
    AssertEquals('right after it', '3 8', Positions(doc, 'cd', []));
    AssertEquals('the object character finds nothing', '', Positions(doc, U([$FFFC]), []));
    AssertEquals('... nor with text around it', '', Positions(doc, U([Ord('b'), $FFFC, Ord('c')]), []));
    AssertEquals('whole word: the object is a word of its own', '0',
      Positions(doc, 'ab', [rfoWholeWord]));
    AssertEquals('...on either side', '3', Positions(doc, 'cd', [rfoWholeWord]));
  finally
    doc.Free;
  end;
end;

procedure TTyRichFindTest.TestAnEscapedByteMatchesOnlyItself;
var
  doc: TTyRichDocument;
  esc: RawByteString;
begin
  // a GBK file with a byte that is no character: kept as the two-character escape
  doc := LoadTxt(BytesOf('ab' + #$FF + 'cd ab?cd'), teAnsi);
  try
    esc := doc.Text.GetText(2, 2);
    AssertEquals('the escape is two characters', 2, Length(TyRichFindCodes(esc)));
    AssertEquals('the escape matches itself', '0', Positions(doc, 'ab' + esc + 'cd', []));
    AssertEquals('a question mark does not match it', '7', Positions(doc, 'ab?cd', []));
    AssertEquals('U+FFFD does not either', '', Positions(doc, U([Ord('b'), $FFFD]), []));
    AssertEquals('half of it does', '2', Positions(doc, Copy(esc, 1, 1), []));
  finally
    doc.Free;
  end;
end;

procedure TTyRichFindTest.TestCellsInTextOrderAndMergedAwayNever;
var
  doc: TTyRichDocument;
  bytes: TBytes;
  want: string;
begin
  // a row of three cells, the third merged into the second: it holds "gone"
  bytes := BytesOf(Rtf('{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}|pard before|par' +
    '|trowd|cellx1000|clmgf|cellx2000|clmrg|cellx3000' +
    '|pard|intbl one|cell two|cell gone|cell|row|pard after|par}'));
  doc := LoadRtf(bytes, False);
  try
    AssertEquals('cell after cell', '7', Positions(doc, 'one' + #10 + 'two', []));
    AssertEquals('a merged-away cell: never', '', Positions(doc, 'gone', []));
    AssertEquals('...nor across into it', '', Positions(doc, 'two' + #10 + 'g', []));
    AssertEquals('the cell before it', '11', Positions(doc, 'two', []));
    want := Naive(doc, 'one', []);
    AssertEquals('the reference agrees', want, Positions(doc, 'one', []));
  finally
    doc.Free;
  end;
  // the fixtures with merged cells: the reference (which skips them) agrees
  bytes := ReadFileBytes(FixtureDir('rtf') + 'word-table-merged.rtf');
  doc := LoadRtf(bytes, False);
  try
    AssertEquals('word-table-merged: e', Naive(doc, 'e', []), Positions(doc, 'e', []));
  finally
    doc.Free;
  end;
end;

procedure TTyRichFindTest.TestBackwardFindsTheLastFirst;
var
  doc: TTyRichDocument;
  f: TTyRichFinder;
  want, got: TStringList;
  s: RawByteString;
  i: Integer;
  r: TTyRichFindResult;
begin
  s := '';
  for i := 0 to 999 do s := s + 'line ' + IntToStr(i) + ' word' + #10;
  s := s + 'word' + #10 + 'wo' + #10 + 'rd';
  doc := TextDoc(s);
  want := TStringList.Create;
  got := TStringList.Create;
  try
    want.Delimiter := ' ';
    want.DelimitedText := Naive(doc, 'word', []);
    AssertEquals('the reference', 1001, want.Count);
    // backward in small steps: every match, the last first
    f := TTyRichFinder.Create(doc, 'word', [rfoBackward]);
    try
      repeat
        r := f.Step(64);
        if r = rfrFound then got.Add(IntToStr(f.MatchPos));
      until r = rfrNotFound;
    finally
      f.Free;
    end;
    AssertEquals('as many', want.Count, got.Count);
    for i := 0 to got.Count - 1 do
      AssertEquals('the last first', want[want.Count - 1 - i], got[i]);
    // across paragraphs, backward
    AssertEquals('backward across paragraph ends', doc.Text.Length - 5,
      First(doc, 'wo' + #10 + 'rd', [rfoBackward]));
    AssertEquals('...and across two', doc.Text.Length - 10,
      First(doc, 'word' + #10 + 'wo' + #10 + 'rd', [rfoBackward]));
  finally
    got.Free;
    want.Free;
    doc.Free;
  end;
end;

procedure TTyRichFindTest.TestARangeHoldsTheWholeMatch;
var
  doc: TTyRichDocument;
begin
  doc := TextDoc('abc abc abc');
  try
    AssertEquals('inside', 4, First(doc, 'abc', [], 1, 7));
    AssertEquals('one character short', -1, First(doc, 'abc', [], 1, 6));
    AssertEquals('backward inside', 4, First(doc, 'abc', [rfoBackward], 0, 10));
    AssertEquals('backward from its end', 8, First(doc, 'abc', [rfoBackward], 0, 11));
  finally
    doc.Free;
  end;
end;

{ ---- the steps ---- }

procedure TTyRichFindTest.TestAStepIsBounded;
var
  doc: TTyRichDocument;
  f: TTyRichFinder;
  s: RawByteString;
  i: Integer;
  r: TTyRichFindResult;
  maxRead, before: Int64;
begin
  s := '';
  for i := 0 to 9999 do s := s + 'some words here' + #10;
  s := s + 'needle';
  doc := TextDoc(s);
  try
    f := TTyRichFinder.Create(doc, 'needle', []);
    try
      maxRead := 0;
      repeat
        before := f.ParasRead;
        r := f.Step(1600);
        if f.ParasRead - before > maxRead then maxRead := f.ParasRead - before;
      until r <> rfrMore;
      AssertTrue('found', r = rfrFound);
      AssertTrue(Format('a step of 1600 characters reads about 100 paragraphs (%d)', [maxRead]),
        maxRead <= 102);
      AssertTrue(Format('in about 100 steps (%d)', [f.Steps]), f.Steps >= 90);
    finally
      f.Free;
    end;
  finally
    doc.Free;
  end;
end;

{ A step is bounded in bytes, whatever the paragraphs are - one line of megabytes of
  text is read in pieces (a match that straddles two steps is found, and so is the next one),
  forward and backward, match case or not, whole word; in a file of paragraphs that are each
  a large picture - a megabyte of the file, one character of text - the file's bytes count:
  a step ends with the paragraph that spent its budget. Counts, not times. }
procedure TTyRichFindTest.TestAStepIsBoundedInBytes;
const
  Budget = 64 * 1024;
  Slack = 4096;
var
  line, s, hex: RawByteString;
  doc: TTyRichDocument;
  f: TTyRichFinder;
  r: TTyRichFindResult;
  i, steps: Integer;
  before, worst, d: Int64;
  opts: TTyRichFindOptions;
  k: Integer;
  m: TMemoryStream;
  total, second: Int64;
begin
  line := '';
  while Length(line) < 4 * MB do line := line + 'lorem ipsum dolor sit amet ';
  // straddling the first step's end, and once more near the end
  Insert('quixotic', line, Budget - 3);
  second := Length(line) - 100;
  Insert(' quixotic ', line, second);
  doc := TextDoc(line);
  try
    AssertEquals('one paragraph', 1, doc.Text.ParaCount);
    for k := 0 to 3 do
    begin
      case k of
        0: opts := [rfoMatchCase];
        1: opts := [];
        2: opts := [rfoWholeWord];
      else
        opts := [rfoBackward];
      end;
      f := TTyRichFinder.Create(doc, 'quixotic', opts);
      try
        worst := 0;
        steps := 0;
        repeat
          before := f.TextBytes;
          r := f.Step(Budget);
          Inc(steps);
          d := f.TextBytes - before;
          if d > worst then worst := d;
        until r <> rfrMore;
        AssertTrue(Format('%d: found', [k]), r = rfrFound);
        if k = 2 then
          // (the first one is inside "lorem...quixoticlorem": no whole word)
          AssertEquals(Format('%d: the whole word', [k]), second, f.MatchPos)
        else if k = 3 then
          AssertEquals(Format('%d: the last first', [k]), second, f.MatchPos)
        else
          AssertEquals(Format('%d: where two steps meet', [k]), Int64(Budget - 4), f.MatchPos);
        AssertTrue(Format('%d: no step read more than its budget (%d)', [k, worst]), worst <= Budget + Slack);
        AssertTrue(Format('%d: in pieces (%d steps)', [k, steps]), (k = 3) or (steps >= 1));
        if k in [0, 1] then
        begin
          // and on: the next one, from right after it - not from the paragraph's start
          before := f.TextBytes;
          repeat
            r := f.Step(Budget);
          until r <> rfrMore;
          AssertTrue(Format('%d: the next one', [k]), r = rfrFound);
          AssertEquals(Format('%d: there', [k]), second, f.MatchPos);
          AssertTrue(Format('%d: read on, not again (%d)', [k, f.TextBytes - before]),
            f.TextBytes - before <= Length(line) - Budget + Slack);
        end;
      finally
        f.Free;
      end;
    end;
    // a find that begins inside the paragraph passes what lies before
    AssertEquals('from inside', second, First(doc, 'quixotic', [rfoMatchCase], Budget));
  finally
    doc.Free;
  end;
  // a file of pictures with a word after them
  m := TMemoryStream.Create;
  try
    s := Rtf('{|rtf1|ansi|ansicpg1252|deff0{|fonttbl{|f0|fswiss Arial;}}|pard first|par ');
    m.WriteBuffer(s[1], Length(s));
    SetLength(hex, MB);
    for i := 1 to Length(hex) do hex[i] := Chr(Ord('0') + (i mod 10));
    for i := 1 to 8 do
    begin
      s := Rtf('{|pict|pngblip|picw100|pich100 ');
      m.WriteBuffer(s[1], Length(s));
      m.WriteBuffer(hex[1], Length(hex));
      s := Rtf('}|par ');
      m.WriteBuffer(s[1], Length(s));
    end;
    s := Rtf('the end: quixotic|par}');
    m.WriteBuffer(s[1], Length(s));
    total := m.Size;
    doc := TTyRichDocument.Create;
    try
      m.Position := 0;
      TyRichLoadRtf(doc, m);
      f := TTyRichFinder.Create(doc, 'quixotic', []);
      try
        worst := 0;
        steps := 0;
        repeat
          before := f.TextBytes + f.FileBytes;
          r := f.Step(Budget);
          Inc(steps);
          d := f.TextBytes + f.FileBytes - before;
          if d > worst then worst := d;
        until r <> rfrMore;
        AssertTrue('found after the pictures', r = rfrFound);
        // (a paragraph is parsed in one piece: the one that spends the budget ends the step)
        AssertTrue(Format('no step over its budget by more than a paragraph (%d)', [worst]),
          worst <= Budget + MB + Slack);
        AssertTrue(Format('each picture ends a step (%d steps)', [steps]), steps >= 8);
        AssertTrue(Format('the file''s bytes counted (%d of %d)', [f.FileBytes, total]),
          (f.FileBytes > total - MB) and (f.FileBytes <= total));
      finally
        f.Free;
      end;
    finally
      doc.Free;
    end;
  finally
    m.Free;
  end;
end;

procedure TTyRichFindTest.TestAFindWhileLoading;
var
  m: TMemoryStream;
  s: RawByteString;
  doc: TTyRichDocument;
  load: TTyRtfLoad;
  f: TTyRichFinder;
  i: Integer;
  r: TTyRichFindResult;
  waits: Integer;
begin
  m := TMemoryStream.Create;
  doc := TTyRichDocument.Create;
  try
    s := Rtf('{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}|pard ');
    m.WriteBuffer(s[1], Length(s));
    for i := 0 to 19999 do
    begin
      s := Rtf('filler text of a line ') + IntToStr(i) + Rtf('|par') + #13#10;
      m.WriteBuffer(s[1], Length(s));
    end;
    s := Rtf('the target|par}');
    m.WriteBuffer(s[1], Length(s));
    m.Position := 0;
    load := TyRichBeginLoadRtf(doc, m, 64 * 1024);
    AssertTrue('loading', doc.Loading);
    // the synchronous run: what is loaded only
    AssertEquals('not in what is loaded yet', -1, First(doc, 'target', []));
    f := TTyRichFinder.Create(doc, 'target', []);
    try
      waits := 0;
      repeat
        r := f.Step(100000);
        if (r = rfrMore) and f.Waiting then
        begin
          Inc(waits);
          load.Step(64 * 1024);
        end;
      until r <> rfrMore;
      AssertTrue('found as the load went on', r = rfrFound);
      AssertTrue('it waited for the load', waits > 0);
      AssertFalse('the load has ended', doc.Loading);
      AssertEquals('there', doc.Text.ParaStart(doc.Text.ParaOfPos(f.MatchPos)) + 4, f.MatchPos);
    finally
      f.Free;
    end;
  finally
    doc.Free;
    m.Free;
  end;
end;

procedure TTyRichFindTest.TestAFindChangesNothing;
const
  Names: array[0..2] of string = ('hand-word-list.rtf', 'word-table-merged.rtf',
    're-zh-picture.rtf');
var
  bytes, saved: TBytes;
  doc: TTyRichDocument;
  load: TTyRtfLoad;
  live, state, resident, bound: Int64;
  info: TTyRtfWriteInfo;
  m: TBytesStream;
  name: string;
  n: Integer;
begin
  for n := 0 to High(Names) do
  begin
    name := Names[n];
    bytes := ReadFileBytes(FixtureDir('rtf') + name);
    doc := LoadRtf(bytes, False);
    try
      load := TyRichRtfLoadOf(doc);
      live := TDocAccess(doc).LiveParaData;
      state := doc.ContentState;
      resident := load.ResidentIntervals;
      Positions(doc, 'e', []);
      Positions(doc, 'e', [rfoWholeWord]);
      First(doc, 'e', [rfoBackward]);
      AssertEquals(name + ': no value left behind', live, TDocAccess(doc).LiveParaData);
      AssertEquals(name + ': the content is the same', state, doc.ContentState);
      AssertFalse(name + ': not modified', doc.Modified);
      bound := 2 * load.MaxResidentIntervals + 1;
      if resident > bound then bound := resident;
      AssertTrue(name + ': the residency did not grow past its bound',
        load.ResidentIntervals <= bound);
      m := TBytesStream.Create;
      try
        TyRichSaveRtf(doc, m, info);
        saved := Copy(m.Bytes, 0, m.Size);
      finally
        m.Free;
      end;
      AssertEquals(name + ': nothing rewritten', 0, info.RewrittenParas);
      AssertTrue(name + ': saved as the file', SameBytes(bytes, saved));
    finally
      doc.Free;
    end;
  end;
end;

{ ---- replacing ---- }

{ Every match of ANeedle replaced by ARepl in one command, run whole (AllAtOnce: the way inside
  an update block, and a redo's); the number replaced, ASkipped the matches the document
  refused. }
function ReplaceIn(ADoc: TTyRichDocument; const ANeedle, ARepl: UTF8String;
  AOptions: TTyRichFindOptions; out ASkipped: Integer): Integer;
var
  cmd: TTyRichReplaceAllCommand;
  tally: TTyRichReplaceTally;
begin
  tally := Default(TTyRichReplaceTally);
  cmd := TTyRichReplaceAllCommand.Create(ADoc, ANeedle, ARepl, AOptions);
  cmd.AllAtOnce := True;
  cmd.Tally := @tally;
  ADoc.Execute(cmd);
  ASkipped := tally.Skipped;
  Result := tally.Replaced;
end;

{ The same in parts, as the control runs it: a range of paragraphs found, then replaced
  (Execute, then ExecutePart: one step), a lazily read file's intervals let go between two. }
function ReplaceInParts(ADoc: TTyRichDocument; const ANeedle, ARepl: UTF8String;
  AOptions: TTyRichFindOptions; ARange: Int64; out ASkipped, AParts: Integer;
  out ALimited: Boolean): Integer;
var
  cmd: TTyRichReplaceAllCommand;
  tally: TTyRichReplaceTally;
  ran: Boolean;
  load: TTyRtfLoad;
begin
  tally := Default(TTyRichReplaceTally);
  cmd := TTyRichReplaceAllCommand.Create(ADoc, ANeedle, ARepl, AOptions);
  cmd.Tally := @tally;
  cmd.RangeChars := ARange;
  ran := False;
  AParts := 0;
  try
    repeat
      cmd.Prepare(-1);
      if not cmd.Ready then Break;
      if not ran then
      begin
        ran := True;
        if not ADoc.Execute(cmd) then Break;
      end
      else if not ADoc.ExecutePart(cmd) then
        Break;
      Inc(AParts);
      load := TyRichRtfLoadOf(ADoc);
      if load <> nil then load.Trim;
    until cmd.Finished;
  finally
    if not ran then cmd.Free;
  end;
  ASkipped := tally.Skipped;
  ALimited := tally.Limited;
  Result := tally.Replaced;
end;

function CountOf(const ASub, AText: RawByteString): Integer;
var
  p: Integer;
begin
  Result := 0;
  p := Pos(ASub, AText);
  while p > 0 do
  begin
    Inc(Result);
    p := Pos(ASub, AText, p + Length(ASub));
  end;
end;

type
  // counts a document's OnChange
  TChangeCounter = class
  public
    Count: Integer;
    procedure Changed(Sender: TObject; const AChange: TTyRichChange);
  end;

procedure TChangeCounter.Changed(Sender: TObject; const AChange: TTyRichChange);
begin
  Inc(Count);
end;

{ A replace of every match is ONE command - its parts (a range of paragraphs from
  the start on each) one undo step, never merged with another step, one OnChange
  a part; an undo puts the text back at once, a redo replays it; and what the step keeps is a
  few bytes a match (one record a range: a paragraph's pieces and value before). }
procedure TTyRichFindTest.TestReplaceIsOneStepOfParts;
var
  doc: TTyRichDocument;
  s, before: RawByteString;
  i, n, skipped, parts: Integer;
  limited: Boolean;
  counter: TChangeCounter;
  bytes, redone: Int64;
begin
  s := '';
  for i := 0 to 1999 do s := s + 'alpha,bravo,charlie,delta,echo,foxtrot,golf,hotel,india,juliet' + #10;
  doc := TextDoc(s);
  counter := TChangeCounter.Create;
  try
    before := doc.Text.GetText(0, doc.Text.Length);
    doc.OnChange := @counter.Changed;
    n := ReplaceInParts(doc, ',', ';', [], 4096, skipped, parts, limited);
    AssertEquals('every comma', 18000, n);
    AssertEquals('none skipped', 0, skipped);
    AssertFalse('no limit', limited);
    AssertTrue(Format('in parts (%d)', [parts]), parts > 10);
    AssertEquals('one OnChange a part', parts, counter.Count);
    AssertEquals('none left', 0, CountOf(',', doc.Text.GetText(0, doc.Text.Length)));
    AssertEquals('one step', 1, doc.UndoDepth);
    AssertEquals('the name', rsRichUndoReplace, doc.UndoDescription);
    bytes := doc.HistoryBytes;
    AssertTrue(Format('a few bytes a match (%d for %d)', [bytes, n]), bytes < 16 * n);
    doc.Undo;
    AssertEquals('undone at once', before, doc.Text.GetText(0, doc.Text.Length));
    AssertEquals('...one OnChange', parts + 1, counter.Count);
    doc.Redo;
    AssertEquals('redone at once', 0, CountOf(',', doc.Text.GetText(0, doc.Text.Length)));
    AssertEquals('...as one step', 1, doc.UndoDepth);
    redone := doc.HistoryBytes;
    AssertTrue(Format('counted as before (%d, %d)', [bytes, redone]), Abs(redone - bytes) * 10 < bytes);
    doc.Undo;
    AssertEquals('undone again', before, doc.Text.GetText(0, doc.Text.Length));
    // typing before it, and another replace after it: steps of their own (never merged)
    doc.OnChange := nil;
    doc.Redo;
    AssertTrue(doc.Execute(TTyRichInsertText.Create(0, 'x')));
    AssertEquals('typing', 2, doc.UndoDepth);
    ReplaceInParts(doc, ';', ',', [], 4096, skipped, parts, limited);
    AssertEquals('another replace: a step of its own', 3, doc.UndoDepth);
    ReplaceInParts(doc, 'alpha', 'A', [], 4096, skipped, parts, limited);
    AssertEquals('and another', 4, doc.UndoDepth);
  finally
    doc.Free;
    counter.Free;
  end;
  // one paragraph with matches all through it: replaced in parts too (CRichReplacePartMatches)
  s := '';
  for i := 0 to 19999 do s := s + 'a,';
  doc := TextDoc(s);
  try
    before := doc.Text.GetText(0, doc.Text.Length);
    n := ReplaceInParts(doc, ',', ';', [], 1 shl 20, skipped, parts, limited);
    AssertEquals('one paragraph: every comma', 20000, n);
    AssertTrue(Format('...in parts (%d)', [parts]), parts >= 3);
    AssertEquals('...none left', 0, CountOf(',', doc.Text.GetText(0, doc.Text.Length)));
    AssertEquals('...one step', 1, doc.UndoDepth);
    doc.Undo;
    AssertEquals('...undone at once', before, doc.Text.GetText(0, doc.Text.Length));
    doc.Redo;
    AssertEquals('...redone', 0, CountOf(',', doc.Text.GetText(0, doc.Text.Length)));
  finally
    doc.Free;
  end;
end;

{ What a replace leaves is what was there: the formats of what it did not replace, the objects,
  a paragraph's format and cell; each replacement in the format of the first character it
  replaces; an undo gives every paragraph its runs back exactly. Whole, in parts, and with
  paragraph ends in the needle (the simple way: every match first) or in the replacement. }
procedure TTyRichFindTest.TestReplaceKeepsFormatsAndObjects;
var
  doc: TTyRichDocument;
  bytes: TBytes;
  runs, before: array of TTyRunArray;
  r, i, k, n, skipped, parts: Integer;
  limited: Boolean;
  text0: RawByteString;
begin
  bytes := BytesOf(Rtf('{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}|pard one {|b cat} two {|i cAt}|par ' +
    'a {|field{|*|fldinst HYPERLINK "x"}{|fldrslt link}} cat{|b cat}cat|par |qc centred cat|par}'));
  for k := 0 to 1 do
  begin
    doc := LoadRtf(bytes, k = 0);
    try
      text0 := doc.Text.GetText(0, doc.Text.Length);
      before := nil;
      SetLength(before, doc.Text.ParaCount);
      for i := 0 to doc.Text.ParaCount - 1 do before[i] := doc.RunsOf(i);
      if k = 0 then n := ReplaceIn(doc, 'cat', 'tiger', [], skipped)
      else n := ReplaceInParts(doc, 'cat', 'tiger', [], 8, skipped, parts, limited);
      AssertEquals('all of them', 6, n);
      runs := nil;
      SetLength(runs, 1);
      runs[0] := doc.RunsOf(0);
      r := High(runs[0]);
      while runs[0][r].Start > 4 do Dec(r);
      AssertTrue('the bold one bold', fsBold in doc.Formats.CharFormat(runs[0][r].Format).Style);
      r := High(runs[0]);
      while runs[0][r].Start > 14 do Dec(r);
      AssertTrue('the italic one italic', fsItalic in doc.Formats.CharFormat(runs[0][r].Format).Style);
      AssertFalse('...not bold', fsBold in doc.Formats.CharFormat(runs[0][r].Format).Style);
      // the link is an object that stays, at its place
      runs[0] := doc.RunsOf(1);
      AssertTrue('the object stays', (Length(runs[0]) > 1) and (runs[0][1].Obj <> nil));
      AssertEquals('the centred paragraph keeps its format', Ord(paraCenter),
        Ord(doc.Formats.ParaFormat(doc.ParaFormatOf(2)).Align));
      doc.Undo;
      AssertEquals('the text back', text0, doc.Text.GetText(0, doc.Text.Length));
      for i := 0 to doc.Text.ParaCount - 1 do
      begin
        runs[0] := doc.RunsOf(i);
        AssertEquals(Format('paragraph %d: as many runs', [i]), Length(before[i]), Length(runs[0]));
        for r := 0 to High(runs[0]) do
        begin
          AssertEquals(Format('paragraph %d run %d: its start', [i, r]), before[i][r].Start, runs[0][r].Start);
          AssertEquals(Format('paragraph %d run %d: its format', [i, r]), before[i][r].Format, runs[0][r].Format);
          AssertTrue(Format('paragraph %d run %d: its object', [i, r]), before[i][r].Obj = runs[0][r].Obj);
        end;
      end;
    finally
      doc.Free;
    end;
  end;
  // paragraph ends: in the needle (every match first), and in the replacement
  doc := TextDoc('one' + #10 + #10 + 'two' + #10 + #10 + #10 + 'three' + #10 + 'four');
  try
    text0 := doc.Text.GetText(0, doc.Text.Length);
    n := ReplaceInParts(doc, #10#10, #10, [], 4, skipped, parts, limited);
    AssertEquals('the empty paragraphs go', 2, n);
    AssertEquals('one' + #10 + 'two' + #10 + #10 + 'three' + #10 + 'four',
      StringReplace(doc.Text.GetText(0, doc.Text.Length), #13#10, #10, [rfReplaceAll]));
    AssertEquals('one step', 1, doc.UndoDepth);
    doc.Undo;
    AssertEquals('undone', text0, doc.Text.GetText(0, doc.Text.Length));
    n := ReplaceInParts(doc, 'o', 'o' + #10, [], 4, skipped, parts, limited);
    AssertEquals('every o', 3, n);
    AssertEquals('...a paragraph end after each', 10, doc.Text.ParaCount);
    doc.Undo;
    AssertEquals('undone again', text0, doc.Text.GetText(0, doc.Text.Length));
    doc.Redo;
    AssertEquals('redone', 10, doc.Text.ParaCount);
  finally
    doc.Free;
  end;
end;

{ The limit - a replace whose step reaches four times MaxUndoBytes ends there, says so,
  and what it replaced is one step; run again it goes on. }
procedure TTyRichFindTest.TestReplaceStopsAtTheLimit;
var
  doc: TTyRichDocument;
  s: RawByteString;
  i, n, n2, skipped, parts: Integer;
  limited: Boolean;
begin
  s := '';
  for i := 0 to 19999 do s := s + 'one,two,three' + #10;
  doc := TextDoc(s);
  try
    doc.MaxUndoBytes := 16 * 1024;
    n := ReplaceInParts(doc, ',', ';', [], 1024, skipped, parts, limited);
    AssertTrue('stopped at the limit', limited);
    AssertTrue(Format('some replaced (%d)', [n]), (n > 0) and (n < 40000));
    AssertEquals('as many as are gone', 40000 - n, CountOf(',', doc.Text.GetText(0, doc.Text.Length)));
    AssertEquals('one step', 1, doc.UndoDepth);
    AssertTrue(Format('the step at its limit (%d)', [doc.HistoryBytes]),
      doc.HistoryBytes >= CRichReplaceLimitFactor * doc.MaxUndoBytes);
    n2 := ReplaceInParts(doc, ',', ';', [], 1024, skipped, parts, limited);
    AssertTrue(Format('again: more (%d)', [n2]), n2 > 0);
    // (a step of its own: the history's bound may have let the first go)
    AssertTrue('a step of its own', doc.UndoDepth >= 1);
    doc.MaxUndoBytes := 0;
    ReplaceInParts(doc, ',', ';', [], 1024, skipped, parts, limited);
    AssertFalse('no limit: to the start', limited);
    AssertEquals('all of them', 0, CountOf(',', doc.Text.GetText(0, doc.Text.Length)));
  finally
    doc.Free;
  end;
end;

{ A row that holds a nested table keeps its matches (counted), whatever comes before or after
  it in the range: the row is asked of each paragraph, once a paragraph. }
procedure TTyRichFindTest.TestReplaceSkipsANestedRow;
var
  doc: TTyRichDocument;
  n, skipped: Integer;
begin
  doc := LoadRtf(BytesOf(Rtf('{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}' +
    '|trowd|cellx2000|cellx4000|pard|intbl word two|cell' +
    '|pard|intbl|itap2 word nested|nestcell{|*|nesttableprops|trowd|cellx1000|nestrow}{|nonesttables|par}' +
    '|pard|intbl|cell|row|pard word one|par word three|par}')), False);
  try
    n := ReplaceIn(doc, 'word', 'w', [], skipped);
    AssertEquals('the paragraphs after the row replaced', 2, n);
    AssertEquals('the row''s two left, and counted', 2, skipped);
    AssertEquals('one step', 1, doc.UndoDepth);
  finally
    doc.Free;
  end;
end;

{ A part runs only on the content the step left - BreakMerge does not stop it (the step
  merges with nothing), a saved point does (Modified := False), and then nothing of it runs:
  nothing is on the redo side. }
procedure TTyRichFindTest.TestAStoppedReplaceLeavesNothingToRedo;
var
  doc: TTyRichDocument;
  s: RawByteString;
  i: Integer;
  cmd: TTyRichReplaceAllCommand;
  tally: TTyRichReplaceTally;
  replaced: Integer;
begin
  s := '';
  for i := 0 to 999 do s := s + 'a cat here' + #10;
  doc := TextDoc(s);
  try
    tally := Default(TTyRichReplaceTally);
    cmd := TTyRichReplaceAllCommand.Create(doc, 'cat', 'dog', []);
    cmd.Tally := @tally;
    cmd.RangeChars := 512;
    AssertTrue('a part found', cmd.Prepare(-1) and cmd.Ready);
    AssertTrue('the first part', doc.Execute(cmd));
    doc.BreakMerge;
    AssertTrue(cmd.Prepare(-1) and cmd.Ready);
    AssertTrue('BreakMerge does not stop it', doc.ExecutePart(cmd));
    AssertEquals('one step', 1, doc.UndoDepth);
    replaced := tally.Replaced;
    doc.Modified := False;
    AssertTrue(cmd.Prepare(-1) and cmd.Ready);
    AssertFalse('a saved point does', doc.ExecutePart(cmd));
    AssertEquals('nothing of it ran', replaced, tally.Replaced);
    AssertEquals('nothing of it ran: the text', replaced, CountOf('dog', doc.Text.GetText(0, doc.Text.Length)));
    AssertFalse('nothing on the redo side', doc.CanRedo);
    AssertEquals('still one step', 1, doc.UndoDepth);
    AssertFalse('not modified', doc.Modified);
    // an edit since: refused too
    doc.Modified := True;
    AssertTrue(doc.Execute(TTyRichInsertText.Create(0, 'x')));
    AssertFalse('not the newest step', doc.ExecutePart(cmd));
    AssertFalse('nothing to redo', doc.CanRedo);
  finally
    doc.Free;
  end;
end;

{ "Let go of" and "through its range" are two states of a replace: one that is let go of
  after a part - by its caller, by a step put on top of its own, by the undo of its step - is
  Stopped, not Finished, also after its step is uncovered or redone; it finds nothing more.
  One that walked through its range is Finished, and stays so let go, undone and redone. }
procedure TTyRichFindTest.TestAReplaceLetGoIsStoppedNotFinished;
var
  s: RawByteString;
  doc: TTyRichDocument;
  i, way: Integer;
  cmd: TTyRichReplaceAllCommand;
  tally: TTyRichReplaceTally;
  skipped: Integer;
begin
  s := '';
  for i := 0 to 999 do s := s + 'a cat here' + #10;
  for way := 0 to 2 do
  begin
    doc := TextDoc(s);
    try
      tally := Default(TTyRichReplaceTally);
      cmd := TTyRichReplaceAllCommand.Create(doc, 'cat', 'dog', []);
      cmd.Tally := @tally;
      cmd.RangeChars := 512;
      AssertTrue('a part found', cmd.Prepare(-1) and cmd.Ready);
      AssertTrue('the first part', doc.Execute(cmd));
      AssertFalse('running: not stopped', cmd.Stopped);
      AssertFalse('running: not finished', cmd.Finished);
      case way of
        0: cmd.LetGo;
        1:
          begin
            // a step on top of it, taken off again
            AssertTrue(doc.Execute(TTyRichInsertText.Create(0, 'x')));
            doc.Undo;
          end;
      else
        doc.Undo;
        doc.Redo;
      end;
      AssertTrue(Format('%d: it is the top step', [way]), doc.UndoStep = cmd);
      AssertTrue(Format('%d: stopped', [way]), cmd.Stopped);
      AssertFalse(Format('%d: not finished', [way]), cmd.Finished);
      AssertTrue(Format('%d: a search finds nothing more', [way]), cmd.Prepare(-1) and not cmd.Ready);
      AssertFalse(Format('%d: still not finished', [way]), cmd.Finished);
      AssertEquals(Format('%d: a part of them replaced', [way]), tally.Replaced,
        CountOf('dog', doc.Text.GetText(0, doc.Text.Length)));
      AssertTrue(Format('%d: not all', [way]), (tally.Replaced > 0) and (tally.Replaced < 1000));
      doc.Undo;
      doc.Redo;
      AssertTrue(Format('%d: undone and redone: stopped', [way]), cmd.Stopped and not cmd.Finished);
    finally
      doc.Free;
    end;
  end;
  // through its range
  doc := TextDoc(s);
  try
    AssertEquals('all of them', 1000, ReplaceIn(doc, 'cat', 'dog', [], skipped));
    cmd := doc.UndoStep as TTyRichReplaceAllCommand;
    AssertTrue('finished', cmd.Finished and not cmd.Stopped);
    cmd.LetGo;
    AssertTrue('let go: finished', cmd.Finished and not cmd.Stopped);
    doc.Undo;
    doc.Redo;
    AssertTrue('undone and redone: finished', cmd.Finished and not cmd.Stopped);
    AssertEquals('all of them again', 1000, CountOf('dog', doc.Text.GetText(0, doc.Text.Length)));
  finally
    doc.Free;
  end;
end;

{ In a lazily read RTF the walk parses each interval about once - the
  range's matches are found and replaced while its intervals are resident - and between its
  parts the residency goes back to the loader's bound; undone, the file saves as it was. }
procedure TTyRichFindTest.TestReplaceParsesEachIntervalOnce;
var
  m: TMemoryStream;
  s: RawByteString;
  doc: TTyRichDocument;
  load: TTyRtfLoad;
  k, n, skipped, parts, parsed0: Integer;
  limited: Boolean;
  bytes: TBytes;
begin
  m := TMemoryStream.Create;
  try
    s := Rtf('{|rtf1|ansi|ansicpg1252|deff0{|fonttbl{|f0|fswiss Arial;}}|pard ');
    m.WriteBuffer(s[1], Length(s));
    k := 0;
    while m.Size < 3 * MB do
    begin
      if k mod 7 = 0 then s := Rtf('line ') + IntToStr(k) + Rtf(' with a {|b zebra} in it|par') + #13#10
      else s := Rtf('line ') + IntToStr(k) + Rtf(' of some {|i filler} words|par') + #13#10;
      m.WriteBuffer(s[1], Length(s));
      Inc(k);
    end;
    s := '}';
    m.WriteBuffer(s[1], 1);
    bytes := nil;
    SetLength(bytes, m.Size);
    Move(m.Memory^, bytes[0], m.Size);
  finally
    m.Free;
  end;
  doc := LoadRtf(bytes, False);
  try
    load := TyRichRtfLoadOf(doc);
    AssertTrue('more intervals than stay parsed', load.IntervalCount > 2 * load.MaxResidentIntervals);
    parsed0 := load.ParseCount;
    n := ReplaceInParts(doc, 'zebra', 'giraffe', [rfoMatchCase], 64 * 1024, skipped, parts, limited);
    AssertEquals('every one', (k + 6) div 7, n);
    AssertTrue(Format('each interval parsed about once (%d for %d)',
      [load.ParseCount - parsed0, load.IntervalCount]),
      load.ParseCount - parsed0 <= load.IntervalCount + 2);
    AssertTrue(Format('the residency back to the bound (%d of %d)',
      [load.ResidentIntervals, load.MaxResidentIntervals]),
      load.ResidentIntervals <= load.MaxResidentIntervals + 1);
    doc.Undo;
    AssertTrue('undone and saved: the file', SameBytes(bytes, SaveRtf(doc)));
  finally
    doc.Free;
  end;
end;

{ The paragraphs of the table row paragraph AIndex is in, added to AList. }
procedure RowParas(ADoc: TTyRichDocument; AIndex: Integer; AList: TStringList);
var
  cell, c: TTyRichCell;
  i: Integer;
begin
  ADoc.BeginRead;
  try
    cell := ADoc.CellAt(AIndex);
    if cell = nil then Exit;
    i := AIndex;
    while i > 0 do
    begin
      c := ADoc.CellAt(i - 1);
      if (c = nil) or (c.Row <> cell.Row) then Break;
      Dec(i);
    end;
    while i < ADoc.Text.ParaCount do
    begin
      c := ADoc.CellAt(i);
      if (c = nil) or (c.Row <> cell.Row) then Break;
      AList.Add(IntToStr(i));
      Inc(i);
    end;
  finally
    ADoc.EndRead;
  end;
end;

{ Every paragraph's text and where it is (a row's number and the cell's, or none), for a
  comparison of the model with the file it saves. }
function Layout(ADoc: TTyRichDocument): string;
var
  i: Integer;
  c: TTyRichCell;
  rows: TFPList;
begin
  Result := '';
  rows := TFPList.Create;
  ADoc.BeginRead;
  try
    for i := 0 to ADoc.Text.ParaCount - 1 do
    begin
      c := ADoc.CellAt(i);
      Result := Result + '"' + ADoc.Text.GetText(ADoc.Text.ParaStart(i), ADoc.Text.ParaLength(i)) + '"';
      if c = nil then
        Result := Result + '[-] '
      else
      begin
        if rows.IndexOf(c.Row) < 0 then rows.Add(c.Row);
        Result := Result + Format('[r%d c%d] ', [rows.IndexOf(c.Row), c.Index]);
      end;
    end;
  finally
    ADoc.EndRead;
    rows.Free;
  end;
end;

{ The table-edge rule: a match whose deletion would join a paragraph with one in
  another cell, another row, or a table it was not in - one that ends with a cell's or a row's
  last paragraph end, or with the paragraph end before a table, or between two tables - is left
  and counted; what the document holds is what its file says (saved and read again, the same
  paragraphs in the same cells), and undone it is the file. Read whole and lazily. }
procedure TTyRichFindTest.TestReplaceKeepsTheTableEdgeRule;
const
  Head = '{|rtf1|ansi|ansicpg1252|deff0{|fonttbl{|f0|fswiss Arial;}}|pard ';
  Row = '|trowd|cellx2000|cellx4000|intbl ';
  Two = Row + 'a|cell b|cell|row |pard mid|par ' + Row + 'c|cell d|cell|row |pard after|par}';
type
  TCase = record
    Name, Body, Needle, Repl: RawByteString;
    Replaced, Skipped: Integer;
  end;
var
  cases: array[0..9] of TCase;
  i, lazy, n, skipped: Integer;
  bytes: TBytes;
  doc, again: TTyRichDocument;
  before: string;

  procedure Put(AIndex: Integer; const AName, ABody, ANeedle, ARepl: RawByteString;
    AReplaced, ASkipped: Integer);
  begin
    cases[AIndex].Name := AName;
    cases[AIndex].Body := ABody;
    cases[AIndex].Needle := ANeedle;
    cases[AIndex].Repl := ARepl;
    cases[AIndex].Replaced := AReplaced;
    cases[AIndex].Skipped := ASkipped;
  end;

begin
  // empty paragraphs before a table, and a paragraph end after an x
  Put(0, 'empty paragraphs removed before a table', 'before|par |par ' + Row +
    'a|cell b|cell|row |pard after|par}', #10#10, #10, 0, 1);
  Put(1, 'a cell''s last paragraph end', 'before|par ' + Row + 'ax|cell b|cell|row |pard after|par}',
    'x'#10, 'y', 0, 1);
  // a cell's empty last paragraph, a row's end, the end before a table
  Put(2, 'a cell''s empty last paragraph', 'before|par ' + Row + 'a|par |cell b|cell|row |pard after|par}',
    #10#10, #10, 0, 1);
  Put(3, 'a row''s last paragraph end', 'before|par ' + Row + 'a|cell bx|cell|row |pard after|par}',
    'x'#10, 'y', 0, 1);
  Put(4, 'the paragraph end before a table', 'before|par ' + Row + 'a|cell b|cell|row |pard after|par}',
    'before'#10, 'B ', 0, 1);
  // between two tables: into the second, out of the first
  Put(5, 'between two tables, into the second', Two, 'mid'#10, 'M', 0, 1);
  Put(6, 'between two tables, out of the first', Two, 'b'#10'mid', 'B', 0, 1);
  // every paragraph end by a space: the one between two plain paragraphs only
  Put(7, 'every paragraph end', 'before|par ' + Row + 'a|cell b|cell|row ' + Row +
    'c|cell d|cell|row |pard after|par last|par}', #10, ' ', 1, 5);
  // inside a cell, and whole rows: allowed
  Put(8, 'inside a cell', 'before|par ' + Row + 'a|par x|cell b|cell|row |pard after|par}',
    'a'#10'x', 'A', 1, 0);
  Put(9, 'a word in a cell', 'before|par ' + Row + 'ax|cell b|cell|row |pard after|par}', 'x', 'y', 1, 0);
  for i := 0 to High(cases) do
    for lazy := 0 to 1 do
    begin
      bytes := BytesOf(Rtf(Head + cases[i].Body));
      doc := LoadRtf(bytes, lazy = 0);
      try
        before := Layout(doc);
        n := ReplaceIn(doc, cases[i].Needle, cases[i].Repl, [], skipped);
        AssertEquals(cases[i].Name + ': replaced', cases[i].Replaced, n);
        AssertEquals(cases[i].Name + ': left and counted', cases[i].Skipped, skipped);
        if n = 0 then
          AssertEquals(cases[i].Name + ': nothing moved', before, Layout(doc));
        // what is saved is what the model holds
        again := LoadRtf(SaveRtf(doc), True);
        try
          AssertEquals(cases[i].Name + ': saved and read again', Layout(doc), Layout(again));
        finally
          again.Free;
        end;
        if n > 0 then
        begin
          doc.Undo;
          AssertTrue(cases[i].Name + ': undone, the file', SameBytes(bytes, SaveRtf(doc)));
        end;
      finally
        doc.Free;
      end;
    end;
end;

procedure TTyRichFindTest.TestReplaceUndoneSavesTheFile;
const
  Names: array[0..3] of string = ('hand-word-zh.rtf', 'wp-zh-table.rtf', 're-zh-mixed.rtf',
    'hand-word-list.rtf');
var
  n: Integer;
  name: string;
  bytes, saved: TBytes;
  doc: TTyRichDocument;
  f: TTyRichFinder;
  pos: array of TTyRichPos;
  i: Integer;
  info: TTyRtfWriteInfo;
  m: TBytesStream;
  hitParas: TStringList;
  skipped, parts: Integer;
  limited: Boolean;
begin
  for n := 0 to High(Names) do
  begin
    name := Names[n];
    bytes := ReadFileBytes(FixtureDir('rtf') + name);
    doc := LoadRtf(bytes, False);
    hitParas := TStringList.Create;
    try
      hitParas.Sorted := True;
      hitParas.Duplicates := dupIgnore;
      f := TTyRichFinder.Create(doc, 'e', []);
      try
        f.Collect := True;
        f.Run;
        pos := nil;
        SetLength(pos, f.MatchCount);
        // the last first
        for i := 0 to f.MatchCount - 1 do
        begin
          pos[i] := f.Match(f.MatchCount - 1 - i);
          hitParas.Add(IntToStr(doc.Text.ParaOfPos(pos[i])));
          // a row is written whole: its other cells' paragraphs may be written with it
          RowParas(doc, doc.Text.ParaOfPos(pos[i]), hitParas);
        end;
      finally
        f.Free;
      end;
      AssertTrue(name + ': matches', Length(pos) > 0);
      AssertEquals(name + ': replaced', Length(pos), ReplaceInParts(doc, 'e', 'EE', [], 256, skipped,
        parts, limited));
      m := TBytesStream.Create;
      try
        TyRichSaveRtf(doc, m, info);
      finally
        m.Free;
      end;
      AssertTrue(Format('%s: only the paragraphs (rows) with a replacement are written from the model (%d of %d)',
        [name, info.RewrittenParas, hitParas.Count]), info.RewrittenParas <= hitParas.Count);
      doc.Undo;
      saved := SaveRtf(doc);
      AssertTrue(name + ': undone, the file', SameBytes(bytes, saved));
      doc.Redo;
      doc.Undo;
      AssertTrue(name + ': redone and undone, the file', SameBytes(bytes, SaveRtf(doc)));
    finally
      hitParas.Free;
      doc.Free;
    end;
  end;
end;

{ A replace of [AStart, AStart + ALength) driven as the control's turns drive it: searched in
  pieces of ABudget units (Prepare), each part run as it is found - at most AMaxCalls searches,
  so a walk that would never end fails here instead of hanging. True: it finished. }
function ReplaceBudgeted(ADoc: TTyRichDocument; const ANeedle, ARepl: UTF8String;
  AOptions: TTyRichFindOptions; AStart, ALength: TTyRichPos; ARange, ABudget: Int64;
  AMaxCalls: Integer; out ATally: TTyRichReplaceTally): Boolean;
var
  cmd: TTyRichReplaceAllCommand;
  ran: Boolean;
  calls: Integer;
begin
  ATally := Default(TTyRichReplaceTally);
  cmd := TTyRichReplaceAllCommand.Create(ADoc, ANeedle, ARepl, AOptions, AStart, ALength);
  cmd.Tally := @ATally;
  cmd.RangeChars := ARange;
  ran := False;
  calls := 0;
  Result := False;
  try
    while calls < AMaxCalls do
    begin
      if not cmd.Ready then
      begin
        Inc(calls);
        cmd.Prepare(ABudget);
        if cmd.Finished then
        begin
          Result := True;
          Break;
        end;
        Continue;
      end;
      if not ran then
      begin
        ran := True;
        if not ADoc.Execute(cmd) then Break;
      end
      else if not ADoc.ExecutePart(cmd) then
        Break;
      if cmd.Finished then
      begin
        Result := True;
        Break;
      end;
    end;
  finally
    if not ran then cmd.Free;
  end;
end;

function Unix(const S: RawByteString): RawByteString;
begin
  Result := StringReplace(S, #13#10, #10, [rfReplaceAll]);
end;

{ A needle with a paragraph end that is longer than the range a replace reads at a time: the
  replace ends (it took nothing, and went round for ever) - searched in pieces as the turns
  do it, and all at once as the synchronous call does it. }
procedure TTyRichFindTest.TestALongNeedleWithAParagraphEndEnds;
var
  doc: TTyRichDocument;
  needle, s: RawByteString;
  tally: TTyRichReplaceTally;
  cmd: TTyRichReplaceAllCommand;
  k: Integer;
begin
  needle := StringOfChar('a', 300) + #10 + StringOfChar('b', 300);
  s := 'x' + #10 + needle + #10 + 'y' + #10 + needle;
  for k := 0 to 1 do
  begin
    doc := TextDoc(s);
    try
      if k = 0 then
        AssertTrue('in pieces: it ends', ReplaceBudgeted(doc, needle, 'z', [], 0, -1, 64, 64,
          10000, tally))
      else
      begin
        tally := Default(TTyRichReplaceTally);
        cmd := TTyRichReplaceAllCommand.Create(doc, needle, 'z', []);
        cmd.Tally := @tally;
        cmd.RangeChars := 64;
        cmd.AllAtOnce := True;
        doc.Execute(cmd);
      end;
      AssertFalse(Format('%d: not failed', [k]), tally.Failed);
      AssertEquals(Format('%d: both replaced', [k]), 2, tally.Replaced);
      AssertEquals(Format('%d: the text', [k]), 'x' + #10 + 'z' + #10 + 'y' + #10 + 'z',
        Unix(doc.Text.GetText(0, doc.Text.Length)));
      doc.Undo;
      AssertEquals(Format('%d: undone', [k]), s, Unix(doc.Text.GetText(0, doc.Text.Length)));
    finally
      doc.Free;
    end;
  end;
end;

{ A replace stopped at its limit tells where it stopped (right behind the last match it dealt
  with, in the text as it now is); run again from there, it replaces the rest and nothing
  twice - also where the replacement holds the needle ("Mr" by "Mr.", ".<end>" by
  ".<end><end>", "xx" by "xxx"), which a run again from the start replaced again and again.
  In a range too:
  what lies outside it stays. }
procedure TTyRichFindTest.TestARerunGoesOnWhereItStopped;
var
  doc: TTyRichDocument;
  s, want, rest: RawByteString;
  i, runs, total, k, span: Integer;
  tally: TTyRichReplaceTally;
  at, len, from, upto: TTyRichPos;
  needle, repl: RawByteString;
begin
  for k := 0 to 3 do
  begin
    s := '';
    want := '';
    case k of
      3:
        begin
          // (a place a character off would find a match in the last replacement again)
          for i := 0 to 1999 do s := s + 'xxxxxxxx' + #10;
          needle := 'xx';
          repl := 'xxx';
        end;
      0, 2:
        begin
          for i := 0 to 1999 do s := s + 'Mr Smith met Mr Jones' + #10;
          needle := 'Mr';
          repl := 'Mr.';
        end;
    else
      for i := 0 to 599 do s := s + 'Line ' + IntToStr(i) + '.' + #10;
      needle := '.' + #10;
      repl := '.' + #10 + #10;
    end;
    if k = 2 then
    begin
      // lines 100 .. 1099 only
      from := 100 * 22;
      upto := 1100 * 22;
      want := Copy(s, 1, from) + StringReplace(Copy(s, from + 1, upto - from), needle, repl,
        [rfReplaceAll]) + Copy(s, upto + 1, MaxInt);
    end
    else
    begin
      from := 0;
      upto := -1;
      want := StringReplace(s, needle, repl, [rfReplaceAll]);
    end;
    doc := TextDoc(s);
    try
      doc.MaxUndoBytes := 4096;
      at := from;
      if upto < 0 then len := -1 else len := upto - from;
      runs := 0;
      total := 0;
      repeat
        Inc(runs);
        AssertTrue(Format('%d: run %d ends', [k, runs]), ReplaceBudgeted(doc, needle, repl, [],
          at, len, 1024, 4096, 100000, tally));
        AssertFalse('not failed', tally.Failed);
        Inc(total, tally.Replaced);
        if tally.Limited then
        begin
          AssertTrue(Format('%d: run %d replaced some', [k, runs]), tally.Replaced > 0);
          AssertTrue('on from further on', tally.ResumeAt > at);
          at := tally.ResumeAt;
          len := tally.ResumeLength;
          if upto < 0 then AssertEquals('to the end', -1, len);
        end;
      until not tally.Limited or (runs >= 400);
      AssertFalse(Format('%d: through in %d runs', [k, runs]), tally.Limited);
      AssertTrue(Format('%d: more than one run (%d)', [k, runs]), runs > 2);
      rest := Unix(doc.Text.GetText(0, doc.Text.Length));
      AssertEquals(Format('%d: each replaced once', [k]), want, rest);
      if upto < 0 then span := MaxInt else span := upto - from;
      AssertEquals(Format('%d: the count', [k]), CountOf(needle, Copy(s, from + 1, span)), total);
    finally
      doc.Free;
    end;
  end;
end;

{ A paragraph read over many steps is fetched once - gathered from its pieces after an edit,
  or decoded from a lazily read file - and kept while the scan is inside it: the bytes handed to
  the finder are about the paragraph's, not the steps' times it (a 20 MB line after one typed
  character took 31 s). A start inside a long paragraph passes the characters before it in
  pieces of a step's budget, not in one go. }
procedure TTyRichFindTest.TestAParagraphIsFetchedOnce;
const
  CBudget = 64 * 1024;
var
  doc: TTyRichDocument;
  s: RawByteString;
  sb: TStringBuilder;
  f: TTyRichFinder;
  r: TTyRichFindResult;
  steps, i: Integer;
  size, want: Int64;
begin
  sb := TStringBuilder.Create;
  try
    while sb.Length < 4 * MB do sb.Append('lorem ipsum dolor sit amet ');
    sb.Append('zebra');
    s := sb.ToString;
  finally
    sb.Free;
  end;
  // one line of 4 MB, then one character typed in it: several pieces
  doc := TextDoc(s);
  try
    AssertTrue(doc.Execute(TTyRichInsertText.Create(10, 'q')));
    size := doc.Text.ParaLength(0);
    want := size - 5;
    f := TTyRichFinder.Create(doc, 'zebra', []);
    try
      steps := 0;
      repeat
        r := f.Step(CBudget);
        Inc(steps);
      until (r <> rfrMore) or (steps > 10000);
      AssertEquals('found at the end', want, f.MatchPos);
      AssertTrue(Format('in many steps (%d)', [steps]), steps > 20);
      AssertTrue(Format('the line fetched once (%d bytes for %d)', [f.FetchedBytes, size]),
        f.FetchedBytes <= 2 * size);
    finally
      f.Free;
    end;
    // a start in its middle: what lies before is passed in pieces too
    f := TTyRichFinder.Create(doc, 'zebra', [rfoWholeWord], size div 2);
    try
      r := f.Step(4096);
      AssertTrue('not found in the first step', r = rfrMore);
      AssertTrue(Format('the first step passed a budget''s worth (%d)', [f.PassedBytes]),
        f.PassedBytes <= 8 * 4096 + 16);
      steps := 1;
      repeat
        r := f.Step(CBudget);
        Inc(steps);
      until (r <> rfrMore) or (steps > 10000);
      AssertEquals('found from the middle', want, f.MatchPos);
      AssertEquals('everything before the start passed once', size div 2, f.PassedBytes);
      AssertTrue(Format('...the line fetched once (%d)', [f.FetchedBytes]), f.FetchedBytes <= 2 * size);
    finally
      f.Free;
    end;
    // the same unbounded (as a replace's search in one go): one piece, not a character at a time
    f := TTyRichFinder.Create(doc, 'zebra', []);
    try
      f.Collect := True;
      r := f.CollectRange(0, 0, size div 2, -1, -1);
      AssertTrue('unbounded: read through', r = rfrFound);
      AssertEquals('...the match', want, f.Match(0));
      AssertEquals('...everything before the start passed', size div 2, f.PassedBytes);
      AssertTrue(Format('...in a piece or two (%d)', [f.Pieces]), f.Pieces <= 2);
    finally
      f.Free;
    end;
    // the text changed while the scan stands in the paragraph: what it kept is not read on
    f := TTyRichFinder.Create(doc, 'xyzzy', []);
    try
      for i := 1 to 3 do AssertTrue('not found yet', f.Step(CBudget) = rfrMore);
      AssertTrue(doc.Execute(TTyRichInsertText.Create(size - 100, 'xyzzy')));
      repeat
        r := f.Step(CBudget);
      until r <> rfrMore;
      AssertEquals('what the change brought is found', size - 100, f.MatchPos);
    finally
      f.Free;
    end;
  finally
    doc.Free;
  end;
  // an RTF paragraph of 2 MB read lazily: decoded once, not once a step
  sb := TStringBuilder.Create;
  try
    sb.Append(Rtf('{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}|pard first|par '));
    i := 0;
    while sb.Length < 2 * MB do
    begin
      sb.Append(Rtf('words of text {|b bold} and {|i more} here '));
      Inc(i);
    end;
    sb.Append(Rtf('zebra|par last|par}'));
    s := sb.ToString;
  finally
    sb.Free;
  end;
  doc := LoadRtf(BytesOf(s), False);
  try
    size := doc.Text.ParaLength(1);
    f := TTyRichFinder.Create(doc, 'zebra', []);
    try
      steps := 0;
      repeat
        r := f.Step(CBudget);
        Inc(steps);
      until (r <> rfrMore) or (steps > 10000);
      AssertEquals('found in the paragraph', doc.Text.ParaStart(1) + size - 5, f.MatchPos);
      AssertTrue(Format('in many steps (%d)', [steps]), steps > 10);
      AssertTrue(Format('decoded once (%d bytes for %d)', [f.FetchedBytes, size]),
        f.FetchedBytes <= 2 * size + 64);
    finally
      f.Free;
    end;
  finally
    doc.Free;
  end;
end;

{ One paragraph with matches all through it (a one-line file): the replace takes them a part's
  worth at a time - its finder stops after them, and goes on in the paragraph's text after the
  part - so it lists no more than a part's matches, and what the step keeps stays a few bytes
  a match however long the paragraph (a list of every match counted toward the limit). Also
  with a replacement that splits the paragraph, and undone. }
procedure TTyRichFindTest.TestOneHugeParagraphKeepsNoListOfItsMatches;
var
  doc: TTyRichDocument;
  s, before: RawByteString;
  sb: TStringBuilder;
  i, n, skipped, parts: Integer;
  limited: Boolean;
begin
  sb := TStringBuilder.Create;
  try
    for i := 0 to 199999 do sb.Append('a,');
    s := sb.ToString;
  finally
    sb.Free;
  end;
  doc := TextDoc(s);
  try
    n := ReplaceInParts(doc, ',', ';', [], 1 shl 20, skipped, parts, limited);
    AssertEquals('every comma', 200000, n);
    AssertTrue(Format('in parts (%d)', [parts]), parts >= 200000 div CRichReplacePartMatches);
    AssertEquals('none left', 0, CountOf(',', doc.Text.GetText(0, doc.Text.Length)));
    AssertTrue(Format('the step: no list of every match (%d bytes)', [doc.HistoryBytes]),
      doc.HistoryBytes < 400 * 1024);
    doc.Undo;
    AssertEquals('undone', s, doc.Text.GetText(0, doc.Text.Length));
  finally
    doc.Free;
  end;
  // a replacement with a paragraph end: the paragraph splits under the finder's feet
  s := Copy(s, 1, 2 * 30000);
  doc := TextDoc(s);
  try
    before := doc.Text.GetText(0, doc.Text.Length);
    n := ReplaceInParts(doc, ',', ';' + #10, [], 1 shl 20, skipped, parts, limited);
    AssertEquals('split: every comma', 30000, n);
    AssertEquals('...a paragraph each', 30001, doc.Text.ParaCount);
    AssertEquals('...the text', StringReplace(s, ',', ';' + #10, [rfReplaceAll]),
      Unix(doc.Text.GetText(0, doc.Text.Length)));
    doc.Undo;
    AssertEquals('...undone', before, doc.Text.GetText(0, doc.Text.Length));
  finally
    doc.Free;
  end;
end;

{ The lazily read document's unparsed paragraphs as they were before a find decoded any (so
  that the next find meets their bytes again). }
procedure ForgetDecodes(ADoc: TTyRichDocument);
var
  i: Integer;
  src, n: Int64;
begin
  for i := 0 to ADoc.Text.ParaCount - 1 do
    if ADoc.Text.ParaLazySource(i, src, n) then ADoc.Text.ForgetDecoded(src);
end;

{ Every pair of the destinations the reader tells apart (a word of each meaning of its own word
  table, an unknown starred word, an unknown plain word, and an ordinary formatting group): one
  inside the other - text in the outer group before the inner, after it, and a paragraph end
  inside the inner one - and every piece of one to four characters of the text the whole read
  gives, searched in the whole read (nothing lazy) and in the lazy read: the two agree. A
  destination added to the reader that the lazy read takes otherwise than the whole read -
  one in which a paragraph can end so that the next one begins inside it, say - is found
  here, whatever it is. The first shape for every pair; the other two for a fixed sample of
  pairs.

  And the ways a paragraph can begin, at each place of the two groups: a paragraph end, a
  cell end, and a row end right after the last cell's end (which ends no paragraph and still
  moves where the next one begins) - before the outer group, between the two braces, inside
  the inner group and after it - for every kind as the outer group of an ordinary one, as the
  inner group of an ordinary one, and inside upr (in ud inside upr a paragraph does begin
  inside a destination: the lazy read must go on there as the whole read did).

  And a lead byte of a double-byte font left waiting where a group ends - in every kind
  alone, and in one inside a field, an ordinary group or upr, and an ordinary group inside
  every kind: the reader keeps a waiting half past the brace whatever it makes of the group,
  so a group whose own text is none of the paragraph's can still put a ? into it (a field's
  result does). }
procedure TTyRichFindTest.TestEveryPairOfDestinations;
const
  CSampleEvery = 3;
  CEndings: array[0..2] of RawByteString = ('|par ', '|cell ', '|row ');
  CTable = '|trowd|cellx2000|cellx4000|pard|intbl ';
var
  words: TStringArray;
  i, j, shape, files, needles, k, len, p1, place, ending: Integer;
  w1, w2, body, e, src: RawByteString;
  full, lazy: TTyRichDocument;
  codes: TTyRichCodeArray;
  seen: TStringList;
  needle: UTF8String;
  want, got: string;

  function Word(const AName: string): RawByteString;
  begin
    if AName = '*' then Result := '|*|zzqqx'
    else if AName = '-' then Result := '|zzqqy'
    else if AName = '.' then Result := '|b'
    else Result := '|' + AName;
  end;

  function Utf8Of(AFrom, ALen: Integer): UTF8String;
  var
    q: Integer;
  begin
    Result := '';
    for q := AFrom to AFrom + ALen - 1 do
      if codes[q] = TyRichFindParaEnd then Result := Result + #10
      else Result := Result + U([codes[q]]);
  end;

begin
  words := TyRtfDestinationWords;
  AssertTrue('the reader names its destinations', Length(words) > 15);
  SetLength(words, Length(words) + 3);
  words[High(words) - 2] := '*';
  words[High(words) - 1] := '-';
  words[High(words)] := '.';
  files := 0;
  needles := 0;
  seen := TStringList.Create;
  try
    seen.Sorted := True;
    seen.Duplicates := dupIgnore;
    for i := 0 to High(words) do
      for j := 0 to High(words) do
        for shape := 0 to 16 do
        begin
          if (shape in [1, 2]) and (((i * Length(words) + j) mod CSampleEvery) <> 0) then Continue;
          if (shape in [3..14]) and not ((words[i] = '.') or (words[j] = '.') or (words[i] = 'upr')) then
            Continue;
          // (the kind alone: once, with the last inner one)
          if (shape = 15) and (j <> High(words)) then Continue;
          if (shape = 16) and not ((words[i] = '.') or (words[j] = '.') or (words[i] = 'upr') or
            (words[i] = 'field')) then
            Continue;
          w1 := Word(words[i]);
          w2 := Word(words[j]);
          case shape of
            0: body := 'a{' + w1 + ' b{' + w2 + ' xyz}}c';
            1: body := 'a{' + w1 + '{' + w2 + ' xyz}b}c';
            2: body := 'a{' + w1 + ' b{' + w2 + ' x|par yz}}c';
            15: body := 'a{' + w1 + ' q|''e9}c';
            16: body := 'a{' + w1 + '{' + w2 + ' q|''e9}}c';
          else
            place := (shape - 3) mod 4;
            ending := (shape - 3) div 4;
            e := CEndings[ending];
            if ending < 2 then
              case place of
                0: body := 'a' + e + 'q{' + w1 + ' b{' + w2 + ' xyz}m}c';
                1: body := 'a{' + w1 + ' b' + e + 'q{' + w2 + ' xyz}m}c';
                2: body := 'a{' + w1 + ' b{' + w2 + ' x' + e + 'yz}m}c';
              else
                body := 'a{' + w1 + ' b{' + w2 + ' xyz}m' + e + 'q}c';
              end
            else
              // (nothing between the last cell's end and the row's end but the braces)
              case place of
                0: body := 'a|cell ' + e + 'q{' + w1 + ' b{' + w2 + ' xyz}m}c';
                1: body := 'a|cell{' + w1 + e + 'q{' + w2 + ' xyz}m}c';
                2: body := 'a|cell{' + w1 + '{' + w2 + e + 'yz}m}c';
              else
                body := 'a|cell{' + w1 + '{' + w2 + '}' + e + 'q}c';
              end;
            if ending > 0 then body := CTable + body;
          end;
          if shape >= 15 then
            // (a double-byte default font: E9 is a lead byte)
            src := Rtf('{|rtf1|ansi|ansicpg936|deff0{|fonttbl{|f0|fnil|fcharset134 SimSun;}}' +
              '|pard filler|par ' + body + '|par}')
          else
            src := Rtf('{|rtf1|ansi|ansicpg1252|deff0{|fonttbl{|f0|fswiss Arial;}}' +
              '|pard filler|par ' + body + '|par}');
          full := LoadRtf(BytesOf(src), True);
          lazy := nil;
          try
            codes := TyRichFindCodes(full.Text.GetText(0, full.Text.Length));
            // (the pieces that reach past the first paragraph, which every file shares)
            p1 := 0;
            while (p1 < Length(codes)) and (codes[p1] <> TyRichFindParaEnd) do Inc(p1);
            seen.Clear;
            for k := 0 to High(codes) do
              for len := 1 to 4 do
              begin
                if (k + len > Length(codes)) or (k + len - 1 <= p1) then Continue;
                needle := Utf8Of(k, len);
                seen.Add(needle);
              end;
            if seen.Count = 0 then Continue;
            Inc(files);
            lazy := LoadRtf(BytesOf(src), False);
            for k := 0 to seen.Count - 1 do
            begin
              needle := seen[k];
              if Pos(#$EF#$BF#$BC, needle) > 0 then Continue;
              Inc(needles);
              want := WholePositions(full, needle, []);
              ForgetDecodes(lazy);
              got := Positions(lazy, needle, []);
              if got <> want then
                Fail(Format('%s / %s, shape %d, "%s": lazily: %s, read whole: %s',
                  [words[i], words[j], shape, needle, got, want]));
            end;
          finally
            lazy.Free;
            full.Free;
          end;
        end;
  finally
    seen.Free;
  end;
  AssertTrue(Format('files %d, needles %d', [files, needles]),
    (files > 1500) and (needles > 15000));
end;

{ Tables made by a generator of fixed seed whose groups, destinations, cell and row words are
  the reader's - and among them, often, a destination read in part that opens right after a
  cell's end and holds the row's end: the row end then ends no paragraph (it is given to the
  last cell) and the next paragraph begins inside the destination, where its bytes alone do
  not say what they read as. Needles of one to four characters from the whole read's own
  text (so each has a place), plain, match case and whole word: the whole read (nothing
  lazy) and the lazy read agree. }
procedure TTyRichFindTest.TestGeneratedRowsThatEndInsideADestination;
const
  CFiles = 3000;
  Head: array[0..2] of RawByteString = (
    '{|rtf1|ansi|ansicpg1251|deff0{|fonttbl{|f0|fnil|fcharset204 Arial Cyr;}{|f1|fswiss Arial;}' +
    '{|f2|ftech|fcharset2 Symbol;}{|f3|fnil|fcharset161 Greek;}}|pard ',
    '{|rtf1|ansi|ansicpg1252|deff1{|fonttbl{|f0|fnil|fcharset204 Arial Cyr;}{|f1|fswiss Arial;}' +
    '{|f2|ftech|fcharset2 Symbol;}{|f3|fnil|fcharset161 Greek;}}|pard ',
    // (a double-byte default font: a byte may be left waiting for its second)
    '{|rtf1|ansi|ansicpg936|deff0{|fonttbl{|f0|fnil|fcharset134 SimSun;}{|f1|fswiss Arial;}' +
    '{|f2|ftech|fcharset2 Symbol;}{|f3|fnil|fcharset128 MS Mincho;}}|pard ');
var
  seed: QWord;
  n, files, needles, tries, len, i, o: Integer;
  body: RawByteString;
  bytes: TBytes;
  full, lazy: TTyRichDocument;
  codes: TTyRichCodeArray;
  needle: UTF8String;
  opts: TTyRichFindOptions;
  want, got: string;
  seen: TStringList;
  bad: Boolean;

  function Rnd(ACount: Integer): Integer;
  begin
    seed := seed xor (seed shl 13);
    seed := seed xor (seed shr 7);
    seed := seed xor (seed shl 17);
    Result := Integer((seed shr 11) mod QWord(ACount));
  end;

  function Pick(const A: array of RawByteString): RawByteString;
  begin
    Result := A[Rnd(Length(A))];
  end;

  function Gen(ADepth: Integer): RawByteString;
  var
    count, q, kind: Integer;
  begin
    Result := '';
    count := 1 + Rnd(5);
    for q := 1 to count do
    begin
      kind := Rnd(100);
      if (ADepth < 3) and (Rnd(6) = 0) then
      begin
        // the destination read in part, opened after a cell's end, the row's end inside it
        Result := Result + '|cell{|upr ' + Pick(['', 'J', 'ab']) + '{|*|ud' +
          Pick(['|row ', '|row |pard ', ' |row ', '|cell |row ']) + Gen(ADepth + 2) + '}' +
          Pick(['J', '', 'xa']) + Gen(ADepth + 1) + '}';
        Continue;
      end;
      if Rnd(2) = 0 then kind := 80;
      if Rnd(4) = 0 then
      begin
        Result := Result + Pick(['|trowd|cellx2000|cellx4000|intbl ', '|cell ', '|cell ', '|row ',
          '|pard ', '|nestcell ', '|intbl ', '|itap2 ',
          '|trowd|clmgf|cellx2000|clmrg|cellx4000|intbl ', '|nestrow ',
          '{|*|nesttableprops|trowd|cellx1000|nestrow}', '{|nonesttables|par}', '|itap1 ']);
        Continue;
      end;
      if kind < 22 then
        Result := Result + Pick(['a', 'b', 'x', '?', ' ', 'ab', 'xa', 'ffd8', 'A', 'B'])
      else if kind < 36 then
        Result := Result + Pick(['|u-10179', '|u-8704', '|u8212', '|u65', '|u-10178', '|u128512',
          '|u20013', '|u', '|u0', '|u97']) + Pick(['?', '', '', ' ', '|''3f', '??', ' ?'])
      else if kind < 46 then
        Result := Result + Pick(['|''d6', '|''d0', '|''ce', '|''c4', '|''61', '|''0a', '|''e9',
          '|''d6|''d0', '|''4', '|''81', '|''40', '|''09'])
      else if kind < 51 then
        Result := Result + Pick(['|uc0 ', '|uc1 ', '|uc2 ', '|uc1'])
      else if kind < 57 then
        Result := Result + Pick(['|f0 ', '|f1 ', '|f2 ', '|f3 ', '|f9 ', '|plain ', '|b ', '|b0'])
      else if kind < 66 then
        Result := Result + Pick(['|tab ', '|line ', '|emdash ', '|~', '|_', '|-', '|{', '|}', '||',
          '|*', '|:', '|bullet', '|chpgn ', '|sect ', '|page ', '|column '])
      else if kind < 70 then
        Result := Result + Pick(['|bin1 x', '|bin0 ', '|bin1 }', '|bin1 {', '|bin2 ab', '|bin'])
      else if kind < 73 then
        Result := Result + Pick([#13#10, #10, #0 + 'a', #1])
      else if kind < 76 then
        Result := Result + Pick(['|par ', '|par', '|' + #10, '|par '])
      else if (kind < 97) and (ADepth < 5) then
        Result := Result + '{' + Pick(['', '', '', ' ', '|b', '|b ', '|*|i', '|*|i ', '|i ',
          '|pict', '|*|pict ', '|pict|wmetafile8 ', '|field', '|*|fldinst ', '|fldinst ',
          '|fldrslt ', '|listtext ', '|pntext ', '|*|pn ', '|pntxtb ', '|*|unk ', '|unk ',
          '|object ', '|*|objdata ', '|nonshppict', '|*|shppict', '|info', '|stylesheet',
          '|footnote ', '|header ', '|b ', '|*', '|*|*|pict ', '|colortbl', '|*|bkmkstart ',
          '|datafield ', '|*|datafield ', '|result ', '|shp', '|*|shpinst', '|shptxt ',
          '|*|oldcprops ', '|*|nesttableprops ', '|listtable', '|f1 ', '|uc0 ', '|u-10179?',
          #13#10 + '|pict ']) + Gen(ADepth + 1) + '}'
      else
        Result := Result + Pick(['a', 'b', 'x']);
    end;
  end;

  function Utf8Of(AFrom, ALen: Integer): UTF8String;
  var
    q: Integer;
  begin
    Result := '';
    for q := AFrom to AFrom + ALen - 1 do
      if codes[q] = TyRichFindParaEnd then Result := Result + #10
      else Result := Result + U([codes[q]]);
  end;

  function HexOf(const S: UTF8String): string;
  var
    q: Integer;
  begin
    Result := '';
    for q := 1 to Length(S) do Result := Result + IntToHex(Ord(S[q]), 2);
  end;

begin
  seed := 88172645463325252;
  files := 0;
  needles := 0;
  seen := TStringList.Create;
  try
    seen.Sorted := True;
    seen.Duplicates := dupIgnore;
    for n := 1 to CFiles do
    begin
      body := Gen(0);
      bytes := BytesOf(Rtf(Head[Rnd(3)] + 'filler|par |trowd|cellx2000|cellx4000|pard|intbl ' +
        body + '|par zz|par}'));
      full := LoadRtf(bytes, True);
      lazy := nil;
      try
        codes := TyRichFindCodes(full.Text.GetText(0, full.Text.Length));
        lazy := LoadRtf(bytes, False);
        AssertEquals(Format('file %d: the lazy read''s text is the whole read''s', [n]),
          full.Text.GetText(0, full.Text.Length), lazy.Text.GetText(0, lazy.Text.Length));
        Inc(files);
        seen.Clear;
        if Length(codes) = 0 then Continue;
        for tries := 1 to 25 do
        begin
          len := 1 + Rnd(4);
          if len > Length(codes) then len := Length(codes);
          i := Rnd(Length(codes) - len + 1);
          bad := False;
          for o := i to i + len - 1 do
            if (codes[o] = $FFFD) or (codes[o] = $FFFC) then bad := True;
          if bad then Continue;
          needle := Utf8Of(i, len);
          case Rnd(3) of
            0: opts := [];
            1: opts := [rfoMatchCase];
          else
            opts := [rfoWholeWord];
          end;
          if seen.IndexOf(needle + '/' + IntToStr(Integer(opts))) >= 0 then Continue;
          seen.Add(needle + '/' + IntToStr(Integer(opts)));
          Inc(needles);
          want := WholePositions(full, needle, opts);
          ForgetDecodes(lazy);
          got := Positions(lazy, needle, opts);
          if got <> want then
            Fail(Format('file %d, needle hex %s, options %d: lazily: [%s], read whole: [%s]',
              [n, HexOf(needle), Integer(opts), got, want]));
        end;
      finally
        lazy.Free;
        full.Free;
      end;
    end;
  finally
    seen.Free;
  end;
  AssertTrue(Format('files %d, needles %d', [files, needles]),
    (files = CFiles) and (needles > 10 * CFiles));
end;

{ One part of a replace of [AStart, AStart + ALength) that goes on where another stopped -
  ABefore: what that one said its walk saw before the place (its tally's ResumeBefore) -, then
  the replace is stopped as the control stops it (it lets go of its walk); True when that part
  was its last. }
function ReplaceOnePart(ADoc: TTyRichDocument; const ANeedle, ARepl: UTF8String;
  AOptions: TTyRichFindOptions; AStart, ALength: TTyRichPos; const ABefore: TTyRichBefore;
  out ATally: TTyRichReplaceTally): Boolean;
var
  cmd: TTyRichReplaceAllCommand;
begin
  ATally := Default(TTyRichReplaceTally);
  cmd := TTyRichReplaceAllCommand.Create(ADoc, ANeedle, ARepl, AOptions, AStart, ALength);
  cmd.Tally := @ATally;
  cmd.StartBefore := ABefore;
  cmd.Prepare(-1);
  if not cmd.Ready then
  begin
    cmd.Free;
    Exit(True);
  end;
  if not ADoc.Execute(cmd) then raise Exception.Create('the part did not run');
  Result := cmd.Finished;
  cmd.Tally := nil;
  cmd.LetGo;
end;

{ A replace stopped after every part and started again from where it said, each start given
  what the one before saw at that place (ACarry; without it every start is judged by the text
  as it is): the matches replaced in all, AParts the parts it took. }
function ReplaceChain(ADoc: TTyRichDocument; const ANeedle, ARepl: UTF8String;
  AOptions: TTyRichFindOptions; ACarry: Boolean; out AParts: Integer): Integer;
var
  tally: TTyRichReplaceTally;
  at, len: TTyRichPos;
  before: TTyRichBefore;
  last: Boolean;
begin
  Result := 0;
  AParts := 0;
  at := 0;
  len := -1;
  before := Default(TTyRichBefore);
  repeat
    Inc(AParts);
    last := ReplaceOnePart(ADoc, ANeedle, ARepl, AOptions, at, len, before, tally);
    Inc(Result, tally.Replaced);
    at := tally.ResumeAt;
    len := tally.ResumeLength;
    if ACarry then before := tally.ResumeBefore;
  until last or (AParts > 1000);
end;

{ Whole word, matches that touch in one paragraph of more of them than a part takes: a part
  ends between two of them like anywhere else, and the replace stopped after every part and
  started again from where it said replaces what one walk replaces - the text and the count -
  because each start is told how the walk saw the character before it. Where the replacement
  ends in a word character the text as it is would answer the other way (the second of two
  touching matches no whole word any more): without what is carried the chain replaces fewer.
  Replacements that end in a word character, in none, the empty one, and one with a paragraph
  end; each text also with the pairs shifted, so that a part's last match is now the first of
  two, now the second. }
procedure TTyRichFindTest.TestAStopBetweenTouchingWholeWords;
const
  CRepl: array[0..4] of UTF8String = ('zz', 'z-', '', #10 + 'z', 'z' + #10);
var
  doc, one: TTyRichDocument;
  s: RawByteString;
  sb: TStringBuilder;
  i, k, r, parts, total, want: Integer;
  skipped: Integer;
  name: string;
  f: TTyRichFinder;
  bef: TTyRichBefore;
begin
  for k := 0 to 2 do
    for r := 0 to High(CRepl) do
    begin
      // (the replacements with a paragraph end - a delete and an insert a match - on one text)
      if (r >= 3) and (k > 0) then Continue;
      sb := TStringBuilder.Create;
      try
        // (more than two parts' matches each)
        case k of
          0: for i := 0 to 16999 do sb.Append('a-');
          1: for i := 0 to 8499 do sb.Append('a-a- ');
        else
          sb.Append('a- ');
          for i := 0 to 8499 do sb.Append('a-a- ');
        end;
        s := sb.ToString;
      finally
        sb.Free;
      end;
      name := Format('text %d, replacement %d', [k, r]);
      one := TextDoc(s);
      doc := TextDoc(s);
      try
        want := ReplaceIn(one, 'a-', CRepl[r], [rfoWholeWord], skipped);
        AssertEquals(name + ': one walk replaces every one', CountOf('a-', s), want);
        total := ReplaceChain(doc, 'a-', CRepl[r], [rfoWholeWord], True, parts);
        AssertTrue(name + Format(': in parts (%d)', [parts]), parts >= 3);
        AssertTrue(name + ': the same text as one walk', one.Text.GetText(0, one.Text.Length) =
          doc.Text.GetText(0, doc.Text.Length));
        AssertEquals(name + ': as many', want, total);
      finally
        doc.Free;
        one.Free;
      end;
    end;
  // what is carried is what makes it exact: without it, a part's end between two that touch
  // costs the second one where the replacement ends in a word character
  sb := TStringBuilder.Create;
  try
    for i := 0 to 16999 do sb.Append('a-');
    s := sb.ToString;
  finally
    sb.Free;
  end;
  doc := TextDoc(s);
  try
    total := ReplaceChain(doc, 'a-', 'zz', [rfoWholeWord], False, parts);
    AssertTrue(Format('judged by the text as it is: fewer (%d)', [total]), total < 17000);
    AssertEquals('... what is left, left as it was', 17000 - total,
      CountOf('a-', doc.Text.GetText(0, doc.Text.Length)));
  finally
    doc.Free;
  end;
  // a finder given what stood before its start takes it for a match that begins exactly there
  doc := TextDoc('zza-a- a-');
  try
    for i := 0 to 2 do
    begin
      f := TTyRichFinder.Create(doc, 'a-', [rfoWholeWord], 2);
      try
        bef := Default(TTyRichBefore);
        bef.Known := i > 0;
        if i = 1 then bef.Code := Ord('-') else bef.Code := Ord('y');
        f.StartBefore := bef;
        f.Collect := True;
        f.Run;
        case i of
          0: AssertEquals('by the text (a letter before it): not the first', '4 7', Joined(f));
          1: AssertEquals('told no letter stood there: the first too', '2 4 7', Joined(f));
        else
          AssertEquals('told a letter stood there: not the first', '4 7', Joined(f));
        end;
      finally
        f.Free;
      end;
    end;
  finally
    doc.Free;
  end;
end;

{ A document's text, its paragraph ends as line feeds whatever they are stored as. }
function LinesOf(ADoc: TTyRichDocument): RawByteString;
begin
  Result := StringReplace(ADoc.Text.GetText(0, ADoc.Text.Length), #13#10, #10, [rfReplaceAll]);
end;

{ One line of 80,000 touching whole-word matches, each replaced by a paragraph end and a
  letter (the ordinary edits, a delete and an insert a match): the parts are bounded - at most
  CRichReplacePartEdits matches each -, the limit on the undo step is looked at after each
  (one part's worth is kept when the first reaches it), and an edit of a part costs a short
  stretch of text, not the line from its start: what the text storage counts to find the
  edits' places is bounded by the matches, by the text between them, and once by the text
  before a part's first. Stopped at the limit and started from where it said, the next part
  follows without a gap. }
procedure TTyRichFindTest.TestALineOfTouchingMatchesIsReplacedInBoundedParts;
const
  CCount = 80000;
var
  doc: TTyRichDocument;
  s, want: RawByteString;
  sb: TStringBuilder;
  i, parts, before, most: Integer;
  cmd: TTyRichReplaceAllCommand;
  tally: TTyRichReplaceTally;
  work: Int64;
  at, len: TTyRichPos;
  bef: TTyRichBefore;
  limited: Boolean;
  line: RawByteString;
begin
  sb := TStringBuilder.Create;
  try
    for i := 1 to CCount do sb.Append('a-');
    s := sb.ToString;
    sb.Clear;
    for i := 1 to CCount do sb.Append(#10 + 'z');
    want := sb.ToString;
  finally
    sb.Free;
  end;
  // no limit: every part bounded, the work linear
  doc := TextDoc(s);
  try
    doc.MaxUndoBytes := 0;
    tally := Default(TTyRichReplaceTally);
    cmd := TTyRichReplaceAllCommand.Create(doc, 'a-', #10 + 'z', [rfoWholeWord]);
    cmd.Tally := @tally;
    parts := 0;
    most := 0;
    work := doc.Text.SplitWork;
    repeat
      cmd.Prepare(-1);
      if not cmd.Ready then Break;
      before := tally.Replaced;
      if parts = 0 then AssertTrue(doc.Execute(cmd)) else AssertTrue(doc.ExecutePart(cmd));
      Inc(parts);
      if tally.Replaced - before > most then most := tally.Replaced - before;
    until cmd.Finished;
    AssertEquals('all of them', CCount, tally.Replaced);
    AssertEquals('a part takes at most its share of matches', CRichReplacePartEdits, most);
    AssertEquals('so many parts', (CCount + CRichReplacePartEdits - 1) div CRichReplacePartEdits, parts);
    work := doc.Text.SplitWork - work;
    AssertTrue(Format('an edit counts a short stretch at most, not the line (%d characters ' +
      'counted for %d matches)', [work, CCount]), work <= 4 * Int64(CRichReplaceBackSpan) * CCount);
    AssertTrue('the text', LinesOf(doc) = want);
  finally
    doc.Free;
  end;
  { What the edits count in the text storage, two more lines: matches far apart (each counts
    the text between two, the part's first the text before it - once), and matches close
    together far into the line (the first counts the line before them, the others the short
    stretch behind it). }
  for i := 0 to 1 do
  begin
    sb := TStringBuilder.Create;
    try
      if i = 0 then
      begin
        most := 12000;
        for parts := 1 to most do
        begin
          sb.Append('a-');
          sb.Append(StringOfChar('x', 200));
          sb.Append(' ');
        end;
      end
      else
      begin
        most := 5000;
        sb.Append(StringOfChar('x', 1024 * 1024));
        sb.Append(' ');
        for parts := 1 to most do sb.Append('a-');
      end;
      line := sb.ToString;
    finally
      sb.Free;
    end;
    doc := TextDoc(line);
    try
      doc.MaxUndoBytes := 0;
      work := doc.Text.SplitWork;
      AssertEquals(Format('line %d: all of them', [i]), most,
        ReplaceInParts(doc, 'a-', #10 + 'z', [rfoWholeWord], CRichReplaceRangeChars, before, parts, limited));
      work := doc.Text.SplitWork - work;
      if i = 0 then
        AssertTrue(Format('far apart: the text between them, a few times (%d characters counted ' +
          'for %d of text)', [work, Length(line)]), work <= 16 * Int64(Length(line)))
      else
        AssertTrue(Format('close together, far into the line: the line once, then the short ' +
          'stretch (%d characters counted for %d matches behind %d of text)', [work, most,
          Length(line)]), work <= 4 * Int64(CRichReplaceBackSpan) * most + 16 * Int64(Length(line)));
      AssertEquals(Format('line %d: none left', [i]), 0, CountOf('a-', doc.Text.GetText(0, doc.Text.Length)));
    finally
      doc.Free;
    end;
  end;
  // the limit: looked at after each part, so a step keeps one part's worth past it at most
  doc := TextDoc(s);
  try
    doc.MaxUndoBytes := 16 * 1024;
    tally := Default(TTyRichReplaceTally);
    cmd := TTyRichReplaceAllCommand.Create(doc, 'a-', #10 + 'z', [rfoWholeWord]);
    cmd.Tally := @tally;
    AssertTrue(cmd.Prepare(-1) and cmd.Ready);
    AssertTrue(doc.Execute(cmd));
    AssertTrue('the first part reached the limit', cmd.Limited and cmd.Finished);
    AssertEquals('one part of them', CRichReplacePartEdits, tally.Replaced);
    cmd.Tally := nil;
    cmd.LetGo;
    // on from where it said, with what it saw there: the next part's worth, from that very place
    at := tally.ResumeAt;
    len := tally.ResumeLength;
    bef := tally.ResumeBefore;
    AssertEquals('it stopped behind what it replaced', Int64(2 * CRichReplacePartEdits), at);
    AssertTrue('it says what stood before that place', bef.Known and (bef.Code = Ord('-')));
    ReplaceOnePart(doc, 'a-', #10 + 'z', [rfoWholeWord], at, len, bef, tally);
    AssertEquals('started again: the next part of them', CRichReplacePartEdits, tally.Replaced);
    AssertTrue('... the limit again', tally.Limited);
    AssertTrue('... none left out between the two', Copy(LinesOf(doc), 1, 4 * CRichReplacePartEdits + 2) =
      Copy(want, 1, 4 * CRichReplacePartEdits) + 'a-');
  finally
    doc.Free;
  end;
end;

{ How many matches one part replaces, by its kind. Neither the needle nor the replacement
  holds a paragraph end: the paragraphs are changed in place, 8,192 matches a part. A
  paragraph end in the replacement, or in the needle: ordinary edits, a delete and an insert
  a match, and a part - what a background turn does without a break - is 512 of them. A
  needle with a paragraph end has its matches listed first and handed on a range's worth at
  a time (every one of a few thousand short lines here): a part still takes its share only,
  and the others follow in the next parts, moved by what it changed. }
procedure TTyRichFindTest.TestAPartOfEachKindTakesItsShareOfMatches;
var
  doc: TTyRichDocument;
  sb: TStringBuilder;
  s, want: RawByteString;
  i, parts: Integer;

  // replaces every match in parts; the most matches one part replaced
  function Most(const ANeedle, ARepl: UTF8String; out AParts: Integer): Integer;
  var
    cmd: TTyRichReplaceAllCommand;
    tally: TTyRichReplaceTally;
    before: Integer;
  begin
    Result := 0;
    AParts := 0;
    doc.MaxUndoBytes := 0;
    tally := Default(TTyRichReplaceTally);
    cmd := TTyRichReplaceAllCommand.Create(doc, ANeedle, ARepl, []);
    cmd.Tally := @tally;
    repeat
      cmd.Prepare(-1);
      if not cmd.Ready then Break;
      before := tally.Replaced;
      if AParts = 0 then AssertTrue(doc.Execute(cmd)) else AssertTrue(doc.ExecutePart(cmd));
      Inc(AParts);
      if tally.Replaced - before > Result then Result := tally.Replaced - before;
    until cmd.Finished;
    AssertTrue('through its range', (AParts > 0) and cmd.Finished and not cmd.Failed);
    cmd.Tally := nil;
  end;

begin
  sb := TStringBuilder.Create;
  try
    for i := 1 to 20000 do sb.Append('a,');
    s := sb.ToString;
  finally
    sb.Free;
  end;
  // changed in place
  doc := TextDoc(s);
  try
    AssertEquals('in place: a part''s matches', 8192, Most(',', ';', parts));
    AssertEquals('in place: the parts', 3, parts);
    AssertTrue('in place: the text', doc.Text.GetText(0, doc.Text.Length) =
      StringReplace(s, ',', ';', [rfReplaceAll]));
  finally
    doc.Free;
  end;
  // a paragraph end in the replacement: ordinary edits
  doc := TextDoc(s);
  try
    AssertEquals('a paragraph end in the replacement: a part''s matches', 512, Most(',', #10, parts));
    AssertEquals('...the parts', (20000 + 511) div 512, parts);
    AssertTrue('...the text', LinesOf(doc) = StringReplace(s, ',', #10, [rfReplaceAll]));
    doc.Undo;
    AssertTrue('...undone, one step', (doc.Text.GetText(0, doc.Text.Length) = s) and
      (doc.UndoDepth = 0));
  finally
    doc.Free;
  end;
  // a paragraph end in the needle: every match of the lines in one range's worth
  sb := TStringBuilder.Create;
  try
    for i := 1 to 3000 do sb.Append('x' + IntToStr(i mod 10) + #10);
    s := sb.ToString;
    sb.Clear;
    for i := 1 to 3000 do sb.Append('x' + IntToStr(i mod 10) + ';');
    want := sb.ToString;
  finally
    sb.Free;
  end;
  doc := TextDoc(s);
  try
    AssertTrue('the lines fit one range', Length(s) < CRichReplaceRangeChars);
    AssertEquals('a paragraph end in the needle: a part''s matches', 512, Most(#10, ';', parts));
    AssertEquals('...the parts', (3000 + 511) div 512, parts);
    AssertTrue('...the text', doc.Text.GetText(0, doc.Text.Length) = want);
    doc.Undo;
    AssertTrue('...undone, one step', (LinesOf(doc) = s) and (doc.UndoDepth = 0));
  finally
    doc.Free;
  end;
end;

initialization
  RegisterTest(TTyRichFindTest);
end.
