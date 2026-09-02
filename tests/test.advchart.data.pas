unit test.advchart.data;
{$mode objfpc}{$H+}
{ The columnar data store.

  Three things below are load-bearing far past this unit and are worth naming
  before the tests start.

  NaN IS THE ONLY SPELLING OF "NO DATA". Not zero, not a magic number, not a
  parallel Has array. Every dimension type stores Double for exactly this
  reason, so the tests check the gap case on all four rather than only on float.

  A FILTER KEEPS NaN. It is the one predicate result that looks wrong and is
  right: a line chart draws a gap where a value is missing, and dropping the row
  would close the gap and draw a line straight through it.

  TWO INDEX SPACES STAY DISTINGUISHABLE. dataZoom moves the data index while the
  raw index stands still, and the v6.1 callback record promises both. A test
  that only ever looks at an unfiltered store cannot tell them apart, so the
  round-trip is checked through a filter. }
interface
uses Classes, SysUtils, Math, DateUtils, fpcunit, testregistry,
     tyControls.AdvChart.Data;
type
  TAdvChartDataTest = class(TTestCase)
  private
    FS: TTyDataStore;
    FEven: Boolean;
    procedure SetUp; override;
    procedure TearDown; override;
    { predicates for FilterSelf }
    function KeepEven(ARawIndex: Integer): Boolean;
    function KeepNone(ARawIndex: Integer): Boolean;
    { a float,float store filled with ARows rows of (i, i*10) }
    procedure FillLinear(ARows: Integer);
  published
    { ---- value parsing ---- }
    procedure TestAbsentValueIsNotAZero;
    procedure TestEmptyAndDashTextAreNoData;
    procedure TestNumericTextIsTrimmedAndParsed;
    procedure TestTextIsParsedWithAFixedDecimalPoint;
    procedure TestIntTruncatesTowardZero;
    procedure TestBooleanCountsAsOneOrZero;
    procedure TestOrdinalIsNotParsedByTheValueParser;
    { ---- time ---- }
    procedure TestTimeAcceptsTheEChartsSubset;
    procedure TestTimeFractionIsPaddedNotTruncated;
    procedure TestTimeZoneDesignatorsAreApplied;
    procedure TestTimeWithoutAZoneIsLocal;
    procedure TestTimeRejectsImpossibleComponents;
    procedure TestTimeRejectsTrailingJunk;
    procedure TestTimeNumberIsAlreadyEpochMs;
    procedure TestTimeRoundTripsThroughTDateTime;
    { ---- schema ---- }
    procedure TestDimensionsAreNamedAndTyped;
    procedure TestUnknownDimensionAnswersSafely;
    procedure TestADimensionAddedAfterFillingHasNoData;
    { ---- filling ---- }
    procedure TestAShortRowLeavesTheRestNoData;
    procedure TestGrowthKeepsEveryValue;
    procedure TestAppendingWhileFilteredIsRefused;
    { ---- ordinal ---- }
    procedure TestCollectingBuildsTheCategoryList;
    procedure TestFixedCategoriesTurnUnknownIntoAGap;
    procedure TestANumberOnAFixedAxisIsACategoryIndex;
    procedure TestANumberOnACollectingAxisIsALabel;
    procedure TestDashAndEmptyAreRealCategories;
    procedure TestAbsentIsStillAGapOnAnOrdinal;
    procedure TestNaNIsNotACategoryCalledNan;
    procedure TestDeduplicationOffAppendsBlind;
    procedure TestCategoriesMustBeSetBeforeFilling;
    procedure TestCategoriesNeedAnOrdinalDimension;
    { ---- a borrowed category list ---- }
    procedure TestTwoStoresSharingOneListAgreeOnOrdinals;
    procedure TestABorrowedListIsNotFreedByTheStore;
    procedure TestClearDoesNotWipeABorrowedList;
    procedure TestABorrowedListCannotBeOverwrittenBySeriesData;
    procedure TestBorrowingAfterFillingIsRefused;
    { ---- identity ---- }
    procedure TestIdAndNameAreOnlyAllocatedWhenUsed;
    procedure TestIdAndNameFollowTheRawRow;
    { ---- overrides ---- }
    procedure TestAnOverrideOfZeroIsNotAbsence;
    procedure TestOverridesAreSparse;
    procedure TestSettingTheSameKeyTwiceReplaces;
    procedure TestOverridesFollowTheRawRowThroughAFilter;
    procedure TestOverrideKeysAreInterned;
    { ---- extent ---- }
    procedure TestExtentIgnoresGaps;
    procedure TestAllGapsHasNoExtent;
    procedure TestExtentIgnoresInfinity;
    procedure TestPositiveOnlyExtentIsForTheLogAxis;
    procedure TestExtentFollowsTheFilter;
    procedure TestExtentIsInvalidatedByAnAppend;
    procedure TestExtentCacheDoesNotOutliveItsWindow;
    procedure TestTheTwoExtentFiltersCacheApart;
    { ---- index spaces ---- }
    procedure TestRawIndexIsIdentityUntilFiltered;
    procedure TestRawIndexRoundTripsThroughAFilter;
    procedure TestAFilteredOutRowHasNoDataIndex;
    procedure TestOutOfRangeIndicesAnswerMinusOne;
    { ---- filtering ---- }
    procedure TestSelectRangeKeepsGaps;
    procedure TestSelectRangeTestsEveryGivenDimension;
    procedure TestFiltersCompose;
    procedure TestRestoreAllUndoesEverything;
    procedure TestAFilterThatKeepsNothingIsStillAFilter;
    procedure TestFilterSelfCarriesItsOwnState;
    { ---- inverted index ---- }
    procedure TestInvertedIndexFindsTheRowForACategory;
    procedure TestInvertedIndexIsUnaffectedByFiltering;
    procedure TestInvertedIndexNeedsBuilding;
    procedure TestInvertedIndexNeedsAnOrdinalDimension;
    { ---- clear ---- }
    procedure TestClearKeepsTheSchema;
    procedure TestClearForgetsCollectedButKeepsFixedCategories;
    procedure TestRepeatedRefillDoesNotGrowTheHeap;
  end;
implementation

procedure TAdvChartDataTest.SetUp;
begin
  inherited SetUp;
  FS := TTyDataStore.Create;
end;

procedure TAdvChartDataTest.TearDown;
begin
  FreeAndNil(FS);
  inherited TearDown;
end;

function TAdvChartDataTest.KeepEven(ARawIndex: Integer): Boolean;
begin
  Result := (ARawIndex mod 2 = 0) = FEven;
end;

function TAdvChartDataTest.KeepNone(ARawIndex: Integer): Boolean;
begin
  Result := False;
end;

procedure TAdvChartDataTest.FillLinear(ARows: Integer);
var i: Integer;
begin
  FS.AddDimension('x', ddtFloat);
  FS.AddDimension('y', ddtFloat);
  for i := 0 to ARows - 1 do
    FS.AppendRow([i * 1.0, i * 10.0]);
end;

{ ============================ value parsing ============================ }

procedure TAdvChartDataTest.TestAbsentValueIsNotAZero;
begin
  { The whole no-data contract in one line: a missing value must not be a
    number, on any of the four dimension types. }
  AssertTrue('float', IsNan(TyParseDataValue(TyDataNone, ddtFloat)));
  AssertTrue('int', IsNan(TyParseDataValue(TyDataNone, ddtInt)));
  AssertTrue('time', IsNan(TyParseDataValue(TyDataNone, ddtTime)));
end;

procedure TAdvChartDataTest.TestEmptyAndDashTextAreNoData;
begin
  { ECharts documents '-' as the way to write a gap in data. It needs no rule of
    its own: it is simply not a number. }
  AssertTrue('dash', IsNan(TyParseDataValue(TyDataText('-'), ddtFloat)));
  AssertTrue('empty', IsNan(TyParseDataValue(TyDataText(''), ddtFloat)));
  AssertTrue('blank', IsNan(TyParseDataValue(TyDataText('   '), ddtFloat)));
  AssertTrue('word', IsNan(TyParseDataValue(TyDataText('none'), ddtFloat)));
end;

procedure TAdvChartDataTest.TestNumericTextIsTrimmedAndParsed;
begin
  AssertEquals(123, TyParseDataValue(TyDataText(' 123 '), ddtFloat), 0);
  AssertEquals(-4.5, TyParseDataValue(TyDataText('-4.5'), ddtFloat), 0);
  AssertEquals(1500, TyParseDataValue(TyDataText('1.5e3'), ddtFloat), 0);
end;

procedure TAdvChartDataTest.TestTextIsParsedWithAFixedDecimalPoint;
var
  saved: Char;
  v: Double;
begin
  { Data text comes from option text, where the decimal separator is always a
    point. Reading it through the machine's locale would turn 1.5 into NaN on
    every comma-locale machine and nothing here would notice, because this
    machine is not one. So the locale is changed for the length of the test. }
  saved := DefaultFormatSettings.DecimalSeparator;
  try
    DefaultFormatSettings.DecimalSeparator := ',';
    v := TyParseDataValue(TyDataText('1.5'), ddtFloat);
    AssertEquals('a point is still a point', 1.5, v, 0);
    AssertTrue('and a comma is not a number', IsNan(TyParseDataValue(TyDataText('1,5'), ddtFloat)));
  finally
    DefaultFormatSettings.DecimalSeparator := saved;
  end;
end;

procedure TAdvChartDataTest.TestIntTruncatesTowardZero;
begin
  AssertEquals('positive', 3, TyParseDataValue(TyDataNum(3.7), ddtInt), 0);
  AssertEquals('negative', -3, TyParseDataValue(TyDataNum(-3.7), ddtInt), 0);
  AssertEquals('from text', 3, TyParseDataValue(TyDataText('3.7'), ddtInt), 0);
  AssertTrue('a gap survives truncation', IsNan(TyParseDataValue(TyDataNone, ddtInt)));
end;

procedure TAdvChartDataTest.TestBooleanCountsAsOneOrZero;
begin
  AssertEquals(1, TyParseDataValue(TyDataBool(True), ddtFloat), 0);
  AssertEquals(0, TyParseDataValue(TyDataBool(False), ddtFloat), 0);
  { A boolean names no instant, so it is a gap on a time dimension rather than
    the epoch. }
  AssertTrue('time', IsNan(TyParseDataValue(TyDataBool(True), ddtTime)));
end;

procedure TAdvChartDataTest.TestOrdinalIsNotParsedByTheValueParser;
begin
  { Interning needs the dimension's category list, which this function does not
    have. Routing an ordinal through it would silently produce gaps. }
  AssertTrue(IsNan(TyParseDataValue(TyDataText('Mon'), ddtOrdinal)));
end;

{ ============================ time ============================ }

procedure TAdvChartDataTest.TestTimeAcceptsTheEChartsSubset;
var ms: Double;
begin
  AssertTrue('year only', TyParseDateMs('2024', ms, True));
  AssertEquals(TyDateTimeToMs(EncodeDate(2024, 1, 1)), ms, 0);
  AssertTrue('year-month', TyParseDateMs('2024-03', ms, True));
  AssertEquals(TyDateTimeToMs(EncodeDate(2024, 3, 1)), ms, 0);
  AssertTrue('date', TyParseDateMs('2024-03-05', ms, True));
  AssertEquals(TyDateTimeToMs(EncodeDate(2024, 3, 5)), ms, 0);
  AssertTrue('slashes', TyParseDateMs('2024/03/05', ms, True));
  AssertEquals(TyDateTimeToMs(EncodeDate(2024, 3, 5)), ms, 0);
  AssertTrue('space instead of T', TyParseDateMs('2024-03-05 06:07', ms, True));
  AssertEquals(TyDateTimeToMs(EncodeDate(2024, 3, 5) + EncodeTime(6, 7, 0, 0)), ms, 0);
  AssertTrue('with seconds', TyParseDateMs('2024-03-05T06:07:08', ms, True));
  AssertEquals(TyDateTimeToMs(EncodeDate(2024, 3, 5) + EncodeTime(6, 7, 8, 0)), ms, 0);
end;

procedure TAdvChartDataTest.TestTimeFractionIsPaddedNotTruncated;
var ms, base: Double;
begin
  base := TyDateTimeToMs(EncodeDate(2024, 3, 5) + EncodeTime(0, 0, 1, 0));
  { .5 of a second is 500 ms, not 5. Reading the digits as a plain integer is
    the obvious mistake and it is silently wrong by two orders of magnitude. }
  AssertTrue(TyParseDateMs('2024-03-05T00:00:01.5', ms, True));
  AssertEquals('one digit', base + 500, ms, 0);
  AssertTrue(TyParseDateMs('2024-03-05T00:00:01.05', ms, True));
  AssertEquals('two digits', base + 50, ms, 0);
  AssertTrue(TyParseDateMs('2024-03-05T00:00:01.125', ms, True));
  AssertEquals('three digits', base + 125, ms, 0);
  { Finer than this store's resolution: dropped, as ECharts drops it. }
  AssertTrue(TyParseDateMs('2024-03-05T00:00:01.1259999', ms, True));
  AssertEquals('surplus digits', base + 125, ms, 0);
  AssertTrue('a comma is a decimal point here', TyParseDateMs('2024-03-05T00:00:01,5', ms, True));
  AssertEquals(base + 500, ms, 0);
end;

procedure TAdvChartDataTest.TestTimeZoneDesignatorsAreApplied;
var utc, z, plus8, minus5, plus0800: Double;
begin
  AssertTrue(TyParseDateMs('2024-03-05T12:00:00', utc, True));
  AssertTrue(TyParseDateMs('2024-03-05T12:00:00Z', z, True));
  AssertEquals('Z is UTC', utc, z, 0);
  AssertTrue(TyParseDateMs('2024-03-05T12:00:00+08:00', plus8, True));
  AssertEquals('noon in +08:00 is 04:00 UTC', utc - 8 * 3600000.0, plus8, 0);
  AssertTrue(TyParseDateMs('2024-03-05T12:00:00-05:00', minus5, True));
  AssertEquals('noon in -05:00 is 17:00 UTC', utc + 5 * 3600000.0, minus5, 0);
  AssertTrue('the colon is optional', TyParseDateMs('2024-03-05T12:00:00+0800', plus0800, True));
  AssertEquals(plus8, plus0800, 0);
end;

procedure TAdvChartDataTest.TestTimeWithoutAZoneIsLocal;
var asLocal, asUTC: Double;
begin
  { ECharts parses an undesignated timestamp as local time, deliberately unlike
    JavaScript's own Date parser. The assertion is written against the machine's
    offset rather than a fixed number, so it says the same thing everywhere. }
  AssertTrue(TyParseDateMs('2024-03-05T12:00:00', asLocal, False));
  AssertTrue(TyParseDateMs('2024-03-05T12:00:00', asUTC, True));
  AssertEquals(asUTC + GetLocalTimeOffset * 60000.0, asLocal, 0);
end;

procedure TAdvChartDataTest.TestTimeRejectsImpossibleComponents;
var ms: Double;
begin
  { JavaScript would wrap month 13 into next January. A gap says "this is a
    typo"; a point silently a year away does not. }
  AssertFalse('month 13', TyParseDateMs('2024-13-01', ms, True));
  AssertFalse('month 0', TyParseDateMs('2024-00-01', ms, True));
  AssertFalse('day 32', TyParseDateMs('2024-01-32', ms, True));
  AssertFalse('30 February', TyParseDateMs('2024-02-30', ms, True));
  AssertTrue('but 29 February in a leap year', TyParseDateMs('2024-02-29', ms, True));
  AssertFalse('and not in a common one', TyParseDateMs('2023-02-29', ms, True));
  AssertFalse('hour 24', TyParseDateMs('2024-01-01T24:00', ms, True));
  AssertFalse('minute 60', TyParseDateMs('2024-01-01T00:60', ms, True));
  AssertTrue('the answer is NaN, not a stale value', IsNan(ms));
end;

procedure TAdvChartDataTest.TestTimeRejectsTrailingJunk;
var ms: Double;
begin
  AssertFalse('short year', TyParseDateMs('24-01-01', ms, True));
  AssertFalse('trailing text', TyParseDateMs('2024-01-01 oops', ms, True));
  AssertFalse('not a date at all', TyParseDateMs('yesterday', ms, True));
  AssertFalse('empty', TyParseDateMs('', ms, True));
end;

procedure TAdvChartDataTest.TestTimeNumberIsAlreadyEpochMs;
begin
  { A number on a time dimension is a timestamp, not something to parse. }
  AssertEquals(1700000000000.0, TyParseDataValue(TyDataNum(1700000000000.0), ddtTime), 0);
  AssertEquals('rounded to the millisecond', 1700000000001.0,
    TyParseDataValue(TyDataNum(1700000000000.6), ddtTime), 0);
end;

procedure TAdvChartDataTest.TestTimeRoundTripsThroughTDateTime;
var dt: TDateTime;
begin
  dt := EncodeDate(2024, 3, 5) + EncodeTime(6, 7, 8, 125);
  AssertEquals(dt, TyMsToDateTime(TyDateTimeToMs(dt)), 1 / 86400000.0);
end;

{ ============================ schema ============================ }

procedure TAdvChartDataTest.TestDimensionsAreNamedAndTyped;
begin
  AssertEquals('first is zero', 0, FS.AddDimension('t', ddtTime));
  AssertEquals('then one', 1, FS.AddDimension('v', ddtFloat));
  AssertEquals(2, FS.DimCount);
  AssertEquals(1, FS.DimIndexOf('v'));
  AssertEquals(-1, FS.DimIndexOf('nope'));
  AssertEquals('t', FS.DimName(0));
  AssertTrue(FS.DimType(0) = ddtTime);
end;

procedure TAdvChartDataTest.TestUnknownDimensionAnswersSafely;
begin
  FillLinear(3);
  { A dimension index that came from a bad `encode` must not crash the render. }
  AssertTrue('read', IsNan(FS.Get(9, 0)));
  AssertTrue('read raw', IsNan(FS.GetByRaw(-1, 0)));
  AssertEquals('name', '', FS.DimName(9));
  AssertEquals('categories', 0, FS.CategoryCount(9));
  AssertEquals('text', '', FS.GetOrdinalText(9, 0));
  AssertTrue('meta', FS.OrdinalMeta(9) = nil);
end;

procedure TAdvChartDataTest.TestADimensionAddedAfterFillingHasNoData;
var
  d: Integer;
  lo, hi: Double;
begin
  { Stacking appends two calculated dimensions to a store that is already full.
    The rows that predate the dimension have no value for it, and no value is
    NaN -- a zero would draw a stack segment that is not there. }
  FillLinear(3);
  d := FS.AddDimension('stacked', ddtFloat);
  AssertTrue('row 0', IsNan(FS.Get(d, 0)));
  AssertTrue('row 2', IsNan(FS.Get(d, 2)));
  AssertFalse('and it has no extent', FS.DataExtent(d, lo, hi));
end;

{ ============================ filling ============================ }

procedure TAdvChartDataTest.TestAShortRowLeavesTheRestNoData;
begin
  { Both overloads, because they fill the tail separately and mutation found
    only one of them was covered: a row of raw values and a row of numbers are
    the same promise to the caller. }
  FS.AddDimension('x', ddtFloat);
  FS.AddDimension('y', ddtFloat);
  FS.AddDimension('z', ddtFloat);
  FS.AppendRow([1.0, 2.0]);
  FS.AppendRow([TyDataNum(3), TyDataNum(4)]);
  AssertEquals(1, FS.Get(0, 0), 0);
  AssertEquals(2, FS.Get(1, 0), 0);
  AssertTrue('numbers: the column the row did not reach', IsNan(FS.Get(2, 0)));
  AssertEquals(3, FS.Get(0, 1), 0);
  AssertTrue('raw values: same', IsNan(FS.Get(2, 1)));
end;

procedure TAdvChartDataTest.TestGrowthKeepsEveryValue;
var i: Integer;
begin
  { The columns grow geometrically. A capacity bug shows up as values lost at a
    power-of-two boundary and nowhere else, so this crosses several. }
  FillLinear(100);
  AssertEquals(100, FS.Count);
  AssertEquals(100, FS.RawCount);
  for i := 0 to 99 do
  begin
    AssertEquals(i, FS.Get(0, i), 0);
    AssertEquals(i * 10, FS.Get(1, i), 0);
  end;
end;

procedure TAdvChartDataTest.TestAppendingWhileFilteredIsRefused;
begin
  { A row appended under an active filter would land outside the index vector
    and be invisible until the filter lifted, which looks like data loss.
    ECharts asserts on the same thing. }
  FillLinear(5);
  FS.SelectRange(0, 1, 3);
  try
    FS.AppendRow([9.0, 90.0]);
    Fail('appending to a filtered store should raise');
  except
    on EInvalidOperation do ;
  end;
end;

{ ============================ ordinal ============================ }

procedure TAdvChartDataTest.TestCollectingBuildsTheCategoryList;
begin
  FS.AddDimension('c', ddtOrdinal);
  FS.AddDimension('v', ddtFloat);
  FS.AppendRow([TyDataText('Mon'), TyDataNum(1)]);
  FS.AppendRow([TyDataText('Tue'), TyDataNum(2)]);
  FS.AppendRow([TyDataText('Mon'), TyDataNum(3)]);
  AssertEquals('two categories, not three', 2, FS.CategoryCount(0));
  AssertEquals(0, FS.Get(0, 0), 0);
  AssertEquals(1, FS.Get(0, 1), 0);
  AssertEquals('the repeat reuses its ordinal', 0, FS.Get(0, 2), 0);
  AssertEquals('Tue', FS.CategoryAt(0, 1));
  AssertEquals('Mon', FS.GetOrdinalText(0, 2));
end;

procedure TAdvChartDataTest.TestFixedCategoriesTurnUnknownIntoAGap;
begin
  { The categories came from the axis. A name that is not among them is not a
    new category -- the axis has no tick for it -- so it is a gap. }
  FS.AddDimension('c', ddtOrdinal);
  FS.SetCategories(0, ['Mon', 'Tue']);
  FS.AppendRow([TyDataText('Tue')]);
  FS.AppendRow([TyDataText('Wed')]);
  AssertEquals(1, FS.Get(0, 0), 0);
  AssertTrue('Wed is not on this axis', IsNan(FS.Get(0, 1)));
  AssertEquals('and it collected nothing', 2, FS.CategoryCount(0));
end;

procedure TAdvChartDataTest.TestANumberOnAFixedAxisIsACategoryIndex;
begin
  FS.AddDimension('c', ddtOrdinal);
  FS.SetCategories(0, ['Mon', 'Tue', 'Wed']);
  FS.AppendRow([TyDataNum(2)]);
  FS.AppendRow([TyDataNum(7)]);
  FS.AppendRow([TyDataNum(1.5)]);
  AssertEquals('an index into the list', 2, FS.Get(0, 0), 0);
  AssertEquals('Wed', FS.GetOrdinalText(0, 0));
  AssertTrue('out of range names no category', IsNan(FS.Get(0, 1)));
  AssertTrue('and neither does half of one', IsNan(FS.Get(0, 2)));
end;

procedure TAdvChartDataTest.TestANumberOnACollectingAxisIsALabel;
begin
  { Years in [[2001, 12], [2002, 15]] are categories, not indices -- there is no
    list for them to be indices into. }
  FS.AddDimension('c', ddtOrdinal);
  FS.AddDimension('v', ddtFloat);
  FS.AppendRow([TyDataNum(2001), TyDataNum(12)]);
  FS.AppendRow([TyDataNum(2002), TyDataNum(15)]);
  AssertEquals(2, FS.CategoryCount(0));
  AssertEquals(0, FS.Get(0, 0), 0);
  AssertEquals('2001', FS.CategoryAt(0, 0));
end;

procedure TAdvChartDataTest.TestDashAndEmptyAreRealCategories;
begin
  { ECharts returns early for ordinal, before its no-data rules run, so on a
    category axis these two are names like any other. Copying the rule matters:
    a bar labelled '-' must get a slot rather than vanish. }
  FS.AddDimension('c', ddtOrdinal);
  FS.AppendRow([TyDataText('-')]);
  FS.AppendRow([TyDataText('')]);
  AssertEquals(2, FS.CategoryCount(0));
  AssertEquals(0, FS.Get(0, 0), 0);
  AssertEquals(1, FS.Get(0, 1), 0);
end;

procedure TAdvChartDataTest.TestAbsentIsStillAGapOnAnOrdinal;
begin
  FS.AddDimension('c', ddtOrdinal);
  FS.AppendRow([TyDataNone]);
  AssertTrue(IsNan(FS.Get(0, 0)));
  AssertEquals('and no category was invented', 0, FS.CategoryCount(0));
  AssertEquals('', FS.GetOrdinalText(0, 0));
end;

procedure TAdvChartDataTest.TestNaNIsNotACategoryCalledNan;
begin
  { A numeric gap reaching a collecting ordinal dimension has to stay a gap.
    Rendering it as text first would intern a category literally called Nan and
    put a tick on the axis for it. }
  FS.AddDimension('c', ddtOrdinal);
  FS.AppendRow([TyDataNum(NaN)]);
  FS.AppendRow([TyDataNum(Infinity)]);
  AssertTrue('row 0', IsNan(FS.Get(0, 0)));
  AssertTrue('row 1', IsNan(FS.Get(0, 1)));
  AssertEquals('and nothing was collected', 0, FS.CategoryCount(0));
end;

procedure TAdvChartDataTest.TestDeduplicationOffAppendsBlind;
var m: TTyOrdinalMeta;
begin
  { ECharts' axis.deduplication = false. It exists for large ordered data known
    not to repeat, and its point is that no map is built and no comparison is
    made -- so a repeat really does become a second category. }
  FS.AddDimension('c', ddtOrdinal);
  m := FS.OrdinalMeta(0);
  m.Deduplication := False;
  FS.AppendRow([TyDataText('Mon')]);
  FS.AppendRow([TyDataText('Mon')]);
  AssertEquals(2, FS.CategoryCount(0));
  AssertEquals(1, FS.Get(0, 1), 0);
end;

procedure TAdvChartDataTest.TestCategoriesMustBeSetBeforeFilling;
begin
  { ECharts fills first and rewrites the column in place when the axis turns up
    later. Ours reads axes before series, so the rewrite is replaced by a rule --
    and a rule that is not enforced is a comment. }
  FS.AddDimension('c', ddtOrdinal);
  FS.AppendRow([TyDataText('Mon')]);
  try
    FS.SetCategories(0, ['Tue', 'Wed']);
    Fail('setting categories after filling should raise');
  except
    on EInvalidOperation do ;
  end;
end;

procedure TAdvChartDataTest.TestCategoriesNeedAnOrdinalDimension;
begin
  FS.AddDimension('v', ddtFloat);
  try
    FS.SetCategories(0, ['Mon']);
    Fail('a float dimension has no categories');
  except
    on EInvalidOperation do ;
  end;
end;

{ ====================== a borrowed category list ====================== }

procedure TAdvChartDataTest.TestTwoStoresSharingOneListAgreeOnOrdinals;
var
  other: TTyDataStore;
  axis: TTyOrdinalMeta;
begin
  { THE reason the list is shared rather than copied. Two series on one category
    axis, each collecting from its own data: with private lists they disagree
    about which name ordinal 0 is, and render offset from each other on an axis
    they supposedly share. Nothing about either store looks wrong on its own --
    which is why this is a test and not a comment. }
  axis := TTyOrdinalMeta.Create;
  other := TTyDataStore.Create;
  try
    FS.AddDimension('c', ddtOrdinal);
    FS.UseOrdinalMeta(0, axis);
    other.AddDimension('c', ddtOrdinal);
    other.UseOrdinalMeta(0, axis);

    FS.AppendRow([TyDataText('Mon')]);
    FS.AppendRow([TyDataText('Tue')]);
    other.AppendRow([TyDataText('Tue')]);
    other.AppendRow([TyDataText('Wed')]);

    AssertEquals('one list, three names', 3, axis.Count);
    AssertEquals('Tue is 1 in the first store', 1, FS.Get(0, 1), 0);
    AssertEquals('and 1 in the second too', 1, other.Get(0, 0), 0);
    AssertEquals('Wed came from the second store', 2, other.Get(0, 1), 0);
    AssertEquals('and the first store can read it', 'Wed', FS.CategoryAt(0, 2));
  finally
    other.Free;
    axis.Free;
  end;
end;

procedure TAdvChartDataTest.TestABorrowedListIsNotFreedByTheStore;
var axis: TTyOrdinalMeta;
begin
  { A double free shows up on the NEXT test, not this one, so the assertion is
    that the list is still usable after the store that borrowed it is gone. }
  axis := TTyOrdinalMeta.Create;
  try
    FS.AddDimension('c', ddtOrdinal);
    FS.UseOrdinalMeta(0, axis);
    FS.AppendRow([TyDataText('Mon')]);
    FreeAndNil(FS);
    AssertEquals('the axis still owns its list', 1, axis.Count);
    AssertEquals('Mon', axis.CategoryAt(0));
  finally
    axis.Free;
  end;
  FS := TTyDataStore.Create;   { TearDown frees it }
end;

procedure TAdvChartDataTest.TestClearDoesNotWipeABorrowedList;
var axis: TTyOrdinalMeta;
begin
  { Only the OWNER resets. One series clearing itself must not drop categories
    another series already contributed -- that other series' ordinal column
    would then point at names which no longer exist. }
  axis := TTyOrdinalMeta.Create;
  try
    FS.AddDimension('c', ddtOrdinal);
    FS.AddDimension('own', ddtOrdinal);
    FS.UseOrdinalMeta(0, axis);
    FS.AppendRow([TyDataText('Mon'), TyDataText('x')]);
    AssertEquals(1, axis.Count);
    FS.Clear;
    AssertEquals('the axis list survives', 1, axis.Count);
    AssertEquals('while the store''s own list is reset', 0, FS.CategoryCount(1));
  finally
    axis.Free;
  end;
end;

procedure TAdvChartDataTest.TestABorrowedListCannotBeOverwrittenBySeriesData;
var axis: TTyOrdinalMeta;
begin
  { A series telling the axis what its categories are is backwards. The axis
    sets them on its own list; a store that borrowed one must not overwrite
    what every other series on that axis is reading. }
  axis := TTyOrdinalMeta.Create;
  try
    axis.SetCategories(['Mon', 'Tue']);
    FS.AddDimension('c', ddtOrdinal);
    FS.UseOrdinalMeta(0, axis);
    try
      FS.SetCategories(0, ['Wed']);
      Fail('a borrowed list must not be overwritten');
    except
      on EInvalidOperation do ;
    end;
    AssertEquals('and it was not', 2, axis.Count);
  finally
    axis.Free;
  end;
end;

procedure TAdvChartDataTest.TestBorrowingAfterFillingIsRefused;
var axis: TTyOrdinalMeta;
begin
  { Same rule as SetCategories, for the same reason: the column has already been
    parsed against the old list, and swapping the list underneath would
    reinterpret every value in it. }
  axis := TTyOrdinalMeta.Create;
  try
    FS.AddDimension('c', ddtOrdinal);
    FS.AppendRow([TyDataText('Mon')]);
    try
      FS.UseOrdinalMeta(0, axis);
      Fail('borrowing after the first row should raise');
    except
      on EInvalidOperation do ;
    end;
  finally
    axis.Free;
  end;
end;

{ ============================ identity ============================ }

procedure TAdvChartDataTest.TestIdAndNameAreOnlyAllocatedWhenUsed;
begin
  { Most series have neither. Paying for two string arrays per store when
    nothing writes them is the kind of cost that only shows up at a million
    points. }
  FillLinear(3);
  AssertFalse('no ids yet', FS.HasIds);
  AssertFalse('no names yet', FS.HasNames);
  AssertEquals('', FS.GetId(0));
  AssertEquals('', FS.GetName(0));
  FS.SetName(1, 'the second');
  AssertTrue(FS.HasNames);
  AssertFalse('and still no ids', FS.HasIds);
end;

procedure TAdvChartDataTest.TestIdAndNameFollowTheRawRow;
begin
  FillLinear(5);
  FS.SetId(3, 'id3');
  FS.SetName(3, 'name3');
  FS.SelectRange(0, 2, 4);        { rows 2, 3, 4 survive }
  AssertEquals('data index 1 is raw row 3', 3, FS.GetRawIndex(1));
  AssertEquals('id3', FS.GetId(1));
  AssertEquals('name3', FS.GetName(1));
end;

{ ============================ overrides ============================ }

procedure TAdvChartDataTest.TestAnOverrideOfZeroIsNotAbsence;
var k: Integer;
begin
  { This is the whole reason the side table has a Has flag rather than a
    sentinel. A symbolSize of 0 hides a point on purpose; "not overridden" lets
    the series value stand. NaN cannot tell them apart and neither can 0. }
  FillLinear(2);
  k := TyOverrideKey('symbolSize');
  FS.SetOverride(0, k, TyDataNum(0));
  AssertTrue('row 0 is overridden', FS.HasOverride(0, k));
  AssertEquals(0, FS.GetOverride(0, k).Num, 0);
  AssertFalse('row 1 is not', FS.HasOverride(1, k));
  AssertTrue('and reads as absent', FS.GetOverride(1, k).Kind = dvkNone);
end;

procedure TAdvChartDataTest.TestOverridesAreSparse;
var k: Integer;
begin
  { A store where nothing is overridden must cost nothing, and one where a
    single point is must cost one entry -- not one per row. }
  FillLinear(1000);
  AssertEquals('nothing stored', 0, FS.OverrideCount);
  k := TyOverrideKey('itemColor');
  FS.SetOverride(500, k, TyDataText('#f00'));
  AssertEquals('one entry for one override', 1, FS.OverrideCount);
  AssertEquals('#f00', FS.GetOverride(500, k).Text);
  AssertFalse(FS.HasOverride(499, k));
end;

procedure TAdvChartDataTest.TestSettingTheSameKeyTwiceReplaces;
var k: Integer;
begin
  FillLinear(2);
  k := TyOverrideKey('symbol');
  FS.SetOverride(0, k, TyDataText('circle'));
  FS.SetOverride(0, k, TyDataText('diamond'));
  AssertEquals('replaced', 'diamond', FS.GetOverride(0, k).Text);
  AssertEquals('and not accumulated', 1, FS.OverrideCount);
end;

procedure TAdvChartDataTest.TestOverridesFollowTheRawRowThroughAFilter;
var k: Integer;
begin
  FillLinear(5);
  k := TyOverrideKey('selected');
  FS.SetOverride(3, k, TyDataBool(True));
  FS.SelectRange(0, 2, 4);
  AssertTrue('by data index', FS.HasOverride(1, k));
  AssertTrue('by raw index', FS.HasOverrideByRaw(3, k));
  AssertFalse('and the neighbour has none', FS.HasOverride(0, k));
end;

procedure TAdvChartDataTest.TestOverrideKeysAreInterned;
var a, b: Integer;
begin
  a := TyOverrideKey('symbolRotate');
  b := TyOverrideKey('symbolRotate');
  AssertEquals('the same name is the same key', a, b);
  AssertEquals('symbolRotate', TyOverrideKeyName(a));
  AssertTrue('a different name is a different key', TyOverrideKey('symbolOffset') <> a);
  { Option keys are case-sensitive, so these are two keys, not one. }
  AssertTrue('case matters', TyOverrideKey('SymbolRotate') <> a);
  AssertEquals('out of range', '', TyOverrideKeyName(-1));
end;

{ ============================ extent ============================ }

procedure TAdvChartDataTest.TestExtentIgnoresGaps;
var lo, hi: Double;
begin
  FS.AddDimension('v', ddtFloat);
  FS.AppendRow([5.0]);
  FS.AppendRow([NaN]);
  FS.AppendRow([-2.0]);
  AssertTrue(FS.DataExtent(0, lo, hi));
  AssertEquals(-2, lo, 0);
  AssertEquals(5, hi, 0);
end;

procedure TAdvChartDataTest.TestAllGapsHasNoExtent;
var lo, hi: Double;
begin
  { An empty extent has to be sayable. ECharts returns [+Inf, -Inf] and every
    caller has to remember which way round the empty one is; False says it
    once and cannot be misread. }
  FS.AddDimension('v', ddtFloat);
  FS.AppendRow([NaN]);
  FS.AppendRow([NaN]);
  AssertFalse(FS.DataExtent(0, lo, hi));
  AssertTrue('and it does not hand back a number', IsNan(lo) and IsNan(hi));
end;

procedure TAdvChartDataTest.TestExtentIgnoresInfinity;
var lo, hi: Double;
begin
  { An infinite bound poisons every nice-tick calculation downstream, and there
    are TWO places it has to be refused: the extent kept incrementally as rows
    arrive, and the scan that a filter forces instead. Mutation found that only
    the first was covered -- an unfiltered store never reaches the loop -- so
    the filter here is on a SECOND dimension, which drops a row while leaving
    both infinities in the window. }
  FS.AddDimension('v', ddtFloat);
  FS.AddDimension('k', ddtFloat);
  FS.AppendRow([3.0, 1.0]);
  FS.AppendRow([Infinity, 1.0]);
  FS.AppendRow([NegInfinity, 1.0]);
  FS.AppendRow([NaN, 1.0]);
  FS.AppendRow([500.0, 9.0]);
  AssertTrue('kept as the rows arrived', FS.DataExtent(0, lo, hi));
  AssertEquals(3, lo, 0);
  AssertEquals(500, hi, 0);
  FS.SelectRange(1, 0, 5);
  AssertEquals('the infinities are still in the window', 4, FS.Count);
  AssertTrue('and scanned', FS.DataExtent(0, lo, hi));
  AssertEquals(3, lo, 0);
  AssertEquals(3, hi, 0);
end;

procedure TAdvChartDataTest.TestPositiveOnlyExtentIsForTheLogAxis;
var lo, hi: Double;
begin
  FS.AddDimension('v', ddtFloat);
  FS.AppendRow([-5.0]);
  FS.AppendRow([0.0]);
  FS.AppendRow([2.0]);
  FS.AppendRow([40.0]);
  AssertTrue(FS.DataExtent(0, lo, hi, defPositive));
  AssertEquals('zero has no logarithm either', 2, lo, 0);
  AssertEquals(40, hi, 0);
  AssertTrue('the unfiltered answer is still there', FS.DataExtent(0, lo, hi));
  AssertEquals(-5, lo, 0);
end;

procedure TAdvChartDataTest.TestExtentFollowsTheFilter;
var lo, hi: Double;
begin
  FillLinear(10);
  AssertTrue(FS.DataExtent(1, lo, hi));
  AssertEquals(0, lo, 0);
  AssertEquals(90, hi, 0);
  FS.SelectRange(0, 3, 5);
  AssertTrue(FS.DataExtent(1, lo, hi));
  AssertEquals('the window, not the input', 30, lo, 0);
  AssertEquals(50, hi, 0);
  FS.RestoreAll;
  AssertTrue(FS.DataExtent(1, lo, hi));
  AssertEquals(90, hi, 0);
end;

procedure TAdvChartDataTest.TestExtentIsInvalidatedByAnAppend;
var lo, hi: Double;
begin
  { The extent is cached. A cache that outlives the data it summarises is the
    classic version of this bug and it only shows after the first read. }
  FS.AddDimension('v', ddtFloat);
  FS.AppendRow([1.0]);
  AssertTrue(FS.DataExtent(0, lo, hi));
  AssertEquals(1, hi, 0);
  FS.AppendRow([7.0]);
  AssertTrue(FS.DataExtent(0, lo, hi));
  AssertEquals(7, hi, 0);
end;

procedure TAdvChartDataTest.TestExtentCacheDoesNotOutliveItsWindow;
var lo, hi: Double;
begin
  { The filtered extent is cached, and a second window is what has to throw the
    cache away. Every other test here reads the extent once per filter, which
    cannot tell a live cache from a dead one -- mutation removing the whole
    invalidation left them all green. }
  FillLinear(10);
  FS.SelectRange(0, 0, 2);
  AssertTrue(FS.DataExtent(1, lo, hi));
  AssertEquals(20, hi, 0);
  FS.SelectRange(0, 0, 1);
  AssertTrue(FS.DataExtent(1, lo, hi));
  AssertEquals('the new window, not the remembered one', 10, hi, 0);
  FS.RestoreAll;
  FS.SelectRange(0, 7, 9);
  AssertTrue(FS.DataExtent(1, lo, hi));
  AssertEquals(70, lo, 0);
  AssertEquals(90, hi, 0);
end;

procedure TAdvChartDataTest.TestTheTwoExtentFiltersCacheApart;
var lo, hi: Double;
begin
  { A log axis and a linear one can read the same dimension in the same layout.
    They cache separately, and neither may answer from the other's slot -- in
    either order. }
  FS.AddDimension('v', ddtFloat);
  FS.AppendRow([-5.0]);
  FS.AppendRow([2.0]);
  FS.AppendRow([40.0]);
  FS.AppendRow([999.0]);
  FS.SelectRange(0, -10, 100);
  AssertEquals('filtered, so both answers are scanned', 3, FS.Count);
  AssertTrue(FS.DataExtent(0, lo, hi));
  AssertEquals(-5, lo, 0);
  AssertTrue(FS.DataExtent(0, lo, hi, defPositive));
  AssertEquals('the log axis reads its own slot', 2, lo, 0);
  AssertTrue(FS.DataExtent(0, lo, hi));
  AssertEquals('and the plain one is still plain', -5, lo, 0);
end;

{ ============================ index spaces ============================ }

procedure TAdvChartDataTest.TestRawIndexIsIdentityUntilFiltered;
var i: Integer;
begin
  FillLinear(4);
  AssertFalse(FS.IsFiltered);
  for i := 0 to 3 do
  begin
    AssertEquals(i, FS.GetRawIndex(i));
    AssertEquals(i, FS.IndexOfRawIndex(i));
  end;
end;

procedure TAdvChartDataTest.TestRawIndexRoundTripsThroughAFilter;
var i: Integer;
begin
  { The pair the v6.1 callback record promises. Every kept row must survive the
    round trip in both directions. }
  FillLinear(20);
  FEven := True;
  FS.FilterSelf(@KeepEven);
  AssertEquals(10, FS.Count);
  AssertEquals('the input is untouched', 20, FS.RawCount);
  AssertTrue(FS.IsFiltered);
  for i := 0 to FS.Count - 1 do
  begin
    AssertEquals('there and back', i, FS.IndexOfRawIndex(FS.GetRawIndex(i)));
    AssertEquals('and the value came with it', FS.GetRawIndex(i) * 10,
      FS.Get(1, i), 0);
  end;
end;

procedure TAdvChartDataTest.TestAFilteredOutRowHasNoDataIndex;
begin
  FillLinear(20);
  FEven := True;
  FS.FilterSelf(@KeepEven);
  AssertEquals('row 4 is shown', 2, FS.IndexOfRawIndex(4));
  AssertEquals('row 5 is not', -1, FS.IndexOfRawIndex(5));
end;

procedure TAdvChartDataTest.TestOutOfRangeIndicesAnswerMinusOne;
begin
  FillLinear(3);
  AssertEquals(-1, FS.GetRawIndex(-1));
  AssertEquals(-1, FS.GetRawIndex(3));
  AssertEquals(-1, FS.IndexOfRawIndex(-1));
  AssertEquals(-1, FS.IndexOfRawIndex(3));
  AssertTrue('and reading through one is a gap', IsNan(FS.Get(0, 3)));
end;

{ ============================ filtering ============================ }

procedure TAdvChartDataTest.TestSelectRangeKeepsGaps;
begin
  { ECharts is explicit that a range select does not drop NaN, and it is not an
    oversight: a line chart draws a gap where a value is missing, and dropping
    the row would close the gap and draw a line straight through it. }
  FS.AddDimension('x', ddtFloat);
  FS.AppendRow([1.0]);
  FS.AppendRow([NaN]);
  FS.AppendRow([2.0]);
  FS.AppendRow([99.0]);
  FS.SelectRange(0, 0, 10);
  AssertEquals('the gap stayed', 3, FS.Count);
  AssertTrue('and it is still a gap', IsNan(FS.Get(0, 1)));
  AssertEquals('while 99 went', 2, FS.Get(0, 2), 0);
end;

procedure TAdvChartDataTest.TestSelectRangeTestsEveryGivenDimension;
var r: array[0..1] of TTyDimRange;
begin
  FS.AddDimension('x', ddtFloat);
  FS.AddDimension('y', ddtFloat);
  FS.AppendRow([1.0, 1.0]);
  FS.AppendRow([1.0, 9.0]);
  FS.AppendRow([9.0, 1.0]);
  r[0].Dim := 0; r[0].Min := 0; r[0].Max := 5;
  r[1].Dim := 1; r[1].Min := 0; r[1].Max := 5;
  FS.SelectRange(r);
  AssertEquals('only the row inside both', 1, FS.Count);
  AssertEquals(0, FS.GetRawIndex(0));
end;

procedure TAdvChartDataTest.TestFiltersCompose;
begin
  { A second filter narrows the first rather than replacing it. dataZoom on two
    axes is exactly this. }
  FillLinear(20);
  FS.SelectRange(0, 5, 15);
  AssertEquals(11, FS.Count);
  FEven := True;
  FS.FilterSelf(@KeepEven);
  AssertEquals('even rows within 5..15', 5, FS.Count);
  AssertEquals(6, FS.GetRawIndex(0));
end;

procedure TAdvChartDataTest.TestRestoreAllUndoesEverything;
begin
  FillLinear(10);
  FS.SelectRange(0, 3, 4);
  FS.RestoreAll;
  AssertEquals(10, FS.Count);
  AssertFalse(FS.IsFiltered);
  AssertEquals(7, FS.GetRawIndex(7));
end;

procedure TAdvChartDataTest.TestAFilterThatKeepsNothingIsStillAFilter;
var lo, hi: Double;
begin
  { An empty index vector in FPC IS nil, so a store that kept nothing looks
    exactly like a store that filtered nothing unless the two are tracked
    apart. The symptom would be an axis drawn to the extent of data that is not
    on screen. }
  FillLinear(5);
  FS.FilterSelf(@KeepNone);
  AssertEquals(0, FS.Count);
  AssertEquals('the input is still there', 5, FS.RawCount);
  AssertTrue('and it knows it is filtered', FS.IsFiltered);
  AssertFalse('so there is no extent to draw', FS.DataExtent(0, lo, hi));
end;

procedure TAdvChartDataTest.TestFilterSelfCarriesItsOwnState;
begin
  { The predicate is a method pointer so it can carry what it filters against;
    a plain procedure would need a global. }
  FillLinear(10);
  FEven := False;
  FS.FilterSelf(@KeepEven);
  AssertEquals(5, FS.Count);
  AssertEquals('the odd rows this time', 1, FS.GetRawIndex(0));
end;

{ ============================ inverted index ============================ }

procedure TAdvChartDataTest.TestInvertedIndexFindsTheRowForACategory;
begin
  FS.AddDimension('c', ddtOrdinal);
  FS.AddDimension('v', ddtFloat);
  FS.AppendRow([TyDataText('Mon'), TyDataNum(1)]);
  FS.AppendRow([TyDataText('Tue'), TyDataNum(2)]);
  FS.AppendRow([TyDataText('Wed'), TyDataNum(3)]);
  FS.BuildInvertedIndex(0);
  AssertEquals(1, FS.RawIndexOfOrdinal(0, 1));
  AssertEquals('a category with no row', -1, FS.RawIndexOfOrdinal(0, 9));
  AssertEquals('negative', -1, FS.RawIndexOfOrdinal(0, -1));
end;

procedure TAdvChartDataTest.TestInvertedIndexIsUnaffectedByFiltering;
begin
  { It is built over the raw rows on purpose, so a dataZoom does not invalidate
    it -- stacking reads it once per layout and the window moves every frame. }
  FS.AddDimension('c', ddtOrdinal);
  FS.AddDimension('v', ddtFloat);
  FS.AppendRow([TyDataText('Mon'), TyDataNum(1)]);
  FS.AppendRow([TyDataText('Tue'), TyDataNum(2)]);
  FS.AppendRow([TyDataText('Wed'), TyDataNum(3)]);
  FS.BuildInvertedIndex(0);
  FS.SelectRange(1, 3, 3);
  AssertEquals('one row shown', 1, FS.Count);
  AssertEquals('but Tue is still raw row 1', 1, FS.RawIndexOfOrdinal(0, 1));
end;

procedure TAdvChartDataTest.TestInvertedIndexNeedsBuilding;
begin
  { Answering -1 for every query would look like data with no categories in it,
    which is a much worse failure than a raised exception at the call site. }
  FS.AddDimension('c', ddtOrdinal);
  FS.AppendRow([TyDataText('Mon')]);
  try
    FS.RawIndexOfOrdinal(0, 0);
    Fail('querying an index that was never built should raise');
  except
    on EInvalidOperation do ;
  end;
end;

procedure TAdvChartDataTest.TestInvertedIndexNeedsAnOrdinalDimension;
begin
  FS.AddDimension('v', ddtFloat);
  try
    FS.BuildInvertedIndex(0);
    Fail('a float dimension has no ordinals to invert');
  except
    on EInvalidOperation do ;
  end;
end;

{ ============================ clear ============================ }

procedure TAdvChartDataTest.TestClearKeepsTheSchema;
begin
  FillLinear(5);
  FS.SelectRange(0, 1, 2);
  FS.Clear;
  AssertEquals('no rows', 0, FS.Count);
  AssertEquals(0, FS.RawCount);
  AssertFalse('and no filter either', FS.IsFiltered);
  AssertEquals('the shape survives', 2, FS.DimCount);
  AssertEquals('x', FS.DimName(0));
  FS.AppendRow([3.0, 30.0]);
  AssertEquals(1, FS.Count);
  AssertEquals(3, FS.Get(0, 0), 0);
end;

procedure TAdvChartDataTest.TestClearForgetsCollectedButKeepsFixedCategories;
begin
  { The two lists have different owners. A fixed list came from the axis and
    must survive its data being replaced; a collected one IS the data, and
    keeping it would leave ticks for categories that no longer exist. }
  FS.AddDimension('fixed', ddtOrdinal);
  FS.AddDimension('collected', ddtOrdinal);
  FS.SetCategories(0, ['Mon', 'Tue']);
  FS.AppendRow([TyDataText('Mon'), TyDataText('alpha')]);
  AssertEquals(2, FS.CategoryCount(0));
  AssertEquals(1, FS.CategoryCount(1));
  FS.Clear;
  AssertEquals('the axis still has its categories', 2, FS.CategoryCount(0));
  AssertEquals('the data-derived ones are gone', 0, FS.CategoryCount(1));
end;

procedure TAdvChartDataTest.TestRepeatedRefillDoesNotGrowTheHeap;
var
  before, after: PtrUInt;
  i, r: Integer;
begin
  { Nothing else in this suite watches memory, and a store is refilled on every
    setOption. The columns are reused; the category map and the override pool
    are the two places a leak would hide. }
  FS.AddDimension('c', ddtOrdinal);
  FS.AddDimension('v', ddtFloat);
  for r := 0 to 4 do
  begin
    FS.Clear;
    for i := 0 to 200 do
      FS.AppendRow([TyDataText('cat' + IntToStr(i mod 7)), TyDataNum(i)]);
    FS.SetOverride(0, TyOverrideKey('symbolSize'), TyDataNum(12));
  end;
  before := GetFPCHeapStatus.CurrHeapUsed;
  for r := 0 to 19 do
  begin
    FS.Clear;
    for i := 0 to 200 do
      FS.AppendRow([TyDataText('cat' + IntToStr(i mod 7)), TyDataNum(i)]);
    FS.SetOverride(0, TyOverrideKey('symbolSize'), TyDataNum(12));
  end;
  after := GetFPCHeapStatus.CurrHeapUsed;
  AssertTrue(Format('heap grew from %d to %d over twenty refills', [before, after]),
    after <= before);
end;

initialization
  RegisterTest(TAdvChartDataTest);
end.
