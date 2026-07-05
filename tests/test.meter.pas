unit test.meter;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.Meter;
type
  TMeterTest = class(TTestCase)
  published
    procedure TestTickAngle;
  end;
implementation

procedure TMeterTest.TestTickAngle;
begin
  // 5 ticks across 150..390 (start 150, sweep 240)
  AssertEquals('first tick = start', 150.0, TyMeterTickAngle(0, 5, 150, 240), 1e-9);
  AssertEquals('last tick = start+sweep', 390.0, TyMeterTickAngle(4, 5, 150, 240), 1e-9);
  AssertEquals('middle tick', 270.0, TyMeterTickAngle(2, 5, 150, 240), 1e-9);
  AssertEquals('quarter tick', 210.0, TyMeterTickAngle(1, 5, 150, 240), 1e-9);
  // degenerate: 0 or 1 tick collapses to the start angle (no div by zero)
  AssertEquals('single tick', 150.0, TyMeterTickAngle(0, 1, 150, 240), 1e-9);
end;

initialization
  RegisterTest(TMeterTest);
end.
