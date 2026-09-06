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
     tyControls.AdvChart.Series, tyControls.AdvChart.Marks;
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
  published
    procedure TestABarIsOneRectPerRowFromDataToLayout;
    procedure TestAGapDrawsNoBarRatherThanAZeroOne;
    procedure TestBarsLeaveTheCategoryGapUpstreamLeaves;
    procedure TestALineIsOnePolylineAndAGapBreaksIt;
    procedure TestEveryMarkAnswersForItsOwnRow;
    procedure TestAnUnknownSeriesTypeDrawsNothing;
    procedure TestThePublishedAnswerMatchesWhatIsActuallyDrawn;
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
  n := TyBuildSeriesMarks(FBinding, FStore, TySeriesVisual($FF3366CC), FList);
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
  n := TyBuildSeriesMarks(FBinding, FStore, TySeriesVisual($FF3366CC), FList);
  AssertEquals('three rows have values, so three bars', 3, n);
end;

procedure TAdvChartMarksTest.TestBarsLeaveTheCategoryGapUpstreamLeaves;
var
  b, cell: TTyRectF;
  v: TTySeriesVisual;
begin
  { UPSTREAM'S OWN DEFAULT, not an invented one: ECharts' barCategoryGap is
    '20%', so a bar takes 0.8 of its band. Bars that fill the band touch each
    other and read as a single block.

    The full width solver -- barWidth / barMaxWidth / barGap / barCategoryGap
    and the offsetting that lets several series share a band -- is its own
    Tier 1 row. This is the single-series default it will replace. }
  Given('bar', 2, [50, 50]);
  v := TySeriesVisual($FF3366CC);
  AssertEquals('the default is upstream''s', 0.8, v.BarBandFraction, 1e-9);
  TyBuildSeriesMarks(FBinding, FStore, v, FList);

  b := TyShapeBounds(FList.Element(0).Shape);
  cell := FCart.DataToLayout([0.0, 50.0]).Rect;
  AssertEquals('the bar is four fifths of its band',
    (cell.Right - cell.Left) * 0.8, b.Right - b.Left, 0.001);
  AssertTrue('and it does not reach the band edge', b.Left > cell.Left);

  { A FRACTION OF 1 FILLS THE BAND -- so the narrowing is the fraction doing
    something, not the geometry happening to differ. }
  FList.Clear;
  v.BarBandFraction := 1;
  TyBuildSeriesMarks(FBinding, FStore, v, FList);
  b := TyShapeBounds(FList.Element(0).Shape);
  AssertEquals('a fraction of one fills the band',
    cell.Right - cell.Left, b.Right - b.Left, 0.001);
end;

procedure TAdvChartMarksTest.TestALineIsOnePolylineAndAGapBreaksIt;
var n: Integer;
begin
  { ONE POLYLINE for a run of points -- not one element per segment, which
    would make the ordering and the hit test answer per segment. }
  Given('line', 4, [10, 20, 30, 40]);
  n := TyBuildSeriesMarks(FBinding, FStore, TySeriesVisual($FF3366CC), FList);
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
  n := TyBuildSeriesMarks(FBinding, FStore, TySeriesVisual($FF3366CC), FList);
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
  TyBuildSeriesMarks(FBinding, FStore, TySeriesVisual($FF3366CC), FList);
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
  { Twenty-one of the twenty-three types have no renderer yet, and drawing an
    approximation would be worse than drawing nothing -- the control's
    diagnostics are what tell the reader why the plot is empty. }
  Given('scatter', 3, [10, 20, 30]);
  AssertEquals('scatter has no renderer yet', 0,
    TyBuildSeriesMarks(FBinding, FStore, TySeriesVisual($FF3366CC), FList));
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
    AssertEquals(cTypes[i] + ': the published answer and the drawing agree',
      TySeriesTypeHasRenderer(cTypes[i]),
      TyBuildSeriesMarks(FBinding, FStore,
        TySeriesVisual($FF3366CC), FList) > 0);
  end;

  { AND IT IS NOT SIMPLY TRUE FOR EVERYTHING -- the loop above would pass if
    both sides answered yes to every type. }
  AssertTrue('bar draws', TySeriesTypeHasRenderer('bar'));
  AssertFalse('scatter does not, yet', TySeriesTypeHasRenderer('scatter'));
  { CASE-SENSITIVE, matching the type registry -- 'Bar' does not resolve as a
    series at all, so answering yes for it would promise a chart that cannot
    draw. }
  AssertFalse('and Bar is not bar', TySeriesTypeHasRenderer('Bar'));
end;

initialization
  RegisterTest(TAdvChartMarksTest);
end.
