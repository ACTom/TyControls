unit test.analogclock;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.AnalogClock;
type
  TAnalogClockTest = class(TTestCase)
  published
    procedure TestHourAngle;
    procedure TestMinuteAngle;
    procedure TestSecondAngle;
  end;
implementation

procedure TAnalogClockTest.TestHourAngle;
begin
  // 12:00 -> straight up (0 deg)
  AssertEquals('12:00 hour', 0.0, TyClockHourAngle(12, 0), 1e-9);
  AssertEquals('0:00 hour', 0.0, TyClockHourAngle(0, 0), 1e-9);
  // 3:00 -> quarter turn (90 deg)
  AssertEquals('3:00 hour', 90.0, TyClockHourAngle(3, 0), 1e-9);
  // 6:00 -> half turn (180 deg)
  AssertEquals('6:00 hour', 180.0, TyClockHourAngle(6, 0), 1e-9);
  // 9:00 -> three-quarter turn (270 deg)
  AssertEquals('9:00 hour', 270.0, TyClockHourAngle(9, 0), 1e-9);
  // hour hand creeps: 3:30 -> 90 + 15 = 105 deg
  AssertEquals('3:30 hour creep', 105.0, TyClockHourAngle(3, 30), 1e-9);
end;

procedure TAnalogClockTest.TestMinuteAngle;
begin
  // :00 -> up
  AssertEquals('00 min', 0.0, TyClockMinuteAngle(0, 0), 1e-9);
  // :15 -> quarter turn
  AssertEquals('15 min', 90.0, TyClockMinuteAngle(15, 0), 1e-9);
  // :30 -> half turn
  AssertEquals('30 min', 180.0, TyClockMinuteAngle(30, 0), 1e-9);
  // minute hand creeps with seconds: :00:30 -> 3 deg
  AssertEquals('min creep', 3.0, TyClockMinuteAngle(0, 30), 1e-9);
end;

procedure TAnalogClockTest.TestSecondAngle;
begin
  AssertEquals('00 sec', 0.0, TyClockSecondAngle(0), 1e-9);
  AssertEquals('15 sec', 90.0, TyClockSecondAngle(15), 1e-9);
  AssertEquals('30 sec', 180.0, TyClockSecondAngle(30), 1e-9);
  AssertEquals('45 sec', 270.0, TyClockSecondAngle(45), 1e-9);
end;

initialization
  RegisterTest(TAnalogClockTest);
end.
