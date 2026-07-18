unit test.transfer;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.ListBox, tyControls.Transfer,
  tyControls.Button;   // TTyButton — the move-rail arrows are plain buttons

type
  { Pure-geometry tests: TyTransferLayout / TyTransferButtonRect / TyTransferArrowRect take
    only rects and integers, so they run with no window handle and no control instance. }
  TTyTransferGeometryTest = class(TTestCase)
  published
    procedure TestPanesSplitEvenlyAroundRail;
    procedure TestColumnsTileWithNoGap;
    procedure TestOddRemainderGoesToTheRail;
    procedure TestTitleBandTakesTopOfEachColumn;
    procedure TestNoTitlesGivesWholeColumnToThePane;
    procedure TestRailWiderThanBoxCollapsesPanes;
    procedure TestTitleTallerThanBoxCollapsesPanes;
    procedure TestZeroSizeIsEmpty;
    procedure TestButtonsStackCentredInRail;
    procedure TestButtonCentredHorizontallyInRail;
    procedure TestButtonStackTallerThanRailPinsToTop;
    procedure TestButtonPastRailBottomIsEmpty;
    procedure TestButtonIndexOutOfRangeIsEmpty;
    procedure TestArrowCentredInContent;
    procedure TestTwoArrowsSeparatedByGap;
    procedure TestArrowShrinksToFitRatherThanVanish;
  end;

  { The move rules — the actual logic of this control. All take plain arrays / bare
    TStringLists: no control, no handle, no theme. }
  TTyTransferRulesTest = class(TTestCase)
  published
    procedure TestMoveIndicesTakesHighlightedOnly;
    procedure TestMoveIndicesWithNothingHighlightedTakesNothing;
    procedure TestMoveAllIgnoresHighlight;
    procedure TestMoveAllOnEmptyPaneTakesNothing;
    procedure TestNormalizeSortsDedupesAndClips;
    procedure TestNormalizeOnEmptyList;
    procedure TestCanMoveRules;
    procedure TestApplyMoveRemovesAndAppends;
    procedure TestApplyMovePreservesSourceOrder;
    procedure TestApplyMoveUnsortedIndicesGiveTheSameLists;
    procedure TestApplyMoveIgnoresOutOfRange;
    procedure TestApplyMoveAppendsAfterExistingTarget;
    procedure TestApplyMoveOfNothingIsANoOp;
    procedure TestMoveIsRightwardAndIsAll;
  end;

  { Headless control behaviour: typeKey, the data model, the panes' bounds, the rail's
    enable rules, the moves, theme-token wiring and graceful degradation. }
  TTyTransferControlTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FChanged: Integer;   // OnChange fire count
    procedure HandleChange(Sender: TObject);
    { A transfer wired to FCtl, sized, with 'a'..'e' on the left. }
    function NewTransfer(AWidth: Integer = 480; AHeight: Integer = 220): TTyTransfer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestMoveAllArrowsStayReadableUnderTextPadding;
    procedure TestDefaults;
    procedure TestItemsIsTheLeftPanesOwnList;
    procedure TestSelectedIsTheRightPanesOwnList;
    procedure TestPanesFollowTheFrameBounds;
    procedure TestPanesShrinkForTitleBands;
    procedure TestRailWidthMetricRetunesTheSplit;
    procedure TestFramePaddingInsetsTheLayout;
    procedure TestButtonsStackedInRailOrder;
    procedure TestShowMoveAllHidesAndRecentres;
    procedure TestRailDisabledWithNothingHighlighted;
    procedure TestHighlightEnablesTheMoveButton;
    procedure TestAddingItemsEnablesMoveAll;
    procedure TestMoveRightMovesHighlightedRows;
    procedure TestMoveRightClearsOnlyTheSourceHighlight;
    procedure TestMoveAllRightEmptiesTheLeftPane;
    procedure TestMoveLeftGoesBack;
    procedure TestMoveOfNothingIsSilent;
    procedure TestMoveFiresOnChangeOnce;
    procedure TestClickingTheRailMoves;
    procedure TestControllerReachesTheChildren;
    procedure TestFrameRendersThemeBackground;
    procedure TestTitleBandRendersThemeBackground;
    procedure TestTitleInheritsFrameInkWhenUncoloured;
    procedure TestNoTitleBackgroundDrawsNoBand;
    procedure TestUndefinedFrameKeyDrawsNothing;
  end;

implementation

type
  { Reaches the protected paint seam. }
  TTransferAccess = class(TTyTransfer)
  public
    function StyleTypeKey: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  { The move-rail arrows are plain TTyButtons; GetStyleTypeKey is protected, so reach it the
    same way TTransferAccess reaches the host's. }
  TArrowAccess = class(TTyButton)
  public
    function StyleTypeKey: string;
  end;

  TArrowRender = class(TTyButton)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

function TTransferAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

function TArrowAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TArrowRender.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin RenderTo(ACanvas, ARect, APPI); end;

procedure TTransferAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

{ A theme that PINS every metric this suite's geometry depends on. Never rely on the
  built-in fallbacks: a skin (or a later retune of the constants) would silently move the
  numbers these tests assert. }
const
  PinnedMetrics =
    ':root {' +
    '  --transfer-rail-width: 56px;' +
    '  --transfer-button-width: 32px;' +
    '  --transfer-button-height: 26px;' +
    '  --transfer-button-gap: 6px;' +
    '  --transfer-title-height: 26px;' +
    '  --transfer-arrow-size: 12px;' +
    '  --transfer-arrow-gap: 1px;' +
    '}';
  { A frame with NO padding, so a test that asserts raw column arithmetic is not also
    asserting the theme's inset. }
  FlatFrame =
    PinnedMetrics +
    'TyTransfer { background: #FFFFFF; color: #111111; padding: 0px; }';

{ --- TTyTransferGeometryTest ----------------------------------------------------------- }

procedure TTyTransferGeometryTest.TestPanesSplitEvenlyAroundRail;
var
  L: TTyTransferLayout;
begin
  // 400 wide, rail 56 -> each pane (400-56)/2 = 172.
  L := TyTransferLayout(Rect(0, 0, 400, 200), 56, 0);
  AssertEquals('left pane starts at the client left', 0, L.LeftPaneRect.Left);
  AssertEquals('left pane is half the leftover', 172, L.LeftPaneRect.Right);
  AssertEquals('rail starts where the left pane ends', 172, L.RailRect.Left);
  AssertEquals('rail is the themed width', 56, L.RailRect.Right - L.RailRect.Left);
  AssertEquals('right pane starts where the rail ends', 228, L.RightPaneRect.Left);
  AssertEquals('right pane ends at the client right', 400, L.RightPaneRect.Right);
  AssertEquals('both panes are the same width',
    L.LeftPaneRect.Right - L.LeftPaneRect.Left,
    L.RightPaneRect.Right - L.RightPaneRect.Left);
end;

procedure TTyTransferGeometryTest.TestColumnsTileWithNoGap;
var
  L: TTyTransferLayout;
begin
  // The three columns must cover [Left, Right) exactly: no strip of frame between a pane
  // and the rail that belongs to nobody.
  L := TyTransferLayout(Rect(10, 20, 410, 220), 56, 0);
  AssertEquals('left pane starts at the client left', 10, L.LeftPaneRect.Left);
  AssertEquals('rail.Left = leftPane.Right', L.LeftPaneRect.Right, L.RailRect.Left);
  AssertEquals('rightPane.Left = rail.Right', L.RailRect.Right, L.RightPaneRect.Left);
  AssertEquals('right pane ends at the client right', 410, L.RightPaneRect.Right);
  // The vertical span is the whole client with no titles.
  AssertEquals('panes span the client top', 20, L.LeftPaneRect.Top);
  AssertEquals('panes span the client bottom', 220, L.LeftPaneRect.Bottom);
end;

procedure TTyTransferGeometryTest.TestOddRemainderGoesToTheRail;
var
  L: TTyTransferLayout;
begin
  // 401 - 56 = 345, an odd leftover: each pane takes 172 and the rail grows to 57 rather
  // than one pane ending up a pixel wider than the other.
  L := TyTransferLayout(Rect(0, 0, 401, 200), 56, 0);
  AssertEquals('left pane width', 172, L.LeftPaneRect.Right - L.LeftPaneRect.Left);
  AssertEquals('right pane width', 172, L.RightPaneRect.Right - L.RightPaneRect.Left);
  AssertEquals('the rail absorbed the odd pixel', 57, L.RailRect.Right - L.RailRect.Left);
  AssertEquals('and the columns still tile', 401, L.RightPaneRect.Right);
end;

procedure TTyTransferGeometryTest.TestTitleBandTakesTopOfEachColumn;
var
  L: TTyTransferLayout;
begin
  L := TyTransferLayout(Rect(0, 0, 400, 200), 56, 26);
  AssertEquals('left band starts at the client top', 0, L.LeftTitleRect.Top);
  AssertEquals('left band is the themed height', 26, L.LeftTitleRect.Bottom);
  AssertEquals('left band spans the pane column', 172, L.LeftTitleRect.Right);
  AssertEquals('left pane starts under its band', 26, L.LeftPaneRect.Top);
  AssertEquals('left pane still ends at the client bottom', 200, L.LeftPaneRect.Bottom);
  AssertEquals('right band spans the right column', 228, L.RightTitleRect.Left);
  AssertEquals('right pane starts under its band', 26, L.RightPaneRect.Top);
  // The rail is NOT shortened by the bands: the arrows centre on the whole box, which is
  // what puts them level with the middle of the lists.
  AssertEquals('rail spans the full height', 0, L.RailRect.Top);
  AssertEquals('rail spans the full height', 200, L.RailRect.Bottom);
end;

procedure TTyTransferGeometryTest.TestNoTitlesGivesWholeColumnToThePane;
var
  L: TTyTransferLayout;
begin
  L := TyTransferLayout(Rect(0, 0, 400, 200), 56, 0);
  AssertEquals('no band', 0, L.LeftTitleRect.Bottom - L.LeftTitleRect.Top);
  AssertEquals('no band', 0, L.RightTitleRect.Bottom - L.RightTitleRect.Top);
  AssertEquals('pane takes the whole column', 0, L.LeftPaneRect.Top);
  AssertEquals('pane takes the whole column', 200, L.LeftPaneRect.Bottom);
end;

procedure TTyTransferGeometryTest.TestRailWiderThanBoxCollapsesPanes;
var
  L: TTyTransferLayout;
begin
  // The rail is the box's only affordance, so it is served first: a box narrower than its
  // rail keeps the arrows and drops the lists rather than inverting anything.
  L := TyTransferLayout(Rect(0, 0, 40, 200), 56, 0);
  AssertEquals('rail clamped to the client', 0, L.RailRect.Left);
  AssertEquals('rail clamped to the client', 40, L.RailRect.Right);
  AssertEquals('left pane dropped', 0, L.LeftPaneRect.Right - L.LeftPaneRect.Left);
  AssertEquals('right pane dropped', 0, L.RightPaneRect.Right - L.RightPaneRect.Left);
end;

procedure TTyTransferGeometryTest.TestTitleTallerThanBoxCollapsesPanes;
var
  L: TTyTransferLayout;
begin
  // A 20px-tall box cannot hold a 26px band AND a list: keep the band, drop the pane —
  // empty, never inverted.
  L := TyTransferLayout(Rect(0, 0, 400, 20), 56, 26);
  AssertEquals('band clamped to the height', 20, L.LeftTitleRect.Bottom);
  AssertEquals('left pane dropped', 0, L.LeftPaneRect.Bottom - L.LeftPaneRect.Top);
  AssertEquals('right pane dropped', 0, L.RightPaneRect.Bottom - L.RightPaneRect.Top);
end;

procedure TTyTransferGeometryTest.TestZeroSizeIsEmpty;
var
  L: TTyTransferLayout;
begin
  L := TyTransferLayout(Rect(0, 0, 0, 200), 56, 26);
  AssertEquals('zero width: no rail', 0, L.RailRect.Right - L.RailRect.Left);
  AssertEquals('zero width: no pane', 0, L.LeftPaneRect.Right - L.LeftPaneRect.Left);
  L := TyTransferLayout(Rect(0, 0, 400, 0), 56, 26);
  AssertEquals('zero height: no rail', 0, L.RailRect.Bottom - L.RailRect.Top);
  AssertEquals('zero height: no pane', 0, L.LeftPaneRect.Bottom - L.LeftPaneRect.Top);
end;

procedure TTyTransferGeometryTest.TestButtonsStackCentredInRail;
var
  r0, r3: TRect;
  rail: TRect;
begin
  // 4 buttons of 26 with 6 between = 4*26 + 3*6 = 122; rail 200 tall -> top = (200-122)/2 = 39.
  rail := Rect(100, 0, 156, 200);
  r0 := TyTransferButtonRect(rail, 4, 0, 32, 26, 6);
  r3 := TyTransferButtonRect(rail, 4, 3, 32, 26, 6);
  AssertEquals('first button top', 39, r0.Top);
  AssertEquals('first button height', 26, r0.Bottom - r0.Top);
  AssertEquals('last button top = 39 + 3*32', 135, r3.Top);
  AssertEquals('last button bottom', 161, r3.Bottom);
  // The stack is symmetric about the rail's centre: 39 of air above, 200-161 = 39 below.
  AssertEquals('stack is vertically centred', r0.Top, rail.Bottom - r3.Bottom);
end;

procedure TTyTransferGeometryTest.TestButtonCentredHorizontallyInRail;
var
  r: TRect;
begin
  // Rail 56 wide at x=100, button 32 -> 12 of air each side.
  r := TyTransferButtonRect(Rect(100, 0, 156, 200), 4, 0, 32, 26, 6);
  AssertEquals('button left', 112, r.Left);
  AssertEquals('button right', 144, r.Right);
  // A button wider than its rail squeezes to the rail rather than spilling over the panes.
  r := TyTransferButtonRect(Rect(100, 0, 120, 200), 4, 0, 32, 26, 6);
  AssertEquals('squeezed to the rail left', 100, r.Left);
  AssertEquals('squeezed to the rail right', 120, r.Right);
end;

procedure TTyTransferGeometryTest.TestButtonStackTallerThanRailPinsToTop;
var
  r0: TRect;
begin
  // Stack 122 tall in a 60-tall rail: pin to the top so the FIRST arrows survive whole,
  // rather than centring and losing half of them off both ends.
  r0 := TyTransferButtonRect(Rect(100, 10, 156, 70), 4, 0, 32, 26, 6);
  AssertEquals('first button pinned to the rail top', 10, r0.Top);
  AssertEquals('and is still full height', 36, r0.Bottom);
end;

procedure TTyTransferGeometryTest.TestButtonPastRailBottomIsEmpty;
var
  r1, r3: TRect;
begin
  // Rail 10..70. Slot 1 starts at 42 and would end at 68 -> fits. Slot 3 starts at 106,
  // entirely past the rail -> empty, never inverted.
  r1 := TyTransferButtonRect(Rect(100, 10, 156, 70), 4, 1, 32, 26, 6);
  AssertTrue('slot 1 still has a rect', r1.Bottom > r1.Top);
  AssertEquals('and is clipped to the rail bottom', 68, r1.Bottom);
  r3 := TyTransferButtonRect(Rect(100, 10, 156, 70), 4, 3, 32, 26, 6);
  AssertEquals('slot 3 is entirely past the rail', 0, r3.Bottom - r3.Top);
  AssertEquals('and is empty, not inverted', 0, r3.Right - r3.Left);
end;

procedure TTyTransferGeometryTest.TestButtonIndexOutOfRangeIsEmpty;
var
  r: TRect;
begin
  r := TyTransferButtonRect(Rect(100, 0, 156, 200), 4, 4, 32, 26, 6);
  AssertEquals('index = count', 0, r.Right - r.Left);
  r := TyTransferButtonRect(Rect(100, 0, 156, 200), 4, -1, 32, 26, 6);
  AssertEquals('negative index', 0, r.Right - r.Left);
  r := TyTransferButtonRect(Rect(100, 0, 156, 200), 0, 0, 32, 26, 6);
  AssertEquals('no buttons', 0, r.Right - r.Left);
end;

procedure TTyTransferGeometryTest.TestArrowCentredInContent;
var
  r: TRect;
begin
  // One 12px arrow in a 20x14 content rect at (0,0): left = (20-12)/2 = 4, top = (14-12)/2 = 1.
  r := TyTransferArrowRect(Rect(0, 0, 20, 14), 1, 0, 12, 1);
  AssertEquals('arrow left', 4, r.Left);
  AssertEquals('arrow right', 16, r.Right);
  AssertEquals('arrow top', 1, r.Top);
  AssertEquals('arrow is square', 12, r.Bottom - r.Top);
end;

procedure TTyTransferGeometryTest.TestTwoArrowsSeparatedByGap;
var
  r0, r1: TRect;
begin
  // Row = 2*12 + 1 = 25 in a 31-wide content rect -> left = (31-25)/2 = 3.
  r0 := TyTransferArrowRect(Rect(0, 0, 31, 14), 2, 0, 12, 1);
  r1 := TyTransferArrowRect(Rect(0, 0, 31, 14), 2, 1, 12, 1);
  AssertEquals('first arrow left', 3, r0.Left);
  AssertEquals('first arrow right', 15, r0.Right);
  AssertEquals('second arrow starts a gap after the first', 16, r1.Left);
  AssertEquals('second arrow right', 28, r1.Right);
  AssertEquals('both arrows are the same size',
    r0.Right - r0.Left, r1.Right - r1.Left);
  AssertEquals('the row is centred', r0.Left, 31 - r1.Right);
end;

procedure TTyTransferGeometryTest.TestArrowShrinksToFitRatherThanVanish;
var
  r0, r1: TRect;
begin
  // A theme with generous TyButton padding can leave less content than 2*12+1 = 25. The arrow
  // IS the button's content, so it must shrink, never disappear: 15 wide - 1 gap = 14, /2 = 7.
  r0 := TyTransferArrowRect(Rect(0, 0, 15, 14), 2, 0, 12, 1);
  r1 := TyTransferArrowRect(Rect(0, 0, 15, 14), 2, 1, 12, 1);
  AssertEquals('first arrow shrank', 7, r0.Right - r0.Left);
  AssertEquals('second arrow shrank the same', 7, r1.Right - r1.Left);
  AssertEquals('the gap is kept whole', 1, r1.Left - r0.Right);
  // A short content rect shrinks it too (the arrow stays square).
  r0 := TyTransferArrowRect(Rect(0, 0, 40, 5), 1, 0, 12, 1);
  AssertEquals('height caps the arrow', 5, r0.Bottom - r0.Top);
  AssertEquals('and it stays square', 5, r0.Right - r0.Left);
  // Only a rect with truly no room comes back empty.
  r0 := TyTransferArrowRect(Rect(0, 0, 1, 14), 2, 0, 12, 1);
  AssertEquals('nothing fits', 0, r0.Right - r0.Left);
end;

{ --- TTyTransferRulesTest -------------------------------------------------------------- }

procedure TTyTransferRulesTest.TestMoveIndicesTakesHighlightedOnly;
var
  idx: TTyTransferIndices;
begin
  idx := TyTransferMoveIndices([False, True, False, True, False], False);
  AssertEquals('two rows move', 2, Length(idx));
  AssertEquals('ascending', 1, idx[0]);
  AssertEquals('ascending', 3, idx[1]);
end;

procedure TTyTransferRulesTest.TestMoveIndicesWithNothingHighlightedTakesNothing;
var
  idx: TTyTransferIndices;
begin
  // Emphatically NOT "then move everything" — that is the other button.
  idx := TyTransferMoveIndices([False, False, False], False);
  AssertEquals('nothing highlighted, nothing moves', 0, Length(idx));
end;

procedure TTyTransferRulesTest.TestMoveAllIgnoresHighlight;
var
  idx: TTyTransferIndices;
begin
  idx := TyTransferMoveIndices([False, True, False], True);
  AssertEquals('every row moves', 3, Length(idx));
  AssertEquals('in list order', 0, idx[0]);
  AssertEquals('in list order', 1, idx[1]);
  AssertEquals('in list order', 2, idx[2]);
end;

procedure TTyTransferRulesTest.TestMoveAllOnEmptyPaneTakesNothing;
var
  idx: TTyTransferIndices;
  empty: array of Boolean;
begin
  empty := nil;
  idx := TyTransferMoveIndices(empty, True);
  AssertEquals('an empty pane gives nothing, even to "all"', 0, Length(idx));
end;

procedure TTyTransferRulesTest.TestNormalizeSortsDedupesAndClips;
var
  idx: TTyTransferIndices;
begin
  // Click order, a duplicate, one past the end and one negative — all of which a caller can
  // plausibly hand over — must come out as the rows that exist, once each, in list order.
  idx := TyTransferNormalizeIndices([3, 0, 3, 9, -2, 1], 4);
  AssertEquals('deduped and clipped', 3, Length(idx));
  AssertEquals('ascending', 0, idx[0]);
  AssertEquals('ascending', 1, idx[1]);
  AssertEquals('ascending', 3, idx[2]);
end;

procedure TTyTransferRulesTest.TestNormalizeOnEmptyList;
var
  idx: TTyTransferIndices;
begin
  idx := TyTransferNormalizeIndices([0, 1], 0);
  AssertEquals('no rows exist, so no indices survive', 0, Length(idx));
end;

procedure TTyTransferRulesTest.TestCanMoveRules;
begin
  // An empty source can never give, whichever button asks.
  AssertFalse('empty pane, plain move', TyTransferCanMove(0, 0, False));
  AssertFalse('empty pane, move all', TyTransferCanMove(0, 0, True));
  // A plain move needs a highlight; "all" never does.
  AssertFalse('nothing highlighted, plain move', TyTransferCanMove(0, 5, False));
  AssertTrue('something highlighted, plain move', TyTransferCanMove(1, 5, False));
  AssertTrue('non-empty pane, move all', TyTransferCanMove(0, 5, True));
end;

procedure TTyTransferRulesTest.TestApplyMoveRemovesAndAppends;
var
  src, dst: TStringList;
  n: Integer;
begin
  src := TStringList.Create;
  dst := TStringList.Create;
  try
    src.AddStrings(['a', 'b', 'c', 'd']);
    n := TyTransferApplyMove(src, dst, [1, 3]);
    AssertEquals('two rows moved', 2, n);
    AssertEquals('source lost exactly those rows', 'a,c', src.CommaText);
    AssertEquals('target gained them', 'b,d', dst.CommaText);
  finally
    src.Free;
    dst.Free;
  end;
end;

procedure TTyTransferRulesTest.TestApplyMovePreservesSourceOrder;
var
  src, dst: TStringList;
begin
  // The rows arrive in the target in SOURCE order, not in the order the indices were given.
  src := TStringList.Create;
  dst := TStringList.Create;
  try
    src.AddStrings(['a', 'b', 'c', 'd', 'e']);
    TyTransferApplyMove(src, dst, [4, 0, 2]);
    AssertEquals('target in source order', 'a,c,e', dst.CommaText);
    AssertEquals('source keeps its own order', 'b,d', src.CommaText);
  finally
    src.Free;
    dst.Free;
  end;
end;

procedure TTyTransferRulesTest.TestApplyMoveUnsortedIndicesGiveTheSameLists;
var
  srcA, dstA, srcB, dstB: TStringList;
begin
  // The bug every hand-rolled transfer box has: deleting front-to-back shifts every later
  // index and quietly removes the wrong rows. Any permutation must give the same answer.
  srcA := TStringList.Create;
  dstA := TStringList.Create;
  srcB := TStringList.Create;
  dstB := TStringList.Create;
  try
    srcA.AddStrings(['a', 'b', 'c', 'd', 'e']);
    srcB.AddStrings(['a', 'b', 'c', 'd', 'e']);
    TyTransferApplyMove(srcA, dstA, [0, 1, 2]);
    TyTransferApplyMove(srcB, dstB, [2, 0, 1, 2]);   // permuted, with a duplicate
    AssertEquals('same source', srcA.CommaText, srcB.CommaText);
    AssertEquals('same target', dstA.CommaText, dstB.CommaText);
    AssertEquals('and it is the right answer', 'd,e', srcA.CommaText);
    AssertEquals('and it is the right answer', 'a,b,c', dstA.CommaText);
  finally
    srcA.Free;
    dstA.Free;
    srcB.Free;
    dstB.Free;
  end;
end;

procedure TTyTransferRulesTest.TestApplyMoveIgnoresOutOfRange;
var
  src, dst: TStringList;
  n: Integer;
begin
  src := TStringList.Create;
  dst := TStringList.Create;
  try
    src.AddStrings(['a', 'b']);
    n := TyTransferApplyMove(src, dst, [1, 7, -3]);
    AssertEquals('only the real row moved', 1, n);
    AssertEquals('source', 'a', src.CommaText);
    AssertEquals('target', 'b', dst.CommaText);
  finally
    src.Free;
    dst.Free;
  end;
end;

procedure TTyTransferRulesTest.TestApplyMoveAppendsAfterExistingTarget;
var
  src, dst: TStringList;
begin
  src := TStringList.Create;
  dst := TStringList.Create;
  try
    src.AddStrings(['c', 'd']);
    dst.AddStrings(['x', 'y']);
    TyTransferApplyMove(src, dst, [0, 1]);
    AssertEquals('appended, not prepended or merged', 'x,y,c,d', dst.CommaText);
  finally
    src.Free;
    dst.Free;
  end;
end;

procedure TTyTransferRulesTest.TestApplyMoveOfNothingIsANoOp;
var
  src, dst: TStringList;
  n: Integer;
  none: array of Integer;
begin
  src := TStringList.Create;
  dst := TStringList.Create;
  try
    src.AddStrings(['a', 'b']);
    none := nil;
    n := TyTransferApplyMove(src, dst, none);
    AssertEquals('moved nothing', 0, n);
    AssertEquals('source untouched', 'a,b', src.CommaText);
    AssertEquals('target untouched', '', dst.CommaText);
    // A nil list is inert rather than fatal.
    AssertEquals('nil source', 0, TyTransferApplyMove(nil, dst, [0]));
    AssertEquals('nil target', 0, TyTransferApplyMove(src, nil, [0]));
    AssertEquals('and nothing was consumed', 'a,b', src.CommaText);
  finally
    src.Free;
    dst.Free;
  end;
end;

procedure TTyTransferRulesTest.TestMoveIsRightwardAndIsAll;
begin
  AssertTrue('tmMoveRight is rightward', TyTransferMoveIsRightward(tmMoveRight));
  AssertTrue('tmMoveAllRight is rightward', TyTransferMoveIsRightward(tmMoveAllRight));
  AssertFalse('tmMoveLeft is not', TyTransferMoveIsRightward(tmMoveLeft));
  AssertFalse('tmMoveAllLeft is not', TyTransferMoveIsRightward(tmMoveAllLeft));
  AssertFalse('tmMoveRight is not an "all"', TyTransferMoveIsAll(tmMoveRight));
  AssertTrue('tmMoveAllRight is', TyTransferMoveIsAll(tmMoveAllRight));
  AssertFalse('tmMoveLeft is not', TyTransferMoveIsAll(tmMoveLeft));
  AssertTrue('tmMoveAllLeft is', TyTransferMoveIsAll(tmMoveAllLeft));
end;

{ --- TTyTransferControlTest ------------------------------------------------------------ }

procedure TTyTransferControlTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FChanged := 0;
end;

procedure TTyTransferControlTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

procedure TTyTransferControlTest.HandleChange(Sender: TObject);
begin
  Inc(FChanged);
end;

function TTyTransferControlTest.NewTransfer(AWidth: Integer; AHeight: Integer): TTyTransfer;
begin
  Result := TTyTransfer.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.Items.AddStrings(['a', 'b', 'c', 'd', 'e']);
  Result.SetBounds(0, 0, AWidth, AHeight);
end;

procedure TTyTransferControlTest.TestTypeKey;
var
  T: TTransferAccess;
begin
  T := TTransferAccess.Create(FForm);
  T.Parent := FForm;
  try
    AssertEquals('TyTransfer', T.StyleTypeKey);
    // The rail keeps TTyButton's own key on purpose: every theme already dresses it, so the
    // arrows are right in all of them with no key a skin could forget.
    AssertEquals('the rail is styled as an ordinary button', 'TyButton',
      TArrowAccess(T.MoveButton[tmMoveRight]).StyleTypeKey);
  finally
    T.Free;
  end;
end;

procedure TTyTransferControlTest.TestDefaults;
var
  T: TTyTransfer;
begin
  T := TTyTransfer.Create(FForm);
  try
    AssertEquals('source pool starts empty', 0, T.Items.Count);
    AssertEquals('target starts empty', 0, T.Selected.Count);
    AssertEquals('no left title', '', T.LeftTitle);
    AssertEquals('no right title', '', T.RightTitle);
    AssertTrue('titles on by default', T.ShowTitles);
    AssertTrue('the "all" arrows are on by default', T.ShowMoveAll);
    AssertEquals('default width', 480, T.Width);
    AssertEquals('default height', 220, T.Height);
    AssertTrue('both panes exist', (T.LeftPane <> nil) and (T.RightPane <> nil));
    AssertTrue('the panes are multi-select', T.LeftPane.MultiSelect and T.RightPane.MultiSelect);
  finally
    T.Free;
  end;
end;

procedure TTyTransferControlTest.TestItemsIsTheLeftPanesOwnList;
var
  T: TTyTransfer;
begin
  T := NewTransfer;
  try
    // Not a copy: one object, so nothing can drift.
    AssertSame('Items IS the left pane''s list', T.LeftPane.Items, T.Items);
    T.Items.Add('f');
    AssertEquals('an edit through Items reaches the pane', 6, T.LeftPane.Items.Count);
    T.LeftPane.Items.Add('g');
    AssertEquals('and an edit through the pane reaches Items', 7, T.Items.Count);
  finally
    T.Free;
  end;
end;

procedure TTyTransferControlTest.TestSelectedIsTheRightPanesOwnList;
var
  T: TTyTransfer;
  seed: TStringList;
begin
  T := NewTransfer;
  seed := TStringList.Create;
  try
    AssertSame('Selected IS the right pane''s list', T.RightPane.Items, T.Selected);
    // Seeding the target is how a transfer box starts out half-filled.
    seed.AddStrings(['x', 'y']);
    T.Selected := seed;
    AssertEquals('seeded', 'x,y', T.RightPane.Items.CommaText);
  finally
    seed.Free;
    T.Free;
  end;
end;

procedure TTyTransferControlTest.TestPanesFollowTheFrameBounds;
var
  T: TTyTransfer;
begin
  FCtl.LoadThemeCss(FlatFrame + 'TyTransfer { padding: 0px; }');
  T := NewTransfer(400, 200);
  try
    T.ShowTitles := False;
    // 400 wide, rail 56, no padding -> panes of 172 either side.
    AssertEquals('left pane left', 0, T.LeftPane.Left);
    AssertEquals('left pane width', 172, T.LeftPane.Width);
    AssertEquals('right pane left', 228, T.RightPane.Left);
    AssertEquals('right pane width', 172, T.RightPane.Width);
    AssertEquals('panes span the height', 200, T.LeftPane.Height);
    // Resizing takes the panes with it — SetBounds is the seam, so this works handle-less.
    T.SetBounds(0, 0, 300, 100);
    AssertEquals('left pane followed', 122, T.LeftPane.Width);
    AssertEquals('right pane followed', 178, T.RightPane.Left);
    AssertEquals('and the height followed', 100, T.LeftPane.Height);
  finally
    T.Free;
  end;
end;

procedure TTyTransferControlTest.TestPanesShrinkForTitleBands;
var
  T: TTyTransfer;
  noTitleH: Integer;
begin
  FCtl.LoadThemeCss(FlatFrame);
  T := NewTransfer(400, 200);
  try
    T.ShowTitles := False;
    noTitleH := T.LeftPane.Height;
    T.ShowTitles := True;
    AssertEquals('the pane dropped below its band', 26, T.LeftPane.Top);
    AssertEquals('and lost exactly the band''s height', noTitleH - 26, T.LeftPane.Height);
    AssertEquals('the band is where the pane is not', 26, T.LeftTitleRect.Bottom);
    AssertEquals('band spans the pane column', T.LeftPane.Width,
      T.LeftTitleRect.Right - T.LeftTitleRect.Left);
    // The flag is authoritative, not the text: an empty title still reserves its band.
    AssertEquals('', T.LeftTitle);
    AssertTrue('band reserved anyway', T.LeftTitleRect.Bottom > T.LeftTitleRect.Top);
  finally
    T.Free;
  end;
end;

procedure TTyTransferControlTest.TestRailWidthMetricRetunesTheSplit;
var
  T: TTyTransfer;
begin
  // --transfer-rail-width is a skin-tunable metric: a theme that sets it moves the columns,
  // proving the split is not baked into the control.
  FCtl.LoadThemeCss(
    ':root { --transfer-rail-width: 100px; --transfer-title-height: 26px; }' +
    'TyTransfer { background: #FFFFFF; color: #111111; padding: 0px; }');
  T := NewTransfer(400, 200);
  try
    AssertEquals('rail takes the themed width', 100, T.RailRect.Right - T.RailRect.Left);
    AssertEquals('and the panes split what is left', 150, T.LeftPane.Width);
    AssertEquals('right pane re-placed', 250, T.RightPane.Left);
  finally
    T.Free;
  end;
end;

procedure TTyTransferControlTest.TestFramePaddingInsetsTheLayout;
var
  T: TTyTransfer;
begin
  // The frame's themed padding is the outer inset the whole layout sits inside — a value the
  // skin owns, not this control.
  FCtl.LoadThemeCss(
    PinnedMetrics +
    'TyTransfer { background: #FFFFFF; color: #111111; padding: 10px; }');
  T := NewTransfer(400, 200);
  try
    T.ShowTitles := False;
    AssertEquals('left pane starts at the themed padding', 10, T.LeftPane.Left);
    AssertEquals('pane top too', 10, T.LeftPane.Top);
    // Inner width = 400 - 20 = 380; panes = (380-56)/2 = 162.
    AssertEquals('panes split the PADDED width', 162, T.LeftPane.Width);
    AssertEquals('right pane ends at the padded right', 390, T.RightPane.Left + T.RightPane.Width);
    AssertEquals('and the panes clear the bottom padding', 180, T.LeftPane.Height);
  finally
    T.Free;
  end;
end;

procedure TTyTransferControlTest.TestButtonsStackedInRailOrder;
var
  T: TTyTransfer;
begin
  FCtl.LoadThemeCss(FlatFrame);
  T := NewTransfer(400, 200);
  try
    // The classic shuttle order, top to bottom: >, >>, <, <<.
    AssertTrue('> above >>',
      T.MoveButton[tmMoveRight].Top < T.MoveButton[tmMoveAllRight].Top);
    AssertTrue('>> above <',
      T.MoveButton[tmMoveAllRight].Top < T.MoveButton[tmMoveLeft].Top);
    AssertTrue('< above <<',
      T.MoveButton[tmMoveLeft].Top < T.MoveButton[tmMoveAllLeft].Top);
    // All four sit in the rail, at the themed width.
    AssertEquals('button width is the themed metric', 32, T.MoveButton[tmMoveRight].Width);
    AssertEquals('button height is the themed metric', 26, T.MoveButton[tmMoveRight].Height);
    AssertTrue('rail is between the panes',
      (T.RailRect.Left >= T.LeftPane.Left + T.LeftPane.Width) and
      (T.RailRect.Right <= T.RightPane.Left));
    AssertTrue('the buttons are inside the rail',
      (T.MoveButton[tmMoveRight].Left >= T.RailRect.Left) and
      (T.MoveButton[tmMoveRight].Left + T.MoveButton[tmMoveRight].Width <= T.RailRect.Right));
  finally
    T.Free;
  end;
end;

procedure TTyTransferControlTest.TestShowMoveAllHidesAndRecentres;
var
  T: TTyTransfer;
  fourTop, twoTop: Integer;
begin
  FCtl.LoadThemeCss(FlatFrame);
  T := NewTransfer(400, 200);
  try
    fourTop := T.MoveButton[tmMoveRight].Top;
    AssertTrue('the "all" arrows show by default', T.MoveButton[tmMoveAllRight].Visible);
    T.ShowMoveAll := False;
    AssertFalse('>> hidden', T.MoveButton[tmMoveAllRight].Visible);
    AssertFalse('<< hidden', T.MoveButton[tmMoveAllLeft].Visible);
    AssertTrue('> still shows', T.MoveButton[tmMoveRight].Visible);
    AssertTrue('< still shows', T.MoveButton[tmMoveLeft].Visible);
    // Two buttons re-centre: the stack is shorter, so it starts lower than the four-high one.
    twoTop := T.MoveButton[tmMoveRight].Top;
    AssertTrue('the shorter stack re-centred', twoTop > fourTop);
    // And < moved up into the slot >> vacated.
    AssertEquals('< is now the second slot', twoTop + 26 + 6, T.MoveButton[tmMoveLeft].Top);
  finally
    T.Free;
  end;
end;

procedure TTyTransferControlTest.TestRailDisabledWithNothingHighlighted;
var
  T: TTyTransfer;
begin
  FCtl.LoadThemeCss(FlatFrame);
  T := NewTransfer;
  try
    // Left has 5 rows, none highlighted; right is empty.
    AssertFalse('> needs a highlight', T.MoveButton[tmMoveRight].Enabled);
    AssertTrue('>> only needs rows', T.MoveButton[tmMoveAllRight].Enabled);
    AssertFalse('< has no rows to take', T.MoveButton[tmMoveLeft].Enabled);
    AssertFalse('<< has no rows to take', T.MoveButton[tmMoveAllLeft].Enabled);
    // CanMove is the same rule the rail is wired to.
    AssertFalse('CanMove agrees', T.CanMove(tmMoveRight));
    AssertTrue('CanMove agrees', T.CanMove(tmMoveAllRight));
  finally
    T.Free;
  end;
end;

procedure TTyTransferControlTest.TestHighlightEnablesTheMoveButton;
var
  T: TTyTransfer;
begin
  FCtl.LoadThemeCss(FlatFrame);
  T := NewTransfer;
  try
    AssertFalse('> starts disabled', T.MoveButton[tmMoveRight].Enabled);
    T.LeftPane.Selected[2] := True;   // fires the pane's OnChange -> the rail re-derives
    AssertTrue('> lit by the highlight', T.MoveButton[tmMoveRight].Enabled);
    T.LeftPane.ClearSelection;
    AssertFalse('> dark again', T.MoveButton[tmMoveRight].Enabled);
  finally
    T.Free;
  end;
end;

procedure TTyTransferControlTest.TestAddingItemsEnablesMoveAll;
var
  T: TTyTransfer;
begin
  // The "all" arrows depend on the COUNT, which no selection event reports — this is what
  // the chained Items.OnChange hook is for.
  FCtl.LoadThemeCss(FlatFrame);
  T := TTyTransfer.Create(FForm);
  try
    T.Parent := FForm;
    T.Controller := FCtl;
    T.SetBounds(0, 0, 400, 200);
    AssertFalse('an empty box can move nothing', T.MoveButton[tmMoveAllRight].Enabled);
    T.Items.Add('a');
    AssertTrue('>> lit by the new row', T.MoveButton[tmMoveAllRight].Enabled);
    T.Items.Clear;
    AssertFalse('>> dark again when the pool empties', T.MoveButton[tmMoveAllRight].Enabled);
    // Same through the target list.
    T.Selected.Add('z');
    AssertTrue('<< lit by a row on the right', T.MoveButton[tmMoveAllLeft].Enabled);
  finally
    T.Free;
  end;
end;

procedure TTyTransferControlTest.TestMoveRightMovesHighlightedRows;
var
  T: TTyTransfer;
begin
  FCtl.LoadThemeCss(FlatFrame);
  T := NewTransfer;
  try
    T.LeftPane.Selected[1] := True;
    T.LeftPane.Selected[3] := True;
    T.MoveRight;
    AssertEquals('source lost exactly the highlighted rows', 'a,c,e', T.Items.CommaText);
    AssertEquals('target gained them in source order', 'b,d', T.Selected.CommaText);
  finally
    T.Free;
  end;
end;

procedure TTyTransferControlTest.TestMoveRightClearsOnlyTheSourceHighlight;
var
  T: TTyTransfer;
begin
  FCtl.LoadThemeCss(FlatFrame);
  T := NewTransfer;
  try
    T.Selected.AddStrings(['x', 'y']);
    T.RightPane.Selected[0] := True;   // a highlight over there, for the return trip
    T.LeftPane.Selected[0] := True;
    T.MoveRight;
    // The source's bit array is index-keyed, so a surviving bit would land on a row the user
    // never picked. The target's rows did not move (the new ones are appended), so its
    // highlight is still about the same item and must survive.
    AssertEquals('source highlight cleared', 0, T.LeftPane.SelCount);
    AssertEquals('target highlight kept', 1, T.RightPane.SelCount);
    AssertTrue('and it is still on the same item', T.RightPane.Selected[0]);
    AssertEquals('x,y,a', T.Selected.CommaText);
  finally
    T.Free;
  end;
end;

procedure TTyTransferControlTest.TestMoveAllRightEmptiesTheLeftPane;
var
  T: TTyTransfer;
begin
  FCtl.LoadThemeCss(FlatFrame);
  T := NewTransfer;
  try
    T.MoveAllRight;   // no highlight needed
    AssertEquals('source emptied', 0, T.Items.Count);
    AssertEquals('target has the lot, in order', 'a,b,c,d,e', T.Selected.CommaText);
    // And the rail re-derives from the new counts.
    AssertFalse('>> now dark', T.MoveButton[tmMoveAllRight].Enabled);
    AssertTrue('<< now lit', T.MoveButton[tmMoveAllLeft].Enabled);
  finally
    T.Free;
  end;
end;

procedure TTyTransferControlTest.TestMoveLeftGoesBack;
var
  T: TTyTransfer;
begin
  FCtl.LoadThemeCss(FlatFrame);
  T := NewTransfer;
  try
    T.MoveAllRight;
    T.RightPane.Selected[2] := True;   // 'c'
    T.MoveLeft;
    AssertEquals('it came back', 'c', T.Items.CommaText);
    AssertEquals('and left the rest', 'a,b,d,e', T.Selected.CommaText);
    T.MoveAllLeft;
    AssertEquals('everything came back, appended after c', 'c,a,b,d,e', T.Items.CommaText);
    AssertEquals('target emptied', 0, T.Selected.Count);
  finally
    T.Free;
  end;
end;

procedure TTyTransferControlTest.TestMoveOfNothingIsSilent;
var
  T: TTyTransfer;
begin
  FCtl.LoadThemeCss(FlatFrame);
  T := NewTransfer;
  try
    T.OnChange := @HandleChange;
    T.MoveRight;   // nothing highlighted
    AssertEquals('nothing moved', 5, T.Items.Count);
    AssertEquals('a move of nothing is not a change', 0, FChanged);
    T.MoveAllLeft; // the right pane is empty
    AssertEquals('still nothing', 0, T.Selected.Count);
    AssertEquals('still silent', 0, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTyTransferControlTest.TestMoveFiresOnChangeOnce;
var
  T: TTyTransfer;
begin
  // One gesture, one event — even though the move edits two lists and clears a selection,
  // each of which fires the internal hooks.
  FCtl.LoadThemeCss(FlatFrame);
  T := NewTransfer;
  try
    T.OnChange := @HandleChange;
    T.LeftPane.Selected[0] := True;
    T.LeftPane.Selected[1] := True;
    T.MoveRight;
    AssertEquals('exactly one OnChange for the move', 1, FChanged);
    AssertEquals('two rows in one event', 'a,b', T.Selected.CommaText);
    // A host's own edit is not a change: the host caused it and does not need telling.
    T.Items.Add('f');
    AssertEquals('editing Items is silent', 1, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTyTransferControlTest.TestClickingTheRailMoves;
var
  T: TTyTransfer;
begin
  FCtl.LoadThemeCss(FlatFrame);
  T := NewTransfer;
  try
    T.OnChange := @HandleChange;
    T.LeftPane.Selected[4] := True;
    T.MoveButton[tmMoveRight].Click;   // the real button, through its real OnClick
    AssertEquals('the click moved the row', 'e', T.Selected.CommaText);
    AssertEquals('a,b,c,d', T.Items.CommaText);
    AssertEquals('and announced it once', 1, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTyTransferControlTest.TestControllerReachesTheChildren;
var
  T: TTyTransfer;
  other: TTyStyleController;
begin
  other := TTyStyleController.Create(nil);
  T := TTyTransfer.Create(FForm);
  try
    T.Parent := FForm;
    // Assigned AFTER the children exist: they must follow, or a themed transfer would sit
    // around two default-themed listboxes.
    T.Controller := other;
    AssertSame('left pane followed', other, T.LeftPane.Controller);
    AssertSame('right pane followed', other, T.RightPane.Controller);
    AssertSame('the rail followed', other, T.MoveButton[tmMoveAllLeft].Controller);
  finally
    T.Free;
    other.Free;
  end;
end;

{ TestFrameRendersThemeBackground
  Theme: a strongly blue TyTransfer fill. Probe the frame and assert it is the themed
  fill — i.e. the box paints from the token, not from an LCL colour. }
procedure TTyTransferControlTest.TestFrameRendersThemeBackground;
var
  T: TTransferAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  FCtl.LoadThemeCss(
    PinnedMetrics +
    'TyTransfer { background: #3B82F6; color: #FFFFFF; padding: 8px; }');
  Bmp := TBitmap.Create;
  T := TTransferAccess.Create(FForm);
  try
    T.Parent := FForm;
    T.Controller := FCtl;
    T.Font.PixelsPerInch := 96;
    T.ShowTitles := False;
    T.SetBounds(0, 0, 400, 200);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 200);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 400, 200);
    T.RenderTo(Bmp.Canvas, Rect(0, 0, 400, 200), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // In the padding band, clear of where the (windowed) panes would sit.
      Px := Reread.GetPixel(3, 100);
      AssertTrue('frame painted in the themed accent fill',
        (Px.blue > 180) and (Px.red < 120));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
    Bmp.Free;
  end;
end;

{ TestTitleBandRendersThemeBackground
  TyTransferTitle sets its own background: the band must take THAT fill (not the frame's),
  proving the band resolves from its own typeKey. }
procedure TTyTransferControlTest.TestTitleBandRendersThemeBackground;
var
  T: TTransferAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  band: TRect;
begin
  FCtl.LoadThemeCss(
    PinnedMetrics +
    'TyTransfer { background: #FFFFFF; color: #111111; padding: 0px; }' +
    'TyTransferTitle { background: #10B981; color: #FFFFFF; }');
  Bmp := TBitmap.Create;
  T := TTransferAccess.Create(FForm);
  try
    T.Parent := FForm;
    T.Controller := FCtl;
    T.Font.PixelsPerInch := 96;
    T.SetBounds(0, 0, 400, 200);
    band := T.LeftTitleRect;
    AssertTrue('there is a band to probe', band.Bottom > band.Top);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 200);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 400, 200);
    T.RenderTo(Bmp.Canvas, Rect(0, 0, 400, 200), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      Px := Reread.GetPixel((band.Left + band.Right) div 2, (band.Top + band.Bottom) div 2);
      AssertTrue('band painted in the TyTransferTitle fill',
        (Px.green > 120) and (Px.green > Px.red + 30) and (Px.green > Px.blue + 30));
      // Below the band is the frame's own white, not the band's green. NOTE this cannot be
      // said as "green < N": the frame is #FFFFFF, whose GREEN channel is 255 — brighter than
      // the band's own #10B981 (185). Brightness in one channel says nothing here; green
      // DOMINANCE does, which is exactly the predicate the band assertion above uses.
      Px := Reread.GetPixel(2, band.Bottom + 40);
      AssertFalse('the band stops at its own height',
        (Px.green > 120) and (Px.green > Px.red + 30) and (Px.green > Px.blue + 30));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
    Bmp.Free;
  end;
end;

{ TestTitleInheritsFrameInkWhenUncoloured
  Graceful degradation. TyTransferTitle IS declared — but WITHOUT `color`. (Omitting the
  rule entirely would be fake-green: any user rule for a typeKey suppresses the whole
  built-in layer for it, so a key with no rule at all would silently inherit the base once
  the theme pass ships one.) The title must then take the FRAME's ink, never a literal. }
procedure TTyTransferControlTest.TestTitleInheritsFrameInkWhenUncoloured;
var
  T: TTransferAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  band: TRect;
  x, y: Integer;
  found: Boolean;
begin
  // White frame, GREEN frame ink, and a title band that declares a background but NO colour:
  // any green pixel in the band can only have come from the frame's ink.
  FCtl.LoadThemeCss(
    PinnedMetrics +
    'TyTransfer { background: #FFFFFF; color: #10B981; padding: 0px; font-size: 12px; }' +
    'TyTransferTitle { background: #FFFFFF; font-size: 12px; }');
  Bmp := TBitmap.Create;
  T := TTransferAccess.Create(FForm);
  try
    T.Parent := FForm;
    T.Controller := FCtl;
    T.Font.PixelsPerInch := 96;
    T.LeftTitle := 'Available';
    T.SetBounds(0, 0, 400, 200);
    band := T.LeftTitleRect;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 200);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 400, 200);
    T.RenderTo(Bmp.Canvas, Rect(0, 0, 400, 200), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      found := False;
      for y := band.Top to band.Bottom - 1 do
        for x := band.Left to band.Right - 1 do
        begin
          Px := Reread.GetPixel(x, y);
          if (Px.green > 120) and (Px.green > Px.red + 30) and (Px.green > Px.blue + 30) then
          begin
            found := True;
            Break;
          end;
        end;
      AssertTrue('title drawn in the frame''s ink', found);
    finally
      Reread.Free;
    end;
  finally
    T.Free;
    Bmp.Free;
  end;
end;

{ TestNoTitleBackgroundDrawsNoBand
  Graceful degradation, the other half: TyTransferTitle declared WITHOUT `background` ->
  no band tint, but the title text still draws. "No background => no band", not
  "no band => no text". }
procedure TTyTransferControlTest.TestNoTitleBackgroundDrawsNoBand;
var
  T: TTransferAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  band: TRect;
  x, y: Integer;
  foundInk: Boolean;
begin
  FCtl.LoadThemeCss(
    PinnedMetrics +
    'TyTransfer { background: #FFFFFF; color: #111111; padding: 0px; font-size: 12px; }' +
    'TyTransferTitle { color: #10B981; font-size: 12px; }');
  Bmp := TBitmap.Create;
  T := TTransferAccess.Create(FForm);
  try
    T.Parent := FForm;
    T.Controller := FCtl;
    T.Font.PixelsPerInch := 96;
    T.LeftTitle := 'Available';
    T.SetBounds(0, 0, 400, 200);
    band := T.LeftTitleRect;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 200);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 400, 200);
    T.RenderTo(Bmp.Canvas, Rect(0, 0, 400, 200), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // The band's far right is past the title text: with no band fill it must be the
      // frame's white, not a tint invented here.
      Px := Reread.GetPixel(band.Right - 2, (band.Top + band.Bottom) div 2);
      AssertTrue('no band tint: the frame shows through',
        (Px.red > 200) and (Px.green > 200) and (Px.blue > 200));
      // ...and the title still drew, in its own colour.
      foundInk := False;
      for y := band.Top to band.Bottom - 1 do
        for x := band.Left to band.Right - 1 do
        begin
          Px := Reread.GetPixel(x, y);
          if (Px.green > 120) and (Px.green > Px.red + 30) and (Px.green > Px.blue + 30) then
          begin
            foundInk := True;
            Break;
          end;
        end;
      AssertTrue('title still drawn', foundInk);
    finally
      Reread.Free;
    end;
  finally
    T.Free;
    Bmp.Free;
  end;
end;

{ TestUndefinedFrameKeyDrawsNothing
  A theme that declares TyTransfer WITHOUT a background gets no frame and no bands — it
  degrades, it does not invent a look. (The rule is declared, not omitted: see the note on
  TestTitleInheritsFrameInkWhenUncoloured.) }
procedure TTyTransferControlTest.TestUndefinedFrameKeyDrawsNothing;
var
  T: TTransferAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  band: TRect;
begin
  FCtl.LoadThemeCss(
    PinnedMetrics +
    'TyTransfer { border-radius: 4px; }' +
    'TyTransferTitle { background: #10B981; }');
  Bmp := TBitmap.Create;
  T := TTransferAccess.Create(FForm);
  try
    T.Parent := FForm;
    T.Controller := FCtl;
    T.Font.PixelsPerInch := 96;
    T.LeftTitle := 'Available';
    T.SetBounds(0, 0, 400, 200);
    band := T.LeftTitleRect;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 200);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 400, 200);
    T.RenderTo(Bmp.Canvas, Rect(0, 0, 400, 200), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // The band's own green would be unmissable if the paint had carried on regardless.
      Px := Reread.GetPixel((band.Left + band.Right) div 2, (band.Top + band.Bottom) div 2);
      AssertFalse('no frame background => no band either',
        (Px.green > 120) and (Px.green > Px.red + 30) and (Px.green > Px.blue + 30));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
    Bmp.Free;
  end;
end;

{ The move-all buttons draw TWO arrows. They are TTyButtons, so AContentRect is inset by the
  theme's TEXT padding — on a 32px button under a 10px-padded skin (antdesign) that leaves ~12px,
  and two arrows then shrink to ~5px stubs with no heads, rendering as '--' (reported from a real
  run). The fix draws the arrows in the button's OWN area (a small icon margin), not the text
  padding. Guard: measure the ink's horizontal span of a >> button rendered at that padding — two
  readable arrows span most of the button; two collapsed stubs span almost nothing. }
function InkWidthPx(RR: TBGRABitmap): Integer;
var x, y, lo, hi: Integer; px: TBGRAPixel; any: Boolean;
begin
  lo := RR.Width; hi := -1; any := False;
  for y := 0 to RR.Height-1 do
    for x := 0 to RR.Width-1 do
    begin
      px := RR.GetPixel(x, y);
      if px.red < 150 then
      begin
        if x < lo then lo := x;
        if x > hi then hi := x;
        any := True;
      end;
    end;
  if any then Result := hi - lo + 1 else Result := 0;
end;

procedure TTyTransferControlTest.TestMoveAllArrowsStayReadableUnderTextPadding;
var
  T: TTransferAccess; Bmp: TBitmap; RR: TBGRABitmap; b: TRect;
  wAll, wOne: Integer;

  function ButtonInkWidth(m: TTyTransferMove): Integer;
  begin
    b := T.MoveButton[m].BoundsRect;
    Bmp.PixelFormat := pf32bit; Bmp.SetSize(b.Right-b.Left, b.Bottom-b.Top);
    Bmp.Canvas.Brush.Color := clWhite; Bmp.Canvas.FillRect(0,0,Bmp.Width,Bmp.Height);
    TArrowRender(T.MoveButton[m]).Render(Bmp.Canvas, Rect(0,0,Bmp.Width,Bmp.Height), 96);
    RR := TBGRABitmap.Create(Bmp);
    try Result := InkWidthPx(RR); finally RR.Free; end;
  end;

begin
  // A realistic 10px-per-side text padding (antdesign's) on a 32px button — the case that broke.
  FCtl.LoadThemeCss('TyButton { background: #FFFFFF; color: #000000; '
    + 'border-color: #CCCCCC; border-width: 1px; padding: 4px 10px; }');
  Bmp := TBitmap.Create;
  T := TTransferAccess.Create(FForm);
  try
    T.Parent := FForm; T.Controller := FCtl; T.Font.PixelsPerInch := 96;
    T.SetBounds(0, 0, 400, 220);
    wAll := ButtonInkWidth(tmMoveAllRight);
    wOne := ButtonInkWidth(tmMoveRight);
    // Two arrows must span WIDER than one (they are two of them side by side). Under the bug the
    // two stubs spanned ~8px, NARROWER than the single arrow — the exact inversion this catches.
    AssertTrue(Format('the >> button''s two arrows span wider than a single > (all=%d, one=%d)',
      [wAll, wOne]), wAll > wOne);
    // ...and cover most of the 32px button, not a couple of collapsed stubs.
    AssertTrue(Format('the >> arrows are readable, not collapsed stubs (ink width %d of 32)', [wAll]),
      wAll >= 14);   // fix ~17, the old collapsed stubs were ~8
  finally Bmp.Free; T.Free; end;
end;

initialization
  RegisterTest(TTyTransferGeometryTest);
  RegisterTest(TTyTransferRulesTest);
  RegisterTest(TTyTransferControlTest);
end.
