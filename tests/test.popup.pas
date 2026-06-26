unit test.popup;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types,
  fpcunit, testregistry,
  tyControls.Popup;

type
  { Pure geometry tests for TyPopupRect. }
  TPopupGeomTest = class(TTestCase)
  published
    procedure TestDropsBelowWhenRoom;
    procedure TestFlipsAboveWhenNoRoom;
  end;

  { Smoke test for TTyDropdownPopup: Create/Destroy + IsOpen, no real window. }
  TPopupSmokeTest = class(TTestCase)
  published
    procedure TestCreateDestroyNoRaise;
  end;

implementation

procedure TPopupGeomTest.TestDropsBelowWhenRoom;
var
  r: TRect;
begin
  // Anchor at y=100..120 on a 1000px-tall screen; 200px content → drops below at y=120.
  r := TyPopupRect(Rect(50, 100, 250, 120), 200, 200, 1000);
  AssertEquals('top below anchor', 120, r.Top);
  AssertEquals('height', 200, r.Bottom - r.Top);
  AssertEquals('left aligned', 50, r.Left);
  AssertEquals('width', 200, r.Right - r.Left);
end;

procedure TPopupGeomTest.TestFlipsAboveWhenNoRoom;
var
  r: TRect;
begin
  // Anchor near the bottom (y=900..920), 200px content, 1000px screen →
  // not enough room below (920+200=1120>1000), room above (900-200=700≥0) → flip above.
  r := TyPopupRect(Rect(50, 900, 250, 920), 200, 200, 1000);
  AssertEquals('bottom at anchor top', 900, r.Bottom);
  AssertEquals('top = anchor.top - height', 700, r.Top);
end;

procedure TPopupSmokeTest.TestCreateDestroyNoRaise;
var
  p: TTyDropdownPopup;
begin
  p := TTyDropdownPopup.Create;
  try
    AssertFalse('not open initially', p.IsOpen);
  finally
    p.Free;
  end;
end;

initialization
  RegisterTest(TPopupGeomTest);
  RegisterTest(TPopupSmokeTest);
end.
