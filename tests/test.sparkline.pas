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

initialization
  RegisterTest(TSparklineTest);
end.
