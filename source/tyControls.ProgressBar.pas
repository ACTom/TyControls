unit tyControls.ProgressBar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, ExtCtrls,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller, tyControls.Animation;
type
  { All four fill directions LCL has (TProgressBarOrientation, comctrls.pp:1801):
    left->right, bottom->up, right->left and top->down. The last two used to be
    unreachable, so an RTL layout and a "draining" meter could not be drawn at all. }
  TTyProgressOrientation = (tpoHorizontal, tpoVertical, tpoRightToLeft, tpoTopDown);

  TTyProgressBar = class(TTyGraphicControl)
  private
    FMin, FMax, FPosition, FStep: Integer;
    FAnimEnabled: Boolean;
    FBarShowText: Boolean;
    FBarTextFormat: string;
    FOnChange: TNotifyEvent;
    FOrientation: TTyProgressOrientation;
    FPosAnim: TTyAnimator;     // 0..1 traversal driving FAnimFrom -> FAnimTo
    FAnimFrom, FAnimTo: Single; // displayed-position endpoints (in Min..Max units)
    FTimer: TTimer;            // lazy; only created when actually animating
    procedure SetMin(const AValue: Integer);
    procedure SetMax(const AValue: Integer);
    procedure SetPosition(const AValue: Integer);
    procedure SetOrientation(const AValue: TTyProgressOrientation);
    procedure SetStep(const AValue: Integer);
    procedure SetBarShowText(const AValue: Boolean);
    procedure SetBarTextFormat(const AValue: string);
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
    { Advance by Step, clamped to Min..Max -- the idiomatic
      `for i := 1 to n do begin Work; Bar.StepIt; end` loop, which had no equivalent
      here at all. LCL: include/progressbar.inc:235-241. }
    procedure StepIt;
    { Advance by an explicit delta, clamped the same way. LCL: progressbar.inc:256. }
    procedure StepBy(ADelta: Integer);
    { The text BarShowText draws, with the template already filled in. Public so a host
      can put the same string somewhere else (a status line) without re-deriving it. }
    function BarText: string;
  published
    property Min: Integer read FMin write SetMin default 0;
    property Max: Integer read FMax write SetMax default 100;
    property Position: Integer read FPosition write SetPosition default 0;
    // v3/C4: which way the fill grows. A per-instance layout choice (mirrors LCL
    // TProgressBar.Orientation), not a theme metric.
    property Orientation: TTyProgressOrientation read FOrientation write SetOrientation default tpoHorizontal;
    { The increment StepIt uses. LCL: comctrls.pp:1853, same default. }
    property Step: Integer read FStep write SetStep default 10;
    { Draw the progress as text inside the bar -- the '47%' readout that otherwise
      needs a separate label kept in sync by hand, even though three sibling controls
      here already render their own value. LCL: comctrls.pp:1855, same default. }
    property BarShowText: Boolean read FBarShowText write SetBarShowText default False;
    { The template BarShowText fills in: %v = Position, %l = Min, %u = Max,
      %p = percent. LCL hard-codes '%v from [%l-%u] (=%p%%)' in the gtk interface
      (include/progressbar.inc:48) and gives no way to change it; ours defaults to the
      plain percentage, which is what the readout is actually used for, and is
      settable. }
    property BarTextFormat: string read FBarTextFormat write SetBarTextFormat;
    // On by default. When enabled and the control has a window handle, changing
    // Position eases the fill from the old to the new value; with no handle
    // (every render test) it snaps, preserving the existing exact-pixel tests.
    property AnimationsEnabled: Boolean read FAnimEnabled write FAnimEnabled default True;
    // Fired whenever Position (or Min/Max) actually changes — i.e. after the
    // "if = then Exit" guard in the setters, so a same-value set never fires.
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

function TyProgressFillRect(const ATrack: TRect; AMin, AMax, APosition: Integer;
  AOrientation: TTyProgressOrientation = tpoHorizontal): TRect;

implementation

function TyProgressFillRect(const ATrack: TRect; AMin, AMax, APosition: Integer;
  AOrientation: TTyProgressOrientation = tpoHorizontal): TRect;
var
  TrackLen, Travel, Pos0, FillLen: Integer;
begin
  Result := ATrack;
  { Default: empty, collapsed against the direction's ORIGIN edge -- left, bottom, right
    or top. Every one of the four is one case here, so a new direction cannot be added
    to the enum and quietly fall through to "horizontal", which is what happened to
    right-to-left and top-down before they existed. }
  case AOrientation of
    tpoVertical:
      begin
        Result.Top := Result.Bottom;
        TrackLen := ATrack.Bottom - ATrack.Top;
      end;
    tpoTopDown:
      begin
        Result.Bottom := Result.Top;
        TrackLen := ATrack.Bottom - ATrack.Top;
      end;
    tpoRightToLeft:
      begin
        Result.Left := Result.Right;
        TrackLen := ATrack.Right - ATrack.Left;
      end;
  else
    Result.Right := Result.Left;
    TrackLen := ATrack.Right - ATrack.Left;
  end;
  Travel := AMax - AMin;
  if Travel <= 0 then
    Exit;  // degenerate: Max <= Min → zero fill
  Pos0 := APosition - AMin;
  if Pos0 <= 0 then
    Exit;  // Pos <= Min → zero fill
  if Pos0 >= Travel then
  begin
    // Pos >= Max → full fill
    case AOrientation of
      tpoVertical:     Result.Top := ATrack.Top;
      tpoTopDown:      Result.Bottom := ATrack.Bottom;
      tpoRightToLeft:  Result.Left := ATrack.Left;
    else
      Result.Right := ATrack.Right;
    end;
    Exit;
  end;
  // Normal case: scale the fill length by Pos0/Travel.
  FillLen := (TrackLen * Pos0) div Travel;
  case AOrientation of
    tpoVertical:     Result.Top := ATrack.Bottom - FillLen;   // grows from the bottom up
    tpoTopDown:      Result.Bottom := ATrack.Top + FillLen;   // drains from the top down
    tpoRightToLeft:  Result.Left := ATrack.Right - FillLen;   // grows leftward
  else
    Result.Right := ATrack.Left + FillLen;
  end;
end;

{ TTyProgressBar }

constructor TTyProgressBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMin := 0;
  FMax := 100;
  FPosition := 0;
  FStep := 10;                  // LCL's default (comctrls.pp:1853)
  FBarShowText := False;
  FBarTextFormat := '%p%%';     // the readout people actually want: "47%"
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
  Height := TyDensityHeight(ActiveController, 20);
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
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyProgressBar.SetMax(const AValue: Integer);
begin
  if FMax = AValue then Exit;
  FMax := AValue;
  if FPosition > FMax then FPosition := FMax;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
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
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyProgressBar.SetOrientation(const AValue: TTyProgressOrientation);
begin
  if FOrientation = AValue then Exit;
  FOrientation := AValue;
  Invalidate;
end;

procedure TTyProgressBar.SetStep(const AValue: Integer);
begin
  if FStep = AValue then Exit;
  FStep := AValue;    // no clamp: LCL allows a negative Step, i.e. a counting-down bar
end;

procedure TTyProgressBar.SetBarShowText(const AValue: Boolean);
begin
  if FBarShowText = AValue then Exit;
  FBarShowText := AValue;
  Invalidate;
end;

procedure TTyProgressBar.SetBarTextFormat(const AValue: string);
begin
  if FBarTextFormat = AValue then Exit;
  FBarTextFormat := AValue;
  if FBarShowText then Invalidate;
end;

procedure TTyProgressBar.StepIt;
begin
  StepBy(FStep);
end;

procedure TTyProgressBar.StepBy(ADelta: Integer);
begin
  { Straight through the setter, so the clamp, the repaint, the ease and OnChange are
    the same ones a Position write gets. LCL reaches around its own setter here
    (progressbar.inc:237) and pays for it with a StepIt that skips the notification. }
  Position := FPosition + ADelta;
end;

function TTyProgressBar.BarText: string;
var
  Travel, Pct: Integer;
begin
  Travel := FMax - FMin;
  if Travel <= 0 then Pct := 0
  else Pct := Round(((FPosition - FMin) * 100.0) / Travel);
  Result := FBarTextFormat;
  Result := StringReplace(Result, '%v', IntToStr(FPosition), [rfReplaceAll]);
  Result := StringReplace(Result, '%l', IntToStr(FMin), [rfReplaceAll]);
  Result := StringReplace(Result, '%u', IntToStr(FMax), [rfReplaceAll]);
  Result := StringReplace(Result, '%p', IntToStr(Pct), [rfReplaceAll]);
  // '%%' last, so a literal percent sign in the template survives the substitutions
  // above rather than being eaten by whichever one ran into it first.
  Result := StringReplace(Result, '%%', '%', [rfReplaceAll]);
end;

procedure TTyProgressBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, FillS: TTyStyleSet;
  R, TrackR, FillR: TRect;
  BW, DispPos: Integer;
  Ink: TTyColor;
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
    FillR := TyProgressFillRect(TrackR, FMin, FMax, DispPos, FOrientation);
    if (FillR.Right > FillR.Left) and (FillR.Bottom > FillR.Top) then
    begin
      // Full fill (Position >= Max) matches the track edge-to-edge, so round all four
      // corners. A partial fill is anchored at its origin (left for horizontal, bottom for
      // vertical) and its leading edge sits mid-track, so round only the ORIGIN corners and
      // keep the leading edge square — otherwise the fill looks like a floating pill.
      if DispPos >= FMax then
        P.FillBackground(FillR, FillS.Background, TyUniformCorners(FillS.BorderRadius))
      else
        case FOrientation of
          tpoVertical:
            P.FillBackground(FillR, FillS.Background,
              TyCorners(0, 0, FillS.BorderRadius, FillS.BorderRadius));  // bottom-anchored: BR, BL
          tpoTopDown:
            P.FillBackground(FillR, FillS.Background,
              TyCorners(FillS.BorderRadius, FillS.BorderRadius, 0, 0));  // top-anchored: TL, TR
          tpoRightToLeft:
            P.FillBackground(FillR, FillS.Background,
              TyCorners(0, FillS.BorderRadius, FillS.BorderRadius, 0));  // right-anchored: TR, BR
        else
          P.FillBackground(FillR, FillS.Background,
            TyCorners(FillS.BorderRadius, 0, 0, FillS.BorderRadius));    // left-anchored: TL, BL
        end;
    end;
    if FBarShowText then
    begin
      { The readout's ink. 'TyProgressBar' has no color declaration in any shipped
        theme, and an undeclared TextColor resolves to $00000000 -- alpha 0 -- which is
        how TTyTrackBar's ShowValue managed to reserve a strip and then paint nothing
        into it for its whole life. So: the theme's own ink when a theme states one,
        and the muted 'TyTextHint' ink (which every theme does define) when it does
        not. No colour is written down here. }
      if tpTextColor in S.Present then
        Ink := S.TextColor
      else
        Ink := ActiveController.Model.ResolveStyle('TyTextHint', '', []).TextColor;
      P.DrawText(TrackR, BarText, S.FontName,
        TyResolveFontSize(S, ParentFont, Font.Size, ActiveController), S.FontWeight,
        Ink, taCenter, tlCenter, False);
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
