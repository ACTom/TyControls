unit test.advchart.stack;
{$mode objfpc}{$H+}
{ Values that accumulate: `stack`, `stackStrategy`, `stackOrder`.

  THESE TESTS ARE THE ONLY GUARD THERE IS. Not one pre-existing assertion in
  the suite changes when accumulation lands -- the bar-layout tests read column
  geometry, which is computed from the bar* keys and the band and never from a
  value, and the rest is vocabulary. So the suite stayed green while stacking
  was added, and it would have stayed green had it been added wrongly.

  Asserted against ECharts 6.1.0's own arithmetic, read from the source. The
  three that a reasonable-looking port gets wrong, and that each have a test
  here on purpose:
    - the search BREAKS at the nearest eligible member; it does not sum
      everything below;
    - so `sum` in the strategy predicate is the series' OWN raw value, never a
      running total;
    - stackOrder is read from the FIRST member of the group only. }
interface
uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Coord, tyControls.AdvChart.Data,
  tyControls.AdvChart.Builder, tyControls.AdvChart.Series,
  tyControls.AdvChart.Stack;

type
  TAdvChartStackTest = class(TTestCase)
  private
    FOpt: TTyChartOption;
    FBuild: TTyChartBuild;
    FIndex: TTyAxisSeriesIndex;
    FBind: TTySeriesBindingArray;
    FStores: array of TTyDataStore;
    FStacks: TTySeriesStackArray;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Run(const AText: string);
    { The cumulative value series ASlot plots at row ARow. }
    function Total(ASlot, ARow: Integer): Double;
    { What it was stacked onto; NaN when nothing was. }
    function Over(ASlot, ARow: Integer): Double;
  published
    procedure TestTwoSeriesAccumulate;
    procedure TestAnEmptyStackNameIsNotAStack;
    procedure TestDifferentNamesDoNotShareAPile;
    procedure TestTheSearchStopsAtTheNearestEligibleMember;
    procedure TestSamesignSplitsPositivesFromNegatives;
    procedure TestTheOtherThreeStrategies;
    procedure TestAGapStaysAGapInBothColumns;
    procedure TestCategoriesAreMatchedByNameNotByPosition;
    procedure TestAValueBaseAxisStacksByRowIndex;
    procedure TestStackOrderIsReadFromTheFirstMemberOnly;
    procedure TestATimeOrCategoryValueAxisIsRefused;
    procedure TestOneNameStacksAcrossTwoGrids;
    procedure TestTheValueAxisSpansTheTotalsNotTheValues;
    procedure TestAddSafeKeepsTheDecimalsTheInputsHad;
    procedure TestDecimalPrecisionCountsWhatIsWritten;
  end;

implementation

const Eps = 1e-9;

procedure TAdvChartStackTest.SetUp;
begin
  inherited SetUp;
  FOpt := TTyChartOption.Create;
  FIndex := TTyAxisSeriesIndex.Create;
  FBuild := nil;
end;

procedure TAdvChartStackTest.TearDown;
var i: Integer;
begin
  { A store borrows the axis' category list, so every store goes before the
    build that owns the axes. }
  for i := 0 to High(FStores) do
    FStores[i].Free;
  FStores := nil;
  FStacks := nil;
  FreeAndNil(FIndex);
  FreeAndNil(FBuild);
  FreeAndNil(FOpt);
  inherited TearDown;
end;

procedure TAdvChartStackTest.Run(const AText: string);
var
  i, k: Integer;
  dims: TTySeriesDimArray;
  st: TTyDataStore;
begin
  AssertTrue('the option parsed: ' + FOpt.Error.Message, FOpt.SetOptionText(AText));
  FreeAndNil(FBuild);
  FBuild := TyBuildGrids(FOpt, TyRectF(0, 0, 600, 400));
  FBind := TyBindSeries(FOpt, FBuild);
  SetLength(FStores, Length(FBind));
  for i := 0 to High(FBind) do
  begin
    st := TTyDataStore.Create;
    FStores[i] := st;
    if not FBind[i].HasAxes then Continue;
    dims := TySeriesCartesianDims(FBind[i].Cart, 0);
    for k := 0 to High(dims) do
    begin
      st.AddDimension(dims[k].Name, dims[k].Kind);
      if dims[k].Axis <> nil then st.UseOrdinalMeta(k, dims[k].Axis.Categories);
    end;
    TyFillSeriesStore(FOpt, i, dims, st);
  end;
  FIndex.Clear;
  TyIndexSeries(FBind, FIndex);
  FStacks := TySolveStacks(FOpt, FBind, FStores);
  TyApplyAxisExtents(FOpt, FBuild, FBind, FStores, FStacks, FIndex);
end;

function TAdvChartStackTest.Total(ASlot, ARow: Integer): Double;
begin
  AssertTrue('series ' + IntToStr(ASlot) + ' stacks', FStacks[ASlot].Stacked);
  Result := FStores[ASlot].GetByRaw(FStacks[ASlot].ResultCol, ARow);
end;

function TAdvChartStackTest.Over(ASlot, ARow: Integer): Double;
begin
  AssertTrue('series ' + IntToStr(ASlot) + ' stacks', FStacks[ASlot].Stacked);
  Result := FStores[ASlot].GetByRaw(FStacks[ASlot].OverCol, ARow);
end;

procedure TAdvChartStackTest.TestTwoSeriesAccumulate;
begin
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', stack: ''s'', data: [1, 2] },'
    + '{ type: ''bar'', stack: ''s'', data: [10, 20] }] }');
  AssertEquals('the bottom member is its own value', 1.0, Total(0, 0), Eps);
  AssertEquals('and it sits on nothing', True, IsNan(Over(0, 0)));
  AssertFalse('so it is drawn like an unstacked series',
    FStacks[0].HasBelow);

  AssertEquals('the second is the sum', 11.0, Total(1, 0), Eps);
  AssertEquals('and it sits on the first', 1.0, Over(1, 0), Eps);
  AssertTrue('which is what makes it a stacked bar', FStacks[1].HasBelow);

  AssertEquals('every row, not just the first', 22.0, Total(1, 1), Eps);
end;

procedure TAdvChartStackTest.TestAnEmptyStackNameIsNotAStack;
begin
  { Upstream spells this out rather than treating any string as a group, and
    says why in a comment: `stack: ''` is how a config turns stacking OFF. }
  Run('{ xAxis: { data: [''A''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', stack: '''', data: [1] },'
    + '{ type: ''bar'', stack: '''', data: [10] }] }');
  AssertFalse('an empty name does not stack', FStacks[0].Stacked);
  AssertFalse('for either of them', FStacks[1].Stacked);
  AssertEquals('and no columns were added', -1, FStacks[0].ResultCol);
end;

procedure TAdvChartStackTest.TestDifferentNamesDoNotShareAPile;
begin
  Run('{ xAxis: { data: [''A''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', stack: ''a'', data: [1] },'
    + '{ type: ''bar'', stack: ''b'', data: [10] }] }');
  AssertEquals('each is alone in its own stack', 1.0, Total(0, 0), Eps);
  AssertEquals('and so is the other', 10.0, Total(1, 0), Eps);
  AssertFalse('neither has anything below it', FStacks[1].HasBelow);
end;

procedure TAdvChartStackTest.TestTheSearchStopsAtTheNearestEligibleMember;
begin
  { NOT A SUM OF EVERYTHING BELOW. Each member adds the already-accumulated
    total of the FIRST member beneath it that qualifies, and breaks. With three
    members that is invisible -- 1+2+3 comes out the same either way -- so the
    third member here is made to skip the second, which only the break-and-add
    -one-cumulative reading gets right. }
  Run('{ xAxis: { data: [''A''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', stack: ''s'', data: [1] },'
    + '{ type: ''bar'', stack: ''s'', data: [2] },'
    + '{ type: ''bar'', stack: ''s'', data: [4] }] }');
  AssertEquals('bottom', 1.0, Total(0, 0), Eps);
  AssertEquals('middle is 2 on top of 1', 3.0, Total(1, 0), Eps);
  { 4 + the MIDDLE's cumulative 3 = 7. Summing every member below would give
    4 + 1 + 3 = 8, and adding the raw values would give 4 + 1 + 2 = 7 as well
    -- which is why the middle member's cumulative is asserted separately
    above: the two readings only diverge once one of them is pinned. }
  AssertEquals('top is 4 on top of the middle''s total', 7.0, Total(2, 0), Eps);
  AssertEquals('and it reports what it stood on', 3.0, Over(2, 0), Eps);
end;

procedure TAdvChartStackTest.TestSamesignSplitsPositivesFromNegatives;
begin
  { The default. A negative point skips every positive member below it and
    lands on the nearest negative one, so the two grow away from the baseline
    as independent piles rather than cancelling. }
  Run('{ xAxis: { data: [''A''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', stack: ''s'', data: [10] },'
    + '{ type: ''bar'', stack: ''s'', data: [-5] },'
    + '{ type: ''bar'', stack: ''s'', data: [-7] },'
    + '{ type: ''bar'', stack: ''s'', data: [3] }] }');
  AssertEquals('the first positive stands alone', 10.0, Total(0, 0), Eps);
  AssertEquals('the first negative ignores it', -5.0, Total(1, 0), Eps);
  AssertTrue('and reports nothing underneath', IsNan(Over(1, 0)));
  AssertEquals('the second negative finds the first', -12.0, Total(2, 0), Eps);
  AssertEquals('the second positive skips both negatives to reach the 10',
    13.0, Total(3, 0), Eps);
  AssertEquals('and says so', 10.0, Over(3, 0), Eps);
end;

procedure TAdvChartStackTest.TestTheOtherThreeStrategies;
begin
  { 'all' -- one pile, signs ignored. }
  Run('{ xAxis: { data: [''A''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', stack: ''s'', data: [10] },'
    + '{ type: ''bar'', stack: ''s'', stackStrategy: ''all'', data: [-4] }] }');
  AssertEquals('all: signs are ignored', 6.0, Total(1, 0), Eps);

  { 'positive' -- only a positive cumulative below is stacked onto. }
  Run('{ xAxis: { data: [''A''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', stack: ''s'', data: [-4] },'
    + '{ type: ''bar'', stack: ''s'', stackStrategy: ''positive'', data: [3] }] }');
  AssertEquals('positive: a negative below is not stacked onto',
    3.0, Total(1, 0), Eps);

  { 'negative' -- the mirror. }
  Run('{ xAxis: { data: [''A''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', stack: ''s'', data: [4] },'
    + '{ type: ''bar'', stack: ''s'', stackStrategy: ''negative'', data: [3] }] }');
  AssertEquals('negative: a positive below is not stacked onto',
    3.0, Total(1, 0), Eps);

  { READ PER SERIES, not once for the group: members of one stack may each use
    a different strategy, because upstream reads it off the target's own model
    inside the per-member loop. }
  Run('{ xAxis: { data: [''A''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', stack: ''s'', data: [10] },'
    + '{ type: ''bar'', stack: ''s'', stackStrategy: ''all'', data: [-4] },'
    + '{ type: ''bar'', stack: ''s'', data: [-2] }] }');
  AssertEquals('the middle used all', 6.0, Total(1, 0), Eps);
  AssertTrue('the last used samesign and found no negative below it',
    IsNan(Over(2, 0)));
  AssertEquals('so it stands on the baseline', -2.0, Total(2, 0), Eps);
end;

procedure TAdvChartStackTest.TestAGapStaysAGapInBothColumns;
begin
  { Upstream returns [NaN, NaN] and says why: a filled line needs stackedOver
    to be NaN as well, or the belt is drawn straight across the hole. }
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', stack: ''s'', data: [1, 2] },'
    + '{ type: ''bar'', stack: ''s'', data: [10, null] }] }');
  AssertEquals('the row with data is fine', 11.0, Total(1, 0), Eps);
  AssertTrue('a gap has no total', IsNan(Total(1, 1)));
  AssertTrue('and nothing underneath either', IsNan(Over(1, 1)));

  { A GAP BELOW IS NOT A ZERO. The series above finds nothing to stand on and
    keeps its own value rather than treating the hole as 0. }
  Run('{ xAxis: { data: [''A''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', stack: ''s'', data: [null] },'
    + '{ type: ''bar'', stack: ''s'', data: [7] }] }');
  AssertEquals('nothing was added', 7.0, Total(1, 0), Eps);
  AssertTrue('and nothing was stood on', IsNan(Over(1, 0)));
end;

procedure TAdvChartStackTest.TestCategoriesAreMatchedByNameNotByPosition;
begin
  { STACK BY CATEGORY. The two series list their categories in different
    orders, so matching by row POSITION would add the wrong numbers together --
    and every assertion here would still be a number, which is why the two
    orders differ rather than merely existing.

    A PAIR, NOT A NAMED OBJECT. `{ name: 'B', value: 20 }` does NOT put the
    datum in category B: `name` is the item's label, and on a category axis the
    category comes from the item's INDEX. The first version of this test used
    the object form, and it failed with 21 rather than 22 -- the port was right
    and the test was wrong. A two-element pair is how a datum names its own
    category. }
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', stack: ''s'', data: [[''A'', 1], [''B'', 2]] },'
    + '{ type: ''bar'', stack: ''s'', data: [[''B'', 20], [''A'', 10]]}] }');
  { Row 0 of the upper series is category B, whose lower value is 2. }
  AssertEquals('B on top of B', 22.0, Total(1, 0), Eps);
  AssertEquals('A on top of A', 11.0, Total(1, 1), Eps);

  { AND THE POSITION READING REALLY WOULD DIFFER: row 0 against row 0 is
    20 + 1 = 21, which is exactly what the object form produced. }
  AssertTrue('the two readings are not the same number here',
    Abs(Total(1, 0) - 21.0) > Eps);
end;

procedure TAdvChartStackTest.TestAValueBaseAxisStacksByRowIndex;
begin
  { A non-category base axis can only stack by index -- upstream says outright
    that stack-by-value is not supported there. }
  Run('{ xAxis: { type: ''value'' }, yAxis: {}, series: ['
    + '{ type: ''line'', stack: ''s'', data: [[1, 5], [2, 6]] },'
    + '{ type: ''line'', stack: ''s'', data: [[1, 50], [2, 60]] }] }');
  AssertEquals('row 0 to row 0', 55.0, Total(1, 0), Eps);
  AssertEquals('row 1 to row 1', 66.0, Total(1, 1), Eps);
end;

procedure TAdvChartStackTest.TestStackOrderIsReadFromTheFirstMemberOnly;
begin
  { seriesDesc reverses the pile, so the LAST declared series ends up at the
    bottom. }
  Run('{ xAxis: { data: [''A''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', stack: ''s'', stackOrder: ''seriesDesc'', data: [1] },'
    + '{ type: ''bar'', stack: ''s'', data: [10] }] }');
  AssertEquals('the last declared is now the bottom', 10.0, Total(1, 0), Eps);
  AssertEquals('and the first sits on it', 11.0, Total(0, 0), Eps);
  AssertTrue('so it is the one with something below', FStacks[0].HasBelow);

  { AND ONLY THE FIRST MEMBER IS ASKED. Setting it on a later series does
    nothing at all upstream -- the group reads `stackInfoList[0]`. A port that
    read it last-wins, or from any member that set it, would reverse here. }
  Run('{ xAxis: { data: [''A''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', stack: ''s'', data: [1] },'
    + '{ type: ''bar'', stack: ''s'', stackOrder: ''seriesDesc'', data: [10] }] }');
  AssertEquals('declaration order stands', 1.0, Total(0, 0), Eps);
  AssertEquals('because only the first member was asked',
    11.0, Total(1, 0), Eps);
end;

procedure TAdvChartStackTest.TestATimeOrCategoryValueAxisIsRefused;
begin
  { Adding two dates is not a date, and upstream refuses a time dimension as
    the stack target on exactly the same footing as an ordinal one. }
  Run('{ xAxis: { data: [''A''] }, yAxis: { type: ''time'' }, series: ['
    + '{ type: ''bar'', stack: ''s'', data: [1] },'
    + '{ type: ''bar'', stack: ''s'', data: [2] }] }');
  AssertFalse('a time value axis does not stack', FStacks[0].Stacked);

  Run('{ xAxis: { data: [''A''] }, yAxis: { type: ''category'', data: [''p''] },'
    + ' series: [{ type: ''bar'', stack: ''s'', data: [1] },'
    + '          { type: ''bar'', stack: ''s'', data: [2] }] }');
  AssertFalse('nor does a category one', FStacks[0].Stacked);
end;

procedure TAdvChartStackTest.TestOneNameStacksAcrossTwoGrids;
begin
  { SURPRISING BUT UPSTREAM'S. Value stacking is keyed on the `stack` string
    ALONE, over the whole chart: no coordinate system test, no base axis test.
    (Bar COLUMN grouping is the per-axis one, and it is a different question
    asked with the same word.) Two series in different grids sharing a name do
    accumulate, and a port that scoped stacking per axis would quietly not. }
  Run('{ grid: [{}, {}],'
    + ' xAxis: [{ gridIndex: 0, data: [''A''] }, { gridIndex: 1, data: [''A''] }],'
    + ' yAxis: [{ gridIndex: 0 }, { gridIndex: 1 }], series: ['
    + '{ type: ''bar'', xAxisIndex: 0, yAxisIndex: 0, stack: ''s'', data: [1] },'
    + '{ type: ''bar'', xAxisIndex: 1, yAxisIndex: 1, stack: ''s'', data: [10] }] }');
  AssertEquals('the second grid''s series stacks onto the first grid''s',
    11.0, Total(1, 0), Eps);
end;

procedure TAdvChartStackTest.TestTheValueAxisSpansTheTotalsNotTheValues;
var
  lo, hi: Double;
  ax: TTyAxis;
begin
  { THE FAILURE THIS PREVENTS IS SILENT. Sized from the raw values the axis
    would reach 60, while the chart draws a bar of 100 -- which simply runs off
    the top of the plot. Nothing raises. }
  Run('{ xAxis: { data: [''A''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', stack: ''s'', data: [40] },'
    + '{ type: ''bar'', stack: ''s'', data: [60] }] }');
  ax := FBuild.Grid(0).YAxis(0);
  lo := ax.Scale.GetExtent.Start;
  hi := ax.Scale.GetExtent.Stop;
  AssertTrue(Format('the axis reaches the total of 100, got %g..%g', [lo, hi]),
    hi >= 100);
  AssertTrue('and not merely the largest single value', hi >= 100);
end;

procedure TAdvChartStackTest.TestAddSafeKeepsTheDecimalsTheInputsHad;
begin
  { The reason upstream does not simply add: 0.1 + 0.2 is
    0.30000000000000004, and the axis' min and max are computed from these
    sums, so the noise escapes into the range and the tick labels. }
  AssertEquals('the classic one', 0.3, TyAddSafe(0.1, 0.2), 0);
  AssertTrue('and it really is exact, not merely close',
    TyAddSafe(0.1, 0.2) = 0.3);
  AssertEquals('the more precise operand decides',
    0.301, TyAddSafe(0.001, 0.3), 0);
  AssertEquals('whole numbers are untouched', 3.0, TyAddSafe(1, 2), 0);
  AssertTrue('a NaN operand gives NaN', IsNan(TyAddSafe(NaN, 1)));
end;

procedure TAdvChartStackTest.TestDecimalPrecisionCountsWhatIsWritten;
begin
  AssertEquals('an integer has none', 0, TyDecimalPrecision(100));
  AssertEquals('one place', 1, TyDecimalPrecision(0.5));
  AssertEquals('three', 3, TyDecimalPrecision(100.123));
  AssertEquals('a negative is measured the same', 2, TyDecimalPrecision(-1.25));
  AssertEquals('NaN has none to count', 0, TyDecimalPrecision(NaN));
end;

initialization
  RegisterTest(TAdvChartStackTest);
end.
