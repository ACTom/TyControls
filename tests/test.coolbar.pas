unit test.coolbar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, LCLType,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.Panel, tyControls.ControlBar, tyControls.CoolBar;

type
  { Pure band math — the headless-tested core (no window handle). }
  TCoolBarMathTest = class(TTestCase)
  published
    procedure TestResizeGrows;
    procedure TestResizeClampsToMin;
    procedure TestResizeClampsToMax;
    procedure TestResizeUnboundedWhenMaxNonPositive;
    procedure TestResizeInvertedRangeCollapsesToFloor;
    procedure TestResizeMinFlooredAtOne;
    procedure TestGripperHitInside;
    procedure TestGripperHitOutsideRight;
    procedure TestGripperHitOutsideVertical;
    procedure TestGripperHitZeroWidthNeverHits;
    // per-band packing (the CoolBar shape, as opposed to a ControlBar's one grip per row)
    procedure TestPackGivesEveryBandItsOwnGripper;
    procedure TestPackWrapsWhenABandDoesNotFit;
    procedure TestPackHonoursAnExplicitBreak;
    procedure TestPackFirstBandCannotBreak;
    procedure TestPackClampsABandWiderThanTheRow;
    // what a grip drag MEANS
    procedure TestDragBelowThresholdDecidesNothing;
    procedure TestVerticalDragMovesTheBand;
    procedure TestHorizontalDragResizes;
    procedure TestVerticalWinsAMixedDrag;
    procedure TestPackReservesRoomForABandCaption;
    // vertical
    procedure TestVerticalPackRunsBandsDownAColumn;
    procedure TestVerticalPackWrapsIntoTheNextColumn;
    procedure TestVerticalPackHonoursABreak;
    // which band a gripper's seam belongs to
    procedure TestSeamOwnerIsThePrecedingBandOnTheRow;
    procedure TestSeamOwnerSkipsBandsOnOtherRows;
    procedure TestRowLeadingBandHasNoSeam;
    procedure TestSeamOwnerVerticalUsesColumns;
    procedure TestSeamOwnerOutOfRange;
    // where a dragged band lands
    procedure TestDropPastANeighbourReorders;
    procedure TestDropBeforeANeighbourReorders;
    procedure TestDropOnItselfChangesNothing;
    procedure TestDropBelowTheLastRowAsksForANewRow;
    procedure TestDropMirroredFlipsTheMidpointTest;
    procedure TestDropOffEveryRowChangesNothing;
    procedure TestDropVerticalTransposesTheAxes;
    // making room on a full row for a band that wants to rejoin it
    procedure TestMakeRoomLeavesAFittingRowAlone;
    procedure TestMakeRoomChargesTheLeadsAndTheGaps;
    procedure TestMakeRoomTakesFromTheNearestBandBeforeTheDrop;
    procedure TestMakeRoomSpillsBackwardsWhenTheNearestBottomsOut;
    procedure TestMakeRoomFallsBackToTheFarSideOfTheDrop;
    procedure TestMakeRoomNeverGoesBelowAMinimum;
    procedure TestMakeRoomRefusesWholeRatherThanHalfApplying;
  end;

  { A band content that DECLARES how wide it wants to be. The content cap has to be measured
    against an exact number; a real control's preferred width depends on the machine's fonts
    and the active theme, which would make the cap tests read as "roughly". }
  TDeclaredWidthPanel = class(TTyPanel)
  private
    FDeclared: Integer;
    procedure SetDeclared(AValue: Integer);
  protected
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
  public
    property Declared: Integer read FDeclared write SetDeclared;
  end;

  { A probe exposing the protected geometry + the private band map indirectly. }
  TCoolBarAccess = class(TTyCoolBar)
  public
    function StyleTypeKey: string;
    function BandRect(ACtl: TControl): TRect;
    function GripPx: Integer;
    function ContentBox: TRect;
    function SeamOwner(ACtl: TControl): TControl;
    function ContentCap(ACtl: TControl): Integer;
    function LeadPx(ACtl: TControl): Integer;
    procedure CallMouseDown(X, Y: Integer);
    procedure CallMouseMove(X, Y: Integer);
    procedure CallMouseUp(X, Y: Integer);
  end;

  { The control: the per-child band map — keyed, drop-on-free, clamp defaults. }
  TCoolBarControlTest = class(TTestCase)
  private
    FForm: TForm;
    FChangeCount: Integer;
    procedure CountChange(Sender: TObject);
    function MakeBand(AParent: TWinControl; AL, AT, AW, AH: Integer): TControl;
    function MakeOverflowedPair(CB: TCoolBarAccess; out b0, b1: TControl): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKeyIsPanel;
    procedure TestSetGetBandWidth;
    procedure TestBandWidthKeyedByControl;
    procedure TestBandMapDroppedOnFree;
    procedure TestDefaultMinWidthWhenUnset;
    procedure TestPerBandMinOverridesDefault;
    procedure TestMaxWidthUnboundedByDefault;
    procedure TestBandRectIsRowLeftGripper;
    procedure TestEveryBandIsGrippable;
    procedure TestHidingABandTakesItOutOfTheLayout;
    procedure TestFixedBandRefusesAResize;
    procedure TestLayoutChangeFiresOnChange;
    // the designable band collection
    procedure TestPerControlApiAndCollectionAreOneState;
    procedure TestEditingTheCollectionRelaysAndNotifies;
    procedure TestFreeingAChildDropsItsBand;
    procedure TestBandDisplayNamePrefersItsCaption;
    procedure TestVerticalPutsTheGripAboveTheBand;
    procedure TestGripperDragMovesTheSeamNotTheDraggedBand;
    procedure TestGripperDragHonoursMinClamp;
    procedure TestRowLeadingGripperIsAMoveNotAResize;
    procedure TestDragPastANeighbourReordersTheBands;
    procedure TestDragBelowTheLastRowGivesTheBandItsOwnRow;
    procedure TestDragBelowTheLastRowMovesAnAlreadyBrokenBand;
    // the user's report: a band pushed down by OVERFLOW can be dragged back up
    procedure TestDragBackUpSqueezesTheRowAndRejoinsIt;
    procedure TestRejoinIsNotSwallowedByTheReorder;
    procedure TestRejoinTakesFromTheBandItLandsNextTo;
    procedure TestRejoinHonoursAnExplicitBandMinWidth;
    procedure TestRejoinFallsBackToDefaultBandMinWidth;
    procedure TestRejoinThatCannotFitChangesNothingAtAll;
    procedure TestVerticalRejoinSqueezesTheColumnOnTheOtherAxis;
    // capping a widening drag at the hosted control's own content
    procedure TestAutoMaxWidthIsOffByDefault;
    procedure TestAutoMaxWidthCapsAtTheDeclaredContentWidth;
    procedure TestAutoMaxWidthStopsAGripperDragAtTheContentEdge;
    procedure TestAutoMaxWidthLeavesAnOpinionlessControlUncapped;
    procedure TestAutoMaxWidthTakesWhicheverCeilingBindsFirst;
    procedure TestAutoMaxWidthHonoursTheControlsOwnConstraint;
    procedure TestABandWithNoControlIsNeverInTheLayout;
  end;

implementation

{ TCoolBarAccess }
function TCoolBarAccess.StyleTypeKey: string;               begin Result := GetStyleTypeKey; end;
function TCoolBarAccess.BandRect(ACtl: TControl): TRect;    begin Result := BandRectFor(ACtl); end;
function TCoolBarAccess.GripPx: Integer;                    begin Result := GripperWidthPx; end;
function TCoolBarAccess.ContentBox: TRect;                  begin Result := BandContentRect; end;
function TCoolBarAccess.SeamOwner(ACtl: TControl): TControl; begin Result := SeamOwnerOf(ACtl); end;
function TCoolBarAccess.ContentCap(ACtl: TControl): Integer; begin Result := BandContentCap(ACtl); end;
function TCoolBarAccess.LeadPx(ACtl: TControl): Integer;    begin Result := BandLeadPx(ACtl); end;
procedure TCoolBarAccess.CallMouseDown(X, Y: Integer);      begin MouseDown(mbLeft, [ssLeft], X, Y); end;
procedure TCoolBarAccess.CallMouseMove(X, Y: Integer);      begin MouseMove([ssLeft], X, Y); end;
procedure TCoolBarAccess.CallMouseUp(X, Y: Integer);        begin MouseUp(mbLeft, [], X, Y); end;

{ TDeclaredWidthPanel }
procedure TDeclaredWidthPanel.SetDeclared(AValue: Integer);
begin
  if FDeclared = AValue then Exit;
  FDeclared := AValue;
  { LCL CACHES the answer (cfPreferredSizeValid / cfPreferredMinSizeValid), so a test that set
    the number after something had already asked would keep measuring the old one. }
  InvalidatePreferredSize;
end;

procedure TDeclaredWidthPanel.CalculatePreferredSize(var PreferredWidth,
  PreferredHeight: Integer; WithThemeSpace: Boolean);
begin
  { Answered for BOTH forms: the cap asks with WithThemeSpace=False, which routes to the
    FPreferredMin* pair, and answering only the themed one would leave it reading 0. }
  if WithThemeSpace then ;
  PreferredWidth := FDeclared;
  PreferredHeight := 0;
end;

{ =========================== pure math =========================== }

procedure TCoolBarMathTest.TestResizeGrows;
begin
  // start 100, drag +30, min 20, max 300 -> 130
  AssertEquals('grows by dx', 130, TyCoolBandResize(100, 30, 20, 300));
  AssertEquals('shrinks by dx', 70, TyCoolBandResize(100, -30, 20, 300));
end;

procedure TCoolBarMathTest.TestResizeClampsToMin;
begin
  // drag far left below the floor -> clamped to min
  AssertEquals('clamped to min', 20, TyCoolBandResize(100, -500, 20, 300));
end;

procedure TCoolBarMathTest.TestResizeClampsToMax;
begin
  AssertEquals('clamped to max', 300, TyCoolBandResize(100, 500, 20, 300));
end;

procedure TCoolBarMathTest.TestResizeUnboundedWhenMaxNonPositive;
begin
  // max <= 0 means unbounded — only the floor applies
  AssertEquals('unbounded max grows freely', 5000, TyCoolBandResize(100, 4900, 20, 0));
  AssertEquals('unbounded (negative) max grows freely', 5000, TyCoolBandResize(100, 4900, 20, -1));
end;

procedure TCoolBarMathTest.TestResizeInvertedRangeCollapsesToFloor;
begin
  // max < min is nonsense -> collapse the range to the floor
  AssertEquals('inverted range -> floor', 50, TyCoolBandResize(100, 500, 50, 10));
end;

procedure TCoolBarMathTest.TestResizeMinFlooredAtOne;
begin
  // a zero/negative min is floored at 1 so a band never vanishes
  AssertEquals('min floored at 1', 1, TyCoolBandResize(100, -500, 0, 300));
  AssertEquals('min floored at 1 (neg)', 1, TyCoolBandResize(100, -500, -9, 300));
end;

procedure TCoolBarMathTest.TestGripperHitInside;
begin
  // band (10..200, 0..40), gripper 10 -> the 10..20 column
  AssertTrue('point on gripper', TyCoolGripperHit(Rect(10, 0, 200, 40), 10, Point(12, 20)));
  AssertTrue('left edge inclusive', TyCoolGripperHit(Rect(10, 0, 200, 40), 10, Point(10, 0)));
end;

procedure TCoolBarMathTest.TestGripperHitOutsideRight;
begin
  // x=20 is just past the half-open right edge (10+10)
  AssertFalse('past the gripper column', TyCoolGripperHit(Rect(10, 0, 200, 40), 10, Point(20, 20)));
  AssertFalse('well past', TyCoolGripperHit(Rect(10, 0, 200, 40), 10, Point(150, 20)));
end;

procedure TCoolBarMathTest.TestGripperHitOutsideVertical;
begin
  AssertFalse('above band', TyCoolGripperHit(Rect(10, 5, 200, 40), 10, Point(12, 2)));
  AssertFalse('bottom exclusive', TyCoolGripperHit(Rect(10, 0, 200, 40), 10, Point(12, 40)));
end;

procedure TCoolBarMathTest.TestGripperHitZeroWidthNeverHits;
begin
  AssertFalse('no gripper -> no hit', TyCoolGripperHit(Rect(10, 0, 200, 40), 0, Point(10, 20)));
end;

{ =========================== control =========================== }

procedure TCoolBarControlTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 500, 300);
end;

procedure TCoolBarControlTest.TearDown;
begin
  FForm.Free;
end;

function TCoolBarControlTest.MakeBand(AParent: TWinControl; AL, AT, AW, AH: Integer): TControl;
var c: TTyPanel;
begin
  c := TTyPanel.Create(AParent);
  c.Parent := AParent;
  c.SetBounds(AL, AT, AW, AH);
  Result := c;
end;

procedure TCoolBarControlTest.TestTypeKeyIsPanel;
var CB: TCoolBarAccess;
begin
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  AssertEquals('owns TyCoolBar', 'TyCoolBar', CB.StyleTypeKey);
end;

procedure TCoolBarControlTest.TestSetGetBandWidth;
var CB: TCoolBarAccess; b: TControl;
begin
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := MakeBand(CB, 0, 0, 80, 30);
  AssertEquals('unset band width is 0 (auto)', 0, CB.GetBandWidth(b));
  CB.SetBandWidth(b, 140);
  AssertEquals('band width stored', 140, CB.GetBandWidth(b));
  AssertEquals('child width follows the given band width', 140, b.Width);
end;

procedure TCoolBarControlTest.TestBandWidthKeyedByControl;
var CB: TCoolBarAccess; b1, b2: TControl;
begin
  // The map is keyed by control, not by position: removing one band must not shift
  // the OTHER band's stored width.
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b1 := MakeBand(CB, 0, 0, 80, 30);
  b2 := MakeBand(CB, 90, 0, 80, 30);
  CB.SetBandWidth(b1, 120);
  CB.SetBandWidth(b2, 200);
  b1.Free;                       // drops b1's entry (opRemove)
  AssertEquals('b2 keeps its width after b1 freed', 200, CB.GetBandWidth(b2));
end;

procedure TCoolBarControlTest.TestBandMapDroppedOnFree;
var CB: TCoolBarAccess; b: TControl;
begin
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := MakeBand(CB, 0, 0, 80, 30);
  CB.SetBandWidth(b, 150);
  CB.SetBandMinWidth(b, 40);
  b.Free;
  // A fresh band placed where b was must read as unset (0), proving the old entry went.
  b := MakeBand(CB, 0, 0, 80, 30);
  AssertEquals('freed band metadata dropped', 0, CB.GetBandWidth(b));
  AssertEquals('freed band min dropped -> default', 24, CB.BandMinWidth(b));
end;

procedure TCoolBarControlTest.TestDefaultMinWidthWhenUnset;
var CB: TCoolBarAccess; b: TControl;
begin
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := MakeBand(CB, 0, 0, 80, 30);
  AssertEquals('unset min -> DefaultBandMinWidth', 24, CB.BandMinWidth(b));
end;

procedure TCoolBarControlTest.TestPerBandMinOverridesDefault;
var CB: TCoolBarAccess; b: TControl;
begin
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := MakeBand(CB, 0, 0, 80, 30);
  CB.SetBandMinWidth(b, 64);
  AssertEquals('per-band min wins over default', 64, CB.BandMinWidth(b));
end;

procedure TCoolBarControlTest.TestMaxWidthUnboundedByDefault;
var CB: TCoolBarAccess; b: TControl;
begin
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := MakeBand(CB, 0, 0, 80, 30);
  AssertEquals('unset max is 0 (unbounded)', 0, CB.BandMaxWidth(b));
  CB.SetBandMaxWidth(b, 300);
  AssertEquals('max stored', 300, CB.BandMaxWidth(b));
end;

procedure TCoolBarControlTest.TestBandRectIsRowLeftGripper;
var CB: TCoolBarAccess; b: TControl; r: TRect;
begin
  { A CoolBar gives EVERY band its own gripper, immediately to the band's left -- so the band
    rect IS that gripper strip, not the whole child. Under the inherited ControlBar model it was
    one grip per ROW and this rect spanned the child; that model is why band 2 in the containers
    demo had no handle at all. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  { The child is placed where the LAYOUT would place a first-of-row band: content left + gripW.
    It used to be placed at a bare 10 with the gripper expected to reach 0 -- which pinned the
    pre-fix geometry, in which the gripper backed onto the frame stroke and a band sat on top
    of it. Everything here is now expressed relative to the content box. }
  b := MakeBand(CB, CB.ContentBox.Left + 10, CB.ContentBox.Top, 80, 30);
  AssertEquals('gripper is 10px at 96 PPI', 10, CB.GripPx);
  r := CB.BandRect(b);
  AssertEquals('gripper starts a grip-width left of the child, inside the frame',
    CB.ContentBox.Left, r.Left);
  AssertEquals('and ends where the child begins', CB.ContentBox.Left + 10, r.Right);
  AssertEquals('band top = child top', CB.ContentBox.Top, r.Top);
  AssertEquals('band bottom = child bottom', CB.ContentBox.Top + 30, r.Bottom);
end;

procedure TCoolBarControlTest.TestEveryBandIsGrippable;
var CB: TCoolBarAccess; b0, b1: TControl; r0, r1: TRect;
begin
  { The reported bug, inverted into a guard. This test used to assert the OPPOSITE -- that a
    band which is not first on its row has no gripper -- which is a ControlBar's one-grip-per-row
    model wearing a CoolBar's name, and is exactly why the demo's second band had no handle to
    grab. Every band owns a gripper, and each one is its OWN, not a shared row-left column. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b0 := MakeBand(CB, 10, 0, 80, 30);
  b1 := MakeBand(CB, 200, 0, 80, 30);   // further right on the SAME row
  r0 := CB.BandRect(b0);
  r1 := CB.BandRect(b1);
  AssertFalse('the first band is grippable', IsRectEmpty(r0));
  AssertFalse('so is the second', IsRectEmpty(r1));
  AssertTrue('and they are different grippers, not one shared column', r0.Left <> r1.Left);
  AssertEquals('the second grip sits just left of its own band', 190, r1.Left);
  AssertEquals('and ends where that band begins', 200, r1.Right);
end;

procedure TCoolBarControlTest.CountChange(Sender: TObject);
begin
  Inc(FChangeCount);
end;

{ ── a gripper moves the SEAM, not its own band ─────────────────────────────────
  These two USED TO assert the opposite: that dragging the FIRST band's gripper resized THAT
  band. Both halves of that were wrong. A rebar gripper is the boundary between its band and
  the one before it on the row, so a drag resizes the PREDECESSOR
  (lcl/include/coolbar.inc:938); and the first band on a row has no predecessor, so its
  gripper is not a resize handle at all -- the reference makes that gesture a move
  (coolbar.inc:899). The old tests pinned the defect the user reported, which is why the suite
  stayed green while the gesture was visibly wrong. }

procedure TCoolBarControlTest.TestGripperDragMovesTheSeamNotTheDraggedBand;
var CB: TCoolBarAccess; b0, b1: TControl;
begin
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  { Two bands on ONE row. b1's gripper is the seam between them, so dragging it right must grow
    b0 -- the band to its LEFT -- and leave b1's own assigned width alone. }
  b0 := MakeBand(CB, CB.ContentBox.Left + 10, CB.ContentBox.Top, 80, 30);
  b1 := MakeBand(CB, CB.ContentBox.Left + 200, CB.ContentBox.Top, 80, 30);
  CB.SetBandWidth(b0, 80);
  CB.SetBandWidth(b1, 80);
  // b1's gripper column is the 10px strip immediately left of b1.
  CB.CallMouseDown(CB.ContentBox.Left + 195, CB.ContentBox.Top + 15);
  CB.CallMouseMove(CB.ContentBox.Left + 245, CB.ContentBox.Top + 15);   // +50 px
  CB.CallMouseUp(CB.ContentBox.Left + 245, CB.ContentBox.Top + 15);
  AssertEquals('the band BEFORE the grabbed one grew by the drag delta', 130,
    CB.GetBandWidth(b0));
  AssertEquals('and the grabbed band was NOT resized in isolation', 80, CB.GetBandWidth(b1));
end;

procedure TCoolBarControlTest.TestGripperDragHonoursMinClamp;
var CB: TCoolBarAccess; b0, b1: TControl;
begin
  { The clamp that applies is the SEAM OWNER's, since that is the band being resized. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b0 := MakeBand(CB, CB.ContentBox.Left + 10, CB.ContentBox.Top, 80, 30);
  b1 := MakeBand(CB, CB.ContentBox.Left + 200, CB.ContentBox.Top, 80, 30);
  CB.SetBandWidth(b0, 80);
  CB.SetBandMinWidth(b0, 50);
  CB.CallMouseDown(CB.ContentBox.Left + 195, CB.ContentBox.Top + 15);
  CB.CallMouseMove(CB.ContentBox.Left + 195 - 500, CB.ContentBox.Top + 15);  // far past the floor
  CB.CallMouseUp(CB.ContentBox.Left + 195 - 500, CB.ContentBox.Top + 15);
  AssertEquals('drag clamps to the seam owner''s min', 50, CB.GetBandWidth(b0));
  if b1 = nil then ;
end;

procedure TCoolBarControlTest.TestDragPastANeighbourReordersTheBands;
var CB: TCoolBarAccess; b0, b1: TControl; L, T: Integer;
begin
  { The user's question, as a test: can the toolbar band be dragged BEHIND the search band?
    Yes -- and "behind" is a real reorder of the child list, which is what the packer reads, so
    the new order survives the next relayout instead of being cosmetic. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  L := CB.ContentBox.Left;
  T := CB.ContentBox.Top;
  b0 := MakeBand(CB, L + 10, T, 80, 30);     // the "Open/Save" toolbar
  b1 := MakeBand(CB, L + 200, T, 80, 30);    // the search box
  AssertEquals('b0 starts first in the child list', 0, CB.GetControlIndex(b0));

  // Grab b0's gripper and drag right, past b1's midpoint (b1 spans 200..280, midpoint 240).
  CB.CallMouseDown(L + 5, T + 15);
  CB.CallMouseMove(L + 250, T + 15);
  CB.CallMouseUp(L + 250, T + 15);

  AssertEquals('the dragged band really moved behind its neighbour', 1,
    CB.GetControlIndex(b0));
  AssertEquals('and the neighbour took its place', 0, CB.GetControlIndex(b1));
end;

procedure TCoolBarControlTest.TestDragBelowTheLastRowGivesTheBandItsOwnRow;
var CB: TCoolBarAccess; b0, b1: TControl; L, T: Integer;
begin
  { The other half of the user's question: can it be dragged UNDER the search band? Below every
    row means a row of its own -- the reference's cNewRowBelow. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  L := CB.ContentBox.Left;
  T := CB.ContentBox.Top;
  b0 := MakeBand(CB, L + 10, T, 80, 30);
  b1 := MakeBand(CB, L + 200, T, 80, 30);
  AssertFalse('no band starts a new row yet', CB.BandBreak(b0));

  // Drag b0's gripper well below the single row (the bands are 30 tall, from T).
  CB.CallMouseDown(L + 5, T + 15);
  CB.CallMouseMove(L + 30, T + 120);
  CB.CallMouseUp(L + 30, T + 120);

  AssertTrue('the band now starts a row of its own', CB.BandBreak(b0));
  AssertEquals('and it moved to the end of the list, so it breaks its OWN row rather than '
    + 'splitting the bands after it onto a third', 1, CB.GetControlIndex(b0));
  if b1 = nil then ;
end;

procedure TCoolBarControlTest.TestDragBelowTheLastRowMovesAnAlreadyBrokenBand;
var CB: TCoolBarAccess; b0, b1: TControl; L, T: Integer;
begin
  { The band already starts a row, so setting Break is a no-op -- and BandsChanged, which is
    what normally relays and fires OnChange, never runs. The list order still changed, so the
    move has to be reported anyway or it is applied to the model and invisible on screen. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  L := CB.ContentBox.Left;
  T := CB.ContentBox.Top;
  b0 := MakeBand(CB, L + 10, T, 80, 30);
  b1 := MakeBand(CB, L + 200, T, 80, 30);
  CB.SetBandBreak(b0, True);
  AssertTrue('precondition: b0 already starts a row', CB.BandBreak(b0));
  FChangeCount := 0;
  CB.OnChange := @CountChange;

  CB.CallMouseDown(L + 5, T + 15);
  CB.CallMouseMove(L + 30, T + 120);      // below every row
  CB.CallMouseUp(L + 30, T + 120);

  AssertEquals('it still moved to the end of the list', 1, CB.GetControlIndex(b0));
  AssertTrue('and the move was reported even though Break did not change',
    FChangeCount > 0);
  if b1 = nil then ;
end;

procedure TCoolBarControlTest.TestRowLeadingGripperIsAMoveNotAResize;
var CB: TCoolBarAccess; b0, b1: TControl;
begin
  { The band that OPENS a row has no seam under its gripper. The reference turns that drag into
    a move rather than letting it resize anything (coolbar.inc:899). Nothing may change width. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b0 := MakeBand(CB, CB.ContentBox.Left + 10, CB.ContentBox.Top, 80, 30);
  b1 := MakeBand(CB, CB.ContentBox.Left + 200, CB.ContentBox.Top, 80, 30);
  CB.SetBandWidth(b0, 80);
  CB.SetBandWidth(b1, 80);
  AssertTrue('precondition: b0 really does open the row', CB.SeamOwner(b0) = nil);
  CB.CallMouseDown(CB.ContentBox.Left + 5, CB.ContentBox.Top + 15);      // b0's own gripper
  CB.CallMouseMove(CB.ContentBox.Left + 55, CB.ContentBox.Top + 15);     // sideways
  CB.CallMouseUp(CB.ContentBox.Left + 55, CB.ContentBox.Top + 15);
  AssertEquals('the leading band did not resize itself', 80, CB.GetBandWidth(b0));
  AssertEquals('and neither did its neighbour', 80, CB.GetBandWidth(b1));
end;

{ ── per-band packing ───────────────────────────────────────────────────────────
  A ControlBar reserves ONE gripper per row, at the row's left edge, so only the first
  control on a row is grabbable. A CoolBar gives EVERY band its own gripper -- which is what
  makes an individual band draggable, and what Delphi's and Lazarus's TCoolBar draw. These
  pin that difference and the row-breaking rules. }

type TSizeArr = array of TSize;

{ Vertical bands are sized on the OTHER axis, so the heights must go into cy -- putting them in
  cx silently measured every band as the fixed 24 the horizontal helper fills in. }
function SizesV(const AH: array of Integer): TSizeArr;
var i: Integer;
begin
  SetLength(Result, Length(AH));
  for i := 0 to High(AH) do
  begin
    Result[i].cx := 24;
    Result[i].cy := AH[i];
  end;
end;

function Sizes(const AW: array of Integer): TSizeArr;
var i: Integer;
begin
  SetLength(Result, Length(AW));
  for i := 0 to High(AW) do
  begin
    Result[i].cx := AW[i];
    Result[i].cy := 24;
  end;
end;

procedure TCoolBarMathTest.TestPackGivesEveryBandItsOwnGripper;
var r: TTyRectArray;
begin
  // Two bands that fit on one row: each starts a gripper-width past where the previous ended.
  r := TyCoolBarPack(Sizes([100, 80]), [], [], 400, 24, 10, 4);
  AssertEquals('band 0 starts after its own gripper', 10, r[0].Left);
  AssertEquals('band 0 ends where its width says', 110, r[0].Right);
  // band 1: 110 + spacing 4 = 114, then ITS gripper -> 124
  AssertEquals('band 1 starts after ITS OWN gripper too', 124, r[1].Left);
  AssertEquals('both on the same row', r[0].Top, r[1].Top);
end;

procedure TCoolBarMathTest.TestPackWrapsWhenABandDoesNotFit;
var r: TTyRectArray;
begin
  r := TyCoolBarPack(Sizes([100, 100]), [], [], 150, 24, 10, 4);
  AssertEquals('band 0 on row 0', 0, r[0].Top);
  AssertTrue('band 1 wrapped to the next row', r[1].Top > r[0].Top);
  AssertEquals('and restarts at the row left, past its gripper', 10, r[1].Left);
end;

procedure TCoolBarMathTest.TestPackHonoursAnExplicitBreak;
var r: TTyRectArray;
begin
  { The point of dragging a band onto its own row: it must break even though it FITS where
    it was. Without this the packer would simply put it back. }
  r := TyCoolBarPack(Sizes([100, 80]), [False, True], [], 400, 24, 10, 4);
  AssertTrue('the broken band moved to a new row', r[1].Top > r[0].Top);
  AssertEquals('and starts at the row left', 10, r[1].Left);
end;

procedure TCoolBarMathTest.TestPackFirstBandCannotBreak;
var r: TTyRectArray;
begin
  // There is no row above the first band to leave, so a Break on it must be inert.
  r := TyCoolBarPack(Sizes([100]), [True], [], 400, 24, 10, 4);
  AssertEquals('first band stays on row 0', 0, r[0].Top);
end;

procedure TCoolBarMathTest.TestPackClampsABandWiderThanTheRow;
var r: TTyRectArray;
begin
  // A band wider than the bar must fit its own row exactly rather than overflow it.
  r := TyCoolBarPack(Sizes([500]), [], [], 200, 24, 10, 4);
  AssertEquals('clamped to the row', 200, r[0].Right);
  AssertTrue('never negative', r[0].Right >= r[0].Left);
end;

{ ── what a grip drag means ─────────────────────────────────────────────────────
  A CoolBar's gripper does two jobs and the pointer's direction picks between them, as in
  Delphi's and Lazarus's TCoolBar. Resizing every band by its handle -- which is all ours used
  to do -- is a ControlBar's idea; the handle is there to MOVE the band. }

procedure TCoolBarMathTest.TestDragBelowThresholdDecidesNothing;
begin
  // A twitch must not silently resize or move anything.
  AssertTrue('still', TyCoolDragMode(0, 0, 4) = cdNone);
  AssertTrue('under threshold both ways', TyCoolDragMode(3, 3, 4) = cdNone);
end;

procedure TCoolBarMathTest.TestVerticalDragMovesTheBand;
begin
  AssertTrue('down moves', TyCoolDragMode(0, 20, 4) = cdMove);
  AssertTrue('up moves too', TyCoolDragMode(0, -20, 4) = cdMove);
end;

procedure TCoolBarMathTest.TestHorizontalDragResizes;
begin
  AssertTrue('right resizes', TyCoolDragMode(20, 0, 4) = cdResize);
  AssertTrue('left resizes', TyCoolDragMode(-20, 0, 4) = cdResize);
end;

procedure TCoolBarMathTest.TestVerticalWinsAMixedDrag;
begin
  { Dragging a band down to another row is never perfectly vertical. If a sideways wobble could
    flip the meaning, the band would resize instead of moving -- the drag has to commit to the
    axis the user is actually travelling along. }
  AssertTrue('mostly down is a move', TyCoolDragMode(6, 20, 4) = cdMove);
  AssertTrue('mostly sideways is a resize', TyCoolDragMode(20, 6, 4) = cdResize);
end;

procedure TCoolBarMathTest.TestPackReservesRoomForABandCaption;
var r: TTyRectArray;
begin
  { With ShowText on, a band's caption lives between its gripper and its child, so the packer
    has to reserve it -- otherwise the caption is drawn over the control it labels. }
  r := TyCoolBarPack(Sizes([100, 80]), [], [0, 40], 400, 24, 10, 4);
  AssertEquals('band 0 has no caption, so grip only', 10, r[0].Left);
  // band 1: 110 + spacing 4 = 114, then grip 10 + caption 40
  AssertEquals('band 1 starts past its grip AND its caption', 164, r[1].Left);
end;

procedure TCoolBarControlTest.TestHidingABandTakesItOutOfTheLayout;
var CB: TCoolBarAccess; b0, b1: TControl;
begin
  { Band visibility is the child's own Visible -- one source of truth, so the packer, the
    hit-test and the painter cannot disagree about whether a band is there. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b0 := MakeBand(CB, 10, 0, 80, 30);
  b1 := MakeBand(CB, 200, 0, 80, 30);
  AssertTrue('both start visible', CB.BandVisible(b0) and CB.BandVisible(b1));
  CB.SetBandVisible(b1, False);
  AssertFalse('hidden band reports hidden', CB.BandVisible(b1));
  AssertFalse('and the child really is hidden', b1.Visible);
  AssertTrue('a hidden band has no gripper to grab', IsRectEmpty(CB.BandRect(b1)) or (not b1.Visible));
end;

procedure TCoolBarControlTest.TestFixedBandRefusesAResize;
var CB: TCoolBarAccess; b0, b1: TControl; w0: Integer;
begin
  { FixedSize stops a RESIZE, not a move: nailing a width down is not nailing the band down.

    It is the SEAM OWNER's FixedSize that decides, because that is the band a gripper drag
    would resize (coolbar.inc:903 gates on FVisiBands[aBand-1].FFixedSize). This test used to
    set FixedSize on a lone first-of-row band and drag its own gripper -- which under the
    corrected semantics is a MOVE, so it would have passed no matter what the FixedSize check
    did. Now it drags a real seam. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b0 := MakeBand(CB, CB.ContentBox.Left + 10, CB.ContentBox.Top, 80, 30);
  b1 := MakeBand(CB, CB.ContentBox.Left + 200, CB.ContentBox.Top, 80, 30);
  CB.SetBandWidth(b0, 80);
  CB.SetBandFixedSize(b0, True);
  AssertSame('precondition: b0 really is the seam under b1''s gripper', b0, CB.SeamOwner(b1));
  w0 := CB.GetBandWidth(b0);
  CB.CallMouseDown(CB.ContentBox.Left + 195, CB.ContentBox.Top + 15);   // b1's gripper
  CB.CallMouseMove(CB.ContentBox.Left + 255, CB.ContentBox.Top + 15);   // clearly horizontal
  CB.CallMouseUp(CB.ContentBox.Left + 255, CB.ContentBox.Top + 15);
  AssertEquals('a fixed band keeps its width even when its seam is dragged', w0,
    CB.GetBandWidth(b0));
  AssertTrue('but it is still movable', CB.BandFixedSize(b0));
end;

procedure TCoolBarControlTest.TestLayoutChangeFiresOnChange;
var CB: TCoolBarAccess; b: TControl;
begin
  // An app that persists its band layout has to be told when the layout moved.
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := MakeBand(CB, 10, 0, 80, 30);
  FChangeCount := 0;
  CB.OnChange := @CountChange;
  CB.SetBandBreak(b, True);
  AssertTrue('moving a band to another row notifies', FChangeCount > 0);
  FChangeCount := 0;
  CB.SetBandVisible(b, False);
  AssertTrue('hiding a band notifies', FChangeCount > 0);
end;

{ ── the designable band collection ─────────────────────────────────────────────
  Band metadata that exists only at run time cannot be designed: a form could host the controls
  but not say which one breaks a row, what its caption is, or that it must not be resized. The
  collection is the state; the per-control helpers are a facade over it, and these pin that they
  really are ONE state rather than two that drift. }

procedure TCoolBarControlTest.TestPerControlApiAndCollectionAreOneState;
var CB: TCoolBarAccess; b: TControl;
begin
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := MakeBand(CB, 10, 0, 80, 30);
  CB.SetBandText(b, 'Tools');
  AssertEquals('the facade created a band in the collection', 1, CB.Bands.Count);
  AssertSame('and it wraps that control', b, CB.Bands[0].Control);
  AssertEquals('the collection sees what the facade set', 'Tools', CB.Bands[0].Text);
  { ...and the other way round. }
  CB.Bands[0].Break := True;
  AssertTrue('the facade sees what the collection set', CB.BandBreak(b));
end;

procedure TCoolBarControlTest.TestEditingTheCollectionRelaysAndNotifies;
var CB: TCoolBarAccess; b: TControl;
begin
  { A band edited in the Object Inspector has to behave exactly like one set at run time --
    same relayout, same OnChange -- or a designed layout only comes true after the first
    run-time poke. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := MakeBand(CB, 10, 0, 80, 30);
  CB.SetBandText(b, 'x');
  FChangeCount := 0;
  CB.OnChange := @CountChange;
  CB.Bands[0].Break := True;
  AssertTrue('editing the collection notifies', FChangeCount > 0);
end;

procedure TCoolBarControlTest.TestFreeingAChildDropsItsBand;
var CB: TCoolBarAccess; b: TControl;
begin
  // A band pointing at a freed control is a dangling reference the packer would read.
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := MakeBand(CB, 10, 0, 80, 30);
  CB.SetBandWidth(b, 80);
  AssertEquals('one band', 1, CB.Bands.Count);
  b.Free;
  AssertEquals('the band went with its control', 0, CB.Bands.Count);
end;

procedure TCoolBarControlTest.TestBandDisplayNamePrefersItsCaption;
var CB: TCoolBarAccess; b: TControl;
begin
  { What the collection editor lists. A column of "0, 1, 2" makes a band collection unusable to
    design, which is the entire reason for having one. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := MakeBand(CB, 10, 0, 80, 30);
  b.Name := 'BandPanel';
  CB.SetBandWidth(b, 80);
  AssertEquals('falls back to the control name', 'BandPanel', CB.Bands[0].DisplayName);
  CB.Bands[0].Text := 'Clipboard';
  AssertEquals('but prefers the caption', 'Clipboard', CB.Bands[0].DisplayName);
end;

{ ── vertical ───────────────────────────────────────────────────────────────────
  A vertical rebar is not the horizontal one with a flag: every axis swaps, including which
  drag direction means "move" and which means "resize". Half a swap is the failure mode worth
  guarding, so these check the geometry and the grip side independently. }

procedure TCoolBarMathTest.TestVerticalPackRunsBandsDownAColumn;
var r: TTyRectArray;
begin
  // avail = the HEIGHT the column runs down; band thickness = the column's width.
  r := TyCoolBarPackVertical(SizesV([60, 50]), [], [], 400, 24, 10, 4);
  AssertEquals('band 0 starts below its own gripper', 10, r[0].Top);
  AssertEquals('and is one band thick', 24, r[0].Right - r[0].Left);
  // band 1: 10 + 60 = 70, + spacing 4 = 74, then ITS gripper -> 84
  AssertEquals('band 1 starts below its own gripper too', 84, r[1].Top);
  AssertEquals('both in the same column', r[0].Left, r[1].Left);
end;

procedure TCoolBarMathTest.TestVerticalPackWrapsIntoTheNextColumn;
var r: TTyRectArray;
begin
  r := TyCoolBarPackVertical(SizesV([100, 100]), [], [], 150, 24, 10, 4);
  AssertEquals('band 0 in column 0', 0, r[0].Left);
  AssertTrue('band 1 wrapped into the next column', r[1].Left > r[0].Left);
  AssertEquals('and restarts at the column top, past its gripper', 10, r[1].Top);
end;

procedure TCoolBarMathTest.TestVerticalPackHonoursABreak;
var r: TTyRectArray;
begin
  r := TyCoolBarPackVertical(SizesV([60, 50]), [False, True], [], 400, 24, 10, 4);
  AssertTrue('the broken band moved to a new column', r[1].Left > r[0].Left);
  AssertEquals('and starts at the column top', 10, r[1].Top);
end;

{ ── the seam rule, pure ────────────────────────────────────────────────────────
  A gripper is the boundary between its band and the one before it ON THE SAME ROW. Getting
  "on the same row" wrong is the failure mode worth guarding: a naive AIndex-1 would hand a
  drag the last band of the PREVIOUS row, so dragging the first band of row 2 would silently
  resize something on row 1. }

function RectsAt(const ATops, ALefts: array of Integer): TTyRectArray;
var i: Integer;
begin
  SetLength(Result, Length(ATops));
  for i := 0 to High(ATops) do
    Result[i] := Rect(ALefts[i], ATops[i], ALefts[i] + 40, ATops[i] + 24);
end;

procedure TCoolBarMathTest.TestSeamOwnerIsThePrecedingBandOnTheRow;
var r: TTyRectArray;
begin
  r := RectsAt([0, 0, 0], [10, 60, 110]);
  AssertEquals('band 1''s seam belongs to band 0', 0, TyCoolBandSeamOwner(r, 1));
  AssertEquals('band 2''s seam belongs to band 1', 1, TyCoolBandSeamOwner(r, 2));
end;

procedure TCoolBarMathTest.TestSeamOwnerSkipsBandsOnOtherRows;
var r: TTyRectArray;
begin
  { Rows 0 and 1, with TWO bands on row 0. Band 2 opens row 1, band 3 follows it there.
    Band 3's seam is band 2 -- NOT band 2's predecessor, and certainly not "index minus one"
    reaching back across the row break. }
  r := RectsAt([0, 0, 30, 30], [10, 60, 10, 60]);
  AssertEquals('band 3''s seam is the band before it on ITS row', 2, TyCoolBandSeamOwner(r, 3));
  AssertEquals('band 1''s seam is still band 0', 0, TyCoolBandSeamOwner(r, 1));
end;

procedure TCoolBarMathTest.TestRowLeadingBandHasNoSeam;
var r: TTyRectArray;
begin
  r := RectsAt([0, 0, 30], [10, 60, 10]);
  AssertEquals('band 0 opens the bar -> no seam', -1, TyCoolBandSeamOwner(r, 0));
  AssertEquals('band 2 opens row 1 -> no seam, so its grip is a MOVE', -1,
    TyCoolBandSeamOwner(r, 2));
end;

procedure TCoolBarMathTest.TestSeamOwnerVerticalUsesColumns;
var r: TTyRectArray;
begin
  { Turned on its side every axis swaps: a "row" is a COLUMN, identified by Left. Reading Top
    here would call two bands in different columns neighbours. }
  r := RectsAt([0, 30, 0], [10, 10, 80]);   // col 0: bands 0,1 ; col 1: band 2
  AssertEquals('band 1 follows band 0 down column 0', 0, TyCoolBandSeamOwner(r, 1, True));
  AssertEquals('band 2 opens column 1 -> no seam', -1, TyCoolBandSeamOwner(r, 2, True));
end;

procedure TCoolBarMathTest.TestSeamOwnerOutOfRange;
var r: TTyRectArray;
begin
  r := RectsAt([0], [10]);
  AssertEquals('negative index', -1, TyCoolBandSeamOwner(r, -1));
  AssertEquals('past the end', -1, TyCoolBandSeamOwner(r, 5));
  SetLength(r, 0);
  AssertEquals('empty', -1, TyCoolBandSeamOwner(r, 0));
end;

{ ── where a dragged band lands ─────────────────────────────────────────────────
  Band reordering is a real rebar gesture (Win32's rebar and Lazarus's TCoolBar both do it).
  These pin the drop rule; the control-level tests below pin that the drop is actually applied. }

procedure TCoolBarMathTest.TestDropPastANeighbourReorders;
var r: TTyRectArray;
begin
  // Three bands on one row: [10..50) [60..100) [110..150)
  r := RectsAt([0, 0, 0], [10, 60, 110]);
  // Drag band 0 rightwards past band 1's midpoint (80) -> it takes band 1's slot.
  AssertEquals('band 0 dropped past band 1 lands at 1', 1,
    TyCoolBandDropIndex(r, 0, Point(85, 12)));
  // Past band 2's midpoint (130) -> the end.
  AssertEquals('band 0 dropped past band 2 lands at 2', 2,
    TyCoolBandDropIndex(r, 0, Point(135, 12)));
end;

procedure TCoolBarMathTest.TestDropBeforeANeighbourReorders;
var r: TTyRectArray;
begin
  r := RectsAt([0, 0, 0], [10, 60, 110]);
  // Drag band 2 LEFT to before band 0's midpoint (30) -> it becomes the row's first band.
  AssertEquals('band 2 dropped before band 0 lands at 0', 0,
    TyCoolBandDropIndex(r, 2, Point(15, 12)));
  // Onto band 1's left half -> before band 1, i.e. index 1.
  AssertEquals('band 2 dropped before band 1 lands at 1', 1,
    TyCoolBandDropIndex(r, 2, Point(65, 12)));
end;

procedure TCoolBarMathTest.TestDropOnItselfChangesNothing;
var r: TTyRectArray;
begin
  { The live-commit stability property: once a swap has happened the pointer sits over the
    dragged band itself, and the answer must be "stay put" or the drag would oscillate. }
  r := RectsAt([0, 0, 0], [10, 60, 110]);
  AssertEquals('pointer over the dragged band -> no change', 1,
    TyCoolBandDropIndex(r, 1, Point(80, 12)));
  AssertEquals('out-of-range index is inert', 9, TyCoolBandDropIndex(r, 9, Point(80, 12)));
end;

procedure TCoolBarMathTest.TestDropBelowTheLastRowAsksForANewRow;
var r: TTyRectArray;
begin
  { "Drag 打开/保存 UNDER the search band" -- the reference's cNewRowBelow. Rects are 24 tall,
    so row 0 ends at y=24. }
  r := RectsAt([0, 0], [10, 60]);
  AssertEquals('below every band -> a row of its own', TyCoolDropNewRow,
    TyCoolBandDropIndex(r, 0, Point(30, 40)));
  AssertTrue('and inside the row it is an ordinary reorder, not a new row',
    TyCoolBandDropIndex(r, 0, Point(85, 12)) <> TyCoolDropNewRow);
end;

procedure TCoolBarMathTest.TestDropMirroredFlipsTheMidpointTest;
var r: TTyRectArray;
begin
  { Mirrored, "past" a band means to its LEFT. The same pointer therefore has to give opposite
    answers under the two readings -- a sign nobody notices in review and no static render can
    catch, exactly like the resize delta. }
  r := RectsAt([0, 0, 0], [10, 60, 110]);
  AssertEquals('LTR: right of band 1''s midpoint -> after it', 1,
    TyCoolBandDropIndex(r, 0, Point(85, 12), False));
  AssertEquals('RTL: the same point is BEFORE band 1, so band 0 stays put', 0,
    TyCoolBandDropIndex(r, 0, Point(85, 12), True));
  AssertEquals('RTL: left of band 1''s midpoint -> after it', 1,
    TyCoolBandDropIndex(r, 0, Point(65, 12), True));
end;

procedure TCoolBarMathTest.TestDropOffEveryRowChangesNothing;
var r: TTyRectArray;
begin
  { Above the first row (a negative Y) is on no row at all. It must be inert rather than
    silently landing on row 0 -- and it must not be confused with the below-everything case. }
  r := RectsAt([0, 0], [10, 60]);
  AssertEquals('above every row -> no change', 1, TyCoolBandDropIndex(r, 1, Point(30, -20)));
end;

procedure TCoolBarMathTest.TestDropVerticalTransposesTheAxes;
var r: TTyRectArray;
begin
  { Turned on its side, bands run DOWN a column: the group is picked by X and the order within
    it by Y. Reading the axes the horizontal way round would call two bands in different columns
    neighbours and reorder against the wrong one.

    Column 0 at x 10..50 holds bands 0 and 1 (y 0..24 and 30..54); band 2 opens column 1. }
  SetLength(r, 3);
  r[0] := Rect(10, 0, 50, 24);
  r[1] := Rect(10, 30, 50, 54);
  r[2] := Rect(60, 0, 100, 24);

  // Band 0 dragged DOWN past band 1's midpoint (y = 42) -> it takes band 1's slot.
  AssertEquals('down past the next band in the column reorders', 1,
    TyCoolBandDropIndex(r, 0, Point(30, 45), False, True));
  // Still inside its own band -> no change.
  AssertEquals('over itself, nothing moves', 0,
    TyCoolBandDropIndex(r, 0, Point(30, 10), False, True));
  // Right of every column -> a column of its own.
  AssertEquals('right of the last column -> a new one', TyCoolDropNewRow,
    TyCoolBandDropIndex(r, 0, Point(140, 10), False, True));
  { The SAME geometry read the horizontal way must give a different answer, or the flag is
    doing nothing. x=140 is right of every column (a new column when vertical) but it is level
    with row 0, so read horizontally it is merely a drop past the last band on that row. }
  AssertEquals('read horizontally the same point is an ordinary reorder, not a new group', 2,
    TyCoolBandDropIndex(r, 0, Point(140, 10), False, False));
end;

{ ── making room on a full row ──────────────────────────────────────────────────
  The arithmetic behind "drag a band back up onto a row that is already full". Every number
  below is in the PACKER's frame: a lead (gripper, plus caption when ShowText) before each
  band, one gap between consecutive bands, and the row is full when the total exceeds AAvail.

  Row used by most of these: three bands of 100 with leads of 10 and gaps of 5, so the row
  costs 3*(10+100) + 2*5 = 340. A joiner of 50 with a lead of 10 pushes the total to
  340 + 5 + 60 = 405. Against AAvail = 380 that is a deficit of 25. }

procedure TCoolBarMathTest.TestMakeRoomLeavesAFittingRowAlone;
var w: TTyCoolExtents;
begin
  AssertTrue('a row with room to spare accepts the band',
    TyCoolRowMakeRoom([100, 100, 100], [20, 20, 20], [10, 10, 10], 3, 10, 50, 500, 5, w));
  AssertEquals('and nobody gives up a pixel', 100, w[0]);
  AssertEquals('nobody', 100, w[1]);
  AssertEquals('nobody', 100, w[2]);
end;

procedure TCoolBarMathTest.TestMakeRoomChargesTheLeadsAndTheGaps;
var w: TTyCoolExtents;
begin
  { The exact boundary, which is the whole point of stating the cost formula: 340 for the row,
    +5 for the new gap, +10 lead +50 band = 405. At AAvail 405 it fits untouched; one pixel
    less and someone has to give exactly one pixel. A cost that forgot the leads or the gap
    would put the boundary tens of pixels away and this pair would straddle it. }
  AssertTrue('405 is exactly enough',
    TyCoolRowMakeRoom([100, 100, 100], [20, 20, 20], [10, 10, 10], 3, 10, 50, 405, 5, w));
  AssertEquals('so nothing shrinks', 100, w[2]);
  AssertTrue('404 is one short',
    TyCoolRowMakeRoom([100, 100, 100], [20, 20, 20], [10, 10, 10], 3, 10, 50, 404, 5, w));
  AssertEquals('and exactly one pixel is taken', 99, w[2]);
  AssertEquals('from one band only', 100, w[1]);
end;

procedure TCoolBarMathTest.TestMakeRoomTakesFromTheNearestBandBeforeTheDrop;
var w: TTyCoolExtents;
begin
  { WHO gives. The band immediately BEFORE the insertion point -- the seam the joining band is
    about to own, the same boundary a gripper drag moves. Dropping at the END of the row that
    is band 2; dropping in the middle it is whoever is now on the left. }
  AssertTrue('drop at the end',
    TyCoolRowMakeRoom([100, 100, 100], [20, 20, 20], [10, 10, 10], 3, 10, 50, 380, 5, w));
  AssertEquals('the last band gave the whole 25', 75, w[2]);
  AssertEquals('band 1 untouched', 100, w[1]);
  AssertEquals('band 0 untouched', 100, w[0]);

  AssertTrue('drop between bands 0 and 1',
    TyCoolRowMakeRoom([100, 100, 100], [20, 20, 20], [10, 10, 10], 1, 10, 50, 380, 5, w));
  AssertEquals('now band 0 is the one next door and gives', 75, w[0]);
  AssertEquals('band 1 untouched', 100, w[1]);
  AssertEquals('band 2 untouched', 100, w[2]);
end;

procedure TCoolBarMathTest.TestMakeRoomSpillsBackwardsWhenTheNearestBottomsOut;
var w: TTyCoolExtents;
begin
  { Band 2 can only give 10 before it hits its minimum of 90, so the remaining 15 walks BACK
    along the row rather than stopping there. }
  AssertTrue('the deficit walks back along the row',
    TyCoolRowMakeRoom([100, 100, 100], [20, 20, 90], [10, 10, 10], 3, 10, 50, 380, 5, w));
  AssertEquals('band 2 gave everything it had', 90, w[2]);
  AssertEquals('and band 1 covered the rest', 85, w[1]);
  AssertEquals('band 0 never had to', 100, w[0]);
end;

procedure TCoolBarMathTest.TestMakeRoomFallsBackToTheFarSideOfTheDrop;
var w: TTyCoolExtents;
begin
  { Everything BEFORE the drop is already at its floor, so the bands AFTER it give -- nearest
    first. Refusing here while 80px of slack sat one band further along would be a far worse
    answer than reaching for it. }
  AssertTrue('the far side gives when the near side cannot',
    TyCoolRowMakeRoom([100, 100, 100], [100, 20, 20], [10, 10, 10], 1, 10, 50, 380, 5, w));
  AssertEquals('band 0 is pinned at its minimum', 100, w[0]);
  AssertEquals('so band 1 -- the nearest on the other side -- gave', 75, w[1]);
  AssertEquals('and band 2 was not needed', 100, w[2]);
end;

procedure TCoolBarMathTest.TestMakeRoomNeverGoesBelowAMinimum;
var w: TTyCoolExtents;
begin
  { A deficit far larger than one band's slack must not push it through the floor on the way
    past. Deficit here is 340+5+60-200 = 205; the row's total slack is 3*80 = 240. }
  AssertTrue('a big deficit is still absorbed',
    TyCoolRowMakeRoom([100, 100, 100], [20, 20, 20], [10, 10, 10], 3, 10, 50, 200, 5, w));
  AssertTrue('band 2 stopped at its floor', w[2] >= 20);
  AssertTrue('band 1 stopped at its floor', w[1] >= 20);
  AssertTrue('band 0 stopped at its floor', w[0] >= 20);
  AssertEquals('and between them they gave exactly the deficit', 205,
    300 - (w[0] + w[1] + w[2]));
end;

procedure TCoolBarMathTest.TestMakeRoomRefusesWholeRatherThanHalfApplying;
var w: TTyCoolExtents;
begin
  { The row's total slack is 3*(100-20) = 240; AAvail 164 makes the deficit 405-164 = 241, one
    pixel more than the row can possibly give. The answer is False AND the row is handed back
    untouched: a half-applied squeeze is the worst outcome of the three, because the layout
    moves and the band still does not arrive. }
  AssertFalse('a row with no slack left refuses',
    TyCoolRowMakeRoom([100, 100, 100], [20, 20, 20], [10, 10, 10], 3, 10, 50, 164, 5, w));
  AssertEquals('and nothing was taken from band 0', 100, w[0]);
  AssertEquals('nor band 1', 100, w[1]);
  AssertEquals('nor band 2', 100, w[2]);
end;

procedure TCoolBarControlTest.TestVerticalPutsTheGripAboveTheBand;
var CB: TCoolBarAccess; b: TControl; r: TRect;
begin
  { The grip has to follow the layout round. Left of the band in a horizontal bar, ABOVE it in
    a vertical one -- a grip still drawn to the left would be over the neighbouring column. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  { Placed where the vertical layout would place a first-in-column band: content top + gripW.
    Same correction as TestBandRectIsRowLeftGripper -- the old literals pinned a grip that
    backed onto the frame stroke. }
  b := MakeBand(CB, CB.ContentBox.Left, CB.ContentBox.Top + 10, 24, 60);
  CB.Vertical := True;
  r := CB.BandRect(b);
  AssertFalse('a vertical band is still grippable', IsRectEmpty(r));
  AssertEquals('the grip ends where the band begins', CB.ContentBox.Top + 10, r.Bottom);
  AssertEquals('and starts a grip-height above it, inside the frame',
    CB.ContentBox.Top, r.Top);
  AssertEquals('spanning the band width', b.Left, r.Left);
end;

{ ── the user's report: a band pushed down by OVERFLOW can be dragged back up ────
  Widen band 0 until band 1 no longer fits beside it and band 1 moves to row 1 -- correct. From
  then on it could never be dragged back, because the gesture did exactly one thing (clear
  Break) and band 1's Break had never been set: it came down by overflow. The rejoin takes the
  width from the row instead.

  All of these lay the bands out BY HAND, as every control test in this file does: the LCL
  align engine does not run for a form that was never shown (AutoSizeDelayedHandle short-
  circuits the tree), so a headless test pins the MODEL -- widths, Break, child order. That the
  band actually lands on row 0 on screen was confirmed on a real window (real posted mouse
  messages) during development. }

{ A two-row scene: b0 alone on row 0 and so wide that b1, on row 1, cannot join it.
  Returns the deficit -- exactly how much room b1 needs -- so each test can name the
  arithmetic instead of guessing at it. }
function TCoolBarControlTest.MakeOverflowedPair(CB: TCoolBarAccess;
  out b0, b1: TControl): Integer;
var
  L, T, step, avail, w0: Integer;
begin
  CB.BandHeight := 26;      // pinned so the row pitch does not follow the active theme
  CB.BandSpacing := 3;
  CB.GripperWidth := 10;
  L := CB.ContentBox.Left;
  T := CB.ContentBox.Top;
  step := CB.BandHeight + CB.BandSpacing;
  avail := CB.ContentBox.Right - CB.ContentBox.Left;
  w0 := avail - 40;
  b0 := MakeBand(CB, L + 10, T, w0, 26);            // row 0, after its own gripper
  b1 := MakeBand(CB, L + 10, T + step, 60, 26);     // row 1, pushed there by overflow
  CB.SetBandWidth(b0, w0);
  CB.SetBandWidth(b1, 60);
  { What the row would cost with b1 back on it: lead+w0 for b0, one gap, lead+60 for b1. }
  Result := (10 + w0) + CB.BandSpacing + (10 + 60) - avail;
end;

procedure TCoolBarControlTest.TestDragBackUpSqueezesTheRowAndRejoinsIt;
var
  CB: TCoolBarAccess; b0, b1: TControl; L, T, step, deficit, w0: Integer;
begin
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  CB.SetBounds(0, 0, 300, 120);
  deficit := MakeOverflowedPair(CB, b0, b1);
  w0 := b0.Width;
  L := CB.ContentBox.Left;
  T := CB.ContentBox.Top;
  step := CB.BandHeight + CB.BandSpacing;
  AssertTrue('precondition: the row really is over-full', deficit > 0);
  AssertFalse('precondition: b1 came down by OVERFLOW, so its Break is not set',
    CB.BandBreak(b1));

  { Grab b1's gripper (the strip immediately left of it) and drag straight up onto row 0,
    landing past b0's midpoint -- the half where the drop rule answers "stay put", so the
    reorder cannot be what produces the result. }
  CB.CallMouseDown(L + 5, T + step + 13);
  CB.CallMouseMove(L + 10 + w0 - 5, T + 13);
  CB.CallMouseUp(L + 10 + w0 - 5, T + 13);

  AssertEquals('row 0 gave up exactly the room the band needed', w0 - deficit,
    CB.GetBandWidth(b0));
  AssertEquals('and the hosted control followed', w0 - deficit, b0.Width);
  AssertFalse('the rejoined band does not break its new row', CB.BandBreak(b1));
  AssertEquals('and it stayed the row''s second band', 1, CB.GetControlIndex(b1));
end;

procedure TCoolBarControlTest.TestRejoinIsNotSwallowedByTheReorder;
var
  CB: TCoolBarAccess; b0, b1: TControl; L, T, step, deficit, w0: Integer;
begin
  { The other half of the report: the swap was the ONLY gesture that still responded. Dragging
    up onto a band's LEADING half is exactly where the midpoint rule says "reorder", and the
    old code ran the reorder first -- so the band and its neighbour swapped, the wide band was
    pushed to row 1 in its place, and no width was ever released. A rejoin has to win that
    race; it can still land the band at the head of the row, but it must MAKE ROOM doing it. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  CB.SetBounds(0, 0, 300, 120);
  deficit := MakeOverflowedPair(CB, b0, b1);
  w0 := b0.Width;
  L := CB.ContentBox.Left;
  T := CB.ContentBox.Top;
  step := CB.BandHeight + CB.BandSpacing;

  CB.CallMouseDown(L + 5, T + step + 13);
  CB.CallMouseMove(L + 13, T + 13);            // b0's leading half -- the swap's home turf
  CB.CallMouseUp(L + 13, T + 13);

  AssertEquals('the row was squeezed, so this was a rejoin and not a bare swap',
    w0 - deficit, CB.GetBandWidth(b0));
  AssertEquals('and the band landed at the head of the row it joined', 0,
    CB.GetControlIndex(b1));
end;

procedure TCoolBarControlTest.TestRejoinTakesFromTheBandItLandsNextTo;
var
  CB: TCoolBarAccess; b0, b1, b2, b3: TControl;
  L, T, step, avail, w, deficit: Integer;
begin
  { WHICH band gives, wired through the control rather than only stated in the math. With one
    band on the target row the question cannot even be asked -- and the row in the user's own
    report has one -- so this builds a THREE-band row. The dragged band lands at the end of it,
    so the band immediately before it is the one whose seam moves; taking from the head of the
    row instead would leave b2 untouched and shrink b0. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  CB.SetBounds(0, 0, 500, 120);
  CB.BandHeight := 26;
  CB.BandSpacing := 3;
  CB.GripperWidth := 10;
  L := CB.ContentBox.Left;
  T := CB.ContentBox.Top;
  step := CB.BandHeight + CB.BandSpacing;
  avail := CB.ContentBox.Right - CB.ContentBox.Left;
  { Three bands of w on row 0 cost 3*(10+w) + 2*3; adding b3 costs a gap plus 10+60. Sized so
    the shortfall is small enough for the LAST band alone to cover, which is what makes "who
    gave" readable in the result. }
  w := (avail - 79) div 3;
  b0 := MakeBand(CB, L + 10, T, w, 26);
  b1 := MakeBand(CB, L + 13 + w, T, w, 26);
  b2 := MakeBand(CB, L + 2 * w + 26, T, w, 26);
  b3 := MakeBand(CB, L + 10, T + step, 60, 26);
  CB.SetBandWidth(b0, w);
  CB.SetBandWidth(b1, w);
  CB.SetBandWidth(b2, w);
  CB.SetBandWidth(b3, 60);
  deficit := 3 * (10 + w) + 2 * CB.BandSpacing + CB.BandSpacing + (10 + 60) - avail;
  AssertTrue('precondition: the row is over-full', deficit > 0);
  AssertTrue('precondition: the last band alone can cover it', w - CB.BandMinWidth(b2) >= deficit);

  { Up onto row 0, past the LAST band's midpoint, so the band lands at the end of the row. }
  CB.CallMouseDown(L + 5, T + step + 13);
  CB.CallMouseMove(L + 3 * w + 21, T + 13);
  CB.CallMouseUp(L + 3 * w + 21, T + 13);

  AssertEquals('the band it landed next to is the one that gave', w - deficit,
    CB.GetBandWidth(b2));
  AssertEquals('the band before that was not asked', w, CB.GetBandWidth(b1));
  AssertEquals('nor the head of the row', w, CB.GetBandWidth(b0));
end;

procedure TCoolBarControlTest.TestRejoinHonoursAnExplicitBandMinWidth;
var
  CB: TCoolBarAccess; b0, b1: TControl; L, T, step, deficit, w0: Integer;
begin
  { The floor is BandMinWidth -- the same number the gripper resize is handed -- so a band the
    author pinned cannot be squeezed past it by the other gesture either. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  CB.SetBounds(0, 0, 300, 120);
  deficit := MakeOverflowedPair(CB, b0, b1);
  w0 := b0.Width;
  L := CB.ContentBox.Left;
  T := CB.ContentBox.Top;
  step := CB.BandHeight + CB.BandSpacing;

  { One pixel short of the room needed: the squeeze must refuse rather than dip under. }
  CB.SetBandMinWidth(b0, w0 - deficit + 1);
  CB.CallMouseDown(L + 5, T + step + 13);
  CB.CallMouseMove(L + 10 + w0 - 5, T + 13);
  CB.CallMouseUp(L + 10 + w0 - 5, T + 13);
  AssertEquals('an explicit MinWidth one pixel too high refuses the rejoin', w0,
    CB.GetBandWidth(b0));

  { Exactly enough: the same gesture now succeeds and stops ON the floor. }
  CB.SetBandMinWidth(b0, w0 - deficit);
  CB.CallMouseDown(L + 5, T + step + 13);
  CB.CallMouseMove(L + 10 + w0 - 5, T + 13);
  CB.CallMouseUp(L + 10 + w0 - 5, T + 13);
  AssertEquals('and a floor that leaves exactly enough is squeezed onto, not through',
    w0 - deficit, CB.GetBandWidth(b0));
end;

procedure TCoolBarControlTest.TestRejoinFallsBackToDefaultBandMinWidth;
var
  CB: TCoolBarAccess; b0, b1: TControl; L, T, step, deficit, w0: Integer;
begin
  { A band with no MinWidth of its own falls back to the BAR's DefaultBandMinWidth -- and the
    squeeze has to consult that fallback, not a constant of its own. Proved by moving the
    fallback and watching the same gesture change answer. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  CB.SetBounds(0, 0, 300, 120);
  deficit := MakeOverflowedPair(CB, b0, b1);
  w0 := b0.Width;
  L := CB.ContentBox.Left;
  T := CB.ContentBox.Top;
  step := CB.BandHeight + CB.BandSpacing;
  AssertEquals('precondition: b0 has no MinWidth of its own, so the bar''s applies',
    CB.DefaultBandMinWidth, CB.BandMinWidth(b0));

  CB.DefaultBandMinWidth := w0 - deficit + 1;
  CB.CallMouseDown(L + 5, T + step + 13);
  CB.CallMouseMove(L + 10 + w0 - 5, T + 13);
  CB.CallMouseUp(L + 10 + w0 - 5, T + 13);
  AssertEquals('a bar-level fallback one pixel too high refuses the rejoin', w0,
    CB.GetBandWidth(b0));

  CB.DefaultBandMinWidth := 24;
  CB.CallMouseDown(L + 5, T + step + 13);
  CB.CallMouseMove(L + 10 + w0 - 5, T + 13);
  CB.CallMouseUp(L + 10 + w0 - 5, T + 13);
  AssertEquals('and a roomier fallback lets the same gesture through', w0 - deficit,
    CB.GetBandWidth(b0));
end;

procedure TCoolBarControlTest.TestRejoinThatCannotFitChangesNothingAtAll;
var
  CB: TCoolBarAccess; b0, b1: TControl; L, T, step, w0, idx0, idx1: Integer;
begin
  { THE PINNED CONTRACT for a rejoin that cannot fit even at every minimum: refuse, and leave
    the band where it is. Nothing moves -- no width, no child order, no Break, and no OnChange,
    because a refusal is not a change. "Silently doing nothing" is what the bug was, so what
    makes this different is that it is the ONLY case where nothing happens: every other upward
    drag now moves something. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  CB.SetBounds(0, 0, 300, 120);
  MakeOverflowedPair(CB, b0, b1);
  w0 := b0.Width;
  L := CB.ContentBox.Left;
  T := CB.ContentBox.Top;
  step := CB.BandHeight + CB.BandSpacing;
  CB.SetBandMinWidth(b0, w0);          // nailed: the row has no slack whatsoever
  idx0 := CB.GetControlIndex(b0);
  idx1 := CB.GetControlIndex(b1);
  FChangeCount := 0;
  CB.OnChange := @CountChange;

  CB.CallMouseDown(L + 5, T + step + 13);
  CB.CallMouseMove(L + 10 + w0 - 5, T + 13);
  CB.CallMouseUp(L + 10 + w0 - 5, T + 13);

  AssertEquals('no width moved', w0, CB.GetBandWidth(b0));
  AssertEquals('and none reached the control either', w0, b0.Width);
  AssertEquals('no child order moved', idx0, CB.GetControlIndex(b0));
  AssertEquals('no child order moved', idx1, CB.GetControlIndex(b1));
  AssertFalse('no Break was set on the refused band', CB.BandBreak(b1));
  AssertEquals('and the refusal was not reported as a change', 0, FChangeCount);
end;

procedure TCoolBarControlTest.TestVerticalRejoinSqueezesTheColumnOnTheOtherAxis;
var
  CB: TCoolBarAccess; b0, b1: TControl; L, T, step, avail, h0, deficit: Integer;
begin
  { Turned on its side EVERY axis swaps: a "row" is a column, the run is the y axis, and the
    extent a band gives up is its HEIGHT. Reading widths here would squeeze the column
    THICKNESS -- which the packer takes from the bar's band height and not from the band at
    all -- so the gesture would be inert on exactly the same shape of bug. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  CB.SetBounds(0, 0, 200, 300);
  CB.BandHeight := 26;
  CB.BandSpacing := 3;
  CB.GripperWidth := 10;
  CB.Vertical := True;
  L := CB.ContentBox.Left;
  T := CB.ContentBox.Top;
  step := CB.BandHeight + CB.BandSpacing;
  avail := CB.ContentBox.Bottom - CB.ContentBox.Top;
  h0 := avail - 40;
  b0 := MakeBand(CB, L, T + 10, 26, h0);              // column 0, below its own gripper
  b1 := MakeBand(CB, L + step, T + 10, 26, 60);       // column 1
  CB.SetBandWidth(b0, h0);                            // vertically the assigned extent IS the height
  CB.SetBandWidth(b1, 60);
  deficit := (10 + h0) + CB.BandSpacing + (10 + 60) - avail;
  AssertTrue('precondition: column 0 really is over-full', deficit > 0);
  AssertEquals('an assigned band extent lands on the RUN axis when vertical', h0, b0.Height);

  { Sideways is the MOVE gesture once the bar is vertical -- the axes swap with the layout. }
  CB.CallMouseDown(L + step + 13, T + 5);
  CB.CallMouseMove(L + 13, T + 5);
  CB.CallMouseUp(L + 13, T + 5);

  AssertEquals('the column gave up height, not width', h0 - deficit, b0.Height);
  AssertEquals('and the model agrees', h0 - deficit, CB.GetBandWidth(b0));
end;

{ ── capping a widening drag at the hosted control's own content ─────────────────
  MaxWidth is a number somebody typed and it goes stale the moment the content changes.
  AutoMaxWidth asks the hosted control instead, so a drag stops where the content ends. }

procedure TCoolBarControlTest.TestAutoMaxWidthIsOffByDefault;
var CB: TCoolBarAccess; b: TDeclaredWidthPanel;
begin
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := TDeclaredWidthPanel.Create(CB);
  b.Parent := CB;
  b.SetBounds(0, 0, 80, 26);
  b.Declared := 120;
  CB.SetBandWidth(b, 80);
  AssertFalse('a fresh band does not cap itself', CB.BandAutoMaxWidth(b));
  AssertEquals('so the ceiling is still unbounded even though the content declares one', 0,
    CB.BandMaxWidth(b));
end;

procedure TCoolBarControlTest.TestAutoMaxWidthCapsAtTheDeclaredContentWidth;
var CB: TCoolBarAccess; b: TDeclaredWidthPanel;
begin
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := TDeclaredWidthPanel.Create(CB);
  b.Parent := CB;
  b.SetBounds(0, 0, 80, 26);
  b.Declared := 120;
  CB.SetBandWidth(b, 80);
  CB.SetBandAutoMaxWidth(b, True);
  AssertEquals('the ceiling is the content width the control declares', 120,
    CB.ContentCap(b));
  { The FRAME matters: the cap is the CHILD's width, gripper excluded, because that is what
    TTyCoolBand.Width sets and TyCoolBandResize clamps. Including the lead here -- which is the
    convention Lazarus's TCoolBand.Width uses -- would let the band grow one gripper PAST its
    content, so the footprint is lead + cap and lands exactly on the content's last pixel. }
  AssertEquals('and it is stated lead-exclusive', 120 + CB.LeadPx(b),
    CB.ContentCap(b) + CB.LeadPx(b));
  AssertEquals('which is what the effective ceiling becomes', 120, CB.BandMaxWidth(b));
end;

procedure TCoolBarControlTest.TestAutoMaxWidthStopsAGripperDragAtTheContentEdge;
var CB: TCoolBarAccess; b0: TDeclaredWidthPanel; b1: TControl; L, T: Integer;
begin
  { The gesture, not just the number. b1's gripper is the seam, so dragging it right widens b0
    -- and with the cap on, b0 stops when its content runs out instead of at whatever the
    pointer reached. It STOPS rather than refuses: the band really moved first, which is what
    separates a bounded gesture from the inert one this pass exists to remove. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  CB.SetBounds(0, 0, 500, 120);
  CB.GripperWidth := 10;
  L := CB.ContentBox.Left;
  T := CB.ContentBox.Top;
  b0 := TDeclaredWidthPanel.Create(CB);
  b0.Parent := CB;
  b0.SetBounds(L + 10, T, 80, 26);
  b0.Declared := 120;
  b1 := MakeBand(CB, L + 200, T, 80, 26);
  CB.SetBandWidth(b0, 80);
  CB.SetBandAutoMaxWidth(b0, True);

  CB.CallMouseDown(L + 195, T + 13);
  CB.CallMouseMove(L + 195 + 300, T + 13);      // far past the content
  CB.CallMouseUp(L + 195 + 300, T + 13);

  AssertEquals('the band grew to its content and stopped there', 120, CB.GetBandWidth(b0));
  if b1 = nil then ;
end;

procedure TCoolBarControlTest.TestAutoMaxWidthLeavesAnOpinionlessControlUncapped;
var CB: TCoolBarAccess; b: TControl;
begin
  { A control that declares no preferred width -- an edit, meaningfully any width -- is left
    alone rather than pinned. This caps bands whose content HAS an end; it does not invent one.
    (Measured: TTyEdit answers raw 0, and the non-raw form would answer its own current Width,
    which is the very number the drag is changing.) }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := MakeBand(CB, 0, 0, 80, 26);              // a plain TTyPanel: no preferred width
  CB.SetBandWidth(b, 80);
  CB.SetBandAutoMaxWidth(b, True);
  AssertEquals('no declared content -> no ceiling', 0, CB.ContentCap(b));
  AssertEquals('and therefore no effective ceiling', 0, CB.BandMaxWidth(b));
end;

procedure TCoolBarControlTest.TestAutoMaxWidthTakesWhicheverCeilingBindsFirst;
var CB: TCoolBarAccess; b: TDeclaredWidthPanel;
begin
  { The precedence, stated once in BandMaxWidth: 0 means "no opinion" and drops out; of what
    remains the SMALLEST binds. So the two ceilings never fight -- whichever runs out first
    stops the drag. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := TDeclaredWidthPanel.Create(CB);
  b.Parent := CB;
  b.SetBounds(0, 0, 80, 26);
  b.Declared := 120;
  CB.SetBandWidth(b, 80);
  CB.SetBandAutoMaxWidth(b, True);

  CB.SetBandMaxWidth(b, 0);
  AssertEquals('an unset MaxWidth drops out, leaving the content cap', 120, CB.BandMaxWidth(b));
  CB.SetBandMaxWidth(b, 200);
  AssertEquals('a roomier MaxWidth loses to the content', 120, CB.BandMaxWidth(b));
  CB.SetBandMaxWidth(b, 80);
  AssertEquals('a tighter MaxWidth wins', 80, CB.BandMaxWidth(b));
end;

procedure TCoolBarControlTest.TestAutoMaxWidthHonoursTheControlsOwnConstraint;
var CB: TCoolBarAccess; b: TDeclaredWidthPanel;
begin
  { Constraints.MaxWidth is the hosted control's own statement that it cannot usefully be
    wider, and it composes by the same rule. It lives behind the AutoMaxWidth opt-in so that
    "default OFF changes nothing" stays literally true. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := TDeclaredWidthPanel.Create(CB);
  b.Parent := CB;
  b.SetBounds(0, 0, 80, 26);
  b.Declared := 120;
  b.Constraints.MaxWidth := 90;
  CB.SetBandWidth(b, 80);
  AssertEquals('with the opt-in off the constraint is not the band''s business', 0,
    CB.BandMaxWidth(b));
  CB.SetBandAutoMaxWidth(b, True);
  AssertEquals('and with it on, the tighter of the two declared ceilings binds', 90,
    CB.BandMaxWidth(b));
end;

procedure TCoolBarControlTest.TestABandWithNoControlIsNeverInTheLayout;
var CB: TCoolBarAccess; b: TControl; sep: TTyCoolBand;
begin
  { The caption-only separator band. It hosts nothing, so the content-cap question never
    arises for it: with no child it is never packed, never gripped and never resized. That is
    the decision -- not "the cap is zero" but "the band is not in the layout at all" -- and it
    is why AutoMaxWidth needs no special case for a control-less band. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := MakeBand(CB, 0, 0, 80, 26);
  CB.SetBandWidth(b, 80);                 // gives b a collection item of its own
  sep := CB.Bands.Add;
  sep.Text := 'separator';
  AssertEquals('both bands exist in the designable collection', 2, CB.Bands.Count);
  AssertTrue('and the separator really hosts nothing', sep.Control = nil);
  AssertEquals('but it contributes no child to pack', 1, CB.ControlCount);
  AssertTrue('and it has no gripper strip to grab', IsRectEmpty(CB.BandRect(nil)));
  AssertEquals('asking the ceiling of no control at all is unbounded, not a trap', 0,
    CB.BandMaxWidth(nil));
  AssertEquals('and so is its content cap', 0, CB.ContentCap(nil));
  if b = nil then ;
end;

initialization
  RegisterTest(TCoolBarMathTest);
  RegisterTest(TCoolBarControlTest);
end.
