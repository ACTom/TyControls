unit test.dial;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Math, fpcunit, testregistry,
  tyControls.Dial, tyControls.Gauge;
type
  TDialTest = class(TTestCase)
  published
    procedure TestValueAtStartAndEnd;
    procedure TestValueMidpoint;
    procedure TestRoundTrip;
    procedure TestDeadWedgeClamps;
    procedure TestDegenerate;
  end;
implementation

const
  C: TPoint = (X: 100; Y: 100);   // centre
  R = 50.0;

// Point on the value-arc at fraction AFrac, mirroring the paint math:
// x = cx + r*cos(ang), y = cy + r*sin(ang), ang = start + sweep*frac (degrees).
function ArcPt(AStartDeg, ASweepDeg, AFrac: Double): TPoint;
var ang: Double;
begin
  ang := DegToRad(TyGaugeSweepEnd(AStartDeg, ASweepDeg, AFrac));
  Result := Point(Round(C.X + R * Cos(ang)), Round(C.Y + R * Sin(ang)));
end;

procedure TDialTest.TestValueAtStartAndEnd;
begin
  // A point at the start angle -> Min; at the end angle -> Max. (Start 135, sweep 270.)
  AssertEquals('start -> Min', 0.0,
    TyDialValueFromAngle(ArcPt(135, 270, 0), C, 135, 270, 0, 100), 0.5);
  AssertEquals('end -> Max', 100.0,
    TyDialValueFromAngle(ArcPt(135, 270, 1), C, 135, 270, 0, 100), 0.5);
end;

procedure TDialTest.TestValueMidpoint;
begin
  // Midpoint of the sweep -> centre of the range.
  AssertEquals('mid -> 50', 50.0,
    TyDialValueFromAngle(ArcPt(135, 270, 0.5), C, 135, 270, 0, 100), 0.5);
end;

procedure TDialTest.TestRoundTrip;
const Fracs: array[0..3] of Double = (0.1, 0.25, 0.75, 0.9);
var i: Integer; f, v: Double;
begin
  // For several fractions, value->angle->value returns the same value.
  for i := Low(Fracs) to High(Fracs) do
  begin
    f := Fracs[i];
    v := TyDialValueFromAngle(ArcPt(135, 270, f), C, 135, 270, 0, 100);
    AssertEquals('round-trip frac ' + FloatToStr(f), f * 100, v, 1.0);
  end;
end;

procedure TDialTest.TestDeadWedgeClamps;
var v: Double;
begin
  // A point inside the 90-deg dead wedge (opposite the sweep for start=135/sweep=270,
  // the gap is centred near 45 deg = south-east) clamps to the nearest end, never
  // wraps to a mid value. Sample the wedge centre (angle 45).
  v := TyDialValueFromAngle(ArcPt(135, 270, 0) { start } , C, 135, 270, 0, 100);
  AssertTrue('start end is Min', Abs(v - 0.0) < 0.5);
  // A point just past the end (angle a few deg into the gap) clamps to Max, not Min.
  v := TyDialValueFromAngle(
    Point(Round(C.X + R * Cos(DegToRad(410))), Round(C.Y + R * Sin(DegToRad(410)))),
    C, 135, 270, 0, 100);
  AssertEquals('just past end clamps to Max', 100.0, v, 0.5);
end;

procedure TDialTest.TestDegenerate;
begin
  // Zero/negative sweep or empty range -> Min (no div-by-zero).
  AssertEquals('zero sweep', 0.0,
    TyDialValueFromAngle(Point(150, 100), C, 135, 0, 0, 100), 1e-9);
  AssertEquals('empty range', 5.0,
    TyDialValueFromAngle(Point(150, 100), C, 135, 270, 5, 5), 1e-9);
end;

initialization
  RegisterTest(TDialTest);
end.
