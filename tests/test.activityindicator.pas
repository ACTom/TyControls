unit test.activityindicator;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.ActivityIndicator;
type
  TActivityIndicatorTest = class(TTestCase)
  published
    procedure TestAdvanceWraps;
    procedure TestControlAdvance;
  end;
implementation

procedure TActivityIndicatorTest.TestAdvanceWraps;
begin
  AssertEquals('half turn', 180.0, TyActivityAdvance(0, 550, 1100), 1e-6);
  AssertEquals('quarter from 0', 90.0, TyActivityAdvance(0, 275, 1100), 1e-6);
  AssertEquals('wraps past 360', 22.5, TyActivityAdvance(350, 100, 1100), 0.5);  // 350 + ~32.7 -> ~22.7
  AssertEquals('degenerate period', 45.0, TyActivityAdvance(45, 100, 0), 1e-6);  // no change
end;

procedure TActivityIndicatorTest.TestControlAdvance;
var c: TTyActivityIndicator;
begin
  c := TTyActivityIndicator.Create(nil);
  try
    AssertEquals('starts at 0', 0.0, c.Angle, 1e-6);
    c.AdvanceAnimation(550);
    AssertEquals('advanced half turn', 180.0, c.Angle, 1e-6);
    c.Active := False;   // toggling must not crash headless
    c.Active := True;
  finally c.Free; end;
end;

initialization
  RegisterTest(TActivityIndicatorTest);
end.
