unit test.balloonhint;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.BalloonHint, tyControls.Controller, tyControls.BuiltinThemes;

type
  { Reaches the protected metric so a theme's resolved wedge size is readable with no window. }
  TBalloonAccess = class(TTyBalloonHint)
  public
    function Arrow: Integer;
    function Inset(ABodyW, ABodyH, APPI: Integer): Integer;
    function Place(const ATarget: TRect; out APointerPx: Integer): TTyBalloonPlacement;
    procedure Render(ACanvas: TCanvas; AW, AH: Integer; const APlacement: TTyBalloonPlacement;
      APointerH: Integer);
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
    procedure TipKeepsOffTheCorners;
    procedure NarrowBodyFallsBackToTheOldRule;
    procedure CornerInsetIsTheRadiusPlusTheBorder;
    procedure PlacementKeepsTheTipOnTheStraightRun;
    procedure RoundedCornerBesideThePointerStaysACurve;
    procedure BodyPaintsInTheAssignedControllersTheme;
  end;

implementation

const
  SW = 1000; SH = 800; PTR = 8;

function TBalloonAccess.Arrow: Integer;
begin
  Result := ArrowSizeLogical;
end;

function TBalloonAccess.Inset(ABodyW, ABodyH, APPI: Integer): Integer;
begin
  Result := CornerInsetPx(ABodyW, ABodyH, APPI);
end;

function TBalloonAccess.Place(const ATarget: TRect; out APointerPx: Integer): TTyBalloonPlacement;
begin
  Result := PlaceAt(ATarget, 96, SW, SH, APointerPx);
end;

procedure TBalloonAccess.Render(ACanvas: TCanvas; AW, AH: Integer;
  const APlacement: TTyBalloonPlacement; APointerH: Integer);
begin
  RenderTo(ACanvas, AW, AH, 96, APlacement, APointerH);
end;

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

procedure TBalloonHintTest.TipKeepsOffTheCorners;
var
  pl: TTyBalloonPlacement;
begin
  // A 6px corner: the tip slides in past the curve as well as the half-base, at both ends.
  pl := TyBalloonPlacement(Rect(0, 100, 20, 120), 200, 80, PTR, SW, SH, 6);
  AssertEquals('body hugs the screen left', 0, pl.Body.Left);
  AssertEquals('tip clamped past the corner', PTR + 6, pl.TipX);
  pl := TyBalloonPlacement(Rect(980, 100, 1000, 120), 200, 80, PTR, SW, SH, 6);
  AssertEquals('and at the far end', pl.Body.Right - (PTR + 6), pl.TipX);
  // A target well inside the body is not moved at all.
  pl := TyBalloonPlacement(Rect(400, 200, 480, 220), 200, 80, PTR, SW, SH, 6);
  AssertEquals('centred tip untouched', 440, pl.TipX);
end;

procedure TBalloonHintTest.NarrowBodyFallsBackToTheOldRule;
var
  pl: TTyBalloonPlacement;
begin
  // 27px cannot keep a 14px margin at both ends: the old half-base rule is all that is left.
  pl := TyBalloonPlacement(Rect(0, 100, 4, 120), 27, 40, PTR, SW, SH, 6);
  AssertEquals('too narrow: half-base only', PTR, pl.TipX);
  pl := TyBalloonPlacement(Rect(0, 100, 4, 120), 28, 40, PTR, SW, SH, 6);
  AssertEquals('exactly wide enough: both margins', PTR + 6, pl.TipX);
end;

const
  { A rounded body with an opaque 4px border (a 1px stroke centred on an inset line is a ~50%
    blend that proves nothing), lime fill, blue border. }
  CBalloonRound = 'TyHint { background: #00FF00; color: #111111; border-radius: 8px;'
    + ' border: 4px solid #0000FF; padding: 10px; font-size: 9px; }';
  CBalloonBorderless = 'TyHint { background: #00FF00; color: #111111; border-radius: 8px;'
    + ' padding: 10px; font-size: 9px; }';

function NewThemedBalloon(ACtl: TTyStyleController; const ACss: string): TBalloonAccess;
begin
  ACtl.LoadThemeCss(ACss);
  Result := TBalloonAccess.Create(nil);
  Result.Controller := ACtl;
  Result.Title := 'Balloon title';
  Result.Description := 'A description long enough to make a wide body';
end;

procedure TBalloonHintTest.CornerInsetIsTheRadiusPlusTheBorder;
var
  ctl: TTyStyleController;
  b: TBalloonAccess;
begin
  ctl := TTyStyleController.Create(nil);
  b := NewThemedBalloon(ctl, CBalloonRound);
  try
    AssertEquals('radius + border', 8 + 4, b.Inset(200, 80, 96));
    AssertEquals('scales with the PPI', 16 + 8, b.Inset(400, 160, 192));
    // The painter clamps a radius to half the shorter side; the inset follows it.
    AssertEquals('clamped radius + border', 5 + 4, b.Inset(200, 10, 96));
    ctl.LoadThemeCss(CBalloonBorderless);
    AssertEquals('no border: the radius alone', 8, b.Inset(200, 80, 96));
  finally
    b.Free;
    ctl.Free;
  end;
end;

{ The target sits at the screen's far left, so the body hugs that edge and the tip is clamped.
  With an 8px corner and a 4px border it must come to rest a half-base (8) + the corner (8)
  + the border (4) in -- and it must get there through the controller the balloon is wired
  to, which is where the theme's corner comes from. }
procedure TBalloonHintTest.PlacementKeepsTheTipOnTheStraightRun;
var
  ctl: TTyStyleController;
  b: TBalloonAccess;
  pl: TTyBalloonPlacement;
  ptr: Integer;
begin
  ctl := TTyStyleController.Create(nil);
  b := NewThemedBalloon(ctl, CBalloonRound);
  try
    pl := b.Place(Rect(0, 100, 10, 124), ptr);
    AssertEquals('pointer from the fallback metric', TyBalloonArrowSize, ptr);
    AssertEquals('body hugs the screen left', 0, pl.Body.Left);
    AssertEquals('tip = half-base + corner + border in', 8 + 8 + 4, pl.TipX - pl.Body.Left);
  finally
    b.Free;
    ctl.Free;
  end;
end;

function IsSentinel(const APx: TBGRAPixel): Boolean;
begin
  Result := (APx.red > 200) and (APx.green < 60) and (APx.blue < 60);
end;

{ Place the balloon at the screen's left edge and paint it onto a clRed sentinel ground. }
function RenderPlaced(B: TBalloonAccess; out AW, AH: Integer): TBGRABitmap;
var
  pl: TTyBalloonPlacement;
  ptr: Integer;
  Bmp: TBitmap;
begin
  pl := B.Place(Rect(0, 100, 10, 124), ptr);
  AW := pl.Body.Right - pl.Body.Left;
  AH := pl.Body.Bottom - pl.Body.Top + ptr;
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(AW, AH);
    Bmp.Canvas.Brush.Color := clRed;
    Bmp.Canvas.FillRect(0, 0, AW, AH);
    B.Render(Bmp.Canvas, AW, AH, pl, ptr);
    Result := TBGRABitmap.Create(Bmp);
  finally
    Bmp.Free;
  end;
end;

{ A pointer whose base started inside the 8px curve sent the outline back along the top edge,
  and the stroke drew a border bar straight across the rounded corner. Pixel (1, 9) is just
  inside the body's top edge (y = 8, below the pointer strip) and well outside the corner's
  arc, so on a correct balloon it is the sentinel ground -- neither border nor fill. }
procedure TBalloonHintTest.RoundedCornerBesideThePointerStaysACurve;
var
  ctl: TTyStyleController;
  b: TBalloonAccess;
  R: TBGRABitmap;
  Px: TBGRAPixel;
  w, h: Integer;
begin
  ctl := TTyStyleController.Create(nil);
  b := NewThemedBalloon(ctl, CBalloonRound);
  try
    R := RenderPlaced(b, w, h);
    try
      Px := R.GetPixel(1, TyBalloonArrowSize + 1);
      AssertTrue(Format('the corner outside the curve is untouched (got %d,%d,%d)',
        [Px.red, Px.green, Px.blue]), IsSentinel(Px));
    finally
      R.Free;
    end;
  finally
    b.Free;
    ctl.Free;
  end;
end;

{ #135: the balloon was measured through its Controller but painted through the default one,
  so a balloon wired to another theme came out that theme's size in the default theme's look.
  A pixel in the bottom padding (above the 4px border) must be the assigned theme's lime. }
procedure TBalloonHintTest.BodyPaintsInTheAssignedControllersTheme;
var
  ctl: TTyStyleController;
  b: TBalloonAccess;
  R: TBGRABitmap;
  Px: TBGRAPixel;
  w, h: Integer;
begin
  ctl := TTyStyleController.Create(nil);
  b := NewThemedBalloon(ctl, CBalloonRound);
  try
    R := RenderPlaced(b, w, h);
    try
      Px := R.GetPixel(w div 2, h - 7);
      AssertTrue(Format('the body is the assigned theme''s fill (got %d,%d,%d)',
        [Px.red, Px.green, Px.blue]), (Px.green > 180) and (Px.red < 120) and (Px.blue < 120));
    finally
      R.Free;
    end;
  finally
    b.Free;
    ctl.Free;
  end;
end;

initialization
  RegisterTest(TBalloonHintTest);
end.
