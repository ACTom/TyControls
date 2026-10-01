unit test.advchart.focusblur;
{$mode objfpc}{$H+}
{ FOCUS AND BLUR, HELD TO UPSTREAM [Batch 90].

  The same fixture as the selection batch (tools/advchart-oracle/
  select-legend.js, the real ECharts 6.1 build driven through pointer moves,
  clicks and dispatchAction), its highlight / focus cases replayed through
  the control's own MouseMove and DispatchAction with test.advchart.select's
  harness: the events, every item's flags (hoverState, the dispatcher's and
  a line path's __highByOuter), its state list, what is drawn (fill, stroke,
  opacity, z2 against rest, geometry), its label (list, visibility, ink,
  opacity, z2) and a line's polyline (list, stroke, width, opacity).

  The cases: highlight / downplay with highlightKey bits, the series and by
  name; highlight that first leaves every blur and then blurs by focus,
  notBlur; a line's one-point highlight on the symbol path that the hover
  clears; focus series over a grid, two grids, a pie with no coordinate
  system and blurScope global; focus self with blurScope series and labels;
  a pie's focus self with labels and label lines; emphasis.label and a
  declared blur opacity; two lines whose polylines follow their symbols.

  Then hand tests for what the fixture has no case for. }
interface
uses Classes, SysUtils, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Shape,
     tyControls.AdvChart.Style, tyControls.AdvChart.Color,
     tyControls.AdvChart.States,
     tyControls.AdvanceChart,
     test.advchart.select;
type
  TFbElements = array of TTyChartElement;

  TAdvChartFocusBlurTest = class(TAdvChartSelectHarness)
  private
    function St(ASeries, ARow: Integer): TTyStItem;
    function StText(ASeries, ARow: Integer): string;
    procedure Frame;
    procedure HoverItem(ASeries, ARow: Integer);
    { every element of an item that is no label (marks, glyphs, wicks) }
    function Marks(ASeries, ARow: Integer): TFbElements;
    function RunOf(ASeries: Integer; out AEl: TTyChartElement): Boolean;
  published
    procedure TestFocusAndBlurAsUpstream;
    { the types and rules the fixture has no case for }
    procedure TestPictorialGlyphsTakeTheStatesTogether;
    procedure TestCandleWicksFollowTheirBody;
    procedure TestACalendarIsACoordinateSystem;
    procedure TestThePolylineAndTheAreaDispatchApart;
    procedure TestTheHighlightBlursByTheItemsOwnFocus;
    procedure TestLeavingTheCanvasLeavesTheBlur;
    procedure TestADeclaredLabelBlurOpacityIsKept;
    procedure TestALineHighlightListGoesToTheGroup;
    { found by surviving mutants }
    procedure TestASymbollessLineBlursItsPolyline;
    procedure TestTheNewTypesTakeTheSelectBorder;
  end;

implementation

const
  { THE FOCUS / BLUR BATCH'S CASES. The legend cases are B3's. }
  cB2Cases: array[0..17] of string = ('highlight-bar', 'highlight-focus',
    'highlight-pie', 'highlight-line', 'focus-series-coord',
    'focus-series-global', 'focus-self-series-scope', 'focus-two-grids',
    'focus-pie-self', 'emphasis-label', 'line-focus',
    { added with this batch: more types, the focus words and the held
      element under focus 'self' }
    'focus-funnel-self', 'focus-heatmap-scatter', 'focus-candlestick',
    'focus-truthy-other', 'focus-self-held', 'focus-sunburst',
    'focus-sunburst-ancestor');

function TAdvChartFocusBlurTest.St(ASeries, ARow: Integer): TTyStItem;
begin
  AssertTrue(Format('a state record for s%d i%d', [ASeries, ARow]),
    FChart.ItemStates(ASeries, ARow, Result));
end;

function TAdvChartFocusBlurTest.StText(ASeries, ARow: Integer): string;
begin
  Result := TyStNamesText(St(ASeries, ARow).Host.States);
end;

procedure TAdvChartFocusBlurTest.Frame;
begin
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
end;

{ the pointer onto an item's mark, near its centre }
procedure TAdvChartFocusBlurTest.HoverItem(ASeries, ARow: Integer);
var el: TTyChartElement; x, y: Integer;
begin
  AssertTrue(Format('a mark for s%d i%d', [ASeries, ARow]), HostOf(ASeries, ARow, el));
  x := Round((el.Shape.Bounds.Left + el.Shape.Bounds.Right) / 2);
  y := Round((el.Shape.Bounds.Top + el.Shape.Bounds.Bottom) / 2);
  FChart.Move(x, y);
end;

function TAdvChartFocusBlurTest.Marks(ASeries, ARow: Integer): TFbElements;
var k: Integer; el: TTyChartElement; l: TTyPaintList;
begin
  Result := nil;
  l := FChart.List;
  for k := 0 to l.Count - 1 do
  begin
    el := l.Element(k);
    if (el.Datum.Kind <> ctkSeries) or (el.Datum.SeriesIndex <> ASeries)
      or (el.Datum.DataIndex <> ARow) or el.Datum.IsEdge then Continue;
    if (el.Caption.FontSizeLogical > 0) or el.IsGuide then Continue;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := el;
  end;
end;

function TAdvChartFocusBlurTest.RunOf(ASeries: Integer; out AEl: TTyChartElement): Boolean;
var k: Integer; l: TTyPaintList;
begin
  Result := False;
  l := FChart.List;
  for k := 0 to l.Count - 1 do
  begin
    AEl := l.Element(k);
    if (AEl.Datum.Kind = ctkSeries) and (AEl.Datum.SeriesIndex = ASeries)
      and (AEl.Datum.DataIndex < 0) and (AEl.Shape.Kind = cskPolyline) then Exit(True);
  end;
end;

{ a shape's width: over its points, else its bounds }
function Wide(const AShape: TTyChartShape): Double;
var i: Integer; lo, hi: Double;
begin
  if Length(AShape.Points) = 0 then
    Exit(AShape.Bounds.Right - AShape.Bounds.Left);
  lo := AShape.Points[0].X;
  hi := lo;
  for i := 1 to High(AShape.Points) do
  begin
    if AShape.Points[i].X < lo then lo := AShape.Points[i].X;
    if AShape.Points[i].X > hi then hi := AShape.Points[i].X;
  end;
  Result := hi - lo;
end;

type
  { MouseLeave is protected }
  TFbCrack = class(TTyAdvanceChart);

procedure TAdvChartFocusBlurTest.TestFocusAndBlurAsUpstream;
begin
  RunCases(cB2Cases, 50);
  AssertTrue(Format('%d mismatches over %d steps:%s', [FBad, FCompared, FReport]), FBad = 0);
  AssertEquals('every focus / blur case ran', Length(cB2Cases), FCases);
  AssertTrue(Format('only %d steps compared', [FCompared]), FCompared >= 50);
end;

{ A PICTORIAL BAR'S GLYPHS are paths of one dispatcher (PictorialBarView.ts:
  903-929): every glyph of the hovered bar lifts its fill, climbs ten and,
  with emphasis.scale, grows a tenth; its focus 'series' blurs the other
  series on the grid, a tenth of their opacity. The inkless target rect
  stays inkless. }
procedure TAdvChartFocusBlurTest.TestPictorialGlyphsTakeTheStatesTogether;
var
  before, after: TFbElements;
  k, glyphs: Integer;
  b: TTyChartElement;
begin
  Plain('{"animation":false,"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{"type":"value","max":40},"series":[{"type":"pictorialBar","name":"P",'
    + '"symbol":"rect","symbolRepeat":true,"symbolSize":[20,8],"symbolMargin":2,'
    + '"emphasis":{"focus":"series","scale":true},"data":[20,30]},'
    + '{"type":"bar","name":"B","data":[10,15]}]}');
  before := Marks(0, 1);
  HoverItem(0, 1);
  Frame;
  AssertEquals('hovered', 'emphasis', StText(0, 1));
  after := Marks(0, 1);
  AssertEquals(Length(before), Length(after));
  glyphs := 0;
  for k := 0 to High(after) do
  begin
    if not after[k].Silent then
    begin
      AssertFalse('the target rect stays inkless', after[k].Style.HasFill);
      Continue;
    end;
    Inc(glyphs);
    AssertEquals(Format('glyph %d lifted', [k]),
      Integer(TyChartLiftColor(before[k].Style.FillColor)), Integer(after[k].Style.FillColor));
    AssertEquals(Format('glyph %d climbed', [k]), before[k].Z2 + 10, after[k].Z2);
    AssertTrue(Format('glyph %d grew a tenth: %g against %g', [k, Wide(after[k].Shape),
      Wide(before[k].Shape)]), Abs(Wide(after[k].Shape) - 1.1 * Wide(before[k].Shape)) < 1e-9);
  end;
  AssertTrue('several glyphs', glyphs > 2);
  AssertEquals('every glyph a part of the host', glyphs - 1, Length(St(0, 1).Parts));
  AssertEquals('the other bar of P is not touched', '', StText(0, 0));
  AssertEquals('B blurred', 'blur', StText(1, 0));
  AssertTrue(HostOf(1, 0, b));
  AssertTrue('B at a tenth', Abs(b.Style.Alpha - 0.1) < 1e-12);
  FChart.Move(2, 2);
  Frame;
  after := Marks(0, 1);
  for k := 0 to High(after) do
    if after[k].Silent then
      AssertEquals('back at rest', Integer(before[k].Style.FillColor), Integer(after[k].Style.FillColor));
  AssertEquals('B back', '', StText(1, 0));
end;

{ A CANDLE IS ONE PATH upstream (NormalBoxPath): the wicks are drawn by the
  same element as the body, so they take its opacity, its paint order and
  its emphasis border width -- but not the body's lifted fill. }
procedure TAdvChartFocusBlurTest.TestCandleWicksFollowTheirBody;
var
  before, after: TFbElements;
  k, wicks: Integer;
begin
  Plain('{"animation":false,"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{"type":"value","scale":true},"series":[{"type":"candlestick","name":"K",'
    + '"data":[[20,30,10,35],[30,25,20,40]]},{"type":"bar","name":"B",'
    + '"emphasis":{"focus":"series"},"data":[22,24]}]}');
  before := Marks(0, 0);
  AssertEquals('a body and two wicks', 3, Length(before));
  HoverItem(1, 1);
  Frame;
  AssertEquals('K blurred by B', 'blur', StText(0, 0));
  after := Marks(0, 0);
  for k := 0 to High(after) do
    AssertTrue(Format('element %d at a tenth', [k]), Abs(after[k].Style.Alpha - 0.1) < 1e-12);
  FChart.Move(2, 2);
  Frame;
  HoverItem(0, 0);
  Frame;
  AssertEquals('hovered', 'emphasis', StText(0, 0));
  after := Marks(0, 0);
  wicks := 0;
  for k := 0 to High(after) do
  begin
    AssertEquals(Format('element %d climbed', [k]), before[k].Z2 + 10, after[k].Z2);
    AssertEquals(Format('element %d border 2', [k]), 2.0, after[k].Style.StrokeWidthLogical);
    if after[k].Anim.Role <> carCandleBody then
    begin
      Inc(wicks);
      AssertEquals('a wick keeps its stroke', Integer(before[k].Style.StrokeColor),
        Integer(after[k].Style.StrokeColor));
      AssertFalse('a wick has no fill', after[k].Style.HasFill);
    end
    else
      AssertEquals('the body lifts', Integer(TyChartLiftColor(before[k].Style.FillColor)),
        Integer(after[k].Style.FillColor));
  end;
  AssertEquals(2, wicks);
end;

{ blurSeries' coordinate system: a calendar is one -- a heatmap and a
  scatter on the same calendar blur together, a bar on the grid does not
  (and a calendar's series are on the state machine now). }
procedure TAdvChartFocusBlurTest.TestACalendarIsACoordinateSystem;
begin
  Plain('{"animation":false,"calendar":{"range":"2017-01","cellSize":[20,20],"top":40,"left":40},'
    + '"grid":{"top":260,"bottom":20},"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{"type":"value"},"visualMap":{"min":0,"max":10,"show":false,"seriesIndex":0},'
    + '"series":[{"type":"heatmap","name":"H","coordinateSystem":"calendar",'
    + '"emphasis":{"focus":"series"},"data":[["2017-01-02",5],["2017-01-10",8]]},'
    + '{"type":"scatter","name":"S","coordinateSystem":"calendar","symbolSize":8,'
    + '"data":[["2017-01-04",3],["2017-01-20",2]]},'
    + '{"type":"bar","name":"B","data":[3,4]}]}');
  HoverItem(0, 0);
  Frame;
  AssertEquals('the cell', 'emphasis', StText(0, 0));
  AssertEquals('H''s own series is spared (focus series)', '', StText(0, 1));
  AssertEquals('the scatter on the calendar blurs', 'blur', StText(1, 0));
  AssertEquals('the scatter on the calendar blurs', 'blur', StText(1, 1));
  AssertEquals('the bar on the grid does not', '', StText(2, 0));
end;

{ THE POLYLINE IS A DISPATCHER OF ITS OWN: hovering it puts it and -- through
  its onHoverStateChange -- the area in emphasis and blurs by the series'
  focus; no symbol enters. }
procedure TAdvChartFocusBlurTest.TestThePolylineAndTheAreaDispatchApart;
var pl, area: TTyStItem; s0, s1: TTyChartElement; mx, my: Integer;
begin
  Plain('{"animation":false,"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{"type":"value","max":40},"series":[{"type":"line","name":"L","areaStyle":{},'
    + '"emphasis":{"focus":"series"},"data":[10,30,20]},'
    + '{"type":"line","name":"M","data":[35,36,37]}]}');
  AssertTrue(HostOf(0, 0, s0));
  AssertTrue(HostOf(0, 1, s1));
  mx := Round((s0.Shape.CX + s1.Shape.CX) / 2);
  my := Round((s0.Shape.CY + s1.Shape.CY) / 2);
  FChart.Move(mx, my);
  Frame;
  AssertEquals('on the polyline', -1, FChart.HoverSeries);
  AssertTrue(FChart.LineStates(0, pl, area));
  AssertEquals('the polyline', 'emphasis', TyStNamesText(pl.Host.States));
  AssertEquals('the area follows it', 'emphasis', TyStNamesText(area.Host.States));
  AssertEquals('no symbol enters', '', StText(0, 0));
  AssertEquals('M blurred', 'blur', StText(1, 1));
  AssertTrue(FChart.LineStates(1, pl, area));
  AssertEquals('M''s polyline blurred', 'blur', TyStNamesText(pl.Host.States));
  { the area takes no pointer here (a known deviation): off the chart }
  FChart.Move(2, 2);
  Frame;
  AssertTrue(FChart.LineStates(0, pl, area));
  AssertEquals('the polyline left', '', TyStNamesText(pl.Host.States));
  AssertEquals('and the area with it', '', TyStNamesText(area.Host.States));
  AssertEquals('M back', '', StText(1, 1));
end;

{ blurSeriesFromHighlightPayload: the focus of the ELEMENT the payload names
  -- the item's own emphasis.focus over the series' -- and, when the payload
  names none that exists, of the first element there is. }
procedure TAdvChartFocusBlurTest.TestTheHighlightBlursByTheItemsOwnFocus;
begin
  Plain('{"animation":false,"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","name":"A","data":['
    + '{"value":5,"emphasis":{"focus":"series"}},6,7]},{"type":"bar","name":"B","data":[1,2,3]}]}');
  AssertTrue(FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":1}'));
  Frame;
  AssertEquals('item 1 has no focus: nothing blurs', '', StText(1, 0));
  AssertTrue(FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":0}'));
  Frame;
  AssertEquals('item 0''s focus series blurs B', 'blur', StText(1, 0));
  AssertTrue(FChart.DispatchAction('{"type":"downplay","seriesIndex":0}'));
  Frame;
  AssertEquals('a downplay leaves every blur first', '', StText(1, 0));
  { a name nobody has: the first element's focus }
  AssertTrue(FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"name":"nope"}'));
  Frame;
  AssertEquals('the first element''s focus', 'blur', StText(1, 2));
  AssertEquals('and nothing of A lights', '', StText(0, 0));
end;

{ the pointer leaving the canvas is a mouseout: allLeaveBlur }
procedure TAdvChartFocusBlurTest.TestLeavingTheCanvasLeavesTheBlur;
begin
  Plain('{"animation":false,"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","name":"A","emphasis":{"focus":"series"},'
    + '"data":[5,6]},{"type":"bar","name":"B","data":[1,2]}]}');
  HoverItem(0, 1);
  Frame;
  AssertEquals('blur', StText(1, 0));
  TFbCrack(TTyAdvanceChart(FChart)).MouseLeave;
  Frame;
  AssertEquals('left with the pointer', '', StText(1, 0));
  AssertEquals('', StText(0, 1));
end;

{ blur.label.opacity is the label's blur, not a tenth of it; the mark
  without blur.itemStyle.opacity takes the tenth }
procedure TAdvChartFocusBlurTest.TestADeclaredLabelBlurOpacityIsKept;
var lab, el: TTyChartElement;
begin
  Plain('{"animation":false,"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","name":"A","label":{"show":true},'
    + '"blur":{"label":{"opacity":0.5}},"data":[5,6]},{"type":"bar","name":"B",'
    + '"emphasis":{"focus":"series"},"data":[1,2]}]}');
  HoverItem(1, 1);
  Frame;
  AssertTrue(LabelOf(0, 0, lab));
  AssertTrue(HostOf(0, 0, el));
  AssertTrue('the declared label opacity', Abs(lab.Style.Alpha - 0.5) < 1e-12);
  AssertTrue('the mark at a tenth', Abs(el.Style.Alpha - 0.1) < 1e-12);
end;

{ LineView.highlight: a LIST of indices is the whole-series branch -- the
  groups take the bit (with the key's digit); downplay coerces a list of one
  to its number and so reaches the symbol path. }
procedure TAdvChartFocusBlurTest.TestALineHighlightListGoesToTheGroup;
var it: TTyStItem;
begin
  Plain('{"animation":false,"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"line","name":"L","data":[1,3,2]}]}');
  AssertTrue(FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":[1]}'));
  Frame;
  it := St(0, 1);
  AssertTrue('the group holds it', it.GroupHbo <> 0);
  AssertEquals('not the path', 0, Integer(it.Host.HighByOuter));
  AssertEquals('emphasis', TyStNamesText(it.Host.States));
  AssertTrue(FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":2}'));
  Frame;
  it := St(0, 2);
  AssertEquals('one index: the path', 0, Integer(it.GroupHbo));
  AssertTrue(it.Host.HighByOuter <> 0);
  AssertTrue(FChart.DispatchAction('{"type":"downplay","seriesIndex":0,"dataIndex":[2]}'));
  Frame;
  it := St(0, 2);
  AssertEquals('a list of one reaches the path', 0, Integer(it.Host.HighByOuter));
  AssertEquals('', TyStNamesText(it.Host.States));
  it := St(0, 1);
  AssertTrue('the group''s bit is not the path''s', it.GroupHbo <> 0);
end;

{ blurSeries walks the view group: the polyline is blurred as an element of
  its own, not only through a symbol's onHoverStateChange -- a line that
  draws no symbol is blurred all the same }
procedure TAdvChartFocusBlurTest.TestASymbollessLineBlursItsPolyline;
var pl, area: TTyStItem; el: TTyChartElement;
begin
  Plain('{"animation":false,"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","name":"A","emphasis":{"focus":"series"},'
    + '"data":[5,6,7]},{"type":"line","name":"L","showSymbol":false,"data":[9,9.5,9]}]}');
  HoverItem(0, 1);
  Frame;
  AssertTrue(FChart.LineStates(1, pl, area));
  AssertEquals('the polyline blurred', 'blur', TyStNamesText(pl.Host.States));
  AssertTrue(RunOf(1, el));
  AssertTrue('drawn at a tenth', Abs(el.Style.Alpha - 0.1 * pl.Host.Rest.Num[stkOpacity]) < 1e-12);
  FChart.Move(2, 2);
  Frame;
  AssertTrue(FChart.LineStates(1, pl, area));
  AssertEquals('and back', '', TyStNamesText(pl.Host.States));
end;

{ a heatmap's, a funnel's and a pictorial bar's select state is a border in
  tokens.color.primary (HeatmapSeries.ts:130, FunnelSeries.ts:200,
  PictorialBarSeries.ts:173) -- the skin's title ink here, as for a bar }
procedure TAdvChartFocusBlurTest.TestTheNewTypesTakeTheSelectBorder;
var el: TTyChartElement;
begin
  Plain('{"animation":false,"series":[{"type":"funnel","selectedMode":"single",'
    + '"data":[{"name":"a","value":3},{"name":"b","value":2}]}]}');
  AssertTrue(FChart.DispatchAction('{"type":"select","seriesIndex":0,"dataIndex":1}'));
  Frame;
  AssertEquals('select', StText(0, 1));
  AssertTrue(HostOf(0, 1, el));
  AssertEquals('the funnel''s border', Integer(FChart.Primary), Integer(el.Style.StrokeColor));
  Plain('{"animation":false,"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{"type":"category","data":["x"]},"visualMap":{"min":0,"max":3,"show":false},'
    + '"series":[{"type":"heatmap","selectedMode":"single","data":[[0,0,1],[1,0,2]]}]}');
  AssertTrue(FChart.DispatchAction('{"type":"select","seriesIndex":0,"dataIndex":0}'));
  Frame;
  AssertEquals('select', StText(0, 0));
  AssertTrue(HostOf(0, 0, el));
  AssertEquals('the cell''s border', Integer(FChart.Primary), Integer(el.Style.StrokeColor));
end;

initialization
  RegisterTest(TAdvChartFocusBlurTest);
end.
