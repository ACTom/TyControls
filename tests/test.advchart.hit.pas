unit test.advchart.hit;
{$mode objfpc}{$H+}
{ What the pointer is over.

  THE CHART'S FIRST INTERACTIVE QUESTION. Everything under it -- the shape
  record, the paint list, its ordering and its hit test -- was built during
  Tier 0 with nothing calling it, and the paint list was a LOCAL in PaintSeries:
  created, drawn from, and freed inside one call. So by the time a pointer could
  have asked what it was over, the answer had already been freed, and the hit
  test's only callers were tests of itself.

  THESE TESTS ASK IN THE CONTROL'S OWN COORDINATES, never the list's. That is
  the join the change is about, and a test that reached into the list directly
  would pass over a chart that never fills one.

  NO PIXELS ARE READ HERE. Where a mark IS, is a question the build already
  answers -- the axes turn a datum into a coordinate, and asking them is how the
  test knows where to point without pinning a layout that theme padding is
  entitled to move. Pixel counting belongs to the tests that ask whether the
  ink is right; this file asks whether the chart can name it. }
interface
uses Classes, SysUtils, Controls, Graphics, Forms, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Coord,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Builder,
     tyControls.AdvanceChart;
type
  { The chart's own probe. Not test.advancechart's: this one also needs the
    pointer seam, which is protected because a host has no business calling
    it and a test has every business proving it was called. }
  THitProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { What MouseEnter, MouseLeave, a press, a release and a focus change all
      reach. }
    procedure PointerMoved;
  end;

  TAdvChartHitTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: THitProbe;
    FBmp: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw(const AOption: string; AW: Integer = 400;
      AH: Integer = 300; APPI: Integer = 96);
    { The first grid's first x and y axis. Fails the test rather than
      returning nil, so a broken fixture reads as a broken fixture. }
    function AxisX: TTyAxis;
    function AxisY: TTyAxis;
    function Plot: TTyRectF;
    { The device point a datum was drawn at, asked of the axes. }
    function PointOf(ACat: Integer; AValue: Double): TPoint;
  published
    procedure TestABarNamesItsOwnRow;
    procedure TestEmptyPlotNamesNothing;
    procedure TestOutsideThePlotNamesNothing;
    procedure TestBeforeAnyRenderNothingIsUnderThePointer;
    procedure TestASmallMarkerHasAForgivingTarget;
    procedure TestAMarkerIsNotHitFromAcrossThePlot;
    procedure TestALineIsHitBetweenItsMarkers;
    procedure TestALineHitNamesTheNearestRow;
    procedure TestAPieSliceNamesTheRowInBothSpaces;
    procedure TestHoveringDoesNotBlindTheChart;
    procedure TestAModelChangeDoes;
    procedure TestAnOptionWithNoSeriesLeavesNoStaleAnswers;
  end;

implementation

const
  cBars =
    '{"xAxis":{"type":"category","data":["A","B","C","D","E"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","data":[20,40,60,80,50]}]}';
  { showSymbol OFF, which is the case the run-element resolution exists for:
    with no markers the only element the series puts in the list is one
    polyline for the whole run, carrying no row at all. }
  cLineNoSymbols =
    '{"xAxis":{"type":"category","data":["A","B","C","D","E"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"line","showSymbol":false,"lineStyle":{"width":2},' +
    '"data":[20,40,60,80,50]}]}';
  { A six-pixel marker: three pixels of radius standing for a whole row. }
  cTinyScatter =
    '{"xAxis":{"type":"value","min":0,"max":100},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"scatter","symbolSize":6,' +
    '"data":[[20,20],[50,50],[80,80]]}]}';
  { B is switched off, so the store's VIEW loses a row and every row after it
    shifts. Raw 2 is view 1. }
  cFilteredPie =
    '{"legend":{"selected":{"B":false}},' +
    '"series":[{"type":"pie","radius":"70%","data":[' +
    '{"name":"A","value":10},{"name":"B","value":20},' +
    '{"name":"C","value":30},{"name":"D","value":40}]}]}';

procedure THitProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure THitProbe.PointerMoved;
begin
  PointerStateChanged;
end;

procedure TAdvChartHitTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := THitProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := nil;
end;

procedure TAdvChartHitTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartHitTest.Draw(const AOption: string; AW: Integer;
  AH: Integer; APPI: Integer);
begin
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(AW, AH, BGRAWhite);
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, AW, AH);
  { ORIGIN (0,0). The paint list is filled in local coordinates whatever rect
    it is rendered onto, so a test that rendered at an offset would be asking
    about points the control has never heard of. }
  FChart.Render(FBmp.Canvas, Rect(0, 0, AW, AH), APPI);
end;

function TAdvChartHitTest.AxisX: TTyAxis;
begin
  AssertTrue('the chart built', FChart.Build <> nil);
  AssertTrue('there is a grid', FChart.Build.GridCount > 0);
  AssertTrue('the grid has an x axis', FChart.Build.Grid(0).XAxisCount > 0);
  Result := FChart.Build.Grid(0).XAxis(0);
end;

function TAdvChartHitTest.AxisY: TTyAxis;
begin
  AssertTrue('the chart built', FChart.Build <> nil);
  AssertTrue('there is a grid', FChart.Build.GridCount > 0);
  AssertTrue('the grid has a y axis', FChart.Build.Grid(0).YAxisCount > 0);
  Result := FChart.Build.Grid(0).YAxis(0);
end;

function TAdvChartHitTest.Plot: TTyRectF;
begin
  AssertTrue('the chart built', FChart.Build <> nil);
  AssertTrue('there is a grid', FChart.Build.GridCount > 0);
  Result := FChart.Build.Grid(0).PlotRect;
end;

function TAdvChartHitTest.PointOf(ACat: Integer; AValue: Double): TPoint;
begin
  Result.X := Round(AxisX.DataToCoord(ACat));
  Result.Y := Round(AxisY.DataToCoord(AValue));
end;

procedure TAdvChartHitTest.TestABarNamesItsOwnRow;
var d: TTyChartDatumRef; p: TPoint;
begin
  Draw(cBars);
  { INSIDE the third bar, a few pixels below its top edge -- not ON the edge,
    where a rounded corner or a sub-pixel snap could legitimately put the
    boundary either side. }
  p := PointOf(2, 60);
  d := FChart.HitTestAt(p.X, p.Y + 6);
  AssertTrue('a point inside a bar names a datum', TyChartDatumValid(d));
  AssertEquals('series', 0, d.SeriesIndex);
  AssertEquals('row', 2, d.DataIndex);
  AssertEquals('and the same row unfiltered', 2, d.RawDataIndex);
end;

procedure TAdvChartHitTest.TestEmptyPlotNamesNothing;
var d: TTyChartDatumRef; p: TPoint;
begin
  Draw(cBars);
  { Well above the tallest bar, still inside the plot. The split lines and the
    split areas drawn there are decoration and say so. }
  p := PointOf(0, 95);
  d := FChart.HitTestAt(p.X, p.Y);
  AssertFalse('empty plot is empty', TyChartDatumValid(d));
end;

procedure TAdvChartHitTest.TestOutsideThePlotNamesNothing;
var d: TTyChartDatumRef; r: TTyRectF;
begin
  Draw(cBars);
  r := Plot;
  { In the label band below the axis. }
  d := FChart.HitTestAt(Round((r.Left + r.Right) / 2), Round(r.Bottom) + 8);
  AssertFalse('the axis furniture is not a datum', TyChartDatumValid(d));
end;

procedure TAdvChartHitTest.TestBeforeAnyRenderNothingIsUnderThePointer;
var d: TTyChartDatumRef;
begin
  FChart.Option := cBars;
  FChart.SetBounds(0, 0, 400, 300);
  { NO RENDER. The list does not exist, and the honest answer to "what is at
    (200, 150)" is that the chart has not drawn anything there yet. }
  d := FChart.HitTestAt(200, 150);
  AssertFalse('nothing has been drawn', TyChartDatumValid(d));
end;

procedure TAdvChartHitTest.TestASmallMarkerHasAForgivingTarget;
var d: TTyChartDatumRef; p: TPoint;
begin
  Draw(cTinyScatter);
  p := PointOf(50, 50);
  { FOUR PIXELS OFF CENTRE, on a marker whose own radius is three. Without a
    hit slop this is a miss, and every scatter chart in the library is a chart
    whose data can only be pointed at exactly. }
  d := FChart.HitTestAt(p.X + 4, p.Y);
  AssertTrue('a 6px marker is hittable just outside its own edge',
             TyChartDatumValid(d));
  AssertEquals('and it is the middle one', 1, d.DataIndex);
end;

procedure TAdvChartHitTest.TestAMarkerIsNotHitFromAcrossThePlot;
var d: TTyChartDatumRef; p: TPoint;
begin
  Draw(cTinyScatter);
  p := PointOf(50, 50);
  { THE OTHER HALF OF THE PREVIOUS TEST, and the reason it means anything: a
    slop generous enough to pass that one and swallow this one too would be a
    chart where every point is every point. }
  d := FChart.HitTestAt(p.X + 30, p.Y + 30);
  AssertFalse('thirty pixels away is not on the marker',
              TyChartDatumValid(d));
end;

procedure TAdvChartHitTest.TestALineIsHitBetweenItsMarkers;
var d: TTyChartDatumRef; a, b: TPoint;
begin
  Draw(cLineNoSymbols);
  a := PointOf(1, 40);
  b := PointOf(2, 60);
  { HALFWAY ALONG THE SEGMENT, where there is no marker and -- with
    showSymbol off -- never could be. The list holds one polyline for the whole
    series carrying `(series, -1)`, which is not a datum. }
  d := FChart.HitTestAt(Round((a.X + b.X) / 2), Round((a.Y + b.Y) / 2));
  AssertTrue('the stroke of a line is a target', TyChartDatumValid(d));
  AssertEquals('series', 0, d.SeriesIndex);
end;

procedure TAdvChartHitTest.TestALineHitNamesTheNearestRow;
var d: TTyChartDatumRef; p: TPoint;
begin
  Draw(cLineNoSymbols);
  { A QUARTER OF THE WAY from category 3 towards category 2, on the line. The
    nearest row is unambiguous, so the answer is checkable rather than merely
    plausible -- the halfway point of the previous test deliberately is not. }
  p.X := Round(AxisX.DataToCoord(3) * 0.75 + AxisX.DataToCoord(2) * 0.25);
  p.Y := Round(AxisY.DataToCoord(80) * 0.75 + AxisY.DataToCoord(60) * 0.25);
  d := FChart.HitTestAt(p.X, p.Y);
  AssertTrue('still on the stroke', TyChartDatumValid(d));
  AssertEquals('the nearer of the two rows', 3, d.DataIndex);
end;

procedure TAdvChartHitTest.TestAPieSliceNamesTheRowInBothSpaces;
var
  d: TTyChartDatumRef;
  i, cx, cy, found: Integer;
begin
  Draw(cFilteredPie);
  { WALK THE DISC rather than computing an angle: the slice's sweep depends on
    startAngle and on the three surviving values, and re-deriving that here
    would be a second implementation of the layout. What matters is only that
    SOME slice reports C, and that when it does the two indices differ.

    C is raw row 2 and -- with B switched off and taken out of the store -- it
    is VIEW row 1. Before the datum carried both, whichever number a pie put in
    DataIndex was wrong for one of the two readers. }
  cx := FChart.Width div 2;
  cy := FChart.Height div 2;
  found := 0;
  for i := 0 to 359 do
  begin
    d := FChart.HitTestAt(cx + Round(Cos(i * Pi / 180) * 60),
                          cy + Round(Sin(i * Pi / 180) * 60));
    if not TyChartDatumValid(d) then Continue;
    if d.RawDataIndex <> 2 then Continue;
    Inc(found);
    AssertEquals('C is view row 1 once B has left the store', 1, d.DataIndex);
    AssertEquals('and raw row 2 however the store is filtered', 2,
                 d.RawDataIndex);
    Break;
  end;
  AssertEquals('a slice for C was found on the disc', 1, found);
end;

procedure TAdvChartHitTest.TestHoveringDoesNotBlindTheChart;
var before, after_: TTyChartDatumRef; p: TPoint;
begin
  Draw(cBars);
  p := PointOf(2, 60);
  before := FChart.HitTestAt(p.X, p.Y + 6);
  AssertTrue('the fixture is hittable to begin with',
             TyChartDatumValid(before));
  { A POINTER CROSSING THE BORDER. The base class answers that with a full
    Invalidate, which on this control rebuilds the stores, re-measures every
    label and throws away the static bitmap -- so the first thing every hover
    session used to do was destroy the picture it was hovering over. }
  FChart.PointerMoved;
  after_ := FChart.HitTestAt(p.X, p.Y + 6);
  AssertTrue('and still hittable after the pointer arrives',
             TyChartDatumValid(after_));
  AssertEquals('same row', before.DataIndex, after_.DataIndex);
end;

procedure TAdvChartHitTest.TestAModelChangeDoes;
var d: TTyChartDatumRef; p: TPoint;
begin
  Draw(cBars);
  p := PointOf(2, 60);
  AssertTrue('hittable first', TyChartDatumValid(FChart.HitTestAt(p.X, p.Y + 6)));
  { THE OTHER HALF, and what keeps the previous test from passing against a
    control that simply never drops anything. A theme change arrives as a bare
    Invalidate and the picture it describes is gone; answering out of the old
    list would be answering about a chart nobody can see. }
  FChart.Invalidate;
  d := FChart.HitTestAt(p.X, p.Y + 6);
  AssertFalse('a dropped picture answers nothing', TyChartDatumValid(d));
end;

procedure TAdvChartHitTest.TestAnOptionWithNoSeriesLeavesNoStaleAnswers;
var d: TTyChartDatumRef; p: TPoint;
begin
  Draw(cBars);
  p := PointOf(2, 60);
  AssertTrue('hittable first', TyChartDatumValid(FChart.HitTestAt(p.X, p.Y + 6)));
  { A CHART THAT RESOLVED NO SERIES still renders -- frame, axes, labels -- so
    the build is fresh and the static layer is real. The series pass takes its
    early exit, and a list left over from the previous option would go on
    naming bars that are no longer drawn. }
  Draw('{"xAxis":{"type":"category","data":["A","B","C","D","E"]},' +
       '"yAxis":{"type":"value","min":0,"max":100},"series":[]}');
  d := FChart.HitTestAt(p.X, p.Y + 6);
  AssertFalse('an empty chart is empty', TyChartDatumValid(d));
end;

initialization
  RegisterTest(TAdvChartHitTest);
end.
