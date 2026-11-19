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
    // writing
    procedure TestAnEditOutsideAFieldKeepsItsBytes;
    procedure TestACopyTakesAWholeFieldAsItsBytesAndHalfAsText;
    // what may change
    procedure TestNothingInsideAResultChanges;
    procedure TestAWholeFieldDeletedComesBackOnUndo;
    procedure TestFormatsPassOverResults;
    procedure TestReplaceAllLeavesResults;
    procedure TestTablesAndObjectsAroundFields;
    procedure TestPastesAndMovesTakeWholeFields;
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

// the open mark keeps the field's bytes; the close mark keeps none
function IsOpenMark(O: TTyRichObject): Boolean;
begin
  Result := IsMark(O) and (O.DataBytes > O.InstanceSize);
end;

function IsCloseMark(O: TTyRichObject): Boolean;
begin
  Result := IsMark(O) and (O.DataBytes = O.InstanceSize);
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
      Length(FieldGroup(LinkRtf, 1)), ObjectAt(d, 0, LinkOpen).DataBytes - ObjectAt(d, 0, LinkOpen).InstanceSize);
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
    '{|field{|*|fldinst X}{|fldrslt x{|sectd y}}}',
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
        ObjectAt(d, 0, 2 * i - 1).DataBytes - ObjectAt(d, 0, 2 * i - 1).InstanceSize);
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
end;

initialization
  RegisterTest(TTyRichFieldsTest);
end.
