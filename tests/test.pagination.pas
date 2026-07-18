unit test.pagination;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.Pagination;

type
  { Pure-rules tests: the ellipsis rule and the geometry take only integers, so they run with
    no window handle, no theme and no control instance at all. }
  TTyPaginationRulesTest = class(TTestCase)
  published
    { the page-index rules }
    procedure TestValidIndexClampsIntoTheRun;
    procedure TestStepTurnsOnePage;
    procedure TestStepClampsAtTheEnds;
    procedure TestStepOnAnEmptyRunIsNone;
    { the ellipsis rule }
    procedure TestNoPagesHasNoItemsAtAll;
    procedure TestOnePageIsJustThatPage;
    procedure TestShortRunShowsEveryPage;
    procedure TestOneMorePageStartsEliding;
    procedure TestCurrentAtTheStartKeepsTheWindowWidth;
    procedure TestCurrentAtTheEndKeepsTheWindowWidth;
    procedure TestCurrentInTheMiddleElidesBothSides;
    procedure TestItemCountIsConstantAcrossTheWholeRun;
    procedure TestAnEllipsisNeverHidesASinglePage;
    procedure TestPrevNextCarryTheirTargetAndGoInertAtTheEnds;
    procedure TestPrevNextCanBeSuppressed;
    procedure TestSiblingCountWidensTheWindow;
    procedure TestBoundaryCountKeepsMorePagesAtEachEnd;
    procedure TestKnobsAreClampedToASaneRule;
    procedure TestOutOfRangeCurrentIsClampedByTheRule;
    procedure TestItemLabelIsOneBased;
    procedure TestItemVariantNamesTheKind;
    { the geometry }
    procedure TestCellsSitInThePaddedBandAGapApart;
    procedure TestCellsAreNotEqualWidth;
    procedure TestMinCellWidthFloorsANarrowCell;
    procedure TestACellThatDoesNotFitIsDroppedAndSoIsEveryLaterOne;
    procedure TestPaddingEatsWholeStrip;
    procedure TestZeroSizeIsEmpty;
    procedure TestIndexAtIsTheInverseOfItemRects;
    procedure TestIndexAtInAGutterOrOutsideIsNone;
    procedure TestPreferredWidthRoundTrips;
    procedure TestPreferredWidthOfAnEmptyStripIsPaddingOnly;
    procedure TestPreferredHeightClearsTheGlyphSlot;
    procedure TestGlyphRectIsCentredAndClampedInItsCell;
  end;

  { Headless control behaviour: typeKey, defaults, theme-driven geometry, the click and
    keyboard rules, AutoSize measurement, and graceful degradation when the theme leaves a
    key undefined. }
  TTyPaginationControlTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FChanged: Integer;      // OnChange fire count
    procedure HandleChange(Sender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestDefaults;
    procedure TestOutOfRangePageIndexIsClamped;
    procedure TestShrinkingPageCountReclampsSilently;
    procedure TestOnChangeFiresOnceForACodeSet;
    procedure TestReturningToTheSamePageIsSilent;
    procedure TestCellRectsFollowTheThemeGapMetric;
    procedure TestMinCellWidthMetricRetunesTheCells;
    procedure TestCellAtIsTheInverseOfCellRect;
    procedure TestClickAPageCellTurnsThePage;
    procedure TestClickPrevAndNextStepOnePage;
    procedure TestClickAnEllipsisIsInert;
    procedure TestClickPrevAtTheFirstPageIsInert;
    procedure TestClickInAGutterKeepsThePage;
    procedure TestDisabledIgnoresAClick;
    procedure TestArrowsTurnThePage;
    procedure TestArrowsClampAtTheEnds;
    procedure TestHomeAndEndJumpToTheEnds;
    procedure TestDisabledLeavesKeysAlone;
    procedure TestPreferredSizeFitsTheWholeStrip;
    procedure TestStripFontIsMeasuredIntoTheCells;
    procedure TestGlyphSizeMetricFloorsThePreferredHeight;
    procedure TestCurrentPageCellTakesTheSelectedStyle;
    procedure TestOtherPageCellsDoNotTakeIt;
    procedure TestDisabledKeepsTheCurrentPageChip;
    procedure TestHoveredCellTakesTheHoverStyle;
    procedure TestInertCellsTakeTheDisabledStyle;
    procedure TestKindVariantIsAddressableByTheTheme;
    procedure TestUndefinedStripKeyDrawsNothing;
    procedure TestUndefinedItemKeyStillDrawsLabelsInTheStripInk;
  end;

implementation

{ A one-line picture of an item list, so a test asserts the rule the way a human checks it:
  '<' prev, '>' next, '.' an ellipsis, and a 1-BASED page number for a page cell (i.e. the
  label the control actually draws). }
function Sketch(const AList: TTyPaginationItems): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(AList) do
  begin
    if Result <> '' then Result := Result + ' ';
    case AList[i].Kind of
      pikPrev:     Result := Result + '<';
      pikNext:     Result := Result + '>';
      pikEllipsis: Result := Result + '.';
    else
      Result := Result + IntToStr(AList[i].Page + 1);
    end;
  end;
end;

{ TTyPaginationRulesTest }

procedure TTyPaginationRulesTest.TestValidIndexClampsIntoTheRun;
begin
  // The deliberate deviation from TySegmentedValidIndex (which answers -1 for out of range):
  // a list is always SHOWING some page, so "which page am I on" is never "none" while pages
  // exist. Out of range is the caller's off-by-something, and the last page is what its data
  // can actually give.
  AssertEquals('in range', 3, TyPaginationValidIndex(3, 195));
  AssertEquals('first', 0, TyPaginationValidIndex(0, 195));
  AssertEquals('last', 194, TyPaginationValidIndex(194, 195));
  AssertEquals('past the end clamps to the last page', 194, TyPaginationValidIndex(500, 195));
  AssertEquals('negative clamps to the first page', 0, TyPaginationValidIndex(-7, 195));
  // ...and the one case that IS "none": there are no pages to be on.
  AssertEquals('no pages, no current page', -1, TyPaginationValidIndex(0, 0));
  AssertEquals('nor for a negative run', -1, TyPaginationValidIndex(3, -2));
end;

procedure TTyPaginationRulesTest.TestStepTurnsOnePage;
begin
  AssertEquals('forward', 4, TyPaginationStepIndex(3, 195, 1));
  AssertEquals('back', 2, TyPaginationStepIndex(3, 195, -1));
  AssertEquals('a zero step stays put', 3, TyPaginationStepIndex(3, 195, 0));
  // A stranded current steps from where the strip is actually showing, not from a page that
  // does not exist: clamped BEFORE the step as well as after.
  AssertEquals('a stranded page steps from the last one', 193,
    TyPaginationStepIndex(500, 195, -1));
end;

procedure TTyPaginationRulesTest.TestStepClampsAtTheEnds;
begin
  // No wrap: running off the end of a result set should stop, not teleport the user from
  // page 195 back to page 1.
  AssertEquals('forward at the last page stays', 194, TyPaginationStepIndex(194, 195, 1));
  AssertEquals('back at the first page stays', 0, TyPaginationStepIndex(0, 195, -1));
end;

procedure TTyPaginationRulesTest.TestStepOnAnEmptyRunIsNone;
begin
  AssertEquals('no pages to step onto', -1, TyPaginationStepIndex(0, 0, 1));
  AssertEquals('and none going back', -1, TyPaginationStepIndex(0, 0, -1));
end;

procedure TTyPaginationRulesTest.TestNoPagesHasNoItemsAtAll;
begin
  // Not even the arrows: a strip of two dead arrows would claim there is something to page.
  AssertEquals('nothing to paginate, nothing to draw', '',
    Sketch(TyPaginationItems(0, 0, 1, 1, True)));
  AssertEquals('and a negative run is the same', '',
    Sketch(TyPaginationItems(-5, 0, 1, 1, True)));
end;

procedure TTyPaginationRulesTest.TestOnePageIsJustThatPage;
begin
  AssertEquals('one page, one cell, two dead arrows', '< 1 >',
    Sketch(TyPaginationItems(1, 0, 1, 1, True)));
  AssertEquals('two pages', '< 1 2 >', Sketch(TyPaginationItems(2, 0, 1, 1, True)));
  AssertEquals('three', '< 1 2 3 >', Sketch(TyPaginationItems(3, 1, 1, 1, True)));
end;

procedure TTyPaginationRulesTest.TestShortRunShowsEveryPage;
begin
  // At the default knobs a run of 7 is exactly what fits without eliding: head(1) + gap(1) +
  // window(3) + gap(1) + tail(1). Every page is reachable and there is no '...' anywhere.
  AssertEquals('a 7-page run needs no ellipsis', '< 1 2 3 4 5 6 7 >',
    Sketch(TyPaginationItems(7, 3, 1, 1, True)));
  // ...from either end of it, too.
  AssertEquals('nor from the first page', '< 1 2 3 4 5 6 7 >',
    Sketch(TyPaginationItems(7, 0, 1, 1, True)));
  AssertEquals('nor from the last', '< 1 2 3 4 5 6 7 >',
    Sketch(TyPaginationItems(7, 6, 1, 1, True)));
end;

procedure TTyPaginationRulesTest.TestOneMorePageStartsEliding;
begin
  // THE ELISION BOUNDARY: one page more than TestShortRunShowsEveryPage's run and the strip
  // must elide -- and it elides exactly once, keeping the same number of cells.
  AssertEquals('an 8-page run elides once', '< 1 2 3 4 5 . 8 >',
    Sketch(TyPaginationItems(8, 3, 1, 1, True)));
  AssertEquals('and the cell count did not change', 9,
    Length(TyPaginationItems(8, 3, 1, 1, True)));
  AssertEquals('same as the 7-page run', Length(TyPaginationItems(7, 3, 1, 1, True)),
    Length(TyPaginationItems(8, 3, 1, 1, True)));
end;

procedure TTyPaginationRulesTest.TestCurrentAtTheStartKeepsTheWindowWidth;
begin
  // Near an end the window is pushed INWARDS rather than truncated, so the strip is the same
  // length here as in the middle -- it must not grow under the pointer as the user moves in.
  AssertEquals('page 1 of 195', '< 1 2 3 4 5 . 195 >',
    Sketch(TyPaginationItems(195, 0, 1, 1, True)));
  AssertEquals('page 2 of 195', '< 1 2 3 4 5 . 195 >',
    Sketch(TyPaginationItems(195, 1, 1, 1, True)));
  // The first page at which the head block detaches from the window.
  AssertEquals('page 5 of 195', '< 1 . 4 5 6 . 195 >',
    Sketch(TyPaginationItems(195, 4, 1, 1, True)));
end;

procedure TTyPaginationRulesTest.TestCurrentAtTheEndKeepsTheWindowWidth;
begin
  AssertEquals('the last page of 195', '< 1 . 191 192 193 194 195 >',
    Sketch(TyPaginationItems(195, 194, 1, 1, True)));
  AssertEquals('the one before it', '< 1 . 191 192 193 194 195 >',
    Sketch(TyPaginationItems(195, 193, 1, 1, True)));
end;

procedure TTyPaginationRulesTest.TestCurrentInTheMiddleElidesBothSides;
begin
  // The shape the whole control exists for.
  AssertEquals('page 98 of 195', '< 1 . 97 98 99 . 195 >',
    Sketch(TyPaginationItems(195, 97, 1, 1, True)));
end;

procedure TTyPaginationRulesTest.TestItemCountIsConstantAcrossTheWholeRun;
var
  i, n: Integer;
begin
  // Walk every page of a 195-run: the strip must never change length. This is what stops the
  // cells shifting sideways under a pointer that is aiming at one of them.
  n := Length(TyPaginationItems(195, 0, 1, 1, True));
  AssertEquals('the default knobs give a 9-cell strip', 9, n);
  for i := 0 to 194 do
    AssertEquals(Format('page %d of 195 has the same cell count', [i + 1]), n,
      Length(TyPaginationItems(195, i, 1, 1, True)));
end;

procedure TTyPaginationRulesTest.TestAnEllipsisNeverHidesASinglePage;
var
  cur, i, before, after: Integer;
  lst: TTyPaginationItems;
begin
  { An ellipsis that stands for exactly one page is a lie the same width as the truth: it
    hides a page for nothing. Walk every page of a 195-run and check that every '...' in
    every strip elides at least TWO pages -- measured from the page cells either side of it,
    which is the only thing the mark can be read as meaning. }
  for cur := 0 to 194 do
  begin
    lst := TyPaginationItems(195, cur, 1, 1, True);
    for i := 0 to High(lst) do
      if lst[i].Kind = pikEllipsis then
      begin
        AssertTrue('an ellipsis is never the first or last cell', (i > 0) and (i < High(lst)));
        AssertEquals('an ellipsis always follows a page cell', Ord(pikPage),
          Ord(lst[i - 1].Kind));
        AssertEquals('and always precedes one', Ord(pikPage), Ord(lst[i + 1].Kind));
        before := lst[i - 1].Page;
        after := lst[i + 1].Page;
        AssertTrue(Format('page %d: the ellipsis between %d and %d hides %d page(s)',
          [cur + 1, before + 1, after + 1, after - before - 1]),
          after - before - 1 >= 2);
      end;
  end;
end;

procedure TTyPaginationRulesTest.TestPrevNextCarryTheirTargetAndGoInertAtTheEnds;
var
  lst: TTyPaginationItems;
begin
  // The arrows are the item list's own business: each carries the 0-based page it goes to,
  // and "nowhere to go" is the absence of a target (Page < 0), not a second flag.
  lst := TyPaginationItems(195, 97, 1, 1, True);
  AssertEquals('prev is the first cell', Ord(pikPrev), Ord(lst[0].Kind));
  AssertEquals('prev goes back one page', 96, lst[0].Page);
  AssertEquals('next is the last cell', Ord(pikNext), Ord(lst[High(lst)].Kind));
  AssertEquals('next goes on one page', 98, lst[High(lst)].Page);

  lst := TyPaginationItems(195, 0, 1, 1, True);
  AssertTrue('prev at the first page has nowhere to go', lst[0].Page < 0);
  AssertEquals('next still does', 1, lst[High(lst)].Page);

  lst := TyPaginationItems(195, 194, 1, 1, True);
  AssertEquals('prev still does', 193, lst[0].Page);
  AssertTrue('next at the last page has nowhere to go', lst[High(lst)].Page < 0);

  // A single-page run: both arrows are there and both are inert.
  lst := TyPaginationItems(1, 0, 1, 1, True);
  AssertTrue('prev of a one-page run is inert', lst[0].Page < 0);
  AssertTrue('and so is next', lst[High(lst)].Page < 0);
end;

procedure TTyPaginationRulesTest.TestPrevNextCanBeSuppressed;
begin
  AssertEquals('a bare number strip', '1 . 97 98 99 . 195',
    Sketch(TyPaginationItems(195, 97, 1, 1, False)));
  AssertEquals('two cells fewer', Length(TyPaginationItems(195, 97, 1, 1, True)) - 2,
    Length(TyPaginationItems(195, 97, 1, 1, False)));
end;

procedure TTyPaginationRulesTest.TestSiblingCountWidensTheWindow;
begin
  // The knob is the window's half-width, and it is the only thing that decides how much of
  // the run the strip names.
  AssertEquals('no siblings: just the current page', '< 1 . 98 . 195 >',
    Sketch(TyPaginationItems(195, 97, 0, 1, True)));
  AssertEquals('one either side', '< 1 . 97 98 99 . 195 >',
    Sketch(TyPaginationItems(195, 97, 1, 1, True)));
  AssertEquals('two either side', '< 1 . 96 97 98 99 100 . 195 >',
    Sketch(TyPaginationItems(195, 97, 2, 1, True)));
end;

procedure TTyPaginationRulesTest.TestBoundaryCountKeepsMorePagesAtEachEnd;
begin
  AssertEquals('two pages at each end', '< 1 2 . 97 98 99 . 194 195 >',
    Sketch(TyPaginationItems(195, 97, 1, 2, True)));
  // ...and the head/tail blocks never name a page twice when the run is short enough for
  // them to meet.
  AssertEquals('a short run under a wide boundary is just every page', '< 1 2 3 4 >',
    Sketch(TyPaginationItems(4, 1, 1, 2, True)));
end;

procedure TTyPaginationRulesTest.TestKnobsAreClampedToASaneRule;
begin
  // BoundaryCount < 1 would hide the first and last pages behind an ellipsis with no way to
  // reach them -- the one thing a pagination must always offer. It is clamped, so 0 and a
  // negative both behave as 1.
  AssertEquals('boundary 0 behaves as 1', Sketch(TyPaginationItems(195, 97, 1, 1, True)),
    Sketch(TyPaginationItems(195, 97, 1, 0, True)));
  AssertEquals('and so does a negative one', Sketch(TyPaginationItems(195, 97, 1, 1, True)),
    Sketch(TyPaginationItems(195, 97, 1, -3, True)));
  // A negative sibling count is just no siblings, not a window that eats itself.
  AssertEquals('a negative sibling count behaves as 0',
    Sketch(TyPaginationItems(195, 97, 0, 1, True)),
    Sketch(TyPaginationItems(195, 97, -2, 1, True)));
end;

procedure TTyPaginationRulesTest.TestOutOfRangeCurrentIsClampedByTheRule;
begin
  // The rule runs TyPaginationValidIndex on its own input, so a caller that hands it a page
  // it does not have still gets a strip it can use rather than a broken one.
  AssertEquals('page 500 of 195 draws the last page', Sketch(TyPaginationItems(195, 194, 1, 1, True)),
    Sketch(TyPaginationItems(195, 500, 1, 1, True)));
  AssertEquals('and a negative draws the first', Sketch(TyPaginationItems(195, 0, 1, 1, True)),
    Sketch(TyPaginationItems(195, -9, 1, 1, True)));
end;

procedure TTyPaginationRulesTest.TestItemLabelIsOneBased;
var
  it: TTyPaginationItem;
begin
  // The whole 0-based/1-based contract lives in this one function: PageIndex 0 is drawn '1'.
  it.Kind := pikPage;
  it.Page := 0;
  AssertEquals('page index 0 is labelled 1', '1', TyPaginationItemLabel(it));
  it.Page := 194;
  AssertEquals('page index 194 is labelled 195', '195', TyPaginationItemLabel(it));
  it.Kind := pikEllipsis;
  it.Page := -1;
  AssertEquals('an ellipsis is the elision mark', TyPaginationEllipsis,
    TyPaginationItemLabel(it));
  // The arrows are glyphs, not text: no label at all (RenderTo never asks for one).
  it.Kind := pikPrev;
  AssertEquals('prev has no label', '', TyPaginationItemLabel(it));
  it.Kind := pikNext;
  AssertEquals('next has no label', '', TyPaginationItemLabel(it));
end;

procedure TTyPaginationRulesTest.TestItemVariantNamesTheKind;
begin
  // The four names a theme writes rules against, so the kinds can look different without a
  // third typeKey.
  AssertEquals('prev', TyPaginationItemVariant(pikPrev));
  AssertEquals('page', TyPaginationItemVariant(pikPage));
  AssertEquals('ellipsis', TyPaginationItemVariant(pikEllipsis));
  AssertEquals('next', TyPaginationItemVariant(pikNext));
end;

procedure TTyPaginationRulesTest.TestCellsSitInThePaddedBandAGapApart;
var
  R: TTyPaginationRects;
begin
  // 200x40, padding 5 all round, gap 4, no floor, three 30px cells.
  R := TyPaginationItemRects(200, 40, 5, 5, 5, 5, 4, 0, [30, 30, 30]);
  AssertEquals('three cells', 3, Length(R));
  AssertEquals('the run starts at the left padding', 5, R[0].Left);
  AssertEquals('and is inset from the top', 5, R[0].Top);
  AssertEquals('and from the bottom', 35, R[0].Bottom);
  AssertEquals('the first cell is its content wide', 35, R[0].Right);
  AssertEquals('the second starts a gap later', 39, R[1].Left);
  AssertEquals('and ends 30 on', 69, R[1].Right);
  AssertEquals('and so does the third', 73, R[2].Left);
  // The cells fill the whole height of the band: the chip is the cell.
  AssertEquals('cells fill the band height', 5, R[2].Top);
  AssertEquals('cells fill the band height', 35, R[2].Bottom);
end;

procedure TTyPaginationRulesTest.TestCellsAreNotEqualWidth;
var
  R: TTyPaginationRects;
begin
  // The point of taking the widths as an INPUT: '195' and '...' are wider than '1', and the
  // strip must give each cell the room its own content needs rather than a uniform slot.
  R := TyPaginationItemRects(400, 40, 0, 0, 0, 0, 4, 0, [10, 40, 25]);
  AssertEquals('a narrow cell', 10, R[0].Right - R[0].Left);
  AssertEquals('a wide one', 40, R[1].Right - R[1].Left);
  AssertEquals('and one between', 25, R[2].Right - R[2].Left);
  // ...and each one still starts exactly a gap after its neighbour's right edge.
  AssertEquals('no drift after a wide cell', R[1].Right + 4, R[2].Left);
end;

procedure TTyPaginationRulesTest.TestMinCellWidthFloorsANarrowCell;
var
  R: TTyPaginationRects;
begin
  // A single digit measures a few px and would be unaimable; the floor keeps every cell a
  // real target, and a cell wider than the floor is left alone.
  R := TyPaginationItemRects(400, 40, 0, 0, 0, 0, 4, 32, [8, 50]);
  AssertEquals('the floor wins over a tiny cell', 32, R[0].Right - R[0].Left);
  AssertEquals('a wide cell wins over the floor', 50, R[1].Right - R[1].Left);
  AssertEquals('and the gap is measured from the FLOORED width', 36, R[1].Left);
end;

procedure TTyPaginationRulesTest.TestACellThatDoesNotFitIsDroppedAndSoIsEveryLaterOne;
var
  R: TTyPaginationRects;
begin
  // A strip 100 wide, cells of 32 a gap of 4 apart: [0,32) [36,68) [72,104). The third would
  // run past the edge, so it is dropped whole rather than painted as an unreadable sliver --
  // and an empty rect is not hit-testable either, so the paint and the click agree.
  R := TyPaginationItemRects(100, 40, 0, 0, 0, 0, 4, 32, [32, 32, 32, 32]);
  AssertEquals('four cells were asked for', 4, Length(R));
  AssertEquals('the first fits', 32, R[0].Right - R[0].Left);
  AssertEquals('the second fits', 68, R[1].Right);
  AssertEquals('the third does not fit and is empty', 0, R[2].Right - R[2].Left);
  AssertEquals('and so is every cell after it', 0, R[3].Right - R[3].Left);
  // A strip exactly wide enough takes it: 104 is the fitting width, not 105.
  R := TyPaginationItemRects(104, 40, 0, 0, 0, 0, 4, 32, [32, 32, 32]);
  AssertEquals('an exactly-wide strip fits the last cell', 104, R[2].Right);
end;

procedure TTyPaginationRulesTest.TestPaddingEatsWholeStrip;
var
  R: TTyPaginationRects;
begin
  // Padding wider/taller than the strip: nothing fits -- empty rects, never inverted ones.
  R := TyPaginationItemRects(10, 40, 8, 0, 8, 0, 4, 0, [30, 30]);
  AssertEquals('padding eats the width', 0, R[0].Right - R[0].Left);
  AssertEquals('all of them', 0, R[1].Right - R[1].Left);
  R := TyPaginationItemRects(200, 10, 0, 8, 0, 8, 4, 0, [30, 30]);
  AssertEquals('padding eats the height', 0, R[0].Bottom - R[0].Top);
  AssertEquals('and nothing to hit', -1, TyPaginationIndexAt(R, 5, 5));
end;

procedure TTyPaginationRulesTest.TestZeroSizeIsEmpty;
var
  R: TTyPaginationRects;
begin
  R := TyPaginationItemRects(0, 40, 0, 0, 0, 0, 4, 32, [32, 32]);
  AssertEquals('zero width: still one rect per cell', 2, Length(R));
  AssertEquals('zero width: but nothing laid out', 0, R[0].Right - R[0].Left);
  R := TyPaginationItemRects(200, 0, 0, 0, 0, 0, 4, 32, [32, 32]);
  AssertEquals('zero height', 0, R[0].Bottom - R[0].Top);
  // A strip with no cells at all is a valid, empty answer -- not a crash.
  R := TyPaginationItemRects(200, 40, 0, 0, 0, 0, 4, 32, []);
  AssertEquals('no cells asked for, none given', 0, Length(R));
  AssertEquals('and nothing to hit', -1, TyPaginationIndexAt(R, 10, 10));
end;

procedure TTyPaginationRulesTest.TestIndexAtIsTheInverseOfItemRects;
var
  R: TTyPaginationRects;
  i: Integer;
begin
  // The contract that keeps the click and the paint honest: the centre of every painted cell
  // hit-tests back to that same cell, and so do its exact edges.
  R := TyPaginationItemRects(400, 40, 5, 5, 5, 5, 4, 32, [32, 50, 32, 40]);
  for i := 0 to High(R) do
  begin
    AssertEquals(Format('centre of cell %d', [i]), i,
      TyPaginationIndexAt(R, (R[i].Left + R[i].Right) div 2, 20));
    AssertEquals(Format('left edge of cell %d belongs to it', [i]), i,
      TyPaginationIndexAt(R, R[i].Left, 20));
    AssertEquals(Format('last px of cell %d belongs to it', [i]), i,
      TyPaginationIndexAt(R, R[i].Right - 1, 20));
  end;
end;

procedure TTyPaginationRulesTest.TestIndexAtInAGutterOrOutsideIsNone;
var
  R: TTyPaginationRects;
begin
  // Unlike TTySegmented, whose segments TILE their band, this strip has real gutters: a click
  // in one belongs to no cell and is inert rather than "the nearest one".
  R := TyPaginationItemRects(400, 40, 5, 5, 5, 5, 6, 32, [32, 32, 32]);
  AssertEquals('the gutter between two cells', -1, TyPaginationIndexAt(R, R[0].Right + 2, 20));
  AssertEquals('the strip padding on the left', -1, TyPaginationIndexAt(R, 2, 20));
  AssertEquals('the strip padding above', -1, TyPaginationIndexAt(R, R[0].Left + 2, 2));
  AssertEquals('the empty run of strip past the last cell', -1,
    TyPaginationIndexAt(R, R[2].Right + 20, 20));
  AssertEquals('outside the control entirely', -1, TyPaginationIndexAt(R, 900, 20));
  AssertEquals('above the top edge', -1, TyPaginationIndexAt(R, R[1].Left + 2, -5));
end;

procedure TTyPaginationRulesTest.TestPreferredWidthRoundTrips;
var
  w: Integer;
  R: TTyPaginationRects;
begin
  // The contract: a strip of TyPaginationPreferredWidth(...) gives every cell its natural
  // width and lands the last one exactly on the right padding.
  w := TyPaginationPreferredWidth(5, 5, 4, 32, [32, 50, 40]);
  AssertEquals('pad + cells + 2 gaps + pad', 5 + 32 + 4 + 50 + 4 + 40 + 5, w);
  R := TyPaginationItemRects(w, 40, 5, 0, 5, 0, 4, 32, [32, 50, 40]);
  AssertEquals('first cell natural', 32, R[0].Right - R[0].Left);
  AssertEquals('second cell natural', 50, R[1].Right - R[1].Left);
  AssertEquals('third cell natural', 40, R[2].Right - R[2].Left);
  AssertEquals('the last cell lands on the right padding', w - 5, R[2].Right);
  // The floor is part of the measurement, not just of the layout.
  AssertEquals('the floor widens the measurement too', 32 + 4 + 32,
    TyPaginationPreferredWidth(0, 0, 4, 32, [8, 8]));
end;

procedure TTyPaginationRulesTest.TestPreferredWidthOfAnEmptyStripIsPaddingOnly;
begin
  AssertEquals('an empty strip is just its own padding', 10,
    TyPaginationPreferredWidth(5, 5, 4, 32, []));
  // A gap goes BETWEEN cells, never around the run: one cell means no gap at all.
  AssertEquals('one cell carries no gap', 42, TyPaginationPreferredWidth(5, 5, 4, 32, [32]));
end;

procedure TTyPaginationRulesTest.TestPreferredHeightClearsTheGlyphSlot;
begin
  // A text line in its own padding, inside the strip's padding.
  AssertEquals('strip pad + (line + cell pad) + strip pad', 2 + (14 + 6 + 6) + 2,
    TyPaginationPreferredHeight(2, 2, 14, 6, 6, 12));
  // The arrow slot is centred in the CELL, so a cell shorter than the slot would squash the
  // glyph: the bare slot is the floor, not slot + padding (TTyTag's rule).
  AssertEquals('a tiny-font strip still clears its arrows', 2 + 30 + 2,
    TyPaginationPreferredHeight(2, 2, 4, 0, 0, 30));
  AssertEquals('and a tall enough cell is left alone', 2 + 26 + 2,
    TyPaginationPreferredHeight(2, 2, 14, 6, 6, 12));
end;

procedure TTyPaginationRulesTest.TestGlyphRectIsCentredAndClampedInItsCell;
var
  R: TRect;
begin
  // A 12px slot centred in a 32x32 cell at (10, 4).
  R := TyPaginationGlyphRect(Rect(10, 4, 42, 36), 12);
  AssertEquals('centred horizontally', 20, R.Left);
  AssertEquals('centred vertically', 14, R.Top);
  AssertEquals('slot is square-sized', 12, R.Right - R.Left);
  AssertEquals('and square', 12, R.Bottom - R.Top);
  // A slot bigger than its cell is squashed into it, never allowed to overflow.
  R := TyPaginationGlyphRect(Rect(10, 4, 20, 36), 30);
  AssertEquals('clamped to the cell left', 10, R.Left);
  AssertEquals('clamped to the cell right', 20, R.Right);
  // Degenerate requests answer an empty rect rather than an inverted one.
  AssertEquals('no size, no slot', 0,
    TyPaginationGlyphRect(Rect(10, 4, 42, 36), 0).Right - TyPaginationGlyphRect(Rect(10, 4, 42, 36), 0).Left);
  R := TyPaginationGlyphRect(Rect(0, 0, 0, 0), 12);
  AssertEquals('no cell, no slot', 0, R.Right - R.Left);
end;

{ TTyPaginationControlTest }

type
  { Reaches the protected paint / measure / input seams. }
  TPagAccess = class(TTyPagination)
  public
    function StyleTypeKey: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure ClickAt(X, Y: Integer);
    procedure MoveTo(X, Y: Integer);
    { True = the control consumed the key (zeroed it), so it never reaches the form. }
    function PressKey(AKey: Word): Boolean;
    { The size AutoSize would fit the strip to. Called directly rather than through AutoSize
      itself: LCL's AutoSizeDelayed suppresses every re-fit while the parent form has no
      handle (the headless runner never realises one), so driving AutoSize here would assert
      on inert plumbing instead of on this control's measurement. }
    procedure PreferredSize(out AWidth, AHeight: Integer);
  end;

function TPagAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TPagAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TPagAccess.ClickAt(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
  MouseUp(mbLeft, [], X, Y);
end;

procedure TPagAccess.MoveTo(X, Y: Integer);
begin
  MouseMove([], X, Y);
end;

function TPagAccess.PressKey(AKey: Word): Boolean;
var
  k: Word;
begin
  k := AKey;
  KeyDown(k, []);
  Result := k = 0;
end;

procedure TPagAccess.PreferredSize(out AWidth, AHeight: Integer);
begin
  AWidth := 0;
  AHeight := 0;
  CalculatePreferredSize(AWidth, AHeight, True);
end;

const
  { The pinned theme nearly every control test below runs against. Every metric this
    control reads is PINNED rather than left to its built-in fallback, and the cell floor
    (32) is wider than any page number the fallback font can measure -- so every cell comes
    out exactly 32 wide and the geometry is exact whatever font the runner happens to have.
    Cell i therefore sits at [i*36, i*36+32). }
  PinnedCss =
    ':root { --pagination-gap: 4px; --pagination-min-cell-width: 32px;' +
    ' --pagination-glyph-size: 12px; }' + LineEnding +
    'TyPagination { background: #FFFFFF; color: #111111; padding: 0px; font-size: 12px; }'
    + LineEnding +
    'TyPaginationItem { color: #111111; font-size: 12px; padding: 0px; }';

{ Build a themed, parented, 96-PPI pagination over APageCount pages showing APageIndex. }
function MakePag(AForm: TForm; ACtl: TTyStyleController;
  APageCount, APageIndex: Integer): TPagAccess;
begin
  Result := TPagAccess.Create(AForm);
  Result.Parent := AForm;
  Result.Controller := ACtl;
  Result.Font.PixelsPerInch := 96;
  Result.PageCount := APageCount;
  Result.PageIndex := APageIndex;
end;

procedure TTyPaginationControlTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FChanged := 0;
end;

procedure TTyPaginationControlTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

procedure TTyPaginationControlTest.HandleChange(Sender: TObject);
begin
  Inc(FChanged);
end;

procedure TTyPaginationControlTest.TestTypeKey;
var
  T: TPagAccess;
begin
  T := TPagAccess.Create(FForm);
  T.Parent := FForm;
  try
    AssertEquals('TyPagination', T.StyleTypeKey);
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestDefaults;
var
  T: TTyPagination;
begin
  T := TTyPagination.Create(FForm);
  try
    AssertEquals('one page by default', 1, T.PageCount);
    AssertEquals('showing it', 0, T.PageIndex);
    AssertEquals('one sibling either side', 1, T.SiblingCount);
    AssertEquals('one page at each end', 1, T.BoundaryCount);
    AssertTrue('the arrows are on', T.ShowPrevNext);
    AssertTrue('focusable: the arrow keys are the point of it', T.TabStop);
    AssertEquals('default width 320', 320, T.Width);
    AssertEquals('default height 32', 32, T.Height);
    AssertEquals('a one-page strip is prev + 1 + next', 3, T.ItemCount);
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestOutOfRangePageIndexIsClamped;
var
  T: TPagAccess;
begin
  FCtl.LoadThemeCss(PinnedCss);
  T := MakePag(FForm, FCtl, 195, 0);
  try
    T.PageIndex := 500;
    AssertEquals('past the end clamps to the last page', 194, T.PageIndex);
    T.PageIndex := -9;
    AssertEquals('and a negative to the first', 0, T.PageIndex);
    // The one case that IS "no page": there is nothing to be on.
    T.PageCount := 0;
    AssertEquals('no pages, no current page', -1, T.PageIndex);
    AssertEquals('and no cells at all, not even arrows', 0, T.ItemCount);
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestShrinkingPageCountReclampsSilently;
var
  T: TPagAccess;
begin
  FCtl.LoadThemeCss(PinnedCss);
  T := MakePag(FForm, FCtl, 195, 100);
  try
    T.OnChange := @HandleChange;
    T.PageCount := 10;   // the host re-queried and got less back
    AssertEquals('the stranded page clamps into the shorter run', 9, T.PageIndex);
    // Setting PageCount is the host's own action: it must not hand the host back a "the user
    // turned the page" event it never asked about (it reads PageIndex itself).
    AssertEquals('a run change is not a page change', 0, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestOnChangeFiresOnceForACodeSet;
var
  T: TPagAccess;
begin
  // OnChange means "the page changed", by any route -- a code set counts. This is where the
  // host re-fills its list, and it must not have to duplicate that call at every setter site.
  FCtl.LoadThemeCss(PinnedCss);
  T := MakePag(FForm, FCtl, 195, 0);
  try
    T.OnChange := @HandleChange;
    T.PageIndex := 97;
    AssertEquals('announced once', 1, FChanged);
    AssertEquals('and it took', 97, T.PageIndex);
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestReturningToTheSamePageIsSilent;
var
  T: TPagAccess;
  R: TRect;
begin
  FCtl.LoadThemeCss(PinnedCss);
  T := MakePag(FForm, FCtl, 195, 97);
  try
    T.SetBounds(0, 0, 320, 32);
    T.OnChange := @HandleChange;
    T.PageIndex := 97;
    AssertEquals('setting the same page is not a change', 0, FChanged);
    // '< 1 . 97 98 99 . 195 >' -- cell 4 is the label '98', i.e. the current PageIndex 97.
    R := T.TyPaginationCellRect(4);
    T.ClickAt((R.Left + R.Right) div 2, 16);
    AssertEquals('nor is clicking the page already current', 0, FChanged);
    AssertEquals('and it is still current', 97, T.PageIndex);
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestCellRectsFollowTheThemeGapMetric;
var
  T: TPagAccess;
begin
  // --pagination-gap is a skin-tunable metric: a theme that sets it moves the geometry (and
  // with it the hit-test), proving the gutter is not baked into the control.
  FCtl.LoadThemeCss(PinnedCss);
  T := MakePag(FForm, FCtl, 1, 0);
  try
    T.SetBounds(0, 0, 320, 32);
    AssertEquals('the first cell starts at the strip padding', 0, T.TyPaginationCellRect(0).Left);
    AssertEquals('the second starts a 4px gap on', 36, T.TyPaginationCellRect(1).Left);
    FCtl.LoadThemeCss(
      ':root { --pagination-gap: 10px; --pagination-min-cell-width: 32px; }' + LineEnding +
      'TyPagination { background: #FFFFFF; color: #111111; padding: 0px; font-size: 12px; }'
      + LineEnding +
      'TyPaginationItem { color: #111111; font-size: 12px; padding: 0px; }');
    AssertEquals('the first cell is where it was', 0, T.TyPaginationCellRect(0).Left);
    AssertEquals('the second follows the themed gap', 42, T.TyPaginationCellRect(1).Left);
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestMinCellWidthMetricRetunesTheCells;
var
  T: TPagAccess;
begin
  FCtl.LoadThemeCss(PinnedCss);
  T := MakePag(FForm, FCtl, 1, 0);
  try
    T.SetBounds(0, 0, 320, 32);
    AssertEquals('a cell takes the themed floor', 32,
      T.TyPaginationCellRect(0).Right - T.TyPaginationCellRect(0).Left);
    FCtl.LoadThemeCss(
      ':root { --pagination-gap: 4px; --pagination-min-cell-width: 48px; }' + LineEnding +
      'TyPagination { background: #FFFFFF; color: #111111; padding: 0px; font-size: 12px; }'
      + LineEnding +
      'TyPaginationItem { color: #111111; font-size: 12px; padding: 0px; }');
    AssertEquals('the theme retunes the floor', 48,
      T.TyPaginationCellRect(0).Right - T.TyPaginationCellRect(0).Left);
    AssertEquals('and the run behind it', 52, T.TyPaginationCellRect(1).Left);
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestCellAtIsTheInverseOfCellRect;
var
  T: TPagAccess;
  i: Integer;
  R: TRect;
begin
  // Through the live theme this time: what the control paints is what it hit-tests.
  FCtl.LoadThemeCss(PinnedCss);
  T := MakePag(FForm, FCtl, 195, 97);
  try
    T.SetBounds(0, 0, 320, 32);
    AssertEquals('a fully-elided strip is 9 cells', 9, T.ItemCount);
    for i := 0 to T.ItemCount - 1 do
    begin
      R := T.TyPaginationCellRect(i);
      AssertTrue(Format('cell %d fits the default width', [i]), R.Right > R.Left);
      AssertEquals(Format('centre of cell %d hits it', [i]), i,
        T.TyPaginationCellAt((R.Left + R.Right) div 2, 16));
    end;
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestClickAPageCellTurnsThePage;
var
  T: TPagAccess;
  R: TRect;
begin
  FCtl.LoadThemeCss(PinnedCss);
  T := MakePag(FForm, FCtl, 195, 97);
  try
    T.SetBounds(0, 0, 320, 32);
    T.OnChange := @HandleChange;
    // '< 1 . 97 98 99 . 195 >' -- cell 1 is page 1, cell 7 is page 195.
    R := T.TyPaginationCellRect(1);
    T.ClickAt((R.Left + R.Right) div 2, 16);
    AssertEquals('the clicked cell turns to its page', 0, T.PageIndex);
    AssertEquals('and announced once', 1, FChanged);
    // The list has changed under the click ('< 1 2 3 4 5 . 195 >'): cell 7 is now page 195.
    R := T.TyPaginationCellRect(7);
    T.ClickAt((R.Left + R.Right) div 2, 16);
    AssertEquals('and the far end is one click away', 194, T.PageIndex);
    AssertEquals('announced again', 2, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestClickPrevAndNextStepOnePage;
var
  T: TPagAccess;
  R: TRect;
begin
  FCtl.LoadThemeCss(PinnedCss);
  T := MakePag(FForm, FCtl, 195, 97);
  try
    T.SetBounds(0, 0, 320, 32);
    T.OnChange := @HandleChange;
    R := T.TyPaginationCellRect(0);            // prev
    T.ClickAt((R.Left + R.Right) div 2, 16);
    AssertEquals('prev goes back one page', 96, T.PageIndex);
    R := T.TyPaginationCellRect(T.ItemCount - 1);   // next
    T.ClickAt((R.Left + R.Right) div 2, 16);
    T.ClickAt((R.Left + R.Right) div 2, 16);
    AssertEquals('next goes on one page at a time', 98, T.PageIndex);
    AssertEquals('each step announced', 3, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestClickAnEllipsisIsInert;
var
  T: TPagAccess;
  R: TRect;
begin
  // An ellipsis stands for pages it does not name, so it has no page to go to. It carries no
  // target (Page < 0) and the one click rule -- "go to the cell's target" -- makes it inert
  // with no branch of its own.
  FCtl.LoadThemeCss(PinnedCss);
  T := MakePag(FForm, FCtl, 195, 97);
  try
    T.SetBounds(0, 0, 320, 32);
    T.OnChange := @HandleChange;
    AssertEquals('cell 2 is the leading ellipsis', Ord(pikEllipsis),
      Ord(T.TyPaginationItemList[2].Kind));
    R := T.TyPaginationCellRect(2);
    T.ClickAt((R.Left + R.Right) div 2, 16);
    AssertEquals('the page is untouched', 97, T.PageIndex);
    AssertEquals('and nothing was announced', 0, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestClickPrevAtTheFirstPageIsInert;
var
  T: TPagAccess;
  R: TRect;
begin
  FCtl.LoadThemeCss(PinnedCss);
  T := MakePag(FForm, FCtl, 195, 0);
  try
    T.SetBounds(0, 0, 320, 32);
    T.OnChange := @HandleChange;
    R := T.TyPaginationCellRect(0);
    T.ClickAt((R.Left + R.Right) div 2, 16);
    AssertEquals('prev at the first page has nowhere to go', 0, T.PageIndex);
    AssertEquals('and announces nothing', 0, FChanged);
    // The same at the other end.
    T.PageIndex := 194;
    FChanged := 0;
    R := T.TyPaginationCellRect(T.ItemCount - 1);
    T.ClickAt((R.Left + R.Right) div 2, 16);
    AssertEquals('next at the last page has nowhere to go', 194, T.PageIndex);
    AssertEquals('and announces nothing', 0, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestClickInAGutterKeepsThePage;
var
  T: TPagAccess;
begin
  // The gutter between two cells is not a cell: clicking it must not turn the page to
  // whichever one happens to be nearest.
  FCtl.LoadThemeCss(PinnedCss);
  T := MakePag(FForm, FCtl, 195, 97);
  try
    T.SetBounds(0, 0, 320, 32);
    T.OnChange := @HandleChange;
    T.ClickAt(34, 16);   // between cell 0 ([0,32)) and cell 1 ([36,68))
    AssertEquals('the page is untouched', 97, T.PageIndex);
    AssertEquals('and nothing was announced', 0, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestDisabledIgnoresAClick;
var
  T: TPagAccess;
  R: TRect;
begin
  FCtl.LoadThemeCss(PinnedCss);
  T := MakePag(FForm, FCtl, 195, 97);
  try
    T.SetBounds(0, 0, 320, 32);
    T.OnChange := @HandleChange;
    T.Enabled := False;
    R := T.TyPaginationCellRect(1);
    T.ClickAt((R.Left + R.Right) div 2, 16);
    AssertEquals('a disabled strip does not turn the page', 97, T.PageIndex);
    AssertEquals('and announces nothing', 0, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestArrowsTurnThePage;
var
  T: TPagAccess;
begin
  FCtl.LoadThemeCss(PinnedCss);
  T := MakePag(FForm, FCtl, 195, 97);
  try
    T.OnChange := @HandleChange;
    AssertTrue('Right is consumed', T.PressKey(VK_RIGHT));
    AssertEquals('Right turns on', 98, T.PageIndex);
    AssertTrue('Left is consumed', T.PressKey(VK_LEFT));
    AssertEquals('Left turns back', 97, T.PageIndex);
    AssertEquals('each turn announced', 2, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestArrowsClampAtTheEnds;
var
  T: TPagAccess;
begin
  FCtl.LoadThemeCss(PinnedCss);
  T := MakePag(FForm, FCtl, 195, 194);
  try
    T.OnChange := @HandleChange;
    T.PressKey(VK_RIGHT);
    AssertEquals('no wrap off the last page', 194, T.PageIndex);
    T.PageIndex := 0;
    FChanged := 0;
    T.PressKey(VK_LEFT);
    AssertEquals('no wrap off the first page', 0, T.PageIndex);
    AssertEquals('a blocked turn is not a change', 0, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestHomeAndEndJumpToTheEnds;
var
  T: TPagAccess;
begin
  FCtl.LoadThemeCss(PinnedCss);
  T := MakePag(FForm, FCtl, 195, 97);
  try
    AssertTrue('End is consumed', T.PressKey(VK_END));
    AssertEquals('End takes the last page', 194, T.PageIndex);
    AssertTrue('Home is consumed', T.PressKey(VK_HOME));
    AssertEquals('Home takes the first', 0, T.PageIndex);
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestDisabledLeavesKeysAlone;
var
  T: TPagAccess;
begin
  FCtl.LoadThemeCss(PinnedCss);
  T := MakePag(FForm, FCtl, 195, 97);
  try
    T.Enabled := False;
    // Not merely ignored -- NOT CONSUMED: a disabled control must let the key travel on to
    // whatever else the form would do with it.
    AssertFalse('the key is left for the form', T.PressKey(VK_RIGHT));
    AssertEquals('and the page is untouched', 97, T.PageIndex);
    T.Enabled := True;
    T.PageCount := 0;
    AssertFalse('an empty run leaves the key alone too', T.PressKey(VK_RIGHT));
    AssertEquals('still no page', -1, T.PageIndex);
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestPreferredSizeFitsTheWholeStrip;
var
  T: TPagAccess;
  w, h, i: Integer;
begin
  // With every metric pinned and the floor wider than any page number the runner's font can
  // measure, the measurement is exactly 9 cells of 32 with 8 gaps of 4 -- and feeding it back
  // in must fit every cell (the round-trip TyPaginationPreferredWidth promises).
  FCtl.LoadThemeCss(PinnedCss);
  T := MakePag(FForm, FCtl, 195, 97);
  try
    T.PreferredSize(w, h);
    AssertEquals('9 cells of 32 with 8 gaps of 4', 9 * 32 + 8 * 4, w);
    T.SetBounds(0, 0, w, h);
    for i := 0 to T.ItemCount - 1 do
      AssertTrue(Format('cell %d fits the measured strip', [i]),
        T.TyPaginationCellRect(i).Right > T.TyPaginationCellRect(i).Left);
    AssertEquals('and the last one lands on the right edge', w,
      T.TyPaginationCellRect(T.ItemCount - 1).Right);
    // A narrower run needs a narrower strip: the measurement follows the ITEM LIST.
    T.PageCount := 1;
    T.PreferredSize(w, h);
    AssertEquals('3 cells of 32 with 2 gaps of 4', 3 * 32 + 2 * 4, w);
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestGlyphSizeMetricFloorsThePreferredHeight;
var
  T: TPagAccess;
  w, smallH, bigH: Integer;
begin
  // The arrow slot is a height floor as well as a width: --pagination-glyph-size is the
  // theme's handle on it, and the same control must grow when the theme asks for a bigger
  // arrow than its text line.
  FCtl.LoadThemeCss(PinnedCss);
  T := MakePag(FForm, FCtl, 195, 97);
  try
    T.PreferredSize(w, smallH);
    FCtl.LoadThemeCss(
      ':root { --pagination-gap: 4px; --pagination-min-cell-width: 32px;' +
      ' --pagination-glyph-size: 64px; }' + LineEnding +
      'TyPagination { background: #FFFFFF; color: #111111; padding: 0px; font-size: 12px; }'
      + LineEnding +
      'TyPaginationItem { color: #111111; font-size: 12px; padding: 0px; }');
    T.PreferredSize(w, bigH);
    AssertTrue(Format('a 64px arrow needs a taller strip than %d', [smallH]),
      bigH > smallH);
    AssertEquals('and the strip clears the slot exactly', 64, bigH);
  finally
    T.Free;
  end;
end;

{ Render T into a fresh AWidth x 32 white bitmap and hand back the re-read BGRA copy. The
  caller frees the result. }
function RenderPag(T: TPagAccess; AWidth: Integer): TBGRABitmap;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(AWidth, 32);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, AWidth, 32);
    T.RenderTo(Bmp.Canvas, Rect(0, 0, AWidth, 32), 96);
    Result := TBGRABitmap.Create(Bmp);
  finally
    Bmp.Free;
  end;
end;

{ True when any pixel in ARect is strongly blue -- the #3B82F6 chip these tests theme with.
  A structural probe, not an exact-pixel one: the headless runner draws text in BGRA's own
  default font, so nothing here may depend on glyph extents. }
function HasBlueChip(R: TBGRABitmap; const ARect: TRect): Boolean;
var
  x, y: Integer;
  px: TBGRAPixel;
begin
  Result := False;
  for y := ARect.Top to ARect.Bottom - 1 do
    for x := ARect.Left to ARect.Right - 1 do
    begin
      px := R.GetPixel(x, y);
      if (px.blue > 180) and (px.red < 120) then Exit(True);
    end;
end;

procedure TTyPaginationControlTest.TestCurrentPageCellTakesTheSelectedStyle;
var
  T: TPagAccess;
  Reread: TBGRABitmap;
begin
  // The whole point of the control: the current page's cell carries tysSelected, so the
  // theme's ':selected' rule (the very state TTyButton.Down injects) paints its chip.
  FCtl.LoadThemeCss(PinnedCss + LineEnding +
    'TyPaginationItem:selected { background: #3B82F6; color: #FFFFFF; }');
  T := MakePag(FForm, FCtl, 195, 97);
  try
    T.SetBounds(0, 0, 320, 32);
    Reread := RenderPag(T, 320);
    try
      // '< 1 . 97 98 99 . 195 >' -- cell 4 is the label '98', i.e. PageIndex 97.
      AssertTrue('the current page is filled by the :selected rule',
        HasBlueChip(Reread, T.TyPaginationCellRect(4)));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestOtherPageCellsDoNotTakeIt;
var
  T: TPagAccess;
  Reread: TBGRABitmap;
begin
  // The other half of the same rule -- without this, "everything is blue" would pass above.
  FCtl.LoadThemeCss(PinnedCss + LineEnding +
    'TyPaginationItem:selected { background: #3B82F6; color: #FFFFFF; }');
  T := MakePag(FForm, FCtl, 195, 97);
  try
    T.SetBounds(0, 0, 320, 32);
    Reread := RenderPag(T, 320);
    try
      // Cells 3 and 5 are the labels '97' and '99', either side of the current '98'.
      AssertFalse('the page before it keeps the strip',
        HasBlueChip(Reread, T.TyPaginationCellRect(3)));
      AssertFalse('the page after it too',
        HasBlueChip(Reread, T.TyPaginationCellRect(5)));
      AssertFalse('and page 1 at the far end',
        HasBlueChip(Reread, T.TyPaginationCellRect(1)));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestDisabledKeepsTheCurrentPageChip;
var
  T: TPagAccess;
  Reread: TBGRABitmap;
begin
  // TTySegmented's deviation from TTyButton.Down, for the same reason: a greyed-out
  // pagination must still show WHICH page is in force -- "you cannot change this", not "no
  // page". The cascade layers :disabled over :selected, so the chip survives.
  FCtl.LoadThemeCss(PinnedCss + LineEnding +
    'TyPaginationItem:selected { background: #3B82F6; color: #FFFFFF; }' + LineEnding +
    'TyPaginationItem:disabled { color: #888888; }');
  T := MakePag(FForm, FCtl, 195, 97);
  try
    T.SetBounds(0, 0, 320, 32);
    T.Enabled := False;
    Reread := RenderPag(T, 320);
    try
      AssertTrue('a disabled strip still shows its current page',
        HasBlueChip(Reread, T.TyPaginationCellRect(4)));
      AssertFalse('and still only that one',
        HasBlueChip(Reread, T.TyPaginationCellRect(5)));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestHoveredCellTakesTheHoverStyle;
var
  T: TPagAccess;
  Reread: TBGRABitmap;
  R: TRect;
begin
  // Hover is per CELL, not per strip: the pointer lights up the one cell under it.
  FCtl.LoadThemeCss(PinnedCss + LineEnding +
    'TyPaginationItem:hover { background: #3B82F6; }');
  T := MakePag(FForm, FCtl, 195, 97);
  try
    T.SetBounds(0, 0, 320, 32);
    // Cell 5 is the label '99' -- a plain, live, non-current page cell, so nothing but the
    // :hover rule can be what fills it.
    R := T.TyPaginationCellRect(5);
    T.MoveTo((R.Left + R.Right) div 2, 16);
    Reread := RenderPag(T, 320);
    try
      AssertTrue('the hovered cell lights up', HasBlueChip(Reread, T.TyPaginationCellRect(5)));
      AssertFalse('its neighbour does not', HasBlueChip(Reread, T.TyPaginationCellRect(3)));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestInertCellsTakeTheDisabledStyle;
var
  T: TPagAccess;
  Reread: TBGRABitmap;
  R: TRect;
begin
  // An inert cell -- every ellipsis, and a prev at the first page -- reads as :disabled: the
  // state a theme already has for "you cannot click this". A hover over one must not light
  // it either, or the strip would offer an affordance it does not have.
  FCtl.LoadThemeCss(PinnedCss + LineEnding +
    'TyPaginationItem:disabled { background: #3B82F6; }' + LineEnding +
    'TyPaginationItem:hover { background: #10B981; }');
  T := MakePag(FForm, FCtl, 195, 0);
  try
    T.SetBounds(0, 0, 320, 32);
    // '< 1 2 3 4 5 . 195 >' -- cell 0 is a prev with nowhere to go, cell 6 the ellipsis.
    R := T.TyPaginationCellRect(6);
    T.MoveTo((R.Left + R.Right) div 2, 16);
    Reread := RenderPag(T, 320);
    try
      AssertTrue('prev at the first page is disabled',
        HasBlueChip(Reread, T.TyPaginationCellRect(0)));
      AssertTrue('and so is the ellipsis, even under the pointer',
        HasBlueChip(Reread, T.TyPaginationCellRect(6)));
      AssertFalse('a live page cell is not', HasBlueChip(Reread, T.TyPaginationCellRect(2)));
      AssertFalse('and next, which has somewhere to go, is not',
        HasBlueChip(Reread, T.TyPaginationCellRect(8)));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestKindVariantIsAddressableByTheTheme;
var
  T: TPagAccess;
  Reread: TBGRABitmap;
begin
  // Each cell resolves TyPaginationItem with a variant token naming its KIND, so a theme can
  // make the four look different (Ant's borderless ellipsis, for one) without this unit
  // growing a third typeKey. Only the ellipsis rule is defined here: only the ellipsis may
  // be blue.
  FCtl.LoadThemeCss(PinnedCss + LineEnding +
    'TyPaginationItem.ellipsis { background: #3B82F6; }');
  T := MakePag(FForm, FCtl, 195, 97);
  try
    T.SetBounds(0, 0, 320, 32);
    Reread := RenderPag(T, 320);
    try
      AssertTrue('the leading ellipsis takes its own variant rule',
        HasBlueChip(Reread, T.TyPaginationCellRect(2)));
      AssertTrue('and the trailing one', HasBlueChip(Reread, T.TyPaginationCellRect(6)));
      AssertFalse('a page cell does not', HasBlueChip(Reread, T.TyPaginationCellRect(3)));
      AssertFalse('nor does prev', HasBlueChip(Reread, T.TyPaginationCellRect(0)));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestUndefinedStripKeyDrawsNothing;
var
  T: TPagAccess;
  Reread: TBGRABitmap;
begin
  // A theme that gives the strip no BACKGROUND must degrade, not invent a look: nothing of
  // ours is drawn at all -- not even the cells, whose own key IS defined here.
  // The TyPagination rule below is deliberately present-but-backgroundless rather than
  // absent: the compiled-in base layer (themes/light.tycss) backs every typeKey a theme
  // omits, so "leave the rule out" would silently stop testing degradation the moment the
  // base defines TyPagination. Any user rule for a typeKey suppresses the whole base layer
  // for it (TTyStyleModel.UserHasTypeKey), so this is how you get a genuinely
  // background-less key.
  FCtl.LoadThemeCss(
    ':root { --pagination-gap: 4px; --pagination-min-cell-width: 32px; }' + LineEnding +
    'TyPagination { color: #000000; }' + LineEnding +
    'TyPaginationItem:selected { background: #3B82F6; color: #FFFFFF; }');
  T := MakePag(FForm, FCtl, 195, 97);
  try
    T.SetBounds(0, 0, 320, 32);
    Reread := RenderPag(T, 320);
    try
      AssertFalse('no strip key -> no chips anywhere',
        HasBlueChip(Reread, Rect(0, 0, 320, 32)));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTyPaginationControlTest.TestUndefinedItemKeyStillDrawsLabelsInTheStripInk;
var
  T: TPagAccess;
  Reread: TBGRABitmap;
  R: TRect;
  x, y: Integer;
  px: TBGRAPixel;
  found: Boolean;
begin
  // The other degradation half: a cell key carrying no COLOUR gets no chips (no background to
  // draw one from) but its page numbers still appear, in the STRIP's own ink.
  // White strip, GREEN ink, and a TyPaginationItem rule with neither background nor color:
  // any green pixel in a cell can only be a label that inherited the strip's colour -- never
  // a hard-coded fallback. (The item rule must be PRESENT to suppress the base layer's own
  // TyPaginationItem, which will define a colour; omitting it would inherit that instead and
  // test nothing. Same reason as TestUndefinedStripKeyDrawsNothing.)
  FCtl.LoadThemeCss(
    ':root { --pagination-gap: 4px; --pagination-min-cell-width: 32px; }' + LineEnding +
    'TyPagination { background: #FFFFFF; color: #10B981; font-size: 12px; }' + LineEnding +
    'TyPaginationItem { border-radius: 0; }');
  T := MakePag(FForm, FCtl, 195, 97);
  try
    T.SetBounds(0, 0, 320, 32);
    Reread := RenderPag(T, 320);
    try
      R := T.TyPaginationCellRect(3);   // the label '97'
      found := False;
      for y := R.Top to R.Bottom - 1 do
        for x := R.Left to R.Right - 1 do
        begin
          px := Reread.GetPixel(x, y);
          if (px.green > 120) and (px.green > px.red + 30) and (px.green > px.blue + 30) then
          begin
            found := True;
            Break;
          end;
        end;
      AssertTrue('the page number inherits the strip ink', found);
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

{ Adversarial-review finding (CONFIRMED): the cell WIDTH was measured with the cell's own
  (un-inherited) font, but the label is DRAWN with the strip-inherited font (CellTextStyle). So a
  theme that sets a font on TyPagination but not TyPaginationItem sized cells for the default 9px
  while painting at the strip's font -> clipped labels. Guard: a bigger STRIP font must widen the
  strip (it did nothing before the fix, because measurement ignored it). The empty
  TyPaginationItem rule is present so it suppresses the base layer and the cell truly inherits. }
procedure TTyPaginationControlTest.TestStripFontIsMeasuredIntoTheCells;

  function StripWidth(AStripFontPx: Integer): Integer;
  var Ctl: TTyStyleController; P: TPagAccess; w, h: Integer;
  begin
    Ctl := TTyStyleController.Create(nil);
    P := TPagAccess.Create(FForm);
    try
      Ctl.LoadThemeCss(Format(
        'TyPagination { background: #FFFFFF; color: #111; font-size: %dpx; }'
        + 'TyPaginationItem { }', [AStripFontPx]));   // empty -> suppresses base, cell inherits
      P.Parent := FForm; P.Controller := Ctl; P.Font.PixelsPerInch := 96;
      P.PageCount := 195; P.PageIndex := 100;         // multi-digit labels ('101', '195')
      P.PreferredSize(w, h);
      Result := w;
    finally P.Free; Ctl.Free; end;
  end;

var wSmall, wBig: Integer;
begin
  wSmall := StripWidth(8);
  wBig := StripWidth(24);
  // The strip font flows into the cells' measured width. Before the fix both measured at the
  // default font, so a 24px strip font produced the SAME width as an 8px one.
  AssertTrue(Format('a bigger strip font widens the strip (8px -> %d, 24px -> %d)',
    [wSmall, wBig]), wBig > wSmall);
end;

initialization
  RegisterTest(TTyPaginationRulesTest);
  RegisterTest(TTyPaginationControlTest);
end.
