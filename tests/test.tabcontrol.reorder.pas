unit test.tabcontrol.reorder;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, fpcunit, testregistry,
  tyControls.Types, tyControls.Panel, tyControls.TabControl;

type
  { Fresh white-box access subclass for the drag-reorder helpers. Kept separate
    from the locked subclasses in the other tabcontrol test units so the existing
    suite stays untouched. It only needs the two new public pure helpers, but
    declares a subclass anyway to mirror the established access-subclass pattern
    and keep room for future protected probes. }
  TTyTabReorderAccess = class(TTyTabControl)
  end;

  { Pure-helper tests for tab drag-reorder: the drag threshold (in device px,
    PPI-scaled) and the drop-target index resolver (which collection index a
    given X coordinate should drop before/into, using shifted header midpoints).
    3-4 tabs at 96 PPI, geometry pinned via Font.PixelsPerInch := 96. }
  TTyTabReorderTest = class(TTestCase)
  private
    FForm: TForm;
    FTab: TTyTabReorderAccess;
    procedure AddTabs(ACount: Integer);
    function MidOf(AIndex: Integer): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDragThresholdIsSmallPositivePxAt96;
    procedure TestDragThresholdScalesWithPPI;
    procedure TestDropIndexLeftOfFirstMidpointIsZero;
    procedure TestDropIndexJustPastFirstMidpoint;
    procedure TestDropIndexFarRightClampsToLast;
    procedure TestDropIndexAtExactMidpoints;
  end;

implementation

{ TTyTabReorderTest }

procedure TTyTabReorderTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 600, 400);
  FTab := TTyTabReorderAccess.Create(FForm);
  FTab.Parent := FForm;
  FTab.Font.PixelsPerInch := 96;
  { Wide enough that 3-4 short tabs never overflow, so shifted == unshifted and
    the midpoints are the plain header midpoints. }
  FTab.SetBounds(0, 0, 600, 200);
end;

procedure TTyTabReorderTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyTabReorderTest.AddTabs(ACount: Integer);
var
  I: Integer;
begin
  for I := 1 to ACount do
    FTab.AddTab('Tab ' + IntToStr(I));
end;

function TTyTabReorderTest.MidOf(AIndex: Integer): Integer;
var
  R: TRect;
begin
  R := FTab.HeaderRectShifted(AIndex);
  Result := (R.Left + R.Right) div 2;
end;

{ (1) The drag threshold at 96 PPI is a small positive number of device px
  (Scale(6) == MulDiv(6,96,96) == 6). }
procedure TTyTabReorderTest.TestDragThresholdIsSmallPositivePxAt96;
begin
  AddTabs(3);
  AssertEquals('drag threshold at 96 ppi', 6, FTab.TyDragThresholdPx(96));
end;

{ (2) The threshold scales linearly with PPI (192 -> 12, 144 -> 9). }
procedure TTyTabReorderTest.TestDragThresholdScalesWithPPI;
begin
  AddTabs(3);
  AssertEquals('drag threshold at 192 ppi', 12, FTab.TyDragThresholdPx(192));
  AssertEquals('drag threshold at 144 ppi', 9,  FTab.TyDragThresholdPx(144));
end;

{ (3) An X left of header 0's midpoint resolves to index 0. }
procedure TTyTabReorderTest.TestDropIndexLeftOfFirstMidpointIsZero;
begin
  AddTabs(3);
  AssertEquals('X at far left drops at 0', 0, FTab.TyDropIndexAt(0, 96));
  AssertEquals('X just left of mid0 drops at 0', 0,
    FTab.TyDropIndexAt(MidOf(0) - 1, 96));
end;

{ (4) An X just past header 1's midpoint resolves to the first header whose
  midpoint is right of X. Just past mid1 (but before mid2) means index 2. }
procedure TTyTabReorderTest.TestDropIndexJustPastFirstMidpoint;
begin
  AddTabs(3);
  { Just past mid0 -> first midpoint right of X is mid1 -> index 1. }
  AssertEquals('just past mid0 -> 1', 1, FTab.TyDropIndexAt(MidOf(0) + 1, 96));
  { Just past mid1 -> first midpoint right of X is mid2 -> index 2. }
  AssertEquals('just past mid1 -> 2', 2, FTab.TyDropIndexAt(MidOf(1) + 1, 96));
end;

{ (5) An X far to the right (past every midpoint) clamps to the last index. }
procedure TTyTabReorderTest.TestDropIndexFarRightClampsToLast;
begin
  AddTabs(4);
  AssertEquals('far right clamps to last', 3, FTab.TyDropIndexAt(100000, 96));
  AssertEquals('past last midpoint clamps to last', 3,
    FTab.TyDropIndexAt(MidOf(3) + 1, 96));
end;

{ (6) Exact-int verification against the shifted header midpoints. The rule is
  "first i where X < mid(i)". At X == mid(i) the strict-less test fails for i,
  so the resolver advances to i+1. Verify the boundary precisely for each tab. }
procedure TTyTabReorderTest.TestDropIndexAtExactMidpoints;
var
  M0, M1, M2: Integer;
begin
  AddTabs(3);
  M0 := MidOf(0);
  M1 := MidOf(1);
  M2 := MidOf(2);

  { X strictly below mid0 -> 0. }
  AssertEquals('mid0-1 -> 0', 0, FTab.TyDropIndexAt(M0 - 1, 96));
  { X exactly at mid0 -> not < mid0, so advance; < mid1 -> 1. }
  AssertEquals('mid0 -> 1', 1, FTab.TyDropIndexAt(M0, 96));
  { X exactly at mid1 -> advance past 0 and 1; < mid2 -> 2. }
  AssertEquals('mid1 -> 2', 2, FTab.TyDropIndexAt(M1, 96));
  { X exactly at mid2 -> no midpoint is right of X, clamp to last (2). }
  AssertEquals('mid2 -> 2 (clamp)', 2, FTab.TyDropIndexAt(M2, 96));
end;

initialization
  RegisterTest(TTyTabReorderTest);

end.
