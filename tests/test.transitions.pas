unit test.transitions;
{$mode objfpc}{$H+}
// Headless tests for the pure, real-machine-free seams of tyControls.Transitions
// (plan docs/superpowers/plans/2026-07-12-phase9-finish.md section ③):
//   1. TyTransitionStartOffset -- the per-direction start-offset geometry.
//   2. The TTyAnimator interpolation a slide/fade is driven by (from
//      tyControls.Animation), including a composite lerp of a start offset back
//      to the target.
// The window/timer driver, real slide on a windowed control, and Windows-only
// AlphaBlend fade are all real-machine and are NOT exercised here.
//
// Slide-offset SIGN convention -- pinned from plan section ③ line 108
//   ("ttSlideUp -> starts from below by +AH etc., pinned by convention") and the task contract:
//   the offset is the START position RELATIVE to the target (t=0 at offset,
//   t=1 at 0). A control "slides up" INTO place, so it must start BELOW the
//   target; screen Y grows downward, hence a POSITIVE DY.
//     ttSlideUp    : DX=0,   DY=+AH   (starts below,  slides up)
//     ttSlideDown  : DX=0,   DY=-AH   (starts above,  slides down)
//     ttSlideLeft  : DX=+AW, DY=0     (starts right,  slides left)
//     ttSlideRight : DX=-AW, DY=0     (starts left,   slides right)
//     ttFade/ttNone: DX=0,   DY=0     (no positional offset)
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Animation, tyControls.Transitions;
type
  TTyTransitionsTest = class(TTestCase)
  published
    // TyTransitionStartOffset -- direction geometry
    procedure TestStartOffsetSlideUpBelow;
    procedure TestStartOffsetSlideDownAbove;
    procedure TestStartOffsetSlideLeftRight;
    procedure TestStartOffsetSlideRightLeft;
    procedure TestStartOffsetFadeZero;
    procedure TestStartOffsetNoneZero;
    procedure TestStartOffsetMagnitudeTracksSize;
    // TTyAnimator interpolation that drives a transition
    procedure TestAnimatorHalfwayEasedInsideUnitInterval;
    procedure TestAnimatorHalfwayLerpStrictlyBetween;
    procedure TestAnimatorFullDurationLandsOnTarget;
    procedure TestSlideUpDrivenBackToTarget;
  end;
implementation

const
  AW = 120;   // sample control width
  AH = 80;    // sample control height

{ ---- TyTransitionStartOffset: per-direction geometry ---- }

procedure TTyTransitionsTest.TestStartOffsetSlideUpBelow;
var dx, dy: Integer;
begin
  dx := 0; dy := 0;
  TyTransitionStartOffset(ttSlideUp, AW, AH, dx, dy);
  AssertEquals('slideUp DX=0', 0, dx);
  AssertEquals('slideUp starts BELOW target -> DY=+AH', AH, dy);
end;

procedure TTyTransitionsTest.TestStartOffsetSlideDownAbove;
var dx, dy: Integer;
begin
  dx := 0; dy := 0;
  TyTransitionStartOffset(ttSlideDown, AW, AH, dx, dy);
  AssertEquals('slideDown DX=0', 0, dx);
  AssertEquals('slideDown starts ABOVE target -> DY=-AH', -AH, dy);
end;

procedure TTyTransitionsTest.TestStartOffsetSlideLeftRight;
var dx, dy: Integer;
begin
  dx := 0; dy := 0;
  TyTransitionStartOffset(ttSlideLeft, AW, AH, dx, dy);
  AssertEquals('slideLeft starts to the RIGHT -> DX=+AW', AW, dx);
  AssertEquals('slideLeft DY=0', 0, dy);
end;

procedure TTyTransitionsTest.TestStartOffsetSlideRightLeft;
var dx, dy: Integer;
begin
  dx := 0; dy := 0;
  TyTransitionStartOffset(ttSlideRight, AW, AH, dx, dy);
  AssertEquals('slideRight starts to the LEFT -> DX=-AW', -AW, dx);
  AssertEquals('slideRight DY=0', 0, dy);
end;

procedure TTyTransitionsTest.TestStartOffsetFadeZero;
var dx, dy: Integer;
begin
  dx := 999; dy := 999;
  TyTransitionStartOffset(ttFade, AW, AH, dx, dy);
  AssertEquals('fade has no positional offset DX=0', 0, dx);
  AssertEquals('fade has no positional offset DY=0', 0, dy);
end;

procedure TTyTransitionsTest.TestStartOffsetNoneZero;
var dx, dy: Integer;
begin
  dx := 999; dy := 999;
  TyTransitionStartOffset(ttNone, AW, AH, dx, dy);
  AssertEquals('none DX=0', 0, dx);
  AssertEquals('none DY=0', 0, dy);
end;

procedure TTyTransitionsTest.TestStartOffsetMagnitudeTracksSize;
var dx, dy: Integer;
begin
  // A vertical slide's magnitude follows the HEIGHT, a horizontal slide's the WIDTH.
  dx := 0; dy := 0;
  TyTransitionStartOffset(ttSlideUp, 33, 77, dx, dy);
  AssertEquals('vertical slide magnitude = AH', 77, Abs(dy));
  AssertEquals('vertical slide has no DX', 0, dx);
  dx := 0; dy := 0;
  TyTransitionStartOffset(ttSlideLeft, 33, 77, dx, dy);
  AssertEquals('horizontal slide magnitude = AW', 33, Abs(dx));
  AssertEquals('horizontal slide has no DY', 0, dy);
end;

{ ---- TTyAnimator interpolation driving a transition ---- }

procedure TTyTransitionsTest.TestAnimatorHalfwayEasedInsideUnitInterval;
var a: TTyAnimator;
begin
  a := TyAnimatorInit(200, teEaseOutCubic);
  a.Advance(100);                       // Progress 0.5 of a 200ms traversal
  AssertTrue('still running at half',   a.Running);
  AssertTrue('eased > 0 at half',       a.Eased > 0.0);
  AssertTrue('eased < 1 at half',       a.Eased < 1.0);
end;

procedure TTyTransitionsTest.TestAnimatorHalfwayLerpStrictlyBetween;
var
  a: TTyAnimator;
  fromPos, toPos, cur: Integer;
begin
  fromPos := 150;
  toPos   := 50;
  a := TyAnimatorInit(200, teEaseOutCubic);
  a.Advance(100);                       // half the duration
  cur := TyLerpI(fromPos, toPos, a.Eased);
  // toPos < fromPos here; a mid-flight value must lie strictly inside the open range.
  AssertTrue('lerp strictly > toPos',   cur > toPos);
  AssertTrue('lerp strictly < fromPos', cur < fromPos);
end;

procedure TTyTransitionsTest.TestAnimatorFullDurationLandsOnTarget;
var
  a: TTyAnimator;
  fromPos, toPos: Integer;
begin
  fromPos := 150;
  toPos   := 50;
  a := TyAnimatorInit(200, teEaseOutCubic);
  a.Advance(100);
  a.Advance(100);                       // full 200ms elapsed
  AssertFalse('not running at full duration', a.Running);
  AssertTrue('eased == 1 at end', Abs(a.Eased - 1.0) < 1e-6);
  AssertEquals('lerp lands exactly on target', toPos,
    TyLerpI(fromPos, toPos, a.Eased));
end;

procedure TTyTransitionsTest.TestSlideUpDrivenBackToTarget;
var
  a: TTyAnimator;
  dx, dy: Integer;
  targetX, targetY, startX, startY, curX, curY: Integer;
begin
  // End-to-end pure model of a slide-up: start = target + offset, animate the
  // control's Bounds position back to the target as Eased goes 0 -> 1.
  targetX := 40; targetY := 200;
  dx := 0; dy := 0;
  TyTransitionStartOffset(ttSlideUp, AW, AH, dx, dy);
  startX := targetX + dx;               // dx = 0
  startY := targetY + dy;               // dy = +AH -> starts below the target
  AssertEquals('start X == target X (no horizontal motion)', targetX, startX);
  AssertTrue('start Y is below target (larger Y)', startY > targetY);

  a := TyAnimatorInit(200, teEaseOutCubic);
  a.Advance(100);
  curX := TyLerpI(startX, targetX, a.Eased);
  curY := TyLerpI(startY, targetY, a.Eased);
  AssertEquals('mid-flight X stays at target', targetX, curX);
  AssertTrue('mid-flight Y is between start and target',
    (curY < startY) and (curY > targetY));

  a.Advance(100);                       // finish
  curX := TyLerpI(startX, targetX, a.Eased);
  curY := TyLerpI(startY, targetY, a.Eased);
  AssertEquals('final X == target', targetX, curX);
  AssertEquals('final Y == target', targetY, curY);
end;

initialization
  RegisterTest(TTyTransitionsTest);
end.
