unit tyControls.Transitions;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

// Self-contained appearance-transition facility. Plays a one-shot "reveal"
// animation (slide-in or fade-in) on any TControl/TForm, driven by the pure,
// wall-clock-free animation kernel (tyControls.Animation.TTyAnimator) plus a
// lazily-created TTimer. Nothing here touches tyControls.Form.pas or any other
// control unit -- it is a small kit of global procedures + a hidden internal
// driver component.
//
// Design at a glance:
//   * SLIDE  -- animates the control's Bounds position from an off-edge start
//               offset toward its target position. Works on ALL platforms.
//   * FADE   -- animates a form's AlphaBlendValue 0->255. AlphaBlend is a
//               {$IFDEF MSWINDOWS} + TCustomForm capability only; on other
//               platforms (or on a non-form control) fade DEGRADES to an
//               immediate show (documented, no error).
//
// The only headless-testable seams are the pure TyTransitionStartOffset
// geometry and the TTyAnimator interpolation it feeds. The timer + window
// behaviour is real-machine.

interface

uses
  Classes, SysUtils, Controls, ExtCtrls, Forms,
  tyControls.Animation;

type
  // Direction/style of the reveal. A slide names the direction the control
  // TRAVELS as it settles (ttSlideUp rises up into place from below, etc.).
  TTyTransitionKind = (ttNone, ttFade, ttSlideUp, ttSlideDown,
                       ttSlideLeft, ttSlideRight);

// PURE, headless-testable. The start pixel offset of a slide relative to the
// control's target position: at animation t=0 the control sits at
// (target + offset); at t=1 it sits exactly at the target (offset 0). AW/AH are
// the control's width/height. ttFade and ttNone have no positional offset ->
// (0, 0). Conventions (pinned):
//   ttSlideUp    -> starts BELOW  the target: ADX=0,   ADY=+AH  (travels up)
//   ttSlideDown  -> starts ABOVE  the target: ADX=0,   ADY=-AH  (travels down)
//   ttSlideLeft  -> starts RIGHT  of target:  ADX=+AW, ADY=0    (travels left)
//   ttSlideRight -> starts LEFT   of target:  ADX=-AW, ADY=0    (travels right)
procedure TyTransitionStartOffset(AKind: TTyTransitionKind; AW, AH: Integer;
  out ADX, ADY: Integer);

// Play a reveal transition on AControl. ttNone or a nil control is a no-op.
// The control is made Visible and animated into place over ADurationMs. A lazy
// internal driver owns the timer and frees itself when the animation ends; it
// is torn down safely if the control is freed mid-animation.
procedure TyPlayTransition(AControl: TControl; AKind: TTyTransitionKind;
  ADurationMs: Integer = 200);

// Convenience: fade a form in (Windows), else immediate show.
procedure TyFadeIn(AControl: TControl; ADurationMs: Integer = 200);
// Convenience: slide a control in from AKind's edge.
procedure TySlideIn(AControl: TControl; AKind: TTyTransitionKind;
  ADurationMs: Integer = 200);

implementation

{ ---- pure geometry (headless-tested) ---- }

procedure TyTransitionStartOffset(AKind: TTyTransitionKind; AW, AH: Integer;
  out ADX, ADY: Integer);
begin
  ADX := 0;
  ADY := 0;
  case AKind of
    ttSlideUp:    ADY :=  AH;   // start below,   travel up
    ttSlideDown:  ADY := -AH;   // start above,   travel down
    ttSlideLeft:  ADX :=  AW;   // start right of, travel left
    ttSlideRight: ADX := -AW;   // start left of,  travel right
  else
    ; // ttFade / ttNone: no positional offset (already 0,0)
  end;
end;

// True when AControl has a live OS window to drive frames against: a windowed
// control needs its own handle; a graphic control rides its parent's. Without
// one (e.g. called before the form is shown) the caller snaps instead of easing.
function TyCanDrive(AControl: TControl): Boolean;
begin
  if AControl is TWinControl then
    Result := TWinControl(AControl).HandleAllocated
  else
    Result := (AControl.Parent <> nil) and AControl.Parent.HandleAllocated;
end;

{ ---- internal driver ----

  One TTyTransitionDriver instance backs one running transition. It is OWNED by
  the target control (inherited Create(AControl)), which is the leak/dangling
  guard: if the control is freed mid-animation the driver (and the TTimer it
  owns) are destroyed as part of the control's component teardown -- no timer
  can outlive its target. On normal completion the driver disables its timer and
  schedules its own destruction via Application.ReleaseComponent (deferred, so it
  is never freed from inside its own OnTimer). ReleaseComponent registers a free
  notification, so an owner-driven free that races the release is handled without
  a double free. }

type
  TTyTransitionDriver = class(TComponent)
  private
    FControl: TControl;
    FKind: TTyTransitionKind;
    FDurationMs: Integer;
    FTimer: TTimer;                 // lazy; created only when actually animating
    FAnimator: TTyAnimator;         // 0..1 traversal, eased
    FTargetLeft, FTargetTop: Integer;
    FTargetW, FTargetH: Integer;    // captured target bounds
    FStartDX, FStartDY: Integer;    // slide start offset (from the pure fn)
    procedure ApplyFrame;           // paint the current eased position/opacity
    procedure Finish;               // snap to the settled end state
    procedure RestoreFadeOpacity;   // undo a fade's AlphaBlend (idempotent; ANY teardown path)
    procedure ReleaseSelf;          // stop timer + schedule deferred free
    procedure HandleTimer(Sender: TObject);
  public
    constructor Create(AControl: TControl; AKind: TTyTransitionKind;
      ADurationMs: Integer); reintroduce;
    destructor Destroy; override;
    procedure Start;
  end;

constructor TTyTransitionDriver.Create(AControl: TControl;
  AKind: TTyTransitionKind; ADurationMs: Integer);
begin
  inherited Create(AControl);   // owned by the control -> auto teardown guard
  FControl := AControl;
  FKind := AKind;
  FDurationMs := ADurationMs;
end;

procedure TTyTransitionDriver.ApplyFrame;
var
  eased: Single;
{$IFDEF MSWINDOWS}
  v: Integer;
{$ENDIF}
begin
  if FControl = nil then Exit;
  eased := FAnimator.Eased;
  if FKind = ttFade then
  begin
    {$IFDEF MSWINDOWS}
    // Fade path only reaches here for a TCustomForm on Windows (gated in
    // TyPlayTransition); animate opacity from transparent to opaque.
    if FControl is TCustomForm then
    begin
      v := TyLerpI(0, 255, eased);
      if v < 0 then v := 0
      else if v > 255 then v := 255;
      TCustomForm(FControl).AlphaBlend := True;
      TCustomForm(FControl).AlphaBlendValue := v;
    end;
    {$ENDIF}
  end
  else
    // Slide: lerp the start offset toward zero; bounds size stays fixed.
    FControl.SetBounds(
      FTargetLeft + TyLerpI(FStartDX, 0, eased),
      FTargetTop  + TyLerpI(FStartDY, 0, eased),
      FTargetW, FTargetH);
end;

procedure TTyTransitionDriver.Finish;
begin
  if FControl = nil then Exit;
  if FKind = ttFade then
    RestoreFadeOpacity
  else
    FControl.SetBounds(FTargetLeft, FTargetTop, FTargetW, FTargetH);
  FControl.Invalidate;
end;

{ Undo a fade's AlphaBlend so the form paints opaque again. Idempotent, and called from
  BOTH Finish (clean completion) AND the destructor -- so a fade interrupted by CancelExisting
  / an owner-free / ReleaseComponent never strands the form semi-transparent. Skips a control
  that is itself being destroyed (its opacity no longer matters + its handle is dying). }
procedure TTyTransitionDriver.RestoreFadeOpacity;
begin
  if (FKind <> ttFade) or (FControl = nil) then Exit;
  if csDestroying in FControl.ComponentState then Exit;
  {$IFDEF MSWINDOWS}
  if FControl is TCustomForm then
  begin
    TCustomForm(FControl).AlphaBlendValue := 255;
    TCustomForm(FControl).AlphaBlend := False;
  end;
  {$ENDIF}
end;

destructor TTyTransitionDriver.Destroy;
begin
  RestoreFadeOpacity;   // any teardown path (cancel / owner-free / deferred release) restores opacity
  inherited Destroy;
end;

procedure TTyTransitionDriver.ReleaseSelf;
begin
  if FTimer <> nil then
    FTimer.Enabled := False;
  // Deferred free: safe to call from within our own OnTimer handler.
  Application.ReleaseComponent(Self);
end;

procedure TTyTransitionDriver.HandleTimer(Sender: TObject);
begin
  if FControl = nil then
  begin
    ReleaseSelf;
    Exit;
  end;
  if FAnimator.Advance(FTimer.Interval) then
  begin
    ApplyFrame;
    FControl.Invalidate;
  end;
  if not FAnimator.Running then
  begin
    Finish;
    ReleaseSelf;
  end;
end;

procedure TTyTransitionDriver.Start;
var
  canAnimate: Boolean;
begin
  // Capture the settled target geometry, then compute the slide start offset.
  FTargetLeft := FControl.Left;
  FTargetTop  := FControl.Top;
  FTargetW    := FControl.Width;
  FTargetH    := FControl.Height;
  TyTransitionStartOffset(FKind, FTargetW, FTargetH, FStartDX, FStartDY);

  FAnimator := TyAnimatorInit(FDurationMs, teEaseOutCubic);   // Progress 0 -> 1

  // Only ease over time when there is a real window and a positive duration;
  // otherwise snap to the settled state (matches the ExPanel headless contract).
  canAnimate := (FDurationMs > 0) and TyCanDrive(FControl);

  ApplyFrame;                    // t=0 frame: start offset / transparent
  FControl.Visible := True;      // reveal (transparent for fade, off-edge for slide)

  if canAnimate then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Interval := 16;       // ~60fps
    FTimer.OnTimer := @HandleTimer;
    FTimer.Enabled := True;
  end
  else
  begin
    FAnimator.SetTargetImmediate(1);
    Finish;
    ReleaseSelf;
  end;
end;

{ ---- public API ---- }

// Free any transition already running on this control so a fresh call cannot
// fight an in-flight one. Direct Free is safe here (not inside a timer event).
procedure CancelExisting(AControl: TControl);
var
  i: Integer;
begin
  for i := AControl.ComponentCount - 1 downto 0 do
    if AControl.Components[i] is TTyTransitionDriver then
      AControl.Components[i].Free;
end;

procedure TyPlayTransition(AControl: TControl; AKind: TTyTransitionKind;
  ADurationMs: Integer);
var
  driver: TTyTransitionDriver;
begin
  if (AControl = nil) or (AKind = ttNone) then Exit;

  if AKind = ttFade then
  begin
    // Fade needs form-level AlphaBlend, which is Windows-only. Everywhere else
    // (and for a non-form control) degrade gracefully to an immediate show.
    {$IFDEF MSWINDOWS}
    if not (AControl is TCustomForm) then
    begin
      AControl.Visible := True;
      Exit;
    end;
    {$ELSE}
    AControl.Visible := True;
    Exit;
    {$ENDIF}
  end;

  CancelExisting(AControl);
  driver := TTyTransitionDriver.Create(AControl, AKind, ADurationMs);
  driver.Start;
end;

procedure TyFadeIn(AControl: TControl; ADurationMs: Integer);
begin
  TyPlayTransition(AControl, ttFade, ADurationMs);
end;

procedure TySlideIn(AControl: TControl; AKind: TTyTransitionKind;
  ADurationMs: Integer);
begin
  TyPlayTransition(AControl, AKind, ADurationMs);
end;

end.
