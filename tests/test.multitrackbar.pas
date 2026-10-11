unit test.multitrackbar;
{$mode objfpc}{$H+}

{ TTyMultiTrackBarBase (#36): the ordered thumb model -- SetThumbValue clamping between the
  neighbours and Min..Max, the events, Normalize, a MinGap the range cannot hold, Min / Max /
  MinGap changes, a form being read -- then the geometry and the painting, then the mouse and
  the keyboard (through MouseDown / MouseMove / MouseUp, KeyDown and the CM_WANTSPECIALKEY and
  CM_HINTSHOW messages the form and the application send).

  Geometry and painting are checked against a TTyTrackBar of the same size and theme, not
  against the formula: a thumb at V must be the track bar's thumb at Position = V, and a bar with
  one thumb must draw the very same pixels the track bar does (groove, thumb, ticks, labels).
  The bitmaps start magenta, a colour nothing in the fixture theme is. }

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, LMessages, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.StyleModel,
  tyControls.Painter, tyControls.TrackBar,
  tyControls.MultiTrackBar;

type
  { Opens the protected seams: the whole-set setter, Normalize and the read-a-form pair, the
    painting, and the per-thumb / per-segment data the final classes will supply (here plain
    arrays a test fills; empty = the base class's answer). }
  TMultiProbe = class(TTyMultiTrackBarBase)
  protected
    function ThumbEnabled(AIndex: Integer): Boolean; override;
    function ThumbColor(AIndex: Integer): TColor; override;
    function ThumbStyleClass(AIndex: Integer): string; override;
    function ThumbHint(AIndex: Integer): string; override;
    function SegmentStyle(AIndex: Integer; out ATypeKey, AStyleClass: string): Boolean; override;
    function KeyShiftState: TShiftState; override;
  public
    HoldShift: Boolean;             // what KeyShiftState reports for Shift
    HoldMouse: Boolean;             // ... and for the left mouse button
    { What Focused answers: a test form is never shown, so the bar never really has the focus. }
    FakeFocus: Boolean;
    Off: array of Boolean;          // thumb i disabled
    Colors: array of TColor;
    ThumbCls: array of string;
    Hints: array of string;
    SegKey, SegCls: array of string;
    function Focused: Boolean; override;
    procedure Put(const AValues: array of Integer);
    procedure BeginReading;
    procedure EndReading;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure PreferredSize(out AW, AH: Integer);
    { The pointer, as the widgetset delivers it. }
    procedure Press(X, Y: Integer);
    procedure Drag(X, Y: Integer);
    procedure Release(X, Y: Integer);
    procedure Hover(X, Y: Integer);
    procedure Leave;
    { KeyDown as the form delivers it; returns the key afterwards (0 = consumed). }
    function Key(AKey: Word; AShift: TShiftState = []): Word;
    { What the bar answers the form's CM_WANTSPECIALKEY for AKey. }
    function WantsKey(AKey: Word): PtrInt;
    { The focus arriving, as the form announces it (CM_ENTER). }
    procedure Enter;
    { One wheel notch as the widgetset delivers it (LM_MOUSEWHEEL, through TControl's
      WMMouseWheel); True when the bar handled it. }
    function Wheel(ADelta: Integer): Boolean;
    { The hint the application would show at (X, Y): CM_HINTSHOW with the control's own hint
      prefilled, as TApplication.ShowHintWindow does; ARect is the CursorRect it hands back. }
    function HintAt(X, Y: Integer; out ARect: TRect): string;
  end;

  { The reference: a TTyTrackBar with its painting and preferred size opened. }
  TRefBar = class(TTyTrackBar)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure PreferredSize(out AW, AH: Integer);
  end;

  TTyMultiTrackModelTest = class(TTestCase)
  private
    FForm: TForm;
    FBar: TMultiProbe;
    FLog: string;
    procedure ThumbChanged(Sender: TObject; AIndex: Integer);
    procedure Changed(Sender: TObject);
    function Values: string;
    procedure CheckInvariant(const AWhere: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDefaults;
    procedure TestSetThumbValueStopsAtTheLeftNeighbour;
    procedure TestSetThumbValueStopsAtTheRightNeighbour;
    procedure TestSetThumbValueStaysWithinMinAndMax;
    procedure TestEventsCarryTheIndexAndFireOnlyOnARealChange;
    procedure TestNormalizeSortsAndPushesApart;
    procedure TestNormalizePushesBackFromMax;
    procedure TestAGapTheRangeCannotHoldShrinksThePlacementNotTheProperty;
    procedure TestMinMaxAndMinGapChangesRestoreTheInvariant;
    procedure TestReadingAFormSettlesOnLoadedWithoutEvents;
    procedure TestSetThumbValuesReportsOnlyARealChange;
    procedure TestSelectedThumbStaysInRange;
    procedure TestOutOfRangeIndexRaises;
    procedure TestRandomEditsKeepTheInvariant;
  end;

  { Shared by the geometry and painting tests: a probe and a TTyTrackBar of the same size on the
    same form and theme. The track bar is the reference -- a thumb of the multi-thumb bar at V
    must be exactly where, and look exactly like, the track bar's thumb at Position = V. }
  TMultiTrackPaintBase = class(TTestCase)
  protected
    FCtl: TTyStyleController;
    FForm: TForm;
    FBar: TMultiProbe;
    FRef: TRefBar;
    procedure SetUp; override;
    procedure TearDown; override;
    { Both bars to one orientation / direction, 200 long and 24 across. }
    procedure Configure(AOri: TTyTrackOrientation; ARev: Boolean);
    { The bar (or the reference) rendered over a magenta sentinel ground. }
    function Shot(ARef: Boolean): TBGRABitmap;
    function W: Integer;
    function H: Integer;
    { Hit rect of the reference's thumb at Position = AValue. }
    function RefThumbRect(AValue: Integer): TRect;
    { Main-axis centre of that rect. }
    function RefCentre(AValue: Integer): Integer;
    { The pixel at main-axis offset AMain on the groove's centre line. }
    function GroovePx(B: TBGRABitmap; AMain: Integer): TBGRAPixel;
    { True when main-axis offset AMain lies inside any thumb's hit band. }
    function UnderAThumb(AMain: Integer): Boolean;
    { The pixel at the middle of thumb AIndex. }
    function ThumbPx(B: TBGRABitmap; AIndex: Integer): TBGRAPixel;
  end;

  TTyMultiTrackGeometryTest = class(TMultiTrackPaintBase)
  published
    procedure TestThumbRectsAreTheTrackBarsAtEachValue;
    procedure TestSegmentSpansRunBetweenTheThumbCentres;
    procedure TestSegmentSpanOutsideTheSegmentsIsFalse;
    procedure TestPreferredCrossSizeIsTheTrackBars;
  end;

  TTyMultiTrackPaintTest = class(TMultiTrackPaintBase)
  published
    procedure TestOneThumbDrawsWhatTheTrackBarDraws;
    procedure TestEveryThumbSitsWhereTheTrackBarDrawsIt;
    procedure TestRangesAreFilledCentreToCentre;
    procedure TestSegmentsTakeTheirClassesBackground;
    procedure TestTheBaseThemeDrawsASegmentOnlyWithAClass;
    procedure TestAThumbColourReplacesTheThemeBackground;
    procedure TestAThumbStyleClassIsResolved;
    procedure TestADisabledThumbIsDrawnAsUsual;
  end;

  { The events logged as `T<i>` (thumb change), `S<i>` (select), `C` (change); points on the
    bar at a value come from the reference track bar's thumb centre at that value. }
  TMultiTrackInputBase = class(TMultiTrackPaintBase)
  protected
    FLog: string;
    procedure SetUp; override;
    procedure Logged(Sender: TObject; AIndex: Integer);
    procedure Selected(Sender: TObject; AIndex: Integer);
    procedure Changed(Sender: TObject);
    function Values: string;
    function At(AValue: Integer): TPoint;
    function Shifted(const P: TPoint; ADelta: Integer): TPoint;
  end;

  TTyMultiTrackMouseTest = class(TMultiTrackInputBase)
  published
    procedure TestPressOnAThumbSelectsItWithoutMovingIt;
    procedure TestWhereThumbsOverlapTheNearestCentreWins;
    procedure TestDragMovesOnlyThatThumb;
    procedure TestADragStopsMinGapFromTheNeighbours;
    procedure TestADragFollowsTheDirectionOfTheBar;
    procedure TestAPressOnTheGrooveBringsTheNearestThumb;
    procedure TestEquidistantPressTakesTheLowerValue;
    procedure TestAJumpSkipsDisabledThumbs;
    procedure TestADisabledThumbIsInert;
    procedure TestHoverAndPressArePaintedOnThatThumbOnly;
    procedure TestThumbsOnOneValueComeApartInTheDragDirection;
    procedure TestADisabledBarIgnoresTheMouse;
    procedure TestTheHintIsTheThumbsUnderThePointer;
  end;

  { The final classes as a form and a theme see them: the published collection, the type key,
    a form file written and read back. Painting and the pointer go through the protected
    methods, opened by these. }
  TBaseAccess = class(TTyMultiTrackBarBase);
  TRangeAccess = class(TTyRangeTrackBar);
  TTrackAccess = class(TTyTrackBar);

  { Shared: a host form and a theme, the form file round trip. }
  TMultiTrackFinalBase = class(TTestCase)
  protected
    FCtl: TTyStyleController;
    FForm: TForm;
    FLog: string;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure ThumbMoved(Sender: TObject; AIndex: Integer);
    procedure Changed(Sender: TObject);
    function ValuesOf(ABar: TTyMultiTrackBarBase): string;
    { The form file text of AHost, as the IDE writes it. }
    function FormText(AHost: TForm): string;
    { A new host form read from AText. }
    function FromText(const AText: string): TForm;
    { AHost written and read back into a new host form. }
    function RoundTrip(AHost: TForm): TForm;
    { The part of a form file text from the bar's `object` line on. }
    function BarText(const AText: string): string;
    { The bar rendered over a magenta sentinel ground. }
    function Shot(ABar: TTyMultiTrackBarBase): TBGRABitmap;
    { True when main-axis offset AMain (horizontal bar) lies inside any thumb's hit band. }
    function UnderAThumb(ABar: TTyMultiTrackBarBase; AMain: Integer): Boolean;
  end;

  TTyRangeTrackBarTest = class(TMultiTrackFinalBase)
  private
    FBar: TTyRangeTrackBar;
    FSeen: string;
    procedure ReadTheRangeInTheEvent(Sender: TObject; AIndex: Integer);
    function Values: string;
    function RangesText(ABar: TTyRangeTrackBar): string;
  protected
    procedure SetUp; override;
  published
    procedure TestDefaults;
    procedure TestTheTypeKeyHangsOnTheTrackBars;
    procedure TestLowValueAndHighValueAreTheFirstRange;
    procedure TestARangeEndMovesThroughTheModel;
    procedure TestBeginUpdateHoldsTheValuesUntilEndUpdate;
    procedure TestSeveralRangesInOrderAndHighlighted;
    procedure TestAFormsRangesAreSortedWhenRead;
    procedure TestADraggedEndIsReadFromItsRange;
    procedure TestRangesRoundTripThroughAFormFile;
    procedure TestNoRangesRoundTrips;
  end;

  TMultiAccess = class(TTyMultiTrackBar);

  { Counts the repaints an item change asks for. }
  TMultiCounting = class(TTyMultiTrackBar)
  public
    Invalidations: Integer;
    procedure Invalidate; override;
  end;

  TTyMultiTrackBarTest = class(TMultiTrackFinalBase)
  private
    FBar: TTyMultiTrackBar;
    function Values: string;
    { Every item: value, colour (as $hex, or 'def'), hint, enabled (+/-), style class. }
    function ThumbsText(ABar: TTyMultiTrackBar): string;
    function SegmentsText(ABar: TTyMultiTrackBar): string;
    function Centre(AIndex: Integer): TPoint;
    function HintAt(const P: TPoint): string;
    procedure Selected(Sender: TObject; AIndex: Integer);
  protected
    procedure SetUp; override;
  published
    procedure TestDefaults;
    procedure TestTheTypeKeyHangsOnTheTrackBars;
    procedure TestAValueMovesThroughTheModel;
    procedure TestSortingKeepsEachThumbsLook;
    procedure TestTheSelectionFollowsItsThumbWhenSorted;
    procedure TestAThumbsColourIsPainted;
    procedure TestAThumbsStyleClassIsResolved;
    procedure TestAThumbsHintIsShownOverIt;
    procedure TestADisabledThumbIsInert;
    procedure TestAnItemChangeRepaints;
    procedure TestSegmentsStyleTheirStretchOnly;
    procedure TestAFormsThumbsAreSortedWhenRead;
    procedure TestThumbsAndSegmentsRoundTripThroughAFormFile;
    procedure TestNoThumbsRoundTrips;
  end;

  TTyMultiTrackKeyboardTest = class(TMultiTrackInputBase)
  private
    procedure WheelSwallowed(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
  published
    procedure TestArrowsStepTheSelectedThumb;
    procedure TestPagesAndEndsStopAtTheNeighbours;
    procedure TestWithNoSelectionTheFirstEnabledThumbMoves;
    procedure TestAKeyMovesNothingWhenEveryThumbIsDisabled;
    procedure TestADisabledBarIgnoresTheKeys;
    procedure TestTabWalksTheEnabledThumbsThenLeaves;
    procedure TestEnteringFromTheKeyboardStartsAtTheNearEnd;
    procedure TestTheWheelStepsTheKeyboardsThumb;
  end;

  { ShowValue against TTyTrackBar's: the same strip, the same shorter track, the same text. }
  TTyMultiTrackReadoutTest = class(TMultiTrackInputBase)
  published
    procedure TestOneThumbWithTheReadoutDrawsWhatTheTrackBarDraws;
    procedure TestTheReadoutIsTheSelectedThumbsElseTheFirst;
  end;

  { OnDrawTrack / OnDrawThumb. The handlers log `track ` and `<i>:<states> ` in the order they
    are asked, keep the rectangles they were handed, and -- as a test sets them up -- take a part
    over (ADefaultDraw := False) and / or fill its rectangle in an ink of their own. }
  TTyMultiTrackOwnerDrawTest = class(TMultiTrackInputBase)
  private
    FCalls: string;
    FTrackRect: TRect;
    FThumbRects: array of TRect;
    FDropThumb: Integer;
    FFillThumb: Boolean;
    FDropTrack: Boolean;
    FFillTrack: Boolean;
    procedure DrawTrack(Sender: TObject; APainter: TTyPainter; const ARect: TRect;
      var ADefaultDraw: Boolean);
    procedure DrawThumb(Sender: TObject; APainter: TTyPainter; AIndex: Integer;
      const ARect: TRect; AStates: TTyStateSet; var ADefaultDraw: Boolean);
    { The bounding box of the pixels of one colour inside AWithin. }
    function InkBox(B: TBGRABitmap; const AWithin: TRect; R, G, Bl: Byte): TRect;
    function InkCount(B: TBGRABitmap; const AWithin: TRect; R, G, Bl: Byte): Integer;
  protected
    procedure SetUp; override;
  published
    procedure TestTheHooksAreAskedForEachPartInPaintOrder;
    procedure TestTheRectanglesAreThePaintedParts;
    procedure TestADefaultDrawFalseLeavesTheThumbToTheHandler;
    procedure TestADefaultDrawFalseLeavesTheTrackToTheHandler;
  end;

implementation

{ TMultiProbe }

procedure TMultiProbe.Put(const AValues: array of Integer);
begin
  SetThumbValues(AValues);
end;

procedure TMultiProbe.BeginReading;
begin
  Loading;
end;

procedure TMultiProbe.EndReading;
begin
  Loaded;
end;

function TMultiProbe.ThumbEnabled(AIndex: Integer): Boolean;
begin
  if AIndex < Length(Off) then Result := not Off[AIndex]
  else Result := inherited ThumbEnabled(AIndex);
end;

function TMultiProbe.ThumbColor(AIndex: Integer): TColor;
begin
  if AIndex < Length(Colors) then Result := Colors[AIndex]
  else Result := inherited ThumbColor(AIndex);
end;

function TMultiProbe.ThumbStyleClass(AIndex: Integer): string;
begin
  if AIndex < Length(ThumbCls) then Result := ThumbCls[AIndex]
  else Result := inherited ThumbStyleClass(AIndex);
end;

function TMultiProbe.ThumbHint(AIndex: Integer): string;
begin
  if AIndex < Length(Hints) then Result := Hints[AIndex]
  else Result := inherited ThumbHint(AIndex);
end;

function TMultiProbe.SegmentStyle(AIndex: Integer; out ATypeKey, AStyleClass: string): Boolean;
begin
  Result := inherited SegmentStyle(AIndex, ATypeKey, AStyleClass);
  if (AIndex < Length(SegKey)) and (SegKey[AIndex] <> '') then
  begin
    ATypeKey := SegKey[AIndex];
    if AIndex < Length(SegCls) then AStyleClass := SegCls[AIndex];
    Result := True;
  end;
end;

procedure TMultiProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TMultiProbe.PreferredSize(out AW, AH: Integer);
begin
  AW := 0;
  AH := 0;
  CalculatePreferredSize(AW, AH, False);
end;

function TMultiProbe.KeyShiftState: TShiftState;
begin
  if HoldShift then Result := [ssShift] else Result := [];
  if HoldMouse then Include(Result, ssLeft);
end;

function TMultiProbe.Focused: Boolean;
begin
  Result := FakeFocus or inherited Focused;
end;

procedure TMultiProbe.Enter;
begin
  Perform(CM_ENTER, 0, 0);
end;

function TMultiProbe.Wheel(ADelta: Integer): Boolean;
var
  msg: TLMMouseEvent;
begin
  FillChar(msg{%H-}, SizeOf(msg), 0);
  msg.Msg := LM_MOUSEWHEEL;
  msg.WheelDelta := ADelta;
  Dispatch(msg);
  Result := msg.Result <> 0;
end;

procedure TMultiProbe.Press(X, Y: Integer);
begin
  MouseDown(mbLeft, [ssLeft], X, Y);
end;

procedure TMultiProbe.Drag(X, Y: Integer);
begin
  MouseMove([ssLeft], X, Y);
end;

procedure TMultiProbe.Release(X, Y: Integer);
begin
  MouseUp(mbLeft, [], X, Y);
end;

procedure TMultiProbe.Hover(X, Y: Integer);
begin
  MouseMove([], X, Y);
end;

procedure TMultiProbe.Leave;
begin
  MouseLeave;
end;

function TMultiProbe.Key(AKey: Word; AShift: TShiftState): Word;
begin
  Result := AKey;
  KeyDown(Result, AShift);
end;

function TMultiProbe.WantsKey(AKey: Word): PtrInt;
begin
  Result := Perform(CM_WANTSPECIALKEY, AKey, 0);
end;

function TMultiProbe.HintAt(X, Y: Integer; out ARect: TRect): string;
var
  info: THintInfo;
begin
  info := Default(THintInfo);
  info.HintControl := Self;
  info.CursorPos := Point(X, Y);
  info.CursorRect := ClientRect;
  info.HintStr := Hint;
  Perform(CM_HINTSHOW, 0, LParam(PtrUInt(@info)));
  ARect := info.CursorRect;
  Result := info.HintStr;
end;

{ TRefBar }

procedure TRefBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TRefBar.PreferredSize(out AW, AH: Integer);
begin
  AW := 0;
  AH := 0;
  CalculatePreferredSize(AW, AH, False);
end;


{ TTyMultiTrackModelTest }

procedure TTyMultiTrackModelTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FBar := TMultiProbe.Create(FForm);
  FBar.Parent := FForm;
  FLog := '';
end;

procedure TTyMultiTrackModelTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyMultiTrackModelTest.ThumbChanged(Sender: TObject; AIndex: Integer);
begin
  AssertSame(FBar, Sender);
  FLog := FLog + 'T' + IntToStr(AIndex) + ' ';
end;

procedure TTyMultiTrackModelTest.Changed(Sender: TObject);
begin
  AssertSame(FBar, Sender);
  FLog := FLog + 'C ';
end;

function TTyMultiTrackModelTest.Values: string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to FBar.ThumbCount - 1 do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + IntToStr(FBar.ThumbValues[i]);
  end;
end;

procedure TTyMultiTrackModelTest.CheckInvariant(const AWhere: string);
var
  i, gap: Integer;
begin
  { A range set inside out holds every thumb at Min, as TTyTrackBar holds its Position. }
  if FBar.Max < FBar.Min then
  begin
    for i := 0 to FBar.ThumbCount - 1 do
      AssertEquals(Format('%s: inside-out range, thumb %d sits at Min [%s]', [AWhere, i, Values]),
        FBar.Min, FBar.ThumbValues[i]);
    Exit;
  end;
  gap := FBar.MinGap;
  if (FBar.ThumbCount > 1) and (Int64(FBar.ThumbCount - 1) * gap > FBar.Max - FBar.Min) then
    gap := (FBar.Max - FBar.Min) div (FBar.ThumbCount - 1);
  for i := 0 to FBar.ThumbCount - 1 do
  begin
    AssertTrue(Format('%s: thumb %d (%d) below Min %d [%s]', [AWhere, i, FBar.ThumbValues[i],
      FBar.Min, Values]), FBar.ThumbValues[i] >= FBar.Min);
    AssertTrue(Format('%s: thumb %d (%d) above Max %d [%s]', [AWhere, i, FBar.ThumbValues[i],
      FBar.Max, Values]), FBar.ThumbValues[i] <= FBar.Max);
    if i > 0 then
      AssertTrue(Format('%s: thumbs %d and %d closer than %d [%s]', [AWhere, i - 1, i, gap, Values]),
        FBar.ThumbValues[i] - FBar.ThumbValues[i - 1] >= gap);
  end;
end;

procedure TTyMultiTrackModelTest.TestDefaults;
begin
  AssertEquals('Min', 0, FBar.Min);
  AssertEquals('Max', 100, FBar.Max);
  AssertEquals('MinGap', 0, FBar.MinGap);
  AssertEquals('no thumb selected', -1, FBar.SelectedThumb);
  AssertEquals('the custom class seeds no thumbs', 0, FBar.ThumbCount);
  AssertTrue('focusable, like TTyTrackBar', FBar.TabStop);
end;

procedure TTyMultiTrackModelTest.TestSetThumbValueStopsAtTheLeftNeighbour;
begin
  FBar.MinGap := 5;
  FBar.Put([20, 50, 80]);
  FBar.SetThumbValue(1, 10);
  AssertEquals('the middle thumb stops MinGap right of the first', '20,25,80', Values);
  FBar.SetThumbValue(2, 0);
  AssertEquals('the last stops MinGap right of the middle', '20,25,30', Values);
end;

procedure TTyMultiTrackModelTest.TestSetThumbValueStopsAtTheRightNeighbour;
begin
  FBar.MinGap := 5;
  FBar.Put([20, 50, 80]);
  FBar.SetThumbValue(1, 95);
  AssertEquals('the middle thumb stops MinGap left of the last', '20,75,80', Values);
  FBar.SetThumbValue(0, 99);
  AssertEquals('the first stops MinGap left of the middle', '70,75,80', Values);
end;

procedure TTyMultiTrackModelTest.TestSetThumbValueStaysWithinMinAndMax;
begin
  FBar.Min := -10;
  FBar.Max := 10;
  FBar.Put([0, 5]);
  FBar.SetThumbValue(0, -500);
  FBar.SetThumbValue(1, 500);
  AssertEquals('-10,10', Values);
end;

procedure TTyMultiTrackModelTest.TestEventsCarryTheIndexAndFireOnlyOnARealChange;
begin
  FBar.MinGap := 5;
  FBar.Put([20, 50, 100]);
  FBar.OnThumbChange := @ThumbChanged;
  FBar.OnChange := @Changed;
  FBar.SetThumbValue(1, 50);
  AssertEquals('the same value fires nothing', '', FLog);
  FBar.SetThumbValue(1, 60);
  AssertEquals('a move reports its thumb, then OnChange', 'T1 C ', FLog);
  FLog := '';
  FBar.SetThumbValue(2, 500);
  AssertEquals('clamped back onto where it was: nothing', '', FLog);
  FBar.SetThumbValue(0, 70);
  AssertEquals('clamped to a new place is a change', 'T0 C ', FLog);
  AssertEquals('55,60,100', Values);
end;

procedure TTyMultiTrackModelTest.TestNormalizeSortsAndPushesApart;
begin
  FBar.MinGap := 5;
  FBar.Put([70, 10, 12, 40]);
  AssertEquals('sorted, and 12 pushed to MinGap from 10', '10,15,40,70', Values);
  FBar.Put([30, 30, 30]);
  AssertEquals('coinciding values pushed apart left to right', '30,35,40', Values);
end;

procedure TTyMultiTrackModelTest.TestNormalizePushesBackFromMax;
begin
  FBar.MinGap := 5;
  FBar.Put([100, 99, 98]);
  AssertEquals('pushed apart, then back from Max', '90,95,100', Values);
  FBar.Put([-50, 200]);
  AssertEquals('clamped into Min..Max', '0,100', Values);
end;

procedure TTyMultiTrackModelTest.TestAGapTheRangeCannotHoldShrinksThePlacementNotTheProperty;
begin
  FBar.Max := 10;
  FBar.MinGap := 5;
  FBar.Put([5, 5, 5, 5]);    // 3 x 5 = 15 > 10: placed (10 - 0) div 3 = 3 apart
  AssertEquals('1,4,7,10', Values);
  AssertEquals('MinGap keeps the value it was given', 5, FBar.MinGap);
  FBar.SetThumbValue(1, 0);
  AssertEquals('a move honours the shrunk gap', '1,4,7,10', Values);
  FBar.Max := 100;
  AssertEquals('room again: the full gap comes back', '1,6,11,16', Values);
  CheckInvariant('after widening');
end;

procedure TTyMultiTrackModelTest.TestMinMaxAndMinGapChangesRestoreTheInvariant;
begin
  FBar.Put([20, 50, 80]);
  FBar.OnThumbChange := @ThumbChanged;
  FBar.OnChange := @Changed;
  FBar.Min := 60;
  AssertEquals('60,60,80', Values);
  AssertEquals('each thumb that moved is reported, then OnChange once', 'T0 T1 C ', FLog);
  FLog := '';
  FBar.MinGap := 5;
  AssertEquals('60,65,80', Values);
  FBar.Max := 66;
  AssertEquals('56 would be below Min: placed 3 apart instead', '60,63,66', Values);
  CheckInvariant('after Max');
  FLog := '';
  FBar.Max := 66;
  AssertEquals('setting the same Max again fires nothing', '', FLog);
end;

procedure TTyMultiTrackModelTest.TestReadingAFormSettlesOnLoadedWithoutEvents;
begin
  FBar.OnThumbChange := @ThumbChanged;
  FBar.OnChange := @Changed;
  FBar.BeginReading;
  FBar.Put([90, 10, 50]);
  FBar.SetThumbValue(0, 300);
  AssertEquals('while reading, values are kept as listed', '300,10,50', Values);
  FBar.Min := 20;
  FBar.Max := 80;
  FBar.MinGap := 5;
  AssertEquals('nor do Min / Max / MinGap settle them yet', '300,10,50', Values);
  FBar.EndReading;
  AssertEquals('Loaded sorts and clamps', '20,50,80', Values);
  CheckInvariant('after Loaded');
  AssertEquals('reading a form fires no thumb or change event', '', FLog);
end;

procedure TTyMultiTrackModelTest.TestSetThumbValuesReportsOnlyARealChange;
begin
  FBar.OnThumbChange := @ThumbChanged;
  FBar.OnChange := @Changed;
  FBar.Put([10, 20]);
  AssertEquals('a new set is a change', 'C ', FLog);
  FLog := '';
  FBar.Put([20, 10]);
  AssertEquals('the same set in another order normalizes to what was there', '', FLog);
  FBar.Put([10, 20, 30]);
  AssertEquals('a thumb more is a change', 'C ', FLog);
end;

procedure TTyMultiTrackModelTest.TestSelectedThumbStaysInRange;
begin
  FBar.Put([10, 20, 30]);
  FBar.SelectedThumb := 2;
  AssertEquals(2, FBar.SelectedThumb);
  FBar.SelectedThumb := 3;
  AssertEquals('past the last thumb is none', -1, FBar.SelectedThumb);
  FBar.SelectedThumb := 2;
  FBar.Put([10]);
  AssertEquals('a selected thumb that went away is none', -1, FBar.SelectedThumb);
end;

procedure TTyMultiTrackModelTest.TestOutOfRangeIndexRaises;
var
  raised: Boolean;
begin
  FBar.Put([10, 20]);
  raised := False;
  try
    FBar.SetThumbValue(2, 5);
  except
    on EListError do raised := True;
  end;
  AssertTrue('SetThumbValue past the last thumb raises EListError', raised);
  raised := False;
  try
    FBar.ThumbValues[-1];
  except
    on EListError do raised := True;
  end;
  AssertTrue('ThumbValues[-1] raises EListError', raised);
end;

procedure TTyMultiTrackModelTest.TestRandomEditsKeepTheInvariant;
var
  step, op: Integer;
begin
  RandSeed := 36;
  FBar.Put([5, 25, 45, 65, 85]);
  for step := 1 to 2000 do
  begin
    op := Random(10);
    case op of
      0: FBar.Min := Random(60) - 20;
      1: FBar.Max := FBar.Min + Random(120);
      2: FBar.MinGap := Random(30);
    else
      FBar.SetThumbValue(Random(FBar.ThumbCount), Random(200) - 50);
    end;
    CheckInvariant('step ' + IntToStr(step) + ' op ' + IntToStr(op));
  end;
end;

{ TMultiTrackPaintBase }

const
  { Every part in a colour of its own, square corners so a rectangle is exactly its pixels. The
    bar itself has no background: what it leaves alone is the parent's. }
  CPaintCss =
    'TyTrackBar { color: #000000; border-width: 0px; border-radius: 0px; }' +
    'TyTrackGroove { background: #606060; border-radius: 0px; }' +
    'TyTrackSelection { background: #FF0000; border-radius: 0px; }' +
    'TyTrackSegment { border-radius: 0px; }' +
    'TyTrackSegment.go { background: #00C000; }' +
    'TyTrackSegment.stop { background: #C08000; }' +
    'TyTrackThumb { background: #3B82F6; border-radius: 0px; }' +
    'TyTrackThumb.big { background: #FFFF00; }' +
    'TyTrackThumb:hover { background: #00FFFF; }' +
    'TyTrackThumb:active { background: #8000FF; }';
  CLen = 200;
  CCross = 24;

function SamePx(const A: TBGRAPixel; R, G, B: Byte): Boolean;
begin
  Result := (A.red = R) and (A.green = G) and (A.blue = B);
end;

function PxStr(const A: TBGRAPixel): string;
begin
  Result := Format('#%.2x%.2x%.2x', [A.red, A.green, A.blue]);
end;

procedure TMultiTrackPaintBase.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(CPaintCss);
  FForm := TForm.CreateNew(nil);
  FBar := TMultiProbe.Create(FForm);
  FBar.Parent := FForm;
  FBar.Controller := FCtl;
  FBar.Font.PixelsPerInch := 96;
  FRef := TRefBar.Create(FForm);
  FRef.Parent := FForm;
  FRef.Controller := FCtl;
  FRef.Font.PixelsPerInch := 96;
  Configure(toHorizontal, False);
end;

procedure TMultiTrackPaintBase.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

procedure TMultiTrackPaintBase.Configure(AOri: TTyTrackOrientation; ARev: Boolean);
begin
  FBar.Orientation := AOri;
  FRef.Orientation := AOri;
  FBar.Reversed := ARev;
  FRef.Reversed := ARev;
  if AOri = toVertical then
  begin
    FBar.SetBounds(0, 0, CCross, CLen);
    FRef.SetBounds(0, 0, CCross, CLen);
  end
  else
  begin
    FBar.SetBounds(0, 0, CLen, CCross);
    FRef.SetBounds(0, 0, CLen, CCross);
  end;
end;

function TMultiTrackPaintBase.W: Integer;
begin
  Result := FBar.Width;
end;

function TMultiTrackPaintBase.H: Integer;
begin
  Result := FBar.Height;
end;

function TMultiTrackPaintBase.Shot(ARef: Boolean): TBGRABitmap;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(W, H);
    { Sentinel ground: nothing the bars draw is magenta. }
    bmp.Canvas.Brush.Color := RGBToColor(255, 0, 255);
    bmp.Canvas.FillRect(0, 0, W, H);
    if ARef then FRef.RenderTo(bmp.Canvas, Rect(0, 0, W, H), 96)
    else FBar.Render(bmp.Canvas, Rect(0, 0, W, H), 96);
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

function TMultiTrackPaintBase.RefThumbRect(AValue: Integer): TRect;
begin
  FRef.Position := AValue;
  Result := FRef.ThumbRect;
end;

function TMultiTrackPaintBase.RefCentre(AValue: Integer): Integer;
var
  r: TRect;
begin
  r := RefThumbRect(AValue);
  if FRef.Orientation = toVertical then Result := r.Top + (r.Bottom - r.Top) div 2
  else Result := r.Left + (r.Right - r.Left) div 2;
end;

{ TTyMultiTrackGeometryTest }

procedure TTyMultiTrackGeometryTest.TestThumbRectsAreTheTrackBarsAtEachValue;
const
  V: array[0..4] of Integer = (0, 20, 50, 77, 100);
var
  ori: TTyTrackOrientation;
  rev: Boolean;
  i: Integer;
  a, b: TRect;
  where: string;
begin
  FBar.Put(V);
  for ori := toHorizontal to toVertical do
    for rev := False to True do
    begin
      Configure(ori, rev);
      for i := 0 to High(V) do
      begin
        where := Format('ori=%d rev=%s thumb %d (%d)', [Ord(ori), BoolToStr(rev, True), i, V[i]]);
        a := FBar.ThumbRect(i);
        b := RefThumbRect(V[i]);
        AssertEquals(where + ' Left', b.Left, a.Left);
        AssertEquals(where + ' Top', b.Top, a.Top);
        AssertEquals(where + ' Right', b.Right, a.Right);
        AssertEquals(where + ' Bottom', b.Bottom, a.Bottom);
      end;
    end;
  { The direction really is followed (not one answer for all four): Reversed swaps the ends. }
  Configure(toHorizontal, True);
  AssertTrue('reversed: the thumb at 0 is right of the thumb at 100',
    FBar.ThumbRect(0).Left > FBar.ThumbRect(4).Left);
  Configure(toVertical, False);
  AssertTrue('vertical: the thumb at 100 is at the top',
    FBar.ThumbRect(4).Top < FBar.ThumbRect(0).Top);
end;

procedure TTyMultiTrackGeometryTest.TestSegmentSpansRunBetweenTheThumbCentres;
var
  ori: TTyTrackOrientation;
  rev: Boolean;
  lo, hi, c20, c60, minEnd, maxEnd: Integer;
  where: string;

  procedure Check(AIdx, A, B: Integer);
  var
    eLo, eHi: Integer;
  begin
    if A <= B then begin eLo := A; eHi := B; end else begin eLo := B; eHi := A; end;
    AssertTrue(where + ': segment ' + IntToStr(AIdx), FBar.SegmentSpan(AIdx, 96, lo, hi));
    AssertEquals(where + ': segment ' + IntToStr(AIdx) + ' low', eLo, lo);
    AssertEquals(where + ': segment ' + IntToStr(AIdx) + ' high', eHi, hi);
  end;

begin
  FBar.Put([20, 60]);
  for ori := toHorizontal to toVertical do
    for rev := False to True do
    begin
      Configure(ori, rev);
      where := Format('ori=%d rev=%s', [Ord(ori), BoolToStr(rev, True)]);
      c20 := RefCentre(20);
      c60 := RefCentre(60);
      { Segment 0 starts at the groove's Min end, the last ends at its Max end. }
      if (ori = toVertical) xor rev then
      begin
        minEnd := CLen;
        maxEnd := 0;
      end
      else
      begin
        minEnd := 0;
        maxEnd := CLen;
      end;
      Check(0, minEnd, c20);
      Check(1, c20, c60);
      Check(2, c60, maxEnd);
    end;
end;

procedure TTyMultiTrackGeometryTest.TestSegmentSpanOutsideTheSegmentsIsFalse;
var
  lo, hi: Integer;
begin
  FBar.Put([20, 60]);
  AssertFalse('below segment 0', FBar.SegmentSpan(-1, 96, lo, hi));
  AssertFalse('past the last segment (ThumbCount)', FBar.SegmentSpan(3, 96, lo, hi));
  FBar.Put([]);
  AssertTrue('no thumbs: one segment, the whole groove', FBar.SegmentSpan(0, 96, lo, hi));
  AssertEquals(0, lo);
  AssertEquals(CLen, hi);
end;

procedure TTyMultiTrackGeometryTest.TestPreferredCrossSizeIsTheTrackBars;
var
  aw, ah, bw, bh, offH: Integer;
  b: TBGRABitmap;
begin
  FBar.Put([30, 70]);
  FBar.PreferredSize(aw, ah);
  FRef.PreferredSize(bw, bh);
  AssertEquals('labels off: same thickness', bh, ah);
  AssertEquals('across only', 0, aw);
  offH := ah;
  FBar.TickLabels := True;
  FRef.TickLabels := True;
  FBar.Frequency := 25;
  FRef.Frequency := 25;
  b := Shot(False); b.Free;      // the label strip is measured when the bar paints
  b := Shot(True); b.Free;
  FBar.PreferredSize(aw, ah);
  FRef.PreferredSize(bw, bh);
  AssertEquals('labels on: same thickness', bh, ah);
  AssertTrue('labels on: thicker than off', ah > offH);
  FBar.Orientation := toVertical;
  FRef.Orientation := toVertical;
  FBar.TickMarks := ttmBoth;
  FRef.TickMarks := ttmBoth;
  b := Shot(False); b.Free;
  b := Shot(True); b.Free;
  FBar.PreferredSize(aw, ah);
  FRef.PreferredSize(bw, bh);
  AssertEquals('vertical, both sides: same width', bw, aw);
  AssertEquals('vertical: along is free', 0, ah);
end;

{ TTyMultiTrackPaintTest }

function TMultiTrackPaintBase.GroovePx(B: TBGRABitmap; AMain: Integer): TBGRAPixel;
begin
  if FBar.Orientation = toVertical then Result := B.GetPixel(W div 2, AMain)
  else Result := B.GetPixel(AMain, H div 2);
end;

function TMultiTrackPaintBase.UnderAThumb(AMain: Integer): Boolean;
var
  i: Integer;
  r: TRect;
begin
  Result := False;
  for i := 0 to FBar.ThumbCount - 1 do
  begin
    r := FBar.ThumbRect(i);
    if FBar.Orientation = toVertical then
    begin
      if (AMain >= r.Top) and (AMain < r.Bottom) then Exit(True);
    end
    else if (AMain >= r.Left) and (AMain < r.Right) then Exit(True);
  end;
end;

function TMultiTrackPaintBase.ThumbPx(B: TBGRABitmap; AIndex: Integer): TBGRAPixel;
var
  r: TRect;
begin
  r := FBar.ThumbRect(AIndex);
  Result := B.GetPixel((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
end;

procedure TTyMultiTrackPaintTest.TestOneThumbDrawsWhatTheTrackBarDraws;
var
  ori: TTyTrackOrientation;
  rev, labels: Boolean;
  marks: TTyTrackTickMark;
  manual: Boolean;
  a, b: TBGRABitmap;
  x, y, diff, thumbInk, tickInk: Integer;
  where: string;
begin
  FBar.Put([30]);
  FBar.SetTick(5);  FBar.SetTick(33);  FBar.SetTick(90);
  FRef.SetTick(5);  FRef.SetTick(33);  FRef.SetTick(90);
  for ori := toHorizontal to toVertical do
    for rev := False to True do
      for marks := Low(TTyTrackTickMark) to High(TTyTrackTickMark) do
        for labels := False to True do
          for manual := False to True do
          begin
            Configure(ori, rev);
            if ori = toVertical then
            begin
              FBar.SetBounds(0, 0, 70, CLen);
              FRef.SetBounds(0, 0, 70, CLen);
            end
            else
            begin
              FBar.SetBounds(0, 0, CLen, 50);
              FRef.SetBounds(0, 0, CLen, 50);
            end;
            FBar.TickMarks := marks;
            FRef.TickMarks := marks;
            FBar.TickLabels := labels;
            FRef.TickLabels := labels;
            if manual then
            begin
              FBar.TickStyle := ttsManual;
              FRef.TickStyle := ttsManual;
            end
            else
            begin
              FBar.TickStyle := ttsAuto;
              FRef.TickStyle := ttsAuto;
              FBar.Frequency := 10;
              FRef.Frequency := 10;
            end;
            FRef.Position := 30;
            where := Format('ori=%d rev=%s marks=%d labels=%s manual=%s', [Ord(ori),
              BoolToStr(rev, True), Ord(marks), BoolToStr(labels, True), BoolToStr(manual, True)]);
            a := Shot(False);
            b := Shot(True);
            try
              diff := 0;
              thumbInk := 0;
              tickInk := 0;
              for y := 0 to H - 1 do
                for x := 0 to W - 1 do
                begin
                  if a.GetPixel(x, y) <> b.GetPixel(x, y) then Inc(diff);
                  if SamePx(a.GetPixel(x, y), $3B, $82, $F6) then Inc(thumbInk);
                  if SamePx(a.GetPixel(x, y), 0, 0, 0) then Inc(tickInk);
                end;
              AssertEquals(where + ': pixels that differ from TTyTrackBar', 0, diff);
              AssertTrue(where + ': the thumb is drawn', thumbInk > 0);
              AssertTrue(where + ': the ticks are drawn', tickInk > 0);
            finally
              a.Free;
              b.Free;
            end;
          end;
end;

procedure TTyMultiTrackPaintTest.TestEveryThumbSitsWhereTheTrackBarDrawsIt;
const
  V: array[0..2] of Integer = (10, 45, 80);
var
  ori: TTyTrackOrientation;
  rev: Boolean;
  a, b: TBGRABitmap;
  i, x, y, m, diff: Integer;
  r: TRect;
  where: string;
begin
  FBar.Put(V);
  FBar.Frequency := 10;
  FRef.Frequency := 10;
  for ori := toHorizontal to toVertical do
    for rev := False to True do
    begin
      Configure(ori, rev);
      where := Format('ori=%d rev=%s', [Ord(ori), BoolToStr(rev, True)]);
      a := Shot(False);
      try
        for i := 0 to High(V) do
        begin
          r := RefThumbRect(V[i]);
          b := Shot(True);
          try
            diff := 0;
            for y := r.Top to r.Bottom - 1 do
              for x := r.Left to r.Right - 1 do
                if a.GetPixel(x, y) <> b.GetPixel(x, y) then Inc(diff);
            AssertEquals(Format('%s: thumb %d is the track bar''s thumb at %d', [where, i, V[i]]),
              0, diff);
            AssertTrue(where + ': thumb ink at its middle',
              SamePx(ThumbPx(a, i), $3B, $82, $F6));
          finally
            b.Free;
          end;
        end;
        { Clear of every thumb, the two bars are the same picture: groove and ticks. }
        FRef.Position := V[0];
        b := Shot(True);
        try
          diff := 0;
          for y := 0 to H - 1 do
            for x := 0 to W - 1 do
            begin
              if ori = toVertical then m := y else m := x;
              if UnderAThumb(m) then Continue;
              if a.GetPixel(x, y) <> b.GetPixel(x, y) then Inc(diff);
            end;
          AssertEquals(where + ': off the thumbs, the groove and ticks are the track bar''s',
            0, diff);
        finally
          b.Free;
        end;
      finally
        a.Free;
      end;
    end;
end;

procedure TTyMultiTrackPaintTest.TestRangesAreFilledCentreToCentre;
var
  rev: Boolean;
  ori: TTyTrackOrientation;
  a: TBGRABitmap;
  m, lo1, hi1, lo3, hi3, red1, red3, misplaced, missing: Integer;
  inSpan, isRed: Boolean;
  where: string;
begin
  { Two ranges: 10..30 and 50..80 -- segments 1 and 3 are TTyRangeTrackBar's highlight. }
  FBar.Put([10, 30, 50, 80]);
  SetLength(FBar.SegKey, 5);
  FBar.SegKey[1] := TyTrackSelectionKey;
  FBar.SegKey[3] := TyTrackSelectionKey;
  FBar.TickStyle := ttsNone;
  for ori := toHorizontal to toVertical do
    for rev := False to True do
    begin
      Configure(ori, rev);
      where := Format('ori=%d rev=%s', [Ord(ori), BoolToStr(rev, True)]);
      AssertTrue(FBar.SegmentSpan(1, 96, lo1, hi1));
      AssertTrue(FBar.SegmentSpan(3, 96, lo3, hi3));
      a := Shot(False);
      try
        red1 := 0; red3 := 0; misplaced := 0; missing := 0;
        for m := 0 to CLen - 1 do
        begin
          if UnderAThumb(m) then Continue;
          isRed := SamePx(GroovePx(a, m), $FF, 0, 0);
          inSpan := ((m >= lo1) and (m < hi1)) or ((m >= lo3) and (m < hi3));
          if isRed and not inSpan then Inc(misplaced);
          if inSpan and not isRed then Inc(missing);
          if isRed and (m >= lo1) and (m < hi1) then Inc(red1);
          if isRed and (m >= lo3) and (m < hi3) then Inc(red3);
        end;
        AssertEquals(where + ': highlight outside a range (between ranges, before, after)', 0, misplaced);
        AssertEquals(where + ': a range pixel not highlighted', 0, missing);
        AssertTrue(where + ': the first range shows', red1 > 0);
        AssertTrue(where + ': the second range shows', red3 > 0);
      finally
        a.Free;
      end;
    end;
end;

procedure TTyMultiTrackPaintTest.TestSegmentsTakeTheirClassesBackground;
var
  a: TBGRABitmap;
  m, s, lo, hi, seen: Integer;
  px: TBGRAPixel;
  ok: Boolean;
begin
  { Four segments: go | (no style) | TyTrackSegment without a class | stop. }
  FBar.Put([20, 50, 80]);
  SetLength(FBar.SegKey, 4);
  SetLength(FBar.SegCls, 4);
  FBar.SegKey[0] := TyTrackSegmentKey;  FBar.SegCls[0] := 'go';
  FBar.SegKey[2] := TyTrackSegmentKey;
  FBar.SegKey[3] := TyTrackSegmentKey;  FBar.SegCls[3] := 'stop';
  FBar.TickStyle := ttsNone;
  a := Shot(False);
  try
    for s := 0 to 3 do
    begin
      AssertTrue(FBar.SegmentSpan(s, 96, lo, hi));
      seen := 0;
      for m := lo to hi - 1 do
      begin
        if UnderAThumb(m) then Continue;
        px := GroovePx(a, m);
        case s of
          0: ok := SamePx(px, 0, $C0, 0);
          3: ok := SamePx(px, $C0, $80, 0);
        else
          ok := SamePx(px, $60, $60, $60);   // the bare groove
        end;
        AssertTrue(Format('segment %d at %d: %s', [s, m, PxStr(px)]), ok);
        Inc(seen);
      end;
      AssertTrue('segment ' + IntToStr(s) + ' has pixels clear of the thumbs', seen > 0);
    end;
  finally
    a.Free;
  end;
end;

procedure TTyMultiTrackPaintTest.TestTheBaseThemeDrawsASegmentOnlyWithAClass;
var
  ctl: TTyStyleController;
  st: TTyStyleSet;
  cls: string;
begin
  ctl := TTyStyleController.Create(nil);
  try
    st := ctl.Model.ResolveStyle(TyTrackSegmentKey, '', []);
    AssertFalse('a segment without a class paints nothing', tpBackground in st.Present);
    for cls in TStringArray.Create('success', 'warning', 'danger') do
    begin
      st := ctl.Model.ResolveStyle(TyTrackSegmentKey, cls, []);
      AssertTrue('TyTrackSegment.' + cls + ' paints', tpBackground in st.Present);
    end;
  finally
    ctl.Free;
  end;
end;

procedure TTyMultiTrackPaintTest.TestAThumbColourReplacesTheThemeBackground;
var
  a: TBGRABitmap;
  px: TBGRAPixel;
begin
  FBar.Put([25, 75]);
  SetLength(FBar.Colors, 2);
  FBar.Colors[0] := clDefault;
  FBar.Colors[1] := RGBToColor($FF, $80, $00);
  a := Shot(False);
  try
    px := ThumbPx(a, 0);
    AssertTrue('clDefault follows the theme: ' + PxStr(px), SamePx(px, $3B, $82, $F6));
    px := ThumbPx(a, 1);
    AssertTrue('a colour is painted as given: ' + PxStr(px), SamePx(px, $FF, $80, $00));
  finally
    a.Free;
  end;
end;

procedure TTyMultiTrackPaintTest.TestAThumbStyleClassIsResolved;
var
  a: TBGRABitmap;
  px: TBGRAPixel;
begin
  FBar.Put([25, 75]);
  SetLength(FBar.ThumbCls, 2);
  FBar.ThumbCls[0] := 'big';
  a := Shot(False);
  try
    px := ThumbPx(a, 0);
    AssertTrue('TyTrackThumb.big: ' + PxStr(px), SamePx(px, $FF, $FF, $00));
    px := ThumbPx(a, 1);
    AssertTrue('no class: plain TyTrackThumb: ' + PxStr(px), SamePx(px, $3B, $82, $F6));
  finally
    a.Free;
  end;
end;

procedure TTyMultiTrackPaintTest.TestADisabledThumbIsDrawnAsUsual;
var
  a, b: TBGRABitmap;
  x, y, diff: Integer;
begin
  FBar.Put([20, 50, 80]);
  a := Shot(False);
  try
    SetLength(FBar.Off, 3);
    FBar.Off[1] := True;
    b := Shot(False);
    try
      AssertTrue('the disabled thumb is drawn', SamePx(ThumbPx(b, 1), $3B, $82, $F6));
      diff := 0;
      for y := 0 to H - 1 do
        for x := 0 to W - 1 do
          if a.GetPixel(x, y) <> b.GetPixel(x, y) then Inc(diff);
      AssertEquals('disabling a thumb changes no pixel', 0, diff);
    finally
      b.Free;
    end;
  finally
    a.Free;
  end;
end;
{ TMultiTrackInputBase }

procedure TMultiTrackInputBase.SetUp;
begin
  inherited SetUp;
  FLog := '';
  FBar.OnThumbChange := @Logged;
  FBar.OnThumbSelect := @Selected;
  FBar.OnChange := @Changed;
end;

procedure TMultiTrackInputBase.Logged(Sender: TObject; AIndex: Integer);
begin
  FLog := FLog + 'T' + IntToStr(AIndex) + ' ';
end;

procedure TMultiTrackInputBase.Selected(Sender: TObject; AIndex: Integer);
begin
  FLog := FLog + 'S' + IntToStr(AIndex) + ' ';
end;

procedure TMultiTrackInputBase.Changed(Sender: TObject);
begin
  FLog := FLog + 'C ';
end;

function TMultiTrackInputBase.Values: string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to FBar.ThumbCount - 1 do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + IntToStr(FBar.ThumbValues[i]);
  end;
end;

function TMultiTrackInputBase.At(AValue: Integer): TPoint;
var
  c: Integer;
begin
  c := RefCentre(AValue);
  if FBar.Orientation = toVertical then Result := Point(W div 2, c)
  else Result := Point(c, H div 2);
end;

function TMultiTrackInputBase.Shifted(const P: TPoint; ADelta: Integer): TPoint;
begin
  Result := P;
  if FBar.Orientation = toVertical then Inc(Result.Y, ADelta) else Inc(Result.X, ADelta);
end;

{ TTyMultiTrackMouseTest }

procedure TTyMultiTrackMouseTest.TestPressOnAThumbSelectsItWithoutMovingIt;
var
  p: TPoint;
begin
  FBar.Put([20, 50, 80]);
  FLog := '';
  p := Shifted(At(50), 4);         // off its centre, still on it
  FBar.Press(p.X, p.Y);
  AssertEquals('selected', 1, FBar.SelectedThumb);
  AssertEquals('not moved', '20,50,80', Values);
  AssertEquals('only the selection is reported', 'S1 ', FLog);
  FBar.Drag(p.X, p.Y);
  AssertEquals('held where it was grabbed: a drag that goes nowhere moves nothing', '20,50,80',
    Values);
  FBar.Release(p.X, p.Y);
  AssertEquals('20,50,80', Values);
end;

procedure TTyMultiTrackMouseTest.TestWhereThumbsOverlapTheNearestCentreWins;
var
  p: TPoint;
begin
  FBar.Put([50, 52]);
  p := At(52);
  AssertTrue('the fixture overlaps: the point is on both thumbs',
    PtInRect(FBar.ThumbRect(0), p) and PtInRect(FBar.ThumbRect(1), p));
  FBar.Press(p.X, p.Y);
  FBar.Release(p.X, p.Y);
  AssertEquals('on thumb 1''s centre', 1, FBar.SelectedThumb);
  p := At(50);
  AssertTrue(PtInRect(FBar.ThumbRect(1), p));
  FBar.Press(p.X, p.Y);
  FBar.Release(p.X, p.Y);
  AssertEquals('on thumb 0''s centre', 0, FBar.SelectedThumb);
  AssertEquals('pressing picks, it does not move', '50,52', Values);
end;

procedure TTyMultiTrackMouseTest.TestDragMovesOnlyThatThumb;
var
  p, q: TPoint;
begin
  FBar.Put([20, 50, 80]);
  p := At(50);
  q := At(65);
  FBar.Press(p.X, p.Y);
  FLog := '';
  FBar.Drag(q.X, q.Y);
  AssertEquals('20,65,80', Values);
  AssertEquals('the dragged thumb reports, then OnChange', 'T1 C ', FLog);
  FBar.Release(q.X, q.Y);
  p := At(30);
  FBar.Hover(p.X, p.Y);
  AssertEquals('after the release the pointer moves nothing', '20,65,80', Values);
end;

procedure TTyMultiTrackMouseTest.TestADragStopsMinGapFromTheNeighbours;
var
  p, q: TPoint;
begin
  FBar.MinGap := 5;
  FBar.Put([20, 50, 80]);
  p := At(50);
  FBar.Press(p.X, p.Y);
  q := At(95);
  FBar.Drag(q.X, q.Y);
  AssertEquals('stops MinGap left of the right neighbour', '20,75,80', Values);
  q := At(3);
  FBar.Drag(q.X, q.Y);
  AssertEquals('stops MinGap right of the left neighbour', '20,25,80', Values);
  FBar.Release(q.X, q.Y);
end;

procedure TTyMultiTrackMouseTest.TestADragFollowsTheDirectionOfTheBar;
var
  ori: TTyTrackOrientation;
  rev: Boolean;
  p, q: TPoint;
  where: string;
begin
  for ori := toHorizontal to toVertical do
    for rev := False to True do
    begin
      Configure(ori, rev);
      FBar.Put([20, 60]);
      where := Format('ori=%d rev=%s', [Ord(ori), BoolToStr(rev, True)]);
      p := At(20);
      q := At(40);
      FBar.Press(p.X, p.Y);
      FBar.Drag(q.X, q.Y);
      FBar.Release(q.X, q.Y);
      AssertEquals(where, '40,60', Values);
    end;
end;

procedure TTyMultiTrackMouseTest.TestAPressOnTheGrooveBringsTheNearestThumb;
var
  p, q: TPoint;
begin
  FBar.Put([20, 60]);
  p := At(35);
  FBar.Press(p.X, p.Y);
  AssertEquals('the thumb at 20 is nearer to 35', '35,60', Values);
  AssertEquals(0, FBar.SelectedThumb);
  q := At(30);
  FBar.Drag(q.X, q.Y);
  AssertEquals('and the press drags it on', '30,60', Values);
  FBar.Release(q.X, q.Y);
  p := At(52);
  FBar.Press(p.X, p.Y);
  FBar.Release(p.X, p.Y);
  AssertEquals('the thumb at 60 is nearer to 52', '30,52', Values);
  AssertEquals(1, FBar.SelectedThumb);
end;

procedure TTyMultiTrackMouseTest.TestEquidistantPressTakesTheLowerValue;
var
  rev: Boolean;
  p: TPoint;
begin
  for rev := False to True do
  begin
    Configure(toHorizontal, rev);
    FBar.Put([20, 60]);
    FBar.SelectedThumb := -1;
    p := At(40);
    FBar.Press(p.X, p.Y);
    FBar.Release(p.X, p.Y);
    AssertEquals('rev=' + BoolToStr(rev, True) + ': 40 is as far from both', '40,60', Values);
    AssertEquals(0, FBar.SelectedThumb);
  end;
end;

procedure TTyMultiTrackMouseTest.TestAJumpSkipsDisabledThumbs;
var
  p: TPoint;
begin
  FBar.Put([20, 60]);
  SetLength(FBar.Off, 2);
  FBar.Off[0] := True;
  p := At(28);
  FBar.Press(p.X, p.Y);
  FBar.Release(p.X, p.Y);
  AssertEquals('the enabled thumb comes, though the other is nearer', '20,28', Values);
  AssertEquals(1, FBar.SelectedThumb);
end;

procedure TTyMultiTrackMouseTest.TestADisabledThumbIsInert;
var
  p, q: TPoint;
  a: TBGRABitmap;
begin
  FBar.Put([20, 50, 80]);
  SetLength(FBar.Off, 3);
  FBar.Off[1] := True;
  FBar.SelectedThumb := 0;
  FLog := '';
  p := At(50);
  FBar.Hover(p.X, p.Y);
  a := Shot(False);
  try
    AssertTrue('no hover on a disabled thumb: ' + PxStr(ThumbPx(a, 1)),
      SamePx(ThumbPx(a, 1), $3B, $82, $F6));
  finally
    a.Free;
  end;
  FBar.Press(p.X, p.Y);
  q := At(65);
  FBar.Drag(q.X, q.Y);
  FBar.Release(q.X, q.Y);
  AssertEquals('nothing moved', '20,50,80', Values);
  AssertEquals('the selection stayed where it was', 0, FBar.SelectedThumb);
  AssertEquals('no event at all', '', FLog);
end;

procedure TTyMultiTrackMouseTest.TestHoverAndPressArePaintedOnThatThumbOnly;
var
  p: TPoint;
  a: TBGRABitmap;
begin
  FBar.Put([20, 50, 80]);
  p := At(50);
  FBar.Hover(p.X, p.Y);
  a := Shot(False);
  try
    AssertTrue('hovered: ' + PxStr(ThumbPx(a, 1)), SamePx(ThumbPx(a, 1), 0, $FF, $FF));
    AssertTrue('the others plain: ' + PxStr(ThumbPx(a, 0)), SamePx(ThumbPx(a, 0), $3B, $82, $F6));
  finally
    a.Free;
  end;
  FBar.Press(p.X, p.Y);
  a := Shot(False);
  try
    AssertTrue('pressed: ' + PxStr(ThumbPx(a, 1)), SamePx(ThumbPx(a, 1), $80, 0, $FF));
    AssertTrue('the others plain: ' + PxStr(ThumbPx(a, 2)), SamePx(ThumbPx(a, 2), $3B, $82, $F6));
  finally
    a.Free;
  end;
  FBar.Release(p.X, p.Y);
  FBar.Leave;
  a := Shot(False);
  try
    AssertTrue('released and left: ' + PxStr(ThumbPx(a, 1)), SamePx(ThumbPx(a, 1), $3B, $82, $F6));
  finally
    a.Free;
  end;
end;

procedure TTyMultiTrackMouseTest.TestThumbsOnOneValueComeApartInTheDragDirection;
var
  p, q: TPoint;
begin
  FBar.Put([0, 0]);
  p := At(0);
  FBar.Press(p.X, p.Y);
  q := At(30);
  FBar.Drag(q.X, q.Y);
  FBar.Release(q.X, q.Y);
  AssertEquals('a pile at Min: dragging right takes the upper thumb', '0,30', Values);
  AssertEquals(1, FBar.SelectedThumb);
  FBar.Put([100, 100]);
  p := At(100);
  FBar.Press(p.X, p.Y);
  q := At(70);
  FBar.Drag(q.X, q.Y);
  FBar.Release(q.X, q.Y);
  AssertEquals('a pile at Max: dragging left takes the lower thumb', '70,100', Values);
end;

procedure TTyMultiTrackMouseTest.TestADisabledBarIgnoresTheMouse;
var
  p: TPoint;
begin
  FBar.Put([20, 60]);
  FBar.Enabled := False;
  p := At(35);
  FBar.Press(p.X, p.Y);
  FBar.Release(p.X, p.Y);
  AssertEquals('20,60', Values);
  AssertEquals(-1, FBar.SelectedThumb);
end;

procedure TTyMultiTrackMouseTest.TestTheHintIsTheThumbsUnderThePointer;
var
  r: TRect;
  p: TPoint;
begin
  FBar.Hint := 'bar';
  FBar.Put([20, 50, 80]);
  SetLength(FBar.Hints, 3);
  FBar.Hints[0] := 'low';
  FBar.Hints[2] := 'high';
  p := At(20);
  AssertEquals('over a thumb with a hint', 'low', FBar.HintAt(p.X, p.Y, r));
  AssertTrue('leaving that thumb asks again', EqualRect(r, FBar.ThumbRect(0)));
  p := At(80);
  AssertEquals('high', FBar.HintAt(p.X, p.Y, r));
  p := At(50);
  AssertEquals('a thumb without one: the control''s', 'bar', FBar.HintAt(p.X, p.Y, r));
  p := At(35);
  AssertEquals('between thumbs: the control''s', 'bar', FBar.HintAt(p.X, p.Y, r));
  AssertEquals('the gap ends where thumb 0 does', FBar.ThumbRect(0).Right, r.Left);
  AssertEquals('and starts where thumb 1 does', FBar.ThumbRect(1).Left, r.Right);
end;

{ TTyMultiTrackKeyboardTest }

procedure TTyMultiTrackKeyboardTest.TestArrowsStepTheSelectedThumb;
var
  ori: TTyTrackOrientation;
  where: string;
begin
  for ori := toHorizontal to toVertical do
  begin
    Configure(ori, False);
    where := 'ori=' + IntToStr(Ord(ori));
    FBar.Put([20, 50, 80]);
    FBar.SelectedThumb := 1;
    FBar.LineSize := 2;
    AssertEquals(where + ': consumed', 0, FBar.Key(VK_RIGHT));
    AssertEquals(where + ': right increases', '20,52,80', Values);
    FBar.Key(VK_UP);
    AssertEquals(where + ': up increases', '20,54,80', Values);
    FBar.Key(VK_LEFT);
    AssertEquals(where + ': left decreases', '20,52,80', Values);
    FBar.Key(VK_DOWN);
    AssertEquals(where + ': down decreases', '20,50,80', Values);
  end;
end;

procedure TTyMultiTrackKeyboardTest.TestPagesAndEndsStopAtTheNeighbours;
begin
  FBar.MinGap := 5;
  FBar.Put([20, 50, 80]);
  FBar.SelectedThumb := 1;
  FBar.Key(VK_PRIOR);
  AssertEquals('PageUp adds PageSize', '20,60,80', Values);
  FBar.Key(VK_NEXT);
  FBar.Key(VK_NEXT);
  AssertEquals('PageDown takes it off', '20,40,80', Values);
  FBar.Key(VK_HOME);
  AssertEquals('Home: as low as the left neighbour lets', '20,25,80', Values);
  FBar.Key(VK_END);
  AssertEquals('End: as high as the right neighbour lets', '20,75,80', Values);
  FBar.SelectedThumb := 0;
  FBar.Key(VK_HOME);
  FBar.SelectedThumb := 2;
  FBar.Key(VK_END);
  AssertEquals('the outer thumbs reach Min and Max', '0,75,100', Values);
end;

procedure TTyMultiTrackKeyboardTest.TestWithNoSelectionTheFirstEnabledThumbMoves;
begin
  FBar.Put([20, 50, 80]);
  SetLength(FBar.Off, 3);
  FBar.Off[0] := True;
  FLog := '';
  FBar.Key(VK_RIGHT);
  AssertEquals('20,51,80', Values);
  AssertEquals('and it becomes the selected one', 1, FBar.SelectedThumb);
  AssertEquals('S1 T1 C ', FLog);
end;

procedure TTyMultiTrackKeyboardTest.TestAKeyMovesNothingWhenEveryThumbIsDisabled;
var
  k: Word;
begin
  FBar.Put([20, 50]);
  SetLength(FBar.Off, 2);
  FBar.Off[0] := True;
  FBar.Off[1] := True;
  FBar.SelectedThumb := 1;
  k := FBar.Key(VK_RIGHT);
  AssertEquals('20,50', Values);
  AssertEquals('not consumed', VK_RIGHT, k);
  AssertEquals('no Tab wanted', 0, FBar.WantsKey(VK_TAB));
end;

procedure TTyMultiTrackKeyboardTest.TestADisabledBarIgnoresTheKeys;
begin
  FBar.Put([20, 50]);
  FBar.SelectedThumb := 0;
  FBar.Enabled := False;
  FBar.Key(VK_RIGHT);
  AssertEquals('20,50', Values);
  AssertEquals('nor wants Tab', 0, FBar.WantsKey(VK_TAB));
end;

procedure TTyMultiTrackKeyboardTest.TestTabWalksTheEnabledThumbsThenLeaves;
begin
  FBar.Put([20, 50, 80]);
  SetLength(FBar.Off, 3);
  FBar.Off[1] := True;
  FBar.SelectedThumb := 0;
  FLog := '';
  AssertEquals('a thumb follows: the bar wants Tab', 1, FBar.WantsKey(VK_TAB));
  AssertEquals('Tab consumed', 0, FBar.Key(VK_TAB));
  AssertEquals('the disabled thumb is skipped', 2, FBar.SelectedThumb);
  AssertEquals('S2 ', FLog);
  AssertEquals('after the last: Tab goes to the form', 0, FBar.WantsKey(VK_TAB));
  FBar.HoldShift := True;
  AssertEquals('Shift+Tab has a thumb to go back to', 1, FBar.WantsKey(VK_TAB));
  FBar.Key(VK_TAB, [ssShift]);
  AssertEquals('Shift+Tab goes back', 0, FBar.SelectedThumb);
  AssertEquals('before the first: Shift+Tab goes to the form', 0, FBar.WantsKey(VK_TAB));
  FBar.HoldShift := False;
  FBar.SelectedThumb := -1;
  AssertEquals('none selected: Tab starts after the first enabled thumb', 1, FBar.WantsKey(VK_TAB));
  AssertEquals('other special keys are the form''s', 0, FBar.WantsKey(VK_RETURN));
end;

procedure TTyMultiTrackKeyboardTest.TestEnteringFromTheKeyboardStartsAtTheNearEnd;
begin
  FBar.Put([20, 50, 80, 90]);
  SetLength(FBar.Off, 4);
  FBar.Off[0] := True;
  FBar.Off[3] := True;
  FBar.SelectedThumb := 2;
  FLog := '';
  FBar.Enter;
  AssertEquals('Tab in: the first enabled thumb, not the one selected before', 1,
    FBar.SelectedThumb);
  AssertEquals('S1 ', FLog);
  AssertEquals('so the next Tab still has a thumb to go to', 1, FBar.WantsKey(VK_TAB));
  FBar.HoldShift := True;
  FBar.Enter;
  AssertEquals('Shift+Tab in: the last enabled thumb', 2, FBar.SelectedThumb);
  AssertEquals('so Shift+Tab still has a thumb to go back to', 1, FBar.WantsKey(VK_TAB));
  FBar.HoldShift := False;
  FBar.HoldMouse := True;
  FBar.SelectedThumb := 2;     // not the first enabled thumb: a reset would show
  FLog := '';
  FBar.Enter;
  AssertEquals('entered by a click: the press picks, the focus does not', 2, FBar.SelectedThumb);
  AssertEquals('', FLog);
  FBar.HoldMouse := False;
  FBar.Off[1] := True;
  FBar.Off[2] := True;
  FBar.Enter;
  AssertEquals('no enabled thumb: the selection is left alone', 2, FBar.SelectedThumb);
end;

procedure TTyMultiTrackKeyboardTest.WheelSwallowed(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  Handled := True;
end;

procedure TTyMultiTrackKeyboardTest.TestTheWheelStepsTheKeyboardsThumb;
begin
  FBar.Put([20, 50, 80]);
  FBar.LineSize := 2;
  FBar.SelectedThumb := 1;
  FLog := '';
  AssertTrue('handled', FBar.Wheel(120));
  AssertEquals('wheel-up increases the selected thumb by LineSize', '20,52,80', Values);
  AssertEquals('T1 C ', FLog);
  FBar.Wheel(-120);
  AssertEquals('wheel-down decreases it', '20,50,80', Values);
  { None selected: the first enabled thumb, which becomes the selected one -- as a key. }
  SetLength(FBar.Off, 3);
  FBar.Off[0] := True;
  FBar.SelectedThumb := -1;
  FBar.Wheel(120);
  AssertEquals('20,52,80', Values);
  AssertEquals(1, FBar.SelectedThumb);
  { An OnMouseWheel handler that handles the wheel stops the step, as on TTyTrackBar. }
  FBar.OnMouseWheel := @WheelSwallowed;
  FBar.Wheel(120);
  AssertEquals('handled by the application: nothing moves', '20,52,80', Values);
  FBar.OnMouseWheel := nil;
  FBar.Enabled := False;
  AssertFalse('a disabled bar leaves the wheel to its parent', FBar.Wheel(120));
  AssertEquals('20,52,80', Values);
end;

{ TMultiTrackFinalBase }

procedure TMultiTrackFinalBase.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(CPaintCss);
  FForm := TForm.CreateNew(nil);
  FForm.Name := 'HostForm';
  FForm.SetBounds(0, 0, 640, 480);
  FLog := '';
end;

procedure TMultiTrackFinalBase.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

procedure TMultiTrackFinalBase.ThumbMoved(Sender: TObject; AIndex: Integer);
begin
  FLog := FLog + 'T' + IntToStr(AIndex) + ' ';
end;

procedure TMultiTrackFinalBase.Changed(Sender: TObject);
begin
  FLog := FLog + 'C ';
end;

function TMultiTrackFinalBase.ValuesOf(ABar: TTyMultiTrackBarBase): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to ABar.ThumbCount - 1 do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + IntToStr(ABar.ThumbValues[i]);
  end;
end;

function TMultiTrackFinalBase.FormText(AHost: TForm): string;
var
  ms: TMemoryStream;
  ts: TStringStream;
begin
  ms := TMemoryStream.Create;
  ts := TStringStream.Create('');
  try
    ms.WriteComponent(AHost);
    ms.Position := 0;
    ObjectBinaryToText(ms, ts);
    Result := ts.DataString;
  finally
    ts.Free;
    ms.Free;
  end;
end;

function TMultiTrackFinalBase.FromText(const AText: string): TForm;
var
  ts: TStringStream;
  bs: TMemoryStream;
begin
  Result := TForm.CreateNew(nil);
  ts := TStringStream.Create(AText);
  bs := TMemoryStream.Create;
  try
    ObjectTextToBinary(ts, bs);
    bs.Position := 0;
    bs.ReadComponent(Result);
  finally
    bs.Free;
    ts.Free;
  end;
end;

function TMultiTrackFinalBase.RoundTrip(AHost: TForm): TForm;
var
  ms: TMemoryStream;
begin
  Result := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    ms.WriteComponent(AHost);
    ms.Position := 0;
    ms.ReadComponent(Result);
  finally
    ms.Free;
  end;
end;

function TMultiTrackFinalBase.BarText(const AText: string): string;
begin
  Result := Copy(AText, Pos('object Bar:', AText), MaxInt);
  AssertTrue('the form file holds the bar', Result <> '');
end;

function TMultiTrackFinalBase.Shot(ABar: TTyMultiTrackBarBase): TBGRABitmap;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(ABar.Width, ABar.Height);
    bmp.Canvas.Brush.Color := RGBToColor(255, 0, 255);
    bmp.Canvas.FillRect(0, 0, ABar.Width, ABar.Height);
    TBaseAccess(ABar).RenderTo(bmp.Canvas, Rect(0, 0, ABar.Width, ABar.Height), 96);
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

function TMultiTrackFinalBase.UnderAThumb(ABar: TTyMultiTrackBarBase; AMain: Integer): Boolean;
var
  i: Integer;
  r: TRect;
begin
  Result := False;
  for i := 0 to ABar.ThumbCount - 1 do
  begin
    r := ABar.ThumbRect(i);
    if (AMain >= r.Left) and (AMain < r.Right) then Exit(True);
  end;
end;

{ TTyRangeTrackBarTest }

procedure TTyRangeTrackBarTest.SetUp;
begin
  inherited SetUp;
  FBar := TTyRangeTrackBar.Create(FForm);
  FBar.Name := 'Bar';
  FBar.Parent := FForm;
  FBar.Font.PixelsPerInch := 96;
  FBar.SetBounds(0, 0, 400, 24);
  FSeen := '';
end;

function TTyRangeTrackBarTest.Values: string;
begin
  Result := ValuesOf(FBar);
end;

function TTyRangeTrackBarTest.RangesText(ABar: TTyRangeTrackBar): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to ABar.Ranges.Count - 1 do
  begin
    if i > 0 then Result := Result + ';';
    Result := Result + IntToStr(ABar.Ranges[i].Low) + '..' + IntToStr(ABar.Ranges[i].High);
  end;
end;

procedure TTyRangeTrackBarTest.ReadTheRangeInTheEvent(Sender: TObject; AIndex: Integer);
begin
  { What a handler reads from the collection while the thumb's event fires. }
  FSeen := FSeen + Format('%d:%s=%d ', [AIndex, RangesText(FBar), FBar.ThumbValues[AIndex]]);
end;

procedure TTyRangeTrackBarTest.TestDefaults;
begin
  AssertEquals('one range, so a new bar shows one', 1, FBar.Ranges.Count);
  AssertEquals('25..75', RangesText(FBar));
  AssertEquals('its two thumbs', '25,75', Values);
  AssertEquals(25, FBar.LowValue);
  AssertEquals(75, FBar.HighValue);
  AssertEquals('Min', 0, FBar.Min);
  AssertEquals('Max', 100, FBar.Max);
  AssertEquals('MinGap', 0, FBar.MinGap);
  AssertEquals('no thumb selected', -1, FBar.SelectedThumb);
  AssertTrue('focusable', FBar.TabStop);
end;

procedure TTyRangeTrackBarTest.TestTheTypeKeyHangsOnTheTrackBars;
var
  ctl: TTyStyleController;
  ref: TTyTrackBar;
begin
  AssertEquals('TyRangeTrackBar', (FBar as ITyStyleable).GetStyleTypeKey);
  AssertEquals('registered under the track bar''s key', 'TyTrackBar',
    TyTypeKeyParent('TyRangeTrackBar'));
  { What the chain is for: a theme that styles only TyTrackBar styles the range bar too, and a
    rule of its own wins over it. }
  ctl := TTyStyleController.Create(nil);
  ref := TTyTrackBar.Create(FForm);
  try
    ctl.LoadThemeCss('TyTrackBar { color: #123456; border-width: 1px; }'
      + 'TyRangeTrackBar { border-width: 3px; }');
    FBar.Controller := ctl;
    ref.Parent := FForm;
    ref.Controller := ctl;
    AssertEquals('the track bar''s rule reaches the range bar',
      TTrackAccess(ref).CurrentStyle.TextColor, TRangeAccess(FBar).CurrentStyle.TextColor);
    AssertEquals('its own rule wins', 3, TRangeAccess(FBar).CurrentStyle.BorderWidth);
    AssertEquals('and stays its own', 1, TTrackAccess(ref).CurrentStyle.BorderWidth);
  finally
    FBar.Controller := nil;
    ref.Free;
    ctl.Free;
  end;
end;

procedure TTyRangeTrackBarTest.TestLowValueAndHighValueAreTheFirstRange;
begin
  FBar.Ranges.Clear;
  AssertEquals('no range: no thumbs', 0, FBar.ThumbCount);
  AssertEquals('no range reads 0', 0, FBar.LowValue);
  AssertEquals(0, FBar.HighValue);
  FBar.LowValue := 10;
  AssertEquals('writing adds a range first', 1, FBar.Ranges.Count);
  AssertEquals('10,100', Values);
  FBar.HighValue := 40;
  AssertEquals('10..40', RangesText(FBar));
  FBar.Ranges.Clear;
  FBar.HighValue := 40;
  AssertEquals('HighValue adds one too, Min..Max to start from', '0..40', RangesText(FBar));
  { With two ranges they are the first one's ends. }
  FBar.Ranges.Add.Low := 70;
  FBar.LowValue := 20;
  AssertEquals('20..40;70..100', RangesText(FBar));
  FBar.HighValue := 50;
  AssertEquals('20..50;70..100', RangesText(FBar));
  AssertEquals(20, FBar.LowValue);
  AssertEquals(50, FBar.HighValue);
end;

procedure TTyRangeTrackBarTest.TestARangeEndMovesThroughTheModel;
begin
  FBar.MinGap := 5;
  FBar.OnThumbChange := @ThumbMoved;
  FBar.OnChange := @Changed;
  FBar.Ranges[0].High := 10;
  AssertEquals('stops MinGap above Low, as a drag would', '25..30', RangesText(FBar));
  AssertEquals('and reports the thumb that moved', 'T1 C ', FLog);
  FLog := '';
  FBar.Ranges[0].Low := -50;
  AssertEquals('inside Min', '0..30', RangesText(FBar));
  FLog := '';
  FBar.Ranges[0].Low := 0;
  AssertEquals('the same value fires nothing', '', FLog);
  { A range added at the end takes the stretch after the last one; MinGap holds between two
    ranges as well. }
  FBar.Ranges.Add;
  AssertEquals('0..30;35..100', RangesText(FBar));
  FBar.Ranges[1].Low := 40;
  AssertEquals('0..30;40..100', RangesText(FBar));
  FBar.Ranges[1].Low := 20;
  AssertEquals('stops MinGap above the range before it', '0..30;35..100', RangesText(FBar));
  AssertEquals('0,30,35,100', Values);
end;

procedure TTyRangeTrackBarTest.TestBeginUpdateHoldsTheValuesUntilEndUpdate;
begin
  FBar.Ranges.BeginUpdate;
  FBar.Ranges[0].Low := 90;
  FBar.Ranges[0].High := 10;
  AssertEquals('kept as given meanwhile', '90..10', RangesText(FBar));
  AssertEquals('the thumbs wait', '25,75', Values);
  FBar.Ranges.EndUpdate;
  AssertEquals('sorted out at EndUpdate', '10..90', RangesText(FBar));
  AssertEquals('10,90', Values);
end;

procedure TTyRangeTrackBarTest.TestSeveralRangesInOrderAndHighlighted;
var
  a: TBGRABitmap;
  m, s, lo, hi, red, misplaced, missing: Integer;
  inSpan, isRed: Boolean;
  px: TBGRAPixel;
  spanLo, spanHi: array[0..6] of Integer;
begin
  FBar.Controller := FCtl;
  FBar.Max := 12;
  FBar.TickStyle := ttsNone;
  FBar.Ranges.BeginUpdate;
  try
    FBar.Ranges.Clear;
    with FBar.Ranges.Add do begin Low := 1; High := 3; end;
    with FBar.Ranges.Add do begin Low := 8; High := 12; end;
    with FBar.Ranges.Add do begin Low := 4; High := 6; end;
  finally
    FBar.Ranges.EndUpdate;
  end;
  AssertEquals('the thumbs in order: each range''s Low then High', '1,3,4,6,8,12', Values);
  AssertEquals('1..3;4..6;8..12', RangesText(FBar));
  for s := 0 to 6 do
    AssertTrue(FBar.SegmentSpan(s, 96, spanLo[s], spanHi[s]));
  a := Shot(FBar);
  try
    misplaced := 0;
    missing := 0;
    for m := 0 to FBar.Width - 1 do
    begin
      if UnderAThumb(FBar, m) then Continue;
      px := a.GetPixel(m, FBar.Height div 2);
      isRed := SamePx(px, $FF, 0, 0);
      inSpan := False;
      for s := 0 to 6 do
        if Odd(s) and (m >= spanLo[s]) and (m < spanHi[s]) then inSpan := True;
      if isRed and not inSpan then Inc(misplaced);
      if inSpan and not isRed then Inc(missing);
      if not isRed then
        AssertTrue(Format('off a range at %d: the bare groove, %s', [m, PxStr(px)]),
          SamePx(px, $60, $60, $60));
    end;
    AssertEquals('highlight outside a range (before, between, after)', 0, misplaced);
    AssertEquals('a range pixel not highlighted', 0, missing);
    for s := 0 to 6 do
    begin
      lo := spanLo[s];
      hi := spanHi[s];
      red := 0;
      for m := lo to hi - 1 do
        if not UnderAThumb(FBar, m) and SamePx(a.GetPixel(m, FBar.Height div 2), $FF, 0, 0) then
          Inc(red);
      if Odd(s) then
        AssertTrue('range ' + IntToStr(s div 2) + ' shows', red > 0)
      else
        AssertEquals('segment ' + IntToStr(s) + ' is not a range', 0, red);
    end;
  finally
    a.Free;
  end;
end;

const
  { A form file as a hand (or an older writer) may leave it: ranges out of order, one inside
    out, listed before Min and Max. }
  CRangeForm =
    'object HostForm: TForm'#10 +
    '  Left = 0'#10 +
    '  Top = 0'#10 +
    '  Width = 640'#10 +
    '  Height = 480'#10 +
    '  object Bar: TTyRangeTrackBar'#10 +
    '    Left = 0'#10 +
    '    Top = 0'#10 +
    '    Width = 400'#10 +
    '    Height = 24'#10 +
    '    Ranges = <'#10 +
    '%s' +
    '>'#10 +
    '    Min = 0'#10 +
    '    Max = 100'#10 +
    '  end'#10 +
    'end'#10;

function RangeItem(ALow, AHigh: Integer): string;
begin
  Result := Format('      item'#10'        Low = %d'#10'        High = %d'#10'      end'#10,
    [ALow, AHigh]);
end;

procedure TTyRangeTrackBarTest.TestAFormsRangesAreSortedWhenRead;
var
  host: TForm;
  bar: TTyRangeTrackBar;
begin
  host := FromText(Format(CRangeForm, [RangeItem(50, 60) + RangeItem(20, 10)]));
  try
    bar := host.FindComponent('Bar') as TTyRangeTrackBar;
    AssertEquals('out of order, inside out: sorted and paired off', '10,20,50,60', ValuesOf(bar));
    AssertEquals('10..20;50..60', RangesText(bar));
  finally
    host.Free;
  end;
  host := FromText(Format(CRangeForm, [RangeItem(10, 50) + RangeItem(20, 30)]));
  try
    bar := host.FindComponent('Bar') as TTyRangeTrackBar;
    AssertEquals('overlapping: the values sorted as one list', '10..20;30..50', RangesText(bar));
  finally
    host.Free;
  end;
end;

procedure TTyRangeTrackBarTest.TestADraggedEndIsReadFromItsRange;
var
  r: TRect;
  x, y: Integer;
begin
  FBar.OnThumbChange := @ReadTheRangeInTheEvent;
  r := FBar.ThumbRect(1);
  x := (r.Left + r.Right) div 2;
  y := (r.Top + r.Bottom) div 2;
  TRangeAccess(FBar).MouseDown(mbLeft, [ssLeft], x, y);
  TRangeAccess(FBar).MouseMove([ssLeft], x + 60, y);
  TRangeAccess(FBar).MouseUp(mbLeft, [], x + 60, y);
  AssertTrue('the High thumb moved up: ' + Values, FBar.ThumbValues[1] > 75);
  AssertEquals('the range reads where the thumb went', FBar.ThumbValues[1], FBar.Ranges[0].High);
  AssertEquals('Low untouched', 25, FBar.Ranges[0].Low);
  AssertEquals('a handler reads the range already moved',
    Format('1:25..%d=%d ', [FBar.ThumbValues[1], FBar.ThumbValues[1]]), FSeen);
end;

procedure TTyRangeTrackBarTest.TestRangesRoundTripThroughAFormFile;
var
  host: TForm;
  bar: TTyRangeTrackBar;
  txt: string;
begin
  FBar.Min := -10;
  FBar.Max := 50;
  FBar.MinGap := 2;
  FBar.Ranges.Add;
  FBar.Ranges[0].Low := -5;
  FBar.Ranges[0].High := 0;
  FBar.Ranges[1].Low := 10;
  FBar.Ranges[1].High := 20;
  AssertEquals('the fixture', '-5..0;10..20', RangesText(FBar));
  txt := FormText(FForm);
  AssertTrue('the ranges are written: ' + txt, Pos('Ranges = <', txt) > 0);
  AssertFalse('no marker while there are ranges', Pos('NoRanges', txt) > 0);
  host := RoundTrip(FForm);
  try
    bar := host.FindComponent('Bar') as TTyRangeTrackBar;
    AssertEquals('read back', '-5..0;10..20', RangesText(bar));
    AssertEquals('-5,0,10,20', ValuesOf(bar));
    AssertEquals(2, bar.MinGap);
    AssertEquals(-10, bar.Min);
    AssertEquals(50, bar.Max);
    AssertEquals('and written again the same', BarText(txt), BarText(FormText(host)));
  finally
    host.Free;
  end;
end;

procedure TTyRangeTrackBarTest.TestNoRangesRoundTrips;
var
  host: TForm;
  bar: TTyRangeTrackBar;
  txt: string;
begin
  FBar.Ranges.Clear;
  txt := FormText(FForm);
  AssertTrue('an emptied bar says so: ' + txt, Pos('NoRanges = True', txt) > 0);
  host := RoundTrip(FForm);
  try
    bar := host.FindComponent('Bar') as TTyRangeTrackBar;
    AssertEquals('read back without the default range', 0, bar.Ranges.Count);
    AssertEquals(0, bar.ThumbCount);
  finally
    host.Free;
  end;
end;

{ TMultiCounting }

procedure TMultiCounting.Invalidate;
begin
  Inc(Invalidations);
  inherited Invalidate;
end;

{ TTyMultiTrackBarTest }

procedure TTyMultiTrackBarTest.SetUp;
begin
  inherited SetUp;
  FBar := TTyMultiTrackBar.Create(FForm);
  FBar.Name := 'Bar';
  FBar.Parent := FForm;
  FBar.Font.PixelsPerInch := 96;
  FBar.SetBounds(0, 0, 400, 24);
end;

function TTyMultiTrackBarTest.Values: string;
begin
  Result := ValuesOf(FBar);
end;

function TTyMultiTrackBarTest.ThumbsText(ABar: TTyMultiTrackBar): string;
var
  i: Integer;
  t: TTyTrackThumbItem;
  c: string;
begin
  Result := '';
  for i := 0 to ABar.Thumbs.Count - 1 do
  begin
    t := ABar.Thumbs[i];
    if t.Color = clDefault then c := 'def' else c := Format('$%x', [t.Color]);
    if i > 0 then Result := Result + ';';
    Result := Result + Format('%d:%s:%s:%s:%s', [t.Value, c, t.Hint,
      BoolToStr(t.Enabled, '+', '-'), t.StyleClass]);
  end;
end;

function TTyMultiTrackBarTest.SegmentsText(ABar: TTyMultiTrackBar): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to ABar.Segments.Count - 1 do
  begin
    if i > 0 then Result := Result + ';';
    Result := Result + ABar.Segments[i].StyleClass;
  end;
end;

function TTyMultiTrackBarTest.Centre(AIndex: Integer): TPoint;
var
  r: TRect;
begin
  r := FBar.ThumbRect(AIndex);
  Result := Point((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
end;

function TTyMultiTrackBarTest.HintAt(const P: TPoint): string;
var
  info: THintInfo;
begin
  info := Default(THintInfo);
  info.HintControl := FBar;
  info.CursorPos := P;
  info.CursorRect := FBar.ClientRect;
  info.HintStr := FBar.Hint;
  FBar.Perform(CM_HINTSHOW, 0, LParam(PtrUInt(@info)));
  Result := info.HintStr;
end;

procedure TTyMultiTrackBarTest.TestDefaults;
begin
  AssertEquals('three thumbs, so a new bar shows them', 3, FBar.Thumbs.Count);
  AssertEquals('25,50,75', Values);
  AssertEquals('each follows the theme, enabled, no hint or class',
    '25:def::+:;50:def::+:;75:def::+:', ThumbsText(FBar));
  AssertEquals('no segment style', 0, FBar.Segments.Count);
  AssertEquals('Min', 0, FBar.Min);
  AssertEquals('Max', 100, FBar.Max);
  AssertEquals('MinGap', 0, FBar.MinGap);
  AssertEquals('no thumb selected', -1, FBar.SelectedThumb);
  AssertTrue('focusable', FBar.TabStop);
end;

procedure TTyMultiTrackBarTest.TestTheTypeKeyHangsOnTheTrackBars;
var
  ctl: TTyStyleController;
  ref: TTyTrackBar;
begin
  AssertEquals('TyMultiTrackBar', (FBar as ITyStyleable).GetStyleTypeKey);
  AssertEquals('registered under the track bar''s key', 'TyTrackBar',
    TyTypeKeyParent('TyMultiTrackBar'));
  ctl := TTyStyleController.Create(nil);
  ref := TTyTrackBar.Create(FForm);
  try
    ctl.LoadThemeCss('TyTrackBar { color: #123456; border-width: 1px; }'
      + 'TyMultiTrackBar { border-width: 3px; }');
    FBar.Controller := ctl;
    ref.Parent := FForm;
    ref.Controller := ctl;
    AssertEquals('the track bar''s rule reaches the multi-value bar',
      TTrackAccess(ref).CurrentStyle.TextColor, TMultiAccess(FBar).CurrentStyle.TextColor);
    AssertEquals('its own rule wins', 3, TMultiAccess(FBar).CurrentStyle.BorderWidth);
    AssertEquals('and stays its own', 1, TTrackAccess(ref).CurrentStyle.BorderWidth);
  finally
    FBar.Controller := nil;
    ref.Free;
    ctl.Free;
  end;
end;

procedure TTyMultiTrackBarTest.TestAValueMovesThroughTheModel;
begin
  FBar.MinGap := 5;
  FBar.OnThumbChange := @ThumbMoved;
  FBar.OnChange := @Changed;
  FBar.Thumbs[1].Value := 90;
  AssertEquals('stops MinGap below the next thumb, as a drag would', '25,70,75', Values);
  AssertEquals('the item reads where the thumb went', 70, FBar.Thumbs[1].Value);
  AssertEquals('and the thumb that moved is reported', 'T1 C ', FLog);
  FLog := '';
  FBar.Thumbs[0].Value := -9;
  AssertEquals('inside Min', '0,70,75', Values);
  FLog := '';
  FBar.Thumbs[0].Value := 0;
  AssertEquals('the same value fires nothing', '', FLog);
  FBar.Thumbs.Add;
  AssertEquals('a thumb added at the end starts at Max', '0,70,75,100', Values);
  FBar.Thumbs.Delete(1);
  AssertEquals('a thumb removed takes its value with it', '0,75,100', Values);
end;

procedure TTyMultiTrackBarTest.TestSortingKeepsEachThumbsLook;
begin
  FBar.Thumbs[2].StyleClass := 'big';
  FBar.Thumbs.BeginUpdate;
  try
    FBar.Thumbs[0].Value := 90;
    FBar.Thumbs[0].Color := clRed;
    FBar.Thumbs[0].Hint := 'was first';
    AssertEquals('kept as given meanwhile', 90, FBar.Thumbs[0].Value);
    AssertEquals('the thumbs wait', '25,50,75', Values);
  finally
    FBar.Thumbs.EndUpdate;
  end;
  AssertEquals('in order at EndUpdate', '50,75,90', Values);
  AssertEquals('each item kept its look and moved with its value',
    '50:def::+:;75:def::+:big;90:$FF:was first:+:', ThumbsText(FBar));
end;

procedure TTyMultiTrackBarTest.TestAThumbsColourIsPainted;
var
  a: TBGRABitmap;
  p: TPoint;
begin
  FBar.Controller := FCtl;
  FBar.Thumbs[1].Color := RGBToColor($FF, $80, $00);
  a := Shot(FBar);
  try
    p := Centre(1);
    AssertTrue('the item''s colour: ' + PxStr(a.GetPixel(p.X, p.Y)),
      SamePx(a.GetPixel(p.X, p.Y), $FF, $80, $00));
    p := Centre(0);
    AssertTrue('clDefault follows the theme: ' + PxStr(a.GetPixel(p.X, p.Y)),
      SamePx(a.GetPixel(p.X, p.Y), $3B, $82, $F6));
  finally
    a.Free;
  end;
end;

procedure TTyMultiTrackBarTest.TestAThumbsStyleClassIsResolved;
var
  a: TBGRABitmap;
  p: TPoint;
begin
  FBar.Controller := FCtl;
  FBar.Thumbs[2].StyleClass := 'big';
  a := Shot(FBar);
  try
    p := Centre(2);
    AssertTrue('TyTrackThumb.big: ' + PxStr(a.GetPixel(p.X, p.Y)),
      SamePx(a.GetPixel(p.X, p.Y), $FF, $FF, $00));
    p := Centre(1);
    AssertTrue('no class: plain TyTrackThumb: ' + PxStr(a.GetPixel(p.X, p.Y)),
      SamePx(a.GetPixel(p.X, p.Y), $3B, $82, $F6));
  finally
    a.Free;
  end;
end;

procedure TTyMultiTrackBarTest.TestAThumbsHintIsShownOverIt;
begin
  FBar.Hint := 'bar';
  FBar.Thumbs[0].Hint := 'low';
  AssertEquals('over a thumb with a hint', 'low', HintAt(Centre(0)));
  AssertEquals('over a thumb without one: the control''s', 'bar', HintAt(Centre(1)));
end;

procedure TTyMultiTrackBarTest.TestADisabledThumbIsInert;
var
  p: TPoint;
  a: TBGRABitmap;
begin
  FBar.Controller := FCtl;
  FBar.Thumbs[1].Enabled := False;
  FBar.SelectedThumb := 0;
  p := Centre(1);
  TMultiAccess(FBar).MouseDown(mbLeft, [ssLeft], p.X, p.Y);
  TMultiAccess(FBar).MouseMove([ssLeft], p.X + 40, p.Y);
  TMultiAccess(FBar).MouseUp(mbLeft, [], p.X + 40, p.Y);
  AssertEquals('not moved', '25,50,75', Values);
  AssertEquals('not selected', 0, FBar.SelectedThumb);
  a := Shot(FBar);
  try
    AssertTrue('still drawn as usual: ' + PxStr(a.GetPixel(p.X, p.Y)),
      SamePx(a.GetPixel(p.X, p.Y), $3B, $82, $F6));
  finally
    a.Free;
  end;
end;

procedure TTyMultiTrackBarTest.TestAnItemChangeRepaints;
var
  bar: TMultiCounting;
begin
  bar := TMultiCounting.Create(FForm);
  bar.Parent := FForm;
  bar.Invalidations := 0;
  bar.Thumbs[0].Color := clRed;
  AssertTrue('Color', bar.Invalidations > 0);
  bar.Invalidations := 0;
  bar.Thumbs[0].Color := clRed;
  AssertEquals('the same colour again asks nothing', 0, bar.Invalidations);
  bar.Thumbs[1].StyleClass := 'big';
  AssertTrue('StyleClass', bar.Invalidations > 0);
  bar.Invalidations := 0;
  bar.Thumbs[2].Enabled := False;
  AssertTrue('Enabled', bar.Invalidations > 0);
  bar.Invalidations := 0;
  bar.Segments.Add;
  bar.Invalidations := 0;
  bar.Segments[0].StyleClass := 'go';
  AssertTrue('a segment''s StyleClass', bar.Invalidations > 0);
end;

procedure TTyMultiTrackBarTest.TestSegmentsStyleTheirStretchOnly;

  { The colour segment AIndex shows clear of the thumbs: 'go', 'stop', 'bare' or 'mixed'. }
  function SegmentLook(B: TBGRABitmap; AIndex: Integer): string;
  var
    lo, hi, m, go, stop, bare, other: Integer;
    px: TBGRAPixel;
  begin
    AssertTrue(FBar.SegmentSpan(AIndex, 96, lo, hi));
    go := 0; stop := 0; bare := 0; other := 0;
    for m := lo to hi - 1 do
    begin
      if UnderAThumb(FBar, m) then Continue;
      px := B.GetPixel(m, FBar.Height div 2);
      if SamePx(px, 0, $C0, 0) then Inc(go)
      else if SamePx(px, $C0, $80, 0) then Inc(stop)
      else if SamePx(px, $60, $60, $60) then Inc(bare)
      else Inc(other);
    end;
    if (go > 0) and (stop + bare + other = 0) then Result := 'go'
    else if (stop > 0) and (go + bare + other = 0) then Result := 'stop'
    else if (bare > 0) and (go + stop + other = 0) then Result := 'bare'
    else Result := Format('mixed(%d/%d/%d/%d)', [go, stop, bare, other]);
  end;

var
  a: TBGRABitmap;
begin
  FBar.Controller := FCtl;
  FBar.TickStyle := ttsNone;
  FBar.Segments.Add.StyleClass := 'go';
  FBar.Segments.Add;                    // an item without a class
  a := Shot(FBar);
  try
    AssertEquals('segment 0, before the first thumb', 'go', SegmentLook(a, 0));
    AssertEquals('an item without a class', 'bare', SegmentLook(a, 1));
    AssertEquals('fewer items than segments: no item', 'bare', SegmentLook(a, 2));
    AssertEquals('nor the last', 'bare', SegmentLook(a, 3));
  finally
    a.Free;
  end;
  FBar.Segments.Add.StyleClass := 'stop';
  a := Shot(FBar);
  try
    AssertEquals('the third item styles the third segment', 'stop', SegmentLook(a, 2));
    AssertEquals('the one after still bare', 'bare', SegmentLook(a, 3));
    AssertEquals('the first unchanged', 'go', SegmentLook(a, 0));
  finally
    a.Free;
  end;
end;

procedure TTyMultiTrackBarTest.Selected(Sender: TObject; AIndex: Integer);
begin
  FLog := FLog + 'S' + IntToStr(AIndex) + ' ';
end;

procedure TTyMultiTrackBarTest.TestTheSelectionFollowsItsThumbWhenSorted;
begin
  FBar.OnThumbSelect := @Selected;
  FBar.SelectedThumb := 0;                       // the thumb at 25
  FLog := '';
  FBar.Thumbs.BeginUpdate;
  try
    FBar.Thumbs[0].Value := 90;
  finally
    FBar.Thumbs.EndUpdate;
  end;
  AssertEquals('50,75,90', Values);
  AssertEquals('the thumb that was selected still is, at its new place', 2, FBar.SelectedThumb);
  AssertEquals('reported once, with the new index', 'S2 ', FLog);

  FLog := '';
  FBar.Thumbs.Delete(0);
  AssertEquals('75,90', Values);
  AssertEquals('a thumb removed before it: the selection moves down with it', 1, FBar.SelectedThumb);
  AssertEquals('S1 ', FLog);

  FLog := '';
  FBar.Thumbs.BeginUpdate;
  try
    FBar.Thumbs.Add.Value := 10;
  finally
    FBar.Thumbs.EndUpdate;
  end;
  AssertEquals('10,75,90', Values);
  AssertEquals('a thumb sorted in before it: the selection moves up', 2, FBar.SelectedThumb);
  AssertEquals('S2 ', FLog);
  AssertEquals('and it is the same thumb', 90, FBar.ThumbValues[FBar.SelectedThumb]);

  FLog := '';
  FBar.SelectedThumb := 0;
  FLog := '';
  FBar.Thumbs.BeginUpdate;
  try
    FBar.Thumbs[1].Value := 95;
  finally
    FBar.Thumbs.EndUpdate;
  end;
  AssertEquals('10,90,95', Values);
  AssertEquals('a sort that leaves it in place', 0, FBar.SelectedThumb);
  AssertEquals('reports nothing', '', FLog);

  FBar.SelectedThumb := 2;
  FLog := '';
  FBar.Thumbs.Delete(2);
  AssertEquals('10,90', Values);
  AssertEquals('the selected thumb removed: nothing selected', -1, FBar.SelectedThumb);
  AssertEquals('reported once', 'S-1 ', FLog);
end;

const
  CMultiForm =
    'object HostForm: TForm'#10 +
    '  Left = 0'#10 +
    '  Top = 0'#10 +
    '  Width = 640'#10 +
    '  Height = 480'#10 +
    '  object Bar: TTyMultiTrackBar'#10 +
    '    Left = 0'#10 +
    '    Top = 0'#10 +
    '    Width = 400'#10 +
    '    Height = 24'#10 +
    '    Thumbs = <'#10 +
    '      item'#10 +
    '        Value = 80'#10 +
    '        Color = clRed'#10 +
    '        Hint = ''high'''#10 +
    '      end'#10 +
    '      item'#10 +
    '        Value = 10'#10 +
    '        StyleClass = ''big'''#10 +
    '      end'#10 +
    '      item'#10 +
    '        Value = 40'#10 +
    '        Enabled = False'#10 +
    '      end>'#10 +
    '    Segments = <'#10 +
    '      item'#10 +
    '        StyleClass = ''go'''#10 +
    '      end>'#10 +
    '  end'#10 +
    'end'#10;

procedure TTyMultiTrackBarTest.TestAFormsThumbsAreSortedWhenRead;
var
  host: TForm;
  bar: TTyMultiTrackBar;
begin
  host := FromText(CMultiForm);
  try
    bar := host.FindComponent('Bar') as TTyMultiTrackBar;
    AssertEquals('10,40,80', ValuesOf(bar));
    AssertEquals('in order, each with its own look', '10:def::+:big;40:def::-:;80:$FF:high:+:',
      ThumbsText(bar));
    AssertEquals('go', SegmentsText(bar));
  finally
    host.Free;
  end;
end;

procedure TTyMultiTrackBarTest.TestThumbsAndSegmentsRoundTripThroughAFormFile;
var
  host: TForm;
  bar: TTyMultiTrackBar;
  txt, want: string;
begin
  FBar.MinGap := 3;
  FBar.Thumbs.Add;
  FBar.Thumbs[0].Value := 5;
  FBar.Thumbs[0].Color := RGBToColor($12, $34, $56);
  FBar.Thumbs[1].Hint := 'middle';
  FBar.Thumbs[2].Enabled := False;
  FBar.Thumbs[3].StyleClass := 'big';
  FBar.Segments.Add.StyleClass := 'go';
  FBar.Segments.Add;
  FBar.Segments.Add.StyleClass := 'stop';
  want := ThumbsText(FBar);
  AssertEquals('the fixture', '5:$563412::+:;50:def:middle:+:;75:def::-:;100:def::+:big', want);
  txt := FormText(FForm);
  AssertTrue('the thumbs are written: ' + txt, Pos('Thumbs = <', txt) > 0);
  AssertFalse('no marker while there are thumbs', Pos('NoThumbs', txt) > 0);
  host := RoundTrip(FForm);
  try
    bar := host.FindComponent('Bar') as TTyMultiTrackBar;
    AssertEquals('read back', want, ThumbsText(bar));
    AssertEquals('5,50,75,100', ValuesOf(bar));
    AssertEquals('go;;stop', SegmentsText(bar));
    AssertEquals(3, bar.MinGap);
    AssertEquals('and written again the same', BarText(txt), BarText(FormText(host)));
  finally
    host.Free;
  end;
end;

procedure TTyMultiTrackBarTest.TestNoThumbsRoundTrips;
var
  host: TForm;
  bar: TTyMultiTrackBar;
  txt: string;
begin
  FBar.Thumbs.Clear;
  AssertEquals(0, FBar.ThumbCount);
  txt := FormText(FForm);
  AssertTrue('an emptied bar says so: ' + txt, Pos('NoThumbs = True', txt) > 0);
  host := RoundTrip(FForm);
  try
    bar := host.FindComponent('Bar') as TTyMultiTrackBar;
    AssertEquals('read back without the default thumbs', 0, bar.Thumbs.Count);
    AssertEquals(0, bar.ThumbCount);
  finally
    host.Free;
  end;
end;

{ TTyMultiTrackReadoutTest }

procedure TTyMultiTrackReadoutTest.TestOneThumbWithTheReadoutDrawsWhatTheTrackBarDraws;
var
  ori: TTyTrackOrientation;
  rev: Boolean;
  a, b, c: TBGRABitmap;
  x, y, diff, moved, offW, offH, aw, ah, bw, bh: Integer;
  ra, rb: TRect;
  where: string;
begin
  FBar.Put([30]);
  FBar.Frequency := 10;
  FRef.Frequency := 10;
  for ori := toHorizontal to toVertical do
    for rev := False to True do
    begin
      Configure(ori, rev);
      if ori = toVertical then
      begin
        FBar.SetBounds(0, 0, 40, CLen);
        FRef.SetBounds(0, 0, 40, CLen);
      end;
      where := Format('ori=%d rev=%s', [Ord(ori), BoolToStr(rev, True)]);
      FBar.ShowValue := False;
      FRef.ShowValue := False;
      FRef.Position := 30;
      FBar.PreferredSize(offW, offH);
      c := Shot(False);
      FBar.ShowValue := True;
      FRef.ShowValue := True;
      a := Shot(False);
      b := Shot(True);
      try
        diff := 0;
        moved := 0;
        for y := 0 to H - 1 do
          for x := 0 to W - 1 do
          begin
            if a.GetPixel(x, y) <> b.GetPixel(x, y) then Inc(diff);
            if a.GetPixel(x, y) <> c.GetPixel(x, y) then Inc(moved);
          end;
        AssertEquals(where + ': pixels that differ from TTyTrackBar with its readout', 0, diff);
        AssertTrue(where + ': the readout changes the picture', moved > 0);
      finally
        a.Free;
        b.Free;
        c.Free;
      end;
      { The track gave the strip up: where a press lands is where the thumb is drawn. }
      ra := FBar.ThumbRect(0);
      rb := FRef.ThumbRect;
      AssertEquals(where + ': thumb Left', rb.Left, ra.Left);
      AssertEquals(where + ': thumb Top', rb.Top, ra.Top);
      AssertEquals(where + ': thumb Right', rb.Right, ra.Right);
      AssertEquals(where + ': thumb Bottom', rb.Bottom, ra.Bottom);
      FBar.PreferredSize(aw, ah);
      FRef.PreferredSize(bw, bh);
      AssertEquals(where + ': preferred width', bw, aw);
      AssertEquals(where + ': preferred height', bh, ah);
      AssertTrue(where + ': the readout makes it thicker', (aw + ah) > (offW + offH));
    end;
end;

procedure TTyMultiTrackReadoutTest.TestTheReadoutIsTheSelectedThumbsElseTheFirst;
var
  x0: Integer;
  b: TBGRABitmap;
  p: TPoint;

  function StripDiff(A, B: TBGRABitmap): Integer;
  var
    x, y: Integer;
  begin
    Result := 0;
    for y := 0 to H - 1 do
      for x := x0 to W - 1 do
        if A.GetPixel(x, y) <> B.GetPixel(x, y) then Inc(Result);
  end;

  procedure Check(AValue: Integer; const AWhere: string);
  var
    a, r: TBGRABitmap;
    x, y, ink: Integer;
  begin
    FRef.Position := AValue;
    a := Shot(False);
    r := Shot(True);
    try
      AssertEquals(AWhere + ': the readout says ' + IntToStr(AValue), 0, StripDiff(a, r));
      ink := 0;
      for y := 0 to H - 1 do
        for x := x0 to W - 1 do
          if SamePx(a.GetPixel(x, y), 0, 0, 0) then Inc(ink);
      AssertTrue(AWhere + ': there is text in the strip', ink > 0);
    finally
      a.Free;
      r.Free;
    end;
  end;

var
  r20, r90: TBGRABitmap;
begin
  FBar.Put([20, 55, 90]);
  FBar.TickStyle := ttsNone;
  FRef.TickStyle := ttsNone;
  FBar.ShowValue := True;
  FRef.ShowValue := True;
  b := Shot(True);                  // the reference measures its strip
  b.Free;
  x0 := RefThumbRect(100).Right;    // the track ends here, the strip runs to the right edge
  AssertTrue('the strip is inside the bar', (x0 > 0) and (x0 < W));
  { The fixture tells the values apart: 20 and 90 are different text. }
  FRef.Position := 20;
  r20 := Shot(True);
  FRef.Position := 90;
  r90 := Shot(True);
  try
    AssertTrue('20 and 90 read differently', StripDiff(r20, r90) > 0);
  finally
    r20.Free;
    r90.Free;
  end;
  Check(20, 'nothing selected: the first thumb''s value');
  FBar.SelectedThumb := 2;
  Check(90, 'thumb 2 selected');
  FBar.SelectedThumb := 1;
  Check(55, 'thumb 1 selected');
  FBar.SetThumbValue(1, 60);
  Check(60, 'the selected thumb moved');
  p := At(90);
  FBar.Press(p.X, p.Y);
  FBar.Release(p.X, p.Y);
  Check(90, 'a press selects');
  FBar.SelectedThumb := -1;
  Check(20, 'selection dropped: the first again');
end;

{ TTyMultiTrackOwnerDrawTest }

const
  CStateName: array[TTyState] of string =
    ('normal', 'hover', 'active', 'focused', 'disabled', 'selected');

procedure FillInk(P: TTyPainter; const R: TRect; AR, AG, AB: Byte);
var
  f: TTyFill;
begin
  f := Default(TTyFill);
  f.Kind := tfkSolid;
  f.Color := TyRGB(AR, AG, AB);
  P.FillBackground(R, f, 0);
end;

procedure TTyMultiTrackOwnerDrawTest.SetUp;
begin
  inherited SetUp;
  FCalls := '';
  FDropThumb := -1;
  FBar.OnDrawTrack := @DrawTrack;
  FBar.OnDrawThumb := @DrawThumb;
end;

procedure TTyMultiTrackOwnerDrawTest.DrawTrack(Sender: TObject; APainter: TTyPainter;
  const ARect: TRect; var ADefaultDraw: Boolean);
begin
  AssertTrue('the sender is the bar', Sender = FBar);
  AssertTrue('the default is to draw', ADefaultDraw);
  FCalls := FCalls + 'track ';
  FTrackRect := ARect;
  if FFillTrack then FillInk(APainter, ARect, $C0, $C0, $FF);
  if FDropTrack then ADefaultDraw := False;
end;

procedure TTyMultiTrackOwnerDrawTest.DrawThumb(Sender: TObject; APainter: TTyPainter;
  AIndex: Integer; const ARect: TRect; AStates: TTyStateSet; var ADefaultDraw: Boolean);
var
  st: TTyState;
  s: string;
begin
  AssertTrue('the sender is the bar', Sender = FBar);
  AssertTrue('the default is to draw', ADefaultDraw);
  s := '';
  for st := Low(TTyState) to High(TTyState) do
    if st in AStates then
    begin
      if s <> '' then s := s + '+';
      s := s + CStateName[st];
    end;
  FCalls := FCalls + Format('%d:%s ', [AIndex, s]);
  if AIndex >= Length(FThumbRects) then SetLength(FThumbRects, AIndex + 1);
  FThumbRects[AIndex] := ARect;
  if AIndex = FDropThumb then
  begin
    ADefaultDraw := False;
    if FFillThumb then FillInk(APainter, ARect, $12, $AB, $34);
  end;
end;

function TTyMultiTrackOwnerDrawTest.InkBox(B: TBGRABitmap; const AWithin: TRect;
  R, G, Bl: Byte): TRect;
var
  x, y: Integer;
begin
  Result := Rect(MaxInt, MaxInt, -1, -1);
  for y := AWithin.Top to AWithin.Bottom - 1 do
    for x := AWithin.Left to AWithin.Right - 1 do
    begin
      if (x < 0) or (y < 0) or (x >= W) or (y >= H) then Continue;
      if not SamePx(B.GetPixel(x, y), R, G, Bl) then Continue;
      if x < Result.Left then Result.Left := x;
      if y < Result.Top then Result.Top := y;
      if x + 1 > Result.Right then Result.Right := x + 1;
      if y + 1 > Result.Bottom then Result.Bottom := y + 1;
    end;
end;

function TTyMultiTrackOwnerDrawTest.InkCount(B: TBGRABitmap; const AWithin: TRect;
  R, G, Bl: Byte): Integer;
var
  x, y: Integer;
begin
  Result := 0;
  for y := AWithin.Top to AWithin.Bottom - 1 do
    for x := AWithin.Left to AWithin.Right - 1 do
      if (x >= 0) and (y >= 0) and (x < W) and (y < H) and SamePx(B.GetPixel(x, y), R, G, Bl) then
        Inc(Result);
end;

procedure TTyMultiTrackOwnerDrawTest.TestTheHooksAreAskedForEachPartInPaintOrder;
var
  b: TBGRABitmap;
  p: TPoint;

  function Calls: string;
  begin
    FCalls := '';
    b := Shot(False);
    b.Free;
    Result := FCalls;
  end;

begin
  FBar.Put([20, 50, 80]);
  AssertEquals('the track first, then every thumb', 'track 0:normal 1:normal 2:normal ', Calls);
  p := At(20);
  FBar.Hover(p.X, p.Y);
  AssertEquals('the thumb under the pointer', 'track 0:hover 1:normal 2:normal ', Calls);
  p := At(80);
  FBar.Press(p.X, p.Y);
  AssertEquals('the thumb being dragged', 'track 0:normal 1:normal 2:active ', Calls);
  FBar.Release(p.X, p.Y);
  FBar.SelectedThumb := 0;
  AssertEquals('the selected thumb is painted last, on top', 'track 1:normal 2:normal 0:normal ',
    Calls);
  FBar.FakeFocus := True;
  AssertEquals('focused: the keyboard''s thumb says so',
    'track 1:normal 2:normal 0:normal+focused ', Calls);
end;

procedure TTyMultiTrackOwnerDrawTest.TestTheRectanglesAreThePaintedParts;
var
  ori: TTyTrackOrientation;
  rev: Boolean;
  a: TBGRABitmap;
  i: Integer;
  box: TRect;
  where: string;

  procedure Same(const AWhat: string; const AWant, AGot: TRect);
  begin
    AssertEquals(AWhat + ' Left', AWant.Left, AGot.Left);
    AssertEquals(AWhat + ' Top', AWant.Top, AGot.Top);
    AssertEquals(AWhat + ' Right', AWant.Right, AGot.Right);
    AssertEquals(AWhat + ' Bottom', AWant.Bottom, AGot.Bottom);
  end;

begin
  FBar.Put([20, 50, 80]);
  { With ticks, so the painted thumb (the slider band) is narrower across than its hit rect. }
  FBar.Frequency := 10;
  for ori := toHorizontal to toVertical do
    for rev := False to True do
    begin
      Configure(ori, rev);
      where := Format('ori=%d rev=%s', [Ord(ori), BoolToStr(rev, True)]);
      SetLength(FThumbRects, 0);
      a := Shot(False);
      try
        AssertEquals(where + ': every thumb asked', 3, Length(FThumbRects));
        for i := 0 to 2 do
        begin
          box := InkBox(a, FBar.ThumbRect(i), $3B, $82, $F6);
          Same(Format('%s: thumb %d is the rectangle painted', [where, i]), box, FThumbRects[i]);
        end;
        box := InkBox(a, Rect(0, 0, W, H), $60, $60, $60);
        Same(where + ': the track is the groove painted', box, FTrackRect);
      finally
        a.Free;
      end;
    end;
end;

procedure TTyMultiTrackOwnerDrawTest.TestADefaultDrawFalseLeavesTheThumbToTheHandler;
var
  d, a: TBGRABitmap;
  r: TRect;
  x, y, diff: Integer;
begin
  FBar.Put([20, 50, 80]);
  d := Shot(False);
  try
    FDropThumb := 1;
    FFillThumb := True;
    a := Shot(False);
    try
      r := FThumbRects[1];
      AssertEquals('no default ink on thumb 1', 0, InkCount(a, r, $3B, $82, $F6));
      AssertEquals('the handler''s ink, all of it', (r.Right - r.Left) * (r.Bottom - r.Top),
        InkCount(a, r, $12, $AB, $34));
      AssertTrue('thumb 0 as usual', SamePx(ThumbPx(a, 0), $3B, $82, $F6));
      AssertTrue('thumb 2 as usual', SamePx(ThumbPx(a, 2), $3B, $82, $F6));
    finally
      a.Free;
    end;
    FFillThumb := False;
    a := Shot(False);
    try
      AssertEquals('the handler drew nothing: no thumb there', 0, InkCount(a, r, $3B, $82, $F6));
      AssertTrue('the groove shows through', InkCount(a, r, $60, $60, $60) > 0);
      diff := 0;
      for y := 0 to H - 1 do
        for x := 0 to W - 1 do
          if not PtInRect(r, Point(x, y)) and (a.GetPixel(x, y) <> d.GetPixel(x, y)) then Inc(diff);
      AssertEquals('everything else as the default', 0, diff);
    finally
      a.Free;
    end;
  finally
    d.Free;
  end;
end;

procedure TTyMultiTrackOwnerDrawTest.TestADefaultDrawFalseLeavesTheTrackToTheHandler;
var
  d, a: TBGRABitmap;
  all: TRect;
  x, y, diff, m, own, other: Integer;
begin
  FBar.Put([20, 50, 80]);
  SetLength(FBar.SegKey, 4);
  FBar.SegKey[1] := TyTrackSelectionKey;
  FBar.Frequency := 10;
  all := Rect(0, 0, W, H);
  d := Shot(False);
  try
    AssertTrue('fixture: a groove', InkCount(d, all, $60, $60, $60) > 0);
    AssertTrue('fixture: a highlighted segment', InkCount(d, all, $FF, 0, 0) > 0);
    AssertTrue('fixture: ticks', InkCount(d, all, 0, 0, 0) > 0);
    { Asked BEFORE the track: left to draw, the bar paints over what the handler drew. }
    FFillTrack := True;
    a := Shot(False);
    try
      AssertEquals('the default covers the handler''s ink', 0, InkCount(a, all, $C0, $C0, $FF));
      diff := 0;
      for y := 0 to H - 1 do
        for x := 0 to W - 1 do
          if a.GetPixel(x, y) <> d.GetPixel(x, y) then Inc(diff);
      AssertEquals('and the picture is the default one', 0, diff);
    finally
      a.Free;
    end;
    FFillTrack := False;
    FDropTrack := True;
    a := Shot(False);
    try
      AssertEquals('no groove', 0, InkCount(a, all, $60, $60, $60));
      AssertEquals('no segment fill', 0, InkCount(a, all, $FF, 0, 0));
      AssertTrue('the thumbs are still drawn', SamePx(ThumbPx(a, 1), $3B, $82, $F6));
      AssertEquals('the ticks are still drawn', InkCount(d, all, 0, 0, 0), InkCount(a, all, 0, 0, 0));
    finally
      a.Free;
    end;
    FFillTrack := True;
    a := Shot(False);
    try
      own := 0;
      other := 0;
      for m := FTrackRect.Left to FTrackRect.Right - 1 do
      begin
        if UnderAThumb(m) then Continue;
        for y := FTrackRect.Top to FTrackRect.Bottom - 1 do
          if SamePx(a.GetPixel(m, y), $C0, $C0, $FF) then Inc(own) else Inc(other);
      end;
      AssertTrue('the handler''s track', own > 0);
      AssertEquals('all of the track off the thumbs is the handler''s', 0, other);
    finally
      a.Free;
    end;
  finally
    d.Free;
  end;
end;

initialization
  RegisterTest(TTyMultiTrackModelTest);
  RegisterTest(TTyMultiTrackGeometryTest);
  RegisterTest(TTyMultiTrackPaintTest);
  RegisterTest(TTyMultiTrackMouseTest);
  RegisterTest(TTyMultiTrackKeyboardTest);
  RegisterTest(TTyRangeTrackBarTest);
  RegisterTest(TTyMultiTrackBarTest);
  RegisterTest(TTyMultiTrackReadoutTest);
  RegisterTest(TTyMultiTrackOwnerDrawTest);
end.
