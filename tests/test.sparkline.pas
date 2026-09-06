unit test.sparkline;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, tyControls.Sparkline;
type
  TSparklineTest = class(TTestCase)
  published
    procedure TestMinMapsToBottom;
    procedure TestMaxMapsToTop;
    procedure TestMidpoint;
    procedure TestClampsOutOfRange;
    procedure TestDegenerateRangeCentres;
    procedure TestBaselineIsZeroLineWhenRangeSpansZero;
    procedure TestBaselineSitsOnBottomForLargePositiveMin;
  end;
implementation

const
  TOP = 10.0;
  H   = 100.0;   // band spans y = 10 (top) .. 110 (bottom)

procedure TSparklineTest.TestMinMapsToBottom;
begin
  // min value -> the bottom of the band (inverted scale).
  AssertEquals('min -> bottom', TOP + H, TySparklineY(0, 0, 100, TOP, H), 1e-9);
end;

procedure TSparklineTest.TestMaxMapsToTop;
begin
  // max value -> the top of the band.
  AssertEquals('max -> top', TOP, TySparklineY(100, 0, 100, TOP, H), 1e-9);
end;

procedure TSparklineTest.TestMidpoint;
begin
  // mid value -> the vertical centre of the band.
  AssertEquals('mid -> centre', TOP + H / 2, TySparklineY(50, 0, 100, TOP, H), 1e-9);
end;

procedure TSparklineTest.TestClampsOutOfRange;
begin
  // Values outside [min,max] clamp to the band edges, never overshoot.
  AssertEquals('below min clamps to bottom', TOP + H, TySparklineY(-20, 0, 100, TOP, H), 1e-9);
  AssertEquals('above max clamps to top', TOP, TySparklineY(150, 0, 100, TOP, H), 1e-9);
end;

procedure TSparklineTest.TestDegenerateRangeCentres;
begin
  // max <= min -> no range -> everything maps to the vertical centre (no div-by-zero).
  AssertEquals('flat range -> centre', TOP + H / 2, TySparklineY(42, 5, 5, TOP, H), 1e-9);
  AssertEquals('inverted range -> centre', TOP + H / 2, TySparklineY(0, 10, 3, TOP, H), 1e-9);
end;

procedure TSparklineTest.TestBaselineIsZeroLineWhenRangeSpansZero;
begin
  // A range that spans zero puts the baseline on the zero line, not on the bottom.
  AssertEquals('zero line', TOP + H * 0.75, TySparklineBaselineY(-25, 75, TOP, H), 1e-9);
end;

procedure TSparklineTest.TestBaselineSitsOnBottomForLargePositiveMin;
const
  BIG = 100000005.0;   // not a Single value: Single rounds it UP to 100000008
begin
  // A positive min keeps the baseline on the bottom of the band whatever its magnitude.
  // Math.Max(0, AMin) resolves to the Single overload and floated it 30px up the band.
  AssertEquals('bottom', TOP + H, TySparklineBaselineY(BIG, BIG + 10, TOP, H), 1e-9);
end;

initialization
  RegisterTest(TSparklineTest);
end.
