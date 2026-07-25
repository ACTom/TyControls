unit tyControls.GearActivityIndicator;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, ExtCtrls,
  BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.StyleModel,
  tyControls.ActivityIndicator, tyControls.GearDial;

type
  { An INDETERMINATE busy indicator: a gear that spins continuously (decorative sibling
    of TTyActivityIndicator). Reuses TTyActivityIndicator's TyActivityAdvance rotation and
    TTyGearDial's TyGearToothAngle tooth layout. No value; `Active` starts/stops the spin.
    Themed as itself — 'TyGearActivityIndicator' (the punched-out centre HOLE) and
    'TyGearActivityIndicatorFill' (teeth + body disc). Note the token roles are inverted
    versus a gauge: the box key paints a hole, not a track behind a fill. Borrowing the
    gauge's key therefore hardcoded the hole to the gauge's sunk-track colour, so on a card,
    a toolbar or a dark overlay the gear spun with a wrongly-coloured plug in its middle and
    no theme rule could fix it. Spins only when Active AND painted (has a parent handle);
    headless it is static, keeping render/golden tests pixel-stable. }
  TTyGearActivityIndicator = class(TTyGraphicControl)
  private
    FActive: Boolean;
    FTeeth: Integer;
    FAngle: Double;       // current rotation (degrees)
    FTimer: TTimer;       // lazy; only created when actually spinning
    procedure SetActive(const AValue: Boolean);
    procedure SetTeeth(const AValue: Integer);
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
    procedure UpdateRunning;
  protected
    function GetStyleTypeKey: string; override;   // 'TyGearActivityIndicator' (+ 'Fill' sub-part)
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Step seam (no wall-clock): advance the spin by AMs; returns True (always moves).
    function AdvanceAnimation(AMs: Integer): Boolean;
    // Read-only current rotation, for tests/introspection.
    property Angle: Double read FAngle;
  published
    property Active: Boolean read FActive write SetActive default True;
    property Teeth: Integer read FTeeth write SetTeeth default 9;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

const
  cPeriodMs = 1400;   // ~1.4s per full turn

constructor TTyGearActivityIndicator.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FActive := True;
  FTeeth := 9;
  FAngle := 0;
  Width := 32;
  Height := 32;
end;

destructor TTyGearActivityIndicator.Destroy;
begin
  FreeAndNil(FTimer);   // stop the callback before teardown
  inherited Destroy;
end;

function TTyGearActivityIndicator.GetStyleTypeKey: string;
begin
  { Its own key, not the gauge's: here the box background is the gear's HOLE, so it must match
    whatever surface hosts the spinner. Under 'TyGauge' that was a track colour and unfixable. }
  Result := 'TyGearActivityIndicator';
end;

procedure TTyGearActivityIndicator.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 16;
    FTimer.OnTimer := @HandleTimer;
  end;
end;

function TTyGearActivityIndicator.AdvanceAnimation(AMs: Integer): Boolean;
begin
  FAngle := TyActivityAdvance(FAngle, AMs, cPeriodMs);   // reuse the spinner's wrapped advance
  Result := True;
end;

procedure TTyGearActivityIndicator.HandleTimer(Sender: TObject);
begin
  AdvanceAnimation(FTimer.Interval);
  Invalidate;
end;

procedure TTyGearActivityIndicator.UpdateRunning;
begin
  if FActive and (Parent <> nil) and Parent.HandleAllocated then
  begin
    EnsureTimer;
    FTimer.Enabled := True;
  end
  else if FTimer <> nil then
    FTimer.Enabled := False;
end;

procedure TTyGearActivityIndicator.SetActive(const AValue: Boolean);
begin
  if FActive = AValue then Exit;
  FActive := AValue;
  UpdateRunning;
  Invalidate;
end;

procedure TTyGearActivityIndicator.SetTeeth(const AValue: Integer);
var v: Integer;
begin
  v := AValue;
  if v < 3 then v := 3 else if v > 24 then v := 24;
  if FTeeth = v then Exit;
  FTeeth := v;
  Invalidate;
end;

procedure TTyGearActivityIndicator.Paint;
var
  P: TTyPainter;
  trackS, fillS: TTyStyleSet;
  R: TRect;
  ctx: TBGRACanvas2D;
  cx, cy, radius, rimR, tipR, halfW, tAng: Double;
  i: Integer;
begin
  UpdateRunning;   // begin spinning once we have a paintable handle
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ClientWidth, ClientHeight);
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    TyApplyStyleOpacity(Self, P, CurrentStyle);   // :disabled { opacity } — this control self-draws (no DrawFrame)
    trackS := CurrentStyle;                                             // TyGearActivityIndicator hole
    { Sub-part key derived from the box key so the two can never drift apart. }
    fillS := ActiveController.Model.ResolveStyle(GetStyleTypeKey + 'Fill', StyleClass, []);  // gear
    cx := (R.Left + R.Right) / 2;
    cy := (R.Top + R.Bottom) / 2;
    radius := Math.Min(R.Right - R.Left, R.Bottom - R.Top) / 2 - P.Scale(5);
    if radius >= 4 then
    begin
      ctx := P.Bitmap.Canvas2D;
      rimR := radius;
      tipR := radius + P.Scale(5);
      halfW := DegToRad(360 / Math.Max(1, FTeeth) * 0.32);   // half angular width of a tooth
      // Teeth (accent), rotated by the current spin angle.
      ctx.fillStyle(TyColorToBGRA(fillS.Background.Color));
      for i := 0 to FTeeth - 1 do
      begin
        tAng := DegToRad(TyGearToothAngle(i, FTeeth) + FAngle);
        ctx.beginPath;
        ctx.moveTo(cx + rimR * Cos(tAng - halfW), cy + rimR * Sin(tAng - halfW));
        ctx.lineTo(cx + tipR * Cos(tAng - halfW * 0.6), cy + tipR * Sin(tAng - halfW * 0.6));
        ctx.lineTo(cx + tipR * Cos(tAng + halfW * 0.6), cy + tipR * Sin(tAng + halfW * 0.6));
        ctx.lineTo(cx + rimR * Cos(tAng + halfW), cy + rimR * Sin(tAng + halfW));
        ctx.closePath;
        ctx.fill;
      end;
      // Gear body: accent disc.
      ctx.beginPath;
      ctx.arc(cx, cy, radius, 0, 2 * Pi, False);
      ctx.fillStyle(TyColorToBGRA(fillS.Background.Color));
      ctx.fill;
      // Centre hole: the faint track colour, so it reads as a gear (and the spin is visible).
      ctx.beginPath;
      ctx.arc(cx, cy, radius * 0.4, 0, 2 * Pi, False);
      ctx.fillStyle(TyColorToBGRA(trackS.Background.Color));
      ctx.fill;
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
