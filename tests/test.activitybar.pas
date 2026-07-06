unit test.activitybar;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, fpcunit, testregistry, tyControls.ActivityBar;
type
  TActivityBarTest = class(TTestCase)
  published
    procedure TestAdvanceWraps;
    procedure TestSpanTravel;
    procedure TestControlAdvance;
  end;
implementation

procedure TActivityBarTest.TestAdvanceWraps;
begin
  AssertEquals('half cycle', 0.5, TyActivityBarAdvance(0, 800, 1600), 1e-6);
  AssertEquals('quarter from 0', 0.25, TyActivityBarAdvance(0, 400, 1600), 1e-6);
  AssertEquals('wraps past 1', 0.1, TyActivityBarAdvance(0.9, 320, 1600), 1e-6);   // 0.9 + 0.2 -> 0.1
  AssertEquals('degenerate period', 0.42, TyActivityBarAdvance(0.42, 100, 0), 1e-6);  // no change
end;

procedure TActivityBarTest.TestSpanTravel;
var s: TPoint;
begin
  // track [0,100], segment 40 wide -> travel distance 140.
  s := TyActivityBarSpan(0.0, 0, 100, 40);
  AssertTrue('phase 0: off the left (empty)', s.Y <= s.X);
  s := TyActivityBarSpan(0.5, 0, 100, 40);   // rawLeft = -40 + 0.5*140 = 30
  AssertEquals('mid: left', 30, s.X);
  AssertEquals('mid: right', 70, s.Y);
  s := TyActivityBarSpan(0.9, 0, 100, 40);   // rawLeft = -40 + 0.9*140 = 86, right clamps to 100
  AssertEquals('late: left', 86, s.X);
  AssertEquals('late: right clamped', 100, s.Y);
  s := TyActivityBarSpan(0.5, 0, 0, 40);     // degenerate track
  AssertTrue('empty track: empty span', s.Y <= s.X);
end;

procedure TActivityBarTest.TestControlAdvance;
var c: TTyActivityBar;
begin
  c := TTyActivityBar.Create(nil);
  try
    AssertEquals('starts at 0', 0.0, c.Phase, 1e-6);
    c.AdvanceAnimation(800);
    AssertEquals('advanced half cycle', 0.5, c.Phase, 1e-6);
    c.Active := False;   // toggling must not crash headless
    c.Active := True;
  finally c.Free; end;
end;

initialization
  RegisterTest(TActivityBarTest);
end.
