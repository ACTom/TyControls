unit tyControls.Meter;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, ExtCtrls,
  BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.StyleModel,
  tyControls.Animation, tyControls.Gauge;

{ Angle (degrees) of tick AIndex of ACount evenly spaced across AStartDeg..+ASweepDeg (inclusive). }
function TyMeterTickAngle(AIndex, ACount: Integer; AStartDeg, ASweepDeg: Double): Double;

type
  { An analog NEEDLE meter: a scaled arc of tick marks with a needle pointing at Value,
    plus a hub and an optional numeric readout. Reuses the gauge theming (typeKey 'TyGauge'
    for face/ticks/text, 'TyGaugeFill' for the needle) so no extra .tycss rules; eased needle
    movement (snaps headless). The sweep covers the 90/120/270-deg meter variants via
    StartAngle/SweepAngle. }
  TTyMeter = class(TTyGraphicControl)
  private
    FMin, FMax, FValue: Double;
    FStartAngle, FSweepAngle, FTicks: Integer;
    FShowValue: Boolean;
    FValueFormat: string;
    FAnimEnabled: Boolean;
    FPosAnim: TTyAnimator;
    FAnimFrom, FAnimTo: Single;
    FTimer: TTimer;
    procedure SetMin(const AValue: Double);
    procedure SetMax(const AValue: Double);
    procedure SetValue(const AValue: Double);
    procedure SetStartAngle(const AValue: Integer);
    procedure SetSweepAngle(const AValue: Integer);
    procedure SetTicks(const AValue: Integer);
    procedure SetShowValue(const AValue: Boolean);
    procedure SetValueFormat(const AValue: string);
    procedure ArmTo(AFrac: Double);
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
  protected
    function GetStyleTypeKey: string; override;   // 'TyGauge'
    procedure Paint; override;
    function DisplayFrac: Single;
    function AdvanceAnimation(AMs: Integer): Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Min: Double read FMin write SetMin;
    property Max: Double read FMax write SetMax;
    property Value: Double read FValue write SetValue;
    property StartAngle: Integer read FStartAngle write SetStartAngle default 150;
    property SweepAngle: Integer read FSweepAngle write SetSweepAngle default 240;
    property Ticks: Integer read FTicks write SetTicks default 5;
    property ShowValue: Boolean read FShowValue write SetShowValue default True;
    property ValueFormat: string read FValueFormat write SetValueFormat;
    property AnimationsEnabled: Boolean read FAnimEnabled write FAnimEnabled default True;
    property Font;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

function TyMeterTickAngle(AIndex, ACount: Integer; AStartDeg, ASweepDeg: Double): Double;
begin
  if ACount <= 1 then Exit(AStartDeg);
  Result := AStartDeg + ASweepDeg * (AIndex / (ACount - 1));
end;

constructor TTyMeter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMin := 0;
  FMax := 100;
  FValue := 0;
  FStartAngle := 150;
  FSweepAngle := 240;
  FTicks := 5;
  FShowValue := True;
  FValueFormat := '%.0f';
  FAnimEnabled := True;
  FPosAnim.Progress := 1;
  FPosAnim.Target := 1;
  FPosAnim.DurationMs := 300;
  FPosAnim.Easing := teEaseOutCubic;
  FAnimFrom := 0;
  FAnimTo := 0;
  Width := 140;
  Height := 120;
end;

destructor TTyMeter.Destroy;
begin
  FreeAndNil(FTimer);
  inherited Destroy;
end;

function TTyMeter.GetStyleTypeKey: string;
begin
  Result := 'TyGauge';
end;

procedure TTyMeter.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 16;
    FTimer.OnTimer := @HandleTimer;
  end;
end;

procedure TTyMeter.HandleTimer(Sender: TObject);
begin
  if AdvanceAnimation(FTimer.Interval) then Invalidate;
  if not FPosAnim.Running then FTimer.Enabled := False;
end;

function TTyMeter.AdvanceAnimation(AMs: Integer): Boolean;
begin
  Result := FPosAnim.Advance(AMs);
end;

function TTyMeter.DisplayFrac: Single;
begin
  Result := TyLerpF(FAnimFrom, FAnimTo, FPosAnim.Eased);
end;

procedure TTyMeter.ArmTo(AFrac: Double);
begin
  if AFrac < 0 then AFrac := 0 else if AFrac > 1 then AFrac := 1;
  if FAnimEnabled and (Parent <> nil) and Parent.HandleAllocated then
  begin
    FAnimFrom := DisplayFrac;
    FAnimTo := AFrac;
    FPosAnim.Progress := 0;
    FPosAnim.Target := 1;
    EnsureTimer;
    FTimer.Enabled := True;
  end
  else
  begin
    FAnimFrom := AFrac;
    FAnimTo := AFrac;
    FPosAnim.SetTargetImmediate(1);
  end;
  Invalidate;
end;

procedure TTyMeter.SetMin(const AValue: Double);
begin
  if FMin = AValue then Exit;
  FMin := AValue;
  ArmTo(TyGaugeFraction(FValue, FMin, FMax));
end;

procedure TTyMeter.SetMax(const AValue: Double);
begin
  if FMax = AValue then Exit;
  FMax := AValue;
  ArmTo(TyGaugeFraction(FValue, FMin, FMax));
end;

procedure TTyMeter.SetValue(const AValue: Double);
var v: Double;
begin
  v := AValue;
  if v < FMin then v := FMin else if v > FMax then v := FMax;
  if FValue = v then Exit;
  FValue := v;
  ArmTo(TyGaugeFraction(FValue, FMin, FMax));
end;

procedure TTyMeter.SetStartAngle(const AValue: Integer);
begin if FStartAngle = AValue then Exit; FStartAngle := AValue; Invalidate; end;

procedure TTyMeter.SetSweepAngle(const AValue: Integer);
begin if FSweepAngle = AValue then Exit; FSweepAngle := AValue; Invalidate; end;

procedure TTyMeter.SetTicks(const AValue: Integer);
begin if FTicks = AValue then Exit; FTicks := Math.Max(0, AValue); Invalidate; end;

procedure TTyMeter.SetShowValue(const AValue: Boolean);
begin if FShowValue = AValue then Exit; FShowValue := AValue; Invalidate; end;

procedure TTyMeter.SetValueFormat(const AValue: string);
begin if FValueFormat = AValue then Exit; FValueFormat := AValue; Invalidate; end;

procedure TTyMeter.Paint;
var
  P: TTyPainter;
  faceS, needleS: TTyStyleSet;
  R: TRect;
  ctx: TBGRACanvas2D;
  cx, cy, radius, ang, rr: Double;
  i: Integer;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ClientWidth, ClientHeight);
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    faceS := CurrentStyle;                                              // TyGauge face/ticks/text
    needleS := ActiveController.Model.ResolveStyle('TyGaugeFill', StyleClass, []);

    // Centre near the bottom so a top-arc meter uses the height well; radius from width/height.
    cx := (R.Left + R.Right) / 2;
    cy := R.Top + (R.Bottom - R.Top) * 0.62;
    radius := Math.Min((R.Right - R.Left) / 2, (R.Bottom - R.Top) * 0.55) - P.Scale(6);
    if radius >= 4 then
    begin
      ctx := P.Bitmap.Canvas2D;
      ctx.lineCap := 'round';

      // Tick marks (short radial strokes at the outer edge), in the face text colour.
      ctx.lineWidth := Math.Max(1, P.Scale(2));
      ctx.strokeStyle(TyColorToBGRA(faceS.TextColor));
      for i := 0 to FTicks - 1 do
      begin
        ang := DegToRad(TyMeterTickAngle(i, FTicks, FStartAngle, FSweepAngle));
        ctx.beginPath;
        ctx.moveTo(cx + radius * Cos(ang), cy + radius * Sin(ang));
        rr := radius - P.Scale(8);
        ctx.lineTo(cx + rr * Cos(ang), cy + rr * Sin(ang));
        ctx.stroke;
      end;

      // Needle from the hub to the value angle, in the accent (fill) colour.
      ang := DegToRad(TyGaugeSweepEnd(FStartAngle, FSweepAngle, DisplayFrac));
      ctx.lineWidth := Math.Max(2, P.Scale(3));
      ctx.strokeStyle(TyColorToBGRA(needleS.Background.Color));
      ctx.beginPath;
      ctx.moveTo(cx, cy);
      ctx.lineTo(cx + (radius - P.Scale(10)) * Cos(ang), cy + (radius - P.Scale(10)) * Sin(ang));
      ctx.stroke;
      // Hub.
      ctx.fillStyle(TyColorToBGRA(needleS.Background.Color));
      ctx.beginPath;
      ctx.arc(cx, cy, Math.Max(2, P.Scale(4)), 0, 2 * Pi, False);
      ctx.fill;
    end;

    if FShowValue then
      P.DrawText(Rect(R.Left, R.Bottom - P.Scale(22), R.Right, R.Bottom),
        Format(FValueFormat, [FValue]), Font.Name, 11, 700, faceS.TextColor,
        taCenter, tlCenter, False);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
