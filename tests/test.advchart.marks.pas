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
     tyControls.AdvChart.BarLayout;
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
    procedure TestTheSolvedColumnDecidesWhereTheBarGoes;
    procedure TestAValueTooSmallToSeeStillGetsBarMinHeight;
    procedure TestARoundedBarIsARoundedShapeNotAFlagNobodyReads;
    procedure TestAColumnOfNoWidthDrawsNothingRatherThanTheWholeBand;
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
  TyBuildSeriesMarks(FBinding, FStore, v, FList);

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
  TyBuildSeriesMarks(FBinding, FStore, v, FList);

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
  TyBuildSeriesMarks(FBinding, FStore, v, FList);

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
  v.Bar.RadiusPx := 5;
  TyBuildSeriesMarks(FBinding, FStore, v, FList);
  AssertEquals('a radius makes a round rect',
    Ord(cskRoundRect), Ord(FList.Element(0).Shape.Kind));
  AssertEquals('carrying the radius', 5.0, FList.Element(0).Shape.RadiusPx, 1e-9);

  { AND NO RADIUS STAYS A PLAIN RECT, so every bar is not quietly rounded. }
  FList.Clear;
  v.Bar.RadiusPx := 0;
  TyBuildSeriesMarks(FBinding, FStore, v, FList);
  AssertEquals('no radius stays square',
    Ord(cskRect), Ord(FList.Element(0).Shape.Kind));
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
    TyBuildSeriesMarks(FBinding, FStore, v, FList));
  AssertEquals('and adds nothing to hit-test against', 0, FList.Count);
end;

initialization
  RegisterTest(TAdvChartMarksTest);
end.
