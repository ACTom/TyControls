unit test.chart;
{$mode objfpc}{$H+}
{ Headless tests for TTyChart's PURE geometry seam (plan section (1)).
  We never instantiate TTyChart (graphic control -> real-machine paint);
  we only exercise the interface-exported scale/layout math:
    TyChartNiceRange / TyChartValueToY / TyChartBarXRange / TyChartPieSweeps. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry,
     tyControls.Types, tyControls.Chart;
type
  TChartTest = class(TTestCase)
  private
    // True when AStep's mantissa is one of {1,2,2.5,5} x 10^k.
    function NiceStepMantissa(AStep: Double): Boolean;
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
  end;

implementation

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
  // Plan: "刻度数≈ATarget" (~5 ticks). Don't over-pin: assert a sane band.
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

initialization
  RegisterTest(TChartTest);
end.
