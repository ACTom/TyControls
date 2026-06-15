unit test.animation.toggle;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Controls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller,
  tyControls.ToggleSwitch;
type
  { Pure-geometry tests for TyToggleKnobX (no LCL controls, no wall-clock).
    Geometry constants taken from the existing 44x24 @96ppi toggle pixel tests:
      TrackWidthDev = 44, MarginDev = 3, KnobSideDev = 18.
      OffX = MarginDev = 3.
      OnX  = TrackWidthDev - MarginDev - KnobSideDev = 44 - 3 - 18 = 23. }
  TTyToggleKnobXTest = class(TTestCase)
  published
    procedure TestKnobXOffAtProgressZero;
    procedure TestKnobXOnAtProgressOne;
    procedure TestKnobXMidpointAtProgressHalf;
    procedure TestKnobXClampsBelowZeroToOff;
    procedure TestKnobXClampsAboveOneToOn;
  end;

  { Probe subclass re-exposes RenderTo, lets tests force-enable animations
    (no wall-clock), step the knob animator a fixed number of milliseconds, and
    read back the raw knob progress. }
  TTyToggleAnimProbe = class(TTyToggleSwitch)
  public
    procedure SetAnimationsEnabled(AValue: Boolean);
    function StepAnimation(AMs: Integer): Boolean;
    procedure ArmTo(ATarget: Single);
    function KnobProgress: Single;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  { Steppable knob-slide tests (deterministic, no real timers). }
  TTyToggleKnobAnimTest = class(TTestCase)
  published
    procedure TestAnimatedCheckDoesNotSnap;
    procedure TestAnimatedAdvanceHalfwayMovesKnob;
    procedure TestAnimatedAdvanceFullReachesOnPosition;
    procedure TestHeadlessDefaultSnapsImmediately;
    procedure TestAnimationsEnabledDefaultsTrue;
  end;

implementation

const
  TrackWidthDev = 44;
  MarginDev     = 3;
  KnobSideDev   = 18;
  OffX          = MarginDev;                                   // 3
  OnX           = TrackWidthDev - MarginDev - KnobSideDev;     // 23

procedure TTyToggleKnobXTest.TestKnobXOffAtProgressZero;
begin
  AssertEquals('Progress=0 → OffX (=Margin)', OffX,
    TyToggleKnobX(TrackWidthDev, MarginDev, KnobSideDev, 0.0));
end;

procedure TTyToggleKnobXTest.TestKnobXOnAtProgressOne;
begin
  AssertEquals('Progress=1 → OnX (=44-3-18)', OnX,
    TyToggleKnobX(TrackWidthDev, MarginDev, KnobSideDev, 1.0));
end;

procedure TTyToggleKnobXTest.TestKnobXMidpointAtProgressHalf;
begin
  // Lerp(3, 23, 0.5) = 13
  AssertEquals('Progress=0.5 → midpoint 13', 13,
    TyToggleKnobX(TrackWidthDev, MarginDev, KnobSideDev, 0.5));
end;

procedure TTyToggleKnobXTest.TestKnobXClampsBelowZeroToOff;
begin
  AssertEquals('Progress<0 clamps to OffX', OffX,
    TyToggleKnobX(TrackWidthDev, MarginDev, KnobSideDev, -0.5));
end;

procedure TTyToggleKnobXTest.TestKnobXClampsAboveOneToOn;
begin
  AssertEquals('Progress>1 clamps to OnX', OnX,
    TyToggleKnobX(TrackWidthDev, MarginDev, KnobSideDev, 1.5));
end;

{ TTyToggleAnimProbe }

procedure TTyToggleAnimProbe.SetAnimationsEnabled(AValue: Boolean);
begin
  AnimationsEnabled := AValue;
end;

function TTyToggleAnimProbe.StepAnimation(AMs: Integer): Boolean;
begin
  Result := AdvanceAnimation(AMs);
end;

procedure TTyToggleAnimProbe.ArmTo(ATarget: Single);
begin
  ArmKnobAnim(ATarget);
end;

function TTyToggleAnimProbe.KnobProgress: Single;
begin
  Result := KnobAnimProgress;
end;

procedure TTyToggleAnimProbe.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

{ Helper: build a probe with the standard test stylesheet, parented to AForm,
  with the supplied controller. Caller owns nothing extra (Form owns probe). }

function RenderKnobBitmap(ASw: TTyToggleAnimProbe): TBGRABitmap;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(44, 24);
    ASw.RenderTo(Bmp.Canvas, Rect(0, 0, 44, 24), 96);
    Result := TBGRABitmap.Create(Bmp);
  finally
    Bmp.Free;
  end;
end;

{ TTyToggleKnobAnimTest }

procedure TTyToggleKnobAnimTest.TestAnimatedCheckDoesNotSnap;
{ Arming the knob slide toward the on-position (the runtime animate path, modeled
  here by ArmTo) must NOT snap: raw progress stays at 0 until the animation is
  advanced. (ArmTo is the test seam for the SetChecked+timer path, which only
  animates when the control has a window handle.) }
var
  Ctl: TTyStyleController;
  Sw: TTyToggleAnimProbe;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Sw := TTyToggleAnimProbe.Create(nil);
    try
      Sw.Controller := Ctl;
      Sw.SetAnimationsEnabled(True);
      AssertTrue('progress starts at 0', Abs(Sw.KnobProgress - 0.0) < 1e-6);
      Sw.ArmTo(1);  // arm toward on-position without snapping
      AssertTrue('armed slide does NOT snap (progress still ~0)',
        Abs(Sw.KnobProgress - 0.0) < 1e-6);
    finally
      Sw.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TTyToggleKnobAnimTest.TestAnimatedAdvanceHalfwayMovesKnob;
{ Advancing 60ms of the 120ms slide takes raw progress to ~0.5 and moves the
  knob off the left margin (it has visibly slid toward the on-position). }
var
  Ctl: TTyStyleController;
  Sw: TTyToggleAnimProbe;
  Reread: TBGRABitmap;
  PxLeft: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(
      'TyToggleSwitch { background: #444444; color: #FFFFFF; border-width: 0px; }' +
      'TyToggleSwitch:active { background: #3B82F6; }');
    Sw := TTyToggleAnimProbe.Create(nil);
    try
      Sw.Controller := Ctl;
      Sw.SetAnimationsEnabled(True);
      Sw.ArmTo(1);           // arm toward on-position without snapping
      Sw.StepAnimation(60);  // half of 120ms
      AssertTrue('raw progress ~0.5 after 60ms',
        Abs(Sw.KnobProgress - 0.5) < 1e-6);

      { The off-position knob centre is at x=12 (covers x=3..21). After sliding
        halfway the knob has left the far-left, so the formerly-knob-edge pixel
        at x=5 is no longer white (the track shows through there). }
      Reread := RenderKnobBitmap(Sw);
      try
        PxLeft := Reread.GetPixel(5, 12);
        AssertFalse('knob has slid off the far-left (x=5 no longer white)',
          (PxLeft.red > 200) and (PxLeft.green > 200) and (PxLeft.blue > 200));
      finally
        Reread.Free;
      end;
    finally
      Sw.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TTyToggleKnobAnimTest.TestAnimatedAdvanceFullReachesOnPosition;
{ Advancing the full 120ms lands raw progress exactly on 1.0 and the knob sits
  at the on-position: the right side (x=32) is knob-white. }
var
  Ctl: TTyStyleController;
  Sw: TTyToggleAnimProbe;
  Reread: TBGRABitmap;
  PxRight: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(
      'TyToggleSwitch { background: #444444; color: #FFFFFF; border-width: 0px; }' +
      'TyToggleSwitch:active { background: #3B82F6; }');
    Sw := TTyToggleAnimProbe.Create(nil);
    try
      Sw.Controller := Ctl;
      Sw.SetAnimationsEnabled(True);
      Sw.ArmTo(1);           // arm toward on-position without snapping
      Sw.StepAnimation(60);
      Sw.StepAnimation(60);  // total 120ms -> 1.0
      AssertTrue('raw progress exactly 1.0 after 120ms',
        Abs(Sw.KnobProgress - 1.0) < 1e-9);

      Reread := RenderKnobBitmap(Sw);
      try
        PxRight := Reread.GetPixel(32, 12);
        AssertTrue('ON-position knob R > 200 (white)',   PxRight.red > 200);
        AssertTrue('ON-position knob G > 200 (white)',   PxRight.green > 200);
        AssertTrue('ON-position knob B > 200 (white)',   PxRight.blue > 200);
      finally
        Reread.Free;
      end;
    finally
      Sw.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TTyToggleKnobAnimTest.TestHeadlessDefaultSnapsImmediately;
{ Headless (no window handle): setting Checked True snaps raw progress to 1.0
  immediately, so RenderTo draws the on-position right away. Animations now
  default ON, but the snap is gated on HandleAllocated, so handle-less render
  tests still settle to the final state — this keeps the existing pixel tests
  green. }
var
  Ctl: TTyStyleController;
  Sw: TTyToggleAnimProbe;
  Reread: TBGRABitmap;
  PxRight: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(
      'TyToggleSwitch { background: #444444; color: #FFFFFF; border-width: 0px; }' +
      'TyToggleSwitch:active { background: #3B82F6; }');
    Sw := TTyToggleAnimProbe.Create(nil);
    try
      Sw.Controller := Ctl;
      // animations default ON now; with no window handle SetChecked snaps
      Sw.Checked := True;
      AssertTrue('headless snap: raw progress = 1.0 immediately',
        Abs(Sw.KnobProgress - 1.0) < 1e-9);

      Reread := RenderKnobBitmap(Sw);
      try
        PxRight := Reread.GetPixel(32, 12);
        AssertTrue('snapped ON knob R > 200', PxRight.red > 200);
        AssertTrue('snapped ON knob G > 200', PxRight.green > 200);
        AssertTrue('snapped ON knob B > 200', PxRight.blue > 200);
      finally
        Reread.Free;
      end;
    finally
      Sw.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TTyToggleKnobAnimTest.TestAnimationsEnabledDefaultsTrue;
{ Motion is on out of the box: a freshly-created toggle switch has
  AnimationsEnabled True by default. (Headless render tests stay green because
  the state-change path still snaps when there is no window handle.) }
var
  Sw: TTyToggleSwitch;
begin
  Sw := TTyToggleSwitch.Create(nil);
  try
    AssertTrue('AnimationsEnabled defaults to True', Sw.AnimationsEnabled);
  finally
    Sw.Free;
  end;
end;

initialization
  RegisterTest(TTyToggleKnobXTest);
  RegisterTest(TTyToggleKnobAnimTest);
end.
