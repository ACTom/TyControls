unit test.advchart.barlayout;
{$mode objfpc}{$H+}
{ The bar width solver: how wide each bar is and where in its band it sits.

  ASSERTED AGAINST THE FORMULA, NOT AGAINST A SCREENSHOT. Every expected number
  here is derived from ECharts 6.1.0's own arithmetic and written out, because
  the whole reason this unit exists is that the friendly summaries of that
  arithmetic -- the option reference, this repo's generated catalog, and the
  first version of Marks.pas -- all state a default that the source does not
  have. A test that asked the solver what it thought would agree with anything.

  The numbers, for a band of B with everything at its defaults (barGap 10%,
  barCategoryGap = max(35 - columns*4, 15)%):
    columns  gap    autoWidth = (1-gap)B / (n + (n-1)*0.1)
      1      31%    0.69      B
      2      27%    0.347619  B
      3      23%    0.240625  B
      4      19%    0.18837209B }
interface
uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Coord, tyControls.AdvChart.Data,
  tyControls.AdvChart.Builder, tyControls.AdvChart.Series,
  tyControls.AdvChart.BarLayout;

type
  TAdvChartBarLayoutTest = class(TTestCase)
  private
    FOpt: TTyChartOption;
    FBuild: TTyChartBuild;
    FIndex: TTyAxisSeriesIndex;
    FBind: TTySeriesBindingArray;
    FStores: array of TTyDataStore;
    FCols: TTyBarColumnArray;
    procedure SetUp; override;
    procedure TearDown; override;
    { Option text -> the whole pure pipeline -> FCols. The plot is 600x400 at
      the origin, and the layout phase is NOT run: these tests want a band they
      can compute by hand, not one shrunk by however wide the labels came out
      on this machine's fonts. }
    procedure Run(const AText: string);
    { The band the solver saw for series ASlot. }
    function Band(ASlot: Integer): Double;
    { The plot the grid actually got. Not 600: the grid's own box defaults
      inset it, and hard-coding what that comes to would pin a GRID default in
      a file about bar widths -- so the band is stated as a relationship to
      this, once, and every width below is a fraction of the band. }
    function Plot: TTyRectF;
  published
    procedure TestALoneBarLeavesTheGapUpstreamComputes;
    procedure TestTwoSeriesSitSideBySideAndTheGroupStaysCentred;
    procedure TestTheCategoryGapShrinksAsColumnsAreAdded;
    procedure TestALineOnTheSameAxisIsNotCountedAsABar;
    procedure TestAnExplicitBarWidthIsHonouredInPixelsAndPercent;
    procedure TestBarWidthIsFirstWinsInsideOneColumn;
    procedure TestBarMaxWidthClampsAndBarMinWidthOutranksIt;
    procedure TestBarMinWidthIsLastWinsEvenWhenTheLastSaysNothing;
    procedure TestZeroIsIgnoredForWidthAndHonouredForCategoryGap;
    procedure TestBarGapMinus100PutsEveryColumnInTheSamePlace;
    procedure TestBarGapAndCategoryGapAreLastWinsAcrossTheAxis;
    procedure TestSeriesSharingAStackShareOneColumn;
    procedure TestSeriesOnDifferentAxesAreSolvedApart;
    procedure TestABarOnAValueAxisGetsABandFromTheDataGaps;
    procedure TestADerivedBandNeverFallsBelowOnePixel;
    procedure TestTheDerivedBandHandlesTheDegenerateCases;
    procedure TestBarMinHeightAndBorderRadiusReachTheColumn;
  end;

implementation

const
  Eps = 1e-6;

procedure TAdvChartBarLayoutTest.SetUp;
begin
  inherited SetUp;
  FOpt := TTyChartOption.Create;
  FIndex := TTyAxisSeriesIndex.Create;
  FBuild := nil;
end;

procedure TAdvChartBarLayoutTest.TearDown;
var i: Integer;
begin
  { A store borrows the axis' category list, so every store goes before the
    build that owns the axes. }
  for i := 0 to High(FStores) do
    FStores[i].Free;
  FStores := nil;
  FCols := nil;
  FreeAndNil(FIndex);
  FreeAndNil(FBuild);
  FreeAndNil(FOpt);
  inherited TearDown;
end;

procedure TAdvChartBarLayoutTest.Run(const AText: string);
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
  TyApplyAxisExtents(FOpt, FBuild, FBind, FStores, FIndex);
  { NO LAYOUT PHASE. Phase A already gives every cartesian the grid's outer
    rect, so the band is exactly 600/categories and every expected number below
    is arithmetic rather than a measurement of this machine's fonts. Phase C
    would shrink the plot to fit the labels, which is right for a chart and
    useless for pinning a formula. }
  FCols := TySolveBarLayout(FOpt, FBuild, FBind, FStores, FIndex);
end;

function TAdvChartBarLayoutTest.Plot: TTyRectF;
begin
  Result := FBuild.Grid(0).PlotRect;
end;

function TAdvChartBarLayoutTest.Band(ASlot: Integer): Double;
begin
  AssertTrue('series ' + IntToStr(ASlot) + ' was solved', FCols[ASlot].Solved);
  Result := FCols[ASlot].BandWidth;
end;

procedure TAdvChartBarLayoutTest.TestALoneBarLeavesTheGapUpstreamComputes;
begin
  { 0.69, NOT 0.8. There is no fixed default barCategoryGap in the source; it
    is max(35 - columns*4, 15)%, which for one column is 31%. The 20% that the
    option reference and this repo's catalog both state is stale documentation,
    and the first version of Marks.pas copied it. }
  Run('{ xAxis: { data: [''A'', ''B'', ''C''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [1, 2, 3] }] }');
  { THE BAND IS THE PLOT OVER THE CATEGORIES -- stated once, here, as a
    relationship rather than a number, so a change in how bands are measured
    fails this and a change in the grid's default box does not. }
  AssertEquals('the band is the plot over three categories',
    TyRectFWidth(Plot) / 3, Band(0), Eps);
  AssertEquals('one column takes 0.69 of it',
    0.69 * Band(0), FCols[0].Width, 1e-9);
  AssertTrue('which is not 0.8', Abs(FCols[0].Width - 0.8 * Band(0)) > 1);
  AssertEquals('and is centred', -0.69 * Band(0) / 2, FCols[0].Offset, 1e-9);
end;

procedure TAdvChartBarLayoutTest.TestTwoSeriesSitSideBySideAndTheGroupStaysCentred;
var w: Double;
begin
  { THE CASE THE WHOLE UNIT EXISTS FOR. Before it, two bar series on one axis
    drew in exactly the same place -- one hid the other, and the chart looked
    like it had one series. }
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', data: [1, 2] }, { type: ''bar'', data: [3, 4] }] }');
  w := 0.73 / 2.1 * Band(0);   { two columns: gap 27%, barGap 10% }
  AssertEquals('two columns share the band', w, FCols[0].Width, 1e-9);
  AssertEquals('equally', w, FCols[1].Width, 1e-9);
  AssertEquals('the first is left of centre',
    -0.365 * Band(0), FCols[0].Offset, 1e-9);
  AssertEquals('the second right of it',
    -0.365 * Band(0) + w * 1.1, FCols[1].Offset, 1e-9);

  { THE GROUP IS CENTRED ON THE BAND, which is the property that survives every
    combination of the knobs and is therefore the one worth stating: the left
    edge of the first and the right edge of the last are equal and opposite. }
  AssertEquals('the group straddles the band centre',
    -FCols[0].Offset, FCols[1].Offset + FCols[1].Width, 1e-9);
  AssertTrue('and the two do not overlap',
    FCols[1].Offset >= FCols[0].Offset + FCols[0].Width - Eps);
end;

procedure TAdvChartBarLayoutTest.TestTheCategoryGapShrinksAsColumnsAreAdded;
var one: string;
begin
  { max(35 - columns*4, 15)%: more columns means a smaller gap between groups,
    or the columns get too thin to see. Asserting three widths at once because
    the interesting part is the PROGRESSION -- a solver that used a fixed gap
    would still get one of them right. }
  one := '{ type: ''bar'', data: [1, 2] }';
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {}, series: ['
    + one + ',' + one + ',' + one + '] }');
  AssertEquals('three columns: 23% gap',
    0.77 / 3.2 * Band(0), FCols[0].Width, 1e-9);

  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {}, series: ['
    + one + ',' + one + ',' + one + ',' + one + '] }');
  AssertEquals('four columns: 19% gap',
    0.81 / 4.3 * Band(0), FCols[0].Width, 1e-9);

  { THE FLOOR NEEDS SIX. `max(35 - n*4, 15)` only starts clamping when
    35 - n*4 drops below 15, which is at n = 6 (11% -> 15%); at five it is
    exactly 15 either way. A test that stopped at four -- as this one did --
    left the floor entirely unpinned, and a version without it passed. }
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {}, series: ['
    + one + ',' + one + ',' + one + ',' + one + ',' + one + ',' + one + '] }');
  AssertEquals('six columns are floored at 15%, not 11%',
    0.85 / 6.5 * Band(0), FCols[0].Width, 1e-9);
  AssertTrue('which is narrower than an unclamped 11% would give',
    FCols[0].Width < 0.89 / 6.5 * Band(0) - Eps);
end;

procedure TAdvChartBarLayoutTest.TestALineOnTheSameAxisIsNotCountedAsABar;
begin
  { THE FAILURE THIS PREVENTS IS INVISIBLE: counting the line would make the
    bar half as wide on a chart that looks otherwise correct. The index buckets
    by series type precisely so the solver cannot make that mistake. }
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', data: [1, 2] }, { type: ''line'', data: [3, 4] }] }');
  AssertEquals('the bar is solved as the only column',
    0.69 * Band(0), FCols[0].Width, 1e-9);
  AssertFalse('and the line gets no column at all', FCols[1].Solved);
end;

procedure TAdvChartBarLayoutTest.TestAnExplicitBarWidthIsHonouredInPixelsAndPercent;
begin
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', barWidth: 20, data: [1, 2] }] }');
  AssertEquals('a number is pixels', 20.0, FCols[0].Width, Eps);
  AssertEquals('and it is still centred', -10.0, FCols[0].Offset, Eps);

  { A PERCENT IS OF THE BAND, not of the plot -- barWidth, barMaxWidth,
    barMinWidth and barCategoryGap all resolve against the band; only barGap
    resolves against 1. }
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', barWidth: ''50%'', data: [1, 2] }] }');
  AssertEquals('half the band', 0.5 * Band(0), FCols[0].Width, Eps);
end;

procedure TAdvChartBarLayoutTest.TestBarWidthIsFirstWinsInsideOneColumn;
begin
  { WITHIN A COLUMN the FIRST series that names a barWidth is heard and the
    rest are ignored -- the opposite of barGap and barCategoryGap, which are
    last-wins. Upstream guards the assignment with `!stackItem.width`, and it
    only shows up when two series share a `stack`, which is why nothing here
    noticed until a mutant made it last-wins and lived. }
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', stack: ''s'', barWidth: 40, data: [1, 2] },'
    + '{ type: ''bar'', stack: ''s'', barWidth: 12, data: [3, 4] }] }');
  AssertEquals('the first barWidth in the column stands',
    40.0, FCols[0].Width, Eps);
  AssertEquals('and its stack-mate gets the same column',
    40.0, FCols[1].Width, Eps);
end;

procedure TAdvChartBarLayoutTest.TestBarMaxWidthClampsAndBarMinWidthOutranksIt;
begin
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', barMaxWidth: 30, data: [1, 2] }] }');
  AssertEquals('the auto width is clamped down', 30.0, FCols[0].Width, Eps);

  { MIN OUTRANKS MAX, and the source says why: minWidth decides whether the bar
    is VISIBLE at all, so it is clamped by neither maxWidth nor the band. Bars
    are allowed to overlap rather than disappear. }
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', barMaxWidth: 10, barMinWidth: 40, data: [1, 2] }] }');
  AssertEquals('min wins over max', 40.0, FCols[0].Width, Eps);

  { AND OVER AN EXPLICIT barWidth, the way CSS min-width outranks width. }
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', barWidth: 5, barMinWidth: 25, data: [1, 2] }] }');
  AssertEquals('min wins over barWidth', 25.0, FCols[0].Width, Eps);
end;

procedure TAdvChartBarLayoutTest.TestBarMinWidthIsLastWinsEvenWhenTheLastSaysNothing;
begin
  { THE ONE THAT LOOKS LIKE A BUG AND IS NOT. Upstream reads barMinWidth as
    `get('barMinWidth') || 1`, so the value is never null and the per-column
    assignment always fires -- which means a later series in the same stack
    that sets nothing OVERWRITES an earlier one's explicit barMinWidth with the
    default 1. Reading "unset" as "leave what is there" is the natural port and
    the wrong one, and it draws a wider bar than the chart being copied. }
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', stack: ''s'', barMaxWidth: 5, barMinWidth: 40,'
    + '  data: [1, 2] },'
    + '{ type: ''bar'', stack: ''s'', data: [3, 4] }] }');
  AssertEquals('the silent second series resets the minimum to 1',
    5.0, FCols[0].Width, Eps);

  { The same two series the other way round: now the explicit 40 is last and it
    stands, so the difference really is the ORDER and not the presence. }
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', stack: ''s'', barMaxWidth: 5, data: [3, 4] },'
    + '{ type: ''bar'', stack: ''s'', barMinWidth: 40, data: [1, 2] }] }');
  AssertEquals('an explicit minimum stated last wins',
    40.0, FCols[0].Width, Eps);
end;

procedure TAdvChartBarLayoutTest.TestZeroIsIgnoredForWidthAndHonouredForCategoryGap;
begin
  { TWO KNOBS, TWO MEANINGS FOR ZERO, and upstream really does treat them
    differently: barWidth is tested for truthiness, so 0 is ignored, while
    barCategoryGap is tested against null, so 0 is a real instruction. Reading
    both the same way gets one of them wrong whichever way you choose. }
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', barWidth: 0, data: [1, 2] }] }');
  AssertEquals('barWidth 0 is ignored, so the auto width stands',
    0.69 * Band(0), FCols[0].Width, 1e-9);

  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', barCategoryGap: 0, data: [1, 2] }] }');
  AssertEquals('barCategoryGap 0 fills the whole band',
    Band(0), FCols[0].Width, Eps);
end;

procedure TAdvChartBarLayoutTest.TestBarGapMinus100PutsEveryColumnInTheSamePlace;
begin
  { NOT SPECIAL-CASED ANYWHERE -- it falls out of the arithmetic. barGap of -1
    makes the denominator n + (n-1)(-1) = 1, so every column gets the full
    remaining width, and the offset step becomes width*(1-1) = 0, so they all
    land on the same offset. That is how a pictorialBar sits on its bar. }
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', barGap: ''-100%'', data: [1, 2] },'
    + '{ type: ''bar'', data: [3, 4] }] }');
  AssertEquals('both columns are full width',
    FCols[0].Width, FCols[1].Width, Eps);
  AssertEquals('and both sit in the same place',
    FCols[0].Offset, FCols[1].Offset, Eps);
  AssertEquals('which is the band less the two-column gap',
    0.73 * Band(0), FCols[0].Width, 1e-9);
end;

procedure TAdvChartBarLayoutTest.TestBarGapAndCategoryGapAreLastWinsAcrossTheAxis;
begin
  { THESE READ PER-SERIES AND ACT PER-AXIS, and upstream's tie-break is
    inconsistent on purpose: barGap and barCategoryGap are last-wins, while the
    private defaultBarGap is seeded from the first series only. Copying the
    inconsistency is the only way two charts of the same option agree. }
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', barCategoryGap: ''50%'', data: [1, 2] },'
    + '{ type: ''bar'', barCategoryGap: 0, data: [3, 4] }] }');
  AssertEquals('the last series'' category gap is the one used',
    Band(0) / 2.1, FCols[0].Width, 1e-9);
end;

procedure TAdvChartBarLayoutTest.TestSeriesSharingAStackShareOneColumn;
begin
  { COLUMNS, NOT SERIES. Two series naming one stack are ONE column: same
    width, same offset. Their values accumulating along the value axis is the
    separate stacking row and is not done -- so today they draw over each
    other, which is the right column and the wrong values. }
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {}, series: ['
    + '{ type: ''bar'', stack: ''s'', data: [1, 2] },'
    + '{ type: ''bar'', stack: ''s'', data: [3, 4] },'
    + '{ type: ''bar'', data: [5, 6] }] }');
  AssertEquals('the two stacked series get one width',
    FCols[0].Width, FCols[1].Width, Eps);
  AssertEquals('and one offset', FCols[0].Offset, FCols[1].Offset, Eps);
  AssertEquals('so the axis has TWO columns, not three',
    0.73 / 2.1 * Band(0), FCols[0].Width, 1e-9);
  AssertTrue('and the unstacked one is elsewhere',
    Abs(FCols[2].Offset - FCols[0].Offset) > 1);
end;

procedure TAdvChartBarLayoutTest.TestSeriesOnDifferentAxesAreSolvedApart;
begin
  { A SECOND GRID IS A SECOND BAND. Solving the whole chart at once would make
    a series widen because an unrelated chart beside it lost one. }
  Run('{ grid: [{}, {}],'
    + ' xAxis: [{ gridIndex: 0, data: [''A'', ''B''] },'
    + '         { gridIndex: 1, data: [''A'', ''B'', ''C'', ''D''] }],'
    + ' yAxis: [{ gridIndex: 0 }, { gridIndex: 1 }], series: ['
    + '{ type: ''bar'', xAxisIndex: 0, yAxisIndex: 0, data: [1, 2] },'
    + '{ type: ''bar'', xAxisIndex: 1, yAxisIndex: 1, data: [1, 2, 3, 4] }] }');
  AssertTrue('both were solved', FCols[0].Solved and FCols[1].Solved);
  AssertTrue('and they did not share a band',
    Abs(FCols[0].BandWidth - FCols[1].BandWidth) > 1);
  AssertEquals('each is a lone column in its own band',
    0.69, FCols[0].Width / FCols[0].BandWidth, 1e-9);
  AssertEquals('both of them',
    0.69, FCols[1].Width / FCols[1].BandWidth, 1e-9);
end;

procedure TAdvChartBarLayoutTest.TestABarOnAValueAxisGetsABandFromTheDataGaps;
begin
  { A VALUE AXIS HAS NO BANDS, and a bar still has to be some width. Before
    this, such a bar got a zero-width rect: it drew nothing and was still
    hit-testable, which is invisible and in the way at the same time. }
  Run('{ xAxis: { type: ''value'', min: 0, max: 10 }, yAxis: {}, series: ['
    + '{ type: ''bar'', data: [[1, 5], [2, 6], [3, 7]] }] }');
  AssertTrue('it was solved at all', FCols[0].Solved);
  AssertTrue('with a real band: ' + FloatToStr(FCols[0].BandWidth),
    FCols[0].BandWidth > 1);
  AssertTrue('and a real width', FCols[0].Width > 1);
  { The gaps are all 1 and the axis spans 10, so the band is a tenth of the
    plot -- the heuristic doing exactly what it says. }
  AssertEquals('the band is one data gap in pixels',
    TyRectFWidth(Plot) / 10, FCols[0].BandWidth, Eps);
end;

procedure TAdvChartBarLayoutTest.TestADerivedBandNeverFallsBelowOnePixel;
begin
  { DATA MUCH DENSER THAN THE AXIS IS WIDE. Gaps of 1 over a span of 100000
    give a band far under a pixel, and everything downstream divides by it.
    Upstream passes `min: 1` to calcBandWidth for exactly this; without the
    floor the bars are sub-pixel and the chart looks empty while every number
    in it is finite and plausible. }
  Run('{ xAxis: { type: ''value'', min: 0, max: 100000 }, yAxis: {}, series: ['
    + '{ type: ''bar'', data: [[1, 5], [2, 6], [3, 7]] }] }');
  AssertTrue('the raw band would be under a pixel',
    TyRectFWidth(Plot) / 100000 < 1);
  AssertEquals('so it is floored at one', 1.0, FCols[0].BandWidth, Eps);
  AssertTrue('and the bar still has some width', FCols[0].Width > 0);
end;

procedure TAdvChartBarLayoutTest.TestTheDerivedBandHandlesTheDegenerateCases;
begin
  AssertEquals('the smallest positive gap wins, not the first',
    100.0 / 10 * 1, TyDerivedBandWidth(100, 10, [0.0, 5.0, 6.0]), Eps);
  AssertEquals('order does not matter',
    100.0 / 10 * 1, TyDerivedBandWidth(100, 10, [6.0, 0.0, 5.0]), Eps);
  { DUPLICATES ARE ORDINARY -- two series reporting the same x -- and a zero
    gap would collapse every bar to nothing, so only strictly positive gaps
    count. }
  AssertEquals('a repeated value is not a zero gap',
    100.0 / 10 * 5, TyDerivedBandWidth(100, 10, [5.0, 5.0, 0.0]), Eps);
  { Nothing to measure: upstream falls back to 80% of the whole span. }
  AssertEquals('one distinct value falls back to 0.8 of the span',
    80.0, TyDerivedBandWidth(100, 10, [5.0, 5.0]), Eps);
  AssertEquals('and a single datum too',
    80.0, TyDerivedBandWidth(100, 10, [5.0]), Eps);
  AssertTrue('a degenerate axis answers NaN rather than a number',
    IsNan(TyDerivedBandWidth(100, 0, [1.0, 2.0])));
  AssertTrue('and NaN data is skipped, not counted as a value',
    IsNan(TyDerivedBandWidth(100, 10, [NaN, NaN])));
end;

procedure TAdvChartBarLayoutTest.TestBarMinHeightAndBorderRadiusReachTheColumn;
begin
  { Both are per-series and both are read here rather than in the renderer, so
    the renderer has one place to look. }
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {}, series: [{ type: ''bar'','
    + ' barMinHeight: 4, itemStyle: { borderRadius: 6 }, data: [1, 2] }] }');
  AssertEquals('barMinHeight came through', 4.0, FCols[0].MinHeightPx, Eps);
  AssertEquals('and the corner radius', 6.0, FCols[0].RadiusPx, Eps);

  { A chart that sets neither must get zero for both, or every bar would be
    quietly rounded. }
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  AssertEquals('nothing set means no minimum', 0.0, FCols[0].MinHeightPx, Eps);
  AssertEquals('and square corners', 0.0, FCols[0].RadiusPx, Eps);
end;

initialization
  RegisterTest(TAdvChartBarLayoutTest);
end.
