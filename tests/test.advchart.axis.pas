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
    { ---- phase 2: shrink ---- }
    procedure TestOuterBoundsNoneDoesNotShrink;
    procedure TestOuterBoundsAutoShrinksTheSideTheAxisIsOn;
    procedure TestTwoAxesOnTheSameSideBothTakeRoom;
    procedure TestOverConstrainedGridCollapsesNotInverts;
    { ---- phase 3: placement and thinning ---- }
    procedure TestBottomLabelAnchorsSitOnTheTicks;
    procedure TestBottomLabelsSitBelowThePlot;
    procedure TestLeftLabelsAreRightAlignedAndMiddleAnchored;
    procedure TestLeftAxisFractionsRunFromTheBottom;
    procedure TestRoomyAxisShowsEveryLabel;
    procedure TestCrowdedAxisThinsToAUniformStep;
    procedure TestThinningNeverHidesEverything;
    procedure TestLabelStepAgreesWithThePlacements;
    { ---- the pass itself ---- }
    procedure TestSecondPassOverTheShrunkPlotKeepsTheSameThickness;
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

procedure TAdvChartAxisTest.TestOuterBoundsNoneDoesNotShrink;
var
  axes: TTyAxisLayoutSpecArray;
  plot: TTyRectF;
begin
  SetLength(axes, 1);
  axes[0] := LeftAxis(['1000000']);
  plot := TySolveGrid(TyRectF(0, 0, 400, 300), axes, FM, 96, obmNone);
  { obmNone is v5's containLabel:false -- the rect given IS the plot band and
    the labels hang outside it. }
  AssertEquals('left', 0.0, plot.Left, Eps);
  AssertEquals('right', 400.0, plot.Right, Eps);
end;

procedure TAdvChartAxisTest.TestOuterBoundsAutoShrinksTheSideTheAxisIsOn;
var
  axes: TTyAxisLayoutSpecArray;
  plot: TTyRectF;
begin
  SetLength(axes, 2);
  axes[0] := LeftAxis(['12345']);        // 50 + 5 + 8 = 63
  axes[1] := BottomAxis(['1']);          // 20 + 5 + 8 = 33
  plot := TySolveGrid(TyRectF(0, 0, 400, 300), axes, FM, 96, obmAuto);
  AssertEquals('left inset by the y axis', 63.0, plot.Left, Eps);
  AssertEquals('bottom inset by the x axis', 300.0 - 33.0, plot.Bottom, Eps);
  AssertEquals('right untouched', 400.0, plot.Right, Eps);
  AssertEquals('top untouched', 0.0, plot.Top, Eps);
end;

procedure TAdvChartAxisTest.TestTwoAxesOnTheSameSideBothTakeRoom;
var
  axes: TTyAxisLayoutSpecArray;
  plot: TTyRectF;
begin
  { A secondary y axis on the same side is the commonest real request. The
    side's inset is the SUM -- taking the max would stack them on top of each
    other. }
  SetLength(axes, 2);
  axes[0] := LeftAxis(['12345']);        // 63
  axes[1] := LeftAxis(['12']);           // 20 + 5 + 8 = 33
  plot := TySolveGrid(TyRectF(0, 0, 400, 300), axes, FM, 96, obmAuto);
  AssertEquals('both axes fit side by side', 96.0, plot.Left, Eps);
end;

procedure TAdvChartAxisTest.TestOverConstrainedGridCollapsesNotInverts;
var
  axes: TTyAxisLayoutSpecArray;
  plot: TTyRectF;
begin
  SetLength(axes, 2);
  axes[0] := LeftAxis(['1234567890123456789012345']);   // 250 + 13
  axes[1] := LeftAxis(['1234567890123456789012345']);
  plot := TySolveGrid(TyRectF(0, 0, 400, 300), axes, FM, 96, obmAuto);
  AssertTrue('still a valid rect', TyRectFIsValid(plot));
  AssertEquals('collapsed to zero width', 0.0, TyRectFWidth(plot), Eps);
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
  AssertEquals('tick 5 + margin 8 below the plot', 163.0, p[0].Y, Eps);
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
  AssertEquals('tick 5 + margin 8 left of the plot', 87.0, p[0].X, Eps);
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

{ ======================== the pass itself ======================== }

procedure TAdvChartAxisTest.TestSecondPassOverTheShrunkPlotKeepsTheSameThickness;
var
  axes: TTyAxisLayoutSpecArray;
  plot: TTyRectF;
  before, after: Double;
begin
  { The pass is estimate -> shrink -> determine, ONE way, no iteration. That is
    only sound because thinning changes how many labels show, not how big each
    one is -- so re-estimating against the shrunk plot must give the same
    thickness. If this ever fails, the single pass has become wrong and the
    unit header's argument needs revisiting, not this test. }
  SetLength(axes, 1);
  axes[0] := LeftAxis(['1', '1000000', '9']);
  before := TyAxisThickness(axes[0], FM, 96, obcAxisLabel);
  plot := TySolveGrid(TyRectF(0, 0, 400, 300), axes, FM, 96, obmAuto);
  after := TyAxisThickness(axes[0], FM, 96, obcAxisLabel);
  AssertEquals('a second estimate changes nothing', before, after, Eps);
  AssertTrue('and the plot really did shrink', plot.Left > 0);
end;

initialization
  RegisterTest(TAdvChartAxisTest);
end.
