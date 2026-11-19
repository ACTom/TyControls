unit test.richedit.drag;

{ Dragging the selection inside TTyRichEdit: a press inside the selection and a move past the
  drag threshold begin a drag; the release moves the selection there, or copies it with Ctrl
  held - one undo step each (TTyRichMove, TTyRichCopy), what a cut (a copy) and a paste of it
  there would give. The drop mark and its repaints, the cursor, the edge scrolling, what ends a
  drag, the capture's order, the refusals, objects and rows; the receiving side fed by an offer
  of another's content; the two commands in a document without a control.

  Headless, on the editor's probe (TEditProbe of test.richedit.edit: the test device, the
  counters, the fake clipboard - which a drag must never touch). No window, no system
  clipboard, no input method. Every bound is a count, never a time (the times are the
  performance suite's). The unit is ASCII. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, fpcunit, testregistry, Controls, Graphics, LCLType, Forms,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.StrConsts,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite, tyControls.RichEdit.TextIO,
  tyControls.RichEdit.Layout,
  tyControls.RichEdit, test.richedit.control, test.richedit.edit;

type
  { The editor's probe with the drag's seams. }
  TDragProbe = class(TEditProbe)
  protected
    function LeftButtonHeld: Boolean; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    { The left button as the system has it when the capture changes (held unless the test
      says it is up); the capture taken away at the start of the button-up's own handling. }
    ButtonUp: Boolean;
    CaptureInsideUp: Boolean;
    function Threshold: Integer;
    procedure MoveWith(X, Y: Integer; AShift: TShiftState);
    procedure ReleaseWith(X, Y: Integer; AShift: TShiftState);
    procedure LoseCapture;
    procedure RightPressAt(X, Y: Integer);
    procedure KeyUpOf(AKey: Word; AShift: TShiftState);
    function Mark(out ARect: TRect): Boolean;
    function Effect: TTyRichDropEffect;
    function Pending: Boolean;
    function OwnDrag: Boolean;
  end;

  { Another's content, as a drop offers it: text, a picture, or both. }
  TTestOffer = class(TTyRichDropOffer)
  public
    Text: string;
    Picture: TBytes;
    TextReads, PictureReads, Takes: Integer;
    function Flavours: TTyRichClipFlavours; override;
    function ReadText: string; override;
    function ReadPicture(AIndex: Integer; out AKind: TTyRichImageKind;
      out ABytes: TBytes): Boolean; override;
    procedure Taken(AEffect: TTyRichDropEffect); override;
  end;

  // the document's load state, as a reader sets it
  TDragLoadState = class(TTyRichDocBuilder)
  public
    class procedure Put(ADoc: TTyRichDocument; AIncomplete: Boolean);
  end;

  TTyRichDragTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TDragProbe;
    function NewProbe: TDragProbe;
    procedure PaintAll(ARich: TDragProbe = nil);
    procedure LoadText(const S: string);
    procedure LoadRtf(ARich: TDragProbe; const S: RawByteString);
    function SaveRtf(ARich: TDragProbe): RawByteString;
    procedure Sel(AFrom, ALen: TTyRichPos);
    { A point a click puts the caret at APos with (just right of its place), and the middle of
      the character at APos. }
    function Pt(APos: TTyRichPos): TPoint;
    function Mid(APos: TTyRichPos): TPoint;
    { A press at AFrom, a move past the threshold, a move to ATo and the release there, the
      keys AShift held from the first move on. }
    procedure Drag(const AFrom, ATo: TPoint; AShift: TShiftState = []);
    { Pressed at AFrom and moved to ATo: the drag under way. }
    procedure StartDrag(const AFrom, ATo: TPoint; AShift: TShiftState = []);
    function AllText: string;
    procedure CheckUntouchedClipboard(const AWhat: string);
    { FRich holds ARtf; the selection [AFrom, AFrom + ALen) pressed at its character APress
      and dropped at APlace (Ctrl: ACopy). Another control, the same document: the
      selection cut (copied) to its clipboard and pasted where the place is then. Both saved:
      the same bytes; one step; undo gives the document back. }
    procedure CheckLikeCutAndPaste(const AWhat: string; const ARtf: RawByteString;
      AFrom, ALen, APress, APlace: TTyRichPos; ACopy: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDragMoveAndCtrlCopyAreSingleUndoSteps;
    procedure TestDropInsideTheSelectionDoesNothing;
    procedure TestAPressAndReleaseWithoutADragIsAClick;
    procedure TestNoDragWhereNoEditCanBeMade;
    procedure TestTheDropMarkShowsThePlaceAndRepaintsOnlyIt;
    procedure TestTheCursorSaysWhatAReleaseWouldDo;
    procedure TestWhatEndsADragChangesNothing;
    procedure TestTheReleaseFinishesInEveryCaptureOrder;
    procedure TestTheTextScrollsNearAndPastAnEdge;
    procedure TestADropIsACutAndAPasteInOneStep;
    procedure TestRefusalsAreToldOnce;
    procedure TestAMovedObjectIsTheVeryOneAndACopySharesItsBytes;
    procedure TestRowsGoAsTablesOfTheirOwn;
    procedure TestADropFromElsewhereGoesInAsAPaste;
    procedure TestTheCommandsWithoutAControl;
    procedure TestTheCommandsKeepTheFileAndCopyNoText;
  end;

implementation

{ ---- helpers ---- }

var
  WidgetSetReady: Boolean = False;

{ The widgetset's window classes, for the one test that makes a window (never shown): the
  console runner never initialises the application. }
procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Application.Initialize;
  WidgetSetReady := True;
end;

function RawBytes(const S: RawByteString): TBytes;
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
end;

function PngOf(AW, AH: Integer): TBytes;
var
  b: TBGRABitmap;
  st: TBytesStream;
begin
  b := TBGRABitmap.Create(AW, AH, BGRA(30, 120, 200, 255));
  st := TBytesStream.Create;
  try
    b.SaveToStreamAs(st, ifPng);
    Result := Copy(st.Bytes, 0, st.Size);
  finally
    st.Free;
    b.Free;
  end;
end;

function FixtureBytes(const AName: string): TBytes;
var
  f: TFileStream;
begin
  Result := nil;
  f := TFileStream.Create(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim +
    'fixtures' + PathDelim + 'rtf' + PathDelim + AName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[0], f.Size);
  finally
    f.Free;
  end;
end;

function Head: RawByteString;
begin
  Result := '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}{\f1 Courier New;}}' +
    '{\colortbl ;\red200\green0\blue0;}' + #13#10;
end;

{ 'before', ARows rows of three cells ('rK a', 'rK b' with a bold b, 'rK c'), 'after'. }
function TableRtf(ARows: Integer): RawByteString;
var
  k: Integer;
begin
  Result := Head + '\pard\f0\fs20 before the table\par' + #13#10;
  for k := 0 to ARows - 1 do
    Result := Result + '\trowd\trgaph108\cellx2400\cellx4800\cellx7200' + #13#10 +
      '\pard\intbl r' + IntToStr(k) + ' a\cell r' + IntToStr(k) + ' \b b\b0\cell r' +
      IntToStr(k) + ' c\cell\row' + #13#10;
  Result := Result + '\pard after the table\par' + #13#10 + '}';
end;

function LoadDocOf(const S: RawByteString): TTyRichDocument;
var
  st: TBytesStream;
begin
  Result := TTyRichDocument.Create;
  st := TBytesStream.Create(RawBytes(S));
  try
    TyRichLoadRtf(Result, st);
  finally
    st.Free;
  end;
end;

function SaveDoc(ADoc: TTyRichDocument): RawByteString;
var
  st: TBytesStream;
begin
  st := TBytesStream.Create;
  try
    TyRichSaveRtf(ADoc, st);
    Result := StrOfBytes(Copy(st.Bytes, 0, st.Size));
  finally
    st.Free;
  end;
end;

function DocText(ADoc: TTyRichDocument): string;
begin
  Result := ADoc.Text.GetText(0, ADoc.Text.Length);
end;

{ Every paragraph: its text, format, runs (objects by address) and, in a table, its cell:
  the table (by address), the row's index, the cell's. }
function Dump(ADoc: TTyRichDocument): string;
var
  i, j: Integer;
  c: TTyRichCell;
  r: TTyRunArray;
begin
  Result := '';
  for i := 0 to ADoc.Text.ParaCount - 1 do
  begin
    Result := Result + '[' + ADoc.Text.GetText(ADoc.Text.ParaStart(i), ADoc.Text.ParaLength(i)) +
      '] P' + IntToStr(ADoc.ParaFormatOf(i)) + ' {';
    r := ADoc.RunsOf(i);
    for j := 0 to High(r) do
    begin
      Result := Result + ' ' + IntToStr(r[j].Start) + ':' + IntToStr(r[j].Format);
      if r[j].Obj <> nil then Result := Result + '@' + IntToHex(PtrUInt(r[j].Obj), 1);
    end;
    Result := Result + '}';
    c := ADoc.CellAt(i);
    if c <> nil then
      Result := Result + Format(' T%s R%d C%d', [IntToHex(PtrUInt(c.Table), 1), c.Row.Index,
        c.Index]);
    Result := Result + LineEnding;
  end;
end;

{ ---- the probe ---- }

function TDragProbe.LeftButtonHeld: Boolean;
begin
  Result := not ButtonUp;
end;

procedure TDragProbe.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if CaptureInsideUp and (Button = mbLeft) then CaptureChanged;
  inherited MouseUp(Button, Shift, X, Y);
end;

function TDragProbe.Threshold: Integer;
begin
  Result := DragThreshold;
end;

procedure TDragProbe.MoveWith(X, Y: Integer; AShift: TShiftState);
begin
  MouseMove(AShift + [ssLeft], X, Y);
end;

procedure TDragProbe.ReleaseWith(X, Y: Integer; AShift: TShiftState);
begin
  MouseUp(mbLeft, AShift, X, Y);
end;

procedure TDragProbe.LoseCapture;
begin
  CaptureChanged;
end;

procedure TDragProbe.RightPressAt(X, Y: Integer);
begin
  MouseDown(mbRight, [ssRight, ssLeft], X, Y);
  MouseUp(mbRight, [ssLeft], X, Y);
end;

procedure TDragProbe.KeyUpOf(AKey: Word; AShift: TShiftState);
begin
  KeyUp(AKey, AShift);
end;

function TDragProbe.Mark(out ARect: TRect): Boolean;
begin
  Result := DropMark(ARect);
end;

function TDragProbe.Effect: TTyRichDropEffect;
begin
  Result := DropEffectNow;
end;

function TDragProbe.Pending: Boolean;
begin
  Result := DragPending;
end;

function TDragProbe.OwnDrag: Boolean;
begin
  Result := DropActive;
end;

function TTestOffer.Flavours: TTyRichClipFlavours;
begin
  Result := [];
  if Text <> '' then Include(Result, rcfText);
  if Length(Picture) > 0 then Include(Result, rcfPicture);
end;

function TTestOffer.ReadText: string;
begin
  Inc(TextReads);
  Result := Text;
end;

function TTestOffer.ReadPicture(AIndex: Integer; out AKind: TTyRichImageKind;
  out ABytes: TBytes): Boolean;
begin
  AKind := rikPng;
  ABytes := nil;
  Result := AIndex = 0;
  if not Result then Exit;
  Inc(PictureReads);
  ABytes := Picture;
end;

procedure TTestOffer.Taken(AEffect: TTyRichDropEffect);
begin
  Inc(Takes);
end;

class procedure TDragLoadState.Put(ADoc: TTyRichDocument; AIncomplete: Boolean);
begin
  SetLoadState(ADoc, False, AIncomplete);
end;

{ ---- fixture ---- }

procedure TTyRichDragTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FRich := NewProbe;
end;

procedure TTyRichDragTest.TearDown;
begin
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
end;

function TTyRichDragTest.NewProbe: TDragProbe;
begin
  Result := TDragProbe.Create(nil);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
  Result.ResetCounts;
end;

procedure TTyRichDragTest.PaintAll(ARich: TDragProbe);
var
  bmp: TBitmap;
begin
  if ARich = nil then ARich := FRich;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(ARich.Width, ARich.Height);
    ARich.PaintPart(bmp.Canvas, Rect(0, 0, ARich.Width, ARich.Height), False);
  finally
    bmp.Free;
  end;
end;

procedure TTyRichDragTest.LoadText(const S: string);
begin
  FRich.Lines.Text := S;
  FRich.Document.ClearUndo;
  FRich.Modified := False;
  FRich.UpdateView;
  PaintAll;
end;

procedure TTyRichDragTest.LoadRtf(ARich: TDragProbe; const S: RawByteString);
var
  st: TBytesStream;
begin
  st := TBytesStream.Create(RawBytes(S));
  try
    ARich.LoadFromStream(st);
  finally
    st.Free;
  end;
  ARich.FinishLoading;
  ARich.UpdateView;
  PaintAll(ARich);
end;

function TTyRichDragTest.SaveRtf(ARich: TDragProbe): RawByteString;
var
  st: TBytesStream;
begin
  st := TBytesStream.Create;
  try
    ARich.SaveToStream(st, rfRtf);
    Result := StrOfBytes(Copy(st.Bytes, 0, st.Size));
  finally
    st.Free;
  end;
end;

procedure TTyRichDragTest.Sel(AFrom, ALen: TTyRichPos);
begin
  FRich.SelStart := AFrom;
  FRich.SelLength := ALen;
end;

function TTyRichDragTest.Pt(APos: TTyRichPos): TPoint;
var
  r: TRect;
begin
  r := FRich.PositionRect(APos);
  Result := Point(r.Left + 1, (r.Top + r.Bottom) div 2);
end;

function TTyRichDragTest.Mid(APos: TTyRichPos): TPoint;
var
  r, r2: TRect;
begin
  r := FRich.PositionRect(APos);
  r2 := FRich.PositionRect(APos + 1);
  if (r2.Top = r.Top) and (r2.Left > r.Left + 2) then Result.X := (r.Left + r2.Left) div 2
  else Result.X := r.Left + 2;
  Result.Y := (r.Top + r.Bottom) div 2;
end;

procedure TTyRichDragTest.StartDrag(const AFrom, ATo: TPoint; AShift: TShiftState);
begin
  FRich.PressAt(AFrom.X, AFrom.Y);
  AssertTrue('the press waits for a drag', FRich.Pending);
  // past the threshold: the drag begins
  FRich.MoveWith(AFrom.X, AFrom.Y + FRich.Threshold + 1, AShift);
  AssertTrue('the drag began', FRich.OwnDrag);
  FRich.MoveWith(ATo.X, ATo.Y, AShift);
end;

procedure TTyRichDragTest.Drag(const AFrom, ATo: TPoint; AShift: TShiftState);
begin
  StartDrag(AFrom, ATo, AShift);
  FRich.ReleaseWith(ATo.X, ATo.Y, AShift);
  AssertFalse('the drag ended', FRich.OwnDrag);
end;

function TTyRichDragTest.AllText: string;
begin
  Result := DocText(FRich.Document);
end;

procedure TTyRichDragTest.CheckUntouchedClipboard(const AWhat: string);
begin
  AssertEquals(AWhat + ': nothing written to the clipboard', 0, FRich.ClipWrites);
  AssertEquals(AWhat + ': its flavours never asked', 0, FRich.FlavourAsks);
  AssertEquals(AWhat + ': its formats never listed', 0, FRich.FormatAsks);
  AssertEquals(AWhat + ': no RTF read', 0, FRich.RtfReads);
  AssertEquals(AWhat + ': no text read', 0, FRich.TextReads);
  AssertEquals(AWhat + ': no picture read', 0, FRich.PictureReads);
end;

procedure TTyRichDragTest.CheckLikeCutAndPaste(const AWhat: string; const ARtf: RawByteString;
  AFrom, ALen, APress, APlace: TTyRichPos; ACopy: Boolean);
var
  other: TDragProbe;
  before, a, b: RawByteString;
  len0, at: TTyRichPos;
  p: TPoint;
  sh: TShiftState;
begin
  LoadRtf(FRich, ARtf);
  before := SaveRtf(FRich);
  Sel(AFrom, ALen);
  p := Pt(APlace);
  AssertEquals(AWhat + ': the place under the pointer', APlace, FRich.PositionAtPoint(p.X, p.Y));
  if ACopy then sh := [ssCtrl] else sh := [];
  Drag(Mid(APress), p, sh);
  AssertEquals(AWhat + ': one step', 1, FRich.Document.UndoDepth);
  a := SaveRtf(FRich);
  other := NewProbe;
  try
    LoadRtf(other, ARtf);
    other.SelStart := AFrom;
    other.SelLength := ALen;
    len0 := other.Document.Text.Length;
    if ACopy then other.CopyToClipboard else other.CutToClipboard;
    // the place in the text the cut left
    at := APlace;
    if at > AFrom then Dec(at, len0 - other.Document.Text.Length);
    other.SelStart := at;
    other.SelLength := 0;
    other.PasteFromClipboard;
    b := SaveRtf(other);
  finally
    other.Free;
  end;
  AssertEquals(AWhat + ': what a cut and a paste give', b, a);
  FRich.Undo;
  AssertEquals(AWhat + ': undo gives the document back', before, SaveRtf(FRich));
  FRich.Redo;
  AssertEquals(AWhat + ': redo the drop again', a, SaveRtf(FRich));
end;

{ ---- the tests ---- }

{ A drag of 'two' to the text's end moves it (one step, named Move, the moved word selected at
  its new place); undo gives the text and the selection back, redo the move. A Ctrl drag to the
  start copies it (one step, named Copy). The clipboard is never touched. }
procedure TTyRichDragTest.TestDragMoveAndCtrlCopyAreSingleUndoSteps;
begin
  LoadText('one two three four');
  Sel(4, 3);
  Drag(Mid(5), Pt(18));
  AssertEquals('moved to the end', 'one  three fourtwo', AllText);
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
  AssertEquals('named Move', rsRichUndoMove, FRich.Document.UndoDescription);
  AssertTrue('modified', FRich.Modified);
  AssertEquals('the moved word selected: start', Int64(15), FRich.SelStart);
  AssertEquals('the moved word selected: length', Int64(3), FRich.SelLength);
  FRich.Undo;
  AssertEquals('undo: the text', 'one two three four', AllText);
  AssertEquals('undo: the selection, start', Int64(4), FRich.SelStart);
  AssertEquals('undo: the selection, length', Int64(3), FRich.SelLength);
  AssertFalse('undo: not modified', FRich.Modified);
  FRich.Redo;
  AssertEquals('redo: moved again', 'one  three fourtwo', AllText);
  AssertEquals('redo: the moved word selected', Int64(15), FRich.SelStart);
  AssertEquals('redo: its length', Int64(3), FRich.SelLength);
  FRich.Undo;
  // with Ctrl: a copy, at the start
  Sel(4, 3);
  Drag(Mid(5), Pt(0), [ssCtrl]);
  AssertEquals('copied to the start', 'twoone two three four', AllText);
  AssertEquals('one step more', 1, FRich.Document.UndoDepth);
  AssertEquals('named Copy', rsRichUndoCopy, FRich.Document.UndoDescription);
  AssertEquals('the copy selected', Int64(0), FRich.SelStart);
  AssertEquals('the copy''s length', Int64(3), FRich.SelLength);
  FRich.Undo;
  AssertEquals('undo the copy', 'one two three four', AllText);
  AssertEquals('undo the copy: the selection', Int64(4), FRich.SelStart);
  // Ctrl going down at the release only: a copy too
  Sel(4, 3);
  StartDrag(Mid(5), Pt(18));
  FRich.ReleaseWith(Pt(18).X, Pt(18).Y, [ssCtrl]);
  AssertEquals('Ctrl at the release: a copy', 'one two three fourtwo', AllText);
  AssertEquals('a copy at the release: named Copy', rsRichUndoCopy, FRich.Document.UndoDescription);
  CheckUntouchedClipboard('move and copy');
end;

{ A release inside the selection, or at its start or its end, moves nothing: no step, not
  modified, the selection as it was, nothing told. A copy there: its ends are places (the copy
  goes beside it), strictly inside is nothing. }
procedure TTyRichDragTest.TestDropInsideTheSelectionDoesNothing;
const
  Places: array[0..3] of Integer = (6, 9, 4, 13);
var
  i: Integer;
begin
  LoadText('one two three four');
  for i := 0 to High(Places) do
  begin
    Sel(4, 9);
    Drag(Mid(5), Pt(Places[i]));
    AssertEquals(Format('a move to %d: the text', [Places[i]]), 'one two three four', AllText);
    AssertEquals(Format('a move to %d: no step', [Places[i]]), 0, FRich.Document.UndoDepth);
    AssertFalse(Format('a move to %d: not modified', [Places[i]]), FRich.Modified);
    AssertEquals(Format('a move to %d: the selection', [Places[i]]), Int64(4), FRich.SelStart);
    AssertEquals(Format('a move to %d: its length', [Places[i]]), Int64(9), FRich.SelLength);
    AssertEquals(Format('a move to %d: nothing told', [Places[i]]), 0, FRich.Refused);
  end;
  // a copy strictly inside: nothing
  Sel(4, 9);
  Drag(Mid(5), Pt(9), [ssCtrl]);
  AssertEquals('a copy inside: the text', 'one two three four', AllText);
  AssertEquals('a copy inside: no step', 0, FRich.Document.UndoDepth);
  AssertEquals('a copy inside: the selection', Int64(9), FRich.SelLength);
  // at its start, and at its end: the content beside itself
  Sel(4, 9);
  Drag(Mid(5), Pt(4), [ssCtrl]);
  AssertEquals('a copy at its start', 'one two threetwo three four', AllText);
  AssertEquals('a copy at its start: one step', 1, FRich.Document.UndoDepth);
  FRich.Undo;
  Sel(4, 9);
  Drag(Mid(5), Pt(13), [ssCtrl]);
  AssertEquals('a copy at its end', 'one two threetwo three four', AllText);
  AssertEquals('the copy at its end selected', Int64(13), FRich.SelStart);
  FRich.Undo;
  AssertEquals('nothing told', 0, FRich.Refused);
  CheckUntouchedClipboard('drops inside');
end;

{ A press inside the selection collapses nothing at once; released without a drag (a move no
  farther than the threshold) it is the click it was. Shift extends, a double click selects the
  word, a press outside the selection is a click and a drag-select, a press on a selected
  picture and a release keep it selected. }
procedure TTyRichDragTest.TestAPressAndReleaseWithoutADragIsAClick;
var
  p: TPoint;
  q: TTyRichPos;
  pic: TTyRichPicture;
  r: TRect;
begin
  LoadText('one two three four');
  Sel(4, 9);
  p := Mid(6);
  q := FRich.PositionAtPoint(p.X, p.Y);
  FRich.PressAt(p.X, p.Y);
  AssertTrue('pending', FRich.Pending);
  AssertEquals('pressed: the selection stays', Int64(9), FRich.SelLength);
  FRich.MoveWith(p.X + FRich.Threshold, p.Y - FRich.Threshold, []);
  AssertTrue('a move as far as the threshold: still pending', FRich.Pending);
  AssertFalse('no drag yet', FRich.OwnDrag);
  AssertEquals('moved a little: the selection stays', Int64(9), FRich.SelLength);
  FRich.ReleaseAt(p.X + FRich.Threshold, p.Y);
  AssertFalse('released: no longer pending', FRich.Pending);
  AssertEquals('released: the caret where the press was', q, FRich.SelStart);
  AssertEquals('released: nothing selected', Int64(0), FRich.SelLength);
  AssertEquals('no step', 0, FRich.Document.UndoDepth);
  // Shift extends from the anchor, never drags
  FRich.SelStart := 4;
  FRich.SelLength := 9;
  FRich.PressAt(p.X, p.Y, [ssShift]);
  AssertFalse('Shift: no drag', FRich.Pending);
  AssertEquals('Shift: from the anchor', Int64(4), FRich.SelStart);
  AssertEquals('Shift: to the press', q - 4, FRich.SelLength);
  FRich.ReleaseAt(p.X, p.Y);
  // a double press: the word
  Sel(4, 9);
  FRich.PressAt(p.X, p.Y);
  FRich.ReleaseAt(p.X, p.Y);
  FRich.PressAt(p.X, p.Y, [ssDouble]);
  AssertFalse('a double press: no drag', FRich.Pending);
  FRich.ReleaseAt(p.X, p.Y);
  AssertEquals('a double press: the word', Int64(4), FRich.SelStart);
  AssertEquals('a double press: its length', Int64(3), FRich.SelLength);
  // a press on the selection's line before it: a click
  Sel(4, 3);
  FRich.PressAt(Mid(1).X, Mid(1).Y);
  AssertFalse('before it on its line: no drag', FRich.Pending);
  AssertEquals('before it on its line: collapsed', Int64(0), FRich.SelLength);
  FRich.ReleaseAt(Mid(1).X, Mid(1).Y);
  // a press outside the selection: a click, then a drag-select
  Sel(4, 3);
  FRich.PressAt(Mid(10).X, Mid(10).Y);
  AssertFalse('outside: no drag of the selection', FRich.Pending);
  AssertEquals('outside: collapsed at once', Int64(0), FRich.SelLength);
  FRich.MoveAt(Mid(15).X, Mid(15).Y);
  AssertTrue('outside: a drag-select', FRich.SelLength > 0);
  FRich.ReleaseAt(Mid(15).X, Mid(15).Y);
  // a selected picture, pressed on its body and let go: still selected
  pic := TTyRichPicture.Create(rpfPng, PngOf(40, 30), 600, 450);
  AssertTrue('a picture', FRich.Document.Execute(TTyRichInsertObject.Create(2, pic)));
  FRich.UpdateView;
  PaintAll;
  Sel(2, 1);
  r := FRich.PositionRect(2);
  p := Point(r.Left + 12, (r.Top + r.Bottom) div 2);
  FRich.PressAt(p.X, p.Y);
  AssertTrue('the picture''s body: pending', FRich.Pending);
  FRich.ReleaseAt(p.X, p.Y);
  AssertEquals('the picture still selected', Int64(2), FRich.SelStart);
  AssertEquals('the picture: its character', Int64(1), FRich.SelLength);
end;

{ Read-only, DragDropEditing False, DragMode dmAutomatic, a document that takes no edit: a
  press inside the selection is a click at once, as it always was; no drop is taken. A plain
  text document drags its text. }
procedure TTyRichDragTest.TestNoDragWhereNoEditCanBeMade;
var
  p: TPoint;
  i: Integer;
  offer: TTestOffer;
begin
  for i := 0 to 3 do
  begin
    LoadText('one two three four');
    case i of
      0: FRich.ReadOnly := True;
      1: FRich.DragDropEditing := False;
      2: FRich.DragMode := dmAutomatic;
      3: TDragLoadState.Put(FRich.Document, True);
    end;
    Sel(4, 9);
    p := Mid(6);
    FRich.PressAt(p.X, p.Y);
    AssertFalse(Format('case %d: no drag', [i]), FRich.Pending);
    AssertEquals(Format('case %d: a click at once', [i]), Int64(0), FRich.SelLength);
    FRich.MoveWith(Mid(15).X, Mid(15).Y, []);
    AssertFalse(Format('case %d: no drag after a move', [i]), FRich.OwnDrag);
    FRich.ReleaseAt(Mid(15).X, Mid(15).Y);
    AssertEquals(Format('case %d: the text', [i]), 'one two three four', AllText);
    AssertEquals(Format('case %d: no step', [i]), 0, FRich.Document.UndoDepth);
    offer := TTestOffer.Create;
    try
      offer.Text := 'x';
      if i in [0, 1] then
      begin
        AssertTrue(Format('case %d: no drop taken', [i]),
          FRich.DropEnter(offer, Pt(2).X, Pt(2).Y, []) = rdeNone);
        AssertFalse(Format('case %d: no session', [i]), FRich.DropActive);
      end;
    finally
      offer.Free;
    end;
    FRich.ReadOnly := False;
    FRich.DragDropEditing := True;
    FRich.DragMode := dmManual;
    TDragLoadState.Put(FRich.Document, False);
  end;
  // a plain text document: its text is dragged
  LoadText('one two three four');
  FRich.PlainText := True;
  Sel(4, 3);
  Drag(Mid(5), Pt(18));
  AssertEquals('plain text: moved', 'one  three fourtwo', AllText);
end;

{ The mark: at the place under the pointer, twice the overlay's line wide, the line's height;
  dotted in the object frame's colour. Moving it repaints its old place and its new one only
  (the selection's lines are not painted again); no mark inside the selection. It follows a
  zoom and a scroll; Esc takes it away. }
procedure TTyRichDragTest.TestTheDropMarkShowsThePlaceAndRepaintsOnlyIt;
var
  m, m2, pr: TRect;
  i, n: Integer;
  st: TTyRichPaintStyle;
  on1, off1, off0: TBGRAPixel;
  q: TTyRichPos;
  s: string;
begin
  s := 'one two three four'#13#10'five six seven'#13#10'eight nine';
  for i := 1 to 40 do s := s + #13#10'more ' + IntToStr(i);
  LoadText(s);
  Sel(4, 3);
  StartDrag(Mid(5), Pt(10));
  PaintAll;
  AssertTrue('a mark', FRich.Mark(m));
  pr := FRich.PositionRect(10);
  AssertTrue('on the place', (m.Left <= pr.Left) and (m.Right > pr.Left));
  AssertEquals('two pixels wide', 2, m.Right - m.Left);
  AssertEquals('the line''s top', pr.Top, m.Top);
  AssertEquals('the line''s bottom', pr.Bottom, m.Bottom);
  // drawn: dotted, the object frame's colour
  st := FRich.Style;
  on1 := FRich.Surf.GetPixel(m.Left, m.Top);
  off1 := FRich.Surf.GetPixel(m.Left, m.Top + 2);
  AssertTrue('a dot in the frame''s colour', (on1.red = st.ObjectFrame.red) and
    (on1.green = st.ObjectFrame.green) and (on1.blue = st.ObjectFrame.blue));
  // a gap between two dots: what is there without the mark
  FRich.ResetCounts;
  FRich.MoveWith(Pt(20).X, Pt(20).Y, []);
  AssertTrue('the mark moved', FRich.Mark(m2));
  n := Length(FRich.Invalidated);
  AssertEquals('two places painted again: the old and the new', 2, n);
  AssertTrue('the old place', EqualRect(FRich.Invalidated[0], m) or EqualRect(FRich.Invalidated[1], m));
  AssertTrue('the new place', EqualRect(FRich.Invalidated[0], m2) or EqualRect(FRich.Invalidated[1], m2));
  PaintAll;
  off0 := FRich.Surf.GetPixel(m.Left, m.Top + 2);
  AssertTrue('the gap is what is there without it', (off0.red = off1.red) and
    (off0.green = off1.green) and (off0.blue = off1.blue));
  on1 := FRich.Surf.GetPixel(m.Left, m.Top);
  AssertFalse('the old dot gone', (on1.red = st.ObjectFrame.red) and
    (on1.green = st.ObjectFrame.green) and (on1.blue = st.ObjectFrame.blue));
  // the same place again: nothing painted
  FRich.ResetCounts;
  FRich.MoveWith(Pt(20).X, Pt(20).Y, []);
  AssertEquals('the same place: nothing painted again', 0, Length(FRich.Invalidated));
  // inside the selection: no mark, its place painted again, nothing else
  FRich.ResetCounts;
  FRich.MoveWith(Mid(5).X, Mid(5).Y, []);
  AssertFalse('inside the selection: no mark', FRich.Mark(m));
  AssertEquals('only the old mark painted again', 1, Length(FRich.Invalidated));
  AssertTrue('the old mark', EqualRect(FRich.Invalidated[0], m2));
  // a zoom: the mark stays on its place, at the new size
  FRich.MoveWith(Pt(20).X, Pt(20).Y, []);
  q := 20;
  FRich.Zoom := 200;
  PaintAll;
  AssertTrue('the drag goes on through a zoom', FRich.OwnDrag);
  AssertTrue('a mark at 200 %', FRich.Mark(m));
  pr := FRich.PositionRect(q);
  AssertTrue('at its place at 200 %', (m.Left <= pr.Left) and (m.Right > pr.Left) and
    (m.Top = pr.Top) and (m.Bottom = pr.Bottom));
  FRich.Zoom := 100;
  PaintAll;
  // a scroll (the wheel): the mark goes with its text
  AssertTrue('a mark before the scroll', FRich.Mark(m));
  FRich.ScrollY := 5;
  PaintAll;
  AssertTrue('the drag goes on through a scroll', FRich.OwnDrag);
  AssertTrue('a mark after the scroll', FRich.Mark(m2));
  pr := FRich.PositionRect(q);
  AssertEquals('the mark with its text after the scroll', m.Top - 5, m2.Top);
  AssertTrue('at its place after the scroll', (m2.Left <= pr.Left) and (m2.Right > pr.Left) and
    (m2.Top = pr.Top));
  // Esc: no mark, nothing changed
  FRich.Press(VK_ESCAPE, [ssLeft]);
  AssertFalse('Esc: no drag', FRich.OwnDrag);
  AssertFalse('Esc: no mark', FRich.Mark(m));
  AssertEquals('nothing changed', 0, FRich.Document.UndoDepth);
end;

{ The cursor: crDrag where a release moves, crMultiDrag where it copies (Ctrl going down and up
  during the drag change it without a move of the pointer), crNoDrop inside the selection and
  for a selection that cannot be moved; back to the I-beam at the end. }
procedure TTyRichDragTest.TestTheCursorSaysWhatAReleaseWouldDo;
var
  p: TPoint;
  last: TCursor;
begin
  LoadText('one two three four');
  Sel(4, 3);
  p := Pt(14);
  StartDrag(Mid(5), p);
  AssertEquals('a move', Ord(crDrag), Ord(FRich.CursorFor(p.X, p.Y)));
  AssertTrue('a move: the verdict', FRich.Effect = rdeMove);
  AssertEquals('a move: the cursor shown', Ord(crDrag), Ord(FRich.TempCursors[High(FRich.TempCursors)]));
  FRich.Press(VK_CONTROL, [ssCtrl, ssLeft]);
  AssertTrue('Ctrl down: a copy', FRich.Effect = rdeCopy);
  AssertEquals('Ctrl down: the copy cursor without a move', Ord(crMultiDrag),
    Ord(FRich.TempCursors[High(FRich.TempCursors)]));
  AssertTrue('Ctrl down: the drag goes on', FRich.OwnDrag);
  FRich.KeyUpOf(VK_CONTROL, [ssLeft]);
  AssertTrue('Ctrl up: a move again', FRich.Effect = rdeMove);
  AssertEquals('Ctrl up: the move cursor', Ord(crDrag), Ord(FRich.TempCursors[High(FRich.TempCursors)]));
  // inside the selection: not here; at its edge: not here for a move, a copy with Ctrl
  FRich.MoveWith(Mid(5).X, Mid(5).Y, []);
  AssertEquals('inside: not here', Ord(crNoDrop), Ord(FRich.CursorFor(Mid(5).X, Mid(5).Y)));
  FRich.MoveWith(Pt(7).X, Pt(7).Y, []);
  AssertTrue('at its end, a move: nothing', FRich.Effect = rdeNone);
  FRich.MoveWith(Pt(7).X, Pt(7).Y, [ssCtrl]);
  AssertTrue('at its end, a copy: a place', FRich.Effect = rdeCopy);
  FRich.MoveWith(Mid(5).X, Mid(5).Y, [ssCtrl]);
  AssertTrue('inside, a copy: nothing', FRich.Effect = rdeNone);
  FRich.ReleaseWith(Mid(5).X, Mid(5).Y, [ssCtrl]);
  last := FRich.TempCursors[High(FRich.TempCursors)];
  AssertEquals('after the drag: the I-beam', Ord(crIBeam), Ord(last));
  AssertEquals('nothing done', 0, FRich.Document.UndoDepth);
  // a selection across two cells cannot be moved: not here, but a copy
  LoadRtf(FRich, TableRtf(2));
  Sel(FRich.Document.Text.ParaStart(1) + 1, 6);
  StartDrag(Mid(FRich.Document.Text.ParaStart(1) + 2),
    Pt(FRich.Document.Text.ParaStart(7) + 3));
  AssertTrue('across cells: no move', FRich.Effect = rdeNone);
  FRich.MoveWith(Pt(FRich.Document.Text.ParaStart(7) + 3).X,
    Pt(FRich.Document.Text.ParaStart(7) + 3).Y, [ssCtrl]);
  AssertTrue('across cells: a copy', FRich.Effect = rdeCopy);
  FRich.Press(VK_ESCAPE, [ssLeft]);
end;

{ Esc, a right press (its menu not shown), the capture taken with the button down, a key that
  is not a modifier (it does what it does), the selection or the content set by code, a change
  of the document, DragDropEditing off, ReadOnly, disabled: the drag ends, nothing changes,
  the release after it does nothing. Shift and Alt leave it going. }
procedure TTyRichDragTest.TestWhatEndsADragChangesNothing;
var
  i, menus: Integer;
  p: TPoint;
  m: TRect;
  form: TForm;
begin
  for i := 0 to 10 do
  begin
    LoadText('one two three four');
    Sel(4, 3);
    p := Pt(14);
    StartDrag(Mid(5), p);
    case i of
      0: AssertEquals('Esc is taken', 0, FRich.KeyResult(VK_ESCAPE, [ssLeft]));
      1:
        begin
          menus := FRich.MenuShows;
          FRich.RightPressAt(p.X, p.Y);
          AssertTrue('the right press: its menu is not shown', FRich.PopupAt(p.X, p.Y));
          AssertEquals('the right press: no menu', menus, FRich.MenuShows);
        end;
      2: FRich.LoseCapture;
      3:
        begin
          // a key that moves nothing ends it too; then End does what it does
          FRich.Press(VK_F5, [ssLeft]);
          AssertFalse('F5: the drag ended', FRich.OwnDrag);
          AssertEquals('F5: the selection as it was', Int64(3), FRich.SelLength);
          FRich.Press(VK_END, [ssLeft]);
        end;
      4: FRich.SelStart := 1;
      5: FRich.Lines.Text := 'new text';
      6: FRich.Document.Execute(TTyRichInsertText.Create(0, 'x'));
      7: FRich.DragDropEditing := False;
      8: FRich.ReadOnly := True;
      9: FRich.Enabled := False;
      10:
        begin
          // Shift and Alt are modifiers: the drag goes on, then ends by Esc
          FRich.Press(VK_SHIFT, [ssShift, ssLeft]);
          FRich.Press(VK_MENU, [ssAlt, ssLeft]);
          AssertTrue('Shift and Alt: the drag goes on', FRich.OwnDrag);
          FRich.Press(VK_ESCAPE, [ssLeft]);
        end;
    end;
    AssertFalse(Format('case %d: the drag ended', [i]), FRich.OwnDrag);
    AssertFalse(Format('case %d: no mark', [i]), FRich.Mark(m));
    FRich.ReleaseAt(p.X, p.Y);
    case i of
      5: AssertEquals('a new content', 'new text', AllText);
      6: AssertEquals('the change of code', 'xone two three four', AllText);
    else
      AssertEquals(Format('case %d: the text', [i]), 'one two three four', AllText);
    end;
    AssertEquals(Format('case %d: no step of the drag', [i]), Ord(i = 6), FRich.Document.UndoDepth);
    case i of
      0, 1, 2, 7, 8, 9, 10:
        begin
          AssertEquals(Format('case %d: the selection as it was', [i]), Int64(4), FRich.SelStart);
          AssertEquals(Format('case %d: its length', [i]), Int64(3), FRich.SelLength);
        end;
      3: AssertEquals('End did what it does', Int64(18), FRich.SelStart);
      4: AssertEquals('the selection set by code', Int64(1), FRich.SelStart);
    end;
    FRich.ReadOnly := False;
    FRich.Enabled := True;
    FRich.DragDropEditing := True;
  end;
  // the window going (a form never shown gives the control one)
  NeedWidgetSet;
  form := TForm.CreateNew(nil);
  try
    FRich.Parent := form;
    form.HandleNeeded;
    FRich.HandleNeeded;
    AssertTrue('a window', FRich.HandleAllocated);
    AssertFalse('the form is not shown', form.Visible);
    LoadText('one two three four');
    Sel(4, 3);
    p := Pt(14);
    StartDrag(Mid(5), p);
    FRich.DropHandle;
    AssertFalse('the window gone: the drag ended', FRich.OwnDrag);
    FRich.ReleaseAt(p.X, p.Y);
    AssertEquals('the window gone: the text', 'one two three four', AllText);
    AssertEquals('the window gone: no step', 0, FRich.Document.UndoDepth);
  finally
    FRich.Parent := nil;
    form.Free;
  end;
  CheckUntouchedClipboard('ended drags');
end;

{ The release is done once whatever the order of the capture's going: before the button-up,
  inside it, after it; a capture taken with the button down does nothing. The keys last known
  (Ctrl pressed during the drag) decide a release the capture's going did. A press without a
  drag let go by a capture's going is its click. }
procedure TTyRichDragTest.TestTheReleaseFinishesInEveryCaptureOrder;
var
  order: Integer;
  p: TPoint;
begin
  for order := 0 to 2 do
  begin
    LoadText('one two three four');
    Sel(4, 3);
    p := Pt(18);
    StartDrag(Mid(5), p);
    FRich.ButtonUp := True;
    case order of
      0:
        begin
          FRich.LoseCapture;
          FRich.ReleaseAt(p.X, p.Y);
        end;
      1:
        begin
          FRich.CaptureInsideUp := True;
          FRich.ReleaseAt(p.X, p.Y);
        end;
    else
      FRich.ReleaseAt(p.X, p.Y);
      FRich.LoseCapture;
    end;
    FRich.ButtonUp := False;
    FRich.CaptureInsideUp := False;
    AssertEquals(Format('order %d: moved once', [order]), 'one  three fourtwo', AllText);
    AssertEquals(Format('order %d: one step', [order]), 1, FRich.Document.UndoDepth);
  end;
  // Ctrl pressed during the drag, the capture going first: a copy
  LoadText('one two three four');
  Sel(4, 3);
  p := Pt(18);
  StartDrag(Mid(5), p);
  FRich.Press(VK_CONTROL, [ssCtrl, ssLeft]);
  FRich.ButtonUp := True;
  FRich.LoseCapture;
  FRich.ReleaseAt(p.X, p.Y);
  FRich.ButtonUp := False;
  AssertEquals('Ctrl known: a copy', 'one two three fourtwo', AllText);
  // the capture taken with the button down: nothing
  LoadText('one two three four');
  Sel(4, 3);
  StartDrag(Mid(5), p);
  FRich.LoseCapture;
  FRich.ReleaseAt(p.X, p.Y);
  AssertEquals('taken away: nothing', 'one two three four', AllText);
  AssertEquals('taken away: no step', 0, FRich.Document.UndoDepth);
  // a press without a drag, let go by the capture's going: its click
  Sel(4, 9);
  FRich.PressAt(Mid(6).X, Mid(6).Y);
  FRich.ButtonUp := True;
  FRich.LoseCapture;
  FRich.ButtonUp := False;
  AssertFalse('the click: no longer pending', FRich.Pending);
  AssertEquals('the click: nothing selected', Int64(0), FRich.SelLength);
  FRich.ReleaseAt(Mid(6).X, Mid(6).Y);
  // and taken with the button down: the selection stays
  Sel(4, 9);
  FRich.PressAt(Mid(6).X, Mid(6).Y);
  FRich.LoseCapture;
  AssertFalse('taken: no longer pending', FRich.Pending);
  FRich.ReleaseAt(Mid(6).X, Mid(6).Y);
  AssertEquals('taken: the selection stays', Int64(9), FRich.SelLength);
end;

{ Past the text's bottom edge each tick scrolls as a drag-select's does (a line, and one more
  for every line's height further out), near it (inside) a line a tick, in the middle not at
  all; the place follows the text that came; the release drops there. Up past the top too. }
procedure TTyRichDragTest.TestTheTextScrollsNearAndPastAnEdge;
var
  s: string;
  i: Integer;
  area: TRect;
  y0, y1, dSel, dDrop: Int64;
  other: TDragProbe;
  q: TTyRichPos;
  m, pr: TRect;
begin
  s := '';
  for i := 1 to 80 do s := s + 'Line ' + IntToStr(i) + #13#10;
  LoadText(s);
  area := FRich.Area;
  Sel(0, 4);
  StartDrag(Mid(1), Point(Mid(1).X, (area.Top + area.Bottom) div 2));
  y0 := FRich.ScrollY;
  FRich.DragTick;
  AssertEquals('in the middle: no scroll', y0, FRich.ScrollY);
  // near the bottom edge, inside: a line a tick
  FRich.MoveWith(Mid(1).X, area.Bottom - 2, []);
  FRich.DragTick;
  y1 := FRich.ScrollY;
  AssertTrue('near the edge: scrolled', y1 > y0);
  // past it, as far as a drag-select there: the same scroll
  FRich.MoveWith(Mid(1).X, area.Bottom + 40, []);
  y0 := FRich.ScrollY;
  FRich.DragTick;
  dDrop := FRich.ScrollY - y0;
  other := NewProbe;
  try
    other.Lines.Text := s;
    other.UpdateView;
    PaintAll(other);
    other.PressAt(5, area.Top + 5);
    other.MoveAt(5, area.Bottom + 40);
    y0 := other.ScrollY;
    other.DragTick;
    dSel := other.ScrollY - y0;
    other.ReleaseAt(5, area.Bottom + 40);
  finally
    other.Free;
  end;
  AssertTrue('past the edge: scrolled', dDrop > 0);
  AssertEquals('past the edge: as a drag-select', dSel, dDrop);
  for i := 1 to 5 do FRich.DragTick;
  PaintAll;
  // the place: the last line shown, under the pointer held to the edge
  q := FRich.PositionAtPoint(Mid(1).X, area.Bottom - 1);
  AssertTrue('the mark at the place that came', FRich.Mark(m));
  AssertTrue('the place is far down', q > 200);
  pr := FRich.PositionRect(q);
  AssertTrue('the mark on that place', (m.Left <= pr.Left) and (m.Right > pr.Left) and
    (m.Top = pr.Top));
  FRich.ReleaseWith(Mid(1).X, area.Bottom + 40, []);
  AssertEquals('dropped there: one step', 1, FRich.Document.UndoDepth);
  AssertEquals('the moved word there', 'Line', FRich.SelText);
  AssertTrue('moved far down', FRich.SelStart > 200);
  // up past the top
  FRich.Undo;
  FRich.ScrollY := FRich.Document.Text.TotalHeight;
  PaintAll;
  Sel(FRich.Document.Text.ParaStart(78), 4);
  StartDrag(Mid(FRich.Document.Text.ParaStart(78) + 1), Point(Mid(1).X, area.Top - 30));
  y0 := FRich.ScrollY;
  FRich.DragTick;
  AssertTrue('past the top: scrolled up', FRich.ScrollY < y0);
  FRich.Press(VK_ESCAPE, [ssLeft]);
end;

{ What a drop gives is what a cut (a copy) of the selection and a paste at the place give, in
  one step: a selection that ends with a paragraph end dropped in a paragraph's middle, a drop
  at the text's end and below the last line, a whole table with text around it, whole rows
  into a cell of their own table, a cell's text into another cell, a list item, a
  right-to-left paragraph, rows copied out of a selection across cells. }
procedure TTyRichDragTest.TestADropIsACutAndAPasteInOneStep;
var
  doc, tbl, lst, rtl: RawByteString;
  t: TTyRichText;
  p: TPoint;
  e: TTyRichPos;
begin
  doc := Head + '\pard\f0\fs20 first \b line\b0  of text\par' + #13#10 +
    '\pard\qc second \cf1 line\cf0\par' + #13#10 + '\pard\li720 third line here\par' + #13#10 + '}';
  // first 0..17 (sep 18), second 19..29 (sep 30), third 31..45
  CheckLikeCutAndPaste('a paragraph with its end into a paragraph''s middle', doc, 19, 12, 20, 36, False);
  CheckLikeCutAndPaste('the same, copied', doc, 19, 12, 20, 36, True);
  CheckLikeCutAndPaste('words to the text''s end', doc, 6, 4, 7, 46, False);
  CheckLikeCutAndPaste('words of two paragraphs to the start', doc, 12, 12, 13, 0, False);
  // below the last line: the place a click there gives (the text's end)
  LoadRtf(FRich, doc);
  t := FRich.Document.Text;
  e := t.Length;
  Sel(6, 4);
  // (right of the last line's end: a click there puts the caret at the text's end)
  p := Point(FRich.Area.Right - 5, FRich.PositionRect(e).Bottom + 30);
  AssertEquals('below the last line: the text''s end', e, FRich.PositionAtPoint(p.X, p.Y));
  Drag(Mid(7), p);
  AssertEquals('below the last line: moved to the end', 'line', string(t.GetText(t.Length - 4, 4)));
  // a whole table with text around it, moved to the end
  tbl := TableRtf(2);
  LoadRtf(FRich, tbl);
  t := FRich.Document.Text;
  CheckLikeCutAndPaste('a whole table with text around it', tbl, 7, t.ParaStart(7) + 3 - 7, 8,
    t.ParaStart(7) + 10, False);
  // the paragraph before a table with its end: the cut keeps that separator, so does the move
  LoadRtf(FRich, tbl);
  t := FRich.Document.Text;
  CheckLikeCutAndPaste('the paragraph before a table, with its end', tbl, 0, t.ParaStart(1), 1,
    t.ParaStart(7) + 5, False);
  LoadRtf(FRich, tbl);
  t := FRich.Document.Text;
  CheckLikeCutAndPaste('whole rows into a cell of their own table', tbl, t.ParaStart(4),
    t.ParaStart(7) - t.ParaStart(4), t.ParaStart(4) + 1, t.ParaStart(1) + 2, False);
  LoadRtf(FRich, tbl);
  t := FRich.Document.Text;
  CheckLikeCutAndPaste('whole rows copied after the table', tbl, t.ParaStart(1),
    t.ParaStart(4) - t.ParaStart(1), t.ParaStart(1) + 1, t.ParaStart(7) + 5, True);
  LoadRtf(FRich, tbl);
  t := FRich.Document.Text;
  CheckLikeCutAndPaste('a cell''s text into another cell', tbl, t.ParaStart(2) + 3, 1,
    t.ParaStart(2) + 3, t.ParaStart(6) + 1, False);
  LoadRtf(FRich, tbl);
  t := FRich.Document.Text;
  CheckLikeCutAndPaste('a copy across cells: the rows whole, after the table', tbl,
    t.ParaStart(1) + 1, t.ParaStart(5) + 2 - t.ParaStart(1) - 1, t.ParaStart(1) + 1,
    t.ParaStart(7) + 5, True);
  lst := Head + '\pard\f0 intro\par' + #13#10 +
    '{\pntext\f0 1.\tab}{\*\pn\pnlvlbody\pnf0\pnindent0\pnstart1\pndec{\pntxta.}}' +
    '\fi-360\li720 item one\par' + #13#10 + '{\pntext\f0 2.\tab}item two\par' + #13#10 +
    '\pard tail text\par' + #13#10 + '}';
  CheckLikeCutAndPaste('a list item to the end', lst, 6, 9, 7, 30, False);
  rtl := Head + '\pard\f0 left to right\par' + #13#10 + '\pard\rtlpar\qr right to left\par' +
    #13#10 + '}';
  CheckLikeCutAndPaste('words into a right-to-left paragraph', rtl, 0, 4, 1, 20, False);
end;

{ What the cut and the paste refuse is told once and changes nothing: a move across cells (a
  copy of the same goes), a place in a row that holds a nested table, a document that takes
  no edit any more when the button comes up. }
procedure TTyRichDragTest.TestRefusalsAreToldOnce;
var
  t: TTyRichText;
  d: TTyRichDocument;
  k, fixed: Integer;
  before: string;
  c: TTyRichCell;
  p: TPoint;
begin
  LoadRtf(FRich, TableRtf(2));
  t := FRich.Document.Text;
  before := AllText;
  Sel(t.ParaStart(1) + 1, 6);
  p := Pt(t.ParaStart(7) + 3);
  Drag(Mid(t.ParaStart(1) + 2), p);
  AssertEquals('across cells: told once', 1, FRich.Refused);
  AssertEquals('across cells: why', rsRichEditRefusedCells, FRich.LastReason);
  AssertEquals('across cells: nothing changed', before, AllText);
  AssertEquals('across cells: no step', 0, FRich.Document.UndoDepth);
  Drag(Mid(t.ParaStart(1) + 2), p, [ssCtrl]);
  AssertEquals('copied: nothing told', 1, FRich.Refused);
  AssertEquals('copied: one step', 1, FRich.Document.UndoDepth);
  // a row that holds a nested table
  LoadRtf(FRich, StrOfBytes(FixtureBytes('word-table-merged.rtf')));
  d := FRich.Document;
  t := d.Text;
  fixed := -1;
  for k := 0 to t.ParaCount - 1 do
  begin
    c := d.CellAt(k);
    if (c <> nil) and c.Row.HoldsNestedTable and (t.ParaLength(k) > 1) then
    begin
      fixed := k;
      Break;
    end;
  end;
  AssertTrue('a row that holds a nested table', fixed >= 0);
  FRich.Refused := 0;
  before := AllText;
  Sel(0, 3);
  PaintAll;
  p := Pt(t.ParaStart(fixed) + 1);
  if FRich.PositionAtPoint(p.X, p.Y) = t.ParaStart(fixed) + 1 then
  begin
    StartDrag(Mid(1), p, [ssCtrl]);
    AssertTrue('a nested table''s row: not here', FRich.Effect = rdeNone);
    FRich.ReleaseWith(p.X, p.Y, [ssCtrl]);
    AssertEquals('a nested table''s row: told once', 1, FRich.Refused);
    AssertEquals('a nested table''s row: why', rsRichEditRefusedFixedRow, FRich.LastReason);
    AssertEquals('a nested table''s row: nothing changed', before, AllText);
  end
  else
    Fail('the nested table''s row is not in view');
  // the document stops taking edits during the drag
  LoadText('one two three four');
  FRich.Refused := 0;
  Sel(4, 3);
  p := Pt(18);
  StartDrag(Mid(5), p);
  TDragLoadState.Put(FRich.Document, True);
  FRich.ReleaseAt(p.X, p.Y);
  AssertEquals('incomplete: told once', 1, FRich.Refused);
  AssertEquals('incomplete: why', rsRichEditRefusedIncomplete, FRich.LastReason);
  AssertEquals('incomplete: nothing changed', 'one two three four', AllText);
  TDragLoadState.Put(FRich.Document, False);
end;

{ A moved picture is the very object at its new place (undo puts that very one back); a copy
  is another object sharing the picture's bytes (the same block). A file's picture moved and
  undone saves as the file. }
procedure TTyRichDragTest.TestAMovedObjectIsTheVeryOneAndACopySharesItsBytes;
var
  pic, got: TTyRichPicture;
  r: TRect;
  p: TPoint;
  file0, s: RawByteString;
  d: TTyRichDocument;
  k: TTyRichPos;
begin
  LoadText('first line'#13#10'abcd');
  pic := TTyRichPicture.Create(rpfPng, PngOf(40, 30), 600, 450);
  AssertTrue('a picture', FRich.Document.Execute(TTyRichInsertObject.Create(13, pic)));
  FRich.Document.ClearUndo;
  FRich.UpdateView;
  PaintAll;
  Sel(13, 1);
  r := FRich.PositionRect(13);
  p := Point(r.Left + 12, (r.Top + r.Bottom) div 2);
  Drag(p, Pt(2));
  got := TTyRichPicture(FRich.Document.ObjectAt(2));
  AssertTrue('moved: the very object', got = pic);
  AssertEquals('moved: the text', 'fi' + TyRichObjectChar + 'rst line'#10'abcd',
    StringReplace(AllText, #13, '', [rfReplaceAll]));
  FRich.Undo;
  AssertTrue('undo: the very object back', FRich.Document.ObjectAt(13) = pic);
  // a copy: another object, the same bytes
  Sel(13, 1);
  PaintAll;
  r := FRich.PositionRect(13);
  p := Point(r.Left + 12, (r.Top + r.Bottom) div 2);
  Drag(p, Pt(2), [ssCtrl]);
  got := TTyRichPicture(FRich.Document.ObjectAt(2));
  AssertTrue('copied: an object there', got <> nil);
  AssertTrue('copied: another object', got <> pic);
  AssertTrue('copied: the very block of bytes', Pointer(got.Data) = Pointer(pic.Data));
  AssertTrue('the original still there', FRich.Document.ObjectAt(14) = pic);
  // a file's picture: moved, undone, saved: the file
  file0 := StrOfBytes(FixtureBytes('re-zh-picture.rtf'));
  LoadRtf(FRich, file0);
  d := FRich.Document;
  k := -1;
  for k := 0 to d.Text.Length - 1 do
    if d.ObjectAt(k) <> nil then Break;
  AssertTrue('the file''s picture', d.ObjectAt(k) <> nil);
  pic := TTyRichPicture(d.ObjectAt(k));
  PaintAll;
  Sel(k, 1);
  r := FRich.PositionRect(k);
  p := Point(r.Left + 8, (r.Top + r.Bottom) div 2);
  Drag(p, Pt(0));
  AssertTrue('the file''s picture moved: the very one', d.ObjectAt(0) = pic);
  FRich.Undo;
  s := SaveRtf(FRich);
  AssertEquals('moved and undone: the file', file0, s);
end;

{ Rows copied or moved out of a table go in as a table of their own (never the source's
  table object); the source table's own rows stay as they were. }
procedure TTyRichDragTest.TestRowsGoAsTablesOfTheirOwn;
var
  d: TTyRichDocument;
  t: TTyRichText;
  src: TTyRichTable;
  k: Integer;
  dump0: string;
begin
  LoadRtf(FRich, TableRtf(3));
  d := FRich.Document;
  t := d.Text;
  src := d.CellAt(1).Table;
  Sel(t.ParaStart(4), t.ParaStart(7) - t.ParaStart(4));
  Drag(Mid(t.ParaStart(4) + 1), Pt(t.ParaStart(10) + 5), [ssCtrl]);
  AssertEquals('one step', 1, d.UndoDepth);
  // the copied row: after 'after', a table of its own
  k := t.ParaCount - 4;
  AssertTrue('the copy is in a table', d.CellAt(k) <> nil);
  AssertTrue('a table of its own', d.CellAt(k).Table <> src);
  AssertEquals('its row: the first of its table', 0, d.CellAt(k).Row.Index);
  AssertTrue('the source rows keep their table', (d.CellAt(1).Table = src) and
    (d.CellAt(9).Table = src));
  FRich.Undo;
  dump0 := Dump(d);
  // moved
  Sel(t.ParaStart(4), t.ParaStart(7) - t.ParaStart(4));
  Drag(Mid(t.ParaStart(4) + 1), Pt(t.ParaStart(10) + 5));
  k := t.ParaCount - 4;
  AssertTrue('moved: in a table', d.CellAt(k) <> nil);
  AssertTrue('moved: a table of its own', d.CellAt(k).Table <> src);
  AssertTrue('the rows left keep theirs', (d.CellAt(1).Table = src) and (d.CellAt(4).Table = src));
  FRich.Undo;
  AssertEquals('undo: every paragraph and cell as it was', dump0, Dump(d));
end;

{ The receiving side fed by another's offer: the verdict (a copy), the mark, the drop as a
  paste of its text - one step, what went in selected -, read once; a picture alone in a
  plain text document is not here and told at the drop; read-only and DragDropEditing False
  take no drop; Leave changes nothing. }
procedure TTyRichDragTest.TestADropFromElsewhereGoesInAsAPaste;
var
  offer: TTestOffer;
  m: TRect;
  p: TPoint;
  bold: TTyCharFormatId;
begin
  LoadText('one two three');
  offer := TTestOffer.Create;
  try
    offer.Text := 'NEW';
    p := Pt(4);
    AssertTrue('a copy', FRich.DropEnter(offer, p.X, p.Y, []) = rdeCopy);
    AssertTrue('a session', FRich.DropActive);
    AssertTrue('a mark', FRich.Mark(m));
    AssertTrue('over: a copy', FRich.DropOver(Pt(8).X, Pt(8).Y, []) = rdeCopy);
    AssertEquals('nothing read before the drop', 0, offer.TextReads);
    AssertTrue('dropped: a copy', FRich.DropOn(p.X, p.Y, []) = rdeCopy);
    AssertFalse('the session ended', FRich.DropActive);
    AssertEquals('dropped as a paste', 'one NEWtwo three', AllText);
    AssertEquals('read once', 1, offer.TextReads);
    AssertEquals('taken once', 1, offer.Takes);
    AssertEquals('one step', 1, FRich.Document.UndoDepth);
    AssertEquals('named Copy', rsRichUndoCopy, FRich.Document.UndoDescription);
    AssertEquals('what went in selected', Int64(4), FRich.SelStart);
    AssertEquals('what went in, its length', Int64(3), FRich.SelLength);
    // Leave: nothing
    AssertTrue('again', FRich.DropEnter(offer, p.X, p.Y, []) = rdeCopy);
    FRich.DropLeave;
    AssertFalse('left: no mark', FRich.Mark(m));
    AssertEquals('left: nothing more', 1, FRich.Document.UndoDepth);
    // a picture alone into a plain text document: not here, told at the drop
    FRich.PlainText := True;
    offer.Text := '';
    offer.Picture := PngOf(4, 4);
    FRich.Refused := 0;
    AssertTrue('a picture into plain text: not here', FRich.DropEnter(offer, p.X, p.Y, []) = rdeNone);
    AssertTrue('a picture into plain text: nothing done', FRich.DropOn(p.X, p.Y, []) = rdeNone);
    AssertEquals('told once', 1, FRich.Refused);
    AssertEquals('why', rsRichEditRefusedPlainPaste, FRich.LastReason);
    FRich.PlainText := False;
    // a picture into a rich document: in, as a paste makes it
    AssertTrue('a picture: a copy', FRich.DropEnter(offer, p.X, p.Y, []) = rdeCopy);
    AssertTrue('a picture dropped', FRich.DropOn(p.X, p.Y, []) = rdeCopy);
    AssertTrue('a picture there', FRich.Document.ObjectAt(4) is TTyRichPicture);
    // text dropped into bold words, the selection in plain ones: the format at the place
    LoadRtf(FRich, Head + '\pard\f0 one \b two\b0  three\par' + #13#10 + '}');
    Sel(0, 3);
    bold := FRich.Document.TypingFormatAt(6);
    AssertTrue('the words differ', bold <> FRich.Document.TypingFormatAt(2));
    offer.Picture := nil;
    offer.Text := 'NEW';
    p := Pt(6);
    AssertTrue('into bold: a copy', FRich.DropEnter(offer, p.X, p.Y, []) = rdeCopy);
    AssertTrue('into bold: dropped', FRich.DropOn(p.X, p.Y, []) = rdeCopy);
    AssertEquals('into bold: the text', 'one twNEWo three', Copy(AllText, 1, 16));
    AssertEquals('into bold: the format at the place', bold, FRich.Document.TypingFormatAt(8));
  finally
    offer.Free;
  end;
  CheckUntouchedClipboard('offers');
end;

{ The commands alone, in a document: what each refuses (nothing changes), what it does, undo
  and redo exactly (every paragraph, its runs, objects and cells), its name, where it put the
  content (Placed). }
procedure TTyRichDragTest.TestTheCommandsWithoutAControl;
var
  d: TTyRichDocument;
  cmd: TTyRichRangeTransfer;
  before, after: string;
  i, k: Integer;
  t: TTyRichText;

  procedure CheckRefused(const AWhat: string; ACmd: TTyRichCommand);
  var
    b: string;
  begin
    b := Dump(d);
    AssertFalse(AWhat + ': refused', d.Execute(ACmd));
    AssertEquals(AWhat + ': nothing changed', b, Dump(d));
  end;

  procedure CheckExact(const AWhat: string; ACmd: TTyRichRangeTransfer; const AText: string);
  var
    cycle: Integer;
  begin
    before := Dump(d);
    AssertTrue(AWhat + ': runs', d.Execute(ACmd));
    AssertEquals(AWhat + ': the text''s integrity after it', '', d.Text.CheckIntegrity);
    AssertEquals(AWhat + ': the text', AText, StringReplace(DocText(d), #13, '', [rfReplaceAll]));
    after := Dump(d);
    AssertEquals(AWhat + ': one step', 1, d.UndoDepth);
    for cycle := 1 to 3 do
    begin
      d.Undo;
      AssertEquals(AWhat + ': undo exact', before, Dump(d));
      AssertEquals(AWhat + ': the text''s integrity', '', d.Text.CheckIntegrity);
      d.Redo;
      AssertEquals(AWhat + ': redo exact', after, Dump(d));
      AssertEquals(AWhat + ': the text''s integrity after the redo', '', d.Text.CheckIntegrity);
    end;
    d.Undo;
    d.ClearUndo;
  end;

begin
  d := LoadDocOf(TableRtf(2));
  try
    t := d.Text;
    // before the table 0..15, rows: 16..19 20..23 24..27 / 28.. , after
    CheckRefused('an empty range', TTyRichMove.Create(2, 0, 10));
    CheckRefused('a range past the text', TTyRichCopy.Create(t.Length - 2, 5, 0));
    CheckRefused('a place past the text', TTyRichCopy.Create(0, 3, t.Length + 1));
    CheckRefused('a move into its range', TTyRichMove.Create(2, 6, 5));
    CheckRefused('a move to its start', TTyRichMove.Create(2, 6, 2));
    CheckRefused('a move to its end', TTyRichMove.Create(2, 6, 8));
    CheckRefused('a copy strictly inside', TTyRichCopy.Create(2, 6, 3));
    CheckRefused('a move across cells', TTyRichMove.Create(t.ParaStart(1) + 1, 6, 0));
    // the separator before the table only (a cut keeps it): nothing to move
    CheckRefused('a move of the separator a cut keeps', TTyRichMove.Create(t.ParaStart(1) - 1, 1, 0));
    CheckExact('a copy to its start', TTyRichCopy.Create(2, 6, 2),
      'before tfore the table'#10'r0 a'#10'r0 b'#10'r0 c'#10'r1 a'#10'r1 b'#10'r1 c'#10'after the table');
    CheckExact('a move to the end', TTyRichMove.Create(0, 7, t.Length),
      'the table'#10'r0 a'#10'r0 b'#10'r0 c'#10'r1 a'#10'r1 b'#10'r1 c'#10'after the tablebefore ');
    CheckExact('whole rows moved after the table', TTyRichMove.Create(t.ParaStart(1),
      t.ParaStart(4) - t.ParaStart(1), t.ParaStart(7) + 5),
      'before the table'#10'r1 a'#10'r1 b'#10'r1 c'#10'after'#10'r0 a'#10'r0 b'#10'r0 c'#10' the table');
    CheckExact('a copy across cells: its rows whole', TTyRichCopy.Create(t.ParaStart(1) + 1, 6, 0),
      'r0 a'#10'r0 b'#10'r0 c'#10'before the table'#10'r0 a'#10'r0 b'#10'r0 c'#10'r1 a'#10'r1 b'#10'r1 c'#10'after the table');
    // Placed and the name
    cmd := TTyRichMove.Create(0, 7, 10);
    AssertTrue('a move', d.Execute(cmd));
    AssertEquals('placed at', Int64(3), cmd.Placed.Pos);
    AssertEquals('placed: its length', Int64(7), cmd.Placed.Len);
    AssertEquals('the name', rsRichUndoMove, d.UndoDescription);
    d.Undo;
    cmd := TTyRichCopy.Create(0, 7, 10);
    AssertTrue('a copy', d.Execute(cmd));
    AssertEquals('copied: placed at', Int64(10), cmd.Placed.Pos);
    AssertEquals('copied: the name', rsRichUndoCopy, d.UndoDescription);
    d.Undo;
    // the commands while the document takes no edit
    TDragLoadState.Put(d, True);
    CheckRefused('incomplete', TTyRichCopy.Create(0, 3, 10));
    TDragLoadState.Put(d, False);
  finally
    d.Free;
  end;
  // a place in a row that holds a nested table, and a move out of such a row's text
  d := LoadDocOf(StrOfBytes(FixtureBytes('word-table-merged.rtf')));
  try
    t := d.Text;
    k := -1;
    for i := 0 to t.ParaCount - 1 do
      if (d.CellAt(i) <> nil) and d.CellAt(i).Row.HoldsNestedTable and (t.ParaLength(i) > 1) then
      begin
        k := i;
        Break;
      end;
    AssertTrue('a row that holds a nested table', k >= 0);
    CheckRefused('a copy into a nested table''s row', TTyRichCopy.Create(0, 1, t.ParaStart(k) + 1));
    CheckRefused('a move out of a nested table''s row', TTyRichMove.Create(t.ParaStart(k), 1,
      t.Length));
  finally
    d.Free;
  end;
  // every paragraph the same after many cycles in a document of objects
  d := LoadDocOf(StrOfBytes(FixtureBytes('re-zh-picture.rtf')));
  try
    for i := 0 to d.Text.Length - 1 do
      if d.ObjectAt(i) <> nil then Break;
    CheckExact('a picture moved to the start', TTyRichMove.Create(i, 1, 0),
      StringReplace(TyRichObjectChar + d.Text.GetText(0, i) + d.Text.GetText(i + 1,
      d.Text.Length - i - 1), #13, '', [rfReplaceAll]));
  finally
    d.Free;
  end;
end;

{ A move or a copy copies no text (the add buffer grows by the paragraph marks at most), and its
  step holds a few bytes per paragraph; a lazily read file: a move undone saves as the file, and
  after a move the paragraphs it did not touch are still written as the file's bytes. }
procedure TTyRichDragTest.TestTheCommandsKeepTheFileAndCopyNoText;
var
  d: TTyRichDocument;
  st: TBytesStream;
  s, file0, saved: RawByteString;
  i: Integer;
  t: TTyRichText;
  added, moved: Int64;
begin
  // a text of 2,000 lines, 500 KB: a move of half of it and a copy of half of it
  s := '';
  for i := 1 to 2000 do
    s := s + 'Line number ' + IntToStr(i) + ' of the text file ' + StringOfChar('x', 220) + #13#10;
  d := TTyRichDocument.Create;
  try
    st := TBytesStream.Create(RawBytes(s));
    try
      TyRichLoadText(d, st);
    finally
      st.Free;
    end;
    t := d.Text;
    added := t.AddedBytes;
    moved := t.ParaStart(1100) - t.ParaStart(100);
    AssertTrue('a move', d.Execute(TTyRichMove.Create(t.ParaStart(100), t.ParaStart(1100) -
      t.ParaStart(100), t.ParaStart(1900))));
    AssertTrue('the move copied no text', t.AddedBytes - added <= 4);
    WriteLn(Format('TTyRichDragTest: a move of %d bytes of text: its step holds %d bytes',
      [moved, d.HistoryBytes]));
    AssertTrue(Format('the move''s step holds %d bytes', [d.HistoryBytes]),
      d.HistoryBytes < moved div 3);
    { (and it counts what it holds: the pieces the delete keeps and those the fragment keeps -
      a piece a paragraph each, 24 bytes) }
    AssertTrue('the step counts both', d.HistoryBytes >= 2 * 1000 * 24);
    added := t.AddedBytes;
    AssertTrue('a copy', d.Execute(TTyRichCopy.Create(t.ParaStart(10), t.ParaStart(1010) -
      t.ParaStart(10), t.Length)));
    AssertTrue('the copy copied no text', t.AddedBytes - added <= 4);
    d.Undo;
    d.Undo;
    st := TBytesStream.Create;
    try
      TyRichSaveText(d, st);
      AssertEquals('undone: the file', s, StrOfBytes(Copy(st.Bytes, 0, st.Size)));
    finally
      st.Free;
    end;
  finally
    d.Free;
  end;
  // a file read on demand
  file0 := Head;
  for i := 0 to 199 do
    file0 := file0 + '\pard\f0 Paragraph ' + IntToStr(i) + ' of the \b file\b0.\par' + #13#10;
  file0 := file0 + '}';
  d := LoadDocOf(file0);
  try
    t := d.Text;
    AssertTrue('a move', d.Execute(TTyRichMove.Create(t.ParaStart(10), t.ParaStart(20) -
      t.ParaStart(10), t.ParaStart(150))));
    AssertEquals('the move: the text''s integrity', '', t.CheckIntegrity);
    saved := SaveDoc(d);
    AssertTrue('an untouched paragraph is the file''s bytes',
      Pos('\pard\f0 Paragraph 100 of the \b file\b0.\par', saved) > 0);
    AssertTrue('a moved paragraph is there',
      Pos('Paragraph 15 of the', saved) > Pos('Paragraph 140 of the', saved));
    d.Undo;
    AssertEquals('moved and undone: the file', file0, SaveDoc(d));
    d.Redo;
    d.Undo;
    AssertEquals('redone and undone: the file', file0, SaveDoc(d));
    AssertTrue('a copy', d.Execute(TTyRichCopy.Create(t.ParaStart(10), t.ParaStart(20) -
      t.ParaStart(10), t.ParaStart(150))));
    AssertEquals('the copy: the text''s integrity', '', t.CheckIntegrity);
    d.Undo;
    AssertEquals('copied and undone: the file', file0, SaveDoc(d));
  finally
    d.Free;
  end;
end;

initialization
  RegisterTest(TTyRichDragTest);

end.
