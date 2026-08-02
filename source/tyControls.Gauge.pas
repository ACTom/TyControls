unit tyControls.Gauge;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, ExtCtrls,
  BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.StyleModel,
  tyControls.Animation;

type
  { Bar (horizontal/vertical), open arc, or full ring. The arc/ring styles sweep
    FStartAngle..FStartAngle+FSweepAngle (degrees, clockwise, 0 = east). }
  TTyGaugeStyle = (gsLinearH, gsLinearV, gsArc, gsRing);

{ Clamped normalized position: (Value-Min)/(Max-Min) in [0,1]; 0 when Max<=Min. }
function TyGaugeFraction(AValue, AMin, AMax: Double): Double;
{ End angle of the value sweep: AStartDeg + ASweepDeg*AFrac. }
function TyGaugeSweepEnd(AStartDeg, ASweepDeg, AFrac: Double): Double;
{ Left-anchored (H) / bottom-anchored (V) fill rect for the linear styles. }
function TyGaugeLinearFill(const ATrack: TRect; AFrac: Double; AVertical: Boolean): TRect;

type
  TTyGauge = class(TTyGraphicControl)
  private
    FMin, FMax, FValue: Double;
    FStyle: TTyGaugeStyle;
    FShowValue: Boolean;
    FValueFormat: string;
    FThickness, FStartAngle, FSweepAngle: Integer;
    FAnimEnabled: Boolean;
    FPosAnim: TTyAnimator;      // 0..1 traversal driving FAnimFrom -> FAnimTo (fraction units)
    FAnimFrom, FAnimTo: Single; // displayed-fraction endpoints
    FTimer: TTimer;             // lazy; only created when actually animating
    procedure SetMin(const AValue: Double);
    procedure SetMax(const AValue: Double);
    procedure SetValue(const AValue: Double);
    procedure SetStyle(const AValue: TTyGaugeStyle);
    procedure SetShowValue(const AValue: Boolean);
    procedure SetValueFormat(const AValue: string);
    procedure SetThickness(const AValue: Integer);
    procedure SetStartAngle(const AValue: Integer);
    procedure SetSweepAngle(const AValue: Integer);
    procedure ArmTo(AFrac: Double);       // clamp target + animate/snap per handle state
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
    procedure DrawValueText(P: TTyPainter; const R: TRect; AColor: TTyColor);
    procedure DrawLinear(P: TTyPainter; const R: TRect; AFrac: Double; const ATrackS, AFillS: TTyStyleSet);
    procedure DrawArc(P: TTyPainter; const R: TRect; AFrac: Double; const ATrackS, AFillS: TTyStyleSet);
  protected
    function GetStyleTypeKey: string; override;   // 'TyGauge'
    procedure Paint; override;
    function DisplayFrac: Single;                  // eased displayed fraction (== target at rest)
    function AdvanceAnimation(AMs: Integer): Boolean;   // steppable seam (no wall-clock)
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Min: Double read FMin write SetMin;
    property Max: Double read FMax write SetMax;
    property Value: Double read FValue write SetValue;
    property Style: TTyGaugeStyle read FStyle write SetStyle default gsArc;
    property ShowValue: Boolean read FShowValue write SetShowValue default True;
    property ValueFormat: string read FValueFormat write SetValueFormat;
    property Thickness: Integer read FThickness write SetThickness default 12;
    property StartAngle: Integer read FStartAngle write SetStartAngle default 135;
    property SweepAngle: Integer read FSweepAngle write SetSweepAngle default 270;
    property AnimationsEnabled: Boolean read FAnimEnabled write FAnimEnabled default True;
    property Font;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

function TyGaugeFraction(AValue, AMin, AMax: Double): Double;
begin
  if AMax <= AMin then Exit(0);
  Result := (AValue - AMin) / (AMax - AMin);
  if Result < 0 then Result := 0
  else if Result > 1 then Result := 1;
end;

function TyGaugeSweepEnd(AStartDeg, ASweepDeg, AFrac: Double): Double;
begin
  Result := AStartDeg + ASweepDeg * AFrac;
end;

function TyGaugeLinearFill(const ATrack: TRect; AFrac: Double; AVertical: Boolean): TRect;
var w, h: Integer;
begin
  Result := ATrack;
  if AFrac < 0 then AFrac := 0 else if AFrac > 1 then AFrac := 1;
  if AVertical then
  begin
    h := ATrack.Bottom - ATrack.Top;
    Result.Top := ATrack.Bottom - Round(h * AFrac);   // bottom-anchored
  end
  else
  begin
    w := ATrack.Right - ATrack.Left;
    Result.Right := ATrack.Left + Round(w * AFrac);    // left-anchored
  end;
end;

{ TTyGauge }

constructor TTyGauge.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { An instrument has no caption. Caption used to be PUBLISHED here and grep found exactly
    one hit -- that declaration; Paint never read it, so the Object Inspector offered a
    knob the control ignored. Unpublished, and csSetCaption dropped with it so a gauge
    stops acquiring its own Name as invisible caption text and streaming it into the .lfm
    for nothing. LCL's industrial family drops csSetCaption for the same reason. }
  ControlStyle := ControlStyle - [csSetCaption];
  FMin := 0;
  FMax := 100;
  FValue := 0;
  FStyle := gsArc;
  FShowValue := True;
  FValueFormat := '%.0f';
  FThickness := 12;
  FStartAngle := 135;
  FSweepAngle := 270;
  FAnimEnabled := True;
  FPosAnim.Progress := 1;
  FPosAnim.Target := 1;
  FPosAnim.DurationMs := 240;
  FPosAnim.Easing := teEaseOutCubic;
  FAnimFrom := 0;
  FAnimTo := 0;
  Width := 120;
  Height := 120;
end;

destructor TTyGauge.Destroy;
begin
  FreeAndNil(FTimer);   // stop the callback before teardown
  inherited Destroy;
end;

function TTyGauge.GetStyleTypeKey: string;
begin
  Result := 'TyGauge';
end;

procedure TTyGauge.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 16;
    FTimer.OnTimer := @HandleTimer;
  end;
end;

procedure TTyGauge.HandleTimer(Sender: TObject);
begin
  if AdvanceAnimation(FTimer.Interval) then Invalidate;
  if not FPosAnim.Running then FTimer.Enabled := False;
end;

function TTyGauge.AdvanceAnimation(AMs: Integer): Boolean;
begin
  Result := FPosAnim.Advance(AMs);
end;

function TTyGauge.DisplayFrac: Single;
begin
  Result := TyLerpF(FAnimFrom, FAnimTo, FPosAnim.Eased);
end;

procedure TTyGauge.ArmTo(AFrac: Double);
begin
  if AFrac < 0 then AFrac := 0 else if AFrac > 1 then AFrac := 1;
  { A graphic control paints onto its parent; "has a window to animate into" means
    the parent handle is allocated. Headless render tests parent to an unshown form
    (no handle) -> snap, keeping exact-pixel tests stable. }
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

procedure TTyGauge.SetMin(const AValue: Double);
begin
  if FMin = AValue then Exit;
  FMin := AValue;
  ArmTo(TyGaugeFraction(FValue, FMin, FMax));
end;

procedure TTyGauge.SetMax(const AValue: Double);
begin
  if FMax = AValue then Exit;
  FMax := AValue;
  ArmTo(TyGaugeFraction(FValue, FMin, FMax));
end;

procedure TTyGauge.SetValue(const AValue: Double);
var v: Double;
begin
  v := AValue;
  if v < FMin then v := FMin else if v > FMax then v := FMax;
  if FValue = v then Exit;
  FValue := v;
  ArmTo(TyGaugeFraction(FValue, FMin, FMax));
end;

procedure TTyGauge.SetStyle(const AValue: TTyGaugeStyle);
begin
  if FStyle = AValue then Exit;
  FStyle := AValue;
  Invalidate;
end;

procedure TTyGauge.SetShowValue(const AValue: Boolean);
begin
  if FShowValue = AValue then Exit;
  FShowValue := AValue;
  Invalidate;
end;

procedure TTyGauge.SetValueFormat(const AValue: string);
begin
  if FValueFormat = AValue then Exit;
  FValueFormat := AValue;
  Invalidate;
end;

procedure TTyGauge.SetThickness(const AValue: Integer);
begin
  if FThickness = AValue then Exit;
  FThickness := Math.Max(1, AValue);
  Invalidate;
end;

procedure TTyGauge.SetStartAngle(const AValue: Integer);
begin
  if FStartAngle = AValue then Exit;
  FStartAngle := AValue;
  Invalidate;
end;

procedure TTyGauge.SetSweepAngle(const AValue: Integer);
begin
  if FSweepAngle = AValue then Exit;
  FSweepAngle := AValue;
  Invalidate;
end;

procedure TTyGauge.DrawValueText(P: TTyPainter; const R: TRect; AColor: TTyColor);
var fs: Integer;
begin
  if not FShowValue then Exit;
  fs := Math.Max(9, (R.Bottom - R.Top) div 6);
  P.DrawText(R, Format(FValueFormat, [FValue]), Font.Name, fs, 700, AColor,
    taCenter, tlCenter, False);
end;

procedure TTyGauge.DrawLinear(P: TTyPainter; const R: TRect; AFrac: Double;
  const ATrackS, AFillS: TTyStyleSet);
var bw: Integer; trackR, fillR: TRect;
begin
  DrawFrame(P, R, ATrackS);   // track background + border
  bw := P.Scale(ATrackS.BorderWidth);
  trackR := Rect(R.Left + bw, R.Top + bw, R.Right - bw, R.Bottom - bw);
  fillR := TyGaugeLinearFill(trackR, AFrac, FStyle = gsLinearV);
  if (fillR.Right > fillR.Left) and (fillR.Bottom > fillR.Top) then
    P.FillBackground(fillR, AFillS.Background, TyUniformCorners(AFillS.BorderRadius));
  DrawValueText(P, R, ATrackS.TextColor);
end;

procedure TTyGauge.DrawArc(P: TTyPainter; const R: TRect; AFrac: Double;
  const ATrackS, AFillS: TTyStyleSet);
var
  ctx: TBGRACanvas2D;
  cx, cy, radius: Double;
  th, startDeg, sweepDeg: Integer;
begin
  th := P.Scale(FThickness);
  cx := (R.Left + R.Right) / 2;
  cy := (R.Top + R.Bottom) / 2;
  radius := (Math.Min(R.Right - R.Left, R.Bottom - R.Top) - th) / 2;
  if radius < 1 then Exit;
  if FStyle = gsRing then
  begin
    startDeg := -90;      // top
    sweepDeg := 360;      // full circle
  end
  else
  begin
    startDeg := FStartAngle;
    sweepDeg := FSweepAngle;
  end;
  ctx := P.Bitmap.Canvas2D;
  ctx.lineWidth := th;
  ctx.lineCap := 'round';
  // track arc
  ctx.beginPath;
  ctx.arc(cx, cy, radius, DegToRad(startDeg), DegToRad(startDeg + sweepDeg), False);
  ctx.strokeStyle(TyColorToBGRA(ATrackS.Background.Color));
  ctx.stroke;
  // value arc
  if AFrac > 0 then
  begin
    ctx.beginPath;
    ctx.arc(cx, cy, radius, DegToRad(startDeg),
      DegToRad(TyGaugeSweepEnd(startDeg, sweepDeg, AFrac)), False);
    ctx.strokeStyle(TyColorToBGRA(AFillS.Background.Color));
    ctx.stroke;
  end;
  DrawValueText(P, R, ATrackS.TextColor);
end;

procedure TTyGauge.Paint;
var
  P: TTyPainter;
  trackS, fillS: TTyStyleSet;
  R: TRect;
  frac: Double;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ClientWidth, ClientHeight);
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    trackS := CurrentStyle;                                       // TyGauge: track/text
    fillS := ActiveController.Model.ResolveStyle('TyGaugeFill', StyleClass, []);  // value fill
    frac := DisplayFrac;
    case FStyle of
      gsLinearH, gsLinearV: DrawLinear(P, R, frac, trackS, fillS);
    else
      DrawArc(P, R, frac, trackS, fillS);
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
