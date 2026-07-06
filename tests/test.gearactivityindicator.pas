unit test.gearactivityindicator;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.GearActivityIndicator;
type
  TGearActivityIndicatorTest = class(TTestCase)
  published
    procedure TestControlAdvance;
    procedure TestTeethClamp;
  end;
implementation

procedure TGearActivityIndicatorTest.TestControlAdvance;
var c: TTyGearActivityIndicator;
begin
  c := TTyGearActivityIndicator.Create(nil);
  try
    AssertEquals('starts at 0', 0.0, c.Angle, 1e-6);
    c.AdvanceAnimation(700);   // half of the 1400ms period
    AssertEquals('advanced half turn', 180.0, c.Angle, 1e-6);
    c.Active := False;   // toggling must not crash headless
    c.Active := True;
  finally c.Free; end;
end;

procedure TGearActivityIndicatorTest.TestTeethClamp;
var c: TTyGearActivityIndicator;
begin
  c := TTyGearActivityIndicator.Create(nil);
  try
    AssertEquals('default teeth', 9, c.Teeth);
    c.Teeth := 1;    AssertEquals('clamped low', 3, c.Teeth);
    c.Teeth := 99;   AssertEquals('clamped high', 24, c.Teeth);
  finally c.Free; end;
end;

initialization
  RegisterTest(TGearActivityIndicatorTest);
end.
