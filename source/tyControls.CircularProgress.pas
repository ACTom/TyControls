unit tyControls.CircularProgress;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, ExtCtrls,
  BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.StyleModel,
  tyControls.Animation, tyControls.Gauge;

type
  { A determinate RING progress indicator — the ring sibling of TTyProgressBar.
    Progress-familiar API (Position/Min/Max: Integer). Reuses the gauge theming
    (typeKey 'TyGauge' for the track/text, 'TyGaugeFill' for the value ring) so it
    tracks the same accent with no extra .tycss rules, and eases like TTyProgressBar. }
  TTyCircularProgress = class(TTyGraphicControl)
  private
    FMin, FMax, FPosition: Integer;
    FThickness: Integer;
    FShowValue: Boolean;
    FValueFormat: string;
    FAnimEnabled: Boolean;
    FPosAnim: TTyAnimator;
    FAnimFrom, FAnimTo: Single;   // displayed-fraction endpoints
    FTimer: TTimer;
    procedure SetMin(const AValue: Integer);
    procedure SetMax(const AValue: Integer);
    procedure SetPosition(const AValue: Integer);
    procedure SetThickness(const AValue: Integer);
    procedure SetShowValue(const AValue: Boolean);
    procedure SetValueFormat(const AValue: string);
    procedure ArmTo(AFrac: Double);
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
  protected
    function GetStyleTypeKey: string; override;   // reuse 'TyGauge'
    procedure Paint; override;
    function DisplayFrac: Single;
    function AdvanceAnimation(AMs: Integer): Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Min: Integer read FMin write SetMin default 0;
    property Max: Integer read FMax write SetMax default 100;
    property Position: Integer read FPosition write SetPosition default 0;
    property Thickness: Integer read FThickness write SetThickness default 10;
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

constructor TTyCircularProgress.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMin := 0;
  FMax := 100;
  FPosition := 0;
  FThickness := 10;
  FShowValue := True;
  FValueFormat := '%.0f%%';
  FAnimEnabled := True;
  FPosAnim.Progress := 1;
  FPosAnim.Target := 1;
  FPosAnim.DurationMs := 240;
  FPosAnim.Easing := teEaseOutCubic;
  FAnimFrom := 0;
  FAnimTo := 0;
  Width := 96;
  Height := 96;
end;

destructor TTyCircularProgress.Destroy;
begin
  FreeAndNil(FTimer);
  inherited Destroy;
end;

function TTyCircularProgress.GetStyleTypeKey: string;
begin
  Result := 'TyGauge';   // reuse the gauge's track/text style
end;

procedure TTyCircularProgress.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 16;
    FTimer.OnTimer := @HandleTimer;
  end;
end;

procedure TTyCircularProgress.HandleTimer(Sender: TObject);
begin
  if AdvanceAnimation(FTimer.Interval) then Invalidate;
  if not FPosAnim.Running then FTimer.Enabled := False;
end;

function TTyCircularProgress.AdvanceAnimation(AMs: Integer): Boolean;
begin
  Result := FPosAnim.Advance(AMs);
end;

function TTyCircularProgress.DisplayFrac: Single;
begin
  Result := TyLerpF(FAnimFrom, FAnimTo, FPosAnim.Eased);
end;

procedure TTyCircularProgress.ArmTo(AFrac: Double);
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

procedure TTyCircularProgress.SetMin(const AValue: Integer);
begin
  if FMin = AValue then Exit;
  FMin := AValue;
  if FPosition < FMin then FPosition := FMin;
  ArmTo(TyGaugeFraction(FPosition, FMin, FMax));
end;

procedure TTyCircularProgress.SetMax(const AValue: Integer);
begin
  if FMax = AValue then Exit;
  FMax := AValue;
  if FPosition > FMax then FPosition := FMax;
  ArmTo(TyGaugeFraction(FPosition, FMin, FMax));
end;

procedure TTyCircularProgress.SetPosition(const AValue: Integer);
var v: Integer;
begin
  v := AValue;
  if v < FMin then v := FMin else if v > FMax then v := FMax;
  if FPosition = v then Exit;
  FPosition := v;
  ArmTo(TyGaugeFraction(FPosition, FMin, FMax));
end;

procedure TTyCircularProgress.SetThickness(const AValue: Integer);
begin
  if FThickness = AValue then Exit;
  FThickness := Math.Max(1, AValue);
  Invalidate;
end;

procedure TTyCircularProgress.SetShowValue(const AValue: Boolean);
begin
  if FShowValue = AValue then Exit;
  FShowValue := AValue;
  Invalidate;
end;

procedure TTyCircularProgress.SetValueFormat(const AValue: string);
begin
  if FValueFormat = AValue then Exit;
  FValueFormat := AValue;
  Invalidate;
end;

procedure TTyCircularProgress.Paint;
var
  P: TTyPainter;
  trackS, fillS: TTyStyleSet;
  R: TRect;
  ctx: TBGRACanvas2D;
  frac: Double;
  cx, cy, radius: Double;
  th: Integer;
  pct: Double;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ClientWidth, ClientHeight);
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    trackS := CurrentStyle;                                              // TyGauge track/text
    fillS := ActiveController.Model.ResolveStyle('TyGaugeFill', StyleClass, []);
    frac := DisplayFrac;

    th := P.Scale(FThickness);
    cx := (R.Left + R.Right) / 2;
    cy := (R.Top + R.Bottom) / 2;
    radius := (Math.Min(R.Right - R.Left, R.Bottom - R.Top) - th) / 2;
    if radius >= 1 then
    begin
      ctx := P.Bitmap.Canvas2D;
      ctx.lineWidth := th;
      ctx.lineCap := 'round';
      // track ring (full circle from top)
      ctx.beginPath;
      ctx.arc(cx, cy, radius, DegToRad(-90), DegToRad(270), False);
      ctx.strokeStyle(TyColorToBGRA(trackS.Background.Color));
      ctx.stroke;
      // value ring (from top, clockwise by fraction)
      if frac > 0 then
      begin
        ctx.beginPath;
        ctx.arc(cx, cy, radius, DegToRad(-90), DegToRad(-90 + 360 * frac), False);
        ctx.strokeStyle(TyColorToBGRA(fillS.Background.Color));
        ctx.stroke;
      end;
    end;

    if FShowValue then
    begin
      pct := TyGaugeFraction(FPosition, FMin, FMax) * 100;
      P.DrawText(R, Format(FValueFormat, [pct]), Font.Name,
        Math.Max(9, (R.Bottom - R.Top) div 6), 700, trackS.TextColor,
        taCenter, tlCenter, False);
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
