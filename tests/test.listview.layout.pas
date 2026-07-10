unit test.listview.layout;
{ Pure headless tests for the layout unit tyControls.ListView.Layout.
  Written from the CONTRACT ONLY (docs/superpowers/plans/2026-07-10-listview-sp1.md,
  section "任务 1 契约"); the implementation was NOT read. Every expected value below
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
{ lvsIcon: (IconPx + 4*Pad, IconPx + LabelH + 3*Pad) = (32+16, 32+16+12) = (48, 60) }
begin
  AssertSize('icon cell', 48, 60, TyListCellSize(CellSizeMetrics(lvsIcon)));
end;

procedure TListCellSizeTest.TestSmallIconCellSizeIsIconLeftLabelRight;
{ lvsSmallIcon: (IconPx + 12*Pad, Max(IconPx,LabelH) + 2*Pad) = (32+48, 32+8) = (80, 40) }
begin
  AssertSize('smallicon cell', 80, 40, TyListCellSize(CellSizeMetrics(lvsSmallIcon)));
end;

procedure TListCellSizeTest.TestListCellSizeMatchesSmallIcon;
{ lvsList shares the smallicon formula: (80, 40) }
begin
  AssertSize('list cell', 80, 40, TyListCellSize(CellSizeMetrics(lvsList)));
end;

procedure TListCellSizeTest.TestTileCellSizeIsTwoLabelLines;
{ lvsTile: (IconPx + 20*Pad, Max(IconPx, 2*LabelH) + 2*Pad) = (32+80, Max(32,32)+8) = (112, 40) }
begin
  AssertSize('tile cell', 112, 40, TyListCellSize(CellSizeMetrics(lvsTile)));
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
end.
