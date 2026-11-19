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
    procedure SetFindSlice(AChars: Int64);
    procedure Designing;
  end;

  { An opaque object whose clones are counted alive, and whose CloneFailAt-th clone raises. }
  TCloneCounted = class(TTyRichOpaque)
  public
    class var Live, Clones, CloneFailAt: Integer;
    constructor Create(const ABytes: RawByteString);
    destructor Destroy; override;
    function Clone: TTyRichObject; override;
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
    class procedure PutLoading(ADoc: TTyRichDocument; ALoading: Boolean);
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
  private
    FFindEnds: array of string;
    procedure FindDone(Sender: TObject; AEnd: TTyRichFindEnd; APos, ALen: TTyRichPos);
    procedure ReplaceDone(Sender: TObject; const AResult: TTyRichReplaceResult);
    procedure TurnSome(AMost: Integer);
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
    procedure TestADragEndsBackgroundWorkAsTypingDoes;
    procedure TestTheMarkFollowsTheViewUnderThePointer;
    procedure TestOutsideTheControlIsNoPlace;
    procedure TestACopyWhoseCloneFailsLeavesNothingAlive;
    procedure TestTheDragThresholdFollowsTheScreen;
    procedure TestTheEatenMenuIsOnlyThatPresss;
    procedure TestAMoveKeepsNoMoreThanACutAndAPaste;
    procedure TestWhatHadNoTest;
    procedure TestAPressOnTheSelectionEndsBackgroundWork;
    procedure TestTheMarkLeavesNoDotWhenTheSurfaceScrolls;
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

procedure TDragProbe.SetFindSlice(AChars: Int64);
begin
  FindSlice := AChars;
end;

procedure TDragProbe.Designing;
begin
  MakeDesigning;
end;

constructor TCloneCounted.Create(const ABytes: RawByteString);
begin
  inherited Create(ABytes, '', 1);
  Inc(Live);
end;

destructor TCloneCounted.Destroy;
begin
  Dec(Live);
  inherited Destroy;
end;

function TCloneCounted.Clone: TTyRichObject;
begin
  Inc(Clones);
  if Clones = CloneFailAt then raise EOutOfMemory.Create('the test''s failing clone');
  Result := TCloneCounted.Create(Bytes);
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

class procedure TDragLoadState.PutLoading(ADoc: TTyRichDocument; ALoading: Boolean);
begin
  SetLoadState(ADoc, ALoading, False);
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

{ DragDropEditing False, DragMode dmAutomatic, a document that takes no edit: a press inside
  the selection is a click at once; no drop is taken. Read-only: the selection can be dragged
  (out of the control, as a copy), but nothing is a place inside it - the release changes
  nothing, and no drop from elsewhere is taken. A plain text document drags its text. }
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
    if i = 0 then
    begin
      AssertTrue('read-only: the press waits', FRich.Pending);
      FRich.MoveWith(Mid(15).X, Mid(15).Y, []);
      AssertTrue('read-only: a drag', FRich.OwnDrag);
      AssertTrue('read-only: not here', FRich.Effect = rdeNone);
      FRich.ReleaseAt(Mid(15).X, Mid(15).Y);
      AssertEquals('read-only: the selection stays', Int64(9), FRich.SelLength);
    end
    else
    begin
      AssertFalse(Format('case %d: no drag', [i]), FRich.Pending);
      AssertEquals(Format('case %d: a click at once', [i]), Int64(0), FRich.SelLength);
      FRich.MoveWith(Mid(15).X, Mid(15).Y, []);
      AssertFalse(Format('case %d: no drag after a move', [i]), FRich.OwnDrag);
      FRich.ReleaseAt(Mid(15).X, Mid(15).Y);
    end;
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
  pp: TPoint;
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
  // a zoom: the mark at the place now under the pointer, at the new size
  pp := Pt(20);
  FRich.MoveWith(pp.X, pp.Y, []);
  FRich.Zoom := 200;
  PaintAll;
  AssertTrue('the drag goes on through a zoom', FRich.OwnDrag);
  AssertTrue('a mark at 200 %', FRich.Mark(m));
  q := FRich.PositionAtPoint(pp.X, pp.Y);
  pr := FRich.PositionRect(q);
  AssertTrue('at the place under the pointer at 200 %', (m.Left <= pr.Left) and
    (m.Right > pr.Left) and (m.Top = pr.Top) and (m.Bottom = pr.Bottom));
  FRich.Zoom := 100;
  PaintAll;
  // a scroll: the mark at the place now under the pointer
  FRich.ScrollY := 40;
  PaintAll;
  AssertTrue('the drag goes on through a scroll', FRich.OwnDrag);
  AssertTrue('a mark after the scroll', FRich.Mark(m2));
  q := FRich.PositionAtPoint(pp.X, pp.Y);
  pr := FRich.PositionRect(q);
  AssertTrue('at the place under the pointer after the scroll', (m2.Left <= pr.Left) and
    (m2.Right > pr.Left) and (m2.Top = pr.Top));
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

{ Near an edge of the text, inside the control (half a line inside the text, and the padding
  between the text and the control's edge), each tick scrolls - a line, and one more for every
  line's height further out, as a drag-select's tick at the same point; in the middle, and with
  the pointer outside the control, not at all. The place follows the text that came; the release
  drops there. The top edge too. }
procedure TTyRichDragTest.TestTheTextScrollsNearAndPastAnEdge;
var
  s: string;
  i: Integer;
  area: TRect;
  y0, y1, dSel, dDrop: Int64;
  other: TDragProbe;
  q: TTyRichPos;
  m, pr: TRect;
  yb: Integer;
begin
  s := '';
  for i := 1 to 80 do s := s + 'Line ' + IntToStr(i) + #13#10;
  LoadText(s);
  area := FRich.Area;
  AssertTrue('room between the text and the control''s bottom edge', area.Bottom < FRich.Height - 1);
  yb := FRich.Height - 1;
  Sel(0, 4);
  StartDrag(Mid(1), Point(Mid(1).X, (area.Top + area.Bottom) div 2));
  y0 := FRich.ScrollY;
  FRich.DragTick;
  AssertEquals('in the middle: no scroll', y0, FRich.ScrollY);
  // near the bottom edge, inside the text: a line a tick
  FRich.MoveWith(Mid(1).X, area.Bottom - 2, []);
  FRich.DragTick;
  y1 := FRich.ScrollY;
  AssertTrue('near the edge: scrolled', y1 > y0);
  // below the text, on the control's last row of pixels: as a drag-select there
  FRich.MoveWith(Mid(1).X, yb, []);
  y0 := FRich.ScrollY;
  FRich.DragTick;
  dDrop := FRich.ScrollY - y0;
  other := NewProbe;
  try
    other.Lines.Text := s;
    other.UpdateView;
    PaintAll(other);
    other.PressAt(5, area.Top + 5);
    other.MoveAt(5, yb);
    y0 := other.ScrollY;
    other.DragTick;
    dSel := other.ScrollY - y0;
    other.ReleaseAt(5, yb);
  finally
    other.Free;
  end;
  AssertTrue('below the text: scrolled', dDrop > 0);
  AssertEquals('below the text: as a drag-select', dSel, dDrop);
  // outside the control: no scroll
  FRich.MoveWith(Mid(1).X, FRich.Height + 40, []);
  y0 := FRich.ScrollY;
  FRich.DragTick;
  AssertEquals('outside the control: no scroll', y0, FRich.ScrollY);
  FRich.MoveWith(Mid(1).X, yb, []);
  for i := 1 to 5 do FRich.DragTick;
  PaintAll;
  // the place: the last line shown, under the pointer held to the text
  q := FRich.PositionAtPoint(Mid(1).X, area.Bottom - 1);
  AssertTrue('the mark at the place that came', FRich.Mark(m));
  AssertTrue('the place is far down', q > 200);
  pr := FRich.PositionRect(q);
  AssertTrue('the mark on that place', (m.Left <= pr.Left) and (m.Right > pr.Left) and
    (m.Top = pr.Top));
  FRich.ReleaseWith(Mid(1).X, yb, []);
  AssertEquals('dropped there: one step', 1, FRich.Document.UndoDepth);
  AssertEquals('the moved word there', 'Line', FRich.SelText);
  AssertTrue('moved far down', FRich.SelStart > 200);
  // the top edge: near it a scroll up, outside the control none
  FRich.Undo;
  FRich.ScrollY := FRich.Document.Text.TotalHeight;
  PaintAll;
  Sel(FRich.Document.Text.ParaStart(78), 4);
  StartDrag(Mid(FRich.Document.Text.ParaStart(78) + 1), Point(Mid(1).X, -30));
  y0 := FRich.ScrollY;
  FRich.DragTick;
  AssertEquals('above the control: no scroll', y0, FRich.ScrollY);
  FRich.MoveWith(Mid(1).X, area.Top + 1, []);
  FRich.DragTick;
  AssertTrue('near the top: scrolled up', FRich.ScrollY < y0);
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
    { (and it counts what it holds: the pieces of the paragraphs moved, which the delete and
      the fragment share - 24 bytes a paragraph -, and a value's place for each, 17) }
    AssertTrue('the step counts its pieces and its parts', d.HistoryBytes >= 1000 * (24 + 17));
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

procedure TTyRichDragTest.FindDone(Sender: TObject; AEnd: TTyRichFindEnd; APos, ALen: TTyRichPos);
begin
  SetLength(FFindEnds, Length(FFindEnds) + 1);
  case AEnd of
    rfeFound: FFindEnds[High(FFindEnds)] := 'find found';
    rfeNotFound: FFindEnds[High(FFindEnds)] := 'find not found';
  else
    FFindEnds[High(FFindEnds)] := 'find cancelled';
  end;
end;

procedure TTyRichDragTest.ReplaceDone(Sender: TObject; const AResult: TTyRichReplaceResult);
begin
  SetLength(FFindEnds, Length(FFindEnds) + 1);
  if AResult.Ending = rreCancelled then FFindEnds[High(FFindEnds)] := 'replace cancelled'
  else FFindEnds[High(FFindEnds)] := 'replace ended';
end;

procedure TTyRichDragTest.TurnSome(AMost: Integer);
var
  i: Integer;
begin
  for i := 1 to AMost do
    if FRich.FindRunning then FRich.Turn;
end;

{ A background replace or find, and the user: a character typed ends it at its next turn
  (cancelled, its one event); the start of a drag ends it at once in the same way, and nothing
  changes the document or the selection under the drag after that - the drag goes on, the drop
  is one step on top. A document still loading: no drag starts, the press is a click. }
procedure TTyRichDragTest.TestADragEndsBackgroundWorkAsTypingDoes;
var
  s: string;
  i: Integer;
  p: TPoint;
  st: TBytesStream;
  depth: Integer;
  t: TTyRichText;
begin
  s := '';
  for i := 1 to 3000 do s := s + 'a cat sat here ' + IntToStr(i) + #13#10;
  FRich.OnFindDone := @FindDone;
  FRich.OnReplaceDone := @ReplaceDone;
  // typing during a replace
  LoadText(s);
  FRich.SetFindSlice(1024);
  FRich.ReplaceAllAsync('cat', 'dog');
  i := 0;
  while FRich.FindRunning and (Pos('dog', AllText) = 0) and (i < 10000) do
  begin
    FRich.Turn;
    Inc(i);
  end;
  AssertTrue('the replace runs, some replaced', FRich.FindRunning and (Pos('dog', AllText) > 0));
  FFindEnds := nil;
  FRich.SelStart := 0;
  FRich.TypeChar('x');
  TurnSome(5);
  AssertFalse('typing: the replace ended', FRich.FindRunning);
  AssertEquals('typing: one event', 1, Length(FFindEnds));
  AssertEquals('typing: cancelled', 'replace cancelled', FFindEnds[0]);
  // a drag started during a replace
  LoadText(s);
  FRich.SetFindSlice(1024);
  FRich.ReplaceAllAsync('cat', 'dog');
  i := 0;
  while FRich.FindRunning and (Pos('dog', AllText) = 0) and (i < 10000) do
  begin
    FRich.Turn;
    Inc(i);
  end;
  AssertTrue('a replace running', FRich.FindRunning);
  depth := FRich.Document.UndoDepth;
  FFindEnds := nil;
  Sel(2, 3);
  p := Pt(15);
  StartDrag(Mid(3), p);
  AssertFalse('the drag''s start: the replace ended', FRich.FindRunning);
  AssertEquals('the drag''s start: one event', 1, Length(FFindEnds));
  AssertEquals('the drag''s start: cancelled', 'replace cancelled', FFindEnds[0]);
  TurnSome(5);
  AssertTrue('the drag goes on', FRich.OwnDrag);
  AssertEquals('the selection under the drag', Int64(2), FRich.SelStart);
  FRich.ReleaseAt(p.X, p.Y);
  AssertEquals('the drop: one step on top', depth + 1, FRich.Document.UndoDepth);
  AssertEquals('the drop: named Move', rsRichUndoMove, FRich.Document.UndoDescription);
  AssertEquals('still one event', 1, Length(FFindEnds));
  // a drag started during a find (its needle far down)
  LoadText(s + 'needle'#13#10);
  FRich.SetFindSlice(1024);
  FFindEnds := nil;
  FRich.FindNextAsync('needle', []);
  FRich.Turn;
  AssertTrue('a find running', FRich.FindRunning);
  Sel(2, 3);
  StartDrag(Mid(3), p);
  AssertFalse('the drag''s start: the find ended', FRich.FindRunning);
  AssertEquals('the find: one event', 1, Length(FFindEnds));
  AssertEquals('the find: cancelled', 'find cancelled', FFindEnds[0]);
  TurnSome(5);
  AssertTrue('the drag goes on after the find', FRich.OwnDrag);
  AssertEquals('the selection under it', Int64(2), FRich.SelStart);
  FRich.ReleaseAt(p.X, p.Y);
  AssertEquals('dropped', 1, FRich.Document.UndoDepth);
  // typing during a find ends it the same way
  FFindEnds := nil;
  FRich.FindNextAsync('needle', []);
  FRich.Turn;
  FRich.TypeChar('y');
  TurnSome(5);
  AssertEquals('typing during a find: one event', 1, Length(FFindEnds));
  AssertEquals('typing during a find: cancelled', 'find cancelled', FFindEnds[0]);
  // a document still loading (the load's own state, as a reader sets it): the press is a click
  LoadText('one two three four');
  TDragLoadState.PutLoading(FRich.Document, True);
  AssertTrue('loading', FRich.Loading);
  Sel(4, 9);
  FRich.PressAt(Mid(6).X, Mid(6).Y);
  AssertFalse('loading: no drag', FRich.Pending);
  AssertEquals('loading: a click', Int64(0), FRich.SelLength);
  FRich.ReleaseAt(Mid(6).X, Mid(6).Y);
  TDragLoadState.PutLoading(FRich.Document, False);
  FRich.OnFindDone := nil;
  FRich.OnReplaceDone := nil;
end;

{ After a scroll by the wheel or the scroll bar, a zoom or a new size during a drag, with no
  move of the pointer: the mark and the verdict are the place now under the pointer, and the
  release drops there. }
procedure TTyRichDragTest.TestTheMarkFollowsTheViewUnderThePointer;
var
  s: string;
  i, k: Integer;
  p: TPoint;
  q, q0: TTyRichPos;
  m, pr: TRect;

  procedure CheckMark(const AWhat: string);
  begin
    PaintAll;
    q := FRich.PositionAtPoint(p.X, p.Y);
    AssertTrue(AWhat + ': a mark', FRich.Mark(m));
    pr := FRich.PositionRect(q);
    AssertTrue(Format('%s: the mark at the place under the pointer (%d)', [AWhat, q]),
      (m.Left <= pr.Left) and (m.Right > pr.Left) and (m.Top = pr.Top));
    AssertTrue(AWhat + ': the verdict there', FRich.Effect = rdeMove);
    AssertEquals(AWhat + ': the cursor', Ord(crDrag), Ord(FRich.CursorFor(p.X, p.Y)));
  end;

begin
  s := '';
  for i := 1 to 80 do s := s + 'Line number ' + IntToStr(i) + #13#10;
  for k := 0 to 4 do
  begin
    LoadText(s);
    Sel(0, 4);
    p := Point(Mid(8).X, (FRich.Area.Top + FRich.Area.Bottom) div 2);
    StartDrag(Mid(1), p);
    PaintAll;
    q0 := FRich.PositionAtPoint(p.X, p.Y);
    case k of
      0: FRich.Wheel(-120, [ssLeft]);
      1: FRich.VBar.Position := FRich.VBar.Position + 40;
      2: FRich.Zoom := 150;
      3: FRich.ScrollY := FRich.ScrollY + 50;
      4: FRich.SetBounds(0, 0, 300, 300);
    end;
    PaintAll;
    if k < 4 then
      AssertTrue(Format('case %d: another place under the pointer', [k]),
        FRich.PositionAtPoint(p.X, p.Y) <> q0);
    CheckMark(Format('case %d', [k]));
    FRich.ReleaseWith(p.X, p.Y, []);
    AssertEquals(Format('case %d: one step', [k]), 1, FRich.Document.UndoDepth);
    AssertEquals(Format('case %d: dropped at the mark', [k]), q - 4, FRich.SelStart);
    FRich.Zoom := 100;
    FRich.SetBounds(0, 0, 400, 300);
  end;
end;

{ The pointer outside the control: no mark, "not here", a release does nothing - one pixel
  past each edge and far away. }
procedure TTyRichDragTest.TestOutsideTheControlIsNoPlace;
const
  N = 6;
var
  pts: array[0..N - 1] of TPoint;
  i: Integer;
  m: TRect;
begin
  LoadText('one two three four');
  pts[0] := Point(-1, Mid(5).Y);
  pts[1] := Point(FRich.Width, Mid(5).Y);
  pts[2] := Point(Mid(5).X, -1);
  pts[3] := Point(Mid(5).X, FRich.Height);
  pts[4] := Point(-200, 10);
  pts[5] := Point(150, 900);
  for i := 0 to N - 1 do
  begin
    Sel(4, 3);
    StartDrag(Mid(5), pts[i]);
    AssertTrue(Format('point %d: not here', [i]), FRich.Effect = rdeNone);
    AssertFalse(Format('point %d: no mark', [i]), FRich.Mark(m));
    AssertEquals(Format('point %d: the cursor', [i]), Ord(crNoDrop),
      Ord(FRich.CursorFor(pts[i].X, pts[i].Y)));
    FRich.ReleaseAt(pts[i].X, pts[i].Y);
    AssertEquals(Format('point %d: the text', [i]), 'one two three four', AllText);
    AssertEquals(Format('point %d: no step', [i]), 0, FRich.Document.UndoDepth);
    AssertEquals(Format('point %d: the selection', [i]), Int64(4), FRich.SelStart);
    AssertEquals(Format('point %d: its length', [i]), Int64(3), FRich.SelLength);
  end;
  // back inside: a place again
  Sel(4, 3);
  StartDrag(Mid(5), pts[4]);
  FRich.MoveWith(Pt(18).X, Pt(18).Y, []);
  AssertTrue('back inside: a move', FRich.Effect = rdeMove);
  FRich.ReleaseAt(Pt(18).X, Pt(18).Y);
  AssertEquals('dropped inside', 'one  three fourtwo', AllText);
end;

{ A copy whose second clone of an object fails: the document as it was, and no clone left alive
  (the three objects in the text only), nothing after the document goes. }
procedure TTyRichDragTest.TestACopyWhoseCloneFailsLeavesNothingAlive;
var
  d: TTyRichDocument;
  b: string;
  raised: Boolean;
begin
  TCloneCounted.Live := 0;
  d := TTyRichDocument.Create;
  try
    d.Execute(TTyRichInsertText.Create(0, 'abcdef'));
    d.Execute(TTyRichInsertObject.Create(1, TCloneCounted.Create('{\object one}')));
    d.Execute(TTyRichInsertObject.Create(3, TCloneCounted.Create('{\object two}')));
    d.Execute(TTyRichInsertObject.Create(5, TCloneCounted.Create('{\object three}')));
    d.ClearUndo;
    AssertEquals('three objects', 3, TCloneCounted.Live);
    b := Dump(d);
    TCloneCounted.Clones := 0;
    TCloneCounted.CloneFailAt := 2;
    raised := False;
    try
      d.Execute(TTyRichCopy.Create(0, d.Text.Length, d.Text.Length));
    except
      on EOutOfMemory do raised := True;
    end;
    AssertTrue('the copy failed', raised);
    AssertEquals('the document as it was', b, Dump(d));
    AssertEquals('no step', 0, d.UndoDepth);
    AssertEquals('no clone alive', 3, TCloneCounted.Live);
    TCloneCounted.CloneFailAt := 0;
  finally
    d.Free;
  end;
  AssertEquals('nothing alive after the document', 0, TCloneCounted.Live);
end;

{ The threshold is LCL's (Mouse.DragThreshold) at 96 PPI, scaled with the control's PPI: the
  same distance on every screen. }
procedure TTyRichDragTest.TestTheDragThresholdFollowsTheScreen;
var
  r: TDragProbe;
  p: TPoint;
begin
  AssertEquals('at 96 PPI: LCL''s', Mouse.DragThreshold, FRich.Threshold);
  r := TDragProbe.Create(nil);
  try
    r.Controller := FCtl;
    r.Font.PixelsPerInch := 192;
    r.SetBounds(0, 0, 400, 300);
    r.Lines.Text := 'one two three four';
    r.UpdateView;
    PaintAll(r);
    AssertEquals('at 192 PPI: twice', 2 * Mouse.DragThreshold, r.Threshold);
    r.SelStart := 4;
    r.SelLength := 3;
    p := Point((r.PositionRect(5).Left + r.PositionRect(6).Left) div 2,
      (r.PositionRect(5).Top + r.PositionRect(5).Bottom) div 2);
    r.PressAt(p.X, p.Y);
    AssertTrue('pending', r.Pending);
    r.MoveWith(p.X, p.Y + Mouse.DragThreshold + 1, []);
    AssertFalse('past the 96 PPI distance only: no drag yet', r.OwnDrag);
    r.MoveWith(p.X, p.Y + 2 * Mouse.DragThreshold + 1, []);
    AssertTrue('past the scaled distance: the drag', r.OwnDrag);
    r.Press(VK_ESCAPE, [ssLeft]);
    r.ReleaseAt(p.X, p.Y);
  finally
    r.Free;
  end;
end;

{ A right press that ends a drag eats the menu of that press only: the next key or mouse event
  lets the menu come again. }
procedure TTyRichDragTest.TestTheEatenMenuIsOnlyThatPresss;
var
  p: TPoint;
  menus: Integer;
begin
  LoadText('one two three four');
  // a key after it
  Sel(4, 3);
  p := Pt(14);
  StartDrag(Mid(5), p);
  FRich.RightPressAt(p.X, p.Y);
  AssertFalse('ended', FRich.OwnDrag);
  menus := FRich.MenuShows;
  FRich.Press(VK_APPS, [ssLeft]);
  FRich.PopupAt(p.X, p.Y);
  AssertEquals('after a key: the menu', menus + 1, FRich.MenuShows);
  FRich.ReleaseAt(p.X, p.Y);
  // a move of the mouse after it
  Sel(4, 3);
  StartDrag(Mid(5), p);
  FRich.RightPressAt(p.X, p.Y);
  FRich.MoveWith(p.X + 3, p.Y, []);
  menus := FRich.MenuShows;
  FRich.PopupAt(p.X, p.Y);
  AssertEquals('after a move: the menu', menus + 1, FRich.MenuShows);
  FRich.ReleaseAt(p.X, p.Y);
  // the popup of that press itself: eaten
  Sel(4, 3);
  StartDrag(Mid(5), p);
  FRich.RightPressAt(p.X, p.Y);
  menus := FRich.MenuShows;
  AssertTrue('that press''s popup: handled', FRich.PopupAt(p.X, p.Y));
  AssertEquals('that press''s popup: no menu', menus, FRich.MenuShows);
  FRich.PopupAt(p.X, p.Y);
  AssertEquals('the next popup: the menu', menus + 1, FRich.MenuShows);
  FRich.ReleaseAt(p.X, p.Y);
end;

{ What a move's step keeps: counted as it is held (100,000 paragraphs of one character, the
  heap's own count), and no more than a cut's step and a paste's step of the same content keep
  together (20,000 lines of 20 characters). }
procedure TTyRichDragTest.TestAMoveKeepsNoMoreThanACutAndAPaste;
var
  d: TTyRichDocument;
  st: TBytesStream;
  s, txt: RawByteString;
  i: Integer;
  t: TTyRichText;
  a, len, at: TTyRichPos;
  h0, held, moveBytes, cutPaste: Int64;

  function LoadLines(AParas, AChars: Integer): TTyRichDocument;
  var
    line: RawByteString;
    k: Integer;
  begin
    line := StringOfChar('x', AChars) + #13#10;
    s := '';
    SetLength(s, AParas * Length(line));
    for k := 0 to AParas - 1 do Move(line[1], s[k * Length(line) + 1], Length(line));
    Result := TTyRichDocument.Create;
    st := TBytesStream.Create(RawBytes(s));
    try
      TyRichLoadText(Result, st);
    finally
      st.Free;
    end;
  end;

begin
  d := LoadLines(200000, 1);
  try
    t := d.Text;
    a := t.ParaStart(20000);
    len := t.ParaStart(120000) - a;
    at := t.ParaStart(180000);
    h0 := GetFPCHeapStatus.CurrHeapUsed;
    AssertTrue('a move', d.Execute(TTyRichMove.Create(a, len, at)));
    held := GetFPCHeapStatus.CurrHeapUsed - h0;
    WriteLn(Format('TTyRichDragTest: a move of 100,000 paragraphs: held %d bytes, counted %d',
      [held, d.HistoryBytes]));
    AssertTrue(Format('counted at least what it holds: %d of %d', [d.HistoryBytes, held]),
      d.HistoryBytes >= held * 9 div 10);
    AssertTrue(Format('counted no more than what it holds: %d of %d', [d.HistoryBytes, held]),
      d.HistoryBytes <= held * 11 div 10);
  finally
    d.Free;
  end;
  // against a cut and a paste
  d := LoadLines(40000, 20);
  try
    t := d.Text;
    a := t.ParaStart(5000);
    len := t.ParaStart(25000) - a;
    at := t.ParaStart(35000);
    AssertTrue('a move', d.Execute(TTyRichMove.Create(a, len, at)));
    moveBytes := d.HistoryBytes;
    d.Undo;
    d.ClearUndo;
    txt := t.GetText(a, len);
    AssertTrue('a cut', d.Execute(TTyRichDelete.Create(a, len)));
    AssertTrue('a paste', d.Execute(TTyRichInsertText.Create(at - len, txt, TyRichInheritFormat,
      False)));
    cutPaste := d.HistoryBytes;
    WriteLn(Format('TTyRichDragTest: 20,000 lines of 20 characters: the move''s step %d bytes, ' +
      'the cut''s and the paste''s %d', [moveBytes, cutPaste]));
    AssertTrue(Format('the move keeps %d, the cut and the paste %d', [moveBytes, cutPaste]),
      moveBytes <= cutPaste);
  finally
    d.Free;
  end;
end;

{ What a drag does that no test held: a refused move or copy through the user's door tells its
  reason once; a triple press on the selection selects the paragraph; the mark after a scroll
  of the kept surface; a drop where a paragraph is too long to lay out; the horizontal edge
  scrolling; the left and right Ctrl keys; no drop in the form designer. }
procedure TTyRichDragTest.TestWhatHadNoTest;
var
  d: TTyRichDocument;
  t: TTyRichText;
  k, i, fixed: Integer;
  c: TTyRichCell;
  p, pOld: TPoint;
  m, m2: TRect;
  st: TTyRichPaintStyle;
  px: TBGRAPixel;
  s: string;
  x0: Integer;
  offer: TTestOffer;
  r: TDragProbe;
  n1: Integer;

  function CountFrame: Integer;
  var
    x, y: Integer;
    q: TBGRAPixel;
  begin
    Result := 0;
    for y := 0 to FRich.Surf.Height - 1 do
      for x := 0 to FRich.Surf.Width - 1 do
      begin
        q := FRich.Surf.GetPixel(x, y);
        if (q.red = st.ObjectFrame.red) and (q.green = st.ObjectFrame.green) and
          (q.blue = st.ObjectFrame.blue) then Inc(Result);
      end;
  end;

begin
  // the reasons of a refused move or copy, through the user's door
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
  AssertFalse('a copy into it', FRich.RunUser(TTyRichCopy.Create(0, 1, t.ParaStart(fixed) + 1)));
  AssertEquals('told once', 1, FRich.Refused);
  AssertEquals('its row', rsRichEditRefusedFixedRow, FRich.LastReason);
  LoadRtf(FRich, TableRtf(2));
  t := FRich.Document.Text;
  FRich.Refused := 0;
  AssertFalse('a move across cells', FRich.RunUser(TTyRichMove.Create(t.ParaStart(1) + 1, 6, 0)));
  AssertEquals('across cells: told once', 1, FRich.Refused);
  AssertEquals('across cells', rsRichEditRefusedCells, FRich.LastReason);
  FRich.Refused := 0;
  AssertFalse('a copy into its own range', FRich.RunUser(TTyRichCopy.Create(2, 6, 4)));
  AssertEquals('inside: told once', 1, FRich.Refused);
  AssertEquals('inside', rsRichEditRefusedRange, FRich.LastReason);
  // a triple press on the selection: the paragraph, no drag
  LoadText('one two three four'#13#10'next');
  Sel(4, 3);
  p := Mid(5);
  FRich.PressAt(p.X, p.Y);
  FRich.ReleaseAt(p.X, p.Y);
  FRich.PressAt(p.X, p.Y, [ssDouble]);
  FRich.ReleaseAt(p.X, p.Y);
  FRich.PressAt(p.X, p.Y);
  AssertFalse('a triple press: no drag', FRich.Pending);
  FRich.ReleaseAt(p.X, p.Y);
  AssertEquals('a triple press: the paragraph', Int64(0), FRich.SelStart);
  AssertTrue('a triple press: all of it', FRich.SelLength >= 18);
  // the mark after a scroll of the kept surface: no dot left where it was
  s := '';
  for i := 1 to 60 do s := s + 'Line number ' + IntToStr(i) + #13#10;
  LoadText(s);
  Sel(0, 4);
  p := Point(Mid(8).X, 150);
  StartDrag(Mid(1), p);
  PaintAll;
  AssertTrue('a mark', FRich.Mark(m));
  st := FRich.Style;
  FRich.Wheel(-120, [ssLeft]);
  PaintAll;
  AssertTrue('a mark after the scroll', FRich.Mark(m2));
  px := FRich.Surf.GetPixel(m2.Left, m2.Top);
  AssertTrue('the new mark drawn', (px.red = st.ObjectFrame.red) and (px.green = st.ObjectFrame.green) and
    (px.blue = st.ObjectFrame.blue));
  // no dot of the old mark left where the scroll moved the surface's pixels: as many dots as a
  // repaint of everything gives
  n1 := CountFrame;
  FRich.RedrawAll;
  PaintAll;
  AssertEquals('the dots after the scroll: those of a whole repaint', CountFrame, n1);
  FRich.Press(VK_ESCAPE, [ssLeft]);
  // a drop where a paragraph is too long to lay out: the paste's reason
  LoadText(StringOfChar('a', CRichMaxParaLayoutChars) + #13#10 + 'b');
  t := FRich.Document.Text;
  Sel(CRichMaxParaLayoutChars + 1, 1);
  PaintAll;
  p := Pt(CRichMaxParaLayoutChars);
  AssertEquals('the cut under the pointer', Int64(CRichMaxParaLayoutChars),
    FRich.PositionAtPoint(p.X, p.Y));
  FRich.Refused := 0;
  StartDrag(Mid(CRichMaxParaLayoutChars + 1), p);
  FRich.ReleaseAt(p.X, p.Y);
  AssertEquals('too long: told once', 1, FRich.Refused);
  AssertEquals('too long', rsRichEditRefusedLongPara, FRich.LastReason);
  AssertEquals('too long: nothing changed', Int64(CRichMaxParaLayoutChars), t.ParaLength(0));
  // the horizontal edge scrolling: a line wider than the view, nothing wrapped
  FRich.WrapMode := rwmNone;
  LoadText(StringOfChar('w', 400) + #13#10'second');
  Sel(0, 3);
  // first the mark across a horizontal scroll of the kept surface (its pixels moved aside)
  StartDrag(Mid(1), Point(150, Mid(1).Y));
  PaintAll;
  AssertTrue('a mark on the long line', FRich.Mark(m));
  FRich.WheelH(120);
  PaintAll;
  AssertTrue('scrolled aside', FRich.ScrollX > 0);
  n1 := CountFrame;
  FRich.RedrawAll;
  PaintAll;
  AssertEquals('the dots after the scroll aside: those of a whole repaint', CountFrame, n1);
  FRich.MoveWith(FRich.Area.Right - 1, Mid(1).Y, []);
  x0 := FRich.ScrollX;
  FRich.DragTick;
  AssertTrue('near the right edge: scrolled right', FRich.ScrollX > x0);
  FRich.MoveWith(FRich.Width + 30, Mid(1).Y, []);
  x0 := FRich.ScrollX;
  FRich.DragTick;
  AssertEquals('outside: no scroll', x0, FRich.ScrollX);
  FRich.Press(VK_ESCAPE, [ssLeft]);
  FRich.WrapMode := rwmWindow;
  // the left and the right Ctrl keys
  LoadText('one two three four');
  for k := 0 to 1 do
  begin
    Sel(4, 3);
    StartDrag(Mid(5), Pt(14));
    if k = 0 then
    begin
      FRich.Press(VK_LCONTROL, [ssCtrl, ssLeft]);
      AssertTrue('the left Ctrl: a copy', FRich.Effect = rdeCopy);
      FRich.KeyUpOf(VK_LCONTROL, [ssLeft]);
    end
    else
    begin
      FRich.Press(VK_RCONTROL, [ssCtrl, ssLeft]);
      AssertTrue('the right Ctrl: a copy', FRich.Effect = rdeCopy);
      FRich.KeyUpOf(VK_RCONTROL, [ssLeft]);
    end;
    AssertTrue('let go: a move', FRich.Effect = rdeMove);
    FRich.Press(VK_ESCAPE, [ssLeft]);
  end;
  // the form designer takes no drop
  r := NewProbe;
  try
    r.Lines.Text := 'abc';
    r.Designing;
    offer := TTestOffer.Create;
    try
      offer.Text := 'x';
      AssertTrue('in the designer: no drop', r.DropEnter(offer, 5, 5, []) = rdeNone);
      AssertFalse('in the designer: no session', r.DropActive);
    finally
      offer.Free;
    end;
  finally
    r.Free;
  end;
end;

{ A press on the selection takes the document in hand, as the first character typed does: a
  background replace or find ends at the press (cancelled, its one event), so its next turn
  changes nothing under the press; the move past the threshold drags, the drop is one step. A
  press whose wait something else ended (a change made by code, the selection set by code) is
  still the click it was at its release. }
procedure TTyRichDragTest.TestAPressOnTheSelectionEndsBackgroundWork;
var
  s: string;
  i, depth: Integer;
  p, pr: TPoint;
  q: TTyRichPos;
begin
  s := '';
  for i := 1 to 3000 do s := s + 'a cat sat here ' + IntToStr(i) + #13#10;
  FRich.OnFindDone := @FindDone;
  FRich.OnReplaceDone := @ReplaceDone;
  // a replace running: the press ends it, a turn changes nothing, the drag goes
  LoadText(s);
  FRich.SetFindSlice(1024);
  FRich.ReplaceAllAsync('cat', 'dog');
  FRich.Turn;
  FRich.Turn;
  AssertTrue('a replace running', FRich.FindRunning);
  depth := FRich.Document.UndoDepth;
  FFindEnds := nil;
  Sel(2, 3);
  pr := Mid(3);
  FRich.PressAt(pr.X, pr.Y);
  AssertTrue('the press waits', FRich.Pending);
  AssertFalse('the press: the replace ended', FRich.FindRunning);
  AssertEquals('the press: one event', 1, Length(FFindEnds));
  AssertEquals('the press: cancelled', 'replace cancelled', FFindEnds[0]);
  FRich.Turn;
  AssertTrue('a turn: the press still waits', FRich.Pending);
  FRich.MoveWith(pr.X, pr.Y + FRich.Threshold + 1, []);
  AssertTrue('past the threshold: the drag', FRich.OwnDrag);
  p := Pt(15);
  FRich.MoveWith(p.X, p.Y, []);
  FRich.ReleaseAt(p.X, p.Y);
  AssertEquals('dropped: one step on top', depth + 1, FRich.Document.UndoDepth);
  AssertEquals('dropped: a move', rsRichUndoMove, FRich.Document.UndoDescription);
  AssertEquals('still one event', 1, Length(FFindEnds));
  // a find whose needle a turn would reach
  LoadText('one two three four'#13#10'a needle here'#13#10);
  FRich.SetFindSlice(1024);
  Sel(4, 3);
  FFindEnds := nil;
  FRich.FindNextAsync('needle', []);
  AssertTrue('a find running', FRich.FindRunning);
  pr := Mid(5);
  FRich.PressAt(pr.X, pr.Y);
  AssertFalse('the press: the find ended', FRich.FindRunning);
  AssertEquals('the find: one event', 1, Length(FFindEnds));
  AssertEquals('the find: cancelled', 'find cancelled', FFindEnds[0]);
  FRich.Turn;
  AssertTrue('a turn: the press still waits', FRich.Pending);
  AssertEquals('the selection kept', Int64(4), FRich.SelStart);
  FRich.MoveWith(pr.X, pr.Y + FRich.Threshold + 1, []);
  AssertTrue('the find: the drag', FRich.OwnDrag);
  p := Pt(18);
  FRich.MoveWith(p.X, p.Y, []);
  FRich.ReleaseAt(p.X, p.Y);
  AssertEquals('the find: dropped', 'one  three fourtwo', Copy(AllText, 1, 18));
  // a press on the selection, its wait ended by a change of code: the click at the release
  LoadText('one two three four');
  Sel(4, 9);
  pr := Mid(6);
  q := FRich.PositionAtPoint(pr.X, pr.Y);
  FRich.PressAt(pr.X, pr.Y);
  AssertTrue('waiting', FRich.Pending);
  FRich.Document.Execute(TTyRichInsertText.Create(0, 'x'));
  AssertFalse('a change ends the wait', FRich.Pending);
  FRich.ReleaseAt(pr.X, pr.Y);
  AssertEquals('the click: nothing selected', Int64(0), FRich.SelLength);
  AssertEquals('the click: at the press''s place, after the change', q + 1, FRich.SelStart);
  // ended by the selection set by code
  LoadText('one two three four');
  Sel(4, 9);
  FRich.PressAt(pr.X, pr.Y);
  FRich.SelStart := 1;
  AssertFalse('the selection set: the wait ends', FRich.Pending);
  FRich.ReleaseAt(pr.X, pr.Y);
  AssertEquals('the click after it', q, FRich.SelStart);
  AssertEquals('the click: nothing selected', Int64(0), FRich.SelLength);
  // Esc while it waits: nothing at the release
  Sel(4, 9);
  FRich.PressAt(pr.X, pr.Y);
  FRich.Press(VK_ESCAPE, [ssLeft]);
  FRich.ReleaseAt(pr.X, pr.Y);
  AssertEquals('Esc: the selection stays', Int64(9), FRich.SelLength);
  FRich.OnFindDone := nil;
  FRich.OnReplaceDone := nil;
end;

{ The window paints deferred, over the kept surface its scrolls move: after a scroll of a line
  and a wheel notch during a drag, the mark's old dots are gone from where the surface's pixels
  went - the surface is what a repaint of everything gives. Long and short lines alternate, the
  pointer near a long line's end on a short line's row, so a line's scroll moves the place
  aside. }
procedure TTyRichDragTest.TestTheMarkLeavesNoDotWhenTheSurfaceScrolls;
var
  s: string;
  i, lineH, k: Integer;
  p: TPoint;
  r: TRect;
  t: TTyRichText;
  kept: TBGRABitmap;
  bmp: TBitmap;

  procedure PaintDeferred;
  begin
    FRich.PaintPart(bmp.Canvas, Rect(0, 0, FRich.Width, FRich.Height), True);
  end;

  procedure CheckLikeARepaint(const AWhat: string);
  var
    n, j: Integer;
    a, b: PBGRAPixel;
  begin
    PaintDeferred;
    kept := FRich.Surf.Duplicate as TBGRABitmap;
    try
      FRich.RedrawAll;
      PaintDeferred;
      AssertEquals(AWhat + ': the surface''s size', kept.Width * kept.Height,
        FRich.Surf.Width * FRich.Surf.Height);
      n := 0;
      a := kept.Data;
      b := FRich.Surf.Data;
      for j := 0 to kept.Width * kept.Height - 1 do
      begin
        if (a^.red <> b^.red) or (a^.green <> b^.green) or (a^.blue <> b^.blue) then Inc(n);
        Inc(a);
        Inc(b);
      end;
      AssertEquals(AWhat + ': pixels unlike a repaint of everything', 0, n);
    finally
      kept.Free;
    end;
  end;

begin
  s := '';
  for i := 1 to 40 do
    s := s + 'A long line number ' + IntToStr(i) + ' with some more words' + #13#10 + 'S' + #13#10;
  LoadText(s);
  t := FRich.Document.Text;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    PaintDeferred;
    lineH := FRich.PositionRect(t.ParaStart(1)).Top - FRich.PositionRect(0).Top;
    AssertTrue('a line''s height', lineH > 0);
    // a short line's row in the middle of the view, the x just left of a long line's end
    k := 9;
    r := FRich.PositionRect(t.ParaStart(k - 1) + t.ParaLength(k - 1));
    p := Point(r.Left - 3, (FRich.PositionRect(t.ParaStart(k)).Top +
      FRich.PositionRect(t.ParaStart(k)).Bottom) div 2);
    Sel(0, 6);
    StartDrag(Mid(1), p);
    PaintDeferred;
    AssertTrue('a mark at the short line''s end', FRich.Mark(r));
    FRich.ScrollY := FRich.ScrollY + lineH;
    CheckLikeARepaint('a line''s scroll');
    FRich.Wheel(-120, [ssLeft]);
    CheckLikeARepaint('a wheel notch');
    FRich.Press(VK_ESCAPE, [ssLeft]);
  finally
    bmp.Free;
  end;
end;

initialization
  RegisterTest(TTyRichDragTest);

end.
