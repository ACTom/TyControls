unit test.advchart.gauge;
{$mode objfpc}{$H+}
{ The gauge.

  THE ANGLES ARE THE WHOLE TEST. A gauge's option is degrees in the maths
  convention -- 0 at three o'clock, counting anticlockwise on screen -- and the
  drawing frame has y pointing down, so the conversion negates and then
  normalises the PAIR with the clockwise flag inverted. Both halves are easy to
  write and easy to write wrong, and a test that asserts a radian it computed
  the same way the code did agrees with a mirrored dial. So the direction is
  pinned by a DEVICE PIXEL SIGN -- the default dial starts at the lower LEFT --
  and not by a number.

  Everything else on a gauge is a fraction of one radius, so a fixture with a
  square viewport cannot tell the centre's two percentage bases apart from the
  radius' one. The rule tests use a rectangle. }
interface
uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Data,
     tyControls.AdvChart.Option, tyControls.AdvChart.Layout,
     tyControls.AdvChart.Shape, tyControls.AdvChart.Gauge,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Series,
     tyControls.AdvChart.Measure,
     tyControls.AdvanceChart, test.advancechart;
type
  TAdvChartGaugeRuleTest = class(TTestCase)
  private
    FOpt: TTyChartOption;
    FStore: TTyDataStore;
    FList: TTyPaintList;
    procedure SetUp; override;
    procedure TearDown; override;
    function SpecOf(const AText: string): TTyGaugeSpec;
    function ItemsOf(const AText: string): TTyGaugeItemArray;
    function StoreOf(const AValues: array of Double): TTyDataStore;
    { The dial, against a deliberately NON-SQUARE rect. }
    function LayoutOf(const ASpec: TTyGaugeSpec): TTyGaugeLayout;
    function Binding: TTySeriesBinding;
    function BuildAxis(const ASpec: TTyGaugeSpec): Integer;
  published
    procedure TestTheDefaultDialStartsAtTheLowerLeftAndSweepsClockwise;
    procedure TestAWholeTurnIsNotAnEmptyOne;
    procedure TestAnticlockwiseIsNotTheComplementOfTheClockwiseArc;
    procedure TestTheValueAngleClampsAtBothEndsAndParksNaNAtTheStart;
    procedure TestADialWhoseMinEqualsItsMaxAnswersTheMiddle;
    procedure TestTheBandsStopWhereTheStopsDoAndTheDialDoesNot;
    procedure TestHidingTheTrackDoesNotMoveTheDial;
    procedure TestAnEmptyStopListIsAnAnswerRatherThanAnIndexError;
    procedure TestTheStopBucketsAreHalfOpen;
    procedure TestANaNFractionTakesTheLastStop;
    procedure TestTheNeedleTailFlipsOnAnExactComparison;
    procedure TestTheNeedleTipSitsOnTheDialAtTheValueAngle;
    procedure TestTheNeedleOffsetTurnsWithTheNeedle;
    procedure TestALabelValueIsComputedForwardFromMin;
    procedure TestTheFormatterReplacesOnlyTheFirstToken;
    procedure TestTheCentreAndTheRadiusAreMeasuredAgainstDifferentThings;
    procedure TestSplitNumberZeroIsNotADivisionByZero;
    procedure TestTheLabelRingIgnoresTheTrackButNotTheSplitLineDistance;
    procedure TestPerDatumOffsetCentreComesFromTheDataArray;
    procedure TestARotateWrittenAsAStringIsNoRotationAtAll;
    procedure TestTheMinorTicksAreCountedUpstreamsWay;
    procedure TestANaNValueIsParkedEvenOnADialOfNoWidth;
    procedure TestTheLabelAnchorThresholdsAreNotSymmetric;
    procedure TestALabelIsMeasuredInTheFontItIsDrawnIn;
    procedure TestTheTicksStartInsideTheTrackAndTheTrackWidthMovesThem;
    procedure TestAStopPastTheEndsIsClamped;
    procedure TestTheEarlierStopIsPaintedOverTheLaterOne;
    procedure TestAnOverlappingProgressArcIsStackedSmallestFirst;
    procedure TestProgressClipLetsTheArcRunPastTheDial;
    procedure TestARichFormatterDegradesToItsWords;
    procedure TestABandIsClampedAndStartsWhereTheLastOneStopped;
  end;

  TAdvChartGaugeDrawTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TChartProbe;
    FBmp: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw(const AOption: string);
    function ColouredPixels: Integer;
    function Diagnostics: string;
  published
    procedure TestAGaugeDrawsAtAll;
    procedure TestItSaysNothingAboutHavingNoRenderer;
    procedure TestTheNeedleSwingsWithTheValue;
    procedure TestTheReadingIsDrawnUnderTheHub;
    procedure TestABandIsPaintedInItsOwnColour;
    procedure TestTheProgressArcGrowsWithTheValue;
    procedure TestTheNeedleReportsItsDatum;
    procedure TestAPathPointerIsTurnedToTheValue;
  end;

implementation

const
  cW = 520;
  cH = 380;
  cGauge =
    '{"tooltip":{"show":false},' +
    '"series":[{"type":"gauge","name":"G",' +
    '"data":[{"name":"score","value":70}]}]}';

{ ==================== the rules ==================== }

procedure TAdvChartGaugeRuleTest.SetUp;
begin
  inherited SetUp;
  FList := TTyPaintList.Create;
end;

procedure TAdvChartGaugeRuleTest.TearDown;
begin
  FreeAndNil(FList);
  FreeAndNil(FOpt);
  FreeAndNil(FStore);
  inherited TearDown;
end;

function TAdvChartGaugeRuleTest.SpecOf(const AText: string): TTyGaugeSpec;
begin
  FreeAndNil(FOpt);
  FOpt := TTyChartOption.Create;
  AssertTrue('the fixture parses', FOpt.SetOptionText(AText));
  Result := TyGaugeSpecOf(FOpt, 0);
end;

function TAdvChartGaugeRuleTest.ItemsOf(const AText: string): TTyGaugeItemArray;
var spec: TTyGaugeSpec;
begin
  spec := SpecOf(AText);
  Result := TyGaugeItemsOf(FOpt, 0, spec);
end;

function TAdvChartGaugeRuleTest.StoreOf(
  const AValues: array of Double): TTyDataStore;
var i: Integer;
begin
  FreeAndNil(FStore);
  FStore := TTyDataStore.Create;
  FStore.AddDimension('value', ddtFloat);
  for i := 0 to High(AValues) do FStore.AppendRow([AValues[i]]);
  Result := FStore;
end;

function TAdvChartGaugeRuleTest.LayoutOf(
  const ASpec: TTyGaugeSpec): TTyGaugeLayout;
begin
  { 400 x 200, NOT a square. A square viewport makes the centre's two bases
    and the radius' one all the same number, and a fixture that cannot tell
    them apart lets a mutant that swaps them live. }
  Result := TyGaugeLayoutOf(ASpec, TyRectF(0, 0, 400, 200), 96);
end;

function TAdvChartGaugeRuleTest.Binding: TTySeriesBinding;
begin
  Result := Default(TTySeriesBinding);
  Result.SeriesIndex := 0;
  Result.SeriesType := TyGaugeSeriesTypeName;
  Result.Resolved := True;
  Result.HasAxes := False;
end;

function TAdvChartGaugeRuleTest.BuildAxis(const ASpec: TTyGaugeSpec): Integer;
begin
  FList.Clear;
  Result := TyBuildGaugeAxis(Binding, LayoutOf(ASpec), ASpec, TyGaugeVisual,
    TTyPainterTextMeasurer.Create(96), 96, FList);
end;

procedure TAdvChartGaugeRuleTest.
  TestTheDefaultDialStartsAtTheLowerLeftAndSweepsClockwise;
var
  lay: TTyGaugeLayout;
begin
  { PINNED BY A PIXEL SIGN, not by a radian. `startAngle: 225` is upper-left
    in the option's own convention and LOWER-left once y points down, and a
    port that forgot the negation -- or applied it twice -- produces a number
    that looks just as plausible as this one. Only the sign of the point on
    the canvas tells them apart. }
  lay := LayoutOf(TyGaugeSpecDefault);
  AssertTrue('the dial is laid out', lay.Valid);
  AssertTrue(Format('the start is LEFT of centre (cos=%g)', [Cos(lay.StartRad)]),
             Cos(lay.StartRad) < -0.5);
  AssertTrue(Format('and BELOW it (sin=%g)', [Sin(lay.StartRad)]),
             Sin(lay.StartRad) > 0.5);
  { And the sweep runs clockwise on screen, which with y down is a POSITIVE
    span -- three quarters of a turn. }
  AssertEquals('three quarters of a turn, clockwise', 1.5 * Pi, lay.Span, 1e-9);
  { The end is lower-RIGHT. }
  AssertTrue(Format('the end is right of centre (cos=%g)', [Cos(lay.EndRad)]),
             Cos(lay.EndRad) > 0.5);
  AssertTrue(Format('and below it (sin=%g)', [Sin(lay.EndRad)]),
             Sin(lay.EndRad) > 0.5);
end;

procedure TAdvChartGaugeRuleTest.TestAWholeTurnIsNotAnEmptyOne;
var
  spec: TTyGaugeSpec;
  lay: TTyGaugeLayout;
begin
  { THE CASE THAT CATCHES A PORT THAT STOPS AFTER THE NEGATION. `startAngle: 0,
    endAngle: 360` negates to 0 and -2*Pi, a span of MINUS a whole turn -- a
    dial drawn backwards, or drawn as nothing. The normaliser is what turns it
    back into a full circle forwards, and the defaults happen to normalise to
    themselves, so nothing else in this file would notice its absence. }
  spec := TyGaugeSpecDefault;
  spec.StartDeg := 0;
  spec.EndDeg := 360;
  lay := LayoutOf(spec);
  AssertTrue(lay.Valid);
  AssertEquals('a whole turn, forwards', 2 * Pi, lay.Span, 1e-9);
end;

procedure TAdvChartGaugeRuleTest.
  TestAnticlockwiseIsNotTheComplementOfTheClockwiseArc;
var
  spec: TTyGaugeSpec;
  lay: TTyGaugeLayout;
begin
  { `clockwise: false` on the DEFAULT angles is not the other 90 degrees of the
    circle -- it is the SHORT way round, a quarter turn backwards through six
    o'clock. A port that took the magnitude of the span, or that sorted the two
    angles, draws the 270-degree arc mirrored instead. }
  spec := TyGaugeSpecDefault;
  spec.Clockwise := False;
  lay := LayoutOf(spec);
  AssertTrue(lay.Valid);
  AssertEquals('a quarter turn, backwards', -0.5 * Pi, lay.Span, 1e-9);
end;

procedure TAdvChartGaugeRuleTest.
  TestTheValueAngleClampsAtBothEndsAndParksNaNAtTheStart;
var
  lay: TTyGaugeLayout;
begin
  lay := LayoutOf(TyGaugeSpecDefault);
  AssertEquals('min is the start', lay.StartRad,
               TyGaugeAngleOf(lay, 0, 100, 0, True), 1e-9);
  AssertEquals('max is the end', lay.EndRad,
               TyGaugeAngleOf(lay, 0, 100, 100, True), 1e-9);
  AssertEquals('half way is half way', (lay.StartRad + lay.EndRad) / 2,
               TyGaugeAngleOf(lay, 0, 100, 50, True), 1e-9);
  AssertEquals('past the top, clamped', lay.EndRad,
               TyGaugeAngleOf(lay, 0, 100, 500, True), 1e-9);
  { WITHOUT THE CLAMP it runs past the end, which is what progress.clip: false
    asks for -- and the two answers must actually differ, or the flag is a
    decoration. }
  AssertTrue('unclamped, it overshoots',
    TyGaugeAngleOf(lay, 0, 100, 500, False) > lay.EndRad + 1);
  { NaN PARKS AT THE START. Upstream says so in a comment and then leaves the
    needle visible there; here it matters twice over, because an ordered
    comparison against NaN does not answer False on this compiler, it raises. }
  AssertEquals('a value that is not a number', lay.StartRad,
               TyGaugeAngleOf(lay, 0, 100, NaN, True), 1e-9);
end;

procedure TAdvChartGaugeRuleTest.TestADialWhoseMinEqualsItsMaxAnswersTheMiddle;
var
  lay: TTyGaugeLayout;
begin
  { `min: 50, max: 50` IS A LEGAL OPTION, and the answer is the middle of the
    dial rather than either end -- which is not a rounding decision, it is what
    upstream's linearMap returns for a domain of no width. A port that guarded
    "denominator is zero, answer the start" parks every needle at the left. }
  lay := LayoutOf(TyGaugeSpecDefault);
  AssertEquals((lay.StartRad + lay.EndRad) / 2,
               TyGaugeAngleOf(lay, 50, 50, 50, True), 1e-9);
  AssertEquals('and the value does not matter', (lay.StartRad + lay.EndRad) / 2,
               TyGaugeAngleOf(lay, 50, 50, 900, True), 1e-9);
end;

procedure TAdvChartGaugeRuleTest.
  TestTheBandsStopWhereTheStopsDoAndTheDialDoesNot;
var
  spec: TTyGaugeSpec;
  lay: TTyGaugeLayout;
begin
  { THE DELIBERATE DIVERGENCE. Upstream reuses the dial's end angle as the
    colour-stop loop's own, so a last stop below 1 silently shrinks the SCALE
    as well as the colour -- the needle under-reads and the labels still say
    min..max. Here the two are separate: the bands stop at 0.7, the dial does
    not. }
  spec := SpecOf('{"series":[{"type":"gauge","axisLine":{"lineStyle":'
    + '{"color":[[0.7,"#ff0000"]]}}}]}');
  lay := LayoutOf(spec);
  AssertTrue(lay.Valid);
  AssertEquals('the bands stop at seven tenths',
               lay.StartRad + lay.Span * 0.7, lay.BandEndRad, 1e-9);
  AssertEquals('the dial does not', lay.StartRad + lay.Span, lay.EndRad, 1e-9);
  AssertTrue('and the two really are different',
             Abs(lay.EndRad - lay.BandEndRad) > 1);
end;

procedure TAdvChartGaugeRuleTest.TestHidingTheTrackDoesNotMoveTheDial;
var
  spec: TTyGaugeSpec;
  lay: TTyGaugeLayout;
begin
  { UPSTREAM'S OWN TELL that the leak above was never meant: its stop loop is
    gated on `axisLine.show`, so switching the track OFF puts the scale back.
    Here the answer is the same either way, which is the point. }
  spec := SpecOf('{"series":[{"type":"gauge","axisLine":{"show":false,'
    + '"lineStyle":{"color":[[0.7,"#ff0000"]]}}}]}');
  lay := LayoutOf(spec);
  AssertTrue(lay.Valid);
  AssertEquals('no bands, so nothing to stop short of',
               lay.EndRad, lay.BandEndRad, 1e-9);
end;

procedure TAdvChartGaugeRuleTest.
  TestAnEmptyStopListIsAnAnswerRatherThanAnIndexError;
var
  stops: TTyGaugeStopArray;
begin
  { `color: []` IS LEGAL JSON and upstream reads colorList[0] before looking at
    the length, then colorList[-1] on the way out. Both are range errors here. }
  stops := nil;
  AssertEquals('the default, not a crash', Int64($FF123456),
               Int64(TyGaugeStopColour(stops, 0.5, $FF123456)));
  AssertEquals('at zero as well', Int64($FF123456),
               Int64(TyGaugeStopColour(stops, 0, $FF123456)));
  AssertEquals('and past the end', Int64($FF123456),
               Int64(TyGaugeStopColour(stops, 2, $FF123456)));
end;

procedure TAdvChartGaugeRuleTest.TestTheStopBucketsAreHalfOpen;
var
  stops: TTyGaugeStopArray;
begin
  { (previous, this]. A fraction landing exactly ON a stop belongs to THAT
    stop, not to the next -- so 0.3 is the first colour and anything above it
    is the second. A fixture whose stops are far apart cannot see the
    difference; these two are a ten-thousandth apart. }
  SetLength(stops, 2);
  stops[0].Frac := 0.3; stops[0].HasColour := True; stops[0].Colour := $FFAA0000;
  stops[1].Frac := 1.0; stops[1].HasColour := True; stops[1].Colour := $FF00AA00;
  AssertEquals('exactly on the stop', Int64($FFAA0000),
               Int64(TyGaugeStopColour(stops, 0.3, 0)));
  AssertEquals('a hair above it', Int64($FF00AA00),
               Int64(TyGaugeStopColour(stops, 0.3001, 0)));
  AssertEquals('a hair below it', Int64($FFAA0000),
               Int64(TyGaugeStopColour(stops, 0.2999, 0)));
  { Zero and below take the first stop outright, which is upstream's own
    early-out rather than a consequence of the loop. }
  AssertEquals('at zero', Int64($FFAA0000), Int64(TyGaugeStopColour(stops, 0, 0)));
  AssertEquals('below zero', Int64($FFAA0000),
               Int64(TyGaugeStopColour(stops, -1, 0)));
end;

procedure TAdvChartGaugeRuleTest.TestANaNFractionTakesTheLastStop;
var
  stops: TTyGaugeStopArray;
begin
  { NOT THE FIRST, which is what a reader expects of a value that is not a
    number. Upstream loses every comparison against NaN, so its loop runs off
    the end and returns the last colour; reproduced, because a NaN datum
    painting itself the FIRST band's colour would read as a small value rather
    than as no value. }
  SetLength(stops, 2);
  stops[0].Frac := 0.3; stops[0].HasColour := True; stops[0].Colour := $FFAA0000;
  stops[1].Frac := 1.0; stops[1].HasColour := True; stops[1].Colour := $FF00AA00;
  AssertEquals(Int64($FF00AA00), Int64(TyGaugeStopColour(stops, NaN, 0)));
end;

procedure TAdvChartGaugeRuleTest.TestTheNeedleTailFlipsOnAnExactComparison;
var
  a, b: TTyPointFArray;
  tailA, tailB: Double;
begin
  { `width >= r / 3` -- exact, no epsilon, and it DOUBLES the tail. A stubby
    needle keeps a tail one half-width long; anything longer gets two. The two
    fixtures below sit either side of the line by a thousandth. }
  a := TyGaugeNeedlePoints(100, 100, 0, 10, 30, 0, 0);
  b := TyGaugeNeedlePoints(100, 100, 0, 10, 30.003, 0, 0);
  AssertEquals(4, Length(a));
  AssertEquals(4, Length(b));
  { The tail is point 0, behind the pivot along -cos. At angle 0 that is
    straight left of it. }
  tailA := 100 - a[0].X;
  tailB := 100 - b[0].X;
  AssertEquals('width >= r/3 keeps one half-width', 10.0, tailA, 1e-6);
  AssertEquals('a hair longer doubles it', 20.0, tailB, 1e-6);
end;

procedure TAdvChartGaugeRuleTest.TestTheNeedleTipSitsOnTheDialAtTheValueAngle;
var
  lay: TTyGaugeLayout;
  pts: TTyPointFArray;
  ang: Double;
begin
  { THE TIP IS THE ONLY POINT THAT MUST BE EXACT, because it is what a reader
    looks at. Pinned against the dial's own geometry rather than against a
    formula: cx + r*cos(theta), cy + r*sin(theta). }
  lay := LayoutOf(TyGaugeSpecDefault);
  ang := TyGaugeAngleOf(lay, 0, 100, 100, True);
  pts := TyGaugeNeedlePoints(lay.CX, lay.CY, ang, 6, lay.R * 0.6, 0, 0);
  AssertEquals(4, Length(pts));
  AssertEquals('tip x', lay.CX + lay.R * 0.6 * Cos(ang), pts[2].X, 1e-6);
  AssertEquals('tip y', lay.CY + lay.R * 0.6 * Sin(ang), pts[2].Y, 1e-6);
  { AND IT REALLY MOVES. At the maximum the needle points lower-right; at the
    minimum, lower-left. Without this the test above passes for a needle that
    never leaves its start. }
  ang := TyGaugeAngleOf(lay, 0, 100, 0, True);
  pts := TyGaugeNeedlePoints(lay.CX, lay.CY, ang, 6, lay.R * 0.6, 0, 0);
  AssertTrue('at the minimum the tip is LEFT of the hub', pts[2].X < lay.CX);
  ang := TyGaugeAngleOf(lay, 0, 100, 100, True);
  pts := TyGaugeNeedlePoints(lay.CX, lay.CY, ang, 6, lay.R * 0.6, 0, 0);
  AssertTrue('at the maximum it is RIGHT of it', pts[2].X > lay.CX);
end;

procedure TAdvChartGaugeRuleTest.TestTheNeedleOffsetTurnsWithTheNeedle;
var
  up, right: TTyPointFArray;
begin
  { `offsetCenter` LIVES IN THE NEEDLE'S OWN FRAME, unlike the anchor's and
    the reading's, which are screen offsets. Upstream puts it into the shape
    and then rotates the shape, so a y offset pushes the needle BACKWARDS
    along its own axis whatever the value is.

    Two angles a quarter turn apart, the same offset: if it were a screen
    offset both pivots would move the same way. }
  up := TyGaugeNeedlePoints(100, 100, -Pi / 2, 6, 40, 0, 10);
  right := TyGaugeNeedlePoints(100, 100, 0, 6, 40, 0, 10);
  { Pointing up (-Pi/2 with y down), a +10 offset pushes the tip DOWN to
    y = 100 - 40 + 10. }
  AssertEquals('turned up, the offset is along y', 70.0, up[2].Y, 1e-6);
  AssertEquals('and x is untouched', 100.0, up[2].X, 1e-6);
  { Pointing right, the SAME offset is now along x. }
  AssertEquals('turned right, it is along x', 130.0, right[2].X, 1e-6);
  AssertEquals('and y is untouched', 100.0, right[2].Y, 1e-6);
end;

procedure TAdvChartGaugeRuleTest.TestALabelValueIsComputedForwardFromMin;
begin
  AssertEquals('the first is min', 0.0, TyGaugeLabelValue(0, 100, 0, 10), 1e-9);
  AssertEquals('the last is max', 100.0, TyGaugeLabelValue(0, 100, 10, 10), 1e-9);
  AssertEquals('and the middle is the middle', 50.0,
               TyGaugeLabelValue(0, 100, 5, 10), 1e-9);
  { A DOMAIN THAT DOES NOT START AT ZERO, because a fixture of 0..100 over ten
    divisions makes `i * (max - min) / n + min` and `i * 10` the same number. }
  AssertEquals(-20.0, TyGaugeLabelValue(-20, 30, 0, 5), 1e-9);
  AssertEquals(-10.0, TyGaugeLabelValue(-20, 30, 1, 5), 1e-9);
  AssertEquals(30.0, TyGaugeLabelValue(-20, 30, 5, 5), 1e-9);
  { `splitNumber: 0` divides by zero upstream and prints NaN at every position;
    here a dial with no divisions still has its own floor. }
  AssertEquals('no divisions', 7.0, TyGaugeLabelValue(7, 90, 0, 0), 1e-9);
end;

procedure TAdvChartGaugeRuleTest.TestTheFormatterReplacesOnlyTheFirstToken;
begin
  AssertEquals('no formatter is the number itself', '70',
               TyGaugeFormat('', False, 70));
  AssertEquals('{value} km/h', '70 km/h',
               TyGaugeFormat('{value} km/h', True, 70));
  { FIRST ONLY. JavaScript's replace takes a plain string here, so a second
    token is emitted literally -- and a port reaching for rfReplaceAll makes a
    different chart out of the same option text. }
  AssertEquals('the second token survives', '70 of {value}',
               TyGaugeFormat('{value} of {value}', True, 70));
  { A formatter with no token at all is a constant caption. }
  AssertEquals('done', TyGaugeFormat('done', True, 70));
end;

procedure TAdvChartGaugeRuleTest.
  TestTheCentreAndTheRadiusAreMeasuredAgainstDifferentThings;
var
  lay: TTyGaugeLayout;
  spec: TTyGaugeSpec;
begin
  { TWO BASES, and a square viewport cannot tell them apart. The rect here is
    400 x 200: the centre's percentages run against 400 and 200 SEPARATELY,
    while the radius' runs against half the SHORTER side -- 100. }
  lay := LayoutOf(TyGaugeSpecDefault);
  AssertTrue(lay.Valid);
  AssertEquals('the centre is half the width across', 200.0, lay.CX, 1e-9);
  AssertEquals('and half the height down', 100.0, lay.CY, 1e-9);
  AssertEquals('the radius is 75% of half the SHORTER side', 75.0, lay.R, 1e-9);
  { A percentage centre that is not one half, so a mutant that ignores the
    option entirely still fails. }
  spec := SpecOf('{"series":[{"type":"gauge","center":["25%","75%"],'
    + '"radius":"50%"}]}');
  lay := LayoutOf(spec);
  AssertEquals('a quarter across', 100.0, lay.CX, 1e-9);
  AssertEquals('three quarters down', 150.0, lay.CY, 1e-9);
  AssertEquals('half of a hundred', 50.0, lay.R, 1e-9);
end;

procedure TAdvChartGaugeRuleTest.TestSplitNumberZeroIsNotADivisionByZero;
var
  spec: TTyGaugeSpec;
begin
  { BOTH DIVISORS ARE USER OPTIONS AND NEITHER IS GUARDED UPSTREAM: in
    JavaScript the step becomes Infinity and then NaN, and every position after
    the first is lost; here it would raise. }
  spec := SpecOf('{"series":[{"type":"gauge","splitNumber":0}]}');
  AssertEquals('the option is read as written', 0, spec.SplitNumber);
  AssertTrue('and the dial still builds', BuildAxis(spec) > 0);
  spec := SpecOf('{"series":[{"type":"gauge","axisTick":{"splitNumber":0}}]}');
  AssertEquals(0, spec.AxisTick.SplitNumber);
  AssertTrue('and so does it with no minor ticks', BuildAxis(spec) > 0);
end;

procedure TAdvChartGaugeRuleTest.
  TestTheLabelRingIgnoresTheTrackButNotTheSplitLineDistance;
var
  base, wider, further: TTyGaugeSpec;
  lay: TTyGaugeLayout;
  n: Integer;

  { The x of the leftmost label in the list, which for the default dial is the
    one at nine o'clock and is the only thing on that side. }
  function LeftmostCaption: Double;
  var i: Integer; e: TTyChartElement;
  begin
    Result := 1e30;
    for i := 0 to FList.Count - 1 do
    begin
      e := FList.Element(i);
      if e.Caption.Text = '' then Continue;
      if e.Caption.X < Result then Result := e.Caption.X;
    end;
  end;

begin
  { THE ASYMMETRY IS UPSTREAM'S AND IT IS NOT OBVIOUS. A tick starts at
    `r - (distance + axisLineWidth)`; a LABEL sits at
    `r - splitLineLen - (axisLabel.distance + splitLine.distance)` -- no track
    width at all, and it borrows the SPLIT LINE's distance as well as its own.
    So widening the track moves the ticks and leaves the labels, and moving the
    split lines moves the labels. }
  base := TyGaugeSpecDefault;
  lay := LayoutOf(base);
  n := BuildAxis(base);
  AssertTrue(n > 0);
  base.Min_ := LeftmostCaption;

  wider := TyGaugeSpecDefault;
  wider.AxisLine.WidthLogical := 40;
  BuildAxis(wider);
  AssertEquals('a wider track leaves the labels alone', base.Min_,
               LeftmostCaption, 0.001);

  further := TyGaugeSpecDefault;
  further.SplitLine.Distance := 40;
  BuildAxis(further);
  AssertTrue(Format('a further split line moves them inward (%g -> %g)',
                    [base.Min_, LeftmostCaption]),
             LeftmostCaption > base.Min_ + 10);
  AssertTrue('and the dial is still where it was', lay.Valid);
end;

procedure TAdvChartGaugeRuleTest.TestPerDatumOffsetCentreComesFromTheDataArray;
var
  items: TTyGaugeItemArray;
begin
  { THE ONE THING THE OVERRIDE TABLE CANNOT CARRY. Per-datum options are
    interned from the raw data item as SCALAR leaves, and `offsetCenter` is an
    array -- so a multi-value gauge's two readings would stack on one spot if
    this came through the store. It is read from the series' own data instead. }
  items := ItemsOf('{"series":[{"type":"gauge","data":['
    + '{"value":1,"title":{"offsetCenter":[0,"-30%"]},'
    + '"detail":{"offsetCenter":["20%","10%"]}},'
    + '{"value":2}]}]}');
  AssertEquals('one entry per datum', 2, Length(items));
  AssertEquals('the written title offset', Ord(buPercent),
               Ord(items[0].Title.OffsetY.Kind));
  AssertEquals(-30.0, items[0].Title.OffsetY.Value, 1e-9);
  AssertEquals('the written reading offset', 20.0,
               items[0].Detail.OffsetX.Value, 1e-9);
  AssertEquals(10.0, items[0].Detail.OffsetY.Value, 1e-9);
  { THE OTHER DATUM KEEPS THE SERIES' OWN, rather than the first datum's --
    the seed is the spec, not the neighbour. }
  AssertEquals('the second is the series default', 20.0,
               items[1].Title.OffsetY.Value, 1e-9);
  AssertEquals(40.0, items[1].Detail.OffsetY.Value, 1e-9);
  AssertEquals(0.0, items[1].Detail.OffsetX.Value, 1e-9);
end;

procedure TAdvChartGaugeRuleTest.TestARotateWrittenAsAStringIsNoRotationAtAll;
var spec: TTyGaugeSpec;
begin
  spec := SpecOf('{"series":[{"type":"gauge","axisLabel":{"rotate":"radial"}}]}');
  AssertEquals(Ord(glrRadial), Ord(spec.AxisLabel.Rotate));
  spec := SpecOf('{"series":[{"type":"gauge","axisLabel":'
    + '{"rotate":"tangential"}}]}');
  AssertEquals(Ord(glrTangential), Ord(spec.AxisLabel.Rotate));
  spec := SpecOf('{"series":[{"type":"gauge","axisLabel":{"rotate":30}}]}');
  AssertEquals(Ord(glrNumber), Ord(spec.AxisLabel.Rotate));
  AssertEquals(30.0, spec.AxisLabel.RotateDeg, 1e-9);
  { A NUMBER IN QUOTES IS NOT A NUMBER. Upstream tests isNumber and nothing
    catches the string, so `rotate: '30'` leaves the labels upright -- kept,
    because tightening it would draw a different chart from the same text. }
  spec := SpecOf('{"series":[{"type":"gauge","axisLabel":{"rotate":"30"}}]}');
  AssertEquals(Ord(glrNumber), Ord(spec.AxisLabel.Rotate));
  AssertEquals('no rotation at all', 0.0, spec.AxisLabel.RotateDeg, 1e-9);
  { AND A HUGE ONE IS CLAMPED BEFORE IT IS MULTIPLIED, because 1e308 degrees
    times Pi/180 is an overflow that would reach every coordinate. }
  spec := SpecOf('{"series":[{"type":"gauge","axisLabel":{"rotate":1e308}}]}');
  AssertEquals(360.0, spec.AxisLabel.RotateDeg, 1e-9);
end;

procedure TAdvChartGaugeRuleTest.TestTheMinorTicksAreCountedUpstreamsWay;
var
  spec: TTyGaugeSpec;
  withTicks, without: Integer;
begin
  { `j <= subSplitNumber` IS THE BOUND, so each major interval draws
    subSplitNumber + 1 minor ticks and the last of one lands exactly on the
    first of the next. That is upstream's own off-by-one and it is visible with
    a translucent stroke, so it is reproduced rather than thinned.

    Counted rather than asserted as a rule, because the arithmetic is the only
    thing that can go wrong: 10 intervals x 6 ticks = 60. }
  spec := TyGaugeSpecDefault;
  spec.SplitLine.Show := False;
  spec.AxisLabel.Show := False;
  spec.AxisLine.Show := False;
  withTicks := BuildAxis(spec);
  AssertEquals('ten intervals of six', 60, withTicks);
  spec.AxisTick.Show := False;
  without := BuildAxis(spec);
  AssertEquals('and nothing at all without them', 0, without);
end;

procedure TAdvChartGaugeRuleTest.TestANaNValueIsParkedEvenOnADialOfNoWidth;
var lay: TTyGaugeLayout;
begin
  { THE GUARD IS NOT THE MAP'S. A degenerate domain is answered BEFORE the
    map's own NaN test, so `min: 50, max: 50` with a value of NaN would come
    back as the middle of the dial -- a needle pointing confidently at nothing.
    The gauge tests NaN first, which is the only case where the two differ. }
  lay := LayoutOf(TyGaugeSpecDefault);
  AssertEquals('a real value on a dial of no width is the middle',
    (lay.StartRad + lay.EndRad) / 2, TyGaugeAngleOf(lay, 50, 50, 50, True), 1e-9);
  AssertEquals('but NaN still parks at the start', lay.StartRad,
    TyGaugeAngleOf(lay, 50, 50, NaN, True), 1e-9);
end;

procedure TAdvChartGaugeRuleTest.TestTheLabelAnchorThresholdsAreNotSymmetric;
var
  i: Integer;
  e: TTyChartElement;
  found: Boolean;
  spec: TTyGaugeSpec;
begin
  { 0.8 VERTICALLY AND 0.4 HORIZONTALLY, which is upstream's and is not a
    typo -- a label at forty-five degrees is pinned by its RIGHT edge and
    centred vertically, so the words grow toward the dial rather than over it.
    Symmetric thresholds centre it on its own anchor and let it sit on the rim.

    The FIRST label of the default dial is the 45-degree case: it sits at the
    lower left, cos = -0.707 and sin = +0.707 -- outside the horizontal
    threshold and inside the vertical one, which symmetric thresholds cannot
    reproduce. }
  spec := TyGaugeSpecDefault;
  spec.SplitNumber := 2;
  BuildAxis(spec);
  found := False;
  for i := 0 to FList.Count - 1 do
  begin
    e := FList.Element(i);
    if e.Caption.Text <> '0' then Continue;
    found := True;
    { Pinned by its LEFT edge, so the words grow from the anchor toward the
      dial rather than away from it -- and vertically centred, because 0.707
      clears the horizontal threshold and not the vertical one. }
    AssertEquals('pinned by its left edge', Ord(tahLeft),
                 Ord(e.Caption.AnchorH));
    AssertEquals('and centred vertically', Ord(tavMiddle),
                 Ord(e.Caption.AnchorV));
  end;
  AssertTrue('the 45-degree label was found', found);
  { AND THE ONE AT THE TOP is centred across and hung below its point -- so
    the two axes really are asked different questions. }
  found := False;
  for i := 0 to FList.Count - 1 do
  begin
    e := FList.Element(i);
    if e.Caption.Text <> '50' then Continue;
    found := True;
    AssertEquals('centred across', Ord(tahCentre), Ord(e.Caption.AnchorH));
    AssertEquals('and hung below the point', Ord(tavTop),
                 Ord(e.Caption.AnchorV));
  end;
  AssertTrue('the top label was found', found);
end;

procedure TAdvChartGaugeRuleTest.TestALabelIsMeasuredInTheFontItIsDrawnIn;
var
  i: Integer;
  e: TTyChartElement;
  spec: TTyGaugeSpec;
  wide, narrow: Double;

  function WidestCaptionBox: Double;
  var j: Integer; el: TTyChartElement;
  begin
    Result := 0;
    for j := 0 to FList.Count - 1 do
    begin
      el := FList.Element(j);
      if el.Caption.Text = '' then Continue;
      if el.Shape.Bounds.Right - el.Shape.Bounds.Left > Result then
        Result := el.Shape.Bounds.Right - el.Shape.Bounds.Left;
    end;
  end;

begin
  { MEASURED FIRST AND RESOLVED SECOND IS THE BUG. The renderer draws the
    words INTO the element's own rectangle, so a label measured at the theme's
    nine points and drawn at the option's thirty comes out clipped -- `100`
    became `00`, and every test that only asked "are there labels" stayed
    green. }
  spec := TyGaugeSpecDefault;
  spec.AxisLabel.HasFontSize := False;
  BuildAxis(spec);
  narrow := WidestCaptionBox;
  spec.AxisLabel.HasFontSize := True;
  spec.AxisLabel.FontSizeLogical := 30;
  BuildAxis(spec);
  wide := WidestCaptionBox;
  AssertTrue(Format('a bigger font needs a bigger box (%g -> %g)',
                    [narrow, wide]), wide > narrow * 1.5);
  { And the caption really carries that size, so the two cannot drift apart. }
  for i := 0 to FList.Count - 1 do
  begin
    e := FList.Element(i);
    if e.Caption.Text = '' then Continue;
    AssertEquals('drawn at the size it was measured at', 30,
                 e.Caption.FontSizeLogical);
    Break;
  end;
end;

procedure TAdvChartGaugeRuleTest.
  TestTheTicksStartInsideTheTrackAndTheTrackWidthMovesThem;
var
  spec: TTyGaugeSpec;
  thin, thick: Double;

  { The x of the leftmost split line's outer end. }
  function OuterTickX: Double;
  var j: Integer; el: TTyChartElement;
  begin
    Result := 1e30;
    for j := 0 to FList.Count - 1 do
    begin
      el := FList.Element(j);
      if el.Shape.Kind <> cskPolyline then Continue;
      if Length(el.Shape.Points) < 2 then Continue;
      if el.Shape.Points[0].X < Result then Result := el.Shape.Points[0].X;
    end;
  end;

begin
  { A TICK STARTS AT `r - (distance + trackWidth)`, so widening the track
    pushes every tick INWARD -- the opposite of what it does to the labels,
    and the asymmetry is upstream's. }
  spec := TyGaugeSpecDefault;
  spec.AxisLabel.Show := False;
  spec.AxisTick.Show := False;
  BuildAxis(spec);
  thin := OuterTickX;
  spec.AxisLine.WidthLogical := 40;
  BuildAxis(spec);
  thick := OuterTickX;
  AssertTrue(Format('a wider track pushes the ticks inward (%g -> %g)',
                    [thin, thick]), thick > thin + 20);
end;

procedure TAdvChartGaugeRuleTest.TestAStopPastTheEndsIsClamped;
var
  spec: TTyGaugeSpec;
  lay: TTyGaugeLayout;
begin
  { NOTHING REQUIRES A STOP TO BE IN RANGE. `[[1.4, red]]` is clamped to one,
    so the band covers the dial and no more; without the clamp it would sweep
    half a turn past the end and wrap over itself. }
  spec := SpecOf('{"series":[{"type":"gauge","axisLine":{"lineStyle":'
    + '{"color":[[1.4,"#ff0000"]]}}}]}');
  lay := LayoutOf(spec);
  AssertEquals('clamped to the end of the dial', lay.EndRad, lay.BandEndRad,
               1e-9);
  spec := SpecOf('{"series":[{"type":"gauge","axisLine":{"lineStyle":'
    + '{"color":[[-2,"#ff0000"]]}}}]}');
  lay := LayoutOf(spec);
  AssertEquals('and at the start', lay.StartRad, lay.BandEndRad, 1e-9);
end;

procedure TAdvChartGaugeRuleTest.TestTheEarlierStopIsPaintedOverTheLaterOne;
var
  spec: TTyGaugeSpec;
  i, firstBand, secondBand: Integer;
  e: TTyChartElement;
begin
  { UPSTREAM REVERSES THE LIST BEFORE ADDING IT, so the FIRST stop ends up
    topmost. It only shows when two bands overlap -- and they can, because
    nothing requires the stops to ascend.

    A FIXTURE OF ASCENDING STOPS CANNOT SEE THIS AT ALL: the bands do not
    overlap, so any order draws the same picture. These two do -- the first
    covers the whole dial and the second covers half of it. }
  spec := SpecOf('{"series":[{"type":"gauge","axisLine":{"lineStyle":'
    + '{"color":[[1,"#ff0000"],[0.5,"#00ff00"]]}}}]}');
  BuildAxis(spec);
  firstBand := -1;
  secondBand := -1;
  for i := 0 to FList.Count - 1 do
  begin
    e := FList.Element(i);
    if e.Shape.Kind <> cskSector then Continue;
    if (e.Style.FillColor = TTyChartColor($FFFF0000)) and (firstBand < 0) then
      firstBand := i;
    if (e.Style.FillColor = TTyChartColor($FF00FF00)) and (secondBand < 0) then
      secondBand := i;
  end;
  AssertTrue('both bands are there', (firstBand >= 0) and (secondBand >= 0));
  { Same Z and Z2, so the list falls back to insertion order and LATER is on
    top. The first stop must therefore be inserted last. }
  AssertTrue(Format('the first stop is inserted after the second (%d > %d)',
                    [firstBand, secondBand]), firstBand > secondBand);
end;

procedure TAdvChartGaugeRuleTest.
  TestAnOverlappingProgressArcIsStackedSmallestFirst;
var
  spec: TTyGaugeSpec;
  i, zSmall, zLarge: Integer;
  e: TTyChartElement;
  st: TTyDataStore;
begin
  { THE RANGE IS INVERTED ON PURPOSE: min maps to 100 and max to 0, so the
    SMALLEST arc paints on top of the larger ones instead of being buried
    under them. That is the whole point of `overlap`. }
  spec := SpecOf('{"series":[{"type":"gauge","progress":{"show":true},'
    + '"pointer":{"show":false},"title":{"show":false},'
    + '"detail":{"show":false}}]}');
  st := StoreOf([20, 80]);
  FList.Clear;
  TyBuildGaugeValue(Binding, LayoutOf(spec), spec, nil, TyGaugeVisual, st, 0,
    TTyPainterTextMeasurer.Create(96), 96, FList);
  zSmall := -1;
  zLarge := -1;
  for i := 0 to FList.Count - 1 do
  begin
    e := FList.Element(i);
    if e.Shape.Kind <> cskSector then Continue;
    if e.Datum.DataIndex = 0 then zSmall := e.Z2;
    if e.Datum.DataIndex = 1 then zLarge := e.Z2;
  end;
  AssertTrue('both arcs are there', (zSmall >= 0) and (zLarge >= 0));
  AssertTrue(Format('the smaller value sits on top (%d > %d)',
                    [zSmall, zLarge]), zSmall > zLarge);
end;

procedure TAdvChartGaugeRuleTest.TestProgressClipLetsTheArcRunPastTheDial;
var
  spec: TTyGaugeSpec;
  st: TTyDataStore;

  function ArcSweep: Double;
  var j: Integer; el: TTyChartElement;
  begin
    Result := 0;
    for j := 0 to FList.Count - 1 do
    begin
      el := FList.Element(j);
      if el.Shape.Kind <> cskSector then Continue;
      Result := Abs(el.Shape.EndRad - el.Shape.StartRad);
    end;
  end;

begin
  { `clip: false` IS THE ONLY WAY AN ARC LEAVES THE DIAL, and it is the only
    thing the flag does -- it is the clamp argument of the value map and
    nothing else. With it on, a value of 300 on a 0..100 dial stops at the end;
    with it off the sweep runs three times as far. }
  st := StoreOf([300]);
  spec := SpecOf('{"series":[{"type":"gauge","progress":{"show":true},'
    + '"pointer":{"show":false},"title":{"show":false},'
    + '"detail":{"show":false}}]}');
  FList.Clear;
  TyBuildGaugeValue(Binding, LayoutOf(spec), spec, nil, TyGaugeVisual, st, 0,
    TTyPainterTextMeasurer.Create(96), 96, FList);
  AssertEquals('clipped, it stops at the end of the dial', 1.5 * Pi, ArcSweep,
               1e-6);
  spec := SpecOf('{"series":[{"type":"gauge","progress":{"show":true,'
    + '"clip":false},"pointer":{"show":false},"title":{"show":false},'
    + '"detail":{"show":false}}]}');
  FList.Clear;
  TyBuildGaugeValue(Binding, LayoutOf(spec), spec, nil, TyGaugeVisual, st, 0,
    TTyPainterTextMeasurer.Create(96), 96, FList);
  AssertTrue(Format('unclipped, it runs past it (%g)', [ArcSweep]),
             ArcSweep > 4 * Pi);
end;

procedure TAdvChartGaugeRuleTest.TestARichFormatterDegradesToItsWords;
begin
  { A RUN THIS PORT DOES NOT DRAW IS STILL A READING. `{a|83}{b| km/h}` names
    two styles the author declared under `rich:`; printed as written it is
    line noise where the number should be.
    [Batch 86: a detail that DECLARES `rich` is now laid out as its block --
    AddGaugeText asks TyGaugeFormat to keep the markup (AKeepRich) and draws
    the tokens -- so the degrade held here is only what a formatter's
    markup comes to when the detail names no rich styles for it: its words.
    The rich path is held against upstream by test.advchart.richwiring
    (gauge-detail-box).] }
  AssertEquals('83 km/h', TyGaugeFormat('{a|{value}}{b| km/h}', True, 83));
  AssertEquals('the value token still works alone', '83 km/h',
               TyGaugeFormat('{value} km/h', True, 83));
  { A BRACE WITH NO BAR IS NOT A RUN, so an unsubstituted token survives
    rather than being eaten. }
  AssertEquals('{other}', TyGaugeFormat('{other}', True, 83));
  { AND THE BAR HAS TO BE INSIDE THAT BRACE. A stray token FOLLOWED by a real
    run is the only fixture that can tell "look ahead for a bar" from "look
    ahead for a bar before the next brace" -- with the stray token alone there
    is no bar anywhere and the two answers agree. }
  AssertEquals('{other} x', TyGaugeFormat('{other} ' + '{a|x}', True, 83));
  { And real line breaks are flattened, because a caption is one run here. }
  AssertEquals('a b', TyGaugeFormat('a' + #10 + 'b', True, 83));
end;

procedure TAdvChartGaugeRuleTest.
  TestABandIsClampedAndStartsWhereTheLastOneStopped;
var
  spec: TTyGaugeSpec;
  lay: TTyGaugeLayout;
  i, n: Integer;
  e: TTyChartElement;
  first, second: TTyChartShape;
begin
  { TWO THINGS THE LAYOUT'S OWN RECORD CANNOT ANSWER FOR. `BandEndRad` has a
    clamp of its own, so asserting on it says nothing about the clamp inside
    the band loop; and no record at all says where each band BEGINS.

    A stop past the end sweeps half a turn past the dial unclamped, which
    wraps over the dial's own start and paints the arc twice. }
  spec := SpecOf('{"series":[{"type":"gauge","splitLine":{"show":false},'
    + '"axisTick":{"show":false},"axisLabel":{"show":false},'
    + '"axisLine":{"lineStyle":{"color":[[1.4,"#ff0000"]]}}}]}');
  lay := LayoutOf(spec);
  n := BuildAxis(spec);
  AssertEquals('one band', 1, n);
  e := FList.Element(0);
  AssertEquals('the band is a sector', Ord(cskSector), Ord(e.Shape.Kind));
  AssertEquals('clamped to the dial''s own sweep', Abs(lay.Span),
               Abs(e.Shape.EndRad - e.Shape.StartRad), 1e-6);

  { EACH BAND PICKS UP WHERE THE LAST ONE STOPPED. Every fraction is an upper
    bound measured from the dial's start, so a band that began at the start
    would be drawn over the one before it -- invisible with opaque fills and
    doubled with a translucent one, which is why this is asserted on the
    GEOMETRY rather than on a pixel. }
  spec := SpecOf('{"series":[{"type":"gauge","splitLine":{"show":false},'
    + '"axisTick":{"show":false},"axisLabel":{"show":false},'
    + '"axisLine":{"lineStyle":{"color":[[0.3,"#ff0000"],[0.7,"#00ff00"],'
    + '[1,"#0000ff"]]}}}]}');
  lay := LayoutOf(spec);
  BuildAxis(spec);
  AssertEquals('three bands', 3, FList.Count);
  { Added in reverse, so element 0 is the LAST stop. }
  first := FList.Element(2).Shape;
  second := FList.Element(1).Shape;
  AssertEquals('the first band starts at the dial', lay.StartRad,
               first.StartRad, 1e-6);
  AssertEquals('and ends three tenths along',
               lay.StartRad + lay.Span * 0.3, first.EndRad, 1e-6);
  AssertEquals('the second begins where the first stopped', first.EndRad,
               second.StartRad, 1e-6);
  AssertEquals('and ends seven tenths along',
               lay.StartRad + lay.Span * 0.7, second.EndRad, 1e-6);
  i := 0;
  AssertEquals('nothing else was added', 3, FList.Count - i);
end;

{ ==================== the drawing ==================== }

procedure TAdvChartGaugeDrawTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TChartProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := nil;
end;

procedure TAdvChartGaugeDrawTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartGaugeDrawTest.Draw(const AOption: string);
begin
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(cW, cH, BGRAWhite);
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartGaugeDrawTest.ColouredPixels: Integer;
var
  x, y, lo, hi: Integer;
  row: PBGRAPixel;
begin
  Result := 0;
  for y := 0 to cH - 1 do
  begin
    row := FBmp.ScanLine[y];
    for x := 0 to cW - 1 do
    begin
      lo := Min(row^.red, Min(row^.green, row^.blue));
      hi := Max(row^.red, Max(row^.green, row^.blue));
      if (row^.alpha <> 0) and (hi - lo > 25) then Inc(Result);
      Inc(row);
    end;
  end;
end;

function TAdvChartGaugeDrawTest.Diagnostics: string;
var i: Integer;
begin
  Result := '';
  for i := 0 to FChart.DiagnosticCount - 1 do
    Result := Result + FChart.Diagnostic(i) + '|';
end;

procedure TAdvChartGaugeDrawTest.TestAGaugeDrawsAtAll;
var ink: Integer;

  { Anything that is not the white ground -- the dial is grey and the ticks are
    grey, so a saturation test would report an empty chart. }
  function InkPixels: Integer;
  var x, y: Integer; row: PBGRAPixel;
  begin
    Result := 0;
    for y := 0 to cH - 1 do
    begin
      row := FBmp.ScanLine[y];
      for x := 0 to cW - 1 do
      begin
        if (row^.alpha <> 0) and ((row^.red < 240) or (row^.green < 240)
          or (row^.blue < 240)) then Inc(Result);
        Inc(row);
      end;
    end;
  end;

begin
  { IT COULD NOT UNTIL THIS BATCH, and for the same one-line reason the funnel
    could not: the registry had said `scuBox` about a gauge since the day it
    was written, and nothing downstream had a branch for it. }
  Draw(cGauge);
  ink := InkPixels;
  AssertTrue(Format('the dial is on the canvas (%d px)', [ink]), ink > 2000);
end;

procedure TAdvChartGaugeDrawTest.TestItSaysNothingAboutHavingNoRenderer;
begin
  Draw(cGauge);
  AssertEquals('a gauge draws now', '', Diagnostics);
end;

procedure TAdvChartGaugeDrawTest.TestTheNeedleSwingsWithTheValue;
var
  lowX, highX: Integer;

  { The x of the saturated pixel FARTHEST FROM THE HUB, which is the needle's
    tip -- the needle is the only saturated thing on a default dial, and its
    tip is the only part of it that says which way it points. An earlier
    version of this read one band of rows above the hub and found the TAIL,
    which points the other way and made the test disagree with the picture. }
  function NeedleTipX: Integer;
  var
    x, y, lo, hi, cx, cy, d, best: Integer;
    row: PBGRAPixel;
  begin
    Result := -1;
    best := -1;
    cx := cW div 2;
    cy := cH div 2;
    for y := 0 to cH - 1 do
    begin
      row := FBmp.ScanLine[y];
      for x := 0 to cW - 1 do
      begin
        lo := Min(row^.red, Min(row^.green, row^.blue));
        hi := Max(row^.red, Max(row^.green, row^.blue));
        if (row^.alpha <> 0) and (hi - lo > 60) then
        begin
          d := (x - cx) * (x - cx) + (y - cy) * (y - cy);
          if d > best then
          begin
            best := d;
            Result := x;
          end;
        end;
        Inc(row);
      end;
    end;
  end;

begin
  { THE ONE ASSERTION THAT CANNOT BE SATISFIED BY A MIRRORED DIAL. At the
    minimum the needle leans LEFT of the hub and at the maximum it leans
    RIGHT, because the default dial runs clockwise from the lower left. A port
    that negated once too often draws both the other way and every radian in
    this file still agrees with it. }
  Draw('{"tooltip":{"show":false},"series":[{"type":"gauge","data":[{"value":0}]'
    + ',"detail":{"show":false},"axisLabel":{"show":false}}]}');
  lowX := NeedleTipX;
  Draw('{"tooltip":{"show":false},"series":[{"type":"gauge","data":[{"value":100}]'
    + ',"detail":{"show":false},"axisLabel":{"show":false}}]}');
  highX := NeedleTipX;
  AssertTrue('a needle was found at the minimum', lowX >= 0);
  AssertTrue('and at the maximum', highX >= 0);
  AssertTrue(Format('the minimum leans left of centre (%d)', [lowX]),
             lowX < cW div 2 - 10);
  AssertTrue(Format('and the maximum leans right (%d)', [highX]),
             highX > cW div 2 + 10);
end;

procedure TAdvChartGaugeDrawTest.TestTheReadingIsDrawnUnderTheHub;
var withIt, without: Integer;

  { Dark pixels in the band the reading sits in -- 40% of the radius below the
    hub -- and nowhere else, so the dial's own ink cannot answer for it. }
  function ReadingInk: Integer;
  var x, y: Integer; row: PBGRAPixel;
  begin
    Result := 0;
    for y := cH div 2 + 40 to cH div 2 + 90 do
    begin
      row := FBmp.ScanLine[y];
      for x := cW div 2 - 60 to cW div 2 + 60 do
        if (row + x)^.red < 150 then Inc(Result);
    end;
  end;

begin
  Draw('{"tooltip":{"show":false},"series":[{"type":"gauge",'
    + '"data":[{"value":70}]}]}');
  withIt := ReadingInk;
  Draw('{"tooltip":{"show":false},"series":[{"type":"gauge",'
    + '"detail":{"show":false},"data":[{"value":70}]}]}');
  without := ReadingInk;
  AssertTrue(Format('the reading is words on the canvas (%d px)', [withIt]),
             withIt > 60);
  AssertTrue(Format('and switching it off removes them (%d)', [without]),
             without < withIt div 3);
end;

procedure TAdvChartGaugeDrawTest.TestABandIsPaintedInItsOwnColour;
var
  px: TBGRAPixel;
  x: Integer;
  found: Boolean;
begin
  { THE STOPS ARE CUMULATIVE UPPER BOUNDS, so [[0.5, red], [1, green]] is red
    for the first half of the dial and green for the second -- not a band of
    half the dial and a band of all of it. The first half of the default dial
    runs from the lower left up over the TOP, so the pixel to look at is the
    top of the ring. }
  Draw('{"tooltip":{"show":false},"series":[{"type":"gauge",'
    + '"pointer":{"show":false},"detail":{"show":false},'
    + '"axisLabel":{"show":false},"splitLine":{"show":false},'
    + '"axisTick":{"show":false},"axisLine":{"lineStyle":{"width":20,'
    + '"color":[[0.5,"#ff0000"],[1,"#00ff00"]]}},"data":[{"value":10}]}]}');
  { SAMPLED ON THE ROW THROUGH THE HUB, at the two sides -- NOT at the top of
    the ring, which is exactly where the two bands meet and where a sample
    reads whichever one won the seam. }
  found := False;
  for x := 0 to cW div 2 do
  begin
    px := FBmp.GetPixel(x, cH div 2);
    if (px.red > 180) and (px.green < 90) then
    begin
      found := True;
      Break;
    end;
  end;
  AssertTrue('the first stop''s red is on the left of the dial', found);
  { AND THE SECOND STOP'S GREEN IS ON THE RIGHT, where the second half ends. }
  found := False;
  for x := cW - 1 downto cW div 2 do
  begin
    px := FBmp.GetPixel(x, cH div 2);
    if (px.green > 180) and (px.red < 90) then
    begin
      found := True;
      Break;
    end;
  end;
  AssertTrue('and the second stop''s green on the right', found);
  { AND THEY ARE NOT THE SAME COLOUR, which is what a fixture with one stop
    would fail to notice. }
  AssertTrue('two bands, two colours',
    FBmp.GetPixel(4 + cW div 2 - 142, cH div 2).red >
    FBmp.GetPixel(cW div 2 + 142 - 4, cH div 2).red);
end;

procedure TAdvChartGaugeDrawTest.TestTheProgressArcGrowsWithTheValue;
var small, large: Integer;

  function AccentPixels: Integer;
  var x, y, lo, hi: Integer; row: PBGRAPixel;
  begin
    Result := 0;
    for y := 0 to cH - 1 do
    begin
      row := FBmp.ScanLine[y];
      for x := 0 to cW - 1 do
      begin
        lo := Min(row^.red, Min(row^.green, row^.blue));
        hi := Max(row^.red, Max(row^.green, row^.blue));
        if (row^.alpha <> 0) and (hi - lo > 40) then Inc(Result);
        Inc(row);
      end;
    end;
  end;

const
  cFmt = '{"tooltip":{"show":false},"series":[{"type":"gauge",'
    + '"progress":{"show":true,"width":18},"pointer":{"show":false},'
    + '"detail":{"show":false},"axisLabel":{"show":false},'
    + '"splitLine":{"show":false},"axisTick":{"show":false},'
    + '"data":[{"value":%d}]}]}';
begin
  { A PROGRESS ARC IS THE VALUE MADE INTO A SWEEP, so ten per cent of the dial
    is about a ninth of the ink ninety per cent is. Counted rather than
    compared to a constant, because the accent colour is the theme's. }
  Draw(Format(cFmt, [10]));
  small := AccentPixels;
  Draw(Format(cFmt, [90]));
  large := AccentPixels;
  AssertTrue(Format('a small value draws a short arc (%d px)', [small]),
             small > 100);
  AssertTrue(Format('a large one draws far more (%d vs %d)', [large, small]),
             large > small * 3);
end;

procedure TAdvChartGaugeDrawTest.TestTheNeedleReportsItsDatum;
var
  hit: TTyChartDatumRef;
  lay: TTyGaugeLayout;
  spec: TTyGaugeSpec;
  ang: Double;
  elem: Integer;
begin
  { THE NEEDLE AND THE ARC ARE THE ONLY THINGS ON A GAUGE THAT ARE NOT SILENT.
    The dial, the ticks, the scale, the name and the reading are all furniture:
    a hover on the band behind the needle would report a datum the band does
    not stand for. }
  Draw('{"tooltip":{"show":false},"series":[{"type":"gauge",'
    + '"data":[{"name":"score","value":100}]}]}');
  spec := TyGaugeSpecDefault;
  lay := TyGaugeLayoutOf(spec, TyRectF(0, 0, cW, cH), 96);
  AssertTrue(lay.Valid);
  ang := TyGaugeAngleOf(lay, 0, 100, 100, True);
  { Half way out along the needle, which is inside the kite and outside the
    hub. }
  hit := FChart.HitTestAt(Round(lay.CX + lay.R * 0.3 * Cos(ang)),
                          Round(lay.CY + lay.R * 0.3 * Sin(ang)));
  AssertEquals('the needle is the series'' own', 0, hit.SeriesIndex);
  AssertEquals('and its datum''s row', 0, hit.DataIndex);
  { THE TRACK IS NOT -- and the question has to be WHICH ELEMENT replied, not
    which datum. A band carries no datum, so a band that stopped being silent
    would still answer "series -1" and a test asking only that would never
    notice it had started swallowing hovers. }
  hit := FChart.HitTestAt(Round(lay.CX + (lay.R - 5) * Cos(lay.StartRad)),
                          Round(lay.CY + (lay.R - 5) * Sin(lay.StartRad)),
                          elem);
  AssertEquals('the band answers no datum', -1, hit.SeriesIndex);
  AssertEquals('and no element at all', -1, elem);
end;

procedure TAdvChartGaugeDrawTest.TestAPathPointerIsTurnedToTheValue;
var
  lowY, midY, lowX: Integer;

  { The x and the y of the red pixel farthest from the hub. The pointer is the
    only red thing on the canvas. }
  procedure Tip(out ATX, ATY: Integer);
  var x, y, cx, cy, d, best: Integer; row: PBGRAPixel;
  begin
    ATX := -1;
    ATY := -1;
    best := -1;
    cx := cW div 2;
    cy := cH div 2;
    for y := 0 to cH - 1 do
    begin
      row := FBmp.ScanLine[y];
      for x := 0 to cW - 1 do
      begin
        if (row^.alpha <> 0) and (row^.red > 180) and (row^.green < 90)
          and (row^.blue < 90) then
        begin
          d := (x - cx) * (x - cx) + (y - cy) * (y - cy);
          if d > best then
          begin
            best := d;
            ATX := x;
            ATY := y;
          end;
        end;
        Inc(row);
      end;
    end;
  end;

  function TipY: Integer;
  var tx: Integer;
  begin
    Tip(tx, Result);
  end;

  function TipX: Integer;
  var ty: Integer;
  begin
    Tip(Result, ty);
  end;

const
  cPath = '{"tooltip":{"show":false},"series":[{"type":"gauge",'
    + '"startAngle":180,"endAngle":0,"min":0,"max":1,'
    + '"axisLabel":{"show":false},"splitLine":{"show":false},'
    + '"axisTick":{"show":false},"detail":{"show":false},'
    + '"pointer":{"icon":"path://M12.8,0.7l12,40.1H0.7L12.8,0.7z",'
    + '"length":"40' + '%' + '","width":40,'
    + '"itemStyle":{"color":"#ff0000"}},'
    + '"data":[{"value":';
  { The same pointer, pushed half a radius out along its own axis. }
  cOffset = '{"tooltip":{"show":false},"series":[{"type":"gauge",'
    + '"startAngle":180,"endAngle":0,"min":0,"max":1,'
    + '"axisLabel":{"show":false},"splitLine":{"show":false},'
    + '"axisTick":{"show":false},"detail":{"show":false},'
    + '"pointer":{"icon":"path://M12.8,0.7l12,40.1H0.7L12.8,0.7z",'
    + '"length":"20' + '%' + '","width":40,'
    + '"offsetCenter":[0,"-50' + '%' + '"],'
    + '"itemStyle":{"color":"#ff0000"}},'
    + '"data":[{"value":';
  cPathEnd = '}]}]}';
begin
  { TEN OF THE TWENTY-TWO GAUGE SERIES IN THE GALLERY POINT WITH A `path://`,
    and a path is the one shape in this library that cannot be built already
    turned -- its geometry is a string in the author's own coordinates that
    the painter fits into a box at draw time. Without the rotation every one
    of them points straight up whatever the value says.

    Pinned on the TIP and on a half dial, where the two ends are horizontal:
    at either end the tip is level with the hub, in the middle it is well
    above it. A pointer that never turns has the same tip at both. }
  Draw(cPath + '0.0' + cPathEnd);
  lowY := TipY;
  lowX := TipX;
  Draw(cPath + '0.5' + cPathEnd);
  midY := TipY;
  AssertTrue('a pointer was found at the minimum', lowY >= 0);
  AssertTrue('and at the middle', midY >= 0);
  AssertTrue(Format('at the minimum the tip is level with the hub (%d)',
                    [lowY]), Abs(lowY - cH div 2) < 40);
  { AND ON THE LEFT OF IT. Turning the other way puts the same tip on the
    right at the same height, so the y alone cannot tell the two apart. }
  AssertTrue(Format('and to the left of it (%d)', [lowX]),
             lowX < cW div 2 - 30);
  AssertTrue(Format('and at the middle it is well above it (%d)', [midY]),
             midY < cH div 2 - 40);
  { AND IT TURNS ABOUT THE HUB, NOT ABOUT ITSELF. `offsetCenter` lives in the
    frame that turns, so a pointer pushed half a radius out along its own axis
    has to be CARRIED round by the same rotation. Turning it about its own
    foot leaves it hanging above the hub whatever the value is -- which with
    no offset at all is the same picture, and is why the fixture above cannot
    see it. }
  Draw(cOffset + '0.0' + cPathEnd);
  lowX := TipX;
  lowY := TipY;
  AssertTrue('an offset pointer was found', lowX >= 0);
  AssertTrue(Format('carried round to the left of the hub (%d)', [lowX]),
             lowX < cW div 2 - 60);
  AssertTrue(Format('and still level with it (%d)', [lowY]),
             Abs(lowY - cH div 2) < 40);
end;

initialization
  RegisterTest(TAdvChartGaugeRuleTest);
  RegisterTest(TAdvChartGaugeDrawTest);
end.
