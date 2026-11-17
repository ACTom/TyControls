unit test.richedit.find;

{ Finding and replacing in the engine (tyControls.RichEdit.Find, Task 11b): what a match is,
  rule by rule; the options alone and together; text that was never parsed - the raw-byte
  filter looked through first, never losing a match (every fixture, every word at every
  place, lazily and fully read, with and without the filter) and parsing only near what it
  finds; a find while a file loads; a find changes nothing; the replace command - one undo
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
    FTotFiltered, FTotRejected, FTotDecoded, FTotWords, FTotHits, FTotEmptyDecodes: Int64;
    function Positions(ADoc: TTyRichDocument; const ANeedle: UTF8String;
      AOptions: TTyRichFindOptions; AFilter: Boolean = True): string;
    function First(ADoc: TTyRichDocument; const ANeedle: UTF8String;
      AOptions: TTyRichFindOptions; AStart: TTyRichPos = 0; AEnd: TTyRichPos = -1): TTyRichPos;
    function Naive(ADoc: TTyRichDocument; const ANeedle: UTF8String;
      AOptions: TTyRichFindOptions): string;
    procedure CheckEveryWord(const AName: string; const ABytes: TBytes; ARtf: Boolean;
      AEncoding: TTyTextEncoding = teAuto);
  published
    // the brief's
    procedure TestFindInsideUnparsedRtf;
    // the filter: every fixture, and every form of a character the reader takes
    procedure TestTheFilterNeverLosesAHit;
    procedure TestEveryFormTheReaderTakes;
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
    procedure TestAFindWhileLoading;
    procedure TestAFindChangesNothing;
    // replacing
    procedure TestReplaceIsOneStepAcrossTurns;
    procedure TestReplaceCountsItsStepOnce;
    procedure TestReplaceTakesTheFormatOfWhatItReplaces;
    procedure TestReplaceUndoneSavesTheFile;
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
  AOptions: TTyRichFindOptions; AFilter: Boolean): string;
var
  f: TTyRichFinder;
  i: Integer;
  a: array of Int64;
begin
  f := TTyRichFinder.Create(ADoc, ANeedle, AOptions);
  try
    f.UseFilter := AFilter;
    f.Collect := True;
    AssertTrue('collected to the end', f.Run = rfrNotFound);
    a := nil;
    SetLength(a, f.MatchCount);
    for i := 0 to f.MatchCount - 1 do a[i] := f.Match(i);
    Result := Join(a);
    Inc(FTotFiltered, f.ParasFiltered);
    Inc(FTotRejected, f.ParasRejected);
    Inc(FTotDecoded, f.ParasDecoded);
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
  every place it is: the finder gives what the reference gives - in the file read lazily
  with the filter and without it, and read whole. }
procedure TTyRichFindTest.CheckEveryWord(const AName: string; const ABytes: TBytes;
  ARtf: Boolean; AEncoding: TTyTextEncoding);
var
  full, lazy: TTyRichDocument;
  text: TTyRichCodeArray;
  words: TStringList;
  i, j: Integer;
  w: UTF8String;
  want, got: string;
  f: TTyRichFinder;
  hitParas: Integer;
  k: Int64;
begin
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
      end;
      if j > i then i := j else Inc(i);
    end;
    for i := 0 to words.Count - 1 do
    begin
      w := words[i];
      want := Naive(full, w, [rfoMatchCase]);
      AssertTrue(AName + ': the reference finds ' + w, want <> '');
      AssertEquals(AName + ': read whole, ' + w, want, Positions(full, w, [rfoMatchCase]));
      if ARtf then
      begin
        lazy := LoadRtf(ABytes, False);
        try
          AssertEquals(AName + ': lazily, filtered, ' + w, want,
            Positions(lazy, w, [rfoMatchCase], True));
        finally
          lazy.Free;
        end;
        lazy := LoadRtf(ABytes, False);
        try
          AssertEquals(AName + ': lazily, not filtered, ' + w, want,
            Positions(lazy, w, [rfoMatchCase], False));
        finally
          lazy.Free;
        end;
        // case-insensitive, the filter's folded tables
        lazy := LoadRtf(ABytes, False);
        try
          AssertEquals(AName + ': lazily, any case, ' + w, Naive(full, w, []),
            Positions(lazy, w, [], True));
        finally
          lazy.Free;
        end;
        // what the filter let through: decoded paragraphs that held no match
        lazy := LoadRtf(ABytes, False);
        try
          f := TTyRichFinder.Create(lazy, w, [rfoMatchCase]);
          try
            f.Collect := True;
            f.Run;
            hitParas := 0;
            for j := 0 to f.MatchCount - 1 do
              if (j = 0) or (lazy.Text.ParaOfPos(f.Match(j)) <> lazy.Text.ParaOfPos(f.Match(j - 1))) then
                Inc(hitParas);
            Inc(FTotHits, hitParas);
            if f.ParasDecoded > hitParas then Inc(FTotEmptyDecodes, f.ParasDecoded - hitParas);
          finally
            f.Free;
          end;
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

{ ---- the brief's ---- }

{ A 5 MB RTF, opened and searched at once for a word that is only in its last paragraph (and
  split there by formatting groups): found, and only the interval of the hit was parsed. }
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
  i, n, para, k: Integer;
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
        seed := seed * 1103515245 + 12345;
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
        AssertTrue(Format('the filter ruled out the paragraphs (%d of %d)',
          [f.ParasRejected, f.ParasFiltered]), f.ParasRejected >= f.ParasFiltered - 1);
        AssertTrue(Format('decoded only the hit (%d)', [f.ParasDecoded]), f.ParasDecoded <= 1);
      finally
        f.Free;
      end;
      AssertTrue(Format('parsed near the hit only: %d intervals', [load.ParseCount - parsed0]),
        load.ParseCount - parsed0 <= 1);
      AssertTrue('the hit''s paragraph is the one decoded',
        doc.Text.ParaLazySource(para, src, bytes) and doc.Text.IsDecoded(src));
      AssertTrue('a paragraph far from it is not',
        doc.Text.ParaLazySource(para div 2, src, bytes) and not doc.Text.IsDecoded(src));
    finally
      doc.Free;
    end;
    // without the filter every interval is parsed to find it
    doc := TTyRichDocument.Create;
    try
      m.Position := 0;
      TyRichLoadRtf(doc, m);
      load := TyRichRtfLoadOf(doc);
      parsed0 := load.ParseCount;
      f := TTyRichFinder.Create(doc, 'quixotic', []);
      try
        f.UseFilter := False;
        AssertTrue('found unfiltered', f.Run = rfrFound);
        AssertEquals('at the end unfiltered', want, f.MatchPos);
      finally
        f.Free;
      end;
      AssertTrue('unfiltered parses everything', load.ParseCount - parsed0 >= load.IntervalCount - 1);
    finally
      doc.Free;
    end;
  finally
    m.Free;
  end;
end;

{ ---- the filter ---- }

procedure TTyRichFindTest.TestTheFilterNeverLosesAHit;
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
    AssertTrue(Format('the filter rules most paragraphs out (words %d; filtered %d, ruled out ' +
      '%d, decoded %d; paragraphs with a hit %d, decoded without one %d)',
      [FTotWords, FTotFiltered, FTotRejected, FTotDecoded, FTotHits, FTotEmptyDecodes]),
      FTotRejected * 2 > FTotFiltered);
    AssertTrue('a paragraph decoded without a hit is rare', FTotEmptyDecodes * 10 < FTotHits);
  finally
    names.Free;
  end;
end;

{ Every way the reader turns bytes into a character of the needle, one paragraph each: the
  filtered find and the unfiltered find agree with the whole parse. }
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
        AssertEquals(Format('needle %d filtered', [i]), want, Positions(lazy, needles[i], [], True));
      finally
        lazy.Free;
      end;
      lazy := LoadRtf(bytes, False);
      try
        AssertEquals(Format('needle %d not filtered', [i]), want, Positions(lazy, needles[i], [], False));
      finally
        lazy.Free;
      end;
    end;
    // and what is not in the text is ruled out by the bytes
    lazy := LoadRtf(bytes, False);
    try
      AssertEquals('ansi half: not text', '', Positions(lazy, 'ansi half', [], True));
      AssertEquals('the bookmark''s name: not text', '', Positions(lazy, 'orqld', [], True));
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
        Positions(lazy, U([$4E2D, $6587]), [], True));
    finally
      lazy.Free;
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
  // a Chinese run is one word (the caret's rule): a needle that is all of it is whole
  doc := TextDoc(U([$4E2D, $6587, 32, $4E2D, $6587, $5B57, 32, $4E2D, $6587, Ord(','), Ord('a'),
    $4E2D, $6587]));
  try
    AssertEquals('anywhere', '0 3 7 11', Positions(doc, U([$4E2D, $6587]), []));
    AssertEquals('whole words', '0 7', Positions(doc, U([$4E2D, $6587]), [rfoWholeWord]));
    AssertEquals('a part of a Chinese run is no whole word', '',
      Positions(doc, U([$6587]), [rfoWholeWord]));
    // never refused: a needle whose end is no word character
    AssertEquals('a comma, whole', '9', Positions(doc, ',', [rfoWholeWord]));
    AssertEquals('a Chinese run and a comma', '7',
      Positions(doc, U([$4E2D, $6587, Ord(',')]), [rfoWholeWord]));
    AssertEquals('...not from inside the run', '',
      Positions(doc, U([$6587, Ord(',')]), [rfoWholeWord]));
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
      Positions(doc, 'e', [], True);
      Positions(doc, 'e', [rfoWholeWord], False);
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

procedure TTyRichFindTest.TestReplaceIsOneStepAcrossTurns;
var
  doc: TTyRichDocument;
begin
  doc := TextDoc('a cat, a cat, a cat, a cat');
  try
    // two turns of the same replace: one step
    AssertTrue(doc.Execute(TTyRichReplaceCommand.Create(7, [23, 16], 3, 'dog')));
    AssertTrue(doc.Execute(TTyRichReplaceCommand.Create(7, [9, 2], 3, 'dog')));
    AssertEquals('replaced', 'a dog, a dog, a dog, a dog', doc.Text.GetText(0, doc.Text.Length));
    AssertEquals('one step', 1, doc.UndoDepth);
    // typing after it is a step of its own, and so is another replace
    AssertTrue(doc.Execute(TTyRichInsertText.Create(0, 'x')));
    AssertEquals('typing', 2, doc.UndoDepth);
    AssertTrue(doc.Execute(TTyRichReplaceCommand.Create(8, [1], 1, 'y')));
    AssertTrue(doc.Execute(TTyRichReplaceCommand.Create(7, [2], 1, 'z')));
    AssertEquals('another session', 4, doc.UndoDepth);
    doc.Undo;
    doc.Undo;
    doc.Undo;
    AssertEquals('the first replace again', 'a dog, a dog, a dog, a dog',
      doc.Text.GetText(0, doc.Text.Length));
    doc.Undo;
    AssertEquals('undone at once', 'a cat, a cat, a cat, a cat', doc.Text.GetText(0, doc.Text.Length));
    doc.Redo;
    AssertEquals('redone at once', 'a dog, a dog, a dog, a dog', doc.Text.GetText(0, doc.Text.Length));
    AssertEquals('the name', rsRichUndoReplace, doc.UndoDescription);
  finally
    doc.Free;
  end;
end;

{ What the history counts of a step that batches merged into is what it counts of the same
  step run whole (a redo counts its records anew); the merges count only what they add. And
  what the document refuses is left, and counted where the caller asked. }
procedure TTyRichFindTest.TestReplaceCountsItsStepOnce;
var
  doc: TTyRichDocument;
  merged, whole: Int64;
  skipped: Integer;
  cmd: TTyRichReplaceCommand;
  f: TTyRichFinder;
  s: RawByteString;
  i: Integer;
  places: array of TTyRichPos;
begin
  s := '';
  for i := 0 to 99 do s := s + 'one cat here' + #10;
  doc := TextDoc(s);
  try
    // 100 matches, the last first, in four batches
    places := nil;
    SetLength(places, 100);
    for i := 0 to 99 do places[i] := (99 - i) * 13 + 4;
    for i := 0 to 3 do
      AssertTrue(doc.Execute(TTyRichReplaceCommand.Create(3, Copy(places, i * 25, 25), 3, 'tiger')));
    AssertEquals('one step', 1, doc.UndoDepth);
    merged := doc.HistoryBytes;
    doc.Undo;
    // undone, its records are reverted and go: the redo side keeps next to nothing of them
    AssertTrue(Format('undone: %d of %d bytes kept', [doc.HistoryBytes, merged]),
      doc.HistoryBytes * 4 < merged);
    doc.Redo;
    whole := doc.HistoryBytes;
    // (the arrays' spare room differs, the records do not)
    AssertTrue(Format('merged (%d), counted as the step run whole (%d)', [merged, whole]),
      Abs(whole - merged) * 100 < whole);
    AssertTrue('records counted', merged > 100 * 8);
    AssertEquals('all replaced', 0, Pos('cat', doc.Text.GetText(0, doc.Text.Length)));
  finally
    doc.Free;
  end;
  // a row with a nested table: its match is left, and counted
  doc := LoadRtf(BytesOf(Rtf('{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}|pard word one|par' +
    '|trowd|cellx2000|cellx4000|pard|intbl word two|cell' +
    '|pard|intbl|itap2 word nested|nestcell{|*|nesttableprops|trowd|cellx1000|nestrow}{|nonesttables|par}' +
    '|pard|intbl|cell|row|pard word three|par}')), False);
  try
    skipped := 0;
    f := TTyRichFinder.Create(doc, 'word', []);
    try
      f.Collect := True;
      f.Run;
      places := nil;
      SetLength(places, f.MatchCount);
      for i := 0 to f.MatchCount - 1 do places[i] := f.Match(f.MatchCount - 1 - i);
    finally
      f.Free;
    end;
    AssertEquals('four', 4, Length(places));
    cmd := TTyRichReplaceCommand.Create(0, places, 4, 'w');
    cmd.SkipCounter := @skipped;
    AssertTrue(doc.Execute(cmd));
    // the row that holds the nested table: its two paragraphs ("two", "nested")
    AssertEquals('the nested row''s left, and counted', 2, skipped);
    AssertEquals('what is left', 2, Length(Naive(doc, 'word', [])) -
      Length(StringReplace(Naive(doc, 'word', []), ' ', '', [rfReplaceAll])) + 1);
    AssertEquals('the others replaced, one step', 1, doc.UndoDepth);
  finally
    doc.Free;
  end;
end;

procedure TTyRichFindTest.TestReplaceTakesTheFormatOfWhatItReplaces;
var
  doc: TTyRichDocument;
  bytes: TBytes;
  runs: TTyRunArray;
  p: Integer;
  r: Integer;
begin
  bytes := BytesOf(Rtf('{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}|pard one {|b cat} two {|i cat}|par}'));
  doc := LoadRtf(bytes, False);
  try
    AssertTrue(doc.Execute(TTyRichReplaceCommand.Create(1, [12, 4], 3, 'tiger')));
    AssertEquals('replaced', 'one tiger two tiger', doc.Text.GetText(0, 19));
    p := 0;
    runs := doc.RunsOf(p);
    r := High(runs);
    while runs[r].Start > 4 do Dec(r);
    AssertTrue('bold', fsBold in doc.Formats.CharFormat(runs[r].Format).Style);
    r := High(runs);
    while runs[r].Start > 14 do Dec(r);
    AssertTrue('italic', fsItalic in doc.Formats.CharFormat(runs[r].Format).Style);
    AssertFalse('...not bold', fsBold in doc.Formats.CharFormat(runs[r].Format).Style);
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
      AssertTrue(doc.Execute(TTyRichReplaceCommand.Create(1, pos, 1, 'EE')));
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

initialization
  RegisterTest(TTyRichFindTest);
end.
