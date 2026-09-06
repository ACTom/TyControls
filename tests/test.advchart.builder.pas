unit test.advchart.builder;
{$mode objfpc}{$H+}
{ Option text in, axes and coordinate systems out.

  Every number asserted here was read out of ECharts' source rather than its
  documentation, because on three of the four rules below the two disagree and
  the documentation is what our generated catalog transcribed.

  The one most likely to be got wrong: THERE IS NO 'category' DEFAULT. Both axis
  families run one identical rule -- an explicit type wins, otherwise an axis
  carrying a `data` key is categorical and everything else is a value axis. A
  bare xAxis is a VALUE axis. Category is the commonest axis in the wild because
  `data` is the commonest option, not because of the axis' name. }
interface
uses Classes, SysUtils, Math, DateUtils, fpjson, fpcunit, testregistry,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Data, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Layout,
     tyControls.AdvChart.Builder;
type
  { A measurer with no font behind it, so an axis-layout assertion is about the
    algorithm rather than about this machine's fonts. }
  TFixedMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  public
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

  TAdvChartBuilderTest = class(TTestCase)
  private
    FOpt: TTyChartOption;
    FBuild: TTyChartBuild;
    procedure SetUp; override;
    procedure TearDown; override;
    function Build(const AText: string;
      const ARect: TTyRectF): TTyChartBuild;
  published
    { ---- the axis type rule ---- }
    procedure TestABareAxisIsAValueAxis;
    procedure TestDataMakesItCategorical;
    procedure TestAnEmptyDataArrayIsStillCategorical;
    procedure TestAnExplicitTypeWins;
    procedure TestAnUnknownTypeIsReportedNotFatal;
    procedure TestNullDataIsNotCategorical;
    { ---- components ---- }
    procedure TestABareComponentBuildsOneAxis;
    procedure TestCategoriesComeOffTheAxis;
    procedure TestObjectFormCategories;
    { ---- grids ---- }
    procedure TestADefaultGridNeedsBothFamilies;
    procedure TestTheDefaultGridRect;
    procedure TestAnExplicitGridBox;
    procedure TestAPercentageBoxIsAFractionOfTheViewport;
    procedure TestTwoGridsKeepGlobalComponentIndices;
    procedure TestADanglingGridIndexIsAnOrphanNotACrash;
    procedure TestAnIndexBeatsAnIdAndDoesNotFallBack;
    procedure TestAnIdThatMatchesNothingIsNotGridZero;
    procedure TestAGridWithOnlyOneDirectionDrawsNothing;
    { ---- the cross product ---- }
    procedure TestNByMCartesians;
    procedure TestCartesianAtNeedsBothIndicesToMatch;
    procedure TestSharedAxesAreFreedExactlyOnce;
    { ---- sides ---- }
    procedure TestSecondAxisTakesTheOppositeSide;
    procedure TestAThirdAxisAlsoGoesOpposite;
    procedure TestAnExplicitPositionConsumesTheSlot;
    procedure TestAnExplicitDefaultSideConsumesItToo;
    procedure TestSideAllocationRestartsPerGrid;
    { ---- geometry ---- }
    procedure TestCategoryAxisGetsItsExtentFromTheCategories;
    procedure TestBandingFollowsBoundaryGap;
    procedure TestInverseIsRead;
    procedure TestPixelExtentIsWrittenTwice;
    { ---- robustness ---- }
    procedure TestAnEmptyOptionBuildsNothingAndDoesNotCrash;
    procedure TestRepeatedBuildsDoNotGrowTheHeap;
    { ---- reading series data ---- }
    procedure TestScalarsOnACategoryAxisGetTheRowIndex;
    procedure TestScalarsOnAValueAxisGoToEveryColumn;
    procedure TestTuplesAreReadColumnByColumn;
    procedure TestAShortTupleLeavesTheRestNoData;
    procedure TestTheObjectFormUnwrapsItsValue;
    procedure TestAnObjectWithNoValueIsNoData;
    procedure TestNoDataSpellings;
    procedure TestRowIndexSurvivesANullFirstRow;
    procedure TestALeadingNullDoesNotTurnTuplesIntoIndexMode;
    procedure TestColumnCountComesFromTheFirstItemLiterally;
    procedure TestNamesThatAreNotOnTheAxisAreGaps;
    procedure TestPerDatumNameAndId;
    procedure TestPerDatumOverridesUseDottedPaths;
    procedure TestTwoSeriesShareTheAxisCategoryList;
    procedure TestATimeAxisGetsATimeColumn;
  end;
implementation

{ What a caller would have resolved from a theme. Stated, not defaulted: the
  layout unit deliberately ships no default text style, because the bug this
  parameter replaced was exactly a hardcoded font living one layer too deep. }
function TestAxisTextStyle: TTyAxisTextStyle;
begin
  Result := Default(TTyAxisTextStyle);
  Result.FontName := 'TestFont';
  Result.FontSizeLogical := 12;
  Result.FontWeight := 400;
  Result.LabelMarginLogical := 8;
  Result.TickLengthLogical := 5;
  Result.NameGapLogical := 15;
end;

procedure TFixedMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
begin
  AW := Length(AText) * 7.0;
  AH := 14.0;
end;

procedure TAdvChartBuilderTest.SetUp;
begin
  inherited SetUp;
  FOpt := TTyChartOption.Create;
  FBuild := nil;
end;

procedure TAdvChartBuilderTest.TearDown;
begin
  FreeAndNil(FBuild);
  FreeAndNil(FOpt);
  inherited TearDown;
end;

function TAdvChartBuilderTest.Build(const AText: string;
  const ARect: TTyRectF): TTyChartBuild;
begin
  AssertTrue('the option parsed: ' + FOpt.Error.Message, FOpt.SetOptionText(AText));
  FreeAndNil(FBuild);
  FBuild := TyBuildGrids(FOpt, ARect);
  Result := FBuild;
end;

{ ============================ the axis type rule ============================ }

procedure TAdvChartBuilderTest.TestABareAxisIsAValueAxis;
var b: TTyChartBuild;
begin
  { The single most likely thing to get wrong. Our own generated catalog says
    xAxis.type defaults to 'category' -- it transcribes an upstream
    DOCUMENTATION bug, and the runtime has no such default. }
  b := Build('{ xAxis: {}, yAxis: {} }', TyRectF(0, 0, 600, 400));
  AssertTrue('x is a value axis', b.Axis('xAxis', 0).AxisType = atValue);
  AssertTrue('and so is y', b.Axis('yAxis', 0).AxisType = atValue);
  AssertFalse('so nothing is banded', b.Axis('xAxis', 0).OnBand);
end;

procedure TAdvChartBuilderTest.TestDataMakesItCategorical;
var b: TTyChartBuild;
begin
  { The rule is about `data`, not about the axis' name: a yAxis with data is
    just as categorical as an xAxis with data. }
  b := Build('{ xAxis: { data: [''a'', ''b''] }, yAxis: {} }', TyRectF(0, 0, 600, 400));
  AssertTrue('x', b.Axis('xAxis', 0).AxisType = atCategory);
  AssertTrue('y', b.Axis('yAxis', 0).AxisType = atValue);
  b := Build('{ xAxis: {}, yAxis: { data: [''a''] } }', TyRectF(0, 0, 600, 400));
  AssertTrue('and the other way round', b.Axis('yAxis', 0).AxisType = atCategory);
  AssertTrue(b.Axis('xAxis', 0).AxisType = atValue);
end;

procedure TAdvChartBuilderTest.TestAnEmptyDataArrayIsStillCategorical;
var b: TTyChartBuild;
begin
  { An empty array is TRUTHY in JavaScript, so `data: []` is a category axis
    with a fixed list of no categories -- which is not the same thing as an axis
    that never declared one. Testing the array's LENGTH here would quietly turn
    it into a value axis. }
  b := Build('{ xAxis: { data: [] }, yAxis: {} }', TyRectF(0, 0, 600, 400));
  AssertTrue('categorical', b.Axis('xAxis', 0).AxisType = atCategory);
  AssertEquals('with nothing in it', 0, b.Axis('xAxis', 0).Categories.Count);
  AssertTrue('and blank', b.Axis('xAxis', 0).Scale.Blank);
end;

procedure TAdvChartBuilderTest.TestAnExplicitTypeWins;
var b: TTyChartBuild;
begin
  b := Build('{ xAxis: { type: ''value'', data: [''a'', ''b''] }, yAxis: { type: ''log'' } }',
    TyRectF(0, 0, 600, 400));
  AssertTrue('data does not override an explicit type',
    b.Axis('xAxis', 0).AxisType = atValue);
  AssertTrue('log', b.Axis('yAxis', 0).AxisType = atLog);
end;

procedure TAdvChartBuilderTest.TestAnUnknownTypeIsReportedNotFatal;
var b: TTyChartBuild;
begin
  { ECharts THROWS on an unrecognised axis type. Throwing is wrong for us: a
    design-time editor renders on every keystroke, and 'cat' on the way to
    'category' would blank the chart. The axis falls back to a value axis and
    the mistake is REPORTED -- silently dropping it would be the worst of the
    three. }
  b := Build('{ xAxis: { type: ''cat'' }, yAxis: {} }', TyRectF(0, 0, 600, 400));
  AssertTrue('still built', b.Axis('xAxis', 0) <> nil);
  AssertTrue('as a value axis', b.Axis('xAxis', 0).AxisType = atValue);
  AssertEquals('and said so', 1, b.DiagnosticCount);
  AssertTrue('naming the offender', Pos('cat', b.Diagnostic(0)) > 0);
end;

procedure TAdvChartBuilderTest.TestNullDataIsNotCategorical;
begin
  { Written, but written as nothing. }
  AssertTrue(Build('{ xAxis: { data: null }, yAxis: {} }',
    TyRectF(0, 0, 600, 400)).Axis('xAxis', 0).AxisType = atValue);
end;

{ ============================ components ============================ }

procedure TAdvChartBuilderTest.TestABareComponentBuildsOneAxis;
var b: TTyChartBuild;
begin
  { Reached through the normalising accessor. CountAt would answer 0 here and
    the chart would draw nothing while reporting nothing. }
  b := Build('{ xAxis: { data: [''a''] }, yAxis: {} }', TyRectF(0, 0, 600, 400));
  AssertEquals(1, b.AxisCount('xAxis'));
  AssertEquals(1, b.AxisCount('yAxis'));
  AssertEquals(1, b.GridCount);
end;

procedure TAdvChartBuilderTest.TestCategoriesComeOffTheAxis;
var b: TTyChartBuild; ax: TTyAxis;
begin
  b := Build('{ xAxis: { data: [''Mon'', ''Tue'', ''Wed''] }, yAxis: {} }',
    TyRectF(0, 0, 600, 400));
  ax := b.Axis('xAxis', 0);
  AssertEquals(3, ax.Categories.Count);
  AssertEquals('Tue', ax.Categories.CategoryAt(1));
  AssertEquals('and the scale sees them', 3, TTyOrdinalScale(ax.Scale).Count);
end;

procedure TAdvChartBuilderTest.TestObjectFormCategories;
var b: TTyChartBuild;
begin
  { ECharts accepts a category written as an object with a value, which is how
    a per-category style is attached. }
  b := Build('{ xAxis: { data: [''a'', { value: ''b'' }, ''c''] }, yAxis: {} }',
    TyRectF(0, 0, 600, 400));
  AssertEquals(3, b.Axis('xAxis', 0).Categories.Count);
  AssertEquals('b', b.Axis('xAxis', 0).Categories.CategoryAt(1));
end;

{ ============================ grids ============================ }

procedure TAdvChartBuilderTest.TestADefaultGridNeedsBothFamilies;
var b: TTyChartBuild;
begin
  { Upstream synthesises a grid only when BOTH families are present. One alone
    is not an oversight: an x axis with nothing to plot against has no rect to
    live in. }
  b := Build('{ xAxis: {}, yAxis: {} }', TyRectF(0, 0, 600, 400));
  AssertEquals('both', 1, b.GridCount);
  b := Build('{ xAxis: {} }', TyRectF(0, 0, 600, 400));
  AssertEquals('x alone builds no grid', 0, b.GridCount);
  AssertTrue('and says why', b.DiagnosticCount > 0);
  b := Build('{ yAxis: {} }', TyRectF(0, 0, 600, 400));
  AssertEquals('y alone likewise', 0, b.GridCount);
end;

procedure TAdvChartBuilderTest.TestTheDefaultGridRect;
var b: TTyChartBuild; r: TTyRectF;
begin
  { left 15%, top 65px, right 10%, bottom 80px, of a 600x400 viewport.
    Percentages are of the FULL extent, not of what is left over. }
  b := Build('{ xAxis: {}, yAxis: {} }', TyRectF(0, 0, 600, 400));
  r := b.Grid(0).OuterRect;
  AssertEquals('left', 90.0, r.Left, 1e-9);
  AssertEquals('top', 65.0, r.Top, 1e-9);
  AssertEquals('right', 540.0, r.Right, 1e-9);
  AssertEquals('bottom', 320.0, r.Bottom, 1e-9);
end;

procedure TAdvChartBuilderTest.TestAnExplicitGridBox;
var b: TTyChartBuild; r: TTyRectF;
begin
  b := Build('{ grid: { left: 10, top: 20, right: 30, bottom: 40 },'
    + ' xAxis: {}, yAxis: {} }', TyRectF(0, 0, 600, 400));
  r := b.Grid(0).OuterRect;
  AssertEquals(10.0, r.Left, 1e-9);
  AssertEquals(20.0, r.Top, 1e-9);
  AssertEquals('right is an INSET from the far edge', 570.0, r.Right, 1e-9);
  AssertEquals(360.0, r.Bottom, 1e-9);
end;

procedure TAdvChartBuilderTest.TestAPercentageBoxIsAFractionOfTheViewport;
var b: TTyChartBuild; r: TTyRectF;
begin
  { A percentage is of the FULL extent, not of what is left after the other
    side. Nothing else in this file writes a percentage STRING -- the defaults
    are built as percentages directly, so the string path had no coverage and a
    mutation turning '20%' into 20px went unnoticed. }
  b := Build('{ grid: { left: ''20%'', top: ''25%'', right: ''10%'', bottom: ''50%'' },'
    + ' xAxis: {}, yAxis: {} }', TyRectF(0, 0, 600, 400));
  r := b.Grid(0).OuterRect;
  AssertEquals('20 per cent of 600', 120.0, r.Left, 1e-9);
  AssertEquals('25 per cent of 400', 100.0, r.Top, 1e-9);
  AssertEquals('inset 10 per cent of 600 from the right', 540.0, r.Right, 1e-9);
  AssertEquals('inset 50 per cent of 400 from the bottom', 200.0, r.Bottom, 1e-9);
end;

procedure TAdvChartBuilderTest.TestTwoGridsKeepGlobalComponentIndices;
var b: TTyChartBuild;
begin
  { The index a series will name is GLOBAL across grids: grid 1's first x axis
    is legitimately component 2. Renumbering per grid is the shortest path to a
    binding that resolves to the wrong plot. }
  b := Build('{ grid: [{}, {}],'
    + ' xAxis: [{ gridIndex: 0 }, { gridIndex: 1 }],'
    + ' yAxis: [{ gridIndex: 0 }, { gridIndex: 1 }] }', TyRectF(0, 0, 600, 400));
  AssertEquals(2, b.GridCount);
  AssertEquals('grid 1 has one x axis', 1, b.Grid(1).XAxisCount);
  AssertEquals('and it is component 1', 1, b.Grid(1).XAxis(0).ComponentIndex);
  AssertEquals('so the key is global', 'x1y1', b.Grid(1).CartesianKey(0));
  AssertEquals('grid 0 keeps its own', 'x0y0', b.Grid(0).CartesianKey(0));
end;

procedure TAdvChartBuilderTest.TestADanglingGridIndexIsAnOrphanNotACrash;
var b: TTyChartBuild;
begin
  { The axis is still built, so an editor can report on it; it simply lands in
    no coordinate system. }
  b := Build('{ xAxis: [{}, { gridIndex: 7 }], yAxis: {} }', TyRectF(0, 0, 600, 400));
  AssertEquals('both axes exist', 2, b.AxisCount('xAxis'));
  AssertEquals('the orphan names no grid', -1, b.Axis('xAxis', 1).GridIndex);
  AssertEquals('the grid holds only the other one', 1, b.Grid(0).XAxisCount);
  AssertTrue('and it was reported', b.DiagnosticCount > 0);
end;

procedure TAdvChartBuilderTest.TestAnIndexBeatsAnIdAndDoesNotFallBack;
var b: TTyChartBuild;
begin
  { An index wins over an id, and an index naming no grid falls back to
    NOTHING -- not to the id, and not to grid 0. Quietly relocating an axis
    would be harder to debug than dropping it and saying so. }
  b := Build('{ grid: [{ id: ''g0'' }, { id: ''g1'' }],'
    + ' xAxis: [{ gridIndex: 1, gridId: ''g0'' }], yAxis: [{ gridIndex: 1 }] }',
    TyRectF(0, 0, 600, 400));
  AssertEquals('the index won', 1, b.Axis('xAxis', 0).GridIndex);
  b := Build('{ grid: [{ id: ''g0'' }],'
    + ' xAxis: [{ gridIndex: 9, gridId: ''g0'' }], yAxis: [{}] }',
    TyRectF(0, 0, 600, 400));
  AssertEquals('a bad index does not fall through to the id', -1,
    b.Axis('xAxis', 0).GridIndex);
  b := Build('{ grid: [{ id: ''g0'' }, { id: ''g1'' }],'
    + ' xAxis: [{ gridId: ''g1'' }], yAxis: [{ gridId: ''g1'' }] }',
    TyRectF(0, 0, 600, 400));
  AssertEquals('an id alone resolves', 1, b.Axis('xAxis', 0).GridIndex);
end;

procedure TAdvChartBuilderTest.TestAnIdThatMatchesNothingIsNotGridZero;
var b: TTyChartBuild;
begin
  { A misspelled gridId must not quietly land the axis on the first grid. The
    chart would draw, and it would be wrong in a way nothing on screen
    distinguishes from a correct one. }
  b := Build('{ grid: [{ id: ''g0'' }, { id: ''g1'' }],'
    + ' xAxis: [{ gridId: ''typo'' }, { gridId: ''g0'' }],'
    + ' yAxis: [{ gridId: ''g0'' }] }', TyRectF(0, 0, 600, 400));
  AssertEquals('names no grid', -1, b.Axis('xAxis', 0).GridIndex);
  AssertEquals('while the correct one resolves', 0, b.Axis('xAxis', 1).GridIndex);
  AssertEquals('so grid 0 holds only the second', 1, b.Grid(0).XAxisCount);
  AssertTrue('and it was reported', b.DiagnosticCount > 0);
end;

procedure TAdvChartBuilderTest.TestAGridWithOnlyOneDirectionDrawsNothing;
var b: TTyChartBuild;
begin
  { One orphaned axis takes the whole plot its partner was on with it. Half a
    cartesian cannot place a datum, so there is nothing honest to draw. }
  b := Build('{ grid: [{}, {}], xAxis: [{ gridIndex: 0 }, { gridIndex: 1 }],'
    + ' yAxis: [{ gridIndex: 0 }] }', TyRectF(0, 0, 600, 400));
  AssertEquals('grid 0 is whole', 1, b.Grid(0).CartesianCount);
  AssertEquals('grid 1 has an x axis', 1, b.Grid(1).XAxisCount);
  AssertEquals('no y axis', 0, b.Grid(1).YAxisCount);
  AssertEquals('and therefore no coordinate system', 0, b.Grid(1).CartesianCount);
  AssertTrue('reported', b.DiagnosticCount > 0);
end;

{ ============================ the cross product ============================ }

procedure TAdvChartBuilderTest.TestNByMCartesians;
var b: TTyChartBuild;
begin
  b := Build('{ xAxis: [{}, {}], yAxis: [{}, {}, {}] }', TyRectF(0, 0, 600, 400));
  AssertEquals('two by three', 6, b.Grid(0).CartesianCount);
  AssertEquals('x0y0', b.Grid(0).CartesianKey(0));
  AssertEquals('x major, y minor', 'x0y1', b.Grid(0).CartesianKey(1));
  AssertEquals('x1y2', b.Grid(0).CartesianKey(5));
end;

procedure TAdvChartBuilderTest.TestCartesianAtNeedsBothIndicesToMatch;
var b: TTyChartBuild; c: TTyCartesian2D;
begin
  { Upstream's lookup falls back when only ONE index matches and hands back
    x0y0 for a request naming y axis 1 -- which is precisely the secondary-axis
    bug this layer exists to prevent. Ours matches both or answers nothing. }
  b := Build('{ xAxis: [{}], yAxis: [{}, {}] }', TyRectF(0, 0, 600, 400));
  c := b.Grid(0).CartesianAt(0, 1);
  AssertTrue('the pair exists', c <> nil);
  AssertTrue('and holds the SECOND y axis', c.GetAxis(1) = b.Axis('yAxis', 1));
  AssertTrue('a pair that does not exist is nil', b.Grid(0).CartesianAt(1, 0) = nil);
end;

procedure TAdvChartBuilderTest.TestSharedAxesAreFreedExactlyOnce;
var b: TTyChartBuild;
begin
  { Two coordinate systems hold the SAME x axis. If each freed what it was
    given, the second free would be on rubble -- and it would not show up here,
    it would show up in whatever test ran next. }
  b := Build('{ xAxis: [{}], yAxis: [{}, {}] }', TyRectF(0, 0, 600, 400));
  AssertEquals(2, b.Grid(0).CartesianCount);
  AssertTrue('one axis, two systems',
    b.Grid(0).CartesianByIndex(0).GetAxis(0) = b.Grid(0).CartesianByIndex(1).GetAxis(0));
  AssertFalse('and neither owns it', b.Grid(0).CartesianByIndex(0).OwnsAxes);
  FreeAndNil(FBuild);
  AssertTrue('freed once, cleanly', True);
end;

{ ============================ sides ============================ }

procedure TAdvChartBuilderTest.TestSecondAxisTakesTheOppositeSide;
var b: TTyChartBuild;
begin
  b := Build('{ xAxis: [{}, {}], yAxis: [{}, {}] }', TyRectF(0, 0, 600, 400));
  AssertTrue('first x at the bottom', b.Axis('xAxis', 0).Side = asBottom);
  AssertTrue('second at the top', b.Axis('xAxis', 1).Side = asTop);
  AssertTrue('first y at the left', b.Axis('yAxis', 0).Side = asLeft);
  AssertTrue('second at the right', b.Axis('yAxis', 1).Side = asRight);
end;

procedure TAdvChartBuilderTest.TestAThirdAxisAlsoGoesOpposite;
var b: TTyChartBuild;
begin
  { Only the bottom flag is consulted, so every axis after the first lands on
    top. They stack by an offset rather than by running out of sides -- so a
    rule that alternated would be wrong from the third axis on. }
  b := Build('{ xAxis: [{}, {}, {}], yAxis: [{}] }', TyRectF(0, 0, 600, 400));
  AssertTrue(b.Axis('xAxis', 0).Side = asBottom);
  AssertTrue(b.Axis('xAxis', 1).Side = asTop);
  AssertTrue('not back to the bottom', b.Axis('xAxis', 2).Side = asTop);
end;

procedure TAdvChartBuilderTest.TestAnExplicitPositionConsumesTheSlot;
var b: TTyChartBuild;
begin
  { An explicit position sets the used-flag too, so the NEXT axis defaults
    around it rather than colliding with it. }
  b := Build('{ xAxis: [{ position: ''top'' }, {}], yAxis: [{}] }',
    TyRectF(0, 0, 600, 400));
  AssertTrue('explicit', b.Axis('xAxis', 0).Side = asTop);
  AssertTrue('the next one takes the free side', b.Axis('xAxis', 1).Side = asBottom);
end;

procedure TAdvChartBuilderTest.TestAnExplicitDefaultSideConsumesItToo;
var b: TTyChartBuild;
begin
  { The flag is set for an explicit position whichever side it names. Writing
    position:'bottom' -- the side the first axis would have taken anyway -- must
    still push the NEXT axis to the top, or the two are drawn on top of each
    other. The 'top' case alone does not cover this: it exercises the other
    branch. }
  b := Build('{ xAxis: [{ position: ''bottom'' }, {}], yAxis: [{}] }',
    TyRectF(0, 0, 600, 400));
  AssertTrue('explicit bottom', b.Axis('xAxis', 0).Side = asBottom);
  AssertTrue('and the next one is pushed off it', b.Axis('xAxis', 1).Side = asTop);
  b := Build('{ yAxis: [{ position: ''left'' }, {}], xAxis: [{}] }',
    TyRectF(0, 0, 600, 400));
  AssertTrue('the same on the other axis', b.Axis('yAxis', 0).Side = asLeft);
  AssertTrue(b.Axis('yAxis', 1).Side = asRight);
end;

procedure TAdvChartBuilderTest.TestSideAllocationRestartsPerGrid;
var b: TTyChartBuild;
begin
  { The used-flags live inside the per-grid loop, so grid 1's first x axis is at
    the bottom again rather than continuing grid 0's allocation. }
  b := Build('{ grid: [{}, {}],'
    + ' xAxis: [{ gridIndex: 0 }, { gridIndex: 1 }],'
    + ' yAxis: [{ gridIndex: 0 }, { gridIndex: 1 }] }', TyRectF(0, 0, 600, 400));
  AssertTrue('grid 0', b.Axis('xAxis', 0).Side = asBottom);
  AssertTrue('grid 1 starts over', b.Axis('xAxis', 1).Side = asBottom);
  AssertTrue(b.Axis('yAxis', 1).Side = asLeft);
end;

{ ============================ geometry ============================ }

procedure TAdvChartBuilderTest.TestCategoryAxisGetsItsExtentFromTheCategories;
var b: TTyChartBuild; sc: TTyOrdinalScale;
begin
  { From the CATEGORY COUNT, never from any data's min or max. }
  b := Build('{ xAxis: { data: [''a'', ''b'', ''c'', ''d''] }, yAxis: {} }',
    TyRectF(0, 0, 600, 400));
  sc := TTyOrdinalScale(b.Axis('xAxis', 0).Scale);
  AssertEquals('start', 0, sc.GetExtent.Start, 0);
  AssertEquals('stop is the LAST index', 3, sc.GetExtent.Stop, 0);
  AssertEquals('four categories', 4, sc.Count);
end;

procedure TAdvChartBuilderTest.TestBandingFollowsBoundaryGap;
var b: TTyChartBuild;
begin
  b := Build('{ xAxis: { data: [''a'', ''b''] }, yAxis: {} }', TyRectF(0, 0, 600, 400));
  AssertTrue('a category axis bands by default', b.Axis('xAxis', 0).OnBand);
  b := Build('{ xAxis: { data: [''a'', ''b''], boundaryGap: false }, yAxis: {} }',
    TyRectF(0, 0, 600, 400));
  AssertFalse('unless told not to', b.Axis('xAxis', 0).OnBand);
  b := Build('{ xAxis: {}, yAxis: {} }', TyRectF(0, 0, 600, 400));
  AssertFalse('and a value axis never does', b.Axis('xAxis', 0).OnBand);
end;

procedure TAdvChartBuilderTest.TestInverseIsRead;
var b: TTyChartBuild;
begin
  b := Build('{ xAxis: { inverse: true }, yAxis: {} }', TyRectF(0, 0, 600, 400));
  AssertTrue(b.Axis('xAxis', 0).Inverse);
  AssertFalse(b.Axis('yAxis', 0).Inverse);
end;

procedure TAdvChartBuilderTest.TestPixelExtentIsWrittenTwice;
var
  b: TTyChartBuild;
  before, after: Double;
  m: ITyTextMeasurer;
begin
  { Phase A writes an approximate extent off the raw grid rect; phase C writes
    the final one off the rect the labels left over. Both are legitimate: a
    dataZoom slider and a bar layouter need an extent before the labels have
    been measured. }
  b := Build('{ xAxis: { data: [''alpha'', ''beta'', ''gamma''] }, yAxis: {} }',
    TyRectF(0, 0, 600, 400));
  before := b.Axis('xAxis', 0).PxStop - b.Axis('xAxis', 0).PxStart;
  AssertEquals('the raw grid width', 450.0, before, 1e-9);
  m := TFixedMeasurer.Create;
  { The style is the CALLER's to resolve, so the test states what it measures
    with instead of inheriting a default -- there is deliberately no default in
    the layout unit, because a default there is the hardcoded font all over
    again. }
  TyLayoutGrids(b, FOpt, m, 96, TestAxisTextStyle);
  after := b.Axis('xAxis', 0).PxStop - b.Axis('xAxis', 0).PxStart;
  AssertTrue('the plot shrank to make room for the labels', after < before);
  AssertTrue('and the band width followed it', b.Axis('xAxis', 0).BandWidth < before / 3);
end;

{ ============================ robustness ============================ }

procedure TAdvChartBuilderTest.TestAnEmptyOptionBuildsNothingAndDoesNotCrash;
var b: TTyChartBuild;
begin
  { A design-time editor renders on every keystroke, so half-typed text is the
    normal state and never an exception. }
  b := Build('{}', TyRectF(0, 0, 600, 400));
  AssertEquals(0, b.GridCount);
  AssertEquals(0, b.AxisCount('xAxis'));
  AssertTrue('and nothing to complain about', b.DiagnosticCount = 0);
  AssertTrue('an absent axis answers nil', b.Axis('xAxis', 0) = nil);
  AssertTrue('so does an absent grid', b.Grid(0) = nil);
end;

procedure TAdvChartBuilderTest.TestRepeatedBuildsDoNotGrowTheHeap;
var
  before, after: PtrUInt;
  i: Integer;
  t: TTyChartBuild;
begin
  { Every setOption rebuilds every axis, so a leak here grows with use rather
    than showing up once. The axes, their category lists and the coordinate
    systems are three separate ownerships and any one of them could leak. }
  AssertTrue(FOpt.SetOptionText('{ grid: [{}, {}],'
    + ' xAxis: [{ data: [''a'', ''b''], gridIndex: 0 }, { gridIndex: 1 }],'
    + ' yAxis: [{ gridIndex: 0 }, { gridIndex: 1 }] }'));
  for i := 0 to 4 do
    TyBuildGrids(FOpt, TyRectF(0, 0, 600, 400)).Free;
  before := GetFPCHeapStatus.CurrHeapUsed;
  for i := 0 to 99 do
  begin
    t := TyBuildGrids(FOpt, TyRectF(0, 0, 600, 400));
    t.Free;
  end;
  after := GetFPCHeapStatus.CurrHeapUsed;
  AssertTrue(Format('heap grew from %d to %d over a hundred builds', [before, after]),
    after <= before);
end;

{ ====================== reading series data ====================== }

procedure TAdvChartBuilderTest.TestScalarsOnACategoryAxisGetTheRowIndex;
var b: TTyChartBuild; st: TTyDataStore; dims: TTySeriesDimArray; i: Integer;
begin
  { The commonest shape on the internet: three bare numbers against three
    category names. It works because the category column is filled with the ROW
    INDEX while the numbers go to the value column. Without it the numbers would
    be read as category NAMES, miss every one, and the chart would be empty. }
  b := Build('{ xAxis: { data: [''Mon'', ''Tue'', ''Wed''] }, yAxis: {},'
    + ' series: [{ type: ''line'', data: [120, 200, 150] }] }', TyRectF(0, 0, 600, 400));
  dims := TySeriesCartesianDims(b.Grid(0).CartesianByIndex(0), 0);
  st := TTyDataStore.Create;
  try
    for i := 0 to High(dims) do
    begin
      st.AddDimension(dims[i].Name, dims[i].Kind);
      if dims[i].Axis <> nil then st.UseOrdinalMeta(i, dims[i].Axis.Categories);
    end;
    AssertEquals('three rows', 3, TyFillSeriesStore(FOpt, 0, dims, st));
    AssertEquals('x is the row index', 0, st.Get(0, 0), 0);
    AssertEquals(1, st.Get(0, 1), 0);
    AssertEquals(2, st.Get(0, 2), 0);
    AssertEquals('y is the datum', 120, st.Get(1, 0), 0);
    AssertEquals(200, st.Get(1, 1), 0);
    AssertEquals(150, st.Get(1, 2), 0);
  finally
    st.Free;
  end;
end;

procedure TAdvChartBuilderTest.TestScalarsOnAValueAxisGoToEveryColumn;
var b: TTyChartBuild; st: TTyDataStore; dims: TTySeriesDimArray; i: Integer;
begin
  { A scalar is fed to EVERY column, so on two value axes 120 really does land
    on both x and y. It looks like a missing guard and it is not -- it is what
    upstream does, and the case where it would be visible is exactly the case
    the row index takes over. }
  b := Build('{ xAxis: {}, yAxis: {},'
    + ' series: [{ type: ''line'', data: [120, 200] }] }', TyRectF(0, 0, 600, 400));
  dims := TySeriesCartesianDims(b.Grid(0).CartesianByIndex(0), 0);
  st := TTyDataStore.Create;
  try
    for i := 0 to High(dims) do st.AddDimension(dims[i].Name, dims[i].Kind);
    TyFillSeriesStore(FOpt, 0, dims, st);
    AssertEquals('x', 120, st.Get(0, 0), 0);
    AssertEquals('and y, the same number', 120, st.Get(1, 0), 0);
    AssertEquals(200, st.Get(0, 1), 0);
    AssertEquals(200, st.Get(1, 1), 0);
  finally
    st.Free;
  end;
end;

procedure TAdvChartBuilderTest.TestTuplesAreReadColumnByColumn;
var b: TTyChartBuild; st: TTyDataStore; dims: TTySeriesDimArray; i: Integer;
begin
  b := Build('{ xAxis: {}, yAxis: {},'
    + ' series: [{ type: ''scatter'', data: [[1, 10], [2, 20], [3, 30]] }] }',
    TyRectF(0, 0, 600, 400));
  dims := TySeriesCartesianDims(b.Grid(0).CartesianByIndex(0), 0);
  st := TTyDataStore.Create;
  try
    for i := 0 to High(dims) do st.AddDimension(dims[i].Name, dims[i].Kind);
    TyFillSeriesStore(FOpt, 0, dims, st);
    AssertEquals(2, st.Get(0, 1), 0);
    AssertEquals(20, st.Get(1, 1), 0);
  finally
    st.Free;
  end;
end;

procedure TAdvChartBuilderTest.TestAShortTupleLeavesTheRestNoData;
var b: TTyChartBuild; st: TTyDataStore; dims: TTySeriesDimArray; i: Integer;
begin
  b := Build('{ xAxis: {}, yAxis: {},'
    + ' series: [{ type: ''scatter'', data: [[1, 10], [2]] }] }', TyRectF(0, 0, 600, 400));
  dims := TySeriesCartesianDims(b.Grid(0).CartesianByIndex(0), 0);
  st := TTyDataStore.Create;
  try
    for i := 0 to High(dims) do st.AddDimension(dims[i].Name, dims[i].Kind);
    TyFillSeriesStore(FOpt, 0, dims, st);
    AssertEquals(2, st.Get(0, 1), 0);
    AssertTrue('the column the tuple did not reach', IsNan(st.Get(1, 1)));
  finally
    st.Free;
  end;
end;

procedure TAdvChartBuilderTest.TestTheObjectFormUnwrapsItsValue;
var b: TTyChartBuild; st: TTyDataStore; dims: TTySeriesDimArray; i: Integer;
begin
  b := Build('{ xAxis: {}, yAxis: {}, series: [{ type: ''scatter'','
    + ' data: [{ value: [1, 10] }, { value: 5 }] }] }', TyRectF(0, 0, 600, 400));
  dims := TySeriesCartesianDims(b.Grid(0).CartesianByIndex(0), 0);
  st := TTyDataStore.Create;
  try
    for i := 0 to High(dims) do st.AddDimension(dims[i].Name, dims[i].Kind);
    TyFillSeriesStore(FOpt, 0, dims, st);
    AssertEquals('a tuple value', 1, st.Get(0, 0), 0);
    AssertEquals(10, st.Get(1, 0), 0);
    AssertEquals('a scalar value, on both columns', 5, st.Get(0, 1), 0);
    AssertEquals(5, st.Get(1, 1), 0);
  finally
    st.Free;
  end;
end;

procedure TAdvChartBuilderTest.TestAnObjectWithNoValueIsNoData;
var b: TTyChartBuild; st: TTyDataStore; dims: TTySeriesDimArray; i: Integer;
begin
  { An object with no `value`, or with a null one, falls back to ITSELF -- and
    an object is not a number, so the datum is a gap. That fallback is
    deliberate upstream, not an accident: it is what lets `{name: 'x'}` be a
    labelled hole. }
  b := Build('{ xAxis: {}, yAxis: {}, series: [{ type: ''scatter'','
    + ' data: [{ name: ''a'' }, { value: null }, { value: 7 }] }] }',
    TyRectF(0, 0, 600, 400));
  dims := TySeriesCartesianDims(b.Grid(0).CartesianByIndex(0), 0);
  st := TTyDataStore.Create;
  try
    for i := 0 to High(dims) do st.AddDimension(dims[i].Name, dims[i].Kind);
    TyFillSeriesStore(FOpt, 0, dims, st);
    AssertTrue('no value key', IsNan(st.Get(1, 0)));
    AssertTrue('a null value', IsNan(st.Get(1, 1)));
    AssertEquals('and a real one still works', 7, st.Get(1, 2), 0);
    AssertEquals('the row is still there', 3, st.Count);
  finally
    st.Free;
  end;
end;

procedure TAdvChartBuilderTest.TestNoDataSpellings;
var b: TTyChartBuild; st: TTyDataStore; dims: TTySeriesDimArray; i: Integer;
begin
  { Every way of writing a hole, and they all have to make the same one -- a
    line chart breaks at a gap, and a gap that parsed to 0 would draw a spike
    to the axis instead. }
  b := Build('{ xAxis: {}, yAxis: {}, series: [{ type: ''line'','
    + ' data: [null, ''-'', '''', ''nonsense'', 4] }] }', TyRectF(0, 0, 600, 400));
  dims := TySeriesCartesianDims(b.Grid(0).CartesianByIndex(0), 0);
  st := TTyDataStore.Create;
  try
    for i := 0 to High(dims) do st.AddDimension(dims[i].Name, dims[i].Kind);
    TyFillSeriesStore(FOpt, 0, dims, st);
    AssertTrue('null', IsNan(st.Get(1, 0)));
    AssertTrue('a dash', IsNan(st.Get(1, 1)));
    AssertTrue('an empty string', IsNan(st.Get(1, 2)));
    AssertTrue('a word', IsNan(st.Get(1, 3)));
    AssertEquals('and a number is a number', 4, st.Get(1, 4), 0);
  finally
    st.Free;
  end;
end;

procedure TAdvChartBuilderTest.TestRowIndexSurvivesANullFirstRow;
var b: TTyChartBuild; st: TTyDataStore; dims: TTySeriesDimArray; i: Integer;
begin
  { The row-index decision reads the first NON-NULL item, so a leading gap does
    not switch it off -- and the null row still gets its index, because the
    index is the row's position, not its content. }
  b := Build('{ xAxis: { data: [''a'', ''b'', ''c''] }, yAxis: {},'
    + ' series: [{ type: ''line'', data: [null, 55, 66] }] }', TyRectF(0, 0, 600, 400));
  dims := TySeriesCartesianDims(b.Grid(0).CartesianByIndex(0), 0);
  st := TTyDataStore.Create;
  try
    for i := 0 to High(dims) do
    begin
      st.AddDimension(dims[i].Name, dims[i].Kind);
      if dims[i].Axis <> nil then st.UseOrdinalMeta(i, dims[i].Axis.Categories);
    end;
    TyFillSeriesStore(FOpt, 0, dims, st);
    AssertEquals('the null row still has its index', 0, st.Get(0, 0), 0);
    AssertTrue('while its value is a gap', IsNan(st.Get(1, 0)));
    AssertEquals(1, st.Get(0, 1), 0);
    AssertEquals(55, st.Get(1, 1), 0);
  finally
    st.Free;
  end;
end;

procedure TAdvChartBuilderTest.TestALeadingNullDoesNotTurnTuplesIntoIndexMode;
var b: TTyChartBuild; st: TTyDataStore; dims: TTySeriesDimArray; i: Integer;
begin
  { The two first-item questions look at DIFFERENT items and genuinely disagree
    here: the column count reads item 0 raw (a null, so one column), while the
    row-index decision skips to the first tuple and says no. Merging them would
    be tidier and would put the row index over real x values. }
  b := Build('{ xAxis: { data: [''a'', ''b'', ''c''] }, yAxis: {},'
    + ' series: [{ type: ''line'', data: [null, [2, 55], [0, 66]] }] }',
    TyRectF(0, 0, 600, 400));
  dims := TySeriesCartesianDims(b.Grid(0).CartesianByIndex(0), 0);
  st := TTyDataStore.Create;
  try
    for i := 0 to High(dims) do
    begin
      st.AddDimension(dims[i].Name, dims[i].Kind);
      if dims[i].Axis <> nil then st.UseOrdinalMeta(i, dims[i].Axis.Categories);
    end;
    TyFillSeriesStore(FOpt, 0, dims, st);
    { Row 1 carries x=2 and row 2 carries x=0, so the tuple's own value and the
      row index can never be confused. They were 1 and 2 at first -- which the
      row indices also are -- and the test then passed under a mutation that
      turned index mode ON. A fixture that makes both answers identical asserts
      nothing. The values still have to be VALID category indices, or the
      column parses to no-data and the assertion raises rather than fails. }
    AssertEquals('the tuple''s own x, not the row index', 2, st.Get(0, 1), 0);
    AssertEquals(55, st.Get(1, 1), 0);
    AssertEquals(0, st.Get(0, 2), 0);
    AssertEquals(66, st.Get(1, 2), 0);
  finally
    st.Free;
  end;
end;

procedure TAdvChartBuilderTest.TestColumnCountComesFromTheFirstItemLiterally;
var
  d: TJSONArray;
  dims: TTySeriesDimArray;
begin
  AssertTrue(FOpt.SetOptionText('{ series: [{ data: [[1, 2, 3], [4, 5]] },'
    + ' { data: [7, [1, 2]] }, { data: [null, [1, 2]] }, { data: [] }] }'));
  d := TJSONArray(TJSONObject(FOpt.ComponentAt('series', 0)).Find('data'));
  AssertEquals('a three-tuple first', 3, TySeriesDetectedDimCount(d));
  d := TJSONArray(TJSONObject(FOpt.ComponentAt('series', 1)).Find('data'));
  AssertEquals('a scalar first is one column', 1, TySeriesDetectedDimCount(d));
  d := TJSONArray(TJSONObject(FOpt.ComponentAt('series', 2)).Find('data'));
  AssertEquals('and so is a NULL first, literally', 1, TySeriesDetectedDimCount(d));
  d := TJSONArray(TJSONObject(FOpt.ComponentAt('series', 3)).Find('data'));
  AssertEquals('empty data is one column, not none', 1, TySeriesDetectedDimCount(d));
  SetLength(dims, 0);
  AssertFalse('and with no category column there is no index mode',
    TySeriesUsesRowIndex(d, dims));
end;

procedure TAdvChartBuilderTest.TestNamesThatAreNotOnTheAxisAreGaps;
var b: TTyChartBuild; st: TTyDataStore; dims: TTySeriesDimArray; i: Integer;
begin
  { A fixed category list is the axis' list. A name that is not in it names no
    band, so it is a gap -- never a new category appended behind the axis' back,
    which would put a bar where the axis has no tick. }
  b := Build('{ xAxis: { data: [''A'', ''B'', ''C''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [[''A'', 1], [''Z'', 2], [''-'', 3]] }] }',
    TyRectF(0, 0, 600, 400));
  dims := TySeriesCartesianDims(b.Grid(0).CartesianByIndex(0), 0);
  st := TTyDataStore.Create;
  try
    for i := 0 to High(dims) do
    begin
      st.AddDimension(dims[i].Name, dims[i].Kind);
      if dims[i].Axis <> nil then st.UseOrdinalMeta(i, dims[i].Axis.Categories);
    end;
    TyFillSeriesStore(FOpt, 0, dims, st);
    AssertEquals('A is on the axis', 0, st.Get(0, 0), 0);
    AssertTrue('Z is not', IsNan(st.Get(0, 1)));
    AssertTrue('and neither is a dash', IsNan(st.Get(0, 2)));
    AssertEquals('the axis grew nothing', 3, b.Axis('xAxis', 0).Categories.Count);
  finally
    st.Free;
  end;
end;

procedure TAdvChartBuilderTest.TestPerDatumNameAndId;
var b: TTyChartBuild; st: TTyDataStore; dims: TTySeriesDimArray; i: Integer;
begin
  { A number is coerced to its decimal form; a boolean is REJECTED rather than
    becoming the string 'true'. }
  b := Build('{ xAxis: {}, yAxis: {}, series: [{ type: ''scatter'', data: ['
    + ' { value: 1, name: ''first'', id: ''a'' },'
    + ' { value: 2, name: 2001 },'
    + ' { value: 3, name: true },'
    + ' 4 ] }] }', TyRectF(0, 0, 600, 400));
  dims := TySeriesCartesianDims(b.Grid(0).CartesianByIndex(0), 0);
  st := TTyDataStore.Create;
  try
    for i := 0 to High(dims) do st.AddDimension(dims[i].Name, dims[i].Kind);
    TyFillSeriesStore(FOpt, 0, dims, st);
    AssertEquals('first', st.GetName(0));
    AssertEquals('a', st.GetId(0));
    AssertEquals('a number becomes its decimal form', '2001', st.GetName(1));
    AssertEquals('a boolean is refused', '', st.GetName(2));
    AssertEquals('and a bare scalar has no name', '', st.GetName(3));
    AssertEquals('nor an id', '', st.GetId(1));
  finally
    st.Free;
  end;
end;

procedure TAdvChartBuilderTest.TestPerDatumOverridesUseDottedPaths;
var b: TTyChartBuild; st: TTyDataStore; dims: TTySeriesDimArray; i: Integer;
begin
  { Interned by LEAF path, not by top-level key, because every read downstream
    is a leaf read. Nothing needs a list of supported keys, and a nested style
    override costs one slot rather than a subtree. }
  b := Build('{ xAxis: {}, yAxis: {}, series: [{ type: ''scatter'', data: ['
    + ' { value: 1, symbolSize: 20, itemStyle: { color: ''#f00'', borderWidth: 2 },'
    + '   emphasis: { itemStyle: { color: ''#00f'' } } },'
    + ' 2 ] }] }', TyRectF(0, 0, 600, 400));
  dims := TySeriesCartesianDims(b.Grid(0).CartesianByIndex(0), 0);
  st := TTyDataStore.Create;
  try
    for i := 0 to High(dims) do st.AddDimension(dims[i].Name, dims[i].Kind);
    TyFillSeriesStore(FOpt, 0, dims, st);
    AssertTrue('a top-level scalar', st.HasOverride(0, TyOverrideKey('symbolSize')));
    AssertEquals(20, st.GetOverride(0, TyOverrideKey('symbolSize')).Num, 0);
    AssertEquals('a nested leaf', '#f00',
      st.GetOverride(0, TyOverrideKey('itemStyle.color')).Text);
    AssertEquals(2, st.GetOverride(0, TyOverrideKey('itemStyle.borderWidth')).Num, 0);
    AssertEquals('three levels deep', '#00f',
      st.GetOverride(0, TyOverrideKey('emphasis.itemStyle.color')).Text);
    AssertFalse('the plain row overrides nothing',
      st.HasOverride(1, TyOverrideKey('symbolSize')));
    AssertFalse('and value is not an override', st.HasOverride(0, TyOverrideKey('value')));
  finally
    st.Free;
  end;
end;

procedure TAdvChartBuilderTest.TestTwoSeriesShareTheAxisCategoryList;
var
  b: TTyChartBuild;
  sa, sb: TTyDataStore;
  dims: TTySeriesDimArray;
  i: Integer;
begin
  { A COLLECTING axis -- type category with no data of its own -- takes its
    categories from whatever the series bring, and both series have to intern
    against the SAME list. With private lists they would disagree about which
    name ordinal 0 is and render offset from each other on an axis they share. }
  b := Build('{ xAxis: { type: ''category'' }, yAxis: {}, series: ['
    + ' { type: ''bar'', data: [[''Mon'', 1], [''Tue'', 2]] },'
    + ' { type: ''line'', data: [[''Tue'', 3], [''Wed'', 4]] } ] }',
    TyRectF(0, 0, 600, 400));
  dims := TySeriesCartesianDims(b.Grid(0).CartesianByIndex(0), 0);
  sa := TTyDataStore.Create;
  sb := TTyDataStore.Create;
  try
    for i := 0 to High(dims) do
    begin
      sa.AddDimension(dims[i].Name, dims[i].Kind);
      sb.AddDimension(dims[i].Name, dims[i].Kind);
      if dims[i].Axis <> nil then
      begin
        sa.UseOrdinalMeta(i, dims[i].Axis.Categories);
        sb.UseOrdinalMeta(i, dims[i].Axis.Categories);
      end;
    end;
    TyFillSeriesStore(FOpt, 0, dims, sa);
    TyFillSeriesStore(FOpt, 1, dims, sb);
    AssertEquals('one list, three names', 3, b.Axis('xAxis', 0).Categories.Count);
    AssertEquals('Tue is 1 in the first series', 1, sa.Get(0, 1), 0);
    AssertEquals('and 1 in the second too', 1, sb.Get(0, 0), 0);
    AssertEquals('Wed came from the second', 2, sb.Get(0, 1), 0);
  finally
    sa.Free;
    sb.Free;
  end;
end;

procedure TAdvChartBuilderTest.TestATimeAxisGetsATimeColumn;
var b: TTyChartBuild; st: TTyDataStore; dims: TTySeriesDimArray; i: Integer;
begin
  { A time axis' column has to be parsed AS time, or a date string is read as a
    number, fails, and the whole series is gaps. Nothing else in this file
    builds a time axis, so the mapping had no coverage at all. }
  b := Build('{ xAxis: { type: ''time'' }, yAxis: {},'
    + ' series: [{ type: ''line'', data: [[''2024-03-05T00:00:00Z'', 5]] }] }',
    TyRectF(0, 0, 600, 400));
  dims := TySeriesCartesianDims(b.Grid(0).CartesianByIndex(0), 0);
  AssertTrue('the column is a time column', dims[0].Kind = ddtTime);
  AssertTrue('and the value column is not', dims[1].Kind = ddtFloat);
  st := TTyDataStore.Create;
  try
    for i := 0 to High(dims) do st.AddDimension(dims[i].Name, dims[i].Kind);
    TyFillSeriesStore(FOpt, 0, dims, st);
    AssertEquals('the date parsed to epoch milliseconds',
      TyDateTimeToMs(EncodeDate(2024, 3, 5)), st.Get(0, 0), 0);
    AssertEquals(5, st.Get(1, 0), 0);
  finally
    st.Free;
  end;
end;

function TFixedMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
var
  perLine, i: Integer;
begin
  { Seven pixels a character, the same figure MeasureLine reports -- so a test
    using this fake gets wrapping that agrees with its own measurements.
    Returning AText unchanged would make every wrapping assertion pass without
    anything being wrapped. }
  Result := AText;
  if (AText = '') or (AMaxWidth <= 0) then Exit;
  perLine := Trunc(AMaxWidth / 7.0);
  if perLine < 1 then perLine := 1;
  if Length(AText) <= perLine then Exit;
  Result := '';
  i := 1;
  while i <= Length(AText) do
  begin
    if Result <> '' then Result := Result + LineEnding;
    Result := Result + Copy(AText, i, perLine);
    Inc(i, perLine);
  end;
end;

initialization
  RegisterTest(TAdvChartBuilderTest);
end.
