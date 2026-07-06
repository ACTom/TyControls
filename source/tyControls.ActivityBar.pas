unit tyControls.ActivityBar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, ExtCtrls,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.StyleModel;

{ Advance an indeterminate phase in [0,1) by AMs of a APeriodMs full cycle (wrapped). }
function TyActivityBarAdvance(APhase: Double; AMs, APeriodMs: Integer): Double;
{ Clamped horizontal span [.X, .Y) of a marching segment ASegW wide at APhase in [0,1),
  travelling from fully off the left to fully off the right across [ALeft, ARight).
  When the segment is entirely off the track the result is empty (.Y <= .X). }
function TyActivityBarSpan(APhase: Double; ALeft, ARight, ASegW: Integer): TPoint;

type
  { An INDETERMINATE linear progress bar — a faint full-width track under two accent
    segments that march left->right (half a cycle apart, so one is always visible),
    for "busy, unknown duration". No value; `Active` starts/stops the march. Reuses the
    gauge theming (typeKey 'TyGauge' track + 'TyGaugeFill' accent), so no extra .tycss
    rules. Marches only when Active AND painted (has a parent handle); headless it is
    static, keeping render/golden tests pixel-stable. }
  TTyActivityBar = class(TTyGraphicControl)
  private
    FActive: Boolean;
    FPhase: Double;       // current march phase in [0,1)
    FTimer: TTimer;       // lazy; only created when actually marching
    procedure SetActive(const AValue: Boolean);
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
    procedure UpdateRunning;
  protected
    function GetStyleTypeKey: string; override;   // 'TyGauge'
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Step seam (no wall-clock): advance the march by AMs; returns True (always moves).
    function AdvanceAnimation(AMs: Integer): Boolean;
    // Read-only current phase, for tests/introspection.
    property Phase: Double read FPhase;
  published
    property Active: Boolean read FActive write SetActive default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

const
  cPeriodMs = 1600;      // one full marching cycle
  cSegFraction = 0.35;   // one accent segment's width as a fraction of the track

function TyActivityBarAdvance(APhase: Double; AMs, APeriodMs: Integer): Double;
begin
  if APeriodMs <= 0 then Exit(APhase);
  Result := APhase + AMs / APeriodMs;
  Result := Result - Floor(Result);   // wrap to [0,1)
end;

function TyActivityBarSpan(APhase: Double; ALeft, ARight, ASegW: Integer): TPoint;
var
  trackW, L, Rr: Integer;
  rawLeft: Double;
begin
  trackW := ARight - ALeft;
  if (trackW <= 0) or (ASegW <= 0) then Exit(Point(ALeft, ALeft));
  APhase := APhase - Floor(APhase);   // wrap to [0,1)
  // The segment travels from fully off the left (-ASegW) to fully off the right (trackW).
  rawLeft := -ASegW + APhase * (trackW + ASegW);
  L := ALeft + Round(rawLeft);
  Rr := L + ASegW;
  if L < ALeft then L := ALeft;
  if Rr > ARight then Rr := ARight;
  Result := Point(L, Rr);
end;

{ TTyActivityBar }

constructor TTyActivityBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FActive := True;
  FPhase := 0;
  Width := 150;
  Height := 8;
end;

destructor TTyActivityBar.Destroy;
begin
  FreeAndNil(FTimer);   // stop the callback before teardown
  inherited Destroy;
end;

function TTyActivityBar.GetStyleTypeKey: string;
begin
  Result := 'TyGauge';
end;

procedure TTyActivityBar.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 16;
    FTimer.OnTimer := @HandleTimer;
  end;
end;

function TTyActivityBar.AdvanceAnimation(AMs: Integer): Boolean;
begin
  FPhase := TyActivityBarAdvance(FPhase, AMs, cPeriodMs);
  Result := True;
end;

procedure TTyActivityBar.HandleTimer(Sender: TObject);
begin
  AdvanceAnimation(FTimer.Interval);
  Invalidate;
end;

procedure TTyActivityBar.UpdateRunning;
begin
  { A graphic control paints onto its parent; "has a window to march into" means the parent
    handle is allocated. Headless render tests parent to an unshown form (no handle) -> the
    timer stays off and the bar is static, keeping exact-pixel tests stable. }
  if FActive and (Parent <> nil) and Parent.HandleAllocated then
  begin
    EnsureTimer;
    FTimer.Enabled := True;
  end
  else if FTimer <> nil then
    FTimer.Enabled := False;
end;

procedure TTyActivityBar.SetActive(const AValue: Boolean);
begin
  if FActive = AValue then Exit;
  FActive := AValue;
  UpdateRunning;
  Invalidate;
end;

procedure TTyActivityBar.Paint;
var
  P: TTyPainter;
  trackS, fillS: TTyStyleSet;
  R, trackR: TRect;
  bw, segW, i: Integer;
  ph: Double;
  span: TPoint;
begin
  UpdateRunning;   // begin marching once we have a paintable handle
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ClientWidth, ClientHeight);
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    trackS := CurrentStyle;                                             // TyGauge: track/border
    fillS := ActiveController.Model.ResolveStyle('TyGaugeFill', StyleClass, []);  // accent segments
    DrawFrame(P, R, trackS);   // track background + border (rounded)
    bw := P.Scale(trackS.BorderWidth);
    trackR := Rect(R.Left + bw, R.Top + bw, R.Right - bw, R.Bottom - bw);
    if (trackR.Right > trackR.Left) and (trackR.Bottom > trackR.Top) then
    begin
      segW := Round((trackR.Right - trackR.Left) * cSegFraction);
      if segW < 1 then segW := 1;
      // Two segments half a cycle apart -> one is always visible (no gap at the wrap).
      for i := 0 to 1 do
      begin
        ph := FPhase + i * 0.5;
        ph := ph - Floor(ph);
        span := TyActivityBarSpan(ph, trackR.Left, trackR.Right, segW);
        if span.Y > span.X then
          P.FillBackground(Rect(span.X, trackR.Top, span.Y, trackR.Bottom),
            fillS.Background, TyUniformCorners(fillS.BorderRadius));
      end;
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
