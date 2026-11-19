unit test.richedit.fields;

{ RTF fields whose stored result is shown (a hyperlink, a page number, a table of contents):
  the result is the document's own content - text in its own formats, paragraphs, tabs,
  pictures, nested fields - between two field marks, zero-width object characters; the open
  mark keeps the field's group as the file has it, and a writer writes those bytes and nothing
  of what lies between the marks. What reading gives (lazily and whole alike), what a field
  that stays one object of its bytes is, what an edit around a field leaves of it in the saved
  file, and that nothing inside a result changes - a change that takes a whole field is fine,
  a format over a result passes it over. The samples are written here with | for a backslash
  (Rtf), and tests/fixtures/rtf. }

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, Graphics, fpcunit, testregistry,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite, tyControls.RichEdit.Find;

type
  TTyRichFieldsTest = class(TTestCase)
  private
    FSeed: Cardinal;
  public
    function NextRandom(AMax: Integer): Integer;
  published
    // reading
    procedure TestALinkIsItsResultBetweenTwoMarks;
    procedure TestATableOfContentsIsItsParagraphs;
    procedure TestChineseResultsReadAndGoBackAsTheFileHasThem;
    procedure TestFieldsThatStayOneObject;
    procedure TestNestedFieldsThreeDeep;
    procedure TestAFieldInATableCell;
    procedure TestAPictureInAResult;
    procedure TestAResultOfATabOrAParagraphEndAlone;
    procedure TestFieldsTouchingAndAtTheEndsOfTheDocument;
    procedure TestLazyEqualsWholeAcrossSnapshots;
    procedure TestCharacterWordsOfTheFieldReachItsResult;
    procedure TestAResultThatShowsNothingStaysOneObject;
    procedure TestALargeFieldIsDecidedAlikeWhereverAParseBegins;
    procedure TestAFieldsGroupIsReadOnceToDecideIt;
    procedure TestWordsOwnTableOfContents;
    // writing
    procedure TestTheSlotFontsAroundAFieldHoldAfterAnEdit;
    procedure TestAnEditOutsideAFieldKeepsItsBytes;
    procedure TestACopyTakesAWholeFieldAsItsBytesAndHalfAsText;
    // what may change
    procedure TestNothingInsideAResultChanges;
    procedure TestAWholeFieldDeletedComesBackOnUndo;
    procedure TestFormatsPassOverResults;
    procedure TestReplaceAllLeavesResults;
    procedure TestTablesAndObjectsAroundFields;
    procedure TestPastesAndMovesTakeWholeFields;
    procedure TestAReplaceOfMatchesInsideAResultLeavesThem;
    // the model's own word on fields
    procedure TestTheDepthOfEveryParagraphFollowsEveryEdit;
    procedure TestTheFieldAroundAPlaceAndAMarksPartner;
    procedure TestTheFieldAroundAPlaceReadsOnlyItsMarksParagraphs;
    procedure TestARefusalSaysItIsAField;
    procedure TestTheOpenMarkKeepsTheFieldsBytes;
  end;

implementation

const
  BS = #92;

{ U+FFFC, an object character (a field's marks are two of them). Expected texts are UTF-8
  strings made of literals and this, turned into bytes once (U): a string of bytes and a
  literal joined would be converted. }
function OC: UTF8String;
begin
  Result := TyRichObjectChar;
end;

function Rtf(const S: RawByteString): RawByteString;
var
  i: Integer;
begin
  Result := S;
  UniqueString(Result);
  for i := 1 to Length(Result) do
    if Result[i] = '|' then Result[i] := BS;
  SetCodePage(Result, CP_NONE, False);
end;

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

function StrOfBytes(const B: TBytes): RawByteString;
begin
  Result := '';
  SetLength(Result, Length(B));
  if Length(B) > 0 then Move(B[0], Result[1], Length(B));
  SetCodePage(Result, CP_NONE, False);
end;

{ The bytes of a UTF8String literal, so comparisons never convert. }
function U(const S: UTF8String): RawByteString;
begin
  Result := S;
  SetCodePage(Result, CP_NONE, False);
end;

function Shown(const S: RawByteString): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if (S[i] >= ' ') and (S[i] < #$7F) then Result := Result + S[i]
    else Result := Result + '<' + IntToHex(Ord(S[i]), 2) + '>';
  if Length(Result) > 300 then Result := Copy(Result, 1, 300) + '...';
end;

function SameRaw(const A, B: RawByteString): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((A = '') or CompareMem(@A[1], @B[1], Length(A)));
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

function CountRaw(const ANeedle, AHay: RawByteString): Integer;
var
  p: Integer;
begin
  Result := 0;
  p := Pos(ANeedle, AHay);
  while p > 0 do
  begin
    Inc(Result);
    p := Pos(ANeedle, AHay, p + Length(ANeedle));
  end;
end;

procedure AssertRaw(ATest: TTestCase; const AMsg: string; const AExpected, AActual: RawByteString);
begin
  if SameRaw(AExpected, AActual) then Exit;
  ATest.Fail(Format('%s: expected <%s> but was <%s>', [AMsg, Shown(AExpected), Shown(AActual)]));
end;

function ParaText(ADoc: TTyRichDocument; AIndex: Integer): RawByteString;
begin
  Result := ADoc.Text.GetText(ADoc.Text.ParaStart(AIndex), ADoc.Text.ParaLength(AIndex));
  SetCodePage(Result, CP_NONE, False);
end;

function WithoutObjects(const S: RawByteString): RawByteString;
var
  i, n: Integer;
begin
  Result := '';
  SetLength(Result, Length(S));
  n := 0;
  i := 1;
  while i <= Length(S) do
    if (i + 2 <= Length(S)) and (S[i] = #$EF) and (S[i + 1] = #$BF) and (S[i + 2] = #$BC) then
      Inc(i, 3)
    else
    begin
      Inc(n);
      Result[n] := S[i];
      Inc(i);
    end;
  SetLength(Result, n);
  SetCodePage(Result, CP_NONE, False);
end;

function LoadDoc(const ABytes: TBytes; AFull: Boolean): TTyRichDocument;
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

function SaveOut(ADoc: TTyRichDocument): TBytes;
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

function RangeOut(ADoc: TTyRichDocument; AFrom, ALen: TTyRichPos): TBytes;
var
  s: TBytesStream;
begin
  s := TBytesStream.Create;
  try
    TyRichSaveRtfRange(ADoc, s, AFrom, ALen);
    Result := Copy(s.Bytes, 0, s.Size);
  finally
    s.Free;
  end;
end;

{ ---- the marks, as every document shows its objects ---- }

function IsMark(O: TTyRichObject): Boolean;
begin
  Result := (O <> nil) and (O.ClassName = 'TTyRichFieldMark');
end;

function IsOpenMark(O: TTyRichObject): Boolean;
begin
  Result := IsMark(O) and (TTyRichFieldMark(O).Kind = rfmOpen);
end;

function IsCloseMark(O: TTyRichObject): Boolean;
begin
  Result := IsMark(O) and (TTyRichFieldMark(O).Kind = rfmClose);
end;

// the bytes an open mark keeps: the field's group
function MarkBytes(O: TTyRichObject): Int64;
begin
  Result := (O as TTyRichFieldMark).BytesLength;
end;

{ The objects of paragraph AIndex in order: [ an open mark, ] a close mark, O an object of
  bytes, P a picture, ? any other. }
function ObjectsOf(ADoc: TTyRichDocument; AIndex: Integer): string;
var
  runs: TTyRunArray;
  i: Integer;
begin
  Result := '';
  runs := ADoc.RunsOf(AIndex);
  for i := 0 to High(runs) do
    if runs[i].Obj <> nil then
      if IsOpenMark(runs[i].Obj) then Result := Result + '['
      else if IsCloseMark(runs[i].Obj) then Result := Result + ']'
      else if runs[i].Obj is TTyRichOpaque then Result := Result + 'O'
      else if runs[i].Obj is TTyRichPicture then Result := Result + 'P'
      else Result := Result + '?';
end;

function AllObjects(ADoc: TTyRichDocument): string;
var
  k: Integer;
begin
  Result := '';
  for k := 0 to ADoc.Text.ParaCount - 1 do
  begin
    if k > 0 then Result := Result + '/';
    Result := Result + ObjectsOf(ADoc, k);
  end;
end;

function ObjectAt(ADoc: TTyRichDocument; APara, AChar: Integer): TTyRichObject;
begin
  Result := ADoc.ObjectAt(ADoc.Text.ParaStart(APara) + AChar);
end;

function FirstOpaque(ADoc: TTyRichDocument): TTyRichOpaque;
var
  k, i: Integer;
  runs: TTyRunArray;
begin
  for k := 0 to ADoc.Text.ParaCount - 1 do
  begin
    runs := ADoc.RunsOf(k);
    for i := 0 to High(runs) do
      if runs[i].Obj is TTyRichOpaque then Exit(TTyRichOpaque(runs[i].Obj));
  end;
  Result := nil;
end;

function CharFmt(ADoc: TTyRichDocument; APos: TTyRichPos): TTyCharFormat;
var
  k, i: Integer;
  runs: TTyRunArray;
  o: Int64;
begin
  k := ADoc.Text.ParaOfPos(APos);
  o := APos - ADoc.Text.ParaStart(k);
  runs := ADoc.RunsOf(k);
  i := High(runs);
  while (i > 0) and (runs[i].Start > o) do Dec(i);
  Result := ADoc.Formats.CharFormat(runs[i].Format);
end;

function SameObj(A, B: TTyRichObject): Boolean;
begin
  if (A = nil) or (B = nil) then Exit(A = B);
  if A.ClassType <> B.ClassType then Exit(False);
  if A.RawUc <> B.RawUc then Exit(False);
  if A is TTyRichOpaque then
    Exit(SameRaw(TTyRichOpaque(A).Bytes, TTyRichOpaque(B).Bytes) and
      SameRaw(TTyRichOpaque(A).DisplayText, TTyRichOpaque(B).DisplayText));
  if A is TTyRichPicture then
    Exit((TTyRichPicture(A).PictureFormat = TTyRichPicture(B).PictureFormat) and
      (Length(TTyRichPicture(A).Data) = Length(TTyRichPicture(B).Data)));
  if A is TTyRichFieldMark then
    Exit((TTyRichFieldMark(A).Kind = TTyRichFieldMark(B).Kind) and
      SameRaw(TTyRichFieldMark(A).Bytes, TTyRichFieldMark(B).Bytes));
  Result := A.DataBytes = B.DataBytes;
end;

{ '' when the two documents are the same: paragraphs, their text, formats, runs (formats by
  value, objects by kind and content), cells. }
function ModelDiff(A, B: TTyRichDocument): string;
var
  k, j: Integer;
  ra, rb: TTyRunArray;
begin
  if A.Text.ParaCount <> B.Text.ParaCount then
    Exit(Format('%d paragraphs / %d', [A.Text.ParaCount, B.Text.ParaCount]));
  for k := 0 to A.Text.ParaCount - 1 do
  begin
    if not SameRaw(ParaText(A, k), ParaText(B, k)) then
      Exit(Format('paragraph %d: text <%s> / <%s>', [k, Shown(ParaText(A, k)), Shown(ParaText(B, k))]));
    if not A.Formats.ParaFormat(A.ParaFormatOf(k)).Equals(B.Formats.ParaFormat(B.ParaFormatOf(k))) then
      Exit(Format('paragraph %d: its format', [k]));
    ra := A.RunsOf(k);
    rb := B.RunsOf(k);
    if Length(ra) <> Length(rb) then
      Exit(Format('paragraph %d: %d runs / %d', [k, Length(ra), Length(rb)]));
    for j := 0 to High(ra) do
    begin
      if ra[j].Start <> rb[j].Start then Exit(Format('paragraph %d run %d: its start', [k, j]));
      if not A.Formats.CharFormat(ra[j].Format).Equals(B.Formats.CharFormat(rb[j].Format)) then
        Exit(Format('paragraph %d run %d: its format', [k, j]));
      if not SameObj(ra[j].Obj, rb[j].Obj) then Exit(Format('paragraph %d run %d: its object', [k, j]));
    end;
    if (A.CellAt(k) = nil) <> (B.CellAt(k) = nil) then Exit(Format('paragraph %d: a cell', [k]));
  end;
  Result := '';
end;

{ The groups B leaves open at its end (0: balanced); ANegative: a group closed that was not
  open. }
function OpenGroupsAtEnd(const B: TBytes; out ANegative: Boolean): Integer;
var
  lex: TTyRtfLexer;
  t: TTyRtfToken;
begin
  Result := 0;
  ANegative := False;
  if Length(B) = 0 then Exit;
  lex.Init(@B[0], 0, Length(B));
  while lex.Next(t) do
    case t.Kind of
      rtkGroupStart: Inc(Result);
      rtkGroupEnd:
        begin
          Dec(Result);
          if Result < 0 then ANegative := True;
        end;
    end;
end;

procedure CheckBalanced(ATest: TTestCase; const AMsg: string; const B: TBytes);
var
  neg: Boolean;
  n: Integer;
begin
  n := OpenGroupsAtEnd(B, neg);
  ATest.AssertEquals(AMsg + ': every group closed', 0, n);
  ATest.AssertFalse(AMsg + ': no group closed that was not open', neg);
end;

{ The group that begins at the AIndex-th (from 1) brace-field of S, brace to brace. }
function FieldGroup(const S: RawByteString; AIndex: Integer): RawByteString;
var
  p, i, depth: Integer;
  b: TBytes;
  lex: TTyRtfLexer;
  t: TTyRtfToken;
begin
  p := 0;
  for i := 1 to AIndex do
  begin
    p := Pos(Rtf('{|field'), S, p + 1);
    if p = 0 then Exit('');
  end;
  b := BytesOf(S);
  lex.Init(@b[0], p - 1, Length(b));
  depth := 0;
  while lex.Next(t) do
    case t.Kind of
      rtkGroupStart: Inc(depth);
      rtkGroupEnd:
        begin
          Dec(depth);
          if depth = 0 then Exit(Copy(S, p, t.Stop - (p - 1)));
        end;
    end;
  Result := '';
end;

{ Opened and saved, lazily and whole: the file again. }
procedure CheckRoundTrip(ATest: TTestCase; const AMsg: string; const B: TBytes);
var
  d: TTyRichDocument;
  full: Boolean;
begin
  for full := False to True do
  begin
    d := LoadDoc(B, full);
    try
      ATest.AssertTrue(Format('%s (whole %s): saved as it was read', [AMsg, BoolToStr(full, True)]),
        SameBytes(B, SaveOut(d)));
    finally
      d.Free;
    end;
  end;
end;

{ Every paragraph of a lazy load (AResident intervals parsed at most, 0: no limit), read in
  the order AOrder gives (nil: from the first), is what the whole parse made of it. }
procedure CheckLazyIsWhole(ATest: TTyRichFieldsTest; const AMsg: string; const B: TBytes;
  AResident: Integer; ARandom: Boolean);
var
  lazy, full: TTyRichDocument;
  order: array of Integer;
  i, j, t: Integer;
begin
  full := LoadDoc(B, True);
  lazy := LoadDoc(B, False);
  try
    if AResident > 0 then TyRichRtfLoadOf(lazy).MaxResidentIntervals := AResident;
    ATest.AssertEquals(AMsg + ': paragraphs', full.Text.ParaCount, lazy.Text.ParaCount);
    order := nil;
    SetLength(order, lazy.Text.ParaCount);
    for i := 0 to High(order) do order[i] := i;
    if ARandom then
      for i := High(order) downto 1 do
      begin
        j := ATest.NextRandom(i + 1);
        t := order[i];
        order[i] := order[j];
        order[j] := t;
      end;
    // one at a time, each against the whole parse (the lazy load lets intervals go between)
    for i := 0 to High(order) do
    begin
      j := order[i];
      AssertRaw(ATest, Format('%s paragraph %d: its text', [AMsg, j]), ParaText(full, j),
        ParaText(lazy, j));
      ATest.AssertTrue(Format('%s paragraph %d: its format', [AMsg, j]),
        full.Formats.ParaFormat(full.ParaFormatOf(j)).Equals(lazy.Formats.ParaFormat(lazy.ParaFormatOf(j))));
      ATest.AssertEquals(Format('%s paragraph %d: its objects', [AMsg, j]), ObjectsOf(full, j),
        ObjectsOf(lazy, j));
    end;
    TyRichRtfLoadOf(lazy).MaxResidentIntervals := MaxInt;
    ATest.AssertEquals(AMsg + ': read whole and lazily', '', ModelDiff(full, lazy));
  finally
    lazy.Free;
    full.Free;
  end;
end;

{ An edit outside every field, on a lazy load of B: the saved bytes hold each of AGroups as it
  is (as many times as the file does), their groups balance, and read back they are the
  edited document. }
procedure CheckEditKeeps(ATest: TTestCase; const AMsg: string; const B: TBytes;
  ACmd: TTyRichCommand; const AGroups: array of RawByteString);
var
  d, r: TTyRichDocument;
  o: TBytes;
  s, f: RawByteString;
  i: Integer;
begin
  f := StrOfBytes(B);
  d := LoadDoc(B, False);
  try
    ATest.AssertTrue(AMsg + ': the edit is made', d.Execute(ACmd));
    o := SaveOut(d);
    s := StrOfBytes(o);
    for i := 0 to High(AGroups) do
      ATest.AssertEquals(Format('%s: field %d as the file has it', [AMsg, i]), CountRaw(AGroups[i], f),
        CountRaw(AGroups[i], s));
    CheckBalanced(ATest, AMsg, o);
    r := LoadDoc(o, True);
    try
      ATest.AssertEquals(AMsg + ': read back, the edited document', '', ModelDiff(d, r));
    finally
      r.Free;
    end;
  finally
    d.Free;
  end;
end;

{ ---- samples ---- }

const
  // SimSun, Arial; blue, red
  H936 = '{|rtf1|ansi|ansicpg936|deff0{|fonttbl{|f0|fnil|fcharset134 SimSun;}{|f1|fswiss|fcharset0 Arial;}}' +
    '{|colortbl;|red0|green0|blue255;|red255|green0|blue0;}|uc1 ';
  // 这里 [链接] 末 / after: the link underlined and blue
  LinkBody = '|pard|f0|fs24 |''d5|''e2|''c0|''ef {|field{|*|fldinst HYPERLINK "http://example.com/"}' +
    '{|fldrslt {|ul|cf1 |''c1|''b4|''bd|''d3}}} |''c4|''a9|par after|par}';
  // 这里 [ 0 1 2, the open mark 3, 链接 4 5, the close mark 6, 末 7 8
  LinkOpen = 3;
  LinkClose = 6;

function LinkRtf: RawByteString;
begin
  Result := Rtf(H936 + LinkBody);
end;

const
  // Word's sample and ours, with a hyperlink in paragraph 1
  LinkFiles: array[0..1] of string = ('hand-word-unknown.rtf', 'word-unknown.rtf');

function Fixture(const AName: string): TBytes;
begin
  Result := ReadFileBytes(FixtureDir + AName);
end;

{ A table of contents of ACount entries (each a link holding the entry's text, a tab and a
  page number field), APad plain paragraphs before it and after it. }
function TocRtf(ACount, APad: Integer): RawByteString;
var
  i: Integer;
  s: RawByteString;
begin
  s := H936;
  for i := 1 to APad do s := s + '|pard plain paragraph ' + IntToStr(i) + ' before the contents|par ';
  s := s + '|pard|s2|tqr|tldot|tx8000 Contents: {|field|fldedit{|*|fldinst TOC ||o "1-3" ||h}{|fldrslt ';
  for i := 1 to ACount do
  begin
    s := s + '{|field{|*|fldinst HYPERLINK ||l "_Toc' + IntToStr(i) + '"}{|fldrslt ' +
      '{|cs15|ul|cf1 |''b5|''da' + IntToStr(i) + '|''d5|''c2 Chapter ' + IntToStr(i) + '|tab ' +
      '{|field{|*|fldinst PAGEREF _Toc' + IntToStr(i) + ' ||h}{|fldrslt ' + IntToStr(i * 3) + '}}}}}';
    if i < ACount then s := s + '|par |pard|s2|tqr|tldot|tx8000 ';
  end;
  s := s + '}} and the text after it|par ';
  for i := 1 to APad do s := s + '|pard plain paragraph ' + IntToStr(i) + ' after the contents|par ';
  Result := Rtf(s + '}');
end;

{ ---- the suite ---- }

function TTyRichFieldsTest.NextRandom(AMax: Integer): Integer;
begin
  FSeed := FSeed * 1103515245 + 12345;
  Result := Integer((FSeed shr 8) mod Cardinal(AMax));
end;

{ A hyperlink: its stored result is the paragraph's text between two marks, in its own look
  (underlined, blue), the text around it in its own; the open mark keeps the field's group.
  The same in Word's files. }
procedure TTyRichFieldsTest.TestALinkIsItsResultBetweenTwoMarks;
var
  d: TTyRichDocument;
  f: TTyCharFormat;
  b: TBytes;
  name: string;
  i: Integer;
begin
  b := BytesOf(LinkRtf);
  d := LoadDoc(b, True);
  try
    AssertRaw(Self, 'the paragraph', '这里 ' + OC + '链接' + OC + ' 末', ParaText(d, 0));
    AssertEquals('two marks', '[]', ObjectsOf(d, 0));
    AssertTrue('the open one', IsOpenMark(ObjectAt(d, 0, LinkOpen)));
    AssertTrue('the close one', IsCloseMark(ObjectAt(d, 0, LinkClose)));
    AssertEquals('the open mark keeps the field''s group',
      Length(FieldGroup(LinkRtf, 1)), MarkBytes(ObjectAt(d, 0, LinkOpen)));
    f := CharFmt(d, LinkOpen + 1);
    AssertTrue('the link underlined', fsUnderline in f.Style);
    AssertEquals('the link blue', $FF0000, f.Color);
    AssertTrue('all of it', fsUnderline in CharFmt(d, LinkOpen + 2).Style);
    AssertFalse('the text before it plain', fsUnderline in CharFmt(d, 0).Style);
    AssertFalse('the text after it plain', fsUnderline in CharFmt(d, LinkClose + 2).Style);
    AssertRaw(Self, 'the next paragraph', 'after', ParaText(d, 1));
  finally
    d.Free;
  end;
  CheckRoundTrip(Self, 'a link', b);
  CheckLazyIsWhole(Self, 'a link', b, 0, False);
  for i := 0 to High(LinkFiles) do
  begin
    name := LinkFiles[i];
    b := Fixture(name);
    d := LoadDoc(b, False);
    try
      AssertRaw(Self, name + ': the link''s paragraph', '这里有一个' + OC + '链接' + OC + '。',
        ParaText(d, 1));
      AssertEquals(name + ': its marks', '[]', ObjectsOf(d, 1));
      AssertTrue(name + ': the link underlined', fsUnderline in CharFmt(d, d.Text.ParaStart(1) + 6).Style);
    finally
      d.Free;
    end;
    CheckRoundTrip(Self, name, b);
    CheckLazyIsWhole(Self, name, b, 1, True);
  end;
end;

{ A table of contents (Word's way: TOC holding a HYPERLINK per entry, holding a PAGEREF) is its
  paragraphs: each entry one, with its tab stop (right, dot leader), its text and its number;
  the field opens after text and closes before text. }
procedure TTyRichFieldsTest.TestATableOfContentsIsItsParagraphs;
var
  b: TBytes;
  d: TTyRichDocument;
  lines: TStringList;
  k: Integer;
  pf: TTyParaFormat;
  t: RawByteString;
begin
  b := Fixture('hand-word-toc.rtf');
  lines := TStringList.Create;
  d := LoadDoc(b, True);
  try
    lines.LoadFromFile(FixtureDir + 'hand-word-toc.visible.txt');
    AssertEquals('every entry a paragraph', 42, d.Text.ParaCount);
    AssertEquals('the visible text''s lines', 42, lines.Count);
    for k := 0 to d.Text.ParaCount - 1 do
      AssertRaw(Self, Format('paragraph %d', [k]), U(lines[k]), WithoutObjects(ParaText(d, k)));
    AssertEquals('the heading has none', '', ObjectsOf(d, 0));
    AssertEquals('the first entry: the field opens, then its link and its page number', '[[[]]',
      ObjectsOf(d, 1));
    for k := 2 to 39 do AssertEquals(Format('entry %d', [k]), '[[]]', ObjectsOf(d, k));
    AssertEquals('the last entry, then the field closes', '[[]]]', ObjectsOf(d, 40));
    AssertEquals('the paragraph after', '', ObjectsOf(d, 41));
    t := ParaText(d, 1);
    AssertRaw(Self, 'it opens after text', '说明：' + OC, Copy(t, 1, 12));
    t := ParaText(d, 40);
    AssertRaw(Self, 'it closes before text', OC + '正文从这里开始。',
      Copy(t, Length(t) - Length(U('正文从这里开始。')) - 2, Length(U('正文从这里开始。')) + 3));
    pf := d.Formats.ParaFormat(d.ParaFormatOf(2));
    AssertEquals('an entry''s tab stop', 1, Length(pf.Tabs));
    AssertEquals('at its place', 8296, pf.Tabs[0].Position);
    AssertTrue('right aligned', pf.Tabs[0].Align = ttaRight);
    AssertTrue('with dots', pf.Tabs[0].Leader = ttlDot);
    AssertTrue('the entry''s text a link', fsUnderline in CharFmt(d, d.Text.ParaStart(2) + 1).Style);
  finally
    d.Free;
    lines.Free;
  end;
  CheckRoundTrip(Self, 'a table of contents', b);
  CheckLazyIsWhole(Self, 'a table of contents', b, 1, True);
end;

{ Chinese in a result: \'xx in the code page of the font (\ansicpg936, and 54936 - GB18030),
  \uN with its fallback, \uN with none (\uc0) and with two bytes (\uc2): read right, and the
  field written back as the file has it after an edit beside it. }
procedure TTyRichFieldsTest.TestChineseResultsReadAndGoBackAsTheFileHasThem;
const
  Results: array[0..4] of RawByteString = (
    '|''c1|''b4|''bd|''d3',
    '|''c1|''b4|''bd|''d3',
    '|u38142?|u25509?',
    '|uc0|u38142|u25509 ',
    '|u38142|''c1|''b4|u25509|''bd|''d3');
  Pages: array[0..4] of string = ('936', '54936', '936', '936', '936');
  Ucs: array[0..4] of string = ('1', '1', '1', '1', '2');
var
  i: Integer;
  s, g: RawByteString;
  b: TBytes;
  d: TTyRichDocument;
begin
  for i := 0 to High(Results) do
  begin
    s := Rtf('{|rtf1|ansi|ansicpg' + Pages[i] + '|deff0{|fonttbl{|f0|fnil SimSun;}}|uc' + Ucs[i] +
      ' |pard|f0 a{|field{|*|fldinst HYPERLINK "x"}{|fldrslt ' + Results[i] + '}}b|par}');
    b := BytesOf(s);
    d := LoadDoc(b, True);
    try
      AssertRaw(Self, Format('sample %d', [i]), 'a' + OC + '链接' + OC + 'b', ParaText(d, 0));
      AssertEquals(Format('sample %d: its marks', [i]), '[]', ObjectsOf(d, 0));
      AssertEquals(Format('sample %d: read under its \uc', [i]), StrToInt(Ucs[i]), ObjectAt(d, 0, 1).RawUc);
    finally
      d.Free;
    end;
    CheckRoundTrip(Self, Format('sample %d', [i]), b);
    g := FieldGroup(s, 1);
    CheckEditKeeps(Self, Format('sample %d, typed before it', [i]), b,
      TTyRichInsertText.Create(0, 'X'), [g]);
    CheckEditKeeps(Self, Format('sample %d, typed after it', [i]), b,
      TTyRichInsertText.Create(5, 'Y'), [g]);
  end;
end;

{ What stays one object of its bytes as before: a field with no result, an empty one, a
  result that holds a table's words, a section break, a header, footer, footnote or comment,
  one nested past eight fields, one whose group the file never closes - the object's bytes the
  whole group, its display text its result's text. A field in a list item's marker makes
  nothing, as before. }
procedure TTyRichFieldsTest.TestFieldsThatStayOneObject;
const
  Groups: array[0..15] of RawByteString = (
    '{|field{|*|fldinst PAGE}}',
    '{|field{|*|fldinst PAGE}{|fldrslt}}',
    '{|field{|*|fldinst DATABASE}{|fldrslt |trowd|cellx1000 x|cell|row}}',
    '{|field{|*|fldinst X}{|fldrslt x|cell y}}',
    '{|field{|*|fldinst X}{|fldrslt x|row}}',
    '{|field{|*|fldinst X}{|fldrslt x|nestcell y}}',
    '{|field{|*|fldinst X}{|fldrslt x|nestrow}}',
    '{|field{|*|fldinst X}{|fldrslt |intbl x}}',
    '{|field{|*|fldinst X}{|fldrslt |itap1 x}}',
    '{|field{|*|fldinst X}{|fldrslt x|sect y}}',
    '{|field{|*|fldinst X}{|fldrslt x{|header h}}}',
    '{|field{|*|fldinst X}{|fldrslt x{|footerl h}}}',
    '{|field{|*|fldinst X}{|fldrslt x{|footnote h}}}',
    '{|field{|*|fldinst X}{|fldrslt x{|*|annotation h}}}',
    '{|field{|*|fldinst X}{|fldrslt x{|sect y}}}',
    '{|field{|*|fldinst X}{|fldrslt |itap2 x}}');
  Shows: array[0..15] of RawByteString = ('', '', 'x', 'xy', 'x', 'xy', 'x', 'x', 'x', 'xy',
    'x', 'x', 'x', 'x', 'xy', 'x');
var
  i, k: Integer;
  s, g: RawByteString;
  b: TBytes;
  d: TTyRichDocument;
  o: TTyRichOpaque;
begin
  for i := 0 to High(Groups) do
  begin
    g := Rtf(Groups[i]);
    s := Rtf(H936 + '|pard a') + g + Rtf('b|par}');
    b := BytesOf(s);
    d := LoadDoc(b, True);
    try
      AssertEquals(Format('field %d: one object', [i]), 'O', AllObjects(d));
      AssertRaw(Self, Format('field %d: the paragraph', [i]), 'a' + OC + 'b', ParaText(d, 0));
      o := FirstOpaque(d);
      AssertRaw(Self, Format('field %d: its bytes', [i]), g, o.Bytes);
      AssertRaw(Self, Format('field %d: what it shows', [i]), Shows[i], o.DisplayText);
    finally
      d.Free;
    end;
    CheckRoundTrip(Self, Format('field %d', [i]), b);
    CheckLazyIsWhole(Self, Format('field %d', [i]), b, 0, False);
  end;
  // nine fields deep: the outer one is one object; eight are shown
  for i := 8 to 9 do
  begin
    g := '';
    for k := 1 to i do g := g + '{|field{|*|fldinst X}{|fldrslt a';
    g := g + 'z';
    for k := 1 to 2 * i do g := g + '}';
    s := Rtf(H936 + '|pard b' + g + 'c|par}');
    b := BytesOf(s);
    d := LoadDoc(b, True);
    try
      if i = 8 then
        AssertEquals('eight deep: shown', '[[[[[[[[]]]]]]]]', AllObjects(d))
      else
      begin
        AssertEquals('nine deep: one object', 'O', AllObjects(d));
        AssertRaw(Self, 'nine deep: its bytes', Rtf(g), FirstOpaque(d).Bytes);
      end;
    finally
      d.Free;
    end;
    CheckRoundTrip(Self, Format('%d deep', [i]), b);
  end;
  // a field the file never closes: one object to the file's end, as before
  s := Rtf(H936 + '|pard a{|field{|*|fldinst PAGE}{|fldrslt 7');
  d := LoadDoc(BytesOf(s), True);
  try
    AssertEquals('unclosed: one object', 'O', AllObjects(d));
    AssertRaw(Self, 'unclosed: to the end', Rtf('{|field{|*|fldinst PAGE}{|fldrslt 7'), FirstOpaque(d).Bytes);
  finally
    d.Free;
  end;
  // in a list item's marker: no object, as before
  s := Rtf(H936 + '|pard{|listtext {|field{|*|fldinst SEQ}{|fldrslt 1.}}|tab}x|par}');
  d := LoadDoc(BytesOf(s), True);
  try
    AssertEquals('in a marker: nothing', '', AllObjects(d));
    AssertRaw(Self, 'in a marker: the text', 'x', ParaText(d, 0));
  finally
    d.Free;
  end;
  // in a header (in the body): inside the header's one object
  s := Rtf(H936 + '|pard x{|header {|field{|*|fldinst PAGE}{|fldrslt 3}}}y|par}');
  d := LoadDoc(BytesOf(s), True);
  try
    AssertEquals('in a header: the header''s object', 'O', AllObjects(d));
    AssertTrue('the field in its bytes', Pos(Rtf('{|field'), FirstOpaque(d).Bytes) > 0);
  finally
    d.Free;
  end;
end;

{ Three fields, one in the other's result: three pairs of marks, nested; each open mark keeps
  its own group (the outer one all three). }
procedure TTyRichFieldsTest.TestNestedFieldsThreeDeep;
var
  s: RawByteString;
  b: TBytes;
  d: TTyRichDocument;
  i: Integer;
begin
  s := Rtf(H936 + '|pard x{|field{|*|fldinst A}{|fldrslt a{|field{|*|fldinst B}{|fldrslt b' +
    '{|field{|*|fldinst C}{|fldrslt c}}}}}}y|par z|par}');
  b := BytesOf(s);
  d := LoadDoc(b, True);
  try
    AssertRaw(Self, 'the text', 'x' + OC + 'a' + OC + 'b' + OC + 'c' + OC + OC + OC + 'y', ParaText(d, 0));
    AssertEquals('nested', '[[[]]]', ObjectsOf(d, 0));
    for i := 1 to 3 do
      AssertEquals(Format('field %d keeps its group', [i]), Length(FieldGroup(s, i)),
        MarkBytes(ObjectAt(d, 0, 2 * i - 1)));
  finally
    d.Free;
  end;
  CheckRoundTrip(Self, 'three deep', b);
  CheckLazyIsWhole(Self, 'three deep', b, 0, False);
  CheckEditKeeps(Self, 'three deep, typed before', b, TTyRichInsertText.Create(0, 'Q'),
    [FieldGroup(s, 1)]);
  CheckEditKeeps(Self, 'three deep, in the next paragraph', b,
    TTyRichInsertText.Create(12, 'Q'), [FieldGroup(s, 1)]);
end;

{ A field in a table cell whose result is one paragraph is shown in the cell; one whose result
  has a paragraph end stays one object. A row holding a field can be deleted, and its undo
  gives the file back. }
procedure TTyRichFieldsTest.TestAFieldInATableCell;
var
  s: RawByteString;
  b: TBytes;
  d: TTyRichDocument;
begin
  s := Rtf(H936 + '|trowd|cellx2000|cellx4000|pard|intbl a{|field{|*|fldinst X}{|fldrslt |''c1|''b4}}b' +
    '|cell c|cell|row|pard after|par}');
  b := BytesOf(s);
  d := LoadDoc(b, True);
  try
    AssertRaw(Self, 'the cell', 'a' + OC + '链' + OC + 'b', ParaText(d, 0));
    AssertEquals('its marks', '[]', ObjectsOf(d, 0));
    AssertTrue('in its cell', d.CellAt(0) <> nil);
    AssertTrue('the row whole', (d.CellAt(1) <> nil) and (d.CellAt(1).Row = d.CellAt(0).Row));
  finally
    d.Free;
  end;
  CheckRoundTrip(Self, 'a field in a cell', b);
  CheckLazyIsWhole(Self, 'a field in a cell', b, 0, False);
  // its row deleted, and undone
  d := LoadDoc(b, False);
  try
    AssertTrue('the row deleted', d.Execute(TTyRichDeleteRow.Create(0, 0)));
    AssertEquals('no mark left', '', AllObjects(d));
    d.Undo;
    AssertTrue('undone: the file', SameBytes(b, SaveOut(d)));
  finally
    d.Free;
  end;
  // with a paragraph end in its result
  s := Rtf(H936 + '|trowd|cellx2000|cellx4000|pard|intbl a{|field{|*|fldinst X}{|fldrslt x|par y}}b' +
    '|cell c|cell|row|pard after|par}');
  b := BytesOf(s);
  d := LoadDoc(b, True);
  try
    AssertEquals('one object', 'O', ObjectsOf(d, 0));
    AssertRaw(Self, 'the cell as before', 'a' + OC + 'b', ParaText(d, 0));
  finally
    d.Free;
  end;
  CheckRoundTrip(Self, 'a field in a cell with a paragraph end', b);
end;

{ INCLUDEPICTURE: the picture is the result, between the marks. }
procedure TTyRichFieldsTest.TestAPictureInAResult;
var
  s: RawByteString;
  b: TBytes;
  d: TTyRichDocument;
begin
  s := Rtf(H936 + '|pard a{|field{|*|fldinst INCLUDEPICTURE "x.png"}{|fldrslt {|pict|pngblip|picwgoal300' +
    '|pichgoal200 89504e470d0a1a0a}}}b|par}');
  b := BytesOf(s);
  d := LoadDoc(b, True);
  try
    AssertEquals('the picture between the marks', '[P]', ObjectsOf(d, 0));
    AssertRaw(Self, 'the paragraph', 'a' + OC + OC + OC + 'b', ParaText(d, 0));
  finally
    d.Free;
  end;
  CheckRoundTrip(Self, 'a picture', b);
  CheckEditKeeps(Self, 'a picture, typed before', b, TTyRichInsertText.Create(0, 'Q'),
    [FieldGroup(s, 1)]);
end;

{ A result of a tab alone, and of a paragraph end alone: shown, the second as two paragraphs. }
procedure TTyRichFieldsTest.TestAResultOfATabOrAParagraphEndAlone;
var
  s: RawByteString;
  b: TBytes;
  d: TTyRichDocument;
begin
  s := Rtf(H936 + '|pard a{|field{|*|fldinst X}{|fldrslt |tab}}b|par}');
  b := BytesOf(s);
  d := LoadDoc(b, True);
  try
    AssertRaw(Self, 'a tab', 'a' + OC + #9 + OC + 'b', ParaText(d, 0));
  finally
    d.Free;
  end;
  CheckRoundTrip(Self, 'a tab', b);
  s := Rtf(H936 + '|pard a{|field{|*|fldinst X}{|fldrslt |par}}b|par c|par}');
  b := BytesOf(s);
  d := LoadDoc(b, True);
  try
    AssertEquals('a paragraph end: two paragraphs and the last', 3, d.Text.ParaCount);
    AssertRaw(Self, 'the first', 'a' + OC, ParaText(d, 0));
    AssertRaw(Self, 'the second', OC + 'b', ParaText(d, 1));
    AssertEquals('the marks', '[/]/', AllObjects(d));
  finally
    d.Free;
  end;
  CheckRoundTrip(Self, 'a paragraph end', b);
  CheckLazyIsWhole(Self, 'a paragraph end', b, 0, False);
  CheckEditKeeps(Self, 'a paragraph end, typed after it', b,
    TTyRichInsertText.Create(4, 'Q'), [FieldGroup(s, 1)]);
end;

{ Two fields with nothing between them; a field that begins the document, one that ends it
  (no paragraph mark after it). }
procedure TTyRichFieldsTest.TestFieldsTouchingAndAtTheEndsOfTheDocument;
var
  s: RawByteString;
  b: TBytes;
  d: TTyRichDocument;
begin
  s := Rtf(H936 + '|pard x{|field{|*|fldinst A}{|fldrslt a}}{|field{|*|fldinst B}{|fldrslt b}}y|par}');
  b := BytesOf(s);
  d := LoadDoc(b, True);
  try
    AssertRaw(Self, 'touching', 'x' + OC + 'a' + OC + OC + 'b' + OC + 'y', ParaText(d, 0));
    AssertEquals('two pairs', '[][]', ObjectsOf(d, 0));
  finally
    d.Free;
  end;
  CheckRoundTrip(Self, 'touching', b);
  CheckEditKeeps(Self, 'touching, typed between', b, TTyRichInsertText.Create(4, 'Q'),
    [FieldGroup(s, 1), FieldGroup(s, 2)]);
  s := Rtf(H936 + '|pard{|field{|*|fldinst A}{|fldrslt first}}x|par y{|field{|*|fldinst B}{|fldrslt last}}}');
  b := BytesOf(s);
  d := LoadDoc(b, True);
  try
    AssertRaw(Self, 'the document begins with one', OC + 'first' + OC + 'x', ParaText(d, 0));
    AssertRaw(Self, 'and ends with one', 'y' + OC + 'last' + OC, ParaText(d, 1));
  finally
    d.Free;
  end;
  CheckRoundTrip(Self, 'at the ends', b);
  CheckLazyIsWhole(Self, 'at the ends', b, 0, False);
  CheckEditKeeps(Self, 'at the ends, typed first', b, TTyRichInsertText.Create(0, 'Q'),
    [FieldGroup(s, 1), FieldGroup(s, 2)]);
  d := LoadDoc(b, True);
  try
    AssertTrue('typed last', d.CanChange(d.Text.Length, 0));
  finally
    d.Free;
  end;
end;

{ A table of contents that crosses many of the lazy load's snapshot intervals: each paragraph
  read lazily, in any order and with intervals let go between, is the whole parse's; the
  index has the whole parse's paragraphs; saved both ways it is the file. }
procedure TTyRichFieldsTest.TestLazyEqualsWholeAcrossSnapshots;
var
  s: RawByteString;
  b: TBytes;
  d: TTyRichDocument;
  load: TTyRtfLoad;
  i, inside: Integer;
  tocStart, tocStop: Int64;
begin
  FSeed := 13;
  s := TocRtf(1500, 100);
  b := BytesOf(s);
  tocStart := Pos(Rtf('{|field|fldedit'), s) - 1;
  tocStop := tocStart + Length(FieldGroup(s, 1));
  d := LoadDoc(b, False);
  try
    load := TyRichRtfLoadOf(d);
    inside := 0;
    for i := 0 to load.IntervalCount - 1 do
      if (load.IntervalStart(i) > tocStart) and (load.IntervalStart(i) < tocStop) then Inc(inside);
    AssertTrue(Format('snapshots inside the contents: %d', [inside]), inside >= 3);
  finally
    d.Free;
  end;
  CheckLazyIsWhole(Self, 'contents', b, 2, True);
  CheckRoundTrip(Self, 'contents', b);
end;

{ An edit outside every field writes each field back as the file has it - an edit before a
  field, after it in its paragraph, in the paragraph after a table of contents and in the
  paragraph that holds its close; the output balances and reads back as the edited document. }
procedure TTyRichFieldsTest.TestAnEditOutsideAFieldKeepsItsBytes;
var
  b: TBytes;
  s, toc: RawByteString;
  d: TTyRichDocument;
  i, k, n: Integer;
  closeAt: TTyRichPos;
  name: string;
begin
  b := Fixture('hand-word-toc.rtf');
  s := StrOfBytes(b);
  toc := FieldGroup(s, 1);
  AssertTrue('the contents'' group', Pos('TOC', toc) > 0);
  d := LoadDoc(b, True);
  try
    n := d.Text.ParaCount;
    // after the last close mark of the paragraph that holds the field's close (正文从这里开始。)
    closeAt := d.Text.ParaStart(40) + d.Text.ParaLength(40) - 8;
  finally
    d.Free;
  end;
  CheckEditKeeps(Self, 'before the contents', b, TTyRichInsertText.Create(4, 'X'), [toc]);
  CheckEditKeeps(Self, 'at the start of its paragraph', b, TTyRichInsertText.Create(3, 'X'), [toc]);
  CheckEditKeeps(Self, 'after its close, in its paragraph', b,
    TTyRichInsertText.Create(closeAt, 'X'), [toc]);
  CheckEditKeeps(Self, 'a word deleted there', b, TTyRichDelete.Create(closeAt, 2), [toc]);
  d := LoadDoc(b, True);
  try
    k := d.Text.ParaStart(n - 1);
  finally
    d.Free;
  end;
  CheckEditKeeps(Self, 'in the paragraph after it', b, TTyRichInsertText.Create(k, 'X'), [toc]);
  CheckEditKeeps(Self, 'a paragraph after it split', b, TTyRichInsertText.Create(k + 2, #10), [toc]);
  for i := 0 to High(LinkFiles) do
  begin
    name := LinkFiles[i];
    b := Fixture(name);
    d := LoadDoc(b, True);
    try
      k := d.Text.ParaStart(1);
    finally
      d.Free;
    end;
    CheckEditKeeps(Self, name + ': before the link', b, TTyRichInsertText.Create(k, 'X'),
      [FieldGroup(StrOfBytes(b), 1)]);
    CheckEditKeeps(Self, name + ': the paragraph before it', b, TTyRichInsertText.Create(0, 'X'),
      [FieldGroup(StrOfBytes(b), 1)]);
  end;
end;

{ A copy of a range that holds a whole field writes the field's bytes; a range that holds one
  of its marks only writes what lies in the range as text, with no field around it; the output
  balances either way and reads back as the range's text. }
procedure TTyRichFieldsTest.TestACopyTakesAWholeFieldAsItsBytesAndHalfAsText;
var
  d, r: TTyRichDocument;
  o: TBytes;
  s: RawByteString;
  b: TBytes;
  k: Integer;
begin
  d := LoadDoc(BytesOf(LinkRtf), False);
  try
    o := RangeOut(d, 0, d.Text.ParaLength(0) + 1);
    s := StrOfBytes(o);
    AssertEquals('the whole field: its bytes', 1, CountRaw(FieldGroup(LinkRtf, 1), s));
    CheckBalanced(Self, 'the whole field', o);
    r := LoadDoc(o, True);
    try
      AssertEquals('read back: a field', '[]', ObjectsOf(r, 0));
      AssertRaw(Self, 'read back: its text', ParaText(d, 0), ParaText(r, 0));
    finally
      r.Free;
    end;
    // the open mark and the first character of the result
    o := RangeOut(d, 1, 4);
    s := StrOfBytes(o);
    AssertEquals('half a field: no field', 0, CountRaw(Rtf('|field'), s));
    CheckBalanced(Self, 'half a field', o);
    r := LoadDoc(o, True);
    try
      AssertRaw(Self, 'read back: the text', U('里 链'), ParaText(r, 0));
      AssertTrue('read back: the link''s look', fsUnderline in CharFmt(r, 2).Style);
    finally
      r.Free;
    end;
    // the result alone, and from its middle to after the field
    o := RangeOut(d, 4, 2);
    AssertEquals('the result alone: no field', 0, CountRaw(Rtf('|field'), StrOfBytes(o)));
    CheckBalanced(Self, 'the result alone', o);
    o := RangeOut(d, 5, 4);
    AssertEquals('to after it: no field', 0, CountRaw(Rtf('|field'), StrOfBytes(o)));
    CheckBalanced(Self, 'to after it', o);
  finally
    d.Free;
  end;
  // whole entries out of a table of contents: their own fields, not the contents
  b := Fixture('hand-word-toc.rtf');
  d := LoadDoc(b, False);
  try
    k := d.Text.ParaStart(10);
    o := RangeOut(d, k, d.Text.ParaStart(20) - k);
    s := StrOfBytes(o);
    AssertEquals('ten entries'' links', 10, CountRaw('HYPERLINK', s));
    AssertEquals('their page numbers', 10, CountRaw('PAGEREF', s));
    AssertEquals('not the contents', 0, CountRaw('TOC', s));
    CheckBalanced(Self, 'ten entries', o);
    r := LoadDoc(o, True);
    try
      AssertTrue('read back: the ten paragraphs', r.Text.ParaCount >= 10);
      AssertRaw(Self, 'read back: an entry', ParaText(d, 10), ParaText(r, 0));
    finally
      r.Free;
    end;
  finally
    d.Free;
  end;
end;

{ Inside a result nothing is typed, deleted or split, and no change takes one mark of a field
  without the other: each is refused before anything changes - the history and the saved
  bytes as they were. }
procedure TTyRichFieldsTest.TestNothingInsideAResultChanges;
const
  Inserts: array[0..2] of TTyRichPos = (LinkOpen + 1, LinkOpen + 2, LinkClose);
  DelFrom: array[0..6] of TTyRichPos = (LinkOpen, LinkClose, LinkOpen - 1, LinkClose - 1,
    LinkOpen + 1, 0, LinkOpen + 1);
  DelLen: array[0..6] of TTyRichPos = (1, 1, 2, 2, 2, LinkOpen + 1, 8);
var
  b: TBytes;
  d: TTyRichDocument;
  i, k: Integer;
begin
  b := BytesOf(LinkRtf);
  d := LoadDoc(b, False);
  try
    for i := 0 to High(Inserts) do
    begin
      AssertFalse(Format('insert at %d', [Inserts[i]]), d.CanChange(Inserts[i], 0));
      AssertFalse(Format('typed at %d', [Inserts[i]]), d.Execute(TTyRichInsertText.Create(Inserts[i], 'x')));
      AssertFalse(Format('a paragraph end at %d', [Inserts[i]]),
        d.Execute(TTyRichInsertText.Create(Inserts[i], #10)));
      AssertFalse(Format('a picture at %d', [Inserts[i]]), d.Execute(TTyRichInsertObject.Create(Inserts[i],
        TTyRichPicture.Create(rpfPng, nil, 100, 100))));
    end;
    for i := 0 to High(DelFrom) do
    begin
      if DelFrom[i] + DelLen[i] > d.Text.Length then Continue;
      AssertFalse(Format('delete %d+%d', [DelFrom[i], DelLen[i]]), d.CanChange(DelFrom[i], DelLen[i]));
      AssertFalse(Format('deleted %d+%d', [DelFrom[i], DelLen[i]]),
        d.Execute(TTyRichDelete.Create(DelFrom[i], DelLen[i])));
    end;
    AssertTrue('before the field', d.CanChange(LinkOpen, 0));
    AssertTrue('after it', d.CanChange(LinkClose + 1, 0));
    AssertTrue('the whole field', d.CanChange(LinkOpen, LinkClose - LinkOpen + 1));
    AssertEquals('no step', 0, d.UndoDepth);
    AssertTrue('the file', SameBytes(b, SaveOut(d)));
  finally
    d.Free;
  end;
  // a table of contents: its paragraphs are neither joined nor split, nor deleted
  b := Fixture('hand-word-toc.rtf');
  d := LoadDoc(b, False);
  try
    for k := 2 to 40 do
    begin
      AssertFalse(Format('the mark before paragraph %d', [k]),
        d.Execute(TTyRichDelete.Create(d.Text.ParaStart(k) - 1, 1)));
      AssertFalse(Format('paragraph %d split', [k]),
        d.Execute(TTyRichInsertText.Create(d.Text.ParaStart(k) + 3, #10)));
    end;
    AssertFalse('a paragraph of it deleted', d.Execute(TTyRichDelete.Create(d.Text.ParaStart(5),
      d.Text.ParaLength(5) + 1)));
    AssertEquals('no step', 0, d.UndoDepth);
    AssertTrue('the file', SameBytes(b, SaveOut(d)));
  finally
    d.Free;
  end;
end;

{ A range that takes a whole field - its two marks and all between them - goes; undone it is
  back with its bytes, redone gone again. A table of contents too. }
procedure TTyRichFieldsTest.TestAWholeFieldDeletedComesBackOnUndo;
var
  b, after: TBytes;
  d: TTyRichDocument;
  s: RawByteString;
  a, z, n: Int64;
begin
  b := BytesOf(LinkRtf);
  d := LoadDoc(b, False);
  try
    AssertTrue('the field deleted', d.Execute(TTyRichDelete.Create(LinkOpen, LinkClose - LinkOpen + 1)));
    AssertRaw(Self, 'its text gone', U('这里  末'), ParaText(d, 0));
    after := SaveOut(d);
    AssertEquals('saved without it', 0, CountRaw(Rtf('|field'), StrOfBytes(after)));
    CheckBalanced(Self, 'without it', after);
    d.Undo;
    AssertTrue('undone: the file', SameBytes(b, SaveOut(d)));
    AssertEquals('undone: its marks', '[]', ObjectsOf(d, 0));
    d.Redo;
    AssertTrue('redone', SameBytes(after, SaveOut(d)));
    d.Undo;
    AssertTrue('with what is around it', d.Execute(TTyRichDelete.Create(1, LinkClose + 1)));
    AssertEquals('no mark left', '/', AllObjects(d));
    d.Undo;
    AssertTrue('undone again: the file', SameBytes(b, SaveOut(d)));
  finally
    d.Free;
  end;
  b := Fixture('hand-word-toc.rtf');
  s := StrOfBytes(b);
  d := LoadDoc(b, False);
  try
    n := d.Text.ParaCount;
    // from 说明： (before its open mark) to the text after its close
    a := d.Text.ParaStart(1) + 2;
    z := d.Text.ParaStart(40) + d.Text.ParaLength(40) - 8;
    AssertTrue('the contents deleted', d.Execute(TTyRichDelete.Create(a, z - a)));
    AssertEquals('its paragraphs gone', n - 39, d.Text.ParaCount);
    AssertEquals('and its marks', '//', AllObjects(d));
    after := SaveOut(d);
    AssertEquals('saved without it', 0, CountRaw('TOC', StrOfBytes(after)));
    CheckBalanced(Self, 'without the contents', after);
    d.Undo;
    AssertTrue('undone: the file', SameBytes(b, SaveOut(d)));
    d.Redo;
    AssertTrue('redone', SameBytes(after, SaveOut(d)));
  finally
    d.Free;
  end;
  AssertTrue(Length(s) > 0);
end;

{ A character format over a range that holds a result formats the rest and leaves the result
  and the marks as they are (one step); over a result alone it is refused. A paragraph format
  changes the paragraphs whose paragraph mark is outside every field. }
procedure TTyRichFieldsTest.TestFormatsPassOverResults;
var
  b: TBytes;
  d, r: TTyRichDocument;
  f: TTyCharFormat;
  p: TTyParaFormat;
  i, k, n: Integer;
  before: array of TTyCharFormat;
begin
  b := BytesOf(LinkRtf);
  d := LoadDoc(b, False);
  try
    before := nil;
    SetLength(before, d.Text.ParaLength(0));
    for i := 0 to High(before) do before[i] := CharFmt(d, i);
    f := TyDefaultCharFormat;
    f.Style := [fsBold];
    AssertTrue('the paragraph made bold', d.Execute(TTyRichSetCharFormat.Create(
      TyRichRange(0, d.Text.ParaLength(0)), [cffBold], f)));
    AssertEquals('one step', 1, d.UndoDepth);
    for i := 0 to High(before) do
      if (i >= LinkOpen) and (i <= LinkClose) then
        AssertTrue(Format('character %d, the field''s, as it was', [i]), before[i].Equals(CharFmt(d, i)))
      else
        AssertTrue(Format('character %d bold', [i]), fsBold in CharFmt(d, i).Style);
    r := LoadDoc(SaveOut(d), True);
    try
      AssertEquals('read back', '', ModelDiff(d, r));
    finally
      r.Free;
    end;
    AssertEquals('the field''s bytes', 1, CountRaw(FieldGroup(LinkRtf, 1), StrOfBytes(SaveOut(d))));
    AssertFalse('the result alone', d.Execute(TTyRichSetCharFormat.Create(
      TyRichRange(LinkOpen + 1, 2), [cffBold], f)));
    AssertFalse('the field alone', d.Execute(TTyRichSetCharFormat.Create(
      TyRichRange(LinkOpen, LinkClose - LinkOpen + 1), [cffBold], f)));
    AssertEquals('still one step', 1, d.UndoDepth);
    d.Undo;
    AssertTrue('undone: the file', SameBytes(b, SaveOut(d)));
  finally
    d.Free;
  end;
  b := Fixture('hand-word-toc.rtf');
  d := LoadDoc(b, False);
  try
    n := d.Text.ParaCount;
    p := TyDefaultParaFormat;
    p.SpaceBefore := 77;
    AssertTrue('every paragraph', d.Execute(TTyRichSetParaFormat.Create(0, n - 1, [pffSpaceBefore], p)));
    for k := 0 to n - 1 do
      if (k >= 1) and (k <= 39) then
        AssertTrue(Format('paragraph %d, the contents'', as it was', [k]),
          d.Formats.ParaFormat(d.ParaFormatOf(k)).SpaceBefore <> 77)
      else
        AssertEquals(Format('paragraph %d', [k]), 77, d.Formats.ParaFormat(d.ParaFormatOf(k)).SpaceBefore);
    AssertFalse('the contents'' paragraphs alone', d.Execute(TTyRichSetParaFormat.Create(2, 39,
      [pffSpaceBefore], p)));
    AssertEquals('one step', 1, d.UndoDepth);
    CheckBalanced(Self, 'a paragraph format', SaveOut(d));
    r := LoadDoc(SaveOut(d), True);
    try
      AssertEquals('read back', '', ModelDiff(d, r));
    finally
      r.Free;
    end;
    d.Undo;
    AssertTrue('undone: the file', SameBytes(b, SaveOut(d)));
  finally
    d.Free;
  end;
end;

{ A replace of every match leaves the matches inside results and counts them as left. }
procedure TTyRichFieldsTest.TestReplaceAllLeavesResults;
var
  d: TTyRichDocument;
  cmd: TTyRichReplaceAllCommand;
  tally: TTyRichReplaceTally;
  b: TBytes;
  fast: Boolean;
begin
  b := BytesOf(Rtf(H936 + '|pard |''c1|''b4|''bd|''d3 {|field{|*|fldinst HYPERLINK "x"}{|fldrslt ' +
    '|''c1|''b4|''bd|''d3}} |''c1|''b4|''bd|''d3|par}'));
  for fast := False to True do
  begin
    d := LoadDoc(b, False);
    try
      tally := Default(TTyRichReplaceTally);
      // (a replacement with a line break goes by ordinary edits, without one in place)
      if fast then cmd := TTyRichReplaceAllCommand.Create(d, U('链接'), 'ab', [])
      else cmd := TTyRichReplaceAllCommand.Create(d, U('链接'), 'a' + #10 + 'b', []);
      cmd.AllAtOnce := True;
      cmd.Tally := @tally;
      d.Execute(cmd);
      AssertEquals('the two outside', 2, tally.Replaced);
      AssertEquals('the one inside left', 1, tally.Skipped);
      AssertEquals('the field''s bytes', 1, CountRaw(FieldGroup(StrOfBytes(b), 1), StrOfBytes(SaveOut(d))));
      d.Undo;
      AssertTrue('undone: the file', SameBytes(b, SaveOut(d)));
    finally
      d.Free;
    end;
  end;
end;

{ No table goes into a result, and no picture in a result is resized or replaced; a table
  goes before a field, and a picture goes beside it. }
procedure TTyRichFieldsTest.TestTablesAndObjectsAroundFields;
var
  d: TTyRichDocument;
  b: TBytes;
  s: RawByteString;
begin
  d := LoadDoc(BytesOf(LinkRtf), False);
  try
    AssertTrue('a table inside: refused', d.TableEditRefusal(TyRichTableEdit(rtkInsertTable,
      LinkOpen + 1, 0, 2, 2)) <> rtrNone);
    AssertFalse('a table inside', d.Execute(TTyRichInsertTable.Create(LinkOpen + 1, 2, 2)));
    AssertTrue('a table before it', d.TableEditRefusal(TyRichTableEdit(rtkInsertTable,
      LinkOpen, 0, 2, 2)) = rtrNone);
    AssertTrue('a picture beside it', d.Execute(TTyRichInsertObject.Create(LinkClose + 1,
      TTyRichPicture.Create(rpfPng, nil, 100, 100))));
    AssertEquals('beside it', '[]P', ObjectsOf(d, 0));
  finally
    d.Free;
  end;
  s := Rtf(H936 + '|pard a{|field{|*|fldinst INCLUDEPICTURE "x.png"}{|fldrslt {|pict|pngblip|picwgoal300' +
    '|pichgoal200 89504e470d0a1a0a}}}b|par}');
  b := BytesOf(s);
  d := LoadDoc(b, False);
  try
    AssertFalse('the result''s picture resized', d.Execute(TTyRichResizeObject.Create(2, 600, 400)));
    AssertTrue('the file', SameBytes(b, SaveOut(d)));
  finally
    d.Free;
  end;
end;

{ Content goes in outside every field only; a move takes whole fields or nothing; a copy of a
  whole field is a second field with the same bytes, a copy of half of one is refused. }
procedure TTyRichFieldsTest.TestPastesAndMovesTakeWholeFields;
var
  s: RawByteString;
  b, after: TBytes;
  d, src: TTyRichDocument;
  ends, raised: Boolean;
begin
  b := BytesOf(LinkRtf);
  d := LoadDoc(b, False);
  try
    src := TyRichReadRtfFragment(BytesOf(Rtf('{|rtf1 pasted}')), ends);
    AssertFalse('a paste inside', d.Execute(TTyRichInsertFragment.Create(LinkOpen + 1, src, ends)));
    AssertFalse('a move of the open mark and before', d.Execute(TTyRichMove.Create(1, LinkOpen, 12)));
    AssertFalse('a move to inside', d.Execute(TTyRichMove.Create(0, 1, LinkOpen + 1)));
    AssertFalse('a copy to inside', d.Execute(TTyRichCopy.Create(0, 1, LinkOpen + 2)));
    AssertEquals('no step', 0, d.UndoDepth);
    // a copy of half of it
    raised := False;
    try
      d.Execute(TTyRichCopy.Create(LinkOpen - 1, 3, d.Text.ParaStart(1)));
    except
      on ETyRichModel do raised := True;
    end;
    AssertTrue('half a field copied: refused', raised);
    AssertTrue('the file', SameBytes(b, SaveOut(d)));
    // a whole one
    AssertTrue('the field copied', d.Execute(TTyRichCopy.Create(LinkOpen, LinkClose - LinkOpen + 1,
      d.Text.ParaStart(1))));
    AssertEquals('a second field', '[]/[]', AllObjects(d));
    after := SaveOut(d);
    AssertEquals('its bytes twice', 2, CountRaw(FieldGroup(LinkRtf, 1), StrOfBytes(after)));
    CheckBalanced(Self, 'two fields', after);
    d.Undo;
    AssertTrue('undone: the file', SameBytes(b, SaveOut(d)));
    // and moved
    AssertTrue('the field moved', d.Execute(TTyRichMove.Create(LinkOpen, LinkClose - LinkOpen + 1,
      d.Text.ParaStart(1) + 2)));
    AssertEquals('moved', '/[]', AllObjects(d));
    AssertEquals('its bytes once', 1, CountRaw(FieldGroup(LinkRtf, 1), StrOfBytes(SaveOut(d))));
  finally
    d.Free;
  end;
  { Marks out of their order: "b]y[c" out of "x[ab]y[cd]z" holds as many open marks as close
    ones, the close one first - the end of one field and the start of another. A copy of it
    is refused: it would put a close mark before any open one. }
  s := Rtf(H936 + '|pard x{|field{|*|fldinst A}{|fldrslt ab}}y{|field{|*|fldinst C}{|fldrslt cd}}z|par}');
  b := BytesOf(s);
  d := LoadDoc(b, False);
  try
    AssertRaw(Self, 'two fields', 'x' + OC + 'ab' + OC + 'y' + OC + 'cd' + OC + 'z', ParaText(d, 0));
    raised := False;
    try
      d.Execute(TTyRichCopy.Create(3, 5, 11));
    except
      on ETyRichModel do raised := True;
    end;
    AssertTrue('the end of one and the start of another copied: refused', raised);
    AssertEquals('no step', 0, d.UndoDepth);
    AssertEquals('the marks as they were', '[][]', AllObjects(d));
    AssertEquals('the paragraph as it was', 0, d.ParaFieldDepth(0));
    AssertTrue('the file', SameBytes(b, SaveOut(d)));
  finally
    d.Free;
  end;
end;

{ ---- what the model says of fields ---- }

{ The invariant every document keeps (TTyRichDocument's paragraph values): the first paragraph
  starts outside every field, each next one as deep as the one before leaves it, never below
  0, and the last one ends outside them. '' when it holds. }
function DepthsWrong(ADoc: TTyRichDocument): string;
var
  k, i, depth: Integer;
  runs: TTyRunArray;
begin
  depth := 0;
  for k := 0 to ADoc.Text.ParaCount - 1 do
  begin
    if ADoc.ParaFieldDepth(k) <> depth then
      Exit(Format('paragraph %d starts %d deep, its marks before say %d', [k, ADoc.ParaFieldDepth(k), depth]));
    runs := ADoc.RunsOf(k);
    for i := 0 to High(runs) do
      if runs[i].Obj is TTyRichFieldMark then
        if TTyRichFieldMark(runs[i].Obj).Kind = rfmOpen then Inc(depth)
        else
        begin
          Dec(depth);
          if depth < 0 then Exit(Format('paragraph %d: a close mark with no open one', [k]));
        end;
  end;
  if depth <> 0 then Exit(Format('%d fields open at the end', [depth]));
  Result := '';
end;

procedure CheckDepths(ATest: TTestCase; const AMsg: string; ADoc: TTyRichDocument);
begin
  ATest.AssertEquals(AMsg + ': the depths', '', DepthsWrong(ADoc));
end;

{ Every edit the document allows keeps each paragraph's depth what its marks make it: typing,
  a split and a join beside fields, a whole field deleted, copied and moved, a fragment with a
  field pasted, a table and its row, formats, a replace - and the undo and redo of each; and
  random allowed edits, undone, give the file back. }
procedure TTyRichFieldsTest.TestTheDepthOfEveryParagraphFollowsEveryEdit;
var
  b: TBytes;
  d, src: TTyRichDocument;
  n, i, steps: Integer;
  closeAt, p, len, a, z: TTyRichPos;
  ends: Boolean;
  f: TTyCharFormat;
  pf: TTyParaFormat;
  tally: TTyRichReplaceTally;
  cmd: TTyRichReplaceAllCommand;
  t: string;

  procedure Step(const AWhat: string; ACmd: TTyRichCommand);
  begin
    AssertTrue(AWhat + ': made', d.Execute(ACmd));
    Inc(steps);
    CheckDepths(Self, AWhat, d);
    d.Undo;
    CheckDepths(Self, AWhat + ', undone', d);
    d.Redo;
    CheckDepths(Self, AWhat + ', redone', d);
  end;

begin
  b := Fixture('hand-word-toc.rtf');
  d := LoadDoc(b, False);
  try
    CheckDepths(Self, 'read', d);
    steps := 0;
    n := d.Text.ParaCount;
    closeAt := d.Text.ParaStart(40) + d.Text.ParaLength(40) - 8;
    Step('typed first', TTyRichInsertText.Create(0, 'X'));
    Step('a paragraph split before the contents', TTyRichInsertText.Create(2, #10));
    closeAt := closeAt + 2;
    Step('a paragraph split right after it', TTyRichInsertText.Create(closeAt, 'ab' + #10 + 'cd'));
    Step('the paragraph after it joined', TTyRichDelete.Create(closeAt + 2, 1));
    Step('the paragraph before it joined', TTyRichDelete.Create(d.Text.ParaStart(1) - 1, 1));
    // a whole entry's link copied out of it, after the contents
    p := d.Text.ParaStart(10);
    Step('an entry''s link copied', TTyRichCopy.Create(p, d.Text.ParaLength(10), d.Text.Length));
    // the whole contents copied to the end, then moved to the start
    p := 0;
    while not (d.ObjectAt(p) is TTyRichFieldMark) do Inc(p);
    len := d.FieldPartner(p) + 1 - p;
    Step('the contents copied', TTyRichCopy.Create(p, len, d.Text.Length));
    Step('the contents moved', TTyRichMove.Create(d.Text.Length - len, len, 0));
    src := TyRichReadRtfFragment(BytesOf(LinkRtf), ends);
    Step('a link pasted', TTyRichInsertFragment.Create(d.Text.ParaStart(d.Text.ParaCount - 1), src, ends));
    Step('a table before it', TTyRichInsertTable.Create(0, 2, 2));
    Step('a row of it deleted', TTyRichDeleteRow.Create(0, 0));
    f := TyDefaultCharFormat;
    f.Style := [fsItalic];
    Step('all italic', TTyRichSetCharFormat.Create(TyRichRange(0, d.Text.Length), [cffItalic], f));
    pf := TyDefaultParaFormat;
    pf.SpaceAfter := 55;
    Step('every paragraph spaced', TTyRichSetParaFormat.Create(0, d.Text.ParaCount - 1, [pffSpaceAfter], pf));
    tally := Default(TTyRichReplaceTally);
    cmd := TTyRichReplaceAllCommand.Create(d, 'X', 'x' + #10 + 'y', [rfoMatchCase]);
    cmd.AllAtOnce := True;
    cmd.Tally := @tally;
    Step('a replace', cmd);
    // the whole contents deleted
    p := 0;
    while (p < d.Text.Length) and not (d.ObjectAt(p) is TTyRichFieldMark) do Inc(p);
    Step('a field deleted', TTyRichDelete.Create(p, d.FieldPartner(p) - p + 1));
    for i := 1 to steps do d.Undo;
    CheckDepths(Self, 'all undone', d);
    AssertTrue('all undone: the file', SameBytes(b, SaveOut(d)));
  finally
    d.Free;
  end;
  // random edits the document allows, then all undone
  FSeed := 7;
  d := LoadDoc(b, False);
  try
    steps := 0;
    for i := 1 to 300 do
    begin
      p := NextRandom(d.Text.Length + 1);
      // (half the time a place right beside a field: out of each field around it, to one of its ends)
      if NextRandom(2) = 0 then
        while d.FieldRangeAt(p, a, z) do
          if NextRandom(2) = 0 then p := a else p := z + 1;
      case NextRandom(3) of
        0: if d.Execute(TTyRichInsertText.Create(p, 'z')) then Inc(steps);
        1: if d.Execute(TTyRichInsertText.Create(p, #10)) then Inc(steps);
      else
        begin
          len := NextRandom(40) + 1;
          if p + len > d.Text.Length then len := d.Text.Length - p;
          if (len > 0) and d.Execute(TTyRichDelete.Create(p, len)) then Inc(steps);
        end;
      end;
      t := DepthsWrong(d);
      if t <> '' then Fail(Format('random edit %d: %s', [i, t]));
    end;
    AssertTrue(Format('edits made: %d', [steps]), steps > 50);
    for i := 1 to d.UndoDepth do d.Undo;
    CheckDepths(Self, 'random edits undone', d);
    AssertTrue('random edits undone: the file', SameBytes(b, SaveOut(d)));
  finally
    d.Free;
  end;
  AssertTrue(n > 0);
end;

{ How deep a place is, the field around it and a mark's partner - read from the place's own
  paragraph and the field's paragraphs, not the whole document: in a table of contents in the
  middle of a large lazily read file only the intervals of the contents are parsed. }
procedure TTyRichFieldsTest.TestTheFieldAroundAPlaceAndAMarksPartner;
var
  d: TTyRichDocument;
  a, z, p, tocOpen, tocClose: TTyRichPos;
  load: TTyRtfLoad;
  s: RawByteString;
  b: TBytes;
  parses, spans, i: Integer;
  tocStart, tocStop: Int64;
begin
  d := LoadDoc(BytesOf(LinkRtf), False);
  try
    AssertEquals('before the open mark', 0, d.FieldDepthAt(LinkOpen));
    AssertEquals('after it', 1, d.FieldDepthAt(LinkOpen + 1));
    AssertEquals('before the close mark', 1, d.FieldDepthAt(LinkClose));
    AssertEquals('after it', 0, d.FieldDepthAt(LinkClose + 1));
    AssertTrue('the field around 5', d.FieldRangeAt(LinkOpen + 2, a, z));
    AssertEquals('its open mark', LinkOpen, a);
    AssertEquals('its close mark', LinkClose, z);
    AssertFalse('none before it', d.FieldRangeAt(LinkOpen, a, z));
    AssertEquals('none: -1', -1, a);
    AssertEquals('the open mark''s partner', LinkClose, d.FieldPartner(LinkOpen));
    AssertEquals('the close mark''s partner', LinkOpen, d.FieldPartner(LinkClose));
    AssertEquals('no mark there', -1, d.FieldPartner(LinkOpen + 1));
  finally
    d.Free;
  end;
  d := LoadDoc(Fixture('hand-word-toc.rtf'), False);
  try
    tocOpen := d.Text.ParaStart(1) + 3;
    tocClose := d.Text.ParaStart(40) + d.Text.ParaLength(40) - 9;
    AssertTrue('its open mark', d.ObjectAt(tocOpen) is TTyRichFieldMark);
    AssertEquals('the contents'' partner', tocClose, d.FieldPartner(tocOpen));
    AssertEquals('and back', tocOpen, d.FieldPartner(tocClose));
    // inside an entry's link: the link
    p := d.Text.ParaStart(10) + 2;
    AssertEquals('two deep', 2, d.FieldDepthAt(p));
    AssertTrue('the link', d.FieldRangeAt(p, a, z));
    AssertEquals('the link''s open mark', d.Text.ParaStart(10), a);
    AssertEquals('the link''s close mark', d.Text.ParaStart(10) + d.Text.ParaLength(10) - 1, z);
    // at an entry's end, after its link: the contents
    p := d.Text.ParaStart(10) + d.Text.ParaLength(10);
    AssertTrue('the contents', d.FieldRangeAt(p, a, z));
    AssertEquals('the contents'' open mark', tocOpen, a);
    AssertEquals('the contents'' close mark', tocClose, z);
    for i := 2 to 40 do
      AssertEquals(Format('paragraph %d starts inside it', [i]), 1, d.ParaFieldDepth(i));
    AssertEquals('the one after it does not', 0, d.ParaFieldDepth(41));
  finally
    d.Free;
  end;
  // the cost: contents in the middle of a large file, read lazily
  s := TocRtf(1500, 6000);
  b := BytesOf(s);
  tocStart := Pos(Rtf('{|field|fldedit'), s) - 1;
  tocStop := tocStart + Length(FieldGroup(s, 1));
  d := LoadDoc(b, False);
  try
    load := TyRichRtfLoadOf(d);
    load.MaxResidentIntervals := MaxInt;
    spans := 0;
    for i := 0 to load.IntervalCount - 1 do
      if (load.IntervalStart(i) < tocStop) and
         ((i = load.IntervalCount - 1) or (load.IntervalStart(i + 1) > tocStart)) then
        Inc(spans);
    p := d.Text.ParaStart(6000 + 750) + 3;
    parses := load.ParseCount;
    AssertTrue('inside the contents', d.FieldRangeAt(p, a, z));
    AssertTrue('the link around it', d.FieldRangeAt(z + 1, a, z));
    AssertEquals('the contents', 6000, d.Text.ParaOfPos(a));
    AssertTrue(Format('only the contents'' intervals parsed: %d of %d (%d span it)',
      [load.ParseCount - parses, load.IntervalCount, spans]), load.ParseCount - parses <= spans + 1);
    AssertTrue('a file of many intervals', load.IntervalCount > 2 * spans);
  finally
    d.Free;
  end;
end;

{ A refusal names its reason: the document's (ChangeRefusal), the engine's (ETyRichRefused's
  Field), a composite's part, a table edit's (rtrInField) and a built-in command's
  (TyRichCommandRefusal). }
procedure TTyRichFieldsTest.TestARefusalSaysItIsAField;
var
  d: TTyRichDocument;
  comp: TTyRichCompositeCommand;
  cmd: TTyRichCommand;
  field: Boolean;
  f: TTyCharFormat;
begin
  d := LoadDoc(BytesOf(LinkRtf), False);
  try
    AssertTrue('an insert inside', d.ChangeRefusal(LinkOpen + 1, 0) = rcrField);
    AssertTrue('a delete of one mark', d.ChangeRefusal(LinkOpen, 1) = rcrField);
    AssertTrue('a delete of the whole field', d.ChangeRefusal(LinkOpen, LinkClose - LinkOpen + 1) = rcrNone);
    // the engine
    field := False;
    try
      d.Execute(TTyRichCopy.Create(LinkOpen - 1, 3, d.Text.ParaStart(1)));
    except
      on E: ETyRichRefused do field := E.Field and not E.FixedRow;
    end;
    AssertTrue('half a field copied: refused as a field', field);
    // a part of a composite
    comp := TTyRichCompositeCommand.Create;
    comp.Add(TTyRichInsertText.Create(0, 'a'));
    comp.Add(TTyRichInsertText.Create(LinkOpen + 2, 'b'));
    field := False;
    try
      d.Execute(comp);
    except
      on E: ETyRichRefused do field := E.Field and not E.FixedRow;
    end;
    AssertTrue('a composite''s part: refused as a field', field);
    AssertEquals('nothing kept', 0, d.UndoDepth);
    AssertTrue('a table', d.TableEditRefusal(TyRichTableEdit(rtkInsertTable, LinkOpen + 1, 0, 2, 2)) = rtrInField);
    f := TyDefaultCharFormat;
    cmd := TTyRichSetCharFormat.Create(TyRichRange(LinkOpen + 1, 2), [cffBold], f);
    try
      AssertFalse('a format of the result', cmd.CanExecute(d));
      AssertTrue('a format of the result: a field''s', TyRichCommandRefusal(d, cmd) = rcrField);
    finally
      cmd.Free;
    end;
    cmd := TTyRichDelete.Create(LinkClose, 1);
    try
      AssertTrue('a delete of the close mark: a field''s', TyRichCommandRefusal(d, cmd) = rcrField);
    finally
      cmd.Free;
    end;
  finally
    d.Free;
  end;
end;

{ The open mark keeps the field's group as the file has it and the \uc it was read under; the
  close mark keeps nothing; a clone is the same mark and shares the bytes; a mark is never
  inserted or replaced on its own. }
procedure TTyRichFieldsTest.TestTheOpenMarkKeepsTheFieldsBytes;
var
  d: TTyRichDocument;
  o, c, k: TTyRichFieldMark;
  n1, n2: Int64;
  g: RawByteString;
begin
  d := LoadDoc(BytesOf(LinkRtf), False);
  try
    o := d.ObjectAt(LinkOpen) as TTyRichFieldMark;
    c := d.ObjectAt(LinkClose) as TTyRichFieldMark;
    AssertTrue('open', o.Kind = rfmOpen);
    AssertTrue('close', c.Kind = rfmClose);
    AssertRaw(Self, 'its bytes', FieldGroup(LinkRtf, 1), o.Bytes);
    AssertEquals('the close one keeps none', 0, Length(c.Bytes));
    AssertEquals('one field', o.Id, c.Id);
    AssertEquals('where its group is in the file', Pos(Rtf('{|field'), LinkRtf) - 1, o.Id);
    AssertEquals('read under \uc1', 1, o.RawUc);
    // read from the file the document keeps: a range of it, not a copy, and not counted again
    AssertTrue('its bytes are the file''s', o.InFile);
    AssertEquals('its bytes where they are', Length(FieldGroup(LinkRtf, 1)), o.BytesLength);
    g := FieldGroup(LinkRtf, 1);
    AssertTrue('in place', CompareMem(o.BytesData, @g[1], o.BytesLength));
    AssertEquals('not counted as its own', o.InstanceSize, o.DataBytes);
    AssertTrue('nothing of its own to share', o.SharedData(n1) = nil);
    k := o.Clone as TTyRichFieldMark;
    try
      AssertTrue('a clone: the same kind', k.Kind = rfmOpen);
      AssertEquals('the same field', o.Id, k.Id);
      AssertFalse('bytes of its own', k.InFile);
      AssertRaw(Self, 'the same bytes', o.Bytes, k.Bytes);
      AssertTrue('counted as its bytes', k.SharedData(n1) <> nil);
      AssertEquals('all of them', Length(o.Bytes), n1);
      AssertEquals('its data', k.InstanceSize + n1, k.DataBytes);
      c := k.Clone as TTyRichFieldMark;
      try
        AssertTrue('a clone of it shares them', k.SharedData(n1) = c.SharedData(n2));
      finally
        c.Free;
      end;
    finally
      k.Free;
    end;
    c := d.ObjectAt(LinkClose) as TTyRichFieldMark;
    n1 := TTyRichFieldMark.NewId;
    n2 := TTyRichFieldMark.NewId;
    AssertTrue('an identity of its own for a mark made here', (n1 < 0) and (n2 < n1));
    // (the command holds the mark, and lets go of it when it is refused)
    k := TTyRichFieldMark.Create(rfmOpen, TTyRichFieldMark.NewId, '{}');
    AssertFalse('a mark alone: refused', d.Execute(TTyRichInsertObject.Create(0, k)));
    AssertEquals('nothing kept', 0, d.UndoDepth);
    AssertTrue('the file', SameBytes(BytesOf(LinkRtf), SaveOut(d)));
    // the file's bytes live as long as a mark of it does
    o.AddRef;
  finally
    d.Free;
  end;
  try
    AssertRaw(Self, 'the document gone, its mark''s bytes still there', FieldGroup(LinkRtf, 1), o.Bytes);
  finally
    o.Release;
  end;
end;

const
  // Times New Roman and SimSun under code page 1252: a font's charset decides its bytes
  H1252 = '{|rtf1|ansi|ansicpg1252|deff0{|fonttbl{|f0|froman Times New Roman;}' +
    '{|f1|fnil|fcharset134 SimSun;}}|pard|f0 ';

{ The character words the field's own group names before its instruction ({\field\f1 ...},
  {\field\b ...}) are in effect in its result: \f1 a font whose charset reads the result's
  \'xx as Chinese, \b a bold result. Not its paragraph words or its text words: those are no
  field's. Lazily and whole alike, and the bytes written back are the file's. }
procedure TTyRichFieldsTest.TestCharacterWordsOfTheFieldReachItsResult;
var
  s: RawByteString;
  b: TBytes;
  d: TTyRichDocument;
  full: Boolean;
begin
  s := Rtf(H1252 + 'a{|field|f1{|*|fldinst HYPERLINK "x"}{|fldrslt |''c1|''b4}}b|par}');
  b := BytesOf(s);
  for full := False to True do
  begin
    d := LoadDoc(b, full);
    try
      AssertRaw(Self, 'in the font of the field''s group', 'a' + OC + '链' + OC + 'b', ParaText(d, 0));
      AssertEquals('the result''s font', 'SimSun', CharFmt(d, 2).FontName);
      AssertEquals('the text after it in its own', 'Times New Roman', CharFmt(d, 4).FontName);
    finally
      d.Free;
    end;
  end;
  CheckRoundTrip(Self, 'a font', b);
  CheckLazyIsWhole(Self, 'a font', b, 0, False);
  CheckEditKeeps(Self, 'a font, typed before', b, TTyRichInsertText.Create(0, 'Q'), [FieldGroup(s, 1)]);
  s := Rtf(H1252 + 'a{|field|b{|*|fldinst X}{|fldrslt xy}}b|par}');
  b := BytesOf(s);
  d := LoadDoc(b, False);
  try
    AssertRaw(Self, 'bold', 'a' + OC + 'xy' + OC + 'b', ParaText(d, 0));
    AssertTrue('the result bold', fsBold in CharFmt(d, 2).Style);
    AssertTrue('all of it', fsBold in CharFmt(d, 3).Style);
    AssertFalse('the text before it not', fsBold in CharFmt(d, 0).Style);
    AssertFalse('the text after it not', fsBold in CharFmt(d, 5).Style);
  finally
    d.Free;
  end;
  CheckRoundTrip(Self, 'bold', b);
  CheckLazyIsWhole(Self, 'bold', b, 0, False);
  // a paragraph word and a text word in the field's group are not the result's
  s := Rtf(H1252 + 'a{|field|qc|tab{|*|fldinst X}{|fldrslt xy}}b|par}');
  b := BytesOf(s);
  d := LoadDoc(b, True);
  try
    AssertRaw(Self, 'no tab', 'a' + OC + 'xy' + OC + 'b', ParaText(d, 0));
    AssertTrue('not centred', d.Formats.ParaFormat(d.ParaFormatOf(0)).Align = paraLeft);
  finally
    d.Free;
  end;
  CheckRoundTrip(Self, 'a paragraph word and a tab', b);
end;

{ A result the reader would make nothing visible of - an optional hyphen alone, bookmarks
  alone, a destination it does not know, line ends - leaves the field one object of its bytes,
  as an empty result does. A non-breaking space or hyphen alone is a character: shown. }
procedure TTyRichFieldsTest.TestAResultThatShowsNothingStaysOneObject;
const
  Nothing: array[0..5] of RawByteString = (
    '{|field{|*|fldinst X}{|fldrslt |-}}',
    '{|field{|*|fldinst X}{|fldrslt {|*|bkmkstart b}}}',
    '{|field{|*|fldinst X}{|fldrslt {|*|bkmkstart b}{|*|bkmkend b}}}',
    '{|field{|*|fldinst X}{|fldrslt {|*|zzz some text}}}',
    '{|field{|*|fldinst X}{|fldrslt |-'#13#10'}}',
    '{|field{|*|fldinst X}{|fldrslt {|*|bkmkstart b}|-}}');
  Something: array[0..2] of RawByteString = (
    '{|field{|*|fldinst X}{|fldrslt |~}}',
    '{|field{|*|fldinst X}{|fldrslt |_}}',
    '{|field{|*|fldinst X}{|fldrslt {|*|bkmkstart b}x{|*|bkmkend b}}}');
var
  i: Integer;
  s, g, objs: RawByteString;
  b: TBytes;
  d: TTyRichDocument;
begin
  for i := 0 to High(Nothing) do
  begin
    g := Rtf(Nothing[i]);
    s := Rtf(H936 + '|pard a') + g + Rtf('b|par}');
    b := BytesOf(s);
    d := LoadDoc(b, True);
    try
      AssertEquals(Format('result %d: one object', [i]), 'O', AllObjects(d));
      AssertRaw(Self, Format('result %d: the paragraph', [i]), 'a' + OC + 'b', ParaText(d, 0));
      AssertRaw(Self, Format('result %d: its bytes', [i]), g, FirstOpaque(d).Bytes);
    finally
      d.Free;
    end;
    CheckRoundTrip(Self, Format('result %d', [i]), b);
    CheckLazyIsWhole(Self, Format('result %d', [i]), b, 0, False);
  end;
  for i := 0 to High(Something) do
  begin
    s := Rtf(H936 + '|pard a' + Something[i] + 'b|par}');
    b := BytesOf(s);
    d := LoadDoc(b, True);
    try
      objs := AllObjects(d);
      AssertTrue(Format('result %d: shown (%s)', [i, objs]), (objs <> '') and (objs[1] = '[') and
        (objs[Length(objs)] = ']'));
      AssertTrue(Format('result %d: a character between the marks', [i]),
        Length(WithoutObjects(ParaText(d, 0))) > 2);
    finally
      d.Free;
    end;
    CheckRoundTrip(Self, Format('shown result %d', [i]), b);
  end;
end;

{ A field larger than the reader's snapshot interval, holding one as large in its result: the
  index scan decides both, and a parse that begins after the outer field's start - at a
  snapshot inside its result - shows the inner one as the whole parse does: its marks, its
  paragraphs. Read lazily one interval at a time it is the whole parse. }
procedure TTyRichFieldsTest.TestALargeFieldIsDecidedAlikeWhereverAParseBegins;
var
  s: RawByteString;
  b: TBytes;
  d, full: TTyRichDocument;
  i: Integer;
begin
  s := H936 + '|pard a{|field{|*|fldinst INCLUDETEXT "outer.rtf"}{|fldrslt ';
  for i := 1 to 100 do
    s := s + '|pard outer line ' + IntToStr(i) + ', with some words to give it length|par ';
  s := s + '{|field{|*|fldinst INCLUDETEXT "inner.rtf"}{|fldrslt ';
  for i := 1 to 6000 do
    s := s + '|pard inner line ' + IntToStr(i) + ', with some words to give it length|par ';
  s := s + '}}';
  for i := 1 to 100 do
    s := s + '|pard outer again ' + IntToStr(i) + ', with some words to give it length|par ';
  s := Rtf(s + '}}z|par}');
  b := BytesOf(s);
  full := LoadDoc(b, True);
  d := LoadDoc(b, False);
  try
    AssertTrue('a file of several intervals', TyRichRtfLoadOf(d).IntervalCount > 3);
    TyRichRtfLoadOf(d).MaxResidentIntervals := 1;
    // the inner field's start first: its interval parsed alone, from its snapshot
    AssertEquals('the inner field opens: whole', '[', Copy(ObjectsOf(full, 100), 1, 1));
    AssertEquals('the inner field opens: lazily', '[', Copy(ObjectsOf(d, 100), 1, 1));
    AssertEquals('its depth', 2, d.FieldDepthAt(d.Text.ParaStart(100) + 1));
    AssertEquals('it closes: whole', ']', Copy(ObjectsOf(full, 6100), 1, 1));
    AssertEquals('it closes: lazily', ']', Copy(ObjectsOf(d, 6100), 1, 1));
  finally
    d.Free;
    full.Free;
  end;
  CheckLazyIsWhole(Self, 'two large fields', b, 1, False);
  CheckRoundTrip(Self, 'two large fields', b);
end;

{ What deciding fields reads (TTyRtfLoad.PreScannedBytes): fields nested eight deep around a
  file of many intervals - the index scan reads their group once, not once a level; parsing
  any interval of it, first or again after it went, reads nothing more (the scan kept the
  verdicts); and the same nest small (below CRtfKeptVerdictBytes), parsed again, is read once
  more - once, not once a level. }
procedure TTyRichFieldsTest.TestAFieldsGroupIsReadOnceToDecideIt;
var
  s, head, tail: RawByteString;
  b: TBytes;
  d: TTyRichDocument;
  load: TTyRtfLoad;
  i, n: Integer;
  scanned, group: Int64;
begin
  head := '';
  tail := '';
  for i := 1 to 8 do
  begin
    head := head + '{|field{|*|fldinst INCLUDETEXT "part' + IntToStr(i) + '.rtf"}{|fldrslt ';
    tail := tail + '}}';
  end;
  s := H936 + '|pard intro|par ' + head;
  for i := 1 to 6000 do
    s := s + '|pard line ' + IntToStr(i) + ' of the included text, to give it length|par ';
  s := Rtf(s + tail + '|pard tail|par}');
  b := BytesOf(s);
  group := Length(FieldGroup(s, 1));
  d := LoadDoc(b, False);
  try
    load := TyRichRtfLoadOf(d);
    load.MaxResidentIntervals := 1;
    AssertTrue('many intervals', load.IntervalCount > 4);
    scanned := load.PreScannedBytes;
    AssertTrue(Format('the scan read the group once: %d of %d', [scanned, group]),
      (scanned >= group) and (scanned < group + 1024));
    AssertEquals('eight open on the first screen', 8, d.ParaFieldDepth(2));
    n := d.Text.ParaCount;
    d.RunsOf(n div 2);
    d.RunsOf(n - 1);
    d.RunsOf(1);
    AssertEquals('parses read none of it again', scanned, load.PreScannedBytes);
    AssertTrue('the large ones kept', load.KeptVerdictCount >= 8);
  finally
    d.Free;
  end;
  // small: read again by a parse that meets it - once
  s := H936 + '|pard intro|par ' + head;
  for i := 1 to 50 do
    s := s + '|pard line ' + IntToStr(i) + ' of the included text, to give it length|par ';
  s := s + tail;
  for i := 1 to 8000 do
    s := s + '|pard after ' + IntToStr(i) + ', plain paragraphs to give the file length|par ';
  s := Rtf(s + '}');
  b := BytesOf(s);
  group := Length(FieldGroup(s, 1));
  AssertTrue('a small nest', group < CRtfKeptVerdictBytes);
  d := LoadDoc(b, False);
  try
    load := TyRichRtfLoadOf(d);
    load.MaxResidentIntervals := 1;
    AssertTrue('many intervals', load.IntervalCount > 4);
    scanned := load.PreScannedBytes;
    AssertTrue(Format('the scan: once, %d of %d', [scanned, group]), scanned < group + 1024);
    d.RunsOf(1);
    AssertTrue(Format('its interval parsed: once more, %d', [load.PreScannedBytes - scanned]),
      load.PreScannedBytes - scanned < group + 1024);
    scanned := load.PreScannedBytes;
    d.RunsOf(d.Text.ParaCount - 1);
    d.RunsOf(1);
    AssertTrue(Format('again after it went: once more, %d', [load.PreScannedBytes - scanned]),
      load.PreScannedBytes - scanned < group + 1024);
  finally
    d.Free;
  end;
  // whole: one pass
  d := LoadDoc(b, True);
  try
    load := TyRichRtfLoadOf(d);
    AssertTrue(Format('a whole parse: %d', [load.PreScannedBytes]), load.PreScannedBytes < 2 * group + 2048);
  finally
    d.Free;
  end;
end;

{ Word's way with its three fonts: \hich\af0\dbch\af1\loch\f0 before a field, \dbch in its
  result naming the double-byte font of the state around it. After an edit in that paragraph
  the field's bytes go back as the file has them - and read again, its result's characters
  are in the fonts they were: the slots in force before the field are in force before its
  bytes. Where nothing names a slot, nothing more is written. }
procedure TTyRichFieldsTest.TestTheSlotFontsAroundAFieldHoldAfterAnEdit;
var
  s: RawByteString;
  b, o: TBytes;
  d: TTyRichDocument;
  pf: TTyParaFormat;
begin
  // a0 b1 _2 [3 链4 接5 x6 y7 ]8 _9 c10 d11
  s := Rtf('{|rtf1|ansi|ansicpg1252|deff0{|fonttbl{|f0|froman Times New Roman;}' +
    '{|f1|fnil|fcharset134 SimSun;}}|pard|plain|f0|hich|af0|dbch|af1|loch|f0 ab ' +
    '{|field{|*|fldinst HYPERLINK "x"}{|fldrslt |dbch|u38142?|u25509?|loch xy}} cd|par next|par}');
  b := BytesOf(s);
  d := LoadDoc(b, True);
  try
    AssertRaw(Self, 'the paragraph', 'ab ' + OC + '链接xy' + OC + ' cd', ParaText(d, 0));
    AssertEquals('the double-byte characters in the double-byte font', 'SimSun', CharFmt(d, 4).FontName);
    AssertEquals('the rest in the low font', 'Times New Roman', CharFmt(d, 6).FontName);
  finally
    d.Free;
  end;
  CheckRoundTrip(Self, 'slots', b);
  CheckEditKeeps(Self, 'slots, typed before the field', b, TTyRichInsertText.Create(0, 'Q'),
    [FieldGroup(s, 1)]);
  CheckEditKeeps(Self, 'slots, typed after the field', b, TTyRichInsertText.Create(11, 'Q'),
    [FieldGroup(s, 1)]);
  pf := TyDefaultParaFormat;
  pf.Align := paraCenter;
  CheckEditKeeps(Self, 'slots, the paragraph centred', b,
    TTyRichSetParaFormat.Create(0, 0, [pffAlign], pf), [FieldGroup(s, 1)]);
  // no slot named around the field: an edit writes no slot word
  b := BytesOf(LinkRtf);
  d := LoadDoc(b, False);
  try
    d.Execute(TTyRichInsertText.Create(0, 'Q'));
    o := SaveOut(d);
    AssertEquals('no \loch', 0, CountRaw(Rtf('|loch'), StrOfBytes(o)));
    AssertEquals('no \hich', 0, CountRaw(Rtf('|hich'), StrOfBytes(o)));
    AssertEquals('no \dbch', 0, CountRaw(Rtf('|dbch'), StrOfBytes(o)));
    AssertEquals('no \af', 0, CountRaw(Rtf('|af'), StrOfBytes(o)));
  finally
    d.Free;
  end;
end;

type
  { Replaces the matches at At (each ALen long) by Text through the replace primitive itself -
    what a replace of every match does, without the find's own choice of matches. }
  TReplaceAtCommand = class(TTyRichCommand)
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    At: array of TTyRichPos;
    Len: TTyRichPos;
    Text: UTF8String;
    Skipped: Integer;
  end;

procedure TReplaceAtCommand.DoExecute(ADoc: TTyRichDocument);
begin
  ReplaceInParas(ADoc, At, 0, Length(At), Len, Text, Skipped);
end;

{ The replace primitive passes over a match inside a field's result whoever chose it (the
  others are replaced), and counts it. }
procedure TTyRichFieldsTest.TestAReplaceOfMatchesInsideAResultLeavesThem;
var
  b: TBytes;
  d: TTyRichDocument;
  cmd: TReplaceAtCommand;
begin
  b := BytesOf(LinkRtf);
  d := LoadDoc(b, False);
  try
    cmd := TReplaceAtCommand.Create;
    SetLength(cmd.At, 3);
    cmd.At[0] := 0;
    cmd.At[1] := LinkOpen + 1;
    cmd.At[2] := LinkClose + 2;
    cmd.Len := 1;
    cmd.Text := 'X';
    AssertTrue('two replaced', d.Execute(cmd));
    AssertEquals('one passed over', 1, cmd.Skipped);
    AssertRaw(Self, 'the result as it was', 'X里 ' + OC + '链接' + OC + ' X', ParaText(d, 0));
    CheckDepths(Self, 'after the replace', d);
    d.Undo;
    AssertTrue('undone: the file', SameBytes(b, SaveOut(d)));
  finally
    d.Free;
  end;
end;

{ The field around a place and a mark's partner, found by the paragraphs' depths: only the
  paragraphs that hold the two marks (and the place's own) are read, however long the field.
  A field that ends in the paragraph where the next one at its depth begins is not taken for
  that one. }
procedure TTyRichFieldsTest.TestTheFieldAroundAPlaceReadsOnlyItsMarksParagraphs;
var
  s: RawByteString;
  b: TBytes;
  d: TTyRichDocument;
  full: Boolean;
  a, z, p, open, close: TTyRichPos;
  load: TTyRtfLoad;
  parses, k: Integer;
  bytes: Int64;
begin
  // x[a / b][c / d]y: the first field ends in the paragraph where the second begins
  s := Rtf(H936 + '|pard x{|field{|*|fldinst A}{|fldrslt a|par b}}{|field{|*|fldinst B}{|fldrslt c|par d}}y|par}');
  b := BytesOf(s);
  for full := False to True do
  begin
    d := LoadDoc(b, full);
    try
      if full then AssertEquals('three paragraphs', '[/][/]', AllObjects(d));
      p := d.Text.ParaStart(2);
      AssertTrue('the second field around its last paragraph', d.FieldRangeAt(p, a, z));
      AssertEquals('its open mark: in the middle paragraph', d.Text.ParaStart(1) + 2, a);
      AssertEquals('its close mark', d.Text.ParaStart(2) + 1, z);
      AssertEquals('the open mark''s partner', z, d.FieldPartner(a));
      AssertEquals('the close mark''s partner', a, d.FieldPartner(z));
      AssertTrue('the first field around the middle paragraph''s start',
        d.FieldRangeAt(d.Text.ParaStart(1), a, z));
      AssertEquals('its open mark', 1, a);
      AssertEquals('its close mark', d.Text.ParaStart(1) + 1, z);
      AssertEquals('the first one''s partner', z, d.FieldPartner(1));
    finally
      d.Free;
    end;
  end;
  // the contents of 3,000 entries in a large file, read lazily: from its middle
  s := TocRtf(3000, 6000);
  b := BytesOf(s);
  d := LoadDoc(b, False);
  try
    load := TyRichRtfLoadOf(d);
    load.MaxResidentIntervals := MaxInt;
    AssertTrue('a file of many intervals', load.IntervalCount > 10);
    k := 6000 + 1500;
    p := d.Text.ParaStart(k) + d.Text.ParaLength(k);
    parses := load.ParseCount;
    bytes := load.ParsedBytes;
    AssertTrue('inside the contents', d.FieldRangeAt(p, open, close));
    AssertEquals('it opens in its first paragraph', 6000, d.Text.ParaOfPos(open));
    AssertEquals('it closes in its last', 6000 + 2999, d.Text.ParaOfPos(close));
    AssertTrue(Format('the intervals of the place and the two marks parsed, no more: %d',
      [load.ParseCount - parses]), load.ParseCount - parses <= 3);
    AssertTrue(Format('their bytes: %d', [load.ParsedBytes - bytes]),
      load.ParsedBytes - bytes <= 3 * 2 * 65536);
    parses := load.ParseCount;
    AssertEquals('the open mark''s partner', close, d.FieldPartner(open));
    AssertEquals('the close mark''s partner', open, d.FieldPartner(close));
    AssertEquals('nothing parsed again', parses, load.ParseCount);
  finally
    d.Free;
  end;
  // the same, the intervals let go of between the questions: each finds its marks' paragraphs
  d := LoadDoc(b, False);
  try
    load := TyRichRtfLoadOf(d);
    load.MaxResidentIntervals := 1;
    parses := load.ParseCount;
    AssertEquals('the partner of the contents'' close mark', open, d.FieldPartner(close));
    AssertTrue(Format('two intervals parsed: %d', [load.ParseCount - parses]),
      load.ParseCount - parses <= 2);
  finally
    d.Free;
  end;
end;

{ The keyword of a field's instruction (what follows \fldinst, up to its result) for Word's type
  number of it (word-toc.fields.txt), '' for one this file does not have. }
function WordFieldName(AType: Integer): string;
begin
  case AType of
    3: Result := 'REF';
    13: Result := 'TOC';
    26: Result := 'NUMPAGES';
    33: Result := 'PAGE';
    37: Result := 'PAGEREF';
    88: Result := 'HYPERLINK';
  else
    Result := '';
  end;
end;

{ A table of contents saved by Word itself (word-toc.rtf, Word 16): its 42 entries each a
  paragraph - a link holding the entry's text, a tab and a page number field -, the headings
  after it, three links in one paragraph, a REF, a table with a link, PAGE and NUMPAGES in its
  cells. Every paragraph's visible text is Word's own (word-toc.paragraphs.txt: Word counts a
  table row's end as a paragraph of its own, an empty line; the control does not - the cells
  are its paragraphs); every one of the 92 fields is shown (none is in a table but in one
  paragraph of a cell, none holds a section break), its marks pair, its instruction is Word's
  and the text between its marks is Word's result (word-toc.fields.txt). Lazily and whole
  alike, saved as read; an edit before the contents, in the paragraph after it and in the
  links' paragraph keeps every field's bytes and reads back the same; inside the contents
  nothing changes. }
procedure TTyRichFieldsTest.TestWordsOwnTableOfContents;
var
  b: TBytes;
  d: TTyRichDocument;
  lines, codes: TStringList;
  k, j, i, n, typ, last: Integer;
  runs: TTyRunArray;
  m: TTyRichFieldMark;
  p, z: TTyRichPos;
  t, w, g, instr: RawByteString;
  groups: array of RawByteString;
  c0, c1: TTyRichCell;
begin
  b := Fixture('word-toc.rtf');
  lines := TStringList.Create;
  codes := TStringList.Create;
  groups := nil;
  d := LoadDoc(b, True);
  try
    lines.LoadFromFile(FixtureDir + 'word-toc.paragraphs.txt');
    codes.LoadFromFile(FixtureDir + 'word-toc.fields.txt');
    AssertEquals('Word''s paragraphs', 137, lines.Count);
    AssertEquals('Word''s fields', 92, codes.Count);
    // the visible text, paragraph by paragraph
    j := 0;
    for k := 0 to d.Text.ParaCount - 1 do
    begin
      if k > 0 then
      begin
        c0 := d.CellAt(k - 1);
        c1 := d.CellAt(k);
        if (c0 <> nil) and ((c1 = nil) or (c1.Row <> c0.Row)) then
        begin
          AssertEquals(Format('Word''s row end before paragraph %d', [k]), '', lines[j]);
          Inc(j);
        end;
      end;
      AssertRaw(Self, Format('paragraph %d (Word''s %d)', [k, j + 1]), U(lines[j]),
        WithoutObjects(ParaText(d, k)));
      Inc(j);
    end;
    AssertEquals('every paragraph of Word''s', lines.Count, j);
    // the fields, in order: shown, paired, Word's instruction and result
    n := 0;
    for k := 0 to d.Text.ParaCount - 1 do
    begin
      runs := d.RunsOf(k);
      for i := 0 to High(runs) do
        if (runs[i].Obj is TTyRichOpaque) and (Pos(Rtf('|field'), TTyRichOpaque(runs[i].Obj).Bytes) > 0) then
          Fail(Format('paragraph %d: a field kept as one object', [k]))
        else if IsOpenMark(runs[i].Obj) then
        begin
          AssertTrue(Format('field %d: one of Word''s', [n]), n < codes.Count);
          m := TTyRichFieldMark(runs[i].Obj);
          p := d.Text.ParaStart(k) + runs[i].Start;
          z := d.FieldPartner(p);
          AssertTrue(Format('field %d: its close mark', [n]), IsCloseMark(d.ObjectAt(z)));
          AssertEquals(Format('field %d: and back', [n]), p, d.FieldPartner(z));
          w := codes[n];
          typ := StrToInt(Copy(w, 1, Pos(#9, w) - 1));
          Delete(w, 1, Pos(#9, w));
          Delete(w, 1, Pos(#9, w));
          g := m.Bytes;
          instr := Copy(g, Pos('fldinst', g), MaxInt);
          instr := Copy(instr, 1, Pos('fldrslt', instr));
          AssertTrue(Format('field %d: its instruction is Word''s %s', [n, WordFieldName(typ)]),
            (WordFieldName(typ) <> '') and (Pos(' ' + WordFieldName(typ) + ' ', instr) > 0));
          t := WithoutObjects(d.Text.GetText(p + 1, z - p - 1));
          t := StringReplace(t, #13#10, '<P>', [rfReplaceAll]);
          t := StringReplace(t, #13, '<P>', [rfReplaceAll]);
          t := StringReplace(t, #10, '<P>', [rfReplaceAll]);
          AssertRaw(Self, Format('field %d: Word''s result', [n]), U(w), t);
          SetLength(groups, n + 1);
          groups[n] := g;
          Inc(n);
        end;
    end;
    AssertEquals('every field shown', codes.Count, n);
    CheckDepths(Self, 'Word''s contents', d);
    // inside the contents: nothing changes
    p := d.Text.ParaStart(10) + 3;
    AssertTrue('inside an entry', d.FieldDepthAt(p) >= 1);
    AssertTrue('a field''s result', d.ChangeRefusal(p, 0) = rcrField);
    AssertFalse('a key refused', d.Execute(TTyRichInsertText.Create(p, 'Q')));
    // the paragraph after the contents (its close mark first), and the links' one
    last := -1;
    for k := 0 to d.Text.ParaCount - 1 do
      if Pos('[][][]', ObjectsOf(d, k)) > 0 then last := k;
    AssertTrue('the links'' paragraph', last > 43);
    k := 43;
    AssertEquals('the contents close in the paragraph after them', ']', Copy(ObjectsOf(d, k), 1, 1));
    p := d.Text.ParaStart(k) + d.Text.ParaLength(k);
    z := d.Text.ParaStart(last);
  finally
    d.Free;
    codes.Free;
    lines.Free;
  end;
  CheckRoundTrip(Self, 'Word''s contents', b);
  CheckLazyIsWhole(Self, 'Word''s contents', b, 1, True);
  CheckEditKeeps(Self, 'Word''s contents, typed before them', b, TTyRichInsertText.Create(0, 'Q'), groups);
  CheckEditKeeps(Self, 'Word''s contents, typed in the paragraph after them', b,
    TTyRichInsertText.Create(p, 'Q'), groups);
  CheckEditKeeps(Self, 'Word''s contents, typed in the links'' paragraph', b,
    TTyRichInsertText.Create(z, 'Q'), groups);
end;

initialization
  RegisterTest(TTyRichFieldsTest);
end.
