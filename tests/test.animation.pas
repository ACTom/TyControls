unit test.animation;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.Css.Values, tyControls.Animation;
type
  TTyAnimationCoreTest = class(TTestCase)
  published
    // easing
    procedure TestEaseLinearIdentity;
    procedure TestEaseOutCubicEndpoints;
    procedure TestEaseOutCubicMonotonic;
    procedure TestEaseOutCubicDecelerating;
    procedure TestEaseClampsOutOfRange;
    // lerps
    procedure TestLerpIEndpointsAndMid;
    procedure TestLerpFEndpoints;
    procedure TestLerpColorMid;
    // animator
    procedure TestAnimatorDefaults;
    procedure TestAnimatorAdvanceReachesTargetNoOvershoot;
    procedure TestAnimatorReverseToZero;
    procedure TestAnimatorSetTargetImmediate;
    procedure TestAnimatorEasedMatchesEase;
    procedure TestAnimatorAdvanceReturnsChanged;
  end;
implementation

procedure TTyAnimationCoreTest.TestEaseLinearIdentity;
begin
  AssertTrue('linear(0)',   Abs(TyEase(teLinear, 0.0)  - 0.0)  < 1e-6);
  AssertTrue('linear(.25)', Abs(TyEase(teLinear, 0.25) - 0.25) < 1e-6);
  AssertTrue('linear(.5)',  Abs(TyEase(teLinear, 0.5)  - 0.5)  < 1e-6);
  AssertTrue('linear(1)',   Abs(TyEase(teLinear, 1.0)  - 1.0)  < 1e-6);
end;

procedure TTyAnimationCoreTest.TestEaseOutCubicEndpoints;
begin
  AssertTrue('easeOutCubic(0)=0', Abs(TyEase(teEaseOutCubic, 0.0) - 0.0) < 1e-6);
  AssertTrue('easeOutCubic(1)=1', Abs(TyEase(teEaseOutCubic, 1.0) - 1.0) < 1e-6);
end;

procedure TTyAnimationCoreTest.TestEaseOutCubicMonotonic;
var
  prev, cur, t: Single;
  i: Integer;
begin
  prev := -1;
  for i := 0 to 20 do
  begin
    t := i / 20;
    cur := TyEase(teEaseOutCubic, t);
    AssertTrue('monotonic non-decreasing at t=' + FloatToStr(t), cur >= prev - 1e-6);
    prev := cur;
  end;
end;

procedure TTyAnimationCoreTest.TestEaseOutCubicDecelerating;
begin
  // decelerating curve sits ABOVE linear in the interior: f(0.5) > 0.5
  AssertTrue('easeOutCubic(.5) > linear(.5)',
    TyEase(teEaseOutCubic, 0.5) > TyEase(teLinear, 0.5) + 1e-4);
end;

procedure TTyAnimationCoreTest.TestEaseClampsOutOfRange;
begin
  AssertTrue('clamp below 0', Abs(TyEase(teLinear, -0.5) - 0.0) < 1e-6);
  AssertTrue('clamp above 1', Abs(TyEase(teLinear,  1.5) - 1.0) < 1e-6);
  AssertTrue('cubic clamp below', Abs(TyEase(teEaseOutCubic, -2.0) - 0.0) < 1e-6);
  AssertTrue('cubic clamp above', Abs(TyEase(teEaseOutCubic,  2.0) - 1.0) < 1e-6);
end;

procedure TTyAnimationCoreTest.TestLerpIEndpointsAndMid;
begin
  AssertEquals('lerpI t=0',   3,  TyLerpI(3, 21, 0.0));
  AssertEquals('lerpI t=1',   21, TyLerpI(3, 21, 1.0));
  AssertEquals('lerpI t=0.5', 12, TyLerpI(3, 21, 0.5));
end;

procedure TTyAnimationCoreTest.TestLerpFEndpoints;
begin
  AssertTrue('lerpF t=0',   Abs(TyLerpF(2.0, 10.0, 0.0) - 2.0)  < 1e-6);
  AssertTrue('lerpF t=1',   Abs(TyLerpF(2.0, 10.0, 1.0) - 10.0) < 1e-6);
  AssertTrue('lerpF t=0.5', Abs(TyLerpF(2.0, 10.0, 0.5) - 6.0)  < 1e-6);
end;

procedure TTyAnimationCoreTest.TestLerpColorMid;
var c: TTyColor;
begin
  // $FF000000 -> $FFFFFFFF at 0.5 should give each channel ~127..128
  c := TyLerpColor($FF000000, $FFFFFFFF, 0.5);
  AssertTrue('red ~127..128',   (TyRedOf(c)   >= 127) and (TyRedOf(c)   <= 128));
  AssertTrue('green ~127..128', (TyGreenOf(c) >= 127) and (TyGreenOf(c) <= 128));
  AssertTrue('blue ~127..128',  (TyBlueOf(c)  >= 127) and (TyBlueOf(c)  <= 128));
  AssertEquals('alpha stays opaque', 255, TyAlphaOf(c));
end;

procedure TTyAnimationCoreTest.TestAnimatorDefaults;
var a: TTyAnimator;
begin
  a := TyAnimatorInit(100, teLinear);
  AssertTrue('progress 0', Abs(a.Progress - 0.0) < 1e-6);
  AssertTrue('target 1',   Abs(a.Target   - 1.0) < 1e-6);
  AssertEquals('duration', 100, a.DurationMs);
end;

procedure TTyAnimationCoreTest.TestAnimatorAdvanceReachesTargetNoOvershoot;
var a: TTyAnimator;
begin
  a := TyAnimatorInit(100, teLinear); // Progress 0 -> Target 1, 100ms
  a.Advance(50);
  AssertTrue('after 50ms ~0.5', Abs(a.Progress - 0.5) < 1e-6);
  AssertTrue('running after 50ms', a.Running);
  a.Advance(50);
  AssertTrue('after 100ms exactly 1.0', Abs(a.Progress - 1.0) < 1e-9);
  a.Advance(50);
  AssertTrue('never overshoots past 1.0', a.Progress <= 1.0 + 1e-9);
  AssertTrue('exactly 1.0 still', Abs(a.Progress - 1.0) < 1e-9);
  AssertFalse('not running at target', a.Running);
end;

procedure TTyAnimationCoreTest.TestAnimatorReverseToZero;
var a: TTyAnimator;
begin
  a := TyAnimatorInit(100, teLinear);
  a.Advance(50);
  a.Advance(50); // now at 1.0
  a.Target := 0.0;
  AssertTrue('running again after retarget', a.Running);
  a.Advance(50);
  AssertTrue('reverse mid ~0.5', Abs(a.Progress - 0.5) < 1e-6);
  a.Advance(50);
  AssertTrue('back to 0.0 exactly', Abs(a.Progress - 0.0) < 1e-9);
  AssertFalse('not running at 0', a.Running);
end;

procedure TTyAnimationCoreTest.TestAnimatorSetTargetImmediate;
var a: TTyAnimator;
begin
  a := TyAnimatorInit(100, teLinear);
  a.SetTargetImmediate(1.0);
  AssertTrue('snaps progress=1', Abs(a.Progress - 1.0) < 1e-9);
  AssertTrue('target=1', Abs(a.Target - 1.0) < 1e-9);
  AssertFalse('not running after snap', a.Running);
  a.SetTargetImmediate(0.25);
  AssertTrue('snaps progress=0.25', Abs(a.Progress - 0.25) < 1e-9);
  AssertFalse('not running after second snap', a.Running);
end;

procedure TTyAnimationCoreTest.TestAnimatorEasedMatchesEase;
var a: TTyAnimator;
begin
  a := TyAnimatorInit(100, teEaseOutCubic);
  a.Advance(50); // progress = 0.5
  AssertTrue('Eased = TyEase(Easing, Progress)',
    Abs(a.Eased - TyEase(teEaseOutCubic, a.Progress)) < 1e-6);
end;

procedure TTyAnimationCoreTest.TestAnimatorAdvanceReturnsChanged;
var a: TTyAnimator;
begin
  a := TyAnimatorInit(100, teLinear);
  AssertTrue('advance changes -> True', a.Advance(50));
  a.Advance(50); // reaches 1.0
  AssertFalse('advance at target -> False (no change)', a.Advance(50));
end;

initialization
  RegisterTest(TTyAnimationCoreTest);
end.
