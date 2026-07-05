unit test.geardial;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Math, fpcunit, testregistry,
  tyControls.GearDial, tyControls.Dial, tyControls.Gauge;
type
  TGearDialTest = class(TTestCase)
  published
    procedure TestToothAngleEvenSpacing;
    procedure TestToothAngleWraps;
    procedure TestToothAngleDegenerate;
    procedure TestValueRoundTrip;
  end;
implementation

const
  C: TPoint = (X: 100; Y: 100);   // centre
  R = 50.0;

// Point on the value-arc at fraction AFrac, mirroring the paint math.
function ArcPt(AStartDeg, ASweepDeg, AFrac: Double): TPoint;
var ang: Double;
begin
  ang := DegToRad(TyGaugeSweepEnd(AStartDeg, ASweepDeg, AFrac));
  Result := Point(Round(C.X + R * Cos(ang)), Round(C.Y + R * Sin(ang)));
end;

procedure TGearDialTest.TestToothAngleEvenSpacing;
begin
  // 12 teeth: 0 -> 0, index 1 -> 30, index 3 -> 90, index 6 -> 180.
  AssertEquals('tooth 0', 0.0, TyGearToothAngle(0, 12), 1e-9);
  AssertEquals('tooth 1', 30.0, TyGearToothAngle(1, 12), 1e-9);
  AssertEquals('tooth 3', 90.0, TyGearToothAngle(3, 12), 1e-9);
  AssertEquals('tooth 6', 180.0, TyGearToothAngle(6, 12), 1e-9);
  // 8 teeth: even 45-deg spacing.
  AssertEquals('8-tooth quarter', 90.0, TyGearToothAngle(2, 8), 1e-9);
end;

procedure TGearDialTest.TestToothAngleWraps;
begin
  // The last index of an N-tooth ring lands one step short of a full turn.
  AssertEquals('last of 12', 330.0, TyGearToothAngle(11, 12), 1e-9);
  // Index == count reaches a full 360 (paint iterates 0..count-1 so this is just the identity).
  AssertEquals('full turn', 360.0, TyGearToothAngle(12, 12), 1e-9);
end;

procedure TGearDialTest.TestToothAngleDegenerate;
begin
  // Zero or negative count -> 0 (no div by zero).
  AssertEquals('zero teeth', 0.0, TyGearToothAngle(0, 0), 1e-9);
  AssertEquals('zero teeth idx', 0.0, TyGearToothAngle(3, 0), 1e-9);
  AssertEquals('negative teeth', 0.0, TyGearToothAngle(1, -4), 1e-9);
end;

procedure TGearDialTest.TestValueRoundTrip;
const Fracs: array[0..3] of Double = (0.1, 0.25, 0.75, 0.9);
var i: Integer; f, v: Double;
begin
  // The knob reuses TyDialValueFromAngle for pointer math: value->angle->value round-trips.
  for i := Low(Fracs) to High(Fracs) do
  begin
    f := Fracs[i];
    v := TyDialValueFromAngle(ArcPt(135, 270, f), C, 135, 270, 0, 100);
    AssertEquals('round-trip frac ' + FloatToStr(f), f * 100, v, 1.0);
  end;
end;

initialization
  RegisterTest(TGearDialTest);
end.
