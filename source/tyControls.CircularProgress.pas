unit tyControls.CircularProgress;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, ExtCtrls, LCLType,
  BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.StyleModel,
  tyControls.Animation, tyControls.Gauge;

type
  { A determinate RING progress indicator — the ring sibling of TTyProgressBar.
    Progress-familiar API (Position/Min/Max: Integer). Themed as itself —
    'TyCircularProgress' (track/text) and 'TyCircularProgressFill' (value ring) — for the
    same reason TTyProgressBar owns TyProgressBar/TyProgressFill rather than borrowing the
    gauge's: skins already pill or recolour the linear progress pair independently of
    gauges, and the ring must be able to follow them. Eases like TTyProgressBar. }
  TTyCustomCircularProgress = class(TTyGraphicControl)
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
    function GetStyleTypeKey: string; override;   // 'TyCircularProgress' (+ 'Fill' sub-part)
    procedure Paint; override;
    function DisplayFrac: Single;
    function AdvanceAnimation(AMs: Integer): Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Min: Integer read FMin write SetMin default 0;
    property Max: Integer read FMax write SetMax default 100;
    property Position: Integer read FPosition write SetPosition default 0;
    property Thickness: Integer read FThickness write SetThickness default 10;
    property ShowValue: Boolean read FShowValue write SetShowValue default True;
    property ValueFormat: string read FValueFormat write SetValueFormat;
    property AnimationsEnabled: Boolean read FAnimEnabled write FAnimEnabled default True;
  end;

  { TTyCircularProgress publishes TTyCustomCircularProgress's properties; everything lives in TTyCustomCircularProgress. }
  TTyCircularProgress = class(TTyCustomCircularProgress)
  published
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseWheel;
    property OnMouseWheelUp;
    property OnMouseWheelDown;
    property OnContextPopup;
    property OnResize;
    property OnChangeBounds;
    property AutoSize;
    property DragMode;
    property DragKind;
    property DragCursor;
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
    property OnMouseWheelHorz;
    property OnMouseWheelLeft;
    property OnMouseWheelRight;
    property OnShowHint;
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property ParentShowHint;
    property Action;
    property OnPaint;
    property StyleClass;
    property StyleOverride;
    property Controller;
    property Min;
    property Max;
    property Position;
    property Thickness;
    property ShowValue;
    property ValueFormat;
    property AnimationsEnabled;
    property Align;
    property Anchors;
  end;

implementation

constructor TTyCustomCircularProgress.Create(AOwner: TComponent);
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

destructor TTyCustomCircularProgress.Destroy;
begin
  FreeAndNil(FTimer);
  inherited Destroy;
end;

function TTyCustomCircularProgress.GetStyleTypeKey: string;
begin
  { Its own key, not the gauge's: this is "progress", and the library already ruled progress
    and gauge separately skinnable for the linear pair. Being able to pill TyProgressFill but
    not the ring was an inconsistency, not a design decision. }
  Result := 'TyCircularProgress';
end;

procedure TTyCustomCircularProgress.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 16;
    FTimer.OnTimer := @HandleTimer;
  end;
end;

procedure TTyCustomCircularProgress.HandleTimer(Sender: TObject);
begin
  if AdvanceAnimation(FTimer.Interval) then Invalidate;
  if not FPosAnim.Running then FTimer.Enabled := False;
end;

function TTyCustomCircularProgress.AdvanceAnimation(AMs: Integer): Boolean;
begin
  Result := FPosAnim.Advance(AMs);
end;

function TTyCustomCircularProgress.DisplayFrac: Single;
begin
  Result := TyLerpF(FAnimFrom, FAnimTo, FPosAnim.Eased);
end;

procedure TTyCustomCircularProgress.ArmTo(AFrac: Double);
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

procedure TTyCustomCircularProgress.SetMin(const AValue: Integer);
begin
  if FMin = AValue then Exit;
  FMin := AValue;
  if FPosition < FMin then FPosition := FMin;
  ArmTo(TyGaugeFraction(FPosition, FMin, FMax));
end;

procedure TTyCustomCircularProgress.SetMax(const AValue: Integer);
begin
  if FMax = AValue then Exit;
  FMax := AValue;
  if FPosition > FMax then FPosition := FMax;
  ArmTo(TyGaugeFraction(FPosition, FMin, FMax));
end;

procedure TTyCustomCircularProgress.SetPosition(const AValue: Integer);
var v: Integer;
begin
  v := AValue;
  if v < FMin then v := FMin else if v > FMax then v := FMax;
  if FPosition = v then Exit;
  FPosition := v;
  ArmTo(TyGaugeFraction(FPosition, FMin, FMax));
end;

procedure TTyCustomCircularProgress.SetThickness(const AValue: Integer);
begin
  if FThickness = AValue then Exit;
  FThickness := Math.Max(1, AValue);
  Invalidate;
end;

procedure TTyCustomCircularProgress.SetShowValue(const AValue: Boolean);
begin
  if FShowValue = AValue then Exit;
  FShowValue := AValue;
  Invalidate;
end;

procedure TTyCustomCircularProgress.SetValueFormat(const AValue: string);
begin
  if FValueFormat = AValue then Exit;
  FValueFormat := AValue;
  Invalidate;
end;

procedure TTyCustomCircularProgress.Paint;
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
    TyApplyStyleOpacity(Self, P, CurrentStyle);   // :disabled { opacity } — this control self-draws (no DrawFrame)
    trackS := CurrentStyle;                                              // TyCircularProgress track/text
    { Sub-part key derived from the box key so the two can never drift apart. }
    fillS := ActiveController.Model.ResolveStyle(GetStyleTypeKey + 'Fill', StyleClass, []);
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
      { A sixth of the ring, turned back into a LOGICAL size: the ring is device px and
        DrawText scales what it is given. See TTyGauge.DrawValueText. }
      P.DrawText(R, Format(FValueFormat, [pct]), Font.Name,
        Math.Max(9, MulDiv((R.Bottom - R.Top) div 6, 96, P.PPI)), 700, trackS.TextColor,
        taCenter, tlCenter, False);
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
