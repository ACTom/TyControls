unit test.advchart.radar;
{$mode objfpc}{$H+}
{ The radar.

  THE ANGLES ARE THE WHOLE TEST AGAIN, and they are NOT the gauge's. A gauge
  negates its option degrees into the drawing frame; a radar does not -- it
  keeps the maths convention and subtracts the sine when it makes a point.
  So `startAngle: 90` is straight up on both, by two different routes, and a
  port that applied the pie's rule here would draw every radar mirrored while
  its first spoke still pointed the right way.

  Pinned by device pixel signs rather than by radians, for the same reason it
  was on the gauge: a radian computed the way the code computes it agrees with
  any convention at all. }
interface
uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Data,
     tyControls.AdvChart.Option, tyControls.AdvChart.Layout,
     tyControls.AdvChart.Shape, tyControls.AdvChart.Coord,
     tyControls.AdvChart.Radar, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Series, tyControls.AdvChart.Measure,
     tyControls.AdvChart.Color,
     tyControls.AdvanceChart, test.advancechart;
type
  TAdvChartRadarRuleTest = class(TTestCase)
  private
    FOpt: TTyChartOption;
    FRadar: TTyRadar;
    FList: TTyPaintList;
    procedure SetUp; override;
    procedure TearDown; override;
    function SpecOf(const AText: string): TTyRadarSpec;
    { A radar laid out against a deliberately NON-SQUARE rect. }
    function RadarOf(const AText: string): TTyRadar;
    function IndicatorOf(const AName: string; AHasMin: Boolean; AMin: Double;
      AHasMax: Boolean; AMax: Double): TTyRadarIndicator;
  published
    procedure TestTheFirstSpokePointsUpAndTheNextRunsAnticlockwise;
    procedure TestClockwiseReversesTheOrderWithoutMovingTheFirst;
    procedure TestASpokeAngleIsFoldedIntoOneTurn;
    procedure TestNoIndicatorsIsNotADivisionByZero;
    procedure TestTheCentreAndTheRadiusAreMeasuredAgainstDifferentThings;
    procedure TestAScalarRadiusIsTheOuterOneAndLeavesNoHole;
    procedure TestAWrittenMaxPinsTheFloorToZeroAndTheMirrorImage;
    procedure TestIncludeZeroOnlyMovesTheEndTheAuthorLeftAlone;
    procedure TestScaleTrueKeepsTheDataRange;
    procedure TestARangeOfNoWidthIsOpenedRatherThanLeftFlat;
    procedure TestNoDataAtAllIsAnAxisOfNothing;
    procedure TestTheRingsAreEvenlySpacedAndNotNiceTicks;
    procedure TestAnEmptyColourListIsAnAnswerRatherThanARemainderByZero;
    procedure TestTheCentreBelongsToNoSpoke;
    procedure TestAPointOnTheRimResolvesToItsOwnSpoke;
    procedure TestTheNameFormatterReplacesOnlyTheFirstToken;
    procedure TestShapeIsComparedWhole;
    procedure TestASplitNumberOfZeroIsTheDefaultAndNotZero;
    procedure TestThePinIsNotTheIncludeZeroPassWearingAHat;
    procedure TestIncludeZeroLeavesAWrittenEndAlone;
    procedure TestTheBandsSitBetweenConsecutiveRings;
    procedure TestABandIsOneContourWithItsInnerRingReversed;
    procedure TestTheGridDrawsItsPartsAndNoneOfThemIsHittable;
    procedure TestANameIsPinnedByTheEdgeFacingTheCentre;
    procedure TestACircleRadarUsesRoundBandsAndRoundRings;
    procedure TestAMissingValueLeavesTheRingRatherThanCollapsingIt;
    procedure TestARingOfOnePointIsNotDrawn;
    procedure TestTheRingClosesBackToItsFirstPoint;
    procedure TestEachRowTakesItsOwnColourAndTheRingIsHittable;
    procedure TestOnlyTheseTypesLetTheirRowsIntoTheLegend;
  end;

  TAdvChartRadarDrawTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TChartProbe;
    FBmp: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw(const AOption: string);
    function InkPixels: Integer;
    function Diagnostics: string;
  published
    procedure TestARadarDrawsAtAll;
    procedure TestItSaysNothingAboutHavingNoRenderer;
    procedure TestTheFirstIndicatorsNameIsAboveTheCentre;
    procedure TestTwoRowsAreTwoColoursOnOneRadar;
    procedure TestAnAreaStyleFillsTheRingAndNothingElseDoes;
    procedure TestACircleShapeIsRoundWhereAPolygonIsFlat;
    procedure TestARingReportsItsRow;
    procedure TestARadarIndexPastTheEndDrawsNothingAndSaysSo;
    procedure TestASwitchedOffRowDoesNotWidenItsSpoke;
  end;

implementation

const
  cW = 520;
  cH = 380;
  cInd =
    '"radar":{"indicator":[{"name":"a","max":100},{"name":"b","max":100},'
    + '{"name":"c","max":100},{"name":"d","max":100}]}';
  cRadar =
    '{"tooltip":{"show":false},' + cInd + ','
    + '"series":[{"type":"radar","data":['
    + '{"value":[60,70,80,50],"name":"one"},'
    + '{"value":[30,40,20,90],"name":"two"}]}]}';

{ ==================== the rules ==================== }

procedure TAdvChartRadarRuleTest.SetUp;
begin
  inherited SetUp;
  FList := TTyPaintList.Create;
end;

procedure TAdvChartRadarRuleTest.TearDown;
begin
  FreeAndNil(FList);
  FreeAndNil(FRadar);
  FreeAndNil(FOpt);
  inherited TearDown;
end;

function TAdvChartRadarRuleTest.SpecOf(const AText: string): TTyRadarSpec;
begin
  FreeAndNil(FOpt);
  FOpt := TTyChartOption.Create;
  AssertTrue('the fixture parses', FOpt.SetOptionText(AText));
  Result := TyRadarSpecOf(FOpt, 0);
end;

function TAdvChartRadarRuleTest.RadarOf(const AText: string): TTyRadar;
begin
  FreeAndNil(FRadar);
  FRadar := TTyRadar.Create(SpecOf(AText));
  { 400 x 200. A square viewport makes the centre's two bases and the radius'
    one the same number, and a fixture that cannot tell them apart lets a
    mutant that swaps them live. }
  FRadar.Resize(TyRectF(0, 0, 400, 200), 96);
  Result := FRadar;
end;

function TAdvChartRadarRuleTest.IndicatorOf(const AName: string; AHasMin: Boolean;
  AMin: Double; AHasMax: Boolean; AMax: Double): TTyRadarIndicator;
begin
  Result := Default(TTyRadarIndicator);
  Result.Name := AName;
  Result.HasMin := AHasMin;
  Result.Min_ := AMin;
  Result.HasMax := AHasMax;
  Result.Max_ := AMax;
end;

procedure TAdvChartRadarRuleTest.
  TestTheFirstSpokePointsUpAndTheNextRunsAnticlockwise;
var
  r: TTyRadar;
  p0, p1: TTyPointF;
begin
  { NINETY DEGREES IS UP, and it gets there WITHOUT the negation a pie needs:
    a radar keeps the maths convention and subtracts the sine when it builds a
    point. Applying the pie's rule here draws every radar mirrored while the
    first spoke still lands in the right place, so only the SECOND spoke can
    tell the two apart. }
  r := RadarOf('{"radar":{"indicator":[{"name":"a"},{"name":"b"},'
    + '{"name":"c"},{"name":"d"}]}}');
  AssertTrue('the radar is laid out', r.Valid);
  p0 := r.CoordToPoint(r.R1, 0);
  AssertEquals('the first spoke is on the centre line', r.CX, p0.X, 0.001);
  AssertTrue(Format('and ABOVE the centre (%g vs %g)', [p0.Y, r.CY]),
             p0.Y < r.CY - 1);
  { ANTICLOCKWISE by default, so the second spoke of four is at nine o'clock
    and not at three. }
  p1 := r.CoordToPoint(r.R1, 1);
  AssertTrue(Format('the second spoke is LEFT of the centre (%g)', [p1.X]),
             p1.X < r.CX - 1);
  AssertEquals('and level with it', r.CY, p1.Y, 0.001);
end;

procedure TAdvChartRadarRuleTest.
  TestClockwiseReversesTheOrderWithoutMovingTheFirst;
var
  r: TTyRadar;
  p0, p1: TTyPointF;
begin
  r := RadarOf('{"radar":{"clockwise":true,"indicator":[{"name":"a"},'
    + '{"name":"b"},{"name":"c"},{"name":"d"}]}}');
  AssertTrue(r.Valid);
  p0 := r.CoordToPoint(r.R1, 0);
  AssertEquals('the first spoke has not moved', r.CX, p0.X, 0.001);
  AssertTrue('still above the centre', p0.Y < r.CY - 1);
  p1 := r.CoordToPoint(r.R1, 1);
  AssertTrue(Format('but the second is now RIGHT of it (%g)', [p1.X]),
             p1.X > r.CX + 1);
end;

procedure TAdvChartRadarRuleTest.TestASpokeAngleIsFoldedIntoOneTurn;
var a: Double;
begin
  { FOLDED WITH atan2 OF ITS OWN SINE AND COSINE, which lands in (-Pi, Pi].
    Not decoration: a bare three-quarter turn reads as the wrong quadrant to
    the alignment rule that decides which edge of an indicator's name is
    pinned to the rim. }
  a := TyRadarAngle(Pi / 2, 3, 4, False);
  AssertTrue(Format('inside one turn (%g)', [a]), (a > -Pi - 1e-9) and (a <= Pi + 1e-9));
  AssertEquals('three quarters anticlockwise from the top is the RIGHT',
               0.0, a, 1e-9);
  a := TyRadarAngle(Pi / 2, 1, 4, False);
  AssertEquals('one quarter is nine o''clock', Pi, Abs(a), 1e-9);
end;

procedure TAdvChartRadarRuleTest.TestNoIndicatorsIsNotADivisionByZero;
var r: TTyRadar;
begin
  { THE DEFAULT IS AN EMPTY INDICATOR LIST, so this is not an exotic case --
    it is what a radar looks like before anybody has typed anything. Upstream
    reaches the division only from inside a loop that never runs; the obvious
    transcription hoists the step above the loop and divides by zero. }
  AssertEquals('the step is the start when there is nothing to step',
               1.5, TyRadarAngle(1.5, 0, 0, False), 1e-9);
  r := RadarOf('{"radar":{"indicator":[]}}');
  AssertFalse('a radar with no spokes is not laid out', r.Valid);
  AssertEquals('and draws nothing', 0,
    TyBuildRadarGrid(r, TyRadarInk, TTyPainterTextMeasurer.Create(96), 96,
      FList));
end;

procedure TAdvChartRadarRuleTest.
  TestTheCentreAndTheRadiusAreMeasuredAgainstDifferentThings;
var r: TTyRadar;
begin
  { THREE PERCENTAGES, TWO BASES. The centre's run against the width and the
    height SEPARATELY; the radius' runs against half the shorter side. On a
    400 x 200 rect that is 200, 100 and 50. }
  r := RadarOf('{"radar":{"indicator":[{"name":"a"},{"name":"b"},'
    + '{"name":"c"}]}}');
  AssertEquals('half the width across', 200.0, r.CX, 1e-9);
  AssertEquals('half the height down', 100.0, r.CY, 1e-9);
  AssertEquals('half of half the shorter side', 50.0, r.R1, 1e-9);
  r := RadarOf('{"radar":{"center":["25%","75%"],"radius":"100%",'
    + '"indicator":[{"name":"a"},{"name":"b"},{"name":"c"}]}}');
  AssertEquals('a quarter across', 100.0, r.CX, 1e-9);
  AssertEquals('three quarters down', 150.0, r.CY, 1e-9);
  AssertEquals('all of half the shorter side', 100.0, r.R1, 1e-9);
end;

procedure TAdvChartRadarRuleTest.TestAScalarRadiusIsTheOuterOneAndLeavesNoHole;
var r: TTyRadar;
begin
  { `radius: '60%'` NORMALISES TO [0, '60%'] and not to ['60%', '60%'] -- so a
    radar written with one number has no hole and its innermost ring is the
    centre itself. A port that duplicated the scalar would draw a ring of
    nothing at the middle and lose every band. }
  r := RadarOf('{"radar":{"radius":"60%","indicator":[{"name":"a"},'
    + '{"name":"b"},{"name":"c"}]}}');
  AssertEquals('no hole', 0.0, r.R0, 1e-9);
  AssertEquals('and the number is the rim', 60.0, r.R1, 1e-9);
  r := RadarOf('{"radar":{"radius":["30%","60%"],"indicator":[{"name":"a"},'
    + '{"name":"b"},{"name":"c"}]}}');
  AssertEquals('a pair is read as a pair', 30.0, r.R0, 1e-9);
  AssertEquals(60.0, r.R1, 1e-9);
end;

procedure TAdvChartRadarRuleTest.
  TestAWrittenMaxPinsTheFloorToZeroAndTheMirrorImage;
var lo, hi: Double;
begin
  { A WRITTEN max ABOVE ZERO PINS min TO ZERO, which is why almost every radar
    anybody writes starts at the middle -- and it happens BEFORE any data is
    looked at, so the data cannot move it. }
  TyRadarIndicatorExtent(IndicatorOf('a', False, 0, True, 100), 40, 90, False, lo, hi);
  AssertEquals('the floor is pinned', 0.0, lo, 1e-9);
  AssertEquals('and the written ceiling kept', 100.0, hi, 1e-9);
  { THE MIRROR IMAGE: a written min BELOW zero pins max to it. }
  TyRadarIndicatorExtent(IndicatorOf('a', True, -100, False, 0), -90, -40, False,
                         lo, hi);
  AssertEquals(-100.0, lo, 1e-9);
  AssertEquals('the ceiling is pinned', 0.0, hi, 1e-9);
  { `max: 0` TRIGGERS NEITHER, because the first test wants a POSITIVE max and
    the second a NEGATIVE min -- so the written ceiling of zero sits BELOW the
    data's own floor, the pair comes out the wrong way round, and the reversal
    that follows makes the written zero the FLOOR. Upstream's answer, reached
    by upstream's route, and not an axis anybody meant to ask for. }
  TyRadarIndicatorExtent(IndicatorOf('a', False, 0, True, 0), 40, 90, False,
                         lo, hi);
  AssertEquals('the written zero became the floor', 0.0, lo, 1e-9);
  AssertEquals('and the data''s own floor became the ceiling', 40.0, hi, 1e-9);
  { AND AN EXPLICIT min: 0 COUNTS AS UNSET, because the test is falsy rather
    than a null check. Harmless here -- it reassigns the zero it already had --
    but a port testing "was min written" diverges the moment the rule grows. }
  TyRadarIndicatorExtent(IndicatorOf('a', True, 0, True, 100), 40, 90, False, lo, hi);
  AssertEquals(0.0, lo, 1e-9);
  AssertEquals(100.0, hi, 1e-9);
end;

procedure TAdvChartRadarRuleTest.
  TestIncludeZeroOnlyMovesTheEndTheAuthorLeftAlone;
var lo, hi: Double;
begin
  { `scale: false` IS THE DEFAULT AND MEANS INCLUDE ZERO. With nothing written
    at either end an all-positive range has its floor dropped. }
  TyRadarIndicatorExtent(IndicatorOf('a', False, 0, False, 0), 40, 90, False, lo, hi);
  AssertEquals('the floor drops to zero', 0.0, lo, 1e-9);
  AssertEquals('the ceiling is the data''s', 90.0, hi, 1e-9);
  { AN ALL-NEGATIVE RANGE goes the other way. }
  TyRadarIndicatorExtent(IndicatorOf('a', False, 0, False, 0), -90, -40, False, lo, hi);
  AssertEquals(-90.0, lo, 1e-9);
  AssertEquals('the ceiling rises to zero', 0.0, hi, 1e-9);
  { AND A RANGE THAT ALREADY STRADDLES ZERO is left alone. }
  TyRadarIndicatorExtent(IndicatorOf('a', False, 0, False, 0), -20, 50, False, lo, hi);
  AssertEquals(-20.0, lo, 1e-9);
  AssertEquals(50.0, hi, 1e-9);
end;

procedure TAdvChartRadarRuleTest.TestScaleTrueKeepsTheDataRange;
var lo, hi: Double;
begin
  { `scale: true` SWITCHES THE INCLUDE-ZERO PASS OFF, which is the only thing
    it does. The data's own range survives. }
  TyRadarIndicatorExtent(IndicatorOf('a', False, 0, False, 0), 40, 90, True, lo, hi);
  AssertEquals(40.0, lo, 1e-9);
  AssertEquals(90.0, hi, 1e-9);
end;

procedure TAdvChartRadarRuleTest.
  TestARangeOfNoWidthIsOpenedRatherThanLeftFlat;
var lo, hi: Double;
begin
  { EVERY VALUE THE SAME is ordinary on a radar -- four indicators all reading
    fifty is a circle, not an error -- and a flat range would divide by zero on
    the very next step. With include-zero on, the zero end supplies the width. }
  TyRadarIndicatorExtent(IndicatorOf('a', False, 0, False, 0), 50, 50, False, lo, hi);
  AssertEquals(0.0, lo, 1e-9);
  AssertEquals(50.0, hi, 1e-9);
  { With it OFF the range is opened about the value itself, half its own
    magnitude either way. }
  TyRadarIndicatorExtent(IndicatorOf('a', False, 0, False, 0), 50, 50, True, lo, hi);
  AssertEquals(25.0, lo, 1e-9);
  AssertEquals(75.0, hi, 1e-9);
  { AND A FLAT ZERO has no magnitude to borrow, so it becomes nought to one. }
  TyRadarIndicatorExtent(IndicatorOf('a', False, 0, False, 0), 0, 0, True, lo, hi);
  AssertEquals(0.0, lo, 1e-9);
  AssertEquals(1.0, hi, 1e-9);
end;

procedure TAdvChartRadarRuleTest.TestNoDataAtAllIsAnAxisOfNothing;
var lo, hi: Double;
begin
  { NaN IS HOW "NOTHING WAS UNIONED" ARRIVES, and every comparison below would
    raise on one rather than answering False. }
  TyRadarIndicatorExtent(IndicatorOf('a', False, 0, False, 0), NaN, NaN, False, lo, hi);
  AssertEquals(0.0, lo, 1e-9);
  AssertEquals(1.0, hi, 1e-9);
end;

procedure TAdvChartRadarRuleTest.TestTheRingsAreEvenlySpacedAndNotNiceTicks;
var
  r: TTyRadar;
  k: Integer;
begin
  { UPSTREAM FORCES EVERY SPOKE ONTO ONE DUMMY SCALE of exactly splitNumber
    intervals, so a ring is a FRACTION OF THE RADIUS and never a nice tick.
    Drawing a ring per nice tick would give one indicator six rings and its
    neighbour five, and the polygon rings would not close.

    The range below is deliberately un-nice: nought to seven over five. }
  r := RadarOf('{"radar":{"splitNumber":5,"indicator":[{"name":"a","max":7},'
    + '{"name":"b","max":7},{"name":"c","max":7}]}}');
  AssertTrue(r.Valid);
  r.SetAxisExtent(0, 0, 7);
  for k := 0 to 5 do
    AssertEquals(Format('ring %d', [k]), r.R0 + (r.R1 - r.R0) * k / 5,
                 r.RingRadius(k), 1e-9);
  AssertEquals('and its value is the same fraction of the range', 2.8,
               r.RingValue(0, 2), 1e-9);
  AssertEquals('the outermost is the max itself', 7.0, r.RingValue(0, 5),
               1e-9);
end;

procedure TAdvChartRadarRuleTest.
  TestAnEmptyColourListIsAnAnswerRatherThanARemainderByZero;
var
  cols: TTyChartColorArray;
  c: TTyChartColor;
begin
  { `color: []` IS LEGAL JSON. Upstream takes a remainder by the length, gets
    NaN, writes into a property nothing iterates and draws nothing without a
    word; here the remainder would raise. }
  cols := nil;
  AssertFalse('no bucket at all', TyRadarBucket(cols, 0, c));
  SetLength(cols, 2);
  cols[0] := $FFAA0000;
  cols[1] := $FF00AA00;
  AssertTrue(TyRadarBucket(cols, 0, c));
  AssertEquals(Int64($FFAA0000), Int64(c));
  AssertTrue(TyRadarBucket(cols, 1, c));
  AssertEquals(Int64($FF00AA00), Int64(c));
  AssertTrue('and it wraps', TyRadarBucket(cols, 2, c));
  AssertEquals(Int64($FFAA0000), Int64(c));
  SetLength(cols, 1);
  AssertTrue('one colour is no alternation', TyRadarBucket(cols, 7, c));
  AssertEquals(Int64($FFAA0000), Int64(c));
end;

procedure TAdvChartRadarRuleTest.TestTheCentreBelongsToNoSpoke;
var
  r: TTyRadar;
  d: TTyDoubleArray;
begin
  { UPSTREAM DIVIDES BY THE RADIUS WITHOUT LOOKING. At the exact centre that is
    a zero, so every comparison that follows is against NaN, the loop falls out
    with an index of minus one, and minus one is handed back to a caller that
    will index an array with it. }
  r := RadarOf('{"radar":{"indicator":[{"name":"a"},{"name":"b"},'
    + '{"name":"c"}]}}');
  AssertFalse('the middle is not on a spoke',
              r.PointToData(TyPointF(r.CX, r.CY), d));
  AssertEquals('and no answer was invented', 0, Length(d));
end;

procedure TAdvChartRadarRuleTest.TestAPointOnTheRimResolvesToItsOwnSpoke;
var
  r: TTyRadar;
  d: TTyDoubleArray;
  p: TTyPointF;
begin
  r := RadarOf('{"radar":{"indicator":[{"name":"a","max":100},'
    + '{"name":"b","max":100},{"name":"c","max":100},'
    + '{"name":"d","max":100}]}}');
  r.SetAxisExtent(1, 0, 100);
  p := r.CoordToPoint(r.R1, 1);
  AssertTrue('the rim answers', r.PointToData(p, d));
  AssertEquals('spoke one', 1.0, d[0], 1e-9);
  AssertEquals('at its top value', 100.0, d[1], 1e-6);
end;

procedure TAdvChartRadarRuleTest.TestTheNameFormatterReplacesOnlyTheFirstToken;
var
  nm: TTyRadarNameSpec;
  ind: TTyRadarIndicator;
begin
  nm := TyRadarSpecDefault.AxisName;
  ind := IndicatorOf('Sales', False, 0, False, 0);
  AssertEquals('no formatter is the name itself', 'Sales',
               TyRadarNameText(ind, nm));
  nm.HasFormatter := True;
  nm.Formatter := '[' + '{value}' + ']';
  AssertEquals('[Sales]', TyRadarNameText(ind, nm));
  { FIRST ONLY, because JavaScript's replace takes a plain string here. }
  nm.Formatter := '{value} and {value}';
  AssertEquals('Sales and {value}', TyRadarNameText(ind, nm));
end;

procedure TAdvChartRadarRuleTest.TestShapeIsComparedWhole;
var spec: TTyRadarSpec;
begin
  spec := SpecOf('{"radar":{"shape":"circle","indicator":[{"name":"a"}]}}');
  AssertEquals(Ord(rsCircle), Ord(spec.Shape));
  { A TYPO IS A POLYGON, silently, because upstream compares against the one
    word and nothing validates. Kept, since tightening it would draw a
    different chart from the same option text. }
  spec := SpecOf('{"radar":{"shape":"Circle","indicator":[{"name":"a"}]}}');
  AssertEquals(Ord(rsPolygon), Ord(spec.Shape));
  spec := SpecOf('{"radar":{"indicator":[{"name":"a"}]}}');
  AssertEquals('and the default is a polygon', Ord(rsPolygon), Ord(spec.Shape));
end;

procedure TAdvChartRadarRuleTest.TestASplitNumberOfZeroIsTheDefaultAndNotZero;
var spec: TTyRadarSpec;
begin
  { UPSTREAM'S OWN SANITISER is a falsy test followed by a floor: nought, NaN
    and every empty thing become five, and a negative becomes one. }
  spec := SpecOf('{"radar":{"splitNumber":0,"indicator":[{"name":"a"}]}}');
  AssertEquals(5, spec.SplitNumber);
  spec := SpecOf('{"radar":{"splitNumber":-3,"indicator":[{"name":"a"}]}}');
  AssertEquals(1, spec.SplitNumber);
  spec := SpecOf('{"radar":{"splitNumber":8,"indicator":[{"name":"a"}]}}');
  AssertEquals(8, spec.SplitNumber);
end;

procedure TAdvChartRadarRuleTest.TestThePinIsNotTheIncludeZeroPassWearingAHat;
var lo, hi: Double;
begin
  { TWO GUARDS, AND THE SECOND SHADOWS THE FIRST. With `scale` off -- the
    default -- the include-zero pass drops an all-positive floor to nought all
    by itself, so removing the written-max pin entirely changes no answer any
    default fixture can produce. The two only part company with `scale: true`,
    where include-zero does not run and the pin still does: the pin is NOT
    gated on scale. }
  TyRadarIndicatorExtent(IndicatorOf('a', False, 0, True, 100), 40, 90, True,
                         lo, hi);
  AssertEquals('scale on, and the written max still pins the floor', 0.0, lo,
               1e-9);
  AssertEquals(100.0, hi, 1e-9);
  { THE MIRROR IMAGE, and it needs the same fixture for the same reason. }
  TyRadarIndicatorExtent(IndicatorOf('a', True, -100, False, 0), -90, -40, True,
                         lo, hi);
  AssertEquals(-100.0, lo, 1e-9);
  AssertEquals('and a written min below zero pins the ceiling', 0.0, hi, 1e-9);
end;

procedure TAdvChartRadarRuleTest.TestIncludeZeroLeavesAWrittenEndAlone;
var lo, hi: Double;
begin
  { IT ONLY MOVES THE END THE AUTHOR LEFT ALONE. Every fixture above writes
    neither end or writes the far one, and both let a version that ignored the
    written end through -- this one writes the NEAR end, which is the only
    place the guard shows. }
  TyRadarIndicatorExtent(IndicatorOf('a', True, 20, True, 100), 40, 90, False,
                         lo, hi);
  AssertEquals('a written floor of twenty is not dropped to nought', 20.0, lo,
               1e-9);
  AssertEquals(100.0, hi, 1e-9);
  TyRadarIndicatorExtent(IndicatorOf('a', True, -100, True, -20), -90, -40,
                         False, lo, hi);
  AssertEquals(-100.0, lo, 1e-9);
  AssertEquals('and a written ceiling is not raised to it', -20.0, hi, 1e-9);
end;

{ Every element the grid emitted, by kind. }
function CountKind(AList: TTyPaintList; AKind: TTyChartShapeKind;
  AFilled: Boolean): Integer;
var i: Integer; e: TTyChartElement;
begin
  Result := 0;
  for i := 0 to AList.Count - 1 do
  begin
    e := AList.Element(i);
    if e.Shape.Kind <> AKind then Continue;
    if e.Caption.Text <> '' then Continue;
    if e.Style.HasFill <> AFilled then Continue;
    Inc(Result);
  end;
end;

procedure TAdvChartRadarRuleTest.TestTheBandsSitBetweenConsecutiveRings;
var
  r: TTyRadar;
  i, bands: Integer;
  e: TTyChartElement;
  rIn, rOut, expIn, expOut: Double;
begin
  { A BAND IS BETWEEN RING k AND RING k+1, and a picture cannot tell that from
    a band between ring k and itself -- the second draws nothing at all, which
    looks exactly like a radar whose split areas are simply pale.

    Asked of the GEOMETRY: the outermost band's inner edge must be the
    second-outermost ring. }
  r := RadarOf('{"radar":{"splitNumber":4,"axisName":{"show":false},'
    + '"indicator":[{"name":"a"},{"name":"b"},{"name":"c"},{"name":"d"}]}}');
  AssertTrue(r.Valid);
  FList.Clear;
  TyBuildRadarGrid(r, TyRadarInk, TTyPainterTextMeasurer.Create(96), 96, FList);
  bands := 0;
  for i := 0 to FList.Count - 1 do
  begin
    e := FList.Element(i);
    if not e.Style.HasFill then Continue;
    Inc(bands);
  end;
  AssertEquals('one band per interval', 4, bands);
  { The bands come first and innermost first, so the last one is the outer. }
  e := FList.Element(3);
  AssertEquals('the outermost band is a polygon', Ord(cskPolygon),
               Ord(e.Shape.Kind));
  expOut := r.RingRadius(4);
  expIn := r.RingRadius(3);
  rOut := Abs(e.Shape.Points[0].Y - r.CY);
  rIn := Abs(e.Shape.Points[Length(e.Shape.Points) - 1].Y - r.CY);
  AssertEquals('its outer edge is the rim', expOut, rOut, 0.001);
  AssertEquals('and its inner edge the ring below it', expIn, rIn, 0.001);
  AssertTrue('which are not the same ring', Abs(expOut - expIn) > 1);
end;

procedure TAdvChartRadarRuleTest.TestABandIsOneContourWithItsInnerRingReversed;
var
  r: TTyRadar;
  e: TTyChartElement;
  n, half, i: Integer;
begin
  { ONE CONTOUR, out along the outer ring and back along the inner one
    REVERSED -- which is what leaves the hole unfilled. Traced forward the
    contour crosses itself and the band fills solid, and on a pale tint over
    white that is very nearly invisible. }
  r := RadarOf('{"radar":{"splitNumber":2,"axisName":{"show":false},'
    + '"indicator":[{"name":"a"},{"name":"b"},{"name":"c"},{"name":"d"}]}}');
  FList.Clear;
  TyBuildRadarGrid(r, TyRadarInk, TTyPainterTextMeasurer.Create(96), 96, FList);
  e := FList.Element(1);
  AssertTrue('a filled band', e.Style.HasFill);
  n := Length(e.Shape.Points);
  AssertEquals('two closed rings of four spokes', 10, n);
  half := n div 2;
  { THE RETURN LEG'S SECOND POINT IS THE INNER RING'S LAST-BUT-ONE, which on
    four spokes is spoke THREE. Its first point says nothing -- every ring is
    closed, so the reversal's two ends are the same point either way -- and
    comparing the return leg against itself says nothing either, because it
    differs from its own mirror in both directions. Only naming the spoke it
    must land on can tell forward from backward. }
  AssertEquals('the return leg starts back at spoke three',
    r.CoordToPoint(r.RingRadius(1), 3).X, e.Shape.Points[half + 1].X, 0.001);
  AssertEquals(r.CoordToPoint(r.RingRadius(1), 3).Y,
               e.Shape.Points[half + 1].Y, 0.001);
  for i := 0 to half - 1 do
    AssertTrue('the outward leg is on the outer ring',
      Abs(Sqrt(Sqr(e.Shape.Points[i].X - r.CX)
               + Sqr(e.Shape.Points[i].Y - r.CY)) - r.RingRadius(2)) < 0.01);
end;

procedure TAdvChartRadarRuleTest.
  TestTheGridDrawsItsPartsAndNoneOfThemIsHittable;
var
  r: TTyRadar;
  i, rings, spokes, names: Integer;
  e: TTyChartElement;
begin
  { EVERY PART, COUNTED. A picture says "there is grey ink there" and lets a
    missing family through whenever another family draws over the same place --
    the spokes and the rings cross at every vertex.

    AND ALL OF IT SILENT. A hover on the grid would report a datum the grid
    does not stand for. }
  r := RadarOf('{"radar":{"splitNumber":3,"indicator":[{"name":"a"},'
    + '{"name":"b"},{"name":"c"},{"name":"d"},{"name":"e"}]}}');
  FList.Clear;
  TyBuildRadarGrid(r, TyRadarInk, TTyPainterTextMeasurer.Create(96), 96, FList);
  rings := 0;
  spokes := 0;
  names := 0;
  for i := 0 to FList.Count - 1 do
  begin
    e := FList.Element(i);
    AssertTrue('every part of the grid is silent', e.Silent);
    if e.Caption.Text <> '' then
    begin
      Inc(names);
      Continue;
    end;
    if e.Shape.Kind <> cskPolyline then Continue;
    if Length(e.Shape.Points) = 2 then Inc(spokes) else Inc(rings);
  end;
  { THREE AND NOT FOUR: ring nought has the radius of the hole, and a default
    radar has no hole -- a ring of no radius is a dot, not a ring, and is
    skipped rather than handed to a rasteriser as a zero-radius circle. }
  AssertEquals('one ring per split, the innermost being the centre itself',
               3, rings);
  AssertEquals('one spoke per indicator', 5, spokes);
  AssertEquals('and one name each', 5, names);
  AssertEquals('one band per interval', 3, CountKind(FList, cskPolygon, True));
end;

procedure TAdvChartRadarRuleTest.TestANameIsPinnedByTheEdgeFacingTheCentre;
var
  r: TTyRadar;
  i: Integer;
  e: TTyChartElement;
  up, left: Boolean;
begin
  { THE WORDS GROW TOWARD THE DIAL. A name out to the LEFT of the centre is
    pinned by its RIGHT edge, so it ends where the spoke does instead of
    starting there and running off the canvas. Pinned the other way the words
    are still drawn, still legible and in the wrong place -- which a pixel
    count of "is there ink up there" cannot tell apart. }
  r := RadarOf('{"radar":{"indicator":[{"name":"UP"},{"name":"LEFT"},'
    + '{"name":"DOWN"},{"name":"RIGHT"}]}}');
  FList.Clear;
  TyBuildRadarGrid(r, TyRadarInk, TTyPainterTextMeasurer.Create(96), 96, FList);
  up := False;
  left := False;
  for i := 0 to FList.Count - 1 do
  begin
    e := FList.Element(i);
    if e.Caption.Text = 'LEFT' then
    begin
      left := True;
      AssertEquals('a name on the left is pinned by its right edge',
                   Ord(tahRight), Ord(e.Caption.AnchorH));
      AssertEquals('and centred vertically', Ord(tavMiddle),
                   Ord(e.Caption.AnchorV));
    end;
    if e.Caption.Text = 'UP' then
    begin
      up := True;
      AssertEquals('a name straight up is centred across', Ord(tahCentre),
                   Ord(e.Caption.AnchorH));
      AssertEquals('and hung above the rim', Ord(tavBottom),
                   Ord(e.Caption.AnchorV));
    end;
    if e.Caption.Text = 'RIGHT' then
      AssertEquals('and one on the right is pinned by its left edge',
                   Ord(tahLeft), Ord(e.Caption.AnchorH));
  end;
  AssertTrue('the top name was found', up);
  AssertTrue('the left name was found', left);
end;

procedure TAdvChartRadarRuleTest.TestACircleRadarUsesRoundBandsAndRoundRings;
var
  r: TTyRadar;
  i, sectors, circles: Integer;
  e: TTyChartElement;
begin
  { BOTH FAMILIES CHANGE, and a test that only looked at the rings let the
    BANDS go on being polygons -- which on a five-spoke radar is a pentagon
    behind a circle and reads as a rendering fault rather than as an option. }
  r := RadarOf('{"radar":{"shape":"circle","splitNumber":3,'
    + '"axisName":{"show":false},"indicator":[{"name":"a"},{"name":"b"},'
    + '{"name":"c"},{"name":"d"},{"name":"e"}]}}');
  FList.Clear;
  TyBuildRadarGrid(r, TyRadarInk, TTyPainterTextMeasurer.Create(96), 96, FList);
  sectors := 0;
  circles := 0;
  for i := 0 to FList.Count - 1 do
  begin
    e := FList.Element(i);
    if e.Shape.Kind = cskSector then Inc(sectors);
    if e.Shape.Kind = cskCircle then Inc(circles);
  end;
  AssertEquals('every band is a ring', 3, sectors);
  AssertEquals('and every split line a circle', 3, circles);
  AssertEquals('with no polygon anywhere', 0, CountKind(FList, cskPolygon, True));
end;

{ A store of one row per array, one column per spoke. }
function RowStore(var AStore: TTyDataStore; ACols: Integer;
  const ARows: array of Double): TTyDataStore;
var
  i, j, n: Integer;
  row: array of TTyDataValue;
begin
  FreeAndNil(AStore);
  AStore := TTyDataStore.Create;
  for j := 0 to ACols - 1 do
    AStore.AddDimension(TyRadarDimPrefix + IntToStr(j), ddtFloat);
  SetLength(row, ACols);
  n := (Length(ARows) + ACols - 1) div ACols;
  for i := 0 to n - 1 do
  begin
    for j := 0 to ACols - 1 do
      if i * ACols + j <= High(ARows) then row[j] := TyDataNum(ARows[i * ACols + j])
      else row[j] := TyDataNum(NaN);
    AStore.AppendRow(row);
  end;
  Result := AStore;
end;

function RadarBinding: TTySeriesBinding;
begin
  Result := Default(TTySeriesBinding);
  Result.SeriesIndex := 0;
  Result.SeriesType := TyRadarSeriesTypeName;
  Result.Resolved := True;
  Result.HasAxes := False;
  Result.RadarIndex := 0;
end;

function AllDims(ACount: Integer): TTyIntegerArray;
var i: Integer;
begin
  SetLength(Result, ACount);
  for i := 0 to ACount - 1 do Result[i] := i;
end;

procedure TAdvChartRadarRuleTest.
  TestAMissingValueLeavesTheRingRatherThanCollapsingIt;
var
  r: TTyRadar;
  st: TTyDataStore;
  i, j: Integer;
  e: TTyChartElement;
  found: Boolean;
begin
  { A SPOKE WITH NOTHING ON IT IS SKIPPED and its neighbours join -- which is
    what a canvas does with a vertex it cannot place, and what upstream
    therefore draws. Collapsing it to the centre instead draws a ring with a
    spike into the middle, and any test that only counted ink would pass. }
  r := RadarOf('{"radar":{"indicator":[{"name":"a","max":100},'
    + '{"name":"b","max":100},{"name":"c","max":100},'
    + '{"name":"d","max":100}]}}');
  for i := 0 to 3 do r.SetAxisExtent(i, 0, 100);
  st := nil;
  try
    RowStore(st, 4, [80, 80, NaN, 80]);
    FList.Clear;
    TyBuildRadarMarks(RadarBinding, r, TyRadarVisual($FF3366CC), st,
      AllDims(4), 96, FList);
    found := False;
    for i := 0 to FList.Count - 1 do
    begin
      e := FList.Element(i);
      if e.Shape.Kind <> cskPolyline then Continue;
      found := True;
      AssertEquals('three spokes and the closing point', 4,
                   Length(e.Shape.Points));
      for j := 0 to High(e.Shape.Points) do
        AssertTrue('and none of them is the centre',
          Abs(e.Shape.Points[j].X - r.CX) + Abs(e.Shape.Points[j].Y - r.CY)
            > 1);
      Break;
    end;
    AssertTrue('a ring was drawn', found);
  finally
    st.Free;
  end;
end;

procedure TAdvChartRadarRuleTest.TestARingOfOnePointIsNotDrawn;
var
  r: TTyRadar;
  st: TTyDataStore;
begin
  { ONE SURVIVING SPOKE IS NOT A RING. A two-point polyline from a point to
    itself is a dot with a hit corridor round it, and a row that said nothing
    would answer a hover. }
  r := RadarOf('{"radar":{"indicator":[{"name":"a","max":100},'
    + '{"name":"b","max":100},{"name":"c","max":100}]}}');
  st := nil;
  try
    RowStore(st, 3, [80, NaN, NaN]);
    FList.Clear;
    AssertEquals('nothing at all', 0,
      TyBuildRadarMarks(RadarBinding, r, TyRadarVisual($FF3366CC), st,
        AllDims(3), 96, FList));
  finally
    st.Free;
  end;
end;

procedure TAdvChartRadarRuleTest.TestTheRingClosesBackToItsFirstPoint;
var
  r: TTyRadar;
  st: TTyDataStore;
  i: Integer;
  e: TTyChartElement;
begin
  { A POLYLINE DOES NOT CLOSE ITSELF, so the first point has to be pushed
    again -- and the missing edge is the one between the LAST spoke and the
    first, which on a radar of many spokes is a short chord nobody notices. }
  r := RadarOf('{"radar":{"indicator":[{"name":"a","max":100},'
    + '{"name":"b","max":100},{"name":"c","max":100},'
    + '{"name":"d","max":100}]}}');
  for i := 0 to 3 do r.SetAxisExtent(i, 0, 100);
  st := nil;
  try
    RowStore(st, 4, [10, 50, 90, 30]);
    FList.Clear;
    TyBuildRadarMarks(RadarBinding, r, TyRadarVisual($FF3366CC), st,
      AllDims(4), 96, FList);
    for i := 0 to FList.Count - 1 do
    begin
      e := FList.Element(i);
      if e.Shape.Kind <> cskPolyline then Continue;
      AssertEquals('four spokes and the closing point', 5,
                   Length(e.Shape.Points));
      AssertEquals('which is the first one again', e.Shape.Points[0].X,
                   e.Shape.Points[4].X, 1e-9);
      AssertEquals(e.Shape.Points[0].Y, e.Shape.Points[4].Y, 1e-9);
      Break;
    end;
  finally
    st.Free;
  end;
end;

procedure TAdvChartRadarRuleTest.TestEachRowTakesItsOwnColourAndTheRingIsHittable;
var
  r: TTyRadar;
  st: TTyDataStore;
  vis: TTyRadarVisual;
  i, n: Integer;
  e: TTyChartElement;
  first, second: TTyChartColor;
begin
  { A RADAR COLOURS BY DATUM. Two rings on one radar are two ROWS of one
    series, and a picture of a theme whose ramp is a family of blues cannot
    tell one colour used twice from two that are close.

    AND THE RING IS THE HIT TARGET -- the only one besides its symbols. }
  r := RadarOf('{"radar":{"indicator":[{"name":"a","max":100},'
    + '{"name":"b","max":100},{"name":"c","max":100}]}}');
  for i := 0 to 2 do r.SetAxisExtent(i, 0, 100);
  st := nil;
  try
    RowStore(st, 3, [10, 20, 30, 70, 80, 90]);
    vis := TyRadarVisual($FF111111);
    SetLength(vis.Fills, 2);
    vis.Fills[0] := $FFAA0000;
    vis.Fills[1] := $FF00AA00;
    FList.Clear;
    TyBuildRadarMarks(RadarBinding, r, vis, st, AllDims(3), 96, FList);
    first := 0;
    second := 0;
    n := 0;
    for i := 0 to FList.Count - 1 do
    begin
      e := FList.Element(i);
      if e.Shape.Kind <> cskPolyline then Continue;
      Inc(n);
      AssertFalse('a ring is not silent', e.Silent);
      AssertEquals('and it carries its own row', n - 1, e.Datum.DataIndex);
      if n = 1 then first := e.Style.StrokeColor
      else second := e.Style.StrokeColor;
    end;
    AssertEquals('two rings', 2, n);
    AssertEquals('the first row''s own colour', Int64($FFAA0000), Int64(first));
    AssertEquals('and the second''s', Int64($FF00AA00), Int64(second));
  finally
    st.Free;
  end;
end;

procedure TAdvChartRadarRuleTest.TestOnlyTheseTypesLetTheirRowsIntoTheLegend;
begin
  { THE LIST THE LEGEND ASKS, and it is worth a test of its own because every
    consequence of it is one step removed: which names the legend offers,
    which colour a swatch takes, and whether a click hides a series or one row
    of one. A picture of a legend shows none of that directly. }
  AssertTrue('a pie names its slices', TySeriesLegendByDatum('pie'));
  AssertTrue('a funnel its bands', TySeriesLegendByDatum('funnel'));
  AssertTrue('a radar its rings', TySeriesLegendByDatum('radar'));
  AssertFalse('a bar is one entry', TySeriesLegendByDatum('bar'));
  AssertFalse('and so is a line', TySeriesLegendByDatum('line'));
  AssertFalse('and a gauge, whose rows are readings', TySeriesLegendByDatum('gauge'));
end;

{ ==================== the drawing ==================== }

procedure TAdvChartRadarDrawTest.SetUp;
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

procedure TAdvChartRadarDrawTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartRadarDrawTest.Draw(const AOption: string);
begin
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(cW, cH, BGRAWhite);
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartRadarDrawTest.InkPixels: Integer;
var
  x, y: Integer;
  row: PBGRAPixel;
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

function TAdvChartRadarDrawTest.Diagnostics: string;
var i: Integer;
begin
  Result := '';
  for i := 0 to FChart.DiagnosticCount - 1 do
    Result := Result + FChart.Diagnostic(i) + '|';
end;

procedure TAdvChartRadarDrawTest.TestARadarDrawsAtAll;
var ink: Integer;
begin
  { IT COULD NOT UNTIL THIS BATCH, and not for the funnel's reason: the binder
    refused every coordinate system but the cartesian outright, so a radar
    series resolved to nothing and said so. }
  Draw(cRadar);
  ink := InkPixels;
  AssertTrue(Format('the radar is on the canvas (%d px)', [ink]), ink > 3000);
end;

procedure TAdvChartRadarDrawTest.TestItSaysNothingAboutHavingNoRenderer;
begin
  Draw(cRadar);
  AssertEquals('a radar draws now', '', Diagnostics);
end;

procedure TAdvChartRadarDrawTest.TestTheFirstIndicatorsNameIsAboveTheCentre;
var
  above, below: Integer;

  { Dark pixels in a column through the middle, OUTSIDE the rings. The series'
    own ring is dark too and it goes all the way round, so a band that reached
    inside the rim would count the same ink on both sides. }
  function DarkIn(AY0, AY1: Integer): Integer;
  var x, y: Integer;
  begin
    Result := 0;
    for y := AY0 to AY1 do
      for x := cW div 2 - 60 to cW div 2 + 60 do
        if FBmp.GetPixel(x, y).red < 150 then Inc(Result);
  end;

begin
  { THE FIRST SPOKE POINTS UP, so its name is above the rings and nowhere
    else. A mirrored radar puts it below and every angle in the rule tests
    still agrees with it, because they were computed the same way the code
    computes them. }
  Draw('{"tooltip":{"show":false},"radar":{"indicator":['
    + '{"name":"MMMMMMMMMM"},{"name":"i"},{"name":"i"},{"name":"i"}]},'
    + '"series":[{"type":"radar","data":[{"value":[1,2,3,4]}]}]}');
  above := DarkIn(10, cH div 2 - 105);
  below := DarkIn(cH div 2 + 105, cH - 10);
  AssertTrue(Format('the long name is above the middle (%d)', [above]),
             above > 100);
  AssertTrue(Format('and the short one below it is far smaller (%d vs %d)',
                    [below, above]), below * 3 < above);
end;

procedure TAdvChartRadarDrawTest.TestTwoRowsAreTwoColoursOnOneRadar;
var
  one, two: Integer;

  { How many SATURATED colours the picture contains, counted as distinct
    (red, green, blue) triples. Everything the grid draws is grey, so the only
    saturated ink on a radar is its rings. }
  function DistinctSaturated: Integer;
  var
    x, y, lo, hi, i, n: Integer;
    row: PBGRAPixel;
    seen: array of LongWord;
    key: LongWord;
    found: Boolean;
  begin
    seen := nil;
    n := 0;
    for y := 0 to cH - 1 do
    begin
      row := FBmp.ScanLine[y];
      for x := 0 to cW - 1 do
      begin
        lo := Min(row^.red, Min(row^.green, row^.blue));
        hi := Max(row^.red, Max(row^.green, row^.blue));
        { Saturated AND fully opaque AND not an antialiased edge: a ring's own
          stroke is the only thing that passes all three. }
        if (row^.alpha = 255) and (hi - lo > 60) then
        begin
          key := (LongWord(row^.red) shl 16) or (LongWord(row^.green) shl 8)
                 or LongWord(row^.blue);
          found := False;
          for i := 0 to n - 1 do
            if seen[i] = key then
            begin
              found := True;
              Break;
            end;
          if not found then
          begin
            if n >= Length(seen) then SetLength(seen, n * 2 + 8);
            seen[n] := key;
            Inc(n);
          end;
        end;
        Inc(row);
      end;
    end;
    Result := n;
  end;

begin
  { A RADAR COLOURS BY DATUM, not by series: two rings on one radar are two
    ROWS of one series, keyed on the row's own name -- which is also what lets
    the legend name them.

    COUNTED AS DISTINCT COLOURS rather than compared against two constants,
    because which two the theme hands out is the theme's business. One row
    first, so the count has something to be more than. }
  Draw('{"tooltip":{"show":false},' + cInd + ','
    + '"series":[{"type":"radar","data":['
    + '{"value":[60,70,80,50],"name":"one"}]}]}');
  one := DistinctSaturated;
  Draw(cRadar);
  two := DistinctSaturated;
  AssertTrue(Format('one row is one colour (%d)', [one]), one >= 1);
  AssertTrue(Format('two rows are more (%d vs %d)', [two, one]),
             two > one);
end;

procedure TAdvChartRadarDrawTest.TestAnAreaStyleFillsTheRingAndNothingElseDoes;
var withIt, without: Integer;

  { Saturated pixels just inside the first ring, where a filled radar is solid
    and a wire one is white. }
  function Filled: Integer;
  var x, y, lo, hi: Integer; px: TBGRAPixel;
  begin
    Result := 0;
    for y := cH div 2 - 20 to cH div 2 + 20 do
      for x := cW div 2 - 20 to cW div 2 + 20 do
      begin
        px := FBmp.GetPixel(x, y);
        lo := Min(px.red, Min(px.green, px.blue));
        hi := Max(px.red, Max(px.green, px.blue));
        if hi - lo > 25 then Inc(Result);
      end;
  end;

begin
  { `areaStyle: {}` IS THE DOCUMENTED WAY TO FILL A RADAR, and an EMPTY object
    counts: upstream's test is whether the option exists at all, not whether it
    says anything. A port testing "has a colour" leaves every filled radar in
    the gallery a wire. }
  Draw('{"tooltip":{"show":false},' + cInd + ','
    + '"series":[{"type":"radar","areaStyle":{},'
    + '"data":[{"value":[90,90,90,90]}]}]}');
  withIt := Filled;
  Draw('{"tooltip":{"show":false},' + cInd + ','
    + '"series":[{"type":"radar",'
    + '"data":[{"value":[90,90,90,90]}]}]}');
  without := Filled;
  AssertTrue(Format('an empty areaStyle fills it (%d px)', [withIt]),
             withIt > 800);
  AssertTrue(Format('and without one the middle is empty (%d)', [without]),
             without < withIt div 4);
end;

procedure TAdvChartRadarDrawTest.TestACircleShapeIsRoundWhereAPolygonIsFlat;
var
  polyR, circR: Integer;

  { How far the outermost ring reaches along the diagonal. On a four-spoke
    polygon the diagonal cuts a flat edge and falls SHORT of the rim; on a
    circle it reaches the rim exactly. }
  function DiagonalReach: Integer;
  var
    d, x, y: Integer;
    px: TBGRAPixel;
  begin
    Result := 0;
    for d := 1 to 140 do
    begin
      x := cW div 2 + Round(d * 0.7071);
      y := cH div 2 - Round(d * 0.7071);
      if (x < 0) or (x >= cW) or (y < 0) or (y >= cH) then Break;
      px := FBmp.GetPixel(x, y);
      if (px.red < 245) or (px.green < 245) or (px.blue < 245) then Result := d;
    end;
  end;

const
  cShape = '{"tooltip":{"show":false},"radar":{"shape":"%s","radius":"60%%",'
    + '"splitLine":{"show":true},"axisName":{"show":false},'
    + '"indicator":[{"name":"a"},{"name":"b"},{"name":"c"},{"name":"d"}]},'
    + '"series":[{"type":"radar","data":[{"value":[1,1,1,1]}]}]}';
begin
  { THE ONE ASSERTION A POLYGON AND A CIRCLE CANNOT BOTH SATISFY. Four spokes
    at the compass points make the outer ring a diamond, so the diagonal
    crosses its edge at about seven tenths of the radius; a circle's diagonal
    reaches the rim. }
  Draw(Format(cShape, ['polygon']));
  polyR := DiagonalReach;
  Draw(Format(cShape, ['circle']));
  circR := DiagonalReach;
  AssertTrue(Format('the polygon''s diagonal falls short (%d)', [polyR]),
             polyR > 10);
  AssertTrue(Format('the circle reaches further (%d vs %d)', [circR, polyR]),
             circR > polyR + 15);
end;

procedure TAdvChartRadarDrawTest.TestARingReportsItsRow;
var
  hit: TTyChartDatumRef;
  elem: Integer;
begin
  { THE RING AND ITS SYMBOLS ARE THE ONLY THINGS ON A RADAR THAT ARE NOT
    SILENT. Every spoke, every band and every name is furniture: a hover on
    the grid would report a datum the grid does not stand for. }
  Draw('{"tooltip":{"show":false},' + cInd + ','
    + '"series":[{"type":"radar","symbol":"circle","symbolSize":10,'
    + '"data":[{"value":[100,100,100,100],"name":"one"}]}]}');
  { Straight up from the middle, at the rim, where the first spoke's symbol
    sits. The radius is half of half the shorter side, so 0.25 * 380 = 95. }
  hit := FChart.HitTestAt(cW div 2, cH div 2 - 95, elem);
  AssertEquals('the ring is the series'' own', 0, hit.SeriesIndex);
  AssertEquals('and its row', 0, hit.DataIndex);
  { THE GRID IS NOT. A point between two spokes, well inside the rings, is
    over a band and over nothing else. }
  hit := FChart.HitTestAt(cW div 2 + 30, cH div 2 + 30, elem);
  AssertEquals('the band answers no datum', -1, hit.SeriesIndex);
  AssertEquals('and no element at all', -1, elem);
end;

procedure TAdvChartRadarDrawTest.TestARadarIndexPastTheEndDrawsNothingAndSaysSo;
begin
  { A radarIndex NOBODY DECLARED is a series on a coordinate system that does
    not exist, and the answer is the same one every unresolvable series gets:
    nothing drawn and a line in the panel saying which. Binding it anyway
    would send it looking for spokes in an empty array. }
  Draw('{"tooltip":{"show":false},' + cInd + ','
    + '"series":[{"type":"radar","radarIndex":5,'
    + '"data":[{"value":[60,70,80,50]}]}]}');
  AssertTrue('the panel names the coordinate system, got: ' + Diagnostics,
             Pos('radar', Diagnostics) > 0);
end;

procedure TAdvChartRadarDrawTest.TestASwitchedOffRowDoesNotWidenItsSpoke;
var squashed, freed: Integer;

  { How far up from the centre the INNERMOST saturated ink is, along the first
    spoke. Scanned outward from the middle, so it finds the smallest ring. }
  function ReachUp: Integer;
  var y, x, lo, hi: Integer; px: TBGRAPixel;
  begin
    Result := 0;
    for y := cH div 2 downto 10 do
    begin
      x := cW div 2;
      px := FBmp.GetPixel(x, y);
      lo := Min(px.red, Min(px.green, px.blue));
      hi := Max(px.red, Max(px.green, px.blue));
      if (hi - lo > 40) then Exit(cH div 2 - y);
    end;
  end;

begin
  { A SWITCHED-OFF ROW MUST NOT SIZE THE SPOKE IT IS NOT DRAWN ON. Nothing
    else in this control is in a position to notice: the value-range pass
    walks the cartesian grids' axis lists and a spoke is in neither, so the
    radar collects its own extents -- and a collection that ignored the
    filter would leave every visible ring squashed against the middle by a
    row nobody can see.

    No indicator max here, deliberately: with one written the spoke's range is
    the author's and the data cannot move it either way. }
  Draw('{"tooltip":{"show":false},"legend":{},'
    + '"radar":{"axisName":{"show":false},"indicator":['
    + '{"name":"a"},{"name":"b"},{"name":"c"}]},'
    + '"series":[{"type":"radar","data":['
    + '{"value":[10,10,10],"name":"small"},'
    + '{"value":[1000,1000,1000],"name":"huge"}]}]}');
  squashed := ReachUp;
  Draw('{"tooltip":{"show":false},"legend":{"selected":{"huge":false}},'
    + '"radar":{"axisName":{"show":false},"indicator":['
    + '{"name":"a"},{"name":"b"},{"name":"c"}]},'
    + '"series":[{"type":"radar","data":['
    + '{"value":[10,10,10],"name":"small"},'
    + '{"value":[1000,1000,1000],"name":"huge"}]}]}');
  freed := ReachUp;
  AssertTrue(Format('the big row crushes the small one against the middle (%d)',
                    [squashed]), squashed < 20);
  AssertTrue(Format('switching it off lets the small one out (%d vs %d)',
                    [freed, squashed]), freed > squashed + 40);
end;

initialization
  RegisterTest(TAdvChartRadarRuleTest);
  RegisterTest(TAdvChartRadarDrawTest);
end.
