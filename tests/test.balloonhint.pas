unit test.balloonhint;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, fpcunit, testregistry, tyControls.BalloonHint;

type
  TBalloonHintTest = class(TTestCase)
  published
    procedure PrefersBelow;
    procedure FlipsAboveWhenNoRoomBelow;
    procedure ClampsBodyToScreenRight;
    procedure ClampsBodyToScreenLeft;
    procedure TipStaysWithinBody;
    procedure TipCentersOnTarget;
  end;

implementation

const
  SW = 1000; SH = 800; PTR = 8;

procedure TBalloonHintTest.PrefersBelow;
var
  pl: TTyBalloonPlacement;
begin
  // Target near the top; plenty of room below -> below.
  pl := TyBalloonPlacement(Rect(400, 100, 480, 120), 200, 100, PTR, SW, SH);
  AssertTrue('below', pl.Below);
  AssertEquals('body top = target bottom + pointer', 120 + PTR, pl.Body.Top);
  AssertEquals('tipY = target bottom', 120, pl.TipY);
end;

procedure TBalloonHintTest.FlipsAboveWhenNoRoomBelow;
var
  pl: TTyBalloonPlacement;
begin
  // Target near the bottom; no room below, room above -> above.
  pl := TyBalloonPlacement(Rect(400, 760, 480, 785), 200, 100, PTR, SW, SH);
  AssertFalse('above', pl.Below);
  AssertEquals('body bottom = target top - pointer', 760 - PTR, pl.Body.Bottom);
  AssertEquals('tipY = target top', 760, pl.TipY);
end;

procedure TBalloonHintTest.ClampsBodyToScreenRight;
var
  pl: TTyBalloonPlacement;
begin
  // Target hard against the right edge; body must not overflow the screen.
  pl := TyBalloonPlacement(Rect(980, 100, 1000, 120), 200, 80, PTR, SW, SH);
  AssertTrue('right within screen', pl.Body.Right <= SW);
  AssertEquals('body width preserved', 200, pl.Body.Right - pl.Body.Left);
end;

procedure TBalloonHintTest.ClampsBodyToScreenLeft;
var
  pl: TTyBalloonPlacement;
begin
  pl := TyBalloonPlacement(Rect(0, 100, 20, 120), 200, 80, PTR, SW, SH);
  AssertTrue('left within screen', pl.Body.Left >= 0);
  AssertEquals('body width preserved', 200, pl.Body.Right - pl.Body.Left);
end;

procedure TBalloonHintTest.TipStaysWithinBody;
var
  pl: TTyBalloonPlacement;
begin
  // Target at far right forces the body to clamp left; the tip must stay on the body.
  pl := TyBalloonPlacement(Rect(980, 100, 1000, 120), 200, 80, PTR, SW, SH);
  AssertTrue('tip >= body.left + pointer', pl.TipX >= pl.Body.Left + PTR);
  AssertTrue('tip <= body.right - pointer', pl.TipX <= pl.Body.Right - PTR);
end;

procedure TBalloonHintTest.TipCentersOnTarget;
var
  pl: TTyBalloonPlacement;
begin
  // Centered target with room on all sides -> tip at target center X.
  pl := TyBalloonPlacement(Rect(400, 200, 480, 220), 200, 80, PTR, SW, SH);
  AssertEquals('tipX = target center', 440, pl.TipX);
end;

initialization
  RegisterTest(TBalloonHintTest);
end.
