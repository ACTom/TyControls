unit test.chart;
{$mode objfpc}{$H+}
{ Headless tests for TTyChart's PURE geometry seam (plan section (1)).
  We never instantiate TTyChart (graphic control -> real-machine paint);
  we only exercise the interface-exported scale/layout/hit-test math:
    TyChartNiceRange / TyChartValueToY / TyChartBarXRange / TyChartPieSweeps
    TyChartLayoutFor / TyChartBarRect / TyChartPointCenter
    TyChartBarHitTest / TyChartLineHitTest / TyChartPieHitTest
    TyChartDonutHoleRadius / TyChartTooltipRect / TyChartDefaultTooltip.

  The hit-test tests are deliberately written as ROUND TRIPS through the paint's own
  geometry (probe the centre of the rect TyChartBarRect drew, the exact point
  TyChartPointCenter drew, the mid-arc of the sweep TyChartPieSweeps drew) rather than
  against hand-computed pixels: what must hold is that the pointer and the pixels agree,
  and hard-coded probe coordinates would only re-state the implementation. }
interface
uses Classes, SysUtils, Math, Types, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Chart;
type
  TChartTest = class(TTestCase)
  private
    // True when AStep's mantissa is one of {1,2,2.5,5} x 10^k.
    function NiceStepMantissa(AStep: Double): Boolean;
    // The 3-series x 4-category fixture the grouped-bar / hit-test cases share.
    function Fixture: TDoubleArrayArray;
  published
    // --- TyChartNiceRange ---
    procedure TestNiceRangeContainsData;
    procedure TestNiceRangeStepIsNice;
    procedure TestNiceRangeTickCountReasonable;
    procedure TestNiceRangeFlatNoDivZero;
    // --- TyChartValueToY ---
    procedure TestValueToYTop;
    procedure TestValueToYBottom;
    procedure TestValueToYMidpoint;
    // --- TyChartBarXRange ---
    procedure TestBarXRangeInBounds;
    procedure TestBarXRangeAscendingNonOverlap;
    procedure TestBarXRangeSingleBar;
    // --- TyChartPieSweeps ---
    procedure TestPieSweepsSumTo360;
    procedure TestPieSweepsProportional;
    procedure TestPieSweepsStartsAreCumulative;
    procedure TestPieSweepsSingleValue;
    procedure TestPieSweepsAllZeroSafe;
    procedure TestPieSweepsNoNaN;
    // --- TyChartLayoutFor ---
    procedure TestLayoutAxesPlotInsideControl;
    procedure TestLayoutAxesReservesAxisGutters;
    procedure TestLayoutRadialHasPieAreaNotPlot;
    procedure TestLayoutLegendOffGivesPlotTheSpace;
    procedure TestLayoutTinyControlDegradesToEmpty;
    procedure TestLayoutTitleEatsFromTheTop;
    // --- TyChartBarRect: the GROUPED (multi-series) bar layout ---
    procedure TestBarRectGroupedSeriesNeverOverlap;
    procedure TestBarRectGroupedStaysInItsCategory;
    procedure TestBarRectSpansBaselineToValue;
    procedure TestBarRectNegativeHangsBelowBaseline;
    procedure TestBarRectZeroValueHasNoArea;
    procedure TestBarRectDegenerateIsEmpty;
    // --- TyChartPointCenter ---
    procedure TestPointCenterIsCategoryMidpoint;
    procedure TestPointCenterYFollowsValue;
    // --- hit-test plumbing ---
    procedure TestNoHitIsInvalid;
    // --- TyChartBarHitTest ---
    procedure TestBarHitTestRoundTripsEveryBar;
    procedure TestBarHitTestEmptyPlotSpaceIsNoHit;
    procedure TestBarHitTestZeroValueIsNotHittable;
    procedure TestBarHitTestNoDataIsNoHit;
    // --- TyChartLineHitTest ---
    procedure TestLineHitTestRoundTripsEveryMarker;
    procedure TestLineHitTestRespectsTolerance;
    procedure TestLineHitTestPicksTheNearerMarker;
    procedure TestLineHitTestTieGoesToLowerSeries;
    procedure TestLineHitTestZeroToleranceGrabsNothing;
    // --- TyChartPieHitTest ---
    procedure TestPieHitTestRoundTripsEverySlice;
    procedure TestPieHitTestOutsideDiscIsNoHit;
    procedure TestPieHitTestDonutHoleIsNoHit;
    procedure TestPieHitTestDonutRingStillHits;
    procedure TestPieHitTestZeroSweepIsNotHittable;
    procedure TestPieHitTestDegenerateRadiusIsNoHit;
    // --- TyChartDonutHoleRadius ---
    procedure TestDonutHoleIsPercentOfOuter;
    procedure TestDonutHoleZeroPercentIsASolidPie;
    procedure TestDonutHoleClampedAtMax;
    procedure TestDonutHoleNegativePercentIsSolid;
    procedure TestDonutHoleDegenerateOuterIsZero;
    // --- TyChartDefaultTooltip ---
    procedure TestTooltipTextHasCategorySeriesAndValue;
    procedure TestTooltipTextOmitsEmptyCategory;
    procedure TestTooltipTextOmitsEmptySeriesName;
    procedure TestTooltipTextAppendsPercent;
    procedure TestTooltipTextOmitsNegativePercent;
    procedure TestTooltipTextUsesDotDecimalSeparator;
    // --- TyChartTooltipRect ---
    procedure TestTooltipRectPrefersUpAndRight;
    procedure TestTooltipRectFlipsLeftAtTheRightEdge;
    procedure TestTooltipRectFlipsDownAtTheTopEdge;
    procedure TestTooltipRectKeepsItsSize;
    procedure TestTooltipRectAlwaysInsideBounds;
    procedure TestTooltipRectOversizedIsPinnedNotHidden;
  end;

implementation

{ ---- shared fixture / helpers ---- }

const
  // The plot band every axes case measures against, and the scale it is read on.
  PLOT_L = 40;  PLOT_T = 10;  PLOT_R = 240;  PLOT_B = 130;
  SCALE_MIN = 0.0;
  SCALE_MAX = 100.0;
  CATS = 4;

function PlotRect: TRect;
begin
  Result := Rect(PLOT_L, PLOT_T, PLOT_R, PLOT_B);
end;

function TChartTest.Fixture: TDoubleArrayArray;
begin
  Result := nil;   // silence FPC's managed-result flow warning; SetLength owns it below
  // 3 series x 4 categories, every value inside (0,100] so every bar has real area.
  SetLength(Result, 3);
  Result[0] := TDoubleArray.Create(20, 40, 60, 80);
  Result[1] := TDoubleArray.Create(50, 10, 90, 30);
  Result[2] := TDoubleArray.Create(70, 60, 20, 45);
end;

function RectsOverlapX(const A, B: TRect): Boolean;
begin
  Result := (A.Left < B.Right) and (B.Left < A.Right);
end;

function TChartTest.NiceStepMantissa(AStep: Double): Boolean;
var
  m: Double;
begin
  Result := False;
  if AStep <= 0 then Exit;
  // normalise to [1,10): mantissa = step / 10^floor(log10(step)).
  m := AStep / Power(10, Floor(Log10(AStep)));
  Result := (Abs(m - 1) < 1e-6) or (Abs(m - 2) < 1e-6) or
            (Abs(m - 2.5) < 1e-6) or (Abs(m - 5) < 1e-6) or
            // guard against float drift landing on 10.0 for the top edge
            (Abs(m - 10) < 1e-6);
end;

{ ---- TyChartNiceRange: expand [min,max] to nice bounds with ~ATarget ticks ---- }

procedure TChartTest.TestNiceRangeContainsData;
var
  nMin, nMax, step: Double;
begin
  // Plan: "niceMin<=min, niceMax>=max". The nice band must never clip data.
  TyChartNiceRange(0, 97, 5, nMin, nMax, step);
  AssertTrue('niceMin <= min', nMin <= 0 + 1e-9);
  AssertTrue('niceMax >= max', nMax >= 97 - 1e-9);
end;

procedure TChartTest.TestNiceRangeStepIsNice;
var
  nMin, nMax, step: Double;
begin
  // Plan: "step in {1,2,2.5,5}*10^k".
  TyChartNiceRange(0, 97, 5, nMin, nMax, step);
  AssertTrue('step > 0', step > 0);
  AssertTrue('step mantissa is nice', NiceStepMantissa(step));

  // A second, differently-scaled range must also produce a nice step.
  TyChartNiceRange(3.2, 8.7, 5, nMin, nMax, step);
  AssertTrue('small-range step mantissa is nice', NiceStepMantissa(step));
end;

procedure TChartTest.TestNiceRangeTickCountReasonable;
var
  nMin, nMax, step: Double;
  ticks: Double;
begin
  // Plan: "tick count ~= ATarget" (~5 ticks). Don't over-pin: assert a sane band.
  TyChartNiceRange(0, 97, 5, nMin, nMax, step);
  ticks := (nMax - nMin) / step;
  AssertTrue('roughly ATarget ticks (>=3)', ticks >= 3 - 1e-9);
  AssertTrue('roughly ATarget ticks (<=8)', ticks <= 8 + 1e-9);
end;

procedure TChartTest.TestNiceRangeFlatNoDivZero;
var
  nMin, nMax, step: Double;
begin
  // Plan: "a flat range (min==max) does not divide by zero".
  // Must return a usable, non-degenerate band with a positive step.
  TyChartNiceRange(5, 5, 5, nMin, nMax, step);
  AssertTrue('flat: step > 0', step > 0);
  AssertTrue('flat: band non-empty', nMax > nMin);
  AssertTrue('flat: contains the value', (nMin <= 5 + 1e-9) and (nMax >= 5 - 1e-9));

  // Zero flat range is the classic div-by-zero trap.
  TyChartNiceRange(0, 0, 5, nMin, nMax, step);
  AssertTrue('zero-flat: step > 0', step > 0);
  AssertTrue('zero-flat: band non-empty', nMax > nMin);
end;

{ ---- TyChartValueToY: linear map, top=niceMax, bottom=niceMin ---- }

const
  TOP    = 10;    // pixel Y of the plot top    (maps to niceMax)
  BOTTOM = 110;   // pixel Y of the plot bottom (maps to niceMin)

procedure TChartTest.TestValueToYTop;
begin
  // Plan: "value=niceMax -> top".
  AssertEquals('niceMax -> top', TOP, TyChartValueToY(100, 0, 100, TOP, BOTTOM));
end;

procedure TChartTest.TestValueToYBottom;
begin
  // Plan: "value=niceMin -> bottom".
  AssertEquals('niceMin -> bottom', BOTTOM, TyChartValueToY(0, 0, 100, TOP, BOTTOM));
end;

procedure TChartTest.TestValueToYMidpoint;
begin
  // Plan: "midpoint -> mid". mid value 50 of [0,100] -> (TOP+BOTTOM) div 2 = 60.
  AssertEquals('midpoint -> mid pixel', (TOP + BOTTOM) div 2,
    TyChartValueToY(50, 0, 100, TOP, BOTTOM));
end;

{ ---- TyChartBarXRange: N bars evenly split across [L,R] ---- }

procedure TChartTest.TestBarXRangeInBounds;
var
  i, x0, x1: Integer;
begin
  // Every bar's [x0,x1] stays inside [L,R].
  for i := 0 to 3 do
  begin
    TyChartBarXRange(i, 4, 0, 100, x0, x1);
    AssertTrue(Format('bar %d x0 >= L', [i]), x0 >= 0);
    AssertTrue(Format('bar %d x1 <= R', [i]), x1 <= 100);
    AssertTrue(Format('bar %d has width', [i]), x1 > x0);
  end;
end;

procedure TChartTest.TestBarXRangeAscendingNonOverlap;
var
  i, x0, x1, prevX1: Integer;
begin
  // Plan: "non-overlapping, ascending x-ranges".
  prevX1 := Low(Integer);
  for i := 0 to 4 do
  begin
    TyChartBarXRange(i, 5, 20, 220, x0, x1);
    AssertTrue(Format('bar %d starts after prev ends', [i]), x0 >= prevX1);
    AssertTrue(Format('bar %d ascending', [i]), x1 > x0);
    prevX1 := x1;
  end;
end;

procedure TChartTest.TestBarXRangeSingleBar;
var
  x0, x1: Integer;
begin
  // Degenerate: a single bar must still yield an in-bounds, positive-width range.
  TyChartBarXRange(0, 1, 0, 100, x0, x1);
  AssertTrue('single bar x0 >= L', x0 >= 0);
  AssertTrue('single bar x1 <= R', x1 <= 100);
  AssertTrue('single bar has width', x1 > x0);
end;

{ ---- TyChartPieSweeps: one TTyChartPieSlice (StartDeg, SweepDeg) per value ---- }

function SumSweeps(const A: TTyChartPieSliceArray): Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(A) do
    Result := Result + A[i].SweepDeg;
end;

procedure TChartTest.TestPieSweepsSumTo360;
var
  sw: TTyChartPieSliceArray;
begin
  // Plan: "sweeps sum to 360 (within 0.01)".
  sw := TyChartPieSweeps([1, 2, 3]);
  AssertEquals('one slice per value', 3, Length(sw));
  AssertEquals('sweeps sum to 360', 360.0, SumSweeps(sw), 0.01);
end;

procedure TChartTest.TestPieSweepsProportional;
var
  sw: TTyChartPieSliceArray;
begin
  // Plan: "proportional to values". Values 1:2:3 -> sweeps 60:120:180.
  sw := TyChartPieSweeps([1, 2, 3]);
  AssertEquals('slice 0 sweep', 60.0, sw[0].SweepDeg, 0.01);
  AssertEquals('slice 1 sweep', 120.0, sw[1].SweepDeg, 0.01);
  AssertEquals('slice 2 sweep', 180.0, sw[2].SweepDeg, 0.01);
end;

procedure TChartTest.TestPieSweepsStartsAreCumulative;
var
  sw: TTyChartPieSliceArray;
begin
  // Each slice's start equals the previous slice's start + its sweep
  // (contiguous slices around the circle). Absolute base is impl-defined,
  // so we only assert the running relationship.
  sw := TyChartPieSweeps([1, 2, 3]);
  AssertEquals('start1 = start0 + sweep0', sw[0].StartDeg + sw[0].SweepDeg, sw[1].StartDeg, 0.01);
  AssertEquals('start2 = start1 + sweep1', sw[1].StartDeg + sw[1].SweepDeg, sw[2].StartDeg, 0.01);
end;

procedure TChartTest.TestPieSweepsSingleValue;
var
  sw: TTyChartPieSliceArray;
begin
  // Plan: "a single value handled". One slice fills the whole circle.
  sw := TyChartPieSweeps([42]);
  AssertEquals('single value -> one slice', 1, Length(sw));
  AssertEquals('single slice sweeps full circle', 360.0, sw[0].SweepDeg, 0.01);
end;

procedure TChartTest.TestPieSweepsAllZeroSafe;
var
  sw: TTyChartPieSliceArray;
begin
  // Plan: "all-zero ... handled (no crash / NaN)". Total is 0 -> proportion
  // undefined; the function must not divide by zero. One (zero) slice per value.
  sw := TyChartPieSweeps([0, 0, 0]);
  AssertEquals('all-zero -> one slice per value', 3, Length(sw));
end;

procedure TChartTest.TestPieSweepsNoNaN;
var
  sw: TTyChartPieSliceArray;
  i: Integer;
begin
  // Neither the all-zero nor the normal case may leak NaN/Inf.
  sw := TyChartPieSweeps([0, 0, 0]);
  for i := 0 to High(sw) do
    AssertFalse(Format('all-zero slice %d is finite', [i]),
      IsNan(sw[i].StartDeg) or IsInfinite(sw[i].StartDeg) or
      IsNan(sw[i].SweepDeg) or IsInfinite(sw[i].SweepDeg));

  sw := TyChartPieSweeps([1, 2, 3]);
  for i := 0 to High(sw) do
    AssertFalse(Format('normal slice %d is finite', [i]),
      IsNan(sw[i].StartDeg) or IsInfinite(sw[i].StartDeg) or
      IsNan(sw[i].SweepDeg) or IsInfinite(sw[i].SweepDeg));
end;

{ ---- TyChartLayoutFor: the bands both the paint and the hit-test measure against ---- }

procedure TChartTest.TestLayoutAxesPlotInsideControl;
var
  lay: TTyChartLayout;
begin
  // An axes chart gets a plot band, and it never leaves the control.
  lay := TyChartLayoutFor(300, 200, False, True, 8, 0, 18, 38, 16);
  AssertTrue('plot has width', lay.Plot.Right > lay.Plot.Left);
  AssertTrue('plot has height', lay.Plot.Bottom > lay.Plot.Top);
  AssertTrue('plot left inside', lay.Plot.Left >= 0);
  AssertTrue('plot top inside', lay.Plot.Top >= 0);
  AssertTrue('plot right inside', lay.Plot.Right <= 300);
  AssertTrue('plot bottom inside', lay.Plot.Bottom <= 200);
  // The legend strip lives BELOW the plot, never over it.
  AssertTrue('legend has width', lay.Legend.Right > lay.Legend.Left);
  AssertTrue('legend sits under the plot', lay.Legend.Top >= lay.Plot.Bottom);
  AssertTrue('legend inside', lay.Legend.Bottom <= 200);
end;

procedure TChartTest.TestLayoutAxesReservesAxisGutters;
var
  lay: TTyChartLayout;
begin
  // The Y gutter (tick labels) and the X band (category labels) are real reservations:
  // the plot must start right of the gutter and stop above the X band + legend.
  lay := TyChartLayoutFor(300, 200, False, True, 8, 0, 18, 38, 16);
  AssertTrue('plot clears the Y gutter', lay.Plot.Left >= 8 + 38);
  AssertTrue('plot clears the X band + legend', lay.Plot.Bottom <= 200 - 8 - 18 - 16);
  // An axes legend starts at the plot's left edge (it labels the series, not the axis).
  AssertEquals('legend aligns with the plot', lay.Plot.Left, lay.Legend.Left);
end;

procedure TChartTest.TestLayoutRadialHasPieAreaNotPlot;
var
  radial, axes: TTyChartLayout;
begin
  // Exactly one of the two bands exists per chart kind -- a caller tests one rect
  // rather than re-deriving which arithmetic applies.
  radial := TyChartLayoutFor(300, 200, True, True, 8, 0, 18, 38, 16);
  AssertTrue('radial: pie area exists', radial.PieArea.Right > radial.PieArea.Left);
  AssertTrue('radial: no plot band', radial.Plot.Right <= radial.Plot.Left);

  axes := TyChartLayoutFor(300, 200, False, True, 8, 0, 18, 38, 16);
  AssertTrue('axes: plot exists', axes.Plot.Right > axes.Plot.Left);
  AssertTrue('axes: no pie area', axes.PieArea.Right <= axes.PieArea.Left);

  // A radial legend spans the whole content width; it is not inset by the (unused) Y gutter.
  AssertEquals('radial legend starts at the margin', 8, radial.Legend.Left);
end;

procedure TChartTest.TestLayoutLegendOffGivesPlotTheSpace;
var
  withLeg, noLeg: TTyChartLayout;
begin
  // Hiding the legend must GIVE the strip back to the data, not just stop drawing on it.
  withLeg := TyChartLayoutFor(300, 200, False, True, 8, 0, 18, 38, 16);
  noLeg := TyChartLayoutFor(300, 200, False, False, 8, 0, 18, 38, 16);
  AssertTrue('no-legend plot is taller', noLeg.Plot.Bottom > withLeg.Plot.Bottom);
  AssertTrue('no-legend has no legend strip', noLeg.Legend.Right <= noLeg.Legend.Left);
end;

procedure TChartTest.TestLayoutTinyControlDegradesToEmpty;
var
  lay: TTyChartLayout;
begin
  // A control smaller than its own margins/gutters must yield EMPTY rects, never inverted
  // ones -- an inverted plot would make every downstream Right>Left guard read backwards.
  lay := TyChartLayoutFor(10, 10, False, True, 8, 0, 18, 38, 16);
  AssertTrue('tiny: plot not inverted', lay.Plot.Right <= lay.Plot.Left);
  AssertTrue('tiny: plot not inverted vertically', lay.Plot.Bottom <= lay.Plot.Top);
  AssertTrue('tiny: legend not inverted', lay.Legend.Right <= lay.Legend.Left);

  lay := TyChartLayoutFor(10, 10, True, True, 8, 0, 18, 38, 16);
  AssertTrue('tiny radial: pie area not inverted', lay.PieArea.Right <= lay.PieArea.Left);

  // Zero / negative sizes must not raise or invert either.
  lay := TyChartLayoutFor(0, 0, False, True, 8, 0, 18, 38, 16);
  AssertTrue('zero: plot empty', lay.Plot.Right <= lay.Plot.Left);
  lay := TyChartLayoutFor(-50, -50, True, True, 8, 0, 18, 38, 16);
  AssertTrue('negative: pie area empty', lay.PieArea.Right <= lay.PieArea.Left);
end;

procedure TChartTest.TestLayoutTitleEatsFromTheTop;
var
  noTitle, titled: TTyChartLayout;
begin
  // The title band comes out of the TOP of the content, so the plot starts lower by
  // exactly the title's height and the bottom edge is untouched.
  noTitle := TyChartLayoutFor(300, 200, False, True, 8, 0, 18, 38, 16);
  titled := TyChartLayoutFor(300, 200, False, True, 8, 20, 18, 38, 16);
  AssertEquals('title pushes the plot down by its height',
    noTitle.Plot.Top + 20, titled.Plot.Top);
  AssertEquals('title does not move the plot bottom', noTitle.Plot.Bottom, titled.Plot.Bottom);
end;

{ ---- TyChartBarRect: this is where "multi-series bars" is either true or not ---- }

procedure TChartTest.TestBarRectGroupedSeriesNeverOverlap;
var
  vals: TDoubleArrayArray;
  cat, sa, sb: Integer;
  ra, rb: TRect;
begin
  // THE grouped-bar claim: within one category, N series get N side-by-side bars that do
  // not overlap. If this failed, a multi-series bar chart would be one series painted over
  // another and the hit-test could never name the right one.
  vals := Fixture;
  for cat := 0 to CATS - 1 do
    for sa := 0 to High(vals) do
    begin
      ra := TyChartBarRect(cat, CATS, sa, Length(vals), PlotRect, vals[sa][cat], SCALE_MIN, SCALE_MAX);
      AssertTrue(Format('cat %d series %d has width', [cat, sa]), ra.Right > ra.Left);
      for sb := sa + 1 to High(vals) do
      begin
        rb := TyChartBarRect(cat, CATS, sb, Length(vals), PlotRect, vals[sb][cat], SCALE_MIN, SCALE_MAX);
        AssertFalse(Format('cat %d: series %d and %d overlap in x', [cat, sa, sb]),
          RectsOverlapX(ra, rb));
      end;
    end;
end;

procedure TChartTest.TestBarRectGroupedStaysInItsCategory;
var
  vals: TDoubleArrayArray;
  cat, seriesIdx: Integer;
  bar, slotA, slotB: TRect;
  cx0, cx1: Integer;
begin
  // Every bar stays inside its own category slot AND inside the plot: a group cannot leak
  // into its neighbour's slot however many series share it.
  vals := Fixture;
  for cat := 0 to CATS - 1 do
  begin
    TyChartBarXRange(cat, CATS, PLOT_L, PLOT_R, cx0, cx1);
    for seriesIdx := 0 to High(vals) do
    begin
      bar := TyChartBarRect(cat, CATS, seriesIdx, Length(vals), PlotRect,
        vals[seriesIdx][cat], SCALE_MIN, SCALE_MAX);
      AssertTrue(Format('cat %d series %d starts in its slot', [cat, seriesIdx]), bar.Left >= cx0);
      AssertTrue(Format('cat %d series %d ends in its slot', [cat, seriesIdx]), bar.Right <= cx1);
      AssertTrue(Format('cat %d series %d inside plot', [cat, seriesIdx]),
        (bar.Left >= PLOT_L) and (bar.Right <= PLOT_R));
      AssertTrue(Format('cat %d series %d vertically inside plot', [cat, seriesIdx]),
        (bar.Top >= PLOT_T) and (bar.Bottom <= PLOT_B));
    end;
  end;
  // And adjacent CATEGORIES do not collide either (the outer split).
  slotA := TyChartBarRect(0, CATS, 2, 3, PlotRect, 70, SCALE_MIN, SCALE_MAX);
  slotB := TyChartBarRect(1, CATS, 0, 3, PlotRect, 40, SCALE_MIN, SCALE_MAX);
  AssertFalse('last bar of cat 0 and first of cat 1 do not overlap', RectsOverlapX(slotA, slotB));
end;

procedure TChartTest.TestBarRectSpansBaselineToValue;
var
  bar: TRect;
  yValue, yZero: Integer;
begin
  // A positive bar runs from the value's pixel down to the zero baseline -- that is what
  // makes its height read as its value.
  bar := TyChartBarRect(0, 1, 0, 1, PlotRect, 50, SCALE_MIN, SCALE_MAX);
  yValue := TyChartValueToY(50, SCALE_MIN, SCALE_MAX, PLOT_T, PLOT_B);
  yZero := TyChartValueToY(0, SCALE_MIN, SCALE_MAX, PLOT_T, PLOT_B);
  AssertEquals('bar top is the value', yValue, bar.Top);
  AssertEquals('bar bottom is the baseline', yZero, bar.Bottom);
  AssertTrue('bar has height', bar.Bottom > bar.Top);
end;

procedure TChartTest.TestBarRectNegativeHangsBelowBaseline;
var
  bar: TRect;
  yZero: Integer;
begin
  // On a scale that includes negatives, a negative bar hangs BELOW the baseline instead of
  // inverting (Top>Bottom), which would make every containment test read backwards.
  bar := TyChartBarRect(0, 1, 0, 1, PlotRect, -40, -100, 100);
  yZero := TyChartValueToY(0, -100, 100, PLOT_T, PLOT_B);
  AssertEquals('negative bar starts at the baseline', yZero, bar.Top);
  AssertTrue('negative bar hangs below it', bar.Bottom > yZero);
  AssertTrue('negative bar is not inverted', bar.Bottom >= bar.Top);
end;

procedure TChartTest.TestBarRectZeroValueHasNoArea;
var
  bar: TRect;
begin
  // A zero value draws nothing, so its rect has no height -- and (see the hit-test case
  // below) nothing can be hovered there. Documented behaviour, not an accident.
  bar := TyChartBarRect(0, 1, 0, 1, PlotRect, 0, SCALE_MIN, SCALE_MAX);
  AssertEquals('zero bar has no height', 0, bar.Bottom - bar.Top);
  AssertTrue('zero bar is not inverted', bar.Bottom >= bar.Top);
end;

procedure TChartTest.TestBarRectDegenerateIsEmpty;
var
  bar: TRect;
begin
  // Out-of-range / empty requests give an empty rect, never an inverted one.
  bar := TyChartBarRect(-1, CATS, 0, 3, PlotRect, 50, SCALE_MIN, SCALE_MAX);
  AssertTrue('negative point index -> empty', (bar.Right <= bar.Left) and (bar.Bottom <= bar.Top));
  bar := TyChartBarRect(9, CATS, 0, 3, PlotRect, 50, SCALE_MIN, SCALE_MAX);
  AssertTrue('point index past the axis -> empty', bar.Right <= bar.Left);
  bar := TyChartBarRect(0, CATS, 5, 3, PlotRect, 50, SCALE_MIN, SCALE_MAX);
  AssertTrue('series index past the group -> empty', bar.Right <= bar.Left);
  bar := TyChartBarRect(0, 0, 0, 0, PlotRect, 50, SCALE_MIN, SCALE_MAX);
  AssertTrue('no categories / no series -> empty', bar.Right <= bar.Left);
end;

{ ---- TyChartPointCenter ---- }

procedure TChartTest.TestPointCenterIsCategoryMidpoint;
var
  ctr: TPoint;
  cx0, cx1: Integer;
begin
  // The marker sits at the centre of its category slot -- which is where the polyline's
  // vertex is, so the line and the markers cannot disagree.
  TyChartBarXRange(2, CATS, PLOT_L, PLOT_R, cx0, cx1);
  ctr := TyChartPointCenter(2, CATS, PlotRect, 50, SCALE_MIN, SCALE_MAX);
  AssertEquals('marker x is the slot midpoint', (cx0 + cx1) div 2, ctr.X);
end;

procedure TChartTest.TestPointCenterYFollowsValue;
var
  low, high_: TPoint;
begin
  // Y is the value on the scale: a bigger value sits HIGHER (smaller Y).
  low := TyChartPointCenter(0, CATS, PlotRect, 10, SCALE_MIN, SCALE_MAX);
  high_ := TyChartPointCenter(0, CATS, PlotRect, 90, SCALE_MIN, SCALE_MAX);
  AssertEquals('low value maps to the scale',
    TyChartValueToY(10, SCALE_MIN, SCALE_MAX, PLOT_T, PLOT_B), low.Y);
  AssertTrue('bigger value is higher on screen', high_.Y < low.Y);
  AssertEquals('same category -> same x', low.X, high_.X);
end;

{ ---- hit-test plumbing ---- }

procedure TChartTest.TestNoHitIsInvalid;
var
  none, some: TTyChartHit;
begin
  none := TyChartNoHit;
  AssertEquals('no-hit series is -1', -1, none.SeriesIndex);
  AssertEquals('no-hit point is -1', -1, none.PointIndex);
  AssertFalse('a no-hit is not valid', TyChartHitValid(none));
  some.SeriesIndex := 0;
  some.PointIndex := 0;
  AssertTrue('an in-range hit is valid', TyChartHitValid(some));
end;

{ ---- TyChartBarHitTest: the inverse of TyChartBarRect ---- }

procedure TChartTest.TestBarHitTestRoundTripsEveryBar;
var
  vals: TDoubleArrayArray;
  cat, seriesIdx, probeX, probeY: Integer;
  bar: TRect;
  hit: TTyChartHit;
begin
  // The round trip that matters: probe the CENTRE of the rect the paint drew for
  // (series, category) and the hit-test must name that exact datum back. Every bar of a
  // 3-series grouped chart -- which is also the proof that the grouping is real.
  vals := Fixture;
  for cat := 0 to CATS - 1 do
    for seriesIdx := 0 to High(vals) do
    begin
      bar := TyChartBarRect(cat, CATS, seriesIdx, Length(vals), PlotRect,
        vals[seriesIdx][cat], SCALE_MIN, SCALE_MAX);
      probeX := (bar.Left + bar.Right) div 2;
      probeY := (bar.Top + bar.Bottom) div 2;
      hit := TyChartBarHitTest(probeX, probeY, vals, CATS, PlotRect, SCALE_MIN, SCALE_MAX);
      AssertTrue(Format('cat %d series %d is hit at all', [cat, seriesIdx]), TyChartHitValid(hit));
      AssertEquals(Format('cat %d series %d -> series', [cat, seriesIdx]), seriesIdx, hit.SeriesIndex);
      AssertEquals(Format('cat %d series %d -> point', [cat, seriesIdx]), cat, hit.PointIndex);
    end;
end;

procedure TChartTest.TestBarHitTestEmptyPlotSpaceIsNoHit;
var
  vals: TDoubleArrayArray;
  hit: TTyChartHit;
begin
  vals := Fixture;
  // Well above every bar (all values <= 90 of 100, so the plot's top strip is empty air).
  hit := TyChartBarHitTest((PLOT_L + PLOT_R) div 2, PLOT_T + 1, vals, CATS, PlotRect,
    SCALE_MIN, SCALE_MAX);
  AssertFalse('empty air above the bars is not a hit', TyChartHitValid(hit));
  // Outside the plot entirely.
  hit := TyChartBarHitTest(PLOT_L - 20, PLOT_B + 20, vals, CATS, PlotRect, SCALE_MIN, SCALE_MAX);
  AssertFalse('outside the plot is not a hit', TyChartHitValid(hit));
end;

procedure TChartTest.TestBarHitTestZeroValueIsNotHittable;
var
  vals: TDoubleArrayArray;
  bar: TRect;
  hit: TTyChartHit;
begin
  // A zero bar draws nothing, so hovering its (zero-height) rect answers nothing. The
  // tooltip must not claim there is a datum where the user can see there is no bar.
  SetLength(vals, 1);
  vals[0] := TDoubleArray.Create(0, 50);
  bar := TyChartBarRect(0, 2, 0, 1, PlotRect, 0, SCALE_MIN, SCALE_MAX);
  hit := TyChartBarHitTest((bar.Left + bar.Right) div 2, bar.Top, vals, 2, PlotRect,
    SCALE_MIN, SCALE_MAX);
  AssertFalse('a zero bar is not hittable', TyChartHitValid(hit));
  // ...while its non-zero neighbour still is, so this is not "the whole chart went dead".
  bar := TyChartBarRect(1, 2, 0, 1, PlotRect, 50, SCALE_MIN, SCALE_MAX);
  hit := TyChartBarHitTest((bar.Left + bar.Right) div 2, (bar.Top + bar.Bottom) div 2,
    vals, 2, PlotRect, SCALE_MIN, SCALE_MAX);
  AssertTrue('the non-zero neighbour is still hittable', TyChartHitValid(hit));
  AssertEquals('and it is the right point', 1, hit.PointIndex);
end;

procedure TChartTest.TestBarHitTestNoDataIsNoHit;
var
  vals: TDoubleArrayArray;
  hit: TTyChartHit;
begin
  // No series at all, and a series with no values: neither may raise or claim a hit.
  vals := nil;
  hit := TyChartBarHitTest(100, 100, vals, CATS, PlotRect, SCALE_MIN, SCALE_MAX);
  AssertFalse('no series -> no hit', TyChartHitValid(hit));
  SetLength(vals, 1);
  vals[0] := nil;
  hit := TyChartBarHitTest(100, 100, vals, CATS, PlotRect, SCALE_MIN, SCALE_MAX);
  AssertFalse('empty series -> no hit', TyChartHitValid(hit));
  // And a zero category count (the degenerate axis) is safe.
  vals := Fixture;
  hit := TyChartBarHitTest(100, 100, vals, 0, PlotRect, SCALE_MIN, SCALE_MAX);
  AssertFalse('no categories -> no hit', TyChartHitValid(hit));
end;

{ ---- TyChartLineHitTest: nearest marker within a grab radius ---- }

procedure TChartTest.TestLineHitTestRoundTripsEveryMarker;
var
  vals: TDoubleArrayArray;
  cat, seriesIdx: Integer;
  ctr: TPoint;
  hit: TTyChartHit;
begin
  // Probe each marker's exact centre: distance 0 always wins, so every drawn marker must
  // round-trip to its own (series, point) even with three series sharing the plot.
  vals := Fixture;
  for cat := 0 to CATS - 1 do
    for seriesIdx := 0 to High(vals) do
    begin
      ctr := TyChartPointCenter(cat, CATS, PlotRect, vals[seriesIdx][cat], SCALE_MIN, SCALE_MAX);
      hit := TyChartLineHitTest(ctr.X, ctr.Y, vals, CATS, PlotRect, SCALE_MIN, SCALE_MAX, 12);
      AssertTrue(Format('cat %d series %d is hit', [cat, seriesIdx]), TyChartHitValid(hit));
      AssertEquals(Format('cat %d series %d -> series', [cat, seriesIdx]), seriesIdx, hit.SeriesIndex);
      AssertEquals(Format('cat %d series %d -> point', [cat, seriesIdx]), cat, hit.PointIndex);
    end;
end;

procedure TChartTest.TestLineHitTestRespectsTolerance;
var
  vals: TDoubleArrayArray;
  ctr: TPoint;
  hit: TTyChartHit;
begin
  // A marker is a few px across, so the pointer gets a grab radius -- but a bounded one.
  SetLength(vals, 1);
  vals[0] := TDoubleArray.Create(50);
  ctr := TyChartPointCenter(0, 1, PlotRect, 50, SCALE_MIN, SCALE_MAX);
  // Just inside the radius.
  hit := TyChartLineHitTest(ctr.X + 4, ctr.Y, vals, 1, PlotRect, SCALE_MIN, SCALE_MAX, 5);
  AssertTrue('inside the tolerance is a hit', TyChartHitValid(hit));
  // Just outside it.
  hit := TyChartLineHitTest(ctr.X + 6, ctr.Y, vals, 1, PlotRect, SCALE_MIN, SCALE_MAX, 5);
  AssertFalse('outside the tolerance is not a hit', TyChartHitValid(hit));
  // Diagonal: the radius must be EUCLIDEAN, not a bounding box. (4,4) is 5.66 away, so a
  // tolerance of 5 must reject it even though both axes are individually within 5.
  hit := TyChartLineHitTest(ctr.X + 4, ctr.Y + 4, vals, 1, PlotRect, SCALE_MIN, SCALE_MAX, 5);
  AssertFalse('the grab radius is a circle, not a square', TyChartHitValid(hit));
end;

procedure TChartTest.TestLineHitTestPicksTheNearerMarker;
var
  vals: TDoubleArrayArray;
  ctrA, ctrB: TPoint;
  hit: TTyChartHit;
begin
  // Two series' markers in the same category, one nearer the pointer: NEAREST wins, not
  // "first found" and not "last drawn".
  SetLength(vals, 2);
  vals[0] := TDoubleArray.Create(20);
  vals[1] := TDoubleArray.Create(80);
  ctrA := TyChartPointCenter(0, 1, PlotRect, 20, SCALE_MIN, SCALE_MAX);
  ctrB := TyChartPointCenter(0, 1, PlotRect, 80, SCALE_MIN, SCALE_MAX);
  // 2px from series 1's marker; series 0's is far up the plot.
  hit := TyChartLineHitTest(ctrB.X, ctrB.Y + 2, vals, 1, PlotRect, SCALE_MIN, SCALE_MAX, 12);
  AssertTrue('near series 1 is a hit', TyChartHitValid(hit));
  AssertEquals('the NEARER marker wins (series 1)', 1, hit.SeriesIndex);
  // ...and symmetrically, so this is not just "the higher index always wins".
  hit := TyChartLineHitTest(ctrA.X, ctrA.Y + 2, vals, 1, PlotRect, SCALE_MIN, SCALE_MAX, 12);
  AssertTrue('near series 0 is a hit', TyChartHitValid(hit));
  AssertEquals('the NEARER marker wins (series 0)', 0, hit.SeriesIndex);
end;

procedure TChartTest.TestLineHitTestTieGoesToLowerSeries;
var
  vals: TDoubleArrayArray;
  ctr: TPoint;
  hit: TTyChartHit;
begin
  // Two series with the SAME value draw markers on top of each other. The answer must be
  // stable (always the lower series), or the tooltip would flicker between them.
  SetLength(vals, 2);
  vals[0] := TDoubleArray.Create(50);
  vals[1] := TDoubleArray.Create(50);
  ctr := TyChartPointCenter(0, 1, PlotRect, 50, SCALE_MIN, SCALE_MAX);
  hit := TyChartLineHitTest(ctr.X, ctr.Y, vals, 1, PlotRect, SCALE_MIN, SCALE_MAX, 12);
  AssertTrue('coincident markers are hit', TyChartHitValid(hit));
  AssertEquals('a tie resolves to the lower series', 0, hit.SeriesIndex);
end;

procedure TChartTest.TestLineHitTestZeroToleranceGrabsNothing;
var
  vals: TDoubleArrayArray;
  ctr: TPoint;
  hit: TTyChartHit;
begin
  // A theme that sets --chart-hit-radius to 0 (or a negative) turns line hovering off
  // rather than grabbing the whole plot or dividing by anything.
  SetLength(vals, 1);
  vals[0] := TDoubleArray.Create(50);
  ctr := TyChartPointCenter(0, 1, PlotRect, 50, SCALE_MIN, SCALE_MAX);
  hit := TyChartLineHitTest(ctr.X, ctr.Y, vals, 1, PlotRect, SCALE_MIN, SCALE_MAX, 0);
  AssertFalse('zero tolerance grabs nothing', TyChartHitValid(hit));
  hit := TyChartLineHitTest(ctr.X, ctr.Y, vals, 1, PlotRect, SCALE_MIN, SCALE_MAX, -5);
  AssertFalse('negative tolerance grabs nothing', TyChartHitValid(hit));
end;

{ ---- TyChartPieHitTest: the inverse of the DrawPie sweep ---- }

procedure TChartTest.TestPieHitTestRoundTripsEverySlice;
const
  CX = 100.0; CY = 100.0; RAD = 50.0;
var
  slices: TTyChartPieSliceArray;
  i, probeX, probeY: Integer;
  mid: Double;
begin
  // Probe each slice's own mid-arc at mid-radius -- the point DrawPie would put its own
  // percentage label on. Each must answer its own slice, which is what proves the -90
  // offset and the screen-space (Y down) angles are undone correctly.
  slices := TyChartPieSweeps([1, 2, 3, 4]);
  for i := 0 to High(slices) do
  begin
    mid := DegToRad(slices[i].StartDeg + slices[i].SweepDeg / 2 - 90);
    probeX := Round(CX + Cos(mid) * RAD * 0.5);
    probeY := Round(CY + Sin(mid) * RAD * 0.5);
    AssertEquals(Format('slice %d round-trips', [i]), i,
      TyChartPieHitTest(probeX, probeY, CX, CY, RAD, 0, slices));
  end;
  // Slice 0 starts at 12 o'clock: a probe straight up from the centre is slice 0.
  AssertEquals('slice 0 starts at the top', 0,
    TyChartPieHitTest(Round(CX), Round(CY - RAD * 0.5), CX, CY, RAD, 0, slices));
end;

procedure TChartTest.TestPieHitTestOutsideDiscIsNoHit;
const
  CX = 100.0; CY = 100.0; RAD = 50.0;
var
  slices: TTyChartPieSliceArray;
begin
  slices := TyChartPieSweeps([1, 2, 3]);
  AssertEquals('outside the radius is no hit', -1,
    TyChartPieHitTest(Round(CX + RAD + 5), Round(CY), CX, CY, RAD, 0, slices));
  AssertEquals('the bounding-box corner is no hit', -1,
    TyChartPieHitTest(Round(CX + RAD), Round(CY + RAD), CX, CY, RAD, 0, slices));
  // Just inside the rim still is, so the boundary is not off by a wide margin.
  AssertTrue('just inside the rim is a hit',
    TyChartPieHitTest(Round(CX + RAD - 3), Round(CY), CX, CY, RAD, 0, slices) >= 0);
end;

procedure TChartTest.TestPieHitTestDonutHoleIsNoHit;
const
  CX = 100.0; CY = 100.0; RAD = 50.0; HOLE = 25.0;
var
  slices: TTyChartPieSliceArray;
begin
  // The hole is not the chart: nothing is drawn there, so nothing may be reported there.
  slices := TyChartPieSweeps([1, 2, 3]);
  AssertEquals('the donut centre is no hit', -1,
    TyChartPieHitTest(Round(CX), Round(CY), CX, CY, RAD, HOLE, slices));
  AssertEquals('inside the hole is no hit', -1,
    TyChartPieHitTest(Round(CX + 10), Round(CY), CX, CY, RAD, HOLE, slices));
  // The SAME point on a solid pie (hole 0) IS a hit -- so this is the hole talking, not
  // a broken angle.
  AssertTrue('the same point on a pie is a hit',
    TyChartPieHitTest(Round(CX + 10), Round(CY), CX, CY, RAD, 0, slices) >= 0);
end;

procedure TChartTest.TestPieHitTestDonutRingStillHits;
const
  CX = 100.0; CY = 100.0; RAD = 50.0; HOLE = 25.0;
var
  slices: TTyChartPieSliceArray;
  i, probeX, probeY: Integer;
  mid, ringR: Double;
begin
  // ...and the ring itself round-trips exactly like a pie's wedge does.
  slices := TyChartPieSweeps([1, 2, 3]);
  ringR := HOLE + (RAD - HOLE) / 2;
  for i := 0 to High(slices) do
  begin
    mid := DegToRad(slices[i].StartDeg + slices[i].SweepDeg / 2 - 90);
    probeX := Round(CX + Cos(mid) * ringR);
    probeY := Round(CY + Sin(mid) * ringR);
    AssertEquals(Format('donut slice %d round-trips', [i]), i,
      TyChartPieHitTest(probeX, probeY, CX, CY, RAD, HOLE, slices));
  end;
end;

procedure TChartTest.TestPieHitTestZeroSweepIsNotHittable;
const
  CX = 100.0; CY = 100.0; RAD = 50.0;
var
  slices: TTyChartPieSliceArray;
  i, hitCount: Integer;
begin
  // All-zero data -> every sweep is 0 -> nothing is drawn -> no probe anywhere in the disc
  // may name a slice.
  slices := TyChartPieSweeps([0, 0, 0]);
  hitCount := 0;
  for i := 0 to 359 do
    if TyChartPieHitTest(Round(CX + Cos(DegToRad(i)) * RAD * 0.5),
                         Round(CY + Sin(DegToRad(i)) * RAD * 0.5), CX, CY, RAD, 0, slices) >= 0 then
      Inc(hitCount);
  AssertEquals('an all-zero pie is not hittable anywhere', 0, hitCount);
  // The centre too.
  AssertEquals('all-zero centre is no hit', -1,
    TyChartPieHitTest(Round(CX), Round(CY), CX, CY, RAD, 0, slices));
end;

procedure TChartTest.TestPieHitTestDegenerateRadiusIsNoHit;
var
  slices: TTyChartPieSliceArray;
begin
  // A disc with no radius (a chart too small to draw one) must answer -1, not divide.
  slices := TyChartPieSweeps([1, 2, 3]);
  AssertEquals('zero radius -> no hit', -1, TyChartPieHitTest(100, 100, 100, 100, 0, 0, slices));
  AssertEquals('negative radius -> no hit', -1, TyChartPieHitTest(100, 100, 100, 100, -5, 0, slices));
  // No slices at all.
  slices := nil;
  AssertEquals('no slices -> no hit', -1, TyChartPieHitTest(100, 100, 100, 100, 50, 0, slices));
end;

{ ---- TyChartDonutHoleRadius ---- }

procedure TChartTest.TestDonutHoleIsPercentOfOuter;
begin
  // The token is a PERCENT of the outer radius (the disc is sized by the control, so an
  // absolute px hole would not survive a resize).
  AssertEquals('55% of 100', 55.0, TyChartDonutHoleRadius(100, 55), 0.001);
  AssertEquals('55% of 40', 22.0, TyChartDonutHoleRadius(40, 55), 0.001);
  AssertEquals('the default is Ant''s ring', 55, TyChartDonutHolePercent);
end;

procedure TChartTest.TestDonutHoleZeroPercentIsASolidPie;
begin
  // 0% is the pie: the donut and the pie really are one geometry.
  AssertEquals('0% -> no hole', 0.0, TyChartDonutHoleRadius(100, 0), 0.001);
end;

procedure TChartTest.TestDonutHoleClampedAtMax;
begin
  // A skin cannot erase the chart: past the cap the ring stops thinning.
  AssertEquals('100% is clamped to the max', TyChartDonutHoleMaxPercent / 100 * 100,
    TyChartDonutHoleRadius(100, 100), 0.001);
  AssertEquals('a wild percent is clamped too', TyChartDonutHoleMaxPercent / 100 * 100,
    TyChartDonutHoleRadius(100, 5000), 0.001);
  AssertTrue('the clamp leaves a real ring', TyChartDonutHoleRadius(100, 100) < 100);
end;

procedure TChartTest.TestDonutHoleNegativePercentIsSolid;
begin
  // A negative hole would be a negative radius -> an inverted ring. Clamp to solid.
  AssertEquals('negative percent -> no hole', 0.0, TyChartDonutHoleRadius(100, -20), 0.001);
end;

procedure TChartTest.TestDonutHoleDegenerateOuterIsZero;
begin
  // No disc, no hole -- and no negative radius handed to the hit-test.
  AssertEquals('zero outer -> no hole', 0.0, TyChartDonutHoleRadius(0, 55), 0.001);
  AssertEquals('negative outer -> no hole', 0.0, TyChartDonutHoleRadius(-30, 55), 0.001);
end;

{ ---- TyChartDefaultTooltip ---- }

procedure TChartTest.TestTooltipTextHasCategorySeriesAndValue;
var
  txt: string;
begin
  // The whole point of the feature: the box says WHICH category, WHICH series, WHAT value.
  txt := TyChartDefaultTooltip('Q3', 'East', 42, -1);
  AssertTrue('mentions the category', Pos('Q3', txt) > 0);
  AssertTrue('mentions the series', Pos('East', txt) > 0);
  AssertTrue('mentions the value', Pos('42', txt) > 0);
  // Two lines: the category heads the box, the datum sits under it.
  AssertEquals('category on its own line', 'Q3' + #10 + 'East: 42', txt);
end;

procedure TChartTest.TestTooltipTextOmitsEmptyCategory;
var
  txt: string;
begin
  // No category -> no blank first line (which would draw as an empty band in the box).
  txt := TyChartDefaultTooltip('', 'East', 42, -1);
  AssertEquals('no leading blank line', 'East: 42', txt);
  AssertEquals('and no line break at all', 0, Pos(#10, txt));
end;

procedure TChartTest.TestTooltipTextOmitsEmptySeriesName;
var
  txt: string;
begin
  // An unnamed series (the pie case) drops the prefix rather than printing ': 42'.
  txt := TyChartDefaultTooltip('Q3', '', 42, -1);
  AssertEquals('bare value under the category', 'Q3' + #10 + '42', txt);
  AssertEquals('no orphan colon', 0, Pos(':', txt));
end;

procedure TChartTest.TestTooltipTextAppendsPercent;
var
  txt: string;
begin
  // A pie slice quotes its share; 0% is a real share, not "no share".
  txt := TyChartDefaultTooltip('Q3', '', 30, 25);
  AssertEquals('share appended', 'Q3' + #10 + '30 (25%)', txt);
  txt := TyChartDefaultTooltip('Q3', '', 0, 0);
  AssertTrue('zero percent still prints', Pos('(0%)', txt) > 0);
end;

procedure TChartTest.TestTooltipTextOmitsNegativePercent;
var
  txt: string;
begin
  // An axes chart has no share to quote and passes -1: no '(...)' may appear.
  txt := TyChartDefaultTooltip('Q3', 'East', 42, -1);
  AssertEquals('no percent for an axes chart', 0, Pos('%', txt));
  AssertEquals('no empty parens either', 0, Pos('(', txt));
end;

procedure TChartTest.TestTooltipTextUsesDotDecimalSeparator;
var
  txt: string;
  saved: TFormatSettings;
begin
  // The tooltip must match the AXIS labels, which format '0.###' with a '.' -- and the axis
  // does not follow the locale. Force a comma locale and prove the tooltip ignores it too;
  // otherwise a de/fr user reads '3,5' off a tooltip over an axis labelled '3.5'.
  saved := DefaultFormatSettings;
  try
    DefaultFormatSettings.DecimalSeparator := ',';
    DefaultFormatSettings.ThousandSeparator := '.';
    txt := TyChartDefaultTooltip('Q3', 'East', 3.5, -1);
    AssertEquals('dot decimals regardless of locale', 'Q3' + #10 + 'East: 3.5', txt);
    txt := TyChartDefaultTooltip('', '', 1234.5, -1);
    AssertEquals('no thousands grouping', '1234.5', txt);
  finally
    DefaultFormatSettings := saved;
  end;
end;

{ ---- TyChartTooltipRect ---- }

procedure TChartTest.TestTooltipRectPrefersUpAndRight;
var
  box: TRect;
begin
  // With room on every side the box goes up-right of the datum, a gap away -- never over
  // the datum the user is reading and never under the cursor.
  box := TyChartTooltipRect(100, 100, 60, 30, 10, Rect(0, 0, 300, 200));
  AssertEquals('gap to the right of the anchor', 110, box.Left);
  AssertEquals('a box-height + gap above it', 60, box.Top);
  AssertTrue('the anchor is not covered', (box.Left > 100) and (box.Bottom < 100));
end;

procedure TChartTest.TestTooltipRectFlipsLeftAtTheRightEdge;
var
  box: TRect;
begin
  // Near the right edge the box flips to the datum's LEFT rather than being shoved back
  // over it. Flip, then clamp -- the flipped box must still clear the anchor.
  box := TyChartTooltipRect(290, 100, 60, 30, 10, Rect(0, 0, 300, 200));
  AssertTrue('inside the right edge', box.Right <= 300);
  AssertTrue('flipped to the left of the anchor', box.Right <= 290);
  AssertEquals('a gap short of the anchor', 280, box.Right);
end;

procedure TChartTest.TestTooltipRectFlipsDownAtTheTopEdge;
var
  box: TRect;
begin
  // Near the top the box flips BELOW the datum instead of being clamped on top of it.
  box := TyChartTooltipRect(100, 5, 60, 30, 10, Rect(0, 0, 300, 200));
  AssertTrue('inside the top edge', box.Top >= 0);
  AssertTrue('flipped below the anchor', box.Top >= 5);
  AssertEquals('a gap under the anchor', 15, box.Top);
end;

procedure TChartTest.TestTooltipRectKeepsItsSize;
var
  box: TRect;
begin
  // Placement never resizes the box: it was measured to fit its text, so a shrunk box
  // would clip the words it exists to show.
  box := TyChartTooltipRect(100, 100, 60, 30, 10, Rect(0, 0, 300, 200));
  AssertEquals('width preserved', 60, box.Right - box.Left);
  AssertEquals('height preserved', 30, box.Bottom - box.Top);
  box := TyChartTooltipRect(299, 1, 60, 30, 10, Rect(0, 0, 300, 200));
  AssertEquals('width preserved in a corner', 60, box.Right - box.Left);
  AssertEquals('height preserved in a corner', 30, box.Bottom - box.Top);
end;

procedure TChartTest.TestTooltipRectAlwaysInsideBounds;
var
  box, bounds: TRect;
  ax, ay: Integer;
begin
  // Sweep every anchor over the chart (including well outside it) -- the box must never
  // leave the control, whichever corner the datum is in.
  bounds := Rect(0, 0, 300, 200);
  ax := -40;
  while ax <= 340 do
  begin
    ay := -40;
    while ay <= 240 do
    begin
      box := TyChartTooltipRect(ax, ay, 60, 30, 10, bounds);
      AssertTrue(Format('anchor (%d,%d): left inside', [ax, ay]), box.Left >= bounds.Left);
      AssertTrue(Format('anchor (%d,%d): top inside', [ax, ay]), box.Top >= bounds.Top);
      AssertTrue(Format('anchor (%d,%d): right inside', [ax, ay]), box.Right <= bounds.Right);
      AssertTrue(Format('anchor (%d,%d): bottom inside', [ax, ay]), box.Bottom <= bounds.Bottom);
      AssertTrue(Format('anchor (%d,%d): not inverted', [ax, ay]),
        (box.Right >= box.Left) and (box.Bottom >= box.Top));
      Inc(ay, 20);
    end;
    Inc(ax, 20);
  end;
end;

procedure TChartTest.TestTooltipRectOversizedIsPinnedNotHidden;
var
  box: TRect;
begin
  // A box bigger than the chart is pinned to the top-left and clipped, NOT pushed off
  // screen: a clipped tooltip still says more than none.
  box := TyChartTooltipRect(50, 50, 400, 300, 10, Rect(0, 0, 300, 200));
  AssertEquals('pinned to the left edge', 0, box.Left);
  AssertEquals('pinned to the top edge', 0, box.Top);
  AssertTrue('still not inverted', (box.Right > box.Left) and (box.Bottom > box.Top));
end;

type
  { Image export (QQ-group request). Instantiates the control -- the "never instantiate"
    note in this file's header predates the library-wide headless RenderTo idiom; export
    is exactly that idiom behind a public method, so it is tested the same way. }
  TChartExportTest = class(TTestCase)
  private
    FChart: TTyChart;
    FBase: string;
    function FileNameFor(const AExt: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSaveToFilePngRoundTrips;
    procedure TestSaveToFileOtherFormatsWrite;
    procedure TestSaveToStreamWritesTheFormat;
    procedure TestSaveToFileExplicitFormatWinsOverExtension;
  end;

procedure TChartExportTest.SetUp;
begin
  FBase := GetTempDir(False) + 'ty_chartexport_' + IntToStr(GetProcessID);
  FChart := TTyChart.Create(nil);
  FChart.Font.PixelsPerInch := 96;
  FChart.SetBounds(0, 0, 320, 200);
  with FChart.Series.Add do Values := '10,20,30,25';
  with FChart.Series.Add do Values := '5,15,10,20';
end;

procedure TChartExportTest.TearDown;
begin
  FChart.Free;
  DeleteFile(FileNameFor('.png'));
  DeleteFile(FileNameFor('.bmp'));
  DeleteFile(FileNameFor('.jpg'));
  DeleteFile(FileNameFor('.tif'));
  DeleteFile(FileNameFor('.dat'));
end;

function TChartExportTest.FileNameFor(const AExt: string): string;
begin
  Result := FBase + AExt;
end;

procedure TChartExportTest.TestSaveToFilePngRoundTrips;
var
  fs: TFileStream;
  Magic: array[0..7] of Byte;
  Bmp: TBGRABitmap;
  Corner, Px: TBGRAPixel;
  x, y: Integer;
  Drawn: Boolean;
begin
  FChart.SaveToFile(FileNameFor('.png'));
  AssertTrue('the PNG file exists', FileExists(FileNameFor('.png')));

  fs := TFileStream.Create(FileNameFor('.png'), fmOpenRead);
  try
    AssertEquals('read the signature', 8, fs.Read(Magic{%H-}, 8));
    AssertTrue('PNG signature', (Magic[0] = $89) and (Magic[1] = Ord('P'))
      and (Magic[2] = Ord('N')) and (Magic[3] = Ord('G')));
  finally
    fs.Free;
  end;

  Bmp := TBGRABitmap.Create(FileNameFor('.png'));
  try
    AssertEquals('exported width is the control width', 320, Bmp.Width);
    AssertEquals('exported height is the control height', 200, Bmp.Height);
    // The chart is an opaque surface: a transparent export is the GDI->BGRA
    // zero-alpha trap, not a valid picture.
    AssertEquals('the export is opaque (alpha trap guard)', 255,
      Bmp.GetPixel(160, 100).alpha);
    // And it actually drew something: some pixel must differ from the corner.
    Corner := Bmp.GetPixel(2, 2);
    Drawn := False;
    for y := 0 to Bmp.Height - 1 do
    begin
      for x := 0 to Bmp.Width - 1 do
      begin
        Px := Bmp.GetPixel(x, y);
        if (Px.red <> Corner.red) or (Px.green <> Corner.green) or (Px.blue <> Corner.blue) then
        begin
          Drawn := True;
          Break;
        end;
      end;
      if Drawn then Break;
    end;
    AssertTrue('the chart drew ink, not a flat sheet', Drawn);
  finally
    Bmp.Free;
  end;
end;

procedure TChartExportTest.TestSaveToFileOtherFormatsWrite;

  procedure CheckWrites(const AExt: string);
  var
    fn: string;
  begin
    fn := FileNameFor(AExt);
    FChart.SaveToFile(fn);
    AssertTrue(AExt + ' file exists', FileExists(fn));
    with TFileStream.Create(fn, fmOpenRead) do
    try
      AssertTrue(AExt + ' file is not empty', Size > 0);
    finally
      Free;
    end;
  end;

begin
  CheckWrites('.bmp');
  CheckWrites('.jpg');
  CheckWrites('.tif');
end;

procedure TChartExportTest.TestSaveToStreamWritesTheFormat;
// The stream form is the export core (a report writer embeds the picture without ever
// touching the disk); SaveToFile is a wrapper over it. The format is BGRABitmap's own
// TBGRAImageFormat, so every registered writer is reachable.
var
  ms: TMemoryStream;
  Magic: array[0..7] of Byte;
  Bmp: TBGRABitmap;
begin
  ms := TMemoryStream.Create;
  try
    FChart.SaveToStream(ms, ifPng);
    AssertTrue('the stream received bytes', ms.Size > 8);
    ms.Position := 0;
    AssertEquals('read the signature', 8, ms.Read(Magic{%H-}, 8));
    AssertTrue('PNG signature in the stream', (Magic[0] = $89) and (Magic[1] = Ord('P')));
    ms.Position := 0;
    Bmp := TBGRABitmap.Create;
    try
      Bmp.LoadFromStream(ms);
      AssertEquals('stream export width', 320, Bmp.Width);
      AssertEquals('stream export height', 200, Bmp.Height);
    finally
      Bmp.Free;
    end;
  finally
    ms.Free;
  end;

  ms := TMemoryStream.Create;
  try
    FChart.SaveToStream(ms, ifJpeg, 160, 100);
    AssertTrue('the sized overload wrote bytes', ms.Size > 2);
    ms.Position := 0;
    AssertEquals('read the JPEG magic', 2, ms.Read(Magic, 2));
    AssertTrue('JPEG signature in the stream', (Magic[0] = $FF) and (Magic[1] = $D8));
  finally
    ms.Free;
  end;
end;

procedure TChartExportTest.TestSaveToFileExplicitFormatWinsOverExtension;
// An explicit format must not be second-guessed by the file name: exporting to a
// temp name or an extensionless path is exactly when the caller says the format.
var
  fs: TFileStream;
  Magic: array[0..7] of Byte;
begin
  FChart.SaveToFile(FileNameFor('.dat'), ifPng);
  AssertTrue('the .dat file exists', FileExists(FileNameFor('.dat')));
  fs := TFileStream.Create(FileNameFor('.dat'), fmOpenRead);
  try
    AssertEquals('read the signature', 8, fs.Read(Magic{%H-}, 8));
    AssertTrue('PNG bytes despite the .dat extension',
      (Magic[0] = $89) and (Magic[1] = Ord('P')));
  finally
    fs.Free;
  end;
end;

initialization
  RegisterTest(TChartTest);
  RegisterTest(TChartExportTest);
end.
