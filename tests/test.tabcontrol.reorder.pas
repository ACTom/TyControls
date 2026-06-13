unit test.tabcontrol.reorder;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, fpcunit, testregistry,
  tyControls.Types, tyControls.Panel, tyControls.TabControl;

type
  { Fresh white-box access subclass for the drag-reorder helpers. Kept separate
    from the locked subclasses in the other tabcontrol test units so the existing
    suite stays untouched. It exposes the two new public pure helpers plus the
    protected mouse handlers (down/move/up) so the gesture-integration tests can
    drive a full press-drag-release sequence headlessly. }
  TTyTabReorderAccess = class(TTyTabControl)
  public
    procedure CallMouseDown(Btn: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure CallMouseMove(Shift: TShiftState; X, Y: Integer);
    procedure CallMouseUp(Btn: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure CallMouseLeave;
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
    // Gesture integration (full press-drag-release sequences)
    procedure TestDragPastNeighborMidpointReorders;
    procedure TestDragLeftAdjacentMidpointSwaps;
    procedure TestSubThresholdMoveDoesNotReorder;
    procedure TestPlainPressReleaseSelectsAndDoesNotReorder;
    procedure TestMouseUpClearsDragState;
    procedure TestMouseLeaveClearsDragState;
  end;

implementation

{ TTyTabReorderAccess }

procedure TTyTabReorderAccess.CallMouseDown(Btn: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  MouseDown(Btn, Shift, X, Y);
end;

procedure TTyTabReorderAccess.CallMouseMove(Shift: TShiftState; X, Y: Integer);
begin
  MouseMove(Shift, X, Y);
end;

procedure TTyTabReorderAccess.CallMouseUp(Btn: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  MouseUp(Btn, Shift, X, Y);
end;

procedure TTyTabReorderAccess.CallMouseLeave;
begin
  MouseLeave;
end;

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

{ Helper: vertical mid of a header rect (any tab; the band height is shared). }
function HeaderMidY(ATab: TTyTabReorderAccess): Integer;
var R: TRect;
begin
  R := ATab.HeaderRectShifted(0);
  Result := (R.Top + R.Bottom) div 2;
end;

{ (G1) Press on header 0, then move past header 1's midpoint with ssLeft held,
  reorders the collection. TyDropIndexAt(just past mid1) resolves to index 2, so
  dragging the index-0 tab there reseats it last: [T1,T2,T3] -> [T2,T3,T1]. The
  load-bearing assertion (reuse TestReorderItemsReordersPages style) is that the
  drag moved tab 0 off the front, so caption(0) becomes the OLD caption[1]. }
procedure TTyTabReorderTest.TestDragPastNeighborMidpointReorders;
var
  Cap0Before, Cap1Before, Cap2Before: string;
  Y: Integer;
begin
  AddTabs(3);
  Cap0Before := FTab.TabCaption(0); // 'Tab 1'
  Cap1Before := FTab.TabCaption(1); // 'Tab 2'
  Cap2Before := FTab.TabCaption(2); // 'Tab 3'
  Y := HeaderMidY(FTab);

  { Press on header 0 (records the drag candidate + selects it). }
  FTab.CallMouseDown(mbLeft, [ssLeft], MidOf(0), Y);
  { Drag right, past header 1's midpoint, with the left button held. }
  FTab.CallMouseMove([ssLeft], MidOf(1) + 1, Y);
  FTab.CallMouseUp(mbLeft, [ssLeft], MidOf(1) + 1, Y);

  { Tab 0 dragged off the front -> caption(0) is the old caption[1]. }
  AssertEquals('caption[0] now old caption[1]', Cap1Before, FTab.TabCaption(0));
  AssertEquals('caption[1] now old caption[2]', Cap2Before, FTab.TabCaption(1));
  AssertEquals('caption[2] now old caption[0]', Cap0Before, FTab.TabCaption(2));
end;

{ (G1b) Dragging the last tab leftward just before header 1's midpoint resolves
  to index 1, a clean adjacent move: [T1,T2,T3] -> [T1,T3,T2]. Tab 0 is untouched
  while the dragged tab swaps with its left neighbor. }
procedure TTyTabReorderTest.TestDragLeftAdjacentMidpointSwaps;
var
  Cap0Before, Cap1Before, Cap2Before: string;
  Y: Integer;
begin
  AddTabs(3);
  Cap0Before := FTab.TabCaption(0); // 'Tab 1'
  Cap1Before := FTab.TabCaption(1); // 'Tab 2'
  Cap2Before := FTab.TabCaption(2); // 'Tab 3'
  Y := HeaderMidY(FTab);

  FTab.CallMouseDown(mbLeft, [ssLeft], MidOf(2), Y);
  FTab.CallMouseMove([ssLeft], MidOf(1) - 1, Y);
  FTab.CallMouseUp(mbLeft, [ssLeft], MidOf(1) - 1, Y);

  AssertEquals('caption[0] unchanged', Cap0Before, FTab.TabCaption(0));
  AssertEquals('caption[1] now old caption[2]', Cap2Before, FTab.TabCaption(1));
  AssertEquals('caption[2] now old caption[1]', Cap1Before, FTab.TabCaption(2));
end;

{ (G2) A sub-threshold move (|dx| < TyDragThresholdPx) does NOT reorder: the
  press selects header 0, the tiny move never crosses the drag threshold, so the
  collection order is untouched. }
procedure TTyTabReorderTest.TestSubThresholdMoveDoesNotReorder;
var
  Cap0Before, Cap1Before: string;
  Y, X0: Integer;
begin
  AddTabs(3);
  Cap0Before := FTab.TabCaption(0);
  Cap1Before := FTab.TabCaption(1);
  Y := HeaderMidY(FTab);
  X0 := MidOf(0);

  FTab.CallMouseDown(mbLeft, [ssLeft], X0, Y);
  { Move by less than the threshold (threshold is 6 at 96 PPI). }
  FTab.CallMouseMove([ssLeft], X0 + (FTab.TyDragThresholdPx(96) - 1), Y);
  FTab.CallMouseUp(mbLeft, [ssLeft], X0 + (FTab.TyDragThresholdPx(96) - 1), Y);

  AssertEquals('caption[0] unchanged', Cap0Before, FTab.TabCaption(0));
  AssertEquals('caption[1] unchanged', Cap1Before, FTab.TabCaption(1));
end;

{ (G3) A plain press + release (no move) still SELECTS the pressed tab and does
  not reorder. Protects TestMouseDownSelectsTab / the closable click path. }
procedure TTyTabReorderTest.TestPlainPressReleaseSelectsAndDoesNotReorder;
var
  Cap0Before, Cap1Before, Cap2Before: string;
  Y: Integer;
begin
  AddTabs(3);
  Cap0Before := FTab.TabCaption(0);
  Cap1Before := FTab.TabCaption(1);
  Cap2Before := FTab.TabCaption(2);
  Y := HeaderMidY(FTab);

  FTab.CallMouseDown(mbLeft, [ssLeft], MidOf(2), Y);
  FTab.CallMouseUp(mbLeft, [ssLeft], MidOf(2), Y);

  AssertEquals('plain press selects pressed tab', 2, FTab.TabIndex);
  AssertEquals('caption[0] unchanged', Cap0Before, FTab.TabCaption(0));
  AssertEquals('caption[1] unchanged', Cap1Before, FTab.TabCaption(1));
  AssertEquals('caption[2] unchanged', Cap2Before, FTab.TabCaption(2));
end;

{ (G4a) MouseUp clears the drag state: a subsequent MouseMove (with ssLeft but no
  preceding press) must NOT reorder. }
procedure TTyTabReorderTest.TestMouseUpClearsDragState;
var
  Cap0Before, Cap1Before: string;
  Y: Integer;
begin
  AddTabs(3);
  Y := HeaderMidY(FTab);

  FTab.CallMouseDown(mbLeft, [ssLeft], MidOf(0), Y);
  FTab.CallMouseUp(mbLeft, [ssLeft], MidOf(0), Y);

  Cap0Before := FTab.TabCaption(0);
  Cap1Before := FTab.TabCaption(1);
  { Drag-like move after release: no candidate is armed, so order is untouched. }
  FTab.CallMouseMove([ssLeft], MidOf(2), Y);

  AssertEquals('caption[0] unchanged after release+move', Cap0Before, FTab.TabCaption(0));
  AssertEquals('caption[1] unchanged after release+move', Cap1Before, FTab.TabCaption(1));
end;

{ (G4b) MouseLeave clears the drag state too: a subsequent MouseMove must NOT
  reorder once the pointer has left and re-entered without a fresh press. }
procedure TTyTabReorderTest.TestMouseLeaveClearsDragState;
var
  Cap0Before, Cap1Before: string;
  Y: Integer;
begin
  AddTabs(3);
  Y := HeaderMidY(FTab);

  FTab.CallMouseDown(mbLeft, [ssLeft], MidOf(0), Y);
  FTab.CallMouseLeave;

  Cap0Before := FTab.TabCaption(0);
  Cap1Before := FTab.TabCaption(1);
  FTab.CallMouseMove([ssLeft], MidOf(2), Y);

  AssertEquals('caption[0] unchanged after leave+move', Cap0Before, FTab.TabCaption(0));
  AssertEquals('caption[1] unchanged after leave+move', Cap1Before, FTab.TabCaption(1));
end;

initialization
  RegisterTest(TTyTabReorderTest);

end.
