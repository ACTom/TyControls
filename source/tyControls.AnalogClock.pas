unit tyControls.AnalogClock;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, ExtCtrls,
  BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.StyleModel;

{ All angles in DEGREES, 0 = up (12 o'clock), clockwise. The Paint path converts to
  the east-based, 0=east geometry the Canvas2D uses by subtracting 90. }

{ Hour-hand angle: (h mod 12)*30 + m*0.5 (the hand creeps between the hour marks). }
function TyClockHourAngle(AHour, AMinute: Integer): Double;
{ Minute-hand angle: m*6 + s*0.1 (creeps with the seconds). }
function TyClockMinuteAngle(AMinute, ASecond: Integer): Double;
{ Second-hand angle: s*6. }
function TyClockSecondAngle(ASecond: Integer): Double;

type
  { An analog CLOCK face — 12 hour tick marks around the rim, an hour + minute hand
    (in the face text colour, different lengths/widths), a thin second hand (accent =
    'TyGaugeFill') and a centre hub. Reuses the gauge theming (typeKey 'TyGauge' for
    face/ticks/text, 'TyGaugeFill' for the second hand) so no extra .tycss rules.
    When Running and painted (has a parent handle) a 1s timer advances Time to Now each
    tick; headless it is static so render tests stay pixel-stable. }
  TTyAnalogClock = class(TTyGraphicControl)
  private
    FTime: TDateTime;
    FShowSeconds: Boolean;
    FShowTicks: Boolean;
    FRunning: Boolean;
    FTimer: TTimer;
    procedure SetTime(const AValue: TDateTime);
    procedure SetShowSeconds(const AValue: Boolean);
    procedure SetShowTicks(const AValue: Boolean);
    procedure SetRunning(const AValue: Boolean);
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
    procedure UpdateRunning;
    procedure DrawHand(ctx: TBGRACanvas2D; cx, cy, ADeg, ALen, AWidth: Double;
      AColor: TTyColor);
  protected
    function GetStyleTypeKey: string; override;   // 'TyGauge'
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Time: TDateTime read FTime write SetTime;
    property ShowSeconds: Boolean read FShowSeconds write SetShowSeconds default True;
    property ShowTicks: Boolean read FShowTicks write SetShowTicks default True;
    property Running: Boolean read FRunning write SetRunning default True;
    property Font;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

function TyClockHourAngle(AHour, AMinute: Integer): Double;
begin
  Result := (AHour mod 12) * 30 + AMinute * 0.5;
end;

function TyClockMinuteAngle(AMinute, ASecond: Integer): Double;
begin
  Result := AMinute * 6 + ASecond * 0.1;
end;

function TyClockSecondAngle(ASecond: Integer): Double;
begin
  Result := ASecond * 6;
end;

constructor TTyAnalogClock.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTime := Now;
  FShowSeconds := True;
  FShowTicks := True;
  FRunning := True;
  Width := 120;
  Height := 120;
end;

destructor TTyAnalogClock.Destroy;
begin
  FreeAndNil(FTimer);   // stop the callback before teardown
  inherited Destroy;
end;

function TTyAnalogClock.GetStyleTypeKey: string;
begin
  Result := 'TyGauge';
end;

procedure TTyAnalogClock.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 1000;   // tick once a second
    FTimer.OnTimer := @HandleTimer;
  end;
end;

procedure TTyAnalogClock.HandleTimer(Sender: TObject);
begin
  FTime := Now;
  Invalidate;
end;

procedure TTyAnalogClock.UpdateRunning;
begin
  { A graphic control paints onto its parent; "has a window to run into" means the
    parent handle is allocated. Headless render tests parent to an unshown form (no
    handle) -> the timer never runs, so Time stays put and pixels are stable. }
  if FRunning and (Parent <> nil) and Parent.HandleAllocated then
  begin
    EnsureTimer;
    FTimer.Enabled := True;
  end
  else if FTimer <> nil then
    FTimer.Enabled := False;
end;

procedure TTyAnalogClock.SetTime(const AValue: TDateTime);
begin
  if FTime = AValue then Exit;
  FTime := AValue;
  Invalidate;
end;

procedure TTyAnalogClock.SetShowSeconds(const AValue: Boolean);
begin
  if FShowSeconds = AValue then Exit;
  FShowSeconds := AValue;
  Invalidate;
end;

procedure TTyAnalogClock.SetShowTicks(const AValue: Boolean);
begin
  if FShowTicks = AValue then Exit;
  FShowTicks := AValue;
  Invalidate;
end;

procedure TTyAnalogClock.SetRunning(const AValue: Boolean);
begin
  if FRunning = AValue then Exit;
  FRunning := AValue;
  UpdateRunning;
  Invalidate;
end;

procedure TTyAnalogClock.DrawHand(ctx: TBGRACanvas2D; cx, cy, ADeg, ALen, AWidth: Double;
  AColor: TTyColor);
var ang: Double;
begin
  ang := DegToRad(ADeg - 90);   // 0=up -> east-based (0=east) geometry
  ctx.lineWidth := Math.Max(1, AWidth);
  ctx.strokeStyle(TyColorToBGRA(AColor));
  ctx.beginPath;
  ctx.moveTo(cx, cy);
  ctx.lineTo(cx + ALen * Cos(ang), cy + ALen * Sin(ang));
  ctx.stroke;
end;

procedure TTyAnalogClock.Paint;
var
  P: TTyPainter;
  faceS, accentS: TTyStyleSet;
  R: TRect;
  ctx: TBGRACanvas2D;
  cx, cy, radius, ang, rr: Double;
  h, m, s, ms: Word;
  i: Integer;
begin
  UpdateRunning;   // begin ticking once we have a paintable handle
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ClientWidth, ClientHeight);
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    faceS := CurrentStyle;                                             // TyGauge face/ticks/text
    accentS := ActiveController.Model.ResolveStyle('TyGaugeFill', StyleClass, []);

    cx := (R.Left + R.Right) / 2;
    cy := (R.Top + R.Bottom) / 2;
    radius := (Math.Min(R.Right - R.Left, R.Bottom - R.Top)) / 2 - P.Scale(6);
    if radius >= 6 then
    begin
      DecodeTime(FTime, h, m, s, ms);
      ctx := P.Bitmap.Canvas2D;
      ctx.lineCap := 'round';

      // 12 hour tick marks around the rim, in the face text colour.
      if FShowTicks then
      begin
        ctx.lineWidth := Math.Max(1, P.Scale(2));
        ctx.strokeStyle(TyColorToBGRA(faceS.TextColor));
        for i := 0 to 11 do
        begin
          ang := DegToRad(i * 30 - 90);   // 0=up, every 30 deg
          ctx.beginPath;
          ctx.moveTo(cx + radius * Cos(ang), cy + radius * Sin(ang));
          rr := radius - P.Scale(7);
          ctx.lineTo(cx + rr * Cos(ang), cy + rr * Sin(ang));
          ctx.stroke;
        end;
      end;

      // Hour hand: short + thick; minute hand: long + medium — both in the text colour.
      DrawHand(ctx, cx, cy, TyClockHourAngle(h, m), radius * 0.5, P.Scale(4), faceS.TextColor);
      DrawHand(ctx, cx, cy, TyClockMinuteAngle(m, s), radius * 0.78, P.Scale(3), faceS.TextColor);

      // Thin second hand in the accent (fill) colour.
      if FShowSeconds then
        DrawHand(ctx, cx, cy, TyClockSecondAngle(s), radius * 0.85, Math.Max(1, P.Scale(1)),
          accentS.Background.Color);

      // Centre hub, in the accent colour.
      ctx.fillStyle(TyColorToBGRA(accentS.Background.Color));
      ctx.beginPath;
      ctx.arc(cx, cy, Math.Max(2, P.Scale(3)), 0, 2 * Pi, False);
      ctx.fill;
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
