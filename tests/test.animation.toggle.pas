unit test.animation.toggle;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
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

initialization
  RegisterTest(TTyToggleKnobXTest);
end.
