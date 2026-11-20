unit test.richedit.fieldctl;

{ TTyRichEdit around fields - a link, a table of contents, a page number - shown as their
  stored result between two marks that have no width: where the caret rests at a field's
  edge, what the keys do there, words, selections that cut a field, find, plain text out,
  formats. What is expected is worked out from the document model here (which objects have
  no width, where a run of them rests the caret), not from the layout the control asks.

  Headless, on the probe of test.richedit.control (the test device, the clipboard double):
  keys and the mouse through the control's own methods. No window, no clipboard, no message
  loop. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, fpcunit, testregistry, Controls, Graphics, LCLType, Forms,
  tyControls.Controller, tyControls.StrConsts,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RtfWrite, tyControls.RichEdit.Find, tyControls.RichEdit.Attrs,
  tyControls.RichEdit, test.richedit.control;

type
  { The control probe with an editor's seams and the mouse's buttons. }
  TFieldProbe = class(TRichProbe)
  protected
    procedure EditRefused(const AReason: string); override;
  public
    Refused: Integer;
    LastReason: string;
    procedure Key8(const AChar: RawByteString);
    procedure MDown(AButton: TMouseButton; AShift: TShiftState; X, Y: Integer);
    procedure MMove(AShift: TShiftState; X, Y: Integer);
    procedure MUp(AButton: TMouseButton; AShift: TShiftState; X, Y: Integer);
    procedure KeyUpOf(AKey: Word; AShift: TShiftState);
  end;

  TTyRichFieldControlTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TFieldProbe;
    FSelChanges, FChanges: Integer;
    procedure SelChanged(Sender: TObject);
    procedure Changed(Sender: TObject);
    function NewProbe: TFieldProbe;
    procedure Load(const S: RawByteString);
    procedure LoadBytes(const B: TBytes);
    procedure Reset;
    procedure Chars(const S: RawByteString);
    procedure Press(AKey: Word; AShift: TShiftState = []);
    procedure Click(const P: TPoint; AShift: TShiftState = []);
    function Doc: TTyRichDocument;
    function AllText: RawByteString;
    function SaveRtf: RawByteString;
    function PlainSave: RawByteString;
    function CharFmt(APos: TTyRichPos): TTyCharFormat;
    { The model's view of what has no width, and where a caret rests (the rule, worked out
      here): an object character whose object is a field's mark or kept bytes with nothing to
      show. }
    function Unseen(AChar: TTyRichPos): Boolean;
    function IsOpen(AChar: TTyRichPos): Boolean;
    function IsClose(AChar: TTyRichPos): Boolean;
    function RestOf(APos: TTyRichPos): TTyRichPos;
    function Seen(AFrom, ATo: TTyRichPos): Integer;
    function PointIn(AChar: TTyRichPos; AThird: Integer = 1): TPoint;
    function PosOfText(const S: RawByteString; AFrom: TTyRichPos = 0): TTyRichPos;
    procedure CheckSteps(const AWhat: string; AShift: TShiftState);
    procedure CheckSelection(const AWhat: string; AStart, ALen: TTyRichPos);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheCaretRestsOutsideALinkAtItsEdges;
    procedure TestArrowsStepOverMarksAsOneCharacter;
    procedure TestHomeEndWordsClicksAndSettersRest;
    procedure TestTypingAtALinksEdgesGoesOutside;
    procedure TestAKeyBesideAFieldSelectsIt;
    procedure TestAKeyPassesOverWhatHasNoWidth;
    procedure TestASelectionThatCutsAFieldGrows;
    procedure TestAnEditInsideAResultIsRefused;
    procedure TestAWholeFieldIsEditedAsAnySelection;
    procedure TestAnInputMethodAtAField;
    procedure TestADragOfASelectionThatCutsAField;
    procedure TestWordsPassOverMarks;
    procedure TestFindSeesThroughMarks;
    procedure TestReplaceFollowsTheEngine;
    procedure TestFormatsAcrossALink;
    procedure TestPlainTextHasNoMarks;
    procedure TestACopyIsNeverRefused;
  end;

implementation

const
  BS = #92;

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

function RawBytes(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

function Raw(const S: string): RawByteString;
begin
  Result := S;
  SetCodePage(Result, CP_NONE, False);
end;

// the bytes of a UTF8String, so that comparisons never convert
function U(const S: UTF8String): RawByteString;
begin
  Result := S;
  SetCodePage(Result, CP_NONE, False);
end;

// bytes as hex, for a message that shows them all
function Hex(const S: RawByteString): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do Result := Result + IntToHex(Ord(S[i]), 2);
end;

// U+FFFC, an object's character, as bytes
function OC: RawByteString;
begin
  Result := U(TyRichObjectChar);
end;

const
  Head = '{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}{|colortbl;|red0|green0|blue255;}|pard|f0 ';
  LinkField = '{|field{|*|fldinst HYPERLINK "http://x.test/a"}{|fldrslt {|ul|cf1 link}}}';

  { ab [link] cd: the open mark at 3, the result 4..7, the close mark at 8; 12 characters. }
  function LinkDoc: RawByteString;
  begin
    Result := Rtf(Head + 'ab ' + LinkField + ' cd|par}');
  end;

  { A table of contents of two entries, each a link holding its text, a tab and a page
    number field; text after it. }
  function TocDoc: RawByteString;
  begin
    Result := Rtf(Head + '{|field{|*|fldinst TOC |o "1-3" |h}{|fldrslt ' +
      '{|field{|*|fldinst HYPERLINK |l "_Toc1"}{|fldrslt Chapter 1|tab ' +
      '{|field{|*|fldinst PAGEREF _Toc1 |h}{|fldrslt 3}}}}|par ' +
      '{|field{|*|fldinst HYPERLINK |l "_Toc2"}{|fldrslt Chapter 2|tab ' +
      '{|field{|*|fldinst PAGEREF _Toc2 |h}{|fldrslt 6}}}}}} after|par}');
  end;

  { Two links touching, the first at the document's start, the second at a paragraph's end;
    a second paragraph that begins and ends with one; a bookmark's two ends. }
  function EdgesDoc: RawByteString;
  begin
    Result := Rtf(Head + '{|field{|*|fldinst HYPERLINK "a"}{|fldrslt one}}' +
      '{|field{|*|fldinst HYPERLINK "b"}{|fldrslt two}}|par ' +
      '{|field{|*|fldinst HYPERLINK "c"}{|fldrslt three}} x{|*|bkmkstart m1}yz{|*|bkmkend m1} ' +
      '{|field{|*|fldinst HYPERLINK "d"}{|fldrslt four}}|par}');
  end;

{ ---- the probe ---- }

procedure TFieldProbe.EditRefused(const AReason: string);
begin
  Inc(Refused);
  LastReason := AReason;
  inherited EditRefused(AReason);
end;

procedure TFieldProbe.Key8(const AChar: RawByteString);
var
  k: TUTF8Char;
begin
  k := '';
  SetLength(k, Length(AChar));
  if AChar <> '' then Move(AChar[1], k[1], Length(AChar));
  UTF8KeyPress(k);
end;

procedure TFieldProbe.MDown(AButton: TMouseButton; AShift: TShiftState; X, Y: Integer);
begin
  MouseDown(AButton, AShift, X, Y);
end;

procedure TFieldProbe.MMove(AShift: TShiftState; X, Y: Integer);
begin
  MouseMove(AShift, X, Y);
end;

procedure TFieldProbe.MUp(AButton: TMouseButton; AShift: TShiftState; X, Y: Integer);
begin
  MouseUp(AButton, AShift, X, Y);
end;

procedure TFieldProbe.KeyUpOf(AKey: Word; AShift: TShiftState);
var
  k: Word;
begin
  k := AKey;
  KeyUp(k, AShift);
end;

{ ---- the suite ---- }

procedure TTyRichFieldControlTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FRich := NewProbe;
end;

procedure TTyRichFieldControlTest.TearDown;
begin
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
end;

function TTyRichFieldControlTest.NewProbe: TFieldProbe;
begin
  Result := TFieldProbe.Create(nil);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 600, 400);
  Result.OnSelectionChange := @SelChanged;
  Result.OnChange := @Changed;
  Result.ResetCounts;
end;

procedure TTyRichFieldControlTest.SelChanged(Sender: TObject);
begin
  Inc(FSelChanges);
end;

procedure TTyRichFieldControlTest.Changed(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TTyRichFieldControlTest.LoadBytes(const B: TBytes);
var
  st: TBytesStream;
begin
  st := TBytesStream.Create(B);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  FRich.UpdateView;
  Reset;
end;

procedure TTyRichFieldControlTest.Load(const S: RawByteString);
begin
  LoadBytes(RawBytes(S));
end;

procedure TTyRichFieldControlTest.Reset;
begin
  FRich.Refused := 0;
  FRich.LastReason := '';
  FSelChanges := 0;
  FChanges := 0;
end;

procedure TTyRichFieldControlTest.Chars(const S: RawByteString);
var
  i, n: Integer;
  b: Byte;
begin
  i := 1;
  while i <= Length(S) do
  begin
    b := Byte(S[i]);
    if b < $C0 then n := 1
    else if b < $E0 then n := 2
    else if b < $F0 then n := 3
    else n := 4;
    FRich.Key8(Copy(S, i, n));
    Inc(i, n);
  end;
end;

procedure TTyRichFieldControlTest.Press(AKey: Word; AShift: TShiftState);
begin
  FRich.Press(AKey, AShift);
end;

procedure TTyRichFieldControlTest.Click(const P: TPoint; AShift: TShiftState);
begin
  FRich.MDown(mbLeft, AShift + [ssLeft], P.X, P.Y);
  FRich.MUp(mbLeft, AShift - [ssDouble], P.X, P.Y);
end;

function TTyRichFieldControlTest.Doc: TTyRichDocument;
begin
  Result := FRich.Document;
end;

function TTyRichFieldControlTest.AllText: RawByteString;
begin
  Result := Doc.Text.GetText(0, Doc.Text.Length);
  SetCodePage(Result, CP_NONE, False);
end;

function TTyRichFieldControlTest.SaveRtf: RawByteString;
var
  st: TBytesStream;
begin
  st := TBytesStream.Create;
  try
    FRich.SaveToStream(st, rfRtf);
    Result := '';
    SetLength(Result, st.Size);
    if st.Size > 0 then Move(st.Bytes[0], Result[1], st.Size);
    SetCodePage(Result, CP_NONE, False);
  finally
    st.Free;
  end;
end;

function TTyRichFieldControlTest.PlainSave: RawByteString;
var
  st: TBytesStream;
begin
  st := TBytesStream.Create;
  try
    FRich.SaveToStream(st, rfText);
    Result := '';
    SetLength(Result, st.Size);
    if st.Size > 0 then Move(st.Bytes[0], Result[1], st.Size);
    SetCodePage(Result, CP_NONE, False);
  finally
    st.Free;
  end;
end;

function TTyRichFieldControlTest.CharFmt(APos: TTyRichPos): TTyCharFormat;
var
  p, i, k: Integer;
  runs: TTyRunArray;
  o: TTyRichPos;
begin
  p := Doc.Text.ParaOfPos(APos);
  o := APos - Doc.Text.ParaStart(p);
  runs := Doc.RunsOf(p);
  k := 0;
  for i := 0 to High(runs) do
    if runs[i].Start <= o then k := i;
  Result := Doc.Formats.CharFormat(runs[k].Format);
end;

function TTyRichFieldControlTest.Unseen(AChar: TTyRichPos): Boolean;
var
  o: TTyRichObject;
begin
  Result := False;
  if (AChar < 0) or (AChar >= Doc.Text.Length) then Exit;
  o := Doc.ObjectAt(AChar);
  Result := (o is TTyRichFieldMark) or ((o is TTyRichOpaque) and (TTyRichOpaque(o).DisplayText = ''));
end;

function TTyRichFieldControlTest.IsOpen(AChar: TTyRichPos): Boolean;
var
  o: TTyRichObject;
begin
  Result := False;
  if (AChar < 0) or (AChar >= Doc.Text.Length) then Exit;
  o := Doc.ObjectAt(AChar);
  Result := (o is TTyRichFieldMark) and (TTyRichFieldMark(o).Kind = rfmOpen);
end;

function TTyRichFieldControlTest.IsClose(AChar: TTyRichPos): Boolean;
var
  o: TTyRichObject;
begin
  Result := False;
  if (AChar < 0) or (AChar >= Doc.Text.Length) then Exit;
  o := Doc.ObjectAt(AChar);
  Result := (o is TTyRichFieldMark) and (TTyRichFieldMark(o).Kind = rfmClose);
end;

{ The rule: a run of objects with no width is one place; the caret's position there is the
  leftmost one right of every close mark and left of every open mark in the run, else the
  run's first. }
function TTyRichFieldControlTest.RestOf(APos: TTyRichPos): TTyRichPos;
var
  rs, re, lo, hi, c: TTyRichPos;
begin
  rs := APos;
  while Unseen(rs - 1) do Dec(rs);
  re := APos;
  while Unseen(re) do Inc(re);
  if rs = re then Exit(APos);
  lo := rs;
  hi := re;
  for c := rs to re - 1 do
  begin
    if IsClose(c) then lo := c + 1;
    if IsOpen(c) and (c < hi) then hi := c;
  end;
  if lo <= hi then Result := lo else Result := rs;
end;

{ What a person sees between two places: the characters with a width (a paragraph's end one). }
function TTyRichFieldControlTest.Seen(AFrom, ATo: TTyRichPos): Integer;
var
  c: TTyRichPos;
begin
  Result := 0;
  for c := Math.Min(AFrom, ATo) to Math.Max(AFrom, ATo) - 1 do
    if not Unseen(c) then Inc(Result);
end;

{ A client point on character AChar: AThird of its width in (1 its left part, 2 its right). }
function TTyRichFieldControlTest.PointIn(AChar: TTyRichPos; AThird: Integer): TPoint;
var
  r, r2: TRect;
begin
  r := FRich.PositionRect(AChar);
  r2 := FRich.PositionRect(AChar + 1, True);
  AssertTrue('the character is in view', r.Bottom > r.Top);
  Result.X := r.Left + (r2.Left - r.Left) * AThird div 3;
  Result.Y := (r.Top + r.Bottom) div 2;
end;

function TTyRichFieldControlTest.PosOfText(const S: RawByteString; AFrom: TTyRichPos): TTyRichPos;
begin
  Result := FRich.FindText(S, AFrom, -1, []);
  AssertTrue('the text is there: ' + S, Result >= 0);
end;

{ Right through the whole text and Left back: every step one character with a width, the
  caret on resting places only; with Shift the anchor stays. }
procedure TTyRichFieldControlTest.CheckSteps(const AWhat: string; AShift: TShiftState);
var
  len, prev, a: TTyRichPos;
  n, want: Integer;
begin
  len := Doc.Text.Length;
  FRich.SelStart := 0;
  a := FRich.SelStart;
  AssertEquals(AWhat + ': the start rests', RestOf(0), a);
  want := Seen(a, RestOf(len));
  n := 0;
  repeat
    prev := FRich.CaretIndex;
    Press(VK_RIGHT, AShift);
    if FRich.CaretIndex = prev then Break;
    Inc(n);
    AssertEquals(Format('%s: Right %d sees one character', [AWhat, n]), 1,
      Seen(prev, FRich.CaretIndex));
    AssertEquals(Format('%s: Right %d rests', [AWhat, n]), RestOf(FRich.CaretIndex),
      FRich.CaretIndex);
    if ssShift in AShift then AssertEquals(AWhat + ': the anchor stays', a, FRich.SelStart);
  until n > len + 2;
  AssertEquals(AWhat + ': as many steps as characters seen', want, n);
  AssertEquals(AWhat + ': at the end', RestOf(len), FRich.CaretIndex);
  n := 0;
  repeat
    prev := FRich.CaretIndex;
    Press(VK_LEFT, AShift);
    if FRich.CaretIndex = prev then Break;
    Inc(n);
    AssertEquals(Format('%s: Left %d sees one character', [AWhat, n]), 1,
      Seen(FRich.CaretIndex, prev));
    AssertEquals(Format('%s: Left %d rests', [AWhat, n]), RestOf(FRich.CaretIndex),
      FRich.CaretIndex);
    if ssShift in AShift then AssertEquals(AWhat + ': the anchor stays back', a, FRich.SelStart);
  until n > len + 2;
  AssertEquals(AWhat + ': as many steps back', want, n);
  AssertEquals(AWhat + ': back at the start', a, FRich.CaretIndex);
  if ssShift in AShift then AssertEquals(AWhat + ': nothing selected at the end', 0, FRich.SelLength);
end;

procedure TTyRichFieldControlTest.CheckSelection(const AWhat: string; AStart, ALen: TTyRichPos);
begin
  AssertEquals(AWhat + ': the selection''s start', AStart, FRich.SelStart);
  AssertEquals(AWhat + ': the selection''s length', ALen, FRich.SelLength);
end;

{ A link's start is before its open mark, its end after its close mark - from a step, a click,
  a setter. }
procedure TTyRichFieldControlTest.TestTheCaretRestsOutsideALinkAtItsEdges;
var
  p: TPoint;
begin
  Load(LinkDoc);
  AssertEquals('the text', 12, Doc.Text.Length);
  AssertTrue('the open mark at 3', IsOpen(3));
  AssertTrue('the close mark at 8', IsClose(8));
  FRich.SelStart := 2;
  Press(VK_RIGHT);
  AssertEquals('Right to the link''s start: before its open mark', Int64(3), FRich.CaretIndex);
  Press(VK_RIGHT);
  AssertEquals('one more: after its first letter', Int64(5), FRich.CaretIndex);
  FRich.SelStart := 7;
  Press(VK_RIGHT);
  AssertEquals('Right past its last letter: after its close mark', Int64(9), FRich.CaretIndex);
  Press(VK_LEFT);
  AssertEquals('Left from its end: before its last letter', Int64(7), FRich.CaretIndex);
  FRich.SelStart := 5;
  Press(VK_LEFT);
  AssertEquals('Left from its second letter: before its open mark', Int64(3), FRich.CaretIndex);
  // a setter from code
  FRich.SelStart := 4;
  AssertEquals('SelStart inside the run: its resting place', Int64(3), FRich.SelStart);
  FRich.SelStart := 8;
  AssertEquals('SelStart before the close mark: after it', Int64(9), FRich.SelStart);
  FRich.CaretIndex := 4;
  AssertEquals('CaretIndex too', Int64(3), FRich.CaretIndex);
  FRich.SelStart := 0;
  FRich.SelLength := 8;
  CheckSelection('SelLength to before the close mark', 0, 9);
  FRich.SelLength := 4;
  CheckSelection('SelLength to after the open mark', 0, 3);
  // a click on the right part of the last letter, on the left part of the first
  p := PointIn(7, 2);
  Click(p);
  AssertEquals('a click at the link''s end: after its close mark', Int64(9), FRich.CaretIndex);
  p := PointIn(4, 0);
  Click(p);
  AssertEquals('a click at the link''s start: before its open mark', Int64(3), FRich.CaretIndex);
  // the undo puts the caret back on a resting place too
  FRich.SelStart := 9;
  Chars('Z');
  FRich.Undo;
  AssertEquals('after the undo', RestOf(FRich.CaretIndex), FRich.CaretIndex);
end;

{ Right and Left over a link's edges, a table of contents' nested fields, two fields touching,
  fields first and last in a paragraph and the document, a bookmark's ends: one character seen
  a step, both ways, with and without Shift. }
procedure TTyRichFieldControlTest.TestArrowsStepOverMarksAsOneCharacter;
begin
  Load(LinkDoc);
  CheckSteps('a link', []);
  CheckSteps('a link, Shift', [ssShift]);
  Load(TocDoc);
  AssertEquals('the contents start with two open marks', True, IsOpen(0) and IsOpen(1));
  CheckSteps('a table of contents', []);
  CheckSteps('a table of contents, Shift', [ssShift]);
  Load(EdgesDoc);
  CheckSteps('fields touching, at the ends, a bookmark', []);
  CheckSteps('fields touching, at the ends, a bookmark, Shift', [ssShift]);
  // two links touching: one place between them, after the first's close mark
  FRich.SelStart := 4;
  AssertEquals('after "one": the first''s close and the second''s open are one place',
    Int64(5), FRich.CaretIndex);
  AssertTrue('... between the two marks', IsClose(4) and IsOpen(5));
end;

procedure TTyRichFieldControlTest.TestHomeEndWordsClicksAndSettersRest;
var
  e: TTyRichPos;
begin
  Load(EdgesDoc);
  // the document's first line begins with a link, its second ends with one
  FRich.SelStart := 3;
  Press(VK_HOME);
  AssertEquals('Home: before the first link''s open mark', Int64(0), FRich.CaretIndex);
  Press(VK_END);
  e := Doc.Text.ParaLength(0);
  AssertEquals('End: after the second link''s close mark', e, FRich.CaretIndex);
  FRich.SelStart := Doc.Text.ParaStart(1) + 2;
  Press(VK_HOME);
  AssertEquals('Home of the second paragraph: before its link', Doc.Text.ParaStart(1),
    FRich.CaretIndex);
  Press(VK_END);
  AssertEquals('End of it: after its last link', Doc.Text.Length, FRich.CaretIndex);
  Press(VK_HOME, [ssCtrl]);
  AssertEquals('Ctrl+Home', Int64(0), FRich.CaretIndex);
  Press(VK_END, [ssCtrl]);
  AssertEquals('Ctrl+End', Doc.Text.Length, FRich.CaretIndex);
  // the word steps
  Load(LinkDoc);
  FRich.SelStart := 0;
  Press(VK_RIGHT, [ssCtrl]);
  AssertEquals('Ctrl+Right: to the link''s start, before its open mark', Int64(3), FRich.CaretIndex);
  Press(VK_RIGHT, [ssCtrl]);
  AssertEquals('Ctrl+Right: past the link and the space', Int64(10), FRich.CaretIndex);
  Press(VK_LEFT, [ssCtrl]);
  AssertEquals('Ctrl+Left: back', Int64(3), FRich.CaretIndex);
  Press(VK_RIGHT, [ssCtrl, ssShift]);
  CheckSelection('Ctrl+Shift+Right: the link and the space', 3, 7);
  // a page key and Down: resting places too
  FRich.SelStart := 0;
  Press(VK_NEXT);
  AssertEquals('Page Down', RestOf(FRich.CaretIndex), FRich.CaretIndex);
  Load(TocDoc);
  FRich.SelStart := 2;
  Press(VK_DOWN);
  AssertEquals('Down into the next entry', RestOf(FRich.CaretIndex), FRich.CaretIndex);
  Press(VK_HOME);
  AssertEquals('Home of an entry: before its open mark', Doc.Text.ParaStart(1), FRich.CaretIndex);
  AssertTrue('... the entry''s', IsOpen(Doc.Text.ParaStart(1)));
end;

{ What is typed at a link's start or end goes outside it, in the look of the text outside; the
  field's bytes are saved as they came. }
procedure TTyRichFieldControlTest.TestTypingAtALinksEdgesGoesOutside;
var
  s: RawByteString;
begin
  Load(LinkDoc);
  FRich.SelStart := 3;
  Chars('X');
  AssertEquals('typed before the open mark', 'X', Doc.Text.GetText(3, 1));
  AssertTrue('the open mark after it', IsOpen(4));
  AssertFalse('not in the link''s look (underline)', fsUnderline in CharFmt(3).Style);
  AssertEquals('not in the link''s colour', CharFmt(0).Color, CharFmt(3).Color);
  FRich.SelStart := 10;
  AssertTrue('after the close mark', IsClose(9));
  Chars('Y');
  AssertEquals('typed after the close mark', 'Y', Doc.Text.GetText(10, 1));
  AssertFalse('not in the link''s look', fsUnderline in CharFmt(10).Style);
  AssertEquals('not in the link''s colour either', CharFmt(0).Color, CharFmt(10).Color);
  AssertEquals('nothing refused', 0, FRich.Refused);
  s := SaveRtf;
  AssertTrue('the field''s bytes as they came', Pos(Rtf(LinkField), s) > 0);
end;

{ No selection: Backspace right after a field, Delete right before one, and the word keys
  there, select the field and tell nothing; the next press deletes it, one step, undone and
  redone with its bytes. }
procedure TTyRichFieldControlTest.TestAKeyBesideAFieldSelectsIt;
var
  keys: array[0..3] of Word;
  shifts: array[0..3] of TShiftState;
  places, lens: array[0..3] of TTyRichPos;
  afters: array[0..3] of RawByteString;
  i: Integer;
  before, s: RawByteString;
begin
  keys[0] := VK_BACK; shifts[0] := []; places[0] := 9; lens[0] := 6; afters[0] := 'ab  cd';
  keys[1] := VK_DELETE; shifts[1] := []; places[1] := 3; lens[1] := 6; afters[1] := 'ab  cd';
  keys[2] := VK_BACK; shifts[2] := [ssCtrl]; places[2] := 9; lens[2] := 6; afters[2] := 'ab  cd';
  // (the word Ctrl+Delete takes is the link and its space)
  keys[3] := VK_DELETE; shifts[3] := [ssCtrl]; places[3] := 3; lens[3] := 7; afters[3] := 'ab cd';
  for i := 0 to 3 do
  begin
    Load(LinkDoc);
    before := AllText;
    FRich.SelStart := places[i];
    Reset;
    Press(keys[i], shifts[i]);
    CheckSelection(Format('key %d: the field selected', [i]), 3, lens[i]);
    AssertEquals(Format('key %d: nothing changed', [i]), before, AllText);
    AssertEquals(Format('key %d: no step', [i]), 0, Doc.UndoDepth);
    AssertEquals(Format('key %d: nothing told', [i]), 0, FRich.Refused);
    AssertEquals(Format('key %d: the selection reported once', [i]), 1, FSelChanges);
    // the second press acts on what is selected
    Press(keys[i], shifts[i]);
    AssertEquals(Format('key %d: the field gone', [i]), afters[i], AllText);
    AssertEquals(Format('key %d: one step', [i]), 1, Doc.UndoDepth);
    AssertEquals(Format('key %d: still nothing told', [i]), 0, FRich.Refused);
    FRich.Undo;
    AssertEquals(Format('key %d: undone', [i]), before, AllText);
    s := SaveRtf;
    AssertTrue(Format('key %d: its bytes back', [i]), Pos(Rtf(LinkField), s) > 0);
    FRich.Redo;
    AssertEquals(Format('key %d: redone', [i]), afters[i], AllText);
  end;
end;

{ What has no width is passed over by a key, and stays: a bookmark's ends, a field that shows
  nothing. }
procedure TTyRichFieldControlTest.TestAKeyPassesOverWhatHasNoWidth;
var
  d: TTyRichDocument;
  bs, be: TTyRichPos;
begin
  Load(Rtf(Head + 'ab{|*|bkmkstart m1}cd{|*|bkmkend m1}ef|par}'));
  d := Doc;
  bs := 2;
  AssertTrue('the bookmark''s start has no width', Unseen(bs));
  be := 5;
  AssertTrue('its end neither', Unseen(be));
  FRich.SelStart := 3;
  AssertEquals('after the start: before it (the run''s first place)', Int64(2), FRich.CaretIndex);
  Press(VK_DELETE);
  AssertEquals('Delete: the c, the bookmark''s start stays', Hex(Raw('ab') + OC + Raw('d') + OC + Raw('ef')),
    Hex(AllText));
  FRich.SelStart := 5;
  AssertEquals('after the end: before it', Int64(4), FRich.CaretIndex);
  Press(VK_BACK);
  AssertEquals('Backspace: the d, the bookmark''s end stays', Hex(Raw('ab') + OC + OC + Raw('ef')),
    Hex(AllText));
  AssertTrue('steps', d.UndoDepth >= 1);
  AssertEquals('nothing told', 0, FRich.Refused);
  // a selection that covers them takes them
  FRich.SelStart := 0;
  FRich.SelLength := d.Text.Length;
  Press(VK_DELETE);
  AssertEquals('a selection takes them', 0, d.Text.Length);
end;

{ A selection that cuts a field, and Delete, Backspace, cut, typing, paste: nothing changes, the
  selection grows to hold the field, told once; the second attempt acts on it. }
procedure TTyRichFieldControlTest.TestASelectionThatCutsAFieldGrows;
var
  i: Integer;
  before: RawByteString;
  what: string;

  procedure Gesture(AIndex: Integer);
  begin
    case AIndex of
      0: Press(VK_DELETE);
      1: Press(VK_BACK);
      2: FRich.CutToClipboard;
      3: Chars('q');
      4:
        begin
          FRich.ClipRtf := '';
          FRich.ClipText := 'pasted';
          FRich.PasteFromClipboard;
        end;
      5: Press(VK_RETURN);
    end;
  end;

begin
  for i := 0 to 5 do
  begin
    what := Format('gesture %d', [i]);
    // from before the link into it, and from inside it to past it
    Load(LinkDoc);
    before := AllText;
    FRich.SelStart := 1;
    FRich.SelLength := 5;
    CheckSelection(what + ': the cutting selection', 1, 5);
    Reset;
    FRich.ClipWrites := 0;
    Gesture(i);
    CheckSelection(what + ': grown to hold the field', 1, 8);
    AssertEquals(what + ': nothing changed', before, AllText);
    AssertEquals(what + ': no step', 0, Doc.UndoDepth);
    AssertEquals(what + ': told once', 1, FRich.Refused);
    AssertEquals(what + ': the field''s reason', rsRichEditRefusedField, FRich.LastReason);
    AssertEquals(what + ': nothing copied', 0, FRich.ClipWrites);
    // the second attempt
    Gesture(i);
    AssertEquals(what + ': the second attempt is not refused', 1, FRich.Refused);
    AssertEquals(what + ': one step', 1, Doc.UndoDepth);
    AssertFalse(what + ': the field went with it', Pos(OC, AllText) > 0);
    // the other side
    Load(LinkDoc);
    FRich.SelStart := 5;
    FRich.SelLength := 6;
    CheckSelection(what + ': from inside to past it', 5, 6);
    Reset;
    Gesture(i);
    CheckSelection(what + ': grown back to the open mark', 3, 8);
    AssertEquals(what + ': nothing changed there either', before, AllText);
    AssertEquals(what + ': told once there too', 1, FRich.Refused);
  end;
end;

{ Inside a result: a caret or a selection there, any edit is refused with the field's reason,
  nothing changes, the selection stays. }
procedure TTyRichFieldControlTest.TestAnEditInsideAResultIsRefused;
var
  before: RawByteString;
begin
  Load(LinkDoc);
  before := AllText;
  FRich.SelStart := 5;
  Reset;
  Chars('x');
  Press(VK_BACK);
  Press(VK_DELETE);
  Press(VK_RETURN);
  AssertEquals('four refused', 4, FRich.Refused);
  AssertEquals('the field''s reason', rsRichEditRefusedField, FRich.LastReason);
  AssertEquals('the caret stays', Int64(5), FRich.CaretIndex);
  FRich.SelStart := 5;
  FRich.SelLength := 2;
  Reset;
  Press(VK_DELETE);
  Chars('x');
  FRich.CutToClipboard;
  AssertEquals('a selection inside: refused each time', 3, FRich.Refused);
  CheckSelection('the selection stays', 5, 2);
  AssertEquals('nothing changed', before, AllText);
  AssertEquals('no step', 0, Doc.UndoDepth);
  // in a table of contents: an entry's text is inside two results
  Load(TocDoc);
  FRich.SelStart := 4;
  Reset;
  Chars('x');
  AssertEquals('an entry''s text: refused', 1, FRich.Refused);
  // Backspace at an entry's start: the paragraph end before is the contents'
  FRich.SelStart := Doc.Text.ParaStart(1);
  Press(VK_BACK);
  AssertEquals('joining two entries: refused', 2, FRich.Refused);
end;

{ A selection that holds whole fields only is edited as any selection: deleted, typed over,
  cut, pasted over - one step, the undo brings the field back with its bytes. }
procedure TTyRichFieldControlTest.TestAWholeFieldIsEditedAsAnySelection;
var
  i: Integer;
  before, s: RawByteString;
  what: string;
begin
  for i := 0 to 3 do
  begin
    what := Format('edit %d', [i]);
    Load(LinkDoc);
    before := AllText;
    FRich.SelStart := 3;
    FRich.SelLength := 6;
    Reset;
    case i of
      0: Press(VK_DELETE);
      1: Chars('W');
      2: FRich.CutToClipboard;
      3:
        begin
          FRich.ClipRtf := '';
          FRich.ClipText := 'P';
          FRich.PasteFromClipboard;
        end;
    end;
    AssertEquals(what + ': not refused', 0, FRich.Refused);
    AssertEquals(what + ': one step', 1, Doc.UndoDepth);
    AssertFalse(what + ': no mark left', Pos(OC, AllText) > 0);
    FRich.Undo;
    AssertEquals(what + ': undone', before, AllText);
    s := SaveRtf;
    AssertTrue(what + ': the field''s bytes back', Pos(Rtf(LinkField), s) > 0);
    FRich.Redo;
    AssertFalse(what + ': redone', Pos(OC, AllText) > 0);
  end;
end;

{ An input method's composition: asked for inside a result, refused; over a selection that cuts
  a field, the selection grows and the refusal is told once. }
procedure TTyRichFieldControlTest.TestAnInputMethodAtAField;
begin
  Load(LinkDoc);
  FRich.SelStart := 5;
  Reset;
  AssertFalse('inside a result: no composition', FRich.BeginComposition);
  AssertEquals('told once', 1, FRich.Refused);
  AssertEquals('the field''s reason', rsRichEditRefusedField, FRich.LastReason);
  FRich.SelStart := 1;
  FRich.SelLength := 5;
  Reset;
  AssertFalse('over a cutting selection: no composition', FRich.BeginComposition);
  CheckSelection('grown', 1, 8);
  AssertEquals('told once there too', 1, FRich.Refused);
  // beside the link: one goes in outside it
  FRich.SelStart := 3;
  Reset;
  AssertTrue('at the link''s start: a composition', FRich.BeginComposition);
  FRich.UpdateComposition('zz');
  FRich.CommitComposition('zz');
  AssertEquals('committed before the open mark', Raw('ab zz'), Copy(AllText, 1, 5));
  AssertTrue('the open mark after it', IsOpen(5));
end;

{ A drag of a selection that cuts a field: moved, nothing goes, the selection grows, told once;
  with Ctrl (a copy) it is never refused - what a clipboard copy takes goes in. }
procedure TTyRichFieldControlTest.TestADragOfASelectionThatCutsAField;
var
  a, b: TPoint;
  before: RawByteString;
  n: Integer;
begin
  Load(LinkDoc);
  before := AllText;
  FRich.SelStart := 1;
  FRich.SelLength := 5;
  Reset;
  a := PointIn(4, 1);
  b := PointIn(11, 2);
  FRich.MDown(mbLeft, [ssLeft], a.X, a.Y);
  FRich.MMove([ssLeft], a.X + 20, a.Y);
  FRich.MMove([ssLeft], b.X, b.Y);
  FRich.MUp(mbLeft, [], b.X, b.Y);
  AssertEquals('moved: nothing changed', before, AllText);
  CheckSelection('the selection grown', 1, 8);
  AssertEquals('told once', 1, FRich.Refused);
  // a copy (Ctrl): the text a clipboard copy takes, at the place
  FRich.SelStart := 1;
  FRich.SelLength := 5;
  Reset;
  n := Doc.Text.Length;
  FRich.MDown(mbLeft, [ssLeft, ssCtrl], a.X, a.Y);
  FRich.MMove([ssLeft, ssCtrl], a.X + 20, a.Y);
  FRich.MMove([ssLeft, ssCtrl], b.X, b.Y);
  FRich.MUp(mbLeft, [ssCtrl], b.X, b.Y);
  AssertEquals('copied: not refused', 0, FRich.Refused);
  AssertEquals('the copy''s text went in: "b li"', n + 4, Doc.Text.Length);
  AssertEquals('as text, at the place', Hex('b li'), Hex(Raw(Doc.Text.GetText(12, 4))));
end;

{ A mark is no word and no break: word steps, a double click, word deletion go as if it were
  not there. }
procedure TTyRichFieldControlTest.TestWordsPassOverMarks;
var
  p: TPoint;
begin
  // ab[cd]ef: one word
  Load(Rtf(Head + 'ab{|field{|*|fldinst HYPERLINK "x"}{|fldrslt cd}}ef gh|par}'));
  FRich.SelStart := 0;
  Press(VK_RIGHT, [ssCtrl]);
  AssertEquals('Ctrl+Right: past the whole word and its space', Int64(9), FRich.CaretIndex);
  Press(VK_LEFT, [ssCtrl]);
  AssertEquals('Ctrl+Left: to its start', Int64(0), FRich.CaretIndex);
  p := PointIn(0, 1);
  Click(p);
  Click(p, [ssDouble]);
  CheckSelection('a double click: the whole word, marks and all', 0, 8);
  // Ctrl+Delete from the start: the word holds the field whole - it goes with it
  FRich.SelStart := 0;
  Reset;
  Press(VK_DELETE, [ssCtrl]);
  AssertEquals('the word and its space', 'gh', AllText);
  AssertEquals('nothing told', 0, FRich.Refused);
  FRich.Undo;
  AssertTrue('the field back', IsOpen(2) and IsClose(5));
  // Ctrl+Backspace from the end of the word: the same word
  FRich.SelStart := 8;
  Press(VK_BACK, [ssCtrl]);
  AssertEquals('back over the word', ' gh', AllText);
end;

{ Find: marks are not there - text across a field's edge and inside results is found, the range
  holding the marks it spans; whole word as if the mark were not there. }
procedure TTyRichFieldControlTest.TestFindSeesThroughMarks;
var
  s, n: TTyRichPos;
begin
  Load(LinkDoc);
  s := 0;
  n := 0;
  AssertTrue('across the open mark', FRich.Search('b li', 0, -1, [], s, n));
  AssertEquals('from the b', Int64(1), s);
  AssertEquals('the mark inside the range', Int64(5), n);
  AssertTrue('across the close mark', FRich.Search('nk c', 0, -1, [], s, n));
  AssertEquals('from the n', Int64(6), s);
  AssertEquals('the close mark inside', Int64(5), n);
  AssertTrue('inside the result', FRich.Search('in', 0, -1, [], s, n));
  AssertEquals('inside: its place', Int64(5), s);
  AssertEquals('inside: its length', Int64(2), n);
  AssertTrue('whole word: the link''s text is a word', FRich.Search('link', 0, -1,
    [soWholeWord], s, n));
  AssertEquals('whole word: at the l', Int64(4), s);
  // a whole word next to a mark: ab[cd]ef is one word, cd is none
  Load(Rtf(Head + 'ab{|field{|*|fldinst HYPERLINK "x"}{|fldrslt cd}}ef|par}'));
  AssertFalse('cd is no whole word', FRich.Search('cd', 0, -1, [soWholeWord], s, n));
  AssertTrue('abcdef is', FRich.Search('abcdef', 0, -1, [soWholeWord], s, n));
  AssertEquals('abcdef: both marks inside', Int64(8), n);
  // FindNext selects the match (on resting places)
  Load(LinkDoc);
  FRich.SelStart := 0;
  AssertTrue('FindNext', FRich.FindNext('b li', []));
  CheckSelection('found and selected', 1, 5);
  // a table of contents: an entry across its paragraph end
  Load(TocDoc);
  AssertTrue('across an entry''s end', FRich.Search('3' + LineEnding + 'Chapter 2', 0, -1, [], s, n));
  AssertEquals('from the page number', Int64(13), s);
  // its 11 characters, and the three marks between them (two close, one open)
  AssertEquals('the needle with its marks', Int64(14), n);
end;

{ Replace: a match inside a result or cutting a field is skipped and counted; one that holds a
  whole field is replaced. }
procedure TTyRichFieldControlTest.TestReplaceFollowsTheEngine;
var
  skipped, n: Integer;
begin
  Load(LinkDoc);
  n := FRich.ReplaceAll('in', 'XX', [], skipped);
  AssertEquals('inside a result: not replaced', 0, n);
  AssertEquals('... counted', 1, skipped);
  n := FRich.ReplaceAll('b li', 'XX', [], skipped);
  AssertEquals('cutting a field: not replaced', 0, n);
  AssertEquals('... counted', 1, skipped);
  n := FRich.ReplaceAll('b link c', 'XX', [], skipped);
  AssertEquals('holding the field: replaced', 1, n);
  AssertEquals('none skipped', 0, skipped);
  AssertEquals('the field went with it', Raw('aXXd'), AllText);
  FRich.Undo;
  AssertEquals('undone', 12, Doc.Text.Length);
  // many of them in a paragraph, mixed with plain matches
  Load(Rtf(Head + 'k ab ' + LinkField + ' k ' + LinkField + ' k|par}'));
  n := FRich.ReplaceAll(' link ', '-', [], skipped);
  AssertEquals('both fields replaced', 2, n);
  AssertFalse('no mark left', Pos(OC, AllText) > 0);
end;

{ Formats across a link (SelAttributes): the rest is formatted, the result keeps its look, one
  step, nothing told; wholly inside a result: nothing changes, refused once (raised: an edit
  from code). }
procedure TTyRichFieldControlTest.TestFormatsAcrossALink;
var
  raised: Integer;
begin
  Load(LinkDoc);
  FRich.SelStart := 0;
  FRich.SelLength := Doc.Text.Length;
  Reset;
  FRich.SelAttributes.Bold := True;
  AssertTrue('before the link: bold', fsBold in CharFmt(0).Style);
  AssertTrue('after it: bold', fsBold in CharFmt(10).Style);
  AssertFalse('its result keeps its look', fsBold in CharFmt(5).Style);
  AssertTrue('... underlined still', fsUnderline in CharFmt(5).Style);
  AssertEquals('one step', 1, Doc.UndoDepth);
  AssertEquals('nothing told', 0, FRich.Refused);
  FRich.SelStart := 5;
  FRich.SelLength := 2;
  raised := 0;
  try
    FRich.SelAttributes.Italic := True;
  except
    on E: ETyRichEdit do Inc(raised);
  end;
  AssertEquals('inside: refused once', 1, raised);
  AssertFalse('nothing changed', fsItalic in CharFmt(5).Style);
  AssertEquals('no step more', 1, Doc.UndoDepth);
  // the typing format at the field's edge is the text's outside it
  FRich.SelStart := 9;
  Chars('t');
  AssertFalse('typed after the link: not underlined', fsUnderline in CharFmt(9).Style);
end;

{ Text out: Lines, Text and a plain-text save give no character for a mark; another object
  is U+FFFC there as before. }
procedure TTyRichFieldControlTest.TestPlainTextHasNoMarks;
var
  s: RawByteString;
begin
  Load(LinkDoc);
  AssertEquals('Lines', 'ab link cd', FRich.Lines[0]);
  AssertEquals('Text', 'ab link cd', FRich.Text);
  s := PlainSave;
  AssertFalse('a plain save: no U+FFFC', Pos(OC, s) > 0);
  AssertTrue('... the result''s text', Pos('ab link cd', s) > 0);
  Load(TocDoc);
  AssertEquals('an entry''s line', 'Chapter 1' + #9 + '3', FRich.Lines[0]);
  // a bookmark (kept bytes, nothing to show) stays a U+FFFC there
  Load(Rtf(Head + 'ab{|*|bkmkstart m1}cd|par}'));
  AssertEquals('another object: U+FFFC as before', Hex(Raw('ab') + OC + Raw('cd')), Hex(Raw(FRich.Lines[0])));
end;

{ A copy changes nothing and is never refused: plain text without marks, the RTF flavour a whole
  field's bytes or a part's text. }
procedure TTyRichFieldControlTest.TestACopyIsNeverRefused;
begin
  Load(LinkDoc);
  FRich.SelStart := 1;
  FRich.SelLength := 5;
  Reset;
  FRich.CopyToClipboard;
  AssertEquals('not refused', 0, FRich.Refused);
  AssertEquals('the text, no mark', 'b li', FRich.ClipText);
  AssertFalse('a part: no field in the RTF', Pos(Rtf('|field'), FRich.ClipRtf) > 0);
  AssertTrue('... its text', Pos('li', FRich.ClipRtf) > 0);
  FRich.SelStart := 0;
  FRich.SelLength := 12;
  FRich.CopyToClipboard;
  AssertEquals('all of it', 'ab link cd', FRich.ClipText);
  AssertTrue('a whole field: its bytes', Pos(Rtf(LinkField), FRich.ClipRtf) > 0);
  AssertEquals('SelText', 'ab link cd', FRich.SelText);
end;

initialization
  RegisterTest(TTyRichFieldControlTest);

end.
