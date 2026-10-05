unit test.advchart.pie;
{$mode objfpc}{$H+}
{ The pie: the first series with no coordinate system under it.

  ASSERTED AGAINST src/chart/pie/pieLayout.ts AND src/util/layout.ts, not
  against the option documentation -- the two disagree about the default radius
  and the catalog transcribed the documentation.

  The five that a reasonable-looking port gets wrong, each with a test here on
  purpose:

    - `center` is a percentage of the view rect's WIDTH and HEIGHT separately
      while `radius` is a percentage of HALF THE SHORTER SIDE, so on an oblong
      chart the two cannot share an arithmetic;
    - the option's angles are NEGATED into canvas radians, so the default 90
      is twelve o'clock and larger numbers go anticlockwise;
    - the redistribution pass is not an edge case -- every pie that does not go
      the whole way round depends on it, a half doughnut included;
    - a negative value is REMOVED rather than clamped, and a NaN is not: it
      keeps its place in the ring;
    - roseType 'area' equalises the ANGLES; it is 'radius' that leaves them
      proportional. }
interface
uses
  Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Data, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Series,
  tyControls.AdvChart.Builder,
  tyControls.AdvChart.Pie;

type
  TAdvChartPieTest = class(TTestCase)
  private
    FOpt: TTyChartOption;
    FStore: TTyDataStore;
    FList: TTyPaintList;
    FSpec: TTyPieSpec;
    FLay: TTyPieLayout;
    procedure SetUp; override;
    procedure TearDown; override;
    { Parse the option, fill a one-column store from series 0, lay it out. }
    procedure Run(const AText: string; AW: Integer = 400; AH: Integer = 300);
    { The sweep of sector i, signed the way the layout ran. }
    function Sweep(AIndex: Integer): Double;
    function Deg(ARad: Double): Double;
  published
    procedure TestTheDefaultDiscIsCentredAndAQuarterOfTheShorterSide;
    procedure TestTheTwoPercentageBasesAreDifferent;
    procedure TestABareRadiusForcesTheInnerOneToZero;
    procedure TestTheSeriesBoxMovesBothTheCentreAndTheRadius;
    procedure TestTheDefaultStartIsTwelveOClockAndItRunsClockwise;
    procedure TestTheOptionAngleIsNegated;
    procedure TestAnticlockwiseRunsTheOtherWay;
    procedure TestValuesTakeTheirShareOfTheTurn;
    procedure TestAHalfDoughnutFillsExactlyItsHalf;
    procedure TestMinAngleTakesFromTheOthersRatherThanFromNothing;
    procedure TestPadAngleEatsBothEndsOfEverySector;
    procedure TestANegativeValueIsRemovedNotClamped;
    procedure TestANaNKeepsItsPlace;
    procedure TestAllZeroesStillShowOrDoNot;
    procedure TestRoseTypeAreaEqualisesTheAnglesAndRadiusDoesNot;
    procedure TestPercentagesAddUpToAHundred;
    procedure TestAPrecisionPastCountingStillAnswers;
    procedure TestTheMarksAreSectorsThatAnswerForTheirOwnRow;
    procedure TestEachSectorTakesTheNextColour;
    procedure TestAnEmptyPieDrawsItsRingAndSaysNothing;
    procedure TestNormaliseNeverStretchesPastOneTurn;
    procedure TestAWholeTurnComesOutExact;
    procedure TestTheScalarsAreActuallyReadOffTheOption;
    procedure TestBorderRadiusReachesTheSectorAndIsAShareOfTheOuterRadius;
  end;

implementation

const
  Eps = 1e-9;
  { Loose enough for a chain of trig, tight enough that a wrong quadrant or a
    wrong base is never inside it. }
  EpsPx = 1e-6;

procedure TAdvChartPieTest.SetUp;
begin
  inherited SetUp;
  FOpt := TTyChartOption.Create;
  FStore := nil;
  FList := nil;
end;

procedure TAdvChartPieTest.TearDown;
begin
  FreeAndNil(FList);
  FreeAndNil(FStore);
  FreeAndNil(FOpt);
  inherited TearDown;
end;

procedure TAdvChartPieTest.Run(const AText: string; AW, AH: Integer);
var
  dims: TTySeriesDimArray;
begin
  AssertTrue('the option parsed: ' + FOpt.Error.Message,
    FOpt.SetOptionText(AText));
  FreeAndNil(FStore);
  FStore := TTyDataStore.Create;
  FStore.AddDimension(TyPieValueDim, ddtFloat);
  dims := nil;
  SetLength(dims, 1);
  dims[0].Name := TyPieValueDim;
  dims[0].Kind := ddtFloat;
  dims[0].Axis := nil;
  TyFillSeriesStore(FOpt, 0, dims, FStore);
  FSpec := TyPieSpecOf(FOpt, 0);
  FLay := TyPieLayoutOf(FSpec, TyRectF(0, 0, AW, AH), FStore, 0);
end;

function TAdvChartPieTest.Sweep(AIndex: Integer): Double;
begin
  Result := FLay.Sectors[AIndex].EndRad - FLay.Sectors[AIndex].StartRad;
end;

function TAdvChartPieTest.Deg(ARad: Double): Double;
begin
  Result := ARad * 180 / Pi;
end;

procedure TAdvChartPieTest.TestTheDefaultDiscIsCentredAndAQuarterOfTheShorterSide;
begin
  Run('{ "series": [ { "type": "pie", "data": [1] } ] }', 400, 300);
  AssertTrue('it laid out', FLay.Valid);
  AssertEquals('centred across', 200.0, FLay.CX, EpsPx);
  AssertEquals('centred down', 150.0, FLay.CY, EpsPx);
  AssertEquals('solid by default', 0.0, FLay.R0, EpsPx);
  { PieSeries.ts:229 is [0, '50%'] and layout.ts:241-242 divides the shorter
    side by two before applying it. 300/2 = 150, half of that is 75.

    THE NUMBER THE DOCUMENTATION WOULD GIVE IS 112.5, from a '75%' this
    library's own catalog still carries. A pie half again too big fills its
    chart plausibly enough that nothing else would ever complain. }
  AssertEquals('a quarter of the shorter side', 75.0, FLay.R1, EpsPx);
end;

procedure TAdvChartPieTest.TestTheTwoPercentageBasesAreDifferent;
begin
  { An oblong chart is what separates them: on a square every base is the same
    number and a port that used min(w,h) for the centre too would pass. }
  Run('{ "series": [ { "type": "pie", "center": ["25%", "25%"],'
    + ' "radius": "100%", "data": [1] } ] }', 400, 300);
  AssertEquals('x is a share of the WIDTH', 100.0, FLay.CX, EpsPx);
  AssertEquals('y is a share of the HEIGHT', 75.0, FLay.CY, EpsPx);
  AssertEquals('but the radius is half the SHORTER side', 150.0, FLay.R1, EpsPx);
end;

procedure TAdvChartPieTest.TestABareRadiusForcesTheInnerOneToZero;
begin
  { layout.ts:235-237 rebuilds a scalar as [0, radius]; it does not leave the
    inner radius at whatever it was. }
  Run('{ "series": [ { "type": "pie", "radius": ["40%", "60%"],'
    + ' "data": [1] } ] }', 400, 300);
  AssertEquals('a pair is a pair', 60.0, FLay.R0, EpsPx);
  AssertEquals('outer too', 90.0, FLay.R1, EpsPx);

  Run('{ "series": [ { "type": "pie", "radius": "60%", "data": [1] } ] }',
    400, 300);
  AssertEquals('a scalar is the OUTER one', 90.0, FLay.R1, EpsPx);
  AssertEquals('and the inner one is zero', 0.0, FLay.R0, EpsPx);

  { A centre, by contrast, IS duplicated -- layout.ts:209-210. }
  Run('{ "series": [ { "type": "pie", "center": "25%", "data": [1] } ] }',
    400, 300);
  AssertEquals('a scalar centre goes to both', 100.0, FLay.CX, EpsPx);
  AssertEquals('each against its own base', 75.0, FLay.CY, EpsPx);
end;

procedure TAdvChartPieTest.TestTheSeriesBoxMovesBothTheCentreAndTheRadius;
begin
  { The pie's box defaults to the whole control, and left/top/right/bottom
    shrink it -- so a pie in the right half is centred on that half and sized
    by it. Both percentages are measured inside the box, not inside the
    control. }
  Run('{ "series": [ { "type": "pie", "left": "50%", "data": [1] } ] }',
    400, 300);
  AssertEquals('the box starts halfway', 200.0, FLay.ViewRect.Left, EpsPx);
  AssertEquals('and the centre is the middle of THAT', 300.0, FLay.CX, EpsPx);
  AssertEquals('down is unchanged', 150.0, FLay.CY, EpsPx);
  { min(200, 300) = 200, halved is 100, at 50% that is 50. }
  AssertEquals('the shorter side is now the width', 50.0, FLay.R1, EpsPx);
end;

procedure TAdvChartPieTest.TestTheDefaultStartIsTwelveOClockAndItRunsClockwise;
begin
  Run('{ "series": [ { "type": "pie", "data": [1, 1, 1, 1] } ] }');
  AssertEquals('four quarters', 4, Length(FLay.Sectors));
  { Canvas radians: +y is down, so 3*Pi/2 points UP. }
  AssertEquals('the ring starts at twelve', 270.0, Deg(FLay.StartRad), EpsPx);
  AssertEquals('the first sector starts there too', 270.0,
    Deg(FLay.Sectors[0].StartRad), EpsPx);
  AssertEquals('and sweeps a quarter FORWARD, which is clockwise', 90.0,
    Deg(Sweep(0)), EpsPx);
  AssertEquals('the next one carries on', 360.0,
    Deg(FLay.Sectors[1].StartRad), EpsPx);
  AssertEquals('the last one closes the turn', 630.0,
    Deg(FLay.Sectors[3].EndRad), EpsPx);
end;

procedure TAdvChartPieTest.TestTheOptionAngleIsNegated;
begin
  { pieLayout.ts:45 -- `-seriesModel.get('startAngle') * RADIAN`. The option is
    the mathematical convention (counter-clockwise from three o'clock); the
    layout works in canvas radians, which run the other way. }
  Run('{ "series": [ { "type": "pie", "startAngle": 0, "data": [1] } ] }');
  AssertEquals('zero degrees is three o''clock', 0.0,
    Deg(FLay.StartRad), EpsPx);

  Run('{ "series": [ { "type": "pie", "startAngle": 45, "data": [1] } ] }');
  { 45 counter-clockwise from three o'clock is up-and-right, which in canvas
    radians is 315 -- not 45. }
  AssertEquals('and 45 goes UP, not down', 315.0, Deg(FLay.StartRad), EpsPx);
end;

procedure TAdvChartPieTest.TestAnticlockwiseRunsTheOtherWay;
begin
  Run('{ "series": [ { "type": "pie", "clockwise": false,'
    + ' "data": [1, 1, 1, 1] } ] }');
  AssertFalse('it says so', FLay.Clockwise);
  AssertEquals('still starting at twelve', 270.0,
    Deg(FLay.Sectors[0].StartRad), EpsPx);
  AssertEquals('but sweeping BACKWARDS', -90.0, Deg(Sweep(0)), EpsPx);
  AssertEquals('so the second one is further back', 180.0,
    Deg(FLay.Sectors[1].StartRad), EpsPx);
end;

procedure TAdvChartPieTest.TestValuesTakeTheirShareOfTheTurn;
begin
  Run('{ "series": [ { "type": "pie", "data": [1, 3] } ] }');
  AssertEquals('a quarter of the total', 90.0, Deg(Sweep(0)), EpsPx);
  AssertEquals('and three quarters', 270.0, Deg(Sweep(1)), EpsPx);
end;

procedure TAdvChartPieTest.TestAHalfDoughnutFillsExactlyItsHalf;
begin
  { THE TEST THAT CATCHES A SKIPPED SECOND PASS. The first pass sizes every
    sector against a WHOLE turn -- two equal values would each take 180 -- and
    the redistribution is what squeezes them into the 180 this pie actually
    has. Skip it as an edge case and the pie draws a full circle over its own
    label area, which looks like a stray sector rather than like a bug in the
    angle arithmetic. }
  Run('{ "series": [ { "type": "pie", "startAngle": 180, "endAngle": 360,'
    + ' "radius": ["40%", "70%"], "data": [1, 1] } ] }');
  AssertEquals('nine o''clock', 180.0, Deg(FLay.StartRad), EpsPx);
  AssertEquals('round to three', 360.0, Deg(FLay.EndRad), EpsPx);
  AssertEquals('each takes half of the HALF', 90.0, Deg(Sweep(0)), EpsPx);
  AssertEquals('the second too', 90.0, Deg(Sweep(1)), EpsPx);
  AssertEquals('and together they end exactly where the ring does', 360.0,
    Deg(FLay.Sectors[1].EndRad), EpsPx);
end;

procedure TAdvChartPieTest.TestMinAngleTakesFromTheOthersRatherThanFromNothing;
begin
  { 100, 1, 1 would give the tiddlers about 3.5 degrees each. minAngle pins
    them at 30, and the 100 has to give up what they took -- 360 - 60 = 300,
    which it then has entirely to itself because it is the only unpinned one. }
  Run('{ "series": [ { "type": "pie", "minAngle": 30,'
    + ' "data": [100, 1, 1] } ] }');
  AssertEquals('the big one keeps the rest', 300.0, Deg(Sweep(0)), EpsPx);
  AssertEquals('pinned', 30.0, Deg(Sweep(1)), EpsPx);
  AssertEquals('pinned', 30.0, Deg(Sweep(2)), EpsPx);
  AssertEquals('and the ring is still closed', 630.0,
    Deg(FLay.Sectors[2].EndRad), EpsPx);
end;

procedure TAdvChartPieTest.TestPadAngleEatsBothEndsOfEverySector;
begin
  { pieLayout.ts:147-148: half the pad off the start, half off the end. The
    sector still OCCUPIES its full share -- padding is a gap in the ink, not a
    smaller slice -- so the next one starts where this one's share ended, not
    where its ink stopped. }
  Run('{ "series": [ { "type": "pie", "padAngle": 4,'
    + ' "data": [1, 1, 1, 1] } ] }');
  AssertEquals('each loses the whole pad', 86.0, Deg(Sweep(0)), EpsPx);
  AssertEquals('starting two degrees in', 272.0,
    Deg(FLay.Sectors[0].StartRad), EpsPx);
  AssertEquals('and the next starts two degrees into ITS share', 362.0,
    Deg(FLay.Sectors[1].StartRad), EpsPx);
  AssertEquals('the share itself is untouched', 90.0,
    Deg(FLay.Sectors[0].Angle), EpsPx);
end;

procedure TAdvChartPieTest.TestANegativeValueIsRemovedNotClamped;
begin
  { negativeDataFilter.ts:28-36 deletes the row before the layout runs, so it
    is not a sector with no angle -- there is no sector, and the total it is
    missing from is what makes the other two halves rather than thirds. }
  Run('{ "series": [ { "type": "pie", "data": [1, -5, 1] } ] }');
  AssertEquals('two sectors, not three', 2, Length(FLay.Sectors));
  AssertEquals('and each is half', 180.0, Deg(Sweep(0)), EpsPx);
  AssertEquals('the survivors keep their own rows', 0, FLay.Sectors[0].RawIndex);
  AssertEquals('skipping the one that went', 2, FLay.Sectors[1].RawIndex);
end;

procedure TAdvChartPieTest.TestANaNKeepsItsPlace;
begin
  { Not the same as a negative. A NaN stays in the ring as a sector with no
    geometry, which is what makes the equal-angle branch leave a gap where it
    was instead of closing up. }
  Run('{ "series": [ { "type": "pie", "data": [1, null, 1] } ] }');
  AssertEquals('three sectors', 3, Length(FLay.Sectors));
  AssertFalse('the middle one has no geometry', FLay.Sectors[1].Valid);
  AssertTrue('and says so in its angle', IsNan(FLay.Sectors[1].StartRad));
  AssertEquals('the other two are halves', 180.0, Deg(Sweep(0)), EpsPx);
  AssertEquals('and they are adjacent, not spread out', 450.0,
    Deg(FLay.Sectors[2].StartRad), EpsPx);
end;

procedure TAdvChartPieTest.TestAllZeroesStillShowOrDoNot;
begin
  { stillShowZeroSum, PieSeries.ts:252, default TRUE: a pie of zeroes is drawn
    as equal slices rather than as nothing, because "no data" and "all zero"
    are different answers and a blank circle cannot tell them apart. }
  Run('{ "series": [ { "type": "pie", "data": [0, 0, 0, 0] } ] }');
  AssertEquals('equal quarters', 90.0, Deg(Sweep(0)), EpsPx);
  AssertEquals('all of them', 90.0, Deg(Sweep(3)), EpsPx);

  Run('{ "series": [ { "type": "pie", "stillShowZeroSum": false,'
    + ' "data": [0, 0, 0, 0] } ] }');
  AssertEquals('switched off, nothing sweeps', 0.0, Deg(Sweep(0)), EpsPx);
end;

procedure TAdvChartPieTest.TestRoseTypeAreaEqualisesTheAnglesAndRadiusDoesNot;
begin
  { The one people get backwards. 'area' is the mode where every sector has
    the SAME angle -- that is what makes its AREA proportional, since area
    grows with the square of the radius. 'radius' leaves the angles alone. }
  Run('{ "series": [ { "type": "pie", "roseType": "area", "radius": "100%",'
    + ' "data": [1, 3] } ] }', 400, 400);
  AssertEquals('equal angles', 180.0, Deg(Sweep(0)), EpsPx);
  AssertEquals('equal angles', 180.0, Deg(Sweep(1)), EpsPx);
  { linearMap over [0, max] onto [r0, r]: 1/3 of 200 and all of it. }
  AssertEquals('but the radius carries the value', Double(200) / 3,
    FLay.Sectors[0].R1, EpsPx);
  AssertEquals('the biggest reaches the rim', 200.0, FLay.Sectors[1].R1, EpsPx);

  Run('{ "series": [ { "type": "pie", "roseType": "radius", "radius": "100%",'
    + ' "data": [1, 3] } ] }', 400, 400);
  AssertEquals('radius mode keeps the shares', 90.0, Deg(Sweep(0)), EpsPx);
  AssertEquals('and still scales the radius', Double(200) / 3,
    FLay.Sectors[0].R1, EpsPx);
end;

procedure TAdvChartPieTest.TestPercentagesAddUpToAHundred;
var
  seats: TTyDoubleArray;
begin
  { The largest remainder method, number.ts:402-447. Three thirds round to
    33.33 each and total 99.99, so the largest remainder gets the last hundredth
    -- which is why a pie's tooltip percentages add up. }
  seats := TyPiePercentSeats([1, 1, 1], 2);
  AssertEquals('three shares', 3, Length(seats));
  { THE TIE GOES TO THE FIRST, because number.ts:433 tests `>` against a
    running maximum that starts at negative infinity. Three identical
    remainders are the commonest case there is, so which one wins is not an
    academic question -- it decides which slice of a three-way pie reads 33.34
    in every tooltip the chart ever shows. }
  AssertEquals('and the first absorbs the remainder', 33.34, seats[0], 1e-9);
  AssertEquals(33.33, seats[1], 1e-9);
  AssertEquals(33.33, seats[2], 1e-9);
  AssertEquals('so they total a hundred', 100.0,
    seats[0] + seats[1] + seats[2], 1e-9);

  { A total of zero answers an EMPTY array rather than zeroes -- number.ts:406.
    The caller reads a missing seat as nothing, so the two agree in the end,
    but only one of them is upstream's. }
  seats := TyPiePercentSeats([0, 0], 2);
  AssertEquals('nothing to share out', 0, Length(seats));
end;

procedure TAdvChartPieTest.TestAPrecisionPastCountingStillAnswers;
var
  seats, pct: TTyDoubleArray;
begin
  { `percentPrecision` is whatever the author wrote, and `Math.pow(10, p)`
    carries on where FPC would raise. Every value below is upstream's own
    getPercentSeats, run in node. }

  { 1e19 reaches here as the largest Integer; digits is Infinity, an empty
    slice votes 0 * Infinity, and every seat is not-a-number -- which the
    label reads as 0 (`seats[i] || 0`). This one killed the whole render. }
  seats := TyPiePercentSeats([1, 1, 1], High(Integer));
  AssertEquals(3, Length(seats));
  AssertTrue('a seat past counting is not-a-number', IsNan(seats[0]));
  Run('{ "series": [ { "type": "pie", "data": [1, 1, 1] } ] }');
  pct := TyPieSectorPercents(FLay, High(Integer));
  AssertEquals('and the share it shows is 0', 0.0, pct[0], 0);
  AssertEquals(0.0, pct[2], 0);

  { 1e307: the votes overflow, and a share of Infinity is printed as one;
    an empty slice still votes 0 }
  seats := TyPiePercentSeats([0, 1], 307);
  AssertEquals('an empty slice', 0.0, seats[0], 0);
  AssertTrue('the other overflows', IsInfinite(seats[1]) and (seats[1] > 0));

  { 1e-323, the last power of ten above zero: nothing floors to a seat, the
    first slice gets the one there is, and one seat of 1e-323 is Infinity }
  seats := TyPiePercentSeats([1, 1, 1], -323);
  AssertTrue(IsInfinite(seats[0]));
  AssertEquals(0.0, seats[1], 0);
  AssertEquals(0.0, seats[2], 0);

  { and below it digits is 0, every seat 0 / 0 }
  seats := TyPiePercentSeats([1, 2], -400);
  AssertTrue(IsNan(seats[0]) and IsNan(seats[1]));

  { WHERE UPSTREAM NEVER RETURNS: past 2^53 the seat that would close the
    gap is no change to the sum, and its loop spins. This set does that at
    14 places; here it has to come back. }
  seats := TyPiePercentSeats([201, 906, 14, 92.57142857142857, 804, 282,
    142.14285714285714], 14);
  AssertEquals('it comes back', 7, Length(seats));
end;

procedure TAdvChartPieTest.TestTheMarksAreSectorsThatAnswerForTheirOwnRow;
var
  n, i: Integer;
  bind: TTySeriesBinding;
  vis: TTyPieVisual;
  el: TTyChartElement;
begin
  Run('{ "series": [ { "type": "pie", "data": [1, 1, 1, 1] } ] }');
  bind := Default(TTySeriesBinding);
  bind.Resolved := True;
  bind.SeriesIndex := 0;
  vis := TyPieVisual($FF3366CC);
  FList := TTyPaintList.Create;
  n := TyBuildPieMarks(bind, FLay, FSpec, vis, FList);
  AssertEquals('one per datum', 4, n);
  AssertEquals('and nothing else', 4, FList.Count);
  for i := 0 to 3 do
  begin
    el := FList.Element(i);
    AssertEquals('a sector', Ord(cskSector), Ord(el.Shape.Kind));
    AssertTrue('filled', el.Style.HasFill);
    AssertFalse('and it answers the pointer', el.Silent);
    AssertEquals('for its own series', 0, el.Datum.SeriesIndex);
    AssertEquals('and its own row', i, el.Datum.DataIndex);
  end;
  { The shape record normalises a sector's angles, so a hit test and the ink
    describe the same wedge whichever way round the pie ran. }
  AssertEquals('the first wedge starts at twelve', 270.0,
    Deg(FList.Element(0).Shape.StartRad), EpsPx);
end;

procedure TAdvChartPieTest.TestEachSectorTakesTheNextColour;
var
  bind: TTySeriesBinding;
  vis: TTyPieVisual;
begin
  { colorBy:'data'. A single-colour pie is a disc, so this is not a nicety --
    it is the difference between a chart and a circle. }
  Run('{ "series": [ { "type": "pie", "data": [1, 1, 1] } ] }');
  bind := Default(TTySeriesBinding);
  bind.Resolved := True;
  vis := TyPieVisual(0);
  SetLength(vis.Fills, 2);
  vis.Fills[0] := $FF111111;
  vis.Fills[1] := $FF222222;
  FList := TTyPaintList.Create;
  TyBuildPieMarks(bind, FLay, FSpec, vis, FList);
  AssertEquals('the first', $FF111111, FList.Element(0).Style.FillColor);
  AssertEquals('the second', $FF222222, FList.Element(1).Style.FillColor);
  AssertEquals('and the ramp cycles', $FF111111,
    FList.Element(2).Style.FillColor);
end;

procedure TAdvChartPieTest.TestAnEmptyPieDrawsItsRingAndSaysNothing;
var
  bind: TTySeriesBinding;
  vis: TTyPieVisual;
begin
  { showEmptyCircle, PieView.ts:263-271. An empty pie is a visible empty pie,
    which is how a reader tells "nothing matched" from "the chart is broken". }
  Run('{ "series": [ { "type": "pie", "data": [] } ] }');
  bind := Default(TTySeriesBinding);
  bind.Resolved := True;
  vis := TyPieVisual($FF888888);
  FList := TTyPaintList.Create;
  AssertEquals('the ring counts as drawn', 1,
    TyBuildPieMarks(bind, FLay, FSpec, vis, FList));
  AssertEquals('a sector', Ord(cskSector), Ord(FList.Element(0).Shape.Kind));
  AssertTrue('but it has no datum to report, so it is silent',
    FList.Element(0).Silent);

  { Switched off, nothing at all. }
  FSpec.ShowEmptyCircle := False;
  FList.Clear;
  AssertEquals('nothing', 0, TyBuildPieMarks(bind, FLay, FSpec, vis, FList));
end;

procedure TAdvChartPieTest.TestNormaliseNeverStretchesPastOneTurn;
var
  s, e: Double;
begin
  { zrender's normalizeArcAngles. Its whole job is that a sweep can never
    exceed a full turn -- a pie asking for 720 degrees would otherwise wrap
    over itself and the last sector would paint over the first. }
  s := 0;
  e := 4 * Pi;
  TyNormalizeArcAngles(s, e, False);
  AssertEquals('clamped to one turn', 360.0, Deg(e - s), EpsPx);

  s := 0;
  e := -4 * Pi;
  TyNormalizeArcAngles(s, e, True);
  AssertEquals('the other way too', -360.0, Deg(e - s), EpsPx);

  { A start outside [0, 2*Pi) is wrapped and the end follows it, so the sweep
    survives the wrap. }
  s := -Pi / 2;
  e := 0;
  TyNormalizeArcAngles(s, e, False);
  AssertEquals('wrapped', 270.0, Deg(s), EpsPx);
  AssertEquals('and the sweep is unchanged', 90.0, Deg(e - s), EpsPx);
end;

procedure TAdvChartPieTest.TestAWholeTurnComesOutExact;
var
  s, e: Double;
begin
  { A WHOLE TURN IS A WHOLE TURN, to the last bit. That is what keeps the
    ordinary pie out of the redistribution pass, which exists for pies that
    are missing an arc: a sweep one part in 10^16 short of a turn is not the
    same number as a turn, and the test `restAngle < 2*Pi` reads it that way.

    ZERO TOLERANCE ON PURPOSE -- exactness IS the property, and an epsilon
    here would assert nothing.

    WHAT THIS DOES NOT PIN, said plainly: it does not pin modPI2's rounding.
    Measured over the 360 whole-degree start angles, the rounding lands 273 of
    them exactly on a turn against 215 without it -- better, but not a
    guarantee, and 90 is exact either way. The mutant that drops the rounding
    survives on purpose. }
  s := 3 * Pi / 2;
  e := -Pi / 2;
  TyNormalizeArcAngles(s, e, False);
  AssertTrue('a whole turn is a whole turn, to the last bit',
    (e - s) = 2 * Pi);
end;

procedure TAdvChartPieTest.TestTheScalarsAreActuallyReadOffTheOption;
var spec: TTyPieSpec;
begin
  { EVERY ONE OF THESE IS READ BY THE SAME FUNCTION, and that function had
    tests only for the keys with visible geometry. showEmptyCircle proved
    it: switching it off worked when the record was poked, and it had never
    once been switched off THROUGH THE OPTION -- so a reader that ignored
    the key entirely passed the whole suite. Second time this library has
    been caught by that exact shape of hole. }
  AssertTrue('the option parsed', FOpt.SetOptionText(
    '{ "series": [ { "type": "pie", "showEmptyCircle": false,'
    + ' "minShowLabelAngle": 7, "percentPrecision": 4, "roseType": true,'
    + ' "center": "center", "data": [1] } ] }'));
  spec := TyPieSpecOf(FOpt, 0);
  AssertFalse('the empty ring can be switched off', spec.ShowEmptyCircle);
  AssertEquals('the label threshold is read', 7.0,
    spec.MinShowLabelAngleDeg, Eps);
  AssertEquals('so is the percent precision', 4, spec.PercentPrecision);
  { pieLayout.ts tests roseType for TRUTH rather than for membership, so
    `true` -- which is not one of the documented values -- behaves as
    'radius'. }
  AssertEquals('a truthy roseType is radius', Ord(prtRadius),
    Ord(spec.Rose));
  { And the keyword forms of a position, which parsePositionOption accepts
    everywhere a percentage is accepted. }
  AssertEquals('centre means fifty per cent', 200.0,
    TyPieResolve(spec.CentreX, 400), EpsPx);
end;

procedure TAdvChartPieTest.TestBorderRadiusReachesTheSectorAndIsAShareOfTheOuterRadius;
var
  bind: TTySeriesBinding;
  vis: TTyPieVisual;
  corners: TTyDoubleArray;
begin
  { A SCALAR MEANS ALL FOUR CORNERS, and it has to be expanded HERE rather
    than left for the shape: zrender reads a bare number and a one-element
    array by different rules -- 5 is every corner, [5] is the inner pair
    only -- and ECharts expands the number before zrender ever sees it. Leave
    it alone and `borderRadius: 8` on a doughnut rounds the hole and leaves
    the rim square. }
  Run('{ "series": [ { "type": "pie", "radius": ["40%", "70%"],'
    + ' "itemStyle": { "borderRadius": 8 }, "data": [1, 1] } ] }');
  corners := TyPieCornersFor(FSpec, FLay.R0, FLay.R1);
  AssertEquals('all four', 4, Length(corners));
  AssertEquals('in pixels as written', 8.0, corners[0], EpsPx);
  AssertEquals('', 8.0, corners[3], EpsPx);

  bind := Default(TTySeriesBinding);
  bind.Resolved := True;
  vis := TyPieVisual($FF3366CC);
  FList := TTyPaintList.Create;
  TyBuildPieMarks(bind, FLay, FSpec, vis, FList);
  AssertEquals('and it reaches the shape', 8.0,
    FList.Element(0).Shape.SectorRadii[0], EpsPx);

  { A PERCENTAGE IS A SHARE OF THE OUTER RADIUS, NOT OF THE RING. That is
    upstream's operator precedence rather than upstream's intent --
    sectorHelper.ts:37 reads as `r || (0 - r0) || 0` -- and a port that did
    the sensible thing instead would round every doughnut differently from
    the chart it is being compared against. On a 300-tall chart the outer
    radius is 105 and the ring is 45 thick, so 10% is 10.5 and not 4.5. }
  Run('{ "series": [ { "type": "pie", "radius": ["40%", "70%"],'
    + ' "itemStyle": { "borderRadius": "10%" }, "data": [1, 1] } ] }',
    400, 300);
  AssertEquals('the ring runs from', 60.0, FLay.R0, EpsPx);
  AssertEquals('to', 105.0, FLay.R1, EpsPx);
  corners := TyPieCornersFor(FSpec, FLay.R0, FLay.R1);
  AssertEquals('a tenth of the OUTER radius', 10.5, corners[0], EpsPx);

  { And an array is passed through as written, for the shape to read by the
    SECTOR rules. }
  Run('{ "series": [ { "type": "pie",'
    + ' "itemStyle": { "borderRadius": [1, 2] }, "data": [1] } ] }');
  corners := TyPieCornersFor(FSpec, FLay.R0, FLay.R1);
  AssertEquals('two, not four', 2, Length(corners));
end;

initialization
  RegisterTest(TAdvChartPieTest);
end.
