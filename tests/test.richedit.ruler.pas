unit test.richedit.ruler;

{ TTyRichEditRuler: what it shows of the caret's paragraph and where (the markers over the text
  they place, to the pixel, at every zoom and PPI, scrolled, in each wrap mode, in a table
  cell), what a drag does (one command through the rich edit's paragraph format action, one
  undo step; the snap, the limits, Esc, a release without a move; tab stops added, moved and
  removed), when nothing may be dragged, the refusal told once, the link (freed, relinked,
  freed by its own handler during the ruler's command), the focus it never takes, the guide
  line the rich edit draws, the events, the theme, the scale's labels and what a caret move
  costs.

  Headless: the rich edit is the control suite's probe (the test device measures by rule),
  both controls on a form that is never shown; the ruler's mouse methods are driven directly,
  no window, no real input, no clipboard. Every bound is a count, never a time. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, TypInfo, fpcunit, testregistry, Controls, Graphics, LCLType,
  Forms, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.StyleModel, tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.StrConsts,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.Layout, tyControls.RichEdit.Attrs, tyControls.RichEdit,
  tyControls.RichEdit.Ruler, test.richedit.control, test.danglingrefs;

type
  { The ruler's protected parts, the focus it gives, the system's unit it is told. }
  TRulerProbe = class(TTyRichEditRuler)
  protected
    procedure FocusRichEdit; override;
    function SystemMeasureUnit: TTyRulerUnit; override;
    function LeftButtonHeld: Boolean; override;
  public
    Repaints, Focusings: Integer;
    SysUnit: TTyRulerUnit;
    HeldLeft: Boolean;
    { the system's own answer (SystemMeasureUnit not replaced) }
    RealUnit: Boolean;
    procedure Invalidate; override;
    procedure Press(X, Y: Integer; AShift: TShiftState = []);
    procedure MoveTo(X, Y: Integer; AShift: TShiftState = []);
    procedure Release(X, Y: Integer; AShift: TShiftState = []);
    procedure Key(AKey: Word);
    function Mid(AMarker: TTyRulerMarker; ATab: Integer = -1): TPoint;
    procedure MakeDesigning;
  end;

  { The rich edit's probe with what the ruler's tests read of it. }
  TRulerRich = class(TRichProbe)
  public
    function TextWindowRect: TRect;
  end;

  TTyRichEditRulerTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FRich: TRulerRich;
    FRuler: TRulerProbe;
    FChanges, FSelChanges, FRefusals, FChangings, FChangeds: Integer;
    FReason: string;
    FAllow: Boolean;
    FLastMarker: TTyRulerMarker;
    FLastTab, FLastOld, FLastNew: Integer;
    FFormatAtChanged: TTyParaFormat;
    procedure Changed(Sender: TObject);
    procedure SelChanged(Sender: TObject);
    procedure Refused(Sender: TObject; const AReason: string);
    procedure Changing(Sender: TObject; AMarker: TTyRulerMarker; ATab: Integer;
      AOldTwips, ANewTwips: Integer; var AAllow: Boolean);
    procedure MarkerChanged(Sender: TObject; AMarker: TTyRulerMarker; ATab: Integer;
      AOldTwips, ANewTwips: Integer);
    procedure FreeOnChange(Sender: TObject);
    procedure FreeRulerChanging(Sender: TObject; AMarker: TTyRulerMarker; ATab: Integer;
      AOldTwips, ANewTwips: Integer; var AAllow: Boolean);
    procedure FreeRulerChanged(Sender: TObject; AMarker: TTyRulerMarker; ATab: Integer;
      AOldTwips, ANewTwips: Integer);
    procedure FreeRulerOnChange(Sender: TObject);
    function NewRich(ALeft, ATop: Integer): TRulerRich;
    procedure SetText(const S: string);
    procedure SetPara(AIndex, ALeft, AFirst, ARight: Integer);
    procedure SetTabs(AIndex: Integer; const APositions: array of Integer);
    function Fmt(AIndex: Integer): TTyParaFormat;
    procedure CaretTo(APara: Integer; AOffset: Integer = 0);
    function CharX(APos: TTyRichPos): Integer;
    function Dx: Integer;
    { The text's width from the zero in twips, as the view gives it. }
    function WT: Integer;
    procedure Drag(AMarker: TTyRulerMarker; ADeltaX: Integer; ATab: Integer = -1;
      AShift: TShiftState = []);
    procedure LoadBytes(const B: TBytes);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // the plan's four
    procedure TestMarkersFollowTheCaretParagraph;
    procedure TestDraggingAMarkerIsOneUndoableCommand;
    procedure TestDoubleClickAddsATabAndDragOutRemovesIt;
    procedure TestFreeingTheRichEditClearsTheLink;
    // what is measured, and where
    procedure TestInACellTheZeroIsTheCellsTextEdge;
    procedure TestTheMarkersStandOverTheTextAtEveryZoomAndPPI;
    procedure TestAScrollMovesTheZero;
    procedure TestEachWrapMode;
    procedure TestRightToLeftKeepsTheZeroAtTheTextsLeft;
    procedure TestTheUnitAndItsLabels;
    procedure TestTheLabelsNeverOverlap;
    procedure TestTheHeightFollowsTheFont;
    // dragging
    procedure TestEveryMarkerAndItsOneProperty;
    procedure TestSeveralParagraphsSelected;
    procedure TestTheSnapAndAlt;
    procedure TestTheLimits;
    procedure TestTabStopsStaySortedAndApart;
    procedure TestEscEndsADragWithNothingChanged;
    procedure TestAReleaseWithoutAMoveRunsNothing;
    procedure TestACaptureTakenAwayEndsTheDrag;
    procedure TestNothingMayBeDraggedWhen;
    procedure TestAPlainTextControlIsFormattedAsTheFormatApiDoes;
    procedure TestAFieldsResultRefusesAndIsToldOnce;
    procedure TestARelinkDuringADragEndsIt;
    procedure TestTheControlFreedDuringTheRulersCommand;
    procedure TestNoFocusIsTaken;
    procedure TestTheGuideLineIsAskedAndWithdrawn;
    procedure TestTheEvents;
    // the look and the cost
    procedure TestTheThemeKeysResolveEverywhere;
    procedure TestACaretMoveCostsNoLayoutAndPaintsOnlyAChange;
    procedure TestTheRulerHearsWithoutTheApplicationsEvents;
    // after the review
    procedure TestAWholeParagraphSelectedIsTheOneShownAndDragged;
    procedure TestNothingMayBeDraggedWhereTheFormatIsRefused;
    procedure TestTheRulerFreedDuringItsOwnCommand;
    procedure TestAMovedStopsIndexIsItsIndexAfterTheMove;
    procedure TestADoubleClickOnAStopsPlaceAddsNone;
    procedure TestTheRightIndentLeavesRoomForAFirstLineRightOfTheOthers;
    procedure TestTheSystemsUnitIsTheLocales;
  end;

implementation

{$IFDEF MSWINDOWS}
// the locale query the test asks itself (not the ruler's own declaration)
function GetLocaleInfoW(ALocale, AType: LongWord; AData: PWideChar; ALen: LongInt): LongInt;
  stdcall; external 'kernel32.dll' name 'GetLocaleInfoW';
{$ENDIF}

const
  BS = #92;
  // where the rich edit sits on the form (the ruler at 0, 0)
  CEditLeft = 13;
  CEditTop = 60;

function RawBytes(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

function FileBytes(const APath: string): TBytes;
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

function FixtureFile(const AName: string): TBytes;
begin
  Result := FileBytes(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim +
    'fixtures' + PathDelim + 'rtf' + PathDelim + AName);
end;

{ ---- TRulerProbe ---- }

procedure TRulerProbe.FocusRichEdit;
begin
  Inc(Focusings);
  inherited FocusRichEdit;
end;

function TRulerProbe.SystemMeasureUnit: TTyRulerUnit;
begin
  if RealUnit then Result := inherited SystemMeasureUnit
  else Result := SysUnit;
end;

function TRulerProbe.LeftButtonHeld: Boolean;
begin
  Result := HeldLeft;
end;

procedure TRulerProbe.Invalidate;
begin
  Inc(Repaints);
  inherited Invalidate;
end;

procedure TRulerProbe.Press(X, Y: Integer; AShift: TShiftState);
begin
  MouseDown(mbLeft, AShift + [ssLeft], X, Y);
end;

procedure TRulerProbe.MoveTo(X, Y: Integer; AShift: TShiftState);
begin
  MouseMove(AShift + [ssLeft], X, Y);
end;

procedure TRulerProbe.Release(X, Y: Integer; AShift: TShiftState);
begin
  MouseUp(mbLeft, AShift, X, Y);
end;

procedure TRulerProbe.Key(AKey: Word);
var
  k: Word;
begin
  k := AKey;
  KeyWhileDragging(k, []);
end;

function TRulerProbe.Mid(AMarker: TTyRulerMarker; ATab: Integer): TPoint;
var
  r: TRect;
begin
  if not MarkerRect(AMarker, ATab, r) then raise Exception.Create('the marker is not shown');
  Result := Point(MarkerX(AMarker, ATab), (r.Top + r.Bottom) div 2);
end;

procedure TRulerProbe.MakeDesigning;
begin
  SetDesigning(True);
end;

function TRulerRich.TextWindowRect: TRect;
begin
  Result := inherited TextWindowRect;
end;

{ ---- the suite ---- }

procedure TTyRichEditRulerTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FRich := NewRich(CEditLeft, CEditTop);
  FRuler := TRulerProbe.Create(nil);
  FRuler.Controller := FCtl;
  FRuler.Font.PixelsPerInch := 96;
  FRuler.AutoSize := False;
  FRuler.Parent := FForm;
  FRuler.SetBounds(0, 0, 440, 40);
  FRuler.SysUnit := ruCentimeters;
  FRuler.OnMarkerChanging := @Changing;
  FRuler.OnMarkerChanged := @MarkerChanged;
  FAllow := True;
  SetText('Alpha beta gamma'#10'Second paragraph'#10'Third');
  FRuler.RichEdit := FRich;
  FChanges := 0;
  FSelChanges := 0;
  FRefusals := 0;
  FChangings := 0;
  FChangeds := 0;
  FReason := '';
end;

procedure TTyRichEditRulerTest.TearDown;
begin
  FreeAndNil(FRuler);
  FreeAndNil(FRich);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
end;

function TTyRichEditRulerTest.NewRich(ALeft, ATop: Integer): TRulerRich;
begin
  Result := TRulerRich.Create(nil);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.Parent := FForm;
  Result.SetBounds(ALeft, ATop, 400, 300);
  Result.OnChange := @Changed;
  Result.OnSelectionChange := @SelChanged;
  Result.OnEditRefused := @Refused;
  Result.ResetCounts;
end;

procedure TTyRichEditRulerTest.Changed(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TTyRichEditRulerTest.SelChanged(Sender: TObject);
begin
  Inc(FSelChanges);
end;

procedure TTyRichEditRulerTest.Refused(Sender: TObject; const AReason: string);
begin
  Inc(FRefusals);
  FReason := AReason;
end;

procedure TTyRichEditRulerTest.Changing(Sender: TObject; AMarker: TTyRulerMarker;
  ATab: Integer; AOldTwips, ANewTwips: Integer; var AAllow: Boolean);
begin
  Inc(FChangings);
  FLastMarker := AMarker;
  FLastTab := ATab;
  FLastOld := AOldTwips;
  FLastNew := ANewTwips;
  AAllow := FAllow;
end;

procedure TTyRichEditRulerTest.MarkerChanged(Sender: TObject; AMarker: TTyRulerMarker;
  ATab: Integer; AOldTwips, ANewTwips: Integer);
begin
  Inc(FChangeds);
  FLastMarker := AMarker;
  FLastTab := ATab;
  FLastOld := AOldTwips;
  FLastNew := ANewTwips;
  if FRich <> nil then FFormatAtChanged := Fmt(FRich.Document.Text.ParaOfPos(FRich.CaretIndex));
end;

procedure TTyRichEditRulerTest.FreeOnChange(Sender: TObject);
begin
  FRich := nil;
  Sender.Free;
end;

procedure TTyRichEditRulerTest.SetText(const S: string);
begin
  FRich.Lines.Text := S;
  FRich.UpdateView;
end;

procedure TTyRichEditRulerTest.SetPara(AIndex, ALeft, AFirst, ARight: Integer);
var
  f: TTyParaFormat;
begin
  f := TyDefaultParaFormat;
  f.LeftIndent := ALeft;
  f.FirstIndent := AFirst;
  f.RightIndent := ARight;
  FRich.Document.Execute(TTyRichSetParaFormat.Create(AIndex, AIndex,
    [pffLeftIndent, pffFirstIndent, pffRightIndent], f));
  FRich.UpdateView;
end;

procedure TTyRichEditRulerTest.SetTabs(AIndex: Integer; const APositions: array of Integer);
var
  f: TTyParaFormat;
  i: Integer;
begin
  f := TyDefaultParaFormat;
  SetLength(f.Tabs, Length(APositions));
  for i := 0 to High(APositions) do
  begin
    f.Tabs[i].Position := APositions[i];
    f.Tabs[i].Align := ttaLeft;
    f.Tabs[i].Leader := ttlNone;
  end;
  FRich.Document.Execute(TTyRichSetParaFormat.Create(AIndex, AIndex, [pffTabs], f));
  FRich.UpdateView;
end;

function TTyRichEditRulerTest.Fmt(AIndex: Integer): TTyParaFormat;
begin
  Result := FRich.Document.Formats.ParaFormat(FRich.Document.ParaFormatOf(AIndex));
end;

procedure TTyRichEditRulerTest.CaretTo(APara: Integer; AOffset: Integer);
begin
  FRich.SelStart := FRich.Document.Text.ParaStart(APara) + AOffset;
  FRich.UpdateView;
end;

function TTyRichEditRulerTest.CharX(APos: TTyRichPos): Integer;
begin
  Result := FRich.PositionRect(APos).Left;
end;

function TTyRichEditRulerTest.WT: Integer;
begin
  Result := Round(FRuler.View.TextWidthRaster * 1440.0 / (FRuler.View.PPI * FRuler.View.Zoom));
end;

function TTyRichEditRulerTest.Dx: Integer;
begin
  Result := FRich.ClientOrigin.X - FRuler.ClientOrigin.X;
end;

procedure TTyRichEditRulerTest.Drag(AMarker: TTyRulerMarker; ADeltaX: Integer; ATab: Integer;
  AShift: TShiftState);
var
  p: TPoint;
begin
  p := FRuler.Mid(AMarker, ATab);
  FRuler.Press(p.X, p.Y, AShift);
  FRuler.MoveTo(p.X + ADeltaX, p.Y, AShift);
  FRuler.Release(p.X + ADeltaX, p.Y, AShift);
end;

procedure TTyRichEditRulerTest.LoadBytes(const B: TBytes);
var
  st: TBytesStream;
begin
  st := TBytesStream.Create(B);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
end;

{ ---- the plan's four ---- }

{ The markers are the caret paragraph's, and follow the caret from paragraph to paragraph by
  themselves (the rich edit's notification): the first line's first character stands under
  the first-line marker, the second paragraph's tab stop over its tabbed text. }
procedure TTyRichEditRulerTest.TestMarkersFollowTheCaretParagraph;
var
  t: TTyRichText;
begin
  SetText('First paragraph'#10'b'#9'tabbed'#10'Third');
  SetPara(0, 567, 283, 0);
  SetPara(1, 1134, 0, 720);
  SetTabs(1, [2268]);
  t := FRich.Document.Text;
  CaretTo(0, 3);
  AssertTrue('a view', FRuler.HasView);
  AssertEquals('paragraph 0', 0, FRuler.View.Para);
  AssertEquals('the first line''s first character under the first-line marker',
    CharX(t.ParaStart(0)) + Dx, FRuler.MarkerX(rmkFirstIndent, -1));
  AssertEquals('no tab stop in paragraph 0', 0, Length(FRuler.ShownFormat.Tabs));
  // the caret moves: nothing is asked of the ruler, it hears
  FRich.SelStart := t.ParaStart(1) + 1;
  AssertEquals('paragraph 1', 1, FRuler.View.Para);
  AssertEquals('its first character', CharX(t.ParaStart(1)) + Dx,
    FRuler.MarkerX(rmkFirstIndent, -1));
  AssertEquals('its other lines (hanging) where its first line is',
    FRuler.MarkerX(rmkFirstIndent, -1), FRuler.MarkerX(rmkHangingIndent, -1));
  AssertEquals('its tab stop over the text after its tab', CharX(t.ParaStart(1) + 2) + Dx,
    FRuler.MarkerX(rmkTabStop, 0));
  AssertEquals('its right indent from where the text wraps',
    FRuler.SpanRight - TyRichTwipsToPx(720, 96, 1), FRuler.MarkerX(rmkRightIndent, -1));
  FRich.SelStart := t.ParaStart(2);
  AssertEquals('paragraph 2', 2, FRuler.View.Para);
  AssertEquals('at the zero', CharX(t.ParaStart(2)) + Dx, FRuler.MarkerX(rmkFirstIndent, -1));
  AssertEquals('the zero is the text area''s left edge', FRich.Area.Left + Dx, FRuler.SpanLeft);
end;

{ A drag of the first-line marker: while it runs nothing changes; the release is one command,
  one undo step named as the format API's, one OnChange; undone, the paragraph is as it was. }
procedure TTyRichEditRulerTest.TestDraggingAMarkerIsOneUndoableCommand;
var
  depth: Integer;
  p: TPoint;
begin
  CaretTo(0);
  depth := FRich.Document.UndoDepth;
  p := FRuler.Mid(rmkFirstIndent);
  FRuler.Press(p.X, p.Y);
  FRuler.MoveTo(p.X + 20, p.Y);
  FRuler.MoveTo(p.X + 40, p.Y);
  AssertTrue('dragging', FRuler.Dragging);
  AssertEquals('nothing changes while it runs', depth, FRich.Document.UndoDepth);
  AssertEquals('the format as it was', 0, Fmt(0).FirstIndent);
  AssertEquals('no OnChange yet', 0, FChanges);
  FRuler.Release(p.X + 40, p.Y);
  AssertFalse('the drag ended', FRuler.Dragging);
  AssertEquals('one undo step', depth + 1, FRich.Document.UndoDepth);
  AssertEquals('named as the format API''s step', rsRichUndoParaFormat,
    FRich.Document.UndoDescription);
  // 40 px at 96 PPI and 100 % are 600 twips: the nearest quarter centimetre is 567
  AssertEquals('the first line moved', 567, Fmt(0).LeftIndent + Fmt(0).FirstIndent);
  AssertEquals('its other lines stayed', 0, Fmt(0).LeftIndent);
  AssertEquals('one OnChange', 1, FChanges);
  AssertEquals('the ruler shows it', CharX(0) + Dx, FRuler.MarkerX(rmkFirstIndent, -1));
  FRich.Undo;
  AssertEquals('undone', 0, Fmt(0).LeftIndent + Fmt(0).FirstIndent);
  AssertEquals('the ruler shows the undo', CharX(0) + Dx, FRuler.MarkerX(rmkFirstIndent, -1));
end;

{ A double click on empty ruler space adds a left stop there (one step); dragged off the ruler
  - below it by more than its height - it goes (one step). }
procedure TTyRichEditRulerTest.TestDoubleClickAddsATabAndDragOutRemovesIt;
var
  depth, x, y: Integer;
  p: TPoint;
  f: TTyParaFormat;
begin
  CaretTo(0);
  depth := FRich.Document.UndoDepth;
  x := FRuler.XOfTwips(2835);
  y := (FRuler.StripTop + FRuler.StripBottom) div 2;
  FRuler.Press(x, y);
  FRuler.Release(x, y);
  AssertEquals('a single press adds nothing', 0, Length(Fmt(0).Tabs));
  FRuler.Press(x, y, [ssDouble]);
  FRuler.Release(x, y);
  f := Fmt(0);
  AssertEquals('one stop', 1, Length(f.Tabs));
  AssertEquals('at the snapped place (5 cm)', 2835, f.Tabs[0].Position);
  AssertTrue('a left stop', f.Tabs[0].Align = ttaLeft);
  AssertEquals('one step', depth + 1, FRich.Document.UndoDepth);
  AssertEquals('the ruler shows it', x, FRuler.MarkerX(rmkTabStop, 0));
  // a double click on the stop itself adds nothing
  p := FRuler.Mid(rmkTabStop, 0);
  FRuler.Press(p.X, p.Y, [ssDouble]);
  FRuler.Release(p.X, p.Y);
  AssertEquals('still one stop', 1, Length(Fmt(0).Tabs));
  // dragged along the ruler but not off it, then off it
  FRuler.Press(p.X, p.Y);
  FRuler.MoveTo(p.X, p.Y + FRuler.Height);
  AssertFalse('below by less than its height: still on', FRuler.DragOff);
  FRuler.MoveTo(p.X, p.Y + 3 * FRuler.Height);
  AssertTrue('off', FRuler.DragOff);
  FRuler.Release(p.X, p.Y + 3 * FRuler.Height);
  AssertEquals('gone', 0, Length(Fmt(0).Tabs));
  AssertEquals('one more step', depth + 2, FRich.Document.UndoDepth);
  // above it too
  SetTabs(0, [1440]);
  p := FRuler.Mid(rmkTabStop, 0);
  FRuler.Press(p.X, p.Y);
  FRuler.MoveTo(p.X, -2 * FRuler.Height);
  FRuler.Release(p.X, -2 * FRuler.Height);
  AssertEquals('dragged off above: gone', 0, Length(Fmt(0).Tabs));
end;

{ The rich edit freed: the ruler lets go of it and shows an empty scale. A ruler freed first:
  the rich edit no longer calls it. }
procedure TTyRichEditRulerTest.TestFreeingTheRichEditClearsTheLink;
var
  other: TRulerProbe;
  bmp: TBitmap;
begin
  CaretTo(0);
  AssertTrue('linked', FRuler.RichEdit = FRich);
  other := TRulerProbe.Create(nil);
  other.Parent := FForm;
  other.RichEdit := FRich;
  other.Free;
  // the rich edit changes: the freed ruler is not called
  FRich.Lines.Add('more');
  FRich.SelStart := 2;
  FreeAndNil(FRich);
  AssertTrue('the link cleared', FRuler.RichEdit = nil);
  AssertFalse('nothing to show', FRuler.HasView);
  AssertFalse('nothing to drag', FRuler.CanDrag);
  bmp := TBitmap.Create;
  try
    bmp.SetSize(FRuler.Width, FRuler.Height);
    FRuler.RenderTo(bmp.Canvas, Rect(0, 0, FRuler.Width, FRuler.Height), 96);
  finally
    bmp.Free;
  end;
  FRuler.Press(10, 10);
  FRuler.Release(10, 10);
  AssertFalse('no drag', FRuler.Dragging);
end;

{ ---- what is measured, and where ---- }

{ The caret in a table cell: the zero is the cell's text edge, the active span its text width;
  the ruler is dimmed outside it. }
procedure TTyRichEditRulerTest.TestInACellTheZeroIsTheCellsTextEdge;
var
  t: TTyRichText;
  p, i: Integer;
  ticks: TTyRulerTicks;
  inside, outside: Boolean;
begin
  SetText('Before the table');
  FRich.SelStart := 0;
  AssertTrue('a table', FRich.InsertTable(1, 3));
  FRich.UpdateView;
  t := FRich.Document.Text;
  // the second cell's paragraph
  p := -1;
  for i := 0 to t.ParaCount - 1 do
    if FRich.Document.CellAt(i) <> nil then
    begin
      if (p = -2) then begin p := i; Break; end;
      if p = -1 then p := -2;
    end;
  AssertTrue('a second cell', p >= 0);
  CaretTo(p);
  AssertTrue('a view', FRuler.HasView);
  AssertTrue('in a cell', FRuler.View.InCell);
  AssertEquals('the zero at the cell''s text', CharX(t.ParaStart(p)) + Dx, FRuler.SpanLeft);
  AssertEquals('the first-line marker there', CharX(t.ParaStart(p)) + Dx,
    FRuler.MarkerX(rmkFirstIndent, -1));
  AssertTrue('right of the text area''s edge (the second cell)',
    FRuler.SpanLeft > FRich.Area.Left + Dx + 20);
  AssertTrue('narrower than the text area',
    FRuler.SpanRight - FRuler.SpanLeft < (FRich.Area.Right - FRich.Area.Left) div 2);
  AssertTrue('the cell''s width', FRuler.SpanRight - FRuler.SpanLeft > 20);
  ticks := FRuler.TickMarks;
  inside := False;
  outside := False;
  for i := 0 to High(ticks) do
  begin
    if ticks[i].Dimmed then
    begin
      outside := True;
      AssertTrue('a dimmed tick is outside the cell',
        (ticks[i].X < FRuler.SpanLeft) or (ticks[i].X > FRuler.SpanRight));
    end
    else
    begin
      inside := True;
      AssertTrue('a plain tick is inside the cell',
        (ticks[i].X >= FRuler.SpanLeft) and (ticks[i].X <= FRuler.SpanRight));
    end;
  end;
  AssertTrue('ticks inside', inside);
  AssertTrue('ticks outside, dimmed', outside);
  // a drag stays inside the cell
  Drag(rmkFirstIndent, 1000);
  AssertTrue('inside the cell''s width',
    Fmt(p).LeftIndent + Fmt(p).FirstIndent <= FRuler.TwipsOfX(FRuler.SpanRight));
  AssertTrue('moved', Fmt(p).LeftIndent + Fmt(p).FirstIndent > 0);
  // back outside the table (the text that was there is after it): the text area's zero
  CaretTo(t.ParaCount - 1);
  AssertFalse('not in a cell', FRuler.View.InCell);
  AssertEquals('the text area''s zero', FRich.Area.Left + Dx, FRuler.SpanLeft);
end;

{ At zoom 50, 100 and 200 and PPI 96, 144 and 192 the first line's first character stands under
  the first-line marker, the other lines' under the hanging marker and the text after a tab under
  its stop - to the pixel: the ruler places them with the rich edit's own conversion. }
procedure TTyRichEditRulerTest.TestTheMarkersStandOverTheTextAtEveryZoomAndPPI;
const
  CZooms: array[0..2] of Integer = (50, 100, 200);
  CPPIs: array[0..2] of Integer = (96, 144, 192);
var
  z, q: Integer;
  t: TTyRichText;
  who: string;
begin
  SetText('Indented first line'#10'Hanging'#10'x'#9'y');
  SetPara(0, 567, 397, 0);
  SetPara(1, 851, 0, 0);
  SetTabs(2, [1134]);
  t := FRich.Document.Text;
  for z := 0 to High(CZooms) do
    for q := 0 to High(CPPIs) do
    begin
      who := Format('zoom %d, %d PPI', [CZooms[z], CPPIs[q]]);
      FRich.Font.PixelsPerInch := CPPIs[q];
      FRich.Zoom := CZooms[z];
      FRich.UpdateView;
      CaretTo(0, 1);
      AssertTrue(who + ': a view', FRuler.HasView);
      AssertEquals(who + ': the first line', CharX(t.ParaStart(0)) + Dx,
        FRuler.MarkerX(rmkFirstIndent, -1));
      CaretTo(1, 1);
      AssertEquals(who + ': the other lines', CharX(t.ParaStart(1)) + Dx,
        FRuler.MarkerX(rmkHangingIndent, -1));
      CaretTo(2, 0);
      AssertEquals(who + ': the stop', CharX(t.ParaStart(2) + 2) + Dx,
        FRuler.MarkerX(rmkTabStop, 0));
      AssertTrue(who + ': a centimetre on the scale is the rich edit''s',
        Abs(TyRichTwipsToPx(567, CPPIs[q], CZooms[z] / 100) -
        (FRuler.XOfTwips(567) - FRuler.XOfTwips(0))) <= 1);
    end;
end;

{ Scrolled across (no wrap, a long line, the caret at its end): the zero moves with the text. }
procedure TTyRichEditRulerTest.TestAScrollMovesTheZero;
var
  s: string;
  zero: Integer;
begin
  s := StringOfChar('x', 300);
  SetText(s + #10'short');
  FRich.WrapMode := rwmNone;
  FRich.UpdateView;
  SetPara(0, 567, 0, 0);
  CaretTo(0);
  zero := FRuler.SpanLeft;
  FRich.SelStart := Length(s);
  FRich.UpdateView;
  AssertTrue('scrolled', FRich.ScrollX > 0);
  AssertEquals('the zero moved with the text', zero - FRich.ScrollX, FRuler.SpanLeft);
  AssertEquals('the marker over the first character', CharX(0) + Dx,
    FRuler.MarkerX(rmkFirstIndent, -1));
end;

{ rwmWindow: the text wraps at the text area's width; rwmPage at the page's text width; rwmNone
  does not wrap - no right indent marker, the span to the text area's right edge. }
procedure TTyRichEditRulerTest.TestEachWrapMode;
var
  a: TRect;
  r: TRect;
begin
  CaretTo(0);
  a := FRich.Area;
  AssertEquals('window: from the text area''s left', a.Left + Dx, FRuler.SpanLeft);
  AssertEquals('window: to its right', a.Right + Dx, FRuler.SpanRight);
  AssertTrue('window: a right indent marker', FRuler.MarkerRect(rmkRightIndent, -1, r));
  AssertEquals('window: at the right edge', a.Right + Dx, FRuler.MarkerX(rmkRightIndent, -1));
  FRich.WrapMode := rwmPage;
  FRich.UpdateView;
  AssertEquals('page: the page''s text width',
    TyRichTwipsToPx(FRich.Document.TextWidthTwips, 96, 1), FRuler.SpanRight - FRuler.SpanLeft);
  AssertTrue('page: a right indent marker', FRuler.MarkerRect(rmkRightIndent, -1, r));
  FRich.WrapMode := rwmNone;
  FRich.UpdateView;
  AssertFalse('none: no right indent marker', FRuler.MarkerRect(rmkRightIndent, -1, r));
  AssertEquals('none: the span to the text area''s right edge', FRich.Area.Right + Dx,
    FRuler.SpanRight);
end;

{ A right-to-left rich edit keeps its text left to right (its scroll bar on the left): the ruler
  agrees with the screen - its zero at the text's left edge, nothing mirrored. }
procedure TTyRichEditRulerTest.TestRightToLeftKeepsTheZeroAtTheTextsLeft;
var
  sl: TStringList;
  i: Integer;
begin
  sl := TStringList.Create;
  try
    for i := 0 to 99 do sl.Add('Line ' + IntToStr(i));
    FRich.Lines.Assign(sl);
  finally
    sl.Free;
  end;
  FRich.BiDiMode := bdRightToLeft;
  FRich.UpdateView;
  SetPara(0, 567, 0, 0);
  CaretTo(0);
  AssertTrue('the bar on the left moved the text area', FRich.Area.Left > 10);
  AssertEquals('the zero at the text''s left edge', FRich.Area.Left + Dx, FRuler.SpanLeft);
  AssertEquals('over the first character', CharX(0) + Dx, FRuler.MarkerX(rmkFirstIndent, -1));
  AssertTrue('not mirrored', FRuler.SpanLeft < FRuler.SpanRight);
end;

{ ruAuto asks the system (here the probe's answer); centimetres and inches as set. }
procedure TTyRichEditRulerTest.TestTheUnitAndItsLabels;

  function LabelAt(AText: string): Integer;
  var
    ticks: TTyRulerTicks;
    i: Integer;
  begin
    Result := -1;
    ticks := FRuler.TickMarks;
    for i := 0 to High(ticks) do
      if ticks[i].Text = AText then Exit(ticks[i].X);
  end;

begin
  CaretTo(0);
  FRuler.SysUnit := ruInches;
  FRuler.MeasureUnit := ruAuto;
  AssertTrue('auto: the system''s inches', FRuler.EffectiveUnit = ruInches);
  AssertEquals('1 at an inch', FRuler.XOfTwips(1440), LabelAt('1'));
  FRuler.SysUnit := ruCentimeters;
  AssertTrue('auto: the system''s centimetres', FRuler.EffectiveUnit = ruCentimeters);
  AssertEquals('1 at a centimetre', FRuler.XOfTwips(567), LabelAt('1'));
  FRuler.MeasureUnit := ruInches;
  AssertEquals('inches as set', FRuler.XOfTwips(1440), LabelAt('1'));
  FRuler.MeasureUnit := ruCentimeters;
  FRuler.SysUnit := ruInches;
  AssertEquals('centimetres as set', FRuler.XOfTwips(567), LabelAt('1'));
  AssertEquals('MeasureUnit''s default', Ord(ruAuto),
    GetPropInfo(TTyRichEditRuler, 'MeasureUnit')^.Default);
end;

{ However the zoom changes the scale, two labels never overlap (and there are always some). }
procedure TTyRichEditRulerTest.TestTheLabelsNeverOverlap;
const
  CZooms: array[0..9] of Integer = (10, 25, 33, 50, 75, 100, 150, 200, 300, 500);
var
  z, u, i, last, labels: Integer;
  ticks: TTyRulerTicks;
  who: string;
begin
  CaretTo(0);
  for u := 0 to 1 do
    for z := 0 to High(CZooms) do
    begin
      if u = 0 then FRuler.MeasureUnit := ruCentimeters else FRuler.MeasureUnit := ruInches;
      FRich.Zoom := CZooms[z];
      FRich.UpdateView;
      who := Format('unit %d, zoom %d', [u, CZooms[z]]);
      ticks := FRuler.TickMarks;
      last := -MaxInt;
      labels := 0;
      for i := 0 to High(ticks) do
        if ticks[i].Text <> '' then
        begin
          Inc(labels);
          AssertTrue(who + ': apart', ticks[i].LabelRect.Left >= last);
          last := ticks[i].LabelRect.Right;
        end;
      // (a whole unit inside the ruler has its label)
      if FRuler.XOfTwips(Round(2 * FRuler.UnitTwips)) < FRuler.Width then
        AssertTrue(who + ': labels', labels > 0);
    end;
end;

{ A new ruler is as tall as its font asks; the height asked follows the font and the PPI
  (AutoSize keeps it so). }
procedure TTyRichEditRulerTest.TestTheHeightFollowsTheFont;
var
  w, h96, h192, hBig: Integer;
  r: TTyRichEditRuler;
begin
  r := TTyRichEditRuler.Create(nil);
  try
    AssertFalse('AutoSize off by default', r.AutoSize);
    AssertEquals('AutoSize''s declared default', 0, GetPropInfo(TTyRichEditRuler, 'AutoSize')^.Default);
    r.Controller := FCtl;
    r.Font.PixelsPerInch := 96;
    w := 0;
    h96 := 0;
    r.GetPreferredSize(w, h96);
    AssertEquals('a new ruler as tall as its font asks', h96, r.Height);
    r.Font.PixelsPerInch := 192;
    h192 := 0;
    // (LCL keeps a preferred size until it is told it changed)
    r.InvalidatePreferredSize;
    r.GetPreferredSize(w, h192);
    AssertTrue('a height', h96 > 10);
    // (the DPI guard's tolerance: a pixel's rounding per part, not a font's worth)
    AssertTrue(Format('twice at twice the PPI (%d, %d)', [h96, h192]),
      Abs(h192 - 2 * h96) <= Max(4, h96 div 5));
    r.Font.PixelsPerInch := 96;
    r.Font.Size := 24;
    hBig := 0;
    r.InvalidatePreferredSize;
    r.GetPreferredSize(w, hBig);
    AssertTrue('a larger font, a taller ruler', hBig > h96);
  finally
    r.Free;
  end;
end;

{ ---- dragging ---- }

{ Each marker gives its one property: the first-line marker the first line (the other lines
  stay), the hanging marker the other lines (the first line stays), the box both (the offset
  kept), the right marker the right indent. }
procedure TTyRichEditRulerTest.TestEveryMarkerAndItsOneProperty;
var
  f: TTyParaFormat;
  depth, x0, ri: Integer;
begin
  SetPara(0, 1134, 567, 567);
  CaretTo(0);
  depth := FRich.Document.UndoDepth;
  Drag(rmkHangingIndent, 40);
  f := Fmt(0);
  AssertEquals('hanging: the other lines', 1701, f.LeftIndent);
  AssertEquals('hanging: the first line stayed', 1701, f.LeftIndent + f.FirstIndent);
  Drag(rmkFirstIndent, -40);
  f := Fmt(0);
  AssertEquals('first: the first line', 1134, f.LeftIndent + f.FirstIndent);
  AssertEquals('first: the other lines stayed', 1701, f.LeftIndent);
  Drag(rmkLeftIndent, 40);
  f := Fmt(0);
  AssertEquals('box: the other lines', 2268, f.LeftIndent);
  AssertEquals('box: the offset kept', -567, f.FirstIndent);
  // the right marker's place snaps; the indent is the text's width less it
  x0 := FRuler.MarkerX(rmkRightIndent, -1);
  ri := WT - FRuler.Snap(FRuler.TwipsOfX(x0 - 40), []);
  Drag(rmkRightIndent, -40);
  f := Fmt(0);
  AssertEquals('right', ri, f.RightIndent);
  AssertTrue('right: moved', ri > 567);
  AssertTrue('right: the marker at its new place',
    Abs(FRuler.XOfTwips(WT - ri) - FRuler.MarkerX(rmkRightIndent, -1)) <= 1);
  AssertEquals('four steps', depth + 4, FRich.Document.UndoDepth);
end;

{ Several paragraphs selected: the markers are the caret paragraph's; the drag gives its one
  property to every paragraph the selection touches, each keeping the rest of its own. }
procedure TTyRichEditRulerTest.TestSeveralParagraphsSelected;
var
  t: TTyRichText;
  depth, i: Integer;
  first: array[0..2] of Integer;
begin
  SetPara(0, 0, 0, 0);
  SetPara(1, 567, 567, 0);
  SetPara(2, 1134, -567, 0);
  t := FRich.Document.Text;
  FRich.SelStart := 1;
  FRich.SelLength := t.ParaStart(2) + 2 - 1;
  FRich.UpdateView;
  AssertEquals('the first paragraph''s markers (where the change begins)', 0, FRuler.View.Para);
  AssertEquals('its hanging indent', CharX(t.ParaStart(0)) + Dx,
    FRuler.MarkerX(rmkHangingIndent, -1));
  for i := 0 to 2 do first[i] := Fmt(i).LeftIndent + Fmt(i).FirstIndent;
  depth := FRich.Document.UndoDepth;
  Drag(rmkHangingIndent, 40);
  AssertEquals('one step', depth + 1, FRich.Document.UndoDepth);
  for i := 0 to 2 do
  begin
    AssertEquals(Format('paragraph %d: the other lines', [i]), 567, Fmt(i).LeftIndent);
    AssertEquals(Format('paragraph %d: its first line stayed', [i]), first[i],
      Fmt(i).LeftIndent + Fmt(i).FirstIndent);
  end;
  AssertEquals('the selection kept', 1, FRich.SelStart);
end;

{ The drag snaps to a quarter of the unit; with Alt held it does not. }
procedure TTyRichEditRulerTest.TestTheSnapAndAlt;
begin
  CaretTo(0);
  FRuler.MeasureUnit := ruInches;
  AssertEquals('inches: a quarter inch', 360, FRuler.Snap(500, []));
  AssertEquals('Alt: none', 500, FRuler.Snap(500, [ssAlt]));
  FRuler.MeasureUnit := ruCentimeters;
  AssertEquals('centimetres: a quarter centimetre', 142, FRuler.Snap(200, []));
  FRuler.MeasureUnit := ruInches;
  Drag(rmkFirstIndent, 20);
  AssertEquals('20 px (300 twips) snapped to 360', 360, Fmt(0).LeftIndent + Fmt(0).FirstIndent);
  SetPara(0, 0, 0, 0);
  Drag(rmkFirstIndent, 20, -1, [ssAlt]);
  AssertEquals('with Alt: 300 exactly', 300, Fmt(0).LeftIndent + Fmt(0).FirstIndent);
end;

{ The drag stays inside the text, CTyRulerMinTextTwips of it left between the indents. }
procedure TTyRichEditRulerTest.TestTheLimits;
var
  w: Integer;
begin
  CaretTo(0);
  w := WT;
  Drag(rmkFirstIndent, 5000);
  AssertEquals('first: at most the width less the room', w - CTyRulerMinTextTwips,
    Fmt(0).LeftIndent + Fmt(0).FirstIndent);
  Drag(rmkFirstIndent, -5000);
  AssertEquals('first: not left of the zero', 0, Fmt(0).LeftIndent + Fmt(0).FirstIndent);
  SetPara(0, 1000, 0, 0);
  Drag(rmkRightIndent, -5000);
  AssertEquals('right: the room kept right of the indents', w - 1000 - CTyRulerMinTextTwips,
    Fmt(0).RightIndent);
  Drag(rmkHangingIndent, 5000);
  AssertEquals('hanging: short of the right indent', w - Fmt(0).RightIndent - CTyRulerMinTextTwips,
    Fmt(0).LeftIndent);
  SetPara(0, 0, 0, 0);
  SetTabs(0, [100]);
  Drag(rmkTabStop, 5000, 0);
  AssertEquals('a stop: at most the width', w, Fmt(0).Tabs[0].Position);
end;

{ Moved, the stops stay sorted and two never end at one place; at most CTyMaxTabStops. }
procedure TTyRichEditRulerTest.TestTabStopsStaySortedAndApart;
var
  i, depth, x, y: Integer;
  pos: array of Integer;
  f: TTyParaFormat;
begin
  CaretTo(0);
  FRuler.MeasureUnit := ruInches;
  SetTabs(0, [1440, 2880, 4320]);
  // the third stop dragged left of the first (an inch is 96 px here)
  Drag(rmkTabStop, -96 * 3 + 0, 2);
  f := Fmt(0);
  AssertEquals('three stops', 3, Length(f.Tabs));
  AssertEquals('sorted 1', 0, f.Tabs[0].Position);
  AssertEquals('sorted 2', 1440, f.Tabs[1].Position);
  AssertEquals('sorted 3', 2880, f.Tabs[2].Position);
  // the first dragged onto the second: it takes the place, one stop there
  Drag(rmkTabStop, 96, 0);
  f := Fmt(0);
  AssertEquals('two stops', 2, Length(f.Tabs));
  AssertEquals('one at 1440', 1440, f.Tabs[0].Position);
  AssertEquals('one at 2880', 2880, f.Tabs[1].Position);
  // the most stops: no more are added
  SetLength(pos, CTyMaxTabStops);
  for i := 0 to High(pos) do pos[i] := 90 * (i + 1);
  SetTabs(0, pos);
  depth := FRich.Document.UndoDepth;
  x := FRuler.XOfTwips(5760);
  y := (FRuler.StripTop + FRuler.StripBottom) div 2;
  FRuler.Press(x, y, [ssDouble]);
  FRuler.Release(x, y);
  AssertEquals('still the most', CTyMaxTabStops, Length(Fmt(0).Tabs));
  AssertEquals('no step', depth, FRich.Document.UndoDepth);
end;

{ Esc ends a drag with nothing changed, its guide line withdrawn; the release does nothing. }
procedure TTyRichEditRulerTest.TestEscEndsADragWithNothingChanged;
var
  depth: Integer;
  p: TPoint;
begin
  CaretTo(0);
  depth := FRich.Document.UndoDepth;
  p := FRuler.Mid(rmkFirstIndent);
  FRuler.Press(p.X, p.Y);
  FRuler.MoveTo(p.X + 40, p.Y);
  AssertTrue('a guide line', FRich.GuideLine >= 0);
  FRuler.Key(VK_ESCAPE);
  AssertFalse('ended', FRuler.Dragging);
  AssertEquals('the guide line withdrawn', -1, FRich.GuideLine);
  FRuler.Release(p.X + 40, p.Y);
  AssertEquals('nothing changed', depth, FRich.Document.UndoDepth);
  AssertEquals('the format as it was', 0, Fmt(0).LeftIndent + Fmt(0).FirstIndent);
  AssertEquals('the marker where it was', CharX(0) + Dx, FRuler.MarkerX(rmkFirstIndent, -1));
  AssertEquals('no change told', 0, FChangings);
end;

{ A release where nothing moved runs nothing: a press and release, and a move that snaps back
  to the same place. }
procedure TTyRichEditRulerTest.TestAReleaseWithoutAMoveRunsNothing;
var
  depth: Integer;
  p: TPoint;
begin
  CaretTo(0);
  depth := FRich.Document.UndoDepth;
  p := FRuler.Mid(rmkFirstIndent);
  FRuler.Press(p.X, p.Y);
  FRuler.Release(p.X, p.Y);
  Drag(rmkFirstIndent, 2);
  AssertEquals('no step', depth, FRich.Document.UndoDepth);
  AssertEquals('no OnChange', 0, FChanges);
  AssertEquals('no change told', 0, FChangings);
end;

{ The capture taken away while the button is held ends the drag with nothing changed; the one
  a release lets go of does not. }
procedure TTyRichEditRulerTest.TestACaptureTakenAwayEndsTheDrag;
var
  depth: Integer;
  p: TPoint;
begin
  CaretTo(0);
  depth := FRich.Document.UndoDepth;
  p := FRuler.Mid(rmkFirstIndent);
  FRuler.Press(p.X, p.Y);
  FRuler.MoveTo(p.X + 40, p.Y);
  FRuler.HeldLeft := True;
  FRuler.CaptureChanged;
  AssertFalse('ended', FRuler.Dragging);
  FRuler.Release(p.X + 40, p.Y);
  AssertEquals('nothing changed', depth, FRich.Document.UndoDepth);
  FRuler.HeldLeft := False;
  FRuler.Press(p.X, p.Y);
  FRuler.MoveTo(p.X + 40, p.Y);
  FRuler.CaptureChanged;
  AssertTrue('the release''s own: still dragging', FRuler.Dragging);
  FRuler.Release(p.X + 40, p.Y);
  AssertEquals('applied', depth + 1, FRich.Document.UndoDepth);
end;

{ ReadOnly, disabled, loading, in the designer, no rich edit: the markers show and do not move. }
procedure TTyRichEditRulerTest.TestNothingMayBeDraggedWhen;
var
  depth: Integer;
  r: TRect;
  s: RawByteString;
  i: Integer;

  procedure Attempt(const AWhy: string);
  var
    p: TPoint;
  begin
    AssertTrue(AWhy + ': the marker shows', FRuler.MarkerRect(rmkFirstIndent, -1, r));
    AssertFalse(AWhy + ': nothing may be dragged', FRuler.CanDrag);
    p := FRuler.Mid(rmkFirstIndent);
    FRuler.Press(p.X, p.Y);
    FRuler.MoveTo(p.X + 40, p.Y);
    AssertFalse(AWhy + ': no drag', FRuler.Dragging);
    FRuler.Release(p.X + 40, p.Y);
    FRuler.Press(p.X + 80, p.Y, [ssDouble]);
    FRuler.Release(p.X + 80, p.Y);
    AssertEquals(AWhy + ': nothing changed', depth, FRich.Document.UndoDepth);
    AssertEquals(AWhy + ': no guide line', -1, FRich.GuideLine);
  end;

begin
  CaretTo(0);
  depth := FRich.Document.UndoDepth;
  AssertTrue('may be dragged', FRuler.CanDrag);
  FRich.ReadOnly := True;
  Attempt('read-only');
  FRich.ReadOnly := False;
  AssertTrue('again', FRuler.CanDrag);
  FRich.Enabled := False;
  Attempt('disabled');
  FRich.Enabled := True;
  FRuler.Enabled := False;
  AssertFalse('the ruler disabled', FRuler.CanDrag);
  FRuler.Enabled := True;
  AssertTrue('again', FRuler.CanDrag);
  // loading: a file read in slices, the load not finished
  s := '{' + BS + 'rtf1' + BS + 'ansi{' + BS + 'fonttbl{' + BS + 'f0 Arial;}}'#13#10;
  for i := 0 to 3000 do
    s := s + BS + 'pard' + BS + 'f0 Paragraph ' + IntToStr(i) + ' of the file.' + BS + 'par'#13#10;
  s := s + '}';
  FRich.Slices(4096, 4096);
  LoadBytes(RawBytes(s));
  FRich.UpdateView;
  AssertTrue('loading', FRich.Loading);
  FRuler.CheckView;
  depth := FRich.Document.UndoDepth;
  Attempt('loading');
  FRich.FinishLoading;
  FRich.UpdateView;
  FRuler.CheckView;
  AssertTrue('loaded: may be dragged', FRuler.CanDrag);
  depth := FRich.Document.UndoDepth;
  FRuler.MakeDesigning;
  Attempt('in the designer');
  // no rich edit linked: nothing shows
  FRuler.RichEdit := nil;
  AssertFalse('no rich edit: no marker', FRuler.MarkerRect(rmkFirstIndent, -1, r));
  AssertFalse('no rich edit: nothing may be dragged', FRuler.CanDrag);
end;

{ PlainText: the format API formats the paragraphs (a text save leaves them out), and so does
  the ruler. }
procedure TTyRichEditRulerTest.TestAPlainTextControlIsFormattedAsTheFormatApiDoes;
begin
  FRich.PlainText := True;
  CaretTo(0);
  AssertTrue('may be dragged', FRuler.CanDrag);
  Drag(rmkFirstIndent, 40);
  AssertEquals('formatted', 567, Fmt(0).LeftIndent + Fmt(0).FirstIndent);
end;

{ The caret in a table of contents (a paragraph that ends inside a field's result): the rich
  edit would refuse the paragraph format there (CanFormatParagraphs), so the markers show
  disabled and a drag does nothing - nothing asked, nothing told, no step. }
procedure TTyRichEditRulerTest.TestAFieldsResultRefusesAndIsToldOnce;
var
  p, i, depth: Integer;
  before: TTyParaFormat;
begin
  LoadBytes(FixtureFile('word-toc.rtf'));
  FRich.FinishLoading;
  FRich.UpdateView;
  p := -1;
  for i := 0 to FRich.Document.Text.ParaCount - 1 do
    if FRich.Document.ParaEndsInField(i) then
    begin
      p := i;
      Break;
    end;
  AssertTrue('a paragraph of the contents', p >= 0);
  CaretTo(p, 1);
  FRuler.CheckView;
  AssertFalse('not draggable: the rich edit would refuse it', FRuler.CanDrag);
  before := Fmt(p);
  depth := FRich.Document.UndoDepth;
  FRefusals := 0;
  Drag(rmkFirstIndent, 40);
  AssertEquals('nothing told', 0, FRefusals);
  AssertEquals('no step', depth, FRich.Document.UndoDepth);
  AssertTrue('the format as it was', before.Equals(Fmt(p)));
  AssertEquals('nothing asked', 0, FChangings);
  AssertEquals('not told as done', 0, FChangeds);
  AssertEquals('the marker where it was', CharX(FRich.Document.Text.ParaStart(p)) + Dx,
    FRuler.MarkerX(rmkFirstIndent, -1));
end;

{ Relinked or unlinked during a drag: the drag ends with nothing changed, the old rich edit's
  guide line withdrawn. }
procedure TTyRichEditRulerTest.TestARelinkDuringADragEndsIt;
var
  other: TRulerRich;
  depth: Integer;
  p: TPoint;
begin
  CaretTo(0);
  other := NewRich(CEditLeft, CEditTop + 320);
  try
    other.Lines.Text := 'Other';
    other.UpdateView;
    depth := FRich.Document.UndoDepth;
    p := FRuler.Mid(rmkFirstIndent);
    FRuler.Press(p.X, p.Y);
    FRuler.MoveTo(p.X + 40, p.Y);
    AssertTrue('a guide line', FRich.GuideLine >= 0);
    FRuler.RichEdit := other;
    AssertFalse('the drag ended', FRuler.Dragging);
    AssertEquals('the old guide line withdrawn', -1, FRich.GuideLine);
    FRuler.MoveTo(p.X + 80, p.Y);
    FRuler.Release(p.X + 80, p.Y);
    AssertEquals('nothing changed there', depth, FRich.Document.UndoDepth);
    AssertEquals('nothing changed here', 0, other.Document.UndoDepth);
    AssertEquals('no guide line on the new one', -1, other.GuideLine);
    // unlinked the same way
    FRuler.Press(p.X, p.Y);
    FRuler.MoveTo(p.X + 40, p.Y);
    AssertTrue('dragging on the new one', FRuler.Dragging);
    FRuler.RichEdit := nil;
    AssertFalse('the drag ended', FRuler.Dragging);
    AssertEquals('its guide line withdrawn', -1, other.GuideLine);
    FRuler.Release(p.X + 40, p.Y);
    AssertEquals('nothing changed', 0, other.Document.UndoDepth);
  finally
    FRuler.RichEdit := nil;
    other.Free;
  end;
end;

{ The rich edit's OnChange frees it during the ruler's command: the ruler lets go of it, nothing
  of it is touched, the after-event does not come. }
procedure TTyRichEditRulerTest.TestTheControlFreedDuringTheRulersCommand;
var
  p: TPoint;
begin
  CaretTo(0);
  FRich.OnChange := @FreeOnChange;
  p := FRuler.Mid(rmkFirstIndent);
  FRuler.Press(p.X, p.Y);
  FRuler.MoveTo(p.X + 40, p.Y);
  FRuler.Release(p.X + 40, p.Y);
  AssertTrue('the rich edit went', FRich = nil);
  AssertTrue('the link cleared', FRuler.RichEdit = nil);
  AssertFalse('no drag', FRuler.Dragging);
  AssertEquals('asked before', 1, FChangings);
  AssertEquals('not told after: the control is gone', 0, FChangeds);
end;

{ The ruler never takes the focus; after a drag the rich edit is where the keys go. }
procedure TTyRichEditRulerTest.TestNoFocusIsTaken;
var
  pi: PPropInfo;
begin
  AssertFalse('no focus', FRuler.CanFocus);
  AssertFalse('no tab stop', FRuler.TabStop);
  pi := GetPropInfo(TTyRichEditRuler, 'TabStop');
  AssertTrue('TabStop published', pi <> nil);
  AssertEquals('declared False', 0, pi^.Default);
  FRuler.TabStop := True;
  AssertFalse('TabStop has no effect', FRuler.CanFocus);
  CaretTo(0);
  FRuler.Focusings := 0;
  Drag(rmkFirstIndent, 40);
  AssertEquals('the rich edit given the keys after the drag', 1, FRuler.Focusings);
  Drag(rmkFirstIndent, 0);
  AssertEquals('after a drag that changed nothing too', 2, FRuler.Focusings);
end;

{ While a drag runs the rich edit shows a line through its text at the marker's place (asked
  through GuideLine, painted again where it was and where it goes); the release withdraws it,
  and so does a stop dragged off the ruler. }
procedure TTyRichEditRulerTest.TestTheGuideLineIsAskedAndWithdrawn;
var
  p: TPoint;
  tw: TRect;
  x: Integer;

  function Asked(AX: Integer): Boolean;
  var
    k: Integer;
  begin
    Result := False;
    for k := 0 to High(FRich.Invalidated) do
      if (FRich.Invalidated[k].Left = AX) and (FRich.Invalidated[k].Right > AX) and
        (FRich.Invalidated[k].Top = tw.Top) and (FRich.Invalidated[k].Bottom = tw.Bottom) then
        Exit(True);
  end;

begin
  CaretTo(0);
  tw := FRich.TextWindowRect;
  AssertEquals('none', -1, FRich.GuideLine);
  FRich.ResetCounts;
  p := FRuler.Mid(rmkFirstIndent);
  FRuler.Press(p.X, p.Y);
  x := FRuler.MarkerX(rmkFirstIndent, -1) - Dx;
  AssertEquals('at the marker''s place in the rich edit', x, FRich.GuideLine);
  AssertTrue('painted there', Asked(x));
  FRuler.MoveTo(p.X + 40, p.Y);
  AssertEquals('it follows the marker', FRuler.MarkerX(rmkFirstIndent, -1) - Dx, FRich.GuideLine);
  AssertEquals('at the text the drag would place', x + TyRichTwipsToPx(567, 96, 1),
    FRich.GuideLine);
  AssertTrue('painted at its new place', Asked(FRich.GuideLine));
  x := FRich.GuideLine;
  FRich.ResetCounts;
  FRuler.Release(p.X + 40, p.Y);
  AssertEquals('withdrawn', -1, FRich.GuideLine);
  AssertTrue('painted again where it was', Asked(x));
  // a stop dragged off: no line while it is off
  SetTabs(0, [1440]);
  p := FRuler.Mid(rmkTabStop, 0);
  FRuler.Press(p.X, p.Y);
  AssertTrue('a line for the stop', FRich.GuideLine >= 0);
  FRuler.MoveTo(p.X, p.Y + 3 * FRuler.Height);
  AssertEquals('off the ruler: none', -1, FRich.GuideLine);
  FRuler.MoveTo(p.X, p.Y);
  AssertTrue('back: again', FRich.GuideLine >= 0);
  FRuler.Key(VK_ESCAPE);
  AssertEquals('ended: none', -1, FRich.GuideLine);
  // asked by an application: the rich edit takes it, and -1 takes it away
  FRich.GuideLine := 50;
  AssertEquals('an application''s', 50, FRich.GuideLine);
  FRich.GuideLine := -7;
  AssertEquals('withdrawn', -1, FRich.GuideLine);
end;

{ Before a marker's change: which marker, its old and new value in twips, var allow (False:
  nothing happens); after it, the same values, the document already changed. }
procedure TTyRichEditRulerTest.TestTheEvents;
var
  depth: Integer;
begin
  CaretTo(0);
  depth := FRich.Document.UndoDepth;
  FAllow := False;
  Drag(rmkFirstIndent, 40);
  AssertEquals('asked', 1, FChangings);
  AssertTrue('the first-line marker', FLastMarker = rmkFirstIndent);
  AssertEquals('old', 0, FLastOld);
  AssertEquals('new', 567, FLastNew);
  AssertEquals('not allowed: nothing', depth, FRich.Document.UndoDepth);
  AssertEquals('no after-event', 0, FChangeds);
  FAllow := True;
  Drag(rmkFirstIndent, 40);
  AssertEquals('after', 1, FChangeds);
  AssertEquals('after: new', 567, FLastNew);
  AssertEquals('applied before the after-event', 567,
    FFormatAtChanged.LeftIndent + FFormatAtChanged.FirstIndent);
  // a stop added and removed: no old place, no new place
  Drag(rmkFirstIndent, -40);
  FRuler.Press(FRuler.XOfTwips(2835), FRuler.StripTop + 2, [ssDouble]);
  FRuler.Release(FRuler.XOfTwips(2835), FRuler.StripTop + 2);
  AssertTrue('a stop', FLastMarker = rmkTabStop);
  AssertEquals('added: no old place', CTyRulerNoTab, FLastOld);
  AssertEquals('added at', 2835, FLastNew);
  AssertEquals('its index', 0, FLastTab);
  FRuler.Press(FRuler.Mid(rmkTabStop, 0).X, FRuler.Mid(rmkTabStop, 0).Y);
  FRuler.MoveTo(FRuler.Mid(rmkTabStop, 0).X, 5 * FRuler.Height);
  FRuler.Release(FRuler.XOfTwips(2835), 5 * FRuler.Height);
  AssertEquals('removed: no new place', CTyRulerNoTab, FLastNew);
  AssertEquals('removed from', 2835, FLastOld);
end;

{ ---- the look and the cost ---- }

{ The keys resolve in the default theme and in every built-in one, light and dark: the ground,
  the active span and its ticks, the dimmed span's ticks, the markers in their four looks. The
  ruler draws with what its theme says. }
procedure TTyRichEditRulerTest.TestTheThemeKeysResolveEverywhere;
var
  c: TTyStyleController;
  names: TStringArray;
  i, m, x, y: Integer;
  mode, who: string;
  s, hov, act, dis: TTyStyleSet;
  bmp: TBitmap;
  r: TRect;
  found: Boolean;
  col: TColor;
begin
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  AssertTrue('the built-in themes', Length(names) >= 17);
  c := TTyStyleController.Create(nil);
  try
    for i := 0 to High(names) do
      for m := 0 to 1 do
      begin
        if m = 0 then mode := 'light' else mode := 'dark';
        c.ThemeName := names[i];
        c.Mode := mode;
        who := names[i] + '/' + mode;
        s := c.Model.ResolveStyle('TyRichEditRuler', '', []);
        AssertTrue(who + ': the ruler''s ground', tpBackground in s.Present);
        AssertTrue(who + ': its text', tpTextColor in s.Present);
        s := c.Model.ResolveStyle('TyRulerTick', '', []);
        AssertTrue(who + ': the span''s ground', tpBackground in s.Present);
        AssertTrue(who + ': the ticks', tpTextColor in s.Present);
        dis := c.Model.ResolveStyle('TyRulerTick', '', [tysDisabled]);
        AssertTrue(who + ': the dimmed ticks', tpTextColor in dis.Present);
        AssertTrue(who + ': dimmed differ', dis.TextColor <> s.TextColor);
        s := c.Model.ResolveStyle('TyRulerMarker', '', []);
        AssertTrue(who + ': a marker''s fill', tpBackground in s.Present);
        AssertTrue(who + ': its outline', tpBorderColor in s.Present);
        hov := c.Model.ResolveStyle('TyRulerMarker', '', [tysHover]);
        act := c.Model.ResolveStyle('TyRulerMarker', '', [tysActive]);
        dis := c.Model.ResolveStyle('TyRulerMarker', '', [tysDisabled]);
        AssertTrue(who + ': hovered differs', hov.BorderColor <> s.BorderColor);
        AssertTrue(who + ': dragged differs', act.Background.Color <> s.Background.Color);
        AssertTrue(who + ': disabled differs', dis.BorderColor <> s.BorderColor);
      end;
  finally
    c.Free;
  end;
  // the ruler paints with its theme
  CaretTo(0);
  FCtl.LoadThemeCss('TyRulerMarker { background: #FF0000; border-color: #FF0000; }');
  FRuler.CheckView;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(FRuler.Width, FRuler.Height);
    FRuler.RenderTo(bmp.Canvas, Rect(0, 0, FRuler.Width, FRuler.Height), 96);
    AssertTrue('the first-line marker', FRuler.MarkerRect(rmkFirstIndent, -1, r));
    found := False;
    for y := r.Top to r.Bottom - 1 do
      for x := r.Left to r.Right - 1 do
      begin
        col := bmp.Canvas.Pixels[x, y];
        if (Red(col) > 200) and (Green(col) < 60) and (Blue(col) < 60) then found := True;
      end;
    AssertTrue('drawn in the theme''s marker colour', found);
  finally
    bmp.Free;
  end;
end;

{ A caret move inside a paragraph lays nothing out and paints the ruler not at all; a move to a
  paragraph of another format paints it once; one to a paragraph of the same format at the same
  place paints nothing either. }
procedure TTyRichEditRulerTest.TestACaretMoveCostsNoLayoutAndPaintsOnlyAChange;
var
  i, checks: Integer;
  t: TTyRichText;
begin
  SetText('Alpha beta gamma delta'#10'Second paragraph here'#10'Third'#10'Fourth');
  SetPara(2, 567, 0, 0);
  CaretTo(0);
  t := FRich.Document.Text;
  FRich.ResetCounts;
  FRuler.Repaints := 0;
  checks := FRuler.ViewChecks;
  for i := 1 to 10 do FRich.SelStart := i;
  AssertEquals('nothing laid out', 0, FRich.LaidParas);
  AssertEquals('the ruler not painted', 0, FRuler.Repaints);
  AssertTrue('it heard every move', FRuler.ViewChecks >= checks + 10);
  FRich.SelStart := t.ParaStart(1) + 2;
  AssertEquals('the same look: not painted', 0, FRuler.Repaints);
  AssertEquals('but it knows the paragraph', 1, FRuler.View.Para);
  FRich.SelStart := t.ParaStart(2) + 1;
  AssertEquals('another format: painted once', 1, FRuler.Repaints);
  AssertEquals('nothing laid out', 0, FRich.LaidParas);
end;

{ The ruler hears through the rich edit's own notification: the application's OnChange and
  OnSelectionChange stay the application's and are raised as before. }
procedure TTyRichEditRulerTest.TestTheRulerHearsWithoutTheApplicationsEvents;
var
  m1, m2: TMethod;
  e: TNotifyEvent;
begin
  e := @Changed;
  m1 := TMethod(FRich.OnChange);
  m2 := TMethod(e);
  AssertTrue('OnChange the application''s', (m1.Code = m2.Code) and (m1.Data = m2.Data));
  e := @SelChanged;
  m1 := TMethod(FRich.OnSelectionChange);
  m2 := TMethod(e);
  AssertTrue('OnSelectionChange the application''s', (m1.Code = m2.Code) and (m1.Data = m2.Data));
  CaretTo(1);
  AssertTrue('the application heard the move', FSelChanges > 0);
  AssertEquals('the ruler heard it', 1, FRuler.View.Para);
  Drag(rmkFirstIndent, 40);
  AssertEquals('the application heard the change once', 1, FChanges);
end;

procedure TTyRichEditRulerTest.FreeRulerChanging(Sender: TObject; AMarker: TTyRulerMarker;
  ATab: Integer; AOldTwips, ANewTwips: Integer; var AAllow: Boolean);
begin
  Inc(FChangings);
  FRuler := nil;
  Sender.Free;
end;

procedure TTyRichEditRulerTest.FreeRulerChanged(Sender: TObject; AMarker: TTyRulerMarker;
  ATab: Integer; AOldTwips, ANewTwips: Integer);
begin
  Inc(FChangeds);
  FRuler := nil;
  Sender.Free;
end;

procedure TTyRichEditRulerTest.FreeRulerOnChange(Sender: TObject);
begin
  Inc(FChanges);
  if FRuler <> nil then
  begin
    FreeAndNil(FRuler);
  end;
end;

{ A whole paragraph selected forward (the caret at the next paragraph's start, as Shift+Down
  from a line's start gives) and backward: the ruler shows the selected paragraph - the one
  Paragraph reads and a drag changes -, and its drag changes what it shows. With nothing
  selected it is the caret's. }
procedure TTyRichEditRulerTest.TestAWholeParagraphSelectedIsTheOneShownAndDragged;
var
  t: TTyRichText;
begin
  SetText('First paragraph'#10'Second paragraph'#10'Third');
  SetPara(1, 1134, 0, 0);
  t := FRich.Document.Text;
  // forward: anchor 0, caret at paragraph 1's start
  FRich.SelStart := 0;
  FRich.SelLength := t.ParaStart(1);
  FRich.UpdateView;
  AssertEquals('the selected paragraph is shown', 0, FRuler.View.Para);
  AssertEquals('as Paragraph reads it', 0, FRich.Paragraph.LeftIndent);
  Drag(rmkLeftIndent, 40);
  AssertEquals('the shown one moved', 567, Fmt(0).LeftIndent);
  AssertEquals('the next one did not', 1134, Fmt(1).LeftIndent);
  AssertEquals('and the ruler shows the move', 567, FRuler.View.Format.LeftIndent);
  // nothing selected: the caret's
  CaretTo(1, 2);
  AssertEquals('the caret''s', 1, FRuler.View.Para);
end;

{ Where the rich edit would refuse a paragraph format (a paragraph of Word's table of contents,
  a row that holds a nested table) the markers show in the disabled look and a press starts no
  drag - asked at the press. }
procedure TTyRichEditRulerTest.TestNothingMayBeDraggedWhereTheFormatIsRefused;
var
  i, p: Integer;
  pt: TPoint;
  c: TTyRichCell;
begin
  LoadBytes(FixtureFile('word-toc.rtf'));
  FRich.FinishLoading;
  FRich.UpdateView;
  p := -1;
  for i := 1 to FRich.Document.Text.ParaCount - 1 do
    if FRich.Document.ParaEndsInField(i) and FRich.Document.ParaEndsInField(i - 1) then
    begin
      p := i;
      Break;
    end;
  AssertTrue('a paragraph of the contents', p >= 0);
  CaretTo(p, 0);
  FRuler.CheckView;
  AssertFalse('the control says no', FRich.CanFormatParagraphs);
  AssertFalse('not draggable', FRuler.CanDrag);
  pt := FRuler.Mid(rmkFirstIndent);
  FRuler.Press(pt.X, pt.Y);
  AssertFalse('a press starts no drag', FRuler.Dragging);
  FRuler.Release(pt.X, pt.Y);
  LoadBytes(FixtureFile('hand-word-table-merged.rtf'));
  FRich.FinishLoading;
  FRich.UpdateView;
  p := -1;
  for i := 0 to FRich.Document.Text.ParaCount - 1 do
  begin
    c := FRich.Document.CellAt(i);
    if (c <> nil) and c.Row.HoldsNestedTable then
    begin
      p := i;
      Break;
    end;
  end;
  AssertTrue('the row that holds the nested table', p >= 0);
  CaretTo(p, 0);
  FRuler.CheckView;
  AssertFalse('there neither', FRuler.CanDrag);
end;

{ The ruler freed during its own command - by its OnMarkerChanging handler, its
  OnMarkerChanged handler, or the rich edit's OnChange the command raises: nothing of it is
  touched afterwards (freed memory poisoned), the rich edit keeps the focus question to itself. }
procedure TTyRichEditRulerTest.TestTheRulerFreedDuringItsOwnCommand;
var
  k: Integer;
  pt: TPoint;
begin
  for k := 0 to 2 do
  begin
    if FRuler = nil then
    begin
      FRuler := TRulerProbe.Create(nil);
      FRuler.Controller := FCtl;
      FRuler.Font.PixelsPerInch := 96;
      FRuler.AutoSize := False;
      FRuler.Parent := FForm;
      FRuler.SetBounds(0, 0, 440, 40);
      FRuler.SysUnit := ruCentimeters;
      FRuler.RichEdit := FRich;
    end;
    CaretTo(0);
    case k of
      0: FRuler.OnMarkerChanging := @FreeRulerChanging;
      1: FRuler.OnMarkerChanged := @FreeRulerChanged;
      2: FRich.OnChange := @FreeRulerOnChange;
    end;
    pt := FRuler.Mid(rmkFirstIndent);
    FRuler.Press(pt.X, pt.Y);
    FRuler.MoveTo(pt.X + 40, pt.Y);
    BeginPoison;
    try
      FRuler.Release(pt.X + 40, pt.Y);
    finally
      EndPoison;
    end;
    AssertNull(Format('case %d: the ruler was freed', [k]), FRuler);
    FRich.OnChange := @Changed;
    // the double click's added stop, freed in its own command
    if k = 0 then
    begin
      FRuler := TRulerProbe.Create(nil);
      FRuler.Controller := FCtl;
      FRuler.Font.PixelsPerInch := 96;
      FRuler.AutoSize := False;
      FRuler.Parent := FForm;
      FRuler.SetBounds(0, 0, 440, 40);
      FRuler.RichEdit := FRich;
      FRuler.OnMarkerChanged := @FreeRulerChanged;
      BeginPoison;
      try
        FRuler.Press(FRuler.XOfTwips(2835), FRuler.StripTop + 2, [ssDouble]);
      finally
        EndPoison;
      end;
      AssertNull('the double click: the ruler was freed', FRuler);
    end;
  end;
end;

{ OnMarkerChanged gives a moved stop's index after the move and the sort: the stop moved past
  another is found at that index. OnMarkerChanging gives its index before. }
procedure TTyRichEditRulerTest.TestAMovedStopsIndexIsItsIndexAfterTheMove;
var
  pt: TPoint;
begin
  SetTabs(0, [1134, 2835]);
  CaretTo(0);
  pt := FRuler.Mid(rmkTabStop, 0);
  FRuler.Press(pt.X, pt.Y);
  FRuler.MoveTo(FRuler.XOfTwips(4252), pt.Y);
  FRuler.Release(FRuler.XOfTwips(4252), pt.Y);
  AssertEquals('moved', 1, FChangeds);
  AssertEquals('its new place', 4252, FLastNew);
  AssertEquals('its index after the sort', 1, FLastTab);
  AssertEquals('the stop at that index is it', 4252, Fmt(0).Tabs[FLastTab].Position);
end;

{ A double click that lands on a place a stop already has adds no second one there. }
procedure TTyRichEditRulerTest.TestADoubleClickOnAStopsPlaceAddsNone;
var
  x, y, tab, depth: Integer;
begin
  SetTabs(0, [2835]);
  CaretTo(0);
  x := FRuler.XOfTwips(2835);
  // a height of the ruler where the stop's marker is not (the click is on empty space)
  y := -1;
  for tab := 0 to FRuler.Height - 1 do
    if FRuler.MarkerAt(x, tab, depth) = rmkNone then
    begin
      y := tab;
      Break;
    end;
  AssertTrue('empty space above or below the stop', y >= 0);
  depth := FRich.Document.UndoDepth;
  FRuler.Press(x, y, [ssDouble]);
  FRuler.Release(x, y);
  AssertEquals('one stop still', 1, Length(Fmt(0).Tabs));
  AssertEquals('no step', depth, FRich.Document.UndoDepth);
  AssertEquals('nothing asked', 0, FChangings);
end;

{ The right indent stops short of the first line when that line starts right of the others:
  CTyRulerMinTextTwips of text is left right of the first line's start. }
procedure TTyRichEditRulerTest.TestTheRightIndentLeavesRoomForAFirstLineRightOfTheOthers;
begin
  SetPara(0, 0, 1440, 0);
  CaretTo(0);
  Drag(rmkRightIndent, -2000);
  AssertTrue(Format('the right indent %d leaves the first line %d twips',
    [Fmt(0).RightIndent, WT - Fmt(0).RightIndent - 1440]),
    WT - Fmt(0).RightIndent - 1440 >= CTyRulerMinTextTwips - 20);
  AssertTrue('and it moved as far as that', Fmt(0).RightIndent > 0);
end;

{ ruAuto: the system's unit, asked of the system itself (not a test's stand-in) - on Windows the
  user's locale setting LOCALE_IMEASURE ('1': U.S., inches), read here by the test's own call. }
procedure TTyRichEditRulerTest.TestTheSystemsUnitIsTheLocales;
{$IFDEF MSWINDOWS}
var
  buf: array[0..3] of WideChar;
  want: TTyRulerUnit;
{$ENDIF}
begin
  FRuler.RealUnit := True;
  {$IFDEF MSWINDOWS}
  FillChar(buf, SizeOf(buf), 0);
  AssertTrue('the locale answers', GetLocaleInfoW($0400, $000D, @buf[0], Length(buf)) > 0);
  if buf[0] = '1' then want := ruInches else want := ruCentimeters;
  AssertTrue('the system''s unit', FRuler.SystemMeasureUnit = want);
  // what the other answer would be, made true through the property, is what is shown
  FRuler.MeasureUnit := ruAuto;
  AssertTrue('ruAuto shows it', FRuler.EffectiveUnit = want);
  {$ELSE}
  AssertTrue('one of the two', FRuler.SystemMeasureUnit in [ruCentimeters, ruInches]);
  {$ENDIF}
end;

initialization
  RegisterTest(TTyRichEditRulerTest);

end.
