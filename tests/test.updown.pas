unit test.updown;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, fpcunit, testregistry, tyControls.UpDown;
type
  TUpDownTest = class(TTestCase)
  published
    procedure TestButtonRect;
    procedure TestHit;
    procedure TestClamp;
    procedure TestPositionClamps;
  end;
implementation

procedure TUpDownTest.TestButtonRect;
var r: TRect;
begin
  // Vertical 20x34: up = top half, down = bottom half.
  r := TyUpDownButtonRect(True, 20, 34, True);
  AssertEquals('v up top', 0, r.Top);   AssertEquals('v up bottom', 17, r.Bottom);
  r := TyUpDownButtonRect(False, 20, 34, True);
  AssertEquals('v down top', 17, r.Top); AssertEquals('v down bottom', 34, r.Bottom);
  // Horizontal 40x20: up = right, down = left.
  r := TyUpDownButtonRect(True, 40, 20, False);
  AssertEquals('h up left', 20, r.Left); AssertEquals('h up right', 40, r.Right);
  r := TyUpDownButtonRect(False, 40, 20, False);
  AssertEquals('h down left', 0, r.Left); AssertEquals('h down right', 20, r.Right);
end;

procedure TUpDownTest.TestHit;
begin
  AssertEquals('v top -> up', 1, TyUpDownHit(10, 4, 20, 34, True));
  AssertEquals('v bottom -> down', -1, TyUpDownHit(10, 30, 20, 34, True));
  AssertEquals('outside', 0, TyUpDownHit(25, 4, 20, 34, True));
  AssertEquals('h right -> up', 1, TyUpDownHit(30, 10, 40, 20, False));
  AssertEquals('h left -> down', -1, TyUpDownHit(5, 10, 40, 20, False));
end;

procedure TUpDownTest.TestClamp;
begin
  AssertEquals('clamp high', 5, TyUpDownClamp(9, 0, 5, False));
  AssertEquals('clamp low', 0, TyUpDownClamp(-3, 0, 5, False));
  AssertEquals('in range', 3, TyUpDownClamp(3, 0, 5, False));
  AssertEquals('wrap over -> min', 0, TyUpDownClamp(6, 0, 5, True));
  AssertEquals('wrap under -> max', 5, TyUpDownClamp(-1, 0, 5, True));
  AssertEquals('inverted range -> min', 0, TyUpDownClamp(3, 0, -5, False));
end;

procedure TUpDownTest.TestPositionClamps;
var c: TTyUpDown;
begin
  c := TTyUpDown.Create(nil);
  try
    c.Min := 0; c.Max := 10;
    c.Position := 20;   AssertEquals('clamped to max', 10, c.Position);
    c.Position := 8;    AssertEquals('set in range', 8, c.Position);
    c.Max := 3;         AssertEquals('shrinking max re-clamps', 3, c.Position);
    c.Position := -5;   AssertEquals('clamped to min', 0, c.Position);
    c.Increment := 0;   AssertEquals('increment floored to 1', 1, c.Increment);
  finally c.Free; end;
end;

initialization
  RegisterTest(TUpDownTest);
end.
