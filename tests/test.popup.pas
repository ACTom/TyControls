unit test.popup;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types,
  fpcunit, testregistry,
  tyControls.Popup, tyControls.ListBox;

type
  { Pure geometry tests for TyPopupRect. }
  TPopupGeomTest = class(TTestCase)
  published
    procedure TestDropsBelowWhenRoom;
    procedure TestFlipsAboveWhenNoRoom;
  end;

  { Smoke test for TTyDropdownPopup: Create/Destroy + IsOpen, no real window. }
  TPopupSmokeTest = class(TTestCase)
  private
    FCloses: Integer;
    procedure OnClose(Sender: TObject);
  published
    procedure TestCreateDestroyNoRaise;
    procedure TestCloseOnHiddenIsNoOp;
    procedure TestSetContentSwaps;
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

procedure TPopupSmokeTest.OnClose(Sender: TObject);
begin
  Inc(FCloses);
end;

procedure TPopupSmokeTest.TestCloseOnHiddenIsNoOp;
var
  p: TTyDropdownPopup;
begin
  // Close is idempotent: closing a popup that was never shown must NOT fire OnClose
  // (a pick that commits+closes could otherwise re-fire it via a trailing deactivate).
  FCloses := 0;
  p := TTyDropdownPopup.Create;
  try
    p.OnClose := @OnClose;
    p.Close;
    p.Close;
    AssertEquals('no OnClose for a never-open popup', 0, FCloses);
  finally
    p.Free;
  end;
end;

procedure TPopupSmokeTest.TestSetContentSwaps;
var
  p: TTyDropdownPopup;
  a, b: TTyListBox;
begin
  // SetContent must SWAP (not latch the first control) so one popup can host an enum list then a
  // colour list — TTyValueListEditor relies on this.
  p := TTyDropdownPopup.Create;
  a := TTyListBox.Create(nil);
  b := TTyListBox.Create(nil);
  try
    p.SetContent(a);
    AssertTrue('a hosted in the popup form', a.Parent = p.Form);
    p.SetContent(b);
    AssertTrue('b now hosted', b.Parent = p.Form);
    AssertTrue('a un-parented on swap', a.Parent = nil);
    p.SetContent(b);   // same control -> no-op
    AssertTrue('b still hosted after re-set', b.Parent = p.Form);
  finally
    a.Free; b.Free; p.Free;
  end;
end;

initialization
  RegisterTest(TPopupGeomTest);
  RegisterTest(TPopupSmokeTest);
end.
