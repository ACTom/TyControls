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
  tyControls.TrackBar,
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
    Off: array of Boolean;          // thumb i disabled
    Colors: array of TColor;
    ThumbCls: array of string;
    Hints: array of string;
    SegKey, SegCls: array of string;
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

initialization
  RegisterTest(TTyMultiTrackModelTest);
  RegisterTest(TTyMultiTrackGeometryTest);
  RegisterTest(TTyMultiTrackPaintTest);
  RegisterTest(TTyMultiTrackMouseTest);
  RegisterTest(TTyMultiTrackKeyboardTest);
  RegisterTest(TTyRangeTrackBarTest);
end.
