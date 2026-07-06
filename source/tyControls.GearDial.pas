unit tyControls.GearDial;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType, ExtCtrls,
  BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.StyleModel,
  tyControls.Animation, tyControls.Gauge, tyControls.Dial;

{ Angle (degrees, 0 = east, clockwise) of gear tooth AIndex of ACount evenly
  spaced around the full rim: AIndex * 360 / ACount. Returns 0 when ACount <= 0. }
function TyGearToothAngle(AIndex, ACount: Integer): Double;

type
  { An INTERACTIVE rotary knob whose body carries GEAR TEETH around the rim. Same
    interaction model as TTyDial: drag around the centre, or use the wheel / arrow
    keys, to change Value; a single ApplyValue choke-point clamps and fires OnChange
    only on a real change. Reuses TyDialValueFromAngle for the pointer angle math and
    the gauge theming (typeKey 'TyGauge' for body/teeth/border/text, 'TyGaugeFill' for
    the accent pointer/hub) so no extra .tycss rules. Direct manipulation SNAPS (no
    ease) so the notch tracks the pointer and headless render tests stay pixel-stable. }
  TTyGearDial = class(TTyCustomControl)
  private
    FMin, FMax, FValue: Double;
    FStartAngle, FSweepAngle: Integer;
    FTeeth: Integer;
    FShowValue: Boolean;
    FValueFormat: string;
    FStep: Double;
    FOnChange: TNotifyEvent;
    procedure SetMin(const AValue: Double);
    procedure SetMax(const AValue: Double);
    procedure SetValue(const AValue: Double);
    procedure SetStartAngle(const AValue: Integer);
    procedure SetSweepAngle(const AValue: Integer);
    procedure SetTeeth(const AValue: Integer);
    procedure SetShowValue(const AValue: Boolean);
    procedure SetValueFormat(const AValue: string);
    procedure ApplyValue(AValue: Double);   // clamp + Invalidate + fire OnChange on real change
    procedure DragToPoint(X, Y: Integer);
  protected
    FDragging: Boolean;
    function GetStyleTypeKey: string; override;   // 'TyGauge'
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Min: Double read FMin write SetMin;
    property Max: Double read FMax write SetMax;
    property Value: Double read FValue write SetValue;
    property StartAngle: Integer read FStartAngle write SetStartAngle default 135;
    property SweepAngle: Integer read FSweepAngle write SetSweepAngle default 270;
    property Teeth: Integer read FTeeth write SetTeeth default 12;
    property Step: Double read FStep write FStep;
    property ShowValue: Boolean read FShowValue write SetShowValue default False;
    property ValueFormat: string read FValueFormat write SetValueFormat;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property Font;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property TabStop default True;
  end;

implementation

function TyGearToothAngle(AIndex, ACount: Integer): Double;
begin
  if ACount <= 0 then Exit(0);
  Result := AIndex * 360 / ACount;
end;

{ TTyGearDial }

constructor TTyGearDial.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  FMin := 0;
  FMax := 100;
  FValue := 0;
  FStartAngle := 135;
  FSweepAngle := 270;
  FTeeth := 12;
  FShowValue := False;
  FValueFormat := '%.0f';
  FStep := 1;
  FDragging := False;
  Width := 76;
  Height := 76;
end;

function TTyGearDial.GetStyleTypeKey: string;
begin
  Result := 'TyGauge';
end;

procedure TTyGearDial.ApplyValue(AValue: Double);
var v: Double;
begin
  v := AValue;
  if v < FMin then v := FMin else if v > FMax then v := FMax;
  if FValue = v then Exit;      // no OnChange on a same-value set
  FValue := v;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyGearDial.DragToPoint(X, Y: Integer);
var c: TPoint;
begin
  c := Point(ClientWidth div 2, ClientHeight div 2);
  ApplyValue(TyDialValueFromAngle(Point(X, Y), c,
    FStartAngle, FSweepAngle, FMin, FMax));
end;

procedure TTyGearDial.SetMin(const AValue: Double);
begin
  if FMin = AValue then Exit;
  FMin := AValue;
  if FValue < FMin then FValue := FMin;
  Invalidate;
end;

procedure TTyGearDial.SetMax(const AValue: Double);
begin
  if FMax = AValue then Exit;
  FMax := AValue;
  if FValue > FMax then FValue := FMax;
  Invalidate;
end;

procedure TTyGearDial.SetValue(const AValue: Double);
begin
  // Programmatic set clamps + fires OnChange (only on a real change), like drag/wheel.
  ApplyValue(AValue);
end;

procedure TTyGearDial.SetStartAngle(const AValue: Integer);
begin if FStartAngle = AValue then Exit; FStartAngle := AValue; Invalidate; end;

procedure TTyGearDial.SetSweepAngle(const AValue: Integer);
begin if FSweepAngle = AValue then Exit; FSweepAngle := Math.Max(1, AValue); Invalidate; end;

procedure TTyGearDial.SetTeeth(const AValue: Integer);
begin if FTeeth = AValue then Exit; FTeeth := Math.Max(0, AValue); Invalidate; end;

procedure TTyGearDial.SetShowValue(const AValue: Boolean);
begin if FShowValue = AValue then Exit; FShowValue := AValue; Invalidate; end;

procedure TTyGearDial.SetValueFormat(const AValue: string);
begin if FValueFormat = AValue then Exit; FValueFormat := AValue; Invalidate; end;

procedure TTyGearDial.KeyDown(var Key: Word; Shift: TShiftState);
var stp: Double;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  stp := FStep;
  if stp <= 0 then stp := 1;
  case Key of
    VK_RIGHT, VK_UP:    begin ApplyValue(FValue + stp); Key := 0; end;
    VK_LEFT, VK_DOWN:   begin ApplyValue(FValue - stp); Key := 0; end;
    VK_PRIOR:           begin ApplyValue(FValue + stp * 10); Key := 0; end;   // PageUp
    VK_NEXT:            begin ApplyValue(FValue - stp * 10); Key := 0; end;   // PageDown
    VK_HOME:            begin ApplyValue(FMin); Key := 0; end;
    VK_END:             begin ApplyValue(FMax); Key := 0; end;
  end;
end;

procedure TTyGearDial.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    if TabStop and CanFocus then SetFocus;
    FDragging := True;
    DragToPoint(X, Y);
  end;
end;

procedure TTyGearDial.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseMove(Shift, X, Y);
  if FDragging then DragToPoint(X, Y);
end;

procedure TTyGearDial.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then FDragging := False;
end;

function TTyGearDial.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var stp: Double;
begin
  // Let the published OnMouseWheel/Up/Down events fire first; honor a handler
  // that marks the wheel handled and do not step.
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result then Exit;
  if not Enabled then Exit;
  stp := FStep;
  if stp <= 0 then stp := 1;
  // Wheel-up (WheelDelta > 0) increases; wheel-down decreases.
  ApplyValue(FValue + Sign(WheelDelta) * stp);
  Result := True;
end;

procedure TTyGearDial.Paint;
var
  P: TTyPainter;
  bodyS, pointerS: TTyStyleSet;
  R: TRect;
  ctx: TBGRACanvas2D;
  cx, cy, radius, ang, r0, r1, rimR, tipR, halfW: Double;
  frac, tAng, ca, sa: Double;
  bw, i: Integer;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ClientWidth, ClientHeight);
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    bodyS := CurrentStyle;                                              // TyGauge body/border/text
    pointerS := ActiveController.Model.ResolveStyle('TyGaugeFill', StyleClass, []);  // accent notch/hub

    // Windowed control (own HWND): fill the full rect with the parent/form background first, so
    // the square corners around the round gear show the form (or the image-theme photo), not the
    // HWND's white brush. Graphic siblings paint straight onto the form; a windowed control must
    // paint its own backdrop.
    TyFillParentBg(Self, P, R, bodyS);

    cx := (R.Left + R.Right) / 2;
    cy := (R.Top + R.Bottom) / 2;
    // Leave room for the protruding teeth (~P.Scale(6)) plus a small margin.
    radius := Math.Min(R.Right - R.Left, R.Bottom - R.Top) / 2 - P.Scale(8);
    if radius >= 4 then
    begin
      ctx := P.Bitmap.Canvas2D;
      ctx.lineCap := 'round';

      // Gear teeth: short radial trapezoids around the rim, in the body colour, drawn
      // first so the body circle sits on top of their inner ends.
      rimR := radius;                          // tooth root sits on the body rim
      tipR := radius + P.Scale(6);             // tooth tip protrudes outward
      halfW := DegToRad(360 / Math.Max(1, FTeeth) * 0.32);  // half angular width of a tooth
      ctx.fillStyle(TyColorToBGRA(bodyS.Background.Color));
      for i := 0 to FTeeth - 1 do
      begin
        tAng := DegToRad(TyGearToothAngle(i, FTeeth));
        ctx.beginPath;
        ctx.moveTo(cx + rimR * Cos(tAng - halfW), cy + rimR * Sin(tAng - halfW));
        ctx.lineTo(cx + tipR * Cos(tAng - halfW * 0.6), cy + tipR * Sin(tAng - halfW * 0.6));
        ctx.lineTo(cx + tipR * Cos(tAng + halfW * 0.6), cy + tipR * Sin(tAng + halfW * 0.6));
        ctx.lineTo(cx + rimR * Cos(tAng + halfW), cy + rimR * Sin(tAng + halfW));
        ctx.closePath;
        ctx.fill;
      end;

      // Gear body: filled circle in the face background.
      ctx.beginPath;
      ctx.arc(cx, cy, radius, 0, 2 * Pi, False);
      ctx.fillStyle(TyColorToBGRA(bodyS.Background.Color));
      ctx.fill;
      // Body rim border (theme border width/colour; falls back to text colour).
      bw := Math.Max(1, P.Scale(Math.Max(1, bodyS.BorderWidth)));
      ctx.lineWidth := bw;
      ctx.strokeStyle(TyColorToBGRA(bodyS.TextColor));
      ctx.beginPath;
      ctx.arc(cx, cy, radius - bw / 2, 0, 2 * Pi, False);
      ctx.stroke;

      // Inner circle (a concentric ring in the body/text colour for a machined look).
      ctx.lineWidth := Math.Max(1, P.Scale(1));
      ctx.strokeStyle(TyColorToBGRA(bodyS.TextColor));
      ctx.beginPath;
      ctx.arc(cx, cy, radius * 0.62, 0, 2 * Pi, False);
      ctx.stroke;

      // Accent pointer/notch from an inner radius out to the rim at the value angle.
      frac := TyGaugeFraction(FValue, FMin, FMax);
      ang := DegToRad(TyGaugeSweepEnd(FStartAngle, FSweepAngle, frac));
      ca := Cos(ang); sa := Sin(ang);
      r0 := radius * 0.30;
      r1 := Math.Max(r0 + P.Scale(2), radius - P.Scale(5));   // never point inward on tiny dials
      ctx.lineWidth := Math.Max(2, P.Scale(3));
      ctx.strokeStyle(TyColorToBGRA(pointerS.Background.Color));
      ctx.beginPath;
      ctx.moveTo(cx + r0 * ca, cy + r0 * sa);
      ctx.lineTo(cx + r1 * ca, cy + r1 * sa);
      ctx.stroke;

      // Hub: solid accent dot at the centre.
      ctx.fillStyle(TyColorToBGRA(pointerS.Background.Color));
      ctx.beginPath;
      ctx.arc(cx, cy, Math.Max(2, P.Scale(4)), 0, 2 * Pi, False);
      ctx.fill;
    end;

    if FShowValue then
      P.DrawText(R, Format(FValueFormat, [FValue]), Font.Name, 10, 700,
        bodyS.TextColor, taCenter, tlCenter, False);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
