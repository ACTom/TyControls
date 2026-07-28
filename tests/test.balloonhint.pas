unit test.balloonhint;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, fpcunit, testregistry,
  tyControls.BalloonHint, tyControls.Controller, tyControls.BuiltinThemes;

type
  { Reaches the protected metric so a theme's resolved wedge size is readable with no window. }
  TBalloonAccess = class(TTyBalloonHint)
  public
    function Arrow: Integer;
  end;

  TBalloonHintTest = class(TTestCase)
  published
    procedure PrefersBelow;
    procedure FlipsAboveWhenNoRoomBelow;
    procedure ClampsBodyToScreenRight;
    procedure ClampsBodyToScreenLeft;
    procedure TipStaysWithinBody;
    procedure TipCentersOnTarget;
    procedure ArrowSizeIsThemeableAndClassicDoesNotMove;
  end;

implementation

function TBalloonAccess.Arrow: Integer;
begin
  Result := ArrowSizeLogical;
end;

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

{ The wedge used to be a hard-coded 8 with no way for a theme to reach it -- the one geometry
  in the balloon that a skin could not retune, while the popover's identical wedge had
  --popover-arrow-size all along.

  Both densities matter and they matter differently. CLASSIC must not move: light.tycss gives
  --balloon-arrow-size the control's own 8, so a classic balloon is byte-identical to the one
  that shipped. MODERN must follow the density pack, which sets 10 to match the popover -- the
  two wedges appear side by side in the same UI. And a theme must be able to override either,
  which is the whole point of the token. }
procedure TBalloonHintTest.ArrowSizeIsThemeableAndClassicDoesNotMove;
var
  ctl: TTyStyleController;
  b: TBalloonAccess;
  savedDensity: TTyDensity;
begin
  TyRegisterBuiltinThemes;
  ctl := TTyStyleController.Create(nil);
  b := TBalloonAccess.Create(nil);
  try
    b.Controller := ctl;
    ctl.ThemeName := 'default';

    savedDensity := ctl.Density;
    ctl.Density := tdClassic;
    AssertEquals('classic keeps the size that shipped', TyBalloonArrowSize, b.Arrow);

    ctl.Density := tdModern;
    AssertTrue(Format('modern grows the wedge (got %d)', [b.Arrow]),
      b.Arrow > TyBalloonArrowSize);

    { A theme owns it in EITHER density -- read back through the same seam the control uses. }
    ctl.Density := tdClassic;
    ctl.LoadThemeCssAdditive(':root { ' + TyBalloonArrowSizeVar + ': 21px; }');
    AssertEquals('a theme retunes it under classic', 21, b.Arrow);
    ctl.Density := savedDensity;
  finally
    b.Free;
    ctl.Free;
  end;
end;

initialization
  RegisterTest(TBalloonHintTest);
end.
