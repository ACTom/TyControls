unit tyControls.ProgressBar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, ExtCtrls,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Animation;
type
  TTyProgressBar = class(TTyGraphicControl)
  private
    FMin, FMax, FPosition: Integer;
    FAnimEnabled: Boolean;
    FPosAnim: TTyAnimator;     // 0..1 traversal driving FAnimFrom -> FAnimTo
    FAnimFrom, FAnimTo: Single; // displayed-position endpoints (in Min..Max units)
    FTimer: TTimer;            // lazy; only created when actually animating
    procedure SetMin(const AValue: Integer);
    procedure SetMax(const AValue: Integer);
    procedure SetPosition(const AValue: Integer);
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    // Current displayed (possibly mid-animation) position, eased between the
    // from/to endpoints. At rest this equals the logical FPosition.
    function DisplayPos: Single;
    // Steppable animation seam (no wall-clock): advance the fill ease by AMs and
    // return True iff the eased progress changed. The lazy TTimer drives it at
    // runtime; tests drive it directly via an access subclass.
    function AdvanceAnimation(AMs: Integer): Boolean;
    // Force the *animating* path toward AValue (clamped) regardless of handle
    // state. Runtime always routes through SetPosition (which snaps headless);
    // this is the test seam so the animation is reachable without a window.
    procedure SetPositionAnimating(AValue: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // On by default. When enabled and the control has a window handle, changing
    // Position eases the fill from the old to the new value; with no handle
    // (every render test) it snaps, preserving the existing exact-pixel tests.
    property AnimationsEnabled: Boolean read FAnimEnabled write FAnimEnabled default True;
  published
    property Min: Integer read FMin write SetMin default 0;
    property Max: Integer read FMax write SetMax default 100;
    property Position: Integer read FPosition write SetPosition default 0;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

function TyProgressFillRect(const ATrack: TRect; AMin, AMax, APosition: Integer): TRect;

implementation

function TyProgressFillRect(const ATrack: TRect; AMin, AMax, APosition: Integer): TRect;
var
  TrackW, Travel, Pos0, FillW: Integer;
begin
  Result := ATrack;
  Result.Right := Result.Left;  // default: empty (zero width)
  TrackW := ATrack.Right - ATrack.Left;
  Travel := AMax - AMin;
  if Travel <= 0 then
    Exit;  // degenerate: Max <= Min → zero fill
  Pos0 := APosition - AMin;
  if Pos0 <= 0 then
  begin
    // Pos <= Min → zero fill (Result already has Right=Left)
    Exit;
  end;
  if Pos0 >= Travel then
  begin
    // Pos >= Max → full fill
    Result.Right := ATrack.Right;
    Exit;
  end;
  // Normal case: scale by Pos0/Travel
  FillW := (TrackW * Pos0) div Travel;
  Result.Right := ATrack.Left + FillW;
end;

{ TTyProgressBar }

constructor TTyProgressBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMin := 0;
  FMax := 100;
  FPosition := 0;
  FAnimEnabled := True;
  // Fill-ease animator: 0..1 traversal in ~120ms, decelerating. Start settled at
  // the rest endpoint so DisplayPos == FPosition before any change.
  FPosAnim.Progress := 1;
  FPosAnim.Target := 1;
  FPosAnim.DurationMs := 120;
  FPosAnim.Easing := teEaseOutCubic;
  FAnimFrom := FPosition;
  FAnimTo := FPosition;
  Width := 200;
  Height := 20;
end;

destructor TTyProgressBar.Destroy;
begin
  // FTimer is owned by Self (would be freed by DestroyComponents), but free it
  // explicitly first so the OnTimer callback can never fire mid-teardown.
  FreeAndNil(FTimer);
  inherited Destroy;
end;

function TTyProgressBar.GetStyleTypeKey: string;
begin
  Result := 'TyProgressBar';
end;

procedure TTyProgressBar.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 16;  // ~60fps
    FTimer.OnTimer := @HandleTimer;
  end;
end;

procedure TTyProgressBar.HandleTimer(Sender: TObject);
begin
  if AdvanceAnimation(FTimer.Interval) then
    Invalidate;
  if not FPosAnim.Running then
    FTimer.Enabled := False;
end;

function TTyProgressBar.AdvanceAnimation(AMs: Integer): Boolean;
begin
  Result := FPosAnim.Advance(AMs);
end;

function TTyProgressBar.DisplayPos: Single;
begin
  Result := TyLerpF(FAnimFrom, FAnimTo, FPosAnim.Eased);
end;

procedure TTyProgressBar.SetPositionAnimating(AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := AValue;
  if Clamped < FMin then Clamped := FMin;
  if Clamped > FMax then Clamped := FMax;
  // Arm the ease from the currently displayed position to the new target,
  // independent of handle state (test seam). FPosition still tracks the logical
  // value for Min/Max/value semantics.
  FAnimFrom := DisplayPos;
  FAnimTo := Clamped;
  FPosAnim.Progress := 0;
  FPosAnim.Target := 1;
  FPosition := Clamped;
  Invalidate;
end;

procedure TTyProgressBar.SetMin(const AValue: Integer);
begin
  if FMin = AValue then Exit;
  FMin := AValue;
  if FPosition < FMin then FPosition := FMin;
  Invalidate;
end;

procedure TTyProgressBar.SetMax(const AValue: Integer);
begin
  if FMax = AValue then Exit;
  FMax := AValue;
  if FPosition > FMax then FPosition := FMax;
  Invalidate;
end;

procedure TTyProgressBar.SetPosition(const AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := AValue;
  if Clamped < FMin then Clamped := FMin;
  if Clamped > FMax then Clamped := FMax;
  if FPosition = Clamped then Exit;
  // A graphic control has no window handle of its own; it paints onto its
  // parent. "Has a window to animate into" therefore means the parent's handle
  // is allocated. Headless render tests parent to an unshown form (no handle),
  // so this snaps — keeping the existing exact-pixel progress tests green.
  if FAnimEnabled and (Parent <> nil) and Parent.HandleAllocated then
  begin
    // Animate: ease the displayed fill from where it is now to the new value.
    FAnimFrom := DisplayPos;
    FAnimTo := Clamped;
    FPosAnim.Progress := 0;
    FPosAnim.Target := 1;
    EnsureTimer;
    FTimer.Enabled := True;
  end
  else
  begin
    // Headless (no window handle) or animations off: snap so DisplayPos == new
    // immediately. Every render test runs handle-less, so this keeps the
    // existing exact-pixel progress tests green.
    FAnimFrom := Clamped;
    FAnimTo := Clamped;
    FPosAnim.SetTargetImmediate(1);
  end;
  FPosition := Clamped;
  Invalidate;
end;

procedure TTyProgressBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, FillS: TTyStyleSet;
  R, TrackR, FillR: TRect;
  BW, DispPos: Integer;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    // Inset the fill track by the border width so the fill doesn't paint over the border
    BW := P.Scale(S.BorderWidth);
    TrackR := Rect(R.Left + BW, R.Top + BW, R.Right - BW, R.Bottom - BW);
    // Resolve fill style for the progress fill. Drive the fill geometry from the
    // displayed (possibly mid-animation) position; at rest DisplayPos == FPosition
    // so headless renders are pixel-identical to the pre-animation behavior.
    DispPos := Round(DisplayPos);
    FillS := ActiveController.Model.ResolveStyle('TyProgressFill', '', []);
    FillR := TyProgressFillRect(TrackR, FMin, FMax, DispPos);
    if FillR.Right > FillR.Left then
    begin
      // Full fill (Position >= Max) matches the track edge-to-edge, so round all
      // four corners. A partial fill is left-anchored and its leading (right) edge
      // sits mid-track, so round only the LEFT (origin) corners and keep the right
      // edge square — otherwise the fill looks like a floating pill.
      if DispPos >= FMax then
        P.FillBackground(FillR, FillS.Background, TyUniformCorners(FillS.BorderRadius))
      else
        P.FillBackground(FillR, FillS.Background,
          TyCorners(FillS.BorderRadius, 0, 0, FillS.BorderRadius)); // TL, TR, BR, BL
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyProgressBar.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
