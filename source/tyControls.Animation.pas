unit tyControls.Animation;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

// Pure, steppable animation core: easing curves, scalar/integer/color
// interpolation, and a wall-clock-free TTyAnimator advanced by explicit
// millisecond steps. No ExtCtrls / TTimer dependency lives here so the maths
// can be exercised deterministically in tests.

interface

uses
  Classes, SysUtils, tyControls.Types, tyControls.Css.Values;

type
  TTyEasing = (teLinear, teEaseOutCubic);

  // Value-type animator. Progress eases from its current value toward Target,
  // stepped in real-time milliseconds via Advance. It carries no timer; a
  // higher layer (e.g. a TTimer driver) owns the clock and calls Advance.
  TTyAnimator = record
    Progress: Single;   // current raw (un-eased) position, 0..1 by convention
    Target: Single;     // value Progress is moving toward
    DurationMs: Integer; // full 0..1 traversal time in milliseconds
    Easing: TTyEasing;
    // Step Progress toward Target by AMs worth of motion. Clamps so it lands
    // exactly on Target without overshoot. Returns True iff Progress changed.
    function Advance(AMs: Integer): Boolean;
    // True while there is still distance left to travel.
    function Running: Boolean;
    // The eased view of Progress (what callers interpolate visuals against).
    function Eased: Single;
    // Snap straight to v with no animation: Progress := Target := v.
    procedure SetTargetImmediate(v: Single);
  end;

// Easing: t is clamped to [0,1]. teLinear is the identity; teEaseOutCubic is
// the decelerating curve 1-(1-t)^3.
function TyEase(e: TTyEasing; t: Single): Single;

// Scalar interpolation. t is NOT clamped (caller controls the domain).
function TyLerpF(a, b, t: Single): Single;
function TyLerpI(a, b: Integer; t: Single): Integer;

// Color interpolation, delegating to TyMix (which takes a 0..100 percentage).
function TyLerpColor(c1, c2: TTyColor; t: Single): TTyColor;

// Convenience constructor: Progress=0, Target=1, given duration/easing.
function TyAnimatorInit(ADurationMs: Integer; AEasing: TTyEasing): TTyAnimator;

// Square-wave caret visibility: visible during even half-periods, hidden during
// odd ones. A non-positive half-period means "always visible" (degenerate guard).
function TyCaretVisible(AElapsedMs, AHalfPeriodMs: Integer): Boolean;

implementation

uses
  Math;

function TyEase(e: TTyEasing; t: Single): Single;
begin
  if t < 0 then t := 0
  else if t > 1 then t := 1;
  case e of
    teEaseOutCubic: Result := 1 - Power(1 - t, 3);
  else
    // teLinear (and any future default): identity
    Result := t;
  end;
end;

function TyLerpF(a, b, t: Single): Single;
begin
  Result := a + (b - a) * t;
end;

function TyLerpI(a, b: Integer; t: Single): Integer;
begin
  Result := Round(TyLerpF(a, b, t));
end;

function TyLerpColor(c1, c2: TTyColor; t: Single): TTyColor;
begin
  Result := TyMix(c1, c2, t * 100);
end;

function TyAnimatorInit(ADurationMs: Integer; AEasing: TTyEasing): TTyAnimator;
begin
  Result.Progress := 0;
  Result.Target := 1;
  Result.DurationMs := ADurationMs;
  Result.Easing := AEasing;
end;

{ TTyAnimator }

function TTyAnimator.Advance(AMs: Integer): Boolean;
var
  step, before: Single;
begin
  before := Progress;
  if (DurationMs <= 0) or (AMs <= 0) then
  begin
    // Degenerate/zero duration: snap to Target.
    Progress := Target;
    Exit(Progress <> before);
  end;
  // Distance covered in AMs of a full 0..1 traversal.
  step := AMs / DurationMs;
  if Progress < Target then
  begin
    Progress := Progress + step;
    if Progress > Target then Progress := Target;
  end
  else if Progress > Target then
  begin
    Progress := Progress - step;
    if Progress < Target then Progress := Target;
  end;
  Result := Progress <> before;
end;

function TTyAnimator.Running: Boolean;
begin
  Result := Progress <> Target;
end;

function TTyAnimator.Eased: Single;
begin
  Result := TyEase(Easing, Progress);
end;

procedure TTyAnimator.SetTargetImmediate(v: Single);
begin
  Target := v;
  Progress := v;
end;

function TyCaretVisible(AElapsedMs, AHalfPeriodMs: Integer): Boolean;
begin
  if AHalfPeriodMs <= 0 then Exit(True);
  if AElapsedMs < 0 then AElapsedMs := 0;
  Result := (AElapsedMs div AHalfPeriodMs) mod 2 = 0;
end;

end.
