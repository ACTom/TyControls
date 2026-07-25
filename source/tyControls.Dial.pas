unit tyControls.Dial;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType, ExtCtrls,
  BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.StyleModel,
  tyControls.Animation, tyControls.Gauge;

{ Map a point APt (about ACenter) to a value in [AMin..AMax] along the arc that
  starts at AStartDeg and spans ASweepDeg (degrees, clockwise, 0 = east — the same
  convention as Canvas2D since y grows downward). The point's angle is normalized
  into the [AStartDeg .. AStartDeg+ASweepDeg] band; anything in the "dead" wedge
  outside the band clamps to the nearest end. Returns AMin when the sweep is
  degenerate (<= 0) or the range is empty. }
function TyDialValueFromAngle(const APt, ACenter: TPoint;
  AStartDeg, ASweepDeg, AMin, AMax: Double): Double;

type
  { An INTERACTIVE rotary knob: a round body with a pointer/notch from the centre
    to the rim at the value angle, plus an optional numeric readout. Drag around
    the centre, or use the wheel / arrow keys, to change Value. Themed as itself —
    'TyDial' (knob body/border/text) and 'TyDialPointer' (the notch). A knob is a
    physical-object metaphor (plastic/metal body, contrasting cap); the gauge's
    background token is a RECESSED TRACK colour, semantically wrong for a raised
    body, and a skin could not give the cap its own colour. Direct manipulation
    SNAPS (no ease) so the notch tracks the pointer and headless render tests stay
    pixel-stable. }
  TTyDial = class(TTyCustomControl)
  private
    FMin, FMax, FValue: Double;
    FStartAngle, FSweepAngle: Integer;
    FShowValue: Boolean;
    FValueFormat: string;
    FStep: Double;
    FOnChange: TNotifyEvent;
    procedure SetMin(const AValue: Double);
    procedure SetMax(const AValue: Double);
    procedure SetValue(const AValue: Double);
    procedure SetStartAngle(const AValue: Integer);
    procedure SetSweepAngle(const AValue: Integer);
    procedure SetShowValue(const AValue: Boolean);
    procedure SetValueFormat(const AValue: string);
    procedure ApplyValue(AValue: Double);   // clamp + Invalidate + fire OnChange on real change
    procedure DragToPoint(X, Y: Integer);
  protected
    FDragging: Boolean;
    function GetStyleTypeKey: string; override;   // 'TyDial' (+ 'Pointer' sub-part)
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

function TyDialValueFromAngle(const APt, ACenter: TPoint;
  AStartDeg, ASweepDeg, AMin, AMax: Double): Double;
var
  angDeg, rel, span, frac: Double;
begin
  if (ASweepDeg <= 0) or (AMax <= AMin) then Exit(AMin);
  // Angle of the point about the centre, degrees, 0 = east, clockwise (y down).
  angDeg := RadToDeg(ArcTan2(APt.Y - ACenter.Y, APt.X - ACenter.X));
  // Offset from the start of the sweep, normalized into [0, 360).
  rel := angDeg - AStartDeg;
  while rel < 0 do rel := rel + 360;
  while rel >= 360 do rel := rel - 360;
  span := ASweepDeg;
  if rel <= span then
    frac := rel / span
  else
  begin
    // In the dead wedge: snap to whichever end is angularly closer.
    if (rel - span) < (360 - rel) then frac := 1 else frac := 0;
  end;
  if frac < 0 then frac := 0 else if frac > 1 then frac := 1;
  Result := AMin + frac * (AMax - AMin);
end;

{ TTyDial }

constructor TTyDial.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  FMin := 0;
  FMax := 100;
  FValue := 0;
  FStartAngle := 135;
  FSweepAngle := 270;
  FShowValue := False;
  FValueFormat := '%.0f';
  FStep := 1;
  FDragging := False;
  Width := 72;
  Height := 72;
end;

function TTyDial.GetStyleTypeKey: string;
begin
  { Its own key, not the gauge's: a raised knob body and a sunk gauge track want opposite
    surface treatments, so a skin can now style the knob without touching every gauge. }
  Result := 'TyDial';
end;

procedure TTyDial.ApplyValue(AValue: Double);
var v: Double;
begin
  v := AValue;
  if v < FMin then v := FMin else if v > FMax then v := FMax;
  if FValue = v then Exit;      // no OnChange on a same-value set
  FValue := v;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyDial.DragToPoint(X, Y: Integer);
var c: TPoint;
begin
  c := Point(ClientWidth div 2, ClientHeight div 2);
  ApplyValue(TyDialValueFromAngle(Point(X, Y), c,
    FStartAngle, FSweepAngle, FMin, FMax));
end;

procedure TTyDial.SetMin(const AValue: Double);
begin
  if FMin = AValue then Exit;
  FMin := AValue;
  if FValue < FMin then FValue := FMin;
  Invalidate;
end;

procedure TTyDial.SetMax(const AValue: Double);
begin
  if FMax = AValue then Exit;
  FMax := AValue;
  if FValue > FMax then FValue := FMax;
  Invalidate;
end;

procedure TTyDial.SetValue(const AValue: Double);
begin
  // Programmatic set clamps + fires OnChange (only on a real change), like drag/wheel.
  ApplyValue(AValue);
end;

procedure TTyDial.SetStartAngle(const AValue: Integer);
begin if FStartAngle = AValue then Exit; FStartAngle := AValue; Invalidate; end;

procedure TTyDial.SetSweepAngle(const AValue: Integer);
begin if FSweepAngle = AValue then Exit; FSweepAngle := Math.Max(1, AValue); Invalidate; end;

procedure TTyDial.SetShowValue(const AValue: Boolean);
begin if FShowValue = AValue then Exit; FShowValue := AValue; Invalidate; end;

procedure TTyDial.SetValueFormat(const AValue: string);
begin if FValueFormat = AValue then Exit; FValueFormat := AValue; Invalidate; end;

procedure TTyDial.KeyDown(var Key: Word; Shift: TShiftState);
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

procedure TTyDial.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
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

procedure TTyDial.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseMove(Shift, X, Y);
  if FDragging then DragToPoint(X, Y);
end;

procedure TTyDial.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then FDragging := False;
end;

function TTyDial.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
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

procedure TTyDial.Paint;
var
  P: TTyPainter;
  bodyS, pointerS: TTyStyleSet;
  R: TRect;
  ctx: TBGRACanvas2D;
  cx, cy, radius, ang, r0, r1: Double;
  frac: Double;
  bw: Integer;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ClientWidth, ClientHeight);
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    TyApplyStyleOpacity(Self, P, CurrentStyle);   // :disabled { opacity } — this control self-draws (no DrawFrame)
    bodyS := CurrentStyle;                                              // TyDial body/border/text
    { Sub-part key derived from the box key so the two can never drift apart. }
    pointerS := ActiveController.Model.ResolveStyle(GetStyleTypeKey + 'Pointer', StyleClass, []);

    // Windowed control (own HWND): fill the full rect with the parent/form background first, so
    // the square corners around the round knob show the form (or the image-theme photo), not the
    // HWND's white brush. Graphic siblings (TTyMeter/TTyAnalogClock) get this free by painting
    // straight onto the form; a windowed control must paint its own backdrop.
    TyFillParentBg(Self, P, R, bodyS);

    cx := (R.Left + R.Right) / 2;
    cy := (R.Top + R.Bottom) / 2;
    radius := Math.Min(R.Right - R.Left, R.Bottom - R.Top) / 2 - P.Scale(4);
    if radius >= 4 then
    begin
      ctx := P.Bitmap.Canvas2D;
      ctx.lineCap := 'round';

      // Knob body: filled circle in the face background.
      ctx.beginPath;
      ctx.arc(cx, cy, radius, 0, 2 * Pi, False);
      ctx.fillStyle(TyColorToBGRA(bodyS.Background.Color));
      ctx.fill;
      // Subtle body border: theme border WIDTH but the text colour, so the rim is chained to
      // the label colour and TyDial's own border-color is unreachable. Left as-is here because
      // this pass is a pure key split and must not move a pixel; switching the stroke to
      // bodyS.BorderColor is a separate, deliberate visual change.
      bw := Math.Max(1, P.Scale(Math.Max(1, bodyS.BorderWidth)));
      ctx.lineWidth := bw;
      ctx.strokeStyle(TyColorToBGRA(bodyS.TextColor));
      ctx.beginPath;
      ctx.arc(cx, cy, radius - bw / 2, 0, 2 * Pi, False);
      ctx.stroke;

      // Pointer/notch from an inner radius out to the rim at the value angle.
      frac := TyGaugeFraction(FValue, FMin, FMax);
      ang := DegToRad(TyGaugeSweepEnd(FStartAngle, FSweepAngle, frac));
      r0 := radius * 0.35;
      r1 := radius - P.Scale(6);
      ctx.lineWidth := Math.Max(2, P.Scale(3));
      ctx.strokeStyle(TyColorToBGRA(pointerS.Background.Color));
      ctx.beginPath;
      ctx.moveTo(cx + r0 * Cos(ang), cy + r0 * Sin(ang));
      ctx.lineTo(cx + r1 * Cos(ang), cy + r1 * Sin(ang));
      ctx.stroke;
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
