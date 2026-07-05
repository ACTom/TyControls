unit test.levelmeter;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.LevelMeter;
type
  TLevelMeterTest = class(TTestCase)
  published
    procedure TestSegmentsLitEdges;
    procedure TestSegmentsLitClamp;
    procedure TestSegmentsLitZeroSegments;
  end;
implementation

procedure TLevelMeterTest.TestSegmentsLitEdges;
begin
  // ceil(frac*segments), clamped 0..segments
  AssertEquals('empty', 0, TyLevelSegmentsLit(0.0, 10));
  AssertEquals('full', 10, TyLevelSegmentsLit(1.0, 10));
  // any positive fraction lights at least the first segment (ceil)
  AssertEquals('just above zero -> 1', 1, TyLevelSegmentsLit(0.01, 10));
  // exact boundary: 0.5*10 = 5, ceil = 5
  AssertEquals('half exact', 5, TyLevelSegmentsLit(0.5, 10));
  // just over a boundary rolls up: 0.51*10 = 5.1 -> 6
  AssertEquals('just over half', 6, TyLevelSegmentsLit(0.51, 10));
  // just under a boundary: 0.49*10 = 4.9 -> 5
  AssertEquals('just under half', 5, TyLevelSegmentsLit(0.49, 10));
end;

procedure TLevelMeterTest.TestSegmentsLitClamp;
begin
  // out-of-range fractions clamp to 0..segments
  AssertEquals('negative frac clamps to 0', 0, TyLevelSegmentsLit(-0.5, 8));
  AssertEquals('over-one frac clamps to all', 8, TyLevelSegmentsLit(1.5, 8));
end;

procedure TLevelMeterTest.TestSegmentsLitZeroSegments;
begin
  // continuous mode (segments <= 0) -> no discrete segments
  AssertEquals('zero segments', 0, TyLevelSegmentsLit(0.7, 0));
  AssertEquals('negative segments', 0, TyLevelSegmentsLit(0.7, -3));
end;

initialization
  RegisterTest(TLevelMeterTest);
end.
