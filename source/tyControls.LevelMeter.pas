unit tyControls.LevelMeter;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, ExtCtrls,
  BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.StyleModel,
  tyControls.Animation, tyControls.Gauge;

type
  { Fill direction of the level bar. Horizontal fills left->right; vertical fills bottom->top. }
  TTyLevelOrientation = (loHorizontal, loVertical);

{ How many of ASegments are lit at fraction AFrac: ceil(AFrac*ASegments) clamped to 0..ASegments.
  ASegments <= 0 -> 0 (continuous mode has no discrete segments). }
function TyLevelSegmentsLit(AFrac: Double; ASegments: Integer): Integer;

type
  { A VU / level bar (audio-style). A track rounded-rect with an accent-coloured lit
    portion up to Value (either a single smooth fill or N gap-separated segments), and an
    optional thin peak-hold marker at the highest value seen. Leaf TTyGraphicControl.
    Reuses the gauge theming (typeKey 'TyGauge' for the track/text, 'TyGaugeFill' for the
    lit accent) so no extra .tycss rules; eased value movement (snaps headless). }
  TTyLevelMeter = class(TTyGraphicControl)
  private
    FMin, FMax, FValue: Double;
    FOrientation: TTyLevelOrientation;
    FSegments: Integer;
    FPeakHold: Boolean;
    FPeakFrac: Double;              // highest fraction seen (peak-hold marker position)
    FShowValue: Boolean;
    FValueFormat: string;
    FAnimEnabled: Boolean;
    FPosAnim: TTyAnimator;          // 0..1 traversal driving FAnimFrom -> FAnimTo (fraction units)
    FAnimFrom, FAnimTo: Single;     // displayed-fraction endpoints
    FTimer: TTimer;                 // lazy; only created when actually animating
    procedure SetMin(const AValue: Double);
    procedure SetMax(const AValue: Double);
    procedure SetValue(const AValue: Double);
    procedure SetOrientation(const AValue: TTyLevelOrientation);
    procedure SetSegments(const AValue: Integer);
    procedure SetPeakHold(const AValue: Boolean);
    procedure SetShowValue(const AValue: Boolean);
    procedure SetValueFormat(const AValue: string);
    procedure ArmTo(AFrac: Double);       // clamp target + animate/snap per handle state
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
    procedure DrawContinuous(P: TTyPainter; const ATrack: TRect; AFrac: Double; const AFillS: TTyStyleSet);
    procedure DrawSegments(P: TTyPainter; const ATrack: TRect; AFrac: Double; const AFillS: TTyStyleSet);
    procedure DrawPeak(P: TTyPainter; const ATrack: TRect; APeak: Double; AColor: TTyColor);
  protected
    function GetStyleTypeKey: string; override;   // 'TyGauge'
    procedure Paint; override;
    function DisplayFrac: Single;                  // eased displayed fraction (== target at rest)
    function AdvanceAnimation(AMs: Integer): Boolean;   // steppable seam (no wall-clock)
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Clear the peak-hold marker back to the current value. }
    procedure ResetPeak;
  published
    property Min: Double read FMin write SetMin;
    property Max: Double read FMax write SetMax;
    property Value: Double read FValue write SetValue;
    property Orientation: TTyLevelOrientation read FOrientation write SetOrientation default loHorizontal;
    property Segments: Integer read FSegments write SetSegments default 0;
    property PeakHold: Boolean read FPeakHold write SetPeakHold default False;
    property ShowValue: Boolean read FShowValue write SetShowValue default False;
    property ValueFormat: string read FValueFormat write SetValueFormat;
    property AnimationsEnabled: Boolean read FAnimEnabled write FAnimEnabled default True;
    property Font;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

function TyLevelSegmentsLit(AFrac: Double; ASegments: Integer): Integer;
begin
  if ASegments <= 0 then Exit(0);
  if AFrac < 0 then AFrac := 0 else if AFrac > 1 then AFrac := 1;
  Result := Ceil(AFrac * ASegments);
  if Result < 0 then Result := 0
  else if Result > ASegments then Result := ASegments;
end;

{ TTyLevelMeter }

constructor TTyLevelMeter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMin := 0;
  FMax := 100;
  FValue := 0;
  FOrientation := loHorizontal;
  FSegments := 0;
  FPeakHold := False;
  FPeakFrac := 0;
  FShowValue := False;
  FValueFormat := '%.0f';
  FAnimEnabled := True;
  FPosAnim.Progress := 1;
  FPosAnim.Target := 1;
  FPosAnim.DurationMs := 200;
  FPosAnim.Easing := teEaseOutCubic;
  FAnimFrom := 0;
  FAnimTo := 0;
  Width := 180;
  Height := 24;
end;

destructor TTyLevelMeter.Destroy;
begin
  FreeAndNil(FTimer);   // stop the callback before teardown
  inherited Destroy;
end;

function TTyLevelMeter.GetStyleTypeKey: string;
begin
  Result := 'TyGauge';
end;

procedure TTyLevelMeter.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 16;
    FTimer.OnTimer := @HandleTimer;
  end;
end;

procedure TTyLevelMeter.HandleTimer(Sender: TObject);
begin
  if AdvanceAnimation(FTimer.Interval) then Invalidate;
  if not FPosAnim.Running then FTimer.Enabled := False;
end;

function TTyLevelMeter.AdvanceAnimation(AMs: Integer): Boolean;
begin
  Result := FPosAnim.Advance(AMs);
end;

function TTyLevelMeter.DisplayFrac: Single;
begin
  Result := TyLerpF(FAnimFrom, FAnimTo, FPosAnim.Eased);
end;

procedure TTyLevelMeter.ArmTo(AFrac: Double);
begin
  if AFrac < 0 then AFrac := 0 else if AFrac > 1 then AFrac := 1;
  { Peak-hold: remember the highest fraction; it only rises (until ResetPeak). }
  if FPeakHold and (AFrac > FPeakFrac) then FPeakFrac := AFrac;
  { A graphic control paints onto its parent; "has a window to animate into" means the
    parent handle is allocated. Headless render tests parent to an unshown form (no handle)
    -> snap, keeping exact-pixel tests stable. }
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

procedure TTyLevelMeter.ResetPeak;
begin
  FPeakFrac := TyGaugeFraction(FValue, FMin, FMax);
  Invalidate;
end;

procedure TTyLevelMeter.SetMin(const AValue: Double);
begin
  if FMin = AValue then Exit;
  FMin := AValue;
  ArmTo(TyGaugeFraction(FValue, FMin, FMax));
end;

procedure TTyLevelMeter.SetMax(const AValue: Double);
begin
  if FMax = AValue then Exit;
  FMax := AValue;
  ArmTo(TyGaugeFraction(FValue, FMin, FMax));
end;

procedure TTyLevelMeter.SetValue(const AValue: Double);
var v: Double;
begin
  v := AValue;
  if v < FMin then v := FMin else if v > FMax then v := FMax;
  if FValue = v then Exit;
  FValue := v;
  ArmTo(TyGaugeFraction(FValue, FMin, FMax));
end;

procedure TTyLevelMeter.SetOrientation(const AValue: TTyLevelOrientation);
begin
  if FOrientation = AValue then Exit;
  FOrientation := AValue;
  Invalidate;
end;

procedure TTyLevelMeter.SetSegments(const AValue: Integer);
begin
  if FSegments = AValue then Exit;
  FSegments := Math.Max(0, AValue);
  Invalidate;
end;

procedure TTyLevelMeter.SetPeakHold(const AValue: Boolean);
begin
  if FPeakHold = AValue then Exit;
  FPeakHold := AValue;
  if FPeakHold then FPeakFrac := TyGaugeFraction(FValue, FMin, FMax);
  Invalidate;
end;

procedure TTyLevelMeter.SetShowValue(const AValue: Boolean);
begin
  if FShowValue = AValue then Exit;
  FShowValue := AValue;
  Invalidate;
end;

procedure TTyLevelMeter.SetValueFormat(const AValue: string);
begin
  if FValueFormat = AValue then Exit;
  FValueFormat := AValue;
  Invalidate;
end;

procedure TTyLevelMeter.DrawContinuous(P: TTyPainter; const ATrack: TRect;
  AFrac: Double; const AFillS: TTyStyleSet);
var fillR: TRect;
begin
  { Reuse the gauge's left-anchored (H) / bottom-anchored (V) linear fill geometry. }
  fillR := TyGaugeLinearFill(ATrack, AFrac, FOrientation = loVertical);
  if (fillR.Right > fillR.Left) and (fillR.Bottom > fillR.Top) then
    P.FillBackground(fillR, AFillS.Background, TyUniformCorners(AFillS.BorderRadius));
end;

procedure TTyLevelMeter.DrawSegments(P: TTyPainter; const ATrack: TRect;
  AFrac: Double; const AFillS: TTyStyleSet);
var
  lit, i, gap, spanW, spanH, segLen, ofs: Integer;
  segR: TRect;
begin
  lit := TyLevelSegmentsLit(AFrac, FSegments);
  if lit <= 0 then Exit;
  gap := Math.Max(1, P.Scale(2));
  if FOrientation = loVertical then
  begin
    spanH := (ATrack.Bottom - ATrack.Top) - gap * (FSegments - 1);
    if spanH < FSegments then spanH := FSegments;
    segLen := spanH div FSegments;
    if segLen < 1 then segLen := 1;
    for i := 0 to lit - 1 do
    begin
      // bottom-anchored: segment 0 sits at the bottom
      ofs := ATrack.Bottom - (i + 1) * segLen - i * gap;
      segR := Rect(ATrack.Left, ofs, ATrack.Right, ofs + segLen);
      P.FillBackground(segR, AFillS.Background, TyUniformCorners(AFillS.BorderRadius));
    end;
  end
  else
  begin
    spanW := (ATrack.Right - ATrack.Left) - gap * (FSegments - 1);
    if spanW < FSegments then spanW := FSegments;
    segLen := spanW div FSegments;
    if segLen < 1 then segLen := 1;
    for i := 0 to lit - 1 do
    begin
      // left-anchored: segment 0 sits at the left
      ofs := ATrack.Left + i * (segLen + gap);
      segR := Rect(ofs, ATrack.Top, ofs + segLen, ATrack.Bottom);
      P.FillBackground(segR, AFillS.Background, TyUniformCorners(AFillS.BorderRadius));
    end;
  end;
end;

procedure TTyLevelMeter.DrawPeak(P: TTyPainter; const ATrack: TRect;
  APeak: Double; AColor: TTyColor);
var
  ctx: TBGRACanvas2D;
  pos: Integer;
  lw: Double;
begin
  if APeak < 0 then Exit;   // peak==0 still draws a marker at the low edge
  if APeak > 1 then APeak := 1;
  ctx := P.Bitmap.Canvas2D;
  lw := Math.Max(2, P.Scale(2));
  ctx.lineWidth := lw;
  ctx.lineCap := 'round';
  ctx.strokeStyle(TyColorToBGRA(AColor));
  ctx.beginPath;
  if FOrientation = loVertical then
  begin
    // marker line spans the track width at the peak height (bottom-anchored)
    pos := ATrack.Bottom - Round((ATrack.Bottom - ATrack.Top) * APeak);
    ctx.moveTo(ATrack.Left, pos);
    ctx.lineTo(ATrack.Right, pos);
  end
  else
  begin
    // marker line spans the track height at the peak position (left-anchored)
    pos := ATrack.Left + Round((ATrack.Right - ATrack.Left) * APeak);
    ctx.moveTo(pos, ATrack.Top);
    ctx.lineTo(pos, ATrack.Bottom);
  end;
  ctx.stroke;
end;

procedure TTyLevelMeter.Paint;
var
  P: TTyPainter;
  trackS, fillS: TTyStyleSet;
  R, trackR: TRect;
  frac: Double;
  bw: Integer;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ClientWidth, ClientHeight);
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    trackS := CurrentStyle;                                       // TyGauge: track/text
    fillS := ActiveController.Model.ResolveStyle('TyGaugeFill', StyleClass, []);  // lit accent
    frac := DisplayFrac;

    DrawFrame(P, R, trackS);   // track background + border
    bw := P.Scale(trackS.BorderWidth);
    trackR := Rect(R.Left + bw, R.Top + bw, R.Right - bw, R.Bottom - bw);

    if (trackR.Right > trackR.Left) and (trackR.Bottom > trackR.Top) then
    begin
      if FSegments > 0 then
        DrawSegments(P, trackR, frac, fillS)
      else
        DrawContinuous(P, trackR, frac, fillS);
      if FPeakHold then
        DrawPeak(P, trackR, FPeakFrac, fillS.Background.Color);
    end;

    if FShowValue then
      P.DrawText(R, Format(FValueFormat, [FValue]), Font.Name, 10, 700,
        trackS.TextColor, taCenter, tlCenter, False);

    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
