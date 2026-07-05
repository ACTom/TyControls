unit tyControls.ActivityIndicator;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, ExtCtrls,
  BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.StyleModel;

{ Advance a rotation (degrees) by AMs of a APeriodMs full turn, wrapped to [0,360). }
function TyActivityAdvance(ACurrentDeg: Double; AMs, APeriodMs: Integer): Double;

type
  { An INDETERMINATE spinner — a faint track ring under a continuously rotating accent
    arc (a spinning "C"). No value; `Active` starts/stops the spin. Reuses the gauge
    theming (typeKey 'TyGauge' track + 'TyGaugeFill' accent), so no extra .tycss rules.
    Spins only when Active AND painted (has a parent handle); headless it is static. }
  TTyActivityIndicator = class(TTyGraphicControl)
  private
    FActive: Boolean;
    FThickness: Integer;
    FSweep: Integer;      // accent arc length (degrees)
    FAngle: Double;       // current rotation start (degrees)
    FTimer: TTimer;
    procedure SetActive(const AValue: Boolean);
    procedure SetThickness(const AValue: Integer);
    procedure SetSweep(const AValue: Integer);
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
    procedure UpdateRunning;
  protected
    function GetStyleTypeKey: string; override;   // 'TyGauge'
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
    property Thickness: Integer read FThickness write SetThickness default 6;
    property Sweep: Integer read FSweep write SetSweep default 270;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

const
  cPeriodMs = 1100;   // ~1.1s per full turn

function TyActivityAdvance(ACurrentDeg: Double; AMs, APeriodMs: Integer): Double;
begin
  if APeriodMs <= 0 then Exit(ACurrentDeg);
  Result := ACurrentDeg + 360 * (AMs / APeriodMs);
  while Result >= 360 do Result := Result - 360;
  while Result < 0 do Result := Result + 360;
end;

constructor TTyActivityIndicator.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FActive := True;
  FThickness := 6;
  FSweep := 270;
  FAngle := 0;
  Width := 32;
  Height := 32;
end;

destructor TTyActivityIndicator.Destroy;
begin
  FreeAndNil(FTimer);
  inherited Destroy;
end;

function TTyActivityIndicator.GetStyleTypeKey: string;
begin
  Result := 'TyGauge';
end;

procedure TTyActivityIndicator.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 16;
    FTimer.OnTimer := @HandleTimer;
  end;
end;

function TTyActivityIndicator.AdvanceAnimation(AMs: Integer): Boolean;
begin
  FAngle := TyActivityAdvance(FAngle, AMs, cPeriodMs);
  Result := True;
end;

procedure TTyActivityIndicator.HandleTimer(Sender: TObject);
begin
  AdvanceAnimation(FTimer.Interval);
  Invalidate;
end;

procedure TTyActivityIndicator.UpdateRunning;
begin
  if FActive and (Parent <> nil) and Parent.HandleAllocated then
  begin
    EnsureTimer;
    FTimer.Enabled := True;
  end
  else if FTimer <> nil then
    FTimer.Enabled := False;
end;

procedure TTyActivityIndicator.SetActive(const AValue: Boolean);
begin
  if FActive = AValue then Exit;
  FActive := AValue;
  UpdateRunning;
  Invalidate;
end;

procedure TTyActivityIndicator.SetThickness(const AValue: Integer);
begin
  if FThickness = AValue then Exit;
  FThickness := Math.Max(1, AValue);
  Invalidate;
end;

procedure TTyActivityIndicator.SetSweep(const AValue: Integer);
var v: Integer;
begin
  v := AValue;
  if v < 10 then v := 10 else if v > 350 then v := 350;
  if FSweep = v then Exit;
  FSweep := v;
  Invalidate;
end;

procedure TTyActivityIndicator.Paint;
var
  P: TTyPainter;
  trackS, fillS: TTyStyleSet;
  R: TRect;
  ctx: TBGRACanvas2D;
  cx, cy, radius: Double;
  th: Integer;
begin
  UpdateRunning;   // begin spinning once we have a paintable handle
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ClientWidth, ClientHeight);
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    trackS := CurrentStyle;                                             // TyGauge track/text
    fillS := ActiveController.Model.ResolveStyle('TyGaugeFill', StyleClass, []);
    th := P.Scale(FThickness);
    cx := (R.Left + R.Right) / 2;
    cy := (R.Top + R.Bottom) / 2;
    radius := (Math.Min(R.Right - R.Left, R.Bottom - R.Top) - th) / 2;
    if radius >= 1 then
    begin
      ctx := P.Bitmap.Canvas2D;
      ctx.lineWidth := th;
      ctx.lineCap := 'round';
      // faint full track ring
      ctx.beginPath;
      ctx.arc(cx, cy, radius, 0, 2 * Pi, False);
      ctx.strokeStyle(TyColorToBGRA(trackS.Background.Color));
      ctx.stroke;
      // rotating accent arc
      ctx.beginPath;
      ctx.arc(cx, cy, radius, DegToRad(FAngle), DegToRad(FAngle + FSweep), False);
      ctx.strokeStyle(TyColorToBGRA(fillS.Background.Color));
      ctx.stroke;
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
