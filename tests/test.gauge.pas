unit test.gauge;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, fpcunit, testregistry, tyControls.Gauge;
type
  TGaugeTest = class(TTestCase)
  published
    procedure TestFraction;
    procedure TestSweepEnd;
    procedure TestLinearFill;
  end;
implementation

procedure TGaugeTest.TestFraction;
begin
  AssertEquals('mid', 0.5, TyGaugeFraction(50, 0, 100), 1e-9);
  AssertEquals('clamp low', 0.0, TyGaugeFraction(-10, 0, 100), 1e-9);
  AssertEquals('clamp high', 1.0, TyGaugeFraction(999, 0, 100), 1e-9);
  AssertEquals('degenerate max<=min', 0.0, TyGaugeFraction(5, 3, 3), 1e-9);
  AssertEquals('quarter', 0.25, TyGaugeFraction(25, 0, 100), 1e-9);
  AssertEquals('negative range', 0.5, TyGaugeFraction(0, -50, 50), 1e-9);
end;

procedure TGaugeTest.TestSweepEnd;
begin
  AssertEquals('half sweep', 270.0, TyGaugeSweepEnd(135, 270, 0.5), 1e-9);
  AssertEquals('zero sweep', 135.0, TyGaugeSweepEnd(135, 270, 0), 1e-9);
  AssertEquals('full sweep', 405.0, TyGaugeSweepEnd(135, 270, 1), 1e-9);
end;

procedure TGaugeTest.TestLinearFill;
var t, f: TRect;
begin
  t := Rect(0, 0, 100, 20);
  f := TyGaugeLinearFill(t, 0.5, False);            // horizontal, left-anchored
  AssertEquals('h left', 0, f.Left);
  AssertEquals('h right = half', 50, f.Right);
  AssertEquals('h full height', 20, f.Bottom);
  AssertEquals('h empty', 0, TyGaugeLinearFill(t, 0, False).Right);
  AssertEquals('h full', 100, TyGaugeLinearFill(t, 1, False).Right);
  AssertEquals('h clamp over', 100, TyGaugeLinearFill(t, 5, False).Right);

  t := Rect(0, 0, 20, 100);
  f := TyGaugeLinearFill(t, 0.5, True);             // vertical, bottom-anchored
  AssertEquals('v top = half down', 50, f.Top);
  AssertEquals('v bottom pinned', 100, f.Bottom);
  AssertEquals('v full reaches top', 0, TyGaugeLinearFill(t, 1, True).Top);
end;

initialization
  RegisterTest(TGaugeTest);
end.
