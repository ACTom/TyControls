unit test.advchart.axis;
{$mode objfpc}{$H+}
{ The two-phase axis build (Tier 0 item 12): estimate -> shrink -> determine.

  Every test here runs against a FAKE measurer with fixed per-character metrics,
  which is the whole reason ITyTextMeasurer is injected. Measured against a real
  font these assertions would be asserting the local font as much as the
  algorithm, and would differ between Win32, GTK and Qt (repo memory
  headless-tests-never-run-lcl-align). The real, painter-backed measurer is
  verified separately in test.advchart.measure. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry,
     tyControls.AdvChart.Types, tyControls.AdvChart.Layout;
type
  { CharW px per character, CharH px tall, whatever the font says. }
  TFakeMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  private
    FCharW, FCharH: Double;
  public
    constructor Create(ACharW, ACharH: Double);
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

  TAdvChartAxisTest = class(TTestCase)
  private
    FM: ITyTextMeasurer;
    function BottomAxis(const ALabels: array of string): TTyAxisLayoutSpec;
    function LeftAxis(const ALabels: array of string): TTyAxisLayoutSpec;
    procedure SetUp; override;
  published
    { ---- phase 1: thickness ---- }
    procedure TestThicknessCountsTheWidestLabelNotTheLast;
    procedure TestThicknessOfAHorizontalAxisIsTheLabelHeight;
    procedure TestThicknessOfAVerticalAxisIsTheLabelWidth;
    procedure TestThicknessIncludesTickAndMargin;
    procedure TestNameCountsOnlyUnderContainAll;
    procedure TestRotationMakesAHorizontalAxisThicker;
    procedure TestQuarterTurnHorizontalThicknessIsTheLabelWidth;
    procedure TestHiddenLabelsCostNothingButTheTick;
    procedure TestTheLabelStandsInTheBandTheThicknessReserved;
    procedure TestAnInsideLabelCrossesTheAxisAndFlipsItsAnchor;
    procedure TestAnInwardTickIsChargedNothingHoweverLongItIs;
    { ---- phase 2: shrink ---- }
    procedure TestLabelsThatFitTheBoundsCostTheGridNothing;
    procedure TestOnlyTheOverflowIsTakenOnTheSideItOverflows;
    procedure TestTwoAxesOnOneSideTakeTheLargerNotTheSum;
    procedure TestAnOverflowAlongTheAxisIsDividedByHowFarAlongItSits;
    procedure TestTheClampStopsTheShrinkAtAQuarterOfTheRawRect;
    procedure TestANameCountsUnderContainAllWhereItIsDrawn;
    procedure TestANoughtProportionTakesTheOverflowAsItIs;
    procedure TestAYOverflowIsDividedOnItsOwnSide;
    procedure TestTheShrinkNeitherGrowsNorClampsPastTheRect;
    procedure TestAYLabelsProportionIsMeasuredFromTheTop;
    procedure TestAThinnedLabelIsNotMeasured;
    procedure TestLegacyContainLabelSkipsInsideLabels;
    { ---- phase 3: placement and thinning ---- }
    procedure TestBottomLabelAnchorsSitOnTheTicks;
    procedure TestBottomLabelsSitBelowThePlot;
    procedure TestLeftLabelsAreRightAlignedAndMiddleAnchored;
    procedure TestLeftAxisFractionsRunFromTheBottom;
    procedure TestRoomyAxisShowsEveryLabel;
    procedure TestCrowdedAxisThinsToAUniformStep;
    procedure TestThinningNeverHidesEverything;
    procedure TestLabelStepAgreesWithThePlacements;
  end;

implementation

const
  Eps = 1e-9;

constructor TFakeMeasurer.Create(ACharW, ACharH: Double);
begin
  inherited Create;
  FCharW := ACharW;
  FCharH := ACharH;
end;

procedure TFakeMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
begin
  AW := Length(AText) * FCharW;
  AH := FCharH;
end;

procedure TAdvChartAxisTest.SetUp;
begin
  inherited SetUp;
  FM := TFakeMeasurer.Create(10, 20);
end;

function TAdvChartAxisTest.BottomAxis(const ALabels: array of string): TTyAxisLayoutSpec;
var i, n: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Side := asBottom;
  Result.ShowLabels := True;
  { What the builder fills in for a real axis. The show family defaults to
    False in a zeroed record, and these fixtures are about the ARITHMETIC of
    the gutter -- WHAT gets drawn is TAdvChartFurnitureTest's subject. }
  Result.ShowTicks := True;
  n := Length(ALabels);
  SetLength(Result.Labels, n);
  SetLength(Result.Positions, n);
  for i := 0 to n - 1 do
  begin
    Result.Labels[i] := ALabels[i];
    if n = 1 then
      Result.Positions[i] := 0
    else
      Result.Positions[i] := i / (n - 1);
  end;
  Result.FontSizeLogical := 12;
  Result.FontWeight := 400;
  Result.LabelMarginLogical := 8;
  Result.TickLengthLogical := 5;
  Result.NameGapLogical := 15;
end;

function TAdvChartAxisTest.LeftAxis(const ALabels: array of string): TTyAxisLayoutSpec;
begin
  Result := BottomAxis(ALabels);
  Result.Side := asLeft;
end;

{ ======================== phase 1: thickness ======================== }

procedure TAdvChartAxisTest.TestThicknessCountsTheWidestLabelNotTheLast;
var a: TTyAxisLayoutSpec;
begin
  { The widest one is in the MIDDLE. A thickness computed from the last label,
    or from the first, would be a plausible-looking bug that only shows up when
    a middle tick happens to carry a long value. }
  a := LeftAxis(['1', '1000000', '9']);
  AssertEquals('width of "1000000" (7 chars x 10) + tick 5 + margin 8',
               70 + 5 + 8, TyAxisThickness(a, FM, 96, obcAxisLabel), Eps);
end;

procedure TAdvChartAxisTest.TestThicknessOfAHorizontalAxisIsTheLabelHeight;
var a: TTyAxisLayoutSpec;
begin
  a := BottomAxis(['1000000']);
  { A bottom axis is thick by its labels' HEIGHT, however wide they are. }
  AssertEquals('height 20 + tick 5 + margin 8', 33.0,
               TyAxisThickness(a, FM, 96, obcAxisLabel), Eps);
end;

procedure TAdvChartAxisTest.TestThicknessOfAVerticalAxisIsTheLabelWidth;
var a: TTyAxisLayoutSpec;
begin
  a := LeftAxis(['12345']);
  AssertEquals('width 50 + tick 5 + margin 8', 63.0,
               TyAxisThickness(a, FM, 96, obcAxisLabel), Eps);
end;

procedure TAdvChartAxisTest.TestThicknessIncludesTickAndMargin;
var a, b: TTyAxisLayoutSpec;
begin
  a := BottomAxis(['x']);
  b := a;
  b.TickLengthLogical := 25;
  AssertEquals('a longer tick pushes the labels out by exactly its own extra',
               TyAxisThickness(a, FM, 96, obcAxisLabel) + 20,
               TyAxisThickness(b, FM, 96, obcAxisLabel), Eps);
end;

procedure TAdvChartAxisTest.TestNameCountsOnlyUnderContainAll;
var
  a: TTyAxisLayoutSpec;
  withoutName, withName: Double;
begin
  a := BottomAxis(['x']);
  a.Name := 'Value';                    // 5 chars -> 50 wide, 20 tall
  withoutName := TyAxisThickness(a, FM, 96, obcAxisLabel);
  withName := TyAxisThickness(a, FM, 96, obcAll);
  AssertEquals('outerBoundsContain:axisLabel leaves the name outside',
               33.0, withoutName, Eps);
  { A horizontal axis' name reads horizontally, so it costs its HEIGHT. }
  AssertEquals('outerBoundsContain:all adds the name gap and its height',
               withoutName + 15 + 20, withName, Eps);
end;

procedure TAdvChartAxisTest.TestRotationMakesAHorizontalAxisThicker;
var
  a, r: TTyAxisLayoutSpec;
begin
  a := BottomAxis(['1000000']);
  r := a;
  r.RotationRad := Pi / 4;
  AssertTrue('turning long labels needs more room under the axis',
             TyAxisThickness(r, FM, 96, obcAxisLabel)
             > TyAxisThickness(a, FM, 96, obcAxisLabel) + 10);
end;

procedure TAdvChartAxisTest.TestQuarterTurnHorizontalThicknessIsTheLabelWidth;
var a: TTyAxisLayoutSpec;
begin
  a := BottomAxis(['1000000']);
  a.RotationRad := Pi / 2;
  { Turned upright, a bottom axis' thickness is the label's WIDTH, not its
    height -- 7 chars x 10 = 70, plus tick and margin. This is the exact value,
    not an inequality, because a sign slip in the rotated-extent formula would
    still satisfy "thicker than unrotated". }
  AssertEquals('70 + 5 + 8', 83.0, TyAxisThickness(a, FM, 96, obcAxisLabel), 1e-6);
end;

procedure TAdvChartAxisTest.TestHiddenLabelsCostNothingButTheTick;
var a: TTyAxisLayoutSpec;
begin
  a := BottomAxis(['1000000']);
  a.ShowLabels := False;
  { Labels off must give the space back, not merely stop drawing -- the same
    rule TTyChart.ShowLegend follows. }
  AssertEquals('just the tick', 5.0, TyAxisThickness(a, FM, 96, obcAxisLabel), Eps);
end;

{ ======================== phase 2: shrink ======================== }

{ The whole canvas, as upstream's default outer bounds are. }
function Canvas: TTyXYWH;
begin
  Result := TyXYWH(0, 0, 400, 300);
end;

procedure TAdvChartAxisTest.TestLabelsThatFitTheBoundsCostTheGridNothing;
var
  axes: TTyAxisLayoutSpecArray;
  plot: TTyRectF;
begin
  { v6's default: the grid is the rect written, and the labels may stand
    outside it as long as they stay on the canvas. Anchored at 70 - 8, a
    label of 50 padded by 3 reaches 9: inside, so nothing moves.
    [Revised in batch 37: this was "outer bounds none does not shrink",
    beside a default that reserved every label's room inside the rect.] }
  SetLength(axes, 1);
  axes[0] := LeftAxis(['12345']);
  axes[0].TextMarginHLogical := 3;
  plot := TySolveGridBounds(TyRectF(70, 20, 330, 260), Canvas, obcAll, 0, 0,
    axes, FM, 96, Canvas);
  AssertEquals(70.0, plot.Left, 0);
  AssertEquals(20.0, plot.Top, 0);
  AssertEquals(330.0, plot.Right, 0);
  AssertEquals(260.0, plot.Bottom, 0);
end;

procedure TAdvChartAxisTest.TestOnlyTheOverflowIsTakenOnTheSideItOverflows;
var
  axes: TTyAxisLayoutSpecArray;
  plot: TTyRectF;
begin
  { A grid filling the canvas: the y label stands 8 out from the edge, 50
    wide, padded 3 each end -- it overflows the left by 61; the x label,
    20 tall 8 below, overflows the bottom by 28. THE TICK IS NOT IN IT:
    upstream's label sits at the margin from the line, and the margin
    clears the tick.
    [Revised in batch 37: 63 and 33 -- tick, margin and label, reserved
    inside the rect whether or not anything overflowed.] }
  SetLength(axes, 2);
  axes[0] := LeftAxis(['12345']);
  axes[0].Positions[0] := 0.5;
  axes[0].TextMarginHLogical := 3;
  axes[1] := BottomAxis(['1']);
  axes[1].Positions[0] := 0.5;
  axes[1].TextMarginHLogical := 3;
  plot := TySolveGridBounds(TyRectF(0, 0, 400, 300), Canvas, obcAll, 0, 0,
    axes, FM, 96, Canvas);
  AssertEquals('left in by the y label', 61.0, plot.Left, 0);
  AssertEquals('bottom up by the x label', 272.0, plot.Bottom, 0);
  AssertEquals('right untouched', 400.0, plot.Right, 0);
  AssertEquals('top untouched', 0.0, plot.Top, 0);
end;

procedure TAdvChartAxisTest.TestTwoAxesOnOneSideTakeTheLargerNotTheSum;
var
  axes: TTyAxisLayoutSpecArray;
  plot: TTyRectF;
begin
  { EACH SIDE TAKES ITS LARGEST OVERFLOW. Two axes on one side are already
    apart by their offset, and the offset is in where their labels stand --
    adding their widths would count the first one twice.
    [Revised in batch 37: the side's inset was the sum.] }
  SetLength(axes, 2);
  axes[0] := LeftAxis(['12345']);        // overflows by 8 + 50 + 3 = 61
  axes[0].Positions[0] := 0.5;
  axes[0].TextMarginHLogical := 3;
  axes[1] := LeftAxis(['12']);           // by 8 + 20 + 3 = 31
  axes[1].Positions[0] := 0.5;
  axes[1].TextMarginHLogical := 3;
  plot := TySolveGridBounds(TyRectF(0, 0, 400, 300), Canvas, obcAll, 0, 0,
    axes, FM, 96, Canvas);
  AssertEquals('the larger', 61.0, plot.Left, 0);
  { offset 60 stands the second axis' labels further out: 60 + 31 }
  axes[1].OffsetLogical := 60;
  plot := TySolveGridBounds(TyRectF(0, 0, 400, 300), Canvas, obcAll, 0, 0,
    axes, FM, 96, Canvas);
  AssertEquals('the offset one, now', 91.0, plot.Left, 0);
end;

procedure TAdvChartAxisTest.TestAnOverflowAlongTheAxisIsDividedByHowFarAlongItSits;
var
  axes: TTyAxisLayoutSpecArray;
  plot: TTyRectF;
begin
  { A label halfway along the axis comes in by half of any shrink, so to
    bring its 3 px of overflow in the plot must give up 6 -- on each side
    it overflows. Across the axis the overflow is taken as it is. }
  SetLength(axes, 1);
  axes[0] := BottomAxis(['1234567890']);
  axes[0].Positions[0] := 0.5;
  SetLength(axes[0].Proportions, 1);
  axes[0].Proportions[0] := 0.5;
  axes[0].TextMarginHLogical := 3;
  plot := TySolveGridBounds(TyRectF(0, 0, 100, 300), TyXYWH(0, 0, 100, 300),
    obcAll, 0, 0, axes, FM, 96, TyXYWH(0, 0, 100, 300));
  AssertEquals('left: 3 / 0.5', 6.0, plot.Left, 0);
  AssertEquals('right: 3 / 0.5', 94.0, plot.Right, 0);
  AssertEquals('bottom: 8 + 20, as it is', 272.0, plot.Bottom, 0);
end;

procedure TAdvChartAxisTest.TestANameCountsUnderContainAllWhereItIsDrawn;
var
  axes: TTyAxisLayoutSpecArray;
  withName, labelsOnly: TTyRectF;
begin
  { UNDER outerBoundsContain 'all' A NAME COUNTS WHERE IT IS LAID OUT, and
    under 'axisLabel' it does not. A middle name on a left axis, 50 by 20,
    turned with the axis: 15 out from the line, bottom-aligned towards it,
    padded by the grid's level -- 400 wide on a 400 canvas is level 2, eight
    across and three along -- so 36 wide, its near side at 7. The labels
    stand 8 out and are 50 wide, reaching 58: in the way. It is moved out
    until its near side is a tenth inside theirs, 57.9, and its far side is
    then 93.9 from the edge.
    [Revised in batch 38: the interim rule -- a turned name centred past the
    labels' band, 90.5 here, and 100 / 200 for the long one -- gave way to
    upstream's layout.] }
  SetLength(axes, 1);
  axes[0] := LeftAxis(['12345']);
  axes[0].Positions[0] := 0.5;
  axes[0].Name := 'Value';
  axes[0].NameLocation := anlMiddle;
  withName := TySolveGridBounds(TyRectF(0, 0, 400, 300), Canvas, obcAll, 0, 0,
    axes, FM, 96, Canvas);
  labelsOnly := TySolveGridBounds(TyRectF(0, 0, 400, 300), Canvas,
    obcAxisLabel, 0, 0, axes, FM, 96, Canvas);
  AssertEquals('the labels alone', 58.0, labelsOnly.Left, 0);
  AssertEquals('the name past them', 93.9, withName.Left, 1e-9);

  { ALONG ITS AXIS A MIDDLE NAME IS HALFWAY: forty characters and three on
    each end are 406 along a 300 plot, 53 over each end, and a thing halfway
    along is brought in by half the shrink -- so each end gives up 106 }
  axes[0].Name := '1234567890123456789012345678901234567890';
  withName := TySolveGridBounds(TyRectF(0, 0, 400, 300), Canvas, obcAll, 0, 0,
    axes, FM, 96, Canvas);
  AssertEquals('top in by 53 / 0.5', 106.0, withName.Top, 1e-9);
  AssertEquals('and the bottom', 194.0, withName.Bottom, 1e-9);

  { AN END NAME IS WHERE IT IS, and counts so: level, centred over the top
    of the line, 15 above it -- 25 over the canvas, taken as it is }
  axes[0].Name := 'Value';
  axes[0].NameLocation := anlEnd;
  withName := TySolveGridBounds(TyRectF(0, 0, 400, 300), Canvas, obcAll, 0, 0,
    axes, FM, 96, Canvas);
  AssertEquals('the top by the end name', 35.0, withName.Top, 1e-9);
  AssertEquals('the left by its half and three', 58.0, withName.Left, 1e-9);
end;

function Item(AX, AY, AW, AH: Double; AAlongY: Boolean;
  AProportion: Double): TTyBoundsItem;
begin
  Result.R := TyXYWH(AX, AY, AW, AH);
  Result.AlongY := AAlongY;
  Result.Proportion := AProportion;
end;

procedure TAdvChartAxisTest.TestANoughtProportionTakesTheOverflowAsItIs;
var
  items: TTyBoundsItemArray;
  m: TTyMargin4;
begin
  { A THING AT THE VERY START OF ITS AXIS is not brought in at all by a
    shrink from the far end, and dividing by that nought would ask for an
    infinite one. Upstream gives up the division below 1e-4 and takes the
    overflow as it is. }
  SetLength(items, 1);
  items[0] := Item(0, 0, 190, 10, False, 0);
  m := TyOuterBoundsMargin(TyXYWH(0, 0, 100, 300), TyXYWH(0, 0, 100, 300), items);
  AssertEquals('p 0: as it is', 90.0, m[1], 0);
  items[0].Proportion := 5e-5;
  m := TyOuterBoundsMargin(TyXYWH(0, 0, 100, 300), TyXYWH(0, 0, 100, 300), items);
  AssertEquals('p below 1e-4: as it is', 90.0, m[1], 0);
  items[0].Proportion := 0.5;
  m := TyOuterBoundsMargin(TyXYWH(0, 0, 100, 300), TyXYWH(0, 0, 100, 300), items);
  AssertEquals('p 0.5: doubled', 180.0, m[1], 0);
end;

procedure TAdvChartAxisTest.TestAYOverflowIsDividedOnItsOwnSide;
var
  items: TTyBoundsItemArray;
  m: TTyMargin4;
  over: Double;
begin
  { upstream's fillMarginOnOneDimension on y: the top divides by 1 - p, the
    bottom by p -- p here being the item's, already measured from the top }
  SetLength(items, 2);
  items[0] := Item(10, -10, 5, 5, True, 0.25);
  items[1] := Item(10, 305, 5, 5, True, 0.25);
  m := TyOuterBoundsMargin(TyXYWH(0, 0, 100, 300), TyXYWH(0, 0, 100, 300), items);
  over := 10;
  AssertEquals('the top by 1 - p', over / 0.75, m[0], 0);
  AssertEquals('the bottom by p', over / 0.25, m[2], 0);
end;

procedure TAdvChartAxisTest.TestTheShrinkNeitherGrowsNorClampsPastTheRect;
var
  r: TTyXYWH;
  m: TTyMargin4;
begin
  { a negative margin is none: a label well inside never grows the plot }
  r := TyXYWH(0, 0, 100, 300);
  m[0] := -10; m[1] := -10; m[2] := -10; m[3] := -10;
  TyShrinkRect(r, m, 0, 0);
  AssertEquals(0.0, r.X, 0);
  AssertEquals(100.0, r.W, 0);
  AssertEquals(300.0, r.H, 0);
  { A CLAMP BIGGER THAN THE RECT is the rect's own size: shrunk by 30 on the
    left against a floor of 500, it keeps its 100 -- and, from the left only,
    moves to where its right end was, as upstream's does }
  r := TyXYWH(0, 0, 100, 300);
  m[0] := 0; m[1] := 0; m[2] := 0; m[3] := 30;
  TyShrinkRect(r, m, 500, 0);
  AssertEquals('no wider than it was', 100.0, r.W, 0);
  AssertEquals('at its old right end', 100.0, r.X, 0);
end;

procedure TAdvChartAxisTest.TestAYLabelsProportionIsMeasuredFromTheTop;
var
  a: TTyAxisLayoutSpec;
  items: TTyBoundsItemArray;
begin
  { a y axis' proportion counts up from the bottom, and the overflow the
    shrink divides by it is the one BELOW -- so the item carries 1 - p }
  a := LeftAxis(['1']);
  a.Positions[0] := 0.25;
  SetLength(a.Proportions, 1);
  a.Proportions[0] := 0.25;
  items := TyAxisLabelBoundsItems(a, TyRectF(0, 0, 400, 300), FM, 96);
  AssertEquals(1, Length(items));
  AssertEquals(0.75, items[0].Proportion, 0);
  { and an x axis' is as it is }
  a := BottomAxis(['1']);
  SetLength(a.Proportions, 1);
  a.Proportions[0] := 0.25;
  items := TyAxisLabelBoundsItems(a, TyRectF(0, 0, 400, 300), FM, 96);
  AssertEquals(0.25, items[0].Proportion, 0);
end;

procedure TAdvChartAxisTest.TestAThinnedLabelIsNotMeasured;
var
  a: TTyAxisLayoutSpec;
  items: TTyBoundsItemArray;
  i: Integer;
begin
  { ONLY THE LABELS THE ESTIMATE SHOWS: a 300-wide label in the middle of a
    100-wide axis thins the axis to every other label, and the one thinned
    out -- the widest -- must not push the plot in }
  a := BottomAxis(['1', '123456789012345678901234567890', '3']);
  items := TyAxisLabelBoundsItems(a, TyRectF(0, 0, 100, 300), FM, 96);
  AssertEquals('the two ends only', 2, Length(items));
  for i := 0 to High(items) do
    AssertTrue('and not the wide one', items[i].R.W < 50);
end;

procedure TAdvChartAxisTest.TestLegacyContainLabelSkipsInsideLabels;
var
  axes: TTyAxisLayoutSpecArray;
  r: TTyRectF;
begin
  { legacy containLabel: a label inside the plot takes nothing from it }
  SetLength(axes, 1);
  axes[0] := LeftAxis(['12345']);
  axes[0].LegacyLabels := True;
  r := TyLegacyContainLabel(TyRectF(0, 0, 400, 300), axes, FM, 96);
  AssertEquals('outside: 50 + 8 off the left', 58.0, r.Left, 0);
  axes[0].LabelInside := True;
  r := TyLegacyContainLabel(TyRectF(0, 0, 400, 300), axes, FM, 96);
  AssertEquals('inside: nothing', 0.0, r.Left, 0);
end;

procedure TAdvChartAxisTest.TestTheClampStopsTheShrinkAtAQuarterOfTheRawRect;
var
  axes: TTyAxisLayoutSpecArray;
  plot: TTyRectF;
begin
  { NO SIDE SHRINKS PAST THE CLAMP -- and where the rect then goes is
    upstream's own: overflowing on the left only, it keeps its width at the
    clamp and moves to the RIGHT end of where it was (expandOrShrinkRect's
    `oldSize + delta`). A label wider than the canvas does that. }
  SetLength(axes, 1);
  axes[0] := LeftAxis(['1234567890123456789012345678901234567890']);
  plot := TySolveGridBounds(TyRectF(0, 0, 400, 300), Canvas, obcAll, 100, 75,
    axes, FM, 96, Canvas);
  AssertEquals('at the clamp', 100.0, TyRectFWidth(plot), 0);
  AssertEquals('past the old right edge', 400.0, plot.Left, 0);
end;

{ THE TWO HALVES OF THE GUTTER MUST AGREE. TyAxisThickness says how much the
  plot gives up; TyLayoutAxisLabels says where in it the text goes. They are
  different routines in different parts of this unit and they were written
  apart -- so when the thickness stopped charging for furniture that is not
  drawn, the placement went on standing the label a tick-length further out
  than the band it was given. These three pin them together. }

procedure TAdvChartAxisTest.TestTheLabelStandsInTheBandTheThicknessReserved;
var
  a: TTyAxisLayoutSpec;
  p: TTyAxisLabelPlacementArray;
begin
  { THE LABEL STANDS AT THE MARGIN FROM THE AXIS LINE, tick or no tick --
    upstream's rule, and its default margin of 8 clears the default tick of 5
    on its own. An OFFSET moves the line, and the label with it.
    [Revised in batch 37: this pinned the label a tick further out whenever
    the tick pointed its way (87), and ignored the offset -- so an offset
    axis drew its line out at the offset and its numbers against the plot.
    The thickness still counts the tick: it places only the axis name now.] }
  a := LeftAxis(['1000']);
  p := TyLayoutAxisLabels(a, TyRectF(100, 0, 300, 200), FM, 96);
  AssertEquals('the margin from the plot', 92.0, p[0].X, Eps);
  a.ShowTicks := False;
  p := TyLayoutAxisLabels(a, TyRectF(100, 0, 300, 200), FM, 96);
  AssertEquals('the same with no tick', 92.0, p[0].X, Eps);
  a.OffsetLogical := 10;
  p := TyLayoutAxisLabels(a, TyRectF(100, 0, 300, 200), FM, 96);
  AssertEquals('an offset line takes its labels with it', 82.0, p[0].X, Eps);
end;

procedure TAdvChartAxisTest.TestAnInsideLabelCrossesTheAxisAndFlipsItsAnchor;
var
  a: TTyAxisLayoutSpec;
  p: TTyAxisLabelPlacementArray;
begin
  { THE ANCHOR HAS TO TURN WITH IT. A left axis' label reads leftwards from
    its anchor; moved inside the plot and still right-anchored it would read
    back out across the axis line it was moved off, so the move would gain
    nothing. Both halves asserted, because the position alone is satisfied by
    a label that straddles the line. }
  a := LeftAxis(['1000']);
  a.LabelInside := True;
  p := TyLayoutAxisLabels(a, TyRectF(100, 0, 300, 200), FM, 96);
  AssertEquals('the margin INTO the plot, not out of it',
    108.0, p[0].X, Eps);
  AssertTrue('and it reads rightwards from there', p[0].AnchorH = tahLeft);
  { The LABELS reserve nothing; the tick still points outward and still costs
    its five. Asking for nought here would be asking `inside` to hide the
    ticks as well, which is a different option. }
  AssertEquals('the outward tick, and nothing else', 5.0,
    TyAxisThickness(a, FM, 96, obcAxisLabel), Eps);

  a := BottomAxis(['1000']);
  a.LabelInside := True;
  p := TyLayoutAxisLabels(a, TyRectF(0, 0, 200, 150), FM, 96);
  { The margin alone: the tick still points DOWN, away from the label, so it
    is not between the two and does not push them apart. }
  AssertEquals('a bottom label moves UP into the plot', 142.0, p[0].Y, Eps);
  AssertTrue('and hangs from its bottom edge', p[0].AnchorV = tavBottom);
end;

procedure TAdvChartAxisTest.TestAnInwardTickIsChargedNothingHoweverLongItIs;
var a: TTyAxisLayoutSpec;
begin
  { A NEGATIVE LENGTH is upstream's other way of pointing the mark inwards,
    and it must not come off the gutter: charged as written, a tick of -60
    would give the axis a thickness smaller than its own labels and pull the
    plot out past the container. }
  a := LeftAxis(['1000']);
  a.TickLengthLogical := -60;
  AssertEquals('the labels and their margin, and nothing off them',
    8 + 40.0, TyAxisThickness(a, FM, 96, obcAxisLabel), Eps);
end;

{ =================== phase 3: placement and thinning =================== }

procedure TAdvChartAxisTest.TestBottomLabelAnchorsSitOnTheTicks;
var
  a: TTyAxisLayoutSpec;
  p: TTyAxisLabelPlacementArray;
begin
  a := BottomAxis(['0', '5', '10']);
  p := TyLayoutAxisLabels(a, TyRectF(100, 0, 300, 200), FM, 96);
  AssertEquals('first label on the left edge', 100.0, p[0].X, Eps);
  AssertEquals('middle label at the middle', 200.0, p[1].X, Eps);
  AssertEquals('last label on the right edge', 300.0, p[2].X, Eps);
end;

procedure TAdvChartAxisTest.TestBottomLabelsSitBelowThePlot;
var
  a: TTyAxisLayoutSpec;
  p: TTyAxisLabelPlacementArray;
begin
  a := BottomAxis(['0', '5']);
  p := TyLayoutAxisLabels(a, TyRectF(0, 0, 200, 150), FM, 96);
  { [Revised in batch 37: 163, tick and margin. Upstream's label stands at
    the margin from the axis line, which clears the tick by itself.] }
  AssertEquals('margin 8 below the plot', 158.0, p[0].Y, Eps);
  AssertTrue('anchored by its top edge', p[0].AnchorV = tavTop);
  AssertTrue('and centred on the tick', p[0].AnchorH = tahCentre);
end;

procedure TAdvChartAxisTest.TestLeftLabelsAreRightAlignedAndMiddleAnchored;
var
  a: TTyAxisLayoutSpec;
  p: TTyAxisLabelPlacementArray;
begin
  a := LeftAxis(['0', '5']);
  p := TyLayoutAxisLabels(a, TyRectF(100, 0, 300, 200), FM, 96);
  { [Revised in batch 37: 87, tick and margin -- see TestBottomLabelsSitBelowThePlot.] }
  AssertEquals('margin 8 left of the plot', 92.0, p[0].X, Eps);
  AssertTrue('right-aligned so the numbers line up', p[0].AnchorH = tahRight);
  AssertTrue('and vertically centred on the tick', p[0].AnchorV = tavMiddle);
end;

procedure TAdvChartAxisTest.TestLeftAxisFractionsRunFromTheBottom;
var
  a: TTyAxisLayoutSpec;
  p: TTyAxisLabelPlacementArray;
begin
  a := LeftAxis(['0', '50', '100']);
  p := TyLayoutAxisLabels(a, TyRectF(0, 20, 200, 220), FM, 96);
  { A vertical axis' fraction 0 is its START, which is the BOTTOM -- the same
    direction the coordinate system's y axis runs. Getting this backwards puts
    every y label upside down while the data draws the right way up. }
  AssertEquals('fraction 0 is at the bottom', 220.0, p[0].Y, Eps);
  AssertEquals('fraction 0.5 is the middle', 120.0, p[1].Y, Eps);
  AssertEquals('fraction 1 is at the top', 20.0, p[2].Y, Eps);
end;

procedure TAdvChartAxisTest.TestRoomyAxisShowsEveryLabel;
var
  a: TTyAxisLayoutSpec;
  p: TTyAxisLabelPlacementArray;
  i: Integer;
begin
  a := BottomAxis(['0', '1', '2', '3']);
  p := TyLayoutAxisLabels(a, TyRectF(0, 0, 800, 200), FM, 96);
  AssertEquals('step is 1', 1, TyAxisLabelStep(a, TyRectF(0, 0, 800, 200), FM, 96));
  for i := 0 to High(p) do
    AssertTrue('label ' + IntToStr(i) + ' shown', p[i].Shown);
end;

procedure TAdvChartAxisTest.TestCrowdedAxisThinsToAUniformStep;
var
  a: TTyAxisLayoutSpec;
  p: TTyAxisLabelPlacementArray;
  i, step: Integer;
begin
  { Ten 4-character labels (40 px each) across 120 px. Everything collides. }
  a := BottomAxis(['1000', '1001', '1002', '1003', '1004',
                   '1005', '1006', '1007', '1008', '1009']);
  step := TyAxisLabelStep(a, TyRectF(0, 0, 120, 100), FM, 96);
  AssertTrue('it had to thin (step=' + IntToStr(step) + ')', step > 1);
  p := TyLayoutAxisLabels(a, TyRectF(0, 0, 120, 100), FM, 96);
  { UNIFORM: exactly the indices divisible by step, no others. A greedy
    keep-if-it-fits would leave gaps of differing size, which on a category axis
    reads as missing data rather than as thinning. }
  for i := 0 to High(p) do
    AssertEquals('label ' + IntToStr(i) + ' shown?', i mod step = 0, p[i].Shown);
end;

procedure TAdvChartAxisTest.TestThinningNeverHidesEverything;
var
  a: TTyAxisLayoutSpec;
  p: TTyAxisLabelPlacementArray;
  i, shown: Integer;
begin
  a := BottomAxis(['1000000000', '1000000001', '1000000002', '1000000003']);
  p := TyLayoutAxisLabels(a, TyRectF(0, 0, 12, 100), FM, 96);   // absurdly narrow
  shown := 0;
  for i := 0 to High(p) do
    if p[i].Shown then Inc(shown);
  { An axis with no labels at all looks broken; one still tells the reader what
    the axis counts in. }
  AssertEquals('exactly one survives', 1, shown);
  AssertTrue('and it is the first', p[0].Shown);
end;

procedure TAdvChartAxisTest.TestLabelStepAgreesWithThePlacements;
var
  a: TTyAxisLayoutSpec;
  p: TTyAxisLabelPlacementArray;
  plot: TTyRectF;
  step, i: Integer;
begin
  { The tick MARKS are drawn from TyAxisLabelStep while the labels come from
    TyLayoutAxisLabels. Two routes to the same number is how marks and labels
    drift apart, so this pins that they agree. }
  a := BottomAxis(['100', '101', '102', '103', '104', '105']);
  plot := TyRectF(0, 0, 150, 100);
  step := TyAxisLabelStep(a, plot, FM, 96);
  p := TyLayoutAxisLabels(a, plot, FM, 96);
  for i := 0 to High(p) do
    AssertEquals('index ' + IntToStr(i), i mod step = 0, p[i].Shown);
end;

function TFakeMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
var
  perLine, i: Integer;
begin
  { A fixed-width fake can wrap for real: the count of characters that fit is
    the width divided by the character width. Returning AText unchanged would
    make every wrapping test pass without wrapping. }
  Result := AText;
  if (AText = '') or (AMaxWidth <= 0) or (FCharW <= 0) then Exit;
  perLine := Trunc(AMaxWidth / FCharW);
  if perLine < 1 then perLine := 1;
  if Length(AText) <= perLine then Exit;
  Result := '';
  i := 1;
  while i <= Length(AText) do
  begin
    if Result <> '' then Result := Result + LineEnding;
    Result := Result + Copy(AText, i, perLine);
    Inc(i, perLine);
  end;
end;

initialization
  RegisterTest(TAdvChartAxisTest);
end.
