unit test.advchart.series;
{$mode objfpc}{$H+}
{ Series types, binding, and the axis-to-series index.

  THE POINT OF THIS UNIT is the option in TestTheHeadlineCase: a bar and a line
  on one category axis, the line on a SECOND y axis. Every way that can silently
  go wrong is a separate test below, because the failures do not look like
  failures -- a secondary axis bound to the wrong pair still draws, still gets
  ticks, and shows the primary axis' numbers.

  Two assertions here are about OBJECT IDENTITY rather than values, and that is
  deliberate. A binding that returns an equal-looking axis is not the same as
  one that returns the axis the coordinate system will actually map through, and
  only identity can tell them apart. }
interface
uses Classes, SysUtils, Math, fpjson, fpcunit, testregistry,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Data, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Builder,
     tyControls.AdvChart.Series;
type
  TAdvChartSeriesTest = class(TTestCase)
  private
    FOpt: TTyChartOption;
    FBuild: TTyChartBuild;
    FIndex: TTyAxisSeriesIndex;
    FStores: array of TTyDataStore;
    FBind: TTySeriesBindingArray;
    procedure SetUp; override;
    procedure TearDown; override;
    { Build, bind, fill every series' store, index and apply extents. }
    procedure Run(const AText: string);
  published
    { ---- the type table ---- }
    procedure TestTheBuiltinTypesAreAllThere;
    procedure TestTypeFactsComeFromTheSourceNotTheCatalog;
    procedure TestRegisteringTwiceReplaces;
    procedure TestAnUnknownTypeIsNotFound;
    { ---- binding ---- }
    procedure TestABarBindsToTheFirstPair;
    procedure TestASecondaryAxisBindsToItsOwnPair;
    procedure TestTheSameCallGivesTheSameCoordinateSystem;
    procedure TestAMissingTypeIsAHoleNotAShift;
    procedure TestAnUnknownTypeIsAHoleToo;
    procedure TestAPieResolvesWithNoAxes;
    procedure TestAnAxisThatDoesNotExistDoesNotBind;
    procedure TestAStrayPolarIndexIsNotRead;
    procedure TestAnUnbuiltCoordinateSystemSaysSo;
    { ---- the base axis ---- }
    procedure TestTheCategoryAxisIsTheBase;
    procedure TestATimeAxisIsTheBaseWhenNothingIsCategorical;
    procedure TestWithNeitherTheHorizontalAxisIsTheBase;
    procedure TestACategoryYAxisBeatsATimeXAxis;
    { ---- the two populations ---- }
    procedure TestBothPopulationsOnOneOption;
    procedure TestAKeyedBucketHoldsOnlyItsOwnType;
    procedure TestAxisKeysDoNotCollide;
    procedure TestAHoleIsInertInBothPopulations;
    procedure TestAValueAxisGetsNoKeyedBucket;
    procedure TestAxesAreResolvedByNameNotBySlot;
    { ---- axis ranges ---- }
    procedure TestEachValueAxisGetsItsOwnRange;
    procedure TestAnAxisIncludesZeroUnlessToldToFit;
    procedure TestACategoryAxisRangeIsNotTouchedByData;
    procedure TestEachAxisUnionsItsOwnColumn;
    { ---- end to end ---- }
    procedure TestTheHeadlineCase;
  end;
implementation

procedure TAdvChartSeriesTest.SetUp;
begin
  inherited SetUp;
  FOpt := TTyChartOption.Create;
  FIndex := TTyAxisSeriesIndex.Create;
  FBuild := nil;
end;

procedure TAdvChartSeriesTest.TearDown;
var i: Integer;
begin
  { Order is a contract, not a habit: a store BORROWS the axis' category list,
    so every store has to go before the build that owns the axes. }
  for i := 0 to High(FStores) do
    FStores[i].Free;
  FStores := nil;
  FreeAndNil(FIndex);
  FreeAndNil(FBuild);
  FreeAndNil(FOpt);
  inherited TearDown;
end;

procedure TAdvChartSeriesTest.Run(const AText: string);
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
  TyIndexSeries(FBind, FIndex);
  TyApplyAxisExtents(FOpt, FBuild, FBind, FStores, FIndex);
end;

{ ============================ the type table ============================ }

procedure TAdvChartSeriesTest.TestTheBuiltinTypesAreAllThere;
var info: TTySeriesTypeInfo;
begin
  AssertEquals('twenty-three types', 23, TySeriesTypeCount);
  AssertTrue(TySeriesFindType('line', info));
  AssertTrue(TySeriesFindType('candlestick', info));
  AssertTrue(TySeriesFindType('sunburst', info));
end;

procedure TAdvChartSeriesTest.TestTypeFactsComeFromTheSourceNotTheCatalog;
var info: TTySeriesTypeInfo;
begin
  { Six rows where the generated catalog and the source disagree. The catalog
    transcribes an upstream documentation bug; the source is what the renderer
    does, and these are the rows a chart would silently get wrong. }
  AssertTrue(TySeriesFindType('radar', info));
  AssertEquals('the catalog has no node for this at all', 'radar', info.DefaultCoordSys);
  AssertTrue(TySeriesFindType('graph', info));
  AssertEquals('the catalog says none', 'view', info.DefaultCoordSys);
  AssertTrue(TySeriesFindType('pie', info));
  AssertEquals('absent, which is not the same as none', '', info.DefaultCoordSys);
  AssertTrue('and it is laid out into a box', info.Usage = scuBox);
  AssertTrue(TySeriesFindType('tree', info));
  AssertTrue('the catalog says data', info.Usage = scuBox);
  AssertEquals('Tree', info.Companion);
  { An empty renders-on list is a real fact, not a gap: the scatter renderer has
    no coordinate-system branch and works against anything that maps a point. }
  AssertTrue(TySeriesFindType('scatter', info));
  AssertEquals('coordinate-system agnostic', 0, Length(info.RendersOn));
  AssertTrue(TySeriesFindType('bar', info));
  AssertEquals('while bar gates on exactly two', 2, Length(info.RendersOn));
end;

procedure TAdvChartSeriesTest.TestRegisteringTwiceReplaces;
var info: TTySeriesTypeInfo;
begin
  { A design-time reload must not accumulate stale entries. }
  info := Default(TTySeriesTypeInfo);
  info.Name := 'line';
  info.DefaultCoordSys := 'polar';
  TySeriesRegisterType(info);
  try
    AssertEquals('still twenty-three', 23, TySeriesTypeCount);
    AssertTrue(TySeriesFindType('line', info));
    AssertEquals('polar', info.DefaultCoordSys);
  finally
    TySeriesClearTypes;
    TySeriesRegisterBuiltinTypes;
  end;
  AssertTrue(TySeriesFindType('line', info));
  AssertEquals('cartesian2d', info.DefaultCoordSys);
end;

procedure TAdvChartSeriesTest.TestAnUnknownTypeIsNotFound;
var info: TTySeriesTypeInfo;
begin
  AssertFalse(TySeriesFindType('bard', info));
  AssertEquals('', info.Name);
end;

{ ============================ binding ============================ }

procedure TAdvChartSeriesTest.TestABarBindsToTheFirstPair;
begin
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  AssertTrue('resolved', FBind[0].Resolved);
  AssertTrue('and on axes', FBind[0].HasAxes);
  AssertEquals('cartesian2d', FBind[0].CoordSysName);
  AssertTrue('the x axis is the build''s', FBind[0].XAxis = FBuild.Axis('xAxis', 0));
  AssertTrue('and the y axis too', FBind[0].YAxis = FBuild.Axis('yAxis', 0));
end;

procedure TAdvChartSeriesTest.TestASecondaryAxisBindsToItsOwnPair;
var p: TTyPointF;
begin
  { THE headline. A binding that returned an equal-looking axis would pass a
    value assertion and still map through the wrong one, so this asserts the
    coordinate system OBJECT -- and then a pixel, because that is what a reader
    would actually see go wrong. }
  Run('{ xAxis: { data: [''A'', ''B'', ''C''] }, yAxis: [{}, {}],'
    + ' series: [{ type: ''bar'', data: [1, 2, 3] },'
    + ' { type: ''line'', yAxisIndex: 1, data: [100, 200, 300] }] }');
  AssertTrue('the line is on the SECOND y axis',
    FBind[1].YAxis = FBuild.Axis('yAxis', 1));
  AssertTrue('and its coordinate system is the pair x0 y1',
    FBind[1].Cart = FBuild.CartesianAt(0, 1));
  AssertFalse('which is not the bar''s', FBind[1].Cart = FBind[0].Cart);
  { Both axes end up ranged 0..3 and 0..300, so the bar''s 1 and the line''s 100
    are each a third of their own axis and land on the SAME pixel. Bound to the
    wrong axis the line would be thousands of pixels away. }
  p := FBind[1].Cart.DataToPoint([1, 100]);
  AssertTrue('the line''s point is inside the plot',
    (p.Y > FBuild.Grid(0).OuterRect.Top - 1) and (p.Y < FBuild.Grid(0).OuterRect.Bottom + 1));
  AssertEquals('and on the same pixel as the bar''s 1',
    FBind[0].Cart.DataToPoint([1, 1]).Y, p.Y, 1e-6);
end;

procedure TAdvChartSeriesTest.TestTheSameCallGivesTheSameCoordinateSystem;
var again: TTySeriesBindingArray;
begin
  { Paint and hit test both go through this object. Two lookups that each build
    their own answer can disagree; identity is the only thing that pins it. }
  Run('{ xAxis: {}, yAxis: [{}, {}], series: [{ type: ''line'', yAxisIndex: 1, data: [1] }] }');
  again := TyBindSeries(FOpt, FBuild);
  AssertTrue('the same instance', again[0].Cart = FBind[0].Cart);
end;

procedure TAdvChartSeriesTest.TestAMissingTypeIsAHoleNotAShift;
begin
  { Upstream drops such a series and leaves a hole. Ours keeps the SLOT: a hole
    that renumbered would move whatever a callback or a hit test was pointing
    at, and nothing on screen would say so. }
  Run('{ xAxis: {}, yAxis: {}, series: [{ data: [1, 2] }, { type: ''line'', data: [3, 4] }] }');
  AssertEquals('both slots are still there', 2, Length(FBind));
  AssertFalse('the first did not resolve', FBind[0].Resolved);
  AssertEquals('but it kept its index', 0, FBind[0].SeriesIndex);
  AssertTrue('and the second is unshifted', FBind[1].Resolved);
  AssertEquals(1, FBind[1].SeriesIndex);
  AssertTrue('with a diagnostic', FBuild.DiagnosticCount > 0);
end;

procedure TAdvChartSeriesTest.TestAnUnknownTypeIsAHoleToo;
begin
  Run('{ xAxis: {}, yAxis: {}, series: [{ type: ''bard'', data: [1] }] }');
  AssertFalse(FBind[0].Resolved);
  AssertEquals('bard', FBind[0].SeriesType);
  AssertTrue(FBuild.DiagnosticCount > 0);
end;

procedure TAdvChartSeriesTest.TestAPieResolvesWithNoAxes;
begin
  { Resolved and deliberately on no axis. Treating that as a failure would make
    every pie a permanent error state, which is what a single IsBound boolean
    would have forced. }
  Run('{ series: [{ type: ''pie'', data: [1, 2, 3] }] }');
  AssertTrue('resolved', FBind[0].Resolved);
  AssertFalse('and on no axis', FBind[0].HasAxes);
  AssertTrue('laid out into a box', FBind[0].Usage = scuBox);
  AssertTrue('with no coordinate system', FBind[0].Cart = nil);
  AssertEquals('and nothing to complain about', 0, FBuild.DiagnosticCount);
end;

procedure TAdvChartSeriesTest.TestAnAxisThatDoesNotExistDoesNotBind;
begin
  Run('{ xAxis: {}, yAxis: {}, series: [{ type: ''line'', yAxisIndex: 3, data: [1] }] }');
  AssertFalse(FBind[0].Resolved);
  AssertTrue('and it is not quietly on y0', FBind[0].YAxis = nil);
  AssertTrue(FBuild.DiagnosticCount > 0);
end;

procedure TAdvChartSeriesTest.TestAStrayPolarIndexIsNotRead;
begin
  { The catalog's default for polarIndex is 0, so an ungated read finds a polar
    axis every single time -- and a plain cartesian line would then widen a
    polar axis' range. Only the named system's keys are consulted. }
  Run('{ xAxis: {}, yAxis: {},'
    + ' series: [{ type: ''line'', polarIndex: 0, data: [1, 2] }] }');
  AssertTrue('still a cartesian', FBind[0].Resolved);
  AssertEquals('cartesian2d', FBind[0].CoordSysName);
  AssertTrue(FBind[0].Cart = FBuild.CartesianAt(0, 0));
end;

procedure TAdvChartSeriesTest.TestAnUnbuiltCoordinateSystemSaysSo;
begin
  { A series naming polar resolves to nothing rather than falling back to the
    cartesian it did not ask for. }
  Run('{ xAxis: {}, yAxis: {},'
    + ' series: [{ type: ''line'', coordinateSystem: ''polar'', data: [1] }] }');
  AssertFalse(FBind[0].Resolved);
  AssertEquals('polar', FBind[0].CoordSysName);
  AssertTrue(FBuild.DiagnosticCount > 0);
end;

{ ============================ the base axis ============================ }

procedure TAdvChartSeriesTest.TestTheCategoryAxisIsTheBase;
begin
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  AssertTrue('the category x axis', FBind[0].BaseAxis = FBuild.Axis('xAxis', 0));
  AssertTrue('and the value is the other', FBind[0].ValueAxis = FBuild.Axis('yAxis', 0));
end;

procedure TAdvChartSeriesTest.TestATimeAxisIsTheBaseWhenNothingIsCategorical;
begin
  { A time axis is an INTERVAL scale here, so a rule that tested the scale's
    class would silently skip this and hand back x on every time chart -- which
    is right by accident when time is on x, and wrong whenever it is not. }
  Run('{ xAxis: {}, yAxis: { type: ''time'' },'
    + ' series: [{ type: ''line'', data: [[1, 2]] }] }');
  AssertTrue('the time y axis', FBind[0].BaseAxis = FBuild.Axis('yAxis', 0));
  AssertTrue(FBind[0].ValueAxis = FBuild.Axis('xAxis', 0));
end;

procedure TAdvChartSeriesTest.TestWithNeitherTheHorizontalAxisIsTheBase;
begin
  Run('{ xAxis: {}, yAxis: {}, series: [{ type: ''scatter'', data: [[1, 2]] }] }');
  AssertTrue(FBind[0].BaseAxis = FBuild.Axis('xAxis', 0));
end;

procedure TAdvChartSeriesTest.TestACategoryYAxisBeatsATimeXAxis;
begin
  { Ordinal is preferred over time wherever it sits, so a horizontal bar chart
    with a time x axis is still based on its category y axis. A single pass
    scoring axes in order would answer x here. }
  Run('{ xAxis: { type: ''time'' }, yAxis: { data: [''A'', ''B''] },'
    + ' series: [{ type: ''bar'', data: [[1, 0]] }] }');
  AssertTrue('the category y axis', FBind[0].BaseAxis = FBuild.Axis('yAxis', 0));
end;

{ ====================== the two populations ====================== }

procedure TAdvChartSeriesTest.TestBothPopulationsOnOneOption;
var x0, y0, y1: TTyAxis;
begin
  { The smallest option where the flat and the keyed populations differ, so they
    are asserted together: either one alone is green while the other is broken. }
  Run('{ xAxis: { data: [''A'', ''B'', ''C''] }, yAxis: [{}, {}],'
    + ' series: [{ type: ''bar'', data: [1, 2, 3] },'
    + ' { type: ''line'', yAxisIndex: 1, data: [100, 200, 300] }] }');
  x0 := FBuild.Axis('xAxis', 0);
  y0 := FBuild.Axis('yAxis', 0);
  y1 := FBuild.Axis('yAxis', 1);
  AssertEquals('both series are on the shared x axis', 2, Length(FIndex.SeriesOnAxis(x0)));
  AssertEquals('only the bar is on y0', 1, Length(FIndex.SeriesOnAxis(y0)));
  AssertEquals(0, FIndex.SeriesOnAxis(y0)[0]);
  AssertEquals('only the line is on y1', 1, Length(FIndex.SeriesOnAxis(y1)));
  AssertEquals(1, FIndex.SeriesOnAxis(y1)[0]);
  { And the keyed one holds ONLY the bar: a line sharing the axis must not be
    counted as one, or every bar comes out half as wide on a chart that looks
    otherwise right. }
  AssertEquals('one bar shares the band', 1,
    FIndex.CountOnAxisOfKey(x0, TySeriesStatKey('bar', 'cartesian2d')));
end;

procedure TAdvChartSeriesTest.TestAKeyedBucketHoldsOnlyItsOwnType;
var x0: TTyAxis;
begin
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [1, 2] }, { type: ''bar'', data: [3, 4] },'
    + ' { type: ''line'', data: [5, 6] }] }');
  x0 := FBuild.Axis('xAxis', 0);
  AssertEquals('all three on the axis', 3, Length(FIndex.SeriesOnAxis(x0)));
  AssertEquals('two bars in the bar bucket', 2,
    FIndex.CountOnAxisOfKey(x0, TySeriesStatKey('bar', 'cartesian2d')));
  AssertEquals('and one line in its own', 1,
    FIndex.CountOnAxisOfKey(x0, TySeriesStatKey('line', 'cartesian2d')));
  AssertEquals('ascending', 0, FIndex.SeriesOnAxisOfKey(x0,
    TySeriesStatKey('bar', 'cartesian2d'))[0]);
  AssertEquals(1, FIndex.SeriesOnAxisOfKey(x0, TySeriesStatKey('bar', 'cartesian2d'))[1]);
end;

procedure TAdvChartSeriesTest.TestAxisKeysDoNotCollide;
begin
  { An index keyed on the component number alone merges x0 and y0 and hands the
    y axis the bar bucket. }
  Run('{ xAxis: {}, yAxis: {}, series: [{ type: ''line'', data: [1] }] }');
  AssertTrue('different axes have different keys',
    FBuild.Axis('xAxis', 0).Uid <> FBuild.Axis('yAxis', 0).Uid);
  AssertEquals('xAxis:0', FBuild.Axis('xAxis', 0).Uid);
  AssertEquals('yAxis:0', FBuild.Axis('yAxis', 0).Uid);
end;

procedure TAdvChartSeriesTest.TestAHoleIsInertInBothPopulations;
var x0: TTyAxis;
begin
  { A series that did not resolve must not appear anywhere -- it would inflate a
    bar bucket and every bar would narrow to make room for something that is
    not drawn. }
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {},'
    + ' series: [{ data: [1, 2] }, { type: ''bar'', data: [3, 4] }] }');
  x0 := FBuild.Axis('xAxis', 0);
  AssertEquals('only the resolved one', 1, Length(FIndex.SeriesOnAxis(x0)));
  AssertEquals('and it is series 1', 1, FIndex.SeriesOnAxis(x0)[0]);
  AssertEquals('the bar bucket holds one', 1,
    FIndex.CountOnAxisOfKey(x0, TySeriesStatKey('bar', 'cartesian2d')));
end;

procedure TAdvChartSeriesTest.TestAValueAxisGetsNoKeyedBucket;
var y0: TTyAxis;
begin
  { The keyed population admits a pair only when the axis is that series' BASE
    axis. Without that test a bar would claim a band on its VALUE axis too, and
    a bar layouter reading the y bucket would size every bar off the wrong
    axis' band -- on a chart that otherwise looks right. }
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }');
  y0 := FBuild.Axis('yAxis', 0);
  AssertEquals('the bar does feed the value axis'' range', 1,
    Length(FIndex.SeriesOnAxis(y0)));
  AssertEquals('but claims no band on it', 0,
    FIndex.CountOnAxisOfKey(y0, TySeriesStatKey('bar', 'cartesian2d')));
end;

procedure TAdvChartSeriesTest.TestAxesAreResolvedByNameNotBySlot;
var
  c: TTyCartesian2D;
  sx, sy: TTyIntervalScale;
  axx, axy: TTyAxis;
begin
  { Built deliberately Y FIRST. Everything else in this suite goes through the
    builder, which adds x then y, so a positional GetAxis(0)/GetAxis(1) passes
    every other test here and is wrong the moment anything adds them in another
    order -- and nothing enforces that order. }
  c := TTyCartesian2D.Create;
  try
    sy := TTyIntervalScale.Create;
    sy.SetExtent(TyRange(0, 100));
    axy := TTyAxis.Create('y', sy, False);
    sx := TTyIntervalScale.Create;
    sx.SetExtent(TyRange(0, 10));
    axx := TTyAxis.Create('x', sx, True);
    c.AddAxis(axy);
    c.AddAxis(axx);
    c.SetRect(TyRectF(0, 0, 400, 300));
    AssertTrue('x by name, not by slot', c.AxisByDim('x') = axx);
    AssertTrue('y likewise', c.AxisByDim('y') = axy);
    AssertTrue('and with neither categorical the base is the HORIZONTAL one',
      c.GetBaseAxis = axx);
    AssertTrue('whose other axis is the vertical', c.GetOtherAxis(axx) = axy);
  finally
    c.Free;
  end;
end;

{ ============================ axis ranges ============================ }

procedure TAdvChartSeriesTest.TestEachValueAxisGetsItsOwnRange;
var y0, y1: TTyRange;
begin
  { The whole reason the flat population exists. Union the wrong way and the
    secondary axis is labelled with the primary's numbers -- which looks like a
    working chart. }
  Run('{ xAxis: { data: [''A'', ''B'', ''C''] }, yAxis: [{}, {}],'
    + ' series: [{ type: ''bar'', data: [1, 2, 3] },'
    + ' { type: ''line'', yAxisIndex: 1, data: [100, 200, 300] }] }');
  y0 := FBuild.Axis('yAxis', 0).Scale.GetExtent;
  y1 := FBuild.Axis('yAxis', 1).Scale.GetExtent;
  AssertEquals('y0 tops out at the bar''s data', 3, y0.Stop, 0);
  AssertEquals('y1 at the line''s', 300, y1.Stop, 0);
  AssertTrue('and they are not the same range', y0.Stop <> y1.Stop);
end;

procedure TAdvChartSeriesTest.TestAnAxisIncludesZeroUnlessToldToFit;
var e: TTyRange;
begin
  { This is why a bar sits on the axis line rather than floating. It applies to
    every value axis, not only ones with bars on them. }
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [10, 20] }] }');
  e := FBuild.Axis('yAxis', 0).Scale.GetExtent;
  AssertEquals('pulled down to zero', 0, e.Start, 0);
  Run('{ xAxis: { data: [''A'', ''B''] }, yAxis: { scale: true },'
    + ' series: [{ type: ''bar'', data: [10, 20] }] }');
  e := FBuild.Axis('yAxis', 0).Scale.GetExtent;
  AssertTrue('told to fit, so it does not reach zero', e.Start > 0);
end;

procedure TAdvChartSeriesTest.TestACategoryAxisRangeIsNotTouchedByData;
var e: TTyRange;
begin
  { A category axis' range is its category count. If the data decided it, a name
    the data never mentions would lose its band and every bar would shuffle. }
  Run('{ xAxis: { data: [''A'', ''B'', ''C'', ''D''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [[0, 1], [1, 2]] }] }');
  e := FBuild.Axis('xAxis', 0).Scale.GetExtent;
  AssertEquals('still all four', 0, e.Start, 0);
  AssertEquals(3, e.Stop, 0);
end;

procedure TAdvChartSeriesTest.TestEachAxisUnionsItsOwnColumn;
var ex, ey: TTyRange;
begin
  { Both axes are value axes here, so both take their range from data -- and
    they must take it from DIFFERENT columns. Every other range test in this
    file has a category x axis, which is skipped, so nothing until now noticed
    which column an axis read. }
  Run('{ xAxis: {}, yAxis: {},'
    + ' series: [{ type: ''scatter'', data: [[1, 100], [2, 200]] }] }');
  ex := FBuild.Axis('xAxis', 0).Scale.GetExtent;
  ey := FBuild.Axis('yAxis', 0).Scale.GetExtent;
  AssertEquals('x from the x column', 2, ex.Stop, 0);
  AssertEquals('y from the y column', 200, ey.Stop, 0);
  AssertTrue('and they are not the same range', ex.Stop <> ey.Stop);
end;

{ ============================ end to end ============================ }

procedure TAdvChartSeriesTest.TestTheHeadlineCase;
var
  x0, y0, y1: TTyAxis;
  barY, lineY: Double;
begin
  { Everything this unit exists for, in one option. Each assertion is a distinct
    way the chart can be wrong while still looking drawn. }
  Run('{ xAxis: [{ type: ''category'', data: [''A'', ''B'', ''C''] }],'
    + ' yAxis: [{ type: ''value'' }, { type: ''value'' }],'
    + ' series: [{ type: ''bar'', data: [1, 2, 3] },'
    + ' { type: ''line'', yAxisIndex: 1, data: [100, 200, 300] }] }');
  x0 := FBuild.Axis('xAxis', 0);
  y0 := FBuild.Axis('yAxis', 0);
  y1 := FBuild.Axis('yAxis', 1);

  AssertEquals('no complaints', 0, FBuild.DiagnosticCount);
  AssertTrue('the bar is on y0', FBind[0].YAxis = y0);
  AssertTrue('the line is on y1', FBind[1].YAxis = y1);
  AssertTrue('both are based on the shared category axis', FBind[0].BaseAxis = x0);
  AssertTrue(FBind[1].BaseAxis = x0);

  { The category list is ONE object, three ways. Give each store a private list
    and every value assertion still passes -- only identity goes red. }
  AssertTrue('the bar''s store borrows the axis'' list',
    FStores[0].OrdinalMeta(0) = x0.Categories);
  AssertTrue('and so does the line''s', FStores[1].OrdinalMeta(0) = x0.Categories);

  AssertEquals('the bar''s categories are row indices', 0, FStores[0].Get(0, 0), 0);
  AssertEquals(2, FStores[0].Get(0, 2), 0);
  AssertEquals('and its values are the data', 3, FStores[0].Get(1, 2), 0);

  AssertEquals('both feed the x axis', 2, Length(FIndex.SeriesOnAxis(x0)));
  AssertEquals('one bar shares the band', 1,
    FIndex.CountOnAxisOfKey(x0, TySeriesStatKey('bar', 'cartesian2d')));

  AssertEquals('y0 is the bar''s range', 3, y0.Scale.GetExtent.Stop, 0);
  AssertEquals('y1 is the line''s', 300, y1.Scale.GetExtent.Stop, 0);

  { Both values are a third of their own axis, so they land on the same pixel.
    Bind the line to y0 and it is thousands of pixels off; a test that only
    asked whether a point came back would pass either way. }
  barY := FBind[0].Cart.DataToPoint([1, 1]).Y;
  lineY := FBind[1].Cart.DataToPoint([1, 100]).Y;
  AssertEquals('a third of the way up each axis', barY, lineY, 1e-6);
  AssertTrue('and inside the plot',
    (lineY > FBuild.Grid(0).OuterRect.Top) and (lineY < FBuild.Grid(0).OuterRect.Bottom));
end;

initialization
  RegisterTest(TAdvChartSeriesTest);
end.
