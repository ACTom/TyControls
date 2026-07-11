unit test.listview.layout;
{ Pure headless tests for the layout unit tyControls.ListView.Layout.
  Written from the CONTRACT ONLY (docs/superpowers/plans/2026-07-10-listview-sp1.md,
  section "Task 1 contract"); the implementation was NOT read. Every expected value below
  is derived by hand from the plan's formulas, so a mismatch pins a contract gap, not
  a ratified bug.

  House style follows tests/test.arrow.pas and tests/test.treeview.columns.pas:
  unit + TTestCase descendants + published procedures + RegisterTest in initialization.
  Procedure names are named after the RULE they pin, not the function. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Math, Types, fpcunit, testregistry,
  tyControls.Columns,          // TTySortDirection (sdAscending, sdDescending)
  tyControls.ListView.Layout;

type
  { A tiny text source that owns a string array and exposes a method matching
    TTyItemTextFn, so TyListPrefixMatch can drive its own loop under test. }
  TTextSource = class
  private
    FItems: array of string;
  public
    procedure SetItems(const AValues: array of string);
    function GetText(AIndex: Integer): string;   // signature = TTyItemTextFn
  end;

  { --- TyListCellSize --- }
  TListCellSizeTest = class(TTestCase)
  published
    procedure TestIconCellSizeIsIconPlusLabelBelow;
    procedure TestIconCellNeverNarrowerThanItsIcon;
    procedure TestCellWidthTracksLabelWidthNotIconSize;
    procedure TestSmallIconCellSizeIsIconLeftLabelRight;
    procedure TestListCellSizeMatchesSmallIcon;
    procedure TestTileCellSizeIsTwoLabelLines;
    procedure TestReportCellSizeIsReportWidthByRowH;
  end;

  { --- TyListTracks --- }
  TListTracksTest = class(TTestCase)
  published
    procedure TestRowMajorTracksFromViewportWidth;
    procedure TestColumnMajorTracksFromViewportHeight;
    procedure TestReportAlwaysOneTrack;
    procedure TestViewportSmallerThanCellStillOneTrack;
    procedure TestZeroPitchXReturnsOneTrack;
    procedure TestZeroPitchYReturnsOneTrack;
  end;

  { --- TyListContentExtent --- }
  TListContentExtentTest = class(TTestCase)
  published
    procedure TestReportExtentIsWidthByCountRows;
    procedure TestRowMajorExtentDropsTrailingVGap;
    procedure TestColumnMajorExtentDropsTrailingHGap;
    procedure TestZeroCountExtentIsZero;
  end;

  { --- TyListItemRect --- }
  TListItemRectTest = class(TTestCase)
  published
    procedure TestRowMajorRectRowColFromPos;
    procedure TestRowMajorRectSubtractsScroll;
    procedure TestColumnMajorRectRowColFromPos;
    procedure TestReportRectSpansReportWidthAndAddsHeader;
    procedure TestOutOfRangePosIsEmptyRect;
  end;

  { --- TyListItemAt (the inverse of ItemRect, plus its refusals) --- }
  TListItemAtTest = class(TTestCase)
  published
    procedure TestHorizontalGapReturnsMinusOne;
    procedure TestVerticalGapReturnsMinusOne;
    procedure TestGapStillMinusOneWithScroll;
    procedure TestReportHeaderBandReturnsMinusOne;
    procedure TestReportBeyondReportWidthReturnsMinusOne;
    procedure TestReportBelowLastRowReturnsMinusOne;
    procedure TestTrailingEmptyCellOfLastRowReturnsMinusOne;
    procedure TestOccupiedCellOfLastRowStillHits;
  end;

  { --- ItemRect / ItemAt mutual inverse across ALL FIVE ViewStyles --- }
  TListInverseTest = class(TTestCase)
  private
    procedure CheckInverse(const AName: string; const M: TTyListMetrics;
      ACount, ASx, ASy: Integer);
  published
    procedure TestInverseAllStylesNoScroll;
    procedure TestInverseAllStylesWithScroll;
    procedure TestInverseAllStylesWithVerticalScroll;
    procedure TestInverseAllStylesWithBothScrolls;
  end;

  { --- TyListVisibleRange --- }
  TListVisibleRangeTest = class(TTestCase)
  published
    procedure TestReportRangeClosedInterval;
    procedure TestReportRangeClampsLastToCountMinusOne;
    procedure TestReportRangeWithScroll;
    procedure TestRowMajorRangeSpansWholeRows;
    procedure TestRowMajorLastPartialRowClampsToCountMinusOne;
    procedure TestColumnMajorRangeSpansWholeColumns;
    procedure TestScrolledPastContentReturnsFalse;
    procedure TestZeroCountReturnsFalseAndMinusOne;
  end;

  { --- TyListNavigate --- }
  TListNavigateTest = class(TTestCase)
  published
    procedure TestUpFromFirstRowDoesNotMove;
    procedure TestDownFromLastRowDoesNotMove;
    procedure TestLeftFromFirstItemDoesNotMove;
    procedure TestRightFromLastItemDoesNotMove;
    procedure TestRightMovesByOneInRowMajor;
    procedure TestDownMovesByTracksInRowMajor;
    procedure TestColumnMajorLeftRightMovesByTracks;
    procedure TestHomeAlwaysGoesToZero;
    procedure TestEndAlwaysGoesToLast;
    procedure TestPageDownClampsToLast;
    procedure TestPageUpClampsToZero;
    procedure TestReportLeftRightDoNotMove;
    procedure TestReportUpDownMoveByOne;
    procedure TestZeroCountReturnsMinusOne;
    procedure TestArrowFromNoSelectionLandsOnFirst;
  end;

  { --- TyListRangeBounds --- }
  TListRangeBoundsTest = class(TTestCase)
  published
    procedure TestOrdersAnchorTargetAscending;
    procedure TestOrderIndependentOfArgOrder;
    procedure TestEqualAnchorTargetGivesSinglePoint;
    procedure TestNegativeArgReturnsFalse;
  end;

  { --- TyListMarqueeHits --- }
  TListMarqueeTest = class(TTestCase)
  published
    procedure TestTwoByTwoBlockHitsFourNonContiguous;
    procedure TestEmptyGapBoxHitsNothing;
    procedure TestOnePixelOverlapCounts;
    procedure TestSharedEdgeCounts;
    procedure TestReversedBoxIsNormalized;
    procedure TestHitsWithScroll;
    procedure TestLargeCountReturnsOnlyIntersecting;
  end;

  { --- TyListPrefixMatch --- }
  TListPrefixTest = class(TTestCase)
  private
    FSrc: TTextSource;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestForwardFromStartAfter;
    procedure TestWrapsAroundFromLastToZero;
    procedure TestCaseInsensitive;
    procedure TestWrapsBackToStartItemItself;
    procedure TestStartAfterMinusOneScansFromZero;
    procedure TestEmptyPrefixReturnsMinusOne;
    procedure TestNoMatchReturnsMinusOne;
    procedure TestZeroCountReturnsMinusOne;
  end;

  { --- TyListCompareCells --- }
  TListCompareTest = class(TTestCase)
  private
    procedure AssertNeg(const AMsg: string; AValue: Integer);
    procedure AssertPos(const AMsg: string; AValue: Integer);
    procedure AssertZero(const AMsg: string; AValue: Integer);
  published
    procedure TestTextIsCaseInsensitive;
    procedure TestTextEqualIsZero;
    procedure TestNumberComparesNumericallyNotLexically;
    procedure TestNumberHonoursDecimalPoint;
    procedure TestNumberOnlyOneParsableRanksParsableFirst;
    procedure TestNumberNeitherParsableFallsBackToText;
    procedure TestUnparsableSortsLastInBothDirections;
    procedure TestDateTimeParsesIsoIndependentOfLocale;
    procedure TestDateTimeNeitherParsableFallsBackToText;
    procedure TestDescendingNegatesResult;
    procedure TestDescendingKeepsEqualAtZero;
  end;

  { --- TyReportRowAt --- }
  TListReportRowAtTest = class(TTestCase)
  published
    procedure TestAboveHeaderReturnsMinusOne;
    procedure TestZeroRowHReturnsMinusOne;
    procedure TestRowFromY;
    procedure TestRowWithScroll;
    procedure TestBeyondLastRowReturnsMinusOne;
  end;

  { --- degenerate metrics: no crash, no divide-by-zero --- }
  TListDegenerateTest = class(TTestCase)
  published
    procedure TestZeroCountEveryFunctionIsSafe;
    procedure TestZeroPitchGeometryDoesNotDivideByZero;
  end;

  { --- TyListCheckRect (SP2a: the ONE source of the row checkbox rect) ---
    Written from docs/superpowers/plans/2026-07-10-listview-sp2a.md, section
    "1. Row-leading checkbox / pure functions". Every expected value is derived by hand from that
    contract; the implementation was NOT read. Names pin the RULE, not the function. }
  TListCheckRectTest = class(TTestCase)
  published
    procedure TestReportCheckRectIsLeftAlignedVerticallyCentred;
    procedure TestListSmallIconTileFollowTheSameCentredRule;
    procedure TestIconCheckRectIsTopLeftNotCentred;
    procedure TestZeroCheckPxIsEmptyRect;
    procedure TestNegativeCheckPxIsEmptyRect;
    procedure TestCellTooNarrowIsEmptyRect;
    procedure TestCellTooShortIsEmptyRect;
    procedure TestExactFitIsNotEmptyRect;
    procedure TestOddCentringDifferenceFloors;
  end;

  { ===========================================================================
    SP2b — grouped view. Written from the CONTRACT ONLY
    (docs/superpowers/plans/2026-07-10-listview-sp2b.md, section "Task 1 contract").
    The new group code in tyControls.ListView.Layout.pas was NOT read: every
    expected value is derived by hand from the plan's formulas, so a mismatch pins
    a contract gap, not a ratified bug. Procedure names pin the RULE, not the
    function. The SP1 surface (TyListTracks etc.) may be reused; only the group
    formulas are re-derived.
    =========================================================================== }

  { --- TyListBuildGroupMap : Tops / FirstVisible / heights --- }
  TListGroupMapTest = class(TTestCase)
  published
    procedure TestTopsIsPrefixSumOfGroupHeights;
    procedure TestContentHeightIsLastTop;
    procedure TestTopsIsMonotonicNonDecreasing;
    procedure TestCollapsedGroupIsHeaderOnly;
    procedure TestEmptyCountGroupKeepsFirstVisible;
    procedure TestHeaderlessGroupAddsNoHeaderHeight;
    procedure TestFirstVisibleCountsExpandedItemsOnly;
    procedure TestReportBodyIsCountTimesRowH;
    procedure TestAllCollapsedContentHeightIsGTimesHeader;
  end;

  { --- TyListGroupHeaderRect --- }
  TListGroupHeaderRectTest = class(TTestCase)
  published
    procedure TestHeaderRectSpansViewportAtGroupTop;
    procedure TestHeaderRectSubtractsVerticalScroll;
    procedure TestHeaderlessGroupHasEmptyHeaderRect;
    procedure TestOutOfRangeGroupHasEmptyHeaderRect;
  end;

  { --- TyListGroupItemRect --- }
  TListGroupItemRectTest = class(TTestCase)
  published
    procedure TestFirstItemSitsAtBodyTopLeft;
    procedure TestItemRowColFromIndexInGroup;
    procedure TestItemRectSubtractsScroll;
    procedure TestCollapsedGroupItemRectIsEmpty;
    procedure TestOutOfRangeGroupOrIndexIsEmpty;
  end;

  { --- TyListGroupHitTest : header band, collapsed body, refusals --- }
  TListGroupHitTestTest = class(TTestCase)
  published
    procedure TestHeaderBandPointReturnsIndexMinusOne;
    procedure TestCollapsedGroupHeaderStillHittable;
    procedure TestPointBelowCollapsedHeaderBelongsToNextGroup;
    procedure TestCollapsedGroupItemsAllEmptyRects;
  end;

  { --- TyListGroupItemRect / TyListGroupHitTest mutual inverse --- }
  TListGroupInverseTest = class(TTestCase)
  private
    procedure CheckGroupInverse(const AName: string; const AMap: TTyListGroupMap;
      const M: TTyListMetrics; AHeaderH, ASx, ASy: Integer);
  published
    procedure TestItemRectHitTestInverseNoScroll;
    procedure TestItemRectHitTestInverseWithScroll;
    procedure TestReportItemRectHitTestInverse;
  end;

  { --- TyListGroupOfDisplayPos / TyListGroupDisplayPos mutual inverse --- }
  TListGroupDisplayPosTest = class(TTestCase)
  private
    procedure CheckDisplayInverse(const AName: string; const AMap: TTyListGroupMap);
  published
    procedure TestDisplayPosIsFirstVisiblePlusIndex;
    procedure TestOfDisplayPosAndDisplayPosAreInverse;
    procedure TestCollapsedGroupItemHasNoDisplayPos;
    procedure TestOutOfRangeDisplayPosReturnsFalse;
  end;

  { --- TyListGroupVisibleRange (must window, not scan) --- }
  TListGroupVisibleRangeTest = class(TTestCase)
  published
    procedure TestMiddleScrollReturnsOnlyViewportGroups;
    procedure TestGroupWhoseBottomEqualsViewportTopIsNotVisible;
    procedure TestScrolledPastAllContentReturnsFalse;
    procedure TestTopScrollStartsAtFirstGroup;
    procedure TestEmptyMapReturnsFalseAndMinusOne;
  end;

  { --- TyListGroupNavigate --- }
  TListGroupNavigateTest = class(TTestCase)
  published
    procedure TestDownWithinGroupMovesByTracks;
    procedure TestDownFromAPartialLastRowStaysInTheGroup;
    procedure TestDownFromTheTrueLastRowLeavesThePartialGroup;
    procedure TestDownOutOfGroupLandsOnNextExpandedNonEmptyKeepingColumn;
    procedure TestDownOutOfGroupClampsColumnToRowLastItem;
    procedure TestDownSkipsCollapsedAndEmptyGroups;
    procedure TestUpWithinGroupMovesByTracks;
    procedure TestUpOutOfGroupLandsOnPrevExpandedNonEmptyKeepingColumn;
    procedure TestUpOutOfGroupClampsColumnToRowLastItem;
    procedure TestLastRowOfLastGroupDownDoesNotMove;
    procedure TestFirstRowOfFirstGroupUpDoesNotMove;
    procedure TestLeftRightAreFlatDisplayStep;
    procedure TestHomeAndEndAlwaysMove;
    procedure TestPageDownAndPageUpClamp;
    procedure TestReportUpDownMoveByOneAcrossGroups;
    procedure TestGroupedReportLeftRightMoveByOne;
    procedure TestAllCollapsedNavigationReturnsMinusOne;
  end;

  { --- degenerate: G=0, zero pitch, no crash, no divide-by-zero --- }
  TListGroupDegenerateTest = class(TTestCase)
  published
    procedure TestEmptyGroupsEveryFunctionIsSafe;
    procedure TestZeroPitchGroupGeometryDoesNotDivideByZero;
  end;

implementation

{ ===========================================================================
  Metrics builders — one canonical record per ViewStyle. Each test copies the
  record it needs and overrides only the fields it cares about.

  Derived pitches / tracks (for the reader):
    Icon      : PitchX=70  PitchY=70   Tracks(rowmajor,VW=300)   = (300+10) div 70 = 4
    SmallIcon : PitchX=128 PitchY=24   Tracks(rowmajor,VW=400)   = (400+8)  div 128= 3
    Tile      : PitchX=160 PitchY=50   Tracks(rowmajor,VW=500)   = (500+10) div 160= 3
    List      : PitchX=70  PitchY=25   Tracks(colmajor,VH=200)   = (200+5)  div 25 = 8
    Report    : one track; RowH=24 HeaderH=22 ReportWidth=230
  =========================================================================== }

function BaseMetrics: TTyListMetrics;
begin
  FillChar(Result, SizeOf(Result), 0);
end;

function IconMetrics: TTyListMetrics;
begin
  Result := BaseMetrics;
  Result.ViewStyle := lvsIcon;
  Result.ViewportW := 300;
  Result.ViewportH := 300;
  Result.CellW := 60;
  Result.CellH := 60;
  Result.HGap := 10;
  Result.VGap := 10;
end;

function SmallIconMetrics: TTyListMetrics;
begin
  Result := BaseMetrics;
  Result.ViewStyle := lvsSmallIcon;
  Result.ViewportW := 400;
  Result.ViewportH := 300;
  Result.CellW := 120;
  Result.CellH := 20;
  Result.HGap := 8;
  Result.VGap := 4;
end;

function TileMetrics: TTyListMetrics;
begin
  Result := BaseMetrics;
  Result.ViewStyle := lvsTile;
  Result.ViewportW := 500;
  Result.ViewportH := 300;
  Result.CellW := 150;
  Result.CellH := 40;
  Result.HGap := 10;
  Result.VGap := 10;
end;

function ListMetrics: TTyListMetrics;
begin
  Result := BaseMetrics;
  Result.ViewStyle := lvsList;
  Result.ViewportW := 300;
  Result.ViewportH := 200;
  Result.CellW := 60;
  Result.CellH := 20;
  Result.HGap := 10;
  Result.VGap := 5;
end;

function ReportMetrics: TTyListMetrics;
begin
  Result := BaseMetrics;
  Result.ViewStyle := lvsReport;
  Result.ViewportW := 300;
  Result.ViewportH := 200;
  Result.RowH := 24;
  Result.HeaderH := 22;
  Result.ReportWidth := 230;
end;

{ Metrics that carry the icon-geometry inputs, for TyListCellSize only. }
function CellSizeMetrics(AStyle: TTyListViewStyle): TTyListMetrics;
begin
  Result := BaseMetrics;
  Result.ViewStyle := AStyle;
  Result.IconPx := 32;
  Result.LabelH := 16;
  Result.LabelW := 90;
  Result.Pad := 4;
  Result.ReportWidth := 230;
  Result.RowH := 24;
end;

{ ---- shared assertion helpers ---- }

procedure AssertSize(const AMsg: string; AExpCx, AExpCy: Integer; const AActual: TSize);
begin
  TAssert.AssertEquals(AMsg + ' (cx)', AExpCx, AActual.cx);
  TAssert.AssertEquals(AMsg + ' (cy)', AExpCy, AActual.cy);
end;

procedure AssertRectEquals(const AMsg: string; AL, AT, AR, AB: Integer; const AActual: TRect);
begin
  TAssert.AssertEquals(AMsg + ' (Left)',   AL, AActual.Left);
  TAssert.AssertEquals(AMsg + ' (Top)',    AT, AActual.Top);
  TAssert.AssertEquals(AMsg + ' (Right)',  AR, AActual.Right);
  TAssert.AssertEquals(AMsg + ' (Bottom)', AB, AActual.Bottom);
end;

{ ===========================================================================
  TTextSource
  =========================================================================== }

procedure TTextSource.SetItems(const AValues: array of string);
var
  i: Integer;
begin
  SetLength(FItems, Length(AValues));
  for i := 0 to High(AValues) do
    FItems[i] := AValues[i];
end;

function TTextSource.GetText(AIndex: Integer): string;
begin
  Result := FItems[AIndex];
end;

{ ===========================================================================
  TyListCellSize
  =========================================================================== }

procedure TListCellSizeTest.TestIconCellSizeIsIconPlusLabelBelow;
{ lvsIcon: (Max(IconPx + 4*Pad, LabelW), IconPx + LabelH + 3*Pad)
         = (Max(32+16, 90), 32+16+12) = (90, 60) -- the LABEL decides the width here. }
begin
  AssertSize('icon cell', 90, 60, TyListCellSize(CellSizeMetrics(lvsIcon)));
end;

procedure TListCellSizeTest.TestIconCellNeverNarrowerThanItsIcon;
{ ... but a very narrow label must not clip the icon: the floor is IconPx + 4*Pad = 48. }
var
  m: TTyListMetrics;
begin
  m := CellSizeMetrics(lvsIcon);
  m.LabelW := 10;
  AssertSize('icon cell floors at the icon', 48, 60, TyListCellSize(m));
end;

procedure TListCellSizeTest.TestSmallIconCellSizeIsIconLeftLabelRight;
{ lvsSmallIcon: (IconPx + 3*Pad + LabelW, Max(IconPx,LabelH) + 2*Pad)
              = (32+12+90, 32+8) = (134, 40) }
begin
  AssertSize('smallicon cell', 134, 40, TyListCellSize(CellSizeMetrics(lvsSmallIcon)));
end;

procedure TListCellSizeTest.TestListCellSizeMatchesSmallIcon;
{ lvsList shares the smallicon formula: (134, 40) }
begin
  AssertSize('list cell', 134, 40, TyListCellSize(CellSizeMetrics(lvsList)));
end;

procedure TListCellSizeTest.TestTileCellSizeIsTwoLabelLines;
{ lvsTile: (IconPx + 3*Pad + LabelW, Max(IconPx, 2*LabelH) + 2*Pad)
         = (32+12+90, Max(32,32)+8) = (134, 40) }
begin
  AssertSize('tile cell', 134, 40, TyListCellSize(CellSizeMetrics(lvsTile)));
end;

procedure TListCellSizeTest.TestCellWidthTracksLabelWidthNotIconSize;
{ The regression this whole batch is about: growing the label must grow the cell, and
  growing the icon must NOT be the only thing that can. }
var
  m: TTyListMetrics;
  narrow, wide: TSize;
begin
  m := CellSizeMetrics(lvsSmallIcon);
  m.LabelW := 60;   narrow := TyListCellSize(m);
  m.LabelW := 160;  wide   := TyListCellSize(m);
  AssertEquals('a wider label widens the cell by exactly that much',
    100, wide.cx - narrow.cx);
  AssertEquals('and leaves the height alone', narrow.cy, wide.cy);
end;

procedure TListCellSizeTest.TestReportCellSizeIsReportWidthByRowH;
{ lvsReport: (ReportWidth, RowH) = (230, 24) }
begin
  AssertSize('report cell', 230, 24, TyListCellSize(CellSizeMetrics(lvsReport)));
end;

{ ===========================================================================
  TyListTracks
  =========================================================================== }

procedure TListTracksTest.TestRowMajorTracksFromViewportWidth;
{ row-major: Max(1, (ViewportW + HGap) div PitchX) = (300+10) div 70 = 4 }
begin
  AssertEquals('icon tracks', 4, TyListTracks(IconMetrics));
end;

procedure TListTracksTest.TestColumnMajorTracksFromViewportHeight;
{ column-major: Max(1, ((ViewportH - HeaderH) + VGap) div PitchY) = (200+5) div 25 = 8 }
begin
  AssertEquals('list tracks', 8, TyListTracks(ListMetrics));
end;

procedure TListTracksTest.TestReportAlwaysOneTrack;
begin
  AssertEquals('report tracks', 1, TyListTracks(ReportMetrics));
end;

procedure TListTracksTest.TestViewportSmallerThanCellStillOneTrack;
{ Viewport narrower than one cell: Tracks must still be 1. }
var
  M: TTyListMetrics;
begin
  M := IconMetrics;
  M.ViewportW := 10;   { (10+10) div 70 = 0 -> Max(1, 0) = 1 }
  AssertEquals('narrow viewport tracks', 1, TyListTracks(M));
end;

procedure TListTracksTest.TestZeroPitchXReturnsOneTrack;
{ PitchX <= 0 (CellW=HGap=0) -> 1, no divide-by-zero. }
var
  M: TTyListMetrics;
begin
  M := IconMetrics;
  M.CellW := 0;
  M.HGap := 0;
  AssertEquals('zero pitchX tracks', 1, TyListTracks(M));
end;

procedure TListTracksTest.TestZeroPitchYReturnsOneTrack;
{ Column-major with PitchY <= 0 -> 1. }
var
  M: TTyListMetrics;
begin
  M := ListMetrics;
  M.CellH := 0;
  M.VGap := 0;
  AssertEquals('zero pitchY tracks', 1, TyListTracks(M));
end;

{ ===========================================================================
  TyListContentExtent
  =========================================================================== }

procedure TListContentExtentTest.TestReportExtentIsWidthByCountRows;
{ lvsReport: (ReportWidth, ACount * RowH) = (230, 10*24) = (230, 240) }
begin
  AssertSize('report extent', 230, 240, TyListContentExtent(10, ReportMetrics));
end;

procedure TListContentExtentTest.TestRowMajorExtentDropsTrailingVGap;
{ row-major: Rows = Ceil(10/4) = 3; (ViewportW, Max(0, Rows*PitchY - VGap))
  = (300, 3*70 - 10) = (300, 200) }
begin
  AssertSize('icon extent', 300, 200, TyListContentExtent(10, IconMetrics));
end;

procedure TListContentExtentTest.TestColumnMajorExtentDropsTrailingHGap;
{ column-major: Cols = Ceil(20/8) = 3; (Max(0, Cols*PitchX - HGap), ViewportH - HeaderH)
  = (3*70 - 10, 200) = (200, 200) }
begin
  AssertSize('list extent', 200, 200, TyListContentExtent(20, ListMetrics));
end;

procedure TListContentExtentTest.TestZeroCountExtentIsZero;
begin
  AssertSize('icon count0',   0, 0, TyListContentExtent(0, IconMetrics));
  AssertSize('list count0',   0, 0, TyListContentExtent(0, ListMetrics));
  AssertSize('report count0', 0, 0, TyListContentExtent(0, ReportMetrics));
end;

{ ===========================================================================
  TyListItemRect
  =========================================================================== }

procedure TListItemRectTest.TestRowMajorRectRowColFromPos;
{ pos=5, Tracks=4: col=5 mod 4=1, row=5 div 4=1.
  Left=1*70=70, Top=1*70=70, size 60x60 -> (70,70,130,130) }
begin
  AssertRectEquals('icon rect pos5', 70, 70, 130, 130,
    TyListItemRect(5, 10, IconMetrics, 0, 0));
end;

procedure TListItemRectTest.TestRowMajorRectSubtractsScroll;
{ pos=5 with scroll (20,30): (70-20, 70-30, 130-20, 130-30) = (50,40,110,100) }
begin
  AssertRectEquals('icon rect pos5 scrolled', 50, 40, 110, 100,
    TyListItemRect(5, 10, IconMetrics, 20, 30));
end;

procedure TListItemRectTest.TestColumnMajorRectRowColFromPos;
{ pos=10, Tracks=8: row=10 mod 8=2, col=10 div 8=1.
  Left=1*70=70, Top=2*25=50, size 60x20 -> (70,50,130,70) }
begin
  AssertRectEquals('list rect pos10', 70, 50, 130, 70,
    TyListItemRect(10, 20, ListMetrics, 0, 0));
end;

procedure TListItemRectTest.TestReportRectSpansReportWidthAndAddsHeader;
{ pos=3: Left=-0, Top=HeaderH+3*RowH=22+72=94, Right=Left+230, Bottom=Top+24
  -> (0, 94, 230, 118) }
begin
  AssertRectEquals('report rect pos3', 0, 94, 230, 118,
    TyListItemRect(3, 20, ReportMetrics, 0, 0));
end;

procedure TListItemRectTest.TestOutOfRangePosIsEmptyRect;
begin
  AssertRectEquals('pos -1',    0, 0, 0, 0, TyListItemRect(-1, 10, IconMetrics, 0, 0));
  AssertRectEquals('pos =count', 0, 0, 0, 0, TyListItemRect(10, 10, IconMetrics, 0, 0));
end;

{ ===========================================================================
  TyListItemAt — gaps, header, trailing empties
  =========================================================================== }

procedure TListItemAtTest.TestHorizontalGapReturnsMinusOne;
{ Icon HGap=10: cell col0 X=[0,60], col1 X=[70,130]; x=65 sits in the gap. }
begin
  AssertEquals('gap x=65', -1, TyListItemAt(Point(65, 5), 10, IconMetrics, 0, 0));
end;

procedure TListItemAtTest.TestVerticalGapReturnsMinusOne;
{ Icon VGap=10: row0 Y=[0,60], row1 Y=[70,130]; y=65 sits in the gap. }
begin
  AssertEquals('gap y=65', -1, TyListItemAt(Point(5, 65), 10, IconMetrics, 0, 0));
end;

procedure TListItemAtTest.TestGapStillMinusOneWithScroll;
{ With scrollX=37 the col0/col1 gap moves to X in (23,33); x=28 is in it. }
begin
  AssertEquals('gap x=28 scrolled', -1, TyListItemAt(Point(28, 5), 10, IconMetrics, 37, 0));
end;

procedure TListItemAtTest.TestReportHeaderBandReturnsMinusOne;
{ Report HeaderH=22: a point with Y in [0,22) is the header, not an item. }
begin
  AssertEquals('report header y=10', -1, TyListItemAt(Point(100, 10), 20, ReportMetrics, 0, 0));
end;

procedure TListItemAtTest.TestReportBeyondReportWidthReturnsMinusOne;
{ Report rows only span ReportWidth=230; X=250 is past the row. }
begin
  AssertEquals('report x=250', -1, TyListItemAt(Point(250, 30), 20, ReportMetrics, 0, 0));
end;

procedure TListItemAtTest.TestReportBelowLastRowReturnsMinusOne;
{ Report Count=5: rows occupy Y in [22,142); Y=150 is below the last row -> pos>=Count. }
begin
  AssertEquals('report below last', -1, TyListItemAt(Point(100, 150), 5, ReportMetrics, 0, 0));
end;

procedure TListItemAtTest.TestTrailingEmptyCellOfLastRowReturnsMinusOne;
{ Icon Tracks=4, Count=6: last row has pos4,5 only; row1 col2 (would be pos6) is empty.
  Cell region row1 col2: X=[140,200], Y=[70,130]; a point inside maps to pos 6 >= Count. }
begin
  AssertEquals('empty trailing cell', -1, TyListItemAt(Point(141, 71), 6, IconMetrics, 0, 0));
end;

procedure TListItemAtTest.TestOccupiedCellOfLastRowStillHits;
{ Same grid: row1 col1 is pos5 (< Count 6); a point inside it hits 5. }
begin
  AssertEquals('occupied trailing cell', 5, TyListItemAt(Point(71, 71), 6, IconMetrics, 0, 0));
end;

{ ===========================================================================
  ItemRect / ItemAt mutual inverse across all five ViewStyles
  =========================================================================== }

procedure TListInverseTest.CheckInverse(const AName: string; const M: TTyListMetrics;
  ACount, ASx, ASy: Integer);
var
  pos, got, probed: Integer;
  r: TRect;
  pt: TPoint;
begin
  probed := 0;
  for pos := 0 to ACount - 1 do
  begin
    r := TyListItemRect(pos, ACount, M, ASx, ASy);
    { A point one pixel inside the top-left corner is unambiguously inside this cell and
      never in a gap -- but under a vertical scroll that corner can sit ABOVE the item
      area (above HeaderH in report mode, above 0 elsewhere), where nothing is hittable
      by design: a report row scrolled under the header must not be clickable. Clamp the
      probe down into the item area, and skip cells that are entirely outside it. }
    pt := Point(r.Left + 1, r.Top + 1);
    if pt.Y < M.HeaderH then
      pt.Y := M.HeaderH;
    if pt.Y >= r.Bottom then
      Continue;   { cell lies wholly above the item area }
    Inc(probed);
    got := TyListItemAt(pt, ACount, M, ASx, ASy);
    AssertEquals(Format('%s: ItemAt(ItemRect(%d) probe)', [AName, pos]), pos, got);
  end;
  { Without this the Continue above could skip every position and the test would pass
    vacuously -- a scroll offset large enough to push all cells out of the item area
    would assert nothing at all. }
  AssertTrue(Format('%s: at least one position was actually probed', [AName]), probed > 0);
end;

procedure TListInverseTest.TestInverseAllStylesNoScroll;
begin
  CheckInverse('icon',      IconMetrics,      10, 0, 0);
  CheckInverse('smallicon', SmallIconMetrics, 7,  0, 0);
  CheckInverse('list',      ListMetrics,      20, 0, 0);
  CheckInverse('tile',      TileMetrics,      7,  0, 0);
  CheckInverse('report',    ReportMetrics,    8,  0, 0);
end;

procedure TListInverseTest.TestInverseAllStylesWithScroll;
{ A horizontal scroll of 37 translates every cell left (X may go negative, which
  has no lower-bound refusal) while leaving Y at or below its unscrolled position
  above the header — so the round-trip holds for EVERY pos, in every style,
  independent of how the header band is treated for negative Y. }
begin
  CheckInverse('icon+sx',      IconMetrics,      10, 37, 0);
  CheckInverse('smallicon+sx', SmallIconMetrics, 7,  37, 0);
  CheckInverse('list+sx',      ListMetrics,      20, 37, 0);
  CheckInverse('tile+sx',      TileMetrics,      7,  37, 0);
  CheckInverse('report+sx',    ReportMetrics,    8,  37, 0);
end;

procedure TListInverseTest.TestInverseAllStylesWithVerticalScroll;
{ The case the horizontal-only test above cannot see. A vertical scroll pushes the first
  cell's client Top NEGATIVE, so ItemRect(0).TopLeft+(1,1) has Y < 0. ItemAt must still
  answer 0: a negative Y is above the client, not "inside the header band", and only the
  band [0, HeaderH) is refused. An `if APt.Y < HeaderH then Exit(-1)` guard passes every
  other test in this file and fails exactly here. }
{ Each offset is just over ONE row pitch: enough to push the first row out of the item area
  (the case being tested) while leaving later rows inside it, so CheckInverse's sentinel
  still sees probes. Pitches differ per style -- smallicon's is 24px, so scrolling it by
  icon's 95px would push all 3 of its rows out and the test would assert nothing. }
begin
  CheckInverse('icon+sy',      IconMetrics,      10, 0, 95);   { pitch 70 }
  CheckInverse('smallicon+sy', SmallIconMetrics, 7,  0, 30);   { pitch 24 }
  CheckInverse('list+sy',      ListMetrics,      20, 0, 30);   { pitch 25 }
  CheckInverse('tile+sy',      TileMetrics,      7,  0, 60);   { pitch 50 }
  { Report: 95 puts row 3's Top at HeaderH + 72 - 95 = -1, i.e. straddling the header --
    exactly the case where the header must win over the row beneath it. }
  CheckInverse('report+sy',    ReportMetrics,    8,  0, 95);
end;

procedure TListInverseTest.TestInverseAllStylesWithBothScrolls;
begin
  CheckInverse('icon+both',      IconMetrics,      10, 37, 95);
  CheckInverse('smallicon+both', SmallIconMetrics, 7,  37, 30);
  CheckInverse('list+both',      ListMetrics,      20, 37, 30);
  CheckInverse('tile+both',      TileMetrics,      7,  37, 60);
  CheckInverse('report+both',    ReportMetrics,    8,  37, 95);
end;

{ ===========================================================================
  TyListVisibleRange
  =========================================================================== }

procedure TListVisibleRangeTest.TestReportRangeClosedInterval;
{ Report vh=ViewportH-HeaderH=178, ScrollY=0:
  AFirst=0 div 24=0; ALast=(0+178-1) div 24 = 177 div 24 = 7 }
var
  f, l: Integer;
begin
  AssertTrue('report range visible', TyListVisibleRange(20, ReportMetrics, 0, 0, f, l));
  AssertEquals('report first', 0, f);
  AssertEquals('report last', 7, l);
end;

procedure TListVisibleRangeTest.TestReportRangeClampsLastToCountMinusOne;
{ Same window but Count=5: ALast=7 clamps to 4. }
var
  f, l: Integer;
begin
  AssertTrue('report range', TyListVisibleRange(5, ReportMetrics, 0, 0, f, l));
  AssertEquals('report first', 0, f);
  AssertEquals('report last clamped', 4, l);
end;

procedure TListVisibleRangeTest.TestReportRangeWithScroll;
{ ScrollY=48: AFirst=48 div 24=2; ALast=(48+177) div 24 = 225 div 24 = 9 }
var
  f, l: Integer;
begin
  AssertTrue('report range scrolled', TyListVisibleRange(20, ReportMetrics, 0, 48, f, l));
  AssertEquals('report first', 2, f);
  AssertEquals('report last', 9, l);
end;

procedure TListVisibleRangeTest.TestRowMajorRangeSpansWholeRows;
{ Icon Tracks=4, PitchY=70, ViewportH=300, ScrollY=0:
  firstRow=0; lastRow=(0+300-1) div 70 = 299 div 70 = 4;
  AFirst=0*4=0; ALast=(4+1)*4-1=19; clamp to Count-1 with a large Count. }
var
  f, l: Integer;
begin
  AssertTrue('icon range', TyListVisibleRange(40, IconMetrics, 0, 0, f, l));
  AssertEquals('icon first', 0, f);
  AssertEquals('icon last', 19, l);
end;

procedure TListVisibleRangeTest.TestRowMajorLastPartialRowClampsToCountMinusOne;
{ Same window, Count=10: ALast=19 clamps to 9 (the last partial row). }
var
  f, l: Integer;
begin
  AssertTrue('icon range', TyListVisibleRange(10, IconMetrics, 0, 0, f, l));
  AssertEquals('icon first', 0, f);
  AssertEquals('icon last clamped', 9, l);
end;

procedure TListVisibleRangeTest.TestColumnMajorRangeSpansWholeColumns;
{ List Tracks=8, PitchX=70, ViewportW=300, ScrollX=70:
  firstCol=70 div 70=1; lastCol=(70+299) div 70 = 369 div 70 = 5;
  AFirst=1*8=8; ALast=(5+1)*8-1=47; clamp to Count-1=19. }
var
  f, l: Integer;
begin
  AssertTrue('list range scrolled', TyListVisibleRange(20, ListMetrics, 70, 0, f, l));
  AssertEquals('list first', 8, f);
  AssertEquals('list last clamped', 19, l);
end;

procedure TListVisibleRangeTest.TestScrolledPastContentReturnsFalse;
{ Icon Count=4 (only row0) but ScrollY=1000: firstRow=14 -> AFirst=56 (only clamped >=0);
  ALast clamps to 3. AFirst(56) > ALast(3) -> False. }
var
  f, l: Integer;
begin
  AssertFalse('scrolled past -> False', TyListVisibleRange(4, IconMetrics, 0, 1000, f, l));
  { One rule for EVERY False path, not just Count=0: a caller that ignores the result
    must not find stale indices (56, 3) to loop over. }
  AssertEquals('scrolled past first=-1', -1, f);
  AssertEquals('scrolled past last=-1', -1, l);
end;

procedure TListVisibleRangeTest.TestZeroCountReturnsFalseAndMinusOne;
var
  f, l: Integer;
begin
  AssertFalse('count0 -> False', TyListVisibleRange(0, IconMetrics, 0, 0, f, l));
  AssertEquals('count0 first=-1', -1, f);
  AssertEquals('count0 last=-1', -1, l);
end;

{ ===========================================================================
  TyListNavigate  (Icon: Tracks=4; row-major steps: L/R=+-1, U/D=+-Tracks)
  =========================================================================== }

procedure TListNavigateTest.TestUpFromFirstRowDoesNotMove;
{ current=1 (row0); Up = -Tracks = -4 -> -3 out of bounds -> stays 1. }
begin
  AssertEquals('up from first row', 1, TyListNavigate(1, 10, lnUp, IconMetrics));
end;

procedure TListNavigateTest.TestDownFromLastRowDoesNotMove;
{ current=9 (Count-1); Down = +4 -> 13 >= 10 out -> stays 9. }
begin
  AssertEquals('down from last row', 9, TyListNavigate(9, 10, lnDown, IconMetrics));
end;

procedure TListNavigateTest.TestLeftFromFirstItemDoesNotMove;
{ current=0; Left = -1 -> -1 out -> stays 0. }
begin
  AssertEquals('left from first', 0, TyListNavigate(0, 10, lnLeft, IconMetrics));
end;

procedure TListNavigateTest.TestRightFromLastItemDoesNotMove;
{ current=9 (Count-1); Right = +1 -> 10 out -> stays 9. }
begin
  AssertEquals('right from last', 9, TyListNavigate(9, 10, lnRight, IconMetrics));
end;

procedure TListNavigateTest.TestRightMovesByOneInRowMajor;
begin
  AssertEquals('right moves +1', 1, TyListNavigate(0, 10, lnRight, IconMetrics));
end;

procedure TListNavigateTest.TestDownMovesByTracksInRowMajor;
{ current=1; Down=+Tracks=+4 -> 5. }
begin
  AssertEquals('down moves +Tracks', 5, TyListNavigate(1, 10, lnDown, IconMetrics));
end;

procedure TListNavigateTest.TestColumnMajorLeftRightMovesByTracks;
{ List column-major, Tracks=8: Left/Right = +-Tracks; Up/Down = +-1. }
begin
  AssertEquals('list right +Tracks', 8, TyListNavigate(0, 20, lnRight, ListMetrics));
  AssertEquals('list down +1',       1, TyListNavigate(0, 20, lnDown,  ListMetrics));
  AssertEquals('list left from col0', 0, TyListNavigate(0, 20, lnLeft, ListMetrics));
  AssertEquals('list up from row0',   0, TyListNavigate(0, 20, lnUp,   ListMetrics));
end;

procedure TListNavigateTest.TestHomeAlwaysGoesToZero;
begin
  AssertEquals('home', 0, TyListNavigate(5, 10, lnHome, IconMetrics));
end;

procedure TListNavigateTest.TestEndAlwaysGoesToLast;
begin
  AssertEquals('end', 9, TyListNavigate(5, 10, lnEnd, IconMetrics));
end;

procedure TListNavigateTest.TestPageDownClampsToLast;
{ Icon page step = Max(1,(300-0) div 70) * 4 = 4*4 = 16; current=8 -> 24 clamps to 9. }
begin
  AssertEquals('pagedown clamps', 9, TyListNavigate(8, 10, lnPageDown, IconMetrics));
end;

procedure TListNavigateTest.TestPageUpClampsToZero;
{ page step 16; current=1 -> -15 clamps to 0. }
begin
  AssertEquals('pageup clamps', 0, TyListNavigate(1, 10, lnPageUp, IconMetrics));
end;

procedure TListNavigateTest.TestReportLeftRightDoNotMove;
{ Report: Left/Right never move. }
begin
  AssertEquals('report left', 3, TyListNavigate(3, 20, lnLeft, ReportMetrics));
  AssertEquals('report right', 3, TyListNavigate(3, 20, lnRight, ReportMetrics));
end;

procedure TListNavigateTest.TestReportUpDownMoveByOne;
begin
  AssertEquals('report up',   4, TyListNavigate(5, 20, lnUp, ReportMetrics));
  AssertEquals('report down', 6, TyListNavigate(5, 20, lnDown, ReportMetrics));
end;

procedure TListNavigateTest.TestZeroCountReturnsMinusOne;
begin
  AssertEquals('nav count0', -1, TyListNavigate(0, 0, lnDown, IconMetrics));
end;

procedure TListNavigateTest.TestArrowFromNoSelectionLandsOnFirst;
{ current=-1: ANY arrow or page key lands on the first item. lnRight would also land on 0
  under a "just add the step to -1" reading, so it proves nothing on its own -- lnUp and
  lnLeft are the ones that separate the readings (adding the step would bounce them back
  below zero, i.e. "no move" from nothing). }
begin
  AssertEquals('right from no-selection', 0, TyListNavigate(-1, 10, lnRight, IconMetrics));
  AssertEquals('left from no-selection',  0, TyListNavigate(-1, 10, lnLeft,  IconMetrics));
  AssertEquals('up from no-selection',    0, TyListNavigate(-1, 10, lnUp,    IconMetrics));
  AssertEquals('down from no-selection',  0, TyListNavigate(-1, 10, lnDown,  IconMetrics));
  AssertEquals('pagedown from no-selection', 0, TyListNavigate(-1, 10, lnPageDown, IconMetrics));
end;

{ ===========================================================================
  TyListRangeBounds
  =========================================================================== }

procedure TListRangeBoundsTest.TestOrdersAnchorTargetAscending;
var
  lo, hi: Integer;
begin
  AssertTrue('range ok', TyListRangeBounds(5, 2, lo, hi));
  AssertEquals('lo', 2, lo);
  AssertEquals('hi', 5, hi);
end;

procedure TListRangeBoundsTest.TestOrderIndependentOfArgOrder;
var
  lo, hi: Integer;
begin
  AssertTrue('range ok', TyListRangeBounds(2, 5, lo, hi));
  AssertEquals('lo', 2, lo);
  AssertEquals('hi', 5, hi);
end;

procedure TListRangeBoundsTest.TestEqualAnchorTargetGivesSinglePoint;
var
  lo, hi: Integer;
begin
  AssertTrue('range ok', TyListRangeBounds(4, 4, lo, hi));
  AssertEquals('lo', 4, lo);
  AssertEquals('hi', 4, hi);
end;

procedure TListRangeBoundsTest.TestNegativeArgReturnsFalse;
var
  lo, hi: Integer;
begin
  AssertFalse('neg anchor -> False', TyListRangeBounds(-1, 3, lo, hi));
  AssertEquals('lo=-1', -1, lo);
  AssertEquals('hi=-1', -1, hi);
end;

{ ===========================================================================
  TyListMarqueeHits (Icon: Tracks=4, PitchX=PitchY=70, cells 60x60)
  =========================================================================== }

procedure TListMarqueeTest.TestTwoByTwoBlockHitsFourNonContiguous;
{ Box (10,10)-(120,120) overlaps cells (col0,row0)=0, (col1,row0)=1,
  (col0,row1)=4, (col1,row1)=5 with positive area, and nothing else.
  0,1,4,5 is deliberately NON-contiguous (2 and 3 are skipped). }
var
  hits: TTyIntArray;
begin
  hits := TyListMarqueeHits(Rect(10, 10, 120, 120), 8, IconMetrics, 0, 0);
  AssertEquals('4 hits', 4, Length(hits));
  AssertEquals('hit[0]', 0, hits[0]);
  AssertEquals('hit[1]', 1, hits[1]);
  AssertEquals('hit[2]', 4, hits[2]);
  AssertEquals('hit[3]', 5, hits[3]);
end;

procedure TListMarqueeTest.TestEmptyGapBoxHitsNothing;
{ Box (61,61)-(69,69) sits entirely inside the cross gap: strictly right of
  col0/row0 (edges at 60) and strictly left of col1/row1 (edges at 70). }
var
  hits: TTyIntArray;
begin
  hits := TyListMarqueeHits(Rect(61, 61, 69, 69), 8, IconMetrics, 0, 0);
  AssertEquals('no hits', 0, Length(hits));
end;

procedure TListMarqueeTest.TestOnePixelOverlapCounts;
{ Box (59,10)-(65,50) overlaps only cell0 by X=[59,60] (positive area). }
var
  hits: TTyIntArray;
begin
  hits := TyListMarqueeHits(Rect(59, 10, 65, 50), 8, IconMetrics, 0, 0);
  AssertEquals('one hit', 1, Length(hits));
  AssertEquals('hit[0]', 0, hits[0]);
end;

procedure TListMarqueeTest.TestSharedEdgeCounts;
{ Marquee intersection is INCLUSIVE: "touching an edge counts". Cell0 spans X=[0,60].
  A box whose Left is exactly 60 shares an edge with it and zero area -- it must still
  hit cell0. Swapping the inclusive test for Types.IntersectRect (which needs positive
  area) passes every other marquee test here and fails only this one. }
var
  hits: TTyIntArray;
begin
  hits := TyListMarqueeHits(Rect(60, 10, 65, 50), 8, IconMetrics, 0, 0);
  AssertTrue('shared edge hits cell0', Length(hits) >= 1);
  AssertEquals('hit[0]', 0, hits[0]);
end;

procedure TListMarqueeTest.TestReversedBoxIsNormalized;
{ Same block as the 2x2 test but given bottom-right -> top-left. }
var
  hits: TTyIntArray;
begin
  hits := TyListMarqueeHits(Rect(120, 120, 10, 10), 8, IconMetrics, 0, 0);
  AssertEquals('4 hits', 4, Length(hits));
  AssertEquals('hit[0]', 0, hits[0]);
  AssertEquals('hit[3]', 5, hits[3]);
end;

procedure TListMarqueeTest.TestHitsWithScroll;
{ ScrollY=70 lifts the grid one pitch: logical row r sits at client Y=(r-1)*70.
  Box (10,80)-(120,190): X hits col0,col1; Y hits row2 (Y=[70,130]) and row3 (Y=[140,200]).
  pos = row*Tracks+col -> 8, 9, 12, 13. }
var
  hits: TTyIntArray;
begin
  hits := TyListMarqueeHits(Rect(10, 80, 120, 190), 16, IconMetrics, 0, 70);
  AssertEquals('4 hits', 4, Length(hits));
  AssertEquals('hit[0]', 8, hits[0]);
  AssertEquals('hit[1]', 9, hits[1]);
  AssertEquals('hit[2]', 12, hits[2]);
  AssertEquals('hit[3]', 13, hits[3]);
end;

procedure TListMarqueeTest.TestLargeCountReturnsOnlyIntersecting;
{ A tiny box against a huge count must return only the few intersecting cells
  (the contract forbids iterating ACount). }
var
  hits: TTyIntArray;
begin
  hits := TyListMarqueeHits(Rect(10, 10, 120, 120), 100000, IconMetrics, 0, 0);
  AssertEquals('4 hits from huge count', 4, Length(hits));
  AssertEquals('hit[0]', 0, hits[0]);
  AssertEquals('hit[3]', 5, hits[3]);
end;

{ ===========================================================================
  TyListPrefixMatch
  =========================================================================== }

procedure TListPrefixTest.SetUp;
begin
  FSrc := TTextSource.Create;
end;

procedure TListPrefixTest.TearDown;
begin
  FSrc.Free;
end;

procedure TListPrefixTest.TestForwardFromStartAfter;
{ Items 0..3; start after 0, prefix 'a': search begins at 1, hits 'apricot' at 1
  (NOT 0, even though 0 also matches — the search starts AFTER the anchor). }
begin
  FSrc.SetItems(['apple', 'apricot', 'banana', 'cherry']);
  AssertEquals('forward from 0', 1, TyListPrefixMatch(@FSrc.GetText, 4, 0, 'a'));
end;

procedure TListPrefixTest.TestWrapsAroundFromLastToZero;
{ StartAfter=3 (last): search begins at index 4 -> wraps to 0 -> 'apple'. }
begin
  FSrc.SetItems(['apple', 'banana', 'cherry', 'date']);
  AssertEquals('wrap last->0', 0, TyListPrefixMatch(@FSrc.GetText, 4, 3, 'a'));
end;

procedure TListPrefixTest.TestCaseInsensitive;
{ Prefix 'AP' matches 'apricot' at index 3 (searching after 0). }
begin
  FSrc.SetItems(['apple', 'banana', 'cherry', 'apricot']);
  AssertEquals('case-insensitive', 3, TyListPrefixMatch(@FSrc.GetText, 4, 0, 'AP'));
end;

procedure TListPrefixTest.TestWrapsBackToStartItemItself;
{ Only the anchor item matches; after a full wrap the anchor is the last item
  checked, so it is found. }
begin
  FSrc.SetItems(['xapple', 'b', 'c']);
  AssertEquals('wrap back to anchor', 0, TyListPrefixMatch(@FSrc.GetText, 3, 0, 'x'));
end;

procedure TListPrefixTest.TestStartAfterMinusOneScansFromZero;
begin
  FSrc.SetItems(['apple', 'banana', 'cherry']);
  AssertEquals('start -1 -> from 0', 1, TyListPrefixMatch(@FSrc.GetText, 3, -1, 'b'));
end;

procedure TListPrefixTest.TestEmptyPrefixReturnsMinusOne;
begin
  FSrc.SetItems(['apple', 'banana']);
  AssertEquals('empty prefix', -1, TyListPrefixMatch(@FSrc.GetText, 2, -1, ''));
end;

procedure TListPrefixTest.TestNoMatchReturnsMinusOne;
begin
  FSrc.SetItems(['apple', 'banana', 'cherry']);
  AssertEquals('no match', -1, TyListPrefixMatch(@FSrc.GetText, 3, -1, 'z'));
end;

procedure TListPrefixTest.TestZeroCountReturnsMinusOne;
begin
  FSrc.SetItems(['apple']);
  AssertEquals('count 0', -1, TyListPrefixMatch(@FSrc.GetText, 0, -1, 'a'));
end;

{ ===========================================================================
  TyListCompareCells
  =========================================================================== }

procedure TListCompareTest.AssertNeg(const AMsg: string; AValue: Integer);
begin
  AssertTrue(AMsg + Format(' (expected <0, got %d)', [AValue]), AValue < 0);
end;

procedure TListCompareTest.AssertPos(const AMsg: string; AValue: Integer);
begin
  AssertTrue(AMsg + Format(' (expected >0, got %d)', [AValue]), AValue > 0);
end;

procedure TListCompareTest.AssertZero(const AMsg: string; AValue: Integer);
begin
  AssertEquals(AMsg, 0, AValue);
end;

procedure TListCompareTest.TestTextIsCaseInsensitive;
{ 'apple' vs 'BANANA' -> a<b regardless of case -> <0. }
begin
  AssertNeg('text a<B', TyListCompareCells('apple', 'BANANA', lskText, sdAscending));
end;

procedure TListCompareTest.TestTextEqualIsZero;
begin
  AssertZero('Foo=foo', TyListCompareCells('Foo', 'foo', lskText, sdAscending));
end;

procedure TListCompareTest.TestNumberComparesNumericallyNotLexically;
{ '10' vs '9': numeric 10>9 -> >0. (Lexical text compare would give '1'<'9' -> <0,
  so this discriminates numeric from text.) }
begin
  AssertPos('10>9 numeric', TyListCompareCells('10', '9', lskNumber, sdAscending));
end;

procedure TListCompareTest.TestNumberHonoursDecimalPoint;
{ '3.5' vs '10': numeric 3.5<10 -> <0. (Text would compare '3'>'1' -> >0.) }
begin
  AssertNeg('3.5<10 numeric', TyListCompareCells('3.5', '10', lskNumber, sdAscending));
end;

procedure TListCompareTest.TestNumberOnlyOneParsableRanksParsableFirst;
{ '5' parses, 'abc' does not -> the parsable one sorts first. }
begin
  AssertNeg('parsable A first', TyListCompareCells('5', 'abc', lskNumber, sdAscending));
  AssertPos('parsable B first', TyListCompareCells('abc', '5', lskNumber, sdAscending));
end;

procedure TListCompareTest.TestNumberNeitherParsableFallsBackToText;
{ Neither 'abc' nor 'abd' parses -> degrade to case-insensitive text -> 'abc'<'abd'. }
begin
  AssertNeg('both unparsable -> text', TyListCompareCells('abc', 'abd', lskNumber, sdAscending));
end;

procedure TListCompareTest.TestUnparsableSortsLastInBothDirections;
{ Direction flips the comparison between two COMPARABLE values; it must not flip where the
  unparseable ones land. Sorting a Size column descending should put the biggest files on
  top, not a pile of blanks. (SQL's NULLS LAST is orthogonal to ASC/DESC for the same
  reason.) Negating the whole result -- the obvious implementation -- fails only here. }
begin
  AssertNeg('asc: parsable first', TyListCompareCells('5', '', lskNumber, sdAscending));
  AssertNeg('desc: parsable STILL first', TyListCompareCells('5', '', lskNumber, sdDescending));
  AssertPos('asc: unparsable last', TyListCompareCells('', '5', lskNumber, sdAscending));
  AssertPos('desc: unparsable STILL last', TyListCompareCells('', '5', lskNumber, sdDescending));

  AssertNeg('date asc: parsable first',
    TyListCompareCells('2026-07-10', 'n/a', lskDateTime, sdAscending));
  AssertNeg('date desc: parsable STILL first',
    TyListCompareCells('2026-07-10', 'n/a', lskDateTime, sdDescending));

  // Between two comparable values the direction DOES flip.
  AssertNeg('asc 5<9', TyListCompareCells('5', '9', lskNumber, sdAscending));
  AssertPos('desc 5>9', TyListCompareCells('5', '9', lskNumber, sdDescending));
end;

procedure TListCompareTest.TestDateTimeParsesIsoIndependentOfLocale;
{ lskDateTime pins ISO-8601-ish parsing so a sort does not depend on the runner's locale. }
begin
  AssertNeg('iso date asc',
    TyListCompareCells('2026-07-10', '2026-12-01', lskDateTime, sdAscending));
  AssertPos('iso date desc',
    TyListCompareCells('2026-07-10', '2026-12-01', lskDateTime, sdDescending));
  AssertNeg('iso datetime with time',
    TyListCompareCells('2026-07-10 08:30', '2026-07-10 17:15', lskDateTime, sdAscending));
end;

procedure TListCompareTest.TestDateTimeNeitherParsableFallsBackToText;
{ Neither 'qux' nor 'quy' parses as a date/time -> degrade to text -> 'qux'<'quy'.
  (A positively-parsing date is intentionally avoided: the contract only pins the
  DecimalSeparator of the FormatSettings, not the date format — see notes.) }
begin
  AssertNeg('both unparsable dt -> text',
    TyListCompareCells('qux', 'quy', lskDateTime, sdAscending));
end;

procedure TListCompareTest.TestDescendingNegatesResult;
{ '10' vs '9' ascending is >0; descending must negate it to <0. }
begin
  AssertNeg('descending negates', TyListCompareCells('10', '9', lskNumber, sdDescending));
end;

procedure TListCompareTest.TestDescendingKeepsEqualAtZero;
{ Equal compares to 0; negating 0 is still 0. }
begin
  AssertZero('descending of equal', TyListCompareCells('7', '7', lskNumber, sdDescending));
end;

{ ===========================================================================
  TyReportRowAt
  =========================================================================== }

procedure TListReportRowAtTest.TestAboveHeaderReturnsMinusOne;
{ AY(10) < HeaderH(22) -> -1 }
begin
  AssertEquals('above header', -1, TyReportRowAt(10, 0, 22, 24, 10));
end;

procedure TListReportRowAtTest.TestZeroRowHReturnsMinusOne;
begin
  AssertEquals('rowH<=0', -1, TyReportRowAt(50, 0, 22, 0, 10));
end;

procedure TListReportRowAtTest.TestRowFromY;
{ row = (AY - HeaderH + ScrollY) div RowH; AY=46 -> (46-22+0) div 24 = 1 }
begin
  AssertEquals('row 0', 0, TyReportRowAt(22, 0, 22, 24, 10));
  AssertEquals('row 1', 1, TyReportRowAt(46, 0, 22, 24, 10));
end;

procedure TListReportRowAtTest.TestRowWithScroll;
{ AY=22, ScrollY=30 -> (22-22+30) div 24 = 1 }
begin
  AssertEquals('row with scroll', 1, TyReportRowAt(22, 30, 22, 24, 10));
end;

procedure TListReportRowAtTest.TestBeyondLastRowReturnsMinusOne;
{ AY=262 -> (262-22+0) div 24 = 10 >= RowCount(10) -> -1 }
begin
  AssertEquals('beyond last row', -1, TyReportRowAt(262, 0, 22, 24, 10));
end;

{ ===========================================================================
  Degenerate metrics
  =========================================================================== }

procedure TListDegenerateTest.TestZeroCountEveryFunctionIsSafe;
{ ACount=0: every function returns its documented empty result, none crash. }
var
  M: TTyListMetrics;
  f, l: Integer;
  hits: TTyIntArray;
begin
  M := IconMetrics;
  AssertSize('extent count0', 0, 0, TyListContentExtent(0, M));
  AssertRectEquals('rect count0', 0, 0, 0, 0, TyListItemRect(0, 0, M, 0, 0));
  AssertEquals('itemat count0', -1, TyListItemAt(Point(5, 5), 0, M, 0, 0));
  AssertFalse('range count0', TyListVisibleRange(0, M, 0, 0, f, l));
  AssertEquals('nav count0', -1, TyListNavigate(0, 0, lnDown, M));
  hits := TyListMarqueeHits(Rect(0, 0, 100, 100), 0, M, 0, 0);
  AssertEquals('marquee count0', 0, Length(hits));
end;

procedure TListDegenerateTest.TestZeroPitchGeometryDoesNotDivideByZero;
{ PitchX=0 (row-major) and PitchY=0 (column-major) must not divide by zero in
  any geometry function. }
var
  Mi, Ml: TTyListMetrics;
  f, l: Integer;
begin
  Mi := IconMetrics;   Mi.CellW := 0;  Mi.HGap := 0;   { PitchX = 0 }
  Ml := ListMetrics;   Ml.CellH := 0;  Ml.VGap := 0;   { PitchY = 0 }
  try
    TyListContentExtent(5, Mi);
    TyListItemRect(2, 5, Mi, 0, 0);
    TyListItemAt(Point(1, 1), 5, Mi, 0, 0);
    TyListVisibleRange(5, Mi, 0, 0, f, l);

    TyListContentExtent(5, Ml);
    TyListItemRect(2, 5, Ml, 0, 0);
    TyListItemAt(Point(1, 1), 5, Ml, 0, 0);
    TyListVisibleRange(5, Ml, 0, 0, f, l);
  except
    on E: Exception do
      Fail('zero-pitch geometry raised: ' + E.ClassName + ': ' + E.Message);
  end;
end;

{ ===========================================================================
  TyListCheckRect
  ---------------------------------------------------------------------------
  Contract (sp2a):
    function TyListCheckRect(const ACell: TRect; AStyle: TTyListViewStyle;
      ACheckPx, APad: Integer): TRect;
    - report / list / smallicon / tile : left-aligned, VERTICALLY CENTRED,
      inset from the left by APad.
    - lvsIcon                          : TOP-LEFT, inset by APad on both axes.
    - box is ACheckPx x ACheckPx.
    - ACheckPx <= 0, OR the cell cannot hold ACheckPx + APad in EITHER axis
      -> Rect(0,0,0,0).
  =========================================================================== }

procedure TListCheckRectTest.TestReportCheckRectIsLeftAlignedVerticallyCentred;
{ Cell (100,50)-(300,74): width 200, height 24. ACheckPx=14 APad=3.
  Left = 100+3 = 103; centred Top = 50 + (24-14) div 2 = 55;
  Right = 103+14 = 117; Bottom = 55+14 = 69.
  (Height difference 10 is EVEN, so floor-vs-round centring cannot disagree here.) }
begin
  AssertRectEquals('report check', 103, 55, 117, 69,
    TyListCheckRect(Rect(100, 50, 300, 74), lvsReport, 14, 3));
end;

procedure TListCheckRectTest.TestListSmallIconTileFollowTheSameCentredRule;
{ The three non-report, non-icon styles share the left-aligned + vertically-centred rule.
  Cell (0,0)-(134,40): Left=3; Top=(40-14) div 2 = 13; Right=17; Bottom=27.
  (Difference 26 is EVEN.) }
begin
  AssertRectEquals('smallicon check', 3, 13, 17, 27,
    TyListCheckRect(Rect(0, 0, 134, 40), lvsSmallIcon, 14, 3));
  AssertRectEquals('list check', 3, 13, 17, 27,
    TyListCheckRect(Rect(0, 0, 134, 40), lvsList, 14, 3));
  AssertRectEquals('tile check', 3, 13, 17, 27,
    TyListCheckRect(Rect(0, 0, 134, 40), lvsTile, 14, 3));
end;

procedure TListCheckRectTest.TestIconCheckRectIsTopLeftNotCentred;
{ Same cell as the report test, but lvsIcon puts the box at the TOP-left:
  Left = 100+3 = 103; Top = 50+3 = 53; Right = 117; Bottom = 53+14 = 67.
  If icon were (wrongly) centred like the others its Top would be 55, so this
  discriminates the two placements. }
begin
  AssertRectEquals('icon check top-left', 103, 53, 117, 67,
    TyListCheckRect(Rect(100, 50, 300, 74), lvsIcon, 14, 3));
end;

procedure TListCheckRectTest.TestZeroCheckPxIsEmptyRect;
begin
  AssertRectEquals('checkpx 0 -> empty', 0, 0, 0, 0,
    TyListCheckRect(Rect(100, 50, 300, 74), lvsReport, 0, 3));
end;

procedure TListCheckRectTest.TestNegativeCheckPxIsEmptyRect;
begin
  AssertRectEquals('checkpx <0 -> empty', 0, 0, 0, 0,
    TyListCheckRect(Rect(100, 50, 300, 74), lvsReport, -5, 3));
end;

procedure TListCheckRectTest.TestCellTooNarrowIsEmptyRect;
{ Needs width >= ACheckPx + APad = 17; width 16 is one short -> empty. }
begin
  AssertRectEquals('too narrow -> empty', 0, 0, 0, 0,
    TyListCheckRect(Rect(0, 0, 16, 40), lvsReport, 14, 3));
end;

procedure TListCheckRectTest.TestCellTooShortIsEmptyRect;
{ Needs height >= ACheckPx + APad = 17; height 16 is one short -> empty. }
begin
  AssertRectEquals('too short -> empty', 0, 0, 0, 0,
    TyListCheckRect(Rect(0, 0, 200, 16), lvsReport, 14, 3));
end;

procedure TListCheckRectTest.TestExactFitIsNotEmptyRect;
{ A cell exactly ACheckPx + APad in BOTH axes (17x17) CAN hold the box, so the
  result is NOT empty. lvsIcon is used so the top-left placement makes the
  coordinates exact with no centring rounding: Left=3, Top=3, Right=17, Bottom=17.
  This is the < vs <= boundary of the refusal rule -- see the notes returned with
  these tests: "cannot hold ACheckPx + APad" is read literally as "equal fits". }
begin
  AssertRectEquals('exact fit is not empty', 3, 3, 17, 17,
    TyListCheckRect(Rect(0, 0, 17, 17), lvsIcon, 14, 3));
end;

procedure TListCheckRectTest.TestOddCentringDifferenceFloors;
{ Every other centred case here happens to use an EVEN (Height - ACheckPx), where floor and
  round agree -- so nothing pinned which one the contract means. Height 25, box 14: the
  difference is 11, and floor gives Top = 5 while round would give 6. Pin floor. }
begin
  AssertRectEquals('odd centring difference floors', 3, 5, 17, 19,
    TyListCheckRect(Rect(0, 0, 200, 25), lvsReport, 14, 3));
end;

{ ===========================================================================
  SP2b group helpers — a tiny local builder so each test states only the group
  shape it cares about (count / collapsed / has-header).
  =========================================================================== }

function GroupInfo(ACount: Integer; ACollapsed, AHasHeader: Boolean): TTyListGroupInfo;
begin
  Result.Count := ACount;
  Result.Collapsed := ACollapsed;
  Result.HasHeader := AHasHeader;
end;

{ Copy an open array of group infos into the dynamic-array type the unit wants,
  then build the map. Lets tests write MakeMap([GroupInfo(...), ...], M, hh). }
function MakeMap(const AGroups: array of TTyListGroupInfo;
  const M: TTyListMetrics; AHeaderH: Integer): TTyListGroupMap;
var
  arr: TTyListGroupInfoArray;
  i: Integer;
begin
  SetLength(arr, Length(AGroups));
  for i := 0 to High(AGroups) do
    arr[i] := AGroups[i];
  Result := TyListBuildGroupMap(arr, M, AHeaderH);
end;

{ ===========================================================================
  TListGroupMapTest
  ---------------------------------------------------------------------------
  Canonical mixed map, IconMetrics (Tracks=4, PitchX=PitchY=70, Cell 60x60,
  HGap=VGap=10, ViewportW=300, M.HeaderH=0), group-header band AHeaderH=30.

    g  Count Collapsed HasHeader | rows body            header height Tops[g]
    0    5      no        yes    |  2   2*70-10=130       30    160     0
    1    0      no        yes    |  -   0                 30     30    160
    2    3      yes       yes    |  -   0 (collapsed)     30     30    190
    3    8      no        NO     |  2   2*70-10=130        0    130    220
                                                                        350 = Tops[4]
  FirstVisible (expanded groups contribute Count, collapsed contribute 0):
    FV[0]=0  FV[1]=5  FV[2]=5  FV[3]=5  FV[4]=13
  =========================================================================== }

function CanonicalMap: TTyListGroupMap;
begin
  Result := MakeMap([GroupInfo(5, False, True),
                     GroupInfo(0, False, True),
                     GroupInfo(3, True,  True),
                     GroupInfo(8, False, False)], IconMetrics, 30);
end;

procedure TListGroupMapTest.TestTopsIsPrefixSumOfGroupHeights;
var
  m: TTyListGroupMap;
begin
  m := CanonicalMap;
  AssertEquals('Tops length is G+1', 5, Length(m.Tops));
  AssertEquals('Tops[0]', 0,   m.Tops[0]);
  AssertEquals('Tops[1]', 160, m.Tops[1]);
  AssertEquals('Tops[2]', 190, m.Tops[2]);
  AssertEquals('Tops[3]', 220, m.Tops[3]);
  AssertEquals('Tops[4]=total content height', 350, m.Tops[4]);
end;

procedure TListGroupMapTest.TestContentHeightIsLastTop;
{ ContentHeight = Tops[High(Tops)] = Tops[G]. }
var
  m: TTyListGroupMap;
begin
  m := CanonicalMap;
  AssertEquals('content height = Tops[G]', 350, TyListGroupContentHeight(m));
end;

procedure TListGroupMapTest.TestTopsIsMonotonicNonDecreasing;
{ Non-decreasing must hold even when a group adds ZERO height. A collapsed,
  header-less group contributes header 0 + body 0 = 0, so Tops repeats:
    G0 expanded hasHeader Count=4 : rows 1, body 70-10=60, +30 = 90 ; Tops 0->90
    G1 collapsed NO header        : 0                                ; Tops 90->90
    G2 expanded hasHeader Count=2 : rows 1, body 60, +30 = 90        ; Tops 90->180 }
var
  m: TTyListGroupMap;
  g: Integer;
begin
  m := MakeMap([GroupInfo(4, False, True),
                GroupInfo(5, True,  False),
                GroupInfo(2, False, True)], IconMetrics, 30);
  AssertEquals('Tops[0]', 0,   m.Tops[0]);
  AssertEquals('Tops[1]', 90,  m.Tops[1]);
  AssertEquals('Tops[2] repeats (zero-height group)', 90, m.Tops[2]);
  AssertEquals('Tops[3]', 180, m.Tops[3]);
  for g := 0 to High(m.Tops) - 1 do
    AssertTrue(Format('Tops non-decreasing at %d', [g]), m.Tops[g + 1] >= m.Tops[g]);
end;

procedure TListGroupMapTest.TestCollapsedGroupIsHeaderOnly;
{ Group 2 is collapsed: its height is exactly the header band (30), so
  Tops[3]-Tops[2] = 30, and it adds nothing to the visible count. }
var
  m: TTyListGroupMap;
begin
  m := CanonicalMap;
  AssertEquals('collapsed group height = header only',
    30, m.Tops[3] - m.Tops[2]);
  AssertEquals('collapsed group adds no visible items',
    m.FirstVisible[2], m.FirstVisible[3]);
end;

procedure TListGroupMapTest.TestEmptyCountGroupKeepsFirstVisible;
{ Group 1 has Count=0: it still occupies a header (height 30) but contributes
  no items, so FirstVisible[2] = FirstVisible[1]. }
var
  m: TTyListGroupMap;
begin
  m := CanonicalMap;
  AssertEquals('empty group still has a header band', 30, m.Tops[2] - m.Tops[1]);
  AssertEquals('empty group keeps FirstVisible', m.FirstVisible[1], m.FirstVisible[2]);
end;

procedure TListGroupMapTest.TestHeaderlessGroupAddsNoHeaderHeight;
{ Group 3 has HasHeader=False: its height is pure body (130), no header band.
  Compare against the same body WITH a header (group 0, also body 130): the
  difference is exactly AHeaderH=30. }
var
  m: TTyListGroupMap;
begin
  m := CanonicalMap;
  AssertEquals('header-less group is body-only', 130, m.Tops[4] - m.Tops[3]);
  AssertEquals('header-ful group of same body adds AHeaderH',
    30, (m.Tops[1] - m.Tops[0]) - (m.Tops[4] - m.Tops[3]));
end;

procedure TListGroupMapTest.TestFirstVisibleCountsExpandedItemsOnly;
{ FirstVisible accumulates Count for every EXPANDED group (header-ful or not)
  and 0 for collapsed ones. Note group 3 is header-LESS yet still contributes
  its 8 items — HasHeader affects layout height, never visibility. }
var
  m: TTyListGroupMap;
begin
  m := CanonicalMap;
  AssertEquals('FV length is G+1', 5, Length(m.FirstVisible));
  AssertEquals('FV[0]', 0,  m.FirstVisible[0]);
  AssertEquals('FV[1]', 5,  m.FirstVisible[1]);
  AssertEquals('FV[2]', 5,  m.FirstVisible[2]);
  AssertEquals('FV[3]', 5,  m.FirstVisible[3]);
  AssertEquals('FV[4]=total visible count', 13, m.FirstVisible[4]);
end;

procedure TListGroupMapTest.TestReportBodyIsCountTimesRowH;
{ In lvsReport the body is Count*RowH (RowH=24), not a row/track grid.
  Group 0 expanded hasHeader Count=5 : body 5*24=120, +AHeaderH 20 = 140.
  Group 1 collapsed hasHeader Count=9: header only 20.
  M.HeaderH (report list header, 22) is NOT part of the content Tops — the
  content Y origin is the item region top. }
var
  m: TTyListGroupMap;
begin
  m := MakeMap([GroupInfo(5, False, True),
                GroupInfo(9, True,  True)], ReportMetrics, 20);
  AssertEquals('Tops[0]', 0,   m.Tops[0]);
  AssertEquals('report body = Count*RowH + header', 140, m.Tops[1]);
  AssertEquals('collapsed report group = header only', 160, m.Tops[2]);
end;

procedure TListGroupMapTest.TestAllCollapsedContentHeightIsGTimesHeader;
{ Every group collapsed with a header: ContentHeight = G * AHeaderH, and the
  total visible count is 0. G=3, AHeaderH=30 -> 90. }
var
  m: TTyListGroupMap;
begin
  m := MakeMap([GroupInfo(5, True, True),
                GroupInfo(3, True, True),
                GroupInfo(7, True, True)], IconMetrics, 30);
  AssertEquals('all-collapsed content height', 90, TyListGroupContentHeight(m));
  AssertEquals('all-collapsed visible count', 0, m.FirstVisible[3]);
end;

{ ===========================================================================
  TListGroupHeaderRectTest
  ---------------------------------------------------------------------------
  Header band of group g is at content Y = Tops[g], spans [0, ViewportW], and
  is returned in CLIENT coords: client Y = Tops[g] + M.HeaderH - AScrollY,
  height = AHeaderH. Icon metrics -> M.HeaderH = 0.
  =========================================================================== }

procedure TListGroupHeaderRectTest.TestHeaderRectSpansViewportAtGroupTop;
{ Group 2 header at content Y = Tops[2] = 190. No scroll, M.HeaderH=0:
  Rect(0, 190, ViewportW=300, 190+30=220). }
begin
  AssertRectEquals('group2 header band', 0, 190, 300, 220,
    TyListGroupHeaderRect(CanonicalMap, 2, IconMetrics, 30, 0));
end;

procedure TListGroupHeaderRectTest.TestHeaderRectSubtractsVerticalScroll;
{ Same band with AScrollY=40: client Y = 190-40 = 150 .. 180. Width unchanged. }
begin
  AssertRectEquals('group2 header scrolled', 0, 150, 300, 180,
    TyListGroupHeaderRect(CanonicalMap, 2, IconMetrics, 30, 40));
end;

procedure TListGroupHeaderRectTest.TestHeaderlessGroupHasEmptyHeaderRect;
{ Group 3 has HasHeader=False -> no header band -> Rect(0,0,0,0). }
begin
  AssertRectEquals('header-less group header rect', 0, 0, 0, 0,
    TyListGroupHeaderRect(CanonicalMap, 3, IconMetrics, 30, 0));
end;

procedure TListGroupHeaderRectTest.TestOutOfRangeGroupHasEmptyHeaderRect;
begin
  AssertRectEquals('group -1', 0, 0, 0, 0,
    TyListGroupHeaderRect(CanonicalMap, -1, IconMetrics, 30, 0));
  AssertRectEquals('group =G', 0, 0, 0, 0,
    TyListGroupHeaderRect(CanonicalMap, 4, IconMetrics, 30, 0));
end;

{ ===========================================================================
  TListGroupItemRectTest
  ---------------------------------------------------------------------------
  Body of group g starts (content Y) at Tops[g] + (HasHeader ? AHeaderH : 0).
  Within the body, item i is row-major: row = i div Tracks, col = i mod Tracks,
  at (col*PitchX, bodyTop + row*PitchY). Client = content + M.HeaderH - scroll.
  Group 0: Tops[0]=0, header 30 -> bodyTop=30 (content). Icon: M.HeaderH=0.
  =========================================================================== }

procedure TListGroupItemRectTest.TestFirstItemSitsAtBodyTopLeft;
{ (g=0,i=0): row0 col0 -> content (0, 30) -> Rect(0,30,60,90). }
begin
  AssertRectEquals('group0 item0', 0, 30, 60, 90,
    TyListGroupItemRect(CanonicalMap, 0, 0, IconMetrics, 30, 0, 0));
end;

procedure TListGroupItemRectTest.TestItemRowColFromIndexInGroup;
{ (g=0,i=1): row0 col1 -> (70, 30) -> Rect(70,30,130,90).
  (g=0,i=4): row1 col0 -> (0, 30+70=100) -> Rect(0,100,60,160). }
begin
  AssertRectEquals('group0 item1 (col1)', 70, 30, 130, 90,
    TyListGroupItemRect(CanonicalMap, 0, 1, IconMetrics, 30, 0, 0));
  AssertRectEquals('group0 item4 (row1 col0)', 0, 100, 60, 160,
    TyListGroupItemRect(CanonicalMap, 0, 4, IconMetrics, 30, 0, 0));
end;

procedure TListGroupItemRectTest.TestItemRectSubtractsScroll;
{ (g=0,i=0) with scroll (25,10): Rect(-25,20,35,80). }
begin
  AssertRectEquals('group0 item0 scrolled', -25, 20, 35, 80,
    TyListGroupItemRect(CanonicalMap, 0, 0, IconMetrics, 30, 25, 10));
end;

procedure TListGroupItemRectTest.TestCollapsedGroupItemRectIsEmpty;
{ Group 2 is collapsed: every one of its items has an empty rect. }
var
  m: TTyListGroupMap;
  i: Integer;
begin
  m := CanonicalMap;
  for i := 0 to 2 do
    AssertRectEquals(Format('collapsed group item %d', [i]), 0, 0, 0, 0,
      TyListGroupItemRect(m, 2, i, IconMetrics, 30, 0, 0));
end;

procedure TListGroupItemRectTest.TestOutOfRangeGroupOrIndexIsEmpty;
var
  m: TTyListGroupMap;
begin
  m := CanonicalMap;
  AssertRectEquals('group -1', 0, 0, 0, 0,
    TyListGroupItemRect(m, -1, 0, IconMetrics, 30, 0, 0));
  AssertRectEquals('group =G', 0, 0, 0, 0,
    TyListGroupItemRect(m, 4, 0, IconMetrics, 30, 0, 0));
  AssertRectEquals('index =Count', 0, 0, 0, 0,
    TyListGroupItemRect(m, 0, 5, IconMetrics, 30, 0, 0));
  AssertRectEquals('index -1', 0, 0, 0, 0,
    TyListGroupItemRect(m, 0, -1, IconMetrics, 30, 0, 0));
end;

{ ===========================================================================
  TListGroupHitTestTest
  =========================================================================== }

procedure TListGroupHitTestTest.TestHeaderBandPointReturnsIndexMinusOne;
{ A point inside group 0's header band (content Y [0,30), client the same with
  M.HeaderH=0) hits the group with AIndexInGroup = -1. Probe the band centre. }
var
  r: TRect;
  g, i: Integer;
begin
  r := TyListGroupHeaderRect(CanonicalMap, 0, IconMetrics, 30, 0);
  AssertTrue('header point hits',
    TyListGroupHitTest(CanonicalMap, Point((r.Left + r.Right) div 2,
      (r.Top + r.Bottom) div 2), IconMetrics, 30, 0, 0, g, i));
  AssertEquals('header group', 0, g);
  AssertEquals('header indexInGroup = -1', -1, i);
end;

procedure TListGroupHitTestTest.TestCollapsedGroupHeaderStillHittable;
{ Group 2 is collapsed but its header band is still clickable (that is how you
  expand it): a point in it -> True, group 2, index -1. }
var
  r: TRect;
  g, i: Integer;
begin
  r := TyListGroupHeaderRect(CanonicalMap, 2, IconMetrics, 30, 0);
  AssertTrue('collapsed header hits',
    TyListGroupHitTest(CanonicalMap, Point((r.Left + r.Right) div 2,
      (r.Top + r.Bottom) div 2), IconMetrics, 30, 0, 0, g, i));
  AssertEquals('collapsed header group', 2, g);
  AssertEquals('collapsed header index -1', -1, i);
end;

procedure TListGroupHitTestTest.TestPointBelowCollapsedHeaderBelongsToNextGroup;
{ Dedicated map:
    G0 collapsed hasHeader Count=5 : header [0,30), height 30 ; Tops 0->30
    G1 expanded  hasHeader Count=3 : header [30,60), body from 60
  If G0 were expanded its first item would sit at content Y ~35. Because G0 is
  collapsed that space is reclaimed by G1's HEADER, so a point at Y=35 must hit
  (G1, -1) — never (G0, 0). This is the geometry-cannot-drift rule for collapse. }
var
  m: TTyListGroupMap;
  g, i: Integer;
begin
  m := MakeMap([GroupInfo(5, True,  True),
                GroupInfo(3, False, True)], IconMetrics, 30);
  AssertTrue('point below collapsed header hits',
    TyListGroupHitTest(m, Point(20, 35), IconMetrics, 30, 0, 0, g, i));
  AssertEquals('belongs to next group', 1, g);
  AssertEquals('is that group''s header, not an item', -1, i);
end;

procedure TListGroupHitTestTest.TestCollapsedGroupItemsAllEmptyRects;
{ Companion to the previous test: the collapsed group really has no item cells. }
var
  m: TTyListGroupMap;
  i: Integer;
begin
  m := MakeMap([GroupInfo(5, True,  True),
                GroupInfo(3, False, True)], IconMetrics, 30);
  for i := 0 to 4 do
    AssertRectEquals(Format('collapsed item %d empty', [i]), 0, 0, 0, 0,
      TyListGroupItemRect(m, 0, i, IconMetrics, 30, 0, 0));
end;

{ ===========================================================================
  TListGroupInverseTest
  ---------------------------------------------------------------------------
  For every visible (g,i): the cell's top-left +(1,1) point must hit back (g,i)
  through TyListGroupHitTest. Same discipline as SP1's ItemRect/ItemAt inverse.
  Count probes and assert at least one, so a skip cannot pass vacuously.
  =========================================================================== }

procedure TListGroupInverseTest.CheckGroupInverse(const AName: string;
  const AMap: TTyListGroupMap; const M: TTyListMetrics; AHeaderH, ASx, ASy: Integer);
var
  g, i, probed, hg, hi: Integer;
  r: TRect;
  pt: TPoint;
begin
  probed := 0;
  for g := 0 to High(AMap.Groups) do
    if not AMap.Groups[g].Collapsed then
      for i := 0 to AMap.Groups[g].Count - 1 do
      begin
        r := TyListGroupItemRect(AMap, g, i, M, AHeaderH, ASx, ASy);
        pt := Point(r.Left + 1, r.Top + 1);
        { Clamp the probe down into the item region: under a vertical scroll a
          cell's top can sit above the report list-header band (or above 0),
          where nothing is hittable by design. The clamped point still lands in
          the same cell's visible sliver because item bodies never overlap a
          header band. Skip cells that are wholly above the item area. }
        if pt.Y < M.HeaderH then
          pt.Y := M.HeaderH;
        if pt.Y >= r.Bottom then
          Continue;
        Inc(probed);
        AssertTrue(Format('%s: (%d,%d) hits', [AName, g, i]),
          TyListGroupHitTest(AMap, pt, M, AHeaderH, ASx, ASy, hg, hi));
        AssertEquals(Format('%s: (%d,%d) group', [AName, g, i]), g, hg);
        AssertEquals(Format('%s: (%d,%d) index', [AName, g, i]), i, hi);
      end;
  AssertTrue(Format('%s: at least one probe', [AName]), probed > 0);
end;

procedure TListGroupInverseTest.TestItemRectHitTestInverseNoScroll;
begin
  CheckGroupInverse('canonical', CanonicalMap, IconMetrics, 30, 0, 0);
end;

procedure TListGroupInverseTest.TestItemRectHitTestInverseWithScroll;
{ A modest scroll pushes early cells' tops negative; the round-trip must hold. }
begin
  CheckGroupInverse('canonical+sx', CanonicalMap, IconMetrics, 30, 20, 0);
  CheckGroupInverse('canonical+sy', CanonicalMap, IconMetrics, 30, 0, 45);
  CheckGroupInverse('canonical+both', CanonicalMap, IconMetrics, 30, 20, 45);
end;

procedure TListGroupInverseTest.TestReportItemRectHitTestInverse;
{ Report mode (Tracks=1, RowH=24, M.HeaderH=22) with a collapsed group between
  two expanded ones, so the inverse also proves the collapsed group's rows are
  simply absent from the probe set. }
var
  m: TTyListGroupMap;
begin
  m := MakeMap([GroupInfo(3, False, True),
                GroupInfo(2, True,  True),
                GroupInfo(4, False, True)], ReportMetrics, 20);
  CheckGroupInverse('report', m, ReportMetrics, 20, 0, 0);
  CheckGroupInverse('report+sy', m, ReportMetrics, 20, 0, 15);
end;

{ ===========================================================================
  TListGroupDisplayPosTest
  ---------------------------------------------------------------------------
  For an expanded group g, item i has display position FirstVisible[g] + i.
  Collapsed groups occupy no display positions. Canonical map visible layout:
    group 0 -> display 0..4   (FV[0]=0, Count 5)
    group 1 -> (empty)
    group 2 -> (collapsed)
    group 3 -> display 5..12  (FV[3]=5, Count 8)   VisibleCount=13
  =========================================================================== }

procedure TListGroupDisplayPosTest.CheckDisplayInverse(const AName: string;
  const AMap: TTyListGroupMap);
var
  g, i, pos, probed, og, oi: Integer;
begin
  probed := 0;
  { forward: every visible (g,i) -> a display position and back. }
  for g := 0 to High(AMap.Groups) do
    if not AMap.Groups[g].Collapsed then
      for i := 0 to AMap.Groups[g].Count - 1 do
      begin
        pos := TyListGroupDisplayPos(AMap, g, i);
        AssertEquals(Format('%s: displaypos(%d,%d)', [AName, g, i]),
          AMap.FirstVisible[g] + i, pos);
        AssertTrue(Format('%s: ofdisplaypos(%d) ok', [AName, pos]),
          TyListGroupOfDisplayPos(AMap, pos, og, oi));
        AssertEquals(Format('%s: ofdisplaypos(%d) group', [AName, pos]), g, og);
        AssertEquals(Format('%s: ofdisplaypos(%d) index', [AName, pos]), i, oi);
        Inc(probed);
      end;
  AssertTrue(Format('%s: at least one probe', [AName]), probed > 0);
end;

procedure TListGroupDisplayPosTest.TestDisplayPosIsFirstVisiblePlusIndex;
{ Spot-check the two boundary items that a fencepost bug would move:
  group 3 item 0 is the first display after group 0's block (5), and the last
  item of the last group is VisibleCount-1 (12). }
var
  m: TTyListGroupMap;
begin
  m := CanonicalMap;
  AssertEquals('group0 item0 -> 0',   0,  TyListGroupDisplayPos(m, 0, 0));
  AssertEquals('group0 item4 -> 4',   4,  TyListGroupDisplayPos(m, 0, 4));
  AssertEquals('group3 item0 -> 5',   5,  TyListGroupDisplayPos(m, 3, 0));
  AssertEquals('group3 item7 -> 12',  12, TyListGroupDisplayPos(m, 3, 7));
end;

procedure TListGroupDisplayPosTest.TestOfDisplayPosAndDisplayPosAreInverse;
begin
  CheckDisplayInverse('canonical', CanonicalMap);
end;

procedure TListGroupDisplayPosTest.TestCollapsedGroupItemHasNoDisplayPos;
{ An item that lives inside the collapsed group is not visible: it has no
  display position, so TyListGroupDisplayPos returns -1. }
begin
  AssertEquals('collapsed group item -> -1', -1,
    TyListGroupDisplayPos(CanonicalMap, 2, 0));
end;

procedure TListGroupDisplayPosTest.TestOutOfRangeDisplayPosReturnsFalse;
var
  m: TTyListGroupMap;
  g, i: Integer;
begin
  m := CanonicalMap;   { VisibleCount = 13 }
  AssertFalse('pos -1 -> False', TyListGroupOfDisplayPos(m, -1, g, i));
  AssertEquals('pos -1 group -1', -1, g);
  AssertEquals('pos -1 index -1', -1, i);
  AssertFalse('pos =VisibleCount -> False', TyListGroupOfDisplayPos(m, 13, g, i));
  AssertEquals('pos =VC group -1', -1, g);
  AssertEquals('pos =VC index -1', -1, i);
end;

{ ===========================================================================
  TListGroupVisibleRangeTest
  ---------------------------------------------------------------------------
  200 uniform groups, IconMetrics: each expanded hasHeader Count=4 -> rows 1,
  body 70-10=60, +header 30 = height 90. Tops[g] = 90*g, ContentHeight=18000.
  ViewportH=300, M.HeaderH=0.
  =========================================================================== }

function UniformGroups(ACount: Integer): TTyListGroupInfoArray;
var
  i: Integer;
begin
  SetLength(Result, ACount);
  for i := 0 to ACount - 1 do
    Result[i] := GroupInfo(4, False, True);
end;

procedure TListGroupVisibleRangeTest.TestMiddleScrollReturnsOnlyViewportGroups;
{ ScrollY=9000: viewport content Y = [9000, 9300). Group g spans [90g, 90g+90).
  First group with Tops[g] <= 9000 is g=100 (Tops=9000). Last group intersecting
  9300 is g=103 (Tops=9270 < 9300; g=104 Tops=9360 >= 9300). So [100,103] — a
  4-group window out of 200, NOT the whole array. }
var
  m: TTyListGroupMap;
  f, l: Integer;
begin
  m := TyListBuildGroupMap(UniformGroups(200), IconMetrics, 30);
  AssertTrue('middle scroll visible',
    TyListGroupVisibleRange(m, IconMetrics, 9000, f, l));
  AssertEquals('first group', 100, f);
  AssertEquals('last group', 103, l);
  AssertTrue('window is small, not the whole array', (l - f) < 10);
  AssertTrue('window does not start at 0', f > 0);
  AssertTrue('window does not reach the end', l < 199);
end;

procedure TListGroupVisibleRangeTest.TestGroupWhoseBottomEqualsViewportTopIsNotVisible;
{ Half-open window, same convention SP1 uses. Each uniform group is 90px tall, so group 0
  spans content Y [0,90). Scroll exactly 90: the viewport top is 90, group 0's bottom edge
  is 90 -> they touch but do not overlap, so group 0 is NOT in the range; it starts at 1. }
var
  m: TTyListGroupMap;
  f, l: Integer;
begin
  m := TyListBuildGroupMap(UniformGroups(200), IconMetrics, 30);
  AssertTrue('range at the exact boundary', TyListGroupVisibleRange(m, IconMetrics, 90, f, l));
  AssertEquals('a group whose bottom == viewport top is excluded', 1, f);
end;

procedure TListGroupVisibleRangeTest.TestScrolledPastAllContentReturnsFalse;
{ A valid map scrolled well past its total content height has nothing visible. }
var
  m: TTyListGroupMap;
  f, l: Integer;
begin
  m := TyListBuildGroupMap(UniformGroups(200), IconMetrics, 30);
  AssertFalse('scrolled past content -> False',
    TyListGroupVisibleRange(m, IconMetrics, 100000, f, l));
  AssertEquals('first -1', -1, f);
  AssertEquals('last -1', -1, l);
end;

procedure TListGroupVisibleRangeTest.TestTopScrollStartsAtFirstGroup;
{ ScrollY=0: [0,300) -> groups 0..3 (Tops[3]=270<300; Tops[4]=360>=300). }
var
  m: TTyListGroupMap;
  f, l: Integer;
begin
  m := TyListBuildGroupMap(UniformGroups(200), IconMetrics, 30);
  AssertTrue('top visible', TyListGroupVisibleRange(m, IconMetrics, 0, f, l));
  AssertEquals('first group 0', 0, f);
  AssertEquals('last group 3', 3, l);
end;

procedure TListGroupVisibleRangeTest.TestEmptyMapReturnsFalseAndMinusOne;
{ Empty AGroups -> empty map -> False, both out params -1. }
var
  m: TTyListGroupMap;
  f, l: Integer;
begin
  m := MakeMap([], IconMetrics, 30);
  AssertFalse('empty map -> False', TyListGroupVisibleRange(m, IconMetrics, 0, f, l));
  AssertEquals('empty first -1', -1, f);
  AssertEquals('empty last -1', -1, l);
end;

{ ===========================================================================
  TListGroupNavigateTest
  ---------------------------------------------------------------------------
  Main nav map, IconMetrics (Tracks=4):
    G0 expanded hasHeader Count=8 : display 0..7 (row0 idx0-3, row1 idx4-7)
    G1 collapsed hasHeader Count=3 : (skipped)
    G2 expanded hasHeader Count=0 : (empty, skipped)
    G3 expanded hasHeader Count=2 : display 8..9 (row0 idx0,1)
  FirstVisible = [0,8,8,8,10], VisibleCount=10.
  =========================================================================== }

function NavMap: TTyListGroupMap;
begin
  Result := MakeMap([GroupInfo(8, False, True),
                     GroupInfo(3, True,  True),
                     GroupInfo(0, False, True),
                     GroupInfo(2, False, True)], IconMetrics, 30);
end;

procedure TListGroupNavigateTest.TestDownWithinGroupMovesByTracks;
{ display 0 (G0 idx0 row0col0) -> down = idx4 (row1col0) -> display 4.
  display 1 (col1) -> idx5 -> display 5. }
begin
  AssertEquals('down within col0', 4, TyListGroupNavigate(NavMap, 0, lnDown, IconMetrics));
  AssertEquals('down within col1', 5, TyListGroupNavigate(NavMap, 1, lnDown, IconMetrics));
end;

function PartialNavMap: TTyListGroupMap;
{ Two expanded groups. G0 has 6 items in Tracks=4: a FULL row 0 (idx0-3) and a PARTIAL
  row 1 (idx4-5, only columns 0-1). G1 has 4 items. FirstVisible=[0,6,10]. }
begin
  Result := MakeMap([GroupInfo(6, False, True),
                     GroupInfo(4, False, True)], IconMetrics, 30);
end;

procedure TListGroupNavigateTest.TestDownFromAPartialLastRowStaysInTheGroup;
{ THE regression this batch was written for. From G0 idx2 (row0 col2), down. The cell
  directly beneath (idx6, col2 of row1) does NOT exist -- row1 only has cols 0-1 -- but
  row1 DOES exist, so down must stay in G0 and clamp to its last item idx5 (display 5),
  NOT jump to G1. The bug read `i + Tracks < Count` and jumped. }
begin
  AssertEquals('partial row down clamps to the group last item, not the next group',
    5, TyListGroupNavigate(PartialNavMap, 2, lnDown, IconMetrics));
end;

procedure TListGroupNavigateTest.TestDownFromTheTrueLastRowLeavesThePartialGroup;
{ From G0 idx5 (row1 col1, the genuine last row): down really does leave G0 and lands on
  G1's first row keeping column 1 -> G1 idx1 -> display 6 (FirstVisible[1]=6) + 1 = 7. }
begin
  AssertEquals('true last row down crosses to the next group',
    7, TyListGroupNavigate(PartialNavMap, 5, lnDown, IconMetrics));
end;

procedure TListGroupNavigateTest.TestDownOutOfGroupLandsOnNextExpandedNonEmptyKeepingColumn;
{ display 4 (G0 idx4 row1 col0): down leaves G0 -> lands on G3's first row at the
  SAME column 0 -> G3 idx0 -> display 8. }
begin
  AssertEquals('cross-down keeps col0', 8, TyListGroupNavigate(NavMap, 4, lnDown, IconMetrics));
end;

procedure TListGroupNavigateTest.TestDownOutOfGroupClampsColumnToRowLastItem;
{ display 7 (G0 idx7 row1 col3): down -> G3 first row, but that row only has
  cols 0..1, so column 3 clamps to the row's last item idx1 -> display 9. }
begin
  AssertEquals('cross-down clamps column', 9, TyListGroupNavigate(NavMap, 7, lnDown, IconMetrics));
end;

procedure TListGroupNavigateTest.TestDownSkipsCollapsedAndEmptyGroups;
{ From G0's last row, down reaches G3 — proving G1 (collapsed) and G2 (empty)
  are both skipped as landing targets. }
begin
  AssertEquals('down skips collapsed+empty', 8, TyListGroupNavigate(NavMap, 4, lnDown, IconMetrics));
end;

procedure TListGroupNavigateTest.TestUpWithinGroupMovesByTracks;
{ Up-clamp map: G0 Count=2 (row0 idx0,1), G1 Count=8 (row0 idx0-3, row1 idx4-7).
  display 6 (G1 idx4 row1 col0) -> up = idx0 -> display 2. }
var
  m: TTyListGroupMap;
begin
  m := MakeMap([GroupInfo(2, False, True),
                GroupInfo(8, False, True)], IconMetrics, 30);
  AssertEquals('up within group', 2, TyListGroupNavigate(m, 6, lnUp, IconMetrics));
end;

procedure TListGroupNavigateTest.TestUpOutOfGroupLandsOnPrevExpandedNonEmptyKeepingColumn;
{ Main nav map: display 8 (G3 idx0 col0): up leaves G3 -> lands on G0's LAST row
  (row1) at column 0 -> idx4 -> display 4.
  display 9 (G3 idx1 col1) -> G0 row1 col1 -> idx5 -> display 5. }
begin
  AssertEquals('cross-up keeps col0', 4, TyListGroupNavigate(NavMap, 8, lnUp, IconMetrics));
  AssertEquals('cross-up keeps col1', 5, TyListGroupNavigate(NavMap, 9, lnUp, IconMetrics));
end;

procedure TListGroupNavigateTest.TestUpOutOfGroupClampsColumnToRowLastItem;
{ Up-clamp map: display 5 (G1 idx3 row0 col3): up -> G0's last row, which has
  only cols 0..1, so column 3 clamps to idx1 -> display 1. }
var
  m: TTyListGroupMap;
begin
  m := MakeMap([GroupInfo(2, False, True),
                GroupInfo(8, False, True)], IconMetrics, 30);
  AssertEquals('cross-up clamps column', 1, TyListGroupNavigate(m, 5, lnUp, IconMetrics));
end;

procedure TListGroupNavigateTest.TestLastRowOfLastGroupDownDoesNotMove;
{ display 9 is the last visible position (G3 idx1). Down finds no further
  expanded non-empty group -> stays put. }
begin
  AssertEquals('last row down stays', 9, TyListGroupNavigate(NavMap, 9, lnDown, IconMetrics));
end;

procedure TListGroupNavigateTest.TestFirstRowOfFirstGroupUpDoesNotMove;
{ display 0 (G0 idx0 row0). Up finds no earlier group -> stays put. }
begin
  AssertEquals('first row up stays', 0, TyListGroupNavigate(NavMap, 0, lnUp, IconMetrics));
end;

procedure TListGroupNavigateTest.TestLeftRightAreFlatDisplayStep;
{ Left/Right ignore groups: they are flat display +-1 over visible positions,
  crossing group boundaries, and do not move at the ends. }
begin
  AssertEquals('right +1', 1, TyListGroupNavigate(NavMap, 0, lnRight, IconMetrics));
  AssertEquals('right crosses group', 8, TyListGroupNavigate(NavMap, 7, lnRight, IconMetrics));
  AssertEquals('left crosses group', 7, TyListGroupNavigate(NavMap, 8, lnLeft, IconMetrics));
  AssertEquals('left at start stays', 0, TyListGroupNavigate(NavMap, 0, lnLeft, IconMetrics));
  AssertEquals('right at end stays', 9, TyListGroupNavigate(NavMap, 9, lnRight, IconMetrics));
end;

procedure TListGroupNavigateTest.TestHomeAndEndAlwaysMove;
{ Home -> 0, End -> VisibleCount-1 = 9, from anywhere. }
begin
  AssertEquals('home', 0, TyListGroupNavigate(NavMap, 5, lnHome, IconMetrics));
  AssertEquals('end',  9, TyListGroupNavigate(NavMap, 5, lnEnd, IconMetrics));
end;

procedure TListGroupNavigateTest.TestPageDownAndPageUpClamp;
{ PageDown/PageUp move by one screen of cells (>=1) and clamp to [0,VC-1].
  From display 8 any positive page step clamps to 9; from display 1 any positive
  step clamps to 0 — so the clamp is asserted without pinning the exact step. }
begin
  AssertEquals('pagedown clamps to last', 9, TyListGroupNavigate(NavMap, 8, lnPageDown, IconMetrics));
  AssertEquals('pageup clamps to first',  0, TyListGroupNavigate(NavMap, 1, lnPageUp, IconMetrics));
end;

procedure TListGroupNavigateTest.TestReportUpDownMoveByOneAcrossGroups;
{ lvsReport: Up/Down are +-1 in display order (group headers take no display
  position), crossing group boundaries seamlessly.
  Two expanded report groups Count 4 each: display 0..3 | 4..7. }
var
  m: TTyListGroupMap;
begin
  m := MakeMap([GroupInfo(4, False, True),
                GroupInfo(4, False, True)], ReportMetrics, 20);
  AssertEquals('report down within', 1, TyListGroupNavigate(m, 0, lnDown, ReportMetrics));
  AssertEquals('report down crosses group', 4, TyListGroupNavigate(m, 3, lnDown, ReportMetrics));
  AssertEquals('report up crosses group',   3, TyListGroupNavigate(m, 4, lnUp, ReportMetrics));
  AssertEquals('report down at end stays',  7, TyListGroupNavigate(m, 7, lnDown, ReportMetrics));
  AssertEquals('report up at start stays',  0, TyListGroupNavigate(m, 0, lnUp, ReportMetrics));
end;

procedure TListGroupNavigateTest.TestGroupedReportLeftRightMoveByOne;
{ Deliberate divergence from SP1's FLAT report path, where Left/Right do not move. In a
  GROUPED report the contract makes Left/Right the flat display step +-1 in every mode, so
  the grouped path moves. Pinned so the divergence is a decision, not an accident. }
var
  m: TTyListGroupMap;
begin
  m := MakeMap([GroupInfo(4, False, True),
                GroupInfo(4, False, True)], ReportMetrics, 20);
  AssertEquals('grouped report right = +1', 4, TyListGroupNavigate(m, 3, lnRight, ReportMetrics));
  AssertEquals('grouped report left = -1',  3, TyListGroupNavigate(m, 4, lnLeft, ReportMetrics));
  AssertEquals('right at the very end stays', 7,
    TyListGroupNavigate(m, 7, lnRight, ReportMetrics));
end;

procedure TListGroupNavigateTest.TestAllCollapsedNavigationReturnsMinusOne;
{ When every group is collapsed VisibleCount=0, so navigation has nowhere to go:
  every key returns -1 (like an empty flat list). }
var
  m: TTyListGroupMap;
begin
  m := MakeMap([GroupInfo(5, True, True),
                GroupInfo(3, True, True),
                GroupInfo(7, True, True)], IconMetrics, 30);
  AssertEquals('down',  -1, TyListGroupNavigate(m, 0, lnDown, IconMetrics));
  AssertEquals('up',    -1, TyListGroupNavigate(m, 0, lnUp, IconMetrics));
  AssertEquals('home',  -1, TyListGroupNavigate(m, 0, lnHome, IconMetrics));
  AssertEquals('end',   -1, TyListGroupNavigate(m, 0, lnEnd, IconMetrics));
end;

{ ===========================================================================
  TListGroupDegenerateTest
  =========================================================================== }

procedure TListGroupDegenerateTest.TestEmptyGroupsEveryFunctionIsSafe;
{ G=0 (empty AGroups): ContentHeight=0, every accessor returns its documented
  empty result and none crash. }
var
  m: TTyListGroupMap;
  f, l, g, i: Integer;
begin
  m := MakeMap([], IconMetrics, 30);
  AssertEquals('content height 0', 0, TyListGroupContentHeight(m));
  AssertRectEquals('header rect empty', 0, 0, 0, 0,
    TyListGroupHeaderRect(m, 0, IconMetrics, 30, 0));
  AssertRectEquals('item rect empty', 0, 0, 0, 0,
    TyListGroupItemRect(m, 0, 0, IconMetrics, 30, 0, 0));
  AssertFalse('hittest false',
    TyListGroupHitTest(m, Point(5, 5), IconMetrics, 30, 0, 0, g, i));
  AssertEquals('hittest group -1', -1, g);
  AssertEquals('hittest index -1', -1, i);
  AssertFalse('visiblerange false', TyListGroupVisibleRange(m, IconMetrics, 0, f, l));
  AssertFalse('ofdisplaypos false', TyListGroupOfDisplayPos(m, 0, g, i));
  AssertEquals('displaypos -1', -1, TyListGroupDisplayPos(m, 0, 0));
  AssertEquals('navigate -1', -1, TyListGroupNavigate(m, 0, lnDown, IconMetrics));
end;

procedure TListGroupDegenerateTest.TestZeroPitchGroupGeometryDoesNotDivideByZero;
{ PitchX=PitchY=0 (icon) and RowH=0 (report) must not divide by zero anywhere in
  the group path — build, geometry, hit-test, range and navigation. }
var
  Mi, Mr: TTyListMetrics;
  mi_map, mr_map: TTyListGroupMap;
  f, l, g, i: Integer;
begin
  Mi := IconMetrics;  Mi.CellW := 0; Mi.CellH := 0; Mi.HGap := 0; Mi.VGap := 0;
  Mr := ReportMetrics; Mr.RowH := 0;
  try
    mi_map := MakeMap([GroupInfo(5, False, True),
                       GroupInfo(3, False, True)], Mi, 30);
    TyListGroupContentHeight(mi_map);
    TyListGroupItemRect(mi_map, 0, 2, Mi, 30, 0, 0);
    TyListGroupHitTest(mi_map, Point(1, 1), Mi, 30, 0, 0, g, i);
    TyListGroupVisibleRange(mi_map, Mi, 0, f, l);
    TyListGroupNavigate(mi_map, 0, lnDown, Mi);

    mr_map := MakeMap([GroupInfo(4, False, True),
                       GroupInfo(2, False, True)], Mr, 20);
    TyListGroupContentHeight(mr_map);
    TyListGroupItemRect(mr_map, 0, 1, Mr, 20, 0, 0);
    TyListGroupHitTest(mr_map, Point(1, 30), Mr, 20, 0, 0, g, i);
    TyListGroupVisibleRange(mr_map, Mr, 0, f, l);
    TyListGroupNavigate(mr_map, 0, lnDown, Mr);
  except
    on E: Exception do
      Fail('zero-pitch group geometry raised: ' + E.ClassName + ': ' + E.Message);
  end;
end;

initialization
  RegisterTest(TListCellSizeTest);
  RegisterTest(TListTracksTest);
  RegisterTest(TListContentExtentTest);
  RegisterTest(TListItemRectTest);
  RegisterTest(TListItemAtTest);
  RegisterTest(TListInverseTest);
  RegisterTest(TListVisibleRangeTest);
  RegisterTest(TListNavigateTest);
  RegisterTest(TListRangeBoundsTest);
  RegisterTest(TListMarqueeTest);
  RegisterTest(TListPrefixTest);
  RegisterTest(TListCompareTest);
  RegisterTest(TListReportRowAtTest);
  RegisterTest(TListDegenerateTest);
  RegisterTest(TListCheckRectTest);
  RegisterTest(TListGroupMapTest);
  RegisterTest(TListGroupHeaderRectTest);
  RegisterTest(TListGroupItemRectTest);
  RegisterTest(TListGroupHitTestTest);
  RegisterTest(TListGroupInverseTest);
  RegisterTest(TListGroupDisplayPosTest);
  RegisterTest(TListGroupVisibleRangeTest);
  RegisterTest(TListGroupNavigateTest);
  RegisterTest(TListGroupDegenerateTest);
end.
