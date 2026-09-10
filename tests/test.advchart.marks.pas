unit test.advchart.marks;
{$mode objfpc}{$H+}
{ Series marks: a bound series plus its store, turned into paint-list elements.

  Asserted on the LIST rather than on pixels, because that is where the
  decisions are -- how many marks, what shape, which datum each answers for --
  and a pixel count cannot tell a bar at the right height from one at the wrong
  one. The drawn result is checked in test.advancechart, through the control. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry,
     tyControls.AdvChart.Types, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Data,
     tyControls.AdvChart.Shape, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Series, tyControls.AdvChart.Marks,
     tyControls.AdvChart.BarLayout, tyControls.AdvChart.Option,
     tyControls.AdvChart.Symbol;
type
  TAdvChartMarksTest = class(TTestCase)
  private
    FCart: TTyCartesian2D;
    FStore: TTyDataStore;
    FList: TTyPaintList;
    FBinding: TTySeriesBinding;
    procedure SetUp; override;
    procedure TearDown; override;
    { A category x axis of ACount names against a 0..100 value y, sized to
      400x300, with AValues appended as rows. }
    procedure Given(const AType: string; ACount: Integer;
      const AValues: array of Double);
    { The same, turned on its side: categories on Y, values on X -- a
      horizontal bar chart. Its own fixture rather than a flag on Given,
      because what changes is which axis is the base, and that is the thing
      under test. }
    procedure GivenSideways(const AType: string; ACount: Integer;
      const AValues: array of Double);
  published
    procedure TestABarIsOneRectPerRowFromDataToLayout;
    procedure TestAGapDrawsNoBarRatherThanAZeroOne;
    procedure TestBarsLeaveTheCategoryGapUpstreamLeaves;
    procedure TestALineIsOnePolylineAndAGapBreaksIt;
    procedure TestEveryMarkAnswersForItsOwnRow;
    procedure TestAnUnknownSeriesTypeDrawsNothing;
    procedure TestThePublishedAnswerMatchesWhatIsActuallyDrawn;
    procedure TestTheSolvedColumnDecidesWhereTheBarGoes;
    procedure TestAValueTooSmallToSeeStillGetsBarMinHeight;
    procedure TestARoundedBarIsARoundedShapeNotAFlagNobodyReads;
    procedure TestABarRoundedOnlyAtTheTopKeepsItsSquareFoot;
    procedure TestTheBackingStripSpansThePlotAndTakesNoHovers;
    procedure TestABarPastTheAxisIsCutAtThePlotEdge;
    procedure TestAColumnOfNoWidthDrawsNothingRatherThanTheWholeBand;
    procedure TestAHorizontalStackedBarStacksAlongXNotY;
    procedure TestTheBottomOfAStackKeepsTheAxisOwnBaseline;
    procedure TestAStackedLineIsDrawnThroughItsTotals;
    procedure TestAnAreaIsAClosedRingUnderTheLine;
    procedure TestTheAreaOriginFollowsTheAxisWhenItIsAllOneSign;
    procedure TestAStackedAreaSitsOnTheOneBelowIt;
    procedure TestConnectNullsJoinsTheRunInsteadOfBreakingIt;
    procedure TestStepTurnsWhereEachModeSaysItDoes;
    procedure TestTheLineOptionsAreActuallyReadFromTheOption;
    procedure TestTheFillIsPaintedBehindItsLine;
    procedure TestASteppedAreaFollowsItsSteppedLine;
    procedure TestACoordinateThatWillNotMapBreaksTheRun;
    procedure TestAScatterIsOneSymbolPerDatum;
    procedure TestAnEmptySymbolIsStrokedAndFilledWithTheThemesOwnGround;
    procedure TestABubbleTakesItsSizeFromTheData;
    procedure TestALineWearsAMarkerOnEveryPoint;
    procedure TestCrowdedMarkersThinToTheAxisOwnLabelInterval;
  end;

implementation

procedure TAdvChartMarksTest.SetUp;
begin
  inherited SetUp;
  FCart := nil;
  FStore := nil;
  FList := TTyPaintList.Create;
end;

procedure TAdvChartMarksTest.TearDown;
begin
  FreeAndNil(FList);
  FreeAndNil(FStore);
  FreeAndNil(FCart);
  inherited TearDown;
end;

procedure TAdvChartMarksTest.Given(const AType: string; ACount: Integer;
  const AValues: array of Double);
var
  ax, ay: TTyAxis;
  sy: TTyIntervalScale;
  cats: TTyStringArray;
  i: Integer;
begin
  FCart := TTyCartesian2D.Create;
  ax := TTyAxis.Create('x', TTyOrdinalScale.Create, True);
  ax.AxisType := atCategory;
  SetLength(cats, ACount);
  for i := 0 to ACount - 1 do cats[i] := Chr(Ord('a') + i);
  ax.SetCategories(cats);
  ax.OnBand := True;
  sy := TTyIntervalScale.Create;
  sy.SetExtent(TyRange(0, 100));
  ay := TTyAxis.Create('y', sy, False);
  FCart.AddAxis(ax);
  FCart.AddAxis(ay);
  FCart.SetRect(TyRectF(0, 0, 400, 300));

  FStore := TTyDataStore.Create;
  FStore.AddDimension('x', ddtOrdinal);
  FStore.AddDimension('y', ddtFloat);
  FStore.UseOrdinalMeta(0, ax.Categories);
  for i := 0 to High(AValues) do
    FStore.AppendRow([Double(i), AValues[i]]);

  FBinding := Default(TTySeriesBinding);
  FBinding.SeriesIndex := 0;
  FBinding.SeriesType := AType;
  FBinding.Resolved := True;
  FBinding.HasAxes := True;
  FBinding.Cart := FCart;
  FBinding.XAxis := ax;
  FBinding.YAxis := ay;
  FBinding.BaseAxis := ax;
  FBinding.ValueAxis := ay;
end;

procedure TAdvChartMarksTest.GivenSideways(const AType: string;
  ACount: Integer; const AValues: array of Double);
var
  ax, ay: TTyAxis;
  sx: TTyIntervalScale;
  cats: TTyStringArray;
  i: Integer;
begin
  FCart := TTyCartesian2D.Create;
  sx := TTyIntervalScale.Create;
  sx.SetExtent(TyRange(0, 100));
  ax := TTyAxis.Create('x', sx, True);
  ay := TTyAxis.Create('y', TTyOrdinalScale.Create, False);
  ay.AxisType := atCategory;
  SetLength(cats, ACount);
  for i := 0 to ACount - 1 do cats[i] := Chr(Ord('a') + i);
  ay.SetCategories(cats);
  ay.OnBand := True;
  FCart.AddAxis(ax);
  FCart.AddAxis(ay);
  FCart.SetRect(TyRectF(0, 0, 400, 300));

  FStore := TTyDataStore.Create;
  FStore.AddDimension('x', ddtFloat);
  FStore.AddDimension('y', ddtOrdinal);
  FStore.UseOrdinalMeta(1, ay.Categories);
  for i := 0 to High(AValues) do
    FStore.AppendRow([AValues[i], Double(i)]);

  FBinding := Default(TTySeriesBinding);
  FBinding.SeriesIndex := 0;
  FBinding.SeriesType := AType;
  FBinding.Resolved := True;
  FBinding.HasAxes := True;
  FBinding.Cart := FCart;
  FBinding.XAxis := ax;
  FBinding.YAxis := ay;
  FBinding.BaseAxis := ay;
  FBinding.ValueAxis := ax;
end;

procedure TAdvChartMarksTest.TestABarIsOneRectPerRowFromDataToLayout;
var
  n, i: Integer;
  b, cell: TTyRectF;
begin
  { ONE RECT PER ROW, and the rect is DataToLayout's -- contract (1) of the
    spec, which exists so a bar and the cell a nested chart would get are the
    same rectangle. A renderer that computed it itself would be a second
    producer of a number the coordinate system already owns. }
  Given('bar', 4, [10, 20, 30, 40]);
  n := TyBuildSeriesMarks(FBinding, FStore, TyNoStack, TySeriesVisual($FF3366CC), FList);
  AssertEquals('one mark per row', 4, n);
  AssertEquals(4, FList.Count);

  for i := 0 to 3 do
  begin
    b := TyShapeBounds(FList.Element(i).Shape);
    cell := FCart.DataToLayout([Double(i), 10.0 * (i + 1)]).Rect;
    AssertEquals(Format('bar %d sits at its cell top', [i]),
      cell.Top, b.Top, 0.001);
    AssertEquals(Format('bar %d reaches the baseline', [i]),
      cell.Bottom, b.Bottom, 0.001);
    AssertEquals(Format('bar %d is centred on its band', [i]),
      (cell.Left + cell.Right) / 2, (b.Left + b.Right) / 2, 0.001);
  end;
end;

procedure TAdvChartMarksTest.TestAGapDrawsNoBarRatherThanAZeroOne;
var n: Integer;
begin
  { NaN IS THE SINGLE SPELLING OF NO DATA across all four dimension types --
    the store's header says so. A gap must draw NOTHING; a bar of height zero
    would read as a real measurement of nothing, which is a different claim. }
  Given('bar', 4, [10, NaN, 30, 40]);
  n := TyBuildSeriesMarks(FBinding, FStore, TyNoStack, TySeriesVisual($FF3366CC), FList);
  AssertEquals('three rows have values, so three bars', 3, n);
end;

procedure TAdvChartMarksTest.TestBarsLeaveTheCategoryGapUpstreamLeaves;
var
  b, cell: TTyRectF;
  v: TTySeriesVisual;
  col: TTyBarColumn;
  band: Double;
begin
  { THIS TEST USED TO PIN 0.8, AND 0.8 WAS WRONG. It cited "ECharts'
    barCategoryGap is '20%'", which is what the published option reference and
    this repo's generated catalog both say. The 6.1.0 source says otherwise:
    there is no fixed default at all, it is `max(35 - columns*4, 15) + '%'`, so
    a lone bar leaves 31% and takes 0.69 of its band.

    Nothing here writes 0.69 down. The expected width is asked of the solver,
    because a test that repeats a constant only proves the constant was copied
    twice; what is worth pinning is that the mark and the solver agree, and
    that the number is not 1 (the bar is narrowed at all) and not 0.8 (the old
    wrong one, which a careless revert would restore). }
  Given('bar', 2, [50, 50]);
  v := TySeriesVisual($FF3366CC);
  AssertFalse('an unsolved visual asks the solver on the spot', v.Bar.Solved);
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);

  b := TyShapeBounds(FList.Element(0).Shape);
  cell := FCart.DataToLayout([0.0, 50.0]).Rect;
  band := cell.Right - cell.Left;
  col := TyBarColumnForOneSeries(band);
  AssertEquals('the mark is exactly the column the solver gives',
    col.Width, b.Right - b.Left, 0.001);
  AssertTrue('and it does not reach the band edge', b.Left > cell.Left);

  { THE ACTUAL NUMBER, once, so a solver that silently started answering
    something else would be caught here rather than agreeing with itself. }
  AssertEquals('one column leaves the 31% gap upstream computes',
    band * 0.69, col.Width, band * 1e-6);
  AssertTrue('which is not the old 0.8', Abs(col.Width - band * 0.8) > 1);

  { CENTRED, which is what an offset of -Width/2 means and the only arrangement
    a single series can correctly have. }
  AssertEquals('a lone column is centred on its band',
    -col.Width / 2, col.Offset, 0.001);
  AssertEquals('so the mark is too', (cell.Left + cell.Right) / 2,
    (b.Left + b.Right) / 2, 0.001);
end;

procedure TAdvChartMarksTest.TestALineIsOnePolylineAndAGapBreaksIt;
var
  n: Integer;
  v: TTySeriesVisual;
begin
  { Markers off: this test is about the LINE. A line shows one on every
    point by default, so counting elements would count those too. }
  v := TySeriesVisual($FF3366CC);
  v.Line.ShowSymbol := False;
  { ONE POLYLINE for a run of points -- not one element per segment, which
    would make the ordering and the hit test answer per segment. }
  Given('line', 4, [10, 20, 30, 40]);
  n := TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
  AssertEquals('four points make one polyline', 1, n);
  AssertEquals(Ord(cskPolyline), Ord(FList.Element(0).Shape.Kind));
  AssertEquals('with a point per row', 4,
    Length(FList.Element(0).Shape.Points));

  { A GAP BREAKS IT, it is not joined across. ECharts calls that connectNulls
    and defaults it to false; joining by default draws a segment through data
    that does not exist. }
  FList.Clear;
  FreeAndNil(FStore);
  FreeAndNil(FCart);
  Given('line', 5, [10, 20, NaN, 40, 50]);
  n := TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
  AssertEquals('a gap makes two runs', 2, n);
  AssertEquals('two points before it', 2, Length(FList.Element(0).Shape.Points));
  AssertEquals('and two after', 2, Length(FList.Element(1).Shape.Points));
end;

procedure TAdvChartMarksTest.TestEveryMarkAnswersForItsOwnRow;
var
  i: Integer;
  d: TTyChartDatumRef;
begin
  { THE POINTER HAS TO REPORT THE DATUM THAT WAS DRAWN THERE -- the rule the
    paint list exists to keep. A mark carries its own row, so a hit test
    answers with the row and not with the series. }
  Given('bar', 3, [10, 50, 90]);
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, TySeriesVisual($FF3366CC), FList);
  for i := 0 to 2 do
  begin
    d := FList.Element(i).Datum;
    AssertEquals(Format('mark %d names its series', [i]), 0, d.SeriesIndex);
    AssertEquals(Format('mark %d names its row', [i]), i, d.DataIndex);
    AssertFalse(Format('mark %d is hittable', [i]), FList.Element(i).Silent);
  end;
end;

procedure TAdvChartMarksTest.TestAnUnknownSeriesTypeDrawsNothing;
begin
  { Twenty of the twenty-three types have no renderer yet, and drawing an
    approximation would be worse than drawing nothing -- the control's
    diagnostics are what tell the reader why the plot is empty.

    This used to say `scatter`, which now draws. A test that pins "X is not
    implemented" has to move when X is, and moving it is the point: the
    assertion is about the RULE, not about scatter. }
  Given('pie', 3, [10, 20, 30]);
  AssertEquals('pie has no renderer yet', 0,
    TyBuildSeriesMarks(FBinding, FStore, TyNoStack, TySeriesVisual($FF3366CC), FList));
  AssertEquals(0, FList.Count);
end;

procedure TAdvChartMarksTest.TestThePublishedAnswerMatchesWhatIsActuallyDrawn;
const
  { Every type ECharts 6.1 has, so a renderer landing without its entry being
    noticed here is not possible. }
  cTypes: array[0..22] of string = (
    'line', 'bar', 'pie', 'scatter', 'effectScatter', 'radar', 'tree',
    'treemap', 'sunburst', 'boxplot', 'candlestick', 'heatmap', 'map',
    'parallel', 'lines', 'graph', 'sankey', 'funnel', 'gauge', 'pictorialBar',
    'themeRiver', 'custom', 'chord');
var
  i: Integer;
begin
  { THE EDITOR BELIEVES THIS FUNCTION. Its all-clear row tells the author which
    of their series will appear on screen, and it asks TySeriesTypeHasRenderer
    rather than keeping a list of its own -- so the day the answer and the
    drawing disagree, the panel starts lying and nothing else notices.

    Asserted by DRAWING each type and comparing, which is the only comparison
    that cannot be satisfied by updating one list to match the other. }
  for i := 0 to High(cTypes) do
  begin
    FList.Clear;
    FreeAndNil(FStore);
    FreeAndNil(FCart);
    Given(cTypes[i], 3, [10, 20, 30]);
    { A PIE IS THE ONE TYPE THIS LOOP CANNOT SPEAK FOR. It has no
      coordinate system, so it never enters TyBuildSeriesMarks and the
      comparison below would read as `the answer is yes and nothing is
      drawn` -- which is exactly backwards. Its pixels are counted at the
      control instead, in test.advancechart. }
    if cTypes[i] = 'pie' then
    begin
      AssertTrue('pie draws, on the other pass',
        TySeriesTypeHasRenderer(cTypes[i]));
      AssertEquals('and not through this one', 0,
        TyBuildSeriesMarks(FBinding, FStore, TyNoStack,
          TySeriesVisual($FF3366CC), FList));
      Continue;
    end;
    AssertEquals(cTypes[i] + ': the published answer and the drawing agree',
      TySeriesTypeHasRenderer(cTypes[i]),
      TyBuildSeriesMarks(FBinding, FStore, TyNoStack,
        TySeriesVisual($FF3366CC), FList) > 0);
  end;

  { AND IT IS NOT SIMPLY TRUE FOR EVERYTHING -- the loop above would pass if
    both sides answered yes to every type. }
  AssertTrue('bar draws', TySeriesTypeHasRenderer('bar'));
  AssertTrue('and so does scatter now', TySeriesTypeHasRenderer('scatter'));
  AssertTrue('and pie does, on its own pass', TySeriesTypeHasRenderer('pie'));
  { CASE-SENSITIVE, matching the type registry -- 'Bar' does not resolve as a
    series at all, so answering yes for it would promise a chart that cannot
    draw. }
  AssertFalse('and Bar is not bar', TySeriesTypeHasRenderer('Bar'));
end;

procedure TAdvChartMarksTest.TestTheSolvedColumnDecidesWhereTheBarGoes;
var
  v: TTySeriesVisual;
  b, cell: TTyRectF;
begin
  { THE POINT OF THE SPLIT. Marks does not decide a width; it puts the rect
    where the solved column says. A test that only ever ran the single-series
    fallback would pass with the offset ignored entirely. }
  Given('bar', 2, [50, 50]);
  v := TySeriesVisual($FF3366CC);
  v.Bar.Solved := True;
  v.Bar.Width := 10;
  v.Bar.Offset := 30;          { deliberately off-centre and to the right }
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);

  b := TyShapeBounds(FList.Element(0).Shape);
  cell := FCart.DataToLayout([0.0, 50.0]).Rect;
  AssertEquals('the width is the column''s', 10.0, b.Right - b.Left, 0.001);
  AssertEquals('and it starts at the centre plus the offset',
    (cell.Left + cell.Right) / 2 + 30, b.Left, 0.001);
  AssertTrue('so it is not centred any more',
    b.Left > (cell.Left + cell.Right) / 2);
end;

procedure TAdvChartMarksTest.TestAValueTooSmallToSeeStillGetsBarMinHeight;
var
  v: TTySeriesVisual;
  b: TTyRectF;
begin
  { A value of zero draws nothing at all without this, and a chart of mostly
    tiny values looks like a chart of no values. }
  Given('bar', 2, [0, 100]);
  v := TySeriesVisual($FF3366CC);
  v.Bar := TyBarColumnForOneSeries(200);
  v.Bar.MinHeightPx := 6;
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);

  b := TyShapeBounds(FList.Element(0).Shape);
  AssertEquals('the zero bar is drawn at the minimum height',
    6.0, b.Bottom - b.Top, 0.001);

  { UPWARDS, because upstream includes zero in the negative test precisely so a
    zero bar points the way a positive one does. On a y axis that runs 0 at the
    bottom, "up" is a smaller Bottom than the baseline. }
  AssertTrue('and it points the way a positive value would',
    b.Bottom <= FCart.DataToPoint([0.0, 0.0]).Y + 0.001);

  { AND A TALL BAR IS UNTOUCHED -- the minimum is a floor, not a size. }
  b := TyShapeBounds(FList.Element(1).Shape);
  AssertTrue('a bar that is already tall keeps its height',
    b.Bottom - b.Top > 100);
end;

procedure TAdvChartMarksTest.TestARoundedBarIsARoundedShapeNotAFlagNobodyReads;
var
  v: TTySeriesVisual;
begin
  { The radius has to reach the SHAPE, or it is a field the solver fills in and
    nothing looks at -- which is this repo's most repeated failure. }
  Given('bar', 1, [50]);
  v := TySeriesVisual($FF3366CC);
  v.Bar := TyBarColumnForOneSeries(200);
  v.Bar.Radii := TyCornerRadii([5]);
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
  AssertEquals('a radius makes a round rect',
    Ord(cskRoundRect), Ord(FList.Element(0).Shape.Kind));
  AssertEquals('carrying the radius', 5.0, FList.Element(0).Shape.Radii[0], 1e-9);
  AssertEquals('on every corner', 5.0, FList.Element(0).Shape.Radii[2], 1e-9);

  { AND NO RADIUS STAYS A PLAIN RECT, so every bar is not quietly rounded. }
  FList.Clear;
  v.Bar.Radii := TyCornerRadii([]);
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
  AssertEquals('no radius stays square',
    Ord(cskRect), Ord(FList.Element(0).Shape.Kind));
end;

procedure TAdvChartMarksTest.TestABarRoundedOnlyAtTheTopKeepsItsSquareFoot;
var v: TTySeriesVisual;
begin
  { `borderRadius: [8, 8, 0, 0]` is what nearly every rounded bar in the
    gallery asks for, and the scalar reader this unit had could not express it
    -- it rounded all four corners or none. }
  Given('bar', 1, [50]);
  v := TySeriesVisual($FF3366CC);
  v.Bar := TyBarColumnForOneSeries(200);
  v.Bar.Radii := TyCornerRadii([8, 8, 0, 0]);
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
  AssertEquals('the top-left is rounded', 8.0,
    FList.Element(0).Shape.Radii[0], 1e-9);
  AssertEquals('the top-right too', 8.0, FList.Element(0).Shape.Radii[1], 1e-9);
  AssertEquals('and the foot is square', 0.0,
    FList.Element(0).Shape.Radii[2], 1e-9);
  AssertEquals('both of it', 0.0, FList.Element(0).Shape.Radii[3], 1e-9);
end;

procedure TAdvChartMarksTest.TestTheBackingStripSpansThePlotAndTakesNoHovers;
var
  v: TTySeriesVisual;
  strip: TTyChartElement;
begin
  { showBackground draws the bar's own band stretched over the whole plot along
    the value axis -- BarView.ts:1237-1246. The plot here is 400 by 300 and the
    bar reaches half of it, so the strip is the one that goes all the way. }
  Given('bar', 2, [50, 50]);
  v := TySeriesVisual($FF3366CC);
  v.Bar := TyBarColumnForOneSeries(200);
  v.Bar.ShowBackground := True;
  v.BackgroundFill := $FF224466;
  AssertEquals('two bars and two strips', 4,
    TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList));

  { BEHIND, not in front: upstream gives the strip and the bar the same z2 and
    lets insertion decide, and this list ties the same way. }
  strip := FList.Element(0);
  AssertEquals('the strip is emitted first', 0, FList.PaintOrder(0));
  AssertEquals('the strip spans the plot', 0.0, strip.Shape.Bounds.Top, 1e-9);
  AssertEquals('all of it', 300.0, strip.Shape.Bounds.Bottom, 1e-9);
  AssertEquals('but only its own band across', FList.Element(1).Shape.Bounds.Left,
    strip.Shape.Bounds.Left, 1e-9);
  AssertEquals('', FList.Element(1).Shape.Bounds.Right,
    strip.Shape.Bounds.Right, 1e-9);
  AssertEquals('in the colour it was handed', $FF224466, strip.Style.FillColor);

  { SILENT. A strip the height of the plot that answered the pointer would take
    every hover the bar under it was meant to get -- the same reason a gridline
    is silent. }
  AssertTrue('and it takes no hovers', strip.Silent);
  AssertEquals('so the bar still answers', 0,
    FList.HitTest(strip.Shape.Bounds.Left + 5, 250, 96).SeriesIndex);

  { OFF BY DEFAULT, BarSeries.ts:151 -- a chart that never asked must not get
    a grey band behind every bar. }
  FList.Clear;
  v.Bar.ShowBackground := False;
  AssertEquals('nothing extra', 2,
    TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList));
end;

procedure TAdvChartMarksTest.TestABarPastTheAxisIsCutAtThePlotEdge;
var
  v: TTySeriesVisual;
  b: TTyRectF;
begin
  { The y axis is fixed at 0..100 and the value is 150, so the bar runs off the
    top of the plot. clip defaults to TRUE, and upstream does it by
    INTERSECTING THE RECT rather than by setting a clip path -- so the shape
    stays a real rect and the pointer keeps agreeing with the ink. }
  Given('bar', 1, [150]);
  v := TySeriesVisual($FF3366CC);
  v.Bar := TyBarColumnForOneSeries(200);
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
  b := FList.Element(0).Shape.Bounds;
  AssertEquals('cut at the plot edge', 0.0, b.Top, 1e-9);
  AssertEquals('and still standing on the baseline', 300.0, b.Bottom, 1e-9);

  { AND IT CAN BE SWITCHED OFF, which is the whole reason the key exists. }
  FList.Clear;
  v.Bar.Clip := False;
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
  AssertTrue('unclipped, it runs off the top: ' +
    FloatToStr(FList.Element(0).Shape.Bounds.Top),
    FList.Element(0).Shape.Bounds.Top < 0);

  { BOTH ENDS, and it takes a second fixture to say so: the bar above runs off
    the near edge only, so a clip that moved Left and Top and left Right and
    Bottom alone would pass every assertion so far. Turned on its side, the
    same overshoot goes off the FAR edge instead. }
  FreeAndNil(FStore);
  FreeAndNil(FCart);
  FList.Clear;
  GivenSideways('bar', 1, [150]);
  v := TySeriesVisual($FF3366CC);
  v.Bar := TyBarColumnForOneSeries(200);
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
  b := FList.Element(0).Shape.Bounds;
  AssertEquals('cut at the far edge too', 400.0, b.Right, 1e-9);
  AssertEquals('and still standing on the baseline', 0.0, b.Left, 1e-9);
end;

procedure TAdvChartMarksTest.TestAColumnOfNoWidthDrawsNothingRatherThanTheWholeBand;
var v: TTySeriesVisual;
begin
  { `barCategoryGap: '100%'` solves every column to zero width. The first
    version of PlaceInBand treated that as "leave the rect alone", and the rect
    it was leaving alone was the WHOLE CELL -- so asking for no bars drew the
    widest bars possible. The guard downstream could never fire, because a
    zero-width rect never reached it. }
  Given('bar', 2, [50, 50]);
  v := TySeriesVisual($FF3366CC);
  v.Bar.Solved := True;
  v.Bar.Width := 0;
  v.Bar.Offset := 0;
  AssertEquals('a zero-width column draws nothing', 0,
    TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList));
  AssertEquals('and adds nothing to hit-test against', 0, FList.Count);
end;

procedure TAdvChartMarksTest.TestAHorizontalStackedBarStacksAlongXNotY;
var
  v: TTySeriesVisual;
  stk: TTySeriesStack;
  b: TTyRectF;
  resultCol: Integer;
begin
  { THE VALUE IS ON WHICHEVER AXIS IS NOT THE BASE. Turned sideways that is X,
    and a renderer that substituted the cumulative into y unconditionally would
    leave horizontal stacked bars looking unstacked -- drawn from the axis to
    their own value, with the accumulation computed and thrown away. That was
    the first version of this code.

    Row 0 is its own value 30; row 1 is 20 stacked on 30, so it runs from 30 to
    50 rather than from 0 to 20. }
  GivenSideways('bar', 2, [30, 20]);
  resultCol := FStore.AddDimension('total', ddtFloat);
  FStore.SetCalculated(resultCol, 0, 30);
  FStore.SetCalculated(resultCol, 1, 50);

  stk := TyNoStack;
  stk.Stacked := True;
  stk.HasBelow := True;
  stk.ResultCol := resultCol;

  v := TySeriesVisual($FF3366CC);
  v.Bar := TyBarColumnForOneSeries(100);
  TyBuildSeriesMarks(FBinding, FStore, stk, v, FList);

  b := TyShapeBounds(FList.Element(1).Shape);
  AssertEquals('the bar ENDS at the cumulative 50',
    FCart.DataToPoint([50.0, 1.0]).X, b.Right, 0.001);
  AssertEquals('and STARTS at the value below it, not at the axis',
    FCart.DataToPoint([30.0, 1.0]).X, b.Left, 0.001);
  AssertTrue('so it does not reach the baseline',
    b.Left > FCart.DataToPoint([0.0, 1.0]).X + 1);
end;

procedure TAdvChartMarksTest.TestTheBottomOfAStackKeepsTheAxisOwnBaseline;
var
  v: TTySeriesVisual;
  stk: TTySeriesStack;
  b: TTyRectF;
  resultCol: Integer;
begin
  { THE BOTTOM MEMBER IS DRAWN LIKE AN UNSTACKED SERIES. It accumulates onto
    nothing, so its floor is the axis' own baseline -- and computing one for it
    as (cumulative - own) would put it at ZERO instead.

    ON AN AXIS THAT STARTS AT ZERO THE TWO ARE THE SAME NUMBER, which is why
    every earlier test missed this: a mutant that gave the bottom member a
    computed floor survived them all. The axis here starts at 10 so the two
    answers differ. }
  Given('bar', 1, [40]);
  TTyIntervalScale(FBinding.ValueAxis.Scale).SetExtent(TyRange(10, 100));
  resultCol := FStore.AddDimension('total', ddtFloat);
  FStore.SetCalculated(resultCol, 0, 40);

  stk := TyNoStack;
  stk.Stacked := True;
  stk.HasBelow := False;          { the bottom of its pile }
  stk.ResultCol := resultCol;

  v := TySeriesVisual($FF3366CC);
  v.Bar := TyBarColumnForOneSeries(100);
  TyBuildSeriesMarks(FBinding, FStore, stk, v, FList);

  b := TyShapeBounds(FList.Element(0).Shape);
  AssertEquals('it stands on the axis, at 10',
    FCart.DataToPoint([0.0, 10.0]).Y, b.Bottom, 0.001);
  AssertEquals('and reaches its value', FCart.DataToPoint([0.0, 40.0]).Y,
    b.Top, 0.001);
  AssertTrue('not down at zero, which is off this axis',
    b.Bottom < FCart.DataToPoint([0.0, 0.0]).Y - 1);
end;

procedure TAdvChartMarksTest.TestAStackedLineIsDrawnThroughItsTotals;
var
  v: TTySeriesVisual;
  stk: TTySeriesStack;
  resultCol: Integer;
  pts: TTyPointFArray;
begin
  { A LINE PLOTS THE CUMULATIVE TOO. Only the bar had a test for it, and a
    mutant that left the line reading its own values survived: the stack was
    computed and then thrown away for exactly the series type that most often
    uses it, since a stacked area chart is a stacked line underneath. }
  Given('line', 3, [10, 20, 30]);
  resultCol := FStore.AddDimension('total', ddtFloat);
  FStore.SetCalculated(resultCol, 0, 15);
  FStore.SetCalculated(resultCol, 1, 25);
  FStore.SetCalculated(resultCol, 2, 35);

  stk := TyNoStack;
  stk.Stacked := True;
  stk.HasBelow := True;
  stk.ResultCol := resultCol;

  v := TySeriesVisual($FF3366CC);
  { Markers off: this test is about the LINE. A line shows one on every
    point by default, so counting elements would count those too. }
  v.Line.ShowSymbol := False;
  AssertEquals('one polyline', 1,
    TyBuildSeriesMarks(FBinding, FStore, stk, v, FList));
  pts := FList.Element(0).Shape.Points;
  AssertEquals('three points', 3, Length(pts));
  AssertEquals('the first is at the total, not the value',
    FCart.DataToPoint([0.0, 15.0]).Y, pts[0].Y, 0.001);
  AssertEquals('and so is the last',
    FCart.DataToPoint([2.0, 35.0]).Y, pts[2].Y, 0.001);
  AssertTrue('which is not where its own value would put it',
    Abs(pts[0].Y - FCart.DataToPoint([0.0, 10.0]).Y) > 1);
end;

procedure TAdvChartMarksTest.TestAnAreaIsAClosedRingUnderTheLine;
var
  v: TTySeriesVisual;
  poly: TTyPointFArray;
  i: Integer;
  base: Double;
begin
  { TWO ELEMENTS, AREA FIRST. The fill and the line are separate shapes -- one
    closed polygon, one open polyline -- and the area is inserted first so the
    line is drawn OVER its own shading rather than under it. }
  Given('line', 3, [10, 20, 30]);
  v := TySeriesVisual($FF3366CC);
  { Markers off: this test is about the LINE. A line shows one on every
    point by default, so counting elements would count those too. }
  v.Line.ShowSymbol := False;
  v.Line.HasArea := True;
  AssertEquals('an area makes two elements, not one', 2,
    TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList));
  AssertEquals('the area is first, so it is behind',
    Ord(cskPolygon), Ord(FList.Element(0).Shape.Kind));
  AssertEquals('and the line is on top',
    Ord(cskPolyline), Ord(FList.Element(1).Shape.Kind));

  { A RING: three points along the top, then the same three along the bottom in
    REVERSE. Walking the lower edge forwards would cross the shape over itself
    and fill an hourglass. }
  poly := FList.Element(0).Shape.Points;
  AssertEquals('three up and three back', 6, Length(poly));
  base := FCart.DataToPoint([0.0, 0.0]).Y;
  for i := 0 to 2 do
    AssertEquals(Format('top %d is the datum', [i]),
      FCart.DataToPoint([Double(i), 10.0 * (i + 1)]).Y, poly[i].Y, 0.001);
  AssertEquals('the return leg starts under the LAST point',
    FCart.DataToPoint([2.0, 0.0]).X, poly[3].X, 0.001);
  for i := 3 to 5 do
    AssertEquals(Format('bottom %d is on the baseline', [i]),
      base, poly[i].Y, 0.001);

  { THE FILL IS NOT HIT-TESTABLE. A pointer over the shading should find the
    line, not the decoration behind it. }
  AssertTrue('the area is silent', FList.Element(0).Silent);
  AssertFalse('the line is not', FList.Element(1).Silent);
end;

procedure TAdvChartMarksTest.TestTheAreaOriginFollowsTheAxisWhenItIsAllOneSign;
var
  v: TTySeriesVisual;
  poly: TTyPointFArray;
begin
  { 'auto' IS NOT SIMPLY ZERO. When the whole axis sits above zero the area
    starts at the BOTTOM OF THE RANGE, because a fill reaching for a zero that
    is not on the axis would run off the plot. }
  Given('line', 2, [50, 60]);
  TTyIntervalScale(FBinding.ValueAxis.Scale).SetExtent(TyRange(40, 100));
  v := TySeriesVisual($FF3366CC);
  { Markers off: this test is about the LINE. A line shows one on every
    point by default, so counting elements would count those too. }
  v.Line.ShowSymbol := False;
  v.Line.HasArea := True;
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
  poly := FList.Element(0).Shape.Points;
  AssertEquals('the floor is the axis minimum, not zero',
    FCart.DataToPoint([0.0, 40.0]).Y, poly[High(poly)].Y, 0.001);
  AssertTrue('which is not where zero would be',
    Abs(poly[High(poly)].Y - FCart.DataToPoint([0.0, 0.0]).Y) > 1);

  { AN EXPLICIT ORIGIN WINS, and is not clamped into the extent. }
  FList.Clear;
  v.Line.AreaOrigin := laoValue;
  v.Line.AreaOriginValue := 55;
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
  poly := FList.Element(0).Shape.Points;
  AssertEquals('a number is used as given',
    FCart.DataToPoint([0.0, 55.0]).Y, poly[High(poly)].Y, 0.001);

  { 'end' anchors at the TOP of the range, so the belt hangs downwards. }
  FList.Clear;
  v.Line.AreaOrigin := laoEnd;
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
  poly := FList.Element(0).Shape.Points;
  AssertEquals('end is the axis maximum',
    FCart.DataToPoint([0.0, 100.0]).Y, poly[High(poly)].Y, 0.001);
end;

procedure TAdvChartMarksTest.TestAStackedAreaSitsOnTheOneBelowIt;
var
  v: TTySeriesVisual;
  stk: TTySeriesStack;
  poly: TTyPointFArray;
  resultCol, overCol: Integer;
begin
  { WHAT THE stackedOver COLUMN WAS BUILT FOR. A stacked area's lower edge is
    the total underneath it, not the axis -- otherwise every band in a stacked
    area chart is drawn from the floor and they all overlap. }
  Given('line', 2, [10, 20]);
  resultCol := FStore.AddDimension('total', ddtFloat);
  overCol := FStore.AddDimension('over', ddtFloat);
  FStore.SetCalculated(resultCol, 0, 15);
  FStore.SetCalculated(resultCol, 1, 26);
  FStore.SetCalculated(overCol, 0, 5);
  FStore.SetCalculated(overCol, 1, 6);

  stk := TyNoStack;
  stk.Stacked := True;
  stk.HasBelow := True;
  stk.ResultCol := resultCol;
  stk.OverCol := overCol;

  v := TySeriesVisual($FF3366CC);
  { Markers off: this test is about the LINE. A line shows one on every
    point by default, so counting elements would count those too. }
  v.Line.ShowSymbol := False;
  v.Line.HasArea := True;
  TyBuildSeriesMarks(FBinding, FStore, stk, v, FList);
  poly := FList.Element(0).Shape.Points;
  AssertEquals('the top is the cumulative',
    FCart.DataToPoint([0.0, 15.0]).Y, poly[0].Y, 0.001);
  AssertEquals('and the floor is what it stands on, not the axis',
    FCart.DataToPoint([0.0, 5.0]).Y, poly[High(poly)].Y, 0.001);
  AssertTrue('which is above the baseline',
    poly[High(poly)].Y < FCart.DataToPoint([0.0, 0.0]).Y - 1);
end;

procedure TAdvChartMarksTest.TestConnectNullsJoinsTheRunInsteadOfBreakingIt;
var v: TTySeriesVisual;
begin
  { OFF (the default): a hole ends the run and a second polyline starts after
    it, so the gap stays visible. }
  Given('line', 5, [10, 20, NaN, 40, 50]);
  v := TySeriesVisual($FF3366CC);
  { Markers off: this test is about the LINE. A line shows one on every
    point by default, so counting elements would count those too. }
  v.Line.ShowSymbol := False;
  AssertEquals('a gap makes two runs', 2,
    TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList));

  { ON: the missing point is dropped and the line continues through. }
  FList.Clear;
  v.Line.ConnectNulls := True;
  AssertEquals('connectNulls joins them into one', 1,
    TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList));
  AssertEquals('with the gap''s point simply absent', 4,
    Length(FList.Element(0).Shape.Points));
end;

procedure TAdvChartMarksTest.TestStepTurnsWhereEachModeSaysItDoes;
var
  v: TTySeriesVisual;
  p: TTyPointFArray;
  a, b: TTyPointF;
begin
  { The three modes differ only in WHERE the corner goes between two points.
    Two points make one corner ('start'/'end') or two ('middle'), so the counts
    alone separate the modes -- and the coordinates say which is which. }
  Given('line', 2, [10, 20]);
  a := FCart.DataToPoint([0.0, 10.0]);
  b := FCart.DataToPoint([1.0, 20.0]);

  v := TySeriesVisual($FF3366CC);
  { Markers off: this test is about the LINE. A line shows one on every
    point by default, so counting elements would count those too. }
  v.Line.ShowSymbol := False;
  v.Line.Step := lstStart;
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
  p := FList.Element(0).Shape.Points;
  AssertEquals('start: one corner', 3, Length(p));
  AssertEquals('the value changes first, at the old x', a.X, p[1].X, 0.001);
  AssertEquals('reaching the new value', b.Y, p[1].Y, 0.001);

  FList.Clear;
  v.Line.Step := lstEnd;
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
  p := FList.Element(0).Shape.Points;
  AssertEquals('end: one corner', 3, Length(p));
  AssertEquals('the base moves first, to the new x', b.X, p[1].X, 0.001);
  AssertEquals('still at the old value', a.Y, p[1].Y, 0.001);

  FList.Clear;
  v.Line.Step := lstMiddle;
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
  p := FList.Element(0).Shape.Points;
  AssertEquals('middle: two corners', 4, Length(p));
  AssertEquals('both at the halfway x', (a.X + b.X) / 2, p[1].X, 0.001);
  AssertEquals('and the same again', (a.X + b.X) / 2, p[2].X, 0.001);
  AssertEquals('the first still at the old value', a.Y, p[1].Y, 0.001);
  AssertEquals('the second at the new one', b.Y, p[2].Y, 0.001);
end;

procedure TAdvChartMarksTest.TestTheLineOptionsAreActuallyReadFromTheOption;
var
  opt: TTyChartOption;
  spec: TTyLineSpec;

  function SpecOf(const AText: string): TTyLineSpec;
  begin
    AssertTrue('the option parsed: ' + opt.Error.Message,
      opt.SetOptionText(AText));
    Result := TyLineSpecOf(opt, 0);
  end;

begin
  { THE READER HAD NO TEST AT ALL. Every geometry test above sets TTyLineSpec
    by hand, so three separate mutants of TyLineSpecOf survived the whole
    suite: `step: true` not meaning 'start', an empty areaStyle not turning the
    area on, and the defaults. Setting a record by hand tests the drawing; it
    says nothing about whether the option is understood. }
  opt := TTyChartOption.Create;
  try
    spec := SpecOf('{ series: [{ type: ''line'', data: [1] }] }');
    AssertFalse('no areaStyle, no area', spec.HasArea);
    AssertEquals('no step', Ord(lstNone), Ord(spec.Step));
    AssertFalse('and connectNulls is off', spec.ConnectNulls);

    { PRESENCE IS THE SWITCH: there is no `show`, and an empty object is a real
      instruction. }
    spec := SpecOf('{ series: [{ type: ''line'', areaStyle: {}, data: [1] }] }');
    AssertTrue('an empty areaStyle turns the area on', spec.HasArea);
    AssertEquals('opaque unless told otherwise', 1.0, spec.AreaOpacity, 1e-9);
    AssertEquals('and anchored automatically',
      Ord(laoAuto), Ord(spec.AreaOrigin));

    spec := SpecOf('{ series: [{ type: ''line'', data: [1],'
      + ' areaStyle: { opacity: 0.25, origin: ''end'' } }] }');
    AssertEquals('opacity comes through', 0.25, spec.AreaOpacity, 1e-9);
    AssertEquals('and so does the origin', Ord(laoEnd), Ord(spec.AreaOrigin));

    spec := SpecOf('{ series: [{ type: ''line'', data: [1],'
      + ' areaStyle: { origin: 42 } }] }');
    AssertEquals('a number is its own kind',
      Ord(laoValue), Ord(spec.AreaOrigin));
    AssertEquals('carrying the value', 42.0, spec.AreaOriginValue, 1e-9);

    { `step: true` MEANS 'start'. Upstream says so beside the default, and a
      port that only understood the three strings would silently ignore the
      commonest spelling. }
    spec := SpecOf('{ series: [{ type: ''line'', step: true, data: [1] }] }');
    AssertEquals('true is start', Ord(lstStart), Ord(spec.Step));
    spec := SpecOf('{ series: [{ type: ''line'', step: false, data: [1] }] }');
    AssertEquals('false is no step', Ord(lstNone), Ord(spec.Step));
    spec := SpecOf('{ series: [{ type: ''line'', step: ''middle'', data: [1] }] }');
    AssertEquals('and the strings work', Ord(lstMiddle), Ord(spec.Step));

    spec := SpecOf('{ series: [{ type: ''line'', connectNulls: true,'
      + ' data: [1] }] }');
    AssertTrue('connectNulls comes through', spec.ConnectNulls);

    { showSymbol AND showAllSymbol, READ FROM THE OPTION. Every marker test
      sets these by hand, which says nothing about whether the option was
      understood -- and a mutant deleting this very read survived the whole
      suite until these assertions existed. The same hole, in the same reader,
      for the second time. }
    spec := SpecOf('{ series: [{ type: ''line'', data: [1] }] }');
    AssertTrue('markers are on unless told otherwise', spec.ShowSymbol);
    AssertEquals('and auto unless told otherwise',
      Ord(sasAuto), Ord(spec.ShowAllSymbol));

    spec := SpecOf('{ series: [{ type: ''line'', showSymbol: false,'
      + ' data: [1] }] }');
    AssertFalse('and the option can switch them off', spec.ShowSymbol);

    spec := SpecOf('{ series: [{ type: ''line'', showAllSymbol: true,'
      + ' data: [1] }] }');
    AssertEquals(Ord(sasYes), Ord(spec.ShowAllSymbol));
    spec := SpecOf('{ series: [{ type: ''line'', showAllSymbol: false,'
      + ' data: [1] }] }');
    AssertEquals(Ord(sasNo), Ord(spec.ShowAllSymbol));
  finally
    opt.Free;
  end;
end;

procedure TAdvChartMarksTest.TestTheFillIsPaintedBehindItsLine;
var v: TTySeriesVisual;
begin
  { PAINT ORDER, NOT INSERTION ORDER. The first version of this asserted that
    Element(0) is the polygon -- which is where it was ADDED, not where it is
    DRAWN. The paint list sorts by (Z, Z2, insertion), so a mutant that raised
    the area's Z2 put the shading over the line and the test never noticed.
    PaintOrder is the list's own answer to "what is drawn first". }
  Given('line', 3, [10, 20, 30]);
  v := TySeriesVisual($FF3366CC);
  { Markers off: this test is about the LINE. A line shows one on every
    point by default, so counting elements would count those too. }
  v.Line.ShowSymbol := False;
  v.Line.HasArea := True;
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
  AssertEquals('two elements', 2, FList.Count);
  AssertEquals('the fill is painted first, so it is behind',
    Ord(cskPolygon), Ord(FList.Element(FList.PaintOrder(0)).Shape.Kind));
  AssertEquals('and the line over it',
    Ord(cskPolyline), Ord(FList.Element(FList.PaintOrder(1)).Shape.Kind));
end;

procedure TAdvChartMarksTest.TestASteppedAreaFollowsItsSteppedLine;
var
  v: TTySeriesVisual;
  line, poly: TTyPointFArray;
  k: Integer;
begin
  { THE BELT IS STEPPED THE SAME WAY AS THE LINE IT BELONGS TO. Step only the
    upper edge and the fill stops following its own outline -- the top is a
    staircase and the bottom is a straight run, so the shape leaks out from
    under the line. A mutant that left the lower edge unstepped survived,
    because nothing compared the two edges. }
  Given('line', 3, [10, 20, 30]);
  v := TySeriesVisual($FF3366CC);
  { Markers off: this test is about the LINE. A line shows one on every
    point by default, so counting elements would count those too. }
  v.Line.ShowSymbol := False;
  v.Line.HasArea := True;
  v.Line.Step := lstEnd;
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);

  poly := FList.Element(FList.PaintOrder(0)).Shape.Points;
  line := FList.Element(FList.PaintOrder(1)).Shape.Points;
  AssertEquals('the line is stepped: 3 points make 5', 5, Length(line));
  AssertEquals('and the ring is both edges of it', 10, Length(poly));
  { The upper half of the ring IS the line, point for point. }
  for k := 0 to High(line) do
  begin
    AssertEquals(Format('ring top %d matches the line', [k]),
      line[k].X, poly[k].X, 0.001);
    AssertEquals(Format('ring top %d matches the line', [k]),
      line[k].Y, poly[k].Y, 0.001);
  end;
  { And the lower half has the same base coordinates, walked backwards. }
  for k := 0 to High(line) do
    AssertEquals(Format('ring bottom %d is under the line', [k]),
      line[High(line) - k].X, poly[Length(line) + k].X, 0.001);
end;

procedure TAdvChartMarksTest.TestACoordinateThatWillNotMapBreaksTheRun;
var
  v: TTySeriesVisual;
  sc: TTyIntervalScale;
begin
  { A HOLE IS NOT ONLY NaN. A zero on a log axis maps to -Infinity, and the
    first version dropped such a point silently -- which JOINS the line across
    it, the very thing connectNulls being false exists to prevent. An Infinity
    that reached the paint list would stretch the polyline across the surface.

    Two mutants lived here: one that dropped an unmappable point instead of
    breaking, and one that stopped counting Infinity as illegal at all. }
  Given('line', 5, [10, 20, 0, 40, 50]);
  { A log axis is an interval scale wearing a log MAPPER -- there is no
    TTyLogScale -- which is how the builder makes one. }
  sc := TTyIntervalScale(FBinding.ValueAxis.Scale);
  sc.Mapper := TTyLogScaleMapper.Create(10);
  sc.SetExtent(TyRange(1, 100));

  v := TySeriesVisual($FF3366CC);
  { Markers off: this test is about the LINE. A line shows one on every
    point by default, so counting elements would count those too. }
  v.Line.ShowSymbol := False;
  AssertEquals('the unmappable point breaks the run in two', 2,
    TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList));
  AssertEquals('two points before it', 2,
    Length(FList.Element(0).Shape.Points));
  AssertEquals('and two after', 2, Length(FList.Element(1).Shape.Points));
end;

procedure TAdvChartMarksTest.TestAScatterIsOneSymbolPerDatum;
var
  v: TTySeriesVisual;
  i: Integer;
  sh: TTyChartShape;
begin
  { ONE MARK PER ROW, centred on the datum, and nothing else -- a scatter has
    no line and no baseline. }
  Given('scatter', 4, [10, 20, 30, 40]);
  v := TySeriesVisual($FF3366CC);
  v.Symbol := TySymbolDefault('scatter');
  AssertEquals('one symbol per row', 4,
    TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList));

  for i := 0 to 3 do
  begin
    sh := FList.Element(i).Shape;
    AssertEquals(Format('mark %d is a circle', [i]),
      Ord(cskCircle), Ord(sh.Kind));
    AssertEquals(Format('mark %d sits on its datum', [i]),
      FCart.DataToPoint([Double(i), 10.0 * (i + 1)]).X, sh.CX, 0.001);
    AssertEquals(Format('mark %d sits on its datum', [i]),
      FCart.DataToPoint([Double(i), 10.0 * (i + 1)]).Y, sh.CY, 0.001);
    AssertEquals(Format('mark %d answers for its own row', [i]),
      i, FList.Element(i).Datum.DataIndex);
  end;
  AssertEquals('and the default size is upstream''s 10', 5.0,
    FList.Element(0).Shape.R1, 0.001);

  { A GAP DRAWS NOTHING rather than a symbol at an invented place. }
  FList.Clear;
  FreeAndNil(FStore);
  FreeAndNil(FCart);
  Given('scatter', 3, [10, NaN, 30]);
  v.Symbol := TySymbolDefault('scatter');
  AssertEquals('two rows have values, so two symbols', 2,
    TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList));

  { `symbol: 'none'` draws nothing at all -- a real instruction, not a
    failure. }
  FList.Clear;
  v.Symbol.Kind := tsyNone;
  AssertEquals('none means none', 0,
    TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList));
end;

procedure TAdvChartMarksTest.TestAnEmptySymbolIsStrokedAndFilledWithTheThemesOwnGround;
var v: TTySeriesVisual;
begin
  { AN `empty` SYMBOL IS A RING, and the hole is the THEME'S ground, not white.
    Upstream fills it from a token for the same reason: a white dot on a dark
    skin is a bug you only see on the dark skin. }
  Given('scatter', 2, [10, 20]);
  v := TySeriesVisual($FF3366CC);
  v.Symbol := TySymbolDefault('scatter');
  v.Symbol.Empty := True;
  v.EmptyFill := $FF102030;
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);

  AssertEquals('the series colour becomes the pen',
    Int64($FF3366CC), Int64(FList.Element(0).Style.StrokeColor));
  AssertTrue('and it is actually stroked',
    FList.Element(0).Style.StrokeWidthLogical > 0);
  AssertEquals('the hole is the ground it was given',
    Int64($FF102030), Int64(FList.Element(0).Style.FillColor));

  { A SOLID SYMBOL IS THE OTHER WAY ROUND: filled in the series colour, no
    pen. }
  FList.Clear;
  v.Symbol.Empty := False;
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
  AssertEquals('filled in the series colour',
    Int64($FF3366CC), Int64(FList.Element(0).Style.FillColor));

  { THE `line` SYMBOL IS STROKED TOO, and has no fill at all -- it is a dash,
    so a fill would have nothing to fill. }
  FList.Clear;
  v.Symbol.Kind := tsyLine;
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
  AssertEquals('the dash is drawn with the pen',
    Int64($FF3366CC), Int64(FList.Element(0).Style.StrokeColor));
  AssertFalse('and has nothing to fill', FList.Element(0).Style.HasFill);
end;

procedure TAdvChartMarksTest.TestABubbleTakesItsSizeFromTheData;
var
  v: TTySeriesVisual;
  extra: Integer;
begin
  { A BUBBLE CHART WITHOUT A CALLBACK. Upstream sizes these with a function
    over the datum, and a function cannot survive the trip to JSON -- so what
    a static option can carry is a third number on the point, and that is what
    is read. Without this every bubble chart in the gallery draws at one size
    and looks like a plain scatter. }
  Given('scatter', 3, [10, 20, 30]);
  extra := FStore.AddDimension('size', ddtFloat);
  FStore.SetCalculated(extra, 0, 8);
  FStore.SetCalculated(extra, 1, 24);
  FStore.SetCalculated(extra, 2, 40);

  v := TySeriesVisual($FF3366CC);
  v.Symbol := TySymbolDefault('scatter');
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);

  AssertEquals('the first bubble is 8 across', 4.0,
    FList.Element(0).Shape.R1, 0.001);
  AssertEquals('the second 24', 12.0, FList.Element(1).Shape.R1, 0.001);
  AssertEquals('the third 40', 20.0, FList.Element(2).Shape.R1, 0.001);
  AssertTrue('so they are not all the default 10',
    Abs(FList.Element(0).Shape.R1 - FList.Element(2).Shape.R1) > 1);
end;

procedure TAdvChartMarksTest.TestALineWearsAMarkerOnEveryPoint;
var
  v: TTySeriesVisual;
  i, syms: Integer;
begin
  { UPSTREAM'S DEFAULT IS ON. An ECharts line has a ring on every point, and
    this port drew none until now -- a gap that only shows beside the original,
    which is exactly the kind that survives a long time. }
  Given('line', 4, [10, 20, 30, 40]);
  v := TySeriesVisual($FF3366CC);
  v.EmptyFill := $FF102030;
  AssertTrue('a bare visual shows them, because upstream does',
    v.Line.ShowSymbol);
  v.Symbol := TySymbolDefault('line');
  AssertEquals('and a line''s marker is 6 across', 6.0, v.Symbol.WidthPx, 1e-9);
  AssertTrue('and it is a RING, not a dot -- symbol is emptyCircle',
    v.Symbol.Empty);

  AssertEquals('one polyline plus one marker per point', 5,
    TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList));

  { THE MARKERS CARRY THE DATUM, which the polyline cannot: one polyline is a
    whole run, so without them a pointer could never name a row on a line. }
  syms := 0;
  for i := 0 to FList.Count - 1 do
    if FList.Element(i).Shape.Kind = cskCircle then
    begin
      AssertEquals('marker answers for its own row', syms,
        FList.Element(i).Datum.DataIndex);
      Inc(syms);
    end;
  AssertEquals('four of them', 4, syms);

  { PAINTED OVER THE LINE, not under it. }
  AssertEquals('the line is drawn first', Ord(cskPolyline),
    Ord(FList.Element(FList.PaintOrder(0)).Shape.Kind));

  { AND IT IS A RING, not a dot: the series colour is the PEN and the hole is
    the ground it was handed. Nothing asserted this until a mutant that filled
    the marker instead of stroking it survived the whole suite -- which turns
    every ECharts-default line marker into a solid blob. }
  for i := 0 to FList.Count - 1 do
    if FList.Element(i).Shape.Kind = cskCircle then
    begin
      AssertEquals('the marker is stroked in the series colour',
        Int64($FF3366CC), Int64(FList.Element(i).Style.StrokeColor));
      AssertTrue('with a real pen',
        FList.Element(i).Style.StrokeWidthLogical > 0);
      AssertEquals('and its hole is the ground, not the series colour',
        Int64($FF102030), Int64(FList.Element(i).Style.FillColor));
      Break;
    end;

  { AND showSymbol: false MEANS NONE. }
  FList.Clear;
  v.Line.ShowSymbol := False;
  AssertEquals('off means the polyline alone', 1,
    TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList));
end;

procedure TAdvChartMarksTest.TestCrowdedMarkersThinToTheAxisOwnLabelInterval;
var
  v: TTySeriesVisual;
  i, syms: Integer;
begin
  { WHEN THEY WOULD CROWD, upstream stops showing them all and "follows the
    label interval strategy on the category axis". So the thinning is not a
    number invented here -- it is the SAME step the axis used for its labels,
    computed once by the layout pass and handed over.

    Twenty categories across 400px is 20px each; a marker 40 across needs
    40 * 1.5 = 60, so they crowd. }
  Given('line', 20, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
                     11, 12, 13, 14, 15, 16, 17, 18, 19, 20]);
  v := TySeriesVisual($FF3366CC);
  v.Symbol := TySymbolDefault('line');
  v.Symbol.WidthPx := 40;
  v.Symbol.HeightPx := 40;
  v.Line.LabelStep := 5;

  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
  syms := 0;
  for i := 0 to FList.Count - 1 do
    if FList.Element(i).Shape.Kind = cskCircle then Inc(syms);
  AssertEquals('every fifth point gets a marker', 4, syms);

  { showAllSymbol: true OVERRULES the crowding check -- the author asked for
    all of them and gets all of them. }
  FList.Clear;
  v.Line.ShowAllSymbol := sasYes;
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
  syms := 0;
  for i := 0 to FList.Count - 1 do
    if FList.Element(i).Shape.Kind = cskCircle then Inc(syms);
  AssertEquals('all twenty', 20, syms);

  { AND A SMALL MARKER NEVER CROWDS, so auto leaves it alone. }
  FList.Clear;
  v.Line.ShowAllSymbol := sasAuto;
  v.Symbol.WidthPx := 6;
  v.Symbol.HeightPx := 6;
  TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
  syms := 0;
  for i := 0 to FList.Count - 1 do
    if FList.Element(i).Shape.Kind = cskCircle then Inc(syms);
  AssertEquals('six across fits in twenty, so all of them', 20, syms);
end;

initialization
  RegisterTest(TAdvChartMarksTest);
end.
