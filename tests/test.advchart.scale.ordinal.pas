unit test.advchart.scale.ordinal;
{$mode objfpc}{$H+}
{ The category scale, and the band geometry that hangs off it.

  Three things here are the kind that look like details and are not.

  THE EXTENT IS INCLUSIVE. [0, 5] is six categories, not five and not a count.
  This library has already shipped an off-by-one of exactly this shape once --
  a scrollbar whose Max meant "last position" while a caller read it as
  "content size" -- and the fix was a whole afternoon, so the meaning is pinned
  by a test rather than by a comment.

  THE THREE NUMBER SPACES STAY APART. A raw category is a string, an ordinal
  number is its index, a tick number is what the extent is measured in. The last
  two are the same number today, and the tests are written against the
  conversion rather than against the coincidence.

  BAND WIDTH IS DERIVED. It used to be a settable Double that only tests ever
  wrote, which meant every assertion about it was pinning a number with no
  source. The tests below say where the number comes from. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry,
     tyControls.AdvChart.Types, tyControls.AdvChart.Data,
     tyControls.AdvChart.Scale, tyControls.AdvChart.Coord;
type
  TAdvChartOrdinalScaleTest = class(TTestCase)
  private
    FMeta: TTyOrdinalMeta;
    FScale: TTyOrdinalScale;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Given(const A: array of string);
  published
    { ---- the extent ---- }
    procedure TestExtentIsInclusiveNotACount;
    procedure TestNoCategoriesIsBlankNotAReversedExtent;
    procedure TestOneCategoryIsOneBand;
    procedure TestNarrowingTheExtentDoesNotDropCategories;
    { ---- parsing ---- }
    procedure TestANameBecomesItsIndex;
    procedure TestAnUnknownNameIsNotAGuess;
    procedure TestANumericStringIsNotAnIndex;
    procedure TestANumberIsAlreadyAnOrdinal;
    procedure TestRoundingIsJavaScriptsNotBankers;
    { ---- mapping ---- }
    procedure TestNormalizeSpreadsAcrossTheExtent;
    procedure TestOneCategoryNormalizesToTheMiddle;
    procedure TestDenormalizeSnapsToAWholeCategory;
    procedure TestContainRejectsOutsideTheCategoryList;
    procedure TestContainRejectsEverythingWhenBlank;
    { ---- ticks and labels ---- }
    procedure TestOneTickPerCategory;
    procedure TestBlankYieldsNoTicks;
    procedure TestLabelsComeBackInOrder;
    procedure TestALabelOutOfRangeIsEmpty;
    procedure TestAScaleWithNoListAtAllIsSafe;
    { ---- band geometry on an axis ---- }
    procedure TestBandWidthIsSpanOverCount;
    procedure TestBandWidthWithoutBandingIsSpanOverGaps;
    procedure TestAValueAxisHasNoBands;
    procedure TestBandingCannotBeTurnedOnForAValueAxis;
    procedure TestCategoriesSitAtBandCentres;
    procedure TestBandCentresSurviveAVerticalAxis;
    procedure TestBandRoundTripsThroughPixels;
    procedure TestBandWidthFollowsAResize;
    procedure TestWithoutBandingCategoriesSitOnTheEnds;
    procedure TestABlankCategoryAxisHasNoBand;
    procedure TestAxesDoNotLeakTheirCategoryLists;
    { ---- tick marks, which are not where the labels are ---- }
    procedure TestTicksSitOnBandEdgesAndOutnumberTheLabels;
    procedure TestAlignWithLabelPutsTicksOnTheCentres;
    procedure TestWithoutBandingTicksAndLabelsCoincide;
    procedure TestTicksFollowTheAxisDirection;
    procedure TestTheAppendedTickHasNoLabel;
    procedure TestABlankAxisHasNoTicks;
    procedure TestNormalizedCoordAgreesWithDataToCoord;
  end;
implementation

procedure TAdvChartOrdinalScaleTest.SetUp;
begin
  inherited SetUp;
  FMeta := TTyOrdinalMeta.Create;
  FScale := TTyOrdinalScale.Create;
  FScale.SetMeta(FMeta);
end;

procedure TAdvChartOrdinalScaleTest.TearDown;
begin
  { The scale BORROWS the meta, so the meta is freed here and not by the scale.
    A double free would show up as a heap error on the next test, not on this
    one, which is why the borrow is worth a test of its own in the data suite. }
  FreeAndNil(FScale);
  FreeAndNil(FMeta);
  inherited TearDown;
end;

procedure TAdvChartOrdinalScaleTest.Given(const A: array of string);
begin
  FMeta.SetCategories(A);
  FScale.SetExtentFromCategories;
end;

{ ============================ the extent ============================ }

procedure TAdvChartOrdinalScaleTest.TestExtentIsInclusiveNotACount;
var e: TTyRange;
begin
  Given(['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']);
  e := FScale.GetExtent;
  AssertEquals('starts at the first index', 0, e.Start, 0);
  AssertEquals('and ENDS at the last one, not past it', 5, e.Stop, 0);
  AssertEquals('so six categories', 6, FScale.Count);
  AssertEquals('and the list agrees', 6, FScale.CategoryCount);
end;

procedure TAdvChartOrdinalScaleTest.TestNoCategoriesIsBlankNotAReversedExtent;
begin
  { The obvious extent for zero categories is [0, -1], and it is a trap:
    TyRange normalises a reversed pair, so it would come back as [-1, 0] and
    Count would answer two categories where there are none. }
  Given([]);
  AssertTrue('blank', FScale.Blank);
  AssertEquals('no categories', 0, FScale.Count);
  { Asserting merely "not reversed" was too weak -- [-1, 0] passes that and is
    exactly the wrong answer the special case exists to avoid. The extent has
    to be the harmless point. }
  AssertEquals('extent start', 0, FScale.GetExtent.Start, 0);
  AssertEquals('extent stop', 0, FScale.GetExtent.Stop, 0);
end;

procedure TAdvChartOrdinalScaleTest.TestOneCategoryIsOneBand;
begin
  Given(['only']);
  AssertFalse('not blank', FScale.Blank);
  AssertEquals('one category', 1, FScale.Count);
  AssertEquals('and its extent is a point', 0, FScale.GetExtent.Stop - FScale.GetExtent.Start, 0);
end;

procedure TAdvChartOrdinalScaleTest.TestNarrowingTheExtentDoesNotDropCategories;
begin
  { Count and CategoryCount stop agreeing the moment a min/max or a dataZoom
    narrows the window, and they are not interchangeable: Contain tests against
    the list, band width divides by the window. }
  Given(['a', 'b', 'c', 'd', 'e']);
  FScale.SetExtent(TyRange(1, 3));
  AssertEquals('three on screen', 3, FScale.Count);
  AssertEquals('five in the list', 5, FScale.CategoryCount);
  AssertFalse('and it is not blank', FScale.Blank);
end;

{ ============================ parsing ============================ }

procedure TAdvChartOrdinalScaleTest.TestANameBecomesItsIndex;
begin
  Given(['Mon', 'Tue', 'Wed']);
  AssertEquals(0, FScale.ParseText('Mon'), 0);
  AssertEquals(2, FScale.ParseText('Wed'), 0);
end;

procedure TAdvChartOrdinalScaleTest.TestAnUnknownNameIsNotAGuess;
begin
  Given(['Mon', 'Tue']);
  AssertTrue('a name off the axis is no data', IsNan(FScale.ParseText('Sun')));
  AssertTrue('and so is anything on a blank scale', IsNan(TTyOrdinalScale.Create.ParseText('x')));
end;

procedure TAdvChartOrdinalScaleTest.TestANumericStringIsNotAnIndex;
begin
  { '3' against ['a','b','c','d'] names no category. Falling back to the number
    would quietly plot a point on a category nobody wrote, and the failure is
    invisible: the chart looks fine and the bar is on the wrong day. }
  Given(['a', 'b', 'c', 'd']);
  AssertTrue(IsNan(FScale.ParseText('3')));
end;

procedure TAdvChartOrdinalScaleTest.TestANumberIsAlreadyAnOrdinal;
begin
  Given(['a', 'b', 'c', 'd']);
  AssertEquals(3, FScale.ParseNumber(3), 0);
  AssertEquals('snapped', 4, FScale.ParseNumber(3.7), 0);
end;

procedure TAdvChartOrdinalScaleTest.TestRoundingIsJavaScriptsNotBankers;
begin
  { FPC's Round is banker's: Round(2.5) is 2 and Round(1.5) is 2. Using it here
    would snap every other band boundary to the wrong category, and only on the
    halves -- which is exactly the kind of bug that survives a test suite that
    only ever uses whole numbers. }
  AssertEquals('2.5 goes up', 3, TyJsRound(2.5), 0);
  AssertEquals('1.5 goes up too', 2, TyJsRound(1.5), 0);
  AssertEquals('and 0.5', 1, TyJsRound(0.5), 0);
  AssertEquals('negative halves go toward zero', 0, TyJsRound(-0.5), 0);
  AssertEquals('-1.5 gives -1', -1, TyJsRound(-1.5), 0);
  AssertTrue('NaN survives', IsNan(TyJsRound(NaN)));
end;

{ ============================ mapping ============================ }

procedure TAdvChartOrdinalScaleTest.TestNormalizeSpreadsAcrossTheExtent;
begin
  Given(['a', 'b', 'c', 'd', 'e']);   { extent [0,4] }
  AssertEquals(0.0, FScale.Normalize(0), 1e-9);
  AssertEquals(0.5, FScale.Normalize(2), 1e-9);
  AssertEquals(1.0, FScale.Normalize(4), 1e-9);
end;

procedure TAdvChartOrdinalScaleTest.TestOneCategoryNormalizesToTheMiddle;
begin
  { A zero-width extent cannot spread anything, so everything lands dead centre
    rather than dividing by zero. }
  Given(['only']);
  AssertEquals(0.5, FScale.Normalize(0), 1e-9);
end;

procedure TAdvChartOrdinalScaleTest.TestDenormalizeSnapsToAWholeCategory;
begin
  { The snap is why dragging a window over a category axis lands on categories
    instead of between them. }
  Given(['a', 'b', 'c', 'd', 'e']);
  AssertEquals(2, FScale.Denormalize(0.5), 0);
  AssertEquals('just past halfway is still c', 2, FScale.Denormalize(0.52), 0);
  AssertEquals('and well past it is d', 3, FScale.Denormalize(0.7), 0);
end;

procedure TAdvChartOrdinalScaleTest.TestContainRejectsOutsideTheCategoryList;
begin
  Given(['a', 'b', 'c']);
  AssertTrue(FScale.Contain(0));
  AssertTrue(FScale.Contain(2));
  AssertFalse('past the end', FScale.Contain(3));
  AssertFalse('before the start', FScale.Contain(-1));
  AssertFalse('no data', FScale.Contain(NaN));
end;

procedure TAdvChartOrdinalScaleTest.TestContainRejectsEverythingWhenBlank;
begin
  Given([]);
  AssertFalse(FScale.Contain(0));
end;

{ ============================ ticks and labels ============================ }

procedure TAdvChartOrdinalScaleTest.TestOneTickPerCategory;
var t: TTyScaleTickArray;
begin
  Given(['a', 'b', 'c', 'd']);
  t := FScale.GetTicks;
  AssertEquals('one each', 4, Length(t));
  AssertEquals(0, t[0].Value, 0);
  AssertEquals(3, t[3].Value, 0);
  AssertEquals('all major', 0, t[2].Level);
end;

procedure TAdvChartOrdinalScaleTest.TestBlankYieldsNoTicks;
begin
  { ECharts emits one junk tick from a blank ordinal scale. Copying that would
    put a labelled tick on an axis with nothing on it. }
  Given([]);
  AssertEquals(0, Length(FScale.GetTicks));
end;

procedure TAdvChartOrdinalScaleTest.TestLabelsComeBackInOrder;
begin
  Given(['Mon', 'Tue', 'Wed']);
  AssertEquals('Mon', FScale.GetLabel(0));
  AssertEquals('Wed', FScale.GetLabel(2));
end;

procedure TAdvChartOrdinalScaleTest.TestALabelOutOfRangeIsEmpty;
begin
  Given(['Mon']);
  AssertEquals('', FScale.GetLabel(5));
  AssertEquals('', FScale.GetLabel(-1));
  Given([]);
  AssertEquals('blank', '', FScale.GetLabel(0));
end;

procedure TAdvChartOrdinalScaleTest.TestAScaleWithNoListAtAllIsSafe;
var sc: TTyOrdinalScale;
begin
  { A scale built and never given a list. Every read has to answer rather than
    crash: this is the state an axis is in between construction and the option
    being read, and a design-time editor renders in exactly that window. }
  sc := TTyOrdinalScale.Create;
  try
    AssertTrue('blank', sc.Blank);
    AssertEquals('no categories', 0, sc.CategoryCount);
    AssertEquals('no label', '', sc.GetLabel(0));
    AssertEquals('no ticks', 0, Length(sc.GetTicks));
    AssertTrue('nothing parses', IsNan(sc.ParseText('a')));
    AssertFalse('and nothing is contained', sc.Contain(0));
  finally
    sc.Free;
  end;
end;

{ ====================== band geometry on an axis ====================== }

procedure TAdvChartOrdinalScaleTest.TestBandWidthIsSpanOverCount;
var ax: TTyAxis;
begin
  { Three categories over 300px, banded: three bands of 100. The extent SPAN is
    2 and the count is 3 -- the +1 is the whole difference between banding and
    not, and getting it wrong is a chart whose last bar hangs off the edge. }
  ax := TTyAxis.Create('x', TTyOrdinalScale.Create, True);
  try
    ax.SetCategories(['a', 'b', 'c']);
    ax.OnBand := True;
    ax.SetPxExtent(0, 300);
    AssertEquals(100.0, ax.BandWidth, 1e-9);
  finally
    ax.Free;
  end;
end;

procedure TAdvChartOrdinalScaleTest.TestBandWidthWithoutBandingIsSpanOverGaps;
var ax: TTyAxis;
begin
  { boundaryGap false: the categories sit ON the ends, so three of them make
    two gaps of 150 rather than three bands of 100. }
  ax := TTyAxis.Create('x', TTyOrdinalScale.Create, True);
  try
    ax.SetCategories(['a', 'b', 'c']);
    ax.OnBand := False;
    ax.SetPxExtent(0, 300);
    AssertEquals(150.0, ax.BandWidth, 1e-9);
  finally
    ax.Free;
  end;
end;

procedure TAdvChartOrdinalScaleTest.TestAValueAxisHasNoBands;
var ax: TTyAxis; sc: TTyIntervalScale;
begin
  { 0 means NOT BANDED, and a cell then collapses onto its anchor. A number
    here would be a fiction -- there is nothing on an interval scale for a band
    width to be derived from. }
  sc := TTyIntervalScale.Create;
  sc.SetExtent(TyRange(0, 10));
  ax := TTyAxis.Create('y', sc, False);
  try
    ax.SetPxExtent(0, 300);
    AssertEquals(0.0, ax.BandWidth, 0);
  finally
    ax.Free;
  end;
end;

procedure TAdvChartOrdinalScaleTest.TestBandingCannotBeTurnedOnForAValueAxis;
var ax: TTyAxis; sc: TTyIntervalScale;
begin
  { A value axis' boundaryGap is a PAIR OF PERCENTAGES, not a boolean, so an
    ungated setter would band every value axis in the chart the moment anyone
    wired boundaryGap through. }
  sc := TTyIntervalScale.Create;
  sc.SetExtent(TyRange(0, 10));
  ax := TTyAxis.Create('y', sc, False);
  try
    ax.OnBand := True;
    AssertFalse('refused', ax.OnBand);
  finally
    ax.Free;
  end;
end;

procedure TAdvChartOrdinalScaleTest.TestCategoriesSitAtBandCentres;
var ax: TTyAxis;
begin
  { Three categories over 300px land at 50, 150, 250 -- the CENTRES of their
    bands, not the edges. The half-band inset is applied to the pixel extent,
    never to the value: ordinal 0 stays ordinal 0. }
  ax := TTyAxis.Create('x', TTyOrdinalScale.Create, True);
  try
    ax.SetCategories(['a', 'b', 'c']);
    ax.OnBand := True;
    ax.SetPxExtent(0, 300);
    AssertEquals(50.0, ax.DataToCoord(0), 1e-9);
    AssertEquals(150.0, ax.DataToCoord(1), 1e-9);
    AssertEquals(250.0, ax.DataToCoord(2), 1e-9);
  finally
    ax.Free;
  end;
end;

procedure TAdvChartOrdinalScaleTest.TestBandCentresSurviveAVerticalAxis;
var ax: TTyAxis;
begin
  { A vertical axis runs bottom-up, so its pixel stop is ABOVE its start and the
    half-band margin comes out negative. Both ends must still move inward. An
    Abs in the inset would look right on every horizontal test here and be
    wrong on every vertical one -- which is why this test exists at all. }
  ax := TTyAxis.Create('y', TTyOrdinalScale.Create, False);
  try
    ax.SetCategories(['a', 'b', 'c']);
    ax.OnBand := True;
    ax.SetPxExtent(300, 0);
    AssertEquals('first category nearest the bottom', 250.0, ax.DataToCoord(0), 1e-9);
    AssertEquals(150.0, ax.DataToCoord(1), 1e-9);
    AssertEquals(50.0, ax.DataToCoord(2), 1e-9);
    AssertEquals('and the band is still 100 wide', 100.0, ax.BandWidth, 1e-9);
  finally
    ax.Free;
  end;
end;

procedure TAdvChartOrdinalScaleTest.TestBandRoundTripsThroughPixels;
var ax: TTyAxis; i: Integer;
begin
  ax := TTyAxis.Create('x', TTyOrdinalScale.Create, True);
  try
    ax.SetCategories(['a', 'b', 'c', 'd', 'e']);
    ax.OnBand := True;
    ax.SetPxExtent(20, 520);
    for i := 0 to 4 do
      AssertEquals('category ' + IntToStr(i) + ' survives the round trip',
        i, ax.CoordToData(ax.DataToCoord(i)), 0);
  finally
    ax.Free;
  end;
end;

procedure TAdvChartOrdinalScaleTest.TestBandWidthFollowsAResize;
var ax: TTyAxis;
begin
  { Derived, not stored, and this is why: the pixel extent is written twice per
    layout pass -- an approximate one off the raw rect, then the final one off
    the shrunk plot rect. A width cached at construction is stale by the second
    write, and every bar in the chart is then the wrong width. }
  ax := TTyAxis.Create('x', TTyOrdinalScale.Create, True);
  try
    ax.SetCategories(['a', 'b', 'c', 'd']);
    ax.OnBand := True;
    ax.SetPxExtent(0, 400);
    AssertEquals(100.0, ax.BandWidth, 1e-9);
    ax.SetPxExtent(0, 200);
    AssertEquals('follows the shrink', 50.0, ax.BandWidth, 1e-9);
  finally
    ax.Free;
  end;
end;

procedure TAdvChartOrdinalScaleTest.TestWithoutBandingCategoriesSitOnTheEnds;
var ax: TTyAxis;
begin
  { boundaryGap false. The half-band inset must NOT apply -- the first category
    sits exactly on the axis' start and the last exactly on its stop, which is
    the whole visual difference between a line chart and a bar chart on the
    same category axis. }
  ax := TTyAxis.Create('x', TTyOrdinalScale.Create, True);
  try
    ax.SetCategories(['a', 'b', 'c']);
    ax.OnBand := False;
    ax.SetPxExtent(0, 300);
    AssertEquals('first is on the start', 0.0, ax.DataToCoord(0), 1e-9);
    AssertEquals(150.0, ax.DataToCoord(1), 1e-9);
    AssertEquals('last is on the stop', 300.0, ax.DataToCoord(2), 1e-9);
  finally
    ax.Free;
  end;
end;

procedure TAdvChartOrdinalScaleTest.TestABlankCategoryAxisHasNoBand;
var ax: TTyAxis;
begin
  { A category axis whose option supplied no data. Without the blank guard the
    span is zero, the +1 makes the divisor one, and the axis reports a band as
    wide as itself -- so a single bar would be drawn across the whole plot. }
  ax := TTyAxis.Create('x', TTyOrdinalScale.Create, True);
  try
    ax.OnBand := True;
    ax.SetPxExtent(0, 300);
    AssertEquals(0.0, ax.BandWidth, 0);
  finally
    ax.Free;
  end;
end;

procedure TAdvChartOrdinalScaleTest.TestAxesDoNotLeakTheirCategoryLists;
var
  before, after: PtrUInt;
  i, r: Integer;
  ax: TTyAxis;
begin
  { The axis OWNS its list, and a leak here is silent: every setOption builds a
    fresh set of axes, so it grows with use rather than showing up once. }
  for r := 0 to 2 do
  begin
    ax := TTyAxis.Create('x', TTyOrdinalScale.Create, True);
    ax.SetCategories(['a', 'b', 'c']);
    ax.Free;
  end;
  before := GetFPCHeapStatus.CurrHeapUsed;
  for i := 0 to 199 do
  begin
    ax := TTyAxis.Create('x', TTyOrdinalScale.Create, True);
    ax.SetCategories(['a', 'b', 'c', 'd', 'e']);
    ax.Free;
  end;
  after := GetFPCHeapStatus.CurrHeapUsed;
  AssertTrue(Format('heap grew from %d to %d over two hundred axes', [before, after]),
    after <= before);
end;

procedure TAdvChartOrdinalScaleTest.TestTicksSitOnBandEdgesAndOutnumberTheLabels;
var ax: TTyAxis; c: TTyDoubleArray;
begin
  { THE DEFAULT, and the one most likely to be got wrong: a label belongs to a
    category so it sits on the band's centre, while a tick SEPARATES two
    categories so it sits on the edge. Three categories therefore have three
    labels and FOUR ticks. A test asserting one tick per category is asserting
    the wrong thing. }
  ax := TTyAxis.Create('x', TTyOrdinalScale.Create, True);
  try
    ax.SetCategories(['a', 'b', 'c']);
    ax.OnBand := True;
    ax.SetPxExtent(0, 300);
    c := ax.TickCoords;
    AssertEquals('one more tick than categories', 4, Length(c));
    AssertEquals(0.0, c[0], 1e-9);
    AssertEquals(100.0, c[1], 1e-9);
    AssertEquals(200.0, c[2], 1e-9);
    AssertEquals(300.0, c[3], 1e-9);
    AssertEquals('while the labels are on the centres', 50.0, ax.DataToCoord(0), 1e-9);
  finally
    ax.Free;
  end;
end;

procedure TAdvChartOrdinalScaleTest.TestAlignWithLabelPutsTicksOnTheCentres;
var ax: TTyAxis; c: TTyDoubleArray;
begin
  ax := TTyAxis.Create('x', TTyOrdinalScale.Create, True);
  try
    ax.SetCategories(['a', 'b', 'c']);
    ax.OnBand := True;
    ax.SetPxExtent(0, 300);
    c := ax.TickCoords(True);
    AssertEquals('one each now', 3, Length(c));
    AssertEquals(50.0, c[0], 1e-9);
    AssertEquals(150.0, c[1], 1e-9);
    AssertEquals(250.0, c[2], 1e-9);
  finally
    ax.Free;
  end;
end;

procedure TAdvChartOrdinalScaleTest.TestWithoutBandingTicksAndLabelsCoincide;
var ax: TTyAxis; c: TTyDoubleArray;
begin
  { boundaryGap false: the categories already sit on the ends, so there is no
    edge distinct from the centre and alignWithLabel has nothing to change. }
  ax := TTyAxis.Create('x', TTyOrdinalScale.Create, True);
  try
    ax.SetCategories(['a', 'b', 'c']);
    ax.OnBand := False;
    ax.SetPxExtent(0, 300);
    c := ax.TickCoords;
    AssertEquals(3, Length(c));
    AssertEquals(0.0, c[0], 1e-9);
    AssertEquals(300.0, c[2], 1e-9);
    c := ax.TickCoords(True);
    AssertEquals('and aligning changes nothing', 3, Length(c));
    AssertEquals(0.0, c[0], 1e-9);
  finally
    ax.Free;
  end;
end;

procedure TAdvChartOrdinalScaleTest.TestTicksFollowTheAxisDirection;
var ax: TTyAxis; c: TTyDoubleArray;
begin
  { A vertical axis runs bottom-up, so the half-band shift has to go the other
    way. A bare subtraction would push every tick off the wrong end -- and it
    would pass every horizontal test in this file. }
  ax := TTyAxis.Create('y', TTyOrdinalScale.Create, False);
  try
    ax.SetCategories(['a', 'b', 'c']);
    ax.OnBand := True;
    ax.SetPxExtent(300, 0);
    c := ax.TickCoords;
    AssertEquals(4, Length(c));
    AssertEquals('the first edge is at the bottom', 300.0, c[0], 1e-9);
    AssertEquals(200.0, c[1], 1e-9);
    AssertEquals(100.0, c[2], 1e-9);
    AssertEquals('and the last at the top', 0.0, c[3], 1e-9);
  finally
    ax.Free;
  end;
end;

procedure TAdvChartOrdinalScaleTest.TestTheAppendedTickHasNoLabel;
var ax: TTyAxis;
begin
  { The extra tick is GEOMETRY -- the trailing edge of the last band -- not a
    category. Giving it a label would put a fourth name on a three-name axis. }
  ax := TTyAxis.Create('x', TTyOrdinalScale.Create, True);
  try
    ax.SetCategories(['a', 'b', 'c']);
    ax.OnBand := True;
    ax.SetPxExtent(0, 300);
    AssertEquals(4, Length(ax.TickCoords));
    AssertEquals('three labels', 3, Length(ax.Scale.GetTicks));
    AssertEquals('and nothing past the end', '', TTyOrdinalScale(ax.Scale).GetLabel(3));
  finally
    ax.Free;
  end;
end;

procedure TAdvChartOrdinalScaleTest.TestABlankAxisHasNoTicks;
var ax: TTyAxis;
begin
  ax := TTyAxis.Create('x', TTyOrdinalScale.Create, True);
  try
    ax.OnBand := True;
    ax.SetPxExtent(0, 300);
    AssertEquals('not one, and not a phantom edge', 0, Length(ax.TickCoords));
    AssertEquals(0, Length(ax.TickCoords(True)));
  finally
    ax.Free;
  end;
end;

procedure TAdvChartOrdinalScaleTest.TestNormalizedCoordAgreesWithDataToCoord;
var ax: TTyAxis; i: Integer; a, b: Double;
begin
  { The layout layer wants fractions and the renderer wants pixels. If they are
    computed independently they drift -- and the drift is exactly half a band,
    which looks like a rounding error rather than a missing rule. }
  ax := TTyAxis.Create('x', TTyOrdinalScale.Create, True);
  try
    ax.SetCategories(['a', 'b', 'c', 'd']);
    ax.OnBand := True;
    ax.SetPxExtent(100, 500);
    for i := 0 to 3 do
    begin
      a := ax.NormalizedCoord(i);
      b := ax.DataToCoord(i);
      AssertEquals('fraction ' + IntToStr(i) + ' maps back to the same pixel',
        b, 150 + a * (450 - 150), 1e-9);
    end;
  finally
    ax.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartOrdinalScaleTest);
end.
